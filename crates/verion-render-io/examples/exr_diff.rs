//! `exr_diff reference.exr test.exr [more.exr ...]`: compares the beauty of each test image with the
//! reference using the REQ-QA-001 gates of `scripts/mitsuba_cornell.py` (worst channel mean within 1%,
//! worst 4x4 block mean within 2%) plus the relative mean absolute error and PSNR, which are reported only.
//! `EXR_DIFF_CHANNEL` and `EXR_DIFF_BLOCK` (fractions) replace the two gates; `scripts/backend_diff.sh` sets them for REQ-GPU-007.
//! Prints `PASS` / `FAIL` per image and exits 1 when any fails.

use std::path::Path;

use verion_render_io::load_hdri;
use verion_scene::ColorSpace;

fn load(p: &str) -> (usize, usize, Vec<[f32; 3]>) {
    let img = load_hdri(Path::new(p), ColorSpace::LinearRec709).unwrap_or_else(|e| {
        eprintln!("{p}: {e}");
        std::process::exit(2)
    });
    (
        img.width() as usize,
        img.height() as usize,
        img.pixels().to_vec(),
    )
}

fn mean(v: impl Iterator<Item = f64>) -> f64 {
    let (s, n) = v.fold((0.0, 0usize), |(s, n), x| (s + x, n + 1));
    s / n.max(1) as f64
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.len() < 2 {
        eprintln!("usage: exr_diff reference.exr test.exr [more.exr ...]");
        std::process::exit(2);
    }
    let gate = |name: &str, default: f64| {
        std::env::var(name).map_or(default, |v| v.parse().expect("gate must be a number"))
    };
    let (gate_channel, gate_block) = (gate("EXR_DIFF_CHANNEL", 0.01), gate("EXR_DIFF_BLOCK", 0.02));
    let (w, h, r) = load(&args[0]);
    let mut ok = true;
    for path in &args[1..] {
        let (tw, th, t) = load(path);
        if (tw, th) != (w, h) {
            eprintln!("{path}: size {tw}x{th} differs from {w}x{h}");
            std::process::exit(2);
        }
        let ch = |img: &[[f32; 3]], c: usize| mean(img.iter().map(|p| f64::from(p[c])));
        let worst = (0..3)
            .map(|c| (ch(&t, c) / ch(&r, c) - 1.0).abs())
            .fold(0.0, f64::max);
        let all = mean(r.iter().flatten().map(|&v| f64::from(v)));
        let n = 4;
        let (bw, bh) = (w / n, h / n);
        let mut worst_block = 0.0f64;
        for by in 0..n {
            for bx in 0..n {
                let block = |img: &[[f32; 3]]| {
                    mean((0..bh).flat_map(|y| {
                        let row = (by * bh + y) * w + bx * bw;
                        img[row..row + bw].iter().flatten().map(|&v| f64::from(v))
                    }))
                };
                let (a, b) = (block(&r), block(&t));
                if a.max(b) > 0.05 * all {
                    worst_block = worst_block.max(if a > 0.0 {
                        (b / a - 1.0).abs()
                    } else {
                        f64::INFINITY
                    });
                }
            }
        }
        let pairs = || {
            r.iter()
                .flatten()
                .zip(t.iter().flatten())
                .map(|(&a, &b)| f64::from(b - a))
        };
        let mae = mean(pairs().map(f64::abs)) / all;
        let mse = mean(pairs().map(|d| d * d));
        let peak = r.iter().flatten().fold(0.0f32, |m, &v| m.max(v)) as f64;
        let psnr = 10.0 * (peak * peak / mse).log10();
        let pass = worst <= gate_channel && worst_block <= gate_block;
        ok &= pass;
        println!(
            "{path}: channel {:.2}% block {:.2}% mae/mean {mae:.4} psnr {psnr:.1} dB {}",
            worst * 100.0,
            worst_block * 100.0,
            if pass { "PASS" } else { "FAIL" }
        );
    }
    std::process::exit(if ok { 0 } else { 1 });
}
