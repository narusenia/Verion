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
            

#line 36 "shaders/pathtrace.slang"
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


#line 53
float pf_0(uint i_0, KernelContext_0 thread* kernelContext_0)
{

#line 53
    return (as_type<float>((kernelContext_0->params_0[i_0])));
}


#line 43
struct Rng_0
{
    uint state_0;
};


#line 46
float Rng_next_0(Rng_0 thread* this_0)
{
    uint _S1 = pcg_0(this_0->state_0);

#line 48
    this_0->state_0 = _S1;
    return float(_S1 >> 8U) * 5.9604644775390625e-08f;
}


#line 322
struct Parts_0
{
    float3 total_0;
    float3 directDiffuse_0;
    float3 indirectDiffuse_0;
    float3 specular_0;
    float3 transmission_0;
    float3 emission_0;
};


#line 351
void Parts_file_0(Parts_0 thread* this_1, uint depth_0, uint cls_0, float3 c_0)
{
    if(depth_0 == 0U)
    {

#line 354
        this_1->emission_0 = this_1->emission_0 + c_0;

#line 353
    }
    else
    {

#line 355
        if(cls_0 == 0U)
        {

#line 356
            this_1->indirectDiffuse_0 = this_1->indirectDiffuse_0 + c_0;

#line 355
        }
        else
        {

#line 357
            if(cls_0 == 1U)
            {

#line 358
                this_1->specular_0 = this_1->specular_0 + c_0;

#line 357
            }
            else
            {
                this_1->transmission_0 = this_1->transmission_0 + c_0;

#line 357
            }

#line 355
        }

#line 353
    }

#line 361
    return;
}


#line 332
void Parts_add_0(Parts_0 thread* this_2, uint depth_1, uint cls_1, float3 c_1)
{
    this_2->total_0 = this_2->total_0 + c_1;
    Parts_file_0(this_2, depth_1, cls_1, c_1);
    return;
}


#line 171
void envCoords_0(float3 d_0, uint thread* i_1, uint thread* j_0, KernelContext_0 thread* kernelContext_1)
{
    uint w_1 = kernelContext_1->params_0[int(24)];
    uint h_0 = kernelContext_1->params_0[int(25)];

    float v_1 = acos(clamp(d_0.y, -1.0f, 1.0f)) / 3.1415927410125732f;
    *i_1 = min(uint((atan2(d_0.x, - d_0.z) * 0.15915493667125702f + 0.5f) * float(w_1)), w_1 - 1U);
    *j_0 = min(uint(v_1 * float(h_0)), h_0 - 1U);
    return;
}


#line 164
float3 envTexel_0(uint i_2, uint j_1, KernelContext_0 thread* kernelContext_2)
{
    uint o_0 = 3U * (j_1 * kernelContext_2->params_0[int(24)] + i_2);
    return float3(kernelContext_2->envPixels_0[o_0], kernelContext_2->envPixels_0[o_0 + 1U], kernelContext_2->envPixels_0[o_0 + 2U]);
}


#line 148
float lum_0(float3 c_2)
{

#line 148
    return dot(c_2, float3(0.2125999927520752f, 0.71520000696182251f, 0.072200000286102295f));
}


#line 190
float envPdf_0(float3 d_1, KernelContext_0 thread* kernelContext_3)
{
    thread uint i_3;

#line 192
    thread uint j_2;

#line 192
    envCoords_0(d_1, &i_3, &j_2, kernelContext_3);

#line 192
    float3 _S2 = envTexel_0(i_3, j_2, kernelContext_3);

    float _S3 = lum_0(_S2);

#line 194
    float _S4 = pf_0(26U, kernelContext_3);

#line 194
    return _S3 * _S4;
}


#line 181
float3 envRadiance_0(float3 d_2, KernelContext_0 thread* kernelContext_4)
{
    thread uint i_4;

#line 183
    thread uint j_3;

#line 183
    envCoords_0(d_2, &i_4, &j_3, kernelContext_4);

#line 183
    float3 _S5 = envTexel_0(i_4, j_3, kernelContext_4);

    return _S5;
}


#line 55
float3 vertexPos_0(uint v_2, KernelContext_0 thread* kernelContext_5)
{

#line 55
    uint _S6 = 3U * v_2;

#line 55
    return float3(kernelContext_5->positions_0[_S6], kernelContext_5->positions_0[_S6 + 1U], kernelContext_5->positions_0[_S6 + 2U]);
}


#line 57
float3 transformPoint_0(uint base_0, float3 p_0, KernelContext_0 thread* kernelContext_6)
{
    thread float3 r_0;

#line 59
    uint row_0 = 0U;
    for(;;)
    {

#line 60
        if(row_0 < 3U)
        {
        }
        else
        {

#line 60
            break;
        }
        uint o_1 = base_0 + 4U * row_0;
        r_0[row_0] = (as_type<float>((kernelContext_6->instances_0[o_1]))) * p_0.x + (as_type<float>((kernelContext_6->instances_0[o_1 + 1U]))) * p_0.y + (as_type<float>((kernelContext_6->instances_0[o_1 + 2U]))) * p_0.z + (as_type<float>((kernelContext_6->instances_0[o_1 + 3U])));

#line 60
        row_0 = row_0 + 1U;

#line 60
    }

#line 65
    return r_0;
}


#line 80
float3 vertexNormal_0(uint v_3, KernelContext_0 thread* kernelContext_7)
{

#line 80
    uint _S7 = 3U * v_3;

#line 80
    return float3(kernelContext_7->vnormals_0[_S7], kernelContext_7->vnormals_0[_S7 + 1U], kernelContext_7->vnormals_0[_S7 + 2U]);
}


#line 70
float3 transformNormal_0(uint base_1, float3 n_0, KernelContext_0 thread* kernelContext_8)
{
    float3 r0_0 = float3((as_type<float>((kernelContext_8->instances_0[base_1]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 1U]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 2U]))));
    float3 r1_0 = float3((as_type<float>((kernelContext_8->instances_0[base_1 + 4U]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 5U]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 6U]))));
    float3 r2_0 = float3((as_type<float>((kernelContext_8->instances_0[base_1 + 8U]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 9U]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 10U]))));
    float3 c0_0 = cross(r1_0, r2_0);

#line 75
    float s_1;
    if((dot(r0_0, c0_0)) < 0.0f)
    {

#line 76
        s_1 = -1.0f;

#line 76
    }
    else
    {

#line 76
        s_1 = 1.0f;

#line 76
    }
    return float3(s_1)  * float3(dot(c0_0, n_0), dot(cross(r2_0, r0_0), n_0), dot(cross(r0_0, r1_0), n_0));
}


#line 232
float3 texelAt_0(uint base_2, uint w_2, uint h_1, int x_0, int y_0, KernelContext_0 thread* kernelContext_9)
{
    int _S8 = int(w_2);

#line 234
    int _S9 = x_0 % _S8;

#line 234
    int _S10 = (_S9 + _S8) % _S8;

#line 234
    uint xi_0 = uint(_S10);
    int _S11 = int(h_1);

#line 235
    int _S12 = y_0 % _S11;

#line 235
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

#line 247
    float3 _S14 = texelAt_0(base_3, w_3, h_2, x0_0, y0_0, kernelContext_10);
    int _S15 = x0_0 + int(1);

#line 248
    float3 _S16 = texelAt_0(base_3, w_3, h_2, _S15, y0_0, kernelContext_10);

#line 248
    float3 _S17 = float3(tx_0) ;

#line 248
    float3 a_0 = mix(_S14, _S16, _S17);
    int _S18 = y0_0 + int(1);

#line 249
    float3 _S19 = texelAt_0(base_3, w_3, h_2, x0_0, _S18, kernelContext_10);

#line 249
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

#line 263
    uint lw_0 = w_4;

#line 263
    uint lh_0 = h_3;

#line 263
    uint k_0 = 0U;

#line 263
    uint off_0 = base_4;



    for(;;)
    {

#line 267
        if(k_0 < l0_0)
        {
        }
        else
        {

#line 267
            break;
        }
        uint off_1 = off_0 + lw_0 * lh_0;
        uint _S21 = max(lw_0 / 2U, 1U);
        uint _S22 = max(lh_0 / 2U, 1U);

#line 267
        uint _S23 = k_0 + 1U;

#line 267
        lw_0 = _S21;

#line 267
        lh_0 = _S22;

#line 267
        k_0 = _S23;

#line 267
        off_0 = off_1;

#line 267
    }

#line 267
    float3 _S24 = bilinear_0(off_0, lw_0, lh_0, uv_1, kernelContext_11);

#line 267
    bool _S25;

#line 274
    if((l0_0 + 1U) >= levels_0)
    {

#line 274
        _S25 = true;

#line 274
    }
    else
    {

#line 274
        _S25 = t_0 <= 0.0f;

#line 274
    }

#line 274
    if(_S25)
    {

#line 275
        return _S24;
    }

#line 275
    float3 _S26 = bilinear_0(off_0 + lw_0 * lh_0, max(lw_0 / 2U, 1U), max(lh_0 / 2U, 1U), uv_1, kernelContext_11);


    return mix(_S24, _S26, float3(t_0) );
}


#line 122
void basis_0(float3 n_1, float3 thread* t_1, float3 thread* b_0)
{

#line 122
    float3 a_1;

    if((abs(n_1.x)) > 0.89999997615814209f)
    {

#line 124
        a_1 = float3(0.0f, 1.0f, 0.0f);

#line 124
    }
    else
    {

#line 124
        a_1 = float3(1.0f, 0.0f, 0.0f);

#line 124
    }
    float3 _S27 = normalize(cross(n_1, a_1));

#line 125
    *b_0 = _S27;
    *t_1 = cross(_S27, n_1);
    return;
}


#line 111
float fresnelDielectric_0(float cosi_0, float eta_0)
{
    float s2_0 = (1.0f - cosi_0 * cosi_0) / (eta_0 * eta_0);
    if(s2_0 >= 1.0f)
    {

#line 115
        return 1.0f;
    }

#line 116
    float cost_0 = sqrt(1.0f - s2_0);
    float _S28 = eta_0 * cost_0;

#line 117
    float rs_0 = (cosi_0 - _S28) / (cosi_0 + _S28);
    float _S29 = eta_0 * cosi_0;

#line 118
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


#line 377 "shaders/pathtrace.slang"
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

#line 386
        bool _S30 = ((&q_0)->next());

#line 386
        if(_S30)
        {
        }
        else
        {

#line 386
            break;
        }

#line 386
    }
    uint _S31 = (_slang_committed_intersection_type_to_uint((&q_0)->get_committed_intersection_type()));

#line 387
    return _S31 == 1U;
}


#line 96
float D_0(float hz_0, float alpha_0)
{
    float a2_0 = alpha_0 * alpha_0;
    float d_4 = hz_0 * hz_0 * (a2_0 - 1.0f) + 1.0f;
    return a2_0 / (3.1415927410125732f * d_4 * d_4);
}


#line 89
float G1_0(float cosT_0, float alpha_1)
{
    float c2_0 = cosT_0 * cosT_0;

    return 2.0f / (1.0f + sqrt(1.0f + alpha_1 * alpha_1 * ((1.0f - c2_0) / max(c2_0, 9.99999993922529029e-09f))));
}


#line 103
float3 schlick_0(float3 f0_0, float c_3)
{
    float m_0 = 1.0f - saturate(c_3);
    float m2_0 = m_0 * m_0;
    return f0_0 + (float3(1.0f)  - f0_0) * float3((m2_0 * m2_0 * m_0)) ;
}


#line 292
struct Lobes_0
{
    float3 diffuse_0;
    float3 specular_1;
};


#line 281
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


#line 300
Lobes_0 evalLobes_0(const Surface_0 thread* s_2, float3 woL_0, float3 wiL_0)
{
    float3 hh_0 = normalize(woL_0 + wiL_0);
    float _S32 = max(dot(woL_0, hh_0), 0.0f);

    float _S33 = woL_0.z;

#line 305
    float _S34 = wiL_0.z;

#line 305
    float core_0 = D_0(hh_0.z, s_2->alpha_2) * G1_0(_S33, s_2->alpha_2) * G1_0(_S34, s_2->alpha_2) / (4.0f * _S33);

    thread Lobes_0 l_0;

    float _S35 = 1.0f - s_2->metallic_0;

#line 309
    float _S36 = 1.0f - s_2->transmission_1;

#line 308
    (&l_0)->specular_1 = float3(s_2->metallic_0)  * schlick_0(s_2->albedo_0, _S32) * float3(core_0)  + float3((_S35 * (s_2->transmission_1 * fresnelDielectric_0(_S32, s_2->eta_1) + _S36 * fresnelDielectric_0(_S32, s_2->ior_0)) * core_0)) ;

    (&l_0)->diffuse_0 = float3((_S35 * _S36 * (1.0f - s_2->fSel_0)))  * s_2->albedo_0 * float3((_S34 / 3.1415927410125732f)) ;
    return l_0;
}


#line 339
void Parts_addLight_0(Parts_0 thread* this_3, uint depth_2, uint cls_2, float3 c_4, float3 cd_0, float3 cs_0)
{
    this_3->total_0 = this_3->total_0 + c_4;
    if(depth_2 == 0U)
    {
        this_3->directDiffuse_0 = this_3->directDiffuse_0 + cd_0;
        this_3->specular_0 = this_3->specular_0 + cs_0;

#line 342
    }
    else
    {



        Parts_file_0(this_3, depth_2, cls_2, cd_0 + cs_0);

#line 342
    }

#line 349
    return;
}


#line 151
void addSlot_0(uint pixel_0, uint slot_0, float3 u_0, float r_1, KernelContext_0 thread* kernelContext_13)
{

#line 151
    bool _S37;

    if(any(isnan(u_0)))
    {

#line 153
        _S37 = true;

#line 153
    }
    else
    {

#line 153
        _S37 = any(isinf(u_0));

#line 153
    }

#line 153
    if(_S37)
    {

#line 154
        return;
    }

#line 155
    uint o_4 = 37U * pixel_0 + 17U + 5U * slot_0;
    float w_5 = lum_0(u_0);
    float device* _S38 = kernelContext_13->lighting_0+o_4;

#line 157
    *_S38 = *_S38 + u_0.x;
    float device* _S39 = kernelContext_13->lighting_0+(o_4 + 1U);

#line 158
    *_S39 = *_S39 + u_0.y;
    float device* _S40 = kernelContext_13->lighting_0+(o_4 + 2U);

#line 159
    *_S40 = *_S40 + u_0.z;
    float device* _S41 = kernelContext_13->lighting_0+(o_4 + 3U);

#line 160
    *_S41 = *_S41 + w_5;
    float device* _S42 = kernelContext_13->lighting_0+(o_4 + 4U);

#line 161
    *_S42 = *_S42 + w_5 * r_1;
    return;
}


#line 366
float reflectivePdf_0(const Surface_0 thread* s_3, float3 woL_1, float3 wiL_1)
{
    float3 hh_1 = normalize(woL_1 + wiL_1);

    float _S43 = woL_1.z;

    float _S44 = 1.0f - s_3->metallic_0;

#line 372
    float _S45 = 1.0f - s_3->transmission_1;

    return (s_3->metallic_0 + _S44 * (s_3->transmission_1 * fresnelDielectric_0(max(dot(woL_1, hh_1), 0.0f), s_3->eta_1) + _S45 * s_3->fSel_0)) * (G1_0(_S43, s_3->alpha_2) * D_0(hh_1.z, s_3->alpha_2) / (4.0f * _S43)) + _S44 * _S45 * (1.0f - s_3->fSel_0) * wiL_1.z / 3.1415927410125732f;
}


#line 314
float3 evalReflective_0(const Surface_0 thread* s_4, float3 woL_2, float3 wiL_2)
{

#line 314
    Lobes_0 _S46 = evalLobes_0(s_4, woL_2, wiL_2);


    return _S46.specular_1 + _S46.diffuse_0;
}


#line 197
float3 envSample_0(float u1_0, float u2_0, float u3_0, float u4_0, float thread* pdf_0, float3 thread* le_0, KernelContext_0 thread* kernelContext_14)
{

#line 197
    uint lo_0;

    uint w_6 = kernelContext_14->params_0[int(24)];
    uint h_4 = kernelContext_14->params_0[int(25)];

    uint _S47 = h_4 - 1U;

#line 202
    uint lo_1 = 0U;

#line 202
    uint hi_0 = _S47;
    for(;;)
    {

#line 203
        if(lo_1 < hi_0)
        {
        }
        else
        {

#line 203
            break;
        }
        uint mid_0 = (lo_1 + hi_0) / 2U;
        if(kernelContext_14->envMarginal_0[mid_0] >= u1_0)
        {

#line 206
            lo_0 = lo_1;

#line 206
            hi_0 = mid_0;

#line 206
        }
        else
        {

#line 206
            lo_0 = mid_0 + 1U;

#line 206
        }

#line 206
        lo_1 = lo_0;

#line 203
    }

#line 213
    uint _S48 = w_6 - 1U;

#line 213
    lo_0 = 0U;

#line 213
    hi_0 = _S48;
    for(;;)
    {

#line 214
        if(lo_0 < hi_0)
        {
        }
        else
        {

#line 214
            break;
        }
        uint mid_1 = (lo_0 + hi_0) / 2U;
        if(kernelContext_14->envCond_0[lo_1 * w_6 + mid_1] >= u2_0)
        {

#line 217
            hi_0 = mid_1;

#line 217
        }
        else
        {

#line 217
            lo_0 = mid_1 + 1U;

#line 217
        }

#line 214
    }

#line 223
    float phi_0 = ((float(lo_0) + u3_0) / float(w_6) - 0.5f) * 2.0f * 3.1415927410125732f;
    float theta_0 = (float(lo_1) + u4_0) / float(h_4) * 3.1415927410125732f;
    float st_0 = sin(theta_0);

#line 225
    float3 _S49 = envTexel_0(lo_0, lo_1, kernelContext_14);
    *le_0 = _S49;
    float _S50 = lum_0(_S49);

#line 227
    float _S51 = pf_0(26U, kernelContext_14);

#line 227
    *pdf_0 = _S50 * _S51;
    return float3(st_0 * sin(phi_0), cos(theta_0), - st_0 * cos(phi_0));
}


#line 130
float3 sampleVndf_0(float3 wo_0, float alpha_3, float u1_1, float u2_1)
{
    float3 vh_0 = normalize(float3(alpha_3 * wo_0.x, alpha_3 * wo_0.y, wo_0.z));
    float _S52 = vh_0.x;

#line 133
    float _S53 = vh_0.y;

#line 133
    float lensq_0 = _S52 * _S52 + _S53 * _S53;

#line 133
    float3 t1_0;
    if(lensq_0 > 0.0f)
    {

#line 134
        t1_0 = float3(- _S53, _S52, 0.0f) * float3(rsqrt(lensq_0)) ;

#line 134
    }
    else
    {

#line 134
        t1_0 = float3(1.0f, 0.0f, 0.0f);

#line 134
    }

    float r_2 = sqrt(u1_1);
    float phi_1 = 6.2831854820251465f * u2_1;
    float a_2 = r_2 * cos(phi_1);

    float s_5 = 0.5f * (1.0f + vh_0.z);
    float _S54 = 1.0f - a_2 * a_2;

#line 141
    float b_1 = (1.0f - s_5) * sqrt(_S54) + s_5 * (r_2 * sin(phi_1));
    float3 nh_0 = float3(a_2)  * t1_0 + float3(b_1)  * cross(vh_0, t1_0) + float3(sqrt(max(0.0f, _S54 - b_1 * b_1)))  * vh_0;
    return normalize(float3(alpha_3 * nh_0.x, alpha_3 * nh_0.y, max(0.0f, nh_0.z)));
}


#line 82
float3 cosineLocal_0(float u1_2, float u2_2)
{
    float r_3 = sqrt(u1_2);
    float phi_2 = 6.2831854820251465f * u2_2;
    return float3(r_3 * cos(phi_2), r_3 * sin(phi_2), sqrt(max(0.0f, 1.0f - u1_2)));
}


#line 392
[[kernel]] void pathtrace(uint3 tid_0 [[thread_position_in_grid]], uint device* params_1 [[buffer(6)]], metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_1 [[buffer(0)]], float device* envPixels_1 [[buffer(10)]], uint device* instances_1 [[buffer(3)]], uint device* indices_1 [[buffer(2)]], float device* positions_1 [[buffer(1)]], float device* vnormals_1 [[buffer(16)]], float device* materials_1 [[buffer(4)]], float device* uvs_1 [[buffer(13)]], uint device* texInfo_1 [[buffer(15)]], float device* texels_1 [[buffer(14)]], float device* emitters_1 [[buffer(8)]], uint device* lights_1 [[buffer(5)]], float device* lighting_1 [[buffer(17)]], float device* emitCdf_1 [[buffer(9)]], float device* envMarginal_1 [[buffer(11)]], float device* envCond_1 [[buffer(12)]], float device* accum_1 [[buffer(7)]])
{

#line 392
    uint k_1;

#line 392
    float visLit_0;

#line 392
    float visTotal_0;

#line 392
    float3 radiance_0;

#line 392
    bool track_0;

#line 392
    float dist_0;

#line 392
    float3 wi_0;

#line 392
    float3 li_0;

#line 392
    thread KernelContext_0 kernelContext_15;

#line 392
    (&kernelContext_15)->params_0 = params_1;

#line 392
    (&kernelContext_15)->scene_0 = scene_1;

#line 392
    (&kernelContext_15)->envPixels_0 = envPixels_1;

#line 392
    (&kernelContext_15)->instances_0 = instances_1;

#line 392
    (&kernelContext_15)->indices_0 = indices_1;

#line 392
    (&kernelContext_15)->positions_0 = positions_1;

#line 392
    (&kernelContext_15)->vnormals_0 = vnormals_1;

#line 392
    (&kernelContext_15)->materials_0 = materials_1;

#line 392
    (&kernelContext_15)->uvs_0 = uvs_1;

#line 392
    (&kernelContext_15)->texInfo_0 = texInfo_1;

#line 392
    (&kernelContext_15)->texels_0 = texels_1;

#line 392
    (&kernelContext_15)->emitters_0 = emitters_1;

#line 392
    (&kernelContext_15)->lights_0 = lights_1;

#line 392
    (&kernelContext_15)->lighting_0 = lighting_1;

#line 392
    (&kernelContext_15)->emitCdf_0 = emitCdf_1;

#line 392
    (&kernelContext_15)->envMarginal_0 = envMarginal_1;

#line 392
    (&kernelContext_15)->envCond_0 = envCond_1;

#line 392
    (&kernelContext_15)->accum_0 = accum_1;

    uint w_7 = params_1[int(0)];
    uint h_5 = params_1[int(1)];
    uint _S55 = tid_0.x;

#line 396
    bool misPrev_0;

#line 396
    if(_S55 >= w_7)
    {

#line 396
        misPrev_0 = true;

#line 396
    }
    else
    {

#line 396
        misPrev_0 = (tid_0.y) >= h_5;

#line 396
    }

#line 396
    if(misPrev_0)
    {

#line 397
        return;
    }

#line 398
    uint _S56 = tid_0.y;

#line 398
    uint pixel_1 = _S56 * w_7 + _S55;
    thread Rng_0 rng_0;
    (&rng_0)->state_0 = pcg_0(pixel_1 ^ (pcg_0((&kernelContext_15)->params_0[int(6)] * 2654435769U + 2135587861U)));

#line 400
    float _S57 = pf_0(2U, &kernelContext_15);



    float _S58 = float(w_7);

#line 404
    float _S59 = float(h_5);

#line 404
    float aspect_0 = _S58 / _S59;
    float _S60 = float(_S55);

#line 405
    float _S61 = Rng_next_0(&rng_0);

#line 405
    float u_1 = (2.0f * (_S60 + _S61) / _S58 - 1.0f) * aspect_0 * _S57;
    float _S62 = float(_S56);

#line 406
    float _S63 = Rng_next_0(&rng_0);
    float3 _S64 = float3(u_1, (1.0f - 2.0f * (_S62 + _S63) / _S59) * _S57, -1.0f);

#line 407
    float _S65 = pf_0(4U, &kernelContext_15);

#line 407
    float3 focal_0 = _S64 * float3(_S65) ;

#line 407
    float _S66 = pf_0(3U, &kernelContext_15);
    float _S67 = Rng_next_0(&rng_0);

#line 408
    float lensR_0 = _S66 * sqrt(_S67);
    float _S68 = Rng_next_0(&rng_0);

#line 409
    float lensA_0 = 6.2831854820251465f * _S68;
    float _S69 = lensR_0 * cos(lensA_0);

#line 410
    float _S70 = lensR_0 * sin(lensA_0);
    float3 _S71 = normalize(focal_0 - float3(_S69, _S70, 0.0f));
    thread float3 org_0;

#line 412
    thread float3 dir_0;

#line 412
    uint r_4 = 0U;
    for(;;)
    {

#line 413
        if(r_4 < 3U)
        {
        }
        else
        {

#line 413
            break;
        }
        uint _S72 = 4U * r_4;

#line 415
        uint _S73 = 8U + _S72;

#line 415
        uint _S74 = 9U + _S72;

#line 415
        uint _S75 = 10U + _S72;

#line 415
        org_0[r_4] = (as_type<float>(((&kernelContext_15)->params_0[_S73]))) * _S69 + (as_type<float>(((&kernelContext_15)->params_0[_S74]))) * _S70 + (as_type<float>(((&kernelContext_15)->params_0[_S75]))) * 0.0f + (as_type<float>(((&kernelContext_15)->params_0[11U + _S72])));
        dir_0[r_4] = (as_type<float>(((&kernelContext_15)->params_0[_S73]))) * _S71.x + (as_type<float>(((&kernelContext_15)->params_0[_S74]))) * _S71.y + (as_type<float>(((&kernelContext_15)->params_0[_S75]))) * _S71.z;

#line 413
        r_4 = r_4 + 1U;

#line 413
    }

#line 418
    dir_0 = normalize(dir_0);

#line 418
    float _S76 = pf_0(20U, &kernelContext_15);

#line 418
    float _S77 = pf_0(21U, &kernelContext_15);

#line 418
    float _S78 = pf_0(22U, &kernelContext_15);

    float3 _S79 = float3(_S76, _S77, _S78);
    float3 _S80 = float3(0.0f) ;

#line 421
    thread Parts_0 parts_0;

#line 421
    (&parts_0)->total_0 = _S80;

#line 421
    (&parts_0)->directDiffuse_0 = _S80;

#line 421
    (&parts_0)->indirectDiffuse_0 = _S80;

#line 421
    (&parts_0)->specular_0 = _S80;

#line 421
    (&parts_0)->transmission_0 = _S80;

#line 421
    (&parts_0)->emission_0 = _S80;
    bool lightingOn_0 = (&kernelContext_15)->params_0[int(28)] != 0U;



    float3 _S81 = float3(1.0f) ;
    uint _S82 = (&kernelContext_15)->params_0[int(5)];
    uint _S83 = (&kernelContext_15)->params_0[int(7)];
    uint emitterCount_0 = (&kernelContext_15)->params_0[int(23)];

    bool hasEnv_0 = (&kernelContext_15)->params_0[int(24)] > 0U;

#line 431
    float _S84;

    if(hasEnv_0)
    {

#line 433
        if(emitterCount_0 > 0U)
        {

#line 433
            _S84 = 0.5f;

#line 433
        }
        else
        {

#line 433
            _S84 = 1.0f;

#line 433
        }

#line 433
    }
    else
    {

#line 433
        _S84 = 0.0f;

#line 433
    }

#line 433
    uint cls_3 = 0U;

#line 433
    misPrev_0 = false;

#line 433
    float qPrev_0 = 0.0f;

#line 433
    uint depth_3 = 0U;

#line 433
    float3 thr_0 = _S81;

#line 433
    float pathLen_0 = 0.0f;

#line 433
    float visTotal_1 = 0.0f;

#line 433
    float visLit_1 = 0.0f;

#line 438
    for(;;)
    {

#line 438
        if(depth_3 < _S83)
        {
        }
        else
        {

#line 438
            visLit_0 = visLit_1;

#line 438
            visTotal_0 = visTotal_1;

#line 438
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

#line 447
            bool _S85 = ((&q_1)->next());

#line 447
            if(_S85)
            {
            }
            else
            {

#line 447
                break;
            }

#line 447
        }

        uint _S86 = (_slang_committed_intersection_type_to_uint((&q_1)->get_committed_intersection_type()));

#line 449
        float wB_0;

#line 449
        if(_S86 != 1U)
        {

            Parts_add_0(&parts_0, depth_3, cls_3, thr_0 * _S79);
            if(hasEnv_0)
            {

                if(misPrev_0)
                {

#line 456
                    float _S87 = envPdf_0(dir_0, &kernelContext_15);

                    float pl_0 = _S84 * _S87;
                    float _S88 = qPrev_0 * qPrev_0;

#line 459
                    float den_0 = _S88 + pl_0 * pl_0;
                    if(den_0 > 0.0f)
                    {

#line 460
                        _S84 = _S88 / den_0;

#line 460
                    }
                    else
                    {

#line 460
                        _S84 = 1.0f;

#line 460
                    }

#line 460
                    wB_0 = _S84;

#line 456
                }
                else
                {

#line 456
                    wB_0 = 1.0f;

#line 456
                }

#line 456
                float3 _S89 = envRadiance_0(dir_0, &kernelContext_15);

#line 462
                Parts_add_0(&parts_0, depth_3, cls_3, thr_0 * _S89 * float3(wB_0) );

#line 453
            }

#line 453
            visLit_0 = visLit_1;

#line 453
            visTotal_0 = visTotal_1;

#line 464
            break;
        }

        uint _S90 = ((&q_1)->get_committed_instance_id());

#line 467
        uint inst_0 = _S90 * 16U;
        uint _S91 = (&kernelContext_15)->instances_0[inst_0 + 1U];

#line 468
        uint _S92 = ((&q_1)->get_committed_primitive_id());

#line 468
        uint tri_0 = _S91 + 3U * _S92;
        uint vo_0 = (&kernelContext_15)->instances_0[inst_0];
        uint _S93 = inst_0 + 4U;

#line 470
        float3 _S94 = vertexPos_0((&kernelContext_15)->indices_0[tri_0] + vo_0, &kernelContext_15);

#line 470
        float3 _S95 = transformPoint_0(_S93, _S94, &kernelContext_15);
        uint _S96 = tri_0 + 1U;

#line 471
        float3 _S97 = vertexPos_0((&kernelContext_15)->indices_0[_S96] + vo_0, &kernelContext_15);

#line 471
        float3 _S98 = transformPoint_0(_S93, _S97, &kernelContext_15);
        uint _S99 = tri_0 + 2U;

#line 472
        float3 _S100 = vertexPos_0((&kernelContext_15)->indices_0[_S99] + vo_0, &kernelContext_15);

#line 472
        float3 _S101 = transformPoint_0(_S93, _S100, &kernelContext_15);

        float3 _S102 = _S98 - _S95;

#line 474
        float3 _S103 = _S101 - _S95;

#line 474
        float3 _S104 = cross(_S102, _S103);

#line 474
        float3 nOut_0 = normalize(_S104);
        float3 wo_1 = - dir_0;
        bool outside_0 = (dot(nOut_0, wo_1)) > 0.0f;
        if(outside_0)
        {

#line 477
            radiance_0 = nOut_0;

#line 477
        }
        else
        {

#line 477
            radiance_0 = - nOut_0;

#line 477
        }
        float pHitT_0 = ((&q_1)->get_committed_distance());
        float pathLen_1 = pathLen_0 + pHitT_0;
        float3 hit_0 = org_0 + dir_0 * float3(pHitT_0) ;

        float3 p_1 = hit_0 + radiance_0 * float3(9.9999997473787516e-05f) ;

#line 487
        float3 e3_0 = hit_0 - _S95;
        float d11_0 = dot(_S102, _S102);
        float d12_0 = dot(_S102, _S103);
        float d22_0 = dot(_S103, _S103);
        float _S105 = max(d11_0 * d22_0 - d12_0 * d12_0, 9.99999968265522539e-21f);
        float _S106 = dot(e3_0, _S102);

#line 492
        float _S107 = dot(e3_0, _S103);

#line 492
        float b1_0 = (d22_0 * _S106 - d12_0 * _S107) / _S105;
        float b2_0 = (d11_0 * _S107 - d12_0 * _S106) / _S105;



        float _S108 = 1.0f - b1_0 - b2_0;

#line 497
        float3 _S109 = vertexNormal_0((&kernelContext_15)->indices_0[tri_0] + vo_0, &kernelContext_15);

#line 497
        float3 _S110 = float3(_S108)  * _S109;

#line 497
        float3 _S111 = vertexNormal_0((&kernelContext_15)->indices_0[_S96] + vo_0, &kernelContext_15);

#line 497
        float3 _S112 = _S110 + float3(b1_0)  * _S111;

#line 497
        float3 _S113 = vertexNormal_0((&kernelContext_15)->indices_0[_S99] + vo_0, &kernelContext_15);

#line 497
        float3 nsObj_0 = _S112 + float3(b2_0)  * _S113;

#line 497
        float3 ns_0;

        if((dot(nsObj_0, nsObj_0)) > 9.999999960041972e-13f)
        {

#line 499
            float3 _S114 = transformNormal_0(_S93, nsObj_0, &kernelContext_15);

            float3 ns_1 = normalize(_S114);
            if((dot(ns_1, nOut_0)) < 0.0f)
            {

#line 502
                ns_0 = - ns_1;

#line 502
            }
            else
            {

#line 502
                ns_0 = ns_1;

#line 502
            }

#line 499
        }
        else
        {

#line 499
            ns_0 = nOut_0;

#line 499
        }

#line 499
        float3 _S115;

#line 505
        if(outside_0)
        {

#line 505
            _S115 = ns_0;

#line 505
        }
        else
        {

#line 505
            _S115 = - ns_0;

#line 505
        }

        uint mi_0 = (&kernelContext_15)->instances_0[inst_0 + 2U] * 16U;
        float3 albedo_1 = float3((&kernelContext_15)->materials_0[mi_0], (&kernelContext_15)->materials_0[mi_0 + 1U], (&kernelContext_15)->materials_0[mi_0 + 2U]);

        uint texBase_0 = uint((&kernelContext_15)->materials_0[mi_0 + 10U]);
        uint texMR_0 = uint((&kernelContext_15)->materials_0[mi_0 + 11U]);
        uint texEm_0 = uint((&kernelContext_15)->materials_0[mi_0 + 12U]);
        uint texNm_0 = uint((&kernelContext_15)->materials_0[mi_0 + 13U]);
        float2 _S116 = float2(1.0f) ;

#line 514
        bool chooseEnv_0;

#line 514
        float3 albedo_2;

#line 514
        float3 texEmission_0;

#line 514
        float3 n_2;

#line 514
        float3 n_3;

#line 514
        float2 texRM_0;

        if((texBase_0 + texMR_0 + texEm_0 + texNm_0) > 0U)
        {
            float2 uv0_0 = float2((&kernelContext_15)->uvs_0[2U * ((&kernelContext_15)->indices_0[tri_0] + vo_0)], (&kernelContext_15)->uvs_0[2U * ((&kernelContext_15)->indices_0[tri_0] + vo_0) + 1U]);


            float2 _S117 = float2((&kernelContext_15)->uvs_0[2U * ((&kernelContext_15)->indices_0[_S96] + vo_0)], (&kernelContext_15)->uvs_0[2U * ((&kernelContext_15)->indices_0[_S96] + vo_0) + 1U]) - uv0_0;

#line 521
            float2 _S118 = float2((&kernelContext_15)->uvs_0[2U * ((&kernelContext_15)->indices_0[_S99] + vo_0)], (&kernelContext_15)->uvs_0[2U * ((&kernelContext_15)->indices_0[_S99] + vo_0) + 1U]) - uv0_0;

#line 521
            float2 uv_2 = uv0_0 + float2(b1_0)  * _S117 + float2(b2_0)  * _S118;


            float _S119 = _S117.x;

#line 524
            float _S120 = _S118.y;

#line 524
            float _S121 = _S119 * _S120;

#line 524
            float _S122 = _S117.y;

#line 524
            float _S123 = _S118.x;

#line 524
            float uvPerWorld_0 = sqrt(abs(_S121 - _S122 * _S123) / max(length(_S104), 9.99999968265522539e-21f));

#line 524
            float _S124 = pf_0(27U, &kernelContext_15);
            float footprint_1 = pathLen_1 * _S124 / max(abs(dot(nOut_0, dir_0)), 0.10000000149011612f) * uvPerWorld_0;
            if(texBase_0 > 0U)
            {

#line 526
                float3 _S125 = sampleTexture_0(texBase_0 - 1U, uv_2, footprint_1, &kernelContext_15);

#line 526
                albedo_2 = albedo_1 * _S125;

#line 526
            }
            else
            {

#line 526
                albedo_2 = albedo_1;

#line 526
            }

            if(texMR_0 > 0U)
            {

#line 528
                float3 _S126 = sampleTexture_0(texMR_0 - 1U, uv_2, footprint_1, &kernelContext_15);

#line 528
                texRM_0 = _S126.yz;

#line 528
            }
            else
            {

#line 528
                texRM_0 = _S116;

#line 528
            }

            if(texEm_0 > 0U)
            {

#line 530
                float3 _S127 = sampleTexture_0(texEm_0 - 1U, uv_2, footprint_1, &kernelContext_15);

#line 530
                texEmission_0 = _S127;

#line 530
            }
            else
            {

#line 530
                texEmission_0 = _S81;

#line 530
            }

            if(texNm_0 > 0U)
            {

                float det_0 = _S121 - _S123 * _S122;

#line 535
                float3 _S128 = float3(det_0) ;
                float3 dPdu_0 = (_S102 * float3(_S120)  - _S103 * float3(_S122) ) / _S128;
                float3 dPdv_0 = (_S103 * float3(_S119)  - _S102 * float3(_S123) ) / _S128;
                float3 tg_0 = dPdu_0 - ns_0 * float3(dot(ns_0, dPdu_0)) ;
                if((abs(det_0)) > 9.99999968265522539e-21f)
                {

#line 539
                    chooseEnv_0 = (dot(tg_0, tg_0)) > 9.99999968265522539e-21f;

#line 539
                }
                else
                {

#line 539
                    chooseEnv_0 = false;

#line 539
                }

#line 539
                if(chooseEnv_0)
                {
                    float3 tg_1 = normalize(tg_0);
                    float3 bt_0 = cross(ns_0, tg_1);
                    if((dot(bt_0, dPdv_0)) > 0.0f)
                    {

#line 543
                        n_2 = - bt_0;

#line 543
                    }
                    else
                    {

#line 543
                        n_2 = bt_0;

#line 543
                    }

#line 543
                    float3 _S129 = sampleTexture_0(texNm_0 - 1U, uv_2, footprint_1, &kernelContext_15);

                    float3 nt_0 = _S129 * float3(2.0f)  - float3(1.0f) ;
                    uint _S130 = mi_0 + 14U;

#line 546
                    float3 ns_2 = normalize(float3((nt_0.x * (&kernelContext_15)->materials_0[_S130]))  * tg_1 + float3((nt_0.y * (&kernelContext_15)->materials_0[_S130]))  * n_2 + float3(nt_0.z)  * ns_0);
                    if(outside_0)
                    {

#line 547
                        n_3 = ns_2;

#line 547
                    }
                    else
                    {

#line 547
                        n_3 = - ns_2;

#line 547
                    }

#line 547
                    n_2 = n_3;

#line 539
                }
                else
                {

#line 539
                    n_2 = _S115;

#line 539
                }

#line 532
            }
            else
            {

#line 532
                n_2 = _S115;

#line 532
            }

#line 516
        }
        else
        {

#line 516
            n_2 = _S115;

#line 516
            texEmission_0 = _S81;

#line 516
            texRM_0 = _S116;

#line 516
            albedo_2 = albedo_1;

#line 516
        }

#line 553
        float woN_0 = dot(n_2, wo_1);
        if(woN_0 < 0.05000000074505806f)
        {

#line 554
            n_3 = normalize(n_2 + wo_1 * float3((0.05000000074505806f - woN_0)) );

#line 554
        }
        else
        {

#line 554
            n_3 = n_2;

#line 554
        }


        float3 le_1 = float3((&kernelContext_15)->materials_0[mi_0 + 3U], (&kernelContext_15)->materials_0[mi_0 + 4U], (&kernelContext_15)->materials_0[mi_0 + 5U]) * texEmission_0;
        if(any(le_1 > (float3(0.0f) )))
        {

            uint eb_0 = (&kernelContext_15)->instances_0[inst_0 + 3U];
            if(misPrev_0)
            {

#line 562
                chooseEnv_0 = eb_0 != 0U;

#line 562
            }
            else
            {

#line 562
                chooseEnv_0 = false;

#line 562
            }

#line 562
            if(chooseEnv_0)
            {
                uint _S131 = eb_0 - 1U;

#line 564
                uint _S132 = ((&q_1)->get_committed_primitive_id());

#line 564
                uint e_0 = (_S131 + _S132) * 16U;

                float pl_1 = (1.0f - _S84) * (&kernelContext_15)->emitters_0[e_0 + 13U] * pHitT_0 * pHitT_0 / ((&kernelContext_15)->emitters_0[e_0 + 12U] * max(abs(dot(nOut_0, dir_0)), 9.9999997473787516e-05f));
                float _S133 = qPrev_0 * qPrev_0;

#line 567
                wB_0 = _S133 / (_S133 + pl_1 * pl_1);

#line 562
            }
            else
            {

#line 562
                wB_0 = 1.0f;

#line 562
            }

#line 569
            Parts_add_0(&parts_0, depth_3, cls_3, thr_0 * le_1 * float3(wB_0) );

#line 558
        }

#line 571
        float metallic_1 = (&kernelContext_15)->materials_0[mi_0 + 6U] * texRM_0.y;
        float rough_0 = (&kernelContext_15)->materials_0[mi_0 + 7U] * texRM_0.x;
        float transmission_2 = (&kernelContext_15)->materials_0[mi_0 + 8U];
        float ior_1 = (&kernelContext_15)->materials_0[mi_0 + 9U];
        float _S134 = max(rough_0 * rough_0, 0.0010000000474974513f);
        if(outside_0)
        {

#line 576
            wB_0 = ior_1;

#line 576
        }
        else
        {

#line 576
            wB_0 = 1.0f / ior_1;

#line 576
        }

        thread float3 T_0;

#line 578
        thread float3 B_0;
        basis_0(n_3, &T_0, &B_0);
        float _S135 = max(dot(wo_1, n_3), 9.9999997473787516e-05f);

#line 580
        float3 woL_3 = float3(dot(wo_1, T_0), dot(wo_1, B_0), _S135);
        float fSel_1 = fresnelDielectric_0(_S135, ior_1);
        thread Surface_0 surf_0;
        (&surf_0)->albedo_0 = albedo_2;
        (&surf_0)->metallic_0 = metallic_1;
        (&surf_0)->alpha_2 = _S134;
        (&surf_0)->transmission_1 = transmission_2;
        (&surf_0)->ior_0 = ior_1;
        (&surf_0)->eta_1 = wB_0;
        (&surf_0)->fSel_0 = fSel_1;

#line 589
        k_1 = 0U;

#line 589
        float visTotal_2 = visTotal_1;

#line 589
        float visLit_2 = visLit_1;



        for(;;)
        {

#line 593
            if(k_1 < _S82)
            {
            }
            else
            {

#line 593
                break;
            }
            uint o_5 = k_1 * 16U;
            float3 col_0 = float3((as_type<float>(((&kernelContext_15)->lights_0[o_5 + 1U]))), (as_type<float>(((&kernelContext_15)->lights_0[o_5 + 2U]))), (as_type<float>(((&kernelContext_15)->lights_0[o_5 + 3U])))) * float3((as_type<float>(((&kernelContext_15)->lights_0[o_5 + 4U])))) ;
            float3 vec_0 = float3((as_type<float>(((&kernelContext_15)->lights_0[o_5 + 5U]))), (as_type<float>(((&kernelContext_15)->lights_0[o_5 + 6U]))), (as_type<float>(((&kernelContext_15)->lights_0[o_5 + 7U]))));



            if((&kernelContext_15)->lights_0[o_5] == 1U)
            {

#line 601
                wi_0 = - normalize(vec_0);

#line 601
                dist_0 = 1.00000001504746622e+30f;

#line 601
                li_0 = col_0;

#line 601
            }
            else
            {

#line 609
                float3 toL_0 = vec_0 - p_1;
                float d2_0 = dot(toL_0, toL_0);
                float dist_1 = sqrt(d2_0);
                float3 wi_1 = toL_0 / float3(dist_1) ;
                float3 li_1 = col_0 / float3(d2_0) ;
                if((&kernelContext_15)->lights_0[o_5] == 2U)
                {

                    float att_0 = saturate(dot(float3((as_type<float>(((&kernelContext_15)->lights_0[o_5 + 8U]))), (as_type<float>(((&kernelContext_15)->lights_0[o_5 + 9U]))), (as_type<float>(((&kernelContext_15)->lights_0[o_5 + 10U])))), - wi_1) * (as_type<float>(((&kernelContext_15)->lights_0[o_5 + 11U]))) + (as_type<float>(((&kernelContext_15)->lights_0[o_5 + 12U]))));

#line 617
                    wi_0 = li_1 * float3((att_0 * att_0)) ;

#line 614
                }
                else
                {

#line 614
                    wi_0 = li_1;

#line 614
                }

#line 600
                float3 _S136 = wi_0;

#line 600
                wi_0 = wi_1;

#line 600
                dist_0 = dist_1;

#line 600
                li_0 = _S136;
            }

#line 621
            float c_5 = dot(n_3, wi_0);
            if(c_5 > 0.0f)
            {

#line 622
                bool _S137 = occluded_0(p_1, wi_0, dist_0 - 0.0010000000474974513f, &kernelContext_15);


                if(lightingOn_0)
                {

#line 625
                    track_0 = depth_3 == 0U;

#line 625
                }
                else
                {

#line 625
                    track_0 = false;

#line 625
                }
                bool _S138 = !_S137;

#line 626
                if(_S138)
                {

#line 626
                    chooseEnv_0 = true;

#line 626
                }
                else
                {

#line 626
                    chooseEnv_0 = track_0;

#line 626
                }

#line 626
                if(chooseEnv_0)
                {
                    float3 _S139 = float3(dot(wi_0, T_0), dot(wi_0, B_0), c_5);

#line 628
                    thread Surface_0 _S140 = surf_0;

#line 628
                    Lobes_0 _S141 = evalLobes_0(&_S140, woL_3, _S139);
                    float3 cd_1 = thr_0 * _S141.diffuse_0 * li_0;
                    float3 cs_1 = thr_0 * _S141.specular_1 * li_0;
                    if(_S138)
                    {

#line 632
                        Parts_addLight_0(&parts_0, depth_3, cls_3, thr_0 * (_S141.diffuse_0 + _S141.specular_1) * li_0, cd_1, cs_1);

#line 631
                    }

                    if(track_0)
                    {
                        float vv_0 = lum_0(cd_1 + cs_1);
                        float visTotal_3 = visTotal_2 + vv_0;
                        if(_S137)
                        {

#line 637
                            visLit_0 = 0.0f;

#line 637
                        }
                        else
                        {

#line 637
                            visLit_0 = vv_0;

#line 637
                        }

#line 637
                        float visLit_3 = visLit_2 + visLit_0;
                        uint _S142 = min(k_1, 2U);

#line 638
                        float3 _S143 = cd_1 / float3(c_5) ;

#line 638
                        if(_S137)
                        {

#line 638
                            visTotal_0 = 0.0f;

#line 638
                        }
                        else
                        {

#line 638
                            visTotal_0 = c_5;

#line 638
                        }

#line 638
                        addSlot_0(pixel_1, _S142, _S143, visTotal_0, &kernelContext_15);

#line 638
                        visTotal_0 = visTotal_3;

#line 638
                        visLit_0 = visLit_3;

#line 633
                    }
                    else
                    {

#line 633
                        visTotal_0 = visTotal_2;

#line 633
                        visLit_0 = visLit_2;

#line 633
                    }

#line 626
                }
                else
                {

#line 626
                    visTotal_0 = visTotal_2;

#line 626
                    visLit_0 = visLit_2;

#line 626
                }

#line 622
            }
            else
            {

#line 622
                visTotal_0 = visTotal_2;

#line 622
                visLit_0 = visLit_2;

#line 622
            }

#line 593
            k_1 = k_1 + 1U;

#line 593
            visTotal_2 = visTotal_0;

#line 593
            visLit_2 = visLit_0;

#line 593
        }

#line 645
        float chooseLight_0 = Rng_next_0(&rng_0);
        if(hasEnv_0)
        {

#line 646
            chooseEnv_0 = chooseLight_0 < _S84;

#line 646
        }
        else
        {

#line 646
            chooseEnv_0 = false;

#line 646
        }

#line 646
        bool _S144;
        if(emitterCount_0 > 0U)
        {

#line 647
            _S144 = !chooseEnv_0;

#line 647
        }
        else
        {

#line 647
            _S144 = false;

#line 647
        }

#line 647
        bool ok_0;

#line 647
        bool _S145;

#line 647
        uint lobeCls_0;

#line 647
        if(_S144)
        {
            float _S146 = Rng_next_0(&rng_0);
            float ua_0 = Rng_next_0(&rng_0);
            float ub_0 = Rng_next_0(&rng_0);

            uint _S147 = emitterCount_0 - 1U;

#line 653
            lobeCls_0 = 0U;

#line 653
            uint hi_1 = _S147;
            for(;;)
            {

#line 654
                if(lobeCls_0 < hi_1)
                {
                }
                else
                {

#line 654
                    break;
                }
                uint mid_2 = (lobeCls_0 + hi_1) / 2U;
                if((&kernelContext_15)->emitCdf_0[mid_2] >= _S146)
                {

#line 657
                    hi_1 = mid_2;

#line 657
                }
                else
                {

#line 657
                    lobeCls_0 = mid_2 + 1U;

#line 657
                }

#line 654
            }

#line 662
            uint e_1 = lobeCls_0 * 16U;
            float3 a_3 = float3((&kernelContext_15)->emitters_0[e_1], (&kernelContext_15)->emitters_0[e_1 + 1U], (&kernelContext_15)->emitters_0[e_1 + 2U]);
            float3 b_2 = float3((&kernelContext_15)->emitters_0[e_1 + 3U], (&kernelContext_15)->emitters_0[e_1 + 4U], (&kernelContext_15)->emitters_0[e_1 + 5U]);
            float3 c_6 = float3((&kernelContext_15)->emitters_0[e_1 + 6U], (&kernelContext_15)->emitters_0[e_1 + 7U], (&kernelContext_15)->emitters_0[e_1 + 8U]);
            float su_0 = sqrt(ua_0);

            float3 toL_1 = a_3 * float3((1.0f - su_0))  + b_2 * float3((su_0 * (1.0f - ub_0)))  + c_6 * float3((su_0 * ub_0))  - p_1;
            float d2_1 = dot(toL_1, toL_1);
            float dist_2 = sqrt(d2_1);
            float3 wi_2 = toL_1 / float3(dist_2) ;
            float cosl_0 = abs(dot(normalize(cross(b_2 - a_3, c_6 - a_3)), wi_2));
            float cosi_1 = dot(n_3, wi_2);
            if(cosi_1 > 0.0f)
            {

#line 674
                ok_0 = cosl_0 > 9.9999997473787516e-06f;

#line 674
            }
            else
            {

#line 674
                ok_0 = false;

#line 674
            }

#line 674
            if(ok_0)
            {

#line 674
                bool _S148 = occluded_0(p_1, wi_2, dist_2 * 0.99900001287460327f, &kernelContext_15);


                if(lightingOn_0)
                {

#line 677
                    track_0 = depth_3 == 0U;

#line 677
                }
                else
                {

#line 677
                    track_0 = false;

#line 677
                }
                bool _S149 = !_S148;

#line 678
                if(_S149)
                {

#line 678
                    _S145 = true;

#line 678
                }
                else
                {

#line 678
                    _S145 = track_0;

#line 678
                }

#line 678
                if(_S145)
                {
                    float pl_2 = (1.0f - _S84) * (&kernelContext_15)->emitters_0[e_1 + 13U] * d2_1 / ((&kernelContext_15)->emitters_0[e_1 + 12U] * cosl_0);
                    float3 wiL_3 = float3(dot(wi_2, T_0), dot(wi_2, B_0), cosi_1);

#line 681
                    thread Surface_0 _S150 = surf_0;

#line 681
                    float _S151 = reflectivePdf_0(&_S150, woL_3, wiL_3);

                    float _S152 = pl_2 * pl_2;

#line 683
                    float wl_0 = _S152 / (_S152 + _S151 * _S151);
                    float3 le_2 = float3((&kernelContext_15)->emitters_0[e_1 + 9U], (&kernelContext_15)->emitters_0[e_1 + 10U], (&kernelContext_15)->emitters_0[e_1 + 11U]);

#line 684
                    thread Surface_0 _S153 = surf_0;

#line 684
                    Lobes_0 _S154 = evalLobes_0(&_S153, woL_3, wiL_3);

#line 684
                    float3 _S155 = float3(pl_2) ;

#line 684
                    float3 _S156 = float3(wl_0) ;

                    float3 cd_2 = thr_0 * _S154.diffuse_0 * le_2 / _S155 * _S156;
                    float3 cs_2 = thr_0 * _S154.specular_1 * le_2 / _S155 * _S156;
                    if(_S149)
                    {

#line 688
                        thread Surface_0 _S157 = surf_0;

#line 688
                        float3 _S158 = evalReflective_0(&_S157, woL_3, wiL_3);
                        Parts_addLight_0(&parts_0, depth_3, cls_3, thr_0 * _S158 * le_2 / _S155 * _S156, cd_2, cs_2);

#line 688
                    }

                    if(track_0)
                    {
                        float vv_1 = lum_0(cd_2 + cs_2);
                        float visTotal_4 = visTotal_2 + vv_1;
                        if(_S148)
                        {

#line 694
                            dist_0 = 0.0f;

#line 694
                        }
                        else
                        {

#line 694
                            dist_0 = vv_1;

#line 694
                        }

#line 694
                        float visLit_4 = visLit_2 + dist_0;
                        float3 _S159 = cd_2 / float3(cosi_1) ;

#line 695
                        if(_S148)
                        {

#line 695
                            visLit_0 = 0.0f;

#line 695
                        }
                        else
                        {

#line 695
                            visLit_0 = cosi_1;

#line 695
                        }

#line 695
                        addSlot_0(pixel_1, 3U, _S159, visLit_0, &kernelContext_15);

#line 695
                        dist_0 = visTotal_4;

#line 695
                        visLit_0 = visLit_4;

#line 690
                    }
                    else
                    {

#line 690
                        dist_0 = visTotal_2;

#line 690
                        visLit_0 = visLit_2;

#line 690
                    }

#line 678
                }
                else
                {

#line 678
                    dist_0 = visTotal_2;

#line 678
                    visLit_0 = visLit_2;

#line 678
                }

#line 674
            }
            else
            {

#line 674
                dist_0 = visTotal_2;

#line 674
                visLit_0 = visLit_2;

#line 674
            }

#line 647
        }
        else
        {

#line 647
            dist_0 = visTotal_2;

#line 647
            visLit_0 = visLit_2;

#line 647
        }

#line 647
        float visLit_5;

#line 701
        if(chooseEnv_0)
        {
            float e1_0 = Rng_next_0(&rng_0);
            float e2_0 = Rng_next_0(&rng_0);
            float e3_1 = Rng_next_0(&rng_0);
            float e4_0 = Rng_next_0(&rng_0);
            thread float pdfE_0;
            thread float3 leE_0;

#line 708
            float3 _S160 = envSample_0(e1_0, e2_0, e3_1, e4_0, &pdfE_0, &leE_0, &kernelContext_15);

            float cosi_2 = dot(n_3, _S160);
            if(pdfE_0 > 0.0f)
            {

#line 711
                ok_0 = cosi_2 > 0.0f;

#line 711
            }
            else
            {

#line 711
                ok_0 = false;

#line 711
            }

#line 711
            if(ok_0)
            {

#line 711
                bool _S161 = occluded_0(p_1, _S160, 1.00000001504746622e+30f, &kernelContext_15);


                if(lightingOn_0)
                {

#line 714
                    track_0 = depth_3 == 0U;

#line 714
                }
                else
                {

#line 714
                    track_0 = false;

#line 714
                }
                bool _S162 = !_S161;

#line 715
                if(_S162)
                {

#line 715
                    _S145 = true;

#line 715
                }
                else
                {

#line 715
                    _S145 = track_0;

#line 715
                }

#line 715
                if(_S145)
                {
                    float pl_3 = _S84 * pdfE_0;
                    float3 wiL_4 = float3(dot(_S160, T_0), dot(_S160, B_0), cosi_2);

#line 718
                    thread Surface_0 _S163 = surf_0;

#line 718
                    float _S164 = reflectivePdf_0(&_S163, woL_3, wiL_4);

                    float _S165 = pl_3 * pl_3;

#line 720
                    float wl_1 = _S165 / (_S165 + _S164 * _S164);

#line 720
                    thread Surface_0 _S166 = surf_0;

#line 720
                    Lobes_0 _S167 = evalLobes_0(&_S166, woL_3, wiL_4);

#line 720
                    float3 _S168 = float3(pl_3) ;

#line 720
                    float3 _S169 = float3(wl_1) ;

                    float3 cd_3 = thr_0 * _S167.diffuse_0 * leE_0 / _S168 * _S169;
                    float3 cs_3 = thr_0 * _S167.specular_1 * leE_0 / _S168 * _S169;
                    if(_S162)
                    {

#line 724
                        thread Surface_0 _S170 = surf_0;

#line 724
                        float3 _S171 = evalReflective_0(&_S170, woL_3, wiL_4);
                        Parts_addLight_0(&parts_0, depth_3, cls_3, thr_0 * _S171 * leE_0 / _S168 * _S169, cd_3, cs_3);

#line 724
                    }

                    if(track_0)
                    {
                        float vv_2 = lum_0(cd_3 + cs_3);
                        float visTotal_5 = dist_0 + vv_2;
                        if(_S161)
                        {

#line 730
                            visTotal_0 = 0.0f;

#line 730
                        }
                        else
                        {

#line 730
                            visTotal_0 = vv_2;

#line 730
                        }

#line 730
                        float visLit_6 = visLit_0 + visTotal_0;
                        float3 _S172 = cd_3 / float3(cosi_2) ;

#line 731
                        if(_S161)
                        {

#line 731
                            visLit_5 = 0.0f;

#line 731
                        }
                        else
                        {

#line 731
                            visLit_5 = cosi_2;

#line 731
                        }

#line 731
                        addSlot_0(pixel_1, 3U, _S172, visLit_5, &kernelContext_15);

#line 731
                        visTotal_0 = visTotal_5;

#line 731
                        visLit_5 = visLit_6;

#line 726
                    }
                    else
                    {

#line 726
                        visTotal_0 = dist_0;

#line 726
                        visLit_5 = visLit_0;

#line 726
                    }

#line 715
                }
                else
                {

#line 715
                    visTotal_0 = dist_0;

#line 715
                    visLit_5 = visLit_0;

#line 715
                }

#line 711
            }
            else
            {

#line 711
                visTotal_0 = dist_0;

#line 711
                visLit_5 = visLit_0;

#line 711
            }

#line 701
        }
        else
        {

#line 701
            visTotal_0 = dist_0;

#line 701
            visLit_5 = visLit_0;

#line 701
        }

#line 739
        float lobe_0 = Rng_next_0(&rng_0);
        float u1_3 = Rng_next_0(&rng_0);
        float u2_3 = Rng_next_0(&rng_0);
        float u3_1 = Rng_next_0(&rng_0);

#line 748
        if(lobe_0 < metallic_1)
        {
            float3 h_6 = sampleVndf_0(woL_3, _S134, u1_3, u2_3);
            float woh_0 = dot(woL_3, h_6);
            float3 wiL_5 = float3((2.0f * woh_0))  * h_6 - woL_3;
            float _S173 = wiL_5.z;
            float3 _S174 = schlick_0(albedo_2, woh_0) * float3(G1_0(max(_S173, 0.0f), _S134)) ;

#line 754
            ok_0 = _S173 > 0.0f;

#line 754
            lobeCls_0 = 1U;

#line 754
            track_0 = false;

#line 754
            wi_0 = wiL_5;

#line 754
            li_0 = _S174;

#line 748
        }
        else
        {

#line 756
            if(lobe_0 < (metallic_1 + (1.0f - metallic_1) * transmission_2))
            {
                float3 h_7 = sampleVndf_0(woL_3, _S134, u1_3, u2_3);
                float woh_1 = dot(woL_3, h_7);
                if(u3_1 < (fresnelDielectric_0(woh_1, wB_0)))
                {
                    float3 wiL_6 = float3((2.0f * woh_1))  * h_7 - woL_3;
                    float _S175 = wiL_6.z;
                    float3 _S176 = float3(G1_0(max(_S175, 0.0f), _S134)) ;

#line 764
                    ok_0 = _S175 > 0.0f;

#line 764
                    lobeCls_0 = 1U;

#line 764
                    track_0 = false;

#line 764
                    wi_0 = wiL_6;

#line 764
                    li_0 = _S176;

#line 760
                }
                else
                {

#line 768
                    float r_5 = 1.0f / wB_0;
                    float k_2 = 1.0f - r_5 * r_5 * (1.0f - woh_1 * woh_1);

#line 769
                    float3 _S177 = float3(r_5) ;
                    float3 wiL_7 = - woL_3 * _S177 + float3((r_5 * woh_1 - sqrt(max(k_2, 0.0f))))  * h_7;
                    float _S178 = wiL_7.z;

#line 771
                    if(_S178 < 0.0f)
                    {

#line 771
                        ok_0 = k_2 > 0.0f;

#line 771
                    }
                    else
                    {

#line 771
                        ok_0 = false;

#line 771
                    }



                    float3 _S179 = albedo_2 * float3(G1_0(max(- _S178, 0.0f), _S134))  * _S177 * _S177;

#line 775
                    lobeCls_0 = 2U;

#line 775
                    track_0 = true;

#line 775
                    wi_0 = wiL_7;

#line 775
                    li_0 = _S179;

#line 760
                }

#line 756
            }
            else
            {

#line 778
                if(u3_1 < fSel_1)
                {
                    float3 h_8 = sampleVndf_0(woL_3, _S134, u1_3, u2_3);
                    float woh_2 = dot(woL_3, h_8);
                    float3 wiL_8 = float3((2.0f * woh_2))  * h_8 - woL_3;
                    float _S180 = wiL_8.z;
                    float3 _S181 = float3((fresnelDielectric_0(woh_2, ior_1) / fSel_1 * G1_0(max(_S180, 0.0f), _S134))) ;

#line 784
                    ok_0 = _S180 > 0.0f;

#line 784
                    lobeCls_0 = 1U;

#line 784
                    wi_0 = wiL_8;

#line 784
                    li_0 = _S181;

#line 778
                }
                else
                {

#line 788
                    float3 _S182 = cosineLocal_0(u1_3, u2_3);

#line 788
                    ok_0 = true;

#line 788
                    lobeCls_0 = 0U;

#line 788
                    wi_0 = _S182;

#line 788
                    li_0 = albedo_2;

#line 778
                }

#line 778
                track_0 = false;

#line 756
            }

#line 748
        }

#line 792
        if(!ok_0)
        {

#line 792
            visLit_0 = visLit_5;
            break;
        }

#line 794
        if(depth_3 == 0U)
        {

#line 794
            cls_3 = lobeCls_0;

#line 794
        }

        bool _S183 = !track_0;
        if(track_0)
        {

#line 797
            qPrev_0 = 0.0f;

#line 797
        }
        else
        {

#line 797
            thread Surface_0 _S184 = surf_0;

#line 797
            float _S185 = reflectivePdf_0(&_S184, woL_3, wi_0);

#line 797
            qPrev_0 = _S185;

#line 797
        }

        float3 _S186 = normalize(float3(wi_0.x)  * T_0 + float3(wi_0.y)  * B_0 + float3(wi_0.z)  * n_3);

#line 799
        dir_0 = _S186;

        float side_0 = dot(_S186, radiance_0);
        if(track_0)
        {

#line 802
            _S145 = side_0 >= 0.0f;

#line 802
        }
        else
        {

#line 802
            _S145 = side_0 <= 0.0f;

#line 802
        }

#line 802
        if(_S145)
        {

#line 802
            visLit_0 = visLit_5;
            break;
        }

#line 803
        float _S187;
        if(side_0 > 0.0f)
        {

#line 804
            _S187 = 9.9999997473787516e-05f;

#line 804
        }
        else
        {

#line 804
            _S187 = -9.9999997473787516e-05f;

#line 804
        }

#line 804
        org_0 = hit_0 + radiance_0 * float3(_S187) ;
        float3 thr_1 = thr_0 * li_0;

        if(depth_3 >= 2U)
        {
            float pr_0 = clamp(max(thr_1.x, max(thr_1.y, thr_1.z)), 0.05000000074505806f, 0.94999998807907104f);
            float _S188 = Rng_next_0(&rng_0);

#line 810
            if(_S188 > pr_0)
            {

#line 810
                visLit_0 = visLit_5;
                break;
            }

#line 811
            thr_0 = thr_1 / float3(pr_0) ;

#line 807
        }
        else
        {

#line 807
            thr_0 = thr_1;

#line 807
        }

#line 438
        uint _S189 = depth_3 + 1U;

#line 438
        misPrev_0 = _S183;

#line 438
        depth_3 = _S189;

#line 438
        pathLen_0 = pathLen_1;

#line 438
        visTotal_1 = visTotal_0;

#line 438
        visLit_1 = visLit_5;

#line 438
    }

#line 816
    float3 radiance_1 = (&parts_0)->total_0;
    if(any(isnan((&parts_0)->total_0)))
    {

#line 817
        misPrev_0 = true;

#line 817
    }
    else
    {

#line 817
        misPrev_0 = any(isinf(radiance_1));

#line 817
    }

#line 817
    if(misPrev_0)
    {

#line 817
        (&parts_0)->total_0 = _S80;

#line 817
        (&parts_0)->directDiffuse_0 = _S80;

#line 817
        (&parts_0)->indirectDiffuse_0 = _S80;

#line 817
        (&parts_0)->specular_0 = _S80;

#line 817
        (&parts_0)->transmission_0 = _S80;

#line 817
        (&parts_0)->emission_0 = _S80;

#line 817
        radiance_0 = _S80;

#line 817
        visLit_0 = 0.0f;

#line 817
        visTotal_0 = 0.0f;

#line 817
    }
    else
    {

#line 817
        radiance_0 = radiance_1;

#line 817
    }

#line 825
    uint o_6 = 3U * pixel_1;
    float device* _S190 = (&kernelContext_15)->accum_0+o_6;

#line 826
    *_S190 = *_S190 + radiance_0.x;
    float device* _S191 = (&kernelContext_15)->accum_0+(o_6 + 1U);

#line 827
    *_S191 = *_S191 + radiance_0.y;
    float device* _S192 = (&kernelContext_15)->accum_0+(o_6 + 2U);

#line 828
    *_S192 = *_S192 + radiance_0.z;

    if(lightingOn_0)
    {
        uint lo_2 = 37U * pixel_1;
        array<float3, int(5)> _S193 = { { (&parts_0)->directDiffuse_0, (&parts_0)->indirectDiffuse_0, (&parts_0)->specular_0, (&parts_0)->transmission_0, (&parts_0)->emission_0 } };

#line 833
        k_1 = 0U;
        for(;;)
        {

#line 834
            if(k_1 < 5U)
            {
            }
            else
            {

#line 834
                break;
            }
            uint _S194 = lo_2 + 3U * k_1;

#line 836
            float device* _S195 = (&kernelContext_15)->lighting_0+_S194;

#line 836
            *_S195 = *_S195 + _S193[k_1].x;
            float device* _S196 = (&kernelContext_15)->lighting_0+(_S194 + 1U);

#line 837
            *_S196 = *_S196 + _S193[k_1].y;
            float device* _S197 = (&kernelContext_15)->lighting_0+(_S194 + 2U);

#line 838
            *_S197 = *_S197 + _S193[k_1].z;

#line 834
            k_1 = k_1 + 1U;

#line 834
        }

#line 840
        float device* _S198 = (&kernelContext_15)->lighting_0+(lo_2 + 15U);

#line 840
        *_S198 = *_S198 + visLit_0;
        float device* _S199 = (&kernelContext_15)->lighting_0+(lo_2 + 16U);

#line 841
        *_S199 = *_S199 + visTotal_0;

#line 830
    }

#line 843
    return;
}

