// Primary-ray normal AOV (M1 item 6a). All resources are flat word buffers so the
// Rust side and the generated MSL agree on layout without struct packing rules.

RaytracingAccelerationStructure scene;
StructuredBuffer<float> positions;  // xyz per vertex, all meshes concatenated
StructuredBuffer<uint> indices;     // triangle vertex indices, all meshes concatenated
StructuredBuffer<uint> instances;   // 16 words each: vertex offset, index offset, 2 pad, 12 floats (row-major 3x4)
StructuredBuffer<float> camera;     // width, height, tan(fov/2), pad, 12 floats (camera-to-world 3x4)
RWStructuredBuffer<float> output;   // xyz per pixel

float3 vertex(uint v) { return float3(positions[3 * v], positions[3 * v + 1], positions[3 * v + 2]); }

float3 transformPoint(StructuredBuffer<uint> buf, uint base, float3 p)
{
    float3 r;
    for (uint row = 0; row < 3; row++)
    {
        uint o = base + 4 * row;
        r[row] = asfloat(buf[o]) * p.x + asfloat(buf[o + 1]) * p.y + asfloat(buf[o + 2]) * p.z + asfloat(buf[o + 3]);
    }
    return r;
}

[shader("compute")]
[numthreads(8, 8, 1)]
void normals(uint3 tid : SV_DispatchThreadID)
{
    uint w = (uint)camera[0];
    uint h = (uint)camera[1];
    if (tid.x >= w || tid.y >= h)
        return;

    float t = camera[2];
    float aspect = camera[0] / camera[1];
    float u = (2.0 * (tid.x + 0.5) / w - 1.0) * aspect * t;
    float v = (1.0 - 2.0 * (tid.y + 0.5) / h) * t;
    float3 d = normalize(float3(u, v, -1.0));

    // Camera-to-world: rotate the direction, translate the origin.
    float3 dir, org;
    for (uint r = 0; r < 3; r++)
    {
        dir[r] = camera[4 + 4 * r] * d.x + camera[5 + 4 * r] * d.y + camera[6 + 4 * r] * d.z;
        org[r] = camera[7 + 4 * r];
    }

    RayDesc ray;
    ray.Origin = org;
    ray.Direction = normalize(dir);
    ray.TMin = 0.0;
    ray.TMax = 1.0e30;

    RayQuery<RAY_FLAG_FORCE_OPAQUE> q;
    q.TraceRayInline(scene, 0, 0xFF, ray);
    while (q.Proceed()) { }

    float3 n = float3(0.0);
    if (q.CommittedStatus() == COMMITTED_TRIANGLE_HIT)
    {
        uint inst = q.CommittedInstanceIndex() * 16;
        uint tri = instances[inst + 1] + 3 * q.CommittedPrimitiveIndex();
        uint vo = instances[inst];
        float3 p0 = transformPoint(instances, inst + 4, vertex(indices[tri] + vo));
        float3 p1 = transformPoint(instances, inst + 4, vertex(indices[tri + 1] + vo));
        float3 p2 = transformPoint(instances, inst + 4, vertex(indices[tri + 2] + vo));
        n = normalize(cross(p1 - p0, p2 - p0));
        if (dot(n, ray.Direction) > 0.0)
            n = -n; // face the viewer: surfaces are double-sided
    }

    uint o = 3 * (tid.y * w + tid.x);
    output[o] = n.x;
    output[o + 1] = n.y;
    output[o + 2] = n.z;
}
