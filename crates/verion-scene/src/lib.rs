//! Scene IR: the renderer's internal scene representation, independent of any
//! input format or GPU API (REQ-CORE-001).

mod mesh;

pub use mesh::{Mesh, MeshError};
