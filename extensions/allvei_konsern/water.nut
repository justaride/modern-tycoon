/*
 * Allvei Konsern - ships: docks (or an oil rig's own dock), a water depot,
 * a check that both docks share the same water, and full-load cargo ships.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

const AK_WATER_SEARCH_BUDGET = 60000;

function AK_CanBuildDock(tile)
{
	local mode = AITestMode();
	return AIMarine.BuildDock(tile, AIStation.STATION_NEW);
}

function AK_CanBuildWaterDepot(tile, front)
{
	local mode = AITestMode();
	return AIMarine.BuildWaterDepot(tile, front);
}

/*
 * The water tile a dock on `tile` would stand in, or -1. Same rule as the game:
 * a land tile with a gentle slope, whose two tiles downhill are flat water.
 */
function AK_DockWaterTile(tile)
{
	local slope = AITile.GetSlope(tile);
	local sx = AIMap.GetMapSizeX();
	local step = 0;
	if (slope == AITile.SLOPE_NE) step = 1;          // Uphill is north-east, so the water lies south-west (+x).
	else if (slope == AITile.SLOPE_SW) step = -1;
	else if (slope == AITile.SLOPE_NW) step = sx;    // Uphill is north-west, so the water lies south-east (+y).
	else if (slope == AITile.SLOPE_SE) step = -sx;
	if (step == 0 || AITile.IsWaterTile(tile) || AITile.IsCoastTile(tile)) return -1;
	local first = tile + step, second = tile + 2 * step;
	if (!AIMap.IsValidTile(second)) return -1;
	foreach (t in [first, second]) {
		if (!AITile.IsWaterTile(t) || AITile.GetSlope(t) != AITile.SLOPE_FLAT) return -1;
	}
	return first;
}

function AK_IsDockSlope(tile) { return AK_DockWaterTile(tile) >= 0; }

/* An industry is coastal when it has its own dock or water within dock reach. Cached per planning round. */
function AllveiKonsern::IsCoastal(industry)
{
	local key = "c" + industry;
	if (key in this.cache) return this.cache[key];
	local result = AIIndustry.HasDock(industry);
	if (!result) {
		local tiles = AITileList_IndustryProducing(industry, AIStation.GetCoverageRadius(AIStation.STATION_DOCK));
		if (tiles.IsEmpty()) tiles = AITileList_IndustryAccepting(industry, AIStation.GetCoverageRadius(AIStation.STATION_DOCK));
		tiles.Valuate(AITile.IsWaterTile);
		tiles.KeepValue(1);
		result = !tiles.IsEmpty();
	}
	this.cache[key] <- result;
	return result;
}

/* Returns { tile, own } for a dock serving the industry, or null. Does not build. */
function AllveiKonsern::FindDockSpot(industry, producing, cargo, toward)
{
	if (AIIndustry.HasDock(industry)) return { tile = AIIndustry.GetDockLocation(industry), own = false };
	local radius = AIStation.GetCoverageRadius(AIStation.STATION_DOCK);
	local tiles = producing ? AITileList_IndustryProducing(industry, radius) : AITileList_IndustryAccepting(industry, radius);
	/* A dock stands on a gently sloped tile at the water's edge. */
	tiles.Valuate(AK_IsDockSlope);
	tiles.KeepValue(1);
	if (!producing) {
		tiles.Valuate(AITile.GetCargoAcceptance, cargo, 1, 1, radius);
		tiles.KeepAboveValue(7);
	}
	tiles.Valuate(AIMap.DistanceManhattan, toward);
	tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
	local tries = 0;
	foreach (tile, dummy in tiles) {
		if (++tries > 40) break;
		if (AK_CanBuildDock(tile)) return { tile = tile, own = true };
	}
	return null;
}

/* Water tiles next to a dock (or within two tiles of it), where ships can arrive. */
function AllveiKonsern::WaterAround(tile)
{
	local result = [];
	local x = AIMap.GetTileX(tile), y = AIMap.GetTileY(tile);
	for (local dx = -2; dx <= 2; dx++) {
		for (local dy = -2; dy <= 2; dy++) {
			local t = AK_Tile(x + dx, y + dy);
			if (AITile.IsWaterTile(t)) result.push(t);
		}
	}
	return result;
}

/* Breadth-first search over water: can a ship sail from one dock to the other? */
function AllveiKonsern::WaterConnected(a, b)
{
	local goal = {};
	foreach (t in this.WaterAround(b)) goal[t] <- true;
	if (goal.len() == 0) return false;

	local sx = AIMap.GetMapSizeX();
	local offsets = [1, -1, sx, -sx];
	local seen = {};
	local queue = [];
	foreach (t in this.WaterAround(a)) {
		if (t in goal) return true;
		seen[t] <- true;
		queue.push(t);
	}
	local head = 0;
	while (head < queue.len() && head < AK_WATER_SEARCH_BUDGET) {
		local tile = queue[head++];
		foreach (off in offsets) {
			local next = tile + off;
			if (next in seen) continue;
			seen[next] <- true;
			if (!AITile.IsWaterTile(next) && !AIMarine.IsLockTile(next) && !AIMarine.IsDockTile(next)) continue;
			if (next in goal) return true;
			queue.push(next);
		}
	}
	return false;
}

/* A water depot near the dock. Returns its tile or null. */
function AllveiKonsern::BuildWaterDepotNear(dock)
{
	local sx = AIMap.GetMapSizeX();
	local offsets = [1, -1, sx, -sx];
	local x = AIMap.GetTileX(dock), y = AIMap.GetTileY(dock);
	for (local r = 2; r <= 7; r++) {
		for (local dx = -r; dx <= r; dx++) {
			for (local dy = -r; dy <= r; dy++) {
				if (AK_Max(AK_Abs(dx), AK_Abs(dy)) != r) continue;
				local tile = AK_Tile(x + dx, y + dy);
				if (!AITile.IsWaterTile(tile)) continue;
				foreach (off in offsets) {
					local front = tile + off;
					if (!AITile.IsWaterTile(front)) continue;
					if (!AK_CanBuildWaterDepot(tile, front)) continue;
					if (AIMarine.BuildWaterDepot(tile, front)) return tile;
				}
			}
		}
	}
	return null;
}

function AllveiKonsern::BuildWaterRoute(p)
{
	local src_tile = AIIndustry.GetLocation(p.src), dst_tile = AIIndustry.GetLocation(p.dst);
	local dock_a = this.FindDockSpot(p.src, true, p.cargo, dst_tile);
	if (dock_a == null) {
		AILog.Info("Ingen plass til kai ved " + this.PlaceName(p.src, false) + ".");
		return false;
	}
	local dock_b = this.FindDockSpot(p.dst, false, p.cargo, src_tile);
	if (dock_b == null) {
		AILog.Info("Ingen plass til kai ved " + this.PlaceName(p.dst, false) + ".");
		return false;
	}
	local engine = this.BestEngine(AIVehicle.VT_WATER, p.cargo);
	if (engine == null) return false;
	local cost = 2 * AIMarine.GetBuildCost(AIMarine.BT_DOCK) + AIMarine.GetBuildCost(AIMarine.BT_DEPOT) + AIEngine.GetPrice(engine);
	if (!this.EnsureCash(cost)) return false;

	/* Water check uses the land tile before the dock exists; WaterAround looks two tiles out. */
	if (!this.WaterConnected(dock_a.tile, dock_b.tile)) {
		AILog.Info("Kaiene ligger ikke ved samme vann.");
		return false;
	}

	if (dock_a.own && !AIMarine.BuildDock(dock_a.tile, AIStation.STATION_NEW)) return false;
	if (dock_b.own && !AIMarine.BuildDock(dock_b.tile, AIStation.STATION_NEW)) {
		if (dock_a.own) AIMarine.RemoveDock(dock_a.tile);
		return false;
	}

	local depot = this.BuildWaterDepotNear(dock_a.tile);
	if (depot == null) depot = this.BuildWaterDepotNear(dock_b.tile);
	if (depot == null) {
		AILog.Info("Fant ikke plass til verft.");
		if (dock_a.own) AIMarine.RemoveDock(dock_a.tile);
		if (dock_b.own) AIMarine.RemoveDock(dock_b.tile);
		return false;
	}

	local route = this.AddRoute({ mode = AK_MODE_WATER, cargo = p.cargo, src = p.src, dst = p.dst, src_town = false, dst_town = false,
			dist = p.dist, st_a = dock_a.tile, st_b = dock_b.tile, depot = depot, own_a = dock_a.own, own_b = dock_b.own });
	if (dock_a.own) this.NameStation(route.st_a, this.PlaceName(p.src, false), AK_MODE_WATER);
	if (dock_b.own) this.NameStation(route.st_b, this.PlaceName(p.dst, false), AK_MODE_WATER);

	local first = AK_Clamp(p.vehicles, 1, 2);
	for (local i = 0; i < first; i++) if (!this.AddShip(route, i)) break;
	return true;
}

function AllveiKonsern::AddShip(route, count)
{
	local engine = this.BestEngine(AIVehicle.VT_WATER, route.cargo);
	local veh = this.BuyVehicle(route, route.depot, engine);
	if (veh == null) return false;
	AIOrder.AppendOrder(veh, route.st_a, AIOrder.OF_FULL_LOAD_ANY);
	AIOrder.AppendOrder(veh, route.st_b, AIOrder.OF_NO_LOAD);
	AIVehicle.StartStopVehicle(veh);
	return true;
}

function AllveiKonsern::TearDownWater(route)
{
	if (route.own_a && AIMarine.IsDockTile(route.st_a) && this.IsOurs(route.st_a)) AIMarine.RemoveDock(route.st_a);
	if (route.own_b && AIMarine.IsDockTile(route.st_b) && this.IsOurs(route.st_b)) AIMarine.RemoveDock(route.st_b);
	if (AIMarine.IsWaterDepotTile(route.depot) && this.IsOurs(route.depot)) AIMarine.RemoveWaterDepot(route.depot);
}
