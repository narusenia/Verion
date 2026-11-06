import bpy

from . import compat, native


class VerionPanel:
    bl_space_type = "PROPERTIES"
    bl_region_type = "WINDOW"
    bl_context = "render"
    COMPAT_ENGINES = {"VERION"}

    @classmethod
    def poll(cls, context):
        return context.engine in cls.COMPAT_ENGINES


class VERION_PT_status(VerionPanel, bpy.types.Panel):
    bl_label = "Verion"

    @classmethod
    def poll(cls, context):
        return context.engine in cls.COMPAT_ENGINES and not native.available()[0]

    def draw(self, context):
        self.layout.alert = True
        self.layout.label(text="Native extension unavailable", icon="ERROR")
        self.layout.label(text=native.available()[1])


class VERION_PT_mode(VerionPanel, bpy.types.Panel):
    bl_label = "Mode"

    def draw(self, context):
        s = context.scene.verion
        col = self.layout.column()
        col.prop(s, "mode", expand=True)
        if s.mode != "REFERENCE":
            col.label(text="Output is marked non-physical", icon="INFO")


class VERION_PT_sampling(VerionPanel, bpy.types.Panel):
    bl_label = "Sampling"

    def draw(self, context):
        s = context.scene.verion
        col = self.layout.column()
        col.prop(s, "samples")
        col.prop(s, "integrator")
        col.prop(s, "multiscatter")


class VERION_PT_viewport(VerionPanel, bpy.types.Panel):
    bl_label = "Viewport"
    bl_parent_id = "VERION_PT_sampling"

    def draw(self, context):
        s = context.scene.verion
        col = self.layout.column()
        col.prop(s, "viewport_samples")
        col.prop(s, "viewport_scale")
        col.prop(s, "viewport_restir")
        col.prop(s, "clean_samples")


class VERION_PT_adaptive(VerionPanel, bpy.types.Panel):
    bl_label = "Adaptive Sampling"
    bl_parent_id = "VERION_PT_sampling"
    bl_options = {"DEFAULT_CLOSED"}

    def draw_header(self, context):
        self.layout.prop(context.scene.verion, "adaptive", text="")

    def draw(self, context):
        s = context.scene.verion
        col = self.layout.column()
        col.active = s.adaptive
        col.prop(s, "adaptive_threshold")
        col.prop(s, "adaptive_min_samples")


class VERION_PT_restir(VerionPanel, bpy.types.Panel):
    bl_label = "ReSTIR"
    bl_parent_id = "VERION_PT_sampling"
    bl_options = {"DEFAULT_CLOSED"}

    def draw_header(self, context):
        self.layout.prop(context.scene.verion, "restir", text="")

    def draw(self, context):
        s = context.scene.verion
        col = self.layout.column()
        col.active = s.restir
        col.prop(s, "restir_gi")
        col.prop(s, "restir_candidates")
        col.prop(s, "restir_history")


class VERION_PT_denoise(VerionPanel, bpy.types.Panel):
    bl_label = "Denoise"
    bl_options = {"DEFAULT_CLOSED"}

    def draw_header(self, context):
        self.layout.prop(context.scene.verion, "denoise", text="")

    def draw(self, context):
        s = context.scene.verion
        col = self.layout.column()
        col.active = s.denoise
        col.prop(s, "denoise_device")
        if s.mode == "STYLIZED":
            col.prop(s, "denoise_stage")


classes = (
    VERION_PT_status,
    VERION_PT_mode,
    VERION_PT_sampling,
    VERION_PT_viewport,
    VERION_PT_adaptive,
    VERION_PT_restir,
    VERION_PT_denoise,
)


def register():
    for c in classes:
        bpy.utils.register_class(c)
    for p in compat.panels_to_enable():
        p.COMPAT_ENGINES.add("VERION")


def unregister():
    for p in compat.panels_to_enable():
        p.COMPAT_ENGINES.discard("VERION")
    for c in reversed(classes):
        bpy.utils.unregister_class(c)
