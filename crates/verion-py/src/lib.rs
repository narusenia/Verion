//! Python extension `verion`: builds the Scene IR from numpy arrays and renders it on the GPU
//! (REQ-DCC-001). The logic lives in the Rust core; this layer only converts types and keeps the
//! GPU on its own thread so a DCC's UI never waits on a render (ADR-0019).

mod engine;
mod scene;
mod settings;

use pyo3::prelude::*;

/// Bumped when the Python API changes in a way the add-on must follow; the add-on refuses an
/// extension with another value (plugins/blender/verion_blender/native.py).
const ABI_VERSION: u32 = 1;

#[pymodule]
fn verion(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_class::<scene::Scene>()?;
    m.add_class::<engine::Engine>()?;
    m.add_class::<engine::Job>()?;
    m.add("ABI_VERSION", ABI_VERSION)?;
    m.add("__version__", env!("CARGO_PKG_VERSION"))
}
