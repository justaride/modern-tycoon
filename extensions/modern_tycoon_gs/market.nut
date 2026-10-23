MT_KIND_COMPANY <- 0;
MT_KIND_INDUSTRY <- 1;
MT_MAX_COMPANY_FLOAT <- 80;
MT_MAX_INDUSTRY_FLOAT <- 100;
MT_MIN_COMPANY_LOT_PRICE <- 1000;
MT_INDUSTRY_BASE_PRICE <- 50000;

class ModernMarket {
    instruments = null;
    portfolios = null;
    news = null;
    last_month_key = -1;
    newspaper_page = -1;
    newspaper_body = -1;
    self_test_done = false;
    is_fresh = true;
    price_seed = 0;         // Seed for the deterministic price noise; drawn once, then saved.
    settlement_faults = 0;  // Test seam: number of upcoming credits to fail on purpose. Never saved.

    constructor(saved_state)
    {
        this.instruments = [];
        this.portfolios = {};
        this.last_month_key = -1;
        this.newspaper_page = -1;
        this.newspaper_body = -1;
        this.self_test_done = false;
        this.is_fresh = saved_state == null;
        this.settlement_faults = 0;
        this.price_seed = (saved_state != null && saved_state.rawin("price_seed"))
            ? saved_state.price_seed : GSBase.RandRange(0x7FFFFFFF);

        if (saved_state == null) {
            this.news = TransportLedger(null, null);
            return;
        }
        if (saved_state.rawin("instruments")) this.instruments = saved_state.instruments;
        if (saved_state.rawin("portfolios")) this.portfolios = saved_state.portfolios;
        if (saved_state.rawin("news")) {
            this.news = TransportLedger(saved_state.news, null);
        } else {
            /* Schema 1/2: carry the old finished headlines into the archive. */
            this.news = TransportLedger(null, saved_state.rawin("headlines") ? saved_state.headlines : null);
        }
        if (saved_state.rawin("last_month_key")) this.last_month_key = saved_state.last_month_key;
        GSLog.Info("Modern Tycoon loaded " + this.instruments.len() + " saved instruments (schema " +
            (saved_state.rawin("schema") ? saved_state.schema : 1) + ")");
        if (saved_state.rawin("newspaper_page")) this.newspaper_page = saved_state.newspaper_page;
        if (saved_state.rawin("newspaper_body")) this.newspaper_body = saved_state.newspaper_body;
        this.self_test_done = saved_state.rawin("self_test_done") ? saved_state.self_test_done : true;
    }

    function Initialise()
    {
        this.EnsureStoredSchema();
        this.RemoveInvalidPortfolios();
        this.RemoveInvalidInstruments();
        this.RefreshUniverse();
        this.ReconcileIssuedLots();
        this.news.EnsurePages(this.newspaper_page, this.newspaper_body);
        this.newspaper_page = -1;
        this.newspaper_body = -1;
        this.EnsureAllPortfolios();
        this.RefreshAllPages();

        if (this.last_month_key < 0) {
            local date = GSDate.GetCurrentDate();
            this.last_month_key = GSDate.GetYear(date) * 12 + GSDate.GetMonth(date);
        }

        if (this.news.rivals.len() == 0) this.news.ObserveRivals(true);
        if (this.is_fresh) {
            this.news.Record("markets", MT_SEV_MAJOR, "exchange_open", [this.instruments.len()], GSNews.NR_NONE, 0, null, false);
            this.news.PublishEdition(true);
        }
        this.news.RefreshPages();
        this.news.LogStats("start");
        GSLog.Info("Modern Tycoon initialised with " + this.instruments.len() + " instruments");
    }

    function GetSaveData()
    {
        return {
            schema = 4,
            price_seed = this.price_seed,
            instruments = this.instruments,
            portfolios = this.portfolios,
            news = this.news.GetSaveData(),
            last_month_key = this.last_month_key,
            self_test_done = this.self_test_done
        };
    }

    function Tick()
    {
        this.MaybeRunSelfTest();

        local date = GSDate.GetCurrentDate();
        local month = GSDate.GetMonth(date);
        local month_key = GSDate.GetYear(date) * 12 + month;
        if (month_key == this.last_month_key) return;

        this.last_month_key = month_key;
        this.RetryPendingCredits();
        this.RemoveInvalidPortfolios();
        this.RemoveInvalidInstruments();
        this.RefreshUniverse();
        this.EnsureAllPortfolios();
        this.UpdatePrices();

        if (month == 1) this.news.LogStats("year=" + (GSDate.GetYear(date) - 1));
        local quarter_start = ((month - 1) % 3) == 0;
        if (quarter_start) this.PayQuarterlyDistributions();
        this.RecordMarketClose();
        this.news.ObserveCargo();
        this.news.ObserveRivals(false);
        this.MaybePublishEdition(quarter_start);
        this.RefreshAllPages();
    }

    /* news_frequency: 2 = monthly editions, 1 = quarterly, 0 = only when something major happened. */
    function MaybePublishEdition(quarter_start)
    {
        local frequency = GSController.GetSetting("news_frequency");
        local major = this.news.HasUnpublishedMajor();
        local due = major || frequency == 2 || (frequency == 1 && quarter_start);
        if (!due) return;
        /* Pop up at most once a quarter unless the edition leads with a major story. */
        this.news.PublishEdition(major || quarter_start);
    }

    function HandleEvent(event)
    {
        local event_type = event.GetEventType();
        /* The newspaper reads names before the market removes the company or industry. */
        this.news.HandleEvent(event, this);
        if (event_type == GSEvent.ET_STORYPAGE_BUTTON_CLICK) {
            local click = GSEventStoryPageButtonClick.Convert(event);
            this.HandleButton(click.GetCompanyID(), click.GetElementID());
            return;
        }

        if (event_type == GSEvent.ET_COMPANY_MERGER) {
            local merger = GSEventCompanyMerger.Convert(event);
            this.MergePortfolios(merger.GetOldCompanyID(), merger.GetNewCompanyID());
            this.RemoveInvalidPortfolios();
            this.RemoveInvalidInstruments();
            this.RefreshUniverse();
            this.EnsureAllPortfolios();
            this.RefreshAllPages();
            return;
        }

        if (event_type == GSEvent.ET_COMPANY_IN_TROUBLE) {
            this.ReactToTrouble(GSEventCompanyInTrouble.Convert(event).GetCompanyID());
            return;
        }

        if (event_type == GSEvent.ET_COMPANY_NEW ||
                event_type == GSEvent.ET_COMPANY_BANKRUPT ||
                event_type == GSEvent.ET_INDUSTRY_OPEN ||
                event_type == GSEvent.ET_INDUSTRY_CLOSE ||
                event_type == GSEvent.ET_COMPANY_RENAMED) {
            this.RemoveInvalidPortfolios();
            this.RemoveInvalidInstruments();
            this.RefreshUniverse();
            this.EnsureAllPortfolios();
            this.RefreshAllPages();
        }
    }

    function HandleButton(company_id, element_id)
    {
        if (!this.IsValidCompany(company_id)) return;
        local portfolio = this.GetPortfolio(company_id);
        if (portfolio == null || this.instruments.len() == 0) return;

        if (element_id == portfolio.previous_button) {
            portfolio.selected--;
            if (portfolio.selected < 0) portfolio.selected = this.instruments.len() - 1;
        } else if (element_id == portfolio.next_button) {
            portfolio.selected++;
            if (portfolio.selected >= this.instruments.len()) portfolio.selected = 0;
        } else if (element_id == portfolio.buy_button) {
            this.BuyOneLot(company_id, this.instruments[portfolio.selected]);
        } else if (element_id == portfolio.sell_button) {
            this.SellOneLot(company_id, this.instruments[portfolio.selected]);
        } else if (element_id != portfolio.refresh_button) {
            return;
        }

        this.RefreshPortfolioPage(company_id);
    }

    function RefreshUniverse()
    {
        if (GSController.GetSetting("company_market")) {
            for (local company_id = GSCompany.COMPANY_FIRST; company_id < GSCompany.COMPANY_LAST; company_id++) {
                if (!this.IsValidCompany(company_id)) continue;
                local instrument_id = "C:" + company_id;
                local instrument_index = this.FindInstrumentIndex(instrument_id);
                if (instrument_index >= 0) {
                    this.instruments[instrument_index].name = this.GetCompanyName(company_id);
                    continue;
                }
                local price = this.CompanyFundamentalPrice(company_id);
                this.instruments.append({
                    id = instrument_id,
                    kind = MT_KIND_COMPANY,
                    object_id = company_id,
                    name = this.GetCompanyName(company_id),
                    price = price,
                    previous_price = price,
                    issued = 0,
                    metric = 0,
                    fair = price,
                    fundamental = price,
                    sentiment = 0,
                    shock = 0,
                    expected = 0,
                    has_expected = false,
                    quarter_open = price
                });
                this.news.Record("markets", MT_SEV_NORMAL, "company_listed", [this.GetCompanyName(company_id), price], GSNews.NR_NONE, 0, null, false);
            }
        }

        if (GSController.GetSetting("industry_market")) {
            local listed_industries = this.CountIndustryInstruments();
            local maximum = GSController.GetSetting("max_industries");
            local industry_list = GSIndustryList();
            foreach (industry_id, unused in industry_list) {
                if (listed_industries >= maximum) break;
                local instrument_id = "I:" + industry_id;
                local instrument_index = this.FindInstrumentIndex(instrument_id);
                if (instrument_index >= 0) {
                    this.instruments[instrument_index].name = this.GetIndustryName(industry_id);
                    continue;
                }
                local metric = this.GetIndustryTransportMetric(industry_id);
                local price = this.IndustryFundamentalPrice(industry_id);
                this.instruments.append({
                    id = instrument_id,
                    kind = MT_KIND_INDUSTRY,
                    object_id = industry_id,
                    name = this.GetIndustryName(industry_id),
                    price = price,
                    previous_price = price,
                    issued = 0,
                    metric = metric,
                    quarter_metric = 0,
                    fair = price,
                    fundamental = price,
                    sentiment = 0,
                    shock = 0,
                    expected = 0,
                    has_expected = false,
                    quarter_open = price
                });
                listed_industries++;
                this.news.Record("markets", MT_SEV_MINOR, "industry_listed", [this.GetIndustryName(industry_id)], GSNews.NR_INDUSTRY, industry_id, null, false);
            }
        }

        this.instruments.sort(function(a, b) {
            if (a.kind != b.kind) return a.kind < b.kind ? -1 : 1;
            return a.object_id < b.object_id ? -1 : (a.object_id > b.object_id ? 1 : 0);
        });
    }

    function RemoveInvalidInstruments()
    {
        for (local index = this.instruments.len() - 1; index >= 0; index--) {
            local instrument = this.instruments[index];
            local valid = instrument.kind == MT_KIND_COMPANY
                ? this.IsValidCompany(instrument.object_id)
                : GSIndustry.IsValidIndustry(instrument.object_id);
            if (valid) continue;

            this.LiquidateInstrument(instrument);
            this.news.Record("markets", instrument.kind == MT_KIND_COMPANY ? MT_SEV_MAJOR : MT_SEV_NORMAL, "delisted",
                [instrument.name, instrument.price], GSNews.NR_NONE, 0, null, false);
            this.instruments.remove(index);
        }
    }

    function LiquidateInstrument(instrument)
    {
        foreach (company_key, portfolio in this.portfolios) {
            if (!portfolio.holdings.rawin(instrument.id)) continue;
            local holding = portfolio.holdings[instrument.id];
            local company_id = company_key.tointeger();
            local proceeds = holding.lots * instrument.price;
            if (this.IsValidCompany(company_id) && proceeds > 0) {
                this.CreditOrQueue(company_id, portfolio, proceeds, 0, proceeds - holding.cost_basis);
            }
            delete portfolio.holdings[instrument.id];
        }
    }

    /* Monthly quotes; the model is described in pricing.nut. */
    function UpdatePrices()
    {
        local date = GSDate.GetCurrentDate();
        local month_key = GSDate.GetYear(date) * 12 + GSDate.GetMonth(date);
        local quarter_start = ((GSDate.GetMonth(date) - 1) % 3) == 0;
        foreach (instrument in this.instruments) {
            instrument.previous_price = instrument.price;
            if (instrument.kind == MT_KIND_COMPANY) {
                instrument.name = this.GetCompanyName(instrument.object_id);
            } else {
                instrument.name = this.GetIndustryName(instrument.object_id);
                instrument.metric = this.GetIndustryTransportMetric(instrument.object_id);
                instrument.quarter_metric += instrument.metric;
            }
            local fundamental = this.FundamentalOf(instrument);
            this.EnsurePricingState(instrument, fundamental);
            if (instrument.kind == MT_KIND_COMPANY) {
                if (quarter_start) this.ReactToResults(instrument);
            } else {
                this.ReactToProduction(instrument);
            }
            this.MovePrice(instrument, fundamental, month_key);
        }
        if (quarter_start) this.RecordQuarterMovers();
    }

    function CompanyFundamentalPrice(company_id)
    {
        local value = GSCompany.GetQuarterlyCompanyValue(company_id, GSCompany.CURRENT_QUARTER);
        if (value < 0) value = 0;

        local trailing_profit = 0;
        for (local quarter = GSCompany.CURRENT_QUARTER; quarter <= GSCompany.CURRENT_QUARTER + 4; quarter++) {
            local income = GSCompany.GetQuarterlyIncome(company_id, quarter);
            local expenses = GSCompany.GetQuarterlyExpenses(company_id, quarter);
            if (income >= 0 && expenses <= 0) trailing_profit += income + expenses;
        }

        local profit_component = trailing_profit * 6;
        profit_component = this.Clamp(profit_component, -(value / 2), value * 4);
        local market_cap = this.MaxValue(MT_MIN_COMPANY_LOT_PRICE * 100, value + profit_component);
        return this.MaxValue(MT_MIN_COMPANY_LOT_PRICE, market_cap / 100);
    }

    function IndustryFundamentalPrice(industry_id)
    {
        local metric = this.GetIndustryTransportMetric(industry_id);
        local production = this.GetIndustryProductionMetric(industry_id);
        return this.MaxValue(1000, MT_INDUSTRY_BASE_PRICE + production * 50 + metric * 100);
    }

    function GetIndustryProductionMetric(industry_id)
    {
        if (!GSIndustry.IsValidIndustry(industry_id)) return 0;
        local total = 0;
        local industry_type = GSIndustry.GetIndustryType(industry_id);
        foreach (cargo_id, unused in GSIndustryType.GetProducedCargo(industry_type)) {
            local amount = GSIndustry.GetLastMonthProduction(industry_id, cargo_id);
            if (amount > 0) total += amount;
        }
        return total;
    }

    function GetIndustryTransportMetric(industry_id)
    {
        if (!GSIndustry.IsValidIndustry(industry_id)) return 0;
        local total = 0;
        local industry_type = GSIndustry.GetIndustryType(industry_id);
        foreach (cargo_id, unused in GSIndustryType.GetProducedCargo(industry_type)) {
            local amount = GSIndustry.GetLastMonthTransported(industry_id, cargo_id);
            if (amount > 0) total += amount;
        }
        return total;
    }

    function PayQuarterlyDistributions()
    {
        foreach (instrument in this.instruments) {
            if (instrument.kind == MT_KIND_COMPANY) {
                if (instrument.issued > 0) this.PayCompanyDividend(instrument);
            } else {
                if (instrument.issued > 0) {
                    this.PayIndustryDistribution(instrument);
                } else {
                    instrument.quarter_metric = 0;
                }
            }
        }
    }

    function PayCompanyDividend(instrument)
    {
        local company_id = instrument.object_id;
        if (!this.IsValidCompany(company_id)) return;
        local income = GSCompany.GetQuarterlyIncome(company_id, GSCompany.CURRENT_QUARTER + 1);
        local expenses = GSCompany.GetQuarterlyExpenses(company_id, GSCompany.CURRENT_QUARTER + 1);
        if (income < 0 || expenses > 0) return;
        local profit = income + expenses;
        if (profit <= 0) return;

        local per_lot = (profit * GSController.GetSetting("company_dividend_percent")) / 10000;
        if (per_lot <= 0) return;

        local available = GSCompany.GetBankBalance(company_id);
        local reserve = this.MaxValue(100000, (-expenses) * 2);
        local maximum_total = this.MaxValue(0, available - reserve);
        local total = per_lot * instrument.issued;
        if (total > maximum_total) {
            per_lot = maximum_total / instrument.issued;
            total = per_lot * instrument.issued;
        }
        if (total <= 0) return;
        if (!GSCompany.ChangeBankBalance(company_id, -total, GSCompany.EXPENSES_OTHER, GSMap.TILE_INVALID)) return;

        this.CreditHolders(instrument, per_lot);
        this.news.Record("markets", MT_SEV_MINOR, "dividend", [instrument.name, per_lot], GSNews.NR_NONE, 0, null, false);
    }

    function PayIndustryDistribution(instrument)
    {
        local quarter_metric = instrument.quarter_metric;
        instrument.quarter_metric = 0;
        local per_lot = (quarter_metric * GSController.GetSetting("industry_yield_per_unit")) / 100;
        if (per_lot <= 0) return;
        this.CreditHolders(instrument, per_lot);
        this.news.Record("markets", MT_SEV_MINOR, "distribution", [instrument.name, per_lot, quarter_metric], GSNews.NR_INDUSTRY, instrument.object_id, null, false);
    }

    function CreditHolders(instrument, per_lot)
    {
        foreach (company_key, portfolio in this.portfolios) {
            if (!portfolio.holdings.rawin(instrument.id)) continue;
            local company_id = company_key.tointeger();
            if (!this.IsValidCompany(company_id)) continue;
            local payment = portfolio.holdings[instrument.id].lots * per_lot;
            if (payment <= 0) continue;
            this.CreditOrQueue(company_id, portfolio, payment, payment, 0);
        }
    }

    function BuyOneLot(company_id, instrument)
    {
        if (instrument.kind == MT_KIND_COMPANY && instrument.object_id == company_id) {
            this.PublishPrivate(company_id, "Exchange rule: companies cannot trade their own shares.");
            return false;
        }

        local maximum = instrument.kind == MT_KIND_COMPANY ? MT_MAX_COMPANY_FLOAT : MT_MAX_INDUSTRY_FLOAT;
        if (instrument.issued >= maximum) {
            this.PublishPrivate(company_id, "No public lots are currently available in " + instrument.name + ".");
            return false;
        }

        local execution_price = instrument.price + this.MarketImpact(instrument.price);
        local fee = this.TransactionFee(execution_price);
        local cost = execution_price + fee;
        if (GSCompany.GetBankBalance(company_id) < cost) {
            this.PublishPrivate(company_id, "Insufficient available cash to buy one lot of " + instrument.name + ".");
            return false;
        }
        if (!GSCompany.ChangeBankBalance(company_id, -cost, GSCompany.EXPENSES_OTHER, GSMap.TILE_INVALID)) return false;

        local portfolio = this.GetPortfolio(company_id);
        if (!portfolio.holdings.rawin(instrument.id)) portfolio.holdings[instrument.id] <- { lots = 0, cost_basis = 0 };
        portfolio.holdings[instrument.id].lots++;
        portfolio.holdings[instrument.id].cost_basis += cost;
        instrument.issued++;
        instrument.price = execution_price;
        this.PublishPrivate(company_id, "Bought one lot of " + instrument.name + " for " + this.FormatMoney(cost) + " including fees.");
        return true;
    }

    function SellOneLot(company_id, instrument)
    {
        local portfolio = this.GetPortfolio(company_id);
        if (!portfolio.holdings.rawin(instrument.id) || portfolio.holdings[instrument.id].lots <= 0) {
            this.PublishPrivate(company_id, "Your company does not hold a lot of " + instrument.name + " to sell.");
            return false;
        }

        local holding = portfolio.holdings[instrument.id];
        local execution_price = this.MaxValue(1, instrument.price - this.MarketImpact(instrument.price));
        local fee = this.TransactionFee(execution_price);
        local proceeds = this.MaxValue(0, execution_price - fee);
        local allocated_cost = holding.cost_basis / holding.lots;
        if (!GSCompany.ChangeBankBalance(company_id, proceeds, GSCompany.EXPENSES_OTHER, GSMap.TILE_INVALID)) return false;

        holding.lots--;
        holding.cost_basis -= allocated_cost;
        portfolio.realised += proceeds - allocated_cost;
        instrument.issued = this.MaxValue(0, instrument.issued - 1);
        instrument.price = execution_price;
        if (holding.lots == 0) delete portfolio.holdings[instrument.id];
        this.PublishPrivate(company_id, "Sold one lot of " + instrument.name + " for " + this.FormatMoney(proceeds) + " after fees.");
        return true;
    }

    function EnsureAllPortfolios()
    {
        for (local company_id = GSCompany.COMPANY_FIRST; company_id < GSCompany.COMPANY_LAST; company_id++) {
            if (!this.IsValidCompany(company_id)) continue;
            this.EnsurePortfolio(company_id);
        }
    }

    function EnsurePortfolio(company_id)
    {
        local key = company_id.tostring();
        if (!this.portfolios.rawin(key)) {
            this.portfolios[key] <- {
                selected = 0,
                page = -1,
                summary = -1,
                detail = -1,
                previous_button = -1,
                next_button = -1,
                buy_button = -1,
                sell_button = -1,
                refresh_button = -1,
                holdings = {},
                realised = 0,
                dividends = 0,
                pending_cash = 0,
                pending_dividends = 0,
                pending_realised = 0
            };
        }

        local portfolio = this.portfolios[key];
        this.EnsurePortfolioSchema(portfolio);

        if (!GSStoryPage.IsValidStoryPage(portfolio.page)) this.CreatePortfolioPage(company_id, portfolio);
        return portfolio;
    }

    function CreatePortfolioPage(company_id, portfolio)
    {
        portfolio.page = GSStoryPage.New(company_id, "Modern Tycoon Exchange");
        portfolio.summary = GSStoryPage.NewElement(portfolio.page, GSStoryPage.SPET_TEXT, 0, "Portfolio initialising...");
        portfolio.detail = GSStoryPage.NewElement(portfolio.page, GSStoryPage.SPET_TEXT, 0, "No listed securities.");

        local left = GSStoryPage.MakePushButtonReference(GSStoryPage.SPBC_LIGHT_BLUE, GSStoryPage.SPBF_FLOAT_LEFT);
        local green = GSStoryPage.MakePushButtonReference(GSStoryPage.SPBC_GREEN, GSStoryPage.SPBF_FLOAT_LEFT);
        local red = GSStoryPage.MakePushButtonReference(GSStoryPage.SPBC_RED, GSStoryPage.SPBF_FLOAT_LEFT);
        portfolio.previous_button = GSStoryPage.NewElement(portfolio.page, GSStoryPage.SPET_BUTTON_PUSH, left, "Previous");
        portfolio.next_button = GSStoryPage.NewElement(portfolio.page, GSStoryPage.SPET_BUTTON_PUSH, left, "Next");
        portfolio.buy_button = GSStoryPage.NewElement(portfolio.page, GSStoryPage.SPET_BUTTON_PUSH, green, "Buy 1 lot");
        portfolio.sell_button = GSStoryPage.NewElement(portfolio.page, GSStoryPage.SPET_BUTTON_PUSH, red, "Sell 1 lot");
        portfolio.refresh_button = GSStoryPage.NewElement(portfolio.page, GSStoryPage.SPET_BUTTON_PUSH, left, "Refresh quote");
        GSLog.Info("Created Modern Tycoon Exchange portfolio page for company " + company_id);
    }

    function MaybeRunSelfTest()
    {
        if (this.self_test_done || GSController.GetSetting("developer_self_test") == 0) return;

        for (local company_id = GSCompany.COMPANY_FIRST; company_id < GSCompany.COMPANY_LAST; company_id++) {
            if (!this.IsValidCompany(company_id)) continue;
            local portfolio = this.EnsurePortfolio(company_id);

            foreach (instrument in this.instruments) {
                if (instrument.kind == MT_KIND_COMPANY && instrument.object_id == company_id) continue;

                local execution_price = instrument.price + this.MarketImpact(instrument.price);
                local fee = this.TransactionFee(execution_price);
                if (GSCompany.GetBankBalance(company_id) < execution_price + fee) continue;

                local issued_before = instrument.issued;
                local lots_before = portfolio.holdings.rawin(instrument.id) ? portfolio.holdings[instrument.id].lots : 0;
                local cash_before = GSCompany.GetBankBalance(company_id);
                if (!this.BuyOneLot(company_id, instrument)) continue;
                local holding_after_buy = portfolio.holdings.rawin(instrument.id) ? portfolio.holdings[instrument.id].lots : 0;
                if (instrument.issued != issued_before + 1 || holding_after_buy != lots_before + 1) {
                    GSLog.Error("Modern Tycoon self-test failed during buy for " + instrument.id);
                    this.self_test_done = true;
                    return;
                }

                local dividends_before = portfolio.dividends;
                local expected_credit = lots_before + 1;
                this.CreditHolders(instrument, 1);
                if (portfolio.dividends != dividends_before + expected_credit) {
                    GSLog.Error("Modern Tycoon self-test failed during distribution for " + instrument.id);
                    this.self_test_done = true;
                    return;
                }

                if (!this.SellOneLot(company_id, instrument)) {
                    GSLog.Error("Modern Tycoon self-test failed during sell for " + instrument.id);
                    this.self_test_done = true;
                    return;
                }
                local holding_after_sell = portfolio.holdings.rawin(instrument.id) ? portfolio.holdings[instrument.id].lots : 0;
                local cash_after = GSCompany.GetBankBalance(company_id);
                if (instrument.issued != issued_before || holding_after_sell != lots_before || cash_after - expected_credit > cash_before) {
                    GSLog.Error("Modern Tycoon self-test failed lot conservation for " + instrument.id);
                    this.self_test_done = true;
                    return;
                }

                this.self_test_done = true;
                this.RefreshPortfolioPage(company_id);
                GSLog.Info("Modern Tycoon self-test passed: buy/distribution/sell conservation for " + instrument.id);
                return;
            }
        }
    }

    function RefreshAllPages()
    {
        foreach (company_key, portfolio in this.portfolios) {
            local company_id = company_key.tointeger();
            if (this.IsValidCompany(company_id)) this.RefreshPortfolioPage(company_id);
        }
    }

    function RefreshPortfolioPage(company_id)
    {
        local portfolio = this.EnsurePortfolio(company_id);
        if (portfolio.selected >= this.instruments.len()) portfolio.selected = 0;
        if (portfolio.selected < 0) portfolio.selected = 0;

        local market_value = 0;
        local cost_basis = 0;
        local lot_count = 0;
        foreach (instrument_id, holding in portfolio.holdings) {
            local instrument_index = this.FindInstrumentIndex(instrument_id);
            if (instrument_index < 0) continue;
            market_value += holding.lots * this.instruments[instrument_index].price;
            cost_basis += holding.cost_basis;
            lot_count += holding.lots;
        }

        local summary = "Available cash: " + this.FormatMoney(GSCompany.GetBankBalance(company_id)) +
            "\nPortfolio: " + lot_count + " lots worth " + this.FormatMoney(market_value) +
            "\nUnrealised result: " + this.FormatSignedMoney(market_value - cost_basis) +
            " | Realised: " + this.FormatSignedMoney(portfolio.realised) +
            " | Dividends: " + this.FormatMoney(portfolio.dividends) +
            (portfolio.pending_cash > 0 ? " | Pending settlement: " + this.FormatMoney(portfolio.pending_cash) : "");
        GSStoryPage.UpdateElement(portfolio.summary, 0, summary);
        if (this.UsesCalendarTimekeeping()) GSStoryPage.SetDate(portfolio.page, GSDate.GetCurrentDate());

        if (this.instruments.len() == 0) {
            GSStoryPage.UpdateElement(portfolio.detail, 0, "No securities are listed. Enable a market in Game Script settings.");
            return;
        }

        local instrument = this.instruments[portfolio.selected];
        local held_lots = portfolio.holdings.rawin(instrument.id) ? portfolio.holdings[instrument.id].lots : 0;
        local change = instrument.price - instrument.previous_price;
        local change_percent = instrument.previous_price > 0 ? (change * 100) / instrument.previous_price : 0;
        local kind = instrument.kind == MT_KIND_COMPANY ? "COMPANY EQUITY" : "INDUSTRY SECURITY";
        local detail = kind + "  " + (portfolio.selected + 1) + "/" + this.instruments.len() +
            "\n" + instrument.name +
            "\nPrice per lot: " + this.FormatMoney(instrument.price) + " (" + this.FormatSigned(change_percent) + "%)" +
            (instrument.rawin("fair") ? "\nFair value: " + this.FormatMoney(instrument.fair) + " | Market mood: " + MT_Percent(instrument.sentiment) : "") +
            "\nYour holding: " + held_lots + " lots | Player-held float: " + instrument.issued +
            "\n" + (instrument.kind == MT_KIND_COMPANY
                ? "One lot represents 1% economic exposure; self-trading is prohibited."
                : "Quote and distributions track this industry's transported production.");
        GSStoryPage.UpdateElement(portfolio.detail, 0, detail);
    }

    /* The exchange close: the biggest riser and faller this month, in basis points. Only the latest close is printed. */
    function RecordMarketClose()
    {
        if (this.instruments.len() == 0) return;

        local leader = this.instruments[0], laggard = this.instruments[0];
        local leader_bp = -1000000000, laggard_bp = 1000000000;
        foreach (instrument in this.instruments) {
            local bp = instrument.previous_price > 0 ? ((instrument.price - instrument.previous_price) * 10000) / instrument.previous_price : 0;
            if (bp > leader_bp) {
                leader = instrument;
                leader_bp = bp;
            }
            if (bp < laggard_bp) {
                laggard = instrument;
                laggard_bp = bp;
            }
        }
        /* A quiet session (no move of half a percent either way) is a minor report. */
        local severity = (leader_bp >= 50 || laggard_bp <= -50) ? MT_SEV_NORMAL : MT_SEV_MINOR;
        this.news.Record("markets", severity, "market_close",
            [leader.name, leader.price, leader_bp, laggard.name, laggard_bp, this.instruments.len()],
            GSNews.NR_NONE, 0, "movers", false);
    }

    function ListedIndustryName(industry_id)
    {
        local index = this.FindInstrumentIndex("I:" + industry_id);
        return index < 0 ? null : this.instruments[index].name;
    }

    function PublishPrivate(company_id, text)
    {
        GSNews.Create(GSNews.NT_ECONOMY, text, company_id, GSNews.NR_NONE, 0);
    }

    function EnsureStoredSchema()
    {
        this.EnsureInstrumentSchema();
        foreach (company_key, portfolio in this.portfolios) this.EnsurePortfolioSchema(portfolio);
    }

    function EnsureInstrumentSchema()
    {
        local migrated = 0;
        foreach (instrument in this.instruments) {
            if (!instrument.rawin("metric")) instrument.metric <- 0;
            if (instrument.kind == MT_KIND_INDUSTRY && !instrument.rawin("quarter_metric")) instrument.quarter_metric <- 0;
            if (!instrument.rawin("fair")) migrated++;
            this.EnsurePricingState(instrument, this.FundamentalOf(instrument));
        }
        if (!this.is_fresh) GSLog.Info("MT-PRICING state restored for " + (this.instruments.len() - migrated) +
            " securities, started from fair value for " + migrated);
    }

    function EnsurePortfolioSchema(portfolio)
    {
        if (!portfolio.rawin("holdings")) portfolio.holdings <- {};
        if (!portfolio.rawin("realised")) portfolio.realised <- 0;
        if (!portfolio.rawin("dividends")) portfolio.dividends <- 0;
        if (!portfolio.rawin("pending_cash")) portfolio.pending_cash <- 0;
        if (!portfolio.rawin("pending_dividends")) portfolio.pending_dividends <- 0;
        if (!portfolio.rawin("pending_realised")) portfolio.pending_realised <- 0;
        if (!portfolio.rawin("selected")) portfolio.selected <- 0;
        if (!portfolio.rawin("page")) portfolio.page <- -1;
        if (!portfolio.rawin("summary")) portfolio.summary <- -1;
        if (!portfolio.rawin("detail")) portfolio.detail <- -1;
        if (!portfolio.rawin("previous_button")) portfolio.previous_button <- -1;
        if (!portfolio.rawin("next_button")) portfolio.next_button <- -1;
        if (!portfolio.rawin("buy_button")) portfolio.buy_button <- -1;
        if (!portfolio.rawin("sell_button")) portfolio.sell_button <- -1;
        if (!portfolio.rawin("refresh_button")) portfolio.refresh_button <- -1;
    }

    function CreditOrQueue(company_id, portfolio, amount, dividend_amount, realised_amount)
    {
        if (amount <= 0) {
            portfolio.dividends += dividend_amount;
            portfolio.realised += realised_amount;
            return true;
        }

        if (this.TryCredit(company_id, amount)) {
            portfolio.dividends += dividend_amount;
            portfolio.realised += realised_amount;
            return true;
        }

        portfolio.pending_cash += amount;
        portfolio.pending_dividends += dividend_amount;
        portfolio.pending_realised += realised_amount;
        GSLog.Warning("Queued a failed Modern Tycoon settlement of " + amount + " for company " + company_id);
        return false;
    }

    /* Pay money to a company. The fixture can make the next few payments fail to exercise the pending queue. */
    function TryCredit(company_id, amount)
    {
        if (this.settlement_faults > 0) {
            this.settlement_faults--;
            return false;
        }
        return GSCompany.ChangeBankBalance(company_id, amount, GSCompany.EXPENSES_OTHER, GSMap.TILE_INVALID);
    }

    function RetryPendingCredits()
    {
        foreach (company_key, portfolio in this.portfolios) {
            local company_id = company_key.tointeger();
            if (!this.IsValidCompany(company_id) || portfolio.pending_cash <= 0) continue;
            if (!this.TryCredit(company_id, portfolio.pending_cash)) continue;

            portfolio.dividends += portfolio.pending_dividends;
            portfolio.realised += portfolio.pending_realised;
            portfolio.pending_cash = 0;
            portfolio.pending_dividends = 0;
            portfolio.pending_realised = 0;
        }
    }

    function MergePortfolios(old_company_id, new_company_id)
    {
        local old_key = old_company_id.tostring();
        if (!this.portfolios.rawin(old_key) || !this.IsValidCompany(new_company_id)) return;

        local source = this.portfolios[old_key];
        this.EnsurePortfolioSchema(source);
        local target = this.EnsurePortfolio(new_company_id);

        foreach (instrument_id, holding in source.holdings) {
            if (!target.holdings.rawin(instrument_id)) target.holdings[instrument_id] <- { lots = 0, cost_basis = 0 };
            target.holdings[instrument_id].lots += holding.lots;
            target.holdings[instrument_id].cost_basis += holding.cost_basis;
        }
        target.realised += source.realised;
        target.dividends += source.dividends;
        target.pending_cash += source.pending_cash;
        target.pending_dividends += source.pending_dividends;
        target.pending_realised += source.pending_realised;
        delete this.portfolios[old_key];

        this.SettleMergedSelfHolding(new_company_id, target);
        this.ReconcileIssuedLots();
    }

    function SettleMergedSelfHolding(company_id, portfolio)
    {
        local instrument_id = "C:" + company_id;
        if (!portfolio.holdings.rawin(instrument_id)) return;

        local index = this.FindInstrumentIndex(instrument_id);
        if (index < 0) return;
        local instrument = this.instruments[index];
        local holding = portfolio.holdings[instrument_id];
        local proceeds = 0;
        local execution_price = instrument.price;
        for (local lot = 0; lot < holding.lots; lot++) {
            execution_price = this.MaxValue(1, execution_price - this.MarketImpact(execution_price));
            proceeds += this.MaxValue(0, execution_price - this.TransactionFee(execution_price));
        }

        this.CreditOrQueue(company_id, portfolio, proceeds, 0, proceeds - holding.cost_basis);
        instrument.price = execution_price;
        delete portfolio.holdings[instrument_id];
        this.PublishPrivate(company_id, "Merger settlement sold inherited self-shares back to public inventory.");
    }

    function RemoveInvalidPortfolios()
    {
        local removals = [];
        foreach (company_key, portfolio in this.portfolios) {
            if (!this.IsValidCompany(company_key.tointeger())) removals.append(company_key);
        }
        foreach (company_key in removals) delete this.portfolios[company_key];
        this.ReconcileIssuedLots();
    }

    function ReconcileIssuedLots()
    {
        foreach (instrument in this.instruments) instrument.issued = 0;
        foreach (company_key, portfolio in this.portfolios) {
            if (!portfolio.rawin("holdings")) continue;
            foreach (instrument_id, holding in portfolio.holdings) {
                local index = this.FindInstrumentIndex(instrument_id);
                if (index >= 0 && holding.lots > 0) this.instruments[index].issued += holding.lots;
            }
        }
    }

    function GetPortfolio(company_id)
    {
        local key = company_id.tostring();
        return this.portfolios.rawin(key) ? this.portfolios[key] : null;
    }

    function FindInstrumentIndex(instrument_id)
    {
        for (local index = 0; index < this.instruments.len(); index++) {
            if (this.instruments[index].id == instrument_id) return index;
        }
        return -1;
    }

    function CountIndustryInstruments()
    {
        local count = 0;
        foreach (instrument in this.instruments) if (instrument.kind == MT_KIND_INDUSTRY) count++;
        return count;
    }

    function IsValidCompany(company_id)
    {
        return GSCompany.ResolveCompanyID(company_id) != GSCompany.COMPANY_INVALID;
    }

    function MarketImpact(price)
    {
        return this.MaxValue(1, price / 200);
    }

    function TransactionFee(value)
    {
        return (value * GSController.GetSetting("transaction_fee_bp")) / 10000;
    }

    function UsesCalendarTimekeeping()
    {
        local setting = "economy.timekeeping_units";
        return !GSGameSettings.IsValid(setting) || GSGameSettings.GetValue(setting) == 0;
    }

    function GetCompanyName(company_id)
    {
        local name = GSCompany.GetName(company_id);
        return name == null ? "Company " + company_id : name;
    }

    function GetIndustryName(industry_id)
    {
        local name = GSIndustry.GetName(industry_id);
        return name == null ? "Industry " + industry_id : name;
    }

    function Clamp(value, minimum, maximum)
    {
        if (value < minimum) return minimum;
        if (value > maximum) return maximum;
        return value;
    }

    function MaxValue(a, b)
    {
        return a > b ? a : b;
    }

    function FormatMoney(value)
    {
        return value < 0 ? "-" + (-value) : value.tostring();
    }

    function FormatSignedMoney(value)
    {
        return value > 0 ? "+" + value : value.tostring();
    }

    function FormatSigned(value)
    {
        return value > 0 ? "+" + value : value.tostring();
    }
}
