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
            

#line 17 "shaders/aov.slang"
struct KernelContext_0
{
    float device* camera_0;
    metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_0;
    uint device* instances_0;
    float device* materials_0;
    uint device* indices_0;
    float device* positions_0;
    float device* uvs_0;
    uint device* texInfo_0;
    float device* texels_0;
    float device* albedoDepth_0;
    uint device* objectIds_0;
    uint device* materialIds_0;
};


#line 19
float3 vertex_0(uint v_0, KernelContext_0 thread* kernelContext_0)
{

#line 19
    uint _S1 = 3U * v_0;

#line 19
    return float3(kernelContext_0->positions_0[_S1], kernelContext_0->positions_0[_S1 + 1U], kernelContext_0->positions_0[_S1 + 2U]);
}


#line 21
float3 transformPoint_0(uint device* buf_0, uint base_0, float3 p_0)
{
    thread float3 r_0;

#line 23
    uint row_0 = 0U;
    for(;;)
    {

#line 24
        if(row_0 < 3U)
        {
        }
        else
        {

#line 24
            break;
        }
        uint o_0 = base_0 + 4U * row_0;
        r_0[row_0] = (as_type<float>((buf_0[o_0]))) * p_0.x + (as_type<float>((buf_0[o_0 + 1U]))) * p_0.y + (as_type<float>((buf_0[o_0 + 2U]))) * p_0.z + (as_type<float>((buf_0[o_0 + 3U])));

#line 24
        row_0 = row_0 + 1U;

#line 24
    }

#line 29
    return r_0;
}

float3 texelAt_0(uint base_1, uint w_0, uint h_0, int x_0, int y_0, KernelContext_0 thread* kernelContext_1)
{
    int _S2 = int(w_0);

#line 34
    int _S3 = x_0 % _S2;

#line 34
    int _S4 = (_S3 + _S2) % _S2;

#line 34
    uint xi_0 = uint(_S4);
    int _S5 = int(h_0);

#line 35
    int _S6 = y_0 % _S5;

#line 35
    int _S7 = (_S6 + _S5) % _S5;
    uint o_1 = 3U * (base_1 + uint(_S7) * w_0 + xi_0);
    return float3(kernelContext_1->texels_0[o_1], kernelContext_1->texels_0[o_1 + 1U], kernelContext_1->texels_0[o_1 + 2U]);
}

float3 bilinear_0(uint base_2, uint w_1, uint h_1, float2 uv_0, KernelContext_0 thread* kernelContext_2)
{
    float fx_0 = uv_0.x * float(w_1) - 0.5f;
    float fy_0 = uv_0.y * float(h_1) - 0.5f;
    int x0_0 = int(floor(fx_0));
    int y0_0 = int(floor(fy_0));
    float tx_0 = fx_0 - float(x0_0);
    float ty_0 = fy_0 - float(y0_0);

#line 47
    float3 _S8 = texelAt_0(base_2, w_1, h_1, x0_0, y0_0, kernelContext_2);
    int _S9 = x0_0 + int(1);

#line 48
    float3 _S10 = texelAt_0(base_2, w_1, h_1, _S9, y0_0, kernelContext_2);

#line 48
    float3 _S11 = float3(tx_0) ;

#line 48
    float3 a_0 = mix(_S8, _S10, _S11);
    int _S12 = y0_0 + int(1);

#line 49
    float3 _S13 = texelAt_0(base_2, w_1, h_1, x0_0, _S12, kernelContext_2);

#line 49
    float3 _S14 = texelAt_0(base_2, w_1, h_1, _S9, _S12, kernelContext_2);
    return mix(a_0, mix(_S13, _S14, _S11), float3(ty_0) );
}


#line 20995 "hlsl.meta.slang"
struct RayDesc_0
{
    float3 Origin_0;
    float TMin_0;
    float3 Direction_0;
    float TMax_0;
};


#line 55 "shaders/aov.slang"
[[kernel]] void aov(uint3 tid_0 [[thread_position_in_grid]], float device* camera_1 [[buffer(4)]], metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_1 [[buffer(0)]], uint device* instances_1 [[buffer(3)]], float device* materials_1 [[buffer(5)]], uint device* indices_1 [[buffer(2)]], float device* positions_1 [[buffer(1)]], float device* uvs_1 [[buffer(6)]], uint device* texInfo_1 [[buffer(7)]], float device* texels_1 [[buffer(8)]], float device* albedoDepth_1 [[buffer(9)]], uint device* objectIds_1 [[buffer(10)]], uint device* materialIds_1 [[buffer(11)]])
{

#line 55
    thread KernelContext_0 kernelContext_3;

#line 55
    (&kernelContext_3)->camera_0 = camera_1;

#line 55
    (&kernelContext_3)->scene_0 = scene_1;

#line 55
    (&kernelContext_3)->instances_0 = instances_1;

#line 55
    (&kernelContext_3)->materials_0 = materials_1;

#line 55
    (&kernelContext_3)->indices_0 = indices_1;

#line 55
    (&kernelContext_3)->positions_0 = positions_1;

#line 55
    (&kernelContext_3)->uvs_0 = uvs_1;

#line 55
    (&kernelContext_3)->texInfo_0 = texInfo_1;

#line 55
    (&kernelContext_3)->texels_0 = texels_1;

#line 55
    (&kernelContext_3)->albedoDepth_0 = albedoDepth_1;

#line 55
    (&kernelContext_3)->objectIds_0 = objectIds_1;

#line 55
    (&kernelContext_3)->materialIds_0 = materialIds_1;

    uint w_2 = uint(camera_1[int(0)]);
    uint h_2 = uint(camera_1[int(1)]);
    uint _S15 = tid_0.x;

#line 59
    bool _S16;

#line 59
    if(_S15 >= w_2)
    {

#line 59
        _S16 = true;

#line 59
    }
    else
    {

#line 59
        _S16 = (tid_0.y) >= h_2;

#line 59
    }

#line 59
    if(_S16)
    {

#line 60
        return;
    }
    float t_0 = (&kernelContext_3)->camera_0[int(2)];


    uint _S17 = tid_0.y;
    float3 d_0 = normalize(float3((2.0f * (float(_S15) + 0.5f) / float(w_2) - 1.0f) * ((&kernelContext_3)->camera_0[int(0)] / (&kernelContext_3)->camera_0[int(1)]) * t_0, (1.0f - 2.0f * (float(_S17) + 0.5f) / float(h_2)) * t_0, -1.0f));

    thread float3 dir_0;

#line 68
    thread float3 org_0;

#line 68
    uint r_1 = 0U;
    for(;;)
    {

#line 69
        if(r_1 < 3U)
        {
        }
        else
        {

#line 69
            break;
        }
        uint _S18 = 4U * r_1;

#line 71
        dir_0[r_1] = (&kernelContext_3)->camera_0[4U + _S18] * d_0.x + (&kernelContext_3)->camera_0[5U + _S18] * d_0.y + (&kernelContext_3)->camera_0[6U + _S18] * d_0.z;
        org_0[r_1] = (&kernelContext_3)->camera_0[7U + _S18];

#line 69
        r_1 = r_1 + 1U;

#line 69
    }

#line 75
    thread RayDesc_0 ray_0;
    (&ray_0)->Origin_0 = org_0;
    (&ray_0)->Direction_0 = normalize(dir_0);
    (&ray_0)->TMin_0 = 0.0f;
    (&ray_0)->TMax_0 = 1.00000001504746622e+30f;

    thread raytracing::intersection_query<raytracing::triangle_data, raytracing::instancing> q_0;
    (&q_0)->reset({ (ray_0.Origin_0), (ray_0.Direction_0), (ray_0.TMin_0), (ray_0.TMax_0) }, ((&kernelContext_3)->scene_0), (255U), _slang_ray_flags_to_intersection_params((1U)));
    for(;;)
    {

#line 83
        bool _S19 = ((&q_0)->next());

#line 83
        if(_S19)
        {
        }
        else
        {

#line 83
            break;
        }

#line 83
    }

    float3 _S20 = float3(0.0f) ;



    uint _S21 = (_slang_committed_intersection_type_to_uint((&q_0)->get_committed_intersection_type()));

#line 89
    uint id_0;

#line 89
    uint matId_0;

#line 89
    float3 albedo_0;

#line 89
    float depth_0;

#line 89
    if(_S21 == 1U)
    {
        uint instance_0 = ((&q_0)->get_committed_instance_id());
        uint inst_0 = instance_0 * 16U;
        uint _S22 = (&kernelContext_3)->instances_0[inst_0 + 1U];

#line 93
        uint _S23 = ((&q_0)->get_committed_primitive_id());

#line 93
        uint tri_0 = _S22 + 3U * _S23;
        uint vo_0 = (&kernelContext_3)->instances_0[inst_0];
        uint _S24 = instance_0 + 1U;
        uint _S25 = inst_0 + 2U;

#line 96
        uint _S26 = (&kernelContext_3)->instances_0[_S25] + 1U;
        float _S27 = ((&q_0)->get_committed_distance());

#line 97
        float _S28 = _S27 * - d_0.z;

        uint mi_0 = (&kernelContext_3)->instances_0[_S25] * 16U;
        float3 albedo_1 = float3((&kernelContext_3)->materials_0[mi_0], (&kernelContext_3)->materials_0[mi_0 + 1U], (&kernelContext_3)->materials_0[mi_0 + 2U]);
        uint texBase_0 = uint((&kernelContext_3)->materials_0[mi_0 + 10U]);
        if(texBase_0 > 0U)
        {
            uint _S29 = inst_0 + 4U;

#line 104
            float3 _S30 = vertex_0((&kernelContext_3)->indices_0[tri_0] + vo_0, &kernelContext_3);

#line 104
            float3 p0_0 = transformPoint_0((&kernelContext_3)->instances_0, _S29, _S30);
            uint _S31 = tri_0 + 1U;

#line 105
            float3 _S32 = vertex_0((&kernelContext_3)->indices_0[_S31] + vo_0, &kernelContext_3);

#line 105
            float3 p1_0 = transformPoint_0((&kernelContext_3)->instances_0, _S29, _S32);
            uint _S33 = tri_0 + 2U;

#line 106
            float3 _S34 = vertex_0((&kernelContext_3)->indices_0[_S33] + vo_0, &kernelContext_3);
            float3 e1_0 = p1_0 - p0_0;
            float3 e2_0 = transformPoint_0((&kernelContext_3)->instances_0, _S29, _S34) - p0_0;
            float _S35 = ((&q_0)->get_committed_distance());

#line 109
            float3 e3_0 = org_0 + (&ray_0)->Direction_0 * float3(_S35)  - p0_0;
            float d11_0 = dot(e1_0, e1_0);
            float d12_0 = dot(e1_0, e2_0);
            float d22_0 = dot(e2_0, e2_0);
            float _S36 = max(d11_0 * d22_0 - d12_0 * d12_0, 9.99999968265522539e-21f);
            float _S37 = dot(e3_0, e1_0);

#line 114
            float _S38 = dot(e3_0, e2_0);

            float2 uv0_0 = float2((&kernelContext_3)->uvs_0[2U * ((&kernelContext_3)->indices_0[tri_0] + vo_0)], (&kernelContext_3)->uvs_0[2U * ((&kernelContext_3)->indices_0[tri_0] + vo_0) + 1U]);



            uint ti_0 = (texBase_0 - 1U) * 4U;

#line 120
            float3 _S39 = bilinear_0((&kernelContext_3)->texInfo_0[ti_0], (&kernelContext_3)->texInfo_0[ti_0 + 1U], (&kernelContext_3)->texInfo_0[ti_0 + 2U], uv0_0 + float2(((d22_0 * _S37 - d12_0 * _S38) / _S36))  * (float2((&kernelContext_3)->uvs_0[2U * ((&kernelContext_3)->indices_0[_S31] + vo_0)], (&kernelContext_3)->uvs_0[2U * ((&kernelContext_3)->indices_0[_S31] + vo_0) + 1U]) - uv0_0) + float2(((d11_0 * _S38 - d12_0 * _S37) / _S36))  * (float2((&kernelContext_3)->uvs_0[2U * ((&kernelContext_3)->indices_0[_S33] + vo_0)], (&kernelContext_3)->uvs_0[2U * ((&kernelContext_3)->indices_0[_S33] + vo_0) + 1U]) - uv0_0), &kernelContext_3);

#line 120
            albedo_0 = albedo_1 * _S39;

#line 102
        }
        else
        {

#line 102
            albedo_0 = albedo_1;

#line 102
        }

#line 102
        depth_0 = _S28;

#line 102
        id_0 = _S24;

#line 102
        matId_0 = _S26;

#line 89
    }
    else
    {

#line 89
        depth_0 = 0.0f;

#line 89
        id_0 = 0U;

#line 89
        matId_0 = 0U;

#line 89
        albedo_0 = _S20;

#line 89
    }

#line 125
    uint pixel_0 = _S17 * w_2 + _S15;
    uint _S40 = 4U * pixel_0;

#line 126
    *((&kernelContext_3)->albedoDepth_0+_S40) = albedo_0.x;
    *((&kernelContext_3)->albedoDepth_0+(_S40 + 1U)) = albedo_0.y;
    *((&kernelContext_3)->albedoDepth_0+(_S40 + 2U)) = albedo_0.z;
    *((&kernelContext_3)->albedoDepth_0+(_S40 + 3U)) = depth_0;
    *((&kernelContext_3)->objectIds_0+pixel_0) = id_0;
    *((&kernelContext_3)->materialIds_0+pixel_0) = matId_0;
    return;
}

