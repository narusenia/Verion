#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

            raytracing::intersection_params _slang_ray_flags_to_intersection_params(uint flags){
                raytracing::intersection_params params;
                if (flags & 0x01) /* RAY_FLAG_FORCE_OPAQUE */
                    params.force_opacity(raytracing::forced_opacity::opaque);
                if (flags & 0x02) /* RAY_FLAG_FORCE_NON_OPAQUE */
                    params.force_opacity(raytracing::forced_opacity::non_opaque);
                if (flags & 0x10) /* RAY_FLAG_CULL_BACK_FACING_TRIANGLES */
                    params.set_triangle_cull_mode(raytracing::triangle_cull_mode::back);
                if (flags & 0x20) /* RAY_FLAG_CULL_FRONT_FACING_TRIANGLES */
                    params.set_triangle_cull_mode(raytracing::triangle_cull_mode::front);
                if (flags & 0x40) /* RAY_FLAG_CULL_OPAQUE */
                    params.set_opacity_cull_mode(raytracing::opacity_cull_mode::opaque);
                if (flags & 0x80) /* RAY_FLAG_CULL_NON_OPAQUE */
                    params.set_opacity_cull_mode(raytracing::opacity_cull_mode::non_opaque);
                if (flags & 0x100) /* RAY_FLAG_SKIP_TRIANGLES */
                    params.set_geometry_cull_mode(raytracing::geometry_cull_mode::triangle);
                if (flags & 0x200) /* RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES */
                    params.set_geometry_cull_mode(raytracing::geometry_cull_mode::bounding_box);
                return params;
            }
        

                uint _slang_committed_intersection_type_to_uint(raytracing::intersection_type type){
                    switch(type){
                        case raytracing::intersection_type::none:
                            return 0; /* COMMITTED_NOTHING */
                        case raytracing::intersection_type::triangle:
                            return 1; /* COMMITTED_TRIANGLE_HIT */
                        case raytracing::intersection_type::bounding_box:
                            return 2; /* COMMITTED_PROCEDURAL_PRIMITIVE_HIT */
                        default:
                            return 0xFFFFFFFF; // Invalid value to indicate error case, should never be returned by the API
                    }
                }
            

#line 12 "shaders/include/wf_state.slang"
struct KernelContext_0
{
    uint device* params_0;
    uint device* counts_0;
    uint device* queueIn_0;
    uint device* state_0;
    metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_0;
    uint device* hits_0;
};


#line 89
uint queuedPath_0(uint i_0, uint depth_0, KernelContext_0 thread* kernelContext_0)
{

#line 89
    uint _S1;

#line 89
    if(depth_0 == 0U)
    {

#line 89
        _S1 = i_0;

#line 89
    }
    else
    {

#line 89
        _S1 = kernelContext_0->queueIn_0[i_0];

#line 89
    }

#line 89
    return _S1;
}


#line 47 "shaders/include/pt_core.slang"
uint pcg_0(uint v_0)
{
    uint s_0 = v_0 * 747796405U + 2891336453U;
    uint w_0 = ((s_0 >> ((s_0 >> 28U) + 4U)) ^ s_0) * 277803737U;
    return (w_0 >> 22U) ^ w_0;
}


#line 64
float pf_0(uint i_1, KernelContext_0 thread* kernelContext_1)
{

#line 64
    return (as_type<float>((kernelContext_1->params_0[i_1])));
}


#line 54
struct Rng_0
{
    uint state_1;
};


#line 57
float Rng_next_0(Rng_0 thread* this_0)
{
    uint _S2 = pcg_0(this_0->state_1);

#line 59
    this_0->state_1 = _S2;
    return float(_S2 >> 8U) * 5.9604644775390625e-08f;
}


#line 439
struct Parts_0
{
    float3 total_0;
    float3 directDiffuse_0;
    float3 indirectDiffuse_0;
    float3 specular_0;
    float3 transmission_0;
    float3 emission_0;
};


#line 516
struct PathState_0
{
    float3 org_0;
    float3 dir_0;
    float3 thr_0;
    uint rng_0;
    uint cls_0;
    int chan_0;
    float pathLen_0;
    bool misPrev_0;
    float qPrev_0;
    float visLit_0;
    float visTotal_0;
    Parts_0 parts_0;
};


#line 542
PathState_0 generatePath_0(uint px_0, uint py_0, KernelContext_0 thread* kernelContext_2)
{
    uint w_1 = kernelContext_2->params_0[int(0)];
    uint h_0 = kernelContext_2->params_0[int(1)];

    thread Rng_0 rng_1;
    (&rng_1)->state_1 = pcg_0((py_0 * w_1 + px_0) ^ (pcg_0(kernelContext_2->params_0[int(6)] * 2654435769U + 2135587861U)));

#line 548
    float _S3 = pf_0(2U, kernelContext_2);

    float _S4 = float(w_1);

#line 550
    float _S5 = float(h_0);

#line 550
    float aspect_0 = _S4 / _S5;
    float _S6 = float(px_0);

#line 551
    float _S7 = Rng_next_0(&rng_1);

#line 551
    float u_0 = (2.0f * (_S6 + _S7) / _S4 - 1.0f) * aspect_0 * _S3;
    float _S8 = float(py_0);

#line 552
    float _S9 = Rng_next_0(&rng_1);
    float3 _S10 = float3(u_0, (1.0f - 2.0f * (_S8 + _S9) / _S5) * _S3, -1.0f);

#line 553
    float _S11 = pf_0(4U, kernelContext_2);

#line 553
    float3 focal_0 = _S10 * float3(_S11) ;

#line 553
    float _S12 = pf_0(3U, kernelContext_2);
    float _S13 = Rng_next_0(&rng_1);

#line 554
    float lensR_0 = _S12 * sqrt(_S13);
    float _S14 = Rng_next_0(&rng_1);

#line 555
    float lensA_0 = 6.2831854820251465f * _S14;
    float _S15 = lensR_0 * cos(lensA_0);

#line 556
    float _S16 = lensR_0 * sin(lensA_0);
    float3 _S17 = normalize(focal_0 - float3(_S15, _S16, 0.0f));
    thread PathState_0 s_1;

#line 558
    uint r_0 = 0U;
    for(;;)
    {

#line 559
        if(r_0 < 3U)
        {
        }
        else
        {

#line 559
            break;
        }
        uint _S18 = 4U * r_0;

#line 561
        uint _S19 = 8U + _S18;

#line 561
        uint _S20 = 9U + _S18;

#line 561
        uint _S21 = 10U + _S18;

#line 561
        (&s_1)->org_0[r_0] = (as_type<float>((kernelContext_2->params_0[_S19]))) * _S15 + (as_type<float>((kernelContext_2->params_0[_S20]))) * _S16 + (as_type<float>((kernelContext_2->params_0[_S21]))) * 0.0f + (as_type<float>((kernelContext_2->params_0[11U + _S18])));
        (&s_1)->dir_0[r_0] = (as_type<float>((kernelContext_2->params_0[_S19]))) * _S17.x + (as_type<float>((kernelContext_2->params_0[_S20]))) * _S17.y + (as_type<float>((kernelContext_2->params_0[_S21]))) * _S17.z;

#line 559
        r_0 = r_0 + 1U;

#line 559
    }

#line 564
    (&s_1)->dir_0 = normalize((&s_1)->dir_0);
    (&s_1)->thr_0 = float3(1.0f) ;
    (&s_1)->rng_0 = (&rng_1)->state_1;
    (&s_1)->cls_0 = 0U;
    (&s_1)->chan_0 = int(-1);
    (&s_1)->pathLen_0 = 0.0f;
    (&s_1)->misPrev_0 = false;
    (&s_1)->qPrev_0 = 0.0f;
    (&s_1)->visLit_0 = 0.0f;
    (&s_1)->visTotal_0 = 0.0f;
    float3 _S22 = float3(0.0f) ;

#line 574
    (&(&s_1)->parts_0)->total_0 = _S22;

#line 574
    (&(&s_1)->parts_0)->directDiffuse_0 = _S22;

#line 574
    (&(&s_1)->parts_0)->indirectDiffuse_0 = _S22;

#line 574
    (&(&s_1)->parts_0)->specular_0 = _S22;

#line 574
    (&(&s_1)->parts_0)->transmission_0 = _S22;

#line 574
    (&(&s_1)->parts_0)->emission_0 = _S22;
    return s_1;
}


#line 22 "shaders/include/wf_state.slang"
uint pathCount_0(KernelContext_0 thread* kernelContext_3)
{

#line 22
    return kernelContext_3->params_0[int(31)];
}

float getF_0(uint f_0, uint p_0, KernelContext_0 thread* kernelContext_4)
{

#line 25
    uint _S23 = pathCount_0(kernelContext_4);

#line 25
    return (as_type<float>((*(kernelContext_4->state_0+(f_0 * _S23 + p_0)))));
}


#line 27
float3 get3_0(uint f_1, uint p_1, KernelContext_0 thread* kernelContext_5)
{

#line 27
    float _S24 = getF_0(f_1, p_1, kernelContext_5);

#line 27
    float _S25 = getF_0(f_1 + 1U, p_1, kernelContext_5);

#line 27
    float _S26 = getF_0(f_1 + 2U, p_1, kernelContext_5);

#line 27
    return float3(_S24, _S25, _S26);
}


#line 533 "shaders/include/pt_core.slang"
struct Hit_0
{
    bool hit_0;
    uint inst_0;
    uint prim_0;
    float t_0;
};


#line 20995 "hlsl.meta.slang"
struct RayDesc_0
{
    float3 Origin_0;
    float TMin_0;
    float3 Direction_0;
    float TMax_0;
};


#line 578 "shaders/include/pt_core.slang"
Hit_0 traceClosest_0(float3 org_1, float3 dir_1, KernelContext_0 thread* kernelContext_6)
{
    thread RayDesc_0 ray_0;
    (&ray_0)->Origin_0 = org_1;
    (&ray_0)->Direction_0 = dir_1;
    (&ray_0)->TMin_0 = 0.0f;
    (&ray_0)->TMax_0 = 1.00000001504746622e+30f;
    thread raytracing::intersection_query<raytracing::triangle_data, raytracing::instancing> q_0;
    (&q_0)->reset({ (ray_0.Origin_0), (ray_0.Direction_0), (ray_0.TMin_0), (ray_0.TMax_0) }, (kernelContext_6->scene_0), (255U), _slang_ray_flags_to_intersection_params((1U)));
    for(;;)
    {

#line 587
        bool _S27 = ((&q_0)->next());

#line 587
        if(_S27)
        {
        }
        else
        {

#line 587
            break;
        }

#line 587
    }
    thread Hit_0 h_1;
    uint _S28 = (_slang_committed_intersection_type_to_uint((&q_0)->get_committed_intersection_type()));

#line 589
    bool _S29 = _S28 == 1U;

#line 589
    (&h_1)->hit_0 = _S29;

#line 589
    uint _S30;
    if(_S29)
    {

#line 590
        uint _S31 = ((&q_0)->get_committed_instance_id());

#line 590
        _S30 = _S31;

#line 590
    }
    else
    {

#line 590
        _S30 = 0U;

#line 590
    }

#line 590
    (&h_1)->inst_0 = _S30;
    if((&h_1)->hit_0)
    {

#line 591
        uint _S32 = ((&q_0)->get_committed_primitive_id());

#line 591
        _S30 = _S32;

#line 591
    }
    else
    {

#line 591
        _S30 = 0U;

#line 591
    }

#line 591
    (&h_1)->prim_0 = _S30;

#line 591
    float _S33;
    if((&h_1)->hit_0)
    {

#line 592
        float _S34 = ((&q_0)->get_committed_distance());

#line 592
        _S33 = _S34;

#line 592
    }
    else
    {

#line 592
        _S33 = 0.0f;

#line 592
    }

#line 592
    (&h_1)->t_0 = _S33;
    return h_1;
}


#line 6 "shaders/wf_extend.slang"
[[kernel]] void wf_extend(uint3 tid_0 [[thread_position_in_grid]], uint device* params_1 [[buffer(6)]], uint device* counts_1 [[buffer(22)]], uint device* queueIn_1 [[buffer(20)]], uint device* state_2 [[buffer(18)]], metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_1 [[buffer(0)]], uint device* hits_1 [[buffer(19)]])
{

#line 6
    thread KernelContext_0 kernelContext_7;

#line 6
    (&kernelContext_7)->params_0 = params_1;

#line 6
    (&kernelContext_7)->counts_0 = counts_1;

#line 6
    (&kernelContext_7)->queueIn_0 = queueIn_1;

#line 6
    (&kernelContext_7)->state_0 = state_2;

#line 6
    (&kernelContext_7)->scene_0 = scene_1;

#line 6
    (&kernelContext_7)->hits_0 = hits_1;

    uint d_0 = params_1[int(30)];
    uint i_2 = tid_0.x;
    if(i_2 >= (*(counts_1+d_0)))
    {

#line 11
        return;
    }

#line 11
    uint _S35 = queuedPath_0(i_2, d_0, &kernelContext_7);

#line 11
    float3 org_2;

#line 11
    float3 dir_2;


    if(d_0 == 0U)
    {
        uint _S36 = _S35 % (&kernelContext_7)->params_0[int(0)];

#line 16
        uint _S37 = _S35 / (&kernelContext_7)->params_0[int(0)];

#line 16
        PathState_0 _S38 = generatePath_0(_S36, _S37, &kernelContext_7);

#line 16
        org_2 = _S38.org_0;

#line 16
        dir_2 = _S38.dir_0;

#line 14
    }
    else
    {

#line 14
        float3 _S39 = get3_0(0U, _S35, &kernelContext_7);

#line 14
        float3 _S40 = get3_0(3U, _S35, &kernelContext_7);

#line 14
        org_2 = _S39;

#line 14
        dir_2 = _S40;

#line 14
    }

#line 14
    Hit_0 _S41 = traceClosest_0(org_2, dir_2, &kernelContext_7);

#line 26
    uint _S42 = 4U * _S35;

#line 26
    uint device* _S43 = (&kernelContext_7)->hits_0+_S42;

#line 26
    uint _S44;

#line 26
    if(_S41.hit_0)
    {

#line 26
        _S44 = 1U;

#line 26
    }
    else
    {

#line 26
        _S44 = 0U;

#line 26
    }

#line 26
    *_S43 = _S44;
    *((&kernelContext_7)->hits_0+(_S42 + 1U)) = _S41.inst_0;
    *((&kernelContext_7)->hits_0+(_S42 + 2U)) = _S41.prim_0;
    *((&kernelContext_7)->hits_0+(_S42 + 3U)) = (as_type<uint>((_S41.t_0)));
    return;
}

