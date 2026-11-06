//! `verion.Engine`: a GPU session on its own thread, and the `Job`s it runs. The thread owns every
//! GPU object (they are not `Send`); Python only waits on, polls and cancels jobs, with the GIL
//! released while it waits (ADR-0019).

use std::{
    sync::{
        Arc, Condvar, Mutex,
        atomic::{AtomicU64, Ordering},
        mpsc,
    },
    thread,
    time::{Duration, Instant},
};

use numpy::{IntoPyArray, PyArray1, PyArrayMethods};
use pyo3::{exceptions::PyRuntimeError, prelude::*, types::PyDict};
use verion_render::{Control, Frame, Session};

use crate::{
    scene::{Scene, value_err},
    settings::{self, JobSettings},
};

#[cfg(target_os = "macos")]
type Backend = verion_gpu_metal::Renderer;
#[cfg(not(target_os = "macos"))]
type Backend = verion_gpu_vulkan::Renderer;

/// Samples a progress image waits for at least between two reads of the GPU (Final).
const PARTIAL_EVERY: Duration = Duration::from_millis(500);
/// The least time between two published frames of an interactive job.
const PUBLISH_EVERY: Duration = Duration::from_millis(40);

struct Latest {
    version: u64,
    samples: u32,
    width: u32,
    height: u32,
    rgba: Vec<f32>,
}

#[derive(Default)]
struct Stats {
    /// Seconds from the last edit (or the start) to the first image, and to `clean_spp` samples.
    first_frame_s: Option<f64>,
    clean_s: Option<f64>,
    /// Scene edits the job picked up and the seconds the last `update` took.
    edits: u32,
    update_s: f64,
}

enum State {
    Running,
    Done(Box<Result<Frame, String>>),
    Taken,
}

struct Shared {
    ctl: Control,
    latest: Mutex<Option<Latest>>,
    version: AtomicU64,
    state: Mutex<State>,
    done: Condvar,
    stats: Mutex<Stats>,
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|p| p.into_inner())
}

impl Shared {
    fn publish(&self, f: &Frame) {
        let mut rgba = Vec::with_capacity(f.beauty.len() * 4);
        for p in &f.beauty {
            rgba.extend_from_slice(&[p[0], p[1], p[2], 1.0]);
        }
        let version = self.version.fetch_add(1, Ordering::Relaxed) + 1;
        *lock(&self.latest) = Some(Latest {
            version,
            samples: f.samples,
            width: f.width,
            height: f.height,
            rgba,
        });
    }

    fn finish(&self, r: Result<Frame, String>) {
        *lock(&self.state) = State::Done(Box::new(r));
        self.done.notify_all();
    }

    fn cancelled(&self) -> bool {
        self.ctl.cancel.load(Ordering::Relaxed)
    }
}

enum Cmd {
    Start {
        settings: Box<JobSettings>,
        interactive: bool,
        shared: Arc<Shared>,
    },
    Quit,
}

fn run_final(
    session: &mut Session<Backend>,
    js: &JobSettings,
    sh: &Shared,
) -> Result<Frame, String> {
    let t = Instant::now();
    session.update()?;
    lock(&sh.stats).update_s = t.elapsed().as_secs_f64();
    let s = &js.render;
    let mut run = session.begin(s)?;
    let mut last = Instant::now();
    while run.samples() < s.spp && !sh.cancelled() {
        let n = 8.min(s.spp - run.samples());
        session.step(&mut run, n)?;
        sh.ctl.samples.store(run.samples(), Ordering::Relaxed);
        if !run.active() {
            break; // adaptive sampling: every pixel converged
        }
        if last.elapsed() >= PARTIAL_EVERY {
            sh.publish(&session.frame(&mut run, false, false)?);
            last = Instant::now();
        }
    }
    session.frame(&mut run, true, true)
}

/// Accumulates until cancelled, starting over on every scene edit.
fn run_interactive(
    session: &mut Session<Backend>,
    js: &JobSettings,
    sh: &Shared,
) -> Result<Frame, String> {
    let s = &js.render;
    session.update()?;
    let mut run = session.begin(s)?;
    let (mut edit_at, mut last) = (Instant::now(), Instant::now());
    let (mut got_first, mut got_clean, mut dirty) = (false, false, false);
    while !sh.cancelled() {
        if session.stale() {
            let t = Instant::now();
            session.update()?;
            run = session.begin(s)?;
            edit_at = Instant::now();
            (got_first, got_clean) = (false, false);
            let mut st = lock(&sh.stats);
            st.edits += 1;
            st.update_s = t.elapsed().as_secs_f64();
            st.first_frame_s = None;
            st.clean_s = None;
        }
        if run.samples() < s.spp && run.active() {
            // Early frames are 1 sample each so the first image appears at once; later ones double.
            let n = run.samples().clamp(1, 8).min(s.spp - run.samples());
            session.step(&mut run, n)?;
            sh.ctl.samples.store(run.samples(), Ordering::Relaxed);
            dirty = true;
            let clean = run.samples() >= js.clean_spp && !got_clean;
            if last.elapsed() >= PUBLISH_EVERY || !got_first || clean {
                // The GPU work is finished (`accumulate` waits), so this is the image on screen.
                sh.publish(&session.frame(&mut run, false, true)?);
                last = Instant::now();
                dirty = false;
                let mut st = lock(&sh.stats);
                if !got_first {
                    got_first = true;
                    st.first_frame_s = Some(edit_at.elapsed().as_secs_f64());
                }
                if clean {
                    got_clean = true;
                    st.clean_s = Some(edit_at.elapsed().as_secs_f64());
                }
            }
        } else {
            if dirty {
                sh.publish(&session.frame(&mut run, false, true)?);
                dirty = false;
            }
            thread::sleep(Duration::from_millis(5));
        }
    }
    session.frame(&mut run, true, true)
}

fn engine_thread(
    scene: Arc<Mutex<verion_scene::Scene>>,
    rx: mpsc::Receiver<Cmd>,
    init: mpsc::Sender<Result<(), String>>,
) {
    let mut session = match Session::<Backend>::new(scene) {
        Ok(s) => {
            let _ = init.send(Ok(()));
            s
        }
        Err(e) => {
            let _ = init.send(Err(e));
            return;
        }
    };
    for cmd in rx {
        match cmd {
            Cmd::Quit => break,
            Cmd::Start {
                settings,
                interactive,
                shared,
            } => {
                let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                    if interactive {
                        run_interactive(&mut session, &settings, &shared)
                    } else {
                        run_final(&mut session, &settings, &shared)
                    }
                }))
                .unwrap_or_else(|_| Err("the render thread panicked".into()));
                shared.finish(r);
            }
        }
    }
}

#[pyclass(module = "verion")]
pub struct Engine {
    tx: mpsc::Sender<Cmd>,
    current: Mutex<Option<Arc<Shared>>>,
    thread: Mutex<Option<thread::JoinHandle<()>>>,
}

#[pymethods]
impl Engine {
    /// Opens the GPU and uploads `scene`. Later edits to the scene reach the GPU on the next job
    /// (and during an interactive one).
    #[new]
    fn new(py: Python<'_>, scene: &Scene) -> PyResult<Self> {
        let (tx, rx) = mpsc::channel();
        let (init_tx, init_rx) = mpsc::channel();
        let inner = scene.inner.clone();
        let thread = thread::Builder::new()
            .name("verion-engine".into())
            .spawn(move || engine_thread(inner, rx, init_tx))
            .map_err(|e| PyRuntimeError::new_err(e.to_string()))?;
        let ready = py.detach(move || init_rx.recv());
        match ready {
            Ok(Ok(())) => Ok(Self {
                tx,
                current: Mutex::new(None),
                thread: Mutex::new(Some(thread)),
            }),
            Ok(Err(e)) => Err(PyRuntimeError::new_err(e)),
            Err(_) => Err(PyRuntimeError::new_err(
                "the render thread stopped at start",
            )),
        }
    }

    /// Starts a job and returns it. A job still running is cancelled first. `interactive` jobs
    /// keep accumulating (and restart on scene edits) until cancelled; the others stop at `spp`.
    #[pyo3(signature = (settings, interactive = false))]
    fn start(&self, settings: &Bound<'_, PyDict>, interactive: bool) -> PyResult<Job> {
        let settings = Box::new(settings::parse(settings)?);
        let shared = Arc::new(Shared {
            ctl: Control::default(),
            latest: Mutex::new(None),
            version: AtomicU64::new(0),
            state: Mutex::new(State::Running),
            done: Condvar::new(),
            stats: Mutex::default(),
        });
        if let Some(old) = lock(&self.current).replace(shared.clone()) {
            old.ctl.cancel.store(true, Ordering::Relaxed);
        }
        self.tx
            .send(Cmd::Start {
                settings,
                interactive,
                shared: shared.clone(),
            })
            .map_err(|_| PyRuntimeError::new_err("the render thread has stopped"))?;
        Ok(Job { shared })
    }

    /// Cancels the running job, stops the thread and releases the GPU.
    fn close(&self, py: Python<'_>) {
        if let Some(old) = lock(&self.current).take() {
            old.ctl.cancel.store(true, Ordering::Relaxed);
        }
        let _ = self.tx.send(Cmd::Quit);
        if let Some(t) = lock(&self.thread).take() {
            py.detach(|| {
                let _ = t.join();
            });
        }
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        if let Some(old) = lock(&self.current).take() {
            old.ctl.cancel.store(true, Ordering::Relaxed);
        }
        let _ = self.tx.send(Cmd::Quit);
        // Not joined here: Drop can run with the GIL held; the thread ends on its own.
    }
}

#[pyclass(module = "verion")]
pub struct Job {
    shared: Arc<Shared>,
}

fn flat3(v: &[[f32; 3]]) -> Vec<f32> {
    v.iter().flatten().copied().collect()
}

fn put<'py, T: numpy::Element>(
    py: Python<'py>,
    d: &Bound<'py, PyDict>,
    key: &str,
    data: Vec<T>,
    shape: &[usize],
) -> PyResult<()> {
    d.set_item(key, PyArray1::from_vec(py, data).reshape(shape.to_vec())?)
}

/// `(version, samples, image)` of `Job.latest`.
type LatestImage<'py> = (u64, u32, Bound<'py, numpy::PyArrayDyn<f32>>);

#[pymethods]
impl Job {
    /// Samples per pixel taken so far.
    fn samples(&self) -> u32 {
        self.shared.ctl.samples.load(Ordering::Relaxed)
    }

    /// Asks the job to stop at the next dispatch. `result` then returns what was reached.
    fn cancel(&self) {
        self.shared.ctl.cancel.store(true, Ordering::Relaxed);
    }

    fn done(&self) -> bool {
        !matches!(*lock(&self.shared.state), State::Running)
    }

    /// Waits up to `timeout` seconds (forever when `None`) with the GIL released. True when done.
    #[pyo3(signature = (timeout = None))]
    fn wait(&self, py: Python<'_>, timeout: Option<f64>) -> bool {
        py.detach(|| {
            let mut state = lock(&self.shared.state);
            let deadline = timeout.map(|t| Instant::now() + Duration::from_secs_f64(t.max(0.0)));
            while matches!(*state, State::Running) {
                let wait = match deadline {
                    None => Duration::from_secs(3600),
                    Some(d) => match d.checked_duration_since(Instant::now()) {
                        Some(w) => w,
                        None => return false,
                    },
                };
                state = self
                    .shared
                    .done
                    .wait_timeout(state, wait)
                    .unwrap_or_else(|p| p.into_inner())
                    .0;
            }
            true
        })
    }

    /// The newest image the job published and nobody has read yet, as
    /// `(version, samples, array)` with an (height, width, 4) float32 array (first row on top),
    /// or `None` when there is nothing new.
    fn latest<'py>(&self, py: Python<'py>) -> PyResult<Option<LatestImage<'py>>> {
        let Some(l) = lock(&self.shared.latest).take() else {
            return Ok(None);
        };
        let shape = vec![l.height as usize, l.width as usize, 4];
        let a = l.rgba.into_pyarray(py).reshape(shape)?.to_dyn().clone();
        Ok(Some((l.version, l.samples, a)))
    }

    /// Timing the job measured: `first_frame_s` and `clean_s` (from the last scene edit, or the
    /// start, to the first image and to `clean_spp` samples: First Clean Preview), `edits`
    /// (scene edits picked up) and `update_s` (the last `update`).
    fn stats<'py>(&self, py: Python<'py>) -> PyResult<Bound<'py, PyDict>> {
        let st = lock(&self.shared.stats);
        let d = PyDict::new(py);
        d.set_item("first_frame_s", st.first_frame_s)?;
        d.set_item("clean_s", st.clean_s)?;
        d.set_item("edits", st.edits)?;
        d.set_item("update_s", st.update_s)?;
        Ok(d)
    }

    /// Waits for the job and returns its image and AOVs as numpy arrays (first row on top, in the
    /// scene's working space): `combined`, `normal`, `albedo`, `depth`, `object_id`, `material_id`,
    /// `sample_count` (adaptive sampling only), the lighting split (`direct_diffuse`,
    /// `indirect_diffuse`, `specular`, `transmission`, `emission`, `visibility`; Stylized mode or
    /// `lighting_aovs`) and `info`. Can be read once.
    fn result<'py>(&self, py: Python<'py>) -> PyResult<Bound<'py, PyDict>> {
        self.wait(py, None);
        let state = std::mem::replace(&mut *lock(&self.shared.state), State::Taken);
        let f = match state {
            State::Done(r) => r.map_err(PyRuntimeError::new_err)?,
            _ => return Err(value_err("the result was already read")),
        };
        let (h, w) = (f.height as usize, f.width as usize);
        let d = PyDict::new(py);
        put(py, &d, "combined", flat3(&f.beauty), &[h, w, 3])?;
        if !f.normal.is_empty() {
            put(py, &d, "normal", flat3(&f.normal), &[h, w, 3])?;
            put(py, &d, "albedo", flat3(&f.albedo), &[h, w, 3])?;
            put(py, &d, "depth", f.depth, &[h, w])?;
            put(py, &d, "object_id", f.object_id, &[h, w])?;
            put(py, &d, "material_id", f.material_id, &[h, w])?;
        }
        if let Some(c) = f.sample_count {
            put(py, &d, "sample_count", c, &[h, w])?;
        }
        if let Some(l) = &f.lighting {
            put(
                py,
                &d,
                "direct_diffuse",
                flat3(&l.direct_diffuse),
                &[h, w, 3],
            )?;
            put(
                py,
                &d,
                "indirect_diffuse",
                flat3(&l.indirect_diffuse),
                &[h, w, 3],
            )?;
            put(py, &d, "specular", flat3(&l.specular), &[h, w, 3])?;
            put(py, &d, "transmission", flat3(&l.transmission), &[h, w, 3])?;
            put(py, &d, "emission", flat3(&l.emission), &[h, w, 3])?;
            put(py, &d, "visibility", l.visibility.clone(), &[h, w])?;
        }
        let info = PyDict::new(py);
        info.set_item("samples", f.samples)?;
        info.set_item("physical", f.physical)?;
        info.set_item("denoise_s", f.times.denoise_s)?;
        info.set_item("stylize_s", f.times.stylize_s)?;
        d.set_item("info", info)?;
        Ok(d)
    }
}
