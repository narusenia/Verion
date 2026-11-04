//! Uploads a Scene IR snapshot and renders AOVs with the Slang-generated kernels.

use std::{ffi::c_void, ptr::NonNull};

use objc2::runtime::ProtocolObject;
use objc2_foundation::NSString;
use objc2_metal::{
    MTLBuffer, MTLCommandBuffer, MTLCommandEncoder, MTLCommandQueue, MTLComputeCommandEncoder,
    MTLComputePipelineState, MTLDevice, MTLLibrary, MTLResourceOptions, MTLResourceUsage, MTLSize,
};
use verion_scene::{Light, Scene, Transform};

use crate::{Blas, Error, Instance, MetalContext, Obj, Tlas};

const NORMALS_MSL: &str = include_str!("../shaders/normals.metal");
const PATHTRACE_MSL: &str = include_str!("../shaders/pathtrace.metal");

/// Path length limit. Radiance beyond it is dropped, so closed furnaces read slightly dark.
const MAX_DEPTH: u32 = 8;
const MATERIAL_WORDS: usize = 12;
const LIGHT_WORDS: usize = 8;
/// Words per emissive triangle; must match `shaders/pathtrace.slang`.
const EMITTER_WORDS: usize = 16;

/// Words per record in the instance table; must match `shaders/normals.slang`.
const INSTANCE_WORDS: usize = 16;

fn world(t: &Transform, p: [f32; 3]) -> [f32; 3] {
    std::array::from_fn(|r| t[r][0] * p[0] + t[r][1] * p[1] + t[r][2] * p[2] + t[r][3])
}

fn upload<T: Copy>(ctx: &MetalContext, data: &[T]) -> Result<Obj<dyn MTLBuffer>, Error> {
    // Metal rejects zero-length buffers; a dummy word keeps empty tables bindable.
    let zero = [0u8; 4];
    let (ptr, len) = if data.is_empty() {
        (zero.as_ptr().cast::<c_void>(), zero.len())
    } else {
        (data.as_ptr().cast::<c_void>(), size_of_val(data))
    };
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

/// A scene snapshot ready to trace. Later scene edits are not reflected.
pub struct Renderer {
    ctx: MetalContext,
    tlas: Tlas,
    _blases: Vec<Blas>,
    positions: Obj<dyn MTLBuffer>,
    indices: Obj<dyn MTLBuffer>,
    instances: Obj<dyn MTLBuffer>,
    materials: Obj<dyn MTLBuffer>,
    lights: Obj<dyn MTLBuffer>,
    light_count: u32,
    emitters: Obj<dyn MTLBuffer>,
    emit_cdf: Obj<dyn MTLBuffer>,
    emitter_count: u32,
    sky: [f32; 3],
    aperture: f32,
    focus: f32,
    camera: [f32; 16],
    normals: Obj<dyn MTLComputePipelineState>,
    pathtrace: Obj<dyn MTLComputePipelineState>,
}

impl Renderer {
    pub fn new(ctx: &MetalContext, scene: &Scene) -> Result<Self, Error> {
        if scene.instances().is_empty() {
            return Err(Error::Scene("scene has no instances".into()));
        }
        let mut positions: Vec<f32> = Vec::new();
        let mut indices: Vec<u32> = Vec::new();
        let mut blases = Vec::new();
        let mut offsets = Vec::new(); // (vertex offset, index offset) per mesh
        for mesh in scene.meshes() {
            offsets.push(((positions.len() / 3) as u32, indices.len() as u32));
            positions.extend(mesh.positions().iter().flatten());
            indices.extend_from_slice(mesh.indices());
            blases.push(Blas::build(ctx, mesh.positions(), mesh.indices())?);
        }

        let mut table = vec![0u32; scene.instances().len() * INSTANCE_WORDS];
        let mut tlas_instances = Vec::new();
        let mut emitters: Vec<f32> = Vec::new();
        let mut powers: Vec<f32> = Vec::new(); // area * radiance per emissive triangle
        for (record, inst) in table.chunks_mut(INSTANCE_WORDS).zip(scene.instances()) {
            let (vertex_offset, index_offset) = offsets[inst.mesh.index()];
            record[0] = vertex_offset;
            record[1] = index_offset;
            record[2] = inst.material.index() as u32;
            for (word, v) in record[4..].iter_mut().zip(inst.transform.iter().flatten()) {
                *word = v.to_bits();
            }
            let le = scene.materials()[inst.material.index()].base.emission;
            let radiance = le[0] + le[1] + le[2];
            if radiance > 0.0 {
                let mesh = &scene.meshes()[inst.mesh.index()];
                record[3] = powers.len() as u32 + 1;
                for tri in mesh.indices().as_chunks::<3>().0 {
                    let [a, b, c] = [0, 1, 2]
                        .map(|k| world(&inst.transform, mesh.positions()[tri[k] as usize]));
                    let (e1, e2) = (
                        [b[0] - a[0], b[1] - a[1], b[2] - a[2]],
                        [c[0] - a[0], c[1] - a[1], c[2] - a[2]],
                    );
                    let cross = [
                        e1[1] * e2[2] - e1[2] * e2[1],
                        e1[2] * e2[0] - e1[0] * e2[2],
                        e1[0] * e2[1] - e1[1] * e2[0],
                    ];
                    let area = 0.5
                        * (cross[0] * cross[0] + cross[1] * cross[1] + cross[2] * cross[2]).sqrt();
                    powers.push(area * radiance);
                    // Degenerate triangles keep their slot (area 0) so primitive index maps to a record.
                    emitters.extend(a.into_iter().chain(b).chain(c).chain(le));
                    emitters.extend([area, 0.0, 0.0, 0.0]);
                }
            }
            tlas_instances.push(Instance {
                blas: inst.mesh.index() as u32,
                transform: inst.transform,
            });
        }
        let blas_refs: Vec<&Blas> = blases.iter().collect();
        let tlas = Tlas::build(ctx, &blas_refs, &tlas_instances)?;

        let cam = scene.camera();
        let mut camera = [0.0f32; 16];
        camera[2] = (cam.vertical_fov * 0.5).tan();
        for (dst, src) in camera[4..].iter_mut().zip(cam.transform.iter().flatten()) {
            *dst = *src;
        }

        // Selection probability proportional to emitted power; the CDF drives light sampling.
        let total: f32 = powers.iter().sum();
        let mut emit_cdf = Vec::with_capacity(powers.len());
        let mut running = 0.0;
        for (record, power) in emitters
            .as_chunks_mut::<EMITTER_WORDS>()
            .0
            .iter_mut()
            .zip(&powers)
        {
            record[13] = power / total;
            running += power / total;
            emit_cdf.push(running);
        }
        if let Some(last) = emit_cdf.last_mut() {
            *last = 1.0;
        }

        let mut materials = Vec::with_capacity(scene.materials().len() * MATERIAL_WORDS);
        for m in scene.materials() {
            let b = &m.base;
            let (c, e) = (b.base_color, b.emission);
            materials.extend([
                c[0],
                c[1],
                c[2],
                e[0],
                e[1],
                e[2],
                b.metallic,
                b.roughness,
                b.transmission,
                b.ior,
                0.0,
                0.0,
            ]);
        }

        // Environment lights are summed into one uniform sky; the rest go to the NEE table.
        let mut sky = [0.0f32; 3];
        let mut lights = Vec::new();
        for light in scene.lights() {
            let (kind, color, intensity, vector) = match *light {
                Light::Point {
                    position,
                    color,
                    intensity,
                } => (0u32, color, intensity, position),
                Light::Directional {
                    direction,
                    color,
                    intensity,
                } => (1, color, intensity, direction),
                Light::Environment { color } => {
                    sky.iter_mut().zip(color).for_each(|(s, c)| *s += c);
                    continue;
                }
            };
            let words: [u32; LIGHT_WORDS] = [
                kind,
                color[0].to_bits(),
                color[1].to_bits(),
                color[2].to_bits(),
                intensity.to_bits(),
                vector[0].to_bits(),
                vector[1].to_bits(),
                vector[2].to_bits(),
            ];
            lights.extend(words);
        }

        Ok(Self {
            ctx: ctx.clone(),
            positions: upload(ctx, &positions)?,
            indices: upload(ctx, &indices)?,
            instances: upload(ctx, &table)?,
            tlas,
            _blases: blases,
            materials: upload(ctx, &materials)?,
            light_count: (lights.len() / LIGHT_WORDS) as u32,
            lights: upload(ctx, &lights)?,
            emitter_count: powers.len() as u32,
            emitters: upload(ctx, &emitters)?,
            emit_cdf: upload(ctx, &emit_cdf)?,
            sky,
            aperture: cam.aperture_radius,
            focus: cam.focus_distance,
            camera,
            normals: pipeline(ctx, NORMALS_MSL, "normals")?,
            pathtrace: pipeline(ctx, PATHTRACE_MSL, "pathtrace")?,
        })
    }

    /// World-space normal of the first hit per pixel, row-major from the top-left; misses are zero.
    /// Normals face the viewer.
    pub fn render_normals(&self, width: u32, height: u32) -> Result<Vec<[f32; 3]>, Error> {
        if width == 0 || height == 0 {
            return Err(Error::Scene("image size must be non-zero".into()));
        }
        let mut camera = self.camera;
        camera[0] = width as f32;
        camera[1] = height as f32;
        let camera = upload(&self.ctx, &camera)?;

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
        // indices, instances, camera, output).
        unsafe {
            enc.setAccelerationStructure_atBufferIndex(Some(self.tlas.raw()), 0);
            enc.setBuffer_offset_atIndex(Some(&self.positions), 0, 1);
            enc.setBuffer_offset_atIndex(Some(&self.indices), 0, 2);
            enc.setBuffer_offset_atIndex(Some(&self.instances), 0, 3);
            enc.setBuffer_offset_atIndex(Some(&camera), 0, 4);
            enc.setBuffer_offset_atIndex(Some(&out), 0, 5);
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
}

/// Running radiance sum for progressive rendering; add samples until the noise is acceptable.
pub struct Accumulation {
    buffer: Obj<dyn MTLBuffer>,
    width: u32,
    height: u32,
    samples: u32,
}

impl Accumulation {
    pub fn samples(&self) -> u32 {
        self.samples
    }

    /// Mean radiance per pixel, row-major from the top-left. All zero before the first sample.
    pub fn mean(&self) -> Vec<[f32; 3]> {
        let n = self.width as usize * self.height as usize;
        // SAFETY: the buffer holds `n` packed float3 values and `accumulate` waits for the GPU.
        let data = unsafe {
            std::slice::from_raw_parts(self.buffer.contents().as_ptr().cast::<f32>(), n * 3)
        };
        let inv = 1.0 / self.samples.max(1) as f32;
        data.as_chunks::<3>()
            .0
            .iter()
            .map(|c| [c[0] * inv, c[1] * inv, c[2] * inv])
            .collect()
    }
}

impl Renderer {
    pub fn new_accumulation(&self, width: u32, height: u32) -> Result<Accumulation, Error> {
        if width == 0 || height == 0 {
            return Err(Error::Scene("image size must be non-zero".into()));
        }
        // Metal zero-fills new buffers, which is the empty sum.
        let buffer = self
            .ctx
            .device
            .newBufferWithLength_options(
                width as usize * height as usize * size_of::<[f32; 3]>(),
                MTLResourceOptions::StorageModeShared,
            )
            .ok_or(Error::Resource("accumulation buffer"))?;
        Ok(Accumulation {
            buffer,
            width,
            height,
            samples: 0,
        })
    }

    /// Traces `samples` more paths per pixel into `acc` and waits for the GPU.
    pub fn accumulate(&self, acc: &mut Accumulation, samples: u32) -> Result<(), Error> {
        let mut params = [0u32; 24];
        params[0] = acc.width;
        params[1] = acc.height;
        params[2] = self.camera[2].to_bits();
        params[3] = self.aperture.to_bits();
        params[4] = self.focus.to_bits();
        params[5] = self.light_count;
        params[7] = MAX_DEPTH;
        for (dst, src) in params[8..20].iter_mut().zip(&self.camera[4..16]) {
            *dst = src.to_bits();
        }
        for (dst, src) in params[20..23].iter_mut().zip(self.sky) {
            *dst = src.to_bits();
        }
        params[23] = self.emitter_count;

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
        // indices, instances, materials, lights, params, accum, emitters, emit_cdf). Dispatches in one encoder run in
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
            for k in 0..samples {
                params[6] = acc.samples + k;
                enc.setBytes_length_atIndex(
                    NonNull::from(&params).cast::<c_void>(),
                    size_of_val(&params),
                    6,
                );
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
        enc.endEncoding();
        cb.commit();
        cb.waitUntilCompleted();
        acc.samples += samples;
        Ok(())
    }

    /// One-shot render: mean radiance over `samples` paths per pixel.
    pub fn render(&self, width: u32, height: u32, samples: u32) -> Result<Vec<[f32; 3]>, Error> {
        let mut acc = self.new_accumulation(width, height)?;
        self.accumulate(&mut acc, samples)?;
        Ok(acc.mean())
    }
}
