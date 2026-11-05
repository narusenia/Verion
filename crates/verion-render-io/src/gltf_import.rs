//! glTF 2.0 -> Scene IR (REQ-IO-001). Unsupported features become warnings, not errors.

use std::{collections::HashMap, fmt, path::Path};

use crate::stylization_ext;
use gltf::{Document, camera::Projection, khr_lights_punctual::Kind, mesh::Mode};
use verion_scene::{
    BaseBsdf, Camera, ColorSpace, IDENTITY, Image, ImageId, Instance, Light, Material, MaterialId,
    Mesh, MeshError, MeshId, Scene, SceneError, Transform,
};

/// Extensions this importer understands; any other one in `extensionsUsed` is warned about.
const SUPPORTED: [&str; 7] = [
    stylization_ext::NAME,
    "KHR_lights_punctual",
    "KHR_materials_transmission",
    "KHR_materials_ior",
    "KHR_materials_emissive_strength",
    "KHR_materials_clearcoat",
    "KHR_materials_sheen",
];

pub struct Import {
    pub scene: Scene,
    pub warnings: Vec<String>,
}

#[derive(Debug)]
pub enum Error {
    /// The file is not valid glTF, or an external buffer could not be read.
    Gltf(String),
    Mesh {
        node: usize,
        source: MeshError,
    },
    Scene(SceneError),
    /// `VERION_materials_stylization` holds an invalid value.
    Stylization {
        material: String,
        why: String,
    },
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Gltf(e) => write!(f, "glTF load failed: {e}"),
            Self::Mesh { node, source } => write!(f, "mesh on node {node}: {source}"),
            Self::Scene(e) => write!(f, "{e}"),
            Self::Stylization { material, why } => {
                write!(f, "material {material}: {}: {why}", stylization_ext::NAME)
            }
        }
    }
}

impl std::error::Error for Error {}

impl From<SceneError> for Error {
    fn from(e: SceneError) -> Self {
        Self::Scene(e)
    }
}

/// Loads a `.gltf` (with external buffers) or `.glb` file into a Linear Rec.709 scene.
pub fn load_gltf(path: &Path) -> Result<Import, Error> {
    load_gltf_in(path, ColorSpace::default())
}

/// Like [`load_gltf`], converting colors (glTF is Rec.709 linear) into `space`.
pub fn load_gltf_in(path: &Path, space: ColorSpace) -> Result<Import, Error> {
    let (doc, buffers, images) = gltf::import(path).map_err(|e| Error::Gltf(e.to_string()))?;
    convert(&doc, &buffers, &images, space)
}

/// Loads a self-contained `.glb` or `.gltf` (embedded buffers) from memory.
pub fn load_gltf_slice(bytes: &[u8]) -> Result<Import, Error> {
    load_gltf_slice_in(bytes, ColorSpace::default())
}

/// Like [`load_gltf_slice`], converting colors into `space`.
pub fn load_gltf_slice_in(bytes: &[u8], space: ColorSpace) -> Result<Import, Error> {
    let (doc, buffers, images) =
        gltf::import_slice(bytes).map_err(|e| Error::Gltf(e.to_string()))?;
    convert(&doc, &buffers, &images, space)
}

/// Column-major 4x4, as glTF stores it.
type Mat4 = [[f32; 4]; 4];

const MAT4_IDENTITY: Mat4 = [
    [1.0, 0.0, 0.0, 0.0],
    [0.0, 1.0, 0.0, 0.0],
    [0.0, 0.0, 1.0, 0.0],
    [0.0, 0.0, 0.0, 1.0],
];

fn mul(a: &Mat4, b: &Mat4) -> Mat4 {
    let mut out = [[0.0; 4]; 4];
    for (c, col) in out.iter_mut().enumerate() {
        for (r, v) in col.iter_mut().enumerate() {
            *v = (0..4).map(|k| a[k][r] * b[c][k]).sum();
        }
    }
    out
}

/// Column-major 4x4 -> row-major 3x4 (the bottom row of an affine matrix is dropped).
fn to_transform(m: &Mat4) -> Transform {
    let mut t = IDENTITY;
    for (r, row) in t.iter_mut().enumerate() {
        for (c, v) in row.iter_mut().enumerate() {
            *v = m[c][r];
        }
    }
    t
}

struct Importer<'a> {
    buffers: &'a [gltf::buffer::Data],
    images: &'a [gltf::image::Data],
    /// (glTF image, sRGB-encoded) -> IR image, so one file used two ways becomes two linear images.
    image_cache: HashMap<(usize, bool), Option<ImageId>>,
    scene: Scene,
    warnings: Vec<String>,
    /// (glTF mesh, primitive) -> IR mesh + material, so shared meshes stay shared.
    meshes: HashMap<(usize, usize), (MeshId, MaterialId)>,
    materials: HashMap<Option<usize>, MaterialId>,
    camera_set: bool,
    space: ColorSpace,
}

fn convert(
    doc: &Document,
    buffers: &[gltf::buffer::Data],
    images: &[gltf::image::Data],
    space: ColorSpace,
) -> Result<Import, Error> {
    let mut imp = Importer {
        buffers,
        images,
        image_cache: HashMap::new(),
        scene: {
            let mut scene = Scene::new();
            scene.set_working_space(space);
            scene
        },
        warnings: Vec::new(),
        meshes: HashMap::new(),
        materials: HashMap::new(),
        camera_set: false,
        space,
    };
    for ext in doc.extensions_used().filter(|e| !SUPPORTED.contains(e)) {
        imp.warnings
            .push(format!("extension {ext} is not supported and was ignored"));
    }
    match doc.default_scene().or_else(|| doc.scenes().next()) {
        Some(scene) => {
            for node in scene.nodes() {
                imp.node(&node, &MAT4_IDENTITY)?;
            }
        }
        None => imp.warnings.push("file contains no scene".into()),
    }
    Ok(Import {
        scene: imp.scene,
        warnings: imp.warnings,
    })
}

impl Importer<'_> {
    fn node(&mut self, node: &gltf::Node, parent: &Mat4) -> Result<(), Error> {
        let world = mul(parent, &node.transform().matrix());
        let transform = to_transform(&world);

        if let Some(mesh) = node.mesh() {
            for prim in mesh.primitives() {
                if let Some((mesh, material)) = self.primitive(node.index(), &mesh, &prim)? {
                    self.scene.add_instance(Instance {
                        mesh,
                        material,
                        transform,
                    })?;
                }
            }
        }
        if let Some(camera) = node.camera() {
            self.camera(node.index(), &camera, transform);
        }
        if let Some(light) = node.light() {
            self.light(&light, &world);
        }
        for child in node.children() {
            self.node(&child, &world)?;
        }
        Ok(())
    }

    fn primitive(
        &mut self,
        node: usize,
        mesh: &gltf::Mesh,
        prim: &gltf::Primitive,
    ) -> Result<Option<(MeshId, MaterialId)>, Error> {
        let key = (mesh.index(), prim.index());
        if let Some(&ids) = self.meshes.get(&key) {
            return Ok(Some(ids));
        }
        if prim.mode() != Mode::Triangles {
            self.warnings.push(format!(
                "mesh {} primitive {}: only triangle lists are supported",
                key.0, key.1
            ));
            return Ok(None);
        }
        let reader = prim.reader(|b| Some(&self.buffers[b.index()]));
        let Some(positions) = reader.read_positions().map(Iterator::collect::<Vec<_>>) else {
            self.warnings.push(format!(
                "mesh {} primitive {}: no POSITION attribute",
                key.0, key.1
            ));
            return Ok(None);
        };
        let normals = reader.read_normals().map(Iterator::collect);
        let uvs = reader.read_tex_coords(0).map(|t| t.into_f32().collect());
        let indices = match reader.read_indices() {
            Some(i) => i.into_u32().collect(),
            None => (0..positions.len() as u32).collect(),
        };
        let ir = Mesh::new(positions, normals, uvs, indices)
            .map_err(|source| Error::Mesh { node, source })?;
        let mesh_id = self.scene.add_mesh(ir);
        let material_id = self.material(&prim.material())?;
        self.meshes.insert(key, (mesh_id, material_id));
        Ok(Some((mesh_id, material_id)))
    }

    fn material(&mut self, m: &gltf::Material) -> Result<MaterialId, Error> {
        if let Some(&id) = self.materials.get(&m.index()) {
            return Ok(id);
        }
        let pbr = m.pbr_metallic_roughness();
        let [r, g, b, _] = pbr.base_color_factor();
        let to_space = |c: [f32; 3]| ColorSpace::LinearRec709.convert(self.space, c);
        let mut emission = m.emissive_factor();
        let strength = m.emissive_strength().unwrap_or(1.0);
        emission = to_space(emission.map(|c| c * strength));
        let base = BaseBsdf {
            base_color: to_space([r, g, b]),
            metallic: pbr.metallic_factor(),
            roughness: pbr.roughness_factor(),
            transmission: m.transmission().map_or(0.0, |t| t.transmission_factor()),
            ior: m.ior().unwrap_or(1.5),
            emission,
            ..BaseBsdf::default()
        };

        let name = m.index().map_or("default".to_string(), |i| i.to_string());
        let mut base = base;
        // The gltf crate has no accessor for clearcoat, so read the raw extension (REQ-CORE-003).
        if let Some(cc) = m.extension_value("KHR_materials_clearcoat") {
            let get = |key: &str, default: f32| {
                cc.get(key)
                    .and_then(|v| v.as_f64())
                    .map_or(default, |v| v as f32)
            };
            base.clearcoat = get("clearcoatFactor", 0.0).clamp(0.0, 1.0);
            base.clearcoat_roughness = get("clearcoatRoughnessFactor", 0.0).clamp(0.0, 1.0);
            for key in [
                "clearcoatTexture",
                "clearcoatRoughnessTexture",
                "clearcoatNormalTexture",
            ] {
                if cc.get(key).is_some() {
                    self.warnings.push(format!(
                        "material {name}: {key} is not supported yet and was ignored"
                    ));
                }
            }
        }
        if let Some(sh) = m.extension_value("KHR_materials_sheen") {
            let color = sh
                .get("sheenColorFactor")
                .and_then(|v| v.as_array())
                .filter(|a| a.len() == 3)
                .map_or([0.0; 3], |a| {
                    std::array::from_fn(|i| a[i].as_f64().unwrap_or(0.0).clamp(0.0, 1.0) as f32)
                });
            base.sheen_color = to_space(color);
            base.sheen_roughness = sh
                .get("sheenRoughnessFactor")
                .and_then(|v| v.as_f64())
                .map_or(0.0, |v| v.clamp(0.0, 1.0) as f32);
            for key in ["sheenColorTexture", "sheenRoughnessTexture"] {
                if sh.get(key).is_some() {
                    self.warnings.push(format!(
                        "material {name}: {key} is not supported yet and was ignored"
                    ));
                }
            }
        }
        base.base_color_texture = pbr.base_color_texture().and_then(|t| {
            self.texture(
                &name,
                "base color",
                t.tex_coord(),
                t.texture().source().index(),
                true,
            )
        });
        base.metallic_roughness_texture = pbr.metallic_roughness_texture().and_then(|t| {
            self.texture(
                &name,
                "metallic-roughness",
                t.tex_coord(),
                t.texture().source().index(),
                false,
            )
        });
        base.emission_texture = m.emissive_texture().and_then(|t| {
            self.texture(
                &name,
                "emissive",
                t.tex_coord(),
                t.texture().source().index(),
                true,
            )
        });
        if let Some(t) = m.normal_texture() {
            base.normal_scale = t.scale();
            base.normal_texture = self.texture(
                &name,
                "normal",
                t.tex_coord(),
                t.texture().source().index(),
                false,
            );
        }
        let ignored = [
            ("occlusion", m.occlusion_texture().is_some()),
            (
                "transmission",
                m.transmission()
                    .is_some_and(|t| t.transmission_texture().is_some()),
            ),
        ];
        for (kind, present) in ignored {
            if present {
                self.warnings.push(format!(
                    "material {name}: {kind} textures are not supported yet and were ignored"
                ));
            }
        }
        if m.alpha_mode() != gltf::material::AlphaMode::Opaque {
            self.warnings.push(format!(
                "material {name}: alpha mode is not supported; rendered as opaque"
            ));
        }

        let mut stylization = Vec::new();
        if let Some(value) = m.extension_value(stylization_ext::NAME) {
            let (layers, warnings) =
                stylization_ext::parse(value, self.space).map_err(|why| Error::Stylization {
                    material: name.clone(),
                    why,
                })?;
            stylization = layers;
            self.warnings.extend(
                warnings
                    .into_iter()
                    .map(|w| format!("material {name}: {w}")),
            );
        }
        let id = self.scene.add_material(Material {
            base,
            stylization,
            ..Material::default()
        });
        self.materials.insert(m.index(), id);
        Ok(id)
    }

    /// Imports the texture's image as linear data; `None` (with a warning) when it cannot be used.
    fn texture(
        &mut self,
        material: &str,
        slot: &str,
        tex_coord: u32,
        source: usize,
        srgb: bool,
    ) -> Option<ImageId> {
        if tex_coord != 0 {
            self.warnings.push(format!(
                "material {material}: {slot} texture uses UV set {tex_coord}; only set 0 is supported"
            ));
            return None;
        }
        if let Some(&cached) = self.image_cache.get(&(source, srgb)) {
            return cached;
        }
        let id = match to_image(&self.images[source], srgb, self.space) {
            Ok(image) => Some(self.scene.add_image(image)),
            Err(why) => {
                self.warnings.push(format!(
                    "material {material}: {slot} texture ignored: {why}"
                ));
                None
            }
        };
        self.image_cache.insert((source, srgb), id);
        id
    }

    fn camera(&mut self, node: usize, camera: &gltf::Camera, transform: Transform) {
        let Projection::Perspective(p) = camera.projection() else {
            self.warnings.push(format!(
                "node {node}: orthographic cameras are not supported"
            ));
            return;
        };
        if self.camera_set {
            self.warnings
                .push(format!("node {node}: only the first camera is used"));
            return;
        }
        self.camera_set = true;
        self.scene.set_camera(Camera {
            transform,
            vertical_fov: p.yfov(),
            ..Camera::default()
        });
    }

    fn light(&mut self, light: &gltf::khr_lights_punctual::Light, world: &Mat4) {
        let (color, intensity) = (
            ColorSpace::LinearRec709.convert(self.space, light.color()),
            light.intensity(),
        );
        let ir = match light.kind() {
            Kind::Point => Light::Point {
                position: [world[3][0], world[3][1], world[3][2]],
                color,
                intensity,
            },
            // A directional light shines along its local -z axis.
            Kind::Directional => Light::Directional {
                direction: [-world[2][0], -world[2][1], -world[2][2]],
                color,
                intensity,
            },
            Kind::Spot {
                inner_cone_angle,
                outer_cone_angle,
            } => Light::Spot {
                position: [world[3][0], world[3][1], world[3][2]],
                direction: [-world[2][0], -world[2][1], -world[2][2]],
                color,
                intensity,
                inner_cone: inner_cone_angle,
                outer_cone: outer_cone_angle,
            },
        };
        self.scene.add_light(ir);
    }
}

fn srgb_to_linear(c: f32) -> f32 {
    if c <= 0.04045 {
        c / 12.92
    } else {
        ((c + 0.055) / 1.055).powf(2.4)
    }
}

/// Converts a decoded glTF image to linear RGB. One channel becomes grey, two become (r, g, 0).
/// Color data (`srgb`) also moves from Rec.709 into `space`; data textures are left alone.
fn to_image(data: &gltf::image::Data, srgb: bool, space: ColorSpace) -> Result<Image, String> {
    use gltf::image::Format::*;
    let (channels, bytes) = match data.format {
        R8 => (1, 1),
        R8G8 => (2, 1),
        R8G8B8 => (3, 1),
        R8G8B8A8 => (4, 1),
        R16 => (1, 2),
        R16G16 => (2, 2),
        R16G16B16 => (3, 2),
        R16G16B16A16 => (4, 2),
        R32G32B32FLOAT => (3, 4),
        R32G32B32A32FLOAT => (4, 4),
    };
    let stride = channels * bytes;
    let is_float = bytes == 4;
    let channel = |px: &[u8], c: usize| -> f32 {
        let at = &px[c * bytes..(c + 1) * bytes];
        let v = match bytes {
            1 => f32::from(at[0]) / 255.0,
            2 => f32::from(u16::from_le_bytes([at[0], at[1]])) / 65535.0,
            _ => f32::from_le_bytes([at[0], at[1], at[2], at[3]]),
        };
        if srgb && !is_float {
            srgb_to_linear(v)
        } else {
            v
        }
    };
    let pixels = data
        .pixels
        .chunks_exact(stride)
        .map(|px| {
            let rgb = match channels {
                1 => [channel(px, 0); 3],
                2 => [channel(px, 0), channel(px, 1), 0.0],
                _ => [channel(px, 0), channel(px, 1), channel(px, 2)],
            };
            if srgb {
                ColorSpace::LinearRec709.convert(space, rgb)
            } else {
                rgb
            }
        })
        .collect();
    Image::new(data.width, data.height, pixels).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// One triangle: node 0 (mesh, +2 x), node 1 (camera at z = 5), node 2 (point light at y = 3).
    const JSON: &str = r#"{
      "asset": {"version": "2.0"},
      "extensionsUsed": ["KHR_lights_punctual", "KHR_materials_volume"],
      "scene": 0,
      "scenes": [{"nodes": [0, 1, 2]}],
      "nodes": [
        {"mesh": 0, "translation": [2, 0, 0]},
        {"camera": 0, "translation": [0, 0, 5]},
        {"translation": [0, 3, 0], "extensions": {"KHR_lights_punctual": {"light": 0}}}
      ],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1, "material": 0}]}],
      "materials": [{
        "pbrMetallicRoughness": {"baseColorFactor": [1, 0, 0, 1], "metallicFactor": 0.5, "roughnessFactor": 0.25}
      }],
      "cameras": [{"type": "perspective", "perspective": {"yfov": 0.5, "znear": 0.1}}],
      "extensions": {"KHR_lights_punctual": {"lights": [{"type": "point", "color": [1, 1, 1], "intensity": 10}]}},
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 0]},
        {"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"}
      ],
      "bufferViews": [
        {"buffer": 0, "byteOffset": 0, "byteLength": 36},
        {"buffer": 0, "byteOffset": 36, "byteLength": 6}
      ],
      "buffers": [{"byteLength": 44}]
    }"#;

    /// Binary glTF: the triangle's buffer (44 bytes) followed by `extra` (an embedded image).
    fn glb(json: &str, extra: &[u8]) -> Vec<u8> {
        let mut bin: Vec<u8> = [0.0f32, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0]
            .iter()
            .flat_map(|f| f.to_le_bytes())
            .collect();
        bin.extend([0u16, 1, 2].iter().flat_map(|i| i.to_le_bytes()));
        bin.extend([0, 0]);
        bin.extend(extra);
        while !bin.len().is_multiple_of(4) {
            bin.push(0);
        }
        let mut j = json.as_bytes().to_vec();
        while !j.len().is_multiple_of(4) {
            j.push(b' ');
        }
        let total = 12 + 8 + j.len() + 8 + bin.len();
        let mut out = Vec::new();
        for v in [0x4654_6C67u32, 2, total as u32, j.len() as u32, 0x4E4F_534A] {
            out.extend(v.to_le_bytes());
        }
        out.extend(&j);
        for v in [bin.len() as u32, 0x004E_4942] {
            out.extend(v.to_le_bytes());
        }
        out.extend(&bin);
        out
    }

    #[test]
    fn imports_a_spot_light_along_local_minus_z() {
        let json = JSON.replace(
            r#"{"type": "point", "color": [1, 1, 1], "intensity": 10}"#,
            r#"{"type": "spot", "color": [1, 1, 1], "intensity": 10, "spot": {"innerConeAngle": 0.1, "outerConeAngle": 0.5}}"#,
        );
        let Import { scene, warnings } = load_gltf_slice(&glb(&json, &[])).unwrap();
        assert_eq!(
            scene.lights(),
            [Light::Spot {
                position: [0.0, 3.0, 0.0],
                direction: [0.0, 0.0, -1.0],
                color: [1.0; 3],
                intensity: 10.0,
                inner_cone: 0.1,
                outer_cone: 0.5,
            }]
        );
        assert!(warnings.iter().all(|w| !w.contains("spot")), "{warnings:?}");
    }

    #[test]
    fn imports_mesh_material_camera_and_light() {
        let Import { scene, warnings } = load_gltf_slice(&glb(JSON, &[])).unwrap();

        assert_eq!(scene.meshes().len(), 1);
        assert_eq!(scene.meshes()[0].indices(), [0, 1, 2]);
        let inst = scene.instances()[0];
        assert_eq!(inst.transform[0][3], 2.0);
        let base = &scene.materials()[inst.material.index()].base;
        assert_eq!(
            (base.base_color, base.metallic, base.roughness),
            ([1.0, 0.0, 0.0], 0.5, 0.25)
        );
        assert_eq!(scene.camera().transform[2][3], 5.0);
        assert_eq!(scene.camera().vertical_fov, 0.5);
        assert_eq!(
            scene.lights(),
            [Light::Point {
                position: [0.0, 3.0, 0.0],
                color: [1.0; 3],
                intensity: 10.0
            }]
        );
        assert_eq!(
            warnings,
            ["extension KHR_materials_volume is not supported and was ignored"]
        );
    }

    fn with_stylization(ext: &str) -> String {
        JSON.replace(
            r#""pbrMetallicRoughness": {"baseColorFactor": [1, 0, 0, 1], "metallicFactor": 0.5, "roughnessFactor": 0.25}"#,
            &format!(
                r#""pbrMetallicRoughness": {{"baseColorFactor": [1, 0, 0, 1]}},
                "extensions": {{"VERION_materials_stylization": {ext}}}"#
            ),
        )
        .replace(
            r#""extensionsUsed": ["KHR_lights_punctual", "KHR_materials_volume"]"#,
            r#""extensionsUsed": ["KHR_lights_punctual", "VERION_materials_stylization"]"#,
        )
    }

    #[test]
    fn imports_clearcoat() {
        let json = JSON
            .replace("KHR_materials_volume", "KHR_materials_clearcoat")
            .replace(
                r#""roughnessFactor": 0.25}"#,
                r#""roughnessFactor": 0.25},
                "extensions": {"KHR_materials_clearcoat": {"clearcoatFactor": 1.5, "clearcoatRoughnessFactor": 0.2, "clearcoatTexture": {"index": 0}}}"#,
            );
        let Import { scene, warnings } = load_gltf_slice(&glb(&json, &[])).unwrap();
        let base = &scene.materials()[0].base;
        assert_eq!((base.clearcoat, base.clearcoat_roughness), (1.0, 0.2)); // factor clamped to 1
        assert_eq!(
            warnings,
            ["material 0: clearcoatTexture is not supported yet and was ignored"]
        );
    }

    #[test]
    fn imports_sheen() {
        let json = JSON
            .replace("KHR_materials_volume", "KHR_materials_sheen")
            .replace(
                r#""roughnessFactor": 0.25}"#,
                r#""roughnessFactor": 0.25},
                "extensions": {"KHR_materials_sheen": {"sheenColorFactor": [1, 0.5, 2], "sheenRoughnessFactor": 0.3, "sheenRoughnessTexture": {"index": 0}}}"#,
            );
        let Import { scene, warnings } = load_gltf_slice(&glb(&json, &[])).unwrap();
        let base = &scene.materials()[0].base;
        assert_eq!(base.sheen_color, [1.0, 0.5, 1.0]); // components clamped to 1
        assert_eq!(base.sheen_roughness, 0.3);
        assert_eq!(
            warnings,
            ["material 0: sheenRoughnessTexture is not supported yet and was ignored"]
        );
    }

    #[test]
    fn imports_the_stylization_extension() {
        let json = with_stylization(
            r#"{"hybridSurface": {"diffuse": 1}, "toonRamp": {"thresholds": [0.5], "palette": [[0.2, 0.2, 0.2], [1, 1, 1]]}}"#,
        );
        let Import { scene, warnings } = load_gltf_slice(&glb(&json, &[])).unwrap();
        assert!(warnings.is_empty(), "{warnings:?}");
        assert_eq!(scene.materials()[0].stylization.len(), 2);
        assert_eq!(scene.revisions().stylization, 1);
    }

    #[test]
    fn a_material_without_the_extension_has_no_layers() {
        let Import { scene, .. } = load_gltf_slice(&glb(JSON, &[])).unwrap();
        assert!(scene.materials()[0].stylization.is_empty());
        assert_eq!(scene.revisions().stylization, 0);
    }

    #[test]
    fn an_invalid_stylization_value_is_an_import_error() {
        let json = with_stylization(r#"{"hybridSurface": {"diffuse": 2}}"#);
        assert!(matches!(
            load_gltf_slice(&glb(&json, &[])),
            Err(Error::Stylization { .. })
        ));
    }

    #[test]
    fn invalid_file_is_an_error() {
        assert!(matches!(load_gltf_slice(b"not gltf"), Err(Error::Gltf(_))));
    }

    /// 2x2 RGB PNG: red, green / blue, grey (128).
    const PNG: [u8; 76] = [
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44,
        0x52, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x02, 0x08, 0x02, 0x00, 0x00, 0x00, 0xfd,
        0xd4, 0x9a, 0x73, 0x00, 0x00, 0x00, 0x13, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8,
        0xcf, 0xc0, 0xc0, 0x00, 0xc2, 0x0c, 0xff, 0x1b, 0x1a, 0x1a, 0x00, 0x1c, 0xf4, 0x04, 0x7e,
        0x29, 0x80, 0x40, 0xd8, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60,
        0x82,
    ];

    fn textured_json(tex_coord: u32) -> String {
        format!(
            r#"{{
          "asset": {{"version": "2.0"}},
          "scene": 0,
          "scenes": [{{"nodes": [0]}}],
          "nodes": [{{"mesh": 0}}],
          "meshes": [{{"primitives": [{{"attributes": {{"POSITION": 0}}, "indices": 1, "material": 0}}]}}],
          "materials": [{{
            "pbrMetallicRoughness": {{
              "baseColorTexture": {{"index": 0, "texCoord": {tex_coord}}},
              "metallicRoughnessTexture": {{"index": 0}}
            }},
            "normalTexture": {{"index": 0}}
          }}],
          "textures": [{{"source": 0}}],
          "images": [{{"bufferView": 2, "mimeType": "image/png"}}],
          "accessors": [
            {{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 0]}},
            {{"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"}}
          ],
          "bufferViews": [
            {{"buffer": 0, "byteOffset": 0, "byteLength": 36}},
            {{"buffer": 0, "byteOffset": 36, "byteLength": 6}},
            {{"buffer": 0, "byteOffset": 44, "byteLength": 76}}
          ],
          "buffers": [{{"byteLength": 120}}]
        }}"#
        )
    }

    #[test]
    fn imports_textures_as_linear_images() {
        let Import { scene, warnings } = load_gltf_slice(&glb(&textured_json(0), &PNG)).unwrap();
        let base = &scene.materials()[0].base;
        let (color, mr) = (
            base.base_color_texture.unwrap(),
            base.metallic_roughness_texture.unwrap(),
        );
        let mr_id = mr;
        assert_ne!(
            color, mr,
            "sRGB and linear uses of one file are separate images"
        );

        let color = &scene.images()[color.index()];
        assert_eq!((color.width(), color.height()), (2, 2));
        assert_eq!(color.pixels()[0], [1.0, 0.0, 0.0]);
        // sRGB 128/255 decodes to about 0.2158.
        assert!(
            (color.pixels()[3][0] - 0.2158).abs() < 1e-3,
            "{:?}",
            color.pixels()[3]
        );
        // Metallic-roughness data is already linear.
        let mr = &scene.images()[mr.index()];
        assert!((mr.pixels()[3][0] - 128.0 / 255.0).abs() < 1e-6);
        assert_eq!(
            base.normal_texture,
            Some(mr_id),
            "normal maps are linear data"
        );
        assert_eq!(base.normal_scale, 1.0);
        assert!(warnings.is_empty(), "{warnings:?}");
    }

    const ACES_RED: [f32; 3] = [0.613_097, 0.070_194, 0.020_616];

    #[test]
    fn acescg_import_converts_color_factors() {
        let Import { scene, .. } = load_gltf_slice_in(&glb(JSON, &[]), ColorSpace::AcesCg).unwrap();
        assert_eq!(scene.working_space(), ColorSpace::AcesCg);
        let base = &scene.materials()[0].base;
        assert_eq!(base.base_color, ACES_RED);
        // Metallic and roughness are scalars, not colors.
        assert_eq!((base.metallic, base.roughness), (0.5, 0.25));
        // White light keeps its color in any space.
        let Light::Point { color, .. } = scene.lights()[0] else {
            panic!("expected a point light");
        };
        assert!(color.iter().all(|c| (c - 1.0).abs() < 1e-4), "{color:?}");
    }

    #[test]
    fn acescg_import_converts_color_textures_but_not_data_textures() {
        let Import { scene, .. } =
            load_gltf_slice_in(&glb(&textured_json(0), &PNG), ColorSpace::AcesCg).unwrap();
        let base = &scene.materials()[0].base;
        let color = &scene.images()[base.base_color_texture.unwrap().index()];
        let red = color.pixels()[0];
        assert!(
            red.iter().zip(ACES_RED).all(|(a, b)| (a - b).abs() < 1e-5),
            "{red:?}"
        );
        let mr = &scene.images()[base.metallic_roughness_texture.unwrap().index()];
        assert!((mr.pixels()[3][0] - 128.0 / 255.0).abs() < 1e-6);
    }

    #[test]
    fn texture_on_another_uv_set_is_ignored_with_a_warning() {
        let Import { scene, warnings } = load_gltf_slice(&glb(&textured_json(1), &PNG)).unwrap();
        assert_eq!(scene.materials()[0].base.base_color_texture, None);
        assert!(
            scene.materials()[0]
                .base
                .metallic_roughness_texture
                .is_some()
        );
        assert!(
            warnings.iter().any(|w| w.contains("UV set 1")),
            "{warnings:?}"
        );
    }
}
