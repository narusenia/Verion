"""Verion against Cycles on a diffuse plane lit by each light type.

The two renderers' diffuse-plus-specular BSDFs differ by about 3% at normal incidence (Verion
layers the dielectric specular over the diffuse differently), so the tolerance is 6%: a wrong unit
factor is off by 3x or more.
"""
import os
import sys
import tempfile
import unittest

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

common.enable_addon()
H = 4.0
ALBEDO = 0.8
CASES = [
    ("point", "POINT", dict(energy=1000.0, shadow_soft_size=0.0)),
    ("spot", "SPOT", dict(energy=1000.0, shadow_soft_size=0.0, spot_size=np.radians(120), spot_blend=0.0)),
    ("sun", "SUN", dict(energy=3.0)),
    ("area square", "AREA", dict(energy=1000.0, shape="SQUARE", size=1.0)),
    ("area rectangle", "AREA", dict(energy=1000.0, shape="RECTANGLE", size=2.0, size_y=0.5)),
    ("area disk", "AREA", dict(energy=1000.0, shape="DISK", size=1.5)),
]


def centre(a):
    h, w = a.shape[:2]
    return float(a[h // 2 - 2 : h // 2 + 2, w // 2 - 2 : w // 2 + 2].mean())


def setup(kind, props):
    common.reset_scene()
    common.add_plane(size=40, color=(ALBEDO,) * 3)
    cam = common.add_camera(location=(0, 0, 2.0), target=(0, 0.0001, 0), lens=50)
    cam.data.sensor_width = 8.0
    light = common.add_light(kind, location=(0, 0, H), energy=props["energy"])
    for k, v in props.items():
        if k != "energy":
            setattr(light.data, k, v)
    common.set_world((0, 0, 0), 0.0)


def measure(kind, props, engine):
    setup(kind, props)
    return centre(common.render(engine, os.path.join(tempfile.gettempdir(), "light_units.exr"), 32, 32, 64))


class LightUnits(unittest.TestCase):
    def test_each_light_type_matches_cycles(self):
        for name, kind, props in CASES:
            with self.subTest(name):
                cycles = measure(kind, props, "CYCLES")
                verion = measure(kind, props, "VERION")
                ratio = verion / cycles
                print(f"LIGHT {name}: verion/cycles = {ratio:.4f}")
                self.assertAlmostEqual(ratio, 1.0, delta=0.06)


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
