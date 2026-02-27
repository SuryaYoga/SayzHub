-- [[ 1. SCRIPT IDENTITY & CLEANUP ]] --
-- Memberi tanda waktu unik agar loop lama tahu kapan harus berhenti
local CurrentRunID = os.clock()
getgenv().SayzLatestRunID = CurrentRunID

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
-- Kita paksa reset setiap run agar tidak "nyangkut" settingan lamanya
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
local SayzUI = loadstring(game:HttpGet(GetRaw("Library/SayzUI.lua")))()

local Window = SayzUI:CreateWindow({
    Title = "SayzUI v1",
    Subtitle = "BlueWhite Edition",
    Theme = "BlueWhite",
    ToggleKeybind = Enum.KeyCode.K,
    ShowWelcomeToast = true,
    ShowLoading = true
})

-- Memaksa UI ke depan
pcall(function()
    local gui = game:GetService("CoreGui"):FindFirstChild("SayzUI v1") or game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SayzUI v1")
    if gui then gui.DisplayOrder = 9999 end
end)

-- [[ 5. KILL SWITCH (ON CLOSE) ]] --
-- Jika library kamu punya OnClose, gunakan ini. Jika tidak, tambahkan tombol Unload nanti.
if Window.OnClose then
    Window:OnClose(function()
        getgenv().SayzLatestRunID = nil
        getgenv().SayzSettings = nil
        print("SayzHub: Fitur dimatikan karena UI ditutup.")
    end)
end

-- [[ 6. LOAD MODULES ]] --
loadstring(game:HttpGet(GetRaw("Modules/Beranda.lua")))()(Window)
loadstring(game:HttpGet(GetRaw("Modules/Automation.lua")))()(Window)
loadstring(game:HttpGet(GetRaw("Modules/Miscs.lua")))()(Window)

Window:Notify("SayzUI Berhasil Dimuat!", 3, "ok")
