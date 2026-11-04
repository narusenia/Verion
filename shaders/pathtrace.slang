// Path tracer with a glTF-style BSDF, one sample per pixel per dispatch (M1 items 6b and 6c).
// Flat word buffers only; layouts are documented next to each binding and mirrored in
// crates/verion-gpu-metal/src/renderer.rs.

RaytracingAccelerationStructure scene;
StructuredBuffer<float> positions;  // xyz per vertex, all meshes concatenated
StructuredBuffer<uint> indices;     // triangle vertex indices, all meshes concatenated
StructuredBuffer<uint> instances;   // 16 words: vertex offset, index offset, material, emitter base + 1 (0 = not emissive), 12 floats (row-major 3x4)
StructuredBuffer<float> materials;  // 12 words: base color rgb, emission rgb, metallic, roughness, transmission, ior, 2 pad
StructuredBuffer<uint> lights;      // 8 words: kind (0 point, 1 directional), color rgb, intensity, position or travel direction xyz (floats as bits)
StructuredBuffer<uint> params;      // 0 width, 1 height, 2 tan(fov/2), 3 aperture radius, 4 focus distance (floats as bits),
                                    // 5 light count, 6 sample index, 7 max depth, 8..19 camera-to-world 3x4, 20..22 sky rgb, 23 emitter count, 24 env width (0 = none), 25 env height, 26 env pdf scale w*h / (2 pi^2 W)
RWStructuredBuffer<float> accum;    // running radiance sum, xyz per pixel
StructuredBuffer<float> emitters;   // 16 words per emissive world-space triangle: p0, p1, p2, radiance rgb, area, selection pdf, 2 pad
StructuredBuffer<float> emitCdf;    // cumulative selection probability per emitter triangle, last entry 1
StructuredBuffer<float> envPixels;  // environment map rgb per texel (scale applied), latitude-longitude, row-major from the top
StructuredBuffer<float> envMarginal; // cumulative probability per row of luminance * sin(theta), last entry 1
StructuredBuffer<float> envCond;    // cumulative probability per column within each row, last entry of each row 1

static const float PI = 3.14159265358979;

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

struct Surface
{
    float3 albedo;
    float metallic;
    float alpha;
    float transmission;
    float ior;
    float eta;  // relative index n_transmitted / n_incident on the viewer's side
    float fSel; // chance the dielectric base lobe reflects specularly
};

// f * cos(wi) of the reflective lobes. Rough transmission is not included.
float3 evalReflective(Surface s, float3 woL, float3 wiL)
{
    float3 hh = normalize(woL + wiL);
    float woh = max(dot(woL, hh), 0.0);
    // The cosine cancels against the 1 / (4 cos wi cos wo) of the microfacet BRDF.
    float core = D(hh.z, s.alpha) * G1(woL.z, s.alpha) * G1(wiL.z, s.alpha) / (4.0 * woL.z);
    float t = s.transmission;
    return s.metallic * schlick(s.albedo, woh) * core
        + (1.0 - s.metallic) * (t * fresnelDielectric(woh, s.eta) + (1.0 - t) * fresnelDielectric(woh, s.ior)) * core
        + (1.0 - s.metallic) * (1.0 - t) * (1.0 - s.fSel) * s.albedo * (wiL.z / PI);
}

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
    return pSpec * spec + pDiff;
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

[shader("compute")]
[numthreads(8, 8, 1)]
void pathtrace(uint3 tid : SV_DispatchThreadID)
{
    uint w = params[0];
    uint h = params[1];
    if (tid.x >= w || tid.y >= h)
        return;
    uint pixel = tid.y * w + tid.x;
    Rng rng;
    rng.state = pcg(pixel ^ pcg(params[6] * 0x9E3779B9u + 0x7F4A7C15u));

    // Thin-lens camera ray with a jittered pixel position.
    float t = pf(2);
    float aspect = float(w) / float(h);
    float u = (2.0 * (tid.x + rng.next()) / w - 1.0) * aspect * t;
    float v = (1.0 - 2.0 * (tid.y + rng.next()) / h) * t;
    float3 focal = float3(u, v, -1.0) * pf(4);
    float lensR = pf(3) * sqrt(rng.next());
    float lensA = 2.0 * PI * rng.next();
    float3 lens = float3(lensR * cos(lensA), lensR * sin(lensA), 0.0);
    float3 dc = normalize(focal - lens);
    float3 org, dir;
    for (uint r = 0; r < 3; r++)
    {
        org[r] = asfloat(params[8 + 4 * r]) * lens.x + asfloat(params[9 + 4 * r]) * lens.y + asfloat(params[10 + 4 * r]) * lens.z + asfloat(params[11 + 4 * r]);
        dir[r] = asfloat(params[8 + 4 * r]) * dc.x + asfloat(params[9 + 4 * r]) * dc.y + asfloat(params[10 + 4 * r]) * dc.z;
    }
    dir = normalize(dir);

    float3 sky = float3(pf(20), pf(21), pf(22));
    float3 radiance = float3(0.0);
    float3 thr = float3(1.0);
    uint lightCount = params[5];
    uint maxDepth = params[7];
    uint emitterCount = params[23];
    // Set when the previous bounce was a reflection that light sampling also covers; qPrev is its density.
    bool hasEnv = params[24] > 0;
    // Probability that next-event estimation samples the environment map instead of an emitter.
    float pEnv = hasEnv ? (emitterCount > 0 ? 0.5 : 1.0) : 0.0;
    bool misPrev = false;
    float qPrev = 0.0;

    for (uint depth = 0; depth < maxDepth; depth++)
    {
        RayDesc ray;
        ray.Origin = org;
        ray.Direction = dir;
        ray.TMin = 0.0;
        ray.TMax = 1.0e30;
        RayQuery<RAY_FLAG_FORCE_OPAQUE> q;
        q.TraceRayInline(scene, 0, 0xFF, ray);
        while (q.Proceed()) { }

        if (q.CommittedStatus() != COMMITTED_TRIANGLE_HIT)
        {
            // Uniform sky is reached by cosine sampling, so it needs no light sampling.
            radiance += thr * sky;
            if (hasEnv)
            {
                float wB = 1.0;
                if (misPrev)
                {
                    float pl = pEnv * envPdf(dir);
                    float den = qPrev * qPrev + pl * pl;
                    wB = den > 0.0 ? qPrev * qPrev / den : 1.0;
                }
                radiance += thr * envRadiance(dir) * wB;
            }
            break;
        }

        uint inst = q.CommittedInstanceIndex() * 16;
        uint tri = instances[inst + 1] + 3 * q.CommittedPrimitiveIndex();
        uint vo = instances[inst];
        float3 p0 = transformPoint(inst + 4, vertexPos(indices[tri] + vo));
        float3 p1 = transformPoint(inst + 4, vertexPos(indices[tri + 1] + vo));
        float3 p2 = transformPoint(inst + 4, vertexPos(indices[tri + 2] + vo));
        // Winding gives the outward normal (glTF is counter-clockwise); `n` faces the viewer.
        float3 nOut = normalize(cross(p1 - p0, p2 - p0));
        float3 wo = -dir;
        bool outside = dot(nOut, wo) > 0.0;
        float3 n = outside ? nOut : -nOut;
        float pHitT = q.CommittedRayT();
        float3 hit = org + dir * pHitT;
        // shortcut: fixed 1e-4 ray offset assumes unit-scale scenes, scale it with scene bounds later.
        float3 p = hit + n * 1.0e-4;

        uint mi = instances[inst + 2] * 12;
        float3 albedo = float3(materials[mi], materials[mi + 1], materials[mi + 2]);
        float3 le = float3(materials[mi + 3], materials[mi + 4], materials[mi + 5]);
        if (any(le > 0.0))
        {
            float wB = 1.0;
            uint eb = instances[inst + 3];
            if (misPrev && eb != 0)
            {
                uint e = (eb - 1 + q.CommittedPrimitiveIndex()) * 16;
                float cosl = max(abs(dot(nOut, dir)), 1.0e-4);
                float pl = (1.0 - pEnv) * emitters[e + 13] * pHitT * pHitT / (emitters[e + 12] * cosl);
                wB = qPrev * qPrev / (qPrev * qPrev + pl * pl);
            }
            radiance += thr * le * wB;
        }
        float metallic = materials[mi + 6];
        float rough = materials[mi + 7];
        float transmission = materials[mi + 8];
        float ior = materials[mi + 9];
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

        // Next-event estimation for delta lights (no MIS: sampling can never hit them). Includes the
        // reflective lobes only; rough transmission of a delta light is not evaluated.
        for (uint li = 0; li < lightCount; li++)
        {
            uint o = li * 8;
            float3 col = float3(asfloat(lights[o + 1]), asfloat(lights[o + 2]), asfloat(lights[o + 3])) * asfloat(lights[o + 4]);
            float3 vec = float3(asfloat(lights[o + 5]), asfloat(lights[o + 6]), asfloat(lights[o + 7]));
            float3 wi;
            float dist;
            float3 li_;
            if (lights[o] == 0)
            {
                float3 toL = vec - p;
                float d2 = dot(toL, toL);
                dist = sqrt(d2);
                wi = toL / dist;
                li_ = col / d2;
            }
            else
            {
                wi = -normalize(vec);
                dist = 1.0e30;
                li_ = col;
            }
            float c = dot(n, wi);
            if (c > 0.0 && !occluded(p, wi, dist - 1.0e-3))
            {
                float3 f = evalReflective(surf, woL, float3(dot(wi, T), dot(wi, B), c));
                radiance += thr * f * li_;
            }
        }

        // Light sampling of emissive triangles, combined with BSDF sampling by the power heuristic.
        float chooseLight = rng.next();
        bool chooseEnv = hasEnv && chooseLight < pEnv;
        if (emitterCount > 0 && !chooseEnv)
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
            if (cosi > 0.0 && cosl > 1.0e-5 && !occluded(p, wi, dist * (1.0 - 1.0e-3)))
            {
                float pl = (1.0 - pEnv) * emitters[e + 13] * d2 / (emitters[e + 12] * cosl);
                float3 wiL = float3(dot(wi, T), dot(wi, B), cosi);
                float qb = reflectivePdf(surf, woL, wiL);
                float wl = pl * pl / (pl * pl + qb * qb);
                radiance += thr * evalReflective(surf, woL, wiL) * float3(emitters[e + 9], emitters[e + 10], emitters[e + 11]) / pl * wl;
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
            if (pdfE > 0.0 && cosi > 0.0 && !occluded(p, wi, 1.0e30))
            {
                float pl = pEnv * pdfE;
                float3 wiL = float3(dot(wi, T), dot(wi, B), cosi);
                float qb = reflectivePdf(surf, woL, wiL);
                float wl = pl * pl / (pl * pl + qb * qb);
                radiance += thr * evalReflective(surf, woL, wiL) * leE / pl * wl;
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
        if (lobe < metallic)
        {
            float3 h = sampleVndf(woL, alpha, u1, u2);
            float woh = dot(woL, h);
            wiL = 2.0 * woh * h - woL;
            ok = wiL.z > 0.0;
            w = schlick(albedo, woh) * G1(max(wiL.z, 0.0), alpha);
        }
        else if (lobe < metallic + (1.0 - metallic) * transmission)
        {
            float3 h = sampleVndf(woL, alpha, u1, u2);
            float woh = dot(woL, h);
            if (u3 < fresnelDielectric(woh, eta))
            {
                wiL = 2.0 * woh * h - woL;
                ok = wiL.z > 0.0;
                w = float3(G1(max(wiL.z, 0.0), alpha));
            }
            else
            {
                float r = 1.0 / eta;
                float k = 1.0 - r * r * (1.0 - woh * woh);
                wiL = -woL * r + (r * woh - sqrt(max(k, 0.0))) * h;
                ok = wiL.z < 0.0 && k > 0.0;
                refracted = true;
                // Radiance scales by (n_incident / n_transmitted)^2 across the interface.
                w = albedo * G1(max(-wiL.z, 0.0), alpha) * r * r;
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
        }
        if (!ok)
            break;
        misPrev = !refracted;
        qPrev = refracted ? 0.0 : reflectivePdf(surf, woL, wiL);

        dir = normalize(wiL.x * T + wiL.y * B + wiL.z * n);
        org = hit + n * (wiL.z > 0.0 ? 1.0e-4 : -1.0e-4);
        thr *= w;

        if (depth >= 2)
        {
            float pr = clamp(max(thr.x, max(thr.y, thr.z)), 0.05, 0.95);
            if (rng.next() > pr)
                break;
            thr /= pr;
        }
    }

    if (any(isnan(radiance)) || any(isinf(radiance)))
        radiance = float3(0.0); // one bad sample must not poison the running sum

    uint o = 3 * pixel;
    accum[o] += radiance.x;
    accum[o + 1] += radiance.y;
    accum[o + 2] += radiance.z;
}
