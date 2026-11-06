//! Uploads a Scene IR snapshot and renders AOVs with the Slang-generated kernels.

use std::{cell::OnceCell, ffi::c_void, ptr::NonNull};

mod wavefront;

use objc2::runtime::ProtocolObject;
use objc2_foundation::NSString;
use objc2_metal::{
    MTLBuffer, MTLCommandBuffer, MTLCommandEncoder, MTLCommandQueue, MTLComputeCommandEncoder,
    MTLComputePipelineState, MTLDevice, MTLLibrary, MTLResourceOptions, MTLResourceUsage, MTLSize,
};
use verion_scene::{Camera, Changes, Scene};

use verion_gpu::{
    Accumulation as _, Adaptive, Aovs, Integrator, LightingAovs, MemoryUsage, RayTracingBackend,
    UpdateReport,
    pack::{self, MeshRange, PARAM_WORDS, SceneInfo, View},
    readback,
};

use crate::{Blas, Error, Instance, MetalContext, Obj, Tlas};

const NORMALS_MSL: &str = include_str!("../shaders/normals.metal");
const AOV_MSL: &str = include_str!("../shaders/aov.metal");
const PATHTRACE_MSL: &str = include_str!("../shaders/pathtrace.metal");

type CommandBuffer = Obj<dyn objc2_metal::MTLCommandBuffer>;
type Encoder = Obj<dyn MTLComputeCommandEncoder>;
/// Most samples one megakernel thread takes in a row. Fewer dispatches cut the launch cost and the
/// wait for each dispatch's slowest path; more would risk long-running command buffers.
const SAMPLES_PER_DISPATCH: u32 = 8;
fn upload<T: Copy>(ctx: &MetalContext, data: &[T]) -> Result<Obj<dyn MTLBuffer>, Error> {
    // Metal rejects zero-length buffers; a dummy word keeps empty tables bindable.
    let zero = [0u8; 4];
    let (ptr, len) = if data.is_empty() {
        (zero.as_ptr().cast::<c_void>(), zero.len())
    } else {
        (data.as_ptr().cast::<c_void>(), size_of_val(data))
    };
    ctx.check_fits(len)?;
    ctx.note_upload(len);
    // SAFETY: `ptr` is valid for `len` bytes; Metal copies them.
    unsafe {
        ctx.device.newBufferWithBytes_length_options(
            NonNull::new(ptr.cast_mut()).unwrap(),
            len,
            MTLResourceOptions::StorageModeShared,
        )
    }
    .ok_or(Error::Resource("buffer"))
}

fn pipeline(
    ctx: &MetalContext,
    msl: &str,
    entry: &str,
) -> Result<Obj<dyn MTLComputePipelineState>, Error> {
    let lib = ctx
        .device
        .newLibraryWithSource_options_error(&NSString::from_str(msl), None)
        .map_err(|e| Error::Shader(e.to_string()))?;
    let func = lib
        .newFunctionWithName(&NSString::from_str(entry))
        .ok_or_else(|| Error::Shader(format!("entry point `{entry}` not found")))?;
    ctx.device
        .newComputePipelineStateWithFunction_error(&func)
        .map_err(|e| Error::Shader(e.to_string()))
}

/// Environment map tables for importance sampling (empty when the scene has none).
struct EnvMap {
    pixels: Obj<dyn MTLBuffer>,
    marginal: Obj<dyn MTLBuffer>,
    conditional: Obj<dyn MTLBuffer>,
}

/// A scene snapshot ready to trace. Later scene edits are not reflected.
pub struct Renderer {
    ctx: MetalContext,
    tlas: Tlas,
    blases: Vec<Blas>,
    meshes: Vec<MeshRange>,
    /// Image per texture slot and the environment map identity the uploaded tables came from.
    texture_images: Vec<usize>,
    env_key: Option<(usize, u32)>,
    positions: Obj<dyn MTLBuffer>,
    indices: Obj<dyn MTLBuffer>,
    instances: Obj<dyn MTLBuffer>,
    materials: Obj<dyn MTLBuffer>,
    lights: Obj<dyn MTLBuffer>,
    emitters: Obj<dyn MTLBuffer>,
    emit_cdf: Obj<dyn MTLBuffer>,
    env: EnvMap,
    uvs: Obj<dyn MTLBuffer>,
    vnormals: Obj<dyn MTLBuffer>,
    texels: Obj<dyn MTLBuffer>,
    tex_info: Obj<dyn MTLBuffer>,
    info: SceneInfo,
    view: View,
    multiscatter: bool,
    normals: Obj<dyn MTLComputePipelineState>,
    aov: Obj<dyn MTLComputePipelineState>,
    pathtrace: Obj<dyn MTLComputePipelineState>,
    /// Bound in place of the lighting buffer when an accumulation has none.
    no_lighting: Obj<dyn MTLBuffer>,
    integrator: Integrator,
    /// Wavefront only: time extend and shade separately (see `run_wavefront`).
    stage_timing: bool,
    adaptive: Option<Adaptive>,
    /// Compiled on first use, so megakernel-only users skip the compile.
    wavefront: OnceCell<Result<wavefront::Pipelines, Error>>,
}

impl Renderer {
    pub fn new(ctx: &MetalContext, scene: &Scene) -> Result<Self, Error> {
        Self::build(ctx, scene, None)
    }

    /// Uploads `scene`. With `reuse`, the compiled pipelines of that renderer are taken over, so
    /// a geometry update does not pay for shader compilation again.
    fn build(ctx: &MetalContext, scene: &Scene, reuse: Option<&mut Self>) -> Result<Self, Error> {
        let packed = pack::pack(scene).map_err(Error::Scene)?;
        let blases = scene
            .meshes()
            .iter()
            .map(|mesh| Blas::build(ctx, mesh.positions(), mesh.indices()))
            .collect::<Result<Vec<_>, _>>()?;
        let tlas_instances: Vec<Instance> = packed
            .tlas
            .iter()
            .map(|&(mesh, transform)| Instance {
                blas: mesh as u32,
                transform,
            })
            .collect();
        let blas_refs: Vec<&Blas> = blases.iter().collect();
        let tlas = Tlas::build(ctx, &blas_refs, &tlas_instances)?;
        let pipelines = match reuse {
            Some(old) => (
                old.normals.clone(),
                old.aov.clone(),
                old.pathtrace.clone(),
                std::mem::take(&mut old.wavefront),
            ),
            None => (
                pipeline(ctx, NORMALS_MSL, "normals")?,
                pipeline(ctx, AOV_MSL, "aov")?,
                pipeline(ctx, PATHTRACE_MSL, "pathtrace")?,
                OnceCell::new(),
            ),
        };

        Ok(Self {
            ctx: ctx.clone(),
            positions: upload(ctx, &packed.positions)?,
            indices: upload(ctx, &packed.indices)?,
            instances: upload(ctx, &packed.instances)?,
            tlas,
            blases,
            meshes: packed.meshes.clone(),
            texture_images: packed.texture_images.clone(),
            env_key: pack::env_key(scene),
            materials: upload(ctx, &packed.materials)?,
            lights: upload(ctx, &packed.lights)?,
            env: EnvMap {
                pixels: upload(ctx, &packed.env.pixels)?,
                marginal: upload(ctx, &packed.env.marginal)?,
                conditional: upload(ctx, &packed.env.conditional)?,
            },
            uvs: upload(ctx, &packed.uvs)?,
            vnormals: upload(ctx, &packed.vnormals)?,
            texels: upload(ctx, &packed.texels)?,
            tex_info: upload(ctx, &packed.tex_info)?,
            emitters: upload(ctx, &packed.emitters)?,
            emit_cdf: upload(ctx, &packed.emit_cdf)?,
            info: packed.info,
            view: packed.view,
            multiscatter: true,
            normals: pipelines.0,
            aov: pipelines.1,
            pathtrace: pipelines.2,
            no_lighting: upload::<f32>(ctx, &[])?,
            integrator: Integrator::default(),
            stage_timing: false,
            adaptive: None,
            wavefront: pipelines.3,
        })
    }

    pub fn adaptive(&self) -> Option<Adaptive> {
        self.adaptive
    }

    /// Applies scene edits, redoing only what `pack::UpdatePlan` says (REQ-ACC-003).
    pub fn update(&mut self, scene: &Scene, changes: &Changes) -> Result<UpdateReport, Error> {
        let plan = pack::UpdatePlan::new(changes);
        let mut report = UpdateReport::default();
        if plan.camera {
            self.view = View::new(scene.camera());
        }
        if plan.full {
            let ctx = self.ctx.clone();
            let mut fresh = Self::build(&ctx, scene, Some(self))?;
            fresh.view = self.view;
            fresh.multiscatter = self.multiscatter;
            fresh.integrator = self.integrator;
            fresh.stage_timing = self.stage_timing;
            fresh.adaptive = self.adaptive;
            report.blases_built = fresh.blases.len();
            report.tlas_built = true;
            *self = fresh;
            return Ok(report);
        }
        if plan.vertices {
            for &m in &plan.blases {
                let mesh = &scene.meshes()[m];
                let r = self.meshes[m];
                // SAFETY: the buffers are shared-storage tables sized for these ranges when the
                // scene was uploaded (a mesh keeps its vertex count unless `Changes::geometry`),
                // and no GPU work runs between `accumulate` calls.
                unsafe {
                    let base = r.vertex_offset as usize;
                    let write =
                        |buf: &Obj<dyn MTLBuffer>,
                         per: usize,
                         data: &mut dyn Iterator<Item = f32>| {
                            let dst = buf.contents().as_ptr().cast::<f32>().add(base * per);
                            for (i, v) in data.take(r.vertex_count as usize * per).enumerate() {
                                *dst.add(i) = v;
                            }
                        };
                    write(
                        &self.positions,
                        3,
                        &mut mesh.positions().iter().flatten().copied(),
                    );
                    match mesh.uvs() {
                        Some(uv) => write(&self.uvs, 2, &mut uv.iter().flatten().copied()),
                        None => write(&self.uvs, 2, &mut std::iter::repeat(0.0)),
                    }
                    match mesh.normals() {
                        Some(n) => write(&self.vnormals, 3, &mut n.iter().flatten().copied()),
                        None => write(&self.vnormals, 3, &mut std::iter::repeat(0.0)),
                    }
                }
                report.bytes_uploaded += r.vertex_count as usize * 32;
                self.blases[m] = Blas::build(&self.ctx, mesh.positions(), mesh.indices())?;
                report.blases_built += 1;
            }
        }
        if plan.materials {
            let mut m = pack::pack_materials(scene, false).map_err(Error::Scene)?;
            report.bytes_uploaded += size_of_val(&m.materials[..]);
            self.materials = upload(&self.ctx, &m.materials)?;
            if m.images != self.texture_images {
                m = pack::pack_materials(scene, true).map_err(Error::Scene)?;
                report.bytes_uploaded += size_of_val(&m.texels[..]) + size_of_val(&m.tex_info[..]);
                self.texels = upload(&self.ctx, &m.texels)?;
                self.tex_info = upload(&self.ctx, &m.tex_info)?;
                self.texture_images = m.images;
            }
        }
        let table = pack::pack_lights(scene);
        if plan.lights {
            report.bytes_uploaded += size_of_val(&table.lights[..]);
            self.lights = upload(&self.ctx, &table.lights)?;
            self.info.light_count = (table.lights.len() / pack::LIGHT_WORDS) as u32;
            self.info.sky = table.sky;
            let key = pack::env_key(scene);
            if key != self.env_key {
                let env = pack::pack_env(scene).map_err(Error::Scene)?;
                report.bytes_uploaded += size_of_val(&env.pixels[..]);
                self.env = EnvMap {
                    pixels: upload(&self.ctx, &env.pixels)?,
                    marginal: upload(&self.ctx, &env.marginal)?,
                    conditional: upload(&self.ctx, &env.conditional)?,
                };
                self.info.env_width = env.width;
                self.info.env_height = env.height;
                self.info.env_pdf_scale = env.pdf_scale;
                self.env_key = key;
            }
        }
        let mut bases = None;
        if plan.emitters {
            let e = pack::pack_emitters(scene);
            report.bytes_uploaded += size_of_val(&e.words[..]) + size_of_val(&e.cdf[..]);
            self.emitters = upload(&self.ctx, &e.words)?;
            self.emit_cdf = upload(&self.ctx, &e.cdf)?;
            self.info.emitter_count = e.count();
            bases = Some(e.bases);
        }
        if plan.instances {
            let bases = match bases {
                Some(b) => b,
                None => pack::pack_emitters(scene).bases,
            };
            let (table, tlas) = pack::pack_instances(scene, &self.meshes, &bases);
            report.bytes_uploaded += size_of_val(&table[..]);
            self.instances = upload(&self.ctx, &table)?;
            if plan.tlas {
                let insts: Vec<Instance> = tlas
                    .iter()
                    .map(|&(mesh, transform)| Instance {
                        blas: mesh as u32,
                        transform,
                    })
                    .collect();
                let refs: Vec<&Blas> = self.blases.iter().collect();
                self.tlas = Tlas::build(&self.ctx, &refs, &insts)?;
                report.tlas_built = true;
            }
        }
        Ok(report)
    }
}

/// Running radiance sum for progressive rendering; add samples until the noise is acceptable.
pub struct Accumulation {
    buffer: Obj<dyn MTLBuffer>,
    width: u32,
    height: u32,
    samples: u32,
    gpu_seconds: f64,
    /// Running sums of the lighting split, when requested.
    lighting: Option<Obj<dyn MTLBuffer>>,
    /// Path queues and state, made on the first wavefront `accumulate`.
    wavefront: Option<wavefront::Buffers>,
    /// GPU seconds of the extend and shade stages, when stage timing is on.
    stage_seconds: Option<[f64; 2]>,
    /// Adaptive sampling only: samples, luminance sum and luminance square sum per pixel.
    pixel_stats: Option<Obj<dyn MTLBuffer>>,
    /// The adaptive setting the accumulation started with; the stats are only valid under it.
    adaptive: Option<Adaptive>,
}

impl Accumulation {
    fn stats(&self) -> Option<&[f32]> {
        let buffer = self.pixel_stats.as_ref()?;
        let n = self.width as usize * self.height as usize;
        // SAFETY: 3 floats per pixel, and `accumulate` waits for the GPU.
        Some(unsafe { std::slice::from_raw_parts(buffer.contents().as_ptr().cast::<f32>(), n * 3) })
    }

    /// 1 / samples per pixel, for turning the sums into means.
    fn inverse_samples(&self) -> Vec<f32> {
        let n = self.width as usize * self.height as usize;
        readback::inverse_samples(self.stats(), n, self.samples)
    }
}

impl Renderer {
    /// A command buffer and a compute encoder with the path tracer's bindings 0..18 set.
    fn open_encoder(&self, acc: &Accumulation) -> Result<(CommandBuffer, Encoder), Error> {
        let cb = self
            .ctx
            .queue
            .commandBuffer()
            .ok_or(Error::Resource("command buffer"))?;
        let enc = cb
            .computeCommandEncoder()
            .ok_or(Error::Resource("compute encoder"))?;
        enc.setComputePipelineState(&self.pathtrace);
        for blas in self.tlas.blases() {
            enc.useResource_usage(ProtocolObject::from_ref(&**blas), MTLResourceUsage::Read);
        }
        // SAFETY: indices match the `[[buffer(n)]]` order in the generated MSL (scene, positions,
        // indices, instances, materials, lights, params, accum, emitters, emit_cdf, env pixels, marginal, conditional, uvs, texels, texInfo, vnormals, lighting, pixelStats). Dispatches in one encoder run in
        // order, so the `+=` on `accum` never races.
        unsafe {
            enc.setAccelerationStructure_atBufferIndex(Some(self.tlas.raw()), 0);
            enc.setBuffer_offset_atIndex(Some(&self.positions), 0, 1);
            enc.setBuffer_offset_atIndex(Some(&self.indices), 0, 2);
            enc.setBuffer_offset_atIndex(Some(&self.instances), 0, 3);
            enc.setBuffer_offset_atIndex(Some(&self.materials), 0, 4);
            enc.setBuffer_offset_atIndex(Some(&self.lights), 0, 5);
            enc.setBuffer_offset_atIndex(Some(&acc.buffer), 0, 7);
            enc.setBuffer_offset_atIndex(Some(&self.emitters), 0, 8);
            enc.setBuffer_offset_atIndex(Some(&self.emit_cdf), 0, 9);
            enc.setBuffer_offset_atIndex(Some(&self.env.pixels), 0, 10);
            enc.setBuffer_offset_atIndex(Some(&self.env.marginal), 0, 11);
            enc.setBuffer_offset_atIndex(Some(&self.env.conditional), 0, 12);
            enc.setBuffer_offset_atIndex(Some(&self.uvs), 0, 13);
            enc.setBuffer_offset_atIndex(Some(&self.texels), 0, 14);
            enc.setBuffer_offset_atIndex(Some(&self.tex_info), 0, 15);
            enc.setBuffer_offset_atIndex(Some(&self.vnormals), 0, 16);
            enc.setBuffer_offset_atIndex(
                Some(acc.lighting.as_ref().unwrap_or(&self.no_lighting)),
                0,
                17,
            );
            enc.setBuffer_offset_atIndex(
                Some(acc.pixel_stats.as_ref().unwrap_or(&self.no_lighting)),
                0,
                18,
            );
        }
        Ok((cb, enc))
    }

    /// # Safety
    /// `enc` must have bindings 0..18 of `shaders/pathtrace.slang` set.
    unsafe fn encode_megakernel(
        &self,
        enc: &ProtocolObject<dyn MTLComputeCommandEncoder>,
        acc: &Accumulation,
        params: &mut [u32; PARAM_WORDS],
        samples: u32,
    ) {
        let mut k = 0;
        while k < samples {
            params[6] = acc.samples + k;
            params[35] = (samples - k).min(SAMPLES_PER_DISPATCH);
            k += params[35];
            // SAFETY: the block outlives the call and Metal copies it.
            unsafe {
                enc.setBytes_length_atIndex(
                    NonNull::from(&*params).cast::<c_void>(),
                    size_of_val(params),
                    6,
                );
            }
            enc.dispatchThreads_threadsPerThreadgroup(
                MTLSize {
                    width: acc.width as usize,
                    height: acc.height as usize,
                    depth: 1,
                },
                MTLSize {
                    width: 8,
                    height: 8,
                    depth: 1,
                },
            );
        }
    }

    /// One-shot render: mean radiance over `samples` paths per pixel.
    pub fn render(&self, width: u32, height: u32, samples: u32) -> Result<Vec<[f32; 3]>, Error> {
        let mut acc = self.new_accumulation(width, height, false)?;
        self.accumulate(&mut acc, samples)?;
        Ok(acc.mean())
    }
}

impl verion_gpu::Accumulation for Accumulation {
    /// Mean lighting split, or `None` unless made with `new_accumulation_with_lighting`.
    fn lighting(&self) -> Option<LightingAovs> {
        let buffer = self.lighting.as_ref()?;
        let n = self.width as usize * self.height as usize;
        // SAFETY: the buffer holds `n` records of `LIGHTING_STRIDE` floats and `accumulate` waits for the GPU.
        let data = unsafe {
            std::slice::from_raw_parts(
                buffer.contents().as_ptr().cast::<f32>(),
                n * readback::LIGHTING_STRIDE,
            )
        };
        Some(readback::lighting(data, &self.inverse_samples()))
    }

    /// GPU execution time of all `accumulate` calls so far, from command-buffer timestamps.
    /// The trace / shade split is `stage_seconds` (wavefront only).
    fn gpu_seconds(&self) -> f64 {
        self.gpu_seconds
    }

    fn samples(&self) -> u32 {
        self.samples
    }

    /// GPU seconds spent in the wavefront's extend (closest hit, with the dispatch sizing) and shade
    /// (shading with its shadow rays) stages; `None` unless `Renderer::set_stage_timing` was on.
    fn stage_seconds(&self) -> Option<[f64; 2]> {
        self.stage_seconds
    }

    /// GPU memory of the wavefront queues and path state (0 until a wavefront `accumulate`).
    fn wavefront_bytes(&self) -> usize {
        self.wavefront.as_ref().map_or(0, wavefront::Buffers::bytes)
    }

    /// Mean radiance per pixel, row-major from the top-left. All zero before the first sample.
    fn mean(&self) -> Vec<[f32; 3]> {
        let n = self.width as usize * self.height as usize;
        // SAFETY: the buffer holds `n` packed float3 values and `accumulate` waits for the GPU.
        let data = unsafe {
            std::slice::from_raw_parts(self.buffer.contents().as_ptr().cast::<f32>(), n * 3)
        };
        readback::mean(data, &self.inverse_samples())
    }

    /// Samples each pixel took, row-major from the top-left; `None` unless adaptive sampling ran.
    fn sample_counts(&self) -> Option<Vec<u32>> {
        Some(readback::sample_counts(self.stats()?))
    }

    /// Pixels the next sample would trace: all of them unless adaptive sampling stopped some.
    /// 0 means every pixel has converged and more samples change nothing.
    fn active_pixels(&self) -> usize {
        let n = self.width as usize * self.height as usize;
        readback::active_pixels(self.stats(), self.adaptive, n)
    }
}

impl RayTracingBackend for Renderer {
    type Context = MetalContext;
    type Accumulation = Accumulation;
    type Error = Error;

    fn context() -> Result<MetalContext, Error> {
        MetalContext::new()
    }

    fn memory(ctx: &MetalContext) -> MemoryUsage {
        ctx.memory()
    }

    fn new(ctx: &MetalContext, scene: &Scene) -> Result<Self, Error> {
        Renderer::new(ctx, scene)
    }

    fn update(&mut self, scene: &Scene, changes: &Changes) -> Result<UpdateReport, Error> {
        Renderer::update(self, scene, changes)
    }

    /// Replaces the camera without rebuilding the acceleration structures. Start a new
    /// accumulation afterwards; samples gathered from the old camera no longer match.
    fn set_camera(&mut self, cam: &Camera) {
        self.view = View::new(cam);
    }

    /// Turns the multiple-scattering compensation of rough metals on (the default) or off. Off gives
    /// the plain single-scattering GGX that other renderers such as Mitsuba 3 use, which the
    /// cross-check against them needs.
    fn set_multiscatter(&mut self, on: bool) {
        self.multiscatter = on;
    }

    /// Chooses the megakernel (the default) or the wavefront path tracer for later `accumulate`
    /// calls. Both run the same path code and give the same image (REQ-GPU-005).
    fn set_integrator(&mut self, integrator: Integrator) {
        self.integrator = integrator;
    }

    fn integrator(&self) -> Integrator {
        self.integrator
    }

    /// Wavefront only: submit each stage separately so `Accumulation::stage_seconds` splits the GPU
    /// time into extend (closest-hit tracing) and shade (REQ-GPU-004). Slows the render down.
    fn set_stage_timing(&mut self, on: bool) {
        self.stage_timing = on;
    }

    /// Turns per-pixel adaptive sampling on or off for accumulations started afterwards.
    /// `accumulate` then takes `samples` as the most each pixel gets, and
    /// `Accumulation::active_pixels` tells how many pixels still take samples.
    fn set_adaptive(&mut self, adaptive: Option<Adaptive>) {
        self.adaptive = adaptive;
    }

    /// World-space normal of the first hit per pixel, row-major from the top-left; misses are zero.
    /// Interpolated vertex normals (geometric normals for meshes without them), facing the viewer.
    fn render_normals(&self, width: u32, height: u32) -> Result<Vec<[f32; 3]>, Error> {
        if width == 0 || height == 0 {
            return Err(Error::Scene("image size must be non-zero".into()));
        }
        let camera = upload(&self.ctx, &self.view.camera_record(width, height))?;

        let pixels = width as usize * height as usize;
        let out = self
            .ctx
            .device
            .newBufferWithLength_options(
                pixels * size_of::<[f32; 3]>(),
                MTLResourceOptions::StorageModeShared,
            )
            .ok_or(Error::Resource("output buffer"))?;

        let cb = self
            .ctx
            .queue
            .commandBuffer()
            .ok_or(Error::Resource("command buffer"))?;
        let enc = cb
            .computeCommandEncoder()
            .ok_or(Error::Resource("compute encoder"))?;
        enc.setComputePipelineState(&self.normals);
        for blas in self.tlas.blases() {
            enc.useResource_usage(ProtocolObject::from_ref(&**blas), MTLResourceUsage::Read);
        }
        // SAFETY: indices match the `[[buffer(n)]]` order in the generated MSL (scene, positions,
        // indices, instances, camera, output, vnormals).
        unsafe {
            enc.setAccelerationStructure_atBufferIndex(Some(self.tlas.raw()), 0);
            enc.setBuffer_offset_atIndex(Some(&self.positions), 0, 1);
            enc.setBuffer_offset_atIndex(Some(&self.indices), 0, 2);
            enc.setBuffer_offset_atIndex(Some(&self.instances), 0, 3);
            enc.setBuffer_offset_atIndex(Some(&camera), 0, 4);
            enc.setBuffer_offset_atIndex(Some(&out), 0, 5);
            enc.setBuffer_offset_atIndex(Some(&self.vnormals), 0, 6);
        }
        enc.dispatchThreads_threadsPerThreadgroup(
            MTLSize {
                width: width as usize,
                height: height as usize,
                depth: 1,
            },
            MTLSize {
                width: 8,
                height: 8,
                depth: 1,
            },
        );
        enc.endEncoding();
        cb.commit();
        cb.waitUntilCompleted();

        // SAFETY: `out` holds `pixels` packed float3 values and the command buffer has completed.
        let data = unsafe {
            std::slice::from_raw_parts(out.contents().as_ptr().cast::<f32>(), pixels * 3)
        };
        Ok(data.as_chunks::<3>().0.to_vec())
    }

    /// Albedo, depth and instance id of the first hit through each pixel centre (one sample, so ids
    /// and depth are never blended).
    fn render_aovs(&self, width: u32, height: u32) -> Result<Aovs, Error> {
        if width == 0 || height == 0 {
            return Err(Error::Scene("image size must be non-zero".into()));
        }
        let camera = upload(&self.ctx, &self.view.camera_record(width, height))?;

        let pixels = width as usize * height as usize;
        let buffer = |bytes: usize| {
            self.ctx
                .device
                .newBufferWithLength_options(bytes, MTLResourceOptions::StorageModeShared)
                .ok_or(Error::Resource("output buffer"))
        };
        let albedo_depth = buffer(pixels * size_of::<[f32; 4]>())?;
        let ids = buffer(pixels * size_of::<u32>())?;
        let material_ids = buffer(pixels * size_of::<u32>())?;

        let cb = self
            .ctx
            .queue
            .commandBuffer()
            .ok_or(Error::Resource("command buffer"))?;
        let enc = cb
            .computeCommandEncoder()
            .ok_or(Error::Resource("compute encoder"))?;
        enc.setComputePipelineState(&self.aov);
        for blas in self.tlas.blases() {
            enc.useResource_usage(ProtocolObject::from_ref(&**blas), MTLResourceUsage::Read);
        }
        // SAFETY: indices match the `[[buffer(n)]]` order in the generated MSL (scene, positions,
        // indices, instances, camera, materials, uvs, texInfo, texels, albedoDepth, objectIds, materialIds).
        unsafe {
            enc.setAccelerationStructure_atBufferIndex(Some(self.tlas.raw()), 0);
            enc.setBuffer_offset_atIndex(Some(&self.positions), 0, 1);
            enc.setBuffer_offset_atIndex(Some(&self.indices), 0, 2);
            enc.setBuffer_offset_atIndex(Some(&self.instances), 0, 3);
            enc.setBuffer_offset_atIndex(Some(&camera), 0, 4);
            enc.setBuffer_offset_atIndex(Some(&self.materials), 0, 5);
            enc.setBuffer_offset_atIndex(Some(&self.uvs), 0, 6);
            enc.setBuffer_offset_atIndex(Some(&self.tex_info), 0, 7);
            enc.setBuffer_offset_atIndex(Some(&self.texels), 0, 8);
            enc.setBuffer_offset_atIndex(Some(&albedo_depth), 0, 9);
            enc.setBuffer_offset_atIndex(Some(&ids), 0, 10);
            enc.setBuffer_offset_atIndex(Some(&material_ids), 0, 11);
        }
        enc.dispatchThreads_threadsPerThreadgroup(
            MTLSize {
                width: width as usize,
                height: height as usize,
                depth: 1,
            },
            MTLSize {
                width: 8,
                height: 8,
                depth: 1,
            },
        );
        enc.endEncoding();
        cb.commit();
        cb.waitUntilCompleted();

        // SAFETY: the buffers hold `pixels` float4 and u32 values and the command buffer has completed.
        let (ad, ids, mids) = unsafe {
            (
                std::slice::from_raw_parts(
                    albedo_depth.contents().as_ptr().cast::<f32>(),
                    pixels * 4,
                ),
                std::slice::from_raw_parts(ids.contents().as_ptr().cast::<u32>(), pixels),
                std::slice::from_raw_parts(material_ids.contents().as_ptr().cast::<u32>(), pixels),
            )
        };
        let ad = ad.as_chunks::<4>().0;
        Ok(Aovs {
            albedo: ad.iter().map(|p| [p[0], p[1], p[2]]).collect(),
            depth: ad.iter().map(|p| p[3]).collect(),
            object_id: ids.to_vec(),
            material_id: mids.to_vec(),
        })
    }

    /// Traces `samples` more paths per pixel into `acc` and waits for the GPU.
    fn accumulate(&self, acc: &mut Accumulation, samples: u32) -> Result<(), Error> {
        let mut params = pack::base_params(
            &self.info,
            &self.view,
            (acc.width, acc.height),
            acc.lighting.is_some(),
            self.multiscatter,
            self.adaptive,
        );

        if acc.samples == 0 {
            acc.adaptive = self.adaptive;
        }
        if acc.pixel_stats.is_none() && acc.adaptive.is_some() {
            let len = acc.width as usize * acc.height as usize * 3 * size_of::<f32>();
            self.ctx.check_fits(len)?;
            acc.pixel_stats = Some(
                self.ctx
                    .device
                    .newBufferWithLength_options(len, MTLResourceOptions::StorageModeShared)
                    .ok_or(Error::Resource("pixel stats buffer"))?,
            );
        }
        // The stats count every sample from the first one on, or the means come out wrong.
        if acc.adaptive.is_some() != self.adaptive.is_some() {
            return Err(Error::Scene(
                "adaptive sampling was switched mid-accumulation; start a new accumulation".into(),
            ));
        }
        let wavefront = self.integrator == Integrator::Wavefront;

        if wavefront && acc.wavefront.is_none() {
            let paths = acc.width as usize * acc.height as usize;
            acc.wavefront = Some(wavefront::Buffers::new(
                &self.ctx,
                paths,
                acc.lighting.is_some(),
            )?);
        }

        if wavefront {
            self.run_wavefront(acc, &mut params, samples)?;
        } else {
            let (cb, enc) = self.open_encoder(acc)?;
            // SAFETY: `open_encoder` set bindings 0..18.
            unsafe { self.encode_megakernel(&enc, acc, &mut params, samples) };
            enc.endEncoding();
            cb.commit();
            cb.waitUntilCompleted();
            acc.gpu_seconds += cb.GPUEndTime() - cb.GPUStartTime();
        }
        acc.samples += samples;
        Ok(())
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
        // Metal zero-fills new buffers, which is the empty sum.
        let pixels = width as usize * height as usize;
        let buffer = self
            .ctx
            .device
            .newBufferWithLength_options(
                pixels * size_of::<[f32; 3]>(),
                MTLResourceOptions::StorageModeShared,
            )
            .ok_or(Error::Resource("accumulation buffer"))?;
        // The lighting split is 65 floats per pixel, about 260 bytes per pixel more.
        let lighting = if lighting {
            let len = pixels * readback::LIGHTING_STRIDE * size_of::<f32>();
            self.ctx.check_fits(len)?;
            Some(
                self.ctx
                    .device
                    .newBufferWithLength_options(len, MTLResourceOptions::StorageModeShared)
                    .ok_or(Error::Resource("lighting buffer"))?,
            )
        } else {
            None
        };
        Ok(Accumulation {
            buffer,
            width,
            height,
            samples: 0,
            gpu_seconds: 0.0,
            lighting,
            wavefront: None,
            stage_seconds: None,
            pixel_stats: None,
            adaptive: None,
        })
    }
}
