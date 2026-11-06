"""The Verion node tree: it must define the same material as the equivalent Principled BSDF."""
import os
import sys
import tempfile
import time
import unittest

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common
from test_materials import lit_scene
from test_viewport import perspective, wait_clean

common.enable_addon()
TMP = tempfile.gettempdir()
LOOK = dict(base_color=(0.7, 0.3, 0.2), roughness=0.3, metallic=0.5)


def verion_tree(mat):
    """A Verion tree bound to `mat` (the operator creates Surface and Output)."""
    with bpy.context.temp_override(material=mat):
        bpy.ops.verion.node_tree_new()
    return mat.verion_surface.node_tree


def sphere(**kw):
    ob = common.add_sphere(**kw)
    return ob, ob.data.materials[0]


class NodeTests(unittest.TestCase):
    def render(self, tree_values=None):
        from verion_blender import materials  # noqa: F401  (registers nothing; import must work)

        lit_scene()
        ob, mat = sphere(color=LOOK["base_color"], roughness=LOOK["roughness"], metallic=LOOK["metallic"])
        if tree_values is not None:
            tree = verion_tree(mat)
            node = next(n for n in tree.nodes if n.bl_idname == "VerionNodeSurface")
            for k, v in tree_values.items():
                node.inputs[k].default_value = v
            # The Principled node stays in the Blender tree with different values: the tree must win.
            mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
        return common.render("VERION", os.path.join(TMP, "nodes.exr"), 96, 72, 24)

    def test_tree_matches_the_principled_material(self):
        ref = self.render()
        got = self.render({"Base Color": (*LOOK["base_color"], 1.0), "Roughness": LOOK["roughness"], "Metallic": LOOK["metallic"]})
        self.assertLess(np.abs(ref - got).mean() / ref.mean(), 0.02)

    def test_a_node_value_changes_the_render(self):
        a = self.render({"Roughness": 0.05})
        b = self.render({"Roughness": 0.9})
        self.assertGreater(np.abs(a - b).mean() / a.mean(), 0.02)

    def test_image_node_feeds_a_texture(self):
        lit_scene()
        ob, mat = sphere()
        img = bpy.data.images.new("tex", 4, 4)
        img.pixels = [1.0, 0.0, 0.0, 1.0] * 16
        tree = verion_tree(mat)
        surf = next(n for n in tree.nodes if n.bl_idname == "VerionNodeSurface")
        node = tree.nodes.new("VerionNodeImage")
        node.image = img
        tree.links.new(node.outputs["Color"], surf.inputs["Base Color"])
        from verion_blender import materials

        warnings = []
        from verion_blender import native

        p = materials.Converter(native.load().Scene(), warnings.append).params(mat)
        self.assertIsNotNone(p.get("base_color_texture"))
        self.assertEqual(warnings, [])

    def test_editing_the_tree_reaches_the_viewport(self):
        from verion_blender import native
        from verion_blender.viewport import View, Viewport

        lit_scene()
        ob, mat = sphere()
        tree = verion_tree(mat)
        surf = next(n for n in tree.nodes if n.bl_idname == "VerionNodeSurface")
        sc = bpy.context.scene
        sc.verion.viewport_samples = sc.verion.clean_samples = 8
        cam = sc.camera
        dg = bpy.context.evaluated_depsgraph_get()
        view = View(cam.matrix_world, perspective(), 96, 96)
        vp = Viewport(native.load())
        try:
            vp.update(dg, view, sc.verion)
            self.assertTrue(wait_clean(vp))
            first = vp.image[2].copy()
            surf.inputs["Base Color"].default_value = (0.0, 0.0, 1.0, 1.0)
            vp.update(bpy.context.evaluated_depsgraph_get(), view, sc.verion)
            self.assertTrue(wait_clean(vp))
            vp.job.wait(0.5)
            vp.poll()
            self.assertGreater(np.abs(vp.image[2] - first).mean(), 1e-3)
        finally:
            vp.close()


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
