-- [[ 1. SCRIPT IDENTITY & TOKEN SYSTEM ]] --
_G.LatestRunToken = (_G.LatestRunToken or 0) + 1
local myToken = _G.LatestRunToken

-- [[ 2. ANTI-AFK ]] --
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

-- [FIX-2] Reset OldHookSet setiap kali script di-execute ulang
-- agar hook scanner di AutoPnB terpasang ulang dengan benar
_G.OldHookSet = false

-- [[ 3. CONFIGURATION ]] --
getgenv().SayzConfig = {
    UserName = "SuryaYoga",
    Repo = "SayzHub",
    Branch = "main"
}

local function GetRaw(path)
    return string.format("https://raw.githubusercontent.com/%s/%s/%s/%s",
        getgenv().SayzConfig.UserName,
        getgenv().SayzConfig.Repo,
        getgenv().SayzConfig.Branch,
        path)
end
getgenv().GetRaw = GetRaw

-- Tabel Penampung Handle UI
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
        SelectedTiles = {}, OriginGrid = nil, LockPosition = false,
        -- Smart Collect settings (namespace terpisah dari AutoCollect)
        SmartCollect = {
            Enabled = false,
            TakeGems = false,
            StepDelay = 0.05,
            AvoidanceStrength = 50,
        }
    },
    Cheat = {
        Fly = false,
        FlySpeed = 50
    }
    -- [NOTED] AutoDrop akan ditambah di sini saat fitur Config siap
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
        -- [FIX-2] Reset flag hook saat window ditutup agar re-execute bersih
        _G.OldHookSet = false
        getgenv().SayzSettings = nil
        getgenv().SayzUI_Handles = nil
        print("SayzHub: Stopped and Cleaned.")
    end
})

-- [[ 6. LOAD MODULES ]] --
-- [FIX-1] SafeLoad sekarang kirim myToken ke semua modul secara konsisten
local function SafeLoad(path, name)
    Window:SetLoadingText("Loading " .. name .. "...")

    local success, code = pcall(game.HttpGet, game, GetRaw(path))
    if not success then
        Window:Notify("Gagal download modul: " .. name, 5, "danger")
        return
    end

    local chunk, err = loadstring(code)
    if not chunk then
        Window:Notify("Syntax Error in " .. name, 5, "danger")
        warn("SayzHub [" .. name .. "]: " .. tostring(err))
        return
    end

    -- [FIX-1] Kirim Window DAN myToken ke semua modul (konsisten dengan Automation.lua)
    local runSuccess, runErr = pcall(function()
        chunk()(Window, myToken)
    end)
    if not runSuccess then
        Window:Notify("Error in " .. name .. ": " .. tostring(runErr), 5, "danger")
        warn("SayzHub Runtime Error [" .. name .. "]: " .. tostring(runErr))
    end
end

-- Eksekusi Loading Modul
SafeLoad("Modules/Beranda.lua", "Beranda")
SafeLoad("Modules/Automation.lua", "Automation")
-- [FIX-7] Miscs.lua dihapus dari load karena file tidak ada di repo
-- SafeLoad("Modules/Miscs.lua", "Miscs")

Window:Notify("SayzUI Berhasil Dimuat!", 3, "ok")
