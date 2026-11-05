#!/usr/bin/env python3
"""Procedural MatCap pictures (REQ-STY-012): a lit sphere seen head-on, as an sRGB PNG, using only the
standard library. `matcap_png(kind)` returns the bytes for kind clay, metal or toon; scripts/gen_showcase_scene.py
embeds them. Outside the disk the rim color is kept (the normal is clamped to the silhouette), so
bilinear lookups at the edge never blend in black.
Usage: gen_matcaps.py OUT_DIR   (writes clay.png, metal.png, toon.png)"""
import math, struct, sys, zlib
from pathlib import Path

SIZE = 128


def norm(v):
    n = math.sqrt(sum(c * c for c in v))
    return tuple(c / n for c in v)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def srgb(c):
    c = min(max(c, 0.0), 1.0)
    return int((12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055) * 255 + 0.5)


LIGHT = norm((-0.5, 0.6, 0.62))
HALF = norm((LIGHT[0], LIGHT[1], LIGHT[2] + 1.0))


def clay(n):
    diffuse = max(dot(n, LIGHT), 0.0)
    ambient = 0.14 + 0.08 * n[1]
    spec = 0.05 * max(dot(n, HALF), 0.0) ** 24
    base = (0.78, 0.72, 0.66)
    return tuple(c * (ambient + 0.82 * diffuse) + spec for c in base)


def metal(n):
    # What the sphere reflects: a bright sky, a dark horizon, a brown ground and a soft box top left.
    r = norm((2 * n[2] * n[0], 2 * n[2] * n[1], 2 * n[2] * n[2] - 1.0))
    sky = 0.25 + 0.75 * max(r[1], 0.0)
    ground = 0.10 + 0.12 * max(-r[1], 0.0)
    env = sky if r[1] > 0.0 else ground
    env *= 1.0 - 0.7 * math.exp(-((r[1]) / 0.06) ** 2)  # dark horizon line
    box = 2.2 if (-0.9 < r[0] < -0.2 and 0.35 < r[1] < 0.85 and r[2] > 0.0) else 0.0
    fresnel = 0.55 + 0.45 * (1.0 - n[2]) ** 3
    tint = (0.92, 0.94, 1.0)
    return tuple(t * (env + box) * fresnel for t in tint)


def toon(n):
    d = dot(n, LIGHT)
    if n[2] < 0.22:
        return (0.15, 0.07, 0.05)  # painted outline at the silhouette
    if dot(n, HALF) > 0.975:
        return (1.0, 0.97, 0.88)  # hard highlight
    bands = [(0.22, (0.30, 0.15, 0.12)), (0.55, (0.72, 0.40, 0.22)), (9.0, (0.98, 0.74, 0.46))]
    return next(c for t, c in bands if d < t)


KINDS = {"clay": clay, "metal": metal, "toon": toon}


def png_rgb(size, pixel):
    """PNG bytes of a size x size picture; pixel(x, y) gives linear RGB for x, y in -1..1 (+y up)."""
    rows = bytearray()
    for j in range(size):
        rows.append(0)  # PNG filter: none
        for i in range(size):
            rows.extend(srgb(c) for c in pixel(2 * (i + 0.5) / size - 1, 1 - 2 * (j + 0.5) / size))
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b""))


def matcap_png(kind):
    shade = KINDS[kind]

    def pixel(x, y):
        r2 = x * x + y * y
        if r2 > 0.999:  # outside the disk: the silhouette normal
            s = math.sqrt(r2)
            x, y, z = x / s * 0.9995, y / s * 0.9995, math.sqrt(1 - 0.9995 ** 2)
        else:
            z = math.sqrt(1 - r2)
        return shade((x, y, z))
    return png_rgb(SIZE, pixel)


def star_png():
    """A white five-pointed star on black, a hand-drawn highlight shape for stylizedSpecular."""
    def pixel(x, y):
        r, a = math.hypot(x, y), math.atan2(y, x) - math.pi / 2
        # Radius of the star outline at this angle: 0.9 at the points, 0.4 between them.
        k = abs(((a / (2 * math.pi / 5)) % 1) - 0.5) * 2
        return (1.0, 1.0, 1.0) if r < 0.4 + 0.5 * k ** 2 else (0.0, 0.0, 0.0)
    return png_rgb(64, pixel)


if __name__ == "__main__":
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for k in KINDS:
        (out / f"{k}.png").write_bytes(matcap_png(k))
