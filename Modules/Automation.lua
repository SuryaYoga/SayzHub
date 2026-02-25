return function(Window)
    local OtomatisTab = Window:AddMainTab("Automation")
    
    -- Buat SubTab-nya di sini
    local PnBSub = OtomatisTab:AddSubTab("Auto PnB")
    local CollectSub = OtomatisTab:AddSubTab("Auto Collect")

    -- Gunakan link RAW GitHub kamu nanti
    local baseUrl = "https://raw.githubusercontent.com/Username/Repo/main/"

    -- Manggil fitur dengan nama yang kamu mau
    -- Kita panggil Collect dulu supaya fungsi GPS-nya siap dipakai
    loadstring(game:HttpGet(baseUrl .. "AutoCollect.lua"))()(CollectSub)
    loadstring(game:HttpGet(baseUrl .. "AutoPnB.lua"))()(PnBSub)
end