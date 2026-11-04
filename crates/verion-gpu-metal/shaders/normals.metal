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
            

#line 72 "shaders/normals.slang"
struct KernelContext_0
{
    float device* camera_0;
    metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_0;
    uint device* instances_0;
    uint device* indices_0;
    float device* positions_0;
    float device* output_0;
};


#line 11
float3 vertex_0(uint v_0, KernelContext_0 thread* kernelContext_0)
{

#line 11
    uint _S1 = 3U * v_0;

#line 11
    return float3(kernelContext_0->positions_0[_S1], kernelContext_0->positions_0[_S1 + 1U], kernelContext_0->positions_0[_S1 + 2U]);
}


#line 13
float3 transformPoint_0(uint device* buf_0, uint base_0, float3 p_0)
{
    thread float3 r_0;

#line 15
    uint row_0 = 0U;
    for(;;)
    {

#line 16
        if(row_0 < 3U)
        {
        }
        else
        {

#line 16
            break;
        }
        uint o_0 = base_0 + 4U * row_0;
        r_0[row_0] = (as_type<float>((buf_0[o_0]))) * p_0.x + (as_type<float>((buf_0[o_0 + 1U]))) * p_0.y + (as_type<float>((buf_0[o_0 + 2U]))) * p_0.z + (as_type<float>((buf_0[o_0 + 3U])));

#line 16
        row_0 = row_0 + 1U;

#line 16
    }

#line 21
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


#line 26 "shaders/normals.slang"
[[kernel]] void normals(uint3 tid_0 [[thread_position_in_grid]], float device* camera_1 [[buffer(4)]], metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_1 [[buffer(0)]], uint device* instances_1 [[buffer(3)]], uint device* indices_1 [[buffer(2)]], float device* positions_1 [[buffer(1)]], float device* output_1 [[buffer(5)]])
{

#line 26
    thread KernelContext_0 kernelContext_1;

#line 26
    (&kernelContext_1)->camera_0 = camera_1;

#line 26
    (&kernelContext_1)->scene_0 = scene_1;

#line 26
    (&kernelContext_1)->instances_0 = instances_1;

#line 26
    (&kernelContext_1)->indices_0 = indices_1;

#line 26
    (&kernelContext_1)->positions_0 = positions_1;

#line 26
    (&kernelContext_1)->output_0 = output_1;

    uint w_0 = uint(camera_1[int(0)]);
    uint h_0 = uint(camera_1[int(1)]);
    uint _S2 = tid_0.x;

#line 30
    bool _S3;

#line 30
    if(_S2 >= w_0)
    {

#line 30
        _S3 = true;

#line 30
    }
    else
    {

#line 30
        _S3 = (tid_0.y) >= h_0;

#line 30
    }

#line 30
    if(_S3)
    {

#line 31
        return;
    }
    float t_0 = (&kernelContext_1)->camera_0[int(2)];


    uint _S4 = tid_0.y;
    float3 _S5 = normalize(float3((2.0f * (float(_S2) + 0.5f) / float(w_0) - 1.0f) * ((&kernelContext_1)->camera_0[int(0)] / (&kernelContext_1)->camera_0[int(1)]) * t_0, (1.0f - 2.0f * (float(_S4) + 0.5f) / float(h_0)) * t_0, -1.0f));


    thread float3 dir_0;

#line 40
    thread float3 org_0;

#line 40
    uint r_1 = 0U;
    for(;;)
    {

#line 41
        if(r_1 < 3U)
        {
        }
        else
        {

#line 41
            break;
        }
        uint _S6 = 4U * r_1;

#line 43
        dir_0[r_1] = (&kernelContext_1)->camera_0[4U + _S6] * _S5.x + (&kernelContext_1)->camera_0[5U + _S6] * _S5.y + (&kernelContext_1)->camera_0[6U + _S6] * _S5.z;
        org_0[r_1] = (&kernelContext_1)->camera_0[7U + _S6];

#line 41
        r_1 = r_1 + 1U;

#line 41
    }

#line 47
    thread RayDesc_0 ray_0;
    (&ray_0)->Origin_0 = org_0;
    (&ray_0)->Direction_0 = normalize(dir_0);
    (&ray_0)->TMin_0 = 0.0f;
    (&ray_0)->TMax_0 = 1.00000001504746622e+30f;

    thread raytracing::intersection_query<raytracing::triangle_data, raytracing::instancing> q_0;
    (&q_0)->reset({ (ray_0.Origin_0), (ray_0.Direction_0), (ray_0.TMin_0), (ray_0.TMax_0) }, ((&kernelContext_1)->scene_0), (255U), _slang_ray_flags_to_intersection_params((1U)));
    for(;;)
    {

#line 55
        bool _S7 = ((&q_0)->next());

#line 55
        if(_S7)
        {
        }
        else
        {

#line 55
            break;
        }

#line 55
    }

    float3 _S8 = float3(0.0f) ;
    uint _S9 = (_slang_committed_intersection_type_to_uint((&q_0)->get_committed_intersection_type()));

#line 58
    float3 n_0;

#line 58
    if(_S9 == 1U)
    {
        uint _S10 = ((&q_0)->get_committed_instance_id());

#line 60
        uint inst_0 = _S10 * 16U;
        uint _S11 = (&kernelContext_1)->instances_0[inst_0 + 1U];

#line 61
        uint _S12 = ((&q_0)->get_committed_primitive_id());

#line 61
        uint tri_0 = _S11 + 3U * _S12;
        uint vo_0 = (&kernelContext_1)->instances_0[inst_0];
        uint _S13 = inst_0 + 4U;

#line 63
        float3 _S14 = vertex_0((&kernelContext_1)->indices_0[tri_0] + vo_0, &kernelContext_1);

#line 63
        float3 p0_0 = transformPoint_0((&kernelContext_1)->instances_0, _S13, _S14);

#line 63
        float3 _S15 = vertex_0((&kernelContext_1)->indices_0[tri_0 + 1U] + vo_0, &kernelContext_1);
        float3 p1_0 = transformPoint_0((&kernelContext_1)->instances_0, _S13, _S15);

#line 64
        float3 _S16 = vertex_0((&kernelContext_1)->indices_0[tri_0 + 2U] + vo_0, &kernelContext_1);

        float3 n_1 = normalize(cross(p1_0 - p0_0, transformPoint_0((&kernelContext_1)->instances_0, _S13, _S16) - p0_0));
        if((dot(n_1, (&ray_0)->Direction_0)) > 0.0f)
        {

#line 67
            n_0 = - n_1;

#line 67
        }
        else
        {

#line 67
            n_0 = n_1;

#line 67
        }

#line 58
    }
    else
    {

#line 58
        n_0 = _S8;

#line 58
    }

#line 71
    uint o_1 = 3U * (_S4 * w_0 + _S2);
    *((&kernelContext_1)->output_0+o_1) = n_0.x;
    *((&kernelContext_1)->output_0+(o_1 + 1U)) = n_0.y;
    *((&kernelContext_1)->output_0+(o_1 + 2U)) = n_0.z;
    return;
}

