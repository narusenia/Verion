//! M1 item 1 spike: run a Slang-generated MSL ray query against one triangle.
//! Usage: verion-spike-rt <path-to-intersect.metal>

use std::{ffi::c_void, ptr::NonNull};

use objc2::{rc::Retained, runtime::ProtocolObject};
use objc2_foundation::{NSArray, NSString};
use objc2_metal::*;

type Obj<T> = Retained<ProtocolObject<T>>;

fn buf<T: Copy>(dev: &Obj<dyn MTLDevice>, data: &[T]) -> Obj<dyn MTLBuffer> {
    let ptr = NonNull::new(data.as_ptr() as *mut c_void).unwrap();
    unsafe {
        dev.newBufferWithBytes_length_options(
            ptr,
            size_of_val(data),
            MTLResourceOptions::StorageModeShared,
        )
    }
    .expect("buffer")
}

/// Build an acceleration structure on the GPU and wait for completion.
fn build(
    dev: &Obj<dyn MTLDevice>,
    queue: &Obj<dyn MTLCommandQueue>,
    desc: &MTLAccelerationStructureDescriptor,
) -> Obj<dyn MTLAccelerationStructure> {
    let sizes = dev.accelerationStructureSizesWithDescriptor(desc);
    let accel = dev
        .newAccelerationStructureWithSize(sizes.accelerationStructureSize)
        .expect("accel");
    let scratch = dev
        .newBufferWithLength_options(
            sizes.buildScratchBufferSize,
            MTLResourceOptions::StorageModePrivate,
        )
        .expect("scratch");
    let cb = queue.commandBuffer().expect("cb");
    let enc = cb.accelerationStructureCommandEncoder().expect("enc");
    enc.buildAccelerationStructure_descriptor_scratchBuffer_scratchBufferOffset(
        &accel, desc, &scratch, 0,
    );
    enc.endEncoding();
    cb.commit();
    cb.waitUntilCompleted();
    accel
}

fn main() {
    let path = std::env::args()
        .nth(1)
        .expect("usage: verion-spike-rt <intersect.metal>");
    let src = std::fs::read_to_string(&path).expect("read msl");

    let dev = MTLCreateSystemDefaultDevice().expect("no Metal device");
    assert!(dev.supportsRaytracing(), "device lacks Metal RT");
    let queue = dev.newCommandQueue().expect("queue");

    // One triangle in the z = 0 plane; the shader fires a ray at (0.25, 0.25) along +z from z = -1.
    let verts: [f32; 9] = [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0];
    let vbuf = buf(&dev, &verts);
    let tri = MTLAccelerationStructureTriangleGeometryDescriptor::descriptor();
    tri.setVertexBuffer(Some(&vbuf));
    tri.setVertexStride(12);
    tri.setTriangleCount(1);
    let blas_desc = MTLPrimitiveAccelerationStructureDescriptor::descriptor();
    blas_desc.setGeometryDescriptors(Some(&NSArray::from_retained_slice(&[
        Retained::into_super(tri),
    ])));
    let blas = build(&dev, &queue, &blas_desc);

    // Identity transform, one instance of the BLAS.
    let col = |x, y, z| MTLPackedFloat3 { x, y, z };
    let inst = MTLAccelerationStructureInstanceDescriptor {
        transformationMatrix: MTLPackedFloat4x3 {
            columns: [
                col(1.0, 0.0, 0.0),
                col(0.0, 1.0, 0.0),
                col(0.0, 0.0, 1.0),
                col(0.0, 0.0, 0.0),
            ],
        },
        options: MTLAccelerationStructureInstanceOptions::Opaque,
        mask: 0xFF,
        intersectionFunctionTableOffset: 0,
        accelerationStructureIndex: 0,
    };
    let ibuf = buf(&dev, &[inst]);
    let tlas_desc = MTLInstanceAccelerationStructureDescriptor::descriptor();
    tlas_desc.setInstanceDescriptorBuffer(Some(&ibuf));
    tlas_desc.setInstanceCount(1);
    tlas_desc.setInstancedAccelerationStructures(Some(&NSArray::from_slice(&[&*blas])));
    let tlas = build(&dev, &queue, &tlas_desc);

    // Slang renamed `main` to `main_0` in the generated MSL.
    let lib = dev
        .newLibraryWithSource_options_error(&NSString::from_str(&src), None)
        .unwrap_or_else(|e| panic!("MSL compile failed: {e}"));
    let func = lib
        .newFunctionWithName(&NSString::from_str("main_0"))
        .expect("main_0");
    let pso = dev
        .newComputePipelineStateWithFunction_error(&func)
        .expect("pso");

    let out = dev
        .newBufferWithLength_options(4, MTLResourceOptions::StorageModeShared)
        .expect("out");
    let cb = queue.commandBuffer().expect("cb");
    let enc = cb.computeCommandEncoder().expect("enc");
    enc.setComputePipelineState(&pso);
    enc.useResource_usage(ProtocolObject::from_ref(&*blas), MTLResourceUsage::Read);
    enc.useResource_usage(ProtocolObject::from_ref(&*tlas), MTLResourceUsage::Read);
    unsafe {
        enc.setAccelerationStructure_atBufferIndex(Some(&tlas), 0);
        enc.setBuffer_offset_atIndex(Some(&out), 0, 1);
    }
    enc.dispatchThreadgroups_threadsPerThreadgroup(
        MTLSize {
            width: 1,
            height: 1,
            depth: 1,
        },
        MTLSize {
            width: 1,
            height: 1,
            depth: 1,
        },
    );
    enc.endEncoding();
    cb.commit();
    cb.waitUntilCompleted();

    let t = unsafe { *(out.contents().as_ptr() as *const f32) };
    println!("hitT = {t}");
    assert!((t - 1.0).abs() < 1e-5, "expected t = 1.0");
}
