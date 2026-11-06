"""UDIM tiles against Cycles: a plane whose UVs span two tiles with different colors."""
import os
import sys
import tempfile
import unittest

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

common.enable_addon()
TMP = tempfile.mkdtemp(prefix="udim_")


def tile_file(number, color):
    im = bpy.data.images.new(f"t{number}", 16, 16, float_buffer=True)
    im.colorspace_settings.name = "Non-Color"
    px = np.ones((16, 16, 4), np.float32)
    px[..., :3] = color
    px[:, :, 0] *= np.linspace(0.6, 1.0, 16)[None, :]   # a gradient so orientation matters
    im.pixels.foreach_set(px.ravel())
    im.filepath_raw = os.path.join(TMP, f"tex.{number}.exr")
    im.file_format = "OPEN_EXR"
    im.save()
    bpy.data.images.remove(im)


def build():
    common.reset_scene()
    common.add_camera(location=(0, -4, 2.2), target=(0, 0, 0.8))
    common.add_light("AREA", location=(1, -3, 5), energy=1500).data.size = 3.0
    common.set_world((0.3, 0.3, 0.3), 1.0)
    me = bpy.data.meshes.new("quad")
    me.from_pydata([(-2, 0, 0), (2, 0, 0), (2, 0, 2), (-2, 0, 2)], [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new()
    for loop, (u, v) in zip(me.loops, [(0.1, 0.1), (1.9, 0.1), (1.9, 0.9), (0.1, 0.9)]):
        uv.data[loop.index].uv = (u, v)       # across tiles 1001 and 1002
    ob = bpy.data.objects.new("quad", me)
    bpy.context.scene.collection.objects.link(ob)
    mat = bpy.data.materials.new("udim")
    mat.use_nodes = True
    me.materials.append(mat)
    img = bpy.data.images.load(os.path.join(TMP, "tex.1001.exr"))
    img.source = "TILED"
    img.filepath = os.path.join(TMP, "tex.<UDIM>.exr")
    img.colorspace_settings.name = "Non-Color"
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Linear"
    nt = mat.node_tree
    nt.links.new(tex.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    nt.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0


class UdimTests(unittest.TestCase):
    def test_two_tiles_match_cycles(self):
        tile_file(1001, (0.9, 0.2, 0.1))
        tile_file(1002, (0.1, 0.3, 0.9))
        out = {}
        for e in ("CYCLES", "VERION"):
            build()
            out[e] = common.render(e, os.path.join(TMP, "u.exr"), 96, 64, 32)
        left, right = [a[20:44, 8:44].mean(axis=(0, 1)) for a in (out["CYCLES"], out["VERION"])], None
        cy, ve = out["CYCLES"], out["VERION"]
        for name, sl in (("left tile", (slice(20, 44), slice(14, 40))), ("right tile", (slice(20, 44), slice(58, 84)))):
            c, v = cy[sl].mean(axis=(0, 1)), ve[sl].mean(axis=(0, 1))
            print(f"UDIM {name}: cycles {np.round(c, 3)} verion {np.round(v, 3)}")
            self.assertTrue(np.all(np.abs(v / np.maximum(c, 1e-3) - 1) < 0.2), name)
        # The tiles really differ: left is red-ish, right is blue-ish.
        self.assertGreater(ve[20:44, 14:40, 0].mean(), ve[20:44, 14:40, 2].mean())
        self.assertGreater(ve[20:44, 58:84, 2].mean(), ve[20:44, 58:84, 0].mean())


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
