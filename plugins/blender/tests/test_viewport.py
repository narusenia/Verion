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

    def test_viewport_denoise_smooths_a_noisy_frame(self):
        from verion_blender import native
        from verion_blender.viewport import View, Viewport

        def noise(denoise):
            cam = make_scene()
            sc = bpy.context.scene
            sc.verion.viewport_samples = 4
            sc.verion.clean_samples = 4
            sc.verion.viewport_denoise = denoise
            dg = bpy.context.evaluated_depsgraph_get()  # before the view: it updates matrix_world
            view = View(cam.matrix_world, perspective(), 96, 96)
            vp = Viewport(native.load())
            try:
                vp.update(dg, view, sc.verion)
                self.assertTrue(wait_clean(vp))
                vp.job.wait(1.0)
                vp.poll()
                img = vp.image[2][..., :3].mean(axis=2)
            finally:
                vp.close()
            # Pixel-to-pixel difference: the noise a denoiser removes.
            return float(np.abs(np.diff(img, axis=1)).mean())

        raw, smooth = noise(False), noise(True)
        self.assertLess(smooth, 0.7 * raw, f"{smooth} vs {raw}")

    def test_resize_rebuilds_at_the_new_aspect(self):
        from verion_blender import native
        from verion_blender.viewport import View, Viewport

        cam = make_scene()
        sc = bpy.context.scene
        dg = bpy.context.evaluated_depsgraph_get()
        vp = Viewport(native.load())
        try:
            vp.update(dg, View(cam.matrix_world, perspective(), 96, 96), sc.verion)
            wide = View(cam.matrix_world, perspective(aspect=2.0), 192, 96)
            self.assertTrue(vp.resized(wide, sc.verion))
            vp.update(dg, wide, sc.verion)
            self.assertFalse(vp.resized(wide, sc.verion))
            self.assertTrue(wait_clean(vp))
            self.assertEqual(vp.image[2].shape, (96, 192, 4))
        finally:
            vp.close()

    def test_camera_move_renders_small_then_settles_to_full_size(self):
        from verion_blender import native, viewport
        from verion_blender.viewport import View, Viewport

        cam = make_scene()
        sc = bpy.context.scene
        dg = bpy.context.evaluated_depsgraph_get()
        vp = Viewport(native.load())
        old, viewport.SETTLE_S = viewport.SETTLE_S, 0.05
        try:
            vp.update(dg, View(cam.matrix_world, perspective(), 96, 96), sc.verion)
            self.assertTrue(wait_clean(vp))
            vp.set_view(View(cam.matrix_world, perspective(0.6), 96, 96), sc.verion)
            self.assertTrue(vp.moving)
            vp.stats.pop("clean_s", None)
            self.assertTrue(wait_clean(vp))
            self.assertEqual(vp.image[2].shape[:2], (24, 24))
            self.assertFalse(vp.resized(View(cam.matrix_world, perspective(0.6), 96, 96), sc.verion))
            time.sleep(0.1)
            self.assertTrue(vp.settle(sc.verion))
            self.assertFalse(vp.moving)
            self.assertTrue(wait_clean(vp))
            self.assertEqual(vp.image[2].shape[:2], (96, 96))
            # The option off: a move changes the camera only.
            sc.verion.viewport_fast_move = False
            vp.set_view(View(cam.matrix_world, perspective(0.9), 96, 96), sc.verion)
            self.assertFalse(vp.moving)
        finally:
            viewport.SETTLE_S = old
            vp.close()

    def test_orthographic_view_is_a_far_perspective(self):
        from verion_blender.viewport import View

        ortho = Matrix(((0.25, 0, 0, 0), (0, 0.25, 0, 0), (0, 0, -0.01, -1), (0, 0, 0, 1)))
        t, fov, shift = View(Matrix.Translation((0, -8, 0)) @ Matrix.Rotation(np.pi / 2, 4, "X"), ortho, 64, 64).camera()
        self.assertTrue(View(Matrix.Identity(4), ortho, 64, 64).orthographic)
        self.assertLess(fov, 0.01)


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
