"""Asteroideraffineri (asteroid refinery): 2 x 3 tiles.

Crushes asteroid ore, melts it in an electric arc furnace and turns the
metals into goods.

    (0,0) smelter hall with two chimneys (animated smoke)
    (0,1) arc furnace with glowing electrodes (animated glow)
    (0,2) crusher tower fed by a conveyor
    (1,0) goods warehouse
    (1,1) container yard
    (1,2) ore receiving hopper and ore heap

SPDX-License-Identifier: GPL-2.0-only
"""
import math

from render3d import Box, Cylinder, Rotated, Sphere
from tilekit import animated_spec, smoke_column, static_spec

SMOKE_FRAMES = 16
GLOW_FRAMES = 16


def _ore_paint(x, y, z, face):
	if int(x * 3 + y * 5 + z * 7) % 11 == 0:
		return 'ore_metal'
	return 'ore_dark' if int(x * 2 + y) % 5 == 0 else 'ore'


def smelter():
	def hall(x, y, z, face):
		if face == 'top':
			return 'granite_dark' if int(y) % 4 == 0 else 'granite'
		if 24.0 <= z <= 26.0:
			return 'cc'
		if face == 'y' and 4.0 < x < 13.0 and z < 12.0:
			return 'steel_dark' if int(x) % 2 else 'granite_dark'      # roller door
		if face == 'x' and 18.0 < z < 22.0:
			return 'glass' if int(y * 1.5) % 3 else 'rust'
		return 'rust' if z < 6 else 'granite'
	prims = [Box((2.0, 14.0), (2.0, 14.0), (0.0, 28.0), hall)]
	for cy in (4.5, 9.5):
		prims.append(Cylinder(4.0, cy, 1.5, (28.0, 56.0), lambda x, y, z, f: 'red' if 46 < z < 50 or 52 < z < 56 else 'snow'))
		prims.append(Cylinder(4.0, cy, 1.8, (55.0, 56.5), 'steel_dark'))
	return prims


def chimney_smoke(f):
	return (smoke_column(4.0, 4.5, 56.5, f, SMOKE_FRAMES, puffs=4, rise=2.2, grow=0.14)
		+ smoke_column(4.0, 9.5, 56.5, (f + 6) % SMOKE_FRAMES, SMOKE_FRAMES, puffs=4, rise=2.2, grow=0.14,
			shade=('smoke_light', 'smoke', 'smoke_dark')))


def furnace():
	prims = [
		Box((2.0, 14.0), (18.0, 30.0), (0.0, 3.0), 'concrete_dark'),
		Cylinder(8.0, 24.0, 4.8, (3.0, 11.0), lambda x, y, z, f: 'cc' if 9.0 < z < 10.2 else 'steel_dark'),
		Sphere(8.0, 24.0, 11.0, 4.8, 'granite', sz=0.4),
		Box((2.5, 4.5), (19.0, 21.0), (3.0, 7.0), 'rust'),                                # tapping spout
	]
	for k in range(3):
		a = k * 2 * math.pi / 3 + 0.3
		x, y = 8.0 + math.cos(a) * 1.6, 24.0 + math.sin(a) * 1.6
		prims.append(Cylinder(x, y, 0.55, (11.0, 22.0), 'granite_dark'))                # electrodes
		prims.append(Box((x - 0.4, x + 0.4), (y - 0.4, y + 0.4), (20.0, 21.0), 'steel'))
	prims.append(Box((11.5, 13.0), (26.0, 28.5), (3.0, 24.0), 'steel'))                 # electrode mast
	prims.append(Box((7.0, 13.0), (26.4, 28.0), (21.5, 23.0), 'steel'))
	return prims


def furnace_glow(f):
	"""Arc light under the lid and a ladle of molten metal; brightness pulses."""
	level = [0, 1, 2, 1, 2, 2, 1, 0, 1, 2, 1, 0, 0, 1, 2, 1][f % GLOW_FRAMES]
	hot = ('ember', 'molten', 'molten_hot')[level]
	prims = [
		Cylinder(8.0, 24.0, 4.9, (7.0, 8.4), hot),                                       # glowing seam
		Box((1.5, 3.0), (19.5, 20.5), (2.2, 3.4), 'molten'),
		Cylinder(1.0, 20.0, 1.6, (0.0, 2.6), lambda x, y, z, face: 'molten_hot' if face == 'top' else 'steel_dark'),
	]
	if level:
		for k in range(level + 1):                                                       # sparks
			a = f * 0.9 + k * 2.1
			prims.append(Sphere(8.0 + math.cos(a) * 5.5, 24.0 + math.sin(a) * 5.5, 9.0 + k * 1.5, 0.45, 'molten_hot'))
	return prims


def crusher():
	def tower(x, y, z, face):
		if face == 'top':
			return 'granite_dark'
		if z > 22.0:
			return 'cc'
		return 'granite' if int(z / 4) % 2 else 'rust'
	prims = [
		Box((3.0, 12.0), (36.0, 45.0), (0.0, 25.0), tower),
		Box((5.0, 10.0), (38.0, 43.0), (25.0, 28.0), 'granite_dark'),
		Box((12.0, 14.0), (38.0, 42.0), (0.0, 6.0), 'steel_dark'),                       # discharge chute
	]
	belt = Box((0.0, 21.0), (-1.0, 1.0), (-0.5, 0.5), lambda x, y, z, f: 'ore' if f == 'top' and abs(y) < 0.7 else 'steel_dark')
	prims.append(Rotated(belt, (27.0, 40.5, 3.0), yaw=math.pi, pitch=-0.95))
	for x, h in ((22.0, 8.5), (17.0, 15.5)):
		prims.append(Box((x - 0.5, x + 0.5), (40.0, 41.0), (0.0, h), 'steel'))
	return prims


def warehouse():
	def shed(x, y, z, face):
		if face == 'top':
			return 'granite' if int(x) % 3 else 'granite_dark'
		if z > 12.0:
			return 'cc'
		if face == 'x' and 3.0 < y < 13.0 and z < 9.0:
			return 'steel_dark' if int(y) % 2 else 'granite_dark'
		return 'snow'
	return [
		Box((17.0, 31.0), (2.0, 14.0), (0.0, 14.0), shed),
		Box((22.0, 26.0), (2.0, 14.0), (14.0, 16.5), 'granite_dark'),                      # roof light
	]


def containers():
	prims = []
	cols = ('cc', 'granite', 'red', 'cc_dark', 'snow', 'cc')
	i = 0
	for y0 in (18.5, 25.5):
		for layer in range(2 if y0 < 20 else 3):
			mat = cols[i % len(cols)]
			i += 1
			prims.append(Box((18.0, 30.0), (y0, y0 + 5.0), (layer * 5.0, layer * 5.0 + 4.8),
				lambda x, y, z, f, m=mat: 'frame' if f in ('x', 'y') and int(x * 2) % 5 == 0 else m))
	return prims


def receiving():
	return [
		Box((17.0, 31.0), (34.0, 35.0), (0.0, 4.0), 'concrete'),                          # bunker walls
		Box((30.0, 31.0), (34.0, 47.0), (0.0, 4.0), 'concrete'),
		Sphere(23.0, 41.0, 1.0, 5.0, _ore_paint, sz=0.8),
		Sphere(27.0, 44.0, 0.5, 2.8, _ore_paint, sz=0.8),
		Box((26.0, 29.0), (38.0, 43.0), (0.0, 6.0), 'cc'),                                  # receiving hopper
		Box((17.0, 30.0), (46.0, 47.0), (0.0, 0.3), 'signal'),
	]


def tile_specs(M):
	everything = smelter() + furnace() + crusher() + warehouse() + containers() + receiving()
	return [
		animated_spec((0, 0), 'smelter', everything, SMOKE_FRAMES, 3, M, height=56, effect=chimney_smoke),
		animated_spec((0, 1), 'furnace', everything, GLOW_FRAMES, 2, M, height=24, variant=furnace_glow),
		static_spec((0, 2), 'crusher', everything, M, height=28),
		static_spec((1, 0), 'warehouse', everything, M, height=16),
		static_spec((1, 1), 'containers', everything, M, height=16),
		static_spec((1, 2), 'receiving', everything, M, height=8),
	]
