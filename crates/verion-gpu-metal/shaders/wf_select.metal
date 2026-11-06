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


#line 84 "shaders/include/pt_core.slang"
float pf_0(uint i_0, KernelContext_0 thread* kernelContext_0)
{

#line 84
    return (as_type<float>((kernelContext_0->params_0[i_0])));
}


#line 1483
bool pixelActive_0(uint p_0, KernelContext_0 thread* kernelContext_1)
{
    uint _S1 = 3U * p_0;

#line 1485
    float device* _S2 = kernelContext_1->pixelStats_0+_S1;

#line 1485
    float n_0 = *_S2;
    if((*_S2) < float(kernelContext_1->params_0[int(34)]))
    {

#line 1487
        return true;
    }

#line 1488
    float mean_0 = *(kernelContext_1->pixelStats_0+(_S1 + 1U)) / n_0;

    float _S3 = sqrt(max(*(kernelContext_1->pixelStats_0+(_S1 + 2U)) / n_0 - mean_0 * mean_0, 0.0f) * n_0 / (n_0 - 1.0f) / n_0);

#line 1490
    float _S4 = pf_0(33U, kernelContext_1);

#line 1490
    return _S3 > (_S4 * max(mean_0, 0.05000000074505806f));
}


#line 7 "shaders/wf_select.slang"
[[kernel]] void wf_select(uint3 tid_0 [[thread_position_in_grid]], uint device* params_1 [[buffer(6)]], float device* pixelStats_1 [[buffer(18)]], uint device* counts_1 [[buffer(24)]], uint device* queueOut_1 [[buffer(23)]])
{

#line 7
    thread KernelContext_0 kernelContext_2;

#line 7
    (&kernelContext_2)->params_0 = params_1;

#line 7
    (&kernelContext_2)->pixelStats_0 = pixelStats_1;

#line 7
    (&kernelContext_2)->counts_0 = counts_1;

#line 7
    (&kernelContext_2)->queueOut_0 = queueOut_1;

    uint _S5 = tid_0.x;

#line 9
    bool _S6;

#line 9
    if(_S5 >= params_1[int(0)])
    {

#line 9
        _S6 = true;

#line 9
    }
    else
    {

#line 9
        _S6 = (tid_0.y) >= ((&kernelContext_2)->params_0)[int(1)];

#line 9
    }

#line 9
    if(_S6)
    {

#line 10
        return;
    }

#line 11
    uint p_1 = tid_0.y * (&kernelContext_2)->params_0[int(0)] + _S5;

#line 11
    bool _S7 = pixelActive_0(p_1, &kernelContext_2);
    if(_S7)
    {

        uint slot_0 = atomic_fetch_add_explicit(((atomic_uint device*)((&kernelContext_2)->counts_0+int(0))), 1U, memory_order_relaxed);
        *((&kernelContext_2)->queueOut_0+slot_0) = p_1;

#line 12
    }

#line 18
    return;
}

