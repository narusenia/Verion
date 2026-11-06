import bpy
from bpy.props import BoolProperty, EnumProperty, FloatProperty, IntProperty, PointerProperty

MODES = [
    ("REFERENCE", "Reference", "Physical path tracing only; no approximation or stylization"),
    ("INTERACTIVE", "Interactive", "ReSTIR for a faster clean image (not physical)"),
    ("STYLIZED", "Stylized", "Stylization Pass on the first hit (not physical)"),
]


class VerionSceneSettings(bpy.types.PropertyGroup):
    mode: EnumProperty(name="Mode", items=MODES, default="REFERENCE")
    samples: IntProperty(name="Samples", description="Samples per pixel of a final render", default=64, min=1, soft_max=4096)
    viewport_samples: IntProperty(name="Viewport Samples", default=256, min=1, soft_max=4096)
    viewport_scale: EnumProperty(
        name="Viewport Resolution",
        items=[("1.0", "100%", ""), ("0.5", "50%", ""), ("0.25", "25%", "")],
        default="1.0",
    )
    clean_samples: IntProperty(
        name="Clean Preview Samples",
        description="Samples after which a viewport frame counts as a clean preview (reported in the status bar)",
        default=16, min=1,
    )
    viewport_restir: BoolProperty(
        name="Viewport ReSTIR",
        description="In Reference mode the viewport uses Interactive (ReSTIR); turn off for a physical viewport",
        default=True,
    )
    bake_size: EnumProperty(
        name="Bake Size",
        description="Texture size for procedural material inputs, which are baked with Cycles",
        items=[("512", "512", ""), ("1024", "1024", ""), ("2048", "2048", ""), ("4096", "4096", "")],
        default="1024",
    )
    integrator: EnumProperty(
        name="Integrator",
        items=[("MEGAKERNEL", "Megakernel", "One thread per path"), ("WAVEFRONT", "Wavefront", "One kernel per stage")],
        default="MEGAKERNEL",
    )
    multiscatter: BoolProperty(name="Multiple Scattering", description="Energy compensation for rough GGX", default=True)

    adaptive: BoolProperty(name="Adaptive Sampling", description="Stop converged pixels early (not physical)", default=False)
    adaptive_threshold: FloatProperty(name="Noise Threshold", default=0.02, min=0.0, precision=4)
    adaptive_min_samples: IntProperty(name="Min Samples", default=16, min=1)

    restir: BoolProperty(name="ReSTIR", description="ReSTIR DI/GI in Stylized mode (not physical)", default=False)
    restir_gi: BoolProperty(name="ReSTIR GI", default=True)
    restir_candidates: IntProperty(name="Candidates", default=4, min=1)
    restir_history: IntProperty(name="History", default=4, min=1)

    denoise: BoolProperty(name="Denoise", description="Intel Open Image Denoise (not physical)", default=False)
    viewport_denoise: BoolProperty(
        name="Viewport Denoise",
        description="Denoise the viewport image with Open Image Denoise (not physical). Uses the device chosen below",
        default=False,
    )
    denoise_device: EnumProperty(
        name="Device",
        items=[
            ("CPU", "CPU", ""),
            ("METAL", "Metal", "Apple GPU, through the OIDN module that ships with Blender"),
            ("CUDA", "CUDA", "NVIDIA GPU, through the OIDN module that ships with Blender"),
            ("HIP", "HIP", "AMD GPU, through the OIDN module that ships with Blender"),
        ],
        default="CPU",
    )
    denoise_stage: EnumProperty(
        name="Stylized Stage",
        items=[("INPUT", "Input", "Denoise the lighting before the Toon bands are cut"), ("OUTPUT", "Output", "Denoise the stylized image")],
        default="INPUT",
    )

    def native_settings(self, width, height, final):
        """The settings dict of `verion.Engine.start`."""
        mode = self.mode
        if not final and mode == "REFERENCE" and self.viewport_restir:
            mode = "INTERACTIVE"
        d = {
            "mode": mode.lower(),
            "width": width,
            "height": height,
            "spp": self.samples if final else self.viewport_samples,
            "integrator": self.integrator.lower(),
            "multiscatter": self.multiscatter,
            "clean_spp": self.clean_samples,
        }
        if final and self.adaptive:
            d["adaptive"] = {"threshold": self.adaptive_threshold, "min_spp": self.adaptive_min_samples}
        if self.restir and mode != "REFERENCE":
            d["restir"] = {"gi": self.restir_gi, "candidates": self.restir_candidates, "history": self.restir_history}
        if self.denoise if final else self.viewport_denoise:
            d["denoise"] = {"device": self.denoise_device.lower(), "stage": self.denoise_stage.lower()}
        return d


classes = (VerionSceneSettings,)


def register():
    for c in classes:
        bpy.utils.register_class(c)
    bpy.types.Scene.verion = PointerProperty(type=VerionSceneSettings)


def unregister():
    del bpy.types.Scene.verion
    for c in reversed(classes):
        bpy.utils.unregister_class(c)
