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
            

#line 27 "shaders/pathtrace.slang"
uint pcg_0(uint v_0)
{
    uint s_0 = v_0 * 747796405U + 2891336453U;
    uint w_0 = ((s_0 >> ((s_0 >> 28U) + 4U)) ^ s_0) * 277803737U;
    return (w_0 >> 22U) ^ w_0;
}


#line 670
struct KernelContext_0
{
    uint device* params_0;
    metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_0;
    float device* envPixels_0;
    uint device* instances_0;
    uint device* indices_0;
    float device* positions_0;
    float device* vnormals_0;
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


#line 44
float pf_0(uint i_0, KernelContext_0 thread* kernelContext_0)
{

#line 44
    return (as_type<float>((kernelContext_0->params_0[i_0])));
}


#line 34
struct Rng_0
{
    uint state_0;
};


#line 37
float Rng_next_0(Rng_0 thread* this_0)
{
    uint _S1 = pcg_0(this_0->state_0);

#line 39
    this_0->state_0 = _S1;
    return float(_S1 >> 8U) * 5.9604644775390625e-08f;
}


#line 148
void envCoords_0(float3 d_0, uint thread* i_1, uint thread* j_0, KernelContext_0 thread* kernelContext_1)
{
    uint w_1 = kernelContext_1->params_0[int(24)];
    uint h_0 = kernelContext_1->params_0[int(25)];

    float v_1 = acos(clamp(d_0.y, -1.0f, 1.0f)) / 3.1415927410125732f;
    *i_1 = min(uint((atan2(d_0.x, - d_0.z) * 0.15915493667125702f + 0.5f) * float(w_1)), w_1 - 1U);
    *j_0 = min(uint(v_1 * float(h_0)), h_0 - 1U);
    return;
}


#line 141
float3 envTexel_0(uint i_2, uint j_1, KernelContext_0 thread* kernelContext_2)
{
    uint o_0 = 3U * (j_1 * kernelContext_2->params_0[int(24)] + i_2);
    return float3(kernelContext_2->envPixels_0[o_0], kernelContext_2->envPixels_0[o_0 + 1U], kernelContext_2->envPixels_0[o_0 + 2U]);
}


#line 139
float lum_0(float3 c_0)
{

#line 139
    return dot(c_0, float3(0.2125999927520752f, 0.71520000696182251f, 0.072200000286102295f));
}


#line 167
float envPdf_0(float3 d_1, KernelContext_0 thread* kernelContext_3)
{
    thread uint i_3;

#line 169
    thread uint j_2;

#line 169
    envCoords_0(d_1, &i_3, &j_2, kernelContext_3);

#line 169
    float3 _S2 = envTexel_0(i_3, j_2, kernelContext_3);

    float _S3 = lum_0(_S2);

#line 171
    float _S4 = pf_0(26U, kernelContext_3);

#line 171
    return _S3 * _S4;
}


#line 158
float3 envRadiance_0(float3 d_2, KernelContext_0 thread* kernelContext_4)
{
    thread uint i_4;

#line 160
    thread uint j_3;

#line 160
    envCoords_0(d_2, &i_4, &j_3, kernelContext_4);

#line 160
    float3 _S5 = envTexel_0(i_4, j_3, kernelContext_4);

    return _S5;
}


#line 46
float3 vertexPos_0(uint v_2, KernelContext_0 thread* kernelContext_5)
{

#line 46
    uint _S6 = 3U * v_2;

#line 46
    return float3(kernelContext_5->positions_0[_S6], kernelContext_5->positions_0[_S6 + 1U], kernelContext_5->positions_0[_S6 + 2U]);
}


#line 48
float3 transformPoint_0(uint base_0, float3 p_0, KernelContext_0 thread* kernelContext_6)
{
    thread float3 r_0;

#line 50
    uint row_0 = 0U;
    for(;;)
    {

#line 51
        if(row_0 < 3U)
        {
        }
        else
        {

#line 51
            break;
        }
        uint o_1 = base_0 + 4U * row_0;
        r_0[row_0] = (as_type<float>((kernelContext_6->instances_0[o_1]))) * p_0.x + (as_type<float>((kernelContext_6->instances_0[o_1 + 1U]))) * p_0.y + (as_type<float>((kernelContext_6->instances_0[o_1 + 2U]))) * p_0.z + (as_type<float>((kernelContext_6->instances_0[o_1 + 3U])));

#line 51
        row_0 = row_0 + 1U;

#line 51
    }

#line 56
    return r_0;
}


#line 71
float3 vertexNormal_0(uint v_3, KernelContext_0 thread* kernelContext_7)
{

#line 71
    uint _S7 = 3U * v_3;

#line 71
    return float3(kernelContext_7->vnormals_0[_S7], kernelContext_7->vnormals_0[_S7 + 1U], kernelContext_7->vnormals_0[_S7 + 2U]);
}


#line 61
float3 transformNormal_0(uint base_1, float3 n_0, KernelContext_0 thread* kernelContext_8)
{
    float3 r0_0 = float3((as_type<float>((kernelContext_8->instances_0[base_1]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 1U]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 2U]))));
    float3 r1_0 = float3((as_type<float>((kernelContext_8->instances_0[base_1 + 4U]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 5U]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 6U]))));
    float3 r2_0 = float3((as_type<float>((kernelContext_8->instances_0[base_1 + 8U]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 9U]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 10U]))));
    float3 c0_0 = cross(r1_0, r2_0);

#line 66
    float s_1;
    if((dot(r0_0, c0_0)) < 0.0f)
    {

#line 67
        s_1 = -1.0f;

#line 67
    }
    else
    {

#line 67
        s_1 = 1.0f;

#line 67
    }
    return float3(s_1)  * float3(dot(c0_0, n_0), dot(cross(r2_0, r0_0), n_0), dot(cross(r0_0, r1_0), n_0));
}


#line 209
float3 texelAt_0(uint base_2, uint w_2, uint h_1, int x_0, int y_0, KernelContext_0 thread* kernelContext_9)
{
    int _S8 = int(w_2);

#line 211
    int _S9 = x_0 % _S8;

#line 211
    int _S10 = (_S9 + _S8) % _S8;

#line 211
    uint xi_0 = uint(_S10);
    int _S11 = int(h_1);

#line 212
    int _S12 = y_0 % _S11;

#line 212
    int _S13 = (_S12 + _S11) % _S11;
    uint o_2 = 3U * (base_2 + uint(_S13) * w_2 + xi_0);
    return float3(kernelContext_9->texels_0[o_2], kernelContext_9->texels_0[o_2 + 1U], kernelContext_9->texels_0[o_2 + 2U]);
}

float3 bilinear_0(uint base_3, uint w_3, uint h_2, float2 uv_0, KernelContext_0 thread* kernelContext_10)
{
    float fx_0 = uv_0.x * float(w_3) - 0.5f;
    float fy_0 = uv_0.y * float(h_2) - 0.5f;
    int x0_0 = int(floor(fx_0));
    int y0_0 = int(floor(fy_0));
    float tx_0 = fx_0 - float(x0_0);
    float ty_0 = fy_0 - float(y0_0);

#line 224
    float3 _S14 = texelAt_0(base_3, w_3, h_2, x0_0, y0_0, kernelContext_10);
    int _S15 = x0_0 + int(1);

#line 225
    float3 _S16 = texelAt_0(base_3, w_3, h_2, _S15, y0_0, kernelContext_10);

#line 225
    float3 _S17 = float3(tx_0) ;

#line 225
    float3 a_0 = mix(_S14, _S16, _S17);
    int _S18 = y0_0 + int(1);

#line 226
    float3 _S19 = texelAt_0(base_3, w_3, h_2, x0_0, _S18, kernelContext_10);

#line 226
    float3 _S20 = texelAt_0(base_3, w_3, h_2, _S15, _S18, kernelContext_10);
    return mix(a_0, mix(_S19, _S20, _S17), float3(ty_0) );
}


float3 sampleTexture_0(uint tex_0, float2 uv_1, float footprint_0, KernelContext_0 thread* kernelContext_11)
{
    uint ti_0 = tex_0 * 4U;
    uint base_4 = kernelContext_11->texInfo_0[ti_0];
    uint w_4 = kernelContext_11->texInfo_0[ti_0 + 1U];
    uint h_3 = kernelContext_11->texInfo_0[ti_0 + 2U];
    uint levels_0 = kernelContext_11->texInfo_0[ti_0 + 3U];
    float lod_0 = clamp(log2(max(footprint_0 * float(max(w_4, h_3)), 9.99999993922529029e-09f)), 0.0f, float(levels_0 - 1U));
    uint l0_0 = uint(floor(lod_0));
    float t_0 = lod_0 - float(l0_0);

#line 240
    uint lw_0 = w_4;

#line 240
    uint lh_0 = h_3;

#line 240
    uint k_0 = 0U;

#line 240
    uint off_0 = base_4;



    for(;;)
    {

#line 244
        if(k_0 < l0_0)
        {
        }
        else
        {

#line 244
            break;
        }
        uint off_1 = off_0 + lw_0 * lh_0;
        uint _S21 = max(lw_0 / 2U, 1U);
        uint _S22 = max(lh_0 / 2U, 1U);

#line 244
        uint _S23 = k_0 + 1U;

#line 244
        lw_0 = _S21;

#line 244
        lh_0 = _S22;

#line 244
        k_0 = _S23;

#line 244
        off_0 = off_1;

#line 244
    }

#line 244
    float3 _S24 = bilinear_0(off_0, lw_0, lh_0, uv_1, kernelContext_11);

#line 244
    bool _S25;

#line 251
    if((l0_0 + 1U) >= levels_0)
    {

#line 251
        _S25 = true;

#line 251
    }
    else
    {

#line 251
        _S25 = t_0 <= 0.0f;

#line 251
    }

#line 251
    if(_S25)
    {

#line 252
        return _S24;
    }

#line 252
    float3 _S26 = bilinear_0(off_0 + lw_0 * lh_0, max(lw_0 / 2U, 1U), max(lh_0 / 2U, 1U), uv_1, kernelContext_11);


    return mix(_S24, _S26, float3(t_0) );
}


#line 113
void basis_0(float3 n_1, float3 thread* t_1, float3 thread* b_0)
{

#line 113
    float3 a_1;

    if((abs(n_1.x)) > 0.89999997615814209f)
    {

#line 115
        a_1 = float3(0.0f, 1.0f, 0.0f);

#line 115
    }
    else
    {

#line 115
        a_1 = float3(1.0f, 0.0f, 0.0f);

#line 115
    }
    float3 _S27 = normalize(cross(n_1, a_1));

#line 116
    *b_0 = _S27;
    *t_1 = cross(_S27, n_1);
    return;
}


#line 102
float fresnelDielectric_0(float cosi_0, float eta_0)
{
    float s2_0 = (1.0f - cosi_0 * cosi_0) / (eta_0 * eta_0);
    if(s2_0 >= 1.0f)
    {

#line 106
        return 1.0f;
    }

#line 107
    float cost_0 = sqrt(1.0f - s2_0);
    float _S28 = eta_0 * cost_0;

#line 108
    float rs_0 = (cosi_0 - _S28) / (cosi_0 + _S28);
    float _S29 = eta_0 * cosi_0;

#line 109
    float rp_0 = (_S29 - cost_0) / (_S29 + cost_0);
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


#line 295 "shaders/pathtrace.slang"
bool occluded_0(float3 o_3, float3 d_3, float tmax_0, KernelContext_0 thread* kernelContext_12)
{
    thread RayDesc_0 ray_0;
    (&ray_0)->Origin_0 = o_3;
    (&ray_0)->Direction_0 = d_3;
    (&ray_0)->TMin_0 = 0.0f;
    (&ray_0)->TMax_0 = tmax_0;
    thread raytracing::intersection_query<raytracing::triangle_data, raytracing::instancing> q_0;
    (&q_0)->reset({ (ray_0.Origin_0), (ray_0.Direction_0), (ray_0.TMin_0), (ray_0.TMax_0) }, (kernelContext_12->scene_0), (255U), _slang_ray_flags_to_intersection_params((5U)));
    for(;;)
    {

#line 304
        bool _S30 = ((&q_0)->next());

#line 304
        if(_S30)
        {
        }
        else
        {

#line 304
            break;
        }

#line 304
    }
    uint _S31 = (_slang_committed_intersection_type_to_uint((&q_0)->get_committed_intersection_type()));

#line 305
    return _S31 == 1U;
}


#line 87
float D_0(float hz_0, float alpha_0)
{
    float a2_0 = alpha_0 * alpha_0;
    float d_4 = hz_0 * hz_0 * (a2_0 - 1.0f) + 1.0f;
    return a2_0 / (3.1415927410125732f * d_4 * d_4);
}


#line 80
float G1_0(float cosT_0, float alpha_1)
{
    float c2_0 = cosT_0 * cosT_0;

    return 2.0f / (1.0f + sqrt(1.0f + alpha_1 * alpha_1 * ((1.0f - c2_0) / max(c2_0, 9.99999993922529029e-09f))));
}


#line 94
float3 schlick_0(float3 f0_0, float c_1)
{
    float m_0 = 1.0f - saturate(c_1);
    float m2_0 = m_0 * m_0;
    return f0_0 + (float3(1.0f)  - f0_0) * float3((m2_0 * m2_0 * m_0)) ;
}


#line 258
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


float3 evalReflective_0(const Surface_0 thread* s_2, float3 woL_0, float3 wiL_0)
{
    float3 hh_0 = normalize(woL_0 + wiL_0);
    float _S32 = max(dot(woL_0, hh_0), 0.0f);

    float _S33 = woL_0.z;

#line 275
    float _S34 = wiL_0.z;

#line 275
    float core_0 = D_0(hh_0.z, s_2->alpha_2) * G1_0(_S33, s_2->alpha_2) * G1_0(_S34, s_2->alpha_2) / (4.0f * _S33);


    float _S35 = 1.0f - s_2->metallic_0;

#line 278
    float _S36 = 1.0f - s_2->transmission_0;

#line 277
    return float3(s_2->metallic_0)  * schlick_0(s_2->albedo_0, _S32) * float3(core_0)  + float3((_S35 * (s_2->transmission_0 * fresnelDielectric_0(_S32, s_2->eta_1) + _S36 * fresnelDielectric_0(_S32, s_2->ior_0)) * core_0))  + float3((_S35 * _S36 * (1.0f - s_2->fSel_0)))  * s_2->albedo_0 * float3((_S34 / 3.1415927410125732f)) ;
}


#line 284
float reflectivePdf_0(const Surface_0 thread* s_3, float3 woL_1, float3 wiL_1)
{
    float3 hh_1 = normalize(woL_1 + wiL_1);

    float _S37 = woL_1.z;

    float _S38 = 1.0f - s_3->metallic_0;

#line 290
    float _S39 = 1.0f - s_3->transmission_0;

    return (s_3->metallic_0 + _S38 * (s_3->transmission_0 * fresnelDielectric_0(max(dot(woL_1, hh_1), 0.0f), s_3->eta_1) + _S39 * s_3->fSel_0)) * (G1_0(_S37, s_3->alpha_2) * D_0(hh_1.z, s_3->alpha_2) / (4.0f * _S37)) + _S38 * _S39 * (1.0f - s_3->fSel_0) * wiL_1.z / 3.1415927410125732f;
}


#line 174
float3 envSample_0(float u1_0, float u2_0, float u3_0, float u4_0, float thread* pdf_0, float3 thread* le_0, KernelContext_0 thread* kernelContext_13)
{

#line 174
    uint lo_0;

    uint w_5 = kernelContext_13->params_0[int(24)];
    uint h_4 = kernelContext_13->params_0[int(25)];

    uint _S40 = h_4 - 1U;

#line 179
    uint lo_1 = 0U;

#line 179
    uint hi_0 = _S40;
    for(;;)
    {

#line 180
        if(lo_1 < hi_0)
        {
        }
        else
        {

#line 180
            break;
        }
        uint mid_0 = (lo_1 + hi_0) / 2U;
        if(kernelContext_13->envMarginal_0[mid_0] >= u1_0)
        {

#line 183
            lo_0 = lo_1;

#line 183
            hi_0 = mid_0;

#line 183
        }
        else
        {

#line 183
            lo_0 = mid_0 + 1U;

#line 183
        }

#line 183
        lo_1 = lo_0;

#line 180
    }

#line 190
    uint _S41 = w_5 - 1U;

#line 190
    lo_0 = 0U;

#line 190
    hi_0 = _S41;
    for(;;)
    {

#line 191
        if(lo_0 < hi_0)
        {
        }
        else
        {

#line 191
            break;
        }
        uint mid_1 = (lo_0 + hi_0) / 2U;
        if(kernelContext_13->envCond_0[lo_1 * w_5 + mid_1] >= u2_0)
        {

#line 194
            hi_0 = mid_1;

#line 194
        }
        else
        {

#line 194
            lo_0 = mid_1 + 1U;

#line 194
        }

#line 191
    }

#line 200
    float phi_0 = ((float(lo_0) + u3_0) / float(w_5) - 0.5f) * 2.0f * 3.1415927410125732f;
    float theta_0 = (float(lo_1) + u4_0) / float(h_4) * 3.1415927410125732f;
    float st_0 = sin(theta_0);

#line 202
    float3 _S42 = envTexel_0(lo_0, lo_1, kernelContext_13);
    *le_0 = _S42;
    float _S43 = lum_0(_S42);

#line 204
    float _S44 = pf_0(26U, kernelContext_13);

#line 204
    *pdf_0 = _S43 * _S44;
    return float3(st_0 * sin(phi_0), cos(theta_0), - st_0 * cos(phi_0));
}


#line 121
float3 sampleVndf_0(float3 wo_0, float alpha_3, float u1_1, float u2_1)
{
    float3 vh_0 = normalize(float3(alpha_3 * wo_0.x, alpha_3 * wo_0.y, wo_0.z));
    float _S45 = vh_0.x;

#line 124
    float _S46 = vh_0.y;

#line 124
    float lensq_0 = _S45 * _S45 + _S46 * _S46;

#line 124
    float3 t1_0;
    if(lensq_0 > 0.0f)
    {

#line 125
        t1_0 = float3(- _S46, _S45, 0.0f) * float3(rsqrt(lensq_0)) ;

#line 125
    }
    else
    {

#line 125
        t1_0 = float3(1.0f, 0.0f, 0.0f);

#line 125
    }

    float r_1 = sqrt(u1_1);
    float phi_1 = 6.2831854820251465f * u2_1;
    float a_2 = r_1 * cos(phi_1);

    float s_4 = 0.5f * (1.0f + vh_0.z);
    float _S47 = 1.0f - a_2 * a_2;

#line 132
    float b_1 = (1.0f - s_4) * sqrt(_S47) + s_4 * (r_1 * sin(phi_1));
    float3 nh_0 = float3(a_2)  * t1_0 + float3(b_1)  * cross(vh_0, t1_0) + float3(sqrt(max(0.0f, _S47 - b_1 * b_1)))  * vh_0;
    return normalize(float3(alpha_3 * nh_0.x, alpha_3 * nh_0.y, max(0.0f, nh_0.z)));
}


#line 73
float3 cosineLocal_0(float u1_2, float u2_2)
{
    float r_2 = sqrt(u1_2);
    float phi_2 = 6.2831854820251465f * u2_2;
    return float3(r_2 * cos(phi_2), r_2 * sin(phi_2), sqrt(max(0.0f, 1.0f - u1_2)));
}


#line 310
[[kernel]] void pathtrace(uint3 tid_0 [[thread_position_in_grid]], uint device* params_1 [[buffer(6)]], metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_1 [[buffer(0)]], float device* envPixels_1 [[buffer(10)]], uint device* instances_1 [[buffer(3)]], uint device* indices_1 [[buffer(2)]], float device* positions_1 [[buffer(1)]], float device* vnormals_1 [[buffer(16)]], float device* materials_1 [[buffer(4)]], float device* uvs_1 [[buffer(13)]], uint device* texInfo_1 [[buffer(15)]], float device* texels_1 [[buffer(14)]], float device* emitters_1 [[buffer(8)]], uint device* lights_1 [[buffer(5)]], float device* emitCdf_1 [[buffer(9)]], float device* envMarginal_1 [[buffer(11)]], float device* envCond_1 [[buffer(12)]], float device* accum_1 [[buffer(7)]])
{

#line 310
    float3 radiance_0;

#line 310
    float dist_0;

#line 310
    float3 wi_0;

#line 310
    float3 li_0;

#line 310
    thread KernelContext_0 kernelContext_14;

#line 310
    (&kernelContext_14)->params_0 = params_1;

#line 310
    (&kernelContext_14)->scene_0 = scene_1;

#line 310
    (&kernelContext_14)->envPixels_0 = envPixels_1;

#line 310
    (&kernelContext_14)->instances_0 = instances_1;

#line 310
    (&kernelContext_14)->indices_0 = indices_1;

#line 310
    (&kernelContext_14)->positions_0 = positions_1;

#line 310
    (&kernelContext_14)->vnormals_0 = vnormals_1;

#line 310
    (&kernelContext_14)->materials_0 = materials_1;

#line 310
    (&kernelContext_14)->uvs_0 = uvs_1;

#line 310
    (&kernelContext_14)->texInfo_0 = texInfo_1;

#line 310
    (&kernelContext_14)->texels_0 = texels_1;

#line 310
    (&kernelContext_14)->emitters_0 = emitters_1;

#line 310
    (&kernelContext_14)->lights_0 = lights_1;

#line 310
    (&kernelContext_14)->emitCdf_0 = emitCdf_1;

#line 310
    (&kernelContext_14)->envMarginal_0 = envMarginal_1;

#line 310
    (&kernelContext_14)->envCond_0 = envCond_1;

#line 310
    (&kernelContext_14)->accum_0 = accum_1;

    uint w_6 = params_1[int(0)];
    uint h_5 = params_1[int(1)];
    uint _S48 = tid_0.x;

#line 314
    bool misPrev_0;

#line 314
    if(_S48 >= w_6)
    {

#line 314
        misPrev_0 = true;

#line 314
    }
    else
    {

#line 314
        misPrev_0 = (tid_0.y) >= h_5;

#line 314
    }

#line 314
    if(misPrev_0)
    {

#line 315
        return;
    }

#line 316
    uint _S49 = tid_0.y;

#line 316
    uint pixel_0 = _S49 * w_6 + _S48;
    thread Rng_0 rng_0;
    (&rng_0)->state_0 = pcg_0(pixel_0 ^ (pcg_0((&kernelContext_14)->params_0[int(6)] * 2654435769U + 2135587861U)));

#line 318
    float _S50 = pf_0(2U, &kernelContext_14);



    float _S51 = float(w_6);

#line 322
    float _S52 = float(h_5);

#line 322
    float aspect_0 = _S51 / _S52;
    float _S53 = float(_S48);

#line 323
    float _S54 = Rng_next_0(&rng_0);

#line 323
    float u_0 = (2.0f * (_S53 + _S54) / _S51 - 1.0f) * aspect_0 * _S50;
    float _S55 = float(_S49);

#line 324
    float _S56 = Rng_next_0(&rng_0);
    float3 _S57 = float3(u_0, (1.0f - 2.0f * (_S55 + _S56) / _S52) * _S50, -1.0f);

#line 325
    float _S58 = pf_0(4U, &kernelContext_14);

#line 325
    float3 focal_0 = _S57 * float3(_S58) ;

#line 325
    float _S59 = pf_0(3U, &kernelContext_14);
    float _S60 = Rng_next_0(&rng_0);

#line 326
    float lensR_0 = _S59 * sqrt(_S60);
    float _S61 = Rng_next_0(&rng_0);

#line 327
    float lensA_0 = 6.2831854820251465f * _S61;
    float _S62 = lensR_0 * cos(lensA_0);

#line 328
    float _S63 = lensR_0 * sin(lensA_0);
    float3 _S64 = normalize(focal_0 - float3(_S62, _S63, 0.0f));
    thread float3 org_0;

#line 330
    thread float3 dir_0;

#line 330
    uint r_3 = 0U;
    for(;;)
    {

#line 331
        if(r_3 < 3U)
        {
        }
        else
        {

#line 331
            break;
        }
        uint _S65 = 4U * r_3;

#line 333
        uint _S66 = 8U + _S65;

#line 333
        uint _S67 = 9U + _S65;

#line 333
        uint _S68 = 10U + _S65;

#line 333
        org_0[r_3] = (as_type<float>(((&kernelContext_14)->params_0[_S66]))) * _S62 + (as_type<float>(((&kernelContext_14)->params_0[_S67]))) * _S63 + (as_type<float>(((&kernelContext_14)->params_0[_S68]))) * 0.0f + (as_type<float>(((&kernelContext_14)->params_0[11U + _S65])));
        dir_0[r_3] = (as_type<float>(((&kernelContext_14)->params_0[_S66]))) * _S64.x + (as_type<float>(((&kernelContext_14)->params_0[_S67]))) * _S64.y + (as_type<float>(((&kernelContext_14)->params_0[_S68]))) * _S64.z;

#line 331
        r_3 = r_3 + 1U;

#line 331
    }

#line 336
    dir_0 = normalize(dir_0);

#line 336
    float _S69 = pf_0(20U, &kernelContext_14);

#line 336
    float _S70 = pf_0(21U, &kernelContext_14);

#line 336
    float _S71 = pf_0(22U, &kernelContext_14);

    float3 _S72 = float3(_S69, _S70, _S71);
    float3 _S73 = float3(0.0f) ;
    float3 _S74 = float3(1.0f) ;
    uint _S75 = (&kernelContext_14)->params_0[int(5)];
    uint _S76 = (&kernelContext_14)->params_0[int(7)];
    uint emitterCount_0 = (&kernelContext_14)->params_0[int(23)];

    bool hasEnv_0 = (&kernelContext_14)->params_0[int(24)] > 0U;

#line 345
    float _S77;

    if(hasEnv_0)
    {

#line 347
        if(emitterCount_0 > 0U)
        {

#line 347
            _S77 = 0.5f;

#line 347
        }
        else
        {

#line 347
            _S77 = 1.0f;

#line 347
        }

#line 347
    }
    else
    {

#line 347
        _S77 = 0.0f;

#line 347
    }

#line 347
    misPrev_0 = false;

#line 347
    float qPrev_0 = 0.0f;

#line 347
    uint depth_0 = 0U;

#line 347
    float3 thr_0 = _S74;

#line 347
    float3 radiance_1 = _S73;

#line 347
    float pathLen_0 = 0.0f;

#line 352
    for(;;)
    {

#line 352
        if(depth_0 < _S76)
        {
        }
        else
        {

#line 352
            radiance_0 = radiance_1;

#line 352
            break;
        }
        thread RayDesc_0 ray_1;
        (&ray_1)->Origin_0 = org_0;
        (&ray_1)->Direction_0 = dir_0;
        (&ray_1)->TMin_0 = 0.0f;
        (&ray_1)->TMax_0 = 1.00000001504746622e+30f;
        thread raytracing::intersection_query<raytracing::triangle_data, raytracing::instancing> q_1;
        (&q_1)->reset({ (ray_1.Origin_0), (ray_1.Direction_0), (ray_1.TMin_0), (ray_1.TMax_0) }, ((&kernelContext_14)->scene_0), (255U), _slang_ray_flags_to_intersection_params((1U)));
        for(;;)
        {

#line 361
            bool _S78 = ((&q_1)->next());

#line 361
            if(_S78)
            {
            }
            else
            {

#line 361
                break;
            }

#line 361
        }

        uint _S79 = (_slang_committed_intersection_type_to_uint((&q_1)->get_committed_intersection_type()));

#line 363
        float wB_0;

#line 363
        if(_S79 != 1U)
        {

            float3 radiance_2 = radiance_1 + thr_0 * _S72;
            if(hasEnv_0)
            {

                if(misPrev_0)
                {

#line 370
                    float _S80 = envPdf_0(dir_0, &kernelContext_14);

                    float pl_0 = _S77 * _S80;
                    float _S81 = qPrev_0 * qPrev_0;

#line 373
                    float den_0 = _S81 + pl_0 * pl_0;
                    if(den_0 > 0.0f)
                    {

#line 374
                        _S77 = _S81 / den_0;

#line 374
                    }
                    else
                    {

#line 374
                        _S77 = 1.0f;

#line 374
                    }

#line 374
                    wB_0 = _S77;

#line 370
                }
                else
                {

#line 370
                    wB_0 = 1.0f;

#line 370
                }

#line 370
                float3 _S82 = envRadiance_0(dir_0, &kernelContext_14);

#line 370
                radiance_0 = radiance_2 + thr_0 * _S82 * float3(wB_0) ;

#line 367
            }
            else
            {

#line 367
                radiance_0 = radiance_2;

#line 367
            }

#line 378
            break;
        }

        uint _S83 = ((&q_1)->get_committed_instance_id());

#line 381
        uint inst_0 = _S83 * 16U;
        uint _S84 = (&kernelContext_14)->instances_0[inst_0 + 1U];

#line 382
        uint _S85 = ((&q_1)->get_committed_primitive_id());

#line 382
        uint tri_0 = _S84 + 3U * _S85;
        uint vo_0 = (&kernelContext_14)->instances_0[inst_0];
        uint _S86 = inst_0 + 4U;

#line 384
        float3 _S87 = vertexPos_0((&kernelContext_14)->indices_0[tri_0] + vo_0, &kernelContext_14);

#line 384
        float3 _S88 = transformPoint_0(_S86, _S87, &kernelContext_14);
        uint _S89 = tri_0 + 1U;

#line 385
        float3 _S90 = vertexPos_0((&kernelContext_14)->indices_0[_S89] + vo_0, &kernelContext_14);

#line 385
        float3 _S91 = transformPoint_0(_S86, _S90, &kernelContext_14);
        uint _S92 = tri_0 + 2U;

#line 386
        float3 _S93 = vertexPos_0((&kernelContext_14)->indices_0[_S92] + vo_0, &kernelContext_14);

#line 386
        float3 _S94 = transformPoint_0(_S86, _S93, &kernelContext_14);

        float3 _S95 = _S91 - _S88;

#line 388
        float3 _S96 = _S94 - _S88;

#line 388
        float3 _S97 = cross(_S95, _S96);

#line 388
        float3 nOut_0 = normalize(_S97);
        float3 wo_1 = - dir_0;
        bool outside_0 = (dot(nOut_0, wo_1)) > 0.0f;

#line 390
        float3 ng_0;
        if(outside_0)
        {

#line 391
            ng_0 = nOut_0;

#line 391
        }
        else
        {

#line 391
            ng_0 = - nOut_0;

#line 391
        }
        float pHitT_0 = ((&q_1)->get_committed_distance());
        float pathLen_1 = pathLen_0 + pHitT_0;
        float3 hit_0 = org_0 + dir_0 * float3(pHitT_0) ;

        float3 p_1 = hit_0 + ng_0 * float3(9.9999997473787516e-05f) ;

#line 401
        float3 e3_0 = hit_0 - _S88;
        float d11_0 = dot(_S95, _S95);
        float d12_0 = dot(_S95, _S96);
        float d22_0 = dot(_S96, _S96);
        float _S98 = max(d11_0 * d22_0 - d12_0 * d12_0, 9.99999968265522539e-21f);
        float _S99 = dot(e3_0, _S95);

#line 406
        float _S100 = dot(e3_0, _S96);

#line 406
        float b1_0 = (d22_0 * _S99 - d12_0 * _S100) / _S98;
        float b2_0 = (d11_0 * _S100 - d12_0 * _S99) / _S98;



        float _S101 = 1.0f - b1_0 - b2_0;

#line 411
        float3 _S102 = vertexNormal_0((&kernelContext_14)->indices_0[tri_0] + vo_0, &kernelContext_14);

#line 411
        float3 _S103 = float3(_S101)  * _S102;

#line 411
        float3 _S104 = vertexNormal_0((&kernelContext_14)->indices_0[_S89] + vo_0, &kernelContext_14);

#line 411
        float3 _S105 = _S103 + float3(b1_0)  * _S104;

#line 411
        float3 _S106 = vertexNormal_0((&kernelContext_14)->indices_0[_S92] + vo_0, &kernelContext_14);

#line 411
        float3 nsObj_0 = _S105 + float3(b2_0)  * _S106;

#line 411
        float3 ns_0;

        if((dot(nsObj_0, nsObj_0)) > 9.999999960041972e-13f)
        {

#line 413
            float3 _S107 = transformNormal_0(_S86, nsObj_0, &kernelContext_14);

            float3 ns_1 = normalize(_S107);
            if((dot(ns_1, nOut_0)) < 0.0f)
            {

#line 416
                ns_0 = - ns_1;

#line 416
            }
            else
            {

#line 416
                ns_0 = ns_1;

#line 416
            }

#line 413
        }
        else
        {

#line 413
            ns_0 = nOut_0;

#line 413
        }

#line 413
        float3 _S108;

#line 419
        if(outside_0)
        {

#line 419
            _S108 = ns_0;

#line 419
        }
        else
        {

#line 419
            _S108 = - ns_0;

#line 419
        }

        uint mi_0 = (&kernelContext_14)->instances_0[inst_0 + 2U] * 16U;
        float3 albedo_1 = float3((&kernelContext_14)->materials_0[mi_0], (&kernelContext_14)->materials_0[mi_0 + 1U], (&kernelContext_14)->materials_0[mi_0 + 2U]);

        uint texBase_0 = uint((&kernelContext_14)->materials_0[mi_0 + 10U]);
        uint texMR_0 = uint((&kernelContext_14)->materials_0[mi_0 + 11U]);
        uint texEm_0 = uint((&kernelContext_14)->materials_0[mi_0 + 12U]);
        uint texNm_0 = uint((&kernelContext_14)->materials_0[mi_0 + 13U]);
        float2 _S109 = float2(1.0f) ;

#line 428
        bool chooseEnv_0;

#line 428
        float3 albedo_2;

#line 428
        float3 texEmission_0;

#line 428
        float3 n_2;

#line 428
        float3 radiance_3;

#line 428
        float2 texRM_0;

        if((texBase_0 + texMR_0 + texEm_0 + texNm_0) > 0U)
        {
            float2 uv0_0 = float2((&kernelContext_14)->uvs_0[2U * ((&kernelContext_14)->indices_0[tri_0] + vo_0)], (&kernelContext_14)->uvs_0[2U * ((&kernelContext_14)->indices_0[tri_0] + vo_0) + 1U]);


            float2 _S110 = float2((&kernelContext_14)->uvs_0[2U * ((&kernelContext_14)->indices_0[_S89] + vo_0)], (&kernelContext_14)->uvs_0[2U * ((&kernelContext_14)->indices_0[_S89] + vo_0) + 1U]) - uv0_0;

#line 435
            float2 _S111 = float2((&kernelContext_14)->uvs_0[2U * ((&kernelContext_14)->indices_0[_S92] + vo_0)], (&kernelContext_14)->uvs_0[2U * ((&kernelContext_14)->indices_0[_S92] + vo_0) + 1U]) - uv0_0;

#line 435
            float2 uv_2 = uv0_0 + float2(b1_0)  * _S110 + float2(b2_0)  * _S111;


            float _S112 = _S110.x;

#line 438
            float _S113 = _S111.y;

#line 438
            float _S114 = _S112 * _S113;

#line 438
            float _S115 = _S110.y;

#line 438
            float _S116 = _S111.x;

#line 438
            float uvPerWorld_0 = sqrt(abs(_S114 - _S115 * _S116) / max(length(_S97), 9.99999968265522539e-21f));

#line 438
            float _S117 = pf_0(27U, &kernelContext_14);
            float footprint_1 = pathLen_1 * _S117 / max(abs(dot(nOut_0, dir_0)), 0.10000000149011612f) * uvPerWorld_0;
            if(texBase_0 > 0U)
            {

#line 440
                float3 _S118 = sampleTexture_0(texBase_0 - 1U, uv_2, footprint_1, &kernelContext_14);

#line 440
                albedo_2 = albedo_1 * _S118;

#line 440
            }
            else
            {

#line 440
                albedo_2 = albedo_1;

#line 440
            }

            if(texMR_0 > 0U)
            {

#line 442
                float3 _S119 = sampleTexture_0(texMR_0 - 1U, uv_2, footprint_1, &kernelContext_14);

#line 442
                texRM_0 = _S119.yz;

#line 442
            }
            else
            {

#line 442
                texRM_0 = _S109;

#line 442
            }

            if(texEm_0 > 0U)
            {

#line 444
                float3 _S120 = sampleTexture_0(texEm_0 - 1U, uv_2, footprint_1, &kernelContext_14);

#line 444
                texEmission_0 = _S120;

#line 444
            }
            else
            {

#line 444
                texEmission_0 = _S74;

#line 444
            }

            if(texNm_0 > 0U)
            {

                float det_0 = _S114 - _S116 * _S115;

#line 449
                float3 _S121 = float3(det_0) ;
                float3 dPdu_0 = (_S95 * float3(_S113)  - _S96 * float3(_S115) ) / _S121;
                float3 dPdv_0 = (_S96 * float3(_S112)  - _S95 * float3(_S116) ) / _S121;
                float3 tg_0 = dPdu_0 - ns_0 * float3(dot(ns_0, dPdu_0)) ;
                if((abs(det_0)) > 9.99999968265522539e-21f)
                {

#line 453
                    chooseEnv_0 = (dot(tg_0, tg_0)) > 9.99999968265522539e-21f;

#line 453
                }
                else
                {

#line 453
                    chooseEnv_0 = false;

#line 453
                }

#line 453
                if(chooseEnv_0)
                {
                    float3 tg_1 = normalize(tg_0);
                    float3 bt_0 = cross(ns_0, tg_1);
                    if((dot(bt_0, dPdv_0)) > 0.0f)
                    {

#line 457
                        n_2 = - bt_0;

#line 457
                    }
                    else
                    {

#line 457
                        n_2 = bt_0;

#line 457
                    }

#line 457
                    float3 _S122 = sampleTexture_0(texNm_0 - 1U, uv_2, footprint_1, &kernelContext_14);

                    float3 nt_0 = _S122 * float3(2.0f)  - float3(1.0f) ;
                    uint _S123 = mi_0 + 14U;

#line 460
                    float3 ns_2 = normalize(float3((nt_0.x * (&kernelContext_14)->materials_0[_S123]))  * tg_1 + float3((nt_0.y * (&kernelContext_14)->materials_0[_S123]))  * n_2 + float3(nt_0.z)  * ns_0);
                    if(outside_0)
                    {

#line 461
                        radiance_3 = ns_2;

#line 461
                    }
                    else
                    {

#line 461
                        radiance_3 = - ns_2;

#line 461
                    }

#line 461
                    n_2 = radiance_3;

#line 453
                }
                else
                {

#line 453
                    n_2 = _S108;

#line 453
                }

#line 446
            }
            else
            {

#line 446
                n_2 = _S108;

#line 446
            }

#line 430
        }
        else
        {

#line 430
            texEmission_0 = _S74;

#line 430
            texRM_0 = _S109;

#line 430
            n_2 = _S108;

#line 430
            albedo_2 = albedo_1;

#line 430
        }

#line 466
        float3 le_1 = float3((&kernelContext_14)->materials_0[mi_0 + 3U], (&kernelContext_14)->materials_0[mi_0 + 4U], (&kernelContext_14)->materials_0[mi_0 + 5U]) * texEmission_0;
        if(any(le_1 > (float3(0.0f) )))
        {

            uint eb_0 = (&kernelContext_14)->instances_0[inst_0 + 3U];
            if(misPrev_0)
            {

#line 471
                chooseEnv_0 = eb_0 != 0U;

#line 471
            }
            else
            {

#line 471
                chooseEnv_0 = false;

#line 471
            }

#line 471
            if(chooseEnv_0)
            {
                uint _S124 = eb_0 - 1U;

#line 473
                uint _S125 = ((&q_1)->get_committed_primitive_id());

#line 473
                uint e_0 = (_S124 + _S125) * 16U;

                float pl_1 = (1.0f - _S77) * (&kernelContext_14)->emitters_0[e_0 + 13U] * pHitT_0 * pHitT_0 / ((&kernelContext_14)->emitters_0[e_0 + 12U] * max(abs(dot(nOut_0, dir_0)), 9.9999997473787516e-05f));
                float _S126 = qPrev_0 * qPrev_0;

#line 476
                wB_0 = _S126 / (_S126 + pl_1 * pl_1);

#line 471
            }
            else
            {

#line 471
                wB_0 = 1.0f;

#line 471
            }

#line 471
            radiance_3 = radiance_1 + thr_0 * le_1 * float3(wB_0) ;

#line 467
        }
        else
        {

#line 467
            radiance_3 = radiance_1;

#line 467
        }

#line 480
        float metallic_1 = (&kernelContext_14)->materials_0[mi_0 + 6U] * texRM_0.y;
        float rough_0 = (&kernelContext_14)->materials_0[mi_0 + 7U] * texRM_0.x;
        float transmission_1 = (&kernelContext_14)->materials_0[mi_0 + 8U];
        float ior_1 = (&kernelContext_14)->materials_0[mi_0 + 9U];
        float _S127 = max(rough_0 * rough_0, 0.0010000000474974513f);
        if(outside_0)
        {

#line 485
            wB_0 = ior_1;

#line 485
        }
        else
        {

#line 485
            wB_0 = 1.0f / ior_1;

#line 485
        }

        thread float3 T_0;

#line 487
        thread float3 B_0;
        basis_0(n_2, &T_0, &B_0);
        float _S128 = max(dot(wo_1, n_2), 9.9999997473787516e-05f);

#line 489
        float3 woL_2 = float3(dot(wo_1, T_0), dot(wo_1, B_0), _S128);
        float fSel_1 = fresnelDielectric_0(_S128, ior_1);
        thread Surface_0 surf_0;
        (&surf_0)->albedo_0 = albedo_2;
        (&surf_0)->metallic_0 = metallic_1;
        (&surf_0)->alpha_2 = _S127;
        (&surf_0)->transmission_0 = transmission_1;
        (&surf_0)->ior_0 = ior_1;
        (&surf_0)->eta_1 = wB_0;
        (&surf_0)->fSel_0 = fSel_1;

#line 498
        uint li_1 = 0U;

#line 498
        radiance_0 = radiance_3;



        for(;;)
        {

#line 502
            if(li_1 < _S75)
            {
            }
            else
            {

#line 502
                break;
            }
            uint o_4 = li_1 * 8U;
            float3 col_0 = float3((as_type<float>(((&kernelContext_14)->lights_0[o_4 + 1U]))), (as_type<float>(((&kernelContext_14)->lights_0[o_4 + 2U]))), (as_type<float>(((&kernelContext_14)->lights_0[o_4 + 3U])))) * float3((as_type<float>(((&kernelContext_14)->lights_0[o_4 + 4U])))) ;
            float3 vec_0 = float3((as_type<float>(((&kernelContext_14)->lights_0[o_4 + 5U]))), (as_type<float>(((&kernelContext_14)->lights_0[o_4 + 6U]))), (as_type<float>(((&kernelContext_14)->lights_0[o_4 + 7U]))));



            if((&kernelContext_14)->lights_0[o_4] == 0U)
            {
                float3 toL_0 = vec_0 - p_1;
                float d2_0 = dot(toL_0, toL_0);
                float dist_1 = sqrt(d2_0);

                float3 _S129 = col_0 / float3(d2_0) ;

#line 516
                wi_0 = toL_0 / float3(dist_1) ;

#line 516
                dist_0 = dist_1;

#line 516
                li_0 = _S129;

#line 510
            }
            else
            {

#line 510
                wi_0 = - normalize(vec_0);

#line 510
                dist_0 = 1.00000001504746622e+30f;

#line 510
                li_0 = col_0;

#line 510
            }

#line 524
            float c_2 = dot(n_2, wi_0);
            if(c_2 > 0.0f)
            {

#line 525
                bool _S130 = occluded_0(p_1, wi_0, dist_0 - 0.0010000000474974513f, &kernelContext_14);

#line 525
                chooseEnv_0 = !_S130;

#line 525
            }
            else
            {

#line 525
                chooseEnv_0 = false;

#line 525
            }

#line 525
            if(chooseEnv_0)
            {
                float3 _S131 = float3(dot(wi_0, T_0), dot(wi_0, B_0), c_2);

#line 527
                thread Surface_0 _S132 = surf_0;

#line 527
                float3 _S133 = evalReflective_0(&_S132, woL_2, _S131);

#line 527
                radiance_0 = radiance_0 + thr_0 * _S133 * li_0;

#line 525
            }

#line 502
            li_1 = li_1 + 1U;

#line 502
        }

#line 533
        float chooseLight_0 = Rng_next_0(&rng_0);
        if(hasEnv_0)
        {

#line 534
            chooseEnv_0 = chooseLight_0 < _S77;

#line 534
        }
        else
        {

#line 534
            chooseEnv_0 = false;

#line 534
        }

#line 534
        bool _S134;
        if(emitterCount_0 > 0U)
        {

#line 535
            _S134 = !chooseEnv_0;

#line 535
        }
        else
        {

#line 535
            _S134 = false;

#line 535
        }

#line 535
        bool ok_0;

#line 535
        bool refracted_0;

#line 535
        if(_S134)
        {
            float _S135 = Rng_next_0(&rng_0);
            float ua_0 = Rng_next_0(&rng_0);
            float ub_0 = Rng_next_0(&rng_0);

            uint _S136 = emitterCount_0 - 1U;

#line 541
            uint lo_2 = 0U;

#line 541
            uint hi_1 = _S136;
            for(;;)
            {

#line 542
                if(lo_2 < hi_1)
                {
                }
                else
                {

#line 542
                    break;
                }
                uint mid_2 = (lo_2 + hi_1) / 2U;
                if((&kernelContext_14)->emitCdf_0[mid_2] >= _S135)
                {

#line 545
                    hi_1 = mid_2;

#line 545
                }
                else
                {

#line 545
                    lo_2 = mid_2 + 1U;

#line 545
                }

#line 542
            }

#line 550
            uint e_1 = lo_2 * 16U;
            float3 a_3 = float3((&kernelContext_14)->emitters_0[e_1], (&kernelContext_14)->emitters_0[e_1 + 1U], (&kernelContext_14)->emitters_0[e_1 + 2U]);
            float3 b_2 = float3((&kernelContext_14)->emitters_0[e_1 + 3U], (&kernelContext_14)->emitters_0[e_1 + 4U], (&kernelContext_14)->emitters_0[e_1 + 5U]);
            float3 c_3 = float3((&kernelContext_14)->emitters_0[e_1 + 6U], (&kernelContext_14)->emitters_0[e_1 + 7U], (&kernelContext_14)->emitters_0[e_1 + 8U]);
            float su_0 = sqrt(ua_0);

            float3 toL_1 = a_3 * float3((1.0f - su_0))  + b_2 * float3((su_0 * (1.0f - ub_0)))  + c_3 * float3((su_0 * ub_0))  - p_1;
            float d2_1 = dot(toL_1, toL_1);
            float dist_2 = sqrt(d2_1);
            float3 wi_1 = toL_1 / float3(dist_2) ;
            float cosl_0 = abs(dot(normalize(cross(b_2 - a_3, c_3 - a_3)), wi_1));
            float cosi_1 = dot(n_2, wi_1);
            if(cosi_1 > 0.0f)
            {

#line 562
                ok_0 = cosl_0 > 9.9999997473787516e-06f;

#line 562
            }
            else
            {

#line 562
                ok_0 = false;

#line 562
            }

#line 562
            if(ok_0)
            {

#line 562
                bool _S137 = occluded_0(p_1, wi_1, dist_2 * 0.99900001287460327f, &kernelContext_14);

#line 562
                refracted_0 = !_S137;

#line 562
            }
            else
            {

#line 562
                refracted_0 = false;

#line 562
            }

#line 562
            if(refracted_0)
            {
                float pl_2 = (1.0f - _S77) * (&kernelContext_14)->emitters_0[e_1 + 13U] * d2_1 / ((&kernelContext_14)->emitters_0[e_1 + 12U] * cosl_0);
                float3 wiL_2 = float3(dot(wi_1, T_0), dot(wi_1, B_0), cosi_1);

#line 565
                thread Surface_0 _S138 = surf_0;

#line 565
                float _S139 = reflectivePdf_0(&_S138, woL_2, wiL_2);

                float _S140 = pl_2 * pl_2;

#line 567
                float wl_0 = _S140 / (_S140 + _S139 * _S139);

#line 567
                thread Surface_0 _S141 = surf_0;

#line 567
                float3 _S142 = evalReflective_0(&_S141, woL_2, wiL_2);

#line 567
                wi_0 = radiance_0 + thr_0 * _S142 * float3((&kernelContext_14)->emitters_0[e_1 + 9U], (&kernelContext_14)->emitters_0[e_1 + 10U], (&kernelContext_14)->emitters_0[e_1 + 11U]) / float3(pl_2)  * float3(wl_0) ;

#line 562
            }
            else
            {

#line 562
                wi_0 = radiance_0;

#line 562
            }

#line 535
        }
        else
        {

#line 535
            wi_0 = radiance_0;

#line 535
        }

#line 572
        if(chooseEnv_0)
        {
            float e1_0 = Rng_next_0(&rng_0);
            float e2_0 = Rng_next_0(&rng_0);
            float e3_1 = Rng_next_0(&rng_0);
            float e4_0 = Rng_next_0(&rng_0);
            thread float pdfE_0;
            thread float3 leE_0;

#line 579
            float3 _S143 = envSample_0(e1_0, e2_0, e3_1, e4_0, &pdfE_0, &leE_0, &kernelContext_14);

            float cosi_2 = dot(n_2, _S143);
            if(pdfE_0 > 0.0f)
            {

#line 582
                ok_0 = cosi_2 > 0.0f;

#line 582
            }
            else
            {

#line 582
                ok_0 = false;

#line 582
            }

#line 582
            if(ok_0)
            {

#line 582
                bool _S144 = occluded_0(p_1, _S143, 1.00000001504746622e+30f, &kernelContext_14);

#line 582
                refracted_0 = !_S144;

#line 582
            }
            else
            {

#line 582
                refracted_0 = false;

#line 582
            }

#line 582
            if(refracted_0)
            {
                float pl_3 = _S77 * pdfE_0;
                float3 wiL_3 = float3(dot(_S143, T_0), dot(_S143, B_0), cosi_2);

#line 585
                thread Surface_0 _S145 = surf_0;

#line 585
                float _S146 = reflectivePdf_0(&_S145, woL_2, wiL_3);

                float _S147 = pl_3 * pl_3;

#line 587
                float wl_1 = _S147 / (_S147 + _S146 * _S146);

#line 587
                thread Surface_0 _S148 = surf_0;

#line 587
                float3 _S149 = evalReflective_0(&_S148, woL_2, wiL_3);

#line 587
                li_0 = wi_0 + thr_0 * _S149 * leE_0 / float3(pl_3)  * float3(wl_1) ;

#line 582
            }
            else
            {

#line 582
                li_0 = wi_0;

#line 582
            }

#line 572
        }
        else
        {

#line 572
            li_0 = wi_0;

#line 572
        }

#line 594
        float lobe_0 = Rng_next_0(&rng_0);
        float u1_3 = Rng_next_0(&rng_0);
        float u2_3 = Rng_next_0(&rng_0);
        float u3_1 = Rng_next_0(&rng_0);

#line 597
        float3 wiL_4;

#line 597
        float3 w_7;

#line 602
        if(lobe_0 < metallic_1)
        {
            float3 h_6 = sampleVndf_0(woL_2, _S127, u1_3, u2_3);
            float woh_0 = dot(woL_2, h_6);
            float3 wiL_5 = float3((2.0f * woh_0))  * h_6 - woL_2;
            float _S150 = wiL_5.z;
            float3 _S151 = schlick_0(albedo_2, woh_0) * float3(G1_0(max(_S150, 0.0f), _S127)) ;

#line 608
            ok_0 = _S150 > 0.0f;

#line 608
            refracted_0 = false;

#line 608
            wiL_4 = wiL_5;

#line 608
            w_7 = _S151;

#line 602
        }
        else
        {

#line 610
            if(lobe_0 < (metallic_1 + (1.0f - metallic_1) * transmission_1))
            {
                float3 h_7 = sampleVndf_0(woL_2, _S127, u1_3, u2_3);
                float woh_1 = dot(woL_2, h_7);
                if(u3_1 < (fresnelDielectric_0(woh_1, wB_0)))
                {
                    float3 wiL_6 = float3((2.0f * woh_1))  * h_7 - woL_2;
                    float _S152 = wiL_6.z;
                    float3 _S153 = float3(G1_0(max(_S152, 0.0f), _S127)) ;

#line 618
                    ok_0 = _S152 > 0.0f;

#line 618
                    refracted_0 = false;

#line 618
                    wiL_4 = wiL_6;

#line 618
                    w_7 = _S153;

#line 614
                }
                else
                {

#line 622
                    float r_4 = 1.0f / wB_0;
                    float k_1 = 1.0f - r_4 * r_4 * (1.0f - woh_1 * woh_1);

#line 623
                    float3 _S154 = float3(r_4) ;
                    float3 wiL_7 = - woL_2 * _S154 + float3((r_4 * woh_1 - sqrt(max(k_1, 0.0f))))  * h_7;
                    float _S155 = wiL_7.z;

#line 625
                    if(_S155 < 0.0f)
                    {

#line 625
                        ok_0 = k_1 > 0.0f;

#line 625
                    }
                    else
                    {

#line 625
                        ok_0 = false;

#line 625
                    }


                    float3 _S156 = albedo_2 * float3(G1_0(max(- _S155, 0.0f), _S127))  * _S154 * _S154;

#line 628
                    refracted_0 = true;

#line 628
                    wiL_4 = wiL_7;

#line 628
                    w_7 = _S156;

#line 614
                }

#line 610
            }
            else
            {

#line 631
                if(u3_1 < fSel_1)
                {
                    float3 h_8 = sampleVndf_0(woL_2, _S127, u1_3, u2_3);
                    float woh_2 = dot(woL_2, h_8);
                    float3 wiL_8 = float3((2.0f * woh_2))  * h_8 - woL_2;
                    float _S157 = wiL_8.z;
                    float3 _S158 = float3((fresnelDielectric_0(woh_2, ior_1) / fSel_1 * G1_0(max(_S157, 0.0f), _S127))) ;

#line 637
                    ok_0 = _S157 > 0.0f;

#line 637
                    wiL_4 = wiL_8;

#line 637
                    w_7 = _S158;

#line 631
                }
                else
                {

#line 641
                    float3 _S159 = cosineLocal_0(u1_3, u2_3);

#line 641
                    ok_0 = true;

#line 641
                    wiL_4 = _S159;

#line 641
                    w_7 = albedo_2;

#line 631
                }

#line 631
                refracted_0 = false;

#line 610
            }

#line 602
        }

#line 644
        if(!ok_0)
        {

#line 644
            radiance_0 = li_0;
            break;
        }

#line 646
        bool _S160 = !refracted_0;
        if(refracted_0)
        {

#line 647
            qPrev_0 = 0.0f;

#line 647
        }
        else
        {

#line 647
            thread Surface_0 _S161 = surf_0;

#line 647
            float _S162 = reflectivePdf_0(&_S161, woL_2, wiL_4);

#line 647
            qPrev_0 = _S162;

#line 647
        }

        float3 _S163 = normalize(float3(wiL_4.x)  * T_0 + float3(wiL_4.y)  * B_0 + float3(wiL_4.z)  * n_2);

#line 649
        dir_0 = _S163;

        float side_0 = dot(_S163, ng_0);

#line 651
        bool _S164;
        if(refracted_0)
        {

#line 652
            _S164 = side_0 >= 0.0f;

#line 652
        }
        else
        {

#line 652
            _S164 = side_0 <= 0.0f;

#line 652
        }

#line 652
        if(_S164)
        {

#line 652
            radiance_0 = li_0;
            break;
        }

#line 654
        if(side_0 > 0.0f)
        {

#line 654
            dist_0 = 9.9999997473787516e-05f;

#line 654
        }
        else
        {

#line 654
            dist_0 = -9.9999997473787516e-05f;

#line 654
        }

#line 654
        org_0 = hit_0 + ng_0 * float3(dist_0) ;
        float3 thr_1 = thr_0 * w_7;

        if(depth_0 >= 2U)
        {
            float pr_0 = clamp(max(thr_1.x, max(thr_1.y, thr_1.z)), 0.05000000074505806f, 0.94999998807907104f);
            float _S165 = Rng_next_0(&rng_0);

#line 660
            if(_S165 > pr_0)
            {

#line 660
                radiance_0 = li_0;
                break;
            }

#line 661
            thr_0 = thr_1 / float3(pr_0) ;

#line 657
        }
        else
        {

#line 657
            thr_0 = thr_1;

#line 657
        }

#line 352
        uint _S166 = depth_0 + 1U;

#line 352
        misPrev_0 = _S160;

#line 352
        depth_0 = _S166;

#line 352
        radiance_1 = li_0;

#line 352
        pathLen_0 = pathLen_1;

#line 352
    }

#line 666
    if(any(isnan(radiance_0)))
    {

#line 666
        misPrev_0 = true;

#line 666
    }
    else
    {

#line 666
        misPrev_0 = any(isinf(radiance_0));

#line 666
    }

#line 666
    if(misPrev_0)
    {

#line 666
        radiance_0 = _S73;

#line 666
    }


    uint o_5 = 3U * pixel_0;
    float device* _S167 = (&kernelContext_14)->accum_0+o_5;

#line 670
    *_S167 = *_S167 + radiance_0.x;
    float device* _S168 = (&kernelContext_14)->accum_0+(o_5 + 1U);

#line 671
    *_S168 = *_S168 + radiance_0.y;
    float device* _S169 = (&kernelContext_14)->accum_0+(o_5 + 2U);

#line 672
    *_S169 = *_S169 + radiance_0.z;
    return;
}

