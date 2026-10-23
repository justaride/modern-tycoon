# Nordlys Air

The first Modern Tycoon AI player: a calm, profit-minded Norwegian airline.

## What it does

1. Names itself *Nordlys Air* (president Solveig Fjellheim) and paints its fleet dark green.
2. Picks the two largest free towns that are far enough apart to make flying worth it.
3. Builds the best airport type that fits near the busiest part of each town
   (metropolitan, large, commuter or small, depending on the year and space).
4. Buys the best passenger plane that suits the airport and can reach the other end.
   Big planes only use big airports, because they crash on small ones.
5. Every month it adds a plane where passengers pile up, and retires planes that have
   lost money for a full year (a route always keeps its last plane).
6. Borrows to grow when allowed and pays the loan back when cash is plentiful.
7. Writes a short yearly report to the AI debug log, in Norwegian.

Planes are named after Norwegian nature with a unique registration, e.g. `Midnattsol LN-NAB`.

## Settings

| Setting | Default | Meaning |
|---|---|---|
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
extensions/nordlys_air/test/smoke_test.sh
```

## Ideas for later

- Mail and freight planes, helicopters for small towns.
- Personality settings (cautious, balanced, aggressive).
- React to Modern Tycoon market events and the newspaper.
- Rivalry: prefer towns that other companies do not serve yet.

SPDX-License-Identifier: GPL-2.0-only
