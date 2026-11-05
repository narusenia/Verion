//! Metal ray-tracing backend (ADR-0001). Empty on non-macOS targets.
#![cfg(target_os = "macos")]

mod accel;
mod renderer;

pub use accel::{Blas, Instance, Tlas};
pub use renderer::{Accumulation, Aovs, LightingAovs, Renderer};

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
    /// The scene does not fit in the device's unified memory (no streaming; REQ-PERF-003).
    OutOfMemory {
        needed: u64,
        available: u64,
    },
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
            Self::OutOfMemory { needed, available } => write!(
                f,
                "scene does not fit in GPU memory: needs {:.2} GiB more, {:.2} GiB left of the device's working set",
                *needed as f64 / GIB,
                *available as f64 / GIB
            ),
            Self::Resource(what) => write!(f, "failed to create Metal resource: {what}"),
            Self::Shader(e) => write!(f, "shader error: {e}"),
            Self::Scene(e) => write!(f, "scene error: {e}"),
        }
    }
}

impl std::error::Error for Error {}

const GIB: f64 = (1u64 << 30) as f64;

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

    /// Fails with [`Error::OutOfMemory`] when `bytes` more would exceed the device's recommended working set.
    pub fn check_fits(&self, bytes: usize) -> Result<(), Error> {
        let limit = self.device.recommendedMaxWorkingSetSize();
        let available = limit.saturating_sub(self.device.currentAllocatedSize() as u64);
        if bytes as u64 > available {
            return Err(Error::OutOfMemory {
                needed: bytes as u64,
                available,
            });
        }
        Ok(())
    }

    pub fn device(&self) -> &ProtocolObject<dyn MTLDevice> {
        &self.device
    }

    pub fn queue(&self) -> &ProtocolObject<dyn MTLCommandQueue> {
        &self.queue
    }
}
