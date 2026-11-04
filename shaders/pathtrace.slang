// Diffuse path tracer, one sample per pixel per dispatch (M1 item 6b).
// Flat word buffers only; layouts are documented next to each binding and mirrored in
// crates/verion-gpu-metal/src/renderer.rs.

RaytracingAccelerationStructure scene;
StructuredBuffer<float> positions;  // xyz per vertex, all meshes concatenated
StructuredBuffer<uint> indices;     // triangle vertex indices, all meshes concatenated
StructuredBuffer<uint> instances;   // 16 words: vertex offset, index offset, material, pad, 12 floats (row-major 3x4)
StructuredBuffer<float> materials;  // 8 words: base color rgb, emission rgb, 2 pad
StructuredBuffer<uint> lights;      // 8 words: kind (0 point, 1 directional), color rgb, intensity, position or travel direction xyz (floats as bits)
StructuredBuffer<uint> params;      // 0 width, 1 height, 2 tan(fov/2), 3 aperture radius, 4 focus distance (floats as bits),
                                    // 5 light count, 6 sample index, 7 max depth, 8..19 camera-to-world 3x4, 20..22 sky rgb
RWStructuredBuffer<float> accum;    // running radiance sum, xyz per pixel

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

float3 cosineHemisphere(float3 n, float u1, float u2)
{
    float3 a = abs(n.x) > 0.9 ? float3(0, 1, 0) : float3(1, 0, 0);
    float3 b = normalize(cross(n, a));
    float3 t = cross(b, n);
    float r = sqrt(u1);
    float phi = 2.0 * PI * u2;
    return normalize(t * (r * cos(phi)) + b * (r * sin(phi)) + n * sqrt(max(0.0, 1.0 - u1)));
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
            break;
        }

        uint inst = q.CommittedInstanceIndex() * 16;
        uint tri = instances[inst + 1] + 3 * q.CommittedPrimitiveIndex();
        uint vo = instances[inst];
        float3 p0 = transformPoint(inst + 4, vertexPos(indices[tri] + vo));
        float3 p1 = transformPoint(inst + 4, vertexPos(indices[tri + 1] + vo));
        float3 p2 = transformPoint(inst + 4, vertexPos(indices[tri + 2] + vo));
        float3 n = normalize(cross(p1 - p0, p2 - p0));
        if (dot(n, dir) > 0.0)
            n = -n; // double-sided
        // shortcut: fixed 1e-4 ray offset assumes unit-scale scenes, scale it with scene bounds later.
        float3 p = org + dir * q.CommittedRayT() + n * 1.0e-4;

        uint mi = instances[inst + 2] * 8;
        float3 albedo = float3(materials[mi], materials[mi + 1], materials[mi + 2]);
        radiance += thr * float3(materials[mi + 3], materials[mi + 4], materials[mi + 5]);

        // Next-event estimation for delta lights (no MIS needed: they cannot be hit by sampling).
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
                radiance += thr * albedo * (c / PI) * li_;
        }

        // Cosine-sampled bounce: pdf = cos / pi cancels the Lambert BRDF, leaving the albedo.
        org = p;
        dir = cosineHemisphere(n, rng.next(), rng.next());
        thr *= albedo;

        if (depth >= 2)
        {
            float pr = clamp(max(thr.x, max(thr.y, thr.z)), 0.05, 0.95);
            if (rng.next() > pr)
                break;
            thr /= pr;
        }
    }

    uint o = 3 * pixel;
    accum[o] += radiance.x;
    accum[o + 1] += radiance.y;
    accum[o + 2] += radiance.z;
}
