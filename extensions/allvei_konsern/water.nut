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
 * a land or shore tile with a gentle slope, whose two tiles downhill are flat water.
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
	/* A sloped shore (coast) tile is fine; it is where docks usually go. */
	if (step == 0 || AITile.IsWaterTile(tile)) return -1;
	local first = tile + step, second = tile + 2 * step;
	if (!AIMap.IsValidTile(second)) return -1;
	foreach (t in [first, second]) {
		if (!AITile.IsWaterTile(t) || AITile.GetSlope(t) != AITile.SLOPE_FLAT) return -1;
	}
	return first;
}

function AK_IsDockSlope(tile) { return AK_DockWaterTile(tile) >= 0; }

/*
 * Shoreline sides: [step to the water, high corners, low corners]. A dock slope is
 * high on the land side and level with the water on the water side.
 */
function AK_ShoreSides()
{
	local sx = AIMap.GetMapSizeX();
	return [
		[1,   [AITile.CORNER_N, AITile.CORNER_E], [AITile.CORNER_S, AITile.CORNER_W]],
		[-1,  [AITile.CORNER_S, AITile.CORNER_W], [AITile.CORNER_N, AITile.CORNER_E]],
		[sx,  [AITile.CORNER_N, AITile.CORNER_W], [AITile.CORNER_S, AITile.CORNER_E]],
		[-sx, [AITile.CORNER_S, AITile.CORNER_E], [AITile.CORNER_N, AITile.CORNER_W]]
	];
}

/* Corner id to the slope bit RaiseTile and LowerTile take. */
function AK_CornerBit(corner)
{
	if (corner == AITile.CORNER_W) return AITile.SLOPE_W;
	if (corner == AITile.CORNER_S) return AITile.SLOPE_S;
	if (corner == AITile.CORNER_E) return AITile.SLOPE_E;
	return AITile.SLOPE_N;
}

/* The side (from AK_ShoreSides) on which a clear land tile has two flat water tiles in a row, or null. */
function AK_ShoreSide(tile)
{
	if (AITile.IsWaterTile(tile) || !(AITile.IsBuildable(tile) || AITile.IsCoastTile(tile))) return null;
	foreach (side in AK_ShoreSides()) {
		local first = tile + side[0], second = tile + 2 * side[0];
		if (!AIMap.IsValidTile(second)) continue;
		if (!AITile.IsWaterTile(first) || !AITile.IsWaterTile(second)) continue;
		if (AITile.GetSlope(first) != AITile.SLOPE_FLAT || AITile.GetSlope(second) != AITile.SLOPE_FLAT) continue;
		return side;
	}
	return null;
}

function AK_CanShapeDockSite(tile) { return AK_ShoreSide(tile) != null; }

/* Raise or lower corners until the tile slopes down into the water. Returns true when a dock now fits. */
function AK_ShapeDockSite(tile)
{
	local side = AK_ShoreSide(tile);
	if (side == null) return false;
	local water_height = AITile.GetCornerHeight(tile + side[0], AITile.CORNER_N);
	for (local round = 0; round < 4; round++) {
		local done = true;
		foreach (corner in side[1]) {
			local h = AITile.GetCornerHeight(tile, corner);
			if (h > water_height + 1) { AITile.LowerTile(tile, AK_CornerBit(corner)); done = false; }
			else if (h < water_height + 1) { AITile.RaiseTile(tile, AK_CornerBit(corner)); done = false; }
		}
		foreach (corner in side[2]) {
			local h = AITile.GetCornerHeight(tile, corner);
			if (h > water_height) { AITile.LowerTile(tile, AK_CornerBit(corner)); done = false; }
		}
		if (done) break;
	}
	return AK_IsDockSlope(tile) && AK_CanBuildDock(tile);
}

/* Tiles where a dock would serve the industry (and, for a customer, accept `cargo`). */
function AllveiKonsern::DockCandidates(industry, producing, cargo, shapeable = false)
{
	local radius = AIStation.GetCoverageRadius(AIStation.STATION_DOCK);
	local tiles = producing ? AITileList_IndustryProducing(industry, radius) : AITileList_IndustryAccepting(industry, radius);
	tiles.Valuate(shapeable ? AK_CanShapeDockSite : AK_IsDockSlope);
	tiles.KeepValue(1);
	if (!producing && !tiles.IsEmpty()) {
		tiles.Valuate(AITile.GetCargoAcceptance, cargo, 1, 1, radius);
		tiles.KeepAboveValue(7);
	}
	return tiles;
}

/* Can a ship load or unload here: its own dock (oil rig), or a real dock site in reach? Cached per planning round. */
function AllveiKonsern::IsCoastal(industry, producing, cargo)
{
	local key = "c" + industry + "_" + (producing ? 1 : 0) + "_" + cargo;
	if (key in this.cache) return this.cache[key];
	local result = AIIndustry.HasDock(industry) || !this.DockCandidates(industry, producing, cargo).IsEmpty() ||
			!this.DockCandidates(industry, producing, cargo, true).IsEmpty();
	this.cache[key] <- result;
	return result;
}

/*
 * Returns { tile, own, shape } for a dock serving the industry, or null. Builds nothing.
 * shape = true means the shore must be reshaped first (see AK_ShapeDockSite).
 */
function AllveiKonsern::FindDockSpot(industry, producing, cargo, toward)
{
	if (AIIndustry.HasDock(industry)) return { tile = AIIndustry.GetDockLocation(industry), own = false, shape = false };
	local tiles = this.DockCandidates(industry, producing, cargo);
	tiles.Valuate(AIMap.DistanceManhattan, toward);
	tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
	local tries = 0;
	foreach (tile, dummy in tiles) {
		if (++tries > 40) break;
		if (AK_CanBuildDock(tile)) return { tile = tile, own = true, shape = false };
	}
	/* No natural site: pick one to shape, like a player with the terraform tool would. */
	tiles = this.DockCandidates(industry, producing, cargo, true);
	tiles.Valuate(AIMap.DistanceManhattan, toward);
	tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
	foreach (tile, dummy in tiles) return { tile = tile, own = true, shape = true };
	return null;
}

/* The flat water tile right in front of a dock site (natural or still to be shaped), or -1. */
function AK_DockFrontWater(dock)
{
	if ("front" in dock) return dock.front;
	if (!dock.own) return -1;
	if (!dock.shape) return AK_DockWaterTile(dock.tile);
	local side = AK_ShoreSide(dock.tile);
	return side == null ? -1 : dock.tile + side[0];
}

/*
 * Water tiles where ships wait to enter a dock. Our own dock reaches one tile into
 * the water, so ships arrive on the tile beyond it; an oil rig is open on all sides.
 */
function AllveiKonsern::DockApproach(dock)
{
	if ("approach" in dock) return dock.approach;
	if (!dock.own) return this.WaterAround(dock.tile);
	local first = AK_DockFrontWater(dock);
	if (first < 0) return [];
	return [first + (first - dock.tile)];
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

/*
 * Breadth-first search over sailable water from any `start` tile to any `goal` tile,
 * never entering `blocked`. Returns the table of water tiles reached, or null.
 */
function AK_WaterSearch(start, goal, blocked)
{
	local sx = AIMap.GetMapSizeX();
	local offsets = [1, -1, sx, -sx];
	local seen = {};
	foreach (t, dummy in blocked) seen[t] <- true;
	local reached = {};
	local queue = [];
	local found = false;
	foreach (t in start) {
		if (t in seen) continue;
		seen[t] <- true;
		reached[t] <- true;
		queue.push(t);
		if (t in goal) found = true;
	}
	local head = 0;
	while (!found && head < queue.len() && head < AK_WATER_SEARCH_BUDGET) {
		local tile = queue[head++];
		foreach (off in offsets) {
			local next = tile + off;
			if ((next in seen) || !AIMap.IsValidTile(next)) continue;
			seen[next] <- true;
			/* Ships sail on flat water; a sloped river tile needs a lock. */
			local sailable = AIMarine.IsLockTile(next) || AIMarine.IsBuoyTile(next) ||
					(AITile.IsWaterTile(next) && AITile.GetSlope(next) == AITile.SLOPE_FLAT);
			if (!sailable) continue;
			reached[next] <- true;
			if (next in goal) found = true;
			queue.push(next);
		}
	}
	return found ? reached : null;
}

/* Tiles ships may not sail through: the water part of both docks (a station), plus `extra`. */
function AllveiKonsern::DockBlocked(dock_a, dock_b, extra)
{
	local blocked = {};
	foreach (dock in [dock_a, dock_b]) {
		local front = AK_DockFrontWater(dock);
		if (front >= 0) blocked[front] <- true;
	}
	foreach (t in extra) blocked[t] <- true;
	return blocked;
}

/* Can a ship sail from one dock to the other? Returns the water tiles reached, or null. */
function AllveiKonsern::WaterConnected(dock_a, dock_b, extra = [])
{
	local goal = {};
	foreach (t in this.DockApproach(dock_b)) goal[t] <- true;
	local start = this.DockApproach(dock_a);
	if (goal.len() == 0 || start.len() == 0) return null;
	return AK_WaterSearch(start, goal, this.DockBlocked(dock_a, dock_b, extra));
}

/*
 * A water depot near `near`, on water the ships really sail, that neither blocks the
 * way between the docks nor gets cut off from them. Returns its tile or null.
 */
function AllveiKonsern::BuildWaterDepotNear(near, dock_a, dock_b, reachable, keep_clear)
{
	local sx = AIMap.GetMapSizeX();
	local offsets = [1, -1, sx, -sx];
	local x = AIMap.GetTileX(near), y = AIMap.GetTileY(near);
	local tries = 0;
	for (local r = 2; r <= 8; r++) {
		for (local dx = -r; dx <= r; dx++) {
			for (local dy = -r; dy <= r; dy++) {
				if (AK_Max(AK_Abs(dx), AK_Abs(dy)) != r) continue;
				local tile = AK_Tile(x + dx, y + dy);
				if (!(tile in reachable) || (tile in keep_clear)) continue;
				foreach (off in offsets) {
					local front = tile + off;
					local back = tile - off;   // The depot is two tiles long, away from its front.
					if (!(front in reachable) || (front in keep_clear) || (back in keep_clear) || !(back in reachable)) continue;
					if (!AK_CanBuildWaterDepot(tile, front)) continue;
					/* The docks must stay connected with the depot in place, and the depot must reach them. */
					if (this.WaterConnected(dock_a, dock_b, [tile, back]) == null) continue;
					local goal = {};
					foreach (t in this.DockApproach(dock_a)) goal[t] <- true;
					if (AK_WaterSearch([front], goal, this.DockBlocked(dock_a, dock_b, [tile, back])) == null) continue;
					if (AIMarine.BuildWaterDepot(tile, front)) return tile;
					if (++tries > 10) return null;
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

	/* Remember where the water is before the docks change the tiles. */
	foreach (dock in [dock_a, dock_b]) {
		dock.front <- AK_DockFrontWater(dock);
		dock.approach <- this.DockApproach(dock);
	}
	local reachable = this.WaterConnected(dock_a, dock_b);
	if (reachable == null) {
		AILog.Info("Kaiene ligger ikke ved samme vann.");
		return false;
	}
	/* Keep the water in front of both docks free for ships. */
	local keep_clear = {};
	foreach (dock in [dock_a, dock_b]) {
		local first = AK_DockFrontWater(dock);
		if (first >= 0) keep_clear[first] <- true;
		foreach (t in this.DockApproach(dock)) keep_clear[t] <- true;
	}

	foreach (dock in [dock_a, dock_b]) {
		if (!dock.shape) continue;
		if (!this.EnsureCash(AITile.GetBuildCost(AITile.BT_TERRAFORM) * 8) || !AK_ShapeDockSite(dock.tile)) {
			AILog.Info("Strandkanten kunne ikke formes for en kai.");
			return false;
		}
		AILog.Info("Formet strandkanten for en kai ved " + AIMap.GetTileX(dock.tile) + "," + AIMap.GetTileY(dock.tile) + ".");
	}

	if (dock_a.own && !AIMarine.BuildDock(dock_a.tile, AIStation.STATION_NEW)) return false;
	if (dock_b.own && !AIMarine.BuildDock(dock_b.tile, AIStation.STATION_NEW)) {
		if (dock_a.own) AIMarine.RemoveDock(dock_a.tile);
		return false;
	}

	local depot = this.BuildWaterDepotNear(dock_a.tile, dock_a, dock_b, reachable, keep_clear);
	if (depot == null) depot = this.BuildWaterDepotNear(dock_b.tile, dock_a, dock_b, reachable, keep_clear);
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
