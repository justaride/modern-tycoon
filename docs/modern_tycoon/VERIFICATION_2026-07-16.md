# Modern Tycoon verified baseline — 2026-07-16

## Scope

This report separates what was actually executed from future architecture. The source baseline is upstream master `5b9f18d8fd0a16f5022c0351b5e3590852d24745` on branch `codex/modern-economy-foundation`, built on Apple Silicon macOS. The final canonical checkout is `/Users/gabrielfreeman/src/OpenTTD`; the original iCloud development location is now a symlink to it.

The existing iCloud OpenTTD player profile was audited read-only. Its saves, configuration, downloaded NewGRFs, and private configuration are not part of this test result.

## Build and upstream tests

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build --parallel 10
ctest --test-dir build --output-on-failure
```

Result:

- `openttd` and `openttd_test` built successfully;
- all 107 of 107 CTest cases passed;
- the four null-driver scripted regressions passed;
- the final canonical-path full-suite run completed in about two seconds after regenerating Ninja dependency metadata damaged by the iCloud-to-local move.

The linker warned that the locally installed Homebrew PNG and LZO libraries target a newer macOS deployment version than OpenTTD's configured macOS 11 minimum. This did not fail build or test, but release binaries need a clean, intentionally versioned dependency toolchain.

## Native exchange spine

The first native Phase 2 slice is compiled but deliberately unreachable from gameplay. It adds 32-bit `SecurityID`/`HoldingID` pools, sparse holdings with aggregate cost basis, deterministic pool-index lookup, a signed 1/256-Money price contract, and portable checked integer helpers for valuation, monthly movement, bid/ask spread, fees, buy/sell settlement, proportional cost allocation, holder caps, and ledger conservation.

Executed proof:

- nine focused Catch2/CTest cases passed with 567,573 assertions, including property-style cost-basis remainder coverage, structurally invalid settlement rejection, and a non-zero conserved transition whose valid account aggregate exceeds `int64` summation range;
- the full matrix passed 107 of 107 cases;
- a 100,000-tick clean null-driver game using `/dev/null` as config exited successfully with no GameScript, AI, or NewGRF loaded;
- the existing 150,000-tick Modern Tycoon GameScript/content soak still passed after linking the native spine;
- source inspection confirms there are no new command IDs, settings, economy timers, save chunks, windows, company lifecycle hooks, or script APIs.

The global pools are empty and normal-reset-managed. They add inert pool registration/reset traversal, so “byte-for-byte/literally unchanged runtime” and cross-platform behavior are not claimed. No security can be created by gameplay yet, so this is Apple Silicon type/arithmetic/conservation proof rather than a native playable market.

## GameScript proof

The built OpenTTD script scanner discovered `Modern Tycoon Markets and News` v2 and `Modern Tycoon Test Company` v1 as API-15-compatible extensions.

Executed proof:

- a clean null-driver generated game started the script with four instruments;
- a 5,000-tick no-company run completed without a GameScript error;
- two first-party idle test companies each created a private Modern Tycoon Exchange Story Book page;
- a 150,000-tick seeded soak (more than five default calendar years) completed without a GameScript error or failed settlement;
- the developer smoke test bought a non-self security, credited a distribution, sold it, and reconciled cash, dividend accounting, holdings, and issued lots;
- the same conservation test passed with transaction fees set to zero, demonstrating that immediate impact trading no longer mints cash;
- an old v1 save migrated and reconstructed six instruments; a new v2 save reloaded without repeating the persisted developer self-test;
- merger handling now transfers the acquired portfolio, aggregates cost basis/results, and settles inherited self-shares; this path is scanner-proven but still needs an event-driven fixture;
- `git diff --check` passed after implementation.

The initial upstream Regression AI deliberately terminated itself with its excessive-CPU test. It was replaced for final soaks by the first-party idle test AI, so the final test surface contains no intentional AI failure.

## Curated content bridge

All twelve pinned NewGRFs in [`curated-playtest.example.cfg`](curated-playtest.example.cfg) were discovered with the expected content IDs and versions: FIRS, Iron Horse, Road Hog, FISH 2, av8, OpenGFX+ Landscape, OpenGFX Trees, Industrial Stations Renewal, OpenGFX+ Stations, OpenGFX+ Airports, Bigger Train Depot, and OpenGFX BigGUI. The 150,000-tick two-company soak passed with that set active.

The archives remain external test fixtures. This is loading/simulation proof, not visual approval or permission to redistribute them.

Iron Horse 4.14.1 emitted three `MapSpriteGroup` skipped-empty-spritegroup diagnostics during loading. The set remained active and the full soak completed; this is recorded as a content warning, not hidden or promoted to proof of a fork defect.

## macOS package and visual boundary

CPack generated a local arm64 `.app`/DMG candidate. Its binary executed after the extracted temporary app was cleaned of iCloud extended attributes and ad-hoc signed. The local Homebrew PNG/LZO deployment-target mismatch remains, and this artifact is not notarized or release-approved.

The OpenTTD SDL window appeared as a running `org.openttd.openttd` application, but repeated accessibility/screenshot capture attempts timed out. Therefore this report claims launch and headless simulation proof only. It does not claim visual approval of the Story Book exchange, newspaper, palettes, sprites, or curated content.

## Not yet claimed

- No existing player save has been opened with this fork.
- No live iCloud profile configuration has been activated or rewritten.
- The Story Book UI has not yet received a visual/manual QA pass.
- Native exchange commands, persistence, UI, multiplayer determinism, industry balance sheets, and new vehicle sprites remain planned work, not implemented features.
- Native pool uniqueness, issuer/holder deletion cascades, generation/ID reuse safety, pool-wide conservation, malformed-save validation, and supported-platform CI are not yet implemented or proven.

SPDX-License-Identifier: GPL-2.0-only
