#!/usr/bin/env python3
"""Procedural equirectangular HDRIs (Radiance .hdr, standard library only) for checking lighting without
third-party images: sunny (sun and sky), sunset (low warm sun), overcast (sky gradient, no sun), softbox (one
broad soft light) and uniform (a white furnace). +y is up; the rows run from the zenith down.
Usage: gen_hdri.py OUT_DIR"""
import math, sys
from pathlib import Path


def norm(v):
    n = math.sqrt(sum(c * c for c in v))
    return tuple(c / n for c in v)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def rgbe(r, g, b):
    m = max(r, g, b)
    if m < 1e-32:
        return bytes((0, 0, 0, 0))
    f, e = math.frexp(m)
    k = f * 256.0 / m
    return bytes((int(r * k), int(g * k), int(b * k), e + 128))


def write(path, w, h, fn):
    with open(path, "wb") as f:
        f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % (h, w))
        for y in range(h):
            theta = (y + 0.5) / h * math.pi  # 0 = zenith
            for x in range(w):
                phi = (x + 0.5) / w * 2 * math.pi
                f.write(rgbe(*fn((math.sin(theta) * math.cos(phi), math.cos(theta), math.sin(theta) * math.sin(phi)))))


def sky(d, zenith, horizon, ground):
    t = max(d[1], 0.0) ** 0.6
    if d[1] < 0:
        return ground
    return tuple(h + (z - h) * t for z, h in zip(zenith, horizon))


def sun(direction, radius, radiance):
    sd = norm(direction)
    cos_r = math.cos(radius)
    return lambda d: radiance if dot(d, sd) > cos_r else (0.0, 0.0, 0.0)


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sunny(d):
    s = sun((0.5, 0.6, 0.62), 0.045, (400.0, 370.0, 320.0))
    return add(sky(d, (0.25, 0.45, 1.0), (0.8, 0.9, 1.0), (0.25, 0.23, 0.2)), s(d))


def sunset(d):
    s = sun((-0.8, 0.12, 0.5), 0.06, (500.0, 220.0, 80.0))
    glow = max(dot(d, norm((-0.8, 0.12, 0.5))), 0.0) ** 8
    base = sky(d, (0.05, 0.1, 0.3), (0.9, 0.45, 0.25), (0.1, 0.07, 0.06))
    return add(add(base, tuple(g * glow for g in (1.2, 0.5, 0.2))), s(d))


def overcast(d):
    return sky(d, (0.9, 0.95, 1.05), (0.45, 0.47, 0.5), (0.15, 0.15, 0.15))


def softbox(d):
    w = math.exp(4.0 * (dot(d, norm((-0.5, 0.7, 0.5))) - 1.0))
    return (0.15 + 3.0 * w, 0.15 + 2.9 * w, 0.15 + 2.6 * w)


KINDS = {  # name: (width, height, function)
    "sunny": (256, 128, sunny), "sunset": (256, 128, sunset), "overcast": (128, 64, overcast),
    "softbox": (128, 64, softbox), "uniform": (32, 16, lambda d: (1.0, 1.0, 1.0)),
}

if __name__ == "__main__":
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for name, (w, h, fn) in KINDS.items():
        write(out / f"{name}.hdr", w, h, fn)
