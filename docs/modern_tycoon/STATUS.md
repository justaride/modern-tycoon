# Modern Tycoon status

Last updated: 2026-10-23

## Proof layers

| Layer | State | Evidence / boundary |
| --- | --- | --- |
| Workspace audit | Complete | Live path identified as user data; secrets not inspected; no prior source checkout found. |
| Canonical checkout | Complete | Source and build moved to `/Users/gabrielfreeman/src/OpenTTD`; the former iCloud development path is a symlink. |
| Upstream truth | Complete | Current master cloned at `5b9f18d8fd0a16f5022c0351b5e3590852d24745`; official stable is 15.3 and 16.0-beta2 is current testing line. |
| Toolchain | Complete | CMake, Ninja, Clang C++20, PNG, zlib, liblzma, LZO, CURL, and OpenGL detected. |
| Vanilla compile | Passed | RelWithDebInfo macOS build linked `openttd` and `openttd_test`. |
| Full test matrix | Passed | All 107 CTest unit and scripted regression tests passed on the final run. |
| Market prototype implementation | Headless runtime proof passed | v2 scanner, two-company 150,000-tick soak, buy/distribution/sell accounting, zero-fee anti-wash test, v1 migration, and v2 reload passed. |
| Market lifecycle fixtures (gate 1) | Headless proof passed 2026-10-23 | `extensions/modern_tycoon_gs/test/market_test.sh merger` and `delist` drive a real engine takeover and a real bankruptcy closure of a test company (the target is pushed into debt; with `accept_merger=1` a test AI buys it). 16/16 and 14/14 checks: insufficient funds, self-trade and no-holding rejection; pending settlement queued, kept on a failed retry and paid by the monthly retry; portfolio transfer; inherited self-share settlement; delisting payouts equal lots x final quote to the unit; released lots; issued lots equal holdings. Both scenarios save and reload in the middle of the bankruptcy. The settlement failure is simulated through a test-only seam, because a deity balance credit does not fail in practice. |
| Structured newspaper (GameScript) | Headless proof passed 2026-10-23 | Schema 3 adds a bounded fact journal with stable template IDs, sections, severities, dedupe keys, aggregation, a ranked lead, and an archive of 12 editions on its own Story Book page. A ten-year run with two Nordlys Air rivals produced 40 quarterly editions with 36 pop-ups (previously one pop-up per listing and payout), Rival Watch and transport reports, and the archive survived reload. A schema 2 save from `main` migrated with all 14 instruments and its old headlines archived. Not yet reviewed visually in the GUI. |
| Deterministic share pricing (GameScript) | Headless proof passed 2026-10-23 | Schema 4 (`extensions/modern_tycoon_gs/pricing.nut`): quote = smoothed fair value x (1 + mood + growth premium). Mood keeps 80% a month, gets a bounded hash-based nudge (seed drawn once and saved) and shocks from quarterly results vs expectation, losses, negative cash, the in-trouble event, raw-industry output booms/slumps and closure warnings. The quote closes 75% of a gap above 20% and 40% otherwise, and stays within 0.25x..4x fair value. `market_test.sh pricing`, ten years with Nordlys Air, Fjellbanen Gods and an idle company on three map seeds: median price/fundamental 1.000-1.004 (p10 0.95, p90 1.04-1.06, range 0.77-1.50); 810-829 monthly falls against 931-953 rises; company shares lost money in 117-145 of 330 quarter holds and 91-105 of 303 one-year holds. `replay`: 345 quotes identical across two runs of the same game. Schema 2 and schema 3 saves (pinned commits) load with every security started from fair value. Not yet reviewed visually in the GUI; the GameScript runs on the server only, so multiplayer sync is by construction, not tested. |
| Native market | Compile-only spine passed locally | 32-bit typed security/holding pools, 1/256-Money checked arithmetic, valuation, spread/fee, structurally validated settlement, cost-basis, cap, conservation, and sparse lookup are covered by nine focused cases (567,573 assertions). No commands, settings, timers, saves, or UI are hooked up. |
| Graphics and vehicle pack | First original NewGRF: headless proof passed 2026-10-23 | `extensions/modern_tycoon_vehicles` builds Modern Tycoon Trains (`MTTR`) from source with nmlc 0.9.0, no warnings, byte-identical rebuilds: the Tinde DM6 dual-mode freight locomotive and the Tinde bulk hopper (empty/loaded), 8 directions each, procedurally drawn 8bpp sprites aligned to OpenGFX anchors. `test/ingame_test.sh`: the GRF loads in a 2020 game, a test AI buys the locomotive and 3 hoppers (capacity 120), refits to iron ore, runs the train at 120 km/h, and the train survives save/reload; Fjellbanen Gods adopts the hoppers by itself. Not release art: provenance review, 32bpp/extra zoom, shadows and GUI visual review are open. Twelve pinned third-party NewGRFs still load in the long soak; no third-party art was copied. |
| Live GameScript discovery | Installed, not activated | The live profile's `game/modern_tycoon` symlink makes the prototype selectable for new games; configuration and existing games were not changed. |
| macOS package/UI | Build-only proof | CPack produced a local app/DMG and the app binary launched after temporary ad-hoc signing; dependency targeting, bundle signing, and visual Story Book QA are not release-approved. |
| Live-profile compatibility | Not claimed | Existing saves/NewGRFs have not been opened with the fork. |
| Multiplayer determinism | Not claimed | Requires native command/state implementation and dedicated soak tests. |
| Save atomicity | Prototype boundary | Quiescent-tick save/reload is proven; GameScript cash commands cannot be made atomic with an independently timed `Save()` callback. |

## Immediate next gates

1. ~~Add scripted merger, issuer deletion/delisting, pending-settlement, and insufficient-funds checks.~~ Done at GameScript level on 2026-10-23 (see the table above).
2. ~~Fix the listing/price-convergence rule before players are invited to trade.~~ Done at GameScript level on 2026-10-23 (deterministic pricing, see the table above).
3. Complete manual/visual Story Book and curated-content QA in an isolated GUI profile.
4. Add the default-off synchronized buy/sell command slice only after fixing the fork save-version band and command-level fixture plan.
5. ~~Create original source art and the first compilable NML vehicle archetype under the provenance contract.~~ First archetype done 2026-10-23 (development preview, see the table above); next: maintainer provenance decision on procedural art, 32bpp and 2x/4x sprites, then the wider roster.
6. Build a clean, signed macOS package with dependencies targeting the documented minimum OS.

## Known risks

- ~~Price convergence is predictable~~ (found and fixed 2026-10-23): quotes now follow a smoothed fair value with a growth premium, mood and event shocks, so they fall as well as rise. Remaining pricing risks: a brand-new company still lists at the 1,000 floor and can more than double in its first months as its value appears (largest single-month rise in tests +113% to +174%); the growth premium rewards steady growers, so a long-lived growing company is still a good, though no longer riskless, holding; industry fundamentals are synthetic.
- Null-driver games have no human company. Loading such a save creates an "Unnamed" local company, which the exchange then lists. This only affects headless tests, but tests must not assume the company count is stable across a reload.
- Industry-close events arrive after the industry is gone, so the Ledger can name only industries that were listed; others are reported as "an unlisted industry".

- Only one GameScript can run, so the market prototype cannot coexist with Villages Is Villages.
- GameScript industry securities are synthetic because core industries have no cash accounts.
- OpenTTD's official repository will not accept generated code; this remains an independent fork.
- Native pool uniqueness, issuer/holder deletion, generation/ID reuse, and pool-wide conservation are not implemented yet; the pools must remain unreachable until command, lifecycle, save/load, and after-load validators cover them.
- The native slice has only been built and tested on Apple Silicon macOS; supported-platform CI remains a release gate.
- Real vehicle likenesses, names, logos, liveries, photography, and third-party models require explicit asset provenance and licensing review.
- The live profile has duplicate/legacy content and historical graphics/NewGRF crashes; it is unsuitable as the first smoke-test environment.

SPDX-License-Identifier: GPL-2.0-only
