/*
 * Test-only AI for Modern Tycoon Space Industry: builds and runs the chain
 * oil wells -> rocket fuel plant -> spaceport with trucks.
 * SPDX-License-Identifier: GPL-2.0-only
 */
class MTSpaceHaulerInfo extends AIInfo {
	function GetAuthor()      { return "Modern Tycoon contributors"; }
	function GetName()        { return "MT Space Hauler"; }
	function GetShortName()   { return "MTSH"; }
	function GetDescription() { return "Test fixture: funds the space chain in a row along one road and runs trucks on it."; }
	function GetVersion()     { return 1; }
	function GetAPIVersion()  { return "15"; }
	function GetDate()        { return "2026-10-23"; }
	function CreateInstance() { return "MTSpaceHauler"; }
	function UseAsRandomAI()  { return false; }
}
RegisterAI(MTSpaceHaulerInfo());
