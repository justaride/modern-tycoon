/*
 * Test-only AI. Lays the chain out along one straight road (north to south):
 *
 *   road x = X-2      oil wells at (X, Y), fuel plant at (X, Y+10), spaceport at (X, Y+20)
 *   stations          drive-through truck stops beside each industry
 *
 * Oil trucks carry oil to the fuel plant; oil tankers refitted to rocket fuel
 * carry the fuel to the spaceport. Logs "MTS-AI ..." lines.
 * SPDX-License-Identifier: GPL-2.0-only
 */
class MTSpaceHauler extends AIController {
	done = false;
	fails = 0;
	constructor() {}
}

function MTSpaceHauler::Log(msg) { AILog.Info("MTS-AI " + msg); }
function MTSpaceHauler::Fail(msg) { AILog.Error("MTS-TEST FAIL ai: " + msg); }

function MTSpaceHauler::TypeByName(name)
{
	foreach (t, _ in AIIndustryTypeList()) if (AIIndustryType.GetName(t) == name) return t;
	return -1;
}

function MTSpaceHauler::CargoByLabel(label)
{
	foreach (c, _ in AICargoList()) if (AICargo.GetCargoLabel(c) == label) return c;
	return -1;
}

function MTSpaceHauler::IndustryAt(type, tile)
{
	foreach (ind, _ in AIIndustryList()) {
		if (AIIndustry.GetIndustryType(ind) == type && AIIndustry.GetLocation(ind) == tile) return ind;
	}
	return -1;
}

/* Find a spot where the whole row fits, and fund the three industries there. */
function MTSpaceHauler::BuildRow(types)
{
	local sx = AIMap.GetMapSizeX(), sy = AIMap.GetMapSizeY();
	for (local y = 8; y < sy - 34; y += 2) {
		for (local x = 8; x < sx - 12; x += 2) {
			// The road column must be free; the industries check their own ground.
			if (!AITile.IsBuildableRectangle(AIMap.GetTileIndex(x - 2, y - 1), 1, 25)) continue;
			local inds = [];
			foreach (i, t in types) {
				local tile = AIMap.GetTileIndex(x, y + 10 * i);
				if (!AIIndustryType.BuildIndustry(t, tile)) break;
				inds.append(this.IndustryAt(t, tile));
			}
			if (inds.len() == types.len()) return {x = x, y = y, inds = inds};
			this.fails++;
			if (this.fails <= 6) {
				local t0 = AIMap.GetTileIndex(x, y + 10 * inds.len());
				this.Log("row at " + x + "," + y + " failed after " + inds.len() + ": " + AIError.GetLastErrorString()
					+ " slope=" + AITile.GetSlope(t0) + " h=" + AITile.GetMaxHeight(t0) + " buildable=" + AITile.IsBuildable(t0)
					+ " town=" + AITile.GetClosestTown(t0) + " snow=" + AITile.IsSnowTile(t0));
			}
		}
	}
	return null;
}

function MTSpaceHauler::PickEngine(cargo)
{
	local best = -1, best_speed = 0;
	foreach (e, _ in AIEngineList(AIVehicle.VT_ROAD)) {
		if (!AIEngine.IsBuildable(e) || AIEngine.GetRoadType(e) != AIRoad.ROADTYPE_ROAD) continue;
		if (!AIEngine.CanRefitCargo(e, cargo) && AIEngine.GetCargoType(e) != cargo) continue;
		if (AIEngine.GetMaxSpeed(e) > best_speed) { best = e; best_speed = AIEngine.GetMaxSpeed(e); }
	}
	return best;
}

function MTSpaceHauler::Trucks(depot, engine, cargo, from, to, n)
{
	for (local i = 0; i < n; i++) {
		local v = AIVehicle.BuildVehicle(depot, engine);
		if (!AIVehicle.IsValidVehicle(v)) return this.Fail("build truck: " + AIError.GetLastErrorString());
		if (AIVehicle.GetCapacity(v, cargo) <= 0 && !AIVehicle.RefitVehicle(v, cargo)) return this.Fail("refit: " + AIError.GetLastErrorString());
		AIOrder.AppendOrder(v, from, AIOrder.OF_FULL_LOAD_ANY);
		AIOrder.AppendOrder(v, to, AIOrder.OF_UNLOAD | AIOrder.OF_NO_LOAD);
		AIVehicle.StartStopVehicle(v);
	}
	this.Log("trucks " + n + "x " + AIEngine.GetName(engine) + " for " + AICargo.GetName(cargo));
	return true;
}

function MTSpaceHauler::Start()
{
	if (this.done) {
		this.Log("RELOADED, chain already built");
		while (true) this.Sleep(1000);
	}
	// The test GameScript transfers capital; wait for it.
	for (local i = 0; i < 200 && AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 10000000; i++) this.Sleep(1);
	if (AICompany.GetBankBalance(AICompany.COMPANY_SELF) < 10000000) return this.Fail("no capital from the test GameScript");
	local types = [this.TypeByName("Oil Wells"), this.TypeByName("Rocket Fuel Plant"), this.TypeByName("Spaceport")];
	foreach (t in types) if (t < 0) return this.Fail("industry type missing");
	local oil = this.CargoByLabel("OIL_"), rful = this.CargoByLabel("RFUL");

	local row = this.BuildRow(types);
	if (row == null) return this.Fail("no room for the chain");
	this.Log("chain at " + row.x + "," + row.y + " industries " + row.inds[0] + "," + row.inds[1] + "," + row.inds[2]);

	AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
	local rx = row.x - 2;
	local a = AIMap.GetTileIndex(rx, row.y - 1), b = AIMap.GetTileIndex(rx, row.y + 23);
	if (!AIRoad.BuildRoad(a, b)) return this.Fail("road: " + AIError.GetLastErrorString());

	local stations = [];
	foreach (i, dy in [1, 11, 21]) {
		local s = AIMap.GetTileIndex(rx, row.y + dy);
		if (!AIRoad.BuildDriveThroughRoadStation(s, s + AIMap.GetTileIndex(0, 1), AIRoad.ROADVEHTYPE_TRUCK, AIStation.STATION_NEW)) {
			return this.Fail("station " + i + ": " + AIError.GetLastErrorString());
		}
		stations.append(s);
	}
	local depot = AIMap.GetTileIndex(rx - 1, row.y + 6);
	if (!AIRoad.BuildRoadDepot(depot, AIMap.GetTileIndex(rx, row.y + 6))) return this.Fail("depot: " + AIError.GetLastErrorString());
	if (!AIRoad.BuildRoad(depot, AIMap.GetTileIndex(rx, row.y + 6))) return this.Fail("depot link: " + AIError.GetLastErrorString());

	local e_oil = this.PickEngine(oil), e_fuel = this.PickEngine(rful);
	if (e_oil < 0 || e_fuel < 0) return this.Fail("no truck for oil or rocket fuel");
	if (!this.Trucks(depot, e_oil, oil, stations[0], stations[1], 3)) return;
	if (!this.Trucks(depot, e_fuel, rful, stations[1], stations[2], 2)) return;
	this.done = true;
	this.Log("RUNNING");
	local st = [];
	foreach (t in stations) st.append(AIStation.GetStationID(t));
	while (true) {
		this.Sleep(74 * 31);
		local line = "status";
		foreach (i, s in st) line += " st" + i + "[oil " + AIStation.GetCargoWaiting(s, oil) + ", fuel " + AIStation.GetCargoWaiting(s, rful) + ", rating " + AIStation.GetCargoRating(s, oil) + "/" + AIStation.GetCargoRating(s, rful) + "]";
		foreach (v, _ in AIVehicleList()) line += " v" + v + "=" + AIVehicle.GetState(v) + "@" + AIMap.GetTileY(AIVehicle.GetLocation(v)) + ":" + AIVehicle.GetCargoLoad(v, oil) + "/" + AIVehicle.GetCargoLoad(v, rful);
		this.Log(line);
	}
}

function MTSpaceHauler::Save() { return {done = this.done}; }
function MTSpaceHauler::Load(version, data) { if ("done" in data) this.done = data.done; }
