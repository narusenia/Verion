//! `render-cli scene.gltf -o out.exr`: headless render (REQ-VIEW-001).
//! `--mode reference` (default) is physical only (REQ-CORE-006); `--mode stylized` adds the Stylization Pass;
//! `--mode interactive` turns on ReSTIR for a faster clean image (REQ-CORE-007).

use std::{fs, path::PathBuf, time::Instant};

use clap::Parser;

/// Render mode. Approximations that bias the image (ReSTIR now, NRC later) live outside Reference.
#[derive(clap::ValueEnum, Clone, Copy, Debug, PartialEq, Eq)]
enum Mode {
    /// Physical path tracing only (REQ-CORE-006).
    Reference,
    /// Path tracing with ReSTIR DI: a faster route to a clean image in scenes with many emitters.
    /// Not physical (the reuse is biased); no Stylization Pass (ADR-0016).
    Interactive,
    /// Stylization Pass on the primary hit (REQ-STY-007). Not physical; needs the lighting AOVs,
    /// so it costs the extra GPU memory of `--lighting-aovs`.
    Stylized,
}

impl Mode {
    fn name(self) -> &'static str {
        match self {
            Mode::Reference => "reference",
            Mode::Interactive => "interactive",
            Mode::Stylized => "stylized",
        }
    }

    /// No non-physical processing in the output.
    fn physical(self) -> bool {
        match self {
            Mode::Reference => true,
            Mode::Interactive | Mode::Stylized => false,
        }
    }
}

/// Form of the path tracer (REQ-GPU-005). Both give the same image.
#[derive(clap::ValueEnum, Clone, Copy, Debug, PartialEq, Eq)]
enum IntegratorArg {
    /// One GPU thread per path
    Megakernel,
    /// One kernel per stage and bounce, with compacted path queues
    Wavefront,
}

/// The OIDN device `--denoise` runs on.
#[derive(clap::ValueEnum, Clone, Copy, Debug, PartialEq, Eq)]
enum DenoiseDevice {
    Cpu,
    /// NVIDIA GPU through OIDN's CUDA module
    Cuda,
}

/// Where `--denoise` filters a stylized render (ADR-0013). Reference renders denoise the beauty.
#[derive(clap::ValueEnum, Clone, Copy, Debug, PartialEq, Eq)]
enum DenoiseStage {
    /// The lighting AOVs the Stylization Pass reads, so Toon bands are cut after denoising.
    Input,
    /// The stylized beauty, before the outline and the color grade (for comparison, REQ-QA-003).
    Output,
}

/// Linear RGB primaries selectable for the working space and the EXR output (REQ-CORE-005).
#[derive(clap::ValueEnum, Clone, Copy, Debug, PartialEq, Eq)]
enum Space {
    Rec709,
    Acescg,
}

impl Space {
    fn color(self) -> verion_scene::ColorSpace {
        match self {
            Space::Rec709 => verion_scene::ColorSpace::LinearRec709,
            Space::Acescg => verion_scene::ColorSpace::AcesCg,
        }
    }
}

#[derive(Parser, Debug)]
#[command(version, about = "Headless Verion renderer")]
struct Args {
    /// Input `.gltf` / `.glb`
    scene: PathBuf,
    /// Output EXR
    #[arg(short, long)]
    output: PathBuf,
    #[arg(long, default_value_t = 512)]
    width: u32,
    #[arg(long, default_value_t = 384)]
    height: u32,
    #[arg(long, value_enum, default_value_t = Mode::Reference)]
    mode: Mode,
    /// GPU API (default: Metal on macOS, Vulkan elsewhere)
    #[arg(long, value_enum)]
    backend: Option<BackendArg>,
    /// Samples per pixel
    #[arg(long, default_value_t = 64)]
    spp: u32,
    /// Equirectangular environment map (`.hdr` / `.exr`) used as the sky light
    #[arg(long)]
    hdri: Option<PathBuf>,
    /// Primaries the scene is rendered in (glTF colors are converted into it)
    #[arg(long, value_enum, default_value_t = Space::Rec709)]
    working_space: Space,
    /// Primaries of the output EXR (default: the working space)
    #[arg(long, value_enum)]
    output_space: Option<Space>,
    /// Also write the first-hit lighting split (DirectDiffuse, IndirectDiffuse, Specular, Transmission,
    /// Emission, Visibility); costs about 260 bytes of GPU memory per pixel
    #[arg(long)]
    lighting_aovs: bool,
    /// Plain single-scattering GGX for rough metals, as other renderers (Mitsuba 3) do, instead of
    /// the default multiple-scattering compensation
    #[arg(long)]
    no_multiscatter: bool,
    /// Gain in stops, applied last (needs `--mode stylized`; write it as `--exposure=-1` for a negative value)
    #[arg(long, default_value_t = 0.0, allow_negative_numbers = true)]
    exposure: f32,
    /// Saturation multiplier, applied last (needs `--mode stylized`)
    #[arg(long, default_value_t = 1.0)]
    saturation: f32,
    /// White balance as per-channel multipliers `R,G,B`, applied last (needs `--mode stylized`)
    #[arg(long, value_delimiter = ',', default_values_t = [1.0, 1.0, 1.0])]
    white_balance: Vec<f32>,
    /// Denoise with Intel Open Image Denoise (loaded at run time; marks the output non-physical)
    #[arg(long)]
    denoise: bool,
    /// OIDN device for `--denoise`
    #[arg(long, value_enum, default_value_t = DenoiseDevice::Cpu)]
    denoise_device: DenoiseDevice,
    /// What `--denoise` filters in `--mode stylized`
    #[arg(long, value_enum, default_value_t = DenoiseStage::Input)]
    denoise_stage: DenoiseStage,
    /// Path tracer form
    #[arg(long, value_enum, default_value_t = IntegratorArg::Megakernel)]
    integrator: IntegratorArg,
    /// Split the GPU time into extend (closest hit) and shade in the metrics (wavefront only;
    /// submits each stage separately, so the total gets slower)
    #[arg(long)]
    stage_timing: bool,
    /// Per-pixel adaptive sampling: a pixel stops once the standard error of its mean is at most
    /// this fraction of the mean (e.g. 0.02). `--spp` becomes the most a pixel takes. The
    /// output is marked non-physical (stopping on the pixel's own estimate biases it)
    #[arg(long, value_name = "THRESHOLD")]
    adaptive: Option<f32>,
    /// Samples every pixel takes before `--adaptive` may stop it
    #[arg(long, default_value_t = 16)]
    adaptive_min_spp: u32,
    /// ReSTIR DI: the first hit's emissive-triangle light sample comes from reservoirs that reuse
    /// the previous samples of the pixel and its neighbours. Faster to a clean image in scenes with
    /// many emitters; the reuse is biased, so the output is marked non-physical. Always on in
    /// `--mode interactive`, rejected in reference mode. Sharp, transmissive and lens-blurred
    /// surfaces use plain light sampling
    #[arg(long)]
    restir: bool,
    /// Light samples drawn per pixel and frame before ReSTIR's reuse
    #[arg(long, default_value_t = 4)]
    restir_candidates: u32,
    /// Most samples a reused ReSTIR reservoir counts for
    #[arg(long, default_value_t = 20)]
    restir_history: u32,
    /// Write timing metrics as JSON
    #[arg(long)]
    metrics: Option<PathBuf>,
}

impl Args {
    /// The color grade the flags ask for. Non-physical, so only `--mode stylized` may use it.
    fn color_grade(&self) -> Result<verion_stylization::ColorGrade, String> {
        let white_balance: [f32; 3] = self
            .white_balance
            .as_slice()
            .try_into()
            .map_err(|_| "--white-balance takes three values: R,G,B")?;
        let grade = verion_stylization::ColorGrade {
            exposure: self.exposure,
            saturation: self.saturation,
            white_balance,
        };
        grade.validate()?;
        if !grade.is_identity() && self.mode != Mode::Stylized {
            return Err(
                "--exposure, --saturation and --white-balance are non-physical; use --mode stylized"
                    .into(),
            );
        }
        Ok(grade)
    }
}

fn json_str(s: &str) -> String {
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// Samples per GPU dispatch; the progress bar advances once per dispatch.
const CHUNK_SPP: u32 = 8;

/// The GPU API to render with (REQ-GPU-003). Each platform builds one: Metal on macOS, Vulkan elsewhere.
#[derive(clap::ValueEnum, Clone, Copy, Debug, PartialEq, Eq)]
enum BackendArg {
    Metal,
    Vulkan,
}

impl BackendArg {
    /// The backend this platform builds.
    fn native() -> Self {
        if cfg!(target_os = "macos") {
            Self::Metal
        } else {
            Self::Vulkan
        }
    }
}

fn run(args: &Args) -> Result<(), String> {
    match args.backend.unwrap_or(BackendArg::native()) {
        #[cfg(target_os = "macos")]
        BackendArg::Metal => run_with::<verion_gpu_metal::Renderer>(args, "metal"),
        #[cfg(not(target_os = "macos"))]
        BackendArg::Vulkan => run_with::<verion_gpu_vulkan::Renderer>(args, "vulkan"),
        other => Err(format!(
            "the {other:?} backend is not built for this platform (use --backend {:?})",
            BackendArg::native()
        )),
    }
}

fn run_with<Backend: verion_gpu::RayTracingBackend>(
    args: &Args,
    backend: &str,
) -> Result<(), String> {
    use indicatif::{ProgressBar, ProgressStyle};
    use verion_gpu::{Accumulation as _, Adaptive, Integrator, Restir};
    use verion_render_io::{
        ExrAovs, ExrFrame, ExrLighting, GradeInfo, RenderInfo, load_gltf_in, load_hdri, write_exr,
    };
    use verion_scene::{Camera, Light, OutputTransform};

    if args.width == 0 || args.height == 0 || args.spp == 0 {
        return Err("width, height and spp must be at least 1".into());
    }
    let grade = args.color_grade()?;
    let restir = args.restir || args.mode == Mode::Interactive;
    if restir && args.mode.physical() {
        return Err("--restir is not allowed in reference mode (its reuse is biased)".into());
    }
    if restir && (args.restir_candidates == 0 || args.restir_history == 0) {
        return Err("--restir-candidates and --restir-history must be at least 1".into());
    }
    if args.adaptive.is_some_and(|t| !(t.is_finite() && t >= 0.0)) {
        return Err("--adaptive takes a threshold of 0 or more".into());
    }
    let total = Instant::now();
    let t = Instant::now();
    let import = load_gltf_in(&args.scene, args.working_space.color())
        .map_err(|e| format!("load {}: {e}", args.scene.display()))?;
    for w in &import.warnings {
        eprintln!("warning: {w}");
    }
    let mut scene = import.scene;
    if *scene.camera() == Camera::default() {
        scene.frame_camera();
    }
    if let Some(path) = &args.hdri {
        let image = load_hdri(path, scene.working_space())
            .map_err(|e| format!("hdri {}: {e}", path.display()))?;
        let image = scene.add_image(image);
        scene.add_light(Light::EnvironmentMap { image, scale: 1.0 });
    }
    let load_s = t.elapsed().as_secs_f64();

    let t = Instant::now();
    let ctx = Backend::context().map_err(|e| format!("GPU ray tracing is required: {e}"))?;
    let mut renderer = Backend::new(&ctx, &scene).map_err(|e| format!("renderer: {e:?}"))?;
    renderer.set_multiscatter(!args.no_multiscatter);
    renderer.set_integrator(match args.integrator {
        IntegratorArg::Megakernel => Integrator::Megakernel,
        IntegratorArg::Wavefront => Integrator::Wavefront,
    });
    renderer.set_stage_timing(args.stage_timing);
    renderer.set_restir(restir.then_some(Restir {
        candidates: args.restir_candidates,
        history: args.restir_history,
    }));
    renderer.set_adaptive(args.adaptive.map(|threshold| Adaptive {
        threshold,
        min_spp: args.adaptive_min_spp,
    }));
    // shortcut: the peak is the largest of the samples taken at stage boundaries, not a true high-water mark.
    let mut peak = Backend::memory(&ctx).allocated;
    let build_s = t.elapsed().as_secs_f64();

    let (w, h) = (args.width, args.height);
    let t = Instant::now();
    let lighting_on = args.lighting_aovs || args.mode == Mode::Stylized;
    let mut acc = renderer
        .new_accumulation(w, h, lighting_on)
        .map_err(|e| format!("render: {e:?}"))?;
    // Hidden automatically when stderr is not a terminal.
    let bar = ProgressBar::new(args.spp as u64)
        .with_style(ProgressStyle::with_template("{bar:40} {pos}/{len} spp ({eta})").unwrap());
    while acc.samples() < args.spp {
        let n = CHUNK_SPP.min(args.spp - acc.samples());
        renderer
            .accumulate(&mut acc, n)
            .map_err(|e| format!("render: {e:?}"))?;
        bar.set_position(acc.samples() as u64);
        if acc.active_pixels() == 0 {
            break; // adaptive sampling: every pixel converged
        }
    }
    bar.finish_and_clear();
    let gpu_s = acc.gpu_seconds();
    let wavefront_bytes = acc.wavefront_bytes();
    let restir_bytes = acc.restir_bytes();
    peak = peak.max(Backend::memory(&ctx).allocated);
    let stages = acc.stage_seconds().map_or(String::new(), |[e, s]| {
        format!("\"extend_s\":{e},\"shade_s\":{s},")
    });
    let sample_count = acc.sample_counts();
    let mean_spp = sample_count.as_ref().map_or(acc.samples() as f64, |n| {
        n.iter().map(|&n| n as f64).sum::<f64>() / n.len() as f64
    });
    let mut beauty = acc.mean();
    let mut lighting = acc.lighting();
    let render_s = t.elapsed().as_secs_f64();

    let t = Instant::now();
    let normals = renderer
        .render_normals(w, h)
        .map_err(|e| format!("normals: {e:?}"))?;
    let aov = renderer
        .render_aovs(w, h)
        .map_err(|e| format!("aovs: {e:?}"))?;
    let aov_s = t.elapsed().as_secs_f64();
    let memory = Backend::memory(&ctx);
    peak = peak.max(memory.allocated);

    let t = Instant::now();
    let mut denoiser = if args.denoise {
        Some(
            verion_denoise::Denoiser::load_on(match args.denoise_device {
                DenoiseDevice::Cpu => verion_denoise::Device::Cpu,
                DenoiseDevice::Cuda => verion_denoise::Device::Cuda,
            })
            .map_err(|e| e.to_string())?,
        )
    } else {
        None
    };
    let aux = verion_denoise::Aux {
        albedo: Some(&aov.albedo),
        normal: Some(&normals),
    };
    let (wu, hu) = (w as usize, h as usize);
    if let Some(d) = denoiser.as_mut() {
        let denoise_err = |e: verion_denoise::Error| format!("denoise: {e}");
        match (args.mode, lighting.as_mut()) {
            (Mode::Stylized, Some(l)) if args.denoise_stage == DenoiseStage::Input => l
                .for_each_radiance(|p| d.denoise(p, aux, wu, hu))
                .map_err(denoise_err)?,
            (Mode::Reference | Mode::Interactive, _) => {
                d.denoise(&mut beauty, aux, wu, hu).map_err(denoise_err)?
            }
            _ => {}
        }
    }
    let mut denoise_s = t.elapsed().as_secs_f64();

    let t = Instant::now();
    if let (Mode::Stylized, Some(l)) = (args.mode, &lighting) {
        if scene.materials().iter().all(|m| m.stylization.is_empty()) {
            eprintln!("warning: no material has stylization layers; the output equals Reference");
        }
        beauty = verion_stylization::stylize_image(
            scene.materials(),
            &verion_stylization::Frame {
                direct_diffuse: &l.direct_diffuse,
                indirect_diffuse: &l.indirect_diffuse,
                specular: &l.specular,
                transmission: &l.transmission,
                emission: &l.emission,
                light_u: &l.light_u,
                light_response: &l.light_response,
                light_s: &l.light_s,
                light_dir: &l.light_dir,
                light_lit: &l.light_lit,
                normal: &normals,
                albedo: &aov.albedo,
                material_id: &aov.material_id,
                images: scene.images(),
                camera: *scene.camera(),
                width: w as usize,
            },
        );
        if let Some(d) = denoiser.as_mut()
            && args.denoise_stage == DenoiseStage::Output
        {
            let t = Instant::now();
            d.denoise(&mut beauty, aux, wu, hu)
                .map_err(|e| format!("denoise: {e}"))?;
            denoise_s += t.elapsed().as_secs_f64();
        }
        verion_stylization::outline(
            scene.materials(),
            &verion_stylization::PostFrame {
                width: w as usize,
                depth: &aov.depth,
                normal: &normals,
                object_id: &aov.object_id,
                material_id: &aov.material_id,
            },
            &mut beauty,
        );
        verion_stylization::color_grade(&mut beauty, &grade);
    }
    let stylize_s = t.elapsed().as_secs_f64();

    let space = scene.working_space();
    let frame = ExrFrame {
        width: w,
        height: h,
        working_space: space,
        beauty: &beauty,
        normal: Some(&normals),
        aovs: ExrAovs {
            albedo: Some(&aov.albedo),
            depth: Some(&aov.depth),
            object_id: Some(&aov.object_id),
            material_id: Some(&aov.material_id),
            sample_count: sample_count.as_deref(),
            lighting: lighting.as_ref().map(|l| ExrLighting {
                direct_diffuse: &l.direct_diffuse,
                indirect_diffuse: &l.indirect_diffuse,
                specular: &l.specular,
                transmission: &l.transmission,
                emission: &l.emission,
                visibility: &l.visibility,
            }),
        },
        info: RenderInfo {
            physical: args.mode.physical(),
            samples: args.spp,
            stylization_revision: scene.revisions().stylization,
            grade: (!grade.is_identity()).then_some(GradeInfo {
                exposure: grade.exposure,
                saturation: grade.saturation,
                white_balance: grade.white_balance,
            }),
            denoiser: args.denoise.then_some("oidn"),
            adaptive_threshold: args.adaptive,
            restir,
        },
    };
    let t = Instant::now();
    write_exr(
        &args.output,
        &frame,
        &OutputTransform::linear(args.output_space.map_or(space, Space::color)),
    )
    .map_err(|e| format!("write {}: {e}", args.output.display()))?;
    let write_s = t.elapsed().as_secs_f64();

    if let Some(path) = &args.metrics {
        let json = format!(
            "{{\"backend\":{},\"scene\":{},\"output\":{},\"width\":{w},\"height\":{h},\"spp\":{},\"mode\":{},\"integrator\":\"{:?}\",\"adaptive\":{},\"restir\":{},\"mean_spp\":{mean_spp},\"wavefront_bytes\":{wavefront_bytes},\"restir_bytes\":{restir_bytes},\"gpu_budget_bytes\":{},\"gpu_peak_bytes\":{peak},\"upload_bytes\":{},\
\"load_s\":{load_s},\"build_s\":{build_s},\"render_s\":{render_s},\"gpu_s\":{gpu_s},{stages}\"aov_s\":{aov_s},\"denoise_s\":{denoise_s},\"stylize_s\":{stylize_s},\
\"write_s\":{write_s},\"total_s\":{}}}\n",
            json_str(backend),
            json_str(&args.scene.display().to_string()),
            json_str(&args.output.display().to_string()),
            args.spp,
            json_str(args.mode.name()),
            args.integrator,
            args.adaptive.map_or("null".into(), |t| t.to_string()),
            restir,
            memory.budget,
            memory.uploaded,
            total.elapsed().as_secs_f64(),
        );
        fs::write(path, json).map_err(|e| format!("write {}: {e}", path.display()))?;
    }
    Ok(())
}

fn main() {
    if let Err(e) = run(&Args::parse()) {
        eprintln!("error: {e}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_required_and_defaults() {
        let a = Args::try_parse_from(["render-cli", "a.gltf", "-o", "o.exr"]).unwrap();
        assert_eq!((a.width, a.height, a.spp), (512, 384, 64));
        assert_eq!(a.mode, Mode::Reference);
        assert_eq!((a.working_space, a.output_space), (Space::Rec709, None));
        let a = Args::try_parse_from([
            "render-cli",
            "a.gltf",
            "-o",
            "o.exr",
            "--working-space",
            "acescg",
            "--output-space",
            "rec709",
        ])
        .unwrap();
        assert_eq!(
            (a.working_space, a.output_space),
            (Space::Acescg, Some(Space::Rec709))
        );
        assert!(Mode::Reference.physical());
        assert!(Args::try_parse_from(["render-cli", "a.gltf"]).is_err());
    }

    #[test]
    fn color_grade_flags_need_the_stylized_mode() {
        let parse = |extra: &[&str]| {
            let mut v = vec!["render-cli", "a.gltf", "-o", "o.exr"];
            v.extend_from_slice(extra);
            Args::try_parse_from(v).unwrap()
        };
        assert!(parse(&[]).color_grade().unwrap().is_identity());
        let g = parse(&[
            "--mode",
            "stylized",
            "--exposure=-1",
            "--saturation",
            "0.8",
            "--white-balance",
            "1.1,1,0.9",
        ])
        .color_grade()
        .unwrap();
        assert_eq!((g.exposure, g.saturation), (-1.0, 0.8));
        assert_eq!(g.white_balance, [1.1, 1.0, 0.9]);
        assert!(parse(&["--exposure", "1"]).color_grade().is_err()); // reference mode
        assert!(
            parse(&["--mode", "stylized", "--saturation=-1"])
                .color_grade()
                .is_err()
        );
        let two = parse(&["--mode", "stylized", "--white-balance", "1,1"]);
        assert!(two.color_grade().is_err()); // needs three values
    }

    #[test]
    fn escapes_json() {
        assert_eq!(json_str("a\"b\\c\n"), "\"a\\\"b\\\\c\\u000a\"");
    }
}
