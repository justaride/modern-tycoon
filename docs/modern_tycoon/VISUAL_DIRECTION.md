# Modern Tycoon visual direction

Status: working direction, 2026-10-23. It applies to first-party art (see
[VEHICLES_AND_ART.md](VEHICLES_AND_ART.md) for the release contract) and
gives Phase 8 UI work a starting point.

## Identity in one line

**Nordic modern:** calm, functional and readable. Clean panels, one strong
accent per vehicle, honest materials, and a world that still looks like
OpenTTD next to the base set.

Rules of thumb:

- Read first, decorate second. A vehicle must be recognisable at 1x zoom in the 8bpp palette.
- One accent. Company colour carries identity; Signal yellow is for safety (cab fronts), not decoration.
- Light comes from the upper left, as in the base set: top faces brightest, the screen-left side next, the screen-right side darkest.
- No black outlines. Edges come from shading steps between faces.

## Palette

Named colours map to fixed DOS palette indices, so every tool and artist
lands on the same pixels. `tools/palette.py` picks the nearest safe index and
never uses transparency (0), the company-colour ranges or animated colours.

| Name | Role | Base RGB | DOS index |
| --- | --- | --- | --- |
| Company colour | Main body panels, wagon rim bands | remap | 0xC6-0xCD (CC1, 8 shades) |
| Second company colour | Reserved for a later 2CC livery stripe | remap | 0x50-0x57 (CC2), not used yet |
| Snow | Side stripe on locomotives | 236, 238, 240 | 0x0E |
| Granite | Freight wagon bodies, roofs | 150, 154, 158 | 0x09 |
| Granite dark | Wagon ribs, roof equipment | 108, 112, 116 | 0x07 |
| Fjord glass | Windows | 44, 58, 74 | 0x10 |
| Signal yellow | Rail cab fronts (warning) | 232, 184, 16 | 0x42 |
| Frame | Underframes | 60, 62, 66 | 0x04 |
| Bogie | Bogies, wheels, tyres | 34, 34, 36 | 0x02 |
| Pine | Reserved: Nordlys Air livery accent | 36, 84, 56 | 0x61 |
| Aurora teal | Reserved: future accent stripe | 40, 150, 140 | 0x9E |

Shading picks lighter or darker neighbours of the base colour. Adjacent
materials on a vehicle must differ by at least two palette steps so they
survive 1x zoom.

## Company colour

- Company colour covers large, deliberate areas: the body of locomotives, the
  top band and rim of wagons. It never tints glass, wheels or safety yellow.
- Essential state (loaded or empty, direction) never depends on company colour alone.
- Wagons stay mostly Granite so a mixed train reads as one company without
  every wagon shouting.

## Silhouettes per era

| Era | Shape language |
| --- | --- |
| Early industrial, network expansion (to 1945) | Tall chimneys, exposed wheels and rods, rounded cabs; company colour as lining, dark bodies. |
| Mechanisation (1946-1979) | Boxy hoods and bonnets, two-tone bodies, small windows, visible louvres. |
| Global systems (1980-2009) | Long smooth bodies, wide windows, flush doors, single-colour bodies with a stripe. |
| Contemporary (2010-2029) | Sloped cab fronts, Signal-yellow noses, flush glass, one Snow stripe, roof equipment visible. |
| Near future (2030-2050) | Fewer seams, light-bar lamps, battery or hydrogen pods on roof or underframe. |
| Speculative (2051+) | Original silhouettes that state their constraint (for example a guideway or a wing); no decoration that implies capability the stats do not have. |

## Naming

- Only fictional names. No real manufacturers, operators, logos, slogans or class designations.
- Families take short Nordic nature words (Tinde = peak; later Bre, Fjell, Skjer, Vidde).
  Each name is checked against obvious real brands before a public release.
- Model codes describe the design (`DM6`: DM = dual-mode, 6 = design index) and must not copy a real class number.
- Every name ships in English and Norwegian (bokmål).

## The AI rivals

| Rival | Company colour | Look |
| --- | --- | --- |
| Nordlys Air | Dark green (falls back to green) | Airline. Base-set aircraft for now; a future first-party livery adds a Snow stripe and a Pine/Aurora accent. |
| Fjellbanen Gods | Red (falls back to brown) | Rail freight. Already uses Tinde bulk hoppers when the pack is loaded; red bodies with Granite wagons. |

Rivals should be recognisable from a distance by colour plus vehicle type,
so they keep different company colours from each other and from the player's default.

## How first-party art is made

The first pack draws its sprites with code. Each vehicle is a small model of
boxes and curved shapes in `extensions/modern_tycoon_vehicles/art/source/`.
`tools/render.py` projects it with OpenTTD's own isometric formula, shades it
and quantises it to the palette. The model file is the editable source; the
PNG exports are rebuilt by `build.sh` and never edited by hand.

Sprite placement on track follows the base set. Per-direction sprite sizes
and offsets of OpenGFX 8.0 trains were measured from GRF headers
(`tools/measure_anchors.py`, numbers only, no pixels). Our sprites take the
same horizontal centre and bottom edge, which puts the wheels on the rails.

Open points before this method counts as release art:

- Human review of provenance. The model files and renderer were written with
  an AI coding assistant, so the contract's "generated imagery" clause needs a
  maintainer decision (the input is code, not an image model).
- 32bpp and 2x/4x zoom sprites (the renderer can render at higher resolution; not done yet).
- Shadows, animation (pantograph, lights) and cargo-specific heaps.

## UI and rendering (Phase 8 brief)

These need C++ changes in the fork and are not started:

- A Modern Tycoon UI theme: calmer window chrome, Snow/Granite neutrals, company colour as the only strong accent.
- Readable typography defaults at high DPI.
- Market and newspaper windows as native GUI instead of Story Book pages.
- A rendering path that can take headless screenshots: today the null video
  driver forces the null blitter (`src/video/null_v.cpp`), so automated visual QA
  needs either a small driver option or a GUI run.

SPDX-License-Identifier: GPL-2.0-only
