#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 16 "shaders/include/wf_state.slang"
struct KernelContext_0
{
    uint device* params_0;
    uint device* counts_0;
    uint device* args_0;
};


#line 22
uint pathCount_0(KernelContext_0 thread* kernelContext_0)
{

#line 22
    return kernelContext_0->params_0[int(31)];
}


#line 7 "shaders/wf_args.slang"
[[kernel]] void wf_args(uint3 tid_0 [[thread_position_in_grid]], uint device* params_1 [[buffer(6)]], uint device* counts_1 [[buffer(22)]], uint device* args_1 [[buffer(23)]])
{

#line 7
    thread KernelContext_0 kernelContext_1;

#line 7
    (&kernelContext_1)->params_0 = params_1;

#line 7
    (&kernelContext_1)->counts_0 = counts_1;

#line 7
    (&kernelContext_1)->args_0 = args_1;

    uint d_0 = params_1[int(30)];
    if(d_0 == 0U)
    {
        uint device* _S1 = (&kernelContext_1)->counts_0+int(0);

#line 12
        uint _S2 = pathCount_0(&kernelContext_1);

#line 12
        *_S1 = _S2;

#line 12
        uint k_0 = 1U;
        for(;;)
        {

#line 13
            if(k_0 <= ((&kernelContext_1)->params_0)[int(7)])
            {
            }
            else
            {

#line 13
                break;
            }

#line 14
            *((&kernelContext_1)->counts_0+k_0) = 0U;

#line 13
            k_0 = k_0 + 1U;

#line 13
        }

#line 10
    }

#line 16
    uint _S3 = 3U * d_0;

#line 16
    *((&kernelContext_1)->args_0+_S3) = (*((&kernelContext_1)->counts_0+d_0) + 64U - 1U) / 64U;
    *((&kernelContext_1)->args_0+(_S3 + 1U)) = 1U;
    *((&kernelContext_1)->args_0+(_S3 + 2U)) = 1U;
    return;
}

