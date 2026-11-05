//! Needs a Metal RT device; skips on machines without one (e.g. CI runners).
#![cfg(target_os = "macos")]

use verion_gpu_metal::{Error, MetalContext, Renderer};
use verion_scene::{BaseBsdf, Camera, IDENTITY, Image, Instance, Material, Mesh, Scene};

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

fn add(s: &mut Scene, positions: Vec<[f32; 3]>, uvs: Option<Vec<[f32; 2]>>, material: Material) {
    let mesh = s.add_mesh(Mesh::new(positions, None, uvs, vec![0, 1, 2]).unwrap());
    let material = s.add_material(material);
    s.add_instance(Instance {
        mesh,
        material,
        transform: IDENTITY,
    })
    .unwrap();
}

fn colored(base_color: [f32; 3]) -> Material {
    Material {
        base: BaseBsdf {
            base_color,
            ..BaseBsdf::default()
        },
        ..Material::default()
    }
}

/// Camera at z = 3 looking down -z. A small triangle at z = 0 covers the centre; a large one at
/// z = -1 covers the right of the frame (but not the centre).
fn scene(near: Material) -> Scene {
    let mut s = Scene::new();
    let tri = |z: f32, a: [f32; 2], b: [f32; 2], c: [f32; 2]| {
        vec![[a[0], a[1], z], [b[0], b[1], z], [c[0], c[1], z]]
    };
    add(
        &mut s,
        tri(0.0, [-0.5, -0.5], [0.5, -0.5], [0.0, 0.5]),
        Some(vec![[0.0, 0.0]; 3]),
        near,
    );
    add(
        &mut s,
        tri(-1.0, [0.8, -2.0], [5.0, -2.0], [0.8, 6.0]),
        None,
        colored([0.9, 0.1, 0.3]),
    );
    let mut cam = Camera::default();
    cam.transform[2][3] = 3.0;
    s.set_camera(cam);
    s
}

const N: usize = 64;

#[test]
fn reports_albedo_depth_and_ids() {
    let Some(ctx) = context() else { return };
    let scene = scene(colored([0.2, 0.4, 0.6]));
    let aov = Renderer::new(&ctx, &scene)
        .unwrap()
        .render_aovs(N as u32, N as u32)
        .unwrap();
    let at = |x: usize, y: usize| y * N + x;

    let c = at(N / 2, N / 2);
    assert_eq!(aov.object_id[c], 1);
    assert_eq!(aov.material_id[c], 1);
    assert_eq!(aov.albedo[c], [0.2, 0.4, 0.6]);
    assert!((aov.depth[c] - 3.0).abs() < 1e-3, "{}", aov.depth[c]);

    // Right of centre: only the far triangle. Depth is along the forward axis, so every pixel on
    // the plane z = -1 reads 4 whatever its ray angle.
    let r = at(54, N / 2);
    assert_eq!(aov.object_id[r], 2);
    assert_eq!(aov.material_id[r], 2);
    assert_eq!(aov.albedo[r], [0.9, 0.1, 0.3]);
    assert!((aov.depth[r] - 4.0).abs() < 1e-3, "{}", aov.depth[r]);

    // Top-left corner: nothing there.
    let m = at(1, 1);
    assert_eq!(
        (
            aov.object_id[m],
            aov.material_id[m],
            aov.albedo[m],
            aov.depth[m]
        ),
        (0, 0, [0.0; 3], 0.0)
    );
}

#[test]
fn albedo_multiplies_the_base_color_texture() {
    let Some(ctx) = context() else { return };
    let mut s = Scene::new();
    let image = s.add_image(Image::new(2, 2, vec![[0.5, 1.0, 0.25]; 4]).unwrap());
    let textured = Material {
        base: BaseBsdf {
            base_color: [0.8; 3],
            base_color_texture: Some(image),
            ..BaseBsdf::default()
        },
        ..Material::default()
    };
    let triangle = vec![[-0.5, -0.5, 0.0], [0.5, -0.5, 0.0], [0.0, 0.5, 0.0]];
    add(&mut s, triangle, Some(vec![[0.0, 0.0]; 3]), textured);
    let mut cam = Camera::default();
    cam.transform[2][3] = 3.0;
    s.set_camera(cam);

    let aov = Renderer::new(&ctx, &s)
        .unwrap()
        .render_aovs(N as u32, N as u32)
        .unwrap();
    let a = aov.albedo[N / 2 * N + N / 2];
    for (got, want) in a.iter().zip([0.4, 0.8, 0.2]) {
        assert!((got - want).abs() < 1e-4, "{a:?}");
    }
}
