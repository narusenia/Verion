#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 17 "shaders/include/wf_state.slang"
struct KernelContext_0
{
    uint device* params_0;
    float device* pixelStats_0;
    uint device* counts_0;
    uint device* queueOut_0;
};


#line 68 "shaders/include/pt_core.slang"
float pf_0(uint i_0, KernelContext_0 thread* kernelContext_0)
{

#line 68
    return (as_type<float>((kernelContext_0->params_0[i_0])));
}


#line 9 "shaders/wf_select.slang"
[[kernel]] void wf_select(uint3 tid_0 [[thread_position_in_grid]], uint device* params_1 [[buffer(6)]], float device* pixelStats_1 [[buffer(18)]], uint device* counts_1 [[buffer(23)]], uint device* queueOut_1 [[buffer(22)]])
{

#line 9
    thread KernelContext_0 kernelContext_1;

#line 9
    (&kernelContext_1)->params_0 = params_1;

#line 9
    (&kernelContext_1)->pixelStats_0 = pixelStats_1;

#line 9
    (&kernelContext_1)->counts_0 = counts_1;

#line 9
    (&kernelContext_1)->queueOut_0 = queueOut_1;

    uint _S1 = tid_0.x;

#line 11
    bool active_0;

#line 11
    if(_S1 >= params_1[int(0)])
    {

#line 11
        active_0 = true;

#line 11
    }
    else
    {

#line 11
        active_0 = (tid_0.y) >= ((&kernelContext_1)->params_0)[int(1)];

#line 11
    }

#line 11
    if(active_0)
    {

#line 12
        return;
    }

#line 13
    uint p_0 = tid_0.y * (&kernelContext_1)->params_0[int(0)] + _S1;
    uint _S2 = 3U * p_0;

#line 14
    float device* _S3 = (&kernelContext_1)->pixelStats_0+_S2;

#line 14
    float n_0 = *_S3;
    bool active_1 = (*_S3) < float((&kernelContext_1)->params_0[int(34)]);
    if(!active_1)
    {
        float mean_0 = *((&kernelContext_1)->pixelStats_0+(_S2 + 1U)) / n_0;

        float _S4 = sqrt(max(*((&kernelContext_1)->pixelStats_0+(_S2 + 2U)) / n_0 - mean_0 * mean_0, 0.0f) * n_0 / (n_0 - 1.0f) / n_0);

#line 20
        float _S5 = pf_0(33U, &kernelContext_1);

#line 20
        active_0 = _S4 > (_S5 * max(mean_0, 0.05000000074505806f));

#line 16
    }
    else
    {

#line 16
        active_0 = active_1;

#line 16
    }

#line 22
    if(active_0)
    {

        uint slot_0 = atomic_fetch_add_explicit(((atomic_uint device*)((&kernelContext_1)->counts_0+int(0))), 1U, memory_order_relaxed);
        *((&kernelContext_1)->queueOut_0+slot_0) = p_0;

#line 22
    }

#line 28
    return;
}

