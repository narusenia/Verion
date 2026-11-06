"""Transparent film and Shadow Catcher: alpha follows the coverage of the scene, and a catcher keeps
only its shadow."""
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


def rgba(catcher):
    common.reset_scene()
    common.add_camera(location=(0, -6, 2.5), target=(0, 0, 0.5), lens=35)
    ground = common.add_plane(size=40, color=(0.6, 0.6, 0.6), name="ground")
    ground.is_shadow_catcher = catcher
    common.add_sphere(location=(0, 0, 1), radius=1.0, color=(0.8, 0.2, 0.1))
    common.add_light("SUN", location=(0, 0, 10), energy=3.0).rotation_euler = (0.6, 0.0, 0.5)
    common.set_world((0.2, 0.2, 0.2), 1.0)
    sc = bpy.context.scene
    sc.render.film_transparent = True
    sc.render.image_settings.color_mode = "RGBA"
    sc.verion.samples = 32
    out = os.path.join(TMP, "alpha.exr")
    common.render("VERION", out, 96, 72, 32)
    im = bpy.data.images.load(out, check_existing=False)
    px = np.empty(96 * 72 * im.channels, np.float32)
    im.pixels.foreach_get(px)
    ch = im.channels
    bpy.data.images.remove(im)
    return px.reshape(72, 96, ch)[::-1]


class AlphaTests(unittest.TestCase):
    def test_film_transparent_alpha(self):
        a = rgba(catcher=False)
        self.assertEqual(a.shape[2], 4)
        self.assertLess(a[2, 48, 3], 0.01, "sky above the horizon is transparent")
        self.assertAlmostEqual(float(a[-2, 48, 3]), 1.0, places=3)  # the ground
        self.assertTrue(((a[..., 3] > 0.05) & (a[..., 3] < 0.95)).any(), "edges are anti-aliased")

    def test_shadow_catcher_keeps_the_shadow(self):
        a = rgba(catcher=True)
        ground = a[40:, :, :]
        shadow = ground[(ground[..., 3] > 0.25) & (ground[..., 3] < 0.99)]
        self.assertGreater(len(shadow), 8, "the sphere's shadow has alpha")
        self.assertLess(float(shadow[..., :3].max()), 0.05, "a shadow is black")
        lit = ground[..., 3] < 0.05
        self.assertGreater(lit.sum(), 500, "the lit ground is transparent")
        sphere = a[(a[..., 0] > 0.1) & (a[..., 3] > 0.99)]
        self.assertGreater(len(sphere), 100, "the sphere stays opaque")


class TransparentTests(unittest.TestCase):
    def render(self, front):
        common.reset_scene()
        common.add_camera(location=(0, -6, 1.0), target=(0, 0, 1.0), lens=50)
        common.add_sphere(location=(0, 0, 1), radius=1.0, color=(0.8, 0.2, 0.1))
        common.add_light("SUN", location=(0, 0, 10), energy=3.0).rotation_euler = (0.9, 0.0, 0.3)
        common.set_world((0.3, 0.3, 0.3), 1.0)
        if front is not None:
            plane = common.add_plane(size=6, color=(0.1, 0.8, 0.1), name="front")
            plane.rotation_euler = (1.5707963, 0, 0)
            plane.location = (0, -3, 1)
            front(plane.data.materials[0])
        return common.render("VERION", os.path.join(TMP, "clear.exr"), 64, 48, 32)

    def test_alpha_zero_and_transparent_bsdf_pass_light(self):
        ref = self.render(None)[16:32, 24:40].mean()

        def alpha0(mat):
            mat.node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = 0.0

        def transparent(mat):
            nt = mat.node_tree
            t = nt.nodes.new("ShaderNodeBsdfTransparent")
            nt.links.new(t.outputs["BSDF"], nt.nodes["Material Output"].inputs["Surface"])

        for name, f in (("alpha 0", alpha0), ("transparent bsdf", transparent)):
            with self.subTest(name):
                got = self.render(f)[16:32, 24:40].mean()
                self.assertTrue(abs(got - ref) < 0.05 * ref, f"{got} vs {ref}")
        opaque = self.render(lambda m: None)[16:32, 24:40].mean()
        self.assertGreater(abs(opaque - ref), 0.1 * ref, "an opaque plane must hide the ball")


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
