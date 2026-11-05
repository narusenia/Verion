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
            

#line 39 "shaders/pathtrace.slang"
uint pcg_0(uint v_0)
{
    uint s_0 = v_0 * 747796405U + 2891336453U;
    uint w_0 = ((s_0 >> ((s_0 >> 28U) + 4U)) ^ s_0) * 277803737U;
    return (w_0 >> 22U) ^ w_0;
}


#line 15
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
    float device* lighting_0;
    float device* emitCdf_0;
    float device* envMarginal_0;
    float device* envCond_0;
    float device* accum_0;
};


#line 56
float pf_0(uint i_0, KernelContext_0 thread* kernelContext_0)
{

#line 56
    return (as_type<float>((kernelContext_0->params_0[i_0])));
}


#line 46
struct Rng_0
{
    uint state_0;
};


#line 49
float Rng_next_0(Rng_0 thread* this_0)
{
    uint _S1 = pcg_0(this_0->state_0);

#line 51
    this_0->state_0 = _S1;
    return float(_S1 >> 8U) * 5.9604644775390625e-08f;
}


#line 334
struct Parts_0
{
    float3 total_0;
    float3 directDiffuse_0;
    float3 indirectDiffuse_0;
    float3 specular_0;
    float3 transmission_0;
    float3 emission_0;
};


#line 363
void Parts_file_0(Parts_0 thread* this_1, uint depth_0, uint cls_0, float3 c_0)
{
    if(depth_0 == 0U)
    {

#line 366
        this_1->emission_0 = this_1->emission_0 + c_0;

#line 365
    }
    else
    {

#line 367
        if(cls_0 == 0U)
        {

#line 368
            this_1->indirectDiffuse_0 = this_1->indirectDiffuse_0 + c_0;

#line 367
        }
        else
        {

#line 369
            if(cls_0 == 1U)
            {

#line 370
                this_1->specular_0 = this_1->specular_0 + c_0;

#line 369
            }
            else
            {
                this_1->transmission_0 = this_1->transmission_0 + c_0;

#line 369
            }

#line 367
        }

#line 365
    }

#line 373
    return;
}


#line 344
void Parts_add_0(Parts_0 thread* this_2, uint depth_1, uint cls_1, float3 c_1)
{
    this_2->total_0 = this_2->total_0 + c_1;
    Parts_file_0(this_2, depth_1, cls_1, c_1);
    return;
}


#line 183
void envCoords_0(float3 d_0, uint thread* i_1, uint thread* j_0, KernelContext_0 thread* kernelContext_1)
{
    uint w_1 = kernelContext_1->params_0[int(24)];
    uint h_0 = kernelContext_1->params_0[int(25)];

    float v_1 = acos(clamp(d_0.y, -1.0f, 1.0f)) / 3.1415927410125732f;
    *i_1 = min(uint((atan2(d_0.x, - d_0.z) * 0.15915493667125702f + 0.5f) * float(w_1)), w_1 - 1U);
    *j_0 = min(uint(v_1 * float(h_0)), h_0 - 1U);
    return;
}


#line 176
float3 envTexel_0(uint i_2, uint j_1, KernelContext_0 thread* kernelContext_2)
{
    uint o_0 = 3U * (j_1 * kernelContext_2->params_0[int(24)] + i_2);
    return float3(kernelContext_2->envPixels_0[o_0], kernelContext_2->envPixels_0[o_0 + 1U], kernelContext_2->envPixels_0[o_0 + 2U]);
}


#line 151
float lum_0(float3 c_2)
{

#line 151
    return dot(c_2, float3(0.2125999927520752f, 0.71520000696182251f, 0.072200000286102295f));
}


#line 202
float envPdf_0(float3 d_1, KernelContext_0 thread* kernelContext_3)
{
    thread uint i_3;

#line 204
    thread uint j_2;

#line 204
    envCoords_0(d_1, &i_3, &j_2, kernelContext_3);

#line 204
    float3 _S2 = envTexel_0(i_3, j_2, kernelContext_3);

    float _S3 = lum_0(_S2);

#line 206
    float _S4 = pf_0(26U, kernelContext_3);

#line 206
    return _S3 * _S4;
}


#line 193
float3 envRadiance_0(float3 d_2, KernelContext_0 thread* kernelContext_4)
{
    thread uint i_4;

#line 195
    thread uint j_3;

#line 195
    envCoords_0(d_2, &i_4, &j_3, kernelContext_4);

#line 195
    float3 _S5 = envTexel_0(i_4, j_3, kernelContext_4);

    return _S5;
}


#line 58
float3 vertexPos_0(uint v_2, KernelContext_0 thread* kernelContext_5)
{

#line 58
    uint _S6 = 3U * v_2;

#line 58
    return float3(kernelContext_5->positions_0[_S6], kernelContext_5->positions_0[_S6 + 1U], kernelContext_5->positions_0[_S6 + 2U]);
}


#line 60
float3 transformPoint_0(uint base_0, float3 p_0, KernelContext_0 thread* kernelContext_6)
{
    thread float3 r_0;

#line 62
    uint row_0 = 0U;
    for(;;)
    {

#line 63
        if(row_0 < 3U)
        {
        }
        else
        {

#line 63
            break;
        }
        uint o_1 = base_0 + 4U * row_0;
        r_0[row_0] = (as_type<float>((kernelContext_6->instances_0[o_1]))) * p_0.x + (as_type<float>((kernelContext_6->instances_0[o_1 + 1U]))) * p_0.y + (as_type<float>((kernelContext_6->instances_0[o_1 + 2U]))) * p_0.z + (as_type<float>((kernelContext_6->instances_0[o_1 + 3U])));

#line 63
        row_0 = row_0 + 1U;

#line 63
    }

#line 68
    return r_0;
}


#line 83
float3 vertexNormal_0(uint v_3, KernelContext_0 thread* kernelContext_7)
{

#line 83
    uint _S7 = 3U * v_3;

#line 83
    return float3(kernelContext_7->vnormals_0[_S7], kernelContext_7->vnormals_0[_S7 + 1U], kernelContext_7->vnormals_0[_S7 + 2U]);
}


#line 73
float3 transformNormal_0(uint base_1, float3 n_0, KernelContext_0 thread* kernelContext_8)
{
    float3 r0_0 = float3((as_type<float>((kernelContext_8->instances_0[base_1]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 1U]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 2U]))));
    float3 r1_0 = float3((as_type<float>((kernelContext_8->instances_0[base_1 + 4U]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 5U]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 6U]))));
    float3 r2_0 = float3((as_type<float>((kernelContext_8->instances_0[base_1 + 8U]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 9U]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 10U]))));
    float3 c0_0 = cross(r1_0, r2_0);

#line 78
    float s_1;
    if((dot(r0_0, c0_0)) < 0.0f)
    {

#line 79
        s_1 = -1.0f;

#line 79
    }
    else
    {

#line 79
        s_1 = 1.0f;

#line 79
    }
    return float3(s_1)  * float3(dot(c0_0, n_0), dot(cross(r2_0, r0_0), n_0), dot(cross(r0_0, r1_0), n_0));
}


#line 244
float3 texelAt_0(uint base_2, uint w_2, uint h_1, int x_0, int y_0, KernelContext_0 thread* kernelContext_9)
{
    int _S8 = int(w_2);

#line 246
    int _S9 = x_0 % _S8;

#line 246
    int _S10 = (_S9 + _S8) % _S8;

#line 246
    uint xi_0 = uint(_S10);
    int _S11 = int(h_1);

#line 247
    int _S12 = y_0 % _S11;

#line 247
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

#line 259
    float3 _S14 = texelAt_0(base_3, w_3, h_2, x0_0, y0_0, kernelContext_10);
    int _S15 = x0_0 + int(1);

#line 260
    float3 _S16 = texelAt_0(base_3, w_3, h_2, _S15, y0_0, kernelContext_10);

#line 260
    float3 _S17 = float3(tx_0) ;

#line 260
    float3 a_0 = mix(_S14, _S16, _S17);
    int _S18 = y0_0 + int(1);

#line 261
    float3 _S19 = texelAt_0(base_3, w_3, h_2, x0_0, _S18, kernelContext_10);

#line 261
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

#line 275
    uint lw_0 = w_4;

#line 275
    uint lh_0 = h_3;

#line 275
    uint k_0 = 0U;

#line 275
    uint off_0 = base_4;



    for(;;)
    {

#line 279
        if(k_0 < l0_0)
        {
        }
        else
        {

#line 279
            break;
        }
        uint off_1 = off_0 + lw_0 * lh_0;
        uint _S21 = max(lw_0 / 2U, 1U);
        uint _S22 = max(lh_0 / 2U, 1U);

#line 279
        uint _S23 = k_0 + 1U;

#line 279
        lw_0 = _S21;

#line 279
        lh_0 = _S22;

#line 279
        k_0 = _S23;

#line 279
        off_0 = off_1;

#line 279
    }

#line 279
    float3 _S24 = bilinear_0(off_0, lw_0, lh_0, uv_1, kernelContext_11);

#line 279
    bool _S25;

#line 286
    if((l0_0 + 1U) >= levels_0)
    {

#line 286
        _S25 = true;

#line 286
    }
    else
    {

#line 286
        _S25 = t_0 <= 0.0f;

#line 286
    }

#line 286
    if(_S25)
    {

#line 287
        return _S24;
    }

#line 287
    float3 _S26 = bilinear_0(off_0 + lw_0 * lh_0, max(lw_0 / 2U, 1U), max(lh_0 / 2U, 1U), uv_1, kernelContext_11);


    return mix(_S24, _S26, float3(t_0) );
}


#line 125
void basis_0(float3 n_1, float3 thread* t_1, float3 thread* b_0)
{

#line 125
    float3 a_1;

    if((abs(n_1.x)) > 0.89999997615814209f)
    {

#line 127
        a_1 = float3(0.0f, 1.0f, 0.0f);

#line 127
    }
    else
    {

#line 127
        a_1 = float3(1.0f, 0.0f, 0.0f);

#line 127
    }
    float3 _S27 = normalize(cross(n_1, a_1));

#line 128
    *b_0 = _S27;
    *t_1 = cross(_S27, n_1);
    return;
}


#line 114
float fresnelDielectric_0(float cosi_0, float eta_0)
{
    float s2_0 = (1.0f - cosi_0 * cosi_0) / (eta_0 * eta_0);
    if(s2_0 >= 1.0f)
    {

#line 118
        return 1.0f;
    }

#line 119
    float cost_0 = sqrt(1.0f - s2_0);
    float _S28 = eta_0 * cost_0;

#line 120
    float rs_0 = (cosi_0 - _S28) / (cosi_0 + _S28);
    float _S29 = eta_0 * cosi_0;

#line 121
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


#line 389 "shaders/pathtrace.slang"
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

#line 398
        bool _S30 = ((&q_0)->next());

#line 398
        if(_S30)
        {
        }
        else
        {

#line 398
            break;
        }

#line 398
    }
    uint _S31 = (_slang_committed_intersection_type_to_uint((&q_0)->get_committed_intersection_type()));

#line 399
    return _S31 == 1U;
}


#line 99
float D_0(float hz_0, float alpha_0)
{
    float a2_0 = alpha_0 * alpha_0;
    float d_4 = hz_0 * hz_0 * (a2_0 - 1.0f) + 1.0f;
    return a2_0 / (3.1415927410125732f * d_4 * d_4);
}


#line 92
float G1_0(float cosT_0, float alpha_1)
{
    float c2_0 = cosT_0 * cosT_0;

    return 2.0f / (1.0f + sqrt(1.0f + alpha_1 * alpha_1 * ((1.0f - c2_0) / max(c2_0, 9.99999993922529029e-09f))));
}


#line 106
float3 schlick_0(float3 f0_0, float c_3)
{
    float m_0 = 1.0f - saturate(c_3);
    float m2_0 = m_0 * m_0;
    return f0_0 + (float3(1.0f)  - f0_0) * float3((m2_0 * m2_0 * m_0)) ;
}


#line 304
struct Lobes_0
{
    float3 diffuse_0;
    float3 specular_1;
};


#line 293
struct Surface_0
{
    float3 albedo_0;
    float metallic_0;
    float alpha_2;
    float transmission_1;
    float ior_0;
    float eta_1;
    float fSel_0;
};


#line 312
Lobes_0 evalLobes_0(const Surface_0 thread* s_2, float3 woL_0, float3 wiL_0)
{
    float3 hh_0 = normalize(woL_0 + wiL_0);
    float _S32 = max(dot(woL_0, hh_0), 0.0f);

    float _S33 = woL_0.z;

#line 317
    float _S34 = wiL_0.z;

#line 317
    float core_0 = D_0(hh_0.z, s_2->alpha_2) * G1_0(_S33, s_2->alpha_2) * G1_0(_S34, s_2->alpha_2) / (4.0f * _S33);

    thread Lobes_0 l_0;

    float _S35 = 1.0f - s_2->metallic_0;

#line 321
    float _S36 = 1.0f - s_2->transmission_1;

#line 320
    (&l_0)->specular_1 = float3(s_2->metallic_0)  * schlick_0(s_2->albedo_0, _S32) * float3(core_0)  + float3((_S35 * (s_2->transmission_1 * fresnelDielectric_0(_S32, s_2->eta_1) + _S36 * fresnelDielectric_0(_S32, s_2->ior_0)) * core_0)) ;

    (&l_0)->diffuse_0 = float3((_S35 * _S36 * (1.0f - s_2->fSel_0)))  * s_2->albedo_0 * float3((_S34 / 3.1415927410125732f)) ;
    return l_0;
}


#line 351
void Parts_addLight_0(Parts_0 thread* this_3, uint depth_2, uint cls_2, float3 c_4, float3 cd_0, float3 cs_0)
{
    this_3->total_0 = this_3->total_0 + c_4;
    if(depth_2 == 0U)
    {
        this_3->directDiffuse_0 = this_3->directDiffuse_0 + cd_0;
        this_3->specular_0 = this_3->specular_0 + cs_0;

#line 354
    }
    else
    {



        Parts_file_0(this_3, depth_2, cls_2, cd_0 + cs_0);

#line 354
    }

#line 361
    return;
}


#line 155
void addSlot_0(uint pixel_0, uint slot_0, float3 u_0, float3 s_3, float3 wi_0, float lit_0, float r_1, KernelContext_0 thread* kernelContext_13)
{

#line 155
    bool _S37;

    if(any(isnan(u_0)))
    {

#line 157
        _S37 = true;

#line 157
    }
    else
    {

#line 157
        _S37 = any(isinf(u_0));

#line 157
    }

#line 157
    if(_S37)
    {

#line 157
        _S37 = true;

#line 157
    }
    else
    {

#line 157
        _S37 = any(isnan(s_3));

#line 157
    }

#line 157
    if(_S37)
    {

#line 157
        _S37 = true;

#line 157
    }
    else
    {

#line 157
        _S37 = any(isinf(s_3));

#line 157
    }

#line 157
    if(_S37)
    {

#line 158
        return;
    }

#line 159
    uint o_4 = 65U * pixel_0 + 17U + 12U * slot_0;
    float w_5 = lum_0(u_0);
    float wd_0 = w_5 + lum_0(s_3);
    float device* _S38 = kernelContext_13->lighting_0+o_4;

#line 162
    *_S38 = *_S38 + u_0.x;
    float device* _S39 = kernelContext_13->lighting_0+(o_4 + 1U);

#line 163
    *_S39 = *_S39 + u_0.y;
    float device* _S40 = kernelContext_13->lighting_0+(o_4 + 2U);

#line 164
    *_S40 = *_S40 + u_0.z;
    float device* _S41 = kernelContext_13->lighting_0+(o_4 + 3U);

#line 165
    *_S41 = *_S41 + w_5;
    float device* _S42 = kernelContext_13->lighting_0+(o_4 + 4U);

#line 166
    *_S42 = *_S42 + w_5 * r_1;
    float device* _S43 = kernelContext_13->lighting_0+(o_4 + 5U);

#line 167
    *_S43 = *_S43 + s_3.x;
    float device* _S44 = kernelContext_13->lighting_0+(o_4 + 6U);

#line 168
    *_S44 = *_S44 + s_3.y;
    float device* _S45 = kernelContext_13->lighting_0+(o_4 + 7U);

#line 169
    *_S45 = *_S45 + s_3.z;
    float device* _S46 = kernelContext_13->lighting_0+(o_4 + 8U);

#line 170
    *_S46 = *_S46 + wd_0 * wi_0.x;
    float device* _S47 = kernelContext_13->lighting_0+(o_4 + 9U);

#line 171
    *_S47 = *_S47 + wd_0 * wi_0.y;
    float device* _S48 = kernelContext_13->lighting_0+(o_4 + 10U);

#line 172
    *_S48 = *_S48 + wd_0 * wi_0.z;
    float device* _S49 = kernelContext_13->lighting_0+(o_4 + 11U);

#line 173
    *_S49 = *_S49 + wd_0 * lit_0;
    return;
}


#line 378
float reflectivePdf_0(const Surface_0 thread* s_4, float3 woL_1, float3 wiL_1)
{
    float3 hh_1 = normalize(woL_1 + wiL_1);

    float _S50 = woL_1.z;

    float _S51 = 1.0f - s_4->metallic_0;

#line 384
    float _S52 = 1.0f - s_4->transmission_1;

    return (s_4->metallic_0 + _S51 * (s_4->transmission_1 * fresnelDielectric_0(max(dot(woL_1, hh_1), 0.0f), s_4->eta_1) + _S52 * s_4->fSel_0)) * (G1_0(_S50, s_4->alpha_2) * D_0(hh_1.z, s_4->alpha_2) / (4.0f * _S50)) + _S51 * _S52 * (1.0f - s_4->fSel_0) * wiL_1.z / 3.1415927410125732f;
}


#line 326
float3 evalReflective_0(const Surface_0 thread* s_5, float3 woL_2, float3 wiL_2)
{

#line 326
    Lobes_0 _S53 = evalLobes_0(s_5, woL_2, wiL_2);


    return _S53.specular_1 + _S53.diffuse_0;
}


#line 209
float3 envSample_0(float u1_0, float u2_0, float u3_0, float u4_0, float thread* pdf_0, float3 thread* le_0, KernelContext_0 thread* kernelContext_14)
{

#line 209
    uint lo_0;

    uint w_6 = kernelContext_14->params_0[int(24)];
    uint h_4 = kernelContext_14->params_0[int(25)];

    uint _S54 = h_4 - 1U;

#line 214
    uint lo_1 = 0U;

#line 214
    uint hi_0 = _S54;
    for(;;)
    {

#line 215
        if(lo_1 < hi_0)
        {
        }
        else
        {

#line 215
            break;
        }
        uint mid_0 = (lo_1 + hi_0) / 2U;
        if(kernelContext_14->envMarginal_0[mid_0] >= u1_0)
        {

#line 218
            lo_0 = lo_1;

#line 218
            hi_0 = mid_0;

#line 218
        }
        else
        {

#line 218
            lo_0 = mid_0 + 1U;

#line 218
        }

#line 218
        lo_1 = lo_0;

#line 215
    }

#line 225
    uint _S55 = w_6 - 1U;

#line 225
    lo_0 = 0U;

#line 225
    hi_0 = _S55;
    for(;;)
    {

#line 226
        if(lo_0 < hi_0)
        {
        }
        else
        {

#line 226
            break;
        }
        uint mid_1 = (lo_0 + hi_0) / 2U;
        if(kernelContext_14->envCond_0[lo_1 * w_6 + mid_1] >= u2_0)
        {

#line 229
            hi_0 = mid_1;

#line 229
        }
        else
        {

#line 229
            lo_0 = mid_1 + 1U;

#line 229
        }

#line 226
    }

#line 235
    float phi_0 = ((float(lo_0) + u3_0) / float(w_6) - 0.5f) * 2.0f * 3.1415927410125732f;
    float theta_0 = (float(lo_1) + u4_0) / float(h_4) * 3.1415927410125732f;
    float st_0 = sin(theta_0);

#line 237
    float3 _S56 = envTexel_0(lo_0, lo_1, kernelContext_14);
    *le_0 = _S56;
    float _S57 = lum_0(_S56);

#line 239
    float _S58 = pf_0(26U, kernelContext_14);

#line 239
    *pdf_0 = _S57 * _S58;
    return float3(st_0 * sin(phi_0), cos(theta_0), - st_0 * cos(phi_0));
}


#line 133
float3 sampleVndf_0(float3 wo_0, float alpha_3, float u1_1, float u2_1)
{
    float3 vh_0 = normalize(float3(alpha_3 * wo_0.x, alpha_3 * wo_0.y, wo_0.z));
    float _S59 = vh_0.x;

#line 136
    float _S60 = vh_0.y;

#line 136
    float lensq_0 = _S59 * _S59 + _S60 * _S60;

#line 136
    float3 t1_0;
    if(lensq_0 > 0.0f)
    {

#line 137
        t1_0 = float3(- _S60, _S59, 0.0f) * float3(rsqrt(lensq_0)) ;

#line 137
    }
    else
    {

#line 137
        t1_0 = float3(1.0f, 0.0f, 0.0f);

#line 137
    }

    float r_2 = sqrt(u1_1);
    float phi_1 = 6.2831854820251465f * u2_1;
    float a_2 = r_2 * cos(phi_1);

    float s_6 = 0.5f * (1.0f + vh_0.z);
    float _S61 = 1.0f - a_2 * a_2;

#line 144
    float b_1 = (1.0f - s_6) * sqrt(_S61) + s_6 * (r_2 * sin(phi_1));
    float3 nh_0 = float3(a_2)  * t1_0 + float3(b_1)  * cross(vh_0, t1_0) + float3(sqrt(max(0.0f, _S61 - b_1 * b_1)))  * vh_0;
    return normalize(float3(alpha_3 * nh_0.x, alpha_3 * nh_0.y, max(0.0f, nh_0.z)));
}


#line 85
float3 cosineLocal_0(float u1_2, float u2_2)
{
    float r_3 = sqrt(u1_2);
    float phi_2 = 6.2831854820251465f * u2_2;
    return float3(r_3 * cos(phi_2), r_3 * sin(phi_2), sqrt(max(0.0f, 1.0f - u1_2)));
}


#line 404
[[kernel]] void pathtrace(uint3 tid_0 [[thread_position_in_grid]], uint device* params_1 [[buffer(6)]], metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_1 [[buffer(0)]], float device* envPixels_1 [[buffer(10)]], uint device* instances_1 [[buffer(3)]], uint device* indices_1 [[buffer(2)]], float device* positions_1 [[buffer(1)]], float device* vnormals_1 [[buffer(16)]], float device* materials_1 [[buffer(4)]], float device* uvs_1 [[buffer(13)]], uint device* texInfo_1 [[buffer(15)]], float device* texels_1 [[buffer(14)]], float device* emitters_1 [[buffer(8)]], uint device* lights_1 [[buffer(5)]], float device* lighting_1 [[buffer(17)]], float device* emitCdf_1 [[buffer(9)]], float device* envMarginal_1 [[buffer(11)]], float device* envCond_1 [[buffer(12)]], float device* accum_1 [[buffer(7)]])
{

#line 404
    uint k_1;

#line 404
    float visLit_0;

#line 404
    float visTotal_0;

#line 404
    float3 radiance_0;

#line 404
    bool track_0;

#line 404
    float dist_0;

#line 404
    float visLit_1;

#line 404
    float3 wi_1;

#line 404
    float3 li_0;

#line 404
    thread KernelContext_0 kernelContext_15;

#line 404
    (&kernelContext_15)->params_0 = params_1;

#line 404
    (&kernelContext_15)->scene_0 = scene_1;

#line 404
    (&kernelContext_15)->envPixels_0 = envPixels_1;

#line 404
    (&kernelContext_15)->instances_0 = instances_1;

#line 404
    (&kernelContext_15)->indices_0 = indices_1;

#line 404
    (&kernelContext_15)->positions_0 = positions_1;

#line 404
    (&kernelContext_15)->vnormals_0 = vnormals_1;

#line 404
    (&kernelContext_15)->materials_0 = materials_1;

#line 404
    (&kernelContext_15)->uvs_0 = uvs_1;

#line 404
    (&kernelContext_15)->texInfo_0 = texInfo_1;

#line 404
    (&kernelContext_15)->texels_0 = texels_1;

#line 404
    (&kernelContext_15)->emitters_0 = emitters_1;

#line 404
    (&kernelContext_15)->lights_0 = lights_1;

#line 404
    (&kernelContext_15)->lighting_0 = lighting_1;

#line 404
    (&kernelContext_15)->emitCdf_0 = emitCdf_1;

#line 404
    (&kernelContext_15)->envMarginal_0 = envMarginal_1;

#line 404
    (&kernelContext_15)->envCond_0 = envCond_1;

#line 404
    (&kernelContext_15)->accum_0 = accum_1;

    uint w_7 = params_1[int(0)];
    uint h_5 = params_1[int(1)];
    uint _S62 = tid_0.x;

#line 408
    bool misPrev_0;

#line 408
    if(_S62 >= w_7)
    {

#line 408
        misPrev_0 = true;

#line 408
    }
    else
    {

#line 408
        misPrev_0 = (tid_0.y) >= h_5;

#line 408
    }

#line 408
    if(misPrev_0)
    {

#line 409
        return;
    }

#line 410
    uint _S63 = tid_0.y;

#line 410
    uint pixel_1 = _S63 * w_7 + _S62;
    thread Rng_0 rng_0;
    (&rng_0)->state_0 = pcg_0(pixel_1 ^ (pcg_0((&kernelContext_15)->params_0[int(6)] * 2654435769U + 2135587861U)));

#line 412
    float _S64 = pf_0(2U, &kernelContext_15);



    float _S65 = float(w_7);

#line 416
    float _S66 = float(h_5);

#line 416
    float aspect_0 = _S65 / _S66;
    float _S67 = float(_S62);

#line 417
    float _S68 = Rng_next_0(&rng_0);

#line 417
    float u_1 = (2.0f * (_S67 + _S68) / _S65 - 1.0f) * aspect_0 * _S64;
    float _S69 = float(_S63);

#line 418
    float _S70 = Rng_next_0(&rng_0);
    float3 _S71 = float3(u_1, (1.0f - 2.0f * (_S69 + _S70) / _S66) * _S64, -1.0f);

#line 419
    float _S72 = pf_0(4U, &kernelContext_15);

#line 419
    float3 focal_0 = _S71 * float3(_S72) ;

#line 419
    float _S73 = pf_0(3U, &kernelContext_15);
    float _S74 = Rng_next_0(&rng_0);

#line 420
    float lensR_0 = _S73 * sqrt(_S74);
    float _S75 = Rng_next_0(&rng_0);

#line 421
    float lensA_0 = 6.2831854820251465f * _S75;
    float _S76 = lensR_0 * cos(lensA_0);

#line 422
    float _S77 = lensR_0 * sin(lensA_0);
    float3 _S78 = normalize(focal_0 - float3(_S76, _S77, 0.0f));
    thread float3 org_0;

#line 424
    thread float3 dir_0;

#line 424
    uint r_4 = 0U;
    for(;;)
    {

#line 425
        if(r_4 < 3U)
        {
        }
        else
        {

#line 425
            break;
        }
        uint _S79 = 4U * r_4;

#line 427
        uint _S80 = 8U + _S79;

#line 427
        uint _S81 = 9U + _S79;

#line 427
        uint _S82 = 10U + _S79;

#line 427
        org_0[r_4] = (as_type<float>(((&kernelContext_15)->params_0[_S80]))) * _S76 + (as_type<float>(((&kernelContext_15)->params_0[_S81]))) * _S77 + (as_type<float>(((&kernelContext_15)->params_0[_S82]))) * 0.0f + (as_type<float>(((&kernelContext_15)->params_0[11U + _S79])));
        dir_0[r_4] = (as_type<float>(((&kernelContext_15)->params_0[_S80]))) * _S78.x + (as_type<float>(((&kernelContext_15)->params_0[_S81]))) * _S78.y + (as_type<float>(((&kernelContext_15)->params_0[_S82]))) * _S78.z;

#line 425
        r_4 = r_4 + 1U;

#line 425
    }

#line 430
    dir_0 = normalize(dir_0);

#line 430
    float _S83 = pf_0(20U, &kernelContext_15);

#line 430
    float _S84 = pf_0(21U, &kernelContext_15);

#line 430
    float _S85 = pf_0(22U, &kernelContext_15);

    float3 _S86 = float3(_S83, _S84, _S85);
    float3 _S87 = float3(0.0f) ;

#line 433
    thread Parts_0 parts_0;

#line 433
    (&parts_0)->total_0 = _S87;

#line 433
    (&parts_0)->directDiffuse_0 = _S87;

#line 433
    (&parts_0)->indirectDiffuse_0 = _S87;

#line 433
    (&parts_0)->specular_0 = _S87;

#line 433
    (&parts_0)->transmission_0 = _S87;

#line 433
    (&parts_0)->emission_0 = _S87;
    bool lightingOn_0 = (&kernelContext_15)->params_0[int(28)] != 0U;



    float3 _S88 = float3(1.0f) ;
    uint _S89 = (&kernelContext_15)->params_0[int(5)];
    uint _S90 = (&kernelContext_15)->params_0[int(7)];
    uint emitterCount_0 = (&kernelContext_15)->params_0[int(23)];

    bool hasEnv_0 = (&kernelContext_15)->params_0[int(24)] > 0U;

#line 443
    float _S91;

    if(hasEnv_0)
    {

#line 445
        if(emitterCount_0 > 0U)
        {

#line 445
            _S91 = 0.5f;

#line 445
        }
        else
        {

#line 445
            _S91 = 1.0f;

#line 445
        }

#line 445
    }
    else
    {

#line 445
        _S91 = 0.0f;

#line 445
    }

#line 445
    uint cls_3 = 0U;

#line 445
    misPrev_0 = false;

#line 445
    float qPrev_0 = 0.0f;

#line 445
    uint depth_3 = 0U;

#line 445
    float3 thr_0 = _S88;

#line 445
    float pathLen_0 = 0.0f;

#line 445
    float visTotal_1 = 0.0f;

#line 445
    float visLit_2 = 0.0f;

#line 450
    for(;;)
    {

#line 450
        if(depth_3 < _S90)
        {
        }
        else
        {

#line 450
            visLit_0 = visLit_2;

#line 450
            visTotal_0 = visTotal_1;

#line 450
            break;
        }
        thread RayDesc_0 ray_1;
        (&ray_1)->Origin_0 = org_0;
        (&ray_1)->Direction_0 = dir_0;
        (&ray_1)->TMin_0 = 0.0f;
        (&ray_1)->TMax_0 = 1.00000001504746622e+30f;
        thread raytracing::intersection_query<raytracing::triangle_data, raytracing::instancing> q_1;
        (&q_1)->reset({ (ray_1.Origin_0), (ray_1.Direction_0), (ray_1.TMin_0), (ray_1.TMax_0) }, ((&kernelContext_15)->scene_0), (255U), _slang_ray_flags_to_intersection_params((1U)));
        for(;;)
        {

#line 459
            bool _S92 = ((&q_1)->next());

#line 459
            if(_S92)
            {
            }
            else
            {

#line 459
                break;
            }

#line 459
        }

        uint _S93 = (_slang_committed_intersection_type_to_uint((&q_1)->get_committed_intersection_type()));

#line 461
        float wB_0;

#line 461
        if(_S93 != 1U)
        {

            Parts_add_0(&parts_0, depth_3, cls_3, thr_0 * _S86);
            if(hasEnv_0)
            {

                if(misPrev_0)
                {

#line 468
                    float _S94 = envPdf_0(dir_0, &kernelContext_15);

                    float pl_0 = _S91 * _S94;
                    float _S95 = qPrev_0 * qPrev_0;

#line 471
                    float den_0 = _S95 + pl_0 * pl_0;
                    if(den_0 > 0.0f)
                    {

#line 472
                        _S91 = _S95 / den_0;

#line 472
                    }
                    else
                    {

#line 472
                        _S91 = 1.0f;

#line 472
                    }

#line 472
                    wB_0 = _S91;

#line 468
                }
                else
                {

#line 468
                    wB_0 = 1.0f;

#line 468
                }

#line 468
                float3 _S96 = envRadiance_0(dir_0, &kernelContext_15);

#line 474
                Parts_add_0(&parts_0, depth_3, cls_3, thr_0 * _S96 * float3(wB_0) );

#line 465
            }

#line 465
            visLit_0 = visLit_2;

#line 465
            visTotal_0 = visTotal_1;

#line 476
            break;
        }

        uint _S97 = ((&q_1)->get_committed_instance_id());

#line 479
        uint inst_0 = _S97 * 16U;
        uint _S98 = (&kernelContext_15)->instances_0[inst_0 + 1U];

#line 480
        uint _S99 = ((&q_1)->get_committed_primitive_id());

#line 480
        uint tri_0 = _S98 + 3U * _S99;
        uint vo_0 = (&kernelContext_15)->instances_0[inst_0];
        uint _S100 = inst_0 + 4U;

#line 482
        float3 _S101 = vertexPos_0((&kernelContext_15)->indices_0[tri_0] + vo_0, &kernelContext_15);

#line 482
        float3 _S102 = transformPoint_0(_S100, _S101, &kernelContext_15);
        uint _S103 = tri_0 + 1U;

#line 483
        float3 _S104 = vertexPos_0((&kernelContext_15)->indices_0[_S103] + vo_0, &kernelContext_15);

#line 483
        float3 _S105 = transformPoint_0(_S100, _S104, &kernelContext_15);
        uint _S106 = tri_0 + 2U;

#line 484
        float3 _S107 = vertexPos_0((&kernelContext_15)->indices_0[_S106] + vo_0, &kernelContext_15);

#line 484
        float3 _S108 = transformPoint_0(_S100, _S107, &kernelContext_15);

        float3 _S109 = _S105 - _S102;

#line 486
        float3 _S110 = _S108 - _S102;

#line 486
        float3 _S111 = cross(_S109, _S110);

#line 486
        float3 nOut_0 = normalize(_S111);
        float3 wo_1 = - dir_0;
        bool outside_0 = (dot(nOut_0, wo_1)) > 0.0f;
        if(outside_0)
        {

#line 489
            radiance_0 = nOut_0;

#line 489
        }
        else
        {

#line 489
            radiance_0 = - nOut_0;

#line 489
        }
        float pHitT_0 = ((&q_1)->get_committed_distance());
        float pathLen_1 = pathLen_0 + pHitT_0;
        float3 hit_0 = org_0 + dir_0 * float3(pHitT_0) ;

        float3 p_1 = hit_0 + radiance_0 * float3(9.9999997473787516e-05f) ;

#line 499
        float3 e3_0 = hit_0 - _S102;
        float d11_0 = dot(_S109, _S109);
        float d12_0 = dot(_S109, _S110);
        float d22_0 = dot(_S110, _S110);
        float _S112 = max(d11_0 * d22_0 - d12_0 * d12_0, 9.99999968265522539e-21f);
        float _S113 = dot(e3_0, _S109);

#line 504
        float _S114 = dot(e3_0, _S110);

#line 504
        float b1_0 = (d22_0 * _S113 - d12_0 * _S114) / _S112;
        float b2_0 = (d11_0 * _S114 - d12_0 * _S113) / _S112;



        float _S115 = 1.0f - b1_0 - b2_0;

#line 509
        float3 _S116 = vertexNormal_0((&kernelContext_15)->indices_0[tri_0] + vo_0, &kernelContext_15);

#line 509
        float3 _S117 = float3(_S115)  * _S116;

#line 509
        float3 _S118 = vertexNormal_0((&kernelContext_15)->indices_0[_S103] + vo_0, &kernelContext_15);

#line 509
        float3 _S119 = _S117 + float3(b1_0)  * _S118;

#line 509
        float3 _S120 = vertexNormal_0((&kernelContext_15)->indices_0[_S106] + vo_0, &kernelContext_15);

#line 509
        float3 nsObj_0 = _S119 + float3(b2_0)  * _S120;

#line 509
        float3 ns_0;

        if((dot(nsObj_0, nsObj_0)) > 9.999999960041972e-13f)
        {

#line 511
            float3 _S121 = transformNormal_0(_S100, nsObj_0, &kernelContext_15);

            float3 ns_1 = normalize(_S121);
            if((dot(ns_1, nOut_0)) < 0.0f)
            {

#line 514
                ns_0 = - ns_1;

#line 514
            }
            else
            {

#line 514
                ns_0 = ns_1;

#line 514
            }

#line 511
        }
        else
        {

#line 511
            ns_0 = nOut_0;

#line 511
        }

#line 511
        float3 _S122;

#line 517
        if(outside_0)
        {

#line 517
            _S122 = ns_0;

#line 517
        }
        else
        {

#line 517
            _S122 = - ns_0;

#line 517
        }

        uint mi_0 = (&kernelContext_15)->instances_0[inst_0 + 2U] * 16U;
        float3 albedo_1 = float3((&kernelContext_15)->materials_0[mi_0], (&kernelContext_15)->materials_0[mi_0 + 1U], (&kernelContext_15)->materials_0[mi_0 + 2U]);

        uint texBase_0 = uint((&kernelContext_15)->materials_0[mi_0 + 10U]);
        uint texMR_0 = uint((&kernelContext_15)->materials_0[mi_0 + 11U]);
        uint texEm_0 = uint((&kernelContext_15)->materials_0[mi_0 + 12U]);
        uint texNm_0 = uint((&kernelContext_15)->materials_0[mi_0 + 13U]);
        float2 _S123 = float2(1.0f) ;

#line 526
        bool chooseEnv_0;

#line 526
        float3 albedo_2;

#line 526
        float3 texEmission_0;

#line 526
        float3 n_2;

#line 526
        float3 n_3;

#line 526
        float2 texRM_0;

        if((texBase_0 + texMR_0 + texEm_0 + texNm_0) > 0U)
        {
            float2 uv0_0 = float2((&kernelContext_15)->uvs_0[2U * ((&kernelContext_15)->indices_0[tri_0] + vo_0)], (&kernelContext_15)->uvs_0[2U * ((&kernelContext_15)->indices_0[tri_0] + vo_0) + 1U]);


            float2 _S124 = float2((&kernelContext_15)->uvs_0[2U * ((&kernelContext_15)->indices_0[_S103] + vo_0)], (&kernelContext_15)->uvs_0[2U * ((&kernelContext_15)->indices_0[_S103] + vo_0) + 1U]) - uv0_0;

#line 533
            float2 _S125 = float2((&kernelContext_15)->uvs_0[2U * ((&kernelContext_15)->indices_0[_S106] + vo_0)], (&kernelContext_15)->uvs_0[2U * ((&kernelContext_15)->indices_0[_S106] + vo_0) + 1U]) - uv0_0;

#line 533
            float2 uv_2 = uv0_0 + float2(b1_0)  * _S124 + float2(b2_0)  * _S125;


            float _S126 = _S124.x;

#line 536
            float _S127 = _S125.y;

#line 536
            float _S128 = _S126 * _S127;

#line 536
            float _S129 = _S124.y;

#line 536
            float _S130 = _S125.x;

#line 536
            float uvPerWorld_0 = sqrt(abs(_S128 - _S129 * _S130) / max(length(_S111), 9.99999968265522539e-21f));

#line 536
            float _S131 = pf_0(27U, &kernelContext_15);
            float footprint_1 = pathLen_1 * _S131 / max(abs(dot(nOut_0, dir_0)), 0.10000000149011612f) * uvPerWorld_0;
            if(texBase_0 > 0U)
            {

#line 538
                float3 _S132 = sampleTexture_0(texBase_0 - 1U, uv_2, footprint_1, &kernelContext_15);

#line 538
                albedo_2 = albedo_1 * _S132;

#line 538
            }
            else
            {

#line 538
                albedo_2 = albedo_1;

#line 538
            }

            if(texMR_0 > 0U)
            {

#line 540
                float3 _S133 = sampleTexture_0(texMR_0 - 1U, uv_2, footprint_1, &kernelContext_15);

#line 540
                texRM_0 = _S133.yz;

#line 540
            }
            else
            {

#line 540
                texRM_0 = _S123;

#line 540
            }

            if(texEm_0 > 0U)
            {

#line 542
                float3 _S134 = sampleTexture_0(texEm_0 - 1U, uv_2, footprint_1, &kernelContext_15);

#line 542
                texEmission_0 = _S134;

#line 542
            }
            else
            {

#line 542
                texEmission_0 = _S88;

#line 542
            }

            if(texNm_0 > 0U)
            {

                float det_0 = _S128 - _S130 * _S129;

#line 547
                float3 _S135 = float3(det_0) ;
                float3 dPdu_0 = (_S109 * float3(_S127)  - _S110 * float3(_S129) ) / _S135;
                float3 dPdv_0 = (_S110 * float3(_S126)  - _S109 * float3(_S130) ) / _S135;
                float3 tg_0 = dPdu_0 - ns_0 * float3(dot(ns_0, dPdu_0)) ;
                if((abs(det_0)) > 9.99999968265522539e-21f)
                {

#line 551
                    chooseEnv_0 = (dot(tg_0, tg_0)) > 9.99999968265522539e-21f;

#line 551
                }
                else
                {

#line 551
                    chooseEnv_0 = false;

#line 551
                }

#line 551
                if(chooseEnv_0)
                {
                    float3 tg_1 = normalize(tg_0);
                    float3 bt_0 = cross(ns_0, tg_1);
                    if((dot(bt_0, dPdv_0)) > 0.0f)
                    {

#line 555
                        n_2 = - bt_0;

#line 555
                    }
                    else
                    {

#line 555
                        n_2 = bt_0;

#line 555
                    }

#line 555
                    float3 _S136 = sampleTexture_0(texNm_0 - 1U, uv_2, footprint_1, &kernelContext_15);

                    float3 nt_0 = _S136 * float3(2.0f)  - float3(1.0f) ;
                    uint _S137 = mi_0 + 14U;

#line 558
                    float3 ns_2 = normalize(float3((nt_0.x * (&kernelContext_15)->materials_0[_S137]))  * tg_1 + float3((nt_0.y * (&kernelContext_15)->materials_0[_S137]))  * n_2 + float3(nt_0.z)  * ns_0);
                    if(outside_0)
                    {

#line 559
                        n_3 = ns_2;

#line 559
                    }
                    else
                    {

#line 559
                        n_3 = - ns_2;

#line 559
                    }

#line 559
                    n_2 = n_3;

#line 551
                }
                else
                {

#line 551
                    n_2 = _S122;

#line 551
                }

#line 544
            }
            else
            {

#line 544
                n_2 = _S122;

#line 544
            }

#line 528
        }
        else
        {

#line 528
            n_2 = _S122;

#line 528
            texEmission_0 = _S88;

#line 528
            texRM_0 = _S123;

#line 528
            albedo_2 = albedo_1;

#line 528
        }

#line 565
        float woN_0 = dot(n_2, wo_1);
        if(woN_0 < 0.05000000074505806f)
        {

#line 566
            n_3 = normalize(n_2 + wo_1 * float3((0.05000000074505806f - woN_0)) );

#line 566
        }
        else
        {

#line 566
            n_3 = n_2;

#line 566
        }


        float3 le_1 = float3((&kernelContext_15)->materials_0[mi_0 + 3U], (&kernelContext_15)->materials_0[mi_0 + 4U], (&kernelContext_15)->materials_0[mi_0 + 5U]) * texEmission_0;
        if(any(le_1 > (float3(0.0f) )))
        {

            uint eb_0 = (&kernelContext_15)->instances_0[inst_0 + 3U];
            if(misPrev_0)
            {

#line 574
                chooseEnv_0 = eb_0 != 0U;

#line 574
            }
            else
            {

#line 574
                chooseEnv_0 = false;

#line 574
            }

#line 574
            if(chooseEnv_0)
            {
                uint _S138 = eb_0 - 1U;

#line 576
                uint _S139 = ((&q_1)->get_committed_primitive_id());

#line 576
                uint e_0 = (_S138 + _S139) * 16U;

                float pl_1 = (1.0f - _S91) * (&kernelContext_15)->emitters_0[e_0 + 13U] * pHitT_0 * pHitT_0 / ((&kernelContext_15)->emitters_0[e_0 + 12U] * max(abs(dot(nOut_0, dir_0)), 9.9999997473787516e-05f));
                float _S140 = qPrev_0 * qPrev_0;

#line 579
                wB_0 = _S140 / (_S140 + pl_1 * pl_1);

#line 574
            }
            else
            {

#line 574
                wB_0 = 1.0f;

#line 574
            }

#line 581
            Parts_add_0(&parts_0, depth_3, cls_3, thr_0 * le_1 * float3(wB_0) );

#line 570
        }

#line 583
        float metallic_1 = (&kernelContext_15)->materials_0[mi_0 + 6U] * texRM_0.y;
        float rough_0 = (&kernelContext_15)->materials_0[mi_0 + 7U] * texRM_0.x;
        float transmission_2 = (&kernelContext_15)->materials_0[mi_0 + 8U];
        float ior_1 = (&kernelContext_15)->materials_0[mi_0 + 9U];
        float _S141 = max(rough_0 * rough_0, 0.0010000000474974513f);
        if(outside_0)
        {

#line 588
            wB_0 = ior_1;

#line 588
        }
        else
        {

#line 588
            wB_0 = 1.0f / ior_1;

#line 588
        }

        thread float3 T_0;

#line 590
        thread float3 B_0;
        basis_0(n_3, &T_0, &B_0);
        float _S142 = max(dot(wo_1, n_3), 9.9999997473787516e-05f);

#line 592
        float3 woL_3 = float3(dot(wo_1, T_0), dot(wo_1, B_0), _S142);
        float fSel_1 = fresnelDielectric_0(_S142, ior_1);
        thread Surface_0 surf_0;
        (&surf_0)->albedo_0 = albedo_2;
        (&surf_0)->metallic_0 = metallic_1;
        (&surf_0)->alpha_2 = _S141;
        (&surf_0)->transmission_1 = transmission_2;
        (&surf_0)->ior_0 = ior_1;
        (&surf_0)->eta_1 = wB_0;
        (&surf_0)->fSel_0 = fSel_1;

#line 601
        k_1 = 0U;

#line 601
        float visTotal_2 = visTotal_1;

#line 601
        float visLit_3 = visLit_2;



        for(;;)
        {

#line 605
            if(k_1 < _S89)
            {
            }
            else
            {

#line 605
                break;
            }
            uint o_5 = k_1 * 16U;
            float3 col_0 = float3((as_type<float>(((&kernelContext_15)->lights_0[o_5 + 1U]))), (as_type<float>(((&kernelContext_15)->lights_0[o_5 + 2U]))), (as_type<float>(((&kernelContext_15)->lights_0[o_5 + 3U])))) * float3((as_type<float>(((&kernelContext_15)->lights_0[o_5 + 4U])))) ;
            float3 vec_0 = float3((as_type<float>(((&kernelContext_15)->lights_0[o_5 + 5U]))), (as_type<float>(((&kernelContext_15)->lights_0[o_5 + 6U]))), (as_type<float>(((&kernelContext_15)->lights_0[o_5 + 7U]))));



            if((&kernelContext_15)->lights_0[o_5] == 1U)
            {

#line 613
                wi_1 = - normalize(vec_0);

#line 613
                dist_0 = 1.00000001504746622e+30f;

#line 613
                li_0 = col_0;

#line 613
            }
            else
            {

#line 621
                float3 toL_0 = vec_0 - p_1;
                float d2_0 = dot(toL_0, toL_0);
                float dist_1 = sqrt(d2_0);
                float3 wi_2 = toL_0 / float3(dist_1) ;
                float3 li_1 = col_0 / float3(d2_0) ;
                if((&kernelContext_15)->lights_0[o_5] == 2U)
                {

                    float att_0 = saturate(dot(float3((as_type<float>(((&kernelContext_15)->lights_0[o_5 + 8U]))), (as_type<float>(((&kernelContext_15)->lights_0[o_5 + 9U]))), (as_type<float>(((&kernelContext_15)->lights_0[o_5 + 10U])))), - wi_2) * (as_type<float>(((&kernelContext_15)->lights_0[o_5 + 11U]))) + (as_type<float>(((&kernelContext_15)->lights_0[o_5 + 12U]))));

#line 629
                    wi_1 = li_1 * float3((att_0 * att_0)) ;

#line 626
                }
                else
                {

#line 626
                    wi_1 = li_1;

#line 626
                }

#line 612
                float3 _S143 = wi_1;

#line 612
                wi_1 = wi_2;

#line 612
                dist_0 = dist_1;

#line 612
                li_0 = _S143;
            }

#line 633
            float c_5 = dot(n_3, wi_1);
            if(c_5 > 0.0f)
            {

#line 634
                bool _S144 = occluded_0(p_1, wi_1, dist_0 - 0.0010000000474974513f, &kernelContext_15);


                if(lightingOn_0)
                {

#line 637
                    track_0 = depth_3 == 0U;

#line 637
                }
                else
                {

#line 637
                    track_0 = false;

#line 637
                }
                bool _S145 = !_S144;

#line 638
                if(_S145)
                {

#line 638
                    chooseEnv_0 = true;

#line 638
                }
                else
                {

#line 638
                    chooseEnv_0 = track_0;

#line 638
                }

#line 638
                if(chooseEnv_0)
                {
                    float3 _S146 = float3(dot(wi_1, T_0), dot(wi_1, B_0), c_5);

#line 640
                    thread Surface_0 _S147 = surf_0;

#line 640
                    Lobes_0 _S148 = evalLobes_0(&_S147, woL_3, _S146);
                    float3 cd_1 = thr_0 * _S148.diffuse_0 * li_0;
                    float3 cs_1 = thr_0 * _S148.specular_1 * li_0;
                    if(_S145)
                    {

#line 644
                        Parts_addLight_0(&parts_0, depth_3, cls_3, thr_0 * (_S148.diffuse_0 + _S148.specular_1) * li_0, cd_1, cs_1);

#line 643
                    }

                    if(track_0)
                    {
                        float vv_0 = lum_0(cd_1 + cs_1);
                        float visTotal_3 = visTotal_2 + vv_0;
                        if(_S144)
                        {

#line 649
                            visLit_0 = 0.0f;

#line 649
                        }
                        else
                        {

#line 649
                            visLit_0 = vv_0;

#line 649
                        }

#line 649
                        float visLit_4 = visLit_3 + visLit_0;
                        uint _S149 = min(k_1, 2U);

#line 650
                        float3 _S150 = float3(c_5) ;

#line 650
                        float3 _S151 = cd_1 / _S150;

#line 650
                        float3 _S152 = cs_1 / _S150;

#line 650
                        if(_S144)
                        {

#line 650
                            visTotal_0 = 0.0f;

#line 650
                        }
                        else
                        {

#line 650
                            visTotal_0 = 1.0f;

#line 650
                        }

#line 650
                        if(_S144)
                        {

#line 650
                            visLit_1 = 0.0f;

#line 650
                        }
                        else
                        {

#line 650
                            visLit_1 = c_5;

#line 650
                        }

#line 650
                        addSlot_0(pixel_1, _S149, _S151, _S152, wi_1, visTotal_0, visLit_1, &kernelContext_15);

#line 650
                        visTotal_0 = visTotal_3;

#line 650
                        visLit_0 = visLit_4;

#line 645
                    }
                    else
                    {

#line 645
                        visTotal_0 = visTotal_2;

#line 645
                        visLit_0 = visLit_3;

#line 645
                    }

#line 638
                }
                else
                {

#line 638
                    visTotal_0 = visTotal_2;

#line 638
                    visLit_0 = visLit_3;

#line 638
                }

#line 634
            }
            else
            {

#line 634
                visTotal_0 = visTotal_2;

#line 634
                visLit_0 = visLit_3;

#line 634
            }

#line 605
            k_1 = k_1 + 1U;

#line 605
            visTotal_2 = visTotal_0;

#line 605
            visLit_3 = visLit_0;

#line 605
        }

#line 657
        float chooseLight_0 = Rng_next_0(&rng_0);
        if(hasEnv_0)
        {

#line 658
            chooseEnv_0 = chooseLight_0 < _S91;

#line 658
        }
        else
        {

#line 658
            chooseEnv_0 = false;

#line 658
        }

#line 658
        bool _S153;
        if(emitterCount_0 > 0U)
        {

#line 659
            _S153 = !chooseEnv_0;

#line 659
        }
        else
        {

#line 659
            _S153 = false;

#line 659
        }

#line 659
        bool ok_0;

#line 659
        bool _S154;

#line 659
        uint lobeCls_0;

#line 659
        if(_S153)
        {
            float _S155 = Rng_next_0(&rng_0);
            float ua_0 = Rng_next_0(&rng_0);
            float ub_0 = Rng_next_0(&rng_0);

            uint _S156 = emitterCount_0 - 1U;

#line 665
            lobeCls_0 = 0U;

#line 665
            uint hi_1 = _S156;
            for(;;)
            {

#line 666
                if(lobeCls_0 < hi_1)
                {
                }
                else
                {

#line 666
                    break;
                }
                uint mid_2 = (lobeCls_0 + hi_1) / 2U;
                if((&kernelContext_15)->emitCdf_0[mid_2] >= _S155)
                {

#line 669
                    hi_1 = mid_2;

#line 669
                }
                else
                {

#line 669
                    lobeCls_0 = mid_2 + 1U;

#line 669
                }

#line 666
            }

#line 674
            uint e_1 = lobeCls_0 * 16U;
            float3 a_3 = float3((&kernelContext_15)->emitters_0[e_1], (&kernelContext_15)->emitters_0[e_1 + 1U], (&kernelContext_15)->emitters_0[e_1 + 2U]);
            float3 b_2 = float3((&kernelContext_15)->emitters_0[e_1 + 3U], (&kernelContext_15)->emitters_0[e_1 + 4U], (&kernelContext_15)->emitters_0[e_1 + 5U]);
            float3 c_6 = float3((&kernelContext_15)->emitters_0[e_1 + 6U], (&kernelContext_15)->emitters_0[e_1 + 7U], (&kernelContext_15)->emitters_0[e_1 + 8U]);
            float su_0 = sqrt(ua_0);

            float3 toL_1 = a_3 * float3((1.0f - su_0))  + b_2 * float3((su_0 * (1.0f - ub_0)))  + c_6 * float3((su_0 * ub_0))  - p_1;
            float d2_1 = dot(toL_1, toL_1);
            float dist_2 = sqrt(d2_1);
            float3 wi_3 = toL_1 / float3(dist_2) ;
            float cosl_0 = abs(dot(normalize(cross(b_2 - a_3, c_6 - a_3)), wi_3));
            float cosi_1 = dot(n_3, wi_3);
            if(cosi_1 > 0.0f)
            {

#line 686
                ok_0 = cosl_0 > 9.9999997473787516e-06f;

#line 686
            }
            else
            {

#line 686
                ok_0 = false;

#line 686
            }

#line 686
            if(ok_0)
            {

#line 686
                bool _S157 = occluded_0(p_1, wi_3, dist_2 * 0.99900001287460327f, &kernelContext_15);


                if(lightingOn_0)
                {

#line 689
                    track_0 = depth_3 == 0U;

#line 689
                }
                else
                {

#line 689
                    track_0 = false;

#line 689
                }
                bool _S158 = !_S157;

#line 690
                if(_S158)
                {

#line 690
                    _S154 = true;

#line 690
                }
                else
                {

#line 690
                    _S154 = track_0;

#line 690
                }

#line 690
                if(_S154)
                {
                    float pl_2 = (1.0f - _S91) * (&kernelContext_15)->emitters_0[e_1 + 13U] * d2_1 / ((&kernelContext_15)->emitters_0[e_1 + 12U] * cosl_0);
                    float3 wiL_3 = float3(dot(wi_3, T_0), dot(wi_3, B_0), cosi_1);

#line 693
                    thread Surface_0 _S159 = surf_0;

#line 693
                    float _S160 = reflectivePdf_0(&_S159, woL_3, wiL_3);

                    float _S161 = pl_2 * pl_2;

#line 695
                    float wl_0 = _S161 / (_S161 + _S160 * _S160);
                    float3 le_2 = float3((&kernelContext_15)->emitters_0[e_1 + 9U], (&kernelContext_15)->emitters_0[e_1 + 10U], (&kernelContext_15)->emitters_0[e_1 + 11U]);

#line 696
                    thread Surface_0 _S162 = surf_0;

#line 696
                    Lobes_0 _S163 = evalLobes_0(&_S162, woL_3, wiL_3);

#line 696
                    float3 _S164 = float3(pl_2) ;

#line 696
                    float3 _S165 = float3(wl_0) ;

                    float3 cd_2 = thr_0 * _S163.diffuse_0 * le_2 / _S164 * _S165;
                    float3 cs_2 = thr_0 * _S163.specular_1 * le_2 / _S164 * _S165;
                    if(_S158)
                    {

#line 700
                        thread Surface_0 _S166 = surf_0;

#line 700
                        float3 _S167 = evalReflective_0(&_S166, woL_3, wiL_3);
                        Parts_addLight_0(&parts_0, depth_3, cls_3, thr_0 * _S167 * le_2 / _S164 * _S165, cd_2, cs_2);

#line 700
                    }

                    if(track_0)
                    {
                        float vv_1 = lum_0(cd_2 + cs_2);
                        float visTotal_4 = visTotal_2 + vv_1;
                        if(_S157)
                        {

#line 706
                            dist_0 = 0.0f;

#line 706
                        }
                        else
                        {

#line 706
                            dist_0 = vv_1;

#line 706
                        }

#line 706
                        float visLit_5 = visLit_3 + dist_0;

#line 706
                        float3 _S168 = float3(cosi_1) ;
                        float3 _S169 = cd_2 / _S168;

#line 707
                        float3 _S170 = cs_2 / _S168;

#line 707
                        if(_S157)
                        {

#line 707
                            visLit_0 = 0.0f;

#line 707
                        }
                        else
                        {

#line 707
                            visLit_0 = 1.0f;

#line 707
                        }

#line 707
                        if(_S157)
                        {

#line 707
                            visTotal_0 = 0.0f;

#line 707
                        }
                        else
                        {

#line 707
                            visTotal_0 = cosi_1;

#line 707
                        }

#line 707
                        addSlot_0(pixel_1, 3U, _S169, _S170, wi_3, visLit_0, visTotal_0, &kernelContext_15);

#line 707
                        dist_0 = visTotal_4;

#line 707
                        visLit_0 = visLit_5;

#line 702
                    }
                    else
                    {

#line 702
                        dist_0 = visTotal_2;

#line 702
                        visLit_0 = visLit_3;

#line 702
                    }

#line 690
                }
                else
                {

#line 690
                    dist_0 = visTotal_2;

#line 690
                    visLit_0 = visLit_3;

#line 690
                }

#line 686
            }
            else
            {

#line 686
                dist_0 = visTotal_2;

#line 686
                visLit_0 = visLit_3;

#line 686
            }

#line 659
        }
        else
        {

#line 659
            dist_0 = visTotal_2;

#line 659
            visLit_0 = visLit_3;

#line 659
        }

#line 659
        float _S171;

#line 713
        if(chooseEnv_0)
        {
            float e1_0 = Rng_next_0(&rng_0);
            float e2_0 = Rng_next_0(&rng_0);
            float e3_1 = Rng_next_0(&rng_0);
            float e4_0 = Rng_next_0(&rng_0);
            thread float pdfE_0;
            thread float3 leE_0;

#line 720
            float3 _S172 = envSample_0(e1_0, e2_0, e3_1, e4_0, &pdfE_0, &leE_0, &kernelContext_15);

            float cosi_2 = dot(n_3, _S172);
            if(pdfE_0 > 0.0f)
            {

#line 723
                ok_0 = cosi_2 > 0.0f;

#line 723
            }
            else
            {

#line 723
                ok_0 = false;

#line 723
            }

#line 723
            if(ok_0)
            {

#line 723
                bool _S173 = occluded_0(p_1, _S172, 1.00000001504746622e+30f, &kernelContext_15);


                if(lightingOn_0)
                {

#line 726
                    track_0 = depth_3 == 0U;

#line 726
                }
                else
                {

#line 726
                    track_0 = false;

#line 726
                }
                bool _S174 = !_S173;

#line 727
                if(_S174)
                {

#line 727
                    _S154 = true;

#line 727
                }
                else
                {

#line 727
                    _S154 = track_0;

#line 727
                }

#line 727
                if(_S154)
                {
                    float pl_3 = _S91 * pdfE_0;
                    float3 wiL_4 = float3(dot(_S172, T_0), dot(_S172, B_0), cosi_2);

#line 730
                    thread Surface_0 _S175 = surf_0;

#line 730
                    float _S176 = reflectivePdf_0(&_S175, woL_3, wiL_4);

                    float _S177 = pl_3 * pl_3;

#line 732
                    float wl_1 = _S177 / (_S177 + _S176 * _S176);

#line 732
                    thread Surface_0 _S178 = surf_0;

#line 732
                    Lobes_0 _S179 = evalLobes_0(&_S178, woL_3, wiL_4);

#line 732
                    float3 _S180 = float3(pl_3) ;

#line 732
                    float3 _S181 = float3(wl_1) ;

                    float3 cd_3 = thr_0 * _S179.diffuse_0 * leE_0 / _S180 * _S181;
                    float3 cs_3 = thr_0 * _S179.specular_1 * leE_0 / _S180 * _S181;
                    if(_S174)
                    {

#line 736
                        thread Surface_0 _S182 = surf_0;

#line 736
                        float3 _S183 = evalReflective_0(&_S182, woL_3, wiL_4);
                        Parts_addLight_0(&parts_0, depth_3, cls_3, thr_0 * _S183 * leE_0 / _S180 * _S181, cd_3, cs_3);

#line 736
                    }

                    if(track_0)
                    {
                        float vv_2 = lum_0(cd_3 + cs_3);
                        float visTotal_5 = dist_0 + vv_2;
                        if(_S173)
                        {

#line 742
                            visTotal_0 = 0.0f;

#line 742
                        }
                        else
                        {

#line 742
                            visTotal_0 = vv_2;

#line 742
                        }

#line 742
                        float visLit_6 = visLit_0 + visTotal_0;

#line 742
                        float3 _S184 = float3(cosi_2) ;
                        float3 _S185 = cd_3 / _S184;

#line 743
                        float3 _S186 = cs_3 / _S184;

#line 743
                        if(_S173)
                        {

#line 743
                            visLit_1 = 0.0f;

#line 743
                        }
                        else
                        {

#line 743
                            visLit_1 = 1.0f;

#line 743
                        }

#line 743
                        if(_S173)
                        {

#line 743
                            _S171 = 0.0f;

#line 743
                        }
                        else
                        {

#line 743
                            _S171 = cosi_2;

#line 743
                        }

#line 743
                        addSlot_0(pixel_1, 3U, _S185, _S186, _S172, visLit_1, _S171, &kernelContext_15);

#line 743
                        visTotal_0 = visTotal_5;

#line 743
                        visLit_1 = visLit_6;

#line 738
                    }
                    else
                    {

#line 738
                        visTotal_0 = dist_0;

#line 738
                        visLit_1 = visLit_0;

#line 738
                    }

#line 727
                }
                else
                {

#line 727
                    visTotal_0 = dist_0;

#line 727
                    visLit_1 = visLit_0;

#line 727
                }

#line 723
            }
            else
            {

#line 723
                visTotal_0 = dist_0;

#line 723
                visLit_1 = visLit_0;

#line 723
            }

#line 713
        }
        else
        {

#line 713
            visTotal_0 = dist_0;

#line 713
            visLit_1 = visLit_0;

#line 713
        }

#line 751
        float lobe_0 = Rng_next_0(&rng_0);
        float u1_3 = Rng_next_0(&rng_0);
        float u2_3 = Rng_next_0(&rng_0);
        float u3_1 = Rng_next_0(&rng_0);

#line 760
        if(lobe_0 < metallic_1)
        {
            float3 h_6 = sampleVndf_0(woL_3, _S141, u1_3, u2_3);
            float woh_0 = dot(woL_3, h_6);
            float3 wiL_5 = float3((2.0f * woh_0))  * h_6 - woL_3;
            float _S187 = wiL_5.z;
            float3 _S188 = schlick_0(albedo_2, woh_0) * float3(G1_0(max(_S187, 0.0f), _S141)) ;

#line 766
            ok_0 = _S187 > 0.0f;

#line 766
            lobeCls_0 = 1U;

#line 766
            track_0 = false;

#line 766
            wi_1 = wiL_5;

#line 766
            li_0 = _S188;

#line 760
        }
        else
        {

#line 768
            if(lobe_0 < (metallic_1 + (1.0f - metallic_1) * transmission_2))
            {
                float3 h_7 = sampleVndf_0(woL_3, _S141, u1_3, u2_3);
                float woh_1 = dot(woL_3, h_7);
                if(u3_1 < (fresnelDielectric_0(woh_1, wB_0)))
                {
                    float3 wiL_6 = float3((2.0f * woh_1))  * h_7 - woL_3;
                    float _S189 = wiL_6.z;
                    float3 _S190 = float3(G1_0(max(_S189, 0.0f), _S141)) ;

#line 776
                    ok_0 = _S189 > 0.0f;

#line 776
                    lobeCls_0 = 1U;

#line 776
                    track_0 = false;

#line 776
                    wi_1 = wiL_6;

#line 776
                    li_0 = _S190;

#line 772
                }
                else
                {

#line 780
                    float r_5 = 1.0f / wB_0;
                    float k_2 = 1.0f - r_5 * r_5 * (1.0f - woh_1 * woh_1);

#line 781
                    float3 _S191 = float3(r_5) ;
                    float3 wiL_7 = - woL_3 * _S191 + float3((r_5 * woh_1 - sqrt(max(k_2, 0.0f))))  * h_7;
                    float _S192 = wiL_7.z;

#line 783
                    if(_S192 < 0.0f)
                    {

#line 783
                        ok_0 = k_2 > 0.0f;

#line 783
                    }
                    else
                    {

#line 783
                        ok_0 = false;

#line 783
                    }



                    float3 _S193 = albedo_2 * float3(G1_0(max(- _S192, 0.0f), _S141))  * _S191 * _S191;

#line 787
                    lobeCls_0 = 2U;

#line 787
                    track_0 = true;

#line 787
                    wi_1 = wiL_7;

#line 787
                    li_0 = _S193;

#line 772
                }

#line 768
            }
            else
            {

#line 790
                if(u3_1 < fSel_1)
                {
                    float3 h_8 = sampleVndf_0(woL_3, _S141, u1_3, u2_3);
                    float woh_2 = dot(woL_3, h_8);
                    float3 wiL_8 = float3((2.0f * woh_2))  * h_8 - woL_3;
                    float _S194 = wiL_8.z;
                    float3 _S195 = float3((fresnelDielectric_0(woh_2, ior_1) / fSel_1 * G1_0(max(_S194, 0.0f), _S141))) ;

#line 796
                    ok_0 = _S194 > 0.0f;

#line 796
                    lobeCls_0 = 1U;

#line 796
                    wi_1 = wiL_8;

#line 796
                    li_0 = _S195;

#line 790
                }
                else
                {

#line 800
                    float3 _S196 = cosineLocal_0(u1_3, u2_3);

#line 800
                    ok_0 = true;

#line 800
                    lobeCls_0 = 0U;

#line 800
                    wi_1 = _S196;

#line 800
                    li_0 = albedo_2;

#line 790
                }

#line 790
                track_0 = false;

#line 768
            }

#line 760
        }

#line 804
        if(!ok_0)
        {

#line 804
            visLit_0 = visLit_1;
            break;
        }

#line 806
        if(depth_3 == 0U)
        {

#line 806
            cls_3 = lobeCls_0;

#line 806
        }

        bool _S197 = !track_0;
        if(track_0)
        {

#line 809
            qPrev_0 = 0.0f;

#line 809
        }
        else
        {

#line 809
            thread Surface_0 _S198 = surf_0;

#line 809
            float _S199 = reflectivePdf_0(&_S198, woL_3, wi_1);

#line 809
            qPrev_0 = _S199;

#line 809
        }

        float3 _S200 = normalize(float3(wi_1.x)  * T_0 + float3(wi_1.y)  * B_0 + float3(wi_1.z)  * n_3);

#line 811
        dir_0 = _S200;

        float side_0 = dot(_S200, radiance_0);
        if(track_0)
        {

#line 814
            _S154 = side_0 >= 0.0f;

#line 814
        }
        else
        {

#line 814
            _S154 = side_0 <= 0.0f;

#line 814
        }

#line 814
        if(_S154)
        {

#line 814
            visLit_0 = visLit_1;
            break;
        }

#line 816
        if(side_0 > 0.0f)
        {

#line 816
            _S171 = 9.9999997473787516e-05f;

#line 816
        }
        else
        {

#line 816
            _S171 = -9.9999997473787516e-05f;

#line 816
        }

#line 816
        org_0 = hit_0 + radiance_0 * float3(_S171) ;
        float3 thr_1 = thr_0 * li_0;

        if(depth_3 >= 2U)
        {
            float pr_0 = clamp(max(thr_1.x, max(thr_1.y, thr_1.z)), 0.05000000074505806f, 0.94999998807907104f);
            float _S201 = Rng_next_0(&rng_0);

#line 822
            if(_S201 > pr_0)
            {

#line 822
                visLit_0 = visLit_1;
                break;
            }

#line 823
            thr_0 = thr_1 / float3(pr_0) ;

#line 819
        }
        else
        {

#line 819
            thr_0 = thr_1;

#line 819
        }

#line 450
        uint _S202 = depth_3 + 1U;

#line 450
        misPrev_0 = _S197;

#line 450
        depth_3 = _S202;

#line 450
        pathLen_0 = pathLen_1;

#line 450
        visTotal_1 = visTotal_0;

#line 450
        visLit_2 = visLit_1;

#line 450
    }

#line 828
    float3 radiance_1 = (&parts_0)->total_0;
    if(any(isnan((&parts_0)->total_0)))
    {

#line 829
        misPrev_0 = true;

#line 829
    }
    else
    {

#line 829
        misPrev_0 = any(isinf(radiance_1));

#line 829
    }

#line 829
    if(misPrev_0)
    {

#line 829
        (&parts_0)->total_0 = _S87;

#line 829
        (&parts_0)->directDiffuse_0 = _S87;

#line 829
        (&parts_0)->indirectDiffuse_0 = _S87;

#line 829
        (&parts_0)->specular_0 = _S87;

#line 829
        (&parts_0)->transmission_0 = _S87;

#line 829
        (&parts_0)->emission_0 = _S87;

#line 829
        radiance_0 = _S87;

#line 829
        visLit_0 = 0.0f;

#line 829
        visTotal_0 = 0.0f;

#line 829
    }
    else
    {

#line 829
        radiance_0 = radiance_1;

#line 829
    }

#line 837
    uint o_6 = 3U * pixel_1;
    float device* _S203 = (&kernelContext_15)->accum_0+o_6;

#line 838
    *_S203 = *_S203 + radiance_0.x;
    float device* _S204 = (&kernelContext_15)->accum_0+(o_6 + 1U);

#line 839
    *_S204 = *_S204 + radiance_0.y;
    float device* _S205 = (&kernelContext_15)->accum_0+(o_6 + 2U);

#line 840
    *_S205 = *_S205 + radiance_0.z;

    if(lightingOn_0)
    {
        uint lo_2 = 65U * pixel_1;
        array<float3, int(5)> _S206 = { { (&parts_0)->directDiffuse_0, (&parts_0)->indirectDiffuse_0, (&parts_0)->specular_0, (&parts_0)->transmission_0, (&parts_0)->emission_0 } };

#line 845
        k_1 = 0U;
        for(;;)
        {

#line 846
            if(k_1 < 5U)
            {
            }
            else
            {

#line 846
                break;
            }
            uint _S207 = lo_2 + 3U * k_1;

#line 848
            float device* _S208 = (&kernelContext_15)->lighting_0+_S207;

#line 848
            *_S208 = *_S208 + _S206[k_1].x;
            float device* _S209 = (&kernelContext_15)->lighting_0+(_S207 + 1U);

#line 849
            *_S209 = *_S209 + _S206[k_1].y;
            float device* _S210 = (&kernelContext_15)->lighting_0+(_S207 + 2U);

#line 850
            *_S210 = *_S210 + _S206[k_1].z;

#line 846
            k_1 = k_1 + 1U;

#line 846
        }

#line 852
        float device* _S211 = (&kernelContext_15)->lighting_0+(lo_2 + 15U);

#line 852
        *_S211 = *_S211 + visLit_0;
        float device* _S212 = (&kernelContext_15)->lighting_0+(lo_2 + 16U);

#line 853
        *_S212 = *_S212 + visTotal_0;

#line 842
    }

#line 855
    return;
}

