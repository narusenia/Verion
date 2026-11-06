"""Started by scripts/blender_gui.sh: registers the add-on from the repository (no install, no preferences
change), builds a small scene and switches the 3D view to the rendered viewport with Verion."""
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import verion_blender  # noqa: E402

verion_blender.register()


def setup():
    sc = bpy.context.scene
    sc.render.engine = "VERION"
    for ob in list(sc.objects):
        if ob.type == "LIGHT":
            ob.data.energy = 1000
    for win in bpy.context.window_manager.windows:
        for area in win.screen.areas:
            if area.type == "VIEW_3D":
                area.spaces[0].shading.type = "RENDERED"
    return None


bpy.app.timers.register(setup, first_interval=1.0)
