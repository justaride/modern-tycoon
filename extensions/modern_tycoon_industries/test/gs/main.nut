/*
 * Test-only GameScript. Logs "MTS-TEST ..." lines that test/ingame_test.sh checks:
 *   - the cargos RFUL and AORE and the three industry types exist;
 *   - the refinery and spaceport can be built and accept their input cargo;
 *   - ordinary vehicles can refit to the new cargos;
 *   - with the test AI trucking oil and fuel, the fuel plant makes fuel and
 *     the fuelled spaceport makes ore, while an unfuelled spaceport makes none;
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
	// Funding a chain of industries costs more than a starting loan: give the
	// test AI's company capital (it waits for it before building).
	local funded = false;
	for (local i = 0; i < 100 && !funded; i++) {
		for (local c = GSCompany.COMPANY_FIRST; c <= GSCompany.COMPANY_LAST; c++) {
			if (GSCompany.ResolveCompanyID(c) == GSCompany.COMPANY_INVALID) continue;
			funded = GSCompany.ChangeBankBalance(c, 50000000, GSCompany.EXPENSES_OTHER, GSMap.TILE_INVALID);
		}
		if (!funded) this.Sleep(1);
	}
	if (!funded) return this.Fail("no company to fund");
	local rful = this.CargoByLabel("RFUL"), aore = this.CargoByLabel("AORE");
	if (rful < 0 || aore < 0) return this.Fail("cargo missing RFUL=" + rful + " AORE=" + aore);
	GSLog.Info("MTS-TEST cargos " + GSCargo.GetName(rful) + ", " + GSCargo.GetName(aore));

	// The refinery and a spaceport that never gets fuel. The test AI funds the
	// rest of the chain (oil wells, fuel plant, spaceport) and runs trucks on it.
	local spec = [["Asteroid Refinery", "AORE", "idle refinery"], ["Spaceport", "RFUL", "idle spaceport"]];
	foreach (item in spec) {
		local name = item[0], input = item[1];
		local t = this.TypeByName(name);
		if (t < 0) return this.Fail("industry type missing: " + name);
		local ind = this.Build(t);
		if (ind < 0) return this.Fail("could not build " + name);
		this.built[item[2]] <- ind;
		local loc = GSIndustry.GetLocation(ind);
		local acc = GSTile.GetCargoAcceptance(loc + GSMap.GetTileIndex(1, 1), this.CargoByLabel(input), 1, 1, 3);
		if (acc < 8) return this.Fail(name + " does not accept " + input + " (" + acc + ")");
		GSLog.Info("MTS-TEST built " + name + " id=" + ind + " accepts " + input + "=" + acc);
	}
	if (this.TypeByName("Rocket Fuel Plant") < 0) return this.Fail("industry type missing: Rocket Fuel Plant");

	foreach (pair in [[rful, "RFUL"], [aore, "AORE"]]) {
		local names = this.Refittable(pair[0]);
		if (names.len() == 0) return this.Fail("no vehicle can carry " + pair[1]);
		local s = "";
		foreach (i, n in names) if (i < 4) s += (i ? ", " : "") + n;
		GSLog.Info("MTS-TEST refit " + pair[1] + ": " + names.len() + " engines (" + s + ")");
	}

	// Watch the chain month by month: fuel made, fuel delivered, ore made.
	local idle_sp = this.built["idle spaceport"];
	local fuel_made = 0, ore_made = 0, idle_ore = 0;
	for (local m = 0; m < 10; m++) {
		this.Sleep(74 * 31);
		foreach (ind, _ in GSIndustryList()) {
			local name = GSIndustryType.GetName(GSIndustry.GetIndustryType(ind));
			if (name == "Rocket Fuel Plant") {
				if (!("fuel plant" in this.built)) this.built["fuel plant"] <- ind;
				fuel_made += GSIndustry.GetLastMonthProduction(ind, rful);
			} else if (name == "Spaceport") {
				local p = GSIndustry.GetLastMonthProduction(ind, aore);
				if (ind == idle_sp) { idle_ore += p; continue; }
				if (!("spaceport" in this.built)) this.built["spaceport"] <- ind;
				ore_made += p;
			}
		}
		GSLog.Info("MTS-TEST month " + m + ": rocket fuel " + fuel_made + ", asteroid ore " + ore_made + ", idle spaceport " + idle_ore);
		if (fuel_made > 0 && ore_made > 0) break;
	}
	if (idle_ore != 0) return this.Fail("a spaceport without fuel produced " + idle_ore + " t ore");
	if (fuel_made <= 0) return this.Fail("the fuel plant made no rocket fuel (oil not delivered?)");
	if (ore_made <= 0) return this.Fail("the fuelled spaceport made no asteroid ore");
	GSLog.Info("MTS-TEST RUN PASS fuel " + fuel_made + " -> ore " + ore_made + ", unfuelled spaceport 0");
	while (true) this.Sleep(1000);
}

function MTSpaceTest::CheckReload()
{
	this.Sleep(1);
	// Keys are roles ("idle spaceport"); values are industry ids recorded before saving.
	local types = {};
	types["idle refinery"] <- "Asteroid Refinery";
	types["idle spaceport"] <- "Spaceport";
	types["fuel plant"] <- "Rocket Fuel Plant";
	types["spaceport"] <- "Spaceport";
	foreach (role, ind in this.built) {
		if (!GSIndustry.IsValidIndustry(ind) || GSIndustryType.GetName(GSIndustry.GetIndustryType(ind)) != types[role]) {
			return this.Fail("lost " + role + " after reload");
		}
	}
	GSLog.Info("MTS-TEST RELOAD ok " + this.built.len() + " industries");
	while (true) this.Sleep(1000);
}

function MTSpaceTest::Save() { return {built = this.built}; }
function MTSpaceTest::Load(version, data) { this.built = data.built; this.reloaded = true; }
