"""Conversions from Blender light units to the glTF-style intensities Verion's Scene IR takes.

Blender's watts are Cycles' convention. Measured against Cycles on a diffuse plane
(tests/test_light_units.py; the derivation is in docs/implementation/M6-blender/light-units.md):

* Point and Spot: radiant intensity I = P / (4 pi) per Blender watt, for any cone (a spot is a
  point light with a mask, not a concentrated beam).
* Sun: irradiance E = strength (a Blender "W/m2" is the irradiance on a perpendicular surface).
* Area: the surface emits radiance L = P / (pi * area), so that its flux over the hemisphere is P.
"""
import math

# IR intensity = factor * Blender value (before the light's color).
POINT_PER_WATT = 1.0 / (4.0 * math.pi)
SPOT_PER_WATT = POINT_PER_WATT
SUN_PER_STRENGTH = 1.0
AREA_RADIANCE_PER_WATT = 1.0 / math.pi   # divide by the area

# An IES profile scales the light's strength by its candela value times this (measured: a uniform
# 50 cd profile makes a Cycles point light 3.53 times brighter than the same light without a profile).
IES_PER_CANDELA = 0.0707
