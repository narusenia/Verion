"""Camera conversion against Cycles: sensor fit, lens, aspect and depth of field."""
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


def silhouette(engine, w, h, **cam):
    common.reset_scene()
    c = common.add_camera(location=(0, -8, 0), target=(0, 0, 0), lens=cam.get("lens", 50))
    c.data.sensor_fit = cam.get("fit", "AUTO")
    c.data.sensor_width = cam.get("sensor", 36.0)
    b = common.add_sphere(location=(0.7, 0, 0.3), radius=0.8, color=(0, 0, 0), roughness=1.0)
    b.data.materials[0].node_tree.nodes["Principled BSDF"].inputs["Specular IOR Level"].default_value = 0.0
    common.set_world((1, 1, 1), 1.0)
    a = common.render(engine, os.path.join(TMP, "cam.exr"), w, h, 8)
    return a.mean(axis=2) < 0.5


class CameraTests(unittest.TestCase):
    def test_sensor_fit_lens_and_aspect_match_cycles(self):
        for fit in ("AUTO", "HORIZONTAL", "VERTICAL"):
            for lens in (28.0, 50.0):
                for w, h in ((96, 64), (64, 96)):
                    with self.subTest(fit=fit, lens=lens, size=(w, h)):
                        cy = silhouette("CYCLES", w, h, fit=fit, lens=lens)
                        ve = silhouette("VERION", w, h, fit=fit, lens=lens)
                        self.assertGreater(cy.sum(), 20)
                        # Cycles filters the image (Blackman-Harris, 1.5 px) and Verion does not, so
                        # compare the size and the position of the silhouette, not its pixels.
                        yy, xx = np.mgrid[:h, :w]
                        centroid = lambda m: np.array([(xx * m).sum(), (yy * m).sum()]) / m.sum()
                        self.assertAlmostEqual(ve.sum() / cy.sum(), 1.0, delta=0.06)
                        np.testing.assert_allclose(centroid(ve), centroid(cy), atol=0.35)

    def test_lens_shift_matches_cycles(self):
        def sil(engine, sx, sy):
            common.reset_scene()
            c = common.add_camera(location=(0, -8, 0), target=(0, 0, 0), lens=50)
            c.data.shift_x, c.data.shift_y = sx, sy
            b = common.add_sphere(location=(0.7, 0, 0.3), radius=0.8, color=(0, 0, 0), roughness=1.0)
            common.set_world((1, 1, 1), 1.0)
            return common.render(engine, os.path.join(TMP, "shift.exr"), 96, 64, 8).mean(axis=2) < 0.5

        yy, xx = np.mgrid[:64, :96]
        for sx, sy in ((0.0, 0.0), (0.15, 0.0), (-0.1, 0.12)):
            with self.subTest(shift=(sx, sy)):
                cy, ve = sil("CYCLES", sx, sy), sil("VERION", sx, sy)
                self.assertGreater(cy.sum(), 20)
                centroid = lambda m: np.array([(xx * m).sum(), (yy * m).sum()]) / m.sum()
                np.testing.assert_allclose(centroid(ve), centroid(cy), atol=0.35)

    def test_depth_of_field_blur_matches_cycles(self):
        def spot(engine):
            common.reset_scene()
            c = common.add_camera(location=(0, -3, 0), target=(0, 0, 0), lens=100)
            c.data.sensor_width = 20.0
            c.data.dof.use_dof = True
            c.data.dof.focus_distance = 10.0      # well behind the spot: it is out of focus
            c.data.dof.aperture_fstop = 1.0
            b = common.add_sphere(location=(0, 0, 0), radius=0.05, color=(0, 0, 0))
            m = b.data.materials[0]
            em = m.node_tree.nodes["Principled BSDF"]
            em.inputs["Emission Color"].default_value = (1, 1, 1, 1)
            em.inputs["Emission Strength"].default_value = 200.0
            common.set_world((0, 0, 0), 0.0)
            return common.render(engine, os.path.join(TMP, "dof.exr"), 128, 128, 128).mean(axis=2)

        def radius(a):
            yy, xx = np.mgrid[: a.shape[0], : a.shape[1]]
            tot = a.sum()
            cy, cx = (a * yy).sum() / tot, (a * xx).sum() / tot
            return np.sqrt((a * ((yy - cy) ** 2 + (xx - cx) ** 2)).sum() / tot)

        cy, ve = spot("CYCLES"), spot("VERION")
        self.assertGreater(radius(cy), 2.0)  # really blurred
        self.assertAlmostEqual(radius(ve) / radius(cy), 1.0, delta=0.15)
        self.assertAlmostEqual(ve.sum() / cy.sum(), 1.0, delta=0.15)


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
