//! `VERION_materials_stylization` -> `StylizationLayer`s (REQ-IO-002; see
//! docs/specifications/gltf-stylization-extension.md).

use gltf::json::Value;
use verion_scene::{
    ColorAdjust, ColorSpace, HybridSurface, RimLight, ShadowPalette, StylizationLayer, ToonRamp,
};

pub const NAME: &str = "VERION_materials_stylization";

/// Layers plus warnings for unknown properties. `Err` carries a message for the import error.
pub fn parse(
    value: &Value,
    space: ColorSpace,
) -> Result<(Vec<StylizationLayer>, Vec<String>), String> {
    let root = value.as_object().ok_or("must be an object")?;
    let mut warnings = Vec::new();
    let mut layers = Vec::new();
    for key in root.keys().filter(|k| {
        !["hybridSurface", "toonRamp", "shadowPalette", "rimLight"].contains(&k.as_str())
    }) {
        warnings.push(format!("unknown property {key}"));
    }
    if let Some(h) = root.get("hybridSurface") {
        let o = h.as_object().ok_or("hybridSurface must be an object")?;
        let known = ["diffuse", "specular", "gi", "shadow", "outline"];
        warn_unknown("hybridSurface", o.keys(), &known, &mut warnings);
        let get = |k: &str| number(o.get(k), 0.0, &format!("hybridSurface.{k}"));
        layers.push(StylizationLayer::HybridSurface(HybridSurface {
            diffuse: get("diffuse")?,
            specular: get("specular")?,
            gi: get("gi")?,
            shadow: get("shadow")?,
            outline: get("outline")?,
        }));
    }
    if let Some(t) = root.get("toonRamp") {
        let o = t.as_object().ok_or("toonRamp must be an object")?;
        let known = ["thresholds", "feather", "palette", "lightWrap"];
        warn_unknown("toonRamp", o.keys(), &known, &mut warnings);
        let thresholds = o
            .get("thresholds")
            .and_then(Value::as_array)
            .ok_or("toonRamp.thresholds is required and must be an array")?
            .iter()
            .map(|v| number(Some(v), 0.0, "toonRamp.thresholds"))
            .collect::<Result<Vec<_>, _>>()?;
        let palette = o
            .get("palette")
            .and_then(Value::as_array)
            .ok_or("toonRamp.palette is required and must be an array")?
            .iter()
            .map(|c| rgb(c, "toonRamp.palette entries", space))
            .collect::<Result<Vec<_>, _>>()?;
        layers.push(StylizationLayer::ToonRamp(ToonRamp {
            thresholds,
            feather: number(o.get("feather"), 0.0, "toonRamp.feather")?,
            palette,
            light_wrap: number(o.get("lightWrap"), 0.0, "toonRamp.lightWrap")?,
        }));
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
    for layer in &layers {
        layer.validate().map_err(|e| format!("{e:?}"))?;
    }
    Ok((layers, warnings))
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
        parse(&serde_json_from(s), ColorSpace::LinearRec709)
    }

    fn serde_json_from(s: &str) -> Value {
        s.parse().unwrap()
    }

    #[test]
    fn reads_both_layers() {
        let (layers, warnings) = parse_str(
            r#"{"hybridSurface":{"diffuse":1},
                "toonRamp":{"thresholds":[0.5],"palette":[[0.2,0.2,0.2],[1,1,1]],"feather":0.1}}"#,
        )
        .unwrap();
        assert!(warnings.is_empty());
        assert_eq!(
            layers[0],
            StylizationLayer::HybridSurface(HybridSurface {
                diffuse: 1.0,
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
