/*
 * This file is part of OpenTTD.
 * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.
 * OpenTTD is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with OpenTTD. If not, see <https://www.gnu.org/licenses/old-licenses/gpl-2.0>.
 */

/** @file company_exchange.cpp Test deterministic company exchange arithmetic. */

#include "../stdafx.h"

#include "../3rdparty/catch2/catch.hpp"

#include "../company_exchange_base.h"
#include "../company_exchange_func.h"

#include "../safeguards.h"

using namespace CompanyExchange;

/** Keep the exchange pools isolated from every other test case. */
struct CompanyExchangePoolGuard {
	CompanyExchangePoolGuard()
	{
		_holding_pool.CleanPool();
		_security_pool.CleanPool();
	}

	~CompanyExchangePoolGuard()
	{
		_holding_pool.CleanPool();
		_security_pool.CleanPool();
	}
};

TEST_CASE("Company exchange sparse holding lookup")
{
	CompanyExchangePoolGuard guard;

	REQUIRE(Security::CanAllocateItem(2));
	Security *first_security = Security::Create(SecurityKind::Company, 1, 10);
	Security *second_security = Security::Create(SecurityKind::Company, 2, 20);

	REQUIRE(Holding::CanAllocateItem(3));
	Holding *first_holding = Holding::Create(first_security->index, CompanyID{0});
	Holding *second_holding = Holding::Create(first_security->index, CompanyID{1});
	Holding *third_holding = Holding::Create(second_security->index, CompanyID{0});

	CHECK(FindHolding(first_security->index, CompanyID{0}) == first_holding);
	CHECK(FindHolding(first_security->index, CompanyID{1}) == second_holding);
	CHECK(FindHolding(second_security->index, CompanyID{0}) == third_holding);
	CHECK(FindHolding(second_security->index, CompanyID{1}) == nullptr);

	delete first_holding;
	CHECK(FindHolding(first_security->index, CompanyID{0}) == nullptr);
	CHECK(FindHolding(second_security->index, CompanyID{0}) == third_holding);
}

TEST_CASE("Company exchange target market cap")
{
	CHECK(CalculateTargetMarketCap(1'000'000, 100'000, 100'000) == 1'600'000);
	CHECK(CalculateTargetMarketCap(1'000'000, 1'000'000, 100'000) == 5'000'000);
	CHECK(CalculateTargetMarketCap(1'000'000, -1'000'000, 100'000) == 500'000);
	CHECK(CalculateTargetMarketCap(10'000, -10'000, 100'000) == 100'000);

	CHECK_FALSE(CalculateTargetMarketCap(-1, 0, 1).has_value());
	CHECK_FALSE(CalculateTargetMarketCap(1, 0, 0).has_value());
	CHECK(CalculateTargetMarketCap(1, std::numeric_limits<int64_t>::max(), 1) == 5);
	CHECK(CalculateTargetMarketCap(1, std::numeric_limits<int64_t>::min(), 1) == 1);
	CHECK(CalculateTargetMarketCap(1'000, std::numeric_limits<int64_t>::min(), 1) == 500);
	CHECK(CalculateTargetMarketCap(std::numeric_limits<int64_t>::max(), 0, 1) == std::numeric_limits<int64_t>::max());
	CHECK_FALSE(CalculateTargetMarketCap(std::numeric_limits<int64_t>::max(), std::numeric_limits<int64_t>::max(), 1).has_value());
}

TEST_CASE("Company exchange fixed-point target and monthly movement")
{
	CHECK(CalculateTargetUnitPrice(10'000) == PRICE_SCALE);
	CHECK(CalculateTargetUnitPrice(1'000'000) == 25'600);
	CHECK_FALSE(CalculateTargetUnitPrice(0).has_value());
	CHECK_FALSE(CalculateTargetUnitPrice(1).has_value());
	CHECK(CalculateTargetUnitPrice(std::numeric_limits<int64_t>::max()).has_value());

	CHECK(MovePriceTowardsTarget(10'000, 20'000) == 11'000);
	CHECK(MovePriceTowardsTarget(10'000, 1'000) == 9'000);
	CHECK(MovePriceTowardsTarget(10'000, 10'403) == 10'100);
	CHECK(MovePriceTowardsTarget(10'000, 9'597) == 9'900);
	CHECK(MovePriceTowardsTarget(10'000, 10'003) == 10'000);
	CHECK(MovePriceTowardsTarget(9, 20) == 10);
	CHECK(MovePriceTowardsTarget(9, 1) == 8);
	CHECK_FALSE(MovePriceTowardsTarget(0, 1).has_value());
	CHECK_FALSE(MovePriceTowardsTarget(1, 0).has_value());
}

TEST_CASE("Company exchange bid ask and fee rounding")
{
	auto quote = CalculateQuote(10'001);
	REQUIRE(quote.has_value());
	CHECK(quote->bid == 9'950);
	CHECK(quote->ask == 10'052);
	CHECK(quote->bid < 10'001);
	CHECK(quote->ask > 10'001);

	CHECK(CalculateTransactionFee(0, 25) == 0);
	CHECK(CalculateTransactionFee(1, 25) == 1);
	CHECK(CalculateTransactionFee(10'000, 25) == 25);
	CHECK(CalculateTransactionFee(10'001, 25) == 26);
	CHECK(CalculateTransactionFee(10'001, 0) == 0);
	CHECK_FALSE(CalculateTransactionFee(-1, 25).has_value());
	CHECK_FALSE(CalculateTransactionFee(1, 10'001).has_value());
	CHECK_FALSE(CalculateQuote(1).has_value());
	CHECK_FALSE(CalculateQuote(std::numeric_limits<int64_t>::max()).has_value());
}

TEST_CASE("Company exchange buy and sell settlement conserves every leg")
{
	auto buy = CalculateBuySettlement(2'560, 100, 25);
	REQUIRE(buy.has_value());
	CHECK(buy->gross == 1'000);
	CHECK(buy->fee == 3);
	CHECK(buy->side == TradeSide::Buy);
	CHECK(buy->quantity == 100);
	CHECK(buy->trader_cash_delta == -1'003);
	CHECK(buy->market_maker_cash_delta == 1'000);
	CHECK(buy->fee_reserve_delta == 3);
	CHECK(buy->public_inventory_delta == -100);
	CHECK(buy->held_units_delta == 100);
	CHECK(IsSettlementConserved(*buy));

	auto sell = CalculateSellSettlement(2'560, 100, 25);
	REQUIRE(sell.has_value());
	CHECK(sell->gross == 1'000);
	CHECK(sell->fee == 3);
	CHECK(sell->side == TradeSide::Sell);
	CHECK(sell->quantity == 100);
	CHECK(sell->trader_cash_delta == 997);
	CHECK(sell->market_maker_cash_delta == -1'000);
	CHECK(sell->fee_reserve_delta == 3);
	CHECK(sell->public_inventory_delta == 100);
	CHECK(sell->held_units_delta == -100);
	CHECK(IsSettlementConserved(*sell));

	CHECK_FALSE(CalculateBuySettlement(1, 0, 25).has_value());
	CHECK_FALSE(CalculateSellSettlement(1, 1, 25).has_value());
	CHECK_FALSE(CalculateBuySettlement(std::numeric_limits<int64_t>::max(), std::numeric_limits<uint16_t>::max(), 25).has_value());

	const TradeSettlement forged_cash{TradeSide::Buy, 100, 100, 0, 100, -100, 0, 0, 0};
	const TradeSettlement forged_units{TradeSide::Buy, 100, 100, 0, 0, 0, 0, -100, 100};
	const TradeSettlement invalid_side{static_cast<TradeSide>(255), 100, 100, 0, -100, 100, 0, -100, 100};
	CHECK_FALSE(IsSettlementConserved(forged_cash));
	CHECK_FALSE(IsSettlementConserved(forged_units));
	CHECK_FALSE(IsSettlementConserved(invalid_side));
}

TEST_CASE("Company exchange zero-fee round trip loses the spread")
{
	auto quote = CalculateQuote(2'560);
	REQUIRE(quote.has_value());
	auto buy = CalculateBuySettlement(quote->ask, 100, 0);
	auto sell = CalculateSellSettlement(quote->bid, 100, 0);
	REQUIRE(buy.has_value());
	REQUIRE(sell.has_value());
	CHECK(-buy->trader_cash_delta > sell->trader_cash_delta);
	CHECK(buy->fee == 0);
	CHECK(sell->fee == 0);
}

TEST_CASE("Company exchange proportional cost basis preserves every Money unit")
{
	CHECK(AllocateProportionalCostBasis(1'000, 100, 25) == 250);
	CHECK(AllocateProportionalCostBasis(5, 3, 1) == 2);
	CHECK(AllocateProportionalCostBasis(3, 2, 1) == 2);
	CHECK(AllocateProportionalCostBasis(1, 2, 1) == 1);
	CHECK(AllocateProportionalCostBasis(5, 3, 3) == 5);
	CHECK_FALSE(AllocateProportionalCostBasis(-1, 1, 1).has_value());
	CHECK_FALSE(AllocateProportionalCostBasis(1, 0, 1).has_value());
	CHECK_FALSE(AllocateProportionalCostBasis(1, 1, 0).has_value());
	CHECK_FALSE(AllocateProportionalCostBasis(1, 1, 2).has_value());

	for (uint16_t initial_units = 1; initial_units <= 64; ++initial_units) {
		for (int64_t initial_basis = 0; initial_basis <= 256; ++initial_basis) {
			uint16_t remaining_units = initial_units;
			int64_t remaining_basis = initial_basis;
			int64_t allocated_total = 0;
			while (remaining_units > 0) {
				auto allocated = AllocateProportionalCostBasis(remaining_basis, remaining_units, 1);
				REQUIRE(allocated.has_value());
				allocated_total += *allocated;
				remaining_basis -= *allocated;
				--remaining_units;
			}
			CHECK(allocated_total == initial_basis);
			CHECK(remaining_basis == 0);
		}
	}
}

TEST_CASE("Company exchange holder cap")
{
	CHECK(CanAcquireCompanyEquity(0, COMPANY_EQUITY_INITIAL_LOT));
	CHECK(CanAcquireCompanyEquity(COMPANY_EQUITY_HOLDER_CAP - 1, 1));
	CHECK_FALSE(CanAcquireCompanyEquity(COMPANY_EQUITY_HOLDER_CAP, 1));
	CHECK_FALSE(CanAcquireCompanyEquity(COMPANY_EQUITY_HOLDER_CAP + 1, 1));
	CHECK_FALSE(CanAcquireCompanyEquity(0, 0));
	CHECK_FALSE(CanAcquireCompanyEquity(std::numeric_limits<uint32_t>::max(), std::numeric_limits<uint32_t>::max()));
}

TEST_CASE("Company exchange ledger applies atomically and conserves totals")
{
	LedgerState opening{10'000, 20'000, 0, COMPANY_EQUITY_UNITS, 0};
	CHECK(IsLedgerValid(opening));

	auto buy = CalculateBuySettlement(2'560, 100, 25);
	REQUIRE(buy.has_value());
	auto after_buy = ApplySettlement(opening, *buy);
	REQUIRE(after_buy.has_value());
	CHECK(after_buy->trader_cash == 8'997);
	CHECK(after_buy->market_maker_cash == 21'000);
	CHECK(after_buy->fee_reserve == 3);
	CHECK(after_buy->public_inventory == 9'900);
	CHECK(after_buy->held_units == 100);
	CHECK(IsLedgerConserved(opening, *after_buy));

	auto sell = CalculateSellSettlement(2'560, 100, 25);
	REQUIRE(sell.has_value());
	auto after_sell = ApplySettlement(*after_buy, *sell);
	REQUIRE(after_sell.has_value());
	CHECK(IsLedgerConserved(*after_buy, *after_sell));
	CHECK(IsLedgerConserved(opening, *after_sell));
	CHECK(after_sell->public_inventory == COMPANY_EQUITY_UNITS);
	CHECK(after_sell->held_units == 0);

	LedgerState malformed{10, 10, 0, COMPANY_EQUITY_UNITS, 1};
	CHECK_FALSE(IsLedgerValid(malformed));
	CHECK_FALSE(ApplySettlement(malformed, *buy).has_value());

	LedgerState insufficient_cash{1, 20'000, 0, COMPANY_EQUITY_UNITS, 0};
	CHECK_FALSE(ApplySettlement(insufficient_cash, *buy).has_value());

	LedgerState overflowing{std::numeric_limits<int64_t>::max(), 1, 0, COMPANY_EQUITY_UNITS, 0};
	CHECK(IsLedgerConserved(overflowing, overflowing));
	LedgerState redistributed{std::numeric_limits<int64_t>::max() - 1, 2, 0, COMPANY_EQUITY_UNITS, 0};
	CHECK(IsLedgerConserved(overflowing, redistributed));
	LedgerState changed_without_conservation{std::numeric_limits<int64_t>::max() - 1, 1, 0, COMPANY_EQUITY_UNITS, 0};
	CHECK_FALSE(IsLedgerConserved(overflowing, changed_without_conservation));
}
