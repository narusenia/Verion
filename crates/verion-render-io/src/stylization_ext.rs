//! `VERION_materials_stylization` -> `StylizationLayer`s (REQ-IO-002; see
//! docs/specifications/gltf-stylization-extension.md).

use gltf::json::Value;
use verion_scene::{
    ColorAdjust, ColorSpace, HighlightShape, HybridSurface, ImageId, MatCap, OutlineStyle,
    RimLight, ShadowPalette, StylizationLayer, StylizedSpecular, ToonRamp,
};

pub const NAME: &str = "VERION_materials_stylization";

/// Turns a glTF texture index into an IR image. `Err` is a bad index (an import error); `Ok(None)`
/// is an image that cannot be used (the layer is skipped with a warning).
pub type ResolveTexture<'a> = &'a mut dyn FnMut(usize) -> Result<Option<ImageId>, String>;

/// Layers plus warnings for unknown properties. `Err` carries a message for the import error.
pub fn parse(
    value: &Value,
    space: ColorSpace,
    resolve: ResolveTexture,
) -> Result<(Vec<StylizationLayer>, Vec<String>), String> {
    let root = value.as_object().ok_or("must be an object")?;
    let mut warnings = Vec::new();
    let mut layers = Vec::new();
    let known = [
        "hybridSurface",
        "toonRamp",
        "shadowPalette",
        "rimLight",
        "stylizedSpecular",
        "outlineStyle",
        "matcap",
    ];
    for key in root.keys().filter(|k| !known.contains(&k.as_str())) {
        warnings.push(format!("unknown property {key}"));
    }
    if let Some(h) = root.get("hybridSurface") {
        let o = h.as_object().ok_or("hybridSurface must be an object")?;
        let known = [
            "diffuse",
            "specular",
            "gi",
            "shadow",
            "outline",
            "reflection",
        ];
        warn_unknown("hybridSurface", o.keys(), &known, &mut warnings);
        let get = |k: &str| number(o.get(k), 0.0, &format!("hybridSurface.{k}"));
        layers.push(StylizationLayer::HybridSurface(HybridSurface {
            diffuse: get("diffuse")?,
            specular: get("specular")?,
            gi: get("gi")?,
            shadow: get("shadow")?,
            outline: get("outline")?,
            reflection: get("reflection")?,
        }));
    }
    if let Some(t) = root.get("toonRamp") {
        let ramp = toon_ramp(t, "toonRamp", space, &mut warnings)?;
        layers.push(StylizationLayer::ToonRamp(ramp));
    }
    if let Some(s) = root.get("shadowPalette") {
        let o = s.as_object().ok_or("shadowPalette must be an object")?;
        warn_unknown(
            "shadowPalette",
            o.keys(),
            &["direct", "indirect"],
            &mut warnings,
        );
        layers.push(StylizationLayer::ShadowPalette(ShadowPalette {
            direct: adjust(o.get("direct"), "shadowPalette.direct", &mut warnings)?,
            indirect: adjust(o.get("indirect"), "shadowPalette.indirect", &mut warnings)?,
        }));
    }
    if let Some(r) = root.get("rimLight") {
        let o = r.as_object().ok_or("rimLight must be an object")?;
        let known = ["color", "width", "feather", "followLight", "strength"];
        warn_unknown("rimLight", o.keys(), &known, &mut warnings);
        let d = RimLight::default();
        let get = |k: &str, default| number(o.get(k), default, &format!("rimLight.{k}"));
        layers.push(StylizationLayer::RimLight(RimLight {
            color: match o.get("color") {
                Some(c) => rgb(c, "rimLight.color", space)?,
                None => d.color,
            },
            width: get("width", d.width)?,
            feather: get("feather", d.feather)?,
            follow_light: get("followLight", d.follow_light)?,
            strength: get("strength", d.strength)?,
        }));
    }
    if let Some(s) = root.get("stylizedSpecular") {
        let o = s.as_object().ok_or("stylizedSpecular must be an object")?;
        let known = [
            "shape", "size", "feather", "color", "strength", "ramp", "stretch", "angle", "texture",
        ];
        warn_unknown("stylizedSpecular", o.keys(), &known, &mut warnings);
        let d = StylizedSpecular::default();
        let get = |k: &str, default| number(o.get(k), default, &format!("stylizedSpecular.{k}"));
        let angle = get("angle", 0.0)?;
        let shape = match o.get("shape").map(|v| v.as_str()) {
            None | Some(Some("band")) => Some(HighlightShape::Band),
            Some(Some("ellipse")) => Some(HighlightShape::Ellipse {
                stretch: get("stretch", 2.0)?,
                angle,
            }),
            Some(Some("texture")) => {
                let index = o
                    .get("texture")
                    .and_then(Value::as_object)
                    .and_then(|t| t.get("index"))
                    .and_then(Value::as_u64)
                    .ok_or("stylizedSpecular.texture.index is required for shape \"texture\"")?;
                match resolve(index as usize)? {
                    Some(image) => Some(HighlightShape::Image { image, angle }),
                    None => {
                        warnings
                            .push("stylizedSpecular ignored: its texture could not be used".into());
                        None
                    }
                }
            }
            _ => {
                return Err(
                    "stylizedSpecular.shape must be \"band\", \"ellipse\" or \"texture\"".into(),
                );
            }
        };
        if let Some(shape) = shape {
            layers.push(StylizationLayer::StylizedSpecular(StylizedSpecular {
                shape,
                size: get("size", d.size)?,
                feather: get("feather", d.feather)?,
                color: match o.get("color") {
                    Some(c) => rgb(c, "stylizedSpecular.color", space)?,
                    None => d.color,
                },
                strength: get("strength", d.strength)?,
                ramp: match o.get("ramp") {
                    Some(r) => Some(toon_ramp(r, "stylizedSpecular.ramp", space, &mut warnings)?),
                    None => None,
                },
            }));
        }
    }
    if let Some(v) = root.get("outlineStyle") {
        let o = v.as_object().ok_or("outlineStyle must be an object")?;
        let known = ["color", "width", "depthThreshold", "creaseAngle"];
        warn_unknown("outlineStyle", o.keys(), &known, &mut warnings);
        let d = OutlineStyle::default();
        let get = |k: &str, default| number(o.get(k), default, &format!("outlineStyle.{k}"));
        layers.push(StylizationLayer::OutlineStyle(OutlineStyle {
            color: match o.get("color") {
                Some(c) => rgb(c, "outlineStyle.color", space)?,
                None => d.color,
            },
            width: get("width", d.width)?,
            depth_threshold: get("depthThreshold", d.depth_threshold)?,
            crease_angle: get("creaseAngle", d.crease_angle)?,
        }));
    }
    if let Some(v) = root.get("matcap") {
        let o = v.as_object().ok_or("matcap must be an object")?;
        warn_unknown(
            "matcap",
            o.keys(),
            &["texture", "strength", "albedo"],
            &mut warnings,
        );
        let index = o
            .get("texture")
            .and_then(Value::as_object)
            .and_then(|t| t.get("index"))
            .and_then(Value::as_u64)
            .ok_or("matcap.texture.index is required (a non-negative integer)")?;
        let get = |k: &str, default| number(o.get(k), default, &format!("matcap.{k}"));
        let (strength, albedo) = (get("strength", 1.0)?, get("albedo", 0.0)?);
        match resolve(index as usize)? {
            Some(image) => layers.push(StylizationLayer::MatCap(MatCap {
                image,
                strength,
                albedo,
            })),
            None => warnings.push("matcap ignored: its texture could not be used".into()),
        }
    }
    for layer in &layers {
        layer.validate().map_err(|e| format!("{e:?}"))?;
    }
    Ok((layers, warnings))
}

/// A `toonRamp`-shaped object; `what` names it in messages (`toonRamp`, `stylizedSpecular.ramp`).
fn toon_ramp(
    v: &Value,
    what: &str,
    space: ColorSpace,
    warnings: &mut Vec<String>,
) -> Result<ToonRamp, String> {
    let o = v
        .as_object()
        .ok_or_else(|| format!("{what} must be an object"))?;
    let known = ["thresholds", "feather", "palette", "lightWrap"];
    warn_unknown(what, o.keys(), &known, warnings);
    let thresholds = o
        .get("thresholds")
        .and_then(Value::as_array)
        .ok_or_else(|| format!("{what}.thresholds is required and must be an array"))?
        .iter()
        .map(|v| number(Some(v), 0.0, &format!("{what}.thresholds")))
        .collect::<Result<Vec<_>, _>>()?;
    let palette = o
        .get("palette")
        .and_then(Value::as_array)
        .ok_or_else(|| format!("{what}.palette is required and must be an array"))?
        .iter()
        .map(|c| rgb(c, &format!("{what}.palette entries"), space))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(ToonRamp {
        thresholds,
        feather: number(o.get("feather"), 0.0, &format!("{what}.feather"))?,
        palette,
        light_wrap: number(o.get("lightWrap"), 0.0, &format!("{what}.lightWrap"))?,
    })
}

fn adjust(
    v: Option<&Value>,
    what: &str,
    warnings: &mut Vec<String>,
) -> Result<ColorAdjust, String> {
    let Some(v) = v else {
        return Ok(ColorAdjust::default());
    };
    let o = v
        .as_object()
        .ok_or_else(|| format!("{what} must be an object"))?;
    warn_unknown(
        what,
        o.keys(),
        &["hueShift", "saturation", "value"],
        warnings,
    );
    let d = ColorAdjust::default();
    Ok(ColorAdjust {
        hue_shift: number(o.get("hueShift"), d.hue_shift, &format!("{what}.hueShift"))?,
        saturation: number(
            o.get("saturation"),
            d.saturation,
            &format!("{what}.saturation"),
        )?,
        value: number(o.get("value"), d.value, &format!("{what}.value"))?,
    })
}

/// A linear Rec.709 `[r, g, b]` converted to the working space.
fn rgb(v: &Value, what: &str, space: ColorSpace) -> Result<[f32; 3], String> {
    let c = v.as_array().filter(|c| c.len() == 3);
    let c = c.ok_or_else(|| format!("{what} must be [r, g, b]"))?;
    let rgb: [f32; 3] = std::array::from_fn(|i| c[i].as_f64().unwrap_or(f64::NAN) as f32);
    if rgb.iter().any(|v| v.is_nan()) {
        return Err(format!("{what} must be numbers"));
    }
    Ok(ColorSpace::LinearRec709.convert(space, rgb))
}

fn number(v: Option<&Value>, default: f32, what: &str) -> Result<f32, String> {
    match v {
        None => Ok(default),
        Some(v) => v
            .as_f64()
            .map(|n| n as f32)
            .ok_or_else(|| format!("{what} must be a number")),
    }
}

fn warn_unknown<'a>(
    scope: &str,
    keys: impl Iterator<Item = &'a String>,
    known: &[&str],
    warnings: &mut Vec<String>,
) {
    for k in keys.filter(|k| !known.contains(&k.as_str())) {
        warnings.push(format!("unknown property {scope}.{k}"));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse_str(s: &str) -> Result<(Vec<StylizationLayer>, Vec<String>), String> {
        let mut scene = verion_scene::Scene::new();
        let image = scene.add_image(verion_scene::Image::new(1, 1, vec![[1.0; 3]]).unwrap());
        parse(&serde_json_from(s), ColorSpace::LinearRec709, &mut |i| {
            if i == 0 {
                Ok(Some(image))
            } else {
                Err(format!("texture {i} does not exist"))
            }
        })
    }

    fn serde_json_from(s: &str) -> Value {
        s.parse().unwrap()
    }

    #[test]
    fn matcap_defaults_and_ranges() {
        let (layers, warnings) = parse_str(r#"{"matcap": {"texture": {"index": 0}}}"#).unwrap();
        assert!(warnings.is_empty());
        let [StylizationLayer::MatCap(m)] = &layers[..] else {
            panic!()
        };
        assert_eq!((m.strength, m.albedo), (1.0, 0.0));
        assert!(parse_str(r#"{"matcap": {"texture": {"index": 0}, "strength": 1.5}}"#).is_err());
        assert!(parse_str(r#"{"matcap": {"texture": {"index": 1}}}"#).is_err()); // no such texture
        assert!(parse_str(r#"{"matcap": {}}"#).is_err()); // the texture is required
    }

    #[test]
    fn reads_both_layers() {
        let (layers, warnings) = parse_str(
            r#"{"hybridSurface":{"diffuse":1,"reflection":0.25},
                "toonRamp":{"thresholds":[0.5],"palette":[[0.2,0.2,0.2],[1,1,1]],"feather":0.1}}"#,
        )
        .unwrap();
        assert!(warnings.is_empty());
        assert_eq!(
            layers[0],
            StylizationLayer::HybridSurface(HybridSurface {
                diffuse: 1.0,
                reflection: 0.25,
                ..Default::default()
            })
        );
        let StylizationLayer::ToonRamp(t) = &layers[1] else {
            panic!()
        };
        assert_eq!(
            (t.thresholds.clone(), t.feather, t.light_wrap),
            (vec![0.5], 0.1, 0.0)
        );
        assert_eq!(t.palette[1], [1.0; 3]);
    }

    #[test]
    fn reads_the_shadow_palette_with_defaults() {
        let (layers, warnings) =
            parse_str(r#"{"shadowPalette":{"direct":{"hueShift":-20,"value":0.7}}}"#).unwrap();
        assert!(warnings.is_empty());
        let StylizationLayer::ShadowPalette(s) = &layers[0] else {
            panic!()
        };
        assert_eq!(
            s.direct,
            ColorAdjust {
                hue_shift: -20.0,
                saturation: 1.0,
                value: 0.7
            }
        );
        assert_eq!(s.indirect, ColorAdjust::default());
        assert!(parse_str(r#"{"shadowPalette":{"indirect":{"hueShift":200}}}"#).is_err());
    }

    #[test]
    fn reads_the_rim_light_with_defaults() {
        let (layers, warnings) = parse_str(r#"{"rimLight":{"width":0.5}}"#).unwrap();
        assert!(warnings.is_empty());
        assert_eq!(
            layers,
            [StylizationLayer::RimLight(RimLight {
                width: 0.5,
                ..Default::default()
            })]
        );
        let (layers, _) = parse_str(r#"{"rimLight":{"color":[0.5,0.25,0],"strength":2}}"#).unwrap();
        let StylizationLayer::RimLight(r) = &layers[0] else {
            panic!()
        };
        assert_eq!((r.color, r.strength), ([0.5, 0.25, 0.0], 2.0));
        assert!(parse_str(r#"{"rimLight":{"color":[1,1]}}"#).is_err());
        assert!(parse_str(r#"{"rimLight":{"color":[1,-1,1]}}"#).is_err());
        assert!(parse_str(r#"{"rimLight":{"strength":-1}}"#).is_err());
        assert!(parse_str(r#"{"rimLight":{"followLight":2}}"#).is_err());
    }

    #[test]
    fn reads_the_stylized_specular_with_defaults() {
        let (layers, warnings) =
            parse_str(r#"{"stylizedSpecular":{"shape":"band","size":0.1,"strength":3}}"#).unwrap();
        assert!(warnings.is_empty());
        assert_eq!(
            layers,
            [StylizationLayer::StylizedSpecular(StylizedSpecular {
                size: 0.1,
                strength: 3.0,
                ..Default::default()
            })]
        );
        let (layers, _) = parse_str(
            r#"{"stylizedSpecular":{"ramp":{"thresholds":[0.5],"palette":[[0,0,0],[1,1,1]]}}}"#,
        )
        .unwrap();
        let StylizationLayer::StylizedSpecular(s) = &layers[0] else {
            panic!()
        };
        assert_eq!(s.ramp.as_ref().unwrap().thresholds, [0.5]);
        // The ramp follows the toonRamp rules: one palette color per band.
        let short = r#"{"stylizedSpecular":{"ramp":{"thresholds":[0.5],"palette":[[1,1,1]]}}}"#;
        assert!(parse_str(short).is_err());
        assert!(parse_str(r#"{"stylizedSpecular":{"shape":"star"}}"#).is_err());
    }

    #[test]
    fn reads_the_highlight_shapes() {
        let shape = |s: &str| {
            let (layers, _) = parse_str(s).unwrap();
            let [StylizationLayer::StylizedSpecular(sp)] = &layers[..] else {
                panic!()
            };
            sp.shape
        };
        assert_eq!(
            shape(r#"{"stylizedSpecular":{"shape":"ellipse"}}"#),
            HighlightShape::Ellipse {
                stretch: 2.0,
                angle: 0.0
            }
        );
        assert_eq!(
            shape(r#"{"stylizedSpecular":{"shape":"ellipse","stretch":4,"angle":-30}}"#),
            HighlightShape::Ellipse {
                stretch: 4.0,
                angle: -30.0
            }
        );
        let s = r#"{"stylizedSpecular":{"shape":"texture","texture":{"index":0},"angle":45}}"#;
        assert!(matches!(
            shape(s),
            HighlightShape::Image { angle: 45.0, .. }
        ));
        assert!(parse_str(r#"{"stylizedSpecular":{"shape":"texture"}}"#).is_err());
        assert!(parse_str(r#"{"stylizedSpecular":{"shape":"ellipse","stretch":20}}"#).is_err());
        assert!(parse_str(r#"{"stylizedSpecular":{"shape":"ellipse","angle":200}}"#).is_err());
        assert!(parse_str(r#"{"stylizedSpecular":{"size":2}}"#).is_err());
        assert!(parse_str(r#"{"stylizedSpecular":{"color":[1,-1,1]}}"#).is_err());
    }

    #[test]
    fn reads_the_outline_style_with_defaults() {
        let (layers, warnings) =
            parse_str(r#"{"outlineStyle":{"width":3,"creaseAngle":30}}"#).unwrap();
        assert!(warnings.is_empty());
        assert_eq!(
            layers,
            [StylizationLayer::OutlineStyle(OutlineStyle {
                width: 3.0,
                crease_angle: 30.0,
                ..Default::default()
            })]
        );
        assert!(parse_str(r#"{"outlineStyle":{"width":0.5}}"#).is_err());
        assert!(parse_str(r#"{"outlineStyle":{"width":9}}"#).is_err());
        assert!(parse_str(r#"{"outlineStyle":{"creaseAngle":200}}"#).is_err());
        assert!(parse_str(r#"{"outlineStyle":{"depthThreshold":2}}"#).is_err());
        assert!(parse_str(r#"{"outlineStyle":{"color":[1,-1,1]}}"#).is_err());
    }

    #[test]
    fn rejects_bad_values_and_warns_on_unknown_properties() {
        assert!(parse_str(r#"{"hybridSurface":{"diffuse":2}}"#).is_err());
        assert!(parse_str(r#"{"hybridSurface":{"diffuse":"x"}}"#).is_err());
        let short = r#"{"toonRamp":{"thresholds":[0.5],"palette":[[1,1,1]]}}"#;
        assert!(parse_str(short).is_err());
        let unsorted =
            r#"{"toonRamp":{"thresholds":[0.6,0.4],"palette":[[1,1,1],[1,1,1],[1,1,1]]}}"#;
        assert!(parse_str(unsorted).is_err());
        let (_, w) = parse_str(r#"{"future":1,"hybridSurface":{"rim":1}}"#).unwrap();
        assert_eq!(
            w,
            [
                "unknown property future",
                "unknown property hybridSurface.rim"
            ]
        );
    }
}
