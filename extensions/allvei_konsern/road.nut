/*
 * Allvei Konsern - roads: an A* road pathfinder, truck and bus stops,
 * depots and road vehicles.
 *
 * The pathfinder reuses existing roads (cheap), builds new road over clear
 * land, crosses flat straight rail with a level crossing, and bridges over
 * water, rail or anything else it cannot build on. A failed build blocks
 * the tile and the search runs again.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

const AK_ROAD_BUILD_TRIES = 6;
const AK_MAX_BRIDGE = 12;

/* Dry runs; they cost nothing. */
function AK_CanBuildRoadStop(tile, front, rvtype)
{
	local mode = AITestMode();
	return AIRoad.BuildRoadStation(tile, front, rvtype, AIStation.STATION_NEW);
}

function AK_CanBuildDriveThrough(tile, front, rvtype)
{
	local mode = AITestMode();
	return AIRoad.BuildDriveThroughRoadStation(tile, front, rvtype, AIStation.STATION_NEW);
}

/* Fastest bridge type for a span from `a` to `b`, or -1. */
function AK_BridgeType(a, b)
{
	local list = AIBridgeList_Length(AIMap.DistanceManhattan(a, b) + 1);
	if (list.IsEmpty()) return -1;
	list.Valuate(AIBridge.GetMaxSpeed);
	list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
	return list.Begin();
}

function AK_CanBuildRoadBridge(a, b)
{
	local type = AK_BridgeType(a, b);
	if (type < 0) return false;
	local mode = AITestMode();
	return AIBridge.BuildBridge(AIVehicle.VT_ROAD, type, a, b);
}

class AK_RoadPathfinder {
	cost_new = 10;
	cost_existing = 3;
	cost_slope = 5;
	cost_turn = 3;
	cost_crossing = 25;
	cost_bridge_tile = 35;
	max_expansions = 30000;
	max_bridge_tests = 300;

	offsets = null;
	blocked = null;
	expansions = 0;
	bridge_tests = 0;

	constructor()
	{
		local sx = AIMap.GetMapSizeX();
		this.offsets = [1, -1, sx, -sx];
		this.blocked = {};
	}

	function Block(tile) { this.blocked[tile] <- true; }

	function IsInsideMap(tile)
	{
		local x = AIMap.GetTileX(tile), y = AIMap.GetTileY(tile);
		return x >= 1 && y >= 1 && x < AIMap.GetMapSizeX() - 1 && y < AIMap.GetMapSizeY() - 1;
	}

	/* Cost to drive onto `tile` moving along `dir`, or -1 when it cannot take a road this way. */
	function EnterCost(tile, dir)
	{
		if ((tile in this.blocked) || !this.IsInsideMap(tile)) return -1;
		if (AITile.IsWaterTile(tile)) return -1;

		if (AIRoad.IsRoadTile(tile)) {
			if (!AIRoad.HasRoadType(tile, AIRoad.ROADTYPE_ROAD)) return -1;
			if (AIRoad.IsRoadStationTile(tile) || AIRoad.IsRoadDepotTile(tile)) return -1;
			if (AIBridge.IsBridgeTile(tile) || AITunnel.IsTunnelTile(tile)) return -1;
			if (AIRail.IsLevelCrossingTile(tile)) {
				/* The road of a crossing runs across the rail. */
				local road_on_y = AIRail.GetRailTracks(tile) == AIRail.RAILTRACK_NE_SW;
				if ((dir / 2 == 1) != road_on_y) return -1;
				return this.cost_existing + this.cost_crossing;
			}
			return this.cost_existing;
		}

		local slope = AITile.GetSlope(tile);
		if (AITile.IsBuildable(tile)) {
			if (AITile.IsSteepSlope(slope)) return -1;
			return this.cost_new + (slope == AITile.SLOPE_FLAT ? 0 : this.cost_slope);
		}

		/* A flat, plain, straight rail track across our way can get a level crossing. */
		if (AIRail.IsRailTile(tile) && slope == AITile.SLOPE_FLAT && !AIRail.IsRailStationTile(tile) &&
				!AIRail.IsRailDepotTile(tile) && !AIBridge.IsBridgeTile(tile) && !AITunnel.IsTunnelTile(tile)) {
			local tracks = AIRail.GetRailTracks(tile);
			if (tracks == AIRail.RAILTRACK_NE_SW && dir / 2 == 1) return this.cost_new + this.cost_crossing;
			if (tracks == AIRail.RAILTRACK_NW_SE && dir / 2 == 0) return this.cost_new + this.cost_crossing;
		}
		return -1;
	}

	/* Can a bridge head go on this tile? It must be clear land (not road). */
	function CanHoldBridgeHead(tile)
	{
		return !(tile in this.blocked) && this.IsInsideMap(tile) && AITile.IsBuildable(tile) && !AITile.IsWaterTile(tile);
	}

	/*
	 * Find a road from `start` to `goal`. Both are tiles a road may use.
	 * Returns { path = [tiles from start to goal], bridges = [[head, other head], ...] } or null.
	 */
	function FindPath(start, goal)
	{
		this.expansions = 0;
		this.bridge_tests = 0;
		if (this.EnterCost(start, 0) < 0 && this.EnterCost(start, 2) < 0) return null;
		local limit = AK_Min(this.max_expansions, 4000 + AIMap.DistanceManhattan(start, goal) * 300);

		local open = AIPriorityQueue();
		local closed = {};
		local best = {};
		/* Node: [tile, dir, g, parent, came_by_bridge]. dir -1 = start. */
		open.Insert([start, -1, 0, null, false], AIMap.DistanceManhattan(start, goal) * 8);

		while (!open.IsEmpty()) {
			local node = open.Pop();
			local tile = node[0], dir = node[1];
			local key = tile * 5 + dir + 1;
			if (key in closed) continue;
			closed[key] <- true;
			if (++this.expansions > limit) return null;

			for (local nd = 0; nd < 4; nd++) {
				if (dir >= 0 && nd == (dir ^ 1)) continue;
				if (node[4] && nd != dir) continue;   // Leave a bridge straight ahead.
				local next = tile + this.offsets[nd];

				if (next == goal) return this.Reconstruct([next, nd, 0, node, false]);

				local step = this.EnterCost(next, nd);
				if (step >= 0) {
					if (dir >= 0 && nd != dir) step += this.cost_turn;
					this.Push(open, best, closed, [next, nd, node[2] + step, node, false], goal);
					continue;
				}

				/* Obstacle: try a bridge whose first head is this tile. */
				if (dir != nd || node[4] || !this.CanHoldBridgeHead(tile) || this.bridge_tests >= this.max_bridge_tests) continue;
				for (local len = 2; len <= AK_MAX_BRIDGE; len++) {
					local end = tile + this.offsets[nd] * len;
					if (!this.IsInsideMap(end)) break;
					if (end == goal || !this.CanHoldBridgeHead(end)) continue;
					this.bridge_tests++;
					if (!AK_CanBuildRoadBridge(tile, end)) continue;
					this.Push(open, best, closed, [end, nd, node[2] + len * this.cost_bridge_tile, node, true], goal);
					break;
				}
			}
		}
		return null;
	}

	function Push(open, best, closed, node, goal)
	{
		local key = node[0] * 5 + node[1] + 1;
		if (key in closed) return;
		if ((key in best) && best[key] <= node[2]) return;
		best[key] <- node[2];
		open.Insert(node, node[2] + AIMap.DistanceManhattan(node[0], goal) * 8);
	}

	function Reconstruct(node)
	{
		local path = [], bridges = [];
		while (node != null) {
			path.push(node[0]);
			if (node[4] && node[3] != null) bridges.push([node[3][0], node[0]]);
			node = node[3];
		}
		path.reverse();
		return { path = path, bridges = bridges };
	}
}

/* ------------------------------------------------------------ building */

/* Retry a command a few times when a vehicle is in the way. */
function AK_BuildRoadPiece(a, b)
{
	for (local i = 0; i < 4; i++) {
		if (AIRoad.BuildRoad(a, b)) return true;
		local err = AIError.GetLastError();
		if (err == AIError.ERR_ALREADY_BUILT) return true;
		if (err != AIError.ERR_VEHICLE_IN_THE_WAY) return false;
		AIController.Sleep(10);
	}
	return false;
}

/* Build the found road. Returns -1 on success, or the index of a path tile that failed. */
function AllveiKonsern::BuildRoadPath(found)
{
	local path = found.path;
	local is_head = {};
	foreach (b in found.bridges) {
		is_head[b[0]] <- b[1];
		if (AIBridge.IsBridgeTile(b[0]) && AIBridge.GetOtherBridgeEnd(b[0]) == b[1]) continue;
		local type = AK_BridgeType(b[0], b[1]);
		if (type < 0 || !AIBridge.BuildBridge(AIVehicle.VT_ROAD, type, b[0], b[1])) {
			for (local i = 0; i < path.len(); i++) if (path[i] == b[0]) return i;
			return 0;
		}
	}
	for (local i = 1; i < path.len(); i++) {
		local a = path[i - 1], b = path[i];
		if ((a in is_head) && is_head[a] == b) continue;
		if (!AK_BuildRoadPiece(a, b)) {
			if (AIError.GetLastError() == AIError.ERR_NOT_ENOUGH_CASH) return -2;
			return i;
		}
	}
	return -1;
}

/* Find and build a road between two tiles, retrying around tiles that fail. */
function AllveiKonsern::ConnectByRoad(from, to, protect)
{
	local pf = AK_RoadPathfinder();
	foreach (tile in protect) pf.Block(tile);
	for (local attempt = 0; attempt < AK_ROAD_BUILD_TRIES; attempt++) {
		local found = pf.FindPath(from, to);
		if (found == null) {
			AILog.Info("Fant ingen veitrasé (" + pf.expansions + " ruter undersøkt).");
			return null;
		}
		local cost = this.TestRoadCost(found);
		if (!this.EnsureCash(cost)) {
			AILog.Info("Veien koster " + cost + ", har ikke råd ennå.");
			return null;
		}
		local failed = this.BuildRoadPath(found);
		if (failed == -1) return found;
		if (failed == -2) return null;
		local tile = found.path[failed];
		AILog.Info("Veien kunne ikke bygges ved " + AIMap.GetTileX(tile) + "," + AIMap.GetTileY(tile) + " (" +
				AIError.GetLastErrorString() + "). Finner ny trasé.");
		if (tile == from || tile == to) {
			if (failed > 0) pf.Block(found.path[failed - 1]);
			else return null;
		} else {
			pf.Block(tile);
		}
	}
	return null;
}

function AllveiKonsern::TestRoadCost(found)
{
	local costs = AIAccounting();
	local mode = AITestMode();
	local is_head = {};
	foreach (b in found.bridges) {
		is_head[b[0]] <- b[1];
		local type = AK_BridgeType(b[0], b[1]);
		if (type >= 0) AIBridge.BuildBridge(AIVehicle.VT_ROAD, type, b[0], b[1]);
	}
	local path = found.path;
	for (local i = 1; i < path.len(); i++) {
		if ((path[i - 1] in is_head) && is_head[path[i - 1]] == path[i]) continue;
		AIRoad.BuildRoad(path[i - 1], path[i]);
	}
	return costs.GetCosts() * 11 / 10 + 1000;
}

/* ------------------------------------------------------------- stops */

/*
 * A stop that serves an industry (bay stop on clear land) or a town (drive-through
 * stop on an existing town road). Returns { tile, front, drive } or null.
 */
function AllveiKonsern::FindRoadStop(place, is_town, producing, cargo, toward, rvtype)
{
	if (is_town) return this.FindTownStop(place, cargo, toward, rvtype);

	local pf = AK_RoadPathfinder();
	local radius = AIStation.GetCoverageRadius(rvtype == AIRoad.ROADVEHTYPE_BUS ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP);
	local tiles = producing ? AITileList_IndustryProducing(place, radius) : AITileList_IndustryAccepting(place, radius);
	tiles.Valuate(AITile.IsBuildable);
	tiles.KeepValue(1);
	tiles.Valuate(AITile.GetSlope);
	tiles.KeepValue(AITile.SLOPE_FLAT);
	if (!producing) {
		tiles.Valuate(AITile.GetCargoAcceptance, cargo, 1, 1, radius);
		tiles.KeepAboveValue(7);
	}
	tiles.Valuate(AIMap.DistanceManhattan, toward);
	tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

	local tries = 0;
	foreach (tile, dummy in tiles) {
		if (++tries > 60) break;
		/* Prefer an entrance that faces the other end. */
		local dirs = [0, 1, 2, 3];
		dirs.sort(function(a, b) : (tile, toward, pf) {
			return AK_Cmp(AIMap.DistanceManhattan(tile + pf.offsets[a], toward), AIMap.DistanceManhattan(tile + pf.offsets[b], toward));
		});
		foreach (d in dirs) {
			local front = tile + pf.offsets[d];
			if (pf.EnterCost(front, d) < 0) continue;
			if (AK_CanBuildRoadStop(tile, front, rvtype)) return { tile = tile, front = front, drive = false };
		}
	}
	return null;
}

/* A drive-through stop on a straight town road, where the most cargo is accepted. */
function AllveiKonsern::FindTownStop(town, cargo, toward, rvtype)
{
	local pf = AK_RoadPathfinder();
	local radius = AIStation.GetCoverageRadius(rvtype == AIRoad.ROADVEHTYPE_BUS ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP);
	local centre = AITown.GetLocation(town);
	local span = 4 + AK_Min(AITown.GetPopulation(town) / 800, 10);
	local cx = AIMap.GetTileX(centre), cy = AIMap.GetTileY(centre);

	local tiles = AITileList();
	tiles.AddRectangle(AK_Tile(cx - span, cy - span), AK_Tile(cx + span, cy + span));
	tiles.Valuate(AIRoad.IsRoadTile);
	tiles.KeepValue(1);
	tiles.Valuate(AITile.GetSlope);
	tiles.KeepValue(AITile.SLOPE_FLAT);
	tiles.Valuate(AITile.GetCargoAcceptance, cargo, 1, 1, radius);
	tiles.KeepAboveValue(7);
	tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);

	local tries = 0;
	foreach (tile, dummy in tiles) {
		if (++tries > 60) break;
		if (AIRoad.IsRoadStationTile(tile) || AIRail.IsLevelCrossingTile(tile) || AIBridge.IsBridgeTile(tile) || AITunnel.IsTunnelTile(tile)) continue;
		foreach (d in [0, 2]) {
			local front = tile + pf.offsets[d];
			local back = tile + pf.offsets[d + 1];
			if (!AIRoad.AreRoadTilesConnected(tile, front) || !AIRoad.AreRoadTilesConnected(tile, back)) continue;
			if (!AK_CanBuildDriveThrough(tile, front, rvtype)) continue;
			/* The road leaves toward the other end from whichever side is closer. */
			if (AIMap.DistanceManhattan(back, toward) < AIMap.DistanceManhattan(front, toward)) {
				local t = front; front = back; back = t;
			}
			return { tile = tile, front = front, drive = true };
		}
	}
	return null;
}

function AllveiKonsern::BuildRoadStop(stop, rvtype)
{
	if (stop.drive) return AIRoad.BuildDriveThroughRoadStation(stop.tile, stop.front, rvtype, AIStation.STATION_NEW);
	if (!AIRoad.BuildRoadStation(stop.tile, stop.front, rvtype, AIStation.STATION_NEW)) return false;
	if (!AK_BuildRoadPiece(stop.front, stop.tile)) {
		AIRoad.RemoveRoadStation(stop.tile);
		return false;
	}
	return true;
}

/* A depot beside the road, close to the pickup. Returns its tile or null. */
function AllveiKonsern::BuildRoadDepotNear(path)
{
	local pf = AK_RoadPathfinder();
	local last = AK_Min(path.len() - 1, 20);
	for (local i = 0; i <= last; i++) {
		local tile = path[i];
		if (!AIRoad.IsRoadTile(tile) || AIBridge.IsBridgeTile(tile) || AIRoad.IsRoadStationTile(tile) || AIRail.IsLevelCrossingTile(tile)) continue;
		foreach (off in pf.offsets) {
			local depot = tile + off;
			if (!AITile.IsBuildable(depot) || AITile.GetSlope(depot) != AITile.SLOPE_FLAT) continue;
			if (!AIRoad.BuildRoadDepot(depot, tile)) continue;
			if (AK_BuildRoadPiece(depot, tile)) return depot;
			AITile.DemolishTile(depot);
		}
	}
	return null;
}

/* --------------------------------------------------------------- routes */

function AllveiKonsern::BuildRoadRoute(p)
{
	local rvtype = AICargo.HasCargoClass(p.cargo, AICargo.CC_PASSENGERS) ? AIRoad.ROADVEHTYPE_BUS : AIRoad.ROADVEHTYPE_TRUCK;
	AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
	local src_tile = p.src_town ? AITown.GetLocation(p.src) : AIIndustry.GetLocation(p.src);
	local dst_tile = p.dst_town ? AITown.GetLocation(p.dst) : AIIndustry.GetLocation(p.dst);

	local stop_a = this.FindRoadStop(p.src, p.src_town, true, p.cargo, dst_tile, rvtype);
	if (stop_a == null) {
		AILog.Info("Ingen plass til holdeplass ved " + this.PlaceName(p.src, p.src_town) + ".");
		if (p.src_town) this.Block("t" + p.src + "_" + p.mode); else this.Block("s" + p.src, 120);
		return false;
	}
	local stop_b = this.FindRoadStop(p.dst, p.dst_town, false, p.cargo, src_tile, rvtype);
	if (stop_b == null) {
		AILog.Info("Ingen plass til holdeplass ved " + this.PlaceName(p.dst, p.dst_town) + ".");
		if (p.dst_town && p.mode == AK_MODE_BUS) this.Block("t" + p.dst + "_" + p.mode);
		return false;
	}

	local engine = this.BestEngine(AIVehicle.VT_ROAD, p.cargo);
	if (engine == null) return false;
	local stop_cost = AIRoad.GetBuildCost(AIRoad.ROADTYPE_ROAD, rvtype == AIRoad.ROADVEHTYPE_BUS ? AIRoad.BT_BUS_STOP : AIRoad.BT_TRUCK_STOP);
	if (!this.EnsureCash(2 * stop_cost + AIEngine.GetPrice(engine))) return false;

	if (!this.BuildRoadStop(stop_a, rvtype)) {
		AILog.Info("Holdeplassen ble ikke bygd: " + AIError.GetLastErrorString());
		return false;
	}
	if (!this.BuildRoadStop(stop_b, rvtype)) {
		AILog.Info("Holdeplassen ble ikke bygd: " + AIError.GetLastErrorString());
		AIRoad.RemoveRoadStation(stop_a.tile);
		return false;
	}

	local found = this.ConnectByRoad(stop_a.front, stop_b.front, [stop_a.tile, stop_b.tile]);
	if (found == null) {
		AIRoad.RemoveRoadStation(stop_a.tile);
		AIRoad.RemoveRoadStation(stop_b.tile);
		return false;
	}

	local depot = this.BuildRoadDepotNear(found.path);
	if (depot == null) {
		AILog.Info("Fant ikke plass til garasje.");
		AIRoad.RemoveRoadStation(stop_a.tile);
		AIRoad.RemoveRoadStation(stop_b.tile);
		return false;
	}

	local route = this.AddRoute({ mode = p.mode, cargo = p.cargo, src = p.src, dst = p.dst, src_town = p.src_town, dst_town = p.dst_town,
			dist = p.dist, st_a = stop_a.tile, st_b = stop_b.tile, depot = depot, rvtype = rvtype });
	local kind = rvtype == AIRoad.ROADVEHTYPE_BUS ? AK_MODE_BUS : AK_MODE_ROAD;
	this.NameStation(route.st_a, this.PlaceName(p.src, p.src_town), kind);
	this.NameStation(route.st_b, this.PlaceName(p.dst, p.dst_town), kind);

	local first = AK_Clamp(p.vehicles, 1, 3);
	for (local i = 0; i < first; i++) {
		if (!this.AddRoadVehicle(route, i)) break;
	}
	return true;
}

function AllveiKonsern::NameStation(tile, place, mode)
{
	local station = AIStation.GetStationID(tile);
	local base = (place.len() > 20 ? place.slice(0, 20) : place) + " " + (mode == AK_MODE_BUS ? "busstopp" : (mode == AK_MODE_WATER ? "kai" : "terminal"));
	if (AIBaseStation.SetName(station, base)) return;
	AIBaseStation.SetName(station, base + " " + station);
}

function AllveiKonsern::AddRoadVehicle(route, count)
{
	AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
	local engine = this.BestEngine(AIVehicle.VT_ROAD, route.cargo);
	local veh = this.BuyVehicle(route, route.depot, engine);
	if (veh == null) return false;

	if (route.mode == AK_MODE_BUS) {
		AIOrder.AppendOrder(veh, route.st_a, AIOrder.OF_NONE);
		AIOrder.AppendOrder(veh, route.st_b, AIOrder.OF_NONE);
		if (count % 2 == 1) AIOrder.SkipToOrder(veh, 1);
	} else {
		AIOrder.AppendOrder(veh, route.st_a, AIOrder.OF_FULL_LOAD_ANY);
		AIOrder.AppendOrder(veh, route.st_b, AIOrder.OF_NO_LOAD);
	}
	AIVehicle.StartStopVehicle(veh);
	return true;
}

function AllveiKonsern::TearDownRoad(route)
{
	foreach (tile in [route.st_a, route.st_b]) {
		if (AIRoad.IsRoadStationTile(tile) && this.IsOurs(tile) && AIVehicleList_Station(AIStation.GetStationID(tile)).Count() == 0) {
			AIRoad.RemoveRoadStation(tile);
		}
	}
	if (AIRoad.IsRoadDepotTile(route.depot) && this.IsOurs(route.depot)) AITile.DemolishTile(route.depot);
}
