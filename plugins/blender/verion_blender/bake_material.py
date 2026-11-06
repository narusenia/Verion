"""Bakes the procedural inputs of a Principled BSDF (noise, ramps, math, ...) to textures.

Verion has no procedural nodes, so each socket fed by something other than an image texture is
rendered by Cycles in a background Blender, as an emission bake over the object's UV map, and used as
an image texture (REQ-DCC-003). The mesh needs UVs to carry the result.
"""
import json
import os
import subprocess
import tempfile

import bpy
import numpy as np

from . import bake_world

_cache = {}


def bake(material, ob, sockets, size):
    """{key: float32 (H, W, 3), first row on top} for `sockets`, a list of (key, node name, input
    identifier). Raises RuntimeError."""
    key = (bake_world.tree_signature(material.node_tree), size, ob.original.data.name, json.dumps(sockets))
    if key in _cache:
        return _cache[key]
    with tempfile.TemporaryDirectory(prefix="verion_mat_") as d:
        blend = os.path.join(d, "mat.blend")
        bpy.data.libraries.write(blend, {ob.original, material}, fake_user=True)
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bake_material_job.py")
        cmd = [bpy.app.binary_path, "-b", "--factory-startup", "--python-exit-code", "1", "--python", script, "--",
               blend, d, str(size), ob.original.name, material.name, json.dumps(sockets)]
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        except (OSError, subprocess.TimeoutExpired) as e:
            raise RuntimeError(f"could not run Blender to bake material '{material.name}': {e}") from e
        out = {}
        for k, _node, _ident in sockets:
            path = os.path.join(d, k + ".exr")
            if r.returncode != 0 or not os.path.exists(path):
                tail = (r.stdout + r.stderr).strip().splitlines()[-5:]
                raise RuntimeError(f"baking material '{material.name}' failed: " + " | ".join(tail))
            im = bpy.data.images.load(path, check_existing=False)
            try:
                ch = im.channels
                buf = np.empty(size * size * ch, np.float32)
                im.pixels.foreach_get(buf)
            finally:
                bpy.data.images.remove(im)
            out[k] = buf.reshape(size, size, ch)[::-1, :, :3].copy()
    _cache[key] = out
    return out
