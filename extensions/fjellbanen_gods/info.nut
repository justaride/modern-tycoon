/*
 * Fjellbanen Gods - a Modern Tycoon rail freight AI with its own A* pathfinder.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

class FjellbanenGodsInfo extends AIInfo {
	function GetAuthor()      { return "Modern Tycoon contributors"; }
	function GetName()        { return "Fjellbanen Gods"; }
	function GetShortName()   { return "FJBG"; }
	function GetDescription() { return "A Norwegian rail freight company that links busy industries with their customers, using its own pathfinder. Personality: cautious, balanced, aggressive or random."; }
	function GetVersion()     { return 1; }
	function MinVersionToLoad() { return 1; }
	function GetAPIVersion()  { return "15"; }
	function GetDate()        { return "2026-10-23"; }
	function GetURL()         { return "https://github.com/justaride/modern-tycoon"; }
	function CreateInstance() { return "FjellbanenGods"; }
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
			description = "Maximum number of rail lines",
			min_value = 1,
			max_value = 30,
			default_value = 8,
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

RegisterAI(FjellbanenGodsInfo());
