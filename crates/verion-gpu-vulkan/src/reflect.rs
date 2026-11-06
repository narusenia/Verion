//! The descriptor bindings a SPIR-V module declares. Slang drops the globals a kernel never
//! touches, so each kernel's set layout comes from its own module instead of a table that could
//! drift from the shader.

/// What a binding holds. Only the two kinds the kernels use.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    AccelerationStructure,
    StorageBuffer,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Binding {
    pub binding: u32,
    pub kind: Kind,
}

const OP_DECORATE: u32 = 71;
const OP_TYPE_POINTER: u32 = 32;
const OP_TYPE_ACCEL: u32 = 5341;
const OP_VARIABLE: u32 = 59;
const DECORATION_BINDING: u32 = 33;
const DECORATION_SET: u32 = 34;
const STORAGE_CLASS_STORAGE_BUFFER: u32 = 12;

/// The little-endian words of a SPIR-V module (its length is a multiple of 4).
pub fn words(spv: &[u8]) -> Vec<u32> {
    spv.as_chunks::<4>()
        .0
        .iter()
        .map(|b| u32::from_le_bytes(*b))
        .collect()
}

/// Bindings of descriptor set 0, sorted by number. Errors on any other set or resource kind.
pub fn bindings(spv: &[u8]) -> Result<Vec<Binding>, String> {
    if !spv.len().is_multiple_of(4) || spv.len() < 20 {
        return Err("not a SPIR-V module".into());
    }
    let words = words(spv);
    let (mut binding_of, mut set_of) = (Vec::new(), Vec::new());
    let (mut pointers, mut accel_types, mut variables) = (Vec::new(), Vec::new(), Vec::new());
    let mut i = 5;
    while i < words.len() {
        let (len, op) = ((words[i] >> 16) as usize, words[i] & 0xffff);
        if len == 0 || i + len > words.len() {
            return Err("truncated SPIR-V".into());
        }
        let a = &words[i + 1..i + len];
        match op {
            OP_DECORATE if a[1] == DECORATION_BINDING => binding_of.push((a[0], a[2])),
            OP_DECORATE if a[1] == DECORATION_SET => set_of.push((a[0], a[2])),
            OP_TYPE_POINTER => pointers.push((a[0], a[1], a[2])), // id, storage class, pointee
            OP_TYPE_ACCEL => accel_types.push(a[0]),
            OP_VARIABLE => variables.push((a[1], a[0])), // id, pointer type
            _ => {}
        }
        i += len;
    }
    let find = |v: &[(u32, u32)], id| v.iter().find(|x| x.0 == id).map(|x| x.1);
    let mut out = Vec::new();
    for (id, ptr) in variables {
        let (Some(binding), Some(set)) = (find(&binding_of, id), find(&set_of, id)) else {
            continue; // not a descriptor resource
        };
        if set != 0 {
            return Err(format!("binding {binding} is in descriptor set {set}"));
        }
        let &(_, class, pointee) = pointers
            .iter()
            .find(|p| p.0 == ptr)
            .ok_or("variable without a pointer type")?;
        let kind = if accel_types.contains(&pointee) {
            Kind::AccelerationStructure
        } else if class == STORAGE_CLASS_STORAGE_BUFFER {
            Kind::StorageBuffer
        } else {
            return Err(format!(
                "binding {binding} is neither a storage buffer nor an acceleration structure"
            ));
        };
        out.push(Binding { binding, kind });
    }
    out.sort_by_key(|b| b.binding);
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::SHADERS;

    fn of(name: &str) -> Vec<(u32, Kind)> {
        let (_, spv) = SHADERS.iter().find(|(n, _)| *n == name).unwrap();
        bindings(spv)
            .unwrap()
            .into_iter()
            .map(|b| (b.binding, b.kind))
            .collect()
    }

    #[test]
    fn megakernel_binds_the_scene_first_and_buffers_after() {
        let b = of("pathtrace");
        assert_eq!(b.len(), 20);
        assert_eq!(b[0], (0, Kind::AccelerationStructure));
        assert!(b[1..].iter().all(|x| x.1 == Kind::StorageBuffer));
    }

    #[test]
    fn unused_globals_are_dropped_from_the_layout() {
        let nums: Vec<u32> = of("wf_args").iter().map(|b| b.0).collect();
        assert_eq!(nums, [6, 24, 25]);
        let nums: Vec<u32> = of("wf_extend").iter().map(|b| b.0).collect();
        assert_eq!(nums, [0, 6, 20, 21, 22, 24]);
    }

    #[test]
    fn every_shader_reflects() {
        for (name, spv) in SHADERS {
            assert!(!bindings(spv).unwrap().is_empty(), "{name}");
        }
    }
}
