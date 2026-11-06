use std::fmt;

use crate::{ColorSpace, Image, Material, Mesh};

/// Row-major 3x4 affine transform.
pub type Transform = [[f32; 4]; 3];

pub const IDENTITY: Transform = [
    [1.0, 0.0, 0.0, 0.0],
    [0.0, 1.0, 0.0, 0.0],
    [0.0, 0.0, 1.0, 0.0],
];

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct MeshId(u32);
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct MaterialId(u32);
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
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
    /// Lens shift: the image center's offset from the optical axis, in half-image extents (x to the
    /// right, y up). The view direction through NDC point `(x, y)` is that of the unshifted camera
    /// through `(x + shift.x, y + shift.y)`, so a positive shift looks further right and up. 0 =
    /// centered. Blender's Shift X/Y (a fraction of the longer side) is twice that value.
    pub shift: [f32; 2],
}

impl Default for Camera {
    fn default() -> Self {
        Self {
            transform: IDENTITY,
            vertical_fov: 0.8,
            focus_distance: 1.0,
            aperture_radius: 0.0,
            shift: [0.0; 2],
        }
    }
}

/// Monotonic change counters. Consumers compare against a stored copy to decide what to rebuild.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Revisions {
    /// Meshes and instances (BLAS / TLAS inputs).
    pub geometry: u64,
    pub material: u64,
    /// Bumps only when a material's stylization layers change (ADR-0008, REQ-STY-008), so
    /// outputs and caches can tell stylized results apart from physical ones.
    pub stylization: u64,
    pub lighting: u64,
    pub camera: u64,
}

/// What changed since the last [`Scene::take_changes`], so a renderer updates only that
/// (REQ-ACC-003). One consumer takes them; revisions stay for anyone who only compares.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Changes {
    /// Meshes or instances were added or re-pointed, or a mesh changed shape: rebuild everything.
    pub geometry: bool,
    /// Meshes whose vertex data changed with the same triangles (Mesh Deformation), sorted.
    pub deformed: Vec<MeshId>,
    /// Instances whose transform or material changed, sorted.
    pub instances: Vec<InstanceId>,
    /// Materials whose physical parameters changed (stylization layers are not GPU data), sorted.
    pub materials: Vec<MaterialId>,
    pub lights: bool,
    pub camera: bool,
}

impl Changes {
    pub fn is_empty(&self) -> bool {
        *self == Self::default()
    }
}

fn mark<T: Ord>(list: &mut Vec<T>, id: T) {
    if let Err(at) = list.binary_search(&id) {
        list.insert(at, id);
    }
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

/// The virtual main light that Toon bands take from the environment (ADR-0020). It feeds only the
/// Stylization light slot; the physical lighting is unchanged.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct StylizationWorld {
    pub virtual_light: bool,
    /// World-space direction toward the light; `None` estimates it from the environment map.
    pub direction: Option<[f32; 3]>,
    /// Multiplies the estimated irradiance.
    pub strength: f32,
}

impl Default for StylizationWorld {
    fn default() -> Self {
        Self {
            virtual_light: true,
            direction: None,
            strength: 1.0,
        }
    }
}

/// Ids come from the scene that issued them; using one on another scene panics.
#[derive(Clone, Debug, Default)]
pub struct Scene {
    meshes: Vec<Mesh>,
    materials: Vec<Material>,
    images: Vec<Image>,
    instances: Vec<Instance>,
    lights: Vec<Light>,
    camera: Camera,
    stylization_world: StylizationWorld,
    working_space: ColorSpace,
    revisions: Revisions,
    changes: Changes,
}

impl Scene {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn revisions(&self) -> Revisions {
        self.revisions
    }

    /// The changes since the previous call, and forgets them.
    pub fn take_changes(&mut self) -> Changes {
        std::mem::take(&mut self.changes)
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

    /// Ids of every image, in `images()` order (for pickers that refer to one).
    pub fn image_ids(&self) -> Vec<ImageId> {
        (0..self.images.len() as u32).map(ImageId).collect()
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

    /// The space every color value in this scene is expressed in.
    pub fn working_space(&self) -> ColorSpace {
        self.working_space
    }

    /// Declares the working space. It does not convert colors already added: set it before adding
    /// content, or convert the values yourself.
    pub fn set_working_space(&mut self, space: ColorSpace) {
        self.working_space = space;
    }

    pub fn add_mesh(&mut self, mesh: Mesh) -> MeshId {
        self.revisions.geometry += 1;
        self.changes.geometry = true;
        self.meshes.push(mesh);
        MeshId(self.meshes.len() as u32 - 1)
    }

    pub fn set_mesh(&mut self, id: MeshId, mesh: Mesh) {
        self.revisions.geometry += 1;
        let old = &self.meshes[id.index()];
        if old.indices() == mesh.indices() && old.positions().len() == mesh.positions().len() {
            mark(&mut self.changes.deformed, id);
        } else {
            self.changes.geometry = true;
        }
        self.meshes[id.index()] = mesh;
    }

    pub fn add_material(&mut self, material: Material) -> MaterialId {
        self.revisions.material += 1;
        self.changes.geometry = true;
        if !material.stylization.is_empty() {
            self.revisions.stylization += 1;
        }
        self.materials.push(material);
        MaterialId(self.materials.len() as u32 - 1)
    }

    /// The id of the `index`-th mesh, for tools that list meshes by position.
    pub fn mesh_id(&self, index: usize) -> Option<MeshId> {
        (index < self.meshes.len()).then_some(MeshId(index as u32))
    }

    /// The id of the `index`-th material, for tools that list materials by position.
    pub fn material_id(&self, index: usize) -> Option<MaterialId> {
        (index < self.materials.len()).then_some(MaterialId(index as u32))
    }

    pub fn set_material(&mut self, id: MaterialId, material: Material) {
        self.revisions.material += 1;
        if self.materials[id.index()].stylization != material.stylization {
            self.revisions.stylization += 1;
        }
        if self.materials[id.index()].base != material.base {
            mark(&mut self.changes.materials, id);
        }
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
        self.changes.geometry = true;
        self.instances.push(instance);
        Ok(InstanceId(self.instances.len() as u32 - 1))
    }

    pub fn set_instance(&mut self, id: InstanceId, instance: Instance) -> Result<(), SceneError> {
        self.check(&instance)?;
        self.revisions.geometry += 1;
        let old = self.instances[id.index()];
        if old.mesh != instance.mesh {
            self.changes.geometry = true;
        } else if old != instance {
            mark(&mut self.changes.instances, id);
        }
        self.instances[id.index()] = instance;
        Ok(())
    }

    /// The id of the `index`-th instance, for tools that list instances by position.
    pub fn instance_id(&self, index: usize) -> Option<InstanceId> {
        (index < self.instances.len()).then_some(InstanceId(index as u32))
    }

    pub fn add_light(&mut self, light: Light) -> LightId {
        self.revisions.lighting += 1;
        self.changes.lights = true;
        self.lights.push(light);
        LightId(self.lights.len() as u32 - 1)
    }

    /// The id of the `index`-th light, for tools that list lights by position.
    pub fn light_id(&self, index: usize) -> Option<LightId> {
        (index < self.lights.len()).then_some(LightId(index as u32))
    }

    pub fn set_light(&mut self, id: LightId, light: Light) {
        self.revisions.lighting += 1;
        self.changes.lights = true;
        self.lights[id.index()] = light;
    }

    pub fn stylization_world(&self) -> StylizationWorld {
        self.stylization_world
    }

    pub fn set_stylization_world(&mut self, world: StylizationWorld) {
        self.revisions.lighting += 1;
        self.changes.lights = true;
        self.stylization_world = world;
    }

    pub fn set_camera(&mut self, camera: Camera) {
        self.revisions.camera += 1;
        self.changes.camera = true;
        self.camera = camera;
    }

    /// Looks at the scene's bounding sphere from +z (glTF's front) so the whole model is in view.
    /// Use it when the source had no camera. Does nothing for an empty scene.
    pub fn frame_camera(&mut self) {
        let (mut lo, mut hi) = ([f32::MAX; 3], [f32::MIN; 3]);
        for inst in &self.instances {
            for p in self.meshes[inst.mesh.index()].positions() {
                for a in 0..3 {
                    let t = inst.transform[a];
                    let v = t[0] * p[0] + t[1] * p[1] + t[2] * p[2] + t[3];
                    lo[a] = lo[a].min(v);
                    hi[a] = hi[a].max(v);
                }
            }
        }
        if lo[0] > hi[0] {
            return;
        }
        let c: [f32; 3] = std::array::from_fn(|a| (lo[a] + hi[a]) / 2.0);
        let r = (0..3).map(|a| (hi[a] - lo[a]).powi(2)).sum::<f32>().sqrt() / 2.0;
        let mut cam = Camera::default();
        let dist = r / (cam.vertical_fov / 2.0).sin() * 1.05;
        cam.transform[0][3] = c[0];
        cam.transform[1][3] = c[1];
        cam.transform[2][3] = c[2] + dist;
        cam.focus_distance = dist;
        self.set_camera(cam);
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
    use crate::{HybridSurface, StylizationLayer};

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

        let toon = Material {
            stylization: vec![StylizationLayer::HybridSurface(HybridSurface::TOON)],
            ..Default::default()
        };
        s.set_material(material, toon.clone());
        expect.material += 1;
        expect.stylization += 1;
        assert_eq!(s.revisions(), expect);

        s.set_material(material, toon);
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
    fn changes_name_what_to_update() {
        let mut s = Scene::new();
        let mesh = s.add_mesh(tri());
        let material = s.add_material(Material::default());
        let inst = Instance {
            mesh,
            material,
            transform: IDENTITY,
        };
        let id = s.add_instance(inst).unwrap();
        assert!(s.take_changes().geometry);
        assert!(s.take_changes().is_empty());

        let mut moved = inst;
        moved.transform[0][3] = 1.0;
        s.set_instance(id, moved).unwrap();
        s.set_instance(id, moved).unwrap();
        let c = s.take_changes();
        assert_eq!((c.geometry, c.instances.clone()), (false, vec![id]));

        let mut bent = tri();
        let mut p = bent.positions().to_vec();
        p[1][0] = 2.0;
        bent = Mesh::new(p, None, None, vec![0, 1, 2]).unwrap();
        s.set_mesh(mesh, bent);
        let c = s.take_changes();
        assert_eq!((c.geometry, c.deformed), (false, vec![mesh]));

        let m = Material {
            stylization: vec![StylizationLayer::HybridSurface(HybridSurface::TOON)],
            ..Default::default()
        };
        s.set_material(material, m);
        assert!(s.take_changes().is_empty(), "stylization is not GPU data");
        let mut m = Material::default();
        m.base.roughness = 0.1;
        s.set_material(material, m);
        assert_eq!(s.take_changes().materials, vec![material]);

        s.set_camera(Camera::default());
        let light = s.add_light(Light::Environment { color: [1.0; 3] });
        s.set_light(light, Light::Environment { color: [2.0; 3] });
        let c = s.take_changes();
        assert!(c.camera && c.lights && !c.geometry);
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
