"""GPU tests of the `verion` extension (needs a GPU with ray tracing; not run in CI).

Run with scripts/py_test.sh, which builds the extension and runs this under a plain Python and
under the Python of each Blender in ~/Applications/Blender/stable.
"""
import base64
import json
import os
import struct
import tempfile
import unittest

import numpy as np

import verion

W, H, SPP = 96, 72, 8


def uv_sphere(rings=24, segs=48):
    pos, nrm, idx = [], [], []
    for i in range(rings + 1):
        th = np.pi * i / rings
        for j in range(segs + 1):
            ph = 2 * np.pi * j / segs
            n = (np.sin(th) * np.cos(ph), np.cos(th), np.sin(th) * np.sin(ph))
            pos.append(n)
            nrm.append(n)
    for i in range(rings):
        for j in range(segs):
            a = i * (segs + 1) + j
            b = a + segs + 1
            idx += [a, b, a + 1, a + 1, b, b + 1]
    return (np.array(pos, np.float32), np.array(nrm, np.float32), np.array(idx, np.uint32))


def quad():
    pos = np.array([[-4, 0, -4], [4, 0, -4], [4, 0, 4], [-4, 0, 4]], np.float32)
    nrm = np.tile(np.array([0, 1, 0], np.float32), (4, 1))
    return pos, nrm, np.array([0, 2, 1, 0, 3, 2], np.uint32)


def translation(x, y, z):
    m = np.eye(4, dtype=np.float32)
    m[:3, 3] = (x, y, z)
    return m


CAM = translation(0, 1.2, 4.0)
FOV = 0.8
LIGHT_POS, LIGHT_COLOR, LIGHT_I = (2.0, 3.0, 2.0), (1.0, 0.9, 0.8), 60.0
SKY = (0.1, 0.12, 0.15)
FLOOR = dict(base_color=[0.6, 0.6, 0.6], metallic=0.0, roughness=0.8)
BALL = dict(base_color=[0.8, 0.2, 0.1], metallic=0.0, roughness=0.35)


def build_scene():
    s = verion.Scene()
    fm = s.add_material(**FLOOR)
    bm = s.add_material(**BALL)
    p, n, i = quad()
    s.add_instance(s.add_mesh(p, i, n), fm, translation(0, 0, 0))
    p, n, i = uv_sphere()
    s.add_instance(s.add_mesh(p, i, n), bm, translation(0, 1, 0))
    s.add_light("point", color=LIGHT_COLOR, intensity=LIGHT_I, position=LIGHT_POS)
    s.add_light("environment", color=SKY)
    s.set_camera(CAM, FOV, 4.0)
    return s


def write_gltf(path):
    """The same scene as a glTF file, to compare the builder with the importer."""
    blobs, views, accs, meshes = b"", [], [], []

    def add(arr, comp, kind, target):
        nonlocal blobs
        data = arr.tobytes()
        views.append({"buffer": 0, "byteOffset": len(blobs), "byteLength": len(data), "target": target})
        blobs += data + b"\0" * (-len(data) % 4)
        a = {"bufferView": len(views) - 1, "componentType": comp, "count": len(arr), "type": kind}
        if kind == "VEC3" and comp == 5126:
            a["min"], a["max"] = arr.min(0).tolist(), arr.max(0).tolist()
        accs.append(a)
        return len(accs) - 1

    for (p, n, i), mat in ((quad(), 0), (uv_sphere(), 1)):
        meshes.append({"primitives": [{
            "attributes": {"POSITION": add(p, 5126, "VEC3", 34962), "NORMAL": add(n, 5126, "VEC3", 34962)},
            "indices": add(i, 5125, "SCALAR", 34963), "material": mat}]})
    mat = lambda d: {"pbrMetallicRoughness": {
        "baseColorFactor": d["base_color"] + [1], "metallicFactor": d["metallic"], "roughnessFactor": d["roughness"]}}
    flat = lambda m: m.T.flatten().tolist()  # glTF matrices are column-major
    doc = {
        "asset": {"version": "2.0"},
        "extensionsUsed": ["KHR_lights_punctual"],
        "extensions": {"KHR_lights_punctual": {"lights": [
            {"type": "point", "color": list(LIGHT_COLOR), "intensity": LIGHT_I}]}},
        "scene": 0, "scenes": [{"nodes": [0, 1, 2, 3]}],
        "nodes": [
            {"mesh": 0}, {"mesh": 1, "matrix": flat(translation(0, 1, 0))},
            {"extensions": {"KHR_lights_punctual": {"light": 0}}, "translation": list(LIGHT_POS)},
            {"camera": 0, "matrix": flat(CAM)}],
        "cameras": [{"type": "perspective", "perspective": {"yfov": FOV, "znear": 0.1, "aspectRatio": W / H}}],
        "materials": [mat(FLOOR), mat(BALL)], "meshes": meshes,
        "accessors": accs, "bufferViews": views,
        "buffers": [{"byteLength": len(blobs), "uri": "data:application/octet-stream;base64," + base64.b64encode(blobs).decode()}],
    }
    with open(path, "w") as f:
        json.dump(doc, f)


def render(scene, **kw):
    settings = dict(width=W, height=H, spp=SPP)
    settings.update(kw)
    eng = verion.Engine(scene)
    try:
        return eng.start(settings).result()
    finally:
        eng.close()


class RenderTests(unittest.TestCase):
    def test_builder_matches_the_gltf_importer(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "scene.gltf")
            write_gltf(path)
            imported = verion.Scene.from_gltf(path)
        imported.add_light("environment", color=SKY)  # glTF has no ambient light
        a, b = render(build_scene()), render(imported)
        for name in ("combined", "normal", "albedo", "depth"):
            self.assertEqual(a[name].shape, b[name].shape, name)
        self.assertEqual(a["combined"].shape, (H, W, 3))
        self.assertGreater(a["combined"].mean(), 0.05)
        diff = np.abs(a["combined"] - b["combined"]).mean() / a["combined"].mean()
        self.assertLess(diff, 1e-4, f"builder and importer differ by {diff}")
        np.testing.assert_allclose(a["depth"], b["depth"], rtol=1e-4, atol=1e-4)

    def test_aovs_ids_and_info(self):
        r = render(build_scene())
        self.assertTrue(r["info"]["physical"])
        self.assertEqual(r["info"]["samples"], SPP)
        self.assertEqual(set(np.unique(r["object_id"])), {0, 1, 2})  # sky, floor, ball
        self.assertEqual(r["depth"].dtype, np.float32)

    def test_modes_mark_non_physical(self):
        r = render(build_scene(), mode="interactive")
        self.assertFalse(r["info"]["physical"])
        r = render(build_scene(), adaptive={"threshold": 0.05})
        self.assertFalse(r["info"]["physical"])
        with self.assertRaises(ValueError):
            render(build_scene(), restir={})  # biased: not allowed in reference mode
        with self.assertRaises(ValueError):
            render(build_scene(), bogus=1)

    def test_stylized_returns_the_lighting_split(self):
        s = build_scene()
        s.set_material(1, **BALL, stylization=json.dumps({
            "hybridSurface": {"diffuse": 1.0, "shadow": 1.0},
            "toonRamp": {"thresholds": [0.3, 0.7], "palette": [[0.3] * 3, [0.7] * 3, [1.0] * 3]}}))
        r = render(s, mode="stylized")
        self.assertIn("direct_diffuse", r)
        base = render(build_scene(), mode="stylized")
        self.assertGreater(np.abs(r["combined"] - base["combined"]).mean(), 1e-3)

    def test_scene_edits_reach_the_next_job(self):
        s = build_scene()
        eng = verion.Engine(s)
        try:
            before = eng.start(dict(width=W, height=H, spp=SPP)).result()
            s.set_instance(1, 1, 1, translation(0, 1, -2.0))  # the ball moves away
            after = eng.start(dict(width=W, height=H, spp=SPP)).result()
        finally:
            eng.close()
        self.assertGreater(np.abs(before["depth"] - after["depth"]).max(), 1.0)

    def test_cancel_returns_what_was_reached(self):
        eng = verion.Engine(build_scene())
        try:
            job = eng.start(dict(width=W, height=H, spp=100000))
            while job.samples() == 0 and not job.done():
                job.wait(0.01)
            job.cancel()
            r = job.result()
        finally:
            eng.close()
        self.assertLess(r["info"]["samples"], 100000)
        self.assertGreater(r["info"]["samples"], 0)

    def test_interactive_job_follows_edits(self):
        s = build_scene()
        eng = verion.Engine(s)
        try:
            job = eng.start(dict(width=W, height=H, spp=64, mode="interactive", clean_spp=8), interactive=True)
            seen = None
            for _ in range(500):
                job.wait(0.01)
                seen = job.latest() or seen
                if job.stats()["clean_s"] is not None:
                    break
            self.assertIsNotNone(seen)
            self.assertEqual(seen[2].shape, (H, W, 4))
            s.set_light(0, "point", color=LIGHT_COLOR, intensity=LIGHT_I * 2, position=LIGHT_POS)
            for _ in range(500):
                job.wait(0.01)
                if job.stats()["edits"] >= 1 and job.stats()["clean_s"] is not None:
                    break
            st = job.stats()
            self.assertGreaterEqual(st["edits"], 1)
            self.assertIsNotNone(st["clean_s"])
            job.cancel()
            job.result()
        finally:
            eng.close()

    def test_bad_input_is_a_python_error(self):
        s = verion.Scene()
        with self.assertRaises(ValueError):
            s.add_mesh(np.zeros((3, 3), np.float32), np.array([0, 1, 5], np.uint32))
        with self.assertRaises(IndexError):
            s.add_instance(0, 0, np.eye(4, dtype=np.float32))
        with self.assertRaises(ValueError):
            s.add_material(nonsense=1)


if __name__ == "__main__":
    unittest.main()
