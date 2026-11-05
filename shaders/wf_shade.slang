// Wavefront stage 3: shade the hit (light sampling traces its shadow rays inline), then either
// append the path to the next depth's queue (compaction) or add it to the pixel's sums.
#include "include/wf_state.slang"

[shader("compute")]
[numthreads(64, 1, 1)]
void wf_shade(uint3 tid : SV_DispatchThreadID)
{
    uint d = params[30];
    uint i = tid.x;
    if (i >= counts[d])
        return;
    uint p = queuedPath(i, d);
    PathState st = loadPath(p, d);
    Hit h;
    h.hit = hits[4 * p] != 0;
    h.inst = hits[4 * p + 1];
    h.prim = hits[4 * p + 2];
    h.t = asfloat(hits[4 * p + 3]);
    if (shadePath(st, h, d, p) && d + 1 < params[7])
    {
        storePath(st, p);
        uint slot;
        InterlockedAdd(counts[d + 1], 1u, slot); // compaction: live paths pack the next queue
        queueOut[slot] = p;
    }
    else
        finishPath(st, p);
}
