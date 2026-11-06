//! Compute pipelines whose descriptor set layout comes from the shader's own SPIR-V, and the
//! descriptor sets that bind buffers to them.

use ash::vk;

use crate::{
    Error, VulkanContext,
    buffer::Buffer,
    reflect::{self, Binding, Kind},
};

/// Binding of the parameter block in the path tracer's kernels. It is a dynamic storage buffer:
/// every dispatch of one command buffer reads its own slice, so a whole accumulation is recorded
/// at once (Metal re-sends the block with `setBytes`).
pub const PARAMS_BINDING: u32 = 6;

pub struct Pipeline {
    ctx: VulkanContext,
    pub bindings: Vec<Binding>,
    dynamic: Option<u32>,
    set_layout: vk::DescriptorSetLayout,
    pub layout: vk::PipelineLayout,
    pub raw: vk::Pipeline,
}

impl Pipeline {
    /// `dynamic` names the binding read through a dynamic offset, if any. `restir` is the
    /// specialization constant `restirCompiled` (id 0) of `pt_core.slang`; kernels without it ignore it.
    pub fn new(
        ctx: &VulkanContext,
        name: &str,
        spv: &[u8],
        dynamic: Option<u32>,
        restir: bool,
    ) -> Result<Self, Error> {
        let bindings = reflect::bindings(spv).map_err(|e| Error::Shader(format!("{name}: {e}")))?;
        let words = reflect::words(spv);
        let d = &ctx.0.device;
        let layout_bindings: Vec<_> = bindings
            .iter()
            .map(|b| {
                vk::DescriptorSetLayoutBinding::default()
                    .binding(b.binding)
                    .descriptor_count(1)
                    .stage_flags(vk::ShaderStageFlags::COMPUTE)
                    .descriptor_type(descriptor_type(*b, dynamic))
            })
            .collect();
        // SAFETY: every object is destroyed in `drop` or on the error paths below.
        unsafe {
            let set_layout = d.create_descriptor_set_layout(
                &vk::DescriptorSetLayoutCreateInfo::default().bindings(&layout_bindings),
                None,
            )?;
            let sets = [set_layout];
            let layout = d
                .create_pipeline_layout(
                    &vk::PipelineLayoutCreateInfo::default().set_layouts(&sets),
                    None,
                )
                .inspect_err(|_| d.destroy_descriptor_set_layout(set_layout, None))?;
            let module = d
                .create_shader_module(&vk::ShaderModuleCreateInfo::default().code(&words), None)
                .inspect_err(|_| {
                    d.destroy_pipeline_layout(layout, None);
                    d.destroy_descriptor_set_layout(set_layout, None);
                })?;
            let entries = [vk::SpecializationMapEntry::default()
                .constant_id(0)
                .offset(0)
                .size(4)];
            let data = u32::from(restir).to_ne_bytes();
            let spec = vk::SpecializationInfo::default()
                .map_entries(&entries)
                .data(&data);
            let stage = vk::PipelineShaderStageCreateInfo::default()
                .stage(vk::ShaderStageFlags::COMPUTE)
                .module(module)
                .name(c"main")
                .specialization_info(&spec);
            let made = d.create_compute_pipelines(
                vk::PipelineCache::null(),
                &[vk::ComputePipelineCreateInfo::default()
                    .stage(stage)
                    .layout(layout)],
                None,
            );
            d.destroy_shader_module(module, None);
            match made {
                Ok(p) => Ok(Self {
                    ctx: ctx.clone(),
                    bindings,
                    dynamic,
                    set_layout,
                    layout,
                    raw: p[0],
                }),
                Err((_, e)) => {
                    d.destroy_pipeline_layout(layout, None);
                    d.destroy_descriptor_set_layout(set_layout, None);
                    Err(Error::Shader(format!("{name}: {e}")))
                }
            }
        }
    }
}

fn descriptor_type(b: Binding, dynamic: Option<u32>) -> vk::DescriptorType {
    match b.kind {
        Kind::AccelerationStructure => vk::DescriptorType::ACCELERATION_STRUCTURE_KHR,
        Kind::StorageBuffer if dynamic == Some(b.binding) => {
            vk::DescriptorType::STORAGE_BUFFER_DYNAMIC
        }
        Kind::StorageBuffer => vk::DescriptorType::STORAGE_BUFFER,
    }
}

impl Drop for Pipeline {
    fn drop(&mut self) {
        let d = &self.ctx.0.device;
        // SAFETY: no submission using the pipeline is pending: they all wait.
        unsafe {
            d.destroy_pipeline(self.raw, None);
            d.destroy_pipeline_layout(self.layout, None);
            d.destroy_descriptor_set_layout(self.set_layout, None);
        }
    }
}

/// What a binding points at.
#[derive(Clone, Copy)]
pub enum Res<'a> {
    Accel(vk::AccelerationStructureKHR),
    Buffer(&'a Buffer),
    /// The first `range` bytes of a buffer (the dynamic parameter block).
    Slice(&'a Buffer, u64),
}

/// A pool whose sets live as long as one batch of work; dropping it frees them all.
pub struct Descriptors {
    ctx: VulkanContext,
    pool: vk::DescriptorPool,
}

impl Descriptors {
    pub fn new(ctx: &VulkanContext, max_sets: u32) -> Result<Self, Error> {
        let per = |ty, n| vk::DescriptorPoolSize::default().ty(ty).descriptor_count(n);
        let sizes = [
            per(vk::DescriptorType::STORAGE_BUFFER, max_sets * 32),
            per(vk::DescriptorType::STORAGE_BUFFER_DYNAMIC, max_sets),
            per(vk::DescriptorType::ACCELERATION_STRUCTURE_KHR, max_sets),
        ];
        // SAFETY: destroyed in `drop`.
        let pool = unsafe {
            ctx.0.device.create_descriptor_pool(
                &vk::DescriptorPoolCreateInfo::default()
                    .max_sets(max_sets)
                    .pool_sizes(&sizes),
                None,
            )?
        };
        Ok(Self {
            ctx: ctx.clone(),
            pool,
        })
    }

    /// A set for `pipeline` with each of its bindings pointed at the resource of the same number.
    /// Resources the shader does not declare are ignored; a declared binding without one is an error.
    pub fn set(
        &self,
        pipeline: &Pipeline,
        resources: &[(u32, Res<'_>)],
    ) -> Result<vk::DescriptorSet, Error> {
        let d = &self.ctx.0.device;
        let layouts = [pipeline.set_layout];
        // SAFETY: the pool and layout are alive; the infos live through each update call.
        unsafe {
            let set = d.allocate_descriptor_sets(
                &vk::DescriptorSetAllocateInfo::default()
                    .descriptor_pool(self.pool)
                    .set_layouts(&layouts),
            )?[0];
            for b in &pipeline.bindings {
                let res = resources
                    .iter()
                    .find(|(n, _)| *n == b.binding)
                    .ok_or_else(|| Error::Shader(format!("binding {} has no resource", b.binding)))?
                    .1;
                let write = vk::WriteDescriptorSet::default()
                    .dst_set(set)
                    .dst_binding(b.binding)
                    .descriptor_type(descriptor_type(*b, pipeline.dynamic));
                match res {
                    Res::Accel(handle) => {
                        let handles = [handle];
                        let mut info = vk::WriteDescriptorSetAccelerationStructureKHR::default()
                            .acceleration_structures(&handles);
                        let mut write = write.push_next(&mut info);
                        write.descriptor_count = 1;
                        d.update_descriptor_sets(&[write], &[]);
                    }
                    Res::Buffer(buf) | Res::Slice(buf, _) => {
                        let range = match res {
                            Res::Slice(_, r) => r,
                            _ => vk::WHOLE_SIZE,
                        };
                        let info = [vk::DescriptorBufferInfo {
                            buffer: buf.raw,
                            offset: 0,
                            range,
                        }];
                        d.update_descriptor_sets(&[write.buffer_info(&info)], &[]);
                    }
                }
            }
            Ok(set)
        }
    }
}

impl Drop for Descriptors {
    fn drop(&mut self) {
        // SAFETY: the sets are no longer in use: submissions wait before this drops.
        unsafe { self.ctx.0.device.destroy_descriptor_pool(self.pool, None) };
    }
}
