"""Stylization settings of a Blender material and world (REQ-DCC-001, REQ-STY).

The properties live on `Material.verion_style` and `World.verion_style` and become the JSON of the
glTF extension `VERION_materials_stylization` (`docs/specifications/gltf-stylization-extension.md`),
which the native module parses and validates, so Blender and glTF share one schema and one set of
rules. Edited in the Material and World property tabs.
"""
import json

import bpy
from bpy.props import (BoolProperty, CollectionProperty, EnumProperty, FloatProperty, FloatVectorProperty,
                       PointerProperty)


def _color(name, default=(1.0, 1.0, 1.0)):
    return FloatVectorProperty(name=name, subtype="COLOR", size=3, min=0.0, soft_max=1.0, default=default)


def _unit(name, default=0.0, description=""):
    return FloatProperty(name=name, description=description, default=default, min=0.0, max=1.0, subtype="FACTOR")


class VerionBand(bpy.types.PropertyGroup):
    threshold: _unit("Threshold", description="Where this band starts (the first band's start is ignored)")
    color: _color("Color")


class VerionRamp(bpy.types.PropertyGroup):
    bands: CollectionProperty(type=VerionBand)
    feather: _unit("Feather", description="Softness of each band edge; 0 is a hard step")
    light_wrap: _unit("Light Wrap", description="How far light wraps past the terminator")

    def to_json(self):
        bands = list(self.bands)
        return {
            "thresholds": [b.threshold for b in bands[1:]],
            "feather": self.feather,
            "palette": [list(b.color) for b in bands],
            "lightWrap": self.light_wrap,
        }

    def reset(self, count=3):
        self.bands.clear()
        for i in range(count):
            b = self.bands.add()
            b.threshold = i / count
            v = 0.35 + 0.65 * i / max(count - 1, 1)
            b.color = (v, v, v)


class VerionShadowTone(bpy.types.PropertyGroup):
    hue_shift: FloatProperty(name="Hue Shift", description="Degrees", default=0.0, min=-180.0, max=180.0)
    saturation: FloatProperty(name="Saturation", default=1.0, min=0.0, soft_max=2.0)
    value: FloatProperty(name="Value", default=1.0, min=0.0, soft_max=2.0)

    def to_json(self):
        return {"hueShift": self.hue_shift, "saturation": self.saturation, "value": self.value}


class VerionStyle(bpy.types.PropertyGroup):
    enabled: BoolProperty(name="Stylization", description="Send this material's Stylization layers to Verion", default=False)

    # hybridSurface
    diffuse: _unit("Diffuse", description="0 is physical, 1 is fully Toon")
    specular: _unit("Specular")
    gi: _unit("GI", description="Flatten indirect diffuse")
    shadow: _unit("Shadow")
    outline: _unit("Outline", description="Opacity of the outline")
    reflection: _unit("Reflection", description="How much indirect specular (reflections) is removed")

    use_toon: BoolProperty(name="Toon Ramp", default=False)
    toon: PointerProperty(type=VerionRamp)

    use_shadow_palette: BoolProperty(name="Shadow Palette", default=False)
    shadow_direct: PointerProperty(type=VerionShadowTone)
    shadow_indirect: PointerProperty(type=VerionShadowTone)

    use_rim: BoolProperty(name="Rim Light", default=False)
    rim_color: _color("Color")
    rim_width: _unit("Width", 0.3)
    rim_feather: _unit("Feather", 0.05)
    rim_follow_light: _unit("Follow Light", 1.0, "0 is all around, 1 only on the lit side")
    rim_strength: FloatProperty(name="Strength", default=1.0, min=0.0, soft_max=4.0)

    use_specular_shape: BoolProperty(name="Stylized Specular", default=False)
    spec_shape: EnumProperty(name="Shape", items=[("band", "Band", ""), ("ellipse", "Ellipse", ""), ("texture", "Texture", "")], default="band")
    spec_stretch: FloatProperty(name="Stretch", default=2.0, min=0.1, max=10.0)
    spec_angle: FloatProperty(name="Angle", description="Degrees", default=0.0, min=-180.0, max=180.0)
    spec_texture: PointerProperty(name="Texture", type=bpy.types.Image)
    spec_size: _unit("Size", 0.05)
    spec_feather: _unit("Feather", 0.02)
    spec_color: _color("Color")
    spec_strength: FloatProperty(name="Strength", default=1.0, min=0.0, soft_max=4.0)
    spec_use_ramp: BoolProperty(name="Ramp", description="Several steps instead of one band", default=False)
    spec_ramp: PointerProperty(type=VerionRamp)

    use_outline_style: BoolProperty(name="Outline Style", default=False)
    outline_color: _color("Color", (0.0, 0.0, 0.0))
    outline_width: FloatProperty(name="Width", description="Pixels", default=2.0, min=1.0, max=8.0)
    outline_depth: _unit("Depth Threshold", 0.05)
    outline_crease: FloatProperty(name="Crease Angle", description="Degrees", default=45.0, min=0.0, max=180.0)

    use_matcap: BoolProperty(name="MatCap", default=False)
    matcap_texture: PointerProperty(name="Image", type=bpy.types.Image)
    matcap_strength: _unit("Strength", 1.0)
    matcap_albedo: _unit("Albedo")

    def to_json(self, image_index, warn):
        """(JSON text, IR image indices) or None when nothing is enabled."""
        d = {"hybridSurface": {k: getattr(self, k) for k in ("diffuse", "specular", "gi", "shadow", "outline", "reflection")}}
        imgs = []

        def texture(image, what):
            if image is None:
                warn(f"{what}: no image set; layer skipped")
                return None
            idx = image_index(image)
            if idx is None:
                warn(f"{what}: image '{image.name}' has no pixels; layer skipped")
                return None
            if idx not in imgs:
                imgs.append(idx)
            return {"index": imgs.index(idx)}

        if self.use_toon and len(self.toon.bands) >= 1:
            d["toonRamp"] = self.toon.to_json()
        if self.use_shadow_palette:
            d["shadowPalette"] = {"direct": self.shadow_direct.to_json(), "indirect": self.shadow_indirect.to_json()}
        if self.use_rim:
            d["rimLight"] = {"color": list(self.rim_color), "width": self.rim_width, "feather": self.rim_feather,
                             "followLight": self.rim_follow_light, "strength": self.rim_strength}
        if self.use_specular_shape:
            s = {"shape": self.spec_shape, "stretch": self.spec_stretch, "angle": self.spec_angle, "size": self.spec_size,
                 "feather": self.spec_feather, "color": list(self.spec_color), "strength": self.spec_strength}
            ok = True
            if self.spec_shape == "texture":
                t = texture(self.spec_texture, "Stylized Specular")
                ok = t is not None
                if ok:
                    s["texture"] = t
            if ok and self.spec_use_ramp and len(self.spec_ramp.bands) >= 1:
                s["ramp"] = self.spec_ramp.to_json()
            if ok:
                d["stylizedSpecular"] = s
        if self.use_outline_style:
            d["outlineStyle"] = {"color": list(self.outline_color), "width": self.outline_width,
                                 "depthThreshold": self.outline_depth, "creaseAngle": self.outline_crease}
        if self.use_matcap:
            t = texture(self.matcap_texture, "MatCap")
            if t is not None:
                d["matcap"] = {"texture": t, "strength": self.matcap_strength, "albedo": self.matcap_albedo}
        return json.dumps(d), imgs


class VerionWorldStyle(bpy.types.PropertyGroup):
    virtual_light: BoolProperty(
        name="Virtual Main Light",
        description="Toon bands take a main light from the brightest part of the HDRI. Physical lighting is unchanged",
        default=True,
    )
    override_direction: BoolProperty(name="Override Direction", default=False)
    direction: FloatVectorProperty(name="Direction", description="Toward the light, in Blender world space", subtype="DIRECTION",
                                   size=3, default=(0.0, 0.0, 1.0))
    strength: FloatProperty(name="Strength", default=1.0, min=0.0, soft_max=4.0)


def material_style(material, image_index, warn):
    """(stylization JSON, image indices) of a Blender material, or None when it has none enabled."""
    st = getattr(material, "verion_style", None)
    if st is None or not st.enabled:
        return None
    try:
        return st.to_json(image_index, warn)
    except Exception as e:  # a bad property must not stop the render
        warn(f"Material '{material.name}': stylization skipped ({e})")
        return None


def apply_world(scene, world):
    """Pushes the World's virtual main light settings to the IR scene."""
    st = getattr(world, "verion_style", None) if world is not None else None
    if st is None:
        scene.set_stylization_world()
        return
    d = None
    if st.override_direction and any(st.direction):
        x, y, z = st.direction
        d = [x, z, -y]  # Blender Z-up to Verion Y-up, as the scene itself
    scene.set_stylization_world(virtual_light=st.virtual_light, direction=d, strength=st.strength)


# -- UI ----------------------------------------------------------------------------------------------


class VERION_OT_band(bpy.types.Operator):
    bl_idname = "verion.style_band"
    bl_label = "Edit Band"
    bl_options = {"UNDO"}
    path: bpy.props.StringProperty()   # which ramp: "toon" or "spec_ramp"
    action: bpy.props.EnumProperty(items=[("ADD", "Add", ""), ("REMOVE", "Remove", ""), ("RESET", "Reset", "")])

    def execute(self, context):
        st = context.material.verion_style
        ramp = getattr(st, self.path)
        if self.action == "ADD":
            n = len(ramp.bands)
            b = ramp.bands.add()
            b.threshold = min(1.0, (ramp.bands[n - 1].threshold + 1.0) / 2 if n else 0.0)
            b.color = ramp.bands[n - 1].color if n else (1.0, 1.0, 1.0)
        elif self.action == "REMOVE" and len(ramp.bands) > 1:
            ramp.bands.remove(len(ramp.bands) - 1)
        elif self.action == "RESET":
            ramp.reset()
        return {"FINISHED"}


def _draw_ramp(layout, ramp, path):
    row = layout.row(align=True)
    for action, icon in (("ADD", "ADD"), ("REMOVE", "REMOVE"), ("RESET", "FILE_REFRESH")):
        op = row.operator("verion.style_band", text="", icon=icon)
        op.path, op.action = path, action
    if not ramp.bands:
        layout.label(text="No bands: press Reset", icon="INFO")
    for i, b in enumerate(ramp.bands):
        r = layout.row(align=True)
        sub = r.row(align=True)
        sub.enabled = i > 0
        sub.prop(b, "threshold", text=f"Band {i + 1}")
        r.prop(b, "color", text="")
    layout.prop(ramp, "feather")
    layout.prop(ramp, "light_wrap")


class StylePanel:
    bl_space_type = "PROPERTIES"
    bl_region_type = "WINDOW"
    bl_context = "material"
    COMPAT_ENGINES = {"VERION"}

    @classmethod
    def poll(cls, context):
        return context.engine in cls.COMPAT_ENGINES and context.material is not None


class VERION_PT_style(StylePanel, bpy.types.Panel):
    bl_label = "Verion Stylization"

    def draw_header(self, context):
        self.layout.prop(context.material.verion_style, "enabled", text="")

    def draw(self, context):
        st = context.material.verion_style
        col = self.layout.column()
        col.active = st.enabled
        for k in ("diffuse", "specular", "gi", "shadow", "outline", "reflection"):
            col.prop(st, k)


def _sub(name, label, flag, props=(), ramp=None, extra=None):
    """A sub-panel with a checkbox header that draws `props`, optionally a ramp and `extra`."""

    class Sub(StylePanel, bpy.types.Panel):
        bl_label = label
        bl_parent_id = "VERION_PT_style"
        bl_options = {"DEFAULT_CLOSED"}

        def draw_header(self, context):
            self.layout.prop(context.material.verion_style, flag, text="")

        def draw(self, context):
            st = context.material.verion_style
            col = self.layout.column()
            col.active = st.enabled and getattr(st, flag)
            for p in props:
                col.prop(st, p)
            if ramp:
                _draw_ramp(col, getattr(st, ramp), ramp)
            if extra:
                extra(col, st)

    Sub.__name__ = Sub.bl_idname = name
    return Sub


def _shadow(col, st):
    for label, tone in (("Direct", st.shadow_direct), ("Indirect", st.shadow_indirect)):
        box = col.box()
        box.label(text=label)
        box.prop(tone, "hue_shift")
        box.prop(tone, "saturation")
        box.prop(tone, "value")


def _spec(col, st):
    col.prop(st, "spec_shape")
    if st.spec_shape == "ellipse":
        col.prop(st, "spec_stretch")
    if st.spec_shape in {"ellipse", "texture"}:
        col.prop(st, "spec_angle")
    if st.spec_shape == "texture":
        col.template_ID(st, "spec_texture", open="image.open")
    for p in ("spec_size", "spec_feather", "spec_color", "spec_strength"):
        col.prop(st, p)
    col.prop(st, "spec_use_ramp")
    if st.spec_use_ramp:
        _draw_ramp(col, st.spec_ramp, "spec_ramp")


def _matcap(col, st):
    col.template_ID(st, "matcap_texture", open="image.open")
    col.prop(st, "matcap_strength")
    col.prop(st, "matcap_albedo")


SUBPANELS = (
    _sub("VERION_PT_style_toon", "Toon Ramp", "use_toon", ramp="toon"),
    _sub("VERION_PT_style_shadow", "Shadow Palette", "use_shadow_palette", extra=_shadow),
    _sub("VERION_PT_style_rim", "Rim Light", "use_rim",
         ("rim_color", "rim_width", "rim_feather", "rim_follow_light", "rim_strength")),
    _sub("VERION_PT_style_spec", "Stylized Specular", "use_specular_shape", extra=_spec),
    _sub("VERION_PT_style_outline", "Outline Style", "use_outline_style",
         ("outline_color", "outline_width", "outline_depth", "outline_crease")),
    _sub("VERION_PT_style_matcap", "MatCap", "use_matcap", extra=_matcap),
)


class VERION_PT_world(bpy.types.Panel):
    bl_label = "Verion Stylization"
    bl_space_type = "PROPERTIES"
    bl_region_type = "WINDOW"
    bl_context = "world"
    COMPAT_ENGINES = {"VERION"}

    @classmethod
    def poll(cls, context):
        return context.engine in cls.COMPAT_ENGINES and context.world is not None

    def draw(self, context):
        st = context.world.verion_style
        col = self.layout.column()
        col.prop(st, "virtual_light")
        sub = col.column()
        sub.active = st.virtual_light
        sub.prop(st, "override_direction")
        if st.override_direction:
            sub.prop(st, "direction")
        sub.prop(st, "strength")


classes = (VerionBand, VerionRamp, VerionShadowTone, VerionStyle, VerionWorldStyle, VERION_OT_band,
           VERION_PT_style, *SUBPANELS, VERION_PT_world)


def register():
    for c in classes:
        bpy.utils.register_class(c)
    bpy.types.Material.verion_style = PointerProperty(type=VerionStyle)
    bpy.types.World.verion_style = PointerProperty(type=VerionWorldStyle)


def unregister():
    del bpy.types.World.verion_style
    del bpy.types.Material.verion_style
    for c in reversed(classes):
        bpy.utils.unregister_class(c)
