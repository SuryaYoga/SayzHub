-- [[ 1. CONFIGURATION & TELEPORT ]] --
getgenv().SayzConfig = {
    UserName = "SuryaYoga",
    Repo = "SayzHub",
    Branch = "main"
}

local function GetRaw(path)
    return string.format("https://raw.githubusercontent.com/%s/%s/%s/%s",
        getgenv().SayzConfig.UserName, getgenv().SayzConfig.Repo, getgenv().SayzConfig.Branch, path)
end
getgenv().GetRaw = GetRaw

-- Fitur Anti-Mati saat Pindah World
local teleportScript = [[loadstring(game:HttpGet("]] .. GetRaw("main.lua") .. [["))()]]
if queue_on_teleport then
    queue_on_teleport(teleportScript)
elseif syn and syn.queue_on_teleport then
    syn.queue_on_teleport(teleportScript)
end

-- [[ 2. GLOBAL SETTINGS TABLE ]] --
-- Semua setting dikumpulkan di sini agar mudah di-Save/Load nanti
getgenv().SayzSettings = getgenv().SayzSettings or {
    -- Auto Collect Settings (Persiapan untuk Automation.lua)
    AutoCollect = {
        Enabled = false,
        TakeGems = true,
        StepDelay = 0.05,
        AvoidanceStrength = 50,
        ItemBlacklist = {}
    },
    -- PnB Settings
    PnB = {
        TargetID = 0, DelayScale = 1, ActualDelay = 0.12, PlaceDelay = 0.05,
        Posisi = "1 Atas", Jumlah = 1, BreakMode = "Mode 1 (Fokus)",
        Place = false, Break = false, Master = false, Scanning = false,
        SelectedTiles = {}, OriginGrid = nil, LockPosition = false
    },
    -- Cheat Settings
    Cheat = {
        Fly = false,
        FlySpeed = 50
    }
}

-- [[ 3. UI INITIALIZATION ]] --
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

-- [[ 4. LOAD MODULES ]] --
-- Kita kirim 'Window' dan 'SayzSettings' ke modul agar bisa dibaca
loadstring(game:HttpGet(GetRaw("Modules/Beranda.lua")))()(Window)
loadstring(game:HttpGet(GetRaw("Modules/Automation.lua")))()(Window)
loadstring(game:HttpGet(GetRaw("Modules/Miscs.lua")))()(Window)

Window:Notify("SayzUI Berhasil Dimuat!", 3, "ok")
