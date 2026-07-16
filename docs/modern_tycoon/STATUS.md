# Modern Tycoon status

Last updated: 2026-07-16

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
| Native market | Compile-only spine passed locally | 32-bit typed security/holding pools, 1/256-Money checked arithmetic, valuation, spread/fee, structurally validated settlement, cost-basis, cap, conservation, and sparse lookup are covered by nine focused cases (567,573 assertions). No commands, settings, timers, saves, or UI are hooked up. |
| Graphics and vehicle pack | Contract plus compatibility bridge | First-party roster/art contract is written. Twelve pinned third-party NewGRFs loaded and completed the long headless soak; no art was copied or edited. |
| Live GameScript discovery | Installed, not activated | The live profile's `game/modern_tycoon` symlink makes the prototype selectable for new games; configuration and existing games were not changed. |
| macOS package/UI | Build-only proof | CPack produced a local app/DMG and the app binary launched after temporary ad-hoc signing; dependency targeting, bundle signing, and visual Story Book QA are not release-approved. |
| Live-profile compatibility | Not claimed | Existing saves/NewGRFs have not been opened with the fork. |
| Multiplayer determinism | Not claimed | Requires native command/state implementation and dedicated soak tests. |
| Save atomicity | Prototype boundary | Quiescent-tick save/reload is proven; GameScript cash commands cannot be made atomic with an independently timed `Save()` callback. |

## Immediate next gates

1. Add scripted merger, issuer deletion/delisting, pending-settlement, and insufficient-funds checks.
2. Complete manual/visual Story Book and curated-content QA in an isolated GUI profile.
3. Add the default-off synchronized buy/sell command slice only after fixing the fork save-version band and command-level fixture plan.
4. Create original source art and the first compilable NML vehicle archetype under the provenance contract.
5. Build a clean, signed macOS package with dependencies targeting the documented minimum OS.

## Known risks

- Only one GameScript can run, so the market prototype cannot coexist with Villages Is Villages.
- GameScript industry securities are synthetic because core industries have no cash accounts.
- OpenTTD's official repository will not accept generated code; this remains an independent fork.
- Native pool uniqueness, issuer/holder deletion, generation/ID reuse, and pool-wide conservation are not implemented yet; the pools must remain unreachable until command, lifecycle, save/load, and after-load validators cover them.
- The native slice has only been built and tested on Apple Silicon macOS; supported-platform CI remains a release gate.
- Real vehicle likenesses, names, logos, liveries, photography, and third-party models require explicit asset provenance and licensing review.
- The live profile has duplicate/legacy content and historical graphics/NewGRF crashes; it is unsuitable as the first smoke-test environment.

SPDX-License-Identifier: GPL-2.0-only
