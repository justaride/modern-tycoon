# Native Company Exchange implementation map

This is the source-level handoff for Phase 2. It maps the architecture contract onto the current OpenTTD tree at baseline `5b9f18d8fd0a16f5022c0351b5e3590852d24745`.

The first native commit must be compile-only and unreachable from gameplay. It establishes types, deterministic arithmetic, conservation helpers, and tests without changing commands, settings, saves, timers, UI, or company lifecycle behavior.

## Commit 1: type and arithmetic spine

Add:

- `src/company_exchange_type.h`: `SecurityID`, `HoldingID`, `SecurityKind`, `ListingStatus`, `TradeSide`, the signed 64-bit 1/256-Money fixed-point contract, 10,000 equity units, 2,500-unit holder cap, and 100-unit initial UI lot.
- `src/company_exchange_base.h`: `SecurityPool`, `HoldingPool`, and their pool items. Persist aggregate `Money cost_basis`; derive display averages. Proportional sale allocation has an explicit remainder rule so cost basis cannot disappear through rounding.
- `src/company_exchange.cpp`: pool globals, `INSTANTIATE_POOL_METHODS`, and a deterministic linear `(SecurityID, CompanyID)` holding lookup. A company-only MVP is small enough that a correctness-sensitive cache is unnecessary.
- `src/company_exchange_func.h`: pure integer-only helpers for target market cap, per-unit fixed-point target, bounded monthly movement, bid/ask and fee calculation, settlement, proportional cost-basis allocation, and ledger conservation.
- `src/tests/company_exchange.cpp`: boundary and property-style tests for rounding, overflow rejection, caps, cost allocation, and conservation.

Register the core files in `src/CMakeLists.txt` and the test in `src/tests/CMakeLists.txt`.

Exit gate:

- feature is unreachable at runtime;
- no savegame or command number changes;
- feature-off behavior is literally unchanged;
- all existing tests plus the new pure tests pass on every supported platform.

## Commands and synchronized settlement

After the spine is accepted:

1. Append `BuySecurity` and `SellSecurity` immediately before `Commands::End` in `src/command_type.h`. Appending preserves existing command numbers.
2. Add `src/company_exchange_cmd.h` and `src/company_exchange_cmd.cpp`.
3. Include the command header from `src/command.cpp`, `src/network/network_command.cpp`, and the invoking GUI/script files.
4. Use `CommandType::MoneyManagement`. The synchronized intent contains only `SecurityID` and `uint16_t quantity`; holder, quote, spread, fee, and cash availability are derived inside the command.
5. Mutate only under `DoCommandFlag::Execute`. Buy returns a positive `CommandCost(ExpensesType::Other, ...)`; sell returns a negative one.

Validation covers feature state, valid listed security and issuer, self-trade, lot size, public inventory, 2,500-unit cap, holding quantity, maker liquidity, available company cash, checked arithmetic, and positive settlement price. GUI button state is a convenience and never the authority.

## Market accounts and quote contract

The native MVP uses explicit saved system accounts so trades never silently mint or destroy money:

- each `Security` owns `market_maker_cash` and `public_inventory`;
- one exchange-state record owns `fee_reserve` and the monotonic issuer-generation counter;
- listing creation seeds maker inventory and a deterministic liquidity reserve as an explicit opening-balance operation recorded in the game log;
- company-to-maker trades conserve company cash, maker cash, inventory, holdings, and fee reserve in one command;
- the fee reserve is not spendable in the MVP.

The displayed quote is a mid-price. The full spread is 1%: bid is the mid less 50 basis points rounded down; ask is the mid plus 50 basis points rounded up. A separate transaction fee is expressed in basis points, default 25, rounded up, and credited to `fee_reserve`. The setting can be zero; a zero-fee immediate round trip must still lose the spread and price impact rather than create cash.

If maker cash is insufficient for a sell, the command is rejected. Credit, delayed settlement, and external liquidity are later systems, not hidden MVP behavior.

## Monthly update

OpenTTD permits only one callback for a timer trigger/priority pair. Month/Company is already occupied in `src/economy.cpp`, so add `Priority::Securities` immediately after `Company` in `src/timer/timer_game_common.h` and register one Month/Securities callback in `company_exchange.cpp`.

The callback runs after company statistics, interest, and economy fluctuations. It iterates `Security::Iterate()` in pool-index order, uses only checked integer/fixed-point arithmetic and economy dates, applies the bounded fundamental move, closes the current OHLCV bar, and opens the next one.

Keep a securities-specific fixed 60-bar ring. Generic `HistoryData` aggregates 24 monthly points into quarters/years and does not satisfy the exchange contract.

Use `CalculateCompanyValue()` in `src/economy.cpp` for the non-recursive asset/cash/loan base and the four completed `old_economy` quarters for trailing profit. Do not add marked portfolio holdings to `CalculateCompanyValue()`: cross-holdings create valuation recursion and the function affects unrelated mechanics such as headquarters costs.

## Save/load

Add `src/saveload/company_exchange_sl.cpp` and register it in `src/saveload/CMakeLists.txt` and `src/saveload/saveload.cpp`.

| Chunk | Content |
| --- | --- |
| `MEXS` | Exchange fee reserve and monotonic issuer-generation counter. |
| `MSEC` | Security pool, lifecycle, issuer generation, quote, maker accounts, current bar, and 60 completed bars. |
| `MHLD` | Sparse holding pool, units, and aggregate cost basis. |

Register in that order. Use the table-backed pool pattern in `subsidy_sl.cpp`, the `CreateAtIndex` pattern in `autoreplace_sl.cpp`, and bounded-list validation patterns in `industry_sl.cpp`.

`AfterLoadCompanyExchange()` runs before scripts start and rejects invalid references, duplicate issuer listings, duplicate `(security, holder)` holdings, zero units or prices, invalid history head/count, self-holdings, cap violations, and any listing where public inventory plus held units is not 10,000.

Before writing these chunks, reserve a high fork-only save-version band and add a loader guard for the unsupported gap above the pinned upstream version. A sequential next number will eventually collide with upstream. Also document that registering empty chunks changes bytes even when the feature is off; behavioral compatibility, not byte-identical saves, is the enforceable default unless conditional chunk saving is added.

## Setting, listing, and lifecycle hooks

- Add `equity_market = off | companies` to `EconomySettings` in `src/settings_type.h` and `src/table/settings/economy_settings.ini` as a synchronized `NewgameOnly` setting with default Off.
- Create a listing at the end of `DoStartupNewCompany()` in `src/company_cmd.cpp`. Do not create it in the `Company` constructor, which also runs while loading.
- Use a saved monotonic generation value for every new issuer identity. `SecurityID` protects live holdings; the generation value lets structured events safely refer to deleted entities after raw company IDs are reused.
- Integrate freeze/settlement/delisting at the start of `ChangeOwnershipOfCompanyItems()` in `src/economy.cpp`, before the bankruptcy jackpot path. That function covers acquisition and bankruptcy deletion.

Acquisition transfers the acquired company's external portfolio to the buyer in stable HoldingID order, settles inherited self-holdings against maker accounts, and immediately sells only the units above the combined 25% cap at the captured recovery quote. Bankruptcy liquidates the dying company's external portfolio first. Issuer recovery is funded from the captured company estate plus its security's maker cash; if the pool is insufficient, all holders receive the same deterministic pro-rata recovery ratio with remainder assigned in stable HoldingID order.

After settlement, remove every holding in the dying security, delist/delete it, and only then permit company-ID reuse.

## First UI and API surfaces

The smallest native UI extends `CompanyWindow` in `src/company_gui.cpp` and its widget set in `src/widgets/company_widget.h` with quote, public inventory, local holding, and Buy/Sell 100-unit controls. Buttons only post commands.

The full directory then adds `src/company_exchange_gui.cpp/.h`, `src/widgets/company_exchange_widget.h`, a `WindowClass`, and a Companies-menu entry through `src/toolbar_gui.cpp`. `IndustryDirectoryWindow` is the sortable/scrollable table pattern. The first chart can subclass the private graph framework inside `src/graph_gui.cpp`, showing the latest 24 closes while retaining 60 in the save chunk.

Only after commands and save/load are stable, add read APIs and buy/sell wrappers to `src/script/api/script_company.hpp/.cpp`. Those wrappers become the deterministic scripted regression surface.

## Native release gates

- Command-level conservation includes company cash, maker cash, fee reserve, public inventory, and sparse holdings.
- Save-at-any-command-boundary is atomic because all legs are one native synchronized command.
- Old upstream saves deterministically initialize an empty exchange; new fork saves round-trip every pool item and bar.
- Deletion, acquisition, company-ID reuse, cap overage, insufficient maker liquidity, and malformed save data have explicit tests.
- A two-client dedicated game runs five economy years with identical state hashes and no desync.
- With the setting Off, simulation, UI, performance, and save-load behavior remain equivalent to baseline, subject to the documented empty-chunk byte boundary.

SPDX-License-Identifier: GPL-2.0-only
