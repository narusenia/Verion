//! Turning the running sums an accumulation keeps on the GPU into the images `Accumulation`
//! returns. The sums are plain float arrays whichever API wrote them, so the arithmetic is shared.

use crate::{Adaptive, LightingAovs};

/// Floats per pixel in the lighting buffer; must match `shaders/include/pt_core.slang`.
pub const LIGHTING_STRIDE: usize = 65;
/// Floats per light slot after the first 17.
pub const SLOT_WORDS: usize = 12;

/// Sum of `lum(u) + lum(s)` over the samples of the slot whose record starts at `o`.
fn slot_weight(r: &[f32; LIGHTING_STRIDE], o: usize) -> f32 {
    r[o + 3] + 0.2126 * r[o + 5] + 0.7152 * r[o + 6] + 0.0722 * r[o + 7]
}

/// 1 / samples per pixel. `stats` is the adaptive-sampling record (samples, luminance sum, square
/// sum per pixel) when there is one; otherwise every pixel took `samples`.
pub fn inverse_samples(stats: Option<&[f32]>, pixels: usize, samples: u32) -> Vec<f32> {
    match stats {
        Some(stats) => stats
            .as_chunks::<3>()
            .0
            .iter()
            .map(|s| 1.0 / s[0].max(1.0))
            .collect(),
        None => vec![1.0 / samples.max(1) as f32; pixels],
    }
}

/// Mean radiance per pixel from the `xyz` sums.
pub fn mean(sums: &[f32], inverse: &[f32]) -> Vec<[f32; 3]> {
    sums.as_chunks::<3>()
        .0
        .iter()
        .zip(inverse)
        .map(|(c, inv)| [c[0] * inv, c[1] * inv, c[2] * inv])
        .collect()
}

/// Samples each pixel took, from the adaptive-sampling record.
pub fn sample_counts(stats: &[f32]) -> Vec<u32> {
    stats
        .as_chunks::<3>()
        .0
        .iter()
        .map(|s| s[0] as u32)
        .collect()
}

/// Pixels the next sample would trace: all of them unless adaptive sampling stopped some.
pub fn active_pixels(stats: Option<&[f32]>, adaptive: Option<Adaptive>, pixels: usize) -> usize {
    match (stats, adaptive) {
        (Some(stats), Some(a)) => stats
            .as_chunks::<3>()
            .0
            .iter()
            .filter(|s| a.active(s[0], s[1], s[2]))
            .count(),
        _ => pixels,
    }
}

/// The lighting split from the `LIGHTING_STRIDE` floats per pixel.
pub fn lighting(data: &[f32], inverse: &[f32]) -> LightingAovs {
    let records = data.as_chunks::<LIGHTING_STRIDE>().0;
    let part = |k: usize| -> Vec<[f32; 3]> {
        records
            .iter()
            .zip(inverse)
            .map(|(r, inv)| std::array::from_fn(|i| r[3 * k + i] * inv))
            .collect()
    };
    LightingAovs {
        direct_diffuse: part(0),
        indirect_diffuse: part(1),
        specular: part(2),
        transmission: part(3),
        emission: part(4),
        light_u: records
            .iter()
            .zip(inverse)
            .map(|(r, inv)| {
                std::array::from_fn(|s| std::array::from_fn(|i| r[17 + SLOT_WORDS * s + i] * inv))
            })
            .collect(),
        light_response: records
            .iter()
            .map(|r| {
                std::array::from_fn(|s| {
                    let o = 17 + SLOT_WORDS * s;
                    if r[o + 3] > 0.0 {
                        r[o + 4] / r[o + 3]
                    } else {
                        0.0
                    }
                })
            })
            .collect(),
        light_s: records
            .iter()
            .zip(inverse)
            .map(|(r, inv)| {
                std::array::from_fn(|s| {
                    std::array::from_fn(|i| r[17 + SLOT_WORDS * s + 5 + i] * inv)
                })
            })
            .collect(),
        light_dir: records
            .iter()
            .map(|r| {
                std::array::from_fn(|s| {
                    let o = 17 + SLOT_WORDS * s;
                    let w = slot_weight(r, o);
                    if w > 0.0 {
                        std::array::from_fn(|i| r[o + 8 + i] / w)
                    } else {
                        [0.0; 3]
                    }
                })
            })
            .collect(),
        light_lit: records
            .iter()
            .map(|r| {
                std::array::from_fn(|s| {
                    let o = 17 + SLOT_WORDS * s;
                    let w = slot_weight(r, o);
                    if w > 0.0 { r[o + 11] / w } else { 0.0 }
                })
            })
            .collect(),
        visibility: records
            .iter()
            .map(|r| if r[16] > 0.0 { r[15] / r[16] } else { 1.0 })
            .collect(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use verion_scene::LIGHT_SLOTS;

    #[test]
    fn mean_divides_by_the_pixels_own_sample_count() {
        let stats = [4.0, 0.0, 0.0, 2.0, 0.0, 0.0];
        let inv = inverse_samples(Some(&stats), 2, 99);
        assert_eq!(inv, [0.25, 0.5]);
        assert_eq!(
            mean(&[4.0, 8.0, 12.0, 2.0, 2.0, 2.0], &inv)[..],
            [[1.0, 2.0, 3.0], [1.0; 3]]
        );
        assert_eq!(inverse_samples(None, 2, 4), [0.25, 0.25]);
        assert_eq!(sample_counts(&stats), [4, 2]);
    }

    #[test]
    fn lighting_reads_parts_and_defaults_empty_slots() {
        let mut record = [0.0f32; LIGHTING_STRIDE];
        record[3..6].copy_from_slice(&[2.0, 4.0, 6.0]); // indirect diffuse
        let l = lighting(&record, &[0.5]);
        assert_eq!(l.indirect_diffuse, [[1.0, 2.0, 3.0]]);
        assert_eq!(l.visibility, [1.0]); // no direct light: fully visible
        assert_eq!(l.light_response, [[0.0; LIGHT_SLOTS]]);
    }
}
