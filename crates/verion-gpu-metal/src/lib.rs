//! Metal ray-tracing backend (ADR-0001). Empty on non-macOS targets.
#![cfg(target_os = "macos")]

mod accel;
mod renderer;

pub use accel::{Blas, Instance, Tlas};
pub use renderer::{Accumulation, Aovs, Renderer};

use std::fmt;

use objc2::{rc::Retained, runtime::ProtocolObject};
use objc2_metal::{MTLCommandQueue, MTLCreateSystemDefaultDevice, MTLDevice};

pub(crate) type Obj<T> = Retained<ProtocolObject<T>>;

#[derive(Debug)]
pub enum Error {
    NoDevice,
    /// The chip has no hardware ray tracing (Apple M3 or later is required).
    RaytracingUnsupported {
        device: String,
    },
    Resource(&'static str),
    /// The generated MSL failed to compile or the entry point is missing.
    Shader(String),
    /// The scene cannot be rendered (for example, it has no instances).
    Scene(String),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NoDevice => write!(f, "no Metal device found"),
            Self::RaytracingUnsupported { device } => {
                write!(
                    f,
                    "{device} does not support Metal ray tracing (Apple M3 or later is required)"
                )
            }
            Self::Resource(what) => write!(f, "failed to create Metal resource: {what}"),
            Self::Shader(e) => write!(f, "shader error: {e}"),
            Self::Scene(e) => write!(f, "scene error: {e}"),
        }
    }
}

impl std::error::Error for Error {}

#[derive(Clone)]
pub struct MetalContext {
    pub(crate) device: Obj<dyn MTLDevice>,
    pub(crate) queue: Obj<dyn MTLCommandQueue>,
}

impl MetalContext {
    pub fn new() -> Result<Self, Error> {
        let device = MTLCreateSystemDefaultDevice().ok_or(Error::NoDevice)?;
        if !device.supportsRaytracing() {
            return Err(Error::RaytracingUnsupported {
                device: device.name().to_string(),
            });
        }
        let queue = device
            .newCommandQueue()
            .ok_or(Error::Resource("command queue"))?;
        Ok(Self { device, queue })
    }

    pub fn device(&self) -> &ProtocolObject<dyn MTLDevice> {
        &self.device
    }

    pub fn queue(&self) -> &ProtocolObject<dyn MTLCommandQueue> {
        &self.queue
    }
}
