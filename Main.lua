-- [[ 1. SCRIPT IDENTITY & TOKEN SYSTEM ]] --
_G.LatestRunToken = (_G.LatestRunToken or 0) + 1
local myToken = _G.LatestRunToken

-- Anti-AFK Function (Sesuai Token agar tidak Spam)
local function InitAntiAFK()
    local VirtualUser = game:GetService("VirtualUser")
    if _G.AFKConnection then _G.AFKConnection:Disconnect() end
    
    _G.AFKConnection = game:GetService("Players").LocalPlayer.Idled:Connect(function()
        if _G.LatestRunToken == myToken then
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
            print("SayzHub: Anti-AFK Action Performed.")
        else
            if _G.AFKConnection then _G.AFKConnection:Disconnect() end
        end
    end)
end
InitAntiAFK()

-- [FIX-2] Reset OldHookSet setiap re-execute agar hook scanner terpasang ulang
_G.OldHookSet = false
_G.AutoDropHookSet = false

-- [[ 3. CONFIGURATION ]] --
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

-- Tabel Penampung Handle UI (Untuk mempermudah Fitur Config nanti)
getgenv().SayzUI_Handles = {}

-- [[ 4. GLOBAL SETTINGS TABLE ]] --
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

-- [[ 5. UI INITIALIZATION ]] --
local successUI, SayzUI = pcall(function()
    return loadstring(game:HttpGet(GetRaw("Library/SayzUI.lua")))()
end)

if not successUI then
    warn("SayzHub: Gagal memuat UI Library. Pastikan koneksi internet stabil.")
    return
end

local Window = SayzUI:CreateWindow({
    Title = "SayzUI v1",
    Subtitle = "BlueWhite Edition",
    Theme = "BlueWhite",
    ToggleKeybind = Enum.KeyCode.K,
    ShowWelcomeToast = true,
    ShowLoading = true,
    OnClose = function()
        _G.LatestRunToken = (_G.LatestRunToken or 0) + 1
        -- [FIX-2] Reset flag hook saat ditutup agar re-execute bersih
        _G.OldHookSet = false
        _G.AutoDropHookSet = false
        getgenv().SayzSettings = nil
        getgenv().SayzUI_Handles = nil
        print("SayzHub: Stopped and Cleaned.")
    end
})

-- [[ 6. LOAD MODULES WITH ENHANCED LOGGING ]] --
local function SafeLoad(path, name)
    Window:SetLoadingText("Loading " .. name .. "...")
    
    local success, code = pcall(game.HttpGet, game, GetRaw(path))
    if success then
        local chunk, err = loadstring(code)
        if chunk then
            local runSuccess, runErr = pcall(function() chunk()(Window) end)
            if not runSuccess then
                Window:Notify("Error in " .. name .. ": " .. tostring(runErr), 5, "danger")
            end
        else
            Window:Notify("Syntax Error in " .. name, 5, "danger")
            warn("SayzHub [" .. name .. "]: " .. err)
        end
    else
        Window:Notify("Gagal download modul: " .. name, 5, "danger")
    end
end

-- Eksekusi Loading Modul
SafeLoad("Modules/Beranda.lua", "Beranda")
SafeLoad("Modules/Automation.lua", "Automation")
SafeLoad("Modules/Menu.lua", "Menu")

Window:Notify("SayzUI Berhasil Dimuat!", 3, "ok")

