"""Face parts. Each function returns a raster.Layer for one sprite.

Coordinates are face pixels in the 92x119 frame. The skull, eyes, nose and
mouth sit at fixed places so every part fits every head shape.

SPDX-License-Identifier: GPL-2.0-only
"""
import numpy as np

from raster import (CHECKER, GH, GW, X, Y, Layer, blur, catmull, curls, dome, ellipse, gauss, lambert, mirror, poly, rect, rng_noise, streaks, stroke)

CX = 46.0
EYE_Y = 47.5
EYE_DX = 10.5
BROW_Y = 41.0
NOSE_Y = 59.5  # nose tip
MOUTH_Y = 68.5
SKULL_TOP = 18.0

# ------------------------------------------------------------------ head

HEADS = {
	# cheek half-width, jaw half-width, chin half-width, chin y
	'oval': (23.0, 19.0, 8.0, 82.0),
	'round': (24.5, 22.0, 11.0, 81.0),
	'square': (23.5, 22.5, 13.0, 82.0),
	'long': (21.5, 18.0, 8.5, 85.0),
	'heavy': (25.0, 24.0, 14.0, 83.5),
	'heart': (23.5, 17.0, 6.0, 81.0),
	'broad': (25.0, 23.0, 12.0, 80.0),
	'narrow': (21.0, 17.0, 7.0, 82.0),
	'soft': (23.0, 20.0, 9.5, 81.0),
}


def head_outline(shape):
	cheek, jaw, chin, chin_y = HEADS[shape]
	half = [(0, SKULL_TOP), (12, SKULL_TOP + 2), (19.5, 26), (23, 35), (23.5, 46),
		(cheek, 55), (jaw, 67), (chin + 3.5, chin_y - 5.5), (chin, chin_y - 1.5), (0, chin_y)]
	return mirror(CX, half)


def head_mask(shape):
	return poly(head_outline(shape))


def skin_shade(mask, age=0):
	lam = lambert(mask, 9.0, depth=1.3)
	s = 0.16 + 0.84 * lam
	s += 0.07 * gauss(CX - 5, 30, 8, 5)  # forehead
	s += 0.05 * gauss(CX - 13, 57, 4, 3) + 0.03 * gauss(CX + 12, 57, 4, 3)  # cheeks
	for side in (-1, 1):
		s -= 0.13 * gauss(CX + side * EYE_DX, EYE_Y - 1, 5.0, 3.0)  # eye sockets
		s += 0.05 * gauss(CX + side * EYE_DX, BROW_Y - 1.5, 5, 1.5)  # brow ridge
	s -= 0.05 * gauss(CX + 19, 40, 3, 6)  # temple
	if age:
		s -= 0.05 * age * gauss(CX, 30, 14, 6) * (np.sin(Y * 2.2) > 0.6)  # forehead lines
		for side in (-1, 1):
			crease = stroke([(CX + side * 6.5, 60), (CX + side * 9, 65), (CX + side * 9.5, 71)], 0.8)
			s = np.where(crease, s - 0.12 * age, s)
			s -= 0.08 * age * gauss(CX + side * EYE_DX, EYE_Y + 3.2, 3.5, 1.0)  # bags
	return s


_REF = None


def ref_shade():
	"""Skin shade of a reference head, used by parts drawn on top of the skin."""
	global _REF
	if _REF is None:
		_REF = skin_shade(head_mask('oval'))
	return _REF


def head(shape='oval', age=0, neck=10.5):
	ly = Layer()
	# neck
	nk = poly([(CX - neck, 64), (CX + neck, 64), (CX + neck + 2, 104), (CX - neck - 2, 104)], smooth=False)
	ns = 0.30 + 0.22 * np.clip((Y - 80) / 20, 0, 1) - 0.06 * np.clip((X - CX) / neck, -1, 1)
	ly.paint(nk, 'skin', ns)
	# ears
	for side in (-1, 1):
		ex = CX + side * 22.8
		em = ellipse(ex, 51.5, 3.8, 7.5, angle=side * -8)
		es = 0.25 + 0.5 * dome(ex, 51.5, 3.8, 7.5) - 0.18 * gauss(ex + side * 0.6, 51, 1.3, 3.5)
		if side > 0:
			es -= 0.08
		ly.paint(em, 'skin', es)
	m = head_mask(shape)
	s = skin_shade(m, age)
	if shape == 'heavy':
		s -= 0.12 * gauss(CX, 81, 10, 1.3)  # double chin line
	ly.paint(m, 'skin', s)
	# shadow of the jaw on the neck
	below = (~m) & nk & (Y < 90)
	ly.shade[below] -= 0.12 * np.exp(-np.clip(Y[below] - 70, 0, None) / 8)
	return ly


# ------------------------------------------------------------------ eyes

EYES = {
	# half width, upper height, lower height, tilt, lash weight, lid cover
	'almond': (4.3, 2.4, 1.4, 0.3, 0.9, 0.0),
	'round': (4.0, 2.8, 1.8, 0.0, 0.9, 0.0),
	'narrow': (4.4, 1.7, 1.0, 0.2, 0.9, 0.0),
	'hooded': (4.2, 2.3, 1.3, -0.2, 1.1, 0.7),
	'upturned': (4.3, 2.3, 1.3, 1.0, 0.9, 0.0),
	'downturned': (4.3, 2.3, 1.4, -0.9, 0.9, 0.0),
	'monolid': (4.4, 1.6, 1.2, 0.6, 1.0, 0.0),
	'lashes': (4.3, 2.5, 1.4, 0.5, 1.4, 0.0),
	'lashes_round': (4.0, 2.9, 1.7, 0.2, 1.4, 0.0),
	'smiling': (4.3, 1.9, 0.6, 0.2, 1.0, 0.0),
}


def eyes(kind='almond', look=0.0):
	ew, up, lo, tilt, lash, cover = EYES[kind]
	ly = Layer()
	for side in (-1, 1):
		cx = CX + side * EYE_DX
		cy = EYE_Y
		inner = (cx - side * ew, cy + 0.2)
		outer = (cx + side * ew, cy - tilt)
		top = (cx + side * 0.6, cy - up)
		bot = (cx + side * 0.4, cy + lo)
		upper = catmull([inner, (cx - side * ew * 0.45, cy - up * 0.85), top, (cx + side * ew * 0.6, cy - up * 0.6 - tilt * 0.5), outer], closed=False, n=6)
		lower = catmull([outer, (cx + side * ew * 0.5, cy + lo * 0.7 - tilt * 0.4), bot, (cx - side * ew * 0.55, cy + lo * 0.6), inner], closed=False, n=6)
		outline = upper + lower[1:]
		m = poly(outline, smooth=False)
		# sclera, shaded darker under the upper lid and at the corners
		sc = 0.85 - 0.35 * np.clip((cy - up * 0.3 - Y) / up + 0.6, 0, 1) - 0.25 * np.abs((X - cx) / ew) ** 2
		if side > 0:
			sc -= 0.1
		ly.paint(m, 'sclera', sc)
		ix = cx + look + side * 0.15
		iy = cy - 0.1
		ir = 2.05 if kind not in ('narrow', 'monolid', 'smiling') else 1.95
		iris = ellipse(ix, iy, ir, ir) & m
		ish = 0.25 + 0.6 * np.clip((Y - (iy - ir)) / (2 * ir), 0, 1) + 0.15 * gauss(ix + 0.8, iy + 0.9, 0.8, 0.6)
		ly.paint(iris, 'eye', ish)
		ly.paint(ellipse(ix, iy, 0.85, 0.95) & m, 'pupil', 0.2)
		ly.paint(ellipse(ix - 0.75, iy - 0.75, 0.42, 0.42) & m, 'white', 1.0)
		if cover:
			lid = poly([(inner[0], inner[1] - 0.2), (cx, cy - up * (1 - cover) - 0.2), (outer[0], outer[1] - 0.2), (outer[0], cy - up - 3), (inner[0], cy - up - 3)])
			ly.erase(lid & m & (Y < cy - up * (1 - cover) + 0.1))
		# lash line along the upper lid
		lw = [lash * 0.6, lash * 0.9, lash, lash * 1.1, lash * (1.6 if lash > 1.2 else 1.0)]
		pts = [inner, (cx - side * ew * 0.45, cy - up * 0.85), top, (cx + side * ew * 0.6, cy - up * 0.6 - tilt * 0.5), outer]
		if cover:
			pts = [(px, py + (up * cover * 0.9 if k in (1, 2, 3) else 0)) for k, (px, py) in enumerate(pts)]
		lm = stroke(pts, lw)
		if lash > 1.2:
			lm |= stroke([outer, (outer[0] + side * 1.4, outer[1] - 1.3)], [1.0, 0.5], smooth=False)
		ly.paint(lm, 'lash', 0.5)
		# faint lower lash line at the outer half
		ll = stroke([(cx + side * ew * 0.1, cy + lo * 0.95), (cx + side * ew * 0.6, cy + lo * 0.7 - tilt * 0.4), outer], 0.45)
		ly.paint(ll & ~m, 'lash', 1.0)
	return ly


# ------------------------------------------------------------------ eyebrows

BROWS = {
	# (inner, peak, outer) offsets from eye centre (dx, dy relative to BROW_Y) and widths
	'straight': ([(-5.8, 0.6), (0.0, -0.4), (5.5, 0.2)], [1.9, 1.8, 1.0]),
	'arched': ([(-5.6, 0.8), (1.5, -1.8), (6.0, 0.8)], [1.2, 1.1, 0.5]),
	'soft': ([(-5.6, 0.6), (1.0, -1.0), (5.8, 0.5)], [1.6, 1.4, 0.7]),
	'thick': ([(-5.8, 0.6), (0.5, -0.8), (5.8, 0.4)], [2.5, 2.3, 1.3]),
	'stern': ([(-5.6, 1.6), (0.5, -0.2), (5.8, -0.4)], [2.1, 1.9, 1.0]),
	'high': ([(-5.4, -0.2), (1.2, -2.6), (6.0, -0.6)], [1.1, 1.0, 0.5]),
	'bushy': ([(-6.2, 0.6), (0.5, -1.2), (6.4, 0.6)], [2.8, 3.0, 2.0]),
	'thin': ([(-5.4, 0.6), (1.2, -1.4), (6.0, 0.6)], [0.85, 0.8, 0.45]),
	'raised': ([(-5.4, -0.6), (0.6, -2.2), (6.0, -0.2)], [1.6, 1.5, 0.8]),
	'unibrow': ([(-5.8, 0.6), (0.5, -1.0), (5.8, 0.5)], [2.0, 1.9, 1.0]),
}


def brows(kind='straight', seed=1):
	pts, ws = BROWS[kind]
	ly = Layer()
	tex = streaks(seed, 75, length=2.0, width=0.4)
	mask = np.zeros((GH, GW), bool)
	for side in (-1, 1):
		cx = CX + side * EYE_DX
		p = [(cx + side * dx, BROW_Y + dy) for dx, dy in pts]
		mask |= stroke(p, ws)
	if kind == 'unibrow':
		mask |= stroke([(CX - 5.5, BROW_Y + 0.8), (CX, BROW_Y + 1.6), (CX + 5.5, BROW_Y + 0.8)], [1.6, 1.2, 1.6])
	sh = 0.18 + 0.5 * tex + 0.15 * (X < CX)
	if kind == 'bushy':
		sh = curls(seed, mask, radius=0.9) * 0.7 + 0.2
		mask &= ~((rng_noise(seed + 9, 0.5) > 0.82) & ~blur(mask, 0.6).__gt__(0.9))
	ly.paint(mask, 'hair', sh)
	return ly


# ------------------------------------------------------------------ nose

NOSES = {
	# nostril half width, tip y, bridge width, tip size, hook
	'straight': (4.2, NOSE_Y, 1.0, 1.0, 0.0),
	'small': (3.6, NOSE_Y - 1.0, 0.8, 0.85, 0.0),
	'button': (3.9, NOSE_Y - 0.6, 0.7, 1.2, -0.4),
	'broad': (5.4, NOSE_Y + 0.2, 1.3, 1.25, 0.0),
	'aquiline': (4.1, NOSE_Y + 0.8, 1.1, 1.0, 0.8),
	'hooked': (4.4, NOSE_Y + 1.4, 1.2, 1.2, 1.4),
	'long': (4.0, NOSE_Y + 1.6, 0.9, 0.95, 0.3),
	'wide_flat': (6.0, NOSE_Y, 1.4, 1.3, -0.3),
}


def _delta_layer(delta, mat='skin', threshold=0.025, base=None):
	ly = Layer()
	if base is None:
		base = ref_shade()
	m = np.abs(delta) > threshold
	ly.paint(m, mat, base + delta)
	return ly


def nose_delta(kind):
	nw, ty, bw, tip, hook = NOSES[kind]
	d = np.zeros((GH, GW), np.float32)
	# shadow along the right side of the bridge, light along the left
	d -= 0.13 * stroke([(CX + 1.8 * bw, 46), (CX + 2.1 * bw + hook * 0.3, 52), (CX + 2.8 * bw, ty - 2)], 1.6 * bw)
	d += 0.07 * stroke([(CX - 1.0, 47), (CX - 1.2 + hook * 0.3, 53), (CX - 1.2, ty - 2.5)], 1.1 * bw)
	if hook > 0.5:
		d += 0.08 * gauss(CX - 0.6, 51, 0.8, 1.6)
	# tip and wings
	d += 0.12 * gauss(CX - 0.6, ty - 1.4, 1.4 * tip, 1.1 * tip)
	for side in (-1, 1):
		wing = ellipse(CX + side * (nw - 0.9), ty - 0.2, 1.6 * tip, 1.5 * tip)
		d += np.where(wing, (-0.10 if side > 0 else 0.03), 0)
		d += 0.05 * stroke([(CX + side * (nw - 0.2), ty - 2.0), (CX + side * (nw + 0.3), ty), (CX + side * (nw - 0.8), ty + 1.2)], 0.6) * (-1.5 if side > 0 else -0.8)
		d -= 0.42 * ellipse(CX + side * (nw * 0.42), ty + 0.9, 1.15 * tip, 0.62)
	d -= 0.16 * gauss(CX + 0.5, ty + 2.2, nw * 0.8, 0.8)  # under-nose shadow
	d -= 0.06 * gauss(CX + 0.3, ty + 4.5, 1.0, 1.6)  # philtrum
	return d


def nose(kind='straight'):
	return _delta_layer(nose_delta(kind))


# ------------------------------------------------------------------ mouth

MOUTHS = {
	# half width, corner lift, upper lip, lower lip, open (teeth), smirk, lip material
	'neutral': (7.2, 0.0, 1.6, 2.3, 0.0, 0.0, 'lip'),
	'smile': (7.8, 1.3, 1.4, 2.2, 0.0, 0.0, 'lip'),
	'grin': (8.4, 1.8, 1.3, 2.0, 1.5, 0.0, 'lip'),
	'stern': (7.0, -0.6, 1.0, 1.6, 0.0, 0.0, 'lip'),
	'full': (7.4, 0.4, 2.1, 2.9, 0.0, 0.0, 'lip'),
	'smirk': (7.4, 0.5, 1.4, 2.1, 0.0, 1.3, 'lip'),
	'lipstick': (7.2, 0.3, 1.8, 2.5, 0.0, 0.0, 'lipstick'),
	'lipstick_smile': (7.8, 1.4, 1.6, 2.3, 1.2, 0.0, 'lipstick'),
	'thin': (6.8, 0.0, 0.7, 1.3, 0.0, 0.0, 'lip'),
}


def mouth(kind='neutral'):
	mw, lift, ul, ll, open_, smirk, mat = MOUTHS[kind]
	ly = Layer()
	y0 = MOUTH_Y
	lc = (CX - mw, y0 - lift + smirk * 0.3)
	rc = (CX + mw, y0 - lift - smirk)
	# mouth line (top of the lower lip)
	line = [lc, (CX - mw * 0.5, y0 + lift * 0.25 + open_ * 0.4), (CX, y0 + lift * 0.35 + open_ * 0.5), (CX + mw * 0.5, y0 + lift * 0.25 + open_ * 0.4 - smirk * 0.4), rc]
	upper_top = [rc, (CX + mw * 0.55, y0 - ul * 0.9 - lift * 0.3 - smirk * 0.5), (CX + 2.0, y0 - ul - 0.6), (CX, y0 - ul + 0.1), (CX - 2.0, y0 - ul - 0.6), (CX - mw * 0.55, y0 - ul * 0.9 - lift * 0.3), lc]
	top_line = [(p[0], p[1] - open_ * 0.5) for p in line]
	upper = catmull(upper_top, closed=False, n=6) + catmull(top_line, closed=False, n=6)
	lower_bot = [rc, (CX + mw * 0.5, y0 + ll * 0.8 + lift * 0.2), (CX, y0 + ll + 0.2 + open_ * 0.6), (CX - mw * 0.5, y0 + ll * 0.8 + lift * 0.2), lc]
	lower = catmull(line, closed=False, n=6) + catmull(lower_bot, closed=False, n=6)
	um = poly(upper, smooth=False)
	lm = poly(lower, smooth=False)
	ref = ref_shade()
	# skin shading around the lips
	d = np.zeros((GH, GW), np.float32)
	d -= 0.13 * gauss(CX + 0.4, y0 + ll + 2.4, mw * 0.6, 0.9)  # under lower lip
	d += 0.06 * gauss(CX - 0.5, y0 - ul - 1.4, 2.4, 0.8)  # top of upper lip
	if lift > 0.8:
		for side in (-1, 1):
			d -= 0.12 * stroke([(CX + side * (mw + 0.4), y0 - lift - 2.2), (CX + side * (mw + 1.3), y0 - lift + 0.2), (CX + side * (mw + 0.6), y0 + 1.6)], 0.8)
	sk = _delta_layer(d, threshold=0.03, base=ref)
	ly.over(sk)
	ly.paint(um, mat, 0.22 + 0.25 * np.clip((Y - (y0 - ul)) / max(ul, 0.5), 0, 1) * (X < CX + 2))
	ly.paint(lm, mat, 0.45 + 0.25 * gauss(CX - 1.2, y0 + ll * 0.45, 2.6, 0.8) - 0.15 * np.clip((X - CX) / mw, 0, 1))
	if open_:
		gap = poly(catmull(top_line, closed=False, n=6) + catmull(list(reversed(line)), closed=False, n=6), smooth=False)
		gap |= stroke(line, open_ * 0.9) & ~lm & ~um
		ly.paint(gap, 'teeth', 0.85 - 0.5 * np.abs((X - CX) / mw) ** 2)
		ly.paint(stroke(line, 0.55) & gap, 'lash', 0.3)
		# hint of tooth separation
		for tx in (-2.6, 0.0, 2.6):
			ly.paint(stroke([(CX + tx, y0 - 0.6 + lift * 0.2), (CX + tx, y0 + 0.6)], 0.3) & gap, 'teeth', 0.35)
	else:
		ly.paint(stroke(line, 0.7), mat, 0.0)
	return ly


# ------------------------------------------------------------------ hair

def _hairline_y(hl, peak=0.0, recess=0.0):
	dx = np.abs(X - CX)
	return hl - peak * np.exp(-(dx / 2.6) ** 2) - recess * np.exp(-((dx - 9.0) / 3.5) ** 2) + 0.012 * dx ** 2


def _flow_texture(seed, part, kind):
	"""Strand texture flowing away from the parting."""
	if kind == 'curly':
		return None
	if kind == 'fine':
		return 0.5 + 0.35 * (rng_noise(seed, 0.35) - 0.5)
	if kind == 'locs':
		t = streaks(seed, 0, length=10, width=1.4)
		return 0.5 + 1.4 * (t - 0.5) + 0.12 * np.sin(Y * 1.6 + np.sin(X * 0.9) * 2)
	if kind == 'up':
		return streaks(seed, 0, length=5, width=0.5)
	px_ = CX if part is None else part
	left = streaks(seed, 60, length=6, width=0.5)
	right = streaks(seed + 1, -60, length=6, width=0.5)
	down = streaks(seed + 2, 0, length=8, width=0.5)
	wl = np.clip((px_ - X) / 6, 0, 1)
	wr = np.clip((X - px_) / 6, 0, 1)
	wd = np.clip((Y - 30) / 14, 0, 1)
	t = (left * wl + right * wr + 0.5 * (1 - wl - wr)) * (1 - wd) + down * wd
	if kind == 'wavy':
		t = t + 0.18 * np.sin(Y * 1.1 + 1.5 * np.sin(X * 0.25))
	return t


def _hair_shade(mask, tex, seed, curl_r=1.3, gloss=0.12, back=False):
	lam = lambert(mask, 5.0, depth=1.1)
	if tex is None:
		c = curls(seed, mask, radius=curl_r)
		s = 0.05 + 0.35 * lam + 0.55 * c
	else:
		s = 0.08 + 0.55 * lam + 0.75 * (tex - 0.5)
		s += gloss * gauss(CX - 7, 25, 6, 3)
	if back:
		s = s * 0.7
	return s


def hair(style, seed=3):
	"""Returns (front, back) layers for a hair style."""
	p = dict(HAIR_STYLES[style])
	front = Layer()
	back = Layer()
	if p.get('none'):
		return front, back
	vol = p.get('vol', 2.0)
	hl = p.get('hl', 28.0)
	part = p.get('part')
	tex_kind = p.get('tex', 'straight')
	length = p.get('length', 0)
	cap = ellipse(CX, 45.5 + p.get('cap_dy', 0), 23.6 + vol, 27.6 + vol) & (Y < 50)
	if p.get('top'):
		cap |= ellipse(*p['top'])
	face_zone = (Y > _hairline_y(hl, p.get('peak', 0), p.get('recess', 0))) & (np.abs(X - CX) < 20.6)
	if p.get('fringe'):
		fy = p['fringe']
		if p.get('swept'):
			edge = fy + 5 * np.clip((X - CX) / 18, -1, 1) * p['swept'] + 0.8 * np.sin(X * 1.7)
		else:
			edge = fy + 0.9 * np.sin(X * 1.9) + 0.02 * (X - CX) ** 2
		face_zone &= Y > edge
	sb = p.get('sideburn', 51.0)
	side = (np.abs(X - CX) >= 20.4) & (np.abs(X - CX) < 23.6) & (Y >= 44) & (Y < sb)
	fm = (cap | side) & ~face_zone
	bm = np.zeros_like(fm)
	if length:
		inner = np.where(Y < 58, 19.8, 19.8 - (Y - 58) * p.get('taper', 0.15))
		outer = 26.0 + vol + p.get('flare', 0) * np.clip((Y - 50) / 30, 0, 1)
		curtain = (np.abs(X - CX) >= inner) & (np.abs(X - CX) < outer) & (Y > 30) & (Y < length - 3)
		for sgn in (-1, 1):
			curtain |= ellipse(CX + sgn * (inner_c := (19.8 + 26.0 + vol) / 2 - 1), length - 4, (26.0 + vol - 19.8) / 2 + 1.5, 4)
		curtain &= ~face_zone | (Y > 70)
		if p.get('front_long', True):
			fm |= curtain & ~((np.abs(X - CX) < inner) & (Y > 30))
		bw = p.get('back_w', 27.0 + vol + p.get('flare', 0))
		bm = (rect(CX - bw, 25, CX + bw, length - 6) | ellipse(CX, length - 7, bw, 6)) & ~fm
	for kind, cx, cy, rx, ry in p.get('extras', []):
		e = ellipse(CX + cx, cy, rx, ry)
		if kind == 'front':
			fm |= e
		else:
			bm |= e & ~fm
	if p.get('afro'):
		bm |= ellipse(CX, p['afro'][0], p['afro'][1], p['afro'][2]) & ~fm
	if p.get('sides_only'):
		fm &= np.abs(X - CX) > p['sides_only']
		fm &= Y > 30
	if p.get('strip'):
		fm = (cap | ellipse(CX, 18, p['strip'], 9)) & (np.abs(X - CX) < p['strip']) & ~face_zone
	if p.get('shaved_sides'):
		shaved = fm & (np.abs(X - CX) > p['shaved_sides']) & (Y > 26)
		fm &= ~shaved
		front.paint(shaved & (rng_noise(seed + 7, 0.3) > 0.45), 'hair', 0.25)
	if p.get('ragged'):
		edge_noise = rng_noise(seed + 5, 0.9)
		fm &= ~((blur(fm, 1.2) < 0.85) & (edge_noise > 0.55))
		bm &= ~((blur(bm, 1.2) < 0.85) & (edge_noise > 0.55))
	tex = _flow_texture(seed, part, tex_kind)
	both = fm | bm
	if tex_kind == 'curly':
		sh = _hair_shade(both, None, seed, p.get('curl', 1.3))
	else:
		sh = _hair_shade(both, tex, seed, gloss=p.get('gloss', 0.12))
	back.paint(bm, 'hair', sh * 0.75)
	front.paint(fm, 'hair', sh)
	if part is not None and tex_kind != 'curly':
		pl = stroke([(part, hl - 1.5), (part + 0.5, hl - 6), (part + 1.5, 19)], 0.6) & fm
		front.paint(pl, 'hair', 0.0)
	# soft shadow where hair meets forehead
	if p.get('braid_crown'):
		arc = stroke([(CX - 22, 34), (CX - 15, 21), (CX, 16.5), (CX + 15, 21), (CX + 22, 34)], 4.2)
		c = curls(seed + 4, arc, radius=1.4)
		front.paint(arc, 'hair', 0.1 + 0.7 * c)
	return front, back


HAIR_STYLES = {
	'bald': {'none': True},
	'side_part': {'vol': 2.4, 'hl': 28.0, 'part': CX - 8, 'sideburn': 52},
	'side_part_r': {'vol': 2.6, 'hl': 27.5, 'part': CX + 8, 'sideburn': 51},
	'buzz': {'vol': 0.8, 'hl': 28.5, 'tex': 'fine', 'sideburn': 50},
	'slick_back': {'vol': 2.0, 'hl': 26.5, 'peak': 1.6, 'tex': 'up', 'sideburn': 51, 'gloss': 0.25},
	'receding': {'vol': 1.6, 'hl': 23.5, 'recess': 4.8, 'tex': 'up', 'sideburn': 50},
	'horseshoe': {'vol': 1.5, 'hl': 20, 'sides_only': 16.5, 'tex': 'fine', 'sideburn': 52},
	'pompadour': {'vol': 2.6, 'hl': 26.5, 'top': (CX - 2, 17.5, 16, 7.5), 'tex': 'up', 'sideburn': 51, 'gloss': 0.2},
	'curly_short': {'vol': 3.0, 'hl': 27.5, 'tex': 'curly', 'curl': 1.0, 'sideburn': 51},
	'afro_short': {'vol': 4.5, 'hl': 27.0, 'tex': 'curly', 'curl': 0.9, 'sideburn': 52},
	'afro': {'vol': 5.0, 'hl': 27.0, 'tex': 'curly', 'curl': 1.2, 'afro': (36, 33, 27), 'sideburn': 52},
	'top_knot': {'vol': 1.4, 'hl': 27.0, 'tex': 'up', 'extras': [('front', 0, 13.5, 6, 5)], 'gloss': 0.2},
	'centre_part': {'vol': 2.2, 'hl': 27.0, 'part': CX, 'sideburn': 50, 'gloss': 0.22},
	'wavy_collar': {'vol': 3.0, 'hl': 27.5, 'part': CX - 7, 'tex': 'wavy', 'length': 66, 'flare': 1.5, 'taper': 0.05},
	'long_straight': {'vol': 2.0, 'hl': 27.0, 'part': CX, 'length': 100, 'taper': 0.12},
	'long_side': {'vol': 2.4, 'hl': 27.0, 'part': CX - 7, 'length': 96, 'taper': 0.1},
	'long_wavy': {'vol': 3.2, 'hl': 27.0, 'part': CX + 6, 'tex': 'wavy', 'length': 98, 'flare': 3, 'taper': 0.08},
	'bob': {'vol': 2.6, 'hl': 27.0, 'part': CX - 6, 'length': 78, 'fringe': 35, 'taper': 0.0, 'flare': 1.0},
	'bob_sleek': {'vol': 2.2, 'hl': 27.0, 'part': CX + 7, 'length': 74, 'taper': 0.0, 'gloss': 0.25},
	'shoulder': {'vol': 2.6, 'hl': 27.0, 'part': CX - 7, 'tex': 'wavy', 'length': 88, 'flare': 2, 'taper': 0.08},
	'fringe_long': {'vol': 2.2, 'hl': 27.0, 'fringe': 36.5, 'length': 98, 'taper': 0.1},
	'pixie': {'vol': 2.2, 'hl': 27.5, 'fringe': 33, 'swept': 1.0, 'sideburn': 49},
	'bun': {'vol': 1.2, 'hl': 27.0, 'part': CX, 'extras': [('back', 0, 13, 8, 6.5)], 'gloss': 0.25, 'sideburn': 48},
	'chignon': {'vol': 1.6, 'hl': 27.0, 'part': CX - 6, 'extras': [('back', 9, 52, 9, 8), ('back', -9, 52, 9, 8)], 'sideburn': 48, 'gloss': 0.2},
	'curly_long': {'vol': 5.0, 'hl': 27.0, 'tex': 'curly', 'curl': 1.2, 'length': 92, 'flare': 6, 'taper': 0.05},
	'braids': {'vol': 2.0, 'hl': 27.0, 'part': CX, 'tex': 'locs', 'length': 104, 'taper': 0.1},
	'locs': {'vol': 3.0, 'hl': 27.5, 'tex': 'locs', 'length': 94, 'flare': 3, 'taper': 0.05},
	'locs_short': {'vol': 3.5, 'hl': 27.5, 'tex': 'locs', 'length': 62, 'flare': 2, 'taper': 0.0, 'front_long': True},
	'sleek_back': {'vol': 1.2, 'hl': 27.0, 'tex': 'up', 'gloss': 0.3, 'sideburn': 47},
	'wild': {'vol': 3.0, 'hl': 22.0, 'recess': 4.0, 'tex': 'curly', 'curl': 1.0, 'ragged': True,
		'extras': [('front', -24, 38, 10, 14), ('front', 24, 38, 10, 14), ('back', 0, 22, 28, 13), ('back', -27, 30, 9, 10), ('back', 27, 30, 9, 10)], 'sideburn': 52},
	'gibson': {'vol': 2.2, 'hl': 26.0, 'top': (CX, 19, 27, 11), 'extras': [('front', 0, 9.5, 8, 5)], 'gloss': 0.15, 'tex': 'up', 'sideburn': 47},
	'victorian': {'vol': 1.4, 'hl': 27.5, 'part': CX, 'extras': [('front', -21.5, 45.5, 3.6, 5.5), ('front', 21.5, 45.5, 3.6, 5.5)], 'gloss': 0.3, 'sideburn': 48},
	'finger_waves': {'vol': 2.0, 'hl': 27.0, 'part': CX - 7, 'tex': 'wavy', 'length': 62, 'taper': 0.0, 'gloss': 0.25},
	'ringlets': {'vol': 2.0, 'hl': 27.0, 'part': CX, 'tex': 'curly', 'curl': 1.4, 'length': 72, 'flare': 2, 'taper': 0.0},
	'braided_crown': {'vol': 1.2, 'hl': 27.5, 'part': CX, 'braid_crown': True, 'gloss': 0.2, 'sideburn': 48},
	'mohawk': {'vol': 1.0, 'hl': 26.0, 'strip': 5.5, 'tex': 'up', 'top': (CX, 14, 6, 8)},
	'undercut': {'vol': 3.0, 'hl': 27.0, 'part': CX - 6, 'shaved_sides': 15.0, 'top': (CX - 2, 18.5, 14, 6), 'gloss': 0.2},
	'messy': {'vol': 3.2, 'hl': 28.0, 'tex': 'up', 'ragged': True, 'fringe': 31, 'swept': -0.6},
	'waves': {'vol': 1.0, 'hl': 28.0, 'tex': 'wavy', 'sideburn': 51, 'gloss': 0.25},
	'fade_curls': {'vol': 3.6, 'hl': 27.5, 'tex': 'curly', 'curl': 0.9, 'shaved_sides': 16.5},
	'military': {'vol': 1.0, 'hl': 27.0, 'tex': 'fine', 'sideburn': 47},
	'thin_comb': {'vol': 0.9, 'hl': 25.0, 'recess': 3.0, 'part': CX - 10, 'sideburn': 50, 'gloss': 0.3},
	'grey_crop': {'vol': 1.4, 'hl': 26.0, 'recess': 2.0, 'tex': 'fine', 'sideburn': 49},
}


# ------------------------------------------------------------------ outfits

def _shoulders(neck=10.5, drop=0.0):
	half = [(0, 84), (neck + 1, 84), (neck + 4, 88 + drop), (20, 92 + drop), (30, 96 + drop), (37, 101 + drop), (41, 108), (43, 125), (0, 125)]
	return poly(mirror(CX, half))


def _cloth_shade(mask, base=0.0):
	lam = lambert(mask, 6.0, depth=0.9)
	return 0.1 + 0.8 * lam + base


def outfit(kind, tie=None):
	"""Clothes on the shoulders. 'cloth' parts are recoloured by the outfit colour."""
	ly = Layer()
	body = _shoulders()
	cs = _cloth_shade(body)
	v_open = poly([(CX - 9.5, 84), (CX + 9.5, 84), (CX + 3.5, 113), (CX - 3.5, 113)], smooth=False)
	if kind in ('suit', 'suit_open', 'double', 'blazer_tee', 'blazer_blouse', 'blazer_shell', 'frock', 'waistcoat', 'military', 'riding'):
		ly.paint(body, 'cloth', cs)
		# lapels
		for side in (-1, 1):
			lap = poly([(CX + side * 8.5, 85), (CX + side * 12.5, 87), (CX + side * 15.5, 96), (CX + side * 11, 99), (CX + side * 4.5, 114), (CX + side * 3.2, 112)], smooth=False)
			if kind != 'military':
				ly.paint(lap, 'cloth', cs + (0.12 if side < 0 else -0.1))
				ly.paint(stroke([(CX + side * 15.5, 96), (CX + side * 11, 99), (CX + side * 4.5, 114)], 0.6), 'cloth', 0.05)
		ly.paint(stroke([(CX, 113), (CX, 125)], 0.7), 'cloth', 0.05)
		shirt = poly([(CX - 9, 83.5), (CX + 9, 83.5), (CX + 4.0, 113), (CX - 4.0, 113)], smooth=False)
		shirt_mat = 'white'
		if kind == 'blazer_tee':
			shirt_mat = 'black' if tie == 'black' else 'white'
		if kind == 'blazer_shell':
			shirt_mat = 'pearl'
		if kind == 'military':
			ly.paint(stroke([(CX, 85), (CX, 125)], 1.2), 'cloth', 0.05)
			for by in (95, 103, 111, 119):
				for side in (-1, 1):
					ly.paint(ellipse(CX + side * 6, by, 1.2, 1.2), 'gold', 0.7)
			for side in (-1, 1):
				ly.paint(poly([(CX + side * 22, 92), (CX + side * 34, 96), (CX + side * 34, 99.5), (CX + side * 22, 95.5)], smooth=False), 'gold', 0.6)
			ly.paint(poly([(CX - 10, 82), (CX + 10, 82), (CX + 10.5, 88), (CX - 10.5, 88)], smooth=False), 'cloth', 0.35)
			ly.paint(stroke([(CX - 10, 82.5), (CX + 10, 82.5)], 0.8), 'gold', 0.8)
			return ly
		ly.paint(shirt & ~(Y > 113), shirt_mat, 0.75 - 0.3 * np.clip((Y - 84) / 30, 0, 1) - 0.15 * (X > CX))
		if kind == 'blazer_blouse':
			for side in (-1, 1):
				col = poly([(CX + side * 1, 85), (CX + side * 9.5, 83), (CX + side * 11, 92), (CX + side * 4, 97)], smooth=False)
				ly.paint(col, 'white', 0.9 if side < 0 else 0.6)
		if kind in ('suit', 'double', 'frock', 'waistcoat', 'suit_open'):
			for side in (-1, 1):
				col = poly([(CX + side * 0.5, 87), (CX + side * 9, 82.5), (CX + side * 10.5, 85), (CX + side * 6.5, 95)], smooth=False)
				ly.paint(col, 'white', 0.95 if side < 0 else 0.6)
		if kind == 'frock':
			# high wing collar and cravat
			ly.paint(poly([(CX - 10.5, 79), (CX + 10.5, 79), (CX + 10, 86), (CX - 10, 86)], smooth=False), 'white', 0.8 - 0.3 * (X > CX))
		if kind == 'waistcoat':
			wc = poly([(CX - 9, 97), (CX + 9, 97), (CX + 7, 125), (CX - 7, 125)], smooth=False) & ~poly([(CX - 4, 96), (CX + 4, 96), (CX, 110)], smooth=False)
			ly.paint(wc, 'tweed', 0.5 + 0.2 * (X < CX))
			ly.paint(stroke([(CX - 6, 114), (CX - 1, 117), (CX + 3, 113)], 0.6), 'gold', 0.8)
			for by in (112, 118):
				ly.paint(ellipse(CX, by, 0.8, 0.8), 'gold', 0.6)
		if kind == 'double':
			for by in (106, 116):
				for side in (-1, 1):
					ly.paint(ellipse(CX + side * 6.5, by, 1.0, 1.0), 'black', 0.5)
		if kind == 'riding':
			ly.paint(poly([(CX - 6, 84), (CX + 6, 84), (CX + 3, 100), (CX - 3, 100)], smooth=False), 'lace', 0.8 - 0.3 * (X > CX))
	elif kind == 'turtleneck':
		ly.paint(body, 'cloth', cs)
		tn = poly([(CX - 11, 74), (CX + 11, 74), (CX + 12.5, 90), (CX - 12.5, 90)])
		ly.paint(tn, 'cloth', _cloth_shade(tn, 0.05))
		for ry in (77, 80.5, 84):
			ly.paint(stroke([(CX - 11, ry), (CX, ry + 1.2), (CX + 11, ry)], 0.5), 'cloth', 0.05)
		return ly
	elif kind in ('tee', 'hoodie', 'sweater', 'polo', 'flannel', 'cardigan', 'dress', 'gown', 'drop_waist', 'mourning', 'wrap', 'blouse_bow', 'lab_coat'):
		ly.paint(body, 'cloth', cs)
		neckline = ellipse(CX, 82, 9.5, 5.5)
		if kind == 'hoodie':
			hood = stroke([(CX - 19, 88), (CX - 12, 84.5), (CX, 87), (CX + 12, 84.5), (CX + 19, 88)], 5.0)
			ly.paint(hood, 'cloth', _cloth_shade(hood, 0.1))
			ly.erase(ellipse(CX, 82, 9, 5))
			for side in (-1, 1):
				ly.paint(stroke([(CX + side * 4, 88), (CX + side * 4.5, 100)], 0.7), 'white', 0.7)
			ly.paint(poly([(CX - 9, 108), (CX + 9, 108), (CX + 11, 125), (CX - 11, 125)], smooth=False) & ~(Y < 108.6), 'cloth', 0.2)
		elif kind == 'polo':
			ly.erase(ellipse(CX, 82, 9, 4.5))
			for side in (-1, 1):
				ly.paint(poly([(CX + side * 1, 85), (CX + side * 10, 81), (CX + side * 12, 88), (CX + side * 5, 92)], smooth=False), 'cloth', 0.55 if side < 0 else 0.3)
			ly.paint(stroke([(CX, 85), (CX, 96)], 0.6), 'cloth', 0.1)
		elif kind == 'flannel':
			ly.erase(ellipse(CX, 82, 9, 4.5))
			check = ((np.floor(X / 3.0) + np.floor(Y / 3.0)) % 2 == 0)
			ly.paint(body & check & ~(Y < 84), 'cloth', cs * 0.6)
			ly.paint(body & (np.abs(((X - CX) % 6) - 3) < 0.4), 'black', 0.4)
			for side in (-1, 1):
				ly.paint(poly([(CX + side * 1, 86), (CX + side * 9.5, 81.5), (CX + side * 11.5, 89), (CX + side * 5, 94)], smooth=False), 'cloth', 0.5 if side < 0 else 0.3)
			ly.paint(poly([(CX - 3, 84), (CX + 3, 84), (CX, 92)], smooth=False), 'white', 0.8)
		elif kind == 'cardigan':
			ly.erase(neckline)
			ly.paint(poly([(CX - 8, 82), (CX + 8, 82), (CX + 4, 113), (CX - 4, 113)], smooth=False) & ~ellipse(CX, 80, 8, 3), 'pearl', 0.7 - 0.2 * (X > CX))
			for by in (100, 108, 116):
				ly.paint(ellipse(CX + 4.5, by, 0.8, 0.8), 'pearl', 0.5)
		elif kind == 'sweater':
			ly.erase(poly([(CX - 9, 82), (CX + 9, 82), (CX, 98)], smooth=False))
			ly.paint(poly([(CX - 8.5, 82), (CX + 8.5, 82), (CX, 97)], smooth=False), 'white', 0.8 - 0.3 * (X > CX))
			ly.paint(stroke([(CX - 9.5, 82), (CX, 98.5), (CX + 9.5, 82)], 1.4, smooth=False), 'cloth', 0.15)
		elif kind in ('dress', 'mourning', 'gown'):
			high = kind != 'gown'
			if high:
				nk = poly([(CX - 10.5, 74), (CX + 10.5, 74), (CX + 11.5, 88), (CX - 11.5, 88)])
				ly.paint(nk, 'cloth', _cloth_shade(nk, 0.05))
				if kind == 'mourning':
					ly.paint(stroke([(CX - 11, 75), (CX + 11, 75)], 1.6) | stroke([(CX - 14, 88), (CX, 92), (CX + 14, 88)], 2.2), 'lace', 0.7)
			else:
				ly.erase(ellipse(CX, 84, 16, 8))
				ly.paint(stroke([(CX - 16.5, 85), (CX - 10, 91.5), (CX, 93), (CX + 10, 91.5), (CX + 16.5, 85)], 1.2), 'cloth', 0.7)
		elif kind == 'drop_waist':
			ly.erase(ellipse(CX, 82, 12, 7))
			ly.paint(stroke([(CX - 12, 83), (CX, 90), (CX + 12, 83)], 1.0), 'cloth', 0.6)
		elif kind == 'wrap':
			ly.erase(poly([(CX - 9.5, 80), (CX + 9.5, 80), (CX + 2, 100), (CX - 2, 100)], smooth=False))
			ly.paint(stroke([(CX + 10, 82), (CX - 2, 100)], 1.6), 'cloth', 0.6)
		elif kind == 'blouse_bow':
			nk = poly([(CX - 10, 77), (CX + 10, 77), (CX + 11, 88), (CX - 11, 88)])
			ly.paint(nk, 'cloth', _cloth_shade(nk, 0.1))
			for side in (-1, 1):
				ly.paint(ellipse(CX + side * 3.5, 87, 3.8, 2.2, angle=side * 15), 'cloth', 0.75 if side < 0 else 0.45)
				ly.paint(stroke([(CX + side * 1, 88), (CX + side * 3.5, 98)], 2.0), 'cloth', 0.5 if side < 0 else 0.3)
			ly.paint(ellipse(CX, 87, 1.4, 1.6), 'cloth', 0.35)
		elif kind == 'lab_coat':
			ly.paint(body, 'white', _cloth_shade(body, 0.1))
			for side in (-1, 1):
				ly.paint(poly([(CX + side * 8.5, 85), (CX + side * 13, 87), (CX + side * 16, 97), (CX + side * 11, 99), (CX + side * 4, 114)], smooth=False), 'white', 0.8 if side < 0 else 0.45)
			ly.paint(poly([(CX - 8.5, 84), (CX + 8.5, 84), (CX + 4, 113), (CX - 4, 113)], smooth=False), 'cloth', 0.3)
		else:  # tee
			ly.erase(neckline)
			ly.paint(stroke([(CX - 9.5, 82), (CX - 5, 86.5), (CX, 87.5), (CX + 5, 86.5), (CX + 9.5, 82)], 1.4), 'cloth', 0.25)
	elif kind == 'stole':
		ly.paint(body, 'cloth', cs)
		ly.erase(ellipse(CX, 83, 12, 6))
		fur = stroke([(CX - 34, 100), (CX - 20, 91), (CX - 10, 92), (CX, 99), (CX + 10, 92), (CX + 20, 91), (CX + 34, 100)], 9.0)
		ly.paint(fur, 'fur', curls(11, fur, radius=1.3) * 0.8 + 0.15)
	# ties
	if tie and kind in ('suit', 'double', 'waistcoat'):
		mat = {'red': 'tie_red', 'blue': 'tie_blue', 'green': 'tie_green', 'gold': 'tie_gold', 'purple': 'tie_purple', 'black': 'black'}.get(tie.split('_')[0], 'tie_red')
		if tie.endswith('bow'):
			bow = poly([(CX - 6, 83.5), (CX - 1, 85.5), (CX + 1, 85.5), (CX + 6, 83.5), (CX + 6, 89.5), (CX + 1, 87.5), (CX - 1, 87.5), (CX - 6, 89.5)], smooth=False)
			ly.paint(bow, mat, 0.6 - 0.3 * (X > CX) + 0.25 * ellipse(CX, 86.5, 1.4, 1.6))
			if tie.startswith('red_dot'):
				pass
		else:
			knot = poly([(CX - 2.4, 86), (CX + 2.4, 86), (CX + 1.6, 90.5), (CX - 1.6, 90.5)], smooth=False)
			blade = poly([(CX - 1.7, 90.5), (CX + 1.7, 90.5), (CX + 3.2, 110), (CX, 113), (CX - 3.2, 110)], smooth=False)
			sh = 0.62 - 0.3 * np.clip((X - CX + 1) / 3, 0, 1)
			ly.paint(knot, mat, sh + 0.1)
			ly.paint(blade, mat, sh)
			if tie.endswith('stripe'):
				ly.paint(blade & (np.abs(((X + Y * 1.0) % 4) - 2) < 0.6), 'white' if mat != 'tie_gold' else 'tie_blue', 0.6)
	if kind == 'frock' and tie:
		cr = poly([(CX - 5, 84), (CX + 5, 84), (CX + 4, 96), (CX, 99), (CX - 4, 96)])
		mat = {'black': 'black', 'white': 'lace', 'red': 'tie_red', 'gold': 'tie_gold'}[tie]
		ly.paint(cr, mat, 0.65 - 0.3 * (X > CX) + 0.15 * gauss(CX - 1, 88, 1.5, 2))
		ly.paint(ellipse(CX, 92, 0.9, 0.9), 'gold', 0.9)
	return ly


# ------------------------------------------------------------------ facial hair

def _jaw_band():
	jaw = poly(head_outline('broad'))
	return jaw


def facial_hair(kind, seed=21):
	ly = Layer()
	if kind == 'none':
		return ly
	jaw = _jaw_band()
	lips = ellipse(CX, MOUTH_Y + 0.6, 7.6, 2.9)
	m = np.zeros((GH, GW), bool)
	tex = 'curly'
	stache_shapes = {
		'chevron': [(CX - 8.5, 66.5), (CX - 4, 62.2), (CX, 62.6), (CX + 4, 62.2), (CX + 8.5, 66.5), (CX + 5, 66.2), (CX, 65.6), (CX - 5, 66.2)],
		'walrus': [(CX - 10, 70), (CX - 6, 62.0), (CX, 62.5), (CX + 6, 62.0), (CX + 10, 70), (CX + 6, 68.5), (CX, 67.8), (CX - 6, 68.5)],
		'pencil': None,
		'handlebar': [(CX - 7, 65.8), (CX - 3, 62.6), (CX, 63.0), (CX + 3, 62.6), (CX + 7, 65.8), (CX + 3.5, 65.4), (CX, 65.0), (CX - 3.5, 65.4)],
		'bushy': [(CX - 10, 68), (CX - 5, 61.6), (CX, 62.2), (CX + 5, 61.6), (CX + 10, 68), (CX + 5, 67.2), (CX, 66.6), (CX - 5, 67.2)],
	}
	stache = None
	parts_ = kind.split('+')
	for k in parts_:
		if k in stache_shapes:
			if k == 'pencil':
				stache = stroke([(CX - 6.5, 65.6), (CX - 3, 64.3), (CX, 64.5), (CX + 3, 64.3), (CX + 6.5, 65.6)], 0.9)
				tex = 'straight'
			else:
				stache = poly(stache_shapes[k])
			if k == 'handlebar':
				for side in (-1, 1):
					stache |= stroke([(CX + side * 6.5, 65.5), (CX + side * 10.5, 65.2), (CX + side * 12.5, 62.0), (CX + side * 11.5, 60.5)], [1.4, 1.1, 0.8, 0.6])
				tex = 'straight'
			m |= stache
		elif k == 'stubble':
			inner = poly(head_outline('narrow'))
			region = inner & (Y > 57) & ~ellipse(CX, MOUTH_Y + 0.4, 7.4, 2.4) & ~ellipse(CX, NOSE_Y + 0.5, 5.5, 2.5)
			region |= inner & (np.abs(X - CX) > 17) & (Y > 45)
			region &= Y < 83
			fade = np.clip((Y - 56) / 9, 0, 1)
			speck = CHECKER & (rng_noise(seed, 0.3) < 0.12 + 0.38 * fade)
			ly.paint(region & speck, 'hair', 0.2)
		elif k == 'goatee':
			m |= poly([(CX - 6, 71.5), (CX + 6, 71.5), (CX + 5, 79), (CX, 83.5), (CX - 5, 79)])
		elif k == 'soul':
			m |= ellipse(CX, 73.3, 1.6, 1.8)
		elif k == 'vandyke':
			m |= poly([(CX - 3.5, 72), (CX + 3.5, 72), (CX + 2.5, 80), (CX, 87), (CX - 2.5, 80)])
		elif k == 'imperial':
			m |= poly([(CX - 2.0, 72.5), (CX + 2.0, 72.5), (CX + 1.2, 82), (CX, 89), (CX - 1.2, 82)])
		elif k in ('beard', 'short_beard', 'long_beard', 'garibaldi'):
			reg = (jaw | ellipse(CX, 76, 18, 11)) & (Y > 52)
			reg |= (np.abs(X - CX) > 19.5) & (np.abs(X - CX) < 24) & (Y > 44) & (Y < 60)
			grow = {'short_beard': 1.0, 'beard': 3.5, 'long_beard': 22, 'garibaldi': 12}[k]
			reg |= ellipse(CX, 80, 15 + (3 if k == 'garibaldi' else 0), 6 + grow) & (Y > 70)
			if k == 'long_beard':
				reg |= poly([(CX - 15, 80), (CX + 15, 80), (CX + 10, 100), (CX + 3, 111), (CX - 3, 111), (CX - 10, 100)])
			cheek_line = 56.5 + 2.5 * np.clip(1 - np.abs(X - CX) / 20, 0, 1)
			reg &= (Y > cheek_line) | (np.abs(X - CX) > 19.5)
			reg &= ~lips
			reg &= ~(ellipse(CX, NOSE_Y + 0.3, 6.5, 3.2))
			m |= reg
			if k in ('beard', 'long_beard', 'garibaldi') and not any(s in stache_shapes for s in parts_):
				m |= poly(stache_shapes['bushy'])
		elif k == 'chin_curtain':
			band = (jaw & ~poly(mirror(CX, [(0, 70), (16, 60), (19.5, 52), (19.5, 40), (0, 40)]))) | ellipse(CX, 81, 13, 5)
			band &= (Y > 50) & ~lips & ~ellipse(CX, 71.5, 6, 2.8)
			band |= (np.abs(X - CX) > 19.5) & (np.abs(X - CX) < 24) & (Y > 44) & (Y < 60)
			m |= band
		elif k == 'chops':
			for side in (-1, 1):
				ch = poly([(CX + side * 20.5, 44), (CX + side * 24, 44), (CX + side * 23.5, 66), (CX + side * 15, 76), (CX + side * 11, 72), (CX + side * 15, 60), (CX + side * 19.5, 54)], smooth=False)
				m |= ch & (jaw | (np.abs(X - CX) > 18))
		elif k == 'sideburns':
			for side in (-1, 1):
				m |= poly([(CX + side * 20.5, 44), (CX + side * 23.6, 44), (CX + side * 23.2, 60), (CX + side * 20.5, 61)], smooth=False)
	if m.any():
		if tex == 'curly':
			sh = 0.05 + 0.35 * lambert(m, 3.0) + 0.5 * curls(seed, m, radius=0.9)
			edge = (blur(m, 0.8) < 0.8) & (rng_noise(seed + 3, 0.4) > 0.6)
			m &= ~edge
		else:
			sh = 0.1 + 0.5 * lambert(m, 2.0) + 0.6 * (streaks(seed, 80, length=2, width=0.4) - 0.5)
		ly.paint(m, 'hair', sh)
	return ly


# ------------------------------------------------------------------ glasses

def glasses(kind):
	ly = Layer()
	if kind == 'none':
		return ly
	ey = EYE_Y + 0.4
	frame = np.zeros((GH, GW), bool)
	lens = np.zeros((GH, GW), bool)
	mat, w = 'black', 1.2
	if kind in ('round', 'round_gold', 'pince_nez'):
		mat = 'gold' if kind != 'round' else 'black'
		w = 0.75
		for side in (-1, 1):
			o = ellipse(CX + side * EYE_DX, ey, 5.4, 5.0)
			i = ellipse(CX + side * EYE_DX, ey, 5.4 - w, 5.0 - w)
			frame |= o & ~i
			lens |= i
		frame |= stroke([(CX - 5.2, ey - 0.8), (CX, ey - 2.0), (CX + 5.2, ey - 0.8)], w)
	elif kind in ('rect', 'rect_thin', 'clear'):
		w = 1.5 if kind == 'rect' else 0.8
		mat = 'black' if kind != 'clear' else 'silver'
		if kind == 'clear':
			w = 1.2
		for side in (-1, 1):
			o = poly([(CX + side * 4.6, ey - 4.0), (CX + side * 16.5, ey - 4.4), (CX + side * 16, ey + 3.4), (CX + side * 5.2, ey + 3.6)])
			i = poly([(CX + side * (4.6 + w), ey - 4.0 + w), (CX + side * (16.5 - w), ey - 4.4 + w), (CX + side * (16 - w), ey + 3.4 - w), (CX + side * (5.2 + w), ey + 3.6 - w)])
			frame |= o & ~i
			lens |= i
		frame |= stroke([(CX - 4.8, ey - 2.4), (CX, ey - 3.0), (CX + 4.8, ey - 2.4)], w * 0.9)
	elif kind in ('horn', 'browline'):
		mat = 'tortoise' if kind == 'horn' else 'black'
		for side in (-1, 1):
			o = poly([(CX + side * 4.5, ey - 4.2), (CX + side * 16.5, ey - 4.6), (CX + side * 15.5, ey + 3.0), (CX + side * 11, ey + 4.6), (CX + side * 6, ey + 3.6)])
			i = poly([(CX + side * 5.8, ey - 2.8), (CX + side * 15.2, ey - 3.0), (CX + side * 14.4, ey + 2.2), (CX + side * 11, ey + 3.6), (CX + side * 6.6, ey + 2.6)])
			if kind == 'browline':
				f = o & ~i
				frame |= f & (Y < ey - 1.5)
				ly.paint(f & (Y >= ey - 1.5), 'silver', 0.6)
			else:
				frame |= o & ~i
			lens |= i
		frame |= stroke([(CX - 4.6, ey - 2.6), (CX, ey - 3.2), (CX + 4.6, ey - 2.6)], 1.4)
	elif kind in ('aviator', 'sunglasses'):
		mat = 'gold' if kind == 'aviator' else 'black'
		for side in (-1, 1):
			o = poly([(CX + side * 4.2, ey - 3.8), (CX + side * 16.5, ey - 4.2), (CX + side * 16, ey + 1.5), (CX + side * 12, ey + 5.6), (CX + side * 6, ey + 4.6)])
			i = poly([(CX + side * 5.0, ey - 3.0), (CX + side * 15.7, ey - 3.4), (CX + side * 15.2, ey + 1.2), (CX + side * 11.8, ey + 4.8), (CX + side * 6.6, ey + 3.8)])
			frame |= o & ~i
			lens |= i
		frame |= stroke([(CX - 4.6, ey - 3.0), (CX, ey - 3.6), (CX + 4.6, ey - 3.0)], 0.8)
		if kind == 'aviator':
			frame |= stroke([(CX - 4.0, ey - 1.6), (CX + 4.0, ey - 1.6)], 0.6)
		w = 0.8
		gl = lens & (np.abs((X - Y * 0.7) % 9 - 4) < 0.7) & (Y < ey)
		ly.paint(lens, 'lens_dark', 0.25 if kind == 'sunglasses' else 0.55)
		ly.paint(gl, 'lens_dark', 0.85)
	elif kind == 'cat_eye':
		for side in (-1, 1):
			o = poly([(CX + side * 4.6, ey - 3.0), (CX + side * 11, ey - 4.2), (CX + side * 18, ey - 6.5), (CX + side * 16, ey + 2.6), (CX + side * 10.5, ey + 4.2), (CX + side * 5.6, ey + 3.0)])
			i = poly([(CX + side * 5.8, ey - 2.0), (CX + side * 11, ey - 2.9), (CX + side * 15.4, ey - 4.0), (CX + side * 14.6, ey + 1.8), (CX + side * 10.5, ey + 3.0), (CX + side * 6.4, ey + 2.2)])
			frame |= o & ~i
			lens |= i
		frame |= stroke([(CX - 4.8, ey - 1.8), (CX, ey - 2.6), (CX + 4.8, ey - 1.8)], 1.1)
	elif kind == 'monocle':
		mat = 'gold'
		o = ellipse(CX + EYE_DX, ey, 5.4, 5.4)
		i = ellipse(CX + EYE_DX, ey, 4.6, 4.6)
		frame = o & ~i
		frame |= stroke([(CX + EYE_DX + 3, ey + 4.6), (CX + 14, 66), (CX + 17, 80), (CX + 15, 95)], 0.5)
		ly.paint(frame, mat, 0.45 + 0.4 * (Y < ey) * (X < CX + EYE_DX))
		ly.paint(i & (np.abs((X - Y) - (CX + EYE_DX - ey) + 2) < 0.7), 'white', 0.9)
		return ly
	if kind != 'pince_nez':
		for side in (-1, 1):
			frame |= stroke([(CX + side * 16.2, ey - 3.2), (CX + side * 20, ey - 2.4), (CX + side * 22.6, ey - 1.5)], w * 0.9)
	if kind == 'pince_nez':
		frame |= stroke([(CX + 15, ey + 1), (CX + 17, 62), (CX + 19, 76), (CX + 17, 92)], 0.45)
	ly.paint(frame, mat, 0.45 + 0.35 * np.clip((ey - Y) / 4, 0, 1) - 0.1 * (X > CX))
	if kind in ('round', 'round_gold', 'rect', 'rect_thin', 'clear', 'horn', 'browline', 'cat_eye', 'pince_nez'):
		gl = lens & (np.abs((X + Y * 0.8) % 10 - 5) < 0.45) & (X < CX - 6) & (Y < ey - 1)
		ly.paint(gl, 'white', 0.95)
	return ly


# ------------------------------------------------------------------ headwear

def headwear(kind, mat=None):
	ly = Layer()
	if kind == 'none':
		return ly

	def solid(mask, m, extra=0.0, radius=5.0):
		ly.paint(mask, m, 0.12 + 0.75 * lambert(mask, radius, depth=1.0) + extra)

	if kind == 'top_hat':
		m = mat or 'felt_black'
		crown = poly([(CX - 15, 0), (CX + 15, 0), (CX + 14, 20), (CX - 14, 20)], smooth=False)
		solid(crown, m, 0.12 * gauss(CX - 7, 10, 2.5, 20))
		ly.paint(rect(CX - 14.2, 15, CX + 14.2, 19.5), 'black' if m != 'felt_grey' else 'felt_black', 0.15)
		brim = ellipse(CX, 21.5, 27, 4.0)
		solid(brim, m, 0.1)
	elif kind == 'bowler':
		m = mat or 'felt_black'
		crown = ellipse(CX, 19, 21, 15) & (Y < 23)
		solid(crown, m, 0.1 * gauss(CX - 8, 10, 4, 4))
		ly.paint(rect(CX - 21, 18.5, CX + 21, 22) & crown, 'black', 0.2)
		solid(ellipse(CX, 23, 27, 3.6), m)
	elif kind == 'homburg' or kind == 'fedora':
		m = mat or 'felt_grey'
		crown = poly([(CX - 19, 22), (CX - 17, 10), (CX - 6, 6), (CX, 9), (CX + 6, 6), (CX + 17, 10), (CX + 19, 22)])
		solid(crown, m)
		ly.paint(rect(CX - 19, 17.5, CX + 19, 22) & crown, 'black', 0.25)
		brim = ellipse(CX, 22.5, 30, 4.0) | (ellipse(CX, 21, 30, 4.4) & (np.abs(X - CX) > 22))
		solid(brim, m, -0.05)
	elif kind == 'flat_cap':
		m = mat or 'tweed'
		cap = ellipse(CX + 1, 22, 26, 12) & (Y < 27)
		solid(cap, m)
		ly.paint(cap & (rng_noise(31, 0.4) > 0.6), m, 0.3)
		peak = ellipse(CX, 27.5, 19, 4) & (Y > 25)
		solid(peak, m, -0.05)
	elif kind == 'beret':
		m = mat or 'felt_black'
		b = ellipse(CX + 4, 19, 26, 10) | ellipse(CX + 18, 22, 10, 6)
		solid(b & (Y < 28), m)
		ly.paint(ellipse(CX + 3, 9, 1.4, 1.6), m, 0.3)
	elif kind == 'hard_hat':
		m = mat or 'yellow'
		dome_ = ellipse(CX, 23, 24, 16) & (Y < 24)
		solid(dome_, m, 0.15 * gauss(CX - 8, 14, 4, 4))
		ly.paint(stroke([(CX, 8), (CX, 23)], 3.0) & dome_, m, 0.75)
		solid(ellipse(CX, 24.5, 28, 3.4), m, -0.05)
	elif kind == 'turban':
		m = mat or 'navy_fixed'
		t = ellipse(CX, 22, 26, 17) & (Y < 33)
		solid(t, m)
		for k in range(4):
			ly.paint(t & stroke([(CX - 26, 30 - k * 4), (CX, 14 + k * 3.5), (CX + 26, 26 - k * 4)], 0.7), m, 0.1)
		ly.paint(poly([(CX - 3, 31), (CX + 3, 31), (CX, 18)], smooth=False), m, 0.55)
	elif kind == 'hijab':
		m = mat or 'rose'
		out = ellipse(CX, 47, 31, 37) | poly([(CX - 30, 60), (CX + 30, 60), (CX + 38, 125), (CX - 38, 125)])
		face = ellipse(CX, 52, 20.5, 31) & (Y > 26)
		hj = out & ~face
		ly.paint(hj, m, 0.15 + 0.7 * lambert(hj, 7, 1.0) + 0.1 * (streaks(41, 20, length=10, width=2) - 0.5))
		ly.paint(stroke([(CX - 20, 52), (CX - 18, 32), (CX, 23), (CX + 18, 32), (CX + 20, 52)], 1.0) & hj, m, 0.1)
	elif kind == 'tiara':
		band = stroke([(CX - 20, 30), (CX - 12, 23), (CX, 21), (CX + 12, 23), (CX + 20, 30)], 1.6)
		ly.paint(band, 'silver', 0.6)
		for k, dx in enumerate((-12, -6, 0, 6, 12)):
			h = 7 if dx == 0 else (5 if abs(dx) == 6 else 3.5)
			y = 21.5 + abs(dx) * 0.12
			pk = poly([(CX + dx - 1.8, y), (CX + dx, y - h), (CX + dx + 1.8, y)], smooth=False)
			ly.paint(pk, 'silver', 0.55 + 0.3 * (dx < 0))
			ly.paint(ellipse(CX + dx, y - h + 0.6, 0.9, 0.9), 'crown_gem' if dx == 0 else 'pearl', 0.8)
	elif kind == 'crown':
		cr = poly([(CX - 15, 22), (CX - 16, 8), (CX - 9, 14), (CX - 4, 4), (CX, 11), (CX + 4, 4), (CX + 9, 14), (CX + 16, 8), (CX + 15, 22)], smooth=False)
		ly.paint(cr, 'gold', 0.25 + 0.7 * lambert(cr, 3))
		ly.paint(ellipse(CX, 17, 1.6, 1.8), 'tie_red', 0.7)
		ly.paint(ellipse(CX - 9, 18, 1.2, 1.4) | ellipse(CX + 9, 18, 1.2, 1.4), 'crown_gem', 0.7)
	elif kind == 'wide_hat':
		m = mat or 'felt_black'
		brim = ellipse(CX + 3, 21, 37, 7) & ~(ellipse(CX + 3, 27, 26, 5) & (Y > 24))
		crown = ellipse(CX + 3, 15, 19, 9) & (Y < 21)
		solid(brim, m)
		solid(crown, m)
		plume = stroke([(CX + 11, 16), (CX + 19, 12.5), (CX + 27, 11.5), (CX + 32, 14)], [2.0, 3.4, 3.4, 1.6])
		ly.paint(plume, 'white', 0.4 + 0.5 * streaks(51, 60, 3, 0.3))
		ly.paint(ellipse(CX + 13, 17, 3.5, 3.5), 'flower_pink', 0.5 + 0.3 * dome(CX + 13, 17, 3.5, 3.5))
	elif kind == 'cloche':
		m = mat or 'felt_brown'
		c = ellipse(CX, 28, 25.5, 20) & (Y < 37)
		c &= ~(ellipse(CX, 42, 21, 9) & (Y > 33))
		solid(c, m)
		ly.paint(c & rect(0, 28, 200, 31), 'black', 0.3)
		ly.paint(ellipse(CX + 15, 29.5, 3, 2.8), 'flower_red', 0.6 + 0.3 * dome(CX + 15, 29.5, 3, 2.8))
	elif kind == 'lace_cap':
		c = ellipse(CX, 24, 22, 10) & (Y < 29)
		ly.paint(c, 'lace', 0.55 + 0.35 * (rng_noise(61, 0.45) > 0.5))
		ly.paint(stroke([(CX - 22, 28), (CX, 32), (CX + 22, 28)], 1.6), 'lace', 0.9)
	elif kind == 'flower_crown':
		for k, dx in enumerate(range(-22, 23, 5)):
			y = 27 - 11 * (1 - (dx / 22) ** 2) + (2 if abs(dx) > 18 else 0)
			fm_ = ['flower_red', 'flower_yellow', 'flower_pink'][k % 3]
			ly.paint(ellipse(CX + dx + 2.5, y + 1, 2.4, 1.2, angle=30), 'leaf', 0.5)
			r = 2.8 if k % 2 == 0 else 2.2
			ly.paint(ellipse(CX + dx, y, r, r), fm_, 0.3 + 0.6 * dome(CX + dx, y, r, r))
			ly.paint(ellipse(CX + dx, y, 0.7, 0.7), 'flower_yellow' if fm_ != 'flower_yellow' else 'cigar', 0.5)
	elif kind == 'beanie':
		m = mat or 'red_cloth'
		b = ellipse(CX, 24, 25.5, 16) & (Y < 31)
		solid(b, m, 0.12 * (np.sin(X * 2.2) > 0.3))
		band = rect(0, 25, 200, 31) & ellipse(CX, 28, 26.5, 10)
		solid(band, m, 0.1 * (np.sin(X * 2.2) > 0))
	elif kind == 'cap':
		m = mat or 'navy_fixed'
		c = ellipse(CX, 24, 24.5, 14) & (Y < 28)
		solid(c, m)
		ly.paint(ellipse(CX, 11, 1.5, 1.2), m, 0.6)
		peak = ellipse(CX, 28.5, 22, 5) & (Y > 26)
		solid(peak, m, -0.08)
		ly.paint(ellipse(CX - 1, 20, 4, 3), 'white', 0.8)
	elif kind == 'bicorne':
		m = mat or 'felt_black'
		hat = poly([(CX - 33, 26), (CX - 20, 12), (CX, 2), (CX + 20, 12), (CX + 33, 26), (CX, 22)])
		solid(hat, m)
		ly.paint(stroke([(CX - 31, 25), (CX, 21), (CX + 31, 25)], 1.0), 'gold', 0.7)
		cock = ellipse(CX + 12, 15, 3, 3)
		ly.paint(cock, 'tie_red', 0.4 + 0.4 * dome(CX + 12, 15, 3, 3))
		ly.paint(ellipse(CX + 12, 15, 1.3, 1.3), 'white', 0.8)
	elif kind == 'deerstalker':
		m = mat or 'tweed'
		c = ellipse(CX, 22, 24.5, 15) & (Y < 28)
		solid(c, m)
		ly.paint(c & (np.abs(((X + Y) % 3) - 1.5) < 0.4), m, 0.2)
		solid(ellipse(CX, 28, 18, 3.5) & (Y > 26), m, -0.05)
	elif kind == 'headphones':
		band = stroke([(CX - 25, 46), (CX - 24, 26), (CX - 12, 14), (CX, 12), (CX + 12, 14), (CX + 24, 26), (CX + 25, 46)], 2.2)
		ly.paint(band, 'black', 0.3 + 0.4 * (X < CX))
		for side in (-1, 1):
			cup = ellipse(CX + side * 25, 50, 4.6, 7.5)
			ly.paint(cup, 'felt_grey', 0.15 + 0.7 * dome(CX + side * 25, 50, 4.6, 7.5))
	return ly


# ------------------------------------------------------------------ jewellery & accessories

def jewellery(kind):
	ly = Layer()
	if kind == 'none':
		return ly
	for k in kind.split('+'):
		for side in (-1, 1):
			ex, ey = CX + side * 23.3, 59.2
			if k == 'pearl_studs':
				ly.paint(ellipse(ex, ey, 1.25, 1.25), 'pearl', 0.3 + 0.6 * dome(ex, ey, 1.25, 1.25))
			elif k == 'gold_studs':
				ly.paint(ellipse(ex, ey, 1.05, 1.05), 'gold', 0.3 + 0.6 * dome(ex, ey, 1.05, 1.05))
			elif k == 'hoops':
				o = ellipse(ex + side * 0.6, ey + 3.6, 2.8, 3.8)
				i = ellipse(ex + side * 0.6, ey + 3.6, 2.0, 3.0)
				ly.paint(o & ~i, 'gold', 0.35 + 0.5 * (X < ex))
			elif k == 'drops':
				ly.paint(stroke([(ex, ey), (ex, ey + 3.5)], 0.5), 'gold', 0.7)
				ly.paint(ellipse(ex, ey + 5.2, 1.4, 2.0), 'pearl', 0.3 + 0.6 * dome(ex, ey + 5.2, 1.4, 2.0))
		if k in ('pearls', 'long_pearls'):
			pts = [(CX - 11.5, 81.5), (CX - 8, 87.5), (CX, 90.5), (CX + 8, 87.5), (CX + 11.5, 81.5)] if k == 'pearls' else [(CX - 11.5, 81.5), (CX - 9, 96), (CX, 108), (CX + 9, 96), (CX + 11.5, 81.5)]
			path = catmull(pts, closed=False, n=40)
			step = 2.0
			acc = 0.0
			last = path[0]
			for p in path:
				acc += ((p[0] - last[0]) ** 2 + (p[1] - last[1]) ** 2) ** 0.5
				last = p
				if acc >= step:
					acc = 0
					ly.paint(ellipse(p[0], p[1], 1.05, 1.05), 'pearl', 0.25 + 0.7 * dome(p[0], p[1], 1.05, 1.05))
		elif k == 'gold_chain':
			ly.paint(stroke([(CX - 10.5, 82), (CX - 6, 88), (CX, 90), (CX + 6, 88), (CX + 10.5, 82)], 0.7), 'gold', 0.7)
			ly.paint(ellipse(CX, 91.5, 1.4, 1.8), 'gold', 0.5 + 0.4 * dome(CX, 91.5, 1.4, 1.8))
		elif k == 'cameo':
			ly.paint(stroke([(CX - 10.5, 79), (CX + 10.5, 79)], 1.5), 'black', 0.4)
			ly.paint(ellipse(CX, 81, 2.6, 3.0), 'gold', 0.7)
			ly.paint(ellipse(CX, 81, 1.8, 2.2), 'pink_shirt', 0.6)
			ly.paint(ellipse(CX + 0.3, 80.6, 0.8, 1.2), 'white', 0.9)
		elif k == 'brooch':
			ly.paint(ellipse(CX - 13, 98, 2.4, 2.4), 'gold', 0.3 + 0.6 * dome(CX - 13, 98, 2.4, 2.4))
			ly.paint(ellipse(CX - 13, 98, 1.0, 1.0), 'crown_gem', 0.7)
	return ly


def accessory(kind):
	ly = Layer()
	if kind == 'cigar':
		c = stroke([(CX + 4, MOUTH_Y + 1), (CX + 11, MOUTH_Y + 3.5), (CX + 15, MOUTH_Y + 5)], [2.2, 2.2, 2.2])
		ly.paint(c, 'cigar', 0.3 + 0.4 * streaks(71, 70, 1, 0.3))
		ly.paint(ellipse(CX + 15.4, MOUTH_Y + 5.2, 1.1, 1.1), 'ember', 0.6)
		ly.paint(stroke([(CX + 7, MOUTH_Y + 2), (CX + 7.5, MOUTH_Y + 2.2)], 2.4), 'gold', 0.6)
	elif kind == 'pipe':
		ly.paint(stroke([(CX + 3, MOUTH_Y + 0.8), (CX + 9, MOUTH_Y + 3), (CX + 12, MOUTH_Y + 5)], 1.1), 'black', 0.3)
		bowl = poly([(CX + 11, MOUTH_Y + 3), (CX + 16, MOUTH_Y + 3), (CX + 15.5, MOUTH_Y + 10), (CX + 12, MOUTH_Y + 10)])
		ly.paint(bowl, 'tortoise', 0.2 + 0.6 * lambert(bowl, 2))
	elif kind == 'flower':
		ly.paint(ellipse(CX - 16, 98, 3.0, 3.0), 'flower_red', 0.3 + 0.6 * dome(CX - 16, 98, 3, 3))
	return ly
