/*
 * Test-only GameScript: every quarter, log "MTV-CENSUS <year> <engine>=<count>, ..."
 * over all companies' trains, wagons included.
 * SPDX-License-Identifier: GPL-2.0-only
 */
class MTFleetCensus extends GSController {}

function MTFleetCensus::Start()
{
	while (true) {
		this.Sleep(74 * 91);
		local counts = {};
		foreach (veh, dummy in GSVehicleList()) {
			if (GSVehicle.GetVehicleType(veh) != GSVehicle.VT_RAIL) continue;
			for (local i = 0; i < GSVehicle.GetNumWagons(veh); i++) {
				local name = GSEngine.GetName(GSVehicle.GetWagonEngineType(veh, i));
				if (!(name in counts)) counts[name] <- 0;
				counts[name]++;
			}
		}
		local line = "";
		foreach (name, n in counts) line += (line == "" ? "" : ", ") + name + "=" + n;
		GSLog.Info("MTV-CENSUS " + GSDate.GetYear(GSDate.GetCurrentDate()) + " " + line);
	}
}

function MTFleetCensus::Save() { return {}; }
function MTFleetCensus::Load(version, data) {}
