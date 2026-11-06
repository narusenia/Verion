bl_info = {
    "name": "Verion",
    "author": "NaruseNia",
    "version": (0, 0, 0),
    "blender": (4, 5, 0),
    "description": "Art-directable physical GPU renderer",
    "category": "Render",
}

import bpy

from . import engine, props, ui


def register():
    props.register()
    bpy.utils.register_class(engine.VerionRenderEngine)
    ui.register()


def unregister():
    ui.unregister()
    bpy.utils.unregister_class(engine.VerionRenderEngine)
    props.unregister()
