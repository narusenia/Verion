#!/usr/bin/env python3
"""Writes scenes/showcase.gltf: a floor and five spheres, one per M2 material feature
(clearcoat, sheen, dispersion, toon stylization, rough metal), lit by two directional lights.
The geometry is embedded, so the file is self-contained. With a second argument `sheen` it writes the sheen comparison instead: the same dark
red base with no sheen, three sheen roughnesses and a blue sheen, lit mostly from behind.
With `matcap` it writes the MatCap comparison instead: the same clay-colored base lit physically, then clay, metal and toon
MatCap pictures (scripts/gen_matcaps.py, embedded) at strength 1, and the clay one at strength 0.5.
Other modes: `toon` (five Toon recipes: ramp bands, rim light, highlight ramp, shadow palette, thick outline), `lights`
(five Toon spheres under five colored lights listed weakest first, to exercise the strength-ordered light slots) and `glass`
(transmission spheres of roughness 0, 0.15, 0.3, 0.5 and 0.8, no dispersion).
glTF's metallicFactor defaults to 1, so non-metals set it to 0. Usage: gen_showcase_scene.py OUT_FILE [sheen|matcap|toon|lights|glass]"""
import base64, json, math, struct, sys

from gen_matcaps import matcap_png

RINGS, SEGS = 48, 96


def sphere():
    pos, nrm, idx = [], [], []
    for i in range(RINGS + 1):
        t = math.pi * i / RINGS
        for j in range(SEGS + 1):
            p = 2 * math.pi * j / SEGS
            n = (math.sin(t) * math.cos(p), math.cos(t), math.sin(t) * math.sin(p))
            pos.append(n)
            nrm.append(n)
    for i in range(RINGS):
        for j in range(SEGS):
            a, b = i * (SEGS + 1) + j, (i + 1) * (SEGS + 1) + j
            # counter-clockwise seen from outside (glTF front faces)
            idx += [a, a + 1, b, a + 1, b + 1, b]
    return pos, nrm, idx


def quat_axis(axis, deg):
    h = math.radians(deg) / 2
    return [c * math.sin(h) for c in axis] + [math.cos(h)]


def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return [aw*bx + ax*bw + ay*bz - az*by, aw*by - ax*bz + ay*bw + az*bx,
            aw*bz + ax*by - ay*bx + az*bw, aw*bw - ax*bx - ay*by - az*bz]


def main(path, mode="showcase"):
    sp, sn, si = sphere()
    floor_pos = [(-12, 0, -8), (12, 0, -8), (12, 0, 8), (-12, 0, 8)]
    floor_nrm = [(0, 1, 0)] * 4
    floor_idx = [0, 3, 2, 0, 2, 1]
    blob = bytearray()
    views, accs = [], []

    def add(data_fmt, values, comp_type, typ, target, bounds=False):
        off = len(blob)
        flat = [x for v in values for x in (v if isinstance(v, (tuple, list)) else [v])]
        blob.extend(struct.pack("<" + data_fmt * len(flat), *flat))
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(blob) - off, "target": target})
        acc = {"bufferView": len(views) - 1, "componentType": comp_type, "count": len(values), "type": typ}
        if bounds:
            acc["min"] = [min(v[k] for v in values) for k in range(3)]
            acc["max"] = [max(v[k] for v in values) for k in range(3)]
        accs.append(acc)
        return len(accs) - 1

    meshes = []
    for pos, nrm, idx in ((sp, sn, si), (floor_pos, floor_nrm, floor_idx)):
        p = add("f", pos, 5126, "VEC3", 34962, True)
        n = add("f", nrm, 5126, "VEC3", 34962)
        i = add("I", idx, 5125, "SCALAR", 34963)
        meshes.append({"primitives": [{"attributes": {"POSITION": p, "NORMAL": n}, "indices": i, "material": 0}]})

    toon = {"hybridSurface": {"diffuse": 1, "specular": 1, "shadow": 1, "outline": 1},
            "toonRamp": {"thresholds": [0.25, 0.6], "feather": 0.04,
                         "palette": [[0.25, 0.3, 0.55], [0.6, 0.7, 0.95], [1, 1, 1]]},
            "stylizedSpecular": {"size": 0.08, "feather": 0.02, "strength": 1},
            "outlineStyle": {"width": 2}}
    # The glass dispersion is exaggerated (realistic values are 0..1) so the color fringes show.
    materials = [
        {"name": "clearcoat red", "pbrMetallicRoughness": {"baseColorFactor": [0.8, 0.03, 0.03, 1], "metallicFactor": 0, "roughnessFactor": 0.45},
         "extensions": {"KHR_materials_clearcoat": {"clearcoatFactor": 1, "clearcoatRoughnessFactor": 0.03}}},
        {"name": "sheen velvet", "pbrMetallicRoughness": {"baseColorFactor": [0.25, 0.02, 0.1, 1], "metallicFactor": 0, "roughnessFactor": 0.9},
         "extensions": {"KHR_materials_sheen": {"sheenColorFactor": [1, 0.55, 0.7], "sheenRoughnessFactor": 0.35}}},
        {"name": "dispersive glass", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0, "roughnessFactor": 0},
         "extensions": {"KHR_materials_transmission": {"transmissionFactor": 1}, "KHR_materials_ior": {"ior": 1.8},
                        "KHR_materials_dispersion": {"dispersion": 10}}},
        {"name": "toon", "pbrMetallicRoughness": {"baseColorFactor": [0.9, 0.6, 0.2, 1], "metallicFactor": 0, "roughnessFactor": 0.5},
         "extensions": {"VERION_materials_stylization": toon}},
        {"name": "rough gold", "pbrMetallicRoughness": {"baseColorFactor": [1.0, 0.77, 0.34, 1], "metallicFactor": 1, "roughnessFactor": 0.55}},
        {"name": "floor", "pbrMetallicRoughness": {"baseColorFactor": [0.55, 0.55, 0.55, 1], "metallicFactor": 0, "roughnessFactor": 0.8}},
    ]
    if mode == "sheen":
        def cloth(name, color, rough):
            ext = {"KHR_materials_sheen": {"sheenColorFactor": color, "sheenRoughnessFactor": rough}} if color else {}
            return {"name": name, "pbrMetallicRoughness": {"baseColorFactor": [0.25, 0.02, 0.1, 1], "metallicFactor": 0, "roughnessFactor": 0.9},
                    "extensions": ext}
        materials[:5] = [
            cloth("no sheen", None, 0),
            cloth("sheen roughness 0.3", [1, 0.55, 0.7], 0.3),
            cloth("sheen roughness 0.6", [1, 0.55, 0.7], 0.6),
            cloth("sheen roughness 1.0", [1, 0.55, 0.7], 1.0),
            cloth("blue sheen roughness 0.5", [0.5, 0.6, 1], 0.5),
        ]
        materials[5]["pbrMetallicRoughness"]["baseColorFactor"] = [0.15, 0.15, 0.15, 1]
    images, textures = [], []
    orange = {"baseColorFactor": [0.9, 0.6, 0.2, 1], "metallicFactor": 0, "roughnessFactor": 0.4}
    stylized = lambda name, ext: {"name": name, "pbrMetallicRoughness": orange,  # noqa: E731
                                  "extensions": {"VERION_materials_stylization": ext}}
    hybrid = {"diffuse": 1, "specular": 1, "shadow": 1, "outline": 1}
    if mode == "toon":
        ramp = lambda t, f, p: {"thresholds": t, "feather": f, "palette": p}  # noqa: E731
        materials[:5] = [
            stylized("two bands", {"hybridSurface": hybrid, "toonRamp": ramp([0.4], 0.0, [[0.35, 0.3, 0.5], [1, 1, 1]]),
                                   "outlineStyle": {"width": 2}}),
            stylized("four soft bands", {"hybridSurface": hybrid,
                                         "toonRamp": ramp([0.15, 0.4, 0.7], 0.08, [[0.2, 0.2, 0.4], [0.5, 0.5, 0.8], [0.8, 0.8, 0.95], [1, 1, 1]]),
                                         "outlineStyle": {"width": 2}}),
            stylized("rim light", {"hybridSurface": hybrid, "toonRamp": ramp([0.3], 0.02, [[0.3, 0.3, 0.55], [1, 1, 1]]),
                                   "rimLight": {"color": [0.6, 0.8, 1], "width": 0.35, "strength": 1.5}}),
            stylized("highlight ramp", {"hybridSurface": hybrid, "toonRamp": ramp([0.3], 0.02, [[0.3, 0.3, 0.55], [1, 1, 1]]),
                                        "stylizedSpecular": {"size": 0.12, "ramp": ramp([0.3, 0.7], 0.05, [[0, 0, 0], [0.5, 0.5, 0.5], [1, 1, 1]])},
                                        "outlineStyle": {"width": 2}}),
            stylized("shadow palette", {"hybridSurface": hybrid, "toonRamp": ramp([0.3, 0.65], 0.03, [[1, 1, 1], [1, 1, 1], [1, 1, 1]]),
                                        "shadowPalette": {"direct": {"hueShift": -25, "saturation": 1.3, "value": 0.55}},
                                        "outlineStyle": {"width": 4, "color": [0.1, 0.02, 0.0]}}),
        ]
    if mode == "glass":
        materials[:5] = [
            {"name": f"glass roughness {r}", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0, "roughnessFactor": r},
             "extensions": {"KHR_materials_transmission": {"transmissionFactor": 1}, "KHR_materials_ior": {"ior": 1.5}}}
            for r in (0.0, 0.15, 0.3, 0.5, 0.8)]
    if mode == "lights":
        materials[:5] = [stylized(f"toon {k}", {"hybridSurface": hybrid,
                                                "toonRamp": {"thresholds": [0.3, 0.65], "feather": 0.03,
                                                             "palette": [[0.3, 0.3, 0.5], [0.7, 0.7, 0.9], [1, 1, 1]]},
                                                "stylizedSpecular": {"size": 0.06}, "outlineStyle": {"width": 2}}) for k in range(5)]
    if mode == "matcap":
        for kind in ("clay", "metal", "toon"):
            images.append({"uri": "data:image/png;base64," + base64.b64encode(matcap_png(kind)).decode()})
            textures.append({"source": len(images) - 1})

        def shaded(name, texture, strength):
            ext = {"matcap": {"texture": {"index": texture}, "strength": strength}} if texture is not None else {}
            return {"name": name, "pbrMetallicRoughness": {"baseColorFactor": [0.8, 0.7, 0.6, 1], "metallicFactor": 0, "roughnessFactor": 0.5},
                    "extensions": {"VERION_materials_stylization": ext}}
        materials[:5] = [
            shaded("physical", None, 0),
            shaded("clay matcap", 0, 1.0),
            shaded("metal matcap", 1, 1.0),
            shaded("toon matcap", 2, 1.0),
            shaded("clay matcap half", 0, 0.5),
        ]
    nodes, scene_nodes = [], []
    for k in range(5):
        meshes_k = json.loads(json.dumps(meshes[0]))
        meshes_k["primitives"][0]["material"] = k
        meshes.append(meshes_k)
        nodes.append({"mesh": len(meshes) - 1, "translation": [(k - 2) * 2.2, 1.0, 0], "scale": [1, 1, 1]})
    meshes[1]["primitives"][0]["material"] = 5
    nodes.append({"mesh": 1})
    pitch = -math.degrees(math.atan2(2.6, 11.0))
    nodes.append({"camera": 0, "translation": [0, 3.6, 11.0], "rotation": quat_axis((1, 0, 0), pitch)})
    # Directional lights shine along local -z: aim them down and across.
    key = qmul(quat_axis((0, 1, 0), -35), quat_axis((1, 0, 0), -50))
    fill = qmul(quat_axis((0, 1, 0), 140), quat_axis((1, 0, 0), -35))
    lights = [{"type": "directional", "color": [1, 0.96, 0.9], "intensity": 3.2},
              {"type": "directional", "color": [0.7, 0.8, 1], "intensity": 0.9}]
    if mode == "sheen":
        # Key light from behind and above (travels toward the camera), a dim fill from the camera side.
        key = qmul(quat_axis((0, 1, 0), 200), quat_axis((1, 0, 0), -35))
        fill = qmul(quat_axis((0, 1, 0), -10), quat_axis((1, 0, 0), -30))
        lights = [{"type": "directional", "color": [1, 1, 1], "intensity": 4.0},
                  {"type": "directional", "color": [1, 1, 1], "intensity": 0.35}]
    nodes.append({"rotation": key, "extensions": {"KHR_lights_punctual": {"light": 0}}})
    nodes.append({"rotation": fill, "extensions": {"KHR_lights_punctual": {"light": 1}}})
    if mode == "lights":
        # Five colored lights, weakest first: the light slots follow strength, not this order.
        nodes.pop(), nodes.pop()
        lights = []
        for k, (yaw, color, intensity) in enumerate([(120, [1, 0.3, 1], 0.4), (200, [0.4, 1, 0.5], 0.7), (-110, [1, 1, 0.3], 1.0),
                                                     (60, [0.4, 0.5, 1], 1.6), (-35, [1, 0.95, 0.9], 3.2)]):
            lights.append({"type": "directional", "color": color, "intensity": intensity})
            nodes.append({"rotation": qmul(quat_axis((0, 1, 0), yaw), quat_axis((1, 0, 0), -40)),
                          "extensions": {"KHR_lights_punctual": {"light": k}}})
    scene_nodes = list(range(len(nodes)))
    gltf = {
        "asset": {"version": "2.0", "generator": "scripts/gen_showcase_scene.py"},
        "extensionsUsed": ["KHR_lights_punctual", "KHR_materials_clearcoat", "KHR_materials_sheen",
                           "KHR_materials_transmission", "KHR_materials_ior", "KHR_materials_dispersion",
                           "VERION_materials_stylization"],
        "scene": 0, "scenes": [{"nodes": scene_nodes}], "nodes": nodes, "meshes": meshes,
        "materials": materials,
        "cameras": [{"type": "perspective", "perspective": {"yfov": 0.5, "znear": 0.1, "aspectRatio": 2.0}}],
        "extensions": {"KHR_lights_punctual": {"lights": lights}},
        "buffers": [{"byteLength": len(blob), "uri": "data:application/octet-stream;base64," + base64.b64encode(bytes(blob)).decode()}],
        "bufferViews": views, "accessors": accs,
    }
    if images:
        gltf["images"], gltf["textures"] = images, textures
    with open(path, "w") as f:
        json.dump(gltf, f, separators=(",", ":"))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "showcase")
