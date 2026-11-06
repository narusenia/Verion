//! BLAS per mesh and one TLAS over the instances. The BLASes read their triangles straight out
//! of the concatenated position and index tables the shaders also bind, so the geometry exists
//! in GPU memory once.
//! shortcut: no compaction and one build at a time (sharing one scratch buffer); compact the
//! BLASes when scene memory matters (REQ-PERF-003).

use ash::vk;
use gpu_allocator::MemoryLocation;
use verion_gpu::pack::MeshRange;
use verion_scene::Transform;

use crate::{
    Error, VulkanContext,
    buffer::{Buffer, Upload},
};

pub struct Accel {
    ctx: VulkanContext,
    pub raw: vk::AccelerationStructureKHR,
    _buffer: Buffer,
    pub address: u64,
}

impl Drop for Accel {
    fn drop(&mut self) {
        // SAFETY: no submission using it is pending: they all wait.
        unsafe {
            self.ctx
                .0
                .accel
                .destroy_acceleration_structure(self.raw, None)
        };
    }
}

/// One build to record: its geometry, range and the acceleration structure it fills.
struct Job<'a> {
    geometry: [vk::AccelerationStructureGeometryKHR<'a>; 1],
    primitives: u32,
    ty: vk::AccelerationStructureTypeKHR,
}

impl Job<'_> {
    fn info(&self) -> vk::AccelerationStructureBuildGeometryInfoKHR<'_> {
        vk::AccelerationStructureBuildGeometryInfoKHR::default()
            .ty(self.ty)
            .flags(vk::BuildAccelerationStructureFlagsKHR::PREFER_FAST_TRACE)
            .mode(vk::BuildAccelerationStructureModeKHR::BUILD)
            .geometries(&self.geometry)
    }
}

fn align_up(v: u64, a: u64) -> u64 {
    v.div_ceil(a) * a
}

/// Builds each job into a new acceleration structure, sequentially in one submission.
fn build(ctx: &VulkanContext, jobs: &[Job<'_>]) -> Result<Vec<Accel>, Error> {
    let loader = &ctx.0.accel;
    let align = ctx.0.info.scratch_alignment;
    let mut outputs = Vec::new();
    let mut scratch_size = 0;
    for job in jobs {
        // SAFETY: plain size query on a valid description.
        let sizes = unsafe {
            let mut s = vk::AccelerationStructureBuildSizesInfoKHR::default();
            loader.get_acceleration_structure_build_sizes(
                vk::AccelerationStructureBuildTypeKHR::DEVICE,
                &job.info(),
                &[job.primitives],
                &mut s,
            );
            s
        };
        scratch_size = scratch_size.max(sizes.build_scratch_size);
        let buffer = Buffer::new(
            ctx,
            sizes.acceleration_structure_size,
            vk::BufferUsageFlags::ACCELERATION_STRUCTURE_STORAGE_KHR,
            MemoryLocation::GpuOnly,
            "acceleration structure",
        )?;
        // SAFETY: the buffer is large enough and outlives the structure (`Accel` keeps both).
        let raw = unsafe {
            loader.create_acceleration_structure(
                &vk::AccelerationStructureCreateInfoKHR::default()
                    .buffer(buffer.raw)
                    .size(sizes.acceleration_structure_size)
                    .ty(job.ty),
                None,
            )?
        };
        // SAFETY: just created.
        let address = unsafe {
            loader.get_acceleration_structure_device_address(
                &vk::AccelerationStructureDeviceAddressInfoKHR::default()
                    .acceleration_structure(raw),
            )
        };
        outputs.push(Accel {
            ctx: ctx.clone(),
            raw,
            _buffer: buffer,
            address,
        });
    }
    let scratch = Buffer::new(
        ctx,
        scratch_size + align,
        vk::BufferUsageFlags::STORAGE_BUFFER,
        MemoryLocation::GpuOnly,
        "acceleration structure scratch",
    )?;
    let scratch_address = align_up(scratch.address(), align);

    ctx.submit(|d, cmd| {
        let barrier = vk::MemoryBarrier::default()
            .src_access_mask(vk::AccessFlags::ACCELERATION_STRUCTURE_WRITE_KHR)
            .dst_access_mask(
                vk::AccessFlags::ACCELERATION_STRUCTURE_READ_KHR
                    | vk::AccessFlags::ACCELERATION_STRUCTURE_WRITE_KHR,
            );
        for (job, out) in jobs.iter().zip(&outputs) {
            let info = job.info().dst_acceleration_structure(out.raw).scratch_data(
                vk::DeviceOrHostAddressKHR {
                    device_address: scratch_address,
                },
            );
            let range = [vk::AccelerationStructureBuildRangeInfoKHR::default()
                .primitive_count(job.primitives)];
            // SAFETY: every address stays valid until this submission completes; the barrier
            // orders builds that share the scratch buffer and the TLAS build after its BLASes.
            unsafe {
                loader.cmd_build_acceleration_structures(cmd, &[info], &[&range]);
                d.cmd_pipeline_barrier(
                    cmd,
                    vk::PipelineStageFlags::ACCELERATION_STRUCTURE_BUILD_KHR,
                    vk::PipelineStageFlags::ACCELERATION_STRUCTURE_BUILD_KHR,
                    vk::DependencyFlags::empty(),
                    &[barrier],
                    &[],
                    &[],
                );
            }
        }
    })?;
    Ok(outputs)
}

/// One BLAS per mesh, in mesh order. `positions` and `indices` are the concatenated tables
/// (usage must include `ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR`); the indices are
/// mesh-local, so each BLAS starts at its mesh's vertex offset.
pub fn build_blases(
    ctx: &VulkanContext,
    positions: &Buffer,
    indices: &Buffer,
    meshes: &[MeshRange],
) -> Result<Vec<Accel>, Error> {
    let (pos, idx) = (positions.address(), indices.address());
    let jobs: Vec<Job> = meshes
        .iter()
        .map(|m| {
            let triangles = vk::AccelerationStructureGeometryTrianglesDataKHR::default()
                .vertex_format(vk::Format::R32G32B32_SFLOAT)
                .vertex_data(vk::DeviceOrHostAddressConstKHR {
                    device_address: pos + 12 * u64::from(m.vertex_offset),
                })
                .vertex_stride(12)
                .max_vertex(m.vertex_count.saturating_sub(1))
                .index_type(vk::IndexType::UINT32)
                .index_data(vk::DeviceOrHostAddressConstKHR {
                    device_address: idx + 4 * u64::from(m.index_offset),
                });
            Job {
                geometry: [vk::AccelerationStructureGeometryKHR::default()
                    .geometry_type(vk::GeometryTypeKHR::TRIANGLES)
                    .flags(vk::GeometryFlagsKHR::OPAQUE)
                    .geometry(vk::AccelerationStructureGeometryDataKHR { triangles })],
                primitives: m.index_count / 3,
                ty: vk::AccelerationStructureTypeKHR::BOTTOM_LEVEL,
            }
        })
        .collect();
    build(ctx, &jobs)
}

/// The TLAS over `instances` (mesh index and transform each). Instance `i` gets custom index
/// `i`, which is the row of the instance table the shaders look up.
pub fn build_tlas(
    ctx: &VulkanContext,
    blases: &[Accel],
    instances: &[(usize, Transform)],
) -> Result<Accel, Error> {
    let records: Vec<vk::AccelerationStructureInstanceKHR> = instances
        .iter()
        .enumerate()
        .map(|(i, (mesh, t))| vk::AccelerationStructureInstanceKHR {
            transform: vk::TransformMatrixKHR {
                matrix: std::array::from_fn(|k| t[k / 4][k % 4]),
            },
            instance_custom_index_and_mask: vk::Packed24_8::new(i as u32, 0xFF),
            // Surfaces are double-sided, as in the Metal backend.
            instance_shader_binding_table_record_offset_and_flags: vk::Packed24_8::new(
                0,
                vk::GeometryInstanceFlagsKHR::TRIANGLE_FACING_CULL_DISABLE.as_raw() as u8,
            ),
            acceleration_structure_reference: vk::AccelerationStructureReferenceKHR {
                device_handle: blases[*mesh].address,
            },
        })
        .collect();
    let mut up = Upload::new(ctx);
    let buffer = up.buffer(
        &records,
        vk::BufferUsageFlags::ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR,
        "tlas instances",
    )?;
    up.flush()?;
    let data = vk::AccelerationStructureGeometryInstancesDataKHR::default().data(
        vk::DeviceOrHostAddressConstKHR {
            device_address: buffer.address(),
        },
    );
    let jobs = [Job {
        geometry: [vk::AccelerationStructureGeometryKHR::default()
            .geometry_type(vk::GeometryTypeKHR::INSTANCES)
            .flags(vk::GeometryFlagsKHR::OPAQUE)
            .geometry(vk::AccelerationStructureGeometryDataKHR { instances: data })],
        primitives: records.len() as u32,
        ty: vk::AccelerationStructureTypeKHR::TOP_LEVEL,
    }];
    Ok(build(ctx, &jobs)?.remove(0))
}
