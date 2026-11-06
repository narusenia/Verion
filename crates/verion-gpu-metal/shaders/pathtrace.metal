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
    float device* uvs_0;
    uint device* texInfo_0;
    float device* texels_0;
    float device* vnormals_0;
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


#line 1551
bool pixelActive_0(uint p_0, KernelContext_0 thread* kernelContext_1)
{
    uint _S1 = 3U * p_0;

#line 1553
    float device* _S2 = kernelContext_1->pixelStats_0+_S1;

#line 1553
    float n_0 = *_S2;
    if((*_S2) < float(kernelContext_1->params_0[int(34)]))
    {

#line 1555
        return true;
    }

#line 1556
    float mean_0 = *(kernelContext_1->pixelStats_0+(_S1 + 1U)) / n_0;

    float _S3 = sqrt(max(*(kernelContext_1->pixelStats_0+(_S1 + 2U)) / n_0 - mean_0 * mean_0, 0.0f) * n_0 / (n_0 - 1.0f) / n_0);

#line 1558
    float _S4 = pf_0(33U, kernelContext_1);

#line 1558
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


#line 616
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


#line 645
PathState_0 generatePathFor_0(uint px_0, uint py_0, uint sample_0, KernelContext_0 thread* kernelContext_2)
{
    uint w_1 = kernelContext_2->params_0[int(0)];
    uint h_0 = kernelContext_2->params_0[int(1)];

    thread Rng_0 rng_1;
    (&rng_1)->state_0 = pcg_0((py_0 * w_1 + px_0) ^ (pcg_0(sample_0 * 2654435769U + 2135587861U)));

#line 651
    float _S6 = pf_0(2U, kernelContext_2);

    float _S7 = float(w_1);

#line 653
    float _S8 = float(h_0);

#line 653
    float aspect_0 = _S7 / _S8;
    float _S9 = float(px_0);

#line 654
    float _S10 = Rng_next_0(&rng_1);

#line 654
    float _S11 = 2.0f * (_S9 + _S10) / _S7 - 1.0f;

#line 654
    float _S12 = pf_0(39U, kernelContext_2);

#line 654
    float u_0 = (_S11 + _S12) * aspect_0 * _S6;
    float _S13 = float(py_0);

#line 655
    float _S14 = Rng_next_0(&rng_1);

#line 655
    float _S15 = 1.0f - 2.0f * (_S13 + _S14) / _S8;

#line 655
    float _S16 = pf_0(40U, kernelContext_2);
    float3 _S17 = float3(u_0, (_S15 + _S16) * _S6, -1.0f);

#line 656
    float _S18 = pf_0(4U, kernelContext_2);

#line 656
    float3 focal_0 = _S17 * float3(_S18) ;

#line 656
    float _S19 = pf_0(3U, kernelContext_2);
    float _S20 = Rng_next_0(&rng_1);

#line 657
    float lensR_0 = _S19 * sqrt(_S20);
    float _S21 = Rng_next_0(&rng_1);

#line 658
    float lensA_0 = 6.2831854820251465f * _S21;
    float _S22 = lensR_0 * cos(lensA_0);

#line 659
    float _S23 = lensR_0 * sin(lensA_0);
    float3 _S24 = normalize(focal_0 - float3(_S22, _S23, 0.0f));
    thread PathState_0 s_1;

#line 661
    uint r_0 = 0U;
    for(;;)
    {

#line 662
        if(r_0 < 3U)
        {
        }
        else
        {

#line 662
            break;
        }
        uint _S25 = 4U * r_0;

#line 664
        uint _S26 = 8U + _S25;

#line 664
        uint _S27 = 9U + _S25;

#line 664
        uint _S28 = 10U + _S25;

#line 664
        (&s_1)->org_0[r_0] = (as_type<float>((kernelContext_2->params_0[_S26]))) * _S22 + (as_type<float>((kernelContext_2->params_0[_S27]))) * _S23 + (as_type<float>((kernelContext_2->params_0[_S28]))) * 0.0f + (as_type<float>((kernelContext_2->params_0[11U + _S25])));
        (&s_1)->dir_0[r_0] = (as_type<float>((kernelContext_2->params_0[_S26]))) * _S24.x + (as_type<float>((kernelContext_2->params_0[_S27]))) * _S24.y + (as_type<float>((kernelContext_2->params_0[_S28]))) * _S24.z;

#line 662
        r_0 = r_0 + 1U;

#line 662
    }

#line 667
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

#line 680
    (&(&s_1)->parts_0)->total_0 = _S29;

#line 680
    (&(&s_1)->parts_0)->directDiffuse_0 = _S29;

#line 680
    (&(&s_1)->parts_0)->indirectDiffuse_0 = _S29;

#line 680
    (&(&s_1)->parts_0)->specular_0 = _S29;

#line 680
    (&(&s_1)->parts_0)->transmission_0 = _S29;

#line 680
    (&(&s_1)->parts_0)->emission_0 = _S29;
    return s_1;
}


#line 636
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


#line 684 "shaders/include/pt_core.slang"
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

#line 693
        bool _S30 = ((&q_0)->next());

#line 693
        if(_S30)
        {
        }
        else
        {

#line 693
            break;
        }

#line 693
    }
    thread Hit_0 h_1;
    uint _S31 = (_slang_committed_intersection_type_to_uint((&q_0)->get_committed_intersection_type()));

#line 695
    bool _S32 = _S31 == 1U;

#line 695
    (&h_1)->hit_0 = _S32;

#line 695
    uint _S33;
    if(_S32)
    {

#line 696
        uint _S34 = ((&q_0)->get_committed_instance_id());

#line 696
        _S33 = _S34;

#line 696
    }
    else
    {

#line 696
        _S33 = 0U;

#line 696
    }

#line 696
    (&h_1)->inst_0 = _S33;
    if((&h_1)->hit_0)
    {

#line 697
        uint _S35 = ((&q_0)->get_committed_primitive_id());

#line 697
        _S33 = _S35;

#line 697
    }
    else
    {

#line 697
        _S33 = 0U;

#line 697
    }

#line 697
    (&h_1)->prim_0 = _S33;

#line 697
    float _S36;
    if((&h_1)->hit_0)
    {

#line 698
        float _S37 = ((&q_0)->get_committed_distance());

#line 698
        _S36 = _S37;

#line 698
    }
    else
    {

#line 698
        _S36 = 0.0f;

#line 698
    }

#line 698
    (&h_1)->t_0 = _S36;
    return h_1;
}


#line 53
constant bool fc_restirCompiled_0 [[function_constant(0)]];
constant bool restirCompiled_0 = is_function_constant_defined(fc_restirCompiled_0) ? fc_restirCompiled_0 : true;

#line 712
uint restirBase_0(uint pixel_0, uint which_0)
{

#line 712
    return pixel_0 * 80U + which_0 * 28U;
}


#line 983
void restirClear_0(uint pixel_1, KernelContext_0 thread* kernelContext_4)
{
    uint co_0 = restirBase_0(pixel_1, kernelContext_4->params_0[int(6)] & 1U);
    float _S38 = (as_type<float>((0U)));

#line 986
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


#line 309
float3 texelAt_0(uint base_1, uint w_3, uint h_3, int x_1, int y_0, KernelContext_0 thread* kernelContext_11)
{
    int _S44 = int(w_3);

#line 311
    int _S45 = x_1 % _S44;

#line 311
    int _S46 = (_S45 + _S44) % _S44;

#line 311
    uint xi_0 = uint(_S46);
    int _S47 = int(h_3);

#line 312
    int _S48 = y_0 % _S47;

#line 312
    int _S49 = (_S48 + _S47) % _S47;
    uint o_2 = 3U * (base_1 + uint(_S49) * w_3 + xi_0);
    return float3(kernelContext_11->texels_0[o_2], kernelContext_11->texels_0[o_2 + 1U], kernelContext_11->texels_0[o_2 + 2U]);
}

float3 bilinear_0(uint base_2, uint w_4, uint h_4, float2 uv_0, KernelContext_0 thread* kernelContext_12)
{
    float fx_0 = uv_0.x * float(w_4) - 0.5f;
    float fy_0 = uv_0.y * float(h_4) - 0.5f;
    int x0_0 = int(floor(fx_0));
    int y0_0 = int(floor(fy_0));
    float tx_0 = fx_0 - float(x0_0);
    float ty_0 = fy_0 - float(y0_0);

#line 324
    float3 _S50 = texelAt_0(base_2, w_4, h_4, x0_0, y0_0, kernelContext_12);
    int _S51 = x0_0 + int(1);

#line 325
    float3 _S52 = texelAt_0(base_2, w_4, h_4, _S51, y0_0, kernelContext_12);

#line 325
    float3 _S53 = float3(tx_0) ;

#line 325
    float3 a_0 = mix(_S50, _S52, _S53);
    int _S54 = y0_0 + int(1);

#line 326
    float3 _S55 = texelAt_0(base_2, w_4, h_4, x0_0, _S54, kernelContext_12);

#line 326
    float3 _S56 = texelAt_0(base_2, w_4, h_4, _S51, _S54, kernelContext_12);
    return mix(a_0, mix(_S55, _S56, _S53), float3(ty_0) );
}


float3 sampleTexture_0(uint tex_0, float2 uv_1, float footprint_0, KernelContext_0 thread* kernelContext_13)
{
    uint ti_0 = tex_0 * 4U;
    uint base_3 = kernelContext_13->texInfo_0[ti_0];
    uint w_5 = kernelContext_13->texInfo_0[ti_0 + 1U];
    uint h_5 = kernelContext_13->texInfo_0[ti_0 + 2U];
    uint levels_0 = kernelContext_13->texInfo_0[ti_0 + 3U];
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
    uint off_0 = base_3;



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
        uint _S57 = max(lw_0 / 2U, 1U);
        uint _S58 = max(lh_0 / 2U, 1U);

#line 344
        uint _S59 = k_0 + 1U;

#line 344
        lw_0 = _S57;

#line 344
        lh_0 = _S58;

#line 344
        k_0 = _S59;

#line 344
        off_0 = off_1;

#line 344
    }

#line 344
    float3 _S60 = bilinear_0(off_0, lw_0, lh_0, uv_1, kernelContext_13);

#line 344
    bool _S61;

#line 351
    if((l0_0 + 1U) >= levels_0)
    {

#line 351
        _S61 = true;

#line 351
    }
    else
    {

#line 351
        _S61 = t_1 <= 0.0f;

#line 351
    }

#line 351
    if(_S61)
    {

#line 352
        return _S60;
    }

#line 352
    float3 _S62 = bilinear_0(off_0 + lw_0 * lh_0, max(lw_0 / 2U, 1U), max(lh_0 / 2U, 1U), uv_1, kernelContext_13);


    return mix(_S60, _S62, float3(t_1) );
}


#line 561
float opacityAt_0(uint instIdx_0, uint prim_1, float2 bary_0, KernelContext_0 thread* kernelContext_14)
{
    uint _S63 = instIdx_0 * 16U;

#line 563
    uint mi_0 = kernelContext_14->instances_0[_S63 + 2U] * 24U;
    float op_0 = kernelContext_14->materials_0[mi_0 + 22U];
    uint tex_1 = uint(kernelContext_14->materials_0[mi_0 + 23U]);

#line 565
    bool _S64;
    if(tex_1 > 0U)
    {

#line 566
        _S64 = op_0 > 0.0f;

#line 566
    }
    else
    {

#line 566
        _S64 = false;

#line 566
    }

#line 566
    float op_1;

#line 566
    if(_S64)
    {
        uint tri_0 = kernelContext_14->instances_0[_S63 + 1U] + 3U * prim_1;
        uint vo_0 = kernelContext_14->instances_0[_S63];
        float2 uv0_0 = float2(kernelContext_14->uvs_0[2U * (kernelContext_14->indices_0[tri_0] + vo_0)], kernelContext_14->uvs_0[2U * (kernelContext_14->indices_0[tri_0] + vo_0) + 1U]);
        uint _S65 = tri_0 + 1U;
        uint _S66 = tri_0 + 2U;

#line 572
        float3 _S67 = sampleTexture_0(tex_1 - 1U, uv0_0 + float2(bary_0.x)  * (float2(kernelContext_14->uvs_0[2U * (kernelContext_14->indices_0[_S65] + vo_0)], kernelContext_14->uvs_0[2U * (kernelContext_14->indices_0[_S65] + vo_0) + 1U]) - uv0_0) + float2(bary_0.y)  * (float2(kernelContext_14->uvs_0[2U * (kernelContext_14->indices_0[_S66] + vo_0)], kernelContext_14->uvs_0[2U * (kernelContext_14->indices_0[_S66] + vo_0) + 1U]) - uv0_0), 0.0f, kernelContext_14);

#line 572
        op_1 = op_0 * _S67.x;

#line 566
    }
    else
    {

#line 566
        op_1 = op_0;

#line 566
    }

#line 575
    return op_1;
}


#line 713
uint restirScratch_0(uint pixel_2)
{

#line 713
    return pixel_2 * 80U + 56U;
}


#line 113
float3 vertexNormal_0(uint v_3, KernelContext_0 thread* kernelContext_15)
{

#line 113
    uint _S68 = 3U * v_3;

#line 113
    return float3(kernelContext_15->vnormals_0[_S68], kernelContext_15->vnormals_0[_S68 + 1U], kernelContext_15->vnormals_0[_S68 + 2U]);
}


#line 103
float3 transformNormal_0(uint base_4, float3 n_1, KernelContext_0 thread* kernelContext_16)
{
    float3 r0_0 = float3((as_type<float>((kernelContext_16->instances_0[base_4]))), (as_type<float>((kernelContext_16->instances_0[base_4 + 1U]))), (as_type<float>((kernelContext_16->instances_0[base_4 + 2U]))));
    float3 r1_0 = float3((as_type<float>((kernelContext_16->instances_0[base_4 + 4U]))), (as_type<float>((kernelContext_16->instances_0[base_4 + 5U]))), (as_type<float>((kernelContext_16->instances_0[base_4 + 6U]))));
    float3 r2_0 = float3((as_type<float>((kernelContext_16->instances_0[base_4 + 8U]))), (as_type<float>((kernelContext_16->instances_0[base_4 + 9U]))), (as_type<float>((kernelContext_16->instances_0[base_4 + 10U]))));
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


#line 195
uint emitMask_0(uint inst_1, KernelContext_0 thread* kernelContext_17)
{

#line 195
    return kernelContext_17->lights_0[kernelContext_17->params_0[int(5)] * 16U + 5888U + 2U * inst_1 + 1U];
}


#line 194
uint recvMask_0(uint inst_2, KernelContext_0 thread* kernelContext_18)
{

#line 194
    return kernelContext_18->lights_0[kernelContext_18->params_0[int(5)] * 16U + 5888U + 2U * inst_2];
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
    float3 _S69 = normalize(cross(n_2, a_1));

#line 158
    *b_0 = _S69;
    *t_2 = cross(_S69, n_2);
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
    float _S70 = eta_0 * cost_0;

#line 150
    float rs_0 = (cosi_0 - _S70) / (cosi_0 + _S70);
    float _S71 = eta_0 * cosi_0;

#line 151
    float rp_0 = (_S71 - cost_0) / (_S71 + cost_0);
    return 0.5f * (rs_0 * rs_0 + rp_0 * rp_0);
}


#line 192
float albedoAt_0(uint i_5, KernelContext_0 thread* kernelContext_19)
{

#line 192
    return (as_type<float>((kernelContext_19->lights_0[kernelContext_19->params_0[int(5)] * 16U + i_5])));
}


#line 410
float dielectricAlbedo_0(float cosO_0, float rough_0, float ior_0, bool outside_0, KernelContext_0 thread* kernelContext_20)
{
    float x_2 = saturate(cosO_0) * 15.0f;
    float y_1 = saturate(rough_0) * 15.0f;
    float z_0 = clamp((ior_0 - 1.0f) * 4.0f, 0.0f, 7.999000072479248f);
    uint _S72 = min(uint(x_2), 14U);
    uint _S73 = min(uint(y_1), 14U);
    uint z0_0 = uint(z_0);
    float _S74 = x_2 - float(_S72);
    float _S75 = y_1 - float(_S73);
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
    uint _S76 = k_1 * 16U * 16U;
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

        uint _S77 = 1280U + (_S76 + ((z0_0 + k_1) * 16U + _S73) * 16U + _S72);

#line 426
        float _S78 = albedoAt_0(_S77, kernelContext_20);

#line 426
        float _S79 = albedoAt_0(_S77 + 1U, kernelContext_20);

#line 426
        float a_2 = mix(_S78, _S79, _S74);
        uint _S80 = _S77 + 16U;

#line 427
        float _S81 = albedoAt_0(_S80, kernelContext_20);

#line 427
        float _S82 = albedoAt_0(_S80 + 1U, kernelContext_20);
        c_3[k_1] = mix(a_2, mix(_S81, _S82, _S74), _S75);

#line 423
        k_1 = k_1 + 1U;

#line 423
    }

#line 430
    return mix(c_3[int(0)], c_3[int(1)], fz_0);
}


float sheenAlbedo_0(float cosO_1, float r_2, KernelContext_0 thread* kernelContext_21)
{
    float x_3 = saturate(cosO_1) * 15.0f;
    float y_2 = saturate(r_2) * 15.0f;
    uint _S83 = min(uint(x_3), 14U);
    uint _S84 = min(uint(y_2), 14U);
    float fx_1 = x_3 - float(_S83);
    float fy_1 = y_2 - float(_S84);
    uint _S85 = 1024U + _S84 * 16U + _S83;

#line 442
    float _S86 = albedoAt_0(_S85, kernelContext_21);

#line 442
    float _S87 = albedoAt_0(_S85 + 1U, kernelContext_21);

#line 442
    float a_3 = mix(_S86, _S87, fx_1);
    uint _S88 = 1024U + (_S84 + 1U) * 16U + _S83;

#line 443
    float _S89 = albedoAt_0(_S88, kernelContext_21);

#line 443
    float _S90 = albedoAt_0(_S88 + 1U, kernelContext_21);
    return mix(a_3, mix(_S89, _S90, fx_1), fy_1);
}


#line 199
float iesFactor_0(uint po_0, float3 d_3, KernelContext_0 thread* kernelContext_22)
{



    float th_0 = degrees_0(acos(clamp(- dot(d_3, float3((as_type<float>((kernelContext_22->lights_0[po_0 + 6U]))), (as_type<float>((kernelContext_22->lights_0[po_0 + 7U]))), (as_type<float>((kernelContext_22->lights_0[po_0 + 8U]))))), -1.0f, 1.0f)));
    float ph_0 = degrees_0(atan2(dot(d_3, float3((as_type<float>((kernelContext_22->lights_0[po_0 + 3U]))), (as_type<float>((kernelContext_22->lights_0[po_0 + 4U]))), (as_type<float>((kernelContext_22->lights_0[po_0 + 5U]))))), dot(d_3, float3((as_type<float>((kernelContext_22->lights_0[po_0]))), (as_type<float>((kernelContext_22->lights_0[po_0 + 1U]))), (as_type<float>((kernelContext_22->lights_0[po_0 + 2U])))))));

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

    uint _S91 = min(uint(th_0), 179U);
    uint _S92 = min(uint(ph_1), 359U);
    float ft_0 = th_0 - float(_S91);

    uint t_3 = po_0 + 9U;
    uint _S93 = t_3 + _S92 * 181U + _S91;
    uint _S94 = t_3 + (_S92 + 1U) * 181U + _S91;
    return mix(mix((as_type<float>((kernelContext_22->lights_0[_S93]))), (as_type<float>((kernelContext_22->lights_0[_S93 + 1U]))), ft_0), mix((as_type<float>((kernelContext_22->lights_0[_S94]))), (as_type<float>((kernelContext_22->lights_0[_S94 + 1U]))), ft_0), ph_1 - float(_S92));
}


#line 580
bool occluded_0(float3 o_3, float3 d_4, float tmax_0, KernelContext_0 thread* kernelContext_23)
{

#line 580
    uint layer_0 = 0U;

#line 580
    float3 _S95 = o_3;

#line 580
    float _S96 = tmax_0;

    for(;;)
    {

#line 582
        if(layer_0 < 8U)
        {
        }
        else
        {

#line 582
            break;
        }
        thread RayDesc_0 ray_1;
        (&ray_1)->Origin_0 = _S95;
        (&ray_1)->Direction_0 = d_4;
        (&ray_1)->TMin_0 = 0.0f;
        (&ray_1)->TMax_0 = _S96;
        thread raytracing::intersection_query<raytracing::triangle_data, raytracing::instancing> q_1;
        (&q_1)->reset({ (ray_1.Origin_0), (ray_1.Direction_0), (ray_1.TMin_0), (ray_1.TMax_0) }, (kernelContext_23->scene_0), (255U), _slang_ray_flags_to_intersection_params((5U)));
        for(;;)
        {

#line 591
            bool _S97 = ((&q_1)->next());

#line 591
            if(_S97)
            {
            }
            else
            {

#line 591
                break;
            }

#line 591
        }
        uint _S98 = (_slang_committed_intersection_type_to_uint((&q_1)->get_committed_intersection_type()));

#line 592
        if(_S98 != 1U)
        {

#line 593
            return false;
        }

#line 594
        uint _S99 = ((&q_1)->get_committed_instance_id());

#line 594
        uint _S100 = ((&q_1)->get_committed_primitive_id());

#line 594
        float2 _S101 = ((&q_1)->get_committed_triangle_barycentric_coord());

#line 594
        float _S102 = opacityAt_0(_S99, _S100, _S101, kernelContext_23);
        if(_S102 >= 1.0f)
        {

#line 596
            return true;
        }
        uint h_6 = (((((((as_type<uint>((_S95.x))) * 73856093U) ^ ((as_type<uint>((_S95.y))) * 19349663U)) ^ ((as_type<uint>((_S95.z))) * 83492791U)) ^ ((as_type<uint>((d_4.x))) * 2654435761U)) ^ ((as_type<uint>((d_4.y))) * 40503U)) ^ ((as_type<uint>((d_4.z))) * 2246822519U)) ^ (layer_0 * 3266489917U);

        uint h_7 = (h_6 ^ (h_6 >> 16U)) * 2146121005U;

        uint h_8 = (h_7 ^ (h_7 >> 15U)) * 2221713035U;

        if((float((h_8 ^ (h_8 >> 16U)) >> 8U) * 5.9604644775390625e-08f) < _S102)
        {

#line 605
            return true;
        }

#line 606
        float _S103 = ((&q_1)->get_committed_distance());

#line 606
        float adv_0 = _S103 + 9.9999997473787516e-05f;
        float3 _S104 = _S95 + d_4 * float3(adv_0) ;
        float _S105 = _S96 - adv_0;
        if(_S105 <= 0.0f)
        {

#line 610
            return false;
        }

#line 582
        layer_0 = layer_0 + 1U;

#line 582
        _S95 = _S104;

#line 582
        _S96 = _S105;

#line 582
    }

#line 612
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
float ggxAlbedo_0(float cosO_2, float alpha_2, KernelContext_0 thread* kernelContext_24)
{
    float x_4 = saturate(cosO_2) * 31.0f;
    float y_3 = saturate(sqrt(alpha_2)) * 31.0f;
    uint _S106 = min(uint(x_4), 30U);
    uint _S107 = min(uint(y_3), 30U);
    float fx_2 = x_4 - float(_S106);
    float fy_2 = y_3 - float(_S107);
    uint _S108 = _S107 * 32U + _S106;

#line 392
    float _S109 = albedoAt_0(_S108, kernelContext_24);

#line 392
    float _S110 = albedoAt_0(_S108 + 1U, kernelContext_24);

#line 392
    float a_4 = mix(_S109, _S110, fx_2);
    uint _S111 = (_S107 + 1U) * 32U + _S106;

#line 393
    float _S112 = albedoAt_0(_S111, kernelContext_24);

#line 393
    float _S113 = albedoAt_0(_S111 + 1U, kernelContext_24);
    return mix(a_4, mix(_S112, _S113, fx_2), fy_2);
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
float3 multiscatterFactor_0(const Surface_0 thread* s_3, float cosO_3, KernelContext_0 thread* kernelContext_25)
{
    if(kernelContext_25->params_0[int(29)] == 0U)
    {

#line 404
        return float3(1.0f) ;
    }

#line 404
    float3 _S114 = s_3->albedo_0;

#line 404
    float _S115 = ggxAlbedo_0(cosO_3, s_3->alpha_3, kernelContext_25);
    return float3(1.0f)  + _S114 * float3((1.0f / max(_S115, 0.05000000074505806f) - 1.0f)) ;
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
Lobes_0 evalLobes_0(const Surface_0 thread* s_4, float3 woL_0, float3 wiL_0, KernelContext_0 thread* kernelContext_26)
{
    float3 hh_0 = normalize(woL_0 + wiL_0);
    float _S116 = max(dot(woL_0, hh_0), 0.0f);

    float _S117 = hh_0.z;

#line 464
    float _S118 = woL_0.z;

#line 464
    float _S119 = wiL_0.z;

#line 464
    float _S120 = 4.0f * _S118;

#line 464
    float core_0 = D_0(_S117, s_4->alpha_3) * G1_0(_S118, s_4->alpha_3) * G1_0(_S119, s_4->alpha_3) / _S120;

#line 464
    float _S121 = s_4->transmission_1;

    thread Lobes_0 l_0;

#line 466
    float _S122 = s_4->metallic_0;

#line 466
    float3 _S123 = s_4->albedo_0;
    float3 _S124 = float3(s_4->metallic_0)  * schlick_0(s_4->albedo_0, _S116);

#line 467
    float3 _S125 = multiscatterFactor_0(s_4, _S118, kernelContext_26);
    float _S126 = 1.0f - _S122;

#line 468
    float _S127 = 1.0f - _S121;

#line 467
    (&l_0)->specular_1 = _S124 * _S125 * float3(core_0)  + float3((_S126 * (_S121 * fresnelDielectric_0(_S116, s_4->eta_1) * s_4->tComp_0 + _S127 * fresnelDielectric_0(_S116, s_4->ior_1)) * core_0)) ;

    (&l_0)->diffuse_0 = float3((_S126 * _S127 * (1.0f - s_4->fSel_0)))  * _S123 * float3((_S119 / 3.1415927410125732f)) ;

#line 469
    float _S128 = s_4->sheenP_0;

    if((s_4->sheenP_0) > 0.0f)
    {

#line 471
        float3 _S129 = float3((1.0f - _S128)) ;

        (&l_0)->specular_1 = _S129 * (&l_0)->specular_1 + s_4->sheenColor_0 * float3(sheenCore_0(_S118, _S119, _S117, s_4->sheenAlpha_0)) ;
        (&l_0)->diffuse_0 = (&l_0)->diffuse_0 * _S129;

#line 471
    }

#line 471
    float _S130 = s_4->coat_0;

#line 476
    if((s_4->coat_0) > 0.0f)
    {

#line 476
        float3 _S131 = float3((1.0f - s_4->coatP_0)) ;

#line 482
        (&l_0)->specular_1 = _S131 * (&l_0)->specular_1 + float3((_S130 * fresnelDielectric_0(_S116, 1.5f) * (D_0(_S117, s_4->coatAlpha_0) * G1_0(_S118, s_4->coatAlpha_0) * G1_0(_S119, s_4->coatAlpha_0) / _S120))) ;
        (&l_0)->diffuse_0 = (&l_0)->diffuse_0 * _S131;

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
void addSlot_0(uint pixel_3, uint slot_0, float3 u_1, float3 s_5, float3 wi_0, float lit_0, float r_3, KernelContext_0 thread* kernelContext_27)
{

#line 220
    bool _S132;

    if(any(isnan(u_1)))
    {

#line 222
        _S132 = true;

#line 222
    }
    else
    {

#line 222
        _S132 = any(isinf(u_1));

#line 222
    }

#line 222
    if(_S132)
    {

#line 222
        _S132 = true;

#line 222
    }
    else
    {

#line 222
        _S132 = any(isnan(s_5));

#line 222
    }

#line 222
    if(_S132)
    {

#line 222
        _S132 = true;

#line 222
    }
    else
    {

#line 222
        _S132 = any(isinf(s_5));

#line 222
    }

#line 222
    if(_S132)
    {

#line 223
        return;
    }

#line 224
    uint o_4 = 65U * pixel_3 + 17U + 12U * slot_0;
    float w_6 = lum_0(u_1);
    float wd_0 = w_6 + lum_0(s_5);
    float device* _S133 = kernelContext_27->lighting_0+o_4;

#line 227
    *_S133 = *_S133 + u_1.x;
    float device* _S134 = kernelContext_27->lighting_0+(o_4 + 1U);

#line 228
    *_S134 = *_S134 + u_1.y;
    float device* _S135 = kernelContext_27->lighting_0+(o_4 + 2U);

#line 229
    *_S135 = *_S135 + u_1.z;
    float device* _S136 = kernelContext_27->lighting_0+(o_4 + 3U);

#line 230
    *_S136 = *_S136 + w_6;
    float device* _S137 = kernelContext_27->lighting_0+(o_4 + 4U);

#line 231
    *_S137 = *_S137 + w_6 * r_3;
    float device* _S138 = kernelContext_27->lighting_0+(o_4 + 5U);

#line 232
    *_S138 = *_S138 + s_5.x;
    float device* _S139 = kernelContext_27->lighting_0+(o_4 + 6U);

#line 233
    *_S139 = *_S139 + s_5.y;
    float device* _S140 = kernelContext_27->lighting_0+(o_4 + 7U);

#line 234
    *_S140 = *_S140 + s_5.z;
    float device* _S141 = kernelContext_27->lighting_0+(o_4 + 8U);

#line 235
    *_S141 = *_S141 + wd_0 * wi_0.x;
    float device* _S142 = kernelContext_27->lighting_0+(o_4 + 9U);

#line 236
    *_S142 = *_S142 + wd_0 * wi_0.y;
    float device* _S143 = kernelContext_27->lighting_0+(o_4 + 10U);

#line 237
    *_S143 = *_S143 + wd_0 * wi_0.z;
    float device* _S144 = kernelContext_27->lighting_0+(o_4 + 11U);

#line 238
    *_S144 = *_S144 + wd_0 * lit_0;
    return;
}


#line 885
void restirGbuffer_0(uint pixel_4, float3 p_2, float3 n_3, KernelContext_0 thread* kernelContext_28)
{
    uint co_1 = restirBase_0(pixel_4, kernelContext_28->params_0[int(6)] & 1U);
    *(kernelContext_28->restir_0+(co_1 + 8U)) = p_2.x;
    *(kernelContext_28->restir_0+(co_1 + 9U)) = p_2.y;
    *(kernelContext_28->restir_0+(co_1 + 10U)) = p_2.z;
    *(kernelContext_28->restir_0+(co_1 + 11U)) = n_3.x;
    *(kernelContext_28->restir_0+(co_1 + 12U)) = n_3.y;
    *(kernelContext_28->restir_0+(co_1 + 13U)) = n_3.z;
    *(kernelContext_28->restir_0+(co_1 + 14U)) = (as_type<float>((1U)));
    return;
}


#line 488
float3 evalReflective_0(const Surface_0 thread* s_6, float3 woL_1, float3 wiL_1, KernelContext_0 thread* kernelContext_29)
{

#line 488
    Lobes_0 _S145 = evalLobes_0(s_6, woL_1, wiL_1, kernelContext_29);


    return _S145.specular_1 + _S145.diffuse_0;
}


#line 901
void restirGIPrepare_0(uint pixel_5, float3 p_3, float3 n_4, float pHitT_0, const Surface_0 thread* surf_0, float3 T_0, float3 B_0, float3 woL_2, Rng_0 thread* rng_2, KernelContext_0 thread* kernelContext_30)
{
    uint w_7 = kernelContext_30->params_0[int(0)];
    uint _S146 = kernelContext_30->params_0[int(6)] & 1U;
    float _S147 = float(max(kernelContext_30->params_0[int(38)], 1U));



    float3 _S148 = float3(0.0f) ;

#line 909
    float pSel_0;

#line 909
    float mTotal_0;

#line 909
    float wsum_0;

#line 909
    float3 cSel_0;

#line 909
    float3 xSel_0;

#line 909
    float3 nSel_0;

#line 909
    float3 lSel_0;

#line 909
    uint k_2;



    if(kernelContext_30->params_0[int(6)] > 0U)
    {
        uint _S149 = pixel_5 % w_7;

#line 915
        int nx_0 = int(_S149);
        uint _S150 = pixel_5 / w_7;

#line 916
        int ny_0 = int(_S150);

#line 916
        pSel_0 = 0.0f;

#line 916
        cSel_0 = _S148;

#line 916
        xSel_0 = _S148;

#line 916
        nSel_0 = _S148;

#line 916
        lSel_0 = _S148;

#line 916
        k_2 = 0U;

#line 916
        mTotal_0 = 0.0f;

#line 916
        wsum_0 = 0.0f;
        for(;;)
        {

#line 917
            if(k_2 < 3U)
            {
            }
            else
            {

#line 917
                break;
            }

#line 917
            bool _S151;

#line 917
            bool _S152;

#line 917
            bool _S153;

#line 917
            int ny_1;

#line 917
            int nx_1;



            if(k_2 > 0U)
            {
                float _S154 = Rng_next_0(rng_2);

#line 923
                int nx_2 = nx_0 + (int(_S154 * 13.0f) - int(6));
                float _S155 = Rng_next_0(rng_2);

#line 924
                int ny_2 = ny_0 + (int(_S155 * 13.0f) - int(6));
                if(nx_2 < int(0))
                {

#line 925
                    _S151 = true;

#line 925
                }
                else
                {

#line 925
                    _S151 = ny_2 < int(0);

#line 925
                }

#line 925
                if(_S151)
                {

#line 925
                    _S152 = true;

#line 925
                }
                else
                {

#line 925
                    _S152 = nx_2 >= int(w_7);

#line 925
                }

#line 925
                if(_S152)
                {

#line 925
                    _S153 = true;

#line 925
                }
                else
                {

#line 925
                    _S153 = ny_2 >= int(kernelContext_30->params_0[int(1)]);

#line 925
                }

#line 925
                if(_S153)
                {

#line 926
                    k_2 = k_2 + 1U;

#line 917
                    continue;
                }

#line 917
                ny_1 = ny_2;

#line 917
                nx_1 = nx_2;



            }
            else
            {

#line 921
                ny_1 = ny_0;

#line 921
                nx_1 = nx_0;

#line 921
            }

#line 928
            uint ro_0 = restirBase_0(uint(ny_1) * w_7 + uint(nx_1), _S146 ^ 1U);
            if((as_type<uint>((*(kernelContext_30->restir_0+(ro_0 + 14U))))) == 0U)
            {

#line 929
                _S151 = true;

#line 929
            }
            else
            {

#line 929
                _S151 = (as_type<uint>((*(kernelContext_30->restir_0+(ro_0 + 27U))))) == 0U;

#line 929
            }

#line 929
            if(_S151)
            {

#line 930
                k_2 = k_2 + 1U;

#line 917
                continue;
            }

#line 931
            float3 pq_0 = float3(*(kernelContext_30->restir_0+(ro_0 + 8U)), *(kernelContext_30->restir_0+(ro_0 + 9U)), *(kernelContext_30->restir_0+(ro_0 + 10U)));

            if((dot(float3(*(kernelContext_30->restir_0+(ro_0 + 11U)), *(kernelContext_30->restir_0+(ro_0 + 12U)), *(kernelContext_30->restir_0+(ro_0 + 13U))), n_4)) < 0.89999997615814209f)
            {

#line 933
                _S152 = true;

#line 933
            }
            else
            {

#line 933
                _S152 = (length(pq_0 - p_3)) > (0.05000000074505806f * max(pHitT_0, 0.0099999997764825821f));

#line 933
            }

#line 933
            if(_S152)
            {

#line 934
                k_2 = k_2 + 1U;

#line 917
                continue;
            }

#line 935
            float3 x2_0 = float3(*(kernelContext_30->restir_0+(ro_0 + 16U)), *(kernelContext_30->restir_0+(ro_0 + 17U)), *(kernelContext_30->restir_0+(ro_0 + 18U)));
            float3 n2_0 = float3(*(kernelContext_30->restir_0+(ro_0 + 19U)), *(kernelContext_30->restir_0+(ro_0 + 20U)), *(kernelContext_30->restir_0+(ro_0 + 21U)));
            float3 l2_0 = float3(*(kernelContext_30->restir_0+(ro_0 + 22U)), *(kernelContext_30->restir_0+(ro_0 + 23U)), *(kernelContext_30->restir_0+(ro_0 + 24U)));
            float _S156 = min(*(kernelContext_30->restir_0+(ro_0 + 26U)), _S147);
            float mTotal_1 = mTotal_0 + _S156;
            float3 toX_0 = x2_0 - p_3;
            float dR_0 = length(toX_0);
            float3 wi_1 = toX_0 / float3(max(dR_0, 9.99999997475242708e-07f)) ;
            float dQ_0 = length(x2_0 - pq_0);
            float cosT_1 = dot(n_4, wi_1);
            float cosR_0 = abs(dot(n2_0, wi_1));
            float cosQ_0 = abs(dot(n2_0, normalize(pq_0 - x2_0)));
            if(cosT_1 <= 0.0f)
            {

#line 947
                _S153 = true;

#line 947
            }
            else
            {

#line 947
                _S153 = dR_0 < 0.0010000000474974513f;

#line 947
            }

#line 947
            bool _S157;

#line 947
            if(_S153)
            {

#line 947
                _S157 = true;

#line 947
            }
            else
            {

#line 947
                _S157 = cosR_0 < 0.0010000000474974513f;

#line 947
            }

#line 947
            bool _S158;

#line 947
            if(_S157)
            {

#line 947
                _S158 = true;

#line 947
            }
            else
            {

#line 947
                _S158 = cosQ_0 < 0.0010000000474974513f;

#line 947
            }

#line 947
            if(_S158)
            {

#line 947
                mTotal_0 = mTotal_1;
                k_2 = k_2 + 1U;

#line 917
                continue;
            }

#line 949
            float jac_0 = cosR_0 / cosQ_0 * (dQ_0 * dQ_0) / (dR_0 * dR_0);

#line 949
            bool _S159;
            if(jac_0 > 10.0f)
            {

#line 950
                _S159 = true;

#line 950
            }
            else
            {

#line 950
                _S159 = jac_0 < 0.10000000149011612f;

#line 950
            }

#line 950
            if(_S159)
            {

#line 950
                mTotal_0 = mTotal_1;
                k_2 = k_2 + 1U;

#line 917
                continue;
            }

#line 917
            float3 _S160 = evalReflective_0(surf_0, woL_2, float3(dot(wi_1, T_0), dot(wi_1, B_0), cosT_1), kernelContext_30);

#line 952
            float3 c_6 = _S160 * l2_0;
            float phat_0 = lum_0(c_6);

#line 953
            bool _S161;
            if(phat_0 <= 0.0f)
            {

#line 954
                _S161 = true;

#line 954
            }
            else
            {

#line 954
                bool _S162 = occluded_0(p_3, wi_1, dR_0 * 0.99900001287460327f, kernelContext_30);

#line 954
                _S161 = _S162;

#line 954
            }

#line 954
            if(_S161)
            {

#line 954
                mTotal_0 = mTotal_1;
                k_2 = k_2 + 1U;

#line 917
                continue;
            }

#line 956
            float wgt_0 = phat_0 * *(kernelContext_30->restir_0+(ro_0 + 25U)) * _S156 * jac_0;
            float wsum_1 = wsum_0 + wgt_0;
            float _S163 = Rng_next_0(rng_2);

#line 958
            float pSel_1;

#line 958
            float3 cSel_1;

#line 958
            float3 xSel_1;

#line 958
            float3 nSel_1;

#line 958
            float3 lSel_1;

#line 958
            if((_S163 * wsum_1) < wgt_0)
            {

#line 958
                pSel_1 = phat_0;

#line 958
                cSel_1 = c_6;

#line 958
                xSel_1 = x2_0;

#line 958
                nSel_1 = n2_0;

#line 958
                lSel_1 = l2_0;

#line 958
            }
            else
            {

#line 958
                pSel_1 = pSel_0;

#line 958
                cSel_1 = cSel_0;

#line 958
                xSel_1 = xSel_0;

#line 958
                nSel_1 = nSel_0;

#line 958
                lSel_1 = lSel_0;

#line 958
            }

#line 958
            pSel_0 = pSel_1;

#line 958
            cSel_0 = cSel_1;

#line 958
            xSel_0 = xSel_1;

#line 958
            nSel_0 = nSel_1;

#line 958
            lSel_0 = lSel_1;

#line 958
            mTotal_0 = mTotal_1;

#line 958
            wsum_0 = wsum_1;

#line 917
            k_2 = k_2 + 1U;

#line 917
        }

#line 913
    }
    else
    {

#line 913
        pSel_0 = 0.0f;

#line 913
        cSel_0 = _S148;

#line 913
        xSel_0 = _S148;

#line 913
        nSel_0 = _S148;

#line 913
        lSel_0 = _S148;

#line 913
        wsum_0 = 0.0f;

#line 913
        mTotal_0 = 0.0f;

#line 913
    }

#line 968
    uint so_0 = restirScratch_0(pixel_5);
    *(kernelContext_30->restir_0+so_0) = wsum_0;
    *(kernelContext_30->restir_0+(so_0 + 1U)) = mTotal_0;
    *(kernelContext_30->restir_0+(so_0 + 2U)) = pSel_0;

#line 971
    k_2 = 0U;
    for(;;)
    {

#line 972
        if(k_2 < 3U)
        {
        }
        else
        {

#line 972
            break;
        }
        *(kernelContext_30->restir_0+(so_0 + 3U + k_2)) = cSel_0[k_2];
        *(kernelContext_30->restir_0+(so_0 + 6U + k_2)) = xSel_0[k_2];
        *(kernelContext_30->restir_0+(so_0 + 9U + k_2)) = nSel_0[k_2];
        *(kernelContext_30->restir_0+(so_0 + 12U + k_2)) = lSel_0[k_2];

#line 972
        k_2 = k_2 + 1U;

#line 972
    }

#line 979
    *(kernelContext_30->restir_0+(so_0 + 22U)) = (as_type<float>((0U)));
    return;
}


#line 718
bool restirLight_0(uint e_0, uint recv_0, float3 x_5, float3 p_4, float3 n_5, float3 thread* wi_2, float thread* dist_0, float thread* cosi_1, float3 thread* g_0, float thread* plsa_0, KernelContext_0 thread* kernelContext_31)
{
    uint o_5 = e_0 * 16U;
    float3 a_5 = float3(kernelContext_31->emitters_0[o_5], kernelContext_31->emitters_0[o_5 + 1U], kernelContext_31->emitters_0[o_5 + 2U]);
    float3 b_1 = float3(kernelContext_31->emitters_0[o_5 + 3U], kernelContext_31->emitters_0[o_5 + 4U], kernelContext_31->emitters_0[o_5 + 5U]);
    float3 c_7 = float3(kernelContext_31->emitters_0[o_5 + 6U], kernelContext_31->emitters_0[o_5 + 7U], kernelContext_31->emitters_0[o_5 + 8U]);
    float3 toL_0 = x_5 - p_4;
    float d2_0 = dot(toL_0, toL_0);
    float _S164 = sqrt(d2_0);

#line 726
    *dist_0 = _S164;
    float3 _S165 = toL_0 / float3(max(_S164, 9.99999997475242708e-07f)) ;

#line 727
    *wi_2 = _S165;
    float cosl_0 = abs(dot(normalize(cross(b_1 - a_5, c_7 - a_5)), _S165));
    *cosi_1 = dot(n_5, _S165);
    *g_0 = float3(kernelContext_31->emitters_0[o_5 + 9U], kernelContext_31->emitters_0[o_5 + 10U], kernelContext_31->emitters_0[o_5 + 11U]) * float3((cosl_0 / max(d2_0, 9.999999960041972e-13f))) ;


    *plsa_0 = kernelContext_31->emitters_0[o_5 + 13U] * d2_0 / (max(kernelContext_31->emitters_0[o_5 + 12U], 1.00000000317107685e-30f) * max(cosl_0, 9.9999997473787516e-06f));

#line 733
    bool _S166;

    if((*cosi_1) > 0.0f)
    {

#line 735
        _S166 = cosl_0 > 9.9999997473787516e-06f;

#line 735
    }
    else
    {

#line 735
        _S166 = false;

#line 735
    }

#line 735
    if(_S166)
    {

#line 735
        _S166 = d2_0 > 9.999999960041972e-13f;

#line 735
    }
    else
    {

#line 735
        _S166 = false;

#line 735
    }

#line 735
    if(_S166)
    {

#line 735
        _S166 = ((as_type<uint>((kernelContext_31->emitters_0[o_5 + 14U]))) & recv_0) != 0U;

#line 735
    }
    else
    {

#line 735
        _S166 = false;

#line 735
    }

#line 735
    return _S166;
}


#line 540
float reflectivePdf_0(const Surface_0 thread* s_7, float3 woL_3, float3 wiL_2)
{
    float3 hh_1 = normalize(woL_3 + wiL_2);

    float _S167 = woL_3.z;

#line 544
    float _S168 = hh_1.z;

#line 544
    float _S169 = 4.0f * _S167;

    float _S170 = 1.0f - s_7->metallic_0;

#line 546
    float _S171 = 1.0f - s_7->transmission_1;
    float _S172 = wiL_2.z;
    float q_2 = (s_7->metallic_0 + _S170 * (s_7->transmission_1 * fresnelDielectric_0(max(dot(woL_3, hh_1), 0.0f), s_7->eta_1) + _S171 * s_7->fSel_0)) * (G1_0(_S167, s_7->alpha_3) * D_0(_S168, s_7->alpha_3) / _S169) + _S170 * _S171 * (1.0f - s_7->fSel_0) * _S172 / 3.1415927410125732f;

#line 548
    float _S173 = s_7->sheenP_0;

#line 548
    float q_3;
    if((s_7->sheenP_0) > 0.0f)
    {

#line 549
        q_3 = (1.0f - _S173) * q_2 + _S173 * _S172 / 3.1415927410125732f;

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
        q_3 = (1.0f - s_7->coatP_0) * q_3 + s_7->coatP_0 * (G1_0(_S167, s_7->coatAlpha_0) * D_0(_S168, s_7->coatAlpha_0) / _S169);

#line 551
    }

#line 556
    return q_3;
}


#line 739
float restirMis_0(const Surface_0 thread* surf_1, float3 woL_4, float3 wiL_3, float plsa_1)
{

#line 739
    float _S174 = reflectivePdf_0(surf_1, woL_4, wiL_3);


    float _S175 = plsa_1 * plsa_1;

#line 742
    return _S175 / max(_S175 + _S174 * _S174, 1.00000000317107685e-30f);
}

struct RestirPick_0
{
    bool valid_0;
    uint e_1;
    float3 x_6;
    float W_0;
    bool occ_0;
};


#line 759
RestirPick_0 restirDI_0(uint pixel_6, uint recv_1, float3 p_5, float3 n_6, float pHitT_1, const Surface_0 thread* surf_2, float3 T_1, float3 B_1, float3 woL_5, Rng_0 thread* rng_3, KernelContext_0 thread* kernelContext_32)
{

#line 759
    uint lo_0;

#line 759
    float q_4;

#line 759
    float phat_1;

#line 759
    float selPhat_0;

#line 759
    float3 selX_0;

#line 759
    bool _S176;

    uint w_8 = kernelContext_32->params_0[int(0)];
    uint cur_0 = kernelContext_32->params_0[int(6)] & 1U;
    uint _S177 = kernelContext_32->params_0[int(23)];
    float _S178 = float(max(kernelContext_32->params_0[int(38)], 1U));



    float3 _S179 = float3(0.0f) ;

#line 768
    uint selE_0 = 0U;

#line 768
    float selPhat_1 = 0.0f;

#line 768
    float3 selX_1 = _S179;

#line 768
    uint k_3 = 0U;

#line 768
    float mTotal_2 = 0.0f;

#line 768
    float wsum_2 = 0.0f;

    for(;;)
    {

#line 770
        if(k_3 < (max(kernelContext_32->params_0[int(37)], 1U)))
        {
        }
        else
        {

#line 770
            break;
        }
        float _S180 = Rng_next_0(rng_3);
        float ua_0 = Rng_next_0(rng_3);
        float ub_0 = Rng_next_0(rng_3);

        uint _S181 = _S177 - 1U;

#line 776
        lo_0 = 0U;

#line 776
        uint hi_0 = _S181;
        for(;;)
        {

#line 777
            if(lo_0 < hi_0)
            {
            }
            else
            {

#line 777
                break;
            }
            uint mid_0 = (lo_0 + hi_0) / 2U;
            if(kernelContext_32->emitCdf_0[mid_0] >= _S180)
            {

#line 780
                hi_0 = mid_0;

#line 780
            }
            else
            {

#line 780
                lo_0 = mid_0 + 1U;

#line 780
            }

#line 777
        }

#line 785
        uint o_6 = lo_0 * 16U;



        float su_0 = sqrt(ua_0);
        float3 x_7 = float3(kernelContext_32->emitters_0[o_6], kernelContext_32->emitters_0[o_6 + 1U], kernelContext_32->emitters_0[o_6 + 2U]) * float3((1.0f - su_0))  + float3(kernelContext_32->emitters_0[o_6 + 3U], kernelContext_32->emitters_0[o_6 + 4U], kernelContext_32->emitters_0[o_6 + 5U]) * float3((su_0 * (1.0f - ub_0)))  + float3(kernelContext_32->emitters_0[o_6 + 6U], kernelContext_32->emitters_0[o_6 + 7U], kernelContext_32->emitters_0[o_6 + 8U]) * float3((su_0 * ub_0)) ;
        float area_0 = kernelContext_32->emitters_0[o_6 + 12U];
        if(area_0 > 0.0f)
        {

#line 792
            q_4 = kernelContext_32->emitters_0[o_6 + 13U] / area_0;

#line 792
        }
        else
        {

#line 792
            q_4 = 0.0f;

#line 792
        }
        thread float3 wi_3;

#line 793
        thread float3 g_1;
        thread float dist_1;

#line 794
        thread float cosi_2;

#line 794
        thread float plsa_2;

        if(q_4 > 0.0f)
        {

#line 796
            bool _S182 = restirLight_0(lo_0, recv_1, x_7, p_5, n_6, &wi_3, &dist_1, &cosi_2, &g_1, &plsa_2, kernelContext_32);

#line 796
            _S176 = _S182;

#line 796
        }
        else
        {

#line 796
            _S176 = false;

#line 796
        }

#line 796
        if(_S176)
        {
            float3 wiL_4 = float3(dot(wi_3, T_1), dot(wi_3, B_1), cosi_2);

#line 798
            float3 _S183 = evalReflective_0(surf_2, woL_5, wiL_4, kernelContext_32);
            float _S184 = lum_0(_S183 * g_1);

#line 799
            float _S185 = restirMis_0(surf_2, woL_5, wiL_4, plsa_2);

#line 799
            phat_1 = _S184 * _S185;

#line 796
        }
        else
        {

#line 796
            phat_1 = 0.0f;

#line 796
        }

#line 801
        float wgt_1 = phat_1 / max(q_4, 1.00000000317107685e-30f);
        float mTotal_3 = mTotal_2 + 1.0f;
        if(phat_1 > 0.0f)
        {
            float wsum_3 = wsum_2 + wgt_1;
            float _S186 = Rng_next_0(rng_3);

#line 806
            uint selE_1;

#line 806
            if((_S186 * wsum_3) < wgt_1)
            {

#line 806
                selE_1 = lo_0 + 1U;

#line 806
                selPhat_0 = phat_1;

#line 806
                selX_0 = x_7;

#line 806
            }
            else
            {

#line 806
                selE_1 = selE_0;

#line 806
                selPhat_0 = selPhat_1;

#line 806
                selX_0 = selX_1;

#line 806
            }

#line 806
            selE_0 = selE_1;

#line 806
            selPhat_1 = selPhat_0;

#line 806
            selX_1 = selX_0;

#line 806
            wsum_2 = wsum_3;

#line 803
        }

#line 770
        k_3 = k_3 + 1U;

#line 770
        mTotal_2 = mTotal_3;

#line 770
    }

#line 814
    if(kernelContext_32->params_0[int(6)] > 0U)
    {
        uint _S187 = pixel_6 % w_8;

#line 816
        int nx_3 = int(_S187);
        uint _S188 = pixel_6 / w_8;

#line 817
        int ny_3 = int(_S188);

#line 817
        k_3 = 0U;
        for(;;)
        {

#line 818
            if(k_3 < 3U)
            {
            }
            else
            {

#line 818
                break;
            }

#line 818
            bool _S189;

#line 818
            int ny_4;

#line 818
            int nx_4;



            if(k_3 > 0U)
            {
                float _S190 = Rng_next_0(rng_3);

#line 824
                int nx_5 = nx_3 + (int(_S190 * 13.0f) - int(6));
                float _S191 = Rng_next_0(rng_3);

#line 825
                int ny_5 = ny_3 + (int(_S191 * 13.0f) - int(6));
                if(nx_5 < int(0))
                {

#line 826
                    _S176 = true;

#line 826
                }
                else
                {

#line 826
                    _S176 = ny_5 < int(0);

#line 826
                }

#line 826
                if(_S176)
                {

#line 826
                    _S189 = true;

#line 826
                }
                else
                {

#line 826
                    _S189 = nx_5 >= int(w_8);

#line 826
                }

#line 826
                bool _S192;

#line 826
                if(_S189)
                {

#line 826
                    _S192 = true;

#line 826
                }
                else
                {

#line 826
                    _S192 = ny_5 >= int(kernelContext_32->params_0[int(1)]);

#line 826
                }

#line 826
                if(_S192)
                {

#line 827
                    k_3 = k_3 + 1U;

#line 818
                    continue;
                }

#line 818
                ny_4 = ny_5;

#line 818
                nx_4 = nx_5;



            }
            else
            {

#line 822
                ny_4 = ny_3;

#line 822
                nx_4 = nx_3;

#line 822
            }

#line 829
            uint ro_1 = restirBase_0(uint(ny_4) * w_8 + uint(nx_4), cur_0 ^ 1U);
            uint ei_0 = (as_type<uint>((*(kernelContext_32->restir_0+ro_1))));
            if((as_type<uint>((*(kernelContext_32->restir_0+(ro_1 + 14U))))) == 0U)
            {

#line 831
                _S176 = true;

#line 831
            }
            else
            {

#line 831
                _S176 = ei_0 == 0U;

#line 831
            }

#line 831
            if(_S176)
            {

#line 832
                k_3 = k_3 + 1U;

#line 818
                continue;
            }

#line 834
            float3 pp_0 = float3(*(kernelContext_32->restir_0+(ro_1 + 8U)), *(kernelContext_32->restir_0+(ro_1 + 9U)), *(kernelContext_32->restir_0+(ro_1 + 10U)));
            if((dot(float3(*(kernelContext_32->restir_0+(ro_1 + 11U)), *(kernelContext_32->restir_0+(ro_1 + 12U)), *(kernelContext_32->restir_0+(ro_1 + 13U))), n_6)) < 0.89999997615814209f)
            {

#line 835
                _S189 = true;

#line 835
            }
            else
            {

#line 835
                _S189 = (length(pp_0 - p_5)) > (0.05000000074505806f * max(pHitT_1, 0.0099999997764825821f));

#line 835
            }

#line 835
            if(_S189)
            {

#line 836
                k_3 = k_3 + 1U;

#line 818
                continue;
            }

#line 837
            float3 xc_0 = float3(*(kernelContext_32->restir_0+(ro_1 + 1U)), *(kernelContext_32->restir_0+(ro_1 + 2U)), *(kernelContext_32->restir_0+(ro_1 + 3U)));
            float _S193 = min(*(kernelContext_32->restir_0+(ro_1 + 5U)), _S178);
            thread float3 wi_4;

#line 839
            thread float3 g_2;
            thread float dist_2;

#line 840
            thread float cosi_3;

#line 840
            thread float plsa_3;

#line 840
            bool _S194 = restirLight_0(ei_0 - 1U, recv_1, xc_0, p_5, n_6, &wi_4, &dist_2, &cosi_3, &g_2, &plsa_3, kernelContext_32);

            if(_S194)
            {
                float3 wiL_5 = float3(dot(wi_4, T_1), dot(wi_4, B_1), cosi_3);

#line 844
                float3 _S195 = evalReflective_0(surf_2, woL_5, wiL_5, kernelContext_32);
                float _S196 = lum_0(_S195 * g_2);

#line 845
                float _S197 = restirMis_0(surf_2, woL_5, wiL_5, plsa_3);

#line 845
                q_4 = _S196 * _S197;

#line 842
            }
            else
            {

#line 842
                q_4 = 0.0f;

#line 842
            }

#line 847
            float wgt_2 = q_4 * *(kernelContext_32->restir_0+(ro_1 + 4U)) * _S193;
            float mTotal_4 = mTotal_2 + _S193;
            if(wgt_2 > 0.0f)
            {
                float wsum_4 = wsum_2 + wgt_2;
                float _S198 = Rng_next_0(rng_3);

#line 852
                if((_S198 * wsum_4) < wgt_2)
                {

#line 852
                    lo_0 = ei_0;

#line 852
                    phat_1 = q_4;

#line 852
                    selX_0 = xc_0;

#line 852
                }
                else
                {

#line 852
                    lo_0 = selE_0;

#line 852
                    phat_1 = selPhat_1;

#line 852
                    selX_0 = selX_1;

#line 852
                }

#line 852
                selPhat_0 = wsum_4;

#line 849
            }
            else
            {

#line 849
                lo_0 = selE_0;

#line 849
                phat_1 = selPhat_1;

#line 849
                selX_0 = selX_1;

#line 849
                selPhat_0 = wsum_2;

#line 849
            }

#line 849
            selE_0 = lo_0;

#line 849
            selPhat_1 = phat_1;

#line 849
            selX_1 = selX_0;

#line 849
            mTotal_2 = mTotal_4;

#line 849
            wsum_2 = selPhat_0;

#line 818
            k_3 = k_3 + 1U;

#line 818
        }

#line 814
    }

#line 861
    thread RestirPick_0 r_4;
    if(selE_0 != 0U)
    {

#line 862
        _S176 = selPhat_1 > 0.0f;

#line 862
    }
    else
    {

#line 862
        _S176 = false;

#line 862
    }

#line 862
    (&r_4)->valid_0 = _S176;
    (&r_4)->e_1 = selE_0;
    (&r_4)->x_6 = selX_1;
    if(_S176)
    {

#line 865
        selPhat_1 = wsum_2 / (mTotal_2 * selPhat_1);

#line 865
    }
    else
    {

#line 865
        selPhat_1 = 0.0f;

#line 865
    }

#line 865
    (&r_4)->W_0 = selPhat_1;
    (&r_4)->occ_0 = false;
    if((&r_4)->valid_0)
    {
        thread float3 wi_5;

#line 869
        thread float3 g_3;
        thread float dist_3;

#line 870
        thread float cosi_4;

#line 870
        thread float plsa_4;

#line 870
        bool _S199 = restirLight_0(selE_0 - 1U, recv_1, selX_1, p_5, n_6, &wi_5, &dist_3, &cosi_4, &g_3, &plsa_4, kernelContext_32);

#line 870
        bool _S200 = occluded_0(p_5, wi_5, dist_3 * 0.99900001287460327f, kernelContext_32);

        (&r_4)->occ_0 = _S200;

#line 867
    }

#line 874
    uint co_2 = restirBase_0(pixel_6, cur_0);
    *(kernelContext_32->restir_0+co_2) = (as_type<float>((selE_0)));
    *(kernelContext_32->restir_0+(co_2 + 1U)) = selX_1.x;
    *(kernelContext_32->restir_0+(co_2 + 2U)) = selX_1.y;
    *(kernelContext_32->restir_0+(co_2 + 3U)) = selX_1.z;
    float device* _S201 = kernelContext_32->restir_0+(co_2 + 4U);

#line 879
    if((&r_4)->occ_0)
    {

#line 879
        selPhat_1 = 0.0f;

#line 879
    }
    else
    {

#line 879
        selPhat_1 = (&r_4)->W_0;

#line 879
    }

#line 879
    *_S201 = selPhat_1;
    *(kernelContext_32->restir_0+(co_2 + 5U)) = mTotal_2;
    return r_4;
}


#line 274
float3 envSample_0(float u1_0, float u2_0, float u3_0, float u4_0, float thread* pdf_0, float3 thread* le_0, KernelContext_0 thread* kernelContext_33)
{

#line 274
    uint lo_1;

    uint w_9 = kernelContext_33->params_0[int(24)];
    uint h_9 = kernelContext_33->params_0[int(25)];

    uint _S202 = h_9 - 1U;

#line 279
    uint lo_2 = 0U;

#line 279
    uint hi_1 = _S202;
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
        if(kernelContext_33->envMarginal_0[mid_1] >= u1_0)
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
    uint _S203 = w_9 - 1U;

#line 290
    lo_1 = 0U;

#line 290
    hi_1 = _S203;
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
        if(kernelContext_33->envCond_0[lo_2 * w_9 + mid_2] >= u2_0)
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
    float3 _S204 = envTexel_0(lo_1, lo_2, kernelContext_33);
    *le_0 = _S204;
    float _S205 = lum_0(_S204);

#line 304
    float _S206 = pf_0(26U, kernelContext_33);

#line 304
    *pdf_0 = _S205 * _S206;
    return float3(st_0 * sin(phi_0), cos(theta_0), - st_0 * cos(phi_0));
}


#line 163
float3 sampleVndf_0(float3 wo_0, float alpha_5, float u1_1, float u2_1)
{
    float3 vh_0 = normalize(float3(alpha_5 * wo_0.x, alpha_5 * wo_0.y, wo_0.z));
    float _S207 = vh_0.x;

#line 166
    float _S208 = vh_0.y;

#line 166
    float lensq_0 = _S207 * _S207 + _S208 * _S208;

#line 166
    float3 t1_0;
    if(lensq_0 > 0.0f)
    {

#line 167
        t1_0 = float3(- _S208, _S207, 0.0f) * float3(rsqrt(lensq_0)) ;

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
    float _S209 = 1.0f - a_6 * a_6;

#line 174
    float b_2 = (1.0f - s_8) * sqrt(_S209) + s_8 * (r_5 * sin(phi_1));
    float3 nh_0 = float3(a_6)  * t1_0 + float3(b_2)  * cross(vh_0, t1_0) + float3(sqrt(max(0.0f, _S209 - b_2 * b_2)))  * vh_0;
    return normalize(float3(alpha_5 * nh_0.x, alpha_5 * nh_0.y, max(0.0f, nh_0.z)));
}


#line 115
float3 cosineLocal_0(float u1_2, float u2_2)
{
    float r_6 = sqrt(u1_2);
    float phi_2 = 6.2831854820251465f * u2_2;
    return float3(r_6 * cos(phi_2), r_6 * sin(phi_2), sqrt(max(0.0f, 1.0f - u1_2)));
}


#line 992
bool shadePath_0(PathState_0 thread* st_1, const Hit_0 thread* hq_0, uint depth_3, uint pixel_7, KernelContext_0 thread* kernelContext_34)
{

#line 992
    uint k_4;

#line 992
    int chan_1;

#line 992
    bool alive_0;

#line 992
    bool _S210;

#line 992
    float dist_4;

#line 992
    float vv_0;

#line 992
    float us_0;

#line 992
    float _S211;

#line 992
    float _S212;

#line 992
    float3 wi_6;

#line 992
    float3 li_0;

#line 992
    bool _S213;

#line 992
    bool _S214;

#line 992
    bool chooseEnv_0;

#line 992
    bool _S215;

#line 992
    bool track_0;

#line 992
    float _S216 = pf_0(20U, kernelContext_34);

#line 992
    float _S217 = pf_0(21U, kernelContext_34);

#line 992
    float _S218 = pf_0(22U, kernelContext_34);

    float3 _S219 = float3(_S216, _S217, _S218);
    bool _S220 = kernelContext_34->params_0[int(28)] != 0U;
    uint _S221 = kernelContext_34->params_0[int(5)];
    uint emitterCount_0 = kernelContext_34->params_0[int(23)];
    bool hasEnv_0 = kernelContext_34->params_0[int(24)] > 0U;

#line 998
    float _S222;

    if(hasEnv_0)
    {

#line 1000
        if(emitterCount_0 > 0U)
        {

#line 1000
            _S222 = 0.5f;

#line 1000
        }
        else
        {

#line 1000
            _S222 = 1.0f;

#line 1000
        }

#line 1000
    }
    else
    {

#line 1000
        _S222 = 0.0f;

#line 1000
    }
    thread Rng_0 rng_4;
    (&rng_4)->state_0 = st_1->rng_0;

#line 1002
    uint cls_4 = st_1->cls_0;

#line 1002
    float3 dir_2 = st_1->dir_0;

#line 1002
    float3 org_2 = st_1->org_0;

#line 1002
    int chan_2 = st_1->chan_0;

#line 1002
    uint once_0 = 0U;

#line 1002
    float3 thr_1 = st_1->thr_0;

#line 1009
    for(;;)
    {

#line 1009
        if(once_0 < 1U)
        {
        }
        else
        {

#line 1009
            chan_1 = chan_2;

#line 1009
            alive_0 = true;

#line 1009
            break;
        }

#line 1009
        float wB_0;

        if(!hq_0->hit_0)
        {
            if(restirCompiled_0)
            {

#line 1013
                alive_0 = depth_3 == 0U;

#line 1013
            }
            else
            {

#line 1013
                alive_0 = false;

#line 1013
            }

#line 1013
            if(alive_0)
            {

#line 1013
                alive_0 = kernelContext_34->params_0[int(36)] != 0U;

#line 1013
            }
            else
            {

#line 1013
                alive_0 = false;

#line 1013
            }

#line 1013
            if(alive_0)
            {

#line 1013
                restirClear_0(pixel_7, kernelContext_34);

#line 1013
            }


            if(depth_3 == 0U)
            {

#line 1016
                alive_0 = kernelContext_34->params_0[int(42)] != 0U;

#line 1016
            }
            else
            {

#line 1016
                alive_0 = false;

#line 1016
            }

#line 1016
            if(alive_0)
            {

#line 1016
                chan_1 = chan_2;

#line 1016
                alive_0 = false;


                break;
            }

            Parts_add_0(&st_1->parts_0, depth_3, cls_4, thr_1 * _S219);
            if(hasEnv_0)
            {

                if(st_1->misPrev_0)
                {
                    if(st_1->restir_1)
                    {

#line 1028
                        alive_0 = depth_3 == 1U;

#line 1028
                    }
                    else
                    {

#line 1028
                        alive_0 = false;

#line 1028
                    }

#line 1028
                    if(alive_0)
                    {

#line 1028
                        _S222 = 1.0f;

#line 1028
                    }

#line 1028
                    float _S223 = envPdf_0(dir_2, kernelContext_34);

#line 1028
                    float pl_0 = _S222 * _S223;
                    float den_0 = st_1->qPrev_0 * st_1->qPrev_0 + pl_0 * pl_0;
                    if(den_0 > 0.0f)
                    {

#line 1030
                        _S222 = st_1->qPrev_0 * st_1->qPrev_0 / den_0;

#line 1030
                    }
                    else
                    {

#line 1030
                        _S222 = 1.0f;

#line 1030
                    }

#line 1030
                    wB_0 = _S222;

#line 1026
                }
                else
                {

#line 1026
                    wB_0 = 1.0f;

#line 1026
                }

#line 1026
                float3 _S224 = envRadiance_0(dir_2, kernelContext_34);

#line 1032
                Parts_add_0(&st_1->parts_0, depth_3, cls_4, thr_1 * _S224 * float3(wB_0) );

#line 1023
            }

#line 1023
            chan_1 = chan_2;

#line 1023
            alive_0 = false;

#line 1034
            break;
        }

#line 1034
        uint _S225 = hq_0->inst_0;


        uint inst_3 = hq_0->inst_0 * 16U;

#line 1037
        uint _S226 = hq_0->prim_0;
        uint tri_1 = kernelContext_34->instances_0[inst_3 + 1U] + 3U * hq_0->prim_0;
        uint vo_1 = kernelContext_34->instances_0[inst_3];
        uint _S227 = inst_3 + 4U;

#line 1040
        float3 _S228 = vertexPos_0(kernelContext_34->indices_0[tri_1] + vo_1, kernelContext_34);

#line 1040
        float3 _S229 = transformPoint_0(_S227, _S228, kernelContext_34);
        uint _S230 = tri_1 + 1U;

#line 1041
        float3 _S231 = vertexPos_0(kernelContext_34->indices_0[_S230] + vo_1, kernelContext_34);

#line 1041
        float3 _S232 = transformPoint_0(_S227, _S231, kernelContext_34);
        uint _S233 = tri_1 + 2U;

#line 1042
        float3 _S234 = vertexPos_0(kernelContext_34->indices_0[_S233] + vo_1, kernelContext_34);

#line 1042
        float3 _S235 = transformPoint_0(_S227, _S234, kernelContext_34);

        float3 _S236 = _S232 - _S229;

#line 1044
        float3 _S237 = _S235 - _S229;

#line 1044
        float3 _S238 = cross(_S236, _S237);

#line 1044
        float3 nOut_0 = normalize(_S238);
        float3 wo_1 = - dir_2;
        bool outside_1 = (dot(nOut_0, wo_1)) > 0.0f;

#line 1046
        float3 ng_0;
        if(outside_1)
        {

#line 1047
            ng_0 = nOut_0;

#line 1047
        }
        else
        {

#line 1047
            ng_0 = - nOut_0;

#line 1047
        }

#line 1047
        float _S239 = hq_0->t_0;

        st_1->pathLen_0 = st_1->pathLen_0 + hq_0->t_0;
        float3 hit_1 = org_2 + dir_2 * float3(_S239) ;

#line 1056
        float3 e3_0 = hit_1 - _S229;
        float d11_0 = dot(_S236, _S236);
        float d12_0 = dot(_S236, _S237);
        float d22_0 = dot(_S237, _S237);
        float _S240 = max(d11_0 * d22_0 - d12_0 * d12_0, 9.99999968265522539e-21f);
        float _S241 = dot(e3_0, _S236);

#line 1061
        float _S242 = dot(e3_0, _S237);

#line 1061
        float b1_0 = (d22_0 * _S241 - d12_0 * _S242) / _S240;
        float b2_0 = (d11_0 * _S242 - d12_0 * _S241) / _S240;

#line 1062
        float _S243 = opacityAt_0(_S225, _S226, float2(b1_0, b2_0), kernelContext_34);


        if(_S243 < 1.0f)
        {

#line 1065
            float _S244 = Rng_next_0(&rng_4);

#line 1065
            alive_0 = _S244 >= _S243;

#line 1065
        }
        else
        {

#line 1065
            alive_0 = false;

#line 1065
        }

#line 1065
        if(alive_0)
        {

#line 1065
            org_2 = hit_1 + dir_2 * float3(9.9999997473787516e-05f) ;

#line 1065
            chan_1 = chan_2;

#line 1065
            alive_0 = true;


            break;
        }

        float3 p_6 = hit_1 + ng_0 * float3(9.9999997473787516e-05f) ;
        bool _S245 = depth_3 == 1U;

#line 1072
        if(_S245)
        {

#line 1072
            _S210 = st_1->gi_0;

#line 1072
        }
        else
        {

#line 1072
            _S210 = false;

#line 1072
        }

#line 1072
        if(_S210)
        {

            uint _S246 = restirBase_0(pixel_7, kernelContext_34->params_0[int(6)] & 1U);

#line 1075
            k_4 = 0U;
            for(;;)
            {

#line 1076
                if(k_4 < 3U)
                {
                }
                else
                {

#line 1076
                    break;
                }
                *(kernelContext_34->restir_0+(_S246 + 16U + k_4)) = hit_1[k_4];
                *(kernelContext_34->restir_0+(_S246 + 19U + k_4)) = ng_0[k_4];

#line 1076
                k_4 = k_4 + 1U;

#line 1076
            }

#line 1081
            *(kernelContext_34->restir_0+(restirScratch_0(pixel_7) + 22U)) = (as_type<float>((1U)));

#line 1072
        }

#line 1086
        float _S247 = 1.0f - b1_0 - b2_0;

#line 1086
        float3 _S248 = vertexNormal_0(kernelContext_34->indices_0[tri_1] + vo_1, kernelContext_34);

#line 1086
        float3 _S249 = float3(_S247)  * _S248;

#line 1086
        float3 _S250 = vertexNormal_0(kernelContext_34->indices_0[_S230] + vo_1, kernelContext_34);

#line 1086
        float3 _S251 = _S249 + float3(b1_0)  * _S250;

#line 1086
        float3 _S252 = vertexNormal_0(kernelContext_34->indices_0[_S233] + vo_1, kernelContext_34);

#line 1086
        float3 nsObj_0 = _S251 + float3(b2_0)  * _S252;

#line 1086
        float3 ns_0;

        if((dot(nsObj_0, nsObj_0)) > 9.999999960041972e-13f)
        {

#line 1088
            float3 _S253 = transformNormal_0(_S227, nsObj_0, kernelContext_34);

            float3 ns_1 = normalize(_S253);
            if((dot(ns_1, nOut_0)) < 0.0f)
            {

#line 1091
                ns_0 = - ns_1;

#line 1091
            }
            else
            {

#line 1091
                ns_0 = ns_1;

#line 1091
            }

#line 1088
        }
        else
        {

#line 1088
            ns_0 = nOut_0;

#line 1088
        }

#line 1088
        float3 _S254;

#line 1094
        if(outside_1)
        {

#line 1094
            _S254 = ns_0;

#line 1094
        }
        else
        {

#line 1094
            _S254 = - ns_0;

#line 1094
        }

        uint mi_1 = kernelContext_34->instances_0[inst_3 + 2U] * 24U;
        float3 albedo_1 = float3(kernelContext_34->materials_0[mi_1], kernelContext_34->materials_0[mi_1 + 1U], kernelContext_34->materials_0[mi_1 + 2U]);

        uint texBase_0 = uint(kernelContext_34->materials_0[mi_1 + 10U]);
        uint texMR_0 = uint(kernelContext_34->materials_0[mi_1 + 11U]);
        uint texEm_0 = uint(kernelContext_34->materials_0[mi_1 + 12U]);
        uint texNm_0 = uint(kernelContext_34->materials_0[mi_1 + 13U]);
        float2 _S255 = float2(1.0f) ;
        float3 _S256 = float3(1.0f) ;

#line 1104
        float3 albedo_2;

#line 1104
        float3 texEmission_0;

#line 1104
        float3 n_7;

#line 1104
        float3 n_8;

#line 1104
        bool _S257;

#line 1104
        float2 texRM_0;
        if((texBase_0 + texMR_0 + texEm_0 + texNm_0) > 0U)
        {
            float2 uv0_1 = float2(kernelContext_34->uvs_0[2U * (kernelContext_34->indices_0[tri_1] + vo_1)], kernelContext_34->uvs_0[2U * (kernelContext_34->indices_0[tri_1] + vo_1) + 1U]);


            float2 _S258 = float2(kernelContext_34->uvs_0[2U * (kernelContext_34->indices_0[_S230] + vo_1)], kernelContext_34->uvs_0[2U * (kernelContext_34->indices_0[_S230] + vo_1) + 1U]) - uv0_1;

#line 1110
            float2 _S259 = float2(kernelContext_34->uvs_0[2U * (kernelContext_34->indices_0[_S233] + vo_1)], kernelContext_34->uvs_0[2U * (kernelContext_34->indices_0[_S233] + vo_1) + 1U]) - uv0_1;

#line 1110
            float2 uv_2 = uv0_1 + float2(b1_0)  * _S258 + float2(b2_0)  * _S259;


            float _S260 = _S258.x;

#line 1113
            float _S261 = _S259.y;

#line 1113
            float _S262 = _S260 * _S261;

#line 1113
            float _S263 = _S258.y;

#line 1113
            float _S264 = _S259.x;

#line 1113
            float uvPerWorld_0 = sqrt(abs(_S262 - _S263 * _S264) / max(length(_S238), 9.99999968265522539e-21f));
            float _S265 = st_1->pathLen_0;

#line 1114
            float _S266 = pf_0(27U, kernelContext_34);

#line 1114
            float footprint_1 = _S265 * _S266 / max(abs(dot(nOut_0, dir_2)), 0.10000000149011612f) * uvPerWorld_0;
            if(texBase_0 > 0U)
            {

#line 1115
                float3 _S267 = sampleTexture_0(texBase_0 - 1U, uv_2, footprint_1, kernelContext_34);

#line 1115
                albedo_2 = albedo_1 * _S267;

#line 1115
            }
            else
            {

#line 1115
                albedo_2 = albedo_1;

#line 1115
            }

            if(texMR_0 > 0U)
            {

#line 1117
                float3 _S268 = sampleTexture_0(texMR_0 - 1U, uv_2, footprint_1, kernelContext_34);

#line 1117
                texRM_0 = _S268.yz;

#line 1117
            }
            else
            {

#line 1117
                texRM_0 = _S255;

#line 1117
            }

            if(texEm_0 > 0U)
            {

#line 1119
                float3 _S269 = sampleTexture_0(texEm_0 - 1U, uv_2, footprint_1, kernelContext_34);

#line 1119
                texEmission_0 = _S269;

#line 1119
            }
            else
            {

#line 1119
                texEmission_0 = _S256;

#line 1119
            }

            if(texNm_0 > 0U)
            {

                float det_0 = _S262 - _S264 * _S263;

#line 1124
                float3 _S270 = float3(det_0) ;
                float3 dPdu_0 = (_S236 * float3(_S261)  - _S237 * float3(_S263) ) / _S270;
                float3 dPdv_0 = (_S237 * float3(_S260)  - _S236 * float3(_S264) ) / _S270;
                float3 tg_0 = dPdu_0 - ns_0 * float3(dot(ns_0, dPdu_0)) ;
                if((abs(det_0)) > 9.99999968265522539e-21f)
                {

#line 1128
                    _S257 = (dot(tg_0, tg_0)) > 9.99999968265522539e-21f;

#line 1128
                }
                else
                {

#line 1128
                    _S257 = false;

#line 1128
                }

#line 1128
                if(_S257)
                {
                    float3 tg_1 = normalize(tg_0);
                    float3 bt_0 = cross(ns_0, tg_1);
                    if((dot(bt_0, dPdv_0)) > 0.0f)
                    {

#line 1132
                        n_7 = - bt_0;

#line 1132
                    }
                    else
                    {

#line 1132
                        n_7 = bt_0;

#line 1132
                    }

#line 1132
                    float3 _S271 = sampleTexture_0(texNm_0 - 1U, uv_2, footprint_1, kernelContext_34);

                    float3 nt_0 = _S271 * float3(2.0f)  - float3(1.0f) ;
                    uint _S272 = mi_1 + 14U;

#line 1135
                    float3 ns_2 = normalize(float3((nt_0.x * kernelContext_34->materials_0[_S272]))  * tg_1 + float3((nt_0.y * kernelContext_34->materials_0[_S272]))  * n_7 + float3(nt_0.z)  * ns_0);
                    if(outside_1)
                    {

#line 1136
                        n_8 = ns_2;

#line 1136
                    }
                    else
                    {

#line 1136
                        n_8 = - ns_2;

#line 1136
                    }

#line 1136
                    n_7 = n_8;

#line 1128
                }
                else
                {

#line 1128
                    n_7 = _S254;

#line 1128
                }

#line 1121
            }
            else
            {

#line 1121
                n_7 = _S254;

#line 1121
            }

#line 1105
        }
        else
        {

#line 1105
            n_7 = _S254;

#line 1105
            texEmission_0 = _S256;

#line 1105
            texRM_0 = _S255;

#line 1105
            albedo_2 = albedo_1;

#line 1105
        }

#line 1142
        float woN_0 = dot(n_7, wo_1);
        if(woN_0 < 0.05000000074505806f)
        {

#line 1143
            n_8 = normalize(n_7 + wo_1 * float3((0.05000000074505806f - woN_0)) );

#line 1143
        }
        else
        {

#line 1143
            n_8 = n_7;

#line 1143
        }


        float3 _S273 = float3(kernelContext_34->materials_0[mi_1 + 3U], kernelContext_34->materials_0[mi_1 + 4U], kernelContext_34->materials_0[mi_1 + 5U]) * texEmission_0;

        if((st_1->prevInst_0) != 0U)
        {

#line 1148
            uint _S274 = emitMask_0(_S225, kernelContext_34);

#line 1148
            uint _S275 = recvMask_0(st_1->prevInst_0 - 1U, kernelContext_34);

#line 1148
            _S257 = (_S274 & _S275) == 0U;

#line 1148
        }
        else
        {

#line 1148
            _S257 = false;

#line 1148
        }

#line 1148
        float3 le_1;

#line 1148
        if(_S257)
        {

#line 1148
            le_1 = float3(0.0f) ;

#line 1148
        }
        else
        {

#line 1148
            le_1 = _S273;

#line 1148
        }

#line 1148
        bool _S276;

#line 1148
        bool _S277;

        if(any(le_1 > (float3(0.0f) )))
        {

            uint eb_0 = kernelContext_34->instances_0[inst_3 + 3U];
            if(st_1->misPrev_0)
            {

#line 1154
                _S276 = eb_0 != 0U;

#line 1154
            }
            else
            {

#line 1154
                _S276 = false;

#line 1154
            }

#line 1154
            if(_S276)
            {
                uint e_2 = (eb_0 - 1U + _S226) * 16U;
                float _S278 = max(abs(dot(nOut_0, dir_2)), 9.9999997473787516e-05f);
                if(st_1->restir_1)
                {

#line 1158
                    _S277 = _S245;

#line 1158
                }
                else
                {

#line 1158
                    _S277 = false;

#line 1158
                }

#line 1158
                if(_S277)
                {

#line 1158
                    wB_0 = 1.0f;

#line 1158
                }
                else
                {

#line 1158
                    wB_0 = 1.0f - _S222;

#line 1158
                }

#line 1158
                float pl_1 = wB_0 * kernelContext_34->emitters_0[e_2 + 13U] * _S239 * _S239 / (kernelContext_34->emitters_0[e_2 + 12U] * _S278);

#line 1158
                wB_0 = st_1->qPrev_0 * st_1->qPrev_0 / (st_1->qPrev_0 * st_1->qPrev_0 + pl_1 * pl_1);

#line 1154
            }
            else
            {

#line 1154
                wB_0 = 1.0f;

#line 1154
            }

#line 1161
            float3 _S279 = thr_1 * le_1 * float3(wB_0) ;

#line 1161
            Parts_add_0(&st_1->parts_0, depth_3, cls_4, _S279);
            if(_S245)
            {

#line 1162
                _S277 = st_1->gi_0;

#line 1162
            }
            else
            {

#line 1162
                _S277 = false;

#line 1162
            }

#line 1162
            if(_S277)
            {


                uint _S280 = restirScratch_0(pixel_7) + 18U;

#line 1166
                k_4 = 0U;
                for(;;)
                {

#line 1167
                    if(k_4 < 3U)
                    {
                    }
                    else
                    {

#line 1167
                        break;
                    }

#line 1168
                    float device* _S281 = kernelContext_34->restir_0+(_S280 + k_4);

#line 1168
                    *_S281 = *_S281 + _S279[k_4];

#line 1167
                    k_4 = k_4 + 1U;

#line 1167
                }

#line 1162
            }

#line 1150
        }

#line 1171
        float metallic_1 = kernelContext_34->materials_0[mi_1 + 6U] * texRM_0.y;
        float rough_1 = kernelContext_34->materials_0[mi_1 + 7U] * texRM_0.x;
        float transmission_2 = kernelContext_34->materials_0[mi_1 + 8U];
        float ior_2 = kernelContext_34->materials_0[mi_1 + 9U];
        float dispersion_0 = kernelContext_34->materials_0[mi_1 + 21U];
        if(dispersion_0 > 0.0f)
        {

#line 1176
            _S276 = transmission_2 > 0.0f;

#line 1176
        }
        else
        {

#line 1176
            _S276 = false;

#line 1176
        }

#line 1176
        float eta_2;

#line 1176
        float _S282;

#line 1176
        float3 thr_2;

#line 1176
        if(_S276)
        {


            if(chan_2 < int(0))
            {
                float _S283 = Rng_next_0(&rng_4);

#line 1182
                int _S284 = min(int(_S283 * 3.0f), int(2));
                if(_S284 == int(0))
                {

#line 1183
                    wB_0 = 1.0f;

#line 1183
                }
                else
                {

#line 1183
                    wB_0 = 0.0f;

#line 1183
                }

#line 1183
                if(_S284 == int(1))
                {

#line 1183
                    eta_2 = 1.0f;

#line 1183
                }
                else
                {

#line 1183
                    eta_2 = 0.0f;

#line 1183
                }

#line 1183
                if(_S284 == int(2))
                {

#line 1183
                    _S282 = 1.0f;

#line 1183
                }
                else
                {

#line 1183
                    _S282 = 0.0f;

#line 1183
                }

#line 1183
                float3 thr_3 = thr_1 * (float3(3.0f)  * float3(wB_0, eta_2, _S282));

#line 1183
                chan_1 = _S284;

#line 1183
                thr_2 = thr_3;

#line 1180
            }
            else
            {

#line 1180
                chan_1 = chan_2;

#line 1180
                thr_2 = thr_1;

#line 1180
            }

#line 1180
            wB_0 = max(ior_2 + float(chan_1 - int(1)) * (ior_2 - 1.0f) * 0.02500000037252903f * dispersion_0, 1.0f);

#line 1176
        }
        else
        {

#line 1176
            wB_0 = ior_2;

#line 1176
            chan_1 = chan_2;

#line 1176
            thr_2 = thr_1;

#line 1176
        }

#line 1189
        if(_S245)
        {

#line 1189
            _S277 = st_1->gi_0;

#line 1189
        }
        else
        {

#line 1189
            _S277 = false;

#line 1189
        }

#line 1189
        bool _S285;

#line 1189
        if(_S277)
        {

#line 1189
            _S285 = transmission_2 > 0.0f;

#line 1189
        }
        else
        {

#line 1189
            _S285 = false;

#line 1189
        }

#line 1189
        if(_S285)
        {

#line 1190
            *(kernelContext_34->restir_0+(restirScratch_0(pixel_7) + 22U)) = (as_type<float>((0U)));

#line 1189
        }

        float _S286 = max(rough_1 * rough_1, 0.0010000000474974513f);
        if(outside_1)
        {

#line 1192
            eta_2 = wB_0;

#line 1192
        }
        else
        {

#line 1192
            eta_2 = 1.0f / wB_0;

#line 1192
        }

        thread float3 T_2;

#line 1194
        thread float3 B_2;
        basis_0(n_8, &T_2, &B_2);
        float _S287 = max(dot(wo_1, n_8), 9.9999997473787516e-05f);

#line 1196
        float3 woL_6 = float3(dot(wo_1, T_2), dot(wo_1, B_2), _S287);
        float fSel_1 = fresnelDielectric_0(_S287, wB_0);
        thread Surface_0 surf_3;
        (&surf_3)->albedo_0 = albedo_2;
        (&surf_3)->metallic_0 = metallic_1;
        (&surf_3)->alpha_3 = _S286;
        (&surf_3)->transmission_1 = transmission_2;
        (&surf_3)->ior_1 = wB_0;
        (&surf_3)->eta_1 = eta_2;
        (&surf_3)->fSel_0 = fSel_1;


        (&surf_3)->tComp_0 = 1.0f;

#line 1208
        bool _S288;
        if(kernelContext_34->params_0[int(29)] != 0U)
        {

#line 1209
            _S288 = transmission_2 > 0.0f;

#line 1209
        }
        else
        {

#line 1209
            _S288 = false;

#line 1209
        }

#line 1209
        bool _S289;

#line 1209
        if(_S288)
        {

#line 1209
            _S289 = rough_1 > 0.0f;

#line 1209
        }
        else
        {

#line 1209
            _S289 = false;

#line 1209
        }

#line 1209
        if(_S289)
        {

#line 1209
            float _S290 = dielectricAlbedo_0(_S287, rough_1, wB_0, outside_1, kernelContext_34);
            (&surf_3)->tComp_0 = 1.0f / max(_S290, 0.10000000149011612f);

#line 1209
        }


        if(outside_1)
        {

#line 1212
            _S282 = kernelContext_34->materials_0[mi_1 + 15U];

#line 1212
        }
        else
        {

#line 1212
            _S282 = 0.0f;

#line 1212
        }

#line 1212
        (&surf_3)->coat_0 = _S282;
        uint _S291 = mi_1 + 16U;

#line 1213
        (&surf_3)->coatAlpha_0 = max(kernelContext_34->materials_0[_S291] * kernelContext_34->materials_0[_S291], 0.0010000000474974513f);
        float coatF_0 = fresnelDielectric_0(_S287, 1.5f);
        (&surf_3)->coatP_0 = _S282 * coatF_0;

#line 1215
        float3 _S292;
        if(outside_1)
        {

#line 1216
            _S292 = float3(kernelContext_34->materials_0[mi_1 + 18U], kernelContext_34->materials_0[mi_1 + 19U], kernelContext_34->materials_0[mi_1 + 20U]);

#line 1216
        }
        else
        {

#line 1216
            _S292 = float3(0.0f) ;

#line 1216
        }

#line 1216
        (&surf_3)->sheenColor_0 = _S292;
        float _S293 = max(_S292.x, max(_S292.y, _S292.z));
        float _S294 = max(kernelContext_34->materials_0[mi_1 + 17U], 0.070000000298023224f);
        (&surf_3)->sheenAlpha_0 = _S294 * _S294;

#line 1219
        float _S295;
        if(_S293 > 0.0f)
        {

#line 1220
            float _S296 = sheenAlbedo_0(_S287, _S294, kernelContext_34);

#line 1220
            _S295 = _S293 * _S296;

#line 1220
        }
        else
        {

#line 1220
            _S295 = 0.0f;

#line 1220
        }

#line 1220
        (&surf_3)->sheenP_0 = _S295;

#line 1220
        k_4 = 0U;



        for(;;)
        {

#line 1224
            if(k_4 < _S221)
            {
            }
            else
            {

#line 1224
                break;
            }
            uint o_7 = k_4 * 16U;
            float3 col_0 = float3((as_type<float>((kernelContext_34->lights_0[o_7 + 1U]))), (as_type<float>((kernelContext_34->lights_0[o_7 + 2U]))), (as_type<float>((kernelContext_34->lights_0[o_7 + 3U])))) * float3((as_type<float>((kernelContext_34->lights_0[o_7 + 4U])))) ;
            float3 vec_0 = float3((as_type<float>((kernelContext_34->lights_0[o_7 + 5U]))), (as_type<float>((kernelContext_34->lights_0[o_7 + 6U]))), (as_type<float>((kernelContext_34->lights_0[o_7 + 7U]))));

            bool virt_0 = kernelContext_34->lights_0[o_7] == 3U;
            if(virt_0)
            {

#line 1231
                if(_S220)
                {

#line 1231
                    _S213 = depth_3 == 0U;

#line 1231
                }
                else
                {

#line 1231
                    _S213 = false;

#line 1231
                }

#line 1231
                _S213 = !_S213;

#line 1231
            }
            else
            {

#line 1231
                _S213 = false;

#line 1231
            }

#line 1231
            if(_S213)
            {

#line 1232
                k_4 = k_4 + 1U;

#line 1224
                continue;
            }

#line 1234
            uint _S297 = kernelContext_34->lights_0[o_7 + 14U];

#line 1234
            uint _S298 = recvMask_0(_S225, kernelContext_34);

#line 1234
            if((_S297 & _S298) == 0U)
            {

#line 1235
                k_4 = k_4 + 1U;

#line 1224
                continue;
            }

#line 1239
            if(kernelContext_34->lights_0[o_7] == 1U)
            {

#line 1239
                _S214 = true;

#line 1239
            }
            else
            {

#line 1239
                _S214 = virt_0;

#line 1239
            }

#line 1239
            if(_S214)
            {

#line 1239
                wi_6 = - normalize(vec_0);

#line 1239
                dist_4 = 1.00000001504746622e+30f;

#line 1239
                li_0 = col_0;

#line 1239
            }
            else
            {

#line 1247
                float3 toL_1 = vec_0 - p_6;
                float d2_1 = dot(toL_1, toL_1);
                float dist_5 = sqrt(d2_1);
                float3 wi_7 = toL_1 / float3(dist_5) ;
                float3 li_1 = col_0 / float3(d2_1) ;
                uint _S299 = o_7 + 15U;

#line 1252
                if(kernelContext_34->lights_0[_S299] != 0U)
                {

#line 1252
                    float _S300 = iesFactor_0(kernelContext_34->lights_0[_S299] - 1U, - wi_7, kernelContext_34);

#line 1252
                    wi_6 = li_1 * float3(_S300) ;

#line 1252
                }
                else
                {

#line 1252
                    wi_6 = li_1;

#line 1252
                }

                if(kernelContext_34->lights_0[o_7] == 2U)
                {

                    float att_0 = saturate(dot(float3((as_type<float>((kernelContext_34->lights_0[o_7 + 8U]))), (as_type<float>((kernelContext_34->lights_0[o_7 + 9U]))), (as_type<float>((kernelContext_34->lights_0[o_7 + 10U])))), - wi_7) * (as_type<float>((kernelContext_34->lights_0[o_7 + 11U]))) + (as_type<float>((kernelContext_34->lights_0[o_7 + 12U]))));

#line 1257
                    li_0 = wi_6 * float3((att_0 * att_0)) ;

#line 1254
                }
                else
                {

#line 1254
                    li_0 = wi_6;

#line 1254
                }

#line 1254
                wi_6 = wi_7;

#line 1254
                dist_4 = dist_5;

#line 1239
            }

#line 1261
            float c_8 = dot(n_8, wi_6);
            if(c_8 > 0.0f)
            {

#line 1262
                bool _S301 = occluded_0(p_6, wi_6, dist_4 - 0.0010000000474974513f, kernelContext_34);


                if(_S220)
                {

#line 1265
                    track_0 = depth_3 == 0U;

#line 1265
                }
                else
                {

#line 1265
                    track_0 = false;

#line 1265
                }
                bool _S302 = !_S301;

#line 1266
                if(_S302)
                {

#line 1266
                    chooseEnv_0 = true;

#line 1266
                }
                else
                {

#line 1266
                    chooseEnv_0 = track_0;

#line 1266
                }

#line 1266
                if(chooseEnv_0)
                {
                    float3 _S303 = float3(dot(wi_6, T_2), dot(wi_6, B_2), c_8);

#line 1268
                    thread Surface_0 _S304 = surf_3;

#line 1268
                    Lobes_0 _S305 = evalLobes_0(&_S304, woL_6, _S303, kernelContext_34);
                    float3 cd_1 = thr_2 * _S305.diffuse_0 * li_0;
                    float3 cs_1 = thr_2 * _S305.specular_1 * li_0;
                    if(_S302)
                    {

#line 1271
                        _S215 = !virt_0;

#line 1271
                    }
                    else
                    {

#line 1271
                        _S215 = false;

#line 1271
                    }

#line 1271
                    if(_S215)
                    {

#line 1272
                        Parts_addLight_0(&st_1->parts_0, depth_3, cls_4, thr_2 * (_S305.diffuse_0 + _S305.specular_1) * li_0, cd_1, cs_1);

#line 1271
                    }

                    if(track_0)
                    {
                        if(virt_0)
                        {

#line 1275
                            vv_0 = 0.0f;

#line 1275
                        }
                        else
                        {

#line 1275
                            vv_0 = lum_0(cd_1 + cs_1);

#line 1275
                        }
                        st_1->visTotal_0 = st_1->visTotal_0 + vv_0;
                        if(_S301)
                        {

#line 1277
                            us_0 = 0.0f;

#line 1277
                        }
                        else
                        {

#line 1277
                            us_0 = vv_0;

#line 1277
                        }

#line 1277
                        st_1->visLit_0 = st_1->visLit_0 + us_0;
                        uint _S306 = kernelContext_34->lights_0[o_7 + 13U];

#line 1278
                        float3 _S307 = float3(c_8) ;

#line 1278
                        float3 _S308 = cd_1 / _S307;

#line 1278
                        float3 _S309 = cs_1 / _S307;

#line 1278
                        if(_S301)
                        {

#line 1278
                            _S211 = 0.0f;

#line 1278
                        }
                        else
                        {

#line 1278
                            _S211 = 1.0f;

#line 1278
                        }

#line 1278
                        if(_S301)
                        {

#line 1278
                            _S212 = 0.0f;

#line 1278
                        }
                        else
                        {

#line 1278
                            _S212 = c_8;

#line 1278
                        }

#line 1278
                        addSlot_0(pixel_7, _S306, _S308, _S309, wi_6, _S211, _S212, kernelContext_34);

#line 1273
                    }

#line 1266
                }

#line 1262
            }

#line 1224
            k_4 = k_4 + 1U;

#line 1224
        }

#line 1287
        if(restirCompiled_0)
        {

#line 1287
            _S213 = depth_3 == 0U;

#line 1287
        }
        else
        {

#line 1287
            _S213 = false;

#line 1287
        }

#line 1287
        if(_S213)
        {

#line 1287
            _S214 = kernelContext_34->params_0[int(36)] != 0U;

#line 1287
        }
        else
        {

#line 1287
            _S214 = false;

#line 1287
        }

#line 1287
        bool suits_0;

#line 1287
        bool ok_0;

#line 1287
        bool reDI_0;

#line 1287
        bool refracted_0;

#line 1287
        if(_S214)
        {

#line 1287
            float _S310 = pf_0(3U, kernelContext_34);

            if(_S310 == 0.0f)
            {

#line 1289
                chooseEnv_0 = transmission_2 == 0.0f;

#line 1289
            }
            else
            {

#line 1289
                chooseEnv_0 = false;

#line 1289
            }

#line 1289
            if(chooseEnv_0)
            {

#line 1289
                _S215 = ((&surf_3)->alpha_3) >= 0.15000000596046448f;

#line 1289
            }
            else
            {

#line 1289
                _S215 = false;

#line 1289
            }
            if(_S215)
            {

#line 1290
                if(((&surf_3)->coat_0) == 0.0f)
                {

#line 1290
                    suits_0 = true;

#line 1290
                }
                else
                {

#line 1290
                    suits_0 = ((&surf_3)->coatAlpha_0) >= 0.15000000596046448f;

#line 1290
                }

#line 1290
            }
            else
            {

#line 1290
                suits_0 = false;

#line 1290
            }
            if(suits_0)
            {

#line 1291
                ok_0 = (kernelContext_34->params_0[int(36)] & 1U) != 0U;

#line 1291
            }
            else
            {

#line 1291
                ok_0 = false;

#line 1291
            }

#line 1291
            if(ok_0)
            {

#line 1291
                reDI_0 = emitterCount_0 > 0U;

#line 1291
            }
            else
            {

#line 1291
                reDI_0 = false;

#line 1291
            }

            if(suits_0)
            {

#line 1293
                refracted_0 = (kernelContext_34->params_0[int(36)] & 2U) != 0U;

#line 1293
            }
            else
            {

#line 1293
                refracted_0 = false;

#line 1293
            }

#line 1293
            if(refracted_0)
            {

#line 1293
                track_0 = !_S220;

#line 1293
            }
            else
            {

#line 1293
                track_0 = false;

#line 1293
            }
            st_1->restir_1 = reDI_0;
            st_1->gi_0 = track_0;
            if(suits_0)
            {

#line 1296
                restirGbuffer_0(pixel_7, p_6, n_8, kernelContext_34);


                if(track_0)
                {

#line 1299
                    thread Surface_0 _S311 = surf_3;

#line 1299
                    restirGIPrepare_0(pixel_7, p_6, n_8, _S239, &_S311, T_2, B_2, woL_6, &rng_4, kernelContext_34);

#line 1299
                }

#line 1296
            }
            else
            {

#line 1296
                restirClear_0(pixel_7, kernelContext_34);

#line 1296
            }

#line 1287
        }
        else
        {

#line 1287
            reDI_0 = false;

#line 1287
        }

#line 1305
        if(reDI_0)
        {

#line 1305
            uint _S312 = recvMask_0(_S225, kernelContext_34);

#line 1305
            thread Surface_0 _S313 = surf_3;

#line 1305
            RestirPick_0 _S314 = restirDI_0(pixel_7, _S312, p_6, n_8, _S239, &_S313, T_2, B_2, woL_6, &rng_4, kernelContext_34);


            if(_S314.valid_0)
            {


                uint _S315 = _S314.e_1 - 1U;

#line 1312
                uint _S316 = recvMask_0(_S225, kernelContext_34);

#line 1310
                thread float3 wi_8;

#line 1310
                thread float3 g_4;
                thread float dist_6;

#line 1311
                thread float cosi_5;

#line 1311
                thread float plsa_5;

#line 1311
                bool _S317 = restirLight_0(_S315, _S316, _S314.x_6, p_6, n_8, &wi_8, &dist_6, &cosi_5, &g_4, &plsa_5, kernelContext_34);


                bool _S318 = !_S314.occ_0;

#line 1314
                if(_S318)
                {

#line 1314
                    chooseEnv_0 = true;

#line 1314
                }
                else
                {

#line 1314
                    chooseEnv_0 = _S220;

#line 1314
                }

#line 1314
                if(chooseEnv_0)
                {
                    float3 wiL_6 = float3(dot(wi_8, T_2), dot(wi_8, B_2), cosi_5);

#line 1316
                    thread Surface_0 _S319 = surf_3;

#line 1316
                    float _S320 = restirMis_0(&_S319, woL_6, wiL_6, plsa_5);

#line 1316
                    thread Surface_0 _S321 = surf_3;

#line 1316
                    Lobes_0 _S322 = evalLobes_0(&_S321, woL_6, wiL_6, kernelContext_34);

#line 1316
                    float3 _S323 = float3((_S320 * _S314.W_0)) ;


                    float3 cd_2 = thr_2 * _S322.diffuse_0 * g_4 * _S323;
                    float3 cs_2 = thr_2 * _S322.specular_1 * g_4 * _S323;
                    if(_S318)
                    {

#line 1322
                        Parts_addLight_0(&st_1->parts_0, depth_3, cls_4, cd_2 + cs_2, cd_2, cs_2);

#line 1321
                    }

                    if(_S220)
                    {
                        float vv_1 = lum_0(cd_2 + cs_2);
                        st_1->visTotal_0 = st_1->visTotal_0 + vv_1;
                        if(_S314.occ_0)
                        {

#line 1327
                            dist_4 = 0.0f;

#line 1327
                        }
                        else
                        {

#line 1327
                            dist_4 = vv_1;

#line 1327
                        }

#line 1327
                        st_1->visLit_0 = st_1->visLit_0 + dist_4;
                        float3 _S324 = cd_2 / float3(cosi_5) ;

#line 1328
                        float3 _S325 = cs_2 / float3(cosi_5) ;

#line 1328
                        float3 _S326 = wi_8;

#line 1328
                        if(_S314.occ_0)
                        {

#line 1328
                            vv_0 = 0.0f;

#line 1328
                        }
                        else
                        {

#line 1328
                            vv_0 = 1.0f;

#line 1328
                        }

#line 1328
                        if(_S314.occ_0)
                        {

#line 1328
                            us_0 = 0.0f;

#line 1328
                        }
                        else
                        {

#line 1328
                            us_0 = cosi_5;

#line 1328
                        }

#line 1328
                        addSlot_0(pixel_7, 3U, _S324, _S325, _S326, vv_0, us_0, kernelContext_34);

#line 1323
                    }

#line 1314
                }

#line 1308
            }

#line 1305
        }

#line 1335
        float chooseLight_0 = Rng_next_0(&rng_4);
        if(reDI_0)
        {

#line 1336
            if(hasEnv_0)
            {

#line 1336
                dist_4 = 1.0f;

#line 1336
            }
            else
            {

#line 1336
                dist_4 = 0.0f;

#line 1336
            }

#line 1336
        }
        else
        {

#line 1336
            dist_4 = _S222;

#line 1336
        }
        if(hasEnv_0)
        {

#line 1337
            chooseEnv_0 = chooseLight_0 < dist_4;

#line 1337
        }
        else
        {

#line 1337
            chooseEnv_0 = false;

#line 1337
        }
        if(emitterCount_0 > 0U)
        {

#line 1338
            _S215 = !chooseEnv_0;

#line 1338
        }
        else
        {

#line 1338
            _S215 = false;

#line 1338
        }

#line 1338
        if(_S215)
        {

#line 1338
            suits_0 = !reDI_0;

#line 1338
        }
        else
        {

#line 1338
            suits_0 = false;

#line 1338
        }

#line 1338
        uint lobeCls_0;

#line 1338
        uint cls_5;

#line 1338
        if(suits_0)
        {
            float _S327 = Rng_next_0(&rng_4);
            float ua_1 = Rng_next_0(&rng_4);
            float ub_1 = Rng_next_0(&rng_4);

            uint _S328 = emitterCount_0 - 1U;

#line 1344
            lobeCls_0 = 0U;

#line 1344
            cls_5 = _S328;
            for(;;)
            {

#line 1345
                if(lobeCls_0 < cls_5)
                {
                }
                else
                {

#line 1345
                    break;
                }
                uint mid_3 = (lobeCls_0 + cls_5) / 2U;
                if(kernelContext_34->emitCdf_0[mid_3] >= _S327)
                {

#line 1348
                    cls_5 = mid_3;

#line 1348
                }
                else
                {

#line 1348
                    lobeCls_0 = mid_3 + 1U;

#line 1348
                }

#line 1345
            }

#line 1353
            uint e_3 = lobeCls_0 * 16U;
            float3 a_7 = float3(kernelContext_34->emitters_0[e_3], kernelContext_34->emitters_0[e_3 + 1U], kernelContext_34->emitters_0[e_3 + 2U]);
            float3 b_3 = float3(kernelContext_34->emitters_0[e_3 + 3U], kernelContext_34->emitters_0[e_3 + 4U], kernelContext_34->emitters_0[e_3 + 5U]);
            float3 c_9 = float3(kernelContext_34->emitters_0[e_3 + 6U], kernelContext_34->emitters_0[e_3 + 7U], kernelContext_34->emitters_0[e_3 + 8U]);
            float su_1 = sqrt(ua_1);

            float3 toL_2 = a_7 * float3((1.0f - su_1))  + b_3 * float3((su_1 * (1.0f - ub_1)))  + c_9 * float3((su_1 * ub_1))  - p_6;
            float d2_2 = dot(toL_2, toL_2);
            float dist_7 = sqrt(d2_2);
            float3 wi_9 = toL_2 / float3(dist_7) ;
            float cosl_1 = abs(dot(normalize(cross(b_3 - a_7, c_9 - a_7)), wi_9));
            float cosi_6 = dot(n_8, wi_9);
            if(cosi_6 > 0.0f)
            {

#line 1365
                ok_0 = cosl_1 > 9.9999997473787516e-06f;

#line 1365
            }
            else
            {

#line 1365
                ok_0 = false;

#line 1365
            }

#line 1365
            if(ok_0)
            {

#line 1365
                uint _S329 = (as_type<uint>((kernelContext_34->emitters_0[e_3 + 14U])));

#line 1365
                uint _S330 = recvMask_0(_S225, kernelContext_34);

#line 1365
                refracted_0 = (_S329 & _S330) != 0U;

#line 1365
            }
            else
            {

#line 1365
                refracted_0 = false;

#line 1365
            }

#line 1365
            if(refracted_0)
            {

#line 1365
                bool _S331 = occluded_0(p_6, wi_9, dist_7 * 0.99900001287460327f, kernelContext_34);


                if(_S220)
                {

#line 1368
                    track_0 = depth_3 == 0U;

#line 1368
                }
                else
                {

#line 1368
                    track_0 = false;

#line 1368
                }
                bool _S332 = !_S331;

#line 1369
                bool _S333;

#line 1369
                if(_S332)
                {

#line 1369
                    _S333 = true;

#line 1369
                }
                else
                {

#line 1369
                    _S333 = track_0;

#line 1369
                }

#line 1369
                if(_S333)
                {
                    float pl_2 = (1.0f - _S222) * kernelContext_34->emitters_0[e_3 + 13U] * d2_2 / (kernelContext_34->emitters_0[e_3 + 12U] * cosl_1);
                    float3 wiL_7 = float3(dot(wi_9, T_2), dot(wi_9, B_2), cosi_6);

#line 1372
                    thread Surface_0 _S334 = surf_3;

#line 1372
                    float _S335 = reflectivePdf_0(&_S334, woL_6, wiL_7);

                    float _S336 = pl_2 * pl_2;

#line 1374
                    float wl_0 = _S336 / (_S336 + _S335 * _S335);
                    float3 le_2 = float3(kernelContext_34->emitters_0[e_3 + 9U], kernelContext_34->emitters_0[e_3 + 10U], kernelContext_34->emitters_0[e_3 + 11U]);

#line 1375
                    thread Surface_0 _S337 = surf_3;

#line 1375
                    Lobes_0 _S338 = evalLobes_0(&_S337, woL_6, wiL_7, kernelContext_34);

#line 1375
                    float3 _S339 = float3(pl_2) ;

#line 1375
                    float3 _S340 = float3(wl_0) ;

                    float3 cd_3 = thr_2 * _S338.diffuse_0 * le_2 / _S339 * _S340;
                    float3 cs_3 = thr_2 * _S338.specular_1 * le_2 / _S339 * _S340;
                    if(_S332)
                    {

#line 1379
                        thread Surface_0 _S341 = surf_3;

#line 1379
                        float3 _S342 = evalReflective_0(&_S341, woL_6, wiL_7, kernelContext_34);
                        Parts_addLight_0(&st_1->parts_0, depth_3, cls_4, thr_2 * _S342 * le_2 / _S339 * _S340, cd_3, cs_3);

#line 1379
                    }

                    if(track_0)
                    {
                        float vv_2 = lum_0(cd_3 + cs_3);
                        st_1->visTotal_0 = st_1->visTotal_0 + vv_2;
                        if(_S331)
                        {

#line 1385
                            vv_0 = 0.0f;

#line 1385
                        }
                        else
                        {

#line 1385
                            vv_0 = vv_2;

#line 1385
                        }

#line 1385
                        st_1->visLit_0 = st_1->visLit_0 + vv_0;

#line 1385
                        float3 _S343 = float3(cosi_6) ;
                        float3 _S344 = cd_3 / _S343;

#line 1386
                        float3 _S345 = cs_3 / _S343;

#line 1386
                        if(_S331)
                        {

#line 1386
                            us_0 = 0.0f;

#line 1386
                        }
                        else
                        {

#line 1386
                            us_0 = 1.0f;

#line 1386
                        }

#line 1386
                        if(_S331)
                        {

#line 1386
                            _S211 = 0.0f;

#line 1386
                        }
                        else
                        {

#line 1386
                            _S211 = cosi_6;

#line 1386
                        }

#line 1386
                        addSlot_0(pixel_7, 3U, _S344, _S345, wi_9, us_0, _S211, kernelContext_34);

#line 1381
                    }

#line 1369
                }

#line 1365
            }

#line 1338
        }

#line 1392
        if(chooseEnv_0)
        {
            float e1_0 = Rng_next_0(&rng_4);
            float e2_0 = Rng_next_0(&rng_4);
            float e3_1 = Rng_next_0(&rng_4);
            float e4_0 = Rng_next_0(&rng_4);
            thread float pdfE_0;
            thread float3 leE_0;

#line 1399
            float3 _S346 = envSample_0(e1_0, e2_0, e3_1, e4_0, &pdfE_0, &leE_0, kernelContext_34);

            float cosi_7 = dot(n_8, _S346);
            if(pdfE_0 > 0.0f)
            {

#line 1402
                ok_0 = cosi_7 > 0.0f;

#line 1402
            }
            else
            {

#line 1402
                ok_0 = false;

#line 1402
            }

#line 1402
            if(ok_0)
            {

#line 1402
                bool _S347 = occluded_0(p_6, _S346, 1.00000001504746622e+30f, kernelContext_34);


                if(_S220)
                {

#line 1405
                    track_0 = depth_3 == 0U;

#line 1405
                }
                else
                {

#line 1405
                    track_0 = false;

#line 1405
                }
                bool _S348 = !_S347;

#line 1406
                if(_S348)
                {

#line 1406
                    refracted_0 = true;

#line 1406
                }
                else
                {

#line 1406
                    refracted_0 = track_0;

#line 1406
                }

#line 1406
                if(refracted_0)
                {
                    float pl_3 = dist_4 * pdfE_0;
                    float3 wiL_8 = float3(dot(_S346, T_2), dot(_S346, B_2), cosi_7);

#line 1409
                    thread Surface_0 _S349 = surf_3;

#line 1409
                    float _S350 = reflectivePdf_0(&_S349, woL_6, wiL_8);

                    float _S351 = pl_3 * pl_3;

#line 1411
                    float wl_1 = _S351 / (_S351 + _S350 * _S350);

#line 1411
                    thread Surface_0 _S352 = surf_3;

#line 1411
                    Lobes_0 _S353 = evalLobes_0(&_S352, woL_6, wiL_8, kernelContext_34);

#line 1411
                    float3 _S354 = float3(pl_3) ;

#line 1411
                    float3 _S355 = float3(wl_1) ;

                    float3 cd_4 = thr_2 * _S353.diffuse_0 * leE_0 / _S354 * _S355;
                    float3 cs_4 = thr_2 * _S353.specular_1 * leE_0 / _S354 * _S355;
                    if(_S348)
                    {

#line 1415
                        thread Surface_0 _S356 = surf_3;

#line 1415
                        float3 _S357 = evalReflective_0(&_S356, woL_6, wiL_8, kernelContext_34);
                        Parts_addLight_0(&st_1->parts_0, depth_3, cls_4, thr_2 * _S357 * leE_0 / _S354 * _S355, cd_4, cs_4);

#line 1415
                    }

                    if(track_0)
                    {
                        float vv_3 = lum_0(cd_4 + cs_4);
                        st_1->visTotal_0 = st_1->visTotal_0 + vv_3;
                        if(_S347)
                        {

#line 1421
                            vv_0 = 0.0f;

#line 1421
                        }
                        else
                        {

#line 1421
                            vv_0 = vv_3;

#line 1421
                        }

#line 1421
                        st_1->visLit_0 = st_1->visLit_0 + vv_0;
                        if(kernelContext_34->params_0[int(41)] == 0U)
                        {

#line 1422
                            float3 _S358 = float3(cosi_7) ;
                            float3 _S359 = cd_4 / _S358;

#line 1423
                            float3 _S360 = cs_4 / _S358;

#line 1423
                            if(_S347)
                            {

#line 1423
                                us_0 = 0.0f;

#line 1423
                            }
                            else
                            {

#line 1423
                                us_0 = 1.0f;

#line 1423
                            }

#line 1423
                            if(_S347)
                            {

#line 1423
                                _S211 = 0.0f;

#line 1423
                            }
                            else
                            {

#line 1423
                                _S211 = cosi_7;

#line 1423
                            }

#line 1423
                            addSlot_0(pixel_7, 3U, _S359, _S360, _S346, us_0, _S211, kernelContext_34);

#line 1422
                        }

#line 1417
                    }

#line 1406
                }

#line 1402
            }

#line 1392
        }

#line 1431
        float lobe_0 = Rng_next_0(&rng_4);
        float u1_3 = Rng_next_0(&rng_4);
        float u2_3 = Rng_next_0(&rng_4);
        float u3_1 = Rng_next_0(&rng_4);

#line 1440
        if(((&surf_3)->coat_0) > 0.0f)
        {

#line 1440
            float _S361 = Rng_next_0(&rng_4);

#line 1440
            vv_0 = _S361;

#line 1440
        }
        else
        {

#line 1440
            vv_0 = 1.0f;

#line 1440
        }
        if(((&surf_3)->sheenP_0) > 0.0f)
        {

#line 1441
            float _S362 = Rng_next_0(&rng_4);

#line 1441
            us_0 = _S362;

#line 1441
        }
        else
        {

#line 1441
            us_0 = 1.0f;

#line 1441
        }
        if(vv_0 < ((&surf_3)->coatP_0))
        {
            float3 h_10 = sampleVndf_0(woL_6, (&surf_3)->coatAlpha_0, u1_3, u2_3);
            float woh_0 = dot(woL_6, h_10);
            float3 wiL_9 = float3((2.0f * woh_0))  * h_10 - woL_6;
            float _S363 = wiL_9.z;
            float3 _S364 = float3((fresnelDielectric_0(woh_0, 1.5f) / coatF_0 * G1_0(max(_S363, 0.0f), (&surf_3)->coatAlpha_0))) ;

#line 1448
            ok_0 = _S363 > 0.0f;

#line 1448
            lobeCls_0 = 1U;

#line 1448
            refracted_0 = false;

#line 1448
            wi_6 = wiL_9;

#line 1448
            li_0 = _S364;

#line 1442
        }
        else
        {

#line 1450
            if(us_0 < ((&surf_3)->sheenP_0))
            {

                float3 wiL_10 = cosineLocal_0(u1_3, u2_3);

                float _S365 = wiL_10.z;

#line 1455
                float3 _S366 = (&surf_3)->sheenColor_0 * float3(sheenCore_0(_S287, _S365, normalize(woL_6 + wiL_10).z, (&surf_3)->sheenAlpha_0))  * float3(3.1415927410125732f)  / float3((_S365 * (&surf_3)->sheenP_0)) ;

#line 1455
                ok_0 = true;

#line 1455
                lobeCls_0 = 1U;

#line 1455
                refracted_0 = false;

#line 1455
                wi_6 = wiL_10;

#line 1455
                li_0 = _S366;

#line 1450
            }
            else
            {

#line 1457
                if(lobe_0 < metallic_1)
                {
                    float3 h_11 = sampleVndf_0(woL_6, _S286, u1_3, u2_3);
                    float woh_1 = dot(woL_6, h_11);
                    float3 wiL_11 = float3((2.0f * woh_1))  * h_11 - woL_6;
                    float _S367 = wiL_11.z;

#line 1462
                    bool _S368 = _S367 > 0.0f;
                    float3 _S369 = schlick_0(albedo_2, woh_1);

#line 1463
                    thread Surface_0 _S370 = surf_3;

#line 1463
                    float3 _S371 = multiscatterFactor_0(&_S370, _S287, kernelContext_34);

#line 1463
                    float3 _S372 = _S369 * _S371 * float3(G1_0(max(_S367, 0.0f), _S286)) ;

#line 1463
                    ok_0 = _S368;

#line 1463
                    lobeCls_0 = 1U;

#line 1463
                    refracted_0 = false;

#line 1463
                    wi_6 = wiL_11;

#line 1463
                    li_0 = _S372;

#line 1457
                }
                else
                {

#line 1465
                    if(lobe_0 < (metallic_1 + (1.0f - metallic_1) * transmission_2))
                    {
                        float3 h_12 = sampleVndf_0(woL_6, _S286, u1_3, u2_3);
                        float woh_2 = dot(woL_6, h_12);
                        if(u3_1 < (fresnelDielectric_0(woh_2, eta_2)))
                        {
                            float3 wiL_12 = float3((2.0f * woh_2))  * h_12 - woL_6;
                            float _S373 = wiL_12.z;
                            float3 _S374 = float3((G1_0(max(_S373, 0.0f), _S286) * (&surf_3)->tComp_0)) ;

#line 1473
                            ok_0 = _S373 > 0.0f;

#line 1473
                            lobeCls_0 = 1U;

#line 1473
                            refracted_0 = false;

#line 1473
                            wi_6 = wiL_12;

#line 1473
                            li_0 = _S374;

#line 1469
                        }
                        else
                        {

#line 1477
                            float r_7 = 1.0f / eta_2;
                            float k_5 = 1.0f - r_7 * r_7 * (1.0f - woh_2 * woh_2);

#line 1478
                            float3 _S375 = float3(r_7) ;
                            float3 wiL_13 = - woL_6 * _S375 + float3((r_7 * woh_2 - sqrt(max(k_5, 0.0f))))  * h_12;
                            float _S376 = wiL_13.z;

#line 1480
                            if(_S376 < 0.0f)
                            {

#line 1480
                                ok_0 = k_5 > 0.0f;

#line 1480
                            }
                            else
                            {

#line 1480
                                ok_0 = false;

#line 1480
                            }



                            float3 _S377 = albedo_2 * float3(G1_0(max(- _S376, 0.0f), _S286))  * _S375 * _S375 * float3((&surf_3)->tComp_0) ;

#line 1484
                            lobeCls_0 = 2U;

#line 1484
                            refracted_0 = true;

#line 1484
                            wi_6 = wiL_13;

#line 1484
                            li_0 = _S377;

#line 1469
                        }

#line 1465
                    }
                    else
                    {

#line 1487
                        if(u3_1 < fSel_1)
                        {
                            float3 h_13 = sampleVndf_0(woL_6, _S286, u1_3, u2_3);
                            float woh_3 = dot(woL_6, h_13);
                            float3 wiL_14 = float3((2.0f * woh_3))  * h_13 - woL_6;
                            float _S378 = wiL_14.z;
                            float3 _S379 = float3((fresnelDielectric_0(woh_3, wB_0) / fSel_1 * G1_0(max(_S378, 0.0f), _S286))) ;

#line 1493
                            ok_0 = _S378 > 0.0f;

#line 1493
                            lobeCls_0 = 1U;

#line 1493
                            wi_6 = wiL_14;

#line 1493
                            li_0 = _S379;

#line 1487
                        }
                        else
                        {

#line 1497
                            float3 _S380 = cosineLocal_0(u1_3, u2_3);

#line 1497
                            ok_0 = true;

#line 1497
                            lobeCls_0 = 0U;

#line 1497
                            wi_6 = _S380;

#line 1497
                            li_0 = albedo_2;

#line 1487
                        }

#line 1487
                        refracted_0 = false;

#line 1465
                    }

#line 1457
                }

#line 1450
            }

#line 1442
        }

#line 1501
        if(!ok_0)
        {

#line 1501
            alive_0 = false;

#line 1501
            thr_1 = thr_2;
            break;
        }

#line 1503
        if(depth_3 == 0U)
        {

#line 1503
            cls_5 = lobeCls_0;

#line 1503
        }
        else
        {

#line 1503
            cls_5 = cls_4;

#line 1503
        }

        st_1->misPrev_0 = !refracted_0;
        if(refracted_0)
        {

#line 1506
            _S211 = 0.0f;

#line 1506
        }
        else
        {

#line 1506
            thread Surface_0 _S381 = surf_3;

#line 1506
            float _S382 = reflectivePdf_0(&_S381, woL_6, wi_6);

#line 1506
            _S211 = _S382;

#line 1506
        }

#line 1506
        st_1->qPrev_0 = _S211;
        st_1->prevInst_0 = _S225 + 1U;

        float3 dir_3 = normalize(float3(wi_6.x)  * T_2 + float3(wi_6.y)  * B_2 + float3(wi_6.z)  * n_8);

        float side_0 = dot(dir_3, ng_0);
        if(refracted_0)
        {

#line 1512
            track_0 = side_0 >= 0.0f;

#line 1512
        }
        else
        {

#line 1512
            track_0 = side_0 <= 0.0f;

#line 1512
        }

#line 1512
        if(track_0)
        {

#line 1512
            dir_2 = dir_3;

#line 1512
            cls_4 = cls_5;

#line 1512
            alive_0 = false;

#line 1512
            thr_1 = thr_2;
            break;
        }

#line 1514
        if(side_0 > 0.0f)
        {

#line 1514
            _S212 = 9.9999997473787516e-05f;

#line 1514
        }
        else
        {

#line 1514
            _S212 = -9.9999997473787516e-05f;

#line 1514
        }

#line 1514
        float3 _S383 = hit_1 + ng_0 * float3(_S212) ;
        float3 thr_4 = thr_2 * li_0;

        if(depth_3 >= 2U)
        {
            float pr_0 = clamp(max(thr_4.x, max(thr_4.y, thr_4.z)), 0.05000000074505806f, 0.94999998807907104f);
            float _S384 = Rng_next_0(&rng_4);

#line 1520
            if(_S384 > pr_0)
            {

#line 1520
                org_2 = _S383;

#line 1520
                dir_2 = dir_3;

#line 1520
                cls_4 = cls_5;

#line 1520
                alive_0 = false;

#line 1520
                thr_1 = thr_4;
                break;
            }

#line 1521
            thr_1 = thr_4 / float3(pr_0) ;

#line 1517
        }
        else
        {

#line 1517
            thr_1 = thr_4;

#line 1517
        }

#line 1009
        uint _S385 = once_0 + 1U;

#line 1009
        cls_4 = cls_5;

#line 1009
        dir_2 = dir_3;

#line 1009
        org_2 = _S383;

#line 1009
        chan_2 = chan_1;

#line 1009
        once_0 = _S385;

#line 1009
    }

#line 1525
    st_1->rng_0 = (&rng_4)->state_0;
    st_1->org_0 = org_2;
    st_1->dir_0 = dir_2;
    st_1->thr_0 = thr_1;
    st_1->cls_0 = cls_4;
    st_1->chan_0 = chan_1;
    if(depth_3 == 0U)
    {

#line 1531
        _S210 = st_1->gi_0;

#line 1531
    }
    else
    {

#line 1531
        _S210 = false;

#line 1531
    }

#line 1531
    if(_S210)
    {

        uint so_1 = restirScratch_0(pixel_7);

#line 1534
        k_4 = 0U;
        for(;;)
        {

#line 1535
            if(k_4 < 3U)
            {
            }
            else
            {

#line 1535
                break;
            }
            *(kernelContext_34->restir_0+(so_1 + 15U + k_4)) = thr_1[k_4];
            *(kernelContext_34->restir_0+(so_1 + 18U + k_4)) = (&st_1->parts_0)->total_0[k_4];

#line 1535
            k_4 = k_4 + 1U;

#line 1535
        }

#line 1540
        *(kernelContext_34->restir_0+(so_1 + 21U)) = st_1->qPrev_0;

#line 1531
    }

#line 1542
    return alive_0;
}


#line 1566
float3 giFinish_0(float3 pathTotal_0, uint pixel_8, KernelContext_0 thread* kernelContext_35)
{
    uint co_3 = restirBase_0(pixel_8, kernelContext_35->params_0[int(6)] & 1U);
    uint so_2 = restirScratch_0(pixel_8);
    float wsum_5 = *(kernelContext_35->restir_0+so_2);
    float m_1 = *(kernelContext_35->restir_0+(so_2 + 1U)) + 1.0f;
    float _S386 = *(kernelContext_35->restir_0+(so_2 + 2U));
    float3 _S387 = float3(*(kernelContext_35->restir_0+(so_2 + 3U)), *(kernelContext_35->restir_0+(so_2 + 4U)), *(kernelContext_35->restir_0+(so_2 + 5U)));
    float3 _S388 = float3(*(kernelContext_35->restir_0+(so_2 + 6U)), *(kernelContext_35->restir_0+(so_2 + 7U)), *(kernelContext_35->restir_0+(so_2 + 8U)));
    float3 _S389 = float3(*(kernelContext_35->restir_0+(so_2 + 9U)), *(kernelContext_35->restir_0+(so_2 + 10U)), *(kernelContext_35->restir_0+(so_2 + 11U)));
    float3 _S390 = float3(*(kernelContext_35->restir_0+(so_2 + 12U)), *(kernelContext_35->restir_0+(so_2 + 13U)), *(kernelContext_35->restir_0+(so_2 + 14U)));
    float _S391 = *(kernelContext_35->restir_0+(so_2 + 15U));

#line 1577
    float _S392 = *(kernelContext_35->restir_0+(so_2 + 16U));

#line 1577
    float _S393 = *(kernelContext_35->restir_0+(so_2 + 17U));
    float3 d0_0 = float3(*(kernelContext_35->restir_0+(so_2 + 18U)), *(kernelContext_35->restir_0+(so_2 + 19U)), *(kernelContext_35->restir_0+(so_2 + 20U)));
    float qPrev_1 = *(kernelContext_35->restir_0+(so_2 + 21U));

#line 1579
    bool own_0;
    if((as_type<uint>((*(kernelContext_35->restir_0+(so_2 + 22U))))) != 0U)
    {

#line 1580
        own_0 = qPrev_1 > 0.0f;

#line 1580
    }
    else
    {

#line 1580
        own_0 = false;

#line 1580
    }
    float3 giTotal_0 = pathTotal_0 - d0_0;

#line 1581
    float pSel_2;

#line 1581
    float wsum_6;

#line 1581
    float W_1;

#line 1581
    float3 cSel_2;

#line 1581
    float3 xSel_2;

#line 1581
    float3 nSel_2;

#line 1581
    float3 lSel_2;

#line 1581
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
            (&r_8)->state_0 = pcg_0(pixel_8 ^ (pcg_0(kernelContext_35->params_0[int(6)] * 2246822507U + 4660U)));
            float _S394 = Rng_next_0(&r_8);

#line 1593
            if((_S394 * wsum_7) < wOwn_0)
            {


                float3 _S395 = float3(*(kernelContext_35->restir_0+(co_3 + 16U)), *(kernelContext_35->restir_0+(co_3 + 17U)), *(kernelContext_35->restir_0+(co_3 + 18U)));
                float3 _S396 = float3(*(kernelContext_35->restir_0+(co_3 + 19U)), *(kernelContext_35->restir_0+(co_3 + 20U)), *(kernelContext_35->restir_0+(co_3 + 21U)));
                if(_S391 > 9.99999997475242708e-07f)
                {

#line 1599
                    pSel_2 = giTotal_0.x / _S391;

#line 1599
                }
                else
                {

#line 1599
                    pSel_2 = 0.0f;

#line 1599
                }

#line 1599
                if(_S392 > 9.99999997475242708e-07f)
                {

#line 1599
                    wsum_6 = giTotal_0.y / _S392;

#line 1599
                }
                else
                {

#line 1599
                    wsum_6 = 0.0f;

#line 1599
                }

#line 1599
                if(_S393 > 9.99999997475242708e-07f)
                {

#line 1599
                    W_1 = giTotal_0.z / _S393;

#line 1599
                }
                else
                {

#line 1599
                    W_1 = 0.0f;

#line 1599
                }

#line 1599
                float3 _S397 = float3(pSel_2, wsum_6, W_1);

#line 1599
                pSel_2 = pOwn_0;

#line 1599
                cSel_2 = cOwn_0;

#line 1599
                xSel_2 = _S395;

#line 1599
                nSel_2 = _S396;

#line 1599
                lSel_2 = _S397;

#line 1593
            }
            else
            {

#line 1593
                pSel_2 = _S386;

#line 1593
                cSel_2 = _S387;

#line 1593
                xSel_2 = _S388;

#line 1593
                nSel_2 = _S389;

#line 1593
                lSel_2 = _S390;

#line 1593
            }

#line 1593
            wsum_6 = wsum_7;

#line 1587
        }
        else
        {

#line 1587
            pSel_2 = _S386;

#line 1587
            cSel_2 = _S387;

#line 1587
            xSel_2 = _S388;

#line 1587
            nSel_2 = _S389;

#line 1587
            lSel_2 = _S390;

#line 1587
            wsum_6 = wsum_5;

#line 1587
        }

#line 1587
        result_0 = d0_0;

#line 1583
    }
    else
    {

#line 1604
        float3 result_1 = d0_0 + giTotal_0;

#line 1604
        pSel_2 = _S386;

#line 1604
        cSel_2 = _S387;

#line 1604
        xSel_2 = _S388;

#line 1604
        nSel_2 = _S389;

#line 1604
        lSel_2 = _S390;

#line 1604
        wsum_6 = wsum_5;

#line 1604
        result_0 = result_1;

#line 1583
    }

#line 1605
    bool _S398 = pSel_2 > 0.0f;

#line 1605
    if(_S398)
    {

#line 1605
        W_1 = wsum_6 / (m_1 * pSel_2);

#line 1605
    }
    else
    {

#line 1605
        W_1 = 0.0f;

#line 1605
    }
    float3 result_2 = result_0 + cSel_2 * float3(W_1) ;

#line 1606
    uint k_6 = 0U;
    for(;;)
    {

#line 1607
        if(k_6 < 3U)
        {
        }
        else
        {

#line 1607
            break;
        }
        *(kernelContext_35->restir_0+(co_3 + 16U + k_6)) = xSel_2[k_6];
        *(kernelContext_35->restir_0+(co_3 + 19U + k_6)) = nSel_2[k_6];
        *(kernelContext_35->restir_0+(co_3 + 22U + k_6)) = lSel_2[k_6];

#line 1607
        k_6 = k_6 + 1U;

#line 1607
    }

#line 1613
    *(kernelContext_35->restir_0+(co_3 + 25U)) = W_1;
    *(kernelContext_35->restir_0+(co_3 + 26U)) = m_1;
    float device* _S399 = kernelContext_35->restir_0+(co_3 + 27U);

#line 1615
    if(_S398)
    {

#line 1615
        k_6 = 1U;

#line 1615
    }
    else
    {

#line 1615
        k_6 = 0U;

#line 1615
    }

#line 1615
    *_S399 = (as_type<float>((k_6)));
    return result_2;
}


void finishPath_0(const PathState_0 thread* st_2, uint pixel_9, KernelContext_0 thread* kernelContext_36)
{

#line 1620
    Parts_0 _S400 = st_2->parts_0;

#line 1620
    float _S401 = st_2->visLit_0;

#line 1620
    float _S402 = st_2->visTotal_0;

#line 1620
    float3 _S403 = (&st_2->parts_0)->total_0;

#line 1620
    float3 radiance_0;

#line 1626
    if(st_2->gi_0)
    {


        if((st_2->chan_0) >= int(0))
        {

#line 1631
            *(kernelContext_36->restir_0+(restirScratch_0(pixel_9) + 22U)) = (as_type<float>((0U)));

#line 1630
        }

#line 1630
        float3 _S404 = giFinish_0(_S403, pixel_9, kernelContext_36);

#line 1630
        radiance_0 = _S404;

#line 1626
    }
    else
    {

#line 1626
        radiance_0 = _S403;

#line 1626
    }

#line 1626
    bool _S405;

#line 1634
    if(any(isnan(radiance_0)))
    {

#line 1634
        _S405 = true;

#line 1634
    }
    else
    {

#line 1634
        _S405 = any(isinf(radiance_0));

#line 1634
    }

#line 1634
    Parts_0 parts_1;

#line 1634
    float visLit_1;

#line 1634
    float visTotal_1;

#line 1634
    if(_S405)
    {
        float3 _S406 = float3(0.0f) ;

#line 1636
        radiance_0 = _S406;

#line 1636
        (&parts_1)->total_0 = _S406;

#line 1636
        (&parts_1)->directDiffuse_0 = _S406;

#line 1636
        (&parts_1)->indirectDiffuse_0 = _S406;

#line 1636
        (&parts_1)->specular_0 = _S406;

#line 1636
        (&parts_1)->transmission_0 = _S406;

#line 1636
        (&parts_1)->emission_0 = _S406;

#line 1636
        visLit_1 = 0.0f;

#line 1636
        visTotal_1 = 0.0f;

#line 1634
    }
    else
    {

#line 1634
        parts_1 = _S400;

#line 1634
        visLit_1 = _S401;

#line 1634
        visTotal_1 = _S402;

#line 1634
    }

#line 1642
    uint o_8 = 3U * pixel_9;
    float device* _S407 = kernelContext_36->accum_0+o_8;

#line 1643
    *_S407 = *_S407 + radiance_0.x;
    uint _S408 = o_8 + 1U;

#line 1644
    float device* _S409 = kernelContext_36->accum_0+_S408;

#line 1644
    *_S409 = *_S409 + radiance_0.y;
    uint _S410 = o_8 + 2U;

#line 1645
    float device* _S411 = kernelContext_36->accum_0+_S410;

#line 1645
    *_S411 = *_S411 + radiance_0.z;
    if(kernelContext_36->params_0[int(32)] != 0U)
    {
        float l_1 = lum_0(radiance_0);
        float device* _S412 = kernelContext_36->pixelStats_0+o_8;

#line 1649
        *_S412 = *_S412 + 1.0f;
        float device* _S413 = kernelContext_36->pixelStats_0+_S408;

#line 1650
        *_S413 = *_S413 + l_1;
        float device* _S414 = kernelContext_36->pixelStats_0+_S410;

#line 1651
        *_S414 = *_S414 + l_1 * l_1;

#line 1646
    }

#line 1654
    if(kernelContext_36->params_0[int(28)] != 0U)
    {
        uint lo_3 = 65U * pixel_9;
        array<float3, int(5)> _S415 = { { parts_1.directDiffuse_0, parts_1.indirectDiffuse_0, parts_1.specular_0, parts_1.transmission_0, parts_1.emission_0 } };

#line 1657
        uint k_7 = 0U;
        for(;;)
        {

#line 1658
            if(k_7 < 5U)
            {
            }
            else
            {

#line 1658
                break;
            }
            uint _S416 = lo_3 + 3U * k_7;

#line 1660
            float device* _S417 = kernelContext_36->lighting_0+_S416;

#line 1660
            *_S417 = *_S417 + _S415[k_7].x;
            float device* _S418 = kernelContext_36->lighting_0+(_S416 + 1U);

#line 1661
            *_S418 = *_S418 + _S415[k_7].y;
            float device* _S419 = kernelContext_36->lighting_0+(_S416 + 2U);

#line 1662
            *_S419 = *_S419 + _S415[k_7].z;

#line 1658
            k_7 = k_7 + 1U;

#line 1658
        }

#line 1664
        float device* _S420 = kernelContext_36->lighting_0+(lo_3 + 15U);

#line 1664
        *_S420 = *_S420 + visLit_1;
        float device* _S421 = kernelContext_36->lighting_0+(lo_3 + 16U);

#line 1665
        *_S421 = *_S421 + visTotal_1;

#line 1654
    }

#line 1667
    return;
}


#line 9 "shaders/pathtrace.slang"
[[kernel]] void pathtrace(uint3 tid_0 [[thread_position_in_grid]], uint device* params_1 [[buffer(6)]], float device* pixelStats_1 [[buffer(18)]], metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_1 [[buffer(0)]], float device* restir_2 [[buffer(19)]], float device* envPixels_1 [[buffer(10)]], uint device* instances_1 [[buffer(3)]], uint device* indices_1 [[buffer(2)]], float device* positions_1 [[buffer(1)]], float device* materials_1 [[buffer(4)]], float device* uvs_1 [[buffer(13)]], uint device* texInfo_1 [[buffer(15)]], float device* texels_1 [[buffer(14)]], float device* vnormals_1 [[buffer(16)]], uint device* lights_1 [[buffer(5)]], float device* emitters_1 [[buffer(8)]], float device* lighting_1 [[buffer(17)]], float device* emitCdf_1 [[buffer(9)]], float device* envMarginal_1 [[buffer(11)]], float device* envCond_1 [[buffer(12)]], float device* accum_1 [[buffer(7)]])
{

#line 9
    thread KernelContext_0 kernelContext_37;

#line 9
    (&kernelContext_37)->params_0 = params_1;

#line 9
    (&kernelContext_37)->pixelStats_0 = pixelStats_1;

#line 9
    (&kernelContext_37)->scene_0 = scene_1;

#line 9
    (&kernelContext_37)->restir_0 = restir_2;

#line 9
    (&kernelContext_37)->envPixels_0 = envPixels_1;

#line 9
    (&kernelContext_37)->instances_0 = instances_1;

#line 9
    (&kernelContext_37)->indices_0 = indices_1;

#line 9
    (&kernelContext_37)->positions_0 = positions_1;

#line 9
    (&kernelContext_37)->materials_0 = materials_1;

#line 9
    (&kernelContext_37)->uvs_0 = uvs_1;

#line 9
    (&kernelContext_37)->texInfo_0 = texInfo_1;

#line 9
    (&kernelContext_37)->texels_0 = texels_1;

#line 9
    (&kernelContext_37)->vnormals_0 = vnormals_1;

#line 9
    (&kernelContext_37)->lights_0 = lights_1;

#line 9
    (&kernelContext_37)->emitters_0 = emitters_1;

#line 9
    (&kernelContext_37)->lighting_0 = lighting_1;

#line 9
    (&kernelContext_37)->emitCdf_0 = emitCdf_1;

#line 9
    (&kernelContext_37)->envMarginal_0 = envMarginal_1;

#line 9
    (&kernelContext_37)->envCond_0 = envCond_1;

#line 9
    (&kernelContext_37)->accum_0 = accum_1;

    uint _S422 = tid_0.x;

#line 11
    bool _S423;

#line 11
    if(_S422 >= params_1[int(0)])
    {

#line 11
        _S423 = true;

#line 11
    }
    else
    {

#line 11
        _S423 = (tid_0.y) >= ((&kernelContext_37)->params_0)[int(1)];

#line 11
    }

#line 11
    if(_S423)
    {

#line 12
        return;
    }

#line 13
    uint _S424 = tid_0.y;

#line 13
    uint _S425 = _S424 * (&kernelContext_37)->params_0[int(0)] + _S422;

#line 13
    uint k_8 = 0U;
    for(;;)
    {

#line 14
        if(k_8 < ((&kernelContext_37)->params_0)[int(35)])
        {
        }
        else
        {

#line 14
            break;
        }
        if((&kernelContext_37)->params_0[int(32)] != 0U)
        {

#line 16
            bool _S426 = pixelActive_0(_S425, &kernelContext_37);

#line 16
            _S423 = !_S426;

#line 16
        }
        else
        {

#line 16
            _S423 = false;

#line 16
        }

#line 16
        if(_S423)
        {

#line 17
            return;
        }

#line 17
        PathState_0 _S427 = generatePathFor_0(_S422, _S424, (&kernelContext_37)->params_0[int(6)] + k_8, &kernelContext_37);
        thread PathState_0 st_3 = _S427;

#line 18
        uint depth_4 = 0U;
        for(;;)
        {

#line 19
            if(depth_4 < ((&kernelContext_37)->params_0)[int(7)])
            {
            }
            else
            {

#line 19
                break;
            }

#line 19
            Hit_0 _S428 = traceClosest_0((&st_3)->org_0, (&st_3)->dir_0, &kernelContext_37);

#line 19
            thread Hit_0 _S429 = _S428;

#line 19
            bool _S430 = shadePath_0(&st_3, &_S429, depth_4, _S425, &kernelContext_37);

            if(!_S430)
            {

#line 22
                break;
            }

#line 19
            depth_4 = depth_4 + 1U;

#line 19
        }

#line 19
        thread PathState_0 _S431 = st_3;

#line 19
        finishPath_0(&_S431, _S425, &kernelContext_37);

#line 14
        k_8 = k_8 + 1U;

#line 14
    }

#line 26
    return;
}

