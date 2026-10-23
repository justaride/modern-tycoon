/*
 * Allvei Konsern - a Modern Tycoon AI that builds every kind of transport.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

class AllveiKonsernInfo extends AIInfo {
	function GetAuthor()      { return "Modern Tycoon contributors"; }
	function GetName()        { return "Allvei Konsern"; }
	function GetShortName()   { return "ALVK"; }
	function GetDescription() { return "A Norwegian transport group that builds trucks, buses, trains, ships and planes. It ranks every freight and passenger opportunity on the map by expected return, builds the best one first, delivers goods, food and water to towns, funds industries where customers are missing, and grows or retires each route from its results."; }
	function GetVersion()     { return 1; }
	function MinVersionToLoad() { return 1; }
	function GetAPIVersion()  { return "15"; }
	function GetDate()        { return "2026-10-23"; }
	function GetURL()         { return "https://github.com/justaride/modern-tycoon"; }
	function CreateInstance() { return "AllveiKonsern"; }
	function UseAsRandomAI()  { return true; }

	function GetSettings()
	{
		AddSetting({ name = "personality", description = "Personality (how boldly the group borrows and grows)",
				min_value = 0, max_value = 3, default_value = 3, flags = 0 });
		AddLabels("personality", { _0 = "Forsiktig (cautious)", _1 = "Balansert (balanced)",
				_2 = "Aggressiv (aggressive)", _3 = "Tilfeldig (random)" });
		AddSetting({ name = "max_routes", description = "Maximum number of routes",
				min_value = 1, max_value = 200, default_value = 80, step_size = 5, flags = CONFIG_INGAME });
		AddSetting({ name = "max_vehicles_per_route", description = "Maximum road vehicles or ships per route",
				min_value = 1, max_value = 40, default_value = 14, step_size = 1, flags = CONFIG_INGAME });
		AddSetting({ name = "use_road", description = "Build truck and bus routes",
				min_value = 0, max_value = 1, default_value = 1, flags = CONFIG_BOOLEAN | CONFIG_INGAME });
		AddSetting({ name = "use_rail", description = "Build rail freight lines",
				min_value = 0, max_value = 1, default_value = 1, flags = CONFIG_BOOLEAN | CONFIG_INGAME });
		AddSetting({ name = "use_water", description = "Build ship routes",
				min_value = 0, max_value = 1, default_value = 1, flags = CONFIG_BOOLEAN | CONFIG_INGAME });
		AddSetting({ name = "use_air", description = "Build air routes",
				min_value = 0, max_value = 1, default_value = 1, flags = CONFIG_BOOLEAN | CONFIG_INGAME });
		AddSetting({ name = "fund_industries", description = "Fund new industries where a producer has no customer",
				min_value = 0, max_value = 1, default_value = 1, flags = CONFIG_BOOLEAN | CONFIG_INGAME });
		AddSetting({ name = "use_loan", description = "Borrow money to expand faster",
				min_value = 0, max_value = 1, default_value = 1, flags = CONFIG_BOOLEAN | CONFIG_INGAME });
	}
}

RegisterAI(AllveiKonsernInfo());
