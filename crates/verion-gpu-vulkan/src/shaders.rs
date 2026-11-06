//! The SPIR-V that `scripts/shaders.sh` compiles from the same Slang sources as the Metal MSL;
//! bindings are descriptor set 0 with the same numbers as the Metal buffer indices.

/// SPIR-V of each shader, entry point `main`, by shader name. All are compute shaders except
/// `pathtrace_ser`, a ray generation shader (Vulkan only, shader execution reordering).
pub const SHADERS: [(&str, &[u8]); 8] = [
    ("aov", include_bytes!("../shaders/aov.spv")),
    ("normals", include_bytes!("../shaders/normals.spv")),
    ("pathtrace", include_bytes!("../shaders/pathtrace.spv")),
    (
        "pathtrace_ser",
        include_bytes!("../shaders/pathtrace_ser.spv"),
    ),
    ("wf_args", include_bytes!("../shaders/wf_args.spv")),
    ("wf_extend", include_bytes!("../shaders/wf_extend.spv")),
    ("wf_select", include_bytes!("../shaders/wf_select.spv")),
    ("wf_shade", include_bytes!("../shaders/wf_shade.spv")),
];

/// The SPIR-V of the named shader; panics on a name that is not in `SHADERS` (a programming error).
pub fn spirv(name: &str) -> &'static [u8] {
    SHADERS
        .iter()
        .find(|(n, _)| *n == name)
        .unwrap_or_else(|| panic!("no shader named {name}"))
        .1
}

#[cfg(test)]
mod tests {
    use super::SHADERS;

    #[test]
    fn every_shader_is_spirv_1_5_with_a_main_entry_point() {
        for (name, spv) in SHADERS {
            assert_eq!(spv.len() % 4, 0, "{name}");
            let word = |i: usize| u32::from_le_bytes(spv[4 * i..4 * i + 4].try_into().unwrap());
            assert_eq!(word(0), 0x0723_0203, "{name}: magic");
            assert_eq!(word(1), 0x0001_0500, "{name}: version");
            assert!(
                spv.windows(5).any(|w| w == b"main\0"),
                "{name}: entry point"
            );
        }
    }

    #[test]
    fn every_slang_shader_has_its_spirv() {
        let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/../../shaders");
        let mut names: Vec<String> = std::fs::read_dir(dir)
            .unwrap()
            .filter_map(|e| e.unwrap().file_name().into_string().ok())
            .filter_map(|f| f.strip_suffix(".slang").map(str::to_owned))
            .collect();
        names.sort();
        assert_eq!(names, SHADERS.map(|(n, _)| n));
    }
}
