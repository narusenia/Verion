//! Multi-channel EXR output (REQ-IO-003): Beauty as R/G/B, the normal AOV as N.X/N.Y/N.Z, and
//! render metadata in the header.

use std::{fmt, path::Path, result::Result};

use exr::{meta::attribute::Chromaticities, prelude::*};
use verion_scene::{ColorSpace, Oetf, OutputTransform, ToneMap};

/// The whole-image color grade applied to Beauty (REQ-STY-011), as recorded in the file.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct GradeInfo {
    /// Gain in stops.
    pub exposure: f32,
    pub saturation: f32,
    pub white_balance: [f32; 3],
}

/// Render settings recorded in the file.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RenderInfo {
    /// The pixels come from a Reference-mode render, free of stylization and AI approximation.
    pub physical: bool,
    pub samples: u32,
    /// `Revisions::stylization` of the scene; identifies the stylization the pixels were made with.
    pub stylization_revision: u64,
    /// The color grade applied to Beauty; `None` when none was.
    pub grade: Option<GradeInfo>,
    /// Beauty went through a denoiser (written as `verion/denoiser`). A denoised frame is not physical.
    pub denoiser: Option<&'static str>,
    /// Per-pixel adaptive sampling threshold (written as `verion/adaptiveThreshold`); `samples` is
    /// then the most any pixel took. Stopping on a pixel's own noise estimate biases it, so an
    /// adaptive frame is not physical.
    pub adaptive_threshold: Option<f32>,
    /// ReSTIR DI was on (written as `verion/restir`). Its reuse is biased near shadow edges, so
    /// the frame is not physical.
    pub restir: bool,
}

/// Optional primary-ray AOVs (all the same size as the frame).
#[derive(Clone, Copy, Debug, Default)]
pub struct ExrAovs<'a> {
    /// Base color in the frame's working space; converted to the output primaries like Beauty.
    pub albedo: Option<&'a [[f32; 3]]>,
    /// Distance along the camera's forward axis, written as `Z`.
    pub depth: Option<&'a [f32]>,
    /// Instance id plus one (0 = background), written as the 32-bit integer channel `ObjectId`.
    pub object_id: Option<&'a [u32]>,
    /// Material index plus one (0 = background), written as the 32-bit integer channel `MaterialId`.
    pub material_id: Option<&'a [u32]>,
    /// Samples each pixel took under adaptive sampling, written as the integer channel `SampleCount`.
    pub sample_count: Option<&'a [u32]>,
    pub lighting: Option<ExrLighting<'a>>,
}

/// First-hit lighting split (REQ-STY-006). The radiance parts are in the frame's working space,
/// converted to the output primaries like Albedo, and are not tone mapped.
#[derive(Clone, Copy, Debug)]
pub struct ExrLighting<'a> {
    pub direct_diffuse: &'a [[f32; 3]],
    pub indirect_diffuse: &'a [[f32; 3]],
    pub specular: &'a [[f32; 3]],
    pub transmission: &'a [[f32; 3]],
    pub emission: &'a [[f32; 3]],
    /// Unshadowed share of the direct light, written as `Visibility.V`.
    pub visibility: &'a [f32],
}

/// One rendered frame. Pixels are row-major from the top-left, radiance in `working_space`.
pub struct ExrFrame<'a> {
    pub width: u32,
    pub height: u32,
    pub working_space: ColorSpace,
    pub beauty: &'a [[f32; 3]],
    /// World-space normals, written untouched.
    pub normal: Option<&'a [[f32; 3]]>,
    pub aovs: ExrAovs<'a>,
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
    let a = &frame.aovs;
    if frame.beauty.len() != size
        || frame.normal.is_some_and(|n| n.len() != size)
        || a.albedo.is_some_and(|p| p.len() != size)
        || a.depth.is_some_and(|p| p.len() != size)
        || a.object_id.is_some_and(|p| p.len() != size)
        || a.material_id.is_some_and(|p| p.len() != size)
        || a.sample_count.is_some_and(|p| p.len() != size)
        || a.lighting.is_some_and(|l| {
            [
                l.direct_diffuse,
                l.indirect_diffuse,
                l.specular,
                l.transmission,
                l.emission,
            ]
            .iter()
            .any(|p| p.len() != size)
                || l.visibility.len() != size
        })
    {
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

    if let Some(albedo) = a.albedo {
        let primaries = OutputTransform::linear(transform.target);
        let albedo: Vec<[f32; 3]> = albedo
            .iter()
            .map(|&p| primaries.apply(frame.working_space, p))
            .collect();
        channels.extend(
            ["Albedo.R", "Albedo.G", "Albedo.B"]
                .iter()
                .enumerate()
                .map(|(i, n)| channel(n, &albedo, i)),
        );
    }
    if let Some(l) = a.lighting {
        let primaries = OutputTransform::linear(transform.target);
        let parts = [
            ("DirectDiffuse", l.direct_diffuse),
            ("IndirectDiffuse", l.indirect_diffuse),
            ("Specular", l.specular),
            ("Transmission", l.transmission),
            ("Emission", l.emission),
        ];
        for (name, part) in parts {
            let part: Vec<[f32; 3]> = part
                .iter()
                .map(|&p| primaries.apply(frame.working_space, p))
                .collect();
            for (i, c) in ["R", "G", "B"].iter().enumerate() {
                channels.push(channel(&format!("{name}.{c}"), &part, i));
            }
        }
        channels.push(AnyChannel::new(
            "Visibility.V",
            FlatSamples::F32(l.visibility.to_vec()),
        ));
    }
    if let Some(depth) = a.depth {
        channels.push(AnyChannel::new("Z", FlatSamples::F32(depth.to_vec())));
    }
    if let Some(ids) = a.object_id {
        channels.push(AnyChannel::new("ObjectId", FlatSamples::U32(ids.to_vec())));
    }
    if let Some(ids) = a.material_id {
        channels.push(AnyChannel::new(
            "MaterialId",
            FlatSamples::U32(ids.to_vec()),
        ));
    }

    if let Some(n) = a.sample_count {
        channels.push(AnyChannel::new("SampleCount", FlatSamples::U32(n.to_vec())));
    }

    let untouched = transform.tone_map == ToneMap::None && transform.oetf == Oetf::Linear;
    let text = |s: String| AttributeValue::Text(Text::from(s.as_str()));
    let mut attributes = LayerAttributes::default();
    let other = &mut attributes.other;
    other.insert(
        Text::from("verion/physical"),
        text(
            (frame.info.physical
                && untouched
                && frame.info.denoiser.is_none()
                && frame.info.adaptive_threshold.is_none()
                && !frame.info.restir)
                .to_string(),
        ),
    );
    other.insert(
        Text::from("verion/samples"),
        AttributeValue::I32(frame.info.samples.min(i32::MAX as u32) as i32),
    );
    other.insert(
        Text::from("verion/stylizationRevision"),
        text(frame.info.stylization_revision.to_string()),
    );
    if let Some(d) = frame.info.denoiser {
        other.insert(Text::from("verion/denoiser"), text(d.to_string()));
    }
    if let Some(t) = frame.info.adaptive_threshold {
        other.insert(
            Text::from("verion/adaptiveThreshold"),
            AttributeValue::F32(t),
        );
    }
    if frame.info.restir {
        other.insert(Text::from("verion/restir"), text("di".to_string()));
    }
    if let Some(g) = frame.info.grade {
        other.insert(
            Text::from("verion/exposure"),
            AttributeValue::F32(g.exposure),
        );
        other.insert(
            Text::from("verion/saturation"),
            AttributeValue::F32(g.saturation),
        );
        let [r, gr, b] = g.white_balance;
        other.insert(
            Text::from("verion/whiteBalance"),
            AttributeValue::FloatVec3((r, gr, b)),
        );
    }
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
            aovs: ExrAovs::default(),
            info: RenderInfo {
                physical: true,
                samples: 64,
                stylization_revision: 3,
                grade: None,
                denoiser: None,
                adaptive_threshold: None,
                restir: false,
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
        assert_eq!(
            get("verion/stylizationRevision"),
            Some(AttributeValue::Text(Text::from("3")))
        );
        assert_eq!(img.attributes.chromaticities.unwrap().red, Vec2(0.64, 0.33));
    }

    #[test]
    fn records_the_color_grade_only_when_one_was_applied() {
        let beauty = [[0.0; 3]; 2];
        let t = OutputTransform::linear(ColorSpace::LinearRec709);
        let attrs = |f: &ExrFrame, name: &str| {
            let path = temp(name);
            write_exr(&path, f, &t).unwrap();
            let img = read_back(&path);
            std::fs::remove_file(&path).ok();
            img.layer_data.attributes.other
        };
        let plain = attrs(&frame(&beauty, None), "grade-none.exr");
        assert!(!plain.contains_key(&Text::from("verion/exposure")));
        assert!(!plain.contains_key(&Text::from("verion/denoiser")));

        let mut f = frame(&beauty, None);
        f.info.denoiser = Some("oidn");
        let denoised = attrs(&f, "denoised.exr");
        let get = |k: &str| denoised.get(&Text::from(k)).cloned();
        assert_eq!(
            get("verion/denoiser"),
            Some(AttributeValue::Text(Text::from("oidn")))
        );
        assert_eq!(
            get("verion/physical"),
            Some(AttributeValue::Text(Text::from("false")))
        );

        let mut f = frame(&beauty, None);
        f.info.adaptive_threshold = Some(0.02);
        let adaptive = attrs(&f, "adaptive.exr");
        let get = |k: &str| adaptive.get(&Text::from(k)).cloned();
        assert_eq!(
            get("verion/adaptiveThreshold"),
            Some(AttributeValue::F32(0.02))
        );
        assert_eq!(
            get("verion/physical"),
            Some(AttributeValue::Text(Text::from("false")))
        );

        let mut f = frame(&beauty, None);
        f.info.grade = Some(GradeInfo {
            exposure: -1.0,
            saturation: 0.8,
            white_balance: [1.1, 1.0, 0.9],
        });
        let graded = attrs(&f, "grade-some.exr");
        let get = |k: &str| graded.get(&Text::from(k)).cloned();
        assert_eq!(get("verion/exposure"), Some(AttributeValue::F32(-1.0)));
        assert_eq!(get("verion/saturation"), Some(AttributeValue::F32(0.8)));
        assert_eq!(
            get("verion/whiteBalance"),
            Some(AttributeValue::FloatVec3((1.1, 1.0, 0.9)))
        );
    }

    #[test]
    fn writes_albedo_depth_and_object_id() {
        let beauty = [[0.0; 3]; 2];
        let albedo = [[1.0, 0.0, 0.0], [0.5, 0.5, 0.5]];
        let mut f = frame(&beauty, None);
        f.aovs = ExrAovs {
            albedo: Some(&albedo),
            depth: Some(&[3.0, 0.0]),
            object_id: Some(&[7, 0]),
            material_id: Some(&[3, 0]),
            sample_count: Some(&[16, 64]),
            ..Default::default()
        };
        let path = temp("ids.exr");
        let t = OutputTransform::linear(ColorSpace::LinearRec709);
        write_exr(&path, &f, &t).unwrap();
        let img = read_back(&path);
        std::fs::remove_file(&path).ok();

        assert_eq!(values(&img, "Albedo.R"), [1.0, 0.5]);
        assert_eq!(values(&img, "Z"), [3.0, 0.0]);
        assert_eq!(values(&img, "ObjectId"), [7.0, 0.0]);
        assert_eq!(values(&img, "MaterialId"), [3.0, 0.0]);
        assert_eq!(values(&img, "SampleCount"), [16.0, 64.0]);
        let list = &img.layer_data.channel_data.list;
        let id = list
            .iter()
            .find(|c| c.name.to_string() == "ObjectId")
            .unwrap();
        assert!(matches!(id.sample_data, FlatSamples::U32(_)));

        f.aovs.depth = Some(&[1.0]);
        assert!(matches!(
            write_exr(&path, &f, &t),
            Err(ExrError::BadFrame(_))
        ));
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

    #[test]
    fn writes_lighting_parts() {
        let beauty = [[0.0; 3]; 2];
        let part = |v: f32| [[v, 2.0 * v, 3.0 * v]; 2];
        let (dd, id, sp, tr, em) = (part(1.0), part(2.0), part(3.0), part(4.0), part(5.0));
        let mut f = frame(&beauty, None);
        f.aovs.lighting = Some(ExrLighting {
            direct_diffuse: &dd,
            indirect_diffuse: &id,
            specular: &sp,
            transmission: &tr,
            emission: &em,
            visibility: &[0.25, 1.0],
        });
        let path = temp("lighting.exr");
        let t = OutputTransform::linear(ColorSpace::LinearRec709);
        write_exr(&path, &f, &t).unwrap();
        let img = read_back(&path);
        std::fs::remove_file(&path).ok();

        assert_eq!(values(&img, "DirectDiffuse.G"), [2.0, 2.0]);
        assert_eq!(values(&img, "IndirectDiffuse.R"), [2.0, 2.0]);
        assert_eq!(values(&img, "Specular.B"), [9.0, 9.0]);
        assert_eq!(values(&img, "Transmission.R"), [4.0, 4.0]);
        assert_eq!(values(&img, "Emission.R"), [5.0, 5.0]);
        assert_eq!(values(&img, "Visibility.V"), [0.25, 1.0]);

        f.aovs.lighting.as_mut().unwrap().visibility = &[1.0];
        assert!(matches!(
            write_exr(&path, &f, &t),
            Err(ExrError::BadFrame(_))
        ));
    }
}
