/*
 * Nordlys Air - the first Modern Tycoon AI player.
 *
 * Strategy in one breath: find two large towns a good distance apart,
 * put an airport near the busiest part of each, fly passengers between
 * them, add planes where passengers pile up, replace planes when better
 * models arrive, move busy routes to bigger airports, fly mail where it
 * piles up, retire planes that keep losing money, and pay back the loan
 * when there is spare cash. How boldly it does all that depends on its
 * personality (see personality.nut).
 *
 * In-game log messages are in Norwegian on purpose: it is part of the
 * company's personality.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

require("personality.nut");

const DAYS_BETWEEN_REVIEWS = 30;
const DAYS_BEFORE_TOWN_RETRY = 365;
const MIN_TOWN_POPULATION = 300;
const MIN_SITE_ACCEPTANCE = 25;
const MAX_SITE_TRIES = 40;
const MAX_PLANES_SMALL_AIRPORT = 4;
const MAX_REPLACEMENTS_PER_REVIEW = 2;
const UPGRADE_SCORE_PERCENT = 120;    // A new model must be 20% better before we replace a plane.
const MAIL_WAITING_PER_PLANE = 60;
const NO_ROUTE = -1;

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

function NA_PlaneScore(engine)
{
	return AIEngine.GetCapacity(engine) * AIEngine.GetMaxSpeed(engine) * AIEngine.GetReliability(engine) / 100;
}

class NordlysAir extends AIController {
	/* Plane names; each plane also gets a unique Norwegian-style registration (LN-Nxx). */
	PLANE_NAMES = ["Nordlys", "Midnattsol", "Fjordfalk", "Polarstjerne", "Havørn", "Vinterlys",
			"Fjellvind", "Kystpilen", "Snøugle", "Lofoten", "Trollheimen", "Sølvmåke"];
	LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

	routes = null;        // Array of { town_a, town_b, tile_a, tile_b, type, retiring }.
	to_sell = null;       // Table: vehicle id -> tile_a of the route that gets a replacement, or NO_ROUTE.
	failed_towns = null;  // Table: town id -> date after which we may try that town again.
	passenger = null;     // Passenger cargo type on this map.
	mail = null;          // Mail cargo type on this map, or null.
	personality = null;
	traits = null;
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

	this.passenger = this.FindCargo(AICargo.CC_PASSENGERS);
	this.mail = this.FindCargo(AICargo.CC_MAIL);
	if (this.passenger == null) {
		AILog.Error("Fant ingen passasjerer på dette kartet. Nordlys Air blir på bakken.");
		while (true) this.Sleep(1000);
	}

	if (this.loaded_data != null) this.RestoreState(this.loaded_data);
	this.loaded_data = null;
	if (this.personality == null) this.personality = MT_ResolvePersonality(AIController.GetSetting("personality"));
	this.traits = MT_Traits(this.personality);

	AILog.Info("Nordlys Air er klar for avgang. Personlighet: " + this.traits.name +
			". Ruter i drift: " + this.ActiveRouteCount());

	while (true) {
		this.HandleEvents();

		local today = AIDate.GetCurrentDate();
		if (today >= this.next_review) {
			this.ReviewRoutes();
			this.next_review = today + DAYS_BETWEEN_REVIEWS;
		}

		if (today >= this.next_route_try && this.ActiveRouteCount() < this.RouteLimit()) {
			if (!this.TryBuildRoute()) this.next_route_try = today + this.traits.retry_days;
		}

		if (MT_RepayLoan(this.traits)) AILog.Info("Lånet er nedbetalt. Nordlys Air er gjeldfri!");
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

function NordlysAir::FindCargo(cargo_class)
{
	foreach (cargo, dummy in AICargoList()) {
		if (AICargo.HasCargoClass(cargo, cargo_class)) return cargo;
	}
	return null;
}

function NordlysAir::UseLoan() { return AIController.GetSetting("use_loan") != 0; }
function NordlysAir::EnsureCash(amount) { return MT_EnsureCash(amount, this.traits, this.UseLoan()); }
function NordlysAir::SpendableMoney() { return MT_SpendableMoney(this.traits, this.UseLoan()); }

function NordlysAir::RouteLimit()
{
	return NA_Min(AIController.GetSetting("max_routes"), this.traits.route_cap);
}

function NordlysAir::ActiveRouteCount()
{
	local count = 0;
	foreach (route in this.routes) if (!route.retiring) count++;
	return count;
}

function NordlysAir::FindRouteByTile(tile_a)
{
	foreach (route in this.routes) if (route.tile_a == tile_a) return route;
	return null;
}

/* ------------------------------------------------------------ new routes */

function NordlysAir::TryBuildRoute()
{
	local types = this.CandidateAirportTypes(false);
	if (types.len() == 0) return false;

	local pair = this.PickTownPair();
	if (pair == null) return false;

	local town_a = pair[0], town_b = pair[1];
	local site_found_a = false, site_found_b = false;

	foreach (type in types) {
		local engine = this.PickPlane(type, AITown.GetLocation(town_a), AITown.GetLocation(town_b), this.passenger);
		if (engine == null) continue;

		local cost = (2 * AIAirport.GetPrice(type) + 2 * AIEngine.GetPrice(engine)) * 11 / 10;
		if (this.SpendableMoney() < cost) continue;

		local site_a = this.FindAirportSite(town_a, type);
		if (site_a != null) site_found_a = true;
		local site_b = this.FindAirportSite(town_b, type);
		if (site_b != null) site_found_b = true;
		if (site_a == null || site_b == null) continue;

		return this.BuildRoute(town_a, town_b, type, engine, site_a, site_b, cost) != null;
	}

	/* Only blame a town when we could afford to look and still found no room. */
	if (this.SpendableMoney() > 0) {
		if (!site_found_a) this.MarkTownFailed(town_a);
		if (!site_found_b) this.MarkTownFailed(town_b);
	}
	return false;
}

/* Airport types we can build today, best first. Huge airports never fit in towns. */
function NordlysAir::CandidateAirportTypes(big_only)
{
	local result = [];
	foreach (type in [AIAirport.AT_METROPOLITAN, AIAirport.AT_LARGE, AIAirport.AT_COMMUTER, AIAirport.AT_SMALL]) {
		if (big_only && !NA_IsBigAirport(type)) continue;
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

/* Best plane for this airport type and cargo that can reach the other end. */
function NordlysAir::PickPlane(type, tile_a, tile_b, cargo)
{
	if (cargo == null) return null;
	local engines = AIEngineList(AIVehicle.VT_AIR);
	engines.Valuate(AIEngine.IsBuildable);
	engines.KeepValue(1);
	engines.Valuate(NA_CarriesCargo, cargo);
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
		local score = NA_PlaneScore(engine);
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

/* Builds two airports and the first two planes. Returns the new route, or null. */
function NordlysAir::BuildRoute(town_a, town_b, type, engine, site_a, site_b, cost)
{
	if (!this.EnsureCash(cost)) return null;

	if (!AIAirport.BuildAirport(site_a, type, AIStation.STATION_NEW)) {
		AILog.Warning("Flyplassen i " + AITown.GetName(town_a) + " ble ikke bygd: " + AIError.GetLastErrorString());
		this.MarkTownFailed(town_a);
		return null;
	}
	if (!AIAirport.BuildAirport(site_b, type, AIStation.STATION_NEW)) {
		AILog.Warning("Flyplassen i " + AITown.GetName(town_b) + " ble ikke bygd: " + AIError.GetLastErrorString());
		AIAirport.RemoveAirport(site_a);
		this.MarkTownFailed(town_b);
		return null;
	}

	this.NameAirport(site_a, town_a);
	this.NameAirport(site_b, town_b);

	local route = { town_a = town_a, town_b = town_b, tile_a = site_a, tile_b = site_b, type = type, retiring = false };
	this.routes.push(route);

	local dist = AIMap.DistanceManhattan(site_a, site_b);
	AILog.Info("Ny rute: " + AITown.GetName(town_a) + " - " + AITown.GetName(town_b) +
			" (" + dist + " ruter, " + AIEngine.GetName(engine) + ")");

	/* Two planes, one from each end, so both towns get service right away. */
	this.AddPlane(route, engine, false, this.passenger);
	this.AddPlane(route, engine, true, this.passenger);
	return route;
}

function NordlysAir::NameAirport(tile, town)
{
	local station = AIStation.GetStationID(tile);
	local name = AITown.GetName(town) + " lufthavn";
	if (!AIBaseStation.SetName(station, name)) AIBaseStation.SetName(station, name + " " + (AIDate.GetYear(AIDate.GetCurrentDate())));
}

/* --------------------------------------------------------------- planes */

function NordlysAir::AddPlane(route, engine, start_at_b, cargo)
{
	if (engine == null) engine = this.PickPlane(route.type, route.tile_a, route.tile_b, cargo);
	if (engine == null) return false;
	if (!this.EnsureCash(AIEngine.GetPrice(engine))) return false;

	local hangar = AIAirport.GetHangarOfAirport(start_at_b ? route.tile_b : route.tile_a);
	local veh = AIVehicle.BuildVehicle(hangar, engine);
	if (!AIVehicle.IsValidVehicle(veh)) {
		AILog.Warning("Kunne ikke kjøpe fly: " + AIError.GetLastErrorString());
		return false;
	}
	/* Planes often carry some mail next to passengers, so refit whenever the main cargo differs. */
	if (AIEngine.GetCargoType(engine) != cargo) AIVehicle.RefitVehicle(veh, cargo);
	if (AIVehicle.GetCapacity(veh, cargo) == 0 || (cargo == this.mail && AIVehicle.GetCapacity(veh, this.passenger) > 0)) {
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

function NordlysAir::IsMailPlane(veh)
{
	return this.mail != null && AIVehicle.GetCapacity(veh, this.mail) > 0 && AIVehicle.GetCapacity(veh, this.passenger) == 0;
}

/* Send a plane on its last trip; when it is sold, `replace_route` (if any) gets a fresh one. */
function NordlysAir::RetirePlane(veh, replace_route)
{
	if (!AIVehicle.SendVehicleToDepot(veh)) return false;
	this.to_sell[veh] <- (replace_route == null ? NO_ROUTE : replace_route.tile_a);
	return true;
}

/* Sell a plane waiting in a hangar; buy its replacement if one was promised. */
function NordlysAir::SellPlane(veh)
{
	local key = this.to_sell[veh];
	local was_mail = this.IsMailPlane(veh);
	if (!AIVehicle.SellVehicle(veh)) return false;
	delete this.to_sell[veh];
	if (key == NO_ROUTE) return true;

	local route = this.FindRouteByTile(key);
	if (route != null && !route.retiring) {
		this.AddPlane(route, null, false, was_mail ? this.mail : this.passenger);
	}
	return true;
}

/* -------------------------------------------------------- monthly review */

function NordlysAir::ReviewRoutes()
{
	local max_planes = AIController.GetSetting("max_planes_per_route");
	local replacements = 0;
	local upgraded = false;

	/* Iterate a copy: an airport upgrade appends a route while we loop. */
	foreach (route in clone this.routes) {
		if (route.retiring) continue;
		local station_a = AIStation.GetStationID(route.tile_a);
		local station_b = AIStation.GetStationID(route.tile_b);
		if (!AIStation.IsValidStation(station_a) || !AIStation.IsValidStation(station_b)) continue;

		local count = 0, mail_count = 0, capacity = 0;
		local best_engine = this.PickPlane(route.type, route.tile_a, route.tile_b, this.passenger);
		local outdated = [];
		foreach (veh, dummy in AIVehicleList_Station(station_a)) {
			if (veh in this.to_sell) continue;
			if (AIVehicle.GetState(veh) == AIVehicle.VS_CRASHED) continue;
			if (this.IsMailPlane(veh)) {
				mail_count++;
				continue;
			}
			count++;
			capacity = NA_Max(capacity, AIVehicle.GetCapacity(veh, this.passenger));
			if (this.IsOutdated(veh, best_engine)) outdated.push(veh);
		}

		local waiting = AIStation.GetCargoWaiting(station_a, this.passenger) +
				AIStation.GetCargoWaiting(station_b, this.passenger);
		local limit = NA_IsBigAirport(route.type) ? max_planes : NA_Min(max_planes, MAX_PLANES_SMALL_AIRPORT);
		local crowded = capacity > 0 && waiting * 10 > capacity * this.traits.growth_x10;

		if (count == 0 || (count < limit && crowded)) {
			if (this.AddPlane(route, null, count % 2 == 1, this.passenger)) {
				AILog.Info("Flere passasjerer venter mellom " + AITown.GetName(route.town_a) + " og " +
						AITown.GetName(route.town_b) + ". Nytt fly satt inn (" + (count + 1) + " totalt).");
			}
		}

		/* Mail: one or two dedicated planes where letters pile up. */
		if (this.mail != null && mail_count < this.traits.extra_vehicles) {
			local mail_waiting = AIStation.GetCargoWaiting(station_a, this.mail) + AIStation.GetCargoWaiting(station_b, this.mail);
			if (mail_waiting > MAIL_WAITING_PER_PLANE * (mail_count + 1) && this.AddPlane(route, null, mail_count % 2 == 1, this.mail)) {
				AILog.Info("Posten hoper seg opp mellom " + AITown.GetName(route.town_a) + " og " +
						AITown.GetName(route.town_b) + ". Postfly satt inn.");
			}
		}

		/* Fleet renewal: swap old or outdated planes for the best current model. */
		foreach (veh in outdated) {
			if (replacements >= MAX_REPLACEMENTS_PER_REVIEW) break;
			if (best_engine == null || this.SpendableMoney() < AIEngine.GetPrice(best_engine) * this.traits.upgrade_x) break;
			if (this.RetirePlane(veh, route)) {
				replacements++;
				AILog.Info(AIVehicle.GetName(veh) + " byttes ut med en " + AIEngine.GetName(best_engine) + ".");
			}
		}

		/* Busy route on a small airport: move it to big airports, once per review. */
		if (!upgraded && !NA_IsBigAirport(route.type) && count >= limit && crowded) {
			upgraded = this.TryUpgradeAirports(route);
		}
	}

	this.CleanUpRetiredRoutes();
	this.RetireLossMakers();
	this.SellWaitingPlanes();
	this.YearlyReport();
}

/* Old, or much worse than what the factory sells today. */
function NordlysAir::IsOutdated(veh, best_engine)
{
	if (AIVehicle.GetAgeLeft(veh) < 365) return true;
	if (best_engine == null) return false;
	local current = AIVehicle.GetEngineType(veh);
	if (current == best_engine) return false;
	return NA_PlaneScore(best_engine) * 100 >= NA_PlaneScore(current) * UPGRADE_SCORE_PERCENT;
}

/* Build a big-airport route between the same towns, then retire the old one. */
function NordlysAir::TryUpgradeAirports(old_route)
{
	foreach (type in this.CandidateAirportTypes(true)) {
		local engine = this.PickPlane(type, old_route.tile_a, old_route.tile_b, this.passenger);
		if (engine == null) continue;
		local cost = (2 * AIAirport.GetPrice(type) + 2 * AIEngine.GetPrice(engine)) * 11 / 10;
		if (this.SpendableMoney() < cost * this.traits.upgrade_x) continue;

		local site_a = this.FindAirportSite(old_route.town_a, type);
		if (site_a == null) continue;
		local site_b = this.FindAirportSite(old_route.town_b, type);
		if (site_b == null) continue;

		local new_route = this.BuildRoute(old_route.town_a, old_route.town_b, type, engine, site_a, site_b, cost);
		if (new_route == null) return false;

		old_route.retiring = true;
		foreach (veh, dummy in AIVehicleList_Station(AIStation.GetStationID(old_route.tile_a))) {
			if (!(veh in this.to_sell)) this.RetirePlane(veh, new_route);
		}
		AILog.Info("Ruten " + AITown.GetName(old_route.town_a) + " - " + AITown.GetName(old_route.town_b) +
				" flytter til større flyplasser.");
		return true;
	}
	return false;
}

/* Remove airports of retired routes once their last plane is gone. */
function NordlysAir::CleanUpRetiredRoutes()
{
	local me = AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
	for (local i = this.routes.len() - 1; i >= 0; i--) {
		local route = this.routes[i];
		if (!route.retiring) continue;
		local busy = false;
		foreach (tile in [route.tile_a, route.tile_b]) {
			if (!AIAirport.IsAirportTile(tile) || AITile.GetOwner(tile) != me) continue;
			if (AIVehicleList_Station(AIStation.GetStationID(tile)).Count() > 0 || !AIAirport.RemoveAirport(tile)) busy = true;
		}
		if (!busy) this.routes.remove(i);
	}
}

function NordlysAir::RetireLossMakers()
{
	foreach (veh, dummy in AIVehicleList()) {
		if (veh in this.to_sell) continue;
		if (AIVehicle.GetAge(veh) < this.traits.retire_years * 365) continue;
		if (AIVehicle.GetProfitLastYear(veh) >= 0 || AIVehicle.GetProfitThisYear(veh) >= 0) continue;

		/* Never strand a route: keep the last plane, the review will judge it again later. */
		local station = AIStation.GetStationID(AIOrder.GetOrderDestination(veh, 0));
		if (AIVehicleList_Station(station).Count() <= 1) continue;

		if (this.RetirePlane(veh, null)) AILog.Info(AIVehicle.GetName(veh) + " taper penger og pensjoneres.");
	}
}

/* Safety net in case a "waiting in depot" event was missed. */
function NordlysAir::SellWaitingPlanes()
{
	local waiting = [];
	foreach (veh, dummy in this.to_sell) {
		if (!AIVehicle.IsValidVehicle(veh)) {
			waiting.push([veh, false]);
		} else if (AIVehicle.IsStoppedInDepot(veh)) {
			waiting.push([veh, true]);
		}
	}
	foreach (item in waiting) {
		if (item[1]) {
			this.SellPlane(item[0]);
		} else if (item[0] in this.to_sell) {
			delete this.to_sell[item[0]];
		}
	}
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
	local big = 0;
	foreach (veh, dummy in planes) profit += AIVehicle.GetProfitLastYear(veh);
	foreach (route in this.routes) if (!route.retiring && NA_IsBigAirport(route.type)) big++;

	foreach (route in this.routes) {
		if (route.retiring) continue;
		local station_a = AIStation.GetStationID(route.tile_a);
		local station_b = AIStation.GetStationID(route.tile_b);
		local route_planes = AIVehicleList_Station(station_a);
		local route_profit = 0;
		foreach (veh, dummy in route_planes) route_profit += AIVehicle.GetProfitLastYear(veh);
		AILog.Info("  " + AITown.GetName(route.town_a) + " - " + AITown.GetName(route.town_b) + ": " +
				route_planes.Count() + " fly, overskudd " + route_profit + ", venter " +
				(AIStation.GetCargoWaiting(station_a, this.passenger) + AIStation.GetCargoWaiting(station_b, this.passenger)) +
				", vurdering " + AIStation.GetCargoRating(station_a, this.passenger) + "/" + AIStation.GetCargoRating(station_b, this.passenger) + "%");
	}
	AILog.Info("Årsrapport " + (year - 1) + ": " + this.ActiveRouteCount() + " ruter (" + big + " med store flyplasser), " +
			planes.Count() + " fly, flyoverskudd " + profit + ", bank " + AICompany.GetBankBalance(AICompany.COMPANY_SELF) +
			", lån " + AICompany.GetLoanAmount());
}

/* --------------------------------------------------------------- events */

function NordlysAir::HandleEvents()
{
	while (AIEventController.IsEventWaiting()) {
		local event = AIEventController.GetNextEvent();
		local type = event.GetEventType();

		if (type == AIEvent.ET_VEHICLE_WAITING_IN_DEPOT) {
			local veh = AIEventVehicleWaitingInDepot.Convert(event).GetVehicleID();
			if (veh in this.to_sell) this.SellPlane(veh);
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
		saved_routes.push([route.town_a, route.town_b, route.tile_a, route.tile_b, route.type, route.retiring ? 1 : 0]);
	}
	local selling = [];
	foreach (veh, key in this.to_sell) selling.push([veh, key]);

	return {
		routes = saved_routes,
		to_sell_v2 = selling,
		plane_counter = this.plane_counter,
		personality = this.personality == null ? -1 : this.personality
	};
}

function NordlysAir::Load(version, data)
{
	/* The API is not fully usable yet; restore in Start(). Version 1 data is still understood. */
	this.loaded_data = data;
}

function NordlysAir::RestoreState(data)
{
	local me = AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);

	if ("routes" in data) {
		foreach (r in data.routes) {
			if (!AIAirport.IsAirportTile(r[2]) || !AIAirport.IsAirportTile(r[3])) continue;
			if (AITile.GetOwner(r[2]) != me || AITile.GetOwner(r[3]) != me) continue;
			local retiring = r.len() > 5 && r[5] != 0;
			this.routes.push({ town_a = r[0], town_b = r[1], tile_a = r[2], tile_b = r[3], type = r[4], retiring = retiring });
		}
	}
	/* v1 stored a plain list of vehicles to sell; v2 stores [vehicle, route key] pairs. */
	if ("to_sell" in data) {
		foreach (veh in data.to_sell) {
			if (AIVehicle.IsValidVehicle(veh)) this.to_sell[veh] <- NO_ROUTE;
		}
	}
	if ("to_sell_v2" in data) {
		foreach (item in data.to_sell_v2) {
			if (AIVehicle.IsValidVehicle(item[0])) this.to_sell[item[0]] <- item[1];
		}
	}
	if ("plane_counter" in data) this.plane_counter = data.plane_counter;
	if ("personality" in data && data.personality >= 0) this.personality = data.personality;
}
