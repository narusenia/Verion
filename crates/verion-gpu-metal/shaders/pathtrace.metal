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
            

#line 1368 "core.meta.slang"
float float_getPi_0()
{

#line 1368
    return 3.1415927410125732f;
}


#line 10545 "hlsl.meta.slang"
float degrees_0(float x_0)
{

#line 10556
    return x_0 * (180.0f / float_getPi_0());
}


#line 29 "shaders/include/pt_core.slang"
struct KernelContext_0
{
    uint device* params_0;
    float device* pixelStats_0;
    metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_0;
    float device* restir_0;
    float device* envPixels_0;
    uint device* instances_0;
    uint device* indices_0;
    float device* positions_0;
    float device* materials_0;
    float device* vnormals_0;
    float device* uvs_0;
    uint device* texInfo_0;
    float device* texels_0;
    uint device* lights_0;
    float device* emitters_0;
    float device* lighting_0;
    float device* emitCdf_0;
    float device* envMarginal_0;
    float device* envCond_0;
    float device* accum_0;
};


#line 86
float pf_0(uint i_0, KernelContext_0 thread* kernelContext_0)
{

#line 86
    return (as_type<float>((kernelContext_0->params_0[i_0])));
}


#line 1532
bool pixelActive_0(uint p_0, KernelContext_0 thread* kernelContext_1)
{
    uint _S1 = 3U * p_0;

#line 1534
    float device* _S2 = kernelContext_1->pixelStats_0+_S1;

#line 1534
    float n_0 = *_S2;
    if((*_S2) < float(kernelContext_1->params_0[int(34)]))
    {

#line 1536
        return true;
    }

#line 1537
    float mean_0 = *(kernelContext_1->pixelStats_0+(_S1 + 1U)) / n_0;

    float _S3 = sqrt(max(*(kernelContext_1->pixelStats_0+(_S1 + 2U)) / n_0 - mean_0 * mean_0, 0.0f) * n_0 / (n_0 - 1.0f) / n_0);

#line 1539
    float _S4 = pf_0(33U, kernelContext_1);

#line 1539
    return _S3 > (_S4 * max(mean_0, 0.05000000074505806f));
}


#line 69
uint pcg_0(uint v_0)
{
    uint s_0 = v_0 * 747796405U + 2891336453U;
    uint w_0 = ((s_0 >> ((s_0 >> 28U) + 4U)) ^ s_0) * 277803737U;
    return (w_0 >> 22U) ^ w_0;
}

struct Rng_0
{
    uint state_0;
};


#line 79
float Rng_next_0(Rng_0 thread* this_0)
{
    uint _S5 = pcg_0(this_0->state_0);

#line 81
    this_0->state_0 = _S5;
    return float(_S5 >> 8U) * 5.9604644775390625e-08f;
}


#line 496
struct Parts_0
{
    float3 total_0;
    float3 directDiffuse_0;
    float3 indirectDiffuse_0;
    float3 specular_0;
    float3 transmission_0;
    float3 emission_0;
};


#line 597
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
    bool restir_1;
    float qPrev_0;
    uint prevInst_0;
    float visLit_0;
    float visTotal_0;
    Parts_0 parts_0;
};


#line 626
PathState_0 generatePathFor_0(uint px_0, uint py_0, uint sample_0, KernelContext_0 thread* kernelContext_2)
{
    uint w_1 = kernelContext_2->params_0[int(0)];
    uint h_0 = kernelContext_2->params_0[int(1)];

    thread Rng_0 rng_1;
    (&rng_1)->state_0 = pcg_0((py_0 * w_1 + px_0) ^ (pcg_0(sample_0 * 2654435769U + 2135587861U)));

#line 632
    float _S6 = pf_0(2U, kernelContext_2);

    float _S7 = float(w_1);

#line 634
    float _S8 = float(h_0);

#line 634
    float aspect_0 = _S7 / _S8;
    float _S9 = float(px_0);

#line 635
    float _S10 = Rng_next_0(&rng_1);

#line 635
    float _S11 = 2.0f * (_S9 + _S10) / _S7 - 1.0f;

#line 635
    float _S12 = pf_0(39U, kernelContext_2);

#line 635
    float u_0 = (_S11 + _S12) * aspect_0 * _S6;
    float _S13 = float(py_0);

#line 636
    float _S14 = Rng_next_0(&rng_1);

#line 636
    float _S15 = 1.0f - 2.0f * (_S13 + _S14) / _S8;

#line 636
    float _S16 = pf_0(40U, kernelContext_2);
    float3 _S17 = float3(u_0, (_S15 + _S16) * _S6, -1.0f);

#line 637
    float _S18 = pf_0(4U, kernelContext_2);

#line 637
    float3 focal_0 = _S17 * float3(_S18) ;

#line 637
    float _S19 = pf_0(3U, kernelContext_2);
    float _S20 = Rng_next_0(&rng_1);

#line 638
    float lensR_0 = _S19 * sqrt(_S20);
    float _S21 = Rng_next_0(&rng_1);

#line 639
    float lensA_0 = 6.2831854820251465f * _S21;
    float _S22 = lensR_0 * cos(lensA_0);

#line 640
    float _S23 = lensR_0 * sin(lensA_0);
    float3 _S24 = normalize(focal_0 - float3(_S22, _S23, 0.0f));
    thread PathState_0 s_1;

#line 642
    uint r_0 = 0U;
    for(;;)
    {

#line 643
        if(r_0 < 3U)
        {
        }
        else
        {

#line 643
            break;
        }
        uint _S25 = 4U * r_0;

#line 645
        uint _S26 = 8U + _S25;

#line 645
        uint _S27 = 9U + _S25;

#line 645
        uint _S28 = 10U + _S25;

#line 645
        (&s_1)->org_0[r_0] = (as_type<float>((kernelContext_2->params_0[_S26]))) * _S22 + (as_type<float>((kernelContext_2->params_0[_S27]))) * _S23 + (as_type<float>((kernelContext_2->params_0[_S28]))) * 0.0f + (as_type<float>((kernelContext_2->params_0[11U + _S25])));
        (&s_1)->dir_0[r_0] = (as_type<float>((kernelContext_2->params_0[_S26]))) * _S24.x + (as_type<float>((kernelContext_2->params_0[_S27]))) * _S24.y + (as_type<float>((kernelContext_2->params_0[_S28]))) * _S24.z;

#line 643
        r_0 = r_0 + 1U;

#line 643
    }

#line 648
    (&s_1)->dir_0 = normalize((&s_1)->dir_0);
    (&s_1)->thr_0 = float3(1.0f) ;
    (&s_1)->rng_0 = (&rng_1)->state_0;
    (&s_1)->cls_0 = 0U;
    (&s_1)->chan_0 = int(-1);
    (&s_1)->pathLen_0 = 0.0f;
    (&s_1)->misPrev_0 = false;
    (&s_1)->restir_1 = false;
    (&s_1)->gi_0 = false;
    (&s_1)->qPrev_0 = 0.0f;
    (&s_1)->prevInst_0 = 0U;
    (&s_1)->visLit_0 = 0.0f;
    (&s_1)->visTotal_0 = 0.0f;
    float3 _S29 = float3(0.0f) ;

#line 661
    (&(&s_1)->parts_0)->total_0 = _S29;

#line 661
    (&(&s_1)->parts_0)->directDiffuse_0 = _S29;

#line 661
    (&(&s_1)->parts_0)->indirectDiffuse_0 = _S29;

#line 661
    (&(&s_1)->parts_0)->specular_0 = _S29;

#line 661
    (&(&s_1)->parts_0)->transmission_0 = _S29;

#line 661
    (&(&s_1)->parts_0)->emission_0 = _S29;
    return s_1;
}


#line 617
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


#line 665 "shaders/include/pt_core.slang"
Hit_0 traceClosest_0(float3 org_1, float3 dir_1, KernelContext_0 thread* kernelContext_3)
{
    thread RayDesc_0 ray_0;
    (&ray_0)->Origin_0 = org_1;
    (&ray_0)->Direction_0 = dir_1;
    (&ray_0)->TMin_0 = 0.0f;
    (&ray_0)->TMax_0 = 1.00000001504746622e+30f;
    thread raytracing::intersection_query<raytracing::triangle_data, raytracing::instancing> q_0;
    (&q_0)->reset({ (ray_0.Origin_0), (ray_0.Direction_0), (ray_0.TMin_0), (ray_0.TMax_0) }, (kernelContext_3->scene_0), (255U), _slang_ray_flags_to_intersection_params((1U)));
    for(;;)
    {

#line 674
        bool _S30 = ((&q_0)->next());

#line 674
        if(_S30)
        {
        }
        else
        {

#line 674
            break;
        }

#line 674
    }
    thread Hit_0 h_1;
    uint _S31 = (_slang_committed_intersection_type_to_uint((&q_0)->get_committed_intersection_type()));

#line 676
    bool _S32 = _S31 == 1U;

#line 676
    (&h_1)->hit_0 = _S32;

#line 676
    uint _S33;
    if(_S32)
    {

#line 677
        uint _S34 = ((&q_0)->get_committed_instance_id());

#line 677
        _S33 = _S34;

#line 677
    }
    else
    {

#line 677
        _S33 = 0U;

#line 677
    }

#line 677
    (&h_1)->inst_0 = _S33;
    if((&h_1)->hit_0)
    {

#line 678
        uint _S35 = ((&q_0)->get_committed_primitive_id());

#line 678
        _S33 = _S35;

#line 678
    }
    else
    {

#line 678
        _S33 = 0U;

#line 678
    }

#line 678
    (&h_1)->prim_0 = _S33;

#line 678
    float _S36;
    if((&h_1)->hit_0)
    {

#line 679
        float _S37 = ((&q_0)->get_committed_distance());

#line 679
        _S36 = _S37;

#line 679
    }
    else
    {

#line 679
        _S36 = 0.0f;

#line 679
    }

#line 679
    (&h_1)->t_0 = _S36;
    return h_1;
}


#line 53
constant bool fc_restirCompiled_0 [[function_constant(0)]];
constant bool restirCompiled_0 = is_function_constant_defined(fc_restirCompiled_0) ? fc_restirCompiled_0 : true;

#line 693
uint restirBase_0(uint pixel_0, uint which_0)
{

#line 693
    return pixel_0 * 80U + which_0 * 28U;
}


#line 964
void restirClear_0(uint pixel_1, KernelContext_0 thread* kernelContext_4)
{
    uint co_0 = restirBase_0(pixel_1, kernelContext_4->params_0[int(6)] & 1U);
    float _S38 = (as_type<float>((0U)));

#line 967
    *(kernelContext_4->restir_0+(co_0 + 14U)) = _S38;
    *(kernelContext_4->restir_0+(co_0 + 27U)) = _S38;
    return;
}


#line 525
void Parts_file_0(Parts_0 thread* this_1, uint depth_0, uint cls_1, float3 c_0)
{
    if(depth_0 == 0U)
    {

#line 528
        this_1->emission_0 = this_1->emission_0 + c_0;

#line 527
    }
    else
    {

#line 529
        if(cls_1 == 0U)
        {

#line 530
            this_1->indirectDiffuse_0 = this_1->indirectDiffuse_0 + c_0;

#line 529
        }
        else
        {

#line 531
            if(cls_1 == 1U)
            {

#line 532
                this_1->specular_0 = this_1->specular_0 + c_0;

#line 531
            }
            else
            {
                this_1->transmission_0 = this_1->transmission_0 + c_0;

#line 531
            }

#line 529
        }

#line 527
    }

#line 535
    return;
}


#line 506
void Parts_add_0(Parts_0 thread* this_2, uint depth_1, uint cls_2, float3 c_1)
{
    this_2->total_0 = this_2->total_0 + c_1;
    Parts_file_0(this_2, depth_1, cls_2, c_1);
    return;
}


#line 248
void envCoords_0(float3 d_0, uint thread* i_1, uint thread* j_0, KernelContext_0 thread* kernelContext_5)
{
    uint w_2 = kernelContext_5->params_0[int(24)];
    uint h_2 = kernelContext_5->params_0[int(25)];

    float v_1 = acos(clamp(d_0.y, -1.0f, 1.0f)) / 3.1415927410125732f;
    *i_1 = min(uint((atan2(d_0.x, - d_0.z) * 0.15915493667125702f + 0.5f) * float(w_2)), w_2 - 1U);
    *j_0 = min(uint(v_1 * float(h_2)), h_2 - 1U);
    return;
}


#line 241
float3 envTexel_0(uint i_2, uint j_1, KernelContext_0 thread* kernelContext_6)
{
    uint o_0 = 3U * (j_1 * kernelContext_6->params_0[int(24)] + i_2);
    return float3(kernelContext_6->envPixels_0[o_0], kernelContext_6->envPixels_0[o_0 + 1U], kernelContext_6->envPixels_0[o_0 + 2U]);
}


#line 181
float lum_0(float3 c_2)
{

#line 181
    return dot(c_2, float3(0.2125999927520752f, 0.71520000696182251f, 0.072200000286102295f));
}


#line 267
float envPdf_0(float3 d_1, KernelContext_0 thread* kernelContext_7)
{
    thread uint i_3;

#line 269
    thread uint j_2;

#line 269
    envCoords_0(d_1, &i_3, &j_2, kernelContext_7);

#line 269
    float3 _S39 = envTexel_0(i_3, j_2, kernelContext_7);

    float _S40 = lum_0(_S39);

#line 271
    float _S41 = pf_0(26U, kernelContext_7);

#line 271
    return _S40 * _S41;
}


#line 258
float3 envRadiance_0(float3 d_2, KernelContext_0 thread* kernelContext_8)
{
    thread uint i_4;

#line 260
    thread uint j_3;

#line 260
    envCoords_0(d_2, &i_4, &j_3, kernelContext_8);

#line 260
    float3 _S42 = envTexel_0(i_4, j_3, kernelContext_8);

    return _S42;
}


#line 88
float3 vertexPos_0(uint v_2, KernelContext_0 thread* kernelContext_9)
{

#line 88
    uint _S43 = 3U * v_2;

#line 88
    return float3(kernelContext_9->positions_0[_S43], kernelContext_9->positions_0[_S43 + 1U], kernelContext_9->positions_0[_S43 + 2U]);
}


#line 90
float3 transformPoint_0(uint base_0, float3 p_1, KernelContext_0 thread* kernelContext_10)
{
    thread float3 r_1;

#line 92
    uint row_0 = 0U;
    for(;;)
    {

#line 93
        if(row_0 < 3U)
        {
        }
        else
        {

#line 93
            break;
        }
        uint o_1 = base_0 + 4U * row_0;
        r_1[row_0] = (as_type<float>((kernelContext_10->instances_0[o_1]))) * p_1.x + (as_type<float>((kernelContext_10->instances_0[o_1 + 1U]))) * p_1.y + (as_type<float>((kernelContext_10->instances_0[o_1 + 2U]))) * p_1.z + (as_type<float>((kernelContext_10->instances_0[o_1 + 3U])));

#line 93
        row_0 = row_0 + 1U;

#line 93
    }

#line 98
    return r_1;
}


#line 694
uint restirScratch_0(uint pixel_2)
{

#line 694
    return pixel_2 * 80U + 56U;
}


#line 113
float3 vertexNormal_0(uint v_3, KernelContext_0 thread* kernelContext_11)
{

#line 113
    uint _S44 = 3U * v_3;

#line 113
    return float3(kernelContext_11->vnormals_0[_S44], kernelContext_11->vnormals_0[_S44 + 1U], kernelContext_11->vnormals_0[_S44 + 2U]);
}


#line 103
float3 transformNormal_0(uint base_1, float3 n_1, KernelContext_0 thread* kernelContext_12)
{
    float3 r0_0 = float3((as_type<float>((kernelContext_12->instances_0[base_1]))), (as_type<float>((kernelContext_12->instances_0[base_1 + 1U]))), (as_type<float>((kernelContext_12->instances_0[base_1 + 2U]))));
    float3 r1_0 = float3((as_type<float>((kernelContext_12->instances_0[base_1 + 4U]))), (as_type<float>((kernelContext_12->instances_0[base_1 + 5U]))), (as_type<float>((kernelContext_12->instances_0[base_1 + 6U]))));
    float3 r2_0 = float3((as_type<float>((kernelContext_12->instances_0[base_1 + 8U]))), (as_type<float>((kernelContext_12->instances_0[base_1 + 9U]))), (as_type<float>((kernelContext_12->instances_0[base_1 + 10U]))));
    float3 c0_0 = cross(r1_0, r2_0);

#line 108
    float s_2;
    if((dot(r0_0, c0_0)) < 0.0f)
    {

#line 109
        s_2 = -1.0f;

#line 109
    }
    else
    {

#line 109
        s_2 = 1.0f;

#line 109
    }
    return float3(s_2)  * float3(dot(c0_0, n_1), dot(cross(r2_0, r0_0), n_1), dot(cross(r0_0, r1_0), n_1));
}


#line 309
float3 texelAt_0(uint base_2, uint w_3, uint h_3, int x_1, int y_0, KernelContext_0 thread* kernelContext_13)
{
    int _S45 = int(w_3);

#line 311
    int _S46 = x_1 % _S45;

#line 311
    int _S47 = (_S46 + _S45) % _S45;

#line 311
    uint xi_0 = uint(_S47);
    int _S48 = int(h_3);

#line 312
    int _S49 = y_0 % _S48;

#line 312
    int _S50 = (_S49 + _S48) % _S48;
    uint o_2 = 3U * (base_2 + uint(_S50) * w_3 + xi_0);
    return float3(kernelContext_13->texels_0[o_2], kernelContext_13->texels_0[o_2 + 1U], kernelContext_13->texels_0[o_2 + 2U]);
}

float3 bilinear_0(uint base_3, uint w_4, uint h_4, float2 uv_0, KernelContext_0 thread* kernelContext_14)
{
    float fx_0 = uv_0.x * float(w_4) - 0.5f;
    float fy_0 = uv_0.y * float(h_4) - 0.5f;
    int x0_0 = int(floor(fx_0));
    int y0_0 = int(floor(fy_0));
    float tx_0 = fx_0 - float(x0_0);
    float ty_0 = fy_0 - float(y0_0);

#line 324
    float3 _S51 = texelAt_0(base_3, w_4, h_4, x0_0, y0_0, kernelContext_14);
    int _S52 = x0_0 + int(1);

#line 325
    float3 _S53 = texelAt_0(base_3, w_4, h_4, _S52, y0_0, kernelContext_14);

#line 325
    float3 _S54 = float3(tx_0) ;

#line 325
    float3 a_0 = mix(_S51, _S53, _S54);
    int _S55 = y0_0 + int(1);

#line 326
    float3 _S56 = texelAt_0(base_3, w_4, h_4, x0_0, _S55, kernelContext_14);

#line 326
    float3 _S57 = texelAt_0(base_3, w_4, h_4, _S52, _S55, kernelContext_14);
    return mix(a_0, mix(_S56, _S57, _S54), float3(ty_0) );
}


float3 sampleTexture_0(uint tex_0, float2 uv_1, float footprint_0, KernelContext_0 thread* kernelContext_15)
{
    uint ti_0 = tex_0 * 4U;
    uint base_4 = kernelContext_15->texInfo_0[ti_0];
    uint w_5 = kernelContext_15->texInfo_0[ti_0 + 1U];
    uint h_5 = kernelContext_15->texInfo_0[ti_0 + 2U];
    uint levels_0 = kernelContext_15->texInfo_0[ti_0 + 3U];
    float lod_0 = clamp(log2(max(footprint_0 * float(max(w_5, h_5)), 9.99999993922529029e-09f)), 0.0f, float(levels_0 - 1U));
    uint l0_0 = uint(floor(lod_0));
    float t_1 = lod_0 - float(l0_0);

#line 340
    uint lw_0 = w_5;

#line 340
    uint lh_0 = h_5;

#line 340
    uint k_0 = 0U;

#line 340
    uint off_0 = base_4;



    for(;;)
    {

#line 344
        if(k_0 < l0_0)
        {
        }
        else
        {

#line 344
            break;
        }
        uint off_1 = off_0 + lw_0 * lh_0;
        uint _S58 = max(lw_0 / 2U, 1U);
        uint _S59 = max(lh_0 / 2U, 1U);

#line 344
        uint _S60 = k_0 + 1U;

#line 344
        lw_0 = _S58;

#line 344
        lh_0 = _S59;

#line 344
        k_0 = _S60;

#line 344
        off_0 = off_1;

#line 344
    }

#line 344
    float3 _S61 = bilinear_0(off_0, lw_0, lh_0, uv_1, kernelContext_15);

#line 344
    bool _S62;

#line 351
    if((l0_0 + 1U) >= levels_0)
    {

#line 351
        _S62 = true;

#line 351
    }
    else
    {

#line 351
        _S62 = t_1 <= 0.0f;

#line 351
    }

#line 351
    if(_S62)
    {

#line 352
        return _S61;
    }

#line 352
    float3 _S63 = bilinear_0(off_0 + lw_0 * lh_0, max(lw_0 / 2U, 1U), max(lh_0 / 2U, 1U), uv_1, kernelContext_15);


    return mix(_S61, _S63, float3(t_1) );
}


#line 195
uint emitMask_0(uint inst_1, KernelContext_0 thread* kernelContext_16)
{

#line 195
    return kernelContext_16->lights_0[kernelContext_16->params_0[int(5)] * 16U + 5888U + 2U * inst_1 + 1U];
}


#line 194
uint recvMask_0(uint inst_2, KernelContext_0 thread* kernelContext_17)
{

#line 194
    return kernelContext_17->lights_0[kernelContext_17->params_0[int(5)] * 16U + 5888U + 2U * inst_2];
}


#line 155
void basis_0(float3 n_2, float3 thread* t_2, float3 thread* b_0)
{

#line 155
    float3 a_1;

    if((abs(n_2.x)) > 0.89999997615814209f)
    {

#line 157
        a_1 = float3(0.0f, 1.0f, 0.0f);

#line 157
    }
    else
    {

#line 157
        a_1 = float3(1.0f, 0.0f, 0.0f);

#line 157
    }
    float3 _S64 = normalize(cross(n_2, a_1));

#line 158
    *b_0 = _S64;
    *t_2 = cross(_S64, n_2);
    return;
}


#line 144
float fresnelDielectric_0(float cosi_0, float eta_0)
{
    float s2_0 = (1.0f - cosi_0 * cosi_0) / (eta_0 * eta_0);
    if(s2_0 >= 1.0f)
    {

#line 148
        return 1.0f;
    }

#line 149
    float cost_0 = sqrt(1.0f - s2_0);
    float _S65 = eta_0 * cost_0;

#line 150
    float rs_0 = (cosi_0 - _S65) / (cosi_0 + _S65);
    float _S66 = eta_0 * cosi_0;

#line 151
    float rp_0 = (_S66 - cost_0) / (_S66 + cost_0);
    return 0.5f * (rs_0 * rs_0 + rp_0 * rp_0);
}


#line 192
float albedoAt_0(uint i_5, KernelContext_0 thread* kernelContext_18)
{

#line 192
    return (as_type<float>((kernelContext_18->lights_0[kernelContext_18->params_0[int(5)] * 16U + i_5])));
}


#line 410
float dielectricAlbedo_0(float cosO_0, float rough_0, float ior_0, bool outside_0, KernelContext_0 thread* kernelContext_19)
{
    float x_2 = saturate(cosO_0) * 15.0f;
    float y_1 = saturate(rough_0) * 15.0f;
    float z_0 = clamp((ior_0 - 1.0f) * 4.0f, 0.0f, 7.999000072479248f);
    uint _S67 = min(uint(x_2), 14U);
    uint _S68 = min(uint(y_1), 14U);
    uint z0_0 = uint(z_0);
    float _S69 = x_2 - float(_S67);
    float _S70 = y_1 - float(_S68);
    float fz_0 = z_0 - float(z0_0);

#line 420
    uint k_1;
    if(outside_0)
    {

#line 421
        k_1 = 0U;

#line 421
    }
    else
    {

#line 421
        k_1 = 9U;

#line 421
    }

#line 421
    uint _S71 = k_1 * 16U * 16U;
    thread array<float, int(2)> c_3;

#line 422
    k_1 = 0U;
    for(;;)
    {

#line 423
        if(k_1 < 2U)
        {
        }
        else
        {

#line 423
            break;
        }

        uint _S72 = 1280U + (_S71 + ((z0_0 + k_1) * 16U + _S68) * 16U + _S67);

#line 426
        float _S73 = albedoAt_0(_S72, kernelContext_19);

#line 426
        float _S74 = albedoAt_0(_S72 + 1U, kernelContext_19);

#line 426
        float a_2 = mix(_S73, _S74, _S69);
        uint _S75 = _S72 + 16U;

#line 427
        float _S76 = albedoAt_0(_S75, kernelContext_19);

#line 427
        float _S77 = albedoAt_0(_S75 + 1U, kernelContext_19);
        c_3[k_1] = mix(a_2, mix(_S76, _S77, _S69), _S70);

#line 423
        k_1 = k_1 + 1U;

#line 423
    }

#line 430
    return mix(c_3[int(0)], c_3[int(1)], fz_0);
}


float sheenAlbedo_0(float cosO_1, float r_2, KernelContext_0 thread* kernelContext_20)
{
    float x_3 = saturate(cosO_1) * 15.0f;
    float y_2 = saturate(r_2) * 15.0f;
    uint _S78 = min(uint(x_3), 14U);
    uint _S79 = min(uint(y_2), 14U);
    float fx_1 = x_3 - float(_S78);
    float fy_1 = y_2 - float(_S79);
    uint _S80 = 1024U + _S79 * 16U + _S78;

#line 442
    float _S81 = albedoAt_0(_S80, kernelContext_20);

#line 442
    float _S82 = albedoAt_0(_S80 + 1U, kernelContext_20);

#line 442
    float a_3 = mix(_S81, _S82, fx_1);
    uint _S83 = 1024U + (_S79 + 1U) * 16U + _S78;

#line 443
    float _S84 = albedoAt_0(_S83, kernelContext_20);

#line 443
    float _S85 = albedoAt_0(_S83 + 1U, kernelContext_20);
    return mix(a_3, mix(_S84, _S85, fx_1), fy_1);
}


#line 199
float iesFactor_0(uint po_0, float3 d_3, KernelContext_0 thread* kernelContext_21)
{



    float th_0 = degrees_0(acos(clamp(- dot(d_3, float3((as_type<float>((kernelContext_21->lights_0[po_0 + 6U]))), (as_type<float>((kernelContext_21->lights_0[po_0 + 7U]))), (as_type<float>((kernelContext_21->lights_0[po_0 + 8U]))))), -1.0f, 1.0f)));
    float ph_0 = degrees_0(atan2(dot(d_3, float3((as_type<float>((kernelContext_21->lights_0[po_0 + 3U]))), (as_type<float>((kernelContext_21->lights_0[po_0 + 4U]))), (as_type<float>((kernelContext_21->lights_0[po_0 + 5U]))))), dot(d_3, float3((as_type<float>((kernelContext_21->lights_0[po_0]))), (as_type<float>((kernelContext_21->lights_0[po_0 + 1U]))), (as_type<float>((kernelContext_21->lights_0[po_0 + 2U])))))));

#line 205
    float ph_1;
    if(ph_0 < 0.0f)
    {

#line 206
        ph_1 = ph_0 + 360.0f;

#line 206
    }
    else
    {

#line 206
        ph_1 = ph_0;

#line 206
    }

    uint _S86 = min(uint(th_0), 179U);
    uint _S87 = min(uint(ph_1), 359U);
    float ft_0 = th_0 - float(_S86);

    uint t_3 = po_0 + 9U;
    uint _S88 = t_3 + _S87 * 181U + _S86;
    uint _S89 = t_3 + (_S87 + 1U) * 181U + _S86;
    return mix(mix((as_type<float>((kernelContext_21->lights_0[_S88]))), (as_type<float>((kernelContext_21->lights_0[_S88 + 1U]))), ft_0), mix((as_type<float>((kernelContext_21->lights_0[_S89]))), (as_type<float>((kernelContext_21->lights_0[_S89 + 1U]))), ft_0), ph_1 - float(_S87));
}


#line 561
bool occluded_0(float3 o_3, float3 d_4, float tmax_0, KernelContext_0 thread* kernelContext_22)
{

#line 561
    uint layer_0 = 0U;

#line 561
    float3 _S90 = o_3;

#line 561
    float _S91 = tmax_0;

    for(;;)
    {

#line 563
        if(layer_0 < 8U)
        {
        }
        else
        {

#line 563
            break;
        }
        thread RayDesc_0 ray_1;
        (&ray_1)->Origin_0 = _S90;
        (&ray_1)->Direction_0 = d_4;
        (&ray_1)->TMin_0 = 0.0f;
        (&ray_1)->TMax_0 = _S91;
        thread raytracing::intersection_query<raytracing::triangle_data, raytracing::instancing> q_1;
        (&q_1)->reset({ (ray_1.Origin_0), (ray_1.Direction_0), (ray_1.TMin_0), (ray_1.TMax_0) }, (kernelContext_22->scene_0), (255U), _slang_ray_flags_to_intersection_params((5U)));
        for(;;)
        {

#line 572
            bool _S92 = ((&q_1)->next());

#line 572
            if(_S92)
            {
            }
            else
            {

#line 572
                break;
            }

#line 572
        }
        uint _S93 = (_slang_committed_intersection_type_to_uint((&q_1)->get_committed_intersection_type()));

#line 573
        if(_S93 != 1U)
        {

#line 574
            return false;
        }

#line 575
        uint _S94 = ((&q_1)->get_committed_instance_id());

#line 575
        float opacity_0 = kernelContext_22->materials_0[kernelContext_22->instances_0[_S94 * 16U + 2U] * 23U + 22U];
        if(opacity_0 >= 1.0f)
        {

#line 577
            return true;
        }
        uint h_6 = (((((((as_type<uint>((_S90.x))) * 73856093U) ^ ((as_type<uint>((_S90.y))) * 19349663U)) ^ ((as_type<uint>((_S90.z))) * 83492791U)) ^ ((as_type<uint>((d_4.x))) * 2654435761U)) ^ ((as_type<uint>((d_4.y))) * 40503U)) ^ ((as_type<uint>((d_4.z))) * 2246822519U)) ^ (layer_0 * 3266489917U);

        uint h_7 = (h_6 ^ (h_6 >> 16U)) * 2146121005U;

        uint h_8 = (h_7 ^ (h_7 >> 15U)) * 2221713035U;

        if((float((h_8 ^ (h_8 >> 16U)) >> 8U) * 5.9604644775390625e-08f) < opacity_0)
        {

#line 586
            return true;
        }

#line 587
        float _S95 = ((&q_1)->get_committed_distance());

#line 587
        float adv_0 = _S95 + 9.9999997473787516e-05f;
        float3 _S96 = _S90 + d_4 * float3(adv_0) ;
        float _S97 = _S91 - adv_0;
        if(_S97 <= 0.0f)
        {

#line 591
            return false;
        }

#line 563
        layer_0 = layer_0 + 1U;

#line 563
        _S90 = _S96;

#line 563
        _S91 = _S97;

#line 563
    }

#line 593
    return true;
}


#line 129
float D_0(float hz_0, float alpha_0)
{
    float a2_0 = alpha_0 * alpha_0;
    float d_5 = hz_0 * hz_0 * (a2_0 - 1.0f) + 1.0f;
    return a2_0 / (3.1415927410125732f * d_5 * d_5);
}


#line 122
float G1_0(float cosT_0, float alpha_1)
{
    float c2_0 = cosT_0 * cosT_0;

    return 2.0f / (1.0f + sqrt(1.0f + alpha_1 * alpha_1 * ((1.0f - c2_0) / max(c2_0, 9.99999993922529029e-09f))));
}


#line 136
float3 schlick_0(float3 f0_0, float c_4)
{
    float m_0 = 1.0f - saturate(c_4);
    float m2_0 = m_0 * m_0;
    return f0_0 + (float3(1.0f)  - f0_0) * float3((m2_0 * m2_0 * m_0)) ;
}


#line 384
float ggxAlbedo_0(float cosO_2, float alpha_2, KernelContext_0 thread* kernelContext_23)
{
    float x_4 = saturate(cosO_2) * 31.0f;
    float y_3 = saturate(sqrt(alpha_2)) * 31.0f;
    uint _S98 = min(uint(x_4), 30U);
    uint _S99 = min(uint(y_3), 30U);
    float fx_2 = x_4 - float(_S98);
    float fy_2 = y_3 - float(_S99);
    uint _S100 = _S99 * 32U + _S98;

#line 392
    float _S101 = albedoAt_0(_S100, kernelContext_23);

#line 392
    float _S102 = albedoAt_0(_S100 + 1U, kernelContext_23);

#line 392
    float a_4 = mix(_S101, _S102, fx_2);
    uint _S103 = (_S99 + 1U) * 32U + _S98;

#line 393
    float _S104 = albedoAt_0(_S103, kernelContext_23);

#line 393
    float _S105 = albedoAt_0(_S103 + 1U, kernelContext_23);
    return mix(a_4, mix(_S104, _S105, fx_2), fy_2);
}


#line 358
struct Surface_0
{
    float3 albedo_0;
    float metallic_0;
    float alpha_3;
    float transmission_1;
    float ior_1;
    float eta_1;
    float fSel_0;
    float tComp_0;
    float coat_0;
    float coatAlpha_0;
    float3 sheenColor_0;
    float sheenAlpha_0;
    float sheenP_0;
    float coatP_0;
};


#line 401
float3 multiscatterFactor_0(const Surface_0 thread* s_3, float cosO_3, KernelContext_0 thread* kernelContext_24)
{
    if(kernelContext_24->params_0[int(29)] == 0U)
    {

#line 404
        return float3(1.0f) ;
    }

#line 404
    float3 _S106 = s_3->albedo_0;

#line 404
    float _S107 = ggxAlbedo_0(cosO_3, s_3->alpha_3, kernelContext_24);
    return float3(1.0f)  + _S106 * float3((1.0f / max(_S107, 0.05000000074505806f) - 1.0f)) ;
}


#line 449
float sheenCore_0(float woz_0, float wiz_0, float hz_1, float alpha_4)
{



    return (2.0f + 1.0f / alpha_4) * pow(sqrt(max(1.0f - hz_1 * hz_1, 0.0f)), 1.0f / alpha_4) / 6.2831854820251465f * (1.0f / (4.0f * (wiz_0 + woz_0 - wiz_0 * woz_0))) * wiz_0;
}


#line 376
struct Lobes_0
{
    float3 diffuse_0;
    float3 specular_1;
};


#line 459
Lobes_0 evalLobes_0(const Surface_0 thread* s_4, float3 woL_0, float3 wiL_0, KernelContext_0 thread* kernelContext_25)
{
    float3 hh_0 = normalize(woL_0 + wiL_0);
    float _S108 = max(dot(woL_0, hh_0), 0.0f);

    float _S109 = hh_0.z;

#line 464
    float _S110 = woL_0.z;

#line 464
    float _S111 = wiL_0.z;

#line 464
    float _S112 = 4.0f * _S110;

#line 464
    float core_0 = D_0(_S109, s_4->alpha_3) * G1_0(_S110, s_4->alpha_3) * G1_0(_S111, s_4->alpha_3) / _S112;

#line 464
    float _S113 = s_4->transmission_1;

    thread Lobes_0 l_0;

#line 466
    float _S114 = s_4->metallic_0;

#line 466
    float3 _S115 = s_4->albedo_0;
    float3 _S116 = float3(s_4->metallic_0)  * schlick_0(s_4->albedo_0, _S108);

#line 467
    float3 _S117 = multiscatterFactor_0(s_4, _S110, kernelContext_25);
    float _S118 = 1.0f - _S114;

#line 468
    float _S119 = 1.0f - _S113;

#line 467
    (&l_0)->specular_1 = _S116 * _S117 * float3(core_0)  + float3((_S118 * (_S113 * fresnelDielectric_0(_S108, s_4->eta_1) * s_4->tComp_0 + _S119 * fresnelDielectric_0(_S108, s_4->ior_1)) * core_0)) ;

    (&l_0)->diffuse_0 = float3((_S118 * _S119 * (1.0f - s_4->fSel_0)))  * _S115 * float3((_S111 / 3.1415927410125732f)) ;

#line 469
    float _S120 = s_4->sheenP_0;

    if((s_4->sheenP_0) > 0.0f)
    {

#line 471
        float3 _S121 = float3((1.0f - _S120)) ;

        (&l_0)->specular_1 = _S121 * (&l_0)->specular_1 + s_4->sheenColor_0 * float3(sheenCore_0(_S110, _S111, _S109, s_4->sheenAlpha_0)) ;
        (&l_0)->diffuse_0 = (&l_0)->diffuse_0 * _S121;

#line 471
    }

#line 471
    float _S122 = s_4->coat_0;

#line 476
    if((s_4->coat_0) > 0.0f)
    {

#line 476
        float3 _S123 = float3((1.0f - s_4->coatP_0)) ;

#line 482
        (&l_0)->specular_1 = _S123 * (&l_0)->specular_1 + float3((_S122 * fresnelDielectric_0(_S108, 1.5f) * (D_0(_S109, s_4->coatAlpha_0) * G1_0(_S110, s_4->coatAlpha_0) * G1_0(_S111, s_4->coatAlpha_0) / _S112))) ;
        (&l_0)->diffuse_0 = (&l_0)->diffuse_0 * _S123;

#line 476
    }

#line 485
    return l_0;
}


#line 513
void Parts_addLight_0(Parts_0 thread* this_3, uint depth_2, uint cls_3, float3 c_5, float3 cd_0, float3 cs_0)
{
    this_3->total_0 = this_3->total_0 + c_5;
    if(depth_2 == 0U)
    {
        this_3->directDiffuse_0 = this_3->directDiffuse_0 + cd_0;
        this_3->specular_0 = this_3->specular_0 + cs_0;

#line 516
    }
    else
    {



        Parts_file_0(this_3, depth_2, cls_3, cd_0 + cs_0);

#line 516
    }

#line 523
    return;
}


#line 220
void addSlot_0(uint pixel_3, uint slot_0, float3 u_1, float3 s_5, float3 wi_0, float lit_0, float r_3, KernelContext_0 thread* kernelContext_26)
{

#line 220
    bool _S124;

    if(any(isnan(u_1)))
    {

#line 222
        _S124 = true;

#line 222
    }
    else
    {

#line 222
        _S124 = any(isinf(u_1));

#line 222
    }

#line 222
    if(_S124)
    {

#line 222
        _S124 = true;

#line 222
    }
    else
    {

#line 222
        _S124 = any(isnan(s_5));

#line 222
    }

#line 222
    if(_S124)
    {

#line 222
        _S124 = true;

#line 222
    }
    else
    {

#line 222
        _S124 = any(isinf(s_5));

#line 222
    }

#line 222
    if(_S124)
    {

#line 223
        return;
    }

#line 224
    uint o_4 = 65U * pixel_3 + 17U + 12U * slot_0;
    float w_6 = lum_0(u_1);
    float wd_0 = w_6 + lum_0(s_5);
    float device* _S125 = kernelContext_26->lighting_0+o_4;

#line 227
    *_S125 = *_S125 + u_1.x;
    float device* _S126 = kernelContext_26->lighting_0+(o_4 + 1U);

#line 228
    *_S126 = *_S126 + u_1.y;
    float device* _S127 = kernelContext_26->lighting_0+(o_4 + 2U);

#line 229
    *_S127 = *_S127 + u_1.z;
    float device* _S128 = kernelContext_26->lighting_0+(o_4 + 3U);

#line 230
    *_S128 = *_S128 + w_6;
    float device* _S129 = kernelContext_26->lighting_0+(o_4 + 4U);

#line 231
    *_S129 = *_S129 + w_6 * r_3;
    float device* _S130 = kernelContext_26->lighting_0+(o_4 + 5U);

#line 232
    *_S130 = *_S130 + s_5.x;
    float device* _S131 = kernelContext_26->lighting_0+(o_4 + 6U);

#line 233
    *_S131 = *_S131 + s_5.y;
    float device* _S132 = kernelContext_26->lighting_0+(o_4 + 7U);

#line 234
    *_S132 = *_S132 + s_5.z;
    float device* _S133 = kernelContext_26->lighting_0+(o_4 + 8U);

#line 235
    *_S133 = *_S133 + wd_0 * wi_0.x;
    float device* _S134 = kernelContext_26->lighting_0+(o_4 + 9U);

#line 236
    *_S134 = *_S134 + wd_0 * wi_0.y;
    float device* _S135 = kernelContext_26->lighting_0+(o_4 + 10U);

#line 237
    *_S135 = *_S135 + wd_0 * wi_0.z;
    float device* _S136 = kernelContext_26->lighting_0+(o_4 + 11U);

#line 238
    *_S136 = *_S136 + wd_0 * lit_0;
    return;
}


#line 866
void restirGbuffer_0(uint pixel_4, float3 p_2, float3 n_3, KernelContext_0 thread* kernelContext_27)
{
    uint co_1 = restirBase_0(pixel_4, kernelContext_27->params_0[int(6)] & 1U);
    *(kernelContext_27->restir_0+(co_1 + 8U)) = p_2.x;
    *(kernelContext_27->restir_0+(co_1 + 9U)) = p_2.y;
    *(kernelContext_27->restir_0+(co_1 + 10U)) = p_2.z;
    *(kernelContext_27->restir_0+(co_1 + 11U)) = n_3.x;
    *(kernelContext_27->restir_0+(co_1 + 12U)) = n_3.y;
    *(kernelContext_27->restir_0+(co_1 + 13U)) = n_3.z;
    *(kernelContext_27->restir_0+(co_1 + 14U)) = (as_type<float>((1U)));
    return;
}


#line 488
float3 evalReflective_0(const Surface_0 thread* s_6, float3 woL_1, float3 wiL_1, KernelContext_0 thread* kernelContext_28)
{

#line 488
    Lobes_0 _S137 = evalLobes_0(s_6, woL_1, wiL_1, kernelContext_28);


    return _S137.specular_1 + _S137.diffuse_0;
}


#line 882
void restirGIPrepare_0(uint pixel_5, float3 p_3, float3 n_4, float pHitT_0, const Surface_0 thread* surf_0, float3 T_0, float3 B_0, float3 woL_2, Rng_0 thread* rng_2, KernelContext_0 thread* kernelContext_29)
{
    uint w_7 = kernelContext_29->params_0[int(0)];
    uint _S138 = kernelContext_29->params_0[int(6)] & 1U;
    float _S139 = float(max(kernelContext_29->params_0[int(38)], 1U));



    float3 _S140 = float3(0.0f) ;

#line 890
    float pSel_0;

#line 890
    float mTotal_0;

#line 890
    float wsum_0;

#line 890
    float3 cSel_0;

#line 890
    float3 xSel_0;

#line 890
    float3 nSel_0;

#line 890
    float3 lSel_0;

#line 890
    uint k_2;



    if(kernelContext_29->params_0[int(6)] > 0U)
    {
        uint _S141 = pixel_5 % w_7;

#line 896
        int nx_0 = int(_S141);
        uint _S142 = pixel_5 / w_7;

#line 897
        int ny_0 = int(_S142);

#line 897
        pSel_0 = 0.0f;

#line 897
        cSel_0 = _S140;

#line 897
        xSel_0 = _S140;

#line 897
        nSel_0 = _S140;

#line 897
        lSel_0 = _S140;

#line 897
        k_2 = 0U;

#line 897
        mTotal_0 = 0.0f;

#line 897
        wsum_0 = 0.0f;
        for(;;)
        {

#line 898
            if(k_2 < 3U)
            {
            }
            else
            {

#line 898
                break;
            }

#line 898
            bool _S143;

#line 898
            bool _S144;

#line 898
            bool _S145;

#line 898
            int ny_1;

#line 898
            int nx_1;



            if(k_2 > 0U)
            {
                float _S146 = Rng_next_0(rng_2);

#line 904
                int nx_2 = nx_0 + (int(_S146 * 13.0f) - int(6));
                float _S147 = Rng_next_0(rng_2);

#line 905
                int ny_2 = ny_0 + (int(_S147 * 13.0f) - int(6));
                if(nx_2 < int(0))
                {

#line 906
                    _S143 = true;

#line 906
                }
                else
                {

#line 906
                    _S143 = ny_2 < int(0);

#line 906
                }

#line 906
                if(_S143)
                {

#line 906
                    _S144 = true;

#line 906
                }
                else
                {

#line 906
                    _S144 = nx_2 >= int(w_7);

#line 906
                }

#line 906
                if(_S144)
                {

#line 906
                    _S145 = true;

#line 906
                }
                else
                {

#line 906
                    _S145 = ny_2 >= int(kernelContext_29->params_0[int(1)]);

#line 906
                }

#line 906
                if(_S145)
                {

#line 907
                    k_2 = k_2 + 1U;

#line 898
                    continue;
                }

#line 898
                ny_1 = ny_2;

#line 898
                nx_1 = nx_2;



            }
            else
            {

#line 902
                ny_1 = ny_0;

#line 902
                nx_1 = nx_0;

#line 902
            }

#line 909
            uint ro_0 = restirBase_0(uint(ny_1) * w_7 + uint(nx_1), _S138 ^ 1U);
            if((as_type<uint>((*(kernelContext_29->restir_0+(ro_0 + 14U))))) == 0U)
            {

#line 910
                _S143 = true;

#line 910
            }
            else
            {

#line 910
                _S143 = (as_type<uint>((*(kernelContext_29->restir_0+(ro_0 + 27U))))) == 0U;

#line 910
            }

#line 910
            if(_S143)
            {

#line 911
                k_2 = k_2 + 1U;

#line 898
                continue;
            }

#line 912
            float3 pq_0 = float3(*(kernelContext_29->restir_0+(ro_0 + 8U)), *(kernelContext_29->restir_0+(ro_0 + 9U)), *(kernelContext_29->restir_0+(ro_0 + 10U)));

            if((dot(float3(*(kernelContext_29->restir_0+(ro_0 + 11U)), *(kernelContext_29->restir_0+(ro_0 + 12U)), *(kernelContext_29->restir_0+(ro_0 + 13U))), n_4)) < 0.89999997615814209f)
            {

#line 914
                _S144 = true;

#line 914
            }
            else
            {

#line 914
                _S144 = (length(pq_0 - p_3)) > (0.05000000074505806f * max(pHitT_0, 0.0099999997764825821f));

#line 914
            }

#line 914
            if(_S144)
            {

#line 915
                k_2 = k_2 + 1U;

#line 898
                continue;
            }

#line 916
            float3 x2_0 = float3(*(kernelContext_29->restir_0+(ro_0 + 16U)), *(kernelContext_29->restir_0+(ro_0 + 17U)), *(kernelContext_29->restir_0+(ro_0 + 18U)));
            float3 n2_0 = float3(*(kernelContext_29->restir_0+(ro_0 + 19U)), *(kernelContext_29->restir_0+(ro_0 + 20U)), *(kernelContext_29->restir_0+(ro_0 + 21U)));
            float3 l2_0 = float3(*(kernelContext_29->restir_0+(ro_0 + 22U)), *(kernelContext_29->restir_0+(ro_0 + 23U)), *(kernelContext_29->restir_0+(ro_0 + 24U)));
            float _S148 = min(*(kernelContext_29->restir_0+(ro_0 + 26U)), _S139);
            float mTotal_1 = mTotal_0 + _S148;
            float3 toX_0 = x2_0 - p_3;
            float dR_0 = length(toX_0);
            float3 wi_1 = toX_0 / float3(max(dR_0, 9.99999997475242708e-07f)) ;
            float dQ_0 = length(x2_0 - pq_0);
            float cosT_1 = dot(n_4, wi_1);
            float cosR_0 = abs(dot(n2_0, wi_1));
            float cosQ_0 = abs(dot(n2_0, normalize(pq_0 - x2_0)));
            if(cosT_1 <= 0.0f)
            {

#line 928
                _S145 = true;

#line 928
            }
            else
            {

#line 928
                _S145 = dR_0 < 0.0010000000474974513f;

#line 928
            }

#line 928
            bool _S149;

#line 928
            if(_S145)
            {

#line 928
                _S149 = true;

#line 928
            }
            else
            {

#line 928
                _S149 = cosR_0 < 0.0010000000474974513f;

#line 928
            }

#line 928
            bool _S150;

#line 928
            if(_S149)
            {

#line 928
                _S150 = true;

#line 928
            }
            else
            {

#line 928
                _S150 = cosQ_0 < 0.0010000000474974513f;

#line 928
            }

#line 928
            if(_S150)
            {

#line 928
                mTotal_0 = mTotal_1;
                k_2 = k_2 + 1U;

#line 898
                continue;
            }

#line 930
            float jac_0 = cosR_0 / cosQ_0 * (dQ_0 * dQ_0) / (dR_0 * dR_0);

#line 930
            bool _S151;
            if(jac_0 > 10.0f)
            {

#line 931
                _S151 = true;

#line 931
            }
            else
            {

#line 931
                _S151 = jac_0 < 0.10000000149011612f;

#line 931
            }

#line 931
            if(_S151)
            {

#line 931
                mTotal_0 = mTotal_1;
                k_2 = k_2 + 1U;

#line 898
                continue;
            }

#line 898
            float3 _S152 = evalReflective_0(surf_0, woL_2, float3(dot(wi_1, T_0), dot(wi_1, B_0), cosT_1), kernelContext_29);

#line 933
            float3 c_6 = _S152 * l2_0;
            float phat_0 = lum_0(c_6);

#line 934
            bool _S153;
            if(phat_0 <= 0.0f)
            {

#line 935
                _S153 = true;

#line 935
            }
            else
            {

#line 935
                bool _S154 = occluded_0(p_3, wi_1, dR_0 * 0.99900001287460327f, kernelContext_29);

#line 935
                _S153 = _S154;

#line 935
            }

#line 935
            if(_S153)
            {

#line 935
                mTotal_0 = mTotal_1;
                k_2 = k_2 + 1U;

#line 898
                continue;
            }

#line 937
            float wgt_0 = phat_0 * *(kernelContext_29->restir_0+(ro_0 + 25U)) * _S148 * jac_0;
            float wsum_1 = wsum_0 + wgt_0;
            float _S155 = Rng_next_0(rng_2);

#line 939
            float pSel_1;

#line 939
            float3 cSel_1;

#line 939
            float3 xSel_1;

#line 939
            float3 nSel_1;

#line 939
            float3 lSel_1;

#line 939
            if((_S155 * wsum_1) < wgt_0)
            {

#line 939
                pSel_1 = phat_0;

#line 939
                cSel_1 = c_6;

#line 939
                xSel_1 = x2_0;

#line 939
                nSel_1 = n2_0;

#line 939
                lSel_1 = l2_0;

#line 939
            }
            else
            {

#line 939
                pSel_1 = pSel_0;

#line 939
                cSel_1 = cSel_0;

#line 939
                xSel_1 = xSel_0;

#line 939
                nSel_1 = nSel_0;

#line 939
                lSel_1 = lSel_0;

#line 939
            }

#line 939
            pSel_0 = pSel_1;

#line 939
            cSel_0 = cSel_1;

#line 939
            xSel_0 = xSel_1;

#line 939
            nSel_0 = nSel_1;

#line 939
            lSel_0 = lSel_1;

#line 939
            mTotal_0 = mTotal_1;

#line 939
            wsum_0 = wsum_1;

#line 898
            k_2 = k_2 + 1U;

#line 898
        }

#line 894
    }
    else
    {

#line 894
        pSel_0 = 0.0f;

#line 894
        cSel_0 = _S140;

#line 894
        xSel_0 = _S140;

#line 894
        nSel_0 = _S140;

#line 894
        lSel_0 = _S140;

#line 894
        wsum_0 = 0.0f;

#line 894
        mTotal_0 = 0.0f;

#line 894
    }

#line 949
    uint so_0 = restirScratch_0(pixel_5);
    *(kernelContext_29->restir_0+so_0) = wsum_0;
    *(kernelContext_29->restir_0+(so_0 + 1U)) = mTotal_0;
    *(kernelContext_29->restir_0+(so_0 + 2U)) = pSel_0;

#line 952
    k_2 = 0U;
    for(;;)
    {

#line 953
        if(k_2 < 3U)
        {
        }
        else
        {

#line 953
            break;
        }
        *(kernelContext_29->restir_0+(so_0 + 3U + k_2)) = cSel_0[k_2];
        *(kernelContext_29->restir_0+(so_0 + 6U + k_2)) = xSel_0[k_2];
        *(kernelContext_29->restir_0+(so_0 + 9U + k_2)) = nSel_0[k_2];
        *(kernelContext_29->restir_0+(so_0 + 12U + k_2)) = lSel_0[k_2];

#line 953
        k_2 = k_2 + 1U;

#line 953
    }

#line 960
    *(kernelContext_29->restir_0+(so_0 + 22U)) = (as_type<float>((0U)));
    return;
}


#line 699
bool restirLight_0(uint e_0, uint recv_0, float3 x_5, float3 p_4, float3 n_5, float3 thread* wi_2, float thread* dist_0, float thread* cosi_1, float3 thread* g_0, float thread* plsa_0, KernelContext_0 thread* kernelContext_30)
{
    uint o_5 = e_0 * 16U;
    float3 a_5 = float3(kernelContext_30->emitters_0[o_5], kernelContext_30->emitters_0[o_5 + 1U], kernelContext_30->emitters_0[o_5 + 2U]);
    float3 b_1 = float3(kernelContext_30->emitters_0[o_5 + 3U], kernelContext_30->emitters_0[o_5 + 4U], kernelContext_30->emitters_0[o_5 + 5U]);
    float3 c_7 = float3(kernelContext_30->emitters_0[o_5 + 6U], kernelContext_30->emitters_0[o_5 + 7U], kernelContext_30->emitters_0[o_5 + 8U]);
    float3 toL_0 = x_5 - p_4;
    float d2_0 = dot(toL_0, toL_0);
    float _S156 = sqrt(d2_0);

#line 707
    *dist_0 = _S156;
    float3 _S157 = toL_0 / float3(max(_S156, 9.99999997475242708e-07f)) ;

#line 708
    *wi_2 = _S157;
    float cosl_0 = abs(dot(normalize(cross(b_1 - a_5, c_7 - a_5)), _S157));
    *cosi_1 = dot(n_5, _S157);
    *g_0 = float3(kernelContext_30->emitters_0[o_5 + 9U], kernelContext_30->emitters_0[o_5 + 10U], kernelContext_30->emitters_0[o_5 + 11U]) * float3((cosl_0 / max(d2_0, 9.999999960041972e-13f))) ;


    *plsa_0 = kernelContext_30->emitters_0[o_5 + 13U] * d2_0 / (max(kernelContext_30->emitters_0[o_5 + 12U], 1.00000000317107685e-30f) * max(cosl_0, 9.9999997473787516e-06f));

#line 714
    bool _S158;

    if((*cosi_1) > 0.0f)
    {

#line 716
        _S158 = cosl_0 > 9.9999997473787516e-06f;

#line 716
    }
    else
    {

#line 716
        _S158 = false;

#line 716
    }

#line 716
    if(_S158)
    {

#line 716
        _S158 = d2_0 > 9.999999960041972e-13f;

#line 716
    }
    else
    {

#line 716
        _S158 = false;

#line 716
    }

#line 716
    if(_S158)
    {

#line 716
        _S158 = ((as_type<uint>((kernelContext_30->emitters_0[o_5 + 14U]))) & recv_0) != 0U;

#line 716
    }
    else
    {

#line 716
        _S158 = false;

#line 716
    }

#line 716
    return _S158;
}


#line 540
float reflectivePdf_0(const Surface_0 thread* s_7, float3 woL_3, float3 wiL_2)
{
    float3 hh_1 = normalize(woL_3 + wiL_2);

    float _S159 = woL_3.z;

#line 544
    float _S160 = hh_1.z;

#line 544
    float _S161 = 4.0f * _S159;

    float _S162 = 1.0f - s_7->metallic_0;

#line 546
    float _S163 = 1.0f - s_7->transmission_1;
    float _S164 = wiL_2.z;
    float q_2 = (s_7->metallic_0 + _S162 * (s_7->transmission_1 * fresnelDielectric_0(max(dot(woL_3, hh_1), 0.0f), s_7->eta_1) + _S163 * s_7->fSel_0)) * (G1_0(_S159, s_7->alpha_3) * D_0(_S160, s_7->alpha_3) / _S161) + _S162 * _S163 * (1.0f - s_7->fSel_0) * _S164 / 3.1415927410125732f;

#line 548
    float _S165 = s_7->sheenP_0;

#line 548
    float q_3;
    if((s_7->sheenP_0) > 0.0f)
    {

#line 549
        q_3 = (1.0f - _S165) * q_2 + _S165 * _S164 / 3.1415927410125732f;

#line 549
    }
    else
    {

#line 549
        q_3 = q_2;

#line 549
    }

    if((s_7->coat_0) > 0.0f)
    {

#line 551
        q_3 = (1.0f - s_7->coatP_0) * q_3 + s_7->coatP_0 * (G1_0(_S159, s_7->coatAlpha_0) * D_0(_S160, s_7->coatAlpha_0) / _S161);

#line 551
    }

#line 556
    return q_3;
}


#line 720
float restirMis_0(const Surface_0 thread* surf_1, float3 woL_4, float3 wiL_3, float plsa_1)
{

#line 720
    float _S166 = reflectivePdf_0(surf_1, woL_4, wiL_3);


    float _S167 = plsa_1 * plsa_1;

#line 723
    return _S167 / max(_S167 + _S166 * _S166, 1.00000000317107685e-30f);
}

struct RestirPick_0
{
    bool valid_0;
    uint e_1;
    float3 x_6;
    float W_0;
    bool occ_0;
};


#line 740
RestirPick_0 restirDI_0(uint pixel_6, uint recv_1, float3 p_5, float3 n_6, float pHitT_1, const Surface_0 thread* surf_2, float3 T_1, float3 B_1, float3 woL_5, Rng_0 thread* rng_3, KernelContext_0 thread* kernelContext_31)
{

#line 740
    uint lo_0;

#line 740
    float q_4;

#line 740
    float phat_1;

#line 740
    float selPhat_0;

#line 740
    float3 selX_0;

#line 740
    bool _S168;

    uint w_8 = kernelContext_31->params_0[int(0)];
    uint cur_0 = kernelContext_31->params_0[int(6)] & 1U;
    uint _S169 = kernelContext_31->params_0[int(23)];
    float _S170 = float(max(kernelContext_31->params_0[int(38)], 1U));



    float3 _S171 = float3(0.0f) ;

#line 749
    uint selE_0 = 0U;

#line 749
    float selPhat_1 = 0.0f;

#line 749
    float3 selX_1 = _S171;

#line 749
    uint k_3 = 0U;

#line 749
    float mTotal_2 = 0.0f;

#line 749
    float wsum_2 = 0.0f;

    for(;;)
    {

#line 751
        if(k_3 < (max(kernelContext_31->params_0[int(37)], 1U)))
        {
        }
        else
        {

#line 751
            break;
        }
        float _S172 = Rng_next_0(rng_3);
        float ua_0 = Rng_next_0(rng_3);
        float ub_0 = Rng_next_0(rng_3);

        uint _S173 = _S169 - 1U;

#line 757
        lo_0 = 0U;

#line 757
        uint hi_0 = _S173;
        for(;;)
        {

#line 758
            if(lo_0 < hi_0)
            {
            }
            else
            {

#line 758
                break;
            }
            uint mid_0 = (lo_0 + hi_0) / 2U;
            if(kernelContext_31->emitCdf_0[mid_0] >= _S172)
            {

#line 761
                hi_0 = mid_0;

#line 761
            }
            else
            {

#line 761
                lo_0 = mid_0 + 1U;

#line 761
            }

#line 758
        }

#line 766
        uint o_6 = lo_0 * 16U;



        float su_0 = sqrt(ua_0);
        float3 x_7 = float3(kernelContext_31->emitters_0[o_6], kernelContext_31->emitters_0[o_6 + 1U], kernelContext_31->emitters_0[o_6 + 2U]) * float3((1.0f - su_0))  + float3(kernelContext_31->emitters_0[o_6 + 3U], kernelContext_31->emitters_0[o_6 + 4U], kernelContext_31->emitters_0[o_6 + 5U]) * float3((su_0 * (1.0f - ub_0)))  + float3(kernelContext_31->emitters_0[o_6 + 6U], kernelContext_31->emitters_0[o_6 + 7U], kernelContext_31->emitters_0[o_6 + 8U]) * float3((su_0 * ub_0)) ;
        float area_0 = kernelContext_31->emitters_0[o_6 + 12U];
        if(area_0 > 0.0f)
        {

#line 773
            q_4 = kernelContext_31->emitters_0[o_6 + 13U] / area_0;

#line 773
        }
        else
        {

#line 773
            q_4 = 0.0f;

#line 773
        }
        thread float3 wi_3;

#line 774
        thread float3 g_1;
        thread float dist_1;

#line 775
        thread float cosi_2;

#line 775
        thread float plsa_2;

        if(q_4 > 0.0f)
        {

#line 777
            bool _S174 = restirLight_0(lo_0, recv_1, x_7, p_5, n_6, &wi_3, &dist_1, &cosi_2, &g_1, &plsa_2, kernelContext_31);

#line 777
            _S168 = _S174;

#line 777
        }
        else
        {

#line 777
            _S168 = false;

#line 777
        }

#line 777
        if(_S168)
        {
            float3 wiL_4 = float3(dot(wi_3, T_1), dot(wi_3, B_1), cosi_2);

#line 779
            float3 _S175 = evalReflective_0(surf_2, woL_5, wiL_4, kernelContext_31);
            float _S176 = lum_0(_S175 * g_1);

#line 780
            float _S177 = restirMis_0(surf_2, woL_5, wiL_4, plsa_2);

#line 780
            phat_1 = _S176 * _S177;

#line 777
        }
        else
        {

#line 777
            phat_1 = 0.0f;

#line 777
        }

#line 782
        float wgt_1 = phat_1 / max(q_4, 1.00000000317107685e-30f);
        float mTotal_3 = mTotal_2 + 1.0f;
        if(phat_1 > 0.0f)
        {
            float wsum_3 = wsum_2 + wgt_1;
            float _S178 = Rng_next_0(rng_3);

#line 787
            uint selE_1;

#line 787
            if((_S178 * wsum_3) < wgt_1)
            {

#line 787
                selE_1 = lo_0 + 1U;

#line 787
                selPhat_0 = phat_1;

#line 787
                selX_0 = x_7;

#line 787
            }
            else
            {

#line 787
                selE_1 = selE_0;

#line 787
                selPhat_0 = selPhat_1;

#line 787
                selX_0 = selX_1;

#line 787
            }

#line 787
            selE_0 = selE_1;

#line 787
            selPhat_1 = selPhat_0;

#line 787
            selX_1 = selX_0;

#line 787
            wsum_2 = wsum_3;

#line 784
        }

#line 751
        k_3 = k_3 + 1U;

#line 751
        mTotal_2 = mTotal_3;

#line 751
    }

#line 795
    if(kernelContext_31->params_0[int(6)] > 0U)
    {
        uint _S179 = pixel_6 % w_8;

#line 797
        int nx_3 = int(_S179);
        uint _S180 = pixel_6 / w_8;

#line 798
        int ny_3 = int(_S180);

#line 798
        k_3 = 0U;
        for(;;)
        {

#line 799
            if(k_3 < 3U)
            {
            }
            else
            {

#line 799
                break;
            }

#line 799
            bool _S181;

#line 799
            int ny_4;

#line 799
            int nx_4;



            if(k_3 > 0U)
            {
                float _S182 = Rng_next_0(rng_3);

#line 805
                int nx_5 = nx_3 + (int(_S182 * 13.0f) - int(6));
                float _S183 = Rng_next_0(rng_3);

#line 806
                int ny_5 = ny_3 + (int(_S183 * 13.0f) - int(6));
                if(nx_5 < int(0))
                {

#line 807
                    _S168 = true;

#line 807
                }
                else
                {

#line 807
                    _S168 = ny_5 < int(0);

#line 807
                }

#line 807
                if(_S168)
                {

#line 807
                    _S181 = true;

#line 807
                }
                else
                {

#line 807
                    _S181 = nx_5 >= int(w_8);

#line 807
                }

#line 807
                bool _S184;

#line 807
                if(_S181)
                {

#line 807
                    _S184 = true;

#line 807
                }
                else
                {

#line 807
                    _S184 = ny_5 >= int(kernelContext_31->params_0[int(1)]);

#line 807
                }

#line 807
                if(_S184)
                {

#line 808
                    k_3 = k_3 + 1U;

#line 799
                    continue;
                }

#line 799
                ny_4 = ny_5;

#line 799
                nx_4 = nx_5;



            }
            else
            {

#line 803
                ny_4 = ny_3;

#line 803
                nx_4 = nx_3;

#line 803
            }

#line 810
            uint ro_1 = restirBase_0(uint(ny_4) * w_8 + uint(nx_4), cur_0 ^ 1U);
            uint ei_0 = (as_type<uint>((*(kernelContext_31->restir_0+ro_1))));
            if((as_type<uint>((*(kernelContext_31->restir_0+(ro_1 + 14U))))) == 0U)
            {

#line 812
                _S168 = true;

#line 812
            }
            else
            {

#line 812
                _S168 = ei_0 == 0U;

#line 812
            }

#line 812
            if(_S168)
            {

#line 813
                k_3 = k_3 + 1U;

#line 799
                continue;
            }

#line 815
            float3 pp_0 = float3(*(kernelContext_31->restir_0+(ro_1 + 8U)), *(kernelContext_31->restir_0+(ro_1 + 9U)), *(kernelContext_31->restir_0+(ro_1 + 10U)));
            if((dot(float3(*(kernelContext_31->restir_0+(ro_1 + 11U)), *(kernelContext_31->restir_0+(ro_1 + 12U)), *(kernelContext_31->restir_0+(ro_1 + 13U))), n_6)) < 0.89999997615814209f)
            {

#line 816
                _S181 = true;

#line 816
            }
            else
            {

#line 816
                _S181 = (length(pp_0 - p_5)) > (0.05000000074505806f * max(pHitT_1, 0.0099999997764825821f));

#line 816
            }

#line 816
            if(_S181)
            {

#line 817
                k_3 = k_3 + 1U;

#line 799
                continue;
            }

#line 818
            float3 xc_0 = float3(*(kernelContext_31->restir_0+(ro_1 + 1U)), *(kernelContext_31->restir_0+(ro_1 + 2U)), *(kernelContext_31->restir_0+(ro_1 + 3U)));
            float _S185 = min(*(kernelContext_31->restir_0+(ro_1 + 5U)), _S170);
            thread float3 wi_4;

#line 820
            thread float3 g_2;
            thread float dist_2;

#line 821
            thread float cosi_3;

#line 821
            thread float plsa_3;

#line 821
            bool _S186 = restirLight_0(ei_0 - 1U, recv_1, xc_0, p_5, n_6, &wi_4, &dist_2, &cosi_3, &g_2, &plsa_3, kernelContext_31);

            if(_S186)
            {
                float3 wiL_5 = float3(dot(wi_4, T_1), dot(wi_4, B_1), cosi_3);

#line 825
                float3 _S187 = evalReflective_0(surf_2, woL_5, wiL_5, kernelContext_31);
                float _S188 = lum_0(_S187 * g_2);

#line 826
                float _S189 = restirMis_0(surf_2, woL_5, wiL_5, plsa_3);

#line 826
                q_4 = _S188 * _S189;

#line 823
            }
            else
            {

#line 823
                q_4 = 0.0f;

#line 823
            }

#line 828
            float wgt_2 = q_4 * *(kernelContext_31->restir_0+(ro_1 + 4U)) * _S185;
            float mTotal_4 = mTotal_2 + _S185;
            if(wgt_2 > 0.0f)
            {
                float wsum_4 = wsum_2 + wgt_2;
                float _S190 = Rng_next_0(rng_3);

#line 833
                if((_S190 * wsum_4) < wgt_2)
                {

#line 833
                    lo_0 = ei_0;

#line 833
                    phat_1 = q_4;

#line 833
                    selX_0 = xc_0;

#line 833
                }
                else
                {

#line 833
                    lo_0 = selE_0;

#line 833
                    phat_1 = selPhat_1;

#line 833
                    selX_0 = selX_1;

#line 833
                }

#line 833
                selPhat_0 = wsum_4;

#line 830
            }
            else
            {

#line 830
                lo_0 = selE_0;

#line 830
                phat_1 = selPhat_1;

#line 830
                selX_0 = selX_1;

#line 830
                selPhat_0 = wsum_2;

#line 830
            }

#line 830
            selE_0 = lo_0;

#line 830
            selPhat_1 = phat_1;

#line 830
            selX_1 = selX_0;

#line 830
            mTotal_2 = mTotal_4;

#line 830
            wsum_2 = selPhat_0;

#line 799
            k_3 = k_3 + 1U;

#line 799
        }

#line 795
    }

#line 842
    thread RestirPick_0 r_4;
    if(selE_0 != 0U)
    {

#line 843
        _S168 = selPhat_1 > 0.0f;

#line 843
    }
    else
    {

#line 843
        _S168 = false;

#line 843
    }

#line 843
    (&r_4)->valid_0 = _S168;
    (&r_4)->e_1 = selE_0;
    (&r_4)->x_6 = selX_1;
    if(_S168)
    {

#line 846
        selPhat_1 = wsum_2 / (mTotal_2 * selPhat_1);

#line 846
    }
    else
    {

#line 846
        selPhat_1 = 0.0f;

#line 846
    }

#line 846
    (&r_4)->W_0 = selPhat_1;
    (&r_4)->occ_0 = false;
    if((&r_4)->valid_0)
    {
        thread float3 wi_5;

#line 850
        thread float3 g_3;
        thread float dist_3;

#line 851
        thread float cosi_4;

#line 851
        thread float plsa_4;

#line 851
        bool _S191 = restirLight_0(selE_0 - 1U, recv_1, selX_1, p_5, n_6, &wi_5, &dist_3, &cosi_4, &g_3, &plsa_4, kernelContext_31);

#line 851
        bool _S192 = occluded_0(p_5, wi_5, dist_3 * 0.99900001287460327f, kernelContext_31);

        (&r_4)->occ_0 = _S192;

#line 848
    }

#line 855
    uint co_2 = restirBase_0(pixel_6, cur_0);
    *(kernelContext_31->restir_0+co_2) = (as_type<float>((selE_0)));
    *(kernelContext_31->restir_0+(co_2 + 1U)) = selX_1.x;
    *(kernelContext_31->restir_0+(co_2 + 2U)) = selX_1.y;
    *(kernelContext_31->restir_0+(co_2 + 3U)) = selX_1.z;
    float device* _S193 = kernelContext_31->restir_0+(co_2 + 4U);

#line 860
    if((&r_4)->occ_0)
    {

#line 860
        selPhat_1 = 0.0f;

#line 860
    }
    else
    {

#line 860
        selPhat_1 = (&r_4)->W_0;

#line 860
    }

#line 860
    *_S193 = selPhat_1;
    *(kernelContext_31->restir_0+(co_2 + 5U)) = mTotal_2;
    return r_4;
}


#line 274
float3 envSample_0(float u1_0, float u2_0, float u3_0, float u4_0, float thread* pdf_0, float3 thread* le_0, KernelContext_0 thread* kernelContext_32)
{

#line 274
    uint lo_1;

    uint w_9 = kernelContext_32->params_0[int(24)];
    uint h_9 = kernelContext_32->params_0[int(25)];

    uint _S194 = h_9 - 1U;

#line 279
    uint lo_2 = 0U;

#line 279
    uint hi_1 = _S194;
    for(;;)
    {

#line 280
        if(lo_2 < hi_1)
        {
        }
        else
        {

#line 280
            break;
        }
        uint mid_1 = (lo_2 + hi_1) / 2U;
        if(kernelContext_32->envMarginal_0[mid_1] >= u1_0)
        {

#line 283
            lo_1 = lo_2;

#line 283
            hi_1 = mid_1;

#line 283
        }
        else
        {

#line 283
            lo_1 = mid_1 + 1U;

#line 283
        }

#line 283
        lo_2 = lo_1;

#line 280
    }

#line 290
    uint _S195 = w_9 - 1U;

#line 290
    lo_1 = 0U;

#line 290
    hi_1 = _S195;
    for(;;)
    {

#line 291
        if(lo_1 < hi_1)
        {
        }
        else
        {

#line 291
            break;
        }
        uint mid_2 = (lo_1 + hi_1) / 2U;
        if(kernelContext_32->envCond_0[lo_2 * w_9 + mid_2] >= u2_0)
        {

#line 294
            hi_1 = mid_2;

#line 294
        }
        else
        {

#line 294
            lo_1 = mid_2 + 1U;

#line 294
        }

#line 291
    }

#line 300
    float phi_0 = ((float(lo_1) + u3_0) / float(w_9) - 0.5f) * 2.0f * 3.1415927410125732f;
    float theta_0 = (float(lo_2) + u4_0) / float(h_9) * 3.1415927410125732f;
    float st_0 = sin(theta_0);

#line 302
    float3 _S196 = envTexel_0(lo_1, lo_2, kernelContext_32);
    *le_0 = _S196;
    float _S197 = lum_0(_S196);

#line 304
    float _S198 = pf_0(26U, kernelContext_32);

#line 304
    *pdf_0 = _S197 * _S198;
    return float3(st_0 * sin(phi_0), cos(theta_0), - st_0 * cos(phi_0));
}


#line 163
float3 sampleVndf_0(float3 wo_0, float alpha_5, float u1_1, float u2_1)
{
    float3 vh_0 = normalize(float3(alpha_5 * wo_0.x, alpha_5 * wo_0.y, wo_0.z));
    float _S199 = vh_0.x;

#line 166
    float _S200 = vh_0.y;

#line 166
    float lensq_0 = _S199 * _S199 + _S200 * _S200;

#line 166
    float3 t1_0;
    if(lensq_0 > 0.0f)
    {

#line 167
        t1_0 = float3(- _S200, _S199, 0.0f) * float3(rsqrt(lensq_0)) ;

#line 167
    }
    else
    {

#line 167
        t1_0 = float3(1.0f, 0.0f, 0.0f);

#line 167
    }

    float r_5 = sqrt(u1_1);
    float phi_1 = 6.2831854820251465f * u2_1;
    float a_6 = r_5 * cos(phi_1);

    float s_8 = 0.5f * (1.0f + vh_0.z);
    float _S201 = 1.0f - a_6 * a_6;

#line 174
    float b_2 = (1.0f - s_8) * sqrt(_S201) + s_8 * (r_5 * sin(phi_1));
    float3 nh_0 = float3(a_6)  * t1_0 + float3(b_2)  * cross(vh_0, t1_0) + float3(sqrt(max(0.0f, _S201 - b_2 * b_2)))  * vh_0;
    return normalize(float3(alpha_5 * nh_0.x, alpha_5 * nh_0.y, max(0.0f, nh_0.z)));
}


#line 115
float3 cosineLocal_0(float u1_2, float u2_2)
{
    float r_6 = sqrt(u1_2);
    float phi_2 = 6.2831854820251465f * u2_2;
    return float3(r_6 * cos(phi_2), r_6 * sin(phi_2), sqrt(max(0.0f, 1.0f - u1_2)));
}


#line 973
bool shadePath_0(PathState_0 thread* st_1, const Hit_0 thread* hq_0, uint depth_3, uint pixel_7, KernelContext_0 thread* kernelContext_33)
{

#line 973
    uint k_4;

#line 973
    int chan_1;

#line 973
    bool alive_0;

#line 973
    bool _S202;

#line 973
    float dist_4;

#line 973
    float vv_0;

#line 973
    float us_0;

#line 973
    float _S203;

#line 973
    float _S204;

#line 973
    float3 wi_6;

#line 973
    float3 li_0;

#line 973
    bool _S205;

#line 973
    bool _S206;

#line 973
    bool chooseEnv_0;

#line 973
    bool _S207;

#line 973
    bool track_0;

#line 973
    float _S208 = pf_0(20U, kernelContext_33);

#line 973
    float _S209 = pf_0(21U, kernelContext_33);

#line 973
    float _S210 = pf_0(22U, kernelContext_33);

    float3 _S211 = float3(_S208, _S209, _S210);
    bool _S212 = kernelContext_33->params_0[int(28)] != 0U;
    uint _S213 = kernelContext_33->params_0[int(5)];
    uint emitterCount_0 = kernelContext_33->params_0[int(23)];
    bool hasEnv_0 = kernelContext_33->params_0[int(24)] > 0U;

#line 979
    float _S214;

    if(hasEnv_0)
    {

#line 981
        if(emitterCount_0 > 0U)
        {

#line 981
            _S214 = 0.5f;

#line 981
        }
        else
        {

#line 981
            _S214 = 1.0f;

#line 981
        }

#line 981
    }
    else
    {

#line 981
        _S214 = 0.0f;

#line 981
    }
    thread Rng_0 rng_4;
    (&rng_4)->state_0 = st_1->rng_0;

#line 983
    uint cls_4 = st_1->cls_0;

#line 983
    float3 dir_2 = st_1->dir_0;

#line 983
    float3 org_2 = st_1->org_0;

#line 983
    int chan_2 = st_1->chan_0;

#line 983
    uint once_0 = 0U;

#line 983
    float3 thr_1 = st_1->thr_0;

#line 990
    for(;;)
    {

#line 990
        if(once_0 < 1U)
        {
        }
        else
        {

#line 990
            chan_1 = chan_2;

#line 990
            alive_0 = true;

#line 990
            break;
        }

#line 990
        float wB_0;

        if(!hq_0->hit_0)
        {
            if(restirCompiled_0)
            {

#line 994
                alive_0 = depth_3 == 0U;

#line 994
            }
            else
            {

#line 994
                alive_0 = false;

#line 994
            }

#line 994
            if(alive_0)
            {

#line 994
                alive_0 = kernelContext_33->params_0[int(36)] != 0U;

#line 994
            }
            else
            {

#line 994
                alive_0 = false;

#line 994
            }

#line 994
            if(alive_0)
            {

#line 994
                restirClear_0(pixel_7, kernelContext_33);

#line 994
            }


            if(depth_3 == 0U)
            {

#line 997
                alive_0 = kernelContext_33->params_0[int(42)] != 0U;

#line 997
            }
            else
            {

#line 997
                alive_0 = false;

#line 997
            }

#line 997
            if(alive_0)
            {

#line 997
                chan_1 = chan_2;

#line 997
                alive_0 = false;


                break;
            }

            Parts_add_0(&st_1->parts_0, depth_3, cls_4, thr_1 * _S211);
            if(hasEnv_0)
            {

                if(st_1->misPrev_0)
                {
                    if(st_1->restir_1)
                    {

#line 1009
                        alive_0 = depth_3 == 1U;

#line 1009
                    }
                    else
                    {

#line 1009
                        alive_0 = false;

#line 1009
                    }

#line 1009
                    if(alive_0)
                    {

#line 1009
                        _S214 = 1.0f;

#line 1009
                    }

#line 1009
                    float _S215 = envPdf_0(dir_2, kernelContext_33);

#line 1009
                    float pl_0 = _S214 * _S215;
                    float den_0 = st_1->qPrev_0 * st_1->qPrev_0 + pl_0 * pl_0;
                    if(den_0 > 0.0f)
                    {

#line 1011
                        _S214 = st_1->qPrev_0 * st_1->qPrev_0 / den_0;

#line 1011
                    }
                    else
                    {

#line 1011
                        _S214 = 1.0f;

#line 1011
                    }

#line 1011
                    wB_0 = _S214;

#line 1007
                }
                else
                {

#line 1007
                    wB_0 = 1.0f;

#line 1007
                }

#line 1007
                float3 _S216 = envRadiance_0(dir_2, kernelContext_33);

#line 1013
                Parts_add_0(&st_1->parts_0, depth_3, cls_4, thr_1 * _S216 * float3(wB_0) );

#line 1004
            }

#line 1004
            chan_1 = chan_2;

#line 1004
            alive_0 = false;

#line 1015
            break;
        }

#line 1015
        uint _S217 = hq_0->inst_0;


        uint inst_3 = hq_0->inst_0 * 16U;

#line 1018
        uint _S218 = hq_0->prim_0;
        uint tri_0 = kernelContext_33->instances_0[inst_3 + 1U] + 3U * hq_0->prim_0;
        uint vo_0 = kernelContext_33->instances_0[inst_3];
        uint _S219 = inst_3 + 4U;

#line 1021
        float3 _S220 = vertexPos_0(kernelContext_33->indices_0[tri_0] + vo_0, kernelContext_33);

#line 1021
        float3 _S221 = transformPoint_0(_S219, _S220, kernelContext_33);
        uint _S222 = tri_0 + 1U;

#line 1022
        float3 _S223 = vertexPos_0(kernelContext_33->indices_0[_S222] + vo_0, kernelContext_33);

#line 1022
        float3 _S224 = transformPoint_0(_S219, _S223, kernelContext_33);
        uint _S225 = tri_0 + 2U;

#line 1023
        float3 _S226 = vertexPos_0(kernelContext_33->indices_0[_S225] + vo_0, kernelContext_33);

#line 1023
        float3 _S227 = transformPoint_0(_S219, _S226, kernelContext_33);

        float3 _S228 = _S224 - _S221;

#line 1025
        float3 _S229 = _S227 - _S221;

#line 1025
        float3 _S230 = cross(_S228, _S229);

#line 1025
        float3 nOut_0 = normalize(_S230);
        float3 wo_1 = - dir_2;
        bool outside_1 = (dot(nOut_0, wo_1)) > 0.0f;

#line 1027
        float3 ng_0;
        if(outside_1)
        {

#line 1028
            ng_0 = nOut_0;

#line 1028
        }
        else
        {

#line 1028
            ng_0 = - nOut_0;

#line 1028
        }

#line 1028
        float _S231 = hq_0->t_0;

        st_1->pathLen_0 = st_1->pathLen_0 + hq_0->t_0;
        float3 hit_1 = org_2 + dir_2 * float3(_S231) ;


        uint _S232 = inst_3 + 2U;

#line 1034
        float opacity_1 = kernelContext_33->materials_0[kernelContext_33->instances_0[_S232] * 23U + 22U];
        if(opacity_1 < 1.0f)
        {

#line 1035
            float _S233 = Rng_next_0(&rng_4);

#line 1035
            alive_0 = _S233 >= opacity_1;

#line 1035
        }
        else
        {

#line 1035
            alive_0 = false;

#line 1035
        }

#line 1035
        if(alive_0)
        {

#line 1035
            org_2 = hit_1 + dir_2 * float3(9.9999997473787516e-05f) ;

#line 1035
            chan_1 = chan_2;

#line 1035
            alive_0 = true;


            break;
        }

        float3 p_6 = hit_1 + ng_0 * float3(9.9999997473787516e-05f) ;
        bool _S234 = depth_3 == 1U;

#line 1042
        if(_S234)
        {

#line 1042
            _S202 = st_1->gi_0;

#line 1042
        }
        else
        {

#line 1042
            _S202 = false;

#line 1042
        }

#line 1042
        if(_S202)
        {

            uint _S235 = restirBase_0(pixel_7, kernelContext_33->params_0[int(6)] & 1U);

#line 1045
            k_4 = 0U;
            for(;;)
            {

#line 1046
                if(k_4 < 3U)
                {
                }
                else
                {

#line 1046
                    break;
                }
                *(kernelContext_33->restir_0+(_S235 + 16U + k_4)) = hit_1[k_4];
                *(kernelContext_33->restir_0+(_S235 + 19U + k_4)) = ng_0[k_4];

#line 1046
                k_4 = k_4 + 1U;

#line 1046
            }

#line 1051
            *(kernelContext_33->restir_0+(restirScratch_0(pixel_7) + 22U)) = (as_type<float>((1U)));

#line 1042
        }

#line 1057
        float3 e3_0 = hit_1 - _S221;
        float d11_0 = dot(_S228, _S228);
        float d12_0 = dot(_S228, _S229);
        float d22_0 = dot(_S229, _S229);
        float _S236 = max(d11_0 * d22_0 - d12_0 * d12_0, 9.99999968265522539e-21f);
        float _S237 = dot(e3_0, _S228);

#line 1062
        float _S238 = dot(e3_0, _S229);

#line 1062
        float b1_0 = (d22_0 * _S237 - d12_0 * _S238) / _S236;
        float b2_0 = (d11_0 * _S238 - d12_0 * _S237) / _S236;



        float _S239 = 1.0f - b1_0 - b2_0;

#line 1067
        float3 _S240 = vertexNormal_0(kernelContext_33->indices_0[tri_0] + vo_0, kernelContext_33);

#line 1067
        float3 _S241 = float3(_S239)  * _S240;

#line 1067
        float3 _S242 = vertexNormal_0(kernelContext_33->indices_0[_S222] + vo_0, kernelContext_33);

#line 1067
        float3 _S243 = _S241 + float3(b1_0)  * _S242;

#line 1067
        float3 _S244 = vertexNormal_0(kernelContext_33->indices_0[_S225] + vo_0, kernelContext_33);

#line 1067
        float3 nsObj_0 = _S243 + float3(b2_0)  * _S244;

#line 1067
        float3 ns_0;

        if((dot(nsObj_0, nsObj_0)) > 9.999999960041972e-13f)
        {

#line 1069
            float3 _S245 = transformNormal_0(_S219, nsObj_0, kernelContext_33);

            float3 ns_1 = normalize(_S245);
            if((dot(ns_1, nOut_0)) < 0.0f)
            {

#line 1072
                ns_0 = - ns_1;

#line 1072
            }
            else
            {

#line 1072
                ns_0 = ns_1;

#line 1072
            }

#line 1069
        }
        else
        {

#line 1069
            ns_0 = nOut_0;

#line 1069
        }

#line 1069
        float3 _S246;

#line 1075
        if(outside_1)
        {

#line 1075
            _S246 = ns_0;

#line 1075
        }
        else
        {

#line 1075
            _S246 = - ns_0;

#line 1075
        }

        uint mi_0 = kernelContext_33->instances_0[_S232] * 23U;
        float3 albedo_1 = float3(kernelContext_33->materials_0[mi_0], kernelContext_33->materials_0[mi_0 + 1U], kernelContext_33->materials_0[mi_0 + 2U]);

        uint texBase_0 = uint(kernelContext_33->materials_0[mi_0 + 10U]);
        uint texMR_0 = uint(kernelContext_33->materials_0[mi_0 + 11U]);
        uint texEm_0 = uint(kernelContext_33->materials_0[mi_0 + 12U]);
        uint texNm_0 = uint(kernelContext_33->materials_0[mi_0 + 13U]);
        float2 _S247 = float2(1.0f) ;
        float3 _S248 = float3(1.0f) ;

#line 1085
        float3 albedo_2;

#line 1085
        float3 texEmission_0;

#line 1085
        float3 n_7;

#line 1085
        float3 n_8;

#line 1085
        bool _S249;

#line 1085
        float2 texRM_0;
        if((texBase_0 + texMR_0 + texEm_0 + texNm_0) > 0U)
        {
            float2 uv0_0 = float2(kernelContext_33->uvs_0[2U * (kernelContext_33->indices_0[tri_0] + vo_0)], kernelContext_33->uvs_0[2U * (kernelContext_33->indices_0[tri_0] + vo_0) + 1U]);


            float2 _S250 = float2(kernelContext_33->uvs_0[2U * (kernelContext_33->indices_0[_S222] + vo_0)], kernelContext_33->uvs_0[2U * (kernelContext_33->indices_0[_S222] + vo_0) + 1U]) - uv0_0;

#line 1091
            float2 _S251 = float2(kernelContext_33->uvs_0[2U * (kernelContext_33->indices_0[_S225] + vo_0)], kernelContext_33->uvs_0[2U * (kernelContext_33->indices_0[_S225] + vo_0) + 1U]) - uv0_0;

#line 1091
            float2 uv_2 = uv0_0 + float2(b1_0)  * _S250 + float2(b2_0)  * _S251;


            float _S252 = _S250.x;

#line 1094
            float _S253 = _S251.y;

#line 1094
            float _S254 = _S252 * _S253;

#line 1094
            float _S255 = _S250.y;

#line 1094
            float _S256 = _S251.x;

#line 1094
            float uvPerWorld_0 = sqrt(abs(_S254 - _S255 * _S256) / max(length(_S230), 9.99999968265522539e-21f));
            float _S257 = st_1->pathLen_0;

#line 1095
            float _S258 = pf_0(27U, kernelContext_33);

#line 1095
            float footprint_1 = _S257 * _S258 / max(abs(dot(nOut_0, dir_2)), 0.10000000149011612f) * uvPerWorld_0;
            if(texBase_0 > 0U)
            {

#line 1096
                float3 _S259 = sampleTexture_0(texBase_0 - 1U, uv_2, footprint_1, kernelContext_33);

#line 1096
                albedo_2 = albedo_1 * _S259;

#line 1096
            }
            else
            {

#line 1096
                albedo_2 = albedo_1;

#line 1096
            }

            if(texMR_0 > 0U)
            {

#line 1098
                float3 _S260 = sampleTexture_0(texMR_0 - 1U, uv_2, footprint_1, kernelContext_33);

#line 1098
                texRM_0 = _S260.yz;

#line 1098
            }
            else
            {

#line 1098
                texRM_0 = _S247;

#line 1098
            }

            if(texEm_0 > 0U)
            {

#line 1100
                float3 _S261 = sampleTexture_0(texEm_0 - 1U, uv_2, footprint_1, kernelContext_33);

#line 1100
                texEmission_0 = _S261;

#line 1100
            }
            else
            {

#line 1100
                texEmission_0 = _S248;

#line 1100
            }

            if(texNm_0 > 0U)
            {

                float det_0 = _S254 - _S256 * _S255;

#line 1105
                float3 _S262 = float3(det_0) ;
                float3 dPdu_0 = (_S228 * float3(_S253)  - _S229 * float3(_S255) ) / _S262;
                float3 dPdv_0 = (_S229 * float3(_S252)  - _S228 * float3(_S256) ) / _S262;
                float3 tg_0 = dPdu_0 - ns_0 * float3(dot(ns_0, dPdu_0)) ;
                if((abs(det_0)) > 9.99999968265522539e-21f)
                {

#line 1109
                    _S249 = (dot(tg_0, tg_0)) > 9.99999968265522539e-21f;

#line 1109
                }
                else
                {

#line 1109
                    _S249 = false;

#line 1109
                }

#line 1109
                if(_S249)
                {
                    float3 tg_1 = normalize(tg_0);
                    float3 bt_0 = cross(ns_0, tg_1);
                    if((dot(bt_0, dPdv_0)) > 0.0f)
                    {

#line 1113
                        n_7 = - bt_0;

#line 1113
                    }
                    else
                    {

#line 1113
                        n_7 = bt_0;

#line 1113
                    }

#line 1113
                    float3 _S263 = sampleTexture_0(texNm_0 - 1U, uv_2, footprint_1, kernelContext_33);

                    float3 nt_0 = _S263 * float3(2.0f)  - float3(1.0f) ;
                    uint _S264 = mi_0 + 14U;

#line 1116
                    float3 ns_2 = normalize(float3((nt_0.x * kernelContext_33->materials_0[_S264]))  * tg_1 + float3((nt_0.y * kernelContext_33->materials_0[_S264]))  * n_7 + float3(nt_0.z)  * ns_0);
                    if(outside_1)
                    {

#line 1117
                        n_8 = ns_2;

#line 1117
                    }
                    else
                    {

#line 1117
                        n_8 = - ns_2;

#line 1117
                    }

#line 1117
                    n_7 = n_8;

#line 1109
                }
                else
                {

#line 1109
                    n_7 = _S246;

#line 1109
                }

#line 1102
            }
            else
            {

#line 1102
                n_7 = _S246;

#line 1102
            }

#line 1086
        }
        else
        {

#line 1086
            n_7 = _S246;

#line 1086
            texEmission_0 = _S248;

#line 1086
            texRM_0 = _S247;

#line 1086
            albedo_2 = albedo_1;

#line 1086
        }

#line 1123
        float woN_0 = dot(n_7, wo_1);
        if(woN_0 < 0.05000000074505806f)
        {

#line 1124
            n_8 = normalize(n_7 + wo_1 * float3((0.05000000074505806f - woN_0)) );

#line 1124
        }
        else
        {

#line 1124
            n_8 = n_7;

#line 1124
        }


        float3 _S265 = float3(kernelContext_33->materials_0[mi_0 + 3U], kernelContext_33->materials_0[mi_0 + 4U], kernelContext_33->materials_0[mi_0 + 5U]) * texEmission_0;

        if((st_1->prevInst_0) != 0U)
        {

#line 1129
            uint _S266 = emitMask_0(_S217, kernelContext_33);

#line 1129
            uint _S267 = recvMask_0(st_1->prevInst_0 - 1U, kernelContext_33);

#line 1129
            _S249 = (_S266 & _S267) == 0U;

#line 1129
        }
        else
        {

#line 1129
            _S249 = false;

#line 1129
        }

#line 1129
        float3 le_1;

#line 1129
        if(_S249)
        {

#line 1129
            le_1 = float3(0.0f) ;

#line 1129
        }
        else
        {

#line 1129
            le_1 = _S265;

#line 1129
        }

#line 1129
        bool _S268;

#line 1129
        bool _S269;

        if(any(le_1 > (float3(0.0f) )))
        {

            uint eb_0 = kernelContext_33->instances_0[inst_3 + 3U];
            if(st_1->misPrev_0)
            {

#line 1135
                _S268 = eb_0 != 0U;

#line 1135
            }
            else
            {

#line 1135
                _S268 = false;

#line 1135
            }

#line 1135
            if(_S268)
            {
                uint e_2 = (eb_0 - 1U + _S218) * 16U;
                float _S270 = max(abs(dot(nOut_0, dir_2)), 9.9999997473787516e-05f);
                if(st_1->restir_1)
                {

#line 1139
                    _S269 = _S234;

#line 1139
                }
                else
                {

#line 1139
                    _S269 = false;

#line 1139
                }

#line 1139
                if(_S269)
                {

#line 1139
                    wB_0 = 1.0f;

#line 1139
                }
                else
                {

#line 1139
                    wB_0 = 1.0f - _S214;

#line 1139
                }

#line 1139
                float pl_1 = wB_0 * kernelContext_33->emitters_0[e_2 + 13U] * _S231 * _S231 / (kernelContext_33->emitters_0[e_2 + 12U] * _S270);

#line 1139
                wB_0 = st_1->qPrev_0 * st_1->qPrev_0 / (st_1->qPrev_0 * st_1->qPrev_0 + pl_1 * pl_1);

#line 1135
            }
            else
            {

#line 1135
                wB_0 = 1.0f;

#line 1135
            }

#line 1142
            float3 _S271 = thr_1 * le_1 * float3(wB_0) ;

#line 1142
            Parts_add_0(&st_1->parts_0, depth_3, cls_4, _S271);
            if(_S234)
            {

#line 1143
                _S269 = st_1->gi_0;

#line 1143
            }
            else
            {

#line 1143
                _S269 = false;

#line 1143
            }

#line 1143
            if(_S269)
            {


                uint _S272 = restirScratch_0(pixel_7) + 18U;

#line 1147
                k_4 = 0U;
                for(;;)
                {

#line 1148
                    if(k_4 < 3U)
                    {
                    }
                    else
                    {

#line 1148
                        break;
                    }

#line 1149
                    float device* _S273 = kernelContext_33->restir_0+(_S272 + k_4);

#line 1149
                    *_S273 = *_S273 + _S271[k_4];

#line 1148
                    k_4 = k_4 + 1U;

#line 1148
                }

#line 1143
            }

#line 1131
        }

#line 1152
        float metallic_1 = kernelContext_33->materials_0[mi_0 + 6U] * texRM_0.y;
        float rough_1 = kernelContext_33->materials_0[mi_0 + 7U] * texRM_0.x;
        float transmission_2 = kernelContext_33->materials_0[mi_0 + 8U];
        float ior_2 = kernelContext_33->materials_0[mi_0 + 9U];
        float dispersion_0 = kernelContext_33->materials_0[mi_0 + 21U];
        if(dispersion_0 > 0.0f)
        {

#line 1157
            _S268 = transmission_2 > 0.0f;

#line 1157
        }
        else
        {

#line 1157
            _S268 = false;

#line 1157
        }

#line 1157
        float eta_2;

#line 1157
        float _S274;

#line 1157
        float3 thr_2;

#line 1157
        if(_S268)
        {


            if(chan_2 < int(0))
            {
                float _S275 = Rng_next_0(&rng_4);

#line 1163
                int _S276 = min(int(_S275 * 3.0f), int(2));
                if(_S276 == int(0))
                {

#line 1164
                    wB_0 = 1.0f;

#line 1164
                }
                else
                {

#line 1164
                    wB_0 = 0.0f;

#line 1164
                }

#line 1164
                if(_S276 == int(1))
                {

#line 1164
                    eta_2 = 1.0f;

#line 1164
                }
                else
                {

#line 1164
                    eta_2 = 0.0f;

#line 1164
                }

#line 1164
                if(_S276 == int(2))
                {

#line 1164
                    _S274 = 1.0f;

#line 1164
                }
                else
                {

#line 1164
                    _S274 = 0.0f;

#line 1164
                }

#line 1164
                float3 thr_3 = thr_1 * (float3(3.0f)  * float3(wB_0, eta_2, _S274));

#line 1164
                chan_1 = _S276;

#line 1164
                thr_2 = thr_3;

#line 1161
            }
            else
            {

#line 1161
                chan_1 = chan_2;

#line 1161
                thr_2 = thr_1;

#line 1161
            }

#line 1161
            wB_0 = max(ior_2 + float(chan_1 - int(1)) * (ior_2 - 1.0f) * 0.02500000037252903f * dispersion_0, 1.0f);

#line 1157
        }
        else
        {

#line 1157
            wB_0 = ior_2;

#line 1157
            chan_1 = chan_2;

#line 1157
            thr_2 = thr_1;

#line 1157
        }

#line 1170
        if(_S234)
        {

#line 1170
            _S269 = st_1->gi_0;

#line 1170
        }
        else
        {

#line 1170
            _S269 = false;

#line 1170
        }

#line 1170
        bool _S277;

#line 1170
        if(_S269)
        {

#line 1170
            _S277 = transmission_2 > 0.0f;

#line 1170
        }
        else
        {

#line 1170
            _S277 = false;

#line 1170
        }

#line 1170
        if(_S277)
        {

#line 1171
            *(kernelContext_33->restir_0+(restirScratch_0(pixel_7) + 22U)) = (as_type<float>((0U)));

#line 1170
        }

        float _S278 = max(rough_1 * rough_1, 0.0010000000474974513f);
        if(outside_1)
        {

#line 1173
            eta_2 = wB_0;

#line 1173
        }
        else
        {

#line 1173
            eta_2 = 1.0f / wB_0;

#line 1173
        }

        thread float3 T_2;

#line 1175
        thread float3 B_2;
        basis_0(n_8, &T_2, &B_2);
        float _S279 = max(dot(wo_1, n_8), 9.9999997473787516e-05f);

#line 1177
        float3 woL_6 = float3(dot(wo_1, T_2), dot(wo_1, B_2), _S279);
        float fSel_1 = fresnelDielectric_0(_S279, wB_0);
        thread Surface_0 surf_3;
        (&surf_3)->albedo_0 = albedo_2;
        (&surf_3)->metallic_0 = metallic_1;
        (&surf_3)->alpha_3 = _S278;
        (&surf_3)->transmission_1 = transmission_2;
        (&surf_3)->ior_1 = wB_0;
        (&surf_3)->eta_1 = eta_2;
        (&surf_3)->fSel_0 = fSel_1;


        (&surf_3)->tComp_0 = 1.0f;

#line 1189
        bool _S280;
        if(kernelContext_33->params_0[int(29)] != 0U)
        {

#line 1190
            _S280 = transmission_2 > 0.0f;

#line 1190
        }
        else
        {

#line 1190
            _S280 = false;

#line 1190
        }

#line 1190
        bool _S281;

#line 1190
        if(_S280)
        {

#line 1190
            _S281 = rough_1 > 0.0f;

#line 1190
        }
        else
        {

#line 1190
            _S281 = false;

#line 1190
        }

#line 1190
        if(_S281)
        {

#line 1190
            float _S282 = dielectricAlbedo_0(_S279, rough_1, wB_0, outside_1, kernelContext_33);
            (&surf_3)->tComp_0 = 1.0f / max(_S282, 0.10000000149011612f);

#line 1190
        }


        if(outside_1)
        {

#line 1193
            _S274 = kernelContext_33->materials_0[mi_0 + 15U];

#line 1193
        }
        else
        {

#line 1193
            _S274 = 0.0f;

#line 1193
        }

#line 1193
        (&surf_3)->coat_0 = _S274;
        uint _S283 = mi_0 + 16U;

#line 1194
        (&surf_3)->coatAlpha_0 = max(kernelContext_33->materials_0[_S283] * kernelContext_33->materials_0[_S283], 0.0010000000474974513f);
        float coatF_0 = fresnelDielectric_0(_S279, 1.5f);
        (&surf_3)->coatP_0 = _S274 * coatF_0;

#line 1196
        float3 _S284;
        if(outside_1)
        {

#line 1197
            _S284 = float3(kernelContext_33->materials_0[mi_0 + 18U], kernelContext_33->materials_0[mi_0 + 19U], kernelContext_33->materials_0[mi_0 + 20U]);

#line 1197
        }
        else
        {

#line 1197
            _S284 = float3(0.0f) ;

#line 1197
        }

#line 1197
        (&surf_3)->sheenColor_0 = _S284;
        float _S285 = max(_S284.x, max(_S284.y, _S284.z));
        float _S286 = max(kernelContext_33->materials_0[mi_0 + 17U], 0.070000000298023224f);
        (&surf_3)->sheenAlpha_0 = _S286 * _S286;

#line 1200
        float _S287;
        if(_S285 > 0.0f)
        {

#line 1201
            float _S288 = sheenAlbedo_0(_S279, _S286, kernelContext_33);

#line 1201
            _S287 = _S285 * _S288;

#line 1201
        }
        else
        {

#line 1201
            _S287 = 0.0f;

#line 1201
        }

#line 1201
        (&surf_3)->sheenP_0 = _S287;

#line 1201
        k_4 = 0U;



        for(;;)
        {

#line 1205
            if(k_4 < _S213)
            {
            }
            else
            {

#line 1205
                break;
            }
            uint o_7 = k_4 * 16U;
            float3 col_0 = float3((as_type<float>((kernelContext_33->lights_0[o_7 + 1U]))), (as_type<float>((kernelContext_33->lights_0[o_7 + 2U]))), (as_type<float>((kernelContext_33->lights_0[o_7 + 3U])))) * float3((as_type<float>((kernelContext_33->lights_0[o_7 + 4U])))) ;
            float3 vec_0 = float3((as_type<float>((kernelContext_33->lights_0[o_7 + 5U]))), (as_type<float>((kernelContext_33->lights_0[o_7 + 6U]))), (as_type<float>((kernelContext_33->lights_0[o_7 + 7U]))));

            bool virt_0 = kernelContext_33->lights_0[o_7] == 3U;
            if(virt_0)
            {

#line 1212
                if(_S212)
                {

#line 1212
                    _S205 = depth_3 == 0U;

#line 1212
                }
                else
                {

#line 1212
                    _S205 = false;

#line 1212
                }

#line 1212
                _S205 = !_S205;

#line 1212
            }
            else
            {

#line 1212
                _S205 = false;

#line 1212
            }

#line 1212
            if(_S205)
            {

#line 1213
                k_4 = k_4 + 1U;

#line 1205
                continue;
            }

#line 1215
            uint _S289 = kernelContext_33->lights_0[o_7 + 14U];

#line 1215
            uint _S290 = recvMask_0(_S217, kernelContext_33);

#line 1215
            if((_S289 & _S290) == 0U)
            {

#line 1216
                k_4 = k_4 + 1U;

#line 1205
                continue;
            }

#line 1220
            if(kernelContext_33->lights_0[o_7] == 1U)
            {

#line 1220
                _S206 = true;

#line 1220
            }
            else
            {

#line 1220
                _S206 = virt_0;

#line 1220
            }

#line 1220
            if(_S206)
            {

#line 1220
                wi_6 = - normalize(vec_0);

#line 1220
                dist_4 = 1.00000001504746622e+30f;

#line 1220
                li_0 = col_0;

#line 1220
            }
            else
            {

#line 1228
                float3 toL_1 = vec_0 - p_6;
                float d2_1 = dot(toL_1, toL_1);
                float dist_5 = sqrt(d2_1);
                float3 wi_7 = toL_1 / float3(dist_5) ;
                float3 li_1 = col_0 / float3(d2_1) ;
                uint _S291 = o_7 + 15U;

#line 1233
                if(kernelContext_33->lights_0[_S291] != 0U)
                {

#line 1233
                    float _S292 = iesFactor_0(kernelContext_33->lights_0[_S291] - 1U, - wi_7, kernelContext_33);

#line 1233
                    wi_6 = li_1 * float3(_S292) ;

#line 1233
                }
                else
                {

#line 1233
                    wi_6 = li_1;

#line 1233
                }

                if(kernelContext_33->lights_0[o_7] == 2U)
                {

                    float att_0 = saturate(dot(float3((as_type<float>((kernelContext_33->lights_0[o_7 + 8U]))), (as_type<float>((kernelContext_33->lights_0[o_7 + 9U]))), (as_type<float>((kernelContext_33->lights_0[o_7 + 10U])))), - wi_7) * (as_type<float>((kernelContext_33->lights_0[o_7 + 11U]))) + (as_type<float>((kernelContext_33->lights_0[o_7 + 12U]))));

#line 1238
                    li_0 = wi_6 * float3((att_0 * att_0)) ;

#line 1235
                }
                else
                {

#line 1235
                    li_0 = wi_6;

#line 1235
                }

#line 1235
                wi_6 = wi_7;

#line 1235
                dist_4 = dist_5;

#line 1220
            }

#line 1242
            float c_8 = dot(n_8, wi_6);
            if(c_8 > 0.0f)
            {

#line 1243
                bool _S293 = occluded_0(p_6, wi_6, dist_4 - 0.0010000000474974513f, kernelContext_33);


                if(_S212)
                {

#line 1246
                    track_0 = depth_3 == 0U;

#line 1246
                }
                else
                {

#line 1246
                    track_0 = false;

#line 1246
                }
                bool _S294 = !_S293;

#line 1247
                if(_S294)
                {

#line 1247
                    chooseEnv_0 = true;

#line 1247
                }
                else
                {

#line 1247
                    chooseEnv_0 = track_0;

#line 1247
                }

#line 1247
                if(chooseEnv_0)
                {
                    float3 _S295 = float3(dot(wi_6, T_2), dot(wi_6, B_2), c_8);

#line 1249
                    thread Surface_0 _S296 = surf_3;

#line 1249
                    Lobes_0 _S297 = evalLobes_0(&_S296, woL_6, _S295, kernelContext_33);
                    float3 cd_1 = thr_2 * _S297.diffuse_0 * li_0;
                    float3 cs_1 = thr_2 * _S297.specular_1 * li_0;
                    if(_S294)
                    {

#line 1252
                        _S207 = !virt_0;

#line 1252
                    }
                    else
                    {

#line 1252
                        _S207 = false;

#line 1252
                    }

#line 1252
                    if(_S207)
                    {

#line 1253
                        Parts_addLight_0(&st_1->parts_0, depth_3, cls_4, thr_2 * (_S297.diffuse_0 + _S297.specular_1) * li_0, cd_1, cs_1);

#line 1252
                    }

                    if(track_0)
                    {
                        if(virt_0)
                        {

#line 1256
                            vv_0 = 0.0f;

#line 1256
                        }
                        else
                        {

#line 1256
                            vv_0 = lum_0(cd_1 + cs_1);

#line 1256
                        }
                        st_1->visTotal_0 = st_1->visTotal_0 + vv_0;
                        if(_S293)
                        {

#line 1258
                            us_0 = 0.0f;

#line 1258
                        }
                        else
                        {

#line 1258
                            us_0 = vv_0;

#line 1258
                        }

#line 1258
                        st_1->visLit_0 = st_1->visLit_0 + us_0;
                        uint _S298 = kernelContext_33->lights_0[o_7 + 13U];

#line 1259
                        float3 _S299 = float3(c_8) ;

#line 1259
                        float3 _S300 = cd_1 / _S299;

#line 1259
                        float3 _S301 = cs_1 / _S299;

#line 1259
                        if(_S293)
                        {

#line 1259
                            _S203 = 0.0f;

#line 1259
                        }
                        else
                        {

#line 1259
                            _S203 = 1.0f;

#line 1259
                        }

#line 1259
                        if(_S293)
                        {

#line 1259
                            _S204 = 0.0f;

#line 1259
                        }
                        else
                        {

#line 1259
                            _S204 = c_8;

#line 1259
                        }

#line 1259
                        addSlot_0(pixel_7, _S298, _S300, _S301, wi_6, _S203, _S204, kernelContext_33);

#line 1254
                    }

#line 1247
                }

#line 1243
            }

#line 1205
            k_4 = k_4 + 1U;

#line 1205
        }

#line 1268
        if(restirCompiled_0)
        {

#line 1268
            _S205 = depth_3 == 0U;

#line 1268
        }
        else
        {

#line 1268
            _S205 = false;

#line 1268
        }

#line 1268
        if(_S205)
        {

#line 1268
            _S206 = kernelContext_33->params_0[int(36)] != 0U;

#line 1268
        }
        else
        {

#line 1268
            _S206 = false;

#line 1268
        }

#line 1268
        bool suits_0;

#line 1268
        bool ok_0;

#line 1268
        bool reDI_0;

#line 1268
        bool refracted_0;

#line 1268
        if(_S206)
        {

#line 1268
            float _S302 = pf_0(3U, kernelContext_33);

            if(_S302 == 0.0f)
            {

#line 1270
                chooseEnv_0 = transmission_2 == 0.0f;

#line 1270
            }
            else
            {

#line 1270
                chooseEnv_0 = false;

#line 1270
            }

#line 1270
            if(chooseEnv_0)
            {

#line 1270
                _S207 = ((&surf_3)->alpha_3) >= 0.15000000596046448f;

#line 1270
            }
            else
            {

#line 1270
                _S207 = false;

#line 1270
            }
            if(_S207)
            {

#line 1271
                if(((&surf_3)->coat_0) == 0.0f)
                {

#line 1271
                    suits_0 = true;

#line 1271
                }
                else
                {

#line 1271
                    suits_0 = ((&surf_3)->coatAlpha_0) >= 0.15000000596046448f;

#line 1271
                }

#line 1271
            }
            else
            {

#line 1271
                suits_0 = false;

#line 1271
            }
            if(suits_0)
            {

#line 1272
                ok_0 = (kernelContext_33->params_0[int(36)] & 1U) != 0U;

#line 1272
            }
            else
            {

#line 1272
                ok_0 = false;

#line 1272
            }

#line 1272
            if(ok_0)
            {

#line 1272
                reDI_0 = emitterCount_0 > 0U;

#line 1272
            }
            else
            {

#line 1272
                reDI_0 = false;

#line 1272
            }

            if(suits_0)
            {

#line 1274
                refracted_0 = (kernelContext_33->params_0[int(36)] & 2U) != 0U;

#line 1274
            }
            else
            {

#line 1274
                refracted_0 = false;

#line 1274
            }

#line 1274
            if(refracted_0)
            {

#line 1274
                track_0 = !_S212;

#line 1274
            }
            else
            {

#line 1274
                track_0 = false;

#line 1274
            }
            st_1->restir_1 = reDI_0;
            st_1->gi_0 = track_0;
            if(suits_0)
            {

#line 1277
                restirGbuffer_0(pixel_7, p_6, n_8, kernelContext_33);


                if(track_0)
                {

#line 1280
                    thread Surface_0 _S303 = surf_3;

#line 1280
                    restirGIPrepare_0(pixel_7, p_6, n_8, _S231, &_S303, T_2, B_2, woL_6, &rng_4, kernelContext_33);

#line 1280
                }

#line 1277
            }
            else
            {

#line 1277
                restirClear_0(pixel_7, kernelContext_33);

#line 1277
            }

#line 1268
        }
        else
        {

#line 1268
            reDI_0 = false;

#line 1268
        }

#line 1286
        if(reDI_0)
        {

#line 1286
            uint _S304 = recvMask_0(_S217, kernelContext_33);

#line 1286
            thread Surface_0 _S305 = surf_3;

#line 1286
            RestirPick_0 _S306 = restirDI_0(pixel_7, _S304, p_6, n_8, _S231, &_S305, T_2, B_2, woL_6, &rng_4, kernelContext_33);


            if(_S306.valid_0)
            {


                uint _S307 = _S306.e_1 - 1U;

#line 1293
                uint _S308 = recvMask_0(_S217, kernelContext_33);

#line 1291
                thread float3 wi_8;

#line 1291
                thread float3 g_4;
                thread float dist_6;

#line 1292
                thread float cosi_5;

#line 1292
                thread float plsa_5;

#line 1292
                bool _S309 = restirLight_0(_S307, _S308, _S306.x_6, p_6, n_8, &wi_8, &dist_6, &cosi_5, &g_4, &plsa_5, kernelContext_33);


                bool _S310 = !_S306.occ_0;

#line 1295
                if(_S310)
                {

#line 1295
                    chooseEnv_0 = true;

#line 1295
                }
                else
                {

#line 1295
                    chooseEnv_0 = _S212;

#line 1295
                }

#line 1295
                if(chooseEnv_0)
                {
                    float3 wiL_6 = float3(dot(wi_8, T_2), dot(wi_8, B_2), cosi_5);

#line 1297
                    thread Surface_0 _S311 = surf_3;

#line 1297
                    float _S312 = restirMis_0(&_S311, woL_6, wiL_6, plsa_5);

#line 1297
                    thread Surface_0 _S313 = surf_3;

#line 1297
                    Lobes_0 _S314 = evalLobes_0(&_S313, woL_6, wiL_6, kernelContext_33);

#line 1297
                    float3 _S315 = float3((_S312 * _S306.W_0)) ;


                    float3 cd_2 = thr_2 * _S314.diffuse_0 * g_4 * _S315;
                    float3 cs_2 = thr_2 * _S314.specular_1 * g_4 * _S315;
                    if(_S310)
                    {

#line 1303
                        Parts_addLight_0(&st_1->parts_0, depth_3, cls_4, cd_2 + cs_2, cd_2, cs_2);

#line 1302
                    }

                    if(_S212)
                    {
                        float vv_1 = lum_0(cd_2 + cs_2);
                        st_1->visTotal_0 = st_1->visTotal_0 + vv_1;
                        if(_S306.occ_0)
                        {

#line 1308
                            dist_4 = 0.0f;

#line 1308
                        }
                        else
                        {

#line 1308
                            dist_4 = vv_1;

#line 1308
                        }

#line 1308
                        st_1->visLit_0 = st_1->visLit_0 + dist_4;
                        float3 _S316 = cd_2 / float3(cosi_5) ;

#line 1309
                        float3 _S317 = cs_2 / float3(cosi_5) ;

#line 1309
                        float3 _S318 = wi_8;

#line 1309
                        if(_S306.occ_0)
                        {

#line 1309
                            vv_0 = 0.0f;

#line 1309
                        }
                        else
                        {

#line 1309
                            vv_0 = 1.0f;

#line 1309
                        }

#line 1309
                        if(_S306.occ_0)
                        {

#line 1309
                            us_0 = 0.0f;

#line 1309
                        }
                        else
                        {

#line 1309
                            us_0 = cosi_5;

#line 1309
                        }

#line 1309
                        addSlot_0(pixel_7, 3U, _S316, _S317, _S318, vv_0, us_0, kernelContext_33);

#line 1304
                    }

#line 1295
                }

#line 1289
            }

#line 1286
        }

#line 1316
        float chooseLight_0 = Rng_next_0(&rng_4);
        if(reDI_0)
        {

#line 1317
            if(hasEnv_0)
            {

#line 1317
                dist_4 = 1.0f;

#line 1317
            }
            else
            {

#line 1317
                dist_4 = 0.0f;

#line 1317
            }

#line 1317
        }
        else
        {

#line 1317
            dist_4 = _S214;

#line 1317
        }
        if(hasEnv_0)
        {

#line 1318
            chooseEnv_0 = chooseLight_0 < dist_4;

#line 1318
        }
        else
        {

#line 1318
            chooseEnv_0 = false;

#line 1318
        }
        if(emitterCount_0 > 0U)
        {

#line 1319
            _S207 = !chooseEnv_0;

#line 1319
        }
        else
        {

#line 1319
            _S207 = false;

#line 1319
        }

#line 1319
        if(_S207)
        {

#line 1319
            suits_0 = !reDI_0;

#line 1319
        }
        else
        {

#line 1319
            suits_0 = false;

#line 1319
        }

#line 1319
        uint lobeCls_0;

#line 1319
        uint cls_5;

#line 1319
        if(suits_0)
        {
            float _S319 = Rng_next_0(&rng_4);
            float ua_1 = Rng_next_0(&rng_4);
            float ub_1 = Rng_next_0(&rng_4);

            uint _S320 = emitterCount_0 - 1U;

#line 1325
            lobeCls_0 = 0U;

#line 1325
            cls_5 = _S320;
            for(;;)
            {

#line 1326
                if(lobeCls_0 < cls_5)
                {
                }
                else
                {

#line 1326
                    break;
                }
                uint mid_3 = (lobeCls_0 + cls_5) / 2U;
                if(kernelContext_33->emitCdf_0[mid_3] >= _S319)
                {

#line 1329
                    cls_5 = mid_3;

#line 1329
                }
                else
                {

#line 1329
                    lobeCls_0 = mid_3 + 1U;

#line 1329
                }

#line 1326
            }

#line 1334
            uint e_3 = lobeCls_0 * 16U;
            float3 a_7 = float3(kernelContext_33->emitters_0[e_3], kernelContext_33->emitters_0[e_3 + 1U], kernelContext_33->emitters_0[e_3 + 2U]);
            float3 b_3 = float3(kernelContext_33->emitters_0[e_3 + 3U], kernelContext_33->emitters_0[e_3 + 4U], kernelContext_33->emitters_0[e_3 + 5U]);
            float3 c_9 = float3(kernelContext_33->emitters_0[e_3 + 6U], kernelContext_33->emitters_0[e_3 + 7U], kernelContext_33->emitters_0[e_3 + 8U]);
            float su_1 = sqrt(ua_1);

            float3 toL_2 = a_7 * float3((1.0f - su_1))  + b_3 * float3((su_1 * (1.0f - ub_1)))  + c_9 * float3((su_1 * ub_1))  - p_6;
            float d2_2 = dot(toL_2, toL_2);
            float dist_7 = sqrt(d2_2);
            float3 wi_9 = toL_2 / float3(dist_7) ;
            float cosl_1 = abs(dot(normalize(cross(b_3 - a_7, c_9 - a_7)), wi_9));
            float cosi_6 = dot(n_8, wi_9);
            if(cosi_6 > 0.0f)
            {

#line 1346
                ok_0 = cosl_1 > 9.9999997473787516e-06f;

#line 1346
            }
            else
            {

#line 1346
                ok_0 = false;

#line 1346
            }

#line 1346
            if(ok_0)
            {

#line 1346
                uint _S321 = (as_type<uint>((kernelContext_33->emitters_0[e_3 + 14U])));

#line 1346
                uint _S322 = recvMask_0(_S217, kernelContext_33);

#line 1346
                refracted_0 = (_S321 & _S322) != 0U;

#line 1346
            }
            else
            {

#line 1346
                refracted_0 = false;

#line 1346
            }

#line 1346
            if(refracted_0)
            {

#line 1346
                bool _S323 = occluded_0(p_6, wi_9, dist_7 * 0.99900001287460327f, kernelContext_33);


                if(_S212)
                {

#line 1349
                    track_0 = depth_3 == 0U;

#line 1349
                }
                else
                {

#line 1349
                    track_0 = false;

#line 1349
                }
                bool _S324 = !_S323;

#line 1350
                bool _S325;

#line 1350
                if(_S324)
                {

#line 1350
                    _S325 = true;

#line 1350
                }
                else
                {

#line 1350
                    _S325 = track_0;

#line 1350
                }

#line 1350
                if(_S325)
                {
                    float pl_2 = (1.0f - _S214) * kernelContext_33->emitters_0[e_3 + 13U] * d2_2 / (kernelContext_33->emitters_0[e_3 + 12U] * cosl_1);
                    float3 wiL_7 = float3(dot(wi_9, T_2), dot(wi_9, B_2), cosi_6);

#line 1353
                    thread Surface_0 _S326 = surf_3;

#line 1353
                    float _S327 = reflectivePdf_0(&_S326, woL_6, wiL_7);

                    float _S328 = pl_2 * pl_2;

#line 1355
                    float wl_0 = _S328 / (_S328 + _S327 * _S327);
                    float3 le_2 = float3(kernelContext_33->emitters_0[e_3 + 9U], kernelContext_33->emitters_0[e_3 + 10U], kernelContext_33->emitters_0[e_3 + 11U]);

#line 1356
                    thread Surface_0 _S329 = surf_3;

#line 1356
                    Lobes_0 _S330 = evalLobes_0(&_S329, woL_6, wiL_7, kernelContext_33);

#line 1356
                    float3 _S331 = float3(pl_2) ;

#line 1356
                    float3 _S332 = float3(wl_0) ;

                    float3 cd_3 = thr_2 * _S330.diffuse_0 * le_2 / _S331 * _S332;
                    float3 cs_3 = thr_2 * _S330.specular_1 * le_2 / _S331 * _S332;
                    if(_S324)
                    {

#line 1360
                        thread Surface_0 _S333 = surf_3;

#line 1360
                        float3 _S334 = evalReflective_0(&_S333, woL_6, wiL_7, kernelContext_33);
                        Parts_addLight_0(&st_1->parts_0, depth_3, cls_4, thr_2 * _S334 * le_2 / _S331 * _S332, cd_3, cs_3);

#line 1360
                    }

                    if(track_0)
                    {
                        float vv_2 = lum_0(cd_3 + cs_3);
                        st_1->visTotal_0 = st_1->visTotal_0 + vv_2;
                        if(_S323)
                        {

#line 1366
                            vv_0 = 0.0f;

#line 1366
                        }
                        else
                        {

#line 1366
                            vv_0 = vv_2;

#line 1366
                        }

#line 1366
                        st_1->visLit_0 = st_1->visLit_0 + vv_0;

#line 1366
                        float3 _S335 = float3(cosi_6) ;
                        float3 _S336 = cd_3 / _S335;

#line 1367
                        float3 _S337 = cs_3 / _S335;

#line 1367
                        if(_S323)
                        {

#line 1367
                            us_0 = 0.0f;

#line 1367
                        }
                        else
                        {

#line 1367
                            us_0 = 1.0f;

#line 1367
                        }

#line 1367
                        if(_S323)
                        {

#line 1367
                            _S203 = 0.0f;

#line 1367
                        }
                        else
                        {

#line 1367
                            _S203 = cosi_6;

#line 1367
                        }

#line 1367
                        addSlot_0(pixel_7, 3U, _S336, _S337, wi_9, us_0, _S203, kernelContext_33);

#line 1362
                    }

#line 1350
                }

#line 1346
            }

#line 1319
        }

#line 1373
        if(chooseEnv_0)
        {
            float e1_0 = Rng_next_0(&rng_4);
            float e2_0 = Rng_next_0(&rng_4);
            float e3_1 = Rng_next_0(&rng_4);
            float e4_0 = Rng_next_0(&rng_4);
            thread float pdfE_0;
            thread float3 leE_0;

#line 1380
            float3 _S338 = envSample_0(e1_0, e2_0, e3_1, e4_0, &pdfE_0, &leE_0, kernelContext_33);

            float cosi_7 = dot(n_8, _S338);
            if(pdfE_0 > 0.0f)
            {

#line 1383
                ok_0 = cosi_7 > 0.0f;

#line 1383
            }
            else
            {

#line 1383
                ok_0 = false;

#line 1383
            }

#line 1383
            if(ok_0)
            {

#line 1383
                bool _S339 = occluded_0(p_6, _S338, 1.00000001504746622e+30f, kernelContext_33);


                if(_S212)
                {

#line 1386
                    track_0 = depth_3 == 0U;

#line 1386
                }
                else
                {

#line 1386
                    track_0 = false;

#line 1386
                }
                bool _S340 = !_S339;

#line 1387
                if(_S340)
                {

#line 1387
                    refracted_0 = true;

#line 1387
                }
                else
                {

#line 1387
                    refracted_0 = track_0;

#line 1387
                }

#line 1387
                if(refracted_0)
                {
                    float pl_3 = dist_4 * pdfE_0;
                    float3 wiL_8 = float3(dot(_S338, T_2), dot(_S338, B_2), cosi_7);

#line 1390
                    thread Surface_0 _S341 = surf_3;

#line 1390
                    float _S342 = reflectivePdf_0(&_S341, woL_6, wiL_8);

                    float _S343 = pl_3 * pl_3;

#line 1392
                    float wl_1 = _S343 / (_S343 + _S342 * _S342);

#line 1392
                    thread Surface_0 _S344 = surf_3;

#line 1392
                    Lobes_0 _S345 = evalLobes_0(&_S344, woL_6, wiL_8, kernelContext_33);

#line 1392
                    float3 _S346 = float3(pl_3) ;

#line 1392
                    float3 _S347 = float3(wl_1) ;

                    float3 cd_4 = thr_2 * _S345.diffuse_0 * leE_0 / _S346 * _S347;
                    float3 cs_4 = thr_2 * _S345.specular_1 * leE_0 / _S346 * _S347;
                    if(_S340)
                    {

#line 1396
                        thread Surface_0 _S348 = surf_3;

#line 1396
                        float3 _S349 = evalReflective_0(&_S348, woL_6, wiL_8, kernelContext_33);
                        Parts_addLight_0(&st_1->parts_0, depth_3, cls_4, thr_2 * _S349 * leE_0 / _S346 * _S347, cd_4, cs_4);

#line 1396
                    }

                    if(track_0)
                    {
                        float vv_3 = lum_0(cd_4 + cs_4);
                        st_1->visTotal_0 = st_1->visTotal_0 + vv_3;
                        if(_S339)
                        {

#line 1402
                            vv_0 = 0.0f;

#line 1402
                        }
                        else
                        {

#line 1402
                            vv_0 = vv_3;

#line 1402
                        }

#line 1402
                        st_1->visLit_0 = st_1->visLit_0 + vv_0;
                        if(kernelContext_33->params_0[int(41)] == 0U)
                        {

#line 1403
                            float3 _S350 = float3(cosi_7) ;
                            float3 _S351 = cd_4 / _S350;

#line 1404
                            float3 _S352 = cs_4 / _S350;

#line 1404
                            if(_S339)
                            {

#line 1404
                                us_0 = 0.0f;

#line 1404
                            }
                            else
                            {

#line 1404
                                us_0 = 1.0f;

#line 1404
                            }

#line 1404
                            if(_S339)
                            {

#line 1404
                                _S203 = 0.0f;

#line 1404
                            }
                            else
                            {

#line 1404
                                _S203 = cosi_7;

#line 1404
                            }

#line 1404
                            addSlot_0(pixel_7, 3U, _S351, _S352, _S338, us_0, _S203, kernelContext_33);

#line 1403
                        }

#line 1398
                    }

#line 1387
                }

#line 1383
            }

#line 1373
        }

#line 1412
        float lobe_0 = Rng_next_0(&rng_4);
        float u1_3 = Rng_next_0(&rng_4);
        float u2_3 = Rng_next_0(&rng_4);
        float u3_1 = Rng_next_0(&rng_4);

#line 1421
        if(((&surf_3)->coat_0) > 0.0f)
        {

#line 1421
            float _S353 = Rng_next_0(&rng_4);

#line 1421
            vv_0 = _S353;

#line 1421
        }
        else
        {

#line 1421
            vv_0 = 1.0f;

#line 1421
        }
        if(((&surf_3)->sheenP_0) > 0.0f)
        {

#line 1422
            float _S354 = Rng_next_0(&rng_4);

#line 1422
            us_0 = _S354;

#line 1422
        }
        else
        {

#line 1422
            us_0 = 1.0f;

#line 1422
        }
        if(vv_0 < ((&surf_3)->coatP_0))
        {
            float3 h_10 = sampleVndf_0(woL_6, (&surf_3)->coatAlpha_0, u1_3, u2_3);
            float woh_0 = dot(woL_6, h_10);
            float3 wiL_9 = float3((2.0f * woh_0))  * h_10 - woL_6;
            float _S355 = wiL_9.z;
            float3 _S356 = float3((fresnelDielectric_0(woh_0, 1.5f) / coatF_0 * G1_0(max(_S355, 0.0f), (&surf_3)->coatAlpha_0))) ;

#line 1429
            ok_0 = _S355 > 0.0f;

#line 1429
            lobeCls_0 = 1U;

#line 1429
            refracted_0 = false;

#line 1429
            wi_6 = wiL_9;

#line 1429
            li_0 = _S356;

#line 1423
        }
        else
        {

#line 1431
            if(us_0 < ((&surf_3)->sheenP_0))
            {

                float3 wiL_10 = cosineLocal_0(u1_3, u2_3);

                float _S357 = wiL_10.z;

#line 1436
                float3 _S358 = (&surf_3)->sheenColor_0 * float3(sheenCore_0(_S279, _S357, normalize(woL_6 + wiL_10).z, (&surf_3)->sheenAlpha_0))  * float3(3.1415927410125732f)  / float3((_S357 * (&surf_3)->sheenP_0)) ;

#line 1436
                ok_0 = true;

#line 1436
                lobeCls_0 = 1U;

#line 1436
                refracted_0 = false;

#line 1436
                wi_6 = wiL_10;

#line 1436
                li_0 = _S358;

#line 1431
            }
            else
            {

#line 1438
                if(lobe_0 < metallic_1)
                {
                    float3 h_11 = sampleVndf_0(woL_6, _S278, u1_3, u2_3);
                    float woh_1 = dot(woL_6, h_11);
                    float3 wiL_11 = float3((2.0f * woh_1))  * h_11 - woL_6;
                    float _S359 = wiL_11.z;

#line 1443
                    bool _S360 = _S359 > 0.0f;
                    float3 _S361 = schlick_0(albedo_2, woh_1);

#line 1444
                    thread Surface_0 _S362 = surf_3;

#line 1444
                    float3 _S363 = multiscatterFactor_0(&_S362, _S279, kernelContext_33);

#line 1444
                    float3 _S364 = _S361 * _S363 * float3(G1_0(max(_S359, 0.0f), _S278)) ;

#line 1444
                    ok_0 = _S360;

#line 1444
                    lobeCls_0 = 1U;

#line 1444
                    refracted_0 = false;

#line 1444
                    wi_6 = wiL_11;

#line 1444
                    li_0 = _S364;

#line 1438
                }
                else
                {

#line 1446
                    if(lobe_0 < (metallic_1 + (1.0f - metallic_1) * transmission_2))
                    {
                        float3 h_12 = sampleVndf_0(woL_6, _S278, u1_3, u2_3);
                        float woh_2 = dot(woL_6, h_12);
                        if(u3_1 < (fresnelDielectric_0(woh_2, eta_2)))
                        {
                            float3 wiL_12 = float3((2.0f * woh_2))  * h_12 - woL_6;
                            float _S365 = wiL_12.z;
                            float3 _S366 = float3((G1_0(max(_S365, 0.0f), _S278) * (&surf_3)->tComp_0)) ;

#line 1454
                            ok_0 = _S365 > 0.0f;

#line 1454
                            lobeCls_0 = 1U;

#line 1454
                            refracted_0 = false;

#line 1454
                            wi_6 = wiL_12;

#line 1454
                            li_0 = _S366;

#line 1450
                        }
                        else
                        {

#line 1458
                            float r_7 = 1.0f / eta_2;
                            float k_5 = 1.0f - r_7 * r_7 * (1.0f - woh_2 * woh_2);

#line 1459
                            float3 _S367 = float3(r_7) ;
                            float3 wiL_13 = - woL_6 * _S367 + float3((r_7 * woh_2 - sqrt(max(k_5, 0.0f))))  * h_12;
                            float _S368 = wiL_13.z;

#line 1461
                            if(_S368 < 0.0f)
                            {

#line 1461
                                ok_0 = k_5 > 0.0f;

#line 1461
                            }
                            else
                            {

#line 1461
                                ok_0 = false;

#line 1461
                            }



                            float3 _S369 = albedo_2 * float3(G1_0(max(- _S368, 0.0f), _S278))  * _S367 * _S367 * float3((&surf_3)->tComp_0) ;

#line 1465
                            lobeCls_0 = 2U;

#line 1465
                            refracted_0 = true;

#line 1465
                            wi_6 = wiL_13;

#line 1465
                            li_0 = _S369;

#line 1450
                        }

#line 1446
                    }
                    else
                    {

#line 1468
                        if(u3_1 < fSel_1)
                        {
                            float3 h_13 = sampleVndf_0(woL_6, _S278, u1_3, u2_3);
                            float woh_3 = dot(woL_6, h_13);
                            float3 wiL_14 = float3((2.0f * woh_3))  * h_13 - woL_6;
                            float _S370 = wiL_14.z;
                            float3 _S371 = float3((fresnelDielectric_0(woh_3, wB_0) / fSel_1 * G1_0(max(_S370, 0.0f), _S278))) ;

#line 1474
                            ok_0 = _S370 > 0.0f;

#line 1474
                            lobeCls_0 = 1U;

#line 1474
                            wi_6 = wiL_14;

#line 1474
                            li_0 = _S371;

#line 1468
                        }
                        else
                        {

#line 1478
                            float3 _S372 = cosineLocal_0(u1_3, u2_3);

#line 1478
                            ok_0 = true;

#line 1478
                            lobeCls_0 = 0U;

#line 1478
                            wi_6 = _S372;

#line 1478
                            li_0 = albedo_2;

#line 1468
                        }

#line 1468
                        refracted_0 = false;

#line 1446
                    }

#line 1438
                }

#line 1431
            }

#line 1423
        }

#line 1482
        if(!ok_0)
        {

#line 1482
            alive_0 = false;

#line 1482
            thr_1 = thr_2;
            break;
        }

#line 1484
        if(depth_3 == 0U)
        {

#line 1484
            cls_5 = lobeCls_0;

#line 1484
        }
        else
        {

#line 1484
            cls_5 = cls_4;

#line 1484
        }

        st_1->misPrev_0 = !refracted_0;
        if(refracted_0)
        {

#line 1487
            _S203 = 0.0f;

#line 1487
        }
        else
        {

#line 1487
            thread Surface_0 _S373 = surf_3;

#line 1487
            float _S374 = reflectivePdf_0(&_S373, woL_6, wi_6);

#line 1487
            _S203 = _S374;

#line 1487
        }

#line 1487
        st_1->qPrev_0 = _S203;
        st_1->prevInst_0 = _S217 + 1U;

        float3 dir_3 = normalize(float3(wi_6.x)  * T_2 + float3(wi_6.y)  * B_2 + float3(wi_6.z)  * n_8);

        float side_0 = dot(dir_3, ng_0);
        if(refracted_0)
        {

#line 1493
            track_0 = side_0 >= 0.0f;

#line 1493
        }
        else
        {

#line 1493
            track_0 = side_0 <= 0.0f;

#line 1493
        }

#line 1493
        if(track_0)
        {

#line 1493
            dir_2 = dir_3;

#line 1493
            cls_4 = cls_5;

#line 1493
            alive_0 = false;

#line 1493
            thr_1 = thr_2;
            break;
        }

#line 1495
        if(side_0 > 0.0f)
        {

#line 1495
            _S204 = 9.9999997473787516e-05f;

#line 1495
        }
        else
        {

#line 1495
            _S204 = -9.9999997473787516e-05f;

#line 1495
        }

#line 1495
        float3 _S375 = hit_1 + ng_0 * float3(_S204) ;
        float3 thr_4 = thr_2 * li_0;

        if(depth_3 >= 2U)
        {
            float pr_0 = clamp(max(thr_4.x, max(thr_4.y, thr_4.z)), 0.05000000074505806f, 0.94999998807907104f);
            float _S376 = Rng_next_0(&rng_4);

#line 1501
            if(_S376 > pr_0)
            {

#line 1501
                org_2 = _S375;

#line 1501
                dir_2 = dir_3;

#line 1501
                cls_4 = cls_5;

#line 1501
                alive_0 = false;

#line 1501
                thr_1 = thr_4;
                break;
            }

#line 1502
            thr_1 = thr_4 / float3(pr_0) ;

#line 1498
        }
        else
        {

#line 1498
            thr_1 = thr_4;

#line 1498
        }

#line 990
        uint _S377 = once_0 + 1U;

#line 990
        cls_4 = cls_5;

#line 990
        dir_2 = dir_3;

#line 990
        org_2 = _S375;

#line 990
        chan_2 = chan_1;

#line 990
        once_0 = _S377;

#line 990
    }

#line 1506
    st_1->rng_0 = (&rng_4)->state_0;
    st_1->org_0 = org_2;
    st_1->dir_0 = dir_2;
    st_1->thr_0 = thr_1;
    st_1->cls_0 = cls_4;
    st_1->chan_0 = chan_1;
    if(depth_3 == 0U)
    {

#line 1512
        _S202 = st_1->gi_0;

#line 1512
    }
    else
    {

#line 1512
        _S202 = false;

#line 1512
    }

#line 1512
    if(_S202)
    {

        uint so_1 = restirScratch_0(pixel_7);

#line 1515
        k_4 = 0U;
        for(;;)
        {

#line 1516
            if(k_4 < 3U)
            {
            }
            else
            {

#line 1516
                break;
            }
            *(kernelContext_33->restir_0+(so_1 + 15U + k_4)) = thr_1[k_4];
            *(kernelContext_33->restir_0+(so_1 + 18U + k_4)) = (&st_1->parts_0)->total_0[k_4];

#line 1516
            k_4 = k_4 + 1U;

#line 1516
        }

#line 1521
        *(kernelContext_33->restir_0+(so_1 + 21U)) = st_1->qPrev_0;

#line 1512
    }

#line 1523
    return alive_0;
}


#line 1547
float3 giFinish_0(float3 pathTotal_0, uint pixel_8, KernelContext_0 thread* kernelContext_34)
{
    uint co_3 = restirBase_0(pixel_8, kernelContext_34->params_0[int(6)] & 1U);
    uint so_2 = restirScratch_0(pixel_8);
    float wsum_5 = *(kernelContext_34->restir_0+so_2);
    float m_1 = *(kernelContext_34->restir_0+(so_2 + 1U)) + 1.0f;
    float _S378 = *(kernelContext_34->restir_0+(so_2 + 2U));
    float3 _S379 = float3(*(kernelContext_34->restir_0+(so_2 + 3U)), *(kernelContext_34->restir_0+(so_2 + 4U)), *(kernelContext_34->restir_0+(so_2 + 5U)));
    float3 _S380 = float3(*(kernelContext_34->restir_0+(so_2 + 6U)), *(kernelContext_34->restir_0+(so_2 + 7U)), *(kernelContext_34->restir_0+(so_2 + 8U)));
    float3 _S381 = float3(*(kernelContext_34->restir_0+(so_2 + 9U)), *(kernelContext_34->restir_0+(so_2 + 10U)), *(kernelContext_34->restir_0+(so_2 + 11U)));
    float3 _S382 = float3(*(kernelContext_34->restir_0+(so_2 + 12U)), *(kernelContext_34->restir_0+(so_2 + 13U)), *(kernelContext_34->restir_0+(so_2 + 14U)));
    float _S383 = *(kernelContext_34->restir_0+(so_2 + 15U));

#line 1558
    float _S384 = *(kernelContext_34->restir_0+(so_2 + 16U));

#line 1558
    float _S385 = *(kernelContext_34->restir_0+(so_2 + 17U));
    float3 d0_0 = float3(*(kernelContext_34->restir_0+(so_2 + 18U)), *(kernelContext_34->restir_0+(so_2 + 19U)), *(kernelContext_34->restir_0+(so_2 + 20U)));
    float qPrev_1 = *(kernelContext_34->restir_0+(so_2 + 21U));

#line 1560
    bool own_0;
    if((as_type<uint>((*(kernelContext_34->restir_0+(so_2 + 22U))))) != 0U)
    {

#line 1561
        own_0 = qPrev_1 > 0.0f;

#line 1561
    }
    else
    {

#line 1561
        own_0 = false;

#line 1561
    }
    float3 giTotal_0 = pathTotal_0 - d0_0;

#line 1562
    float pSel_2;

#line 1562
    float wsum_6;

#line 1562
    float W_1;

#line 1562
    float3 cSel_2;

#line 1562
    float3 xSel_2;

#line 1562
    float3 nSel_2;

#line 1562
    float3 lSel_2;

#line 1562
    float3 result_0;

    if(own_0)
    {
        float3 cOwn_0 = giTotal_0 * float3(qPrev_1) ;
        float pOwn_0 = lum_0(cOwn_0);
        if(pOwn_0 > 0.0f)
        {
            float wOwn_0 = pOwn_0 / qPrev_1;
            float wsum_7 = wsum_5 + wOwn_0;
            thread Rng_0 r_8;
            (&r_8)->state_0 = pcg_0(pixel_8 ^ (pcg_0(kernelContext_34->params_0[int(6)] * 2246822507U + 4660U)));
            float _S386 = Rng_next_0(&r_8);

#line 1574
            if((_S386 * wsum_7) < wOwn_0)
            {


                float3 _S387 = float3(*(kernelContext_34->restir_0+(co_3 + 16U)), *(kernelContext_34->restir_0+(co_3 + 17U)), *(kernelContext_34->restir_0+(co_3 + 18U)));
                float3 _S388 = float3(*(kernelContext_34->restir_0+(co_3 + 19U)), *(kernelContext_34->restir_0+(co_3 + 20U)), *(kernelContext_34->restir_0+(co_3 + 21U)));
                if(_S383 > 9.99999997475242708e-07f)
                {

#line 1580
                    pSel_2 = giTotal_0.x / _S383;

#line 1580
                }
                else
                {

#line 1580
                    pSel_2 = 0.0f;

#line 1580
                }

#line 1580
                if(_S384 > 9.99999997475242708e-07f)
                {

#line 1580
                    wsum_6 = giTotal_0.y / _S384;

#line 1580
                }
                else
                {

#line 1580
                    wsum_6 = 0.0f;

#line 1580
                }

#line 1580
                if(_S385 > 9.99999997475242708e-07f)
                {

#line 1580
                    W_1 = giTotal_0.z / _S385;

#line 1580
                }
                else
                {

#line 1580
                    W_1 = 0.0f;

#line 1580
                }

#line 1580
                float3 _S389 = float3(pSel_2, wsum_6, W_1);

#line 1580
                pSel_2 = pOwn_0;

#line 1580
                cSel_2 = cOwn_0;

#line 1580
                xSel_2 = _S387;

#line 1580
                nSel_2 = _S388;

#line 1580
                lSel_2 = _S389;

#line 1574
            }
            else
            {

#line 1574
                pSel_2 = _S378;

#line 1574
                cSel_2 = _S379;

#line 1574
                xSel_2 = _S380;

#line 1574
                nSel_2 = _S381;

#line 1574
                lSel_2 = _S382;

#line 1574
            }

#line 1574
            wsum_6 = wsum_7;

#line 1568
        }
        else
        {

#line 1568
            pSel_2 = _S378;

#line 1568
            cSel_2 = _S379;

#line 1568
            xSel_2 = _S380;

#line 1568
            nSel_2 = _S381;

#line 1568
            lSel_2 = _S382;

#line 1568
            wsum_6 = wsum_5;

#line 1568
        }

#line 1568
        result_0 = d0_0;

#line 1564
    }
    else
    {

#line 1585
        float3 result_1 = d0_0 + giTotal_0;

#line 1585
        pSel_2 = _S378;

#line 1585
        cSel_2 = _S379;

#line 1585
        xSel_2 = _S380;

#line 1585
        nSel_2 = _S381;

#line 1585
        lSel_2 = _S382;

#line 1585
        wsum_6 = wsum_5;

#line 1585
        result_0 = result_1;

#line 1564
    }

#line 1586
    bool _S390 = pSel_2 > 0.0f;

#line 1586
    if(_S390)
    {

#line 1586
        W_1 = wsum_6 / (m_1 * pSel_2);

#line 1586
    }
    else
    {

#line 1586
        W_1 = 0.0f;

#line 1586
    }
    float3 result_2 = result_0 + cSel_2 * float3(W_1) ;

#line 1587
    uint k_6 = 0U;
    for(;;)
    {

#line 1588
        if(k_6 < 3U)
        {
        }
        else
        {

#line 1588
            break;
        }
        *(kernelContext_34->restir_0+(co_3 + 16U + k_6)) = xSel_2[k_6];
        *(kernelContext_34->restir_0+(co_3 + 19U + k_6)) = nSel_2[k_6];
        *(kernelContext_34->restir_0+(co_3 + 22U + k_6)) = lSel_2[k_6];

#line 1588
        k_6 = k_6 + 1U;

#line 1588
    }

#line 1594
    *(kernelContext_34->restir_0+(co_3 + 25U)) = W_1;
    *(kernelContext_34->restir_0+(co_3 + 26U)) = m_1;
    float device* _S391 = kernelContext_34->restir_0+(co_3 + 27U);

#line 1596
    if(_S390)
    {

#line 1596
        k_6 = 1U;

#line 1596
    }
    else
    {

#line 1596
        k_6 = 0U;

#line 1596
    }

#line 1596
    *_S391 = (as_type<float>((k_6)));
    return result_2;
}


void finishPath_0(const PathState_0 thread* st_2, uint pixel_9, KernelContext_0 thread* kernelContext_35)
{

#line 1601
    Parts_0 _S392 = st_2->parts_0;

#line 1601
    float _S393 = st_2->visLit_0;

#line 1601
    float _S394 = st_2->visTotal_0;

#line 1601
    float3 _S395 = (&st_2->parts_0)->total_0;

#line 1601
    float3 radiance_0;

#line 1607
    if(st_2->gi_0)
    {


        if((st_2->chan_0) >= int(0))
        {

#line 1612
            *(kernelContext_35->restir_0+(restirScratch_0(pixel_9) + 22U)) = (as_type<float>((0U)));

#line 1611
        }

#line 1611
        float3 _S396 = giFinish_0(_S395, pixel_9, kernelContext_35);

#line 1611
        radiance_0 = _S396;

#line 1607
    }
    else
    {

#line 1607
        radiance_0 = _S395;

#line 1607
    }

#line 1607
    bool _S397;

#line 1615
    if(any(isnan(radiance_0)))
    {

#line 1615
        _S397 = true;

#line 1615
    }
    else
    {

#line 1615
        _S397 = any(isinf(radiance_0));

#line 1615
    }

#line 1615
    Parts_0 parts_1;

#line 1615
    float visLit_1;

#line 1615
    float visTotal_1;

#line 1615
    if(_S397)
    {
        float3 _S398 = float3(0.0f) ;

#line 1617
        radiance_0 = _S398;

#line 1617
        (&parts_1)->total_0 = _S398;

#line 1617
        (&parts_1)->directDiffuse_0 = _S398;

#line 1617
        (&parts_1)->indirectDiffuse_0 = _S398;

#line 1617
        (&parts_1)->specular_0 = _S398;

#line 1617
        (&parts_1)->transmission_0 = _S398;

#line 1617
        (&parts_1)->emission_0 = _S398;

#line 1617
        visLit_1 = 0.0f;

#line 1617
        visTotal_1 = 0.0f;

#line 1615
    }
    else
    {

#line 1615
        parts_1 = _S392;

#line 1615
        visLit_1 = _S393;

#line 1615
        visTotal_1 = _S394;

#line 1615
    }

#line 1623
    uint o_8 = 3U * pixel_9;
    float device* _S399 = kernelContext_35->accum_0+o_8;

#line 1624
    *_S399 = *_S399 + radiance_0.x;
    uint _S400 = o_8 + 1U;

#line 1625
    float device* _S401 = kernelContext_35->accum_0+_S400;

#line 1625
    *_S401 = *_S401 + radiance_0.y;
    uint _S402 = o_8 + 2U;

#line 1626
    float device* _S403 = kernelContext_35->accum_0+_S402;

#line 1626
    *_S403 = *_S403 + radiance_0.z;
    if(kernelContext_35->params_0[int(32)] != 0U)
    {
        float l_1 = lum_0(radiance_0);
        float device* _S404 = kernelContext_35->pixelStats_0+o_8;

#line 1630
        *_S404 = *_S404 + 1.0f;
        float device* _S405 = kernelContext_35->pixelStats_0+_S400;

#line 1631
        *_S405 = *_S405 + l_1;
        float device* _S406 = kernelContext_35->pixelStats_0+_S402;

#line 1632
        *_S406 = *_S406 + l_1 * l_1;

#line 1627
    }

#line 1635
    if(kernelContext_35->params_0[int(28)] != 0U)
    {
        uint lo_3 = 65U * pixel_9;
        array<float3, int(5)> _S407 = { { parts_1.directDiffuse_0, parts_1.indirectDiffuse_0, parts_1.specular_0, parts_1.transmission_0, parts_1.emission_0 } };

#line 1638
        uint k_7 = 0U;
        for(;;)
        {

#line 1639
            if(k_7 < 5U)
            {
            }
            else
            {

#line 1639
                break;
            }
            uint _S408 = lo_3 + 3U * k_7;

#line 1641
            float device* _S409 = kernelContext_35->lighting_0+_S408;

#line 1641
            *_S409 = *_S409 + _S407[k_7].x;
            float device* _S410 = kernelContext_35->lighting_0+(_S408 + 1U);

#line 1642
            *_S410 = *_S410 + _S407[k_7].y;
            float device* _S411 = kernelContext_35->lighting_0+(_S408 + 2U);

#line 1643
            *_S411 = *_S411 + _S407[k_7].z;

#line 1639
            k_7 = k_7 + 1U;

#line 1639
        }

#line 1645
        float device* _S412 = kernelContext_35->lighting_0+(lo_3 + 15U);

#line 1645
        *_S412 = *_S412 + visLit_1;
        float device* _S413 = kernelContext_35->lighting_0+(lo_3 + 16U);

#line 1646
        *_S413 = *_S413 + visTotal_1;

#line 1635
    }

#line 1648
    return;
}


#line 9 "shaders/pathtrace.slang"
[[kernel]] void pathtrace(uint3 tid_0 [[thread_position_in_grid]], uint device* params_1 [[buffer(6)]], float device* pixelStats_1 [[buffer(18)]], metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_1 [[buffer(0)]], float device* restir_2 [[buffer(19)]], float device* envPixels_1 [[buffer(10)]], uint device* instances_1 [[buffer(3)]], uint device* indices_1 [[buffer(2)]], float device* positions_1 [[buffer(1)]], float device* materials_1 [[buffer(4)]], float device* vnormals_1 [[buffer(16)]], float device* uvs_1 [[buffer(13)]], uint device* texInfo_1 [[buffer(15)]], float device* texels_1 [[buffer(14)]], uint device* lights_1 [[buffer(5)]], float device* emitters_1 [[buffer(8)]], float device* lighting_1 [[buffer(17)]], float device* emitCdf_1 [[buffer(9)]], float device* envMarginal_1 [[buffer(11)]], float device* envCond_1 [[buffer(12)]], float device* accum_1 [[buffer(7)]])
{

#line 9
    thread KernelContext_0 kernelContext_36;

#line 9
    (&kernelContext_36)->params_0 = params_1;

#line 9
    (&kernelContext_36)->pixelStats_0 = pixelStats_1;

#line 9
    (&kernelContext_36)->scene_0 = scene_1;

#line 9
    (&kernelContext_36)->restir_0 = restir_2;

#line 9
    (&kernelContext_36)->envPixels_0 = envPixels_1;

#line 9
    (&kernelContext_36)->instances_0 = instances_1;

#line 9
    (&kernelContext_36)->indices_0 = indices_1;

#line 9
    (&kernelContext_36)->positions_0 = positions_1;

#line 9
    (&kernelContext_36)->materials_0 = materials_1;

#line 9
    (&kernelContext_36)->vnormals_0 = vnormals_1;

#line 9
    (&kernelContext_36)->uvs_0 = uvs_1;

#line 9
    (&kernelContext_36)->texInfo_0 = texInfo_1;

#line 9
    (&kernelContext_36)->texels_0 = texels_1;

#line 9
    (&kernelContext_36)->lights_0 = lights_1;

#line 9
    (&kernelContext_36)->emitters_0 = emitters_1;

#line 9
    (&kernelContext_36)->lighting_0 = lighting_1;

#line 9
    (&kernelContext_36)->emitCdf_0 = emitCdf_1;

#line 9
    (&kernelContext_36)->envMarginal_0 = envMarginal_1;

#line 9
    (&kernelContext_36)->envCond_0 = envCond_1;

#line 9
    (&kernelContext_36)->accum_0 = accum_1;

    uint _S414 = tid_0.x;

#line 11
    bool _S415;

#line 11
    if(_S414 >= params_1[int(0)])
    {

#line 11
        _S415 = true;

#line 11
    }
    else
    {

#line 11
        _S415 = (tid_0.y) >= ((&kernelContext_36)->params_0)[int(1)];

#line 11
    }

#line 11
    if(_S415)
    {

#line 12
        return;
    }

#line 13
    uint _S416 = tid_0.y;

#line 13
    uint _S417 = _S416 * (&kernelContext_36)->params_0[int(0)] + _S414;

#line 13
    uint k_8 = 0U;
    for(;;)
    {

#line 14
        if(k_8 < ((&kernelContext_36)->params_0)[int(35)])
        {
        }
        else
        {

#line 14
            break;
        }
        if((&kernelContext_36)->params_0[int(32)] != 0U)
        {

#line 16
            bool _S418 = pixelActive_0(_S417, &kernelContext_36);

#line 16
            _S415 = !_S418;

#line 16
        }
        else
        {

#line 16
            _S415 = false;

#line 16
        }

#line 16
        if(_S415)
        {

#line 17
            return;
        }

#line 17
        PathState_0 _S419 = generatePathFor_0(_S414, _S416, (&kernelContext_36)->params_0[int(6)] + k_8, &kernelContext_36);
        thread PathState_0 st_3 = _S419;

#line 18
        uint depth_4 = 0U;
        for(;;)
        {

#line 19
            if(depth_4 < ((&kernelContext_36)->params_0)[int(7)])
            {
            }
            else
            {

#line 19
                break;
            }

#line 19
            Hit_0 _S420 = traceClosest_0((&st_3)->org_0, (&st_3)->dir_0, &kernelContext_36);

#line 19
            thread Hit_0 _S421 = _S420;

#line 19
            bool _S422 = shadePath_0(&st_3, &_S421, depth_4, _S417, &kernelContext_36);

            if(!_S422)
            {

#line 22
                break;
            }

#line 19
            depth_4 = depth_4 + 1U;

#line 19
        }

#line 19
        thread PathState_0 _S423 = st_3;

#line 19
        finishPath_0(&_S423, _S417, &kernelContext_36);

#line 14
        k_8 = k_8 + 1U;

#line 14
    }

#line 26
    return;
}

