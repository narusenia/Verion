import math

import numpy as np

from . import convert


def settings(depsgraph, cam_ob, width, height, warn):
    """(camera-to-world 3x4, vertical fov, focus distance, aperture radius) of a camera object."""
    cam = cam_ob.data
    rd = depsgraph.scene.render
    proj = np.array(
        cam_ob.calc_matrix_camera(
            depsgraph, x=width, y=height, scale_x=rd.pixel_aspect_x, scale_y=rd.pixel_aspect_y
        )
    )
    if cam.type != "PERSP":
        warn(f"Camera '{cam_ob.name}' is {cam.type.lower()}: only perspective cameras are supported; rendering it as perspective")
    if abs(rd.pixel_aspect_x - rd.pixel_aspect_y) > 1e-6:
        warn("Non-square pixel aspect is not supported")
    shift = (float(proj[0][2]), float(proj[1][2]))
    # P[1][1] = 1 / tan(vertical fov / 2), with the sensor fit and the pixel aspect already applied.
    fov = 2.0 * math.atan(1.0 / float(proj[1][1])) if proj[1][1] else 0.8
    world = cam_ob.matrix_world.normalized()  # drop the object's scale
    focus, radius = 10.0, 0.0
    dof = cam.dof
    if dof.use_dof:
        if dof.focus_object is not None:
            focus = max((dof.focus_object.matrix_world.translation - world.translation).length, 1e-4)
        else:
            focus = max(dof.focus_distance, 1e-4)
        radius = (cam.lens * 1e-3) / (2.0 * max(dof.aperture_fstop, 1e-3))
        if dof.aperture_blades >= 3:
            warn("Polygonal aperture (blades) is rendered as a round lens")
    return convert.matrix(world), fov, focus, radius, shift
