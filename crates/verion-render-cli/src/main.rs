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
    /// Emission, Visibility); costs about 70 bytes of GPU memory per pixel
    #[arg(long)]
    lighting_aovs: bool,
    /// Write timing metrics as JSON
    #[arg(long)]
    metrics: Option<PathBuf>,
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

/// The glTF had no camera: look at the scene's bounding sphere from +z (glTF's front), so the
/// whole model is in view. shortcut: a camera exactly equal to the default counts as "none".
#[cfg(target_os = "macos")]
fn frame_camera(scene: &mut verion_scene::Scene) {
    let (mut lo, mut hi) = ([f32::MAX; 3], [f32::MIN; 3]);
    for inst in scene.instances() {
        for p in scene.meshes()[inst.mesh.index()].positions() {
            for a in 0..3 {
                let t = inst.transform[a];
                let v = t[0] * p[0] + t[1] * p[1] + t[2] * p[2] + t[3];
                lo[a] = lo[a].min(v);
                hi[a] = hi[a].max(v);
            }
        }
    }
    if lo[0] > hi[0] {
        return;
    }
    let c: [f32; 3] = std::array::from_fn(|a| (lo[a] + hi[a]) / 2.0);
    let r = (0..3).map(|a| (hi[a] - lo[a]).powi(2)).sum::<f32>().sqrt() / 2.0;
    let mut cam = verion_scene::Camera::default();
    let dist = r / (cam.vertical_fov / 2.0).sin() * 1.05;
    cam.transform[0][3] = c[0];
    cam.transform[1][3] = c[1];
    cam.transform[2][3] = c[2] + dist;
    cam.focus_distance = dist;
    scene.set_camera(cam);
}

/// Samples per GPU dispatch; the progress bar advances once per dispatch.
#[cfg(target_os = "macos")]
const CHUNK_SPP: u32 = 8;

#[cfg(target_os = "macos")]
fn run(args: &Args) -> Result<(), String> {
    use indicatif::{ProgressBar, ProgressStyle};
    use verion_gpu_metal::{MetalContext, Renderer};
    use verion_render_io::{
        ExrAovs, ExrFrame, ExrLighting, RenderInfo, load_gltf_in, load_hdri, write_exr,
    };
    use verion_scene::{Camera, Light, OutputTransform};

    if args.width == 0 || args.height == 0 || args.spp == 0 {
        return Err("width, height and spp must be at least 1".into());
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
        frame_camera(&mut scene);
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
    let renderer = Renderer::new(&ctx, &scene).map_err(|e| format!("renderer: {e:?}"))?;
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
    let lighting = acc.lighting();
    let render_s = t.elapsed().as_secs_f64();

    let t = Instant::now();
    let normals = renderer
        .render_normals(w, h)
        .map_err(|e| format!("normals: {e:?}"))?;
    let aov = renderer
        .render_aovs(w, h)
        .map_err(|e| format!("aovs: {e:?}"))?;
    if let (Mode::Stylized, Some(l)) = (args.mode, &lighting) {
        if scene.materials().iter().all(|m| m.stylization.is_empty()) {
            eprintln!("warning: no material has stylization layers; the output equals Reference");
        }
        beauty = verion_stylization::stylize_image(
            scene.materials(),
            &verion_stylization::Frame {
                albedo: &aov.albedo,
                direct_diffuse: &l.direct_diffuse,
                indirect_diffuse: &l.indirect_diffuse,
                specular: &l.specular,
                transmission: &l.transmission,
                emission: &l.emission,
                material_id: &aov.material_id,
            },
        );
    }
    let aov_s = t.elapsed().as_secs_f64();

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
\"load_s\":{load_s},\"build_s\":{build_s},\"render_s\":{render_s},\"gpu_s\":{gpu_s},\"aov_s\":{aov_s},\
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
    fn escapes_json() {
        assert_eq!(json_str("a\"b\\c\n"), "\"a\\\"b\\\\c\\u000a\"");
    }
}
