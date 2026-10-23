"""Procedural 8bpp sprite renderer for Modern Tycoon vehicles.

Every pixel of our vehicle art is produced here from the primitive models in
art/source/: there is no hand-painted or third-party input. A model is a list
of simple solids in vehicle-local coordinates:

    u: along the vehicle, +u is the front (a full-length rail vehicle is
       8 units long, u in [-4, 4])
    v: across the vehicle (+v is the vehicle's right-hand side)
    z: height above the rail in OpenTTD pixels (1 unit = 1 px at normal zoom)

For each of the 8 OpenTTD directions the model is placed on the map grid,
projected with OpenTTD's own isometric formula (RemapCoords: screen_x =
2 * (y - x), screen_y = x + y - z), ray cast per pixel, shaded with an
upper-left light and quantised to the DOS palette. Company-colour materials
map straight onto the CC1 remap range so the game can recolour them.

Sprite offsets are aligned to the base set: each direction's horizontal
centre and bottom edge match the default OpenTTD train sprites (measured
with tools/measure_anchors.py from OpenGFX 8.0 headers; no pixels used).

SPDX-License-Identifier: GPL-2.0-only
"""
import math

from PIL import Image, ImageDraw

import palette as pal

DIRECTIONS = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW']

# World step per unit of vehicle length. Axis directions move 1 unit per
# step; the screen-diagonal directions (N, E, S, W) move one unit in both x
# and y per step, like vehicles on OpenTTD's diagonal track pieces.
FORWARD = {
	'N': (-1, -1), 'NE': (-1, 0), 'E': (-1, 1), 'SE': (0, 1),
	'S': (1, 1), 'SW': (1, 0), 'W': (1, -1), 'NW': (0, -1),
}

# Base-set anchor per direction: (horizontal centre, bottom edge), relative to
# OpenTTD's sprite reference point. Measured from OpenGFX 8.0, sprites
# 0x0BB1-0x0BB8 (an 8/8-length locomotive), see tools/measure_anchors.py.
ANCHOR = {
	'N': (1.0, 12), 'NE': (-3.0, 8), 'E': (-0.5, 4), 'SE': (5.0, 8),
	'S': (1.0, 12), 'SW': (-3.0, 8), 'W': (0.5, 4), 'NW': (5.0, 8),
}

# Where OpenTTD draws a full-length train sprite relative to the vehicle
# position (Train::UpdateDeltaXY, bounds.offset), in world units.
SPRITE_OFFSET = {
	'NE': (1, 0), 'SW': (1, 0), 'SE': (0, 1), 'NW': (0, 1),
	'N': (0, 0), 'E': (0, 0), 'S': (0, 0), 'W': (0, 0),
}


def _normalise(v):
	length = math.sqrt(sum(c * c for c in v))
	return tuple(c / length for c in v)


# Light from the upper left of the screen and above, as in the base set.
LIGHT = _normalise((0.6, -0.4, 1.0))


class Box:
	"""Axis-aligned box in local space; optional taper slopes both ends above z_taper."""

	def __init__(self, u, v, z, paint, taper=None):
		self.u0, self.u1 = u
		self.v0, self.v1 = v
		self.z0, self.z1 = z
		self.paint = paint
		self.taper = taper  # (z_start, slope): ends lean inwards by slope per unit of z

	def _u_bounds(self, z):
		if self.taper is None or z <= self.taper[0]:
			return self.u0, self.u1
		d = self.taper[1] * (z - self.taper[0])
		return self.u0 + d, self.u1 - d

	def contains(self, u, v, z):
		if not (self.z0 <= z <= self.z1 and self.v0 <= v <= self.v1):
			return False
		lo, hi = self._u_bounds(z)
		return lo <= u <= hi

	def surface(self, u, v, z):
		"""Nearest face to a point just inside the box: (local normal, face name)."""
		lo, hi = self._u_bounds(z)
		sloped = self.taper is not None and z > self.taper[0]
		s = self.taper[1] if sloped else 0.0
		k = math.sqrt(1 + s * s)
		candidates = [
			((hi - u) / k, (1, 0, s), 'front_slope' if sloped else 'front'),
			((u - lo) / k, (-1, 0, s), 'back_slope' if sloped else 'back'),
			(self.v1 - v, (0, 1, 0), 'side'),
			(v - self.v0, (0, -1, 0), 'side'),
			(self.z1 - z, (0, 0, 1), 'top'),
			(z - self.z0, (0, 0, -1), 'bottom'),
		]
		_, normal, face = min(candidates, key=lambda c: c[0])
		return normal, face

	def corners(self):
		return [(u, v, z) for u in (self.u0, self.u1) for v in (self.v0, self.v1) for z in (self.z0, self.z1)]

	def bounds(self):
		return (self.u0, self.u1, self.v0, self.v1, self.z0, self.z1)

	@property
	def exact(self):
		return self.taper is None


class Mound:
	"""Half-ellipsoid heap, e.g. bulk cargo in an open wagon."""

	def __init__(self, ru, rv, z0, height, paint):
		self.ru, self.rv, self.z0, self.h = ru, rv, z0, height
		self.paint = paint

	def contains(self, u, v, z):
		if z < self.z0:
			return False
		return (u / self.ru) ** 2 + (v / self.rv) ** 2 + ((z - self.z0) / self.h) ** 2 <= 1.0

	def surface(self, u, v, z):
		n = (2 * u / self.ru ** 2, 2 * v / self.rv ** 2, 2 * (z - self.z0) / self.h ** 2 + 1e-6)
		return n, 'top'

	def corners(self):
		return [(u, v, z) for u in (-self.ru, self.ru) for v in (-self.rv, self.rv) for z in (self.z0, self.z0 + self.h)]

	def bounds(self):
		return (-self.ru, self.ru, -self.rv, self.rv, self.z0, self.z0 + self.h)

	exact = False


def _slab(a, b, lo, hi):
	"""Interval of t where lo <= a * t + b <= hi."""
	if abs(a) < 1e-12:
		return (-math.inf, math.inf) if lo <= b <= hi else None
	t0, t1 = (lo - b) / a, (hi - b) / a
	return (min(t0, t1), max(t0, t1))


def _material(paint, u, v, z, face):
	return paint(u, v, z, face) if callable(paint) else paint


def _shade_index(material, shade, materials):
	"""Palette index for a material at a light level 0..1."""
	spec = materials[material]
	if spec == 'cc':
		return pal.CC1[max(0, min(7, int(round(1 + shade * 6))))]
	if isinstance(spec, tuple) and spec[0] == 'cc':
		level = int(round(spec[1] + shade * 3))
		return pal.CC1[max(0, min(7, level))]
	factor = 0.55 + 0.75 * shade
	return pal.nearest(tuple(min(255, int(c * factor)) for c in spec))


def render_direction(model, materials, direction, step=0.02):
	"""Render one direction. Returns (image, xoff, yoff)."""
	fx, fy = FORWARD[direction]
	flen = math.hypot(fx, fy)
	sxv, syv = -fy / flen, fx / flen  # unit vector to the vehicle's right

	def to_world(u, v, z):
		return (u * fx + v * sxv, u * fy + v * syv, z)

	def normal_to_world(n):
		nu, nv, nz = n
		return _normalise((nu * fx / (flen * flen) + nv * sxv, nu * fy / (flen * flen) + nv * syv, nz))

	# Screen-space bounds of the model around the projected vehicle centre O.
	pts = [to_world(*c) for prim in model for c in prim.corners()]
	sxs = [2 * (y - x) for x, y, _ in pts]
	sys_ = [x + y - z for x, y, z in pts]
	x0, x1 = int(math.floor(min(sxs))) - 1, int(math.ceil(max(sxs))) + 1
	y0, y1 = int(math.floor(min(sys_))) - 1, int(math.ceil(max(sys_))) + 1

	width, height = x1 - x0, y1 - y0
	pixels = [[pal.TRANSPARENT] * width for _ in range(height)]
	inv = 1.0 / (flen * flen)
	for py in range(height):
		sy = y0 + py + 0.5
		for px in range(width):
			sx = x0 + px + 0.5
			# The pixel's view ray, parametrised by b = x + y (larger b is nearer
			# the camera): x = b/2 - sx/4, y = b/2 + sx/4, z = b - sy.
			# In local coordinates every axis is affine in b.
			au, bu = (fx + fy) / 2 * inv, (fy - fx) * sx / 4 * inv
			av, bv = (sxv + syv) / 2, (syv - sxv) * sx / 4
			best_b, best = -math.inf, None
			for prim in model:
				u0, u1, v0, v1, z0, z1 = prim.bounds()
				iu, iv, iz = _slab(au, bu, u0, u1), _slab(av, bv, v0, v1), _slab(1.0, -sy, z0, z1)
				if iu is None or iv is None:
					continue
				lo, hi = max(iu[0], iv[0], iz[0]), min(iu[1], iv[1], iz[1])
				if lo > hi or hi <= best_b:
					continue
				if prim.exact:
					hit_b = hi - 1e-6
				else:
					hit_b, b = None, hi
					while b >= lo:
						if prim.contains(au * b + bu, av * b + bv, b - sy):
							hit_b = b
							break
						b -= step
					if hit_b is None:
						continue
				if hit_b > best_b:
					best_b, best = hit_b, prim
			if best is None:
				continue
			u, v, z = au * best_b + bu, av * best_b + bv, best_b - sy
			normal, face = best.surface(u, v, z)
			shade = max(0.0, sum(a * c for a, c in zip(normal_to_world(normal), LIGHT)))
			pixels[py][px] = _shade_index(_material(best.paint, u, v, z, face), shade, materials)

	# Crop to content.
	rows = [i for i, row in enumerate(pixels) if any(row)]
	cols = [j for j in range(width) if any(pixels[i][j] for i in range(height))]
	top, bottom, left, right = rows[0], rows[-1] + 1, cols[0], cols[-1] + 1
	img = Image.new('P', (right - left, bottom - top), 0)
	img.putpalette(pal.DOS)
	img.putdata([pixels[i][j] for i in range(top, bottom) for j in range(left, right)])

	cx, bottom_edge = ANCHOR[direction]
	xoff = int(round(cx + (x0 + left)))
	yoff = bottom_edge - (bottom - top)
	return img, xoff, yoff


def render_set(model, materials, step=0.02):
	"""All 8 directions as [(direction, image, xoff, yoff)]."""
	return [(d, *render_direction(model, materials, d, step)) for d in DIRECTIONS]


def pack_strip(sprites, path):
	"""Save sprites side by side (1 px gap) as one 8bpp PNG; return NML sprite rows."""
	total_w = sum(img.width for _, img, _, _ in sprites) + len(sprites) + 1
	total_h = max(img.height for _, img, _, _ in sprites) + 2
	sheet = Image.new('P', (total_w, total_h), 0)
	sheet.putpalette(pal.DOS)
	rows, x = [], 1
	for direction, img, xoff, yoff in sprites:
		sheet.paste(img, (x, 1))
		rows.append((direction, x, 1, img.width, img.height, xoff, yoff))
		x += img.width + 1
	sheet.save(path, transparency=0)
	return rows


def contact_sheet(named_sets, path, scale=4):
	"""Review sheet: each set in all directions on a schematic track, scaled up."""
	cell_w, cell_h = 76, 60
	label_h = 12
	img = Image.new('RGB', (cell_w * 8 * scale, (cell_h + label_h) * len(named_sets) * scale), (232, 236, 240))
	draw = ImageDraw.Draw(img)
	for row, (name, sprites) in enumerate(named_sets):
		oy = row * (cell_h + label_h)
		draw.text((4, (oy + 1) * scale), name, fill=(40, 48, 60))
		for col, (direction, sprite, xoff, yoff) in enumerate(sprites):
			# Reference point of the sprite inside the cell, and the vehicle centre V.
			rx, ry = col * cell_w + cell_w // 2, oy + label_h + cell_h // 2 + 4
			ox, oy_w = SPRITE_OFFSET[direction]
			vx, vy = rx + 2 * ox - 2 * oy_w, ry - (ox + oy_w)  # screen(V) = R - screen(offset)
			fx, fy = FORWARD[direction]
			dx, dy = 2 * (fy - fx), (fx + fy)
			k = 24 / max(1, math.hypot(dx, dy))
			sx_, sy_ = -fy / math.hypot(fx, fy), fx / math.hypot(fx, fy)
			for side in (-0.8, 0.8):
				lx, ly = 2 * (sy_ - sx_) * side, (sx_ + sy_) * side
				draw.line([((vx + lx - dx * k) * scale, (vy + ly - dy * k) * scale),
						((vx + lx + dx * k) * scale, (vy + ly + dy * k) * scale)], fill=(120, 110, 100), width=scale)
			rgba = sprite.convert('RGBA')
			alpha = Image.new('L', sprite.size)
			alpha.putdata([0 if p == 0 else 255 for p in sprite.getdata()])
			rgba.putalpha(alpha)
			big = rgba.resize((sprite.width * scale, sprite.height * scale), Image.NEAREST)
			img.paste(big, ((rx + xoff) * scale, (ry + yoff) * scale), big)
			draw.text(((col * cell_w + 2) * scale, (oy + label_h) * scale), direction, fill=(90, 96, 110))
	img.save(path)
