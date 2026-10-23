require("news.nut");
require("market.nut");
require("pricing.nut");
require("fixture.nut");

class ModernTycoon extends GSController {
    market = null;
    fixture = null;
    loaded_state = null;

    constructor()
    {
        this.market = null;
        this.fixture = null;
        this.loaded_state = null;
    }
}

function ModernTycoon::Start()
{
    GSLog.Info("Modern Tycoon market laboratory is starting");
    this.market = ModernMarket(this.loaded_state);
    this.market.Initialise();

    /* Developer fixture: resumes from a save, or starts when the developer setting asks for it. */
    if (this.loaded_state != null && this.loaded_state.rawin("fixture")) {
        this.fixture = MarketFixture(this.market, this.loaded_state.fixture, 0);
    } else if (GSController.GetSetting("developer_fixture") > 0) {
        this.fixture = MarketFixture(this.market, null, GSController.GetSetting("developer_fixture"));
    }
    this.loaded_state = null;

    while (true) {
        while (GSEventController.IsEventWaiting()) {
            local event = GSEventController.GetNextEvent();
            if (event == null) continue;
            if (this.fixture != null) this.fixture.BeforeEvent(event);
            this.market.HandleEvent(event);
            if (this.fixture != null) this.fixture.AfterEvent(event);
        }

        this.market.Tick();
        if (this.fixture != null) this.fixture.Tick();
        this.Sleep(10);
    }
}

function ModernTycoon::Save()
{
    if (this.market == null) return { schema = 4 };
    local data = this.market.GetSaveData();
    if (this.fixture != null) data.fixture <- this.fixture.state;
    return data;
}

function ModernTycoon::Load(version, data)
{
    GSLog.Info("Loading Modern Tycoon save data from script version " + version);
    this.loaded_state = data;
}
