// Adaptive sampling (REQ-ACC-007): queues the pixels whose mean is still uncertain for the next
// sample. A pixel stops once it has the minimum samples (params[34]) and the standard error of its
// luminance is within params[33] of its mean (with a floor, so near-black pixels can stop too).
// Stopping on the pixel's own estimate biases it slightly, so adaptive renders are not physical.
#include "include/wf_state.slang"

[shader("compute")]
[numthreads(8, 8, 1)]
void wf_select(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= params[0] || tid.y >= params[1])
        return;
    uint p = tid.y * params[0] + tid.x;
    float n = pixelStats[3 * p];
    bool active = n < float(params[34]);
    if (!active)
    {
        float mean = pixelStats[3 * p + 1] / n;
        float var = max(pixelStats[3 * p + 2] / n - mean * mean, 0.0) * n / (n - 1.0);
        active = sqrt(var / n) > pf(33) * max(mean, 0.05);
    }
    if (active)
    {
        uint slot;
        InterlockedAdd(counts[0], 1u, slot);
        queueOut[slot] = p;
    }
}
