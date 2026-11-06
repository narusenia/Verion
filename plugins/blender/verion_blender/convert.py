"""Blender <-> Verion coordinate and data conversions."""
import math

import numpy as np

# Blender is Z-up, Verion (like glTF) is Y-up with the camera looking down -Z.
# (x, y, z) in Blender is (x, z, -y) in Verion.
BASIS = np.array(
    [[1, 0, 0, 0], [0, 0, 1, 0], [0, -1, 0, 0], [0, 0, 0, 1]], dtype=np.float64
)


def matrix(m):
    """A Blender 4x4 world matrix as a Verion 3x4 float32 matrix."""
    return (BASIS @ np.array(m, dtype=np.float64))[:3].astype(np.float32)


def point(v):
    p = BASIS @ np.array([v[0], v[1], v[2], 1.0])
    return tuple(float(x) for x in p[:3])


def direction(v):
    p = BASIS @ np.array([v[0], v[1], v[2], 0.0])
    return tuple(float(x) for x in p[:3])


def rgb(c):
    return tuple(float(x) for x in c[:3])


def srgb_to_linear(c):
    c = np.asarray(c, dtype=np.float32)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def degrees(r):
    return r * 180.0 / math.pi
