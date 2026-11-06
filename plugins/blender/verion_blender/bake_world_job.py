"""Runs inside a background Blender started by bake_world.py: renders a World as an equirectangular
panorama with Cycles. Arguments after `--`: the .blend with the world, the output EXR, width, height."""
import math
import sys

import bpy
import mathutils

blend, out, width, height = sys.argv[sys.argv.index("--") + 1 :][:4]
width, height = int(width), int(height)

bpy.ops.wm.read_factory_settings(use_empty=True)
with bpy.data.libraries.load(blend) as (src, dst):
    dst.worlds = list(src.worlds)
world = dst.worlds[0]
scene = bpy.context.scene
scene.world = world
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 16
scene.cycles.use_denoising = False
scene.cycles.filter_width = 1.0
scene.render.resolution_x, scene.render.resolution_y, scene.render.resolution_percentage = width, height, 100
scene.render.film_transparent = False
scene.render.image_settings.file_format = "OPEN_EXR"
scene.render.image_settings.color_depth = "32"
scene.render.filepath = out
scene.view_settings.view_transform = "Standard"

cam = bpy.data.cameras.new("pano")
cam.type = "PANO"
cam.panorama_type = "EQUIRECTANGULAR"
cam.latitude_min, cam.latitude_max = -math.pi / 2, math.pi / 2
cam.longitude_min, cam.longitude_max = -math.pi, math.pi
cam.clip_start, cam.clip_end = 0.01, 1e5
ob = bpy.data.objects.new("pano", cam)
scene.collection.objects.link(ob)
# The image center faces +X, like an Environment Texture's (see world.py).
ob.rotation_euler = mathutils.Matrix([[0, 0, -1], [-1, 0, 0], [0, 1, 0]]).to_euler()
scene.camera = ob
bpy.ops.render.render(write_still=True)
