# Modern Tycoon Markets and News

This GameScript is the first playable vertical slice of the Modern Tycoon fork. It runs on the supported OpenTTD GameScript API and prototypes economic rules before they are promoted into deterministic native C++ systems.

Version 3 provides:

- 1% company-equity lots with deterministic fundamental pricing;
- production-linked securities for individual industries;
- per-company portfolios with buy/sell buttons in Story Book;
- transaction fees, cost basis, realised/unrealised results, and dividends;
- quarterly industry distributions tied to transported cargo;
- **The Transport Ledger**, a structured newspaper (see below);
- deterministic share pricing ([pricing.nut](pricing.nut)): a smoothed fair value, a growth premium, a mean-reverting market mood with bounded noise, and reactions to quarterly results, losses, financial trouble and raw-industry output; the Ledger reports results that beat or miss expectations and each quarter's winners and losers;
- save/load support for listings, holdings, prices, pricing state, portfolios, the news journal and the edition archive;
- merger portfolio transfer, inherited self-share settlement, pending-credit retry, and v1/v2-save migration.

## The Transport Ledger

Producers record facts once in a bounded journal: a stable template ID, typed parameters, a section and a severity. They never store a finished paragraph, so old entries stay readable. An edition (monthly, quarterly, or only after major news; see the `news_frequency` setting) collects the unpublished facts, chooses a lead story (real news before routine reports), folds three or more similar reports into one line, and keeps at most four lines per section:

- **Markets**: listings, delistings, dividends, distributions and the exchange close (biggest riser and faller, in hundredths of a percent).
- **Companies**: new companies, financial trouble, bankruptcies, takeovers and company-value milestones.
- **Rival Watch**: fleet entries into new transport modes, fleet growth, and one rotating company profile per edition. Known rival AIs get a named desk through the `MT_RIVAL_DESKS` table in `news.nut` (Nordlys Air and a rail freight AI are pre-registered); every other company is profiled from its fleet. No AI depends on the newspaper.
- **Industry**: openings and closures.
- **Transport**: the company that delivered the most cargo last quarter.

The Story Book has a front page with the latest edition and an archive page with the last 12 leads. Pop-up news is limited to major events (takeovers, bankruptcies) and at most one edition notice per quarter; the old script showed a pop-up for every listing and payout. Editions are also written to the script log (`MT-LEDGER ...`) for headless review.

## Install for play testing

Place this directory under the active OpenTTD profile as `game/modern_tycoon`, start a new game, and select **Modern Tycoon Markets and News** in AI/Game Script settings. Open Story Book after a company is created to access its exchange page.

Only one GameScript can run in a game. This prototype therefore cannot run alongside Villages Is Villages or another GameScript.

## Prototype boundary

The script uses OpenTTD's deity-mode balance transfer API to settle trades and distributions. It is intentionally a market laboratory, not the final native exchange. It does not add voting rights, player-to-player limit orders, short selling, industry balance sheets, or takeover control. Those require synchronized C++ commands, native save chunks, and multiplayer state in the fork.

Industry distributions are a configurable world-economy reward linked to transported production; industries do not have native cash accounts in current OpenTTD.

GameScript balance commands and `Save()` are separate engine callbacks, so this laboratory cannot guarantee transaction-atomic saves taken between the cash command and the following script instructions. Tested saves are taken at a quiescent tick. Full save-at-any-instant accounting requires the native command and transaction-journal implementation described in the architecture plan.

## Tests

See [test/README.md](test/README.md). `test/market_test.sh all` runs the gate 1 merger and delisting fixtures, a ten-year newspaper run, schema 2 and 3 migration, the pricing and replay checks, and the original soak.

## Developer smoke test

The hidden `developer_self_test` setting is available when Script development tools are enabled. It performs one affordable non-self buy, a one-credit distribution, and a sell, then checks cash, dividend accounting, portfolio holdings, and issued-lot conservation. The setting defaults off and must never be enabled in a normal game because it intentionally mutates the test company's finances.

SPDX-License-Identifier: GPL-2.0-only
