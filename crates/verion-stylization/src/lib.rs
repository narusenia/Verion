//! Stylization Pass (REQ-STY-007): composes the final color of a primary hit from the lighting
//! AOVs and the material's stylization layers. GPU independent. Reference mode never calls it.
//!
//! Implemented so far: `HybridSurface::diffuse` blending the direct diffuse toward a `ToonRamp`
//! applied per light, and `ShadowPalette` grading the shadowed part of the direct and indirect
//! diffuse (strength from `HybridSurface::shadow`), `RimLight` adding a rim to the final color,
//! and `StylizedSpecular` replacing the specular by per-light banded highlights.
//! The other components pass through unchanged until their layers land.

mod postprocess;

pub use postprocess::{ColorGrade, PostFrame, color_grade, outline};

use verion_scene::{
    Camera, ColorAdjust, HybridSurface, Image, LIGHT_SLOTS, Material, RimLight, ShadowPalette,
    StylizationLayer, StylizedSpecular, ToonRamp,
};

/// The first-hit lighting split of one pixel, in the working space (see `LightingAovs`).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct PixelInput {
    /// World-space unit normal of the hit (zero on the background).
    pub normal: [f32; 3],
    /// World-space unit vector from the hit toward the camera (see `view_directions`).
    pub view: [f32; 3],
    /// The normal's components along the camera's right and up axes, for the `MatCap` lookup.
    pub normal_view: [f32; 2],
    /// Base color at the hit (the Albedo AOV).
    pub albedo: [f32; 3],
    /// The material's mean indirect diffuse divided by albedo over the frame (see
    /// `stylize_image`). `HybridSurface::gi` flattens the indirect diffuse toward `albedo * ambient`.
    pub ambient: [f32; 3],
    pub direct_diffuse: [f32; 3],
    pub indirect_diffuse: [f32; 3],
    pub specular: [f32; 3],
    pub transmission: [f32; 3],
    pub emission: [f32; 3],
    /// Per light slot: the diffuse contribution without cos and without shadowing.
    pub light_u: [[f32; 3]; LIGHT_SLOTS],
    /// Per light slot: cos(N, L) times visibility. The physical diffuse is `u * response`.
    pub light_response: [f32; LIGHT_SLOTS],
    /// Per light slot: the specular contribution without cos and without shadowing.
    pub light_s: [[f32; 3]; LIGHT_SLOTS],
    /// Per light slot: unit vector from the hit toward the light (zero where it never reaches).
    pub light_dir: [[f32; 3]; LIGHT_SLOTS],
    /// Per light slot: share of the contribution that is not shadowed, the visibility of `light_s`.
    pub light_lit: [f32; LIGHT_SLOTS],
}

/// World-space unit vector from the surface toward the camera for every pixel, row-major from the
/// top-left. Pinhole model: it depends on the pixel only, not on depth.
/// shortcut: the lens aperture is ignored, so with depth of field the vector is the chief ray's;
/// use the per-pixel position and the camera origin when a layer needs the exact one.
pub fn view_directions(camera: &Camera, width: usize, height: usize) -> Vec<[f32; 3]> {
    let t = (camera.vertical_fov * 0.5).tan();
    let aspect = width as f32 / height as f32;
    let m = &camera.transform;
    (0..width * height)
        .map(|i| {
            let (x, y) = ((i % width) as f32, (i / width) as f32);
            let d = [
                (2.0 * (x + 0.5) / width as f32 - 1.0) * aspect * t,
                (1.0 - 2.0 * (y + 0.5) / height as f32) * t,
                -1.0,
            ];
            let n = (d[0] * d[0] + d[1] * d[1] + 1.0).sqrt();
            // The camera-to-world rotation is the 3x3 block; negate to point toward the camera.
            std::array::from_fn(|r| -(m[r][0] * d[0] + m[r][1] * d[1] + m[r][2] * d[2]) / n)
        })
        .collect()
}

fn lum(c: [f32; 3]) -> f32 {
    0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
}

/// Hue shift, saturation and value change of a linear RGB color. Value is the largest channel, so
/// HDR values keep their scale and black stays black.
pub fn grade(c: [f32; 3], a: &ColorAdjust) -> [f32; 3] {
    let v = c[0].max(c[1]).max(c[2]);
    if v <= 0.0 {
        return c;
    }
    let min = c[0].min(c[1]).min(c[2]);
    let chroma = v - min;
    let s = chroma / v;
    let h = if chroma <= 0.0 {
        0.0
    } else if v == c[0] {
        ((c[1] - c[2]) / chroma).rem_euclid(6.0)
    } else if v == c[1] {
        (c[2] - c[0]) / chroma + 2.0
    } else {
        (c[0] - c[1]) / chroma + 4.0
    };
    let h = (h + a.hue_shift / 60.0).rem_euclid(6.0);
    let s = (s * a.saturation).min(1.0);
    let v = v * a.value;
    let f = |n: f32| {
        let k = (n + h).rem_euclid(6.0);
        v * (1.0 - s * k.min(4.0 - k).clamp(0.0, 1.0))
    };
    [f(5.0), f(3.0), f(1.0)]
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
    stylize_with(layers, p, &[])
}

/// `stylize` with the scene's images (`Scene::images`) for the layers that sample one; a layer
/// whose image is not in `images` is skipped.
pub fn stylize_with(layers: &[StylizationLayer], p: &PixelInput, images: &[Image]) -> [f32; 3] {
    let hybrid = hybrid_of(layers);
    let mut diffuse = p.direct_diffuse;
    // `gi` flattens the indirect diffuse toward a uniform ambient fill before the layers grade it.
    let mut indirect: [f32; 3] = std::array::from_fn(|i| {
        let flat = p.albedo[i] * p.ambient[i];
        p.indirect_diffuse[i] + (flat - p.indirect_diffuse[i]) * hybrid.gi
    });
    // The physical specular is the direct highlights plus the reflections; only the highlights are
    // stylized. shortcut: the direct part is rebuilt from the slots (`s * cos * lit`, cos taken at
    // the slot's mean direction), exact for a single light per slot and approximate for the pooled
    // area and environment slot, where the BSDF-sampled share stays with the reflections.
    let dot = |a: [f32; 3], b: [f32; 3]| a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    let mut specular: [f32; 3] = std::array::from_fn(|i| {
        let est: f32 = (0..LIGHT_SLOTS)
            .map(|k| p.light_s[k][i] * dot(p.normal, p.light_dir[k]).max(0.0) * p.light_lit[k])
            .sum();
        est.clamp(0.0, p.specular[i].max(0.0))
    });
    let reflections: [f32; 3] = std::array::from_fn(|i| p.specular[i] - specular[i]);
    let mut reflection_kept = 1.0 - hybrid.reflection;
    let mut added = [0.0f32; 3];
    // Layers apply in the order the material lists them, so the same kind may appear twice.
    for layer in layers {
        match layer {
            // The outline needs neighboring pixels, so it is a post pass, not part of `stylize`.
            StylizationLayer::HybridSurface(_) | StylizationLayer::OutlineStyle(_) => {}
            StylizationLayer::ToonRamp(ramp) => {
                let mut toon = [0.0f32; 3];
                for (u, &r) in p.light_u.iter().zip(&p.light_response) {
                    let band = ramp_color(ramp, r);
                    for i in 0..3 {
                        toon[i] += u[i] * band[i];
                    }
                }
                let k = hybrid.diffuse;
                diffuse = std::array::from_fn(|i| diffuse[i] + (toon[i] - diffuse[i]) * k);
            }
            StylizationLayer::ShadowPalette(ShadowPalette {
                direct,
                indirect: ind,
            }) => {
                // Shadowness: how much of the light the pixel could receive it does not (0 lit, 1 dark).
                let potential: [f32; 3] =
                    std::array::from_fn(|i| p.light_u.iter().map(|u| u[i]).sum());
                let full = lum(potential);
                let w = if full > 1.0e-6 {
                    (1.0 - lum(diffuse) / full).clamp(0.0, 1.0)
                } else {
                    0.0
                } * hybrid.shadow;
                let mix = |c: [f32; 3], a: &ColorAdjust| {
                    let g = grade(c, a);
                    std::array::from_fn(|i| c[i] + (g[i] - c[i]) * w)
                };
                diffuse = mix(diffuse, direct);
                indirect = mix(indirect, ind);
            }
            StylizationLayer::RimLight(rim) => {
                let r = rim_light(rim, p);
                added = std::array::from_fn(|i| added[i] + r[i]);
            }
            StylizationLayer::MatCap(mc) => {
                let Some(image) = images.get(mc.image.index()) else {
                    continue;
                };
                // shortcut: the picture stands in for the diffuse and the specular together, so it
                // goes into the diffuse term and the specular terms fade out; a second picture for
                // the specular (REQ-STY-012, later) takes over the specular term instead.
                let m = matcap_color(mc.albedo, image, p);
                let k = mc.strength;
                diffuse = std::array::from_fn(|i| diffuse[i] + (m[i] - diffuse[i]) * k);
                indirect = indirect.map(|c| c * (1.0 - k));
                specular = specular.map(|c| c * (1.0 - k));
                reflection_kept *= 1.0 - k;
            }
            StylizationLayer::StylizedSpecular(sp) => {
                let st = stylized_specular(sp, p);
                let k = hybrid.specular;
                specular = std::array::from_fn(|i| specular[i] + (st[i] - specular[i]) * k);
            }
        }
    }
    std::array::from_fn(|i| {
        let kept = reflections[i] * reflection_kept;
        diffuse[i] + indirect[i] + specular[i] + kept + p.transmission[i] + p.emission[i] + added[i]
    })
}

/// The `MatCap` image at the pixel's view-space normal (`u = 0.5 + 0.5 n_x`, `v = 0.5 - 0.5 n_y`),
/// bilinear, times `lerp(1, albedo, mc_albedo)`.
fn matcap_color(mc_albedo: f32, image: &Image, p: &PixelInput) -> [f32; 3] {
    let (w, h) = (image.width() as usize, image.height() as usize);
    let x = ((0.5 + 0.5 * p.normal_view[0]) * w as f32 - 0.5).clamp(0.0, (w - 1) as f32);
    let y = ((0.5 - 0.5 * p.normal_view[1]) * h as f32 - 0.5).clamp(0.0, (h - 1) as f32);
    let (x0, y0) = (x as usize, y as usize);
    let (x1, y1) = ((x0 + 1).min(w - 1), (y0 + 1).min(h - 1));
    let (fx, fy) = (x - x0 as f32, y - y0 as f32);
    let px = image.pixels();
    std::array::from_fn(|c| {
        let top = px[y0 * w + x0][c] + (px[y0 * w + x1][c] - px[y0 * w + x0][c]) * fx;
        let bottom = px[y1 * w + x0][c] + (px[y1 * w + x1][c] - px[y1 * w + x0][c]) * fx;
        let tint = 1.0 + (p.albedo[c] - 1.0) * mc_albedo;
        (top + (bottom - top) * fy) * tint
    })
}

/// HybridSurface only carries the blend strengths the other layers read; none means all 0.
fn hybrid_of(layers: &[StylizationLayer]) -> HybridSurface {
    layers
        .iter()
        .find_map(|l| match l {
            StylizationLayer::HybridSurface(h) => Some(*h),
            _ => None,
        })
        .unwrap_or_default()
}

/// The banded highlights of a `StylizedSpecular` (REQ-STY-004), summed over the light slots: a
/// slot that carries specular puts a band where the half vector H of its light and the view is
/// within `size` of the normal (`1 - N·H <= size`), and an unshadowed share of it counts.
/// Independent of the light's strength.
///
/// shortcut: a slot that pools several lights (or an area light) has the mean direction, so its
/// highlight sits where that mean points.
pub fn stylized_specular(sp: &StylizedSpecular, p: &PixelInput) -> [f32; 3] {
    let dot = |a: [f32; 3], b: [f32; 3]| a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    if sp.strength == 0.0 || dot(p.normal, p.normal) < 0.5 {
        return [0.0; 3]; // off, or no surface (a zero normal)
    }
    let mut sum = [0.0f32; 3];
    for k in 0..LIGHT_SLOTS {
        let h: [f32; 3] = std::array::from_fn(|i| p.light_dir[k][i] + p.view[i]);
        let len2 = dot(h, h);
        // A light with no specular (Lambert) or no direction (never reaches) has no highlight.
        if lum(p.light_s[k]) < 1.0e-6 || len2 < 1.0e-8 {
            continue;
        }
        let x = 1.0 - (dot(p.normal, h) / len2.sqrt()).max(0.0);
        let band = match &sp.ramp {
            // Response 1 at the center of the highlight, 0 at the edge `size`.
            Some(ramp) => {
                let r = if sp.size > 0.0 {
                    (1.0 - x / sp.size).clamp(0.0, 1.0)
                } else {
                    (x <= 0.0) as u8 as f32
                };
                ramp_color(ramp, r)
            }
            None if sp.feather > 0.0 => {
                [1.0 - smoothstep(sp.size - 0.5 * sp.feather, sp.size + 0.5 * sp.feather, x); 3]
            }
            None => [(x <= sp.size) as u8 as f32; 3],
        };
        sum = std::array::from_fn(|i| sum[i] + band[i] * p.light_lit[k]);
    }
    std::array::from_fn(|i| sp.color[i] * sp.strength * sum[i])
}

/// The rim added by a `RimLight` (REQ-STY-005): a band where the surface turns away from the
/// camera, weighted per light slot by its share of the contribution, how much it faces the light
/// and how much of it is unshadowed. Independent of the light's strength.
pub fn rim_light(rim: &RimLight, p: &PixelInput) -> [f32; 3] {
    let dot = |a: [f32; 3], b: [f32; 3]| a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    if rim.strength == 0.0 || dot(p.normal, p.normal) < 0.5 {
        return [0.0; 3]; // off, or no surface (a zero normal)
    }
    let x = 1.0 - dot(p.normal, p.view).max(0.0);
    let edge = 1.0 - rim.width;
    let band = if rim.feather > 0.0 {
        smoothstep(edge - 0.5 * rim.feather, edge + 0.5 * rim.feather, x)
    } else {
        (x >= edge) as u8 as f32
    };
    let weight = |k: usize| lum(p.light_u[k]) + lum(p.light_s[k]);
    let total: f32 = (0..LIGHT_SLOTS).map(weight).sum();
    if total <= 0.0 {
        return [0.0; 3];
    }
    let lit: f32 = (0..LIGHT_SLOTS)
        .map(|k| {
            let face = dot(p.normal, p.light_dir[k]).clamp(0.0, 1.0);
            let follow = 1.0 + (face - 1.0) * rim.follow_light;
            weight(k) / total * follow * p.light_lit[k]
        })
        .sum();
    let s = rim.strength * band * lit;
    rim.color.map(|c| c * s)
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
    pub light_s: &'a [[[f32; 3]; LIGHT_SLOTS]],
    pub light_dir: &'a [[[f32; 3]; LIGHT_SLOTS]],
    pub light_lit: &'a [[f32; LIGHT_SLOTS]],
    /// World-space unit normals (the Normal AOV).
    pub normal: &'a [[f32; 3]],
    /// Base color at the hit (the Albedo AOV).
    pub albedo: &'a [[f32; 3]],
    /// Material index plus one; 0 (background) is left unstylized.
    pub material_id: &'a [u32],
    /// The scene's images (`Scene::images`), for layers that sample one.
    pub images: &'a [Image],
    /// The camera and image width the frame was rendered with; the height follows from the length.
    pub camera: Camera,
    pub width: usize,
}

/// Stylizes a frame. `materials` is the scene's material table (`Scene::materials`).
/// Panics when a slice length differs from `material_id.len()` or an id is out of range.
pub fn stylize_image(materials: &[Material], f: &Frame) -> Vec<[f32; 3]> {
    let n = f.material_id.len();
    let view = view_directions(&f.camera, f.width, n / f.width);
    let m = &f.camera.transform;
    let right: [f32; 3] = std::array::from_fn(|r| m[r][0]);
    let up: [f32; 3] = std::array::from_fn(|r| m[r][1]);
    let dot3 = |a: [f32; 3], b: [f32; 3]| a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    // Per material: the sums of indirect diffuse and albedo, so `ambient` is a ratio of sums.
    // shortcut: a material's ambient is one value per frame, so objects sharing a material share
    // it, and it moves with the view; per-object or temporally smoothed values come with M8.
    let mut sums = vec![([0.0f32; 3], [0.0f32; 3]); materials.len()];
    for (i, &id) in f.material_id.iter().enumerate() {
        if id > 0 {
            let (ind, alb) = &mut sums[id as usize - 1];
            for c in 0..3 {
                ind[c] += f.indirect_diffuse[i][c];
                alb[c] += f.albedo[i][c];
            }
        }
    }
    let ambient: Vec<[f32; 3]> = sums
        .iter()
        .map(|(ind, alb)| {
            std::array::from_fn(|c| if alb[c] > 1e-6 { ind[c] / alb[c] } else { 0.0 })
        })
        .collect();
    (0..n)
        .map(|i| {
            let p = PixelInput {
                normal: f.normal[i],
                view: view[i],
                normal_view: [dot3(f.normal[i], right), dot3(f.normal[i], up)],
                albedo: f.albedo[i],
                ambient: match f.material_id[i] {
                    0 => [0.0; 3],
                    id => ambient[id as usize - 1],
                },
                light_s: f.light_s[i],
                light_dir: f.light_dir[i],
                light_lit: f.light_lit[i],
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
            stylize_with(layers, &p, f.images)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use verion_scene::HybridSurface;

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

    /// A surface seen edge-on (N ⟂ V) with one fully lit light in slot 0 straight along the normal.
    fn rim_px() -> PixelInput {
        let mut p = PixelInput {
            normal: [0.0, 0.0, 1.0],
            view: [1.0, 0.0, 0.0],
            ..Default::default()
        };
        p.light_u[0] = [1.0; 3];
        p.light_dir[0] = [0.0, 0.0, 1.0];
        p.light_lit[0] = 1.0;
        p
    }

    fn rim(f: impl FnOnce(&mut RimLight)) -> RimLight {
        let mut r = RimLight {
            feather: 0.0,
            ..Default::default()
        };
        f(&mut r);
        r
    }

    #[test]
    fn rim_appears_only_toward_the_silhouette() {
        let r = rim(|r| r.width = 0.3);
        assert_eq!(rim_light(&r, &rim_px()), [1.0; 3]); // N ⟂ V: x = 1
        let mut facing = rim_px();
        facing.view = [0.0, 0.0, 1.0]; // N = V: x = 0
        assert_eq!(rim_light(&r, &facing), [0.0; 3]);
        // x = 1 - cos(45°) = 0.29 is just short of the edge at 1 - 0.3 = 0.7 ... and inside at width 0.9.
        let mut slanted = rim_px();
        slanted.view = [0.5f32.sqrt(), 0.0, 0.5f32.sqrt()];
        assert_eq!(rim_light(&r, &slanted), [0.0; 3]);
        assert_eq!(rim_light(&rim(|r| r.width = 0.9), &slanted), [1.0; 3]);
    }

    #[test]
    fn rim_follows_the_light_and_its_shadow() {
        let mut away = rim_px();
        away.light_dir[0] = [0.0, 0.0, -1.0];
        assert_eq!(rim_light(&rim(|r| r.follow_light = 1.0), &away), [0.0; 3]);
        assert_eq!(rim_light(&rim(|r| r.follow_light = 0.0), &away), [1.0; 3]);
        let mut shadowed = rim_px();
        shadowed.light_lit[0] = 0.0;
        assert_eq!(rim_light(&rim(|_| {}), &shadowed), [0.0; 3]);
    }

    #[test]
    fn rim_splits_by_each_lights_share_and_scales_with_color_and_strength() {
        let mut two = rim_px();
        two.light_u[1] = [1.0; 3]; // same weight, but shadowed
        two.light_dir[1] = [0.0, 0.0, 1.0];
        let out = rim_light(
            &rim(|r| (r.color, r.strength) = ([0.5, 1.0, 2.0], 2.0)),
            &two,
        );
        assert_eq!(out, [0.5, 1.0, 2.0]); // half the share is lit: 0.5 * 2 = 1
        assert_eq!(rim_light(&rim(|r| r.strength = 0.0), &two), [0.0; 3]);
        // No surface (zero normal) or no light: nothing.
        assert_eq!(rim_light(&rim(|_| {}), &PixelInput::default()), [0.0; 3]);
    }

    /// Looking straight at a surface lit head-on by a light that carries specular.
    fn spec_px() -> PixelInput {
        let mut p = PixelInput {
            normal: [0.0, 0.0, 1.0],
            view: [0.0, 0.0, 1.0],
            ..Default::default()
        };
        p.light_s[0] = [0.1; 3];
        p.light_dir[0] = [0.0, 0.0, 1.0];
        p.light_lit[0] = 1.0;
        p
    }

    fn spec(f: impl FnOnce(&mut StylizedSpecular)) -> StylizedSpecular {
        let mut s = StylizedSpecular {
            feather: 0.0,
            ..Default::default()
        };
        f(&mut s);
        s
    }

    #[test]
    fn specular_band_sits_around_the_half_vector() {
        let s = spec(|s| s.size = 0.05);
        assert_eq!(stylized_specular(&s, &spec_px()), [1.0; 3]); // N = H
        // L along +x with V along +z: H is 45° off the normal, 1 - cos = 0.29 > 0.05.
        let mut off = spec_px();
        off.light_dir[0] = [1.0, 0.0, 0.0];
        assert_eq!(stylized_specular(&s, &off), [0.0; 3]);
        assert_eq!(stylized_specular(&spec(|s| s.size = 0.3), &off), [1.0; 3]);
    }

    #[test]
    fn specular_ramp_gives_a_core_inside_a_halo() {
        // Outside 0, halo 0.4 from response 0.3, core 1.0 from response 0.8. size 0.2.
        let ramp = ToonRamp {
            thresholds: vec![0.3, 0.8],
            feather: 0.0,
            palette: vec![[0.0; 3], [0.4; 3], [1.0; 3]],
            light_wrap: 0.0,
        };
        let s = StylizedSpecular {
            size: 0.2,
            ramp: Some(ramp),
            ..Default::default()
        };
        let mut p = spec_px();
        // L = (sin 2a, 0, cos 2a) gives H at angle a from the normal, 1 - N·H = 1 - cos a.
        let at = |p: &mut PixelInput, x: f32| {
            let a = (1.0 - x).acos();
            p.light_dir[0] = [(2.0 * a).sin(), 0.0, (2.0 * a).cos()];
            stylized_specular(&s, p)[0]
        };
        assert!((at(&mut p, 0.0) - 1.0).abs() < 1e-5); // center: response 1
        assert!((at(&mut p, 0.1) - 0.4).abs() < 1e-5); // response 0.5: halo
        assert!(at(&mut p, 0.19).abs() < 1e-5); // response 0.05: outside
        assert!(at(&mut p, 0.3).abs() < 1e-5); // beyond size
    }

    #[test]
    fn specular_needs_a_specular_light_that_reaches_the_point() {
        let mut lambert = spec_px();
        lambert.light_s[0] = [0.0; 3];
        assert_eq!(stylized_specular(&spec(|_| {}), &lambert), [0.0; 3]);
        let mut shadowed = spec_px();
        shadowed.light_lit[0] = 0.0;
        assert_eq!(stylized_specular(&spec(|_| {}), &shadowed), [0.0; 3]);
        assert_eq!(
            stylized_specular(&spec(|_| {}), &PixelInput::default()),
            [0.0; 3]
        );
        // Two lights give a highlight each; color and strength scale them.
        let mut two = spec_px();
        two.light_s[1] = [0.1; 3];
        two.light_dir[1] = [0.0, 0.0, 1.0];
        two.light_lit[1] = 1.0;
        let s = spec(|s| (s.color, s.strength) = ([0.5, 1.0, 2.0], 0.5));
        assert_eq!(stylized_specular(&s, &two), [0.5, 1.0, 2.0]);
    }

    #[test]
    fn specular_blends_with_the_physical_one_by_hybrid_specular() {
        let mut p = spec_px(); // the highlight alone: s * cos * lit = 0.2
        p.light_s[0] = [0.2; 3];
        p.specular = [0.2; 3];
        let at = |k: f32| {
            let l = [
                StylizationLayer::HybridSurface(HybridSurface {
                    specular: k,
                    ..Default::default()
                }),
                StylizationLayer::StylizedSpecular(spec(|_| {})),
            ];
            stylize(&l, &p)[0]
        };
        assert!((at(0.0) - 0.2).abs() < 1e-6);
        assert!((at(0.5) - 0.6).abs() < 1e-6); // halfway between 0.2 and the highlight 1.0
        assert!((at(1.0) - 1.0).abs() < 1e-6);
        // Without HybridSurface the specular stays physical.
        let bare = [StylizationLayer::StylizedSpecular(spec(|_| {}))];
        assert!((stylize(&bare, &p)[0] - 0.2).abs() < 1e-6);
    }

    #[test]
    fn reflections_survive_the_stylized_highlight_unless_reflection_removes_them() {
        let mut p = spec_px();
        p.specular = [0.5; 3]; // 0.1 highlight (s * cos * lit) plus 0.4 of reflections
        let at = |reflection: f32| {
            let l = [
                StylizationLayer::HybridSurface(HybridSurface {
                    specular: 1.0,
                    reflection,
                    ..Default::default()
                }),
                StylizationLayer::StylizedSpecular(spec(|_| {})),
            ];
            stylize(&l, &p)[0]
        };
        assert!((at(0.0) - 1.4).abs() < 1e-6); // band 1.0 + all 0.4 of the reflections
        assert!((at(0.5) - 1.2).abs() < 1e-6);
        assert!((at(1.0) - 1.0).abs() < 1e-6); // the old behavior: the highlight alone
        // A shadowed light's highlight is not counted as direct: the physical value stays whole.
        let mut dark = p;
        dark.light_lit[0] = 0.0;
        assert!(
            (stylize(
                &[StylizationLayer::HybridSurface(HybridSurface::TOON)],
                &dark
            )[0] - 0.5)
                .abs()
                < 1e-6
        );
    }

    /// A 2 x 2 picture (top row 0.1, 0.2; bottom row 0.3, 0.4) as the scene's only image.
    fn matcap_scene() -> (verion_scene::Scene, verion_scene::ImageId) {
        let mut scene = verion_scene::Scene::new();
        let px = [0.1, 0.2, 0.3, 0.4].map(|v| [v; 3]).to_vec();
        let id = scene.add_image(Image::new(2, 2, px).unwrap());
        (scene, id)
    }

    fn matcap(id: verion_scene::ImageId, strength: f32, albedo: f32) -> [StylizationLayer; 1] {
        [StylizationLayer::MatCap(verion_scene::MatCap {
            image: id,
            strength,
            albedo,
        })]
    }

    #[test]
    fn matcap_reads_the_picture_at_the_view_space_normal() {
        let (scene, id) = matcap_scene();
        let at = |n: [f32; 2]| {
            let p = PixelInput {
                normal_view: n,
                ..Default::default()
            };
            stylize_with(&matcap(id, 1.0, 0.0), &p, scene.images())[0]
        };
        // Facing the camera is the picture's center (the mean of the four pixels); the corners of
        // the disk are the corner pixels, with +y at the top of the picture.
        assert!((at([0.0, 0.0]) - 0.25).abs() < 1e-6);
        assert!((at([-1.0, 1.0]) - 0.1).abs() < 1e-6);
        assert!((at([1.0, 1.0]) - 0.2).abs() < 1e-6);
        assert!((at([-1.0, -1.0]) - 0.3).abs() < 1e-6);
        assert!((at([1.0, -1.0]) - 0.4).abs() < 1e-6);
    }

    #[test]
    fn matcap_replaces_the_shading_but_keeps_emission_and_transmission() {
        let (scene, id) = matcap_scene();
        let p = PixelInput {
            direct_diffuse: [0.3; 3],
            indirect_diffuse: [0.1; 3],
            specular: [0.05; 3], // reflections only: no light slot carries any
            emission: [0.2; 3],
            transmission: [0.07; 3],
            ..Default::default()
        };
        let at = |k: f32| stylize_with(&matcap(id, k, 0.0), &p, scene.images())[0];
        let rest = 0.2 + 0.07;
        assert!((at(0.0) - (0.3 + 0.1 + 0.05 + rest)).abs() < 1e-6); // physical
        assert!((at(1.0) - (0.25 + rest)).abs() < 1e-6); // the picture alone
        // Halfway: every shading term fades by half and the picture comes in at half.
        assert!((at(0.5) - (0.5 * (0.3 + 0.1 + 0.05) + 0.5 * 0.25 + rest)).abs() < 1e-6);
    }

    #[test]
    fn matcap_albedo_multiplies_the_base_color() {
        let (scene, id) = matcap_scene();
        let p = PixelInput {
            albedo: [0.5; 3],
            ..Default::default()
        };
        let at = |a: f32| stylize_with(&matcap(id, 1.0, a), &p, scene.images())[0];
        assert!((at(0.0) - 0.25).abs() < 1e-6);
        assert!((at(1.0) - 0.125).abs() < 1e-6);
        assert!((at(0.5) - 0.25 * 0.75).abs() < 1e-6);
    }

    #[test]
    fn matcap_without_its_image_is_skipped() {
        let (_, id) = matcap_scene();
        let p = px(0.4);
        assert_eq!(
            stylize(&matcap(id, 1.0, 0.0), &p),
            stylize(&[], &p),
            "no image to sample, so the shading stays physical"
        );
    }

    #[test]
    fn gi_flattens_the_indirect_diffuse_toward_albedo_times_ambient() {
        let p = PixelInput {
            albedo: [0.5; 3],
            ambient: [0.2; 3],
            indirect_diffuse: [0.3; 3],
            ..Default::default()
        };
        let at = |gi| {
            let l = [StylizationLayer::HybridSurface(HybridSurface {
                gi,
                ..Default::default()
            })];
            stylize(&l, &p)[0]
        };
        assert!((at(0.0) - 0.3).abs() < 1e-6); // physical
        assert!((at(1.0) - 0.1).abs() < 1e-6); // albedo 0.5 * ambient 0.2
        assert!((at(0.5) - 0.2).abs() < 1e-6);
    }

    #[test]
    fn ambient_is_the_ratio_of_indirect_to_albedo_over_the_material() {
        let toon = Material {
            stylization: vec![StylizationLayer::HybridSurface(HybridSurface {
                gi: 1.0,
                ..Default::default()
            })],
            ..Default::default()
        };
        // Four pixels of one material (albedo 0.5) with uneven indirect light, one background.
        let ind = [[0.1; 3], [0.2; 3], [0.4; 3], [0.5; 3], [9.0; 3]];
        let z = [[0.0; 3]; 5];
        let alb = [[0.5; 3], [0.5; 3], [0.5; 3], [0.5; 3], [0.0; 3]];
        let slots = [[[0.0; 3]; LIGHT_SLOTS]; 5];
        let resp = [[0.0; LIGHT_SLOTS]; 5];
        let out = stylize_image(
            &[toon],
            &Frame {
                direct_diffuse: &z,
                indirect_diffuse: &ind,
                specular: &z,
                transmission: &z,
                emission: &z,
                light_u: &slots,
                light_response: &resp,
                light_s: &slots,
                light_dir: &slots,
                light_lit: &resp,
                normal: &z,
                albedo: &alb,
                material_id: &[1, 1, 1, 1, 0],
                images: &[],
                camera: Camera::default(),
                width: 5,
            },
        );
        // Mean indirect 0.3 over mean albedo 0.5 is 0.6, so every pixel gets 0.5 * 0.6 = 0.3.
        assert!(
            out[..4].iter().all(|c| (c[0] - 0.3).abs() < 1e-6),
            "{out:?}"
        );
        assert_eq!(out[4], [9.0; 3]); // background untouched
    }

    #[test]
    fn layers_apply_in_order_and_a_kind_can_repeat() {
        let p = rim_px();
        let l = |s| StylizationLayer::RimLight(rim(|r| r.strength = s));
        assert_eq!(stylize(&[l(1.0)], &p), [1.0; 3]);
        assert_eq!(stylize(&[l(1.0), l(0.5)], &p), [1.5; 3]);
    }

    #[test]
    fn view_points_back_toward_the_camera() {
        let cam = Camera::default();
        // A single pixel looks straight down -z, so the view vector points to +z.
        assert_eq!(view_directions(&cam, 1, 1), [[0.0, 0.0, 1.0]]);
        // Left pixels see the scene to the left of the axis, so the view leans to the right (+x);
        // top pixels lean down (-y).
        let v = view_directions(&cam, 2, 2);
        assert!(v[0][0] > 0.0 && v[1][0] < 0.0, "x: {v:?}");
        assert!(v[0][1] < 0.0 && v[2][1] > 0.0, "y: {v:?}");
        assert!(
            v.iter()
                .all(|d| (d.iter().map(|c| c * c).sum::<f32>() - 1.0).abs() < 1e-6)
        );
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

    fn close(a: [f32; 3], b: [f32; 3]) -> bool {
        a.iter().zip(b).all(|(x, y)| (x - y).abs() < 1e-5)
    }

    #[test]
    fn grade_is_identity_by_default_and_shifts_hue() {
        let c = [0.8, 0.4, 0.2];
        assert!(close(grade(c, &ColorAdjust::default()), c));
        let boost = ColorAdjust {
            value: 5.0,
            ..Default::default()
        };
        assert_eq!(grade([0.0; 3], &boost), [0.0; 3]);
        // Red shifted by 120 degrees is green; value halves it; zero saturation is grey.
        let g = grade(
            [1.0, 0.0, 0.0],
            &ColorAdjust {
                hue_shift: 120.0,
                ..Default::default()
            },
        );
        assert!(close(g, [0.0, 1.0, 0.0]), "{g:?}");
        let g = grade(
            c,
            &ColorAdjust {
                value: 0.5,
                ..Default::default()
            },
        );
        assert!(close(g, [0.4, 0.2, 0.1]), "{g:?}");
        let g = grade(
            c,
            &ColorAdjust {
                saturation: 0.0,
                ..Default::default()
            },
        );
        assert!(close(g, [0.8; 3]), "{g:?}");
    }

    fn shadow_layers(k: f32, direct: ColorAdjust, indirect: ColorAdjust) -> Vec<StylizationLayer> {
        vec![
            StylizationLayer::HybridSurface(HybridSurface {
                shadow: k,
                ..Default::default()
            }),
            StylizationLayer::ShadowPalette(ShadowPalette { direct, indirect }),
        ]
    }

    #[test]
    fn shadow_palette_grades_only_the_shadowed_part_and_each_component_separately() {
        let dim = ColorAdjust {
            value: 0.5,
            ..Default::default()
        };
        let grey = ColorAdjust {
            saturation: 0.0,
            ..Default::default()
        };
        let tinted = |r: f32| {
            let mut p = px(r);
            p.light_u[0] = [0.8 / PI, 0.4 / PI, 0.2 / PI];
            p.direct_diffuse = p.light_u[0].map(|u| u * r);
            p.indirect_diffuse = [0.3, 0.2, 0.1];
            p
        };
        // Fully lit: nothing is graded.
        let lit = tinted(1.0);
        assert!(close(
            stylize(&shadow_layers(1.0, dim, dim), &lit),
            stylize(&[], &lit)
        ));
        // Fully shadowed: each component takes its own grade.
        let dark = tinted(0.0);
        let base = stylize(&[], &dark);
        let out = stylize(&shadow_layers(1.0, ColorAdjust::default(), dim), &dark);
        assert!(
            close(out, [base[0] - 0.15, base[1] - 0.1, base[2] - 0.05]),
            "{out:?}"
        );
        let out = stylize(&shadow_layers(1.0, ColorAdjust::default(), grey), &dark);
        assert!(
            close(out, [base[0], base[1] + 0.1, base[2] + 0.2]),
            "{out:?}"
        );
        // The strength comes from HybridSurface::shadow.
        assert!(close(stylize(&shadow_layers(0.0, dim, dim), &dark), base));
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
        let (s, dir, lit) = ([p.light_s; 3], [p.light_dir; 3], [p.light_lit; 3]);
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
                light_s: &s,
                light_dir: &dir,
                light_lit: &lit,
                normal: &z,
                albedo: &z,
                material_id: &[0, 1, 2],
                images: &[],
                camera: Camera::default(),
                width: 3,
            },
        );
        assert_eq!(out[0], [0.6 / PI; 3]); // background: untouched
        assert_eq!(out[1], [0.6 / PI; 3]); // material without layers
        assert!((out[2][0] - 1.0 / PI).abs() < 1e-6); // toon material
    }
}
