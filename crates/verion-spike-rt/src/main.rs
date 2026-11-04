//! M1 item 1 spike entry point. Metal exists only on macOS, so other targets build an empty stub.

#[cfg(target_os = "macos")]
mod macos;

#[cfg(target_os = "macos")]
fn main() {
    macos::run();
}

#[cfg(not(target_os = "macos"))]
fn main() {
    eprintln!("verion-spike-rt requires macOS (Metal)");
}
