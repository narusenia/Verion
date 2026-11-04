//! Needs a Metal RT device; skips on machines without one (e.g. CI runners).
#![cfg(target_os = "macos")]

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

fn material(base_color: [f32; 3], emission: [f32; 3]) -> Material {
    Material {
        base: BaseBsdf {
            base_color,
            emission,
            ..BaseBsdf::default()
        },
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
