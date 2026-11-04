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

/// No layers are defined yet; variants arrive with REQ-STY-001 to 005.
#[derive(Clone, Debug, PartialEq)]
pub enum StylizationLayer {}

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
