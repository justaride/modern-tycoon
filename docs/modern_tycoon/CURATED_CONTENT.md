# Curated content playtest

The first-party vehicle and art family will take time to produce. This optional profile uses exact third-party NewGRFs already downloaded on the development machine as a compatibility bridge. Nothing from these archives is copied into, modified by, or redistributed with Modern Tycoon.

## Selected baseline

| Role | Exact test version |
| --- | --- |
| Economy and cargos | FIRS Industry Replacement Set 5.2.0 |
| Trains | Iron Horse 4.14.1 |
| Road vehicles and trams | Road Hog 1.4.1 |
| Ships | Squid Ate FISH/FISH 2 r1687 / archive 2.0.3 |
| Aircraft | av8 2.21 |
| Landscape and trees | OpenGFX+ Landscape 1.1.2; OpenGFX Trees 0.8.0 |
| Stations and airports | Industrial Stations Renewal 1.0.2; OpenGFX+ Stations 1.0; OpenGFX+ Airports 0.5.0 |
| Usability | Bigger Train Depot 0.3; OpenGFX BigGUI 2.0.0 |

The manifest in [`curated-playtest.example.cfg`](curated-playtest.example.cfg) pins each content ID, archive path, MD5, load order, and tested parameter set. Acquire those versions through OpenTTD's online content system; the example does not supply them.

## Executed compatibility proof

On 2026-07-16 all twelve selected NewGRFs were discovered with their expected IDs and versions. A seeded null-driver game then ran 150,000 ticks (more than five default calendar years) with two idle companies, Modern Tycoon Markets and News v2, and the zero-profit buy/sell conservation test. It exited successfully without a GameScript error or failed settlement log.

This proves loading and headless simulation only. Visual palette consistency, every purchase list, vehicle refits, station clipping, manual Story Book behavior, and save/reload with the entire set still require GUI and content-matrix QA.

## Deliberate exclusions

- Duplicate versions are never loaded together.
- XIS and OpenGFX+ Industries are excluded because FIRS owns the industry/cargo role.
- Additional train, road, ship, aircraft, metro, and vactrain sets remain isolated until they have a defined role and conflict test.
- Total Bridge Renewal remains outside the baseline because the live profile has historical graphics/NewGRF crashes. It is a precaution, not a proven diagnosis.
- Vactrain is a promising GPL future-play bridge, but the first-party design uses an explicit 2050 fiction boundary and will not inherit unreviewed third-party dates, names, stats, or art.

Every third-party archive remains subject to its own license and source-availability requirements. A future distributable preset may reference online-content IDs, but it must not bundle archives until provenance and redistribution terms are recorded.

SPDX-License-Identifier: GPL-2.0-only
