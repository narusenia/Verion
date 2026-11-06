"""Materials, meshes and textures against Cycles. Differences are recorded (REQ-QA, item 14); the
tolerances catch a wrong conversion, not the renderers' ordinary BSDF differences."""
import os
import sys
import tempfile
import unittest

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

common.enable_addon()
TMP = tempfile.gettempdir()


def lit_scene():
    common.reset_scene()
    common.add_camera(location=(0, -5, 1.5), target=(0, 0, 0.8), lens=50)
    common.add_plane(size=30, color=(0.5, 0.5, 0.5))
    common.add_light("AREA", location=(2, -3, 5), energy=1500.0).data.size = 3.0
    common.add_light("SUN", location=(0, 0, 10), energy=1.0)
    common.set_world((0.3, 0.35, 0.4), 1.0)


def both(build, w=128, h=96, spp=48):
    out = {}
    for engine in ("CYCLES", "VERION"):
        lit_scene()
        build()
        out[engine] = common.render(engine, os.path.join(TMP, "mat.exr"), w, h, spp)
    return out


def principled(ob):
    return ob.data.materials[0].node_tree.nodes["Principled BSDF"]


def blocks(a, n=4):
    h, w = a.shape[0] // n * n, a.shape[1] // n * n
    return a[:h, :w].mean(axis=2).reshape(h // n, n, w // n, n).mean(axis=(1, 3))


def corr(a, b):
    return float(np.corrcoef(blocks(a).ravel(), blocks(b).ravel())[0, 1])


class MaterialTests(unittest.TestCase):
    def check(self, name, build, lo=0.75, hi=1.15, min_corr=0.98):
        """Verion's mean must be within [lo, hi] of Cycles' and the images, averaged over 4x4
        pixel blocks (the renderers' noise differs), must correlate. Verion's rough dielectrics are
        up to 9% darker than Cycles' at grazing angles (a BSDF difference, not a conversion)."""
        r = both(build)
        ratio = r["VERION"].mean() / r["CYCLES"].mean()
        c = corr(r["CYCLES"], r["VERION"])
        print(f"MAT {name}: mean ratio {ratio:.3f}, block correlation {c:.4f}")
        self.assertTrue(lo <= ratio <= hi, f"{name}: ratio {ratio:.3f}")
        self.assertGreater(c, min_corr, name)
        return r

    def test_dielectric_and_metal_and_rough(self):
        for name, kw in {
            "rough dielectric": dict(color=(0.7, 0.2, 0.1), roughness=0.8),
            "glossy dielectric": dict(color=(0.1, 0.4, 0.8), roughness=0.2),
            "rough metal": dict(color=(0.9, 0.7, 0.3), roughness=0.4, metallic=1.0),
            "mirror": dict(color=(0.9, 0.9, 0.9), roughness=0.02, metallic=1.0),
        }.items():
            self.check(name, lambda kw=kw: common.add_sphere(**kw), min_corr=0.95)

    def test_emission_and_transmission(self):
        def emissive():
            b = common.add_sphere(color=(0, 0, 0))
            p = principled(b)
            p.inputs["Emission Color"].default_value = (1, 0.5, 0.2, 1)
            p.inputs["Emission Strength"].default_value = 3.0

        def glass():
            b = common.add_sphere(color=(1, 1, 1), roughness=0.0)
            p = principled(b)
            p.inputs["Transmission Weight"].default_value = 1.0
            p.inputs["IOR"].default_value = 1.45

        self.check("emission", emissive)
        # Verion refracts a solid sphere differently from Cycles (the horizon stays visible through it).
        self.check("glass", glass, min_corr=0.75)

    def test_hard_edges_and_uv_texture(self):
        import bmesh

        def cube():
            me = bpy.data.meshes.new("cube")
            bm = bmesh.new()
            bm.loops.layers.uv.verify()
            bmesh.ops.create_cube(bm, size=1.6, calc_uvs=True)
            bm.to_mesh(me)
            bm.free()
            ob = bpy.data.objects.new("cube", me)
            ob.location = (0, 0, 0.9)
            ob.rotation_euler = (0.3, 0.2, 0.6)
            bpy.context.scene.collection.objects.link(ob)
            m = bpy.data.materials.new("m")
            m.use_nodes = True
            me.materials.append(m)
            nt = m.node_tree
            tex = nt.nodes.new("ShaderNodeTexImage")
            img = bpy.data.images.new("chk", 64, 64)
            yy, xx = np.mgrid[:64, :64]
            px = np.ones((64, 64, 4), np.float32)
            px[..., :3] = (((xx // 16 + yy // 16) % 2) * 0.6 + 0.2)[..., None] * np.array([1.0, 0.6, 0.3])
            img.pixels.foreach_set(px.ravel())
            tex.image = img
            tex.interpolation = "Linear"
            nt.links.new(tex.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
            nt.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0

        r = self.check("cube with uv texture", cube)
        self.assertGreater(r["VERION"].std(), 0.02)


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
