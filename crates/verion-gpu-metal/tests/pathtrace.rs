//! Needs a Metal RT device; skips on machines without one (e.g. CI runners).
#![cfg(target_os = "macos")]

use std::collections::HashMap;
use verion_gpu_metal::{Error, MetalContext, Renderer};

use verion_scene::{BaseBsdf, Camera, IDENTITY, Instance, Light, Material, Mesh, Scene};

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
