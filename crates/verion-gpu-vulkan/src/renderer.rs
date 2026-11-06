//! Uploads a Scene IR snapshot and renders with the Slang-generated SPIR-V kernels (compute
//! shaders with ray query). One `accumulate` is one submission: every dispatch of it is recorded
//! up front, each reading its own slice of the parameter buffer through a dynamic offset.

use std::{cell::OnceCell, time::Instant};

use ash::vk;
use gpu_allocator::MemoryLocation;
use verion_gpu::{
    Adaptive, Aovs, Integrator, LightingAovs, MemoryUsage, RESTIR_FLOATS_PER_PIXEL,
    RayTracingBackend, Restir, UpdateReport,
    pack::{self, MAX_DEPTH, PARAM_WORDS, SceneInfo, View},
    readback,
    wavefront::Stage,
};
use verion_scene::{Camera, Changes, Scene};

use crate::shaders::spirv;
use crate::{
    Error, VulkanContext,
    accel::{self, Accel},
    buffer::{Buffer, Upload, bytes_of},
    pipeline::{Descriptors, PARAMS_BINDING, Pipeline, Res},
};

mod wavefront;

/// Most samples one megakernel thread takes in a row; the same as Metal's, see there.
const SAMPLES_PER_DISPATCH: u32 = 8;
const STORAGE: vk::BufferUsageFlags = vk::BufferUsageFlags::STORAGE_BUFFER;
/// Storage plus the copy-out of readbacks: the accumulation sums.
const RESULT: vk::BufferUsageFlags = vk::BufferUsageFlags::from_raw(
    vk::BufferUsageFlags::STORAGE_BUFFER.as_raw() | vk::BufferUsageFlags::TRANSFER_SRC.as_raw(),
);

fn groups(n: u32, size: u32) -> u32 {
    n.div_ceil(size)
}

/// One device-local buffer holding `data`.
fn put<T: Copy>(
    ctx: &VulkanContext,
    data: &[T],
    usage: vk::BufferUsageFlags,
    name: &'static str,
) -> Result<Buffer, Error> {
    let mut up = Upload::new(ctx);
    let buffer = up.buffer(data, usage, name)?;
    up.flush()?;
    Ok(buffer)
}

fn align_up(v: u64, a: u64) -> u64 {
    v.div_ceil(a) * a
}

/// A scene snapshot ready to trace. Later scene edits are not reflected.
pub struct Renderer {
    ctx: VulkanContext,
    tlas: Accel,
    blases: Vec<Accel>,
    meshes: Vec<pack::MeshRange>,
    /// Image per texture slot and the environment map's identity, to skip unchanged tables.
    texture_images: Vec<usize>,
    env_key: Option<(usize, u32)>,
    positions: Buffer,
    indices: Buffer,
    instances: Buffer,
    materials: Buffer,
    lights: Buffer,
    emitters: Buffer,
    emit_cdf: Buffer,
    env_pixels: Buffer,
    env_marginal: Buffer,
    env_conditional: Buffer,
    uvs: Buffer,
    vnormals: Buffer,
    texels: Buffer,
    tex_info: Buffer,
    /// Bound in place of the lighting and statistics buffers an accumulation does not have.
    dummy: Buffer,
    info: SceneInfo,
    view: View,
    multiscatter: bool,
    normals: Pipeline,
    aov: Pipeline,
    /// Indexed by whether ReSTIR is compiled in (`restirCompiled`), so a renderer without it
    /// runs a kernel without its registers. Compiled on first use.
    pathtrace: [OnceCell<Result<Pipeline, Error>>; 2],
    integrator: Integrator,
    /// Wavefront only: time extend and shade separately.
    stage_timing: bool,
    adaptive: Option<Adaptive>,
    restir: Option<Restir>,
    /// Compiled on first use, so megakernel-only users skip the compile; indexed like `pathtrace`.
    wavefront: [OnceCell<Result<wavefront::Pipelines, Error>>; 2],
}

impl Renderer {
    pub fn new(ctx: &VulkanContext, scene: &Scene) -> Result<Self, Error> {
        let packed = pack::pack(scene).map_err(Error::Scene)?;
        let mut up = Upload::new(ctx);
        let geometry =
            STORAGE | vk::BufferUsageFlags::ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR;
        let positions = up.buffer(&packed.positions, geometry, "positions")?;
        let indices = up.buffer(&packed.indices, geometry, "indices")?;
        let instances = up.buffer(&packed.instances, STORAGE, "instances")?;
        let materials = up.buffer(&packed.materials, STORAGE, "materials")?;
        let lights = up.buffer(&packed.lights, STORAGE, "lights")?;
        let emitters = up.buffer(&packed.emitters, STORAGE, "emitters")?;
        let emit_cdf = up.buffer(&packed.emit_cdf, STORAGE, "emitter cdf")?;
        let env_pixels = up.buffer(&packed.env.pixels, STORAGE, "env pixels")?;
        let env_marginal = up.buffer(&packed.env.marginal, STORAGE, "env marginal")?;
        let env_conditional = up.buffer(&packed.env.conditional, STORAGE, "env conditional")?;
        let uvs = up.buffer(&packed.uvs, STORAGE, "uvs")?;
        let vnormals = up.buffer(&packed.vnormals, STORAGE, "vertex normals")?;
        let texels = up.buffer(&packed.texels, STORAGE, "texels")?;
        let tex_info = up.buffer(&packed.tex_info, STORAGE, "texture info")?;
        up.flush()?;
        let blases = accel::build_blases(ctx, &positions, &indices, &packed.meshes)?;
        let tlas = accel::build_tlas(ctx, &blases, &packed.tlas)?;
        let pipe = |name, dynamic| Pipeline::new(ctx, name, spirv(name), dynamic, false);
        Ok(Self {
            ctx: ctx.clone(),
            tlas,
            blases,
            meshes: packed.meshes.clone(),
            texture_images: packed.texture_images.clone(),
            env_key: pack::env_key(scene),
            positions,
            indices,
            instances,
            materials,
            lights,
            emitters,
            emit_cdf,
            env_pixels,
            env_marginal,
            env_conditional,
            uvs,
            vnormals,
            texels,
            tex_info,
            dummy: ctx.zeroed(16, STORAGE, "dummy")?,
            info: packed.info,
            view: packed.view,
            multiscatter: true,
            normals: pipe("normals", None)?,
            aov: pipe("aov", None)?,
            pathtrace: [OnceCell::new(), OnceCell::new()],
            integrator: Integrator::default(),
            stage_timing: false,
            adaptive: None,
            restir: None,
            wavefront: [OnceCell::new(), OnceCell::new()],
        })
    }

    pub fn adaptive(&self) -> Option<Adaptive> {
        self.adaptive
    }

    /// Bindings 0..19 of the path tracer's kernels (`shaders/include/pt_core.slang`).
    fn path_resources<'a>(
        &'a self,
        acc: &'a Accumulation,
        params: &'a Buffer,
    ) -> Vec<(u32, Res<'a>)> {
        vec![
            (0, Res::Accel(self.tlas.raw)),
            (1, Res::Buffer(&self.positions)),
            (2, Res::Buffer(&self.indices)),
            (3, Res::Buffer(&self.instances)),
            (4, Res::Buffer(&self.materials)),
            (5, Res::Buffer(&self.lights)),
            (PARAMS_BINDING, Res::Slice(params, (PARAM_WORDS * 4) as u64)),
            (7, Res::Buffer(&acc.buffer)),
            (8, Res::Buffer(&self.emitters)),
            (9, Res::Buffer(&self.emit_cdf)),
            (10, Res::Buffer(&self.env_pixels)),
            (11, Res::Buffer(&self.env_marginal)),
            (12, Res::Buffer(&self.env_conditional)),
            (13, Res::Buffer(&self.uvs)),
            (14, Res::Buffer(&self.texels)),
            (15, Res::Buffer(&self.tex_info)),
            (16, Res::Buffer(&self.vnormals)),
            (
                17,
                Res::Buffer(acc.lighting.as_ref().unwrap_or(&self.dummy)),
            ),
            (
                18,
                Res::Buffer(acc.pixel_stats.as_ref().unwrap_or(&self.dummy)),
            ),
            (
                19,
                Res::Buffer(acc.restir.as_ref().map_or(&self.dummy, |r| &r.0)),
            ),
        ]
    }

    /// Runs one dispatch of a one-shot kernel (the normal and AOV passes) and waits for it.
    fn run_once(
        &self,
        pipeline: &Pipeline,
        resources: &[(u32, Res<'_>)],
        (width, height): (u32, u32),
    ) -> Result<(), Error> {
        let desc = Descriptors::new(&self.ctx, 1)?;
        let set = desc.set(pipeline, resources)?;
        self.ctx.submit(|d, cmd| {
            // SAFETY: the pipeline, set and every buffer outlive the submission, which is waited for.
            unsafe {
                d.cmd_bind_pipeline(cmd, vk::PipelineBindPoint::COMPUTE, pipeline.raw);
                d.cmd_bind_descriptor_sets(
                    cmd,
                    vk::PipelineBindPoint::COMPUTE,
                    pipeline.layout,
                    0,
                    &[set],
                    &[],
                );
                d.cmd_dispatch(cmd, groups(width, 8), groups(height, 8), 1);
            }
        })
    }

    fn camera_buffer(&self, width: u32, height: u32) -> Result<Buffer, Error> {
        let mut up = Upload::new(&self.ctx);
        let camera = up.buffer(&self.view.camera_record(width, height), STORAGE, "camera")?;
        up.flush()?;
        Ok(camera)
    }
}

/// Running radiance sum for progressive rendering; add samples until the noise is acceptable.
pub struct Accumulation {
    ctx: VulkanContext,
    buffer: Buffer,
    width: u32,
    height: u32,
    samples: u32,
    gpu_seconds: f64,
    /// Running sums of the lighting split, when requested.
    lighting: Option<Buffer>,
    /// Path queues and state, made on the first wavefront `accumulate`.
    wavefront: Option<wavefront::Buffers>,
    /// GPU seconds of the extend and shade stages, when stage timing is on.
    stage_seconds: Option<[f64; 2]>,
    /// Adaptive sampling only: samples, luminance sum and luminance square sum per pixel.
    pixel_stats: Option<Buffer>,
    /// The adaptive setting the accumulation started with; the stats are only valid under it.
    adaptive: Option<Adaptive>,
    /// ReSTIR only: the reservoirs (80 floats per pixel, `RESTIR_FLOATS_PER_PIXEL`), the setting the
    /// accumulation started with, and their size in bytes.
    restir: Option<(Buffer, Restir, usize)>,
}

impl Accumulation {
    fn pixels(&self) -> usize {
        self.width as usize * self.height as usize
    }

    // A failed readback means the device is lost, which the infallible `Accumulation` interface
    // (Metal reads shared memory) cannot report.
    fn read(&self, buf: &Buffer, floats: usize) -> Vec<f32> {
        self.ctx
            .read_f32(buf, floats)
            .expect("reading back an accumulation failed (device lost?)")
    }

    fn stats(&self) -> Option<Vec<f32>> {
        Some(self.read(self.pixel_stats.as_ref()?, self.pixels() * 3))
    }

    /// 1 / samples per pixel, for turning the sums into means.
    fn inverse_samples(&self) -> Vec<f32> {
        readback::inverse_samples(self.stats().as_deref(), self.pixels(), self.samples)
    }
}

impl verion_gpu::Accumulation for Accumulation {
    fn samples(&self) -> u32 {
        self.samples
    }

    fn gpu_seconds(&self) -> f64 {
        self.gpu_seconds
    }

    fn stage_seconds(&self) -> Option<[f64; 2]> {
        self.stage_seconds
    }

    fn wavefront_bytes(&self) -> usize {
        self.wavefront.as_ref().map_or(0, wavefront::Buffers::bytes)
    }

    fn restir_bytes(&self) -> usize {
        self.restir.as_ref().map_or(0, |r| r.2)
    }

    fn mean(&self) -> Vec<[f32; 3]> {
        let sums = self.read(&self.buffer, self.pixels() * 3);
        readback::mean(&sums, &self.inverse_samples())
    }

    fn lighting(&self) -> Option<LightingAovs> {
        let data = self.read(
            self.lighting.as_ref()?,
            self.pixels() * readback::LIGHTING_STRIDE,
        );
        Some(readback::lighting(&data, &self.inverse_samples()))
    }

    fn sample_counts(&self) -> Option<Vec<u32>> {
        Some(readback::sample_counts(&self.stats()?))
    }

    fn active_pixels(&self) -> usize {
        readback::active_pixels(self.stats().as_deref(), self.adaptive, self.pixels())
    }
}

/// The path tracer's bindings plus the wavefront's (`shaders/include/wf_state.slang`, 20..25):
/// queue `parity` is read, `out` is written.
fn wf_resources<'a>(
    path: &[(u32, Res<'a>)],
    w: &'a wavefront::Buffers,
    parity: usize,
    out: &'a Buffer,
) -> Vec<(u32, Res<'a>)> {
    let mut r = path.to_vec();
    r.extend([
        (20, Res::Buffer(&w.state)),
        (21, Res::Buffer(&w.hits)),
        (22, Res::Buffer(&w.queues[parity])),
        (23, Res::Buffer(out)),
        (24, Res::Buffer(&w.counts)),
        (25, Res::Buffer(&w.args)),
    ]);
    r
}

/// One dispatch to record: which kernel, which parameter block, and the bounce depth (which picks
/// the indirect arguments and the queue pair).
#[derive(Clone, Copy)]
struct Step {
    stage: Option<Stage>, // `None` is the megakernel
    block: usize,
    depth: usize,
}

impl RayTracingBackend for Renderer {
    type Context = VulkanContext;
    type Accumulation = Accumulation;
    type Error = Error;

    fn context() -> Result<VulkanContext, Error> {
        VulkanContext::new()
    }

    fn memory(ctx: &VulkanContext) -> MemoryUsage {
        ctx.memory()
    }

    fn new(ctx: &VulkanContext, scene: &Scene) -> Result<Self, Error> {
        Renderer::new(ctx, scene)
    }

    fn set_camera(&mut self, cam: &Camera) {
        self.view = View::new(cam);
    }

    fn set_multiscatter(&mut self, on: bool) {
        self.multiscatter = on;
    }

    fn set_integrator(&mut self, integrator: Integrator) {
        self.integrator = integrator;
    }

    fn integrator(&self) -> Integrator {
        self.integrator
    }

    /// Wavefront only: a timestamp pair around each dispatch splits the GPU time into extend
    /// (closest-hit tracing, with the dispatch sizing) and shade.
    fn set_stage_timing(&mut self, on: bool) {
        self.stage_timing = on;
    }

    fn set_adaptive(&mut self, adaptive: Option<Adaptive>) {
        self.adaptive = adaptive;
    }

    fn set_restir(&mut self, restir: Option<Restir>) {
        self.restir = restir;
    }

    /// Applies scene edits, redoing only what `pack::UpdatePlan` says (REQ-ACC-003). The pipelines
    /// and descriptors are untouched: descriptor sets are made per `accumulate` from the buffers
    /// held here, so replacing a buffer is enough.
    fn update(&mut self, scene: &Scene, changes: &Changes) -> Result<UpdateReport, Error> {
        let plan = pack::UpdatePlan::new(changes);
        let mut report = UpdateReport::default();
        if plan.camera {
            self.view = View::new(scene.camera());
        }
        let ctx = self.ctx.clone();
        let size = |n: usize| n * 4;
        if plan.vertices {
            let g = pack::pack_geometry(scene);
            let geometry =
                STORAGE | vk::BufferUsageFlags::ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR;
            let mut up = Upload::new(&ctx);
            self.positions = up.buffer(&g.positions, geometry, "positions")?;
            self.uvs = up.buffer(&g.uvs, STORAGE, "uvs")?;
            self.vnormals = up.buffer(&g.vnormals, STORAGE, "vertex normals")?;
            report.bytes_uploaded += size(g.positions.len() + g.uvs.len() + g.vnormals.len());
            if plan.full {
                self.indices = up.buffer(&g.indices, geometry, "indices")?;
                report.bytes_uploaded += size(g.indices.len());
            }
            up.flush()?;
            let ids: Vec<usize> = if plan.full {
                (0..g.meshes.len()).collect()
            } else {
                plan.blases.clone()
            };
            let ranges: Vec<pack::MeshRange> = ids.iter().map(|&m| g.meshes[m]).collect();
            // A built structure keeps its own copy of the triangles, so the BLASes of untouched
            // meshes stay valid although the position buffer is a new one.
            let built = accel::build_blases(&ctx, &self.positions, &self.indices, &ranges)?;
            report.blases_built = built.len();
            if plan.full {
                self.blases = built;
                self.meshes = g.meshes;
            } else {
                for (m, b) in ids.into_iter().zip(built) {
                    self.blases[m] = b;
                }
            }
        }
        if plan.materials {
            let mut m = pack::pack_materials(scene, false).map_err(Error::Scene)?;
            report.bytes_uploaded += size(m.materials.len());
            self.materials = put(&ctx, &m.materials, STORAGE, "materials")?;
            if m.images != self.texture_images {
                m = pack::pack_materials(scene, true).map_err(Error::Scene)?;
                report.bytes_uploaded += size(m.texels.len() + m.tex_info.len());
                self.texels = put(&ctx, &m.texels, STORAGE, "texels")?;
                self.tex_info = put(&ctx, &m.tex_info, STORAGE, "texture info")?;
                self.texture_images = m.images;
            }
        }
        if plan.lights {
            let table = pack::pack_lights(scene);
            report.bytes_uploaded += size(table.lights.len());
            self.lights = put(&ctx, &table.lights, STORAGE, "lights")?;
            self.info.light_count = (table.lights.len() / pack::LIGHT_WORDS) as u32;
            self.info.sky = table.sky;
            self.info.virtual_light = table.virtual_light;
            self.info.transparent_background = table.transparent_background;
            let key = pack::env_key(scene);
            if key != self.env_key {
                let env = pack::pack_env(scene).map_err(Error::Scene)?;
                report.bytes_uploaded +=
                    size(env.pixels.len() + env.marginal.len() + env.conditional.len());
                self.env_pixels = put(&ctx, &env.pixels, STORAGE, "env pixels")?;
                self.env_marginal = put(&ctx, &env.marginal, STORAGE, "env marginal")?;
                self.env_conditional = put(&ctx, &env.conditional, STORAGE, "env conditional")?;
                self.info.env_width = env.width;
                self.info.env_height = env.height;
                self.info.env_pdf_scale = env.pdf_scale;
                self.env_key = key;
            }
        }
        let mut bases = None;
        if plan.emitters {
            let e = pack::pack_emitters(scene);
            report.bytes_uploaded += size(e.words.len() + e.cdf.len());
            self.emitters = put(&ctx, &e.words, STORAGE, "emitters")?;
            self.emit_cdf = put(&ctx, &e.cdf, STORAGE, "emitter cdf")?;
            self.info.emitter_count = e.count();
            bases = Some(e.bases);
        }
        if plan.instances {
            let bases = match bases {
                Some(b) => b,
                None => pack::pack_emitters(scene).bases,
            };
            let (table, tlas) = pack::pack_instances(scene, &self.meshes, &bases);
            report.bytes_uploaded += size(table.len());
            self.instances = put(&ctx, &table, STORAGE, "instances")?;
            if plan.tlas {
                self.tlas = accel::build_tlas(&ctx, &self.blases, &tlas)?;
                report.tlas_built = true;
            }
        }
        Ok(report)
    }

    fn new_accumulation(
        &self,
        width: u32,
        height: u32,
        lighting: bool,
    ) -> Result<Accumulation, Error> {
        if width == 0 || height == 0 {
            return Err(Error::Scene("image size must be non-zero".into()));
        }
        let pixels = width as u64 * height as u64;
        let lighting = if lighting {
            let len = pixels * readback::LIGHTING_STRIDE as u64 * 4;
            Some(self.ctx.zeroed(len, RESULT, "lighting buffer")?)
        } else {
            None
        };
        Ok(Accumulation {
            ctx: self.ctx.clone(),
            buffer: self
                .ctx
                .zeroed(pixels * 12, RESULT, "accumulation buffer")?,
            width,
            height,
            samples: 0,
            gpu_seconds: 0.0,
            lighting,
            wavefront: None,
            stage_seconds: None,
            pixel_stats: None,
            adaptive: None,
            restir: None,
        })
    }

    fn accumulate(&self, acc: &mut Accumulation, samples: u32) -> Result<(), Error> {
        let base = pack::base_params(
            &self.info,
            &self.view,
            (acc.width, acc.height),
            acc.lighting.is_some(),
            self.multiscatter,
            self.adaptive,
            self.restir,
        );
        if acc.samples == 0 {
            acc.adaptive = self.adaptive;
            acc.restir = match self.restir {
                Some(r) => {
                    let bytes = acc.pixels() * RESTIR_FLOATS_PER_PIXEL * 4;
                    Some((
                        self.ctx.zeroed(bytes as u64, RESULT, "reservoirs")?,
                        r,
                        bytes,
                    ))
                }
                None => None,
            };
        }
        if acc.restir.as_ref().map(|r| r.1) != self.restir {
            return Err(Error::Scene(
                "ReSTIR was switched mid-accumulation; start a new accumulation".into(),
            ));
        }
        if acc.pixel_stats.is_none() && acc.adaptive.is_some() {
            acc.pixel_stats = Some(self.ctx.zeroed(
                acc.pixels() as u64 * 12,
                RESULT,
                "pixel stats",
            )?);
        }
        // The stats count every sample from the first one on, or the means come out wrong.
        if acc.adaptive.is_some() != self.adaptive.is_some() {
            return Err(Error::Scene(
                "adaptive sampling was switched mid-accumulation; start a new accumulation".into(),
            ));
        }
        let wavefront = self.integrator == Integrator::Wavefront;
        if wavefront && acc.wavefront.is_none() {
            acc.wavefront = Some(wavefront::Buffers::new(
                &self.ctx,
                acc.pixels(),
                acc.lighting.is_some(),
            )?);
        }

        // The plan: parameter blocks (words 6, 30, 31 and 35 differ) and the dispatches that read them.
        let mut blocks: Vec<[u32; PARAM_WORDS]> = Vec::new();
        let mut steps: Vec<Step> = Vec::new();
        if wavefront {
            let adaptive = base[32] != 0;
            for k in 0..samples {
                for depth in 0..MAX_DEPTH as usize {
                    let mut b = base;
                    b[6] = acc.samples + k;
                    b[30] = depth as u32;
                    b[31] = acc.width * acc.height;
                    blocks.push(b);
                    steps.extend(Stage::of_depth(depth, adaptive).map(|s| Step {
                        stage: Some(s),
                        block: blocks.len() - 1,
                        depth,
                    }));
                }
            }
        } else {
            let mut k = 0;
            while k < samples {
                let mut b = base;
                b[6] = acc.samples + k;
                // ReSTIR reads other pixels' last frame, so each dispatch is one sample.
                b[35] = (samples - k).min(if acc.restir.is_some() {
                    1
                } else {
                    SAMPLES_PER_DISPATCH
                });
                k += b[35];
                blocks.push(b);
                steps.push(Step {
                    stage: None,
                    block: blocks.len() - 1,
                    depth: 0,
                });
            }
        }
        if steps.is_empty() {
            return Ok(());
        }

        let stride = align_up((PARAM_WORDS * 4) as u64, self.ctx.0.info.storage_alignment);
        let mut params = Buffer::new(
            &self.ctx,
            stride * blocks.len() as u64,
            STORAGE,
            MemoryLocation::CpuToGpu,
            "parameter blocks",
        )?;
        for (i, b) in blocks.iter().enumerate() {
            let at = i * stride as usize;
            params.mapped()[at..at + PARAM_WORDS * 4].copy_from_slice(bytes_of(b));
        }

        let desc = Descriptors::new(&self.ctx, 8)?;
        let path = self.path_resources(acc, &params);
        let restir_on = self.restir.is_some();
        let variant = usize::from(restir_on);
        let mega_pipe = if wavefront {
            None
        } else {
            Some(
                self.pathtrace[variant]
                    .get_or_init(|| {
                        Pipeline::new(
                            &self.ctx,
                            "pathtrace",
                            spirv("pathtrace"),
                            Some(PARAMS_BINDING),
                            restir_on,
                        )
                    })
                    .as_ref()
                    .map_err(Clone::clone)?,
            )
        };
        let mut mega_set = vk::DescriptorSet::null();
        // Per queue parity, then per stage (args, extend, shade); the select set is apart.
        let mut wf_sets = [[vk::DescriptorSet::null(); 3]; 2];
        let mut select_set = vk::DescriptorSet::null();
        let wf_pipes = if wavefront {
            Some(
                self.wavefront[variant]
                    .get_or_init(|| wavefront::Pipelines::new(&self.ctx, restir_on))
                    .as_ref()
                    .map_err(Clone::clone)?,
            )
        } else {
            None
        };
        if let (Some(p), Some(w)) = (wf_pipes, acc.wavefront.as_ref()) {
            for (parity, sets) in wf_sets.iter_mut().enumerate() {
                let r = wf_resources(&path, w, parity, &w.queues[1 - parity]);
                *sets = [
                    desc.set(&p.args, &r)?,
                    desc.set(&p.extend, &r)?,
                    desc.set(&p.shade, &r)?,
                ];
            }
            // wf_select fills the depth-0 queue, which depth 0 then reads as its input.
            select_set = desc.set(&p.select, &wf_resources(&path, w, 0, &w.queues[0]))?;
        } else {
            mega_set = desc.set(
                mega_pipe.expect("the megakernel runs without the wavefront"),
                &path,
            )?;
        }

        let pipe_and_set = |s: &Step| -> (&Pipeline, vk::DescriptorSet) {
            let parity = s.depth % 2;
            match (s.stage, wf_pipes) {
                (Some(Stage::Select), Some(p)) => (&p.select, select_set),
                (Some(Stage::Args), Some(p)) => (&p.args, wf_sets[parity][0]),
                (Some(Stage::Extend), Some(p)) => (&p.extend, wf_sets[parity][1]),
                (Some(Stage::Shade), Some(p)) => (&p.shade, wf_sets[parity][2]),
                _ => (
                    mega_pipe.expect("the megakernel runs without the wavefront"),
                    mega_set,
                ),
            }
        };

        let period = self.ctx.0.info.timestamp_period_ns;
        let timed = self.stage_timing && wavefront && period.is_some();
        let queries = if timed { 2 * steps.len() } else { 2 } as u32;
        let device = &self.ctx.0.device;
        // SAFETY: destroyed below, after the submission has completed.
        let pool = match period {
            Some(_) => Some(unsafe {
                device.create_query_pool(
                    &vk::QueryPoolCreateInfo::default()
                        .query_type(vk::QueryType::TIMESTAMP)
                        .query_count(queries),
                    None,
                )?
            }),
            None => None,
        };
        let wall = Instant::now();
        let (w, h) = (acc.width, acc.height);
        let ran = self.ctx.submit(|d, cmd| {
            let stamp = |stage, q| {
                if let Some(pool) = pool {
                    // SAFETY: `q` is below the pool's query count and was reset above.
                    unsafe { d.cmd_write_timestamp(cmd, stage, pool, q) };
                }
            };
            // SAFETY: the pipelines, sets and buffers outlive the submission, which is waited for;
            // dynamic offsets stay inside the parameter buffer.
            unsafe {
                if let Some(pool) = pool {
                    d.cmd_reset_query_pool(cmd, pool, 0, queries);
                }
                if !timed {
                    stamp(vk::PipelineStageFlags::TOP_OF_PIPE, 0);
                }
                for (i, s) in steps.iter().enumerate() {
                    let (pipe, set) = pipe_and_set(s);
                    if timed {
                        stamp(vk::PipelineStageFlags::TOP_OF_PIPE, 2 * i as u32);
                    }
                    d.cmd_bind_pipeline(cmd, vk::PipelineBindPoint::COMPUTE, pipe.raw);
                    d.cmd_bind_descriptor_sets(
                        cmd,
                        vk::PipelineBindPoint::COMPUTE,
                        pipe.layout,
                        0,
                        &[set],
                        &[(s.block as u64 * stride) as u32],
                    );
                    match (s.stage, acc.wavefront.as_ref()) {
                        (None | Some(Stage::Select), _) => {
                            d.cmd_dispatch(cmd, groups(w, 8), groups(h, 8), 1)
                        }
                        (Some(Stage::Args), _) => d.cmd_dispatch(cmd, 1, 1, 1),
                        (_, Some(wf)) => {
                            d.cmd_dispatch_indirect(cmd, wf.args.raw, 12 * s.depth as u64)
                        }
                        _ => unreachable!("wavefront stages have wavefront buffers"),
                    }
                    if timed {
                        stamp(vk::PipelineStageFlags::BOTTOM_OF_PIPE, 2 * i as u32 + 1);
                    }
                    // Each dispatch reads what the one before wrote: sums, queues, counts and
                    // the indirect arguments. The transfer bit covers the readbacks after it.
                    d.cmd_pipeline_barrier(
                        cmd,
                        vk::PipelineStageFlags::COMPUTE_SHADER,
                        vk::PipelineStageFlags::COMPUTE_SHADER
                            | vk::PipelineStageFlags::DRAW_INDIRECT
                            | vk::PipelineStageFlags::TRANSFER,
                        vk::DependencyFlags::empty(),
                        &[vk::MemoryBarrier::default()
                            .src_access_mask(vk::AccessFlags::SHADER_WRITE)
                            .dst_access_mask(
                                vk::AccessFlags::SHADER_READ
                                    | vk::AccessFlags::SHADER_WRITE
                                    | vk::AccessFlags::INDIRECT_COMMAND_READ
                                    | vk::AccessFlags::TRANSFER_READ,
                            )],
                        &[],
                        &[],
                    );
                }
                if !timed {
                    stamp(vk::PipelineStageFlags::BOTTOM_OF_PIPE, 1);
                }
            }
        });
        let stamps = match (ran, pool) {
            (Ok(()), Some(pool)) => {
                let mut t = vec![0u64; queries as usize];
                // SAFETY: the submission has completed; the pool has `queries` results.
                let got = unsafe {
                    device.get_query_pool_results(
                        pool,
                        0,
                        &mut t,
                        vk::QueryResultFlags::TYPE_64 | vk::QueryResultFlags::WAIT,
                    )
                };
                got.map(|()| Some(t))
            }
            (Ok(()), None) => Ok(None),
            (Err(e), _) => {
                if let Some(pool) = pool {
                    // SAFETY: the submission failed or was waited for.
                    unsafe { device.destroy_query_pool(pool, None) };
                }
                return Err(e);
            }
        };
        if let Some(pool) = pool {
            // SAFETY: the submission has completed.
            unsafe { device.destroy_query_pool(pool, None) };
        }
        match (stamps?, period) {
            (Some(t), Some(ns)) => {
                let bits = self.ctx.0.info.timestamp_bits;
                let mask = if bits >= 64 {
                    u64::MAX
                } else {
                    (1u64 << bits) - 1
                };
                let seconds =
                    |a: usize, b: usize| (t[b].wrapping_sub(t[a]) & mask) as f64 * ns * 1e-9;
                if timed {
                    for (i, s) in steps.iter().enumerate() {
                        let dt = seconds(2 * i, 2 * i + 1);
                        acc.gpu_seconds += dt;
                        let slot = s.stage.map_or(0, Stage::timing_slot);
                        acc.stage_seconds.get_or_insert([0.0; 2])[slot] += dt;
                    }
                } else {
                    acc.gpu_seconds += seconds(0, 1);
                }
            }
            // No timestamps on this queue: the wall time of the submission stands in.
            _ => acc.gpu_seconds += wall.elapsed().as_secs_f64(),
        }
        acc.samples += samples;
        Ok(())
    }

    fn render_normals(&self, width: u32, height: u32) -> Result<Vec<[f32; 3]>, Error> {
        if width == 0 || height == 0 {
            return Err(Error::Scene("image size must be non-zero".into()));
        }
        let camera = self.camera_buffer(width, height)?;
        let pixels = width as usize * height as usize;
        let out = self.ctx.zeroed(pixels as u64 * 12, RESULT, "normals")?;
        self.run_once(
            &self.normals,
            &[
                (0, Res::Accel(self.tlas.raw)),
                (1, Res::Buffer(&self.positions)),
                (2, Res::Buffer(&self.indices)),
                (3, Res::Buffer(&self.instances)),
                (4, Res::Buffer(&camera)),
                (5, Res::Buffer(&out)),
                (6, Res::Buffer(&self.vnormals)),
            ],
            (width, height),
        )?;
        let data = self.ctx.read_f32(&out, pixels * 3)?;
        Ok(data.as_chunks::<3>().0.to_vec())
    }

    fn render_aovs(&self, width: u32, height: u32) -> Result<Aovs, Error> {
        if width == 0 || height == 0 {
            return Err(Error::Scene("image size must be non-zero".into()));
        }
        let camera = self.camera_buffer(width, height)?;
        let pixels = width as usize * height as usize;
        let albedo_depth = self
            .ctx
            .zeroed(pixels as u64 * 16, RESULT, "albedo and depth")?;
        let ids = self.ctx.zeroed(pixels as u64 * 4, RESULT, "object ids")?;
        let material_ids = self.ctx.zeroed(pixels as u64 * 4, RESULT, "material ids")?;
        let coverage = self.ctx.zeroed(pixels as u64 * 4, RESULT, "coverage")?;
        self.run_once(
            &self.aov,
            &[
                (0, Res::Accel(self.tlas.raw)),
                (1, Res::Buffer(&self.positions)),
                (2, Res::Buffer(&self.indices)),
                (3, Res::Buffer(&self.instances)),
                (4, Res::Buffer(&camera)),
                (5, Res::Buffer(&self.materials)),
                (6, Res::Buffer(&self.uvs)),
                (7, Res::Buffer(&self.tex_info)),
                (8, Res::Buffer(&self.texels)),
                (9, Res::Buffer(&albedo_depth)),
                (10, Res::Buffer(&ids)),
                (11, Res::Buffer(&material_ids)),
                (12, Res::Buffer(&coverage)),
            ],
            (width, height),
        )?;
        let ad = self.ctx.read_f32(&albedo_depth, pixels * 4)?;
        let ad = ad.as_chunks::<4>().0;
        Ok(Aovs {
            albedo: ad.iter().map(|p| [p[0], p[1], p[2]]).collect(),
            depth: ad.iter().map(|p| p[3]).collect(),
            object_id: self.ctx.read_u32(&ids, pixels)?,
            material_id: self.ctx.read_u32(&material_ids, pixels)?,
            coverage: self.ctx.read_f32(&coverage, pixels)?,
        })
    }
}
