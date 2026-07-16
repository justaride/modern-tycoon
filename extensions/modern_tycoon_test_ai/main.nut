class ModernTycoonTestCompany extends AIController {
}

function ModernTycoonTestCompany::Start()
{
    AILog.Info("Modern Tycoon test company is ready");
    while (true) this.Sleep(100);
}

function ModernTycoonTestCompany::Save()
{
    return {};
}

function ModernTycoonTestCompany::Load(version, data)
{
}
