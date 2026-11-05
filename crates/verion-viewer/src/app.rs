use std::{
    path::PathBuf,
    time::{Duration, Instant},
};

use eframe::egui;
use verion_gpu_metal::{Accumulation, MetalContext, Renderer};
use verion_scene::{
    Camera, HybridSurface, Light, Material, OutlineStyle, OutputTransform, Scene, StylizationLayer,
    ToonRamp,
};
use verion_stylization::{ColorGrade, Frame, PostFrame};

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

/// Samples per GPU dispatch; one dispatch per UI frame keeps the window responsive.
const CHUNK_SPP: u32 = 4;

/// Longest side of the render. The accumulation is read back to the CPU every frame, so a bigger
/// window does not mean a bigger render.
const MAX_SIDE: f32 = 1024.0;
const MIN_SIDE: f32 = 64.0;
/// A window resize re-renders only after the size has been stable this long.
const RESIZE_SETTLE: Duration = Duration::from_millis(300);

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
    /// shortcut: a glTF camera with a default focus distance orbits a point 1 unit ahead; zoom
    /// corrects it. Upgrade by orbiting the scene's bounding-sphere center.
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

    fn camera(&self, base: &Camera) -> Camera {
        let (sy, cy) = self.yaw.sin_cos();
        let (sp, cp) = self.pitch.sin_cos();
        let z = [cp * sy, sp, cp * cy];
        let x = normalize([z[2], 0.0, -z[0]]); // up (0,1,0) x z
        let y = cross(z, x);
        let mut cam = *base;
        for a in 0..3 {
            cam.transform[a] = [x[a], y[a], z[a], self.target[a] + z[a] * self.dist];
        }
        cam.focus_distance = self.dist;
        cam
    }
}

#[derive(Clone, Copy, PartialEq)]
enum View {
    Beauty,
    Albedo,
    Normal,
    Depth,
}

pub struct App {
    scene: Scene,
    renderer: Renderer,
    acc: Accumulation,
    normals: Vec<[f32; 3]>,
    aov: verion_gpu_metal::Aovs,
    width: u32,
    height: u32,
    max_spp: u32,
    view: View,
    stylized: bool,
    multiscatter: bool,
    grade: ColorGrade,
    /// The texture is stale: samples, view or a parameter changed.
    dirty: bool,
    texture: Option<egui::TextureHandle>,
    orbit: Orbit,
    material: usize,
    /// A window size waiting to settle before the render follows it.
    pending_size: Option<((u32, u32), Instant)>,
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
        if let Some(path) = &args.hdri {
            let image = verion_render_io::load_hdri(path, scene.working_space())
                .map_err(|e| format!("hdri {}: {e}", path.display()))?;
            let image = scene.add_image(image);
            scene.add_light(Light::EnvironmentMap { image, scale: 1.0 });
        }
        let ctx =
            MetalContext::new().map_err(|e| format!("Metal ray tracing is required: {e:?}"))?;
        let renderer = Renderer::new(&ctx, &scene).map_err(|e| format!("renderer: {e:?}"))?;
        let (w, h) = (args.width, args.height);
        let acc = renderer
            .new_accumulation_with_lighting(w, h)
            .map_err(|e| format!("render: {e:?}"))?;
        let normals = renderer
            .render_normals(w, h)
            .map_err(|e| format!("normals: {e:?}"))?;
        let aov = renderer
            .render_aovs(w, h)
            .map_err(|e| format!("aovs: {e:?}"))?;
        let orbit = Orbit::from_camera(scene.camera());
        Ok(Self {
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
            grade: ColorGrade::default(),
            dirty: true,
            texture: None,
            orbit,
            material: 0,
            pending_size: None,
        })
    }

    /// The first-hit AOVs belong to the camera and the size, so they are redone when either changes.
    fn refresh_aovs(&mut self) {
        let (w, h) = (self.width, self.height);
        match (
            self.renderer.render_normals(w, h),
            self.renderer.render_aovs(w, h),
        ) {
            (Ok(n), Ok(a)) => (self.normals, self.aov) = (n, a),
            (n, a) => eprintln!("aovs: {:?}", n.err().or(a.err())),
        }
        self.restart();
    }

    fn move_camera(&mut self) {
        let cam = self.orbit.camera(self.scene.camera());
        self.scene.set_camera(cam);
        self.renderer.set_camera(&cam);
        self.refresh_aovs();
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

    /// Sliders for the stylization layers of one material; edits `m` in place.
    fn material_ui(ui: &mut egui::Ui, m: &mut Material) {
        if m.stylization.is_empty() {
            if ui.button("Add toon preset").clicked() {
                m.stylization = vec![
                    StylizationLayer::HybridSurface(HybridSurface::TOON),
                    StylizationLayer::ToonRamp(ToonRamp {
                        thresholds: vec![0.3, 0.7],
                        feather: 0.05,
                        palette: vec![[0.5; 3], [0.8; 3], [1.0; 3]],
                        light_wrap: 0.0,
                    }),
                    StylizationLayer::OutlineStyle(OutlineStyle::default()),
                ];
            }
            return;
        }
        let unit = |ui: &mut egui::Ui, v: &mut f32, name: &str| {
            ui.add(egui::Slider::new(v, 0.0..=1.0).text(name));
        };
        for layer in &mut m.stylization {
            match layer {
                StylizationLayer::HybridSurface(h) => {
                    for (v, name) in [
                        (&mut h.diffuse, "diffuse"),
                        (&mut h.specular, "specular"),
                        (&mut h.gi, "gi"),
                        (&mut h.shadow, "shadow"),
                        (&mut h.outline, "outline"),
                        (&mut h.reflection, "reflection"),
                    ] {
                        unit(ui, v, name);
                    }
                }
                StylizationLayer::ToonRamp(t) => {
                    unit(ui, &mut t.feather, "toon feather");
                    unit(ui, &mut t.light_wrap, "toon wrap");
                }
                StylizationLayer::RimLight(r) => {
                    unit(ui, &mut r.width, "rim width");
                    ui.add(egui::Slider::new(&mut r.strength, 0.0..=4.0).text("rim strength"));
                }
                StylizationLayer::StylizedSpecular(s) => {
                    unit(ui, &mut s.size, "spec size");
                    ui.add(egui::Slider::new(&mut s.strength, 0.0..=4.0).text("spec strength"));
                }
                StylizationLayer::OutlineStyle(o) => {
                    ui.add(egui::Slider::new(&mut o.width, 1.0..=8.0).text("outline px"));
                }
                StylizationLayer::MatCap(mc) => {
                    unit(ui, &mut mc.strength, "matcap strength");
                    unit(ui, &mut mc.albedo, "matcap albedo");
                }
                StylizationLayer::ShadowPalette(_) => {}
            }
        }
        if ui.button("Clear stylization").clicked() {
            m.stylization.clear();
        }
    }

    fn restart(&mut self) {
        match self
            .renderer
            .new_accumulation_with_lighting(self.width, self.height)
        {
            Ok(acc) => self.acc = acc,
            Err(e) => eprintln!("render: {e:?}"),
        }
        self.dirty = true;
    }

    /// The displayed image in the working space (linear), before the display transform.
    fn linear_image(&self) -> Vec<[f32; 3]> {
        match self.view {
            View::Albedo => self.aov.albedo.clone(),
            View::Normal => self
                .normals
                .iter()
                .map(|n| n.map(|v| v * 0.5 + 0.5))
                .collect(),
            View::Depth => {
                let far = self.aov.depth.iter().copied().fold(0.0, f32::max).max(1e-6);
                self.aov.depth.iter().map(|d| [d / far; 3]).collect()
            }
            View::Beauty => {
                let mut beauty = self.acc.mean();
                if let (true, Some(l)) = (self.stylized, self.acc.lighting()) {
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

    fn upload(&mut self, ctx: &egui::Context) {
        let display = OutputTransform::display();
        let space = self.scene.working_space();
        let rgb: Vec<u8> = self
            .linear_image()
            .iter()
            .flat_map(|p| display.apply(space, *p).map(|v| (v * 255.0 + 0.5) as u8))
            .collect();
        let image = egui::ColorImage::from_rgb([self.width as usize, self.height as usize], &rgb);
        match &mut self.texture {
            Some(t) => t.set(image, egui::TextureOptions::NEAREST),
            None => {
                self.texture = Some(ctx.load_texture("view", image, egui::TextureOptions::NEAREST));
            }
        }
        self.dirty = false;
    }
}

impl eframe::App for App {
    fn logic(&mut self, ctx: &egui::Context, _: &mut eframe::Frame) {
        if self.acc.samples() < self.max_spp {
            let n = CHUNK_SPP.min(self.max_spp - self.acc.samples());
            match self.renderer.accumulate(&mut self.acc, n) {
                Ok(()) => self.dirty = true,
                Err(e) => eprintln!("render: {e:?}"),
            }
            ctx.request_repaint();
        }
    }

    fn ui(&mut self, ui: &mut egui::Ui, _: &mut eframe::Frame) {
        let ctx = ui.ctx().clone();
        let mut restart = false;
        egui::Panel::left("controls").show(ui, |ui| {
            let spp = self.acc.samples();
            ui.add(
                egui::ProgressBar::new(spp as f32 / self.max_spp as f32)
                    .text(format!("{spp} / {} spp", self.max_spp)),
            );
            ui.separator();
            let before = (self.view, self.stylized);
            ui.label("AOV");
            for (v, name) in [
                (View::Beauty, "Beauty"),
                (View::Albedo, "Albedo"),
                (View::Normal, "Normal"),
                (View::Depth, "Depth"),
            ] {
                ui.radio_value(&mut self.view, v, name);
            }
            ui.separator();
            ui.checkbox(&mut self.stylized, "Stylized (non-physical)");
            self.dirty |= before != (self.view, self.stylized);
            // The grade applies only to the stylized beauty (REQ-CORE-006: Reference stays physical).
            ui.add_enabled_ui(self.stylized, |ui| {
                let g = &mut self.grade;
                let before = *g;
                ui.add(egui::Slider::new(&mut g.exposure, -4.0..=4.0).text("exposure"));
                ui.add(egui::Slider::new(&mut g.saturation, 0.0..=2.0).text("saturation"));
                for (w, name) in g.white_balance.iter_mut().zip(["R", "G", "B"]) {
                    ui.add(egui::Slider::new(w, 0.0..=2.0).text(format!("wb {name}")));
                }
                self.dirty |= before != *g;
            });
            ui.separator();
            ui.label("Material stylization");
            let count = self.scene.materials().len();
            if count > 0 {
                self.material = self.material.min(count - 1);
                egui::ComboBox::from_id_salt("material")
                    .selected_text(format!("material {}", self.material))
                    .show_ui(ui, |ui| {
                        for i in 0..count {
                            ui.selectable_value(&mut self.material, i, format!("material {i}"));
                        }
                    });
                let mut edited = self.scene.materials()[self.material].clone();
                Self::material_ui(ui, &mut edited);
                if edited != self.scene.materials()[self.material]
                    && let Some(id) = self.scene.material_id(self.material)
                {
                    self.scene.set_material(id, edited);
                    // Stylization is a post pass: no new samples are needed.
                    self.dirty = true;
                }
            }
            ui.separator();
            if ui
                .checkbox(&mut self.multiscatter, "Multiple-scattering compensation")
                .changed()
            {
                self.renderer.set_multiscatter(self.multiscatter);
                restart = true;
            }
            if ui.button("Restart accumulation").clicked() {
                restart = true;
            }
        });
        if restart {
            self.restart();
        }
        if self.dirty {
            self.upload(&ctx);
        }
        egui::CentralPanel::default().show(ui, |ui| {
            self.follow_size(&ctx, ui.available_size());
            let Some(t) = &self.texture else { return };
            let r = ui.add(
                egui::Image::new(t)
                    .shrink_to_fit()
                    .sense(egui::Sense::click_and_drag()),
            );
            let scroll = if r.hovered() {
                ui.input(|i| i.smooth_scroll_delta.y)
            } else {
                0.0
            };
            let d = r.drag_delta();
            if d != egui::Vec2::ZERO || scroll != 0.0 {
                let o = &mut self.orbit;
                o.yaw -= d.x * 0.005;
                o.pitch = (o.pitch + d.y * 0.005).clamp(-1.5, 1.5);
                o.dist = (o.dist * (-scroll * 0.005).exp()).max(1e-3);
                self.move_camera();
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn orbit_rebuilds_the_camera_it_came_from() {
        let cam = Camera {
            transform: [
                [1.0, 0.0, 0.0, 1.0],
                [0.0, 1.0, 0.0, 2.0],
                [0.0, 0.0, 1.0, 5.0],
            ],
            focus_distance: 5.0,
            ..Camera::default()
        };
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
}
