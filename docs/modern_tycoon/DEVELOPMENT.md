# Development and verification

## Repository truth

- Upstream remote: `https://github.com/OpenTTD/OpenTTD.git`
- Development branch: `codex/modern-economy-foundation`
- Initial base: upstream master `5b9f18d8fd0a16f5022c0351b5e3590852d24745` (`16.0-beta2-25` at checkout time).
- The existing iCloud OpenTTD directory is a live player profile, not source. Its saves, config, downloaded content, and secrets remain outside the development proof boundary.

The canonical source lives on local storage at `/Users/gabrielfreeman/src/OpenTTD`; the former iCloud development path is a lightweight symlink. Build output and temporary test profiles are not synced through iCloud.

## macOS prerequisites

```sh
brew install cmake ninja pkgconf libpng xz lzo
```

Build:

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build --parallel 10
```

Verify:

```sh
ctest --test-dir build --output-on-failure
git diff --check
```

Long scripted regression tests run actual null-driver games and can take materially longer than unit tests.

## Profile isolation

Do not launch a debug or modified build against the live iCloud profile first. Use a clean local config, generated map, OpenGFX, no AIs, no GameScript, and no NewGRFs. Prove these layers separately:

1. Build and unit tests.
2. Scripted upstream regressions.
3. Clean local launch/new game/save/reload.
4. Modern Tycoon GameScript launch and save/reload.
5. One curated content pack at a time.
6. Representative existing saves, copied into the test profile.
7. Multiplayer/dedicated determinism and soak.

The historical live profile contains many duplicate NewGRF versions and three past crashes in base-media/NewGRF loading. Total Bridge Renewal is excluded from the first compatibility set; this is a risk-control decision, not a proven root-cause claim.

## GameScript test contract

For `extensions/modern_tycoon_gs`:

- Script loads without compile/runtime errors on API 15 and current master.
- No-company and no-industry maps remain valid.
- Company creation creates one private exchange page.
- Buy/sell changes cash and holdings once per button event.
- Insufficient cash, self-trade, no inventory, and no holding are rejected.
- Monthly quote update is deterministic.
- Quarterly distributions reconcile with held lots.
- Company/industry deletion settles and removes holdings.
- Save/load preserves listings, holdings, cost basis, prices, pages, archive, and last processed month without paying a period twice.
- A five-year null-driver run completes without script errors or opcode starvation.

`extensions/modern_tycoon_test_ai` supplies idle, non-random test companies for this contract. Copy or link both extension directories into the executable's `game` and `ai` search paths, then use [`soak-test.example.cfg`](soak-test.example.cfg) with a clean profile. This fixture isolates market behavior from route-building AI behavior.

## Content compatibility matrix

Each NewGRF test row records:

```text
content ID and exact hash
version and source URL
license/source availability
role and load order
new-game result
save/reload result
10-year fast-forward result
known conflicts
performance notes
visual evidence
```

Choose one version per duplicate family. Installed archives are test fixtures only; do not modify or redistribute them without source and license confirmation.

## Upstream boundary

Official OpenTTD's contribution guide explicitly rejects AI-generated code and automated issues/PRs. Do not open an upstream issue or pull request containing this work. A future human maintainer may independently design, author, understand, test, and discuss a narrowly scoped API change with upstream, but that is a separate workflow.

SPDX-License-Identifier: GPL-2.0-only
