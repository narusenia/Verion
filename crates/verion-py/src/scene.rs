//! `verion.Scene`: builds the Scene IR from numpy arrays. Indices are positions in each list
//! (meshes, images, materials, instances, lights), in the order they were added.

use std::sync::{Arc, Mutex, MutexGuard};

use numpy::PyReadonlyArrayDyn;
use pyo3::{
    exceptions::{PyIndexError, PyValueError},
    prelude::*,
    types::PyDict,
};
use verion_scene::{
    BaseBsdf, Camera, ColorSpace, Image, ImageId, Instance, Light, Material, Mesh,
    Scene as CoreScene,
};

pub(crate) fn value_err(e: impl std::fmt::Display) -> PyErr {
    PyValueError::new_err(e.to_string())
}

/// Floats of a float32 array in C order, whatever its shape; `per` is the group size the caller
/// needs (3 for positions, 2 for UVs), checked against the length.
fn floats(a: &PyReadonlyArrayDyn<f32>, per: usize, what: &str) -> PyResult<Vec<f32>> {
    let v: Vec<f32> = a.as_array().iter().copied().collect();
    if !v.len().is_multiple_of(per) {
        return Err(value_err(format!(
            "{what} has {} values, not a multiple of {per}",
            v.len()
        )));
    }
    Ok(v)
}

fn groups<const N: usize>(a: &PyReadonlyArrayDyn<f32>, what: &str) -> PyResult<Vec<[f32; N]>> {
    Ok(floats(a, N, what)?.as_chunks::<N>().0.to_vec())
}

/// A 3x4 or 4x4 row-major float32 matrix (the last row of a 4x4 is dropped).
fn transform(a: &PyReadonlyArrayDyn<f32>) -> PyResult<verion_scene::Transform> {
    let v = floats(a, 1, "transform")?;
    if v.len() != 12 && v.len() != 16 {
        return Err(value_err("a transform has 12 (3x4) or 16 (4x4) values"));
    }
    let cols = v.len() / if v.len() == 12 { 3 } else { 4 };
    Ok(std::array::from_fn(|r| {
        std::array::from_fn(|c| v[r * cols + c])
    }))
}

#[pyclass(module = "verion")]
pub struct Scene {
    pub(crate) inner: Arc<Mutex<CoreScene>>,
    warnings: Mutex<Vec<String>>,
}

impl Scene {
    pub(crate) fn lock(&self) -> MutexGuard<'_, CoreScene> {
        self.inner.lock().unwrap_or_else(|p| p.into_inner())
    }

    fn warn(&self, w: impl IntoIterator<Item = String>) {
        self.warnings
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .extend(w);
    }
}

fn image_id(s: &CoreScene, index: usize) -> PyResult<ImageId> {
    s.image_ids()
        .get(index)
        .copied()
        .ok_or_else(|| PyIndexError::new_err(format!("no image {index}")))
}

fn opt_image(s: &CoreScene, v: &Bound<'_, PyAny>) -> PyResult<Option<ImageId>> {
    if v.is_none() {
        return Ok(None);
    }
    image_id(s, v.extract()?).map(Some)
}

fn mesh_from(
    positions: &PyReadonlyArrayDyn<f32>,
    indices: &PyReadonlyArrayDyn<u32>,
    normals: Option<&PyReadonlyArrayDyn<f32>>,
    uvs: Option<&PyReadonlyArrayDyn<f32>>,
) -> PyResult<Mesh> {
    Mesh::new(
        groups::<3>(positions, "positions")?,
        normals.map(|n| groups::<3>(n, "normals")).transpose()?,
        uvs.map(|n| groups::<2>(n, "uvs")).transpose()?,
        indices.as_array().iter().copied().collect(),
    )
    .map_err(value_err)
}

fn corner_mesh_from(
    positions: &PyReadonlyArrayDyn<f32>,
    tri_vertices: &PyReadonlyArrayDyn<u32>,
    normals: Option<&PyReadonlyArrayDyn<f32>>,
    uvs: Option<&PyReadonlyArrayDyn<f32>>,
) -> PyResult<Mesh> {
    let tri: Vec<u32> = tri_vertices.as_array().iter().copied().collect();
    let n = normals.map(|n| groups::<3>(n, "normals")).transpose()?;
    let t = uvs.map(|n| groups::<2>(n, "uvs")).transpose()?;
    Mesh::from_corners(
        &groups::<3>(positions, "positions")?,
        &tri,
        n.as_deref(),
        t.as_deref(),
    )
    .map_err(value_err)
}

/// The material keywords of `add_material` / `set_material`.
fn material_from(
    s: &CoreScene,
    kw: Option<&Bound<'_, PyDict>>,
    warnings: &mut Vec<String>,
) -> PyResult<Material> {
    let mut b = BaseBsdf::default();
    let mut layers = Vec::new();
    let (mut json, mut images): (Option<String>, Vec<usize>) = (None, Vec::new());
    for (k, v) in kw.into_iter().flat_map(|d| d.iter()) {
        let key: String = k.extract()?;
        let rgb = |v: &Bound<'_, PyAny>| -> PyResult<[f32; 3]> {
            let a: Vec<f32> = v.extract()?;
            <[f32; 3]>::try_from(a).map_err(|_| value_err(format!("{key} takes three values")))
        };
        match key.as_str() {
            "base_color" => b.base_color = rgb(&v)?,
            "emission" => b.emission = rgb(&v)?,
            "sheen_color" => b.sheen_color = rgb(&v)?,
            "metallic" => b.metallic = v.extract()?,
            "roughness" => b.roughness = v.extract()?,
            "transmission" => b.transmission = v.extract()?,
            "ior" => b.ior = v.extract()?,
            "clearcoat" => b.clearcoat = v.extract()?,
            "clearcoat_roughness" => b.clearcoat_roughness = v.extract()?,
            "sheen_roughness" => b.sheen_roughness = v.extract()?,
            "dispersion" => b.dispersion = v.extract()?,
            "opacity" => b.opacity = v.extract::<f32>()?.clamp(0.0, 1.0),
            "normal_scale" => b.normal_scale = v.extract()?,
            "base_color_texture" => b.base_color_texture = opt_image(s, &v)?,
            "metallic_roughness_texture" => b.metallic_roughness_texture = opt_image(s, &v)?,
            "emission_texture" => b.emission_texture = opt_image(s, &v)?,
            "normal_texture" => b.normal_texture = opt_image(s, &v)?,
            "stylization" => json = Some(v.extract()?),
            "stylization_images" => images = v.extract()?,
            _ => return Err(value_err(format!("unknown material property {key}"))),
        }
    }
    if let Some(text) = json {
        // Texture indices in the JSON are positions in `stylization_images`.
        let mut resolve = |i: usize| -> Result<Option<ImageId>, String> {
            let idx = *images
                .get(i)
                .ok_or(format!("texture {i} is not in stylization_images"))?;
            image_id(s, idx).map(Some).map_err(|e| e.to_string())
        };
        let (parsed, w) =
            verion_render_io::parse_stylization_json(&text, s.working_space(), &mut resolve)
                .map_err(value_err)?;
        for l in &parsed {
            l.validate().map_err(|e| value_err(format!("{e:?}")))?;
        }
        warnings.extend(w);
        layers = parsed;
    }
    Ok(Material {
        base: b,
        stylization: layers,
        ..Default::default()
    })
}

#[allow(clippy::too_many_arguments)]
fn light_from(
    s: &CoreScene,
    kind: &str,
    color: [f32; 3],
    intensity: f32,
    position: Option<[f32; 3]>,
    direction: Option<[f32; 3]>,
    inner_cone: f32,
    outer_cone: f32,
    image: Option<usize>,
) -> PyResult<Light> {
    let need = |v: Option<[f32; 3]>, what: &str| {
        v.ok_or_else(|| value_err(format!("a {kind} light needs {what}")))
    };
    Ok(match kind {
        "point" => Light::Point {
            position: need(position, "position")?,
            color,
            intensity,
        },
        "directional" => Light::Directional {
            direction: need(direction, "direction")?,
            color,
            intensity,
        },
        "spot" => Light::Spot {
            position: need(position, "position")?,
            direction: need(direction, "direction")?,
            color,
            intensity,
            inner_cone,
            outer_cone,
        },
        "environment" => Light::Environment {
            color: color.map(|c| c * intensity),
        },
        "environment_map" => Light::EnvironmentMap {
            image: image_id(
                s,
                image.ok_or_else(|| value_err("an environment_map needs image"))?,
            )?,
            scale: intensity,
        },
        _ => {
            return Err(value_err(format!(
                "unknown light kind {kind} (point, directional, spot, environment, environment_map)"
            )));
        }
    })
}

fn space_from(name: &str) -> PyResult<ColorSpace> {
    match name {
        "rec709" => Ok(ColorSpace::LinearRec709),
        "acescg" => Ok(ColorSpace::AcesCg),
        _ => Err(value_err("working space is rec709 or acescg")),
    }
}

#[pymethods]
impl Scene {
    #[new]
    #[pyo3(signature = (working_space = "rec709"))]
    fn new(working_space: &str) -> PyResult<Self> {
        let mut s = CoreScene::new();
        s.set_working_space(space_from(working_space)?);
        Ok(Self {
            inner: Arc::new(Mutex::new(s)),
            warnings: Mutex::default(),
        })
    }

    /// Loads a glTF file (`.gltf` / `.glb`) the way `render-cli` does, for comparison and tests.
    #[staticmethod]
    #[pyo3(signature = (path, working_space = "rec709"))]
    fn from_gltf(path: &str, working_space: &str) -> PyResult<Self> {
        let import = verion_render_io::load_gltf_in(path.as_ref(), space_from(working_space)?)
            .map_err(|e| value_err(format!("load {path}: {e}")))?;
        Ok(Self {
            inner: Arc::new(Mutex::new(import.scene)),
            warnings: Mutex::new(import.warnings),
        })
    }

    /// Notes the importers and converters left (unsupported features, substituted values), drained.
    fn take_warnings(&self) -> Vec<String> {
        std::mem::take(&mut *self.warnings.lock().unwrap_or_else(|p| p.into_inner()))
    }

    /// `positions` (N,3) float32, `indices` three per triangle (uint32), optional `normals` (N,3)
    /// and `uvs` (N,2) per vertex. Returns the mesh index.
    #[pyo3(signature = (positions, indices, normals = None, uvs = None))]
    fn add_mesh(
        &self,
        positions: PyReadonlyArrayDyn<f32>,
        indices: PyReadonlyArrayDyn<u32>,
        normals: Option<PyReadonlyArrayDyn<f32>>,
        uvs: Option<PyReadonlyArrayDyn<f32>>,
    ) -> PyResult<usize> {
        let mesh = mesh_from(&positions, &indices, normals.as_ref(), uvs.as_ref())?;
        let mut s = self.lock();
        s.add_mesh(mesh);
        Ok(s.meshes().len() - 1)
    }

    /// Replaces a mesh. The same triangles with moved vertices update in place (deformation).
    #[pyo3(signature = (index, positions, indices, normals = None, uvs = None))]
    fn set_mesh(
        &self,
        index: usize,
        positions: PyReadonlyArrayDyn<f32>,
        indices: PyReadonlyArrayDyn<u32>,
        normals: Option<PyReadonlyArrayDyn<f32>>,
        uvs: Option<PyReadonlyArrayDyn<f32>>,
    ) -> PyResult<()> {
        let mesh = mesh_from(&positions, &indices, normals.as_ref(), uvs.as_ref())?;
        let mut s = self.lock();
        let id = s
            .mesh_id(index)
            .ok_or_else(|| PyIndexError::new_err(format!("no mesh {index}")))?;
        s.set_mesh(id, mesh);
        Ok(())
    }

    /// A mesh from per-corner data, as DCC tools store it: shared vertex `positions` (V,3),
    /// `tri_vertices` (3 per triangle, vertex indices), `normals` (3 per triangle, one per corner)
    /// and `uvs` (one per corner). Equal corners weld into one vertex.
    #[pyo3(signature = (positions, tri_vertices, normals = None, uvs = None))]
    fn add_mesh_corners(
        &self,
        positions: PyReadonlyArrayDyn<f32>,
        tri_vertices: PyReadonlyArrayDyn<u32>,
        normals: Option<PyReadonlyArrayDyn<f32>>,
        uvs: Option<PyReadonlyArrayDyn<f32>>,
    ) -> PyResult<usize> {
        let mesh = corner_mesh_from(&positions, &tri_vertices, normals.as_ref(), uvs.as_ref())?;
        let mut s = self.lock();
        s.add_mesh(mesh);
        Ok(s.meshes().len() - 1)
    }

    /// `set_mesh` for `add_mesh_corners` data.
    #[pyo3(signature = (index, positions, tri_vertices, normals = None, uvs = None))]
    fn set_mesh_corners(
        &self,
        index: usize,
        positions: PyReadonlyArrayDyn<f32>,
        tri_vertices: PyReadonlyArrayDyn<u32>,
        normals: Option<PyReadonlyArrayDyn<f32>>,
        uvs: Option<PyReadonlyArrayDyn<f32>>,
    ) -> PyResult<()> {
        let mesh = corner_mesh_from(&positions, &tri_vertices, normals.as_ref(), uvs.as_ref())?;
        let mut s = self.lock();
        let id = s
            .mesh_id(index)
            .ok_or_else(|| PyIndexError::new_err(format!("no mesh {index}")))?;
        s.set_mesh(id, mesh);
        Ok(())
    }

    /// A linear RGB image (H,W,3) or RGBA (H,W,4; alpha is dropped) float32, first row on top.
    /// Returns the image index.
    fn add_image(&self, pixels: PyReadonlyArrayDyn<f32>) -> PyResult<usize> {
        let a = pixels.as_array();
        let shape = a.shape().to_vec();
        let &[h, w, c] = shape.as_slice() else {
            return Err(value_err("an image has shape (height, width, channels)"));
        };
        if !(c == 3 || c == 4) {
            return Err(value_err("an image has 3 (RGB) or 4 (RGBA) channels"));
        }
        let flat: Vec<f32> = a.iter().copied().collect();
        let px = flat.chunks_exact(c).map(|p| [p[0], p[1], p[2]]).collect();
        let image = Image::new(w as u32, h as u32, px).map_err(value_err)?;
        let mut s = self.lock();
        s.add_image(image);
        Ok(s.images().len() - 1)
    }

    /// Loads an equirectangular `.hdr` / `.exr` into the scene's working space. Returns the
    /// image index.
    fn add_hdri(&self, path: &str) -> PyResult<usize> {
        let mut s = self.lock();
        let image = verion_render_io::load_hdri(path.as_ref(), s.working_space())
            .map_err(|e| value_err(format!("hdri {path}: {e}")))?;
        s.add_image(image);
        Ok(s.images().len() - 1)
    }

    /// Keywords: base_color, metallic, roughness, transmission, ior, clearcoat, clearcoat_roughness,
    /// sheen_color, sheen_roughness, dispersion, opacity, emission, normal_scale, the `*_texture` image
    /// indices (base_color, metallic_roughness, emission, normal), `stylization` (the JSON of a
    /// `VERION_materials_stylization` object) and `stylization_images` (image indices for the
    /// textures that JSON names). Returns the material index.
    #[pyo3(signature = (**kw))]
    fn add_material(&self, kw: Option<&Bound<'_, PyDict>>) -> PyResult<usize> {
        let mut w = Vec::new();
        let mut s = self.lock();
        let m = material_from(&s, kw, &mut w)?;
        s.add_material(m);
        drop(s);
        self.warn(w);
        Ok(self.lock().materials().len() - 1)
    }

    #[pyo3(signature = (index, **kw))]
    fn set_material(&self, index: usize, kw: Option<&Bound<'_, PyDict>>) -> PyResult<()> {
        let mut w = Vec::new();
        let mut s = self.lock();
        let id = s
            .material_id(index)
            .ok_or_else(|| PyIndexError::new_err(format!("no material {index}")))?;
        let m = material_from(&s, kw, &mut w)?;
        s.set_material(id, m);
        drop(s);
        self.warn(w);
        Ok(())
    }

    /// `transform` is object-to-world, 3x4 or 4x4 row-major. Returns the instance index.
    fn add_instance(
        &self,
        mesh: usize,
        material: usize,
        transform_: PyReadonlyArrayDyn<f32>,
    ) -> PyResult<usize> {
        let t = transform(&transform_)?;
        let mut s = self.lock();
        let inst = self.instance_of(&s, mesh, material, t)?;
        s.add_instance(inst).map_err(value_err)?;
        Ok(s.instances().len() - 1)
    }

    fn set_instance(
        &self,
        index: usize,
        mesh: usize,
        material: usize,
        transform_: PyReadonlyArrayDyn<f32>,
    ) -> PyResult<()> {
        let t = transform(&transform_)?;
        let mut s = self.lock();
        let id = s
            .instance_id(index)
            .ok_or_else(|| PyIndexError::new_err(format!("no instance {index}")))?;
        let inst = self.instance_of(&s, mesh, material, t)?;
        s.set_instance(id, inst).map_err(value_err)
    }

    /// Light linking: the instance receives the light groups in `mask` (a light shines on an instance
    /// when their masks share a bit; all ones is the default).
    fn set_instance_light_mask(&self, index: usize, mask: u32) -> PyResult<()> {
        let mut s = self.lock();
        let id = s
            .instance_id(index)
            .ok_or_else(|| PyIndexError::new_err(format!("no instance {index}")))?;
        s.set_instance_light_mask(id, mask);
        Ok(())
    }

    /// The light group an emissive instance (an area light) emits as; see `set_instance_light_mask`.
    fn set_instance_emit_mask(&self, index: usize, mask: u32) -> PyResult<()> {
        let mut s = self.lock();
        let id = s
            .instance_id(index)
            .ok_or_else(|| PyIndexError::new_err(format!("no instance {index}")))?;
        s.set_instance_emit_mask(id, mask);
        Ok(())
    }

    /// Light linking and an IES profile for light `index`. `link_mask` is the light's group bits;
    /// `ies` is the text of an LM-63 file (point and spot lights) with `frame`, the light's world
    /// frame as three rows x, y, z (vertical angle 0 along -z, horizontal angle 0 along +x). The
    /// light's intensity is multiplied by the file's candela value times `ies_scale`.
    #[pyo3(signature = (index, link_mask = u32::MAX, ies = None, frame = None, ies_scale = 1.0))]
    fn set_light_extra(
        &self,
        index: usize,
        link_mask: u32,
        ies: Option<&str>,
        frame: Option<[[f32; 3]; 3]>,
        ies_scale: f32,
    ) -> PyResult<()> {
        let mut s = self.lock();
        let id = s
            .light_id(index)
            .ok_or_else(|| PyIndexError::new_err(format!("no light {index}")))?;
        let ies = match ies {
            Some(text) => {
                let profile = verion_scene::IesProfile::parse(text).map_err(value_err)?;
                let profile = profile.clone().scaled(profile.peak() * ies_scale);
                let frame = frame.unwrap_or([[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]);
                Some((std::sync::Arc::new(profile), frame))
            }
            None => None,
        };
        s.set_light_extra(id, verion_scene::LightExtra { link_mask, ies });
        Ok(())
    }

    /// kind: point, directional, spot, environment (a uniform sky) or environment_map (`image`).
    /// `intensity` is glTF's: candela for point and spot, lux for directional, a multiplier for
    /// the environments. Cone angles are half-angles in radians.
    #[pyo3(signature = (kind, color = [1.0; 3], intensity = 1.0, position = None, direction = None, inner_cone = 0.0, outer_cone = std::f32::consts::FRAC_PI_4, image = None))]
    #[allow(clippy::too_many_arguments)]
    fn add_light(
        &self,
        kind: &str,
        color: [f32; 3],
        intensity: f32,
        position: Option<[f32; 3]>,
        direction: Option<[f32; 3]>,
        inner_cone: f32,
        outer_cone: f32,
        image: Option<usize>,
    ) -> PyResult<usize> {
        let mut s = self.lock();
        let l = light_from(
            &s, kind, color, intensity, position, direction, inner_cone, outer_cone, image,
        )?;
        s.add_light(l);
        Ok(s.lights().len() - 1)
    }

    #[pyo3(signature = (index, kind, color = [1.0; 3], intensity = 1.0, position = None, direction = None, inner_cone = 0.0, outer_cone = std::f32::consts::FRAC_PI_4, image = None))]
    #[allow(clippy::too_many_arguments)]
    fn set_light(
        &self,
        index: usize,
        kind: &str,
        color: [f32; 3],
        intensity: f32,
        position: Option<[f32; 3]>,
        direction: Option<[f32; 3]>,
        inner_cone: f32,
        outer_cone: f32,
        image: Option<usize>,
    ) -> PyResult<()> {
        let mut s = self.lock();
        let id = s
            .light_id(index)
            .ok_or_else(|| PyIndexError::new_err(format!("no light {index}")))?;
        let l = light_from(
            &s, kind, color, intensity, position, direction, inner_cone, outer_cone, image,
        )?;
        s.set_light(id, l);
        Ok(())
    }

    /// Camera rays that leave the scene return black (a transparent film); the sky still lights it.
    fn set_transparent_background(&self, on: bool) {
        self.lock().set_transparent_background(on);
    }

    /// The virtual main light that Toon bands take from the environment map (ADR-0020).
    /// `direction` points toward the light in world space (Y up); `strength` scales the estimate.
    #[pyo3(signature = (virtual_light = true, direction = None, strength = 1.0))]
    fn set_stylization_world(
        &self,
        virtual_light: bool,
        direction: Option<[f32; 3]>,
        strength: f32,
    ) -> PyResult<()> {
        if !strength.is_finite() || strength < 0.0 {
            return Err(value_err("strength must be finite and not negative"));
        }
        self.lock()
            .set_stylization_world(verion_scene::StylizationWorld {
                virtual_light,
                direction,
                strength,
            });
        Ok(())
    }

    /// `transform` is camera-to-world (3x4 or 4x4), looking down -z. `shift` is the lens shift in
    /// half-image extents (`Camera::shift`).
    #[pyo3(signature = (transform_, vertical_fov, focus_distance = 1.0, aperture_radius = 0.0, shift = [0.0; 2]))]
    fn set_camera(
        &self,
        transform_: PyReadonlyArrayDyn<f32>,
        vertical_fov: f32,
        focus_distance: f32,
        aperture_radius: f32,
        shift: [f32; 2],
    ) -> PyResult<()> {
        let cam = Camera {
            shift,
            transform: transform(&transform_)?,
            vertical_fov,
            focus_distance,
            aperture_radius,
        };
        if !(vertical_fov > 0.0 && vertical_fov < std::f32::consts::PI)
            || focus_distance <= 0.0
            || aperture_radius < 0.0
        {
            return Err(value_err("camera values out of range"));
        }
        self.lock().set_camera(cam);
        Ok(())
    }

    /// Points the camera at the whole scene from +z (for scenes without a camera).
    fn frame_camera(&self) {
        self.lock().frame_camera();
    }

    /// Counts of what the scene holds, for logs and tests.
    fn stats<'py>(&self, py: Python<'py>) -> PyResult<Bound<'py, PyDict>> {
        let s = self.lock();
        let d = PyDict::new(py);
        d.set_item("meshes", s.meshes().len())?;
        d.set_item("images", s.images().len())?;
        d.set_item("materials", s.materials().len())?;
        d.set_item("instances", s.instances().len())?;
        d.set_item("lights", s.lights().len())?;
        let tris: usize = s
            .instances()
            .iter()
            .map(|i| s.meshes()[i.mesh.index()].indices().len() / 3)
            .sum();
        d.set_item("triangles", tris)?;
        Ok(d)
    }
}

impl Scene {
    fn instance_of(
        &self,
        s: &CoreScene,
        mesh: usize,
        material: usize,
        t: verion_scene::Transform,
    ) -> PyResult<Instance> {
        Ok(Instance {
            mesh: s
                .mesh_id(mesh)
                .ok_or_else(|| PyIndexError::new_err(format!("no mesh {mesh}")))?,
            material: s
                .material_id(material)
                .ok_or_else(|| PyIndexError::new_err(format!("no material {material}")))?,
            transform: t,
        })
    }
}
