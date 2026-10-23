"""Procedural 8bpp renderer for Modern Tycoon industry buildings.

Every pixel of the industry art comes from the small models in art/source/:
there is no hand-painted or third-party input. A model is a list of solids in
industry coordinates:

    x, y: OpenTTD world units, 16 per tile (x grows to the screen's lower
          left, y to the lower right, as on the map)
    z:    height in OpenTTD pixels above the ground (1 unit = 1 px at 1x zoom)

Projection is OpenTTD's own (RemapCoords): screen_x = 2 * (y - x),
screen_y = x + y - z. A pixel's view ray is cast through the model and hits
the nearest surface, which is shaded with the base set's upper-left light and
quantised to the DOS palette (tools/palette.py of the vehicle pack).

A multi-tile building is modelled once and cut per tile: each tile sprite
only shows surfaces inside that tile's 16 x 16 column, so the pieces line up
when OpenTTD draws the tiles back to front.

SPDX-License-Identifier: GPL-2.0-only
"""
import math
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'modern_tycoon_vehicles', 'tools'))
import palette as pal  # noqa: E402

TILE = 16
# Ray direction per unit of the ray parameter b = x + y (camera is at +b).
RAY = (0.5, 0.5, 1.0)
EPS = 1e-6


def _norm(v):
	n = math.sqrt(sum(c * c for c in v)) or 1.0
	return tuple(c / n for c in v)


# Light from the upper left of the screen and above, as in the base set.
LIGHT = _norm((0.6, -0.4, 1.0))


def _dot(a, b):
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


# --------------------------------------------------------------------------
# Primitives. intersect(o, d) returns (t_enter, t_exit, normal_at_exit, face)
# for the ray o + t*d, or None. "Exit" is the larger t, which is the surface
# nearest to the camera because the camera looks along -d.
# --------------------------------------------------------------------------

def _slab(o, d, lo, hi):
	if abs(d) < 1e-12:
		return (-math.inf, math.inf) if lo <= o <= hi else None
	t0, t1 = (lo - o) / d, (hi - o) / d
	return (t0, t1) if t0 <= t1 else (t1, t0)


class Box:
	"""Axis-aligned box. paint: material name or f(x, y, z, face) -> name."""

	def __init__(self, x, y, z, paint):
		self.lo = (x[0], y[0], z[0])
		self.hi = (x[1], y[1], z[1])
		self.paint = paint

	def bounds(self):
		return self.lo, self.hi

	def intersect(self, o, d):
		t_lo, t_hi, axis = -math.inf, math.inf, 2
		for i in range(3):
			s = _slab(o[i], d[i], self.lo[i], self.hi[i])
			if s is None:
				return None
			t_lo = max(t_lo, s[0])
			if s[1] < t_hi:
				t_hi, axis = s[1], i
		if t_lo > t_hi:
			return None
		n = [0.0, 0.0, 0.0]
		n[axis] = 1.0 if d[axis] > 0 else -1.0
		return t_lo, t_hi, tuple(n), ('x', 'y', 'top')[axis] if n[axis] > 0 else 'under'


class Cylinder:
	"""Cylinder along the local z axis; optional linear taper (frustum/cone)."""

	def __init__(self, cx, cy, r, z, paint, r_top=None):
		self.cx, self.cy, self.r = cx, cy, r
		self.r_top = r if r_top is None else r_top
		self.z0, self.z1 = z
		self.paint = paint

	def bounds(self):
		rm = max(self.r, self.r_top)
		return (self.cx - rm, self.cy - rm, self.z0), (self.cx + rm, self.cy + rm, self.z1)

	def _radius(self, z):
		f = (z - self.z0) / max(EPS, self.z1 - self.z0)
		return self.r + (self.r_top - self.r) * f

	def intersect(self, o, d):
		sz = _slab(o[2], d[2], self.z0, self.z1)
		if sz is None:
			return None
		ax, ay = o[0] - self.cx, o[1] - self.cy
		# radius(z) = k * z + m along the ray: r(t) = rk * t + rm
		k = (self.r_top - self.r) / max(EPS, self.z1 - self.z0)
		rk = k * d[2]
		rm = self.r + k * (o[2] - self.z0)
		a = d[0] * d[0] + d[1] * d[1] - rk * rk
		b = 2 * (ax * d[0] + ay * d[1] - rk * rm)
		c = ax * ax + ay * ay - rm * rm
		if a < -1e-12:
			return self._march(o, d, sz, ax, ay, rk, rm, k)
		if abs(a) < 1e-12:
			if abs(b) < 1e-12:
				return None
			t = -c / b
			roots = (t, t)
		else:
			disc = b * b - 4 * a * c
			if disc < 0:
				return None
			q = math.sqrt(disc)
			roots = sorted(((-b - q) / (2 * a), (-b + q) / (2 * a)))
		lo, hi = max(sz[0], roots[0]), min(sz[1], roots[1])
		if lo > hi:
			return None
		# Must be inside the (non-negative) radius region.
		tm = (lo + hi) / 2
		if rk * tm + rm < 0:
			return None
		if hi >= sz[1] - EPS and sz[1] <= roots[1]:
			z = o[2] + d[2] * hi
			n = (0.0, 0.0, 1.0) if d[2] > 0 else (0.0, 0.0, -1.0)
			return lo, hi, n, 'top' if d[2] > 0 else 'under'
		px, py, pz = o[0] + d[0] * hi - self.cx, o[1] + d[1] * hi - self.cy, o[2] + d[2] * hi
		rr = math.hypot(px, py) or 1.0
		n = _norm((px / rr, py / rr, -k))
		return lo, hi, n, 'side'

	def _march(self, o, d, sz, ax, ay, rk, rm, k):
		"""Flat cones seen nearly along their slope: sample the ray instead."""
		inside = []
		steps = 96
		for s in range(steps + 1):
			t = sz[0] + (sz[1] - sz[0]) * s / steps
			r = rk * t + rm
			if r >= 0 and (ax + d[0] * t) ** 2 + (ay + d[1] * t) ** 2 <= r * r:
				inside.append(t)
		if not inside:
			return None
		hi = inside[-1]
		if hi >= sz[1] - EPS:
			return inside[0], hi, ((0.0, 0.0, 1.0) if d[2] > 0 else (0.0, 0.0, -1.0)), 'top' if d[2] > 0 else 'under'
		px, py = ax + d[0] * hi, ay + d[1] * hi
		rr = math.hypot(px, py) or 1.0
		return inside[0], hi, _norm((px / rr, py / rr, -k)), 'side'


class Sphere:
	def __init__(self, cx, cy, cz, r, paint, sz=1.0):
		self.c = (cx, cy, cz)
		self.r, self.sz = r, sz  # sz squashes the sphere vertically
		self.paint = paint

	def bounds(self):
		cx, cy, cz = self.c
		return (cx - self.r, cy - self.r, cz - self.r * self.sz), (cx + self.r, cy + self.r, cz + self.r * self.sz)

	def intersect(self, o, d):
		s = self.sz
		ax, ay, az = o[0] - self.c[0], o[1] - self.c[1], (o[2] - self.c[2]) / s
		dx, dy, dz = d[0], d[1], d[2] / s
		a = dx * dx + dy * dy + dz * dz
		b = 2 * (ax * dx + ay * dy + az * dz)
		c = ax * ax + ay * ay + az * az - self.r * self.r
		disc = b * b - 4 * a * c
		if disc < 0:
			return None
		q = math.sqrt(disc)
		t0, t1 = (-b - q) / (2 * a), (-b + q) / (2 * a)
		px, py, pz = ax + dx * t1, ay + dy * t1, az + dz * t1
		return t0, t1, _norm((px, py, pz / s)), 'side'


class Rotated:
	"""A primitive turned by yaw (around z) and then pitch (around the turned y axis) about a pivot."""

	def __init__(self, prim, pivot, yaw=0.0, pitch=0.0, roll=0.0):
		self.prim, self.pivot = prim, pivot
		cy, sy = math.cos(yaw), math.sin(yaw)
		cp, sp = math.cos(pitch), math.sin(pitch)
		cr, sr = math.cos(roll), math.sin(roll)
		# local -> world rotation matrix R = Rz(yaw) * Ry(pitch) * Rx(roll)
		rz = ((cy, -sy, 0), (sy, cy, 0), (0, 0, 1))
		ry = ((cp, 0, sp), (0, 1, 0), (-sp, 0, cp))
		rx = ((1, 0, 0), (0, cr, -sr), (0, sr, cr))
		self.R = _matmul(_matmul(rz, ry), rx)
		self.paint = self._paint
		self._inner_paint = prim.paint

	def _paint(self, x, y, z, face):
		lx, ly, lz = self.to_local((x, y, z))
		p = self._inner_paint
		return p(lx, ly, lz, face) if callable(p) else p

	def to_local(self, p):
		v = tuple(p[i] - self.pivot[i] for i in range(3))
		R = self.R
		return tuple(R[0][i] * v[0] + R[1][i] * v[1] + R[2][i] * v[2] for i in range(3))

	def bounds(self):
		lo, hi = self.prim.bounds()
		pts = [(x, y, z) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]
		R = self.R
		w = [tuple(sum(R[i][j] * p[j] for j in range(3)) + self.pivot[i] for i in range(3)) for p in pts]
		return tuple(min(q[i] for q in w) for i in range(3)), tuple(max(q[i] for q in w) for i in range(3))

	def intersect(self, o, d):
		R = self.R
		lo_ = self.to_local(o)
		ld = tuple(R[0][i] * d[0] + R[1][i] * d[1] + R[2][i] * d[2] for i in range(3))
		hit = self.prim.intersect(lo_, ld)
		if hit is None:
			return None
		t0, t1, n, face = hit
		wn = tuple(sum(R[i][j] * n[j] for j in range(3)) for i in range(3))
		return t0, t1, wn, face


def _matmul(a, b):
	return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))


# --------------------------------------------------------------------------
# Materials and shading
# --------------------------------------------------------------------------

def _paint_of(prim, p, face):
	paint = prim.paint
	return paint(p[0], p[1], p[2], face) if callable(paint) else paint


def shade_index(material, shade, materials):
	"""Palette index for a material at light level 0..1."""
	spec = materials[material]
	if spec == 'cc':
		return pal.CC1[max(0, min(7, int(round(1 + shade * 6))))]
	if isinstance(spec, tuple) and spec and spec[0] == 'cc':
		return pal.CC1[max(0, min(7, int(round(spec[1] + shade * 3))))]
	if isinstance(spec, tuple) and spec and spec[0] == 'glow':
		return pal.nearest(spec[1])  # emissive: not shaded
	factor = 0.55 + 0.75 * shade
	return pal.nearest(tuple(min(255, int(c * factor)) for c in spec))


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------

class Sprite:
	"""An 8bpp image with its offset from the reference point (OpenTTD xoff/yoff)."""

	def __init__(self, img, xoff, yoff):
		self.img, self.xoff, self.yoff = img, xoff, yoff

	@property
	def empty(self):
		return self.img is None


def _screen_bounds(model, clip):
	xs, ys = [], []
	for prim in model:
		lo, hi = prim.bounds()
		if clip:
			lo = (max(lo[0], clip[0][0]), max(lo[1], clip[0][1]), lo[2])
			hi = (min(hi[0], clip[1][0]), min(hi[1], clip[1][1]), hi[2])
			if lo[0] > hi[0] or lo[1] > hi[1]:
				continue
		for x in (lo[0], hi[0]):
			for y in (lo[1], hi[1]):
				for z in (lo[2], hi[2]):
					xs.append(2 * (y - x))
					ys.append(x + y - z)
	if not xs:
		return None
	return int(math.floor(min(xs))) - 1, int(math.ceil(max(xs))) + 1, int(math.floor(min(ys))) - 1, int(math.ceil(max(ys))) + 1


def render(model, materials, clip=None, origin=(0, 0, 0)):
	"""Render a model. clip = ((x0, y0), (x1, y1)) keeps only surfaces in that column.

	Offsets are relative to the screen position of `origin` (the bounding box
	origin OpenTTD draws the sprite at). Returns a Sprite (img None if empty).
	"""
	sb = _screen_bounds(model, clip)
	if sb is None:
		return Sprite(None, 0, 0)
	x0, x1, y0, y1 = sb
	w, h = x1 - x0, y1 - y0
	px = bytearray(w * h)
	d = RAY
	prims = []
	for prim in model:
		lo, hi = prim.bounds()
		if clip and (hi[0] < clip[0][0] or lo[0] > clip[1][0] or hi[1] < clip[0][1] or lo[1] > clip[1][1]):
			continue
		prims.append(prim)
	for j in range(h):
		sy = y0 + j + 0.5
		for i in range(w):
			sx = x0 + i + 0.5
			o = (-sx / 4, sx / 4, -sy)
			c_lo, c_hi = -math.inf, math.inf
			if clip:
				s1 = _slab(o[0], d[0], clip[0][0], clip[1][0])
				s2 = _slab(o[1], d[1], clip[0][1], clip[1][1])
				c_lo, c_hi = max(s1[0], s2[0]), min(s1[1], s2[1])
				if c_lo > c_hi:
					continue
			best_t, best = -math.inf, None
			for prim in prims:
				hit = prim.intersect(o, d)
				if hit is None:
					continue
				t0, t1, n, face = hit
				if t1 > c_hi:
					# The nearest surface is outside the clip column: look at the cut face.
					if t0 > c_hi:
						continue
					t1, n, face = c_hi, None, 'cut'
				if t1 < c_lo or t1 <= best_t:
					continue
				best_t, best = t1, (prim, n, face)
			if best is None:
				continue
			prim, n, face = best
			if n is None:
				continue  # cut faces are hidden by the neighbouring tile's sprite
			p = (o[0] + d[0] * best_t, o[1] + d[1] * best_t, o[2] + d[2] * best_t)
			mat = _paint_of(prim, p, face)
			if mat is None:
				continue
			shade = max(0.0, _dot(n, LIGHT))
			px[j * w + i] = shade_index(mat, shade, materials)
	return _crop(px, w, h, x0, y0, origin)


def _crop(px, w, h, x0, y0, origin):
	rows = [j for j in range(h) if any(px[j * w:(j + 1) * w])]
	if not rows:
		return Sprite(None, 0, 0)
	cols = [i for i in range(w) if any(px[j * w + i] for j in rows)]
	top, bottom, left, right = rows[0], rows[-1] + 1, cols[0], cols[-1] + 1
	img = Image.new('P', (right - left, bottom - top), 0)
	img.putpalette(pal.DOS)
	img.putdata([px[j * w + i] for j in range(top, bottom) for i in range(left, right)])
	ox, oy, oz = origin
	# +1: base-set flat tiles span screen columns -31..32 around the tile's
	# north corner, one column right of the exact projection.
	return Sprite(img, x0 + left - 2 * (oy - ox) + 1, y0 + top - (ox + oy - oz))


def composite(layers):
	"""Paint Sprites over each other (first is at the back). Returns one Sprite."""
	layers = [s for s in layers if not s.empty]
	if not layers:
		return Sprite(None, 0, 0)
	x0 = min(s.xoff for s in layers)
	y0 = min(s.yoff for s in layers)
	x1 = max(s.xoff + s.img.width for s in layers)
	y1 = max(s.yoff + s.img.height for s in layers)
	img = Image.new('P', (x1 - x0, y1 - y0), 0)
	img.putpalette(pal.DOS)
	for s in layers:
		mask = Image.new('L', s.img.size)
		mask.putdata([0 if p == 0 else 255 for p in s.img.getdata()])
		img.paste(s.img, (s.xoff - x0, s.yoff - y0), mask)
	return Sprite(img, x0, y0)


def shifted(sprite, dx=0, dy=0):
	return Sprite(sprite.img, sprite.xoff + dx, sprite.yoff + dy)


def clip_top(sprite, min_y):
	"""Remove the part of a sprite above screen row min_y (relative to the reference point)."""
	if sprite.empty or sprite.yoff >= min_y:
		return sprite
	cut = min_y - sprite.yoff
	if cut >= sprite.img.height:
		return Sprite(None, 0, 0)
	img = sprite.img.crop((0, cut, sprite.img.width, sprite.img.height))
	return Sprite(img, sprite.xoff, min_y)


def tile_clip(tx, ty):
	return ((tx * TILE, ty * TILE), ((tx + 1) * TILE, (ty + 1) * TILE))


def clip_box(sprite, x0, x1, y0, y1):
	"""Keep only the part of a sprite inside the screen box [x0, x1) x [y0, y1) around its reference point."""
	if sprite.empty:
		return sprite
	l, t = max(x0, sprite.xoff), max(y0, sprite.yoff)
	r, b = min(x1, sprite.xoff + sprite.img.width), min(y1, sprite.yoff + sprite.img.height)
	if l >= r or t >= b:
		return Sprite(None, 0, 0)
	img = sprite.img.crop((l - sprite.xoff, t - sprite.yoff, r - sprite.xoff, b - sprite.yoff))
	# Re-crop to content so empty borders do not waste space.
	bbox = Image.frombytes('L', img.size, img.tobytes()).getbbox()
	if bbox is None:
		return Sprite(None, 0, 0)
	return Sprite(img.crop(bbox), l + bbox[0], t + bbox[1])
