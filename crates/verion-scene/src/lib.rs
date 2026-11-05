//! Scene IR: the renderer's internal scene representation, independent of any
//! input format or GPU API (REQ-CORE-001).

mod color;
mod image;
mod material;
mod mesh;
mod scene;
mod shading;

pub use color::{ColorSpace, Oetf, OutputTransform, ToneMap};
pub use image::{Image, ImageError};
pub use material::{
    Aov, BaseBsdf, ColorAdjust, HighlightShape, HybridSurface, MatCap, Material, OutlineStyle,
    OutputChannels, RimLight, ShadowPalette, StylizationError, StylizationLayer, StylizedSpecular,
    ToonRamp,
};
pub use mesh::{Mesh, MeshError};
pub use scene::{
    Camera, IDENTITY, ImageId, Instance, InstanceId, Light, LightId, MaterialId, MeshId, Revisions,
    Scene, SceneError, Transform,
};
pub use shading::{LIGHT_SLOTS, LightComponents, ShadingContext};
