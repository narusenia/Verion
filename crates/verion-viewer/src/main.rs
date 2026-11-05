//! `viewer scene.gltf`: progressive preview with AOV switching and a live color grade (REQ-VIEW-002).
//! The accumulated image is shown as an egui texture (ADR-0012).

#[cfg(target_os = "macos")]
mod app;
#[cfg(target_os = "macos")]
mod material_ui;
#[cfg(target_os = "macos")]
mod theme;
#[cfg(target_os = "macos")]
mod widgets;

#[cfg(target_os = "macos")]
fn main() -> Result<(), Box<dyn std::error::Error>> {
    use clap::Parser;
    let args = app::Args::parse();
    let state = app::App::new(&args)?;
    let options = eframe::NativeOptions {
        viewport: eframe::egui::ViewportBuilder::default()
            .with_inner_size([1280.0, 780.0])
            .with_min_inner_size([720.0, 480.0]),
        ..Default::default()
    };
    eframe::run_native(
        "Verion Viewer",
        options,
        Box::new(|cc| {
            theme::install(&cc.egui_ctx);
            egui_material_icons::initialize(&cc.egui_ctx);
            Ok(Box::new(state))
        }),
    )?;
    Ok(())
}

#[cfg(not(target_os = "macos"))]
fn main() {
    eprintln!("viewer requires macOS (Metal)");
    std::process::exit(1);
}
