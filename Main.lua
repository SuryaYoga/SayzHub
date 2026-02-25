-- [[ CONFIGURATION ]] --
getgenv().SayzConfig = {
    UserName = "UsernameKamu", -- GANTI INI
    Repo = "SayzUI_Project",   -- GANTI INI
    Branch = "main"
}

local function GetRaw(path)
    return string.format("https://raw.githubusercontent.com/%s/%s/%s/%s", 
        getgenv().SayzConfig.UserName, getgenv().SayzConfig.Repo, getgenv().SayzConfig.Branch, path)
end

-- [[ LOAD UI LIBRARY ]] --
local SayzUI = loadstring(game:HttpGet("https://pastebin.com/raw/hys38rNm"))()

local Window = SayzUI:CreateWindow({
    Title = "SayzUI v1",
    Subtitle = "BlueWhite Edition",
    Theme = "BlueWhite",
    Keybind = Enum.KeyCode.K,
    ShowWelcomeToast = true,
    Loading = {
        Enabled = true,
        Text = "Loading SayzUI v1...",
        Duration = 1.5
    }
})

-- [[ GLOBAL SETTINGS ]] --
-- Variabel yang sering diakses antar tab ditaruh di getgenv()
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

-- [[ LOAD MODULES ]] --
-- Memanggil Tab-Tab Utama
loadstring(game:HttpGet(GetRaw("Modules/Beranda.lua")))()(Window)
loadstring(game:HttpGet(GetRaw("Modules/Automation.lua")))()(Window)
loadstring(game:HttpGet(GetRaw("Modules/Miscs.lua")))()(Window)

Window:Notify("SayzUI Modular Berhasil Dimuat!", 3, "ok")