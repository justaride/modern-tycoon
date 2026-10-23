"""Bre-9 reusable rocket with its asteroid pod, plus flames and smoke.

Fictional design: a white booster that lands on its own legs, topped by a
pod that leaves empty and comes back from the asteroid belt full of ore.
The outbound rocket is clean white with a company-colour band; the returning
one is sooty from re-entry and its pod is ore-stained. When it has landed
the pod's side hatch opens and the ore is visible.

All parts are modelled around (cx, cy) with z = 0 at the pad surface.

SPDX-License-Identifier: GPL-2.0-only
"""
import math

from render3d import Box, Cylinder, Rotated, Sphere

R = 1.8           # booster radius in world units (about 10 px wide on screen)
BOOSTER = (3.0, 50.0)
INTERSTAGE = (50.0, 53.0)
UPPER = (53.0, 60.0)
POD = (60.0, 66.0)
NOSE = (66.0, 73.0)
HEIGHT = NOSE[1]


def _booster_paint(sooty):
	def paint(x, y, z, face):
		if 44.0 <= z <= 46.5:
			return 'cc'                       # company-colour band
		if 30.0 <= z <= 31.0:
			return 'black'                    # roll marking
		if sooty:
			# Re-entry soot: heavy at the bottom, streaky higher up.
			streak = (math.sin(x * 3.1 + y * 2.3) + math.sin(z * 0.37)) * 6
			if z < 18 + streak or (z < 34 + streak and (int(x * 4 + y * 4) % 3 == 0)):
				return 'soot'
		return 'snow'
	return paint


def _pod_paint(state):
	def paint(x, y, z, face):
		if state == 'open' and face == 'side' and 61.0 <= z <= 65.0:
			return 'ore'                      # hatch open: ore visible
		if z < 60.8 or z > 65.2:
			return 'frame'
		if state == 'out':
			return 'tank_white'
		return 'pod'
	return paint


def model(cx, cy, state='out', legs=True, z=0.0):
	"""The rocket standing at (cx, cy) with its engine bell at height z.

	state: 'out' (clean, empty pod), 'back' (sooty, full pod), 'open' (landed, hatch open).
	"""
	sooty = state != 'out'
	body = _booster_paint(sooty)
	prims = [
		Cylinder(cx, cy, 1.1, (z + 0.0, z + 3.0), 'black', r_top=1.5),           # engine bell
		Cylinder(cx, cy, R, (z + BOOSTER[0], z + BOOSTER[1]), body),
		Cylinder(cx, cy, R, (z + INTERSTAGE[0], z + INTERSTAGE[1]), 'black'),
		Cylinder(cx, cy, R, (z + UPPER[0], z + UPPER[1]), 'snow'),
		Cylinder(cx, cy, R + 0.15, (z + POD[0], z + POD[1]), _pod_paint(state)),
		Cylinder(cx, cy, R + 0.15, (z + NOSE[0], z + NOSE[1]), 'snow' if not sooty else 'granite', r_top=0.25),
	]
	# Grid fins just below the interstage, one per side.
	for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
		fx, fy = cx + dx * (R + 0.5), cy + dy * (R + 0.5)
		prims.append(Box((fx - 0.5, fx + 0.5), (fy - 0.5, fy + 0.5), (z + 47.0, z + 49.0), 'steel_dark'))
	# Landing legs: splayed when deployed, folded flat against the booster in flight.
	for k in range(4):
		a = math.pi / 4 + k * math.pi / 2
		if legs:
			leg = Box((-0.3, 0.3), (-0.3, 0.3), (0.0, 14.0), 'granite_dark')
			px, py = cx + math.cos(a) * (R + 3.6), cy + math.sin(a) * (R + 3.6)
			prims.append(Rotated(leg, (px, py, z + 0.0), yaw=a, pitch=-0.27))
			prims.append(Box((px - 0.6, px + 0.6), (py - 0.6, py + 0.6), (z + 0.0, z + 0.6), 'black'))
		else:
			px, py = cx + math.cos(a) * (R + 0.2), cy + math.sin(a) * (R + 0.2)
			prims.append(Box((px - 0.3, px + 0.3), (py - 0.3, py + 0.3), (z + 4.0, z + 18.0), 'granite_dark'))
	return prims


def flame(cx, cy, length, width=1.0, z=0.0, flicker=0, kind='launch'):
	"""Engine plume hanging below height z. kind 'retro' is the shorter, bluer landing burn."""
	w = width * (1.0 + 0.08 * ((flicker % 3) - 1))
	ln = length * (1.0 + 0.06 * ((flicker % 2) * 2 - 1))
	if kind == 'retro':
		return [
			Cylinder(cx, cy, 0.5 * w, (z - ln, z), 'flame_blue', r_top=1.0 * w),
			Cylinder(cx, cy, 0.25 * w, (z - ln * 0.75, z), 'flame_core', r_top=0.7 * w),
		]
	return [
		Cylinder(cx, cy, 0.4 * w, (z - ln, z - ln * 0.3), 'flame_outer', r_top=1.6 * w),
		Cylinder(cx, cy, 1.6 * w, (z - ln * 0.3, z), 'flame', r_top=1.2 * w),
		Cylinder(cx, cy, 0.3 * w, (z - ln * 0.8, z), 'flame_core', r_top=0.9 * w),
	]


def _puff_material(i):
	return ('smoke', 'smoke_light', 'smoke_dark', 'smoke_light')[i % 4]


def ground_cloud(cx, cy, size, seed=0):
	"""Billowing exhaust cloud on the pad. size 0..1."""
	if size <= 0:
		return []
	prims = []
	n = 7
	for i in range(n):
		a = seed * 0.7 + i * 2 * math.pi / n
		d = 2.5 + 3.0 * size
		r = 1.5 + 3.2 * size * (0.8 + 0.3 * math.sin(i * 1.7 + seed))
		prims.append(Sphere(cx + math.cos(a) * d, cy + math.sin(a) * d, r * 0.5, r, _puff_material(i + seed), sz=0.75))
	prims.append(Sphere(cx, cy, 2 + 3 * size, 2 + 3.5 * size, 'smoke_light', sz=0.8))
	return prims


def trail(cx, cy, z_top, z_bottom, age, seed=0):
	"""Exhaust trail of puffs from z_bottom up to z_top; older trails are wider."""
	prims = []
	z = z_bottom
	i = 0
	while z < z_top:
		r = 1.4 + 1.6 * age + 0.4 * math.sin(i * 2.1 + seed)
		wob = 1.2 * math.sin(i * 1.3 + seed) * (0.5 + age)
		prims.append(Sphere(cx + wob, cy - wob, z, r, _puff_material(i + seed)))
		z += max(3.0, r * 1.3)
		i += 1
	return prims


def vapour(cx, cy, z, phase):
	"""Small venting puffs from the upper stage while fuelling."""
	prims = []
	for k in range(2):
		p = (phase + k * 4) % 8
		r = 0.8 + 0.35 * p
		prims.append(Sphere(cx + 2.2 + 0.4 * p, cy - 1.0 - 0.3 * p, z + 0.5 * p, r, 'vapour'))
	return prims


def dust(cx, cy, size):
	"""Low dust ring kicked up at touchdown."""
	if size <= 0:
		return []
	prims = []
	for i in range(8):
		a = i * math.pi / 4
		d = 3.0 + 2.5 * size
		prims.append(Sphere(cx + math.cos(a) * d, cy + math.sin(a) * d, 1.0, 1.0 + 1.8 * size, 'smoke_dark' if i % 2 else 'smoke', sz=0.6))
	return prims
