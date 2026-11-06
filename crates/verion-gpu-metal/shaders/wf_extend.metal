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
            

#line 15 "shaders/include/wf_state.slang"
struct KernelContext_0
{
    uint device* params_0;
    uint device* counts_0;
    uint device* queueIn_0;
    uint device* state_0;
    metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_0;
    uint device* hits_0;
};


#line 95
uint queuedPath_0(uint i_0, uint depth_0, KernelContext_0 thread* kernelContext_0)
{

#line 95
    bool _S1;

#line 95
    if(depth_0 == 0U)
    {

#line 95
        _S1 = kernelContext_0->params_0[int(32)] == 0U;

#line 95
    }
    else
    {

#line 95
        _S1 = false;

#line 95
    }

#line 95
    uint _S2;

#line 95
    if(_S1)
    {

#line 95
        _S2 = i_0;

#line 95
    }
    else
    {

#line 95
        _S2 = kernelContext_0->queueIn_0[i_0];

#line 95
    }

#line 95
    return _S2;
}


#line 67 "shaders/include/pt_core.slang"
uint pcg_0(uint v_0)
{
    uint s_0 = v_0 * 747796405U + 2891336453U;
    uint w_0 = ((s_0 >> ((s_0 >> 28U) + 4U)) ^ s_0) * 277803737U;
    return (w_0 >> 22U) ^ w_0;
}


#line 84
float pf_0(uint i_1, KernelContext_0 thread* kernelContext_1)
{

#line 84
    return (as_type<float>((kernelContext_1->params_0[i_1])));
}


#line 74
struct Rng_0
{
    uint state_1;
};


#line 77
float Rng_next_0(Rng_0 thread* this_0)
{
    uint _S3 = pcg_0(this_0->state_1);

#line 79
    this_0->state_1 = _S3;
    return float(_S3 >> 8U) * 5.9604644775390625e-08f;
}


#line 459
struct Parts_0
{
    float3 total_0;
    float3 directDiffuse_0;
    float3 indirectDiffuse_0;
    float3 specular_0;
    float3 transmission_0;
    float3 emission_0;
};


#line 536
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
    bool gi_0;
    bool restir_0;
    float qPrev_0;
    float visLit_0;
    float visTotal_0;
    Parts_0 parts_0;
};


#line 564
PathState_0 generatePathFor_0(uint px_0, uint py_0, uint sample_0, KernelContext_0 thread* kernelContext_2)
{
    uint w_1 = kernelContext_2->params_0[int(0)];
    uint h_0 = kernelContext_2->params_0[int(1)];

    thread Rng_0 rng_1;
    (&rng_1)->state_1 = pcg_0((py_0 * w_1 + px_0) ^ (pcg_0(sample_0 * 2654435769U + 2135587861U)));

#line 570
    float _S4 = pf_0(2U, kernelContext_2);

    float _S5 = float(w_1);

#line 572
    float _S6 = float(h_0);

#line 572
    float aspect_0 = _S5 / _S6;
    float _S7 = float(px_0);

#line 573
    float _S8 = Rng_next_0(&rng_1);

#line 573
    float _S9 = 2.0f * (_S7 + _S8) / _S5 - 1.0f;

#line 573
    float _S10 = pf_0(39U, kernelContext_2);

#line 573
    float u_0 = (_S9 + _S10) * aspect_0 * _S4;
    float _S11 = float(py_0);

#line 574
    float _S12 = Rng_next_0(&rng_1);

#line 574
    float _S13 = 1.0f - 2.0f * (_S11 + _S12) / _S6;

#line 574
    float _S14 = pf_0(40U, kernelContext_2);
    float3 _S15 = float3(u_0, (_S13 + _S14) * _S4, -1.0f);

#line 575
    float _S16 = pf_0(4U, kernelContext_2);

#line 575
    float3 focal_0 = _S15 * float3(_S16) ;

#line 575
    float _S17 = pf_0(3U, kernelContext_2);
    float _S18 = Rng_next_0(&rng_1);

#line 576
    float lensR_0 = _S17 * sqrt(_S18);
    float _S19 = Rng_next_0(&rng_1);

#line 577
    float lensA_0 = 6.2831854820251465f * _S19;
    float _S20 = lensR_0 * cos(lensA_0);

#line 578
    float _S21 = lensR_0 * sin(lensA_0);
    float3 _S22 = normalize(focal_0 - float3(_S20, _S21, 0.0f));
    thread PathState_0 s_1;

#line 580
    uint r_0 = 0U;
    for(;;)
    {

#line 581
        if(r_0 < 3U)
        {
        }
        else
        {

#line 581
            break;
        }
        uint _S23 = 4U * r_0;

#line 583
        uint _S24 = 8U + _S23;

#line 583
        uint _S25 = 9U + _S23;

#line 583
        uint _S26 = 10U + _S23;

#line 583
        (&s_1)->org_0[r_0] = (as_type<float>((kernelContext_2->params_0[_S24]))) * _S20 + (as_type<float>((kernelContext_2->params_0[_S25]))) * _S21 + (as_type<float>((kernelContext_2->params_0[_S26]))) * 0.0f + (as_type<float>((kernelContext_2->params_0[11U + _S23])));
        (&s_1)->dir_0[r_0] = (as_type<float>((kernelContext_2->params_0[_S24]))) * _S22.x + (as_type<float>((kernelContext_2->params_0[_S25]))) * _S22.y + (as_type<float>((kernelContext_2->params_0[_S26]))) * _S22.z;

#line 581
        r_0 = r_0 + 1U;

#line 581
    }

#line 586
    (&s_1)->dir_0 = normalize((&s_1)->dir_0);
    (&s_1)->thr_0 = float3(1.0f) ;
    (&s_1)->rng_0 = (&rng_1)->state_1;
    (&s_1)->cls_0 = 0U;
    (&s_1)->chan_0 = int(-1);
    (&s_1)->pathLen_0 = 0.0f;
    (&s_1)->misPrev_0 = false;
    (&s_1)->restir_0 = false;
    (&s_1)->gi_0 = false;
    (&s_1)->qPrev_0 = 0.0f;
    (&s_1)->visLit_0 = 0.0f;
    (&s_1)->visTotal_0 = 0.0f;
    float3 _S27 = float3(0.0f) ;

#line 598
    (&(&s_1)->parts_0)->total_0 = _S27;

#line 598
    (&(&s_1)->parts_0)->directDiffuse_0 = _S27;

#line 598
    (&(&s_1)->parts_0)->indirectDiffuse_0 = _S27;

#line 598
    (&(&s_1)->parts_0)->specular_0 = _S27;

#line 598
    (&(&s_1)->parts_0)->transmission_0 = _S27;

#line 598
    (&(&s_1)->parts_0)->emission_0 = _S27;
    return s_1;
}


#line 1439
PathState_0 generatePath_0(uint px_1, uint py_1, KernelContext_0 thread* kernelContext_3)
{

#line 1439
    PathState_0 _S28 = generatePathFor_0(px_1, py_1, kernelContext_3->params_0[int(6)], kernelContext_3);

#line 1439
    return _S28;
}


#line 25 "shaders/include/wf_state.slang"
uint pathCount_0(KernelContext_0 thread* kernelContext_4)
{

#line 25
    return kernelContext_4->params_0[int(31)];
}

float getF_0(uint f_0, uint p_0, KernelContext_0 thread* kernelContext_5)
{

#line 28
    uint _S29 = pathCount_0(kernelContext_5);

#line 28
    return (as_type<float>((*(kernelContext_5->state_0+(f_0 * _S29 + p_0)))));
}


#line 30
float3 get3_0(uint f_1, uint p_1, KernelContext_0 thread* kernelContext_6)
{

#line 30
    float _S30 = getF_0(f_1, p_1, kernelContext_6);

#line 30
    float _S31 = getF_0(f_1 + 1U, p_1, kernelContext_6);

#line 30
    float _S32 = getF_0(f_1 + 2U, p_1, kernelContext_6);

#line 30
    return float3(_S30, _S31, _S32);
}


#line 555 "shaders/include/pt_core.slang"
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


#line 602 "shaders/include/pt_core.slang"
Hit_0 traceClosest_0(float3 org_1, float3 dir_1, KernelContext_0 thread* kernelContext_7)
{
    thread RayDesc_0 ray_0;
    (&ray_0)->Origin_0 = org_1;
    (&ray_0)->Direction_0 = dir_1;
    (&ray_0)->TMin_0 = 0.0f;
    (&ray_0)->TMax_0 = 1.00000001504746622e+30f;
    thread raytracing::intersection_query<raytracing::triangle_data, raytracing::instancing> q_0;
    (&q_0)->reset({ (ray_0.Origin_0), (ray_0.Direction_0), (ray_0.TMin_0), (ray_0.TMax_0) }, (kernelContext_7->scene_0), (255U), _slang_ray_flags_to_intersection_params((1U)));
    for(;;)
    {

#line 611
        bool _S33 = ((&q_0)->next());

#line 611
        if(_S33)
        {
        }
        else
        {

#line 611
            break;
        }

#line 611
    }
    thread Hit_0 h_1;
    uint _S34 = (_slang_committed_intersection_type_to_uint((&q_0)->get_committed_intersection_type()));

#line 613
    bool _S35 = _S34 == 1U;

#line 613
    (&h_1)->hit_0 = _S35;

#line 613
    uint _S36;
    if(_S35)
    {

#line 614
        uint _S37 = ((&q_0)->get_committed_instance_id());

#line 614
        _S36 = _S37;

#line 614
    }
    else
    {

#line 614
        _S36 = 0U;

#line 614
    }

#line 614
    (&h_1)->inst_0 = _S36;
    if((&h_1)->hit_0)
    {

#line 615
        uint _S38 = ((&q_0)->get_committed_primitive_id());

#line 615
        _S36 = _S38;

#line 615
    }
    else
    {

#line 615
        _S36 = 0U;

#line 615
    }

#line 615
    (&h_1)->prim_0 = _S36;

#line 615
    float _S39;
    if((&h_1)->hit_0)
    {

#line 616
        float _S40 = ((&q_0)->get_committed_distance());

#line 616
        _S39 = _S40;

#line 616
    }
    else
    {

#line 616
        _S39 = 0.0f;

#line 616
    }

#line 616
    (&h_1)->t_0 = _S39;
    return h_1;
}


#line 6 "shaders/wf_extend.slang"
[[kernel]] void wf_extend(uint3 tid_0 [[thread_position_in_grid]], uint device* params_1 [[buffer(6)]], uint device* counts_1 [[buffer(24)]], uint device* queueIn_1 [[buffer(22)]], uint device* state_2 [[buffer(20)]], metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_1 [[buffer(0)]], uint device* hits_1 [[buffer(21)]])
{

#line 6
    thread KernelContext_0 kernelContext_8;

#line 6
    (&kernelContext_8)->params_0 = params_1;

#line 6
    (&kernelContext_8)->counts_0 = counts_1;

#line 6
    (&kernelContext_8)->queueIn_0 = queueIn_1;

#line 6
    (&kernelContext_8)->state_0 = state_2;

#line 6
    (&kernelContext_8)->scene_0 = scene_1;

#line 6
    (&kernelContext_8)->hits_0 = hits_1;

    uint d_0 = params_1[int(30)];
    uint i_2 = tid_0.x;
    if(i_2 >= (*(counts_1+d_0)))
    {

#line 11
        return;
    }

#line 11
    uint _S41 = queuedPath_0(i_2, d_0, &kernelContext_8);

#line 11
    float3 org_2;

#line 11
    float3 dir_2;


    if(d_0 == 0U)
    {
        uint _S42 = _S41 % (&kernelContext_8)->params_0[int(0)];

#line 16
        uint _S43 = _S41 / (&kernelContext_8)->params_0[int(0)];

#line 16
        PathState_0 _S44 = generatePath_0(_S42, _S43, &kernelContext_8);

#line 16
        org_2 = _S44.org_0;

#line 16
        dir_2 = _S44.dir_0;

#line 14
    }
    else
    {

#line 14
        float3 _S45 = get3_0(0U, _S41, &kernelContext_8);

#line 14
        float3 _S46 = get3_0(3U, _S41, &kernelContext_8);

#line 14
        org_2 = _S45;

#line 14
        dir_2 = _S46;

#line 14
    }

#line 14
    Hit_0 _S47 = traceClosest_0(org_2, dir_2, &kernelContext_8);

#line 26
    uint _S48 = 4U * _S41;

#line 26
    uint device* _S49 = (&kernelContext_8)->hits_0+_S48;

#line 26
    uint _S50;

#line 26
    if(_S47.hit_0)
    {

#line 26
        _S50 = 1U;

#line 26
    }
    else
    {

#line 26
        _S50 = 0U;

#line 26
    }

#line 26
    *_S49 = _S50;
    *((&kernelContext_8)->hits_0+(_S48 + 1U)) = _S47.inst_0;
    *((&kernelContext_8)->hits_0+(_S48 + 2U)) = _S47.prim_0;
    *((&kernelContext_8)->hits_0+(_S48 + 3U)) = (as_type<uint>((_S47.t_0)));
    return;
}

