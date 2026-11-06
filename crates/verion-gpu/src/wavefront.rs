//! The shape of the wavefront's GPU buffers (REQ-GPU-005), shared by the backends. The layout is
//! mirrored in `shaders/include/wf_state.slang`.

use crate::pack::MAX_DEPTH;

/// Path-state words per path.
pub const BASE_WORDS: usize = 16;
/// More words per path when the lighting AOVs are on.
pub const SPLIT_WORDS: usize = 17;
/// Threads per group of the extend and shade kernels (`WF_GROUP`).
pub const GROUP: u32 = 64;

/// Byte sizes of the buffers one accumulation's wavefront needs.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Sizes {
    pub state: usize,
    /// Closest-hit records: 4 words per path.
    pub hits: usize,
    /// Each of the two path queues.
    pub queue: usize,
    /// Live paths per depth.
    pub counts: usize,
    /// Indirect dispatch arguments, 3 words per depth.
    pub args: usize,
}

impl Sizes {
    pub fn new(paths: usize, lighting: bool) -> Self {
        let words = BASE_WORDS + if lighting { SPLIT_WORDS } else { 0 };
        let depth = MAX_DEPTH as usize;
        Self {
            state: paths * words * 4,
            hits: paths * 16,
            queue: paths * 4,
            counts: (depth + 1) * 4,
            args: depth * 12,
        }
    }

    pub fn total(&self) -> usize {
        self.state + self.hits + 2 * self.queue + self.counts + self.args
    }
}

/// Which stages one bounce depth runs, in order: adaptive sampling first selects the pixels at
/// depth 0, then every depth sizes its dispatch, finds the closest hits and shades.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Stage {
    Select,
    Args,
    Extend,
    Shade,
}

impl Stage {
    pub fn of_depth(depth: usize, adaptive: bool) -> impl Iterator<Item = Stage> {
        (depth == 0 && adaptive)
            .then_some(Stage::Select)
            .into_iter()
            .chain([Stage::Args, Stage::Extend, Stage::Shade])
    }

    /// Stage-timing bucket: 0 is extend (with its dispatch sizing), 1 shade.
    pub fn timing_slot(self) -> usize {
        usize::from(self == Stage::Shade)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sizes_follow_the_path_count() {
        let s = Sizes::new(100, false);
        assert_eq!(s.state, 100 * 16 * 4);
        assert_eq!(Sizes::new(100, true).state, 100 * 33 * 4);
        assert_eq!(s.total(), 6400 + 1600 + 800 + 36 + 96);
    }

    #[test]
    fn adaptive_sampling_adds_select_at_depth_zero_only() {
        assert_eq!(Stage::of_depth(0, true).count(), 4);
        assert_eq!(Stage::of_depth(0, false).count(), 3);
        assert_eq!(Stage::of_depth(3, true).count(), 3);
    }
}
