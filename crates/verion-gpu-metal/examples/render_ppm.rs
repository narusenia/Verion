//! Dev tool: renders a small test scene (Cornell-style box, metal and glass spheres) to PPM and EXR files.
//! Usage: cargo run --release -p verion-gpu-metal --example render_ppm -- [out_dir] [width] [height] [spp] [walls|hdri|spot|normalmap]
//! `walls` leaves out the spheres (diffuse walls, area light and point light only). `hdri` renders
//! the spheres on a large floor lit by a procedural environment map (written to env.exr).
//! `spot` lights the same open scene with one hard-edged spot light. `normalmap` lights it the same
//! way and puts a procedural normal map on the floor (written to normal.exr).
#[cfg(target_os = "macos")]
mod imp {
    use std::{collections::HashMap, fs, io::Write, path::Path};

    use verion_gpu_metal::{MetalContext, Renderer};
    use verion_render_io::{ExrAovs, ExrFrame, RenderInfo, load_hdri, write_exr};
    use verion_scene::{
        BaseBsdf, Camera, IDENTITY, Image, Instance, Light, Material, Mesh, OutputTransform, Scene,
    };

    fn diffuse(c: [f32; 3]) -> Material {
        let base = BaseBsdf {
            base_color: c,
            ior: 1.0,
            ..BaseBsdf::default()
        };
        Material {
            base,
            ..Material::default()
        }
    }

    /// Only the clearcoat reflects: base color 0 and IOR 1 leave the base lobe nothing to reflect.
    /// Mitsuba counterpart: `roughplastic` with no diffuse part, alpha = roughness squared.
    fn coated_black() -> Material {
        let base = BaseBsdf {
            base_color: [0.0; 3],
            ior: 1.0,
            clearcoat: 1.0,
            clearcoat_roughness: COAT_ROUGHNESS,
            ..BaseBsdf::default()
        };
        Material {
            base,
            ..Material::default()
        }
    }

    fn emissive(e: [f32; 3]) -> Material {
        let base = BaseBsdf {
            base_color: [0.0; 3],
            emission: e,
            ior: 1.0,
            ..BaseBsdf::default()
        };
        Material {
            base,
            ..Material::default()
        }
    }

    fn quad(a: [f32; 3], b: [f32; 3], c: [f32; 3], d: [f32; 3]) -> Mesh {
        Mesh::new(vec![a, b, c, d], None, None, vec![0, 1, 2, 0, 2, 3]).unwrap()
    }

    /// Icosphere with outward counter-clockwise faces.
    fn sphere(radius: f32) -> Mesh {
        let t = (1.0 + 5.0f32.sqrt()) / 2.0;
        let mut v: Vec<[f32; 3]> = vec![
            [-1.0, t, 0.0],
            [1.0, t, 0.0],
            [-1.0, -t, 0.0],
            [1.0, -t, 0.0],
            [0.0, -1.0, t],
            [0.0, 1.0, t],
            [0.0, -1.0, -t],
            [0.0, 1.0, -t],
            [t, 0.0, -1.0],
            [t, 0.0, 1.0],
            [-t, 0.0, -1.0],
            [-t, 0.0, 1.0],
        ];
        #[rustfmt::skip]
        let mut faces: Vec<[u32; 3]> = vec![
            [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
            [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
            [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
            [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
        ];
        for _ in 0..3 {
            let mut mids: HashMap<(u32, u32), u32> = HashMap::new();
            let mut mid = |a: u32, b: u32, v: &mut Vec<[f32; 3]>| -> u32 {
                *mids.entry((a.min(b), a.max(b))).or_insert_with(|| {
                    let (p, q) = (v[a as usize], v[b as usize]);
                    v.push([
                        (p[0] + q[0]) / 2.0,
                        (p[1] + q[1]) / 2.0,
                        (p[2] + q[2]) / 2.0,
                    ]);
                    v.len() as u32 - 1
                })
            };
            let mut next = Vec::new();
            for [a, b, c] in faces {
                let (ab, bc, ca) = (mid(a, b, &mut v), mid(b, c, &mut v), mid(c, a, &mut v));
                next.extend([[a, ab, ca], [b, bc, ab], [c, ca, bc], [ab, bc, ca]]);
            }
            faces = next;
        }
        for p in &mut v {
            let len = (p[0] * p[0] + p[1] * p[1] + p[2] * p[2]).sqrt();
            *p = [
                p[0] / len * radius,
                p[1] / len * radius,
                p[2] / len * radius,
            ];
        }
        for f in &mut faces {
            let [a, b, c] = f.map(|i| v[i as usize]);
            let n = [
                (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]),
                (b[2] - a[2]) * (c[0] - a[0]) - (b[0] - a[0]) * (c[2] - a[2]),
                (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]),
            ];
            if n[0] * (a[0] + b[0] + c[0])
                + n[1] * (a[1] + b[1] + c[1])
                + n[2] * (a[2] + b[2] + c[2])
                < 0.0
            {
                f.swap(1, 2);
            }
        }
        // Centred on the origin, so the outward normal is the normalised position.
        let normals = v.iter().map(|p| p.map(|c| c / radius)).collect();
        Mesh::new(v, Some(normals), None, faces.concat()).unwrap()
    }

    fn translate(x: f32, y: f32, z: f32) -> [[f32; 4]; 3] {
        [[1.0, 0.0, 0.0, x], [0.0, 1.0, 0.0, y], [0.0, 0.0, 1.0, z]]
    }

    fn scene(mode: &str) -> Scene {
        let walls_only = mode == "walls";
        let nmap = mode == "normalmap";
        let spot = mode == "spot" || nmap;
        let coat = mode == "coat";
        let open = mode == "hdri" || coat || spot;
        let mut s = Scene::new();
        let add = |s: &mut Scene, mesh: Mesh, material: Material, transform| {
            let (mesh, material) = (s.add_mesh(mesh), s.add_material(material));
            s.add_instance(Instance {
                mesh,
                material,
                transform,
            })
            .unwrap();
        };
        let (lo, hi) = (-2.0, 2.0);
        let grey = [0.75; 3];
        let f = if nmap {
            3.0
        } else if open {
            20.0
        } else {
            2.0
        };
        let (floor, floor_material) = if coat {
            // Wound so the normal faces up: the coat is skipped on a back face (seen from "inside").
            (
                quad([-f, lo, -f], [-f, lo, f], [f, lo, f], [f, lo, -f]),
                coated_black(),
            )
        } else if nmap {
            let image = Image::new(NMAP_SIZE, NMAP_SIZE, normal_map_pixels()).unwrap();
            let base = BaseBsdf {
                base_color: grey,
                ior: 1.0,
                normal_texture: Some(s.add_image(image)),
                ..BaseBsdf::default()
            };
            // u runs along +x and v along +z, so the image reads as seen from the camera.
            let mesh = Mesh::new(
                vec![[-f, lo, -f], [f, lo, -f], [f, lo, f], [-f, lo, f]],
                Some(vec![[0.0, 1.0, 0.0]; 4]),
                Some(vec![[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]]),
                vec![0, 2, 1, 0, 3, 2],
            )
            .unwrap();
            (
                mesh,
                Material {
                    base,
                    ..Material::default()
                },
            )
        } else {
            (
                quad([-f, lo, -f], [f, lo, -f], [f, lo, f], [-f, lo, f]),
                diffuse(grey),
            )
        };
        add(&mut s, floor, floor_material, IDENTITY); // floor
        if !open {
            add(
                &mut s,
                quad([lo, hi, lo], [hi, hi, lo], [hi, hi, hi], [lo, hi, hi]),
                diffuse(grey),
                IDENTITY,
            ); // ceiling
            add(
                &mut s,
                quad([lo, lo, lo], [hi, lo, lo], [hi, hi, lo], [lo, hi, lo]),
                diffuse(grey),
                IDENTITY,
            ); // back
            add(
                &mut s,
                quad([lo, lo, lo], [lo, lo, hi], [lo, hi, hi], [lo, hi, lo]),
                diffuse([0.75, 0.15, 0.15]),
                IDENTITY,
            ); // left
            add(
                &mut s,
                quad([hi, lo, lo], [hi, lo, hi], [hi, hi, hi], [hi, hi, lo]),
                diffuse([0.15, 0.6, 0.15]),
                IDENTITY,
            ); // right
            add(
                &mut s,
                quad(
                    [-0.6, 1.99, -0.6],
                    [0.6, 1.99, -0.6],
                    [0.6, 1.99, 0.6],
                    [-0.6, 1.99, 0.6],
                ),
                emissive([14.0; 3]),
                IDENTITY,
            );
        }
        if coat {
            add(
                &mut s,
                sphere(0.7),
                coated_black(),
                translate(0.0, -1.3, 0.0),
            );
        } else if !walls_only {
            let ball = sphere(0.7);
            let gold = BaseBsdf {
                base_color: [1.0, 0.78, 0.34],
                metallic: 1.0,
                roughness: 0.2,
                ..BaseBsdf::default()
            };
            let glass = BaseBsdf {
                base_color: [1.0; 3],
                roughness: 0.0,
                transmission: 1.0,
                ..BaseBsdf::default()
            };
            add(
                &mut s,
                ball.clone(),
                Material {
                    base: gold,
                    ..Material::default()
                },
                translate(-0.9, -1.3, -0.6),
            );
            add(
                &mut s,
                ball,
                Material {
                    base: glass,
                    ..Material::default()
                },
                translate(0.9, -1.3, 0.3),
            );
        }
        let mut cam = Camera {
            vertical_fov: 0.9,
            ..Camera::default()
        };
        cam.transform[2][3] = 6.0;
        s.set_camera(cam);
        if !open {
            s.add_light(Light::Point {
                position: [0.0, 1.0, 1.5],
                color: [1.0, 0.95, 0.9],
                intensity: 1.5,
            });
        }
        if spot {
            s.add_light(Light::Spot {
                position: [2.0, 4.0, 3.0],
                direction: [-2.0, -5.3, -3.0],
                color: [1.0, 0.95, 0.9],
                intensity: 40.0,
                inner_cone: 0.49,
                outer_cone: 0.5,
            });
        }
        s
    }

    const NMAP_SIZE: u32 = 128;
    /// Clearcoat roughness of the `coat` mode; scripts/mitsuba_cornell.py uses the same value.
    const COAT_ROUGHNESS: f32 = 0.4;

    /// Tangent-space normals (glTF: +Y up the image) of four Gaussian bumps, deliberately asymmetric
    /// so a mirrored or rotated lookup shows up.
    fn normal_map_pixels() -> Vec<[f32; 3]> {
        let bumps = [
            (0.3f32, 0.3f32, 1.0f32, 0.10f32),
            (0.7, 0.35, -1.0, 0.08),
            (0.5, 0.7, 1.0, 0.12),
            (0.2, 0.75, -0.8, 0.07),
        ];
        let mut px = Vec::with_capacity((NMAP_SIZE * NMAP_SIZE) as usize);
        for j in 0..NMAP_SIZE {
            for i in 0..NMAP_SIZE {
                let (x, y) = (
                    (i as f32 + 0.5) / NMAP_SIZE as f32,
                    (j as f32 + 0.5) / NMAP_SIZE as f32,
                );
                // Height gradient in image coordinates (y grows downward).
                let (mut gx, mut gy) = (0.0, 0.0);
                for (cx, cy, a, sigma) in bumps {
                    let g = a
                        * (-((x - cx).powi(2) + (y - cy).powi(2)) / (2.0 * sigma * sigma)).exp()
                        / (sigma * sigma);
                    gx += -(x - cx) * g;
                    gy += -(y - cy) * g;
                }
                // Slope toward +u is gx; toward the image's up direction (+Y) it is -gy.
                // Peak tilt is about 35 degrees, past the camera's grazing view of the floor.
                let n = [-0.08 * gx, 0.08 * gy, 1.0];
                let len = (n[0] * n[0] + n[1] * n[1] + n[2] * n[2]).sqrt();
                px.push(n.map(|c| c / len * 0.5 + 0.5));
            }
        }
        px
    }

    /// Smooth sky gradient plus a wide sun lobe, so nearest and bilinear lookups agree closely.
    fn env_pixels(w: u32, h: u32) -> Vec<[f32; 3]> {
        let sun = [0.5f32, 0.6, 0.3];
        let sun_len = (sun[0] * sun[0] + sun[1] * sun[1] + sun[2] * sun[2]).sqrt();
        let mut px = Vec::with_capacity((w * h) as usize);
        for j in 0..h {
            let theta = (j as f32 + 0.5) / h as f32 * std::f32::consts::PI;
            for i in 0..w {
                let phi = ((i as f32 + 0.5) / w as f32 - 0.5) * 2.0 * std::f32::consts::PI;
                // Inverse of the renderer's u = atan2(x, -z) / 2pi + 0.5, v = acos(y) / pi.
                let d = [
                    theta.sin() * phi.sin(),
                    theta.cos(),
                    -theta.sin() * phi.cos(),
                ];
                let t = 0.5 + 0.5 * d[1];
                let cos_sun = (d[0] * sun[0] + d[1] * sun[1] + d[2] * sun[2]) / sun_len;
                let lobe = (-(1.0 - cos_sun) / 0.03).exp();
                px.push([
                    0.25 + 0.35 * t + 8.0 * lobe,
                    0.3 + 0.4 * t + 7.0 * lobe,
                    0.5 + 0.5 * t + 5.0 * lobe,
                ]);
            }
        }
        px
    }

    fn write_ppm(path: &Path, w: u32, h: u32, pixels: &[[f32; 3]], encode: impl Fn(f32) -> u8) {
        let mut out = fs::File::create(path).expect("create output");
        write!(out, "P6\n{w} {h}\n255\n").unwrap();
        let bytes: Vec<u8> = pixels.iter().flatten().map(|&v| encode(v)).collect();
        out.write_all(&bytes).unwrap();
    }

    pub fn run() {
        let mut args = std::env::args().skip(1);
        let dir = args.next().unwrap_or_else(|| ".".into());
        let mut num = |default: u32| args.next().map_or(default, |a| a.parse().expect("number"));
        let (w, h, spp) = (num(512), num(384), num(256));

        let mode = args.next().unwrap_or_default();
        let mut scene = scene(&mode);
        let dir = Path::new(&dir);
        fs::create_dir_all(dir).unwrap();
        if mode == "hdri" || mode == "coat" {
            let (ew, eh) = (256, 128);
            let env = ExrFrame {
                width: ew,
                height: eh,
                working_space: scene.working_space(),
                beauty: &env_pixels(ew, eh),
                normal: None,
                aovs: Default::default(),
                info: RenderInfo {
                    physical: true,
                    samples: 0,
                    stylization_revision: 0,
                    grade: None,
                    denoiser: None,
                    adaptive_threshold: None,
                },
            };
            let path = dir.join("env.exr");
            let linear = OutputTransform::linear(scene.working_space());
            write_exr(&path, &env, &linear).expect("write env");
            let image = load_hdri(&path, scene.working_space()).expect("load env");
            let image = scene.add_image(image);
            scene.add_light(Light::EnvironmentMap { image, scale: 1.0 });
        }
        if mode == "normalmap" {
            let map = ExrFrame {
                width: NMAP_SIZE,
                height: NMAP_SIZE,
                working_space: scene.working_space(),
                beauty: &normal_map_pixels(),
                normal: None,
                aovs: Default::default(),
                info: RenderInfo {
                    physical: true,
                    samples: 0,
                    stylization_revision: 0,
                    grade: None,
                    denoiser: None,
                    adaptive_threshold: None,
                },
            };
            let linear = OutputTransform::linear(scene.working_space());
            write_exr(&dir.join("normal.exr"), &map, &linear).expect("write normal map");
        }
        let ctx = MetalContext::new().expect("Metal ray tracing is required");
        let mut renderer = Renderer::new(&ctx, &scene).expect("renderer");
        // Mitsuba 3's rough conductor is single-scattering, so the cross-check turns the
        // multiple-scattering compensation off.
        renderer.set_multiscatter(false);

        let beauty = renderer.render(w, h, spp).expect("render");
        let display = OutputTransform::display();
        let space = scene.working_space();
        let shown: Vec<[f32; 3]> = beauty.iter().map(|&p| display.apply(space, p)).collect();
        write_ppm(&dir.join("beauty.ppm"), w, h, &shown, |v| {
            (v.clamp(0.0, 1.0) * 255.0 + 0.5) as u8
        });
        let normals = renderer.render_normals(w, h).expect("normals");
        write_ppm(&dir.join("normals.ppm"), w, h, &normals, |v| {
            ((v * 0.5 + 0.5).clamp(0.0, 1.0) * 255.0 + 0.5) as u8
        });
        let aov = renderer.render_aovs(w, h).expect("aovs");
        let mut ids = aov.object_id.clone();
        ids.sort_unstable();
        ids.dedup();
        let far = aov.depth.iter().fold(0.0f32, |m, &d| m.max(d));
        println!("aovs: object ids {ids:?}, farthest depth {far:.2}");
        let frame = ExrFrame {
            width: w,
            height: h,
            working_space: space,
            beauty: &beauty,
            normal: Some(&normals),
            aovs: ExrAovs {
                albedo: Some(&aov.albedo),
                depth: Some(&aov.depth),
                object_id: Some(&aov.object_id),
                material_id: Some(&aov.material_id),
                lighting: None,
                ..Default::default()
            },
            info: RenderInfo {
                physical: true,
                samples: spp,
                stylization_revision: 0,
                grade: None,
                denoiser: None,
                adaptive_threshold: None,
            },
        };
        write_exr(
            &dir.join("render.exr"),
            &frame,
            &OutputTransform::linear(space),
        )
        .expect("write exr");
        println!(
            "wrote {}/beauty.ppm, normals.ppm and render.exr ({w}x{h}, {spp} spp)",
            dir.display()
        );
    }
}

fn main() {
    #[cfg(target_os = "macos")]
    imp::run();
    #[cfg(not(target_os = "macos"))]
    eprintln!("render_ppm requires macOS (Metal)");
}
