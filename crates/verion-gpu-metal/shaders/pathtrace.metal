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
            

#line 17 "shaders/pathtrace.slang"
uint pcg_0(uint v_0)
{
    uint s_0 = v_0 * 747796405U + 2891336453U;
    uint w_0 = ((s_0 >> ((s_0 >> 28U) + 4U)) ^ s_0) * 277803737U;
    return (w_0 >> 22U) ^ w_0;
}


#line 320
struct KernelContext_0
{
    uint device* params_0;
    metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_0;
    uint device* instances_0;
    uint device* indices_0;
    float device* positions_0;
    float device* materials_0;
    uint device* lights_0;
    float device* accum_0;
};


#line 34
float pf_0(uint i_0, KernelContext_0 thread* kernelContext_0)
{

#line 34
    return (as_type<float>((kernelContext_0->params_0[i_0])));
}


#line 24
struct Rng_0
{
    uint state_0;
};


#line 27
float Rng_next_0(Rng_0 thread* this_0)
{
    uint _S1 = pcg_0(this_0->state_0);

#line 29
    this_0->state_0 = _S1;
    return float(_S1 >> 8U) * 5.9604644775390625e-08f;
}




float3 vertexPos_0(uint v_1, KernelContext_0 thread* kernelContext_1)
{

#line 36
    uint _S2 = 3U * v_1;

#line 36
    return float3(kernelContext_1->positions_0[_S2], kernelContext_1->positions_0[_S2 + 1U], kernelContext_1->positions_0[_S2 + 2U]);
}


#line 38
float3 transformPoint_0(uint base_0, float3 p_0, KernelContext_0 thread* kernelContext_2)
{
    thread float3 r_0;

#line 40
    uint row_0 = 0U;
    for(;;)
    {

#line 41
        if(row_0 < 3U)
        {
        }
        else
        {

#line 41
            break;
        }
        uint o_0 = base_0 + 4U * row_0;
        r_0[row_0] = (as_type<float>((kernelContext_2->instances_0[o_0]))) * p_0.x + (as_type<float>((kernelContext_2->instances_0[o_0 + 1U]))) * p_0.y + (as_type<float>((kernelContext_2->instances_0[o_0 + 2U]))) * p_0.z + (as_type<float>((kernelContext_2->instances_0[o_0 + 3U])));

#line 41
        row_0 = row_0 + 1U;

#line 41
    }

#line 46
    return r_0;
}


#line 89
void basis_0(float3 n_0, float3 thread* t_0, float3 thread* b_0)
{

#line 89
    float3 a_0;

    if((abs(n_0.x)) > 0.89999997615814209f)
    {

#line 91
        a_0 = float3(0.0f, 1.0f, 0.0f);

#line 91
    }
    else
    {

#line 91
        a_0 = float3(1.0f, 0.0f, 0.0f);

#line 91
    }
    float3 _S3 = normalize(cross(n_0, a_0));

#line 92
    *b_0 = _S3;
    *t_0 = cross(_S3, n_0);
    return;
}


#line 78
float fresnelDielectric_0(float cosi_0, float eta_0)
{
    float s2_0 = (1.0f - cosi_0 * cosi_0) / (eta_0 * eta_0);
    if(s2_0 >= 1.0f)
    {

#line 82
        return 1.0f;
    }

#line 83
    float cost_0 = sqrt(1.0f - s2_0);
    float _S4 = eta_0 * cost_0;

#line 84
    float rs_0 = (cosi_0 - _S4) / (cosi_0 + _S4);
    float _S5 = eta_0 * cosi_0;

#line 85
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


#line 113 "shaders/pathtrace.slang"
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

#line 122
        bool _S6 = ((&q_0)->next());

#line 122
        if(_S6)
        {
        }
        else
        {

#line 122
            break;
        }

#line 122
    }
    uint _S7 = (_slang_committed_intersection_type_to_uint((&q_0)->get_committed_intersection_type()));

#line 123
    return _S7 == 1U;
}


#line 63
float D_0(float hz_0, float alpha_0)
{
    float a2_0 = alpha_0 * alpha_0;
    float d_1 = hz_0 * hz_0 * (a2_0 - 1.0f) + 1.0f;
    return a2_0 / (3.1415927410125732f * d_1 * d_1);
}


#line 56
float G1_0(float cosT_0, float alpha_1)
{
    float c2_0 = cosT_0 * cosT_0;

    return 2.0f / (1.0f + sqrt(1.0f + alpha_1 * alpha_1 * ((1.0f - c2_0) / max(c2_0, 9.99999993922529029e-09f))));
}


#line 70
float3 schlick_0(float3 f0_0, float c_0)
{
    float m_0 = 1.0f - saturate(c_0);
    float m2_0 = m_0 * m_0;
    return f0_0 + (float3(1.0f)  - f0_0) * float3((m2_0 * m2_0 * m_0)) ;
}


#line 97
float3 sampleVndf_0(float3 wo_0, float alpha_2, float u1_0, float u2_0)
{
    float3 vh_0 = normalize(float3(alpha_2 * wo_0.x, alpha_2 * wo_0.y, wo_0.z));
    float _S8 = vh_0.x;

#line 100
    float _S9 = vh_0.y;

#line 100
    float lensq_0 = _S8 * _S8 + _S9 * _S9;

#line 100
    float3 t1_0;
    if(lensq_0 > 0.0f)
    {

#line 101
        t1_0 = float3(- _S9, _S8, 0.0f) * float3(rsqrt(lensq_0)) ;

#line 101
    }
    else
    {

#line 101
        t1_0 = float3(1.0f, 0.0f, 0.0f);

#line 101
    }

    float r_1 = sqrt(u1_0);
    float phi_0 = 6.2831854820251465f * u2_0;
    float a_1 = r_1 * cos(phi_0);

    float s_1 = 0.5f * (1.0f + vh_0.z);
    float _S10 = 1.0f - a_1 * a_1;

#line 108
    float b_1 = (1.0f - s_1) * sqrt(_S10) + s_1 * (r_1 * sin(phi_0));
    float3 nh_0 = float3(a_1)  * t1_0 + float3(b_1)  * cross(vh_0, t1_0) + float3(sqrt(max(0.0f, _S10 - b_1 * b_1)))  * vh_0;
    return normalize(float3(alpha_2 * nh_0.x, alpha_2 * nh_0.y, max(0.0f, nh_0.z)));
}


#line 49
float3 cosineLocal_0(float u1_1, float u2_1)
{
    float r_2 = sqrt(u1_1);
    float phi_1 = 6.2831854820251465f * u2_1;
    return float3(r_2 * cos(phi_1), r_2 * sin(phi_1), sqrt(max(0.0f, 1.0f - u1_1)));
}


#line 128
[[kernel]] void pathtrace(uint3 tid_0 [[thread_position_in_grid]], uint device* params_1 [[buffer(6)]], metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_1 [[buffer(0)]], uint device* instances_1 [[buffer(3)]], uint device* indices_1 [[buffer(2)]], float device* positions_1 [[buffer(1)]], float device* materials_1 [[buffer(4)]], uint device* lights_1 [[buffer(5)]], float device* accum_1 [[buffer(7)]])
{

#line 128
    float3 radiance_0;

#line 128
    float3 wi_0;

#line 128
    float3 li_0;

#line 128
    float dist_0;

#line 128
    thread KernelContext_0 kernelContext_4;

#line 128
    (&kernelContext_4)->params_0 = params_1;

#line 128
    (&kernelContext_4)->scene_0 = scene_1;

#line 128
    (&kernelContext_4)->instances_0 = instances_1;

#line 128
    (&kernelContext_4)->indices_0 = indices_1;

#line 128
    (&kernelContext_4)->positions_0 = positions_1;

#line 128
    (&kernelContext_4)->materials_0 = materials_1;

#line 128
    (&kernelContext_4)->lights_0 = lights_1;

#line 128
    (&kernelContext_4)->accum_0 = accum_1;

    uint w_1 = params_1[int(0)];
    uint h_0 = params_1[int(1)];
    uint _S11 = tid_0.x;

#line 132
    bool ok_0;

#line 132
    if(_S11 >= w_1)
    {

#line 132
        ok_0 = true;

#line 132
    }
    else
    {

#line 132
        ok_0 = (tid_0.y) >= h_0;

#line 132
    }

#line 132
    if(ok_0)
    {

#line 133
        return;
    }

#line 134
    uint _S12 = tid_0.y;

#line 134
    uint pixel_0 = _S12 * w_1 + _S11;
    thread Rng_0 rng_0;
    (&rng_0)->state_0 = pcg_0(pixel_0 ^ (pcg_0((&kernelContext_4)->params_0[int(6)] * 2654435769U + 2135587861U)));

#line 136
    float _S13 = pf_0(2U, &kernelContext_4);



    float _S14 = float(w_1);

#line 140
    float _S15 = float(h_0);

#line 140
    float aspect_0 = _S14 / _S15;
    float _S16 = float(_S11);

#line 141
    float _S17 = Rng_next_0(&rng_0);

#line 141
    float u_0 = (2.0f * (_S16 + _S17) / _S14 - 1.0f) * aspect_0 * _S13;
    float _S18 = float(_S12);

#line 142
    float _S19 = Rng_next_0(&rng_0);
    float3 _S20 = float3(u_0, (1.0f - 2.0f * (_S18 + _S19) / _S15) * _S13, -1.0f);

#line 143
    float _S21 = pf_0(4U, &kernelContext_4);

#line 143
    float3 focal_0 = _S20 * float3(_S21) ;

#line 143
    float _S22 = pf_0(3U, &kernelContext_4);
    float _S23 = Rng_next_0(&rng_0);

#line 144
    float lensR_0 = _S22 * sqrt(_S23);
    float _S24 = Rng_next_0(&rng_0);

#line 145
    float lensA_0 = 6.2831854820251465f * _S24;
    float _S25 = lensR_0 * cos(lensA_0);

#line 146
    float _S26 = lensR_0 * sin(lensA_0);
    float3 _S27 = normalize(focal_0 - float3(_S25, _S26, 0.0f));
    thread float3 org_0;

#line 148
    thread float3 dir_0;

#line 148
    uint r_3 = 0U;
    for(;;)
    {

#line 149
        if(r_3 < 3U)
        {
        }
        else
        {

#line 149
            break;
        }
        uint _S28 = 4U * r_3;

#line 151
        uint _S29 = 8U + _S28;

#line 151
        uint _S30 = 9U + _S28;

#line 151
        uint _S31 = 10U + _S28;

#line 151
        org_0[r_3] = (as_type<float>(((&kernelContext_4)->params_0[_S29]))) * _S25 + (as_type<float>(((&kernelContext_4)->params_0[_S30]))) * _S26 + (as_type<float>(((&kernelContext_4)->params_0[_S31]))) * 0.0f + (as_type<float>(((&kernelContext_4)->params_0[11U + _S28])));
        dir_0[r_3] = (as_type<float>(((&kernelContext_4)->params_0[_S29]))) * _S27.x + (as_type<float>(((&kernelContext_4)->params_0[_S30]))) * _S27.y + (as_type<float>(((&kernelContext_4)->params_0[_S31]))) * _S27.z;

#line 149
        r_3 = r_3 + 1U;

#line 149
    }

#line 154
    dir_0 = normalize(dir_0);

#line 154
    float _S32 = pf_0(20U, &kernelContext_4);

#line 154
    float _S33 = pf_0(21U, &kernelContext_4);

#line 154
    float _S34 = pf_0(22U, &kernelContext_4);

    float3 _S35 = float3(_S32, _S33, _S34);
    float3 _S36 = float3(0.0f) ;
    float3 _S37 = float3(1.0f) ;
    uint _S38 = (&kernelContext_4)->params_0[int(5)];
    uint _S39 = (&kernelContext_4)->params_0[int(7)];

#line 160
    uint depth_0 = 0U;

#line 160
    float3 thr_0 = _S37;

#line 160
    float3 radiance_1 = _S36;

    for(;;)
    {

#line 162
        if(depth_0 < _S39)
        {
        }
        else
        {

#line 162
            radiance_0 = radiance_1;

#line 162
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

#line 171
            bool _S40 = ((&q_1)->next());

#line 171
            if(_S40)
            {
            }
            else
            {

#line 171
                break;
            }

#line 171
        }

        uint _S41 = (_slang_committed_intersection_type_to_uint((&q_1)->get_committed_intersection_type()));

#line 173
        if(_S41 != 1U)
        {

#line 173
            radiance_0 = radiance_1 + thr_0 * _S35;



            break;
        }

        uint _S42 = ((&q_1)->get_committed_instance_id());

#line 180
        uint inst_0 = _S42 * 16U;
        uint _S43 = (&kernelContext_4)->instances_0[inst_0 + 1U];

#line 181
        uint _S44 = ((&q_1)->get_committed_primitive_id());

#line 181
        uint tri_0 = _S43 + 3U * _S44;
        uint vo_0 = (&kernelContext_4)->instances_0[inst_0];
        uint _S45 = inst_0 + 4U;

#line 183
        float3 _S46 = vertexPos_0((&kernelContext_4)->indices_0[tri_0] + vo_0, &kernelContext_4);

#line 183
        float3 _S47 = transformPoint_0(_S45, _S46, &kernelContext_4);

#line 183
        float3 _S48 = vertexPos_0((&kernelContext_4)->indices_0[tri_0 + 1U] + vo_0, &kernelContext_4);

#line 183
        float3 _S49 = transformPoint_0(_S45, _S48, &kernelContext_4);

#line 183
        float3 _S50 = vertexPos_0((&kernelContext_4)->indices_0[tri_0 + 2U] + vo_0, &kernelContext_4);

#line 183
        float3 _S51 = transformPoint_0(_S45, _S50, &kernelContext_4);



        float3 nOut_0 = normalize(cross(_S49 - _S47, _S51 - _S47));
        float3 wo_1 = - dir_0;
        bool outside_0 = (dot(nOut_0, wo_1)) > 0.0f;

#line 189
        float3 n_1;
        if(outside_0)
        {

#line 190
            n_1 = nOut_0;

#line 190
        }
        else
        {

#line 190
            n_1 = - nOut_0;

#line 190
        }
        float pHitT_0 = ((&q_1)->get_committed_distance());
        float3 hit_0 = org_0 + dir_0 * float3(pHitT_0) ;

        float3 _S52 = hit_0 + n_1 * float3(9.9999997473787516e-05f) ;

        uint mi_0 = (&kernelContext_4)->instances_0[inst_0 + 2U] * 12U;
        float3 albedo_0 = float3((&kernelContext_4)->materials_0[mi_0], (&kernelContext_4)->materials_0[mi_0 + 1U], (&kernelContext_4)->materials_0[mi_0 + 2U]);
        float3 radiance_2 = radiance_1 + thr_0 * float3((&kernelContext_4)->materials_0[mi_0 + 3U], (&kernelContext_4)->materials_0[mi_0 + 4U], (&kernelContext_4)->materials_0[mi_0 + 5U]);
        float metallic_0 = (&kernelContext_4)->materials_0[mi_0 + 6U];
        float rough_0 = (&kernelContext_4)->materials_0[mi_0 + 7U];
        float transmission_0 = (&kernelContext_4)->materials_0[mi_0 + 8U];
        float ior_0 = (&kernelContext_4)->materials_0[mi_0 + 9U];
        float _S53 = max(rough_0 * rough_0, 0.0010000000474974513f);

#line 203
        float eta_1;
        if(outside_0)
        {

#line 204
            eta_1 = ior_0;

#line 204
        }
        else
        {

#line 204
            eta_1 = 1.0f / ior_0;

#line 204
        }

        thread float3 T_0;

#line 206
        thread float3 B_0;
        basis_0(n_1, &T_0, &B_0);
        float _S54 = max(dot(wo_1, n_1), 9.9999997473787516e-05f);

#line 208
        float3 woL_0 = float3(dot(wo_1, T_0), dot(wo_1, B_0), _S54);
        float fSel_0 = fresnelDielectric_0(_S54, ior_0);

#line 209
        uint li_1 = 0U;

#line 209
        radiance_0 = radiance_2;



        for(;;)
        {

#line 213
            if(li_1 < _S38)
            {
            }
            else
            {

#line 213
                break;
            }
            uint o_2 = li_1 * 8U;
            float3 col_0 = float3((as_type<float>(((&kernelContext_4)->lights_0[o_2 + 1U]))), (as_type<float>(((&kernelContext_4)->lights_0[o_2 + 2U]))), (as_type<float>(((&kernelContext_4)->lights_0[o_2 + 3U])))) * float3((as_type<float>(((&kernelContext_4)->lights_0[o_2 + 4U])))) ;
            float3 vec_0 = float3((as_type<float>(((&kernelContext_4)->lights_0[o_2 + 5U]))), (as_type<float>(((&kernelContext_4)->lights_0[o_2 + 6U]))), (as_type<float>(((&kernelContext_4)->lights_0[o_2 + 7U]))));



            if((&kernelContext_4)->lights_0[o_2] == 0U)
            {
                float3 toL_0 = vec_0 - _S52;
                float d2_0 = dot(toL_0, toL_0);
                float dist_1 = sqrt(d2_0);

                float3 _S55 = col_0 / float3(d2_0) ;

#line 227
                wi_0 = toL_0 / float3(dist_1) ;

#line 227
                dist_0 = dist_1;

#line 227
                li_0 = _S55;

#line 221
            }
            else
            {

#line 221
                wi_0 = - normalize(vec_0);

#line 221
                dist_0 = 1.00000001504746622e+30f;

#line 221
                li_0 = col_0;

#line 221
            }

#line 235
            float c_1 = dot(n_1, wi_0);
            if(c_1 > 0.0f)
            {

#line 236
                bool _S56 = occluded_0(_S52, wi_0, dist_0 - 0.0010000000474974513f, &kernelContext_4);

#line 236
                ok_0 = !_S56;

#line 236
            }
            else
            {

#line 236
                ok_0 = false;

#line 236
            }

#line 236
            if(ok_0)
            {

                float3 hh_0 = normalize(woL_0 + float3(dot(wi_0, T_0), dot(wi_0, B_0), c_1));
                float _S57 = max(dot(woL_0, hh_0), 0.0f);

                float core_0 = D_0(hh_0.z, _S53) * G1_0(_S54, _S53) * G1_0(c_1, _S53) / (4.0f * _S54);

                float _S58 = 1.0f - metallic_0;

#line 244
                float _S59 = 1.0f - transmission_0;

#line 244
                radiance_0 = radiance_0 + thr_0 * (float3(metallic_0)  * schlick_0(albedo_0, _S57) * float3(core_0)  + float3((_S58 * (transmission_0 * fresnelDielectric_0(_S57, eta_1) + _S59 * fresnelDielectric_0(_S57, ior_0)) * core_0))  + float3((_S58 * _S59 * (1.0f - fSel_0)))  * albedo_0 * float3((c_1 / 3.1415927410125732f)) ) * li_0;

#line 236
            }

#line 213
            li_1 = li_1 + 1U;

#line 213
        }

#line 252
        float lobe_0 = Rng_next_0(&rng_0);
        float u1_2 = Rng_next_0(&rng_0);
        float u2_2 = Rng_next_0(&rng_0);
        float u3_0 = Rng_next_0(&rng_0);



        if(lobe_0 < metallic_0)
        {
            float3 h_1 = sampleVndf_0(woL_0, _S53, u1_2, u2_2);
            float woh_0 = dot(woL_0, h_1);
            float3 wiL_0 = float3((2.0f * woh_0))  * h_1 - woL_0;
            float _S60 = wiL_0.z;
            float3 _S61 = schlick_0(albedo_0, woh_0) * float3(G1_0(max(_S60, 0.0f), _S53)) ;

#line 265
            ok_0 = _S60 > 0.0f;

#line 265
            wi_0 = wiL_0;

#line 265
            li_0 = _S61;

#line 259
        }
        else
        {

#line 267
            if(lobe_0 < (metallic_0 + (1.0f - metallic_0) * transmission_0))
            {
                float3 h_2 = sampleVndf_0(woL_0, _S53, u1_2, u2_2);
                float woh_1 = dot(woL_0, h_2);
                if(u3_0 < (fresnelDielectric_0(woh_1, eta_1)))
                {
                    float3 wiL_1 = float3((2.0f * woh_1))  * h_2 - woL_0;
                    float _S62 = wiL_1.z;
                    float3 _S63 = float3(G1_0(max(_S62, 0.0f), _S53)) ;

#line 275
                    ok_0 = _S62 > 0.0f;

#line 275
                    wi_0 = wiL_1;

#line 275
                    li_0 = _S63;

#line 271
                }
                else
                {

#line 279
                    float r_4 = 1.0f / eta_1;
                    float k_0 = 1.0f - r_4 * r_4 * (1.0f - woh_1 * woh_1);

#line 280
                    float3 _S64 = float3(r_4) ;
                    float3 wiL_2 = - woL_0 * _S64 + float3((r_4 * woh_1 - sqrt(max(k_0, 0.0f))))  * h_2;
                    float _S65 = wiL_2.z;

#line 282
                    if(_S65 < 0.0f)
                    {

#line 282
                        ok_0 = k_0 > 0.0f;

#line 282
                    }
                    else
                    {

#line 282
                        ok_0 = false;

#line 282
                    }

                    float3 _S66 = albedo_0 * float3(G1_0(max(- _S65, 0.0f), _S53))  * _S64 * _S64;

#line 284
                    wi_0 = wiL_2;

#line 284
                    li_0 = _S66;

#line 271
                }

#line 267
            }
            else
            {

#line 287
                if(u3_0 < fSel_0)
                {
                    float3 h_3 = sampleVndf_0(woL_0, _S53, u1_2, u2_2);
                    float woh_2 = dot(woL_0, h_3);
                    float3 wiL_3 = float3((2.0f * woh_2))  * h_3 - woL_0;
                    float _S67 = wiL_3.z;
                    float3 _S68 = float3((fresnelDielectric_0(woh_2, ior_0) / fSel_0 * G1_0(max(_S67, 0.0f), _S53))) ;

#line 293
                    ok_0 = _S67 > 0.0f;

#line 293
                    wi_0 = wiL_3;

#line 293
                    li_0 = _S68;

#line 287
                }
                else
                {

#line 297
                    float3 _S69 = cosineLocal_0(u1_2, u2_2);

#line 297
                    ok_0 = true;

#line 297
                    wi_0 = _S69;

#line 297
                    li_0 = albedo_0;

#line 287
                }

#line 267
            }

#line 259
        }

#line 300
        if(!ok_0)
        {

#line 301
            break;
        }
        float _S70 = wi_0.z;

#line 303
        dir_0 = normalize(float3(wi_0.x)  * T_0 + float3(wi_0.y)  * B_0 + float3(_S70)  * n_1);
        if(_S70 > 0.0f)
        {

#line 304
            dist_0 = 9.9999997473787516e-05f;

#line 304
        }
        else
        {

#line 304
            dist_0 = -9.9999997473787516e-05f;

#line 304
        }

#line 304
        org_0 = hit_0 + n_1 * float3(dist_0) ;
        float3 thr_1 = thr_0 * li_0;

        if(depth_0 >= 2U)
        {
            float pr_0 = clamp(max(thr_1.x, max(thr_1.y, thr_1.z)), 0.05000000074505806f, 0.94999998807907104f);
            float _S71 = Rng_next_0(&rng_0);

#line 310
            if(_S71 > pr_0)
            {

#line 311
                break;
            }

#line 311
            thr_0 = thr_1 / float3(pr_0) ;

#line 307
        }
        else
        {

#line 307
            thr_0 = thr_1;

#line 307
        }

#line 162
        depth_0 = depth_0 + 1U;

#line 162
        radiance_1 = radiance_0;

#line 162
    }

#line 316
    if(any(isnan(radiance_0)))
    {

#line 316
        ok_0 = true;

#line 316
    }
    else
    {

#line 316
        ok_0 = any(isinf(radiance_0));

#line 316
    }

#line 316
    if(ok_0)
    {

#line 316
        radiance_0 = _S36;

#line 316
    }


    uint o_3 = 3U * pixel_0;
    float device* _S72 = (&kernelContext_4)->accum_0+o_3;

#line 320
    *_S72 = *_S72 + radiance_0.x;
    float device* _S73 = (&kernelContext_4)->accum_0+(o_3 + 1U);

#line 321
    *_S73 = *_S73 + radiance_0.y;
    float device* _S74 = (&kernelContext_4)->accum_0+(o_3 + 2U);

#line 322
    *_S74 = *_S74 + radiance_0.z;
    return;
}

