/*
 * A* rail pathfinder for Modern Tycoon AIs. No libraries, plain Squirrel.
 *
 * The path is a list of tiles; consecutive tiles are neighbours along the
 * x or y axis, except across a bridge or tunnel, where the two heads follow
 * each other (see `last_jumps`). A turn inside a tile becomes a diagonal
 * track piece. Rules that keep the result buildable and connected:
 *   - only clear (buildable) land, or a straight level crossing over a flat road;
 *   - flat tiles may turn; a sloped tile must be crossed straight, along its incline;
 *   - steep slopes and water are never used as plain track;
 *   - two turns the same way on neighbouring tiles make a 90 degree bend,
 *     which trains may not take (OpenTTD's default), so it is never built;
 *   - where the way ahead is blocked (water, a hill, a road or railway, steep
 *     land), the path may jump with a bridge or a tunnel. Heads are straight;
 *   - the first and last tile of a path are straight, so they join station
 *     throats cleanly.
 * Costs: every tile, extra for turns, slopes, level crossings, bridges and tunnels.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

/* Directions: 0 = +x, 1 = -x, 2 = +y, 3 = -y. Opposite is d ^ 1, axis is d / 2. */
MT_CLOCKWISE <- [2, 3, 1, 0];

const MT_JUMP_BRIDGE = 1;
const MT_JUMP_TUNNEL = 2;

function MT_TurnSign(from_dir, to_dir)
{
	if (from_dir == to_dir) return 0;
	return MT_CLOCKWISE[from_dir] == to_dir ? 1 : -1;
}

/* Fastest bridge type that spans `length` tiles (heads included), or null. */
function MT_PickBridge(length)
{
	local bridges = AIBridgeList_Length(length);
	if (bridges.IsEmpty()) return null;
	bridges.Valuate(AIBridge.GetMaxSpeed);
	bridges.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
	return bridges.Begin();
}

/* Something a bridge or tunnel is worth trying for: water, a road or railway, or land too steep for track. */
function MT_IsObstacle(tile, dir)
{
	if (AITile.IsWaterTile(tile) || AIRoad.IsRoadTile(tile) || AIRail.IsRailTile(tile)) return true;
	if (AIBridge.IsBridgeTile(tile) || AITunnel.IsTunnelTile(tile) || AIRail.IsLevelCrossingTile(tile)) return true;
	local slope = AITile.GetSlope(tile);
	if (slope == AITile.SLOPE_FLAT) return false;
	if (AITile.IsSteepSlope(slope)) return true;
	/* An incline across the direction of travel cannot take straight track. */
	if (dir / 2 == 0) return slope != AITile.SLOPE_NE && slope != AITile.SLOPE_SW;
	return slope != AITile.SLOPE_NW && slope != AITile.SLOPE_SE;
}

class MT_RailPathfinder {
	cost_tile = 10;
	cost_turn = 6;
	cost_slope = 15;
	cost_crossing = 40;
	cost_bridge_tile = 25;
	cost_tunnel_tile = 18;   // Cheap-ish: trains avoid the climb, so tunnels are worth it.
	max_bridge = 10;
	max_tunnel = 16;
	max_expansions = 60000;
	/* Heuristic weight in tenths: a little greedy, much faster, paths stay close to the cheapest. */
	h_weight_x10 = 13;

	/* A search gives up after this many game days, so the company never stalls on one line. */
	max_days = 60;

	offsets = null;   // Tile index offsets per direction.
	blocked = null;   // Table: tile -> true, never used by the path.
	expansions = 0;
	timed_out = false;
	last_jumps = null; // Array of [start_head, end_head, kind] for the last path found.
	jump_cache = null; // Table: head * 4 + dir -> result of Jumps(), per search.
	bridge_cache = null; // Table: length -> bridge type (or -1).
	deadline = 0;

	constructor()
	{
		local sx = AIMap.GetMapSizeX();
		this.offsets = [1, -1, sx, -sx];
		this.blocked = {};
		this.last_jumps = [];
		this.jump_cache = {};
		this.bridge_cache = {};
	}

	function BridgeFor(length)
	{
		if (!(length in this.bridge_cache)) {
			local type = MT_PickBridge(length);
			this.bridge_cache[length] <- type == null ? -1 : type;
		}
		local cached = this.bridge_cache[length];
		return cached < 0 ? null : cached;
	}

	function Block(tile) { this.blocked[tile] <- true; }
	function Unblock(tile) { if (tile in this.blocked) delete this.blocked[tile]; }
	/* State 0..2 is the last turn (-1, 0, +1); 3 means "standing on the end head of a bridge or tunnel". */
	function Key(tile, dir, state) { return (tile * 4 + dir) * 4 + state; }
	function Offset(dir) { return this.offsets[dir]; }
	function H(tile, goal) { return AIMap.DistanceManhattan(tile, goal) * this.cost_tile * this.h_weight_x10 / 10; }

	/* Direction that leads from `from` to its neighbour `to`, or -1. */
	function DirBetween(from, to)
	{
		local delta = to - from;
		for (local d = 0; d < 4; d++) if (this.offsets[d] == delta) return d;
		return -1;
	}

	/* Direction from `from` to a tile further along the same row or column, or -1. */
	function DirAlong(from, to)
	{
		local dx = AIMap.GetTileX(to) - AIMap.GetTileX(from), dy = AIMap.GetTileY(to) - AIMap.GetTileY(from);
		if (dx != 0 && dy != 0) return -1;
		if (dx > 0) return 0;
		if (dx < 0) return 1;
		if (dy > 0) return 2;
		if (dy < 0) return 3;
		return -1;
	}

	function IsInsideMap(tile)
	{
		local x = AIMap.GetTileX(tile), y = AIMap.GetTileY(tile);
		return x >= 1 && y >= 1 && x < AIMap.GetMapSizeX() - 1 && y < AIMap.GetMapSizeY() - 1;
	}

	/* Extra cost of the slope when moving along `dir`, or -1 when not allowed. */
	function SlopeCost(tile, dir)
	{
		local slope = AITile.GetSlope(tile);
		if (slope == AITile.SLOPE_FLAT) return 0;
		if (AITile.IsSteepSlope(slope)) return -1;
		if (dir / 2 == 0 && (slope == AITile.SLOPE_NE || slope == AITile.SLOPE_SW)) return this.cost_slope;
		if (dir / 2 == 1 && (slope == AITile.SLOPE_NW || slope == AITile.SLOPE_SE)) return this.cost_slope;
		return -1;
	}

	/* A flat, plain road that runs across `dir` can get a level crossing. */
	function IsCrossable(tile, dir)
	{
		if (!AIRoad.IsRoadTile(tile) || AIRoad.IsRoadStationTile(tile) || AIRoad.IsRoadDepotTile(tile)) return false;
		if (AIRail.IsRailTile(tile) || AITile.GetSlope(tile) != AITile.SLOPE_FLAT) return false;
		if (AIBridge.IsBridgeTile(tile) || AITunnel.IsTunnelTile(tile)) return false;
		local side = dir / 2 == 0 ? 2 : 0;
		if (AIRoad.AreRoadTilesConnected(tile, tile + this.offsets[dir]) ||
				AIRoad.AreRoadTilesConnected(tile, tile + this.offsets[dir ^ 1])) return false;
		return AIRoad.AreRoadTilesConnected(tile, tile + this.offsets[side]) ||
				AIRoad.AreRoadTilesConnected(tile, tile + this.offsets[side ^ 1]);
	}

	/* Cost to step onto `tile` moving along `dir`, or -1 when the tile cannot be used. */
	function EnterCost(tile, dir)
	{
		if (tile in this.blocked || !this.IsInsideMap(tile)) return -1;
		local slope_cost = this.SlopeCost(tile, dir);
		if (slope_cost < 0) return -1;
		if (AITile.IsBuildable(tile) && !AITile.IsWaterTile(tile)) return this.cost_tile + slope_cost;
		if (this.IsCrossable(tile, dir)) return this.cost_tile + this.cost_crossing;
		return -1;
	}

	/* Only flat, clear tiles may hold a diagonal (turning) piece. */
	function CanTurnOn(tile)
	{
		return AITile.GetSlope(tile) == AITile.SLOPE_FLAT && AITile.IsBuildable(tile);
	}

	/*
	 * Bridges and tunnels whose first head is `head` (entered along `dir`) and
	 * whose other head lies further along `dir`. Only tried when the tile after
	 * `head` cannot take plain track, so open land never pays for test builds.
	 * Returns an array of [end_head, cost, kind].
	 */
	function Jumps(head, dir)
	{
		local key = head * 4 + dir;
		if (key in this.jump_cache) return this.jump_cache[key];
		local result = this.FindJumps(head, dir);
		this.jump_cache[key] <- result;
		return result;
	}

	function FindJumps(head, dir)
	{
		local result = [];
		if (head in this.blocked || !this.IsInsideMap(head)) return result;
		local off = this.offsets[dir];
		if (!this.IsInsideMap(head + off) || !MT_IsObstacle(head + off, dir)) return result;
		/* One test mode for the whole function: nested mode objects must be released in order. */
		local mode = AITestMode();

		/* Tunnel: the head must be a simple incline into a hill. */
		if (AITile.GetSlope(head) != AITile.SLOPE_FLAT && AITile.IsBuildable(head)) {
			local other = AITunnel.GetOtherTunnelEnd(head);
			if (AIMap.IsValidTile(other) && this.DirAlong(head, other) == dir) {
				local len = AIMap.DistanceManhattan(head, other) + 1;
				if (len <= this.max_tunnel && !(other in this.blocked) && this.IsInsideMap(other)) {
					if (AITunnel.BuildTunnel(AIVehicle.VT_RAIL, head)) result.push([other, len * this.cost_tunnel_tile, MT_JUMP_TUNNEL]);
				}
			}
		}

		/* Bridge: the shortest one that works, heads on clear land. */
		if (!AITile.IsBuildable(head) || AITile.IsWaterTile(head)) return result;
		for (local span = 2; span <= this.max_bridge; span++) {
			local other = head + off * span;
			if (!this.IsInsideMap(other) || (other in this.blocked)) break;
			if (!AITile.IsBuildable(other) || AITile.IsWaterTile(other)) continue;
			local type = this.BridgeFor(span + 1);
			if (type == null) continue;
			if (AIBridge.BuildBridge(AIVehicle.VT_RAIL, type, head, other)) {
				result.push([other, (span + 1) * this.cost_bridge_tile, MT_JUMP_BRIDGE]);
				break;
			}
		}
		return result;
	}

	/*
	 * Find a path that starts on `start` (entered along `start_dir`) and ends
	 * on a tile from which a straight step along `goal_dir` reaches `goal`.
	 * Returns an array of tiles from start to the tile before goal, or null.
	 * Bridges and tunnels used are in `last_jumps`.
	 */
	function FindPath(start, start_dir, goal, goal_dir)
	{
		this.expansions = 0;
		this.timed_out = false;
		this.last_jumps = [];
		this.jump_cache = {};
		this.deadline = AIDate.GetCurrentDate() + this.max_days;
		local start_cost = this.EnterCost(start, start_dir);
		if (start_cost < 0) return null;

		local open = AIPriorityQueue();
		local closed = {};
		local best = {};
		local seen = {};   // Tiles expanded at least once: only then can a path come back to them.
		/*
		 * Node: [tile, dir, last_turn, g, parent, jump_head, jump_kind].
		 * jump_head is the first head when the node stands on the far head of a bridge or tunnel.
		 * The start is marked as a head too, so the first piece is straight.
		 */
		local first = [start, start_dir, 0, start_cost, null, null, 0];
		open.Insert(first, start_cost + this.H(start, goal));

		while (!open.IsEmpty()) {
			local node = open.Pop();
			local tile = node[0], dir = node[1];
			local on_head = node[5] != null || node[4] == null;
			local key = this.Key(tile, dir, on_head ? 3 : node[2] + 1);
			if (key in closed) continue;
			closed[key] <- true;
			seen[tile] <- true;
			if (++this.expansions > this.max_expansions) return null;
			if (this.expansions % 256 == 0 && AIDate.GetCurrentDate() > this.deadline) {
				this.timed_out = true;
				return null;
			}

			local can_turn = !on_head && this.CanTurnOn(tile);
			for (local nd = 0; nd < 4; nd++) {
				if (nd == (dir ^ 1)) continue;
				if (nd != dir && !can_turn) continue;
				local turn = MT_TurnSign(dir, nd);
				if (turn != 0 && turn == node[2]) continue;   // 90 degree bend.
				local next = tile + this.offsets[nd];

				if (next == goal) {
					if (nd == goal_dir && nd == dir) return this.Reconstruct(node);
					continue;
				}
				local turn_cost = turn != 0 ? this.cost_turn : 0;

				/* A track may never use a tile twice: a loop back over itself would meet its own one-way signals. */
				if ((next in seen) && this.OnPath(node, next)) continue;

				local step = this.EnterCost(next, nd);
				if (step >= 0) {
					local next_key = this.Key(next, nd, turn + 1);
					local g = node[3] + step + turn_cost;
					if (!(next_key in closed) && !(next_key in best && best[next_key] <= g)) {
						best[next_key] <- g;
						open.Insert([next, nd, turn, g, node, null, 0], g + this.H(next, goal));
					}
				}

				/* A head may not sit right after another head or a turn on the same tile pair. */
				if (on_head && node[4] != null) continue;
				foreach (jump in this.Jumps(next, nd)) {
					local far = jump[0];
					if ((far in seen) && this.OnPath(node, far)) continue;
					local jump_key = this.Key(far, nd, 3);
					local g = node[3] + jump[1] + turn_cost;
					if (jump_key in closed || (jump_key in best && best[jump_key] <= g)) continue;
					best[jump_key] <- g;
					open.Insert([far, nd, 0, g, node, next, jump[2]], g + this.H(far, goal));
				}
			}
		}
		return null;
	}

	/* Is `tile` already used by the path that ends in `node` (bridge and tunnel heads included)? */
	function OnPath(node, tile)
	{
		while (node != null) {
			if (node[0] == tile || node[5] == tile) return true;
			node = node[4];
		}
		return false;
	}

	function Reconstruct(node)
	{
		local path = [];
		local jumps = [];
		while (node != null) {
			path.push(node[0]);
			if (node[5] != null) {
				path.push(node[5]);
				jumps.push([node[5], node[0], node[6]]);
			}
			node = node[4];
		}
		path.reverse();
		jumps.reverse();
		this.last_jumps = jumps;
		return path;
	}
}
