//! Needs a Metal RT device; skips on machines without one (e.g. CI runners).
#![cfg(target_os = "macos")]

use std::collections::HashMap;
use verion_gpu_metal::{Error, MetalContext, Renderer};

use verion_scene::{BaseBsdf, Camera, IDENTITY, Image, Instance, Light, Material, Mesh, Scene};

fn context() -> Option<MetalContext> {
    match MetalContext::new() {
        Ok(ctx) => Some(ctx),
        Err(e @ (Error::NoDevice | Error::RaytracingUnsupported { .. })) => {
            eprintln!("skipped: {e}");
            None
        }
        Err(e) => panic!("{e}"),
    }
}

/// Pure Lambert: `ior = 1` switches the dielectric specular layer off.
fn material(base_color: [f32; 3], emission: [f32; 3]) -> Material {
    Material {
        base: BaseBsdf {
            base_color,
            emission,
            ior: 1.0,
            ..BaseBsdf::default()
        },
        ..Material::default()
    }
}

fn bsdf(base: BaseBsdf) -> Material {
    Material {
        base,
        ..Material::default()
    }
}

/// Axis-aligned cube with 12 triangles; winding does not matter (surfaces are double-sided).
fn cube(half: f32) -> Mesh {
    let h = half;
    let positions = vec![
        [-h, -h, -h],
        [h, -h, -h],
        [h, h, -h],
        [-h, h, -h],
        [-h, -h, h],
        [h, -h, h],
        [h, h, h],
        [-h, h, h],
    ];
    #[rustfmt::skip]
    let indices = vec![
        0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7, 0, 1, 5, 0, 5, 4,
        2, 3, 7, 2, 7, 6, 1, 2, 6, 1, 6, 5, 0, 3, 7, 0, 7, 4,
    ];
    Mesh::new(positions, None, None, indices).unwrap()
}

/// Large square in the z = 0 plane, `half` wide.
fn plane(half: f32, z: f32) -> Mesh {
    let h = half;
    Mesh::new(
        vec![[-h, -h, z], [h, -h, z], [h, h, z], [-h, h, z]],
        None,
        None,
        vec![0, 1, 2, 0, 2, 3],
    )
    .unwrap()
}

fn camera_at_z(z: f32) -> Camera {
    let mut cam = Camera::default();
    cam.transform[2][3] = z;
    cam
}

fn mean(img: &[[f32; 3]]) -> f32 {
    img.iter().map(|p| p[0]).sum::<f32>() / img.len() as f32
}

fn variance(img: &[[f32; 3]]) -> f32 {
    let m = mean(img);
    img.iter().map(|p| (p[0] - m).powi(2)).sum::<f32>() / img.len() as f32
}

/// Camera inside a closed cube whose walls emit `e` and reflect `rho`.
fn furnace_room(rho: f32, e: f32) -> Scene {
    let mut s = Scene::new();
    let mesh = s.add_mesh(cube(1.0));
    let mat = s.add_material(material([rho; 3], [e; 3]));
    s.add_instance(Instance {
        mesh,
        material: mat,
        transform: IDENTITY,
    })
    .unwrap();
    s
}

#[test]
fn closed_emissive_room_matches_the_series_sum() {
    let Some(ctx) = context() else { return };
    let (rho, e) = (0.5f32, 1.0f32);
    let r = Renderer::new(&ctx, &furnace_room(rho, e)).unwrap();
    let got = mean(&r.render(64, 64, 64).unwrap());
    // Paths are cut at 8 bounces: L = E * (1 - rho^8) / (1 - rho).
    let expected = e * (1.0 - rho.powi(8)) / (1.0 - rho);
    assert!(
        (got - expected).abs() / expected < 0.01,
        "{got} vs {expected}"
    );
}

#[test]
fn white_furnace_returns_the_sky_exactly() {
    let Some(ctx) = context() else { return };
    // Convex albedo-1 object under a uniform sky: every path escapes after one bounce.
    let mut s = Scene::new();
    let mesh = s.add_mesh(cube(0.5));
    let mat = s.add_material(material([1.0; 3], [0.0; 3]));
    s.add_instance(Instance {
        mesh,
        material: mat,
        transform: IDENTITY,
    })
    .unwrap();
    s.add_light(Light::Environment { color: [1.0; 3] });
    s.set_camera(camera_at_z(3.0));
    let img = Renderer::new(&ctx, &s).unwrap().render(32, 32, 4).unwrap();
    assert!(
        img.iter().all(|p| p.iter().all(|c| (c - 1.0).abs() < 1e-4)),
        "furnace not flat"
    );
}

#[test]
fn variance_decreases_with_samples() {
    let Some(ctx) = context() else { return };
    let r = Renderer::new(&ctx, &furnace_room(0.5, 1.0)).unwrap();
    let v: Vec<f32> = [4, 16, 64]
        .iter()
        .map(|&n| variance(&r.render(64, 64, n).unwrap()))
        .collect();
    assert!(v[0] > v[1] && v[1] > v[2], "{v:?}");
}

#[test]
fn progressive_accumulation_equals_one_shot_sample_count() {
    let Some(ctx) = context() else { return };
    let r = Renderer::new(&ctx, &furnace_room(0.5, 1.0)).unwrap();
    let mut acc = r.new_accumulation(16, 16).unwrap();
    assert_eq!(acc.mean()[0], [0.0; 3]);
    r.accumulate(&mut acc, 8).unwrap();
    r.accumulate(&mut acc, 8).unwrap();
    assert_eq!(acc.samples(), 16);
    assert!((mean(&acc.mean()) - 1.99).abs() < 0.1);
}

/// Albedo-1 floor lit by one light and seen from above; center pixel radiance is analytic.
fn floor_scene(light: Light, occluder: bool) -> Scene {
    let mut s = Scene::new();
    let floor = s.add_mesh(plane(5.0, 0.0));
    let mat = s.add_material(material([1.0; 3], [0.0; 3]));
    s.add_instance(Instance {
        mesh: floor,
        material: mat,
        transform: IDENTITY,
    })
    .unwrap();
    if occluder {
        // Small triangle between the light and the floor point under the camera, off the view ray.
        let tri = Mesh::new(
            vec![[0.4, -0.3, 0.5], [0.6, -0.3, 0.5], [0.5, 0.3, 0.5]],
            None,
            None,
            vec![0, 1, 2],
        )
        .unwrap();
        let m = s.add_mesh(tri);
        // Black, so it blocks the light without bouncing any of the lit floor back.
        let black = s.add_material(material([0.0; 3], [0.0; 3]));
        s.add_instance(Instance {
            mesh: m,
            material: black,
            transform: IDENTITY,
        })
        .unwrap();
    }
    s.add_light(light);
    s.set_camera(camera_at_z(3.0));
    s
}

fn center_pixel(ctx: &MetalContext, scene: &Scene) -> f32 {
    let img = Renderer::new(ctx, scene)
        .unwrap()
        .render(65, 65, 64)
        .unwrap();
    img[32 * 65 + 32][0]
}

#[test]
fn point_light_direct_lighting_matches_lambert() {
    let Some(ctx) = context() else { return };
    // L = rho/pi * I * cos / d^2 at the origin; light at (1, 0, 1): d^2 = 2, cos = 1/sqrt 2.
    let intensity = std::f32::consts::PI * 2.0 * 2.0f32.sqrt();
    let light = Light::Point {
        position: [1.0, 0.0, 1.0],
        color: [1.0; 3],
        intensity,
    };
    let lit = center_pixel(&ctx, &floor_scene(light, false));
    assert!((lit - 1.0).abs() < 0.01, "lit {lit}");
    let shadowed = center_pixel(&ctx, &floor_scene(light, true));
    assert!(shadowed < 1e-3, "shadowed {shadowed}");
}

#[test]
fn directional_light_direct_lighting_matches_lambert() {
    let Some(ctx) = context() else { return };
    // Sun straight down: L = rho/pi * E.
    let light = Light::Directional {
        direction: [0.0, 0.0, -1.0],
        color: [1.0; 3],
        intensity: std::f32::consts::PI,
    };
    let lit = center_pixel(&ctx, &floor_scene(light, false));
    assert!((lit - 1.0).abs() < 0.01, "{lit}");
}

/// Floor lit by a sun straight down, every vertex carrying `normal`; returns the centre radiance.
fn shaded_floor(ctx: &MetalContext, normal: [f32; 3], transform: [[f32; 4]; 3]) -> f32 {
    let mut s = Scene::new();
    let h = 5.0;
    let mesh = Mesh::new(
        vec![[-h, -h, 0.0], [h, -h, 0.0], [h, h, 0.0], [-h, h, 0.0]],
        Some(vec![normal; 4]),
        None,
        vec![0, 1, 2, 0, 2, 3],
    )
    .unwrap();
    let mesh = s.add_mesh(mesh);
    let mat = s.add_material(material([1.0; 3], [0.0; 3]));
    s.add_instance(Instance {
        mesh,
        material: mat,
        transform,
    })
    .unwrap();
    s.add_light(Light::Directional {
        direction: [0.0, 0.0, -1.0],
        color: [1.0; 3],
        intensity: std::f32::consts::PI,
    });
    s.set_camera(camera_at_z(3.0));
    center_pixel(ctx, &s)
}

#[test]
fn vertex_normals_drive_the_shading() {
    let Some(ctx) = context() else { return };
    // Normal tilted 60 degrees from the geometric one: L = cos(60) = 0.5 instead of 1.
    let tilted = shaded_floor(&ctx, [0.866_025_4, 0.0, 0.5], IDENTITY);
    assert!((tilted - 0.5).abs() < 0.01, "{tilted}");
}

#[test]
fn vertex_normals_follow_a_non_uniform_scale() {
    let Some(ctx) = context() else { return };
    // Stretching x by 2 turns (1, 0, 1) into (1/2, 0, 1) as a normal: cos = 1 / sqrt(1.25).
    let scale = [
        [2.0, 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0],
    ];
    let got = shaded_floor(&ctx, [1.0, 0.0, 1.0], scale);
    assert!((got - 0.894_427).abs() < 0.01, "{got}");
}

/// Textured floor (u to +x, v to -y) with a 1x1 normal map, lit by a sun shining from `to_light`.
fn normal_mapped_floor(
    ctx: &MetalContext,
    tangent_normal: [f32; 3],
    scale: f32,
    to_light: [f32; 3],
) -> f32 {
    let mut s = Scene::new();
    let h = 5.0;
    let mesh = Mesh::new(
        vec![[-h, -h, 0.0], [h, -h, 0.0], [h, h, 0.0], [-h, h, 0.0]],
        None,
        Some(vec![[0.0, 1.0], [1.0, 1.0], [1.0, 0.0], [0.0, 0.0]]),
        vec![0, 1, 2, 0, 2, 3],
    )
    .unwrap();
    let mesh = s.add_mesh(mesh);
    let texel = tangent_normal.map(|c| c * 0.5 + 0.5);
    let map = s.add_image(Image::new(1, 1, vec![texel]).unwrap());
    let mat = s.add_material(bsdf(BaseBsdf {
        base_color: [1.0; 3],
        ior: 1.0,
        normal_texture: Some(map),
        normal_scale: scale,
        ..BaseBsdf::default()
    }));
    s.add_instance(Instance {
        mesh,
        material: mat,
        transform: IDENTITY,
    })
    .unwrap();
    s.add_light(Light::Directional {
        direction: to_light.map(|c| -c),
        color: [1.0; 3],
        intensity: std::f32::consts::PI,
    });
    s.set_camera(camera_at_z(3.0));
    center_pixel(ctx, &s)
}

#[test]
fn normal_map_tilts_the_shading_normal() {
    let Some(ctx) = context() else { return };
    let tilt = [0.866_025_4, 0.5];
    // Sun 60 degrees off the surface normal. Matching the map's tilt lights the texel fully;
    // a flat surface would get cos(60) = 0.5. Green is up the image, which is +y in the world.
    let x = normal_mapped_floor(&ctx, [tilt[0], 0.0, tilt[1]], 1.0, [tilt[0], 0.0, tilt[1]]);
    let y = normal_mapped_floor(&ctx, [0.0, tilt[0], tilt[1]], 1.0, [0.0, tilt[0], tilt[1]]);
    assert!((x - 1.0).abs() < 0.01, "x {x}");
    assert!((y - 1.0).abs() < 0.01, "y {y}");
    // Tilted the other way in y the normal faces away from the sun (cos = -0.5): no light.
    let away = normal_mapped_floor(&ctx, [0.0, -tilt[0], tilt[1]], 1.0, [0.0, tilt[0], tilt[1]]);
    assert!(away < 0.01, "away {away}");
}

#[test]
fn normal_scale_flattens_the_tilt() {
    let Some(ctx) = context() else { return };
    // Scale 0 leaves the geometric normal: sun straight above gives L = 1.
    let flat = normal_mapped_floor(&ctx, [0.866_025_4, 0.0, 0.5], 0.0, [0.0, 0.0, 1.0]);
    assert!((flat - 1.0).abs() < 0.01, "{flat}");
}

#[test]
fn thin_lens_keeps_the_focal_plane_sharp() {
    let Some(ctx) = context() else { return };
    // An emissive wall exactly at the focus distance stays uniform however wide the aperture.
    let mut s = Scene::new();
    let wall = s.add_mesh(plane(5.0, 0.0));
    let mat = s.add_material(material([0.0; 3], [1.0; 3]));
    s.add_instance(Instance {
        mesh: wall,
        material: mat,
        transform: IDENTITY,
    })
    .unwrap();
    let mut cam = camera_at_z(3.0);
    cam.focus_distance = 3.0;
    cam.aperture_radius = 0.2;
    s.set_camera(cam);
    let img = Renderer::new(&ctx, &s).unwrap().render(32, 32, 8).unwrap();
    assert!(img.iter().all(|p| (p[0] - 1.0).abs() < 1e-4));
}

/// Unit-radius-scaled icosphere with outward counter-clockwise faces.
fn icosphere(radius: f32) -> Mesh {
    let t = (1.0 + 5.0f32.sqrt()) / 2.0;
    let mut v: Vec<[f32; 3]> = vec![
        [-1.0, t, 0.0],
        [1.0, t, 0.0],
        [-1.0, -t, 0.0],
        [1.0, -t, 0.0],
        [0.0, -1.0, t],
        [0.0, 1.0, t],
        [0.0, -1.0, -t],
        [0.0, 1.0, -t],
        [t, 0.0, -1.0],
        [t, 0.0, 1.0],
        [-t, 0.0, -1.0],
        [-t, 0.0, 1.0],
    ];
    #[rustfmt::skip]
    let mut faces: Vec<[u32; 3]> = vec![
        [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
        [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
        [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
        [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
    ];
    for _ in 0..2 {
        let mut mids: HashMap<(u32, u32), u32> = HashMap::new();
        let mut mid = |a: u32, b: u32, v: &mut Vec<[f32; 3]>| -> u32 {
            *mids.entry((a.min(b), a.max(b))).or_insert_with(|| {
                let (p, q) = (v[a as usize], v[b as usize]);
                v.push([
                    (p[0] + q[0]) / 2.0,
                    (p[1] + q[1]) / 2.0,
                    (p[2] + q[2]) / 2.0,
                ]);
                v.len() as u32 - 1
            })
        };
        let mut next = Vec::new();
        for [a, b, c] in faces {
            let (ab, bc, ca) = (mid(a, b, &mut v), mid(b, c, &mut v), mid(c, a, &mut v));
            next.extend([[a, ab, ca], [b, bc, ab], [c, ca, bc], [ab, bc, ca]]);
        }
        faces = next;
    }
    for p in &mut v {
        let len = (p[0] * p[0] + p[1] * p[1] + p[2] * p[2]).sqrt();
        *p = [
            p[0] / len * radius,
            p[1] / len * radius,
            p[2] / len * radius,
        ];
    }
    for f in &mut faces {
        let [a, b, c] = f.map(|i| v[i as usize]);
        let n = [
            (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]),
            (b[2] - a[2]) * (c[0] - a[0]) - (b[0] - a[0]) * (c[2] - a[2]),
            (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]),
        ];
        // The centroid points outward on a sphere centered at the origin.
        if n[0] * (a[0] + b[0] + c[0]) + n[1] * (a[1] + b[1] + c[1]) + n[2] * (a[2] + b[2] + c[2])
            < 0.0
        {
            f.swap(1, 2);
        }
    }
    Mesh::new(v, None, None, faces.concat()).unwrap()
}

/// Mean of the central `size` x `size` block of a `w` x `w` image.
fn center_mean(img: &[[f32; 3]], w: usize, size: usize) -> f32 {
    let lo = (w - size) / 2;
    let mut sum = 0.0;
    for y in lo..lo + size {
        for x in lo..lo + size {
            sum += img[y * w + x][0];
        }
    }
    sum / (size * size) as f32
}

fn sky_scene(mesh: Mesh, material: Material, camera_z: f32) -> Scene {
    let mut s = Scene::new();
    let mesh = s.add_mesh(mesh);
    let mat = s.add_material(material);
    s.add_instance(Instance {
        mesh,
        material: mat,
        transform: IDENTITY,
    })
    .unwrap();
    s.add_light(Light::Environment { color: [1.0; 3] });
    s.set_camera(camera_at_z(camera_z));
    s
}

#[test]
fn smooth_dielectric_reflects_the_normal_incidence_fresnel() {
    let Some(ctx) = context() else { return };
    // Black base, mirror-smooth: the only light is the specular layer, F0 = ((1.5 - 1) / (1.5 + 1))^2 = 0.04.
    let m = bsdf(BaseBsdf {
        base_color: [0.0; 3],
        roughness: 0.0,
        ..BaseBsdf::default()
    });
    let img = Renderer::new(&ctx, &sky_scene(plane(5.0, 0.0), m, 3.0))
        .unwrap()
        .render(32, 32, 64)
        .unwrap();
    let got = center_mean(&img, 32, 16);
    assert!((got - 0.04).abs() < 0.003, "{got}");
}

#[test]
fn metal_furnace_conserves_energy() {
    let Some(ctx) = context() else { return };
    for (roughness, lo) in [(0.0, 0.99), (0.3, 0.96), (0.5, 0.9)] {
        let m = bsdf(BaseBsdf {
            base_color: [1.0; 3],
            metallic: 1.0,
            roughness,
            ..BaseBsdf::default()
        });
        let img = Renderer::new(&ctx, &sky_scene(cube(0.5), m, 3.0))
            .unwrap()
            .render(32, 32, 64)
            .unwrap();
        let got = center_mean(&img, 32, 16);
        // Single scattering only: some energy is lost at grazing angles, never gained.
        assert!(got > lo && got < 1.005, "roughness {roughness}: {got}");
    }
}

#[test]
fn metal_tints_by_base_color() {
    let Some(ctx) = context() else { return };
    let m = bsdf(BaseBsdf {
        base_color: [0.5; 3],
        metallic: 1.0,
        roughness: 0.0,
        ..BaseBsdf::default()
    });
    let img = Renderer::new(&ctx, &sky_scene(plane(5.0, 0.0), m, 3.0))
        .unwrap()
        .render(32, 32, 16)
        .unwrap();
    let got = center_mean(&img, 32, 16);
    assert!((got - 0.5).abs() < 0.01, "{got}");
}

#[test]
fn glass_furnace_conserves_energy() {
    let Some(ctx) = context() else { return };
    for (roughness, lo) in [(0.0, 0.98), (0.3, 0.9)] {
        let m = bsdf(BaseBsdf {
            base_color: [1.0; 3],
            roughness,
            transmission: 1.0,
            ..BaseBsdf::default()
        });
        let img = Renderer::new(&ctx, &sky_scene(icosphere(1.0), m, 4.0))
            .unwrap()
            .render(48, 48, 64)
            .unwrap();
        let got = mean(&img);
        // Every path escapes a closed convex object, so the sky must come back out.
        assert!(got > lo && got < 1.01, "roughness {roughness}: {got}");
    }
}

#[test]
fn rough_metal_highlight_matches_ggx() {
    let Some(ctx) = context() else { return };
    // Light straight above the shading point, camera on the same axis: h = n, wo = wi = n.
    // f * cos = F * D(n) / 4 with D = 1 / (pi alpha^2), alpha = 0.5^2; radiance = f * cos * I / d^2.
    let alpha = 0.25f32;
    let d = 2.0f32;
    let intensity = 4.0 * std::f32::consts::PI * alpha * alpha * d * d;
    let mut s = Scene::new();
    let floor = s.add_mesh(plane(5.0, 0.0));
    let m = s.add_material(bsdf(BaseBsdf {
        base_color: [1.0; 3],
        metallic: 1.0,
        roughness: 0.5,
        ..BaseBsdf::default()
    }));
    s.add_instance(Instance {
        mesh: floor,
        material: m,
        transform: IDENTITY,
    })
    .unwrap();
    s.add_light(Light::Point {
        position: [0.0, 0.0, d],
        color: [1.0; 3],
        intensity,
    });
    s.set_camera(camera_at_z(3.0));
    let img = Renderer::new(&ctx, &s).unwrap().render(65, 65, 64).unwrap();
    let got = img[32 * 65 + 32][0];
    assert!((got - 1.0).abs() < 0.02, "{got}");
}

/// Emitter-only material: black base, constant emitted radiance.
fn emitter(le: f32) -> Material {
    material([0.0; 3], [le; 3])
}

/// Floor at z = 0 with `floor` material, a camera at z = 0.5, and `light` placed above it.
fn floor_with_emitter(
    floor: Material,
    light: Mesh,
    light_transform: verion_scene::Transform,
    le: f32,
) -> Scene {
    let mut s = Scene::new();
    let f = s.add_mesh(plane(25.0, 0.0));
    let fm = s.add_material(floor);
    s.add_instance(Instance {
        mesh: f,
        material: fm,
        transform: IDENTITY,
    })
    .unwrap();
    let l = s.add_mesh(light);
    let lm = s.add_material(emitter(le));
    s.add_instance(Instance {
        mesh: l,
        material: lm,
        transform: light_transform,
    })
    .unwrap();
    s.set_camera(camera_at_z(0.5));
    s
}

fn center_pixel_radiance(ctx: &MetalContext, scene: &Scene) -> f32 {
    let img = Renderer::new(ctx, scene)
        .unwrap()
        .render(65, 65, 64)
        .unwrap();
    center_mean(&img, 65, 5)
}

#[test]
fn large_area_light_over_a_floor_gives_rho_times_radiance() {
    let Some(ctx) = context() else { return };
    // Parallel planes: irradiance pi * Le * F with a view factor F = 0.999 for a 50 x 50 emitter at height 1.
    let mut up = IDENTITY;
    up[2][3] = 1.0;
    let scene = floor_with_emitter(material([0.5; 3], [0.0; 3]), plane(25.0, 0.0), up, 2.0);
    let got = center_pixel_radiance(&ctx, &scene);
    assert!((got - 0.5 * 2.0 * 0.999).abs() < 0.015, "{got}");
}

#[test]
fn small_area_light_matches_the_square_form_factor() {
    let Some(ctx) = context() else { return };
    // 0.2 x 0.2 emitter at height 1, placed by an instance transform. Point below its center:
    // E = 4 pi Le F with F the corner form factor of a 0.1 x 0.1 rectangle; L = rho E / pi.
    let a = 0.1f64;
    let root = (1.0 + a * a).sqrt();
    let corner = (a / root) * (a / root).atan() / std::f64::consts::PI;
    let (rho, le) = (1.0f32, 50.0f32);
    let expected = rho as f64 * 4.0 * corner * le as f64;
    let mut up = IDENTITY;
    up[2][3] = 1.0;
    let scene = floor_with_emitter(material([rho; 3], [0.0; 3]), plane(0.1, 0.0), up, le);
    let got = center_pixel_radiance(&ctx, &scene) as f64;
    assert!(
        (got - expected).abs() / expected < 0.03,
        "{got} vs {expected}"
    );
}

#[test]
fn glossy_metal_reflects_a_large_area_light_without_gain_or_loss() {
    let Some(ctx) = context() else { return };
    let mut up = IDENTITY;
    up[2][3] = 1.0;
    // Light sampling and BSDF sampling must agree at every roughness, or the weights would bias this.
    for (roughness, lo) in [(0.0, 0.995), (0.3, 0.95), (0.5, 0.9)] {
        let metal = bsdf(BaseBsdf {
            base_color: [1.0; 3],
            metallic: 1.0,
            roughness,
            ..BaseBsdf::default()
        });
        let scene = floor_with_emitter(metal, plane(25.0, 0.0), up, 1.0);
        let got = center_pixel_radiance(&ctx, &scene);
        assert!(got > lo && got < 1.005, "roughness {roughness}: {got}");
    }
}

fn hdri(w: u32, h: u32, f: impl Fn(u32, u32) -> f32) -> Image {
    let pixels = (0..h)
        .flat_map(|y| (0..w).map(move |x| (x, y)))
        .map(|(x, y)| [f(x, y); 3])
        .collect();
    Image::new(w, h, pixels).unwrap()
}

#[test]
fn constant_environment_map_is_a_white_furnace() {
    let Some(ctx) = context() else { return };
    // A uniform lat-long map must behave like the uniform sky: light sampling and BSDF sampling
    // share the weight, so the combined estimate has to stay exactly unbiased.
    let mut s = Scene::new();
    let mesh = s.add_mesh(cube(0.5));
    let mat = s.add_material(material([1.0; 3], [0.0; 3]));
    s.add_instance(Instance {
        mesh,
        material: mat,
        transform: IDENTITY,
    })
    .unwrap();
    let image = s.add_image(hdri(32, 16, |_, _| 1.0));
    s.add_light(Light::EnvironmentMap { image, scale: 1.0 });
    s.set_camera(camera_at_z(3.0));
    let img = Renderer::new(&ctx, &s).unwrap().render(32, 32, 64).unwrap();
    let got = center_mean(&img, 32, 16);
    assert!((got - 1.0).abs() < 0.015, "{got}");
    assert!(
        (mean(&img) - 1.0).abs() < 0.015,
        "background {}",
        mean(&img)
    );
}

#[test]
fn bright_texel_is_importance_sampled() {
    let Some(ctx) = context() else { return };
    // One texel carries all the light. It subtends ~0.007 sr, so plain BSDF sampling would hit it in
    // about 0.2% of paths and leave 64 samples nearly black; importance sampling must find it.
    let (w, h, i, j, radiance) = (64u32, 32u32, 0u32, 8u32, 200.0f32);
    let mut s = Scene::new();
    let floor = s.add_mesh(plane(25.0, 0.0));
    let mat = s.add_material(material([1.0; 3], [0.0; 3]));
    s.add_instance(Instance {
        mesh: floor,
        material: mat,
        transform: IDENTITY,
    })
    .unwrap();
    let image = s.add_image(hdri(
        w,
        h,
        |x, y| if (x, y) == (i, j) { radiance } else { 0.0 },
    ));
    s.add_light(Light::EnvironmentMap { image, scale: 1.0 });
    s.set_camera(camera_at_z(3.0));

    // Irradiance on the +z-facing floor: integrate cos(theta_floor) over the texel's solid angle.
    let n = 64;
    let mut e = 0.0f64;
    for a in 0..n {
        for b in 0..n {
            let u = (f64::from(i) + (f64::from(a) + 0.5) / f64::from(n)) / f64::from(w);
            let v = (f64::from(j) + (f64::from(b) + 0.5) / f64::from(n)) / f64::from(h);
            let (phi, theta) = (
                (u - 0.5) * 2.0 * std::f64::consts::PI,
                v * std::f64::consts::PI,
            );
            let d_omega = theta.sin()
                * (std::f64::consts::PI / f64::from(h * n))
                * (2.0 * std::f64::consts::PI / f64::from(w * n));
            e += f64::from(radiance) * (-theta.sin() * phi.cos()) * d_omega;
        }
    }
    let expected = e / std::f64::consts::PI; // albedo 1
    assert!(expected > 0.1, "test setup: {expected}");

    let img = Renderer::new(&ctx, &s).unwrap().render(65, 65, 64).unwrap();
    let got = f64::from(center_mean(&img, 65, 5));
    assert!(
        (got - expected).abs() / expected < 0.03,
        "{got} vs {expected}"
    );
}

#[test]
fn invalid_environment_maps_are_rejected() {
    let Some(ctx) = context() else { return };
    let tri_scene = |lights: &dyn Fn(&mut Scene)| {
        let mut s = sky_scene(cube(0.5), material([1.0; 3], [0.0; 3]), 3.0);
        lights(&mut s);
        s
    };
    // An image id that belongs to a different scene.
    let mut other = Scene::new();
    let foreign = other.add_image(hdri(2, 2, |_, _| 1.0));
    let dangling = tri_scene(&|s| {
        s.add_light(Light::EnvironmentMap {
            image: foreign,
            scale: 1.0,
        });
    });
    assert!(matches!(
        Renderer::new(&ctx, &dangling),
        Err(Error::Scene(_))
    ));

    let two = tri_scene(&|s| {
        let image = s.add_image(hdri(2, 2, |_, _| 1.0));
        s.add_light(Light::EnvironmentMap { image, scale: 1.0 });
        s.add_light(Light::EnvironmentMap { image, scale: 2.0 });
    });
    assert!(matches!(Renderer::new(&ctx, &two), Err(Error::Scene(_))));
}

/// `half` x `half` square in the z = 0 plane whose uv runs over [0, repeat]; v grows downward like
/// the image rows (glTF convention), so the top-left corner has uv (0, 0).
fn textured_plane(half: f32, repeat: f32) -> Mesh {
    let h = half;
    Mesh::new(
        vec![[-h, -h, 0.0], [h, -h, 0.0], [h, h, 0.0], [-h, h, 0.0]],
        None,
        Some(vec![
            [0.0, repeat],
            [repeat, repeat],
            [repeat, 0.0],
            [0.0, 0.0],
        ]),
        vec![0, 1, 2, 0, 2, 3],
    )
    .unwrap()
}

fn texture_scene(
    mesh: Mesh,
    image: Image,
    base: impl FnOnce(verion_scene::ImageId) -> BaseBsdf,
) -> Scene {
    let mut s = Scene::new();
    let img = s.add_image(image);
    let mesh = s.add_mesh(mesh);
    let mat = s.add_material(bsdf(base(img)));
    s.add_instance(Instance {
        mesh,
        material: mat,
        transform: IDENTITY,
    })
    .unwrap();
    s.add_light(Light::Environment { color: [1.0; 3] });
    s.set_camera(camera_at_z(3.0));
    s
}

fn lambert(base_color: [f32; 3], texture: verion_scene::ImageId) -> BaseBsdf {
    BaseBsdf {
        base_color,
        ior: 1.0,
        base_color_texture: Some(texture),
        ..BaseBsdf::default()
    }
}

#[test]
fn base_color_texels_land_where_the_uvs_say() {
    let Some(ctx) = context() else { return };
    // 2x2 texture: red, green / blue, grey. The plane spans [-0.5, 0.5] and maps to uv [0, 1].
    let tex = Image::new(
        2,
        2,
        vec![[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0], [0.5; 3]],
    )
    .unwrap();
    let s = texture_scene(textured_plane(0.5, 1.0), tex, |t| lambert([1.0; 3], t));
    let img = Renderer::new(&ctx, &s).unwrap().render(65, 65, 64).unwrap();
    // World (+-0.25, +-0.25) is pixel 32.5 +- 0.25 / (3 tan 0.4) * 32.5, about 26 and 39.
    let at = |x: usize, y: usize| img[y * 65 + x];
    let close = |a: [f32; 3], b: [f32; 3]| a.iter().zip(b).all(|(p, q)| (p - q).abs() < 0.1);
    assert!(close(at(26, 26), [1.0, 0.0, 0.0]), "{:?}", at(26, 26));
    assert!(close(at(39, 26), [0.0, 1.0, 0.0]), "{:?}", at(39, 26));
    assert!(close(at(26, 39), [0.0, 0.0, 1.0]), "{:?}", at(26, 39));
    assert!(close(at(39, 39), [0.5; 3]), "{:?}", at(39, 39));
}

#[test]
fn minified_checkerboard_averages_through_the_mip_chain() {
    let Some(ctx) = context() else { return };
    // 8x8 one-texel checkerboard repeated 256 times over the floor: each pixel covers ~8 texels.
    // At one sample per pixel only a correct mip level gives 0.5; level 0 would alternate 0 and 1.
    let pixels = (0..64)
        .map(|i| {
            if (i % 8 + i / 8) % 2 == 0 {
                [1.0; 3]
            } else {
                [0.0; 3]
            }
        })
        .collect();
    let tex = Image::new(8, 8, pixels).unwrap();
    let s = texture_scene(textured_plane(5.0, 256.0), tex, |t| lambert([1.0; 3], t));
    let img = Renderer::new(&ctx, &s).unwrap().render(64, 64, 1).unwrap();
    let worst = img
        .iter()
        .map(|p| (p[0] - 0.5).abs())
        .fold(0.0f32, f32::max);
    assert!(worst < 0.05, "worst deviation {worst}");
}

#[test]
fn metallic_roughness_texture_scales_the_factors() {
    let Some(ctx) = context() else { return };
    // Factors say rough dielectric; the texture (green 0, blue 1) turns that into a smooth metal,
    // which reflects the sky at its base color 0.5.
    let tex = Image::new(1, 1, vec![[0.0, 0.0, 1.0]]).unwrap();
    let s = texture_scene(textured_plane(5.0, 1.0), tex, |t| BaseBsdf {
        base_color: [0.5; 3],
        metallic: 1.0,
        roughness: 1.0,
        metallic_roughness_texture: Some(t),
        ..BaseBsdf::default()
    });
    let img = Renderer::new(&ctx, &s).unwrap().render(32, 32, 16).unwrap();
    let got = center_mean(&img, 32, 16);
    assert!((got - 0.5).abs() < 0.01, "{got}");
}

#[test]
fn emission_texture_scales_the_emitted_radiance() {
    let Some(ctx) = context() else { return };
    let tex = Image::new(1, 1, vec![[0.25; 3]]).unwrap();
    let s = texture_scene(textured_plane(5.0, 1.0), tex, |t| BaseBsdf {
        base_color: [0.0; 3],
        emission: [1.0; 3],
        ior: 1.0,
        emission_texture: Some(t),
        ..BaseBsdf::default()
    });
    let img = Renderer::new(&ctx, &s).unwrap().render(32, 32, 8).unwrap();
    // The sky adds nothing (albedo 0), so the plane shows exactly factor * texture.
    assert!((center_mean(&img, 32, 16) - 0.25).abs() < 1e-3);
}

#[test]
fn missing_texture_image_is_rejected() {
    let Some(ctx) = context() else { return };
    let mut other = Scene::new();
    let foreign = other.add_image(Image::new(1, 1, vec![[1.0; 3]]).unwrap());
    let mut s = sky_scene(cube(0.5), bsdf(lambert([1.0; 3], foreign)), 3.0);
    s.add_light(Light::Environment { color: [0.0; 3] });
    assert!(matches!(Renderer::new(&ctx, &s), Err(Error::Scene(_))));
}
