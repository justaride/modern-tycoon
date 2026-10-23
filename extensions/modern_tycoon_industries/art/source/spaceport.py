"""Romhavn (spaceport): 3 x 3 tiles, modelled once in industry coordinates.

Layout (tile x, tile y), back of the screen first:

    (0,0) cryogenic fuel sphere
    (1,0) (2,0) rocket assembly hall
    (0,1) mission control with a turning tracking dish
    (1,1) launch and landing pad with the service tower (the rocket lives here)
    (0,2) ore silos
    (2,1) deluge water tower
    (1,2) ore conveyor from the bunker up to the silos
    (2,2) ore bunker and truck loading bay

Tall things stand at the back so the rocket is never hidden.

SPDX-License-Identifier: GPL-2.0-only
"""
import math

from render3d import Box, Cylinder, Rotated, Sphere

PAD_CENTRE = (24.0, 24.0)


def _hall_paint(x, y, z, face):
	if face == 'top':
		return 'granite' if (int(x) % 4) else 'granite_dark'
	if 38.0 <= z <= 41.0:
		return 'cc'
	if face == 'y' and 20.0 <= x <= 42.0 and z <= 34.0:
		# Tall door on the pad side, with yellow-black edge marking.
		if x < 21.0 or x > 41.0:
			return 'signal' if int(z / 2) % 2 else 'black'
		return 'granite_dark' if int(x) % 3 else 'steel_dark'
	if face == 'x' and 3.0 < y < 12.0 and 24.0 < z < 30.0:
		return 'glass' if int(y * 2) % 3 else 'granite_dark'
	return 'snow' if z > 24.0 else 'granite'


def _control_paint(x, y, z, face):
	if face == 'top':
		return 'granite_dark'
	if 7.0 <= z <= 10.5 and face in ('x', 'y'):
		v = y if face == 'x' else x
		return 'screen' if int(v * 1.5) % 4 == 0 else 'glass'
	if z > 12.0:
		return 'cc'
	return 'snow'


def mission_control(dish_angle):
	prims = [
		Box((2.0, 14.0), (18.0, 30.0), (0.0, 13.0), _control_paint),
		Box((5.0, 9.0), (21.0, 25.0), (13.0, 20.0), 'granite'),                    # dish pedestal
		Cylinder(7.0, 23.0, 1.0, (20.0, 23.0), 'steel_dark'),
		Box((11.0, 12.0), (19.0, 20.0), (13.0, 26.0), 'steel'),                    # antenna mast
		Sphere(11.5, 19.5, 26.5, 0.8, 'lamp_red'),
	]
	# Tracking dish: a shallow bowl on a tilted mount that turns with the animation.
	bowl = Sphere(0.0, 0.0, 0.0, 5.0, 'snow', sz=0.35)
	feed = Cylinder(0.0, 0.0, 0.25, (0.0, 4.5), 'steel_dark')
	for p in (bowl, feed):
		prims.append(Rotated(p, (7.0, 23.0, 26.0), yaw=dish_angle, pitch=0.85))
	return prims


def assembly_hall():
	return [
		Box((18.0, 46.0), (2.0, 14.0), (0.0, 42.0), _hall_paint),
		Box((22.0, 26.0), (5.0, 9.0), (42.0, 45.0), 'granite_dark'),             # roof units
		Box((34.0, 38.0), (5.0, 9.0), (42.0, 45.0), 'granite_dark'),
		Box((29.0, 31.0), (11.0, 12.0), (42.0, 50.0), 'steel'),                  # lightning mast
	]


def fuel_sphere():
	prims = [Sphere(8.0, 8.0, 12.0, 6.5, 'tank_white')]
	for dx, dy in ((-4, -4), (4, -4), (-4, 4), (4, 4)):
		x, y = 8.0 + dx, 8.0 + dy
		prims.append(Box((x - 0.6, x + 0.6), (y - 0.6, y + 0.6), (0.0, 9.0), 'steel_dark'))
	prims.append(Box((13.0, 18.0), (12.6, 13.8), (2.0, 3.2), 'pipe'))            # line to the pad
	prims.append(Box((3.0, 4.0), (1.0, 2.0), (16.0, 19.0), 'cc'))
	return prims


def ore_silos():
	prims = []
	for cy in (37.0, 43.5):
		prims += [
			Cylinder(6.0, cy, 3.4, (6.0, 32.0), 'granite'),
			Cylinder(6.0, cy, 3.4, (32.0, 35.0), 'cc', r_top=1.0),
			Cylinder(6.0, cy, 1.2, (2.0, 6.0), 'steel_dark', r_top=3.0),
		]
		for dx, dy in ((-2.5, -2.5), (2.5, -2.5), (-2.5, 2.5), (2.5, 2.5)):
			prims.append(Box((6 + dx - 0.4, 6 + dx + 0.4), (cy + dy - 0.4, cy + dy + 0.4), (0.0, 7.0), 'steel_dark'))
	prims.append(Box((2.0, 10.0), (35.5, 45.0), (32.5, 34.0), 'steel_dark'))    # walkway between tops
	return prims


def water_tower():
	prims = [
		Cylinder(40.0, 24.0, 4.5, (20.0, 28.0), 'granite'),
		Cylinder(40.0, 24.0, 4.5, (28.0, 31.0), 'cc', r_top=2.0),
		Box((39.0, 41.0), (23.0, 25.0), (0.0, 20.0), 'steel'),
	]
	for dx, dy in ((-3, -3), (3, -3), (-3, 3), (3, 3)):
		leg = Box((-0.35, 0.35), (-0.35, 0.35), (0.0, 21.0), 'steel_dark')
		prims.append(Rotated(leg, (40.0 + dx * 1.3, 24.0 + dy * 1.3, 0.0), yaw=math.atan2(dy, dx), pitch=-0.12))
	prims.append(Box((33.0, 35.0), (25.0, 26.0), (0.0, 1.6), 'pipe'))
	return prims


def conveyor():
	"""Inclined belt carrying ore from the bunker hopper up to the silo tops."""
	length, angle = 33.0, 0.80
	belt = Box((0.0, length), (-1.1, 1.1), (-0.6, 0.6), lambda x, y, z, f: 'ore' if f == 'top' and abs(y) < 0.8 else 'steel_dark')
	prims = [Rotated(belt, (34.0, 40.0, 6.0), yaw=math.pi, pitch=-angle)]
	for x in (28.0, 22.0, 16.0):
		h = 6.0 + (34.0 - x) * math.tan(angle)
		prims.append(Box((x - 0.5, x + 0.5), (39.5, 40.5), (0.0, h - 0.8), 'steel'))
	prims.append(Box((18.0, 30.0), (36.0, 38.0), (0.0, 0.5), 'signal'))
	return prims


def bunker():
	def heap_paint(x, y, z, face):
		return 'ore_metal' if (int(x * 3 + y * 5 + z * 7) % 11) == 0 else ('ore_dark' if (int(x * 2 + y) % 5) == 0 else 'ore')
	prims = [
		Box((33.0, 47.0), (33.0, 35.0), (0.0, 6.0), 'concrete'),                 # bunker walls
		Box((33.0, 35.0), (35.0, 47.0), (0.0, 6.0), 'concrete'),
		Sphere(41.0, 41.0, 2.0, 5.5, heap_paint, sz=0.8),
		Sphere(37.5, 44.0, 1.0, 3.5, heap_paint, sz=0.75),
		Box((44.0, 47.0), (36.0, 47.0), (0.0, 0.4), 'signal'),                    # loading lane marking
		Box((36.0, 40.0), (33.5, 34.5), (6.0, 12.0), 'cc'),                       # loading hopper
		Cylinder(38.0, 36.0, 1.6, (6.0, 10.0), 'steel_dark', r_top=0.6),
	]
	return prims


def tower(arm):
	"""Service tower on the pad, behind and to the right of the rocket. arm: 'on' or 'off'."""
	x0, x1, y0, y1 = 16.8, 20.2, 21.0, 25.0
	prims = []
	for x in (x0, x1 - 0.6):
		for y in (y0, y1 - 0.6):
			prims.append(Box((x, x + 0.6), (y, y + 0.6), (0.0, 80.0), 'cc_dark'))
	for z in range(4, 80, 6):
		prims.append(Box((x0, x1), (y0, y0 + 0.4), (z, z + 0.6), 'cc'))
		prims.append(Box((x0, x0 + 0.4), (y0, y1), (z, z + 0.6), 'cc'))
	prims.append(Box((x0 - 0.3, x1 + 0.3), (y0 - 0.3, y1 + 0.3), (80.0, 82.0), 'granite_dark'))
	prims.append(Box((18.0, 19.0), (22.6, 23.4), (82.0, 90.0), 'steel'))        # lightning rod
	prims.append(Sphere(18.5, 23.0, 90.5, 0.7, 'lamp_red'))
	if arm == 'on':
		# Crew/fuel arm reaching to the upper stage.
		prims.append(Box((x1, 22.6), (22.4, 23.6), (54.0, 55.6), 'granite'))
		prims.append(Box((x1, 22.2), (22.6, 23.4), (44.0, 45.2), 'pipe'))
	else:
		prims.append(Box((x1, x1 + 1.0), (22.0, 24.0), (54.0, 55.6), 'granite'))
		prims.append(Box((x1, x1 + 1.0), (22.2, 23.8), (44.0, 45.2), 'pipe'))
	return prims


def pad_paint(x, y, z, face):
	"""Launch pad surface, as a ground tile (tile-local x, y in 0..16)."""
	dx, dy = x - 8.0, y - 8.0
	r = math.hypot(dx, dy)
	if abs(r - 6.2) < 0.45:
		return 'signal'
	if r < 3.2:
		return 'black'                                                             # flame trench grate
	if r < 6.0:
		return 'scorch' if (int(x * 2) + int(y * 2)) % 3 else 'soot'
	if x < 0.6 or y < 0.6 or x > 15.4 or y > 15.4:
		return 'concrete_dark'
	return 'concrete'


def pad_ground():
	return [Box((0.0, 16.0), (0.0, 16.0), (-0.01, 0.0), pad_paint)]


def static_model(dish_angle=0.0):
	"""Everything except the rocket, its effects and the pad tile."""
	return (mission_control(dish_angle) + assembly_hall() + fuel_sphere() + ore_silos()
			+ water_tower() + conveyor() + bunker())


TILES = [(0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (2, 1), (0, 2), (1, 2), (2, 2)]


# --------------------------------------------------------------------------
# Animation: one launch-and-return cycle on the pad tile, the dish on (0,1).
# --------------------------------------------------------------------------

PAD_FRAMES = 240     # at animation speed 1 (a frame every 2 ticks) one cycle is about 13 s
DISH_FRAMES = 16

# Phases of the pad cycle (first frame of each).
FUELLING, IGNITION, LIFTOFF, EMPTY, DESCENT, LANDED, HATCH_OPEN = 0, 36, 46, 126, 150, 200, 206


def ascent_height(t):
	return 0.028 * t * t + 0.3 * t


def pad_state(f):
	"""What the pad shows in frame f, as a hashable description."""
	s = {'rocket': None, 'h': 0, 'legs': True, 'flame': None, 'cloud': 0.0, 'trail': None,
		'vapour': None, 'arm': 'off', 'dust': 0.0}
	if f < IGNITION:
		s.update(rocket='out', arm='on', vapour=f % 8)
	elif f < LIFTOFF:
		k = f - IGNITION
		s.update(rocket='out', flame=('launch', 6 + k, f % 6), cloud=round(0.15 + 0.07 * k, 2))
	elif f < EMPTY:
		t = f - LIFTOFF
		h = int(round(ascent_height(t)))
		cloud = 0.85 if t < 12 else max(0.0, round(0.85 - (t - 12) * 0.022, 2))
		s.update(rocket='out', h=h, legs=h < 12, flame=('launch', 18, f % 6), cloud=cloud)
		if h > 10:
			s['trail'] = (min(h, 150), max(4, h - 80), round(min(1.0, t / 60), 2))
	elif f < DESCENT:
		age = (f - EMPTY) / (DESCENT - EMPTY)
		top = int(150 - 110 * age)
		if top > 20:
			s['trail'] = (top, int(30 + 40 * age), round(1.0 + age, 2))
	elif f < LANDED:
		u = (f - DESCENT) / (LANDED - DESCENT)
		h = int(round(150 * (1 - u) ** 2))
		s.update(rocket='back', h=h, legs=h < 26, flame=('retro', 8 + int(6 * (1 - u)), f % 6))
		if h < 10:
			s['dust'] = round(1.0 - h / 10, 2)
	else:
		k = f - LANDED
		s.update(rocket='back' if f < HATCH_OPEN else 'open')
		if k < 8:
			s['dust'] = round(max(0.0, 1.0 - k / 8), 2)
		if f >= 228:
			s['vapour'] = f % 8
	return tuple(sorted(s.items()))


# --------------------------------------------------------------------------
# Tile specs for tools/build_pack.py
# --------------------------------------------------------------------------
# Each layer is (cache key, producer, bbox origin in tile units, bbox extent).
# The producer returns a render3d.Sprite whose offsets are relative to the
# bbox origin, which is where OpenTTD draws a building sprite.

import rocket  # noqa: E402
from render3d import clip_box, composite, render, shifted, tile_clip  # noqa: E402

# A tile may only draw inside this screen box around its north corner
# (OpenTTD's MAX_TILE_EXTENT_*), or animation leaves stale pixels.
TILE_SCREEN = (-32, 32, -200, 48)

ROCKET_ORIGIN = (6, 6, 0)      # rocket bbox, tile-local
TOWER_ORIGIN = (0, 5, 0)


def _ind(tile, origin):
	return (tile[0] * 16 + origin[0], tile[1] * 16 + origin[1], origin[2])


def _box_for(origin):
	"""Screen clip box relative to a bbox origin (inside the tile)."""
	ox, oy, oz = origin
	sx, sy = 2 * (oy - ox), ox + oy - oz
	x0, x1, y0, y1 = TILE_SCREEN
	return x0 - sx, x1 - sx, y0 - sy, y1 - sy


def _pad_effect(state, M, cache):
	s = dict(state)
	o = _ind((1, 1), ROCKET_ORIGIN)
	cx, cy = PAD_CENTRE

	def get(key, fn):
		if key not in cache:
			cache[key] = fn()
		return cache[key]

	layers = []
	if s['trail']:
		top, bottom, age = s['trail']
		layers.append(get(('trail', s['trail']), lambda: render(rocket.trail(cx, cy, top, bottom, age), M, origin=o)))
	if s['rocket']:
		h = s['h']
		layers.append(shifted(get(('rocket', s['rocket'], s['legs']), lambda: render(rocket.model(cx, cy, s['rocket'], s['legs']), M, origin=o)), 0, -h))
		if s['vapour'] is not None:
			layers.append(shifted(get(('vapour', s['vapour']), lambda: render(rocket.vapour(cx, cy, 54, s['vapour']), M, origin=o)), 0, -h))
		if s['flame']:
			kind, length, flicker = s['flame']
			layers.append(shifted(get(('flame', s['flame']), lambda: render(rocket.flame(cx, cy, length, z=0.5, flicker=flicker, kind=kind), M, origin=o)), 0, -h))
	if s['cloud']:
		layers.append(get(('cloud', s['cloud']), lambda: render(rocket.ground_cloud(cx, cy, s['cloud']), M, origin=o)))
	if s['dust']:
		layers.append(get(('dust', s['dust']), lambda: render(rocket.dust(cx, cy, s['dust']), M, origin=o)))
	return clip_box(composite(layers), *_box_for(ROCKET_ORIGIN))


def tile_specs(M):
	"""All tiles of the spaceport with their per-frame layers."""
	static = static_model(0.0)
	cache = {}
	specs = []
	for t in TILES:
		origin = _ind(t, (0, 0, 0))
		if t == (1, 1):
			def pad_layers(f, t=t):
				state = pad_state(f)
				arm = dict(state)['arm']
				return [
					('ground', ('pad_ground',), lambda: render(_shift_model(pad_ground(), 16, 16), M, origin=(16, 16, 0)), None, None),
					('building', ('tower', arm), lambda: render(tower(arm), M, clip=tile_clip(1, 1), origin=_ind(t, TOWER_ORIGIN)), TOWER_ORIGIN, (4, 4, 92)),
					('building', ('pad', state), lambda: _pad_effect(state, M, cache), ROCKET_ORIGIN, (4, 4, 80)),
				]
			specs.append({'pos': t, 'name': 'pad', 'anim': (PAD_FRAMES, 1), 'layers': pad_layers})
		elif t == (0, 1):
			def dish_layers(f, t=t, origin=origin):
				angle = 2 * math.pi * f / DISH_FRAMES
				return [
					('ground', ('concrete',), None, None, None),
					('building', ('control', f), lambda: render(mission_control(angle), M, clip=tile_clip(*t), origin=origin), (0, 0, 0), (16, 16, 32)),
				]
			specs.append({'pos': t, 'name': 'control', 'anim': (DISH_FRAMES, 3), 'layers': dish_layers})
		else:
			def static_layers(f, t=t, origin=origin):
				return [
					('ground', ('concrete',), None, None, None),
					('building', ('static',), lambda: render(static, M, clip=tile_clip(*t), origin=origin), (0, 0, 0), (16, 16, 48)),
				]
			specs.append({'pos': t, 'name': f'part_{t[0]}{t[1]}', 'anim': None, 'layers': static_layers})
	return specs


def _shift_model(prims, dx, dy):
	"""Pad ground is modelled tile-local; move it to industry coordinates."""
	out = []
	for p in prims:
		lo, hi = p.bounds()
		paint = p.paint
		out.append(Box((lo[0] + dx, hi[0] + dx), (lo[1] + dy, hi[1] + dy), (lo[2], hi[2]),
				(lambda x, y, z, f, paint=paint: paint(x - dx, y - dy, z, f)) if callable(paint) else paint))
	return out
