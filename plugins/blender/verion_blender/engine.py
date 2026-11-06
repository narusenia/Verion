import bpy
import gpu
from gpu_extras.batch import batch_for_shader
import numpy as np

from . import compat, cryptomatte, native
from .sync import Sync
from .viewport import View, Viewport


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
    # Blender's own shader nodes (Principled, ...): without this the Shader Editor is hidden for the engine.
    bl_use_shading_nodes_custom = False
    bl_use_postprocess = True

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.session = None
        self.viewport = None
        self.draw_data = None

    def __del__(self):
        try:
            self._close()
        except ReferenceError:
            pass  # the engine struct is already gone

    def _close(self):
        vp = getattr(self, "viewport", None)
        if vp is not None:
            vp.close()
            self.viewport = None

    def _warn(self, level, msg):
        self.report({level}, msg)

    # -- passes -----------------------------------------------------------------------------------

    def update_render_passes(self, scene=None, renderlayer=None):
        self.register_pass(scene, renderlayer, "Combined", 4, "RGBA", "COLOR")
        for kind, flag in cryptomatte.KINDS:
            if getattr(renderlayer, flag, False):
                self.register_pass(scene, renderlayer, f"Crypto{kind}00", 4, "RGBA", "COLOR")
        for name, chan, n, _key, flag in PASSES:
            if getattr(renderlayer, flag, False):
                self.register_pass(scene, renderlayer, name, n, chan, "VALUE" if n == 1 else "VECTOR" if chan == "XYZ" else "COLOR")

    # -- viewport ----------------------------------------------------------------------------------

    def view_update(self, context, depsgraph):
        try:
            if self.viewport is None:
                self.viewport = Viewport(native.load(), self._warn)
            view = View.from_region(context.region_data, context.region)
            self.viewport.update(depsgraph, view, depsgraph.scene.verion)
        except Exception as e:
            import traceback

            traceback.print_exc()
            self.report({"ERROR"}, f"Verion: {e}")
            return
        self.tag_redraw()

    def view_draw(self, context, depsgraph):
        vp = self.viewport
        if vp is None:
            return
        scene = depsgraph.scene
        view = View.from_region(context.region_data, context.region)
        vp.set_view(view, scene.verion)
        if vp.poll() is not None or self.draw_data is None:
            self.draw_data = _upload(vp.image)
        self.update_stats("Verion", vp.status())
        if self.draw_data is not None:
            gpu.state.blend_set("ALPHA_PREMULT")
            self.bind_display_space_shader(scene)
            _draw(self.draw_data, context.region)
            self.unbind_display_space_shader()
            gpu.state.blend_set("NONE")
        if vp.job is not None and not vp.job.done():
            self.tag_redraw()  # more frames are coming

    # -- final render -----------------------------------------------------------------------------

    def render(self, depsgraph):
        try:
            self._render(depsgraph)
        except Exception as e:  # an exception here takes Blender down in background mode
            import traceback

            traceback.print_exc()
            self.report({"ERROR"}, f"Verion: {e}")

    def _render(self, depsgraph):
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
        transparent = scene.render.film_transparent
        vscene.set_transparent_background(transparent)
        self.update_stats("", "Verion: starting the GPU")
        engine = nat.Engine(vscene)
        try:
            cfg = settings.native_settings(width, height, final=True)
            layer = depsgraph.view_layer
            need = [p for p in PASSES if getattr(layer, p[4], False)]
            if need and cfg["mode"] != "stylized":
                cfg["lighting_aovs"] = any(p[3] in {"direct_diffuse", "indirect_diffuse", "emission"} for p in need)
            if transparent and sync.catcher_ids():
                cfg["lighting_aovs"] = True  # the shadow catcher reads the visibility
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
        self._write(result, layer, scene, width, height, sync, transparent)
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

    def _write(self, result, layer, scene, width, height, sync=None, transparent=False):
        x0, y0, x1, y1 = self._region(scene, width, height)
        # Blender places the border region itself: tile coordinates start at its corner.
        res = self.begin_result(0, 0, x1 - x0, y1 - y0, layer=layer.name)
        passes = res.layers[0].passes
        # Row 0 of our arrays is the top of the image; Blender's is the bottom.
        top = height - y1
        crypto = {}
        if sync is not None:
            objects, mats, assets = sync.id_names()
            for kind, flag in cryptomatte.KINDS:
                if f"Crypto{kind}00" in passes:
                    names = {"Object": objects, "Material": mats, "Asset": assets}[kind]
                    ids = result["material_id"] if kind == "Material" else result["object_id"]
                    crypto[f"Crypto{kind}00"] = (4, cryptomatte.layer_pass(ids, names), kind, names)
        arrays = pass_arrays(result, set(passes.keys()), transparent, sync.catcher_ids() if sync else ())
        arrays.update({k: v[:2] for k, v in crypto.items()})
        for name, (_n, arr) in arrays.items():
            crop = arr[top : top + (y1 - y0), x0:x1]
            passes[name].rect.foreach_set(np.ascontiguousarray(crop[::-1], dtype=np.float32).ravel())
        self.end_result(res)
        # The stamp fields reach the saved image (EXR header) only when added to the finished result.
        final = self.get_result()
        fields = stamp_fields(scene.verion, result["info"])
        for _name, (_n, _a, kind, names) in crypto.items():
            fields.update(cryptomatte.metadata(layer.name, kind, names))
        for key, value in fields.items():
            compat.stamp_field(final, scene, key, value)


def combined_rgba(result, transparent=False, catchers=()):
    """(H, W, 4) Combined. A transparent film takes alpha from the coverage of the scene (the sky was
    already dropped for camera rays). A shadow catcher shows black with the shadow as alpha: one minus
    the share of direct light that reaches it (the Visibility AOV)."""
    c = result["combined"]
    a = np.ones(c.shape[:2], np.float32)
    if transparent and "coverage" in result:
        a = np.asarray(result["coverage"], np.float32)
        if len(catchers) and "visibility" in result:
            m = np.isin(result["object_id"], np.asarray(list(catchers)) + 1)
            shadow = 1.0 - np.clip(result["visibility"], 0.0, 1.0)
            c = np.where(m[..., None], 0.0, c)
            a = np.where(m, shadow * a, a)
    return np.concatenate([c, a[..., None]], axis=2).astype(np.float32)


def pass_arrays(result, available, transparent=False, catchers=()):
    """{Blender pass name: (channels, array (H, W, channels))} for the passes in `available`."""
    out = {"Combined": (4, combined_rgba(result, transparent, catchers))}
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


def _upload(image):
    """A float RGBA texture of a viewport frame `(version, samples, (h, w, 4) array)`."""
    if image is None:
        return None
    rgba = np.ascontiguousarray(image[2][::-1], dtype=np.float32)  # texture row 0 is the bottom
    h, w = rgba.shape[:2]
    buf = gpu.types.Buffer("FLOAT", w * h * 4, rgba.ravel())
    return gpu.types.GPUTexture((w, h), format="RGBA32F", data=buf)


def _draw(texture, region):
    """Draws the texture over the whole region (it is stretched when rendered at a lower resolution)."""
    shader = gpu.shader.from_builtin("IMAGE")
    coords = ((0, 0), (1, 0), (1, 1), (0, 1))
    batch = batch_for_shader(shader, "TRI_FAN", {"pos": coords, "texCoord": coords})
    with gpu.matrix.push_pop():
        gpu.matrix.translate((0, 0))
        gpu.matrix.scale((region.width, region.height))
        shader.bind()
        shader.uniform_sampler("image", texture)
        batch.draw(shader)
