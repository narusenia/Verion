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


#line 74
float3 pixelDir_0(float2 px_0, uint w_0, uint h_0, float t_0, float aspect_0, float3 thread* dir_0, KernelContext_0 thread* kernelContext_0)
{


    float3 d_0 = normalize(float3((2.0f * px_0.x / float(w_0) - 1.0f + kernelContext_0->camera_0[int(16)]) * aspect_0 * t_0, (1.0f - 2.0f * px_0.y / float(h_0) + kernelContext_0->camera_0[int(17)]) * t_0, -1.0f));

#line 78
    uint r_0 = 0U;
    for(;;)
    {

#line 79
        if(r_0 < 3U)
        {
        }
        else
        {

#line 79
            break;
        }

#line 80
        uint _S1 = 4U * r_0;

#line 80
        (*dir_0)[r_0] = kernelContext_0->camera_0[4U + _S1] * d_0.x + kernelContext_0->camera_0[5U + _S1] * d_0.y + kernelContext_0->camera_0[6U + _S1] * d_0.z;

#line 79
        r_0 = r_0 + 1U;

#line 79
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



float opacityAt_0(uint instIdx_0, uint prim_0, float2 bary_0, KernelContext_0 thread* kernelContext_4)
{
    uint _S16 = instIdx_0 * 16U;

#line 58
    uint mi_0 = kernelContext_4->instances_0[_S16 + 2U] * 24U;
    float op_0 = kernelContext_4->materials_0[mi_0 + 22U];
    uint tex_0 = uint(kernelContext_4->materials_0[mi_0 + 23U]);

#line 60
    bool _S17;
    if(tex_0 > 0U)
    {

#line 61
        _S17 = op_0 > 0.0f;

#line 61
    }
    else
    {

#line 61
        _S17 = false;

#line 61
    }

#line 61
    float op_1;

#line 61
    if(_S17)
    {
        uint tri_0 = kernelContext_4->instances_0[_S16 + 1U] + 3U * prim_0;
        uint vo_0 = kernelContext_4->instances_0[_S16];
        float2 uv0_0 = float2(kernelContext_4->uvs_0[2U * (kernelContext_4->indices_0[tri_0] + vo_0)], kernelContext_4->uvs_0[2U * (kernelContext_4->indices_0[tri_0] + vo_0) + 1U]);
        uint _S18 = tri_0 + 1U;
        uint _S19 = tri_0 + 2U;
        uint ti_0 = (tex_0 - 1U) * 4U;

#line 68
        float3 _S20 = bilinear_0(kernelContext_4->texInfo_0[ti_0], kernelContext_4->texInfo_0[ti_0 + 1U], kernelContext_4->texInfo_0[ti_0 + 2U], uv0_0 + float2(bary_0.x)  * (float2(kernelContext_4->uvs_0[2U * (kernelContext_4->indices_0[_S18] + vo_0)], kernelContext_4->uvs_0[2U * (kernelContext_4->indices_0[_S18] + vo_0) + 1U]) - uv0_0) + float2(bary_0.y)  * (float2(kernelContext_4->uvs_0[2U * (kernelContext_4->indices_0[_S19] + vo_0)], kernelContext_4->uvs_0[2U * (kernelContext_4->indices_0[_S19] + vo_0) + 1U]) - uv0_0), kernelContext_4);

#line 68
        op_1 = op_0 * _S20.x;

#line 61
    }
    else
    {

#line 61
        op_1 = op_0;

#line 61
    }

#line 71
    return op_1;
}


#line 20995 "hlsl.meta.slang"
struct RayDesc_0
{
    float3 Origin_0;
    float TMin_0;
    float3 Direction_0;
    float TMax_0;
};


#line 86 "shaders/aov.slang"
[[kernel]] void aov(uint3 tid_0 [[thread_position_in_grid]], float device* camera_1 [[buffer(4)]], metal::raytracing::acceleration_structure<metal::raytracing::instancing> scene_1 [[buffer(0)]], uint device* instances_1 [[buffer(3)]], float device* materials_1 [[buffer(5)]], uint device* indices_1 [[buffer(2)]], float device* positions_1 [[buffer(1)]], float device* uvs_1 [[buffer(6)]], uint device* texInfo_1 [[buffer(7)]], float device* texels_1 [[buffer(8)]], float device* coverage_1 [[buffer(12)]], float device* albedoDepth_1 [[buffer(9)]], uint device* objectIds_1 [[buffer(10)]], uint device* materialIds_1 [[buffer(11)]])
{

#line 86
    thread KernelContext_0 kernelContext_5;

#line 86
    (&kernelContext_5)->camera_0 = camera_1;

#line 86
    (&kernelContext_5)->scene_0 = scene_1;

#line 86
    (&kernelContext_5)->instances_0 = instances_1;

#line 86
    (&kernelContext_5)->materials_0 = materials_1;

#line 86
    (&kernelContext_5)->indices_0 = indices_1;

#line 86
    (&kernelContext_5)->positions_0 = positions_1;

#line 86
    (&kernelContext_5)->uvs_0 = uvs_1;

#line 86
    (&kernelContext_5)->texInfo_0 = texInfo_1;

#line 86
    (&kernelContext_5)->texels_0 = texels_1;

#line 86
    (&kernelContext_5)->coverage_0 = coverage_1;

#line 86
    (&kernelContext_5)->albedoDepth_0 = albedoDepth_1;

#line 86
    (&kernelContext_5)->objectIds_0 = objectIds_1;

#line 86
    (&kernelContext_5)->materialIds_0 = materialIds_1;

    uint w_3 = uint(camera_1[int(0)]);
    uint h_3 = uint(camera_1[int(1)]);
    uint _S21 = tid_0.x;

#line 90
    bool _S22;

#line 90
    if(_S21 >= w_3)
    {

#line 90
        _S22 = true;

#line 90
    }
    else
    {

#line 90
        _S22 = (tid_0.y) >= h_3;

#line 90
    }

#line 90
    if(_S22)
    {

#line 91
        return;
    }
    float t_1 = (&kernelContext_5)->camera_0[int(2)];
    float aspect_1 = (&kernelContext_5)->camera_0[int(0)] / (&kernelContext_5)->camera_0[int(1)];
    float _S23 = float(_S21);

#line 95
    uint _S24 = tid_0.y;

#line 95
    float _S25 = float(_S24);

#line 95
    float2 px_1 = float2(_S23 + 0.5f, _S25 + 0.5f);


    thread RayDesc_0 ray_0;
    (&ray_0)->TMin_0 = 0.0f;
    (&ray_0)->TMax_0 = 1.00000001504746622e+30f;
    float3 org_0 = float3((&kernelContext_5)->camera_0[int(7)], (&kernelContext_5)->camera_0[int(11)], (&kernelContext_5)->camera_0[int(15)]);

#line 97
    thread float3 dir_1;

#line 97
    float3 _S26 = pixelDir_0(px_1, w_3, h_3, t_1, aspect_1, &dir_1, &kernelContext_5);

#line 103
    (&ray_0)->Origin_0 = org_0;
    (&ray_0)->Direction_0 = normalize(dir_1);

    thread raytracing::intersection_query<raytracing::triangle_data, raytracing::instancing> q_0;
    (&q_0)->reset({ (ray_0.Origin_0), (ray_0.Direction_0), (ray_0.TMin_0), (ray_0.TMax_0) }, ((&kernelContext_5)->scene_0), (255U), _slang_ray_flags_to_intersection_params((1U)));
    for(;;)
    {

#line 108
        bool _S27 = ((&q_0)->next());

#line 108
        if(_S27)
        {
        }
        else
        {

#line 108
            break;
        }

#line 108
    }

    float3 _S28 = float3(0.0f) ;



    uint _S29 = (_slang_committed_intersection_type_to_uint((&q_0)->get_committed_intersection_type()));

#line 114
    float3 albedo_0;

#line 114
    float depth_0;

#line 114
    uint id_0;

#line 114
    uint matId_0;

#line 114
    if(_S29 == 1U)
    {
        uint instance_0 = ((&q_0)->get_committed_instance_id());
        uint inst_0 = instance_0 * 16U;
        uint _S30 = (&kernelContext_5)->instances_0[inst_0 + 1U];

#line 118
        uint _S31 = ((&q_0)->get_committed_primitive_id());

#line 118
        uint tri_1 = _S30 + 3U * _S31;
        uint vo_1 = (&kernelContext_5)->instances_0[inst_0];
        uint _S32 = instance_0 + 1U;
        uint _S33 = inst_0 + 2U;

#line 121
        uint _S34 = (&kernelContext_5)->instances_0[_S33] + 1U;
        float _S35 = ((&q_0)->get_committed_distance());

#line 122
        float _S36 = _S35 * - _S26.z;

        uint mi_1 = (&kernelContext_5)->instances_0[_S33] * 24U;
        float3 albedo_1 = float3((&kernelContext_5)->materials_0[mi_1], (&kernelContext_5)->materials_0[mi_1 + 1U], (&kernelContext_5)->materials_0[mi_1 + 2U]);
        uint texBase_0 = uint((&kernelContext_5)->materials_0[mi_1 + 10U]);
        if(texBase_0 > 0U)
        {
            uint _S37 = inst_0 + 4U;

#line 129
            float3 _S38 = vertex_0((&kernelContext_5)->indices_0[tri_1] + vo_1, &kernelContext_5);

#line 129
            float3 p0_0 = transformPoint_0((&kernelContext_5)->instances_0, _S37, _S38);
            uint _S39 = tri_1 + 1U;

#line 130
            float3 _S40 = vertex_0((&kernelContext_5)->indices_0[_S39] + vo_1, &kernelContext_5);

#line 130
            float3 p1_0 = transformPoint_0((&kernelContext_5)->instances_0, _S37, _S40);
            uint _S41 = tri_1 + 2U;

#line 131
            float3 _S42 = vertex_0((&kernelContext_5)->indices_0[_S41] + vo_1, &kernelContext_5);
            float3 e1_0 = p1_0 - p0_0;
            float3 e2_0 = transformPoint_0((&kernelContext_5)->instances_0, _S37, _S42) - p0_0;
            float _S43 = ((&q_0)->get_committed_distance());

#line 134
            float3 e3_0 = org_0 + (&ray_0)->Direction_0 * float3(_S43)  - p0_0;
            float d11_0 = dot(e1_0, e1_0);
            float d12_0 = dot(e1_0, e2_0);
            float d22_0 = dot(e2_0, e2_0);
            float _S44 = max(d11_0 * d22_0 - d12_0 * d12_0, 9.99999968265522539e-21f);
            float _S45 = dot(e3_0, e1_0);

#line 139
            float _S46 = dot(e3_0, e2_0);

            float2 uv0_1 = float2((&kernelContext_5)->uvs_0[2U * ((&kernelContext_5)->indices_0[tri_1] + vo_1)], (&kernelContext_5)->uvs_0[2U * ((&kernelContext_5)->indices_0[tri_1] + vo_1) + 1U]);



            uint ti_1 = (texBase_0 - 1U) * 4U;

#line 145
            float3 _S47 = bilinear_0((&kernelContext_5)->texInfo_0[ti_1], (&kernelContext_5)->texInfo_0[ti_1 + 1U], (&kernelContext_5)->texInfo_0[ti_1 + 2U], uv0_1 + float2(((d22_0 * _S45 - d12_0 * _S46) / _S44))  * (float2((&kernelContext_5)->uvs_0[2U * ((&kernelContext_5)->indices_0[_S39] + vo_1)], (&kernelContext_5)->uvs_0[2U * ((&kernelContext_5)->indices_0[_S39] + vo_1) + 1U]) - uv0_1) + float2(((d11_0 * _S46 - d12_0 * _S45) / _S44))  * (float2((&kernelContext_5)->uvs_0[2U * ((&kernelContext_5)->indices_0[_S41] + vo_1)], (&kernelContext_5)->uvs_0[2U * ((&kernelContext_5)->indices_0[_S41] + vo_1) + 1U]) - uv0_1), &kernelContext_5);

#line 145
            albedo_0 = albedo_1 * _S47;

#line 127
        }
        else
        {

#line 127
            albedo_0 = albedo_1;

#line 127
        }

#line 127
        depth_0 = _S36;

#line 127
        id_0 = _S32;

#line 127
        matId_0 = _S34;

#line 114
    }
    else
    {

#line 114
        depth_0 = 0.0f;

#line 114
        id_0 = 0U;

#line 114
        matId_0 = 0U;

#line 114
        albedo_0 = _S28;

#line 114
    }

#line 114
    uint k_0 = 0U;

#line 114
    float cover_0 = 0.0f;

#line 152
    for(;;)
    {

#line 152
        if(k_0 < 16U)
        {
        }
        else
        {

#line 152
            break;
        }

        thread float3 sdir_0;

#line 155
        float3 _S48 = pixelDir_0(float2(_S23 + (float(k_0 % 4U) + 0.5f) / 4.0f, _S25 + (float(k_0 / 4U) + 0.5f) / 4.0f), w_3, h_3, t_1, aspect_1, &sdir_0, &kernelContext_5);

        thread RayDesc_0 sr_0;
        (&sr_0)->Origin_0 = org_0;
        (&sr_0)->Direction_0 = normalize(sdir_0);
        (&sr_0)->TMin_0 = 0.0f;
        (&sr_0)->TMax_0 = 1.00000001504746622e+30f;

#line 161
        uint layer_0 = 0U;

#line 161
        float through_0 = 1.0f;

#line 161
        float seen_0 = 0.0f;



        for(;;)
        {

#line 165
            if(layer_0 < 8U)
            {

#line 165
                _S22 = through_0 > 0.0f;

#line 165
            }
            else
            {

#line 165
                _S22 = false;

#line 165
            }

#line 165
            if(_S22)
            {
            }
            else
            {

#line 165
                break;
            }
            thread raytracing::intersection_query<raytracing::triangle_data, raytracing::instancing> sq_0;
            (&sq_0)->reset({ (sr_0.Origin_0), (sr_0.Direction_0), (sr_0.TMin_0), (sr_0.TMax_0) }, ((&kernelContext_5)->scene_0), (255U), _slang_ray_flags_to_intersection_params((1U)));
            for(;;)
            {

#line 169
                bool _S49 = ((&sq_0)->next());

#line 169
                if(_S49)
                {
                }
                else
                {

#line 169
                    break;
                }

#line 169
            }
            uint _S50 = (_slang_committed_intersection_type_to_uint((&sq_0)->get_committed_intersection_type()));

#line 170
            if(_S50 != 1U)
            {

#line 171
                break;
            }

#line 172
            uint _S51 = ((&sq_0)->get_committed_instance_id());

#line 172
            uint _S52 = ((&sq_0)->get_committed_primitive_id());

#line 172
            float2 _S53 = ((&sq_0)->get_committed_triangle_barycentric_coord());

#line 172
            float _S54 = opacityAt_0(_S51, _S52, _S53, &kernelContext_5);
            float seen_1 = seen_0 + through_0 * _S54;
            float through_1 = through_0 * (1.0f - _S54);
            float _S55 = ((&sq_0)->get_committed_distance());

#line 175
            (&sr_0)->Origin_0 = (&sr_0)->Origin_0 + (&sr_0)->Direction_0 * float3((_S55 + 9.9999997473787516e-05f)) ;

#line 165
            layer_0 = layer_0 + 1U;

#line 165
            through_0 = through_1;

#line 165
            seen_0 = seen_1;

#line 165
        }

#line 177
        float cover_1 = cover_0 + seen_0;

#line 152
        k_0 = k_0 + 1U;

#line 152
        cover_0 = cover_1;

#line 152
    }

#line 180
    uint pixel_0 = _S24 * w_3 + _S21;
    *((&kernelContext_5)->coverage_0+pixel_0) = cover_0 / 16.0f;
    uint _S56 = 4U * pixel_0;

#line 182
    *((&kernelContext_5)->albedoDepth_0+_S56) = albedo_0.x;
    *((&kernelContext_5)->albedoDepth_0+(_S56 + 1U)) = albedo_0.y;
    *((&kernelContext_5)->albedoDepth_0+(_S56 + 2U)) = albedo_0.z;
    *((&kernelContext_5)->albedoDepth_0+(_S56 + 3U)) = depth_0;
    *((&kernelContext_5)->objectIds_0+pixel_0) = id_0;
    *((&kernelContext_5)->materialIds_0+pixel_0) = matId_0;
    return;
}

