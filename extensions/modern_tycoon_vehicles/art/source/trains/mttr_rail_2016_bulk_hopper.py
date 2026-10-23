"""Tinde bulk hopper: matching open bulk wagon, empty and loaded.

Granite-grey ribbed body with a company-colour top band; the loaded state
shows a generic bulk heap (cargo-specific heaps are a later step).

SPDX-License-Identifier: GPL-2.0-only
"""
from render import Box, Mound

BODY_Z = (2.4, 7.4)


def body_paint(u, v, z, face):
	if face == 'top':
		if abs(v) > 1.1 or abs(u) > 3.4:
			return 'cc'              # rim
		return 'interior'
	if z >= 6.7:
		return 'cc'                  # company-colour top band
	if face == 'side' and (u + 3.7) % 1.5 < 0.3:
		return 'granite_dark'        # vertical ribs
	return 'granite'


def bogie(u0, u1):
	return Box((u0, u1), (-1.15, 1.15), (0.0, 1.7), 'bogie')


EMPTY = [
	bogie(-3.3, -1.6),
	bogie(1.6, 3.3),
	Box((-3.9, 3.9), (-1.4, 1.4), (1.7, BODY_Z[0]), 'frame'),
	Box((-3.75, 3.75), (-1.45, 1.45), BODY_Z, body_paint),
]

LOADED = EMPTY + [Mound(3.35, 1.3, BODY_Z[1] - 0.3, 2.2, 'cargo')]
