"""Run by scripts/package_blender.sh in a Blender that has the built extension installed (and nothing
else): enables it and renders a small scene with Verion, with the denoiser on."""
import bpy
import numpy as np

mod = next(m for m in bpy.context.preferences.addons.keys() if m.endswith(".verion"))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.preferences.addon_enable(module=mod)
sc = bpy.context.scene
bpy.ops.mesh.primitive_uv_sphere_add(location=(0, 0, 0))
light = bpy.data.objects.new("l", bpy.data.lights.new("l", "SUN"))
light.rotation_euler = (0.6, 0.2, 0.4)
sc.collection.objects.link(light)
cam = bpy.data.objects.new("c", bpy.data.cameras.new("c"))
cam.location = (0, -5, 1)
cam.rotation_euler = (1.45, 0, 0)
sc.collection.objects.link(cam)
sc.camera = cam
sc.render.engine = "VERION"
sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = 64, 48, 100
sc.verion.samples = 8
sc.verion.denoise = True
bpy.ops.render.render(write_still=False)
px = np.array(bpy.data.images["Render Result"].pixels[:]) if "Render Result" in bpy.data.images else None
import verion

assert "extensions" in verion.__file__, f"the native module did not come from the extension: {verion.__file__}"
print("SMOKE ok", mod, verion.__file__)
