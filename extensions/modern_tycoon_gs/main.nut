require("market.nut");

class ModernTycoon extends GSController {
    market = null;
    loaded_state = null;

    constructor()
    {
        this.market = null;
        this.loaded_state = null;
    }
}

function ModernTycoon::Start()
{
    GSLog.Info("Modern Tycoon market laboratory is starting");
    this.market = ModernMarket(this.loaded_state);
    this.market.Initialise();

    while (true) {
        while (GSEventController.IsEventWaiting()) {
            local event = GSEventController.GetNextEvent();
            if (event != null) this.market.HandleEvent(event);
        }

        this.market.Tick();
        this.Sleep(10);
    }
}

function ModernTycoon::Save()
{
    if (this.market == null) return { schema = 2 };
    return this.market.GetSaveData();
}

function ModernTycoon::Load(version, data)
{
    GSLog.Info("Loading Modern Tycoon save data from script version " + version);
    this.loaded_state = data;
}
