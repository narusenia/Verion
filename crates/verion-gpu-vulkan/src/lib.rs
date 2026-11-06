//! Vulkan ray-tracing backend (ADR-0001, M4): compute shaders with ray query over the same Slang
//! sources as the Metal backend. Empty on macOS, where MoltenVK has no ray tracing.
#![cfg(not(target_os = "macos"))]

mod accel;
mod buffer;
mod context;
mod pipeline;
mod reflect;
mod renderer;
mod shaders;

pub use context::{DeviceInfo, SerSupport, VulkanContext};
pub use renderer::{Accumulation, Renderer};
pub use shaders::SHADERS;
pub use verion_gpu::{Adaptive, Aovs, Integrator, LightingAovs, MemoryUsage};

use std::fmt;

use ash::vk;

#[derive(Clone, Debug)]
pub enum Error {
    /// The Vulkan loader is missing or has no usable ICD.
    NoVulkan(String),
    NoDevice,
    /// No device has every required extension and feature.
    Unsupported {
        device: String,
        missing: Vec<&'static str>,
    },
    Vulkan(vk::Result),
    Resource(&'static str),
    /// The scene does not fit in the device's memory (no streaming; REQ-PERF-003).
    OutOfMemory {
        needed: u64,
        available: u64,
    },
    /// A shader failed to load or its entry point is missing.
    Shader(String),
    /// The scene cannot be rendered (for example, it has no instances).
    Scene(String),
}

const GIB: f64 = (1u64 << 30) as f64;

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NoVulkan(e) => write!(f, "Vulkan is not available: {e}"),
            Self::NoDevice => write!(f, "no Vulkan device found"),
            Self::Unsupported { device, missing } => write!(
                f,
                "{device} lacks Vulkan ray tracing support: {}",
                missing.join(", ")
            ),
            Self::Vulkan(r) => write!(f, "Vulkan error: {r}"),
            Self::Resource(what) => write!(f, "failed to create Vulkan resource: {what}"),
            Self::OutOfMemory { needed, available } => write!(
                f,
                "scene does not fit in GPU memory: needs {:.2} GiB more, {:.2} GiB left of the device's budget",
                *needed as f64 / GIB,
                *available as f64 / GIB
            ),
            Self::Shader(e) => write!(f, "shader error: {e}"),
            Self::Scene(e) => write!(f, "scene error: {e}"),
        }
    }
}

impl std::error::Error for Error {}

impl From<vk::Result> for Error {
    fn from(r: vk::Result) -> Self {
        Self::Vulkan(r)
    }
}
