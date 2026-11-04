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
            

#line 107 "shaders/normals.slang"
struct KernelContext_0
{
    float device* camera_0;
    metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_0;
    uint device* instances_0;
    uint device* indices_0;
    float device* positions_0;
    float device* vnormals_0;
    float device* output_0;
};


#line 13
float3 vertex_0(uint v_0, KernelContext_0 thread* kernelContext_0)
{

#line 13
    uint _S1 = 3U * v_0;

#line 13
    return float3(kernelContext_0->positions_0[_S1], kernelContext_0->positions_0[_S1 + 1U], kernelContext_0->positions_0[_S1 + 2U]);
}


#line 28
float3 transformPoint_0(uint device* buf_0, uint base_0, float3 p_0)
{
    thread float3 r_0;

#line 30
    uint row_0 = 0U;
    for(;;)
    {

#line 31
        if(row_0 < 3U)
        {
        }
        else
        {

#line 31
            break;
        }
        uint o_0 = base_0 + 4U * row_0;
        r_0[row_0] = (as_type<float>((buf_0[o_0]))) * p_0.x + (as_type<float>((buf_0[o_0 + 1U]))) * p_0.y + (as_type<float>((buf_0[o_0 + 2U]))) * p_0.z + (as_type<float>((buf_0[o_0 + 3U])));

#line 31
        row_0 = row_0 + 1U;

#line 31
    }

#line 36
    return r_0;
}


#line 26
float3 vertexNormal_0(uint v_1, KernelContext_0 thread* kernelContext_1)
{

#line 26
    uint _S2 = 3U * v_1;

#line 26
    return float3(kernelContext_1->vnormals_0[_S2], kernelContext_1->vnormals_0[_S2 + 1U], kernelContext_1->vnormals_0[_S2 + 2U]);
}


#line 16
float3 transformNormal_0(uint base_1, float3 n_0, KernelContext_0 thread* kernelContext_2)
{
    float3 r0_0 = float3((as_type<float>((kernelContext_2->instances_0[base_1]))), (as_type<float>((kernelContext_2->instances_0[base_1 + 1U]))), (as_type<float>((kernelContext_2->instances_0[base_1 + 2U]))));
    float3 r1_0 = float3((as_type<float>((kernelContext_2->instances_0[base_1 + 4U]))), (as_type<float>((kernelContext_2->instances_0[base_1 + 5U]))), (as_type<float>((kernelContext_2->instances_0[base_1 + 6U]))));
    float3 r2_0 = float3((as_type<float>((kernelContext_2->instances_0[base_1 + 8U]))), (as_type<float>((kernelContext_2->instances_0[base_1 + 9U]))), (as_type<float>((kernelContext_2->instances_0[base_1 + 10U]))));
    float3 c0_0 = cross(r1_0, r2_0);

#line 21
    float s_0;
    if((dot(r0_0, c0_0)) < 0.0f)
    {

#line 22
        s_0 = -1.0f;

#line 22
    }
    else
    {

#line 22
        s_0 = 1.0f;

#line 22
    }
    return float3(s_0)  * float3(dot(c0_0, n_0), dot(cross(r2_0, r0_0), n_0), dot(cross(r0_0, r1_0), n_0));
}


#line 20995 "hlsl.meta.slang"
struct RayDesc_0
{
    float3 Origin_0;
    float TMin_0;
    float3 Direction_0;
    float TMax_0;
};


#line 41 "shaders/normals.slang"
[[kernel]] void normals(uint3 tid_0 [[thread_position_in_grid]], float device* camera_1 [[buffer(4)]], metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_1 [[buffer(0)]], uint device* instances_1 [[buffer(3)]], uint device* indices_1 [[buffer(2)]], float device* positions_1 [[buffer(1)]], float device* vnormals_1 [[buffer(6)]], float device* output_1 [[buffer(5)]])
{

#line 41
    thread KernelContext_0 kernelContext_3;

#line 41
    (&kernelContext_3)->camera_0 = camera_1;

#line 41
    (&kernelContext_3)->scene_0 = scene_1;

#line 41
    (&kernelContext_3)->instances_0 = instances_1;

#line 41
    (&kernelContext_3)->indices_0 = indices_1;

#line 41
    (&kernelContext_3)->positions_0 = positions_1;

#line 41
    (&kernelContext_3)->vnormals_0 = vnormals_1;

#line 41
    (&kernelContext_3)->output_0 = output_1;

    uint w_0 = uint(camera_1[int(0)]);
    uint h_0 = uint(camera_1[int(1)]);
    uint _S3 = tid_0.x;

#line 45
    bool _S4;

#line 45
    if(_S3 >= w_0)
    {

#line 45
        _S4 = true;

#line 45
    }
    else
    {

#line 45
        _S4 = (tid_0.y) >= h_0;

#line 45
    }

#line 45
    if(_S4)
    {

#line 46
        return;
    }
    float t_0 = (&kernelContext_3)->camera_0[int(2)];


    uint _S5 = tid_0.y;
    float3 _S6 = normalize(float3((2.0f * (float(_S3) + 0.5f) / float(w_0) - 1.0f) * ((&kernelContext_3)->camera_0[int(0)] / (&kernelContext_3)->camera_0[int(1)]) * t_0, (1.0f - 2.0f * (float(_S5) + 0.5f) / float(h_0)) * t_0, -1.0f));


    thread float3 dir_0;

#line 55
    thread float3 org_0;

#line 55
    uint r_1 = 0U;
    for(;;)
    {

#line 56
        if(r_1 < 3U)
        {
        }
        else
        {

#line 56
            break;
        }
        uint _S7 = 4U * r_1;

#line 58
        dir_0[r_1] = (&kernelContext_3)->camera_0[4U + _S7] * _S6.x + (&kernelContext_3)->camera_0[5U + _S7] * _S6.y + (&kernelContext_3)->camera_0[6U + _S7] * _S6.z;
        org_0[r_1] = (&kernelContext_3)->camera_0[7U + _S7];

#line 56
        r_1 = r_1 + 1U;

#line 56
    }

#line 62
    thread RayDesc_0 ray_0;
    (&ray_0)->Origin_0 = org_0;
    (&ray_0)->Direction_0 = normalize(dir_0);
    (&ray_0)->TMin_0 = 0.0f;
    (&ray_0)->TMax_0 = 1.00000001504746622e+30f;

    thread raytracing::intersection_query<raytracing::triangle_data, raytracing::instancing> q_0;
    (&q_0)->reset({ (ray_0.Origin_0), (ray_0.Direction_0), (ray_0.TMin_0), (ray_0.TMax_0) }, ((&kernelContext_3)->scene_0), (255U), _slang_ray_flags_to_intersection_params((1U)));
    for(;;)
    {

#line 70
        bool _S8 = ((&q_0)->next());

#line 70
        if(_S8)
        {
        }
        else
        {

#line 70
            break;
        }

#line 70
    }

    float3 _S9 = float3(0.0f) ;
    uint _S10 = (_slang_committed_intersection_type_to_uint((&q_0)->get_committed_intersection_type()));

#line 73
    float3 n_1;

#line 73
    if(_S10 == 1U)
    {
        uint _S11 = ((&q_0)->get_committed_instance_id());

#line 75
        uint inst_0 = _S11 * 16U;
        uint _S12 = (&kernelContext_3)->instances_0[inst_0 + 1U];

#line 76
        uint _S13 = ((&q_0)->get_committed_primitive_id());

#line 76
        uint tri_0 = _S12 + 3U * _S13;
        uint vo_0 = (&kernelContext_3)->instances_0[inst_0];
        uint _S14 = inst_0 + 4U;

#line 78
        float3 _S15 = vertex_0((&kernelContext_3)->indices_0[tri_0] + vo_0, &kernelContext_3);

#line 78
        float3 p0_0 = transformPoint_0((&kernelContext_3)->instances_0, _S14, _S15);
        uint _S16 = tri_0 + 1U;

#line 79
        float3 _S17 = vertex_0((&kernelContext_3)->indices_0[_S16] + vo_0, &kernelContext_3);

#line 79
        float3 p1_0 = transformPoint_0((&kernelContext_3)->instances_0, _S14, _S17);
        uint _S18 = tri_0 + 2U;

#line 80
        float3 _S19 = vertex_0((&kernelContext_3)->indices_0[_S18] + vo_0, &kernelContext_3);
        float3 _S20 = p1_0 - p0_0;

#line 81
        float3 _S21 = transformPoint_0((&kernelContext_3)->instances_0, _S14, _S19) - p0_0;

#line 81
        float3 ng_0 = normalize(cross(_S20, _S21));

#line 88
        float _S22 = ((&q_0)->get_committed_distance());

#line 88
        float3 e3_0 = org_0 + (&ray_0)->Direction_0 * float3(_S22)  - p0_0;
        float d11_0 = dot(_S20, _S20);
        float d12_0 = dot(_S20, _S21);
        float d22_0 = dot(_S21, _S21);
        float _S23 = max(d11_0 * d22_0 - d12_0 * d12_0, 9.99999968265522539e-21f);
        float _S24 = dot(e3_0, _S20);

#line 93
        float _S25 = dot(e3_0, _S21);

#line 93
        float b1_0 = (d22_0 * _S24 - d12_0 * _S25) / _S23;
        float b2_0 = (d11_0 * _S25 - d12_0 * _S24) / _S23;
        float _S26 = 1.0f - b1_0 - b2_0;

#line 95
        float3 _S27 = vertexNormal_0((&kernelContext_3)->indices_0[tri_0] + vo_0, &kernelContext_3);

#line 95
        float3 _S28 = float3(_S26)  * _S27;

#line 95
        float3 _S29 = vertexNormal_0((&kernelContext_3)->indices_0[_S16] + vo_0, &kernelContext_3);

#line 95
        float3 _S30 = _S28 + float3(b1_0)  * _S29;

#line 95
        float3 _S31 = vertexNormal_0((&kernelContext_3)->indices_0[_S18] + vo_0, &kernelContext_3);

#line 95
        float3 nsObj_0 = _S30 + float3(b2_0)  * _S31;
        if((dot(nsObj_0, nsObj_0)) > 9.999999960041972e-13f)
        {

#line 96
            float3 _S32 = transformNormal_0(_S14, nsObj_0, &kernelContext_3);

            float3 n_2 = normalize(_S32);
            if((dot(n_2, ng_0)) < 0.0f)
            {

#line 99
                n_1 = - n_2;

#line 99
            }
            else
            {

#line 99
                n_1 = n_2;

#line 99
            }

#line 96
        }
        else
        {

#line 96
            n_1 = ng_0;

#line 96
        }

#line 102
        if((dot(ng_0, (&ray_0)->Direction_0)) > 0.0f)
        {

#line 102
            n_1 = - n_1;

#line 102
        }

#line 73
    }
    else
    {

#line 73
        n_1 = _S9;

#line 73
    }

#line 106
    uint o_1 = 3U * (_S5 * w_0 + _S3);
    *((&kernelContext_3)->output_0+o_1) = n_1.x;
    *((&kernelContext_3)->output_0+(o_1 + 1U)) = n_1.y;
    *((&kernelContext_3)->output_0+(o_1 + 2U)) = n_1.z;
    return;
}

