use crate::ImageId;

/// Material IR, split per ADR-0008 so stylization never leaks into the physical base.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Material {
    pub base: BaseBsdf,
    /// Applied on top of `base` for stylized output only; Reference mode ignores it.
    pub stylization: Vec<StylizationLayer>,
    pub outputs: OutputChannels,
}

/// Physically based surface response (glTF metallic-roughness model, REQ-CORE-003).
#[derive(Clone, Debug, PartialEq)]
pub struct BaseBsdf {
    pub base_color: [f32; 3],
    pub metallic: f32,
    pub roughness: f32,
    /// 0 = opaque, 1 = fully transmissive dielectric.
    pub transmission: f32,
    pub ior: f32,
    pub emission: [f32; 3],
    /// Textures multiply the factors above (glTF semantics) and hold linear values. Sampling is
    /// repeat-wrapped trilinear; UVs come from the mesh. The image ids must come from the same scene.
    pub base_color_texture: Option<ImageId>,
    /// Roughness in green, metallic in blue.
    pub metallic_roughness_texture: Option<ImageId>,
    pub emission_texture: Option<ImageId>,
    /// Tangent-space normal map (+Y up, glTF convention). Tangents are derived from the UVs.
    pub normal_texture: Option<ImageId>,
    /// Scales the map's x and y before normalizing.
    pub normal_scale: f32,
}

impl Default for BaseBsdf {
    fn default() -> Self {
        Self {
            base_color: [0.8; 3],
            metallic: 0.0,
            roughness: 0.5,
            transmission: 0.0,
            ior: 1.5,
            emission: [0.0; 3],
            base_color_texture: None,
            metallic_roughness_texture: None,
            emission_texture: None,
            normal_texture: None,
            normal_scale: 1.0,
        }
    }
}

/// Stylization is non-physical: Reference mode must skip every layer (ADR-0008).
/// Variants for REQ-STY-003 to 005 arrive with their own slices.
#[derive(Clone, Debug, PartialEq)]
pub enum StylizationLayer {
    HybridSurface(HybridSurface),
    ToonRamp(ToonRamp),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum StylizationError {
    /// A parameter is outside its range (NaN counts as outside).
    OutOfRange(&'static str),
    /// `ToonRamp` needs one palette color per band.
    PaletteLength { expected: usize, found: usize },
}

impl StylizationLayer {
    pub fn validate(&self) -> Result<(), StylizationError> {
        match self {
            Self::HybridSurface(h) => h.validate(),
            Self::ToonRamp(t) => t.validate(),
        }
    }
}

/// Per-component blend between the physical result and the toon result (REQ-STY-001).
/// 0 = physical, 1 = fully stylized; each is in `0..=1`.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct HybridSurface {
    pub diffuse: f32,
    pub specular: f32,
    pub gi: f32,
    pub shadow: f32,
    pub outline: f32,
}

impl HybridSurface {
    /// Every component fully stylized.
    pub const TOON: Self = Self {
        diffuse: 1.0,
        specular: 1.0,
        gi: 1.0,
        shadow: 1.0,
        outline: 1.0,
    };

    fn validate(&self) -> Result<(), StylizationError> {
        for (name, v) in [
            ("hybrid.diffuse", self.diffuse),
            ("hybrid.specular", self.specular),
            ("hybrid.gi", self.gi),
            ("hybrid.shadow", self.shadow),
            ("hybrid.outline", self.outline),
        ] {
            unit_range(name, v)?;
        }
        Ok(())
    }
}

/// Quantizes each light's contribution into shadow bands (REQ-STY-002).
/// Band count is `thresholds.len() + 1`, bands ordered dark to lit.
#[derive(Clone, Debug, PartialEq)]
pub struct ToonRamp {
    /// Strictly increasing values in `0..=1` on the light's N·L-style response.
    pub thresholds: Vec<f32>,
    /// Soft edge width at each threshold, in `0..=1`; 0 is a hard step.
    pub feather: f32,
    /// One linear RGB multiplier per band, dark to lit.
    pub palette: Vec<[f32; 3]>,
    /// How far light wraps past the terminator, in `0..=1`.
    pub light_wrap: f32,
}

impl ToonRamp {
    fn validate(&self) -> Result<(), StylizationError> {
        for &t in &self.thresholds {
            unit_range("toon.thresholds", t)?;
        }
        if !self.thresholds.windows(2).all(|w| w[0] < w[1]) {
            return Err(StylizationError::OutOfRange("toon.thresholds"));
        }
        unit_range("toon.feather", self.feather)?;
        unit_range("toon.light_wrap", self.light_wrap)?;
        let expected = self.thresholds.len() + 1;
        if self.palette.len() != expected {
            return Err(StylizationError::PaletteLength {
                expected,
                found: self.palette.len(),
            });
        }
        if !self
            .palette
            .iter()
            .flatten()
            .all(|c| c.is_finite() && *c >= 0.0)
        {
            return Err(StylizationError::OutOfRange("toon.palette"));
        }
        Ok(())
    }
}

fn unit_range(name: &'static str, v: f32) -> Result<(), StylizationError> {
    if (0.0..=1.0).contains(&v) {
        Ok(())
    } else {
        Err(StylizationError::OutOfRange(name))
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct OutputChannels {
    /// Extra AOVs written besides the beauty pass.
    pub aovs: Vec<Aov>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Aov {
    Albedo,
    Normal,
    Depth,
    ObjectId,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ramp() -> ToonRamp {
        ToonRamp {
            thresholds: vec![0.3, 0.7],
            feather: 0.05,
            palette: vec![[0.3; 3], [0.7; 3], [1.0; 3]],
            light_wrap: 0.0,
        }
    }

    #[test]
    fn accepts_valid_layers() {
        assert_eq!(
            StylizationLayer::HybridSurface(HybridSurface::TOON).validate(),
            Ok(())
        );
        assert_eq!(StylizationLayer::ToonRamp(ramp()).validate(), Ok(()));
    }

    #[test]
    fn hybrid_rejects_out_of_range_and_nan() {
        for v in [-0.1, 1.1, f32::NAN] {
            let h = HybridSurface {
                gi: v,
                ..Default::default()
            };
            assert_eq!(
                StylizationLayer::HybridSurface(h).validate(),
                Err(StylizationError::OutOfRange("hybrid.gi"))
            );
        }
    }

    #[test]
    fn toon_rejects_bad_ramp() {
        let check = |r: ToonRamp| StylizationLayer::ToonRamp(r).validate();
        let unsorted = ToonRamp {
            thresholds: vec![0.7, 0.3],
            ..ramp()
        };
        assert_eq!(
            check(unsorted),
            Err(StylizationError::OutOfRange("toon.thresholds"))
        );
        let short = ToonRamp {
            palette: vec![[1.0; 3]; 2],
            ..ramp()
        };
        assert_eq!(
            check(short),
            Err(StylizationError::PaletteLength {
                expected: 3,
                found: 2
            })
        );
        let negative = ToonRamp {
            palette: vec![[-1.0; 3]; 3],
            ..ramp()
        };
        assert_eq!(
            check(negative),
            Err(StylizationError::OutOfRange("toon.palette"))
        );
    }
}
