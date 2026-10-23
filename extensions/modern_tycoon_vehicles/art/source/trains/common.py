"""Shared materials for Modern Tycoon train art (see docs/modern_tycoon/VISUAL_DIRECTION.md).

Values are base colours at mid light; the renderer shades and quantises them
to the DOS palette. 'cc' entries map onto the company-colour remap range.

SPDX-License-Identifier: GPL-2.0-only
"""
MATERIALS = {
	'cc': 'cc',                    # company colour, full range
	'cc_dark': ('cc', 0),          # company colour, darker skirt/edge
	'snow': (236, 238, 240),       # Snow white stripe
	'signal': (232, 184, 16),      # Signal yellow warning front
	'glass': (44, 58, 74),         # Fjord-dark window glass
	'frame': (60, 62, 66),         # underframe
	'bogie': (34, 34, 36),         # bogies and wheels
	'roof': (150, 154, 158),       # Granite roof
	'roof_dark': (96, 100, 104),   # roof equipment
	'lamp': (252, 250, 236),       # head lamps (leading end)
	'tail_lamp': (224, 36, 28),    # tail lamps (trailing end)
	'granite': (150, 154, 158),    # wagon body
	'granite_dark': (108, 112, 116),  # wagon ribs
	'interior': (70, 66, 62),      # open wagon interior
	'cargo': (92, 84, 72),         # generic bulk load
}
