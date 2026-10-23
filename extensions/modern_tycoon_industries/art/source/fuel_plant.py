"""Rakettdrivstoffverk (rocket fuel plant): 2 x 3 tiles.

Takes crude oil and makes refined kerosene-type rocket fuel and the cryogenic
oxidiser that goes with it.

    (0,0) distillation column and the flare stack (animated flame)
    (0,1) horizontal cryogenic tanks (venting vapour)
    (0,2) large storage tank
    (1,0) control and pump house
    (1,1) pipe rack and compressor
    (1,2) tanker loading gantry

SPDX-License-Identifier: GPL-2.0-only
"""
import math

from render3d import Box, Cylinder, Rotated, Sphere
from tilekit import animated_spec, smoke_column, static_spec

FRAMES = 8


def column():
	def paint(x, y, z, face):
		if z > 52:
			return 'cc'
		return 'granite_dark' if int(z) % 10 == 0 else 'tank_white'
	prims = [Cylinder(8.0, 7.0, 2.6, (0.0, 54.0), paint), Cylinder(8.0, 7.0, 2.6, (54.0, 57.0), 'cc', r_top=1.0)]
	for z in (12.0, 24.0, 36.0, 48.0):
		prims.append(Cylinder(8.0, 7.0, 3.6, (z, z + 0.8), 'steel_dark'))           # platforms
	prims.append(Box((10.0, 10.8), (9.0, 9.8), (0.0, 50.0), 'steel'))               # ladder cage
	prims.append(Box((3.0, 13.0), (12.0, 15.0), (0.0, 3.0), 'concrete_dark'))       # plinth
	# Flare stack with guy-wire posts, at the far corner of the site.
	prims.append(Cylinder(3.0, 13.0, 0.9, (0.0, 62.0), lambda x, y, z, f: 'red' if int(z / 8) % 2 else 'snow'))
	prims.append(Cylinder(3.0, 13.0, 1.3, (62.0, 63.5), 'steel_dark'))
	return prims


def flare(f):
	"""Flickering flame on the stack top."""
	k = [0, 2, 1, 3, 2, 0, 3, 1][f % FRAMES]
	h = 5.0 + k
	lean = 0.12 * (k - 1.5)
	prims = [
		Rotated(Cylinder(0.0, 0.0, 1.4, (0.0, h), 'flame_outer', r_top=0.2), (3.0, 13.0, 63.5), pitch=lean),
		Rotated(Cylinder(0.0, 0.0, 0.9, (0.0, h * 0.7), 'flame', r_top=0.15), (3.0, 13.0, 63.5), pitch=lean),
		Rotated(Cylinder(0.0, 0.0, 0.4, (0.0, h * 0.4), 'flame_core', r_top=0.1), (3.0, 13.0, 63.5), pitch=lean),
	]
	return prims + smoke_column(3.0 + lean * 4, 13.0, 63.5 + h, f, FRAMES, puffs=2, rise=1.6, grow=0.12, shade=('smoke_dark', 'smoke'))


def cryo_tanks():
	prims = []
	for x in (5.0, 11.0):
		tank = Cylinder(0.0, 0.0, 2.6, (-6.5, 6.5), lambda lx, ly, lz, f: 'cc' if abs(lz) < 0.6 else 'tank_white')
		prims.append(Rotated(tank, (x, 24.0, 5.0), yaw=math.pi / 2, pitch=math.pi / 2))
		for cap in (-6.5, 6.5):
			prims.append(Sphere(x, 24.0 + cap, 5.0, 2.6, 'tank_white', sz=1.0))
		for y in (19.5, 28.5):
			prims.append(Box((x - 2.0, x + 2.0), (y - 0.6, y + 0.6), (0.0, 3.4), 'concrete_dark'))   # saddles
		prims.append(Cylinder(x, 24.0, 0.4, (7.0, 10.0), 'steel_dark'))                            # vent
	prims.append(Box((7.4, 8.6), (16.5, 31.5), (1.0, 2.0), 'pipe'))
	return prims


def vents(f):
	"""Cold vapour drifting from the tank vents."""
	prims = []
	for x, phase in ((5.0, 0), (11.0, 4)):
		p = (f + phase) % FRAMES
		if p < 6:
			r = 0.8 + 0.3 * p
			prims.append(Sphere(x + 0.3 * p, 24.0 - 0.2 * p, 10.5 + 1.2 * p, r, 'vapour'))
	return prims


def storage_tank():
	def paint(x, y, z, face):
		if 14.0 <= z <= 16.0:
			return 'cc'
		return 'tank_white' if face != 'top' else 'granite'
	prims = [
		Cylinder(8.0, 40.0, 6.0, (0.0, 20.0), paint),
		Cylinder(8.0, 40.0, 6.0, (20.0, 23.0), 'granite', r_top=1.5),
		Box((1.0, 15.0), (33.0, 34.0), (0.0, 1.5), 'concrete_dark'),                     # bund wall
		Box((1.0, 2.0), (33.0, 47.0), (0.0, 1.5), 'concrete_dark'),
	]
	# Spiral stair approximated by steps up the screen-right side.
	for i in range(10):
		a = -0.2 + i * 0.16
		x, y = 8.0 + math.cos(a) * 6.4, 40.0 + math.sin(a) * 6.4
		prims.append(Box((x - 0.6, x + 0.6), (y - 0.6, y + 0.6), (i * 2.0, i * 2.0 + 0.5), 'steel_dark'))
	return prims


def control_house():
	def paint(x, y, z, face):
		if face == 'top':
			return 'granite_dark'
		if z > 10.5:
			return 'cc'
		if 5.0 < z < 8.0 and face in ('x', 'y'):
			v = y if face == 'x' else x
			return 'glass' if int(v) % 3 else 'snow'
		return 'snow'
	return [
		Box((19.0, 30.0), (2.0, 12.0), (0.0, 12.0), paint),
		Box((22.0, 26.0), (4.0, 8.0), (12.0, 15.0), 'granite_dark'),
		Cylinder(27.5, 9.0, 1.0, (12.0, 16.0), 'steel'),
		Box((19.0, 30.0), (12.5, 15.0), (0.0, 4.0), 'steel_dark'),                       # pumps
		Box((20.0, 22.0), (13.0, 14.6), (4.0, 5.5), 'red'),
		Box((25.0, 27.0), (13.0, 14.6), (4.0, 5.5), 'red'),
	]


def pipe_rack():
	prims = []
	for x in (18.0, 24.0, 30.0):
		for y in (18.0, 30.0):
			prims.append(Box((x - 0.4, x + 0.4), (y - 0.4, y + 0.4), (0.0, 9.0), 'steel_dark'))
		prims.append(Box((x - 0.4, x + 0.4), (18.0, 30.0), (8.0, 9.0), 'steel_dark'))
	for i, (mat, z) in enumerate((('pipe', 9.6), ('tank_white', 9.6), ('cc', 9.6), ('pipe', 6.0))):
		y = 20.0 + i * 2.6
		prims.append(Rotated(Cylinder(0.0, 0.0, 0.6, (0.0, 16.0), mat), (16.0, y, z), pitch=math.pi / 2))
	prims.append(Box((20.0, 28.0), (21.0, 27.0), (0.0, 4.5), 'granite'))             # compressor
	prims.append(Cylinder(24.0, 24.0, 2.2, (4.5, 6.5), 'steel_dark'))
	return prims


def loading_gantry():
	prims = [
		Box((17.0, 31.0), (39.0, 41.0), (0.0, 0.3), 'signal'),                            # lane
		Box((17.0, 31.0), (35.0, 36.0), (0.0, 0.3), 'signal'),
		Box((18.0, 30.0), (42.0, 46.0), (8.0, 9.0), 'steel_dark'),                        # platform
		Box((18.0, 30.0), (42.0, 46.0), (9.0, 12.0), lambda x, y, z, f: 'cc' if f == 'y' else 'granite'),
		Box((26.0, 30.0), (42.0, 46.0), (0.0, 8.0), 'snow'),                              # booth
	]
	for x in (18.5, 29.5):
		prims.append(Box((x - 0.4, x + 0.4), (44.0, 44.8), (0.0, 8.0), 'steel'))
	for x in (20.0, 24.0):
		arm = Box((-0.25, 0.25), (-0.25, 0.25), (0.0, 5.0), 'pipe')
		prims.append(Rotated(arm, (x, 42.0, 8.0), yaw=-math.pi / 2, pitch=2.2))
	return prims


def tile_specs(M):
	everything = column() + cryo_tanks() + storage_tank() + control_house() + pipe_rack() + loading_gantry()
	return [
		animated_spec((0, 0), 'column', everything, FRAMES, 2, M, height=64, effect=flare),
		animated_spec((0, 1), 'cryo', everything, FRAMES, 2, M, height=16, effect=vents),
		static_spec((0, 2), 'storage', everything, M, height=24),
		static_spec((1, 0), 'control', everything, M, height=16),
		static_spec((1, 1), 'piperack', everything, M, height=12),
		static_spec((1, 2), 'loading', everything, M, height=12),
	]
