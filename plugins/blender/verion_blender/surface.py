"""Surface settings of a Blender material that Blender's own shader nodes cannot express.

Dispersion (the IR's `KHR_materials_dispersion`): Principled and Glass BSDF have no such socket, so it
is a property of the material, shown in the Material tab, and overrides the converted material's value.
"""
import bpy
from bpy.props import FloatProperty, PointerProperty


class VerionSurface(bpy.types.PropertyGroup):
    dispersion: FloatProperty(
        name="Dispersion",
        description="Splits the IOR of a transmissive material per color channel: 20 / Abbe number "
        "(about 0.3 for glass, 1 or more for a strong effect). 0 is off",
        default=0.0, min=0.0, soft_max=2.0,
    )


class VERION_PT_surface_extras(bpy.types.Panel):
    bl_label = "Verion Surface"
    bl_space_type = "PROPERTIES"
    bl_region_type = "WINDOW"
    bl_context = "material"
    COMPAT_ENGINES = {"VERION"}

    @classmethod
    def poll(cls, context):
        return context.engine in cls.COMPAT_ENGINES and context.material is not None

    def draw(self, context):
        self.layout.prop(context.material.verion_surface, "dispersion")


def apply(material, params):
    """Adds the material's Verion-only settings to the converted parameters."""
    s = getattr(material, "verion_surface", None)
    if s is not None and s.dispersion > 0.0:
        params["dispersion"] = s.dispersion
    return params


classes = (VerionSurface, VERION_PT_surface_extras)


def register():
    for c in classes:
        bpy.utils.register_class(c)
    bpy.types.Material.verion_surface = PointerProperty(type=VerionSurface)


def unregister():
    del bpy.types.Material.verion_surface
    for c in reversed(classes):
        bpy.utils.unregister_class(c)
