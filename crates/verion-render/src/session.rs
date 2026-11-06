use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, AtomicU32, Ordering},
};

use verion_denoise::{Denoiser, Device};
use verion_gpu::{
    Accumulation as _, Adaptive, Aovs, Integrator, LightingAovs, RayTracingBackend, Restir,
    UpdateReport,
};
use verion_scene::Scene;
use verion_stylization::ColorGrade;

use crate::post::{DenoiseStage, Mode, PostInput, PostTimes, finish};

/// Samples per GPU dispatch of `Session::render`; progress and cancellation are checked between them.
const CHUNK_SPP: u32 = 8;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Denoise {
    pub device: Device,
    pub stage: DenoiseStage,
}

/// What one render needs besides the scene.
#[derive(Clone, Debug)]
pub struct Settings {
    pub mode: Mode,
    pub width: u32,
    pub height: u32,
    /// Samples per pixel to reach (the most a pixel takes, under adaptive sampling).
    pub spp: u32,
    pub integrator: Integrator,
    pub multiscatter: bool,
    pub adaptive: Option<Adaptive>,
    /// ReSTIR. `None` is the plain path tracer, except in `Mode::Interactive`, which defaults to DI+GI.
    /// Rejected in Reference mode (its reuse is biased).
    pub restir: Option<Restir>,
    /// Also read back the first-hit lighting split (always on in Stylized mode).
    pub lighting_aovs: bool,
    pub denoise: Option<Denoise>,
    /// Applied last; non-physical, so only Stylized mode may use it.
    pub grade: ColorGrade,
}

impl Settings {
    pub fn new(mode: Mode, width: u32, height: u32, spp: u32) -> Self {
        Self {
            mode,
            width,
            height,
            spp,
            integrator: Integrator::Megakernel,
            multiscatter: true,
            adaptive: None,
            restir: None,
            lighting_aovs: false,
            denoise: None,
            grade: ColorGrade::default(),
        }
    }

    fn restir(&self) -> Option<Restir> {
        match (self.mode, self.restir) {
            (Mode::Interactive, None) => Some(Restir {
                gi: true,
                ..Restir::default()
            }),
            (_, restir) => restir,
        }
    }

    pub fn validate(&self) -> Result<(), String> {
        if self.width == 0 || self.height == 0 || self.spp == 0 {
            return Err("width, height and spp must be at least 1".into());
        }
        if self.mode.physical() && self.restir.is_some() {
            return Err("ReSTIR is not allowed in reference mode (its reuse is biased)".into());
        }
        if let Some(r) = self.restir
            && (r.candidates == 0 || r.history == 0)
        {
            return Err("ReSTIR candidates and history must be at least 1".into());
        }
        if self
            .adaptive
            .is_some_and(|a| !(a.threshold.is_finite() && a.threshold >= 0.0))
        {
            return Err("the adaptive threshold must be 0 or more".into());
        }
        self.grade.validate()?;
        if !self.grade.is_identity() && self.mode != Mode::Stylized {
            return Err("the color grade is non-physical; use stylized mode".into());
        }
        Ok(())
    }

    /// Whether the output is a physical image (nothing biased or stylized went into it).
    pub fn physical(&self) -> bool {
        self.mode.physical()
            && self.restir.is_none()
            && self.adaptive.is_none()
            && self.denoise.is_none()
    }
}

/// Shared between the thread that renders and the one that watches (progress bar, Cancel button).
#[derive(Default)]
pub struct Control {
    pub cancel: AtomicBool,
    /// Samples per pixel taken so far.
    pub samples: AtomicU32,
}

/// One finished or partial image with the AOVs that came with it. Pixels are row-major from the
/// top-left, in the scene's working space.
pub struct Frame {
    pub width: u32,
    pub height: u32,
    /// Samples per pixel taken (the most any pixel took, under adaptive sampling).
    pub samples: u32,
    /// Post-processed beauty (denoised and stylized as the settings ask).
    pub beauty: Vec<[f32; 3]>,
    /// The AOVs below are empty when the frame was read without them.
    pub normal: Vec<[f32; 3]>,
    pub albedo: Vec<[f32; 3]>,
    pub depth: Vec<f32>,
    pub object_id: Vec<u32>,
    pub material_id: Vec<u32>,
    pub sample_count: Option<Vec<u32>>,
    pub lighting: Option<LightingAovs>,
    pub physical: bool,
    pub times: PostTimes,
}

/// An accumulation in progress with the settings it was started with.
pub struct Run<B: RayTracingBackend> {
    pub settings: Settings,
    acc: B::Accumulation,
    /// Normals and primary-hit AOVs, read once: they follow the scene and the camera, not the samples.
    aovs: Option<(Vec<[f32; 3]>, Aovs)>,
}

impl<B: RayTracingBackend> Run<B> {
    pub fn samples(&self) -> u32 {
        self.acc.samples()
    }

    /// Whether the next sample would trace any pixel (false once adaptive sampling converged).
    pub fn active(&self) -> bool {
        self.acc.active_pixels() > 0
    }
}

/// A scene on a GPU. Not `Send` (GPU objects stay on the thread that made them), so a front end
/// that renders in the background keeps the whole session on one thread.
pub struct Session<B: RayTracingBackend> {
    ctx: B::Context,
    renderer: B,
    scene: Arc<Mutex<Scene>>,
    denoiser: Option<(Device, Denoiser)>,
    applied: verion_scene::Revisions,
}

fn lock(scene: &Mutex<Scene>) -> std::sync::MutexGuard<'_, Scene> {
    // A panic while editing leaves a scene that is still consistent (each edit is one push or store).
    scene.lock().unwrap_or_else(|p| p.into_inner())
}

impl<B: RayTracingBackend> Session<B> {
    pub fn new(scene: Arc<Mutex<Scene>>) -> Result<Self, String> {
        let ctx = B::context().map_err(|e| format!("GPU ray tracing is required: {e}"))?;
        let (renderer, applied) = {
            let mut s = lock(&scene);
            let r = B::new(&ctx, &s).map_err(|e| format!("renderer: {e:?}"))?;
            s.take_changes();
            (r, s.revisions())
        };
        Ok(Self {
            ctx,
            renderer,
            scene,
            denoiser: None,
            applied,
        })
    }

    pub fn scene(&self) -> &Arc<Mutex<Scene>> {
        &self.scene
    }

    pub fn memory(&self) -> verion_gpu::MemoryUsage {
        B::memory(&self.ctx)
    }

    /// Whether the scene was edited since the last `update`.
    pub fn stale(&self) -> bool {
        lock(&self.scene).revisions() != self.applied
    }

    /// Sends the scene edits made since the last call to the renderer. Start a new run afterwards.
    pub fn update(&mut self) -> Result<UpdateReport, String> {
        let mut scene = lock(&self.scene);
        self.applied = scene.revisions();
        let changes = scene.take_changes();
        if changes.is_empty() {
            return Ok(UpdateReport::default());
        }
        self.renderer
            .update(&scene, &changes)
            .map_err(|e| format!("update: {e:?}"))
    }

    pub fn begin(&mut self, settings: &Settings) -> Result<Run<B>, String> {
        settings.validate()?;
        self.renderer.set_multiscatter(settings.multiscatter);
        self.renderer.set_integrator(settings.integrator);
        self.renderer.set_adaptive(settings.adaptive);
        self.renderer.set_restir(settings.restir());
        if let Some(d) = settings.denoise
            && self
                .denoiser
                .as_ref()
                .is_none_or(|(dev, _)| *dev != d.device)
        {
            let loaded = Denoiser::load_on(d.device).map_err(|e| e.to_string())?;
            self.denoiser = Some((d.device, loaded));
        }
        let lighting = settings.lighting_aovs || settings.mode == Mode::Stylized;
        let acc = self
            .renderer
            .new_accumulation(settings.width, settings.height, lighting)
            .map_err(|e| format!("render: {e:?}"))?;
        Ok(Run {
            settings: settings.clone(),
            acc,
            aovs: None,
        })
    }

    /// Traces `n` more samples per pixel.
    pub fn step(&mut self, run: &mut Run<B>, n: u32) -> Result<(), String> {
        self.renderer
            .accumulate(&mut run.acc, n)
            .map_err(|e| format!("render: {e:?}"))
    }

    /// Reads the image so far. `aovs` also reads the primary-hit AOVs (Stylized mode and denoising
    /// need them anyway); `post` runs the denoiser and the Stylization Pass.
    pub fn frame(&mut self, run: &mut Run<B>, aovs: bool, post: bool) -> Result<Frame, String> {
        let s = run.settings.clone();
        let (w, h) = (s.width, s.height);
        let stylize = post && s.mode == Mode::Stylized;
        let denoise = post.then_some(s.denoise).flatten();
        if (aovs || stylize || denoise.is_some()) && run.aovs.is_none() {
            let normals = self
                .renderer
                .render_normals(w, h)
                .map_err(|e| format!("normals: {e:?}"))?;
            let a = self
                .renderer
                .render_aovs(w, h)
                .map_err(|e| format!("aovs: {e:?}"))?;
            run.aovs = Some((normals, a));
        }
        let mut beauty = run.acc.mean();
        let mut lighting = run.acc.lighting();
        let mut times = PostTimes::default();
        if post && let Some((normals, a)) = &run.aovs {
            let scene = lock(&self.scene);
            let denoise = match (denoise, self.denoiser.as_mut()) {
                (Some(d), Some((_, den))) => Some((den, d.stage)),
                _ => None,
            };
            times = finish(
                PostInput {
                    scene: &scene,
                    mode: s.mode,
                    width: w as usize,
                    height: h as usize,
                    normals,
                    aov: a,
                    grade: &s.grade,
                    denoise,
                },
                &mut beauty,
                lighting.as_mut(),
            )?;
        }
        let (normal, albedo, depth, object_id, material_id) = match run.aovs.as_ref() {
            Some((n, a)) => (
                n.clone(),
                a.albedo.clone(),
                a.depth.clone(),
                a.object_id.clone(),
                a.material_id.clone(),
            ),
            None => Default::default(),
        };
        Ok(Frame {
            width: w,
            height: h,
            samples: run.acc.samples(),
            beauty,
            normal,
            albedo,
            depth,
            object_id,
            material_id,
            sample_count: run.acc.sample_counts(),
            lighting,
            physical: s.physical(),
            times,
        })
    }

    /// Renders to `settings.spp`, checking `ctl.cancel` between dispatches and publishing the
    /// sample count in `ctl.samples`. A cancelled render returns the frame it had reached.
    pub fn render(&mut self, settings: &Settings, ctl: &Control) -> Result<Frame, String> {
        let mut run = self.begin(settings)?;
        ctl.samples.store(0, Ordering::Relaxed);
        while run.samples() < settings.spp && !ctl.cancel.load(Ordering::Relaxed) {
            let n = CHUNK_SPP.min(settings.spp - run.samples());
            self.step(&mut run, n)?;
            ctl.samples.store(run.samples(), Ordering::Relaxed);
            if !run.active() {
                break; // adaptive sampling: every pixel converged
            }
        }
        self.frame(&mut run, true, true)
    }
}
