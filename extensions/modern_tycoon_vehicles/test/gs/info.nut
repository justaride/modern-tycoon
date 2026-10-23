/*
 * Test-only GameScript: counts which engines every company runs.
 * SPDX-License-Identifier: GPL-2.0-only
 */
class MTFleetCensusInfo extends GSInfo {
	function GetAuthor()      { return "Modern Tycoon contributors"; }
	function GetName()        { return "MT Fleet Census"; }
	function GetShortName()   { return "MTFC"; }
	function GetDescription() { return "Test fixture: logs a fleet census by engine name every quarter."; }
	function GetVersion()     { return 1; }
	function GetAPIVersion()  { return "15"; }
	function GetDate()        { return "2026-10-23"; }
	function CreateInstance() { return "MTFleetCensus"; }
}
RegisterGS(MTFleetCensusInfo());
