/*
 * Allvei Konsern - industry funding. When the group has spare money it
 * builds a customer (for example a factory or power station) close to a busy
 * producer that has no customer within reach, so the next planning round
 * finds a short, profitable route. Rich groups also prospect for new raw
 * industries when the map has few of a kind.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

const AK_FUND_MIN_PRODUCTION = 40;
const AK_FUND_REACH = 110;          // A customer closer than this counts as "within reach".
const AK_FUND_SITE_TRIES = 60;

/* Industry types we may fund that accept `cargo`, cheapest first. */
function AllveiKonsern::FundableAcceptors(cargo)
{
	local result = [];
	foreach (type, dummy in AIIndustryTypeList()) {
		if (!AIIndustryType.CanBuildIndustry(type)) continue;
		if (!AIIndustryType.GetAcceptedCargo(type).HasItem(cargo)) continue;
		result.push([type, AIIndustryType.GetConstructionCost(type)]);
	}
	result.sort(function(a, b) { return AK_Cmp(a[1], b[1]); });
	return result;
}

/* Place an industry of `type` 25-60 tiles from `near`. Returns true on success. */
function AllveiKonsern::PlaceIndustryNear(type, near)
{
	local x = AIMap.GetTileX(near), y = AIMap.GetTileY(near);
	for (local i = 0; i < AK_FUND_SITE_TRIES; i++) {
		local dist = 25 + AIBase.RandRange(36);
		local dx = AIBase.RandRange(dist + 1);
		local dy = dist - dx;
		if (AIBase.Chance(1, 2)) dx = -dx;
		if (AIBase.Chance(1, 2)) dy = -dy;
		local tile = AK_Tile(x + dx, y + dy);
		if (AIIndustryType.BuildIndustry(type, tile)) return true;
		if (AIError.GetLastError() == AIError.ERR_NOT_ENOUGH_CASH) return false;
	}
	return false;
}

function AllveiKonsern::FundIndustries()
{
	local spendable = this.SpendableMoney();
	/* Only spend on industry when the transport side has money left over. */
	if (spendable < 200000 || AICompany.GetLoanAmount() > AICompany.GetMaxLoanAmount() / 2) return;
	local budget = spendable / 4;

	/* 1. A customer for the busiest stranded producer. */
	local sources = AIIndustryList();
	sources.Valuate(AK_IndustryTotalProduction);
	sources.KeepAboveValue(AK_FUND_MIN_PRODUCTION - 1);
	sources.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
	foreach (src, dummy in sources) {
		if (this.IsBlocked("f" + src) || AIIndustry.IsBuiltOnWater(src)) continue;
		local src_tile = AIIndustry.GetLocation(src);
		foreach (cargo, dummy2 in AICargoList_IndustryProducing(src)) {
			if (!AICargo.IsFreight(cargo) || AIIndustry.GetLastMonthProduction(src, cargo) < AK_FUND_MIN_PRODUCTION) continue;
			if (AICargo.GetTownEffect(cargo) != AICargo.TE_NONE) continue;   // Towns take these.
			local dests = AIIndustryList_CargoAccepting(cargo);
			dests.Valuate(AIIndustry.GetDistanceManhattanToTile, src_tile);
			dests.KeepBelowValue(AK_FUND_REACH);
			if (!dests.IsEmpty()) continue;

			foreach (item in this.FundableAcceptors(cargo)) {
				if (item[1] > budget) continue;
				if (!this.EnsureCash(item[1])) return;
				if (this.PlaceIndustryNear(item[0], src_tile)) {
					AILog.Info("Allvei finansierer " + AIIndustryType.GetName(item[0]) + " som kunde for " +
							AICargo.GetCargoLabel(cargo) + " fra " + AIIndustry.GetName(src) + ".");
					this.Block("f" + src, 2 * AK_DAYS_BEFORE_RETRY);
					return;
				}
			}
			this.Block("f" + src);
		}
	}

	/* 2. Prospect a raw industry of a type that is rare on this map. */
	if (spendable < 600000 || this.IsBlocked("prospect")) return;
	this.Block("prospect", 365);
	local best_type = null, fewest = 1000000;
	foreach (type, dummy in AIIndustryTypeList()) {
		if (!AIIndustryType.IsRawIndustry(type) || !AIIndustryType.CanProspectIndustry(type)) continue;
		if (AIIndustryType.GetConstructionCost(type) > budget) continue;
		local count = 0;
		foreach (ind, dummy2 in AIIndustryList()) if (AIIndustry.GetIndustryType(ind) == type) count++;
		if (count < fewest) {
			fewest = count;
			best_type = type;
		}
	}
	if (best_type != null && this.EnsureCash(AIIndustryType.GetConstructionCost(best_type)) && AIIndustryType.ProspectIndustry(best_type)) {
		AILog.Info("Allvei leter etter ny " + AIIndustryType.GetName(best_type) + ".");
	}
}
