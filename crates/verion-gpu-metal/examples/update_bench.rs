//! Times scene edits: a full rebuild against the differential `update` (REQ-ACC-003), and the
//! time from an edit to a first preview of `SPP` samples (First Clean Preview, REQ-DCC-002).
//! `cargo run --release -p verion-gpu-metal --example update_bench -- scene.gltf [spp]`
#[cfg(target_os = "macos")]
use std::time::Instant;

#[cfg(target_os = "macos")]
use verion_gpu::RayTracingBackend as _;
#[cfg(target_os = "macos")]
use verion_gpu_metal::{MetalContext, Renderer};
#[cfg(target_os = "macos")]
use verion_render_io::load_gltf;
#[cfg(target_os = "macos")]
use verion_scene::Scene;

#[cfg(target_os = "macos")]
fn secs(f: impl FnOnce()) -> f64 {
    let t = Instant::now();
    f();
    t.elapsed().as_secs_f64()
}

#[cfg(not(target_os = "macos"))]
fn main() {
    eprintln!("update_bench requires macOS (Metal)");
}

#[cfg(target_os = "macos")]
fn main() {
    let mut args = std::env::args().skip(1);
    let path = args.next().expect("scene.gltf");
    let spp: u32 = args.next().map_or(4, |s| s.parse().expect("spp"));
    let mut scene = load_gltf(std::path::Path::new(&path)).expect("load").scene;
    if *scene.camera() == verion_scene::Camera::default() {
        scene.frame_camera();
    }
    scene.take_changes();
    let ctx = MetalContext::new().expect("Metal ray tracing");
    let mut r = Renderer::new(&ctx, &scene).expect("renderer");
    let rebuild = secs(|| drop(Renderer::new(&ctx, &scene).unwrap()));
    println!("{path}: full rebuild {rebuild:.3} s");

    let preview = |r: &Renderer| {
        let mut acc = r.new_accumulation(512, 384, false).unwrap();
        r.accumulate(&mut acc, spp).unwrap();
    };
    let edit = |name: &str, scene: &mut Scene, r: &mut Renderer| {
        let changes = scene.take_changes();
        let mut report = Default::default();
        let update = secs(|| report = r.update(scene, &changes).unwrap());
        let first = secs(|| preview(r));
        println!(
            "{name:<12} update {update:.4} s  blas {} tlas {}  + {spp} spp {first:.3} s",
            report.blases_built, report.tlas_built
        );
    };

    let mut m = scene.materials()[0].clone();
    m.base.roughness = (m.base.roughness + 0.3).min(1.0);
    m.base.base_color[0] = 1.0 - m.base.base_color[0];
    let id = scene.material_id(0).unwrap();
    scene.set_material(id, m);
    edit("material", &mut scene, &mut r);

    if let Some(id) = scene.light_id(0) {
        let mut l = scene.lights()[0];
        if let verion_scene::Light::Point { intensity, .. }
        | verion_scene::Light::Directional { intensity, .. }
        | verion_scene::Light::Spot { intensity, .. } = &mut l
        {
            *intensity *= 2.0;
        }
        scene.set_light(id, l);
        edit("light", &mut scene, &mut r);
    }

    let id = scene.instance_id(0).unwrap();
    let mut inst = scene.instances()[0];
    inst.transform[0][3] += 0.1;
    scene.set_instance(id, inst).unwrap();
    edit("transform", &mut scene, &mut r);

    let mesh = scene.instances()[0].mesh;
    let m = &scene.meshes()[mesh.index()];
    let moved: Vec<[f32; 3]> = m
        .positions()
        .iter()
        .map(|p| [p[0] * 1.05, p[1], p[2]])
        .collect();
    let bent = verion_scene::Mesh::new(
        moved,
        m.normals().map(<[_]>::to_vec),
        m.uvs().map(<[_]>::to_vec),
        m.indices().to_vec(),
    )
    .unwrap();
    scene.set_mesh(mesh, bent);
    edit("deformation", &mut scene, &mut r);
}
