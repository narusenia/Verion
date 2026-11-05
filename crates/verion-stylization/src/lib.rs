//! Stylization Pass (REQ-STY-007): composes the final color of a primary hit from the lighting
//! AOVs and the material's stylization layers. GPU independent. Reference mode never calls it.
//!
//! Implemented so far: `HybridSurface::diffuse` blending the direct diffuse toward a `ToonRamp`
//! applied per light.
//! The other components pass through unchanged until their layers land.

use verion_scene::{HybridSurface, LIGHT_SLOTS, Material, StylizationLayer, ToonRamp};

/// The first-hit lighting split of one pixel, in the working space (see `LightingAovs`).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct PixelInput {
    pub direct_diffuse: [f32; 3],
    pub indirect_diffuse: [f32; 3],
    pub specular: [f32; 3],
    pub transmission: [f32; 3],
    pub emission: [f32; 3],
    /// Per light slot: the diffuse contribution without cos and without shadowing.
    pub light_u: [[f32; 3]; LIGHT_SLOTS],
    /// Per light slot: cos(N, L) times visibility. The physical diffuse is `u * response`.
    pub light_response: [f32; LIGHT_SLOTS],
}

fn smoothstep(e0: f32, e1: f32, x: f32) -> f32 {
    let t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

/// Band color of `ramp` for a light response in `0..=1`. Adjacent bands blend over `feather`
/// around each threshold; light wrap shifts the response so light reaches past the terminator.
pub fn ramp_color(ramp: &ToonRamp, response: f32) -> [f32; 3] {
    let r = ((response + ramp.light_wrap) / (1.0 + ramp.light_wrap)).clamp(0.0, 1.0);
    let mut color = ramp.palette[0];
    for (&t, next) in ramp.thresholds.iter().zip(&ramp.palette[1..]) {
        let w = if ramp.feather > 0.0 {
            smoothstep(t - 0.5 * ramp.feather, t + 0.5 * ramp.feather, r)
        } else {
            (r >= t) as u8 as f32
        };
        color = std::array::from_fn(|i| color[i] + (next[i] - color[i]) * w);
    }
    color
}

/// Final color of one pixel. Layers must be valid (`StylizationLayer::validate`).
///
/// The ramp sees each light's own response (cos times visibility), so it bands every light
/// separately and a shadowed light still lands in the darkest band.
///
/// shortcut: emissive triangles and the environment share one slot, so their ramp input is the
/// contribution-weighted mean response of the samples; soft edges from area lights are averaged.
pub fn stylize(layers: &[StylizationLayer], p: &PixelInput) -> [f32; 3] {
    let hybrid = layers.iter().find_map(|l| match l {
        StylizationLayer::HybridSurface(h) => Some(*h),
        _ => None,
    });
    let ramp = layers.iter().find_map(|l| match l {
        StylizationLayer::ToonRamp(t) => Some(t),
        _ => None,
    });
    let mut diffuse = p.direct_diffuse;
    if let (Some(HybridSurface { diffuse: k, .. }), Some(ramp)) = (hybrid, ramp) {
        let mut toon = [0.0f32; 3];
        for (u, &r) in p.light_u.iter().zip(&p.light_response) {
            let band = ramp_color(ramp, r);
            for i in 0..3 {
                toon[i] += u[i] * band[i];
            }
        }
        diffuse = std::array::from_fn(|i| diffuse[i] + (toon[i] - diffuse[i]) * k);
    }
    std::array::from_fn(|i| {
        diffuse[i] + p.indirect_diffuse[i] + p.specular[i] + p.transmission[i] + p.emission[i]
    })
}

/// Per-pixel inputs for a whole frame; every slice has the same length.
#[derive(Clone, Copy, Debug)]
pub struct Frame<'a> {
    pub direct_diffuse: &'a [[f32; 3]],
    pub indirect_diffuse: &'a [[f32; 3]],
    pub specular: &'a [[f32; 3]],
    pub transmission: &'a [[f32; 3]],
    pub emission: &'a [[f32; 3]],
    pub light_u: &'a [[[f32; 3]; LIGHT_SLOTS]],
    pub light_response: &'a [[f32; LIGHT_SLOTS]],
    /// Material index plus one; 0 (background) is left unstylized.
    pub material_id: &'a [u32],
}

/// Stylizes a frame. `materials` is the scene's material table (`Scene::materials`).
/// Panics when a slice length differs from `material_id.len()` or an id is out of range.
pub fn stylize_image(materials: &[Material], f: &Frame) -> Vec<[f32; 3]> {
    (0..f.material_id.len())
        .map(|i| {
            let p = PixelInput {
                direct_diffuse: f.direct_diffuse[i],
                indirect_diffuse: f.indirect_diffuse[i],
                specular: f.specular[i],
                transmission: f.transmission[i],
                emission: f.emission[i],
                light_u: f.light_u[i],
                light_response: f.light_response[i],
            };
            let layers: &[StylizationLayer] = match f.material_id[i] {
                0 => &[],
                id => &materials[id as usize - 1].stylization,
            };
            stylize(layers, &p)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ramp(feather: f32, light_wrap: f32) -> ToonRamp {
        ToonRamp {
            thresholds: vec![0.5],
            feather,
            palette: vec![[0.2; 3], [1.0; 3]],
            light_wrap,
        }
    }

    fn layers(k: f32, ramp: ToonRamp) -> Vec<StylizationLayer> {
        vec![
            StylizationLayer::HybridSurface(HybridSurface {
                diffuse: k,
                ..Default::default()
            }),
            StylizationLayer::ToonRamp(ramp),
        ]
    }

    const PI: f32 = std::f32::consts::PI;

    /// A white surface lit by one unit light in slot 0 at response `r`.
    fn px(r: f32) -> PixelInput {
        let mut p = PixelInput {
            direct_diffuse: [r / PI; 3],
            indirect_diffuse: [0.1; 3],
            specular: [0.05; 3],
            ..Default::default()
        };
        p.light_u[0] = [1.0 / PI; 3];
        p.light_response[0] = r;
        p
    }

    #[test]
    fn without_layers_the_output_is_the_physical_sum() {
        let p = px(0.7);
        let sum = 0.7 / PI + 0.1 + 0.05;
        assert_eq!(stylize(&[], &p), [sum; 3]);
        assert_eq!(stylize(&layers(0.0, ramp(0.0, 0.0)), &p), [sum; 3]);
    }

    #[test]
    fn full_toon_snaps_the_diffuse_to_bands() {
        let l = layers(1.0, ramp(0.0, 0.0));
        let rest = 0.1 + 0.05;
        assert!((stylize(&l, &px(0.4))[0] - (0.2 / PI + rest)).abs() < 1e-6);
        assert!((stylize(&l, &px(0.6))[0] - (1.0 / PI + rest)).abs() < 1e-6);
    }

    #[test]
    fn blend_is_continuous_between_physical_and_toon() {
        let p = px(0.4);
        let at = |k| stylize(&layers(k, ramp(0.0, 0.0)), &p)[0];
        let (a, b) = (at(0.0), at(1.0));
        assert!((at(0.5) - 0.5 * (a + b)).abs() < 1e-6);
    }

    #[test]
    fn feather_softens_and_light_wrap_lights_the_dark_side() {
        let hard = stylize(&layers(1.0, ramp(0.0, 0.0)), &px(0.49))[0];
        let soft = stylize(&layers(1.0, ramp(0.2, 0.0)), &px(0.49))[0];
        assert!(soft > hard);
        let wrapped = stylize(&layers(1.0, ramp(0.0, 0.5)), &px(0.4))[0];
        assert!(wrapped > hard);
    }

    #[test]
    fn each_light_is_banded_on_its_own_and_shadow_keeps_the_dark_band() {
        let l = layers(1.0, ramp(0.0, 0.0));
        let mut p = px(0.6);
        // A second light, shadowed: potential 1/pi but response 0 (dark band 0.2), not black.
        p.light_u[1] = [1.0 / PI; 3];
        let out = stylize(&l, &p)[0];
        assert!((out - ((1.0 + 0.2) / PI + 0.15)).abs() < 1e-6, "{out}");
        // Two lit lights add their bands; the response is never summed first.
        p.light_response[1] = 0.6;
        let out = stylize(&l, &p)[0];
        assert!((out - (2.0 / PI + 0.15)).abs() < 1e-6, "{out}");
    }

    #[test]
    fn background_and_material_lookup() {
        let toon = Material {
            stylization: layers(1.0, ramp(0.0, 0.0)),
            ..Default::default()
        };
        let materials = [Material::default(), toon];
        let p = px(0.6);
        let dd = [p.direct_diffuse; 3];
        let z = [[0.0; 3]; 3];
        let (u, r) = ([p.light_u; 3], [p.light_response; 3]);
        let out = stylize_image(
            &materials,
            &Frame {
                direct_diffuse: &dd,
                indirect_diffuse: &z,
                specular: &z,
                transmission: &z,
                emission: &z,
                light_u: &u,
                light_response: &r,
                material_id: &[0, 1, 2],
            },
        );
        assert_eq!(out[0], [0.6 / PI; 3]); // background: untouched
        assert_eq!(out[1], [0.6 / PI; 3]); // material without layers
        assert!((out[2][0] - 1.0 / PI).abs() < 1e-6); // toon material
    }
}
