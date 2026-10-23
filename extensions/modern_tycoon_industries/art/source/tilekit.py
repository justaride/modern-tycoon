"""Helpers that turn an industry model into tile specs for tools/build_pack.py.

A tile spec is {'pos', 'name', 'anim': (frames, speed) or None, 'layers': f(frame)}
where each layer is (kind, cache key, producer, bbox origin, bbox extent):
kind 'ground' (producer None = the base set's concrete) or 'building'.
Producers return a render3d.Sprite with offsets relative to the bbox origin.

SPDX-License-Identifier: GPL-2.0-only
"""
from render3d import clip_box, composite, render, tile_clip

# A tile may only draw inside this screen box around its north corner
# (OpenTTD's MAX_TILE_EXTENT_*); animated pixels outside it are never repainted.
TILE_SCREEN = (-32, 32, -200, 48)


def ind_origin(tile, origin=(0, 0, 0)):
	"""Tile-local bbox origin -> industry coordinates."""
	return (tile[0] * 16 + origin[0], tile[1] * 16 + origin[1], origin[2])


def tile_box(origin):
	"""TILE_SCREEN relative to a tile-local bbox origin."""
	ox, oy, oz = origin
	sx, sy = 2 * (oy - ox), ox + oy - oz
	x0, x1, y0, y1 = TILE_SCREEN
	return x0 - sx, x1 - sx, y0 - sy, y1 - sy


def static_spec(tile, name, model, M, height=48):
	cache = {}

	def produce():
		if 'sprite' not in cache:
			cache['sprite'] = render(model, M, clip=tile_clip(*tile), origin=ind_origin(tile))
		return cache['sprite']

	def layers(f):
		return [
			('ground', ('concrete',), None, None, None),
			('building', ('static',), produce, (0, 0, 0), (16, 16, height)),
		]
	return {'pos': tile, 'name': name, 'anim': None, 'layers': layers}


def animated_spec(tile, name, model, frames, speed, M, height=48, effect=None, variant=None, key=None):
	"""A tile whose building changes per frame.

	variant(f) -> extra primitives rendered with the model (they can be hidden
	behind it, e.g. a furnace glow); effect(f) -> primitives painted on top
	without the tile clip (smoke may drift over the tile edge), kept inside
	TILE_SCREEN. Both use industry coordinates. key(f) -> hashable; frames
	with equal keys share one sprite.
	"""
	cache = {}
	key_of = key or (lambda f: f)
	origin = ind_origin(tile)

	def body(f):
		extra = variant(f) if variant else []
		vk = ('body', key_of(f)) if extra else ('body',)
		if vk not in cache:
			cache[vk] = render(model + extra, M, clip=tile_clip(*tile), origin=origin)
		return cache[vk]

	def layers(f):
		def produce():
			parts = [body(f)]
			if effect:
				parts.append(render(effect(f), M, origin=origin))
			return clip_box(composite(parts), *tile_box((0, 0, 0)))
		return [
			('ground', ('concrete',), None, None, None),
			('building', ('anim', key_of(f)), produce, (0, 0, 0), (16, 16, height)),
		]
	return {'pos': tile, 'name': name, 'anim': (frames, speed), 'layers': layers}


def smoke_column(cx, cy, z0, f, frames, puffs=4, rise=2.4, grow=0.16, drift=(0.22, -0.12), shade=('smoke', 'smoke_light', 'smoke_dark')):
	"""Puffs rising from (cx, cy, z0); frame f of a loop of `frames`."""
	from render3d import Sphere
	prims = []
	for k in range(puffs):
		p = (f + k * frames // puffs) % frames
		r = 0.9 + grow * p
		prims.append(Sphere(cx + drift[0] * p, cy + drift[1] * p, z0 + 1 + rise * p, r, shade[k % len(shade)]))
	return prims
