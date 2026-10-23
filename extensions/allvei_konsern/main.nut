/*
 * Allvei Konsern - a Modern Tycoon AI that builds every kind of transport.
 *
 * Strategy in one breath: every few weeks, list every freight source on the
 * map (with each customer it could reach) and every town pair, estimate the
 * yearly profit and the building cost of serving it by truck, train, ship,
 * bus or plane, and build the one with the best return that we can afford.
 * Goods, food and water also go to towns. Each route then grows with its
 * waiting cargo, gets better vehicles through autoreplace, and is shut down
 * when its industry closes or it keeps losing money. Rich years fund new
 * industries where a producer has no customer within reach.
 *
 * Files: road.nut (road pathfinder, trucks and buses), water.nut (ships),
 * air.nut (planes), rail.nut + pathfinder.nut (trains), industry.nut
 * (funding), personality.nut (shared with the other Modern Tycoon AIs).
 *
 * Log messages are in Norwegian as part of the company's personality.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

require("personality.nut");
require("pathfinder.nut");

const AK_MODE_ROAD = 0;    // Trucks, industry or town customer.
const AK_MODE_RAIL = 1;    // Freight train.
const AK_MODE_WATER = 2;   // Ships.
const AK_MODE_AIR = 3;     // Passenger planes between towns.
const AK_MODE_BUS = 4;     // Buses between towns.

const AK_DAYS_BETWEEN_REVIEWS = 20;
const AK_DAYS_BEFORE_RETRY = 365;
const AK_MAX_SOURCES = 120;           // Busiest freight sources looked at per planning round.
const AK_MIN_PRODUCTION = 10;
const AK_MAX_FOREIGN_TRANSPORTED = 60;
const AK_SECOND_ROUTE_PRODUCTION = 100;  // Monthly production that may justify a second route from one source.
const AK_DAYS_BETWEEN_FLEET_CHANGES = 90;

AK_MODE_NAMES <- ["lastebil", "tog", "skip", "fly", "buss"];

function AK_Min(a, b) { return a < b ? a : b; }
function AK_Max(a, b) { return a > b ? a : b; }
function AK_Cmp(a, b) { return a < b ? -1 : (a > b ? 1 : 0); }
function AK_Abs(v) { return v < 0 ? -v : v; }
function AK_Clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }

function AK_Tile(x, y)
{
	return AIMap.GetTileIndex(AK_Clamp(x, 1, AIMap.GetMapSizeX() - 2), AK_Clamp(y, 1, AIMap.GetMapSizeY() - 2));
}

function AK_CarriesCargo(engine, cargo)
{
	return AIEngine.GetCargoType(engine) == cargo || AIEngine.CanRefitCargo(engine, cargo);
}

function AK_EngineScore(engine)
{
	return AIEngine.GetCapacity(engine) * AK_Max(AIEngine.GetMaxSpeed(engine), 1) * AIEngine.GetReliability(engine) / 100;
}

/* Tiles a vehicle covers per day at `speed` km/h (rough, measured in game). Planes fly at a quarter of their speed by default. */
function AK_TilesPerDayX10(mode, speed)
{
	if (mode == AK_MODE_AIR) return AK_Max(1, speed * 10 / 80);
	return AK_Max(1, speed * 10 / 20);
}

class AllveiKonsern extends AIController {
	routes = null;        // Array of route tables; see the Build* functions of each mode.
	to_sell = null;       // Table: vehicle id -> true, on their last trip to a depot.
	failed = null;        // Table: string key -> date after which we may try again.
	cache = null;         // Per planning round: best engines and coastal checks.
	passenger = null;
	mail = null;
	personality = null;
	traits = null;
	rail_pf = null;
	next_id = 1;
	vehicle_counter = 0;
	next_review = 0;
	next_build = 0;
	next_funding = 0;
	last_report_year = 0;
	loaded_data = null;

	constructor()
	{
		this.routes = [];
		this.to_sell = {};
		this.failed = {};
		this.cache = {};
	}
}

require("road.nut");
require("water.nut");
require("air.nut");
require("rail.nut");
require("industry.nut");

function AllveiKonsern::Start()
{
	this.SetIdentity();
	AICompany.SetAutoRenewStatus(true);
	AICompany.SetAutoRenewMonths(-6);
	AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
	this.rail_pf = MT_RailPathfinder();

	this.passenger = this.FindCargo(AICargo.CC_PASSENGERS);
	this.mail = this.FindCargo(AICargo.CC_MAIL);

	if (this.loaded_data != null) this.RestoreState(this.loaded_data);
	this.loaded_data = null;
	if (this.personality == null) this.personality = MT_ResolvePersonality(AIController.GetSetting("personality"));
	this.traits = MT_Traits(this.personality);

	AILog.Info("Allvei Konsern er klar. Personlighet: " + this.traits.name + ". Ruter i drift: " + this.LiveRouteCount());

	while (true) {
		this.HandleEvents();

		local today = AIDate.GetCurrentDate();
		if (today >= this.next_review) {
			this.Review();
			this.next_review = AIDate.GetCurrentDate() + AK_DAYS_BETWEEN_REVIEWS;
		}

		today = AIDate.GetCurrentDate();
		if (today >= this.next_build && this.LiveRouteCount() < AIController.GetSetting("max_routes")) {
			local built = this.TryBuildBest();
			this.next_build = AIDate.GetCurrentDate() + (built ? 3 : this.traits.retry_days);
		}

		today = AIDate.GetCurrentDate();
		if (today >= this.next_funding && AIController.GetSetting("fund_industries") != 0) {
			this.FundIndustries();
			this.next_funding = AIDate.GetCurrentDate() + 120;
		}

		if (MT_RepayLoan(this.traits)) AILog.Info("Lånet er nedbetalt. Allvei Konsern er gjeldfri!");
		this.Sleep(30);
	}
}

/* ---------------------------------------------------------------- basics */

function AllveiKonsern::SetIdentity()
{
	local current = AICompany.GetName(AICompany.COMPANY_SELF);
	if (current == null || current.find("Allvei Konsern") != 0) {
		if (!AICompany.SetName("Allvei Konsern")) {
			local i = 2;
			while (i < 20 && !AICompany.SetName("Allvei Konsern " + i)) i++;
		}
		AICompany.SetPresidentName("Ragnhild Vognmand");
	}
	if (!AICompany.SetPrimaryLiveryColour(AICompany.LS_DEFAULT, AICompany.COLOUR_DARK_BLUE)) {
		AICompany.SetPrimaryLiveryColour(AICompany.LS_DEFAULT, AICompany.COLOUR_BLUE);
	}
	AICompany.SetSecondaryLiveryColour(AICompany.LS_DEFAULT, AICompany.COLOUR_YELLOW);
}

function AllveiKonsern::FindCargo(cargo_class)
{
	foreach (cargo, dummy in AICargoList()) {
		if (AICargo.HasCargoClass(cargo, cargo_class)) return cargo;
	}
	return null;
}

function AllveiKonsern::UseLoan() { return AIController.GetSetting("use_loan") != 0; }
function AllveiKonsern::EnsureCash(amount) { return MT_EnsureCash(amount, this.traits, this.UseLoan()); }
function AllveiKonsern::SpendableMoney() { return MT_SpendableMoney(this.traits, this.UseLoan()); }

function AllveiKonsern::LiveRouteCount()
{
	local count = 0;
	foreach (route in this.routes) if (!route.dead) count++;
	return count;
}

function AllveiKonsern::IsBlocked(key)
{
	return (key in this.failed) && this.failed[key] > AIDate.GetCurrentDate();
}

function AllveiKonsern::Block(key, days = AK_DAYS_BEFORE_RETRY)
{
	this.failed[key] <- AIDate.GetCurrentDate() + days;
}

function AllveiKonsern::PlaceName(id, is_town)
{
	if (is_town) return AITown.IsValidTown(id) ? AITown.GetName(id) : ("by " + id);
	return AIIndustry.IsValidIndustry(id) ? AIIndustry.GetName(id) : ("industri " + id);
}

function AllveiKonsern::RouteName(route)
{
	return this.PlaceName(route.src, route.src_town) + " -> " + this.PlaceName(route.dst, route.dst_town);
}

function AllveiKonsern::ModeEnabled(mode)
{
	if (mode == AK_MODE_ROAD || mode == AK_MODE_BUS) return AIController.GetSetting("use_road") != 0 && !AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_ROAD);
	if (mode == AK_MODE_RAIL) return AIController.GetSetting("use_rail") != 0 && !AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_RAIL);
	if (mode == AK_MODE_WATER) return AIController.GetSetting("use_water") != 0 && !AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_WATER);
	if (mode == AK_MODE_AIR) return AIController.GetSetting("use_air") != 0 && !AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_AIR);
	return false;
}

function AllveiKonsern::ModeVehicleType(mode)
{
	if (mode == AK_MODE_RAIL) return AIVehicle.VT_RAIL;
	if (mode == AK_MODE_WATER) return AIVehicle.VT_WATER;
	if (mode == AK_MODE_AIR) return AIVehicle.VT_AIR;
	return AIVehicle.VT_ROAD;
}

/* Key that says "this source already ships this cargo with us". */
function AllveiKonsern::ServeKey(src, cargo, src_town) { return (src_town ? "t" : "i") + src + "_" + cargo; }
function AllveiKonsern::PairKey(mode, src, dst, cargo) { return "p" + mode + "_" + src + "_" + dst + "_" + cargo; }

/* ------------------------------------------------------------- engines */

/* Best engine of a vehicle type for a cargo; cached for one planning round. */
function AllveiKonsern::BestEngine(vtype, cargo)
{
	local key = "e" + vtype + "_" + cargo;
	if (key in this.cache) return this.cache[key];

	local engines = AIEngineList(vtype);
	engines.Valuate(AIEngine.IsBuildable);
	engines.KeepValue(1);
	engines.Valuate(AK_CarriesCargo, cargo);
	engines.KeepValue(1);
	if (vtype == AIVehicle.VT_ROAD) {
		engines.Valuate(AIEngine.GetRoadType);
		engines.KeepValue(AIRoad.ROADTYPE_ROAD);
		engines.Valuate(AIEngine.IsArticulated);   // Articulated vehicles cannot use bay stops.
		engines.KeepValue(0);
	}
	if (vtype == AIVehicle.VT_AIR) {
		engines.Valuate(AIEngine.GetPlaneType);
		engines.RemoveValue(AIAirport.PT_BIG_PLANE);   // Big planes crash on small airports; keep it simple and safe.
	}

	local best = null, best_score = -1;
	foreach (engine, dummy in engines) {
		local score = AK_EngineScore(engine);
		if (score > best_score) {
			best_score = score;
			best = engine;
		}
	}
	this.cache[key] <- best;
	return best;
}

/* ------------------------------------------------------- the estimator */

/*
 * Rough yearly money for serving `monthly` units of `cargo` over `dist` tiles.
 * Returns { score, cost, profit, vehicles } or null when it does not pay.
 */
function AllveiKonsern::Estimate(mode, cargo, dist, monthly, both_ways)
{
	local capacity = 0, speed = 0, price = 0, running = 0, max_vehicles = 1, infra = 0;
	local max_per_route = AIController.GetSetting("max_vehicles_per_route");

	if (mode == AK_MODE_RAIL) {
		local kit = this.RailKit(cargo);
		if (kit == null) return null;
		local wagons = this.traits.station_length * 2 - 1;
		capacity = AIEngine.GetCapacity(kit.wagon) * wagons;
		speed = AIEngine.GetMaxSpeed(kit.loco);
		local wagon_speed = AIEngine.GetMaxSpeed(kit.wagon);
		if (wagon_speed > 0) speed = AK_Min(speed, wagon_speed);
		price = AIEngine.GetPrice(kit.loco) + AIEngine.GetPrice(kit.wagon) * wagons;
		running = AIEngine.GetRunningCost(kit.loco);
		max_vehicles = 1;
		infra = dist * 14 / 10 * AIRail.GetBuildCost(kit.railtype, AIRail.BT_TRACK) * 3 +
				2 * this.traits.station_length * AIRail.GetBuildCost(kit.railtype, AIRail.BT_STATION) +
				AIRail.GetBuildCost(kit.railtype, AIRail.BT_DEPOT);
	} else {
		local engine = this.BestEngine(this.ModeVehicleType(mode), cargo);
		if (engine == null) return null;
		capacity = AIEngine.GetCapacity(engine);
		speed = AIEngine.GetMaxSpeed(engine);
		price = AIEngine.GetPrice(engine);
		running = AIEngine.GetRunningCost(engine);
		if (mode == AK_MODE_ROAD || mode == AK_MODE_BUS) {
			max_vehicles = AK_Min(max_per_route, 3 + dist / 5);
			infra = dist * 13 / 10 * AIRoad.GetBuildCost(AIRoad.ROADTYPE_ROAD, AIRoad.BT_ROAD) * 2 +
					2 * AIRoad.GetBuildCost(AIRoad.ROADTYPE_ROAD, AIRoad.BT_TRUCK_STOP) +
					AIRoad.GetBuildCost(AIRoad.ROADTYPE_ROAD, AIRoad.BT_DEPOT);
		} else if (mode == AK_MODE_WATER) {
			max_vehicles = AK_Min(max_per_route, 2 + dist / 12);
			infra = 2 * AIMarine.GetBuildCost(AIMarine.BT_DOCK) + AIMarine.GetBuildCost(AIMarine.BT_DEPOT);
		} else if (mode == AK_MODE_AIR) {
			max_vehicles = 6;
			local type = this.BestAirportType();
			if (type == null) return null;
			infra = 2 * AIAirport.GetPrice(type);
		}
	}
	if (capacity <= 0 || speed <= 0) return null;

	local tpd_x10 = AK_TilesPerDayX10(mode, speed);
	local travel = dist * 10 / tpd_x10 + 2;
	if (mode == AK_MODE_ROAD || mode == AK_MODE_BUS) travel = travel * 5 / 4;   // Bends, junctions, towns.
	local income = AICargo.GetCargoIncome(cargo, dist, travel);
	if (income <= 0) return null;

	local units = monthly * 7 / 10;
	if (units <= 0) return null;
	local round_trip = 2 * travel + 6;
	local per_vehicle = AK_Max(1, capacity * 30 / round_trip);
	if (both_ways) per_vehicle *= 2;
	local vehicles = AK_Clamp((units + per_vehicle - 1) / per_vehicle, 1, max_vehicles);
	local moved = AK_Min(units, vehicles * per_vehicle);

	local profit = moved * 12 * income - vehicles * running;
	if (profit <= 0) return null;
	local first_vehicles = mode == AK_MODE_RAIL ? 1 : AK_Min(vehicles, 3);
	local cost = infra + first_vehicles * price;
	return { score = profit * 100 / AK_Max(cost, 1), cost = cost, profit = profit, vehicles = vehicles };
}

/* ---------------------------------------------------- choosing a project */

function AllveiKonsern::ModeDistanceOk(mode, dist)
{
	if (mode == AK_MODE_ROAD) return dist >= 10 && dist <= 130;
	if (mode == AK_MODE_BUS) return dist >= 15 && dist <= 80;
	if (mode == AK_MODE_RAIL) return dist >= 45 && dist <= 150;
	if (mode == AK_MODE_WATER) return dist >= 12 && dist <= 140;
	if (mode == AK_MODE_AIR) return dist >= 90 && dist <= 600;
	return false;
}

/* Every freight and passenger project worth considering right now, best first. */
function AllveiKonsern::ListProjects()
{
	this.cache = {};
	local projects = [];
	/* served: source+cargo -> number of our routes; existing: pairs we already run. */
	local served = {}, existing = {};
	foreach (route in this.routes) {
		if (route.dead) continue;
		local key = this.ServeKey(route.src, route.cargo, route.src_town);
		served[key] <- (key in served ? served[key] : 0) + 1;
		existing[this.PairKey(route.mode, route.src, route.dst_town && !route.src_town ? -1 - route.dst : route.dst, route.cargo)] <- true;
	}

	/* Freight: the busiest sources first. */
	local sources = AIIndustryList();
	sources.Valuate(AK_IndustryTotalProduction);
	sources.KeepAboveValue(AK_MIN_PRODUCTION - 1);
	sources.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
	sources.KeepTop(AK_MAX_SOURCES);

	foreach (src, dummy in sources) {
		if (this.IsBlocked("s" + src)) continue;
		local src_tile = AIIndustry.GetLocation(src);
		local on_water = AIIndustry.IsBuiltOnWater(src);
		foreach (cargo, dummy2 in AICargoList_IndustryProducing(src)) {
			if (!AICargo.IsFreight(cargo)) continue;
			local production = AIIndustry.GetLastMonthProduction(src, cargo);
			if (production < AK_MIN_PRODUCTION) continue;
			local transported = AIIndustry.GetLastMonthTransportedPercentage(src, cargo);
			local ours = this.ServeKey(src, cargo, false);
			local count = (ours in served) ? served[ours] : 0;
			/* A big producer we serve, with much cargo left behind, may get a second customer. */
			if (count >= 2 || (count == 1 && (production < AK_SECOND_ROUTE_PRODUCTION || transported > 55))) continue;
			if (count == 0 && transported > AK_MAX_FOREIGN_TRANSPORTED) continue;
			if (count == 1) production = production * (100 - transported) / 100;

			local dests = AIIndustryList_CargoAccepting(cargo);
			dests.Valuate(AIIndustry.GetDistanceManhattanToTile, src_tile);
			dests.KeepBetweenValue(9, 201);
			foreach (dst, dist in dests) {
				if (dst == src) continue;
				foreach (mode in [AK_MODE_ROAD, AK_MODE_RAIL, AK_MODE_WATER]) {
					if (!this.ModeEnabled(mode) || !this.ModeDistanceOk(mode, dist)) continue;
					if (on_water && mode != AK_MODE_WATER) continue;
					if (AIIndustry.IsBuiltOnWater(dst) && mode != AK_MODE_WATER) continue;
					if (mode == AK_MODE_WATER && (!this.IsCoastal(src, true, cargo) || !this.IsCoastal(dst, false, cargo))) continue;
					local pair = this.PairKey(mode, src, dst, cargo);
					if ((pair in existing) || this.IsBlocked(pair)) continue;
					local est = this.Estimate(mode, cargo, dist, production, false);
					if (est == null) continue;
					projects.push({ mode = mode, cargo = cargo, src = src, dst = dst, src_town = false, dst_town = false,
							dist = dist, score = est.score, cost = est.cost, profit = est.profit, vehicles = est.vehicles });
				}
			}

			/* Goods, food and water: towns are customers too. */
			if (AICargo.GetTownEffect(cargo) != AICargo.TE_NONE && this.ModeEnabled(AK_MODE_ROAD) && !on_water) {
				local towns = AITownList();
				towns.Valuate(AITown.GetPopulation);
				towns.KeepAboveValue(AICargo.GetTownEffect(cargo) == AICargo.TE_GOODS ? 900 : 300);
				towns.Valuate(AITown.GetDistanceManhattanToTile, src_tile);
				towns.KeepBetweenValue(9, 111);
				foreach (town, dist in towns) {
					local pair = this.PairKey(AK_MODE_ROAD, src, -1 - town, cargo);
					if ((pair in existing) || this.IsBlocked(pair)) continue;
					local est = this.Estimate(AK_MODE_ROAD, cargo, dist, production, false);
					if (est == null) continue;
					projects.push({ mode = AK_MODE_ROAD, cargo = cargo, src = src, dst = town, src_town = false, dst_town = true,
							dist = dist, score = est.score, cost = est.cost, profit = est.profit, vehicles = est.vehicles });
				}
			}
		}
	}

	/* Passengers: buses between neighbouring towns, planes between distant big towns. */
	if (this.passenger != null) this.ListPassengerProjects(projects, existing);

	projects.sort(function(a, b) { return AK_Cmp(b.score, a.score); });
	local counts = [0, 0, 0, 0, 0];
	foreach (p in projects) counts[p.mode]++;
	local summary = "";
	for (local m = 0; m < counts.len(); m++) summary += " " + AK_MODE_NAMES[m] + " " + counts[m];
	AILog.Info("Mulige prosjekter:" + summary);
	return projects;
}

function AK_IndustryTotalProduction(industry)
{
	local total = 0;
	foreach (cargo, dummy in AICargoList_IndustryProducing(industry)) total += AIIndustry.GetLastMonthProduction(industry, cargo);
	return total;
}

/* Passengers and mail between towns: road for neighbours, planes for distant big towns. */
function AllveiKonsern::ListPassengerProjects(projects, existing)
{
	/* Lines per town, per mode and cargo. Big towns may carry several bus lines. */
	local lines = {};
	foreach (route in this.routes) {
		if (route.dead || !route.src_town) continue;
		foreach (town in [route.src, route.dst]) {
			local key = "l" + town + "_" + route.mode + "_" + route.cargo;
			lines[key] <- (key in lines ? lines[key] : 0) + 1;
		}
	}

	local towns = AITownList();
	towns.Valuate(AITown.GetPopulation);
	towns.KeepAboveValue(399);
	towns.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
	towns.KeepTop(50);
	local list = [];
	foreach (town, pop in towns) list.push([town, pop]);

	local options = [[AK_MODE_BUS, this.passenger, 20], [AK_MODE_AIR, this.passenger, 40]];
	if (this.mail != null) options.push([AK_MODE_BUS, this.mail, 35]);

	for (local i = 0; i < list.len(); i++) {
		for (local j = i + 1; j < list.len(); j++) {
			local a = list[i][0], b = list[j][0];
			local dist = AIMap.DistanceManhattan(AITown.GetLocation(a), AITown.GetLocation(b));
			foreach (opt in options) {
				local mode = opt[0], cargo = opt[1], share = opt[2];
				if (!this.ModeEnabled(mode) || !this.ModeDistanceOk(mode, dist)) continue;
				if (mode == AK_MODE_AIR && AK_Min(list[i][1], list[j][1]) < 900) continue;
				local full = false;
				foreach (t in [list[i], list[j]]) {
					local key = "l" + t[0] + "_" + mode + "_" + cargo;
					local allowed = mode == AK_MODE_AIR ? 1 : 1 + t[1] / 1500;
					if ((key in lines) && lines[key] >= allowed) full = true;
				}
				if (full) continue;
				local pair = this.PairKey(mode, a, b, cargo);
				if ((pair in existing) || this.IsBlocked(pair)) continue;
				if (this.IsBlocked("t" + a + "_" + mode) || this.IsBlocked("t" + b + "_" + mode)) continue;
				/* A stop or airport catches only part of a town's passengers or mail. */
				local monthly = AK_Min(AITown.GetLastMonthProduction(a, cargo), AITown.GetLastMonthProduction(b, cargo)) * share / 100;
				local est = this.Estimate(mode, cargo, dist, monthly, true);
				if (est == null) continue;
				projects.push({ mode = mode, cargo = cargo, src = a, dst = b, src_town = true, dst_town = true,
						dist = dist, score = est.score, cost = est.cost, profit = est.profit, vehicles = est.vehicles });
			}
		}
	}
}

/* Build the best project we can afford. Returns true when something was built. */
function AllveiKonsern::TryBuildBest()
{
	local spendable = this.SpendableMoney();
	if (spendable <= 0) return false;
	local projects = this.ListProjects();
	if (projects.len() == 0) {
		AILog.Info("Fant ingen lønnsomme prosjekter akkurat nå.");
		return false;
	}

	local tried = 0;
	foreach (p in projects) {
		if (p.cost > spendable) continue;
		/* The first candidates may share a town or industry; keep the round short. */
		if (++tried > 3) break;
		AILog.Info("Beste prosjekt: " + AK_MODE_NAMES[p.mode] + " " + this.PlaceName(p.src, p.src_town) + " -> " +
				this.PlaceName(p.dst, p.dst_town) + " (" + AICargo.GetCargoLabel(p.cargo) + ", " + p.dist +
				" ruter, ventet overskudd " + p.profit + "/år, kostnad " + p.cost + ")");
		local ok = false;
		if (p.mode == AK_MODE_ROAD || p.mode == AK_MODE_BUS) ok = this.BuildRoadRoute(p);
		else if (p.mode == AK_MODE_WATER) ok = this.BuildWaterRoute(p);
		else if (p.mode == AK_MODE_AIR) ok = this.BuildAirRoute(p);
		else if (p.mode == AK_MODE_RAIL) ok = this.BuildRailRoute(p);
		if (ok) return true;
		this.Block(this.PairKey(p.mode, p.src, p.dst_town ? -1 - p.dst : p.dst, p.cargo));
		if (p.src_town) this.Block(this.PairKey(p.mode, p.src, p.dst, p.cargo));
	}
	if (tried == 0) AILog.Info("Beste prosjekt koster " + projects[0].cost + ". Sparer først.");
	return false;
}

/* Register a finished route and give it a vehicle group. */
function AllveiKonsern::AddRoute(route)
{
	route.id <- this.next_id++;
	route.dead <- false;
	route.lost <- 0;
	route.built <- AIDate.GetCurrentDate();
	local group = AIGroup.CreateGroup(this.ModeVehicleType(route.mode), AIGroup.GROUP_INVALID);
	route.group <- group;
	if (AIGroup.IsValidGroup(group)) {
		local name = AK_MODE_NAMES[route.mode] + " " + route.id + " " + AICargo.GetCargoLabel(route.cargo);
		AIGroup.SetName(group, name);
	}
	this.routes.push(route);
	AILog.Info("Ny rute (" + AK_MODE_NAMES[route.mode] + "): " + this.RouteName(route) + ", " +
			AICargo.GetCargoLabel(route.cargo) + ", " + route.dist + " ruter");
	return route;
}

/* ------------------------------------------------------------ vehicles */

function AllveiKonsern::RouteVehicles(route)
{
	local result = [];
	if (!AIGroup.IsValidGroup(route.group)) return result;
	foreach (veh, dummy in AIVehicleList_Group(route.group)) {
		if (veh in this.to_sell) continue;
		if (AIVehicle.GetState(veh) == AIVehicle.VS_CRASHED) continue;
		result.push(veh);
	}
	return result;
}

/* Buy one vehicle of `engine` in `depot`, refit it, and put it in the route's group. Returns the vehicle or null. */
function AllveiKonsern::BuyVehicle(route, depot, engine)
{
	if (engine == null) return null;
	if (!this.EnsureCash(AIEngine.GetPrice(engine))) return null;
	local veh = AIVehicle.BuildVehicle(depot, engine);
	if (!AIVehicle.IsValidVehicle(veh)) {
		AILog.Warning("Kunne ikke kjøpe " + AK_MODE_NAMES[route.mode] + ": " + AIError.GetLastErrorString());
		return null;
	}
	if (AIEngine.GetCargoType(engine) != route.cargo) AIVehicle.RefitVehicle(veh, route.cargo);
	if (AIVehicle.GetCapacity(veh, route.cargo) <= 0) {
		AIVehicle.SellVehicle(veh);
		return null;
	}
	if (AIGroup.IsValidGroup(route.group)) AIGroup.MoveVehicle(route.group, veh);
	AIVehicle.SetName(veh, "Allvei " + AK_MODE_NAMES[route.mode] + " " + (++this.vehicle_counter));
	return veh;
}

/* Add one vehicle to a route, whatever its mode. */
function AllveiKonsern::AddVehicle(route, count)
{
	if (route.mode == AK_MODE_ROAD || route.mode == AK_MODE_BUS) return this.AddRoadVehicle(route, count);
	if (route.mode == AK_MODE_WATER) return this.AddShip(route, count);
	if (route.mode == AK_MODE_AIR) return this.AddPlane(route, count);
	if (route.mode == AK_MODE_RAIL) return this.BuildTrain(route);
	return false;
}

function AllveiKonsern::SendToSell(veh)
{
	if (veh in this.to_sell) return true;
	if (AIVehicle.IsStoppedInDepot(veh)) return AIVehicle.SellVehicle(veh);
	if (!AIVehicle.SendVehicleToDepot(veh)) return false;
	this.to_sell[veh] <- true;
	return true;
}

function AllveiKonsern::SellWaitingVehicles()
{
	local done = [];
	foreach (veh, dummy in this.to_sell) {
		if (!AIVehicle.IsValidVehicle(veh)) done.push(veh);
		else if (AIVehicle.IsStoppedInDepot(veh) && AIVehicle.SellVehicle(veh)) done.push(veh);
		else if (!AIVehicle.IsStoppedInDepot(veh) && !AIOrder.IsGotoDepotOrder(veh, AIOrder.ORDER_CURRENT)) {
			/* The depot order was lost (for example after a breakdown service); ask again. */
			AIVehicle.SendVehicleToDepot(veh);
		}
	}
	foreach (veh in done) delete this.to_sell[veh];
}

/* Point the route's group at a clearly better engine; autoreplace swaps vehicles on their next depot visit. */
function AllveiKonsern::UpgradeFleet(route, vehicles)
{
	if (route.mode == AK_MODE_RAIL || vehicles.len() == 0) return;
	local best = this.BestEngine(this.ModeVehicleType(route.mode), route.cargo);
	if (best == null) return;
	local seen = {};
	foreach (veh in vehicles) {
		local engine = AIVehicle.GetEngineType(veh);
		if (engine == best || (engine in seen)) continue;
		seen[engine] <- true;
		if (AK_EngineScore(best) * 100 < AK_EngineScore(engine) * 125) continue;
		if (AIGroup.GetEngineReplacement(route.group, engine) == best) continue;
		if (AIGroup.SetAutoReplace(route.group, engine, best)) {
			AILog.Info(this.RouteName(route) + ": " + AIEngine.GetName(engine) + " byttes til " + AIEngine.GetName(best) + ".");
		}
	}
}

/* ---------------------------------------------------------------- review */

function AllveiKonsern::Review()
{
	this.cache = {};
	local max_per_route = AIController.GetSetting("max_vehicles_per_route");

	for (local i = this.routes.len() - 1; i >= 0; i--) {
		local route = this.routes[i];
		local vehicles = this.RouteVehicles(route);

		if (route.dead) {
			foreach (veh in vehicles) this.SendToSell(veh);
			if (vehicles.len() == 0 && this.RouteVehicles(route).len() == 0 && this.NoneLeftToSell(route)) {
				this.TearDownRoute(route);
				this.routes.remove(i);
			}
			continue;
		}

		if ((!route.src_town && !AIIndustry.IsValidIndustry(route.src)) || (!route.dst_town && !AIIndustry.IsValidIndustry(route.dst))) {
			this.CloseRoute(route, "industrien er stengt");
			continue;
		}
		if (!this.StationsIntact(route)) {
			this.CloseRoute(route, "en stasjon er borte");
			continue;
		}

		if (vehicles.len() == 0) {
			if (this.AddVehicle(route, 0)) AILog.Info(this.RouteName(route) + ": nytt kjøretøy satt inn.");
			continue;
		}

		/* Grow or shrink at most once per AK_DAYS_BETWEEN_FLEET_CHANGES, so the fleet does not see-saw. */
		local today = AIDate.GetCurrentDate();
		local settled = !("changed" in route) || today - route.changed >= AK_DAYS_BETWEEN_FLEET_CHANGES;

		/* Grow: cargo piles up at a stop and the rating suffers. */
		local limit = route.mode == AK_MODE_RAIL ? 1 : (route.mode == AK_MODE_AIR ? 8 : max_per_route);
		if (route.mode == AK_MODE_ROAD || route.mode == AK_MODE_BUS) limit = AK_Min(limit, 3 + route.dist / 5);
		local shrunk_lately = ("shrunk" in route) && today - route.shrunk < AK_DAYS_BETWEEN_FLEET_CHANGES * 2;
		if (vehicles.len() < limit && !shrunk_lately && this.NeedsMoreVehicles(route, vehicles)) {
			if (this.AddVehicle(route, vehicles.len())) {
				route.changed <- today;
				settled = false;
				AILog.Info(this.RouteName(route) + ": last hoper seg opp, " + AK_MODE_NAMES[route.mode] + " nr. " + (vehicles.len() + 1) + " satt inn.");
			}
		}

		/* Shrink: too many vehicles queueing for too little cargo. */
		if (settled && vehicles.len() > 2 && this.HasTooManyVehicles(route, vehicles)) {
			if (this.SendToSell(vehicles[vehicles.len() - 1])) {
				route.changed <- today;
				route.shrunk <- today;
				AILog.Info(this.RouteName(route) + ": for mange kjøretøy, ett selges.");
			}
		}

		this.UpgradeFleet(route, vehicles);
		this.JudgeProfit(route, vehicles);
	}

	this.SellWaitingVehicles();
	this.YearlyReport();
}

function AllveiKonsern::NoneLeftToSell(route)
{
	if (!AIGroup.IsValidGroup(route.group)) return true;
	return AIVehicleList_Group(route.group).Count() == 0;
}

function AllveiKonsern::StationsIntact(route)
{
	return AIStation.IsValidStation(AIStation.GetStationID(route.st_a)) && AIStation.IsValidStation(AIStation.GetStationID(route.st_b));
}

function AllveiKonsern::NeedsMoreVehicles(route, vehicles)
{
	local capacity = 0;
	foreach (veh in vehicles) capacity = AK_Max(capacity, AIVehicle.GetCapacity(veh, route.cargo));
	if (capacity <= 0) return false;
	local st_a = AIStation.GetStationID(route.st_a);
	local waiting = AIStation.GetCargoWaiting(st_a, route.cargo);
	local rating = AIStation.GetCargoRating(st_a, route.cargo);
	if (route.src_town && route.dst_town) {
		local st_b = AIStation.GetStationID(route.st_b);
		waiting = AK_Max(waiting, AIStation.GetCargoWaiting(st_b, route.cargo));
		rating = AK_Min(rating, AIStation.GetCargoRating(st_b, route.cargo));
	}
	/* Young vehicles may still be on their first trip. */
	foreach (veh in vehicles) if (AIVehicle.GetAge(veh) < 30) return false;
	return waiting * 10 > capacity * this.traits.growth_x10 || (rating < 50 && waiting > capacity / 2);
}

/* Several full-load vehicles waiting at the pickup while nothing is waiting: one is surplus. */
function AllveiKonsern::HasTooManyVehicles(route, vehicles)
{
	if (route.src_town) return false;
	local st_a = AIStation.GetStationID(route.st_a);
	if (AIStation.GetCargoWaiting(st_a, route.cargo) > 0) return false;
	local idle = 0;
	foreach (veh in vehicles) {
		if (AIVehicle.GetState(veh) != AIVehicle.VS_AT_STATION && AIVehicle.GetCurrentSpeed(veh) > 0) continue;
		if (AIMap.DistanceManhattan(AIVehicle.GetLocation(veh), route.st_a) <= 3) idle++;
	}
	return idle >= 3;
}

/* Retire vehicles and routes that keep losing money. */
function AllveiKonsern::JudgeProfit(route, vehicles)
{
	local grace = this.traits.retire_years * 365 + 365;
	local route_profit = 0, judged = 0;
	foreach (veh in vehicles) {
		if (AIVehicle.GetAge(veh) < grace) continue;
		judged++;
		local p = AIVehicle.GetProfitLastYear(veh);
		route_profit += p;
		if (p < 0 && AIVehicle.GetProfitThisYear(veh) < 0 && vehicles.len() > 1) {
			if (this.SendToSell(veh)) AILog.Info(AIVehicle.GetName(veh) + " taper penger og selges.");
		}
	}
	if (judged > 0 && judged == vehicles.len() && route_profit < 0 && AIDate.GetCurrentDate() - route.built > grace) {
		this.CloseRoute(route, "den taper penger");
	}
}

function AllveiKonsern::CloseRoute(route, reason)
{
	if (route.dead) return;
	route.dead = true;
	AILog.Info("Ruten " + this.RouteName(route) + " (" + AK_MODE_NAMES[route.mode] + ") legges ned: " + reason + ".");
	foreach (veh in this.RouteVehicles(route)) this.SendToSell(veh);
	/* Don't rebuild the same thing right away. */
	this.Block(this.PairKey(route.mode, route.src, route.dst_town && !route.src_town ? -1 - route.dst : route.dst, route.cargo), 2 * AK_DAYS_BEFORE_RETRY);
}

function AllveiKonsern::TearDownRoute(route)
{
	if (route.mode == AK_MODE_ROAD || route.mode == AK_MODE_BUS) this.TearDownRoad(route);
	else if (route.mode == AK_MODE_WATER) this.TearDownWater(route);
	else if (route.mode == AK_MODE_AIR) this.TearDownAir(route);
	else if (route.mode == AK_MODE_RAIL) this.TearDownRail(route);
	if (AIGroup.IsValidGroup(route.group)) AIGroup.DeleteGroup(route.group);
}

/* A tile we built, and still own. */
function AllveiKonsern::IsOurs(tile)
{
	return AITile.GetOwner(tile) == AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
}

/* --------------------------------------------------------------- report */

function AllveiKonsern::YearlyReport()
{
	local year = AIDate.GetYear(AIDate.GetCurrentDate());
	if (year == this.last_report_year) return;
	if (this.last_report_year == 0) {
		this.last_report_year = year;
		return;
	}
	this.last_report_year = year;

	local per_mode = [[0, 0, 0], [0, 0, 0], [0, 0, 0], [0, 0, 0], [0, 0, 0]];   // routes, vehicles, profit
	foreach (route in this.routes) {
		if (route.dead) continue;
		local vehicles = this.RouteVehicles(route);
		local profit = 0;
		foreach (veh in vehicles) profit += AIVehicle.GetProfitLastYear(veh);
		per_mode[route.mode][0]++;
		per_mode[route.mode][1] += vehicles.len();
		per_mode[route.mode][2] += profit;
		AILog.Info("  " + AK_MODE_NAMES[route.mode] + " " + this.RouteName(route) + ": " + AICargo.GetCargoLabel(route.cargo) +
				", " + vehicles.len() + " kjøretøy, overskudd " + profit +
				", venter " + AIStation.GetCargoWaiting(AIStation.GetStationID(route.st_a), route.cargo) +
				", vurdering " + AIStation.GetCargoRating(AIStation.GetStationID(route.st_a), route.cargo) + "%");
	}
	local total = 0;
	local parts = "";
	for (local m = 0; m < per_mode.len(); m++) {
		total += per_mode[m][2];
		if (per_mode[m][0] == 0) continue;
		parts += " " + AK_MODE_NAMES[m] + ": " + per_mode[m][0] + " ruter/" + per_mode[m][1] + " kjt/" + per_mode[m][2] + ";";
	}
	AILog.Info("Årsrapport " + (year - 1) + ": " + this.LiveRouteCount() + " ruter, kjøretøyoverskudd " + total + "," + parts +
			" bank " + AICompany.GetBankBalance(AICompany.COMPANY_SELF) + ", lån " + AICompany.GetLoanAmount());
}

/* ---------------------------------------------------------------- events */

function AllveiKonsern::FindRouteOfVehicle(veh)
{
	if (!AIVehicle.IsValidVehicle(veh)) return null;
	local group = AIVehicle.GetGroupID(veh);
	foreach (route in this.routes) if (route.group == group) return route;
	return null;
}

function AllveiKonsern::HandleEvents()
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
			AILog.Warning("Et Allvei-kjøretøy har forulykket. Erstatning settes inn ved neste gjennomgang.");
		} else if (type == AIEvent.ET_VEHICLE_LOST) {
			local veh = AIEventVehicleLost.Convert(event).GetVehicleID();
			local route = this.FindRouteOfVehicle(veh);
			if (route != null && !route.dead) {
				route.lost++;
				AILog.Warning(AIVehicle.GetName(veh) + " finner ikke frem (" + this.RouteName(route) + ").");
				if (route.lost >= 3) this.CloseRoute(route, "kjøretøyene finner ikke frem");
			}
		} else if (type == AIEvent.ET_INDUSTRY_CLOSE) {
			local industry = AIEventIndustryClose.Convert(event).GetIndustryID();
			foreach (route in this.routes) {
				if ((!route.src_town && route.src == industry) || (!route.dst_town && route.dst == industry)) this.CloseRoute(route, "industrien stenger");
			}
		} else if (type == AIEvent.ET_COMPANY_IN_TROUBLE) {
			local company = AIEventCompanyInTrouble.Convert(event).GetCompanyID();
			if (AICompany.IsMine(company)) AILog.Warning("Allvei Konsern sliter økonomisk.");
		}
	}
}

/* ------------------------------------------------------------- save/load */

function AllveiKonsern::Save()
{
	/* Route tables only hold numbers, booleans, strings and arrays of tiles, which the save format accepts. */
	local selling = [];
	foreach (veh, dummy in this.to_sell) selling.push(veh);
	local failed = [];
	local today = AIDate.GetCurrentDate();
	foreach (key, date in this.failed) if (date > today) failed.push([key, date]);
	return { routes = this.routes, to_sell = selling, failed = failed, next_id = this.next_id,
			vehicle_counter = this.vehicle_counter, personality = this.personality == null ? -1 : this.personality };
}

function AllveiKonsern::Load(version, data)
{
	this.loaded_data = data;
}

function AllveiKonsern::RestoreState(data)
{
	if ("routes" in data) foreach (route in data.routes) this.routes.push(route);
	if ("to_sell" in data) foreach (veh in data.to_sell) if (AIVehicle.IsValidVehicle(veh)) this.to_sell[veh] <- true;
	if ("failed" in data) foreach (item in data.failed) this.failed[item[0]] <- item[1];
	if ("next_id" in data) this.next_id = data.next_id;
	if ("vehicle_counter" in data) this.vehicle_counter = data.vehicle_counter;
	if ("personality" in data && data.personality >= 0) this.personality = data.personality;
}
