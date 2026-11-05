use std::path::PathBuf;

use eframe::egui;
use verion_gpu_metal::{Accumulation, MetalContext, Renderer};
use verion_scene::{Camera, Light, OutputTransform, Scene};
use verion_stylization::{ColorGrade, Frame, PostFrame};

#[derive(clap::Parser, Debug)]
#[command(version, about = "Verion progressive viewer")]
pub struct Args {
    /// Input `.gltf` / `.glb`
    scene: PathBuf,
    /// Equirectangular environment map (`.hdr` / `.exr`) used as the sky light
    #[arg(long)]
    hdri: Option<PathBuf>,
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
        })
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
            if let Some(t) = &self.texture {
                ui.add(egui::Image::new(t).shrink_to_fit());
            }
        });
    }
}
