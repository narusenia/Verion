"""Blender depsgraph to a Verion scene (REQ-DCC-001).

`Sync.build` converts the whole depsgraph. `Sync.update` follows the edits of a viewport session:
it changes what can change in place (transforms, materials, lights, the camera, the world) and
reports `False` when the scene's structure changed, so the caller rebuilds.
"""
import numpy as np

from . import camera as camera_mod
from . import convert, lights, materials, stylization, units, world as world_mod

GEOMETRY = {"MESH", "CURVE", "SURFACE", "FONT", "META"}


class Sync:
    def __init__(self, native, report=None):
        self.native = native
        self.report = report or (lambda level, msg: print(f"{level}: {msg}"))
        self.scene = native.Scene("rec709")
        self.materials = materials.Converter(self.scene, self.warn)
        self._warned = set()
        self.mesh_cache = {}     # mesh key -> [(IR mesh index, material slot)]
        self.instances = {}      # instance key -> [(IR instance index, IR mesh index, slot, object)]
        self.light_obs = {}      # light key -> Blender object
        self.lights = {}         # instance key -> IR light index
        self.world_light = None
        self.world_desc = None
        self.camera = None       # (object, width, height) when the scene's camera drives the view

    def warn(self, msg):
        if msg not in self._warned:
            self._warned.add(msg)
            self.report("WARNING", msg)

    # -- keys -----------------------------------------------------------------------------------

    @staticmethod
    def instance_key(inst):
        ob = inst.object
        base = ob.original.name_full
        return (base, tuple(inst.persistent_id)) if inst.is_instance else (base,)

    def mesh_key(self, ob):
        orig = ob.original
        data = orig.data.name_full if orig.data is not None else orig.name_full
        # Modifiers make the evaluated mesh per object even when the data is shared; UDIM materials
        # move the UVs, so objects sharing the mesh with other materials get their own copy.
        udim = tuple(
            (m.name_full, lay[1:]) for m in (s.material for s in ob.material_slots)
            if m is not None and (lay := self.materials.udim_layout(m)) is not None
        )
        return ((data, orig.name_full) if len(orig.modifiers) else (data,)) + udim

    # -- geometry -------------------------------------------------------------------------------

    def mesh_parts(self, depsgraph, ob):
        """[(material slot, positions, tri_vertices, normals, uvs)] of an evaluated object."""
        me = ob.to_mesh(preserve_all_data_layers=False, depsgraph=depsgraph)
        if me is None:
            return []
        try:
            me.calc_loop_triangles()
            nt = len(me.loop_triangles)
            if nt == 0:
                return []
            co = np.empty(len(me.vertices) * 3, np.float32)
            me.vertices.foreach_get("co", co)
            co = co.reshape(-1, 3)
            tv = np.empty(nt * 3, np.uint32)
            me.loop_triangles.foreach_get("vertices", tv)
            tl = np.empty(nt * 3, np.uint32)
            me.loop_triangles.foreach_get("loops", tl)
            slot = np.empty(nt, np.int32)
            me.loop_triangles.foreach_get("material_index", slot)
            cn = np.empty(len(me.loops) * 3, np.float32)
            me.corner_normals.foreach_get("vector", cn)
            normals = cn.reshape(-1, 3)[tl]
            uvs = None
            if me.uv_layers.active is not None:
                uv = np.empty(len(me.loops) * 2, np.float32)
                me.uv_layers.active.data.foreach_get("uv", uv)
                uvs = uv.reshape(-1, 2)[tl]
            parts = []
            for s in np.unique(slot):
                sel = np.repeat(slot == s, 3)
                part_uvs = None if uvs is None else np.ascontiguousarray(uvs[sel])
                layout = self.materials.udim_layout(self.slot_blender_material(ob, int(s)))
                if layout is not None and part_uvs is not None:
                    part_uvs = materials.atlas_uvs(part_uvs, layout[1], layout[2])
                if part_uvs is not None:
                    part_uvs = np.stack([part_uvs[:, 0], 1.0 - part_uvs[:, 1]], axis=1)  # images are stored top row first
                parts.append((int(s), co, tv[sel], np.ascontiguousarray(normals[sel]), part_uvs))
            return parts
        finally:
            ob.to_mesh_clear()

    @staticmethod
    def slot_blender_material(ob, slot):
        slots = ob.material_slots
        return slots[min(slot, len(slots) - 1)].material if len(slots) else None

    def slot_material(self, ob, slot):
        self.materials.bake_ob = ob  # procedural inputs bake over the UVs of the first object that uses the material
        return self.materials.material(self.slot_blender_material(ob, slot))

    def add_geometry(self, depsgraph, inst):
        ob, key = inst.object, self.instance_key(inst)
        mk = self.mesh_key(ob)
        if mk not in self.mesh_cache:
            self.mesh_cache[mk] = [
                (self.scene.add_mesh_corners(co, tv, n, uv), s) for s, co, tv, n, uv in self.mesh_parts(depsgraph, ob)
            ]
        mat = convert.matrix(inst.matrix_world)
        recs = []
        for mesh, slot in self.mesh_cache[mk]:
            idx = self.scene.add_instance(mesh, self.slot_material(ob, slot), mat)
            recs.append((idx, mesh, slot, ob))
        self.instances[key] = recs

    # -- the whole scene ------------------------------------------------------------------------

    def build(self, depsgraph, width, height, cam_ob=None, with_camera=True):
        scene = depsgraph.scene
        self.materials.bake_size = int(scene.verion.bake_size)
        for inst in depsgraph.object_instances:
            ob = inst.object
            if ob.type in GEOMETRY:
                self.add_geometry(depsgraph, inst)
            elif ob.type == "LIGHT":
                key = self.instance_key(inst)
                self.light_obs[key] = ob
                if ob.data.type == "AREA":
                    self.lights[key] = ("area", lights.area_signature(ob.data), lights.add_area(self.scene, ob, self.warn))
                else:
                    self.lights[key] = ("punctual", lights.add(self.scene, ob, self.warn))
        self.world_desc = world_mod.describe(scene.world, self.warn)
        self.world_light = world_mod.apply(self.scene, self.world_desc, self.warn, {})
        stylization.apply_world(self.scene, scene.world)
        self.apply_light_extras()
        cam_ob = cam_ob or scene.camera
        if not with_camera:
            pass  # the viewport sets the camera from the 3D view
        elif cam_ob is None:
            self.warn("The scene has no camera")
            self.scene.frame_camera()
        else:
            self.set_camera(depsgraph, cam_ob, width, height)
        for w in self.scene.take_warnings():
            self.warn(w)
        return self.scene

    def set_camera(self, depsgraph, cam_ob, width, height):
        t, fov, focus, radius, shift = camera_mod.settings(depsgraph, cam_ob, width, height, self.warn)
        self.scene.set_camera(t, fov, focus, radius, shift)
        self.camera = (cam_ob, width, height)

    # -- light linking and IES ---------------------------------------------------------------------

    @staticmethod
    def receivers(collection):
        """(included, excluded): object names a light's receiver collection names, children included."""
        inc, exc = set(), set()

        def walk(col, state):
            for ob, co in zip(col.objects, col.collection_objects):  # the two lists run in step
                st = co.light_linking.link_state if state is None else state
                (inc if st == "INCLUDE" else exc).add(ob.name_full)
            for child, ch in zip(col.children, col.collection_children):
                walk(child, ch.light_linking.link_state)

        walk(collection, None)
        return inc, exc

    def apply_light_extras(self):
        """Light linking (receivers, up to 31 linked lights) and IES profiles of the punctual lights.

        A linked light gets one group bit; an instance carries the bits of the lights that shine on
        it. Unlinked lights use bit 31, which every instance has. Blocker collections and linked area
        lights are not supported."""
        UNLINKED = 0x80000000
        masks = {}
        bit = 0
        for key, rec in self.lights.items():
            ob = self.light_obs[key]
            ll = ob.light_linking
            if ll.blocker_collection is not None:
                self.warn(f"Light '{ob.name}': blocker linking is not supported")
            if ll.receiver_collection is None:
                continue
            if rec[0] == "area":
                self.warn(f"Light '{ob.name}': light linking of area lights is not supported")
                continue
            if bit >= 31:
                self.warn("Light linking supports 31 linked lights; the rest shine on everything")
                continue
            masks[key] = (1 << bit, self.receivers(ll.receiver_collection))
            bit += 1
        inst_mask = {}
        for recs in self.instances.values():
            for idx, _mesh, _slot, ob in recs:
                m = UNLINKED
                name = ob.original.name_full
                for lbit, (inc, exc) in masks.values():
                    if (name in inc) if inc else (name not in exc):
                        m |= lbit
                inst_mask[idx] = m
        for idx, m in inst_mask.items():
            self.scene.set_instance_light_mask(idx, m)
        for key, rec in self.lights.items():
            if rec[0] != "punctual":
                continue
            ob = self.light_obs[key]
            extra = lights.ies(ob, self.warn)
            kw = dict(link_mask=masks[key][0] if key in masks else UNLINKED)
            if extra is not None:
                kw["ies"], kw["frame"] = extra
                kw["ies_scale"] = units.IES_PER_CANDELA
            try:
                self.scene.set_light_extra(rec[1], **kw)
            except ValueError as e:
                self.warn(f"Light '{ob.name}': {e}")
                kw.pop("ies", None)
                kw.pop("frame", None)
                self.scene.set_light_extra(rec[1], **kw)

    # -- viewport edits ---------------------------------------------------------------------------

    def id_names(self):
        """Names for the id AOVs: (objects, materials, assets), indexed by `id - 1`."""
        n = max([i for recs in self.instances.values() for i, *_ in recs] + [r[2][2] for r in self.lights.values() if r[0] == "area"] + [-1]) + 1
        objects, assets = [""] * n, [""] * n
        for recs in self.instances.values():
            for idx, _mesh, _slot, ob in recs:
                objects[idx] = ob.original.name
                top = ob.original
                while top.parent is not None:
                    top = top.parent
                assets[idx] = top.name
        for key, rec in self.lights.items():
            if rec[0] == "area":
                objects[rec[2][2]] = assets[rec[2][2]] = key[0].split(":")[-1]
        mats = [""] * (max(self.materials.index.values(), default=-1) + 1)  # area lights add materials too
        for k, i in self.materials.index.items():
            mats[i] = k or "None"
        return objects, mats, assets

    def catcher_ids(self):
        """IR instance indices of the objects marked Shadow Catcher."""
        return [i for recs in self.instances.values() for i, _m, _s, ob in recs if ob.original.is_shadow_catcher]

    def keys(self, depsgraph):
        return {self.instance_key(i) for i in depsgraph.object_instances if i.object.type in GEOMETRY | {"LIGHT"}}

    def update(self, depsgraph):
        """Applies the depsgraph's updates in place. False: the structure changed, rebuild."""
        if self.keys(depsgraph) != set(self.instances) | set(self.lights):
            return False
        changed_obj = set()
        for u in depsgraph.updates:
            idb = u.id
            tn = type(idb).__name__
            if tn == "Object":
                if u.is_updated_geometry:
                    return False  # mesh edits rebuild (deform-only edits could use set_mesh_corners)
                changed_obj.add(idb.original.name_full)
            elif tn in {"Mesh", "Curve", "Collection"}:
                return False
            elif tn == "Material":
                self.materials.update(idb.original)
            elif tn == "World":
                return False
            elif tn in {"Light", "Camera", "Scene"}:
                pass
        for inst in depsgraph.object_instances:
            ob = inst.object
            key = self.instance_key(inst)
            if ob.type == "LIGHT" and key in self.lights:
                self.light_obs[key] = ob
                rec = self.lights[key]
                if rec[0] == "area":
                    if rec[1] != lights.area_signature(ob.data):
                        return False  # the shape changed: rebuild
                    lights.update_area(self.scene, rec[2], ob)
                else:
                    lights.update(self.scene, rec[1], ob)
            elif ob.type in GEOMETRY and key in self.instances:
                mat = convert.matrix(inst.matrix_world)
                for idx, mesh, slot, _ in self.instances[key]:
                    self.scene.set_instance(idx, mesh, self.slot_material(ob, slot), mat)
        self.apply_light_extras()
        if self.camera is not None:
            cam_ob, w, h = self.camera
            self.set_camera(depsgraph, cam_ob, w, h)
        return True
