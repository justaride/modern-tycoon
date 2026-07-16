# Vehicle and art implementation contract

## Status and purpose

This document is the release contract for a first-party Modern Tycoon vehicle family. It defines what may be built, how it must behave, and what evidence is required before it is presented as finished.

No vehicle sprites, sounds, models, or distributable NewGRF binaries are implemented by this document. The names and roster below are design targets, not claims that assets already exist.

The family extends OpenTTD through NML/NewGRF. It must not make the native game depend on a content pack, silently replace third-party vehicles, or remove the upstream Classic experience.

## Product modes

The content is split into four independently selectable NewGRFs so players can mix modes without installing a monolith:

| Pack | Stable GRF ID | Scope |
| --- | --- | --- |
| Modern Tycoon Trains | `MTTR` | Rail locomotives, multiple units, metros, trams, wagons, and future guided vehicles. |
| Modern Tycoon Road | `MTRV` | Buses, coaches, vans, trucks, trolleybuses, and specialist road vehicles. |
| Modern Tycoon Ships | `MTSH` | Ferries, river and coastal craft, bulk, container, tanker, tug/barge, and future vessels. |
| Modern Tycoon Aircraft | `MTAR` | Airships, piston aircraft, helicopters, turboprops, jets, cargo aircraft, and future aircraft. |

IDs are reserved project identifiers and must be checked against the live NewGRF registry before the first public release. Once a public save can contain an ID, neither the GRF ID nor an internal vehicle ID may be reused for a different object.

Each pack exposes the same parameters where the feature is meaningful:

| Parameter | Values | Default | Contract |
| --- | --- | --- | --- |
| `roster_scope` | `grounded`, `extended`, `full_future` | `extended` | `grounded` introduces nothing after 2050; `extended` includes 2051-2100; `full_future` enables all approved speculative vehicles. |
| `roster_density` | `compact`, `standard`, `complete` | `standard` | Removes overlapping roles without changing the stats of vehicles that remain. |
| `balance` | `classic`, `modern`, `simulation` | `modern` | Applies documented cost and capacity multipliers only; it does not change visual identity. |
| `vehicle_names` | `original`, `licensed_real` | `original` | Real product names appear only when the asset manifest records explicit approval. |
| `future_start_year` | `2051`-`2100` | `2051` | May delay fictional introductions; it may never move them earlier than 2051. |
| `visual_detail` | `essential`, `standard`, `animated` | `standard` | Disables optional overlays or animation without changing simulation properties. |

The Modern Tycoon game presets select recommended parameter values, but the NewGRFs remain ordinary explicit content choices. Classic does not auto-enable them.

## Era and authenticity boundary

Every vehicle has exactly one declared era and evidence class:

| Era | Years | Content rule |
| --- | --- | --- |
| Early industrial | 1830-1889 | Historically grounded technology and operating roles. |
| Network expansion | 1890-1945 | Historically grounded steam, electric, road, marine, and early aviation archetypes. |
| Mechanisation | 1946-1979 | Historically grounded dieselisation, electrification, mass motoring, and jet transition. |
| Global systems | 1980-2009 | Historically grounded intermodal, high-speed, wide-body, and modern transit archetypes. |
| Contemporary | 2010-2029 | Existing technology and announced production classes, verified against dated sources. |
| Near future | 2030-2050 | Grounded projections based on demonstrated prototypes, published standards, or defensible engineering trends. |
| Speculative | 2051 onward | Clearly fictional vehicles with original names, liveries, silhouettes, and written design premises. |

The year 2050 is a hard content boundary. A post-2050 vehicle may use plausible engineering, but it must not be described as historical, real, announced, or manufacturer-backed. A pre-2051 vehicle cannot be invented merely to fill a balance gap: it needs a sourced archetype or moves to the speculative era.

An archetype records capability and role rather than copying a particular branded product. Examples are `four-axle mixed-traffic diesel`, `single-deck intercity EMU`, and `twin-aisle long-haul jet`, not a manufacturer model number.

## Naming, likeness, and legal boundary

The default release uses original names and project liveries. A historically grounded vehicle may follow facts such as wheel arrangement, power source, capacity range, service era, and broad body type while remaining an original illustration.

The following require explicit rights review and an asset-manifest decision before release:

- manufacturer, operator, product, or service names;
- logos, badges, route brands, typefaces, slogans, and recognisable commercial liveries;
- exact industrial-design copies where current design rights may apply;
- traced photographs, drawings, models, game sprites, or promotional renders;
- sounds extracted from recordings whose redistribution terms are unknown.

Technical facts and public specifications may inform balance. Reference images are not source art. Artists must build an original sprite from licensed source material, self-made sketches/models, or permissively licensed references and record the method. Original Transport Tycoon Deluxe graphics are never accepted as input or redistributed.

Generated imagery is not accepted into the first-party asset tree by default. A future exception requires documented model/tool provenance, rights compatible with GPLv2 distribution, and a human-authored source file sufficient to revise the work.

## Vehicle record and balance rules

The source of truth is one machine-readable record per vehicle. The generated NML and player-facing tables must agree with it.

Required fields:

```yaml
id: mttr_rail_1962_mixed_diesel
pack: trains
mode: rail
era: mechanisation
evidence_class: historical_archetype
intro_year: 1962
retire_year: 1992
role: mixed_traffic
traction: diesel
speed_kmh: 120
power_kw: 1450
tractive_effort_kn: 255
empty_mass_t: 108
capacity: 0
purchase_cost_index: 100
running_cost_index: 100
reliability_class: proven
cargo_labels: []
spriteset: mttr_rail_1962_mixed_diesel
asset_manifest: MT-A-000123
sources:
  - MT-S-000456
```

The exact schema is versioned before implementation. Integer values and rational multipliers are used when generating NML; platform-dependent floating-point calculations may not affect gameplay.

### Introduction and retirement

- Dates use a January 1 introduction unless a sourced month materially matters.
- Random introduction variation uses OpenTTD/NewGRF behavior consistently across the family; no vehicle-specific hidden randomness is added.
- Standard roster overlap is 8-20 years within a role so replacement is a choice rather than a cliff.
- Compact mode retains at least one generally available vehicle for every supported mode and essential cargo class.
- A retirement date removes new purchases only. Existing vehicles remain operable under normal OpenTTD rules.
- There must be no unintended technology gap from the first supported year through 2050. Post-2050 continuity depends on `roster_scope`.
- A speculative vehicle delayed by `future_start_year` keeps its relative place in the future roster; it does not rewrite historical dates.

### Stats and progression

Stats are balanced by role, not by making every successor strictly superior:

- speed and capacity trade against purchase cost, running cost, mass, loading time, and infrastructure needs;
- specialist freight vehicles outperform generalists only for their declared cargo or operating context;
- efficiency generally improves across generations, while early adoption may carry higher price or lower reliability;
- metro, tram, feeder, regional, intercity, express, heavy-haul, and specialist roles retain distinct uses;
- fictional vehicles extrapolate bounded trends and must state their new constraint; no zero-cost, zero-emission, instant-loading, infinite-range, or universally best vehicle is permitted;
- visual-only variants share gameplay stats unless a documented operational difference justifies a separate vehicle;
- capacities stay legible relative to OpenTTD tile and station scale instead of claiming literal one-to-one real-world dimensions.

The balance generator derives purchase and running costs from versioned mode coefficients. Hand-tuned exceptions require a reason in the vehicle record. Every balance change emits a before/after roster report and is treated as savegame-visible gameplay change.

### Reliability and availability

Reliability classes are `experimental`, `early_adopter`, `proven`, and `mature`. They map to documented NML reliability parameters. Near-future prototypes normally begin as `early_adopter`; speculative vehicles cannot use fiction as a reason for perfect reliability.

If the game has breakdowns disabled, the class remains metadata and must not create a private penalty callback.

### Cargo and infrastructure

- Use cargo labels, railtype labels, and road/tram type labels, never numeric slots owned by another NewGRF.
- The baseline roster supports vanilla cargo labels and standard OpenTTD rail/road infrastructure.
- Extended cargo support is an explicit compatibility table, not a blanket claim of support for every economy set.
- Unknown cargos are rejected or handled by a documented generic refit class; they are never silently assigned passenger or mail graphics.
- Livery and loading-state callbacks may depend on cargo label, fill level, direction, and declared subtype only.
- The first release adds vehicles; it does not override other sets' engines or require a new railtype, roadtype, airport, or industry GRF.

## Visual production standard

### Coordinate and lighting contract

- All sprites use OpenTTD's isometric view and the direction count required by the vehicle feature.
- The canonical light comes from the upper-left/northwest visual direction, matching the selected first-party base-set reference sheet.
- Scale is judged against vanilla/OpenGFX infrastructure, depot doors, platforms, road lanes, and comparable vehicles. Literal dimensions yield to a coherent world scale.
- Each vehicle has a declared ground/contact anchor. The same anchor is preserved at every zoom level and in loaded, articulated, animated, and company-colour variants.
- Shadows are part of the art contract: direction, opacity, and footprint remain consistent and may not imply a different bounding box.
- Transparent padding is minimal and stable. Sprite offsets are reviewed in motion, not accepted from a static sheet alone.

### Required sprite tiers

Every released vehicle includes:

1. a readable 8-bpp palette fallback at normal zoom;
2. a 32-bpp normal-zoom sprite using the same silhouette and anchor;
3. authored 2x and 4x extra-zoom sprites where the target OpenTTD sprite feature supports them;
4. company-colour behavior that remains recognisable in both palette and 32-bpp presentation;
5. all required directions, loaded states, articulated parts, and mandatory animation frames.

Extra-zoom sprites are authored for their resolution. Automated nearest-neighbour enlargement is acceptable only as a temporary development placeholder and blocks an art-complete release label.

The 8-bpp sprite is not an afterthought: silhouette, windows, wheels/bogies, articulation, and cargo state must remain identifiable without relying on alpha or fine texture.

### Company colour and liveries

- Company colours occupy deliberate panels, stripes, or structural areas rather than tinting the entire vehicle.
- Palette sprites use the supported OpenTTD company-colour ranges. 32-bpp work uses the corresponding mask/recolour pipeline supported by NML/OpenTTD.
- Essential state is never communicated by company colour alone.
- Default liveries are original. Historical/operator liveries follow the rights rules above and remain optional variants.
- Two-company-colour support is used consistently within a pack or not exposed; it cannot change vehicle stats.

### Animation and state variants

Animation is reserved for readable mechanical state: wheel or rotor motion, pantographs, doors, loading equipment, wakes, exhaust, navigation lights, or cargo fill. It must obey these rules:

- frame selection is deterministic and driven by supported game state/ticks;
- a static fallback exists for `visual_detail=essential`;
- animation does not mutate capacity, reliability, payment, speed, or any other simulation value;
- frame counts and callback chains are bounded;
- stopped, loading, reversing, depot, crashed, and hidden states do not show impossible motion;
- visual emissions follow the technology and load rather than decorating every vehicle identically.

Sounds are optional for the first release. Any sound that ships follows the same provenance and license manifest as visual art, has a sane level, and does not replace unrelated base sounds globally.

## Initial release roster

These are original working names. Year ranges are design windows to validate during research, not final historical claims.

### Trains and trams

| ID | Working name | Introduction | Role | Evidence class |
| --- | --- | ---: | --- | --- |
| `mttr_rail_1835_pioneer_steam` | Pioneer 2-2-2 | 1835 | Light passenger | Historical archetype |
| `mttr_rail_1875_consolidation` | Foundry 2-8-0 | 1875 | Heavy freight | Historical archetype |
| `mttr_rail_1915_express_steam` | Meridian 4-6-2 | 1915 | Express passenger | Historical archetype |
| `mttr_rail_1935_electric` | Gridline Electric | 1935 | Mixed traffic | Historical archetype |
| `mttr_rail_1962_mixed_diesel` | Longhaul Diesel | 1962 | Mixed traffic | Historical archetype |
| `mttr_rail_1978_commuter_emu` | Citylink EMU | 1978 | Commuter | Historical archetype |
| `mttr_rail_1992_high_speed` | Intercity 300 | 1992 | High-speed passenger | Historical archetype |
| `mttr_rail_2024_battery_emu` | Regional Battery Unit | 2024 | Regional/branch | Contemporary archetype |
| `mttr_rail_2042_hydrogen_freight` | H2 Heavy Hauler | 2042 | Low-carbon freight | Near-future projection |
| `mttr_rail_2070_flux_maglev` | Fluxline 600 | 2070 | Very high-speed passenger | Fictional |
| `mttr_tram_1900_electric` | Borough Tram | 1900 | Urban tram | Historical archetype |
| `mttr_tram_2032_modular` | Metrostreet Modular | 2032 | High-capacity tram | Near-future projection |

The train pack also needs a compatible wagon family at launch: early and modern passenger coaches; mail/express van; box/covered, open/bulk, flat/container, hopper, tanker, refrigerated, livestock, and armoured/value wagons. Wagon graphics require empty/loaded or cargo-specific states where the cargo is externally visible.

### Road vehicles

| ID | Working name | Introduction | Role | Evidence class |
| --- | --- | ---: | --- | --- |
| `mtrv_bus_1910_petrol` | Town Motor Bus | 1910 | Local bus | Historical archetype |
| `mtrv_truck_1925_rigid` | Workhorse Rigid | 1925 | General freight | Historical archetype |
| `mtrv_bus_1955_diesel` | Metro Diesel Bus | 1955 | Urban bus | Historical archetype |
| `mtrv_truck_1968_articulated` | Continental Artic | 1968 | Long-haul freight | Historical archetype |
| `mtrv_coach_1988` | Horizon Coach | 1988 | Intercity coach | Historical archetype |
| `mtrv_van_2005` | City Cargo Van | 2005 | Express/light freight | Historical archetype |
| `mtrv_bus_2022_electric` | E-Line City Bus | 2022 | Battery urban bus | Contemporary archetype |
| `mtrv_truck_2035_electric` | Megawatt Artic | 2035 | Battery freight | Near-future projection |
| `mtrv_bus_2045_autonomous` | Loop Shuttle | 2045 | High-frequency feeder | Near-future projection |
| `mtrv_truck_2075_roadtrain` | Atlas Modular Roadtrain | 2075 | Autonomous heavy freight | Fictional |

The road pack launches with body/cargo variants for passengers, mail/express, piece goods, refrigerated goods, bulk, liquid, livestock, and containerised freight. Variants reuse a chassis only when dimensions, axle count, and loading behavior remain visually credible.

### Ships

| ID | Working name | Introduction | Role | Evidence class |
| --- | --- | ---: | --- | --- |
| `mtsh_1860_coastal_steamer` | Coastal Steamer | 1860 | Mixed coastal service | Historical archetype |
| `mtsh_1905_river_tug` | River Tug and Barge | 1905 | Inland freight | Historical archetype |
| `mtsh_1958_vehicle_ferry` | Sound Ro-Ro Ferry | 1958 | Passenger/vehicle ferry | Historical archetype |
| `mtsh_1975_bulk_carrier` | Capesize Bulk Carrier | 1975 | Bulk freight | Historical archetype |
| `mtsh_1998_container` | Oceanbridge Container Ship | 1998 | Container/general cargo | Historical archetype |
| `mtsh_2028_methanol_feeder` | Greenwake Feeder | 2028 | Low-carbon short sea | Contemporary archetype |
| `mtsh_2045_electric_ferry` | Fjord Battery Ferry | 2045 | Short-range passenger | Near-future projection |
| `mtsh_2080_wind_assist` | Pelagic Wingfreighter | 2080 | Long-range freight | Fictional |

Tankers, refrigerated cargo, and passenger ferries use distinct silhouettes or deck states; a generic hull recolour is not sufficient when the operating role changes visibly.

### Aircraft

| ID | Working name | Introduction | Role | Evidence class |
| --- | --- | ---: | --- | --- |
| `mtar_1932_piston_mail` | Courier Twin | 1932 | Mail/light passenger | Historical archetype |
| `mtar_1948_piston_airliner` | Meridian Pistonliner | 1948 | Medium passenger | Historical archetype |
| `mtar_1960_turboprop` | Regional Turboprop | 1960 | Short-haul passenger | Historical archetype |
| `mtar_1972_narrowbody_jet` | Cityjet 120 | 1972 | Medium-haul passenger | Historical archetype |
| `mtar_1988_widebody` | Global Twin-Aisle | 1988 | Long-haul passenger | Historical archetype |
| `mtar_1995_cargo_jet` | Atlas Freighter | 1995 | Long-haul cargo | Historical archetype |
| `mtar_2025_efficient_twinjet` | Horizon Twinjet | 2025 | Long-haul passenger | Contemporary archetype |
| `mtar_2038_hybrid_regional` | Voltwing Regional | 2038 | Short-haul passenger | Near-future projection |
| `mtar_2048_hydrogen_cargo` | Cryowing Freighter | 2048 | Medium-haul cargo | Near-future projection |
| `mtar_2085_blended_wing` | Stratos Lifter | 2085 | High-capacity passenger/cargo | Fictional |

At least one historically grounded helicopter and one airship are required before the aircraft roster is considered complete, but they are not part of the compact launch gate unless their gameplay roles are distinct and their airport behavior is verified.

## Source and repository layout

Target layout; these paths are not asserted to exist yet:

```text
extensions/modern_tycoon_vehicles/
  README.md
  LICENSE
  Makefile
  manifest/
    assets.yaml
    sources.yaml
    ids.yaml
  data/
    balance.yaml
    cargo_compatibility.yaml
    trains.yaml
    road_vehicles.yaml
    ships.yaml
    aircraft.yaml
  nml/
    common/
      parameters.pnml
      callbacks.pnml
      costs.pnml
    trains/
      modern_tycoon_trains.nml
      vehicles.pnml
      wagons.pnml
    road/
      modern_tycoon_road.nml
      vehicles.pnml
    ships/
      modern_tycoon_ships.nml
      vehicles.pnml
    aircraft/
      modern_tycoon_aircraft.nml
      vehicles.pnml
  lang/
    english.lng
  art/
    source/<pack>/<vehicle>/
    exports/8bpp/<pack>/
    exports/32bpp/<zoom>/<pack>/
    masks/company_colour/<pack>/
  sounds/source/
  generated/
  tools/
    validate_manifest.py
    validate_roster.py
    validate_sprites.py
    render_contact_sheets.py
  tests/
    compatibility/
    expected/
```

Only source files, manifests, reviewable exports, and reproducible build instructions are committed. `generated/` is disposable build output. The build must pin or record the NML compiler version used for a release.

Shared data is expanded into each pack at build time; the `.grf` files have no runtime dependency on a private shared GRF. Generated NML is inspectable. Stable IDs live in `manifest/ids.yaml`, not in file ordering or an implicit counter.

## Provenance and license manifest

Every source and exported asset has a manifest record before it can enter a release:

```yaml
asset_id: MT-A-000123
vehicle_id: mttr_rail_1962_mixed_diesel
files:
  - art/source/trains/mttr_rail_1962_mixed_diesel/body.blend
  - art/exports/8bpp/trains/mttr_rail_1962_mixed_diesel.png
kind: original_sprite
authors:
  - name: Example Artist
    contribution: modelling, lighting, pixel cleanup
license: GPL-2.0-or-later
source_asset: art/source/trains/mttr_rail_1962_mixed_diesel/body.blend
created: 2026-07-16
derived_from: []
references:
  - MT-S-000456
review:
  provenance: pending
  visual: pending
  legal: pending
sha256: pending
```

Each source record includes title, author/publisher, URL or archive identifier, access date, license/status, and what factual claim it supports. A source marked `reference-only` is not copied into the repository and cannot be transformed into a distributable asset.

NML, build scripts, and original first-party assets use `GPL-2.0-only` or a GPLv2-compatible license accepted by the project. Contributors must state the exact license; `free to use`, unknown, or no-license material is rejected. Public-domain/CC0 material records its provenance and declaration. A release bundles the license text, authorship credits, source offer/source archive, and generated provenance report.

No asset is accepted because another NewGRF happens to contain it. Reuse requires its actual source, author, exact license, and derivative permission.

## Automated quality gates

### Build and data integrity

- All four packs compile with the pinned supported NML compiler with no warnings promoted by project policy.
- GRF IDs, vehicle IDs, string IDs, and asset IDs are unique and stable.
- Every referenced sprite, sound, translation string, cargo label, type label, and manifest record resolves.
- Generated NML is reproducible from committed data and source art; a clean rebuild has no unexplained diff.
- Each public build embeds a version and source revision and produces checksums for the GRFs and source archive.

### Roster and balance

- CI renders an introduction/retirement timeline for every mode, role, and `roster_scope` and fails on an unintended availability gap.
- Capacity, speed, power, mass, cost, loading, and reliability stay inside declared role bands.
- Unit tests cover every parameter combination and ensure 2051+ fictional vehicles cannot leak into `grounded` mode.
- Cargo/refit matrices are generated and reviewed; unknown labels produce a deliberate result.
- A deterministic test game can buy, refit, clone, replace, sell, save, load, and continue every vehicle class.

### Visual QA

- A sprite validator checks PNG mode, palette, alpha, dimensions, empty frames, masks, frame count, and declared offsets.
- CI produces contact sheets for every direction, zoom, company-colour combination, cargo/loading state, articulated part, and animation frame.
- Automated bounds tests flag clipping, anchor drift, detached parts, direction mismatches, and non-empty pixels outside the declared box.
- Review saves exercise depots, stations, bridges, tunnels, slopes, crossings, airports, docks, overtaking, reversing, crashes, and dense queues.
- Visual sign-off is performed at 1x, 2x, and 4x UI/display scales with both 8-bpp fallback and 32-bpp sprites.
- Placeholder upscales, missing directions, unlicensed sounds, and `pending` provenance block an art-complete release.

### Compatibility and determinism

The release matrix covers:

- current stable OpenTTD and the fork's pinned revision;
- OpenGFX and the selected OpenGFX2 development baseline;
- temperate, sub-arctic, sub-tropical, and toyland cargo/climate behavior where the vehicle is enabled;
- no other vehicle set, one representative additive vehicle set, and deliberate parameter/name conflicts;
- vanilla cargos plus pinned representative cargo/industry sets whose label mappings are documented;
- games beginning in 1830, 1900, 1950, 2000, 2050, and 2100;
- new game, autoreplace, save/load, content removal error handling, and two-client dedicated multiplayer.

The exact GRF files and parameter values are part of the network content signature. Visual callbacks use only deterministic NewGRF variables. A pack may show an incompatibility notice for a known hard conflict; it may not mutate another GRF or guess its numeric IDs.

### Performance budgets

- Static properties remain static; callbacks are used only when state-dependent graphics or behavior require them.
- Callback chains, animation frames, articulated parts, cargo variants, and recolour combinations have explicit per-vehicle limits recorded in the data schema.
- The initial compressed family budget is 128 MiB per pack and 320 MiB total, including all required zoom levels. Exceeding it requires measured value and a documented packaging decision.
- A 5,000-vehicle benchmark compares tick time, render frame time at representative zooms, save size/time, load time, and peak memory with `visual_detail=essential` and `animated`.
- Simulation tick time may not regress more than 2% against the same save using equivalent static callbacks; larger changes require profiling and approval.
- No animation or visual callback may scan the map, stations, industries, or other vehicles.
- CI records GRF compile time and size. Release testing records content scan/load time on the reference machine; budgets are tightened after the first measured baseline rather than hidden.

## Definition of done for one vehicle

A vehicle is release-ready only when:

1. its gameplay record, era, evidence class, sources, and stable ID are approved;
2. its stats pass role and availability validation in every exposed parameter mode;
3. source art and all required exported sprite tiers exist;
4. all directions, states, zooms, masks, offsets, articulation, and animation pass automated and visual QA;
5. every file has approved authorship, provenance, license, and hash records;
6. purchase, refit, operation, autoreplace, sell, save/load, and multiplayer smoke tests pass;
7. player-facing names and descriptions clearly distinguish grounded, projected, and fictional content;
8. performance evidence fits the family budget.

## Definition of done for the first family release

- Each of the four packs has a coherent compact roster and no accidental pre-2051 service gap in its declared scope.
- Standard mode includes the initial roster above plus the required wagon/cargo variants.
- Fictional content is disabled by `grounded`, clearly labelled elsewhere, and uses only original names and designs.
- There are no missing sprites, placeholder upscales, unknown licenses, unreviewed manifest entries, or borrowed TTD/third-party pixels.
- A clean source checkout reproduces all release GRFs and the provenance report.
- Compatibility, deterministic multiplayer, save/load, visual, and performance gates pass on the pinned matrix.
- The release notes distinguish implemented content from later roster targets and list known NewGRF conflicts honestly.

## Primary implementation references

- OpenTTD NewGRF development overview: <https://wiki.openttd.org/en/Development/NewGRF/>
- NML documentation: <https://nml.readthedocs.io/en/latest/>
- NML source and current documentation entry points: <https://github.com/OpenTTD/nml>
- OpenGFX2 source and art direction reference: <https://github.com/OpenTTD/OpenGFX2>
- OpenTTD contribution and GPL boundary: <https://github.com/OpenTTD/OpenTTD/blob/master/CONTRIBUTING.md>

SPDX-License-Identifier: GPL-2.0-only
