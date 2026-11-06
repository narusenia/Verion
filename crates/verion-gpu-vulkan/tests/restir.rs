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
    room_with(roughness, false)
}

/// `closed_room` with a strongly dispersive glass block in the middle.
fn room_with(roughness: f32, glass: bool) -> Scene {
    let glass = glass.then_some((0.35, [-0.7, -0.9, 0.0]));
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
    let mut parts = vec![
        (room, walls, IDENTITY),
        (ball, walls, IDENTITY),
        (lamps, glow, IDENTITY),
    ];
    if let Some((size, pos)) = glass {
        let block = s.add_mesh(cube(size));
        let dispersive = s.add_material(mat(BaseBsdf {
            base_color: [1.0; 3],
            transmission: 1.0,
            roughness: 0.0,
            ior: 1.6,
            dispersion: 8.0,
            ..BaseBsdf::default()
        }));
        let mut at = IDENTITY;
        at[0][3] = pos[0];
        at[1][3] = pos[1];
        at[2][3] = pos[2];
        parts.push((block, dispersive, at));
    }
    for (mesh, material, transform) in parts {
        s.add_instance(Instance {
            mesh,
            material,
            transform,
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

/// Largest relative difference between the 8x8 block means of two images, per color channel
/// (the blocks average the sample noise away, a stain stays).
fn worst_block(a: &[[f32; 3]], b: &[[f32; 3]]) -> f32 {
    let mut worst = 0.0f32;
    for by in 0..8 {
        for bx in 0..8 {
            for c in 0..3 {
                let (mut sa, mut sb) = (0.0, 0.0);
                for y in 0..8 {
                    for x in 0..8 {
                        let i = (by * 8 + y) * 64 + bx * 8 + x;
                        sa += a[i][c];
                        sb += b[i][c];
                    }
                }
                worst = worst.max((sa - sb).abs() / sb.max(1.0e-3));
            }
        }
    }
    worst
}

#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn gi_leaves_no_stains_behind_dispersive_glass() {
    let ctx = VulkanContext::new().unwrap();
    let mut r = Renderer::new(&ctx, &room_with(0.9, true)).unwrap();
    let plain = render(&r, 2048);
    r.set_restir(Some(gi()));
    let resampled = render(&r, 2048);
    let worst = worst_block(&resampled, &plain);
    assert!(worst < 0.15, "worst block differs by {worst}");
}

/// Largest difference of the red-blue balance between the 8x8 block means of two images.
fn worst_chroma(a: &[[f32; 3]], b: &[[f32; 3]]) -> f32 {
    let balance = |v: [f32; 3]| (v[0] - v[2]) / (v[0] + v[2]).max(1.0e-4);
    let mut worst = 0.0f32;
    for by in 0..8 {
        for bx in 0..8 {
            let (mut sa, mut sb) = ([0.0f32; 3], [0.0f32; 3]);
            for y in 0..8 {
                for x in 0..8 {
                    let i = (by * 8 + y) * 64 + bx * 8 + x;
                    for c in 0..3 {
                        sa[c] += a[i][c];
                        sb[c] += b[i][c];
                    }
                }
            }
            worst = worst.max((balance(sa) - balance(sb)).abs());
        }
    }
    worst
}

/// The Cornell Box with its glass sphere set to a high index and strong dispersion: reusing the
/// paths that went through the glass left colored stains on the walls (the first versions of GI
/// measured 0.50 and 0.26 here; plain path tracing 0.15 and 0.04).
#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn gi_leaves_no_stains_on_the_cornell_box_walls() {
    let ctx = VulkanContext::new().unwrap();
    let path =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../scenes/cornell_box.gltf");
    let mut scene = verion_render_io::load_gltf_in(&path, verion_scene::ColorSpace::LinearRec709)
        .unwrap()
        .scene;
    let id = scene.material_id(5).unwrap();
    let mut glass = scene.materials()[5].clone();
    glass.base.ior = 2.4;
    glass.base.dispersion = 20.0;
    scene.set_material(id, glass);
    let mut r = Renderer::new(&ctx, &scene).unwrap();
    let reference = render(&r, 4096);
    r.set_restir(Some(gi()));
    let img = render(&r, 256);
    let (block, chroma) = (
        worst_block(&img, &reference),
        worst_chroma(&img, &reference),
    );
    assert!(block < 0.3, "worst block differs by {block}");
    assert!(chroma < 0.15, "worst color balance differs by {chroma}");
}
