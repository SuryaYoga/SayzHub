getgenv().SayzConfig = {
    UserName = "SuryaYoga",
    Repo = "SayzHub",
    Branch = "main"
}

local function GetRaw(path)
    return string.format("https://raw.githubusercontent.com/%s/%s/%s/%s",
        getgenv().SayzConfig.UserName, getgenv().SayzConfig.Repo, getgenv().SayzConfig.Branch, path)
end

-- load library dari repo (disarankan)
local SayzUI = loadstring(game:HttpGet(GetRaw("Library/SayzUI.lua")))()

local Window = SayzUI:CreateWindow({
    Title = "SayzUI v1",
    Subtitle = "BlueWhite Edition",
    Theme = "BlueWhite",

    ToggleKeybind = Enum.KeyCode.K,
    ShowWelcomeToast = true,

    ShowLoading = true,
    LoadingText = "Loading SayzUI v1...",
    LoadingDuration = 1.5
})

getgenv().PnBSettings = {
    TargetID = 0, DelayScale = 1, ActualDelay = 0.12, PlaceDelay = 0.05,
    Posisi = "1 Atas", Jumlah = 1, BreakMode = "Mode 1 (Fokus)",
    Place = false, Break = false, Master = false, Scanning = false,
    SelectedTiles = {}, OriginGrid = nil, LockPosition = false
}

getgenv().CheatSettings = {
    Fly = false,
    FlySpeed = 50
}

loadstring(game:HttpGet(GetRaw("Modules/Beranda.lua")))()(Window)
loadstring(game:HttpGet(GetRaw("Modules/Automation.lua")))()(Window)
loadstring(game:HttpGet(GetRaw("Modules/Miscs.lua")))()(Window)

Window:Notify("SayzUI Modular Berhasil Dimuat!", 3, "ok")
