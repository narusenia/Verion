use std::{
    path::PathBuf,
    time::{Duration, Instant},
};

use eframe::egui::{self, Align, Align2, Color32, Key, Layout, PointerButton, RichText};
use egui_material_icons::icons::*;
use verion_gpu::{Accumulation as _, Adaptive, Aovs, Integrator, LightingAovs, RayTracingBackend};

/// The GPU backend of this platform (REQ-GPU-003): each platform builds exactly one.
#[cfg(target_os = "macos")]
type Backend = verion_gpu_metal::Renderer;
#[cfg(not(target_os = "macos"))]
type Backend = verion_gpu_vulkan::Renderer;
type Accumulation = <Backend as RayTracingBackend>::Accumulation;
use verion_scene::{Camera, Light, Material, OutputTransform, Scene};
use verion_stylization::{ColorGrade, Frame, PostFrame};

use crate::{
    material_ui::{self, Clipboard},
    theme::{ACCENT, BACKGROUND, BORDER, MUTED, SUCCESS, WARNING},
    widgets::{self, kv, section},
};

#[derive(clap::Parser, Debug)]
#[command(version, about = "Verion progressive viewer")]
pub struct Args {
    /// Input `.gltf` / `.glb`
    scene: PathBuf,
    /// Equirectangular environment map (`.hdr` / `.exr`) used as the sky light
    #[arg(long)]
    hdri: Option<PathBuf>,
    /// Initial render size; it follows the window afterwards
    #[arg(long, default_value_t = 512)]
    width: u32,
    #[arg(long, default_value_t = 384)]
    height: u32,
    /// Stop accumulating at this many samples per pixel
    #[arg(long, default_value_t = 1024)]
    max_spp: u32,
}

/// Samples per GPU dispatch start here and adapt: a dispatch blocks the UI, so each one is sized to
/// take about `FRAME_BUDGET`.
const START_CHUNK: f32 = 4.0;
const MAX_CHUNK: f32 = 16.0;
const FRAME_BUDGET: f32 = 0.014;

/// Longest side of the render. The accumulation is read back to the CPU every frame, so a bigger
/// window does not mean a bigger render.
const MAX_SIDE: f32 = 1024.0;
const MIN_SIDE: f32 = 64.0;
/// A window resize re-renders only after the size has been stable this long.
const RESIZE_SETTLE: Duration = Duration::from_millis(300);
/// After this long without camera motion the first-hit AOVs are redone.
const MOTION_SETTLE: Duration = Duration::from_millis(150);
const DRAG_RAD_PER_PX: f32 = 0.005;

/// Orbit camera around `target`; the scene camera is rebuilt from it on every change.
#[derive(Clone, Copy)]
struct Orbit {
    target: [f32; 3],
    yaw: f32,
    pitch: f32,
    dist: f32,
}

type V3 = [f32; 3];

fn cross(a: V3, b: V3) -> V3 {
    [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]
}

fn normalize(v: V3) -> V3 {
    let n = v.iter().map(|c| c * c).sum::<f32>().sqrt().max(1e-12);
    v.map(|c| c / n)
}

impl Orbit {
    /// Orbits the point `focus_distance` ahead of the camera.
    fn from_camera(cam: &Camera) -> Self {
        let t = cam.transform;
        let z = [t[0][2], t[1][2], t[2][2]];
        let dist = cam.focus_distance.max(1e-3);
        Self {
            target: std::array::from_fn(|a| t[a][3] - z[a] * dist),
            yaw: z[0].atan2(z[2]),
            pitch: z[1].clamp(-1.0, 1.0).asin(),
            dist,
        }
    }

    /// Puts the pivot on the view axis at the depth of `center`, so orbiting keeps turning around
    /// the scene after the eye has moved. A center behind the camera leaves the pivot alone.
    fn repivot(&mut self, center: Option<V3>) {
        let Some(c) = center else { return };
        let (_, _, z) = self.axes();
        let eye = self.eye();
        let along: f32 = (0..3).map(|a| (eye[a] - c[a]) * z[a]).sum();
        if along > 1e-3 {
            self.target = std::array::from_fn(|a| eye[a] - z[a] * along);
            self.dist = along;
        }
    }

    /// Orbits the scene's bounding-box center, measured along the view.
    fn about(cam: &Camera, center: Option<V3>) -> Self {
        let mut o = Self::from_camera(cam);
        o.repivot(center);
        o
    }

    /// Right, up and back axes of the camera.
    fn axes(&self) -> (V3, V3, V3) {
        let (sy, cy) = self.yaw.sin_cos();
        let (sp, cp) = self.pitch.sin_cos();
        let z = [cp * sy, sp, cp * cy];
        let x = normalize([z[2], 0.0, -z[0]]); // up (0,1,0) x z
        (x, cross(z, x), z)
    }

    fn eye(&self) -> V3 {
        let (_, _, z) = self.axes();
        std::array::from_fn(|a| self.target[a] + z[a] * self.dist)
    }

    fn camera(&self, base: &Camera) -> Camera {
        let (x, y, z) = self.axes();
        let mut cam = *base;
        for a in 0..3 {
            cam.transform[a] = [x[a], y[a], z[a], self.target[a] + z[a] * self.dist];
        }
        cam.focus_distance = self.dist;
        cam
    }

    fn orbit(&mut self, dx: f32, dy: f32) {
        self.yaw -= dx * DRAG_RAD_PER_PX;
        self.pitch = (self.pitch + dy * DRAG_RAD_PER_PX).clamp(-1.5, 1.5);
    }

    /// Turns the view with the eye fixed.
    fn look(&mut self, dx: f32, dy: f32) {
        let eye = self.eye();
        self.orbit(dx, dy);
        let (_, _, z) = self.axes();
        self.target = std::array::from_fn(|a| eye[a] - z[a] * self.dist);
    }

    /// Slides along the image plane.
    fn pan(&mut self, right: f32, up: f32) {
        let (x, y, _) = self.axes();
        for a in 0..3 {
            self.target[a] += x[a] * right + y[a] * up;
        }
    }

    /// Fly: forward along the view, sideways, and along world up.
    fn walk(&mut self, forward: f32, right: f32, up: f32) {
        let (x, _, z) = self.axes();
        for a in 0..3 {
            self.target[a] += x[a] * right - z[a] * forward + if a == 1 { up } else { 0.0 };
        }
    }
}

#[derive(Clone, Copy, PartialEq)]
enum View {
    Beauty,
    Albedo,
    Normal,
    Depth,
    /// Samples per pixel, white at the max spp (adaptive sampling).
    Samples,
}

const VIEWS: [(View, &str, &str); 5] = [
    (View::Beauty, "Beauty", "1"),
    (View::Albedo, "Albedo", "2"),
    (View::Normal, "Normal", "3"),
    (View::Depth, "Depth", "4"),
    (View::Samples, "Samples", "5"),
];

struct Stats {
    meshes: usize,
    instances: usize,
    triangles: usize,
    vertices: usize,
    images: usize,
}

pub struct App {
    scene: Scene,
    renderer: Backend,
    acc: Accumulation,
    normals: Vec<[f32; 3]>,
    aov: Aovs,
    width: u32,
    height: u32,
    max_spp: u32,
    view: View,
    stylized: bool,
    multiscatter: bool,
    integrator: Integrator,
    /// Per-pixel adaptive sampling (REQ-ACC-007), with its threshold kept while off.
    adaptive: bool,
    adaptive_threshold: f32,
    /// Pixels that still take samples, counted after each accumulate.
    active: usize,
    /// Denoise the finished (or paused) accumulation with OIDN (ADR-0013).
    denoise: bool,
    /// Loaded on first use; the error is shown when OIDN is missing.
    denoiser: Option<Result<verion_denoise::Denoiser, String>>,
    /// Denoised beauty and lighting split for the accumulation at this sample count.
    denoised: Option<(u32, Vec<[f32; 3]>, Option<LightingAovs>)>,
    paused: bool,
    grade: ColorGrade,
    /// View-only gain in stops for the beauty pass.
    exposure: f32,
    /// The texture is stale: samples, view or a parameter changed.
    dirty: bool,
    texture: Option<egui::TextureHandle>,
    /// What the texture shows, linear, for the pixel readout.
    shown: Vec<[f32; 3]>,
    hover: Option<(usize, usize)>,
    orbit: Orbit,
    home: Camera,
    /// Bounding-box center and half-diagonal of the instances.
    bounds: Option<(V3, f32)>,
    /// The camera moved recently: samples are kept small and the AOVs wait.
    last_move: Instant,
    aov_stale: bool,
    /// New samples wait here until the picture may be rebuilt (see `upload_due`).
    samples_dirty: bool,
    chunk: f32,
    last_upload: Instant,
    material: usize,
    instance: usize,
    original_materials: Vec<Material>,
    clipboard: Clipboard,
    /// A window size waiting to settle before the render follows it.
    pending_size: Option<((u32, u32), Instant)>,
    stats: Stats,
    /// Fly speed in view distances per second.
    speed: f32,
    show_panels: bool,
    show_help: bool,
    spp_rate: f32,
    last_tick: Instant,
    fps: f32,
}

fn resolve_hdri(scene: &mut Scene, args: &Args) -> Result<(), String> {
    if let Some(path) = &args.hdri {
        let image = verion_render_io::load_hdri(path, scene.working_space())
            .map_err(|e| format!("hdri {}: {e}", path.display()))?;
        let image = scene.add_image(image);
        scene.add_light(Light::EnvironmentMap { image, scale: 1.0 });
    }
    Ok(())
}

impl App {
    pub fn new(args: &Args) -> Result<Self, String> {
        if args.width == 0 || args.height == 0 {
            return Err("width and height must be at least 1".into());
        }
        let import =
            verion_render_io::load_gltf_in(&args.scene, verion_scene::ColorSpace::LinearRec709)
                .map_err(|e| format!("load {}: {e}", args.scene.display()))?;
        for w in &import.warnings {
            eprintln!("warning: {w}");
        }
        let mut scene = import.scene;
        if *scene.camera() == Camera::default() {
            scene.frame_camera();
        }
        resolve_hdri(&mut scene, args)?;
        let ctx = Backend::context().map_err(|e| format!("GPU ray tracing is required: {e}"))?;
        let renderer = Backend::new(&ctx, &scene).map_err(|e| format!("renderer: {e:?}"))?;
        let (w, h) = (args.width, args.height);
        let acc = renderer
            .new_accumulation(w, h, true)
            .map_err(|e| format!("render: {e:?}"))?;
        let normals = renderer
            .render_normals(w, h)
            .map_err(|e| format!("normals: {e:?}"))?;
        let aov = renderer
            .render_aovs(w, h)
            .map_err(|e| format!("aovs: {e:?}"))?;
        let orbit = Orbit::about(scene.camera(), Self::scene_bounds(&scene).map(|b| b.0));
        let tris = |i: &verion_scene::Instance| scene.meshes()[i.mesh.index()].indices().len() / 3;
        let stats = Stats {
            meshes: scene.meshes().len(),
            instances: scene.instances().len(),
            triangles: scene.instances().iter().map(tris).sum(),
            vertices: scene
                .instances()
                .iter()
                .map(|i| scene.meshes()[i.mesh.index()].positions().len())
                .sum(),
            images: scene.images().len(),
        };
        Ok(Self {
            home: *scene.camera(),
            bounds: Self::scene_bounds(&scene),
            last_move: Instant::now() - MOTION_SETTLE,
            aov_stale: false,
            samples_dirty: false,
            chunk: START_CHUNK,
            last_upload: Instant::now(),
            original_materials: scene.materials().to_vec(),
            scene,
            renderer,
            acc,
            normals,
            aov,
            width: w,
            height: h,
            max_spp: args.max_spp,
            view: View::Beauty,
            stylized: false,
            multiscatter: true,
            integrator: Integrator::Megakernel,
            adaptive: false,
            adaptive_threshold: Adaptive::default().threshold,
            active: (w * h) as usize,
            denoise: false,
            denoiser: None,
            denoised: None,
            paused: false,
            grade: ColorGrade::default(),
            exposure: 0.0,
            dirty: true,
            texture: None,
            shown: Vec::new(),
            hover: None,
            orbit,
            material: 0,
            instance: 0,
            clipboard: None,
            pending_size: None,
            stats,
            speed: 1.0,
            show_panels: true,
            show_help: false,
            spp_rate: 0.0,
            last_tick: Instant::now(),
            fps: 60.0,
        })
    }

    /// The first-hit AOVs belong to the camera and the size.
    fn fetch_aovs(&mut self) {
        let (w, h) = (self.width, self.height);
        match (
            self.renderer.render_normals(w, h),
            self.renderer.render_aovs(w, h),
        ) {
            (Ok(n), Ok(a)) => (self.normals, self.aov) = (n, a),
            (n, a) => eprintln!("aovs: {:?}", n.err().or(a.err())),
        }
        self.aov_stale = false;
    }

    /// New AOVs and a new accumulation, for a change of size, scene or renderer.
    fn refresh_aovs(&mut self) {
        self.fetch_aovs();
        self.restart();
    }

    /// Pushes the scene camera (orbit pose plus lens) to the renderer. The AOVs only matter to the
    /// stylized and AOV views, so for the beauty pass they are redone once the camera settles;
    /// reading them back every frame is what makes flying choppy.
    fn move_camera(&mut self) {
        let cam = self.orbit.camera(self.scene.camera());
        self.scene.set_camera(cam);
        self.renderer.set_camera(&cam);
        self.last_move = Instant::now();
        if self.view == View::Beauty && !self.stylized {
            self.aov_stale = true;
            self.restart();
        } else {
            self.refresh_aovs();
        }
    }

    /// Sends the scene edits made since the last call to the renderer, which redoes only what they
    /// touch (REQ-ACC-003), and starts the accumulation over (IPR, REQ-VIEW-003).
    fn apply_edits(&mut self) {
        let changes = self.scene.take_changes();
        if changes.is_empty() {
            return;
        }
        match self.renderer.update(&self.scene, &changes) {
            Ok(_) => self.refresh_aovs(),
            Err(e) => eprintln!("update: {e:?}"),
        }
    }

    /// Center of the instances' bounding box in world space.
    fn scene_bounds(scene: &Scene) -> Option<(V3, f32)> {
        let (mut lo, mut hi) = ([f32::MAX; 3], [f32::MIN; 3]);
        for inst in scene.instances() {
            for p in scene.meshes()[inst.mesh.index()].positions() {
                for a in 0..3 {
                    let t = inst.transform[a];
                    let v = t[0] * p[0] + t[1] * p[1] + t[2] * p[2] + t[3];
                    lo[a] = lo[a].min(v);
                    hi[a] = hi[a].max(v);
                }
            }
        }
        (lo[0] <= hi[0]).then(|| {
            let center = std::array::from_fn(|a| (lo[a] + hi[a]) / 2.0);
            let radius = (0..3).map(|a| (hi[a] - lo[a]).powi(2)).sum::<f32>().sqrt() / 2.0;
            (center, radius)
        })
    }

    fn center(&self) -> Option<V3> {
        self.bounds.map(|b| b.0)
    }

    fn frame_scene(&mut self) {
        let lens = *self.scene.camera();
        self.scene.frame_camera();
        let mut cam = *self.scene.camera();
        (cam.vertical_fov, cam.aperture_radius) = (lens.vertical_fov, lens.aperture_radius);
        self.orbit = Orbit::about(&cam, self.center());
        self.scene.set_camera(cam);
        self.move_camera();
    }

    fn reset_camera(&mut self) {
        self.scene.set_camera(self.home);
        self.orbit = Orbit::about(&self.home, self.center());
        self.move_camera();
    }

    /// Follows the window once its size has been stable for `RESIZE_SETTLE`.
    fn follow_size(&mut self, ctx: &egui::Context, avail: egui::Vec2) {
        let k = (MAX_SIDE / avail.x.max(avail.y)).min(1.0);
        let size = (
            (avail.x * k).max(MIN_SIDE) as u32,
            (avail.y * k).max(MIN_SIDE) as u32,
        );
        if size == (self.width, self.height) {
            self.pending_size = None;
            return;
        }
        let since = match self.pending_size {
            Some((s, t)) if s == size => t,
            _ => Instant::now(),
        };
        self.pending_size = Some((size, since));
        if since.elapsed() >= RESIZE_SETTLE {
            (self.width, self.height) = size;
            self.pending_size = None;
            self.refresh_aovs();
        } else {
            ctx.request_repaint_after(RESIZE_SETTLE / 3);
        }
    }

    /// Only the stylized beauty reads the per-component lighting buffers, which are ~65 floats per
    /// pixel; skipping them keeps a restart per frame cheap while the camera moves.
    fn restart(&mut self) {
        let (w, h) = (self.width, self.height);
        let acc = self.renderer.new_accumulation(w, h, self.stylized);
        match acc {
            Ok(acc) => {
                self.active = acc.active_pixels();
                self.acc = acc;
            }
            Err(e) => eprintln!("render: {e:?}"),
        }
        self.denoised = None;
        self.dirty = true;
    }

    fn adaptive_setting(&self) -> Option<Adaptive> {
        self.adaptive.then(|| Adaptive {
            threshold: self.adaptive_threshold,
            ..Adaptive::default()
        })
    }

    /// The accumulation reached the max spp, or adaptive sampling stopped every pixel.
    fn done(&self) -> bool {
        self.acc.samples() >= self.max_spp || self.active == 0
    }

    /// Denoising takes about a second, so it runs once the accumulation is done or paused.
    fn denoise_ready(&self) -> bool {
        self.denoise && self.acc.samples() > 0 && (self.done() || self.paused)
    }

    /// Beauty and (stylized only) lighting split, denoised when `denoise_ready`. A stylized frame
    /// denoises the Pass input, so Toon bands are cut after the denoiser (as `render-cli` does).
    fn beauty_inputs(&mut self) -> (Vec<[f32; 3]>, Option<LightingAovs>) {
        let lighting = || {
            if self.stylized {
                self.acc.lighting()
            } else {
                None
            }
        };
        if !self.denoise_ready() {
            return (self.acc.mean(), lighting());
        }
        let spp = self.acc.samples();
        if let Some((at, b, l)) = &self.denoised
            && *at == spp
        {
            return (b.clone(), l.clone());
        }
        let (mut beauty, mut light) = (self.acc.mean(), lighting());
        let d = self
            .denoiser
            .get_or_insert_with(|| verion_denoise::Denoiser::load().map_err(|e| e.to_string()));
        if let Ok(d) = d {
            let aux = verion_denoise::Aux {
                albedo: Some(&self.aov.albedo),
                normal: Some(&self.normals),
            };
            let (w, h) = (self.width as usize, self.height as usize);
            let result = match light.as_mut() {
                Some(l) => l.for_each_radiance(|p| d.denoise(p, aux, w, h)),
                None => d.denoise(&mut beauty, aux, w, h),
            };
            if let Err(e) = result {
                eprintln!("denoise: {e}");
            }
        }
        self.denoised = Some((spp, beauty.clone(), light.clone()));
        (beauty, light)
    }

    /// The displayed image in the working space (linear), before the display transform.
    fn linear_image(&mut self) -> Vec<[f32; 3]> {
        match self.view {
            View::Albedo => self.aov.albedo.clone(),
            View::Normal => self
                .normals
                .iter()
                .map(|n| n.map(|v| v * 0.5 + 0.5))
                .collect(),
            View::Samples => {
                let max = self.max_spp.max(1) as f32;
                match self.acc.sample_counts() {
                    Some(n) => n.iter().map(|&n| [n as f32 / max; 3]).collect(),
                    None => vec![[self.acc.samples() as f32 / max; 3]; self.shown_len()],
                }
            }
            View::Depth => {
                let far = self.aov.depth.iter().copied().fold(0.0, f32::max).max(1e-6);
                self.aov.depth.iter().map(|d| [d / far; 3]).collect()
            }
            View::Beauty => {
                let (mut beauty, lighting) = self.beauty_inputs();
                if let (true, Some(l)) = (self.stylized, lighting) {
                    beauty = verion_stylization::stylize_image(
                        self.scene.materials(),
                        &Frame {
                            direct_diffuse: &l.direct_diffuse,
                            indirect_diffuse: &l.indirect_diffuse,
                            specular: &l.specular,
                            transmission: &l.transmission,
                            emission: &l.emission,
                            light_u: &l.light_u,
                            light_response: &l.light_response,
                            light_s: &l.light_s,
                            light_dir: &l.light_dir,
                            light_lit: &l.light_lit,
                            normal: &self.normals,
                            albedo: &self.aov.albedo,
                            material_id: &self.aov.material_id,
                            images: self.scene.images(),
                            camera: *self.scene.camera(),
                            width: self.width as usize,
                        },
                    );
                    verion_stylization::outline(
                        self.scene.materials(),
                        &PostFrame {
                            width: self.width as usize,
                            depth: &self.aov.depth,
                            normal: &self.normals,
                            object_id: &self.aov.object_id,
                            material_id: &self.aov.material_id,
                        },
                        &mut beauty,
                    );
                    verion_stylization::color_grade(&mut beauty, &self.grade);
                }
                beauty
            }
        }
    }

    fn shown_len(&self) -> usize {
        self.width as usize * self.height as usize
    }

    /// Rebuilding the picture reads the whole accumulation back and converts every pixel, so it is
    /// done often while the image is rough (few samples) and rarely once it has converged.
    fn upload_due(&self) -> bool {
        let spp = self.acc.samples();
        let wait = Duration::from_millis((u64::from(spp) / 2).clamp(30, 500));
        let moving = self.last_move.elapsed() < MOTION_SETTLE;
        moving || self.done() || self.paused || self.last_upload.elapsed() >= wait
    }

    /// Stylization needs the lighting buffers, so switching it starts a new accumulation.
    fn set_stylized(&mut self, on: bool) {
        self.stylized = on;
        self.restart();
    }

    fn refresh_picture(&mut self, ctx: &egui::Context) {
        if self.samples_dirty && self.upload_due() {
            self.dirty = true;
        }
        if self.dirty {
            self.upload(ctx);
        }
    }

    fn upload(&mut self, ctx: &egui::Context) {
        // A fresh accumulation has no samples and averages to black; keep the last picture until
        // the first samples land. After a resize the old picture no longer fits, so show black then.
        let fits = self.shown.len() == self.width as usize * self.height as usize;
        if self.view == View::Beauty && self.acc.samples() == 0 && fits {
            return;
        }
        let display = OutputTransform::display();
        let space = self.scene.working_space();
        let mut lin = self.linear_image();
        if self.view == View::Beauty && self.exposure != 0.0 {
            let gain = self.exposure.exp2();
            for p in &mut lin {
                *p = p.map(|v| v * gain);
            }
        }
        let rgb: Vec<u8> = lin
            .iter()
            .flat_map(|p| display.apply(space, *p).map(|v| (v * 255.0 + 0.5) as u8))
            .collect();
        self.shown = lin;
        let image = egui::ColorImage::from_rgb([self.width as usize, self.height as usize], &rgb);
        match &mut self.texture {
            Some(t) => t.set(image, egui::TextureOptions::NEAREST),
            None => {
                self.texture = Some(ctx.load_texture("view", image, egui::TextureOptions::NEAREST));
            }
        }
        self.dirty = false;
        self.samples_dirty = false;
        self.last_upload = Instant::now();
    }

    /// Keyboard: WASD / arrows fly, Q / E down / up, Shift fast, Ctrl slow; the rest are toggles.
    fn keys(&mut self, ctx: &egui::Context) {
        if ctx.egui_wants_keyboard_input() {
            return;
        }
        let (dt, axis, fast, slow, cmd) = ctx.input(|i| {
            // A tap shorter than one frame still counts as a step.
            let k = |key| f32::from(u8::from(i.key_down(key) || i.key_pressed(key)));
            (
                i.stable_dt.min(0.05),
                [
                    k(Key::W) + k(Key::ArrowUp) - k(Key::S) - k(Key::ArrowDown),
                    k(Key::D) + k(Key::ArrowRight) - k(Key::A) - k(Key::ArrowLeft),
                    k(Key::E) - k(Key::Q),
                ],
                i.modifiers.shift,
                i.modifiers.ctrl,
                i.modifiers.command,
            )
        });
        if cmd {
            return;
        }
        let pressed = |key| ctx.input(|i| i.key_pressed(key));
        for (v, _, key) in VIEWS {
            let k = match key {
                "1" => Key::Num1,
                "2" => Key::Num2,
                "3" => Key::Num3,
                "4" => Key::Num4,
                _ => Key::Num5,
            };
            if pressed(k) {
                self.view = v;
                self.dirty = true;
            }
        }
        if pressed(Key::T) {
            self.set_stylized(!self.stylized);
        }
        if pressed(Key::Space) {
            self.paused = !self.paused;
        }
        if pressed(Key::Backspace) {
            self.restart();
        }
        if pressed(Key::F) {
            self.frame_scene();
        }
        if pressed(Key::R) {
            self.reset_camera();
        }
        if pressed(Key::Tab) {
            self.show_panels = !self.show_panels;
        }
        if pressed(Key::H) || pressed(Key::F1) {
            self.show_help = !self.show_help;
        }
        if axis != [0.0; 3] {
            let gear = if fast {
                4.0
            } else if slow {
                0.25
            } else {
                1.0
            };
            let reach = self.orbit.dist.max(self.bounds.map_or(0.0, |b| b.1 * 0.05));
            let step = reach * self.speed * gear * dt;
            self.orbit
                .walk(axis[0] * step, axis[1] * step, axis[2] * step);
            self.orbit.repivot(self.center());
            self.move_camera();
            ctx.request_repaint();
        }
    }

    fn toolbar(&mut self, ui: &mut egui::Ui) {
        egui::Panel::top("toolbar").show(ui, |ui| {
            ui.horizontal_centered(|ui| {
                for (v, name, key) in VIEWS {
                    let icon = match v {
                        View::Beauty => ICON_IMAGE,
                        View::Albedo => ICON_PALETTE,
                        View::Normal => ICON_TEXTURE,
                        View::Depth => ICON_LAYERS,
                        View::Samples => ICON_GRAIN,
                    };
                    let r = ui.selectable_label(self.view == v, (icon.rich_text(), name));
                    if r.on_hover_text(format!("Show {name} ({key})")).clicked() {
                        self.view = v;
                        self.dirty = true;
                    }
                }
                ui.separator();
                let r = ui
                    .selectable_label(self.stylized, (ICON_AUTO_FIX_HIGH.rich_text(), "Stylized"));
                if r.on_hover_text("Non-physical stylization (T)").clicked() {
                    self.set_stylized(!self.stylized);
                }
                ui.separator();
                let (icon, label) = if self.paused {
                    (ICON_PLAY_ARROW, "Resume")
                } else {
                    (ICON_PAUSE, "Pause")
                };
                if ui
                    .button((icon.rich_text(), label))
                    .on_hover_text("Space")
                    .clicked()
                {
                    self.paused = !self.paused;
                }
                if ui
                    .button((ICON_RESTART_ALT.rich_text(), "Restart"))
                    .on_hover_text("Backspace")
                    .clicked()
                {
                    self.restart();
                }
                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    if ui
                        .button(ICON_HELP.rich_text())
                        .on_hover_text("Shortcuts (H)")
                        .clicked()
                    {
                        self.show_help = !self.show_help;
                    }
                    let panels = ui.selectable_label(
                        self.show_panels,
                        (ICON_VIEW_SIDEBAR.rich_text(), "Inspector"),
                    );
                    if panels.on_hover_text("Tab").clicked() {
                        self.show_panels = !self.show_panels;
                    }
                    let spp = self.acc.samples();
                    let rate = if self.paused || self.done() {
                        String::new()
                    } else {
                        format!("  {:.0} spp/s", self.spp_rate)
                    };
                    ui.add(
                        egui::ProgressBar::new(spp as f32 / self.max_spp as f32)
                            .desired_width(190.0)
                            .text(format!("{spp} / {} spp{rate}", self.max_spp)),
                    );
                });
            });
        });
    }

    fn statusbar(&mut self, ui: &mut egui::Ui) {
        egui::Panel::bottom("status").show(ui, |ui| {
            ui.horizontal_centered(|ui| {
                let mono = |s: String| RichText::new(s).monospace().color(MUTED);
                match self.hover.filter(|_| !self.shown.is_empty()) {
                    Some((x, y)) => {
                        let i = y * self.width as usize + x;
                        let c = self.shown[i];
                        let n = self.normals[i];
                        let swatch = OutputTransform::display()
                            .apply(self.scene.working_space(), c)
                            .map(|v| (v.clamp(0.0, 1.0) * 255.0 + 0.5) as u8);
                        let (rect, _) =
                            ui.allocate_exact_size(egui::vec2(12.0, 12.0), egui::Sense::hover());
                        ui.painter().rect_filled(
                            rect,
                            2.0,
                            Color32::from_rgb(swatch[0], swatch[1], swatch[2]),
                        );
                        let mat = self.aov.material_id[i];
                        let mat = if mat == 0 { "-".into() } else { format!("{}", mat - 1) };
                        ui.label(mono(format!(
                            "({x},{y})  RGB {:.3} {:.3} {:.3}  Z {:.3}  N {:+.2} {:+.2} {:+.2}  mat {mat}  obj {}",
                            c[0], c[1], c[2], self.aov.depth[i], n[0], n[1], n[2],
                            self.aov.object_id[i].saturating_sub(1),
                        )));
                    }
                    None => {
                        ui.label(mono("hover the image for pixel values".into()));
                    }
                }
                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    let eye = self.orbit.eye();
                    ui.label(mono(format!(
                        "{}x{}  eye {:.2} {:.2} {:.2}  {:.0} fps",
                        self.width, self.height, eye[0], eye[1], eye[2], self.fps
                    )));
                });
            });
        });
    }

    fn inspector(&mut self, ui: &mut egui::Ui) {
        egui::Panel::right("inspector")
            .default_size(290.0)
            .size_range(240.0..=480.0)
            .show(ui, |ui| {
                egui::ScrollArea::vertical().show(ui, |ui| {
                    ui.spacing_mut().item_spacing.y = 3.0;
                    section(ui, ICON_PHOTO_CAMERA, "Camera", true, |ui| {
                        self.camera_section(ui)
                    });
                    section(ui, ICON_MOTION_PHOTOS_ON, "Render", true, |ui| {
                        self.render_section(ui)
                    });
                    section(ui, ICON_EXPOSURE, "Display", true, |ui| {
                        self.display_section(ui)
                    });
                    section(ui, ICON_PALETTE, "Material", true, |ui| {
                        self.material_section(ui)
                    });
                    section(ui, ICON_LIGHTBULB, "Lights", false, |ui| {
                        self.lights_section(ui)
                    });
                    section(ui, ICON_LAYERS, "Instances", false, |ui| {
                        self.instances_section(ui)
                    });
                    section(ui, ICON_LAYERS, "Scene", false, |ui| self.scene_section(ui));
                });
            });
    }

    fn camera_section(&mut self, ui: &mut egui::Ui) {
        let mut cam = *self.scene.camera();
        let mut fov = cam.vertical_fov.to_degrees();
        let shown = fov;
        widgets::slider(ui, &mut fov, 10.0..=120.0, "fov deg");
        // The slider rounds to 2 decimals, which a radians round trip reports as a change.
        let mut changed = (fov - shown).abs() > 0.006;
        cam.vertical_fov = fov.to_radians();
        changed |= widgets::slider(ui, &mut cam.aperture_radius, 0.0..=0.5, "aperture");
        let mut dist = self.orbit.dist;
        if widgets::log_slider(ui, &mut dist, 0.01..=1000.0, "distance") {
            self.orbit.dist = dist;
            changed = true;
        }
        widgets::log_slider(ui, &mut self.speed, 0.1..=10.0, "fly speed");
        let eye = self.orbit.eye();
        kv(
            ui,
            "eye",
            format!("{:.2} {:.2} {:.2}", eye[0], eye[1], eye[2]),
        );
        let t = self.orbit.target;
        kv(ui, "target", format!("{:.2} {:.2} {:.2}", t[0], t[1], t[2]));
        kv(
            ui,
            "yaw / pitch",
            format!(
                "{:.1} / {:.1} deg",
                self.orbit.yaw.to_degrees(),
                self.orbit.pitch.to_degrees()
            ),
        );
        ui.horizontal(|ui| {
            if ui
                .button((ICON_FIT_SCREEN.rich_text(), "Frame (F)"))
                .clicked()
            {
                self.frame_scene();
            }
            if ui.button((ICON_HOME.rich_text(), "Reset (R)")).clicked() {
                self.reset_camera();
            }
        });
        if changed {
            self.scene.set_camera(cam);
            self.move_camera();
        }
    }

    fn render_section(&mut self, ui: &mut egui::Ui) {
        let spp = self.acc.samples();
        kv(ui, "samples", format!("{spp} / {}", self.max_spp));
        kv(ui, "gpu time", format!("{:.2} s", self.acc.gpu_seconds()));
        kv(ui, "size", format!("{} x {}", self.width, self.height));
        widgets::row(ui, "max spp", |ui| {
            ui.add(
                egui::DragValue::new(&mut self.max_spp)
                    .speed(16.0)
                    .range(1..=1_000_000),
            )
        });
        if widgets::checkbox(
            ui,
            &mut self.multiscatter,
            "Multiple-scattering compensation",
        ) {
            self.renderer.set_multiscatter(self.multiscatter);
            self.restart();
        }
        let mut integrator = self.integrator;
        widgets::row(ui, "integrator", |ui| {
            ui.radio_value(&mut integrator, Integrator::Megakernel, "Megakernel")
                | ui.radio_value(&mut integrator, Integrator::Wavefront, "Wavefront")
        })
        .on_hover_text("Same image; wavefront splits each bounce into queued stages (M3)");
        if integrator != self.integrator {
            self.integrator = integrator;
            self.renderer.set_integrator(integrator);
            self.restart();
        }
        let mut adaptive_changed = widgets::checkbox(ui, &mut self.adaptive, "Adaptive sampling");
        ui.add_enabled_ui(self.adaptive, |ui| {
            adaptive_changed |= widgets::log_slider(
                ui,
                &mut self.adaptive_threshold,
                0.005..=0.2,
                "noise threshold",
            );
            let pixels = self.shown_len().max(1);
            kv(
                ui,
                "active pixels",
                format!("{:.1} %", 100.0 * self.active as f32 / pixels as f32),
            );
        })
        .response
        .on_hover_text(
            "Each pixel stops once its noise is under the threshold (relative standard error); \
             view 5 shows the samples per pixel. Slightly biased, so not physical",
        );
        if adaptive_changed {
            self.renderer.set_adaptive(self.adaptive_setting());
            self.restart();
        }
        if widgets::checkbox(ui, &mut self.denoise, "Denoise when done (OIDN)") {
            self.dirty = true;
        }
        if self.denoise
            && let Some(Err(e)) = &self.denoiser
        {
            ui.colored_label(WARNING, e);
        }
    }

    fn display_section(&mut self, ui: &mut egui::Ui) {
        let before = (self.exposure, self.grade);
        widgets::slider(ui, &mut self.exposure, -6.0..=6.0, "exposure EV");
        ui.add_enabled_ui(self.stylized && self.view == View::Beauty, |ui| {
            let g = &mut self.grade;
            widgets::slider(ui, &mut g.exposure, -4.0..=4.0, "grade EV");
            widgets::slider(ui, &mut g.saturation, 0.0..=2.0, "saturation");
            for (w, name) in g.white_balance.iter_mut().zip(["wb R", "wb G", "wb B"]) {
                widgets::slider(ui, w, 0.0..=2.0, name);
            }
        })
        .response
        .on_disabled_hover_text(
            "The grade applies to the stylized beauty only (Reference stays physical)",
        );
        if ui
            .button((ICON_RESTORE.rich_text(), "Reset display"))
            .clicked()
        {
            (self.exposure, self.grade) = (0.0, ColorGrade::default());
        }
        self.dirty |= before != (self.exposure, self.grade);
    }

    fn material_section(&mut self, ui: &mut egui::Ui) {
        let count = self.scene.materials().len();
        if count == 0 {
            return;
        }
        self.material = self.material.min(count - 1);
        let i = self.material;
        ui.horizontal(|ui| {
            egui::ComboBox::from_id_salt("material")
                .selected_text(format!("material {i}"))
                .show_ui(ui, |ui| {
                    for k in 0..count {
                        ui.selectable_value(&mut self.material, k, format!("material {k}"));
                    }
                });
            ui.label(
                RichText::new("click the image to pick")
                    .small()
                    .color(MUTED),
            );
        });
        let i = self.material;
        let current = self.scene.materials()[i].clone();
        let mut edited = current.clone();
        material_ui::edit(
            ui,
            &mut edited,
            &self.original_materials[i],
            &mut self.clipboard,
            &self.scene.image_ids(),
        );
        if edited != current
            && let Some(id) = self.scene.material_id(i)
        {
            let physical = edited.base != current.base;
            self.scene.set_material(id, edited);
            if physical {
                self.apply_edits();
            } else {
                // Stylization is a post pass: no new samples are needed.
                self.dirty = true;
            }
        }
    }

    /// Moves an instance: only the top-level structure is rebuilt, not the meshes' own.
    fn instances_section(&mut self, ui: &mut egui::Ui) {
        let n = self.scene.instances().len();
        self.instance = self.instance.min(n.saturating_sub(1));
        egui::ComboBox::from_id_salt("instance")
            .selected_text(format!("instance {}", self.instance))
            .show_ui(ui, |ui| {
                for k in 0..n {
                    ui.selectable_value(&mut self.instance, k, format!("instance {k}"));
                }
            });
        let Some(id) = self.scene.instance_id(self.instance) else {
            return;
        };
        let mut inst = self.scene.instances()[self.instance];
        let mut at = [
            inst.transform[0][3],
            inst.transform[1][3],
            inst.transform[2][3],
        ];
        let step = self.bounds.map_or(0.05, |b| b.1 * 0.01);
        if widgets::vec3(ui, &mut at, "position", step) {
            for (row, v) in inst.transform.iter_mut().zip(at) {
                row[3] = v;
            }
            if self.scene.set_instance(id, inst).is_ok() {
                self.apply_edits();
            }
        }
    }

    fn lights_section(&mut self, ui: &mut egui::Ui) {
        let mut changed = false;
        for i in 0..self.scene.lights().len() {
            let mut light = self.scene.lights()[i];
            let title = match light {
                Light::Point { .. } => "Point",
                Light::Directional { .. } => "Directional",
                Light::Spot { .. } => "Spot",
                Light::Environment { .. } => "Environment (uniform)",
                Light::EnvironmentMap { .. } => "Environment (HDRI)",
            };
            egui::CollapsingHeader::new(format!("{i}  {title}"))
                .id_salt(("light", i))
                .default_open(true)
                .show(ui, |ui| match &mut light {
                    Light::Point {
                        position,
                        color,
                        intensity,
                    } => {
                        changed |= widgets::vec3(ui, position, "position", 0.05);
                        changed |= widgets::color(ui, color, "color");
                        changed |= widgets::log_slider(ui, intensity, 0.01..=10_000.0, "intensity");
                    }
                    Light::Directional {
                        direction,
                        color,
                        intensity,
                    } => {
                        changed |= widgets::vec3(ui, direction, "direction", 0.02);
                        changed |= widgets::color(ui, color, "color");
                        changed |= widgets::log_slider(ui, intensity, 0.01..=1000.0, "intensity");
                    }
                    Light::Spot {
                        position,
                        direction,
                        color,
                        intensity,
                        inner_cone,
                        outer_cone,
                    } => {
                        changed |= widgets::vec3(ui, position, "position", 0.05);
                        changed |= widgets::vec3(ui, direction, "direction", 0.02);
                        changed |= widgets::color(ui, color, "color");
                        changed |= widgets::log_slider(ui, intensity, 0.01..=10_000.0, "intensity");
                        let mut outer = outer_cone.to_degrees();
                        if widgets::slider(ui, &mut outer, 1.0..=90.0, "outer deg") {
                            *outer_cone = outer.to_radians();
                            *inner_cone = inner_cone.min(*outer_cone * 0.99);
                            changed = true;
                        }
                        let mut inner = inner_cone.to_degrees();
                        if widgets::slider(ui, &mut inner, 0.0..=outer * 0.99, "inner deg") {
                            *inner_cone = inner.to_radians();
                            changed = true;
                        }
                    }
                    Light::Environment { color } => {
                        changed |= widgets::hdr(ui, color, "color");
                    }
                    Light::EnvironmentMap { scale, .. } => {
                        changed |= widgets::log_slider(ui, scale, 0.01..=100.0, "scale");
                    }
                });
            if light != self.scene.lights()[i]
                && let Some(id) = self.scene.light_id(i)
            {
                self.scene.set_light(id, light);
            }
        }
        if changed {
            self.apply_edits();
        }
    }

    fn scene_section(&mut self, ui: &mut egui::Ui) {
        let s = &self.stats;
        kv(ui, "meshes", s.meshes.to_string());
        kv(ui, "instances", s.instances.to_string());
        kv(ui, "triangles", s.triangles.to_string());
        kv(ui, "vertices", s.vertices.to_string());
        kv(ui, "materials", self.scene.materials().len().to_string());
        kv(ui, "lights", self.scene.lights().len().to_string());
        kv(ui, "images", s.images.to_string());
        kv(
            ui,
            "color space",
            format!("{:?}", self.scene.working_space()),
        );
    }

    fn viewport(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        egui::CentralPanel::default()
            .frame(egui::Frame::new().fill(BACKGROUND))
            .show(ui, |ui| {
                let avail = ui.available_rect_before_wrap();
                self.follow_size(ctx, avail.size());
                let Some(tid) = self.texture.as_ref().map(egui::TextureHandle::id) else {
                    return;
                };
                let img = egui::vec2(self.width as f32, self.height as f32);
                let fit = (avail.width() / img.x).min(avail.height() / img.y);
                let rect = Align2::CENTER_CENTER.align_size_within_rect(img * fit, avail);
                let r = ui.allocate_rect(rect, egui::Sense::click_and_drag());
                let uv = egui::Rect::from_min_max(egui::pos2(0.0, 0.0), egui::pos2(1.0, 1.0));
                ui.painter().image(tid, rect, uv, Color32::WHITE);

                self.hover = r.hover_pos().map(|p| {
                    let u = ((p.x - rect.min.x) / rect.width()).clamp(0.0, 0.9999);
                    let v = ((p.y - rect.min.y) / rect.height()).clamp(0.0, 0.9999);
                    (
                        (u * self.width as f32) as usize,
                        (v * self.height as f32) as usize,
                    )
                });
                if r.clicked_by(PointerButton::Primary)
                    && let Some((x, y)) = self.hover
                {
                    let id = self.aov.material_id[y * self.width as usize + x];
                    if id > 0 {
                        self.material = id as usize - 1;
                    }
                }
                self.navigate(ctx, &r, rect);
                self.overlay(ui, rect);
            });
    }

    /// Mouse: left orbit, right look, middle or Shift+left pan, wheel dolly.
    fn navigate(&mut self, ctx: &egui::Context, r: &egui::Response, rect: egui::Rect) {
        let d = r.drag_delta();
        let shift = ctx.input(|i| i.modifiers.shift);
        let (scroll, pinch) = if r.hovered() {
            ctx.input(|i| (i.smooth_scroll_delta.y, i.zoom_delta()))
        } else {
            (0.0, 1.0)
        };
        let center = self.center();
        let mut moved = false;
        if d != egui::Vec2::ZERO {
            let o = &mut self.orbit;
            if r.dragged_by(PointerButton::Secondary) {
                o.look(d.x, d.y);
                o.repivot(center);
                ctx.set_cursor_icon(egui::CursorIcon::Crosshair);
            } else if r.dragged_by(PointerButton::Middle)
                || (shift && r.dragged_by(PointerButton::Primary))
            {
                let half = (self.scene.camera().vertical_fov / 2.0).tan();
                let k = 2.0 * o.dist * half / rect.height();
                o.pan(-d.x * k, d.y * k);
                ctx.set_cursor_icon(egui::CursorIcon::Move);
            } else if r.dragged_by(PointerButton::Primary) {
                o.orbit(d.x, d.y);
                ctx.set_cursor_icon(egui::CursorIcon::Grabbing);
            }
            moved = true;
        }
        if scroll != 0.0 || pinch != 1.0 {
            let o = &mut self.orbit;
            // One wheel burst never changes the distance by more than 2x.
            o.dist = (o.dist * (-scroll * 0.004).clamp(-0.7, 0.7).exp() / pinch).max(1e-3);
            moved = true;
        }
        if moved {
            self.move_camera();
        }
    }

    /// Corner readout and the axis gizmo over the image.
    fn overlay(&self, ui: &egui::Ui, rect: egui::Rect) {
        let p = ui.painter_at(rect);
        let name = VIEWS.iter().find(|v| v.0 == self.view).map_or("", |v| v.1);
        let beauty = self.view == View::Beauty;
        let mode = match (beauty && self.stylized, beauty && self.denoise_ready()) {
            (true, true) => " · Stylized · Denoised",
            (true, false) => " · Stylized",
            (false, true) => " · Denoised",
            (false, false) => "",
        };
        let font = egui::FontId::monospace(11.0);
        p.text(
            rect.min + egui::vec2(8.0, 6.0),
            Align2::LEFT_TOP,
            format!("{name}{mode}"),
            font.clone(),
            Color32::from_white_alpha(170),
        );
        let (text, color) = if self.paused {
            ("PAUSED", WARNING)
        } else if self.done() {
            ("DONE", SUCCESS)
        } else {
            ("", ACCENT)
        };
        p.text(
            rect.right_top() + egui::vec2(-8.0, 6.0),
            Align2::RIGHT_TOP,
            text,
            font.clone(),
            color,
        );

        let (x, y, _) = self.orbit.axes();
        let origin = rect.left_bottom() + egui::vec2(34.0, -34.0);
        p.circle_filled(origin, 28.0, Color32::from_black_alpha(70));
        p.circle_stroke(origin, 28.0, egui::Stroke::new(1.0, BORDER));
        let mut axes = [
            ("X", [1.0, 0.0, 0.0], Color32::from_rgb(0xe8, 0x5a, 0x5a)),
            ("Y", [0.0, 1.0, 0.0], Color32::from_rgb(0x6c, 0xd0, 0x6c)),
            ("Z", [0.0, 0.0, 1.0], Color32::from_rgb(0x5a, 0x8c, 0xf0)),
        ]
        .map(|(n, a, c)| {
            let dot = |b: V3| a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
            (
                n,
                egui::vec2(dot(x), -dot(y)) * 20.0,
                c,
                dot(self.orbit.axes().2),
            )
        });
        // Far axes first so near ones draw over them.
        axes.sort_by(|a, b| a.3.total_cmp(&b.3));
        for (n, v, c, depth) in axes {
            let c = if depth < -0.05 {
                c.gamma_multiply(0.55)
            } else {
                c
            };
            p.line_segment([origin, origin + v], egui::Stroke::new(2.0, c));
            p.text(
                origin + v * 1.3,
                Align2::CENTER_CENTER,
                n,
                egui::FontId::monospace(10.0),
                c,
            );
        }
    }

    fn help(&mut self, ctx: &egui::Context) {
        let rows: [(&str, &str); 14] = [
            ("W A S D / arrows", "fly forward / left / back / right"),
            ("Q / E", "down / up"),
            ("Shift / Ctrl", "faster x4 / slower x0.25"),
            ("Left drag", "orbit"),
            ("Right drag", "look around"),
            ("Middle / Shift+left drag", "pan"),
            ("Wheel / pinch", "dolly"),
            ("Click", "pick the material under the cursor"),
            ("F / R", "frame the scene / reset the camera"),
            ("1 2 3 4 5", "Beauty / Albedo / Normal / Depth / Samples"),
            ("T", "toggle stylization"),
            ("Space / Backspace", "pause / restart accumulation"),
            ("Tab", "hide or show the inspector"),
            ("H / F1", "this help"),
        ];
        egui::Window::new("Shortcuts")
            .open(&mut self.show_help)
            .collapsible(false)
            .resizable(false)
            .anchor(Align2::CENTER_CENTER, [0.0, 0.0])
            .show(ctx, |ui| {
                egui::Grid::new("help")
                    .num_columns(2)
                    .spacing([16.0, 4.0])
                    .show(ui, |ui| {
                        for (k, v) in rows {
                            ui.label(RichText::new(k).monospace().color(ACCENT));
                            ui.label(v);
                            ui.end_row();
                        }
                    });
            });
    }
}

impl eframe::App for App {
    fn logic(&mut self, ctx: &egui::Context, _: &mut eframe::Frame) {
        let now = Instant::now();
        let dt = now.duration_since(self.last_tick).as_secs_f32().max(1e-4);
        self.last_tick = now;
        self.fps += (1.0 / dt - self.fps) * 0.1;
        let moving = self.last_move.elapsed() < MOTION_SETTLE;
        if self.aov_stale {
            if moving {
                ctx.request_repaint_after(MOTION_SETTLE / 3);
            } else {
                self.fetch_aovs();
            }
        }
        if !self.paused && !self.done() {
            let chunk = if moving { 1 } else { self.chunk.round() as u32 };
            let n = chunk.min(self.max_spp - self.acc.samples());
            let started = Instant::now();
            match self.renderer.accumulate(&mut self.acc, n) {
                Ok(()) => {
                    self.active = self.acc.active_pixels();
                    self.samples_dirty = true;
                }
                Err(e) => eprintln!("render: {e:?}"),
            }
            let took = started.elapsed().as_secs_f32().max(1e-4);
            let fit = n as f32 * FRAME_BUDGET / took;
            self.chunk = (self.chunk * 0.7 + fit * 0.3).clamp(1.0, MAX_CHUNK);
            self.spp_rate += (n as f32 / dt - self.spp_rate) * 0.1;
            ctx.request_repaint();
        }
    }

    fn ui(&mut self, ui: &mut egui::Ui, _: &mut eframe::Frame) {
        let ctx = ui.ctx().clone();
        // Show the samples `logic` just gathered before input can restart the accumulation;
        // the other way round, a camera that moves every frame would never reach the screen.
        self.refresh_picture(&ctx);
        self.keys(&ctx);
        self.toolbar(ui);
        self.statusbar(ui);
        if self.show_panels {
            self.inspector(ui);
        }
        self.refresh_picture(&ctx);
        self.viewport(ui, &ctx);
        self.help(&ctx);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn camera() -> Camera {
        Camera {
            transform: [
                [1.0, 0.0, 0.0, 1.0],
                [0.0, 1.0, 0.0, 2.0],
                [0.0, 0.0, 1.0, 5.0],
            ],
            focus_distance: 5.0,
            ..Camera::default()
        }
    }

    #[test]
    fn orbit_rebuilds_the_camera_it_came_from() {
        let cam = camera();
        let back = Orbit::from_camera(&cam).camera(&cam);
        for (a, b) in back
            .transform
            .iter()
            .flatten()
            .zip(cam.transform.iter().flatten())
        {
            assert!(
                (a - b).abs() < 1e-4,
                "{:?} vs {:?}",
                back.transform,
                cam.transform
            );
        }
    }

    #[test]
    fn about_keeps_the_view_and_pivots_at_the_scene_center() {
        let cam = camera();
        let o = Orbit::about(&cam, Some([1.0, 2.0, -3.0]));
        assert!((o.dist - 8.0).abs() < 1e-4, "{}", o.dist);
        let back = o.camera(&cam);
        assert!(
            back.transform
                .iter()
                .flatten()
                .zip(cam.transform.iter().flatten())
                .all(|(a, b)| (a - b).abs() < 1e-4)
        );
        // A center behind the camera keeps the glTF pivot.
        assert_eq!(Orbit::about(&cam, Some([0.0, 0.0, 20.0])).dist, 5.0);
    }

    #[test]
    fn walking_keeps_the_pivot_at_the_scene_depth() {
        let cam = camera();
        let center = Some([1.0, 2.0, -3.0]);
        let mut o = Orbit::about(&cam, center);
        o.walk(2.0, 0.5, 0.0);
        o.repivot(center);
        // 2 units closer, and the pivot sits on the view axis at that depth.
        assert!((o.dist - 6.0).abs() < 1e-4, "{}", o.dist);
        let (_, _, z) = o.axes();
        let eye = o.eye();
        assert!((0..3).all(|a| (o.target[a] - (eye[a] - z[a] * o.dist)).abs() < 1e-4));
    }

    #[test]
    fn look_keeps_the_eye_and_walk_moves_it_along_the_view() {
        let mut o = Orbit::from_camera(&camera());
        let eye = o.eye();
        o.look(120.0, -40.0);
        assert!(o.eye().iter().zip(eye).all(|(a, b)| (a - b).abs() < 1e-4));
        let (_, _, z) = o.axes();
        o.walk(1.0, 0.0, 0.0);
        let moved: Vec<f32> = o.eye().iter().zip(eye).map(|(a, b)| a - b).collect();
        assert!(
            moved.iter().zip(z).all(|(m, z)| (m + z).abs() < 1e-4),
            "{moved:?}"
        );
    }
}
