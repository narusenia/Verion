//! The wavefront's pipelines and GPU-only buffers (REQ-GPU-005). The stage loop itself is in
//! `renderer.rs`, where it shares the recording code with the megakernel.

use ash::vk;
use verion_gpu::wavefront::Sizes;

use crate::{
    Error, VulkanContext,
    buffer::Buffer,
    pipeline::{PARAMS_BINDING, Pipeline},
};

pub struct Pipelines {
    pub select: Pipeline,
    pub args: Pipeline,
    pub extend: Pipeline,
    pub shade: Pipeline,
}

impl Pipelines {
    pub fn new(ctx: &VulkanContext, restir: bool) -> Result<Self, Error> {
        let make = |name: &str| {
            Pipeline::new(
                ctx,
                name,
                crate::shaders::spirv(name),
                Some(PARAMS_BINDING),
                restir,
            )
        };
        Ok(Self {
            select: make("wf_select")?,
            args: make("wf_args")?,
            extend: make("wf_extend")?,
            shade: make("wf_shade")?,
        })
    }
}

/// GPU-only buffers of one accumulation's wavefront.
pub struct Buffers {
    pub state: Buffer,
    pub hits: Buffer,
    pub queues: [Buffer; 2],
    pub counts: Buffer,
    pub args: Buffer,
    bytes: usize,
}

impl Buffers {
    pub fn new(ctx: &VulkanContext, paths: usize, lighting: bool) -> Result<Self, Error> {
        let sizes = Sizes::new(paths, lighting);
        let storage = vk::BufferUsageFlags::STORAGE_BUFFER;
        let zeroed = |bytes: usize, usage| ctx.zeroed(bytes as u64, usage, "wavefront buffer");
        Ok(Self {
            state: zeroed(sizes.state, storage)?,
            hits: zeroed(sizes.hits, storage)?,
            queues: [zeroed(sizes.queue, storage)?, zeroed(sizes.queue, storage)?],
            counts: zeroed(sizes.counts, storage)?,
            args: zeroed(sizes.args, storage | vk::BufferUsageFlags::INDIRECT_BUFFER)?,
            bytes: sizes.total(),
        })
    }

    /// Bytes of GPU memory, for the metrics.
    pub fn bytes(&self) -> usize {
        self.bytes
    }
}
