/*
 * Test-only AI for the Modern Tycoon Trains NewGRF. Logs lines starting
 * with "MTV-TEST" that test/ingame_test.sh checks.
 * SPDX-License-Identifier: GPL-2.0-only
 */
const LINE_LENGTH = 12;

class MTVehicleTest extends AIController {
	train = null;
	depot = null;
	loaded = false;
}

function MTVehicleTest::Find(name)
{
	foreach (engine, dummy in AIEngineList(AIVehicle.VT_RAIL)) {
		if (AIEngine.GetName(engine) == name) return engine;
	}
	return null;
}

function MTVehicleTest::Fail(msg)
{
	AILog.Error("MTV-TEST FAIL " + msg + " (" + AIError.GetLastErrorString() + ")");
	while (true) this.Sleep(1000);
}

/* A flat, buildable strip of LINE_LENGTH tiles along the x axis. */
function MTVehicleTest::FindStrip()
{
	for (local y = 20; y < AIMap.GetMapSizeY() - 20; y += 3) {
		for (local x = 20; x < AIMap.GetMapSizeX() - 20 - LINE_LENGTH; x += 2) {
			local ok = true;
			for (local i = 0; i < LINE_LENGTH && ok; i++) {
				local t = AIMap.GetTileIndex(x + i, y);
				ok = AITile.IsBuildable(t) && AITile.GetSlope(t) == AITile.SLOPE_FLAT;
			}
			if (ok) return AIMap.GetTileIndex(x, y);
		}
	}
	return null;
}

function MTVehicleTest::Start()
{
	if (this.loaded) {
		local ok = this.train != null && AIVehicle.IsValidVehicle(this.train) &&
				AIEngine.GetName(AIVehicle.GetEngineType(this.train)) == "Tinde DM6 Dual-Mode";
		AILog.Info("MTV-TEST RELOAD " + (ok ? "ok" : "lost") + " train=" + this.train);
		while (true) this.Sleep(1000);
	}

	local loco = this.Find("Tinde DM6 Dual-Mode");
	local wagon = this.Find("Tinde Bulk Hopper");
	if (loco == null || wagon == null) this.Fail("engines not found");
	AILog.Info("MTV-TEST ENGINES loco=" + loco + " buildable=" + AIEngine.IsBuildable(loco) +
			" power_hp=" + AIEngine.GetPower(loco) + " speed=" + AIEngine.GetMaxSpeed(loco) +
			" wagon=" + wagon + " capacity=" + AIEngine.GetCapacity(wagon));

	local railtype = null;
	foreach (rt, dummy in AIRailTypeList()) {
		if (AIEngine.HasPowerOnRail(loco, rt) && AIEngine.CanRunOnRail(wagon, rt)) { railtype = rt; break; }
	}
	if (railtype == null) this.Fail("no rail type");
	AIRail.SetCurrentRailType(railtype);
	AICompany.SetLoanAmount(AICompany.GetMaxLoanAmount());

	local start = this.FindStrip();
	if (start == null) this.Fail("no flat strip");
	this.depot = start;
	if (!AIRail.BuildRailDepot(start, start + AIMap.GetTileIndex(1, 0))) this.Fail("depot");
	for (local i = 1; i < LINE_LENGTH - 1; i++) {
		local t = start + AIMap.GetTileIndex(i, 0);
		if (!AIRail.BuildRail(t - AIMap.GetTileIndex(1, 0), t, t + AIMap.GetTileIndex(1, 0))) this.Fail("rail " + i);
	}
	AILog.Info("MTV-TEST LINE depot=" + start + " x=" + AIMap.GetTileX(start) + " y=" + AIMap.GetTileY(start));

	this.train = AIVehicle.BuildVehicle(start, loco);
	if (!AIVehicle.IsValidVehicle(this.train)) this.Fail("build loco");
	for (local i = 0; i < 3; i++) {
		local w = AIVehicle.BuildVehicle(start, wagon);
		if (!AIVehicle.IsValidVehicle(w)) this.Fail("build wagon");
		if (!AIVehicle.MoveWagon(w, 0, this.train, AIVehicle.GetNumWagons(this.train) - 1)) this.Fail("attach wagon");
	}

	local coal = null, ore = null;
	foreach (c, dummy in AICargoList()) {
		if (AICargo.GetCargoLabel(c) == "COAL") coal = c;
		if (AICargo.GetCargoLabel(c) == "IORE") ore = c;
	}
	AILog.Info("MTV-TEST CONSIST parts=" + AIVehicle.GetNumWagons(this.train) +
			" length16=" + AIVehicle.GetLength(this.train) + " coal_capacity=" + AIVehicle.GetCapacity(this.train, coal));
	if (ore != null) {
		if (!AIVehicle.RefitVehicle(this.train, ore)) this.Fail("refit to IORE");
		AILog.Info("MTV-TEST REFIT IORE capacity=" + AIVehicle.GetCapacity(this.train, ore));
	}

	if (!AIVehicle.StartStopVehicle(this.train)) this.Fail("start");
	local max_dist = 0, max_speed = 0;
	for (local day = 0; day < 60; day++) {
		this.Sleep(74);
		local d = AIMap.DistanceManhattan(AIVehicle.GetLocation(this.train), start);
		if (d > max_dist) max_dist = d;
		local s = AIVehicle.GetCurrentSpeed(this.train);
		if (s > max_speed) max_speed = s;
	}
	local result = (max_dist >= 5 && max_speed > 0) ? "PASS" : "FAIL";
	AILog.Info("MTV-TEST RUN " + result + " max_tiles_from_depot=" + max_dist + " max_speed_kmh=" + max_speed);
	while (true) this.Sleep(1000);
}

function MTVehicleTest::Save()
{
	return { train = this.train == null ? -1 : this.train };
}

function MTVehicleTest::Load(version, data)
{
	this.loaded = true;
	if ("train" in data && data.train >= 0) this.train = data.train;
}
