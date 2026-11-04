#!/usr/bin/env python3
"""Writes the REQ-PERF-003 scale scene: a ~5M-triangle UV sphere on a ground plane with four 4K PNG
textures (base colour, normal, metallic-roughness, ground colour). Too big to commit, so bench.sh
generates it under target/. Usage: gen_scale_scene.py OUT_DIR"""
import json, math, os, struct, sys, zlib
from array import array

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
LAT, LON, TEX = 1250, 2000, 4096  # 2 * LAT * LON = 5.0M triangles


def png(path, tile_fn):
    # shortcut: a 256x256 tile repeated, so the PNG is small to write but is 4096x4096 once decoded
    tile = [bytes(c for x in range(256) for c in tile_fn(x, y)) for y in range(256)]
    rows = b"".join(b"\0" + t * (TEX // 256) for t in tile)
    raw = rows * (TEX // 256)
    def chunk(k, d):
        c = struct.pack(">I", len(d)) + k + d
        return c + struct.pack(">I", zlib.crc32(k + d))
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", TEX, TEX, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 1)) + chunk(b"IEND", b""))


def clamp(v):
    return max(0, min(255, int(v)))


png(f"{out}/base.png", lambda x, y: (clamp(128 + 100 * math.sin(x / 9)), clamp(128 + 100 * math.sin(y / 7)), 90))
png(f"{out}/normal.png", lambda x, y: (clamp(128 + 40 * math.sin(x / 5)), clamp(128 + 40 * math.sin(y / 5)), 230))
png(f"{out}/mr.png", lambda x, y: (0, clamp(140 + 80 * math.sin((x + y) / 11)), clamp(60 + 40 * math.sin(x / 13))))
png(f"{out}/ground.png", lambda x, y: ((200, 200, 200) if (x // 32 + y // 32) % 2 else (90, 90, 90)))

pos, nrm, uv, idx = array("f"), array("f"), array("f"), array("I")
for i in range(LAT + 1):
    th = math.pi * i / LAT
    for j in range(LON + 1):
        ph = 2 * math.pi * j / LON
        n = (math.sin(th) * math.cos(ph), math.cos(th), math.sin(th) * math.sin(ph))
        pos.extend((n[0], n[1] + 1.0, n[2]))
        nrm.extend(n)
        uv.extend((j / LON * 8, i / LAT * 4))
for i in range(LAT):
    for j in range(LON):
        a = i * (LON + 1) + j
        b = a + LON + 1
        idx.extend((a, b, a + 1, a + 1, b, b + 1))
nv = (LAT + 1) * (LON + 1)
gp = array("f", [-6, 0, -6, -6, 0, 6, 6, 0, 6, 6, 0, -6])
gn = array("f", [0, 1, 0] * 4)
gu = array("f", [0, 0, 0, 6, 6, 6, 6, 0])
gi = array("I", [0, 1, 2, 0, 2, 3])
chunks = [pos, nrm, uv, idx, gp, gn, gu, gi]
with open(f"{out}/scale.bin", "wb") as f:
    for c in chunks:
        f.write(c.tobytes())
off, views = 0, []
for c in chunks:
    n = len(c) * c.itemsize
    views.append({"buffer": 0, "byteOffset": off, "byteLength": n})
    off += n
mm = lambda a, k: [min(a[i] for i in range(k, len(a), 3)), max(a[i] for i in range(k, len(a), 3))]
def acc(v, t, count, ct=5126, **kw):
    return {"bufferView": v, "componentType": ct, "count": count, "type": t, **kw}
accessors = [
    acc(0, "VEC3", nv, min=[-1, 0, -1], max=[1, 2, 1]), acc(1, "VEC3", nv), acc(2, "VEC2", nv),
    acc(3, "SCALAR", len(idx), 5125),
    acc(4, "VEC3", 4, min=[-6, 0, -6], max=[6, 0, 6]), acc(5, "VEC3", 4), acc(6, "VEC2", 4),
    acc(7, "SCALAR", 6, 5125),
]
g = {
    "asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0, 1, 2]}],
    "extensionsUsed": ["KHR_lights_punctual"],
    "extensions": {"KHR_lights_punctual": {"lights": [{"type": "point", "color": [1, 1, 1], "intensity": 600}]}},
    "nodes": [{"mesh": 0}, {"mesh": 1}, {"translation": [3, 6, 4], "extensions": {"KHR_lights_punctual": {"light": 0}}}],
    "meshes": [
        {"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3, "material": 0}]},
        {"primitives": [{"attributes": {"POSITION": 4, "NORMAL": 5, "TEXCOORD_0": 6}, "indices": 7, "material": 1}]},
    ],
    "materials": [
        {"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicRoughnessTexture": {"index": 2}},
         "normalTexture": {"index": 1}},
        {"pbrMetallicRoughness": {"baseColorTexture": {"index": 3}, "metallicFactor": 0, "roughnessFactor": 1}},
    ],
    "textures": [{"source": i} for i in range(4)],
    "images": [{"uri": n} for n in ("base.png", "normal.png", "mr.png", "ground.png")],
    "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": off, "uri": "scale.bin"}],
}
json.dump(g, open(f"{out}/scale.gltf", "w"))
print(f"{2 * LAT * LON} triangles, 4 textures {TEX}x{TEX} -> {out}/scale.gltf")
