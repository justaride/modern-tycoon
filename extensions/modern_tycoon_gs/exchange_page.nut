/*
 * The Modern Tycoon Exchange page in each company's Story Book.
 *
 * Raw script text cannot contain line breaks (the game shows them as "?"),
 * so every line is its own text element: a fixed block for the portfolio
 * summary and the selected security, the buttons, and below them a market
 * board with one element per line that grows and shrinks with the listings.
 *
 * Pages made by older versions (one text element with "\n" in it) are
 * replaced by a new page with this layout the first time they are refreshed.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

MT_PAGE_LAYOUT <- 5;
MT_SUMMARY_LINES <- 3;
MT_DETAIL_LINES <- 6;

/* 1234567 -> "1,234,567"; negative numbers keep their sign. */
function MT_Group(value)
{
    local negative = value < 0;
    local digits = (negative ? -value : value).tostring();
    local grouped = "";
    while (digits.len() > 3) {
        grouped = "," + digits.slice(digits.len() - 3) + grouped;
        digits = digits.slice(0, digits.len() - 3);
    }
    return (negative ? "-" : "") + digits + grouped;
}

function ModernMarket::NeedsNewPage(portfolio)
{
    return !GSStoryPage.IsValidStoryPage(portfolio.page) || !portfolio.rawin("layout") || portfolio.layout != MT_PAGE_LAYOUT;
}

/* (Re)creates the page with the current layout; an old page is removed first. */
function ModernMarket::BuildPortfolioPage(company_id, portfolio)
{
    if (GSStoryPage.IsValidStoryPage(portfolio.page)) GSStoryPage.Remove(portfolio.page);
    portfolio.page = GSStoryPage.New(company_id, "Modern Tycoon Exchange");

    if (!portfolio.rawin("summary_lines")) portfolio.summary_lines <- [];
    if (!portfolio.rawin("detail_lines")) portfolio.detail_lines <- [];
    if (!portfolio.rawin("board_lines")) portfolio.board_lines <- [];
    portfolio.summary_lines = [];
    portfolio.detail_lines = [];
    portfolio.board_lines = [];
    for (local i = 0; i < MT_SUMMARY_LINES; i++) {
        portfolio.summary_lines.append(GSStoryPage.NewElement(portfolio.page, GSStoryPage.SPET_TEXT, 0, i == 0 ? "Portfolio initialising..." : " "));
    }
    for (local i = 0; i < MT_DETAIL_LINES; i++) {
        portfolio.detail_lines.append(GSStoryPage.NewElement(portfolio.page, GSStoryPage.SPET_TEXT, 0, " "));
    }

    /* Buttons do not float, so the board below starts under them instead of beside them. */
    local left = GSStoryPage.MakePushButtonReference(GSStoryPage.SPBC_LIGHT_BLUE, GSStoryPage.SPBF_NONE);
    local green = GSStoryPage.MakePushButtonReference(GSStoryPage.SPBC_GREEN, GSStoryPage.SPBF_NONE);
    local red = GSStoryPage.MakePushButtonReference(GSStoryPage.SPBC_RED, GSStoryPage.SPBF_NONE);
    portfolio.previous_button = GSStoryPage.NewElement(portfolio.page, GSStoryPage.SPET_BUTTON_PUSH, left, "Previous");
    portfolio.next_button = GSStoryPage.NewElement(portfolio.page, GSStoryPage.SPET_BUTTON_PUSH, left, "Next");
    portfolio.buy_button = GSStoryPage.NewElement(portfolio.page, GSStoryPage.SPET_BUTTON_PUSH, green, "Buy 1 lot");
    portfolio.sell_button = GSStoryPage.NewElement(portfolio.page, GSStoryPage.SPET_BUTTON_PUSH, red, "Sell 1 lot");
    portfolio.refresh_button = GSStoryPage.NewElement(portfolio.page, GSStoryPage.SPET_BUTTON_PUSH, left, "Refresh quote");

    if (!portfolio.rawin("layout")) portfolio.layout <- 0;
    portfolio.layout = MT_PAGE_LAYOUT;
    GSLog.Info("Created Modern Tycoon Exchange portfolio page for company " + company_id);
}

/* Writes lines into a fixed block of elements; unused elements show a blank. */
function ModernMarket::WriteBlock(elements, lines)
{
    foreach (index, element in elements) {
        GSStoryPage.UpdateElement(element, 0, index < lines.len() ? lines[index] : " ");
    }
}

/* Writes lines into the board, adding or removing elements at the end of the page to match. */
function ModernMarket::WriteBoard(portfolio, lines)
{
    local elements = portfolio.board_lines;
    while (elements.len() < lines.len()) {
        elements.append(GSStoryPage.NewElement(portfolio.page, GSStoryPage.SPET_TEXT, 0, " "));
    }
    while (elements.len() > lines.len()) {
        GSStoryPage.RemoveElement(elements.pop());
    }
    this.WriteBlock(elements, lines);
}

function ModernMarket::SummaryLines(company_id, portfolio)
{
    local market_value = 0, cost_basis = 0, lot_count = 0;
    foreach (instrument_id, holding in portfolio.holdings) {
        local index = this.FindInstrumentIndex(instrument_id);
        if (index < 0) continue;
        market_value += holding.lots * this.instruments[index].price;
        cost_basis += holding.cost_basis;
        lot_count += holding.lots;
    }
    return [
        "Available cash: " + this.FormatMoney(GSCompany.GetBankBalance(company_id)),
        "Portfolio: " + lot_count + " lots worth " + this.FormatMoney(market_value) +
            " | unrealised " + this.FormatSignedMoney(market_value - cost_basis),
        "Realised: " + this.FormatSignedMoney(portfolio.realised) + " | Dividends: " + this.FormatMoney(portfolio.dividends) +
            (portfolio.pending_cash > 0 ? " | Pending settlement: " + this.FormatMoney(portfolio.pending_cash) : "")
    ];
}

function ModernMarket::DetailLines(portfolio, selected)
{
    if (selected < 0) return ["No securities are listed. Enable a market in Game Script settings."];

    local instrument = this.instruments[selected];
    local held_lots = portfolio.holdings.rawin(instrument.id) ? portfolio.holdings[instrument.id].lots : 0;
    local is_company = instrument.kind == MT_KIND_COMPANY;
    local history = this.HistoryLine(instrument);
    local status;
    if (!this.IsOpenForTrading(instrument)) {
        status = "Not yet open for trading: shares open in " + MT_MonthName(instrument.opens) + ". The quote is indicative.";
    } else {
        status = is_company ? "One lot is 1% economic exposure. Companies cannot trade their own shares."
            : "Quote and distributions track this industry's transported production.";
    }
    return [
        (is_company ? "COMPANY EQUITY " : "INDUSTRY SECURITY ") + (selected + 1) + "/" + this.instruments.len() + ": " + instrument.name,
        "Price per lot: " + this.FormatMoney(instrument.price) + " (" + MT_Percent(MT_ChangeBp(instrument.previous_price, instrument.price)) + " this month)",
        "Fair value: " + this.FormatMoney(instrument.fair) + " | Market mood: " + MT_Percent(instrument.sentiment),
        history != null ? history : "No price history yet.",
        "Your holding: " + held_lots + " lots | Player-held float: " + instrument.issued + " lots",
        status
    ];
}

function ModernMarket::BoardLines(portfolio, selected)
{
    local lines = ["MARKET BOARD  (> selected)"];
    local kind = -1;
    foreach (index, instrument in this.instruments) {
        if (instrument.kind != kind) {
            kind = instrument.kind;
            lines.append(kind == MT_KIND_COMPANY ? "COMPANIES" : "INDUSTRIES");
        }
        local line = (index == selected ? "> " : "   ") + instrument.name + ": " + this.FormatMoney(instrument.price) +
            " (" + MT_Percent(MT_ChangeBp(instrument.previous_price, instrument.price)) + ")";
        if (portfolio.holdings.rawin(instrument.id)) line += " | you hold " + portfolio.holdings[instrument.id].lots;
        if (!this.IsOpenForTrading(instrument)) line += " | opens " + MT_MonthName(instrument.opens);
        lines.append(line);
    }
    if (this.instruments.len() == 0) lines.append("No securities are listed.");
    return lines;
}
