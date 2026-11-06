#!/usr/bin/env python3
"""Writes scenes/many_lights.gltf: a 6 x 3 x 6 room lit only by 256 small emissive panels of different sizes under the
ceiling (the many-light case ReSTIR DI is for, REQ-ACC-002), with three rough spheres and a slab that shadows part of
the floor. The geometry is embedded. Usage: gen_many_lights_scene.py OUT_FILE [dark]
`dark` gives the walls 0.1 albedo so direct light dominates the image (indirect light is the same noise either way).
"""
import base64, json, math, random, struct, sys

from gen_cornell_scene import quad
from gen_showcase_scene import sphere


def main(path, dark=False):
    rnd = random.Random(7)
    materials = {
        "wall": {"name": "wall", "pbrMetallicRoughness": {"baseColorFactor": [0.1, 0.1, 0.1, 1] if dark else [0.72, 0.7, 0.66, 1], "metallicFactor": 0, "roughnessFactor": 1}},
        "ball": {"name": "ball", "pbrMetallicRoughness": {"baseColorFactor": [0.8, 0.3, 0.2, 1], "metallicFactor": 0, "roughnessFactor": 0.6}},
        "metal": {"name": "metal", "pbrMetallicRoughness": {"baseColorFactor": [0.9, 0.85, 0.7, 1], "metallicFactor": 1, "roughnessFactor": 0.45}},
        "slab": {"name": "slab", "pbrMetallicRoughness": {"baseColorFactor": [0.15, 0.2, 0.5, 1], "metallicFactor": 0, "roughnessFactor": 0.9}},
        "lamp": {"name": "lamp", "pbrMetallicRoughness": {"baseColorFactor": [0, 0, 0, 1], "metallicFactor": 0, "roughnessFactor": 1},
                 "emissiveFactor": [1, 0.93, 0.85], "extensions": {"KHR_materials_emissive_strength": {"emissiveStrength": 25}}},
    }
    mat_index = {k: i for i, k in enumerate(materials)}
    blob, views, accs, meshes, nodes = bytearray(), [], [], [], []

    def add(fmt, values, comp, typ, target, bounds=False):
        off = len(blob)
        flat = [x for v in values for x in (v if isinstance(v, (tuple, list)) else [v])]
        blob.extend(struct.pack("<" + fmt * len(flat), *flat))
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(blob) - off, "target": target})
        acc = {"bufferView": len(views) - 1, "componentType": comp, "count": len(values), "type": typ}
        if bounds:
            acc["min"] = [min(v[k] for v in values) for k in range(3)]
            acc["max"] = [max(v[k] for v in values) for k in range(3)]
        accs.append(acc)
        return len(accs) - 1

    def mesh(pos, nrm, idx, material):
        p, n, i = add("f", pos, 5126, "VEC3", 34962, True), add("f", nrm, 5126, "VEC3", 34962), add("I", idx, 5125, "SCALAR", 34963)
        meshes.append({"primitives": [{"attributes": {"POSITION": p, "NORMAL": n}, "indices": i, "material": mat_index[material]}]})
        return len(meshes) - 1

    def merge(parts):
        pos, nrm, idx = [], [], []
        for p, n, i in parts:
            idx += [k + len(pos) for k in i]
            pos += p
            nrm += n
        return pos, nrm, idx

    h = 3.0
    room = {
        "floor": ((-3, 0, -3), (3, 0, -3), (3, 0, 3), (-3, 0, 3), (0, 1, 0)),
        "ceiling": ((-3, h, -3), (3, h, -3), (3, h, 3), (-3, h, 3), (0, -1, 0)),
        "back": ((-3, 0, -3), (3, 0, -3), (3, h, -3), (-3, h, -3), (0, 0, 1)),
        "left": ((-3, 0, -3), (-3, 0, 3), (-3, h, 3), (-3, h, -3), (1, 0, 0)),
        "right": ((3, 0, -3), (3, 0, 3), (3, h, 3), (3, h, -3), (-1, 0, 0)),
    }
    nodes.append({"mesh": mesh(*merge(quad(*c[:4], c[4]) for c in room.values()), "wall")})
    panels = []
    for gx in range(16):
        for gz in range(16):
            cx, cz = -2.6 + gx * 0.35 + rnd.uniform(-0.05, 0.05), -2.6 + gz * 0.35 + rnd.uniform(-0.05, 0.05)
            r = rnd.uniform(0.03, 0.11)
            y = h - 0.02
            panels.append(quad((cx - r, y, cz - r), (cx + r, y, cz - r), (cx + r, y, cz + r), (cx - r, y, cz + r), (0, -1, 0)))
    nodes.append({"mesh": mesh(*merge(panels), "lamp")})
    sp, sn, si = sphere()
    ball, metal = mesh(sp, sn, si, "ball"), len(meshes)
    meshes.append({"primitives": [{**meshes[ball]["primitives"][0], "material": mat_index["metal"]}]})
    nodes.append({"mesh": ball, "translation": [-1.1, 0.6, -0.3], "scale": [0.6] * 3})
    nodes.append({"mesh": metal, "translation": [1.0, 0.6, 0.6], "scale": [0.6] * 3})
    nodes.append({"mesh": ball, "translation": [0.0, 0.4, -1.6], "scale": [0.4] * 3})
    nodes.append({"mesh": mesh(*quad((-0.8, 1.5, -0.8), (0.8, 1.5, -0.8), (0.8, 1.5, 0.8), (-0.8, 1.5, 0.8), (0, 1, 0)), "slab")})
    # Tilted down 20 degrees so the panels stay out of view: their own edges would drown the lighting noise.
    nodes.append({"camera": 0, "translation": [0, 1.5, 2.9], "rotation": [-math.sin(math.radians(10)), 0, 0, math.cos(math.radians(10))]})
    gltf = {
        "asset": {"version": "2.0", "generator": "scripts/gen_many_lights_scene.py"},
        "extensionsUsed": ["KHR_materials_emissive_strength"],
        "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}], "nodes": nodes, "meshes": meshes,
        "materials": list(materials.values()),
        "cameras": [{"type": "perspective", "perspective": {"yfov": 1.0, "znear": 0.1, "aspectRatio": 4 / 3}}],
        "buffers": [{"byteLength": len(blob), "uri": "data:application/octet-stream;base64," + base64.b64encode(bytes(blob)).decode()}],
        "bufferViews": views, "accessors": accs,
    }
    with open(path, "w") as f:
        json.dump(gltf, f, separators=(",", ":"))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:] == ["dark"])
