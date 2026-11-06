"""Measures First Clean Preview (REQ-DCC-002): seconds from a scene edit to `clean_samples` samples.

Run: blender -b --factory-startup --python measure_fcp.py [-- WIDTH HEIGHT]
Prints one line per edit kind: first frame and clean (16 spp) times.
"""
import os
import sys
import time

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common
from test_viewport import make_scene, perspective, wait_clean

common.enable_addon()
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
W, H = (int(args[0]), int(args[1])) if len(args) >= 2 else (960, 540)

from verion_blender import native
from verion_blender.viewport import View, Viewport

cam = make_scene()
for i in range(6):
    common.add_sphere(location=(-3 + i * 1.2, 1.5, 0.6), radius=0.5, color=(0.2 + 0.1 * i, 0.4, 0.8 - 0.1 * i), name=f"b{i}")
sc = bpy.context.scene
sc.verion.viewport_samples = 64
sc.verion.clean_samples = 16
view = View(cam.matrix_world, perspective(0.8, W / H), W, H)
vp = Viewport(native.load())


def graph():
    return bpy.context.evaluated_depsgraph_get()


def wait_after(edits, timeout=30):
    """Waits for the clean preview that follows the edit numbered `edits` (stats lag until the job sees it)."""
    t = time.time()
    while time.time() - t < timeout:
        vp.job.wait(0.01)
        vp.poll()
        if vp.stats["edits"] > edits and vp.stats["clean_s"] is not None:
            return True
    return False


def measure(name, edit):
    edit()
    t = time.time()
    n = vp.stats["edits"]
    vp.update(graph(), view, sc.verion)
    ok = wait_after(n)
    st = vp.stats
    print(f"FCP {name}: first frame {st.get('first_frame_s'):.3f} s, clean {st.get('clean_s'):.3f} s, "
          f"update {st['update_s'] * 1000:.1f} ms, wall {time.time() - t:.3f} s" if ok else f"FCP {name}: timeout")


vp.update(graph(), view, sc.verion)
wait_clean(vp)
print(f"FCP initial build ({W}x{H}): first frame {vp.stats['first_frame_s']:.3f} s, clean {vp.stats['clean_s']:.3f} s")
light = bpy.data.objects["light"]
ball = bpy.data.objects["ball"]
measure("light moved", lambda: setattr(light, "location", (-2, -2, 4)))
measure("object moved", lambda: setattr(ball, "location", (1, 0, 1)))
measure("material color", lambda: bpy.data.materials["ball"].node_tree.nodes["Principled BSDF"].inputs["Base Color"].__setattr__("default_value", (0.1, 0.9, 0.2, 1)))
n = vp.stats["edits"]
vp.set_view(View(cam.matrix_world, perspective(0.7, W / H), W, H), sc.verion)
wait_after(n)
print(f"FCP camera moved: clean {vp.stats['clean_s']:.3f} s")
vp.close()
