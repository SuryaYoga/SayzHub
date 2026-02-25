return function(Window)
    -- 1. Setup Tab & SubTab
    local OtomatisTab = Window:AddMainTab("Automation")
    local PnBSub = OtomatisTab:AddSubTab("Auto PnB")
    local CollectSub = OtomatisTab:AddSubTab("Auto Collect")

    -- 2. Konfigurasi Link (PASTIKAN USERNAME & REPO BENAR)
    local rawPath = "https://raw.githubusercontent.com/SuryaYoga/SayzHub/main/Automation/"

    -- 3. Fungsi Panggil (Direct Load)
    local function LoadFitur(fileName, subTabObj)
        local fullUrl = rawPath .. fileName
        
        -- Kita pakai pcall supaya kalau GitHub lagi error, game kamu gak crash
        local success, code = pcall(function() 
            return game:HttpGet(fullUrl) 
        end)

        if success and code then
            local func, err = loadstring(code)
            if func then
                -- Jalankan kodenya dan kirim SubTab + Window
                local runSuccess, runErr = pcall(function()
                    func()(subTabObj, Window)
                end)
                
                if not runSuccess then
                    warn("❌ Error saat menjalankan isi " .. fileName .. ": " .. tostring(runErr))
                end
            else
                warn("❌ Syntax Error di file " .. fileName .. ": " .. tostring(err))
            end
        else
            warn("❌ HTTP 404: File tidak ditemukan di " .. fullUrl)
        end
    end

    -- 4. Eksekusi Panggilan
    LoadFitur("AutoPnB.lua", PnBSub)
    LoadFitur("AutoCollect.lua", CollectSub)
end
