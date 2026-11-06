"""Blender shader nodes to Verion's Base BSDF (REQ-DCC-003).

Supported: Principled BSDF (color, metallic, roughness, transmission, IOR, emission, coat, sheen,
normal map, image textures), plus Diffuse, Glossy, Glass, Emission and a constant-factor Mix Shader
of those. Anything else is reported through `warn` and replaced by its default value.
"""
import json

import numpy as np

from . import images

DEFAULT = dict(base_color=[0.8, 0.8, 0.8], metallic=0.0, roughness=0.5)


def _active_output(tree):
    outs = [n for n in tree.nodes if n.bl_idname == "ShaderNodeOutputMaterial" and n.target in {"ALL", "CYCLES"}]
    return next((n for n in outs if n.is_active_output), outs[0] if outs else None)


class Converter:
    def __init__(self, scene, warn):
        self.scene = scene
        self.warn = warn
        self.index = {}     # material key -> IR material index
        self.images = {}    # (image key, channels) -> IR image index

    def key(self, material):
        return material.name_full if material else None

    def material(self, material):
        """The IR material index for a Blender material (None: the default grey)."""
        k = self.key(material)
        if k not in self.index:
            self.index[k] = self.scene.add_material(**self.params(material))
        return self.index[k]

    def update(self, material):
        """Re-converts a material that already has an IR index."""
        k = self.key(material)
        if k in self.index:
            self.scene.set_material(self.index[k], **self.params(material))

    # -- node walking -------------------------------------------------------------------------

    def params(self, material):
        if material is None:
            return dict(DEFAULT)
        if not material.use_nodes or material.node_tree is None:
            return dict(base_color=list(material.diffuse_color[:3]), metallic=material.metallic, roughness=material.roughness)
        out = _active_output(material.node_tree)
        if out is None or not out.inputs["Surface"].is_linked:
            self.warn(f"Material '{material.name}': no shader connected to the output; using grey")
            return dict(DEFAULT)
        p = self.closure(out.inputs["Surface"].links[0].from_node, material)
        return p if p is not None else dict(DEFAULT)

    def closure(self, node, material):
        t = node.bl_idname
        name = material.name
        if t == "ShaderNodeBsdfPrincipled":
            return self.principled(node, material)
        if t == "ShaderNodeBsdfDiffuse":
            return dict(base_color=self.color(node.inputs["Color"], material, True), metallic=0.0, roughness=1.0,
                        **self.normal_params(node, material))
        if t == "ShaderNodeBsdfGlossy":
            return dict(base_color=self.color(node.inputs["Color"], material, True), metallic=1.0,
                        roughness=self.value(node.inputs["Roughness"], material), **self.normal_params(node, material))
        if t in {"ShaderNodeBsdfGlass", "ShaderNodeBsdfRefraction"}:
            return dict(base_color=self.color(node.inputs["Color"], material, True), metallic=0.0, transmission=1.0,
                        roughness=self.value(node.inputs["Roughness"], material), ior=self.value(node.inputs["IOR"], material),
                        **self.normal_params(node, material))
        if t == "ShaderNodeEmission":
            return dict(base_color=[0.0, 0.0, 0.0], metallic=0.0, roughness=1.0,
                        emission=self.emission(node.inputs["Color"], node.inputs["Strength"], material))
        if t == "ShaderNodeMixShader":
            return self.mix(node, material)
        self.warn(f"Material '{name}': shader node {node.bl_idname} is not supported; using grey")
        return dict(DEFAULT)

    def mix(self, node, material):
        fac = node.inputs["Fac"]
        if fac.is_linked:
            self.warn(f"Material '{material.name}': a Mix Shader with a linked factor is not supported; using the first shader")
            f = 0.0
        else:
            f = float(fac.default_value)
        ins = [node.inputs[1], node.inputs[2]]
        subs = []
        for s in ins:
            subs.append(self.closure(s.links[0].from_node, material) if s.is_linked else None)
        a, b = subs
        if a is None and b is None:
            return dict(DEFAULT)
        if a is None or b is None:  # a closure against nothing (Transparent is not supported)
            self.warn(f"Material '{material.name}': Mix Shader with an empty or unsupported side; using the other shader")
            return a or b
        keys = {"metallic", "roughness", "transmission", "ior", "clearcoat", "clearcoat_roughness", "sheen_roughness"}
        out = {}
        for k in set(a) | set(b):
            va, vb = a.get(k, DEFAULT.get(k)), b.get(k, DEFAULT.get(k))
            if k in keys or k in {"base_color", "emission", "sheen_color"}:
                va = va if va is not None else (0.0 if k in keys else [0.0] * 3)
                vb = vb if vb is not None else (0.0 if k in keys else [0.0] * 3)
                out[k] = (np.array(va) * (1 - f) + np.array(vb) * f).tolist() if k not in keys else float(va * (1 - f) + vb * f)
            else:
                out[k] = (a if f < 0.5 else b).get(k, va)  # textures: the dominant side
        return out

    def principled(self, node, material):
        i = node.inputs
        get = lambda *names: next((i[n] for n in names if n in i), None)
        v = lambda *names: self.value(get(*names), material) if get(*names) is not None else 0.0
        p = dict(
            metallic=v("Metallic"),
            roughness=v("Roughness"),
            ior=v("IOR"),
            transmission=v("Transmission Weight", "Transmission"),
            clearcoat=v("Coat Weight", "Clearcoat"),
            clearcoat_roughness=v("Coat Roughness", "Clearcoat Roughness"),
        )
        sheen = v("Sheen Weight", "Sheen")
        if sheen > 0:
            tint = self.color(get("Sheen Tint"), material, False) if get("Sheen Tint") is not None else [1.0] * 3
            p["sheen_color"] = [sheen * c for c in tint] if isinstance(tint, list) else [sheen] * 3
            p["sheen_roughness"] = v("Sheen Roughness")
        if v("Subsurface Weight", "Subsurface") > 0:
            self.warn(f"Material '{material.name}': subsurface scattering is not supported")
        if get("Alpha") is not None and (get("Alpha").is_linked or get("Alpha").default_value < 1.0):
            self.warn(f"Material '{material.name}': alpha is not supported yet; rendering opaque")
        p["base_color"] = self.color(i["Base Color"], material, True)
        tex = self.texture_of(i["Base Color"], material)
        if tex is not None:
            p["base_color"] = [1.0, 1.0, 1.0]
            p["base_color_texture"] = tex
        emit_color = get("Emission Color", "Emission")
        if emit_color is not None:
            strength = get("Emission Strength")
            p["emission"] = self.emission(emit_color, strength, material)
            et = self.texture_of(emit_color, material)
            if et is not None:
                p["emission_texture"] = et
                p["emission"] = [float(strength.default_value if strength is not None else 1.0)] * 3
        p.update(self.metallic_roughness(i, p, material))
        p.update(self.normal_params(node, material))
        return p

    # -- sockets --------------------------------------------------------------------------------

    def value(self, socket, material):
        if socket.is_linked:
            self.warn(f"Material '{material.name}': a node connected to '{socket.name}' is not supported; using its default value")
        return float(socket.default_value)

    def color(self, socket, material, with_texture):
        """The constant color of a socket (a linked image texture is handled by `texture_of`)."""
        if socket.is_linked:
            if self.texture_of(socket, material, quiet=True) is not None:
                return [1.0, 1.0, 1.0]
            self.warn(f"Material '{material.name}': a node connected to '{socket.name}' is not supported; using its default color")
        return [float(c) for c in socket.default_value[:3]]

    def emission(self, color_socket, strength_socket, material):
        s = 1.0 if strength_socket is None else self.value(strength_socket, material)
        c = self.color(color_socket, material, False)
        return [x * s for x in c]

    def image_index(self, image, channels=None):
        key = (image.name_full, channels)
        if key not in self.images:
            px = images.pixels(image)
            if px is None:
                return None
            self.images[key] = self.scene.add_image(px)
        return self.images[key]

    def texture_of(self, socket, material, quiet=False):
        if not socket.is_linked:
            return None
        n = socket.links[0].from_node
        if n.bl_idname == "ShaderNodeTexImage" and n.image is not None:
            if n.image.source == "TILED":
                if not quiet:
                    self.warn(f"Material '{material.name}': UDIM tiles are not supported yet")
                return None
            return self.image_index(n.image)
        return None

    def metallic_roughness(self, inputs, params, material):
        """glTF packs roughness (G) and metallic (B) in one image; build it from the two textures."""
        m, r = inputs["Metallic"], inputs["Roughness"]
        tm, tr = self.texture_of(m, material, quiet=True), self.texture_of(r, material, quiet=True)
        if tm is None and tr is None:
            return {}
        w = h = 1
        sources = {}
        for name, sock in (("m", m), ("r", r)):
            n = sock.links[0].from_node if sock.is_linked and sock.links[0].from_node.bl_idname == "ShaderNodeTexImage" else None
            if n is not None and n.image is not None:
                px = images.pixels(n.image)
                if px is not None:
                    sources[name] = px
                    h, w = max(h, px.shape[0]), max(w, px.shape[1])
        packed = np.zeros((h, w, 4), np.float32)
        packed[..., 3] = 1.0
        for name, ch, sock in (("r", 1, r), ("m", 2, m)):
            if name in sources:
                px = sources[name]
                if px.shape[:2] != (h, w):  # nearest resize; the two textures are rarely different sizes
                    yy = (np.arange(h) * px.shape[0] // h)[:, None]
                    xx = (np.arange(w) * px.shape[1] // w)[None, :]
                    px = px[yy, xx]
                packed[..., ch] = px[..., 0]
            else:
                packed[..., ch] = float(sock.default_value)
        return dict(metallic=1.0, roughness=1.0, metallic_roughness_texture=self.scene.add_image(packed))

    def normal_params(self, node, material):
        if "Normal" not in node.inputs or not node.inputs["Normal"].is_linked:
            return {}
        n = node.inputs["Normal"].links[0].from_node
        if n.bl_idname == "ShaderNodeNormalMap" and n.space == "TANGENT":
            col = n.inputs["Color"]
            if col.is_linked and col.links[0].from_node.bl_idname == "ShaderNodeTexImage" and col.links[0].from_node.image is not None:
                idx = self.image_index(col.links[0].from_node.image)
                if idx is not None:
                    return dict(normal_texture=idx, normal_scale=float(n.inputs["Strength"].default_value))
        self.warn(f"Material '{material.name}': only a tangent-space Normal Map fed by an image texture is supported")
        return {}


def stylization_json(material):
    """The `stylization` JSON of a material (item 8 fills this in)."""
    return None
