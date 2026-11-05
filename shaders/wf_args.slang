// Wavefront: indirect dispatch size for the depth's queue, so the CPU never waits for the count.
// At depth 0 it also starts a sample: the later queues are empty, and every pixel's path is live
// unless adaptive sampling filled the depth-0 queue (wf_select). At the last depth it clears that
// queue's count for the next sample's wf_select (counts[0] is no longer read in this sample).
#include "include/wf_state.slang"

[shader("compute")]
[numthreads(1, 1, 1)]
void wf_args(uint3 tid : SV_DispatchThreadID)
{
    uint d = params[30];
    if (d == 0)
    {
        if (params[32] == 0)
            counts[0] = pathCount();
        counts[params[7] + 1] = counts[0]; // pixels sampled this time, read back by the host
        for (uint k = 1; k <= params[7]; k++)
            counts[k] = 0;
    }
    args[3 * d] = (counts[d] + WF_GROUP - 1) / WF_GROUP;
    args[3 * d + 1] = 1;
    args[3 * d + 2] = 1;
    if (d + 1 == params[7] && params[32] != 0)
        counts[0] = 0;
}
