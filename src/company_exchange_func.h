/*
 * This file is part of OpenTTD.
 * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.
 * OpenTTD is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with OpenTTD. If not, see <https://www.gnu.org/licenses/old-licenses/gpl-2.0>.
 */

/** @file company_exchange_func.h Pure deterministic arithmetic for the company exchange. */

#ifndef COMPANY_EXCHANGE_FUNC_H
#define COMPANY_EXCHANGE_FUNC_H

#include "company_exchange_type.h"

#include <algorithm>
#include <cstdint>
#include <limits>
#include <optional>

namespace CompanyExchange {

static constexpr SecurityPrice PRICE_SCALE = SECURITY_PRICE_ONE; ///< Scaling factor for fixed-point security prices.
static constexpr int64_t BASIS_POINTS = 10000;
static constexpr int64_t HALF_SPREAD_BASIS_POINTS = 50;
static constexpr int64_t MONTHLY_TARGET_DIVISOR = 4;
static constexpr int64_t MONTHLY_MOVE_CAP_DIVISOR = 10;

/** Bid and ask around a displayed mid-price. */
struct Quote {
	SecurityPrice bid;
	SecurityPrice ask;
};

/** Every ledger delta produced by one immediately settled trade. */
struct TradeSettlement {
	TradeSide side;
	uint16_t quantity;
	int64_t gross;
	int64_t fee;
	int64_t trader_cash_delta;
	int64_t market_maker_cash_delta;
	int64_t fee_reserve_delta;
	int64_t public_inventory_delta;
	int64_t held_units_delta;
};

/** One security's cash accounts and aggregate unit ledger. */
struct LedgerState {
	int64_t trader_cash;
	int64_t market_maker_cash;
	int64_t fee_reserve;
	uint32_t public_inventory;
	uint32_t held_units;
};

namespace Detail {

inline constexpr std::optional<int64_t> CheckedAdd(int64_t left, int64_t right)
{
	if (right > 0 && left > std::numeric_limits<int64_t>::max() - right) return std::nullopt;
	if (right < 0 && left < std::numeric_limits<int64_t>::min() - right) return std::nullopt;
	return left + right;
}

inline constexpr std::optional<int64_t> CheckedSubtract(int64_t left, int64_t right)
{
	if (right > 0 && left < std::numeric_limits<int64_t>::min() + right) return std::nullopt;
	if (right < 0 && left > std::numeric_limits<int64_t>::max() + right) return std::nullopt;
	return left - right;
}

inline constexpr std::optional<int64_t> CheckedMultiply(int64_t left, int64_t right)
{
	if (left == 0 || right == 0) return 0;
	if ((left == -1 && right == std::numeric_limits<int64_t>::min()) ||
			(right == -1 && left == std::numeric_limits<int64_t>::min())) {
		return std::nullopt;
	}

	if (left > 0) {
		if (right > 0) {
			if (left > std::numeric_limits<int64_t>::max() / right) return std::nullopt;
		} else {
			if (right < std::numeric_limits<int64_t>::min() / left) return std::nullopt;
		}
	} else {
		if (right > 0) {
			if (left < std::numeric_limits<int64_t>::min() / right) return std::nullopt;
		} else {
			if (left < std::numeric_limits<int64_t>::max() / right) return std::nullopt;
		}
	}

	return left * right;
}

/** Calculate floor(value * multiplier / divisor) without overflowing an avoidable intermediate. */
inline constexpr std::optional<int64_t> MultiplyDivideFloor(int64_t value, int64_t multiplier, int64_t divisor)
{
	if (value < 0 || multiplier < 0 || divisor <= 0) return std::nullopt;

	const int64_t quotient = value / divisor;
	const int64_t remainder = value % divisor;
	const auto whole = CheckedMultiply(quotient, multiplier);
	const auto fractional_numerator = CheckedMultiply(remainder, multiplier);
	if (!whole.has_value() || !fractional_numerator.has_value()) return std::nullopt;

	return CheckedAdd(*whole, *fractional_numerator / divisor);
}

/** Calculate ceil(value * multiplier / divisor) without overflowing an avoidable intermediate. */
inline constexpr std::optional<int64_t> MultiplyDivideCeil(int64_t value, int64_t multiplier, int64_t divisor)
{
	if (value < 0 || multiplier < 0 || divisor <= 0) return std::nullopt;

	const int64_t quotient = value / divisor;
	const int64_t remainder = value % divisor;
	const auto whole = CheckedMultiply(quotient, multiplier);
	const auto fractional_numerator = CheckedMultiply(remainder, multiplier);
	if (!whole.has_value() || !fractional_numerator.has_value()) return std::nullopt;

	auto result = CheckedAdd(*whole, *fractional_numerator / divisor);
	if (!result.has_value()) return std::nullopt;
	if (*fractional_numerator % divisor == 0) return result;
	return CheckedAdd(*result, 1);
}

} // namespace Detail

/**
 * Calculate the monthly fundamental market capitalisation.
 *
 * The profit component is six times trailing profit, clamped to -50%/+400%
 * of non-recursive net company value.
 */
inline constexpr std::optional<int64_t> CalculateTargetMarketCap(int64_t net_company_value, int64_t trailing_profit, int64_t minimum_cap)
{
	if (net_company_value < 0 || minimum_cap <= 0) return std::nullopt;

	const auto checked_profit_component = Detail::CheckedMultiply(trailing_profit, 6);
	const int64_t profit_component = checked_profit_component.value_or(
			trailing_profit < 0 ? std::numeric_limits<int64_t>::min() : std::numeric_limits<int64_t>::max());
	const int64_t minimum_profit_component = -(net_company_value / 2);
	const int64_t maximum_profit_component = net_company_value > std::numeric_limits<int64_t>::max() / 4 ?
			std::numeric_limits<int64_t>::max() : net_company_value * 4;
	const int64_t clamped_profit = std::clamp(profit_component, minimum_profit_component, maximum_profit_component);
	const auto target = Detail::CheckedAdd(net_company_value, clamped_profit);
	if (!target.has_value()) return std::nullopt;
	return std::max(minimum_cap, *target);
}

/** Convert total market capitalisation in Money to one 1/10,000 unit price. */
inline constexpr std::optional<SecurityPrice> CalculateTargetUnitPrice(int64_t target_market_cap)
{
	if (target_market_cap <= 0) return std::nullopt;
	const auto price = Detail::MultiplyDivideFloor(target_market_cap, PRICE_SCALE, COMPANY_EQUITY_UNITS);
	if (!price.has_value() || *price <= 0) return std::nullopt;
	return *price;
}

/** Move 25% toward the target, limited to the greater of 10% or one fixed-point tick per month. */
inline constexpr std::optional<SecurityPrice> MovePriceTowardsTarget(SecurityPrice current, SecurityPrice target)
{
	if (current <= 0 || target <= 0) return std::nullopt;

	const auto gap = Detail::CheckedSubtract(target, current);
	if (!gap.has_value()) return std::nullopt;
	/* One fixed-point tick is the smallest representable move at the low-price lattice edge. */
	const int64_t cap = std::max<int64_t>(1, current / MONTHLY_MOVE_CAP_DIVISOR);
	const int64_t movement = std::clamp(*gap / MONTHLY_TARGET_DIVISOR, -cap, cap);
	const auto result = Detail::CheckedAdd(current, movement);
	if (!result.has_value() || *result <= 0) return std::nullopt;
	return *result;
}

/** Calculate a one-percent full spread, rounding both sides against the trader. */
inline constexpr std::optional<Quote> CalculateQuote(SecurityPrice mid)
{
	if (mid <= 0) return std::nullopt;

	const auto bid = Detail::MultiplyDivideFloor(mid, BASIS_POINTS - HALF_SPREAD_BASIS_POINTS, BASIS_POINTS);
	const auto ask = Detail::MultiplyDivideCeil(mid, BASIS_POINTS + HALF_SPREAD_BASIS_POINTS, BASIS_POINTS);
	if (!bid.has_value() || !ask.has_value() || *bid <= 0 || *ask <= 0) return std::nullopt;
	return Quote{*bid, *ask};
}

/** Calculate a fee in Money, rounded up into the fee reserve. */
inline constexpr std::optional<int64_t> CalculateTransactionFee(int64_t gross, uint16_t fee_basis_points)
{
	if (gross < 0 || fee_basis_points > BASIS_POINTS) return std::nullopt;
	return Detail::MultiplyDivideCeil(gross, fee_basis_points, BASIS_POINTS);
}

/** Calculate all cash and unit deltas for a purchase from the market maker. */
inline constexpr std::optional<TradeSettlement> CalculateBuySettlement(SecurityPrice ask, uint16_t quantity, uint16_t fee_basis_points)
{
	if (ask <= 0 || quantity == 0) return std::nullopt;

	const auto gross = Detail::MultiplyDivideCeil(ask, quantity, PRICE_SCALE);
	if (!gross.has_value() || *gross <= 0) return std::nullopt;
	const auto fee = CalculateTransactionFee(*gross, fee_basis_points);
	if (!fee.has_value()) return std::nullopt;
	const auto debit = Detail::CheckedAdd(*gross, *fee);
	if (!debit.has_value()) return std::nullopt;

	return TradeSettlement{TradeSide::Buy, quantity, *gross, *fee, -*debit, *gross, *fee, -static_cast<int64_t>(quantity), quantity};
}

/** Calculate all cash and unit deltas for a sale to the market maker. */
inline constexpr std::optional<TradeSettlement> CalculateSellSettlement(SecurityPrice bid, uint16_t quantity, uint16_t fee_basis_points)
{
	if (bid <= 0 || quantity == 0) return std::nullopt;

	const auto gross = Detail::MultiplyDivideFloor(bid, quantity, PRICE_SCALE);
	if (!gross.has_value() || *gross <= 0) return std::nullopt;
	const auto fee = CalculateTransactionFee(*gross, fee_basis_points);
	if (!fee.has_value()) return std::nullopt;
	const auto proceeds = Detail::CheckedSubtract(*gross, *fee);
	if (!proceeds.has_value() || *proceeds < 0) return std::nullopt;

	return TradeSettlement{TradeSide::Sell, quantity, *gross, *fee, *proceeds, -*gross, *fee, quantity, -static_cast<int64_t>(quantity)};
}

/** Allocate aggregate cost basis to sold units, assigning indivisible remainders to the earliest units sold. */
inline constexpr std::optional<int64_t> AllocateProportionalCostBasis(int64_t cost_basis, uint16_t holding_units, uint16_t sold_units)
{
	if (cost_basis < 0 || holding_units == 0 || sold_units == 0 || sold_units > holding_units) return std::nullopt;
	if (sold_units == holding_units) return cost_basis;

	const int64_t per_unit = cost_basis / holding_units;
	const int64_t remainder = cost_basis % holding_units;
	const auto proportional = Detail::CheckedMultiply(per_unit, sold_units);
	if (!proportional.has_value()) return std::nullopt;
	return Detail::CheckedAdd(*proportional, std::min<int64_t>(remainder, sold_units));
}

/** Test the 25% holder cap without allowing an overflowing addition. */
inline constexpr bool CanAcquireCompanyEquity(uint32_t current_units, uint32_t quantity)
{
	return quantity > 0 && current_units <= COMPANY_EQUITY_HOLDER_CAP &&
			quantity <= COMPANY_EQUITY_HOLDER_CAP - current_units;
}

/** Check that an individual settlement conserves cash and issued units. */
inline constexpr bool IsSettlementConserved(const TradeSettlement &settlement)
{
	if (settlement.quantity == 0 || settlement.gross <= 0 || settlement.fee < 0 ||
			settlement.fee_reserve_delta != settlement.fee) {
		return false;
	}

	const int64_t quantity = settlement.quantity;
	switch (settlement.side) {
		case TradeSide::Buy: {
			const auto debit = Detail::CheckedAdd(settlement.gross, settlement.fee);
			if (!debit.has_value() || settlement.trader_cash_delta != -*debit ||
					settlement.market_maker_cash_delta != settlement.gross ||
					settlement.public_inventory_delta != -quantity || settlement.held_units_delta != quantity) {
				return false;
			}
			break;
		}

		case TradeSide::Sell: {
			const auto proceeds = Detail::CheckedSubtract(settlement.gross, settlement.fee);
			if (!proceeds.has_value() || *proceeds < 0 || settlement.trader_cash_delta != *proceeds ||
					settlement.market_maker_cash_delta != -settlement.gross ||
					settlement.public_inventory_delta != quantity || settlement.held_units_delta != -quantity) {
				return false;
			}
			break;
		}

		default: return false;
	}

	const auto operating_cash = Detail::CheckedAdd(settlement.trader_cash_delta, settlement.market_maker_cash_delta);
	if (!operating_cash.has_value()) return false;
	const auto total_cash = Detail::CheckedAdd(*operating_cash, settlement.fee_reserve_delta);
	const auto total_units = Detail::CheckedAdd(settlement.public_inventory_delta, settlement.held_units_delta);
	return total_cash.has_value() && *total_cash == 0 && total_units.has_value() && *total_units == 0;
}

/** Check account domains and the invariant that exactly 10,000 units remain issued. */
inline constexpr bool IsLedgerValid(const LedgerState &ledger)
{
	if (ledger.trader_cash < 0 || ledger.market_maker_cash < 0 || ledger.fee_reserve < 0) return false;
	return static_cast<uint64_t>(ledger.public_inventory) + ledger.held_units == COMPANY_EQUITY_UNITS;
}

/** Apply an already-validated settlement without partial mutation. */
inline constexpr std::optional<LedgerState> ApplySettlement(const LedgerState &before, const TradeSettlement &settlement)
{
	if (!IsLedgerValid(before) || !IsSettlementConserved(settlement)) return std::nullopt;

	const auto trader_cash = Detail::CheckedAdd(before.trader_cash, settlement.trader_cash_delta);
	const auto maker_cash = Detail::CheckedAdd(before.market_maker_cash, settlement.market_maker_cash_delta);
	const auto fee_reserve = Detail::CheckedAdd(before.fee_reserve, settlement.fee_reserve_delta);
	const auto public_inventory = Detail::CheckedAdd(before.public_inventory, settlement.public_inventory_delta);
	const auto held_units = Detail::CheckedAdd(before.held_units, settlement.held_units_delta);
	if (!trader_cash.has_value() || !maker_cash.has_value() || !fee_reserve.has_value() ||
			!public_inventory.has_value() || !held_units.has_value()) {
		return std::nullopt;
	}
	if (*public_inventory < 0 || *public_inventory > std::numeric_limits<uint32_t>::max() ||
			*held_units < 0 || *held_units > std::numeric_limits<uint32_t>::max()) {
		return std::nullopt;
	}

	LedgerState after{*trader_cash, *maker_cash, *fee_reserve,
			static_cast<uint32_t>(*public_inventory), static_cast<uint32_t>(*held_units)};
	if (!IsLedgerValid(after)) return std::nullopt;
	return after;
}

/** Check that a complete before/after ledger transition preserves both totals. */
inline constexpr bool IsLedgerConserved(const LedgerState &before, const LedgerState &after)
{
	if (!IsLedgerValid(before) || !IsLedgerValid(after)) return false;
	const auto trader_delta = Detail::CheckedSubtract(after.trader_cash, before.trader_cash);
	const auto maker_delta = Detail::CheckedSubtract(after.market_maker_cash, before.market_maker_cash);
	const auto fee_delta = Detail::CheckedSubtract(after.fee_reserve, before.fee_reserve);
	if (!trader_delta.has_value() || !maker_delta.has_value() || !fee_delta.has_value()) return false;
	const auto operating_delta = Detail::CheckedAdd(*trader_delta, *maker_delta);
	if (!operating_delta.has_value()) return false;
	const auto total_delta = Detail::CheckedAdd(*operating_delta, *fee_delta);
	return total_delta.has_value() && *total_delta == 0;
}

} // namespace CompanyExchange

#endif /* COMPANY_EXCHANGE_FUNC_H */
