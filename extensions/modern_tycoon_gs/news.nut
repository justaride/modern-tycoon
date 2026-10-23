/*
 * The Transport Ledger: a structured newspaper for the Modern Tycoon lab.
 *
 * Producers record facts once in a bounded journal (typed parameters and a
 * stable template ID, never a finished paragraph). An edition groups the
 * unpublished facts into sections, picks a lead story, folds repeated
 * reports into one line, and is archived. Text is rendered from templates,
 * so old journal entries stay readable as long as their template ID exists.
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

MT_SECTIONS <- ["markets", "companies", "rivals", "industry", "transport"];
MT_SECTION_TITLES <- {
    markets = "MARKETS",
    companies = "COMPANIES",
    rivals = "RIVAL WATCH",
    industry = "INDUSTRY",
    transport = "TRANSPORT"
};

MT_VALUE_MILESTONES <- [1000000, 5000000, 10000000, 50000000, 100000000, 500000000];

/*
 * Rival desk hook. Known rival AIs get a named beat in Rival Watch, matched by
 * company-name prefix. Unknown companies are profiled from their fleet, so
 * new AIs show up without any change here. This is plain data on purpose:
 * no AI depends on the newspaper, and the newspaper depends on no AI.
 */
MT_RIVAL_DESKS <- [
    { prefix = "Nordlys Air", desk = "the Norwegian-flavoured airline" },
    { prefix = "Fjellbanen", desk = "the mountain rail freight operator" }
];

MT_MONTH_NAMES <- ["January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"];

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

/* Routine reports fill sections but never lead an edition while there is other news. */
MT_ROUTINE_TEMPLATES <- {
    market_movers = true, market_close = true, rival_profile = true, cargo_leader = true,
    dividend = true, distribution = true, industry_listed = true, industry_close_unlisted = true,
    market_quarter = true, production_boom = true, production_slump = true
};

function MT_ShortText(text)
{
    if (typeof text != "string") return text;
    return text.len() > MT_SAVED_TEXT_LIMIT ? text.slice(0, MT_SAVED_TEXT_LIMIT) : text;
}

/* Fleet types in a fixed order, with display words. */
MT_FLEET <- [
    { type = GSVehicle.VT_RAIL,  key = "rail",  noun = "trains",        sector = "rail transport" },
    { type = GSVehicle.VT_ROAD,  key = "road",  noun = "road vehicles", sector = "road transport" },
    { type = GSVehicle.VT_WATER, key = "water", noun = "ships",         sector = "shipping" },
    { type = GSVehicle.VT_AIR,   key = "air",   noun = "aircraft",      sector = "aviation" }
];

/* One line of text for one journal event. Template IDs are stable: never rename them. */
function MT_RenderEvent(event)
{
    local p = event.params;
    switch (event.template) {
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
        case "rival_profile":   return "Profile: " + p[0] + ", " + p[1] + ", runs " + p[2] + " and is valued at " + MT_Money(p[3]) + ".";
        case "rival_entry":     return p[0] + " enters " + p[1] + " with " + p[2] + " " + p[3] + ".";
        case "rival_growth":    return p[0] + " adds " + p[1] + " " + p[2] + " (" + p[3] + " in service).";
        case "cargo_leader":    return p[0] + " delivered the most cargo last quarter: " + p[1] + " units.";
        case "market_quarter":
            return "Quarter in review: " + p[0] + " gained most (" + MT_Percent(p[1]) + "), " + p[2] + " fell most (" +
                MT_Percent(p[3]) + "). " + p[4] + " securities rose, " + p[5] + " fell.";
        case "results_beat":    return p[0] + " beats expectations: quarterly profit " + MT_Money(p[1]) + " against " + MT_Money(p[2]) + " expected.";
        case "results_miss":    return p[0] + " misses expectations: quarterly profit " + MT_Money(p[1]) + " against " + MT_Money(p[2]) + " expected.";
        case "quarterly_loss":  return p[0] + " reports a quarterly loss of " + MT_Money(p[1]) + "; the shares are marked down.";
        case "closure_warning": return p[0] + " warns it will close; its shares slump.";
        case "production_boom": return p[0] + " output jumps to " + p[1] + " units (normally " + p[2] + ").";
        case "production_slump": return p[0] + " output drops to " + p[1] + " units (normally " + p[2] + ").";
        case "legacy":          return p[0];
    }
    return "[" + event.template + "]";
}

/* Fold three or more reports of one kind into one line. */
function MT_RenderAggregate(template, events)
{
    local count = events.len();
    local names = [];
    foreach (event in events) {
        if (event.params.len() > 0 && typeof event.params[0] == "string") names.append(event.params[0]);
    }
    local named = "";
    for (local i = 0; i < names.len() && i < 3; i++) named += (i == 0 ? "" : ", ") + names[i];
    if (names.len() > 3) named += " and " + (names.len() - 3) + " more";

    switch (template) {
        case "company_listed":  return count + " companies list on the exchange: " + named + ".";
        case "industry_listed": return count + " industries receive exchange listings: " + named + ".";
        case "industry_open":   return count + " new industries open, including " + named + ".";
        case "industry_close_unlisted": return count + " unlisted industries have closed.";
        case "dividend":
        case "distribution": {
            local best = events[0];
            foreach (event in events) if (event.params[1] > best.params[1]) best = event;
            return count + (template == "dividend" ? " companies declare dividends" : " industries pay distributions") +
                "; the richest is " + best.params[0] + " at " + MT_Money(best.params[1]) + " per lot.";
        }
        case "rival_growth":    return count + " expansion reports: " + named + " are growing their fleets.";
        case "results_beat":    return count + " companies beat expectations: " + named + ".";
        case "results_miss":    return count + " companies miss expectations: " + named + ".";
        case "production_boom": return count + " industries report output jumps: " + named + ".";
        case "production_slump": return count + " industries report output drops: " + named + ".";
    }
    return count + " reports: " + named + ".";
}

class TransportLedger {
    journal = null;          // Array of facts: { seq, year, month, section, severity, template, params, ref_type, ref_id, key }
    next_seq = 1;
    last_edition_seq = 0;    // Facts with a higher seq are not published yet.
    editions = null;         // Archive: { number, year, month, lead, sections = [[title, line, ...], ...] }
    edition_number = 0;
    popups = 0;
    front_page = -1;
    front_elements = null;   // Story page elements: masthead first, then one per section.
    archive_page = -1;
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
            return;
        }

        /* Schema 2 saves kept finished English headlines; keep them readable as one archived edition. */
        if (legacy_headlines != null && legacy_headlines.len() > 0) {
            local lines = ["EARLIER REPORTS"];
            foreach (text in legacy_headlines) lines.append(MT_ShortText(text));
            this.editions.append({ number = 0, year = 0, month = 0, lead = "Archive carried over from the first Ledger.", sections = [lines] });
            GSLog.Info("MT-LEDGER MIGRATED headlines=" + legacy_headlines.len() + " last=" + legacy_headlines[legacy_headlines.len() - 1]);
        }
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
            archive_page = this.archive_page,
            archive_body = this.archive_body,
            rivals = this.rivals,
            last_cargo_quarter = this.last_cargo_quarter
        };
    }

    /* ------------------------------------------------------------ journal */

    /*
     * Record one fact. `key`, when not null, replaces any unpublished fact with
     * the same key (e.g. only the latest exchange close is worth printing).
     * `popup` shows an immediate news message; use it for major events only.
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
            key = key
        };
        this.journal.append(event);
        while (this.journal.len() > MT_JOURNAL_LIMIT) this.journal.remove(0);

        if (popup) this.Popup(MT_RenderEvent(event), ref_type, ref_id);
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
            local lines = this.RenderSection(section, pending, lead);
            if (lines.len() > 1) sections.append(lines);
        }

        local date = GSDate.GetCurrentDate();
        this.edition_number++;
        local edition = {
            number = this.edition_number,
            year = GSDate.GetYear(date),
            month = GSDate.GetMonth(date),
            lead = MT_ShortText(MT_RenderEvent(lead)),
            sections = sections
        };
        this.editions.append(edition);
        while (this.editions.len() > MT_EDITION_ARCHIVE_LIMIT) this.editions.remove(0);
        this.last_edition_seq = this.next_seq - 1;

        if (with_popup) this.Popup("The Transport Ledger #" + edition.number + ": " + edition.lead, GSNews.NR_NONE, 0);
        this.LogEdition(edition);
        this.RefreshPages();
        return edition;
    }

    function LeadRank(event)
    {
        return event.severity * 2 + (MT_ROUTINE_TEMPLATES.rawin(event.template) ? 0 : 1);
    }

    /* Editions also go to the script log, so headless tests and reviewers can read them. */
    function LogEdition(edition)
    {
        GSLog.Info("MT-LEDGER EDITION " + this.EditionLabel(edition) + " | LEAD " + edition.lead);
        foreach (lines in edition.sections) {
            for (local i = 1; i < lines.len(); i++) GSLog.Info("MT-LEDGER   " + lines[0] + " | " + lines[i]);
        }
    }

    function LogStats(label)
    {
        GSLog.Info("MT-LEDGER STATS " + label + " editions=" + this.edition_number + " archived=" + this.editions.len() +
            " popups=" + this.popups + " journal=" + this.journal.len() + " unpublished=" + this.CountUnpublished());
    }

    /* Title line plus at most MT_SECTION_LINE_LIMIT lines, most severe first, repeats folded. */
    function RenderSection(section, pending, lead)
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

        local items = [];
        foreach (template in order) {
            local group = by_template[template];
            local severity = 0;
            foreach (event in group) if (event.severity > severity) severity = event.severity;
            if (group.len() >= MT_AGGREGATE_THRESHOLD) {
                items.append({ severity = severity, seq = group[0].seq, text = MT_RenderAggregate(template, group) });
            } else {
                foreach (event in group) items.append({ severity = event.severity, seq = event.seq, text = MT_RenderEvent(event) });
            }
        }
        items.sort(function(a, b) {
            if (a.severity != b.severity) return a.severity > b.severity ? -1 : 1;
            return a.seq < b.seq ? -1 : (a.seq > b.seq ? 1 : 0);
        });

        local lines = [MT_SECTION_TITLES[section]];
        for (local i = 0; i < items.len() && i < MT_SECTION_LINE_LIMIT; i++) lines.append(MT_ShortText(items[i].text));
        if (items.len() > MT_SECTION_LINE_LIMIT) lines.append("(" + (items.len() - MT_SECTION_LINE_LIMIT) + " smaller reports in the journal)");
        return lines;
    }

    /* -------------------------------------------------------- story pages */

    function EnsurePages(legacy_page, legacy_body)
    {
        /* Reuse the schema 2 front page; its single text body is replaced by sectioned elements. */
        if (!GSStoryPage.IsValidStoryPage(this.front_page) && GSStoryPage.IsValidStoryPage(legacy_page)) {
            this.front_page = legacy_page;
            if (GSStoryPage.IsValidStoryPageElement(legacy_body)) GSStoryPage.RemoveElement(legacy_body);
            this.front_elements = [];
        }
        if (!GSStoryPage.IsValidStoryPage(this.front_page)) {
            this.front_page = GSStoryPage.New(GSCompany.COMPANY_INVALID, "The Transport Ledger");
            this.front_elements = [];
        }
        local valid = this.front_elements.len() == MT_SECTIONS.len() + 1;
        foreach (element in this.front_elements) if (!GSStoryPage.IsValidStoryPageElement(element)) valid = false;
        if (!valid) {
            foreach (element in this.front_elements) {
                if (GSStoryPage.IsValidStoryPageElement(element)) GSStoryPage.RemoveElement(element);
            }
            this.front_elements = [];
            for (local i = 0; i <= MT_SECTIONS.len(); i++) {
                this.front_elements.append(GSStoryPage.NewElement(this.front_page, GSStoryPage.SPET_TEXT, 0, i == 0 ? "THE TRANSPORT LEDGER" : " "));
            }
        }
        if (!GSStoryPage.IsValidStoryPage(this.archive_page)) {
            this.archive_page = GSStoryPage.New(GSCompany.COMPANY_INVALID, "Ledger archive");
            this.archive_body = GSStoryPage.NewElement(this.archive_page, GSStoryPage.SPET_TEXT, 0, "No editions yet.");
        } else if (!GSStoryPage.IsValidStoryPageElement(this.archive_body)) {
            this.archive_body = GSStoryPage.NewElement(this.archive_page, GSStoryPage.SPET_TEXT, 0, "No editions yet.");
        }
    }

    function RefreshPages()
    {
        this.EnsurePages(-1, -1);
        local latest = this.editions.len() > 0 ? this.editions[this.editions.len() - 1] : null;

        local masthead = "THE TRANSPORT LEDGER\nMarkets, companies, rivals, industry and transport";
        if (latest == null) {
            masthead += "\n\nThe first edition is being typeset.";
        } else {
            masthead += "\n\n" + this.EditionLabel(latest) + "\n\nLEAD: " + latest.lead;
        }
        GSStoryPage.UpdateElement(this.front_elements[0], 0, masthead);

        for (local i = 0; i < MT_SECTIONS.len(); i++) {
            local text = " ";
            if (latest != null) {
                foreach (lines in latest.sections) {
                    if (lines[0] != MT_SECTION_TITLES[MT_SECTIONS[i]]) continue;
                    text = lines[0];
                    for (local j = 1; j < lines.len(); j++) text += "\n- " + lines[j];
                }
            }
            GSStoryPage.UpdateElement(this.front_elements[i + 1], 0, text);
        }

        local archive = "LEDGER ARCHIVE\nThe last " + MT_EDITION_ARCHIVE_LIMIT + " editions, newest first.";
        if (this.editions.len() == 0) archive += "\n\nNo editions yet.";
        for (local i = this.editions.len() - 1; i >= 0; i--) {
            archive += "\n\n" + this.EditionLabel(this.editions[i]) + "\n" + this.editions[i].lead;
        }
        GSStoryPage.UpdateElement(this.archive_body, 0, archive);

        if (this.UsesCalendarTimekeeping()) {
            GSStoryPage.SetDate(this.front_page, GSDate.GetCurrentDate());
            GSStoryPage.SetDate(this.archive_page, GSDate.GetCurrentDate());
        }
    }

    function EditionLabel(edition)
    {
        if (edition.number == 0) return "Earlier reports";
        return "Edition #" + edition.number + ", " + MT_MONTH_NAMES[edition.month - 1] + " " + edition.year;
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

    function DeskFor(name, snapshot)
    {
        foreach (desk in MT_RIVAL_DESKS) {
            if (name.find(desk.prefix) == 0) return desk.desk;
        }
        local best = null, best_count = 0;
        foreach (fleet in MT_FLEET) {
            if (snapshot[fleet.key] > best_count) {
                best = fleet;
                best_count = snapshot[fleet.key];
            }
        }
        if (best == null) return "a company without vehicles";
        switch (best.key) {
            case "rail":  return "a railway company";
            case "road":  return "a road haulier";
            case "water": return "a shipping line";
            case "air":   return "an airline";
        }
        return "a transport company";
    }

    function FleetText(snapshot)
    {
        local parts = [];
        foreach (fleet in MT_FLEET) {
            if (snapshot[fleet.key] > 0) parts.append(snapshot[fleet.key] + " " + fleet.noun);
        }
        if (parts.len() == 0) return "no vehicles";
        local text = parts[0];
        for (local i = 1; i < parts.len(); i++) text += (i == parts.len() - 1 ? " and " : ", ") + parts[i];
        return text;
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
                        this.Record("rivals", MT_SEV_NORMAL, "rival_entry", [name, fleet.sector, has, fleet.noun], GSNews.NR_NONE, 0, null, false);
                    } else if (had > 0 && has - had >= this.MaxValue(3, had / 4)) {
                        this.Record("rivals", MT_SEV_MINOR, "rival_growth", [name, has - had, fleet.noun, has], GSNews.NR_NONE, 0, null, false);
                    }
                }
                local passed = 0;
                foreach (milestone in MT_VALUE_MILESTONES) {
                    if (before.value < milestone && value >= milestone) passed = milestone;
                }
                if (passed > 0) this.Record("companies", MT_SEV_NORMAL, "value_milestone", [name, passed], GSNews.NR_NONE, 0, null, false);
            }

            this.rivals[key] <- { name = name, value = value, rail = now.rail, road = now.road, water = now.water, air = now.air };
            if (now.rail + now.road + now.water + now.air > 0) profiled.append(company_id);
        }

        /* One rotating profile per edition keeps the desk lively but short. */
        if (!silent && profiled.len() > 0) {
            local company_id = profiled[this.edition_number % profiled.len()];
            local snap = this.rivals[company_id.tostring()];
            this.Record("rivals", MT_SEV_MINOR, "rival_profile",
                [snap.name, this.DeskFor(snap.name, snap), this.FleetText(snap), snap.value], GSNews.NR_NONE, 0, "profile", false);
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
            this.Record("transport", MT_SEV_MINOR, "cargo_leader", [this.CompanyName(best), best_amount], GSNews.NR_NONE, 0, null, false);
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
            this.Record("companies", MT_SEV_NORMAL, "company_trouble", [MT_ShortText(this.CompanyName(company_id))], GSNews.NR_NONE, 0, null, false);
        } else if (type == GSEvent.ET_COMPANY_BANKRUPT) {
            local company_id = GSEventCompanyBankrupt.Convert(event).GetCompanyID();
            this.Record("companies", MT_SEV_MAJOR, "company_closed", [MT_ShortText(this.CompanyName(company_id))], GSNews.NR_NONE, 0, null, true);
            this.Forget(company_id);
        } else if (type == GSEvent.ET_COMPANY_MERGER) {
            local merger = GSEventCompanyMerger.Convert(event);
            local acquirer = MT_ShortText(this.CompanyName(merger.GetNewCompanyID()));
            local acquired = MT_ShortText(this.CompanyName(merger.GetOldCompanyID()));
            this.Record("companies", MT_SEV_MAJOR, "merger", [acquirer, acquired], GSNews.NR_NONE, 0, null, true);
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
