//! `exr_png in.exr out.png [stops]`: sRGB preview of an EXR's beauty (exposure in stops, then clamp).

use std::{fs::File, io::BufWriter, path::Path};

use verion_render_io::load_hdri;
use verion_scene::ColorSpace;

fn srgb(v: f32) -> u8 {
    let v = v.clamp(0.0, 1.0);
    let e = if v <= 0.0031308 {
        12.92 * v
    } else {
        1.055 * v.powf(1.0 / 2.4) - 0.055
    };
    (e * 255.0 + 0.5) as u8
}

fn main() {
    let a: Vec<String> = std::env::args().skip(1).collect();
    if a.len() < 2 {
        eprintln!("usage: exr_png in.exr out.png [stops]");
        std::process::exit(2);
    }
    let gain = 2f32.powf(a.get(2).map_or(0.0, |s| s.parse().expect("stops")));
    let img = load_hdri(Path::new(&a[0]), ColorSpace::LinearRec709).expect("read exr");
    let data: Vec<u8> = img
        .pixels()
        .iter()
        .flatten()
        .map(|&v| srgb(v * gain))
        .collect();
    let mut enc = png::Encoder::new(
        BufWriter::new(File::create(&a[1]).expect("create png")),
        img.width(),
        img.height(),
    );
    enc.set_color(png::ColorType::Rgb);
    enc.write_header()
        .and_then(|mut w| w.write_image_data(&data))
        .expect("write png");
}
