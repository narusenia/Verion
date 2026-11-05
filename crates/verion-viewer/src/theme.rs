//! Compact dark theme: 12 pt text, 22 pt controls, 3 pt corners, flat surfaces with thin borders.

use eframe::egui::{
    self, Color32, CornerRadius, FontFamily, FontId, Stroke, TextStyle, Vec2, Visuals,
    epaint::Shadow,
};

const fn rgb(hex: u32) -> Color32 {
    Color32::from_rgb((hex >> 16) as u8, (hex >> 8) as u8, hex as u8)
}

pub const BACKGROUND: Color32 = rgb(0x0e0e0e);
pub const SURFACE: Color32 = rgb(0x151515);
pub const RAISED: Color32 = rgb(0x1c1c1c);
pub const BORDER: Color32 = rgb(0x2e2e2e);
pub const BORDER_STRONG: Color32 = rgb(0x484848);
pub const TEXT: Color32 = rgb(0xe8e8e8);
pub const MUTED: Color32 = rgb(0x9a9a9a);
pub const ACCENT: Color32 = rgb(0x7a88f0);
pub const ON_ACCENT: Color32 = rgb(0x0e0e0e);
pub const CONTROL: Color32 = rgb(0x2a2a2a);
pub const CONTROL_HOVER: Color32 = rgb(0x353535);
pub const CONTROL_ACTIVE: Color32 = rgb(0x404040);
pub const WARNING: Color32 = rgb(0xe5a946);
pub const SUCCESS: Color32 = rgb(0x4cc38a);

const TEXT_SIZE: f32 = 12.0;
const RADIUS: u8 = 3;

pub fn install(ctx: &egui::Context) {
    let mut v = Visuals::dark();
    v.panel_fill = SURFACE;
    v.window_fill = RAISED;
    v.faint_bg_color = SURFACE;
    v.extreme_bg_color = CONTROL;
    v.window_stroke = Stroke::new(1.0, BORDER);
    v.window_corner_radius = CornerRadius::same(RADIUS + 2);
    v.menu_corner_radius = CornerRadius::same(RADIUS);
    v.window_shadow = Shadow::NONE;
    v.popup_shadow = Shadow::NONE;
    v.selection.bg_fill = ACCENT;
    v.selection.stroke = Stroke::new(1.0, ON_ACCENT);
    v.hyperlink_color = ACCENT;
    v.warn_fg_color = WARNING;
    v.weak_text_color = Some(MUTED);
    v.handle_shape = egui::style::HandleShape::Circle;
    let w = &mut v.widgets;
    w.noninteractive.bg_fill = SURFACE;
    w.noninteractive.bg_stroke = Stroke::new(1.0, BORDER);
    w.noninteractive.fg_stroke = Stroke::new(1.0, TEXT);
    for (state, fill) in [
        (&mut w.inactive, CONTROL),
        (&mut w.hovered, CONTROL_HOVER),
        (&mut w.active, CONTROL_ACTIVE),
        (&mut w.open, CONTROL_HOVER),
    ] {
        state.bg_fill = fill;
        state.weak_bg_fill = fill;
        state.bg_stroke = Stroke::new(1.0, BORDER);
        state.fg_stroke = Stroke::new(1.0, TEXT);
    }
    // Slider rails and checkbox frames use `bg_fill`; buttons use the weak one.
    w.inactive.bg_fill = CONTROL_HOVER;
    w.hovered.bg_stroke = Stroke::new(1.0, BORDER_STRONG);
    for state in [
        &mut w.noninteractive,
        &mut w.inactive,
        &mut w.hovered,
        &mut w.active,
        &mut w.open,
    ] {
        state.corner_radius = CornerRadius::same(RADIUS);
    }

    let mut style = egui::Style {
        visuals: v,
        ..Default::default()
    };
    style.spacing.item_spacing = Vec2::splat(4.0);
    style.spacing.button_padding = Vec2::new(8.0, 2.0);
    style.spacing.interact_size.y = 22.0;
    style.spacing.slider_rail_height = 2.0;
    style.spacing.icon_width = 14.0;
    style.spacing.menu_margin = egui::Margin::same(4);
    style.spacing.tooltip_width = 280.0;
    style.text_styles = [
        (
            TextStyle::Small,
            FontId::new(TEXT_SIZE - 2.0, FontFamily::Proportional),
        ),
        (
            TextStyle::Body,
            FontId::new(TEXT_SIZE, FontFamily::Proportional),
        ),
        (
            TextStyle::Button,
            FontId::new(TEXT_SIZE, FontFamily::Proportional),
        ),
        (
            TextStyle::Heading,
            FontId::new(TEXT_SIZE + 3.0, FontFamily::Proportional),
        ),
        (
            TextStyle::Monospace,
            FontId::new(TEXT_SIZE, FontFamily::Monospace),
        ),
    ]
    .into();
    ctx.set_style_of(egui::Theme::Dark, style);
    ctx.set_theme(egui::ThemePreference::Dark);
}
