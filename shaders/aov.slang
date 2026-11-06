// Primary-ray Albedo / Depth / ObjectId AOVs (M1 item 8). One ray through each pixel centre, so IDs
// and depth are never blended. Flat word buffers, as in normals.slang.
// shortcut: the texture lookup and barycentrics are copied from pathtrace.slang (level 0 only);
// share them through an include when a third kernel needs them.

RaytracingAccelerationStructure scene;
StructuredBuffer<float> positions;  // xyz per vertex, all meshes concatenated
StructuredBuffer<uint> indices;     // triangle vertex indices, all meshes concatenated
StructuredBuffer<uint> instances;   // 16 words each: vertex offset, index offset, material, emitter base, 12 floats (row-major 3x4)
StructuredBuffer<float> camera;     // width, height, tan(fov/2), pad, 12 floats (camera-to-world 3x4)
StructuredBuffer<float> materials;  // 24 words each; 0..2 base color, 10 = base color texture + 1 (0 = none), 15 clearcoat, 16 its roughness, 17 sheen roughness, 18..20 sheen color, 21 dispersion, 22 opacity, 23 opacity texture + 1
StructuredBuffer<float> uvs;        // uv per vertex (zero when a mesh has none)
StructuredBuffer<uint> texInfo;     // 4 words per texture: texel offset, width, height, mip level count
StructuredBuffer<float> texels;     // rgb texels, each texture's mip chain level 0 first
RWStructuredBuffer<float> albedoDepth; // rgb albedo then depth (distance along the camera's forward axis), per pixel
RWStructuredBuffer<uint> objectIds;    // instance index + 1 per pixel, 0 where the ray misses
RWStructuredBuffer<uint> materialIds;  // material index + 1 per pixel, 0 where the ray misses
RWStructuredBuffer<float> coverage;    // fraction of 16 stratified rays through the pixel that hit something (anti-aliased alpha)

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

// Camera-space unit direction through pixel position `px` (in pixels), and its world-space direction in `dir`.
// Opacity of a triangle hit: the material factor times the opacity texture's red channel at the hit's UV.
float opacityAt(uint instIdx, uint prim, float2 bary)
{
    uint mi = instances[instIdx * 16 + 2] * 24;
    float op = materials[mi + 22];
    uint tex = uint(materials[mi + 23]);
    if (tex > 0 && op > 0.0)
    {
        uint tri = instances[instIdx * 16 + 1] + 3 * prim;
        uint vo = instances[instIdx * 16];
        float2 uv0 = float2(uvs[2 * (indices[tri] + vo)], uvs[2 * (indices[tri] + vo) + 1]);
        float2 uv1 = float2(uvs[2 * (indices[tri + 1] + vo)], uvs[2 * (indices[tri + 1] + vo) + 1]);
        float2 uv2 = float2(uvs[2 * (indices[tri + 2] + vo)], uvs[2 * (indices[tri + 2] + vo) + 1]);
        uint ti = (tex - 1) * 4;
        op *= bilinear(texInfo[ti], texInfo[ti + 1], texInfo[ti + 2], uv0 + bary.x * (uv1 - uv0) + bary.y * (uv2 - uv0)).x;
    }
    return op;
}

float3 pixelDir(float2 px, uint w, uint h, float t, float aspect, out float3 dir)
{
    float u = (2.0 * px.x / w - 1.0 + camera[16]) * aspect * t;
    float v = (1.0 - 2.0 * px.y / h + camera[17]) * t;
    float3 d = normalize(float3(u, v, -1.0));
    for (uint r = 0; r < 3; r++)
        dir[r] = camera[4 + 4 * r] * d.x + camera[5 + 4 * r] * d.y + camera[6 + 4 * r] * d.z;
    return d;
}

[shader("compute")]
[numthreads(8, 8, 1)]
void aov(uint3 tid : SV_DispatchThreadID)
{
    uint w = (uint)camera[0];
    uint h = (uint)camera[1];
    if (tid.x >= w || tid.y >= h)
        return;

    float t = camera[2];
    float aspect = camera[0] / camera[1];
    float2 px = float2(tid.x + 0.5, tid.y + 0.5);
    float3 d;
    float3 dir, org;
    RayDesc ray;
    ray.TMin = 0.0;
    ray.TMax = 1.0e30;
    org = float3(camera[7], camera[11], camera[15]);
    d = pixelDir(px, w, h, t, aspect, dir);
    ray.Origin = org;
    ray.Direction = normalize(dir);

    RayQuery<RAY_FLAG_FORCE_OPAQUE> q;
    q.TraceRayInline(scene, 0, 0xFF, ray);
    while (q.Proceed()) { }

    float3 albedo = float3(0.0);
    float depth = 0.0;
    uint id = 0;
    uint matId = 0;
    if (q.CommittedStatus() == COMMITTED_TRIANGLE_HIT)
    {
        uint instance = q.CommittedInstanceIndex();
        uint inst = instance * 16;
        uint tri = instances[inst + 1] + 3 * q.CommittedPrimitiveIndex();
        uint vo = instances[inst];
        id = instance + 1;
        matId = instances[inst + 2] + 1;
        depth = q.CommittedRayT() * -d.z; // d is unit length in camera space, so -d.z is the forward component

        uint mi = instances[inst + 2] * 24;
        albedo = float3(materials[mi], materials[mi + 1], materials[mi + 2]);
        uint texBase = uint(materials[mi + 10]);
        if (texBase > 0)
        {
            float3 p0 = transformPoint(instances, inst + 4, vertex(indices[tri] + vo));
            float3 p1 = transformPoint(instances, inst + 4, vertex(indices[tri + 1] + vo));
            float3 p2 = transformPoint(instances, inst + 4, vertex(indices[tri + 2] + vo));
            float3 e1 = p1 - p0;
            float3 e2 = p2 - p0;
            float3 e3 = org + ray.Direction * q.CommittedRayT() - p0;
            float d11 = dot(e1, e1);
            float d12 = dot(e1, e2);
            float d22 = dot(e2, e2);
            float den = max(d11 * d22 - d12 * d12, 1.0e-20);
            float b1 = (d22 * dot(e3, e1) - d12 * dot(e3, e2)) / den;
            float b2 = (d11 * dot(e3, e2) - d12 * dot(e3, e1)) / den;
            float2 uv0 = float2(uvs[2 * (indices[tri] + vo)], uvs[2 * (indices[tri] + vo) + 1]);
            float2 uv1 = float2(uvs[2 * (indices[tri + 1] + vo)], uvs[2 * (indices[tri + 1] + vo) + 1]);
            float2 uv2 = float2(uvs[2 * (indices[tri + 2] + vo)], uvs[2 * (indices[tri + 2] + vo) + 1]);
            float2 uv = uv0 + b1 * (uv1 - uv0) + b2 * (uv2 - uv0);
            uint ti = (texBase - 1) * 4;
            albedo *= bilinear(texInfo[ti], texInfo[ti + 1], texInfo[ti + 2], uv);
        }
    }

    // Coverage: a 4x4 stratified grid inside the pixel, so an edge gets partial alpha.
    float cover = 0.0;
    for (uint k = 0; k < 16; k++)
    {
        float2 sp = float2(tid.x + (k % 4 + 0.5) / 4.0, tid.y + (k / 4 + 0.5) / 4.0);
        float3 sdir;
        pixelDir(sp, w, h, t, aspect, sdir);
        RayDesc sr;
        sr.Origin = org;
        sr.Direction = normalize(sdir);
        sr.TMin = 0.0;
        sr.TMax = 1.0e30;
        // Follow the ray through translucent surfaces: what is left is the light that reaches the camera.
        float seen = 0.0;
        float through = 1.0;
        for (uint layer = 0; layer < 8 && through > 0.0; layer++)
        {
            RayQuery<RAY_FLAG_FORCE_OPAQUE> sq;
            sq.TraceRayInline(scene, 0, 0xFF, sr);
            while (sq.Proceed()) { }
            if (sq.CommittedStatus() != COMMITTED_TRIANGLE_HIT)
                break;
            float op = opacityAt(sq.CommittedInstanceIndex(), sq.CommittedPrimitiveIndex(), sq.CommittedTriangleBarycentrics());
            seen += through * op;
            through *= 1.0 - op;
            sr.Origin = sr.Origin + sr.Direction * (sq.CommittedRayT() + 1.0e-4);
        }
        cover += seen;
    }

    uint pixel = tid.y * w + tid.x;
    coverage[pixel] = cover / 16.0;
    albedoDepth[4 * pixel] = albedo.x;
    albedoDepth[4 * pixel + 1] = albedo.y;
    albedoDepth[4 * pixel + 2] = albedo.z;
    albedoDepth[4 * pixel + 3] = depth;
    objectIds[pixel] = id;
    materialIds[pixel] = matId;
}
