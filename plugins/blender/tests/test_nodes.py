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

    def test_sliders_have_ranges(self):
        lit_scene()
        ob, mat = sphere()
        surf = next(n for n in verion_tree(mat).nodes if n.bl_idname == "VerionNodeSurface")
        surf.inputs["Metallic"].default_value = 5.0
        surf.inputs["IOR"].default_value = 0.2
        self.assertEqual(surf.inputs["Metallic"].default_value, 1.0)
        self.assertEqual(surf.inputs["IOR"].default_value, 1.0)

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

    def converted(self, mat, warnings=None):
        import json

        from verion_blender import materials, native

        p = materials.Converter(native.load().Scene(), (warnings if warnings is not None else []).append).params(mat)
        return json.loads(p["stylization"]) if "stylization" in p else None, p

    def chain(self, tree, *keys):
        """Surface -> the given Stylization nodes -> Output, in order."""
        surf = next(n for n in tree.nodes if n.bl_idname == "VerionNodeSurface")
        out = next(n for n in tree.nodes if n.bl_idname == "VerionNodeOutput")
        prev, nodes = surf, []
        for k in keys:
            n = tree.nodes.new("VerionNodeStyle_" + k)
            tree.links.new(prev.outputs["Surface"], n.inputs["Surface"])
            prev = n
            nodes.append(n)
        tree.links.new(prev.outputs["Surface"], out.inputs["Surface"])
        return nodes

    def test_style_nodes_make_the_same_json_as_the_panel(self):
        lit_scene()
        ob, panel_mat = sphere(name="panel")
        st = panel_mat.verion_style
        st.enabled = st.use_toon = st.use_rim = True
        st.toon.reset()
        st.diffuse, st.rim_width = 1.0, 0.5
        _, node_mat = sphere(name="node")
        toon, rim, hybrid = self.chain(verion_tree(node_mat), "toon", "rim", "hybrid")
        hybrid.style.diffuse, rim.style.rim_width = 1.0, 0.5
        self.assertEqual(self.converted(node_mat)[0], self.converted(panel_mat)[0])

    def test_the_tree_replaces_the_panel(self):
        lit_scene()
        ob, mat = sphere()
        mat.verion_style.enabled = mat.verion_style.use_toon = True
        mat.verion_style.toon.reset()
        self.assertIn("toonRamp", self.converted(mat)[0])
        verion_tree(mat)  # no Stylization nodes: the panel is ignored
        self.assertIsNone(self.converted(mat)[0])

    def test_style_edits_change_the_signature(self):
        from verion_blender import materials

        lit_scene()
        ob, mat = sphere()
        (rim,) = self.chain(verion_tree(mat), "rim")
        before = materials.Converter.tree_signature(mat)
        rim.style.rim_width = 0.9
        self.assertNotEqual(materials.Converter.tree_signature(mat), before)
        before = materials.Converter.tree_signature(mat)
        rim.style.toon.reset(5)
        self.assertNotEqual(materials.Converter.tree_signature(mat), before)

    def test_matcap_node_carries_its_image(self):
        lit_scene()
        ob, mat = sphere()
        (cap,) = self.chain(verion_tree(mat), "matcap")
        img = bpy.data.images.new("cap", 4, 4)
        img.pixels = [0.5, 0.5, 0.5, 1.0] * 16
        cap.style.matcap_texture = img
        warnings = []
        d, p = self.converted(mat, warnings)
        self.assertEqual(d["matcap"]["texture"], {"index": 0})
        self.assertEqual(len(p["stylization_images"]), 1)
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
