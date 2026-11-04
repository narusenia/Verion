//! Scene IR: the renderer's internal scene representation, independent of any
//! input format or GPU API (REQ-CORE-001).

mod material;
mod mesh;

pub use material::{Aov, BaseBsdf, Material, OutputChannels, StylizationLayer};
pub use mesh::{Mesh, MeshError};
