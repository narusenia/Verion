// Adaptive sampling (REQ-ACC-007): queues the pixels that still take samples (pixelActive in
// pt_core.slang) for the next sample.
#include "include/wf_state.slang"

[shader("compute")]
[numthreads(8, 8, 1)]
void wf_select(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= params[0] || tid.y >= params[1])
        return;
    uint p = tid.y * params[0] + tid.x;
    if (pixelActive(p))
    {
        uint slot;
        InterlockedAdd(counts[0], 1u, slot);
        queueOut[slot] = p;
    }
}
