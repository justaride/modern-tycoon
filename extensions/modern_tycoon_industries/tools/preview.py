"""Review images: put an industry's tile sprites together the way OpenTTD draws them.

Used by build_pack.py for the contact sheet and the animated GIF preview of
each industry. Tiles are drawn back to front (by x + y), each tile's ground
first and then its building sprites, with the sprite offsets the game uses.

SPDX-License-Identifier: GPL-2.0-only
"""
from PIL import Image

import render3d

GRASS = (96, 140, 72)


def _paste(canvas, sprite, x, y):
	if sprite is None or sprite.empty:
		return
	rgba = sprite.img.convert('RGBA')
	mask = Image.new('L', sprite.img.size)
	mask.putdata([0 if p == 0 else 255 for p in sprite.img.tobytes()])
	canvas.paste(rgba, (x + sprite.xoff, y + sprite.yoff), mask)


def tile_screen(tx, ty, ox, oy):
	"""Screen position of a tile's north corner on the preview canvas."""
	return ox + 2 * (ty - tx) * 16, oy + (tx + ty) * 16


def scene(tiles, size_x, size_y, sky=200, margin=40, background=GRASS):
	"""tiles: {(tx, ty): [(sprite, (bx, by, bz)), ...]} with ground first; b* = bbox origin in tile units.

	Returns an RGB image of the whole industry on a grass apron.
	"""
	w = (size_x + size_y) * 32 + 2 * margin + 64
	h = (size_x + size_y) * 16 + sky + margin + 32
	ox = margin + 32 + size_x * 32
	oy = sky
	canvas = Image.new('RGB', (w, h), (210, 222, 232))
	grass = render3d.render([render3d.Box((-16.0, (size_x + 1) * 16.0), (-16.0, (size_y + 1) * 16.0), (-0.01, 0.0), 'concrete')], {'concrete': background})
	_paste(canvas, grass, *tile_screen(0, 0, ox, oy))
	order = sorted(tiles, key=lambda t: (t[0] + t[1], t[0]))
	for t in order:
		x, y = tile_screen(t[0], t[1], ox, oy)
		for sprite, (bx, by, bz) in tiles[t]:
			_paste(canvas, sprite, x + 2 * (by - bx), y + (bx + by - bz))
	return canvas


def scale(img, k):
	return img.resize((img.width * k, img.height * k), Image.NEAREST)


def concrete_ground(materials):
	"""Stand-in for the base set's concrete ground tile in review images."""
	return render3d.render([render3d.Box((0.0, 16.0), (0.0, 16.0), (-0.01, 0.0),
			lambda x, y, z, f: 'concrete_dark' if x < 0.5 or y < 0.5 else 'concrete')], materials)
