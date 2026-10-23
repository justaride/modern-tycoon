/*
 * The Transport Ledger: a structured newspaper for the Modern Tycoon lab.
 *
 * Producers record facts once in a bounded journal (typed parameters and a
 * stable template ID, never a finished paragraph). An edition groups the
 * unpublished facts into sections, picks a lead story, folds repeated
 * reports into one line, and is archived as structured items.
 *
 * Presentation: every edition gets its own Story Book page, rendered from
 * lang/*.txt so players see formatted, translated text with real currency.
 * Stories about a place (industries, company headquarters) become location
 * lines that scroll the map. A fixed front page lists the back issues.
 *
 * Everything here is deterministic: fixed section order, ID-sorted company
 * loops, no randomness, and no wall clock.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

MT_SEV_MINOR <- 0;
MT_SEV_NORMAL <- 1;
MT_SEV_MAJOR <- 2;

MT_JOURNAL_LIMIT <- 160;
MT_EDITION_ARCHIVE_LIMIT <- 12;
MT_SECTION_LINE_LIMIT <- 4;
MT_AGGREGATE_THRESHOLD <- 3;
MT_SAVED_TEXT_LIMIT <- 240;
MT_MAX_NESTED_PARAMS <- 7;   // {STRING7} is the deepest nesting a GameScript string allows.

MT_SECTIONS <- ["markets", "companies", "rivals", "industry", "transport"];

/* Schema 3 stored finished section titles; used to read old editions back, and for the log. */
MT_SECTION_TITLES <- {
    markets = "MARKETS",
    companies = "COMPANIES",
    rivals = "RIVAL WATCH",
    industry = "INDUSTRY",
    transport = "TRANSPORT",
    earlier = "EARLIER REPORTS"
};

MT_VALUE_MILESTONES <- [1000000, 5000000, 10000000, 50000000, 100000000, 500000000];

/*
 * Rival desk hook. Known rival AIs get a named beat in Rival Watch, matched by
 * company-name prefix. `key` selects STR_LEDGER_DESK_<KEY> in the language
 * files; `desk` is the English text for the script log. Unknown companies are
 * profiled from their fleet, so new AIs show up without any change here. No AI
 * depends on the newspaper, and the newspaper depends on no AI.
 */
MT_RIVAL_DESKS <- [
    { prefix = "Nordlys Air", key = "nordlys",    desk = "the Norwegian-flavoured airline" },
    { prefix = "Fjellbanen",  key = "fjellbanen", desk = "the mountain rail freight operator" }
];

MT_DESK_ENGLISH <- {
    rail = "a railway company", road = "a road haulier", water = "a shipping line", air = "an airline",
    none = "a company without vehicles"
};

MT_MONTH_NAMES <- ["January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"];

/* Routine reports fill sections but never lead an edition while there is other news. */
MT_ROUTINE_TEMPLATES <- {
    market_movers = true, market_close = true, rival_profile = true, rival_desk = true, cargo_leader = true,
    dividend = true, distribution = true, industry_listed = true, industry_close_unlisted = true
};

/* Fleet types in a fixed order, with English words for the script log. */
MT_FLEET <- [
    { type = GSVehicle.VT_RAIL,  key = "rail",  noun = "trains",        sector = "rail transport" },
    { type = GSVehicle.VT_ROAD,  key = "road",  noun = "road vehicles", sector = "road transport" },
    { type = GSVehicle.VT_WATER, key = "water", noun = "ships",         sector = "shipping" },
    { type = GSVehicle.VT_AIR,   key = "air",   noun = "aircraft",      sector = "aviation" }
];

function MT_Money(value)
{
    return value < 0 ? "-" + (-value) : value.tostring();
}

function MT_Signed(value)
{
    return value > 0 ? "+" + value : value.tostring();
}

/* Basis points as a signed percentage with two decimals, e.g. 912 -> "+9.12%". */
function MT_Percent(bp)
{
    local sign = bp > 0 ? "+" : (bp < 0 ? "-" : "");
    local magnitude = bp < 0 ? -bp : bp;
    local cents = magnitude % 100;
    return sign + (magnitude / 100) + "." + (cents < 10 ? "0" : "") + cents + "%";
}

function MT_ShortText(text)
{
    if (typeof text != "string") return text;
    return text.len() > MT_SAVED_TEXT_LIMIT ? text.slice(0, MT_SAVED_TEXT_LIMIT) : text;
}

function MT_FleetFor(key)
{
    foreach (fleet in MT_FLEET) if (fleet.key == key) return fleet;
    return MT_FLEET[0];
}

/* ------------------------------------------------------------------ story text */

/*
 * A GSText plus the number of parameters it consumes. Strings are raw text,
 * integers are numbers or money, and tables are nested story texts. A nested
 * text with n parameters needs {STRINGn} in the enclosing string, which is
 * why wrappers exist in eight variants.
 */
function MT_T(name, args)
{
    local text = GSText(GSText[name]);
    local n = 0;
    foreach (arg in args) {
        if (typeof arg == "table") {
            text.AddParam(arg.text);
            n += arg.n + 1;
        } else {
            text.AddParam(arg);
            n++;
        }
    }
    return { text = text, n = n };
}

/* Wrap a story text in STR_LEDGER_<kind>_<n>, after the wrapper's own leading parameters. */
function MT_Wrap(kind, prefix, inner)
{
    if (inner.n > MT_MAX_NESTED_PARAMS) inner = MT_T("STR_LEDGER_T_UNKNOWN", ["text too long"]);
    local args = clone prefix;
    args.append(inner);
    return MT_T("STR_LEDGER_" + kind + "_" + inner.n, args);
}

function MT_EditionLabel(edition)
{
    if (edition.number == 0) return MT_T("STR_LEDGER_EDITION_EARLIER", ["", "", ""]);
    return MT_T("STR_LEDGER_EDITION_LABEL", [edition.number, MT_T("STR_LEDGER_MONTH_" + edition.month, []), edition.year]);
}

function MT_SectionTitle(key)
{
    return MT_T("STR_LEDGER_SECTION", [MT_T("STR_LEDGER_SECTION_" + key.toupper(), [])]);
}

/* Story text for one journal event or archived item. Template IDs are stable: never rename them. */
function MT_ItemText(item)
{
    if (item.rawin("agg") && item.agg) return MT_AggregateText(item.template, item.params);

    local p = item.params;
    switch (item.template) {
        case "exchange_open":   return MT_T("STR_LEDGER_T_EXCHANGE_OPEN", [p[0]]);
        case "company_listed":  return MT_T("STR_LEDGER_T_COMPANY_LISTED", [p[0], p[1]]);
        case "industry_listed": return MT_T("STR_LEDGER_T_INDUSTRY_LISTED", [p[0]]);
        case "delisted":        return MT_T("STR_LEDGER_T_DELISTED", [p[0], p[1]]);
        case "dividend":        return MT_T("STR_LEDGER_T_DIVIDEND", [p[0], p[1]]);
        case "distribution":    return MT_T("STR_LEDGER_T_DISTRIBUTION", [p[0], p[1], p[2]]);
        case "market_movers":
            if (p[3] == p[0]) return MT_T("STR_LEDGER_T_MARKET_CLOSE_ONE", [p[0], p[1], MT_Signed(p[2]) + "%", p[5]]);
            return MT_T("STR_LEDGER_T_MARKET_CLOSE", [p[0], p[1], MT_Signed(p[2]) + "%", p[3], MT_Signed(p[4]) + "%", p[5]]);
        case "market_close":
            if (p[0] == p[3]) return MT_T("STR_LEDGER_T_MARKET_CLOSE_ONE", [p[0], p[1], MT_Percent(p[2]), p[5]]);
            return MT_T("STR_LEDGER_T_MARKET_CLOSE", [p[0], p[1], MT_Percent(p[2]), p[3], MT_Percent(p[4]), p[5]]);
        case "merger":          return MT_T("STR_LEDGER_T_MERGER", [p[0], p[1]]);
        case "company_founded": return MT_T("STR_LEDGER_T_COMPANY_FOUNDED", [p[0]]);
        case "company_trouble": return MT_T("STR_LEDGER_T_COMPANY_TROUBLE", [p[0]]);
        case "company_closed":  return MT_T("STR_LEDGER_T_COMPANY_CLOSED", [p[0]]);
        case "value_milestone": return MT_T("STR_LEDGER_T_VALUE_MILESTONE", [p[0], p[1]]);
        case "industry_open":   return MT_T("STR_LEDGER_T_INDUSTRY_OPEN", [p[1], p[0]]);
        case "industry_close":  return MT_T("STR_LEDGER_T_INDUSTRY_CLOSE", [p[0]]);
        case "industry_close_unlisted": return MT_T("STR_LEDGER_T_INDUSTRY_CLOSE_UNLISTED", []);
        case "rival_desk":      return MT_T("STR_LEDGER_T_RIVAL_DESK", [p[0], MT_T("STR_LEDGER_DESK_" + p[1].toupper(), []), p[2], p[3]]);
        case "fleet_entry":     return MT_T("STR_LEDGER_T_ENTRY_" + p[1].toupper(), [p[0], p[2]]);
        case "fleet_growth":    return MT_T("STR_LEDGER_T_GROWTH_" + p[1].toupper(), [p[0], p[2], p[3]]);
        case "cargo_leader":    return MT_T("STR_LEDGER_T_CARGO_LEADER", [p[0], p[1]]);
        case "legacy":          return MT_T("STR_LEDGER_T_LEGACY", [p[0]]);
        /* Schema 3 rival reports carried English words; they are only read back, never recorded. */
        case "rival_profile":   return MT_T("STR_LEDGER_T_PROFILE_OLD", [p[0], p[1], p[2], p[3]]);
        case "rival_entry":     return MT_T("STR_LEDGER_T_ENTRY_OLD", [p[0], p[1], p[2], p[3]]);
        case "rival_growth":    return MT_T("STR_LEDGER_T_GROWTH_OLD", [p[0], p[1], p[2], p[3]]);
    }
    return MT_T("STR_LEDGER_T_UNKNOWN", [item.template]);
}

/* Folded reports: [count, more, name, name, name], or [count, best name, best value] for payouts. */
function MT_AggregateText(template, p)
{
    switch (template) {
        case "industry_close_unlisted": return MT_T("STR_LEDGER_A_INDUSTRY_CLOSE_UNLISTED", [p[0]]);
        case "dividend":     return MT_T("STR_LEDGER_A_DIVIDEND", [p[0], p[1], p[2]]);
        case "distribution": return MT_T("STR_LEDGER_A_DISTRIBUTION", [p[0], p[1], p[2]]);
    }
    if (p.len() < 5) return MT_T("STR_LEDGER_A_COUNT", [p[0]]);
    local names = p[1] > 0
        ? MT_T("STR_LEDGER_NAMES_MORE", [p[2], p[3], p[4], p[1]])
        : MT_T("STR_LEDGER_NAMES_3", [p[2], p[3], p[4], ""]);
    switch (template) {
        case "company_listed":  return MT_T("STR_LEDGER_A_COMPANY_LISTED", [p[0], names]);
        case "industry_listed": return MT_T("STR_LEDGER_A_INDUSTRY_LISTED", [p[0], names]);
        case "industry_open":   return MT_T("STR_LEDGER_A_INDUSTRY_OPEN", [p[0], names]);
        case "rival_growth":
        case "fleet_growth":    return MT_T("STR_LEDGER_A_RIVAL_GROWTH", [p[0], names]);
    }
    return MT_T("STR_LEDGER_A_GENERIC", [p[0], names]);
}

/* ------------------------------------------------------------------ log text */

/* English text for the script log, so headless tests and reviewers can read editions. */
function MT_PlainItem(item)
{
    if (item.rawin("agg") && item.agg) return MT_PlainAggregate(item.template, item.params);

    local p = item.params;
    switch (item.template) {
        case "exchange_open":   return "The Modern Tycoon Exchange opens with " + p[0] + " listed securities.";
        case "company_listed":  return p[0] + " lists on the exchange at " + MT_Money(p[1]) + " per 1% lot.";
        case "industry_listed": return p[0] + " receives an exchange listing tied to transported production.";
        case "delisted":        return p[0] + " is delisted; holders are paid the final quote of " + MT_Money(p[1]) + " per lot.";
        case "dividend":        return p[0] + " declares a quarterly dividend of " + MT_Money(p[1]) + " per 1% lot.";
        case "distribution":    return p[0] + " pays " + MT_Money(p[1]) + " per lot after moving " + p[2] + " cargo units this quarter.";
        case "market_movers":
            if (p[3] == p[0]) return "Exchange close: " + p[0] + " at " + MT_Money(p[1]) + " (" + MT_Signed(p[2]) + "%). " + p[5] + " securities listed.";
            return "Exchange close: " + p[0] + " leads at " + MT_Money(p[1]) + " (" + MT_Signed(p[2]) + "%), " + p[3] + " lags (" + MT_Signed(p[4]) + "%). " + p[5] + " securities listed.";
        case "market_close":
            if (p[0] == p[3]) return "Exchange close: " + p[0] + " at " + MT_Money(p[1]) + " (" + MT_Percent(p[2]) + "). " + p[5] + " securities listed.";
            return "Exchange close: " + p[0] + " leads at " + MT_Money(p[1]) + " (" + MT_Percent(p[2]) + "); " + p[3] + " is weakest (" + MT_Percent(p[4]) + "). " + p[5] + " securities listed.";
        case "merger":          return p[0] + " takes over " + p[1] + ". The acquired investment portfolio moves to the new owner.";
        case "company_founded": return p[0] + " is founded and joins the transport market.";
        case "company_trouble": return p[0] + " is in financial trouble and may soon be offered for sale.";
        case "company_closed":  return p[0] + " has gone bankrupt and closes down.";
        case "value_milestone": return p[0] + " passes a company value of " + MT_Money(p[1]) + ".";
        case "industry_open":   return "A new " + p[1] + " opens: " + p[0] + ".";
        case "industry_close":  return p[0] + " closes its gates.";
        case "industry_close_unlisted": return "An unlisted industry has closed.";
        case "rival_desk": {
            local desk = MT_DESK_ENGLISH.rawin(p[1]) ? MT_DESK_ENGLISH[p[1]] : p[1];
            foreach (known in MT_RIVAL_DESKS) if (known.key == p[1]) desk = known.desk;
            return "Profile: " + p[0] + ", " + desk + ", runs " + p[2] + " vehicles and is valued at " + MT_Money(p[3]) + ".";
        }
        case "fleet_entry": {
            local fleet = MT_FleetFor(p[1]);
            return p[0] + " enters " + fleet.sector + " with " + p[2] + " " + fleet.noun + ".";
        }
        case "fleet_growth":    return p[0] + " adds " + p[2] + " " + MT_FleetFor(p[1]).noun + " (" + p[3] + " in service).";
        case "cargo_leader":    return p[0] + " delivered the most cargo last quarter: " + p[1] + " units.";
        case "legacy":          return p[0];
        case "rival_profile":   return "Profile: " + p[0] + ", " + p[1] + ", runs " + p[2] + " and is valued at " + MT_Money(p[3]) + ".";
        case "rival_entry":     return p[0] + " enters " + p[1] + " with " + p[2] + " " + p[3] + ".";
        case "rival_growth":    return p[0] + " adds " + p[1] + " " + p[2] + " (" + p[3] + " in service).";
    }
    return "[" + item.template + "]";
}

function MT_PlainAggregate(template, p)
{
    switch (template) {
        case "industry_close_unlisted": return p[0] + " unlisted industries have closed.";
        case "dividend":     return p[0] + " companies declare dividends; the richest is " + p[1] + " at " + MT_Money(p[2]) + " per lot.";
        case "distribution": return p[0] + " industries pay distributions; the richest is " + p[1] + " at " + MT_Money(p[2]) + " per lot.";
    }
    if (p.len() < 5) return p[0] + " similar reports.";
    local named = p[2] + ", " + p[3] + (p[1] > 0 ? ", " + p[4] + " and " + p[1] + " more" : " and " + p[4]);
    switch (template) {
        case "company_listed":  return p[0] + " companies list on the exchange: " + named + ".";
        case "industry_listed": return p[0] + " industries receive exchange listings: " + named + ".";
        case "industry_open":   return p[0] + " new industries open, including " + named + ".";
        case "rival_growth":
        case "fleet_growth":    return p[0] + " expansion reports: " + named + " are growing their fleets.";
    }
    return p[0] + " reports: " + named + ".";
}

/* Fold three or more reports of one kind into one archived item. */
function MT_Aggregate(template, events)
{
    local count = events.len();
    if (template == "industry_close_unlisted") return { template = template, params = [count], agg = true, tile = -1 };
    if (template == "dividend" || template == "distribution") {
        local best = events[0];
        foreach (event in events) if (event.params[1] > best.params[1]) best = event;
        return { template = template, params = [count, best.params[0], best.params[1]], agg = true, tile = -1 };
    }
    local names = [];
    foreach (event in events) {
        if (event.params.len() > 0 && typeof event.params[0] == "string") names.append(event.params[0]);
    }
    if (names.len() < 3) return { template = template, params = [count], agg = true, tile = -1 };
    return { template = template, params = [count, names.len() - 3, names[0], names[1], names[2]], agg = true, tile = -1 };
}

/* An archived item keeps the template, parameters and map location of its event. */
function MT_Item(event)
{
    return { template = event.template, params = event.params, tile = event.rawin("tile") ? event.tile : -1 };
}

class TransportLedger {
    journal = null;          // Array of facts: { seq, year, month, section, severity, template, params, ref_type, ref_id, key, tile }
    next_seq = 1;
    last_edition_seq = 0;    // Facts with a higher seq are not published yet.
    editions = null;         // Archive: { number, year, month, lead = item, sections = [{ key, items, more }], page }
    edition_number = 0;
    popups = 0;
    front_page = -1;         // The index page: masthead, latest lead, back issues.
    front_elements = null;
    archive_page = -1;       // Schema 3 only; removed on load.
    archive_body = -1;
    rivals = null;           // company key -> { name, value, rail, road, water, air }
    last_cargo_quarter = -1;

    constructor(saved, legacy_headlines)
    {
        this.journal = [];
        this.editions = [];
        this.front_elements = [];
        this.rivals = {};

        if (saved != null) {
            foreach (field in ["journal", "next_seq", "last_edition_seq", "editions", "edition_number", "popups",
                    "front_page", "front_elements", "archive_page", "archive_body", "rivals", "last_cargo_quarter"]) {
                if (saved.rawin(field)) this[field] = saved[field];
            }
            local upgraded = 0;
            foreach (index, edition in this.editions) {
                if (typeof edition.lead == "string") {
                    this.editions[index] = this.UpgradeEdition(edition);
                    upgraded++;
                }
            }
            if (upgraded > 0) GSLog.Info("MT-LEDGER UPGRADED editions=" + upgraded);
            return;
        }

        /* Schema 2 saves kept finished English headlines; keep them readable as one archived edition. */
        if (legacy_headlines != null && legacy_headlines.len() > 0) {
            local items = [];
            foreach (text in legacy_headlines) items.append({ template = "legacy", params = [MT_ShortText(text)], tile = -1 });
            this.editions.append({
                number = 0, year = 0, month = 0, page = -1,
                lead = { template = "legacy", params = ["Archive carried over from the first Ledger."], tile = -1 },
                sections = [{ key = "earlier", items = items, more = 0 }]
            });
            GSLog.Info("MT-LEDGER MIGRATED headlines=" + legacy_headlines.len() + " last=" + legacy_headlines[legacy_headlines.len() - 1]);
        }
    }

    /* Schema 3 editions stored finished English lines: { lead = "...", sections = [[title, line, ...]] }. */
    function UpgradeEdition(old)
    {
        local sections = [];
        foreach (lines in old.sections) {
            local key = "earlier";
            foreach (candidate, title in MT_SECTION_TITLES) if (title == lines[0]) key = candidate;
            local items = [];
            for (local i = 1; i < lines.len(); i++) items.append({ template = "legacy", params = [MT_ShortText(lines[i])], tile = -1 });
            sections.append({ key = key, items = items, more = 0 });
        }
        return {
            number = old.number, year = old.year, month = old.month, page = -1,
            lead = { template = "legacy", params = [MT_ShortText(old.lead)], tile = -1 },
            sections = sections
        };
    }

    function GetSaveData()
    {
        return {
            journal = this.journal,
            next_seq = this.next_seq,
            last_edition_seq = this.last_edition_seq,
            editions = this.editions,
            edition_number = this.edition_number,
            popups = this.popups,
            front_page = this.front_page,
            front_elements = this.front_elements,
            rivals = this.rivals,
            last_cargo_quarter = this.last_cargo_quarter
        };
    }

    /* ------------------------------------------------------------ journal */

    /*
     * Record one fact. `key`, when not null, replaces any unpublished fact with
     * the same key (e.g. only the latest exchange close is worth printing).
     * `popup` shows an immediate news message; use it for major events only.
     * A reference to an industry or tile is kept as a map location.
     */
    function Record(section, severity, template, params, ref_type, ref_id, key, popup)
    {
        if (key != null) {
            for (local i = this.journal.len() - 1; i >= 0; i--) {
                local old = this.journal[i];
                if (old.seq <= this.last_edition_seq) break;
                if (old.key == key) this.journal.remove(i);
            }
        }

        local safe_params = [];
        foreach (value in params) safe_params.append(MT_ShortText(value));

        local tile = -1;
        if (ref_type == GSNews.NR_INDUSTRY && GSIndustry.IsValidIndustry(ref_id)) {
            tile = GSIndustry.GetLocation(ref_id);
        } else if (ref_type == GSNews.NR_TILE && GSMap.IsValidTile(ref_id)) {
            tile = ref_id;
        } else {
            ref_type = GSNews.NR_NONE;
            ref_id = 0;
        }

        local date = GSDate.GetCurrentDate();
        local event = {
            seq = this.next_seq++,
            year = GSDate.GetYear(date),
            month = GSDate.GetMonth(date),
            section = section,
            severity = severity,
            template = template,
            params = safe_params,
            ref_type = ref_type,
            ref_id = ref_id,
            key = key,
            tile = tile
        };
        this.journal.append(event);
        while (this.journal.len() > MT_JOURNAL_LIMIT) this.journal.remove(0);

        if (popup) this.Popup(MT_ItemText(event).text, ref_type, ref_id);
        return event;
    }

    function Popup(text, ref_type, ref_id)
    {
        GSNews.Create(GSNews.NT_ECONOMY, text, GSCompany.COMPANY_INVALID, ref_type, ref_id);
        this.popups++;
    }

    function HasUnpublishedMajor()
    {
        foreach (event in this.journal) {
            if (event.seq > this.last_edition_seq && event.severity == MT_SEV_MAJOR) return true;
        }
        return false;
    }

    function CountUnpublished()
    {
        local count = 0;
        foreach (event in this.journal) if (event.seq > this.last_edition_seq) count++;
        return count;
    }

    /* ----------------------------------------------------------- editions */

    /* Group unpublished facts into an edition. Returns the edition, or null when there was no news. */
    function PublishEdition(with_popup)
    {
        local pending = [];
        foreach (event in this.journal) if (event.seq > this.last_edition_seq) pending.append(event);
        if (pending.len() == 0) return null;

        /* Lead story: news before routine reports, then highest severity, earliest first on ties. */
        local lead = null;
        foreach (event in pending) {
            if (lead == null || this.LeadRank(event) > this.LeadRank(lead)) lead = event;
        }

        local sections = [];
        foreach (section in MT_SECTIONS) {
            local built = this.BuildSection(section, pending, lead);
            if (built.items.len() > 0) sections.append(built);
        }

        local date = GSDate.GetCurrentDate();
        this.edition_number++;
        local edition = {
            number = this.edition_number,
            year = GSDate.GetYear(date),
            month = GSDate.GetMonth(date),
            lead = MT_Item(lead),
            sections = sections,
            page = -1
        };
        this.editions.append(edition);
        while (this.editions.len() > MT_EDITION_ARCHIVE_LIMIT) {
            local old = this.editions[0];
            if (old.rawin("page") && GSStoryPage.IsValidStoryPage(old.page)) GSStoryPage.Remove(old.page);
            this.editions.remove(0);
        }
        this.last_edition_seq = this.next_seq - 1;

        /* RefreshPages creates the new edition's page along with any other missing page. */
        this.RefreshPages();

        if (with_popup) {
            local text = MT_Wrap("POPUP", [edition.number], MT_ItemText(edition.lead)).text;
            if (this.HasTile(edition.lead)) {
                this.Popup(text, GSNews.NR_TILE, edition.lead.tile);
            } else {
                this.Popup(text, GSNews.NR_NONE, 0);
            }
        }
        this.LogEdition(edition);
        return edition;
    }

    function LeadRank(event)
    {
        return event.severity * 2 + (MT_ROUTINE_TEMPLATES.rawin(event.template) ? 0 : 1);
    }

    /* Editions also go to the script log, so headless tests and reviewers can read them. */
    function LogEdition(edition)
    {
        GSLog.Info("MT-LEDGER EDITION " + this.PlainLabel(edition) + " | LEAD " + MT_PlainItem(edition.lead) +
            (this.HasTile(edition.lead) ? " [map]" : "") + " | page=" + (GSStoryPage.IsValidStoryPage(edition.page) ? "ok" : "missing"));
        foreach (section in edition.sections) {
            local title = MT_SECTION_TITLES[section.key];
            foreach (item in section.items) {
                GSLog.Info("MT-LEDGER   " + title + " | " + MT_PlainItem(item) + (this.HasTile(item) ? " [map]" : ""));
            }
            if (section.more > 0) GSLog.Info("MT-LEDGER   " + title + " | (" + section.more + " smaller reports not shown)");
        }
    }

    function LogStats(label)
    {
        local pages = 0;
        foreach (edition in this.editions) if (edition.rawin("page") && GSStoryPage.IsValidStoryPage(edition.page)) pages++;
        GSLog.Info("MT-LEDGER STATS " + label + " editions=" + this.edition_number + " archived=" + this.editions.len() +
            " pages=" + pages + " popups=" + this.popups + " journal=" + this.journal.len() + " unpublished=" + this.CountUnpublished());
    }

    function PlainLabel(edition)
    {
        if (edition.number == 0) return "Earlier reports";
        return "Edition #" + edition.number + ", " + MT_MONTH_NAMES[edition.month - 1] + " " + edition.year;
    }

    /* At most MT_SECTION_LINE_LIMIT items, most severe first, repeats folded. */
    function BuildSection(section, pending, lead)
    {
        local by_template = {};
        local order = [];
        foreach (event in pending) {
            if (event.section != section || event == lead) continue;
            if (!by_template.rawin(event.template)) {
                by_template[event.template] <- [];
                order.append(event.template);
            }
            by_template[event.template].append(event);
        }

        local entries = [];
        foreach (template in order) {
            local group = by_template[template];
            local severity = 0;
            foreach (event in group) if (event.severity > severity) severity = event.severity;
            if (group.len() >= MT_AGGREGATE_THRESHOLD) {
                entries.append({ severity = severity, seq = group[0].seq, item = MT_Aggregate(template, group) });
            } else {
                foreach (event in group) entries.append({ severity = event.severity, seq = event.seq, item = MT_Item(event) });
            }
        }
        entries.sort(function(a, b) {
            if (a.severity != b.severity) return a.severity > b.severity ? -1 : 1;
            return a.seq < b.seq ? -1 : (a.seq > b.seq ? 1 : 0);
        });

        local items = [];
        for (local i = 0; i < entries.len() && i < MT_SECTION_LINE_LIMIT; i++) items.append(entries[i].item);
        local more = entries.len() > MT_SECTION_LINE_LIMIT ? entries.len() - MT_SECTION_LINE_LIMIT : 0;
        return { key = section, items = items, more = more };
    }

    /* -------------------------------------------------------- story pages */

    /*
     * Make sure the index page and one page per archived edition exist.
     * Reuses the oldest Ledger page as the index so it stays first in the
     * Story Book: the schema 2 newspaper page or the schema 3 front page.
     */
    function EnsurePages(legacy_page, legacy_body)
    {
        if (!GSStoryPage.IsValidStoryPage(this.front_page) && GSStoryPage.IsValidStoryPage(legacy_page)) {
            this.front_page = legacy_page;
            if (GSStoryPage.IsValidStoryPageElement(legacy_body)) GSStoryPage.RemoveElement(legacy_body);
        }
        if (!GSStoryPage.IsValidStoryPage(this.front_page)) {
            this.front_page = GSStoryPage.New(GSCompany.COMPANY_INVALID, GSText(GSText.STR_LEDGER_INDEX_TITLE));
            this.front_elements = [];
        }
        if (GSStoryPage.IsValidStoryPage(this.archive_page)) {
            GSStoryPage.Remove(this.archive_page);
            GSLog.Info("MT-LEDGER removed the schema 3 archive page");
        }
        this.archive_page = -1;
        this.archive_body = -1;

        foreach (edition in this.editions) {
            if (!edition.rawin("page")) edition.page <- -1;
            if (!GSStoryPage.IsValidStoryPage(edition.page)) edition.page = this.CreateEditionPage(edition);
        }
    }

    /* One page per edition: masthead, lead story, then the sections. Pages never change once printed. */
    function CreateEditionPage(edition)
    {
        local title = edition.number == 0
            ? GSText(GSText.STR_LEDGER_PAGE_TITLE_EARLIER)
            : MT_T("STR_LEDGER_PAGE_TITLE", [edition.number]).text;
        local page = GSStoryPage.New(GSCompany.COMPANY_INVALID, title);
        if (!GSStoryPage.IsValidStoryPage(page)) {
            GSLog.Warning("MT-LEDGER could not create a page for " + this.PlainLabel(edition));
            return -1;
        }

        this.Text(page, MT_T("STR_LEDGER_MASTHEAD", [MT_EditionLabel(edition)]));
        this.Text(page, MT_Wrap("LEAD", [], MT_ItemText(edition.lead)));
        if (this.HasTile(edition.lead)) {
            GSStoryPage.NewElement(page, GSStoryPage.SPET_LOCATION, edition.lead.tile, GSText(GSText.STR_LEDGER_SHOW_ON_MAP));
        }

        foreach (section in edition.sections) {
            this.Text(page, MT_SectionTitle(section.key));
            foreach (item in section.items) {
                local line = MT_Wrap("LINE", [], MT_ItemText(item)).text;
                if (this.HasTile(item)) {
                    GSStoryPage.NewElement(page, GSStoryPage.SPET_LOCATION, item.tile, line);
                } else {
                    GSStoryPage.NewElement(page, GSStoryPage.SPET_TEXT, 0, line);
                }
            }
            if (section.more > 0) this.Text(page, MT_T("STR_LEDGER_MORE", [section.more]));
        }

        if (edition.year > 0 && this.UsesCalendarTimekeeping()) {
            GSStoryPage.SetDate(page, GSDate.GetDate(edition.year, edition.month, 1));
        }
        return page;
    }

    function Text(page, story)
    {
        return GSStoryPage.NewElement(page, GSStoryPage.SPET_TEXT, 0, story.text);
    }

    function HasTile(item)
    {
        return item.rawin("tile") && item.tile >= 0 && GSMap.IsValidTile(item.tile);
    }

    /* Rebuild the index page: masthead, the latest lead, then the back issues, newest first. */
    function RefreshPages()
    {
        this.EnsurePages(-1, -1);
        foreach (element in this.front_elements) {
            if (GSStoryPage.IsValidStoryPageElement(element)) GSStoryPage.RemoveElement(element);
        }
        this.front_elements = [];
        local page = this.front_page;
        GSStoryPage.SetTitle(page, GSText(GSText.STR_LEDGER_INDEX_TITLE));

        this.front_elements.append(GSStoryPage.NewElement(page, GSStoryPage.SPET_TEXT, 0, GSText(GSText.STR_LEDGER_INDEX_INTRO)));
        if (this.editions.len() == 0) {
            this.front_elements.append(GSStoryPage.NewElement(page, GSStoryPage.SPET_TEXT, 0, GSText(GSText.STR_LEDGER_INDEX_EMPTY)));
        } else {
            local latest = this.editions[this.editions.len() - 1];
            this.front_elements.append(this.Text(page, MT_Wrap("LATEST", [MT_EditionLabel(latest)], MT_ItemText(latest.lead))));
            if (this.editions.len() > 1) {
                this.front_elements.append(GSStoryPage.NewElement(page, GSStoryPage.SPET_TEXT, 0, GSText(GSText.STR_LEDGER_INDEX_ARCHIVE)));
                for (local i = this.editions.len() - 2; i >= 0; i--) {
                    local edition = this.editions[i];
                    this.front_elements.append(this.Text(page, MT_Wrap("ENTRY", [MT_EditionLabel(edition)], MT_ItemText(edition.lead))));
                }
            }
        }

        if (this.UsesCalendarTimekeeping()) GSStoryPage.SetDate(page, GSDate.GetCurrentDate());
    }

    function UsesCalendarTimekeeping()
    {
        local setting = "economy.timekeeping_units";
        return !GSGameSettings.IsValid(setting) || GSGameSettings.GetValue(setting) == 0;
    }

    /* ------------------------------------------------------- data desks */

    /* Remember names while companies are alive, so closures and takeovers can still be reported. */
    function CompanyName(company_id)
    {
        local key = company_id.tostring();
        if (GSCompany.ResolveCompanyID(company_id) != GSCompany.COMPANY_INVALID) {
            local name = GSCompany.GetName(company_id);
            if (name != null) {
                if (this.rivals.rawin(key)) this.rivals[key].name = MT_ShortText(name);
                return name;
            }
        }
        if (this.rivals.rawin(key)) return this.rivals[key].name;
        return "Company " + (company_id + 1);
    }

    /* The company headquarters as a map reference, when it has one. */
    function HeadquartersTile(company_id)
    {
        if (GSCompany.ResolveCompanyID(company_id) == GSCompany.COMPANY_INVALID) return -1;
        local tile = GSCompany.GetCompanyHQ(company_id);
        return GSMap.IsValidTile(tile) ? tile : -1;
    }

    function RecordAboutCompany(company_id, section, severity, template, params, key, popup)
    {
        local tile = this.HeadquartersTile(company_id);
        return this.Record(section, severity, template, params, tile >= 0 ? GSNews.NR_TILE : GSNews.NR_NONE, tile >= 0 ? tile : 0, key, popup);
    }

    function DeskFor(name, snapshot)
    {
        foreach (desk in MT_RIVAL_DESKS) {
            if (name.find(desk.prefix) == 0) return desk.key;
        }
        local best = null, best_count = 0;
        foreach (fleet in MT_FLEET) {
            if (snapshot[fleet.key] > best_count) {
                best = fleet;
                best_count = snapshot[fleet.key];
            }
        }
        return best == null ? "none" : best.key;
    }

    /*
     * Rival Watch: compare each company's fleet and value with the last
     * observation. `silent` only takes the snapshot (used at game start).
     */
    function ObserveRivals(silent)
    {
        local counts = {};
        foreach (vehicle, unused in GSVehicleList()) {
            local owner = GSVehicle.GetOwner(vehicle);
            local key = owner.tostring();
            if (!counts.rawin(key)) counts[key] <- { rail = 0, road = 0, water = 0, air = 0 };
            local type = GSVehicle.GetVehicleType(vehicle);
            foreach (fleet in MT_FLEET) if (fleet.type == type) counts[key][fleet.key]++;
        }

        local profiled = [];
        for (local company_id = GSCompany.COMPANY_FIRST; company_id < GSCompany.COMPANY_LAST; company_id++) {
            if (GSCompany.ResolveCompanyID(company_id) == GSCompany.COMPANY_INVALID) continue;
            local key = company_id.tostring();
            local name = MT_ShortText(this.CompanyName(company_id));
            local now = counts.rawin(key) ? counts[key] : { rail = 0, road = 0, water = 0, air = 0 };
            local value = GSCompany.GetQuarterlyCompanyValue(company_id, GSCompany.CURRENT_QUARTER);
            local before = this.rivals.rawin(key) ? this.rivals[key] : null;

            if (!silent && before != null) {
                foreach (fleet in MT_FLEET) {
                    local had = before[fleet.key], has = now[fleet.key];
                    if (had == 0 && has > 0) {
                        this.RecordAboutCompany(company_id, "rivals", MT_SEV_NORMAL, "fleet_entry", [name, fleet.key, has], null, false);
                    } else if (had > 0 && has - had >= this.MaxValue(3, had / 4)) {
                        this.RecordAboutCompany(company_id, "rivals", MT_SEV_MINOR, "fleet_growth", [name, fleet.key, has - had, has], null, false);
                    }
                }
                local passed = 0;
                foreach (milestone in MT_VALUE_MILESTONES) {
                    if (before.value < milestone && value >= milestone) passed = milestone;
                }
                if (passed > 0) this.RecordAboutCompany(company_id, "companies", MT_SEV_NORMAL, "value_milestone", [name, passed], null, false);
            }

            this.rivals[key] <- { name = name, value = value, rail = now.rail, road = now.road, water = now.water, air = now.air };
            if (now.rail + now.road + now.water + now.air > 0) profiled.append(company_id);
        }

        /* One rotating profile per edition keeps the desk lively but short. */
        if (!silent && profiled.len() > 0) {
            local company_id = profiled[this.edition_number % profiled.len()];
            local snap = this.rivals[company_id.tostring()];
            this.RecordAboutCompany(company_id, "rivals", MT_SEV_MINOR, "rival_desk",
                [snap.name, this.DeskFor(snap.name, snap), snap.rail + snap.road + snap.water + snap.air, snap.value], "profile", false);
        }
    }

    /* Transport desk: once per quarter, the company that delivered the most cargo. */
    function ObserveCargo()
    {
        local date = GSDate.GetCurrentDate();
        local quarter_key = GSDate.GetYear(date) * 4 + (GSDate.GetMonth(date) - 1) / 3;
        if (quarter_key == this.last_cargo_quarter) return;
        local first = this.last_cargo_quarter < 0;
        this.last_cargo_quarter = quarter_key;
        if (first) return;

        local best = GSCompany.COMPANY_INVALID, best_amount = 0;
        for (local company_id = GSCompany.COMPANY_FIRST; company_id < GSCompany.COMPANY_LAST; company_id++) {
            if (GSCompany.ResolveCompanyID(company_id) == GSCompany.COMPANY_INVALID) continue;
            local amount = GSCompany.GetQuarterlyCargoDelivered(company_id, GSCompany.CURRENT_QUARTER + 1);
            if (amount > best_amount) {
                best = company_id;
                best_amount = amount;
            }
        }
        if (best != GSCompany.COMPANY_INVALID) {
            this.RecordAboutCompany(best, "transport", MT_SEV_MINOR, "cargo_leader", [this.CompanyName(best), best_amount], null, false);
        }
    }

    /* Company and industry desks, fed by engine events. Call before the market forgets anything. */
    function HandleEvent(event, market)
    {
        local type = event.GetEventType();
        if (type == GSEvent.ET_COMPANY_NEW) {
            local company_id = GSEventCompanyNew.Convert(event).GetCompanyID();
            this.Record("companies", MT_SEV_NORMAL, "company_founded", [MT_ShortText(this.CompanyName(company_id))], GSNews.NR_NONE, 0, null, false);
        } else if (type == GSEvent.ET_COMPANY_IN_TROUBLE) {
            local company_id = GSEventCompanyInTrouble.Convert(event).GetCompanyID();
            this.RecordAboutCompany(company_id, "companies", MT_SEV_NORMAL, "company_trouble", [MT_ShortText(this.CompanyName(company_id))], null, false);
        } else if (type == GSEvent.ET_COMPANY_BANKRUPT) {
            local company_id = GSEventCompanyBankrupt.Convert(event).GetCompanyID();
            this.Record("companies", MT_SEV_MAJOR, "company_closed", [MT_ShortText(this.CompanyName(company_id))], GSNews.NR_NONE, 0, null, true);
            this.Forget(company_id);
        } else if (type == GSEvent.ET_COMPANY_MERGER) {
            local merger = GSEventCompanyMerger.Convert(event);
            local acquirer = MT_ShortText(this.CompanyName(merger.GetNewCompanyID()));
            local acquired = MT_ShortText(this.CompanyName(merger.GetOldCompanyID()));
            this.RecordAboutCompany(merger.GetNewCompanyID(), "companies", MT_SEV_MAJOR, "merger", [acquirer, acquired], null, true);
            this.Forget(merger.GetOldCompanyID());
        } else if (type == GSEvent.ET_INDUSTRY_OPEN) {
            local industry_id = GSEventIndustryOpen.Convert(event).GetIndustryID();
            if (!GSIndustry.IsValidIndustry(industry_id)) return;
            local name = GSIndustry.GetName(industry_id);
            local type_name = GSIndustryType.GetName(GSIndustry.GetIndustryType(industry_id));
            this.Record("industry", MT_SEV_MINOR, "industry_open",
                [MT_ShortText(name == null ? "an industry" : name), MT_ShortText(type_name == null ? "industry" : type_name.tolower())],
                GSNews.NR_INDUSTRY, industry_id, null, false);
        } else if (type == GSEvent.ET_INDUSTRY_CLOSE) {
            local industry_id = GSEventIndustryClose.Convert(event).GetIndustryID();
            local name = market == null ? null : market.ListedIndustryName(industry_id);
            if (name == null) {
                this.Record("industry", MT_SEV_MINOR, "industry_close_unlisted", [], GSNews.NR_NONE, 0, null, false);
            } else {
                this.Record("industry", MT_SEV_NORMAL, "industry_close", [MT_ShortText(name)], GSNews.NR_NONE, 0, null, false);
            }
        }
    }

    function Forget(company_id)
    {
        local key = company_id.tostring();
        if (this.rivals.rawin(key)) delete this.rivals[key];
    }

    function MaxValue(a, b)
    {
        return a > b ? a : b;
    }
}
