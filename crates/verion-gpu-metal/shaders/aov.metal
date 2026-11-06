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
    float device* coverage_0;
    float device* albedoDepth_0;
    uint device* objectIds_0;
    uint device* materialIds_0;
};


#line 55
float3 pixelDir_0(float2 px_0, uint w_0, uint h_0, float t_0, float aspect_0, float3 thread* dir_0, KernelContext_0 thread* kernelContext_0)
{


    float3 d_0 = normalize(float3((2.0f * px_0.x / float(w_0) - 1.0f + kernelContext_0->camera_0[int(16)]) * aspect_0 * t_0, (1.0f - 2.0f * px_0.y / float(h_0) + kernelContext_0->camera_0[int(17)]) * t_0, -1.0f));

#line 59
    uint r_0 = 0U;
    for(;;)
    {

#line 60
        if(r_0 < 3U)
        {
        }
        else
        {

#line 60
            break;
        }

#line 61
        uint _S1 = 4U * r_0;

#line 61
        (*dir_0)[r_0] = kernelContext_0->camera_0[4U + _S1] * d_0.x + kernelContext_0->camera_0[5U + _S1] * d_0.y + kernelContext_0->camera_0[6U + _S1] * d_0.z;

#line 60
        r_0 = r_0 + 1U;

#line 60
    }

    return d_0;
}


#line 20
float3 vertex_0(uint v_0, KernelContext_0 thread* kernelContext_1)
{

#line 20
    uint _S2 = 3U * v_0;

#line 20
    return float3(kernelContext_1->positions_0[_S2], kernelContext_1->positions_0[_S2 + 1U], kernelContext_1->positions_0[_S2 + 2U]);
}


#line 22
float3 transformPoint_0(uint device* buf_0, uint base_0, float3 p_0)
{
    thread float3 r_1;

#line 24
    uint row_0 = 0U;
    for(;;)
    {

#line 25
        if(row_0 < 3U)
        {
        }
        else
        {

#line 25
            break;
        }
        uint o_0 = base_0 + 4U * row_0;
        r_1[row_0] = (as_type<float>((buf_0[o_0]))) * p_0.x + (as_type<float>((buf_0[o_0 + 1U]))) * p_0.y + (as_type<float>((buf_0[o_0 + 2U]))) * p_0.z + (as_type<float>((buf_0[o_0 + 3U])));

#line 25
        row_0 = row_0 + 1U;

#line 25
    }

#line 30
    return r_1;
}

float3 texelAt_0(uint base_1, uint w_1, uint h_1, int x_0, int y_0, KernelContext_0 thread* kernelContext_2)
{
    int _S3 = int(w_1);

#line 35
    int _S4 = x_0 % _S3;

#line 35
    int _S5 = (_S4 + _S3) % _S3;

#line 35
    uint xi_0 = uint(_S5);
    int _S6 = int(h_1);

#line 36
    int _S7 = y_0 % _S6;

#line 36
    int _S8 = (_S7 + _S6) % _S6;
    uint o_1 = 3U * (base_1 + uint(_S8) * w_1 + xi_0);
    return float3(kernelContext_2->texels_0[o_1], kernelContext_2->texels_0[o_1 + 1U], kernelContext_2->texels_0[o_1 + 2U]);
}

float3 bilinear_0(uint base_2, uint w_2, uint h_2, float2 uv_0, KernelContext_0 thread* kernelContext_3)
{
    float fx_0 = uv_0.x * float(w_2) - 0.5f;
    float fy_0 = uv_0.y * float(h_2) - 0.5f;
    int x0_0 = int(floor(fx_0));
    int y0_0 = int(floor(fy_0));
    float tx_0 = fx_0 - float(x0_0);
    float ty_0 = fy_0 - float(y0_0);

#line 48
    float3 _S9 = texelAt_0(base_2, w_2, h_2, x0_0, y0_0, kernelContext_3);
    int _S10 = x0_0 + int(1);

#line 49
    float3 _S11 = texelAt_0(base_2, w_2, h_2, _S10, y0_0, kernelContext_3);

#line 49
    float3 _S12 = float3(tx_0) ;

#line 49
    float3 a_0 = mix(_S9, _S11, _S12);
    int _S13 = y0_0 + int(1);

#line 50
    float3 _S14 = texelAt_0(base_2, w_2, h_2, x0_0, _S13, kernelContext_3);

#line 50
    float3 _S15 = texelAt_0(base_2, w_2, h_2, _S10, _S13, kernelContext_3);
    return mix(a_0, mix(_S14, _S15, _S12), float3(ty_0) );
}


#line 20995 "hlsl.meta.slang"
struct RayDesc_0
{
    float3 Origin_0;
    float TMin_0;
    float3 Direction_0;
    float TMax_0;
};


#line 67 "shaders/aov.slang"
[[kernel]] void aov(uint3 tid_0 [[thread_position_in_grid]], float device* camera_1 [[buffer(4)]], metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_1 [[buffer(0)]], uint device* instances_1 [[buffer(3)]], float device* materials_1 [[buffer(5)]], uint device* indices_1 [[buffer(2)]], float device* positions_1 [[buffer(1)]], float device* uvs_1 [[buffer(6)]], uint device* texInfo_1 [[buffer(7)]], float device* texels_1 [[buffer(8)]], float device* coverage_1 [[buffer(12)]], float device* albedoDepth_1 [[buffer(9)]], uint device* objectIds_1 [[buffer(10)]], uint device* materialIds_1 [[buffer(11)]])
{

#line 67
    thread KernelContext_0 kernelContext_4;

#line 67
    (&kernelContext_4)->camera_0 = camera_1;

#line 67
    (&kernelContext_4)->scene_0 = scene_1;

#line 67
    (&kernelContext_4)->instances_0 = instances_1;

#line 67
    (&kernelContext_4)->materials_0 = materials_1;

#line 67
    (&kernelContext_4)->indices_0 = indices_1;

#line 67
    (&kernelContext_4)->positions_0 = positions_1;

#line 67
    (&kernelContext_4)->uvs_0 = uvs_1;

#line 67
    (&kernelContext_4)->texInfo_0 = texInfo_1;

#line 67
    (&kernelContext_4)->texels_0 = texels_1;

#line 67
    (&kernelContext_4)->coverage_0 = coverage_1;

#line 67
    (&kernelContext_4)->albedoDepth_0 = albedoDepth_1;

#line 67
    (&kernelContext_4)->objectIds_0 = objectIds_1;

#line 67
    (&kernelContext_4)->materialIds_0 = materialIds_1;

    uint w_3 = uint(camera_1[int(0)]);
    uint h_3 = uint(camera_1[int(1)]);
    uint _S16 = tid_0.x;

#line 71
    bool _S17;

#line 71
    if(_S16 >= w_3)
    {

#line 71
        _S17 = true;

#line 71
    }
    else
    {

#line 71
        _S17 = (tid_0.y) >= h_3;

#line 71
    }

#line 71
    if(_S17)
    {

#line 72
        return;
    }
    float t_1 = (&kernelContext_4)->camera_0[int(2)];
    float aspect_1 = (&kernelContext_4)->camera_0[int(0)] / (&kernelContext_4)->camera_0[int(1)];
    float _S18 = float(_S16);

#line 76
    uint _S19 = tid_0.y;

#line 76
    float _S20 = float(_S19);

#line 76
    float2 px_1 = float2(_S18 + 0.5f, _S20 + 0.5f);


    thread RayDesc_0 ray_0;
    (&ray_0)->TMin_0 = 0.0f;
    (&ray_0)->TMax_0 = 1.00000001504746622e+30f;
    float3 org_0 = float3((&kernelContext_4)->camera_0[int(7)], (&kernelContext_4)->camera_0[int(11)], (&kernelContext_4)->camera_0[int(15)]);

#line 78
    thread float3 dir_1;

#line 78
    float3 _S21 = pixelDir_0(px_1, w_3, h_3, t_1, aspect_1, &dir_1, &kernelContext_4);

#line 84
    (&ray_0)->Origin_0 = org_0;
    (&ray_0)->Direction_0 = normalize(dir_1);

    thread raytracing::intersection_query<raytracing::triangle_data, raytracing::instancing> q_0;
    (&q_0)->reset({ (ray_0.Origin_0), (ray_0.Direction_0), (ray_0.TMin_0), (ray_0.TMax_0) }, ((&kernelContext_4)->scene_0), (255U), _slang_ray_flags_to_intersection_params((1U)));
    for(;;)
    {

#line 89
        bool _S22 = ((&q_0)->next());

#line 89
        if(_S22)
        {
        }
        else
        {

#line 89
            break;
        }

#line 89
    }

    float3 _S23 = float3(0.0f) ;



    uint _S24 = (_slang_committed_intersection_type_to_uint((&q_0)->get_committed_intersection_type()));

#line 95
    float3 albedo_0;

#line 95
    float depth_0;

#line 95
    uint id_0;

#line 95
    uint matId_0;

#line 95
    if(_S24 == 1U)
    {
        uint instance_0 = ((&q_0)->get_committed_instance_id());
        uint inst_0 = instance_0 * 16U;
        uint _S25 = (&kernelContext_4)->instances_0[inst_0 + 1U];

#line 99
        uint _S26 = ((&q_0)->get_committed_primitive_id());

#line 99
        uint tri_0 = _S25 + 3U * _S26;
        uint vo_0 = (&kernelContext_4)->instances_0[inst_0];
        uint _S27 = instance_0 + 1U;
        uint _S28 = inst_0 + 2U;

#line 102
        uint _S29 = (&kernelContext_4)->instances_0[_S28] + 1U;
        float _S30 = ((&q_0)->get_committed_distance());

#line 103
        float _S31 = _S30 * - _S21.z;

        uint mi_0 = (&kernelContext_4)->instances_0[_S28] * 23U;
        float3 albedo_1 = float3((&kernelContext_4)->materials_0[mi_0], (&kernelContext_4)->materials_0[mi_0 + 1U], (&kernelContext_4)->materials_0[mi_0 + 2U]);
        uint texBase_0 = uint((&kernelContext_4)->materials_0[mi_0 + 10U]);
        if(texBase_0 > 0U)
        {
            uint _S32 = inst_0 + 4U;

#line 110
            float3 _S33 = vertex_0((&kernelContext_4)->indices_0[tri_0] + vo_0, &kernelContext_4);

#line 110
            float3 p0_0 = transformPoint_0((&kernelContext_4)->instances_0, _S32, _S33);
            uint _S34 = tri_0 + 1U;

#line 111
            float3 _S35 = vertex_0((&kernelContext_4)->indices_0[_S34] + vo_0, &kernelContext_4);

#line 111
            float3 p1_0 = transformPoint_0((&kernelContext_4)->instances_0, _S32, _S35);
            uint _S36 = tri_0 + 2U;

#line 112
            float3 _S37 = vertex_0((&kernelContext_4)->indices_0[_S36] + vo_0, &kernelContext_4);
            float3 e1_0 = p1_0 - p0_0;
            float3 e2_0 = transformPoint_0((&kernelContext_4)->instances_0, _S32, _S37) - p0_0;
            float _S38 = ((&q_0)->get_committed_distance());

#line 115
            float3 e3_0 = org_0 + (&ray_0)->Direction_0 * float3(_S38)  - p0_0;
            float d11_0 = dot(e1_0, e1_0);
            float d12_0 = dot(e1_0, e2_0);
            float d22_0 = dot(e2_0, e2_0);
            float _S39 = max(d11_0 * d22_0 - d12_0 * d12_0, 9.99999968265522539e-21f);
            float _S40 = dot(e3_0, e1_0);

#line 120
            float _S41 = dot(e3_0, e2_0);

            float2 uv0_0 = float2((&kernelContext_4)->uvs_0[2U * ((&kernelContext_4)->indices_0[tri_0] + vo_0)], (&kernelContext_4)->uvs_0[2U * ((&kernelContext_4)->indices_0[tri_0] + vo_0) + 1U]);



            uint ti_0 = (texBase_0 - 1U) * 4U;

#line 126
            float3 _S42 = bilinear_0((&kernelContext_4)->texInfo_0[ti_0], (&kernelContext_4)->texInfo_0[ti_0 + 1U], (&kernelContext_4)->texInfo_0[ti_0 + 2U], uv0_0 + float2(((d22_0 * _S40 - d12_0 * _S41) / _S39))  * (float2((&kernelContext_4)->uvs_0[2U * ((&kernelContext_4)->indices_0[_S34] + vo_0)], (&kernelContext_4)->uvs_0[2U * ((&kernelContext_4)->indices_0[_S34] + vo_0) + 1U]) - uv0_0) + float2(((d11_0 * _S41 - d12_0 * _S40) / _S39))  * (float2((&kernelContext_4)->uvs_0[2U * ((&kernelContext_4)->indices_0[_S36] + vo_0)], (&kernelContext_4)->uvs_0[2U * ((&kernelContext_4)->indices_0[_S36] + vo_0) + 1U]) - uv0_0), &kernelContext_4);

#line 126
            albedo_0 = albedo_1 * _S42;

#line 108
        }
        else
        {

#line 108
            albedo_0 = albedo_1;

#line 108
        }

#line 108
        depth_0 = _S31;

#line 108
        id_0 = _S27;

#line 108
        matId_0 = _S29;

#line 95
    }
    else
    {

#line 95
        depth_0 = 0.0f;

#line 95
        id_0 = 0U;

#line 95
        matId_0 = 0U;

#line 95
        albedo_0 = _S23;

#line 95
    }

#line 95
    uint k_0 = 0U;

#line 95
    float cover_0 = 0.0f;

#line 133
    for(;;)
    {

#line 133
        if(k_0 < 16U)
        {
        }
        else
        {

#line 133
            break;
        }

        thread float3 sdir_0;

#line 136
        float3 _S43 = pixelDir_0(float2(_S18 + (float(k_0 % 4U) + 0.5f) / 4.0f, _S20 + (float(k_0 / 4U) + 0.5f) / 4.0f), w_3, h_3, t_1, aspect_1, &sdir_0, &kernelContext_4);

        thread RayDesc_0 sr_0;
        (&sr_0)->Origin_0 = org_0;
        (&sr_0)->Direction_0 = normalize(sdir_0);
        (&sr_0)->TMin_0 = 0.0f;
        (&sr_0)->TMax_0 = 1.00000001504746622e+30f;

#line 142
        uint layer_0 = 0U;

#line 142
        float through_0 = 1.0f;

#line 142
        float seen_0 = 0.0f;



        for(;;)
        {

#line 146
            if(layer_0 < 8U)
            {

#line 146
                _S17 = through_0 > 0.0f;

#line 146
            }
            else
            {

#line 146
                _S17 = false;

#line 146
            }

#line 146
            if(_S17)
            {
            }
            else
            {

#line 146
                break;
            }
            thread raytracing::intersection_query<raytracing::triangle_data, raytracing::instancing> sq_0;
            (&sq_0)->reset({ (sr_0.Origin_0), (sr_0.Direction_0), (sr_0.TMin_0), (sr_0.TMax_0) }, ((&kernelContext_4)->scene_0), (255U), _slang_ray_flags_to_intersection_params((1U)));
            for(;;)
            {

#line 150
                bool _S44 = ((&sq_0)->next());

#line 150
                if(_S44)
                {
                }
                else
                {

#line 150
                    break;
                }

#line 150
            }
            uint _S45 = (_slang_committed_intersection_type_to_uint((&sq_0)->get_committed_intersection_type()));

#line 151
            if(_S45 != 1U)
            {

#line 152
                break;
            }

#line 153
            uint _S46 = ((&sq_0)->get_committed_instance_id());

#line 153
            float op_0 = (&kernelContext_4)->materials_0[(&kernelContext_4)->instances_0[_S46 * 16U + 2U] * 23U + 22U];
            float seen_1 = seen_0 + through_0 * op_0;
            float through_1 = through_0 * (1.0f - op_0);
            float _S47 = ((&sq_0)->get_committed_distance());

#line 156
            (&sr_0)->Origin_0 = (&sr_0)->Origin_0 + (&sr_0)->Direction_0 * float3((_S47 + 9.9999997473787516e-05f)) ;

#line 146
            layer_0 = layer_0 + 1U;

#line 146
            through_0 = through_1;

#line 146
            seen_0 = seen_1;

#line 146
        }

#line 158
        float cover_1 = cover_0 + seen_0;

#line 133
        k_0 = k_0 + 1U;

#line 133
        cover_0 = cover_1;

#line 133
    }

#line 161
    uint pixel_0 = _S19 * w_3 + _S16;
    *((&kernelContext_4)->coverage_0+pixel_0) = cover_0 / 16.0f;
    uint _S48 = 4U * pixel_0;

#line 163
    *((&kernelContext_4)->albedoDepth_0+_S48) = albedo_0.x;
    *((&kernelContext_4)->albedoDepth_0+(_S48 + 1U)) = albedo_0.y;
    *((&kernelContext_4)->albedoDepth_0+(_S48 + 2U)) = albedo_0.z;
    *((&kernelContext_4)->albedoDepth_0+(_S48 + 3U)) = depth_0;
    *((&kernelContext_4)->objectIds_0+pixel_0) = id_0;
    *((&kernelContext_4)->materialIds_0+pixel_0) = matId_0;
    return;
}

