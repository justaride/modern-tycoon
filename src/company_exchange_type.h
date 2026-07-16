/*
 * This file is part of OpenTTD.
 * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.
 * OpenTTD is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with OpenTTD. If not, see <https://www.gnu.org/licenses/old-licenses/gpl-2.0>.
 */

/** @file company_exchange_type.h Basic types related to the company exchange. */

#ifndef COMPANY_EXCHANGE_TYPE_H
#define COMPANY_EXCHANGE_TYPE_H

#include "core/pool_type.hpp"

/** Unique identifier of a security. */
using SecurityID = PoolID<uint32_t, struct SecurityIDTag, 0xFF000, 0xFFFFF>;

/** Unique identifier of a company holding. */
using HoldingID = PoolID<uint32_t, struct HoldingIDTag, 0xFF000, 0xFFFFF>;

/** Kind of entity that issued a security. */
enum class SecurityKind : uint8_t {
	Company, ///< A transport company.
	Industry, ///< An individual industry enterprise.
	End, ///< End marker.
};

/** Lifecycle state of a security listing. */
enum class ListingStatus : uint8_t {
	Listed, ///< Trading is permitted.
	Frozen, ///< Trading is temporarily suspended.
	Delisted, ///< Trading has permanently ended.
	End, ///< End marker.
};

/** Side of a security trade. */
enum class TradeSide : uint8_t {
	Buy, ///< Buy units from the public inventory.
	Sell, ///< Sell units to the market maker.
};

/**
 * Signed security price with eight fractional bits.
 *
 * One whole unit of OpenTTD Money is represented by #SECURITY_PRICE_ONE.
 * Arithmetic using this type must remain integer-only and check overflow before
 * multiplying a price by a quantity.
 */
using SecurityPrice = int64_t;

static constexpr uint8_t SECURITY_PRICE_FRACTION_BITS = 8; ///< Number of fractional bits in a security price.
static constexpr SecurityPrice SECURITY_PRICE_ONE = SecurityPrice{1} << SECURITY_PRICE_FRACTION_BITS; ///< One whole Money unit.

static constexpr uint16_t COMPANY_EQUITY_UNITS = 10000; ///< Total units in one company equity listing.
static constexpr uint16_t COMPANY_EQUITY_HOLDER_CAP = 2500; ///< Maximum units one company may hold in another company.
static constexpr uint16_t COMPANY_EQUITY_INITIAL_LOT = 100; ///< Initial quantity exposed by one UI trade action.

struct Security;
struct Holding;

#endif /* COMPANY_EXCHANGE_TYPE_H */
