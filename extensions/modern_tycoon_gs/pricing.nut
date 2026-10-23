/*
 * Share pricing for the Modern Tycoon exchange.
 *
 * In plain words: every security has a fair value that follows its
 * fundamental (company value plus a profit multiple, or industry output).
 * The quote is the fair value times a mood ("sentiment") and a growth
 * premium: the recent monthly growth of the fundamental, priced about six
 * months ahead, so growth is paid for up front and a slowdown hurts. The mood keeps
 * 80% of itself each month, gets a small bounded random nudge, and gets
 * shocks from real events: quarterly results against expectations, losses,
 * financial trouble, production booms and slumps, closure warnings.
 * The quote closes most of the gap to that target when the gap is large and
 * part of it when close, so prices follow fundamentals quickly but can fall
 * as well as rise. Quotes stay between a quarter of and four times fair value.
 *
 * Determinism: the only randomness is a hash of (seed, security, month).
 * The seed is drawn once from the game's own random generator and saved, so
 * a loaded game replays the same quotes. No wall clock is used.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

MT_SENTIMENT_KEEP_PCT <- 80;      // Share of last month's mood that remains.
MT_SENTIMENT_LIMIT_BP <- 3000;    // Mood never exceeds +/-30%.
MT_NOISE_COMPANY_BP <- 600;       // Largest monthly random nudge for a company.
MT_NOISE_INDUSTRY_BP <- 400;      // Largest monthly random nudge for an industry.
MT_FAST_GAP_PCT <- 20;            // A gap above this is closed quickly.
MT_FAIR_FAST_GAP_PCT <- 30;       // Fair value catches up faster above this gap.
MT_SHOCK_LIMIT_BP <- 1200;        // Largest reaction to one quarter's results.
MT_SURPRISE_NEWS_BP <- 1500;      // Surprise needed before the Ledger reports it.
MT_LOSS_SHOCK_BP <- -600;         // Extra reaction to a quarterly loss.
MT_NEGATIVE_CASH_SHOCK_BP <- -800;
MT_TROUBLE_SHOCK_BP <- -2000;     // The company was flagged as in financial trouble.
MT_SLUMP_SHOCK_BP <- -1500;
MT_BOOM_SHOCK_BP <- 1000;
MT_CLOSURE_SHOCK_BP <- -3000;     // The industry announced it will close.
MT_SLUMP_PCT <- 50;               // Production below this share of normal is a slump.
MT_BOOM_PCT <- 170;               // Production above this share of normal is a boom.
MT_MIN_TRACKED_PRODUCTION <- 40;  // Ignore swings at tiny industries.
MT_GROWTH_STEP_LIMIT_BP <- 1500;  // One month's fundamental growth counts at most +/-15%.
MT_GROWTH_MONTHS_PRICED <- 6;     // Expected growth priced this many months ahead.
MT_PREMIUM_MIN_BP <- -2500;
MT_PREMIUM_MAX_BP <- 5000;

function MT_Abs(value) { return value < 0 ? -value : value; }

/* A small integer hash (FNV-style with extra mixing), always 0..2^31-1. */
function MT_Hash(seed, a, b, c)
{
    local h = 2166136261 & 0x7FFFFFFF;
    foreach (x in [seed, a, b, c]) {
        h = ((h ^ (x & 0x7FFFFFFF)) * 16777619) & 0x7FFFFFFF;
        h = h ^ (h >> 15);
    }
    h = (h * 1274126177) & 0x7FFFFFFF;
    return h ^ (h >> 16);
}

/* Two uniform draws of half the amplitude: bounded, centred, more often small than large. */
function MT_Noise(seed, kind, object_id, month_key, amplitude)
{
    local half = amplitude / 2;
    local span = half * 2 + 1;
    local id = kind * 65536 + object_id;
    return (MT_Hash(seed, id, month_key, 1) % span - half) + (MT_Hash(seed, id, month_key, 2) % span - half);
}

function MT_ChangeBp(from, to)
{
    return from > 0 ? ((to - from) * 10000) / from : 0;
}

/* Fields added in schema 4. Old saves start with fair value = today's fundamental. */
function ModernMarket::EnsurePricingState(instrument, fundamental)
{
    if (!instrument.rawin("fair")) instrument.fair <- fundamental > 0 ? fundamental : instrument.price;
    if (!instrument.rawin("fundamental")) instrument.fundamental <- fundamental;
    if (!instrument.rawin("sentiment")) instrument.sentiment <- 0;
    if (!instrument.rawin("shock")) instrument.shock <- 0;
    if (!instrument.rawin("expected")) instrument.expected <- 0;
    if (!instrument.rawin("has_expected")) instrument.has_expected <- false;
    if (!instrument.rawin("quarter_open")) instrument.quarter_open <- instrument.price;
    if (!instrument.rawin("growth")) instrument.growth <- 0;
}

function ModernMarket::FundamentalOf(instrument)
{
    return instrument.kind == MT_KIND_COMPANY
        ? this.CompanyFundamentalPrice(instrument.object_id)
        : this.IndustryFundamentalPrice(instrument.object_id);
}

/* One month: fair value follows the fundamental, the mood moves, the quote follows both. */
function ModernMarket::MovePrice(instrument, fundamental, month_key)
{
    local step = this.Clamp(MT_ChangeBp(instrument.fundamental, fundamental), -MT_GROWTH_STEP_LIMIT_BP, MT_GROWTH_STEP_LIMIT_BP);
    instrument.growth = (instrument.growth * 2 + step) / 3;
    instrument.fundamental = fundamental;

    local fair = instrument.fair;
    local fair_gap = fundamental - fair;
    local divisor = MT_Abs(fair_gap) * 100 > fair * MT_FAIR_FAST_GAP_PCT ? 2 : 3;
    fair = this.MaxValue(1, fair + fair_gap / divisor);
    instrument.fair = fair;

    local amplitude = instrument.kind == MT_KIND_COMPANY ? MT_NOISE_COMPANY_BP : MT_NOISE_INDUSTRY_BP;
    local noise = MT_Noise(this.price_seed, instrument.kind, instrument.object_id, month_key, amplitude);
    local sentiment = (instrument.sentiment * MT_SENTIMENT_KEEP_PCT) / 100 + noise + instrument.shock;
    instrument.shock = 0;
    instrument.sentiment = this.Clamp(sentiment, -MT_SENTIMENT_LIMIT_BP, MT_SENTIMENT_LIMIT_BP);

    local premium = this.Clamp(instrument.growth * MT_GROWTH_MONTHS_PRICED, MT_PREMIUM_MIN_BP, MT_PREMIUM_MAX_BP);
    local target = this.MaxValue(1, (fair * (10000 + instrument.sentiment + premium)) / 10000);
    local gap = target - instrument.price;
    local fast = MT_Abs(gap) * 100 > instrument.price * MT_FAST_GAP_PCT;
    local move = fast ? (gap * 3) / 4 : (gap * 2) / 5;
    instrument.price = this.Clamp(instrument.price + move, this.MaxValue(1, fair / 4), this.MaxValue(1, fair * 4));

    if (GSController.GetSetting("developer_price_log")) {
        GSLog.Info("MT-PRICE " + month_key + " " + instrument.id + " price=" + instrument.price + " fair=" + fair +
            " fundamental=" + fundamental + " sentiment=" + instrument.sentiment + " premium=" + premium);
    }
}

/* Start of a quarter: compare last quarter's profit with what the market expected. */
function ModernMarket::ReactToResults(instrument)
{
    local company_id = instrument.object_id;
    local profit = GSCompany.GetQuarterlyIncome(company_id, 1) + GSCompany.GetQuarterlyExpenses(company_id, 1);
    if (!instrument.has_expected) {
        instrument.expected = profit;
        instrument.has_expected = true;
        return;
    }

    local expected = instrument.expected;
    local market_value = this.MaxValue(1, instrument.fair) * 100;
    /* Small expectations are measured against 2% of market value, so tiny numbers do not swing the price. */
    local base = this.MaxValue(MT_Abs(expected), market_value / 50);
    local surprise_bp = ((profit - expected) * 10000) / this.MaxValue(1, base);
    local shock = this.Clamp(surprise_bp / 4, -MT_SHOCK_LIMIT_BP, MT_SHOCK_LIMIT_BP);
    if (profit < 0) shock += MT_LOSS_SHOCK_BP;
    if (GSCompany.GetBankBalance(company_id) < 0) shock += MT_NEGATIVE_CASH_SHOCK_BP;
    instrument.shock += shock;
    instrument.expected = (expected * 3 + profit) / 4;

    if (surprise_bp >= MT_SURPRISE_NEWS_BP) {
        this.news.Record("companies", MT_SEV_NORMAL, "results_beat", [instrument.name, profit, expected], GSNews.NR_NONE, 0, null, false);
    } else if (surprise_bp <= -MT_SURPRISE_NEWS_BP) {
        this.news.Record("companies", MT_SEV_NORMAL, "results_miss", [instrument.name, profit, expected], GSNews.NR_NONE, 0, null, false);
    }
    if (profit < 0 && (-profit) * 100 > market_value * 3) {
        this.news.Record("companies", MT_SEV_NORMAL, "quarterly_loss", [instrument.name, -profit], GSNews.NR_NONE, 0, null, false);
    }
}

/* Every month: production far from normal, or a closure warning, moves an industry's mood. */
function ModernMarket::ReactToProduction(instrument)
{
    local industry_id = instrument.object_id;
    if (!GSIndustry.IsValidIndustry(industry_id)) return;

    if (GSIndustry.GetProductionLevel(industry_id) == 0 && !instrument.rawin("closing")) {
        instrument.closing <- true;
        instrument.shock += MT_CLOSURE_SHOCK_BP;
        this.news.Record("industry", MT_SEV_NORMAL, "closure_warning", [instrument.name], GSNews.NR_INDUSTRY, industry_id, null, false);
    }

    local production = this.GetIndustryProductionMetric(industry_id);
    if (!instrument.has_expected) {
        instrument.expected = production;
        instrument.has_expected = true;
        return;
    }
    local normal = instrument.expected;
    /* Only raw industries: a factory's output just mirrors deliveries, which the fundamental already counts. */
    local raw = GSIndustryType.IsRawIndustry(GSIndustry.GetIndustryType(industry_id));
    if (raw && normal >= MT_MIN_TRACKED_PRODUCTION) {
        if (production * 100 < normal * MT_SLUMP_PCT) {
            instrument.shock += MT_SLUMP_SHOCK_BP;
            this.news.Record("industry", MT_SEV_MINOR, "production_slump", [instrument.name, production, normal], GSNews.NR_INDUSTRY, industry_id, "output:" + industry_id, false);
        } else if (production * 100 > normal * MT_BOOM_PCT) {
            instrument.shock += MT_BOOM_SHOCK_BP;
            this.news.Record("industry", MT_SEV_MINOR, "production_boom", [instrument.name, production, normal], GSNews.NR_INDUSTRY, industry_id, "output:" + industry_id, false);
        }
    }
    instrument.expected = (normal * 3 + production) / 4;
}

/* The company was flagged as in trouble: the market marks it down at the next close. */
function ModernMarket::ReactToTrouble(company_id)
{
    local index = this.FindInstrumentIndex("C:" + company_id);
    if (index >= 0) this.instruments[index].shock += MT_TROUBLE_SHOCK_BP;
}

/* Start of a quarter: the biggest winner and loser over the quarter that just ended. */
function ModernMarket::RecordQuarterMovers()
{
    if (this.instruments.len() == 0) return;

    local best = null, worst = null, best_bp = 0, worst_bp = 0, ups = 0, downs = 0;
    foreach (instrument in this.instruments) {
        local bp = MT_ChangeBp(instrument.quarter_open, instrument.price);
        if (bp > 0) ups++;
        if (bp < 0) downs++;
        if (best == null || bp > best_bp) {
            best = instrument;
            best_bp = bp;
        }
        if (worst == null || bp < worst_bp) {
            worst = instrument;
            worst_bp = bp;
        }
        instrument.quarter_open = instrument.price;
    }
    this.news.Record("markets", MT_SEV_NORMAL, "market_quarter", [best.name, best_bp, worst.name, worst_bp, ups, downs],
        GSNews.NR_NONE, 0, "quarter_movers", false);
}
