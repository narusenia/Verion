// Wavefront stage 2: closest hit for every live path of the depth.
#include "include/wf_state.slang"

[shader("compute")]
[numthreads(64, 1, 1)]
void wf_extend(uint3 tid : SV_DispatchThreadID)
{
    uint d = params[30];
    uint i = tid.x;
    if (i >= counts[d])
        return;
    uint p = queuedPath(i, d);
    float3 org, dir;
    if (d == 0)
    {
        PathState s = generatePath(p % params[0], p / params[0]);
        org = s.org;
        dir = s.dir;
    }
    else
    {
        org = get3(0, p);
        dir = get3(3, p);
    }
    Hit h = traceClosest(org, dir);
    hits[4 * p] = h.hit ? 1u : 0u;
    hits[4 * p + 1] = h.inst;
    hits[4 * p + 2] = h.prim;
    hits[4 * p + 3] = asuint(h.t);
}
