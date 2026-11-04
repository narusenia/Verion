"""Renders the render_ppm example scene with Mitsuba 3 and compares it with Verion's render.exr.

Usage: mise exec -- ~/.local/share/mise/installs/pipx-mitsuba/3.7.1/mitsuba/bin/python \
           scripts/mitsuba_cornell.py [out_dir] [width] [height] [spp]
out_dir must hold the render.exr written by the example (cargo run --release -p verion-gpu-metal
--example render_ppm -- out_dir w h spp). Writes out_dir/mitsuba.exr.
Differences from Verion: Mitsuba's analytic spheres versus Verion's icospheres.
"""

import math
import sys
from pathlib import Path

import mitsuba as mi

mi.set_variant("scalar_rgb")
T = mi.ScalarTransform4f

out = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
w, h, spp = (int(a) for a in sys.argv[2:5]) if len(sys.argv) > 4 else (512, 384, 256)


def diffuse(rgb):
    return {"type": "twosided", "bsdf": {"type": "diffuse", "reflectance": {"type": "rgb", "value": rgb}}}


def quad(bsdf, center, rot_axis, rot_deg, half=2.0, emitter=None):
    shape = {
        "type": "rectangle",
        "to_world": T().translate(center).rotate(rot_axis, rot_deg).scale(half),
        "bsdf": bsdf,
    }
    if emitter is not None:
        shape["emitter"] = {"type": "area", "radiance": {"type": "rgb", "value": emitter}}
    return shape


grey = diffuse([0.75] * 3)
scene = mi.load_dict(
    {
        "type": "scene",
        "integrator": {"type": "path", "max_depth": 8},
        "sensor": {
            "type": "perspective",
            "fov_axis": "y",
            "fov": math.degrees(0.9),
            "to_world": T().look_at(origin=[0, 0, 6], target=[0, 0, 0], up=[0, 1, 0]),
            "film": {"type": "hdrfilm", "width": w, "height": h, "pixel_format": "rgb",
                     "rfilter": {"type": "box"}},
            "sampler": {"type": "independent", "sample_count": spp},
        },
        "floor": quad(grey, [0, -2, 0], [1, 0, 0], -90),
        "ceiling": quad(grey, [0, 2, 0], [1, 0, 0], 90),
        "back": quad(grey, [0, 0, -2], [0, 1, 0], 0),
        "left": quad(diffuse([0.75, 0.15, 0.15]), [-2, 0, 0], [0, 1, 0], 90),
        "right": quad(diffuse([0.15, 0.6, 0.15]), [2, 0, 0], [0, 1, 0], -90),
        "light": quad(diffuse([0.0] * 3), [0, 1.99, 0], [1, 0, 0], 90, half=0.6, emitter=[14.0] * 3),
        "gold": {
            "type": "sphere",
            "center": [-0.9, -1.3, -0.6],
            "radius": 0.7,
            "bsdf": {"type": "principled", "base_color": {"type": "rgb", "value": [1.0, 0.78, 0.34]},
                     "metallic": 1.0, "roughness": 0.2},
        },
        "glass": {
            "type": "sphere",
            "center": [0.9, -1.3, 0.3],
            "radius": 0.7,
            "bsdf": {"type": "principled", "base_color": {"type": "rgb", "value": [1.0] * 3},
                     "roughness": 0.0, "spec_trans": 1.0, "eta": 1.5},
        },
        "point": {"type": "point", "position": [0, 1, 1.5],
                  "intensity": {"type": "rgb", "value": [1.5, 1.425, 1.35]}},
    }
)

image = mi.render(scene)
mi.util.write_bitmap(str(out / "mitsuba.exr"), image)


def beauty(path):
    # Flat [r, g, b, ...] of the root layer (Verion's EXR also carries the N layer).
    root = dict(mi.Bitmap(str(path)).split())["<root>"]
    return list(mi.TensorXf(root).array)


verion = beauty(out / "render.exr")
mine, ref = ([c[i::3] for i in range(3)] for c in (list(image.array), verion))
mean = lambda v: sum(v) / len(v)  # noqa: E731
mm, mv = [mean(c) for c in mine], [mean(c) for c in ref]
print("mean RGB  mitsuba", [round(x, 4) for x in mm], " verion", [round(x, 4) for x in mv],
      " ratio", [round(b / a, 4) for a, b in zip(mm, mv)])
abs_err = mean([abs(a - b) for m, r in zip(mine, ref) for a, b in zip(m, r)])
print(f"mean abs error / mean radiance: {abs_err / mean(mm):.4f} (noise floor falls with 1/sqrt(spp))")
