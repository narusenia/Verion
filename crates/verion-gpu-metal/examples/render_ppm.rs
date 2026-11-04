//! Dev tool: renders a small test scene (Cornell-style box, metal and glass spheres) to PPM and EXR files.
//! Usage: cargo run --release -p verion-gpu-metal --example render_ppm -- [out_dir] [width] [height] [spp]
#[cfg(target_os = "macos")]
mod imp {
    use std::{collections::HashMap, fs, io::Write, path::Path};

    use verion_gpu_metal::{MetalContext, Renderer};
    use verion_render_io::{ExrFrame, RenderInfo, write_exr};
    use verion_scene::{
        BaseBsdf, Camera, IDENTITY, Instance, Light, Material, Mesh, OutputTransform, Scene,
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
        Mesh::new(v, None, None, faces.concat()).unwrap()
    }

    fn translate(x: f32, y: f32, z: f32) -> [[f32; 4]; 3] {
        [[1.0, 0.0, 0.0, x], [0.0, 1.0, 0.0, y], [0.0, 0.0, 1.0, z]]
    }

    fn scene() -> Scene {
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
        add(
            &mut s,
            quad([lo, lo, lo], [hi, lo, lo], [hi, lo, hi], [lo, lo, hi]),
            diffuse(grey),
            IDENTITY,
        ); // floor
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
        let mut cam = Camera {
            vertical_fov: 0.9,
            ..Camera::default()
        };
        cam.transform[2][3] = 6.0;
        s.set_camera(cam);
        s.add_light(Light::Point {
            position: [0.0, 1.0, 1.5],
            color: [1.0, 0.95, 0.9],
            intensity: 1.5,
        });
        s
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

        let scene = scene();
        let ctx = MetalContext::new().expect("Metal ray tracing is required");
        let renderer = Renderer::new(&ctx, &scene).expect("renderer");
        let dir = Path::new(&dir);
        fs::create_dir_all(dir).unwrap();

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
        let frame = ExrFrame {
            width: w,
            height: h,
            working_space: space,
            beauty: &beauty,
            normal: Some(&normals),
            info: RenderInfo {
                physical: true,
                samples: spp,
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
