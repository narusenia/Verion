//! Environment map files for `Light::EnvironmentMap`: Radiance `.hdr` and OpenEXR `.exr`.

use std::{fmt, fs, path::Path, result::Result};

use exr::prelude::read_first_rgba_layer_from_file;
use verion_scene::{ColorSpace, Image};

#[derive(Debug)]
pub enum HdriError {
    Io(String),
    /// Not a file this loader reads (extension, orientation, encoding).
    Unsupported(String),
    /// Truncated or malformed data.
    Format(String),
}

impl fmt::Display for HdriError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io(why) => write!(f, "cannot read environment map: {why}"),
            Self::Unsupported(why) => write!(f, "unsupported environment map: {why}"),
            Self::Format(why) => write!(f, "invalid environment map: {why}"),
        }
    }
}

impl std::error::Error for HdriError {}

/// Loads a latitude-longitude HDRI and converts it into `space`.
///
/// `.hdr` is taken as Rec.709 primaries. `.exr` uses its chromaticities attribute to tell ACEScg
/// from Rec.709 and treats anything else as Rec.709.
pub fn load_hdri(path: &Path, space: ColorSpace) -> Result<Image, HdriError> {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .map(str::to_ascii_lowercase);
    let (width, height, pixels, source) = match ext.as_deref() {
        Some("hdr") => {
            let bytes = fs::read(path).map_err(|e| HdriError::Io(e.to_string()))?;
            let (w, h, px) = parse_hdr(&bytes)?;
            (w, h, px, ColorSpace::LinearRec709)
        }
        Some("exr") => read_exr(path)?,
        _ => {
            return Err(HdriError::Unsupported(
                "expected a .hdr or .exr file".into(),
            ));
        }
    };
    let pixels = pixels
        .into_iter()
        .map(|p| source.convert(space, p))
        .collect();
    Image::new(width, height, pixels).map_err(|e| HdriError::Format(e.to_string()))
}

/// Width, height, pixels and the color space the file declares.
type Decoded = (u32, u32, Vec<[f32; 3]>, ColorSpace);

fn read_exr(path: &Path) -> Result<Decoded, HdriError> {
    let image = read_first_rgba_layer_from_file(
        path,
        |res, _| (res.width(), vec![[0.0f32; 3]; res.area()]),
        |(width, px): &mut (usize, Vec<[f32; 3]>), pos, (r, g, b, _): (f32, f32, f32, f32)| {
            px[pos.y() * *width + pos.x()] = [r, g, b];
        },
    )
    .map_err(|e| HdriError::Format(e.to_string()))?;
    let source = match image.attributes.chromaticities {
        Some(c) if (c.red.x() - 0.713).abs() < 0.01 => ColorSpace::AcesCg,
        _ => ColorSpace::LinearRec709,
    };
    let size = image.layer_data.size;
    let (_, pixels) = image.layer_data.channel_data.pixels;
    Ok((size.width() as u32, size.height() as u32, pixels, source))
}

/// Decodes a Radiance RGBE file in the standard `-Y h +X w` orientation, flat or run-length
/// encoded per scanline. The old run-length variant is not supported.
fn parse_hdr(bytes: &[u8]) -> Result<(u32, u32, Vec<[f32; 3]>), HdriError> {
    let bad = |why: &str| HdriError::Format(why.into());
    let mut pos = 0;
    let mut line = || -> Option<&[u8]> {
        let rest = bytes.get(pos..)?;
        let end = rest.iter().position(|&b| b == b'\n')?;
        pos += end + 1;
        Some(&rest[..end])
    };
    if !line().is_some_and(|l| l.starts_with(b"#?")) {
        return Err(bad("missing #? signature"));
    }
    loop {
        let l = line().ok_or_else(|| bad("header ends before the resolution line"))?;
        if l.is_empty() {
            break;
        }
        if l.starts_with(b"FORMAT=") && l != b"FORMAT=32-bit_rle_rgbe" {
            return Err(HdriError::Unsupported(
                "only 32-bit_rle_rgbe is supported".into(),
            ));
        }
    }
    let res = line().ok_or_else(|| bad("missing resolution line"))?;
    let res = String::from_utf8_lossy(res);
    let parts: Vec<&str> = res.split_whitespace().collect();
    let (h, w) = match parts[..] {
        ["-Y", h, "+X", w] => (h.parse::<usize>(), w.parse::<usize>()),
        _ => {
            return Err(HdriError::Unsupported(
                "only -Y h +X w images are supported".into(),
            ));
        }
    };
    let (Ok(h), Ok(w)) = (h, w) else {
        return Err(bad("unreadable resolution"));
    };
    if w == 0 || h == 0 || w.saturating_mul(h) > 1 << 28 {
        return Err(bad("resolution out of range"));
    }

    let mut data = &bytes[pos..];
    let mut pixels: Vec<[f32; 3]> = Vec::new();
    let mut scan = vec![[0u8; 4]; w];
    for _ in 0..h {
        if (8..32768).contains(&w) && data.starts_with(&[2, 2, (w >> 8) as u8, w as u8]) {
            data = &data[4..];
            for channel in 0..4 {
                let mut x = 0;
                while x < w {
                    let (&count, rest) = data.split_first().ok_or_else(|| bad("truncated"))?;
                    data = rest;
                    let (run, literal) = if count > 128 {
                        (count as usize - 128, false)
                    } else {
                        (count as usize, true)
                    };
                    if run == 0 || x + run > w {
                        return Err(bad("bad run length"));
                    }
                    if literal {
                        let src = data.get(..run).ok_or_else(|| bad("truncated"))?;
                        for (px, &v) in scan[x..x + run].iter_mut().zip(src) {
                            px[channel] = v;
                        }
                        data = &data[run..];
                    } else {
                        let (&v, rest) = data.split_first().ok_or_else(|| bad("truncated"))?;
                        data = rest;
                        scan[x..x + run].iter_mut().for_each(|px| px[channel] = v);
                    }
                    x += run;
                }
            }
        } else {
            let src = data.get(..4 * w).ok_or_else(|| bad("truncated"))?;
            for (px, v) in scan.iter_mut().zip(src.as_chunks::<4>().0) {
                *px = *v;
            }
            data = &data[4 * w..];
        }
        pixels.extend(scan.iter().map(|&[r, g, b, e]| {
            if e == 0 {
                [0.0; 3]
            } else {
                let f = (f32::from(e) - 136.0).exp2();
                [f32::from(r) * f, f32::from(g) * f, f32::from(b) * f]
            }
        }));
    }
    Ok((w as u32, h as u32, pixels))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{ExrFrame, RenderInfo, write_exr};
    use verion_scene::OutputTransform;

    fn header(w: usize, h: usize) -> Vec<u8> {
        format!("#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y {h} +X {w}\n").into_bytes()
    }

    fn temp(name: &str) -> std::path::PathBuf {
        std::env::temp_dir().join(format!("verion-{}-{name}", std::process::id()))
    }

    #[test]
    fn decodes_flat_pixels() {
        let mut file = header(2, 1);
        // Exponent 129 scales the mantissas by 2^(129 - 136) = 1/128.
        file.extend([128, 64, 0, 129, 0, 0, 0, 0]);
        let (w, h, px) = parse_hdr(&file).unwrap();
        assert_eq!((w, h), (2, 1));
        assert_eq!(px, [[1.0, 0.5, 0.0], [0.0; 3]]);
    }

    #[test]
    fn decodes_run_length_scanlines() {
        let w = 8;
        let mut file = header(w, 1);
        file.extend([2, 2, 0, w as u8]);
        file.extend([128 + 8, 128]); // red: a run of 8
        file.extend([128 + 8, 0]); // green
        file.extend([3, 1, 2, 3, 128 + 5, 4]); // blue: literals 1 2 3, then a run of 5
        file.extend([128 + 8, 129]); // exponent
        let (_, _, px) = parse_hdr(&file).unwrap();
        assert_eq!(px.len(), w);
        assert_eq!(px[0], [1.0, 0.0, 1.0 / 128.0]);
        assert_eq!(px[7][2], 4.0 / 128.0);
    }

    #[test]
    fn rejects_bad_files() {
        assert!(matches!(
            parse_hdr(b"not an image"),
            Err(HdriError::Format(_))
        ));
        let mut flipped = b"#?RADIANCE\n\n+Y 1 +X 1\n".to_vec();
        flipped.extend([0; 4]);
        assert!(matches!(
            parse_hdr(&flipped),
            Err(HdriError::Unsupported(_))
        ));
        let mut short = header(4, 1);
        short.extend([0; 8]);
        assert!(matches!(parse_hdr(&short), Err(HdriError::Format(_))));
        assert!(matches!(
            load_hdri(Path::new("sky.png"), ColorSpace::default()),
            Err(HdriError::Unsupported(_))
        ));
    }

    #[test]
    fn loads_hdr_files_and_converts_into_the_working_space() {
        let mut file = header(1, 1);
        file.extend([128, 0, 0, 136]); // (128, 0, 0) * 2^0 = pure red of 128
        let path = temp("sky.hdr");
        fs::write(&path, file).unwrap();
        let img = load_hdri(&path, ColorSpace::AcesCg).unwrap();
        fs::remove_file(&path).ok();
        assert!((img.pixels()[0][0] - 128.0 * 0.613_097).abs() < 1e-3);
    }

    #[test]
    fn exr_round_trip_keeps_values_across_color_spaces() {
        let beauty = [[0.5, 2.0, 8.0], [1.0, 1.0, 1.0]];
        let frame = ExrFrame {
            width: 2,
            height: 1,
            working_space: ColorSpace::LinearRec709,
            beauty: &beauty,
            normal: None,
            info: RenderInfo {
                physical: true,
                samples: 1,
            },
        };
        let path = temp("sky.exr");
        // Written as ACEScg, read back as Rec.709: the chromaticities attribute must drive the conversion.
        write_exr(&path, &frame, &OutputTransform::linear(ColorSpace::AcesCg)).unwrap();
        let img = load_hdri(&path, ColorSpace::LinearRec709).unwrap();
        fs::remove_file(&path).ok();
        for (got, want) in img.pixels().iter().flatten().zip(beauty.iter().flatten()) {
            assert!((got - want).abs() < 1e-3, "{got} vs {want}");
        }
    }
}
