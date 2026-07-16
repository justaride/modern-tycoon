class ModernTycoonTestCompanyInfo extends AIInfo {
    function GetAuthor()      { return "Modern Tycoon contributors"; }
    function GetName()        { return "Modern Tycoon Test Company"; }
    function GetShortName()   { return "MTTC"; }
    function GetDescription() { return "A deliberately idle company used for deterministic Modern Tycoon market soak tests."; }
    function GetVersion()     { return 1; }
    function GetAPIVersion()  { return "15"; }
    function GetDate()        { return "2026-07-16"; }
    function CreateInstance() { return "ModernTycoonTestCompany"; }
    function UseAsRandomAI()  { return false; }
}

RegisterAI(ModernTycoonTestCompanyInfo());
