return function(Window)
    local OtomatisTab = Window:AddMainTab("Automation")
    local PnBSub = OtomatisTab:AddSubTab("Auto PnB")
    local CollectSub = OtomatisTab:AddSubTab("Auto Collect")

    -- Kita gunakan fungsi GetRaw dari main.lua agar otomatis sinkron
    local function LoadFitur(fileName, subTabObj)
        -- Path folder tempat fitur AutoPnB.lua dan AutoCollect.lua berada
        local fullUrl = getgenv().GetRaw("Automation/" .. fileName)

        local success, code = pcall(function()
            return game:HttpGet(fullUrl)
        end)

        if not success or type(code) ~= "string" then
            warn("❌ Gagal memuat fitur: " .. fileName .. " (Cek koneksi/path)")
            return
        end

        local chunk, err = loadstring(code)
        if not chunk then
            warn("❌ Syntax Error [" .. fileName .. "]: " .. tostring(err))
            return
        end

        local ok, exported = pcall(chunk)
        if ok and type(exported) == "function" then
            -- Jalankan fitur dan kirim Window sebagai parameter
            local ok2, runErr = pcall(function()
                exported(subTabObj, Window)
            end)
            if not ok2 then warn("❌ Runtime Error [" .. fileName .. "]: " .. tostring(runErr)) end
        else
            warn("❌ Format file " .. fileName .. " tidak valid (Bukan function)")
        end
    end

    -- Memanggil fitur-fitur utama
    LoadFitur("AutoPnB.lua", PnBSub)
    LoadFitur("AutoCollect.lua", CollectSub)
end
