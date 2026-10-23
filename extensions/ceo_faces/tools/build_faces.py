"""Build the Modern Tycoon CEO faces.

Renders every face part, then writes:
    media/baseset/mt_faces.grf          sprites + recolour palettes (GRF container v2)
    src/table/mt_company_face.h          face styles for the engine (generated)
    extensions/ceo_faces/generated/contact_sheet.png   random faces for review

Usage: python build_faces.py [--sheet-only]

SPDX-License-Identifier: GPL-2.0-only
"""
import math
import os
import random
import struct
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import materials as M  # noqa: E402
import parts  # noqa: E402
import raster  # noqa: E402
from palette import ROOT  # noqa: E402

PACK = os.path.dirname(HERE)
GRF_OUT = os.path.join(ROOT, 'media', 'baseset', 'mt_faces.grf')
HEADER_OUT = os.path.join(ROOT, 'src', 'table', 'mt_company_face.h')
SHEET_OUT = os.path.join(PACK, 'generated', 'contact_sheet.png')

# ------------------------------------------------------------------ tone lists
SKIN = [k for _, k in M.SKIN_TONES]
HAIR_ALL = [M.HAIR_TONES[n] for n in ('black', 'dark brown', 'brown', 'auburn', 'ginger', 'blonde', 'grey', 'white')]
HAIR_FOUNDER = [M.HAIR_TONES[n] for n in ('black', 'dark brown', 'brown', 'blonde', 'ginger', 'platinum', 'pink', 'teal')]
EYES_MODERN = [M.EYE_TONES[n] for n in ('brown', 'dark brown', 'blue', 'green')]
EYES_OLD = [M.EYE_TONES[n] for n in ('brown', 'blue', 'grey', 'hazel')]


def cloth(*names):
	return [M.CLOTH_TONES[n] for n in names]


# ------------------------------------------------------------------ styles
# Variables are listed in draw order. Kinds:
#   ('recolour', key, string, group, tones, [affected var keys])
#   ('sprite', key, string, [variants])           variants are part specs
#   ('shared', key, of_key, [variants])           hidden layer sharing the bits of another var

def hair_vars(styles):
	return ('shared', 'hair_back', 'hair', [('hair_back', s) for s in styles]), ('sprite', 'hair', 'STR_FACE_HAIR', [('hair_front', s) for s in styles])


HAIR_AFFECTS = ['hair_back', 'brows', 'facial', 'hair']


def style_executive_m():
	hb, hf = hair_vars(['side_part', 'buzz', 'slick_back', 'receding', 'horseshoe', 'bald', 'curly_short', 'afro_short'])
	return [
		('recolour', 'skin', 'STR_FACE_SKIN', 'skin', SKIN, ['head', 'nose', 'mouth']),
		('recolour', 'haircol', 'STR_FACE_HAIR_COLOUR', 'hair', HAIR_ALL, HAIR_AFFECTS),
		('recolour', 'eyecol', 'STR_FACE_EYECOLOUR', 'eye', EYES_MODERN, ['eyes']),
		('recolour', 'clothcol', 'STR_FACE_OUTFIT_COLOUR', 'cloth', cloth('charcoal', 'navy', 'black', 'brown'), ['outfit']),
		hb,
		('sprite', 'head', 'STR_FACE_HEAD', [('head', 'oval', 0), ('head', 'square', 0), ('head', 'broad', 1), ('head', 'long', 0)]),
		('sprite', 'outfit', 'STR_FACE_OUTFIT', [('outfit', 'suit', 'red'), ('outfit', 'suit', 'blue_stripe'), ('outfit', 'suit', 'blue'), ('outfit', 'suit', 'black_bow'),
			('outfit', 'suit_open', None), ('outfit', 'turtleneck', None), ('outfit', 'double', 'gold'), ('outfit', 'sweater', None)]),
		('sprite', 'eyes', 'STR_FACE_EYES', [('eyes', k) for k in ('almond', 'narrow', 'hooded', 'round')]),
		('sprite', 'brows', 'STR_FACE_EYEBROWS', [('brows', k) for k in ('straight', 'thick', 'stern', 'soft')]),
		('sprite', 'nose', 'STR_FACE_NOSE', [('nose', k) for k in ('straight', 'broad', 'aquiline', 'button')]),
		('sprite', 'mouth', 'STR_FACE_MOUTH', [('mouth', k) for k in ('neutral', 'smile', 'grin', 'stern')]),
		('sprite', 'facial', 'STR_FACE_FACIAL_HAIR', [('facial', k) for k in ('none', 'stubble', 'chevron', 'goatee+chevron', 'short_beard', 'beard', 'vandyke+handlebar', 'pencil')]),
		hf,
		('sprite', 'glasses', 'STR_FACE_GLASSES', [('glasses', k) for k in ('none', 'rect', 'round', 'horn')]),
		('sprite', 'headwear', 'STR_FACE_HEADWEAR', [('headwear', 'none', None), ('headwear', 'turban', None)]),
	]


def style_executive_f():
	hb, hf = hair_vars(['long_straight', 'bob', 'bun', 'pixie', 'long_wavy', 'curly_long', 'afro', 'braids',
		'locs', 'chignon', 'long_side', 'shoulder', 'fringe_long', 'bob_sleek', 'sleek_back', 'curly_short'])
	return [
		('recolour', 'skin', 'STR_FACE_SKIN', 'skin', SKIN, ['head', 'nose', 'mouth']),
		('recolour', 'haircol', 'STR_FACE_HAIR_COLOUR', 'hair', HAIR_ALL, HAIR_AFFECTS),
		('recolour', 'eyecol', 'STR_FACE_EYECOLOUR', 'eye', EYES_MODERN, ['eyes']),
		('recolour', 'clothcol', 'STR_FACE_OUTFIT_COLOUR', 'cloth', cloth('navy', 'black', 'burgundy', 'camel'), ['outfit', 'headwear']),
		hb,
		('sprite', 'head', 'STR_FACE_HEAD', [('head', 'oval', 0), ('head', 'heart', 0), ('head', 'soft', 0), ('head', 'narrow', 0)]),
		('sprite', 'outfit', 'STR_FACE_OUTFIT', [('outfit', k, None) for k in ('blazer_blouse', 'blazer_shell', 'dress', 'turtleneck', 'blouse_bow', 'suit_open', 'wrap', 'cardigan')]),
		('sprite', 'eyes', 'STR_FACE_EYES', [('eyes', k) for k in ('lashes', 'lashes_round', 'upturned', 'almond')]),
		('sprite', 'brows', 'STR_FACE_EYEBROWS', [('brows', k) for k in ('arched', 'soft', 'thin', 'high')]),
		('sprite', 'nose', 'STR_FACE_NOSE', [('nose', k) for k in ('small', 'button', 'straight', 'broad')]),
		('sprite', 'mouth', 'STR_FACE_MOUTH', [('mouth', k) for k in ('lipstick', 'lipstick_smile', 'smile', 'full')]),
		hf,
		('sprite', 'jewellery', 'STR_FACE_JEWELLERY', [('jewellery', k) for k in ('none', 'pearl_studs', 'hoops', 'pearls+pearl_studs')]),
		('sprite', 'glasses', 'STR_FACE_GLASSES', [('glasses', k) for k in ('none', 'cat_eye', 'round_gold', 'rect_thin')]),
		('sprite', 'headwear', 'STR_FACE_HEADWEAR', [('headwear', 'none', None), ('headwear', 'hijab', 'cloth')]),
	]


def style_tycoon():
	hb, hf = hair_vars(['centre_part', 'side_part', 'receding', 'horseshoe', 'wild', 'wavy_collar', 'thin_comb', 'bald'])
	return [
		('recolour', 'skin', 'STR_FACE_SKIN', 'skin', SKIN, ['head', 'nose', 'mouth']),
		('recolour', 'haircol', 'STR_FACE_HAIR_COLOUR', 'hair', HAIR_ALL, HAIR_AFFECTS),
		('recolour', 'eyecol', 'STR_FACE_EYECOLOUR', 'eye', EYES_OLD, ['eyes']),
		('recolour', 'clothcol', None, 'cloth', cloth('black'), ['outfit']),
		hb,
		('sprite', 'head', 'STR_FACE_HEAD', [('head', 'oval', 1), ('head', 'heavy', 1), ('head', 'long', 1), ('head', 'broad', 0)]),
		('sprite', 'outfit', 'STR_FACE_OUTFIT', [('outfit', 'frock', 'white'), ('outfit', 'frock', 'black'), ('outfit', 'waistcoat', 'black_bow'), ('outfit', 'military', None)]),
		('sprite', 'eyes', 'STR_FACE_EYES', [('eyes', k) for k in ('almond', 'hooded', 'narrow', 'downturned')]),
		('sprite', 'brows', 'STR_FACE_EYEBROWS', [('brows', k) for k in ('bushy', 'straight', 'stern', 'raised')]),
		('sprite', 'nose', 'STR_FACE_NOSE', [('nose', k) for k in ('aquiline', 'broad', 'hooked', 'straight')]),
		('sprite', 'mouth', 'STR_FACE_MOUTH', [('mouth', k) for k in ('stern', 'neutral', 'smirk', 'smile')]),
		('sprite', 'facial', 'STR_FACE_FACIAL_HAIR', [('facial', k) for k in ('none', 'walrus', 'handlebar', 'chops', 'chops+walrus', 'beard', 'long_beard', 'chin_curtain',
			'vandyke+handlebar', 'imperial+handlebar', 'short_beard', 'chevron', 'garibaldi', 'pencil', 'goatee+chevron', 'sideburns')]),
		hf,
		('sprite', 'glasses', 'STR_FACE_GLASSES', [('glasses', k) for k in ('none', 'monocle', 'pince_nez', 'round_gold')]),
		('sprite', 'headwear', 'STR_FACE_HEADWEAR', [('headwear', k, None) for k in ('none', 'top_hat', 'bowler', 'homburg', 'flat_cap', 'deerstalker', 'turban', 'beret')]),
	]


def style_lady():
	hb, hf = hair_vars(['victorian', 'gibson', 'braided_crown', 'ringlets', 'finger_waves', 'chignon', 'bun', 'bob'])
	return [
		('recolour', 'skin', 'STR_FACE_SKIN', 'skin', SKIN, ['head', 'nose', 'mouth']),
		('recolour', 'haircol', 'STR_FACE_HAIR_COLOUR', 'hair', HAIR_ALL, HAIR_AFFECTS),
		('recolour', 'eyecol', 'STR_FACE_EYECOLOUR', 'eye', EYES_OLD, ['eyes']),
		('recolour', 'clothcol', 'STR_FACE_OUTFIT_COLOUR', 'cloth', cloth('black', 'burgundy', 'navy', 'green'), ['outfit']),
		hb,
		('sprite', 'head', 'STR_FACE_HEAD', [('head', 'oval', 0), ('head', 'heart', 0), ('head', 'soft', 0), ('head', 'long', 1)]),
		('sprite', 'outfit', 'STR_FACE_OUTFIT', [('outfit', k, None) for k in ('dress', 'mourning', 'gown', 'riding', 'drop_waist', 'stole', 'blouse_bow', 'lab_coat')]),
		('sprite', 'eyes', 'STR_FACE_EYES', [('eyes', k) for k in ('lashes', 'almond', 'hooded', 'lashes_round')]),
		('sprite', 'brows', 'STR_FACE_EYEBROWS', [('brows', k) for k in ('arched', 'thin', 'soft', 'high')]),
		('sprite', 'nose', 'STR_FACE_NOSE', [('nose', k) for k in ('straight', 'small', 'aquiline', 'button')]),
		('sprite', 'mouth', 'STR_FACE_MOUTH', [('mouth', k) for k in ('neutral', 'smile', 'lipstick', 'thin')]),
		hf,
		('sprite', 'jewellery', 'STR_FACE_JEWELLERY', [('jewellery', k) for k in ('none', 'drops', 'pearls+pearl_studs', 'cameo')]),
		('sprite', 'glasses', 'STR_FACE_GLASSES', [('glasses', 'none'), ('glasses', 'pince_nez')]),
		('sprite', 'headwear', 'STR_FACE_HEADWEAR', [('headwear', k, None) for k in ('none', 'wide_hat', 'tiara', 'cloche', 'lace_cap', 'flower_crown', 'hijab', 'beret')]),
	]


def style_founder():
	hb, hf = hair_vars(['messy', 'buzz', 'top_knot', 'fade_curls', 'long_straight', 'pixie', 'afro', 'locs_short',
		'bald', 'undercut', 'bob', 'mohawk', 'waves', 'braids', 'side_part_r', 'curly_long'])
	return [
		('recolour', 'skin', 'STR_FACE_SKIN', 'skin', SKIN, ['head', 'nose', 'mouth']),
		('recolour', 'haircol', 'STR_FACE_HAIR_COLOUR', 'hair', HAIR_FOUNDER, HAIR_AFFECTS),
		('recolour', 'eyecol', 'STR_FACE_EYECOLOUR', 'eye', EYES_MODERN, ['eyes']),
		('recolour', 'clothcol', 'STR_FACE_OUTFIT_COLOUR', 'cloth', cloth('light grey', 'black', 'navy', 'red'), ['outfit']),
		hb,
		('sprite', 'head', 'STR_FACE_HEAD', [('head', 'oval', 0), ('head', 'round', 0), ('head', 'heart', 0), ('head', 'square', 0)]),
		('sprite', 'outfit', 'STR_FACE_OUTFIT', [('outfit', 'hoodie', None), ('outfit', 'turtleneck', None), ('outfit', 'tee', None), ('outfit', 'blazer_tee', None),
			('outfit', 'flannel', None), ('outfit', 'polo', None), ('outfit', 'blazer_tee', 'black'), ('outfit', 'cardigan', None)]),
		('sprite', 'eyes', 'STR_FACE_EYES', [('eyes', k) for k in ('almond', 'round', 'monolid', 'smiling')]),
		('sprite', 'brows', 'STR_FACE_EYEBROWS', [('brows', k) for k in ('straight', 'soft', 'thick', 'arched')]),
		('sprite', 'nose', 'STR_FACE_NOSE', [('nose', k) for k in ('straight', 'small', 'broad', 'wide_flat')]),
		('sprite', 'mouth', 'STR_FACE_MOUTH', [('mouth', k) for k in ('smile', 'grin', 'neutral', 'smirk')]),
		('sprite', 'facial', 'STR_FACE_FACIAL_HAIR', [('facial', k) for k in ('none', 'stubble', 'short_beard', 'chevron')]),
		hf,
		('sprite', 'glasses', 'STR_FACE_GLASSES', [('glasses', k) for k in ('none', 'round', 'rect', 'clear')]),
		('sprite', 'headwear', 'STR_FACE_HEADWEAR', [('headwear', 'none', None), ('headwear', 'headphones', None)]),
	]


# Historic look-alikes, each one a finished portrait.
FIGURES = [
	# name, skin, hair colour, eye colour, cloth colour, parts
	('Brunel', 1, 'dark brown', 'brown', 'black', dict(head=('long', 0), hair='centre_part', facial='chops', brows='straight', eyes='narrow', nose='aquiline', mouth='stern', outfit=('frock', 'black'), headwear='top_hat', accessory='cigar')),
	('Lincoln', 2, 'black', 'grey', 'black', dict(head=('long', 1), hair='wavy_collar', facial='chin_curtain', brows='thick', eyes='hooded', nose='long', mouth='thin', outfit=('frock', 'black'))),
	('Einstein', 1, 'white', 'brown', 'light grey', dict(head=('heavy', 1), hair='wild', facial='walrus', brows='bushy', eyes='downturned', nose='broad', mouth='neutral', outfit=('cardigan', None))),
	('Tesla', 2, 'black', 'grey', 'charcoal', dict(head=('long', 0), hair='centre_part', facial='chevron', brows='stern', eyes='almond', nose='straight', mouth='thin', outfit=('suit', 'black'))),
	('Edison', 1, 'grey', 'blue', 'black', dict(head=('square', 1), hair='grey_crop', brows='straight', eyes='hooded', nose='straight', mouth='neutral', outfit=('suit', 'black_bow'))),
	('Carnegie', 1, 'white', 'blue', 'black', dict(head=('round', 1), hair='horseshoe', facial='short_beard+chevron', brows='soft', eyes='almond', nose='button', mouth='neutral', outfit=('waistcoat', 'black_bow'))),
	('Victoria', 0, 'grey', 'blue', 'black', dict(head=('heavy', 1), hair='victorian', brows='thin', eyes='downturned', nose='straight', mouth='stern', outfit=('mourning', None), headwear='tiara', jewellery='drops')),
	('Curie', 1, 'grey', 'grey', 'black', dict(head=('long', 1), hair='chignon', brows='thin', eyes='hooded', nose='straight', mouth='thin', outfit=('dress', None))),
	('Churchill', 0, 'platinum', 'blue', 'charcoal', dict(head=('heavy', 1), hair='horseshoe', brows='thin', eyes='narrow', nose='button', mouth='stern', outfit=('suit', 'blue_bow'), accessory='cigar')),
	('Darwin', 1, 'white', 'grey', 'black', dict(head=('long', 1), hair='horseshoe', facial='long_beard', brows='bushy', eyes='hooded', nose='broad', mouth='neutral', outfit=('frock', 'black'))),
	('Kahlo', 2, 'black', 'dark brown', 'red', dict(head=('oval', 0), hair='braided_crown', brows='unibrow', eyes='almond', nose='straight', mouth='full', outfit=('gown', None), headwear='flower_crown', jewellery='drops+gold_chain')),
	('Jobs', 1, 'grey', 'brown', 'black', dict(head=('long', 0), hair='grey_crop', facial='stubble', brows='straight', eyes='almond', nose='straight', mouth='smile', outfit=('turtleneck', None), glasses='round')),
	('Chanel', 2, 'black', 'dark brown', 'black', dict(head=('heart', 0), hair='finger_waves', brows='arched', eyes='lashes', nose='small', mouth='lipstick', outfit=('drop_waist', None), jewellery='long_pearls+pearl_studs')),
	('Ford', 1, 'grey', 'blue', 'charcoal', dict(head=('long', 1), hair='side_part', brows='straight', eyes='almond', nose='long', mouth='thin', outfit=('suit', 'black'))),
	('Walker', 6, 'black', 'dark brown', 'black', dict(head=('round', 0), hair='gibson', brows='soft', eyes='almond', nose='broad', mouth='neutral', outfit=('dress', None), jewellery='pearls')),
	('Napoleon', 1, 'dark brown', 'grey', 'navy', dict(head=('oval', 0), hair='messy', brows='straight', eyes='almond', nose='aquiline', mouth='stern', outfit=('military', None), headwear='bicorne')),
]


def style_figures():
	return [('sprite', 'figure', 'STR_FACE_FIGURE', [('figure', k) for k in range(len(FIGURES))])]


# Chance in eighths that a random face leaves an optional extra off (value 0).
RARITY = {
	'modern/executive_m': {'glasses': 4, 'headwear': 7, 'facial': 3},
	'modern/executive_f': {'glasses': 4, 'headwear': 6, 'jewellery': 2},
	'modern/tycoon': {'glasses': 5, 'headwear': 3, 'facial': 1},
	'modern/lady': {'glasses': 6, 'headwear': 4, 'jewellery': 2},
	'modern/founder': {'glasses': 4, 'headwear': 6, 'facial': 4},
}

STYLES = [
	('modern/executive_m', style_executive_m),
	('modern/executive_f', style_executive_f),
	('modern/tycoon', style_tycoon),
	('modern/lady', style_lady),
	('modern/founder', style_founder),
	('modern/figures', style_figures),
]

# ------------------------------------------------------------------ rendering

_cache = {}


def render_part(spec):
	"""Render a part spec to a finalised index image (cached)."""
	if spec in _cache:
		return _cache[spec]
	kind = spec[0]
	if kind == 'head':
		ly = parts.head(spec[1], age=spec[2], neck=9.5 if spec[1] in ('heart', 'soft', 'narrow') else 10.5)
	elif kind in ('hair_front', 'hair_back'):
		fr, bk = parts.hair(spec[1])
		_cache[('hair_front', spec[1])] = raster.finalize(fr)
		_cache[('hair_back', spec[1])] = raster.finalize(bk)
		return _cache[spec]
	elif kind == 'outfit':
		ly = parts.outfit(spec[1], spec[2])
	elif kind == 'eyes':
		ly = parts.eyes(spec[1])
	elif kind == 'brows':
		ly = parts.brows(spec[1])
	elif kind == 'nose':
		ly = parts.nose(spec[1])
	elif kind == 'mouth':
		ly = parts.mouth(spec[1])
	elif kind == 'facial':
		ly = parts.facial_hair(spec[1])
	elif kind == 'glasses':
		ly = parts.glasses(spec[1])
	elif kind == 'headwear':
		ly = parts.headwear(spec[1], spec[2])
	elif kind == 'jewellery':
		ly = parts.jewellery(spec[1])
	elif kind == 'accessory':
		ly = parts.accessory(spec[1])
	elif kind == 'figure':
		img = render_figure(FIGURES[spec[1]])
		_cache[spec] = img
		return img
	else:
		raise KeyError(spec)
	img = raster.finalize(ly)
	_cache[spec] = img
	return img


def _rc(group, keys):
	return np.array(M.recolour(group, keys), np.uint8)


def render_figure(fig):
	_, skin, hair_c, eye_c, cloth_c, p = fig
	sk = _rc('skin', SKIN[skin])
	hc = _rc('hair', M.HAIR_TONES[hair_c])
	ec = _rc('eye', M.EYE_TONES[eye_c])
	cc = _rc('cloth', M.CLOTH_TONES[cloth_c])
	ident = np.arange(256, dtype=np.uint8)
	layers = [
		(('hair_back', p['hair']), hc),
		(('head', p['head'][0], p['head'][1]), sk),
		(('outfit', p['outfit'][0], p['outfit'][1]), cc),
		(('eyes', p['eyes']), ec),
		(('brows', p['brows']), hc),
		(('nose', p['nose']), sk),
		(('mouth', p['mouth']), sk),
		(('facial', p.get('facial', 'none')), hc),
		(('hair_front', p['hair']), hc),
		(('jewellery', p.get('jewellery', 'none')), ident),
		(('glasses', p.get('glasses', 'none')), ident),
		(('headwear', p.get('headwear', 'none'), None), cc),
		(('accessory', p.get('accessory', 'none')), ident),
	]
	return raster.stack([table[render_part(spec)] for spec, table in layers])


# ------------------------------------------------------------------ assembly

class Builder:
	def __init__(self):
		self.entries = []  # ('sprite', img) or ('recolour', table)

	def add_sprite(self, img):
		self.entries.append(('sprite', img))
		return len(self.entries) - 1

	def add_recolour(self, table):
		self.entries.append(('recolour', table))
		return len(self.entries) - 1


def bits_for(n):
	return 0 if n <= 1 else math.ceil(math.log2(n))


def build_style(builder, label, fn):
	vars_ = fn()
	keys = [v[1] for v in vars_]
	out = []
	offset = 0
	placed = {}
	position = 0
	for v in vars_:
		kind, key = v[0], v[1]
		if kind == 'recolour':
			_, _, string, group, tones, affects = v
			first = None
			for t in tones:
				i = builder.add_recolour(M.recolour(group, t))
				first = i if first is None else first
			n = len(tones)
			length = bits_for(n)
			mask = 0
			for a in affects:
				if a in keys:
					mask |= 1 << keys.index(a)
			entry = dict(type='Recolour', key=key, offset=offset, length=length, n=n, mask=mask, first=first, string=string)
			placed[key] = (offset, length, n)
			offset += length
		elif kind == 'sprite':
			_, _, string, variants = v
			first = None
			for spec in variants:
				i = builder.add_sprite(render_part(spec))
				first = i if first is None else first
			n = len(variants)
			if key in placed:  # bits reserved by a shared layer drawn earlier
				off, length, n0 = placed[key]
				assert n0 == n
			else:
				off, length = offset, bits_for(n)
				placed[key] = (off, length, n)
				offset += length
			entry = dict(type='Sprite', key=key, offset=off, length=length, n=n, first=first, string=string)
		else:  # shared
			_, _, of, variants = v
			first = None
			for spec in variants:
				i = builder.add_sprite(render_part(spec))
				first = i if first is None else first
			n = len(variants)
			if of not in placed:
				placed[of] = (offset, bits_for(n), n)
				offset += bits_for(n)
			off, length, _ = placed[of]
			entry = dict(type='Sprite', key=key, offset=off, length=length, n=n, first=first, string=None)
		entry['rarity'] = RARITY.get(label, {}).get(key, 0)
		if entry['string']:
			entry['position'] = position
			position += 1
		else:
			entry['position'] = 0
		out.append(entry)
	assert offset <= 32, f'{label} uses {offset} bits'
	return dict(label=label, vars=out, bits=offset)


# ------------------------------------------------------------------ GRF writer

def _lz_literal(data):
	"""Wrap data in the GRF 'LZ77' stream using only literal chunks."""
	out = bytearray()
	for i in range(0, len(data), 0x7F):
		chunk = data[i:i + 0x7F]
		out.append(len(chunk))
		out += chunk
	return bytes(out)


def _encode_sprite(img):
	ys, xs = np.nonzero(img)
	if len(xs) == 0:
		img = np.zeros((1, 1), np.uint8)
		x0 = y0 = 0
	else:
		x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
		img = img[y0:y1, x0:x1]
	h, w = img.shape
	rows = []
	for row in img:
		items = bytearray()
		x = 0
		runs = []
		while x < w:
			if row[x] == 0:
				x += 1
				continue
			start = x
			while x < w and row[x] != 0 and x - start < 0x7F:
				x += 1
			runs.append((start, row[start:x]))
		if not runs:
			items += bytes([0x80, 0])
		for k, (start, px) in enumerate(runs):
			items.append(len(px) | (0x80 if k == len(runs) - 1 else 0))
			items.append(start)
			items += px.tobytes()
		rows.append(bytes(items))
	table = bytearray()
	pos = 2 * h
	for r in rows:
		table += struct.pack('<H', pos)
		pos += len(r)
	data = bytes(table) + b''.join(rows)
	assert len(data) <= 0xFFFF
	return w, h, int(x0), int(y0), data


def write_grf(builder, path):
	data_section = bytearray()
	sprite_section = bytearray()
	sid = 0
	for kind, payload in builder.entries:
		if kind == 'recolour':
			body = bytes([0]) + bytes(payload)
			data_section += struct.pack('<IB', len(body), 0xFF) + body
		else:
			sid += 1
			w, h, xo, yo, raw = _encode_sprite(payload)
			info = 0x04 | 0x08  # palette, chunked transparency
			body = struct.pack('<BBHHhhI', info, 0, h, w, xo, yo, len(raw)) + _lz_literal(raw)
			sprite_section += struct.pack('<II', sid, len(body)) + body
			data_section += struct.pack('<IBI', 4, 0xFD, sid)
	data_section += struct.pack('<I', 0)
	sprite_section += struct.pack('<I', 0)
	header = b'\x00\x00GRF\x82\x0D\x0A\x1A\x0A'
	out = header + struct.pack('<IB', len(data_section) + 1, 0) + data_section + sprite_section
	# The offset counts from just after itself; the compression byte is the first byte it spans.
	with open(path, 'wb') as f:
		f.write(out)


# ------------------------------------------------------------------ header writer

def write_header(styles, count, path):
	L = []
	L.append('/*')
	L.append(' * This file is part of OpenTTD.')
	L.append(' * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.')
	L.append(' * OpenTTD is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.')
	L.append(' * See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with OpenTTD. If not, see <https://www.gnu.org/licenses/old-licenses/gpl-2.0>.')
	L.append(' */')
	L.append('')
	L.append('/** @file mt_company_face.h Modern Tycoon CEO face styles. Generated by extensions/ceo_faces/tools/build_faces.py, do not edit. */')
	L.append('')
	L.append('#ifndef TABLE_MT_COMPANY_FACE_H')
	L.append('#define TABLE_MT_COMPANY_FACE_H')
	L.append('')
	L.append('#include "../company_manager_face.h"')
	L.append('')
	L.append(f'static_assert(MT_FACES_SPRITE_COUNT == {count}, "mt_faces.grf and sprites.h are out of sync");')
	L.append('')
	names = []
	for st in styles:
		name = '_mt_face_' + st['label'].split('/')[1]
		names.append((st['label'], name))
		L.append(f"/** Variables of face style '{st['label']}' ({st['bits']} bits). */")
		L.append(f'static constexpr FaceVar {name}[] = {{')
		for v in st['vars']:
			s = v['string'] or 'STR_NULL'
			if v['type'] == 'Recolour':
				data = f"std::pair<uint64_t, uint64_t>{{0x{v['mask']:X}ULL, SPR_MT_FACES_BASE + {v['first']}}}"
			else:
				data = f"SpriteID{{SPR_MT_FACES_BASE + {v['first']}}}"
			rarity = f", {v['rarity']}" if v['rarity'] else ''
			L.append(f"\t{{FaceVarType::{v['type']}, {v['position']}, {v['offset']}, {v['length']}, {v['n']}, {data}, {s}{rarity}}}, // {v['key']}")
		L.append('};')
		L.append('')
	L.append('/** Modern Tycoon face styles, added after the original ones. */')
	L.append('static FaceSpec _mt_faces[] = {')
	for label, name in names:
		L.append(f'\t{{"{label}", {name}}},')
	L.append('};')
	L.append('')
	L.append('#endif /* TABLE_MT_COMPANY_FACE_H */')
	with open(path, 'w') as f:
		f.write('\n'.join(L) + '\n')


# ------------------------------------------------------------------ contact sheet

def contact_sheet(builder, styles, path, per_style=8, seed=5):
	grad_path = os.path.join(PACK, 'art', 'gradient.png')
	if os.path.exists(grad_path):
		bg = np.array(Image.open(grad_path))
	else:
		bg = np.full((raster.H, raster.W), 0x9A, np.uint8)
	r = random.Random(seed)
	tiles = []
	for st in styles:
		for _ in range(per_style):
			bits = r.getrandbits(32)
			vals = {}
			for v in st['vars']:
				vals[v['key']] = ((bits >> v['offset']) & ((1 << v['length']) - 1)) % v['n']
			for v in st['vars']:
				if v['rarity'] and r.randrange(8) < v['rarity']:
					vals[v['key']] = 0
			pal = {}
			for idx, v in enumerate(st['vars']):
				if v['type'] == 'Recolour':
					table = np.array(builder.entries[v['first'] + vals[v['key']]][1], np.uint8)
					for k in range(64):
						if v['mask'] >> k & 1:
							pal[k] = table
			img = bg.copy()
			for idx, v in enumerate(st['vars']):
				if v['type'] != 'Sprite':
					continue
				part = builder.entries[v['first'] + vals[v['key']]][1]
				if idx in pal:
					part = pal[idx][part]
				m = part != 0
				img[m] = part[m]
			tiles.append(M.to_rgb(img))
	cols = per_style
	rows = len(tiles) // cols
	sheet = Image.new('RGB', (cols * (raster.W + 4), rows * (raster.H + 4)), (24, 24, 24))
	for k, t in enumerate(tiles):
		sheet.paste(Image.fromarray(t), ((k % cols) * (raster.W + 4) + 2, (k // cols) * (raster.H + 4) + 2))
	os.makedirs(os.path.dirname(path), exist_ok=True)
	sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(path)


def main():
	builder = Builder()
	styles = [build_style(builder, label, fn) for label, fn in STYLES]
	count = len(builder.entries)
	contact_sheet(builder, styles, SHEET_OUT)
	if '--sheet-only' in sys.argv:
		return
	write_grf(builder, GRF_OUT)
	write_header(styles, count, HEADER_OUT)
	for st in styles:
		print(f"{st['label']}: {st['bits']} bits")
	print(f'{count} sprites, {os.path.getsize(GRF_OUT)} bytes')


if __name__ == '__main__':
	main()
