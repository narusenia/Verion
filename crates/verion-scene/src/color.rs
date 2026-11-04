//! Working color spaces and output transforms (REQ-CORE-005).
//!
//! Every color value in the scene IR (factors, light colors, color textures, sky) is linear RGB in
//! the scene's working space. Importers convert into it; `OutputTransform` converts out of it.

type Mat3 = [[f32; 3]; 3];

/// Linear RGB primaries. Conversions keep (1, 1, 1) white, so equal-energy RGB stays grey.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum ColorSpace {
    /// Linear Rec.709 / sRGB primaries.
    #[default]
    LinearRec709,
    /// ACEScg (AP1 primaries, D60 white; the matrices Bradford-adapt from D65).
    AcesCg,
}

// Rec.709 -> ACEScg, and its exact inverse (computed from the forward matrix so round trips close).
const REC709_TO_ACESCG: Mat3 = [
    [0.613_097, 0.339_523, 0.047_379],
    [0.070_194, 0.916_354, 0.013_452],
    [0.020_616, 0.109_570, 0.869_815],
];
const ACESCG_TO_REC709: Mat3 = [
    [1.705_052, -0.621_792, -0.083_258],
    [-0.130_257, 1.140_805, -0.010_548],
    [-0.024_004, -0.128_969, 1.152_972],
];

fn apply(m: &Mat3, c: [f32; 3]) -> [f32; 3] {
    m.map(|row| row[0] * c[0] + row[1] * c[1] + row[2] * c[2])
}

impl ColorSpace {
    /// Converts linear RGB between spaces. Out-of-gamut results can be negative; they are kept.
    pub fn convert(self, to: ColorSpace, rgb: [f32; 3]) -> [f32; 3] {
        match (self, to) {
            (Self::LinearRec709, Self::AcesCg) => apply(&REC709_TO_ACESCG, rgb),
            (Self::AcesCg, Self::LinearRec709) => apply(&ACESCG_TO_REC709, rgb),
            _ => rgb,
        }
    }

    /// CIE xy chromaticities of red, green, blue and white, as written to file metadata.
    pub fn chromaticities(self) -> [[f32; 2]; 4] {
        match self {
            Self::LinearRec709 => [[0.64, 0.33], [0.30, 0.60], [0.15, 0.06], [0.3127, 0.3290]],
            Self::AcesCg => [
                [0.713, 0.293],
                [0.165, 0.830],
                [0.128, 0.044],
                [0.32168, 0.33767],
            ],
        }
    }

    /// Relative luminance (Y) of a linear RGB value in this space.
    pub fn luminance(self, rgb: [f32; 3]) -> f32 {
        let w = match self {
            Self::LinearRec709 => [0.2126, 0.7152, 0.0722],
            Self::AcesCg => [0.272_229, 0.674_082, 0.053_689],
        };
        w[0] * rgb[0] + w[1] * rgb[1] + w[2] * rgb[2]
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum ToneMap {
    /// Values pass through unchanged (Reference output, EXR).
    #[default]
    None,
    /// `L / (1 + L)` applied to luminance, so hue is kept. Display only; not physically based.
    Reinhard,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Oetf {
    #[default]
    Linear,
    /// sRGB transfer function; clamps to [0, 1] first.
    Srgb,
}

/// Conversion from working-space radiance to an output: a target space, then tone map, then OETF.
/// Display and EXR output each pick their own.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct OutputTransform {
    pub target: ColorSpace,
    pub tone_map: ToneMap,
    pub oetf: Oetf,
}

impl OutputTransform {
    /// 8-bit sRGB display: Rec.709 primaries, Reinhard, sRGB encoding.
    pub fn display() -> Self {
        Self {
            target: ColorSpace::LinearRec709,
            tone_map: ToneMap::Reinhard,
            oetf: Oetf::Srgb,
        }
    }

    /// Scene-linear file output in `target`, values untouched apart from the primaries.
    pub fn linear(target: ColorSpace) -> Self {
        Self {
            target,
            tone_map: ToneMap::None,
            oetf: Oetf::Linear,
        }
    }

    pub fn apply(&self, working: ColorSpace, rgb: [f32; 3]) -> [f32; 3] {
        let mut c = working.convert(self.target, rgb);
        if self.tone_map == ToneMap::Reinhard {
            let scale = 1.0 / (1.0 + self.target.luminance(c).max(0.0));
            c = c.map(|v| v * scale);
        }
        match self.oetf {
            Oetf::Linear => c,
            Oetf::Srgb => c.map(|v| linear_to_srgb(v.clamp(0.0, 1.0))),
        }
    }
}

fn linear_to_srgb(c: f32) -> f32 {
    if c <= 0.003_130_8 {
        c * 12.92
    } else {
        1.055 * c.powf(1.0 / 2.4) - 0.055
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SPACES: [ColorSpace; 2] = [ColorSpace::LinearRec709, ColorSpace::AcesCg];

    fn close(a: [f32; 3], b: [f32; 3], tol: f32) -> bool {
        a.iter().zip(b).all(|(x, y)| (x - y).abs() < tol)
    }

    #[test]
    fn white_stays_white_and_round_trips() {
        for from in SPACES {
            for to in SPACES {
                assert!(close(from.convert(to, [1.0; 3]), [1.0; 3], 1e-4));
                let c = [0.2, 0.5, 0.9];
                assert!(close(to.convert(from, from.convert(to, c)), c, 1e-4));
            }
        }
    }

    #[test]
    fn rec709_red_lands_in_the_acescg_matrix_column() {
        let red = ColorSpace::LinearRec709.convert(ColorSpace::AcesCg, [1.0, 0.0, 0.0]);
        assert!(close(red, [0.613_097, 0.070_194, 0.020_616], 1e-6));
    }

    #[test]
    fn luminance_of_white_is_one() {
        for s in SPACES {
            assert!((s.luminance([1.0; 3]) - 1.0).abs() < 1e-4);
        }
    }

    #[test]
    fn display_transform_encodes_srgb_after_reinhard() {
        let out = OutputTransform::display().apply(ColorSpace::LinearRec709, [1.0; 3]);
        // Reinhard maps 1 to 0.5; sRGB encodes 0.5 as about 0.7354.
        assert!(close(out, [0.7354; 3], 1e-3), "{out:?}");
        assert_eq!(
            OutputTransform::display().apply(ColorSpace::LinearRec709, [0.0; 3]),
            [0.0; 3]
        );
    }

    #[test]
    fn linear_output_only_changes_primaries() {
        let c = [0.3, 0.6, 0.1];
        let t = OutputTransform::linear(ColorSpace::LinearRec709);
        assert_eq!(t.apply(ColorSpace::LinearRec709, c), c);
        let aces = OutputTransform::linear(ColorSpace::AcesCg).apply(ColorSpace::LinearRec709, c);
        assert_eq!(
            aces,
            ColorSpace::LinearRec709.convert(ColorSpace::AcesCg, c)
        );
    }
}
