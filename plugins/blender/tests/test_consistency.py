"""The same scene through the add-on and through glTF (REQ-QA, item 14): Blender's own glTF exporter writes
the geometry, materials and camera, the lights are added to the file with the add-on's unit factors, and
`render-cli` renders it. The two images must agree. (Cycles is compared in the other tests, as a reference.)"""
import json
import math
import os
import subprocess
import sys
import tempfile
import unittest

import bpy
import mathutils
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

common.enable_addon()
from verion_blender import units  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
TMP = tempfile.mkdtemp(prefix="verion_consistency_")
W, H, SPP = 128, 96, 96
# Blender Z-up to glTF Y-up, as the exporter does.
C = mathutils.Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))


def build():
    common.reset_scene()
    common.add_camera(location=(0, -6, 3), target=(0, 0, 0.8), lens=45)
    common.add_plane(size=20, color=(0.5, 0.5, 0.5))
    common.add_sphere(location=(-1.2, 0, 1), radius=1.0, color=(0.8, 0.3, 0.2), roughness=0.9)
    common.add_sphere(location=(1.3, 0.3, 0.7), radius=0.7, color=(0.2, 0.5, 0.8), roughness=0.5, metallic=1.0)
    sun = common.add_light("SUN", location=(0, 0, 10), energy=2.0, name="sun")
    sun.rotation_euler = (0.7, 0.2, 0.5)
    common.add_light("POINT", location=(2.5, -3.0, 3.5), energy=900.0, color=(1.0, 0.9, 0.8), name="lamp")
    common.set_world((0.0, 0.0, 0.0), 0.0)


def gltf_lights(path_gltf):
    """Adds the scene's lights to the exported glTF as KHR_lights_punctual, with the add-on's factors."""
    with open(path_gltf) as f:
        doc = json.load(f)
    lights, nodes = [], []
    for ob in bpy.context.scene.objects:
        if ob.type != "LIGHT":
            continue
        d = ob.data
        if d.type == "SUN":
            lights.append({"type": "directional", "color": list(d.color), "intensity": d.energy * units.SUN_PER_STRENGTH})
        else:
            lights.append({"type": "point", "color": list(d.color), "intensity": d.energy * units.POINT_PER_WATT})
        m = C @ ob.matrix_world.normalized()
        t, q, _s = m.decompose()
        nodes.append({"name": ob.name, "translation": list(t), "rotation": [q.x, q.y, q.z, q.w],
                      "extensions": {"KHR_lights_punctual": {"light": len(lights) - 1}}})
    first = len(doc["nodes"])
    doc["nodes"].extend(nodes)
    doc["scenes"][0]["nodes"].extend(range(first, first + len(nodes)))
    doc.setdefault("extensions", {})["KHR_lights_punctual"] = {"lights": lights}
    doc.setdefault("extensionsUsed", []).append("KHR_lights_punctual")
    with open(path_gltf, "w") as f:
        json.dump(doc, f)


def read_exr(path):
    from verion_blender import native

    return native.load().read_image(path)


def blocks(a, n=4):
    return a.mean(axis=2).reshape(H // n, n, W // n, n).mean(axis=(1, 3))


class ConsistencyTests(unittest.TestCase):
    def test_blender_and_gltf_agree(self):
        cli = os.path.join(ROOT, "target", "debug", "render-cli")
        subprocess.run(["cargo", "build", "-q", "-p", "verion-render-cli"], cwd=ROOT, check=True)
        build()
        ours = common.render("VERION", os.path.join(TMP, "blender.exr"), W, H, SPP)
        gltf = os.path.join(TMP, "scene.gltf")
        bpy.ops.export_scene.gltf(filepath=gltf, export_format="GLTF_SEPARATE", export_lights=False, export_cameras=True,
                                  export_apply=True, export_yup=True)
        gltf_lights(gltf)
        out = os.path.join(TMP, "cli.exr")
        r = subprocess.run([cli, gltf, "-o", out, "--width", str(W), "--height", str(H), "--spp", str(SPP)],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr[-500:])
        theirs = read_exr(out)
        ratio = float(ours.mean() / theirs.mean())
        a, b = blocks(ours).ravel(), blocks(theirs).ravel()
        corr = float(np.corrcoef(a, b)[0, 1])
        print(f"CONSISTENCY: mean ratio {ratio:.4f}, block correlation {corr:.5f}, max block diff "
              f"{float(np.abs(a - b).max() / max(b.max(), 1e-6)):.4f}")
        common.save_png(os.path.join(TMP, "blender.png"), ours)
        common.save_png(os.path.join(TMP, "cli.png"), theirs)
        self.assertTrue(0.97 <= ratio <= 1.03, f"mean ratio {ratio:.4f}")
        self.assertGreater(corr, 0.995)


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
