//! Compute pipelines whose descriptor set layout comes from the shader's own SPIR-V, and the
//! descriptor sets that bind buffers to them.

use ash::vk;
use gpu_allocator::MemoryLocation;

use crate::{
    Error, VulkanContext,
    buffer::Buffer,
    reflect::{self, Binding, Kind},
};

/// Binding of the parameter block in the path tracer's kernels. It is a dynamic storage buffer:
/// every dispatch of one command buffer reads its own slice, so a whole accumulation is recorded
/// at once (Metal re-sends the block with `setBytes`).
pub const PARAMS_BINDING: u32 = 6;

/// The shader binding table of a ray generation pipeline: only a ray generation record, since the
/// hit objects of shader execution reordering never invoke hit or miss shaders.
pub struct Sbt {
    _buffer: Buffer,
    pub raygen: vk::StridedDeviceAddressRegionKHR,
}

pub struct Pipeline {
    ctx: VulkanContext,
    pub bindings: Vec<Binding>,
    dynamic: Option<u32>,
    set_layout: vk::DescriptorSetLayout,
    pub layout: vk::PipelineLayout,
    pub raw: vk::Pipeline,
    /// Set for ray generation pipelines (`trace_rays`); compute pipelines use `dispatch`.
    pub sbt: Option<Sbt>,
}

fn align_up(v: u64, a: u64) -> u64 {
    v.div_ceil(a) * a
}

impl Pipeline {
    /// A compute pipeline. `dynamic` names the binding read through a dynamic offset, if any.
    pub fn compute(
        ctx: &VulkanContext,
        name: &str,
        spv: &[u8],
        dynamic: Option<u32>,
    ) -> Result<Self, Error> {
        Self::build(ctx, name, spv, dynamic, false)
    }

    /// A ray tracing pipeline with the shader as its only (ray generation) stage. Needs a device
    /// with `DeviceInfo::ser`.
    pub fn ray_gen(
        ctx: &VulkanContext,
        name: &str,
        spv: &[u8],
        dynamic: Option<u32>,
    ) -> Result<Self, Error> {
        Self::build(ctx, name, spv, dynamic, true)
    }

    fn build(
        ctx: &VulkanContext,
        name: &str,
        spv: &[u8],
        dynamic: Option<u32>,
        ray_gen: bool,
    ) -> Result<Self, Error> {
        let bindings = reflect::bindings(spv).map_err(|e| Error::Shader(format!("{name}: {e}")))?;
        let words = reflect::words(spv);
        let d = &ctx.0.device;
        let stage_kind = if ray_gen {
            vk::ShaderStageFlags::RAYGEN_KHR
        } else {
            vk::ShaderStageFlags::COMPUTE
        };
        let layout_bindings: Vec<_> = bindings
            .iter()
            .map(|b| {
                vk::DescriptorSetLayoutBinding::default()
                    .binding(b.binding)
                    .descriptor_count(1)
                    .stage_flags(stage_kind)
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
            let fail = |e: Error| {
                d.destroy_pipeline_layout(layout, None);
                d.destroy_descriptor_set_layout(set_layout, None);
                e
            };
            let module = d
                .create_shader_module(&vk::ShaderModuleCreateInfo::default().code(&words), None)
                .map_err(|e| fail(e.into()))?;
            let stage = vk::PipelineShaderStageCreateInfo::default()
                .stage(stage_kind)
                .module(module)
                .name(c"main");
            let made = if ray_gen {
                Self::create_ray_gen(ctx, stage, layout)
            } else {
                d.create_compute_pipelines(
                    vk::PipelineCache::null(),
                    &[vk::ComputePipelineCreateInfo::default()
                        .stage(stage)
                        .layout(layout)],
                    None,
                )
                .map(|p| (p[0], None))
                .map_err(|(_, e)| Error::Shader(format!("{name}: {e}")))
            };
            d.destroy_shader_module(module, None);
            let (raw, sbt) = made.map_err(fail)?;
            Ok(Self {
                ctx: ctx.clone(),
                bindings,
                dynamic,
                set_layout,
                layout,
                raw,
                sbt,
            })
        }
    }

    fn create_ray_gen(
        ctx: &VulkanContext,
        stage: vk::PipelineShaderStageCreateInfo<'_>,
        layout: vk::PipelineLayout,
    ) -> Result<(vk::Pipeline, Option<Sbt>), Error> {
        let rt = ctx
            .0
            .ray_tracing
            .as_ref()
            .ok_or(Error::Resource("ray tracing pipeline (device has no SER)"))?;
        let unused = vk::SHADER_UNUSED_KHR;
        let group = [vk::RayTracingShaderGroupCreateInfoKHR::default()
            .ty(vk::RayTracingShaderGroupTypeKHR::GENERAL)
            .general_shader(0)
            .closest_hit_shader(unused)
            .any_hit_shader(unused)
            .intersection_shader(unused)];
        let stages = [stage];
        // SAFETY: the create info and what it points to live through the calls; the pipeline is
        // destroyed in `drop`.
        unsafe {
            let raw = rt
                .create_ray_tracing_pipelines(
                    vk::DeferredOperationKHR::null(),
                    vk::PipelineCache::null(),
                    &[vk::RayTracingPipelineCreateInfoKHR::default()
                        .stages(&stages)
                        .groups(&group)
                        .max_pipeline_ray_recursion_depth(1)
                        .layout(layout)],
                    None,
                )
                .map_err(|(_, e)| Error::Vulkan(e))?[0];
            let info = &ctx.0.info;
            let handle = rt.get_ray_tracing_shader_group_handles(
                raw,
                0,
                1,
                info.shader_group_handle_size as usize,
            );
            let sbt = handle
                .map_err(Error::from)
                .and_then(|handle| Self::sbt(ctx, &handle));
            match sbt {
                Ok(sbt) => Ok((raw, Some(sbt))),
                Err(e) => {
                    ctx.0.device.destroy_pipeline(raw, None);
                    Err(e)
                }
            }
        }
    }

    fn sbt(ctx: &VulkanContext, handle: &[u8]) -> Result<Sbt, Error> {
        let align = u64::from(ctx.0.info.shader_group_base_alignment);
        let stride = align_up(handle.len() as u64, align);
        let mut buffer = Buffer::new(
            ctx,
            stride + align,
            vk::BufferUsageFlags::SHADER_BINDING_TABLE_KHR,
            MemoryLocation::CpuToGpu,
            "shader binding table",
        )?;
        let base = buffer.address();
        let at = align_up(base, align) - base;
        buffer.mapped()[at as usize..at as usize + handle.len()].copy_from_slice(handle);
        Ok(Sbt {
            raygen: vk::StridedDeviceAddressRegionKHR {
                device_address: base + at,
                stride,
                size: stride,
            },
            _buffer: buffer,
        })
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
