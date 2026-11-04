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


#line 185
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


#line 20995 "hlsl.meta.slang"
struct RayDesc_0
{
    float3 Origin_0;
    float TMin_0;
    float3 Direction_0;
    float TMax_0;
};


#line 59 "shaders/pathtrace.slang"
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

#line 68
        bool _S3 = ((&q_0)->next());

#line 68
        if(_S3)
        {
        }
        else
        {

#line 68
            break;
        }

#line 68
    }
    uint _S4 = (_slang_committed_intersection_type_to_uint((&q_0)->get_committed_intersection_type()));

#line 69
    return _S4 == 1U;
}


#line 49
float3 cosineHemisphere_0(float3 n_0, float u1_0, float u2_0)
{

#line 49
    float3 a_0;

    if((abs(n_0.x)) > 0.89999997615814209f)
    {

#line 51
        a_0 = float3(0.0f, 1.0f, 0.0f);

#line 51
    }
    else
    {

#line 51
        a_0 = float3(1.0f, 0.0f, 0.0f);

#line 51
    }
    float3 b_0 = normalize(cross(n_0, a_0));

    float r_1 = sqrt(u1_0);
    float phi_0 = 6.2831854820251465f * u2_0;
    return normalize(cross(b_0, n_0) * float3((r_1 * cos(phi_0)))  + b_0 * float3((r_1 * sin(phi_0)))  + n_0 * float3(sqrt(max(0.0f, 1.0f - u1_0))) );
}


#line 74
[[kernel]] void pathtrace(uint3 tid_0 [[thread_position_in_grid]], uint device* params_1 [[buffer(6)]], metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_1 [[buffer(0)]], uint device* instances_1 [[buffer(3)]], uint device* indices_1 [[buffer(2)]], float device* positions_1 [[buffer(1)]], float device* materials_1 [[buffer(4)]], uint device* lights_1 [[buffer(5)]], float device* accum_1 [[buffer(7)]])
{

#line 74
    float3 radiance_0;

#line 74
    thread KernelContext_0 kernelContext_4;

#line 74
    (&kernelContext_4)->params_0 = params_1;

#line 74
    (&kernelContext_4)->scene_0 = scene_1;

#line 74
    (&kernelContext_4)->instances_0 = instances_1;

#line 74
    (&kernelContext_4)->indices_0 = indices_1;

#line 74
    (&kernelContext_4)->positions_0 = positions_1;

#line 74
    (&kernelContext_4)->materials_0 = materials_1;

#line 74
    (&kernelContext_4)->lights_0 = lights_1;

#line 74
    (&kernelContext_4)->accum_0 = accum_1;

    uint w_1 = params_1[int(0)];
    uint h_0 = params_1[int(1)];
    uint _S5 = tid_0.x;

#line 78
    bool _S6;

#line 78
    if(_S5 >= w_1)
    {

#line 78
        _S6 = true;

#line 78
    }
    else
    {

#line 78
        _S6 = (tid_0.y) >= h_0;

#line 78
    }

#line 78
    if(_S6)
    {

#line 79
        return;
    }

#line 80
    uint _S7 = tid_0.y;

#line 80
    uint pixel_0 = _S7 * w_1 + _S5;
    thread Rng_0 rng_0;
    (&rng_0)->state_0 = pcg_0(pixel_0 ^ (pcg_0((&kernelContext_4)->params_0[int(6)] * 2654435769U + 2135587861U)));

#line 82
    float _S8 = pf_0(2U, &kernelContext_4);



    float _S9 = float(w_1);

#line 86
    float _S10 = float(h_0);

#line 86
    float aspect_0 = _S9 / _S10;
    float _S11 = float(_S5);

#line 87
    float _S12 = Rng_next_0(&rng_0);

#line 87
    float u_0 = (2.0f * (_S11 + _S12) / _S9 - 1.0f) * aspect_0 * _S8;
    float _S13 = float(_S7);

#line 88
    float _S14 = Rng_next_0(&rng_0);
    float3 _S15 = float3(u_0, (1.0f - 2.0f * (_S13 + _S14) / _S10) * _S8, -1.0f);

#line 89
    float _S16 = pf_0(4U, &kernelContext_4);

#line 89
    float3 focal_0 = _S15 * float3(_S16) ;

#line 89
    float _S17 = pf_0(3U, &kernelContext_4);
    float _S18 = Rng_next_0(&rng_0);

#line 90
    float lensR_0 = _S17 * sqrt(_S18);
    float _S19 = Rng_next_0(&rng_0);

#line 91
    float lensA_0 = 6.2831854820251465f * _S19;
    float _S20 = lensR_0 * cos(lensA_0);

#line 92
    float _S21 = lensR_0 * sin(lensA_0);
    float3 _S22 = normalize(focal_0 - float3(_S20, _S21, 0.0f));
    thread float3 org_0;

#line 94
    thread float3 dir_0;

#line 94
    uint r_2 = 0U;
    for(;;)
    {

#line 95
        if(r_2 < 3U)
        {
        }
        else
        {

#line 95
            break;
        }
        uint _S23 = 4U * r_2;

#line 97
        uint _S24 = 8U + _S23;

#line 97
        uint _S25 = 9U + _S23;

#line 97
        uint _S26 = 10U + _S23;

#line 97
        org_0[r_2] = (as_type<float>(((&kernelContext_4)->params_0[_S24]))) * _S20 + (as_type<float>(((&kernelContext_4)->params_0[_S25]))) * _S21 + (as_type<float>(((&kernelContext_4)->params_0[_S26]))) * 0.0f + (as_type<float>(((&kernelContext_4)->params_0[11U + _S23])));
        dir_0[r_2] = (as_type<float>(((&kernelContext_4)->params_0[_S24]))) * _S22.x + (as_type<float>(((&kernelContext_4)->params_0[_S25]))) * _S22.y + (as_type<float>(((&kernelContext_4)->params_0[_S26]))) * _S22.z;

#line 95
        r_2 = r_2 + 1U;

#line 95
    }

#line 100
    dir_0 = normalize(dir_0);

#line 100
    float _S27 = pf_0(20U, &kernelContext_4);

#line 100
    float _S28 = pf_0(21U, &kernelContext_4);

#line 100
    float _S29 = pf_0(22U, &kernelContext_4);

    float3 _S30 = float3(_S27, _S28, _S29);
    float3 _S31 = float3(0.0f) ;
    float3 _S32 = float3(1.0f) ;
    uint _S33 = (&kernelContext_4)->params_0[int(5)];
    uint _S34 = (&kernelContext_4)->params_0[int(7)];

#line 106
    uint depth_0 = 0U;

#line 106
    float3 thr_0 = _S32;

#line 106
    float3 radiance_1 = _S31;

    for(;;)
    {

#line 108
        if(depth_0 < _S34)
        {
        }
        else
        {

#line 108
            radiance_0 = radiance_1;

#line 108
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

#line 117
            bool _S35 = ((&q_1)->next());

#line 117
            if(_S35)
            {
            }
            else
            {

#line 117
                break;
            }

#line 117
        }

        uint _S36 = (_slang_committed_intersection_type_to_uint((&q_1)->get_committed_intersection_type()));

#line 119
        if(_S36 != 1U)
        {

#line 119
            radiance_0 = radiance_1 + thr_0 * _S30;



            break;
        }

        uint _S37 = ((&q_1)->get_committed_instance_id());

#line 126
        uint inst_0 = _S37 * 16U;
        uint _S38 = (&kernelContext_4)->instances_0[inst_0 + 1U];

#line 127
        uint _S39 = ((&q_1)->get_committed_primitive_id());

#line 127
        uint tri_0 = _S38 + 3U * _S39;
        uint vo_0 = (&kernelContext_4)->instances_0[inst_0];
        uint _S40 = inst_0 + 4U;

#line 129
        float3 _S41 = vertexPos_0((&kernelContext_4)->indices_0[tri_0] + vo_0, &kernelContext_4);

#line 129
        float3 _S42 = transformPoint_0(_S40, _S41, &kernelContext_4);

#line 129
        float3 _S43 = vertexPos_0((&kernelContext_4)->indices_0[tri_0 + 1U] + vo_0, &kernelContext_4);

#line 129
        float3 _S44 = transformPoint_0(_S40, _S43, &kernelContext_4);

#line 129
        float3 _S45 = vertexPos_0((&kernelContext_4)->indices_0[tri_0 + 2U] + vo_0, &kernelContext_4);

#line 129
        float3 _S46 = transformPoint_0(_S40, _S45, &kernelContext_4);


        float3 n_1 = normalize(cross(_S44 - _S42, _S46 - _S42));

#line 132
        float3 n_2;
        if((dot(n_1, dir_0)) > 0.0f)
        {

#line 133
            n_2 = - n_1;

#line 133
        }
        else
        {

#line 133
            n_2 = n_1;

#line 133
        }


        float _S47 = ((&q_1)->get_committed_distance());

#line 136
        float3 p_1 = org_0 + dir_0 * float3(_S47)  + n_2 * float3(9.9999997473787516e-05f) ;

        uint mi_0 = (&kernelContext_4)->instances_0[inst_0 + 2U] * 8U;
        float3 albedo_0 = float3((&kernelContext_4)->materials_0[mi_0], (&kernelContext_4)->materials_0[mi_0 + 1U], (&kernelContext_4)->materials_0[mi_0 + 2U]);
        float3 radiance_2 = radiance_1 + thr_0 * float3((&kernelContext_4)->materials_0[mi_0 + 3U], (&kernelContext_4)->materials_0[mi_0 + 4U], (&kernelContext_4)->materials_0[mi_0 + 5U]);

#line 140
        uint li_0 = 0U;

#line 140
        radiance_0 = radiance_2;


        for(;;)
        {

#line 143
            if(li_0 < _S33)
            {
            }
            else
            {

#line 143
                break;
            }
            uint o_2 = li_0 * 8U;
            float3 col_0 = float3((as_type<float>(((&kernelContext_4)->lights_0[o_2 + 1U]))), (as_type<float>(((&kernelContext_4)->lights_0[o_2 + 2U]))), (as_type<float>(((&kernelContext_4)->lights_0[o_2 + 3U])))) * float3((as_type<float>(((&kernelContext_4)->lights_0[o_2 + 4U])))) ;
            float3 vec_0 = float3((as_type<float>(((&kernelContext_4)->lights_0[o_2 + 5U]))), (as_type<float>(((&kernelContext_4)->lights_0[o_2 + 6U]))), (as_type<float>(((&kernelContext_4)->lights_0[o_2 + 7U]))));

#line 147
            float3 wi_0;

#line 147
            float3 li_1;

#line 147
            float dist_0;



            if((&kernelContext_4)->lights_0[o_2] == 0U)
            {
                float3 toL_0 = vec_0 - p_1;
                float d2_0 = dot(toL_0, toL_0);
                float dist_1 = sqrt(d2_0);

                float3 _S48 = col_0 / float3(d2_0) ;

#line 157
                wi_0 = toL_0 / float3(dist_1) ;

#line 157
                dist_0 = dist_1;

#line 157
                li_1 = _S48;

#line 151
            }
            else
            {

#line 151
                wi_0 = - normalize(vec_0);

#line 151
                dist_0 = 1.00000001504746622e+30f;

#line 151
                li_1 = col_0;

#line 151
            }

#line 165
            float c_0 = dot(n_2, wi_0);
            if(c_0 > 0.0f)
            {

#line 166
                bool _S49 = occluded_0(p_1, wi_0, dist_0 - 0.0010000000474974513f, &kernelContext_4);

#line 166
                _S6 = !_S49;

#line 166
            }
            else
            {

#line 166
                _S6 = false;

#line 166
            }

#line 166
            if(_S6)
            {

#line 166
                radiance_0 = radiance_0 + thr_0 * albedo_0 * float3((c_0 / 3.1415927410125732f))  * li_1;

#line 166
            }

#line 143
            li_0 = li_0 + 1U;

#line 143
        }

#line 171
        org_0 = p_1;
        float _S50 = Rng_next_0(&rng_0);

#line 172
        float _S51 = Rng_next_0(&rng_0);

#line 172
        dir_0 = cosineHemisphere_0(n_2, _S50, _S51);
        float3 thr_1 = thr_0 * albedo_0;

        if(depth_0 >= 2U)
        {
            float pr_0 = clamp(max(thr_1.x, max(thr_1.y, thr_1.z)), 0.05000000074505806f, 0.94999998807907104f);
            float _S52 = Rng_next_0(&rng_0);

#line 178
            if(_S52 > pr_0)
            {

#line 179
                break;
            }

#line 179
            thr_0 = thr_1 / float3(pr_0) ;

#line 175
        }
        else
        {

#line 175
            thr_0 = thr_1;

#line 175
        }

#line 108
        depth_0 = depth_0 + 1U;

#line 108
        radiance_1 = radiance_0;

#line 108
    }

#line 184
    uint o_3 = 3U * pixel_0;
    float device* _S53 = (&kernelContext_4)->accum_0+o_3;

#line 185
    *_S53 = *_S53 + radiance_0.x;
    float device* _S54 = (&kernelContext_4)->accum_0+(o_3 + 1U);

#line 186
    *_S54 = *_S54 + radiance_0.y;
    float device* _S55 = (&kernelContext_4)->accum_0+(o_3 + 2U);

#line 187
    *_S55 = *_S55 + radiance_0.z;
    return;
}

