"""The Blender World to Verion lights."""
import numpy as np

from . import bake_world, images


def _background(world):
    """The Background node feeding the active World Output, or None."""
    if not world.use_nodes or world.node_tree is None:
        return None
    nodes = world.node_tree.nodes
    outs = [n for n in nodes if n.bl_idname == "ShaderNodeOutputWorld"]
    out = next((n for n in outs if n.is_active_output), outs[0] if outs else None)
    if out is None or not out.inputs["Surface"].is_linked:
        return None
    node = out.inputs["Surface"].links[0].from_node
    return node if node.bl_idname == "ShaderNodeBackground" else None


def describe(world, warn):
    """('color', rgb) / ('image', blender image, strength, z rotation) / ('none',) for a World."""
    if world is None:
        return ("none",)
    if not world.use_nodes:
        return ("color", tuple(world.color))
    bg = _background(world)
    if bg is None:
        return ("baked", world, 1.0)  # other shader trees are rendered as they are
    strength = bg.inputs["Strength"]
    if strength.is_linked:
        warn("World: a linked Strength is not supported; using its default")
    s = float(strength.default_value)
    col = bg.inputs["Color"]
    if not col.is_linked:
        c = tuple(float(x) for x in col.default_value[:3])
        return ("color", tuple(x * s for x in c))
    src = col.links[0].from_node
    if src.bl_idname == "ShaderNodeTexEnvironment" and src.image is not None:
        rot = 0.0
        vec = src.inputs["Vector"]
        if vec.is_linked:
            m = vec.links[0].from_node
            if m.bl_idname == "ShaderNodeMapping":
                rot = float(m.inputs["Rotation"].default_value[2])
                if any(abs(x) > 1e-6 for x in m.inputs["Rotation"].default_value[:2]) or any(
                    abs(x) > 1e-6 for x in m.inputs["Location"].default_value
                ):
                    warn("World: only the Z rotation of a Mapping node is supported")
            else:
                warn("World: the texture coordinates of the Environment Texture are not supported")
        return ("image", src.image, s, rot)
    # Anything procedural (Sky Texture, gradients, noise, mixes): rendered to an HDRI by Cycles.
    return ("baked", world, 1.0)


def _to_rgba(px):
    return np.ascontiguousarray(np.concatenate([px, np.ones(px.shape[:2] + (1,), np.float32)], axis=2))


def apply(scene, desc, warn, state):
    """Adds the World's light to `scene`. Returns the light index (or None). `state` keeps the
    image index of an HDRI between calls."""
    kind = desc[0]
    if kind == "color":
        return scene.add_light("environment", color=tuple(desc[1]))
    if kind == "image":
        _, image, strength, rot = desc
        px = images.pixels(image)
        if px is None:
            warn(f"World: image '{image.name}' has no pixels")
            return None
        px = px[..., :3]
        # The image center faces Blender's +X in Cycles and -Z in Verion space; a quarter turn of
        # the image about the vertical axis lines them up (tests/test_world.py compares the two).
        w = px.shape[1]
        shift = int(round((rot / (2 * np.pi)) * w)) + w // 4
        px = np.roll(px, shift, axis=1)
        idx = scene.add_image(np.ascontiguousarray(px))
        return scene.add_light("environment_map", intensity=strength, image=idx)
    if kind == "baked":
        try:
            px = bake_world.bake(desc[1])
        except RuntimeError as e:
            warn(f"World: {e}; the world is black")
            return None
        return scene.add_light("environment_map", intensity=desc[2], image=scene.add_image(_to_rgba(np.roll(px, px.shape[1] // 4, axis=1))))
    return None
