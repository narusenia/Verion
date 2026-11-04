//! Scene IR: the renderer's internal scene representation, independent of any
//! input format or GPU API (REQ-CORE-001).

mod image;
mod material;
mod mesh;
mod scene;

pub use image::{Image, ImageError};
pub use material::{Aov, BaseBsdf, Material, OutputChannels, StylizationLayer};
pub use mesh::{Mesh, MeshError};
pub use scene::{
    Camera, IDENTITY, ImageId, Instance, InstanceId, Light, LightId, MaterialId, MeshId, Revisions,
    Scene, SceneError, Transform,
};
