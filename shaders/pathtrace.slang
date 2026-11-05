// Megakernel path tracer: one thread runs whole paths, params[35] samples of its pixel in a row
// from sample params[6] (M1 items 6b and 6c). Only this thread touches its pixel's sums, so the
// image equals one dispatch per sample. The path code lives in include/pt_core.slang, shared with the wavefront kernels.

#include "include/pt_core.slang"

[shader("compute")]
[numthreads(8, 8, 1)]
void pathtrace(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= params[0] || tid.y >= params[1])
        return;
    uint pixel = tid.y * params[0] + tid.x;
    for (uint k = 0; k < params[35]; k++)
    {
        if (params[32] != 0 && !pixelActive(pixel))
            return; // adaptive sampling: converged
        PathState st = generatePathFor(tid.x, tid.y, params[6] + k);
        for (uint depth = 0; depth < params[7]; depth++)
        {
            if (!shadePath(st, traceClosest(st.org, st.dir), depth, pixel))
                break;
        }
        finishPath(st, pixel);
    }
}
