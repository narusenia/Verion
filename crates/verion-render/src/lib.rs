//! The render pipeline the front ends share (the CLI, the Python extension and so on): a GPU
//! session that renders a scene to frames (`session`), and the post-processing that turns the
//! GPU's sums into the output image (`post`). Keeps the DCC adapters thin (REQ-DCC-001).

mod post;
mod session;

pub use post::{DenoiseStage, Mode, PostInput, PostTimes, finish};
pub use session::{Control, Denoise, Frame, Run, Session, Settings};
pub use verion_denoise::Device as DenoiseDevice;
