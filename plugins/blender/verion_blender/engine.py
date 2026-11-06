import bpy
import numpy as np

from . import compat, native
from .sync import Sync


def render_size(scene):
    rd = scene.render
    s = rd.resolution_percentage / 100.0
    return max(1, int(rd.resolution_x * s)), max(1, int(rd.resolution_y * s))


# (Blender pass name, channels, key in the native result, flag on the view layer or None)
PASSES = [
    ("Depth", "Z", 1, "depth", "use_pass_z"),
    ("Normal", "XYZ", 3, "normal", "use_pass_normal"),
    ("DiffCol", "RGB", 3, "albedo", "use_pass_diffuse_color"),
    ("Emit", "RGB", 3, "emission", "use_pass_emit"),
    ("DiffDir", "RGB", 3, "direct_diffuse", "use_pass_diffuse_direct"),
    ("DiffInd", "RGB", 3, "indirect_diffuse", "use_pass_diffuse_indirect"),
    ("IndexOB", "X", 1, "object_id", "use_pass_object_index"),
    ("IndexMA", "X", 1, "material_id", "use_pass_material_index"),
]


class VerionRenderEngine(bpy.types.RenderEngine):
    bl_idname = "VERION"
    bl_label = "Verion"
    bl_use_preview = False
    bl_use_postprocess = True

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.session = None

    def __del__(self):
        try:
            self._close()
        except ReferenceError:
            pass  # the engine struct is already gone

    def _close(self):
        s = getattr(self, "session", None)
        if s is not None:
            s["engine"].close()
            self.session = None

    def _warn(self, level, msg):
        self.report({level}, msg)

    # -- passes -----------------------------------------------------------------------------------

    def update_render_passes(self, scene=None, renderlayer=None):
        self.register_pass(scene, renderlayer, "Combined", 4, "RGBA", "COLOR")
        for name, chan, n, _key, flag in PASSES:
            if getattr(renderlayer, flag, False):
                self.register_pass(scene, renderlayer, name, n, chan, "VALUE" if n == 1 else "VECTOR" if chan == "XYZ" else "COLOR")

    # -- final render -----------------------------------------------------------------------------

    def render(self, depsgraph):
        scene = depsgraph.scene
        settings = scene.verion
        width, height = render_size(scene)
        try:
            nat = native.load()
        except native.NativeError as e:
            self.report({"ERROR"}, str(e))
            return
        self.update_stats("", "Verion: building the scene")
        sync = Sync(nat, self._warn)
        vscene = sync.build(depsgraph, width, height)
        self.update_stats("", "Verion: starting the GPU")
        engine = nat.Engine(vscene)
        try:
            cfg = settings.native_settings(width, height, final=True)
            layer = depsgraph.view_layer
            need = [p for p in PASSES if getattr(layer, p[4], False)]
            if need and cfg["mode"] != "stylized":
                cfg["lighting_aovs"] = any(p[3] in {"direct_diffuse", "indirect_diffuse", "emission"} for p in need)
            job = engine.start(cfg)
            total = cfg["spp"]
            while not job.wait(0.1):
                if self.test_break():
                    job.cancel()
                done = job.samples()
                self.update_progress(min(done / total, 1.0))
                self.update_stats("", f"Verion: {done}/{total} samples")
                latest = job.latest()
                if latest is not None:
                    self._show(latest[2], layer, scene)
            result = job.result()
        except RuntimeError as e:
            self.report({"ERROR"}, str(e))
            return
        finally:
            engine.close()
        self._write(result, layer, scene, width, height)
        self.update_progress(1.0)

    @staticmethod
    def _region(scene, width, height):
        """(x0, y0, x1, y1) of the render border from the bottom left, or the whole frame."""
        rd = scene.render
        if not rd.use_border:
            return 0, 0, width, height
        x0, y0 = int(rd.border_min_x * width), int(rd.border_min_y * height)
        x1, y1 = max(int(rd.border_max_x * width), x0 + 1), max(int(rd.border_max_y * height), y0 + 1)
        return x0, y0, x1, y1

    def _show(self, rgba, layer, scene):
        """Progress image: the Combined pass only."""
        height, width = rgba.shape[:2]
        x0, y0, x1, y1 = self._region(scene, width, height)
        crop = rgba[height - y1 : height - y0, x0:x1]
        res = self.begin_result(0, 0, x1 - x0, y1 - y0, layer=layer.name)
        res.layers[0].passes["Combined"].rect.foreach_set(np.ascontiguousarray(crop[::-1]).ravel())
        self.end_result(res, highlight=True)

    def _write(self, result, layer, scene, width, height):
        x0, y0, x1, y1 = self._region(scene, width, height)
        # Blender places the border region itself: tile coordinates start at its corner.
        res = self.begin_result(0, 0, x1 - x0, y1 - y0, layer=layer.name)
        passes = res.layers[0].passes
        # Row 0 of our arrays is the top of the image; Blender's is the bottom.
        top = height - y1
        for name, (_n, arr) in pass_arrays(result, set(passes.keys())).items():
            crop = arr[top : top + (y1 - y0), x0:x1]
            passes[name].rect.foreach_set(np.ascontiguousarray(crop[::-1], dtype=np.float32).ravel())
        self.end_result(res)
        # The stamp fields reach the saved image (EXR header) only when added to the finished result.
        final = self.get_result()
        for key, value in stamp_fields(scene.verion, result["info"]).items():
            compat.stamp_field(final, scene, key, value)


def pass_arrays(result, available):
    """{Blender pass name: (channels, array (H, W, channels))} for the passes in `available`."""
    c = result["combined"]
    out = {"Combined": (4, np.concatenate([c, np.ones(c.shape[:2] + (1,), np.float32)], axis=2))}
    for name, _chan, n, key, _flag in PASSES:
        if name in available and key in result:
            a = np.asarray(result[key], dtype=np.float32)
            out[name] = (n, a if a.ndim == 3 else a[..., None])
    return {k: v for k, v in out.items() if k in available}


def stamp_fields(settings, info):
    """Metadata stored in the saved image (EXR header): non-physical output is marked (ADR-0008)."""
    f = {
        "Verion Physical": "true" if info["physical"] else "false",
        "Verion Mode": settings.mode.lower(),
        "Verion Samples": str(info["samples"]),
    }
    if settings.adaptive:
        f["Verion Adaptive Threshold"] = str(settings.adaptive_threshold)
    if settings.restir or settings.mode == "INTERACTIVE":
        f["Verion ReSTIR"] = "di+gi" if settings.restir_gi or settings.mode == "INTERACTIVE" else "di"
    if settings.denoise:
        f["Verion Denoiser"] = "oidn"
    return f
