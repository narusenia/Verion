"""Stylization panels: a Toon ramp set on a Blender material cuts the lighting into bands, the other
layers reach the native parser, and the World's virtual main light settings are accepted."""
import json
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


def scene(style):
    common.reset_scene()
    common.add_camera(location=(0, -5, 1.5), target=(0, 0, 1), lens=60)
    ball = common.add_sphere(location=(0, 0, 1), radius=1.0, color=(0.8, 0.5, 0.4), roughness=1.0)
    common.add_light("SUN", location=(0, 0, 10), energy=3.0).rotation_euler = (0.8, 0.0, 0.6)
    common.set_world((0.02, 0.02, 0.02), 1.0)
    style(ball.data.materials[0].verion_style)
    bpy.context.scene.verion.mode = "STYLIZED"
    return ball


def levels(img):
    lum = img.mean(axis=2)
    h, w = lum.shape
    core = lum[h // 4: 3 * h // 4, w // 3: 2 * w // 3]
    core = core[core > 0.02]
    return len(np.unique(np.round(core, 2)))


def toon(st):
    st.enabled = True
    st.diffuse = 1.0
    st.use_toon = True
    st.toon.reset(3)


class StylizationTests(unittest.TestCase):
    def render(self):
        return common.render("VERION", os.path.join(TMP, "sty.exr"), 96, 72, 32)

    def test_toon_ramp_cuts_bands(self):
        scene(lambda st: setattr(st, "enabled", False))
        smooth = levels(self.render())
        scene(toon)
        banded = levels(self.render())
        self.assertGreater(smooth, 20)
        self.assertLessEqual(banded, 8, f"{banded} levels with a 3 band ramp")

    def test_json_follows_the_schema(self):
        ball = scene(toon)
        st = ball.data.materials[0].verion_style
        st.use_rim = True
        st.use_shadow_palette = True
        st.use_specular_shape = True
        st.spec_use_ramp = True
        st.spec_ramp.reset(2)
        st.use_outline_style = True
        text, imgs = st.to_json(lambda im: 0, print)
        d = json.loads(text)
        self.assertEqual(set(d), {"hybridSurface", "toonRamp", "shadowPalette", "rimLight", "stylizedSpecular", "outlineStyle"})
        self.assertEqual(len(d["toonRamp"]["palette"]), len(d["toonRamp"]["thresholds"]) + 1)
        self.assertEqual(imgs, [])
        # Every layer must pass the native parser and its validation.
        from verion_blender import native

        verion = native.load()

        s = verion.Scene()
        s.add_material(stylization=text, stylization_images=[])
        # A texture layer without an image is skipped with a warning, not sent.
        st.use_matcap = True
        warned = []
        text, _ = st.to_json(lambda im: 0, warned.append)
        self.assertNotIn("matcap", json.loads(text))
        self.assertTrue(warned)

    def test_render_with_every_layer_and_world_override(self):
        def everything(st):
            toon(st)
            st.use_rim = st.use_shadow_palette = st.use_specular_shape = st.use_outline_style = True
            st.shadow = st.outline = st.specular = 1.0
        ball = scene(everything)
        w = bpy.context.scene.world
        w.verion_style.override_direction = True
        w.verion_style.direction = (0.3, -0.5, 0.8)
        img = self.render()
        self.assertTrue(np.isfinite(img).all() and img.mean() > 0.01)


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
