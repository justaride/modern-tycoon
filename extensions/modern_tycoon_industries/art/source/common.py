"""Shared materials for Modern Tycoon industry art (see docs/modern_tycoon/VISUAL_DIRECTION.md).

Values are base colours at mid light; the renderer shades and quantises them
to the DOS palette. 'cc' entries map onto the company-colour remap range,
which OpenTTD recolours with each industry's own random colour.
('glow', rgb) entries are emissive (flames, lamps) and are not shaded.

SPDX-License-Identifier: GPL-2.0-only
"""
MATERIALS = {
	'cc': 'cc',
	'cc_dark': ('cc', 0),
	'snow': (236, 238, 240),          # rocket bodies, hall upper walls
	'granite': (150, 154, 158),       # steel, walls
	'granite_dark': (108, 112, 116),  # ribs, doors, roof equipment
	'steel': (128, 132, 138),
	'steel_dark': (78, 82, 88),
	'frame': (60, 62, 66),
	'black': (34, 34, 36),
	'glass': (44, 58, 74),
	'signal': (232, 184, 16),         # safety markings
	'concrete': (176, 172, 160),
	'concrete_dark': (128, 124, 116),
	'asphalt': (84, 84, 88),
	'scorch': (58, 54, 50),
	'soot': (92, 88, 84),
	'rust': (150, 84, 48),
	'ore': (168, 100, 52),            # asteroid ore: rusty orange with dark grains
	'ore_dark': (104, 66, 44),
	'ore_metal': (196, 176, 120),     # metallic glints in the ore
	'pod': (126, 96, 70),             # loaded return pod (ore-stained)
	'tank_white': (222, 224, 220),
	'pipe': (170, 160, 120),
	'water': (60, 96, 140),
	'red': (196, 44, 36),
	'smoke': (196, 196, 192),
	'smoke_light': (226, 226, 222),
	'smoke_dark': (140, 138, 136),
	'vapour': (238, 242, 246),
	'flame_core': ('glow', (252, 252, 220)),
	'flame': ('glow', (252, 204, 64)),
	'flame_outer': ('glow', (236, 120, 24)),
	'flame_blue': ('glow', (140, 180, 252)),
	'lamp': ('glow', (252, 250, 236)),
	'lamp_red': ('glow', (236, 40, 28)),
	'lamp_green': ('glow', (60, 220, 90)),
	'screen': ('glow', (90, 200, 220)),
	'molten': ('glow', (252, 160, 32)),
	'molten_hot': ('glow', (252, 230, 120)),
	'ember': ('glow', (200, 72, 24)),
}


def stripes(a, b, period, width, axis=2):
	"""Paint helper: material b on bands of `width` every `period` along an axis, else a."""
	def paint(x, y, z, face):
		v = (x, y, z)[axis]
		return b if (v % period) < width else a
	return paint
