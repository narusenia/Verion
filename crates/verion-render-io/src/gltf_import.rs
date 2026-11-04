//! glTF 2.0 -> Scene IR (REQ-IO-001). Unsupported features become warnings, not errors.

use std::{collections::HashMap, fmt, path::Path};

use gltf::{Document, camera::Projection, khr_lights_punctual::Kind, mesh::Mode};
use verion_scene::{
    BaseBsdf, Camera, IDENTITY, Instance, Light, Material, MaterialId, Mesh, MeshError, MeshId,
    Scene, SceneError, Transform,
};

/// Extensions this importer understands; any other one in `extensionsUsed` is warned about.
const SUPPORTED: [&str; 4] = [
    "KHR_lights_punctual",
    "KHR_materials_transmission",
    "KHR_materials_ior",
    "KHR_materials_emissive_strength",
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
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Gltf(e) => write!(f, "glTF load failed: {e}"),
            Self::Mesh { node, source } => write!(f, "mesh on node {node}: {source}"),
            Self::Scene(e) => write!(f, "{e}"),
        }
    }
}

impl std::error::Error for Error {}

impl From<SceneError> for Error {
    fn from(e: SceneError) -> Self {
        Self::Scene(e)
    }
}

/// Loads a `.gltf` (with external buffers) or `.glb` file.
pub fn load_gltf(path: &Path) -> Result<Import, Error> {
    let (doc, buffers, _images) = gltf::import(path).map_err(|e| Error::Gltf(e.to_string()))?;
    convert(&doc, &buffers)
}

/// Loads a self-contained `.glb` or `.gltf` (embedded buffers) from memory.
pub fn load_gltf_slice(bytes: &[u8]) -> Result<Import, Error> {
    let (doc, buffers, _images) =
        gltf::import_slice(bytes).map_err(|e| Error::Gltf(e.to_string()))?;
    convert(&doc, &buffers)
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
    scene: Scene,
    warnings: Vec<String>,
    /// (glTF mesh, primitive) -> IR mesh + material, so shared meshes stay shared.
    meshes: HashMap<(usize, usize), (MeshId, MaterialId)>,
    materials: HashMap<Option<usize>, MaterialId>,
    camera_set: bool,
}

fn convert(doc: &Document, buffers: &[gltf::buffer::Data]) -> Result<Import, Error> {
    let mut imp = Importer {
        buffers,
        scene: Scene::new(),
        warnings: Vec::new(),
        meshes: HashMap::new(),
        materials: HashMap::new(),
        camera_set: false,
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
            self.light(node.index(), &light, &world);
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
        let material_id = self.material(&prim.material());
        self.meshes.insert(key, (mesh_id, material_id));
        Ok(Some((mesh_id, material_id)))
    }

    fn material(&mut self, m: &gltf::Material) -> MaterialId {
        if let Some(&id) = self.materials.get(&m.index()) {
            return id;
        }
        let pbr = m.pbr_metallic_roughness();
        let [r, g, b, _] = pbr.base_color_factor();
        let mut emission = m.emissive_factor();
        let strength = m.emissive_strength().unwrap_or(1.0);
        emission = emission.map(|c| c * strength);
        let base = BaseBsdf {
            base_color: [r, g, b],
            metallic: pbr.metallic_factor(),
            roughness: pbr.roughness_factor(),
            transmission: m.transmission().map_or(0.0, |t| t.transmission_factor()),
            ior: m.ior().unwrap_or(1.5),
            emission,
        };

        let name = m.index().map_or("default".to_string(), |i| i.to_string());
        let has_texture = pbr.base_color_texture().is_some()
            || pbr.metallic_roughness_texture().is_some()
            || m.normal_texture().is_some()
            || m.occlusion_texture().is_some()
            || m.emissive_texture().is_some()
            || m.transmission()
                .is_some_and(|t| t.transmission_texture().is_some());
        if has_texture {
            self.warnings.push(format!(
                "material {name}: textures are not supported yet and were ignored"
            ));
        }
        if m.alpha_mode() != gltf::material::AlphaMode::Opaque {
            self.warnings.push(format!(
                "material {name}: alpha mode is not supported; rendered as opaque"
            ));
        }

        let id = self.scene.add_material(Material {
            base,
            ..Material::default()
        });
        self.materials.insert(m.index(), id);
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

    fn light(&mut self, node: usize, light: &gltf::khr_lights_punctual::Light, world: &Mat4) {
        let (color, intensity) = (light.color(), light.intensity());
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
            Kind::Spot { .. } => {
                self.warnings
                    .push(format!("node {node}: spot lights are not supported"));
                return;
            }
        };
        self.scene.add_light(ir);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// One triangle: node 0 (mesh, +2 x), node 1 (camera at z = 5), node 2 (point light at y = 3).
    const JSON: &str = r#"{
      "asset": {"version": "2.0"},
      "extensionsUsed": ["KHR_lights_punctual", "KHR_materials_clearcoat"],
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

    fn glb(json: &str) -> Vec<u8> {
        let mut bin: Vec<u8> = [0.0f32, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0]
            .iter()
            .flat_map(|f| f.to_le_bytes())
            .collect();
        bin.extend([0u16, 1, 2].iter().flat_map(|i| i.to_le_bytes()));
        bin.extend([0, 0]);
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
    fn imports_mesh_material_camera_and_light() {
        let Import { scene, warnings } = load_gltf_slice(&glb(JSON)).unwrap();

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
            ["extension KHR_materials_clearcoat is not supported and was ignored"]
        );
    }

    #[test]
    fn invalid_file_is_an_error() {
        assert!(matches!(load_gltf_slice(b"not gltf"), Err(Error::Gltf(_))));
    }
}
