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
            

#line 31 "shaders/pathtrace.slang"
uint pcg_0(uint v_0)
{
    uint s_0 = v_0 * 747796405U + 2891336453U;
    uint w_0 = ((s_0 >> ((s_0 >> 28U) + 4U)) ^ s_0) * 277803737U;
    return (w_0 >> 22U) ^ w_0;
}


#line 25
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
    float device* lighting_0;
};


float pf_0(uint i_0, KernelContext_0 thread* kernelContext_0)
{

#line 48
    return (as_type<float>((kernelContext_0->params_0[i_0])));
}


#line 38
struct Rng_0
{
    uint state_0;
};


#line 41
float Rng_next_0(Rng_0 thread* this_0)
{
    uint _S1 = pcg_0(this_0->state_0);

#line 43
    this_0->state_0 = _S1;
    return float(_S1 >> 8U) * 5.9604644775390625e-08f;
}


#line 303
struct Parts_0
{
    float3 total_0;
    float3 directDiffuse_0;
    float3 indirectDiffuse_0;
    float3 specular_0;
    float3 transmission_0;
    float3 emission_0;
};


#line 332
void Parts_file_0(Parts_0 thread* this_1, uint depth_0, uint cls_0, float3 c_0)
{
    if(depth_0 == 0U)
    {

#line 335
        this_1->emission_0 = this_1->emission_0 + c_0;

#line 334
    }
    else
    {

#line 336
        if(cls_0 == 0U)
        {

#line 337
            this_1->indirectDiffuse_0 = this_1->indirectDiffuse_0 + c_0;

#line 336
        }
        else
        {

#line 338
            if(cls_0 == 1U)
            {

#line 339
                this_1->specular_0 = this_1->specular_0 + c_0;

#line 338
            }
            else
            {
                this_1->transmission_0 = this_1->transmission_0 + c_0;

#line 338
            }

#line 336
        }

#line 334
    }

#line 342
    return;
}


#line 313
void Parts_add_0(Parts_0 thread* this_2, uint depth_1, uint cls_1, float3 c_1)
{
    this_2->total_0 = this_2->total_0 + c_1;
    Parts_file_0(this_2, depth_1, cls_1, c_1);
    return;
}


#line 152
void envCoords_0(float3 d_0, uint thread* i_1, uint thread* j_0, KernelContext_0 thread* kernelContext_1)
{
    uint w_1 = kernelContext_1->params_0[int(24)];
    uint h_0 = kernelContext_1->params_0[int(25)];

    float v_1 = acos(clamp(d_0.y, -1.0f, 1.0f)) / 3.1415927410125732f;
    *i_1 = min(uint((atan2(d_0.x, - d_0.z) * 0.15915493667125702f + 0.5f) * float(w_1)), w_1 - 1U);
    *j_0 = min(uint(v_1 * float(h_0)), h_0 - 1U);
    return;
}


#line 145
float3 envTexel_0(uint i_2, uint j_1, KernelContext_0 thread* kernelContext_2)
{
    uint o_0 = 3U * (j_1 * kernelContext_2->params_0[int(24)] + i_2);
    return float3(kernelContext_2->envPixels_0[o_0], kernelContext_2->envPixels_0[o_0 + 1U], kernelContext_2->envPixels_0[o_0 + 2U]);
}


#line 143
float lum_0(float3 c_2)
{

#line 143
    return dot(c_2, float3(0.2125999927520752f, 0.71520000696182251f, 0.072200000286102295f));
}


#line 171
float envPdf_0(float3 d_1, KernelContext_0 thread* kernelContext_3)
{
    thread uint i_3;

#line 173
    thread uint j_2;

#line 173
    envCoords_0(d_1, &i_3, &j_2, kernelContext_3);

#line 173
    float3 _S2 = envTexel_0(i_3, j_2, kernelContext_3);

    float _S3 = lum_0(_S2);

#line 175
    float _S4 = pf_0(26U, kernelContext_3);

#line 175
    return _S3 * _S4;
}


#line 162
float3 envRadiance_0(float3 d_2, KernelContext_0 thread* kernelContext_4)
{
    thread uint i_4;

#line 164
    thread uint j_3;

#line 164
    envCoords_0(d_2, &i_4, &j_3, kernelContext_4);

#line 164
    float3 _S5 = envTexel_0(i_4, j_3, kernelContext_4);

    return _S5;
}


#line 50
float3 vertexPos_0(uint v_2, KernelContext_0 thread* kernelContext_5)
{

#line 50
    uint _S6 = 3U * v_2;

#line 50
    return float3(kernelContext_5->positions_0[_S6], kernelContext_5->positions_0[_S6 + 1U], kernelContext_5->positions_0[_S6 + 2U]);
}


#line 52
float3 transformPoint_0(uint base_0, float3 p_0, KernelContext_0 thread* kernelContext_6)
{
    thread float3 r_0;

#line 54
    uint row_0 = 0U;
    for(;;)
    {

#line 55
        if(row_0 < 3U)
        {
        }
        else
        {

#line 55
            break;
        }
        uint o_1 = base_0 + 4U * row_0;
        r_0[row_0] = (as_type<float>((kernelContext_6->instances_0[o_1]))) * p_0.x + (as_type<float>((kernelContext_6->instances_0[o_1 + 1U]))) * p_0.y + (as_type<float>((kernelContext_6->instances_0[o_1 + 2U]))) * p_0.z + (as_type<float>((kernelContext_6->instances_0[o_1 + 3U])));

#line 55
        row_0 = row_0 + 1U;

#line 55
    }

#line 60
    return r_0;
}


#line 75
float3 vertexNormal_0(uint v_3, KernelContext_0 thread* kernelContext_7)
{

#line 75
    uint _S7 = 3U * v_3;

#line 75
    return float3(kernelContext_7->vnormals_0[_S7], kernelContext_7->vnormals_0[_S7 + 1U], kernelContext_7->vnormals_0[_S7 + 2U]);
}


#line 65
float3 transformNormal_0(uint base_1, float3 n_0, KernelContext_0 thread* kernelContext_8)
{
    float3 r0_0 = float3((as_type<float>((kernelContext_8->instances_0[base_1]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 1U]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 2U]))));
    float3 r1_0 = float3((as_type<float>((kernelContext_8->instances_0[base_1 + 4U]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 5U]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 6U]))));
    float3 r2_0 = float3((as_type<float>((kernelContext_8->instances_0[base_1 + 8U]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 9U]))), (as_type<float>((kernelContext_8->instances_0[base_1 + 10U]))));
    float3 c0_0 = cross(r1_0, r2_0);

#line 70
    float s_1;
    if((dot(r0_0, c0_0)) < 0.0f)
    {

#line 71
        s_1 = -1.0f;

#line 71
    }
    else
    {

#line 71
        s_1 = 1.0f;

#line 71
    }
    return float3(s_1)  * float3(dot(c0_0, n_0), dot(cross(r2_0, r0_0), n_0), dot(cross(r0_0, r1_0), n_0));
}


#line 213
float3 texelAt_0(uint base_2, uint w_2, uint h_1, int x_0, int y_0, KernelContext_0 thread* kernelContext_9)
{
    int _S8 = int(w_2);

#line 215
    int _S9 = x_0 % _S8;

#line 215
    int _S10 = (_S9 + _S8) % _S8;

#line 215
    uint xi_0 = uint(_S10);
    int _S11 = int(h_1);

#line 216
    int _S12 = y_0 % _S11;

#line 216
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

#line 228
    float3 _S14 = texelAt_0(base_3, w_3, h_2, x0_0, y0_0, kernelContext_10);
    int _S15 = x0_0 + int(1);

#line 229
    float3 _S16 = texelAt_0(base_3, w_3, h_2, _S15, y0_0, kernelContext_10);

#line 229
    float3 _S17 = float3(tx_0) ;

#line 229
    float3 a_0 = mix(_S14, _S16, _S17);
    int _S18 = y0_0 + int(1);

#line 230
    float3 _S19 = texelAt_0(base_3, w_3, h_2, x0_0, _S18, kernelContext_10);

#line 230
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

#line 244
    uint lw_0 = w_4;

#line 244
    uint lh_0 = h_3;

#line 244
    uint k_0 = 0U;

#line 244
    uint off_0 = base_4;



    for(;;)
    {

#line 248
        if(k_0 < l0_0)
        {
        }
        else
        {

#line 248
            break;
        }
        uint off_1 = off_0 + lw_0 * lh_0;
        uint _S21 = max(lw_0 / 2U, 1U);
        uint _S22 = max(lh_0 / 2U, 1U);

#line 248
        uint _S23 = k_0 + 1U;

#line 248
        lw_0 = _S21;

#line 248
        lh_0 = _S22;

#line 248
        k_0 = _S23;

#line 248
        off_0 = off_1;

#line 248
    }

#line 248
    float3 _S24 = bilinear_0(off_0, lw_0, lh_0, uv_1, kernelContext_11);

#line 248
    bool _S25;

#line 255
    if((l0_0 + 1U) >= levels_0)
    {

#line 255
        _S25 = true;

#line 255
    }
    else
    {

#line 255
        _S25 = t_0 <= 0.0f;

#line 255
    }

#line 255
    if(_S25)
    {

#line 256
        return _S24;
    }

#line 256
    float3 _S26 = bilinear_0(off_0 + lw_0 * lh_0, max(lw_0 / 2U, 1U), max(lh_0 / 2U, 1U), uv_1, kernelContext_11);


    return mix(_S24, _S26, float3(t_0) );
}


#line 117
void basis_0(float3 n_1, float3 thread* t_1, float3 thread* b_0)
{

#line 117
    float3 a_1;

    if((abs(n_1.x)) > 0.89999997615814209f)
    {

#line 119
        a_1 = float3(0.0f, 1.0f, 0.0f);

#line 119
    }
    else
    {

#line 119
        a_1 = float3(1.0f, 0.0f, 0.0f);

#line 119
    }
    float3 _S27 = normalize(cross(n_1, a_1));

#line 120
    *b_0 = _S27;
    *t_1 = cross(_S27, n_1);
    return;
}


#line 106
float fresnelDielectric_0(float cosi_0, float eta_0)
{
    float s2_0 = (1.0f - cosi_0 * cosi_0) / (eta_0 * eta_0);
    if(s2_0 >= 1.0f)
    {

#line 110
        return 1.0f;
    }

#line 111
    float cost_0 = sqrt(1.0f - s2_0);
    float _S28 = eta_0 * cost_0;

#line 112
    float rs_0 = (cosi_0 - _S28) / (cosi_0 + _S28);
    float _S29 = eta_0 * cosi_0;

#line 113
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


#line 358 "shaders/pathtrace.slang"
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

#line 367
        bool _S30 = ((&q_0)->next());

#line 367
        if(_S30)
        {
        }
        else
        {

#line 367
            break;
        }

#line 367
    }
    uint _S31 = (_slang_committed_intersection_type_to_uint((&q_0)->get_committed_intersection_type()));

#line 368
    return _S31 == 1U;
}


#line 91
float D_0(float hz_0, float alpha_0)
{
    float a2_0 = alpha_0 * alpha_0;
    float d_4 = hz_0 * hz_0 * (a2_0 - 1.0f) + 1.0f;
    return a2_0 / (3.1415927410125732f * d_4 * d_4);
}


#line 84
float G1_0(float cosT_0, float alpha_1)
{
    float c2_0 = cosT_0 * cosT_0;

    return 2.0f / (1.0f + sqrt(1.0f + alpha_1 * alpha_1 * ((1.0f - c2_0) / max(c2_0, 9.99999993922529029e-09f))));
}


#line 98
float3 schlick_0(float3 f0_0, float c_3)
{
    float m_0 = 1.0f - saturate(c_3);
    float m2_0 = m_0 * m_0;
    return f0_0 + (float3(1.0f)  - f0_0) * float3((m2_0 * m2_0 * m_0)) ;
}


#line 273
struct Lobes_0
{
    float3 diffuse_0;
    float3 specular_1;
};


#line 262
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


#line 281
Lobes_0 evalLobes_0(const Surface_0 thread* s_2, float3 woL_0, float3 wiL_0)
{
    float3 hh_0 = normalize(woL_0 + wiL_0);
    float _S32 = max(dot(woL_0, hh_0), 0.0f);

    float _S33 = woL_0.z;

#line 286
    float _S34 = wiL_0.z;

#line 286
    float core_0 = D_0(hh_0.z, s_2->alpha_2) * G1_0(_S33, s_2->alpha_2) * G1_0(_S34, s_2->alpha_2) / (4.0f * _S33);

    thread Lobes_0 l_0;

    float _S35 = 1.0f - s_2->metallic_0;

#line 290
    float _S36 = 1.0f - s_2->transmission_1;

#line 289
    (&l_0)->specular_1 = float3(s_2->metallic_0)  * schlick_0(s_2->albedo_0, _S32) * float3(core_0)  + float3((_S35 * (s_2->transmission_1 * fresnelDielectric_0(_S32, s_2->eta_1) + _S36 * fresnelDielectric_0(_S32, s_2->ior_0)) * core_0)) ;

    (&l_0)->diffuse_0 = float3((_S35 * _S36 * (1.0f - s_2->fSel_0)))  * s_2->albedo_0 * float3((_S34 / 3.1415927410125732f)) ;
    return l_0;
}


#line 320
void Parts_addLight_0(Parts_0 thread* this_3, uint depth_2, uint cls_2, float3 c_4, float3 cd_0, float3 cs_0)
{
    this_3->total_0 = this_3->total_0 + c_4;
    if(depth_2 == 0U)
    {
        this_3->directDiffuse_0 = this_3->directDiffuse_0 + cd_0;
        this_3->specular_0 = this_3->specular_0 + cs_0;

#line 323
    }
    else
    {



        Parts_file_0(this_3, depth_2, cls_2, cd_0 + cs_0);

#line 323
    }

#line 330
    return;
}


#line 347
float reflectivePdf_0(const Surface_0 thread* s_3, float3 woL_1, float3 wiL_1)
{
    float3 hh_1 = normalize(woL_1 + wiL_1);

    float _S37 = woL_1.z;

    float _S38 = 1.0f - s_3->metallic_0;

#line 353
    float _S39 = 1.0f - s_3->transmission_1;

    return (s_3->metallic_0 + _S38 * (s_3->transmission_1 * fresnelDielectric_0(max(dot(woL_1, hh_1), 0.0f), s_3->eta_1) + _S39 * s_3->fSel_0)) * (G1_0(_S37, s_3->alpha_2) * D_0(hh_1.z, s_3->alpha_2) / (4.0f * _S37)) + _S38 * _S39 * (1.0f - s_3->fSel_0) * wiL_1.z / 3.1415927410125732f;
}


#line 295
float3 evalReflective_0(const Surface_0 thread* s_4, float3 woL_2, float3 wiL_2)
{

#line 295
    Lobes_0 _S40 = evalLobes_0(s_4, woL_2, wiL_2);


    return _S40.specular_1 + _S40.diffuse_0;
}


#line 178
float3 envSample_0(float u1_0, float u2_0, float u3_0, float u4_0, float thread* pdf_0, float3 thread* le_0, KernelContext_0 thread* kernelContext_13)
{

#line 178
    uint lo_0;

    uint w_5 = kernelContext_13->params_0[int(24)];
    uint h_4 = kernelContext_13->params_0[int(25)];

    uint _S41 = h_4 - 1U;

#line 183
    uint lo_1 = 0U;

#line 183
    uint hi_0 = _S41;
    for(;;)
    {

#line 184
        if(lo_1 < hi_0)
        {
        }
        else
        {

#line 184
            break;
        }
        uint mid_0 = (lo_1 + hi_0) / 2U;
        if(kernelContext_13->envMarginal_0[mid_0] >= u1_0)
        {

#line 187
            lo_0 = lo_1;

#line 187
            hi_0 = mid_0;

#line 187
        }
        else
        {

#line 187
            lo_0 = mid_0 + 1U;

#line 187
        }

#line 187
        lo_1 = lo_0;

#line 184
    }

#line 194
    uint _S42 = w_5 - 1U;

#line 194
    lo_0 = 0U;

#line 194
    hi_0 = _S42;
    for(;;)
    {

#line 195
        if(lo_0 < hi_0)
        {
        }
        else
        {

#line 195
            break;
        }
        uint mid_1 = (lo_0 + hi_0) / 2U;
        if(kernelContext_13->envCond_0[lo_1 * w_5 + mid_1] >= u2_0)
        {

#line 198
            hi_0 = mid_1;

#line 198
        }
        else
        {

#line 198
            lo_0 = mid_1 + 1U;

#line 198
        }

#line 195
    }

#line 204
    float phi_0 = ((float(lo_0) + u3_0) / float(w_5) - 0.5f) * 2.0f * 3.1415927410125732f;
    float theta_0 = (float(lo_1) + u4_0) / float(h_4) * 3.1415927410125732f;
    float st_0 = sin(theta_0);

#line 206
    float3 _S43 = envTexel_0(lo_0, lo_1, kernelContext_13);
    *le_0 = _S43;
    float _S44 = lum_0(_S43);

#line 208
    float _S45 = pf_0(26U, kernelContext_13);

#line 208
    *pdf_0 = _S44 * _S45;
    return float3(st_0 * sin(phi_0), cos(theta_0), - st_0 * cos(phi_0));
}


#line 125
float3 sampleVndf_0(float3 wo_0, float alpha_3, float u1_1, float u2_1)
{
    float3 vh_0 = normalize(float3(alpha_3 * wo_0.x, alpha_3 * wo_0.y, wo_0.z));
    float _S46 = vh_0.x;

#line 128
    float _S47 = vh_0.y;

#line 128
    float lensq_0 = _S46 * _S46 + _S47 * _S47;

#line 128
    float3 t1_0;
    if(lensq_0 > 0.0f)
    {

#line 129
        t1_0 = float3(- _S47, _S46, 0.0f) * float3(rsqrt(lensq_0)) ;

#line 129
    }
    else
    {

#line 129
        t1_0 = float3(1.0f, 0.0f, 0.0f);

#line 129
    }

    float r_1 = sqrt(u1_1);
    float phi_1 = 6.2831854820251465f * u2_1;
    float a_2 = r_1 * cos(phi_1);

    float s_5 = 0.5f * (1.0f + vh_0.z);
    float _S48 = 1.0f - a_2 * a_2;

#line 136
    float b_1 = (1.0f - s_5) * sqrt(_S48) + s_5 * (r_1 * sin(phi_1));
    float3 nh_0 = float3(a_2)  * t1_0 + float3(b_1)  * cross(vh_0, t1_0) + float3(sqrt(max(0.0f, _S48 - b_1 * b_1)))  * vh_0;
    return normalize(float3(alpha_3 * nh_0.x, alpha_3 * nh_0.y, max(0.0f, nh_0.z)));
}


#line 77
float3 cosineLocal_0(float u1_2, float u2_2)
{
    float r_2 = sqrt(u1_2);
    float phi_2 = 6.2831854820251465f * u2_2;
    return float3(r_2 * cos(phi_2), r_2 * sin(phi_2), sqrt(max(0.0f, 1.0f - u1_2)));
}


#line 373
[[kernel]] void pathtrace(uint3 tid_0 [[thread_position_in_grid]], uint device* params_1 [[buffer(6)]], metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_1 [[buffer(0)]], float device* envPixels_1 [[buffer(10)]], uint device* instances_1 [[buffer(3)]], uint device* indices_1 [[buffer(2)]], float device* positions_1 [[buffer(1)]], float device* vnormals_1 [[buffer(16)]], float device* materials_1 [[buffer(4)]], float device* uvs_1 [[buffer(13)]], uint device* texInfo_1 [[buffer(15)]], float device* texels_1 [[buffer(14)]], float device* emitters_1 [[buffer(8)]], uint device* lights_1 [[buffer(5)]], float device* emitCdf_1 [[buffer(9)]], float device* envMarginal_1 [[buffer(11)]], float device* envCond_1 [[buffer(12)]], float device* accum_1 [[buffer(7)]], float device* lighting_1 [[buffer(17)]])
{

#line 373
    uint k_1;

#line 373
    float visLit_0;

#line 373
    float visTotal_0;

#line 373
    float3 radiance_0;

#line 373
    bool track_0;

#line 373
    float dist_0;

#line 373
    float3 wi_0;

#line 373
    float3 li_0;

#line 373
    thread KernelContext_0 kernelContext_14;

#line 373
    (&kernelContext_14)->params_0 = params_1;

#line 373
    (&kernelContext_14)->scene_0 = scene_1;

#line 373
    (&kernelContext_14)->envPixels_0 = envPixels_1;

#line 373
    (&kernelContext_14)->instances_0 = instances_1;

#line 373
    (&kernelContext_14)->indices_0 = indices_1;

#line 373
    (&kernelContext_14)->positions_0 = positions_1;

#line 373
    (&kernelContext_14)->vnormals_0 = vnormals_1;

#line 373
    (&kernelContext_14)->materials_0 = materials_1;

#line 373
    (&kernelContext_14)->uvs_0 = uvs_1;

#line 373
    (&kernelContext_14)->texInfo_0 = texInfo_1;

#line 373
    (&kernelContext_14)->texels_0 = texels_1;

#line 373
    (&kernelContext_14)->emitters_0 = emitters_1;

#line 373
    (&kernelContext_14)->lights_0 = lights_1;

#line 373
    (&kernelContext_14)->emitCdf_0 = emitCdf_1;

#line 373
    (&kernelContext_14)->envMarginal_0 = envMarginal_1;

#line 373
    (&kernelContext_14)->envCond_0 = envCond_1;

#line 373
    (&kernelContext_14)->accum_0 = accum_1;

#line 373
    (&kernelContext_14)->lighting_0 = lighting_1;

    uint w_6 = params_1[int(0)];
    uint h_5 = params_1[int(1)];
    uint _S49 = tid_0.x;

#line 377
    bool misPrev_0;

#line 377
    if(_S49 >= w_6)
    {

#line 377
        misPrev_0 = true;

#line 377
    }
    else
    {

#line 377
        misPrev_0 = (tid_0.y) >= h_5;

#line 377
    }

#line 377
    if(misPrev_0)
    {

#line 378
        return;
    }

#line 379
    uint _S50 = tid_0.y;

#line 379
    uint pixel_0 = _S50 * w_6 + _S49;
    thread Rng_0 rng_0;
    (&rng_0)->state_0 = pcg_0(pixel_0 ^ (pcg_0((&kernelContext_14)->params_0[int(6)] * 2654435769U + 2135587861U)));

#line 381
    float _S51 = pf_0(2U, &kernelContext_14);



    float _S52 = float(w_6);

#line 385
    float _S53 = float(h_5);

#line 385
    float aspect_0 = _S52 / _S53;
    float _S54 = float(_S49);

#line 386
    float _S55 = Rng_next_0(&rng_0);

#line 386
    float u_0 = (2.0f * (_S54 + _S55) / _S52 - 1.0f) * aspect_0 * _S51;
    float _S56 = float(_S50);

#line 387
    float _S57 = Rng_next_0(&rng_0);
    float3 _S58 = float3(u_0, (1.0f - 2.0f * (_S56 + _S57) / _S53) * _S51, -1.0f);

#line 388
    float _S59 = pf_0(4U, &kernelContext_14);

#line 388
    float3 focal_0 = _S58 * float3(_S59) ;

#line 388
    float _S60 = pf_0(3U, &kernelContext_14);
    float _S61 = Rng_next_0(&rng_0);

#line 389
    float lensR_0 = _S60 * sqrt(_S61);
    float _S62 = Rng_next_0(&rng_0);

#line 390
    float lensA_0 = 6.2831854820251465f * _S62;
    float _S63 = lensR_0 * cos(lensA_0);

#line 391
    float _S64 = lensR_0 * sin(lensA_0);
    float3 _S65 = normalize(focal_0 - float3(_S63, _S64, 0.0f));
    thread float3 org_0;

#line 393
    thread float3 dir_0;

#line 393
    uint r_3 = 0U;
    for(;;)
    {

#line 394
        if(r_3 < 3U)
        {
        }
        else
        {

#line 394
            break;
        }
        uint _S66 = 4U * r_3;

#line 396
        uint _S67 = 8U + _S66;

#line 396
        uint _S68 = 9U + _S66;

#line 396
        uint _S69 = 10U + _S66;

#line 396
        org_0[r_3] = (as_type<float>(((&kernelContext_14)->params_0[_S67]))) * _S63 + (as_type<float>(((&kernelContext_14)->params_0[_S68]))) * _S64 + (as_type<float>(((&kernelContext_14)->params_0[_S69]))) * 0.0f + (as_type<float>(((&kernelContext_14)->params_0[11U + _S66])));
        dir_0[r_3] = (as_type<float>(((&kernelContext_14)->params_0[_S67]))) * _S65.x + (as_type<float>(((&kernelContext_14)->params_0[_S68]))) * _S65.y + (as_type<float>(((&kernelContext_14)->params_0[_S69]))) * _S65.z;

#line 394
        r_3 = r_3 + 1U;

#line 394
    }

#line 399
    dir_0 = normalize(dir_0);

#line 399
    float _S70 = pf_0(20U, &kernelContext_14);

#line 399
    float _S71 = pf_0(21U, &kernelContext_14);

#line 399
    float _S72 = pf_0(22U, &kernelContext_14);

    float3 _S73 = float3(_S70, _S71, _S72);
    float3 _S74 = float3(0.0f) ;

#line 402
    thread Parts_0 parts_0;

#line 402
    (&parts_0)->total_0 = _S74;

#line 402
    (&parts_0)->directDiffuse_0 = _S74;

#line 402
    (&parts_0)->indirectDiffuse_0 = _S74;

#line 402
    (&parts_0)->specular_0 = _S74;

#line 402
    (&parts_0)->transmission_0 = _S74;

#line 402
    (&parts_0)->emission_0 = _S74;
    bool lightingOn_0 = (&kernelContext_14)->params_0[int(28)] != 0U;



    float3 _S75 = float3(1.0f) ;
    uint _S76 = (&kernelContext_14)->params_0[int(5)];
    uint _S77 = (&kernelContext_14)->params_0[int(7)];
    uint emitterCount_0 = (&kernelContext_14)->params_0[int(23)];

    bool hasEnv_0 = (&kernelContext_14)->params_0[int(24)] > 0U;

#line 412
    float _S78;

    if(hasEnv_0)
    {

#line 414
        if(emitterCount_0 > 0U)
        {

#line 414
            _S78 = 0.5f;

#line 414
        }
        else
        {

#line 414
            _S78 = 1.0f;

#line 414
        }

#line 414
    }
    else
    {

#line 414
        _S78 = 0.0f;

#line 414
    }

#line 414
    uint cls_3 = 0U;

#line 414
    misPrev_0 = false;

#line 414
    float qPrev_0 = 0.0f;

#line 414
    uint depth_3 = 0U;

#line 414
    float3 thr_0 = _S75;

#line 414
    float pathLen_0 = 0.0f;

#line 414
    float visTotal_1 = 0.0f;

#line 414
    float visLit_1 = 0.0f;

#line 419
    for(;;)
    {

#line 419
        if(depth_3 < _S77)
        {
        }
        else
        {

#line 419
            visLit_0 = visLit_1;

#line 419
            visTotal_0 = visTotal_1;

#line 419
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

#line 428
            bool _S79 = ((&q_1)->next());

#line 428
            if(_S79)
            {
            }
            else
            {

#line 428
                break;
            }

#line 428
        }

        uint _S80 = (_slang_committed_intersection_type_to_uint((&q_1)->get_committed_intersection_type()));

#line 430
        float wB_0;

#line 430
        if(_S80 != 1U)
        {

            Parts_add_0(&parts_0, depth_3, cls_3, thr_0 * _S73);
            if(hasEnv_0)
            {

                if(misPrev_0)
                {

#line 437
                    float _S81 = envPdf_0(dir_0, &kernelContext_14);

                    float pl_0 = _S78 * _S81;
                    float _S82 = qPrev_0 * qPrev_0;

#line 440
                    float den_0 = _S82 + pl_0 * pl_0;
                    if(den_0 > 0.0f)
                    {

#line 441
                        _S78 = _S82 / den_0;

#line 441
                    }
                    else
                    {

#line 441
                        _S78 = 1.0f;

#line 441
                    }

#line 441
                    wB_0 = _S78;

#line 437
                }
                else
                {

#line 437
                    wB_0 = 1.0f;

#line 437
                }

#line 437
                float3 _S83 = envRadiance_0(dir_0, &kernelContext_14);

#line 443
                Parts_add_0(&parts_0, depth_3, cls_3, thr_0 * _S83 * float3(wB_0) );

#line 434
            }

#line 434
            visLit_0 = visLit_1;

#line 434
            visTotal_0 = visTotal_1;

#line 445
            break;
        }

        uint _S84 = ((&q_1)->get_committed_instance_id());

#line 448
        uint inst_0 = _S84 * 16U;
        uint _S85 = (&kernelContext_14)->instances_0[inst_0 + 1U];

#line 449
        uint _S86 = ((&q_1)->get_committed_primitive_id());

#line 449
        uint tri_0 = _S85 + 3U * _S86;
        uint vo_0 = (&kernelContext_14)->instances_0[inst_0];
        uint _S87 = inst_0 + 4U;

#line 451
        float3 _S88 = vertexPos_0((&kernelContext_14)->indices_0[tri_0] + vo_0, &kernelContext_14);

#line 451
        float3 _S89 = transformPoint_0(_S87, _S88, &kernelContext_14);
        uint _S90 = tri_0 + 1U;

#line 452
        float3 _S91 = vertexPos_0((&kernelContext_14)->indices_0[_S90] + vo_0, &kernelContext_14);

#line 452
        float3 _S92 = transformPoint_0(_S87, _S91, &kernelContext_14);
        uint _S93 = tri_0 + 2U;

#line 453
        float3 _S94 = vertexPos_0((&kernelContext_14)->indices_0[_S93] + vo_0, &kernelContext_14);

#line 453
        float3 _S95 = transformPoint_0(_S87, _S94, &kernelContext_14);

        float3 _S96 = _S92 - _S89;

#line 455
        float3 _S97 = _S95 - _S89;

#line 455
        float3 _S98 = cross(_S96, _S97);

#line 455
        float3 nOut_0 = normalize(_S98);
        float3 wo_1 = - dir_0;
        bool outside_0 = (dot(nOut_0, wo_1)) > 0.0f;
        if(outside_0)
        {

#line 458
            radiance_0 = nOut_0;

#line 458
        }
        else
        {

#line 458
            radiance_0 = - nOut_0;

#line 458
        }
        float pHitT_0 = ((&q_1)->get_committed_distance());
        float pathLen_1 = pathLen_0 + pHitT_0;
        float3 hit_0 = org_0 + dir_0 * float3(pHitT_0) ;

        float3 p_1 = hit_0 + radiance_0 * float3(9.9999997473787516e-05f) ;

#line 468
        float3 e3_0 = hit_0 - _S89;
        float d11_0 = dot(_S96, _S96);
        float d12_0 = dot(_S96, _S97);
        float d22_0 = dot(_S97, _S97);
        float _S99 = max(d11_0 * d22_0 - d12_0 * d12_0, 9.99999968265522539e-21f);
        float _S100 = dot(e3_0, _S96);

#line 473
        float _S101 = dot(e3_0, _S97);

#line 473
        float b1_0 = (d22_0 * _S100 - d12_0 * _S101) / _S99;
        float b2_0 = (d11_0 * _S101 - d12_0 * _S100) / _S99;



        float _S102 = 1.0f - b1_0 - b2_0;

#line 478
        float3 _S103 = vertexNormal_0((&kernelContext_14)->indices_0[tri_0] + vo_0, &kernelContext_14);

#line 478
        float3 _S104 = float3(_S102)  * _S103;

#line 478
        float3 _S105 = vertexNormal_0((&kernelContext_14)->indices_0[_S90] + vo_0, &kernelContext_14);

#line 478
        float3 _S106 = _S104 + float3(b1_0)  * _S105;

#line 478
        float3 _S107 = vertexNormal_0((&kernelContext_14)->indices_0[_S93] + vo_0, &kernelContext_14);

#line 478
        float3 nsObj_0 = _S106 + float3(b2_0)  * _S107;

#line 478
        float3 ns_0;

        if((dot(nsObj_0, nsObj_0)) > 9.999999960041972e-13f)
        {

#line 480
            float3 _S108 = transformNormal_0(_S87, nsObj_0, &kernelContext_14);

            float3 ns_1 = normalize(_S108);
            if((dot(ns_1, nOut_0)) < 0.0f)
            {

#line 483
                ns_0 = - ns_1;

#line 483
            }
            else
            {

#line 483
                ns_0 = ns_1;

#line 483
            }

#line 480
        }
        else
        {

#line 480
            ns_0 = nOut_0;

#line 480
        }

#line 480
        float3 _S109;

#line 486
        if(outside_0)
        {

#line 486
            _S109 = ns_0;

#line 486
        }
        else
        {

#line 486
            _S109 = - ns_0;

#line 486
        }

        uint mi_0 = (&kernelContext_14)->instances_0[inst_0 + 2U] * 16U;
        float3 albedo_1 = float3((&kernelContext_14)->materials_0[mi_0], (&kernelContext_14)->materials_0[mi_0 + 1U], (&kernelContext_14)->materials_0[mi_0 + 2U]);

        uint texBase_0 = uint((&kernelContext_14)->materials_0[mi_0 + 10U]);
        uint texMR_0 = uint((&kernelContext_14)->materials_0[mi_0 + 11U]);
        uint texEm_0 = uint((&kernelContext_14)->materials_0[mi_0 + 12U]);
        uint texNm_0 = uint((&kernelContext_14)->materials_0[mi_0 + 13U]);
        float2 _S110 = float2(1.0f) ;

#line 495
        bool chooseEnv_0;

#line 495
        float3 albedo_2;

#line 495
        float3 texEmission_0;

#line 495
        float3 n_2;

#line 495
        float3 n_3;

#line 495
        float2 texRM_0;

        if((texBase_0 + texMR_0 + texEm_0 + texNm_0) > 0U)
        {
            float2 uv0_0 = float2((&kernelContext_14)->uvs_0[2U * ((&kernelContext_14)->indices_0[tri_0] + vo_0)], (&kernelContext_14)->uvs_0[2U * ((&kernelContext_14)->indices_0[tri_0] + vo_0) + 1U]);


            float2 _S111 = float2((&kernelContext_14)->uvs_0[2U * ((&kernelContext_14)->indices_0[_S90] + vo_0)], (&kernelContext_14)->uvs_0[2U * ((&kernelContext_14)->indices_0[_S90] + vo_0) + 1U]) - uv0_0;

#line 502
            float2 _S112 = float2((&kernelContext_14)->uvs_0[2U * ((&kernelContext_14)->indices_0[_S93] + vo_0)], (&kernelContext_14)->uvs_0[2U * ((&kernelContext_14)->indices_0[_S93] + vo_0) + 1U]) - uv0_0;

#line 502
            float2 uv_2 = uv0_0 + float2(b1_0)  * _S111 + float2(b2_0)  * _S112;


            float _S113 = _S111.x;

#line 505
            float _S114 = _S112.y;

#line 505
            float _S115 = _S113 * _S114;

#line 505
            float _S116 = _S111.y;

#line 505
            float _S117 = _S112.x;

#line 505
            float uvPerWorld_0 = sqrt(abs(_S115 - _S116 * _S117) / max(length(_S98), 9.99999968265522539e-21f));

#line 505
            float _S118 = pf_0(27U, &kernelContext_14);
            float footprint_1 = pathLen_1 * _S118 / max(abs(dot(nOut_0, dir_0)), 0.10000000149011612f) * uvPerWorld_0;
            if(texBase_0 > 0U)
            {

#line 507
                float3 _S119 = sampleTexture_0(texBase_0 - 1U, uv_2, footprint_1, &kernelContext_14);

#line 507
                albedo_2 = albedo_1 * _S119;

#line 507
            }
            else
            {

#line 507
                albedo_2 = albedo_1;

#line 507
            }

            if(texMR_0 > 0U)
            {

#line 509
                float3 _S120 = sampleTexture_0(texMR_0 - 1U, uv_2, footprint_1, &kernelContext_14);

#line 509
                texRM_0 = _S120.yz;

#line 509
            }
            else
            {

#line 509
                texRM_0 = _S110;

#line 509
            }

            if(texEm_0 > 0U)
            {

#line 511
                float3 _S121 = sampleTexture_0(texEm_0 - 1U, uv_2, footprint_1, &kernelContext_14);

#line 511
                texEmission_0 = _S121;

#line 511
            }
            else
            {

#line 511
                texEmission_0 = _S75;

#line 511
            }

            if(texNm_0 > 0U)
            {

                float det_0 = _S115 - _S117 * _S116;

#line 516
                float3 _S122 = float3(det_0) ;
                float3 dPdu_0 = (_S96 * float3(_S114)  - _S97 * float3(_S116) ) / _S122;
                float3 dPdv_0 = (_S97 * float3(_S113)  - _S96 * float3(_S117) ) / _S122;
                float3 tg_0 = dPdu_0 - ns_0 * float3(dot(ns_0, dPdu_0)) ;
                if((abs(det_0)) > 9.99999968265522539e-21f)
                {

#line 520
                    chooseEnv_0 = (dot(tg_0, tg_0)) > 9.99999968265522539e-21f;

#line 520
                }
                else
                {

#line 520
                    chooseEnv_0 = false;

#line 520
                }

#line 520
                if(chooseEnv_0)
                {
                    float3 tg_1 = normalize(tg_0);
                    float3 bt_0 = cross(ns_0, tg_1);
                    if((dot(bt_0, dPdv_0)) > 0.0f)
                    {

#line 524
                        n_2 = - bt_0;

#line 524
                    }
                    else
                    {

#line 524
                        n_2 = bt_0;

#line 524
                    }

#line 524
                    float3 _S123 = sampleTexture_0(texNm_0 - 1U, uv_2, footprint_1, &kernelContext_14);

                    float3 nt_0 = _S123 * float3(2.0f)  - float3(1.0f) ;
                    uint _S124 = mi_0 + 14U;

#line 527
                    float3 ns_2 = normalize(float3((nt_0.x * (&kernelContext_14)->materials_0[_S124]))  * tg_1 + float3((nt_0.y * (&kernelContext_14)->materials_0[_S124]))  * n_2 + float3(nt_0.z)  * ns_0);
                    if(outside_0)
                    {

#line 528
                        n_3 = ns_2;

#line 528
                    }
                    else
                    {

#line 528
                        n_3 = - ns_2;

#line 528
                    }

#line 528
                    n_2 = n_3;

#line 520
                }
                else
                {

#line 520
                    n_2 = _S109;

#line 520
                }

#line 513
            }
            else
            {

#line 513
                n_2 = _S109;

#line 513
            }

#line 497
        }
        else
        {

#line 497
            n_2 = _S109;

#line 497
            texEmission_0 = _S75;

#line 497
            texRM_0 = _S110;

#line 497
            albedo_2 = albedo_1;

#line 497
        }

#line 534
        float woN_0 = dot(n_2, wo_1);
        if(woN_0 < 0.05000000074505806f)
        {

#line 535
            n_3 = normalize(n_2 + wo_1 * float3((0.05000000074505806f - woN_0)) );

#line 535
        }
        else
        {

#line 535
            n_3 = n_2;

#line 535
        }


        float3 le_1 = float3((&kernelContext_14)->materials_0[mi_0 + 3U], (&kernelContext_14)->materials_0[mi_0 + 4U], (&kernelContext_14)->materials_0[mi_0 + 5U]) * texEmission_0;
        if(any(le_1 > (float3(0.0f) )))
        {

            uint eb_0 = (&kernelContext_14)->instances_0[inst_0 + 3U];
            if(misPrev_0)
            {

#line 543
                chooseEnv_0 = eb_0 != 0U;

#line 543
            }
            else
            {

#line 543
                chooseEnv_0 = false;

#line 543
            }

#line 543
            if(chooseEnv_0)
            {
                uint _S125 = eb_0 - 1U;

#line 545
                uint _S126 = ((&q_1)->get_committed_primitive_id());

#line 545
                uint e_0 = (_S125 + _S126) * 16U;

                float pl_1 = (1.0f - _S78) * (&kernelContext_14)->emitters_0[e_0 + 13U] * pHitT_0 * pHitT_0 / ((&kernelContext_14)->emitters_0[e_0 + 12U] * max(abs(dot(nOut_0, dir_0)), 9.9999997473787516e-05f));
                float _S127 = qPrev_0 * qPrev_0;

#line 548
                wB_0 = _S127 / (_S127 + pl_1 * pl_1);

#line 543
            }
            else
            {

#line 543
                wB_0 = 1.0f;

#line 543
            }

#line 550
            Parts_add_0(&parts_0, depth_3, cls_3, thr_0 * le_1 * float3(wB_0) );

#line 539
        }

#line 552
        float metallic_1 = (&kernelContext_14)->materials_0[mi_0 + 6U] * texRM_0.y;
        float rough_0 = (&kernelContext_14)->materials_0[mi_0 + 7U] * texRM_0.x;
        float transmission_2 = (&kernelContext_14)->materials_0[mi_0 + 8U];
        float ior_1 = (&kernelContext_14)->materials_0[mi_0 + 9U];
        float _S128 = max(rough_0 * rough_0, 0.0010000000474974513f);
        if(outside_0)
        {

#line 557
            wB_0 = ior_1;

#line 557
        }
        else
        {

#line 557
            wB_0 = 1.0f / ior_1;

#line 557
        }

        thread float3 T_0;

#line 559
        thread float3 B_0;
        basis_0(n_3, &T_0, &B_0);
        float _S129 = max(dot(wo_1, n_3), 9.9999997473787516e-05f);

#line 561
        float3 woL_3 = float3(dot(wo_1, T_0), dot(wo_1, B_0), _S129);
        float fSel_1 = fresnelDielectric_0(_S129, ior_1);
        thread Surface_0 surf_0;
        (&surf_0)->albedo_0 = albedo_2;
        (&surf_0)->metallic_0 = metallic_1;
        (&surf_0)->alpha_2 = _S128;
        (&surf_0)->transmission_1 = transmission_2;
        (&surf_0)->ior_0 = ior_1;
        (&surf_0)->eta_1 = wB_0;
        (&surf_0)->fSel_0 = fSel_1;

#line 570
        k_1 = 0U;

#line 570
        float visTotal_2 = visTotal_1;

#line 570
        float visLit_2 = visLit_1;



        for(;;)
        {

#line 574
            if(k_1 < _S76)
            {
            }
            else
            {

#line 574
                break;
            }
            uint o_4 = k_1 * 16U;
            float3 col_0 = float3((as_type<float>(((&kernelContext_14)->lights_0[o_4 + 1U]))), (as_type<float>(((&kernelContext_14)->lights_0[o_4 + 2U]))), (as_type<float>(((&kernelContext_14)->lights_0[o_4 + 3U])))) * float3((as_type<float>(((&kernelContext_14)->lights_0[o_4 + 4U])))) ;
            float3 vec_0 = float3((as_type<float>(((&kernelContext_14)->lights_0[o_4 + 5U]))), (as_type<float>(((&kernelContext_14)->lights_0[o_4 + 6U]))), (as_type<float>(((&kernelContext_14)->lights_0[o_4 + 7U]))));



            if((&kernelContext_14)->lights_0[o_4] == 1U)
            {

#line 582
                wi_0 = - normalize(vec_0);

#line 582
                dist_0 = 1.00000001504746622e+30f;

#line 582
                li_0 = col_0;

#line 582
            }
            else
            {

#line 590
                float3 toL_0 = vec_0 - p_1;
                float d2_0 = dot(toL_0, toL_0);
                float dist_1 = sqrt(d2_0);
                float3 wi_1 = toL_0 / float3(dist_1) ;
                float3 li_1 = col_0 / float3(d2_0) ;
                if((&kernelContext_14)->lights_0[o_4] == 2U)
                {

                    float att_0 = saturate(dot(float3((as_type<float>(((&kernelContext_14)->lights_0[o_4 + 8U]))), (as_type<float>(((&kernelContext_14)->lights_0[o_4 + 9U]))), (as_type<float>(((&kernelContext_14)->lights_0[o_4 + 10U])))), - wi_1) * (as_type<float>(((&kernelContext_14)->lights_0[o_4 + 11U]))) + (as_type<float>(((&kernelContext_14)->lights_0[o_4 + 12U]))));

#line 598
                    wi_0 = li_1 * float3((att_0 * att_0)) ;

#line 595
                }
                else
                {

#line 595
                    wi_0 = li_1;

#line 595
                }

#line 581
                float3 _S130 = wi_0;

#line 581
                wi_0 = wi_1;

#line 581
                dist_0 = dist_1;

#line 581
                li_0 = _S130;
            }

#line 602
            float c_5 = dot(n_3, wi_0);
            if(c_5 > 0.0f)
            {

#line 603
                bool _S131 = occluded_0(p_1, wi_0, dist_0 - 0.0010000000474974513f, &kernelContext_14);


                if(lightingOn_0)
                {

#line 606
                    track_0 = depth_3 == 0U;

#line 606
                }
                else
                {

#line 606
                    track_0 = false;

#line 606
                }
                bool _S132 = !_S131;

#line 607
                if(_S132)
                {

#line 607
                    chooseEnv_0 = true;

#line 607
                }
                else
                {

#line 607
                    chooseEnv_0 = track_0;

#line 607
                }

#line 607
                if(chooseEnv_0)
                {
                    float3 _S133 = float3(dot(wi_0, T_0), dot(wi_0, B_0), c_5);

#line 609
                    thread Surface_0 _S134 = surf_0;

#line 609
                    Lobes_0 _S135 = evalLobes_0(&_S134, woL_3, _S133);
                    float3 cd_1 = thr_0 * _S135.diffuse_0 * li_0;
                    float3 cs_1 = thr_0 * _S135.specular_1 * li_0;
                    if(_S132)
                    {

#line 613
                        Parts_addLight_0(&parts_0, depth_3, cls_3, thr_0 * (_S135.diffuse_0 + _S135.specular_1) * li_0, cd_1, cs_1);

#line 612
                    }

                    if(track_0)
                    {
                        float vv_0 = lum_0(cd_1 + cs_1);
                        float visTotal_3 = visTotal_2 + vv_0;
                        if(_S131)
                        {

#line 618
                            visLit_0 = 0.0f;

#line 618
                        }
                        else
                        {

#line 618
                            visLit_0 = vv_0;

#line 618
                        }

#line 618
                        float visLit_3 = visLit_2 + visLit_0;

#line 618
                        visTotal_0 = visTotal_3;

#line 618
                        visLit_0 = visLit_3;

#line 614
                    }
                    else
                    {

#line 614
                        visTotal_0 = visTotal_2;

#line 614
                        visLit_0 = visLit_2;

#line 614
                    }

#line 607
                }
                else
                {

#line 607
                    visTotal_0 = visTotal_2;

#line 607
                    visLit_0 = visLit_2;

#line 607
                }

#line 603
            }
            else
            {

#line 603
                visTotal_0 = visTotal_2;

#line 603
                visLit_0 = visLit_2;

#line 603
            }

#line 574
            k_1 = k_1 + 1U;

#line 574
            visTotal_2 = visTotal_0;

#line 574
            visLit_2 = visLit_0;

#line 574
        }

#line 625
        float chooseLight_0 = Rng_next_0(&rng_0);
        if(hasEnv_0)
        {

#line 626
            chooseEnv_0 = chooseLight_0 < _S78;

#line 626
        }
        else
        {

#line 626
            chooseEnv_0 = false;

#line 626
        }

#line 626
        bool _S136;
        if(emitterCount_0 > 0U)
        {

#line 627
            _S136 = !chooseEnv_0;

#line 627
        }
        else
        {

#line 627
            _S136 = false;

#line 627
        }

#line 627
        bool ok_0;

#line 627
        bool _S137;

#line 627
        uint lobeCls_0;

#line 627
        if(_S136)
        {
            float _S138 = Rng_next_0(&rng_0);
            float ua_0 = Rng_next_0(&rng_0);
            float ub_0 = Rng_next_0(&rng_0);

            uint _S139 = emitterCount_0 - 1U;

#line 633
            lobeCls_0 = 0U;

#line 633
            uint hi_1 = _S139;
            for(;;)
            {

#line 634
                if(lobeCls_0 < hi_1)
                {
                }
                else
                {

#line 634
                    break;
                }
                uint mid_2 = (lobeCls_0 + hi_1) / 2U;
                if((&kernelContext_14)->emitCdf_0[mid_2] >= _S138)
                {

#line 637
                    hi_1 = mid_2;

#line 637
                }
                else
                {

#line 637
                    lobeCls_0 = mid_2 + 1U;

#line 637
                }

#line 634
            }

#line 642
            uint e_1 = lobeCls_0 * 16U;
            float3 a_3 = float3((&kernelContext_14)->emitters_0[e_1], (&kernelContext_14)->emitters_0[e_1 + 1U], (&kernelContext_14)->emitters_0[e_1 + 2U]);
            float3 b_2 = float3((&kernelContext_14)->emitters_0[e_1 + 3U], (&kernelContext_14)->emitters_0[e_1 + 4U], (&kernelContext_14)->emitters_0[e_1 + 5U]);
            float3 c_6 = float3((&kernelContext_14)->emitters_0[e_1 + 6U], (&kernelContext_14)->emitters_0[e_1 + 7U], (&kernelContext_14)->emitters_0[e_1 + 8U]);
            float su_0 = sqrt(ua_0);

            float3 toL_1 = a_3 * float3((1.0f - su_0))  + b_2 * float3((su_0 * (1.0f - ub_0)))  + c_6 * float3((su_0 * ub_0))  - p_1;
            float d2_1 = dot(toL_1, toL_1);
            float dist_2 = sqrt(d2_1);
            float3 wi_2 = toL_1 / float3(dist_2) ;
            float cosl_0 = abs(dot(normalize(cross(b_2 - a_3, c_6 - a_3)), wi_2));
            float cosi_1 = dot(n_3, wi_2);
            if(cosi_1 > 0.0f)
            {

#line 654
                ok_0 = cosl_0 > 9.9999997473787516e-06f;

#line 654
            }
            else
            {

#line 654
                ok_0 = false;

#line 654
            }

#line 654
            if(ok_0)
            {

#line 654
                bool _S140 = occluded_0(p_1, wi_2, dist_2 * 0.99900001287460327f, &kernelContext_14);


                if(lightingOn_0)
                {

#line 657
                    track_0 = depth_3 == 0U;

#line 657
                }
                else
                {

#line 657
                    track_0 = false;

#line 657
                }
                bool _S141 = !_S140;

#line 658
                if(_S141)
                {

#line 658
                    _S137 = true;

#line 658
                }
                else
                {

#line 658
                    _S137 = track_0;

#line 658
                }

#line 658
                if(_S137)
                {
                    float pl_2 = (1.0f - _S78) * (&kernelContext_14)->emitters_0[e_1 + 13U] * d2_1 / ((&kernelContext_14)->emitters_0[e_1 + 12U] * cosl_0);
                    float3 wiL_3 = float3(dot(wi_2, T_0), dot(wi_2, B_0), cosi_1);

#line 661
                    thread Surface_0 _S142 = surf_0;

#line 661
                    float _S143 = reflectivePdf_0(&_S142, woL_3, wiL_3);

                    float _S144 = pl_2 * pl_2;

#line 663
                    float wl_0 = _S144 / (_S144 + _S143 * _S143);
                    float3 le_2 = float3((&kernelContext_14)->emitters_0[e_1 + 9U], (&kernelContext_14)->emitters_0[e_1 + 10U], (&kernelContext_14)->emitters_0[e_1 + 11U]);

#line 664
                    thread Surface_0 _S145 = surf_0;

#line 664
                    Lobes_0 _S146 = evalLobes_0(&_S145, woL_3, wiL_3);

#line 664
                    float3 _S147 = float3(pl_2) ;

#line 664
                    float3 _S148 = float3(wl_0) ;

                    float3 cd_2 = thr_0 * _S146.diffuse_0 * le_2 / _S147 * _S148;
                    float3 cs_2 = thr_0 * _S146.specular_1 * le_2 / _S147 * _S148;
                    if(_S141)
                    {

#line 668
                        thread Surface_0 _S149 = surf_0;

#line 668
                        float3 _S150 = evalReflective_0(&_S149, woL_3, wiL_3);
                        Parts_addLight_0(&parts_0, depth_3, cls_3, thr_0 * _S150 * le_2 / _S147 * _S148, cd_2, cs_2);

#line 668
                    }

                    if(track_0)
                    {
                        float vv_1 = lum_0(cd_2 + cs_2);
                        float visTotal_4 = visTotal_2 + vv_1;
                        if(_S140)
                        {

#line 674
                            dist_0 = 0.0f;

#line 674
                        }
                        else
                        {

#line 674
                            dist_0 = vv_1;

#line 674
                        }

#line 674
                        float visLit_4 = visLit_2 + dist_0;

#line 674
                        dist_0 = visTotal_4;

#line 674
                        visLit_0 = visLit_4;

#line 670
                    }
                    else
                    {

#line 670
                        dist_0 = visTotal_2;

#line 670
                        visLit_0 = visLit_2;

#line 670
                    }

#line 658
                }
                else
                {

#line 658
                    dist_0 = visTotal_2;

#line 658
                    visLit_0 = visLit_2;

#line 658
                }

#line 654
            }
            else
            {

#line 654
                dist_0 = visTotal_2;

#line 654
                visLit_0 = visLit_2;

#line 654
            }

#line 627
        }
        else
        {

#line 627
            dist_0 = visTotal_2;

#line 627
            visLit_0 = visLit_2;

#line 627
        }

#line 627
        float visLit_5;

#line 680
        if(chooseEnv_0)
        {
            float e1_0 = Rng_next_0(&rng_0);
            float e2_0 = Rng_next_0(&rng_0);
            float e3_1 = Rng_next_0(&rng_0);
            float e4_0 = Rng_next_0(&rng_0);
            thread float pdfE_0;
            thread float3 leE_0;

#line 687
            float3 _S151 = envSample_0(e1_0, e2_0, e3_1, e4_0, &pdfE_0, &leE_0, &kernelContext_14);

            float cosi_2 = dot(n_3, _S151);
            if(pdfE_0 > 0.0f)
            {

#line 690
                ok_0 = cosi_2 > 0.0f;

#line 690
            }
            else
            {

#line 690
                ok_0 = false;

#line 690
            }

#line 690
            if(ok_0)
            {

#line 690
                bool _S152 = occluded_0(p_1, _S151, 1.00000001504746622e+30f, &kernelContext_14);


                if(lightingOn_0)
                {

#line 693
                    track_0 = depth_3 == 0U;

#line 693
                }
                else
                {

#line 693
                    track_0 = false;

#line 693
                }
                bool _S153 = !_S152;

#line 694
                if(_S153)
                {

#line 694
                    _S137 = true;

#line 694
                }
                else
                {

#line 694
                    _S137 = track_0;

#line 694
                }

#line 694
                if(_S137)
                {
                    float pl_3 = _S78 * pdfE_0;
                    float3 wiL_4 = float3(dot(_S151, T_0), dot(_S151, B_0), cosi_2);

#line 697
                    thread Surface_0 _S154 = surf_0;

#line 697
                    float _S155 = reflectivePdf_0(&_S154, woL_3, wiL_4);

                    float _S156 = pl_3 * pl_3;

#line 699
                    float wl_1 = _S156 / (_S156 + _S155 * _S155);

#line 699
                    thread Surface_0 _S157 = surf_0;

#line 699
                    Lobes_0 _S158 = evalLobes_0(&_S157, woL_3, wiL_4);

#line 699
                    float3 _S159 = float3(pl_3) ;

#line 699
                    float3 _S160 = float3(wl_1) ;

                    float3 cd_3 = thr_0 * _S158.diffuse_0 * leE_0 / _S159 * _S160;
                    float3 cs_3 = thr_0 * _S158.specular_1 * leE_0 / _S159 * _S160;
                    if(_S153)
                    {

#line 703
                        thread Surface_0 _S161 = surf_0;

#line 703
                        float3 _S162 = evalReflective_0(&_S161, woL_3, wiL_4);
                        Parts_addLight_0(&parts_0, depth_3, cls_3, thr_0 * _S162 * leE_0 / _S159 * _S160, cd_3, cs_3);

#line 703
                    }

                    if(track_0)
                    {
                        float vv_2 = lum_0(cd_3 + cs_3);
                        float visTotal_5 = dist_0 + vv_2;
                        if(_S152)
                        {

#line 709
                            visTotal_0 = 0.0f;

#line 709
                        }
                        else
                        {

#line 709
                            visTotal_0 = vv_2;

#line 709
                        }

#line 709
                        float visLit_6 = visLit_0 + visTotal_0;

#line 709
                        visTotal_0 = visTotal_5;

#line 709
                        visLit_5 = visLit_6;

#line 705
                    }
                    else
                    {

#line 705
                        visTotal_0 = dist_0;

#line 705
                        visLit_5 = visLit_0;

#line 705
                    }

#line 694
                }
                else
                {

#line 694
                    visTotal_0 = dist_0;

#line 694
                    visLit_5 = visLit_0;

#line 694
                }

#line 690
            }
            else
            {

#line 690
                visTotal_0 = dist_0;

#line 690
                visLit_5 = visLit_0;

#line 690
            }

#line 680
        }
        else
        {

#line 680
            visTotal_0 = dist_0;

#line 680
            visLit_5 = visLit_0;

#line 680
        }

#line 717
        float lobe_0 = Rng_next_0(&rng_0);
        float u1_3 = Rng_next_0(&rng_0);
        float u2_3 = Rng_next_0(&rng_0);
        float u3_1 = Rng_next_0(&rng_0);

#line 726
        if(lobe_0 < metallic_1)
        {
            float3 h_6 = sampleVndf_0(woL_3, _S128, u1_3, u2_3);
            float woh_0 = dot(woL_3, h_6);
            float3 wiL_5 = float3((2.0f * woh_0))  * h_6 - woL_3;
            float _S163 = wiL_5.z;
            float3 _S164 = schlick_0(albedo_2, woh_0) * float3(G1_0(max(_S163, 0.0f), _S128)) ;

#line 732
            ok_0 = _S163 > 0.0f;

#line 732
            lobeCls_0 = 1U;

#line 732
            track_0 = false;

#line 732
            wi_0 = wiL_5;

#line 732
            li_0 = _S164;

#line 726
        }
        else
        {

#line 734
            if(lobe_0 < (metallic_1 + (1.0f - metallic_1) * transmission_2))
            {
                float3 h_7 = sampleVndf_0(woL_3, _S128, u1_3, u2_3);
                float woh_1 = dot(woL_3, h_7);
                if(u3_1 < (fresnelDielectric_0(woh_1, wB_0)))
                {
                    float3 wiL_6 = float3((2.0f * woh_1))  * h_7 - woL_3;
                    float _S165 = wiL_6.z;
                    float3 _S166 = float3(G1_0(max(_S165, 0.0f), _S128)) ;

#line 742
                    ok_0 = _S165 > 0.0f;

#line 742
                    lobeCls_0 = 1U;

#line 742
                    track_0 = false;

#line 742
                    wi_0 = wiL_6;

#line 742
                    li_0 = _S166;

#line 738
                }
                else
                {

#line 746
                    float r_4 = 1.0f / wB_0;
                    float k_2 = 1.0f - r_4 * r_4 * (1.0f - woh_1 * woh_1);

#line 747
                    float3 _S167 = float3(r_4) ;
                    float3 wiL_7 = - woL_3 * _S167 + float3((r_4 * woh_1 - sqrt(max(k_2, 0.0f))))  * h_7;
                    float _S168 = wiL_7.z;

#line 749
                    if(_S168 < 0.0f)
                    {

#line 749
                        ok_0 = k_2 > 0.0f;

#line 749
                    }
                    else
                    {

#line 749
                        ok_0 = false;

#line 749
                    }



                    float3 _S169 = albedo_2 * float3(G1_0(max(- _S168, 0.0f), _S128))  * _S167 * _S167;

#line 753
                    lobeCls_0 = 2U;

#line 753
                    track_0 = true;

#line 753
                    wi_0 = wiL_7;

#line 753
                    li_0 = _S169;

#line 738
                }

#line 734
            }
            else
            {

#line 756
                if(u3_1 < fSel_1)
                {
                    float3 h_8 = sampleVndf_0(woL_3, _S128, u1_3, u2_3);
                    float woh_2 = dot(woL_3, h_8);
                    float3 wiL_8 = float3((2.0f * woh_2))  * h_8 - woL_3;
                    float _S170 = wiL_8.z;
                    float3 _S171 = float3((fresnelDielectric_0(woh_2, ior_1) / fSel_1 * G1_0(max(_S170, 0.0f), _S128))) ;

#line 762
                    ok_0 = _S170 > 0.0f;

#line 762
                    lobeCls_0 = 1U;

#line 762
                    wi_0 = wiL_8;

#line 762
                    li_0 = _S171;

#line 756
                }
                else
                {

#line 766
                    float3 _S172 = cosineLocal_0(u1_3, u2_3);

#line 766
                    ok_0 = true;

#line 766
                    lobeCls_0 = 0U;

#line 766
                    wi_0 = _S172;

#line 766
                    li_0 = albedo_2;

#line 756
                }

#line 756
                track_0 = false;

#line 734
            }

#line 726
        }

#line 770
        if(!ok_0)
        {

#line 770
            visLit_0 = visLit_5;
            break;
        }

#line 772
        if(depth_3 == 0U)
        {

#line 772
            cls_3 = lobeCls_0;

#line 772
        }

        bool _S173 = !track_0;
        if(track_0)
        {

#line 775
            qPrev_0 = 0.0f;

#line 775
        }
        else
        {

#line 775
            thread Surface_0 _S174 = surf_0;

#line 775
            float _S175 = reflectivePdf_0(&_S174, woL_3, wi_0);

#line 775
            qPrev_0 = _S175;

#line 775
        }

        float3 _S176 = normalize(float3(wi_0.x)  * T_0 + float3(wi_0.y)  * B_0 + float3(wi_0.z)  * n_3);

#line 777
        dir_0 = _S176;

        float side_0 = dot(_S176, radiance_0);
        if(track_0)
        {

#line 780
            _S137 = side_0 >= 0.0f;

#line 780
        }
        else
        {

#line 780
            _S137 = side_0 <= 0.0f;

#line 780
        }

#line 780
        if(_S137)
        {

#line 780
            visLit_0 = visLit_5;
            break;
        }

#line 781
        float _S177;
        if(side_0 > 0.0f)
        {

#line 782
            _S177 = 9.9999997473787516e-05f;

#line 782
        }
        else
        {

#line 782
            _S177 = -9.9999997473787516e-05f;

#line 782
        }

#line 782
        org_0 = hit_0 + radiance_0 * float3(_S177) ;
        float3 thr_1 = thr_0 * li_0;

        if(depth_3 >= 2U)
        {
            float pr_0 = clamp(max(thr_1.x, max(thr_1.y, thr_1.z)), 0.05000000074505806f, 0.94999998807907104f);
            float _S178 = Rng_next_0(&rng_0);

#line 788
            if(_S178 > pr_0)
            {

#line 788
                visLit_0 = visLit_5;
                break;
            }

#line 789
            thr_0 = thr_1 / float3(pr_0) ;

#line 785
        }
        else
        {

#line 785
            thr_0 = thr_1;

#line 785
        }

#line 419
        uint _S179 = depth_3 + 1U;

#line 419
        misPrev_0 = _S173;

#line 419
        depth_3 = _S179;

#line 419
        pathLen_0 = pathLen_1;

#line 419
        visTotal_1 = visTotal_0;

#line 419
        visLit_1 = visLit_5;

#line 419
    }

#line 794
    float3 radiance_1 = (&parts_0)->total_0;
    if(any(isnan((&parts_0)->total_0)))
    {

#line 795
        misPrev_0 = true;

#line 795
    }
    else
    {

#line 795
        misPrev_0 = any(isinf(radiance_1));

#line 795
    }

#line 795
    if(misPrev_0)
    {

#line 795
        (&parts_0)->total_0 = _S74;

#line 795
        (&parts_0)->directDiffuse_0 = _S74;

#line 795
        (&parts_0)->indirectDiffuse_0 = _S74;

#line 795
        (&parts_0)->specular_0 = _S74;

#line 795
        (&parts_0)->transmission_0 = _S74;

#line 795
        (&parts_0)->emission_0 = _S74;

#line 795
        radiance_0 = _S74;

#line 795
        visLit_0 = 0.0f;

#line 795
        visTotal_0 = 0.0f;

#line 795
    }
    else
    {

#line 795
        radiance_0 = radiance_1;

#line 795
    }

#line 803
    uint o_5 = 3U * pixel_0;
    float device* _S180 = (&kernelContext_14)->accum_0+o_5;

#line 804
    *_S180 = *_S180 + radiance_0.x;
    float device* _S181 = (&kernelContext_14)->accum_0+(o_5 + 1U);

#line 805
    *_S181 = *_S181 + radiance_0.y;
    float device* _S182 = (&kernelContext_14)->accum_0+(o_5 + 2U);

#line 806
    *_S182 = *_S182 + radiance_0.z;

    if(lightingOn_0)
    {
        uint lo_2 = 17U * pixel_0;
        array<float3, int(5)> _S183 = { { (&parts_0)->directDiffuse_0, (&parts_0)->indirectDiffuse_0, (&parts_0)->specular_0, (&parts_0)->transmission_0, (&parts_0)->emission_0 } };

#line 811
        k_1 = 0U;
        for(;;)
        {

#line 812
            if(k_1 < 5U)
            {
            }
            else
            {

#line 812
                break;
            }
            uint _S184 = lo_2 + 3U * k_1;

#line 814
            float device* _S185 = (&kernelContext_14)->lighting_0+_S184;

#line 814
            *_S185 = *_S185 + _S183[k_1].x;
            float device* _S186 = (&kernelContext_14)->lighting_0+(_S184 + 1U);

#line 815
            *_S186 = *_S186 + _S183[k_1].y;
            float device* _S187 = (&kernelContext_14)->lighting_0+(_S184 + 2U);

#line 816
            *_S187 = *_S187 + _S183[k_1].z;

#line 812
            k_1 = k_1 + 1U;

#line 812
        }

#line 818
        float device* _S188 = (&kernelContext_14)->lighting_0+(lo_2 + 15U);

#line 818
        *_S188 = *_S188 + visLit_0;
        float device* _S189 = (&kernelContext_14)->lighting_0+(lo_2 + 16U);

#line 819
        *_S189 = *_S189 + visTotal_0;

#line 808
    }

#line 821
    return;
}

