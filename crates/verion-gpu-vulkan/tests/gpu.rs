//! Needs a Vulkan ray-tracing GPU, so these are ignored by default (CI has none):
//! `mise run test:gpu` runs them on the dev machine.
#![cfg(not(target_os = "macos"))]

use std::path::Path;

use verion_gpu::{Accumulation as _, Adaptive, Integrator, RayTracingBackend};
use verion_gpu_vulkan::{Renderer, VulkanContext};
use verion_render_io::load_gltf_in;
use verion_scene::{ColorSpace, Scene};

const W: u32 = 96;
const H: u32 = 72;

fn cornell() -> Scene {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../scenes/cornell_box.gltf");
    load_gltf_in(&path, ColorSpace::LinearRec709).unwrap().scene
}

fn renderer(ctx: &VulkanContext) -> Renderer {
    Renderer::new(ctx, &cornell()).unwrap()
}

fn bits(image: &[[f32; 3]]) -> Vec<u32> {
    image.iter().flatten().map(|v| v.to_bits()).collect()
}

fn render(
    r: &mut Renderer,
    integrator: Integrator,
    adaptive: Option<Adaptive>,
) -> impl verion_gpu::Accumulation + use<> {
    r.set_integrator(integrator);
    r.set_adaptive(adaptive);
    let mut acc = r.new_accumulation(W, H, true).unwrap();
    r.accumulate(&mut acc, 12).unwrap();
    acc
}

#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn context_reports_what_the_device_can_do() {
    let ctx = VulkanContext::new().unwrap();
    let info = ctx.info();
    println!("{info:#?}\n{:?}", ctx.memory());
    assert!(!info.name.is_empty());
    assert!(ctx.memory().budget > 0);
}

#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn wavefront_matches_the_megakernel_bit_for_bit() {
    let ctx = VulkanContext::new().unwrap();
    let mut r = renderer(&ctx);
    let mega = render(&mut r, Integrator::Megakernel, None);
    let wave = render(&mut r, Integrator::Wavefront, None);
    assert!(mega.mean().iter().flatten().any(|v| *v > 0.0));
    assert_eq!(bits(&mega.mean()), bits(&wave.mean()));
    let (a, b) = (mega.lighting().unwrap(), wave.lighting().unwrap());
    assert_eq!(bits(&a.direct_diffuse), bits(&b.direct_diffuse));
    assert_eq!(bits(&a.indirect_diffuse), bits(&b.indirect_diffuse));
    assert_eq!(bits(&a.specular), bits(&b.specular));
    assert_eq!(bits(&a.transmission), bits(&b.transmission));
    assert_eq!(bits(&a.emission), bits(&b.emission));
    assert_eq!(a.visibility, b.visibility);
    assert!(wave.wavefront_bytes() > 0);
}

#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn adaptive_sampling_agrees_between_integrators() {
    let ctx = VulkanContext::new().unwrap();
    let mut r = renderer(&ctx);
    let a = Some(Adaptive {
        threshold: 0.3,
        min_spp: 4,
    });
    let mega = render(&mut r, Integrator::Megakernel, a);
    let wave = render(&mut r, Integrator::Wavefront, a);
    assert_eq!(mega.sample_counts(), wave.sample_counts());
    assert_eq!(bits(&mega.mean()), bits(&wave.mean()));
    let counts = mega.sample_counts().unwrap();
    assert!(
        counts.iter().any(|&n| n < 12),
        "some pixel should stop early"
    );
    assert_eq!(mega.active_pixels(), wave.active_pixels());
}

#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn gpu_time_is_measured_and_stages_split_when_asked() {
    let ctx = VulkanContext::new().unwrap();
    let mut r = renderer(&ctx);
    r.set_integrator(Integrator::Wavefront);
    r.set_stage_timing(true);
    let mut acc = r.new_accumulation(W, H, false).unwrap();
    r.accumulate(&mut acc, 2).unwrap();
    let [extend, shade] = acc.stage_seconds().unwrap();
    assert!(extend > 0.0 && shade > 0.0 && acc.gpu_seconds() > 0.0);
}

#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn aovs_and_normals_describe_the_first_hit() {
    let ctx = VulkanContext::new().unwrap();
    let r = renderer(&ctx);
    let aov = r.render_aovs(W, H).unwrap();
    let normals = r.render_normals(W, H).unwrap();
    let hits = aov.object_id.iter().filter(|&&id| id > 0).count();
    assert!(hits > (W * H) as usize / 2, "the box fills the frame");
    for (i, id) in aov.object_id.iter().enumerate() {
        let n = normals[i];
        let len = (n[0] * n[0] + n[1] * n[1] + n[2] * n[2]).sqrt();
        if *id > 0 {
            assert!((len - 1.0).abs() < 1e-3, "pixel {i}: |n| = {len}");
            assert!(aov.depth[i] > 0.0 && aov.material_id[i] > 0);
        } else {
            assert_eq!((len, aov.depth[i]), (0.0, 0.0));
        }
    }
}

#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn a_scene_without_instances_is_an_error_not_a_crash() {
    let ctx = VulkanContext::new().unwrap();
    assert!(Renderer::new(&ctx, &Scene::new()).is_err());
}

#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn reordering_megakernel_renders_the_same_image() {
    let ctx = VulkanContext::new().unwrap();
    if !ctx.info().ser {
        println!("no shader execution reordering on this device: skipped");
        return;
    }
    let mut r = renderer(&ctx);
    let plain = render(&mut r, Integrator::Megakernel, None);
    assert!(r.set_reorder(true));
    let reordered = render(&mut r, Integrator::Megakernel, None);
    let mean = |acc: &dyn Fn() -> Vec<[f32; 3]>| {
        let img = acc();
        (0..3)
            .map(|c| img.iter().map(|p| f64::from(p[c])).sum::<f64>() / img.len() as f64)
            .collect::<Vec<_>>()
    };
    let (a, b) = (mean(&|| plain.mean()), mean(&|| reordered.mean()));
    for c in 0..3 {
        assert!(
            a[c] > 0.0 && (b[c] / a[c] - 1.0).abs() < 0.01,
            "channel {c}: {a:?} vs {b:?}"
        );
    }
    // Both lighting splits exist, so Stylized works with it too.
    assert!(reordered.lighting().is_some());
}

#[test]
#[ignore = "needs a Vulkan ray tracing GPU"]
fn reordering_is_refused_when_unsupported_and_off_by_default() {
    let ctx = VulkanContext::new().unwrap();
    let mut r = renderer(&ctx);
    assert!(r.set_reorder(false));
    assert_eq!(r.set_reorder(true), ctx.info().ser);
}
