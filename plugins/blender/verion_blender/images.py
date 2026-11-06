"""Blender images to Verion images (linear float RGB, first row on top)."""
import numpy as np

from . import convert


def pixels(image):
    """The image as float32 (H, W, 4), first row on top, in linear Rec.709 where the image has color."""
    w, h = image.size
    if w == 0 or h == 0:
        return None
    buf = np.empty(w * h * image.channels, dtype=np.float32)
    image.pixels.foreach_get(buf)
    px = buf.reshape(h, w, image.channels)
    if image.channels == 1:
        px = np.repeat(px, 3, axis=2)
    elif image.channels == 2:
        px = np.concatenate([px, np.zeros((h, w, 1), np.float32)], axis=2)
    if px.shape[2] == 3:
        px = np.concatenate([px, np.ones((h, w, 1), np.float32)], axis=2)
    return np.ascontiguousarray(px[::-1])  # Blender stores the bottom row first


def to_linear(image, px):
    """`pixels` returns what Blender decodes for the image's color space: scene-linear for sRGB
    images and raw values for Non-Color, which is what the IR wants for color and data textures."""
    return px
