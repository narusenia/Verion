"""Viewport logic without a 3D view: a View built from matrices drives the interactive job."""
import os
import sys
import time
import unittest

import bpy
import numpy as np
from mathutils import Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

common.enable_addon()


def perspective(fov=0.8, aspect=1.0, shift=(0, 0)):
    t = 1 / np.tan(fov / 2)
    return Matrix(((t / aspect, 0, shift[0], 0), (0, t, shift[1], 0), (0, 0, -1.002, -0.2), (0, 0, -1, 0)))


def make_scene():
    common.reset_scene()
    common.add_plane()
    common.add_sphere()
    common.add_light("AREA", location=(2, -2, 4), energy=800).data.size = 2.0
    common.set_world((0.2, 0.25, 0.3), 1.0)
    cam = common.add_camera()
    return cam


def wait_clean(vp, timeout=20):
    t = time.time()
    while time.time() - t < timeout:
        vp.job.wait(0.02)
        vp.poll()
        if vp.stats.get("clean_s") is not None:
            return True
    return False


class ViewportTests(unittest.TestCase):
    def test_viewport_renders_follows_edits_and_rebuilds(self):
        from verion_blender import native
        from verion_blender.viewport import View, Viewport

        cam = make_scene()
        sc = bpy.context.scene
        sc.verion.viewport_samples = 64
        sc.verion.clean_samples = 8
        dg = bpy.context.evaluated_depsgraph_get()
        view = View(cam.matrix_world, perspective(), 96, 96)
        vp = Viewport(native.load())
        try:
            vp.update(dg, view, sc.verion)
            self.assertTrue(wait_clean(vp))
            first = vp.image[2].copy()
            self.assertEqual(first.shape, (96, 96, 4))
            self.assertGreater(first[..., :3].mean(), 0.02)
            # A transform edit is applied in place and restarts the accumulation.
            ball = bpy.data.objects["ball"]
            ball.location.x += 1.5
            dg = bpy.context.evaluated_depsgraph_get()
            vp.update(dg, view, sc.verion)
            self.assertTrue(wait_clean(vp))
            self.assertGreaterEqual(vp.stats["edits"], 1)
            self.assertGreater(np.abs(vp.image[2] - first).mean(), 1e-3)
            # A view change moves only the camera.
            vp.set_view(View(cam.matrix_world, perspective(0.5), 96, 96), sc.verion)
            self.assertTrue(wait_clean(vp))
            # A new object changes the structure: the session is rebuilt.
            common.add_sphere(location=(-2, 0, 1), name="ball2")
            dg = bpy.context.evaluated_depsgraph_get()
            vp.update(dg, view, sc.verion)
            self.assertTrue(wait_clean(vp))
        finally:
            vp.close()

    def test_orthographic_view_is_a_far_perspective(self):
        from verion_blender.viewport import View

        ortho = Matrix(((0.25, 0, 0, 0), (0, 0.25, 0, 0), (0, 0, -0.01, -1), (0, 0, 0, 1)))
        t, fov, shift = View(Matrix.Translation((0, -8, 0)) @ Matrix.Rotation(np.pi / 2, 4, "X"), ortho, 64, 64).camera()
        self.assertTrue(View(Matrix.Identity(4), ortho, 64, 64).orthographic)
        self.assertLess(fov, 0.01)


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
