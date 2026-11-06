//! Intel Open Image Denoise (OIDN) loaded at run time (ADR-0013, REQ-ACC-001).
//!
//! The library is found through `VERION_OIDN_LIB`, the platform's default search path, or the
//! Homebrew prefix. Without it, `Denoiser::load` fails and callers keep the noisy image.

use std::{
    ffi::{CStr, CString, c_char, c_void},
    fmt,
};

use libloading::{Library, Symbol};

/// OIDN device / filter handles are opaque pointers.
type Handle = *mut c_void;

/// Where OIDN runs. A GPU device needs an OIDN package that ships its module (the release zips ship
/// CUDA and HIP; Blender's copy ships the module of its platform, Metal on macOS) and that GPU;
/// asking for one that is not there is an `Error::Oidn`.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Device {
    #[default]
    Cpu,
    Cuda,
    Hip,
    Metal,
}

impl Device {
    /// `OIDNDeviceType` of `oidn.h`.
    fn raw(self) -> i32 {
        match self {
            Device::Cpu => 1,
            Device::Cuda => 3,
            Device::Hip => 4,
            Device::Metal => 5,
        }
    }
}

const FORMAT_FLOAT3: i32 = 3;

#[derive(Debug)]
pub enum Error {
    /// The OIDN library was not found or lacks a symbol.
    Load(String),
    /// OIDN reported an error.
    Oidn(String),
    /// Image buffers do not match the size.
    Size,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Load(m) => write!(f, "OIDN not available: {m}"),
            Error::Oidn(m) => write!(f, "OIDN: {m}"),
            Error::Size => write!(f, "image buffers do not match the size"),
        }
    }
}

impl std::error::Error for Error {}

static HOST_LIBRARY: std::sync::Mutex<Option<String>> = std::sync::Mutex::new(None);

/// A copy of OIDN the host application ships (Blender bundles one with its GPU modules). It is tried
/// after `VERION_OIDN_LIB` and before the system's own copies.
pub fn set_host_library(path: &str) {
    *HOST_LIBRARY.lock().unwrap_or_else(|e| e.into_inner()) = Some(path.to_owned());
}

fn candidates() -> Vec<String> {
    let mut v: Vec<String> = std::env::var("VERION_OIDN_LIB").into_iter().collect();
    v.extend(
        HOST_LIBRARY
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone(),
    );
    if cfg!(target_os = "macos") {
        v.push("libOpenImageDenoise.2.dylib".into());
        v.push("/opt/homebrew/lib/libOpenImageDenoise.2.dylib".into());
        v.push("/usr/local/lib/libOpenImageDenoise.2.dylib".into());
    } else if cfg!(windows) {
        v.push("OpenImageDenoise.dll".into());
    } else {
        v.push("libOpenImageDenoise.so.2".into());
    }
    v
}

/// Auxiliary feature images that guide the filter. Both should be noise-free.
#[derive(Clone, Copy, Default)]
pub struct Aux<'a> {
    /// Surface albedo, 0 to 1.
    pub albedo: Option<&'a [[f32; 3]]>,
    /// Shading normal, -1 to 1 (any space).
    pub normal: Option<&'a [[f32; 3]]>,
}

/// A CPU OIDN device. Reuse it across images: creating one loads the network weights.
pub struct Denoiser {
    lib: Library,
    device: Handle,
    kind: Device,
}

// SAFETY: OIDN devices are thread-safe for use from one thread at a time; `&mut self` on
// `denoise` serialises calls.
unsafe impl Send for Denoiser {}

impl Denoiser {
    /// A CPU device.
    pub fn load() -> Result<Self, Error> {
        Self::load_on(Device::Cpu)
    }

    pub fn load_on(device: Device) -> Result<Self, Error> {
        let mut last = String::new();
        for name in candidates() {
            // SAFETY: loading OIDN runs only its own initialisers.
            match unsafe { Library::new(&name) } {
                Ok(lib) => return Self::with_library(lib, device),
                Err(e) => last = format!("{name}: {e}"),
            }
        }
        Err(Error::Load(last))
    }

    fn with_library(lib: Library, device_kind: Device) -> Result<Self, Error> {
        // SAFETY: signatures match `OpenImageDenoise/oidn.h` (2.x).
        let device = unsafe {
            let new: Symbol<unsafe extern "C" fn(i32) -> Handle> = sym(&lib, b"oidnNewDevice\0")?;
            let commit: Symbol<unsafe extern "C" fn(Handle)> = sym(&lib, b"oidnCommitDevice\0")?;
            let d = new(device_kind.raw());
            if d.is_null() {
                return Err(Error::Oidn(format!(
                    "could not create a {device_kind:?} device"
                )));
            }
            commit(d);
            d
        };
        let me = Self {
            lib,
            device,
            kind: device_kind,
        };
        me.check()?;
        Ok(me)
    }

    fn check(&self) -> Result<(), Error> {
        // SAFETY: `device` is live; OIDN owns the message string until the next call.
        unsafe {
            let get: Symbol<unsafe extern "C" fn(Handle, *mut *const c_char) -> i32> =
                sym(&self.lib, b"oidnGetDeviceError\0")?;
            let mut msg: *const c_char = std::ptr::null();
            let code = get(self.device, &mut msg);
            if code == 0 {
                return Ok(());
            }
            let text = if msg.is_null() {
                format!("error code {code}")
            } else {
                CStr::from_ptr(msg).to_string_lossy().into_owned()
            };
            Err(Error::Oidn(text))
        }
    }

    /// Denoises HDR radiance in place with the `RT` filter. Buffers are row-major, `width * height` long.
    pub fn denoise(
        &mut self,
        color: &mut [[f32; 3]],
        aux: Aux,
        width: usize,
        height: usize,
    ) -> Result<(), Error> {
        let n = width * height;
        if color.len() != n
            || aux.albedo.is_some_and(|a| a.len() != n)
            || aux.normal.is_some_and(|a| a.len() != n)
            || n == 0
        {
            return Err(Error::Size);
        }
        // OIDN needs a normal only alongside an albedo.
        let normal = aux.albedo.and(aux.normal);
        // SAFETY: every image pointer covers `n` packed float3 values and outlives the filter;
        // OIDN writes only to "output", which aliases `color` (in-place filtering is supported).
        unsafe {
            let new: Symbol<unsafe extern "C" fn(Handle, *const c_char) -> Handle> =
                sym(&self.lib, b"oidnNewFilter\0")?;
            let set_image: Symbol<
                unsafe extern "C" fn(
                    Handle,
                    *const c_char,
                    *mut c_void,
                    i32,
                    usize,
                    usize,
                    usize,
                    usize,
                    usize,
                ),
            > = sym(&self.lib, b"oidnSetSharedFilterImage\0")?;
            let set_bool: Symbol<unsafe extern "C" fn(Handle, *const c_char, bool)> =
                sym(&self.lib, b"oidnSetFilterBool\0")?;
            let commit: Symbol<unsafe extern "C" fn(Handle)> =
                sym(&self.lib, b"oidnCommitFilter\0")?;
            let exec: Symbol<unsafe extern "C" fn(Handle)> =
                sym(&self.lib, b"oidnExecuteFilter\0")?;
            let release: Symbol<unsafe extern "C" fn(Handle)> =
                sym(&self.lib, b"oidnReleaseFilter\0")?;

            let filter = new(self.device, c"RT".as_ptr());
            if filter.is_null() {
                self.check()?;
                return Err(Error::Oidn("could not create the RT filter".into()));
            }
            // The CPU device reads and writes the host images in place. A GPU device cannot see host
            // memory, so each image goes through an OIDN buffer: copied in, and the output copied back.
            let new_buffer: Symbol<unsafe extern "C" fn(Handle, usize) -> Handle> =
                sym(&self.lib, b"oidnNewBuffer\0")?;
            let write_buffer: Symbol<unsafe extern "C" fn(Handle, usize, usize, *const c_void)> =
                sym(&self.lib, b"oidnWriteBuffer\0")?;
            let read_buffer: Symbol<unsafe extern "C" fn(Handle, usize, usize, *mut c_void)> =
                sym(&self.lib, b"oidnReadBuffer\0")?;
            let release_buffer: Symbol<unsafe extern "C" fn(Handle)> =
                sym(&self.lib, b"oidnReleaseBuffer\0")?;
            let set_buffer_image: Symbol<
                unsafe extern "C" fn(
                    Handle,
                    *const c_char,
                    Handle,
                    i32,
                    usize,
                    usize,
                    usize,
                    usize,
                    usize,
                ),
            > = sym(&self.lib, b"oidnSetFilterImage\0")?;
            let bytes = n * size_of::<[f32; 3]>();
            let mut buffers: Vec<Handle> = Vec::new();
            let mut output_buffer: Handle = std::ptr::null_mut();
            let mut image = |name: &str, ptr: *const [f32; 3], is_output: bool| {
                let cname = CString::new(name).unwrap();
                if self.kind == Device::Cpu {
                    set_image(
                        filter,
                        cname.as_ptr(),
                        ptr.cast_mut().cast(),
                        FORMAT_FLOAT3,
                        width,
                        height,
                        0,
                        0,
                        0,
                    );
                    return;
                }
                let buffer = new_buffer(self.device, bytes);
                if !buffer.is_null() {
                    if is_output {
                        output_buffer = buffer;
                    } else {
                        write_buffer(buffer, 0, bytes, ptr.cast());
                    }
                    buffers.push(buffer);
                    set_buffer_image(
                        filter,
                        cname.as_ptr(),
                        buffer,
                        FORMAT_FLOAT3,
                        width,
                        height,
                        0,
                        0,
                        0,
                    );
                }
            };
            image("color", color.as_ptr(), false);
            image("output", color.as_ptr(), true);
            if let Some(a) = aux.albedo {
                image("albedo", a.as_ptr(), false);
            }
            if let Some(a) = normal {
                image("normal", a.as_ptr(), false);
            }
            set_bool(filter, c"hdr".as_ptr(), true);
            // Our albedo and normal come from one noise-free primary ray per pixel.
            set_bool(filter, c"cleanAux".as_ptr(), aux.albedo.is_some());
            commit(filter);
            let result = self.check();
            if result.is_ok() {
                exec(filter);
                if !output_buffer.is_null() {
                    // The read waits for the filter to finish.
                    read_buffer(output_buffer, 0, bytes, color.as_mut_ptr().cast());
                }
            }
            release(filter);
            for buffer in buffers {
                release_buffer(buffer);
            }
            result.and_then(|_| self.check())
        }
    }
}

impl Drop for Denoiser {
    fn drop(&mut self) {
        // SAFETY: the device is released once, before the library is unloaded.
        unsafe {
            if let Ok(release) =
                sym::<unsafe extern "C" fn(Handle)>(&self.lib, b"oidnReleaseDevice\0")
            {
                release(self.device);
            }
        }
    }
}

/// # Safety
/// `T` must match the C signature of `name`.
unsafe fn sym<'l, T>(lib: &'l Library, name: &[u8]) -> Result<Symbol<'l, T>, Error> {
    // SAFETY: forwarded to the caller.
    unsafe { lib.get(name) }.map_err(|e| Error::Load(e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_mismatched_sizes_before_calling_oidn() {
        // Runs only where OIDN is installed; CI has none.
        let Ok(mut d) = Denoiser::load() else { return };
        let mut c = vec![[0.0; 3]; 4];
        assert!(matches!(
            d.denoise(&mut c, Aux::default(), 3, 1),
            Err(Error::Size)
        ));
    }

    #[test]
    fn flattens_noise_on_a_flat_image() {
        let Ok(mut d) = Denoiser::load() else { return };
        let (w, h) = (64, 64);
        let mut state = 1u32;
        let mut c: Vec<[f32; 3]> = (0..w * h)
            .map(|_| {
                state = state.wrapping_mul(1664525).wrapping_add(1013904223);
                let v = (state >> 8) as f32 / 16777216.0;
                [v; 3]
            })
            .collect();
        let albedo = vec![[0.5f32; 3]; w * h];
        let normal = vec![[0.0f32, 0.0, 1.0]; w * h];
        let var = |c: &[[f32; 3]]| {
            let m = c.iter().map(|p| p[0]).sum::<f32>() / c.len() as f32;
            c.iter().map(|p| (p[0] - m).powi(2)).sum::<f32>() / c.len() as f32
        };
        let before = var(&c);
        d.denoise(
            &mut c,
            Aux {
                albedo: Some(&albedo),
                normal: Some(&normal),
            },
            w,
            h,
        )
        .unwrap();
        assert!(var(&c) < before * 0.1, "{} -> {}", before, var(&c));
    }
}
