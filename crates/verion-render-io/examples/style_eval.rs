//! `style_eval reference.exr test.exr [more.exr ...]`: Stylization evaluation (REQ-QA-003) of
//! render-cli EXRs against a high-sample reference of the same scene and settings.
//!
//! - `edge`: how much of the reference's Toon band edges survives. Band-edge pixels are those
//!   where the reference luminance changes sharply (relative gradient above 0.25) inside one object
//!   (all 3x3 neighbours share the ObjectId), so silhouettes, which the denoiser's aux images
//!   protect anyway, are left out. The score is the mean of `min(grad_test / grad_ref, 1)` over
//!   them: 1 keeps every edge as sharp as the reference, 0.5 halves them.
//! - `flat`: mean absolute error over the other object pixels divided by their mean (noise).
//!
//! Gate (M2 completion: denoising must not erase Toon edges): `edge >= 0.8`. Exits 1 on a failure.

use std::path::Path;

use exr::prelude::*;

struct Frame {
    w: usize,
    h: usize,
    lum: Vec<f32>,
    id: Vec<u32>,
}

fn load(p: &str) -> Frame {
    let img = read()
        .no_deep_data()
        .largest_resolution_level()
        .all_channels()
        .first_valid_layer()
        .all_attributes()
        .from_file(Path::new(p))
        .unwrap_or_else(|e| {
            eprintln!("{p}: {e}");
            std::process::exit(2)
        });
    let size = img.layer_data.size;
    let list = &img.layer_data.channel_data.list;
    let get = |name: &str| {
        list.iter()
            .find(|c| c.name.to_string() == name)
            .unwrap_or_else(|| {
                eprintln!("{p}: no channel {name}");
                std::process::exit(2)
            })
    };
    let (r, g, b) = (get("R"), get("G"), get("B"));
    let (r, g, b): (Vec<f32>, Vec<f32>, Vec<f32>) = (
        r.sample_data.values_as_f32().collect(),
        g.sample_data.values_as_f32().collect(),
        b.sample_data.values_as_f32().collect(),
    );
    let id = match &get("ObjectId").sample_data {
        FlatSamples::U32(v) => v.clone(),
        other => other.values_as_f32().map(|v| v as u32).collect(),
    };
    let lum = (0..r.len())
        .map(|i| 0.2126 * r[i] + 0.7152 * g[i] + 0.0722 * b[i])
        .collect();
    Frame {
        w: size.width(),
        h: size.height(),
        lum,
        id,
    }
}

/// Central-difference gradient magnitude of the luminance at an interior pixel.
fn grad(f: &Frame, x: usize, y: usize) -> f32 {
    let at = |x: usize, y: usize| f.lum[y * f.w + x];
    let gx = at(x + 1, y) - at(x - 1, y);
    let gy = at(x, y + 1) - at(x, y - 1);
    0.5 * (gx * gx + gy * gy).sqrt()
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.len() < 2 {
        eprintln!("usage: style_eval reference.exr test.exr [more.exr ...]");
        std::process::exit(2);
    }
    let r = load(&args[0]);
    // Band-edge pixels of the reference, and the flat object pixels.
    let mut edges = Vec::new();
    let mut flat = Vec::new();
    for y in 1..r.h - 1 {
        for x in 1..r.w - 1 {
            let i = y * r.w + x;
            if r.id[i] == 0 {
                continue;
            }
            let one_object = (0..9).all(|k| r.id[(y + k / 3 - 1) * r.w + x + k % 3 - 1] == r.id[i]);
            if !one_object {
                continue;
            }
            if grad(&r, x, y) > 0.25 * r.lum[i].max(1.0e-3) {
                edges.push((x, y));
            } else {
                flat.push(i);
            }
        }
    }
    let mut ok = true;
    for path in &args[1..] {
        let t = load(path);
        if (t.w, t.h) != (r.w, r.h) {
            eprintln!("{path}: size differs from the reference");
            std::process::exit(2);
        }
        let edge = edges
            .iter()
            .map(|&(x, y)| (grad(&t, x, y) / grad(&r, x, y)).min(1.0))
            .sum::<f32>()
            / edges.len().max(1) as f32;
        let mean = flat.iter().map(|&i| r.lum[i]).sum::<f32>() / flat.len().max(1) as f32;
        let err = flat
            .iter()
            .map(|&i| (t.lum[i] - r.lum[i]).abs())
            .sum::<f32>()
            / flat.len().max(1) as f32
            / mean.max(1.0e-6);
        let pass = edge >= 0.8;
        ok &= pass;
        println!(
            "{path}: edge {edge:.3} ({} px) flat {err:.4} {}",
            edges.len(),
            if pass { "PASS" } else { "FAIL" }
        );
    }
    std::process::exit(if ok { 0 } else { 1 });
}
