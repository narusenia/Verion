"""Runs inside a background Blender started by bake_material.py: bakes the node trees feeding some
sockets of a shader node into images with Cycles. Arguments after `--`: the .blend with the object and
the material, the output directory, the image size, the object name, the material name and a JSON list
of [key, node name, input identifier]."""
import json
import os
import sys

import bpy

blend, out_dir, size, ob_name, mat_name, spec = sys.argv[sys.argv.index("--") + 1 :][:6]
size, spec = int(size), json.loads(spec)

bpy.ops.wm.read_factory_settings(use_empty=True)
with bpy.data.libraries.load(blend) as (src, dst):
    dst.objects = [ob_name]
    dst.materials = [mat_name]
ob, mat = dst.objects[0], dst.materials[0]
scene = bpy.context.scene
scene.collection.objects.link(ob)
bpy.context.view_layer.objects.active = ob
ob.select_set(True)
ob.data.materials.clear()  # every face bakes this material
ob.data.materials.append(mat)
if not ob.data.uv_layers:
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project()
    bpy.ops.object.mode_set(mode="OBJECT")

scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 4  # procedural colors are deterministic; the samples only filter the edges
scene.cycles.bake_type = "EMIT"
scene.render.bake.margin = 16
scene.view_settings.view_transform = "Standard"

tree = mat.node_tree
out_node = next(n for n in tree.nodes if n.bl_idname == "ShaderNodeOutputMaterial" and n.is_active_output)
surface = out_node.inputs["Surface"]
original = surface.links[0].from_socket if surface.is_linked else None
emit = tree.nodes.new("ShaderNodeEmission")
target = tree.nodes.new("ShaderNodeTexImage")
for key, node_name, ident in spec:
    sock = tree.nodes[node_name].inputs[ident]
    image = bpy.data.images.new(key, size, size, alpha=False, float_buffer=True)
    image.colorspace_settings.name = "Non-Color"  # raw values: no display transform on the way out
    target.image = image
    tree.nodes.active = target
    for l in list(emit.inputs["Color"].links):
        tree.links.remove(l)
    if sock.is_linked:
        tree.links.new(sock.links[0].from_socket, emit.inputs["Color"])
    tree.links.new(emit.outputs["Emission"], surface)
    bpy.ops.object.bake(type="EMIT")
    image.filepath_raw = os.path.join(out_dir, key + ".exr")
    image.file_format = "OPEN_EXR"
    image.save()
if original is not None:
    tree.links.new(original, surface)
