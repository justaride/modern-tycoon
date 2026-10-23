# Nordlys Air

The first Modern Tycoon AI player: a calm, profit-minded Norwegian airline.

## What it does

1. Names itself *Nordlys Air* (president Solveig Fjellheim) and paints its fleet dark green.
2. Picks the two largest free towns that are far enough apart to make flying worth it.
3. Builds the best airport type that fits near the busiest part of each town
   (metropolitan, large, commuter or small, depending on the year and space).
4. Buys the best passenger plane that suits the airport and can reach the other end.
   Big planes only use big airports, because they crash on small ones.
5. Every month it adds a plane where passengers pile up, and retires planes that keep
   losing money (a route always keeps its last plane).
6. **Fleet renewal (v2):** old planes, and planes that are at least 20% worse than the best
   current model, are sent to the hangar, sold and replaced with the best model.
7. **Airport upgrades (v2):** a busy route on small airports gets new large airports in the
   same towns; the old planes are retired and the old airports removed when empty.
8. **Mail (v2):** dedicated mail planes where mail piles up.
9. Borrows to grow within its personality's limits and pays the loan back when cash is plentiful.
10. Writes a yearly report to the AI debug log, in Norwegian, with one line per route.

## Personality

Shared with the other Modern Tycoon AIs through an identical copy of
[`personality.nut`](personality.nut):

| Personality | Reserve | Loan used | Expansion | Adds vehicles when waiting > | Retires loss makers after | Route cap |
|---|---|---|---|---|---|---|
| Forsiktig (cautious) | 40 000 | 60% | slow (45 days) | 3 × capacity | 3 years | 6 |
| Balansert (balanced) | 25 000 | 80% | normal (15 days) | 2 × capacity | 2 years | 12 |
| Aggressiv (aggressive) | 10 000 | 100% | fast (7 days) | 1.2 × capacity | 1 year | 40 |
| Tilfeldig (random) | rolled once per company and saved | | | | | |

Planes are named after Norwegian nature with a unique registration, e.g. `Midnattsol LN-NAB`.

## Settings

| Setting | Default | Meaning |
|---|---|---|
| `personality` | random | Cautious, balanced, aggressive or random |
| `max_routes` | 12 | Maximum number of air routes |
| `max_planes_per_route` | 5 | Maximum planes on one route (small airports cap at 4) |
| `use_loan` | on | Borrow money to expand faster |

## Install for play or testing

Link this folder into an `ai` search path of the game, for example:

```sh
ln -s "$PWD/extensions/nordlys_air" ~/Documents/OpenTTD/ai/nordlys_air
```

Then pick *Nordlys Air* under AI settings. Use a test profile first, as described in
[the development guide](../../docs/modern_tycoon/DEVELOPMENT.md).

Automated smoke test (clean throw-away profile, null drivers, save and reload):

```sh
extensions/nordlys_air/test/smoke_test.sh [start_year] [years]
PERSONALITY=0 extensions/nordlys_air/test/smoke_test.sh 1950 6
# Upgrade test: play with an older copy, load the save with this version
RUN1_AI_DIR=/path/to/old/nordlys_air extensions/nordlys_air/test/smoke_test.sh
```

Saves from version 1 load in version 2.

## Ideas for later

- Helicopters for small towns, freight planes.
- Better station ratings (more frequent service) on long routes.
- React to Modern Tycoon market events and the newspaper.
- Rivalry: prefer towns that other companies do not serve yet.

SPDX-License-Identifier: GPL-2.0-only
