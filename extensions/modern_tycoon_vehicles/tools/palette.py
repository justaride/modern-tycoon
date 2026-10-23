"""OpenTTD DOS palette helpers for 8bpp sprite export.

The palette is taken from the NML compiler (nml.palette, GPL-2.0), because
nmlc only accepts PNGs whose palette matches its own table byte for byte.
It is the same DOS palette as OpenTTD's src/table/palettes.h.

SPDX-License-Identifier: GPL-2.0-only
"""
from nml import palette as nml_palette

DOS = nml_palette.palette_data[0]  # 768 bytes, "DEFAULT"
RGB = [tuple(DOS[i * 3:i * 3 + 3]) for i in range(256)]

TRANSPARENT = 0
# Company colour 1 remap range, dark -> light (8 shades).
CC1 = list(range(0xC6, 0xCE))
# Indices we never pick for ordinary colours: transparent, both company
# colour ranges, and the animated/special tail of the palette.
_EXCLUDED = {0, *range(0x50, 0x58), *CC1, *range(0xD7, 0x100)}
SAFE = [i for i in range(256) if i not in _EXCLUDED]


def nearest(rgb):
    """Closest safe palette index to an (r, g, b) colour (weighted RGB distance)."""
    r, g, b = rgb
    best, best_d = None, None
    for i in SAFE:
        pr, pg, pb = RGB[i]
        d = 2 * (pr - r) ** 2 + 4 * (pg - g) ** 2 + 3 * (pb - b) ** 2
        if best_d is None or d < best_d:
            best, best_d = i, d
    return best
