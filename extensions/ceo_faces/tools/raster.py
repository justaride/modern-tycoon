"""Supersampled drawing canvas for face parts.

Every part is drawn as a map of (material, shade 0..1) at 4x resolution, then
reduced to the 92x119 face frame and quantised to palette indices with an
ordered dither. Materials are palette ramps; the recolourable ones (skin, hair,
eyes, cloth) use "label" ramps that the game recolours at draw time.

SPDX-License-Identifier: GPL-2.0-only
"""
import math

import numpy as np
from PIL import Image, ImageDraw

W, H = 92, 119  # size of the face frame (the gradient sprite)
SS = 4
GW, GH = W * SS, H * SS
# Parts are designed in 'design units'; they are scaled up around ORIGIN to fill the frame.
SCALE = 1.2
ORIGIN = (46.0, 64.0)
_ys, _xs = np.mgrid[0:GH, 0:GW]
X = (ORIGIN[0] + ((_xs + 0.5) / SS - ORIGIN[0]) / SCALE).astype(np.float32)
Y = (ORIGIN[1] + ((_ys + 0.5) / SS - ORIGIN[1]) / SCALE).astype(np.float32)
del _xs, _ys
K = SS * SCALE  # samples per design unit
_oy, _ox = np.mgrid[0:GH, 0:GW] // SS
CHECKER = ((_ox + _oy) % 2) == 0  # one-pixel checkerboard in face pixels
del _ox, _oy


def px(x, y):
	"""Design units to sample coordinates."""
	return ((ORIGIN[0] + (x - ORIGIN[0]) * SCALE) * SS, (ORIGIN[1] + (y - ORIGIN[1]) * SCALE) * SS)

LIGHT = np.array([-0.42, -0.55, 0.72])
LIGHT = LIGHT / np.linalg.norm(LIGHT)

BAYER4 = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16


# ---------------------------------------------------------------- geometry

def catmull(pts, closed=True, n=10):
	"""Smooth curve through the points (Catmull-Rom)."""
	pts = [tuple(p) for p in pts]
	if len(pts) < 3:
		return pts
	out = []
	m = len(pts)
	rng = range(m) if closed else range(m - 1)
	for i in rng:
		p0 = pts[(i - 1) % m] if closed or i > 0 else pts[0]
		p1 = pts[i]
		p2 = pts[(i + 1) % m]
		p3 = pts[(i + 2) % m] if closed or i + 2 < m else pts[-1]
		for k in range(n):
			t = k / n
			t2, t3 = t * t, t * t * t
			out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2 + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in range(2)))
	if not closed:
		out.append(pts[-1])
	return out


def mirror(cx, half):
	"""Closed outline from the right half (top to bottom) mirrored around x = cx."""
	right = [(cx + dx, y) for dx, y in half]
	left = [(cx - dx, y) for dx, y in reversed(half) if dx != 0]
	return right + left


def poly(pts, smooth=True):
	if smooth:
		pts = catmull(pts)
	im = Image.new('L', (GW, GH), 0)
	ImageDraw.Draw(im).polygon([px(x, y) for x, y in pts], fill=255)
	return np.asarray(im) > 127


def ellipse(cx, cy, rx, ry, angle=0.0):
	if angle:
		c, s = math.cos(math.radians(angle)), math.sin(math.radians(angle))
		dx, dy = X - cx, Y - cy
		u, v = dx * c + dy * s, -dx * s + dy * c
		return (u / rx) ** 2 + (v / ry) ** 2 <= 1
	return ((X - cx) / rx) ** 2 + ((Y - cy) / ry) ** 2 <= 1


def stroke(pts, widths, smooth=True, n=8):
	"""Mask of a brush stroke along the points; widths is a number or one per point."""
	if not isinstance(widths, (list, tuple)):
		widths = [widths] * len(pts)
	if smooth and len(pts) >= 3:
		path = catmull(pts, closed=False, n=n)
		wpath = np.interp(np.linspace(0, len(pts) - 1, len(path)), range(len(pts)), widths)
	else:
		path = []
		wpath = []
		for i in range(len(pts) - 1):
			for k in range(n):
				t = k / n
				path.append(tuple(pts[i][j] + (pts[i + 1][j] - pts[i][j]) * t for j in range(2)))
				wpath.append(widths[i] + (widths[i + 1] - widths[i]) * t)
		path.append(pts[-1])
		wpath.append(widths[-1])
	im = Image.new('L', (GW, GH), 0)
	d = ImageDraw.Draw(im)
	for (x, y), w in zip(path, wpath):
		r = max(w * K / 2, 0.5)
		sx, sy = px(x, y)
		d.ellipse([sx - r, sy - r, sx + r, sy + r], fill=255)
	return np.asarray(im) > 127


def rect(x0, y0, x1, y1):
	return (X >= x0) & (X < x1) & (Y >= y0) & (Y < y1)


def gauss(cx, cy, sx, sy):
	return np.exp(-(((X - cx) / sx) ** 2 + ((Y - cy) / sy) ** 2) / 2)


# ---------------------------------------------------------------- shading

def _box(a, r, axis):
	if r < 1:
		return a
	c = np.cumsum(np.pad(a, [(r + 1, r) if k == axis else (0, 0) for k in range(2)], mode='edge'), axis=axis)
	if axis == 0:
		return (c[2 * r + 1:] - c[:-2 * r - 1]) / (2 * r + 1)
	return (c[:, 2 * r + 1:] - c[:, :-2 * r - 1]) / (2 * r + 1)


def blur(a, radius):
	"""Approximate gaussian blur; radius in face pixels."""
	r = max(int(radius * K / 2), 1)
	a = a.astype(np.float32)
	for _ in range(2):
		a = _box(_box(a, r, 0), r, 1)
	return a


def lambert(mask, radius, depth=1.0, light=LIGHT):
	"""Diffuse light on a soft bump shaped like the mask (0..1)."""
	h = blur(mask, radius) * radius * depth
	gy, gx = np.gradient(h)
	gx *= K
	gy *= K
	nz = np.ones_like(h)
	norm = np.sqrt(gx * gx + gy * gy + 1)
	d = (-gx * light[0] - gy * light[1] + nz * light[2]) / norm
	return np.clip(d, 0, 1)


def dome(cx, cy, rx, ry):
	"""Lambert shade of an ellipsoid, valid inside the ellipse."""
	u = (X - cx) / rx
	v = (Y - cy) / ry
	z = np.sqrt(np.clip(1 - u * u - v * v, 0, 1))
	return np.clip(u * LIGHT[0] + v * LIGHT[1] + z * LIGHT[2], 0, 1)


def rng_noise(seed, scale=1.0):
	"""Smooth value noise at roughly 'scale' face pixels."""
	r = np.random.default_rng(seed)
	n = r.random((GH, GW)).astype(np.float32)
	if scale > 0.3:
		n = blur(n, scale)
		n = (n - n.min()) / max(n.max() - n.min(), 1e-6)
	return n


def streaks(seed, angle, length=6.0, width=0.6):
	"""Hair-like streak texture along 'angle' degrees (0 = down)."""
	r = np.random.default_rng(seed)
	pad = 60
	n = r.random((GH + 2 * pad, GW + 2 * pad)).astype(np.float32)
	im = Image.fromarray((n * 255).astype(np.uint8))
	im = im.rotate(-angle, resample=Image.BILINEAR)
	a = np.asarray(im).astype(np.float32) / 255
	a = _box(a, max(int(length * K / 2), 1), 0)
	a = _box(a, max(int(width * K / 2), 0), 1)
	im = Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8)).rotate(angle, resample=Image.BILINEAR)
	a = np.asarray(im).astype(np.float32)[pad:pad + GH, pad:pad + GW] / 255
	a = (a - a.mean()) / max(a.std(), 1e-6)
	return np.clip(0.5 + a * 0.22, 0, 1)


def curls(seed, mask, radius=1.6, density=1.0):
	"""Shade map made of many small lit spheres inside the mask (curly hair, beards)."""
	r = np.random.default_rng(seed)
	sub = mask[::SS, ::SS]
	ys, xs = Y[::SS, ::SS][sub], X[::SS, ::SS][sub]
	shade = np.full((GH, GW), 0.35, np.float32)
	if len(xs) == 0:
		return shade
	count = int(len(xs) * density / (radius * radius) * 1.2)
	idx = r.integers(0, len(xs), count)
	order = np.argsort(ys[idx] + r.random(count) * 3)
	for k in idx[order]:
		cx, cy = xs[k] + r.random() - 0.5, ys[k] + r.random() - 0.5
		rr = radius * (0.7 + 0.6 * r.random())
		sx0, sy0 = px(cx - rr, cy - rr)
		sx1, sy1 = px(cx + rr, cy + rr)
		x0, x1 = int(max(sx0, 0)), int(min(sx1 + 1, GW))
		y0, y1 = int(max(sy0, 0)), int(min(sy1 + 1, GH))
		if x0 >= x1 or y0 >= y1:
			continue
		u = (X[y0:y1, x0:x1] - cx) / rr
		v = (Y[y0:y1, x0:x1] - cy) / rr
		inside = u * u + v * v <= 1
		z = np.sqrt(np.clip(1 - u * u - v * v, 0, 1))
		s = np.clip(u * LIGHT[0] + v * LIGHT[1] + z * LIGHT[2], 0, 1)
		blk = shade[y0:y1, x0:x1]
		blk[inside] = s[inside]
	return shade


# ---------------------------------------------------------------- layers

class Layer:
	"""One sprite under construction: material id and shade per sample."""

	def __init__(self):
		self.mat = np.full((GH, GW), -1, np.int16)
		self.shade = np.zeros((GH, GW), np.float32)

	def paint(self, mask, mat, shade):
		from materials import MAT_ID
		m = MAT_ID[mat]
		self.mat[mask] = m
		if isinstance(shade, np.ndarray):
			self.shade[mask] = np.clip(shade[mask], 0, 1)
		else:
			self.shade[mask] = min(max(shade, 0), 1)

	def erase(self, mask):
		self.mat[mask] = -1

	def over(self, other):
		"""Draw another layer on top of this one."""
		m = other.mat >= 0
		self.mat[m] = other.mat[m]
		self.shade[m] = other.shade[m]
		return self


def finalize(layer, dither=1.0, threshold=0.5):
	"""Reduce to face resolution; returns a W x H uint8 array of palette indices."""
	from materials import RAMPS
	mat = layer.mat.reshape(H, SS, W, SS).transpose(0, 2, 1, 3).reshape(H, W, SS * SS)
	sh = layer.shade.reshape(H, SS, W, SS).transpose(0, 2, 1, 3).reshape(H, W, SS * SS)
	cov = (mat >= 0).sum(-1)
	best = np.full((H, W), -1, np.int32)
	bestc = np.zeros((H, W), np.int32)
	for m in np.unique(mat):
		if m < 0:
			continue
		c = (mat == m).sum(-1)
		upd = c > bestc
		best[upd] = m
		bestc[upd] = c[upd]
	ssum = np.where(mat == best[..., None], sh, 0).sum(-1)
	shade = ssum / np.maximum(bestc, 1)
	out = np.zeros((H, W), np.uint8)
	opaque = cov >= SS * SS * threshold
	bay = np.tile(BAYER4, (H // 4 + 1, W // 4 + 1))[:H, :W]
	for m in np.unique(best[opaque]):
		ramp = RAMPS[m]
		n = len(ramp)
		sel = opaque & (best == m)
		lv = shade[sel] * (n - 1) + (bay[sel] - 0.5) * dither
		idx = np.clip(np.rint(lv), 0, n - 1).astype(int)
		out[sel] = np.array(ramp, np.uint8)[idx]
	return out


def stack(images):
	"""Overlay finalised index images (later ones on top)."""
	out = images[0].copy()
	for im in images[1:]:
		m = im != 0
		out[m] = im[m]
	return out
