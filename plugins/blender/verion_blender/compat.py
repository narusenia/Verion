"""Differences between Blender 4.5 LTS and 5.x, kept in one place (ADR-0019).

Add a function here instead of branching on the version inside the add-on.
"""
import bpy

BLENDER_5 = bpy.app.version >= (5, 0, 0)


def panels_to_enable():
    """Built-in panels a custom engine reuses: every panel that lists the legacy engine id.

    The names differ between versions, but they all carry 'BLENDER_RENDER' in COMPAT_ENGINES.
    """
    exclude = {
        "VIEWLAYER_PT_filter",
        "VIEWLAYER_PT_layer_passes",
        "RENDER_PT_freestyle",
    }
    stack = list(bpy.types.Panel.__subclasses__())
    while stack:
        p = stack.pop()
        stack.extend(p.__subclasses__())
        engines = getattr(p, "COMPAT_ENGINES", None)
        if engines is None or p.__name__ in exclude:
            continue
        if "BLENDER_RENDER" in engines or p.__name__ in NODE_PANELS:
            yield p


# The node-socket panels of the Material and World tabs (Surface, Volume, slots). They list only the
# engines that draw them, not the legacy id, so a custom engine has to be added by name.
NODE_PANELS = {
    "EEVEE_MATERIAL_PT_context_material",
    "EEVEE_MATERIAL_PT_surface",
    "EEVEE_MATERIAL_PT_volume",
    "EEVEE_MATERIAL_PT_settings",
    "EEVEE_WORLD_PT_surface",
}


def eevee_engine_ids():
    """The id of Blender's real-time engine, for the engine picker (renamed in 5.0)."""
    return {"BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"}


def stamp_field(result, scene, key, value):
    """RenderResult.stamp_data_add_field(field, value); older versions also took the scene first."""
    try:
        result.stamp_data_add_field(key, value)
    except TypeError:
        result.stamp_data_add_field(scene, key, value)
