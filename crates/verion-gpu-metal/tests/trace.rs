//! Needs a Metal RT device; skips on machines without one (e.g. CI runners).
#![cfg(target_os = "macos")]

use objc2::runtime::ProtocolObject;
use objc2_foundation::NSString;
use objc2_metal::*;
use verion_gpu_metal::{Blas, Error, Instance, MetalContext, Tlas};

const KERNEL: &str = r#"
#include <metal_stdlib>
using namespace metal;
using namespace metal::raytracing;

kernel void trace(
    acceleration_structure<instancing> scene [[buffer(0)]],
    device const float* xs [[buffer(1)]],
    device float* out [[buffer(2)]],
    uint i [[thread_position_in_grid]])
{
    intersector<triangle_data, instancing> isect;
    ray r(float3(xs[i], 0.25, -1.0), float3(0.0, 0.0, 1.0), 0.0, 100.0);
    auto hit = isect.intersect(r, scene);
    out[i] = hit.type == intersection_type::triangle ? hit.distance : -1.0;
}
"#;

fn context() -> Option<MetalContext> {
    match MetalContext::new() {
        Ok(ctx) => Some(ctx),
        Err(e @ (Error::NoDevice | Error::RaytracingUnsupported { .. })) => {
            eprintln!("skipped: {e}");
            None
        }
        Err(e) => panic!("{e}"),
    }
}

/// Fires one +z ray per `xs` entry at y = 0.25 and returns the hit distances (-1 = miss).
fn trace(ctx: &MetalContext, tlas: &Tlas, xs: &[f32]) -> Vec<f32> {
    let dev = ctx.device();
    let lib = dev
        .newLibraryWithSource_options_error(&NSString::from_str(KERNEL), None)
        .unwrap_or_else(|e| panic!("MSL compile failed: {e}"));
    let func = lib
        .newFunctionWithName(&NSString::from_str("trace"))
        .expect("trace function");
    let pso = dev
        .newComputePipelineStateWithFunction_error(&func)
        .expect("pipeline");

    let opts = MTLResourceOptions::StorageModeShared;
    let xs_buf = unsafe {
        dev.newBufferWithBytes_length_options(
            std::ptr::NonNull::new(xs.as_ptr().cast_mut().cast()).unwrap(),
            size_of_val(xs),
            opts,
        )
    }
    .expect("xs buffer");
    let out = dev
        .newBufferWithLength_options(size_of_val(xs), opts)
        .expect("out buffer");

    let cb = ctx.queue().commandBuffer().expect("command buffer");
    let enc = cb.computeCommandEncoder().expect("encoder");
    enc.setComputePipelineState(&pso);
    for blas in tlas.blases() {
        enc.useResource_usage(ProtocolObject::from_ref(&**blas), MTLResourceUsage::Read);
    }
    unsafe {
        enc.setAccelerationStructure_atBufferIndex(Some(tlas.raw()), 0);
        enc.setBuffer_offset_atIndex(Some(&xs_buf), 0, 1);
        enc.setBuffer_offset_atIndex(Some(&out), 0, 2);
    }
    enc.dispatchThreads_threadsPerThreadgroup(
        MTLSize {
            width: xs.len(),
            height: 1,
            depth: 1,
        },
        MTLSize {
            width: xs.len(),
            height: 1,
            depth: 1,
        },
    );
    enc.endEncoding();
    cb.commit();
    cb.waitUntilCompleted();

    let ptr = out.contents().as_ptr().cast::<f32>();
    (0..xs.len()).map(|i| unsafe { *ptr.add(i) }).collect()
}

#[test]
fn two_instances_of_one_triangle() {
    let Some(ctx) = context() else { return };
    // Right triangle covering x + y <= 1 in the z = 0 plane.
    let blas = Blas::build(
        &ctx,
        &[[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]],
        &[0, 1, 2],
    )
    .unwrap();
    let mut shifted = Instance::IDENTITY;
    shifted[0][3] = 2.0;
    let instances = [
        Instance {
            blas: 0,
            transform: Instance::IDENTITY,
        },
        Instance {
            blas: 0,
            transform: shifted,
        },
    ];
    let tlas = Tlas::build(&ctx, &[&blas], &instances).unwrap();

    // Hit the original, hit the shifted copy, miss in the gap between them.
    assert_eq!(trace(&ctx, &tlas, &[0.25, 2.25, 1.5]), [1.0, 1.0, -1.0]);
}

#[test]
fn invalid_input_is_rejected_before_the_gpu() {
    let Some(ctx) = context() else { return };
    let tri = [[0.0; 3]; 3];
    assert!(Blas::build(&ctx, &tri, &[]).is_err());
    assert!(Blas::build(&ctx, &tri, &[0, 1]).is_err());
    assert!(Blas::build(&ctx, &tri, &[0, 1, 3]).is_err());
    let blas = Blas::build(&ctx, &tri, &[0, 1, 2]).unwrap();
    assert!(Tlas::build(&ctx, &[&blas], &[]).is_err());
    assert!(
        Tlas::build(
            &ctx,
            &[&blas],
            &[Instance {
                blas: 1,
                transform: Instance::IDENTITY
            }]
        )
        .is_err()
    );
}

#[test]
fn oversized_scene_reports_out_of_memory() {
    let Ok(ctx) = MetalContext::new() else {
        return;
    };
    // Twice the working set can never fit; the check runs before any allocation.
    let huge = ctx.device().recommendedMaxWorkingSetSize() as usize * 2;
    let err = ctx.check_fits(huge).unwrap_err();
    assert!(matches!(err, Error::OutOfMemory { .. }), "{err}");
    assert!(err.to_string().contains("GPU memory"));
}
