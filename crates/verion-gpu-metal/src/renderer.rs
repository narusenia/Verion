//! Uploads a Scene IR snapshot and renders AOVs with the Slang-generated kernels.

use std::{ffi::c_void, ptr::NonNull};

use objc2::runtime::ProtocolObject;
use objc2_foundation::NSString;
use objc2_metal::{
    MTLBuffer, MTLCommandBuffer, MTLCommandEncoder, MTLCommandQueue, MTLComputeCommandEncoder,
    MTLComputePipelineState, MTLDevice, MTLLibrary, MTLResourceOptions, MTLResourceUsage, MTLSize,
};
use verion_scene::Scene;

use crate::{Blas, Error, Instance, MetalContext, Obj, Tlas};

const NORMALS_MSL: &str = include_str!("../shaders/normals.metal");

/// Words per record in the instance table; must match `shaders/normals.slang`.
const INSTANCE_WORDS: usize = 16;

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

/// A scene snapshot ready to trace. Later scene edits are not reflected.
pub struct Renderer {
    ctx: MetalContext,
    tlas: Tlas,
    _blases: Vec<Blas>,
    positions: Obj<dyn MTLBuffer>,
    indices: Obj<dyn MTLBuffer>,
    instances: Obj<dyn MTLBuffer>,
    camera: [f32; 16],
    normals: Obj<dyn MTLComputePipelineState>,
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
        for (record, inst) in table.chunks_mut(INSTANCE_WORDS).zip(scene.instances()) {
            let (vertex_offset, index_offset) = offsets[inst.mesh.index()];
            record[0] = vertex_offset;
            record[1] = index_offset;
            for (word, v) in record[4..].iter_mut().zip(inst.transform.iter().flatten()) {
                *word = v.to_bits();
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

        let lib = ctx
            .device
            .newLibraryWithSource_options_error(&NSString::from_str(NORMALS_MSL), None)
            .map_err(|e| Error::Shader(e.to_string()))?;
        let func = lib
            .newFunctionWithName(&NSString::from_str("normals"))
            .ok_or_else(|| Error::Shader("entry point `normals` not found".into()))?;
        let normals = ctx
            .device
            .newComputePipelineStateWithFunction_error(&func)
            .map_err(|e| Error::Shader(e.to_string()))?;

        Ok(Self {
            ctx: ctx.clone(),
            positions: upload(ctx, &positions)?,
            indices: upload(ctx, &indices)?,
            instances: upload(ctx, &table)?,
            tlas,
            _blases: blases,
            camera,
            normals,
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
