"""Shared helpers of the Blender add-on tests. Run them with scripts/blender_test.sh."""
import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))  # plugins/blender, which holds the verion_blender package


def enable_addon():
    import verion_blender

    try:
        verion_blender.register()
    except ValueError:
        pass  # already registered
    return verion_blender


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    return bpy.context.scene


def add_camera(location=(0, -6, 2), target=(0, 0, 0.5), lens=50.0):
    cam = bpy.data.cameras.new("cam")
    cam.lens = lens
    ob = bpy.data.objects.new("cam", cam)
    bpy.context.scene.collection.objects.link(ob)
    d = np.array(target) - np.array(location)
    from mathutils import Vector

    ob.location = location
    ob.rotation_euler = Vector(d).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = ob
    return ob


def add_plane(size=10.0, z=0.0, color=(0.8, 0.8, 0.8), name="plane"):
    me = bpy.data.meshes.new(name)
    h = size / 2
    me.from_pydata([(-h, -h, z), (h, -h, z), (h, h, z), (-h, h, z)], [], [(0, 1, 2, 3)])
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(diffuse_material(name, color))
    return ob


def add_sphere(location=(0, 0, 1), radius=1.0, color=(0.8, 0.2, 0.1), roughness=0.4, metallic=0.0, name="ball"):
    import bmesh

    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=48, v_segments=24, radius=radius)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    ob.location = location
    bpy.context.scene.collection.objects.link(ob)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = roughness
    b.inputs["Metallic"].default_value = metallic
    me.materials.append(mat)
    return ob


def diffuse_material(name, color):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = 1.0
    b.inputs["Metallic"].default_value = 0.0
    return mat


def add_light(kind="POINT", location=(2, -2, 4), energy=1000.0, color=(1, 1, 1), name="light"):
    light = bpy.data.lights.new(name, kind)
    light.energy = energy
    light.color = color
    ob = bpy.data.objects.new(name, light)
    ob.location = location
    bpy.context.scene.collection.objects.link(ob)
    return ob


def set_world(color=(0.05, 0.05, 0.05), strength=1.0):
    w = bpy.data.worlds.new("world")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*color, 1)
    bg.inputs["Strength"].default_value = strength
    bpy.context.scene.world = w
    return w


def render(engine, path, width=96, height=72, samples=16):
    """Renders the current scene with `engine` into an EXR and returns its pixels (H, W, 3), top row first."""
    sc = bpy.context.scene
    sc.render.engine = engine
    sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = width, height, 100
    sc.render.image_settings.file_format = "OPEN_EXR"
    sc.render.image_settings.color_depth = "32"
    sc.render.filepath = path
    if engine == "VERION":
        sc.verion.samples = samples
    else:
        sc.cycles.samples = samples
        sc.cycles.use_denoising = False
        sc.cycles.device = "CPU"
    bpy.ops.render.render(write_still=True)
    im = bpy.data.images.load(path + ("" if path.endswith(".exr") else ".exr"), check_existing=False)
    px = np.empty(width * height * im.channels, np.float32)
    im.pixels.foreach_get(px)
    a = px.reshape(height, width, im.channels)[::-1, :, :3]
    bpy.data.images.remove(im)
    return a


def save_png(path, rgb):
    """A quick sRGB preview of linear (H, W, 3) pixels, for looking at results."""
    import struct
    import zlib

    a = np.clip(rgb, 0, 1)
    a = np.where(a <= 0.0031308, a * 12.92, 1.055 * a ** (1 / 2.4) - 0.055)
    a = (a * 255 + 0.5).astype(np.uint8)
    h, w = a.shape[:2]
    raw = b"".join(b"\0" + a[y].tobytes() for y in range(h))

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
