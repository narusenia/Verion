"""Bakes a procedural World (Sky Texture, gradients, noise, ...) to an equirectangular HDRI.

Verion has no procedural nodes, so the World is rendered by Cycles in a background Blender, as a
panorama camera at the origin, and the result is used as an environment map (ADR-0019). The image
has the layout of an Environment Texture, so it goes through the same orientation step.
"""
import hashlib
import os
import subprocess
import sys
import tempfile

import bpy
import numpy as np

WIDTH, HEIGHT = 2048, 1024
_cache = {}


def signature(world):
    """A hash of everything in the World's node tree that changes the picture."""
    if world.node_tree is None:
        return hashlib.sha1(repr(tuple(world.color)).encode()).hexdigest()
    return tree_signature(world.node_tree)


def tree_signature(tree):
    """A hash of every node setting, input value and link of a node tree."""
    h = hashlib.sha1()
    for node in sorted(tree.nodes, key=lambda n: n.name):
        h.update(node.bl_idname.encode())
        for p in node.bl_rna.properties:
            if p.identifier in {"location", "width", "height", "select", "name", "label", "dimensions", "color"}:
                continue
            try:
                v = getattr(node, p.identifier)
            except AttributeError:
                continue
            if hasattr(v, "name") and hasattr(v, "filepath"):
                v = (v.name, v.filepath)  # an image
            if p.type in {"POINTER", "COLLECTION"} and not isinstance(v, tuple):
                continue
            h.update(f"{p.identifier}={tuple(v) if hasattr(v, '__len__') and not isinstance(v, (str, tuple)) else v!r}".encode())
        for i in node.inputs:
            if hasattr(i, "default_value"):
                dv = i.default_value
                h.update(repr(tuple(dv) if hasattr(dv, "__len__") else dv).encode())
    for l in tree.links:
        h.update(f"{l.from_node.name}.{l.from_socket.identifier}>{l.to_node.name}.{l.to_socket.identifier}".encode())
    return h.hexdigest()


def bake(world, width=WIDTH, height=HEIGHT):
    """The World as a float32 (H, W, 3) image in linear Rec.709, first row on top. Raises RuntimeError."""
    key = (signature(world), width, height)
    if key in _cache:
        return _cache[key]
    with tempfile.TemporaryDirectory(prefix="verion_world_") as d:
        blend = os.path.join(d, "world.blend")
        out = os.path.join(d, "sky.exr")
        bpy.data.libraries.write(blend, {world}, fake_user=True)
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bake_world_job.py")
        cmd = [bpy.app.binary_path, "-b", "--factory-startup", "--python-exit-code", "1",
               "--python", script, "--", blend, out, str(width), str(height)]
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        except (OSError, subprocess.TimeoutExpired) as e:
            raise RuntimeError(f"could not run Blender to bake the world: {e}") from e
        if r.returncode != 0 or not os.path.exists(out):
            tail = (r.stdout + r.stderr).strip().splitlines()[-5:]
            raise RuntimeError("baking the world failed: " + " | ".join(tail))
        im = bpy.data.images.load(out, check_existing=False)
        channels = im.channels
        try:
            buf = np.empty(width * height * channels, np.float32)
            im.pixels.foreach_get(buf)
        finally:
            bpy.data.images.remove(im)
    px = buf.reshape(height, width, channels)[::-1, :, :3].copy()
    _cache[key] = px
    return px
