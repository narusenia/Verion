"""Final render: passes, the non-physical mark in the saved EXR, denoising, the render border."""
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


def scene():
    common.reset_scene()
    common.add_camera()
    common.add_plane()
    common.add_sphere()
    common.add_light("AREA", location=(2, -2, 4), energy=800).data.size = 2.0
    common.set_world((0.2, 0.25, 0.3), 1.0)


def render(**kw):
    scene()
    sc = bpy.context.scene
    for k, v in kw.items():
        obj = sc.verion if hasattr(sc.verion, k) else sc.render
        setattr(obj, k, v)
    return common.render("VERION", os.path.join(TMP, "final.exr"), 96, 72, 16)


def exr_header(path):
    with open(path, "rb") as f:
        return f.read(65536)


class FinalTests(unittest.TestCase):
    def test_reference_is_marked_physical_and_others_are_not(self):
        render()
        self.assertIn(b"Verion Physical", exr_header(os.path.join(TMP, "final.exr")))
        self.assertIn(b"true", exr_header(os.path.join(TMP, "final.exr")))
        render(mode="STYLIZED")
        h = exr_header(os.path.join(TMP, "final.exr"))
        self.assertIn(b"Verion Physical", h)
        self.assertIn(b"false", h)
        self.assertIn(b"stylized", h)
        render(adaptive=True)
        self.assertIn(b"Verion Adaptive Threshold", exr_header(os.path.join(TMP, "final.exr")))

    def test_pass_arrays(self):
        from verion_blender import engine, native

        nat = native.load()
        s = nat.Scene()
        import numpy as np

        s.add_instance(
            s.add_mesh(np.array([[-1, 0, -1], [1, 0, -1], [0, 0, 1]], np.float32), np.array([0, 2, 1], np.uint32), np.array([[0, 1, 0]] * 3, np.float32)),
            s.add_material(base_color=[0.5] * 3), np.eye(4, dtype=np.float32))
        s.add_light("environment", color=(1, 1, 1))
        t = np.eye(4, dtype=np.float32)
        t[1, 3], t[2, 3] = 3.0, 0.0
        r = np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]], np.float32)  # look down -y
        t[:3, :3] = r
        s.set_camera(t, 0.8, 3.0)
        e = nat.Engine(s)
        res = e.start(dict(width=16, height=16, spp=4, lighting_aovs=True)).result()
        e.close()
        names = {p[0] for p in engine.PASSES}
        arrays = engine.pass_arrays(res, names | {"Combined"})
        self.assertEqual(arrays["Combined"][1].shape, (16, 16, 4))
        for name, chan, n, key, flag in engine.PASSES:
            self.assertIn(name, arrays, name)
            self.assertEqual(arrays[name][1].shape, (16, 16, n), name)

    def test_denoise_runs_and_is_marked(self):
        a = render(denoise=True)
        self.assertGreater(a.mean(), 0.05)
        self.assertIn(b"oidn", exr_header(os.path.join(TMP, "final.exr")))

    @unittest.skipUnless(sys.platform == "darwin", "the Metal device of OIDN")
    def test_denoise_on_the_gpu_device_blender_ships(self):
        cpu = render(denoise=True, denoise_device="CPU")
        gpu = render(denoise=True, denoise_device="METAL")
        self.assertGreater(gpu.mean(), 0.05)
        self.assertTrue(0.9 < gpu.mean() / cpu.mean() < 1.1, f"{gpu.mean()} vs {cpu.mean()}")

    def test_render_border_keeps_the_frame_size(self):
        a = render(use_border=True, border_min_x=0.25, border_max_x=0.75, border_min_y=0.25, border_max_y=0.75)
        self.assertEqual(a.shape[:2], (72, 96))
        self.assertGreater(a[30:40, 40:56].mean(), 0.02)   # inside the border
        self.assertEqual(float(a[:10].max()), 0.0)          # outside it: not rendered


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])


class CryptomatteTests(unittest.TestCase):
    def test_hash_matches_the_reference_vectors(self):
        from verion_blender import cryptomatte as c

        self.assertEqual(c.murmur3_32(b"test"), 0xBA6BD213)
        self.assertEqual(c.murmur3_32(b"Hello, world!", 0x9747B28C), 0x24884CBA)
        import struct

        bits = struct.unpack("<I", struct.pack("<f", c.hash_float("ball")))[0]
        self.assertNotIn((bits >> 23) & 255, (0, 255))  # a finite, normal float

    def test_ids_and_manifest_reach_the_exr(self):
        from verion_blender import cryptomatte as c

        scene()
        sc = bpy.context.scene
        sc.view_layers[0].use_pass_cryptomatte_object = True
        sc.view_layers[0].use_pass_cryptomatte_material = True
        common.render("VERION", os.path.join(TMP, "crypto.exr"), 64, 48, 4)
        h = exr_header(os.path.join(TMP, "crypto.exr"))
        self.assertIn(b"MurmurHash3_32", h)
        self.assertIn(b"uint32_to_float32", h)
        self.assertIn(b'"ball":"%08x"' % c._bits("ball"), h)
        self.assertIn(b"CryptoObject00", h)
