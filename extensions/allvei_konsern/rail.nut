/*
 * Allvei Konsern - freight trains: two terminus stations facing each other,
 * track from the shared A* rail pathfinder (pathfinder.nut), a depot near the
 * source and one full-load train sized to the platform. Ported from
 * Fjellbanen Gods.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

const AK_RAIL_BUILD_TRIES = 3;
const AK_RAIL_STATION_TRIES = 40;
const AK_RAIL_DEPOT_SEARCH = 12;

function AK_CanBuildRailStation(tile, track, length)
{
	local mode = AITestMode();
	return AIRail.BuildRailStation(tile, track, 1, length, AIStation.STATION_NEW);
}

function AK_TestRailCost(spot_a, spot_b, full)
{
	local costs = AIAccounting();
	local mode = AITestMode();
	AIRail.BuildRailStation(spot_a.top, spot_a.track, 1, spot_a.length, AIStation.STATION_NEW);
	AIRail.BuildRailStation(spot_b.top, spot_b.track, 1, spot_b.length, AIStation.STATION_NEW);
	for (local i = 1; i < full.len() - 1; i++) AIRail.BuildRail(full[i - 1], full[i], full[i + 1]);
	return costs.GetCosts();
}

function AllveiKonsern::PickLoco(railtype, budget)
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
	engines.KeepBelowValue(1);
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

function AllveiKonsern::PickWagon(railtype, cargo)
{
	local engines = AIEngineList(AIVehicle.VT_RAIL);
	engines.Valuate(AIEngine.IsBuildable);
	engines.KeepValue(1);
	engines.Valuate(AIEngine.IsWagon);
	engines.KeepValue(1);
	engines.Valuate(AIEngine.CanRunOnRail, railtype);
	engines.KeepValue(1);
	engines.Valuate(AK_CarriesCargo, cargo);
	engines.KeepValue(1);
	local best = null, best_score = -1;
	foreach (engine, dummy in engines) {
		local speed = AIEngine.GetMaxSpeed(engine);
		local score = AIEngine.GetCapacity(engine) * 1000 + (speed <= 0 ? 999 : AK_Min(speed, 999));
		if (score > best_score) {
			best_score = score;
			best = engine;
		}
	}
	return best;
}

/* Rail type, locomotive and wagon for the best train for this cargo; cached per planning round. */
function AllveiKonsern::RailKit(cargo)
{
	local key = "k" + cargo;
	if (key in this.cache) return this.cache[key];
	local best = null;
	foreach (railtype, dummy in AIRailTypeList()) {
		if (!AIRail.IsRailTypeAvailable(railtype)) continue;
		local loco = this.PickLoco(railtype, null);
		local wagon = this.PickWagon(railtype, cargo);
		if (loco == null || wagon == null) continue;
		local score = AIEngine.GetMaxSpeed(loco) * AIEngine.GetPower(loco);
		if (best == null || score > best.score) best = { railtype = railtype, loco = loco, wagon = wagon, score = score };
	}
	this.cache[key] <- best;
	return best;
}

function AllveiKonsern::DescribeRailStation(top, track, length, toward)
{
	local pf = this.rail_pf;
	local along = track == AIRail.RAILTRACK_NE_SW ? 0 : 2;
	local far = top + pf.Offset(along) * (length - 1);
	if (along == 0 && AIMap.GetTileX(far) - AIMap.GetTileX(top) != length - 1) return null;
	if (along == 2 && AIMap.GetTileY(far) - AIMap.GetTileY(top) != length - 1) return null;

	local front_top = top + pf.Offset(along ^ 1);
	local front_far = far + pf.Offset(along);
	local spot = { top = top, far = far, track = track, length = length, end = far, front = front_far, out_dir = along };
	if (AIMap.DistanceManhattan(front_top, toward) < AIMap.DistanceManhattan(front_far, toward)) {
		spot.end = top;
		spot.front = front_top;
		spot.out_dir = along ^ 1;
	}
	if (!pf.IsInsideMap(spot.front) || pf.EnterCost(spot.front, spot.out_dir) < 0) return null;
	spot.w <- along == 0 ? length : 1;
	spot.h <- along == 0 ? 1 : length;
	return spot;
}

function AllveiKonsern::FindRailStationSpot(industry, producing, cargo, toward, length)
{
	local radius = AIStation.GetCoverageRadius(AIStation.STATION_TRAIN);
	local tiles = producing ? AITileList_IndustryProducing(industry, radius) : AITileList_IndustryAccepting(industry, radius);
	tiles.Valuate(AIMap.DistanceManhattan, toward);
	tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
	local tries = 0;
	foreach (tile, dummy in tiles) {
		foreach (track in [AIRail.RAILTRACK_NE_SW, AIRail.RAILTRACK_NW_SE]) {
			local spot = this.DescribeRailStation(tile, track, length, toward);
			if (spot == null) continue;
			if (!producing && AITile.GetCargoAcceptance(tile, cargo, spot.w, spot.h, radius) < 8) continue;
			if (AK_CanBuildRailStation(tile, track, length)) return spot;
		}
		if (++tries >= AK_RAIL_STATION_TRIES) break;
	}
	return null;
}

function AllveiKonsern::BlockRailStation(spot)
{
	local along = spot.track == AIRail.RAILTRACK_NE_SW ? 0 : 2;
	for (local i = 0; i < spot.length; i++) this.rail_pf.Block(spot.top + this.rail_pf.Offset(along) * i);
}

function AllveiKonsern::BuildRailRoute(p)
{
	local kit = this.RailKit(p.cargo);
	if (kit == null) return false;
	AIRail.SetCurrentRailType(kit.railtype);
	this.rail_pf = MT_RailPathfinder();
	local length = this.traits.station_length;
	local src_tile = AIIndustry.GetLocation(p.src), dst_tile = AIIndustry.GetLocation(p.dst);

	local spot_a = this.FindRailStationSpot(p.src, true, p.cargo, dst_tile, length);
	if (spot_a == null) {
		AILog.Info("Ingen plass til jernbanestasjon ved " + this.PlaceName(p.src, false) + ".");
		return false;
	}
	local spot_b = this.FindRailStationSpot(p.dst, false, p.cargo, src_tile, length);
	if (spot_b == null) {
		AILog.Info("Ingen plass til jernbanestasjon ved " + this.PlaceName(p.dst, false) + ".");
		return false;
	}
	this.BlockRailStation(spot_a);
	this.BlockRailStation(spot_b);

	local stations_built = false;
	for (local attempt = 0; attempt < AK_RAIL_BUILD_TRIES; attempt++) {
		local path = this.rail_pf.FindPath(spot_a.front, spot_a.out_dir, spot_b.end, spot_b.out_dir ^ 1);
		if (path == null) {
			AILog.Info("Fant ingen jernbanetrasé (" + this.rail_pf.expansions + " ruter undersøkt).");
			break;
		}
		local full = [spot_a.end];
		full.extend(path);
		full.push(spot_b.end);

		local cost = AK_TestRailCost(spot_a, spot_b, full) + AIRail.GetBuildCost(kit.railtype, AIRail.BT_DEPOT) +
				AIEngine.GetPrice(kit.loco) + AIEngine.GetPrice(kit.wagon) * length * 2;
		if (!stations_built && this.SpendableMoney() < cost) {
			AILog.Info("Jernbanen koster " + cost + ". Sparer først.");
			break;
		}
		if (!this.EnsureCash(cost)) break;

		if (!stations_built) {
			if (!AIRail.BuildRailStation(spot_a.top, spot_a.track, 1, spot_a.length, AIStation.STATION_NEW)) return false;
			if (!AIRail.BuildRailStation(spot_b.top, spot_b.track, 1, spot_b.length, AIStation.STATION_NEW)) {
				AIRail.RemoveRailStationTileRectangle(spot_a.top, spot_a.far, false);
				return false;
			}
			stations_built = true;
		}

		local failed_at = this.BuildTrack(full);
		if (failed_at < 0) return this.FinishRailRoute(p, kit, spot_a, spot_b, path, full);

		local reason = AIError.GetLastErrorString();
		local err = AIError.GetLastError();
		this.RemoveTrack(full, failed_at);
		if (err == AIError.ERR_NOT_ENOUGH_CASH) break;
		AILog.Info("Sporet kunne ikke legges (" + reason + "). Finner ny trasé.");
		this.rail_pf.Block(full[failed_at]);
	}
	if (stations_built) {
		AIRail.RemoveRailStationTileRectangle(spot_a.top, spot_a.far, false);
		AIRail.RemoveRailStationTileRectangle(spot_b.top, spot_b.far, false);
	}
	return false;
}

function AllveiKonsern::BuildTrack(full)
{
	for (local i = 1; i < full.len() - 1; i++) {
		if (AIRail.BuildRail(full[i - 1], full[i], full[i + 1])) continue;
		if (AIError.GetLastError() == AIError.ERR_ALREADY_BUILT) continue;
		return i;
	}
	return -1;
}

function AllveiKonsern::RemoveTrack(full, upto)
{
	for (local i = 1; i < upto && i < full.len() - 1; i++) AIRail.RemoveRail(full[i - 1], full[i], full[i + 1]);
}

function AllveiKonsern::BuildRailDepotNear(path)
{
	local pf = this.rail_pf;
	local last = AK_Min(AK_RAIL_DEPOT_SEARCH, path.len() - 2);
	for (local i = 1; i <= last; i++) {
		local tile = path[i];
		local dir = pf.DirBetween(path[i - 1], tile);
		if (dir != pf.DirBetween(tile, path[i + 1])) continue;
		if (AITile.GetSlope(tile) != AITile.SLOPE_FLAT || AIRoad.IsRoadTile(tile)) continue;
		local sides = dir / 2 == 0 ? [2, 3] : [0, 1];
		foreach (side in sides) {
			local depot = tile + pf.Offset(side);
			if (!AITile.IsBuildable(depot) || AITile.GetSlope(depot) != AITile.SLOPE_FLAT) continue;
			if (!AIRail.BuildRailDepot(depot, tile)) continue;
			if (AIRail.BuildRail(depot, tile, path[i - 1])) return [depot, tile, path[i - 1]];
			AITile.DemolishTile(depot);
		}
	}
	return null;
}

function AllveiKonsern::FinishRailRoute(p, kit, spot_a, spot_b, path, full)
{
	local depot = this.BuildRailDepotNear(path);
	if (depot == null) {
		AILog.Warning("Fant ikke plass til lokstall. Linjen rives.");
		this.RemoveTrack(full, full.len() - 1);
		AIRail.RemoveRailStationTileRectangle(spot_a.top, spot_a.far, false);
		AIRail.RemoveRailStationTileRectangle(spot_b.top, spot_b.far, false);
		return false;
	}
	local route = this.AddRoute({ mode = AK_MODE_RAIL, cargo = p.cargo, src = p.src, dst = p.dst, src_town = false, dst_town = false,
			dist = p.dist, st_a = spot_a.end, st_b = spot_b.end, depot = depot[0],
			railtype = kit.railtype, length = spot_a.length,
			top_a = spot_a.top, far_a = spot_a.far, top_b = spot_b.top, far_b = spot_b.far,
			path = path, depot_on = depot[1], depot_toward = depot[2] });
	this.NameStation(route.st_a, this.PlaceName(p.src, false), AK_MODE_RAIL);
	this.NameStation(route.st_b, this.PlaceName(p.dst, false), AK_MODE_RAIL);
	if (!this.BuildTrain(route)) AILog.Warning("Toget ble ikke kjøpt ennå. Prøver igjen ved neste gjennomgang.");
	return true;
}

function AllveiKonsern::BuildTrain(route)
{
	AIRail.SetCurrentRailType(route.railtype);
	local loco = this.PickLoco(route.railtype, AK_Max(0, this.SpendableMoney()));
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
	if (AIGroup.IsValidGroup(route.group)) AIGroup.MoveVehicle(route.group, train);
	AIVehicle.SetName(train, "Allvei tog " + (++this.vehicle_counter));
	AIOrder.AppendOrder(train, route.st_a, AIOrder.OF_FULL_LOAD_ANY | AIOrder.OF_NON_STOP_INTERMEDIATE);
	AIOrder.AppendOrder(train, route.st_b, AIOrder.OF_NO_LOAD | AIOrder.OF_NON_STOP_INTERMEDIATE);
	AIVehicle.StartStopVehicle(train);
	return true;
}

function AllveiKonsern::TearDownRail(route)
{
	local full = [route.st_a];
	full.extend(route.path);
	full.push(route.st_b);
	AIRail.RemoveRail(route.depot, route.depot_on, route.depot_toward);
	AITile.DemolishTile(route.depot);
	this.RemoveTrack(full, full.len() - 1);
	AIRail.RemoveRailStationTileRectangle(route.top_a, route.far_a, false);
	AIRail.RemoveRailStationTileRectangle(route.top_b, route.far_b, false);
}
