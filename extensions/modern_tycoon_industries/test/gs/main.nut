/*
 * Test-only GameScript. Logs "MTS-TEST ..." lines that test/ingame_test.sh checks:
 *   - the cargos RFUL and AORE and the three industry types exist;
 *   - each industry can be built, and accepts its input cargo;
 *   - ordinary vehicles can refit to the new cargos;
 *   - the spaceport produces asteroid ore on its own;
 *   - after a reload the built industries are still there.
 * SPDX-License-Identifier: GPL-2.0-only
 */
class MTSpaceTest extends GSController {
	built = null;      // industry type name -> industry id
	reloaded = false;
	constructor() { this.built = {}; }
}

function MTSpaceTest::Fail(msg) { GSLog.Error("MTS-TEST FAIL " + msg); }

function MTSpaceTest::CargoByLabel(label)
{
	foreach (c, _ in GSCargoList()) if (GSCargo.GetCargoLabel(c) == label) return c;
	return -1;
}

function MTSpaceTest::TypeByName(name)
{
	foreach (t, _ in GSIndustryTypeList()) if (GSIndustryType.GetName(t) == name) return t;
	return -1;
}

function MTSpaceTest::Build(type)
{
	local size = GSMap.GetMapSizeX() * GSMap.GetMapSizeY();
	for (local i = 0; i < 4000; i++) {
		local tile = GSBase.RandRange(size);
		if (GSIndustryType.BuildIndustry(type, tile)) {
			local list = GSIndustryList();
			foreach (ind, _ in list) {
				if (GSIndustry.GetIndustryType(ind) == type && GSIndustry.GetLocation(ind) == tile) return ind;
			}
		}
	}
	return -1;
}

function MTSpaceTest::Refittable(cargo)
{
	local names = [];
	foreach (vt in [GSVehicle.VT_RAIL, GSVehicle.VT_ROAD, GSVehicle.VT_WATER]) {
		foreach (e, _ in GSEngineList(vt)) {
			if (GSEngine.CanRefitCargo(e, cargo)) names.append(GSEngine.GetName(e));
		}
	}
	return names;
}

function MTSpaceTest::Start()
{
	if (this.reloaded) return this.CheckReload();
	this.Sleep(1);
	local rful = this.CargoByLabel("RFUL"), aore = this.CargoByLabel("AORE");
	if (rful < 0 || aore < 0) return this.Fail("cargo missing RFUL=" + rful + " AORE=" + aore);
	GSLog.Info("MTS-TEST cargos " + GSCargo.GetName(rful) + ", " + GSCargo.GetName(aore));

	local spec = [["Rocket Fuel Plant", "OIL_"], ["Spaceport", "RFUL"], ["Asteroid Refinery", "AORE"]];
	foreach (pair in spec) {
		local name = pair[0], input = pair[1];
		local t = this.TypeByName(name);
		if (t < 0) return this.Fail("industry type missing: " + name);
		local ind = this.Build(t);
		if (ind < 0) return this.Fail("could not build " + name);
		this.built[name] <- ind;
		local loc = GSIndustry.GetLocation(ind);
		local acc = GSTile.GetCargoAcceptance(loc + GSMap.GetTileIndex(1, 1), this.CargoByLabel(input), 1, 1, 3);
		if (acc < 8) return this.Fail(name + " does not accept " + input + " (" + acc + ")");
		GSLog.Info("MTS-TEST built " + name + " id=" + ind + " accepts " + input + "=" + acc);
	}

	foreach (pair in [[rful, "RFUL"], [aore, "AORE"]]) {
		local names = this.Refittable(pair[0]);
		if (names.len() == 0) return this.Fail("no vehicle can carry " + pair[1]);
		local s = "";
		foreach (i, n in names) if (i < 4) s += (i ? ", " : "") + n;
		GSLog.Info("MTS-TEST refit " + pair[1] + ": " + names.len() + " engines (" + s + ")");
	}

	// Three months of production at the spaceport (base production, no deliveries).
	local sp = this.built["Spaceport"];
	local total = 0;
	for (local m = 0; m < 3; m++) {
		this.Sleep(74 * 31);
		total += GSIndustry.GetLastMonthProduction(sp, aore);
	}
	if (total <= 0) return this.Fail("spaceport produced no asteroid ore");
	GSLog.Info("MTS-TEST RUN PASS spaceport produced " + total + " t asteroid ore in 3 months");
	while (true) this.Sleep(1000);
}

function MTSpaceTest::CheckReload()
{
	this.Sleep(1);
	foreach (name, ind in this.built) {
		if (!GSIndustry.IsValidIndustry(ind) || GSIndustryType.GetName(GSIndustry.GetIndustryType(ind)) != name) {
			return this.Fail("lost " + name + " after reload");
		}
	}
	GSLog.Info("MTS-TEST RELOAD ok " + this.built.len() + " industries");
	while (true) this.Sleep(1000);
}

function MTSpaceTest::Save() { return {built = this.built}; }
function MTSpaceTest::Load(version, data) { this.built = data.built; this.reloaded = true; }
