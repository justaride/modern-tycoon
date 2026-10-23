class ModernTycoonTestCompanyInfo extends AIInfo {
    function GetAuthor()      { return "Modern Tycoon contributors"; }
    function GetName()        { return "Modern Tycoon Test Company"; }
    function GetShortName()   { return "MTTC"; }
    function GetDescription() { return "A deliberately idle company used for deterministic Modern Tycoon market soak tests."; }
    function GetVersion()     { return 2; }
    function MinVersionToLoad() { return 1; }
    function GetAPIVersion()  { return "15"; }
    function GetDate()        { return "2026-10-23"; }
    function CreateInstance() { return "ModernTycoonTestCompany"; }
    function UseAsRandomAI()  { return false; }

    function GetSettings()
    {
        AddSetting({
            name = "accept_merger",
            description = "Accept takeover offers for bankrupt companies (test fixtures only)",
            min_value = 0,
            max_value = 1,
            default_value = 0,
            flags = CONFIG_BOOLEAN
        });
    }
}

RegisterAI(ModernTycoonTestCompanyInfo());
