//! Differential scene updates (REQ-ACC-003): an updated renderer must draw exactly what a renderer
//! built from scratch on the edited scene draws, and must not rebuild what the edit leaves alone.
//! Needs a Vulkan ray-tracing GPU, so these are ignored by default (`mise run test:gpu`).
#![cfg(not(target_os = "macos"))]

use verion_gpu::{Accumulation as _, RayTracingBackend as _};
use verion_gpu_vulkan::{Renderer, VulkanContext};
use verion_scene::{
    BaseBsdf, Camera, IDENTITY, Instance, InstanceId, Light, Material, MaterialId, Mesh, MeshId,
    Scene,
};

fn cube(half: f32, y: f32) -> Mesh {
    let h = half;
    let positions = vec![
        [-h, y - h, -h],
        [h, y - h, -h],
        [h, y + h, -h],
        [-h, y + h, -h],
        [-h, y - h, h],
        [h, y - h, h],
        [h, y + h, h],
        [-h, y + h, h],
    ];
    #[rustfmt::skip]
    let indices = vec![
        0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7, 0, 1, 5, 0, 5, 4,
        2, 3, 7, 2, 7, 6, 1, 2, 6, 1, 6, 5, 0, 3, 7, 0, 7, 4,
    ];
    Mesh::new(positions, None, None, indices).unwrap()
}

fn diffuse(color: [f32; 3], emission: [f32; 3]) -> Material {
    Material {
        base: BaseBsdf {
            base_color: color,
            emission,
            ior: 1.0,
            ..BaseBsdf::default()
        },
        ..Material::default()
    }
}

struct Room {
    scene: Scene,
    walls: MaterialId,
    lamp_mesh: MeshId,
    lamp: InstanceId,
}

/// A closed room lit by a small emissive cube and a point light, seen from inside.
fn room() -> Room {
    let mut scene = Scene::new();
    let room_mesh = scene.add_mesh(cube(1.0, 0.0));
    let lamp_mesh = scene.add_mesh(cube(0.1, 0.0));
    let walls = scene.add_material(diffuse([0.6; 3], [0.0; 3]));
    let glow = scene.add_material(diffuse([0.0; 3], [8.0; 3]));
    scene
        .add_instance(Instance {
            mesh: room_mesh,
            material: walls,
            transform: IDENTITY,
        })
        .unwrap();
    let mut at = IDENTITY;
    at[1][3] = 0.7;
    let lamp = scene
        .add_instance(Instance {
            mesh: lamp_mesh,
            material: glow,
            transform: at,
        })
        .unwrap();
    scene.add_light(Light::Point {
        position: [0.0, -0.5, 0.0],
        color: [1.0; 3],
        intensity: 0.5,
    });
    let mut cam = Camera::default();
    cam.transform[2][3] = 0.95;
    scene.set_camera(cam);
    scene.take_changes();
    Room {
        scene,
        walls,
        lamp_mesh,
        lamp,
    }
}

fn render(r: &Renderer) -> Vec<[f32; 3]> {
    let mut acc = r.new_accumulation(48, 48, false).unwrap();
    r.accumulate(&mut acc, 8).unwrap();
    acc.mean()
}

/// Applies the pending edits to `r` and checks the result against a fresh renderer.
fn update_matches_fresh(
    ctx: &VulkanContext,
    r: &mut Renderer,
    scene: &mut Scene,
) -> verion_gpu::UpdateReport {
    let before = render(r);
    let changes = scene.take_changes();
    let report = r.update(scene, &changes).unwrap();
    let after = render(r);
    let fresh = render(&Renderer::new(ctx, scene).unwrap());
    assert_eq!(after, fresh, "the update differs from a rebuild");
    assert_ne!(before, after, "the edit changed nothing");
    report
}

#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn a_material_edit_reuses_every_acceleration_structure() {
    let ctx = VulkanContext::new().unwrap();
    let mut room = room();
    let mut r = Renderer::new(&ctx, &room.scene).unwrap();
    // Red walls: the floor patch the camera sees is not edited, but its indirect light is.
    room.scene
        .set_material(room.walls, diffuse([0.9, 0.1, 0.1], [0.0; 3]));
    let report = update_matches_fresh(&ctx, &mut r, &mut room.scene);
    assert_eq!((report.blases_built, report.tlas_built), (0, false));
}

#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn a_light_edit_reuses_every_acceleration_structure() {
    let ctx = VulkanContext::new().unwrap();
    let mut room = room();
    let mut r = Renderer::new(&ctx, &room.scene).unwrap();
    let id = room.scene.light_id(0).unwrap();
    room.scene.set_light(
        id,
        Light::Point {
            position: [0.0, -0.5, 0.0],
            color: [1.0, 0.5, 0.2],
            intensity: 2.0,
        },
    );
    let report = update_matches_fresh(&ctx, &mut r, &mut room.scene);
    assert_eq!((report.blases_built, report.tlas_built), (0, false));
}

#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn moving_an_instance_rebuilds_only_the_tlas() {
    let ctx = VulkanContext::new().unwrap();
    let mut room = room();
    let mut r = Renderer::new(&ctx, &room.scene).unwrap();
    let mut inst = room.scene.instances()[room.lamp.index()];
    inst.transform[0][3] = 0.4;
    room.scene.set_instance(room.lamp, inst).unwrap();
    let report = update_matches_fresh(&ctx, &mut r, &mut room.scene);
    assert_eq!((report.blases_built, report.tlas_built), (0, true));
}

#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn deforming_a_mesh_rebuilds_only_its_blas() {
    let ctx = VulkanContext::new().unwrap();
    let mut room = room();
    let mut r = Renderer::new(&ctx, &room.scene).unwrap();
    room.scene.set_mesh(room.lamp_mesh, cube(0.3, 0.0));
    let report = update_matches_fresh(&ctx, &mut r, &mut room.scene);
    assert_eq!((report.blases_built, report.tlas_built), (1, true));
}

#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn a_camera_edit_rebuilds_nothing() {
    let ctx = VulkanContext::new().unwrap();
    let mut room = room();
    let mut r = Renderer::new(&ctx, &room.scene).unwrap();
    let mut cam = *room.scene.camera();
    cam.transform[0][3] = 0.3;
    room.scene.set_camera(cam);
    let report = update_matches_fresh(&ctx, &mut r, &mut room.scene);
    assert_eq!(report, verion_gpu::UpdateReport::default());
}

#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn a_new_instance_rebuilds_everything_but_keeps_the_settings() {
    let ctx = VulkanContext::new().unwrap();
    let mut room = room();
    let mut r = Renderer::new(&ctx, &room.scene).unwrap();
    r.set_integrator(verion_gpu::Integrator::Wavefront);
    let mesh = room.scene.add_mesh(cube(0.2, 0.0));
    let mut at = IDENTITY;
    at[0][3] = -0.5;
    room.scene
        .add_instance(Instance {
            mesh,
            material: room.walls,
            transform: at,
        })
        .unwrap();
    let report = update_matches_fresh(&ctx, &mut r, &mut room.scene);
    assert_eq!((report.blases_built, report.tlas_built), (3, true));
    assert_eq!(r.integrator(), verion_gpu::Integrator::Wavefront);
}
