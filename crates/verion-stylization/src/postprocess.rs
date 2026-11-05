//! PostProcess passes (REQ-STY-011): screen-space passes that run after the per-pixel
//! `stylize` and read neighboring pixels. Non-physical; Reference mode never calls them.

use verion_scene::{Material, StylizationLayer};

/// Primary-hit AOVs a post pass reads. Every slice has `width * height` entries, row-major from
/// the top-left, and a miss is zero in every field (see the renderer's `Aovs`).
#[derive(Clone, Copy, Debug)]
pub struct PostFrame<'a> {
    pub width: usize,
    /// Distance along the camera's forward axis.
    pub depth: &'a [f32],
    /// World-space unit normals.
    pub normal: &'a [[f32; 3]],
    /// Instance index plus one.
    pub object_id: &'a [u32],
    /// Material index plus one; 0 is the background.
    pub material_id: &'a [u32],
}

/// Draws each material's `OutlineStyle` (REQ-STY-009, minimal version) over `beauty`, with the
/// opacity `HybridSurface::outline`. A pixel is an outline pixel when a neighbor within `width`
/// pixels is background, is farther by more than `depth_threshold` (relative), or, on the same
/// object, has a normal more than `crease_angle` away. So the line lands on the nearer object and
/// the background is never touched. Panics when a slice length differs from `material_id.len()`
/// or an id is out of range.
///
/// shortcut: the line width is in pixels, so it thins out as the resolution grows, and thin faces
/// or shallow creases can be missed; scale it with the resolution when that matters.
pub fn outline(materials: &[Material], f: &PostFrame, beauty: &mut [[f32; 3]]) {
    let n = f.material_id.len();
    let height = n / f.width;
    for (i, px) in beauty.iter_mut().enumerate() {
        let id = f.material_id[i];
        if id == 0 {
            continue;
        }
        let layers = &materials[id as usize - 1].stylization;
        let opacity = layers.iter().find_map(|l| match l {
            StylizationLayer::HybridSurface(h) => Some(h.outline),
            _ => None,
        });
        let style = layers.iter().find_map(|l| match l {
            StylizationLayer::OutlineStyle(o) => Some(o),
            _ => None,
        });
        let (Some(opacity), Some(style)) = (opacity, style) else {
            continue;
        };
        if opacity <= 0.0 {
            continue;
        }
        let (x, y) = ((i % f.width) as i32, (i / f.width) as i32);
        let r = style.width.ceil() as i32;
        let min_cos = style.crease_angle.to_radians().cos();
        let mut edge = false;
        'scan: for dy in -r..=r {
            for dx in -r..=r {
                let (nx, ny) = (x + dx, y + dy);
                let inside =
                    nx >= 0 && ny >= 0 && (nx as usize) < f.width && (ny as usize) < height;
                if (dx, dy) == (0, 0)
                    || !inside
                    || (dx * dx + dy * dy) as f32 > style.width * style.width
                {
                    continue;
                }
                let j = ny as usize * f.width + nx as usize;
                let same_object = f.object_id[j] == f.object_id[i];
                let cos = (0..3).map(|c| f.normal[i][c] * f.normal[j][c]).sum::<f32>();
                if f.material_id[j] == 0
                    || f.depth[j] > f.depth[i] * (1.0 + style.depth_threshold)
                    || (same_object && cos < min_cos)
                {
                    edge = true;
                    break 'scan;
                }
            }
        }
        if edge {
            *px = std::array::from_fn(|c| px[c] + (style.color[c] - px[c]) * opacity);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use verion_scene::{HybridSurface, OutlineStyle};

    fn material(opacity: f32, style: OutlineStyle) -> Material {
        Material {
            stylization: vec![
                StylizationLayer::HybridSurface(HybridSurface {
                    outline: opacity,
                    ..Default::default()
                }),
                StylizationLayer::OutlineStyle(style),
            ],
            ..Default::default()
        }
    }

    fn style(width: f32) -> OutlineStyle {
        OutlineStyle {
            color: [0.0; 3],
            width,
            ..Default::default()
        }
    }

    /// One row of pixels with the given depth, object id, normal x-tilt (degrees) and material id.
    fn run(materials: &[Material], px: &[(f32, u32, f32, u32)], beauty: f32) -> Vec<f32> {
        let depth: Vec<f32> = px.iter().map(|p| p.0).collect();
        let object_id: Vec<u32> = px.iter().map(|p| p.1).collect();
        let normal: Vec<[f32; 3]> = px
            .iter()
            .map(|p| {
                let a = p.2.to_radians();
                if p.3 == 0 {
                    [0.0; 3]
                } else {
                    [a.sin(), 0.0, a.cos()]
                }
            })
            .collect();
        let material_id: Vec<u32> = px.iter().map(|p| p.3).collect();
        let mut img = vec![[beauty; 3]; px.len()];
        let frame = PostFrame {
            width: px.len(),
            depth: &depth,
            normal: &normal,
            object_id: &object_id,
            material_id: &material_id,
        };
        outline(materials, &frame, &mut img);
        img.iter().map(|c| c[0]).collect()
    }

    const BG: (f32, u32, f32, u32) = (0.0, 0, 0.0, 0);
    const OBJ: (f32, u32, f32, u32) = (1.0, 1, 0.0, 1);

    #[test]
    fn silhouette_line_grows_into_the_object_by_its_width() {
        let row = [BG, BG, OBJ, OBJ, OBJ, OBJ];
        let one = run(&[material(1.0, style(1.0))], &row, 1.0);
        assert_eq!(one, [1.0, 1.0, 0.0, 1.0, 1.0, 1.0]); // background untouched
        let two = run(&[material(1.0, style(2.0))], &row, 1.0);
        assert_eq!(two, [1.0, 1.0, 0.0, 0.0, 1.0, 1.0]);
    }

    #[test]
    fn the_nearer_object_gets_the_line_at_a_depth_jump() {
        let near = (1.0, 1, 0.0, 1);
        let far = (2.0, 2, 0.0, 1); // 2 > 1 * 1.05
        let out = run(&[material(1.0, style(1.0))], &[near, near, far, far], 1.0);
        assert_eq!(out, [1.0, 0.0, 1.0, 1.0]);
        // A jump below the threshold is not an outline.
        let close = (1.02, 2, 0.0, 1);
        let out = run(
            &[material(1.0, style(1.0))],
            &[near, near, close, close],
            1.0,
        );
        assert_eq!(out, [1.0; 4]);
    }

    #[test]
    fn creases_need_the_same_object_and_a_wide_enough_angle() {
        let flat = (1.0, 1, 0.0, 1);
        let bent = (1.0, 1, 90.0, 1);
        let mat = |angle| {
            material(
                1.0,
                OutlineStyle {
                    crease_angle: angle,
                    ..style(1.0)
                },
            )
        };
        assert_eq!(
            run(&[mat(45.0)], &[flat, flat, bent, bent], 1.0),
            [1.0, 0.0, 0.0, 1.0]
        );
        assert_eq!(run(&[mat(120.0)], &[flat, flat, bent, bent], 1.0), [1.0; 4]);
        // The same bend between two objects is not a crease.
        let other = (1.0, 2, 90.0, 1);
        assert_eq!(
            run(&[mat(45.0)], &[flat, flat, other, other], 1.0),
            [1.0; 4]
        );
    }

    #[test]
    fn opacity_blends_and_a_material_without_the_style_stays_clean() {
        let row = [BG, OBJ, OBJ, OBJ];
        let half = run(&[material(0.5, style(1.0))], &row, 1.0);
        assert_eq!(half, [1.0, 0.5, 1.0, 1.0]);
        assert_eq!(run(&[material(0.0, style(1.0))], &row, 1.0), [1.0; 4]);
        let none = Material {
            stylization: vec![StylizationLayer::HybridSurface(HybridSurface {
                outline: 1.0,
                ..Default::default()
            })],
            ..Default::default()
        };
        assert_eq!(run(&[none], &row, 1.0), [1.0; 4]);
    }
}
