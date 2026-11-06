//! ReSTIR DI (REQ-ACC-002). Needs a Vulkan ray-tracing GPU, so these are ignored by default (`mise run test:gpu`).
#![cfg(not(target_os = "macos"))]

use verion_gpu::{Accumulation as _, Integrator, RayTracingBackend as _, Restir};
use verion_gpu_vulkan::{Renderer, VulkanContext};
use verion_scene::{BaseBsdf, Camera, IDENTITY, Instance, Material, Mesh, Scene};

fn quads(cells: &[([f32; 3], f32)]) -> Mesh {
    let mut p = Vec::new();
    let mut i = Vec::new();
    for ([x, y, z], h) in cells {
        let b = p.len() as u32;
        p.extend([
            [x - h, y - h, *z],
            [x + h, y - h, *z],
            [x + h, y + h, *z],
            [x - h, y + h, *z],
        ]);
        i.extend([b, b + 1, b + 2, b, b + 2, b + 3]);
    }
    Mesh::new(p, None, None, i).unwrap()
}

/// A wall at z = 0 lit by 64 small emitters of different sizes at z = 0.8, with a cube-ish
/// blocker between them, seen from z = 3.
fn many_lights(roughness: f32, metallic: f32) -> Scene {
    let mut s = Scene::new();
    let wall = s.add_mesh(quads(&[([0.0, 0.0, 0.0], 2.0)]));
    let lights: Vec<_> = (0..64)
        .map(|k| {
            let (gx, gy) = ((k % 8) as f32, (k / 8) as f32);
            (
                [-1.4 + gx * 0.4, -1.4 + gy * 0.4, 0.8],
                0.03 + 0.02 * ((k * 7 % 5) as f32),
            )
        })
        .collect();
    let lamps = s.add_mesh(quads(&lights));
    let blocker = s.add_mesh(quads(&[([0.2, 0.1, 0.4], 0.5)]));
    let mat = |base: BaseBsdf| Material {
        base,
        ..Material::default()
    };
    let wall_m = s.add_material(mat(BaseBsdf {
        base_color: [0.7; 3],
        roughness,
        metallic,
        ior: 1.0,
        ..BaseBsdf::default()
    }));
    let glow = s.add_material(mat(BaseBsdf {
        base_color: [0.0; 3],
        emission: [40.0; 3],
        roughness,
        metallic,
        ..BaseBsdf::default()
    }));
    let dark = s.add_material(mat(BaseBsdf {
        base_color: [0.1; 3],
        roughness,
        metallic,
        ..BaseBsdf::default()
    }));
    for (mesh, material) in [(wall, wall_m), (lamps, glow), (blocker, dark)] {
        s.add_instance(Instance {
            mesh,
            material,
            transform: IDENTITY,
        })
        .unwrap();
    }
    let mut cam = Camera::default();
    cam.transform[2][3] = 3.0;
    s.set_camera(cam);
    s
}

fn render(r: &Renderer, spp: u32) -> Vec<[f32; 3]> {
    let mut acc = r.new_accumulation(64, 64, false).unwrap();
    r.accumulate(&mut acc, spp).unwrap();
    acc.mean()
}

fn mean(img: &[[f32; 3]]) -> f32 {
    img.iter().map(|p| p[1]).sum::<f32>() / img.len() as f32
}

#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn converges_to_the_light_sampled_image() {
    let ctx = VulkanContext::new().unwrap();
    let mut r = Renderer::new(&ctx, &many_lights(0.9, 0.0)).unwrap();
    let plain = mean(&render(&r, 1024));
    r.set_restir(Some(Restir::default()));
    let resampled = mean(&render(&r, 1024));
    let err = (resampled - plain).abs() / plain;
    assert!(err < 0.03, "plain {plain}, restir {resampled}, error {err}");
}

#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn both_integrators_draw_the_same_restir_image() {
    let ctx = VulkanContext::new().unwrap();
    let mut r = Renderer::new(&ctx, &many_lights(0.9, 0.0)).unwrap();
    r.set_restir(Some(Restir::default()));
    let mega = render(&r, 16);
    r.set_integrator(Integrator::Wavefront);
    assert_eq!(mega, render(&r, 16));
}

#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn sharp_surfaces_fall_back_to_light_sampling() {
    let ctx = VulkanContext::new().unwrap();
    let mut r = Renderer::new(&ctx, &many_lights(0.05, 1.0)).unwrap();
    let plain = render(&r, 8);
    r.set_restir(Some(Restir::default()));
    assert_eq!(plain, render(&r, 8));
}

#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn switching_mid_accumulation_is_an_error() {
    let ctx = VulkanContext::new().unwrap();
    let mut r = Renderer::new(&ctx, &many_lights(0.9, 0.0)).unwrap();
    let mut acc = r.new_accumulation(16, 16, false).unwrap();
    r.accumulate(&mut acc, 1).unwrap();
    r.set_restir(Some(Restir::default()));
    assert!(r.accumulate(&mut acc, 1).is_err());
}

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

/// A closed room of rough walls lit by 16 small panels and a rough ball, seen from inside:
/// most of what the camera sees is indirect light.
fn closed_room(roughness: f32) -> Scene {
    let mut s = Scene::new();
    let room = s.add_mesh(cube(1.5));
    let ball = s.add_mesh(cube(0.4));
    let panels: Vec<_> = (0..16)
        .map(|k| {
            let (gx, gz) = ((k % 4) as f32, (k / 4) as f32);
            let mut q = quads(&[([-0.6 + gx * 0.4, -0.6 + gz * 0.4, 0.0], 0.06)]);
            // Lay the panel flat under the ceiling.
            let p: Vec<[f32; 3]> = q.positions().iter().map(|v| [v[0], 1.45, v[1]]).collect();
            q = Mesh::new(p, None, None, q.indices().to_vec()).unwrap();
            q
        })
        .collect();
    let mut positions = Vec::new();
    let mut indices = Vec::new();
    for q in &panels {
        let b = positions.len() as u32;
        positions.extend_from_slice(q.positions());
        indices.extend(q.indices().iter().map(|i| i + b));
    }
    let lamps = s.add_mesh(Mesh::new(positions, None, None, indices).unwrap());
    let mat = |base: BaseBsdf| Material {
        base,
        ..Material::default()
    };
    let walls = s.add_material(mat(BaseBsdf {
        base_color: [0.7, 0.65, 0.6],
        roughness,
        ior: 1.0,
        ..BaseBsdf::default()
    }));
    let glow = s.add_material(mat(BaseBsdf {
        base_color: [0.0; 3],
        emission: [30.0; 3],
        roughness,
        ..BaseBsdf::default()
    }));
    for (mesh, material) in [(room, walls), (ball, walls), (lamps, glow)] {
        s.add_instance(Instance {
            mesh,
            material,
            transform: IDENTITY,
        })
        .unwrap();
    }
    let mut cam = Camera::default();
    cam.transform[2][3] = 1.4;
    s.set_camera(cam);
    s
}

fn gi() -> Restir {
    Restir {
        gi: true,
        ..Restir::default()
    }
}

#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn gi_converges_to_the_path_traced_image() {
    let ctx = VulkanContext::new().unwrap();
    let mut r = Renderer::new(&ctx, &closed_room(0.9)).unwrap();
    let plain = mean(&render(&r, 1024));
    r.set_restir(Some(gi()));
    let resampled = mean(&render(&r, 1024));
    let err = (resampled - plain).abs() / plain;
    assert!(err < 0.03, "plain {plain}, gi {resampled}, error {err}");
}

#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn gi_draws_the_same_image_with_both_integrators() {
    let ctx = VulkanContext::new().unwrap();
    let mut r = Renderer::new(&ctx, &closed_room(0.9)).unwrap();
    r.set_restir(Some(gi()));
    let mega = render(&r, 16);
    r.set_integrator(Integrator::Wavefront);
    assert_eq!(mega, render(&r, 16));
}

#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn gi_leaves_sharp_surfaces_alone() {
    let ctx = VulkanContext::new().unwrap();
    let mut r = Renderer::new(&ctx, &closed_room(0.05)).unwrap();
    let plain = render(&r, 8);
    r.set_restir(Some(gi()));
    assert_eq!(plain, render(&r, 8));
}
