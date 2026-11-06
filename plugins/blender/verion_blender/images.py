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
    px = np.ascontiguousarray(px[::-1])  # Blender stores the bottom row first
    if image.colorspace_settings.name == "sRGB":
        # `pixels` holds the stored (encoded) values; the IR wants linear light. Non-Color data
        # (normal maps, roughness) and linear images are used as they are.
        px[..., :3] = convert.srgb_to_linear(px[..., :3])
    return px
