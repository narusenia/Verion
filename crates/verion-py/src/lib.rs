//! Python extension `verion`: builds the Scene IR from numpy arrays and renders it on the GPU
//! (REQ-DCC-001). The logic lives in the Rust core; this layer only converts types and keeps the
//! GPU on its own thread so a DCC's UI never waits on a render (ADR-0019).

mod engine;
mod scene;
mod settings;

use numpy::PyArrayMethods as _;
use pyo3::prelude::*;

/// Bumped when the Python API changes in a way the add-on must follow; the add-on refuses an
/// extension with another value (plugins/blender/verion_blender/native.py).
const ABI_VERSION: u32 = 1;

/// The first three channels of a `.hdr` or `.exr` file as float32 (H, W, 3), first row on top, in
/// linear Rec.709 (a Verion render-cli output, for tools that compare renders).
#[pyfunction]
fn read_image<'py>(py: Python<'py>, path: &str) -> PyResult<Bound<'py, numpy::PyArray3<f32>>> {
    let image = verion_render_io::load_hdri(path.as_ref(), verion_scene::ColorSpace::LinearRec709)
        .map_err(|e| pyo3::exceptions::PyValueError::new_err(format!("{path}: {e}")))?;
    let (w, h) = (image.width() as usize, image.height() as usize);
    let flat: Vec<f32> = image.pixels().iter().flatten().copied().collect();
    numpy::PyArray1::from_vec(py, flat).reshape([h, w, 3])
}

/// The OIDN library the host ships (Blender's own copy), tried after `VERION_OIDN_LIB`.
#[pyfunction]
fn set_oidn_library(path: &str) {
    verion_denoise::set_host_library(path);
}

#[pymodule]
fn verion(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(set_oidn_library, m)?)?;
    m.add_function(wrap_pyfunction!(read_image, m)?)?;
    m.add_class::<scene::Scene>()?;
    m.add_class::<engine::Engine>()?;
    m.add_class::<engine::Job>()?;
    m.add("ABI_VERSION", ABI_VERSION)?;
    m.add("__version__", env!("CARGO_PKG_VERSION"))
}
