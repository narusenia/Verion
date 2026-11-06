"""IES profiles and light linking against Cycles."""
import os
import sys
import tempfile
import unittest

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

common.enable_addon()
TMP = tempfile.gettempdir()

# A downlight: the peak straight down, 100 -> 40 at 30 degrees, nothing past 60.
IES = "IESNA:LM-63-2002\nTILT=NONE\n1 1000 1 5 1 1 2 0 0 0\n1 1 10\n0 15 30 60 90\n0\n100 85 40 0 0\n"


def both(build, w=96, h=72, spp=48):
    out = {}
    for engine in ("CYCLES", "VERION"):
        common.reset_scene()
        common.add_camera(location=(0, -6, 4), target=(0, 0, 0), lens=40)
        common.add_plane(size=20, color=(0.6, 0.6, 0.6))
        common.set_world((0.0, 0.0, 0.0), 0.0)
        build()
        out[engine] = common.render(engine, os.path.join(TMP, "extras.exr"), w, h, spp)
    return out


def blocks(a, n=4):
    h, w = a.shape[0] // n * n, a.shape[1] // n * n
    return a[:h, :w].mean(axis=2).reshape(h // n, n, w // n, n).mean(axis=(1, 3))


class LightExtrasTests(unittest.TestCase):
    def test_ies_downlight(self):
        path = os.path.join(TMP, "down.ies")
        with open(path, "w") as f:
            f.write(IES)

        def build():
            ob = common.add_light("POINT", location=(0, 0, 3), energy=800.0)
            ob.data.use_nodes = True
            nt = ob.data.node_tree
            ies = nt.nodes.new("ShaderNodeTexIES")
            ies.mode = "EXTERNAL"
            ies.filepath = path
            nt.links.new(ies.outputs[0], nt.nodes["Emission"].inputs["Strength"])

        r = both(build)
        cy, ve = r["CYCLES"], r["VERION"]
        a, b = blocks(cy).ravel(), blocks(ve).ravel()
        c = float(np.corrcoef(a, b)[0, 1])
        ratio = float(ve.mean() / cy.mean())
        print(f"IES: mean ratio {ratio:.3f}, block correlation {c:.4f}")
        self.assertGreater(c, 0.97)
        self.assertTrue(0.8 <= ratio <= 1.25, f"ratio {ratio:.3f}")

    def test_light_linking_receivers(self):
        def build():
            for i, x in enumerate((-2.0, 2.0)):
                common.add_sphere(location=(x, 0, 1), radius=0.8, color=(0.8, 0.8, 0.8), name=f"ball{i}")
            lamp = common.add_light("POINT", location=(0, -2, 5), energy=1500.0)
            col = bpy.data.collections.new("receivers")
            bpy.context.scene.collection.children.link(col)
            col.objects.link(bpy.data.objects["ball0"])
            lamp.light_linking.receiver_collection = col

        r = both(build)
        # Only ball0 (left of the image) is lit by the lamp; ball1 and the floor get nothing.
        for engine, img in r.items():
            h, w = img.shape[:2]
            left, right = img[h // 3 : 2 * h // 3, w // 6 : w // 3].mean(), img[h // 3 : 2 * h // 3, 2 * w // 3 : 5 * w // 6].mean()
            print(f"linking {engine}: left {left:.3f} right {right:.3f}")
            self.assertGreater(left, 5 * right + 0.01, engine)


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
