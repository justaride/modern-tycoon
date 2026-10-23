"""Cargo icons (about 10 x 10 px) for the cargo lists in the game's windows.

SPDX-License-Identifier: GPL-2.0-only
"""
from render3d import Box, Cylinder, Sphere, render


def _fuel():
	# A cryogenic fuel canister: white, frosted blue top, yellow hazard band.
	return [
		Cylinder(0.0, 0.0, 1.6, (0.0, 6.0), lambda x, y, z, f: 'signal' if 2.5 < z < 3.5 else 'tank_white'),
		Cylinder(0.0, 0.0, 1.6, (6.0, 7.0), 'flame_blue', r_top=0.8),
	]


def _ore():
	def grain(x, y, z, f):
		return 'ore_metal' if int(x * 5 + y * 3 + z * 7) % 7 == 0 else ('ore_dark' if int(x * 3 - y * 2) % 4 == 0 else 'ore')
	return [Sphere(0.0, 0.0, 2.0, 2.6, grain, sz=0.8), Sphere(0.6, -1.6, 1.4, 1.4, grain)]


def render_icon(kind, materials):
	model = {'fuel': _fuel, 'ore': _ore}[kind]()
	return render(model, materials)
