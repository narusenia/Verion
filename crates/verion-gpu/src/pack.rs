//! Host-side scene packing shared by the backends: the flat word tables the Slang kernels read
//! (layouts documented next to the bindings in `shaders/include/pt_core.slang`) and the
//! per-dispatch parameter block. Nothing here touches a GPU API, so both backends upload the same
//! bytes and the images differ only by what the hardware does.

use std::collections::HashMap;

use verion_scene::{Camera, Image, ImageId, Light, Scene, Transform};

use crate::{Adaptive, Restir};

/// Path length limit. Radiance beyond it is dropped, so closed furnaces read slightly dark.
pub const MAX_DEPTH: u32 = 8;
/// Words of the parameter block; must match `params` in `shaders/include/pt_core.slang`.
pub const PARAM_WORDS: usize = 39;
pub const MATERIAL_WORDS: usize = 22;
pub const LIGHT_WORDS: usize = 16;
/// Words per emissive triangle; must match `shaders/include/pt_core.slang`.
pub const EMITTER_WORDS: usize = 16;
/// Words per record in the instance table; must match `shaders/normals.slang`.
pub const INSTANCE_WORDS: usize = 16;

/// Environment map tables for importance sampling (empty when the scene has none).
#[derive(Default)]
pub struct Env {
    pub pixels: Vec<f32>,
    pub marginal: Vec<f32>,
    pub conditional: Vec<f32>,
    pub width: u32,
    pub height: u32,
    /// `w * h / (2 pi^2 W)`: turns a texel luminance into a solid-angle density.
    pub pdf_scale: f32,
}

/// Where one mesh sits in the concatenated vertex and index tables.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MeshRange {
    pub vertex_offset: u32,
    pub vertex_count: u32,
    pub index_offset: u32,
    pub index_count: u32,
}

/// The scene-wide constants of the parameter block.
#[derive(Clone, Copy, Debug)]
pub struct SceneInfo {
    pub light_count: u32,
    pub emitter_count: u32,
    pub env_width: u32,
    pub env_height: u32,
    pub env_pdf_scale: f32,
    /// Environment lights summed into one uniform sky.
    pub sky: [f32; 3],
}

/// The camera as the shaders read it, replaceable without touching the rest of the scene.
#[derive(Clone, Copy, Debug)]
pub struct View {
    /// tan(fov/2) at 2, the camera-to-world rows from 4 (0 and 1 are the image size, filled per dispatch).
    pub camera: [f32; 16],
    pub aperture: f32,
    pub focus: f32,
}

impl View {
    pub fn new(cam: &Camera) -> Self {
        let mut camera = [0.0f32; 16];
        camera[2] = (cam.vertical_fov * 0.5).tan();
        for (dst, src) in camera[4..].iter_mut().zip(cam.transform.iter().flatten()) {
            *dst = *src;
        }
        Self {
            camera,
            aperture: cam.aperture_radius,
            focus: cam.focus_distance,
        }
    }

    /// The camera record of the normal and AOV kernels, with the image size filled in.
    pub fn camera_record(&self, width: u32, height: u32) -> [f32; 16] {
        let mut camera = self.camera;
        camera[0] = width as f32;
        camera[1] = height as f32;
        camera
    }
}

/// A scene flattened into the tables the kernels read.
pub struct Packed {
    pub positions: Vec<f32>,
    pub indices: Vec<u32>,
    pub uvs: Vec<f32>,
    pub vnormals: Vec<f32>,
    /// `INSTANCE_WORDS` per instance.
    pub instances: Vec<u32>,
    pub materials: Vec<f32>,
    pub lights: Vec<u32>,
    pub emitters: Vec<f32>,
    pub emit_cdf: Vec<f32>,
    pub env: Env,
    pub texels: Vec<f32>,
    /// 4 words per texture: texel offset, width, height, mip level count.
    pub tex_info: Vec<u32>,
    /// Image index per texture slot.
    pub texture_images: Vec<usize>,
    pub meshes: Vec<MeshRange>,
    /// Per instance, in table order: its mesh index and object-to-world transform.
    pub tlas: Vec<(usize, Transform)>,
    pub info: SceneInfo,
    pub view: View,
}

fn world(t: &Transform, p: [f32; 3]) -> [f32; 3] {
    std::array::from_fn(|r| t[r][0] * p[0] + t[r][1] * p[1] + t[r][2] * p[2] + t[r][3])
}

fn luminance(c: [f32; 3]) -> f32 {
    0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
}

/// Sampling tables over `luminance * sin(theta)`: a marginal CDF over rows and one CDF per row.
fn build_env(scene: &Scene) -> Result<Env, String> {
    let mut maps = scene.lights().iter().filter_map(|l| match *l {
        Light::EnvironmentMap { image, scale } => Some((image, scale)),
        _ => None,
    });
    let first = maps.next();
    if maps.next().is_some() {
        return Err("only one environment map is supported".into());
    }
    let Some((id, scale)) = first else {
        return Ok(Env::default());
    };
    let image = scene
        .images()
        .get(id.index())
        .ok_or("environment map refers to a missing image")?;
    let (w, h) = (image.width() as usize, image.height() as usize);
    let pixels: Vec<f32> = image.pixels().iter().flatten().map(|v| v * scale).collect();

    let mut rows = vec![0.0f64; h];
    let mut conditional = vec![0.0f32; w * h];
    for (j, row) in rows.iter_mut().enumerate() {
        let sin_theta = (((j as f64) + 0.5) / h as f64 * std::f64::consts::PI).sin();
        let weights: Vec<f64> = (0..w)
            .map(|i| {
                f64::from(luminance([
                    pixels[3 * (j * w + i)],
                    pixels[3 * (j * w + i) + 1],
                    pixels[3 * (j * w + i) + 2],
                ])) * sin_theta
            })
            .collect();
        *row = weights.iter().sum();
        let mut running = 0.0;
        for (i, wgt) in weights.iter().enumerate() {
            running += wgt;
            // A black row is never chosen; a uniform CDF keeps the search well defined anyway.
            conditional[j * w + i] = if *row > 0.0 {
                (running / *row) as f32
            } else {
                (i + 1) as f32 / w as f32
            };
        }
        conditional[j * w + w - 1] = 1.0;
    }
    let total: f64 = rows.iter().sum();
    if total <= 0.0 {
        return Ok(Env::default()); // an all-black map lights nothing
    }
    let mut running = 0.0;
    let mut marginal: Vec<f32> = rows
        .iter()
        .map(|r| {
            running += r / total;
            running as f32
        })
        .collect();
    marginal[h - 1] = 1.0;
    let pdf_scale = ((w * h) as f64 / (2.0 * std::f64::consts::PI.powi(2) * total)) as f32;
    Ok(Env {
        pixels,
        marginal,
        conditional,
        width: w as u32,
        height: h as u32,
        pdf_scale,
    })
}

/// Box-filtered mip chain of `image`, level 0 first. Returns the texels (rgb) and the level count.
fn mip_chain(image: &Image) -> (Vec<f32>, u32) {
    let (mut w, mut h) = (image.width() as usize, image.height() as usize);
    let mut level = image.pixels().to_vec();
    let mut texels = Vec::new();
    let mut levels = 0;
    loop {
        texels.extend(level.iter().flatten());
        levels += 1;
        if w == 1 && h == 1 {
            return (texels, levels);
        }
        let (nw, nh) = ((w / 2).max(1), (h / 2).max(1));
        let mut next = Vec::with_capacity(nw * nh);
        for y in 0..nh {
            for x in 0..nw {
                let mut sum = [0.0f32; 3];
                for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                    let p = level[(2 * y + dy).min(h - 1) * w + (2 * x + dx).min(w - 1)];
                    sum.iter_mut().zip(p).for_each(|(s, v)| *s += v);
                }
                next.push(sum.map(|s| s / 4.0));
            }
        }
        (level, w, h) = (next, nw, nh);
    }
}

/// Vertex tables of every mesh, concatenated.
pub struct Geometry {
    pub positions: Vec<f32>,
    pub indices: Vec<u32>,
    pub uvs: Vec<f32>,
    pub vnormals: Vec<f32>,
    pub meshes: Vec<MeshRange>,
}

pub fn pack_geometry(scene: &Scene) -> Geometry {
    let mut g = Geometry {
        positions: Vec::new(),
        indices: Vec::new(),
        uvs: Vec::new(),
        vnormals: Vec::new(),
        meshes: Vec::new(),
    };
    for mesh in scene.meshes() {
        g.meshes.push(MeshRange {
            vertex_offset: (g.positions.len() / 3) as u32,
            vertex_count: mesh.positions().len() as u32,
            index_offset: g.indices.len() as u32,
            index_count: mesh.indices().len() as u32,
        });
        g.positions.extend(mesh.positions().iter().flatten());
        match mesh.uvs() {
            Some(uv) => g.uvs.extend(uv.iter().flatten()),
            None => g
                .uvs
                .extend(std::iter::repeat_n(0.0, mesh.positions().len() * 2)),
        }
        match mesh.normals() {
            Some(n) => g.vnormals.extend(n.iter().flatten()),
            None => g
                .vnormals
                .extend(std::iter::repeat_n(0.0, mesh.positions().len() * 3)),
        }
        g.indices.extend_from_slice(mesh.indices());
    }
    g
}

/// Emissive world-space triangles and their selection CDF.
pub struct Emitters {
    pub words: Vec<f32>,
    pub cdf: Vec<f32>,
    /// Per instance: its first emitter + 1, or 0 when it does not emit.
    pub bases: Vec<u32>,
}

impl Emitters {
    pub fn count(&self) -> u32 {
        self.cdf.len() as u32
    }
}

pub fn pack_emitters(scene: &Scene) -> Emitters {
    let mut words: Vec<f32> = Vec::new();
    let mut powers: Vec<f32> = Vec::new(); // area * radiance per emissive triangle
    let mut bases = Vec::with_capacity(scene.instances().len());
    for inst in scene.instances() {
        let base = &scene.materials()[inst.material.index()].base;
        let le = base.emission;
        let radiance = le[0] + le[1] + le[2];
        // A textured emitter has no constant radiance to sample, so only BSDF sampling finds it.
        if radiance <= 0.0 || base.emission_texture.is_some() {
            bases.push(0);
            continue;
        }
        let mesh = &scene.meshes()[inst.mesh.index()];
        bases.push(powers.len() as u32 + 1);
        for tri in mesh.indices().as_chunks::<3>().0 {
            let [a, b, c] =
                [0, 1, 2].map(|k| world(&inst.transform, mesh.positions()[tri[k] as usize]));
            let (e1, e2) = (
                [b[0] - a[0], b[1] - a[1], b[2] - a[2]],
                [c[0] - a[0], c[1] - a[1], c[2] - a[2]],
            );
            let cross = [
                e1[1] * e2[2] - e1[2] * e2[1],
                e1[2] * e2[0] - e1[0] * e2[2],
                e1[0] * e2[1] - e1[1] * e2[0],
            ];
            let area =
                0.5 * (cross[0] * cross[0] + cross[1] * cross[1] + cross[2] * cross[2]).sqrt();
            powers.push(area * radiance);
            // Degenerate triangles keep their slot (area 0) so primitive index maps to a record.
            words.extend(a.into_iter().chain(b).chain(c).chain(le));
            words.extend([area, 0.0, 0.0, 0.0]);
        }
    }
    // Selection probability proportional to emitted power; the CDF drives light sampling.
    let total: f32 = powers.iter().sum();
    let mut cdf = Vec::with_capacity(powers.len());
    let mut running = 0.0;
    for (record, power) in words
        .as_chunks_mut::<EMITTER_WORDS>()
        .0
        .iter_mut()
        .zip(&powers)
    {
        record[13] = power / total;
        running += power / total;
        cdf.push(running);
    }
    if let Some(last) = cdf.last_mut() {
        *last = 1.0;
    }
    Emitters { words, cdf, bases }
}

/// The instance table and, per instance, its mesh index and transform for the TLAS.
pub fn pack_instances(
    scene: &Scene,
    meshes: &[MeshRange],
    emitter_bases: &[u32],
) -> (Vec<u32>, Vec<(usize, Transform)>) {
    let mut table = vec![0u32; scene.instances().len() * INSTANCE_WORDS];
    let mut tlas = Vec::new();
    for ((record, inst), base) in table
        .chunks_mut(INSTANCE_WORDS)
        .zip(scene.instances())
        .zip(emitter_bases)
    {
        let range = meshes[inst.mesh.index()];
        record[0] = range.vertex_offset;
        record[1] = range.index_offset;
        record[2] = inst.material.index() as u32;
        record[3] = *base;
        for (word, v) in record[4..].iter_mut().zip(inst.transform.iter().flatten()) {
            *word = v.to_bits();
        }
        tlas.push((inst.mesh.index(), inst.transform));
    }
    (table, tlas)
}

/// The material table and the textures it refers to.
pub struct Materials {
    pub materials: Vec<f32>,
    pub texels: Vec<f32>,
    /// 4 words per texture: texel offset, width, height, mip level count.
    pub tex_info: Vec<u32>,
    /// Image index per texture slot, to tell whether the texture tables changed.
    pub images: Vec<usize>,
}

/// With `textures` false the mip chains are not built (`texels` and `tex_info` stay empty): an
/// update compares `images` first and pays for the textures only when they changed.
pub fn pack_materials(scene: &Scene, textures: bool) -> Result<Materials, String> {
    // Every referenced image becomes one texture with a full mip chain.
    let mut texture_of: HashMap<usize, u32> = HashMap::new();
    let mut texels: Vec<f32> = Vec::new();
    let mut tex_info: Vec<u32> = Vec::new();
    let mut images: Vec<usize> = Vec::new();
    let mut texture = |id: Option<ImageId>| -> Result<f32, String> {
        let Some(id) = id else { return Ok(0.0) };
        let slot = match texture_of.get(&id.index()) {
            Some(&slot) => slot,
            None => {
                let image = scene
                    .images()
                    .get(id.index())
                    .ok_or("material refers to a missing image")?;
                let slot = texture_of.len() as u32;
                if textures {
                    let (chain, levels) = mip_chain(image);
                    tex_info.extend([
                        (texels.len() / 3) as u32,
                        image.width(),
                        image.height(),
                        levels,
                    ]);
                    texels.extend(chain);
                }
                texture_of.insert(id.index(), slot);
                images.push(id.index());
                slot
            }
        };
        Ok(slot as f32 + 1.0)
    };
    let mut materials = Vec::with_capacity(scene.materials().len() * MATERIAL_WORDS);
    for m in scene.materials() {
        let b = &m.base;
        let (c, e) = (b.base_color, b.emission);
        let tex = [
            texture(b.base_color_texture)?,
            texture(b.metallic_roughness_texture)?,
            texture(b.emission_texture)?,
        ];
        let normal_texture = texture(b.normal_texture)?;
        materials.extend([
            c[0],
            c[1],
            c[2],
            e[0],
            e[1],
            e[2],
            b.metallic,
            b.roughness,
            b.transmission,
            b.ior,
            tex[0],
            tex[1],
            tex[2],
            normal_texture,
            b.normal_scale,
            b.clearcoat,
            b.clearcoat_roughness,
            b.sheen_roughness,
            b.sheen_color[0],
            b.sheen_color[1],
            b.sheen_color[2],
            b.dispersion,
        ]);
    }
    debug_assert_eq!(materials.len(), scene.materials().len() * MATERIAL_WORDS);
    Ok(Materials {
        materials,
        texels,
        tex_info,
        images,
    })
}

/// The next-event table of delta lights and the uniform sky.
pub struct LightTable {
    pub lights: Vec<u32>,
    pub sky: [f32; 3],
}

pub fn pack_lights(scene: &Scene) -> LightTable {
    // Environment lights are summed into one uniform sky; the rest go to the NEE table.
    let mut sky = [0.0f32; 3];
    let mut lights = Vec::new();
    let mut strengths = Vec::new(); // per light in `lights`, to rank them for the light slots
    for light in scene.lights() {
        let mut cone = [0.0f32; 4]; // axis xyz and the angular falloff scale, for spot lights
        let mut offset = 0.0;
        let (kind, color, intensity, vector) = match *light {
            Light::Point {
                position,
                color,
                intensity,
            } => (0u32, color, intensity, position),
            Light::Directional {
                direction,
                color,
                intensity,
            } => (1, color, intensity, direction),
            Light::Spot {
                position,
                direction,
                color,
                intensity,
                inner_cone,
                outer_cone,
            } => {
                let len = direction.iter().map(|c| c * c).sum::<f32>().sqrt();
                let axis = direction.map(|c| c / len);
                // glTF falloff: saturate(cos * scale + offset), squared in the shader.
                let scale = 1.0 / (inner_cone.cos() - outer_cone.cos()).max(1.0e-3);
                cone = [axis[0], axis[1], axis[2], scale];
                offset = -outer_cone.cos() * scale;
                (2, color, intensity, position)
            }
            Light::EnvironmentMap { .. } => continue, // see `build_env`
            Light::Environment { color } => {
                sky.iter_mut().zip(color).for_each(|(s, c)| *s += c);
                continue;
            }
        };
        let words: [u32; LIGHT_WORDS] = std::array::from_fn(|i| match i {
            0 => kind,
            1..=3 => color[i - 1].to_bits(),
            4 => intensity.to_bits(),
            5..=7 => vector[i - 5].to_bits(),
            8..=11 => cone[i - 8].to_bits(),
            12 => offset.to_bits(),
            _ => 0,
        });
        lights.extend(words);
        strengths.push(luminance(color) * intensity);
    }
    // The strongest lights get their own light slots whatever their order in the scene; the
    // weaker ones share the last of those slots (word 13). The sort is stable, so equals keep
    // their order. shortcut: strength is color times intensity, ignoring distance and cone.
    let mut ranked: Vec<usize> = (0..strengths.len()).collect();
    ranked.sort_by(|&a, &b| strengths[b].total_cmp(&strengths[a]));
    for (rank, &i) in ranked.iter().enumerate() {
        lights[i * LIGHT_WORDS + 13] = rank.min(2) as u32;
    }
    LightTable { lights, sky }
}

/// The scene-wide constants for the current lights and emitters.
pub fn scene_info(light_table: &LightTable, emitters: &Emitters, env: &Env) -> SceneInfo {
    SceneInfo {
        light_count: (light_table.lights.len() / LIGHT_WORDS) as u32,
        emitter_count: emitters.count(),
        env_width: env.width,
        env_height: env.height,
        env_pdf_scale: env.pdf_scale,
        sky: light_table.sky,
    }
}

/// Environment sampling tables of `scene` (empty without an environment map).
pub fn pack_env(scene: &Scene) -> Result<Env, String> {
    build_env(scene)
}

/// Identifies the environment map (image and scale), so an update can skip rebuilding its
/// sampling tables when only other lights changed.
pub fn env_key(scene: &Scene) -> Option<(usize, u32)> {
    scene.lights().iter().find_map(|l| match *l {
        Light::EnvironmentMap { image, scale } => Some((image.index(), scale.to_bits())),
        _ => None,
    })
}

/// Flattens `scene` into the kernel tables. The error is a message for the backend's scene error.
pub fn pack(scene: &Scene) -> Result<Packed, String> {
    if scene.instances().is_empty() {
        return Err("scene has no instances".into());
    }
    let g = pack_geometry(scene);
    let emitters = pack_emitters(scene);
    let (instances, tlas) = pack_instances(scene, &g.meshes, &emitters.bases);
    let m = pack_materials(scene, true)?;
    let light_table = pack_lights(scene);
    let env = build_env(scene)?;
    let info = scene_info(&light_table, &emitters, &env);
    Ok(Packed {
        positions: g.positions,
        indices: g.indices,
        uvs: g.uvs,
        vnormals: g.vnormals,
        instances,
        materials: m.materials,
        lights: light_table.lights,
        emitters: emitters.words,
        emit_cdf: emitters.cdf,
        env,
        texels: m.texels,
        tex_info: m.tex_info,
        texture_images: m.images,
        meshes: g.meshes,
        tlas,
        info,
        view: View::new(scene.camera()),
    })
}

/// What a batch of scene changes makes a backend redo (REQ-ACC-003). Each flag is a table to
/// repack and upload or a structure to rebuild; everything else is reused as it is.
///
/// | change | reused | redone |
/// |---|---|---|
/// | camera | everything | the view (and the history of the integrator) |
/// | material | BLAS, TLAS, vertex tables | material and texture tables, emitters, instance table |
/// | light | BLAS, TLAS, tables | light table, sky, environment map |
/// | instance transform | every BLAS | instance table, TLAS, emitters |
/// | mesh deformation | every other BLAS | vertex tables, that BLAS, TLAS, emitters |
/// | geometry | pipelines | everything else |
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct UpdatePlan {
    /// Meshes or instances were added or re-pointed: rebuild every table and structure.
    pub full: bool,
    pub materials: bool,
    pub lights: bool,
    pub emitters: bool,
    pub instances: bool,
    /// Vertex tables are rewritten in place (same sizes).
    pub vertices: bool,
    /// Mesh indices whose BLAS is rebuilt.
    pub blases: Vec<usize>,
    pub tlas: bool,
    pub camera: bool,
}

impl UpdatePlan {
    pub fn new(changes: &verion_scene::Changes) -> Self {
        let mut p = Self {
            camera: changes.camera,
            lights: changes.lights,
            ..Self::default()
        };
        if changes.geometry {
            p.full = true;
            p.materials = true;
            p.lights = true;
            p.emitters = true;
            p.instances = true;
            p.vertices = true;
            p.tlas = true;
            return p;
        }
        if !changes.materials.is_empty() {
            p.materials = true;
            p.emitters = true;
        }
        if !changes.instances.is_empty() {
            p.instances = true;
            p.tlas = true;
            p.emitters = true;
        }
        if !changes.deformed.is_empty() {
            p.vertices = true;
            p.blases = changes.deformed.iter().map(|m| m.index()).collect();
            p.tlas = true;
            p.emitters = true;
        }
        // Emitters carry the instance table's emitter bases.
        p.instances |= p.emitters;
        p
    }

    pub fn is_empty(&self) -> bool {
        *self == Self::default()
    }
}

/// The parameter block of an accumulation, with the per-dispatch words (6, 30, 31 and 35) zero.
pub fn base_params(
    info: &SceneInfo,
    view: &View,
    (width, height): (u32, u32),
    lighting: bool,
    multiscatter: bool,
    adaptive: Option<Adaptive>,
    restir: Option<Restir>,
) -> [u32; PARAM_WORDS] {
    let mut params = [0u32; PARAM_WORDS];
    params[0] = width;
    params[1] = height;
    params[2] = view.camera[2].to_bits();
    params[3] = view.aperture.to_bits();
    params[4] = view.focus.to_bits();
    params[5] = info.light_count;
    params[7] = MAX_DEPTH;
    for (dst, src) in params[8..20].iter_mut().zip(&view.camera[4..16]) {
        *dst = src.to_bits();
    }
    for (dst, src) in params[20..23].iter_mut().zip(info.sky) {
        *dst = src.to_bits();
    }
    params[23] = info.emitter_count;
    params[24] = info.env_width;
    params[25] = info.env_height;
    params[26] = info.env_pdf_scale.to_bits();
    // Footprint of one pixel per unit of travelled distance, for texture filtering.
    params[27] = (2.0 * view.camera[2] / height as f32).to_bits();
    params[28] = lighting as u32;
    params[29] = multiscatter as u32;
    if let Some(a) = adaptive {
        params[32] = 1;
        params[33] = a.threshold.to_bits();
        params[34] = a.min_spp;
    }
    if let Some(r) = restir {
        params[36] = u32::from(r.di) | (u32::from(r.gi) << 1);
        params[37] = r.candidates;
        params[38] = r.history;
    }
    params
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plan_follows_the_reuse_table() {
        use verion_scene::Changes;
        let p = UpdatePlan::new(&Changes {
            camera: true,
            ..Changes::default()
        });
        assert!(p.camera && !p.materials && !p.tlas && p.blases.is_empty() && !p.full);
        let p = UpdatePlan::new(&Changes {
            lights: true,
            ..Changes::default()
        });
        assert!(p.lights && !p.emitters && !p.tlas && !p.vertices);
        let p = UpdatePlan::new(&Changes {
            geometry: true,
            ..Changes::default()
        });
        assert!(p.full && p.tlas && p.vertices);
        assert!(UpdatePlan::new(&Changes::default()).is_empty());
    }

    #[test]
    fn mip_chain_ends_at_one_texel_and_averages() {
        let image = Image::new(2, 2, vec![[1.0; 3], [3.0; 3], [5.0; 3], [7.0; 3]]).unwrap();
        let (texels, levels) = mip_chain(&image);
        assert_eq!(levels, 2);
        assert_eq!(texels.len(), (4 + 1) * 3);
        assert_eq!(&texels[12..], &[4.0; 3]);
    }

    #[test]
    fn base_params_carry_the_view_and_leave_dispatch_words_clear() {
        let info = SceneInfo {
            light_count: 2,
            emitter_count: 5,
            env_width: 0,
            env_height: 0,
            env_pdf_scale: 0.0,
            sky: [0.1, 0.2, 0.3],
        };
        let view = View::new(&Camera::default());
        let p = base_params(
            &info,
            &view,
            (64, 32),
            true,
            false,
            Some(Adaptive::default()),
            Some(Restir::default()),
        );
        assert_eq!((p[0], p[1], p[5], p[23]), (64, 32, 2, 5));
        assert_eq!((p[28], p[29], p[32], p[34]), (1, 0, 1, 16));
        assert_eq!((p[6], p[30], p[31], p[35]), (0, 0, 0, 0));
        assert_eq!((p[36], p[37], p[38]), (1, 4, 4));
        let gi = Restir {
            gi: true,
            ..Restir::default()
        };
        let p = base_params(&info, &view, (64, 32), false, false, None, Some(gi));
        assert_eq!(p[36], 3);
        assert_eq!(f32::from_bits(p[21]), 0.2);
    }
}
