/*
 * Allvei Konsern - planes: an airport in each of two big towns far apart,
 * placed where the most passengers live, and small or medium passenger planes.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

function AK_CanBuildAirport(tile, type)
{
	local mode = AITestMode();
	return AIAirport.BuildAirport(tile, type, AIStation.STATION_NEW);
}

/* The best small-plane airport we may build; large ones rarely fit in towns. */
function AllveiKonsern::BestAirportType()
{
	foreach (type in [AIAirport.AT_COMMUTER, AIAirport.AT_SMALL]) {
		if (AIAirport.IsValidAirportType(type)) return type;
	}
	return null;
}

function AllveiKonsern::FindAirportSite(town, type)
{
	local width = AIAirport.GetAirportWidth(type);
	local height = AIAirport.GetAirportHeight(type);
	local radius = AIAirport.GetAirportCoverageRadius(type);
	local centre = AITown.GetLocation(town);
	local span = 10 + AK_Min(AITown.GetPopulation(town) / 300, 15);
	local cx = AIMap.GetTileX(centre), cy = AIMap.GetTileY(centre);

	local tiles = AITileList();
	tiles.AddRectangle(AK_Tile(cx - span, cy - span), AK_Tile(cx + span, cy + span));
	tiles.Valuate(AITile.IsBuildableRectangle, width, height);
	tiles.KeepValue(1);
	if (tiles.IsEmpty()) return null;
	tiles.Valuate(AITile.GetCargoAcceptance, this.passenger, width, height, radius);
	tiles.KeepAboveValue(24);
	tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);

	local tries = 0;
	foreach (tile, dummy in tiles) {
		if (AK_CanBuildAirport(tile, type)) return tile;
		if (++tries >= 40) break;
	}
	return null;
}

/* Best plane that fits the airport and reaches the other end. */
function AllveiKonsern::PickPlane(tile_a, tile_b, cargo)
{
	local engines = AIEngineList(AIVehicle.VT_AIR);
	engines.Valuate(AIEngine.IsBuildable);
	engines.KeepValue(1);
	engines.Valuate(AK_CarriesCargo, cargo);
	engines.KeepValue(1);
	engines.Valuate(AIEngine.GetPlaneType);
	engines.RemoveValue(AIAirport.PT_BIG_PLANE);
	local order_dist = AIOrder.GetOrderDistance(AIVehicle.VT_AIR, tile_a, tile_b);
	local best = null, best_score = -1;
	foreach (engine, dummy in engines) {
		local range = AIEngine.GetMaximumOrderDistance(engine);
		if (range != 0 && range < order_dist) continue;
		local score = AK_EngineScore(engine);
		if (score > best_score) {
			best_score = score;
			best = engine;
		}
	}
	return best;
}

function AllveiKonsern::BuildAirRoute(p)
{
	local type = this.BestAirportType();
	if (type == null) return false;
	local engine = this.PickPlane(AITown.GetLocation(p.src), AITown.GetLocation(p.dst), this.passenger);
	if (engine == null) return false;
	local cost = (2 * AIAirport.GetPrice(type) + 2 * AIEngine.GetPrice(engine)) * 11 / 10;
	if (this.SpendableMoney() < cost) return false;

	local site_a = this.FindAirportSite(p.src, type);
	if (site_a == null) {
		this.Block("t" + p.src + "_" + p.mode);
		AILog.Info("Ingen plass til flyplass i " + AITown.GetName(p.src) + ".");
		return false;
	}
	local site_b = this.FindAirportSite(p.dst, type);
	if (site_b == null) {
		this.Block("t" + p.dst + "_" + p.mode);
		AILog.Info("Ingen plass til flyplass i " + AITown.GetName(p.dst) + ".");
		return false;
	}
	if (!this.EnsureCash(cost)) return false;
	if (!AIAirport.BuildAirport(site_a, type, AIStation.STATION_NEW)) return false;
	if (!AIAirport.BuildAirport(site_b, type, AIStation.STATION_NEW)) {
		AIAirport.RemoveAirport(site_a);
		return false;
	}

	local route = this.AddRoute({ mode = AK_MODE_AIR, cargo = this.passenger, src = p.src, dst = p.dst, src_town = true, dst_town = true,
			dist = p.dist, st_a = site_a, st_b = site_b, depot = AIAirport.GetHangarOfAirport(site_a), type = type });
	foreach (pair in [[site_a, p.src], [site_b, p.dst]]) {
		local station = AIStation.GetStationID(pair[0]);
		if (!AIBaseStation.SetName(station, AITown.GetName(pair[1]) + " lufthavn")) AIBaseStation.SetName(station, AITown.GetName(pair[1]) + " lufthavn " + station);
	}
	this.AddPlane(route, 0);
	this.AddPlane(route, 1);
	return true;
}

function AllveiKonsern::AddPlane(route, count)
{
	local engine = this.PickPlane(route.st_a, route.st_b, route.cargo);
	local hangar = AIAirport.GetHangarOfAirport(count % 2 == 1 ? route.st_b : route.st_a);
	local veh = this.BuyVehicle(route, hangar, engine);
	if (veh == null) return false;
	AIOrder.AppendOrder(veh, route.st_a, AIOrder.OF_NONE);
	AIOrder.AppendOrder(veh, route.st_b, AIOrder.OF_NONE);
	if (count % 2 == 1) AIOrder.SkipToOrder(veh, 1);
	AIVehicle.StartStopVehicle(veh);
	return true;
}

function AllveiKonsern::TearDownAir(route)
{
	foreach (tile in [route.st_a, route.st_b]) {
		if (AIAirport.IsAirportTile(tile) && this.IsOurs(tile) && AIVehicleList_Station(AIStation.GetStationID(tile)).Count() == 0) {
			AIAirport.RemoveAirport(tile);
		}
	}
}
