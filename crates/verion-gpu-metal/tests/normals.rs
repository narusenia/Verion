//! Needs a Metal RT device; skips on machines without one (e.g. CI runners).
#![cfg(target_os = "macos")]

use verion_gpu_metal::{Error, MetalContext, Renderer};
use verion_scene::{Camera, IDENTITY, Instance, Material, Mesh, Scene, Transform};

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

/// One small triangle at the origin, seen by a camera at z = 3 looking down -z.
fn scene(indices: [u32; 3], transform: Transform) -> Scene {
    let mut s = Scene::new();
    let positions = vec![[-0.5, -0.5, 0.0], [0.5, -0.5, 0.0], [0.0, 0.5, 0.0]];
    let mesh = s.add_mesh(Mesh::new(positions, None, None, indices.to_vec()).unwrap());
    let material = s.add_material(Material::default());
    s.add_instance(Instance {
        mesh,
        material,
        transform,
    })
    .unwrap();
    let mut cam = Camera::default();
    cam.transform[2][3] = 3.0;
    s.set_camera(cam);
    s
}

fn center(img: &[[f32; 3]], w: usize, h: usize) -> [f32; 3] {
    img[h / 2 * w + w / 2]
}

fn assert_close(a: [f32; 3], b: [f32; 3]) {
    assert!(
        a.iter().zip(b).all(|(x, y)| (x - y).abs() < 1e-4),
        "{a:?} != {b:?}"
    );
}

#[test]
fn hit_pixel_has_normal_and_background_is_zero() {
    let Some(ctx) = context() else { return };
    let r = Renderer::new(&ctx, &scene([0, 1, 2], IDENTITY)).unwrap();
    let img = r.render_normals(64, 64).unwrap();
    assert_eq!(img.len(), 64 * 64);
    assert_close(center(&img, 64, 64), [0.0, 0.0, 1.0]);
    assert_eq!(img[0], [0.0; 3]);
}

#[test]
fn back_faces_are_flipped_toward_the_viewer() {
    let Some(ctx) = context() else { return };
    let r = Renderer::new(&ctx, &scene([0, 2, 1], IDENTITY)).unwrap();
    assert_close(
        center(&r.render_normals(32, 32).unwrap(), 32, 32),
        [0.0, 0.0, 1.0],
    );
}

#[test]
fn instance_rotation_reaches_the_normal() {
    let Some(ctx) = context() else { return };
    let (s, c) = std::f32::consts::FRAC_PI_4.sin_cos();
    // Rotate 45 degrees about x: (0, 0, 1) -> (0, -sin, cos).
    let rot = [[1.0, 0.0, 0.0, 0.0], [0.0, c, -s, 0.0], [0.0, s, c, 0.0]];
    let r = Renderer::new(&ctx, &scene([0, 1, 2], rot)).unwrap();
    assert_close(
        center(&r.render_normals(32, 32).unwrap(), 32, 32),
        [0.0, -s, c],
    );
}

#[test]
fn empty_scene_and_zero_size_are_errors() {
    let Some(ctx) = context() else { return };
    assert!(matches!(
        Renderer::new(&ctx, &Scene::new()),
        Err(Error::Scene(_))
    ));
    let r = Renderer::new(&ctx, &scene([0, 1, 2], IDENTITY)).unwrap();
    assert!(matches!(r.render_normals(0, 8), Err(Error::Scene(_))));
}
