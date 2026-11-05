#!/usr/bin/env python3
"""Writes scenes/cornell_box.gltf: the Cornell Box of the Mitsuba cross-check (crates/verion-gpu-metal/examples/render_ppm.rs,
mode `box`) as glTF: 4 x 4 x 4 box, red left and green right wall, a square emitter (14) in the ceiling, a gold and a glass
sphere, and a dim point light. The geometry is embedded. Usage: gen_cornell_scene.py OUT_FILE"""
import base64, json, struct, sys

from gen_showcase_scene import sphere


def quad(a, b, c, d, up):
    """Two triangles over corners a, b, c, d wound so the front face looks along `up`."""
    n = [(b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]),
         (b[2] - a[2]) * (c[0] - a[0]) - (b[0] - a[0]) * (c[2] - a[2]),
         (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])]
    if sum(x * y for x, y in zip(n, up)) < 0:
        b, d = d, b
    return [a, b, c, d], [up] * 4, [0, 1, 2, 0, 2, 3]


def main(path):
    lo, hi = -2.0, 2.0
    surfaces = {  # name: (corners, inward normal, material)
        "floor": ((-2, lo, -2), (2, lo, -2), (2, lo, 2), (-2, lo, 2), (0, 1, 0), "grey"),
        "ceiling": ((-2, hi, -2), (2, hi, -2), (2, hi, 2), (-2, hi, 2), (0, -1, 0), "grey"),
        "back": ((-2, -2, lo), (2, -2, lo), (2, 2, lo), (-2, 2, lo), (0, 0, 1), "grey"),
        "left": ((lo, -2, -2), (lo, -2, 2), (lo, 2, 2), (lo, 2, -2), (1, 0, 0), "red"),
        "right": ((hi, -2, -2), (hi, -2, 2), (hi, 2, 2), (hi, 2, -2), (-1, 0, 0), "green"),
        "light": ((-0.6, 1.99, -0.6), (0.6, 1.99, -0.6), (0.6, 1.99, 0.6), (-0.6, 1.99, 0.6), (0, -1, 0), "light"),
    }
    # ior 1 leaves the diffuse materials without a specular coat, as in the example scene.
    flat = lambda name, rgb, extra=None: {  # noqa: E731
        "name": name, "pbrMetallicRoughness": {"baseColorFactor": rgb + [1], "metallicFactor": 0, "roughnessFactor": 1},
        "extensions": {"KHR_materials_ior": {"ior": 1.0}, **(extra or {})}}
    materials = {
        "grey": flat("grey", [0.75, 0.75, 0.75]),
        "red": flat("red", [0.75, 0.15, 0.15]),
        "green": flat("green", [0.15, 0.6, 0.15]),
        "light": {**flat("light", [0, 0, 0], {"KHR_materials_emissive_strength": {"emissiveStrength": 14}}), "emissiveFactor": [1, 1, 1]},
        "gold": {"name": "gold", "pbrMetallicRoughness": {"baseColorFactor": [1.0, 0.78, 0.34, 1], "metallicFactor": 1, "roughnessFactor": 0.2}},
        "glass": {"name": "glass", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0, "roughnessFactor": 0},
                  "extensions": {"KHR_materials_transmission": {"transmissionFactor": 1}}},
    }
    mat_index = {k: i for i, k in enumerate(materials)}
    blob, views, accs, meshes, nodes = bytearray(), [], [], [], []

    def add(fmt, values, comp, typ, target, bounds=False):
        off = len(blob)
        flat_values = [x for v in values for x in (v if isinstance(v, (tuple, list)) else [v])]
        blob.extend(struct.pack("<" + fmt * len(flat_values), *flat_values))
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

    for corners_normal_material in surfaces.values():
        *corners, up, material = corners_normal_material
        nodes.append({"mesh": mesh(*quad(*corners, up), material)})
    sp, sn, si = sphere()
    first = mesh(sp, sn, si, "gold")
    # The glass sphere reuses the gold one's vertex data under another material.
    meshes.append({"primitives": [{**meshes[first]["primitives"][0], "material": mat_index["glass"]}]})
    for m, (x, y, z) in ((first, (-0.9, -1.3, -0.6)), (len(meshes) - 1, (0.9, -1.3, 0.3))):
        nodes.append({"mesh": m, "translation": [x, y, z], "scale": [0.7] * 3})
    nodes.append({"camera": 0, "translation": [0, 0, 6]})
    nodes.append({"extensions": {"KHR_lights_punctual": {"light": 0}}, "translation": [0, 1, 1.5]})
    gltf = {
        "asset": {"version": "2.0", "generator": "scripts/gen_cornell_scene.py"},
        "extensionsUsed": ["KHR_lights_punctual", "KHR_materials_ior", "KHR_materials_emissive_strength", "KHR_materials_transmission"],
        "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}], "nodes": nodes, "meshes": meshes,
        "materials": list(materials.values()),
        "cameras": [{"type": "perspective", "perspective": {"yfov": 0.9, "znear": 0.1, "aspectRatio": 4 / 3}}],
        "extensions": {"KHR_lights_punctual": {"lights": [{"type": "point", "color": [1, 0.95, 0.9], "intensity": 1.5}]}},
        "buffers": [{"byteLength": len(blob), "uri": "data:application/octet-stream;base64," + base64.b64encode(bytes(blob)).decode()}],
        "bufferViews": views, "accessors": accs,
    }
    with open(path, "w") as f:
        json.dump(gltf, f, separators=(",", ":"))


if __name__ == "__main__":
    main(sys.argv[1])
