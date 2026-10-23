/*
 * Test-only AI: proves the Modern Tycoon Trains NewGRF in a real game.
 * SPDX-License-Identifier: GPL-2.0-only
 */
class MTVehicleTestInfo extends AIInfo {
	function GetAuthor()      { return "Modern Tycoon contributors"; }
	function GetName()        { return "MT Vehicle Test"; }
	function GetShortName()   { return "MTVT"; }
	function GetDescription() { return "Test fixture: buys, refits and runs the Modern Tycoon Trains vehicles."; }
	function GetVersion()     { return 1; }
	function GetAPIVersion()  { return "15"; }
	function GetDate()        { return "2026-10-23"; }
	function CreateInstance() { return "MTVehicleTest"; }
	function UseAsRandomAI()  { return false; }
}
RegisterAI(MTVehicleTestInfo());
