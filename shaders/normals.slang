// Primary-ray normal AOV (M1 item 6a): the interpolated vertex normal, or the geometric normal for
// meshes without normals. Normal maps are not applied. All resources are flat word buffers so the
// Rust side and the generated MSL agree on layout without struct packing rules.

RaytracingAccelerationStructure scene;
StructuredBuffer<float> positions;  // xyz per vertex, all meshes concatenated
StructuredBuffer<uint> indices;     // triangle vertex indices, all meshes concatenated
StructuredBuffer<uint> instances;   // 16 words each: vertex offset, index offset, 2 pad, 12 floats (row-major 3x4)
StructuredBuffer<float> camera;     // width, height, tan(fov/2), pad, 12 floats (camera-to-world 3x4), lens shift x and y
RWStructuredBuffer<float> output;   // xyz per pixel
StructuredBuffer<float> vnormals;   // xyz per vertex, all meshes concatenated (zero when a mesh has none)

float3 vertex(uint v) { return float3(positions[3 * v], positions[3 * v + 1], positions[3 * v + 2]); }

// Object-space normal to world space: inverse transpose of the 3x3 part, written with cofactors.
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
    float u = (2.0 * (tid.x + 0.5) / w - 1.0 + camera[16]) * aspect * t;
    float v = (1.0 - 2.0 * (tid.y + 0.5) / h + camera[17]) * t;
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
        float3 ng = normalize(cross(p1 - p0, p2 - p0));
        n = ng;

        // Barycentric weights of vertices 1 and 2 at the hit, then the interpolated vertex normal on the
        // same side as the geometric normal.
        float3 e1 = p1 - p0;
        float3 e2 = p2 - p0;
        float3 e3 = org + ray.Direction * q.CommittedRayT() - p0;
        float d11 = dot(e1, e1);
        float d12 = dot(e1, e2);
        float d22 = dot(e2, e2);
        float den = max(d11 * d22 - d12 * d12, 1.0e-20);
        float b1 = (d22 * dot(e3, e1) - d12 * dot(e3, e2)) / den;
        float b2 = (d11 * dot(e3, e2) - d12 * dot(e3, e1)) / den;
        float3 nsObj = (1.0 - b1 - b2) * vertexNormal(indices[tri] + vo) + b1 * vertexNormal(indices[tri + 1] + vo) + b2 * vertexNormal(indices[tri + 2] + vo);
        if (dot(nsObj, nsObj) > 1.0e-12)
        {
            n = normalize(transformNormal(inst + 4, nsObj));
            if (dot(n, ng) < 0.0)
                n = -n;
        }
        if (dot(ng, ray.Direction) > 0.0)
            n = -n; // face the viewer: surfaces are double-sided
    }

    uint o = 3 * (tid.y * w + tid.x);
    output[o] = n.x;
    output[o + 1] = n.y;
    output[o + 2] = n.z;
}
