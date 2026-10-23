"""Materials (palette ramps) and recolour palettes for the faces.

Recolourable materials are drawn with 'label' indices. The game swaps them for
real colours through recolour sprites, so one hair sprite can be black, ginger
or grey. Fixed materials are quantised straight to the DOS palette.

SPDX-License-Identifier: GPL-2.0-only
"""
from palette import RGB, SAFE, nearest, ramp_rgb

# --------------------------------------------------------------- label ramps
LABELS = {
	'skin': list(range(0x46, 0x50)),
	'lip': list(range(0xA2, 0xA8)),
	'hair': list(range(0x68, 0x70)) + [0x78, 0x79],
	'eye': list(range(0x98, 0x9E)),
	'cloth': list(range(0x88, 0x90)) + [0x60, 0x61],
}
_ALL_LABELS = {i for v in LABELS.values() for i in v}
FIXED_ALLOWED = [i for i in SAFE if i not in _ALL_LABELS]

# --------------------------------------------------------------- fixed ramps
FIXED = {
	'white': [(110, 110, 118), (200, 202, 208), (252, 252, 252)],
	'shirt_blue': [(70, 85, 115), (150, 178, 212), (220, 232, 250)],
	'pink_shirt': [(120, 80, 90), (220, 170, 180), (252, 225, 230)],
	'sclera': [(120, 110, 105), (205, 200, 195), (245, 242, 238)],
	'teeth': [(130, 120, 100), (220, 215, 200), (250, 248, 240)],
	'black': [(4, 4, 4), (28, 28, 30), (95, 95, 100)],
	'lash': [(8, 4, 2), (30, 20, 14), (60, 45, 35)],
	'pupil': [(4, 4, 4), (16, 16, 16)],
	'gold': [(90, 60, 10), (190, 150, 40), (252, 236, 130)],
	'silver': [(60, 62, 68), (155, 160, 168), (245, 245, 250)],
	'pearl': [(140, 135, 130), (225, 222, 215), (255, 255, 250)],
	'tortoise': [(30, 15, 5), (100, 55, 20), (180, 120, 60)],
	'tie_red': [(60, 4, 8), (160, 24, 34), (235, 100, 100)],
	'tie_blue': [(10, 20, 55), (40, 75, 150), (120, 160, 225)],
	'tie_green': [(10, 35, 20), (40, 100, 55), (120, 175, 120)],
	'tie_gold': [(80, 55, 10), (175, 135, 35), (240, 210, 110)],
	'tie_purple': [(35, 10, 45), (95, 45, 120), (175, 130, 200)],
	'lipstick': [(70, 5, 15), (165, 25, 45), (235, 105, 120)],
	'felt_black': [(4, 4, 6), (30, 30, 34), (90, 90, 100)],
	'felt_grey': [(40, 40, 42), (110, 110, 112), (185, 185, 190)],
	'felt_brown': [(35, 20, 10), (100, 65, 35), (170, 130, 90)],
	'tweed': [(45, 40, 30), (115, 105, 85), (180, 170, 145)],
	'yellow': [(110, 80, 0), (230, 190, 20), (252, 245, 140)],
	'saffron': [(110, 45, 0), (225, 120, 20), (252, 200, 100)],
	'navy_fixed': [(8, 12, 30), (35, 50, 100), (100, 120, 175)],
	'rose': [(90, 30, 45), (190, 95, 115), (245, 180, 190)],
	'olive': [(35, 40, 15), (100, 105, 50), (170, 170, 110)],
	'teal': [(5, 40, 45), (30, 110, 115), (120, 190, 190)],
	'flower_red': [(90, 5, 10), (210, 35, 40), (252, 130, 120)],
	'flower_yellow': [(120, 80, 0), (240, 190, 30), (252, 245, 150)],
	'flower_pink': [(110, 30, 70), (220, 100, 160), (252, 190, 220)],
	'leaf': [(10, 40, 10), (40, 110, 35), (130, 185, 90)],
	'cigar': [(30, 15, 5), (95, 60, 30), (160, 120, 75)],
	'ember': [(120, 30, 0), (230, 110, 20), (252, 220, 120)],
	'lens_dark': [(4, 4, 8), (25, 28, 40), (90, 100, 130)],
	'lace': [(130, 128, 125), (215, 212, 205), (252, 252, 248)],
	'fur': [(50, 35, 25), (140, 115, 90), (225, 205, 180)],
	'denim': [(15, 25, 50), (60, 85, 130), (140, 165, 200)],
	'red_cloth': [(60, 5, 8), (150, 25, 30), (225, 90, 90)],
	'crown_gem': [(40, 0, 60), (130, 30, 160), (220, 150, 240)],
}

# --------------------------------------------------------------- tones
SKIN_TONES = [
	('porcelain', [(105, 70, 62), (222, 178, 160), (255, 236, 222)]),
	('fair', [(100, 62, 48), (212, 162, 132), (252, 222, 196)]),
	('light olive', [(92, 62, 40), (198, 152, 112), (242, 206, 166)]),
	('tan', [(82, 52, 32), (182, 128, 88), (232, 186, 142)]),
	('olive brown', [(68, 42, 26), (156, 106, 68), (212, 166, 120)]),
	('brown', [(52, 32, 20), (128, 84, 54), (192, 142, 102)]),
	('dark brown', [(36, 22, 14), (100, 62, 40), (160, 114, 82)]),
	('deep', [(24, 14, 10), (72, 44, 30), (128, 90, 68)]),
]

HAIR_TONES = {
	'black': [(6, 5, 5), (34, 30, 30), (95, 88, 85)],
	'dark brown': [(20, 12, 8), (64, 42, 26), (130, 96, 66)],
	'brown': [(36, 22, 10), (104, 68, 38), (175, 132, 86)],
	'auburn': [(36, 12, 6), (124, 52, 26), (196, 112, 66)],
	'ginger': [(66, 28, 6), (182, 92, 36), (245, 170, 92)],
	'blonde': [(86, 62, 28), (196, 160, 94), (252, 234, 172)],
	'grey': [(50, 50, 52), (128, 126, 124), (205, 204, 200)],
	'white': [(110, 110, 116), (200, 200, 204), (255, 255, 255)],
	'pink': [(90, 20, 55), (210, 90, 150), (252, 190, 220)],
	'teal': [(5, 45, 55), (30, 130, 140), (130, 210, 210)],
	'platinum': [(120, 112, 95), (215, 205, 180), (255, 252, 235)],
}

EYE_TONES = {
	'brown': [(28, 14, 4), (100, 60, 25), (165, 115, 60)],
	'dark brown': [(10, 5, 2), (48, 28, 14), (100, 70, 40)],
	'blue': [(10, 25, 60), (60, 110, 175), (150, 190, 235)],
	'green': [(15, 40, 20), (70, 120, 70), (155, 195, 125)],
	'grey': [(40, 45, 50), (110, 120, 130), (190, 198, 205)],
	'hazel': [(40, 28, 8), (120, 100, 45), (185, 170, 95)],
}

CLOTH_TONES = {
	'charcoal': [(16, 16, 18), (66, 68, 72), (132, 134, 140)],
	'navy': [(6, 10, 28), (32, 48, 96), (96, 116, 170)],
	'black': [(3, 3, 4), (26, 26, 30), (82, 82, 92)],
	'brown': [(28, 16, 8), (92, 62, 38), (160, 124, 88)],
	'tweed': [(24, 32, 18), (78, 92, 58), (148, 156, 112)],
	'burgundy': [(34, 4, 10), (108, 24, 40), (182, 82, 96)],
	'camel': [(76, 56, 32), (168, 138, 98), (232, 212, 172)],
	'light grey': [(66, 68, 72), (148, 150, 156), (220, 222, 226)],
	'green': [(8, 30, 18), (34, 90, 56), (110, 170, 120)],
	'red': [(50, 4, 6), (150, 28, 32), (230, 100, 96)],
	'royal blue': [(10, 20, 70), (45, 80, 170), (130, 160, 235)],
	'mustard': [(80, 55, 5), (180, 140, 30), (240, 215, 110)],
	'white': [(110, 110, 116), (205, 206, 210), (252, 252, 252)],
	'plum': [(30, 8, 30), (95, 40, 90), (170, 120, 165)],
}

# --------------------------------------------------------------- tables
MATERIALS = list(LABELS) + list(FIXED)
MAT_ID = {name: i for i, name in enumerate(MATERIALS)}


def _fixed_ramp(keys, n=8):
	out = []
	for rgb in ramp_rgb(keys, n):
		out.append(nearest(rgb, FIXED_ALLOWED))
	return out


RAMPS = [LABELS[m] if m in LABELS else _fixed_ramp(FIXED[m], 3 if len(FIXED[m]) == 2 else 8) for m in MATERIALS]


def lip_keys(skin_keys):
	"""Lip colours derived from a skin tone: redder and a little darker."""
	out = []
	for (r, g, b), f in zip(skin_keys, (0.75, 0.82, 0.9)):
		lum = (r + g + b) / 3
		red = (min(255, lum * 1.15 + 40), lum * 0.55, lum * 0.6)
		out.append(tuple((c * 0.55 + rc * 0.45) * f for c, rc in zip((r, g, b), red)))
	return out


def recolour(group, keys):
	"""256-entry recolour table for one tone of a recolour group."""
	table = list(range(256))
	pairs = {'skin': [('skin', keys), ('lip', lip_keys(keys))],
		'hair': [('hair', keys)], 'eye': [('eye', keys)], 'cloth': [('cloth', keys)]}[group]
	for label, k in pairs:
		idx = LABELS[label]
		for i, rgb in zip(idx, ramp_rgb(k, len(idx))):
			table[i] = nearest(rgb, SAFE)
	return table


def apply(img, tables):
	"""Apply recolour tables (preview only)."""
	import numpy as np
	out = img.copy()
	for t in tables:
		out = np.array(t, np.uint8)[out]
	return out


def to_rgb(img):
	import numpy as np
	pal = np.array(RGB, np.uint8)
	return pal[img]
