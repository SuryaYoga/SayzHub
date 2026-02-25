return function(Window)
    local OtomatisTab = Window:AddMainTab("Automation")
    local PnBSub = OtomatisTab:AddSubTab("Auto PnB")
    local CollectSub = OtomatisTab:AddSubTab("Auto Collect")

    local featurePath = "Automation/" 

    local function SafeLoad(path, tabObj)
        -- Ambil URL Raw
        local url = getgenv().GetRaw(path)
        
        -- Cek apakah file ada
        local success, code = pcall(game.HttpGet, game, url)
        
        if success and code and #code > 0 then
            -- Coba compile kodenya
            local func, err = loadstring(code)
            
            if func then
                -- Jalankan fungsi kodenya
                local runSuccess, runErr = pcall(function()
                    func()(tabObj)
                end)
                
                if not runSuccess then
                    warn("❌ Error saat menjalankan isi file: " .. path .. " | Error: " .. tostring(runErr))
                end
            else
                warn("❌ Gagal Compile (Syntax Error) di file: " .. path .. " | Error: " .. tostring(err))
                print("Isi kode yang terbaca: " .. string.sub(code, 1, 100) .. "...")
            end
        else
            warn("❌ HTTP Error: File tidak ditemukan atau kosong di: " .. url)
        end
    end

    -- Eksekusi dengan proteksi
    SafeLoad(featurePath .. "AutoPnB.lua", PnBSub)
    SafeLoad(featurePath .. "AutoCollect.lua", CollectSub)
end
