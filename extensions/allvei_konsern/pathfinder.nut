/*
 * A* rail pathfinder for Modern Tycoon AIs. No libraries, plain Squirrel.
 *
 * The path is a list of tiles; consecutive tiles are neighbours along the
 * x or y axis. A turn inside a tile becomes a diagonal track piece. Rules
 * that keep the result buildable and connected:
 *   - only clear (buildable) land, or a straight level crossing over a flat road;
 *   - flat tiles may turn; a sloped tile must be crossed straight, along its incline;
 *   - steep slopes and water are never used.
 *   - two turns the same way on neighbouring tiles make a 90 degree bend,
 *     which trains may not take (OpenTTD's default), so it is never built.
 * Costs: every tile, extra for turns, slopes and level crossings.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

/* Directions: 0 = +x, 1 = -x, 2 = +y, 3 = -y. Opposite is d ^ 1, axis is d / 2. */
MT_CLOCKWISE <- [2, 3, 1, 0];

function MT_TurnSign(from_dir, to_dir)
{
	if (from_dir == to_dir) return 0;
	return MT_CLOCKWISE[from_dir] == to_dir ? 1 : -1;
}

class MT_RailPathfinder {
	cost_tile = 10;
	cost_turn = 6;
	cost_slope = 15;
	cost_crossing = 40;
	max_expansions = 40000;

	offsets = null;   // Tile index offsets per direction.
	blocked = null;   // Table: tile -> true, never used by the path.
	expansions = 0;

	constructor()
	{
		local sx = AIMap.GetMapSizeX();
		this.offsets = [1, -1, sx, -sx];
		this.blocked = {};
	}

	function Block(tile) { this.blocked[tile] <- true; }
	function Key(tile, dir, turn) { return (tile * 4 + dir) * 3 + turn + 1; }
	function Offset(dir) { return this.offsets[dir]; }

	/* Direction that leads from `from` to its neighbour `to`, or -1. */
	function DirBetween(from, to)
	{
		local delta = to - from;
		for (local d = 0; d < 4; d++) if (this.offsets[d] == delta) return d;
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
	 * Find a path that starts on `start` (entered along `start_dir`) and ends
	 * on a tile from which a step along `goal_dir` reaches `goal`.
	 * Returns an array of tiles from start to the tile before goal, or null.
	 */
	function FindPath(start, start_dir, goal, goal_dir)
	{
		this.expansions = 0;
		local start_cost = this.EnterCost(start, start_dir);
		if (start_cost < 0) return null;

		local open = AIPriorityQueue();
		local closed = {};
		local best = {};
		/* Node: [tile, dir, last_turn, g, parent]. The key includes the last turn, which limits the next one. */
		local first = [start, start_dir, 0, start_cost, null];
		open.Insert(first, start_cost + AIMap.DistanceManhattan(start, goal) * this.cost_tile);
		best[this.Key(start, start_dir, 0)] <- start_cost;

		while (!open.IsEmpty()) {
			local node = open.Pop();
			local tile = node[0], dir = node[1];
			local key = this.Key(tile, dir, node[2]);
			if (key in closed) continue;
			closed[key] <- true;
			if (++this.expansions > this.max_expansions) return null;

			local can_turn = this.CanTurnOn(tile);
			for (local nd = 0; nd < 4; nd++) {
				if (nd == (dir ^ 1)) continue;
				if (nd != dir && !can_turn) continue;
				local turn = MT_TurnSign(dir, nd);
				if (turn != 0 && turn == node[2]) continue;   // 90 degree bend.
				local next = tile + this.offsets[nd];

				if (next == goal) {
					if (nd == goal_dir) return this.Reconstruct(node);
					continue;
				}

				local step = this.EnterCost(next, nd);
				if (step < 0) continue;
				if (turn != 0) step += this.cost_turn;

				local next_key = this.Key(next, nd, turn);
				if (next_key in closed) continue;
				local g = node[3] + step;
				if (next_key in best && best[next_key] <= g) continue;
				best[next_key] <- g;
				open.Insert([next, nd, turn, g, node], g + AIMap.DistanceManhattan(next, goal) * this.cost_tile);
			}
		}
		return null;
	}

	function Reconstruct(node)
	{
		local path = [];
		while (node != null) {
			path.push(node[0]);
			node = node[4];
		}
		path.reverse();
		return path;
	}
}
