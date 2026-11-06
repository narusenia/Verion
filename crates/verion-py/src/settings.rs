//! The settings dict of `Engine.start`, checked key by key so a typo is an error, not a silent default.

use pyo3::{prelude::*, types::PyDict};
use verion_gpu::{Adaptive, Integrator, Restir};
use verion_render::{Denoise, DenoiseDevice, DenoiseStage, Mode, Settings};
use verion_stylization::ColorGrade;

use crate::scene::value_err;

pub struct JobSettings {
    pub render: Settings,
    /// Samples per pixel that count as a clean preview (for the First Clean Preview time).
    pub clean_spp: u32,
}

const KEYS: &[&str] = &[
    "mode",
    "width",
    "height",
    "spp",
    "integrator",
    "multiscatter",
    "adaptive",
    "restir",
    "lighting_aovs",
    "denoise",
    "grade",
    "clean_spp",
];

fn get<'py, T>(d: &Bound<'py, PyDict>, key: &str) -> PyResult<Option<T>>
where
    T: for<'a> FromPyObject<'a, 'py>,
    for<'a> <T as FromPyObject<'a, 'py>>::Error: Into<PyErr>,
{
    d.get_item(key)?
        .filter(|v| !v.is_none())
        .map(|v| {
            v.extract::<T>()
                .map_err(|e| value_err(format!("{key}: {}", e.into())))
        })
        .transpose()
}

fn get_dict<'py>(d: &Bound<'py, PyDict>, key: &str) -> PyResult<Option<Bound<'py, PyDict>>> {
    d.get_item(key)?
        .filter(|v| !v.is_none())
        .map(|v| {
            v.cast_into::<PyDict>()
                .map_err(|_| value_err(format!("{key} must be a dict")))
        })
        .transpose()
}

fn choice<T: Copy>(name: &str, v: &str, options: &[(&str, T)]) -> PyResult<T> {
    options
        .iter()
        .find(|(n, _)| *n == v)
        .map(|(_, t)| *t)
        .ok_or_else(|| {
            let names: Vec<_> = options.iter().map(|(n, _)| *n).collect();
            value_err(format!("{name} is one of {}", names.join(", ")))
        })
}

pub fn parse(d: &Bound<'_, PyDict>) -> PyResult<JobSettings> {
    for (k, _) in d.iter() {
        let k: String = k.extract()?;
        if !KEYS.contains(&k.as_str()) {
            return Err(value_err(format!("unknown setting {k}")));
        }
    }
    let mode = choice(
        "mode",
        &get::<String>(d, "mode")?.unwrap_or_else(|| "reference".into()),
        &[
            ("reference", Mode::Reference),
            ("interactive", Mode::Interactive),
            ("stylized", Mode::Stylized),
        ],
    )?;
    let mut s = Settings::new(
        mode,
        get(d, "width")?.ok_or_else(|| value_err("width is required"))?,
        get(d, "height")?.ok_or_else(|| value_err("height is required"))?,
        get(d, "spp")?.unwrap_or(64),
    );
    if let Some(v) = get::<String>(d, "integrator")? {
        s.integrator = choice(
            "integrator",
            &v,
            &[
                ("megakernel", Integrator::Megakernel),
                ("wavefront", Integrator::Wavefront),
            ],
        )?;
    }
    s.multiscatter = get(d, "multiscatter")?.unwrap_or(true);
    s.lighting_aovs = get(d, "lighting_aovs")?.unwrap_or(false);
    if let Some(a) = get_dict(d, "adaptive")? {
        let def = Adaptive::default();
        s.adaptive = Some(Adaptive {
            threshold: get(&a, "threshold")?.unwrap_or(def.threshold),
            min_spp: get(&a, "min_spp")?.unwrap_or(def.min_spp),
        });
    }
    if let Some(r) = get_dict(d, "restir")? {
        let def = Restir::default();
        s.restir = Some(Restir {
            di: get(&r, "di")?.unwrap_or(def.di),
            gi: get(&r, "gi")?.unwrap_or(def.gi),
            candidates: get(&r, "candidates")?.unwrap_or(def.candidates),
            history: get(&r, "history")?.unwrap_or(def.history),
        });
    }
    if let Some(n) = get_dict(d, "denoise")? {
        s.denoise = Some(Denoise {
            device: choice(
                "denoise device",
                &get::<String>(&n, "device")?.unwrap_or_else(|| "cpu".into()),
                &[
                    ("cpu", DenoiseDevice::Cpu),
                    ("cuda", DenoiseDevice::Cuda),
                    ("hip", DenoiseDevice::Hip),
                    ("metal", DenoiseDevice::Metal),
                ],
            )?,
            stage: choice(
                "denoise stage",
                &get::<String>(&n, "stage")?.unwrap_or_else(|| "input".into()),
                &[
                    ("input", DenoiseStage::Input),
                    ("output", DenoiseStage::Output),
                ],
            )?,
        });
    }
    if let Some(g) = get_dict(d, "grade")? {
        let def = ColorGrade::default();
        s.grade = ColorGrade {
            exposure: get(&g, "exposure")?.unwrap_or(def.exposure),
            saturation: get(&g, "saturation")?.unwrap_or(def.saturation),
            white_balance: get(&g, "white_balance")?.unwrap_or(def.white_balance),
        };
    }
    s.validate().map_err(value_err)?;
    Ok(JobSettings {
        render: s,
        clean_spp: get(d, "clean_spp")?.unwrap_or(16),
    })
}
