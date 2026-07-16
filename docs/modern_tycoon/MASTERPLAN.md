# Modern Tycoon masterplan

## Product promise

Modern Tycoon should feel like OpenTTD grew continuously into a present-day transport, infrastructure, and economic simulation without losing the clarity, scale, mod support, deterministic multiplayer, or fast construction loop that make OpenTTD special.

Four presets keep the project legible:

| Preset | Purpose |
| --- | --- |
| Classic | Upstream-compatible rules and UI behavior wherever possible. |
| Modern | Exchange, richer news, modern UX, and the first-party vehicle/content family. |
| Simulation | Industry finance, contracts, credit, commodity cycles, maintenance, energy, emissions, and policy events. |
| Custom | Explicit control over each independent system. |

The default upstream experience must remain available. New simulation systems are not allowed to silently alter a Classic game.

## Product pillars

### 1. Companies become real enterprises

- Company exchange with listings, portfolios, price history, dividends, public float, and deterministic settlement.
- Bonds and credit ratings after equity is proven.
- Shareholder concentration, governance, and takeovers only after the accounting and deletion rules are robust.
- Better finance dashboards: operating margin, capital expenditure, asset utilization, debt coverage, and mode-level performance.

### 2. Industries become economic actors

- Per-industry accounts separate from the NewGRF industry type definition.
- Revenue, operating cost, maintenance, retained earnings, debt, capacity, distress, and closure.
- Listed industry securities and infrastructure investment.
- Freight tenders, service-level contracts, exclusivity, penalties, and capacity upgrades.
- Ownership never grants transport access by itself and never overwrites NewGRF-controlled production.

### 3. The world explains itself

- A structured world-event journal records facts once.
- A newspaper publisher groups events into readable editions with business, transport, industry, technology, local, and incident sections.
- Archive, search, filters, entity/map links, charts, deduplication, and audience controls.
- Generated text stays template-driven and deterministic. Runtime LLM calls are out of scope for simulation and multiplayer.

### 4. Transport spans history to a plausible future

- Rail: steam, diesel, electric, battery, hydrogen, high-speed, metro, tram, maglev, and post-2050 concepts.
- Road: buses, coaches, vans, trucks, trolleybuses, trams, electric/autonomous generations, and specialist cargo vehicles.
- Water: coastal, river, ferry, Ro-Ro, bulk, container, tanker, tug/barge, hydrofoil, and future low-carbon vessels.
- Air: piston, turboprop, jet, cargo, regional, helicopter, airship, electric/hybrid, and carefully bounded future concepts.
- Real vehicles use original, license-cleared representations. Fictional brands become the default where trademarks, liveries, or design rights are uncertain.

### 5. The game looks and feels current

- Scalable, information-dense tables and dashboards rather than oversized decorative UI.
- Search, keyboard navigation, accessible color palettes, good long-string/RTL behavior, and 1x-4x UI validation.
- Consistent 8-bpp fallback plus 32-bpp normal/2x/4x sprites where supported.
- A coherent isometric camera, scale, lighting, company-color mask, animation, and shadow standard.
- Native renderer work is evidence-led; a full 3D rewrite is not a prerequisite for modern visuals.

### 6. Smoothness is measured

- Stable benchmark saves for small, large, and extreme networks.
- Frame, tick, pathfinder, link-graph, industry, finance, event, save/load, and memory budgets.
- Incremental ledgers and bounded archives; no full-map or company-by-industry scans every tick.
- Multiplayer soak tests and state-hash checks for every simulation milestone.

## Delivery architecture

```text
Company and industry simulation
             |
             v
      Finance snapshots
             |
             v
      Securities engine <---- synchronized player commands
             |
             v
    Structured event journal
             |
             +----> Newspaper and archive
             +----> Exchange/company/industry dashboards

NewGRF/NML packs ----> vehicles, cargos, industries, buildings, sounds
OpenGFX2 workstream --> base sprites, 32-bpp and extra zoom assets
```

## Phases and release gates

### Phase 0: Development spine

Deliverables:

- Reproducible upstream build and unit/regression baseline.
- Separate development profile; live iCloud saves remain read-only.
- Feature preset and compatibility policy.
- Benchmark saves, performance capture, deterministic-math helpers, and CI fixtures.
- Asset provenance manifest and content ID policy.

Exit gate: vanilla master builds; unit and regression tests pass; a clean generated world runs and saves from the isolated profile; updating from upstream is documented.

### Phase 1: Market laboratory (GameScript)

Deliverables:

- Company and individual-industry instruments.
- Per-company Story Book exchange pages.
- Buy/sell settlement, fees, cost basis, realised/unrealised result, and distributions.
- Persistent Transport Ledger archive and market news.
- Save/load round-trip and clean game smoke test.

Exit gate: two companies can trade for five game years without script errors; holdings and prices survive save/load; cash and lots reconcile; a delisted issuer leaves no stale holding.

### Phase 2: Native Company Exchange MVP

Deliverables:

- `SecurityID` pool, public inventory, sparse holdings, monthly OHLCV history.
- Deterministic integer/fixed-point valuation.
- Network commands for buy/sell only; no GUI-side mutation.
- Native exchange list/detail/chart and company investor view.
- `MSEC` and `MHLD` save chunks, old-save initialization, deletion settlement, and API read surfaces.

Exit gate: see the native exchange acceptance criteria in [ARCHITECTURE.md](ARCHITECTURE.md).

### Phase 3: Structured newspaper

Deliverables:

- Saved `WorldEvent` records with typed parameters and references.
- Bounded journal, aggregation, severity, dedupe, audience, sections, archive, and filters.
- Migration of company, economy, industry, vehicle, technology, subsidy, and incident news producers.
- Stable template IDs so old saved editions remain readable.

Exit gate: one simulated decade produces useful, non-spammy editions; save/load preserves the journal; filtering never changes simulation state.

### Phase 4: Listed industries

Deliverables:

- Sparse `IndustryEnterprise` financial state keyed through generation-safe references.
- Monthly P&L, cash, debt, maintenance, capacity, retained earnings, distress, and liquidation.
- Equity, dividends, investment, and native industry finance view.
- Explicit interoperability with vanilla and NewGRF industry production callbacks.

Exit gate: vanilla and representative FIRS/XIS games complete a ten-year deterministic soak; closures and industry ID reuse leave no stale security or contract.

### Phase 5: Contracts and investment

Deliverables:

- Freight tenders, qualifying routes, service-level measurement, penalties, renewal, and termination.
- Industry capacity/maintenance projects and municipal/public infrastructure contracts.
- Contract browser, bid workflow, vehicle/order links, and news coverage.

### Phase 6: Living economy

Deliverables:

- Cargo price indices, demand cycles, variable credit, bonds, fuel/energy cost, optional emissions, and policy events.
- Every subsystem independently switchable and represented in the game log/network signature.

### Phase 7: Vehicle generations and art

This workstream begins during Phase 0 and releases incrementally.

- A first-party modular NML family for trains, road vehicles, ships, and aircraft.
- Eras: `historical`, `contemporary`, `near_future`, and `speculative`.
- Fictional future introduction year configurable, default 2050.
- Consistent stats, running/maintenance cost, reliability, loading, cargo/refit, and sprite standards.
- Source art, license/provenance, and automated bounds/clipping checks retained for every asset.

### Phase 8: UX, rendering, and performance

- Cross-game navigation and information architecture pass.
- High-DPI dashboards, search, keyboard control, accessible charts, and scalable tables.
- Profiling-guided renderer/blitter, pathfinder, link graph, UI invalidation, save, and simulation improvements.
- GPU work only where profiles show a clear benefit without fragmenting platform support.

## Non-negotiable acceptance rules

- No simulation mutation occurs outside a synchronized command or declared deterministic periodic update.
- No platform-sensitive floating point, wall clock, OS randomness, unordered iteration, or client-only cache may affect game state.
- Every persistent field has reset, save, load, old-save initialization, deletion, and network behavior.
- Feature-off Classic behavior is covered by regression and performance checks.
- Installed third-party NewGRFs are test inputs, never source material unless their licenses and source permit derivatives.
- Original Transport Tycoon Deluxe graphics are not redistributed.
- A binary release includes corresponding GPL source and an asset provenance report.

## Current first slice

The initial GameScript lives at [`extensions/modern_tycoon_gs`](../../extensions/modern_tycoon_gs/README.md). It intentionally validates rules and UX cheaply before native state is added. Its virtual ledger is not the final C++ ownership model.

The first native Phase 2 spine is also present: typed security/holding pools and pure checked valuation/settlement/conservation helpers with focused tests. It is intentionally unreachable—there are no exchange commands, settings, save chunks, timers, or GUI hooks yet. The exact next-file map is in [NATIVE_MVP_FILEMAP.md](NATIVE_MVP_FILEMAP.md).

Primary upstream references:

- <https://github.com/OpenTTD/OpenTTD/blob/master/CONTRIBUTING.md>
- <https://github.com/OpenTTD/OpenTTD/blob/master/COMPILING.md>
- <https://github.com/OpenTTD/OpenTTD/blob/master/docs/desync.md>
- <https://github.com/OpenTTD/OpenTTD/blob/master/docs/savegame_format.md>
- <https://wiki.openttd.org/en/Development/NewGRF/>
- <https://github.com/OpenTTD/OpenGFX2>

SPDX-License-Identifier: GPL-2.0-only
