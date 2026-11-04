"""Renders the render_ppm example scene with Mitsuba 3 and compares it with Verion's render.exr.

Usage: mise exec -- ~/.local/share/mise/installs/pipx-mitsuba/3.7.1/mitsuba/bin/python \
           scripts/mitsuba_cornell.py [out_dir] [width] [height] [spp] [walls|hdri|spot|normalmap]
out_dir must hold the render.exr written by the example (cargo run --release -p verion-gpu-metal
--example render_ppm -- out_dir w h spp). Writes out_dir/mitsuba.exr.
`walls` leaves out the spheres, `hdri` swaps the box for a floor under out_dir/env.exr (pass the same
mode to the example, which writes env.exr); `spot` uses the same floor with one spot light, `normalmap` adds the
example's normal.exr on a 6x6 floor.
Differences from Verion: Mitsuba's analytic spheres versus Verion's icospheres.
"""

import array
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
desc = (
    {
        "type": "scene",
        # Verion: 8 iterations, each a hit (emission) plus a light-sampling segment = 9 segments.
        "integrator": {"type": "path", "max_depth": 9},
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
        # Verion emits from both faces; Mitsuba's area emitter is one-sided, so a copy just above the light faces the ceiling.
        "light_back": quad(diffuse([0.0] * 3), [0, 1.9901, 0], [1, 0, 0], -90, half=0.6, emitter=[14.0] * 3),
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
mode = sys.argv[5] if len(sys.argv) > 5 else ""
if mode == "walls":
    del desc["gold"], desc["glass"]
elif mode in ("hdri", "spot", "normalmap"):
    for k in ("ceiling", "back", "left", "right", "light", "light_back", "point"):
        del desc[k]
    desc["floor"] = quad(grey, [0, -2, 0], [1, 0, 0], -90, half=20.0)
    # Mitsuba's lat-long mapping is Verion's turned 180 degrees about +y (found by rendering a sun).
if mode in ("spot", "normalmap"):
    # Half-angles 0.5 / 0.49 rad as in the example; the thin falloff band makes the edge near hard.
    desc["spot"] = {"type": "spot", "cutoff_angle": math.degrees(0.5), "beam_width": math.degrees(0.49),
                    "intensity": {"type": "rgb", "value": [40.0, 38.0, 36.0]},
                    "to_world": T().look_at(origin=[2, 4, 3], target=[0, -1.3, 0], up=[0, 1, 0])}
if mode == "normalmap":
    desc["floor"] = quad(
        {"type": "normalmap",
         # Mitsuba's v runs up the image, Verion's down.
         "normalmap": {"type": "bitmap", "raw": True, "filename": str(out / "normal.exr"),
                        "to_uv": T().translate([0, 1, 0]).scale([1, -1, 1])},
         "bsdf": grey},
        [0, -2, 0], [1, 0, 0], -90, half=3.0)
elif mode == "hdri":
    desc["env"] = {"type": "envmap", "filename": str(out / "env.exr"),
                   "to_world": T().rotate([0, 1, 0], 180)}
scene = mi.load_dict(desc)

image = mi.render(scene)
mi.util.write_bitmap(str(out / "mitsuba.exr"), image)


def beauty(path):
    # Flat [r, g, b, ...] of the root layer. Verion's EXR also carries Z and ObjectId there (more
    # than 3 channels), plus the N and Albedo layers, so take only the first three channels.
    t = mi.TensorXf(dict(mi.Bitmap(str(path)).split())["<root>"])
    n, data = t.shape[2], list(t.array)
    return [data[i + c] for i in range(0, len(data), n) for c in range(3)]


verion = beauty(out / "render.exr")
# RGB-only copy for FLIP, whose CLI wants both images in the same plain format.
mi.util.write_bitmap(str(out / "verion_rgb.exr"), mi.TensorXf(array.array("f", verion), shape=(h, w, 3)))
mine, ref = ([c[i::3] for i in range(3)] for c in (list(image.array), verion))
mean = lambda v: sum(v) / len(v)  # noqa: E731
mm, mv = [mean(c) for c in mine], [mean(c) for c in ref]
print("mean RGB  mitsuba", [round(x, 4) for x in mm], " verion", [round(x, 4) for x in mv],
      " ratio", [round(b / a, 4) for a, b in zip(mm, mv)])
abs_err = mean([abs(a - b) for m, r in zip(mine, ref) for a, b in zip(m, r)])
print(f"mean abs error / mean radiance: {abs_err / mean(mm):.4f} (noise floor falls with 1/sqrt(spp))")
worst = max(abs(b / a - 1) for a, b in zip(mm, mv))
print(f"worst channel deviation {worst:.2%} (limit 1%)")

# Block means catch what the global mean hides, e.g. a mirrored or rotated environment map.
n = 4
bw, bh = w // n, h // n
worst_block = 0.0
for by in range(n):
    for bx in range(n):
        idx = [(by * bh + y) * w + bx * bw + x for y in range(bh) for x in range(bw)]
        a = mean([c[i] for c in mine for i in idx])
        b = mean([c[i] for c in ref for i in idx])
        if max(a, b) > 0.05 * mean(mm):  # skip near-black blocks (background, thin cone edges)
            worst_block = max(worst_block, abs(b / a - 1) if a else float("inf"))
print(f"worst {n}x{n} block mean deviation (blocks above 5% of mean radiance) {worst_block:.2%} (limit 2%)")

# PSNR against Mitsuba's render over the peak radiance; noise-dominated, so reported but not gated.
mse = mean([(a - b) ** 2 for m, r in zip(mine, ref) for a, b in zip(m, r)])
peak = max(max(c) for c in mine)
print(f"PSNR {10 * math.log10(peak * peak / mse):.1f} dB (peak {peak:.2f}; reported only)")

ok = worst <= 0.01 and worst_block <= 0.02
print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
