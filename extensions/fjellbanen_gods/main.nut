/*
 * Fjellbanen Gods - a Modern Tycoon rail freight AI.
 *
 * Strategy: find a busy, poorly served freight industry and a customer
 * 40-120 tiles away (an industry that accepts the cargo, or a big town for
 * goods, food and water), and connect them with a double-track line:
 *
 *   platform 0 ═ s0 ═ f0 ╲╱ ═ n0 ── outbound track ──▶ other end
 *   platform 1 ═ s1 ═ f1 ╱╲ ═ n1 ◀── inbound track ───
 *
 * Each end is a two-platform terminus with a scissors crossover (f0/f1) and
 * two-way path signals at the platform exits (s0/s1). The two tracks are
 * found separately by the A* pathfinder (pathfinder.nut, with bridges and
 * tunnels) and carry one-way path signals, so trains never meet head on and
 * the line cannot deadlock. Trains are added while cargo piles up.
 *
 * Lines from version 1 (single track, one train) keep running as they are.
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
const MIN_PRODUCTION = 20;
const MAX_TRANSPORTED_PERCENT = 40;
const MIN_TOWN_POPULATION = 1000;
const MAX_STATION_TRIES = 40;
const MAX_TOWN_STATION_TRIES = 80;
const MAX_BUILD_TRIES = 3;
const DEPOT_SEARCH_TILES = 14;
const MAX_TRAINS_PER_LINE = 8;
const STUCK_REVIEWS = 12;
const LAYOUT_SINGLE = 1;   // Version 1 lines: one track, one train.
const LAYOUT_DOUBLE = 2;
const SAVE_FORMAT = 2;

function FG_Min(a, b) { return a < b ? a : b; }
function FG_Max(a, b) { return a > b ? a : b; }
function FG_Clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }

function FG_CarriesCargo(engine, cargo)
{
	return AIEngine.GetCargoType(engine) == cargo || AIEngine.CanRefitCargo(engine, cargo);
}

function FG_IsFreight(cargo)
{
	return !AICargo.HasCargoClass(cargo, AICargo.CC_PASSENGERS) && !AICargo.HasCargoClass(cargo, AICargo.CC_MAIL);
}

/* Goods, food and water are wanted by towns rather than by industries. */
function FG_IsTownCargo(cargo)
{
	local effect = AICargo.GetTownEffect(cargo);
	return effect == AICargo.TE_GOODS || effect == AICargo.TE_FOOD || effect == AICargo.TE_WATER;
}

/* Dry run of a rail station. Costs nothing. */
function FG_CanBuildStation(tile, track, platforms, length)
{
	local mode = AITestMode();
	return AIRail.BuildRailStation(tile, track, platforms, length, AIStation.STATION_NEW);
}

function FG_JumpTable(jumps)
{
	local table = {};
	foreach (j in jumps) table[j[0]] <- j;
	return table;
}

/* Build one bridge or tunnel; `jump` is [start_head, end_head, kind]. */
function FG_BuildJump(jump)
{
	if (jump[2] == MT_JUMP_TUNNEL) return AITunnel.BuildTunnel(AIVehicle.VT_RAIL, jump[0]);
	local type = MT_PickBridge(AIMap.DistanceManhattan(jump[0], jump[1]) + 1);   // Same choice as the pathfinder.
	return type != null && AIBridge.BuildBridge(AIVehicle.VT_RAIL, type, jump[0], jump[1]);
}

/* Lay the pieces of `full` (track between two already built ends). Returns -1 or the failing index. */
function FG_BuildTrack(full, jumps)
{
	local starts = FG_JumpTable(jumps);
	for (local i = 1; i < full.len() - 1; i++) {
		local tile = full[i];
		if (tile in starts) {
			if (!FG_BuildJump(starts[tile])) return i;
			i++;   // The far head is part of the bridge or tunnel.
			continue;
		}
		if (AIRail.BuildRail(full[i - 1], tile, full[i + 1])) continue;
		if (AIError.GetLastError() == AIError.ERR_ALREADY_BUILT) continue;
		return i;
	}
	return -1;
}

/* Pieces of a built track that do not join their neighbours (bridges and tunnels checked by their heads). */
function FG_VerifyTrack(full)
{
	local problems = 0;
	for (local i = 1; i < full.len() - 1; i++) {
		local tile = full[i];
		if (AIBridge.IsBridgeTile(tile) || AITunnel.IsTunnelTile(tile)) {
			local other = AIBridge.IsBridgeTile(tile) ? AIBridge.GetOtherBridgeEnd(tile) : AITunnel.GetOtherTunnelEnd(tile);
			if (full[i + 1] == other) i++;
			else if (full[i - 1] != other) problems++;
			continue;
		}
		if (AIRail.IsLevelCrossingTile(tile)) continue;
		if (!AIRail.AreTilesConnected(full[i - 1], tile, full[i + 1])) problems++;
	}
	return problems;
}

/* Undo FG_BuildTrack for pieces 1 .. upto - 1. */
function FG_RemoveTrack(full, jumps, upto)
{
	local starts = FG_JumpTable(jumps);
	for (local i = 1; i < upto && i < full.len() - 1; i++) {
		local tile = full[i];
		if (tile in starts) {
			AITile.DemolishTile(tile);
			i++;
			continue;
		}
		AIRail.RemoveRail(full[i - 1], tile, full[i + 1]);
	}
}

class FjellbanenGods extends AIController {
	TRAIN_NAMES = ["Dovregubben", "Rauma", "Hardangervidda", "Ofoten", "Femunden", "Jotunheimen",
			"Saltfjellet", "Rondane", "Finse", "Bergsfjord", "Myrdal", "Bjørnfjell"];

	routes = null;        // Array of route tables, see FinishLine() and RestoreState().
	to_sell = null;       // Table: vehicle id -> true, trains on their last trip to the depot.
	failed = null;        // Table: industry id or pair key -> date after which we may try again.
	watch = null;         // Table: vehicle id -> [tile, reviews standing still]. Not saved.
	lost = null;          // Table: vehicle id -> times reported lost. Not saved.
	pf = null;            // Pathfinder; also provides the direction offsets.
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
		this.watch = {};
		this.lost = {};
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

function FjellbanenGods::PairKey(source, dest, to_town)
{
	return (to_town ? 500000000 : 0) + 1000000 + source * 65536 + dest;
}

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

function FjellbanenGods::DestName(route)
{
	if (!route.dest_town) return this.IndustryName(route.dest);
	return AITown.IsValidTown(route.dest) ? AITown.GetName(route.dest) : ("by " + route.dest);
}

function FjellbanenGods::ShortName(name)
{
	return name.len() > 18 ? name.slice(0, 18) : name;
}

/* ---------------------------------------------------- choosing a new line */

/*
 * The best paying unserved freight source with a customer at a good distance.
 * Score = monthly production x income per unit for that distance. Sources we
 * already feed (a factory we deliver to) get a bonus: closing the chain means
 * the goods they make from our deliveries earn money too.
 */
function FjellbanenGods::PickIndustryPair()
{
	local used = {}, fed = {};
	foreach (route in this.routes) {
		if (route.dead) continue;
		used[route.source] <- true;
		if (!route.dest_town) fed[route.dest] <- true;
	}

	local towns = AITownList();
	towns.Valuate(AITown.GetPopulation);
	towns.KeepAboveValue(MIN_TOWN_POPULATION - 1);

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
			local bonus = (source in fed) ? 3 : 2;

			local candidates = [];
			if (FG_IsTownCargo(cargo)) {
				foreach (town, population in towns) {
					local dist = AITown.GetDistanceManhattanToTile(town, source_tile);
					if (dist >= MIN_DISTANCE && dist <= MAX_DISTANCE) candidates.push([town, dist, true]);
				}
			}
			local dests = AIIndustryList_CargoAccepting(cargo);
			dests.Valuate(AIIndustry.GetDistanceManhattanToTile, source_tile);
			dests.KeepBetweenValue(MIN_DISTANCE - 1, MAX_DISTANCE + 1);
			foreach (dest, dist in dests) {
				if (dest != source && !AIIndustry.IsBuiltOnWater(dest)) candidates.push([dest, dist, false]);
			}

			foreach (c in candidates) {
				if (this.IsBlocked(this.PairKey(source, c[0], c[2]))) continue;
				local income = AICargo.GetCargoIncome(cargo, c[1], c[1] / 3 + 4);
				local score = production * income * bonus;
				if (score > best_score) {
					best_score = score;
					best = { source = source, dest = c[0], to_town = c[2], cargo = cargo, dist = c[1], production = production,
							chain = (source in fed) };
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

/* ------------------------------------------------------------- stations */

function FjellbanenGods::IsClearFlat(tile)
{
	return this.pf.IsInsideMap(tile) && !(tile in this.pf.blocked) && AITile.IsBuildable(tile) &&
			!AITile.IsWaterTile(tile) && AITile.GetSlope(tile) == AITile.SLOPE_FLAT;
}

/*
 * Describe a two-platform terminus of `length` tiles whose north tile is
 * `top`, with its throat on the end that faces `toward`.
 * e = platform ends, s = signal tiles, f = crossover tiles, n = where the tracks start.
 * Returns null if it does not fit.
 */
function FjellbanenGods::DescribeTerminus(top, track, length, toward)
{
	local along = track == AIRail.RAILTRACK_NE_SW ? 0 : 2;
	local side = along == 0 ? 2 : 0;
	local ao = this.pf.Offset(along), so = this.pf.Offset(side);
	local far = top + ao * (length - 1);
	if (along == 0 && AIMap.GetTileX(far) - AIMap.GetTileX(top) != length - 1) return null;
	if (along == 2 && AIMap.GetTileY(far) - AIMap.GetTileY(top) != length - 1) return null;
	if (!this.pf.IsInsideMap(top + so) || !this.pf.IsInsideMap(far + so)) return null;

	local out = along, end = far;
	if (AIMap.DistanceManhattan(top - ao * 3, toward) < AIMap.DistanceManhattan(far + ao * 3, toward)) {
		out = along ^ 1;
		end = top;
	}
	local oo = this.pf.Offset(out);
	local e = [end, end + so];
	local s = [e[0] + oo, e[1] + oo];
	local f = [s[0] + oo, s[1] + oo];
	local n = [f[0] + oo, f[1] + oo];
	foreach (t in [s[0], s[1], f[0], f[1]]) if (!this.IsClearFlat(t)) return null;
	/* Both tracks leave straight, so the first tiles ahead of each throat must take track. */
	foreach (t in n) {
		for (local k = 0; k < 3; k++) if (this.pf.EnterCost(t + oo * k, out) < 0) return null;
	}

	return {
		top = top, corner = far + so, track = track, length = length, out_dir = out, e = e, s = s, f = f, n = n,
		w = along == 0 ? length : 2, h = along == 0 ? 2 : length
	};
}

function FjellbanenGods::TrySpots(tiles, cargo, accepting, toward, length, max_tries)
{
	local radius = AIStation.GetCoverageRadius(AIStation.STATION_TRAIN);
	local tries = 0;
	foreach (tile, dummy in tiles) {
		foreach (track in [AIRail.RAILTRACK_NE_SW, AIRail.RAILTRACK_NW_SE]) {
			local spot = this.DescribeTerminus(tile, track, length, toward);
			if (spot == null) continue;
			if (accepting && AITile.GetCargoAcceptance(tile, cargo, spot.w, spot.h, radius) < 8) continue;
			if (FG_CanBuildStation(tile, track, 2, length)) return spot;
		}
		if (++tries >= max_tries) break;
	}
	return null;
}

/* A terminus that serves the industry, with room for both tracks to leave toward `toward`. */
function FjellbanenGods::FindIndustrySpot(industry, producing, cargo, toward, length)
{
	local radius = AIStation.GetCoverageRadius(AIStation.STATION_TRAIN);
	local tiles = producing ? AITileList_IndustryProducing(industry, radius) : AITileList_IndustryAccepting(industry, radius);
	tiles.Valuate(AIMap.DistanceManhattan, toward);
	tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
	return this.TrySpots(tiles, cargo, !producing, toward, length, MAX_STATION_TRIES);
}

/* A terminus on the side of town that faces the source, where enough houses take the cargo. */
function FjellbanenGods::FindTownSpot(town, cargo, toward, length)
{
	local radius = AIStation.GetCoverageRadius(AIStation.STATION_TRAIN);
	local centre = AITown.GetLocation(town);
	local span = 8 + FG_Min(AITown.GetPopulation(town) / 500, 12);
	local cx = AIMap.GetTileX(centre), cy = AIMap.GetTileY(centre);
	local tiles = AITileList();
	tiles.AddRectangle(AIMap.GetTileIndex(FG_Clamp(cx - span, 1, AIMap.GetMapSizeX() - 2), FG_Clamp(cy - span, 1, AIMap.GetMapSizeY() - 2)),
			AIMap.GetTileIndex(FG_Clamp(cx + span, 1, AIMap.GetMapSizeX() - 2), FG_Clamp(cy + span, 1, AIMap.GetMapSizeY() - 2)));
	tiles.Valuate(AITile.IsBuildable);
	tiles.KeepValue(1);
	tiles.Valuate(AITile.GetCargoAcceptance, cargo, 1, 1, radius);
	tiles.KeepAboveValue(0);
	tiles.Valuate(AIMap.DistanceManhattan, toward);
	tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
	return this.TrySpots(tiles, cargo, true, toward, length, MAX_TOWN_STATION_TRIES);
}

function FjellbanenGods::SpotTiles(spot)
{
	local tiles = [spot.s[0], spot.s[1], spot.f[0], spot.f[1]];
	local along = spot.track == AIRail.RAILTRACK_NE_SW ? 0 : 2;
	local side = along == 0 ? 2 : 0;
	for (local i = 0; i < spot.length; i++) {
		local t = spot.top + this.pf.Offset(along) * i;
		tiles.push(t);
		tiles.push(t + this.pf.Offset(side));
	}
	return tiles;
}

/* Station, signal and crossover tiles are never used by a path. */
function FjellbanenGods::BlockSpot(spot)
{
	foreach (t in this.SpotTiles(spot)) this.pf.Block(t);
}

/* The pieces of a terminus throat: straight to each track start, plus a scissors crossover. */
function FjellbanenGods::ThroatPieces(spot)
{
	local e = spot.e, s = spot.s, f = spot.f, n = spot.n;
	return [
		[e[0], s[0], f[0]], [s[0], f[0], n[0]],
		[e[1], s[1], f[1]], [s[1], f[1], n[1]],
		[s[0], f[0], f[1]], [f[0], f[1], n[1]],
		[s[1], f[1], f[0]], [f[1], f[0], n[0]]
	];
}

function FjellbanenGods::BuildTerminus(spot)
{
	if (!AIRail.BuildRailStation(spot.top, spot.track, 2, spot.length, AIStation.STATION_NEW)) return false;
	foreach (p in this.ThroatPieces(spot)) {
		if (!AIRail.BuildRail(p[0], p[1], p[2]) && AIError.GetLastError() != AIError.ERR_ALREADY_BUILT) {
			AILog.Info("Sporveksel ved stasjonen ble ikke bygd: " + AIError.GetLastErrorString());
			this.RemoveTerminus(spot);
			return false;
		}
	}
	/*
	 * Platform exit signals: two-way path signals, so arriving trains pass them from behind.
	 * BuildSignal's `front` is the tile the trains come from (the signal faces them).
	 */
	AIRail.BuildSignal(spot.s[0], spot.e[0], AIRail.SIGNALTYPE_PBS);
	AIRail.BuildSignal(spot.s[1], spot.e[1], AIRail.SIGNALTYPE_PBS);
	return true;
}

function FjellbanenGods::RemoveTerminus(spot)
{
	foreach (t in [spot.s[0], spot.s[1], spot.f[0], spot.f[1]]) {
		if (AIRail.IsRailTile(t) && AITile.GetOwner(t) == AICompany.ResolveCompanyID(AICompany.COMPANY_SELF)) AITile.DemolishTile(t);
	}
	AIRail.RemoveRailStationTileRectangle(spot.top, spot.corner, false);
}

/* -------------------------------------------------------- building a line */

/*
 * Find both tracks without building anything: outbound from A's n[0] to one
 * of B's throats, then inbound from B's other throat to A's n[1], avoiding
 * the outbound track. Tries both ways of pairing B's throats.
 */
function FjellbanenGods::PlanTracks(a, b, bad)
{
	foreach (j in [0, 1]) {
		this.pf = MT_RailPathfinder();
		this.BlockSpot(a);
		this.BlockSpot(b);
		foreach (t in bad) this.pf.Block(t);

		/* Keep the mouth of the other track free while the outbound one is found. */
		local mouths = this.Mouth(a, 1);
		mouths.extend(this.Mouth(b, 1 - j));
		foreach (t in mouths) this.pf.Block(t);
		local out = this.pf.FindPath(a.n[0], a.out_dir, b.f[j], b.out_dir ^ 1);
		local expansions = this.pf.expansions;
		if (out == null) continue;
		local out_jumps = this.pf.last_jumps;

		foreach (t in mouths) this.pf.Unblock(t);
		foreach (t in bad) this.pf.Block(t);
		foreach (t in out) this.pf.Block(t);
		local back = this.pf.FindPath(b.n[1 - j], b.out_dir, a.f[1], a.out_dir ^ 1);
		expansions += this.pf.expansions;
		if (back == null) continue;

		local full_out = [a.f[0]];
		full_out.extend(out);
		full_out.push(b.f[j]);
		local full_back = [b.f[1 - j]];
		full_back.extend(back);
		full_back.push(a.f[1]);
		return { j = j, out = out, back = back, full_out = full_out, full_back = full_back,
				out_jumps = out_jumps, back_jumps = this.pf.last_jumps, expansions = expansions };
	}
	return null;
}

/* The first tiles of track `i` of a terminus, straight out from its throat. */
function FjellbanenGods::Mouth(spot, i)
{
	local oo = this.pf.Offset(spot.out_dir);
	return [spot.n[i], spot.n[i] + oo, spot.n[i] + oo * 2];
}

/* Price of the whole line, measured with a dry run. */
function FjellbanenGods::TestCost(a, b, plan, railtype)
{
	local costs = AIAccounting();
	local mode = AITestMode();
	foreach (spot in [a, b]) {
		AIRail.BuildRailStation(spot.top, spot.track, 2, spot.length, AIStation.STATION_NEW);
		foreach (p in this.ThroatPieces(spot)) AIRail.BuildRail(p[0], p[1], p[2]);
	}
	FG_BuildTrack(plan.full_out, plan.out_jumps);
	FG_BuildTrack(plan.full_back, plan.back_jumps);
	local signals = (plan.out.len() + plan.back.len()) / FG_Max(4, a.length + 2) + 6;
	return costs.GetCosts() + signals * AIRail.GetBuildCost(railtype, AIRail.BT_SIGNAL);
}

function FjellbanenGods::TryBuildLine()
{
	local pick = this.PickIndustryPair();
	if (pick == null) {
		AILog.Info("Ingen ledig industri med kunde i passe avstand akkurat nå.");
		return false;
	}
	local pair_key = this.PairKey(pick.source, pick.dest, pick.to_town);
	local dest_name = pick.to_town ? AITown.GetName(pick.dest) : this.IndustryName(pick.dest);

	local kit = this.ChooseKit(pick.cargo, FG_Max(0, this.SpendableMoney() / 4));
	if (kit == null) {
		AILog.Info("Har ikke råd til lokomotiv og vogner for " + AICargo.GetCargoLabel(pick.cargo) + " ennå.");
		return false;
	}
	AIRail.SetCurrentRailType(kit.railtype);

	this.pf = MT_RailPathfinder();
	local length = this.traits.station_length;
	local source_tile = AIIndustry.GetLocation(pick.source);
	local dest_tile = pick.to_town ? AITown.GetLocation(pick.dest) : AIIndustry.GetLocation(pick.dest);

	local a = this.FindIndustrySpot(pick.source, true, pick.cargo, dest_tile, length);
	if (a == null) {
		AILog.Info("Ingen plass til stasjon ved " + this.IndustryName(pick.source) + ". Prøver igjen om et år.");
		this.Block(pick.source);
		return false;
	}
	this.BlockSpot(a);
	local b = pick.to_town ? this.FindTownSpot(pick.dest, pick.cargo, source_tile, length)
			: this.FindIndustrySpot(pick.dest, false, pick.cargo, source_tile, length);
	if (b == null) {
		AILog.Info("Ingen plass til stasjon ved " + dest_name + ".");
		this.Block(pair_key);
		return false;
	}

	local bad = [];
	local termini_built = false;
	for (local attempt = 0; attempt < MAX_BUILD_TRIES; attempt++) {
		local plan = this.PlanTracks(a, b, bad);
		if (plan == null) {
			AILog.Info("Fant ingen dobbeltspor-trasé fra " + this.IndustryName(pick.source) + " til " + dest_name + ".");
			break;
		}

		local train_cost = AIEngine.GetPrice(kit.loco) + AIEngine.GetPrice(kit.wagon) * length * 2;
		local cost = this.TestCost(a, b, plan, kit.railtype) + AIRail.GetBuildCost(kit.railtype, AIRail.BT_DEPOT) + 2 * train_cost;
		if (!termini_built && this.SpendableMoney() < cost) {
			AILog.Info("Linjen " + this.IndustryName(pick.source) + " - " + dest_name + " koster " + cost + ". Sparer litt først.");
			return false;
		}
		if (!this.EnsureCash(cost)) break;

		if (!termini_built) {
			if (!this.BuildTerminus(a)) break;
			if (!this.BuildTerminus(b)) {
				this.RemoveTerminus(a);
				break;
			}
			termini_built = true;
		}

		local failed_at = FG_BuildTrack(plan.full_out, plan.out_jumps);
		local failed_full = plan.full_out;
		local reason = AIError.GetLastErrorString(), error = AIError.GetLastError();
		if (failed_at < 0) {
			failed_at = FG_BuildTrack(plan.full_back, plan.back_jumps);
			failed_full = plan.full_back;
			if (failed_at < 0) return this.FinishLine(pick, kit, a, b, plan);
			reason = AIError.GetLastErrorString();
			error = AIError.GetLastError();
			FG_RemoveTrack(plan.full_back, plan.back_jumps, failed_at);
			FG_RemoveTrack(plan.full_out, plan.out_jumps, plan.full_out.len() - 1);
		} else {
			FG_RemoveTrack(plan.full_out, plan.out_jumps, failed_at);
		}

		if (error == AIError.ERR_NOT_ENOUGH_CASH) break;
		AILog.Info("Sporet kunne ikke legges (" + reason + "). Finner ny trasé.");
		bad.push(failed_full[failed_at]);
		/* A failed bridge or tunnel head: avoid the far head too. */
		if (failed_at + 1 < failed_full.len()) bad.push(failed_full[failed_at + 1]);
	}

	if (termini_built) {
		this.RemoveTerminus(a);
		this.RemoveTerminus(b);
	}
	this.Block(pair_key);
	return false;
}

/*
 * A depot beside a straight stretch, joined both ways. Tries the inbound track
 * from A outward first (trains leave toward A), then the outbound track.
 */
function FjellbanenGods::BuildDepot(plan, skip)
{
	foreach (pass in [0, 1]) {
		local full = pass == 0 ? plan.full_back : plan.full_out;
		local first = pass == 0 ? full.len() - 3 : 2;
		local step = pass == 0 ? -1 : 1;
		for (local i = first; i >= 2 && i <= full.len() - 3; i += step) {
			local depot = this.TryDepotAt(full, i, skip, pass == 0);
			if (depot != null) return depot;
		}
	}
	return null;
}

function FjellbanenGods::TryDepotAt(full, i, skip, toward_next_first)
{
	local tile = full[i];
	if ((tile in skip) || (full[i - 1] in skip) || (full[i + 1] in skip)) return null;
	/*
	 * The junction needs straight track on both sides: the depot curve plus a
	 * curve on the next tile would be a 90 degree bend, which trains refuse.
	 */
	local dir = this.pf.DirBetween(full[i - 1], tile);
	if (dir < 0 || dir != this.pf.DirBetween(tile, full[i + 1])) return null;
	if (dir != this.pf.DirBetween(full[i - 2], full[i - 1]) || dir != this.pf.DirBetween(full[i + 1], full[i + 2])) return null;
	if (!AIRail.IsRailTile(tile) || AIRail.IsLevelCrossingTile(tile) || AITile.GetSlope(tile) != AITile.SLOPE_FLAT) return null;

	local sides = dir / 2 == 0 ? [2, 3] : [0, 1];
	foreach (side in sides) {
		local depot = tile + this.pf.Offset(side);
		if (!this.IsClearFlat(depot)) continue;
		if (!AIRail.BuildRailDepot(depot, tile)) continue;
		local ahead = AIRail.BuildRail(depot, tile, full[i + 1]);
		local behind = AIRail.BuildRail(depot, tile, full[i - 1]);
		if (ahead && behind) return [depot, tile];
		if (ahead) AIRail.RemoveRail(depot, tile, full[i + 1]);
		if (behind) AIRail.RemoveRail(depot, tile, full[i - 1]);
		AITile.DemolishTile(depot);
	}
	return null;
}

/*
 * One-way path signals along a track (in travel order): an entry signal on the
 * last tile before the throat, and line signals every `spacing` tiles.
 * The first line signal is far enough out that a waiting train clears the crossover.
 */
function FjellbanenGods::PlaceSignals(full, spacing, skip)
{
	local count = 0;
	local ok = function(i) : (full, skip) {
		return !(full[i] in skip) && AIRail.IsRailTile(full[i]) && !AIRail.IsLevelCrossingTile(full[i]) &&
				AIMap.DistanceManhattan(full[i], full[i + 1]) == 1 && AIMap.DistanceManhattan(full[i - 1], full[i]) == 1;
	};

	/* BuildSignal's `front` is the tile trains come from: full[i - 1] in travel order. */
	local entry = full.len() - 2;
	while (entry > 1 && !ok(entry)) entry--;
	if (AIRail.BuildSignal(full[entry], full[entry - 1], AIRail.SIGNALTYPE_PBS_ONEWAY)) count++;

	for (local k = spacing + 1; k < entry - 3; k += spacing) {
		local i = k;
		while (i < entry - 3 && !ok(i)) i++;
		if (i >= entry - 3) break;
		if (AIRail.BuildSignal(full[i], full[i - 1], AIRail.SIGNALTYPE_PBS_ONEWAY)) count++;
		k = i;
	}
	return count;
}

function FjellbanenGods::FinishLine(pick, kit, a, b, plan)
{
	local heads = {};
	foreach (j in plan.out_jumps) { heads[j[0]] <- true; heads[j[1]] <- true; }
	foreach (j in plan.back_jumps) { heads[j[0]] <- true; heads[j[1]] <- true; }

	local tiles = [a.s[0], a.s[1], a.f[0], a.f[1], b.s[0], b.s[1], b.f[0], b.f[1]];
	tiles.extend(plan.out);
	tiles.extend(plan.back);

	/* Self-check: every piece must join its neighbours, or trains would get lost. */
	local broken = FG_VerifyTrack(plan.full_out) + FG_VerifyTrack(plan.full_back);
	if (broken > 0) AILog.Warning("Sporfeil: " + broken + " biter henger ikke sammen på linjen fra " + this.IndustryName(pick.source) + ".");
	local depot = this.BuildDepot(plan, heads);
	if (depot == null) {
		AILog.Warning("Fant ikke plass til lokstall. Linjen rives.");
		this.TearDownTiles(tiles, a.top, a.corner, b.top, b.corner);
		this.Block(this.PairKey(pick.source, pick.dest, pick.to_town));
		return false;
	}
	tiles.push(depot[0]);

	local skip = clone heads;
	skip[depot[1]] <- true;
	local spacing = a.length + 2;
	local signals = this.PlaceSignals(plan.full_out, spacing, skip) + this.PlaceSignals(plan.full_back, spacing, skip);

	local bridges = 0, tunnels = 0;
	foreach (j in plan.out_jumps) if (j[2] == MT_JUMP_TUNNEL) tunnels++; else bridges++;
	foreach (j in plan.back_jumps) if (j[2] == MT_JUMP_TUNNEL) tunnels++; else bridges++;

	local max_trains = FG_Clamp(plan.out.len() / spacing, 2, MAX_TRAINS_PER_LINE);
	if (this.personality == MT_PERSONALITY_CAUTIOUS) max_trains = FG_Min(max_trains, 4);

	local route = {
		layout = LAYOUT_DOUBLE, source = pick.source, dest = pick.dest, dest_town = pick.to_town ? 1 : 0,
		cargo = pick.cargo, railtype = kit.railtype, length = a.length,
		top_a = a.top, corner_a = a.corner, order_a = a.e[0],
		top_b = b.top, corner_b = b.corner, order_b = b.e[0],
		tiles = tiles, depot = depot[0], trains = [], max_trains = max_trains,
		bridges = bridges, tunnels = tunnels, dead = 0
	};
	this.routes.push(route);
	AIBaseStation.SetName(AIStation.GetStationID(route.order_a), this.ShortName(this.IndustryName(pick.source)) + " godsterminal");
	AIBaseStation.SetName(AIStation.GetStationID(route.order_b), this.ShortName(this.DestName(route)) + " godsterminal");

	AILog.Info("Ny jernbane: " + this.IndustryName(pick.source) + " -> " + this.DestName(route) + " (" +
			AICargo.GetCargoLabel(pick.cargo) + (pick.to_town ? " til byen" : "") + (pick.chain ? ", verdikjede" : "") +
			", dobbeltspor " + plan.out.len() + "+" + plan.back.len() + " spor, " + signals + " signaler, " +
			bridges + " bruer, " + tunnels + " tunneler, opptil " + max_trains + " tog, " + plan.expansions + " ruter undersøkt)");

	/* A few trains to start with (setting start_trains); more come while cargo piles up. */
	local wanted = FG_Clamp(AIController.GetSetting("start_trains"), 1, route.max_trains);
	for (local n = 0; n < wanted; n++) {
		if (this.BuildTrain(route)) continue;
		AILog.Warning("Bare " + n + " tog ble kjøpt. Flere settes inn ved neste gjennomgang.");
		break;
	}
	return true;
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

	AIOrder.AppendOrder(train, route.order_a, AIOrder.OF_FULL_LOAD_ANY | AIOrder.OF_NON_STOP_INTERMEDIATE);
	AIOrder.AppendOrder(train, route.order_b, AIOrder.OF_NO_LOAD | AIOrder.OF_NON_STOP_INTERMEDIATE);
	this.NameTrain(train);
	AIVehicle.StartStopVehicle(train);
	route.trains.push(train);
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

function FjellbanenGods::IsLive(train)
{
	return AIVehicle.IsValidVehicle(train) && AIVehicle.GetState(train) != AIVehicle.VS_CRASHED;
}

/* Drop crashed or vanished trains from the route; returns the live ones. */
function FjellbanenGods::LiveTrains(route)
{
	local live = [];
	foreach (t in route.trains) if (this.IsLive(t)) live.push(t);
	route.trains = live;
	return live;
}

/*
 * Send a train to be sold. Returns true if it was newly retired.
 *
 * On double track a train cannot turn around except at the end of the line,
 * and the pathfinder does not plan through that dead end. So a train is only
 * retired while it loads at A or heads for B: its A order is replaced by a
 * stop at the line's own depot, which it then reaches on the normal loop
 * (B, then the inbound track). A train heading for A is retired next month.
 */
function FjellbanenGods::RetireTrain(route, train)
{
	if (train in this.to_sell) return false;
	if (route.layout != LAYOUT_DOUBLE) {
		if (!AIVehicle.SendVehicleToDepot(train)) return false;
		this.to_sell[train] <- true;
		return true;
	}

	local loading_at_a = AIVehicle.GetState(train) == AIVehicle.VS_AT_STATION &&
			AIStation.GetStationID(AIVehicle.GetLocation(train)) == AIStation.GetStationID(route.order_a);
	if (!loading_at_a && AIOrder.ResolveOrderPosition(train, AIOrder.ORDER_CURRENT) != 1) return false;
	if (AIOrder.GetOrderCount(train) != 2) return false;
	if (!AIOrder.AppendOrder(train, route.depot, AIOrder.OF_STOP_IN_DEPOT)) return false;
	if (!AIOrder.RemoveOrder(train, 0)) return false;   // Now: B, then the depot.
	this.to_sell[train] <- true;
	return true;
}

/* Stop a line: send its trains to be sold; track comes down once they are gone. */
function FjellbanenGods::CloseLine(route, reason)
{
	if (route.dead) return;
	route.dead = 1;
	AILog.Info("Linjen " + this.IndustryName(route.source) + " -> " + this.DestName(route) + " legges ned: " + reason + ".");
	foreach (t in this.LiveTrains(route)) this.RetireTrain(route, t);
}

function FjellbanenGods::TearDownTiles(tiles, top_a, corner_a, top_b, corner_b)
{
	local me = AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
	local sx = AIMap.GetMapSizeX();
	foreach (tile in tiles) {
		if (AITile.GetOwner(tile) != me) continue;
		if (AIRail.IsLevelCrossingTile(tile)) {
			local step = AIRail.GetRailTracks(tile) == AIRail.RAILTRACK_NE_SW ? 1 : sx;
			AIRail.RemoveRail(tile - step, tile, tile + step);
		} else if (AIRail.IsRailTile(tile) || AIRail.IsRailDepotTile(tile) || AIBridge.IsBridgeTile(tile) || AITunnel.IsTunnelTile(tile)) {
			AITile.DemolishTile(tile);
		}
	}
	AIRail.RemoveRailStationTileRectangle(top_a, corner_a, false);
	AIRail.RemoveRailStationTileRectangle(top_b, corner_b, false);
}

function FjellbanenGods::TearDown(route)
{
	this.TearDownTiles(route.tiles, route.top_a, route.corner_a, route.top_b, route.corner_b);
}

/* ---------------------------------------------------------------- review */

/* Trains that stand still outside stations and depots for a year are stuck. */
function FjellbanenGods::CheckStuck(route, trains)
{
	foreach (t in trains) {
		local loc = AIVehicle.GetLocation(t);
		local still = AIVehicle.GetState(t) == AIVehicle.VS_RUNNING && AIVehicle.GetCurrentSpeed(t) == 0 &&
				!AIRail.IsRailStationTile(loc) && !AIRail.IsRailDepotTile(loc);
		if (!still) {
			if (t in this.watch) delete this.watch[t];
			continue;
		}
		if ((t in this.watch) && this.watch[t][0] == loc) this.watch[t][1]++;
		else this.watch[t] <- [loc, 1];
		if (this.watch[t][1] == STUCK_REVIEWS) {
			AILog.Warning(AIVehicle.GetName(t) + " står fast på linjen fra " + this.IndustryName(route.source) + ". Snur toget.");
			AIVehicle.ReverseVehicle(t);
		}
	}
}

/* Trains loading at the source station right now. */
function FjellbanenGods::LoadingAtSource(route, trains)
{
	local station = AIStation.GetStationID(route.order_a);
	local count = 0;
	foreach (t in trains) {
		if (AIVehicle.GetState(t) != AIVehicle.VS_AT_STATION) continue;
		if (AIStation.GetStationID(AIVehicle.GetLocation(t)) == station) count++;
	}
	return count;
}

function FjellbanenGods::Review()
{
	for (local i = this.routes.len() - 1; i >= 0; i--) {
		local route = this.routes[i];
		local trains = this.LiveTrains(route);

		if (route.dead) {
			if (trains.len() > 0) {
				/* Still on their last trip; ask again if the first depot order did not stick. */
				foreach (t in trains) this.RetireTrain(route, t);
				continue;
			}
			this.TearDown(route);
			this.routes.remove(i);
			continue;
		}

		if (!AIIndustry.IsValidIndustry(route.source) || (!route.dest_town && !AIIndustry.IsValidIndustry(route.dest))) {
			this.CloseLine(route, "industrien er stengt");
			continue;
		}

		if (trains.len() == 0) {
			if (this.BuildTrain(route)) AILog.Info("Nytt tog satt inn på linjen fra " + this.IndustryName(route.source) + ".");
			continue;
		}

		this.CheckStuck(route, trains);

		/* Whole line loses money for a long time: close it. */
		local old_enough = true, profit_last = 0, profit_now = 0;
		foreach (t in trains) {
			if (AIVehicle.GetAge(t) < this.traits.retire_years * 365 + 365) old_enough = false;
			profit_last += AIVehicle.GetProfitLastYear(t);
			profit_now += AIVehicle.GetProfitThisYear(t);
		}
		if (old_enough && profit_last < 0 && profit_now < 0) {
			this.CloseLine(route, "den taper penger");
			continue;
		}

		if (route.layout != LAYOUT_DOUBLE) continue;   // Version 1 lines keep one train.

		local today = AIDate.GetCurrentDate();
		if (!("next_add" in route)) route.next_add <- 0;
		if (!("last_add" in route)) route.last_add <- 0;

		/* Extra trains that lose money go, as long as two remain and no train was added lately. */
		if (trains.len() > 2 && today - route.last_add > 365) {
			foreach (t in trains) {
				if (t in this.to_sell) continue;
				if (AIVehicle.GetAge(t) < this.traits.retire_years * 365 + 365) continue;
				if (AIVehicle.GetProfitLastYear(t) >= 0 || AIVehicle.GetProfitThisYear(t) >= 0) continue;
				if (!this.RetireTrain(route, t)) continue;
				AILog.Info(AIVehicle.GetName(t) + " tjener ikke nok og pensjoneres.");
				route.next_add = today + 365;   // The line has too many trains: no new ones for a year.
				break;
			}
		}

		/* More cargo than the trains take away: add one, unless both platforms are busy loading. */
		local active = 0, capacity = 0;
		foreach (t in trains) {
			if (t in this.to_sell) continue;
			active++;
			capacity = FG_Max(capacity, AIVehicle.GetCapacity(t, route.cargo));
		}
		local waiting = AIStation.GetCargoWaiting(AIStation.GetStationID(route.order_a), route.cargo);
		local loading = this.LoadingAtSource(route, trains);
		local piling_up = waiting * 10 > capacity * this.traits.growth_x10 && loading < 2;
		local nobody_loading = loading == 0 && waiting * 2 > capacity;
		local may_grow = today >= route.next_add && active < route.max_trains && capacity > 0 && (piling_up || nobody_loading);
		if (active < 2 || may_grow) {
			if (this.BuildTrain(route)) {
				route.last_add = today;
				route.next_add = today + 90;
				AILog.Info("Mye gods venter ved " + this.IndustryName(route.source) + ". Tog nummer " + (active + 1) + " satt inn.");
			}
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
		local live = this.LiveTrains(route);
		foreach (t in live) line_profit += AIVehicle.GetProfitLastYear(t);
		trains += live.len();
		profit += line_profit;
		AILog.Info("  " + this.IndustryName(route.source) + " -> " + this.DestName(route) + ": " +
				AICargo.GetCargoLabel(route.cargo) + ", " + live.len() + " tog, overskudd " + line_profit +
				", venter " + AIStation.GetCargoWaiting(AIStation.GetStationID(route.order_a), route.cargo) +
				(route.layout == LAYOUT_DOUBLE ? "" : " (enkeltspor)"));
	}
	AILog.Info("Årsrapport " + (year - 1) + ": " + this.LiveRouteCount() + " jernbaner, " + trains + " tog, togoverskudd " +
			profit + ", bank " + AICompany.GetBankBalance(AICompany.COMPANY_SELF) + ", lån " + AICompany.GetLoanAmount());
}

/* ---------------------------------------------------------------- events */

function FjellbanenGods::RouteOfTrain(veh)
{
	foreach (route in this.routes) {
		foreach (t in route.trains) if (t == veh) return route;
	}
	return null;
}

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
			local route = this.RouteOfTrain(veh);
			if (route != null && !route.dead) {
				this.lost[veh] <- ((veh in this.lost) ? this.lost[veh] : 0) + 1;
				AILog.Warning(AIVehicle.GetName(veh) + " finner ikke frem.");
				if (this.lost[veh] >= 2) this.CloseLine(route, "toget finner ikke frem");
			}
		} else if (type == AIEvent.ET_INDUSTRY_CLOSE) {
			local industry = AIEventIndustryClose.Convert(event).GetIndustryID();
			foreach (route in this.routes) {
				if (route.source == industry || (!route.dest_town && route.dest == industry)) this.CloseLine(route, "industrien stenger");
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
		saved.push({
			layout = r.layout, source = r.source, dest = r.dest, dest_town = r.dest_town, cargo = r.cargo,
			railtype = r.railtype, length = r.length,
			top_a = r.top_a, corner_a = r.corner_a, order_a = r.order_a,
			top_b = r.top_b, corner_b = r.corner_b, order_b = r.order_b,
			tiles = r.tiles, depot = r.depot, trains = r.trains, max_trains = r.max_trains,
			bridges = r.bridges, tunnels = r.tunnels, dead = r.dead,
			next_add = ("next_add" in r) ? r.next_add : 0, last_add = ("last_add" in r) ? r.last_add : 0
		});
	}
	local selling = [];
	foreach (veh, dummy in this.to_sell) selling.push(veh);
	return { format = SAVE_FORMAT, routes = saved, to_sell = selling, train_counter = this.train_counter,
			personality = this.personality == null ? -1 : this.personality };
}

function FjellbanenGods::Load(version, data)
{
	this.loaded_data = data;
}

/* A version 1 line was saved as an array: single track, one train, path between the station ends. */
function FjellbanenGods::RouteFromV1(r)
{
	local tiles = [];
	tiles.extend(r[11]);
	tiles.push(r[12]);
	local train = r[15];
	return {
		layout = LAYOUT_SINGLE, source = r[0], dest = r[1], dest_town = 0, cargo = r[2], railtype = r[3], length = r[4],
		top_a = r[5], corner_a = r[6], order_a = r[7], top_b = r[8], corner_b = r[9], order_b = r[10],
		tiles = tiles, depot = r[12], trains = (train >= 0 && AIVehicle.IsValidVehicle(train)) ? [train] : [],
		max_trains = 1, bridges = 0, tunnels = 0, dead = r[16] != 0 ? 1 : 0
	};
}

function FjellbanenGods::RestoreState(data)
{
	if ("routes" in data) {
		foreach (r in data.routes) {
			if (typeof r == "array") {
				this.routes.push(this.RouteFromV1(r));
				continue;
			}
			local route = clone r;
			local live = [];
			foreach (t in route.trains) if (AIVehicle.IsValidVehicle(t)) live.push(t);
			route.trains = live;
			this.routes.push(route);
		}
	}
	if ("to_sell" in data) {
		foreach (veh in data.to_sell) if (AIVehicle.IsValidVehicle(veh)) this.to_sell[veh] <- true;
	}
	if ("train_counter" in data) this.train_counter = data.train_counter;
	if ("personality" in data && data.personality >= 0) this.personality = data.personality;
	this.pf = MT_RailPathfinder();
}
