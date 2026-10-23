/*
 * Nordlys Air - the first Modern Tycoon AI player.
 *
 * Strategy in one breath: find two large towns a good distance apart,
 * put an airport near the busiest part of each, fly passengers between
 * them, add planes where passengers pile up, retire planes that keep
 * losing money, and pay back the loan when there is spare cash.
 *
 * In-game log messages are in Norwegian on purpose: it is part of the
 * company's personality.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

const DAYS_BETWEEN_REVIEWS = 30;
const DAYS_BEFORE_ROUTE_RETRY = 15;
const DAYS_BEFORE_TOWN_RETRY = 365;
const CASH_RESERVE = 25000;
const MIN_TOWN_POPULATION = 300;
const MIN_SITE_ACCEPTANCE = 25;
const MAX_SITE_TRIES = 40;
const MAX_PLANES_SMALL_AIRPORT = 4;
const SAVE_VERSION = 1;

/* Small helpers, kept global so valuators and methods can share them. */
function NA_Min(a, b) { return a < b ? a : b; }
function NA_Max(a, b) { return a > b ? a : b; }
function NA_Clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }

function NA_Tile(x, y)
{
	return AIMap.GetTileIndex(NA_Clamp(x, 1, AIMap.GetMapSizeX() - 2), NA_Clamp(y, 1, AIMap.GetMapSizeY() - 2));
}

/* Big planes crash too often on small airports, so only big airports get them. */
function NA_IsBigAirport(type)
{
	return type == AIAirport.AT_LARGE || type == AIAirport.AT_METROPOLITAN ||
			type == AIAirport.AT_INTERNATIONAL || type == AIAirport.AT_INTERCON;
}

/* Dry run: would this airport build succeed right now? Costs nothing. */
function NA_CanBuildAirport(tile, type)
{
	local mode = AITestMode();
	return AIAirport.BuildAirport(tile, type, AIStation.STATION_NEW);
}

function NA_CarriesCargo(engine, cargo)
{
	return AIEngine.GetCargoType(engine) == cargo || AIEngine.CanRefitCargo(engine, cargo);
}

class NordlysAir extends AIController {
	/* Plane names; each plane also gets a unique Norwegian-style registration (LN-Nxx). */
	PLANE_NAMES = ["Nordlys", "Midnattsol", "Fjordfalk", "Polarstjerne", "Havørn", "Vinterlys",
			"Fjellvind", "Kystpilen", "Snøugle", "Lofoten", "Trollheimen", "Sølvmåke"];
	LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

	routes = null;        // Array of { town_a, town_b, tile_a, tile_b, type }.
	to_sell = null;       // Table: vehicle id -> true, for planes on their last trip to the hangar.
	failed_towns = null;  // Table: town id -> date after which we may try that town again.
	passenger = null;     // Passenger cargo type on this map.
	plane_counter = 0;
	next_review = 0;
	next_route_try = 0;
	last_report_year = 0;
	loaded_data = null;

	constructor()
	{
		this.routes = [];
		this.to_sell = {};
		this.failed_towns = {};
	}
}

function NordlysAir::Start()
{
	this.SetIdentity();
	AICompany.SetAutoRenewStatus(true);

	this.passenger = this.FindPassengerCargo();
	if (this.passenger == null) {
		AILog.Error("Fant ingen passasjerer på dette kartet. Nordlys Air blir på bakken.");
		while (true) this.Sleep(1000);
	}

	if (this.loaded_data != null) this.RestoreState(this.loaded_data);
	this.loaded_data = null;

	AILog.Info("Nordlys Air er klar for avgang. Ruter i drift: " + this.routes.len());

	while (true) {
		this.HandleEvents();

		local today = AIDate.GetCurrentDate();
		if (today >= this.next_review) {
			this.ReviewRoutes();
			this.next_review = today + DAYS_BETWEEN_REVIEWS;
		}

		if (today >= this.next_route_try && this.routes.len() < AIController.GetSetting("max_routes")) {
			if (!this.TryBuildRoute()) this.next_route_try = today + DAYS_BEFORE_ROUTE_RETRY;
		}

		this.RepayLoan();
		this.Sleep(74);
	}
}

/* ---------------------------------------------------------------- identity */

function NordlysAir::SetIdentity()
{
	local current = AICompany.GetName(AICompany.COMPANY_SELF);
	if (current == null || current.find("Nordlys Air") != 0) {
		if (!AICompany.SetName("Nordlys Air")) {
			local i = 2;
			while (i < 20 && !AICompany.SetName("Nordlys Air " + i)) i++;
		}
		AICompany.SetPresidentName("Solveig Fjellheim");
	}
	if (!AICompany.SetPrimaryLiveryColour(AICompany.LS_DEFAULT, AICompany.COLOUR_DARK_GREEN)) {
		AICompany.SetPrimaryLiveryColour(AICompany.LS_DEFAULT, AICompany.COLOUR_GREEN);
	}
}

function NordlysAir::FindPassengerCargo()
{
	foreach (cargo, dummy in AICargoList()) {
		if (AICargo.HasCargoClass(cargo, AICargo.CC_PASSENGERS)) return cargo;
	}
	return null;
}

/* ------------------------------------------------------------------- money */

/* What we could spend now without dipping into the safety reserve. */
function NordlysAir::SpendableMoney()
{
	local cash = AICompany.GetBankBalance(AICompany.COMPANY_SELF);
	if (AIController.GetSetting("use_loan")) cash += AICompany.GetMaxLoanAmount() - AICompany.GetLoanAmount();
	return cash - CASH_RESERVE;
}

/* Make sure `amount` is in the bank, borrowing if allowed. */
function NordlysAir::EnsureCash(amount)
{
	local cash = AICompany.GetBankBalance(AICompany.COMPANY_SELF);
	if (cash >= amount + CASH_RESERVE) return true;
	if (!AIController.GetSetting("use_loan")) return cash >= amount;

	local wanted = AICompany.GetLoanAmount() + amount + CASH_RESERVE - cash;
	if (wanted >= AICompany.GetMaxLoanAmount()) {
		AICompany.SetLoanAmount(AICompany.GetMaxLoanAmount());
	} else {
		AICompany.SetMinimumLoanAmount(wanted);
	}
	return AICompany.GetBankBalance(AICompany.COMPANY_SELF) >= amount;
}

/* Pay back the loan in steps when there is clearly more cash than we need. */
function NordlysAir::RepayLoan()
{
	local loan = AICompany.GetLoanAmount();
	if (loan == 0) return;

	local interval = AICompany.GetLoanInterval();
	local spare = AICompany.GetBankBalance(AICompany.COMPANY_SELF) - CASH_RESERVE * 3;
	if (spare < interval) return;

	local repay = NA_Min((spare / interval) * interval, loan);
	if (AICompany.SetLoanAmount(loan - repay) && loan - repay == 0) {
		AILog.Info("Lånet er nedbetalt. Nordlys Air er gjeldfri!");
	}
}

/* ------------------------------------------------------------ new routes */

function NordlysAir::TryBuildRoute()
{
	local types = this.CandidateAirportTypes();
	if (types.len() == 0) return false;

	local pair = this.PickTownPair();
	if (pair == null) return false;

	local town_a = pair[0], town_b = pair[1];
	local site_found_a = false, site_found_b = false;

	foreach (type in types) {
		local engine = this.PickPlane(type, AITown.GetLocation(town_a), AITown.GetLocation(town_b));
		if (engine == null) continue;

		local cost = (2 * AIAirport.GetPrice(type) + 2 * AIEngine.GetPrice(engine)) * 11 / 10;
		if (this.SpendableMoney() < cost) continue;

		local site_a = this.FindAirportSite(town_a, type);
		if (site_a != null) site_found_a = true;
		local site_b = this.FindAirportSite(town_b, type);
		if (site_b != null) site_found_b = true;
		if (site_a == null || site_b == null) continue;

		return this.BuildRoute(town_a, town_b, type, engine, site_a, site_b, cost);
	}

	/* Only blame a town when we could afford to look and still found no room. */
	if (this.SpendableMoney() > 0) {
		if (!site_found_a) this.MarkTownFailed(town_a);
		if (!site_found_b) this.MarkTownFailed(town_b);
	}
	return false;
}

/* Airport types we can build today, best first. Huge airports never fit in towns. */
function NordlysAir::CandidateAirportTypes()
{
	local result = [];
	foreach (type in [AIAirport.AT_METROPOLITAN, AIAirport.AT_LARGE, AIAirport.AT_COMMUTER, AIAirport.AT_SMALL]) {
		if (AIAirport.IsValidAirportType(type)) result.push(type);
	}
	return result;
}

function NordlysAir::MarkTownFailed(town)
{
	this.failed_towns[town] <- AIDate.GetCurrentDate() + DAYS_BEFORE_TOWN_RETRY;
	AILog.Info("Fant ikke plass til flyplass i " + AITown.GetName(town) + ". Prøver igjen om et år.");
}

/* The two biggest free towns that are far enough apart to make flying worth it. */
function NordlysAir::PickTownPair()
{
	local today = AIDate.GetCurrentDate();
	local towns = AITownList();
	towns.Valuate(AITown.GetPopulation);
	towns.KeepAboveValue(MIN_TOWN_POPULATION - 1);
	foreach (route in this.routes) {
		towns.RemoveItem(route.town_a);
		towns.RemoveItem(route.town_b);
	}
	foreach (town, retry_date in this.failed_towns) {
		if (retry_date > today) towns.RemoveItem(town);
	}
	towns.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
	towns.KeepTop(24);
	if (towns.Count() < 2) return null;

	/* Copy to an array: nested foreach over one AIList is not safe. */
	local candidates = [];
	foreach (town, population in towns) candidates.push([town, population]);

	local map_size = NA_Max(AIMap.GetMapSizeX(), AIMap.GetMapSizeY());
	local min_dist = NA_Max(40, map_size / 8);
	local max_dist = NA_Min(450, NA_Max(min_dist + 60, map_size));

	local best = null, best_score = -1;
	for (local i = 0; i < candidates.len(); i++) {
		for (local j = i + 1; j < candidates.len(); j++) {
			local a = candidates[i], b = candidates[j];
			local dist = AIMap.DistanceManhattan(AITown.GetLocation(a[0]), AITown.GetLocation(b[0]));
			if (dist < min_dist || dist > max_dist) continue;
			/* Passenger income grows with distance; the smaller town limits the traffic. */
			local score = NA_Min(a[1], b[1]) * NA_Min(dist, 250);
			if (score > best_score) {
				best_score = score;
				best = [a[0], b[0]];
			}
		}
	}
	return best;
}

/* Best passenger plane for this airport type that can reach the other end. */
function NordlysAir::PickPlane(type, tile_a, tile_b)
{
	local engines = AIEngineList(AIVehicle.VT_AIR);
	engines.Valuate(AIEngine.IsBuildable);
	engines.KeepValue(1);
	engines.Valuate(NA_CarriesCargo, this.passenger);
	engines.KeepValue(1);
	if (!NA_IsBigAirport(type)) {
		engines.Valuate(AIEngine.GetPlaneType);
		engines.RemoveValue(AIAirport.PT_BIG_PLANE);
	}

	local order_dist = AIOrder.GetOrderDistance(AIVehicle.VT_AIR, tile_a, tile_b);
	local best = null, best_score = -1;
	foreach (engine, dummy in engines) {
		local range = AIEngine.GetMaximumOrderDistance(engine);
		if (range != 0 && range < order_dist) continue;
		local score = AIEngine.GetCapacity(engine) * AIEngine.GetMaxSpeed(engine) * AIEngine.GetReliability(engine) / 100;
		if (score > best_score) {
			best_score = score;
			best = engine;
		}
	}
	return best;
}

/* A free, flat spot with many houses in reach, close to the town centre. */
function NordlysAir::FindAirportSite(town, type)
{
	local width = AIAirport.GetAirportWidth(type);
	local height = AIAirport.GetAirportHeight(type);
	local radius = AIAirport.GetAirportCoverageRadius(type);
	local centre = AITown.GetLocation(town);
	local span = 10 + NA_Min(AITown.GetPopulation(town) / 300, 15);
	local cx = AIMap.GetTileX(centre), cy = AIMap.GetTileY(centre);

	local tiles = AITileList();
	tiles.AddRectangle(NA_Tile(cx - span, cy - span), NA_Tile(cx + span, cy + span));
	tiles.Valuate(AITile.IsBuildableRectangle, width, height);
	tiles.KeepValue(1);
	if (tiles.IsEmpty()) return null;

	tiles.Valuate(AITile.GetCargoAcceptance, this.passenger, width, height, radius);
	tiles.KeepAboveValue(MIN_SITE_ACCEPTANCE - 1);
	tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);

	local tries = 0;
	foreach (tile, acceptance in tiles) {
		if (NA_CanBuildAirport(tile, type)) return tile;
		if (++tries >= MAX_SITE_TRIES) break;
	}
	return null;
}

function NordlysAir::BuildRoute(town_a, town_b, type, engine, site_a, site_b, cost)
{
	if (!this.EnsureCash(cost)) return false;

	if (!AIAirport.BuildAirport(site_a, type, AIStation.STATION_NEW)) {
		AILog.Warning("Flyplassen i " + AITown.GetName(town_a) + " ble ikke bygd: " + AIError.GetLastErrorString());
		this.MarkTownFailed(town_a);
		return false;
	}
	if (!AIAirport.BuildAirport(site_b, type, AIStation.STATION_NEW)) {
		AILog.Warning("Flyplassen i " + AITown.GetName(town_b) + " ble ikke bygd: " + AIError.GetLastErrorString());
		AIAirport.RemoveAirport(site_a);
		this.MarkTownFailed(town_b);
		return false;
	}

	this.NameAirport(site_a, town_a);
	this.NameAirport(site_b, town_b);

	local route = { town_a = town_a, town_b = town_b, tile_a = site_a, tile_b = site_b, type = type };
	this.routes.push(route);

	local dist = AIMap.DistanceManhattan(site_a, site_b);
	AILog.Info("Ny rute: " + AITown.GetName(town_a) + " - " + AITown.GetName(town_b) +
			" (" + dist + " ruter, " + AIEngine.GetName(engine) + ")");

	/* Two planes, one from each end, so both towns get service right away. */
	this.AddPlane(route, engine, false);
	this.AddPlane(route, engine, true);
	return true;
}

function NordlysAir::NameAirport(tile, town)
{
	AIBaseStation.SetName(AIStation.GetStationID(tile), AITown.GetName(town) + " lufthavn");
}

/* --------------------------------------------------------------- planes */

function NordlysAir::AddPlane(route, engine, start_at_b)
{
	if (engine == null) engine = this.PickPlane(route.type, route.tile_a, route.tile_b);
	if (engine == null) return false;
	if (!this.EnsureCash(AIEngine.GetPrice(engine))) return false;

	local hangar = AIAirport.GetHangarOfAirport(start_at_b ? route.tile_b : route.tile_a);
	local veh = AIVehicle.BuildVehicle(hangar, engine);
	if (!AIVehicle.IsValidVehicle(veh)) {
		AILog.Warning("Kunne ikke kjøpe fly: " + AIError.GetLastErrorString());
		return false;
	}
	if (AIVehicle.GetCapacity(veh, this.passenger) == 0 && !AIVehicle.RefitVehicle(veh, this.passenger)) {
		AIVehicle.SellVehicle(veh);
		return false;
	}

	AIOrder.AppendOrder(veh, route.tile_a, AIOrder.OF_NONE);
	AIOrder.AppendOrder(veh, route.tile_b, AIOrder.OF_NONE);
	/* A plane in hangar B first loads at B, then flies to A. */
	if (start_at_b) AIOrder.SkipToOrder(veh, 1);

	this.NamePlane(veh);
	AIVehicle.StartStopVehicle(veh);
	return true;
}

/* E.g. "Midnattsol LN-NAB": a name plus a unique Norwegian-style registration. */
function NordlysAir::NamePlane(veh)
{
	for (local attempt = 0; attempt < 5; attempt++) {
		local n = this.plane_counter++;
		local first = (n / 26) % 26, second = n % 26;
		local registration = "LN-N" + LETTERS.slice(first, first + 1) + LETTERS.slice(second, second + 1);
		local name = PLANE_NAMES[n % PLANE_NAMES.len()] + " " + registration;
		if (AIVehicle.SetName(veh, name)) return;
	}
}

/* Monthly check: add planes where passengers pile up, retire loss makers. */
function NordlysAir::ReviewRoutes()
{
	local max_planes = AIController.GetSetting("max_planes_per_route");

	foreach (route in this.routes) {
		local station_a = AIStation.GetStationID(route.tile_a);
		local station_b = AIStation.GetStationID(route.tile_b);
		if (!AIStation.IsValidStation(station_a) || !AIStation.IsValidStation(station_b)) continue;

		local count = 0, capacity = 0;
		foreach (veh, dummy in AIVehicleList_Station(station_a)) {
			if (veh in this.to_sell) continue;
			if (AIVehicle.GetState(veh) == AIVehicle.VS_CRASHED) continue;
			count++;
			capacity = NA_Max(capacity, AIVehicle.GetCapacity(veh, this.passenger));
		}

		local waiting = AIStation.GetCargoWaiting(station_a, this.passenger) +
				AIStation.GetCargoWaiting(station_b, this.passenger);
		local limit = NA_IsBigAirport(route.type) ? max_planes : NA_Min(max_planes, MAX_PLANES_SMALL_AIRPORT);

		local needs_plane = count == 0 || (count < limit && capacity > 0 && waiting > capacity * 2);
		if (needs_plane && this.AddPlane(route, null, count % 2 == 1)) {
			AILog.Info("Flere passasjerer venter mellom " + AITown.GetName(route.town_a) + " og " +
					AITown.GetName(route.town_b) + ". Nytt fly satt inn (" + (count + 1) + " totalt).");
		}
	}

	this.RetireLossMakers();
	this.SellWaitingPlanes();
	this.YearlyReport();
}

/* Once a year, tell the player how the airline is doing. */
function NordlysAir::YearlyReport()
{
	local year = AIDate.GetYear(AIDate.GetCurrentDate());
	if (year == this.last_report_year) return;
	if (this.last_report_year == 0) {
		this.last_report_year = year;
		return;
	}
	this.last_report_year = year;

	local planes = AIVehicleList();
	local profit = 0;
	foreach (veh, dummy in planes) profit += AIVehicle.GetProfitLastYear(veh);

	AILog.Info("Årsrapport " + (year - 1) + ": " + this.routes.len() + " ruter, " + planes.Count() +
			" fly, flyoverskudd " + profit + ", bank " + AICompany.GetBankBalance(AICompany.COMPANY_SELF) +
			", lån " + AICompany.GetLoanAmount());
}

function NordlysAir::RetireLossMakers()
{
	foreach (veh, dummy in AIVehicleList()) {
		if (veh in this.to_sell) continue;
		if (AIVehicle.GetAge(veh) < 2 * 365) continue;
		if (AIVehicle.GetProfitLastYear(veh) >= 0 || AIVehicle.GetProfitThisYear(veh) >= 0) continue;

		/* Never strand a route: keep the last plane, the review will judge it again later. */
		local station = AIStation.GetStationID(AIOrder.GetOrderDestination(veh, 0));
		if (AIVehicleList_Station(station).Count() <= 1) continue;

		if (AIVehicle.SendVehicleToDepot(veh)) {
			this.to_sell[veh] <- true;
			AILog.Info(AIVehicle.GetName(veh) + " taper penger og pensjoneres.");
		}
	}
}

/* Safety net in case a "waiting in depot" event was missed. */
function NordlysAir::SellWaitingPlanes()
{
	local done = [];
	foreach (veh, dummy in this.to_sell) {
		if (!AIVehicle.IsValidVehicle(veh)) {
			done.push(veh);
		} else if (AIVehicle.IsStoppedInDepot(veh) && AIVehicle.SellVehicle(veh)) {
			done.push(veh);
		}
	}
	foreach (veh in done) delete this.to_sell[veh];
}

/* --------------------------------------------------------------- events */

function NordlysAir::HandleEvents()
{
	while (AIEventController.IsEventWaiting()) {
		local event = AIEventController.GetNextEvent();
		local type = event.GetEventType();

		if (type == AIEvent.ET_VEHICLE_WAITING_IN_DEPOT) {
			local veh = AIEventVehicleWaitingInDepot.Convert(event).GetVehicleID();
			if ((veh in this.to_sell) && AIVehicle.SellVehicle(veh)) delete this.to_sell[veh];
		} else if (type == AIEvent.ET_VEHICLE_CRASHED) {
			local veh = AIEventVehicleCrashed.Convert(event).GetVehicleID();
			if (veh in this.to_sell) delete this.to_sell[veh];
			AILog.Warning("Et Nordlys-fly har styrtet. Et nytt fly settes inn ved neste gjennomgang.");
		} else if (type == AIEvent.ET_COMPANY_IN_TROUBLE) {
			local company = AIEventCompanyInTrouble.Convert(event).GetCompanyID();
			if (AICompany.IsMine(company)) AILog.Warning("Nordlys Air sliter økonomisk. Ingen nye ruter før kassa er bedre.");
		}
	}
}

/* ------------------------------------------------------------ save/load */

function NordlysAir::Save()
{
	local saved_routes = [];
	foreach (route in this.routes) {
		saved_routes.push([route.town_a, route.town_b, route.tile_a, route.tile_b, route.type]);
	}
	local selling = [];
	foreach (veh, dummy in this.to_sell) selling.push(veh);

	return { routes = saved_routes, to_sell = selling, plane_counter = this.plane_counter };
}

function NordlysAir::Load(version, data)
{
	/* The API is not fully usable yet; restore in Start(). */
	this.loaded_data = data;
}

function NordlysAir::RestoreState(data)
{
	local me = AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);

	if ("routes" in data) {
		foreach (r in data.routes) {
			if (!AIAirport.IsAirportTile(r[2]) || !AIAirport.IsAirportTile(r[3])) continue;
			if (AITile.GetOwner(r[2]) != me || AITile.GetOwner(r[3]) != me) continue;
			this.routes.push({ town_a = r[0], town_b = r[1], tile_a = r[2], tile_b = r[3], type = r[4] });
		}
	}
	if ("to_sell" in data) {
		foreach (veh in data.to_sell) {
			if (AIVehicle.IsValidVehicle(veh)) this.to_sell[veh] <- true;
		}
	}
	if ("plane_counter" in data) this.plane_counter = data.plane_counter;
}
