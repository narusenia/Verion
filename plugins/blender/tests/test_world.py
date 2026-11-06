"""The World (uniform color and an HDRI) against Cycles: strength, orientation and rotation."""
import math
import os
import sys
import tempfile
import unittest

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

common.enable_addon()
TMP = tempfile.gettempdir()


def make_hdri(path):
    """Eight vertical color bands left to right, cyan on the top rows and magenta on the bottom ones."""
    w, h = 64, 32
    a = np.zeros((h, w, 4), np.float32)
    bands = [(2, 0, 0), (0, 2, 0), (0, 0, 2), (2, 2, 0), (0, 2, 2), (2, 0, 2), (2, 2, 2), (1, 0.5, 0)]
    for i, c in enumerate(bands):
        a[:, i * w // 8 : (i + 1) * w // 8, :3] = c
    a[: h // 4, :, :3] = (0, 2, 2)      # the top rows of the file: cyan
    a[-h // 4 :, :, :3] = (2, 0, 2)     # the bottom rows: magenta
    a[..., 3] = 1
    im = bpy.data.images.new("hdri", w, h, float_buffer=True, alpha=False)
    im.colorspace_settings.name = "Non-Color"
    im.pixels.foreach_set(a[::-1].ravel())  # Blender stores the bottom row first
    im.filepath_raw = path
    im.file_format = "OPEN_EXR"
    im.save()
    return im


def world_with_hdri(path, rotation_z=0.0, strength=1.0):
    w = bpy.data.worlds.new("hdri")
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes["Background"]
    bg.inputs["Strength"].default_value = strength
    tex = nt.nodes.new("ShaderNodeTexEnvironment")
    tex.image = bpy.data.images.load(path)
    tex.image.colorspace_settings.name = "Non-Color"
    nt.links.new(tex.outputs["Color"], bg.inputs["Color"])
    if rotation_z:
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Rotation"].default_value = (0, 0, rotation_z)
        coord = nt.nodes.new("ShaderNodeTexCoord")
        nt.links.new(coord.outputs["Generated"], mp.inputs["Vector"])
        nt.links.new(mp.outputs["Vector"], tex.inputs["Vector"])
    bpy.context.scene.world = w


def scene_for(look):
    common.reset_scene()
    # A floor far out of view so the scene is not empty.
    common.add_plane(size=2.0, z=-500.0)
    cam = common.add_camera(location=(0, 0, 0), target=tuple(look), lens=20)
    return cam


def sky_pixel(engine, look):
    return common.render(engine, os.path.join(TMP, "w.exr"), 16, 16, 4)[8, 8]


class WorldTests(unittest.TestCase):
    def test_uniform_color_and_strength(self):
        for engine in ("CYCLES", "VERION"):
            scene_for((1, 0, 0))
            common.set_world((0.2, 0.4, 0.6), 2.0)
            px = sky_pixel(engine, (1, 0, 0))
            np.testing.assert_allclose(px, (0.4, 0.8, 1.2), rtol=0.02, err_msg=engine)

    def test_hdri_direction_matches_cycles(self):
        path = os.path.join(TMP, "bands.exr")
        for rot in (0.0, math.pi / 2):
            looks = [(math.cos(a), math.sin(a), 0) for a in np.radians(22.5 + 45 * np.arange(8))]
            for look in looks + [(0.1, 0.2, 1), (0.1, 0.2, -1)]:
                got = {}
                for engine in ("CYCLES", "VERION"):
                    scene_for(look)
                    make_hdri(path)
                    world_with_hdri(path, rot)
                    got[engine] = sky_pixel(engine, look)
                with self.subTest(look=look, rotation=rot):
                    np.testing.assert_allclose(got["VERION"], got["CYCLES"], atol=0.15, err_msg=f"{got}")




class SkyTests(unittest.TestCase):
    def test_sky_texture_is_baked_and_matches_cycles(self):
        def sky_world():
            w = bpy.data.worlds.new("sky")
            w.use_nodes = True
            nt = w.node_tree
            sky = nt.nodes.new("ShaderNodeTexSky")
            kinds = {e.identifier for e in sky.bl_rna.properties["sky_type"].enum_items}
            sky.sky_type = "NISHITA" if "NISHITA" in kinds else "MULTIPLE_SCATTERING"  # renamed in 5.0
            sky.sun_elevation = np.radians(35)
            sky.sun_rotation = np.radians(70)
            nt.links.new(sky.outputs["Color"], nt.nodes["Background"].inputs["Color"])
            bpy.context.scene.world = w

        def lit(engine, look):
            scene_for(look)
            common.add_plane(size=60, z=-0.5, color=(0.5, 0.5, 0.5), name="ground")
            sky_world()
            return common.render(engine, os.path.join(TMP, "sky.exr"), 24, 24, 32)

        # The sky away from the sun (a 0.5 degree disc is sub-pixel noise in a direct view), and a
        # ground lit by the sun and the sky, which is where the sun's energy shows.
        for look in [(-1, -0.3, 0.2), (-0.3, 1, 0.5), (0, -1, 0.1), (0.5, 0.5, -0.4), (1, 0.3, -0.7)]:
            with self.subTest(look=look):
                cy, ve = lit("CYCLES", look), lit("VERION", look)
                # The grey ground is about 14% darker in Verion than in Cycles at grazing angles
                # (a BSDF difference, see test_materials.py), so the ratio is not 1.
                self.assertTrue(0.75 <= ve.mean() / cy.mean() <= 1.15, f"{ve.mean() / cy.mean():.3f}")


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
