use verion_denoise::{Aux, Denoiser};
use verion_gpu::{Aovs, LightingAovs};
use verion_scene::Scene;
use verion_stylization::ColorGrade;

/// Render mode. Approximations that bias the image (ReSTIR now, NRC later) live outside Reference.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    /// Physical path tracing only (REQ-CORE-006).
    Reference,
    /// Path tracing with ReSTIR: a faster route to a clean image. Not physical (ADR-0016).
    Interactive,
    /// Stylization Pass on the primary hit (REQ-STY-007). Not physical.
    Stylized,
}

impl Mode {
    /// No non-physical processing in the output.
    pub fn physical(self) -> bool {
        self == Mode::Reference
    }
}

/// Where a denoiser filters a stylized render (ADR-0013). Other modes denoise the beauty.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DenoiseStage {
    /// The lighting AOVs the Stylization Pass reads, so Toon bands are cut after denoising.
    Input,
    /// The stylized beauty, before the outline and the color grade (for comparison, REQ-QA-003).
    Output,
}

pub struct PostInput<'a> {
    pub scene: &'a Scene,
    pub mode: Mode,
    pub width: usize,
    pub height: usize,
    pub normals: &'a [[f32; 3]],
    pub aov: &'a Aovs,
    pub grade: &'a ColorGrade,
    pub denoise: Option<(&'a mut Denoiser, DenoiseStage)>,
}

/// Seconds spent in each post step.
#[derive(Clone, Copy, Debug, Default)]
pub struct PostTimes {
    pub denoise_s: f64,
    pub stylize_s: f64,
}

/// Turns the accumulated sums into the output beauty: denoise, then (Stylized) the Stylization Pass,
/// the outline and the color grade. `beauty` is replaced in Stylized mode. Does nothing to the
/// colors in Reference mode but the optional denoise.
pub fn finish(
    input: PostInput,
    beauty: &mut Vec<[f32; 3]>,
    mut lighting: Option<&mut LightingAovs>,
) -> Result<PostTimes, String> {
    use std::time::Instant;
    let PostInput {
        scene,
        mode,
        width: w,
        height: h,
        normals,
        aov,
        grade,
        mut denoise,
    } = input;
    let aux = Aux {
        albedo: Some(&aov.albedo),
        normal: Some(normals),
    };
    let err = |e: verion_denoise::Error| format!("denoise: {e}");
    let mut times = PostTimes::default();
    let t = Instant::now();
    if let Some((d, stage)) = denoise.as_mut() {
        match (mode, lighting.as_deref_mut()) {
            (Mode::Stylized, Some(l)) if *stage == DenoiseStage::Input => l
                .for_each_radiance(|p| d.denoise(p, aux, w, h))
                .map_err(err)?,
            (Mode::Reference | Mode::Interactive, _) => {
                d.denoise(beauty, aux, w, h).map_err(err)?
            }
            _ => {}
        }
    }
    times.denoise_s = t.elapsed().as_secs_f64();

    if let (Mode::Stylized, Some(l)) = (mode, lighting) {
        let t = Instant::now();
        *beauty = verion_stylization::stylize_image(
            scene.materials(),
            &verion_stylization::Frame {
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
                normal: normals,
                albedo: &aov.albedo,
                material_id: &aov.material_id,
                images: scene.images(),
                camera: *scene.camera(),
                width: w,
            },
        );
        times.stylize_s = t.elapsed().as_secs_f64();
        if let Some((d, DenoiseStage::Output)) = denoise.as_mut() {
            let t = Instant::now();
            d.denoise(beauty, aux, w, h).map_err(err)?;
            times.denoise_s += t.elapsed().as_secs_f64();
        }
        let t = Instant::now();
        verion_stylization::outline(
            scene.materials(),
            &verion_stylization::PostFrame {
                width: w,
                depth: &aov.depth,
                normal: normals,
                object_id: &aov.object_id,
                material_id: &aov.material_id,
            },
            beauty,
        );
        verion_stylization::color_grade(beauty, grade);
        times.stylize_s += t.elapsed().as_secs_f64();
    }
    Ok(times)
}
