/// Light slots per pixel in the lighting AOVs. Slots 0 to `LIGHT_SLOTS - 2` hold point, directional
/// and spot lights by index (later lights share the last of them); the final slot pools emissive
/// triangles and the environment map. Must match `shaders/pathtrace.slang`.
pub const LIGHT_SLOTS: usize = 4;

/// Input to a stylization function. Not tied to the primary hit, so a later stage can call it
/// from any bounce (ADR-0008, REQ-STY-008). Vectors are in world space, color in the working space.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ShadingContext {
    pub position: [f32; 3],
    pub normal: [f32; 3],
    /// Distance along the camera's forward axis.
    pub depth: f32,
    /// One entry per light, never summed, so each light can be staged separately.
    pub lights: Vec<LightComponents>,
}

/// One light's contribution at the shading point, split before any stylization.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct LightComponents {
    /// Unit vector from the point toward the light.
    pub direction: [f32; 3],
    pub diffuse: [f32; 3],
    pub specular: [f32; 3],
    /// 0 = fully shadowed, 1 = fully lit.
    pub visibility: f32,
}
