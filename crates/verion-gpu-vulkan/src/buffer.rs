//! Buffers with their memory, batched uploads and readbacks. Scene data lives in device-local
//! memory and goes up through one staging copy per upload batch; results come back through a
//! staging buffer too, because on a discrete GPU the accumulation buffers must not sit in host memory.

use std::sync::atomic::Ordering;

use ash::vk;
use gpu_allocator::{
    MemoryLocation,
    vulkan::{Allocation, AllocationCreateDesc, AllocationScheme},
};

use crate::{Error, VulkanContext};

/// A buffer that frees itself (and its memory) on drop.
pub struct Buffer {
    ctx: VulkanContext,
    pub raw: vk::Buffer,
    alloc: Option<Allocation>,
    /// Device-local bytes behind it, counted in `MemoryUsage` when the budget extension is missing.
    memory: u64,
}

impl Buffer {
    pub fn new(
        ctx: &VulkanContext,
        size: u64,
        usage: vk::BufferUsageFlags,
        location: MemoryLocation,
        name: &'static str,
    ) -> Result<Self, Error> {
        let size = size.max(4); // Vulkan rejects zero-sized buffers; a word keeps empty tables bindable
        let d = &ctx.0.device;
        let info = vk::BufferCreateInfo::default()
            .size(size)
            .usage(usage | vk::BufferUsageFlags::SHADER_DEVICE_ADDRESS)
            .sharing_mode(vk::SharingMode::EXCLUSIVE);
        // SAFETY: the buffer is bound to memory before use and destroyed in `drop`.
        unsafe {
            let raw = d.create_buffer(&info, None)?;
            let req = d.get_buffer_memory_requirements(raw);
            let device_local = location == MemoryLocation::GpuOnly;
            if device_local && let Err(e) = ctx.check_fits(req.size) {
                d.destroy_buffer(raw, None);
                return Err(e);
            }
            let alloc =
                ctx.0
                    .allocator
                    .lock()
                    .unwrap()
                    .as_mut()
                    .unwrap()
                    .allocate(&AllocationCreateDesc {
                        name,
                        requirements: req,
                        location,
                        linear: true,
                        allocation_scheme: AllocationScheme::GpuAllocatorManaged,
                    });
            let Ok(alloc) = alloc else {
                d.destroy_buffer(raw, None);
                return Err(Error::Resource(name));
            };
            if let Err(e) = d.bind_buffer_memory(raw, alloc.memory(), alloc.offset()) {
                d.destroy_buffer(raw, None);
                let _ = ctx
                    .0
                    .allocator
                    .lock()
                    .unwrap()
                    .as_mut()
                    .unwrap()
                    .free(alloc);
                return Err(e.into());
            }
            let memory = if device_local { req.size } else { 0 };
            ctx.0.allocated.fetch_add(memory, Ordering::Relaxed);
            Ok(Self {
                ctx: ctx.clone(),
                raw,
                alloc: Some(alloc),
                memory,
            })
        }
    }

    pub fn address(&self) -> u64 {
        // SAFETY: the buffer was created with SHADER_DEVICE_ADDRESS.
        unsafe {
            self.ctx
                .0
                .device
                .get_buffer_device_address(&vk::BufferDeviceAddressInfo::default().buffer(self.raw))
        }
    }

    /// The mapped bytes of a host-visible buffer.
    pub fn mapped(&mut self) -> &mut [u8] {
        self.alloc
            .as_mut()
            .and_then(|a| a.mapped_slice_mut())
            .expect("buffer is not host-visible")
    }
}

impl Drop for Buffer {
    fn drop(&mut self) {
        // SAFETY: the GPU is done with it: every submission waits before its buffers are dropped.
        unsafe { self.ctx.0.device.destroy_buffer(self.raw, None) };
        if let Some(a) = self.alloc.take() {
            let _ = self
                .ctx
                .0
                .allocator
                .lock()
                .unwrap()
                .as_mut()
                .unwrap()
                .free(a);
        }
        self.ctx
            .0
            .allocated
            .fetch_sub(self.memory, Ordering::Relaxed);
    }
}

pub fn bytes_of<T: Copy>(data: &[T]) -> &[u8] {
    // SAFETY: `T` is plain old data (f32 / u32 tables); the slice covers exactly its bytes.
    unsafe { std::slice::from_raw_parts(data.as_ptr().cast(), size_of_val(data)) }
}

/// Uploads several tables with one submission: each goes to a staging buffer now and is copied
/// to its device-local buffer when [`Upload::flush`] runs.
pub struct Upload<'a> {
    ctx: &'a VulkanContext,
    pending: Vec<(Buffer, vk::Buffer, u64)>,
}

impl<'a> Upload<'a> {
    pub fn new(ctx: &'a VulkanContext) -> Self {
        Self {
            ctx,
            pending: Vec::new(),
        }
    }

    /// A device-local buffer that holds `data` once `flush` has run.
    pub fn buffer<T: Copy>(
        &mut self,
        data: &[T],
        usage: vk::BufferUsageFlags,
        name: &'static str,
    ) -> Result<Buffer, Error> {
        let bytes = bytes_of(data);
        let size = bytes.len().max(4) as u64;
        let dst = Buffer::new(
            self.ctx,
            size,
            usage | vk::BufferUsageFlags::TRANSFER_DST,
            MemoryLocation::GpuOnly,
            name,
        )?;
        let mut staging = Buffer::new(
            self.ctx,
            size,
            vk::BufferUsageFlags::TRANSFER_SRC,
            MemoryLocation::CpuToGpu,
            "staging",
        )?;
        staging.mapped()[..bytes.len()].copy_from_slice(bytes);
        self.ctx.note_upload(bytes.len() as u64);
        self.pending.push((staging, dst.raw, size));
        Ok(dst)
    }

    pub fn flush(self) -> Result<(), Error> {
        if self.pending.is_empty() {
            return Ok(());
        }
        self.ctx.submit(|d, cmd| {
            for (staging, dst, size) in &self.pending {
                // SAFETY: both buffers outlive the submission, which this call waits for.
                unsafe {
                    d.cmd_copy_buffer(
                        cmd,
                        staging.raw,
                        *dst,
                        &[vk::BufferCopy::default().size(*size)],
                    );
                }
            }
        })
    }
}

impl VulkanContext {
    /// A zero-filled device-local buffer.
    pub(crate) fn zeroed(
        &self,
        size: u64,
        usage: vk::BufferUsageFlags,
        name: &'static str,
    ) -> Result<Buffer, Error> {
        // Rounded up to a word: vkCmdFillBuffer wants a multiple of 4.
        let buf = Buffer::new(
            self,
            size.next_multiple_of(4),
            usage | vk::BufferUsageFlags::TRANSFER_DST,
            MemoryLocation::GpuOnly,
            name,
        )?;
        self.submit(|d, cmd| {
            // SAFETY: the buffer has TRANSFER_DST and outlives the submission.
            unsafe { d.cmd_fill_buffer(cmd, buf.raw, 0, vk::WHOLE_SIZE, 0) }
        })?;
        Ok(buf)
    }

    /// Copies the first `len` bytes of `buf` (usage `TRANSFER_SRC`) back to the host.
    pub(crate) fn read_bytes(&self, buf: &Buffer, len: u64) -> Result<Vec<u8>, Error> {
        let mut staging = Buffer::new(
            self,
            len,
            vk::BufferUsageFlags::TRANSFER_DST,
            MemoryLocation::GpuToCpu,
            "readback",
        )?;
        self.submit(|d, cmd| {
            // SAFETY: both buffers outlive the submission, which this call waits for.
            unsafe {
                d.cmd_copy_buffer(
                    cmd,
                    buf.raw,
                    staging.raw,
                    &[vk::BufferCopy::default().size(len)],
                );
            }
        })?;
        Ok(staging.mapped()[..len as usize].to_vec())
    }

    pub(crate) fn read_f32(&self, buf: &Buffer, count: usize) -> Result<Vec<f32>, Error> {
        let bytes = self.read_bytes(buf, (count * 4) as u64)?;
        Ok(bytes
            .as_chunks::<4>()
            .0
            .iter()
            .map(|b| f32::from_le_bytes(*b))
            .collect())
    }

    pub(crate) fn read_u32(&self, buf: &Buffer, count: usize) -> Result<Vec<u32>, Error> {
        let bytes = self.read_bytes(buf, (count * 4) as u64)?;
        Ok(bytes
            .as_chunks::<4>()
            .0
            .iter()
            .map(|b| u32::from_le_bytes(*b))
            .collect())
    }
}
