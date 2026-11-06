"""Blender lights to Verion lights.

Point, Spot and Sun lights map to the IR's punctual lights. Area lights have no IR light: they
become an emissive quad or disk, which the renderer samples as an area light (emissive triangles).
"""
import math

import bpy
import mathutils
import numpy as np

from . import convert, units


def _frame(ob):
    """Position and unit direction the light faces (Blender lights shine along local -Z), in Verion space."""
    world = ob.matrix_world.normalized()
    d = world.to_3x3() @ mathutils.Vector((0.0, 0.0, -1.0))
    return convert.point(world.translation), convert.direction(d)


def punctual(ob):
    """The keyword arguments of `Scene.add_light` for a Point, Spot or Sun light object."""
    light = ob.data
    color = convert.rgb(light.color)
    position, direction = _frame(ob)
    if light.type == "POINT":
        return dict(kind="point", color=color, intensity=light.energy * units.POINT_PER_WATT, position=position)
    if light.type == "SUN":
        return dict(kind="directional", color=color, intensity=light.energy * units.SUN_PER_STRENGTH, direction=direction)
    outer = light.spot_size * 0.5
    # Cycles blends over `spot_blend` of the cone, measured in cos(angle) from the edge.
    inner = math.acos(math.cos(outer) + (1.0 - math.cos(outer)) * light.spot_blend)
    return dict(
        kind="spot", color=color, intensity=light.energy * units.SPOT_PER_WATT,
        position=position, direction=direction, inner_cone=inner, outer_cone=outer,
    )


def add(scene, ob, warn):
    """Adds a Point, Spot or Sun light object; returns its IR light index."""
    if getattr(ob.data, "shadow_soft_size", 0.0) > 0.0 and ob.data.type != "SUN":
        warn(f"Light '{ob.name}': a non-zero radius is rendered as a point (no soft shadows from punctual lights)")
    return scene.add_light(**punctual(ob))


def ies(ob, warn):
    """(IES text, world frame rows x, y, z in Verion space) when a Point or Spot light's node tree has an
    IES Texture, else None. Vertical angle 0 of the profile points along the light's -Z."""
    light = ob.data
    if light.type == "SUN" or not getattr(light, "node_tree", None):
        return None
    node = next((n for n in light.node_tree.nodes if n.bl_idname == "ShaderNodeTexIES"), None)
    if node is None:
        return None
    try:
        if node.mode == "INTERNAL":
            text = node.ies.as_string() if node.ies is not None else None
        else:
            with open(bpy.path.abspath(node.filepath), encoding="latin-1") as f:
                text = f.read()
    except OSError as e:
        warn(f"Light '{ob.name}': the IES file could not be read ({e}); using a plain light")
        return None
    if not text:
        return None
    rot = ob.matrix_world.normalized().to_3x3()
    axes = [convert.direction(rot @ mathutils.Vector(v)) for v in ((1, 0, 0), (0, 1, 0), (0, 0, 1))]
    return text, axes


def update(scene, index, ob):
    scene.set_light(index, **punctual(ob))


# -- area lights ---------------------------------------------------------------------------------

def area_shape(light):
    """(positions (N, 3), triangle vertex indices) of an area light in the light's local space,
    facing -Z, and the area."""
    sx = light.size
    sy = light.size_y if light.shape in {"RECTANGLE", "ELLIPSE"} else light.size
    if light.shape in {"SQUARE", "RECTANGLE"}:
        h = np.array([[-sx, -sy], [sx, -sy], [sx, sy], [-sx, sy]], np.float32) / 2
        tri = np.array([0, 2, 1, 0, 3, 2], np.uint32)  # counter-clockwise seen from -Z
        area = sx * sy
    else:
        n = 48
        a = np.linspace(0, 2 * np.pi, n, endpoint=False)
        h = np.stack([np.cos(a) * sx / 2, np.sin(a) * sy / 2], axis=1).astype(np.float32)
        h = np.concatenate([np.zeros((1, 2), np.float32), h])
        tri = np.array([[0, 1 + (i + 1) % n, 1 + i] for i in range(n)], np.uint32).ravel()
        area = math.pi * sx * sy / 4
    pos = np.concatenate([h, np.zeros((len(h), 1), np.float32)], axis=1)
    return np.ascontiguousarray(pos), tri, area


def area_emission(light, area):
    """Radiance of the emitting surface that gives the light's power as Cycles defines it."""
    k = units.AREA_RADIANCE_PER_WATT / area
    return [c * light.energy * k for c in convert.rgb(light.color)]


def area_signature(light):
    return (light.shape, light.size, light.size_y)


def add_area(scene, ob, warn):
    """Adds an area light as an emissive surface. Returns (mesh, material, instance) indices."""
    light = ob.data
    pos, tri, area = area_shape(light)
    mesh = scene.add_mesh(pos, tri)
    mat = scene.add_material(base_color=[0.0, 0.0, 0.0], emission=area_emission(light, area))
    inst = scene.add_instance(mesh, mat, convert.matrix(ob.matrix_world))
    if light.spread < math.pi - 1e-3:
        warn(f"Light '{ob.name}': Spread is not supported; the area light emits over the whole hemisphere")
    return mesh, mat, inst


def update_area(scene, rec, ob):
    mesh, mat, inst = rec
    _, _, area = area_shape(ob.data)
    scene.set_material(mat, base_color=[0.0, 0.0, 0.0], emission=area_emission(ob.data, area))
    scene.set_instance(inst, mesh, mat, convert.matrix(ob.matrix_world))
