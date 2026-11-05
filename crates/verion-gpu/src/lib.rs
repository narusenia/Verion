//! The contract every GPU backend implements (REQ-GPU-003), and the plain data types that cross
//! it. No GPU API here: the backends (`verion-gpu-metal`, later `verion-gpu-vulkan`) depend on this
//! crate, and the CLI and the viewer pick one per platform and use it only through these traits.

use verion_scene::{Camera, LIGHT_SLOTS, Scene};

/// A ray-tracing path tracer on one GPU API.
pub trait RayTracingBackend: Sized {
    /// The device and queue, shared by renderers made from it.
    type Context;
    type Accumulation: Accumulation;
    type Error: std::error::Error + 'static;

    /// Opens the default device; fails when it has no hardware ray tracing.
    fn context() -> Result<Self::Context, Self::Error>;
    fn memory(ctx: &Self::Context) -> MemoryUsage;
    /// Uploads the scene and builds its acceleration structures.
    fn new(ctx: &Self::Context, scene: &Scene) -> Result<Self, Self::Error>;

    /// Replaces the camera without rebuilding the acceleration structures. Start a new
    /// accumulation afterwards; samples gathered from the old camera no longer match.
    fn set_camera(&mut self, cam: &Camera);
    /// Multiple-scattering energy compensation for rough GGX lobes (on by default).
    fn set_multiscatter(&mut self, on: bool);
    fn set_integrator(&mut self, integrator: Integrator);
    fn integrator(&self) -> Integrator;
    /// Wavefront only: time the extend and shade stages apart (`Accumulation::stage_seconds`).
    fn set_stage_timing(&mut self, on: bool);
    /// Per-pixel adaptive sampling for accumulations started afterwards (REQ-ACC-007).
    fn set_adaptive(&mut self, adaptive: Option<Adaptive>);

    /// An empty running sum; `lighting` adds the per-pixel buffers of the lighting split.
    fn new_accumulation(
        &self,
        width: u32,
        height: u32,
        lighting: bool,
    ) -> Result<Self::Accumulation, Self::Error>;
    /// Traces `samples` more paths per pixel into `acc` (at most, under adaptive sampling) and
    /// waits for the GPU.
    fn accumulate(&self, acc: &mut Self::Accumulation, samples: u32) -> Result<(), Self::Error>;

    /// World-space normal of the first hit per pixel, row-major from the top-left; misses are zero.
    fn render_normals(&self, width: u32, height: u32) -> Result<Vec<[f32; 3]>, Self::Error>;
    /// Albedo, depth and ids of the first hit through each pixel centre.
    fn render_aovs(&self, width: u32, height: u32) -> Result<Aovs, Self::Error>;
}

/// Running radiance sums of one image, read back as means.
pub trait Accumulation {
    /// Samples per pixel so far (the most any pixel took, under adaptive sampling).
    fn samples(&self) -> u32;
    /// GPU execution time of all `accumulate` calls so far.
    fn gpu_seconds(&self) -> f64;
    /// GPU seconds of the wavefront's extend and shade stages, when stage timing was on.
    fn stage_seconds(&self) -> Option<[f64; 2]>;
    /// GPU memory of the wavefront queues and path state (0 until a wavefront `accumulate`).
    fn wavefront_bytes(&self) -> usize;
    /// Mean radiance per pixel, row-major from the top-left. All zero before the first sample.
    fn mean(&self) -> Vec<[f32; 3]>;
    /// Mean lighting split, or `None` unless made with `lighting`.
    fn lighting(&self) -> Option<LightingAovs>;
    /// Samples each pixel took, row-major from the top-left; `None` unless adaptive sampling ran.
    fn sample_counts(&self) -> Option<Vec<u32>>;
    /// Pixels the next sample would trace: all of them unless adaptive sampling stopped some.
    fn active_pixels(&self) -> usize;
}

/// Which form of the path tracer `RayTracingBackend::accumulate` runs. Both give the same image.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Integrator {
    /// One thread runs a whole path.
    #[default]
    Megakernel,
    /// One kernel per stage and bounce, with path queues in between (REQ-GPU-005).
    Wavefront,
}

/// Per-pixel adaptive sampling (REQ-ACC-007): a pixel stops taking samples once it has `min_spp`
/// and the standard error of its luminance mean is at most `threshold` times the mean (with a
/// floor of 0.05 for dark pixels). Stopping on the pixel's own estimate biases it slightly, so
/// the result is non-physical. Works with both integrators.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Adaptive {
    pub threshold: f32,
    pub min_spp: u32,
}

impl Default for Adaptive {
    fn default() -> Self {
        Self {
            threshold: 0.02,
            min_spp: 16,
        }
    }
}

impl Adaptive {
    /// Whether a pixel with `n` samples, luminance sum `s` and square sum `s2` takes more samples.
    /// Mirrors `pixelActive` in `shaders/include/pt_core.slang`.
    pub fn active(&self, n: f32, s: f32, s2: f32) -> bool {
        if n < self.min_spp as f32 {
            return true;
        }
        let mean = s / n;
        let var = (s2 / n - mean * mean).max(0.0) * n / (n - 1.0);
        (var / n).sqrt() > self.threshold * mean.max(0.05)
    }
}

/// Primary-ray AOVs, row-major from the top-left. Misses are zero in every field.
pub struct Aovs {
    /// Base color factor times the base color texture at the hit.
    pub albedo: Vec<[f32; 3]>,
    /// Distance along the camera's forward axis (not along the ray).
    pub depth: Vec<f32>,
    /// Instance index plus one.
    pub object_id: Vec<u32>,
    /// Material index plus one.
    pub material_id: Vec<u32>,
}

/// First-hit lighting split (REQ-STY-006), mean per pixel, row-major from the top-left. Radiance
/// parts sum to the beauty image; indirect light is filed under the lobe taken at the first bounce.
/// Rays that miss the scene file the sky as `emission`.
#[derive(Clone)]
pub struct LightingAovs {
    pub direct_diffuse: Vec<[f32; 3]>,
    pub indirect_diffuse: Vec<[f32; 3]>,
    pub specular: Vec<[f32; 3]>,
    pub transmission: Vec<[f32; 3]>,
    pub emission: Vec<[f32; 3]>,
    /// Share of the direct light that is not shadowed, 0 to 1 (1 where no light reaches the point).
    pub visibility: Vec<f32>,
    /// Per light slot: the light's diffuse contribution without cos and without shadowing (`u`).
    /// The physical direct diffuse is `u * light_response`, summed over slots (see `LIGHT_SLOTS`).
    pub light_u: Vec<[[f32; 3]; LIGHT_SLOTS]>,
    /// Per light slot: cos(N, L) times visibility, averaged weighted by the light's contribution.
    /// 0 where the slot's light never reaches the pixel.
    pub light_response: Vec<[f32; LIGHT_SLOTS]>,
    /// Per light slot: the light's specular contribution without cos and without shadowing (`s`),
    /// the specular counterpart of `light_u`.
    pub light_s: Vec<[[f32; 3]; LIGHT_SLOTS]>,
    /// Per light slot: unit vector from the point toward the light, averaged weighted by the light's
    /// diffuse plus specular contribution. Zero where the slot's light never reaches the pixel; for a
    /// slot that pools several lights it is the mean direction, so it shortens (and is only
    /// approximate) when they disagree.
    pub light_dir: Vec<[[f32; 3]; LIGHT_SLOTS]>,
    /// Per light slot: share of the slot's contribution that is not shadowed, 0 to 1 (0 where the
    /// slot's light never reaches the pixel). The visibility that goes with `light_s`.
    pub light_lit: Vec<[f32; LIGHT_SLOTS]>,
}

impl LightingAovs {
    /// Calls `f` on every radiance plane (the five parts, then `light_u` and `light_s` per used
    /// slot), writing back what it leaves, e.g. a denoiser. The ratios (response, direction,
    /// visibility) carry no radiance scale and are left alone.
    pub fn for_each_radiance<E>(
        &mut self,
        mut f: impl FnMut(&mut [[f32; 3]]) -> Result<(), E>,
    ) -> Result<(), E> {
        for part in [
            &mut self.direct_diffuse,
            &mut self.indirect_diffuse,
            &mut self.specular,
            &mut self.transmission,
            &mut self.emission,
        ] {
            f(part)?;
        }
        for slots in [&mut self.light_u, &mut self.light_s] {
            for k in 0..LIGHT_SLOTS {
                let mut plane: Vec<[f32; 3]> = slots.iter().map(|s| s[k]).collect();
                if plane.iter().all(|p| *p == [0.0; 3]) {
                    continue; // an unused slot
                }
                f(&mut plane)?;
                slots.iter_mut().zip(plane).for_each(|(s, p)| s[k] = p);
            }
        }
        Ok(())
    }
}

/// GPU memory against the budget (REQ-PERF-006, step 2: measured, behavior unchanged).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MemoryUsage {
    /// The device's recommended working set; allocations past it fail with an out-of-memory error.
    pub budget: u64,
    /// Bytes the device has allocated now, all clients of the process included.
    pub allocated: u64,
    /// Bytes uploaded from the host through this context so far.
    pub uploaded: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adaptive_stops_after_the_minimum_once_the_error_is_small() {
        let a = Adaptive {
            threshold: 0.1,
            min_spp: 4,
        };
        // Below the minimum a pixel always continues, even with no variance.
        assert!(a.active(3.0, 3.0, 3.0));
        // Constant luminance 1: no error, so it stops.
        assert!(!a.active(4.0, 4.0, 4.0));
        // Luminance 0 or 2 alternating: mean 1, standard error sqrt(4/3 / 4) = 0.58 > 0.1.
        assert!(a.active(4.0, 4.0, 8.0));
        // Black pixels stop against the 0.05 floor instead of never.
        assert!(!a.active(16.0, 0.0, 0.0));
    }
}
