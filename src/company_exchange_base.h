/*
 * This file is part of OpenTTD.
 * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.
 * OpenTTD is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with OpenTTD. If not, see <https://www.gnu.org/licenses/old-licenses/gpl-2.0>.
 */

/** @file company_exchange_base.h Base structures related to the company exchange. */

#ifndef COMPANY_EXCHANGE_BASE_H
#define COMPANY_EXCHANGE_BASE_H

#include "company_exchange_type.h"
#include "company_type.h"
#include "economy_type.h"
#include "core/pool_type.hpp"

using SecurityPool = Pool<Security, SecurityID, 16>;
extern SecurityPool _security_pool;

using HoldingPool = Pool<Holding, HoldingID, 64>;
extern HoldingPool _holding_pool;

/** A listed financial security and its market-maker accounts. */
struct Security : SecurityPool::PoolItem<&_security_pool> {
	SecurityKind kind = SecurityKind::Company; ///< Kind of issuer.
	uint32_t issuer = 0; ///< Pool index of the issuer within its entity kind.
	uint32_t issuer_generation = 0; ///< Monotonic generation protecting against issuer ID reuse.
	ListingStatus status = ListingStatus::Listed; ///< Current listing state.
	SecurityPrice price = 0; ///< Mid-price in 1/256 Money units.
	SecurityPrice fundamental = 0; ///< Fundamental target in 1/256 Money units.
	uint16_t public_inventory = COMPANY_EQUITY_UNITS; ///< Units held by the market maker.
	Money market_maker_cash = 0; ///< Explicit cash available to settle sales.

	Security(SecurityID index, SecurityKind kind = SecurityKind::Company, uint32_t issuer = 0, uint32_t issuer_generation = 0) :
		SecurityPool::PoolItem<&_security_pool>(index), kind(kind), issuer(issuer), issuer_generation(issuer_generation) {}

	/**
	 * (Empty) destructor has to be defined else operator delete might be called with nullptr parameter.
	 */
	~Security() { }
};

/** A sparse company holding in one security. */
struct Holding : HoldingPool::PoolItem<&_holding_pool> {
	SecurityID security = SecurityID::Invalid(); ///< Security owned by the holder.
	CompanyID holder = CompanyID::Invalid(); ///< Company that owns the units.
	uint16_t units = 0; ///< Number of equity units owned.
	Money cost_basis = 0; ///< Aggregate Money paid for all currently held units.

	Holding(HoldingID index, SecurityID security = SecurityID::Invalid(), CompanyID holder = CompanyID::Invalid()) :
		HoldingPool::PoolItem<&_holding_pool>(index), security(security), holder(holder) {}

	/**
	 * (Empty) destructor has to be defined else operator delete might be called with nullptr parameter.
	 */
	~Holding() { }
};

/**
 * Find a company's holding in a security using stable pool-index iteration.
 * @param security Security to look up.
 * @param holder Company that may own units.
 * @return Matching holding, or nullptr when no holding exists.
 */
Holding *FindHolding(SecurityID security, CompanyID holder);

#endif /* COMPANY_EXCHANGE_BASE_H */
