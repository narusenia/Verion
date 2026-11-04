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
            

#line 19 "shaders/pathtrace.slang"
uint pcg_0(uint v_0)
{
    uint s_0 = v_0 * 747796405U + 2891336453U;
    uint w_0 = ((s_0 >> ((s_0 >> 28U) + 4U)) ^ s_0) * 277803737U;
    return (w_0 >> 22U) ^ w_0;
}


#line 420
struct KernelContext_0
{
    uint device* params_0;
    metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_0;
    uint device* instances_0;
    uint device* indices_0;
    float device* positions_0;
    float device* materials_0;
    float device* emitters_0;
    uint device* lights_0;
    float device* emitCdf_0;
    float device* accum_0;
};


#line 36
float pf_0(uint i_0, KernelContext_0 thread* kernelContext_0)
{

#line 36
    return (as_type<float>((kernelContext_0->params_0[i_0])));
}


#line 26
struct Rng_0
{
    uint state_0;
};


#line 29
float Rng_next_0(Rng_0 thread* this_0)
{
    uint _S1 = pcg_0(this_0->state_0);

#line 31
    this_0->state_0 = _S1;
    return float(_S1 >> 8U) * 5.9604644775390625e-08f;
}




float3 vertexPos_0(uint v_1, KernelContext_0 thread* kernelContext_1)
{

#line 38
    uint _S2 = 3U * v_1;

#line 38
    return float3(kernelContext_1->positions_0[_S2], kernelContext_1->positions_0[_S2 + 1U], kernelContext_1->positions_0[_S2 + 2U]);
}


#line 40
float3 transformPoint_0(uint base_0, float3 p_0, KernelContext_0 thread* kernelContext_2)
{
    thread float3 r_0;

#line 42
    uint row_0 = 0U;
    for(;;)
    {

#line 43
        if(row_0 < 3U)
        {
        }
        else
        {

#line 43
            break;
        }
        uint o_0 = base_0 + 4U * row_0;
        r_0[row_0] = (as_type<float>((kernelContext_2->instances_0[o_0]))) * p_0.x + (as_type<float>((kernelContext_2->instances_0[o_0 + 1U]))) * p_0.y + (as_type<float>((kernelContext_2->instances_0[o_0 + 2U]))) * p_0.z + (as_type<float>((kernelContext_2->instances_0[o_0 + 3U])));

#line 43
        row_0 = row_0 + 1U;

#line 43
    }

#line 48
    return r_0;
}


#line 91
void basis_0(float3 n_0, float3 thread* t_0, float3 thread* b_0)
{

#line 91
    float3 a_0;

    if((abs(n_0.x)) > 0.89999997615814209f)
    {

#line 93
        a_0 = float3(0.0f, 1.0f, 0.0f);

#line 93
    }
    else
    {

#line 93
        a_0 = float3(1.0f, 0.0f, 0.0f);

#line 93
    }
    float3 _S3 = normalize(cross(n_0, a_0));

#line 94
    *b_0 = _S3;
    *t_0 = cross(_S3, n_0);
    return;
}


#line 80
float fresnelDielectric_0(float cosi_0, float eta_0)
{
    float s2_0 = (1.0f - cosi_0 * cosi_0) / (eta_0 * eta_0);
    if(s2_0 >= 1.0f)
    {

#line 84
        return 1.0f;
    }

#line 85
    float cost_0 = sqrt(1.0f - s2_0);
    float _S4 = eta_0 * cost_0;

#line 86
    float rs_0 = (cosi_0 - _S4) / (cosi_0 + _S4);
    float _S5 = eta_0 * cosi_0;

#line 87
    float rp_0 = (_S5 - cost_0) / (_S5 + cost_0);
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


#line 153 "shaders/pathtrace.slang"
bool occluded_0(float3 o_1, float3 d_0, float tmax_0, KernelContext_0 thread* kernelContext_3)
{
    thread RayDesc_0 ray_0;
    (&ray_0)->Origin_0 = o_1;
    (&ray_0)->Direction_0 = d_0;
    (&ray_0)->TMin_0 = 0.0f;
    (&ray_0)->TMax_0 = tmax_0;
    thread raytracing::intersection_query<raytracing::triangle_data, raytracing::instancing> q_0;
    (&q_0)->reset({ (ray_0.Origin_0), (ray_0.Direction_0), (ray_0.TMin_0), (ray_0.TMax_0) }, (kernelContext_3->scene_0), (255U), _slang_ray_flags_to_intersection_params((5U)));
    for(;;)
    {

#line 162
        bool _S6 = ((&q_0)->next());

#line 162
        if(_S6)
        {
        }
        else
        {

#line 162
            break;
        }

#line 162
    }
    uint _S7 = (_slang_committed_intersection_type_to_uint((&q_0)->get_committed_intersection_type()));

#line 163
    return _S7 == 1U;
}


#line 65
float D_0(float hz_0, float alpha_0)
{
    float a2_0 = alpha_0 * alpha_0;
    float d_1 = hz_0 * hz_0 * (a2_0 - 1.0f) + 1.0f;
    return a2_0 / (3.1415927410125732f * d_1 * d_1);
}


#line 58
float G1_0(float cosT_0, float alpha_1)
{
    float c2_0 = cosT_0 * cosT_0;

    return 2.0f / (1.0f + sqrt(1.0f + alpha_1 * alpha_1 * ((1.0f - c2_0) / max(c2_0, 9.99999993922529029e-09f))));
}


#line 72
float3 schlick_0(float3 f0_0, float c_0)
{
    float m_0 = 1.0f - saturate(c_0);
    float m2_0 = m_0 * m_0;
    return f0_0 + (float3(1.0f)  - f0_0) * float3((m2_0 * m2_0 * m_0)) ;
}


#line 116
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
    float _S8 = max(dot(woL_0, hh_0), 0.0f);

    float _S9 = woL_0.z;

#line 133
    float _S10 = wiL_0.z;

#line 133
    float core_0 = D_0(hh_0.z, s_1->alpha_2) * G1_0(_S9, s_1->alpha_2) * G1_0(_S10, s_1->alpha_2) / (4.0f * _S9);


    float _S11 = 1.0f - s_1->metallic_0;

#line 136
    float _S12 = 1.0f - s_1->transmission_0;

#line 135
    return float3(s_1->metallic_0)  * schlick_0(s_1->albedo_0, _S8) * float3(core_0)  + float3((_S11 * (s_1->transmission_0 * fresnelDielectric_0(_S8, s_1->eta_1) + _S12 * fresnelDielectric_0(_S8, s_1->ior_0)) * core_0))  + float3((_S11 * _S12 * (1.0f - s_1->fSel_0)))  * s_1->albedo_0 * float3((_S10 / 3.1415927410125732f)) ;
}


#line 142
float reflectivePdf_0(const Surface_0 thread* s_2, float3 woL_1, float3 wiL_1)
{
    float3 hh_1 = normalize(woL_1 + wiL_1);

    float _S13 = woL_1.z;

    float _S14 = 1.0f - s_2->metallic_0;

#line 148
    float _S15 = 1.0f - s_2->transmission_0;

    return (s_2->metallic_0 + _S14 * (s_2->transmission_0 * fresnelDielectric_0(max(dot(woL_1, hh_1), 0.0f), s_2->eta_1) + _S15 * s_2->fSel_0)) * (G1_0(_S13, s_2->alpha_2) * D_0(hh_1.z, s_2->alpha_2) / (4.0f * _S13)) + _S14 * _S15 * (1.0f - s_2->fSel_0) * wiL_1.z / 3.1415927410125732f;
}


#line 99
float3 sampleVndf_0(float3 wo_0, float alpha_3, float u1_0, float u2_0)
{
    float3 vh_0 = normalize(float3(alpha_3 * wo_0.x, alpha_3 * wo_0.y, wo_0.z));
    float _S16 = vh_0.x;

#line 102
    float _S17 = vh_0.y;

#line 102
    float lensq_0 = _S16 * _S16 + _S17 * _S17;

#line 102
    float3 t1_0;
    if(lensq_0 > 0.0f)
    {

#line 103
        t1_0 = float3(- _S17, _S16, 0.0f) * float3(rsqrt(lensq_0)) ;

#line 103
    }
    else
    {

#line 103
        t1_0 = float3(1.0f, 0.0f, 0.0f);

#line 103
    }

    float r_1 = sqrt(u1_0);
    float phi_0 = 6.2831854820251465f * u2_0;
    float a_1 = r_1 * cos(phi_0);

    float s_3 = 0.5f * (1.0f + vh_0.z);
    float _S18 = 1.0f - a_1 * a_1;

#line 110
    float b_1 = (1.0f - s_3) * sqrt(_S18) + s_3 * (r_1 * sin(phi_0));
    float3 nh_0 = float3(a_1)  * t1_0 + float3(b_1)  * cross(vh_0, t1_0) + float3(sqrt(max(0.0f, _S18 - b_1 * b_1)))  * vh_0;
    return normalize(float3(alpha_3 * nh_0.x, alpha_3 * nh_0.y, max(0.0f, nh_0.z)));
}


#line 51
float3 cosineLocal_0(float u1_1, float u2_1)
{
    float r_2 = sqrt(u1_1);
    float phi_1 = 6.2831854820251465f * u2_1;
    return float3(r_2 * cos(phi_1), r_2 * sin(phi_1), sqrt(max(0.0f, 1.0f - u1_1)));
}


#line 168
[[kernel]] void pathtrace(uint3 tid_0 [[thread_position_in_grid]], uint device* params_1 [[buffer(6)]], metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_1 [[buffer(0)]], uint device* instances_1 [[buffer(3)]], uint device* indices_1 [[buffer(2)]], float device* positions_1 [[buffer(1)]], float device* materials_1 [[buffer(4)]], float device* emitters_1 [[buffer(8)]], uint device* lights_1 [[buffer(5)]], float device* emitCdf_1 [[buffer(9)]], float device* accum_1 [[buffer(7)]])
{

#line 168
    float3 radiance_0;

#line 168
    float dist_0;

#line 168
    float3 wi_0;

#line 168
    float3 li_0;

#line 168
    thread KernelContext_0 kernelContext_4;

#line 168
    (&kernelContext_4)->params_0 = params_1;

#line 168
    (&kernelContext_4)->scene_0 = scene_1;

#line 168
    (&kernelContext_4)->instances_0 = instances_1;

#line 168
    (&kernelContext_4)->indices_0 = indices_1;

#line 168
    (&kernelContext_4)->positions_0 = positions_1;

#line 168
    (&kernelContext_4)->materials_0 = materials_1;

#line 168
    (&kernelContext_4)->emitters_0 = emitters_1;

#line 168
    (&kernelContext_4)->lights_0 = lights_1;

#line 168
    (&kernelContext_4)->emitCdf_0 = emitCdf_1;

#line 168
    (&kernelContext_4)->accum_0 = accum_1;

    uint w_1 = params_1[int(0)];
    uint h_0 = params_1[int(1)];
    uint _S19 = tid_0.x;

#line 172
    bool misPrev_0;

#line 172
    if(_S19 >= w_1)
    {

#line 172
        misPrev_0 = true;

#line 172
    }
    else
    {

#line 172
        misPrev_0 = (tid_0.y) >= h_0;

#line 172
    }

#line 172
    if(misPrev_0)
    {

#line 173
        return;
    }

#line 174
    uint _S20 = tid_0.y;

#line 174
    uint pixel_0 = _S20 * w_1 + _S19;
    thread Rng_0 rng_0;
    (&rng_0)->state_0 = pcg_0(pixel_0 ^ (pcg_0((&kernelContext_4)->params_0[int(6)] * 2654435769U + 2135587861U)));

#line 176
    float _S21 = pf_0(2U, &kernelContext_4);



    float _S22 = float(w_1);

#line 180
    float _S23 = float(h_0);

#line 180
    float aspect_0 = _S22 / _S23;
    float _S24 = float(_S19);

#line 181
    float _S25 = Rng_next_0(&rng_0);

#line 181
    float u_0 = (2.0f * (_S24 + _S25) / _S22 - 1.0f) * aspect_0 * _S21;
    float _S26 = float(_S20);

#line 182
    float _S27 = Rng_next_0(&rng_0);
    float3 _S28 = float3(u_0, (1.0f - 2.0f * (_S26 + _S27) / _S23) * _S21, -1.0f);

#line 183
    float _S29 = pf_0(4U, &kernelContext_4);

#line 183
    float3 focal_0 = _S28 * float3(_S29) ;

#line 183
    float _S30 = pf_0(3U, &kernelContext_4);
    float _S31 = Rng_next_0(&rng_0);

#line 184
    float lensR_0 = _S30 * sqrt(_S31);
    float _S32 = Rng_next_0(&rng_0);

#line 185
    float lensA_0 = 6.2831854820251465f * _S32;
    float _S33 = lensR_0 * cos(lensA_0);

#line 186
    float _S34 = lensR_0 * sin(lensA_0);
    float3 _S35 = normalize(focal_0 - float3(_S33, _S34, 0.0f));
    thread float3 org_0;

#line 188
    thread float3 dir_0;

#line 188
    uint r_3 = 0U;
    for(;;)
    {

#line 189
        if(r_3 < 3U)
        {
        }
        else
        {

#line 189
            break;
        }
        uint _S36 = 4U * r_3;

#line 191
        uint _S37 = 8U + _S36;

#line 191
        uint _S38 = 9U + _S36;

#line 191
        uint _S39 = 10U + _S36;

#line 191
        org_0[r_3] = (as_type<float>(((&kernelContext_4)->params_0[_S37]))) * _S33 + (as_type<float>(((&kernelContext_4)->params_0[_S38]))) * _S34 + (as_type<float>(((&kernelContext_4)->params_0[_S39]))) * 0.0f + (as_type<float>(((&kernelContext_4)->params_0[11U + _S36])));
        dir_0[r_3] = (as_type<float>(((&kernelContext_4)->params_0[_S37]))) * _S35.x + (as_type<float>(((&kernelContext_4)->params_0[_S38]))) * _S35.y + (as_type<float>(((&kernelContext_4)->params_0[_S39]))) * _S35.z;

#line 189
        r_3 = r_3 + 1U;

#line 189
    }

#line 194
    dir_0 = normalize(dir_0);

#line 194
    float _S40 = pf_0(20U, &kernelContext_4);

#line 194
    float _S41 = pf_0(21U, &kernelContext_4);

#line 194
    float _S42 = pf_0(22U, &kernelContext_4);

    float3 _S43 = float3(_S40, _S41, _S42);
    float3 _S44 = float3(0.0f) ;
    float3 _S45 = float3(1.0f) ;
    uint _S46 = (&kernelContext_4)->params_0[int(5)];
    uint _S47 = (&kernelContext_4)->params_0[int(7)];
    uint _S48 = (&kernelContext_4)->params_0[int(23)];

#line 201
    misPrev_0 = false;

#line 201
    float qPrev_0 = 0.0f;

#line 201
    uint depth_0 = 0U;

#line 201
    float3 thr_0 = _S45;

#line 201
    float3 radiance_1 = _S44;

#line 206
    for(;;)
    {

#line 206
        if(depth_0 < _S47)
        {
        }
        else
        {

#line 206
            radiance_0 = radiance_1;

#line 206
            break;
        }
        thread RayDesc_0 ray_1;
        (&ray_1)->Origin_0 = org_0;
        (&ray_1)->Direction_0 = dir_0;
        (&ray_1)->TMin_0 = 0.0f;
        (&ray_1)->TMax_0 = 1.00000001504746622e+30f;
        thread raytracing::intersection_query<raytracing::triangle_data, raytracing::instancing> q_1;
        (&q_1)->reset({ (ray_1.Origin_0), (ray_1.Direction_0), (ray_1.TMin_0), (ray_1.TMax_0) }, ((&kernelContext_4)->scene_0), (255U), _slang_ray_flags_to_intersection_params((1U)));
        for(;;)
        {

#line 215
            bool _S49 = ((&q_1)->next());

#line 215
            if(_S49)
            {
            }
            else
            {

#line 215
                break;
            }

#line 215
        }

        uint _S50 = (_slang_committed_intersection_type_to_uint((&q_1)->get_committed_intersection_type()));

#line 217
        if(_S50 != 1U)
        {

#line 217
            radiance_0 = radiance_1 + thr_0 * _S43;



            break;
        }

        uint _S51 = ((&q_1)->get_committed_instance_id());

#line 224
        uint inst_0 = _S51 * 16U;
        uint _S52 = (&kernelContext_4)->instances_0[inst_0 + 1U];

#line 225
        uint _S53 = ((&q_1)->get_committed_primitive_id());

#line 225
        uint tri_0 = _S52 + 3U * _S53;
        uint vo_0 = (&kernelContext_4)->instances_0[inst_0];
        uint _S54 = inst_0 + 4U;

#line 227
        float3 _S55 = vertexPos_0((&kernelContext_4)->indices_0[tri_0] + vo_0, &kernelContext_4);

#line 227
        float3 _S56 = transformPoint_0(_S54, _S55, &kernelContext_4);

#line 227
        float3 _S57 = vertexPos_0((&kernelContext_4)->indices_0[tri_0 + 1U] + vo_0, &kernelContext_4);

#line 227
        float3 _S58 = transformPoint_0(_S54, _S57, &kernelContext_4);

#line 227
        float3 _S59 = vertexPos_0((&kernelContext_4)->indices_0[tri_0 + 2U] + vo_0, &kernelContext_4);

#line 227
        float3 _S60 = transformPoint_0(_S54, _S59, &kernelContext_4);



        float3 nOut_0 = normalize(cross(_S58 - _S56, _S60 - _S56));
        float3 wo_1 = - dir_0;
        bool outside_0 = (dot(nOut_0, wo_1)) > 0.0f;

#line 233
        float3 n_1;
        if(outside_0)
        {

#line 234
            n_1 = nOut_0;

#line 234
        }
        else
        {

#line 234
            n_1 = - nOut_0;

#line 234
        }
        float pHitT_0 = ((&q_1)->get_committed_distance());
        float3 hit_0 = org_0 + dir_0 * float3(pHitT_0) ;

        float3 p_1 = hit_0 + n_1 * float3(9.9999997473787516e-05f) ;

        uint mi_0 = (&kernelContext_4)->instances_0[inst_0 + 2U] * 12U;
        float3 albedo_1 = float3((&kernelContext_4)->materials_0[mi_0], (&kernelContext_4)->materials_0[mi_0 + 1U], (&kernelContext_4)->materials_0[mi_0 + 2U]);
        float3 le_0 = float3((&kernelContext_4)->materials_0[mi_0 + 3U], (&kernelContext_4)->materials_0[mi_0 + 4U], (&kernelContext_4)->materials_0[mi_0 + 5U]);

#line 242
        bool ok_0;

#line 242
        float eta_2;

#line 242
        float3 radiance_2;
        if(any(le_0 > (float3(0.0f) )))
        {

            uint eb_0 = (&kernelContext_4)->instances_0[inst_0 + 3U];
            if(misPrev_0)
            {

#line 247
                ok_0 = eb_0 != 0U;

#line 247
            }
            else
            {

#line 247
                ok_0 = false;

#line 247
            }

#line 247
            if(ok_0)
            {
                uint _S61 = eb_0 - 1U;

#line 249
                uint _S62 = ((&q_1)->get_committed_primitive_id());

#line 249
                uint e_0 = (_S61 + _S62) * 16U;

                float pl_0 = (&kernelContext_4)->emitters_0[e_0 + 13U] * pHitT_0 * pHitT_0 / ((&kernelContext_4)->emitters_0[e_0 + 12U] * max(abs(dot(nOut_0, dir_0)), 9.9999997473787516e-05f));
                float _S63 = qPrev_0 * qPrev_0;

#line 252
                eta_2 = _S63 / (_S63 + pl_0 * pl_0);

#line 247
            }
            else
            {

#line 247
                eta_2 = 1.0f;

#line 247
            }

#line 247
            radiance_2 = radiance_1 + thr_0 * le_0 * float3(eta_2) ;

#line 243
        }
        else
        {

#line 243
            radiance_2 = radiance_1;

#line 243
        }

#line 256
        float metallic_1 = (&kernelContext_4)->materials_0[mi_0 + 6U];
        float rough_0 = (&kernelContext_4)->materials_0[mi_0 + 7U];
        float transmission_1 = (&kernelContext_4)->materials_0[mi_0 + 8U];
        float ior_1 = (&kernelContext_4)->materials_0[mi_0 + 9U];
        float _S64 = max(rough_0 * rough_0, 0.0010000000474974513f);
        if(outside_0)
        {

#line 261
            eta_2 = ior_1;

#line 261
        }
        else
        {

#line 261
            eta_2 = 1.0f / ior_1;

#line 261
        }

        thread float3 T_0;

#line 263
        thread float3 B_0;
        basis_0(n_1, &T_0, &B_0);
        float _S65 = max(dot(wo_1, n_1), 9.9999997473787516e-05f);

#line 265
        float3 woL_2 = float3(dot(wo_1, T_0), dot(wo_1, B_0), _S65);
        float fSel_1 = fresnelDielectric_0(_S65, ior_1);
        thread Surface_0 surf_0;
        (&surf_0)->albedo_0 = albedo_1;
        (&surf_0)->metallic_0 = metallic_1;
        (&surf_0)->alpha_2 = _S64;
        (&surf_0)->transmission_0 = transmission_1;
        (&surf_0)->ior_0 = ior_1;
        (&surf_0)->eta_1 = eta_2;
        (&surf_0)->fSel_0 = fSel_1;

#line 274
        uint li_1 = 0U;

#line 274
        radiance_0 = radiance_2;



        for(;;)
        {

#line 278
            if(li_1 < _S46)
            {
            }
            else
            {

#line 278
                break;
            }
            uint o_2 = li_1 * 8U;
            float3 col_0 = float3((as_type<float>(((&kernelContext_4)->lights_0[o_2 + 1U]))), (as_type<float>(((&kernelContext_4)->lights_0[o_2 + 2U]))), (as_type<float>(((&kernelContext_4)->lights_0[o_2 + 3U])))) * float3((as_type<float>(((&kernelContext_4)->lights_0[o_2 + 4U])))) ;
            float3 vec_0 = float3((as_type<float>(((&kernelContext_4)->lights_0[o_2 + 5U]))), (as_type<float>(((&kernelContext_4)->lights_0[o_2 + 6U]))), (as_type<float>(((&kernelContext_4)->lights_0[o_2 + 7U]))));



            if((&kernelContext_4)->lights_0[o_2] == 0U)
            {
                float3 toL_0 = vec_0 - p_1;
                float d2_0 = dot(toL_0, toL_0);
                float dist_1 = sqrt(d2_0);

                float3 _S66 = col_0 / float3(d2_0) ;

#line 292
                wi_0 = toL_0 / float3(dist_1) ;

#line 292
                dist_0 = dist_1;

#line 292
                li_0 = _S66;

#line 286
            }
            else
            {

#line 286
                wi_0 = - normalize(vec_0);

#line 286
                dist_0 = 1.00000001504746622e+30f;

#line 286
                li_0 = col_0;

#line 286
            }

#line 300
            float c_1 = dot(n_1, wi_0);
            if(c_1 > 0.0f)
            {

#line 301
                bool _S67 = occluded_0(p_1, wi_0, dist_0 - 0.0010000000474974513f, &kernelContext_4);

#line 301
                ok_0 = !_S67;

#line 301
            }
            else
            {

#line 301
                ok_0 = false;

#line 301
            }

#line 301
            if(ok_0)
            {
                float3 _S68 = float3(dot(wi_0, T_0), dot(wi_0, B_0), c_1);

#line 303
                thread Surface_0 _S69 = surf_0;

#line 303
                float3 _S70 = evalReflective_0(&_S69, woL_2, _S68);

#line 303
                radiance_0 = radiance_0 + thr_0 * _S70 * li_0;

#line 301
            }

#line 278
            li_1 = li_1 + 1U;

#line 278
        }

#line 278
        bool refracted_0;

#line 309
        if(_S48 > 0U)
        {
            float _S71 = Rng_next_0(&rng_0);
            float ua_0 = Rng_next_0(&rng_0);
            float ub_0 = Rng_next_0(&rng_0);

            uint _S72 = _S48 - 1U;

#line 315
            uint lo_0 = 0U;

#line 315
            uint hi_0 = _S72;
            for(;;)
            {

#line 316
                if(lo_0 < hi_0)
                {
                }
                else
                {

#line 316
                    break;
                }
                uint mid_0 = (lo_0 + hi_0) / 2U;
                if((&kernelContext_4)->emitCdf_0[mid_0] >= _S71)
                {

#line 319
                    hi_0 = mid_0;

#line 319
                }
                else
                {

#line 319
                    lo_0 = mid_0 + 1U;

#line 319
                }

#line 316
            }

#line 324
            uint e_1 = lo_0 * 16U;
            float3 a_2 = float3((&kernelContext_4)->emitters_0[e_1], (&kernelContext_4)->emitters_0[e_1 + 1U], (&kernelContext_4)->emitters_0[e_1 + 2U]);
            float3 b_2 = float3((&kernelContext_4)->emitters_0[e_1 + 3U], (&kernelContext_4)->emitters_0[e_1 + 4U], (&kernelContext_4)->emitters_0[e_1 + 5U]);
            float3 c_2 = float3((&kernelContext_4)->emitters_0[e_1 + 6U], (&kernelContext_4)->emitters_0[e_1 + 7U], (&kernelContext_4)->emitters_0[e_1 + 8U]);
            float su_0 = sqrt(ua_0);

            float3 toL_1 = a_2 * float3((1.0f - su_0))  + b_2 * float3((su_0 * (1.0f - ub_0)))  + c_2 * float3((su_0 * ub_0))  - p_1;
            float d2_1 = dot(toL_1, toL_1);
            float dist_2 = sqrt(d2_1);
            float3 wi_1 = toL_1 / float3(dist_2) ;
            float cosl_0 = abs(dot(normalize(cross(b_2 - a_2, c_2 - a_2)), wi_1));
            float cosi_1 = dot(n_1, wi_1);
            if(cosi_1 > 0.0f)
            {

#line 336
                ok_0 = cosl_0 > 9.9999997473787516e-06f;

#line 336
            }
            else
            {

#line 336
                ok_0 = false;

#line 336
            }

#line 336
            if(ok_0)
            {

#line 336
                bool _S73 = occluded_0(p_1, wi_1, dist_2 * 0.99900001287460327f, &kernelContext_4);

#line 336
                refracted_0 = !_S73;

#line 336
            }
            else
            {

#line 336
                refracted_0 = false;

#line 336
            }

#line 336
            if(refracted_0)
            {
                float pl_1 = (&kernelContext_4)->emitters_0[e_1 + 13U] * d2_1 / ((&kernelContext_4)->emitters_0[e_1 + 12U] * cosl_0);
                float3 wiL_2 = float3(dot(wi_1, T_0), dot(wi_1, B_0), cosi_1);

#line 339
                thread Surface_0 _S74 = surf_0;

#line 339
                float _S75 = reflectivePdf_0(&_S74, woL_2, wiL_2);

                float _S76 = pl_1 * pl_1;

#line 341
                float wl_0 = _S76 / (_S76 + _S75 * _S75);

#line 341
                thread Surface_0 _S77 = surf_0;

#line 341
                float3 _S78 = evalReflective_0(&_S77, woL_2, wiL_2);

#line 341
                wi_0 = radiance_0 + thr_0 * _S78 * float3((&kernelContext_4)->emitters_0[e_1 + 9U], (&kernelContext_4)->emitters_0[e_1 + 10U], (&kernelContext_4)->emitters_0[e_1 + 11U]) / float3(pl_1)  * float3(wl_0) ;

#line 336
            }
            else
            {

#line 336
                wi_0 = radiance_0;

#line 336
            }

#line 309
        }
        else
        {

#line 309
            wi_0 = radiance_0;

#line 309
        }

#line 348
        float lobe_0 = Rng_next_0(&rng_0);
        float u1_2 = Rng_next_0(&rng_0);
        float u2_2 = Rng_next_0(&rng_0);
        float u3_0 = Rng_next_0(&rng_0);

#line 351
        float3 w_2;

#line 356
        if(lobe_0 < metallic_1)
        {
            float3 h_1 = sampleVndf_0(woL_2, _S64, u1_2, u2_2);
            float woh_0 = dot(woL_2, h_1);
            float3 wiL_3 = float3((2.0f * woh_0))  * h_1 - woL_2;
            float _S79 = wiL_3.z;
            float3 _S80 = schlick_0(albedo_1, woh_0) * float3(G1_0(max(_S79, 0.0f), _S64)) ;

#line 362
            ok_0 = _S79 > 0.0f;

#line 362
            refracted_0 = false;

#line 362
            li_0 = wiL_3;

#line 362
            w_2 = _S80;

#line 356
        }
        else
        {

#line 364
            if(lobe_0 < (metallic_1 + (1.0f - metallic_1) * transmission_1))
            {
                float3 h_2 = sampleVndf_0(woL_2, _S64, u1_2, u2_2);
                float woh_1 = dot(woL_2, h_2);
                if(u3_0 < (fresnelDielectric_0(woh_1, eta_2)))
                {
                    float3 wiL_4 = float3((2.0f * woh_1))  * h_2 - woL_2;
                    float _S81 = wiL_4.z;
                    float3 _S82 = float3(G1_0(max(_S81, 0.0f), _S64)) ;

#line 372
                    ok_0 = _S81 > 0.0f;

#line 372
                    refracted_0 = false;

#line 372
                    li_0 = wiL_4;

#line 372
                    w_2 = _S82;

#line 368
                }
                else
                {

#line 376
                    float r_4 = 1.0f / eta_2;
                    float k_0 = 1.0f - r_4 * r_4 * (1.0f - woh_1 * woh_1);

#line 377
                    float3 _S83 = float3(r_4) ;
                    float3 wiL_5 = - woL_2 * _S83 + float3((r_4 * woh_1 - sqrt(max(k_0, 0.0f))))  * h_2;
                    float _S84 = wiL_5.z;

#line 379
                    if(_S84 < 0.0f)
                    {

#line 379
                        ok_0 = k_0 > 0.0f;

#line 379
                    }
                    else
                    {

#line 379
                        ok_0 = false;

#line 379
                    }


                    float3 _S85 = albedo_1 * float3(G1_0(max(- _S84, 0.0f), _S64))  * _S83 * _S83;

#line 382
                    refracted_0 = true;

#line 382
                    li_0 = wiL_5;

#line 382
                    w_2 = _S85;

#line 368
                }

#line 364
            }
            else
            {

#line 385
                if(u3_0 < fSel_1)
                {
                    float3 h_3 = sampleVndf_0(woL_2, _S64, u1_2, u2_2);
                    float woh_2 = dot(woL_2, h_3);
                    float3 wiL_6 = float3((2.0f * woh_2))  * h_3 - woL_2;
                    float _S86 = wiL_6.z;
                    float3 _S87 = float3((fresnelDielectric_0(woh_2, ior_1) / fSel_1 * G1_0(max(_S86, 0.0f), _S64))) ;

#line 391
                    ok_0 = _S86 > 0.0f;

#line 391
                    li_0 = wiL_6;

#line 391
                    w_2 = _S87;

#line 385
                }
                else
                {

#line 395
                    float3 _S88 = cosineLocal_0(u1_2, u2_2);

#line 395
                    ok_0 = true;

#line 395
                    li_0 = _S88;

#line 395
                    w_2 = albedo_1;

#line 385
                }

#line 385
                refracted_0 = false;

#line 364
            }

#line 356
        }

#line 398
        if(!ok_0)
        {

#line 398
            radiance_0 = wi_0;
            break;
        }

#line 400
        bool _S89 = !refracted_0;
        if(refracted_0)
        {

#line 401
            qPrev_0 = 0.0f;

#line 401
        }
        else
        {

#line 401
            thread Surface_0 _S90 = surf_0;

#line 401
            float _S91 = reflectivePdf_0(&_S90, woL_2, li_0);

#line 401
            qPrev_0 = _S91;

#line 401
        }

        float _S92 = li_0.z;

#line 403
        dir_0 = normalize(float3(li_0.x)  * T_0 + float3(li_0.y)  * B_0 + float3(_S92)  * n_1);
        if(_S92 > 0.0f)
        {

#line 404
            dist_0 = 9.9999997473787516e-05f;

#line 404
        }
        else
        {

#line 404
            dist_0 = -9.9999997473787516e-05f;

#line 404
        }

#line 404
        org_0 = hit_0 + n_1 * float3(dist_0) ;
        float3 thr_1 = thr_0 * w_2;

        if(depth_0 >= 2U)
        {
            float pr_0 = clamp(max(thr_1.x, max(thr_1.y, thr_1.z)), 0.05000000074505806f, 0.94999998807907104f);
            float _S93 = Rng_next_0(&rng_0);

#line 410
            if(_S93 > pr_0)
            {

#line 410
                radiance_0 = wi_0;
                break;
            }

#line 411
            thr_0 = thr_1 / float3(pr_0) ;

#line 407
        }
        else
        {

#line 407
            thr_0 = thr_1;

#line 407
        }

#line 206
        uint _S94 = depth_0 + 1U;

#line 206
        misPrev_0 = _S89;

#line 206
        depth_0 = _S94;

#line 206
        radiance_1 = wi_0;

#line 206
    }

#line 416
    if(any(isnan(radiance_0)))
    {

#line 416
        misPrev_0 = true;

#line 416
    }
    else
    {

#line 416
        misPrev_0 = any(isinf(radiance_0));

#line 416
    }

#line 416
    if(misPrev_0)
    {

#line 416
        radiance_0 = _S44;

#line 416
    }


    uint o_3 = 3U * pixel_0;
    float device* _S95 = (&kernelContext_4)->accum_0+o_3;

#line 420
    *_S95 = *_S95 + radiance_0.x;
    float device* _S96 = (&kernelContext_4)->accum_0+(o_3 + 1U);

#line 421
    *_S96 = *_S96 + radiance_0.y;
    float device* _S97 = (&kernelContext_4)->accum_0+(o_3 + 2U);

#line 422
    *_S97 = *_S97 + radiance_0.z;
    return;
}

