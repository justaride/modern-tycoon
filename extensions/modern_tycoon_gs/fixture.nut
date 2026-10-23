/*
 * Developer fixture for the Modern Tycoon market lab (STATUS gate 1).
 *
 * Enabled only by the developer setting `developer_fixture`:
 *   1 = merger: the target company goes bankrupt and a test company buys it.
 *   2 = delist: the target company goes bankrupt and nobody buys it.
 *
 * It needs three companies (use modern_tycoon_test_ai; for the merger
 * scenario set accept_merger=1). Roles by company ID: investor = lowest,
 * middle = next, target = highest. It deliberately changes their money.
 * Never enable it in a normal game.
 *
 * Every check logs "MT-FIXTURE PASS <name>" or "MT-FIXTURE FAIL <name>",
 * and the run ends with "MT-FIXTURE COMPLETE ...". State is saved, so a
 * fixture survives save and reload in the middle of a scenario.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

MT_FIXTURE_MERGER <- 1;
MT_FIXTURE_DELIST <- 2;
MT_FIXTURE_TIMEOUT_MONTHS <- 14;

class MarketFixture {
    market = null;
    state = null;
    pre = null;   // Snapshot taken right before the merger/bankruptcy event is handled. Never saved.

    constructor(market, saved, scenario)
    {
        this.market = market;
        this.pre = null;
        this.state = saved != null ? saved : {
            scenario = scenario,
            step = 0,
            passed = 0,
            failed = 0,
            investor = -1,
            middle = -1,
            target = -1,
            industry = "",
            pending_month = -1,
            pending_target = 0,
            drained_month = -1,
            done = false
        };
        if (saved == null) GSLog.Info("MT-FIXTURE START scenario=" + this.ScenarioName());
        else GSLog.Info("MT-FIXTURE RESUME scenario=" + this.ScenarioName() + " step=" + this.state.step);
    }

    function ScenarioName()
    {
        return this.state.scenario == MT_FIXTURE_MERGER ? "merger" : "delist";
    }

    /* ------------------------------------------------------------ results */

    function Check(ok, name, detail)
    {
        if (ok) {
            this.state.passed++;
            GSLog.Info("MT-FIXTURE PASS " + name);
        } else {
            this.state.failed++;
            GSLog.Error("MT-FIXTURE FAIL " + name + ": " + detail);
        }
        return ok;
    }

    function Finish()
    {
        this.state.done = true;
        this.state.step = 99;
        GSLog.Info("MT-FIXTURE COMPLETE scenario=" + this.ScenarioName() + " passed=" + this.state.passed + " failed=" + this.state.failed);
    }

    /* ------------------------------------------------------------ helpers */

    function MonthKey()
    {
        local date = GSDate.GetCurrentDate();
        return GSDate.GetYear(date) * 12 + GSDate.GetMonth(date);
    }

    function Cash(company_id)
    {
        return GSCompany.GetBankBalance(company_id);
    }

    function SetCash(company_id, amount)
    {
        return GSCompany.ChangeBankBalance(company_id, amount - this.Cash(company_id), GSCompany.EXPENSES_OTHER, GSMap.TILE_INVALID);
    }

    function Instrument(id)
    {
        local index = this.market.FindInstrumentIndex(id);
        return index < 0 ? null : this.market.instruments[index];
    }

    function Lots(company_id, instrument_id)
    {
        local portfolio = this.market.GetPortfolio(company_id);
        if (portfolio == null || !portfolio.holdings.rawin(instrument_id)) return 0;
        return portfolio.holdings[instrument_id].lots;
    }

    function BuyCost(instrument)
    {
        local execution = instrument.price + this.market.MarketImpact(instrument.price);
        return execution + this.market.TransactionFee(execution);
    }

    function Snapshot(company_id, instrument)
    {
        local portfolio = this.market.GetPortfolio(company_id);
        return {
            cash = this.Cash(company_id),
            lots = this.Lots(company_id, instrument.id),
            issued = instrument.issued,
            price = instrument.price,
            realised = portfolio == null ? 0 : portfolio.realised
        };
    }

    function SameSnapshot(a, b)
    {
        return a.cash == b.cash && a.lots == b.lots && a.issued == b.issued && a.price == b.price && a.realised == b.realised;
    }

    function Describe(s)
    {
        return "cash=" + s.cash + " lots=" + s.lots + " issued=" + s.issued + " price=" + s.price;
    }

    function ValidCompanies()
    {
        local result = [];
        for (local company_id = GSCompany.COMPANY_FIRST; company_id < GSCompany.COMPANY_LAST; company_id++) {
            if (GSCompany.ResolveCompanyID(company_id) != GSCompany.COMPANY_INVALID) result.append(company_id);
        }
        return result;
    }

    /* Issued lots recomputed from holdings, independent of the market's own counter. */
    function CheckIssuedConservation(name)
    {
        local totals = {};
        foreach (company_key, portfolio in this.market.portfolios) {
            foreach (instrument_id, holding in portfolio.holdings) {
                if (!totals.rawin(instrument_id)) totals[instrument_id] <- 0;
                totals[instrument_id] += holding.lots;
            }
        }
        local ok = true, detail = "";
        foreach (instrument in this.market.instruments) {
            local expected = totals.rawin(instrument.id) ? totals[instrument.id] : 0;
            if (instrument.issued != expected) {
                ok = false;
                detail += instrument.id + " issued=" + instrument.issued + " holdings=" + expected + " ";
            }
        }
        foreach (instrument_id, total in totals) {
            if (this.market.FindInstrumentIndex(instrument_id) < 0) {
                ok = false;
                detail += instrument_id + " held but not listed ";
            }
        }
        return this.Check(ok, name, detail);
    }

    /* ------------------------------------------------------------- driver */

    function Tick()
    {
        if (this.state.done) return;

        switch (this.state.step) {
            case 0: this.StepRoles(); break;
            case 1: this.StepFundsRules(); break;
            case 2: this.StepHoldings(); break;
            case 3: this.StepPendingQueue(); break;
            case 4: this.StepPendingSettledAndDrain(); break;
            case 5: this.StepWaitForOutcome(); break;
        }
    }

    function StepRoles()
    {
        local companies = this.ValidCompanies();
        if (companies.len() < 3) return;
        local investor = companies[0], middle = companies[1], target = companies[companies.len() - 1];
        foreach (company_id in [investor, middle, target]) {
            if (this.Instrument("C:" + company_id) == null || this.market.GetPortfolio(company_id) == null) return;
        }
        local industry = null;
        foreach (instrument in this.market.instruments) {
            if (instrument.kind == MT_KIND_INDUSTRY) {
                industry = instrument;
                break;
            }
        }
        if (industry == null) return;

        this.state.investor = investor;
        this.state.middle = middle;
        this.state.target = target;
        this.state.industry = industry.id;
        GSLog.Info("MT-FIXTURE ROLES investor=" + investor + " middle=" + middle + " target=" + target + " industry=" + industry.id);
        this.state.step = 1;
    }

    /* Rule checks that must never move money, lots or prices. */
    function StepFundsRules()
    {
        local investor = this.state.investor;
        local other = this.Instrument("C:" + this.state.middle);
        local own = this.Instrument("C:" + investor);

        /* Insufficient funds: one unit short of the full buy cost. */
        local original_cash = this.Cash(investor);
        local cost = this.BuyCost(other);
        this.SetCash(investor, cost - 1);
        local before = this.Snapshot(investor, other);
        local bought = this.market.BuyOneLot(investor, other);
        local after = this.Snapshot(investor, other);
        this.Check(!bought && this.SameSnapshot(before, after) && after.cash == cost - 1,
            "insufficient_funds_rejected", "bought=" + bought + " before " + this.Describe(before) + " after " + this.Describe(after));
        this.SetCash(investor, original_cash);
        this.Check(this.Cash(investor) == original_cash, "insufficient_funds_cash_restored", "cash=" + this.Cash(investor) + " expected " + original_cash);

        /* Self-trade is refused even with plenty of cash. */
        this.SetCash(investor, original_cash + cost * 4);
        before = this.Snapshot(investor, own);
        bought = this.market.BuyOneLot(investor, own);
        after = this.Snapshot(investor, own);
        this.Check(!bought && this.SameSnapshot(before, after), "self_trade_rejected", "bought=" + bought + " " + this.Describe(after));

        /* Selling a lot you do not hold is refused. */
        before = this.Snapshot(investor, other);
        local sold = this.market.SellOneLot(investor, other);
        after = this.Snapshot(investor, other);
        this.Check(!sold && this.SameSnapshot(before, after), "sell_without_holding_rejected", "sold=" + sold + " " + this.Describe(after));
        this.SetCash(investor, original_cash);

        this.state.step = 2;
    }

    function Fund(company_id, amount)
    {
        if (this.Cash(company_id) < amount) this.SetCash(company_id, amount);
    }

    /* Investor and middle hold the target; the target holds the investor and an industry. */
    function StepHoldings()
    {
        local investor = this.state.investor, middle = this.state.middle, target = this.state.target;
        local target_equity = this.Instrument("C:" + target);
        local investor_equity = this.Instrument("C:" + investor);
        local industry = this.Instrument(this.state.industry);
        if (target_equity == null || investor_equity == null || industry == null) {
            this.Check(false, "setup_holdings", "an instrument disappeared before setup");
            this.Finish();
            return;
        }

        local ok = true;
        this.Fund(investor, this.BuyCost(target_equity) * 3);
        ok = this.market.BuyOneLot(investor, target_equity) && ok;
        ok = this.market.BuyOneLot(investor, target_equity) && ok;
        this.Fund(middle, this.BuyCost(target_equity) * 2);
        ok = this.market.BuyOneLot(middle, target_equity) && ok;
        this.Fund(target, this.BuyCost(investor_equity) + this.BuyCost(industry) * 2);
        ok = this.market.BuyOneLot(target, investor_equity) && ok;
        ok = this.market.BuyOneLot(target, industry) && ok;

        ok = ok && this.Lots(investor, target_equity.id) == 2 && this.Lots(middle, target_equity.id) == 1 &&
            this.Lots(target, investor_equity.id) == 1 && this.Lots(target, industry.id) == 1;
        this.Check(ok, "setup_holdings", "investor=" + this.Lots(investor, target_equity.id) + " middle=" + this.Lots(middle, target_equity.id) +
            " target_self=" + this.Lots(target, investor_equity.id) + " target_industry=" + this.Lots(target, industry.id));
        this.CheckIssuedConservation("setup_issued_matches_holdings");
        this.state.step = 3;
    }

    /* A failed payment is queued, a failed retry keeps it queued, and the monthly retry pays it. */
    function StepPendingQueue()
    {
        local target = this.state.target;
        local industry = this.Instrument(this.state.industry);
        local portfolio = this.market.GetPortfolio(target);
        local cash = this.Cash(target);
        local dividends = portfolio.dividends, pending = portfolio.pending_cash, pending_dividends = portfolio.pending_dividends;

        /* Only the target holds this industry, so exactly one payment of 7 is attempted. */
        this.market.settlement_faults = 1;
        this.market.CreditHolders(industry, 7);
        this.Check(this.market.settlement_faults == 0 && portfolio.pending_cash == pending + 7 &&
            portfolio.pending_dividends == pending_dividends + 7 && portfolio.dividends == dividends && this.Cash(target) == cash,
            "pending_settlement_queued", "pending=" + portfolio.pending_cash + " dividends=" + portfolio.dividends + " cash=" + this.Cash(target));

        this.market.settlement_faults = 1;
        this.market.RetryPendingCredits();
        this.Check(portfolio.pending_cash == pending + 7 && this.Cash(target) == cash,
            "pending_failed_retry_keeps_queue", "pending=" + portfolio.pending_cash + " cash=" + this.Cash(target));
        this.market.settlement_faults = 0;

        this.state.pending_target = dividends + 7;
        this.state.pending_month = this.MonthKey();
        this.state.step = 4;
    }

    function StepPendingSettledAndDrain()
    {
        if (this.MonthKey() == this.state.pending_month) return;

        local target = this.state.target;
        local portfolio = this.market.GetPortfolio(target);
        this.Check(portfolio != null && portfolio.pending_cash == 0 && portfolio.dividends == this.state.pending_target,
            "pending_settled_by_monthly_retry", portfolio == null ? "no portfolio" : "pending=" + portfolio.pending_cash + " dividends=" + portfolio.dividends);

        /* Push the target far enough into debt that the engine starts its bankruptcy process. */
        local max_loan = this.MaxLoanOf(target);
        this.SetCash(target, -(max_loan * 2 + 1000000));
        GSLog.Info("MT-FIXTURE DRAINED target=" + target + " cash=" + this.Cash(target) + " max_loan=" + max_loan);
        this.state.drained_month = this.MonthKey();
        this.state.step = 5;
    }

    /* The company mode object must be released before deity commands run again; returning releases it. */
    function MaxLoanOf(company_id)
    {
        local mode = GSCompanyMode(company_id);
        return GSCompany.GetMaxLoanAmount();
    }

    function StepWaitForOutcome()
    {
        if (this.MonthKey() - this.state.drained_month <= MT_FIXTURE_TIMEOUT_MONTHS) return;
        this.Check(false, "outcome_within_timeout", "no " + this.ScenarioName() + " event within " + MT_FIXTURE_TIMEOUT_MONTHS + " months");
        this.Finish();
    }

    /* ------------------------------------------------------ event checks */

    function BeforeEvent(event)
    {
        if (this.state.done || this.state.step != 5) return;
        local type = event.GetEventType();

        if (type == GSEvent.ET_COMPANY_MERGER) {
            local merger = GSEventCompanyMerger.Convert(event);
            if (merger.GetOldCompanyID() != this.state.target) return;
            if (this.state.scenario != MT_FIXTURE_MERGER) {
                this.Check(false, "no_unexpected_merger", "target was bought in the delist scenario");
                this.Finish();
                return;
            }
            this.pre = this.Capture(merger.GetNewCompanyID());
        } else if (type == GSEvent.ET_COMPANY_BANKRUPT) {
            if (GSEventCompanyBankrupt.Convert(event).GetCompanyID() != this.state.target) return;
            if (this.state.scenario != MT_FIXTURE_DELIST) {
                this.Check(false, "no_unexpected_bankruptcy", "target closed instead of being bought");
                this.Finish();
                return;
            }
            this.pre = this.Capture(GSCompany.COMPANY_INVALID);
        }
    }

    function AfterEvent(event)
    {
        if (this.pre == null) return;
        local pre = this.pre;
        this.pre = null;
        this.Verify(pre);
        this.Finish();
    }

    function CopyHoldings(portfolio)
    {
        local copy = {};
        if (portfolio == null) return copy;
        foreach (instrument_id, holding in portfolio.holdings) copy[instrument_id] <- { lots = holding.lots, cost_basis = holding.cost_basis };
        return copy;
    }

    function Capture(acquirer)
    {
        local snapshot = { acquirer = acquirer, cash = {}, holdings = {}, issued = {}, prices = {} };
        foreach (company_id in this.ValidCompanies()) {
            local key = company_id.tostring();
            snapshot.cash[key] <- this.Cash(company_id);
            snapshot.holdings[key] <- this.CopyHoldings(this.market.GetPortfolio(company_id));
        }
        snapshot.target_holdings <- this.CopyHoldings(this.market.GetPortfolio(this.state.target));
        foreach (instrument in this.market.instruments) {
            snapshot.issued[instrument.id] <- instrument.issued;
            snapshot.prices[instrument.id] <- instrument.price;
        }
        GSLog.Info("MT-FIXTURE EVENT " + (acquirer == GSCompany.COMPANY_INVALID ? "bankruptcy" : "merger into " + acquirer));
        return snapshot;
    }

    function HeldLots(holdings, instrument_id)
    {
        return holdings.rawin(instrument_id) ? holdings[instrument_id].lots : 0;
    }

    /* Same arithmetic as the market's merger settlement: one lot at a time, price impact per lot. */
    function ExpectedSelfProceeds(price, lots)
    {
        local proceeds = 0;
        local execution = price;
        for (local lot = 0; lot < lots; lot++) {
            execution = this.market.MaxValue(1, execution - this.market.MarketImpact(execution));
            proceeds += this.market.MaxValue(0, execution - this.market.TransactionFee(execution));
        }
        return proceeds;
    }

    function Verify(pre)
    {
        local target = this.state.target;
        local target_id = "C:" + target;
        local merger = pre.acquirer != GSCompany.COMPANY_INVALID;
        local final_price = pre.prices.rawin(target_id) ? pre.prices[target_id] : 0;

        this.Check(this.market.GetPortfolio(target) == null, "target_portfolio_removed", "target still has a portfolio");
        this.Check(this.Instrument(target_id) == null, "target_delisted", target_id + " is still listed");

        /* Expected cash per surviving company. */
        local ok = true, detail = "";
        foreach (company_key, cash_before in pre.cash) {
            local company_id = company_key.tointeger();
            if (company_id == target) continue;
            local expected = this.HeldLots(pre.holdings[company_key], target_id) * final_price;
            if (merger && company_id == pre.acquirer) {
                local self_id = "C:" + company_id;
                local self_lots = this.HeldLots(pre.target_holdings, self_id) + this.HeldLots(pre.holdings[company_key], self_id);
                if (self_lots > 0 && pre.prices.rawin(self_id)) expected += this.ExpectedSelfProceeds(pre.prices[self_id], self_lots);
            }
            local actual = this.Cash(company_id) - cash_before;
            GSLog.Info("MT-FIXTURE PAYOUT company=" + company_id + " received=" + actual + " expected=" + expected);
            if (actual != expected) {
                ok = false;
                detail += "company " + company_id + " got " + actual + " expected " + expected + "; ";
            }
            if (this.Lots(company_id, target_id) != 0) {
                ok = false;
                detail += "company " + company_id + " still holds the target; ";
            }
        }
        this.Check(ok, "delisted_holders_paid_final_quote", detail);

        local industry_id = this.state.industry;
        local industry = this.Instrument(industry_id);
        if (merger) {
            local acquirer_key = pre.acquirer.tostring();
            local expected_lots = this.HeldLots(pre.holdings[acquirer_key], industry_id) + this.HeldLots(pre.target_holdings, industry_id);
            this.Check(this.Lots(pre.acquirer, industry_id) == expected_lots, "merger_holdings_transferred",
                "acquirer holds " + this.Lots(pre.acquirer, industry_id) + " expected " + expected_lots);

            local self_id = "C:" + pre.acquirer;
            this.Check(this.Lots(pre.acquirer, self_id) == 0, "merger_self_shares_settled", "acquirer still holds " + this.Lots(pre.acquirer, self_id) + " own lots");

            local issued_ok = industry != null && industry.issued == pre.issued[industry_id];
            this.Check(issued_ok, "merger_industry_lots_conserved", industry == null ? "industry gone" : "issued=" + industry.issued + " before=" + pre.issued[industry_id]);
        } else {
            local released = this.HeldLots(pre.target_holdings, industry_id);
            local issued_ok = industry != null && industry.issued == pre.issued[industry_id] - released;
            this.Check(issued_ok, "deleted_company_lots_released", industry == null ? "industry gone" : "issued=" + industry.issued + " before=" + pre.issued[industry_id] + " released=" + released);
        }
        this.CheckIssuedConservation("final_issued_matches_holdings");
    }
}
