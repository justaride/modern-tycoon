# Fjellbanen Gods

A Modern Tycoon rail freight AI with its own A* pathfinder (no downloaded libraries).
President Ivar Skinnes, red livery, trains named after Norwegian mountains and lines
(`Dovregubben 1`, `Rauma 2`, ...). Log messages are in Norwegian.

## What it does

1. Picks the busiest freight industry that few others serve (coal, wood, grain, oil, ore ...)
   and a customer 40-120 tiles away that accepts the cargo. Score = production × distance,
   best around 80 tiles.
2. Places a one-platform terminus at each end (platform length depends on personality) with
   the open end facing the other industry.
3. Finds a route with [`pathfinder.nut`](pathfinder.nut):
   - A* over tiles with a priority queue, 40 000 node budget;
   - only clear land, or straight level crossings over flat roads;
   - flat tiles may turn; sloped tiles are crossed straight along the incline; no steep slopes or water;
   - never two same-way turns in a row, because trains may not take 90° bends (OpenTTD default).
4. Checks the full price with a dry run, lays the track, and on a failed piece removes it,
   blocks that tile and searches again (3 tries).
5. Builds a depot beside the line near the source and a full-load freight train that fits the platform.
6. Every month: replaces lost or crashed trains, closes lines whose industry closed or whose
   train keeps losing money, and tears down closed lines (track, stations, depot).
7. Self-healing: a train that reports "lost" twice closes its line.
8. Yearly report with one line per rail line.

Personality (shared with Nordlys Air through an identical [`personality.nut`](personality.nut)):
cautious companies keep more cash, borrow less, build 4-tile platforms and grow slowly;
aggressive ones borrow fully, build 6-tile platforms and expand fast.

## Settings

| Setting | Default | Meaning |
|---|---|---|
| `personality` | random | Cautious, balanced, aggressive or random |
| `max_routes` | 8 | Maximum number of rail lines |
| `use_loan` | on | Borrow money to expand faster |

## Limits of version 1

- One train per line, no signals or passing loops yet.
- No bridges or tunnels: water and steep valleys block a line.
- Freight to industries only (no goods to towns, no passengers).

## Testing

```sh
extensions/fjellbanen_gods/test/smoke_test.sh [start_year] [years] [seed]
PERSONALITY=2 extensions/fjellbanen_gods/test/smoke_test.sh 1950 6 777
RIVALS=1 extensions/fjellbanen_gods/test/smoke_test.sh   # with Nordlys Air in the same game
```

The test fails on script errors, if no line is built, if no train earns money, if a train
gets lost, if lines are lost after save/load, or if the `personality.nut` copies differ.

SPDX-License-Identifier: GPL-2.0-only
