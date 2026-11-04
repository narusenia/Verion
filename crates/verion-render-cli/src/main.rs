//! `render-cli scene.gltf -o out.exr`: headless render (REQ-VIEW-001).
//! Always Reference mode for now: no stylization or AI approximation exists yet (REQ-CORE-006).

use std::{fs, path::PathBuf, time::Instant};

use clap::Parser;

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
    /// Samples per pixel
    #[arg(long, default_value_t = 64)]
    spp: u32,
    /// Equirectangular environment map (`.hdr` / `.exr`) used as the sky light
    #[arg(long)]
    hdri: Option<PathBuf>,
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

/// Samples per GPU dispatch; the progress bar advances once per dispatch.
#[cfg(target_os = "macos")]
const CHUNK_SPP: u32 = 8;

#[cfg(target_os = "macos")]
fn run(args: &Args) -> Result<(), String> {
    use indicatif::{ProgressBar, ProgressStyle};
    use verion_gpu_metal::{MetalContext, Renderer};
    use verion_render_io::{ExrAovs, ExrFrame, RenderInfo, load_gltf, load_hdri, write_exr};
    use verion_scene::{Light, OutputTransform};

    if args.width == 0 || args.height == 0 || args.spp == 0 {
        return Err("width, height and spp must be at least 1".into());
    }
    let total = Instant::now();
    let t = Instant::now();
    let import =
        load_gltf(&args.scene).map_err(|e| format!("load {}: {e}", args.scene.display()))?;
    for w in &import.warnings {
        eprintln!("warning: {w}");
    }
    let mut scene = import.scene;
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
    let mut acc = renderer
        .new_accumulation(w, h)
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
    let beauty = acc.mean();
    let render_s = t.elapsed().as_secs_f64();

    let t = Instant::now();
    let normals = renderer
        .render_normals(w, h)
        .map_err(|e| format!("normals: {e:?}"))?;
    let aov = renderer
        .render_aovs(w, h)
        .map_err(|e| format!("aovs: {e:?}"))?;
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
        },
        info: RenderInfo {
            physical: true,
            samples: args.spp,
        },
    };
    let t = Instant::now();
    write_exr(&args.output, &frame, &OutputTransform::linear(space))
        .map_err(|e| format!("write {}: {e}", args.output.display()))?;
    let write_s = t.elapsed().as_secs_f64();

    if let Some(path) = &args.metrics {
        let json = format!(
            "{{\"scene\":{},\"output\":{},\"width\":{w},\"height\":{h},\"spp\":{},\"mode\":\"reference\",\
\"load_s\":{load_s},\"build_s\":{build_s},\"render_s\":{render_s},\"aov_s\":{aov_s},\
\"write_s\":{write_s},\"total_s\":{}}}\n",
            json_str(&args.scene.display().to_string()),
            json_str(&args.output.display().to_string()),
            args.spp,
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
        assert!(Args::try_parse_from(["render-cli", "a.gltf"]).is_err());
    }

    #[test]
    fn escapes_json() {
        assert_eq!(json_str("a\"b\\c\n"), "\"a\\\"b\\\\c\\u000a\"");
    }
}
