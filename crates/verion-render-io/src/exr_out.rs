//! Multi-channel EXR output (REQ-IO-003): Beauty as R/G/B, the normal AOV as N.X/N.Y/N.Z, and
//! render metadata in the header.

use std::{fmt, path::Path, result::Result};

use exr::{meta::attribute::Chromaticities, prelude::*};
use verion_scene::{ColorSpace, Oetf, OutputTransform, ToneMap};

/// Render settings recorded in the file.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RenderInfo {
    /// The pixels come from a Reference-mode render, free of stylization and AI approximation.
    pub physical: bool,
    pub samples: u32,
}

/// One rendered frame. Pixels are row-major from the top-left, radiance in `working_space`.
pub struct ExrFrame<'a> {
    pub width: u32,
    pub height: u32,
    pub working_space: ColorSpace,
    pub beauty: &'a [[f32; 3]],
    /// World-space normals, written untouched.
    pub normal: Option<&'a [[f32; 3]]>,
    pub info: RenderInfo,
}

#[derive(Debug)]
pub enum ExrError {
    /// Zero size, or a pixel buffer that does not match it.
    BadFrame(String),
    Exr(String),
}

impl fmt::Display for ExrError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::BadFrame(why) => write!(f, "invalid frame: {why}"),
            Self::Exr(why) => write!(f, "EXR error: {why}"),
        }
    }
}

impl std::error::Error for ExrError {}

fn channel(name: &str, pixels: &[[f32; 3]], axis: usize) -> AnyChannel<FlatSamples> {
    let values = pixels.iter().map(|p| p[axis]).collect();
    AnyChannel::new(name, FlatSamples::F32(values))
}

fn xy(p: [f32; 2]) -> Vec2<f32> {
    Vec2(p[0], p[1])
}

/// Writes `frame` to `path`. Beauty goes through `transform` (use `OutputTransform::linear` for a
/// scene-linear file); the file is marked physical only when the frame is and the transform leaves
/// values untouched apart from the primaries.
pub fn write_exr(
    path: &Path,
    frame: &ExrFrame,
    transform: &OutputTransform,
) -> Result<(), ExrError> {
    let size = frame.width as usize * frame.height as usize;
    let bad = |why: &str| Err(ExrError::BadFrame(why.into()));
    if size == 0 {
        return bad("size must be non-zero");
    }
    if frame.beauty.len() != size || frame.normal.is_some_and(|n| n.len() != size) {
        return bad("pixel count does not match width x height");
    }

    let beauty: Vec<[f32; 3]> = frame
        .beauty
        .iter()
        .map(|&p| transform.apply(frame.working_space, p))
        .collect();
    let mut channels = vec![
        channel("R", &beauty, 0),
        channel("G", &beauty, 1),
        channel("B", &beauty, 2),
    ];
    if let Some(normal) = frame.normal {
        channels.extend(
            ["N.X", "N.Y", "N.Z"]
                .iter()
                .enumerate()
                .map(|(i, n)| channel(n, normal, i)),
        );
    }

    let untouched = transform.tone_map == ToneMap::None && transform.oetf == Oetf::Linear;
    let text = |s: String| AttributeValue::Text(Text::from(s.as_str()));
    let mut attributes = LayerAttributes::default();
    let other = &mut attributes.other;
    other.insert(
        Text::from("verion/physical"),
        text((frame.info.physical && untouched).to_string()),
    );
    other.insert(
        Text::from("verion/samples"),
        AttributeValue::I32(frame.info.samples.min(i32::MAX as u32) as i32),
    );
    other.insert(
        Text::from("verion/workingSpace"),
        text(format!("{:?}", frame.working_space)),
    );
    other.insert(
        Text::from("verion/outputTransform"),
        text(format!("{transform:?}")),
    );

    let layer = Layer::new(
        (frame.width as usize, frame.height as usize),
        attributes,
        Encoding::FAST_LOSSLESS,
        AnyChannels::sort(channels.into_iter().collect()),
    );
    let mut image = Image::from_layer(layer);
    let [red, green, blue, white] = transform.target.chromaticities().map(xy);
    image.attributes.chromaticities = Some(Chromaticities {
        red,
        green,
        blue,
        white,
    });

    image
        .write()
        .to_file(path)
        .map_err(|e| ExrError::Exr(e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp(name: &str) -> std::path::PathBuf {
        std::env::temp_dir().join(format!("verion-{}-{name}", std::process::id()))
    }

    fn frame<'a>(beauty: &'a [[f32; 3]], normal: Option<&'a [[f32; 3]]>) -> ExrFrame<'a> {
        ExrFrame {
            width: 2,
            height: 1,
            working_space: ColorSpace::LinearRec709,
            beauty,
            normal,
            info: RenderInfo {
                physical: true,
                samples: 64,
            },
        }
    }

    fn read_back(path: &Path) -> Image<Layer<AnyChannels<FlatSamples>>> {
        read()
            .no_deep_data()
            .largest_resolution_level()
            .all_channels()
            .first_valid_layer()
            .all_attributes()
            .from_file(path)
            .unwrap()
    }

    fn values(img: &Image<Layer<AnyChannels<FlatSamples>>>, name: &str) -> Vec<f32> {
        let list = &img.layer_data.channel_data.list;
        let ch = list.iter().find(|c| c.name.to_string() == name).unwrap();
        ch.sample_data.values_as_f32().collect()
    }

    #[test]
    fn writes_beauty_normal_and_metadata() {
        let beauty = [[1.0, 2.0, 3.0], [0.25, 0.5, 4.0]];
        let normal = [[0.0, 0.0, 1.0], [1.0, 0.0, 0.0]];
        let path = temp("aov.exr");
        let t = OutputTransform::linear(ColorSpace::LinearRec709);
        write_exr(&path, &frame(&beauty, Some(&normal)), &t).unwrap();
        let img = read_back(&path);
        std::fs::remove_file(&path).ok();

        assert_eq!(values(&img, "R"), [1.0, 0.25]);
        assert_eq!(values(&img, "B"), [3.0, 4.0]);
        assert_eq!(values(&img, "N.Z"), [1.0, 0.0]);
        let other = &img.layer_data.attributes.other;
        let get = |k: &str| other.get(&Text::from(k)).cloned();
        assert_eq!(
            get("verion/physical"),
            Some(AttributeValue::Text(Text::from("true")))
        );
        assert_eq!(get("verion/samples"), Some(AttributeValue::I32(64)));
        assert_eq!(img.attributes.chromaticities.unwrap().red, Vec2(0.64, 0.33));
    }

    #[test]
    fn converts_primaries_and_marks_display_output_non_physical() {
        let beauty = [[1.0, 0.0, 0.0], [0.0, 0.0, 0.0]];
        let path = temp("aces.exr");
        let t = OutputTransform::linear(ColorSpace::AcesCg);
        write_exr(&path, &frame(&beauty, None), &t).unwrap();
        let img = read_back(&path);
        assert!((values(&img, "R")[0] - 0.613_097).abs() < 1e-6);
        assert_eq!(
            img.attributes.chromaticities.unwrap().white,
            Vec2(0.32168, 0.33767)
        );

        write_exr(&path, &frame(&beauty, None), &OutputTransform::display()).unwrap();
        let img = read_back(&path);
        std::fs::remove_file(&path).ok();
        assert_eq!(
            img.layer_data
                .attributes
                .other
                .get(&Text::from("verion/physical")),
            Some(&AttributeValue::Text(Text::from("false")))
        );
    }

    #[test]
    fn rejects_mismatched_frames() {
        let t = OutputTransform::default();
        let path = temp("bad.exr");
        let one = [[0.0; 3]];
        assert!(matches!(
            write_exr(&path, &frame(&one, None), &t),
            Err(ExrError::BadFrame(_))
        ));
        let two = [[0.0; 3]; 2];
        assert!(matches!(
            write_exr(&path, &frame(&two, Some(&one)), &t),
            Err(ExrError::BadFrame(_))
        ));
    }
}
