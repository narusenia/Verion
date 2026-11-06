"""Verion's own material node tree.

The renderer's material is a fixed parameter set (the glTF model plus dispersion), not a shader
program, so the tree mirrors it: one Verion Surface node whose sockets are those parameters, Verion
Image nodes for the textures, and a Verion Output. A tree is bound to a material in the Material tab
(`Material.verion_surface.node_tree`); `materials.Converter` reads it instead of the Blender tree.
Nothing here is shown to Cycles or EEVEE: they ignore the tree.
"""
import bpy
import nodeitems_utils
from bpy.props import PointerProperty
from nodeitems_utils import NodeCategory, NodeItem

TREE = "VerionNodeTree"
SURFACE = "VerionNodeSurface"
OUTPUT = "VerionNodeOutput"
IMAGE = "VerionNodeImage"


class VerionNodeTree(bpy.types.NodeTree):
    bl_idname = TREE
    bl_label = "Verion Material"
    bl_icon = "NODE_MATERIAL"

    def update(self):
        # The tree is not a dependency of the material in the depsgraph: tell it that it changed.
        for m in bpy.data.materials:
            if m.verion_surface.node_tree == self:
                m.update_tag()


def signature(tree):
    """A comparable summary of everything the converter reads from a tree (values, links, images)."""
    def value(s):
        v = getattr(s, "default_value", None)
        return tuple(v) if hasattr(v, "__len__") else v

    return tuple(
        (n.name, n.bl_idname, n.image.name_full if n.bl_idname == IMAGE and n.image else None,
         tuple((s.name, value(s), tuple((l.from_node.name, l.from_socket.name) for l in s.links)) for s in n.inputs))
        for n in sorted(tree.nodes, key=lambda n: n.name)
    )


class VerionSocketSurface(bpy.types.NodeSocket):
    bl_idname = "VerionSocketSurface"
    bl_label = "Surface"

    def draw(self, context, layout, node, text):
        layout.label(text=text)

    @classmethod
    def draw_color_simple(cls):
        return (0.39, 0.78, 0.39, 1.0)


class _Node:
    @classmethod
    def poll(cls, ntree):
        return ntree.bl_idname == TREE


class VerionNodeOutput(_Node, bpy.types.Node):
    bl_idname = OUTPUT
    bl_label = "Verion Output"

    def init(self, context):
        self.inputs.new("VerionSocketSurface", "Surface")


# (socket type, name, default): the parameters of `scene.add_material`, in panel order.
SURFACE_INPUTS = (
    ("NodeSocketColor", "Base Color", (0.8, 0.8, 0.8, 1.0)),
    ("NodeSocketFloatFactor", "Metallic", 0.0),
    ("NodeSocketFloatFactor", "Roughness", 0.5),
    ("NodeSocketFloatFactor", "Transmission", 0.0),
    ("NodeSocketFloat", "IOR", 1.5),
    ("NodeSocketFloat", "Dispersion", 0.0),
    ("NodeSocketFloatFactor", "Opacity", 1.0),
    ("NodeSocketFloatFactor", "Clearcoat", 0.0),
    ("NodeSocketFloatFactor", "Clearcoat Roughness", 0.0),
    ("NodeSocketColor", "Sheen Color", (0.0, 0.0, 0.0, 1.0)),
    ("NodeSocketFloatFactor", "Sheen Roughness", 0.0),
    ("NodeSocketColor", "Emission", (0.0, 0.0, 0.0, 1.0)),
    ("NodeSocketFloat", "Emission Strength", 1.0),
    ("NodeSocketColor", "Normal Map", (0.5, 0.5, 1.0, 1.0)),
    ("NodeSocketFloat", "Normal Scale", 1.0),
)


class VerionNodeSurface(_Node, bpy.types.Node):
    bl_idname = SURFACE
    bl_label = "Verion Surface"

    def init(self, context):
        for kind, name, default in SURFACE_INPUTS:
            self.inputs.new(kind, name).default_value = default
        self.outputs.new("VerionSocketSurface", "Surface")
        self.width = 220


class VerionNodeImage(_Node, bpy.types.Node):
    """A texture. Its color feeds a color socket; a scalar socket (Roughness, Metallic) uses the red channel."""

    bl_idname = IMAGE
    bl_label = "Verion Image"
    image: PointerProperty(type=bpy.types.Image)

    def init(self, context):
        self.outputs.new("NodeSocketColor", "Color")

    def draw_buttons(self, context, layout):
        layout.template_ID(self, "image", open="image.open")


class VERION_OT_node_tree_new(bpy.types.Operator):
    bl_idname = "verion.node_tree_new"
    bl_label = "New Verion Nodes"
    bl_description = "Create a Verion node tree (Surface and Output) for this material"
    bl_options = {"UNDO"}

    @classmethod
    def poll(cls, context):
        return context.material is not None

    def execute(self, context):
        mat = context.material
        tree = bpy.data.node_groups.new(mat.name, TREE)
        surface = tree.nodes.new(SURFACE)
        out = tree.nodes.new(OUTPUT)
        surface.location = (-260, 0)
        out.location = (60, 0)
        tree.links.new(surface.outputs["Surface"], out.inputs["Surface"])
        mat.verion_surface.node_tree = tree
        return {"FINISHED"}


class _Category(NodeCategory):
    @classmethod
    def poll(cls, context):
        return context.space_data.tree_type == TREE


CATEGORIES = [
    _Category("VERION_SHADER", "Shader", items=[NodeItem(SURFACE), NodeItem(OUTPUT)]),
    _Category("VERION_INPUT", "Input", items=[NodeItem(IMAGE)]),
]

classes = (VerionNodeTree, VerionSocketSurface, VerionNodeOutput, VerionNodeSurface, VerionNodeImage, VERION_OT_node_tree_new)


def register():
    for c in classes:
        bpy.utils.register_class(c)
    nodeitems_utils.register_node_categories("VERION_NODES", CATEGORIES)


def unregister():
    nodeitems_utils.unregister_node_categories("VERION_NODES")
    for c in reversed(classes):
        bpy.utils.unregister_class(c)
