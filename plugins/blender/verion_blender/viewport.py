"""Viewport render (IPR): one interactive native job that follows the depsgraph (REQ-DCC-002).

The logic is kept apart from `RenderEngine` so it can be driven without a 3D view: a view is
described by its camera-to-world matrix and its projection (`View`), which the engine reads from
`context.region_data`.
"""
import math
import time

import numpy as np

from . import convert
from .sync import Sync

# How far a perspective camera stands back to stand in for an orthographic view, in view extents.
ORTHO_DISTANCE = 2000.0
# While the camera moves the job renders at this fraction of the size; it returns to full size
# after the view has been still for SETTLE_S seconds.
MOVE_SCALE = 0.25
SETTLE_S = 0.3


class View:
    """A 3D view: camera-to-world (Blender, 4x4), the window (projection) matrix and the region size."""

    def __init__(self, camera_to_world, window, width, height):
        self.camera_to_world = np.array(camera_to_world, dtype=np.float64)
        self.window = np.array(window, dtype=np.float64)
        self.width, self.height = int(width), int(height)

    @classmethod
    def from_region(cls, region_data, region):
        return cls(region_data.view_matrix.inverted(), region_data.window_matrix, region.width, region.height)

    @property
    def orthographic(self):
        return abs(self.window[3][3] - 1.0) < 1e-6 and abs(self.window[3][2]) < 1e-6

    def camera(self):
        """(camera-to-world 3x4 in Verion space, vertical fov, shift) of the view."""
        m = self.camera_to_world.copy()
        p = self.window
        if self.orthographic:
            # Half the visible height in view units is 1 / P11; a far perspective camera with the
            # same visible height there is close enough to orthographic (the error is ~1/2000).
            half_h = 1.0 / p[1][1]
            d = half_h * ORTHO_DISTANCE
            fwd = -m[:3, 2] / np.linalg.norm(m[:3, 2])
            m[:3, 3] -= fwd * d
            fov = 2.0 * math.atan(half_h / d)
            shift = (p[0][2] * 0.0, p[1][2] * 0.0)  # ortho window offsets are in view units: not supported
        else:
            fov = 2.0 * math.atan(1.0 / p[1][1])
            shift = (float(p[0][2]), float(p[1][2]))
        return convert.matrix(m), fov, shift


def settings_key(settings):
    """What restarts the job when it changes."""
    return tuple(
        getattr(settings, k) for k in (
            "mode", "viewport_samples", "viewport_restir", "integrator", "multiscatter", "restir",
            "restir_gi", "restir_candidates", "restir_history", "clean_samples", "viewport_scale",
            "viewport_denoise", "denoise_device", "denoise_stage",
        )
    )


class Viewport:
    def __init__(self, native, report=None):
        self.native = native
        self.report = report or (lambda level, msg: print(f"{level}: {msg}"))
        self.sync = None
        self.engine = None
        self.job = None
        self.key = None
        self.size = None        # the full render size; the job renders smaller while the camera moves
        self.moving = False
        self.last_move = 0.0
        self.view = None
        self.image = None       # latest (version, samples, rgba array)
        self.stats = {}
        self.failed = False

    # -- lifecycle --------------------------------------------------------------------------------

    def close(self):
        if self.job is not None:
            self.job.cancel()
        if self.engine is not None:
            self.engine.close()
        self.job = self.engine = self.sync = None

    def _render_size(self, settings, view):
        s = float(settings.viewport_scale)
        return max(1, int(view.width * s)), max(1, int(view.height * s))

    def _build(self, depsgraph, view, settings):
        self.close()
        self.sync = Sync(self.native, self.report)
        w, h = self._render_size(settings, view)
        scene = self.sync.build(depsgraph, w, h, with_camera=False)
        self._apply_view(view)
        self.engine = self.native.Engine(scene)
        self._start(settings, w, h)

    def _start(self, settings, w, h, scale=1.0):
        cfg = settings.native_settings(max(1, int(w * scale)), max(1, int(h * scale)), final=False)
        self.job = self.engine.start(cfg, interactive=True)  # replaces a running job
        self.failed = False
        self.key = settings_key(settings)
        self.size = (w, h)
        self.moving = scale < 1.0

    def _apply_view(self, view):
        t, fov, shift = view.camera()
        self.sync.scene.set_camera(t, fov, 10.0, 0.0, shift)
        self.view = view

    # -- the engine's callbacks --------------------------------------------------------------------

    def update(self, depsgraph, view, settings):
        """`view_update`: follows the depsgraph and the view. Returns True when the image will change."""
        w, h = self._render_size(settings, view)
        if self.engine is None or self.key != settings_key(settings) or self.size != (w, h):
            self._build(depsgraph, view, settings)
            return True
        if not self.sync.update(depsgraph):
            self._build(depsgraph, view, settings)  # the structure changed: rebuild (no removal in the IR)
            return True
        self._apply_view(view)
        return True

    def set_view(self, view, settings):
        """`view_draw` saw the user move the view: only the camera changes."""
        if self.engine is not None and self._view_changed(view):
            self._apply_view(view)
            self.last_move = time.monotonic()
            if settings.viewport_fast_move and not self.moving:
                self._start(settings, *self.size, scale=MOVE_SCALE)

    def settle(self, settings):
        """True when the view has been still long enough: the job is restarted at full size."""
        if self.moving and time.monotonic() - self.last_move > SETTLE_S:
            self._start(settings, *self.size)
            return True
        return False

    def resized(self, view, settings):
        """True when the region no longer matches the size the job renders at."""
        return self.size is not None and self.size != self._render_size(settings, view)

    def _view_changed(self, view):
        v = self.view
        return v is None or not (np.allclose(v.camera_to_world, view.camera_to_world) and np.allclose(v.window, view.window))

    def poll(self):
        """The newest unread frame `(version, samples, (h, w, 4) array)`, or None."""
        if self.job is None:
            return None
        got = self.job.latest()
        if got is not None:
            self.image = got
        self.stats = self.job.stats()
        if self.job.done() and not self.failed:  # an interactive job only ends on an error
            self.failed = True
            try:
                self.job.result()
            except RuntimeError as e:
                self.report("ERROR", f"Verion: the viewport job stopped: {e}")
        return got

    def status(self):
        if self.job is None:
            return ""
        s = self.job.samples()
        clean = self.stats.get("clean_s")
        text = f"{s} spp"
        if clean is not None:
            text += f" | clean preview {clean:.2f} s"
        return text
