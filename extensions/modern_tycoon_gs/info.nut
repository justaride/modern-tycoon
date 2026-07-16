class ModernTycoonInfo extends GSInfo {
    function GetAuthor()      { return "Modern Tycoon contributors"; }
    function GetName()        { return "Modern Tycoon Markets and News"; }
    function GetDescription() { return "A playable market laboratory with company equity, production-linked industry securities, portfolios, dividends, and a persistent transport newspaper."; }
    function GetVersion()     { return 2; }
    function MinVersionToLoad() { return 1; }
    function GetDate()        { return "2026-07-16"; }
    function CreateInstance() { return "ModernTycoon"; }
    function GetShortName()   { return "MTMK"; }
    function GetAPIVersion()  { return "15"; }
    function GetUrl()         { return "https://github.com/OpenTTD/OpenTTD"; }

    function GetSettings()
    {
        AddSetting({
            name = "company_market",
            description = "List transport companies on the exchange",
            easy_value = 1,
            medium_value = 1,
            hard_value = 1,
            custom_value = 1,
            flags = CONFIG_BOOLEAN
        });
        AddSetting({
            name = "industry_market",
            description = "List production-linked industry securities",
            easy_value = 1,
            medium_value = 1,
            hard_value = 1,
            custom_value = 1,
            flags = CONFIG_BOOLEAN
        });
        AddSetting({
            name = "max_industries",
            description = "Maximum listed industries",
            easy_value = 8,
            medium_value = 12,
            hard_value = 16,
            custom_value = 12,
            flags = 0,
            min_value = 0,
            max_value = 40,
            step_size = 1
        });
        AddSetting({
            name = "transaction_fee_bp",
            description = "Exchange transaction fee in basis points (100 = 1%)",
            easy_value = 50,
            medium_value = 100,
            hard_value = 200,
            custom_value = 100,
            flags = CONFIG_INGAME,
            min_value = 0,
            max_value = 1000,
            step_size = 25
        });
        AddSetting({
            name = "company_dividend_percent",
            description = "Quarterly company profit paid to listed player-held shares (%)",
            easy_value = 15,
            medium_value = 25,
            hard_value = 35,
            custom_value = 25,
            flags = CONFIG_INGAME,
            min_value = 0,
            max_value = 80,
            step_size = 5
        });
        AddSetting({
            name = "industry_yield_per_unit",
            description = "Quarterly industry distribution per transported cargo unit",
            easy_value = 20,
            medium_value = 10,
            hard_value = 5,
            custom_value = 10,
            flags = CONFIG_INGAME,
            min_value = 0,
            max_value = 100,
            step_size = 5
        });
        AddSetting({
            name = "news_frequency",
            description = "Market news frequency (0 major only, 1 quarterly, 2 monthly)",
            easy_value = 1,
            medium_value = 1,
            hard_value = 2,
            custom_value = 1,
            flags = CONFIG_INGAME,
            min_value = 0,
            max_value = 2,
            step_size = 1
        });
        AddSetting({
            name = "developer_self_test",
            description = "Run one automatic buy/sell conservation smoke test",
            easy_value = 0,
            medium_value = 0,
            hard_value = 0,
            custom_value = 0,
            flags = CONFIG_BOOLEAN | CONFIG_DEVELOPER
        });
    }
}

RegisterGS(ModernTycoonInfo());
