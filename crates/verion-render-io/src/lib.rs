//! Scene input and image output. glTF types stay inside this crate (ADR-0003).

mod gltf_import;

pub use gltf_import::{
    Error, Import, load_gltf, load_gltf_in, load_gltf_slice, load_gltf_slice_in,
};
