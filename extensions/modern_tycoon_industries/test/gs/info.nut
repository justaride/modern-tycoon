/*
 * Test-only GameScript for Modern Tycoon Space Industry.
 * SPDX-License-Identifier: GPL-2.0-only
 */
class MTSpaceTestInfo extends GSInfo {
	function GetAuthor()      { return "Modern Tycoon contributors"; }
	function GetName()        { return "MT Space Test"; }
	function GetShortName()   { return "MTST"; }
	function GetDescription() { return "Test fixture: builds the space industries and checks cargo, production and refits."; }
	function GetVersion()     { return 1; }
	function GetAPIVersion()  { return "15"; }
	function GetDate()        { return "2026-10-23"; }
	function CreateInstance() { return "MTSpaceTest"; }
}
RegisterGS(MTSpaceTestInfo());
