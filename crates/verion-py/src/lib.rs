use numpy::{IntoPyArray, PyArray2, PyReadonlyArray2};
use pyo3::prelude::*;

#[pyfunction]
fn double<'py>(py: Python<'py>, a: PyReadonlyArray2<'py, f32>) -> Bound<'py, PyArray2<f32>> {
    let v = a.as_array().mapv(|x| x * 2.0);
    v.into_pyarray(py)
}

#[pymodule]
fn verion(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(double, m)?)
}
