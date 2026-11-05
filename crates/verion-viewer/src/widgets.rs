//! Compact label + control rows shared by the inspector sections.

use std::ops::RangeInclusive;

use eframe::egui::{
    self, Align, CollapsingHeader, DragValue, FontId, Layout, Response, RichText, Slider,
    TextFormat, Ui, text::LayoutJob,
};
use egui_material_icons::MaterialIcon;

use crate::theme::{MUTED, TEXT};

const LABEL_W: f32 = 84.0;
const VALUE_W: f32 = 58.0;

/// A muted label on the left; `add` fills the rest of the row.
pub fn row(ui: &mut Ui, label: &str, add: impl FnOnce(&mut Ui) -> Response) -> Response {
    ui.horizontal(|ui| {
        let h = ui.spacing().interact_size.y;
        let name = ui
            .allocate_ui_with_layout(
                egui::vec2(LABEL_W, h),
                Layout::left_to_right(Align::Center),
                |ui| ui.add(egui::Label::new(RichText::new(label).color(MUTED)).truncate()),
            )
            .inner;
        ui.spacing_mut().slider_width = (ui.available_width() - VALUE_W).max(40.0);
        // Screen readers and UI tests find the control by its row label.
        add(ui).labelled_by(name.id)
    })
    .inner
}

pub fn slider(ui: &mut Ui, v: &mut f32, range: RangeInclusive<f32>, label: &str) -> bool {
    row(ui, label, |ui| {
        ui.add(Slider::new(v, range).fixed_decimals(2))
    })
    .changed()
}

pub fn unit(ui: &mut Ui, v: &mut f32, label: &str) -> bool {
    slider(ui, v, 0.0..=1.0, label)
}

/// A slider that spans decades, for intensities. A logarithmic slider re-reports its own rounding
/// as a change every frame, so only a drag, a click on the rail or a typed value counts.
pub fn log_slider(ui: &mut Ui, v: &mut f32, range: RangeInclusive<f32>, label: &str) -> bool {
    let mut touched = false;
    row(ui, label, |ui| {
        let r = ui.add(
            Slider::new(v, range)
                .logarithmic(true)
                .smallest_positive(1e-3)
                .fixed_decimals(2),
        );
        touched = r.changed() && (r.dragged() || r.is_pointer_button_down_on() || r.has_focus());
        r
    });
    touched
}

/// A color in `0..=1`.
pub fn color(ui: &mut Ui, c: &mut [f32; 3], label: &str) -> bool {
    row(ui, label, |ui| {
        egui::color_picker::color_edit_button_rgb(ui, c)
    })
    .changed()
}

/// A color that may exceed 1: a picker for the hue and a multiplier for the level.
pub fn hdr(ui: &mut Ui, c: &mut [f32; 3], label: &str) -> bool {
    let mut level = c.iter().copied().fold(0.0, f32::max);
    let mut hue = if level > 0.0 {
        c.map(|v| v / level)
    } else {
        [1.0; 3]
    };
    let mut changed = false;
    row(ui, label, |ui| {
        let a = egui::color_picker::color_edit_button_rgb(ui, &mut hue);
        let b = ui.add(
            DragValue::new(&mut level)
                .speed(0.02)
                .range(0.0..=10_000.0)
                .prefix("x "),
        );
        changed = a.changed() || b.changed();
        a.union(b)
    });
    if changed {
        *c = hue.map(|v| v * level);
    }
    changed
}

pub fn vec3(ui: &mut Ui, v: &mut [f32; 3], label: &str, speed: f32) -> bool {
    row(ui, label, |ui| {
        let mut r = None::<Response>;
        for (c, axis) in v.iter_mut().zip(["x", "y", "z"]) {
            let d = ui.add(
                DragValue::new(c)
                    .speed(speed)
                    .prefix(axis)
                    .fixed_decimals(2),
            );
            r = Some(r.map_or(d.clone(), |p| p.union(d)));
        }
        r.expect("three components")
    })
    .changed()
}

pub fn checkbox(ui: &mut Ui, v: &mut bool, label: &str) -> bool {
    ui.checkbox(v, label).changed()
}

/// A muted key with its value.
pub fn kv(ui: &mut Ui, k: &str, v: impl Into<String>) {
    ui.horizontal(|ui| {
        ui.allocate_ui_with_layout(
            egui::vec2(LABEL_W, ui.spacing().interact_size.y),
            Layout::left_to_right(Align::Center),
            |ui| {
                ui.label(RichText::new(k).color(MUTED));
            },
        );
        ui.label(RichText::new(v.into()).monospace());
    });
}

/// A collapsing section whose header carries an icon.
pub fn section<R>(
    ui: &mut Ui,
    icon: MaterialIcon,
    title: &str,
    open: bool,
    add: impl FnOnce(&mut Ui) -> R,
) -> Option<R> {
    let mut job = LayoutJob::default();
    job.append(
        icon.codepoint,
        0.0,
        TextFormat {
            font_id: FontId::new(14.0, icon.font_family()),
            color: MUTED,
            valign: Align::Center,
            ..Default::default()
        },
    );
    job.append(
        title,
        6.0,
        TextFormat {
            font_id: FontId::proportional(12.0),
            color: TEXT,
            valign: Align::Center,
            ..Default::default()
        },
    );
    CollapsingHeader::new(job)
        .id_salt(title)
        .default_open(open)
        .show(ui, add)
        .body_returned
}
