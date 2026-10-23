# Market lab and Ledger tests

`market_test.sh` runs headless OpenTTD games in throw-away profiles (null video, sound and music; never the player's profile) and checks the script log.

```sh
OPENTTD_BIN=build/openttd extensions/modern_tycoon_gs/test/market_test.sh all
```

| Scenario | What it proves |
|---|---|
| `merger` | STATUS gate 1 with a real engine takeover: funds rules, pending settlement, portfolio transfer, inherited self-share settlement, delisting payouts and lot conservation. Saves and reloads in the middle of the bankruptcy. |
| `delist` | STATUS gate 1 with a real bankruptcy closure: holders are paid the final quote, the closed company's lots are released, and issued lots still match holdings. Also reloads mid-bankruptcy. |
| `news` | Ten years with a route-building rival (Nordlys Air, read from `origin/claude/first-ai-player` when available): at least 30 editions, at most 60 pop-ups, Rival Watch reports, and the archive survives reload. Prints the first and last editions. |
| `migrate` | A schema 2 save made by the last schema 2 script (commit `72e60f2ef`, override with `SCHEMA2_COMMIT`) loads into the current script with the same instruments, and its old headlines become an archived edition. |
| `soak` | The original July soak: 150,000 ticks with the built-in buy/distribution/sell self-test. |

The fixture lives in [`../fixture.nut`](../fixture.nut) and is enabled only by the developer setting `developer_fixture` (1 merger, 2 delist). It deliberately changes company finances, so never enable it in a normal game. It uses three `Modern Tycoon Test Company` AIs; the merger scenario sets their `accept_merger=1` so one of them buys the bankrupt target.

Requirements: a built `openttd` with `OpenGFX-*.tar` in its `baseset` folder, and `git` (the `news` and `migrate` scenarios read files from other branches).

SPDX-License-Identifier: GPL-2.0-only
