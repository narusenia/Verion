import bpy
import numpy as np

from . import native
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
                    self._show(latest[2], layer)
            result = job.result()
        except RuntimeError as e:
            self.report({"ERROR"}, str(e))
            return
        finally:
            engine.close()
        self._write(result, layer, width, height)
        self.update_progress(1.0)

    def _show(self, rgba, layer):
        """Progress image: the Combined pass only."""
        h, w = rgba.shape[:2]
        res = self.begin_result(0, 0, w, h, layer=layer.name)
        res.layers[0].passes["Combined"].rect.foreach_set(np.ascontiguousarray(rgba[::-1]).ravel())
        self.end_result(res, highlight=True)

    def _write(self, result, layer, width, height):
        res = self.begin_result(0, 0, width, height, layer=layer.name)
        passes = res.layers[0].passes

        def put(name, arr):
            # Blender stores the bottom row first.
            passes[name].rect.foreach_set(np.ascontiguousarray(arr[::-1], dtype=np.float32).ravel())

        c = result["combined"]
        put("Combined", np.concatenate([c, np.ones(c.shape[:2] + (1,), np.float32)], axis=2))
        for name, _chan, n, key, flag in PASSES:
            if name in passes and key in result:
                a = result[key]
                put(name, a.astype(np.float32) if a.ndim == 3 else a.astype(np.float32)[..., None] if n == 1 else a)
        self.end_result(res)
