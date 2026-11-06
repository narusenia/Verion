"""Blender shader nodes to Verion's Base BSDF (REQ-DCC-003).

Supported: Principled BSDF (color, metallic, roughness, transmission, IOR, emission, coat, sheen,
normal map, image textures), plus Diffuse, Glossy, Glass, Emission and a constant-factor Mix Shader
of those. Anything else is reported through `warn` and replaced by its default value.
"""
import os

import bpy
import numpy as np

from . import bake_material, images, nodes, stylization, surface

IMAGE_NODES = {"ShaderNodeTexImage", nodes.IMAGE}

DEFAULT = dict(base_color=[0.8, 0.8, 0.8], metallic=0.0, roughness=0.5)
# Transparent BSDF: a surface that stops no ray. `_clear` marks it for `blend_clear`.
CLEAR = dict(base_color=[1.0, 1.0, 1.0], metallic=0.0, roughness=1.0, opacity=0.0, _clear=True)


def blend_clear(solid, weight):
    """`solid` with `weight` of its rays passing straight through, as a Mix with a Transparent BSDF.

    shortcut: a cutout from an alpha texture is not supported (the alpha of an image is not read)."""
    out = dict(solid)
    out["opacity"] = out.get("opacity", 1.0) * (1.0 - weight)
    return out


def _active_output(tree):
    outs = [n for n in tree.nodes if n.bl_idname == "ShaderNodeOutputMaterial" and n.target in {"ALL", "CYCLES"}]
    return next((n for n in outs if n.is_active_output), outs[0] if outs else None)


class Converter:
    def __init__(self, scene, warn):
        self.scene = scene
        self.warn = warn
        self.bake_ob = None     # the object whose UVs carry baked textures (set by the caller before `material`)
        self.bake_size = 1024
        self._quiet = set()     # socket names being baked: no "not supported" warning for them
        self.index = {}     # material key -> IR material index
        self.images = {}    # (image key, channels) -> IR image index
        self._baked = {}
        self.tree_sigs = {}  # material key -> signature of its Verion node tree (None: it has none)

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

    def refresh_trees(self):
        """Re-converts the materials whose Verion node tree changed (or was bound or unbound): a tree edit
        does not always arrive as a depsgraph update of the material."""
        for k, old in list(self.tree_sigs.items()):
            m = bpy.data.materials.get(k) if k is not None else None
            if m is not None and self.tree_signature(m) != old:
                self.update(m)

    @staticmethod
    def tree_signature(material):
        tree = material.verion_surface.node_tree
        return None if tree is None else (tree.name_full, nodes.signature(tree))

    def params(self, material):
        if material is not None:
            self.tree_sigs[self.key(material)] = self.tree_signature(material)
        p = self.surface_params(material)
        p.pop("_clear", None)
        if material is not None:
            surface.apply(material, p)
        tree = material.verion_surface.node_tree if material is not None else None
        if tree is not None:
            st = nodes.style_json(tree, self.image_index, self.warn)  # the nodes define the layers, not the panel
        else:
            st = stylization.material_style(material, self.image_index, self.warn) if material is not None else None
        if st is not None:
            p["stylization"], p["stylization_images"] = st
        return p

    def surface_params(self, material):
        if material is None:
            return dict(DEFAULT)
        tree = material.verion_surface.node_tree
        if tree is not None:
            return self.verion_tree(tree, material)
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
        if t == "ShaderNodeBsdfTransparent":
            return dict(CLEAR)
        if t == "ShaderNodeMixShader":
            return self.mix(node, material)
        self.warn(f"Material '{name}': shader node {node.bl_idname} is not supported; using grey")
        return dict(DEFAULT)

    def verion_tree(self, tree, material):
        """The parameters of a Verion node tree (the Surface node linked to the first Output)."""
        surface = nodes.chain(tree)[0]
        if surface is None:
            self.warn(f"Material '{material.name}': the Verion nodes have no Surface connected to the output; using grey")
            return dict(DEFAULT)
        i = surface.inputs
        self._baked, self._quiet = {}, set()
        v = lambda name: self.value(i[name], material)
        p = dict(metallic=v("Metallic"), roughness=v("Roughness"), transmission=v("Transmission"), ior=v("IOR"),
                 clearcoat=v("Clearcoat"), clearcoat_roughness=v("Clearcoat Roughness"))
        if v("Dispersion") > 0:
            p["dispersion"] = v("Dispersion")
        p["base_color"] = self.color(i["Base Color"], material, True)
        tex = self.texture_of(i["Base Color"], material)
        if tex is not None:
            p["base_color_texture"] = tex
        sheen = self.color(i["Sheen Color"], material, False)
        if any(sheen):
            p["sheen_color"], p["sheen_roughness"] = sheen, v("Sheen Roughness")
        strength = v("Emission Strength")
        p["emission"] = [c * strength for c in self.color(i["Emission"], material, False)]
        et = self.texture_of(i["Emission"], material)
        if et is not None:
            p["emission_texture"], p["emission"] = et, [strength] * 3
        p.update(self.metallic_roughness(i, p, material))
        nt = self.texture_of(i["Normal Map"], material)
        if nt is not None:
            p.update(normal_texture=nt, normal_scale=v("Normal Scale"))
        if v("Opacity") < 1.0:
            p = blend_clear(p, 1.0 - v("Opacity"))
        return p

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
        if a is None or b is None:  # a closure against nothing (an unsupported node)
            self.warn(f"Material '{material.name}': Mix Shader with an empty or unsupported side; using the other shader")
            return a or b
        if a.get("_clear") or b.get("_clear"):
            if a.get("_clear") and b.get("_clear"):
                return a
            solid, w = (b, 1.0 - f) if a.get("_clear") else (a, f)
            return blend_clear(solid, w)
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
        self._baked = self.bake_sockets(node, material)
        self._quiet = {self._socket_of(node, k).name for k in self._baked}
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
        alpha = get("Alpha")
        if alpha is not None and alpha.is_linked:
            self.warn(f"Material '{material.name}': an alpha texture (cutout) is not supported; rendering opaque")
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
        p.update(self.baked_params(node, material, p))
        p.update(self.normal_params(node, material))
        if alpha is not None and not alpha.is_linked and alpha.default_value < 1.0:
            p = blend_clear(p, 1.0 - float(alpha.default_value))
        return p

    # -- baked procedural inputs ---------------------------------------------------------------

    BAKED = {"base_color": ("Base Color",), "roughness": ("Roughness",), "metallic": ("Metallic",),
             "emission": ("Emission Color", "Emission")}

    def _socket_of(self, node, key):
        return next(node.inputs[n] for n in self.BAKED[key] if n in node.inputs)

    def bake_sockets(self, node, material):
        """{key: the baked (H, W, 3) image} for the sockets of `node` fed by something other than an image
        texture. Empty (with a warning) when there is no object with UVs to bake over or the bake fails."""
        todo = []
        for key in self.BAKED:
            if not any(n in node.inputs for n in self.BAKED[key]):
                continue
            sock = self._socket_of(node, key)
            if sock.is_linked and self.texture_of(sock, material, quiet=True) is None:
                todo.append((key, node.name, sock.identifier))
        if not todo:
            return {}
        ob = self.bake_ob
        if ob is None or ob.type != "MESH" or not ob.original.data.uv_layers:
            self.warn(f"Material '{material.name}': procedural inputs need an object with UVs to be baked; using the default values")
            return {}
        try:
            return bake_material.bake(material, ob, todo, self.bake_size)
        except RuntimeError as e:
            self.warn(f"Material '{material.name}': {e}")
            return {}

    def baked_params(self, node, material, p):
        """Textures for the baked sockets (a roughness and metallic bake share one packed image)."""
        out = {}
        baked = self._baked
        rgba = lambda a: np.concatenate([a, np.ones(a.shape[:2] + (1,), np.float32)], axis=2)
        if "base_color" in baked:
            out["base_color"] = [1.0, 1.0, 1.0]
            out["base_color_texture"] = self.scene.add_image(rgba(baked["base_color"]))
        if "emission" in baked:
            strength = node.inputs["Emission Strength"].default_value if "Emission Strength" in node.inputs else 1.0
            out["emission"] = [float(strength)] * 3
            out["emission_texture"] = self.scene.add_image(rgba(baked["emission"]))
        if "roughness" in baked or "metallic" in baked:
            size = next(baked[k].shape[0] for k in ("roughness", "metallic") if k in baked)
            packed = np.ones((size, size, 4), np.float32)
            for key, ch in (("roughness", 1), ("metallic", 2)):
                # A channel that was not baked keeps its constant, since the factor becomes 1.
                packed[..., ch] = baked[key][..., 0] if key in baked else p[key]
            out.update(roughness=1.0, metallic=1.0, metallic_roughness_texture=self.scene.add_image(packed))
        return out

    # -- sockets --------------------------------------------------------------------------------

    def value(self, socket, material):
        if socket.is_linked and socket.name not in self._quiet:
            self.warn(f"Material '{material.name}': a node connected to '{socket.name}' is not supported; using its default value")
        return float(socket.default_value)

    def color(self, socket, material, with_texture):
        """The constant color of a socket (a linked image texture is handled by `texture_of`)."""
        if socket.is_linked:
            if self.texture_of(socket, material, quiet=True) is not None:
                return [1.0, 1.0, 1.0]
            if socket.name not in self._quiet:
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
        if n.bl_idname in IMAGE_NODES and n.image is not None:
            if n.image.source == "TILED":
                return self.udim_index(n.image, material, quiet)
            return self.image_index(n.image)
        return None

    # -- UDIM ---------------------------------------------------------------------------------------

    def udim_layout(self, material):
        """{tile number: (column, row)} and the grid size of the first UDIM image a material uses, or None.

        UDIM tiles become one atlas image (tile (col, row) at that cell) and the mesh UVs are moved
        into the atlas (`atlas_uvs`), so the renderer needs no tiled textures."""
        if material is None or not material.use_nodes or material.node_tree is None:
            return None
        for n in material.node_tree.nodes:
            if n.bl_idname == "ShaderNodeTexImage" and n.image is not None and n.image.source == "TILED":
                nums = sorted(t.number for t in n.image.tiles)
                cells = {num: ((num - 1001) % 10, (num - 1001) // 10) for num in nums}
                return cells, max(c for c, _ in cells.values()) + 1, max(r for _, r in cells.values()) + 1
        return None

    def udim_index(self, image, material, quiet):
        key = (image.name_full, "udim")
        if key in self.images:
            return self.images[key]
        layout = self.udim_layout_of(image)
        cells, cols, rows = layout
        tiles = {}
        for t in image.tiles:
            path = bpy.path.abspath(image.filepath).replace("<UDIM>", str(t.number))
            if not os.path.exists(path):
                if not quiet:
                    self.warn(f"Material '{material.name}': UDIM tile {t.number} is missing ({path})")
                continue
            im = bpy.data.images.load(path, check_existing=False)
            try:
                im.colorspace_settings.name = image.colorspace_settings.name
                tiles[t.number] = images.pixels(im)
            finally:
                bpy.data.images.remove(im)
        if not tiles:
            return None
        th = max(p.shape[0] for p in tiles.values())
        tw = max(p.shape[1] for p in tiles.values())
        atlas = np.zeros((rows * th, cols * tw, 4), np.float32)
        atlas[..., 3] = 1.0
        for num, px in tiles.items():
            c, r = cells[num]
            if px.shape[:2] != (th, tw):
                yy = (np.arange(th) * px.shape[0] // th)[:, None]
                xx = (np.arange(tw) * px.shape[1] // tw)[None, :]
                px = px[yy, xx]
            # `px` has its top row first; tile row r counts from the bottom of the atlas.
            y0 = (rows - 1 - r) * th
            atlas[y0 : y0 + th, c * tw : (c + 1) * tw] = px
        self.images[key] = self.scene.add_image(atlas)
        return self.images[key]

    @staticmethod
    def udim_layout_of(image):
        nums = sorted(t.number for t in image.tiles)
        cells = {num: ((num - 1001) % 10, (num - 1001) // 10) for num in nums}
        return cells, max(c for c, _ in cells.values()) + 1, max(r for _, r in cells.values()) + 1

    def metallic_roughness(self, inputs, params, material):
        """glTF packs roughness (G) and metallic (B) in one image; build it from the two textures."""
        m, r = inputs["Metallic"], inputs["Roughness"]
        tm, tr = self.texture_of(m, material, quiet=True), self.texture_of(r, material, quiet=True)
        if tm is None and tr is None:
            return {}
        w = h = 1
        sources = {}
        for name, sock in (("m", m), ("r", r)):
            n = sock.links[0].from_node if sock.is_linked and sock.links[0].from_node.bl_idname in IMAGE_NODES else None
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


def atlas_uvs(uvs, cols, rows):
    """Blender's UV space puts tile (c, r) at [c, c+1] x [r, r+1]; the atlas has the same cells scaled
    to the unit square, so a UDIM material's UVs only need dividing by the grid size."""
    return uvs / np.array([cols, rows], np.float32)
