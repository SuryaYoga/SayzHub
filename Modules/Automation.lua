return function(Window)
    local OtomatisTab = Window:AddMainTab("Automation")
    local PnBSub = OtomatisTab:AddSubTab("Auto PnB")
    local CollectSub = OtomatisTab:AddSubTab("Auto Collect")

    local featurePath = "Automation/" 

    -- Fungsi buat panggil file dengan proteksi agar tidak 'nil'
    local function SafeLoad(path, tabObj)
        local success, code = pcall(game.HttpGet, game, getgenv().GetRaw(path))
        if success and code then
            local func, err = loadstring(code)
            if func then
                -- Menjalankan isi file dan mengirimkan SubTab-nya
                func()(tabObj) 
            else
                warn("Gagal loadstring file: " .. path .. " | Error: " .. tostring(err))
            end
        else
            warn("File tidak ditemukan di GitHub: " .. path)
        end
    end

    -- Eksekusi
    SafeLoad(featurePath .. "AutoPnB.lua", PnBSub)
    SafeLoad(featurePath .. "AutoCollect.lua", CollectSub)
end
