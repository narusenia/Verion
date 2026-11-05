//! `render-cli scene.gltf -o out.exr`: headless render (REQ-VIEW-001).
//! `--mode reference` (default) is physical only (REQ-CORE-006); `--mode stylized` adds the Stylization Pass.

// shortcut: the render path is macOS-only, so off macOS its helpers look dead; gate them individually once a second backend exists.
#![cfg_attr(not(target_os = "macos"), allow(dead_code, unused_imports))]

use std::{fs, path::PathBuf, time::Instant};

use clap::Parser;

/// Render mode. AI approximation (NRC, ReSTIR) does not exist yet; add variants here when it
/// lands and set `physical` accordingly.
#[derive(clap::ValueEnum, Clone, Copy, Debug, PartialEq, Eq)]
enum Mode {
    /// Physical path tracing only (REQ-CORE-006).
    Reference,
    /// Stylization Pass on the primary hit (REQ-STY-007). Not physical; needs the lighting AOVs,
    /// so it costs the extra GPU memory of `--lighting-aovs`.
    Stylized,
}

impl Mode {
    fn name(self) -> &'static str {
        match self {
            Mode::Reference => "reference",
            Mode::Stylized => "stylized",
        }
    }

    /// No non-physical processing in the output.
    fn physical(self) -> bool {
        match self {
            Mode::Reference => true,
            Mode::Stylized => false,
        }
    }
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
    /// What `--denoise` filters in `--mode stylized`
    #[arg(long, value_enum, default_value_t = DenoiseStage::Input)]
    denoise_stage: DenoiseStage,
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
#[cfg(target_os = "macos")]
const CHUNK_SPP: u32 = 8;

#[cfg(target_os = "macos")]
fn run(args: &Args) -> Result<(), String> {
    use indicatif::{ProgressBar, ProgressStyle};
    use verion_gpu_metal::{MetalContext, Renderer};
    use verion_render_io::{
        ExrAovs, ExrFrame, ExrLighting, GradeInfo, RenderInfo, load_gltf_in, load_hdri, write_exr,
    };
    use verion_scene::{Camera, Light, OutputTransform};

    if args.width == 0 || args.height == 0 || args.spp == 0 {
        return Err("width, height and spp must be at least 1".into());
    }
    let grade = args.color_grade()?;
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
    let ctx = MetalContext::new().map_err(|e| format!("Metal ray tracing is required: {e:?}"))?;
    let mut renderer = Renderer::new(&ctx, &scene).map_err(|e| format!("renderer: {e:?}"))?;
    renderer.set_multiscatter(!args.no_multiscatter);
    let build_s = t.elapsed().as_secs_f64();

    let (w, h) = (args.width, args.height);
    let t = Instant::now();
    let lighting_on = args.lighting_aovs || args.mode == Mode::Stylized;
    let mut acc = if lighting_on {
        renderer.new_accumulation_with_lighting(w, h)
    } else {
        renderer.new_accumulation(w, h)
    }
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
    }
    bar.finish_and_clear();
    let gpu_s = acc.gpu_seconds();
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

    let t = Instant::now();
    let mut denoiser = if args.denoise {
        Some(verion_denoise::Denoiser::load().map_err(|e| e.to_string())?)
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
            (Mode::Reference, _) => d.denoise(&mut beauty, aux, wu, hu).map_err(denoise_err)?,
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
            "{{\"scene\":{},\"output\":{},\"width\":{w},\"height\":{h},\"spp\":{},\"mode\":{},\
\"load_s\":{load_s},\"build_s\":{build_s},\"render_s\":{render_s},\"gpu_s\":{gpu_s},\"aov_s\":{aov_s},\"denoise_s\":{denoise_s},\"stylize_s\":{stylize_s},\
\"write_s\":{write_s},\"total_s\":{}}}\n",
            json_str(&args.scene.display().to_string()),
            json_str(&args.output.display().to_string()),
            args.spp,
            json_str(args.mode.name()),
            total.elapsed().as_secs_f64(),
        );
        fs::write(path, json).map_err(|e| format!("write {}: {e}", path.display()))?;
    }
    Ok(())
}

#[cfg(not(target_os = "macos"))]
fn run(_: &Args) -> Result<(), String> {
    Err("render-cli requires macOS (Metal)".into())
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
