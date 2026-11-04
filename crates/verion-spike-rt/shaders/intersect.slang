// Single-triangle ray intersection via inline ray query (Slang -> MSL spike).
[[vk::binding(0, 0)]] RaytracingAccelerationStructure scene;
RWStructuredBuffer<float> hitT;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    RayDesc ray;
    ray.Origin = float3(0.25, 0.25, -1.0);
    ray.Direction = float3(0.0, 0.0, 1.0);
    ray.TMin = 0.0;
    ray.TMax = 100.0;

    RayQuery<RAY_FLAG_FORCE_OPAQUE> q;
    q.TraceRayInline(scene, 0, 0xFF, ray);
    while (q.Proceed()) { }
    hitT[tid.x] = (q.CommittedStatus() == COMMITTED_TRIANGLE_HIT) ? q.CommittedRayT() : -1.0;
}
