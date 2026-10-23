/*
 * Shared personality traits for Modern Tycoon AI players.
 *
 * Every Modern Tycoon AI keeps an identical copy of this file, so a
 * "cautious" airline and a "cautious" railway behave the same way.
 * The smoke tests check that the copies stay identical.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

const MT_PERSONALITY_CAUTIOUS = 0;
const MT_PERSONALITY_BALANCED = 1;
const MT_PERSONALITY_AGGRESSIVE = 2;
const MT_PERSONALITY_RANDOM = 3;

/* Settings label table, for AddLabels("personality", ...). */
MT_PERSONALITY_LABELS <- {
	_0 = "Forsiktig (cautious)",
	_1 = "Balansert (balanced)",
	_2 = "Aggressiv (aggressive)",
	_3 = "Tilfeldig (random)"
};

/*
 * reserve        Cash we always keep in the bank.
 * loan_share     Percent of the maximum loan we are willing to use.
 * retry_days     Days to wait after a failed expansion attempt.
 * growth_x10     Add a vehicle when waiting cargo exceeds capacity * growth_x10 / 10.
 * retire_years   Years a vehicle may lose money before it is retired.
 * route_cap      Upper bound on routes, on top of the max_routes setting.
 * repay_x        Repay loan when cash exceeds reserve * repay_x.
 * upgrade_x      Upgrade (bigger stations, better vehicles) when spendable >= cost * upgrade_x.
 * extra_vehicles Extra specialised vehicles per route (e.g. mail planes).
 * station_length Platform length for rail lines.
 */
MT_TRAITS <- [
	{ name = "Forsiktig",  reserve = 40000, loan_share = 60,  retry_days = 45, growth_x10 = 30,
	  retire_years = 3, route_cap = 6,  repay_x = 1, upgrade_x = 4, extra_vehicles = 1, station_length = 4 },
	{ name = "Balansert",  reserve = 25000, loan_share = 80,  retry_days = 15, growth_x10 = 20,
	  retire_years = 2, route_cap = 12, repay_x = 3, upgrade_x = 3, extra_vehicles = 1, station_length = 5 },
	{ name = "Aggressiv",  reserve = 10000, loan_share = 100, retry_days = 7,  growth_x10 = 12,
	  retire_years = 1, route_cap = 40, repay_x = 6, upgrade_x = 2, extra_vehicles = 2, station_length = 6 }
];

/* Turn the setting value into a concrete personality; "random" is rolled once. */
function MT_ResolvePersonality(setting)
{
	if (setting >= MT_PERSONALITY_CAUTIOUS && setting <= MT_PERSONALITY_AGGRESSIVE) return setting;
	return AIBase.RandRange(3);
}

function MT_Traits(personality)
{
	if (personality < 0 || personality >= MT_TRAITS.len()) personality = MT_PERSONALITY_BALANCED;
	return MT_TRAITS[personality];
}

/* Money we may borrow right now, given the personality's loan appetite. */
function MT_LoanHeadroom(traits)
{
	local allowed = AICompany.GetMaxLoanAmount() * traits.loan_share / 100;
	local headroom = allowed - AICompany.GetLoanAmount();
	return headroom > 0 ? headroom : 0;
}

/* Make sure `amount` is in the bank, borrowing within the personality's limits. */
function MT_EnsureCash(amount, traits, use_loan)
{
	local cash = AICompany.GetBankBalance(AICompany.COMPANY_SELF);
	if (cash >= amount + traits.reserve) return true;
	if (!use_loan) return cash >= amount;

	local allowed = AICompany.GetMaxLoanAmount() * traits.loan_share / 100;
	local wanted = AICompany.GetLoanAmount() + amount + traits.reserve - cash;
	if (wanted > allowed) wanted = allowed;
	if (wanted <= AICompany.GetLoanAmount()) return cash >= amount;
	if (wanted >= AICompany.GetMaxLoanAmount()) {
		AICompany.SetLoanAmount(AICompany.GetMaxLoanAmount());
	} else {
		AICompany.SetMinimumLoanAmount(wanted);
	}
	return AICompany.GetBankBalance(AICompany.COMPANY_SELF) >= amount;
}

/* What could be spent now without touching the reserve. */
function MT_SpendableMoney(traits, use_loan)
{
	local cash = AICompany.GetBankBalance(AICompany.COMPANY_SELF);
	if (use_loan) cash += MT_LoanHeadroom(traits);
	return cash - traits.reserve;
}

/* Repay in loan-sized steps once cash clearly exceeds what the personality wants to keep. Returns true when debt free. */
function MT_RepayLoan(traits)
{
	local loan = AICompany.GetLoanAmount();
	if (loan == 0) return false;
	local interval = AICompany.GetLoanInterval();
	local spare = AICompany.GetBankBalance(AICompany.COMPANY_SELF) - traits.reserve * traits.repay_x;
	if (spare < interval) return false;
	local repay = (spare / interval) * interval;
	if (repay > loan) repay = loan;
	return AICompany.SetLoanAmount(loan - repay) && loan - repay == 0;
}
