# Market lab and Ledger tests

`market_test.sh` runs headless OpenTTD games in throw-away profiles (null video, sound and music; never the player's profile) and checks the script log.

```sh
OPENTTD_BIN=build/openttd extensions/modern_tycoon_gs/test/market_test.sh all
```

| Scenario | What it proves |
|---|---|
| `merger` | STATUS gate 1 with a real engine takeover: funds rules, pending settlement, portfolio transfer, inherited self-share settlement, delisting payouts and lot conservation. Saves and reloads in the middle of the bankruptcy. |
| `delist` | STATUS gate 1 with a real bankruptcy closure: holders are paid the final quote, the closed company's lots are released, and issued lots still match holdings. Also reloads mid-bankruptcy. |
| `news` | Ten years with a route-building rival (Nordlys Air from `extensions/nordlys_air`): at least 30 editions, at most 60 pop-ups, Rival Watch reports, and the archive survives reload. Prints the first and last editions. |
| `migrate` | Saves made by the schema 2 lab (`926376b84`) and the schema 3 Ledger (`7cf977433`) load into the current script with the same instruments; every security starts pricing from fair value; schema 2 headlines become an archived edition and schema 3 editions are kept. |
| `pricing` | Ten years with Nordlys Air, Fjellbanen Gods and an idle company (`PRICING_SEED` picks the map, default 20261023). [`price_report.py`](price_report.py) checks that the median price/fundamental is 0.80-1.25, quotes stay within 0.2-5x fundamental, at least a sixth of monthly moves are falls, and buy-and-hold loses money in some quarters (also for company shares alone). Then reloads and checks the pricing state was restored. |
| `replay` | The same two-year game (fixed map seed) run twice gives identical monthly quotes. |
| `soak` | The original July soak: 150,000 ticks with the built-in buy/distribution/sell self-test. |

The fixture lives in [`../fixture.nut`](../fixture.nut) and is enabled only by the developer setting `developer_fixture` (1 merger, 2 delist). It deliberately changes company finances, so never enable it in a normal game. It uses three `Modern Tycoon Test Company` AIs; the merger scenario sets their `accept_merger=1` so one of them buys the bankrupt target.

Requirements: a built `openttd` with `OpenGFX-*.tar` in its `baseset` folder, `git` (the `migrate` scenario reads the script from pinned commits) and `python3` (the `pricing` report).

SPDX-License-Identifier: GPL-2.0-only
