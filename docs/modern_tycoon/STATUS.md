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
| Native market | Compile-only spine passed locally | 32-bit typed security/holding pools, 1/256-Money checked arithmetic, valuation, spread/fee, structurally validated settlement, cost-basis, cap, conservation, and sparse lookup are covered by nine focused cases (567,573 assertions). No commands, settings, timers, saves, or UI are hooked up. |
| Graphics and vehicle pack | First original NewGRF: headless proof passed 2026-10-23 | `extensions/modern_tycoon_vehicles` builds Modern Tycoon Trains (`MTTR`) from source with nmlc 0.9.0, no warnings, byte-identical rebuilds: the Tinde DM6 dual-mode freight locomotive and the Tinde bulk hopper (empty/loaded), 8 directions each, procedurally drawn 8bpp sprites aligned to OpenGFX anchors. `test/ingame_test.sh`: the GRF loads in a 2020 game, a test AI buys the locomotive and 3 hoppers (capacity 120), refits to iron ore, runs the train at 120 km/h, and the train survives save/reload; Fjellbanen Gods adopts the hoppers by itself. Not release art: provenance review, 32bpp/extra zoom, shadows and GUI visual review are open. Twelve pinned third-party NewGRFs still load in the long soak; no third-party art was copied. |
| Space industry pack | First industry NewGRF: headless proof passed 2026-10-23 | `extensions/modern_tycoon_industries` builds Modern Tycoon Space Industry (`MTSI`) from source with nmlc 0.9.0: Rocket Fuel Plant (oil to rocket fuel), Spaceport (fuel to asteroid ore, with a 240-frame launch, return and landing animation) and Asteroid Refinery (ore to goods), two new cargos, procedurally drawn 8bpp buildings. `test/ingame_test.sh`: in a 1990 temperate game all three industries are built and accept their input, default oil tankers and coal trucks refit to the new cargos, the spaceport produced 104 t of ore in three months, and the industries survive save/reload. Not release art; the animation was reviewed in preview images, not in the GUI. |
| Live GameScript discovery | Installed, not activated | The live profile's `game/modern_tycoon` symlink makes the prototype selectable for new games; configuration and existing games were not changed. |
| macOS package/UI | Build-only proof | CPack produced a local app/DMG and the app binary launched after temporary ad-hoc signing; dependency targeting, bundle signing, and visual Story Book QA are not release-approved. |
| Live-profile compatibility | Not claimed | Existing saves/NewGRFs have not been opened with the fork. |
| Multiplayer determinism | Not claimed | Requires native command/state implementation and dedicated soak tests. |
| Save atomicity | Prototype boundary | Quiescent-tick save/reload is proven; GameScript cash commands cannot be made atomic with an independently timed `Save()` callback. |

## Immediate next gates

1. ~~Add scripted merger, issuer deletion/delisting, pending-settlement, and insufficient-funds checks.~~ Done at GameScript level on 2026-10-23 (see the table above).
2. Fix the listing/price-convergence rule (see risks) before players are invited to trade.
3. Complete manual/visual Story Book and curated-content QA in an isolated GUI profile.
4. Add the default-off synchronized buy/sell command slice only after fixing the fork save-version band and command-level fixture plan.
5. ~~Create original source art and the first compilable NML vehicle archetype under the provenance contract.~~ First archetype done 2026-10-23 (development preview, see the table above); next: maintainer provenance decision on procedural art, 32bpp and 2x/4x sprites, then the wider roster.
6. Build a clean, signed macOS package with dependencies targeting the documented minimum OS.

## Known risks

- Price convergence is predictable (found 2026-10-23): a company lists at the 1,000 floor when it is new, and the monthly move is capped at 10% of price, so a fast-growing company's quote climbs about 9% every month for years (Nordlys Air: 1,100 to 78,000 over about four years in the ten-year test). Buy-and-hold is close to riskless. Listing at a smoothed fundamental, or a faster cap while the gap is large, would fix it; this is a market-design choice, so it is not changed yet.
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
