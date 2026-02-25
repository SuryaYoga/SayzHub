return function(Window)
    -- 1. Buat Tab Utama
    local OtomatisTab = Window:AddMainTab("Automation")

    -- 2. Buat SubTab (Rumah untuk fiturnya)
    local PnBSub = OtomatisTab:AddSubTab("Auto PnB")
    local CollectSub = OtomatisTab:AddSubTab("Auto Collect")

    -- 3. Path Folder Fitur
    local featurePath = "Automation/"

    -- 4. Panggil Fitur Auto PnB
    -- Kita kirim 'PnBSub' agar UI PnB nempel di SubTab ini
    local pnbSource = game:HttpGet(getgenv().GetRaw(featurePath .. "AutoPnB.lua"))
    loadstring(pnbSource)()(PnBSub)

    -- 5. Panggil Fitur Auto Collect
    -- Kita kirim 'CollectSub' agar UI Collect nempel di SubTab ini
    local collectSource = game:HttpGet(getgenv().GetRaw(featurePath .. "AutoCollect.lua"))
    loadstring(collectSource)()(CollectSub)
end
