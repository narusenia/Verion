//! Material inspector: the physical base and every stylization layer, edited in place.

use eframe::egui::{self, Ui};
use verion_scene::{
    BaseBsdf, ColorAdjust, HighlightShape, HybridSurface, Material, OutlineStyle, RimLight,
    ShadowPalette, StylizationLayer, StylizedSpecular, ToonRamp,
};

use egui_material_icons::icons::*;

use crate::widgets::{checkbox, color, hdr, kv, section, slider, unit};

/// Stylization layers copied from one material, ready to paste onto another.
pub type Clipboard = Option<Vec<StylizationLayer>>;

pub fn edit(ui: &mut Ui, m: &mut Material, original: &Material, clip: &mut Clipboard) {
    ui.horizontal(|ui| {
        if ui
            .button((ICON_UNDO.rich_text(), "Revert"))
            .on_hover_text("Back to the loaded values")
            .clicked()
        {
            *m = original.clone();
        }
        if ui
            .button((ICON_CONTENT_COPY.rich_text(), "Copy style"))
            .on_hover_text("Copy the stylization layers")
            .clicked()
        {
            *clip = Some(m.stylization.clone());
        }
        let paste = ui.add_enabled(
            clip.is_some(),
            egui::Button::new((ICON_CONTENT_PASTE.rich_text(), "Paste style")),
        );
        if let (true, Some(c)) = (paste.clicked(), clip.as_ref()) {
            m.stylization.clone_from(c);
        }
    });
    section(ui, ICON_VIEW_IN_AR, "Base (physical)", true, |ui| {
        base(ui, &mut m.base)
    });
    section(
        ui,
        ICON_AUTO_FIX_HIGH,
        "Stylization (non-physical)",
        true,
        |ui| stylization(ui, m),
    );
}

type Preset = (&'static str, fn(&mut BaseBsdf));

const PRESETS: [Preset; 6] = [
    ("Matte", |b| {
        (b.metallic, b.roughness, b.transmission) = (0.0, 0.9, 0.0);
    }),
    ("Plastic", |b| {
        (b.metallic, b.roughness, b.transmission) = (0.0, 0.25, 0.0);
    }),
    ("Gold", |b| {
        b.base_color = [1.0, 0.77, 0.34];
        (b.metallic, b.roughness, b.transmission) = (1.0, 0.2, 0.0);
    }),
    ("Mirror", |b| {
        b.base_color = [0.95; 3];
        (b.metallic, b.roughness, b.transmission) = (1.0, 0.0, 0.0);
    }),
    ("Glass", |b| {
        b.base_color = [1.0; 3];
        (b.metallic, b.roughness, b.transmission, b.ior) = (0.0, 0.0, 1.0, 1.5);
    }),
    ("Lacquer", |b| {
        (b.metallic, b.roughness, b.clearcoat, b.clearcoat_roughness) = (0.0, 0.6, 1.0, 0.03);
    }),
];

fn base(ui: &mut Ui, b: &mut BaseBsdf) {
    ui.horizontal_wrapped(|ui| {
        for (name, apply) in PRESETS {
            if ui.small_button(name).clicked() {
                apply(b);
            }
        }
    });
    color(ui, &mut b.base_color, "base color");
    unit(ui, &mut b.metallic, "metallic");
    unit(ui, &mut b.roughness, "roughness");
    unit(ui, &mut b.transmission, "transmission");
    slider(ui, &mut b.ior, 1.0..=3.0, "ior");
    ui.add_enabled_ui(b.transmission > 0.0, |ui| {
        slider(ui, &mut b.dispersion, 0.0..=10.0, "dispersion");
    });
    section(ui, ICON_CONTRAST, "Clear coat", b.clearcoat > 0.0, |ui| {
        unit(ui, &mut b.clearcoat, "coat");
        unit(ui, &mut b.clearcoat_roughness, "coat rough");
    });
    section(ui, ICON_TEXTURE, "Sheen", b.sheen_color != [0.0; 3], |ui| {
        color(ui, &mut b.sheen_color, "sheen color");
        unit(ui, &mut b.sheen_roughness, "sheen rough");
    });
    section(
        ui,
        ICON_LIGHTBULB,
        "Emission",
        b.emission != [0.0; 3],
        |ui| {
            hdr(ui, &mut b.emission, "emission");
        },
    );
    section(ui, ICON_IMAGE, "Textures", false, |ui| {
        for (name, t) in [
            ("base color", b.base_color_texture),
            ("metal/rough", b.metallic_roughness_texture),
            ("emission", b.emission_texture),
            ("normal", b.normal_texture),
        ] {
            kv(
                ui,
                name,
                t.map_or("-".to_owned(), |i| format!("image {}", i.index())),
            );
        }
        if b.normal_texture.is_some() {
            slider(ui, &mut b.normal_scale, 0.0..=4.0, "normal scale");
        }
    });
}

fn toon_default() -> Vec<StylizationLayer> {
    vec![
        StylizationLayer::HybridSurface(HybridSurface::TOON),
        StylizationLayer::ToonRamp(ToonRamp {
            thresholds: vec![0.3, 0.7],
            feather: 0.05,
            palette: vec![[0.5; 3], [0.8; 3], [1.0; 3]],
            light_wrap: 0.0,
        }),
        StylizationLayer::OutlineStyle(OutlineStyle::default()),
    ]
}

fn layer_name(l: &StylizationLayer) -> &'static str {
    match l {
        StylizationLayer::HybridSurface(_) => "Hybrid surface",
        StylizationLayer::ToonRamp(_) => "Toon ramp",
        StylizationLayer::ShadowPalette(_) => "Shadow palette",
        StylizationLayer::RimLight(_) => "Rim light",
        StylizationLayer::StylizedSpecular(_) => "Stylized specular",
        StylizationLayer::OutlineStyle(_) => "Outline",
        StylizationLayer::MatCap(_) => "MatCap",
    }
}

fn stylization(ui: &mut Ui, m: &mut Material) {
    let layers = &mut m.stylization;
    ui.horizontal(|ui| {
        if layers.is_empty()
            && ui
                .button((ICON_AUTO_FIX_HIGH.rich_text(), "Toon preset"))
                .clicked()
        {
            *layers = toon_default();
        }
        ui.menu_button((ICON_ADD.rich_text(), "Add layer"), |ui| {
            let new: [(&str, StylizationLayer); 6] = [
                (
                    "Hybrid surface",
                    StylizationLayer::HybridSurface(HybridSurface::TOON),
                ),
                ("Toon ramp", toon_default().swap_remove(1)),
                (
                    "Shadow palette",
                    StylizationLayer::ShadowPalette(ShadowPalette::default()),
                ),
                ("Rim light", StylizationLayer::RimLight(RimLight::default())),
                (
                    "Stylized specular",
                    StylizationLayer::StylizedSpecular(StylizedSpecular::default()),
                ),
                (
                    "Outline",
                    StylizationLayer::OutlineStyle(OutlineStyle::default()),
                ),
            ];
            for (name, layer) in new {
                let has = layers
                    .iter()
                    .any(|l| std::mem::discriminant(l) == std::mem::discriminant(&layer));
                if ui.add_enabled(!has, egui::Button::new(name)).clicked() {
                    layers.push(layer);
                    ui.close();
                }
            }
        });
        if !layers.is_empty()
            && ui
                .button((ICON_DELETE.rich_text(), "Clear layers"))
                .clicked()
        {
            layers.clear();
        }
    });
    let mut remove = None;
    for (i, layer) in layers.iter_mut().enumerate() {
        let title = layer_name(layer);
        egui::CollapsingHeader::new(title)
            .id_salt(("layer", i))
            .default_open(true)
            .show(ui, |ui| {
                if ui
                    .small_button((ICON_CLOSE.rich_text(), "Remove layer"))
                    .clicked()
                {
                    remove = Some(i);
                }
                layer_ui(ui, layer, i);
            });
    }
    if let Some(i) = remove {
        layers.remove(i);
    }
}

fn layer_ui(ui: &mut Ui, layer: &mut StylizationLayer, id: usize) {
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
            ui.horizontal(|ui| {
                if ui.small_button("All physical").clicked() {
                    *h = HybridSurface::default();
                }
                if ui.small_button("All toon").clicked() {
                    *h = HybridSurface::TOON;
                }
            });
        }
        StylizationLayer::ToonRamp(t) => ramp(ui, t, true, id),
        StylizationLayer::ShadowPalette(s) => {
            for (a, name) in [(&mut s.direct, "direct"), (&mut s.indirect, "indirect")] {
                adjust(ui, a, name);
            }
        }
        StylizationLayer::RimLight(r) => {
            color(ui, &mut r.color, "color");
            unit(ui, &mut r.width, "width");
            unit(ui, &mut r.feather, "feather");
            unit(ui, &mut r.follow_light, "follow light");
            slider(ui, &mut r.strength, 0.0..=4.0, "strength");
        }
        StylizationLayer::StylizedSpecular(s) => {
            ui.horizontal(|ui| {
                let round = matches!(s.shape, HighlightShape::Band);
                if ui.selectable_label(round, "round").clicked() && !round {
                    s.shape = HighlightShape::Band;
                }
                let ellipse = matches!(s.shape, HighlightShape::Ellipse { .. });
                if ui.selectable_label(ellipse, "ellipse").clicked() && !ellipse {
                    s.shape = HighlightShape::Ellipse {
                        stretch: 2.0,
                        angle: 0.0,
                    };
                }
                // shortcut: an image shape comes from the glTF only; picking an image here needs the scene's image list.
                if let HighlightShape::Image { image, .. } = s.shape {
                    ui.label(format!("image {}", image.index()));
                }
            });
            match &mut s.shape {
                HighlightShape::Band => {}
                HighlightShape::Ellipse { stretch, angle } => {
                    slider(ui, stretch, 0.1..=10.0, "stretch");
                    slider(ui, angle, -180.0..=180.0, "angle deg");
                }
                HighlightShape::Image { angle, .. } => {
                    slider(ui, angle, -180.0..=180.0, "angle deg");
                }
            }
            color(ui, &mut s.color, "color");
            unit(ui, &mut s.size, "size");
            unit(ui, &mut s.feather, "feather");
            slider(ui, &mut s.strength, 0.0..=4.0, "strength");
            let mut stepped = s.ramp.is_some();
            if checkbox(ui, &mut stepped, "stepped highlight") {
                s.ramp = stepped.then(|| ToonRamp {
                    thresholds: vec![0.5],
                    feather: 0.05,
                    palette: vec![[0.0; 3], [1.0; 3]],
                    light_wrap: 0.0,
                });
            }
            if let Some(r) = &mut s.ramp {
                ramp(ui, r, false, id);
            }
        }
        StylizationLayer::OutlineStyle(o) => {
            color(ui, &mut o.color, "color");
            slider(ui, &mut o.width, 1.0..=8.0, "width px");
            unit(ui, &mut o.depth_threshold, "depth thresh");
            slider(ui, &mut o.crease_angle, 0.0..=180.0, "crease deg");
        }
        StylizationLayer::MatCap(mc) => {
            kv(ui, "image", format!("image {}", mc.image.index()));
            unit(ui, &mut mc.strength, "strength");
            unit(ui, &mut mc.albedo, "albedo");
        }
    }
}

fn adjust(ui: &mut Ui, a: &mut ColorAdjust, name: &str) {
    ui.label(name);
    slider(ui, &mut a.hue_shift, -180.0..=180.0, "hue");
    slider(ui, &mut a.saturation, 0.0..=2.0, "saturation");
    slider(ui, &mut a.value, 0.0..=2.0, "value");
}

/// Bands from dark to lit: one color per band and a threshold between neighbours.
fn ramp(ui: &mut Ui, t: &mut ToonRamp, wrap: bool, id: usize) {
    unit(ui, &mut t.feather, "feather");
    if wrap {
        unit(ui, &mut t.light_wrap, "light wrap");
    }
    let bands = t.palette.len();
    for i in 0..bands {
        ui.push_id((id, i), |ui| {
            ui.horizontal(|ui| {
                let name = ui.label(format!("band {i}"));
                egui::color_picker::color_edit_button_rgb(ui, &mut t.palette[i]);
                if i + 1 < bands {
                    let lo = if i == 0 {
                        0.0
                    } else {
                        t.thresholds[i - 1] + 0.01
                    };
                    let hi = t.thresholds.get(i + 1).map_or(1.0, |n| n - 0.01);
                    let v = &mut t.thresholds[i];
                    *v = v.clamp(lo, hi.max(lo));
                    ui.spacing_mut().slider_width = (ui.available_width() - 58.0).max(40.0);
                    ui.add(egui::Slider::new(v, lo..=hi.max(lo + 1e-3)).fixed_decimals(2))
                        .labelled_by(name.id);
                }
            });
        });
    }
    ui.horizontal(|ui| {
        if ui.small_button("+ band").clicked() && t.thresholds.last().is_none_or(|l| *l < 0.98) {
            let next = t.thresholds.last().map_or(0.5, |l| (l + 1.0) / 2.0);
            t.thresholds.push(next);
            t.palette.push([1.0; 3]);
        }
        if ui.small_button("- band").clicked() && !t.thresholds.is_empty() {
            t.thresholds.pop();
            t.palette.pop();
        }
    });
}

#[cfg(test)]
mod tests {
    use egui_kittest::{Harness, kittest::Queryable};

    use super::*;

    fn harness(m: Material) -> Harness<'static, (Material, Material, Clipboard)> {
        let original = m.clone();
        Harness::new_ui_state(
            |ui, (m, original, clip)| {
                egui_material_icons::initialize(ui.ctx());
                edit(ui, m, original, clip);
            },
            (m, original, None),
        )
    }

    #[test]
    fn preset_edits_the_physical_base_and_revert_restores_it() {
        let mut h = harness(Material::default());
        h.get_by_label("Gold").click();
        h.run();
        let base = &h.state().0.base;
        assert_eq!((base.metallic, base.base_color[0]), (1.0, 1.0));
        h.get_by_label_contains("Revert").click();
        h.run();
        assert_eq!(h.state().0, Material::default());
    }

    #[test]
    fn toon_preset_adds_layers_and_clear_removes_them() {
        let mut h = harness(Material::default());
        h.get_by_label_contains("Toon preset").click();
        h.run();
        assert_eq!(h.state().0.stylization.len(), 3);
        h.get_by_label_contains("Clear layers").click();
        h.run();
        assert!(h.state().0.stylization.is_empty());
    }

    #[test]
    fn copy_then_paste_moves_stylization_between_materials() {
        let styled = Material {
            stylization: toon_default(),
            ..Material::default()
        };
        let mut h = harness(styled.clone());
        h.get_by_label_contains("Copy style").click();
        h.run();
        h.state_mut().0.stylization.clear();
        h.run();
        h.get_by_label_contains("Paste style").click();
        h.run();
        assert_eq!(h.state().0.stylization, styled.stylization);
    }
}
