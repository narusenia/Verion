use std::fmt;

use crate::{Image, Material, Mesh};

/// Row-major 3x4 affine transform.
pub type Transform = [[f32; 4]; 3];

pub const IDENTITY: Transform = [
    [1.0, 0.0, 0.0, 0.0],
    [0.0, 1.0, 0.0, 0.0],
    [0.0, 0.0, 1.0, 0.0],
];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MeshId(u32);
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MaterialId(u32);
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct InstanceId(u32);
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct LightId(u32);
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ImageId(u32);

macro_rules! id_index {
    ($($t:ty),*) => {$(impl $t { pub fn index(self) -> usize { self.0 as usize } })*};
}
id_index!(MeshId, MaterialId, InstanceId, LightId, ImageId);

/// A placed copy of a mesh with a material.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Instance {
    pub mesh: MeshId,
    pub material: MaterialId,
    pub transform: Transform,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Light {
    Point {
        position: [f32; 3],
        color: [f32; 3],
        intensity: f32,
    },
    Directional {
        direction: [f32; 3],
        color: [f32; 3],
        intensity: f32,
    },
    /// Cone light. `direction` is the axis the light shines along (need not be normalized);
    /// the cone angles are half-angles in radians with `inner < outer <= pi / 2`, and intensity
    /// falls off smoothly between them (glTF KHR_lights_punctual).
    Spot {
        position: [f32; 3],
        direction: [f32; 3],
        color: [f32; 3],
        intensity: f32,
        inner_cone: f32,
        outer_cone: f32,
    },
    /// Uniform sky.
    Environment { color: [f32; 3] },
    /// Latitude-longitude HDRI. +y is up and the image center faces -z. The image id must come from
    /// this scene; consumers report a dangling id as an error.
    EnvironmentMap { image: ImageId, scale: f32 },
}

/// Perspective thin-lens camera.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Camera {
    /// Camera-to-world, looking down -z.
    pub transform: Transform,
    pub vertical_fov: f32,
    pub focus_distance: f32,
    /// 0 = pinhole.
    pub aperture_radius: f32,
}

impl Default for Camera {
    fn default() -> Self {
        Self {
            transform: IDENTITY,
            vertical_fov: 0.8,
            focus_distance: 1.0,
            aperture_radius: 0.0,
        }
    }
}

/// Monotonic change counters. Consumers compare against a stored copy to decide what to rebuild.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Revisions {
    /// Meshes and instances (BLAS / TLAS inputs).
    pub geometry: u64,
    pub material: u64,
    pub lighting: u64,
    pub camera: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SceneError {
    /// An instance refers to a mesh or material that is not in this scene.
    DanglingReference(&'static str),
}

impl fmt::Display for SceneError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::DanglingReference(what) => {
                write!(f, "instance refers to a {what} that is not in the scene")
            }
        }
    }
}

impl std::error::Error for SceneError {}

/// Ids come from the scene that issued them; using one on another scene panics.
#[derive(Clone, Debug, Default)]
pub struct Scene {
    meshes: Vec<Mesh>,
    materials: Vec<Material>,
    images: Vec<Image>,
    instances: Vec<Instance>,
    lights: Vec<Light>,
    camera: Camera,
    revisions: Revisions,
}

impl Scene {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn revisions(&self) -> Revisions {
        self.revisions
    }

    pub fn meshes(&self) -> &[Mesh] {
        &self.meshes
    }

    pub fn materials(&self) -> &[Material] {
        &self.materials
    }

    pub fn images(&self) -> &[Image] {
        &self.images
    }

    pub fn instances(&self) -> &[Instance] {
        &self.instances
    }

    pub fn lights(&self) -> &[Light] {
        &self.lights
    }

    pub fn camera(&self) -> &Camera {
        &self.camera
    }

    pub fn add_mesh(&mut self, mesh: Mesh) -> MeshId {
        self.revisions.geometry += 1;
        self.meshes.push(mesh);
        MeshId(self.meshes.len() as u32 - 1)
    }

    pub fn set_mesh(&mut self, id: MeshId, mesh: Mesh) {
        self.revisions.geometry += 1;
        self.meshes[id.index()] = mesh;
    }

    pub fn add_material(&mut self, material: Material) -> MaterialId {
        self.revisions.material += 1;
        self.materials.push(material);
        MaterialId(self.materials.len() as u32 - 1)
    }

    pub fn set_material(&mut self, id: MaterialId, material: Material) {
        self.revisions.material += 1;
        self.materials[id.index()] = material;
    }

    /// Images do not change any revision until a light or material refers to them.
    pub fn add_image(&mut self, image: Image) -> ImageId {
        self.images.push(image);
        ImageId(self.images.len() as u32 - 1)
    }

    pub fn add_instance(&mut self, instance: Instance) -> Result<InstanceId, SceneError> {
        self.check(&instance)?;
        self.revisions.geometry += 1;
        self.instances.push(instance);
        Ok(InstanceId(self.instances.len() as u32 - 1))
    }

    pub fn set_instance(&mut self, id: InstanceId, instance: Instance) -> Result<(), SceneError> {
        self.check(&instance)?;
        self.revisions.geometry += 1;
        self.instances[id.index()] = instance;
        Ok(())
    }

    pub fn add_light(&mut self, light: Light) -> LightId {
        self.revisions.lighting += 1;
        self.lights.push(light);
        LightId(self.lights.len() as u32 - 1)
    }

    pub fn set_light(&mut self, id: LightId, light: Light) {
        self.revisions.lighting += 1;
        self.lights[id.index()] = light;
    }

    pub fn set_camera(&mut self, camera: Camera) {
        self.revisions.camera += 1;
        self.camera = camera;
    }

    fn check(&self, i: &Instance) -> Result<(), SceneError> {
        if i.mesh.index() >= self.meshes.len() {
            return Err(SceneError::DanglingReference("mesh"));
        }
        if i.material.index() >= self.materials.len() {
            return Err(SceneError::DanglingReference("material"));
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tri() -> Mesh {
        Mesh::new(
            vec![[0.0; 3], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]],
            None,
            None,
            vec![0, 1, 2],
        )
        .unwrap()
    }

    /// Each mutation bumps exactly its own counter by one.
    #[test]
    fn mutations_bump_only_their_revision() {
        let mut s = Scene::new();
        let mut expect = Revisions::default();
        assert_eq!(s.revisions(), expect);

        let mesh = s.add_mesh(tri());
        expect.geometry += 1;
        assert_eq!(s.revisions(), expect);

        let material = s.add_material(Material::default());
        expect.material += 1;
        assert_eq!(s.revisions(), expect);

        let inst = Instance {
            mesh,
            material,
            transform: IDENTITY,
        };
        let id = s.add_instance(inst).unwrap();
        expect.geometry += 1;
        assert_eq!(s.revisions(), expect);

        s.set_instance(id, inst).unwrap();
        s.set_mesh(mesh, tri());
        expect.geometry += 2;
        assert_eq!(s.revisions(), expect);

        s.set_material(material, Material::default());
        expect.material += 1;
        assert_eq!(s.revisions(), expect);

        let light = s.add_light(Light::Environment { color: [1.0; 3] });
        s.set_light(light, Light::Environment { color: [0.5; 3] });
        expect.lighting += 2;
        assert_eq!(s.revisions(), expect);

        s.set_camera(Camera::default());
        expect.camera += 1;
        assert_eq!(s.revisions(), expect);
    }

    #[test]
    fn dangling_instance_is_rejected_without_a_revision_bump() {
        let mut s = Scene::new();
        let mesh = s.add_mesh(tri());
        let before = s.revisions();
        let inst = Instance {
            mesh,
            material: MaterialId(0),
            transform: IDENTITY,
        };
        assert_eq!(
            s.add_instance(inst),
            Err(SceneError::DanglingReference("material"))
        );
        assert_eq!(s.revisions(), before);
        assert!(s.instances().is_empty());
    }
}
