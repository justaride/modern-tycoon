# Fjellbanen Gods

A Modern Tycoon rail freight AI with its own A* pathfinder (no downloaded libraries).
President Ivar Skinnes, red livery, trains named after Norwegian mountains and lines
(`Dovregubben 1`, `Rauma 2`, ...). Log messages are in Norwegian.

## What it does

1. Picks the best paying freight source that few others serve: monthly production ×
   income per unit for the distance (40-120 tiles). The customer is an industry that
   accepts the cargo, or, for goods, food and water, a town of at least 1 000 people.
   A source the company already feeds (a sawmill or factory it delivers to) scores
   higher: closing the chain means the goods made from its deliveries earn money too.
2. Builds a **double-track line** between two **two-platform termini**:

   ```
   platform 0 ═ s0 ═ f0 ╲╱ ═ n0 ── outbound track ──▶ other end
   platform 1 ═ s1 ═ f1 ╱╲ ═ n1 ◀── inbound track ───
   ```

   - `s0/s1`: two-way path signals at the platform exits (arriving trains pass them from behind);
   - `f0/f1`: a scissors crossover, so every platform reaches both tracks;
   - each track is found separately by [`pathfinder.nut`](pathfinder.nut) and carries
     one-way path signals every platform length + 2 tiles, plus an entry signal in front
     of the next terminus.

   Trains never meet head on and only wait at signals or platforms, so the line cannot
   deadlock however many trains run. Tested up to 8 trains per line.
3. The pathfinder:
   - A* over tiles with a priority queue, 60 000 node budget and a 60 game-day time limit;
   - clear land, or straight level crossings over flat roads;
   - flat tiles may turn; sloped tiles are crossed straight along the incline;
   - never two same-way turns in a row (trains may not take 90° bends, OpenTTD's default);
   - **bridges** over water, roads, railways and steep land, **tunnels** through hills,
     each tried only where plain track is blocked, and cached per search;
   - a track never uses a tile twice (a loop back over itself would meet its own one-way signals).
4. Checks the full price with a dry run, lays both tracks, verifies every piece joins its
   neighbours (`Sporfeil` in the log if not), and on a failed piece searches again around it.
5. A depot beside a straight stretch, joined both ways; starts `start_trains` full-load trains.
6. Every month: adds a train when cargo piles up or nobody is loading (at most every 3 months),
   retires extra trains that lose money (then no new trains for a year), closes lines whose
   industry closed or that keep losing money, and tears down closed lines.
7. Watchdog: a train that stands still outside stations and depots for a year is reported
   (`står fast`) and reversed; a train reported lost twice closes its line.
8. Yearly report with one line per rail line (cargo, trains, profit, cargo waiting).

Version 1 lines (single track, one train) in older saves keep running unchanged.

Personality (shared with Nordlys Air through an identical [`personality.nut`](personality.nut)):
cautious companies keep more cash, borrow less, build 4-tile platforms, grow slowly and run
at most 4 trains per line; aggressive ones borrow fully, build 6-tile platforms and expand fast.

## Settings

| Setting | Default | Meaning |
|---|---|---|
| `personality` | random | Cautious, balanced, aggressive or random |
| `max_routes` | 8 | Maximum number of rail lines |
| `start_trains` | 2 | Trains on a new line (more are added while cargo piles up) |
| `use_loan` | on | Borrow money to expand faster |

## Limits

- Tunnels are supported but rare: in hills most tunnel exits end on corner slopes where
  straight track cannot continue without breaking the track height, so the pathfinder goes
  over or around instead. No tunnel was built in the test games.
- No passengers, no electrified or faster rail upgrades yet.
- A terminus needs a free, flat 2 × (platform + 2) area next to the industry or town.

## Testing

```sh
extensions/fjellbanen_gods/test/smoke_test.sh [start_year] [years] [seed]
PERSONALITY=2 START_TRAINS=5 extensions/fjellbanen_gods/test/smoke_test.sh 1995 12 44  # signal stress
MAP_BITS=9 TERRAIN=4 extensions/fjellbanen_gods/test/smoke_test.sh                      # big alpine map
RIVALS=1 extensions/fjellbanen_gods/test/smoke_test.sh                                  # with Nordlys Air
extensions/fjellbanen_gods/test/matrix.sh      # 11 games in parallel: seeds, years, sizes, terrain
extensions/fjellbanen_gods/test/v1_compat.sh   # a version 1 save loads and keeps running
```

The smoke test fails on script errors, no line built, no train earning money, no line with
two or more profitable trains, a lost or stuck train, track that does not connect, lines lost
after save/load, or `personality.nut` copies that differ. `REQUIRE_JUMP=1` also requires a
bridge or tunnel.

SPDX-License-Identifier: GPL-2.0-only
