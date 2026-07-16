# Modern Tycoon Markets and News

This GameScript is the first playable vertical slice of the Modern Tycoon fork. It runs on the supported OpenTTD GameScript API and prototypes economic rules before they are promoted into deterministic native C++ systems.

Version 2 provides:

- 1% company-equity lots with deterministic fundamental pricing;
- production-linked securities for individual industries;
- per-company portfolios with buy/sell buttons in Story Book;
- transaction fees, cost basis, realised/unrealised results, and dividends;
- quarterly industry distributions tied to transported cargo;
- monthly or quarterly market news;
- a persistent global newspaper archive, **The Transport Ledger**;
- save/load support for listings, holdings, prices, portfolios, and the archive;
- merger portfolio transfer, inherited self-share settlement, pending-credit retry, and v1-save migration.

## Install for play testing

Place this directory under the active OpenTTD profile as `game/modern_tycoon`, start a new game, and select **Modern Tycoon Markets and News** in AI/Game Script settings. Open Story Book after a company is created to access its exchange page.

Only one GameScript can run in a game. This prototype therefore cannot run alongside Villages Is Villages or another GameScript.

## Prototype boundary

The script uses OpenTTD's deity-mode balance transfer API to settle trades and distributions. It is intentionally a market laboratory, not the final native exchange. It does not add voting rights, player-to-player limit orders, short selling, industry balance sheets, or takeover control. Those require synchronized C++ commands, native save chunks, and multiplayer state in the fork.

Industry distributions are a configurable world-economy reward linked to transported production; industries do not have native cash accounts in current OpenTTD.

GameScript balance commands and `Save()` are separate engine callbacks, so this laboratory cannot guarantee transaction-atomic saves taken between the cash command and the following script instructions. Tested saves are taken at a quiescent tick. Full save-at-any-instant accounting requires the native command and transaction-journal implementation described in the architecture plan.

## Developer smoke test

The hidden `developer_self_test` setting is available when Script development tools are enabled. It performs one affordable non-self buy, a one-credit distribution, and a sell, then checks cash, dividend accounting, portfolio holdings, and issued-lot conservation. The setting defaults off and must never be enabled in a normal game because it intentionally mutates the test company's finances.

SPDX-License-Identifier: GPL-2.0-only
