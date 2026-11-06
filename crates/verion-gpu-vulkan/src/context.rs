//! Instance, device and queue, with the feature detection of REQ-GPU-006: ray query and
//! acceleration structures are required (an explicit error names what is missing); shader
//! execution reordering and the timestamp clock are optional.

use std::{
    ffi::{CStr, c_char},
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, Ordering},
    },
};

use ash::{khr, vk};
use gpu_allocator::vulkan::{Allocator, AllocatorCreateDesc};
use verion_gpu::MemoryUsage;

use crate::Error;

/// Which shader-execution-reordering extension the device offers (`VK_EXT_` is the cross-vendor one).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SerSupport {
    Ext,
    Nv,
}

/// What the chosen device can do, for the metrics and for choosing code paths.
#[derive(Clone, Debug)]
pub struct DeviceInfo {
    pub name: String,
    pub driver_version: u32,
    pub api_version: u32,
    /// Nanoseconds per timestamp tick, or `None` when the queue cannot write timestamps.
    pub timestamp_period_ns: Option<f64>,
    /// Valid low bits of a timestamp (the rest read as zero).
    pub timestamp_bits: u32,
    pub ser: Option<SerSupport>,
    /// `VK_KHR_ray_tracing_pipeline`, which the SER megakernel needs.
    pub ray_tracing_pipeline: bool,
    pub(crate) scratch_alignment: u64,
    pub(crate) storage_alignment: u64,
    pub(crate) memory_budget_ext: bool,
}

pub(crate) struct Inner {
    // Declared first so it is dropped before the device it was made from.
    pub allocator: Mutex<Option<Allocator>>,
    pub device: ash::Device,
    pub accel: khr::acceleration_structure::Device,
    pub queue: Mutex<vk::Queue>,
    pub pool: Mutex<vk::CommandPool>,
    pub info: DeviceInfo,
    pub physical: vk::PhysicalDevice,
    pub instance: ash::Instance,
    _entry: ash::Entry,
    pub uploaded: AtomicU64,
    /// Bytes of buffer memory this context holds, used when the budget extension is missing.
    pub allocated: AtomicU64,
}

impl Drop for Inner {
    fn drop(&mut self) {
        // SAFETY: nothing else holds the device once the last context clone is gone.
        unsafe {
            let _ = self.device.device_wait_idle();
            self.device
                .destroy_command_pool(*self.pool.get_mut().unwrap(), None);
            drop(self.allocator.get_mut().unwrap().take());
            self.device.destroy_device(None);
            self.instance.destroy_instance(None);
        }
    }
}

/// The device and queue, shared (and kept alive) by everything made from it.
#[derive(Clone)]
pub struct VulkanContext(pub(crate) Arc<Inner>);

const REQUIRED_EXTENSIONS: [(&CStr, &str); 3] = [
    (
        khr::acceleration_structure::NAME,
        "VK_KHR_acceleration_structure",
    ),
    (khr::ray_query::NAME, "VK_KHR_ray_query"),
    (
        khr::deferred_host_operations::NAME,
        "VK_KHR_deferred_host_operations",
    ),
];

fn has(exts: &[vk::ExtensionProperties], name: &CStr) -> bool {
    exts.iter()
        .any(|e| e.extension_name_as_c_str().is_ok_and(|n| n == name))
}

struct Candidate {
    physical: vk::PhysicalDevice,
    family: u32,
    info: DeviceInfo,
    discrete: bool,
    vram: u64,
    extensions: Vec<&'static CStr>,
    missing: Vec<&'static str>,
}

impl VulkanContext {
    /// Opens the best device with hardware ray tracing: a discrete GPU first, then the most memory.
    pub fn new() -> Result<Self, Error> {
        // SAFETY: loads the system's Vulkan loader.
        let entry = unsafe { ash::Entry::load() }.map_err(|e| Error::NoVulkan(e.to_string()))?;
        let app = vk::ApplicationInfo::default()
            .application_name(c"Verion")
            .api_version(vk::API_VERSION_1_2);
        let mut layers: Vec<*const c_char> = Vec::new();
        // The validation layer is only there with the Vulkan SDK; opt in with VERION_VULKAN_VALIDATION=1.
        let validation = c"VK_LAYER_KHRONOS_validation";
        if std::env::var_os("VERION_VULKAN_VALIDATION").is_some_and(|v| v == "1") {
            // SAFETY: plain query.
            let available = unsafe { entry.enumerate_instance_layer_properties() }?;
            if available
                .iter()
                .any(|l| l.layer_name_as_c_str().is_ok_and(|n| n == validation))
            {
                layers.push(validation.as_ptr());
            } else {
                eprintln!("warning: VK_LAYER_KHRONOS_validation is not installed");
            }
        }
        let create = vk::InstanceCreateInfo::default()
            .application_info(&app)
            .enabled_layer_names(&layers);
        // SAFETY: the create info and what it points to live through the call.
        let instance = unsafe { entry.create_instance(&create, None) }
            .map_err(|e| Error::NoVulkan(e.to_string()))?;

        match Self::open(&entry, &instance) {
            Ok(inner) => Ok(Self(Arc::new(inner))),
            Err(e) => {
                // SAFETY: no device was created from it.
                unsafe { instance.destroy_instance(None) };
                Err(e)
            }
        }
    }

    fn candidates(instance: &ash::Instance) -> Result<Vec<Candidate>, Error> {
        // SAFETY: plain queries on handles the instance returned.
        unsafe {
            let mut out = Vec::new();
            for physical in instance.enumerate_physical_devices()? {
                let props = instance.get_physical_device_properties(physical);
                let name = props
                    .device_name_as_c_str()
                    .map_or_else(|_| "unknown".into(), |n| n.to_string_lossy().into_owned());
                let exts = instance.enumerate_device_extension_properties(physical)?;
                let mut missing: Vec<&'static str> = REQUIRED_EXTENSIONS
                    .iter()
                    .filter(|(n, _)| !has(&exts, n))
                    .map(|&(_, label)| label)
                    .collect();

                let mut accel = vk::PhysicalDeviceAccelerationStructureFeaturesKHR::default();
                let mut query = vk::PhysicalDeviceRayQueryFeaturesKHR::default();
                let mut v12 = vk::PhysicalDeviceVulkan12Features::default();
                let mut f2 = vk::PhysicalDeviceFeatures2::default()
                    .push_next(&mut accel)
                    .push_next(&mut query)
                    .push_next(&mut v12);
                instance.get_physical_device_features2(physical, &mut f2);
                if props.api_version < vk::API_VERSION_1_2 {
                    missing.push("Vulkan 1.2");
                }
                if missing.is_empty() {
                    if accel.acceleration_structure == vk::FALSE {
                        missing.push("accelerationStructure");
                    }
                    if query.ray_query == vk::FALSE {
                        missing.push("rayQuery");
                    }
                    if v12.buffer_device_address == vk::FALSE {
                        missing.push("bufferDeviceAddress");
                    }
                }

                let families = instance.get_physical_device_queue_family_properties(physical);
                let family = families
                    .iter()
                    .position(|f| f.queue_flags.contains(vk::QueueFlags::COMPUTE))
                    .map(|i| i as u32);
                if family.is_none() {
                    missing.push("a compute queue");
                }
                let family_index = family.unwrap_or(0);
                let valid_bits = families
                    .get(family_index as usize)
                    .map_or(0, |f| f.timestamp_valid_bits);

                let mut as_props = vk::PhysicalDeviceAccelerationStructurePropertiesKHR::default();
                let mut p2 = vk::PhysicalDeviceProperties2::default().push_next(&mut as_props);
                instance.get_physical_device_properties2(physical, &mut p2);

                let mem = instance.get_physical_device_memory_properties(physical);
                let vram: u64 = mem.memory_heaps[..mem.memory_heap_count as usize]
                    .iter()
                    .filter(|h| h.flags.contains(vk::MemoryHeapFlags::DEVICE_LOCAL))
                    .map(|h| h.size)
                    .sum();

                let ser = if has(&exts, c"VK_EXT_ray_tracing_invocation_reorder") {
                    Some(SerSupport::Ext)
                } else if has(&exts, c"VK_NV_ray_tracing_invocation_reorder") {
                    Some(SerSupport::Nv)
                } else {
                    None
                };
                let budget = has(&exts, c"VK_EXT_memory_budget");
                let mut extensions: Vec<&'static CStr> =
                    REQUIRED_EXTENSIONS.iter().map(|&(n, _)| n).collect();
                if budget {
                    extensions.push(c"VK_EXT_memory_budget");
                }
                out.push(Candidate {
                    physical,
                    family: family_index,
                    discrete: props.device_type == vk::PhysicalDeviceType::DISCRETE_GPU,
                    vram,
                    extensions,
                    missing,
                    info: DeviceInfo {
                        name,
                        driver_version: props.driver_version,
                        api_version: props.api_version,
                        timestamp_bits: valid_bits,
                        timestamp_period_ns: (valid_bits > 0
                            && props.limits.timestamp_period > 0.0)
                            .then_some(f64::from(props.limits.timestamp_period)),
                        ser,
                        ray_tracing_pipeline: has(&exts, khr::ray_tracing_pipeline::NAME),
                        scratch_alignment: u64::from(
                            as_props
                                .min_acceleration_structure_scratch_offset_alignment
                                .max(1),
                        ),
                        storage_alignment: props.limits.min_storage_buffer_offset_alignment.max(1),
                        memory_budget_ext: budget,
                    },
                });
            }
            Ok(out)
        }
    }

    fn open(entry: &ash::Entry, instance: &ash::Instance) -> Result<Inner, Error> {
        let mut candidates = Self::candidates(instance)?;
        if candidates.is_empty() {
            return Err(Error::NoDevice);
        }
        candidates.sort_by_key(|c| (c.missing.is_empty(), c.discrete, c.vram));
        let best = candidates.pop().unwrap();
        if !best.missing.is_empty() {
            return Err(Error::Unsupported {
                device: best.info.name,
                missing: best.missing,
            });
        }

        let priorities = [1.0f32];
        let queue_info = [vk::DeviceQueueCreateInfo::default()
            .queue_family_index(best.family)
            .queue_priorities(&priorities)];
        let mut accel = vk::PhysicalDeviceAccelerationStructureFeaturesKHR::default()
            .acceleration_structure(true);
        let mut query = vk::PhysicalDeviceRayQueryFeaturesKHR::default().ray_query(true);
        let mut v12 = vk::PhysicalDeviceVulkan12Features::default().buffer_device_address(true);
        let names: Vec<*const c_char> = best.extensions.iter().map(|n| n.as_ptr()).collect();
        let create = vk::DeviceCreateInfo::default()
            .queue_create_infos(&queue_info)
            .enabled_extension_names(&names)
            .push_next(&mut accel)
            .push_next(&mut query)
            .push_next(&mut v12);
        // SAFETY: the create info and what it points to live through the calls; the device is used
        // only through this context.
        unsafe {
            let device = instance.create_device(best.physical, &create, None)?;
            let queue = device.get_device_queue(best.family, 0);
            let pool = device.create_command_pool(
                &vk::CommandPoolCreateInfo::default()
                    .queue_family_index(best.family)
                    .flags(vk::CommandPoolCreateFlags::RESET_COMMAND_BUFFER),
                None,
            )?;
            let allocator = Allocator::new(&AllocatorCreateDesc {
                instance: instance.clone(),
                device: device.clone(),
                physical_device: best.physical,
                debug_settings: Default::default(),
                buffer_device_address: true,
                allocation_sizes: Default::default(),
            })
            .map_err(|_| Error::Resource("allocator"))?;
            Ok(Inner {
                allocator: Mutex::new(Some(allocator)),
                accel: khr::acceleration_structure::Device::new(instance, &device),
                device,
                queue: Mutex::new(queue),
                pool: Mutex::new(pool),
                info: best.info,
                physical: best.physical,
                instance: instance.clone(),
                _entry: entry.clone(),
                uploaded: AtomicU64::new(0),
                allocated: AtomicU64::new(0),
            })
        }
    }

    pub fn info(&self) -> &DeviceInfo {
        &self.0.info
    }

    pub(crate) fn note_upload(&self, bytes: u64) {
        self.0.uploaded.fetch_add(bytes, Ordering::Relaxed);
    }

    /// Budget and use of device-local memory. With `VK_EXT_memory_budget` both come from the
    /// driver and count every client of the process; otherwise the budget is the heap size and the
    /// use is what this context allocated.
    pub fn memory(&self) -> MemoryUsage {
        let inner = &self.0;
        let uploaded = inner.uploaded.load(Ordering::Relaxed);
        // SAFETY: plain query; the budget struct is chained as the extension requires.
        let (budget, allocated) = unsafe {
            if inner.info.memory_budget_ext {
                let mut b = vk::PhysicalDeviceMemoryBudgetPropertiesEXT::default();
                let mut p = vk::PhysicalDeviceMemoryProperties2::default().push_next(&mut b);
                inner
                    .instance
                    .get_physical_device_memory_properties2(inner.physical, &mut p);
                let heaps = p.memory_properties;
                let (mut budget, mut used) = (0, 0);
                for i in 0..heaps.memory_heap_count as usize {
                    if heaps.memory_heaps[i]
                        .flags
                        .contains(vk::MemoryHeapFlags::DEVICE_LOCAL)
                    {
                        budget += b.heap_budget[i];
                        used += b.heap_usage[i];
                    }
                }
                (budget, used)
            } else {
                let m = inner
                    .instance
                    .get_physical_device_memory_properties(inner.physical);
                let heap: u64 = m.memory_heaps[..m.memory_heap_count as usize]
                    .iter()
                    .filter(|h| h.flags.contains(vk::MemoryHeapFlags::DEVICE_LOCAL))
                    .map(|h| h.size)
                    .sum();
                (heap, inner.allocated.load(Ordering::Relaxed))
            }
        };
        MemoryUsage {
            budget,
            allocated,
            uploaded,
        }
    }

    /// Fails with [`Error::OutOfMemory`] when `bytes` more would exceed the device's budget.
    pub(crate) fn check_fits(&self, bytes: u64) -> Result<(), Error> {
        let m = self.memory();
        let available = m.budget.saturating_sub(m.allocated);
        if bytes > available {
            return Err(Error::OutOfMemory {
                needed: bytes,
                available,
            });
        }
        Ok(())
    }

    /// Records into a fresh command buffer, submits it and waits for the GPU. `record` may also
    /// read back anything it wrote after this returns.
    pub(crate) fn submit(
        &self,
        record: impl FnOnce(&ash::Device, vk::CommandBuffer),
    ) -> Result<(), Error> {
        let d = &self.0.device;
        // SAFETY: the pool and queue are locked while used; the command buffer and fence are
        // destroyed after the wait.
        unsafe {
            let cmd = {
                let pool = self.0.pool.lock().unwrap();
                d.allocate_command_buffers(
                    &vk::CommandBufferAllocateInfo::default()
                        .command_pool(*pool)
                        .command_buffer_count(1),
                )?[0]
            };
            let result = (|| -> Result<(), Error> {
                d.begin_command_buffer(
                    cmd,
                    &vk::CommandBufferBeginInfo::default()
                        .flags(vk::CommandBufferUsageFlags::ONE_TIME_SUBMIT),
                )?;
                record(d, cmd);
                d.end_command_buffer(cmd)?;
                let fence = d.create_fence(&vk::FenceCreateInfo::default(), None)?;
                let cmds = [cmd];
                let submit = [vk::SubmitInfo::default().command_buffers(&cmds)];
                let sent = {
                    let q = self.0.queue.lock().unwrap();
                    d.queue_submit(*q, &submit, fence)
                };
                let waited = sent.and_then(|()| d.wait_for_fences(&[fence], true, u64::MAX));
                d.destroy_fence(fence, None);
                Ok(waited?)
            })();
            let pool = self.0.pool.lock().unwrap();
            d.free_command_buffers(*pool, &[cmd]);
            result
        }
    }
}
