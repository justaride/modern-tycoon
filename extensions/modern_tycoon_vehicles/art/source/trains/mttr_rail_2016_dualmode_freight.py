"""Tinde DM6: fictional dual-mode (electric + diesel) freight locomotive.

Contemporary archetype: a double-cab Bo-Bo freight locomotive with a sloped
cab front, a Signal-yellow warning nose, a Snow-white side stripe on a
company-colour body, and a pantograph on the roof.

SPDX-License-Identifier: GPL-2.0-only
"""
from render import Box

LENGTH_HALF = 3.9
BODY_Z = (2.6, 8.2)
TAPER = (6.0, 0.36)


def body_paint(u, v, z, face):
	if face in ('front_slope', 'back_slope'):
		return 'glass' if z < 7.6 else 'cc'
	if face in ('front', 'back'):
		if 3.4 <= z <= 4.0 and abs(v) > 0.85:
			return 'lamp'
		return 'signal'
	if face == 'top':
		return 'roof'
	if face == 'side':
		end = abs(u)
		if end > 3.15 and 6.0 <= z <= 7.3:
			return 'glass'           # cab side window
		if 4.5 <= z <= 5.6:
			return 'snow'            # Nordic stripe
		if z < 3.3:
			return 'cc_dark'         # skirt
		return 'cc'
	return 'frame'


def bogie(u0, u1):
	return Box((u0, u1), (-1.15, 1.15), (0.0, 1.7), 'bogie')


MODEL = [
	bogie(-3.3, -1.5),
	bogie(1.5, 3.3),
	Box((-LENGTH_HALF, LENGTH_HALF), (-1.5, 1.5), (1.7, BODY_Z[0]), 'frame'),
	Box((-LENGTH_HALF + 0.05, LENGTH_HALF - 0.05), (-1.45, 1.45), BODY_Z, body_paint, taper=TAPER),
	Box((-1.7, 1.7), (-0.9, 0.9), (BODY_Z[1], BODY_Z[1] + 0.6), 'roof_dark'),       # cooling hood
	Box((0.6, 2.2), (-0.15, 0.15), (BODY_Z[1] + 0.6, BODY_Z[1] + 1.3), 'roof_dark'), # pantograph arm
	Box((1.9, 2.3), (-0.7, 0.7), (BODY_Z[1] + 1.2, BODY_Z[1] + 1.4), 'roof_dark'),  # pantograph head
]
