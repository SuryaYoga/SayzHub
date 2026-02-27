-- [[ 1. SCRIPT IDENTITY & TOKEN SYSTEM ]] --
-- Gunakan Token agar sinkron dengan library SayzUI yang sudah kita modif
_G.LatestRunToken = (_G.LatestRunToken or 0) + 1
local myToken = _G.LatestRunToken

-- [[ 2. CONFIGURATION ]] --
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

-- [[ 3. GLOBAL SETTINGS TABLE ]] --
getgenv().SayzSettings = {
    AutoCollect = {
        Enabled = false,
        TakeGems = true,
        StepDelay = 0.05,
        AvoidanceStrength = 50,
        ItemBlacklist = {}
    },
    PnB = {
        TargetID = 0, DelayScale = 1, ActualDelay = 0.12, PlaceDelay = 0.05,
        Posisi = "1 Atas", Jumlah = 1, BreakMode = "Mode 1 (Fokus)",
        Place = false, Break = false, Master = false, Scanning = false,
        SelectedTiles = {}, OriginGrid = nil, LockPosition = false
    },
    Cheat = {
        Fly = false,
        FlySpeed = 50
    }
}

-- [[ 4. UI INITIALIZATION ]] --
-- Pastikan Library SayzUI.lua di GitHub sudah kamu update dengan _G.LatestRunToken tadi
local SayzUI = loadstring(game:HttpGet(GetRaw("Library/SayzUI.lua")))()

local Window = SayzUI:CreateWindow({
    Title = "SayzUI v1",
    Subtitle = "BlueWhite Edition",
    Theme = "BlueWhite",
    ToggleKeybind = Enum.KeyCode.K,
    ShowWelcomeToast = true,
    ShowLoading = true,
    -- Menambahkan fungsi OnClose agar token naik saat UI ditutup
    OnClose = function()
        _G.LatestRunToken = (_G.LatestRunToken or 0) + 1
        getgenv().SayzSettings = nil
        print("SayzHub: Stopped and Cleaned.")
    end
})

-- [[ 5. LOAD MODULES ]] --
-- Kita bungkus dengan pcall agar jika satu modul error, yang lain tetap jalan
local function SafeLoad(path, name)
    local success, code = pcall(game.HttpGet, game, GetRaw(path))
    if success then
        local chunk, err = loadstring(code)
        if chunk then
            pcall(function() chunk()(Window) end)
        else
            warn("Syntax Error in " .. name .. ": " .. err)
        end
    else
        warn("Failed to download " .. name)
    end
end

SafeLoad("Modules/Beranda.lua", "Beranda")
SafeLoad("Modules/Automation.lua", "Automation")
SafeLoad("Modules/Miscs.lua", "Miscs")

Window:Notify("SayzUI Berhasil Dimuat!", 3, "ok")
