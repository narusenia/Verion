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
            

#line 22 "shaders/pathtrace.slang"
uint pcg_0(uint v_0)
{
    uint s_0 = v_0 * 747796405U + 2891336453U;
    uint w_0 = ((s_0 >> ((s_0 >> 28U) + 4U)) ^ s_0) * 277803737U;
    return (w_0 >> 22U) ^ w_0;
}


#line 529
struct KernelContext_0
{
    uint device* params_0;
    metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_0;
    float device* envPixels_0;
    uint device* instances_0;
    uint device* indices_0;
    float device* positions_0;
    float device* materials_0;
    float device* emitters_0;
    uint device* lights_0;
    float device* emitCdf_0;
    float device* envMarginal_0;
    float device* envCond_0;
    float device* accum_0;
};


#line 39
float pf_0(uint i_0, KernelContext_0 thread* kernelContext_0)
{

#line 39
    return (as_type<float>((kernelContext_0->params_0[i_0])));
}


#line 29
struct Rng_0
{
    uint state_0;
};


#line 32
float Rng_next_0(Rng_0 thread* this_0)
{
    uint _S1 = pcg_0(this_0->state_0);

#line 34
    this_0->state_0 = _S1;
    return float(_S1 >> 8U) * 5.9604644775390625e-08f;
}


#line 129
void envCoords_0(float3 d_0, uint thread* i_1, uint thread* j_0, KernelContext_0 thread* kernelContext_1)
{
    uint w_1 = kernelContext_1->params_0[int(24)];
    uint h_0 = kernelContext_1->params_0[int(25)];

    float v_1 = acos(clamp(d_0.y, -1.0f, 1.0f)) / 3.1415927410125732f;
    *i_1 = min(uint((atan2(d_0.x, - d_0.z) * 0.15915493667125702f + 0.5f) * float(w_1)), w_1 - 1U);
    *j_0 = min(uint(v_1 * float(h_0)), h_0 - 1U);
    return;
}


#line 122
float3 envTexel_0(uint i_2, uint j_1, KernelContext_0 thread* kernelContext_2)
{
    uint o_0 = 3U * (j_1 * kernelContext_2->params_0[int(24)] + i_2);
    return float3(kernelContext_2->envPixels_0[o_0], kernelContext_2->envPixels_0[o_0 + 1U], kernelContext_2->envPixels_0[o_0 + 2U]);
}


#line 120
float lum_0(float3 c_0)
{

#line 120
    return dot(c_0, float3(0.2125999927520752f, 0.71520000696182251f, 0.072200000286102295f));
}


#line 148
float envPdf_0(float3 d_1, KernelContext_0 thread* kernelContext_3)
{
    thread uint i_3;

#line 150
    thread uint j_2;

#line 150
    envCoords_0(d_1, &i_3, &j_2, kernelContext_3);

#line 150
    float3 _S2 = envTexel_0(i_3, j_2, kernelContext_3);

    float _S3 = lum_0(_S2);

#line 152
    float _S4 = pf_0(26U, kernelContext_3);

#line 152
    return _S3 * _S4;
}


#line 139
float3 envRadiance_0(float3 d_2, KernelContext_0 thread* kernelContext_4)
{
    thread uint i_4;

#line 141
    thread uint j_3;

#line 141
    envCoords_0(d_2, &i_4, &j_3, kernelContext_4);

#line 141
    float3 _S5 = envTexel_0(i_4, j_3, kernelContext_4);

    return _S5;
}


#line 41
float3 vertexPos_0(uint v_2, KernelContext_0 thread* kernelContext_5)
{

#line 41
    uint _S6 = 3U * v_2;

#line 41
    return float3(kernelContext_5->positions_0[_S6], kernelContext_5->positions_0[_S6 + 1U], kernelContext_5->positions_0[_S6 + 2U]);
}


#line 43
float3 transformPoint_0(uint base_0, float3 p_0, KernelContext_0 thread* kernelContext_6)
{
    thread float3 r_0;

#line 45
    uint row_0 = 0U;
    for(;;)
    {

#line 46
        if(row_0 < 3U)
        {
        }
        else
        {

#line 46
            break;
        }
        uint o_1 = base_0 + 4U * row_0;
        r_0[row_0] = (as_type<float>((kernelContext_6->instances_0[o_1]))) * p_0.x + (as_type<float>((kernelContext_6->instances_0[o_1 + 1U]))) * p_0.y + (as_type<float>((kernelContext_6->instances_0[o_1 + 2U]))) * p_0.z + (as_type<float>((kernelContext_6->instances_0[o_1 + 3U])));

#line 46
        row_0 = row_0 + 1U;

#line 46
    }

#line 51
    return r_0;
}


#line 94
void basis_0(float3 n_0, float3 thread* t_0, float3 thread* b_0)
{

#line 94
    float3 a_0;

    if((abs(n_0.x)) > 0.89999997615814209f)
    {

#line 96
        a_0 = float3(0.0f, 1.0f, 0.0f);

#line 96
    }
    else
    {

#line 96
        a_0 = float3(1.0f, 0.0f, 0.0f);

#line 96
    }
    float3 _S7 = normalize(cross(n_0, a_0));

#line 97
    *b_0 = _S7;
    *t_0 = cross(_S7, n_0);
    return;
}


#line 83
float fresnelDielectric_0(float cosi_0, float eta_0)
{
    float s2_0 = (1.0f - cosi_0 * cosi_0) / (eta_0 * eta_0);
    if(s2_0 >= 1.0f)
    {

#line 87
        return 1.0f;
    }

#line 88
    float cost_0 = sqrt(1.0f - s2_0);
    float _S8 = eta_0 * cost_0;

#line 89
    float rs_0 = (cosi_0 - _S8) / (cosi_0 + _S8);
    float _S9 = eta_0 * cosi_0;

#line 90
    float rp_0 = (_S9 - cost_0) / (_S9 + cost_0);
    return 0.5f * (rs_0 * rs_0 + rp_0 * rp_0);
}


#line 20995 "hlsl.meta.slang"
struct RayDesc_0
{
    float3 Origin_0;
    float TMin_0;
    float3 Direction_0;
    float TMax_0;
};


#line 226 "shaders/pathtrace.slang"
bool occluded_0(float3 o_2, float3 d_3, float tmax_0, KernelContext_0 thread* kernelContext_7)
{
    thread RayDesc_0 ray_0;
    (&ray_0)->Origin_0 = o_2;
    (&ray_0)->Direction_0 = d_3;
    (&ray_0)->TMin_0 = 0.0f;
    (&ray_0)->TMax_0 = tmax_0;
    thread raytracing::intersection_query<raytracing::triangle_data, raytracing::instancing> q_0;
    (&q_0)->reset({ (ray_0.Origin_0), (ray_0.Direction_0), (ray_0.TMin_0), (ray_0.TMax_0) }, (kernelContext_7->scene_0), (255U), _slang_ray_flags_to_intersection_params((5U)));
    for(;;)
    {

#line 235
        bool _S10 = ((&q_0)->next());

#line 235
        if(_S10)
        {
        }
        else
        {

#line 235
            break;
        }

#line 235
    }
    uint _S11 = (_slang_committed_intersection_type_to_uint((&q_0)->get_committed_intersection_type()));

#line 236
    return _S11 == 1U;
}


#line 68
float D_0(float hz_0, float alpha_0)
{
    float a2_0 = alpha_0 * alpha_0;
    float d_4 = hz_0 * hz_0 * (a2_0 - 1.0f) + 1.0f;
    return a2_0 / (3.1415927410125732f * d_4 * d_4);
}


#line 61
float G1_0(float cosT_0, float alpha_1)
{
    float c2_0 = cosT_0 * cosT_0;

    return 2.0f / (1.0f + sqrt(1.0f + alpha_1 * alpha_1 * ((1.0f - c2_0) / max(c2_0, 9.99999993922529029e-09f))));
}


#line 75
float3 schlick_0(float3 f0_0, float c_1)
{
    float m_0 = 1.0f - saturate(c_1);
    float m2_0 = m_0 * m_0;
    return f0_0 + (float3(1.0f)  - f0_0) * float3((m2_0 * m2_0 * m_0)) ;
}


#line 189
struct Surface_0
{
    float3 albedo_0;
    float metallic_0;
    float alpha_2;
    float transmission_0;
    float ior_0;
    float eta_1;
    float fSel_0;
};


float3 evalReflective_0(const Surface_0 thread* s_1, float3 woL_0, float3 wiL_0)
{
    float3 hh_0 = normalize(woL_0 + wiL_0);
    float _S12 = max(dot(woL_0, hh_0), 0.0f);

    float _S13 = woL_0.z;

#line 206
    float _S14 = wiL_0.z;

#line 206
    float core_0 = D_0(hh_0.z, s_1->alpha_2) * G1_0(_S13, s_1->alpha_2) * G1_0(_S14, s_1->alpha_2) / (4.0f * _S13);


    float _S15 = 1.0f - s_1->metallic_0;

#line 209
    float _S16 = 1.0f - s_1->transmission_0;

#line 208
    return float3(s_1->metallic_0)  * schlick_0(s_1->albedo_0, _S12) * float3(core_0)  + float3((_S15 * (s_1->transmission_0 * fresnelDielectric_0(_S12, s_1->eta_1) + _S16 * fresnelDielectric_0(_S12, s_1->ior_0)) * core_0))  + float3((_S15 * _S16 * (1.0f - s_1->fSel_0)))  * s_1->albedo_0 * float3((_S14 / 3.1415927410125732f)) ;
}


#line 215
float reflectivePdf_0(const Surface_0 thread* s_2, float3 woL_1, float3 wiL_1)
{
    float3 hh_1 = normalize(woL_1 + wiL_1);

    float _S17 = woL_1.z;

    float _S18 = 1.0f - s_2->metallic_0;

#line 221
    float _S19 = 1.0f - s_2->transmission_0;

    return (s_2->metallic_0 + _S18 * (s_2->transmission_0 * fresnelDielectric_0(max(dot(woL_1, hh_1), 0.0f), s_2->eta_1) + _S19 * s_2->fSel_0)) * (G1_0(_S17, s_2->alpha_2) * D_0(hh_1.z, s_2->alpha_2) / (4.0f * _S17)) + _S18 * _S19 * (1.0f - s_2->fSel_0) * wiL_1.z / 3.1415927410125732f;
}


#line 155
float3 envSample_0(float u1_0, float u2_0, float u3_0, float u4_0, float thread* pdf_0, float3 thread* le_0, KernelContext_0 thread* kernelContext_8)
{

#line 155
    uint lo_0;

    uint w_2 = kernelContext_8->params_0[int(24)];
    uint h_1 = kernelContext_8->params_0[int(25)];

    uint _S20 = h_1 - 1U;

#line 160
    uint lo_1 = 0U;

#line 160
    uint hi_0 = _S20;
    for(;;)
    {

#line 161
        if(lo_1 < hi_0)
        {
        }
        else
        {

#line 161
            break;
        }
        uint mid_0 = (lo_1 + hi_0) / 2U;
        if(kernelContext_8->envMarginal_0[mid_0] >= u1_0)
        {

#line 164
            lo_0 = lo_1;

#line 164
            hi_0 = mid_0;

#line 164
        }
        else
        {

#line 164
            lo_0 = mid_0 + 1U;

#line 164
        }

#line 164
        lo_1 = lo_0;

#line 161
    }

#line 171
    uint _S21 = w_2 - 1U;

#line 171
    lo_0 = 0U;

#line 171
    hi_0 = _S21;
    for(;;)
    {

#line 172
        if(lo_0 < hi_0)
        {
        }
        else
        {

#line 172
            break;
        }
        uint mid_1 = (lo_0 + hi_0) / 2U;
        if(kernelContext_8->envCond_0[lo_1 * w_2 + mid_1] >= u2_0)
        {

#line 175
            hi_0 = mid_1;

#line 175
        }
        else
        {

#line 175
            lo_0 = mid_1 + 1U;

#line 175
        }

#line 172
    }

#line 181
    float phi_0 = ((float(lo_0) + u3_0) / float(w_2) - 0.5f) * 2.0f * 3.1415927410125732f;
    float theta_0 = (float(lo_1) + u4_0) / float(h_1) * 3.1415927410125732f;
    float st_0 = sin(theta_0);

#line 183
    float3 _S22 = envTexel_0(lo_0, lo_1, kernelContext_8);
    *le_0 = _S22;
    float _S23 = lum_0(_S22);

#line 185
    float _S24 = pf_0(26U, kernelContext_8);

#line 185
    *pdf_0 = _S23 * _S24;
    return float3(st_0 * sin(phi_0), cos(theta_0), - st_0 * cos(phi_0));
}


#line 102
float3 sampleVndf_0(float3 wo_0, float alpha_3, float u1_1, float u2_1)
{
    float3 vh_0 = normalize(float3(alpha_3 * wo_0.x, alpha_3 * wo_0.y, wo_0.z));
    float _S25 = vh_0.x;

#line 105
    float _S26 = vh_0.y;

#line 105
    float lensq_0 = _S25 * _S25 + _S26 * _S26;

#line 105
    float3 t1_0;
    if(lensq_0 > 0.0f)
    {

#line 106
        t1_0 = float3(- _S26, _S25, 0.0f) * float3(rsqrt(lensq_0)) ;

#line 106
    }
    else
    {

#line 106
        t1_0 = float3(1.0f, 0.0f, 0.0f);

#line 106
    }

    float r_1 = sqrt(u1_1);
    float phi_1 = 6.2831854820251465f * u2_1;
    float a_1 = r_1 * cos(phi_1);

    float s_3 = 0.5f * (1.0f + vh_0.z);
    float _S27 = 1.0f - a_1 * a_1;

#line 113
    float b_1 = (1.0f - s_3) * sqrt(_S27) + s_3 * (r_1 * sin(phi_1));
    float3 nh_0 = float3(a_1)  * t1_0 + float3(b_1)  * cross(vh_0, t1_0) + float3(sqrt(max(0.0f, _S27 - b_1 * b_1)))  * vh_0;
    return normalize(float3(alpha_3 * nh_0.x, alpha_3 * nh_0.y, max(0.0f, nh_0.z)));
}


#line 54
float3 cosineLocal_0(float u1_2, float u2_2)
{
    float r_2 = sqrt(u1_2);
    float phi_2 = 6.2831854820251465f * u2_2;
    return float3(r_2 * cos(phi_2), r_2 * sin(phi_2), sqrt(max(0.0f, 1.0f - u1_2)));
}


#line 241
[[kernel]] void pathtrace(uint3 tid_0 [[thread_position_in_grid]], uint device* params_1 [[buffer(6)]], metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_1 [[buffer(0)]], float device* envPixels_1 [[buffer(10)]], uint device* instances_1 [[buffer(3)]], uint device* indices_1 [[buffer(2)]], float device* positions_1 [[buffer(1)]], float device* materials_1 [[buffer(4)]], float device* emitters_1 [[buffer(8)]], uint device* lights_1 [[buffer(5)]], float device* emitCdf_1 [[buffer(9)]], float device* envMarginal_1 [[buffer(11)]], float device* envCond_1 [[buffer(12)]], float device* accum_1 [[buffer(7)]])
{

#line 241
    float3 radiance_0;

#line 241
    float dist_0;

#line 241
    float3 wi_0;

#line 241
    float3 li_0;

#line 241
    thread KernelContext_0 kernelContext_9;

#line 241
    (&kernelContext_9)->params_0 = params_1;

#line 241
    (&kernelContext_9)->scene_0 = scene_1;

#line 241
    (&kernelContext_9)->envPixels_0 = envPixels_1;

#line 241
    (&kernelContext_9)->instances_0 = instances_1;

#line 241
    (&kernelContext_9)->indices_0 = indices_1;

#line 241
    (&kernelContext_9)->positions_0 = positions_1;

#line 241
    (&kernelContext_9)->materials_0 = materials_1;

#line 241
    (&kernelContext_9)->emitters_0 = emitters_1;

#line 241
    (&kernelContext_9)->lights_0 = lights_1;

#line 241
    (&kernelContext_9)->emitCdf_0 = emitCdf_1;

#line 241
    (&kernelContext_9)->envMarginal_0 = envMarginal_1;

#line 241
    (&kernelContext_9)->envCond_0 = envCond_1;

#line 241
    (&kernelContext_9)->accum_0 = accum_1;

    uint w_3 = params_1[int(0)];
    uint h_2 = params_1[int(1)];
    uint _S28 = tid_0.x;

#line 245
    bool misPrev_0;

#line 245
    if(_S28 >= w_3)
    {

#line 245
        misPrev_0 = true;

#line 245
    }
    else
    {

#line 245
        misPrev_0 = (tid_0.y) >= h_2;

#line 245
    }

#line 245
    if(misPrev_0)
    {

#line 246
        return;
    }

#line 247
    uint _S29 = tid_0.y;

#line 247
    uint pixel_0 = _S29 * w_3 + _S28;
    thread Rng_0 rng_0;
    (&rng_0)->state_0 = pcg_0(pixel_0 ^ (pcg_0((&kernelContext_9)->params_0[int(6)] * 2654435769U + 2135587861U)));

#line 249
    float _S30 = pf_0(2U, &kernelContext_9);



    float _S31 = float(w_3);

#line 253
    float _S32 = float(h_2);

#line 253
    float aspect_0 = _S31 / _S32;
    float _S33 = float(_S28);

#line 254
    float _S34 = Rng_next_0(&rng_0);

#line 254
    float u_0 = (2.0f * (_S33 + _S34) / _S31 - 1.0f) * aspect_0 * _S30;
    float _S35 = float(_S29);

#line 255
    float _S36 = Rng_next_0(&rng_0);
    float3 _S37 = float3(u_0, (1.0f - 2.0f * (_S35 + _S36) / _S32) * _S30, -1.0f);

#line 256
    float _S38 = pf_0(4U, &kernelContext_9);

#line 256
    float3 focal_0 = _S37 * float3(_S38) ;

#line 256
    float _S39 = pf_0(3U, &kernelContext_9);
    float _S40 = Rng_next_0(&rng_0);

#line 257
    float lensR_0 = _S39 * sqrt(_S40);
    float _S41 = Rng_next_0(&rng_0);

#line 258
    float lensA_0 = 6.2831854820251465f * _S41;
    float _S42 = lensR_0 * cos(lensA_0);

#line 259
    float _S43 = lensR_0 * sin(lensA_0);
    float3 _S44 = normalize(focal_0 - float3(_S42, _S43, 0.0f));
    thread float3 org_0;

#line 261
    thread float3 dir_0;

#line 261
    uint r_3 = 0U;
    for(;;)
    {

#line 262
        if(r_3 < 3U)
        {
        }
        else
        {

#line 262
            break;
        }
        uint _S45 = 4U * r_3;

#line 264
        uint _S46 = 8U + _S45;

#line 264
        uint _S47 = 9U + _S45;

#line 264
        uint _S48 = 10U + _S45;

#line 264
        org_0[r_3] = (as_type<float>(((&kernelContext_9)->params_0[_S46]))) * _S42 + (as_type<float>(((&kernelContext_9)->params_0[_S47]))) * _S43 + (as_type<float>(((&kernelContext_9)->params_0[_S48]))) * 0.0f + (as_type<float>(((&kernelContext_9)->params_0[11U + _S45])));
        dir_0[r_3] = (as_type<float>(((&kernelContext_9)->params_0[_S46]))) * _S44.x + (as_type<float>(((&kernelContext_9)->params_0[_S47]))) * _S44.y + (as_type<float>(((&kernelContext_9)->params_0[_S48]))) * _S44.z;

#line 262
        r_3 = r_3 + 1U;

#line 262
    }

#line 267
    dir_0 = normalize(dir_0);

#line 267
    float _S49 = pf_0(20U, &kernelContext_9);

#line 267
    float _S50 = pf_0(21U, &kernelContext_9);

#line 267
    float _S51 = pf_0(22U, &kernelContext_9);

    float3 _S52 = float3(_S49, _S50, _S51);
    float3 _S53 = float3(0.0f) ;
    float3 _S54 = float3(1.0f) ;
    uint _S55 = (&kernelContext_9)->params_0[int(5)];
    uint _S56 = (&kernelContext_9)->params_0[int(7)];
    uint emitterCount_0 = (&kernelContext_9)->params_0[int(23)];

    bool hasEnv_0 = (&kernelContext_9)->params_0[int(24)] > 0U;

#line 276
    float _S57;

    if(hasEnv_0)
    {

#line 278
        if(emitterCount_0 > 0U)
        {

#line 278
            _S57 = 0.5f;

#line 278
        }
        else
        {

#line 278
            _S57 = 1.0f;

#line 278
        }

#line 278
    }
    else
    {

#line 278
        _S57 = 0.0f;

#line 278
    }

#line 278
    misPrev_0 = false;

#line 278
    float qPrev_0 = 0.0f;

#line 278
    uint depth_0 = 0U;

#line 278
    float3 thr_0 = _S54;

#line 278
    float3 radiance_1 = _S53;



    for(;;)
    {

#line 282
        if(depth_0 < _S56)
        {
        }
        else
        {

#line 282
            radiance_0 = radiance_1;

#line 282
            break;
        }
        thread RayDesc_0 ray_1;
        (&ray_1)->Origin_0 = org_0;
        (&ray_1)->Direction_0 = dir_0;
        (&ray_1)->TMin_0 = 0.0f;
        (&ray_1)->TMax_0 = 1.00000001504746622e+30f;
        thread raytracing::intersection_query<raytracing::triangle_data, raytracing::instancing> q_1;
        (&q_1)->reset({ (ray_1.Origin_0), (ray_1.Direction_0), (ray_1.TMin_0), (ray_1.TMax_0) }, ((&kernelContext_9)->scene_0), (255U), _slang_ray_flags_to_intersection_params((1U)));
        for(;;)
        {

#line 291
            bool _S58 = ((&q_1)->next());

#line 291
            if(_S58)
            {
            }
            else
            {

#line 291
                break;
            }

#line 291
        }

        uint _S59 = (_slang_committed_intersection_type_to_uint((&q_1)->get_committed_intersection_type()));

#line 293
        float wB_0;

#line 293
        if(_S59 != 1U)
        {

            float3 radiance_2 = radiance_1 + thr_0 * _S52;
            if(hasEnv_0)
            {

                if(misPrev_0)
                {

#line 300
                    float _S60 = envPdf_0(dir_0, &kernelContext_9);

                    float pl_0 = _S57 * _S60;
                    float _S61 = qPrev_0 * qPrev_0;

#line 303
                    float den_0 = _S61 + pl_0 * pl_0;
                    if(den_0 > 0.0f)
                    {

#line 304
                        _S57 = _S61 / den_0;

#line 304
                    }
                    else
                    {

#line 304
                        _S57 = 1.0f;

#line 304
                    }

#line 304
                    wB_0 = _S57;

#line 300
                }
                else
                {

#line 300
                    wB_0 = 1.0f;

#line 300
                }

#line 300
                float3 _S62 = envRadiance_0(dir_0, &kernelContext_9);

#line 300
                radiance_0 = radiance_2 + thr_0 * _S62 * float3(wB_0) ;

#line 297
            }
            else
            {

#line 297
                radiance_0 = radiance_2;

#line 297
            }

#line 308
            break;
        }

        uint _S63 = ((&q_1)->get_committed_instance_id());

#line 311
        uint inst_0 = _S63 * 16U;
        uint _S64 = (&kernelContext_9)->instances_0[inst_0 + 1U];

#line 312
        uint _S65 = ((&q_1)->get_committed_primitive_id());

#line 312
        uint tri_0 = _S64 + 3U * _S65;
        uint vo_0 = (&kernelContext_9)->instances_0[inst_0];
        uint _S66 = inst_0 + 4U;

#line 314
        float3 _S67 = vertexPos_0((&kernelContext_9)->indices_0[tri_0] + vo_0, &kernelContext_9);

#line 314
        float3 _S68 = transformPoint_0(_S66, _S67, &kernelContext_9);

#line 314
        float3 _S69 = vertexPos_0((&kernelContext_9)->indices_0[tri_0 + 1U] + vo_0, &kernelContext_9);

#line 314
        float3 _S70 = transformPoint_0(_S66, _S69, &kernelContext_9);

#line 314
        float3 _S71 = vertexPos_0((&kernelContext_9)->indices_0[tri_0 + 2U] + vo_0, &kernelContext_9);

#line 314
        float3 _S72 = transformPoint_0(_S66, _S71, &kernelContext_9);



        float3 nOut_0 = normalize(cross(_S70 - _S68, _S72 - _S68));
        float3 wo_1 = - dir_0;
        bool outside_0 = (dot(nOut_0, wo_1)) > 0.0f;

#line 320
        float3 n_1;
        if(outside_0)
        {

#line 321
            n_1 = nOut_0;

#line 321
        }
        else
        {

#line 321
            n_1 = - nOut_0;

#line 321
        }
        float pHitT_0 = ((&q_1)->get_committed_distance());
        float3 hit_0 = org_0 + dir_0 * float3(pHitT_0) ;

        float3 p_1 = hit_0 + n_1 * float3(9.9999997473787516e-05f) ;

        uint mi_0 = (&kernelContext_9)->instances_0[inst_0 + 2U] * 12U;
        float3 albedo_1 = float3((&kernelContext_9)->materials_0[mi_0], (&kernelContext_9)->materials_0[mi_0 + 1U], (&kernelContext_9)->materials_0[mi_0 + 2U]);
        float3 le_1 = float3((&kernelContext_9)->materials_0[mi_0 + 3U], (&kernelContext_9)->materials_0[mi_0 + 4U], (&kernelContext_9)->materials_0[mi_0 + 5U]);

#line 329
        bool chooseEnv_0;

#line 329
        float3 radiance_3;
        if(any(le_1 > (float3(0.0f) )))
        {

            uint eb_0 = (&kernelContext_9)->instances_0[inst_0 + 3U];
            if(misPrev_0)
            {

#line 334
                chooseEnv_0 = eb_0 != 0U;

#line 334
            }
            else
            {

#line 334
                chooseEnv_0 = false;

#line 334
            }

#line 334
            if(chooseEnv_0)
            {
                uint _S73 = eb_0 - 1U;

#line 336
                uint _S74 = ((&q_1)->get_committed_primitive_id());

#line 336
                uint e_0 = (_S73 + _S74) * 16U;

                float pl_1 = (1.0f - _S57) * (&kernelContext_9)->emitters_0[e_0 + 13U] * pHitT_0 * pHitT_0 / ((&kernelContext_9)->emitters_0[e_0 + 12U] * max(abs(dot(nOut_0, dir_0)), 9.9999997473787516e-05f));
                float _S75 = qPrev_0 * qPrev_0;

#line 339
                wB_0 = _S75 / (_S75 + pl_1 * pl_1);

#line 334
            }
            else
            {

#line 334
                wB_0 = 1.0f;

#line 334
            }

#line 334
            radiance_3 = radiance_1 + thr_0 * le_1 * float3(wB_0) ;

#line 330
        }
        else
        {

#line 330
            radiance_3 = radiance_1;

#line 330
        }

#line 343
        float metallic_1 = (&kernelContext_9)->materials_0[mi_0 + 6U];
        float rough_0 = (&kernelContext_9)->materials_0[mi_0 + 7U];
        float transmission_1 = (&kernelContext_9)->materials_0[mi_0 + 8U];
        float ior_1 = (&kernelContext_9)->materials_0[mi_0 + 9U];
        float _S76 = max(rough_0 * rough_0, 0.0010000000474974513f);
        if(outside_0)
        {

#line 348
            wB_0 = ior_1;

#line 348
        }
        else
        {

#line 348
            wB_0 = 1.0f / ior_1;

#line 348
        }

        thread float3 T_0;

#line 350
        thread float3 B_0;
        basis_0(n_1, &T_0, &B_0);
        float _S77 = max(dot(wo_1, n_1), 9.9999997473787516e-05f);

#line 352
        float3 woL_2 = float3(dot(wo_1, T_0), dot(wo_1, B_0), _S77);
        float fSel_1 = fresnelDielectric_0(_S77, ior_1);
        thread Surface_0 surf_0;
        (&surf_0)->albedo_0 = albedo_1;
        (&surf_0)->metallic_0 = metallic_1;
        (&surf_0)->alpha_2 = _S76;
        (&surf_0)->transmission_0 = transmission_1;
        (&surf_0)->ior_0 = ior_1;
        (&surf_0)->eta_1 = wB_0;
        (&surf_0)->fSel_0 = fSel_1;

#line 361
        uint li_1 = 0U;

#line 361
        radiance_0 = radiance_3;



        for(;;)
        {

#line 365
            if(li_1 < _S55)
            {
            }
            else
            {

#line 365
                break;
            }
            uint o_3 = li_1 * 8U;
            float3 col_0 = float3((as_type<float>(((&kernelContext_9)->lights_0[o_3 + 1U]))), (as_type<float>(((&kernelContext_9)->lights_0[o_3 + 2U]))), (as_type<float>(((&kernelContext_9)->lights_0[o_3 + 3U])))) * float3((as_type<float>(((&kernelContext_9)->lights_0[o_3 + 4U])))) ;
            float3 vec_0 = float3((as_type<float>(((&kernelContext_9)->lights_0[o_3 + 5U]))), (as_type<float>(((&kernelContext_9)->lights_0[o_3 + 6U]))), (as_type<float>(((&kernelContext_9)->lights_0[o_3 + 7U]))));



            if((&kernelContext_9)->lights_0[o_3] == 0U)
            {
                float3 toL_0 = vec_0 - p_1;
                float d2_0 = dot(toL_0, toL_0);
                float dist_1 = sqrt(d2_0);

                float3 _S78 = col_0 / float3(d2_0) ;

#line 379
                wi_0 = toL_0 / float3(dist_1) ;

#line 379
                dist_0 = dist_1;

#line 379
                li_0 = _S78;

#line 373
            }
            else
            {

#line 373
                wi_0 = - normalize(vec_0);

#line 373
                dist_0 = 1.00000001504746622e+30f;

#line 373
                li_0 = col_0;

#line 373
            }

#line 387
            float c_2 = dot(n_1, wi_0);
            if(c_2 > 0.0f)
            {

#line 388
                bool _S79 = occluded_0(p_1, wi_0, dist_0 - 0.0010000000474974513f, &kernelContext_9);

#line 388
                chooseEnv_0 = !_S79;

#line 388
            }
            else
            {

#line 388
                chooseEnv_0 = false;

#line 388
            }

#line 388
            if(chooseEnv_0)
            {
                float3 _S80 = float3(dot(wi_0, T_0), dot(wi_0, B_0), c_2);

#line 390
                thread Surface_0 _S81 = surf_0;

#line 390
                float3 _S82 = evalReflective_0(&_S81, woL_2, _S80);

#line 390
                radiance_0 = radiance_0 + thr_0 * _S82 * li_0;

#line 388
            }

#line 365
            li_1 = li_1 + 1U;

#line 365
        }

#line 396
        float chooseLight_0 = Rng_next_0(&rng_0);
        if(hasEnv_0)
        {

#line 397
            chooseEnv_0 = chooseLight_0 < _S57;

#line 397
        }
        else
        {

#line 397
            chooseEnv_0 = false;

#line 397
        }

#line 397
        bool _S83;
        if(emitterCount_0 > 0U)
        {

#line 398
            _S83 = !chooseEnv_0;

#line 398
        }
        else
        {

#line 398
            _S83 = false;

#line 398
        }

#line 398
        bool ok_0;

#line 398
        bool refracted_0;

#line 398
        if(_S83)
        {
            float _S84 = Rng_next_0(&rng_0);
            float ua_0 = Rng_next_0(&rng_0);
            float ub_0 = Rng_next_0(&rng_0);

            uint _S85 = emitterCount_0 - 1U;

#line 404
            uint lo_2 = 0U;

#line 404
            uint hi_1 = _S85;
            for(;;)
            {

#line 405
                if(lo_2 < hi_1)
                {
                }
                else
                {

#line 405
                    break;
                }
                uint mid_2 = (lo_2 + hi_1) / 2U;
                if((&kernelContext_9)->emitCdf_0[mid_2] >= _S84)
                {

#line 408
                    hi_1 = mid_2;

#line 408
                }
                else
                {

#line 408
                    lo_2 = mid_2 + 1U;

#line 408
                }

#line 405
            }

#line 413
            uint e_1 = lo_2 * 16U;
            float3 a_2 = float3((&kernelContext_9)->emitters_0[e_1], (&kernelContext_9)->emitters_0[e_1 + 1U], (&kernelContext_9)->emitters_0[e_1 + 2U]);
            float3 b_2 = float3((&kernelContext_9)->emitters_0[e_1 + 3U], (&kernelContext_9)->emitters_0[e_1 + 4U], (&kernelContext_9)->emitters_0[e_1 + 5U]);
            float3 c_3 = float3((&kernelContext_9)->emitters_0[e_1 + 6U], (&kernelContext_9)->emitters_0[e_1 + 7U], (&kernelContext_9)->emitters_0[e_1 + 8U]);
            float su_0 = sqrt(ua_0);

            float3 toL_1 = a_2 * float3((1.0f - su_0))  + b_2 * float3((su_0 * (1.0f - ub_0)))  + c_3 * float3((su_0 * ub_0))  - p_1;
            float d2_1 = dot(toL_1, toL_1);
            float dist_2 = sqrt(d2_1);
            float3 wi_1 = toL_1 / float3(dist_2) ;
            float cosl_0 = abs(dot(normalize(cross(b_2 - a_2, c_3 - a_2)), wi_1));
            float cosi_1 = dot(n_1, wi_1);
            if(cosi_1 > 0.0f)
            {

#line 425
                ok_0 = cosl_0 > 9.9999997473787516e-06f;

#line 425
            }
            else
            {

#line 425
                ok_0 = false;

#line 425
            }

#line 425
            if(ok_0)
            {

#line 425
                bool _S86 = occluded_0(p_1, wi_1, dist_2 * 0.99900001287460327f, &kernelContext_9);

#line 425
                refracted_0 = !_S86;

#line 425
            }
            else
            {

#line 425
                refracted_0 = false;

#line 425
            }

#line 425
            if(refracted_0)
            {
                float pl_2 = (1.0f - _S57) * (&kernelContext_9)->emitters_0[e_1 + 13U] * d2_1 / ((&kernelContext_9)->emitters_0[e_1 + 12U] * cosl_0);
                float3 wiL_2 = float3(dot(wi_1, T_0), dot(wi_1, B_0), cosi_1);

#line 428
                thread Surface_0 _S87 = surf_0;

#line 428
                float _S88 = reflectivePdf_0(&_S87, woL_2, wiL_2);

                float _S89 = pl_2 * pl_2;

#line 430
                float wl_0 = _S89 / (_S89 + _S88 * _S88);

#line 430
                thread Surface_0 _S90 = surf_0;

#line 430
                float3 _S91 = evalReflective_0(&_S90, woL_2, wiL_2);

#line 430
                wi_0 = radiance_0 + thr_0 * _S91 * float3((&kernelContext_9)->emitters_0[e_1 + 9U], (&kernelContext_9)->emitters_0[e_1 + 10U], (&kernelContext_9)->emitters_0[e_1 + 11U]) / float3(pl_2)  * float3(wl_0) ;

#line 425
            }
            else
            {

#line 425
                wi_0 = radiance_0;

#line 425
            }

#line 398
        }
        else
        {

#line 398
            wi_0 = radiance_0;

#line 398
        }

#line 435
        if(chooseEnv_0)
        {
            float e1_0 = Rng_next_0(&rng_0);
            float e2_0 = Rng_next_0(&rng_0);
            float e3_0 = Rng_next_0(&rng_0);
            float e4_0 = Rng_next_0(&rng_0);
            thread float pdfE_0;
            thread float3 leE_0;

#line 442
            float3 _S92 = envSample_0(e1_0, e2_0, e3_0, e4_0, &pdfE_0, &leE_0, &kernelContext_9);

            float cosi_2 = dot(n_1, _S92);
            if(pdfE_0 > 0.0f)
            {

#line 445
                ok_0 = cosi_2 > 0.0f;

#line 445
            }
            else
            {

#line 445
                ok_0 = false;

#line 445
            }

#line 445
            if(ok_0)
            {

#line 445
                bool _S93 = occluded_0(p_1, _S92, 1.00000001504746622e+30f, &kernelContext_9);

#line 445
                refracted_0 = !_S93;

#line 445
            }
            else
            {

#line 445
                refracted_0 = false;

#line 445
            }

#line 445
            if(refracted_0)
            {
                float pl_3 = _S57 * pdfE_0;
                float3 wiL_3 = float3(dot(_S92, T_0), dot(_S92, B_0), cosi_2);

#line 448
                thread Surface_0 _S94 = surf_0;

#line 448
                float _S95 = reflectivePdf_0(&_S94, woL_2, wiL_3);

                float _S96 = pl_3 * pl_3;

#line 450
                float wl_1 = _S96 / (_S96 + _S95 * _S95);

#line 450
                thread Surface_0 _S97 = surf_0;

#line 450
                float3 _S98 = evalReflective_0(&_S97, woL_2, wiL_3);

#line 450
                li_0 = wi_0 + thr_0 * _S98 * leE_0 / float3(pl_3)  * float3(wl_1) ;

#line 445
            }
            else
            {

#line 445
                li_0 = wi_0;

#line 445
            }

#line 435
        }
        else
        {

#line 435
            li_0 = wi_0;

#line 435
        }

#line 457
        float lobe_0 = Rng_next_0(&rng_0);
        float u1_3 = Rng_next_0(&rng_0);
        float u2_3 = Rng_next_0(&rng_0);
        float u3_1 = Rng_next_0(&rng_0);

#line 460
        float3 wiL_4;

#line 460
        float3 w_4;

#line 465
        if(lobe_0 < metallic_1)
        {
            float3 h_3 = sampleVndf_0(woL_2, _S76, u1_3, u2_3);
            float woh_0 = dot(woL_2, h_3);
            float3 wiL_5 = float3((2.0f * woh_0))  * h_3 - woL_2;
            float _S99 = wiL_5.z;
            float3 _S100 = schlick_0(albedo_1, woh_0) * float3(G1_0(max(_S99, 0.0f), _S76)) ;

#line 471
            ok_0 = _S99 > 0.0f;

#line 471
            refracted_0 = false;

#line 471
            wiL_4 = wiL_5;

#line 471
            w_4 = _S100;

#line 465
        }
        else
        {

#line 473
            if(lobe_0 < (metallic_1 + (1.0f - metallic_1) * transmission_1))
            {
                float3 h_4 = sampleVndf_0(woL_2, _S76, u1_3, u2_3);
                float woh_1 = dot(woL_2, h_4);
                if(u3_1 < (fresnelDielectric_0(woh_1, wB_0)))
                {
                    float3 wiL_6 = float3((2.0f * woh_1))  * h_4 - woL_2;
                    float _S101 = wiL_6.z;
                    float3 _S102 = float3(G1_0(max(_S101, 0.0f), _S76)) ;

#line 481
                    ok_0 = _S101 > 0.0f;

#line 481
                    refracted_0 = false;

#line 481
                    wiL_4 = wiL_6;

#line 481
                    w_4 = _S102;

#line 477
                }
                else
                {

#line 485
                    float r_4 = 1.0f / wB_0;
                    float k_0 = 1.0f - r_4 * r_4 * (1.0f - woh_1 * woh_1);

#line 486
                    float3 _S103 = float3(r_4) ;
                    float3 wiL_7 = - woL_2 * _S103 + float3((r_4 * woh_1 - sqrt(max(k_0, 0.0f))))  * h_4;
                    float _S104 = wiL_7.z;

#line 488
                    if(_S104 < 0.0f)
                    {

#line 488
                        ok_0 = k_0 > 0.0f;

#line 488
                    }
                    else
                    {

#line 488
                        ok_0 = false;

#line 488
                    }


                    float3 _S105 = albedo_1 * float3(G1_0(max(- _S104, 0.0f), _S76))  * _S103 * _S103;

#line 491
                    refracted_0 = true;

#line 491
                    wiL_4 = wiL_7;

#line 491
                    w_4 = _S105;

#line 477
                }

#line 473
            }
            else
            {

#line 494
                if(u3_1 < fSel_1)
                {
                    float3 h_5 = sampleVndf_0(woL_2, _S76, u1_3, u2_3);
                    float woh_2 = dot(woL_2, h_5);
                    float3 wiL_8 = float3((2.0f * woh_2))  * h_5 - woL_2;
                    float _S106 = wiL_8.z;
                    float3 _S107 = float3((fresnelDielectric_0(woh_2, ior_1) / fSel_1 * G1_0(max(_S106, 0.0f), _S76))) ;

#line 500
                    ok_0 = _S106 > 0.0f;

#line 500
                    wiL_4 = wiL_8;

#line 500
                    w_4 = _S107;

#line 494
                }
                else
                {

#line 504
                    float3 _S108 = cosineLocal_0(u1_3, u2_3);

#line 504
                    ok_0 = true;

#line 504
                    wiL_4 = _S108;

#line 504
                    w_4 = albedo_1;

#line 494
                }

#line 494
                refracted_0 = false;

#line 473
            }

#line 465
        }

#line 507
        if(!ok_0)
        {

#line 507
            radiance_0 = li_0;
            break;
        }

#line 509
        bool _S109 = !refracted_0;
        if(refracted_0)
        {

#line 510
            qPrev_0 = 0.0f;

#line 510
        }
        else
        {

#line 510
            thread Surface_0 _S110 = surf_0;

#line 510
            float _S111 = reflectivePdf_0(&_S110, woL_2, wiL_4);

#line 510
            qPrev_0 = _S111;

#line 510
        }

        float _S112 = wiL_4.z;

#line 512
        dir_0 = normalize(float3(wiL_4.x)  * T_0 + float3(wiL_4.y)  * B_0 + float3(_S112)  * n_1);
        if(_S112 > 0.0f)
        {

#line 513
            dist_0 = 9.9999997473787516e-05f;

#line 513
        }
        else
        {

#line 513
            dist_0 = -9.9999997473787516e-05f;

#line 513
        }

#line 513
        org_0 = hit_0 + n_1 * float3(dist_0) ;
        float3 thr_1 = thr_0 * w_4;

        if(depth_0 >= 2U)
        {
            float pr_0 = clamp(max(thr_1.x, max(thr_1.y, thr_1.z)), 0.05000000074505806f, 0.94999998807907104f);
            float _S113 = Rng_next_0(&rng_0);

#line 519
            if(_S113 > pr_0)
            {

#line 519
                radiance_0 = li_0;
                break;
            }

#line 520
            thr_0 = thr_1 / float3(pr_0) ;

#line 516
        }
        else
        {

#line 516
            thr_0 = thr_1;

#line 516
        }

#line 282
        uint _S114 = depth_0 + 1U;

#line 282
        misPrev_0 = _S109;

#line 282
        depth_0 = _S114;

#line 282
        radiance_1 = li_0;

#line 282
    }

#line 525
    if(any(isnan(radiance_0)))
    {

#line 525
        misPrev_0 = true;

#line 525
    }
    else
    {

#line 525
        misPrev_0 = any(isinf(radiance_0));

#line 525
    }

#line 525
    if(misPrev_0)
    {

#line 525
        radiance_0 = _S53;

#line 525
    }


    uint o_4 = 3U * pixel_0;
    float device* _S115 = (&kernelContext_9)->accum_0+o_4;

#line 529
    *_S115 = *_S115 + radiance_0.x;
    float device* _S116 = (&kernelContext_9)->accum_0+(o_4 + 1U);

#line 530
    *_S116 = *_S116 + radiance_0.y;
    float device* _S117 = (&kernelContext_9)->accum_0+(o_4 + 2U);

#line 531
    *_S117 = *_S117 + radiance_0.z;
    return;
}

