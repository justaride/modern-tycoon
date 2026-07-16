/*
 * This file is part of OpenTTD.
 * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.
 * OpenTTD is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with OpenTTD. If not, see <https://www.gnu.org/licenses/old-licenses/gpl-2.0>.
 */

/** @file company_exchange.cpp Company exchange pool storage and lookup. */

#include "stdafx.h"
#include "company_exchange_base.h"
#include "core/pool_func.hpp"

#include "safeguards.h"

/* Register dependent holdings first so normal pool resets release references before securities. */
HoldingPool _holding_pool("Holding"); ///< Pool for sparse company holdings.
SecurityPool _security_pool("Security"); ///< Pool for listed securities.

INSTANTIATE_POOL_METHODS(Security)
INSTANTIATE_POOL_METHODS(Holding)

Holding *FindHolding(SecurityID security, CompanyID holder)
{
	for (Holding *holding : Holding::Iterate()) {
		if (holding->security == security && holding->holder == holder) return holding;
	}

	return nullptr;
}
