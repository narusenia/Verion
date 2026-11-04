# Verion

> 日本語版: [`README_ja.md`](README_ja.md)

Verion is a GPU renderer written in Rust, meant to be used from DCC applications such as Blender, Cinema 4D and Maya. It computes light with physically based path tracing, and lets artists tune the result anywhere from photorealism to game-style and cel looks.

The project is at the planning stage and has no code yet.

## The looks we aim for

Instead of building photorealistic and anime-style images with separate mechanisms, Verion lets you move between them continuously inside one renderer. The physical information (light direction, occlusion, indirect light) stays, and only the parts that define the look are stylized.

We target four kinds of looks.

- **Stylized PBR**: physically based materials with adjusted shadow colors and saturation
- **Cinematic Toon**: cinematic lighting expressed with clearly banded shadows
- **Painterly Realism**: realistic forms and light with painterly color placement
- **Anime Cinematic**: faces, hair and outlines closer to hand-drawn animation

To get there, we make the following controllable.

| Look | What you can do | Planned |
|---|---|---|
| Shadow bands | Set the number of bands, edge softness and a color palette | v0.1 |
| Shadow color | Color-correct direct and indirect shadows separately | v0.1 |
| Highlights | Shape them as bands, ellipses or hand-drawn forms | v0.1 |
| Rim light | Add an edge light based on normal, view and light direction | v0.1 |
| Realism blend | Set how realistic diffuse, specular, indirect light and shadow are, per material | v0.1 |
| Outlines | Draw lines on silhouettes, creases and material boundaries | Later |
| Face shadow | Use a face-specific map so shadows hold up as the angle changes | Later |
| Hair highlights | Make banded highlights that follow the flow of the hair | Later |
| Style in reflections | Apply style to images seen in mirrors and refractions | Research |

## Technology

| Area | Technology | Why |
|---|---|---|
| Language | Rust | Types protect GPU buffer lifetimes and synchronization |
| GPU | Metal Ray Tracing (M3 and later), then Vulkan Ray Tracing (RTX) | Our development machines are Macs, so Metal comes first |
| Shaders | Slang (compiled to MSL and SPIR-V) | BSDF and style code is written only once |
| Rendering | Path tracing (NEE and MIS) | The physical baseline |
| Input | glTF 2.0 with a JSON extension for style | Existing test scenes work as they are |
| Color | OCIO / ACES | It affects every output, so it goes in from the start |
| Output | OpenEXR (beauty and AOVs in one file) | Components stay separate so style can be applied afterward |
| Denoising | OIDN and MetalFX (compared, then chosen) | AOVs keep Toon edges from being smoothed away |
| Speed (later) | ReSTIR, Neural Radiance Cache, incremental updates | Shorten the time to reach the same quality |
| Validation | Image comparison with Mitsuba 3, white furnace tests | Check physical correctness mechanically |
| DCC (later) | Blender, Cinema 4D, Maya | Blender first |
| Tooling | mise, cargo-deny, lefthook | One entry point, `mise run check` |

Style is applied at the first surface the camera sees. There we compute the contribution of each light separately and write it out as per-component AOVs, and a final compositing pass applies the style to those AOVs. Reference mode turns off style and every AI approximation and renders with path tracing alone.

## Documentation

Start with [`docs/requirements/overview.md`](docs/requirements/overview.md). The plan is in [`docs/implementation/roadmap.md`](docs/implementation/roadmap.md), the reasons behind each decision are in [`docs/adr/`](docs/adr), and the first concept, including research hypotheses, is in [`docs/drafts/draft_arch.md`](docs/drafts/draft_arch.md). Where the draft and the requirements disagree, the requirements win.

## Development

Tools and tasks are managed with [mise](https://mise.jdx.dev). Run `mise install` to set up the tools, then `mise run check` to run formatting, linting, the license check and the tests together.

## License

Not decided yet. We also plan to distribute outside the project, and we are considering something close to an open-core model. We expect to decide around M4, once the redistribution terms of NVIDIA's SDKs are clear. Until then we use only dependencies whose licenses allow commercial redistribution. See [ADR-0004](docs/adr/0004-positioning-and-license-deferral.md) for details.
