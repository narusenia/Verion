//! `viewer scene.gltf`: progressive preview with AOV switching and a live color grade (REQ-VIEW-002).
//! The accumulated image is shown as an egui texture (ADR-0012).

#[cfg(target_os = "macos")]
mod app;

#[cfg(target_os = "macos")]
fn main() -> Result<(), Box<dyn std::error::Error>> {
    use clap::Parser;
    let args = app::Args::parse();
    let state = app::App::new(&args)?;
    let options = eframe::NativeOptions {
        viewport: eframe::egui::ViewportBuilder::default().with_inner_size([1000.0, 640.0]),
        ..Default::default()
    };
    eframe::run_native("Verion Viewer", options, Box::new(|_| Ok(Box::new(state))))?;
    Ok(())
}

#[cfg(not(target_os = "macos"))]
fn main() {
    eprintln!("viewer requires macOS (Metal)");
    std::process::exit(1);
}
