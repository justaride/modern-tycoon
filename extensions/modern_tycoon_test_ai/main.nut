class ModernTycoonTestCompany extends AIController {
}

function ModernTycoonTestCompany::Start()
{
    AILog.Info("Modern Tycoon test company is ready");
    while (true) {
        while (AIEventController.IsEventWaiting()) {
            local event = AIEventController.GetNextEvent();
            if (event == null || event.GetEventType() != AIEvent.ET_COMPANY_ASK_MERGER) continue;
            if (!AIController.GetSetting("accept_merger")) continue;

            local offer = AIEventCompanyAskMerger.Convert(event);
            local accepted = offer.AcceptMerger();
            AILog.Info("Takeover offer for company " + offer.GetCompanyID() + (accepted ? " accepted" : " could not be accepted"));
        }
        this.Sleep(20);
    }
}

function ModernTycoonTestCompany::Save()
{
    return {};
}

function ModernTycoonTestCompany::Load(version, data)
{
}
