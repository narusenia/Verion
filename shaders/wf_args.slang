// Wavefront: indirect dispatch size for the depth's queue, so the CPU never waits for the count.
// At depth 0 it also starts a sample: every pixel's path is live and the later queues are empty.
#include "include/wf_state.slang"

[shader("compute")]
[numthreads(1, 1, 1)]
void wf_args(uint3 tid : SV_DispatchThreadID)
{
    uint d = params[30];
    if (d == 0)
    {
        counts[0] = pathCount();
        for (uint k = 1; k <= params[7]; k++)
            counts[k] = 0;
    }
    args[3 * d] = (counts[d] + WF_GROUP - 1) / WF_GROUP;
    args[3 * d + 1] = 1;
    args[3 * d + 2] = 1;
}
