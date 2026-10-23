/*
 * Nordlys Air - the first Modern Tycoon AI player.
 * A Norwegian-flavoured airline that links the largest towns on the map.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

class NordlysAirInfo extends AIInfo {
	function GetAuthor()      { return "Modern Tycoon contributors"; }
	function GetName()        { return "Nordlys Air"; }
	function GetShortName()   { return "NLAR"; }
	function GetDescription() { return "A Norwegian airline that links the biggest towns, grows where passengers pile up, renews its fleet, moves busy routes to bigger airports and flies mail. Personality: cautious, balanced, aggressive or random."; }
	function GetVersion()     { return 2; }
	function MinVersionToLoad() { return 1; }
	function GetAPIVersion()  { return "15"; }
	function GetDate()        { return "2026-10-23"; }
	function GetURL()         { return "https://github.com/justaride/modern-tycoon"; }
	function CreateInstance() { return "NordlysAir"; }
	function UseAsRandomAI()  { return true; }

	function GetSettings()
	{
		AddSetting({
			name = "personality",
			description = "Personality (how boldly the company borrows and grows)",
			min_value = 0,
			max_value = 3,
			default_value = 3,
			flags = 0
		});
		AddLabels("personality", {
			_0 = "Forsiktig (cautious)",
			_1 = "Balansert (balanced)",
			_2 = "Aggressiv (aggressive)",
			_3 = "Tilfeldig (random)"
		});
		AddSetting({
			name = "max_routes",
			description = "Maximum number of air routes",
			min_value = 1,
			max_value = 40,
			default_value = 12,
			step_size = 1,
			flags = CONFIG_INGAME
		});
		AddSetting({
			name = "max_planes_per_route",
			description = "Maximum planes on one route",
			min_value = 2,
			max_value = 12,
			default_value = 5,
			step_size = 1,
			flags = CONFIG_INGAME
		});
		AddSetting({
			name = "use_loan",
			description = "Borrow money to expand faster",
			min_value = 0,
			max_value = 1,
			default_value = 1,
			flags = CONFIG_BOOLEAN | CONFIG_INGAME
		});
	}
}

RegisterAI(NordlysAirInfo());
