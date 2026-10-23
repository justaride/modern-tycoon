"""Tinde DM6: fictional dual-mode (electric + diesel) freight locomotive.

Contemporary archetype: a double-cab Bo-Bo freight locomotive with a sloped
cab front, a Signal-yellow warning nose, a Snow-white side stripe on a
company-colour body, and two pantographs on the roof.

Both ends have a cab, as on the real archetype, so the direction of travel is
shown the way real locomotives show it: white head lamps (low pair plus a top
lamp) only at the leading end (+u), red tail lamps at the trailing end, and
the trailing pantograph raised while the leading one is lowered. OpenTTD
draws a train sprite for the direction the vehicle is moving in, so +u is
always the end in front.

SPDX-License-Identifier: GPL-2.0-only
"""
from render import Box

LENGTH_HALF = 3.9
BODY_Z = (2.6, 8.2)
TAPER = (6.0, 0.36)


def body_paint(u, v, z, face):
	if face in ('front_slope', 'back_slope'):
		return 'glass' if z < 7.6 else 'cc'
	if face == 'front':
		if (3.2 <= z <= 4.2 and abs(v) > 0.7) or (5.2 <= z and abs(v) < 0.4):
			return 'lamp'            # head lamps: leading end only
		return 'signal'
	if face == 'back':
		if 3.2 <= z <= 4.2 and abs(v) > 0.7:
			return 'tail_lamp'       # tail lamps: trailing end
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
	# Leading pantograph, lowered.
	Box((0.7, 2.3), (-0.6, 0.6), (BODY_Z[1] + 0.6, BODY_Z[1] + 0.85), 'roof_dark'),
	# Trailing pantograph, raised: arm and collector head.
	Box((-2.3, -0.7), (-0.15, 0.15), (BODY_Z[1] + 0.6, BODY_Z[1] + 1.8), 'roof_dark'),
	Box((-2.5, -2.0), (-0.8, 0.8), (BODY_Z[1] + 1.6, BODY_Z[1] + 1.9), 'roof_dark'),
]
