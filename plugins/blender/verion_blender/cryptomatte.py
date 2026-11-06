"""Cryptomatte (Object, Material, Asset) from the renderer's first-hit id AOVs.

Ids follow the specification: MurmurHash3_32 of the name, reinterpreted as a float32 with the
exponent kept finite. Verion's id AOVs are first-hit and unfiltered, so every pixel has one id at
coverage 1; one layer (two ranks, `CryptoXX00`) is written per kind.
"""
import hashlib
import json
import struct

import numpy as np

KINDS = [("Object", "use_pass_cryptomatte_object"), ("Material", "use_pass_cryptomatte_material"), ("Asset", "use_pass_cryptomatte_asset")]


def murmur3_32(data, seed=0):
    """MurmurHash3 x86 32-bit of bytes."""
    c1, c2, mask = 0xCC9E2D51, 0x1B873593, 0xFFFFFFFF
    h = seed
    n = len(data) // 4 * 4
    for (k,) in struct.iter_unpack("<I", data[:n]):
        k = (k * c1) & mask
        k = ((k << 15) | (k >> 17)) & mask
        k = (k * c2) & mask
        h ^= k
        h = ((h << 13) | (h >> 19)) & mask
        h = (h * 5 + 0xE6546B64) & mask
    tail, k = data[n:], 0
    for i in range(len(tail) - 1, -1, -1):
        k = (k << 8) | tail[i]
    if tail:
        k = (k * c1) & mask
        k = ((k << 15) | (k >> 17)) & mask
        k = (k * c2) & mask
        h ^= k
    h ^= len(data)
    h ^= h >> 16
    h = (h * 0x85EBCA6B) & mask
    h ^= h >> 13
    h = (h * 0xC2B2AE35) & mask
    h ^= h >> 16
    return h


def hash_float(name):
    """The id of a name as the float32 the pass stores (the spec's uint32_to_float32)."""
    h = murmur3_32(name.encode("utf-8"))
    exp = (h >> 23) & 255
    if exp in (0, 255):
        h ^= 1 << 23
    return struct.unpack("<f", struct.pack("<I", h))[0]


def _bits(name):
    h = murmur3_32(name.encode("utf-8"))
    if ((h >> 23) & 255) in (0, 255):
        h ^= 1 << 23
    return h


def layer_pass(ids, names):
    """RGBA float32 (H, W, 4): (id, coverage, 0, 0) per pixel for `ids` (0 = background, k = names[k-1])."""
    table = np.zeros(len(names) + 1, np.float32)
    table[1:] = [hash_float(n) for n in names]
    out = np.zeros(ids.shape + (4,), np.float32)
    ok = ids > 0
    out[..., 0] = table[np.clip(ids, 0, len(names))]
    out[..., 1] = np.where(ok, 1.0, 0.0)
    return out


def metadata(layer_name, kind, names):
    """The EXR header entries of one Cryptomatte layer."""
    full = f"{layer_name}.Crypto{kind}"
    key = hashlib.md5(full.encode()).hexdigest()[:7]
    manifest = {n: "%08x" % _bits(n) for n in sorted(set(names))}
    p = f"cryptomatte/{key}/"
    return {
        p + "name": full,
        p + "hash": "MurmurHash3_32",
        p + "conversion": "uint32_to_float32",
        p + "manifest": json.dumps(manifest, separators=(",", ":")),
    }
