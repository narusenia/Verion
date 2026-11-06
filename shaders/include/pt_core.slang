// Path tracing core shared by the megakernel (pathtrace.slang) and the wavefront kernels
// (wf_*.slang, REQ-GPU-005): bindings 0..17, the BSDF, and one path split into generate, trace,
// shade and finish, so both forms run the same code and the same random numbers.
// Flat word buffers only; layouts are documented next to each binding and mirrored in
// crates/verion-gpu-metal/src/renderer.rs. Kernels that include this file declare their own
// bindings after it (18 on).

#include "ggx_albedo.slang"
#include "sheen_albedo.slang"
#include "dielectric_albedo.slang"

RaytracingAccelerationStructure scene;
StructuredBuffer<float> positions;  // xyz per vertex, all meshes concatenated
StructuredBuffer<uint> indices;     // triangle vertex indices, all meshes concatenated
StructuredBuffer<uint> instances;   // 16 words: vertex offset, index offset, material, emitter base + 1 (0 = not emissive), 12 floats (row-major 3x4)
StructuredBuffer<float> materials;  // 22 words: base color rgb, emission rgb, metallic, roughness, transmission, ior,
                                    // base color / metallic-roughness / emission / normal texture + 1 (0 = none), normal scale,
                                    // clearcoat, clearcoat roughness, sheen roughness, sheen color rgb, dispersion
StructuredBuffer<uint> lights;      // 16 words: kind (0 point, 1 directional, 2 spot), color rgb, intensity, position or travel direction xyz,
                                    // spot axis xyz, spot falloff scale, spot falloff offset, 3 pad (floats as bits)
StructuredBuffer<uint> params;      // 0 width, 1 height, 2 tan(fov/2), 3 aperture radius, 4 focus distance (floats as bits),
                                    // 5 light count, 6 sample index, 7 max depth, 8..19 camera-to-world 3x4, 20..22 sky rgb, 23 emitter count, 24 env width (0 = none), 25 env height, 26 env pdf scale w*h / (2 pi^2 W), 27 pixel cone angle, 28 lighting AOV enable, 29 multiple-scattering compensation enable,
                                    // 30 / 31 wavefront depth and path count, 32 adaptive sampling enable, 33 adaptive threshold
                                    // (float), 34 adaptive minimum samples, 35 megakernel samples per dispatch, 36 ReSTIR DI enable,
                                    // 37 ReSTIR initial candidates per pixel, 38 ReSTIR history cap (samples a reused reservoir counts for)
RWStructuredBuffer<float> accum;    // running radiance sum, xyz per pixel
StructuredBuffer<float> emitters;   // 16 words per emissive world-space triangle: p0, p1, p2, radiance rgb, area, selection pdf, 2 pad
StructuredBuffer<float> emitCdf;    // cumulative selection probability per emitter triangle, last entry 1
StructuredBuffer<float> envPixels;  // environment map rgb per texel (scale applied), latitude-longitude, row-major from the top
StructuredBuffer<float> envMarginal; // cumulative probability per row of luminance * sin(theta), last entry 1
StructuredBuffer<float> envCond;    // cumulative probability per column within each row, last entry of each row 1
StructuredBuffer<float> uvs;        // uv per vertex, all meshes concatenated (zero when a mesh has none)
StructuredBuffer<float> texels;     // rgb texels, each texture's mip chain level 0 first
StructuredBuffer<uint> texInfo;     // 4 words per texture: texel offset, width, height, mip level count
StructuredBuffer<float> vnormals;   // xyz per vertex, all meshes concatenated (zero when a mesh has none)
RWStructuredBuffer<float> lighting; // used only when params[28] != 0; 65 floats per pixel, running sums of the first-hit
                                    // lighting split: direct diffuse, indirect diffuse, specular, transmission, emission (rgb each),
                                    // then lit and total direct-light luminance (visibility = lit / total), then 4 light slots of
                                    // 12 floats: sum of u (rgb), sum of lum(u), sum of lum(u) * r, sum of s (rgb), sum of
                                    // wd * wi (xyz), sum of wd * lit. u and s are a light's diffuse and specular contribution
                                    // divided by cos, r is cos * visibility, wi points toward the light, lit is 1 when the light
                                    // reaches the point, and wd = lum(u) + lum(s). The physical diffuse is u * r.
                                    // Slots 0..2 hold point / directional / spot lights by index (later ones share slot 2);
                                    // slot 3 holds emissive triangles and the environment map.
RWStructuredBuffer<float> pixelStats; // used only when params[32] != 0; 3 floats per pixel: samples taken, sum of
                                      // luminance, sum of squared luminance (adaptive sampling, REQ-ACC-007)

RWStructuredBuffer<float> restir;   // used only when params[36] != 0 (ReSTIR, REQ-ACC-002): 80 floats per pixel: two halves of
                                    // 28, the current frame's and the previous one's, swapped by sample parity, then 24 of scratch.
                                    // A half: 0 emitter + 1 (bits, 0 = none), 1..3 DI sample point, 4 DI contribution weight W,
                                    // 5 DI sample count M, 8..10 shading point, 11..13 shading normal, 14 usable as a neighbour
                                    // (bits, 1 or 0); GI: 16..18 the second hit's point, 19..21 its normal, 22..24 the radiance
                                    // leaving it toward the shading point, 25 W, 26 M, 27 valid (bits).
                                    // Scratch (GI, this frame): 0 resampled weight sum, 1 its count, 2 its target, 3..5 its contribution,
                                    // 6..8 point, 9..11 normal, 12..14 radiance, 15..17 throughput after the first bounce, 18..20 radiance
                                    // gathered at the first hit, 21 the first bounce's density, 22 the path hit a surface at depth 1 (bits)

static const float PI = 3.14159265358979;
static const uint LIGHTING_STRIDE = 65;
static const uint SLOT_WORDS = 12;

uint pcg(uint v)
{
    uint s = v * 747796405u + 2891336453u;
    uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
    return (w >> 22u) ^ w;
}

struct Rng
{
    uint state;
    [mutating] float next()
    {
        state = pcg(state);
        return float(state >> 8) * (1.0 / 16777216.0); // [0, 1)
    }
};

float pf(uint i) { return asfloat(params[i]); }

float3 vertexPos(uint v) { return float3(positions[3 * v], positions[3 * v + 1], positions[3 * v + 2]); }

float3 transformPoint(uint base, float3 p)
{
    float3 r;
    for (uint row = 0; row < 3; row++)
    {
        uint o = base + 4 * row;
        r[row] = asfloat(instances[o]) * p.x + asfloat(instances[o + 1]) * p.y + asfloat(instances[o + 2]) * p.z + asfloat(instances[o + 3]);
    }
    return r;
}

// Object-space normal to world space: inverse transpose of the 3x3 part, written with cofactors
// (rows of the inverse transpose are cross products of the other two rows, divided by det).
float3 transformNormal(uint base, float3 n)
{
    float3 r0 = float3(asfloat(instances[base]), asfloat(instances[base + 1]), asfloat(instances[base + 2]));
    float3 r1 = float3(asfloat(instances[base + 4]), asfloat(instances[base + 5]), asfloat(instances[base + 6]));
    float3 r2 = float3(asfloat(instances[base + 8]), asfloat(instances[base + 9]), asfloat(instances[base + 10]));
    float3 c0 = cross(r1, r2);
    float s = dot(r0, c0) < 0.0 ? -1.0 : 1.0; // a mirroring transform flips the cofactor direction
    return s * float3(dot(c0, n), dot(cross(r2, r0), n), dot(cross(r0, r1), n));
}

float3 vertexNormal(uint v) { return float3(vnormals[3 * v], vnormals[3 * v + 1], vnormals[3 * v + 2]); }

float3 cosineLocal(float u1, float u2)
{
    float r = sqrt(u1);
    float phi = 2.0 * PI * u2;
    return float3(r * cos(phi), r * sin(phi), sqrt(max(0.0, 1.0 - u1)));
}

float G1(float cosT, float alpha)
{
    float c2 = cosT * cosT;
    float tan2 = (1.0 - c2) / max(c2, 1.0e-8);
    return 2.0 / (1.0 + sqrt(1.0 + alpha * alpha * tan2));
}

float D(float hz, float alpha)
{
    float a2 = alpha * alpha;
    float d = hz * hz * (a2 - 1.0) + 1.0;
    return a2 / (PI * d * d);
}

float3 schlick(float3 f0, float c)
{
    float m = 1.0 - saturate(c);
    float m2 = m * m;
    return f0 + (1.0 - f0) * (m2 * m2 * m);
}

// Unpolarized dielectric Fresnel. eta = n_transmitted / n_incident; 1 at total internal reflection.
float fresnelDielectric(float cosi, float eta)
{
    float s2 = (1.0 - cosi * cosi) / (eta * eta);
    if (s2 >= 1.0)
        return 1.0;
    float cost = sqrt(1.0 - s2);
    float rs = (cosi - eta * cost) / (cosi + eta * cost);
    float rp = (eta * cosi - cost) / (eta * cosi + cost);
    return 0.5 * (rs * rs + rp * rp);
}

void basis(float3 n, out float3 t, out float3 b)
{
    float3 a = abs(n.x) > 0.9 ? float3(0, 1, 0) : float3(1, 0, 0);
    b = normalize(cross(n, a));
    t = cross(b, n);
}

// Visible-normal sampling of GGX (Heitz 2018) in the local frame (z = normal), wo.z > 0.
float3 sampleVndf(float3 wo, float alpha, float u1, float u2)
{
    float3 vh = normalize(float3(alpha * wo.x, alpha * wo.y, wo.z));
    float lensq = vh.x * vh.x + vh.y * vh.y;
    float3 t1 = lensq > 0.0 ? float3(-vh.y, vh.x, 0.0) * rsqrt(lensq) : float3(1, 0, 0);
    float3 t2 = cross(vh, t1);
    float r = sqrt(u1);
    float phi = 2.0 * PI * u2;
    float a = r * cos(phi);
    float b = r * sin(phi);
    float s = 0.5 * (1.0 + vh.z);
    b = (1.0 - s) * sqrt(1.0 - a * a) + s * b;
    float3 nh = a * t1 + b * t2 + sqrt(max(0.0, 1.0 - a * a - b * b)) * vh;
    return normalize(float3(alpha * nh.x, alpha * nh.y, max(0.0, nh.z)));
}



float lum(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// Adds one light's potential diffuse `u` and specular `s` (unshadowed, without cos), its direction `wi`,
// whether it reaches the point (`lit`) and the diffuse response `r` to its slot.
void addSlot(uint pixel, uint slot, float3 u, float3 s, float3 wi, float lit, float r)
{
    if (any(isnan(u)) || any(isinf(u)) || any(isnan(s)) || any(isinf(s)))
        return; // one bad sample must not poison the running sum
    uint o = LIGHTING_STRIDE * pixel + 17 + SLOT_WORDS * slot;
    float w = lum(u);
    float wd = w + lum(s);
    lighting[o] += u.x;
    lighting[o + 1] += u.y;
    lighting[o + 2] += u.z;
    lighting[o + 3] += w;
    lighting[o + 4] += w * r;
    lighting[o + 5] += s.x;
    lighting[o + 6] += s.y;
    lighting[o + 7] += s.z;
    lighting[o + 8] += wd * wi.x;
    lighting[o + 9] += wd * wi.y;
    lighting[o + 10] += wd * wi.z;
    lighting[o + 11] += wd * lit;
}

float3 envTexel(uint i, uint j)
{
    uint o = 3 * (j * params[24] + i);
    return float3(envPixels[o], envPixels[o + 1], envPixels[o + 2]);
}

// +y is up and the image center faces -z.
void envCoords(float3 d, out uint i, out uint j)
{
    uint w = params[24];
    uint h = params[25];
    float u = atan2(d.x, -d.z) * (0.5 / PI) + 0.5;
    float v = acos(clamp(d.y, -1.0, 1.0)) / PI;
    i = min(uint(u * w), w - 1);
    j = min(uint(v * h), h - 1);
}

float3 envRadiance(float3 d)
{
    uint i, j;
    envCoords(d, i, j);
    return envTexel(i, j);
}

// Solid-angle density of sampling direction d: the sin(theta) of the lat-long Jacobian cancels
// against the sin(theta) weight of the distribution.
float envPdf(float3 d)
{
    uint i, j;
    envCoords(d, i, j);
    return lum(envTexel(i, j)) * pf(26);
}

float3 envSample(float u1, float u2, float u3, float u4, out float pdf, out float3 le)
{
    uint w = params[24];
    uint h = params[25];
    uint lo = 0;
    uint hi = h - 1;
    while (lo < hi)
    {
        uint mid = (lo + hi) / 2;
        if (envMarginal[mid] >= u1)
            hi = mid;
        else
            lo = mid + 1;
    }
    uint j = lo;
    lo = 0;
    hi = w - 1;
    while (lo < hi)
    {
        uint mid = (lo + hi) / 2;
        if (envCond[j * w + mid] >= u2)
            hi = mid;
        else
            lo = mid + 1;
    }
    uint i = lo;
    float phi = ((i + u3) / w - 0.5) * 2.0 * PI;
    float theta = ((j + u4) / h) * PI;
    float st = sin(theta);
    le = envTexel(i, j);
    pdf = lum(le) * pf(26);
    return float3(st * sin(phi), cos(theta), -st * cos(phi));
}


float3 texelAt(uint base, uint w, uint h, int x, int y)
{
    uint xi = uint(((x % int(w)) + int(w)) % int(w));
    uint yi = uint(((y % int(h)) + int(h)) % int(h));
    uint o = 3 * (base + yi * w + xi);
    return float3(texels[o], texels[o + 1], texels[o + 2]);
}

float3 bilinear(uint base, uint w, uint h, float2 uv)
{
    float fx = uv.x * w - 0.5;
    float fy = uv.y * h - 0.5;
    int x0 = int(floor(fx));
    int y0 = int(floor(fy));
    float tx = fx - x0;
    float ty = fy - y0;
    float3 a = lerp(texelAt(base, w, h, x0, y0), texelAt(base, w, h, x0 + 1, y0), tx);
    float3 b = lerp(texelAt(base, w, h, x0, y0 + 1), texelAt(base, w, h, x0 + 1, y0 + 1), tx);
    return lerp(a, b, ty);
}

// Repeat-wrapped trilinear lookup. `footprint` is the width of the ray cone in uv units.
float3 sampleTexture(uint tex, float2 uv, float footprint)
{
    uint ti = tex * 4;
    uint base = texInfo[ti];
    uint w = texInfo[ti + 1];
    uint h = texInfo[ti + 2];
    uint levels = texInfo[ti + 3];
    float lod = clamp(log2(max(footprint * float(max(w, h)), 1.0e-8)), 0.0, float(levels - 1));
    uint l0 = uint(floor(lod));
    float t = lod - float(l0);
    uint off = base;
    uint lw = w;
    uint lh = h;
    for (uint k = 0; k < l0; k++)
    {
        off += lw * lh;
        lw = max(lw / 2, 1u);
        lh = max(lh / 2, 1u);
    }
    float3 a = bilinear(off, lw, lh, uv);
    if (l0 + 1 >= levels || t <= 0.0)
        return a;
    off += lw * lh;
    float3 b = bilinear(off, max(lw / 2, 1u), max(lh / 2, 1u), uv);
    return lerp(a, b, t);
}

struct Surface
{
    float3 albedo;
    float metallic;
    float alpha;
    float transmission;
    float ior;
    float eta;  // relative index n_transmitted / n_incident on the viewer's side
    float fSel; // chance the dielectric base lobe reflects specularly
    float tComp; // multiple-scattering compensation of rough transmission (1 = off)
    float coat;      // clear coat strength, 0 = none
    float coatAlpha; // GGX alpha of the coat
    float3 sheenColor;
    float sheenAlpha;
    float sheenP;    // chance the sampler takes the sheen lobe: max(sheenColor) * E(view); the base keeps 1 - sheenP
    float coatP;     // chance the sampler takes the coat lobe: coat * Fresnel at the view angle; the base keeps 1 - coatP
};

struct Lobes
{
    float3 diffuse;
    float3 specular;
};

// Single-scattering GGX directional albedo E(cos wo, alpha) for F = 1, bilinear in the generated
// table (indexed by sqrt(alpha) and cos wo).
float ggxAlbedo(float cosO, float alpha)
{
    float x = saturate(cosO) * (GGX_ALBEDO_N - 1);
    float y = saturate(sqrt(alpha)) * (GGX_ALBEDO_N - 1);
    uint x0 = min(uint(x), GGX_ALBEDO_N - 2);
    uint y0 = min(uint(y), GGX_ALBEDO_N - 2);
    float fx = x - x0;
    float fy = y - y0;
    float a = lerp(GGX_ALBEDO[y0 * GGX_ALBEDO_N + x0], GGX_ALBEDO[y0 * GGX_ALBEDO_N + x0 + 1], fx);
    float b = lerp(GGX_ALBEDO[(y0 + 1) * GGX_ALBEDO_N + x0], GGX_ALBEDO[(y0 + 1) * GGX_ALBEDO_N + x0 + 1], fx);
    return lerp(a, b, fy);
}

// Energy a rough metal's single-scattering GGX loses to light that bounces between microfacets:
// the specular lobe is scaled by 1 + F0 * (1 / E(cos wo) - 1), which restores a white furnace to 1
// for F = 1 (Fdez-Aguera 2019). Depends on the view direction only, so it is not reciprocal.
// 1 when the compensation is off.
float3 multiscatterFactor(Surface s, float cosO)
{
    if (params[29] == 0)
        return float3(1.0);
    return 1.0 + s.albedo * (1.0 / max(ggxAlbedo(cosO, s.alpha), 0.05) - 1.0);
}

// Single-scattering albedo of a rough dielectric interface (reflection plus transmission), trilinear in
// the generated table over (cos wo, roughness, ior), for a path entering (`outside`) or leaving the medium.
float dielectricAlbedo(float cosO, float rough, float ior, bool outside)
{
    float x = saturate(cosO) * (DIEL_ALBEDO_N - 1);
    float y = saturate(rough) * (DIEL_ALBEDO_N - 1);
    float z = clamp((ior - 1.0) * 4.0, 0.0, float(DIEL_ALBEDO_N_IOR - 1) - 1.0e-3);
    uint x0 = min(uint(x), DIEL_ALBEDO_N - 2);
    uint y0 = min(uint(y), DIEL_ALBEDO_N - 2);
    uint z0 = uint(z);
    float fx = x - x0;
    float fy = y - y0;
    float fz = z - z0;
    uint base = (outside ? 0 : DIEL_ALBEDO_N_IOR) * DIEL_ALBEDO_N * DIEL_ALBEDO_N;
    float c[2];
    for (uint k = 0; k < 2; k++)
    {
        uint o = base + ((z0 + k) * DIEL_ALBEDO_N + y0) * DIEL_ALBEDO_N + x0;
        float a = lerp(DIEL_ALBEDO[o], DIEL_ALBEDO[o + 1], fx);
        float b = lerp(DIEL_ALBEDO[o + DIEL_ALBEDO_N], DIEL_ALBEDO[o + DIEL_ALBEDO_N + 1], fx);
        c[k] = lerp(a, b, fy);
    }
    return lerp(c[0], c[1], fz);
}

// Directional albedo of the sheen lobe (color 1), bilinear in the generated table (r, cos wo).
float sheenAlbedo(float cosO, float r)
{
    float x = saturate(cosO) * (SHEEN_ALBEDO_N - 1);
    float y = saturate(r) * (SHEEN_ALBEDO_N - 1);
    uint x0 = min(uint(x), SHEEN_ALBEDO_N - 2);
    uint y0 = min(uint(y), SHEEN_ALBEDO_N - 2);
    float fx = x - x0;
    float fy = y - y0;
    float a = lerp(SHEEN_ALBEDO[y0 * SHEEN_ALBEDO_N + x0], SHEEN_ALBEDO[y0 * SHEEN_ALBEDO_N + x0 + 1], fx);
    float b = lerp(SHEEN_ALBEDO[(y0 + 1) * SHEEN_ALBEDO_N + x0], SHEEN_ALBEDO[(y0 + 1) * SHEEN_ALBEDO_N + x0 + 1], fx);
    return lerp(a, b, fy);
}

// Sheen BRDF times cos(wi): the Charlie distribution (Estevez and Kulla) with the Neubelt visibility,
// as in KHR_materials_sheen. Color is the caller's.
float sheenCore(float woz, float wiz, float hz, float alpha)
{
    float sinH = sqrt(max(1.0 - hz * hz, 0.0));
    float d = (2.0 + 1.0 / alpha) * pow(sinH, 1.0 / alpha) / (2.0 * PI);
    float v = 1.0 / (4.0 * (wiz + woz - wiz * woz));
    return d * v * wiz;
}

// f * cos(wi) of the reflective lobes, split into the diffuse base and the specular lobes.
// Rough transmission is not included.
Lobes evalLobes(Surface s, float3 woL, float3 wiL)
{
    float3 hh = normalize(woL + wiL);
    float woh = max(dot(woL, hh), 0.0);
    // The cosine cancels against the 1 / (4 cos wi cos wo) of the microfacet BRDF.
    float core = D(hh.z, s.alpha) * G1(woL.z, s.alpha) * G1(wiL.z, s.alpha) / (4.0 * woL.z);
    float t = s.transmission;
    Lobes l;
    l.specular = s.metallic * schlick(s.albedo, woh) * multiscatterFactor(s, woL.z) * core
        + (1.0 - s.metallic) * (t * fresnelDielectric(woh, s.eta) * s.tComp + (1.0 - t) * fresnelDielectric(woh, s.ior)) * core;
    l.diffuse = (1.0 - s.metallic) * (1.0 - t) * (1.0 - s.fSel) * s.albedo * (wiL.z / PI);
    // Layers, outermost last: base, sheen scaled so the pair keeps energy, then the coat.
    if (s.sheenP > 0.0)
    {
        l.specular = (1.0 - s.sheenP) * l.specular + s.sheenColor * sheenCore(woL.z, wiL.z, hh.z, s.sheenAlpha);
        l.diffuse *= 1.0 - s.sheenP;
    }
    if (s.coat > 0.0)
    {
        // Clear coat (IOR 1.5): the base loses what the coat reflects at the view angle, and the coat
        // adds its own GGX lobe. shortcut: no refraction or absorption inside the coat, no coat
        // multiple scattering; upgrade when a layered BSDF is needed.
        float coreC = D(hh.z, s.coatAlpha) * G1(woL.z, s.coatAlpha) * G1(wiL.z, s.coatAlpha) / (4.0 * woL.z);
        l.specular = (1.0 - s.coatP) * l.specular + s.coat * fresnelDielectric(woh, 1.5) * coreC;
        l.diffuse *= 1.0 - s.coatP;
    }
    return l;
}

float3 evalReflective(Surface s, float3 woL, float3 wiL)
{
    Lobes l = evalLobes(s, woL, wiL);
    return l.specular + l.diffuse;
}

// Radiance split by what produced it (REQ-STY-006). Indirect light is filed under the lobe the
// path took at its first bounce; `total` is the beauty and is the sum of the parts.
struct Parts
{
    float3 total;
    float3 directDiffuse;
    float3 indirectDiffuse;
    float3 specular;
    float3 transmission;
    float3 emission;

    // Light reached by emission or the sky: seen directly, or through the first bounce's lobe.
    [mutating] void add(uint depth, uint cls, float3 c)
    {
        total += c;
        file(depth, cls, c);
    }

    // Next-event estimate with its diffuse and specular halves (c is their sum).
    [mutating] void addLight(uint depth, uint cls, float3 c, float3 cd, float3 cs)
    {
        total += c;
        if (depth == 0)
        {
            directDiffuse += cd;
            specular += cs;
        }
        else
            file(depth, cls, cd + cs);
    }

    [mutating] void file(uint depth, uint cls, float3 c)
    {
        if (depth == 0)
            emission += c;
        else if (cls == 0)
            indirectDiffuse += c;
        else if (cls == 1)
            specular += c;
        else
            transmission += c;
    }
};

// Density of choosing wiL through the reflective lobes of the sampler below. Used for MIS only:
// NEE and BSDF sampling share this function, so an approximate value still gives an unbiased image.
float reflectivePdf(Surface s, float3 woL, float3 wiL)
{
    float3 hh = normalize(woL + wiL);
    float woh = max(dot(woL, hh), 0.0);
    float spec = G1(woL.z, s.alpha) * D(hh.z, s.alpha) / (4.0 * woL.z); // visible-normal reflection pdf
    float t = s.transmission;
    float pSpec = s.metallic + (1.0 - s.metallic) * (t * fresnelDielectric(woh, s.eta) + (1.0 - t) * s.fSel);
    float pDiff = (1.0 - s.metallic) * (1.0 - t) * (1.0 - s.fSel) * wiL.z / PI;
    float q = pSpec * spec + pDiff;
    if (s.sheenP > 0.0)
        q = (1.0 - s.sheenP) * q + s.sheenP * wiL.z / PI; // the sheen lobe is sampled by cosine
    if (s.coat > 0.0)
    {
        float specC = G1(woL.z, s.coatAlpha) * D(hh.z, s.coatAlpha) / (4.0 * woL.z);
        q = (1.0 - s.coatP) * q + s.coatP * specC;
    }
    return q;
}

bool occluded(float3 o, float3 d, float tmax)
{
    RayDesc ray;
    ray.Origin = o;
    ray.Direction = d;
    ray.TMin = 0.0;
    ray.TMax = tmax;
    RayQuery<RAY_FLAG_FORCE_OPAQUE | RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH> q;
    q.TraceRayInline(scene, 0, 0xFF, ray);
    while (q.Proceed()) { }
    return q.CommittedStatus() == COMMITTED_TRIANGLE_HIT;
}

// Everything one path carries between bounces.
struct PathState
{
    float3 org;
    float3 dir;
    float3 thr;
    uint rng;
    uint cls;      // lobe class of the first bounce: 0 diffuse, 1 specular, 2 transmission
    int chan;      // color channel this path follows after its first dispersive hit, -1 until then
    float pathLen; // distance travelled so far, widens the texture-filter cone
    bool misPrev;  // the previous bounce was a reflection that light sampling also covers
    bool gi;       // the first hit takes part in ReSTIR GI: the rest of the path is resampled when it ends
    bool restir;   // the first hit took its emitter sample from ReSTIR: light sampling then has probability 1 at the next hit
    float qPrev;   // its density
    float visLit;
    float visTotal;
    Parts parts;
};

// The closest hit of a ray; `hit` is false on a miss.
struct Hit
{
    bool hit;
    uint inst;
    uint prim;
    float t;
};

// Thin-lens camera ray with a jittered pixel position, for sample `sample`.
PathState generatePathFor(uint px, uint py, uint sample)
{
    uint w = params[0];
    uint h = params[1];
    uint pixel = py * w + px;
    Rng rng;
    rng.state = pcg(pixel ^ pcg(sample * 0x9E3779B9u + 0x7F4A7C15u));
    float t = pf(2);
    float aspect = float(w) / float(h);
    float u = (2.0 * (px + rng.next()) / w - 1.0) * aspect * t;
    float v = (1.0 - 2.0 * (py + rng.next()) / h) * t;
    float3 focal = float3(u, v, -1.0) * pf(4);
    float lensR = pf(3) * sqrt(rng.next());
    float lensA = 2.0 * PI * rng.next();
    float3 lens = float3(lensR * cos(lensA), lensR * sin(lensA), 0.0);
    float3 dc = normalize(focal - lens);
    PathState s;
    for (uint r = 0; r < 3; r++)
    {
        s.org[r] = asfloat(params[8 + 4 * r]) * lens.x + asfloat(params[9 + 4 * r]) * lens.y + asfloat(params[10 + 4 * r]) * lens.z + asfloat(params[11 + 4 * r]);
        s.dir[r] = asfloat(params[8 + 4 * r]) * dc.x + asfloat(params[9 + 4 * r]) * dc.y + asfloat(params[10 + 4 * r]) * dc.z;
    }
    s.dir = normalize(s.dir);
    s.thr = float3(1.0);
    s.rng = rng.state;
    s.cls = 0;
    s.chan = -1;
    s.pathLen = 0.0;
    s.misPrev = false;
    s.restir = false;
    s.gi = false;
    s.qPrev = 0.0;
    s.visLit = 0.0;
    s.visTotal = 0.0;
    s.parts = (Parts)0;
    return s;
}

Hit traceClosest(float3 org, float3 dir)
{
    RayDesc ray;
    ray.Origin = org;
    ray.Direction = dir;
    ray.TMin = 0.0;
    ray.TMax = 1.0e30;
    RayQuery<RAY_FLAG_FORCE_OPAQUE> q;
    q.TraceRayInline(scene, 0, 0xFF, ray);
    while (q.Proceed()) { }
    Hit h;
    h.hit = q.CommittedStatus() == COMMITTED_TRIANGLE_HIT;
    h.inst = h.hit ? q.CommittedInstanceIndex() : 0;
    h.prim = h.hit ? q.CommittedPrimitiveIndex() : 0;
    h.t = h.hit ? q.CommittedRayT() : 0.0;
    return h;
}

// ReSTIR DI (REQ-ACC-002, ADR-0016). Surfaces rougher than this take emitter samples from
// reservoirs; sharper ones keep light sampling with BSDF MIS, which resolves their highlights better.
static const float RESTIR_MIN_ALPHA = 0.15;
static const int RESTIR_RADIUS = 6;   // pixels, for the neighbours of the previous frame
static const uint RESTIR_NEIGHBOURS = 2;

static const uint RESTIR_HALF = 28;
static const uint RESTIR_STRIDE = 80;
static const float RESTIR_MAX_JACOBIAN = 10.0;

uint restirBase(uint pixel, uint which) { return pixel * RESTIR_STRIDE + which * RESTIR_HALF; }
uint restirScratch(uint pixel) { return pixel * RESTIR_STRIDE + 2 * RESTIR_HALF; }

// The light arriving from point `x` of emitter `e` at `p` without the BSDF: Le cos(light) / d^2,
// and the density plain light sampling has for it.
// False when the point is behind the surface or the light faces away.
bool restirLight(uint e, float3 x, float3 p, float3 n, out float3 wi, out float dist, out float cosi, out float3 g, out float plsa)
{
    uint o = e * 16;
    float3 a = float3(emitters[o], emitters[o + 1], emitters[o + 2]);
    float3 b = float3(emitters[o + 3], emitters[o + 4], emitters[o + 5]);
    float3 c = float3(emitters[o + 6], emitters[o + 7], emitters[o + 8]);
    float3 toL = x - p;
    float d2 = dot(toL, toL);
    dist = sqrt(d2);
    wi = toL / max(dist, 1.0e-6);
    float cosl = abs(dot(normalize(cross(b - a, c - a)), wi));
    cosi = dot(n, wi);
    g = float3(emitters[o + 9], emitters[o + 10], emitters[o + 11]) * (cosl / max(d2, 1.0e-12));
    // Density per solid angle of drawing this point by emitted power: what the BSDF-sampled hits
    // on emitters are weighed against, as in plain light sampling.
    plsa = emitters[o + 13] * d2 / (max(emitters[o + 12], 1.0e-30) * max(cosl, 1.0e-5));
    return cosi > 0.0 && cosl > 1.0e-5 && d2 > 1.0e-12;
}

// Power-heuristic weight of the light-sampling strategy, which the BSDF-sampled hits on emitters complement.
float restirMis(Surface surf, float3 woL, float3 wiL, float plsa)
{
    float qb = reflectivePdf(surf, woL, wiL);
    return plsa * plsa / max(plsa * plsa + qb * qb, 1.0e-30);
}

struct RestirPick
{
    bool valid;   // a sample was chosen
    uint e;       // its emitter
    float3 x;     // its point
    float W;      // contribution weight: the unshadowed, MIS-weighted contribution times W estimates the direct light
    bool occ;     // the chosen sample is hidden from the shading point
};

// Resamples the emitter light of the first hit: initial candidates by emitted power, then the
// pixel's reservoir and a few neighbours' from the previous frame. One shadow ray tests the
// winner, and a hidden winner is stored with weight 0 so shadows do not spread. The reuse takes
// the previous reservoirs without a visibility test of their own, so it is biased near shadow
// edges; the image is marked non-physical (ADR-0016).
RestirPick restirDI(uint pixel, float3 p, float3 n, float pHitT, Surface surf, float3 T, float3 B, float3 woL, inout Rng rng)
{
    uint w = params[0];
    uint cur = params[6] & 1u;
    uint emitterCount = params[23];
    float cap = float(max(params[38], 1u));
    float wsum = 0.0;
    float mTotal = 0.0;
    uint selE = 0;
    float3 selX = float3(0.0);
    float selPhat = 0.0;
    for (uint k = 0; k < max(params[37], 1u); k++)
    {
        float ue = rng.next();
        float ua = rng.next();
        float ub = rng.next();
        uint lo = 0;
        uint hi = emitterCount - 1;
        while (lo < hi)
        {
            uint mid = (lo + hi) / 2;
            if (emitCdf[mid] >= ue)
                hi = mid;
            else
                lo = mid + 1;
        }
        uint o = lo * 16;
        float3 a = float3(emitters[o], emitters[o + 1], emitters[o + 2]);
        float3 b = float3(emitters[o + 3], emitters[o + 4], emitters[o + 5]);
        float3 c = float3(emitters[o + 6], emitters[o + 7], emitters[o + 8]);
        float su = sqrt(ua);
        float3 x = a * (1.0 - su) + b * (su * (1.0 - ub)) + c * (su * ub);
        float area = emitters[o + 12];
        float q = area > 0.0 ? emitters[o + 13] / area : 0.0; // density per unit area
        float3 wi, g;
        float dist, cosi, plsa;
        float phat = 0.0;
        if (q > 0.0 && restirLight(lo, x, p, n, wi, dist, cosi, g, plsa))
        {
            float3 wiL = float3(dot(wi, T), dot(wi, B), cosi);
            phat = lum(evalReflective(surf, woL, wiL) * g) * restirMis(surf, woL, wiL, plsa);
        }
        float wgt = phat / max(q, 1.0e-30);
        mTotal += 1.0;
        if (phat > 0.0)
        {
            wsum += wgt;
            if (rng.next() * wsum < wgt)
            {
                selE = lo + 1;
                selX = x;
                selPhat = phat;
            }
        }
    }
    if (params[6] > 0)
    {
        int px = int(pixel % w);
        int py = int(pixel / w);
        for (uint k = 0; k < 1 + RESTIR_NEIGHBOURS; k++)
        {
            int nx = px;
            int ny = py;
            if (k > 0)
            {
                nx += int(rng.next() * float(2 * RESTIR_RADIUS + 1)) - RESTIR_RADIUS;
                ny += int(rng.next() * float(2 * RESTIR_RADIUS + 1)) - RESTIR_RADIUS;
                if (nx < 0 || ny < 0 || nx >= int(w) || ny >= int(params[1]))
                    continue;
            }
            uint ro = restirBase(uint(ny) * w + uint(nx), cur ^ 1u);
            uint ei = asuint(restir[ro]);
            if (asuint(restir[ro + 14]) == 0 || ei == 0)
                continue;
            float3 pn = float3(restir[ro + 11], restir[ro + 12], restir[ro + 13]);
            float3 pp = float3(restir[ro + 8], restir[ro + 9], restir[ro + 10]);
            if (dot(pn, n) < 0.9 || length(pp - p) > 0.05 * max(pHitT, 0.01))
                continue;
            float3 xc = float3(restir[ro + 1], restir[ro + 2], restir[ro + 3]);
            float mc = min(restir[ro + 5], cap);
            float3 wi, g;
            float dist, cosi, plsa;
            float phat = 0.0;
            if (restirLight(ei - 1, xc, p, n, wi, dist, cosi, g, plsa))
            {
                float3 wiL = float3(dot(wi, T), dot(wi, B), cosi);
                phat = lum(evalReflective(surf, woL, wiL) * g) * restirMis(surf, woL, wiL, plsa);
            }
            float wgt = phat * restir[ro + 4] * mc;
            mTotal += mc;
            if (wgt > 0.0)
            {
                wsum += wgt;
                if (rng.next() * wsum < wgt)
                {
                    selE = ei;
                    selX = xc;
                    selPhat = phat;
                }
            }
        }
    }
    RestirPick r;
    r.valid = selE != 0 && selPhat > 0.0;
    r.e = selE;
    r.x = selX;
    r.W = r.valid ? wsum / (mTotal * selPhat) : 0.0;
    r.occ = false;
    if (r.valid)
    {
        float3 wi, g;
        float dist, cosi, plsa;
        restirLight(selE - 1, selX, p, n, wi, dist, cosi, g, plsa);
        r.occ = occluded(p, wi, dist * (1.0 - 1.0e-3));
    }
    uint co = restirBase(pixel, cur);
    restir[co] = asfloat(selE);
    restir[co + 1] = selX.x;
    restir[co + 2] = selX.y;
    restir[co + 3] = selX.z;
    restir[co + 4] = r.occ ? 0.0 : r.W;
    restir[co + 5] = mTotal;
    return r;
}

// The shading point other pixels compare their own with before reusing this pixel's samples.
void restirGbuffer(uint pixel, float3 p, float3 n)
{
    uint co = restirBase(pixel, params[6] & 1u);
    restir[co + 8] = p.x;
    restir[co + 9] = p.y;
    restir[co + 10] = p.z;
    restir[co + 11] = n.x;
    restir[co + 12] = n.y;
    restir[co + 13] = n.z;
    restir[co + 14] = asfloat(1u);
}

// ReSTIR GI, first half (REQ-ACC-002): the previous frame's second-hit samples of this pixel and
// its neighbours, moved to this shading point (reconnection: the sample keeps its point and
// radiance, and its weight follows the change of solid angle). A candidate must see the point.
// The pixel's own path adds its candidate when it ends (`finishGI`).
void restirGIPrepare(uint pixel, float3 p, float3 n, float pHitT, Surface surf, float3 T, float3 B, float3 woL, inout Rng rng)
{
    uint w = params[0];
    uint cur = params[6] & 1u;
    float cap = float(max(params[38], 1u));
    float wsum = 0.0;
    float mTotal = 0.0;
    float pSel = 0.0;
    float3 cSel = float3(0.0);
    float3 xSel = float3(0.0);
    float3 nSel = float3(0.0);
    float3 lSel = float3(0.0);
    if (params[6] > 0)
    {
        int px = int(pixel % w);
        int py = int(pixel / w);
        for (uint k = 0; k < 1 + RESTIR_NEIGHBOURS; k++)
        {
            int nx = px;
            int ny = py;
            if (k > 0)
            {
                nx += int(rng.next() * float(2 * RESTIR_RADIUS + 1)) - RESTIR_RADIUS;
                ny += int(rng.next() * float(2 * RESTIR_RADIUS + 1)) - RESTIR_RADIUS;
                if (nx < 0 || ny < 0 || nx >= int(w) || ny >= int(params[1]))
                    continue;
            }
            uint ro = restirBase(uint(ny) * w + uint(nx), cur ^ 1u);
            if (asuint(restir[ro + 14]) == 0 || asuint(restir[ro + 27]) == 0)
                continue;
            float3 pq = float3(restir[ro + 8], restir[ro + 9], restir[ro + 10]);
            float3 nq = float3(restir[ro + 11], restir[ro + 12], restir[ro + 13]);
            if (dot(nq, n) < 0.9 || length(pq - p) > 0.05 * max(pHitT, 0.01))
                continue;
            float3 x2 = float3(restir[ro + 16], restir[ro + 17], restir[ro + 18]);
            float3 n2 = float3(restir[ro + 19], restir[ro + 20], restir[ro + 21]);
            float3 l2 = float3(restir[ro + 22], restir[ro + 23], restir[ro + 24]);
            float mq = min(restir[ro + 26], cap);
            mTotal += mq;
            float3 toX = x2 - p;
            float dR = length(toX);
            float3 wi = toX / max(dR, 1.0e-6);
            float dQ = length(x2 - pq);
            float cosT = dot(n, wi);
            float cosR = abs(dot(n2, wi));
            float cosQ = abs(dot(n2, normalize(pq - x2)));
            if (cosT <= 0.0 || dR < 1.0e-3 || cosR < 1.0e-3 || cosQ < 1.0e-3)
                continue;
            float jac = (cosR / cosQ) * (dQ * dQ) / (dR * dR);
            if (jac > RESTIR_MAX_JACOBIAN || jac < 1.0 / RESTIR_MAX_JACOBIAN)
                continue;
            float3 c = evalReflective(surf, woL, float3(dot(wi, T), dot(wi, B), cosT)) * l2;
            float phat = lum(c);
            if (phat <= 0.0 || occluded(p, wi, dR * (1.0 - 1.0e-3)))
                continue;
            float wgt = phat * restir[ro + 25] * mq * jac;
            wsum += wgt;
            if (rng.next() * wsum < wgt)
            {
                pSel = phat;
                cSel = c;
                xSel = x2;
                nSel = n2;
                lSel = l2;
            }
        }
    }
    uint so = restirScratch(pixel);
    restir[so] = wsum;
    restir[so + 1] = mTotal;
    restir[so + 2] = pSel;
    for (uint k = 0; k < 3; k++)
    {
        restir[so + 3 + k] = cSel[k];
        restir[so + 6 + k] = xSel[k];
        restir[so + 9 + k] = nSel[k];
        restir[so + 12 + k] = lSel[k];
    }
    restir[so + 22] = asfloat(0u);
}

// A pixel that takes no ReSTIR sample this frame must not look like a neighbour to the next one.
void restirClear(uint pixel)
{
    uint co = restirBase(pixel, params[6] & 1u);
    restir[co + 14] = asfloat(0u);
    restir[co + 27] = asfloat(0u);
}

// One bounce at `depth`: the miss or the hit's emission, light sampling and the next direction.
// Returns false when the path ends here.
bool shadePath(inout PathState st, Hit hq, uint depth, uint pixel)
{
    float3 sky = float3(pf(20), pf(21), pf(22));
    bool lightingOn = params[28] != 0;
    uint lightCount = params[5];
    uint emitterCount = params[23];
    bool hasEnv = params[24] > 0;
    // Probability that next-event estimation samples the environment map instead of an emitter.
    float pEnv = hasEnv ? (emitterCount > 0 ? 0.5 : 1.0) : 0.0;
    Rng rng;
    rng.state = st.rng;
    float3 org = st.org;
    float3 dir = st.dir;
    float3 thr = st.thr;
    uint cls = st.cls;
    int chan = st.chan;
    bool alive = true;
    for (uint once = 0; once < 1; once++) // `break` ends the path, as in the megakernel's loop
    {
        if (!hq.hit)
        {
            if (depth == 0 && params[36] != 0)
                restirClear(pixel);
            // Uniform sky is reached by cosine sampling, so it needs no light sampling.
            st.parts.add(depth, cls, thr * sky);
            if (hasEnv)
            {
                float wB = 1.0;
                if (st.misPrev)
                {
                    float pl = (st.restir && depth == 1 ? 1.0 : pEnv) * envPdf(dir);
                    float den = st.qPrev * st.qPrev + pl * pl;
                    wB = den > 0.0 ? st.qPrev * st.qPrev / den : 1.0;
                }
                st.parts.add(depth, cls, thr * envRadiance(dir) * wB);
            }
            { alive = false; break; }
        }

        uint inst = hq.inst * 16;
        uint tri = instances[inst + 1] + 3 * hq.prim;
        uint vo = instances[inst];
        float3 p0 = transformPoint(inst + 4, vertexPos(indices[tri] + vo));
        float3 p1 = transformPoint(inst + 4, vertexPos(indices[tri + 1] + vo));
        float3 p2 = transformPoint(inst + 4, vertexPos(indices[tri + 2] + vo));
        // Winding gives the outward normal (glTF is counter-clockwise); `ng` faces the viewer.
        float3 nOut = normalize(cross(p1 - p0, p2 - p0));
        float3 wo = -dir;
        bool outside = dot(nOut, wo) > 0.0;
        float3 ng = outside ? nOut : -nOut;
        float pHitT = hq.t;
        st.pathLen += pHitT;
        float3 hit = org + dir * pHitT;
        // shortcut: fixed 1e-4 ray offset assumes unit-scale scenes, scale it with scene bounds later.
        float3 p = hit + ng * 1.0e-4;
        if (depth == 1 && st.gi)
        {
            // The first bounce reached a surface: its point and facing normal are ReSTIR GI's candidate.
            uint co = restirBase(pixel, params[6] & 1u);
            for (uint k = 0; k < 3; k++)
            {
                restir[co + 16 + k] = hit[k];
                restir[co + 19 + k] = ng[k];
            }
            restir[restirScratch(pixel) + 22] = asfloat(1u);
        }

        // Barycentric weights of vertices 1 and 2 at the hit.
        float3 e1 = p1 - p0;
        float3 e2 = p2 - p0;
        float3 e3 = hit - p0;
        float d11 = dot(e1, e1);
        float d12 = dot(e1, e2);
        float d22 = dot(e2, e2);
        float den = max(d11 * d22 - d12 * d12, 1.0e-20);
        float b1 = (d22 * dot(e3, e1) - d12 * dot(e3, e2)) / den;
        float b2 = (d11 * dot(e3, e2) - d12 * dot(e3, e1)) / den;

        // Shading normal: interpolated vertex normals, on the same side as the geometric normal.
        // Meshes without normals (zero vectors) shade with the geometric normal.
        float3 nsObj = (1.0 - b1 - b2) * vertexNormal(indices[tri] + vo) + b1 * vertexNormal(indices[tri + 1] + vo) + b2 * vertexNormal(indices[tri + 2] + vo);
        float3 ns = nOut;
        if (dot(nsObj, nsObj) > 1.0e-12)
        {
            ns = normalize(transformNormal(inst + 4, nsObj));
            if (dot(ns, nOut) < 0.0)
                ns = -ns;
        }
        float3 n = outside ? ns : -ns;

        uint mi = instances[inst + 2] * 22;
        float3 albedo = float3(materials[mi], materials[mi + 1], materials[mi + 2]);
        // Textures multiply the material factors. The filter footprint comes from the ray cone.
        uint texBase = uint(materials[mi + 10]);
        uint texMR = uint(materials[mi + 11]);
        uint texEm = uint(materials[mi + 12]);
        uint texNm = uint(materials[mi + 13]);
        float2 texRM = float2(1.0); // x = roughness (green), y = metallic (blue)
        float3 texEmission = float3(1.0);
        if (texBase + texMR + texEm + texNm > 0)
        {
            float2 uv0 = float2(uvs[2 * (indices[tri] + vo)], uvs[2 * (indices[tri] + vo) + 1]);
            float2 uv1 = float2(uvs[2 * (indices[tri + 1] + vo)], uvs[2 * (indices[tri + 1] + vo) + 1]);
            float2 uv2 = float2(uvs[2 * (indices[tri + 2] + vo)], uvs[2 * (indices[tri + 2] + vo) + 1]);
            float2 uv = uv0 + b1 * (uv1 - uv0) + b2 * (uv2 - uv0);
            float2 d1 = uv1 - uv0;
            float2 d2 = uv2 - uv0;
            float uvPerWorld = sqrt(abs(d1.x * d2.y - d1.y * d2.x) / max(length(cross(e1, e2)), 1.0e-20));
            float footprint = st.pathLen * pf(27) / max(abs(dot(nOut, dir)), 0.1) * uvPerWorld;
            if (texBase > 0)
                albedo *= sampleTexture(texBase - 1, uv, footprint);
            if (texMR > 0)
                texRM = sampleTexture(texMR - 1, uv, footprint).yz;
            if (texEm > 0)
                texEmission = sampleTexture(texEm - 1, uv, footprint);
            if (texNm > 0)
            {
                // Tangent frame from the UV derivatives of this triangle; green points up the image (-v).
                float det = d1.x * d2.y - d2.x * d1.y;
                float3 dPdu = (e1 * d2.y - e2 * d1.y) / det;
                float3 dPdv = (e2 * d1.x - e1 * d2.x) / det;
                float3 tg = dPdu - ns * dot(ns, dPdu);
                if (abs(det) > 1.0e-20 && dot(tg, tg) > 1.0e-20)
                {
                    tg = normalize(tg);
                    float3 bt = cross(ns, tg);
                    if (dot(bt, dPdv) > 0.0)
                        bt = -bt;
                    float3 nt = sampleTexture(texNm - 1, uv, footprint) * 2.0 - 1.0;
                    ns = normalize(nt.x * materials[mi + 14] * tg + nt.y * materials[mi + 14] * bt + nt.z * ns);
                    n = outside ? ns : -ns;
                }
            }
        }
        // A shading normal bent away from the viewer would put wo below the lobe's horizon and zero the
        // diffuse term (the Fresnel weight reaches 1); keep it a small angle on the viewer's side.
        float woN = dot(n, wo);
        if (woN < 0.05)
            n = normalize(n + wo * (0.05 - woN));

        float3 le = float3(materials[mi + 3], materials[mi + 4], materials[mi + 5]) * texEmission;
        if (any(le > 0.0))
        {
            float wB = 1.0;
            uint eb = instances[inst + 3];
            if (st.misPrev && eb != 0)
            {
                uint e = (eb - 1 + hq.prim) * 16;
                float cosl = max(abs(dot(nOut, dir)), 1.0e-4);
                float pl = (st.restir && depth == 1 ? 1.0 : 1.0 - pEnv) * emitters[e + 13] * pHitT * pHitT / (emitters[e + 12] * cosl);
                wB = st.qPrev * st.qPrev / (st.qPrev * st.qPrev + pl * pl);
            }
            st.parts.add(depth, cls, thr * le * wB);
            if (depth == 1 && st.gi)
            {
                // Its weight depends on the first hit's view of the emitter, so it is not part of what
                // ReSTIR GI reuses elsewhere: count it with what the first hit gathered itself.
                uint so = restirScratch(pixel) + 18;
                for (uint k = 0; k < 3; k++)
                    restir[so + k] += (thr * le * wB)[k];
            }
        }
        float metallic = materials[mi + 6] * texRM.y;
        float rough = materials[mi + 7] * texRM.x;
        float transmission = materials[mi + 8];
        float ior = materials[mi + 9];
        float dispersion = materials[mi + 21];
        if (dispersion > 0.0 && transmission > 0.0)
        {
            // RGB dispersion (KHR_materials_dispersion): the path follows one channel from its first
            // dispersive hit on, chosen at random, and carries three times that channel so the mean stays right.
            if (chan < 0)
            {
                chan = min(int(rng.next() * 3.0), 2);
                thr *= 3.0 * float3(chan == 0 ? 1.0 : 0.0, chan == 1 ? 1.0 : 0.0, chan == 2 ? 1.0 : 0.0);
            }
            ior = max(ior + float(chan - 1) * (ior - 1.0) * 0.025 * dispersion, 1.0);
        }
        // A glass second hit cannot be reconnected to from another pixel: its outgoing direction follows
        // from the incoming one. The path stays what it is, a plain sample of this pixel's own.
        if (depth == 1 && st.gi && transmission > 0.0)
            restir[restirScratch(pixel) + 22] = asfloat(0u);
        float alpha = max(rough * rough, 1.0e-3);
        float eta = outside ? ior : 1.0 / ior; // relative index n_transmitted / n_incident

        float3 T, B;
        basis(n, T, B);
        float3 woL = float3(dot(wo, T), dot(wo, B), max(dot(wo, n), 1.0e-4));
        float fSel = fresnelDielectric(woL.z, ior); // chance the dielectric base lobe reflects specularly
        Surface surf;
        surf.albedo = albedo;
        surf.metallic = metallic;
        surf.alpha = alpha;
        surf.transmission = transmission;
        surf.ior = ior;
        surf.eta = eta;
        surf.fSel = fSel;
        // Rough transmission loses the energy that would scatter a second time on the microsurface;
        // scaling reflection and transmission by 1 / E gives it back and keeps their ratio.
        surf.tComp = 1.0;
        if (params[29] != 0 && transmission > 0.0 && rough > 0.0)
            surf.tComp = 1.0 / max(dielectricAlbedo(woL.z, rough, ior, outside), 0.1);
        // The coat sits on the viewer's side of a surface, so it is skipped when seen from inside.
        surf.coat = outside ? materials[mi + 15] : 0.0;
        surf.coatAlpha = max(materials[mi + 16] * materials[mi + 16], 1.0e-3);
        float coatF = fresnelDielectric(woL.z, 1.5);
        surf.coatP = surf.coat * coatF;
        surf.sheenColor = outside ? float3(materials[mi + 18], materials[mi + 19], materials[mi + 20]) : float3(0.0);
        float sheenMax = max(surf.sheenColor.x, max(surf.sheenColor.y, surf.sheenColor.z));
        float sheenR = max(materials[mi + 17], 0.07);
        surf.sheenAlpha = sheenR * sheenR;
        surf.sheenP = sheenMax > 0.0 ? sheenMax * sheenAlbedo(woL.z, sheenR) : 0.0;

        // Next-event estimation for delta lights (no MIS: sampling can never hit them). Includes the
        // reflective lobes only; rough transmission of a delta light is not evaluated.
        for (uint li = 0; li < lightCount; li++)
        {
            uint o = li * 16;
            float3 col = float3(asfloat(lights[o + 1]), asfloat(lights[o + 2]), asfloat(lights[o + 3])) * asfloat(lights[o + 4]);
            float3 vec = float3(asfloat(lights[o + 5]), asfloat(lights[o + 6]), asfloat(lights[o + 7]));
            float3 wi;
            float dist;
            float3 li_;
            if (lights[o] == 1)
            {
                wi = -normalize(vec);
                dist = 1.0e30;
                li_ = col;
            }
            else
            {
                float3 toL = vec - p;
                float d2 = dot(toL, toL);
                dist = sqrt(d2);
                wi = toL / dist;
                li_ = col / d2;
                if (lights[o] == 2)
                {
                    float3 axis = float3(asfloat(lights[o + 8]), asfloat(lights[o + 9]), asfloat(lights[o + 10]));
                    float att = saturate(dot(axis, -wi) * asfloat(lights[o + 11]) + asfloat(lights[o + 12]));
                    li_ *= att * att;
                }
            }
            float c = dot(n, wi);
            if (c > 0.0)
            {
                bool occ = occluded(p, wi, dist - 1.0e-3);
                bool track = lightingOn && depth == 0;
                if (!occ || track)
                {
                    Lobes l = evalLobes(surf, woL, float3(dot(wi, T), dot(wi, B), c));
                    float3 cd = thr * l.diffuse * li_;
                    float3 cs = thr * l.specular * li_;
                    if (!occ)
                        st.parts.addLight(depth, cls, thr * (l.diffuse + l.specular) * li_, cd, cs);
                    if (track)
                    {
                        float vv = lum(cd + cs);
                        st.visTotal += vv;
                        st.visLit += occ ? 0.0 : vv;
                        addSlot(pixel, lights[o + 13], cd / c, cs / c, wi, occ ? 0.0 : 1.0, occ ? 0.0 : c);
                    }
                }
            }
        }

        // ReSTIR DI at the first hit of surfaces it suits: emitters come from reservoirs, the
        // environment map is always light sampled, and BSDF hits on emitters are weighed against that.
        bool reDI = false;
        if (depth == 0 && params[36] != 0)
        {
            bool suits = pf(3) == 0.0 && transmission == 0.0 && surf.alpha >= RESTIR_MIN_ALPHA
                && (surf.coat == 0.0 || surf.coatAlpha >= RESTIR_MIN_ALPHA);
            reDI = suits && (params[36] & 1u) != 0 && emitterCount > 0;
            // ReSTIR GI replaces the path's own indirect light, which the lighting split cannot follow.
            bool reGI = suits && (params[36] & 2u) != 0 && !lightingOn;
            st.restir = reDI;
            st.gi = reGI;
            if (suits)
            {
                restirGbuffer(pixel, p, n);
                if (reGI)
                    restirGIPrepare(pixel, p, n, pHitT, surf, T, B, woL, rng);
            }
            else
                restirClear(pixel);
        }
        if (reDI)
        {
            RestirPick pick = restirDI(pixel, p, n, pHitT, surf, T, B, woL, rng);
            if (pick.valid)
            {
                float3 wi, g;
                float dist, cosi, plsa;
                restirLight(pick.e - 1, pick.x, p, n, wi, dist, cosi, g, plsa);
                bool track = lightingOn;
                if (!pick.occ || track)
                {
                    float3 wiL = float3(dot(wi, T), dot(wi, B), cosi);
                    float wl = restirMis(surf, woL, wiL, plsa);
                    Lobes l = evalLobes(surf, woL, wiL);
                    float3 cd = thr * l.diffuse * g * (wl * pick.W);
                    float3 cs = thr * l.specular * g * (wl * pick.W);
                    if (!pick.occ)
                        st.parts.addLight(depth, cls, cd + cs, cd, cs);
                    if (track)
                    {
                        float vv = lum(cd + cs);
                        st.visTotal += vv;
                        st.visLit += pick.occ ? 0.0 : vv;
                        addSlot(pixel, 3u, cd / cosi, cs / cosi, wi, pick.occ ? 0.0 : 1.0, pick.occ ? 0.0 : cosi);
                    }
                }
            }
        }

        // Light sampling of emissive triangles, combined with BSDF sampling by the power heuristic.
        float chooseLight = rng.next();
        float pEnvHere = reDI ? (hasEnv ? 1.0 : 0.0) : pEnv;
        bool chooseEnv = hasEnv && chooseLight < pEnvHere;
        if (emitterCount > 0 && !chooseEnv && !reDI)
        {
            float ue = rng.next();
            float ua = rng.next();
            float ub = rng.next();
            uint lo = 0;
            uint hi = emitterCount - 1;
            while (lo < hi)
            {
                uint mid = (lo + hi) / 2;
                if (emitCdf[mid] >= ue)
                    hi = mid;
                else
                    lo = mid + 1;
            }
            uint e = lo * 16;
            float3 a = float3(emitters[e], emitters[e + 1], emitters[e + 2]);
            float3 b = float3(emitters[e + 3], emitters[e + 4], emitters[e + 5]);
            float3 c = float3(emitters[e + 6], emitters[e + 7], emitters[e + 8]);
            float su = sqrt(ua);
            float3 xl = a * (1.0 - su) + b * (su * (1.0 - ub)) + c * (su * ub);
            float3 toL = xl - p;
            float d2 = dot(toL, toL);
            float dist = sqrt(d2);
            float3 wi = toL / dist;
            float cosl = abs(dot(normalize(cross(b - a, c - a)), wi));
            float cosi = dot(n, wi);
            if (cosi > 0.0 && cosl > 1.0e-5)
            {
                bool occ = occluded(p, wi, dist * (1.0 - 1.0e-3));
                bool track = lightingOn && depth == 0;
                if (!occ || track)
                {
                    float pl = (1.0 - pEnv) * emitters[e + 13] * d2 / (emitters[e + 12] * cosl);
                    float3 wiL = float3(dot(wi, T), dot(wi, B), cosi);
                    float qb = reflectivePdf(surf, woL, wiL);
                    float wl = pl * pl / (pl * pl + qb * qb);
                    float3 le = float3(emitters[e + 9], emitters[e + 10], emitters[e + 11]);
                    Lobes l = evalLobes(surf, woL, wiL);
                    float3 cd = thr * l.diffuse * le / pl * wl;
                    float3 cs = thr * l.specular * le / pl * wl;
                    if (!occ)
                        st.parts.addLight(depth, cls, thr * evalReflective(surf, woL, wiL) * le / pl * wl, cd, cs);
                    if (track)
                    {
                        float vv = lum(cd + cs);
                        st.visTotal += vv;
                        st.visLit += occ ? 0.0 : vv;
                        addSlot(pixel, 3u, cd / cosi, cs / cosi, wi, occ ? 0.0 : 1.0, occ ? 0.0 : cosi);
                    }
                }
            }
        }

        if (chooseEnv)
        {
            float e1 = rng.next();
            float e2 = rng.next();
            float e3 = rng.next();
            float e4 = rng.next();
            float pdfE;
            float3 leE;
            float3 wi = envSample(e1, e2, e3, e4, pdfE, leE);
            float cosi = dot(n, wi);
            if (pdfE > 0.0 && cosi > 0.0)
            {
                bool occ = occluded(p, wi, 1.0e30);
                bool track = lightingOn && depth == 0;
                if (!occ || track)
                {
                    float pl = pEnvHere * pdfE;
                    float3 wiL = float3(dot(wi, T), dot(wi, B), cosi);
                    float qb = reflectivePdf(surf, woL, wiL);
                    float wl = pl * pl / (pl * pl + qb * qb);
                    Lobes l = evalLobes(surf, woL, wiL);
                    float3 cd = thr * l.diffuse * leE / pl * wl;
                    float3 cs = thr * l.specular * leE / pl * wl;
                    if (!occ)
                        st.parts.addLight(depth, cls, thr * evalReflective(surf, woL, wiL) * leE / pl * wl, cd, cs);
                    if (track)
                    {
                        float vv = lum(cd + cs);
                        st.visTotal += vv;
                        st.visLit += occ ? 0.0 : vv;
                        addSlot(pixel, 3u, cd / cosi, cs / cosi, wi, occ ? 0.0 : 1.0, occ ? 0.0 : cosi);
                    }
                }
            }
        }

        // Sample one lobe by its weight, then apply that lobe's own sampling weight, which already
        // carries f * cos / pdf: metal GGX, rough dielectric transmission, or dielectric base.
        float lobe = rng.next();
        float u1 = rng.next();
        float u2 = rng.next();
        float u3 = rng.next();
        float3 wiL = float3(0, 0, 1);
        float3 w = float3(1.0);
        bool ok = true;
        bool refracted = false;
        uint lobeCls = 1;
        float uc = surf.coat > 0.0 ? rng.next() : 1.0;
        float us = surf.sheenP > 0.0 ? rng.next() : 1.0;
        if (uc < surf.coatP)
        {
            float3 h = sampleVndf(woL, surf.coatAlpha, u1, u2);
            float woh = dot(woL, h);
            wiL = 2.0 * woh * h - woL;
            ok = wiL.z > 0.0;
            w = float3(fresnelDielectric(woh, 1.5) / coatF * G1(max(wiL.z, 0.0), surf.coatAlpha));
        }
        else if (us < surf.sheenP)
        {
            // Cosine sampling: f * cos / pdf = D * V * pi, divided by the chance of taking this lobe.
            wiL = cosineLocal(u1, u2);
            float3 hh = normalize(woL + wiL);
            w = surf.sheenColor * sheenCore(woL.z, wiL.z, hh.z, surf.sheenAlpha) * PI / (wiL.z * surf.sheenP);
        }
        else if (lobe < metallic)
        {
            float3 h = sampleVndf(woL, alpha, u1, u2);
            float woh = dot(woL, h);
            wiL = 2.0 * woh * h - woL;
            ok = wiL.z > 0.0;
            w = schlick(albedo, woh) * multiscatterFactor(surf, woL.z) * G1(max(wiL.z, 0.0), alpha);
        }
        else if (lobe < metallic + (1.0 - metallic) * transmission)
        {
            float3 h = sampleVndf(woL, alpha, u1, u2);
            float woh = dot(woL, h);
            if (u3 < fresnelDielectric(woh, eta))
            {
                wiL = 2.0 * woh * h - woL;
                ok = wiL.z > 0.0;
                w = float3(G1(max(wiL.z, 0.0), alpha) * surf.tComp);
            }
            else
            {
                float r = 1.0 / eta;
                float k = 1.0 - r * r * (1.0 - woh * woh);
                wiL = -woL * r + (r * woh - sqrt(max(k, 0.0))) * h;
                ok = wiL.z < 0.0 && k > 0.0;
                refracted = true;
                lobeCls = 2;
                // Radiance scales by (n_incident / n_transmitted)^2 across the interface.
                w = albedo * G1(max(-wiL.z, 0.0), alpha) * r * r * surf.tComp;
            }
        }
        else if (u3 < fSel)
        {
            float3 h = sampleVndf(woL, alpha, u1, u2);
            float woh = dot(woL, h);
            wiL = 2.0 * woh * h - woL;
            ok = wiL.z > 0.0;
            w = float3(fresnelDielectric(woh, ior) / fSel * G1(max(wiL.z, 0.0), alpha));
        }
        else
        {
            wiL = cosineLocal(u1, u2);
            w = albedo;
            lobeCls = 0;
        }
        if (!ok)
            { alive = false; break; }
        if (depth == 0)
            cls = lobeCls;
        st.misPrev = !refracted;
        st.qPrev = refracted ? 0.0 : reflectivePdf(surf, woL, wiL);

        dir = normalize(wiL.x * T + wiL.y * B + wiL.z * n);
        // A shading normal can bend a sample through the true surface; drop it rather than leak.
        float side = dot(dir, ng);
        if (refracted ? side >= 0.0 : side <= 0.0)
            { alive = false; break; }
        org = hit + ng * (side > 0.0 ? 1.0e-4 : -1.0e-4);
        thr *= w;

        if (depth >= 2)
        {
            float pr = clamp(max(thr.x, max(thr.y, thr.z)), 0.05, 0.95);
            if (rng.next() > pr)
                { alive = false; break; }
            thr /= pr;
        }
    }
    st.rng = rng.state;
    st.org = org;
    st.dir = dir;
    st.thr = thr;
    st.cls = cls;
    st.chan = chan;
    if (depth == 0 && st.gi)
    {
        // What the first hit gathered (and later its direct sight of an emitter) and what the first bounce carries on, for `giFinish`.
        uint so = restirScratch(pixel);
        for (uint k = 0; k < 3; k++)
        {
            restir[so + 15 + k] = thr[k];
            restir[so + 18 + k] = st.parts.total[k];
        }
        restir[so + 21] = st.qPrev;
    }
    return alive;
}

PathState generatePath(uint px, uint py) { return generatePathFor(px, py, params[6]); }

// Adaptive sampling (REQ-ACC-007): whether pixel p takes more samples. It stops once it has the
// minimum samples (params[34]) and the standard error of its luminance mean is within params[33]
// of the mean (with a floor, so near-black pixels stop too). Stopping on the pixel's own estimate
// biases it slightly, so adaptive renders are not physical. Mirrored in `Adaptive::active` (renderer.rs).
bool pixelActive(uint p)
{
    float n = pixelStats[3 * p];
    if (n < float(params[34]))
        return true;
    float mean = pixelStats[3 * p + 1] / n;
    float var = max(pixelStats[3 * p + 2] / n - mean * mean, 0.0) * n / (n - 1.0);
    return sqrt(var / n) > pf(33) * max(mean, 0.05);
}

// ReSTIR GI, second half: adds the path's own candidate (the surface its first bounce reached, with
// the radiance the rest of the path gathered there) to the resampled neighbours', picks one, and
// returns the pixel's radiance with the indirect light of the pick in place of the path's own.
// The new reservoir goes to this frame's half for the next frame to reuse. A path that left the
// scene keeps its sky light as it is; it is not a surface sample.
float3 giFinish(float3 pathTotal, uint pixel)
{
    uint co = restirBase(pixel, params[6] & 1u);
    uint so = restirScratch(pixel);
    float wsum = restir[so];
    float m = restir[so + 1] + 1.0;
    float pSel = restir[so + 2];
    float3 cSel = float3(restir[so + 3], restir[so + 4], restir[so + 5]);
    float3 xSel = float3(restir[so + 6], restir[so + 7], restir[so + 8]);
    float3 nSel = float3(restir[so + 9], restir[so + 10], restir[so + 11]);
    float3 lSel = float3(restir[so + 12], restir[so + 13], restir[so + 14]);
    float3 thr1 = float3(restir[so + 15], restir[so + 16], restir[so + 17]);
    float3 d0 = float3(restir[so + 18], restir[so + 19], restir[so + 20]);
    float qPrev = restir[so + 21];
    bool own = asuint(restir[so + 22]) != 0 && qPrev > 0.0;
    float3 giTotal = pathTotal - d0;
    float3 result = d0;
    if (own)
    {
        float3 cOwn = giTotal * qPrev;
        float pOwn = lum(cOwn);
        if (pOwn > 0.0)
        {
            float wOwn = pOwn / qPrev;
            wsum += wOwn;
            Rng r;
            r.state = pcg(pixel ^ pcg(params[6] * 0x85EBCA6Bu + 0x1234u));
            if (r.next() * wsum < wOwn)
            {
                pSel = pOwn;
                cSel = cOwn;
                xSel = float3(restir[co + 16], restir[co + 17], restir[co + 18]);
                nSel = float3(restir[co + 19], restir[co + 20], restir[co + 21]);
                lSel = float3(thr1.x > 1.0e-6 ? giTotal.x / thr1.x : 0.0, thr1.y > 1.0e-6 ? giTotal.y / thr1.y : 0.0, thr1.z > 1.0e-6 ? giTotal.z / thr1.z : 0.0);
            }
        }
    }
    else
        result += giTotal;
    float W = pSel > 0.0 ? wsum / (m * pSel) : 0.0;
    result += cSel * W;
    for (uint k = 0; k < 3; k++)
    {
        restir[co + 16 + k] = xSel[k];
        restir[co + 19 + k] = nSel[k];
        restir[co + 22 + k] = lSel[k];
    }
    restir[co + 25] = W;
    restir[co + 26] = m;
    restir[co + 27] = asfloat(pSel > 0.0 ? 1u : 0u);
    return result;
}

// Adds the finished path to the running sums of its pixel.
void finishPath(PathState st, uint pixel)
{
    Parts parts = st.parts;
    float visLit = st.visLit;
    float visTotal = st.visTotal;
    float3 radiance = parts.total;
    if (st.gi)
    {
        // A path that went through dispersive glass follows one color channel, tripled: as a reused
        // sample it would tint the neighbours and the next frames, so it is not shared either.
        if (st.chan >= 0)
            restir[restirScratch(pixel) + 22] = asfloat(0u);
        radiance = giFinish(radiance, pixel);
    }
    if (any(isnan(radiance)) || any(isinf(radiance)))
    {
        radiance = float3(0.0); // one bad sample must not poison the running sum
        parts = (Parts)0;
        visLit = 0.0;
        visTotal = 0.0;
    }

    uint o = 3 * pixel;
    accum[o] += radiance.x;
    accum[o + 1] += radiance.y;
    accum[o + 2] += radiance.z;
    if (params[32] != 0)
    {
        float l = lum(radiance);
        pixelStats[3 * pixel] += 1.0;
        pixelStats[3 * pixel + 1] += l;
        pixelStats[3 * pixel + 2] += l * l;
    }

    if (params[28] != 0)
    {
        uint lo = LIGHTING_STRIDE * pixel;
        float3 split[5] = { parts.directDiffuse, parts.indirectDiffuse, parts.specular, parts.transmission, parts.emission };
        for (uint k = 0; k < 5; k++)
        {
            lighting[lo + 3 * k] += split[k].x;
            lighting[lo + 3 * k + 1] += split[k].y;
            lighting[lo + 3 * k + 2] += split[k].z;
        }
        lighting[lo + 15] += visLit;
        lighting[lo + 16] += visTotal;
    }
}
