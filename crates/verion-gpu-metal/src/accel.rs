//! Bottom- and top-level acceleration structures.

use std::{ffi::c_void, ptr::NonNull};

use objc2::{rc::Retained, runtime::ProtocolObject};
use objc2_foundation::NSArray;
use objc2_metal::{
    MTLAccelerationStructure, MTLAccelerationStructureCommandEncoder,
    MTLAccelerationStructureDescriptor, MTLAccelerationStructureInstanceDescriptor,
    MTLAccelerationStructureInstanceOptions, MTLAccelerationStructureTriangleGeometryDescriptor,
    MTLBuffer, MTLCommandBuffer, MTLCommandEncoder, MTLCommandQueue, MTLDevice, MTLIndexType,
    MTLInstanceAccelerationStructureDescriptor, MTLPackedFloat3, MTLPackedFloat4x3,
    MTLPrimitiveAccelerationStructureDescriptor, MTLResourceOptions,
};

use crate::{Error, MetalContext, Obj};

fn shared_buffer<T: Copy>(ctx: &MetalContext, data: &[T]) -> Result<Obj<dyn MTLBuffer>, Error> {
    let ptr = NonNull::new(data.as_ptr().cast_mut().cast::<c_void>())
        .ok_or(Error::Resource("empty buffer"))?;
    ctx.check_fits(size_of_val(data))?;
    ctx.note_upload(size_of_val(data));
    // SAFETY: `ptr` points to `size_of_val(data)` readable bytes; Metal copies them.
    unsafe {
        ctx.device.newBufferWithBytes_length_options(
            ptr,
            size_of_val(data),
            MTLResourceOptions::StorageModeShared,
        )
    }
    .ok_or(Error::Resource("buffer"))
}

/// Builds on the GPU and blocks until the structure is ready.
fn build(
    ctx: &MetalContext,
    desc: &MTLAccelerationStructureDescriptor,
) -> Result<Obj<dyn MTLAccelerationStructure>, Error> {
    let sizes = ctx.device.accelerationStructureSizesWithDescriptor(desc);
    let accel = ctx
        .device
        .newAccelerationStructureWithSize(sizes.accelerationStructureSize)
        .ok_or(Error::Resource("acceleration structure"))?;
    let scratch = ctx
        .device
        .newBufferWithLength_options(
            sizes.buildScratchBufferSize,
            MTLResourceOptions::StorageModePrivate,
        )
        .ok_or(Error::Resource("build scratch buffer"))?;
    let cb = ctx
        .queue
        .commandBuffer()
        .ok_or(Error::Resource("command buffer"))?;
    let enc = cb
        .accelerationStructureCommandEncoder()
        .ok_or(Error::Resource("acceleration structure encoder"))?;
    enc.buildAccelerationStructure_descriptor_scratchBuffer_scratchBufferOffset(
        &accel, desc, &scratch, 0,
    );
    enc.endEncoding();
    cb.commit();
    cb.waitUntilCompleted();
    Ok(accel)
}

/// Triangle mesh acceleration structure.
pub struct Blas(pub(crate) Obj<dyn MTLAccelerationStructure>);

impl Blas {
    /// `positions` are tightly packed `xyz` floats; `indices` are triangle vertex indices (a multiple of 3).
    pub fn build(
        ctx: &MetalContext,
        positions: &[[f32; 3]],
        indices: &[u32],
    ) -> Result<Self, Error> {
        if indices.is_empty() || !indices.len().is_multiple_of(3) {
            return Err(Error::Resource(
                "index count must be a non-zero multiple of 3",
            ));
        }
        if indices.iter().any(|&i| i as usize >= positions.len()) {
            return Err(Error::Resource("index out of range"));
        }
        let vertices = shared_buffer(ctx, positions)?;
        let index_buf = shared_buffer(ctx, indices)?;
        let tri = MTLAccelerationStructureTriangleGeometryDescriptor::descriptor();
        tri.setVertexBuffer(Some(&vertices));
        tri.setVertexStride(size_of::<[f32; 3]>());
        tri.setIndexBuffer(Some(&index_buf));
        tri.setIndexType(MTLIndexType::UInt32);
        tri.setTriangleCount(indices.len() / 3);
        let desc = MTLPrimitiveAccelerationStructureDescriptor::descriptor();
        desc.setGeometryDescriptors(Some(&NSArray::from_retained_slice(&[
            Retained::into_super(tri),
        ])));
        build(ctx, &desc).map(Self)
    }

    pub fn raw(&self) -> &ProtocolObject<dyn MTLAccelerationStructure> {
        &self.0
    }
}

/// One placed copy of a BLAS.
pub struct Instance {
    /// Index into the `blases` slice passed to [`Tlas::build`].
    pub blas: u32,
    /// Row-major 3x4 object-to-world transform.
    pub transform: [[f32; 4]; 3],
}

impl Instance {
    pub const IDENTITY: [[f32; 4]; 3] = [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0],
    ];
}

/// Instance-level acceleration structure; keeps its BLASes alive.
pub struct Tlas {
    accel: Obj<dyn MTLAccelerationStructure>,
    blases: Vec<Obj<dyn MTLAccelerationStructure>>,
}

impl Tlas {
    pub fn build(
        ctx: &MetalContext,
        blases: &[&Blas],
        instances: &[Instance],
    ) -> Result<Self, Error> {
        if instances.is_empty() {
            return Err(Error::Resource("no instances"));
        }
        if instances.iter().any(|i| i.blas as usize >= blases.len()) {
            return Err(Error::Resource("instance references a missing BLAS"));
        }
        let descs: Vec<_> = instances
            .iter()
            .map(|i| {
                let col = |c: usize| MTLPackedFloat3 {
                    x: i.transform[0][c],
                    y: i.transform[1][c],
                    z: i.transform[2][c],
                };
                MTLAccelerationStructureInstanceDescriptor {
                    transformationMatrix: MTLPackedFloat4x3 {
                        columns: [col(0), col(1), col(2), col(3)],
                    },
                    options: MTLAccelerationStructureInstanceOptions::Opaque,
                    mask: 0xFF,
                    intersectionFunctionTableOffset: 0,
                    accelerationStructureIndex: i.blas,
                }
            })
            .collect();
        let inst_buf = shared_buffer(ctx, &descs)?;
        let raw: Vec<Obj<dyn MTLAccelerationStructure>> =
            blases.iter().map(|b| b.0.clone()).collect();
        let desc = MTLInstanceAccelerationStructureDescriptor::descriptor();
        desc.setInstanceDescriptorBuffer(Some(&inst_buf));
        desc.setInstanceCount(instances.len());
        desc.setInstancedAccelerationStructures(Some(&NSArray::from_retained_slice(&raw)));
        let accel = build(ctx, &desc)?;
        Ok(Self { accel, blases: raw })
    }

    pub fn raw(&self) -> &ProtocolObject<dyn MTLAccelerationStructure> {
        &self.accel
    }

    /// BLASes that must be passed to `useResource` when tracing against this TLAS.
    pub fn blases(&self) -> &[Obj<dyn MTLAccelerationStructure>] {
        &self.blases
    }
}
