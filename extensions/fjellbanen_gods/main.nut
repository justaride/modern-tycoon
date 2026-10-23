/*
 * Fjellbanen Gods - a Modern Tycoon rail freight AI.
 *
 * Strategy: find a busy, poorly served freight industry and a factory or
 * plant that accepts its cargo 40-120 tiles away, place a terminus station
 * at each end, find a route with its own A* pathfinder (pathfinder.nut),
 * lay the track, add a depot and run a full-load freight train. Lines whose
 * industry closes, or that keep losing money, are torn down again.
 *
 * Version 1 runs one train per line (no signals yet).
 * Log messages are in Norwegian as part of the company's personality.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

require("personality.nut");
require("pathfinder.nut");

const DAYS_BETWEEN_REVIEWS = 30;
const DAYS_BEFORE_RETRY = 365;
const MIN_DISTANCE = 40;
const MAX_DISTANCE = 120;
const BEST_DISTANCE = 80;
const MIN_PRODUCTION = 20;
const MAX_TRANSPORTED_PERCENT = 40;
const MAX_STATION_TRIES = 40;
const MAX_BUILD_TRIES = 3;
const DEPOT_SEARCH_TILES = 12;
const NO_TILE = -1;

function FG_Min(a, b) { return a < b ? a : b; }
function FG_Max(a, b) { return a > b ? a : b; }

function FG_CarriesCargo(engine, cargo)
{
	return AIEngine.GetCargoType(engine) == cargo || AIEngine.CanRefitCargo(engine, cargo);
}

function FG_IsFreight(cargo)
{
	return !AICargo.HasCargoClass(cargo, AICargo.CC_PASSENGERS) && !AICargo.HasCargoClass(cargo, AICargo.CC_MAIL);
}

/* Dry run of a rail station. Costs nothing. */
function FG_CanBuildStation(tile, track, length)
{
	local mode = AITestMode();
	return AIRail.BuildRailStation(tile, track, 1, length, AIStation.STATION_NEW);
}

/* What stations and track would cost, measured with a dry run. */
function FG_TestCost(spot_a, spot_b, full)
{
	local costs = AIAccounting();
	local mode = AITestMode();
	AIRail.BuildRailStation(spot_a.top, spot_a.track, 1, spot_a.length, AIStation.STATION_NEW);
	AIRail.BuildRailStation(spot_b.top, spot_b.track, 1, spot_b.length, AIStation.STATION_NEW);
	for (local i = 1; i < full.len() - 1; i++) AIRail.BuildRail(full[i - 1], full[i], full[i + 1]);
	return costs.GetCosts();
}

class FjellbanenGods extends AIController {
	TRAIN_NAMES = ["Dovregubben", "Rauma", "Hardangervidda", "Ofoten", "Femunden", "Jotunheimen",
			"Saltfjellet", "Rondane", "Finse", "Bergsfjord", "Myrdal", "Bjørnfjell"];

	routes = null;        // Array of route tables, see BuildLine().
	to_sell = null;       // Table: vehicle id -> true, trains on their last trip to the depot.
	failed = null;        // Table: industry id or pair key -> date after which we may try again.
	pf = null;            // Shared pathfinder (only its offsets are reused between searches).
	personality = null;
	traits = null;
	train_counter = 0;
	next_review = 0;
	next_route_try = 0;
	last_report_year = 0;
	loaded_data = null;

	constructor()
	{
		this.routes = [];
		this.to_sell = {};
		this.failed = {};
	}
}

function FjellbanenGods::Start()
{
	this.SetIdentity();
	AICompany.SetAutoRenewStatus(true);
	this.pf = MT_RailPathfinder();

	if (this.loaded_data != null) this.RestoreState(this.loaded_data);
	this.loaded_data = null;
	if (this.personality == null) this.personality = MT_ResolvePersonality(AIController.GetSetting("personality"));
	this.traits = MT_Traits(this.personality);

	AILog.Info("Fjellbanen Gods er klar. Personlighet: " + this.traits.name + ". Jernbaner i drift: " + this.LiveRouteCount());

	while (true) {
		this.HandleEvents();

		local today = AIDate.GetCurrentDate();
		if (today >= this.next_review) {
			this.Review();
			this.next_review = today + DAYS_BETWEEN_REVIEWS;
		}

		if (today >= this.next_route_try && this.LiveRouteCount() < this.RouteLimit()) {
			if (!this.TryBuildLine()) this.next_route_try = AIDate.GetCurrentDate() + this.traits.retry_days;
		}

		if (MT_RepayLoan(this.traits)) AILog.Info("Lånet er nedbetalt. Fjellbanen Gods er gjeldfri!");
		this.Sleep(74);
	}
}

/* ---------------------------------------------------------------- basics */

function FjellbanenGods::SetIdentity()
{
	local current = AICompany.GetName(AICompany.COMPANY_SELF);
	if (current == null || current.find("Fjellbanen Gods") != 0) {
		if (!AICompany.SetName("Fjellbanen Gods")) {
			local i = 2;
			while (i < 20 && !AICompany.SetName("Fjellbanen Gods " + i)) i++;
		}
		AICompany.SetPresidentName("Ivar Skinnes");
	}
	if (!AICompany.SetPrimaryLiveryColour(AICompany.LS_DEFAULT, AICompany.COLOUR_RED)) {
		AICompany.SetPrimaryLiveryColour(AICompany.LS_DEFAULT, AICompany.COLOUR_BROWN);
	}
}

function FjellbanenGods::UseLoan() { return AIController.GetSetting("use_loan") != 0; }
function FjellbanenGods::EnsureCash(amount) { return MT_EnsureCash(amount, this.traits, this.UseLoan()); }
function FjellbanenGods::SpendableMoney() { return MT_SpendableMoney(this.traits, this.UseLoan()); }
function FjellbanenGods::RouteLimit() { return FG_Min(AIController.GetSetting("max_routes"), this.traits.route_cap); }

function FjellbanenGods::LiveRouteCount()
{
	local count = 0;
	foreach (route in this.routes) if (!route.dead) count++;
	return count;
}

function FjellbanenGods::PairKey(source, dest) { return 1000000 + source * 65536 + dest; }

function FjellbanenGods::IsBlocked(key)
{
	return (key in this.failed) && this.failed[key] > AIDate.GetCurrentDate();
}

function FjellbanenGods::Block(key)
{
	this.failed[key] <- AIDate.GetCurrentDate() + DAYS_BEFORE_RETRY;
}

function FjellbanenGods::IndustryName(industry)
{
	return AIIndustry.IsValidIndustry(industry) ? AIIndustry.GetName(industry) : ("industri " + industry);
}

/* ---------------------------------------------------- choosing a new line */

/* The richest unserved freight source with a customer at a good distance. */
function FjellbanenGods::PickIndustryPair()
{
	local used = {};
	foreach (route in this.routes) used[route.source] <- true;

	local sources = AIIndustryList();
	sources.Valuate(AIIndustry.IsBuiltOnWater);
	sources.KeepValue(0);

	local best = null, best_score = -1;
	foreach (source, dummy in sources) {
		if ((source in used) || this.IsBlocked(source)) continue;
		local source_tile = AIIndustry.GetLocation(source);
		foreach (cargo, dummy2 in AICargoList_IndustryProducing(source)) {
			if (!FG_IsFreight(cargo)) continue;
			local production = AIIndustry.GetLastMonthProduction(source, cargo);
			if (production < MIN_PRODUCTION) continue;
			if (AIIndustry.GetLastMonthTransportedPercentage(source, cargo) > MAX_TRANSPORTED_PERCENT) continue;

			local dests = AIIndustryList_CargoAccepting(cargo);
			dests.Valuate(AIIndustry.GetDistanceManhattanToTile, source_tile);
			dests.KeepBetweenValue(MIN_DISTANCE - 1, MAX_DISTANCE + 1);
			foreach (dest, dist in dests) {
				if (dest == source || AIIndustry.IsBuiltOnWater(dest)) continue;
				if (this.IsBlocked(this.PairKey(source, dest))) continue;
				/* Income grows with distance, but long lines cost more and take longer to build. */
				local score = production * (dist <= BEST_DISTANCE ? dist : 2 * BEST_DISTANCE - dist);
				if (score > best_score) {
					best_score = score;
					best = { source = source, dest = dest, cargo = cargo, dist = dist, production = production };
				}
			}
		}
	}
	return best;
}

/* Most powerful affordable locomotive that runs, with power, on this rail type. */
function FjellbanenGods::PickLoco(railtype, budget)
{
	local engines = AIEngineList(AIVehicle.VT_RAIL);
	engines.Valuate(AIEngine.IsBuildable);
	engines.KeepValue(1);
	engines.Valuate(AIEngine.IsWagon);
	engines.KeepValue(0);
	engines.Valuate(AIEngine.CanRunOnRail, railtype);
	engines.KeepValue(1);
	engines.Valuate(AIEngine.HasPowerOnRail, railtype);
	engines.KeepValue(1);
	engines.Valuate(AIEngine.GetCapacity);
	engines.KeepBelowValue(1);   // Plain locomotives only, no multiple units.

	local best = null, best_score = -1;
	foreach (engine, dummy in engines) {
		if (budget != null && AIEngine.GetPrice(engine) > budget) continue;
		local score = AIEngine.GetMaxSpeed(engine) * AIEngine.GetPower(engine) / 100 * AIEngine.GetReliability(engine) / 100;
		if (score > best_score) {
			best_score = score;
			best = engine;
		}
	}
	return best;
}

function FjellbanenGods::PickWagon(railtype, cargo)
{
	local engines = AIEngineList(AIVehicle.VT_RAIL);
	engines.Valuate(AIEngine.IsBuildable);
	engines.KeepValue(1);
	engines.Valuate(AIEngine.IsWagon);
	engines.KeepValue(1);
	engines.Valuate(AIEngine.CanRunOnRail, railtype);
	engines.KeepValue(1);
	engines.Valuate(FG_CarriesCargo, cargo);
	engines.KeepValue(1);

	local best = null, best_score = -1;
	foreach (engine, dummy in engines) {
		local speed = AIEngine.GetMaxSpeed(engine);
		local score = AIEngine.GetCapacity(engine) * 1000 + (speed <= 0 ? 999 : FG_Min(speed, 999));
		if (score > best_score) {
			best_score = score;
			best = engine;
		}
	}
	return best;
}

/* Rail type, locomotive and wagon that together make the best train for this cargo. */
function FjellbanenGods::ChooseKit(cargo, budget)
{
	local best = null;
	foreach (railtype, dummy in AIRailTypeList()) {
		if (!AIRail.IsRailTypeAvailable(railtype)) continue;
		local loco = this.PickLoco(railtype, budget);
		local wagon = this.PickWagon(railtype, cargo);
		if (loco == null || wagon == null) continue;
		local score = AIEngine.GetMaxSpeed(loco) * AIEngine.GetPower(loco);
		if (best == null || score > best.score) best = { railtype = railtype, loco = loco, wagon = wagon, score = score };
	}
	return best;
}

/*
 * Describe a terminus of `length` tiles whose north tile is `top`.
 * The open end is the one that faces `toward`. Returns null if it does not fit the map.
 */
function FjellbanenGods::DescribeStation(top, track, length, toward)
{
	local along = track == AIRail.RAILTRACK_NE_SW ? 0 : 2;   // +x or +y
	local far = top + this.pf.Offset(along) * (length - 1);
	if (along == 0 && AIMap.GetTileX(far) - AIMap.GetTileX(top) != length - 1) return null;
	if (along == 2 && AIMap.GetTileY(far) - AIMap.GetTileY(top) != length - 1) return null;

	local front_top = top + this.pf.Offset(along ^ 1);
	local front_far = far + this.pf.Offset(along);
	local spot = { top = top, far = far, track = track, length = length, end = far, front = front_far, out_dir = along };
	if (AIMap.DistanceManhattan(front_top, toward) < AIMap.DistanceManhattan(front_far, toward)) {
		spot.end = top;
		spot.front = front_top;
		spot.out_dir = along ^ 1;
	}
	if (!this.pf.IsInsideMap(spot.front) || this.pf.EnterCost(spot.front, spot.out_dir) < 0) return null;
	spot.w <- along == 0 ? length : 1;
	spot.h <- along == 0 ? 1 : length;
	return spot;
}

/* A terminus that serves the industry, with room for the line to leave toward `toward`. */
function FjellbanenGods::FindStationSpot(industry, producing, cargo, toward, length)
{
	local radius = AIStation.GetCoverageRadius(AIStation.STATION_TRAIN);
	local tiles = producing ? AITileList_IndustryProducing(industry, radius) : AITileList_IndustryAccepting(industry, radius);
	tiles.Valuate(AIMap.DistanceManhattan, toward);
	tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

	local tries = 0;
	foreach (tile, dummy in tiles) {
		foreach (track in [AIRail.RAILTRACK_NE_SW, AIRail.RAILTRACK_NW_SE]) {
			local spot = this.DescribeStation(tile, track, length, toward);
			if (spot == null) continue;
			if (!producing && AITile.GetCargoAcceptance(tile, cargo, spot.w, spot.h, radius) < 8) continue;
			if (FG_CanBuildStation(tile, track, length)) return spot;
		}
		if (++tries >= MAX_STATION_TRIES) break;
	}
	return null;
}

function FjellbanenGods::BlockStationTiles(spot)
{
	local along = spot.track == AIRail.RAILTRACK_NE_SW ? 0 : 2;
	for (local i = 0; i < spot.length; i++) this.pf.Block(spot.top + this.pf.Offset(along) * i);
}

/* -------------------------------------------------------- building a line */

function FjellbanenGods::TryBuildLine()
{
	local pick = this.PickIndustryPair();
	if (pick == null) {
		AILog.Info("Ingen ledig industri med kunde i passe avstand akkurat nå.");
		return false;
	}
	local pair_key = this.PairKey(pick.source, pick.dest);

	local kit = this.ChooseKit(pick.cargo, FG_Max(0, this.SpendableMoney() / 3));
	if (kit == null) {
		AILog.Info("Har ikke råd til lokomotiv og vogner for " + AICargo.GetCargoLabel(pick.cargo) + " ennå.");
		return false;
	}
	AIRail.SetCurrentRailType(kit.railtype);

	this.pf = MT_RailPathfinder();
	local length = this.traits.station_length;
	local source_tile = AIIndustry.GetLocation(pick.source), dest_tile = AIIndustry.GetLocation(pick.dest);

	local spot_a = this.FindStationSpot(pick.source, true, pick.cargo, dest_tile, length);
	if (spot_a == null) {
		AILog.Info("Ingen plass til stasjon ved " + this.IndustryName(pick.source) + ". Prøver igjen om et år.");
		this.Block(pick.source);
		return false;
	}
	local spot_b = this.FindStationSpot(pick.dest, false, pick.cargo, source_tile, length);
	if (spot_b == null) {
		AILog.Info("Ingen plass til stasjon ved " + this.IndustryName(pick.dest) + ".");
		this.Block(pair_key);
		return false;
	}
	this.BlockStationTiles(spot_a);
	this.BlockStationTiles(spot_b);

	local stations_built = false;
	for (local attempt = 0; attempt < MAX_BUILD_TRIES; attempt++) {
		local path = this.pf.FindPath(spot_a.front, spot_a.out_dir, spot_b.end, spot_b.out_dir ^ 1);
		if (path == null) {
			AILog.Info("Fant ingen trasé fra " + this.IndustryName(pick.source) + " til " + this.IndustryName(pick.dest) +
					" (" + this.pf.expansions + " ruter undersøkt).");
			break;
		}
		local full = [spot_a.end];
		full.extend(path);
		full.push(spot_b.end);

		local cost = FG_TestCost(spot_a, spot_b, full) + AIRail.GetBuildCost(kit.railtype, AIRail.BT_DEPOT) +
				AIEngine.GetPrice(kit.loco) + AIEngine.GetPrice(kit.wagon) * length * 2;
		if (!stations_built && this.SpendableMoney() < cost) {
			AILog.Info("Linjen " + this.IndustryName(pick.source) + " - " + this.IndustryName(pick.dest) +
					" koster " + cost + ". Sparer litt først.");
			return false;
		}
		if (!this.EnsureCash(cost)) return false;

		if (!stations_built) {
			if (!this.BuildStations(spot_a, spot_b)) {
				this.Block(pair_key);
				return false;
			}
			stations_built = true;
		}

		local failed_at = this.BuildTrack(full);
		if (failed_at < 0) return this.FinishLine(pick, kit, spot_a, spot_b, path, full);

		local reason = AIError.GetLastErrorString();
		this.RemoveTrack(full, failed_at);
		if (AIError.GetLastError() == AIError.ERR_NOT_ENOUGH_CASH) break;
		AILog.Info("Sporet kunne ikke legges (" + reason + "). Finner ny trasé.");
		this.pf.Block(full[failed_at]);
	}

	if (stations_built) this.RemoveStations(spot_a.top, spot_a.far, spot_b.top, spot_b.far);
	this.Block(pair_key);
	return false;
}

function FjellbanenGods::BuildStations(spot_a, spot_b)
{
	if (!AIRail.BuildRailStation(spot_a.top, spot_a.track, 1, spot_a.length, AIStation.STATION_NEW)) return false;
	if (!AIRail.BuildRailStation(spot_b.top, spot_b.track, 1, spot_b.length, AIStation.STATION_NEW)) {
		AIRail.RemoveRailStationTileRectangle(spot_a.top, spot_a.far, false);
		return false;
	}
	return true;
}

function FjellbanenGods::RemoveStations(top_a, far_a, top_b, far_b)
{
	AIRail.RemoveRailStationTileRectangle(top_a, far_a, false);
	AIRail.RemoveRailStationTileRectangle(top_b, far_b, false);
}

/* Lay every piece; returns -1 on success or the index of the tile that failed. */
function FjellbanenGods::BuildTrack(full)
{
	for (local i = 1; i < full.len() - 1; i++) {
		if (AIRail.BuildRail(full[i - 1], full[i], full[i + 1])) continue;
		if (AIError.GetLastError() == AIError.ERR_ALREADY_BUILT) continue;
		return i;
	}
	return -1;
}

/* Remove pieces 1 .. upto - 1 of a line. */
function FjellbanenGods::RemoveTrack(full, upto)
{
	for (local i = 1; i < upto && i < full.len() - 1; i++) AIRail.RemoveRail(full[i - 1], full[i], full[i + 1]);
}

/* A depot beside a straight stretch near the source, linked toward the source station. */
function FjellbanenGods::BuildDepot(path)
{
	local last = FG_Min(DEPOT_SEARCH_TILES, path.len() - 2);
	for (local i = 1; i <= last; i++) {
		local tile = path[i];
		local dir = this.pf.DirBetween(path[i - 1], tile);
		if (dir != this.pf.DirBetween(tile, path[i + 1])) continue;
		if (AITile.GetSlope(tile) != AITile.SLOPE_FLAT || AIRoad.IsRoadTile(tile)) continue;

		local sides = dir / 2 == 0 ? [2, 3] : [0, 1];
		foreach (side in sides) {
			local depot = tile + this.pf.Offset(side);
			if (!AITile.IsBuildable(depot) || AITile.GetSlope(depot) != AITile.SLOPE_FLAT) continue;
			if (!AIRail.BuildRailDepot(depot, tile)) continue;
			if (AIRail.BuildRail(depot, tile, path[i - 1])) return [depot, tile, path[i - 1]];
			AITile.DemolishTile(depot);
		}
	}
	return null;
}

function FjellbanenGods::FinishLine(pick, kit, spot_a, spot_b, path, full)
{
	local depot = this.BuildDepot(path);
	if (depot == null) {
		AILog.Warning("Fant ikke plass til lokstall. Linjen rives.");
		this.RemoveTrack(full, full.len() - 1);
		this.RemoveStations(spot_a.top, spot_a.far, spot_b.top, spot_b.far);
		this.Block(this.PairKey(pick.source, pick.dest));
		return false;
	}

	local route = {
		source = pick.source, dest = pick.dest, cargo = pick.cargo, railtype = kit.railtype, length = spot_a.length,
		top_a = spot_a.top, far_a = spot_a.far, end_a = spot_a.end,
		top_b = spot_b.top, far_b = spot_b.far, end_b = spot_b.end,
		path = path, depot = depot[0], depot_on = depot[1], depot_toward = depot[2],
		train = null, dead = false
	};
	this.routes.push(route);
	AIBaseStation.SetName(AIStation.GetStationID(route.end_a), this.ShortName(this.IndustryName(pick.source)) + " godsterminal");
	AIBaseStation.SetName(AIStation.GetStationID(route.end_b), this.ShortName(this.IndustryName(pick.dest)) + " godsterminal");

	AILog.Info("Ny jernbane: " + this.IndustryName(pick.source) + " -> " + this.IndustryName(pick.dest) + " (" +
			AICargo.GetCargoLabel(pick.cargo) + ", " + path.len() + " spor, " + this.pf.expansions + " ruter undersøkt)");

	if (!this.BuildTrain(route)) AILog.Warning("Toget ble ikke kjøpt ennå. Prøver igjen ved neste gjennomgang.");
	return true;
}

function FjellbanenGods::ShortName(name)
{
	return name.len() > 18 ? name.slice(0, 18) : name;
}

/* --------------------------------------------------------------- trains */

function FjellbanenGods::BuildTrain(route)
{
	AIRail.SetCurrentRailType(route.railtype);
	local loco = this.PickLoco(route.railtype, FG_Max(0, this.SpendableMoney()));
	local wagon = this.PickWagon(route.railtype, route.cargo);
	if (loco == null || wagon == null) return false;
	if (!this.EnsureCash(AIEngine.GetPrice(loco) + AIEngine.GetPrice(wagon) * 2)) return false;

	local train = AIVehicle.BuildVehicle(route.depot, loco);
	if (!AIVehicle.IsValidVehicle(train)) {
		AILog.Warning("Kunne ikke kjøpe lokomotiv: " + AIError.GetLastErrorString());
		return false;
	}

	local max_length = route.length * 16;
	while (AIVehicle.GetLength(train) < max_length) {
		if (!this.EnsureCash(AIEngine.GetPrice(wagon))) break;
		local car = AIVehicle.BuildVehicle(route.depot, wagon);
		if (!AIVehicle.IsValidVehicle(car)) break;
		if (AIEngine.GetCargoType(wagon) != route.cargo) AIVehicle.RefitVehicle(car, route.cargo);
		if (!AIVehicle.MoveWagon(car, 0, train, AIVehicle.GetNumWagons(train) - 1)) {
			AIVehicle.SellVehicle(car);
			break;
		}
		if (AIVehicle.GetLength(train) > max_length) {
			AIVehicle.SellWagon(train, AIVehicle.GetNumWagons(train) - 1);
			break;
		}
	}
	if (AIVehicle.GetCapacity(train, route.cargo) <= 0) {
		AIVehicle.SellVehicle(train);
		return false;
	}

	AIOrder.AppendOrder(train, route.end_a, AIOrder.OF_FULL_LOAD_ANY | AIOrder.OF_NON_STOP_INTERMEDIATE);
	AIOrder.AppendOrder(train, route.end_b, AIOrder.OF_NO_LOAD | AIOrder.OF_NON_STOP_INTERMEDIATE);
	this.NameTrain(train);
	AIVehicle.StartStopVehicle(train);
	route.train = train;
	return true;
}

function FjellbanenGods::NameTrain(train)
{
	for (local attempt = 0; attempt < 5; attempt++) {
		local n = this.train_counter++;
		local name = TRAIN_NAMES[n % TRAIN_NAMES.len()] + " " + (n / TRAIN_NAMES.len() + 1);
		if (AIVehicle.SetName(train, name)) return;
	}
}

function FjellbanenGods::HasLiveTrain(route)
{
	return route.train != null && AIVehicle.IsValidVehicle(route.train) &&
			AIVehicle.GetState(route.train) != AIVehicle.VS_CRASHED;
}

/* Stop a line: send its train to be sold; track comes down once the train is gone. */
function FjellbanenGods::CloseLine(route, reason)
{
	if (route.dead) return;
	route.dead = true;
	AILog.Info("Linjen " + this.IndustryName(route.source) + " -> " + this.IndustryName(route.dest) + " legges ned: " + reason + ".");
	if (this.HasLiveTrain(route) && AIVehicle.SendVehicleToDepot(route.train)) this.to_sell[route.train] <- true;
}

function FjellbanenGods::TearDown(route)
{
	local full = [route.end_a];
	full.extend(route.path);
	full.push(route.end_b);
	AIRail.RemoveRail(route.depot, route.depot_on, route.depot_toward);
	AITile.DemolishTile(route.depot);
	this.RemoveTrack(full, full.len() - 1);
	this.RemoveStations(route.top_a, route.far_a, route.top_b, route.far_b);
}

/* ---------------------------------------------------------------- review */

function FjellbanenGods::Review()
{
	for (local i = this.routes.len() - 1; i >= 0; i--) {
		local route = this.routes[i];

		if (route.dead) {
			if (this.HasLiveTrain(route)) {
				/* Still on its last trip; ask again if the first depot order did not stick. */
				if (!(route.train in this.to_sell) && AIVehicle.SendVehicleToDepot(route.train)) this.to_sell[route.train] <- true;
				continue;
			}
			this.TearDown(route);
			this.routes.remove(i);
			continue;
		}

		if (!AIIndustry.IsValidIndustry(route.source) || !AIIndustry.IsValidIndustry(route.dest)) {
			this.CloseLine(route, "industrien er stengt");
			continue;
		}

		if (!this.HasLiveTrain(route)) {
			route.train = null;
			if (this.BuildTrain(route)) AILog.Info("Nytt tog satt inn på linjen fra " + this.IndustryName(route.source) + ".");
			continue;
		}

		local train = route.train;
		if (AIVehicle.GetAge(train) >= this.traits.retire_years * 365 + 365 &&
				AIVehicle.GetProfitLastYear(train) < 0 && AIVehicle.GetProfitThisYear(train) < 0) {
			this.CloseLine(route, "den taper penger");
		}
	}

	this.SellWaitingTrains();
	this.YearlyReport();
}

function FjellbanenGods::SellWaitingTrains()
{
	local done = [];
	foreach (veh, dummy in this.to_sell) {
		if (!AIVehicle.IsValidVehicle(veh)) done.push(veh);
		else if (AIVehicle.IsStoppedInDepot(veh) && AIVehicle.SellVehicle(veh)) done.push(veh);
	}
	foreach (veh in done) delete this.to_sell[veh];
}

function FjellbanenGods::YearlyReport()
{
	local year = AIDate.GetYear(AIDate.GetCurrentDate());
	if (year == this.last_report_year) return;
	if (this.last_report_year == 0) {
		this.last_report_year = year;
		return;
	}
	this.last_report_year = year;

	local profit = 0, trains = 0;
	foreach (route in this.routes) {
		if (route.dead) continue;
		local line_profit = 0;
		if (this.HasLiveTrain(route)) {
			trains++;
			line_profit = AIVehicle.GetProfitLastYear(route.train);
			profit += line_profit;
		}
		AILog.Info("  " + this.IndustryName(route.source) + " -> " + this.IndustryName(route.dest) + ": " +
				AICargo.GetCargoLabel(route.cargo) + ", overskudd " + line_profit +
				", venter " + AIStation.GetCargoWaiting(AIStation.GetStationID(route.end_a), route.cargo));
	}
	AILog.Info("Årsrapport " + (year - 1) + ": " + this.LiveRouteCount() + " jernbaner, " + trains + " tog, togoverskudd " +
			profit + ", bank " + AICompany.GetBankBalance(AICompany.COMPANY_SELF) + ", lån " + AICompany.GetLoanAmount());
}

/* ---------------------------------------------------------------- events */

function FjellbanenGods::HandleEvents()
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
			AILog.Warning("Et Fjellbanen-tog har forulykket. Nytt tog settes inn ved neste gjennomgang.");
		} else if (type == AIEvent.ET_VEHICLE_LOST) {
			local veh = AIEventVehicleLost.Convert(event).GetVehicleID();
			foreach (route in this.routes) {
				if (route.train != veh || route.dead) continue;
				route.lost <- ("lost" in route ? route.lost : 0) + 1;
				AILog.Warning(AIVehicle.GetName(veh) + " finner ikke frem.");
				if (route.lost >= 2) this.CloseLine(route, "toget finner ikke frem");
			}
		} else if (type == AIEvent.ET_INDUSTRY_CLOSE) {
			local industry = AIEventIndustryClose.Convert(event).GetIndustryID();
			foreach (route in this.routes) {
				if (route.source == industry || route.dest == industry) this.CloseLine(route, "industrien stenger");
			}
		} else if (type == AIEvent.ET_COMPANY_IN_TROUBLE) {
			local company = AIEventCompanyInTrouble.Convert(event).GetCompanyID();
			if (AICompany.IsMine(company)) AILog.Warning("Fjellbanen Gods sliter økonomisk.");
		}
	}
}

/* ------------------------------------------------------------- save/load */

function FjellbanenGods::Save()
{
	local saved = [];
	foreach (r in this.routes) {
		saved.push([r.source, r.dest, r.cargo, r.railtype, r.length, r.top_a, r.far_a, r.end_a, r.top_b, r.far_b, r.end_b,
				r.path, r.depot, r.depot_on, r.depot_toward, r.train == null ? -1 : r.train, r.dead ? 1 : 0]);
	}
	local selling = [];
	foreach (veh, dummy in this.to_sell) selling.push(veh);
	return { routes = saved, to_sell = selling, train_counter = this.train_counter,
			personality = this.personality == null ? -1 : this.personality };
}

function FjellbanenGods::Load(version, data)
{
	this.loaded_data = data;
}

function FjellbanenGods::RestoreState(data)
{
	if ("routes" in data) {
		foreach (r in data.routes) {
			this.routes.push({
				source = r[0], dest = r[1], cargo = r[2], railtype = r[3], length = r[4],
				top_a = r[5], far_a = r[6], end_a = r[7], top_b = r[8], far_b = r[9], end_b = r[10],
				path = r[11], depot = r[12], depot_on = r[13], depot_toward = r[14],
				train = (r[15] >= 0 && AIVehicle.IsValidVehicle(r[15])) ? r[15] : null, dead = r[16] != 0
			});
		}
	}
	if ("to_sell" in data) {
		foreach (veh in data.to_sell) if (AIVehicle.IsValidVehicle(veh)) this.to_sell[veh] <- true;
	}
	if ("train_counter" in data) this.train_counter = data.train_counter;
	if ("personality" in data && data.personality >= 0) this.personality = data.personality;
	this.pf = MT_RailPathfinder();
}
