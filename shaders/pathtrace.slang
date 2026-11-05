// Megakernel path tracer: one thread runs a whole path, one sample per pixel per dispatch
// (M1 items 6b and 6c). The path code lives in include/pt_core.slang, shared with the wavefront kernels.

#include "include/pt_core.slang"

[shader("compute")]
[numthreads(8, 8, 1)]
void pathtrace(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= params[0] || tid.y >= params[1])
        return;
    uint pixel = tid.y * params[0] + tid.x;
    PathState st = generatePath(tid.x, tid.y);
    for (uint depth = 0; depth < params[7]; depth++)
    {
        if (!shadePath(st, traceClosest(st.org, st.dir), depth, pixel))
            break;
    }
    finishPath(st, pixel);
}
