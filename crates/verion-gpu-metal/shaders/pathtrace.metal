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
            

#line 26 "shaders/pathtrace.slang"
uint pcg_0(uint v_0)
{
    uint s_0 = v_0 * 747796405U + 2891336453U;
    uint w_0 = ((s_0 >> ((s_0 >> 28U) + 4U)) ^ s_0) * 277803737U;
    return (w_0 >> 22U) ^ w_0;
}


#line 618
struct KernelContext_0
{
    uint device* params_0;
    metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_0;
    float device* envPixels_0;
    uint device* instances_0;
    uint device* indices_0;
    float device* positions_0;
    float device* materials_0;
    float device* uvs_0;
    uint device* texInfo_0;
    float device* texels_0;
    float device* emitters_0;
    uint device* lights_0;
    float device* emitCdf_0;
    float device* envMarginal_0;
    float device* envCond_0;
    float device* accum_0;
};


#line 43
float pf_0(uint i_0, KernelContext_0 thread* kernelContext_0)
{

#line 43
    return (as_type<float>((kernelContext_0->params_0[i_0])));
}


#line 33
struct Rng_0
{
    uint state_0;
};


#line 36
float Rng_next_0(Rng_0 thread* this_0)
{
    uint _S1 = pcg_0(this_0->state_0);

#line 38
    this_0->state_0 = _S1;
    return float(_S1 >> 8U) * 5.9604644775390625e-08f;
}


#line 133
void envCoords_0(float3 d_0, uint thread* i_1, uint thread* j_0, KernelContext_0 thread* kernelContext_1)
{
    uint w_1 = kernelContext_1->params_0[int(24)];
    uint h_0 = kernelContext_1->params_0[int(25)];

    float v_1 = acos(clamp(d_0.y, -1.0f, 1.0f)) / 3.1415927410125732f;
    *i_1 = min(uint((atan2(d_0.x, - d_0.z) * 0.15915493667125702f + 0.5f) * float(w_1)), w_1 - 1U);
    *j_0 = min(uint(v_1 * float(h_0)), h_0 - 1U);
    return;
}


#line 126
float3 envTexel_0(uint i_2, uint j_1, KernelContext_0 thread* kernelContext_2)
{
    uint o_0 = 3U * (j_1 * kernelContext_2->params_0[int(24)] + i_2);
    return float3(kernelContext_2->envPixels_0[o_0], kernelContext_2->envPixels_0[o_0 + 1U], kernelContext_2->envPixels_0[o_0 + 2U]);
}


#line 124
float lum_0(float3 c_0)
{

#line 124
    return dot(c_0, float3(0.2125999927520752f, 0.71520000696182251f, 0.072200000286102295f));
}


#line 152
float envPdf_0(float3 d_1, KernelContext_0 thread* kernelContext_3)
{
    thread uint i_3;

#line 154
    thread uint j_2;

#line 154
    envCoords_0(d_1, &i_3, &j_2, kernelContext_3);

#line 154
    float3 _S2 = envTexel_0(i_3, j_2, kernelContext_3);

    float _S3 = lum_0(_S2);

#line 156
    float _S4 = pf_0(26U, kernelContext_3);

#line 156
    return _S3 * _S4;
}


#line 143
float3 envRadiance_0(float3 d_2, KernelContext_0 thread* kernelContext_4)
{
    thread uint i_4;

#line 145
    thread uint j_3;

#line 145
    envCoords_0(d_2, &i_4, &j_3, kernelContext_4);

#line 145
    float3 _S5 = envTexel_0(i_4, j_3, kernelContext_4);

    return _S5;
}


#line 45
float3 vertexPos_0(uint v_2, KernelContext_0 thread* kernelContext_5)
{

#line 45
    uint _S6 = 3U * v_2;

#line 45
    return float3(kernelContext_5->positions_0[_S6], kernelContext_5->positions_0[_S6 + 1U], kernelContext_5->positions_0[_S6 + 2U]);
}


#line 47
float3 transformPoint_0(uint base_0, float3 p_0, KernelContext_0 thread* kernelContext_6)
{
    thread float3 r_0;

#line 49
    uint row_0 = 0U;
    for(;;)
    {

#line 50
        if(row_0 < 3U)
        {
        }
        else
        {

#line 50
            break;
        }
        uint o_1 = base_0 + 4U * row_0;
        r_0[row_0] = (as_type<float>((kernelContext_6->instances_0[o_1]))) * p_0.x + (as_type<float>((kernelContext_6->instances_0[o_1 + 1U]))) * p_0.y + (as_type<float>((kernelContext_6->instances_0[o_1 + 2U]))) * p_0.z + (as_type<float>((kernelContext_6->instances_0[o_1 + 3U])));

#line 50
        row_0 = row_0 + 1U;

#line 50
    }

#line 55
    return r_0;
}


#line 194
float3 texelAt_0(uint base_1, uint w_2, uint h_1, int x_0, int y_0, KernelContext_0 thread* kernelContext_7)
{
    int _S7 = int(w_2);

#line 196
    int _S8 = x_0 % _S7;

#line 196
    int _S9 = (_S8 + _S7) % _S7;

#line 196
    uint xi_0 = uint(_S9);
    int _S10 = int(h_1);

#line 197
    int _S11 = y_0 % _S10;

#line 197
    int _S12 = (_S11 + _S10) % _S10;
    uint o_2 = 3U * (base_1 + uint(_S12) * w_2 + xi_0);
    return float3(kernelContext_7->texels_0[o_2], kernelContext_7->texels_0[o_2 + 1U], kernelContext_7->texels_0[o_2 + 2U]);
}

float3 bilinear_0(uint base_2, uint w_3, uint h_2, float2 uv_0, KernelContext_0 thread* kernelContext_8)
{
    float fx_0 = uv_0.x * float(w_3) - 0.5f;
    float fy_0 = uv_0.y * float(h_2) - 0.5f;
    int x0_0 = int(floor(fx_0));
    int y0_0 = int(floor(fy_0));
    float tx_0 = fx_0 - float(x0_0);
    float ty_0 = fy_0 - float(y0_0);

#line 209
    float3 _S13 = texelAt_0(base_2, w_3, h_2, x0_0, y0_0, kernelContext_8);
    int _S14 = x0_0 + int(1);

#line 210
    float3 _S15 = texelAt_0(base_2, w_3, h_2, _S14, y0_0, kernelContext_8);

#line 210
    float3 _S16 = float3(tx_0) ;

#line 210
    float3 a_0 = mix(_S13, _S15, _S16);
    int _S17 = y0_0 + int(1);

#line 211
    float3 _S18 = texelAt_0(base_2, w_3, h_2, x0_0, _S17, kernelContext_8);

#line 211
    float3 _S19 = texelAt_0(base_2, w_3, h_2, _S14, _S17, kernelContext_8);
    return mix(a_0, mix(_S18, _S19, _S16), float3(ty_0) );
}


float3 sampleTexture_0(uint tex_0, float2 uv_1, float footprint_0, KernelContext_0 thread* kernelContext_9)
{
    uint ti_0 = tex_0 * 4U;
    uint base_3 = kernelContext_9->texInfo_0[ti_0];
    uint w_4 = kernelContext_9->texInfo_0[ti_0 + 1U];
    uint h_3 = kernelContext_9->texInfo_0[ti_0 + 2U];
    uint levels_0 = kernelContext_9->texInfo_0[ti_0 + 3U];
    float lod_0 = clamp(log2(max(footprint_0 * float(max(w_4, h_3)), 9.99999993922529029e-09f)), 0.0f, float(levels_0 - 1U));
    uint l0_0 = uint(floor(lod_0));
    float t_0 = lod_0 - float(l0_0);

#line 225
    uint lw_0 = w_4;

#line 225
    uint lh_0 = h_3;

#line 225
    uint k_0 = 0U;

#line 225
    uint off_0 = base_3;



    for(;;)
    {

#line 229
        if(k_0 < l0_0)
        {
        }
        else
        {

#line 229
            break;
        }
        uint off_1 = off_0 + lw_0 * lh_0;
        uint _S20 = max(lw_0 / 2U, 1U);
        uint _S21 = max(lh_0 / 2U, 1U);

#line 229
        uint _S22 = k_0 + 1U;

#line 229
        lw_0 = _S20;

#line 229
        lh_0 = _S21;

#line 229
        k_0 = _S22;

#line 229
        off_0 = off_1;

#line 229
    }

#line 229
    float3 _S23 = bilinear_0(off_0, lw_0, lh_0, uv_1, kernelContext_9);

#line 229
    bool _S24;

#line 236
    if((l0_0 + 1U) >= levels_0)
    {

#line 236
        _S24 = true;

#line 236
    }
    else
    {

#line 236
        _S24 = t_0 <= 0.0f;

#line 236
    }

#line 236
    if(_S24)
    {

#line 237
        return _S23;
    }

#line 237
    float3 _S25 = bilinear_0(off_0 + lw_0 * lh_0, max(lw_0 / 2U, 1U), max(lh_0 / 2U, 1U), uv_1, kernelContext_9);


    return mix(_S23, _S25, float3(t_0) );
}


#line 98
void basis_0(float3 n_0, float3 thread* t_1, float3 thread* b_0)
{

#line 98
    float3 a_1;

    if((abs(n_0.x)) > 0.89999997615814209f)
    {

#line 100
        a_1 = float3(0.0f, 1.0f, 0.0f);

#line 100
    }
    else
    {

#line 100
        a_1 = float3(1.0f, 0.0f, 0.0f);

#line 100
    }
    float3 _S26 = normalize(cross(n_0, a_1));

#line 101
    *b_0 = _S26;
    *t_1 = cross(_S26, n_0);
    return;
}


#line 87
float fresnelDielectric_0(float cosi_0, float eta_0)
{
    float s2_0 = (1.0f - cosi_0 * cosi_0) / (eta_0 * eta_0);
    if(s2_0 >= 1.0f)
    {

#line 91
        return 1.0f;
    }

#line 92
    float cost_0 = sqrt(1.0f - s2_0);
    float _S27 = eta_0 * cost_0;

#line 93
    float rs_0 = (cosi_0 - _S27) / (cosi_0 + _S27);
    float _S28 = eta_0 * cosi_0;

#line 94
    float rp_0 = (_S28 - cost_0) / (_S28 + cost_0);
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


#line 280 "shaders/pathtrace.slang"
bool occluded_0(float3 o_3, float3 d_3, float tmax_0, KernelContext_0 thread* kernelContext_10)
{
    thread RayDesc_0 ray_0;
    (&ray_0)->Origin_0 = o_3;
    (&ray_0)->Direction_0 = d_3;
    (&ray_0)->TMin_0 = 0.0f;
    (&ray_0)->TMax_0 = tmax_0;
    thread raytracing::intersection_query<raytracing::triangle_data, raytracing::instancing> q_0;
    (&q_0)->reset({ (ray_0.Origin_0), (ray_0.Direction_0), (ray_0.TMin_0), (ray_0.TMax_0) }, (kernelContext_10->scene_0), (255U), _slang_ray_flags_to_intersection_params((5U)));
    for(;;)
    {

#line 289
        bool _S29 = ((&q_0)->next());

#line 289
        if(_S29)
        {
        }
        else
        {

#line 289
            break;
        }

#line 289
    }
    uint _S30 = (_slang_committed_intersection_type_to_uint((&q_0)->get_committed_intersection_type()));

#line 290
    return _S30 == 1U;
}


#line 72
float D_0(float hz_0, float alpha_0)
{
    float a2_0 = alpha_0 * alpha_0;
    float d_4 = hz_0 * hz_0 * (a2_0 - 1.0f) + 1.0f;
    return a2_0 / (3.1415927410125732f * d_4 * d_4);
}


#line 65
float G1_0(float cosT_0, float alpha_1)
{
    float c2_0 = cosT_0 * cosT_0;

    return 2.0f / (1.0f + sqrt(1.0f + alpha_1 * alpha_1 * ((1.0f - c2_0) / max(c2_0, 9.99999993922529029e-09f))));
}


#line 79
float3 schlick_0(float3 f0_0, float c_1)
{
    float m_0 = 1.0f - saturate(c_1);
    float m2_0 = m_0 * m_0;
    return f0_0 + (float3(1.0f)  - f0_0) * float3((m2_0 * m2_0 * m_0)) ;
}


#line 243
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
    float _S31 = max(dot(woL_0, hh_0), 0.0f);

    float _S32 = woL_0.z;

#line 260
    float _S33 = wiL_0.z;

#line 260
    float core_0 = D_0(hh_0.z, s_1->alpha_2) * G1_0(_S32, s_1->alpha_2) * G1_0(_S33, s_1->alpha_2) / (4.0f * _S32);


    float _S34 = 1.0f - s_1->metallic_0;

#line 263
    float _S35 = 1.0f - s_1->transmission_0;

#line 262
    return float3(s_1->metallic_0)  * schlick_0(s_1->albedo_0, _S31) * float3(core_0)  + float3((_S34 * (s_1->transmission_0 * fresnelDielectric_0(_S31, s_1->eta_1) + _S35 * fresnelDielectric_0(_S31, s_1->ior_0)) * core_0))  + float3((_S34 * _S35 * (1.0f - s_1->fSel_0)))  * s_1->albedo_0 * float3((_S33 / 3.1415927410125732f)) ;
}


#line 269
float reflectivePdf_0(const Surface_0 thread* s_2, float3 woL_1, float3 wiL_1)
{
    float3 hh_1 = normalize(woL_1 + wiL_1);

    float _S36 = woL_1.z;

    float _S37 = 1.0f - s_2->metallic_0;

#line 275
    float _S38 = 1.0f - s_2->transmission_0;

    return (s_2->metallic_0 + _S37 * (s_2->transmission_0 * fresnelDielectric_0(max(dot(woL_1, hh_1), 0.0f), s_2->eta_1) + _S38 * s_2->fSel_0)) * (G1_0(_S36, s_2->alpha_2) * D_0(hh_1.z, s_2->alpha_2) / (4.0f * _S36)) + _S37 * _S38 * (1.0f - s_2->fSel_0) * wiL_1.z / 3.1415927410125732f;
}


#line 159
float3 envSample_0(float u1_0, float u2_0, float u3_0, float u4_0, float thread* pdf_0, float3 thread* le_0, KernelContext_0 thread* kernelContext_11)
{

#line 159
    uint lo_0;

    uint w_5 = kernelContext_11->params_0[int(24)];
    uint h_4 = kernelContext_11->params_0[int(25)];

    uint _S39 = h_4 - 1U;

#line 164
    uint lo_1 = 0U;

#line 164
    uint hi_0 = _S39;
    for(;;)
    {

#line 165
        if(lo_1 < hi_0)
        {
        }
        else
        {

#line 165
            break;
        }
        uint mid_0 = (lo_1 + hi_0) / 2U;
        if(kernelContext_11->envMarginal_0[mid_0] >= u1_0)
        {

#line 168
            lo_0 = lo_1;

#line 168
            hi_0 = mid_0;

#line 168
        }
        else
        {

#line 168
            lo_0 = mid_0 + 1U;

#line 168
        }

#line 168
        lo_1 = lo_0;

#line 165
    }

#line 175
    uint _S40 = w_5 - 1U;

#line 175
    lo_0 = 0U;

#line 175
    hi_0 = _S40;
    for(;;)
    {

#line 176
        if(lo_0 < hi_0)
        {
        }
        else
        {

#line 176
            break;
        }
        uint mid_1 = (lo_0 + hi_0) / 2U;
        if(kernelContext_11->envCond_0[lo_1 * w_5 + mid_1] >= u2_0)
        {

#line 179
            hi_0 = mid_1;

#line 179
        }
        else
        {

#line 179
            lo_0 = mid_1 + 1U;

#line 179
        }

#line 176
    }

#line 185
    float phi_0 = ((float(lo_0) + u3_0) / float(w_5) - 0.5f) * 2.0f * 3.1415927410125732f;
    float theta_0 = (float(lo_1) + u4_0) / float(h_4) * 3.1415927410125732f;
    float st_0 = sin(theta_0);

#line 187
    float3 _S41 = envTexel_0(lo_0, lo_1, kernelContext_11);
    *le_0 = _S41;
    float _S42 = lum_0(_S41);

#line 189
    float _S43 = pf_0(26U, kernelContext_11);

#line 189
    *pdf_0 = _S42 * _S43;
    return float3(st_0 * sin(phi_0), cos(theta_0), - st_0 * cos(phi_0));
}


#line 106
float3 sampleVndf_0(float3 wo_0, float alpha_3, float u1_1, float u2_1)
{
    float3 vh_0 = normalize(float3(alpha_3 * wo_0.x, alpha_3 * wo_0.y, wo_0.z));
    float _S44 = vh_0.x;

#line 109
    float _S45 = vh_0.y;

#line 109
    float lensq_0 = _S44 * _S44 + _S45 * _S45;

#line 109
    float3 t1_0;
    if(lensq_0 > 0.0f)
    {

#line 110
        t1_0 = float3(- _S45, _S44, 0.0f) * float3(rsqrt(lensq_0)) ;

#line 110
    }
    else
    {

#line 110
        t1_0 = float3(1.0f, 0.0f, 0.0f);

#line 110
    }

    float r_1 = sqrt(u1_1);
    float phi_1 = 6.2831854820251465f * u2_1;
    float a_2 = r_1 * cos(phi_1);

    float s_3 = 0.5f * (1.0f + vh_0.z);
    float _S46 = 1.0f - a_2 * a_2;

#line 117
    float b_1 = (1.0f - s_3) * sqrt(_S46) + s_3 * (r_1 * sin(phi_1));
    float3 nh_0 = float3(a_2)  * t1_0 + float3(b_1)  * cross(vh_0, t1_0) + float3(sqrt(max(0.0f, _S46 - b_1 * b_1)))  * vh_0;
    return normalize(float3(alpha_3 * nh_0.x, alpha_3 * nh_0.y, max(0.0f, nh_0.z)));
}


#line 58
float3 cosineLocal_0(float u1_2, float u2_2)
{
    float r_2 = sqrt(u1_2);
    float phi_2 = 6.2831854820251465f * u2_2;
    return float3(r_2 * cos(phi_2), r_2 * sin(phi_2), sqrt(max(0.0f, 1.0f - u1_2)));
}


#line 295
[[kernel]] void pathtrace(uint3 tid_0 [[thread_position_in_grid]], uint device* params_1 [[buffer(6)]], metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_1 [[buffer(0)]], float device* envPixels_1 [[buffer(10)]], uint device* instances_1 [[buffer(3)]], uint device* indices_1 [[buffer(2)]], float device* positions_1 [[buffer(1)]], float device* materials_1 [[buffer(4)]], float device* uvs_1 [[buffer(13)]], uint device* texInfo_1 [[buffer(15)]], float device* texels_1 [[buffer(14)]], float device* emitters_1 [[buffer(8)]], uint device* lights_1 [[buffer(5)]], float device* emitCdf_1 [[buffer(9)]], float device* envMarginal_1 [[buffer(11)]], float device* envCond_1 [[buffer(12)]], float device* accum_1 [[buffer(7)]])
{

#line 295
    float3 radiance_0;

#line 295
    float dist_0;

#line 295
    float3 wi_0;

#line 295
    float3 li_0;

#line 295
    thread KernelContext_0 kernelContext_12;

#line 295
    (&kernelContext_12)->params_0 = params_1;

#line 295
    (&kernelContext_12)->scene_0 = scene_1;

#line 295
    (&kernelContext_12)->envPixels_0 = envPixels_1;

#line 295
    (&kernelContext_12)->instances_0 = instances_1;

#line 295
    (&kernelContext_12)->indices_0 = indices_1;

#line 295
    (&kernelContext_12)->positions_0 = positions_1;

#line 295
    (&kernelContext_12)->materials_0 = materials_1;

#line 295
    (&kernelContext_12)->uvs_0 = uvs_1;

#line 295
    (&kernelContext_12)->texInfo_0 = texInfo_1;

#line 295
    (&kernelContext_12)->texels_0 = texels_1;

#line 295
    (&kernelContext_12)->emitters_0 = emitters_1;

#line 295
    (&kernelContext_12)->lights_0 = lights_1;

#line 295
    (&kernelContext_12)->emitCdf_0 = emitCdf_1;

#line 295
    (&kernelContext_12)->envMarginal_0 = envMarginal_1;

#line 295
    (&kernelContext_12)->envCond_0 = envCond_1;

#line 295
    (&kernelContext_12)->accum_0 = accum_1;

    uint w_6 = params_1[int(0)];
    uint h_5 = params_1[int(1)];
    uint _S47 = tid_0.x;

#line 299
    bool misPrev_0;

#line 299
    if(_S47 >= w_6)
    {

#line 299
        misPrev_0 = true;

#line 299
    }
    else
    {

#line 299
        misPrev_0 = (tid_0.y) >= h_5;

#line 299
    }

#line 299
    if(misPrev_0)
    {

#line 300
        return;
    }

#line 301
    uint _S48 = tid_0.y;

#line 301
    uint pixel_0 = _S48 * w_6 + _S47;
    thread Rng_0 rng_0;
    (&rng_0)->state_0 = pcg_0(pixel_0 ^ (pcg_0((&kernelContext_12)->params_0[int(6)] * 2654435769U + 2135587861U)));

#line 303
    float _S49 = pf_0(2U, &kernelContext_12);



    float _S50 = float(w_6);

#line 307
    float _S51 = float(h_5);

#line 307
    float aspect_0 = _S50 / _S51;
    float _S52 = float(_S47);

#line 308
    float _S53 = Rng_next_0(&rng_0);

#line 308
    float u_0 = (2.0f * (_S52 + _S53) / _S50 - 1.0f) * aspect_0 * _S49;
    float _S54 = float(_S48);

#line 309
    float _S55 = Rng_next_0(&rng_0);
    float3 _S56 = float3(u_0, (1.0f - 2.0f * (_S54 + _S55) / _S51) * _S49, -1.0f);

#line 310
    float _S57 = pf_0(4U, &kernelContext_12);

#line 310
    float3 focal_0 = _S56 * float3(_S57) ;

#line 310
    float _S58 = pf_0(3U, &kernelContext_12);
    float _S59 = Rng_next_0(&rng_0);

#line 311
    float lensR_0 = _S58 * sqrt(_S59);
    float _S60 = Rng_next_0(&rng_0);

#line 312
    float lensA_0 = 6.2831854820251465f * _S60;
    float _S61 = lensR_0 * cos(lensA_0);

#line 313
    float _S62 = lensR_0 * sin(lensA_0);
    float3 _S63 = normalize(focal_0 - float3(_S61, _S62, 0.0f));
    thread float3 org_0;

#line 315
    thread float3 dir_0;

#line 315
    uint r_3 = 0U;
    for(;;)
    {

#line 316
        if(r_3 < 3U)
        {
        }
        else
        {

#line 316
            break;
        }
        uint _S64 = 4U * r_3;

#line 318
        uint _S65 = 8U + _S64;

#line 318
        uint _S66 = 9U + _S64;

#line 318
        uint _S67 = 10U + _S64;

#line 318
        org_0[r_3] = (as_type<float>(((&kernelContext_12)->params_0[_S65]))) * _S61 + (as_type<float>(((&kernelContext_12)->params_0[_S66]))) * _S62 + (as_type<float>(((&kernelContext_12)->params_0[_S67]))) * 0.0f + (as_type<float>(((&kernelContext_12)->params_0[11U + _S64])));
        dir_0[r_3] = (as_type<float>(((&kernelContext_12)->params_0[_S65]))) * _S63.x + (as_type<float>(((&kernelContext_12)->params_0[_S66]))) * _S63.y + (as_type<float>(((&kernelContext_12)->params_0[_S67]))) * _S63.z;

#line 316
        r_3 = r_3 + 1U;

#line 316
    }

#line 321
    dir_0 = normalize(dir_0);

#line 321
    float _S68 = pf_0(20U, &kernelContext_12);

#line 321
    float _S69 = pf_0(21U, &kernelContext_12);

#line 321
    float _S70 = pf_0(22U, &kernelContext_12);

    float3 _S71 = float3(_S68, _S69, _S70);
    float3 _S72 = float3(0.0f) ;
    float3 _S73 = float3(1.0f) ;
    uint _S74 = (&kernelContext_12)->params_0[int(5)];
    uint _S75 = (&kernelContext_12)->params_0[int(7)];
    uint emitterCount_0 = (&kernelContext_12)->params_0[int(23)];

    bool hasEnv_0 = (&kernelContext_12)->params_0[int(24)] > 0U;

#line 330
    float _S76;

    if(hasEnv_0)
    {

#line 332
        if(emitterCount_0 > 0U)
        {

#line 332
            _S76 = 0.5f;

#line 332
        }
        else
        {

#line 332
            _S76 = 1.0f;

#line 332
        }

#line 332
    }
    else
    {

#line 332
        _S76 = 0.0f;

#line 332
    }

#line 332
    misPrev_0 = false;

#line 332
    float qPrev_0 = 0.0f;

#line 332
    uint depth_0 = 0U;

#line 332
    float3 thr_0 = _S73;

#line 332
    float3 radiance_1 = _S72;

#line 332
    float pathLen_0 = 0.0f;

#line 337
    for(;;)
    {

#line 337
        if(depth_0 < _S75)
        {
        }
        else
        {

#line 337
            radiance_0 = radiance_1;

#line 337
            break;
        }
        thread RayDesc_0 ray_1;
        (&ray_1)->Origin_0 = org_0;
        (&ray_1)->Direction_0 = dir_0;
        (&ray_1)->TMin_0 = 0.0f;
        (&ray_1)->TMax_0 = 1.00000001504746622e+30f;
        thread raytracing::intersection_query<raytracing::triangle_data, raytracing::instancing> q_1;
        (&q_1)->reset({ (ray_1.Origin_0), (ray_1.Direction_0), (ray_1.TMin_0), (ray_1.TMax_0) }, ((&kernelContext_12)->scene_0), (255U), _slang_ray_flags_to_intersection_params((1U)));
        for(;;)
        {

#line 346
            bool _S77 = ((&q_1)->next());

#line 346
            if(_S77)
            {
            }
            else
            {

#line 346
                break;
            }

#line 346
        }

        uint _S78 = (_slang_committed_intersection_type_to_uint((&q_1)->get_committed_intersection_type()));

#line 348
        float wB_0;

#line 348
        if(_S78 != 1U)
        {

            float3 radiance_2 = radiance_1 + thr_0 * _S71;
            if(hasEnv_0)
            {

                if(misPrev_0)
                {

#line 355
                    float _S79 = envPdf_0(dir_0, &kernelContext_12);

                    float pl_0 = _S76 * _S79;
                    float _S80 = qPrev_0 * qPrev_0;

#line 358
                    float den_0 = _S80 + pl_0 * pl_0;
                    if(den_0 > 0.0f)
                    {

#line 359
                        _S76 = _S80 / den_0;

#line 359
                    }
                    else
                    {

#line 359
                        _S76 = 1.0f;

#line 359
                    }

#line 359
                    wB_0 = _S76;

#line 355
                }
                else
                {

#line 355
                    wB_0 = 1.0f;

#line 355
                }

#line 355
                float3 _S81 = envRadiance_0(dir_0, &kernelContext_12);

#line 355
                radiance_0 = radiance_2 + thr_0 * _S81 * float3(wB_0) ;

#line 352
            }
            else
            {

#line 352
                radiance_0 = radiance_2;

#line 352
            }

#line 363
            break;
        }

        uint _S82 = ((&q_1)->get_committed_instance_id());

#line 366
        uint inst_0 = _S82 * 16U;
        uint _S83 = (&kernelContext_12)->instances_0[inst_0 + 1U];

#line 367
        uint _S84 = ((&q_1)->get_committed_primitive_id());

#line 367
        uint tri_0 = _S83 + 3U * _S84;
        uint vo_0 = (&kernelContext_12)->instances_0[inst_0];
        uint _S85 = inst_0 + 4U;

#line 369
        float3 _S86 = vertexPos_0((&kernelContext_12)->indices_0[tri_0] + vo_0, &kernelContext_12);

#line 369
        float3 _S87 = transformPoint_0(_S85, _S86, &kernelContext_12);
        uint _S88 = tri_0 + 1U;

#line 370
        float3 _S89 = vertexPos_0((&kernelContext_12)->indices_0[_S88] + vo_0, &kernelContext_12);

#line 370
        float3 _S90 = transformPoint_0(_S85, _S89, &kernelContext_12);
        uint _S91 = tri_0 + 2U;

#line 371
        float3 _S92 = vertexPos_0((&kernelContext_12)->indices_0[_S91] + vo_0, &kernelContext_12);

#line 371
        float3 _S93 = transformPoint_0(_S85, _S92, &kernelContext_12);

        float3 _S94 = _S90 - _S87;

#line 373
        float3 _S95 = _S93 - _S87;

#line 373
        float3 _S96 = cross(_S94, _S95);

#line 373
        float3 nOut_0 = normalize(_S96);
        float3 wo_1 = - dir_0;
        bool outside_0 = (dot(nOut_0, wo_1)) > 0.0f;

#line 375
        float3 n_1;
        if(outside_0)
        {

#line 376
            n_1 = nOut_0;

#line 376
        }
        else
        {

#line 376
            n_1 = - nOut_0;

#line 376
        }
        float pHitT_0 = ((&q_1)->get_committed_distance());
        float pathLen_1 = pathLen_0 + pHitT_0;
        float3 hit_0 = org_0 + dir_0 * float3(pHitT_0) ;

        float3 p_1 = hit_0 + n_1 * float3(9.9999997473787516e-05f) ;

        uint mi_0 = (&kernelContext_12)->instances_0[inst_0 + 2U] * 16U;
        float3 albedo_1 = float3((&kernelContext_12)->materials_0[mi_0], (&kernelContext_12)->materials_0[mi_0 + 1U], (&kernelContext_12)->materials_0[mi_0 + 2U]);

        uint texBase_0 = uint((&kernelContext_12)->materials_0[mi_0 + 10U]);
        uint texMR_0 = uint((&kernelContext_12)->materials_0[mi_0 + 11U]);
        uint texEm_0 = uint((&kernelContext_12)->materials_0[mi_0 + 12U]);
        float2 _S97 = float2(1.0f) ;

#line 389
        float3 albedo_2;

#line 389
        float3 texEmission_0;

#line 389
        float2 texRM_0;

        if((texBase_0 + texMR_0 + texEm_0) > 0U)
        {
            float2 uv0_0 = float2((&kernelContext_12)->uvs_0[2U * ((&kernelContext_12)->indices_0[tri_0] + vo_0)], (&kernelContext_12)->uvs_0[2U * ((&kernelContext_12)->indices_0[tri_0] + vo_0) + 1U]);

#line 398
            float3 e3_0 = hit_0 - _S87;
            float d11_0 = dot(_S94, _S94);
            float d12_0 = dot(_S94, _S95);
            float d22_0 = dot(_S95, _S95);
            float _S98 = max(d11_0 * d22_0 - d12_0 * d12_0, 9.99999968265522539e-21f);
            float _S99 = dot(e3_0, _S94);

#line 403
            float _S100 = dot(e3_0, _S95);

            float2 _S101 = float2((&kernelContext_12)->uvs_0[2U * ((&kernelContext_12)->indices_0[_S88] + vo_0)], (&kernelContext_12)->uvs_0[2U * ((&kernelContext_12)->indices_0[_S88] + vo_0) + 1U]) - uv0_0;

#line 405
            float2 _S102 = float2((&kernelContext_12)->uvs_0[2U * ((&kernelContext_12)->indices_0[_S91] + vo_0)], (&kernelContext_12)->uvs_0[2U * ((&kernelContext_12)->indices_0[_S91] + vo_0) + 1U]) - uv0_0;

#line 405
            float2 uv_2 = uv0_0 + float2(((d22_0 * _S99 - d12_0 * _S100) / _S98))  * _S101 + float2(((d11_0 * _S100 - d12_0 * _S99) / _S98))  * _S102;


            float uvPerWorld_0 = sqrt(abs(_S101.x * _S102.y - _S101.y * _S102.x) / max(length(_S96), 9.99999968265522539e-21f));

#line 408
            float _S103 = pf_0(27U, &kernelContext_12);
            float footprint_1 = pathLen_1 * _S103 / max(abs(dot(nOut_0, dir_0)), 0.10000000149011612f) * uvPerWorld_0;
            if(texBase_0 > 0U)
            {

#line 410
                float3 _S104 = sampleTexture_0(texBase_0 - 1U, uv_2, footprint_1, &kernelContext_12);

#line 410
                albedo_2 = albedo_1 * _S104;

#line 410
            }
            else
            {

#line 410
                albedo_2 = albedo_1;

#line 410
            }

            if(texMR_0 > 0U)
            {

#line 412
                float3 _S105 = sampleTexture_0(texMR_0 - 1U, uv_2, footprint_1, &kernelContext_12);

#line 412
                texRM_0 = _S105.yz;

#line 412
            }
            else
            {

#line 412
                texRM_0 = _S97;

#line 412
            }

            if(texEm_0 > 0U)
            {

#line 414
                float3 _S106 = sampleTexture_0(texEm_0 - 1U, uv_2, footprint_1, &kernelContext_12);

#line 414
                texEmission_0 = _S106;

#line 414
            }
            else
            {

#line 414
                texEmission_0 = _S73;

#line 414
            }

#line 391
        }
        else
        {

#line 391
            texEmission_0 = _S73;

#line 391
            texRM_0 = _S97;

#line 391
            albedo_2 = albedo_1;

#line 391
        }

#line 418
        float3 le_1 = float3((&kernelContext_12)->materials_0[mi_0 + 3U], (&kernelContext_12)->materials_0[mi_0 + 4U], (&kernelContext_12)->materials_0[mi_0 + 5U]) * texEmission_0;

#line 418
        bool chooseEnv_0;

#line 418
        float3 radiance_3;
        if(any(le_1 > (float3(0.0f) )))
        {

            uint eb_0 = (&kernelContext_12)->instances_0[inst_0 + 3U];
            if(misPrev_0)
            {

#line 423
                chooseEnv_0 = eb_0 != 0U;

#line 423
            }
            else
            {

#line 423
                chooseEnv_0 = false;

#line 423
            }

#line 423
            if(chooseEnv_0)
            {
                uint _S107 = eb_0 - 1U;

#line 425
                uint _S108 = ((&q_1)->get_committed_primitive_id());

#line 425
                uint e_0 = (_S107 + _S108) * 16U;

                float pl_1 = (1.0f - _S76) * (&kernelContext_12)->emitters_0[e_0 + 13U] * pHitT_0 * pHitT_0 / ((&kernelContext_12)->emitters_0[e_0 + 12U] * max(abs(dot(nOut_0, dir_0)), 9.9999997473787516e-05f));
                float _S109 = qPrev_0 * qPrev_0;

#line 428
                wB_0 = _S109 / (_S109 + pl_1 * pl_1);

#line 423
            }
            else
            {

#line 423
                wB_0 = 1.0f;

#line 423
            }

#line 423
            radiance_3 = radiance_1 + thr_0 * le_1 * float3(wB_0) ;

#line 419
        }
        else
        {

#line 419
            radiance_3 = radiance_1;

#line 419
        }

#line 432
        float metallic_1 = (&kernelContext_12)->materials_0[mi_0 + 6U] * texRM_0.y;
        float rough_0 = (&kernelContext_12)->materials_0[mi_0 + 7U] * texRM_0.x;
        float transmission_1 = (&kernelContext_12)->materials_0[mi_0 + 8U];
        float ior_1 = (&kernelContext_12)->materials_0[mi_0 + 9U];
        float _S110 = max(rough_0 * rough_0, 0.0010000000474974513f);
        if(outside_0)
        {

#line 437
            wB_0 = ior_1;

#line 437
        }
        else
        {

#line 437
            wB_0 = 1.0f / ior_1;

#line 437
        }

        thread float3 T_0;

#line 439
        thread float3 B_0;
        basis_0(n_1, &T_0, &B_0);
        float _S111 = max(dot(wo_1, n_1), 9.9999997473787516e-05f);

#line 441
        float3 woL_2 = float3(dot(wo_1, T_0), dot(wo_1, B_0), _S111);
        float fSel_1 = fresnelDielectric_0(_S111, ior_1);
        thread Surface_0 surf_0;
        (&surf_0)->albedo_0 = albedo_2;
        (&surf_0)->metallic_0 = metallic_1;
        (&surf_0)->alpha_2 = _S110;
        (&surf_0)->transmission_0 = transmission_1;
        (&surf_0)->ior_0 = ior_1;
        (&surf_0)->eta_1 = wB_0;
        (&surf_0)->fSel_0 = fSel_1;

#line 450
        uint li_1 = 0U;

#line 450
        radiance_0 = radiance_3;



        for(;;)
        {

#line 454
            if(li_1 < _S74)
            {
            }
            else
            {

#line 454
                break;
            }
            uint o_4 = li_1 * 8U;
            float3 col_0 = float3((as_type<float>(((&kernelContext_12)->lights_0[o_4 + 1U]))), (as_type<float>(((&kernelContext_12)->lights_0[o_4 + 2U]))), (as_type<float>(((&kernelContext_12)->lights_0[o_4 + 3U])))) * float3((as_type<float>(((&kernelContext_12)->lights_0[o_4 + 4U])))) ;
            float3 vec_0 = float3((as_type<float>(((&kernelContext_12)->lights_0[o_4 + 5U]))), (as_type<float>(((&kernelContext_12)->lights_0[o_4 + 6U]))), (as_type<float>(((&kernelContext_12)->lights_0[o_4 + 7U]))));



            if((&kernelContext_12)->lights_0[o_4] == 0U)
            {
                float3 toL_0 = vec_0 - p_1;
                float d2_0 = dot(toL_0, toL_0);
                float dist_1 = sqrt(d2_0);

                float3 _S112 = col_0 / float3(d2_0) ;

#line 468
                wi_0 = toL_0 / float3(dist_1) ;

#line 468
                dist_0 = dist_1;

#line 468
                li_0 = _S112;

#line 462
            }
            else
            {

#line 462
                wi_0 = - normalize(vec_0);

#line 462
                dist_0 = 1.00000001504746622e+30f;

#line 462
                li_0 = col_0;

#line 462
            }

#line 476
            float c_2 = dot(n_1, wi_0);
            if(c_2 > 0.0f)
            {

#line 477
                bool _S113 = occluded_0(p_1, wi_0, dist_0 - 0.0010000000474974513f, &kernelContext_12);

#line 477
                chooseEnv_0 = !_S113;

#line 477
            }
            else
            {

#line 477
                chooseEnv_0 = false;

#line 477
            }

#line 477
            if(chooseEnv_0)
            {
                float3 _S114 = float3(dot(wi_0, T_0), dot(wi_0, B_0), c_2);

#line 479
                thread Surface_0 _S115 = surf_0;

#line 479
                float3 _S116 = evalReflective_0(&_S115, woL_2, _S114);

#line 479
                radiance_0 = radiance_0 + thr_0 * _S116 * li_0;

#line 477
            }

#line 454
            li_1 = li_1 + 1U;

#line 454
        }

#line 485
        float chooseLight_0 = Rng_next_0(&rng_0);
        if(hasEnv_0)
        {

#line 486
            chooseEnv_0 = chooseLight_0 < _S76;

#line 486
        }
        else
        {

#line 486
            chooseEnv_0 = false;

#line 486
        }

#line 486
        bool _S117;
        if(emitterCount_0 > 0U)
        {

#line 487
            _S117 = !chooseEnv_0;

#line 487
        }
        else
        {

#line 487
            _S117 = false;

#line 487
        }

#line 487
        bool ok_0;

#line 487
        bool refracted_0;

#line 487
        if(_S117)
        {
            float _S118 = Rng_next_0(&rng_0);
            float ua_0 = Rng_next_0(&rng_0);
            float ub_0 = Rng_next_0(&rng_0);

            uint _S119 = emitterCount_0 - 1U;

#line 493
            uint lo_2 = 0U;

#line 493
            uint hi_1 = _S119;
            for(;;)
            {

#line 494
                if(lo_2 < hi_1)
                {
                }
                else
                {

#line 494
                    break;
                }
                uint mid_2 = (lo_2 + hi_1) / 2U;
                if((&kernelContext_12)->emitCdf_0[mid_2] >= _S118)
                {

#line 497
                    hi_1 = mid_2;

#line 497
                }
                else
                {

#line 497
                    lo_2 = mid_2 + 1U;

#line 497
                }

#line 494
            }

#line 502
            uint e_1 = lo_2 * 16U;
            float3 a_3 = float3((&kernelContext_12)->emitters_0[e_1], (&kernelContext_12)->emitters_0[e_1 + 1U], (&kernelContext_12)->emitters_0[e_1 + 2U]);
            float3 b_2 = float3((&kernelContext_12)->emitters_0[e_1 + 3U], (&kernelContext_12)->emitters_0[e_1 + 4U], (&kernelContext_12)->emitters_0[e_1 + 5U]);
            float3 c_3 = float3((&kernelContext_12)->emitters_0[e_1 + 6U], (&kernelContext_12)->emitters_0[e_1 + 7U], (&kernelContext_12)->emitters_0[e_1 + 8U]);
            float su_0 = sqrt(ua_0);

            float3 toL_1 = a_3 * float3((1.0f - su_0))  + b_2 * float3((su_0 * (1.0f - ub_0)))  + c_3 * float3((su_0 * ub_0))  - p_1;
            float d2_1 = dot(toL_1, toL_1);
            float dist_2 = sqrt(d2_1);
            float3 wi_1 = toL_1 / float3(dist_2) ;
            float cosl_0 = abs(dot(normalize(cross(b_2 - a_3, c_3 - a_3)), wi_1));
            float cosi_1 = dot(n_1, wi_1);
            if(cosi_1 > 0.0f)
            {

#line 514
                ok_0 = cosl_0 > 9.9999997473787516e-06f;

#line 514
            }
            else
            {

#line 514
                ok_0 = false;

#line 514
            }

#line 514
            if(ok_0)
            {

#line 514
                bool _S120 = occluded_0(p_1, wi_1, dist_2 * 0.99900001287460327f, &kernelContext_12);

#line 514
                refracted_0 = !_S120;

#line 514
            }
            else
            {

#line 514
                refracted_0 = false;

#line 514
            }

#line 514
            if(refracted_0)
            {
                float pl_2 = (1.0f - _S76) * (&kernelContext_12)->emitters_0[e_1 + 13U] * d2_1 / ((&kernelContext_12)->emitters_0[e_1 + 12U] * cosl_0);
                float3 wiL_2 = float3(dot(wi_1, T_0), dot(wi_1, B_0), cosi_1);

#line 517
                thread Surface_0 _S121 = surf_0;

#line 517
                float _S122 = reflectivePdf_0(&_S121, woL_2, wiL_2);

                float _S123 = pl_2 * pl_2;

#line 519
                float wl_0 = _S123 / (_S123 + _S122 * _S122);

#line 519
                thread Surface_0 _S124 = surf_0;

#line 519
                float3 _S125 = evalReflective_0(&_S124, woL_2, wiL_2);

#line 519
                wi_0 = radiance_0 + thr_0 * _S125 * float3((&kernelContext_12)->emitters_0[e_1 + 9U], (&kernelContext_12)->emitters_0[e_1 + 10U], (&kernelContext_12)->emitters_0[e_1 + 11U]) / float3(pl_2)  * float3(wl_0) ;

#line 514
            }
            else
            {

#line 514
                wi_0 = radiance_0;

#line 514
            }

#line 487
        }
        else
        {

#line 487
            wi_0 = radiance_0;

#line 487
        }

#line 524
        if(chooseEnv_0)
        {
            float e1_0 = Rng_next_0(&rng_0);
            float e2_0 = Rng_next_0(&rng_0);
            float e3_1 = Rng_next_0(&rng_0);
            float e4_0 = Rng_next_0(&rng_0);
            thread float pdfE_0;
            thread float3 leE_0;

#line 531
            float3 _S126 = envSample_0(e1_0, e2_0, e3_1, e4_0, &pdfE_0, &leE_0, &kernelContext_12);

            float cosi_2 = dot(n_1, _S126);
            if(pdfE_0 > 0.0f)
            {

#line 534
                ok_0 = cosi_2 > 0.0f;

#line 534
            }
            else
            {

#line 534
                ok_0 = false;

#line 534
            }

#line 534
            if(ok_0)
            {

#line 534
                bool _S127 = occluded_0(p_1, _S126, 1.00000001504746622e+30f, &kernelContext_12);

#line 534
                refracted_0 = !_S127;

#line 534
            }
            else
            {

#line 534
                refracted_0 = false;

#line 534
            }

#line 534
            if(refracted_0)
            {
                float pl_3 = _S76 * pdfE_0;
                float3 wiL_3 = float3(dot(_S126, T_0), dot(_S126, B_0), cosi_2);

#line 537
                thread Surface_0 _S128 = surf_0;

#line 537
                float _S129 = reflectivePdf_0(&_S128, woL_2, wiL_3);

                float _S130 = pl_3 * pl_3;

#line 539
                float wl_1 = _S130 / (_S130 + _S129 * _S129);

#line 539
                thread Surface_0 _S131 = surf_0;

#line 539
                float3 _S132 = evalReflective_0(&_S131, woL_2, wiL_3);

#line 539
                li_0 = wi_0 + thr_0 * _S132 * leE_0 / float3(pl_3)  * float3(wl_1) ;

#line 534
            }
            else
            {

#line 534
                li_0 = wi_0;

#line 534
            }

#line 524
        }
        else
        {

#line 524
            li_0 = wi_0;

#line 524
        }

#line 546
        float lobe_0 = Rng_next_0(&rng_0);
        float u1_3 = Rng_next_0(&rng_0);
        float u2_3 = Rng_next_0(&rng_0);
        float u3_1 = Rng_next_0(&rng_0);

#line 549
        float3 wiL_4;

#line 549
        float3 w_7;

#line 554
        if(lobe_0 < metallic_1)
        {
            float3 h_6 = sampleVndf_0(woL_2, _S110, u1_3, u2_3);
            float woh_0 = dot(woL_2, h_6);
            float3 wiL_5 = float3((2.0f * woh_0))  * h_6 - woL_2;
            float _S133 = wiL_5.z;
            float3 _S134 = schlick_0(albedo_2, woh_0) * float3(G1_0(max(_S133, 0.0f), _S110)) ;

#line 560
            ok_0 = _S133 > 0.0f;

#line 560
            refracted_0 = false;

#line 560
            wiL_4 = wiL_5;

#line 560
            w_7 = _S134;

#line 554
        }
        else
        {

#line 562
            if(lobe_0 < (metallic_1 + (1.0f - metallic_1) * transmission_1))
            {
                float3 h_7 = sampleVndf_0(woL_2, _S110, u1_3, u2_3);
                float woh_1 = dot(woL_2, h_7);
                if(u3_1 < (fresnelDielectric_0(woh_1, wB_0)))
                {
                    float3 wiL_6 = float3((2.0f * woh_1))  * h_7 - woL_2;
                    float _S135 = wiL_6.z;
                    float3 _S136 = float3(G1_0(max(_S135, 0.0f), _S110)) ;

#line 570
                    ok_0 = _S135 > 0.0f;

#line 570
                    refracted_0 = false;

#line 570
                    wiL_4 = wiL_6;

#line 570
                    w_7 = _S136;

#line 566
                }
                else
                {

#line 574
                    float r_4 = 1.0f / wB_0;
                    float k_1 = 1.0f - r_4 * r_4 * (1.0f - woh_1 * woh_1);

#line 575
                    float3 _S137 = float3(r_4) ;
                    float3 wiL_7 = - woL_2 * _S137 + float3((r_4 * woh_1 - sqrt(max(k_1, 0.0f))))  * h_7;
                    float _S138 = wiL_7.z;

#line 577
                    if(_S138 < 0.0f)
                    {

#line 577
                        ok_0 = k_1 > 0.0f;

#line 577
                    }
                    else
                    {

#line 577
                        ok_0 = false;

#line 577
                    }


                    float3 _S139 = albedo_2 * float3(G1_0(max(- _S138, 0.0f), _S110))  * _S137 * _S137;

#line 580
                    refracted_0 = true;

#line 580
                    wiL_4 = wiL_7;

#line 580
                    w_7 = _S139;

#line 566
                }

#line 562
            }
            else
            {

#line 583
                if(u3_1 < fSel_1)
                {
                    float3 h_8 = sampleVndf_0(woL_2, _S110, u1_3, u2_3);
                    float woh_2 = dot(woL_2, h_8);
                    float3 wiL_8 = float3((2.0f * woh_2))  * h_8 - woL_2;
                    float _S140 = wiL_8.z;
                    float3 _S141 = float3((fresnelDielectric_0(woh_2, ior_1) / fSel_1 * G1_0(max(_S140, 0.0f), _S110))) ;

#line 589
                    ok_0 = _S140 > 0.0f;

#line 589
                    wiL_4 = wiL_8;

#line 589
                    w_7 = _S141;

#line 583
                }
                else
                {

#line 593
                    float3 _S142 = cosineLocal_0(u1_3, u2_3);

#line 593
                    ok_0 = true;

#line 593
                    wiL_4 = _S142;

#line 593
                    w_7 = albedo_2;

#line 583
                }

#line 583
                refracted_0 = false;

#line 562
            }

#line 554
        }

#line 596
        if(!ok_0)
        {

#line 596
            radiance_0 = li_0;
            break;
        }

#line 598
        bool _S143 = !refracted_0;
        if(refracted_0)
        {

#line 599
            qPrev_0 = 0.0f;

#line 599
        }
        else
        {

#line 599
            thread Surface_0 _S144 = surf_0;

#line 599
            float _S145 = reflectivePdf_0(&_S144, woL_2, wiL_4);

#line 599
            qPrev_0 = _S145;

#line 599
        }

        float _S146 = wiL_4.z;

#line 601
        dir_0 = normalize(float3(wiL_4.x)  * T_0 + float3(wiL_4.y)  * B_0 + float3(_S146)  * n_1);
        if(_S146 > 0.0f)
        {

#line 602
            dist_0 = 9.9999997473787516e-05f;

#line 602
        }
        else
        {

#line 602
            dist_0 = -9.9999997473787516e-05f;

#line 602
        }

#line 602
        org_0 = hit_0 + n_1 * float3(dist_0) ;
        float3 thr_1 = thr_0 * w_7;

        if(depth_0 >= 2U)
        {
            float pr_0 = clamp(max(thr_1.x, max(thr_1.y, thr_1.z)), 0.05000000074505806f, 0.94999998807907104f);
            float _S147 = Rng_next_0(&rng_0);

#line 608
            if(_S147 > pr_0)
            {

#line 608
                radiance_0 = li_0;
                break;
            }

#line 609
            thr_0 = thr_1 / float3(pr_0) ;

#line 605
        }
        else
        {

#line 605
            thr_0 = thr_1;

#line 605
        }

#line 337
        uint _S148 = depth_0 + 1U;

#line 337
        misPrev_0 = _S143;

#line 337
        depth_0 = _S148;

#line 337
        radiance_1 = li_0;

#line 337
        pathLen_0 = pathLen_1;

#line 337
    }

#line 614
    if(any(isnan(radiance_0)))
    {

#line 614
        misPrev_0 = true;

#line 614
    }
    else
    {

#line 614
        misPrev_0 = any(isinf(radiance_0));

#line 614
    }

#line 614
    if(misPrev_0)
    {

#line 614
        radiance_0 = _S72;

#line 614
    }


    uint o_5 = 3U * pixel_0;
    float device* _S149 = (&kernelContext_12)->accum_0+o_5;

#line 618
    *_S149 = *_S149 + radiance_0.x;
    float device* _S150 = (&kernelContext_12)->accum_0+(o_5 + 1U);

#line 619
    *_S150 = *_S150 + radiance_0.y;
    float device* _S151 = (&kernelContext_12)->accum_0+(o_5 + 2U);

#line 620
    *_S151 = *_S151 + radiance_0.z;
    return;
}

