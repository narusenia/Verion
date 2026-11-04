//! Uploads a Scene IR snapshot and renders AOVs with the Slang-generated kernels.

use std::{collections::HashMap, ffi::c_void, ptr::NonNull};

use objc2::runtime::ProtocolObject;
use objc2_foundation::NSString;
use objc2_metal::{
    MTLBuffer, MTLCommandBuffer, MTLCommandEncoder, MTLCommandQueue, MTLComputeCommandEncoder,
    MTLComputePipelineState, MTLDevice, MTLLibrary, MTLResourceOptions, MTLResourceUsage, MTLSize,
};
use verion_scene::{Image, Light, Scene, Transform};

use crate::{Blas, Error, Instance, MetalContext, Obj, Tlas};

const NORMALS_MSL: &str = include_str!("../shaders/normals.metal");
const PATHTRACE_MSL: &str = include_str!("../shaders/pathtrace.metal");

/// Path length limit. Radiance beyond it is dropped, so closed furnaces read slightly dark.
const MAX_DEPTH: u32 = 8;
const MATERIAL_WORDS: usize = 16;
const LIGHT_WORDS: usize = 16;
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

/// Environment map tables for importance sampling (empty when the scene has none).
struct EnvMap {
    pixels: Obj<dyn MTLBuffer>,
    marginal: Obj<dyn MTLBuffer>,
    conditional: Obj<dyn MTLBuffer>,
    width: u32,
    height: u32,
    /// `w * h / (2 pi^2 W)`: turns a texel luminance into a solid-angle density.
    pdf_scale: f32,
}

fn luminance(c: [f32; 3]) -> f32 {
    0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
}

/// Sampling tables over `luminance * sin(theta)`: a marginal CDF over rows and one CDF per row.
fn build_env(ctx: &MetalContext, scene: &Scene) -> Result<EnvMap, Error> {
    let mut maps = scene.lights().iter().filter_map(|l| match *l {
        Light::EnvironmentMap { image, scale } => Some((image, scale)),
        _ => None,
    });
    let first = maps.next();
    if maps.next().is_some() {
        return Err(Error::Scene("only one environment map is supported".into()));
    }
    let empty = |ctx: &MetalContext| -> Result<EnvMap, Error> {
        Ok(EnvMap {
            pixels: upload::<f32>(ctx, &[])?,
            marginal: upload::<f32>(ctx, &[])?,
            conditional: upload::<f32>(ctx, &[])?,
            width: 0,
            height: 0,
            pdf_scale: 0.0,
        })
    };
    let Some((id, scale)) = first else {
        return empty(ctx);
    };
    let image = scene
        .images()
        .get(id.index())
        .ok_or_else(|| Error::Scene("environment map refers to a missing image".into()))?;
    let (w, h) = (image.width() as usize, image.height() as usize);
    let pixels: Vec<f32> = image.pixels().iter().flatten().map(|v| v * scale).collect();

    let mut rows = vec![0.0f64; h];
    let mut conditional = vec![0.0f32; w * h];
    for (j, row) in rows.iter_mut().enumerate() {
        let sin_theta = (((j as f64) + 0.5) / h as f64 * std::f64::consts::PI).sin();
        let weights: Vec<f64> = (0..w)
            .map(|i| {
                f64::from(luminance([
                    pixels[3 * (j * w + i)],
                    pixels[3 * (j * w + i) + 1],
                    pixels[3 * (j * w + i) + 2],
                ])) * sin_theta
            })
            .collect();
        *row = weights.iter().sum();
        let mut running = 0.0;
        for (i, wgt) in weights.iter().enumerate() {
            running += wgt;
            // A black row is never chosen; a uniform CDF keeps the search well defined anyway.
            conditional[j * w + i] = if *row > 0.0 {
                (running / *row) as f32
            } else {
                (i + 1) as f32 / w as f32
            };
        }
        conditional[j * w + w - 1] = 1.0;
    }
    let total: f64 = rows.iter().sum();
    if total <= 0.0 {
        return empty(ctx); // an all-black map lights nothing
    }
    let mut running = 0.0;
    let mut marginal: Vec<f32> = rows
        .iter()
        .map(|r| {
            running += r / total;
            running as f32
        })
        .collect();
    marginal[h - 1] = 1.0;
    let pdf_scale = ((w * h) as f64 / (2.0 * std::f64::consts::PI.powi(2) * total)) as f32;
    Ok(EnvMap {
        pixels: upload(ctx, &pixels)?,
        marginal: upload(ctx, &marginal)?,
        conditional: upload(ctx, &conditional)?,
        width: w as u32,
        height: h as u32,
        pdf_scale,
    })
}

/// Box-filtered mip chain of `image`, level 0 first. Returns the texels (rgb) and the level count.
fn mip_chain(image: &Image) -> (Vec<f32>, u32) {
    let (mut w, mut h) = (image.width() as usize, image.height() as usize);
    let mut level = image.pixels().to_vec();
    let mut texels = Vec::new();
    let mut levels = 0;
    loop {
        texels.extend(level.iter().flatten());
        levels += 1;
        if w == 1 && h == 1 {
            return (texels, levels);
        }
        let (nw, nh) = ((w / 2).max(1), (h / 2).max(1));
        let mut next = Vec::with_capacity(nw * nh);
        for y in 0..nh {
            for x in 0..nw {
                let mut sum = [0.0f32; 3];
                for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                    let p = level[(2 * y + dy).min(h - 1) * w + (2 * x + dx).min(w - 1)];
                    sum.iter_mut().zip(p).for_each(|(s, v)| *s += v);
                }
                next.push(sum.map(|s| s / 4.0));
            }
        }
        (level, w, h) = (next, nw, nh);
    }
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
    env: EnvMap,
    uvs: Obj<dyn MTLBuffer>,
    vnormals: Obj<dyn MTLBuffer>,
    texels: Obj<dyn MTLBuffer>,
    tex_info: Obj<dyn MTLBuffer>,
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
        let mut uvs: Vec<f32> = Vec::new();
        let mut vnormals: Vec<f32> = Vec::new();
        let mut blases = Vec::new();
        let mut offsets = Vec::new(); // (vertex offset, index offset) per mesh
        for mesh in scene.meshes() {
            offsets.push(((positions.len() / 3) as u32, indices.len() as u32));
            positions.extend(mesh.positions().iter().flatten());
            match mesh.uvs() {
                Some(uv) => uvs.extend(uv.iter().flatten()),
                None => uvs.extend(std::iter::repeat_n(0.0, mesh.positions().len() * 2)),
            }
            match mesh.normals() {
                Some(n) => vnormals.extend(n.iter().flatten()),
                None => vnormals.extend(std::iter::repeat_n(0.0, mesh.positions().len() * 3)),
            }
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
            // A textured emitter has no constant radiance to sample, so only BSDF sampling finds it.
            let textured = scene.materials()[inst.material.index()]
                .base
                .emission_texture
                .is_some();
            if radiance > 0.0 && !textured {
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

        // Every referenced image becomes one texture with a full mip chain.
        let mut texture_of: HashMap<usize, u32> = HashMap::new();
        let mut texels: Vec<f32> = Vec::new();
        let mut tex_info: Vec<u32> = Vec::new();
        let mut texture = |id: Option<verion_scene::ImageId>| -> Result<f32, Error> {
            let Some(id) = id else { return Ok(0.0) };
            let slot = match texture_of.get(&id.index()) {
                Some(&slot) => slot,
                None => {
                    let image = scene
                        .images()
                        .get(id.index())
                        .ok_or_else(|| Error::Scene("material refers to a missing image".into()))?;
                    let (chain, levels) = mip_chain(image);
                    let slot = texture_of.len() as u32;
                    tex_info.extend([
                        (texels.len() / 3) as u32,
                        image.width(),
                        image.height(),
                        levels,
                    ]);
                    texels.extend(chain);
                    texture_of.insert(id.index(), slot);
                    slot
                }
            };
            Ok(slot as f32 + 1.0)
        };
        let mut materials = Vec::with_capacity(scene.materials().len() * MATERIAL_WORDS);
        for m in scene.materials() {
            let b = &m.base;
            let (c, e) = (b.base_color, b.emission);
            let tex = [
                texture(b.base_color_texture)?,
                texture(b.metallic_roughness_texture)?,
                texture(b.emission_texture)?,
            ];
            let normal_texture = texture(b.normal_texture)?;
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
                tex[0],
                tex[1],
                tex[2],
                normal_texture,
                b.normal_scale,
                0.0,
            ]);
        }

        // Environment lights are summed into one uniform sky; the rest go to the NEE table.
        let mut sky = [0.0f32; 3];
        let mut lights = Vec::new();
        for light in scene.lights() {
            let mut cone = [0.0f32; 4]; // axis xyz and the angular falloff scale, for spot lights
            let mut offset = 0.0;
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
                Light::Spot {
                    position,
                    direction,
                    color,
                    intensity,
                    inner_cone,
                    outer_cone,
                } => {
                    let len = direction.iter().map(|c| c * c).sum::<f32>().sqrt();
                    let axis = direction.map(|c| c / len);
                    // glTF falloff: saturate(cos * scale + offset), squared in the shader.
                    let scale = 1.0 / (inner_cone.cos() - outer_cone.cos()).max(1.0e-3);
                    cone = [axis[0], axis[1], axis[2], scale];
                    offset = -outer_cone.cos() * scale;
                    (2, color, intensity, position)
                }
                Light::EnvironmentMap { .. } => continue, // see `build_env`
                Light::Environment { color } => {
                    sky.iter_mut().zip(color).for_each(|(s, c)| *s += c);
                    continue;
                }
            };
            let words: [u32; LIGHT_WORDS] = std::array::from_fn(|i| match i {
                0 => kind,
                1..=3 => color[i - 1].to_bits(),
                4 => intensity.to_bits(),
                5..=7 => vector[i - 5].to_bits(),
                8..=11 => cone[i - 8].to_bits(),
                12 => offset.to_bits(),
                _ => 0,
            });
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
            env: build_env(ctx, scene)?,
            uvs: upload(ctx, &uvs)?,
            vnormals: upload(ctx, &vnormals)?,
            texels: upload(ctx, &texels)?,
            tex_info: upload(ctx, &tex_info)?,
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
        let mut params = [0u32; 28];
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
        params[24] = self.env.width;
        params[25] = self.env.height;
        params[26] = self.env.pdf_scale.to_bits();
        // Footprint of one pixel per unit of travelled distance, for texture filtering.
        params[27] = (2.0 * self.camera[2] / acc.height as f32).to_bits();

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
        // indices, instances, materials, lights, params, accum, emitters, emit_cdf, env pixels, marginal, conditional, uvs, texels, texInfo, vnormals). Dispatches in one encoder run in
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
