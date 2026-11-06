bl_info = {
    "name": "Verion",
    "author": "NaruseNia",
    "version": (0, 0, 0),
    "blender": (4, 5, 0),
    "description": "Art-directable physical GPU renderer",
    "category": "Render",
}

import bpy

from . import engine, nodes, props, stylization, surface, ui


def register():
    props.register()
    stylization.register()
    nodes.register()
    surface.register()
    bpy.utils.register_class(engine.VerionRenderEngine)
    ui.register()


def unregister():
    ui.unregister()
    bpy.utils.unregister_class(engine.VerionRenderEngine)
    surface.unregister()
    nodes.unregister()
    stylization.unregister()
    props.unregister()
