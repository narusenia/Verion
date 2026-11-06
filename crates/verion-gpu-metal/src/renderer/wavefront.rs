//! Wavefront path tracing (REQ-GPU-005): the megakernel's bounce loop split into extend (closest
//! hit) and shade kernels that pass paths through queues in GPU memory. Shade appends the
//! paths that live on to the next depth's queue with an atomic counter (compaction), and indirect
//! dispatches size each stage from that counter, so the CPU never waits between bounces.
//! The kernels run the same path code as the megakernel (`shaders/include/pt_core.slang`). Depth 0
//! keeps no path state: both kernels generate the camera path again from the pixel, which costs
//! less than writing and reading it.

use objc2_metal::{
    MTLBuffer, MTLCommandBuffer, MTLCommandEncoder, MTLComputeCommandEncoder,
    MTLComputePipelineState, MTLDevice, MTLResourceOptions, MTLSize,
};

use verion_gpu::{
    pack::{MAX_DEPTH, PARAM_WORDS},
    wavefront::{GROUP, Sizes},
};

use super::{Accumulation, CommandBuffer, Encoder, Obj, Renderer, pipeline};
use crate::{Error, MetalContext};

const ARGS_MSL: &str = include_str!("../../shaders/wf_args.metal");
const EXTEND_MSL: &str = include_str!("../../shaders/wf_extend.metal");
const SHADE_MSL: &str = include_str!("../../shaders/wf_shade.metal");
const SELECT_MSL: &str = include_str!("../../shaders/wf_select.metal");

pub(super) struct Pipelines {
    args: Obj<dyn MTLComputePipelineState>,
    extend: Obj<dyn MTLComputePipelineState>,
    shade: Obj<dyn MTLComputePipelineState>,
    select: Obj<dyn MTLComputePipelineState>,
}

impl Pipelines {
    pub(super) fn new(ctx: &MetalContext) -> Result<Self, Error> {
        Ok(Self {
            args: pipeline(ctx, ARGS_MSL, "wf_args")?,
            extend: pipeline(ctx, EXTEND_MSL, "wf_extend")?,
            shade: pipeline(ctx, SHADE_MSL, "wf_shade")?,
            select: pipeline(ctx, SELECT_MSL, "wf_select")?,
        })
    }
}

/// GPU-only buffers of one accumulation's wavefront.
pub(super) struct Buffers {
    state: Obj<dyn MTLBuffer>,
    hits: Obj<dyn MTLBuffer>,
    queues: [Obj<dyn MTLBuffer>; 2],
    counts: Obj<dyn MTLBuffer>,
    args: Obj<dyn MTLBuffer>,
}

impl Buffers {
    pub(super) fn new(ctx: &MetalContext, paths: usize, lighting: bool) -> Result<Self, Error> {
        let sizes = Sizes::new(paths, lighting);
        let private = |bytes: usize| -> Result<Obj<dyn MTLBuffer>, Error> {
            ctx.check_fits(bytes)?;
            ctx.device
                .newBufferWithLength_options(bytes.max(4), MTLResourceOptions::StorageModePrivate)
                .ok_or(Error::Resource("wavefront buffer"))
        };
        Ok(Self {
            state: private(sizes.state)?,
            hits: private(sizes.hits)?,
            queues: [private(sizes.queue)?, private(sizes.queue)?],
            counts: private(sizes.counts)?,
            args: private(sizes.args)?,
        })
    }

    /// Bytes of GPU memory, for the metrics.
    pub(super) fn bytes(&self) -> usize {
        [
            &self.state,
            &self.hits,
            &self.queues[0],
            &self.queues[1],
            &self.counts,
            &self.args,
        ]
        .iter()
        .map(|b| b.length())
        .sum()
    }
}

impl Renderer {
    /// Runs `samples` wavefront samples into `acc` and waits for the GPU. `params` is the
    /// megakernel's parameter block; words 6, 30 and 31 are filled here. With stage timing on,
    /// every dispatch gets its own command buffer, so their GPU times split extend from shade
    /// (the extra submissions make the total slower; use it to compare stages, not for speed).
    pub(super) fn run_wavefront(
        &self,
        acc: &mut Accumulation,
        params: &mut [u32; PARAM_WORDS],
        samples: u32,
    ) -> Result<(), Error> {
        let p = self.wavefront.get_or_init(|| Pipelines::new(&self.ctx));
        let p = p.as_ref().map_err(Clone::clone)?;
        let timed = self.stage_timing;
        let (w, h) = (acc.width as usize, acc.height as usize);
        params[31] = (w * h) as u32;
        // (stage, command buffer) in submission order; stage 0 is extend (with its args), 1 shade.
        let mut done: Vec<(usize, CommandBuffer)> = Vec::new();
        let (mut cb, mut enc) = self.open_encoder(acc)?;
        let mut stage_of_cb = 0;
        let b = acc
            .wavefront
            .as_ref()
            .ok_or(Error::Resource("wavefront buffers"))?;
        for k in 0..samples {
            params[6] = acc.samples + k;
            for d in 0..MAX_DEPTH as usize {
                params[30] = d as u32;
                let select = (d == 0 && params[32] != 0).then_some((0, &p.select));
                let stages =
                    select
                        .into_iter()
                        .chain([(0, &p.args), (0, &p.extend), (1, &p.shade)]);
                for (n, (stage, pipe)) in stages.enumerate() {
                    if timed && !(k == 0 && d == 0 && n == 0) {
                        enc.endEncoding();
                        cb.commit();
                        done.push((stage_of_cb, cb));
                        (cb, enc) = self.open_encoder(acc)?;
                    }
                    stage_of_cb = stage;
                    bind(&enc, b, params, d);
                    enc.setComputePipelineState(pipe);
                    if pipe == &p.select {
                        // The depth-0 queue is what wf_select writes.
                        // SAFETY: binding 23 is `queueOut` in wf_state.slang.
                        unsafe { enc.setBuffer_offset_atIndex(Some(&b.queues[0]), 0, 23) };
                        enc.dispatchThreads_threadsPerThreadgroup(
                            MTLSize {
                                width: w,
                                height: h,
                                depth: 1,
                            },
                            MTLSize {
                                width: 8,
                                height: 8,
                                depth: 1,
                            },
                        );
                    } else if pipe == &p.args {
                        enc.dispatchThreads_threadsPerThreadgroup(size(1), size(1));
                    } else {
                        // SAFETY: `args` holds 3 words per depth, written by the args dispatch above.
                        unsafe {
                            enc.dispatchThreadgroupsWithIndirectBuffer_indirectBufferOffset_threadsPerThreadgroup(
                                &b.args,
                                12 * d,
                                size(GROUP as usize),
                            );
                        }
                    }
                }
            }
        }
        enc.endEncoding();
        cb.commit();
        cb.waitUntilCompleted();
        done.push((stage_of_cb, cb));
        for (stage, cb) in &done {
            let t = cb.GPUEndTime() - cb.GPUStartTime();
            acc.gpu_seconds += t;
            if timed {
                acc.stage_seconds.get_or_insert([0.0; 2])[*stage] += t;
            }
        }
        Ok(())
    }
}

fn size(n: usize) -> MTLSize {
    MTLSize {
        width: n,
        height: 1,
        depth: 1,
    }
}

/// Binds the wavefront buffers (`shaders/include/wf_state.slang`, 20..25), the queues of depth `d`
/// and the parameter block. Bindings stay with the encoder, so this is redone for each new one.
fn bind(enc: &Encoder, b: &Buffers, params: &[u32; PARAM_WORDS], d: usize) {
    // SAFETY: the indices match the slang declarations; `params` outlives the call and Metal copies it.
    unsafe {
        enc.setBuffer_offset_atIndex(Some(&b.state), 0, 20);
        enc.setBuffer_offset_atIndex(Some(&b.hits), 0, 21);
        enc.setBuffer_offset_atIndex(Some(&b.queues[d % 2]), 0, 22);
        enc.setBuffer_offset_atIndex(Some(&b.queues[(d + 1) % 2]), 0, 23);
        enc.setBuffer_offset_atIndex(Some(&b.counts), 0, 24);
        enc.setBuffer_offset_atIndex(Some(&b.args), 0, 25);
        enc.setBytes_length_atIndex(
            std::ptr::NonNull::from(params).cast(),
            size_of_val(params),
            6,
        );
    }
}
