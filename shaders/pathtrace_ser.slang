// The megakernel as a ray tracing pipeline's ray generation shader, so the closest hit can use
// shader execution reordering (Vulkan only, M4 item 10; see traceClosest under VERION_SER in
// include/pt_core.slang). One thread runs params[35] samples of its pixel in a row, exactly as
// pathtrace.slang does; keep the two loops the same.

#define VERION_SER 1
#include "include/pt_core.slang"

[shader("raygeneration")]
void pathtrace_ser()
{
    uint3 tid = DispatchRaysIndex();
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
