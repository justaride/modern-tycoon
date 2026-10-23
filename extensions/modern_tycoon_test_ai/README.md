# Modern Tycoon test company

This non-random AI creates an otherwise idle transport company for deterministic market testing. Running two instances gives the GameScript stable issuers and investor portfolios without coupling the test to a route-building AI or its economic decisions.

It is test infrastructure, not player-facing AI. It does not build, borrow, rename, or mutate the world after startup.

The `accept_merger` setting (default off) makes it accept a takeover offer for a bankrupt company. The GameScript fixture in [`../modern_tycoon_gs/test`](../modern_tycoon_gs/test/README.md) uses it to drive a real engine merger.

SPDX-License-Identifier: GPL-2.0-only
