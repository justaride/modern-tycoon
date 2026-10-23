"""DOS palette, read from OpenTTD's own src/table/palettes.h, plus colour helpers.

SPDX-License-Identifier: GPL-2.0-only
"""
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))


def _load_dos_palette():
	with open(os.path.join(ROOT, 'src', 'table', 'palettes.h')) as f:
		text = f.read()
	block = text[text.index('static const Palette _palette'):]
	block = block[:block.index('\n};')]
	rgb = [tuple(int(v) for v in m) for m in re.findall(r'M\(\s*(\d+),\s*(\d+),\s*(\d+)\)', block)]
	assert len(rgb) == 255, len(rgb)
	return [(0, 0, 255)] + rgb  # index 0 is transparent ("magic blue")


RGB = _load_dos_palette()
FLAT = [c for rgb in RGB for c in rgb]

# Never use: transparent, company colour remap ranges and the animated tail.
_EXCLUDED = {0, *range(0xC6, 0xCE), *range(0x50, 0x58), *range(0xD7, 0x100)}
SAFE = [i for i in range(256) if i not in _EXCLUDED]


def nearest(rgb, allowed):
	"""Closest palette index from 'allowed' to an (r, g, b) colour (weighted RGB distance)."""
	r, g, b = rgb
	best, best_d = None, None
	for i in allowed:
		pr, pg, pb = RGB[i]
		d = 3 * (pr - r) ** 2 + 4 * (pg - g) ** 2 + 2 * (pb - b) ** 2
		if best_d is None or d < best_d:
			best, best_d = i, d
	return best


def lerp(a, b, t):
	return tuple(a[k] + (b[k] - a[k]) * t for k in range(3))


def ramp_rgb(keys, n):
	"""n colours along a piecewise-linear ramp through the key colours (dark -> light)."""
	out = []
	for i in range(n):
		t = i / (n - 1) * (len(keys) - 1)
		k = min(int(t), len(keys) - 2)
		out.append(lerp(keys[k], keys[k + 1], t - k))
	return out
