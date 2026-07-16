# Architecture and compatibility contract

## Core data model

The native market must not revive the removed four-block company-share mechanic. It needs independent identities, fine-grained units, sparse holdings, history, and explicit lifecycle behavior.

```cpp
struct EntityRef {
    EntityKind kind;
    uint32_t id;
    uint32_t generation;
};

struct FinancialPeriod {
    Money revenue;
    Money operating_cost;
    Money capex;
    Money interest;
    Money net_income;
    Money assets;
    Money debt;
    Money cash;
};

struct Security {
    SecurityID id;
    EntityRef issuer;
    ListingStatus status;
    uint32_t equity_units;       // 10,000 basis-point units
    int64_t price_fp;            // 1/256 Money precision
    int64_t fundamental_fp;
    uint32_t public_inventory;
    RingBuffer<PriceBar, 60> history;
};

struct Holding {
    SecurityID security;
    CompanyID holder;
    uint16_t units;
    int64_t average_cost_fp;
};
```

Use an independent `SecurityID`. Company and industry pool IDs can be deleted and reused, so an unqualified raw ID is not a durable issuer reference.

Industry finance is instance state, not part of `IndustrySpec`:

```cpp
struct IndustryEnterprise {
    EntityRef industry;
    Money cash;
    Money debt;
    Money retained_earnings;
    uint16_t capacity_index;
    uint16_t maintenance_index;
    SecurityID security;
};
```

Never reinterpret `Industry::owner` as equity ownership. Transport access, land ownership, exclusivity, and financial ownership are separate concepts.

## Deterministic update order

One declared economy-month boundary runs:

1. Close company and industry operating statistics.
2. Produce immutable finance snapshots.
3. Settle due contracts, interest, and distributions.
4. Recalculate security fundamentals and bounded quote movement.
5. Append price bars and structured world events.
6. Publish any scheduled newspaper edition.
7. Invalidate read-only GUI views.

Pricing uses integer/fixed-point math, stable ID-sorted iteration, and saturating/checked arithmetic. Trade impact never depends on UI order or the machine clock.

## Company Exchange MVP rules

- New-game setting: `equity_market = off | companies`; default off.
- Eligible companies receive 10,000 units.
- A deterministic market maker supplies initial public inventory.
- Company treasuries can buy competitor equity; self-trading is rejected.
- Initial holder cap: 25%; governance and takeover are deferred.
- Immediate settlement with a 1% spread and bounded price impact.
- Monthly fundamental target:

```text
target cap = max(minimum cap,
                 net company value
                 + clamp(6 x trailing-year profit,
                         -50% of net value,
                         +400% of net value))

monthly movement = 25% of the gap toward target,
                   capped to +/-10% before trade impact
```

- Store 60 monthly OHLCV bars.
- On deletion/bankruptcy: freeze, calculate recovery, pay holders in stable order, delist, then release references.
- Existing hostile-takeover behavior remains independent until a later governance design explicitly replaces it.

## Commands and conservation

All player mutations are `Cmd*` operations sent through the normal command queue. A trade command validates issuer status, holder, quantity, cap, inventory, available cash, checked settlement math, and feature state before execution.

For every successful trade:

```text
buyer cash decrease = gross consideration + fee
seller/market-maker cash increase = gross consideration
fee sink increase = fee
buyer holding increase = seller/public inventory decrease
```

The command must either update all legs or none.

The native MVP stores `market_maker_cash` per security and a saved exchange-wide `fee_reserve`; these are explicit conservation accounts, not implied sinks or sources. The displayed quote is the mid-price. Bid/ask use a full 1% spread (minus/plus 50 basis points, rounded against the trader) and the separate default 25-basis-point transaction fee is rounded up into `fee_reserve`. The fee may be configured to zero without enabling profitable wash trades.

## Save and network plan

Proposed table/sparse-table chunks:

| Chunk | Content |
| --- | --- |
| `MSEC` | Securities, listing lifecycle, quote, and bounded price history. |
| `MHLD` | Sparse holdings and cost bases. |
| `IFIN` | Listed-industry finance and capacity state. |
| `WEVT` | Bounded structured world-event journal. |
| `NPPR` | Immutable published editions, only if they cannot be regenerated safely. |

Each schema change adds a `SaveLoadVersion`. Old saves initialize missing data deterministically. New fork saves are not promised to load in an older unmodified binary.

The enabled ruleset and content signature belong in game-log and network compatibility evidence. Servers pin the fork revision and exact NewGRF hashes.

The exact source integration order, save-version fork policy, lifecycle funding, and first compile-only commit are specified in [NATIVE_MVP_FILEMAP.md](NATIVE_MVP_FILEMAP.md).

## Native Exchange acceptance criteria

- With the feature off, simulation results, UI availability, save behavior, and performance match baseline.
- Buy/sell executes only through synchronized commands.
- Cash, holding, public inventory, and fee deltas conserve exactly.
- Negative holdings, non-positive settlement prices, overflow, self-trading, cap violations, bankrupt issuers, and unaffordable orders are rejected.
- Quotes and histories are identical after save/load.
- A pre-market save initializes deterministically.
- A new-save round trip preserves every listing, holding, quote, and price bar.
- Company deletion and ID reuse leave no stale issuer or holder reference.
- Two-client dedicated scripted play for five economy years produces identical state hashes with no desync.
- Unit/property tests cover conservation, rounding, caps, deletion, and malformed commands.
- Regression tests cover old-save migration and new-save round trip.
- The UI works at 1x-4x scale, with long translations, RTL text, keyboard navigation, and non-color-only indicators.
- Disabled monthly cost is effectively zero; enabled cost remains below an agreed 1% simulation budget on benchmark saves.

## Structured events

```cpp
struct WorldEvent {
    uint64_t id;
    EconomyDate date;
    EventCategory category;
    EventSeverity severity;
    EntityRef source;
    CompanyMask audience;
    StringID template_id;
    TypedParameters parameters;
    References references;
    uint64_t dedupe_key;
};
```

The event stores facts and localization parameters, not a preformatted English paragraph. News windows, status bars, admin tools, scripts, and newspaper editions become consumers of the same record.

## Performance budgets

- Holdings are sparse; never allocate a company x maximum-industry matrix.
- Finance closes monthly, not per tick.
- Event and price histories are bounded.
- GUI builds cached view models and cannot scan every map tile.
- Deletion uses issuer-to-holding indexes rather than a global search where practical.
- Benchmark gates capture tick time, finance close time, publication time, save size/time, and peak memory.

SPDX-License-Identifier: GPL-2.0-only
