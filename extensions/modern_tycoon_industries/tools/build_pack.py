"""Generate sprites, NML and review images for Modern Tycoon Space Industry.

Reads data/industries.yaml and the models in art/source/, writes into
generated/ (disposable build output):

    generated/sprites/<industry>_<tile>.png   8bpp sprite strips (DOS palette)
    generated/modern_tycoon_space.nml
    generated/preview_<industry>.png          each industry as the game draws it
    generated/preview_spaceport.gif           one full launch-and-return cycle

Run from the pack directory (build.sh does this).

SPDX-License-Identifier: GPL-2.0-only
"""
import importlib
import os
import sys

import yaml
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PACK = os.path.dirname(HERE)
sys.path[:0] = [HERE, os.path.join(PACK, 'art', 'source')]

import icons  # noqa: E402
import palette as pal  # noqa: E402
import preview  # noqa: E402
from common import MATERIALS  # noqa: E402

GEN = os.path.join(PACK, 'generated')
GROUND_CONCRETE = 'GROUNDSPRITE_CONCRETE'


def pack_strip(sprites, path):
	"""Save sprites side by side (1 px gap) as one 8bpp PNG; return [x, y, w, h, xoff, yoff] rows."""
	total_w = sum(s.img.width for s in sprites) + len(sprites) + 1
	total_h = max(s.img.height for s in sprites) + 2
	sheet = Image.new('P', (total_w, total_h), 0)
	sheet.putpalette(pal.DOS)
	rows, x = [], 1
	for s in sprites:
		sheet.paste(s.img, (x, 1))
		rows.append((x, 1, s.img.width, s.img.height, s.xoff, s.yoff))
		x += s.img.width + 1
	sheet.save(path, transparency=0)
	return rows


def frame_ranges(values):
	"""[(first, last, value)] runs of equal values."""
	runs = []
	for i, v in enumerate(values):
		if runs and runs[-1][2] == v:
			runs[-1][1] = i
		else:
			runs.append([i, i, v])
	return runs


class TileBuild:
	"""Collects the unique sprites and layouts of one industry tile over all its frames."""

	def __init__(self, ind_id, spec):
		self.spec = spec
		self.name = f"{ind_id}_{spec['name']}"
		self.sprites, self.sprite_index = [], {}
		self.layouts, self.layout_index = [], {}
		self.frame_layout = []
		self.preview = []          # per frame: [(Sprite, bbox origin)] for review images
		frames = spec['anim'][0] if spec['anim'] else 1
		for f in range(frames):
			layout, shown = [], []
			for kind, key, producer, origin, extent in spec['layers'](f):
				if producer is None:
					layout.append((kind, None, None, None))
					shown.append((None, None))
					continue
				if key not in self.sprite_index:
					sprite = producer()
					self.sprite_index[key] = None if sprite.empty else len(self.sprites)
					if not sprite.empty:
						self.sprites.append(sprite)
				idx = self.sprite_index[key]
				if idx is None:
					continue
				layout.append((kind, idx, origin, extent))
				shown.append((self.sprites[idx], origin or (0, 0, 0)))
			layout = tuple(layout)
			if layout not in self.layout_index:
				self.layout_index[layout] = len(self.layouts)
				self.layouts.append(layout)
			self.frame_layout.append(self.layout_index[layout])
			self.preview.append(shown)

	def nml(self, tile_numeric_id, accepts):
		png = f'generated/sprites/{self.name}.png'
		rows = pack_strip(self.sprites, os.path.join(PACK, png))
		ss = f'ss_{self.name}'
		out = [f'spriteset({ss}, "{png}") {{\n' + '\n'.join(f'\t[{x}, {y}, {w}, {h}, {xo}, {yo}]' for x, y, w, h, xo, yo in rows) + '\n}']
		for li, layout in enumerate(self.layouts):
			parts = []
			has_ground = False
			for kind, idx, origin, extent in layout:
				if kind == 'ground':
					has_ground = True
					sprite = GROUND_CONCRETE if idx is None else f'{ss}({idx})'
					parts.append(f'\tground {{ sprite: {sprite}; }}')
				else:
					(ox, oy, oz), (ex, ey, ez) = origin, extent
					parts.append(f"""\tbuilding {{
		sprite: {ss}({idx});
		xoffset: {ox}; yoffset: {oy}; zoffset: {oz};
		xextent: {ex}; yextent: {ey}; zextent: {ez};
		recolour_mode: RECOLOUR_REMAP;
		palette: PALETTE_USE_DEFAULT;
	}}""")
			if not has_ground:
				parts.insert(0, f'\tground {{ sprite: {GROUND_CONCRETE}; }}')
			out.append(f'spritelayout sl_{self.name}_{li} {{\n' + '\n'.join(parts) + '\n}')
		graphics = f'sl_{self.name}_0'
		if len(self.layouts) > 1:
			cases = [f'\t{a}..{b}: sl_{self.name}_{v};' if a != b else f'\t{a}: sl_{self.name}_{v};' for a, b, v in frame_ranges(self.frame_layout)]
			out.append(f'switch(FEAT_INDUSTRYTILES, SELF, sw_{self.name}, animation_frame) {{\n' + '\n'.join(cases) + f'\n\tsl_{self.name}_0;\n}}')
			graphics = f'sw_{self.name}'
		anim = ''
		callbacks = ''
		if self.spec['anim']:
			frames, speed = self.spec['anim']
			logic = self.spec.get('logic') or {'loop': True}
			triggers = 'bitmask(ANIM_TRIGGER_INDTILE_RECEIVED_CARGO)' if logic.get('start_on_cargo') else '0'
			anim = f"""
		animation_info: [{'ANIMATION_LOOPING' if logic['loop'] else 'ANIMATION_NON_LOOPING'}, {frames}];
		animation_speed: {speed};
		animation_triggers: {triggers};"""
			if not logic['loop']:
				# Idle frames hold still; cargo arriving at an idle tile starts one run.
				idle = logic['idle_frames']
				idle_cases = '\n\t'.join(f"{i}: return {logic['start_frame']};" for i in idle)
				out.append(f"""// Cargo delivered: start a run if idle, otherwise let the current run finish.
switch(FEAT_INDUSTRYTILES, SELF, sw_{self.name}_control, animation_frame) {{
	{idle_cases}
	return CB_RESULT_DO_NOTHING;
}}

// The idle frame stops the animation (also right after construction).
switch(FEAT_INDUSTRYTILES, SELF, sw_{self.name}_next, animation_frame) {{
	{idle[0]}: return CB_RESULT_STOP_ANIMATION;
	return CB_RESULT_NEXT_FRAME;
}}""")
				callbacks = f'anim_control: sw_{self.name}_control; anim_next_frame: sw_{self.name}_next; '
		acc = ', '.join(f'[{c}, 8]' for c in accepts)
		out.append(f"""item(FEAT_INDUSTRYTILES, tile_{self.name}, {tile_numeric_id}) {{
	property {{
		substitute: 0;
		land_shape_flags: bitmask(LSF_ONLY_ON_FLAT_LAND);
		accepted_cargos: [{acc}];{anim}
	}}
	graphics {{ {callbacks}{graphics}; }}
}}""")
		return '\n\n'.join(out)


def cargo_nml(c, icon_png, icon_row):
	x, y, w, h, xo, yo = icon_row
	s = c['strings']
	return f"""spriteset(ss_icon_{c['label']}, "{icon_png}") {{ [{x}, {y}, {w}, {h}, {xo}, {yo}] }}

item(FEAT_CARGOS, cargo_{c['label']}, {c['slot']}) {{
	property {{
		number: {c['slot']};
		type_name: string({s['name']});
		unit_name: string({s['unit']});
		units_of_cargo: {c['units']};
		items_of_cargo: string({s['quantity']});
		type_abbreviation: string({s['abbrev']});
		sprite: NEW_CARGO_SPRITE;
		weight: {c['weight_t']};
		penalty_lowerbound: {c['penalty_lowerbound']};
		single_penalty_length: {c['single_penalty_length']};
		price_factor: {c['price_factor']};
		station_list_colour: {c['list_colour']};
		cargo_payment_list_colour: {c['list_colour']};
		is_freight: 1;
		cargo_classes: bitmask({', '.join(c['classes'])});
		cargo_label: "{c['label']}";
		town_growth_effect: TOWNGROWTH_NONE;
		town_growth_multiplier: 1.0;
		capacity_multiplier: 1;
	}}
	graphics {{ ss_icon_{c['label']}; }}
}}"""


def industry_nml(ind, tiles, tile_ids):
	layout = ';\n\t'.join(f'{b.spec["pos"][0]}, {b.spec["pos"][1]}: tile_{b.name}' for b in tiles)
	cargo_types = []
	for cin, outs in ind['accepts'].items():
		inner = ', '.join(f'produce_cargo("{cout}", {m})' for cout, m in outs.items())
		cargo_types.append(f'accept_cargo("{cin}", {inner})')
	for cout, rate in ind['base_production'].items():
		cargo_types.append(f'produce_cargo("{cout}", {rate})')
	produced = {c for outs in ind['accepts'].values() for c in outs}
	for cout in sorted(produced - set(ind['base_production'])):
		cargo_types.append(f'produce_cargo("{cout}", 0)')
	return f"""tilelayout layout_{ind['id']} {{
	{layout};
}}

item(FEAT_INDUSTRIES, {ind['id']}, {ind['numeric_id']}) {{
	property {{
		substitute: {ind['substitute']};
		life_type: IND_LIFE_TYPE_PROCESSING;
		layouts: [layout_{ind['id']}];
		cargo_types: [{', '.join(cargo_types)}];
		name: string({ind['name']});
		nearby_station_name: string({ind['station_name']});
		map_colour: {ind['map_colour']};
		fund_cost_multiplier: {ind['fund_cost_multiplier']};
		remove_cost_multiplier: 0;
		prob_random: {ind['prob_map_gen']};
		prob_map_gen: {ind['prob_map_gen']};
		prob_in_game: {ind['prob_in_game']};
		min_cargo_distr: 1;
		spec_flags: bitmask(IND_FLAG_DO_NOT_FORCE_INSTANCE_AT_MAP_GENERATION);
	}}
}}"""


def main():
	data = yaml.safe_load(open(os.path.join(PACK, 'data', 'industries.yaml'), encoding='utf-8'))
	os.makedirs(os.path.join(GEN, 'sprites'), exist_ok=True)
	grf = data['grf']
	labels = ['OIL_', 'GOOD'] + [c['label'] for c in data['cargos']]
	out = [
		'// Generated by tools/build_pack.py from data/industries.yaml. Do not edit.',
		'// SPDX-License-Identifier: GPL-2.0-only',
		f"""grf {{
	grfid: "{grf['grfid']}";
	name: string(STR_GRF_NAME);
	desc: string(STR_GRF_DESC);
	url: string(STR_GRF_URL);
	version: {grf['version']};
	min_compatible_version: {grf['min_compatible_version']};
}}""",
		'if (climate == CLIMATE_TOYLAND) {\n\terror(FATAL, string(STR_ERR_TOYLAND));\n}',
		'cargotable { ' + ', '.join(labels) + ' }',
	]

	icon_sprites = [icons.render_icon(c['icon'], MATERIALS) for c in data['cargos']]
	icon_png = 'generated/sprites/cargo_icons.png'
	icon_rows = pack_strip(icon_sprites, os.path.join(PACK, icon_png))
	for c, row in zip(data['cargos'], icon_rows):
		out.append(cargo_nml(c, icon_png, row))

	tile_id = 0
	report = []
	for ind in data['industries']:
		art = importlib.import_module(ind['art'])
		builds = [TileBuild(ind['id'], spec) for spec in art.tile_specs(MATERIALS)]
		ids = []
		for b in builds:
			out.append(b.nml(tile_id, list(ind['accepts'])))
			ids.append(tile_id)
			tile_id += 1
		out.append(industry_nml(ind, builds, ids))
		n_sprites = sum(len(b.sprites) for b in builds)
		report.append(f"{ind['id']}: {len(builds)} tiles, {n_sprites} sprites, {sum(len(b.layouts) for b in builds)} layouts")
		write_previews(ind, art, builds)

	with open(os.path.join(GEN, 'modern_tycoon_space.nml'), 'w', encoding='utf-8') as f:
		f.write('\n\n'.join(out) + '\n')
	print('\n'.join(report))


def write_previews(ind, art, builds):
	"""A still of the first frame, and an animated GIF in game time for animated industries."""
	size_x = max(b.spec['pos'][0] for b in builds) + 1
	size_y = max(b.spec['pos'][1] for b in builds) + 1
	concrete = preview.concrete_ground(MATERIALS)
	animated = [b for b in builds if b.spec['anim']]
	# Game ticks per frame of each tile (OpenTTD: 2 ** animation_speed), and the GIF time step.
	step = min((2 ** b.spec['anim'][1] for b in animated), default=1) * (2 if any(b.spec['anim'][0] > 64 for b in animated) else 1)
	cycle = max((b.spec['anim'][0] * 2 ** b.spec['anim'][1] for b in animated), default=1)
	stills = []
	for tick in range(0, cycle, step):
		tiles = {}
		for b in builds:
			f = (tick // 2 ** b.spec['anim'][1]) % b.spec['anim'][0] if b.spec['anim'] else 0
			tiles[b.spec['pos']] = [(s if s is not None else concrete, o if o is not None else (0, 0, 0)) for s, o in b.preview[f]]
		stills.append(preview.scene(tiles, size_x, size_y, sky=230 if ind['art'] == 'spaceport' else 120))
	short = ind['art']
	preview.scale(stills[0], 2).save(os.path.join(GEN, f'preview_{short}.png'))
	if len(stills) > 1:
		big = [preview.scale(s, 2) for s in stills]
		big[0].save(os.path.join(GEN, f'preview_{short}.gif'), save_all=True, append_images=big[1:],
				duration=27 * step, loop=0, disposal=1)


if __name__ == '__main__':
	main()
