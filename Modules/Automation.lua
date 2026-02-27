-- [FIX-1] Sekarang terima myToken dari SafeLoad di Main.lua
return function(Window, myToken)
    -- Fallback jika dipanggil tanpa myToken
    myToken = myToken or _G.LatestRunToken

    local OtomatisTab = Window:AddMainTab("Automation")
    local PnBSub = OtomatisTab:AddSubTab("Auto PnB")
    local CollectSub = OtomatisTab:AddSubTab("Auto Collect")

    local function LoadFitur(fileName, subTabObj)
        local fullUrl = getgenv().GetRaw("Automation/" .. fileName)
        local maxRetries = 3
        local code = nil
        local success = false

        if Window._loadingText then
            Window:SetLoadingText("Downloading " .. fileName .. "...")
        end

        for i = 1, maxRetries do
            success, code = pcall(function()
                return game:HttpGet(fullUrl)
            end)
            if success and type(code) == "string" then break end
            task.wait(1.5)
        end

        if not success then
            Window:Notify("Gagal download: " .. fileName, 5, "danger")
            warn("SayzHub: Gagal memuat modul setelah 3x percobaan — " .. fileName)
            return
        end

        local chunk, err = loadstring(code)
        if not chunk then
            warn("SayzHub Syntax Error [" .. fileName .. "]: " .. tostring(err))
            return
        end

        local ok, exported = pcall(chunk)
        if ok and type(exported) == "function" then
            -- [FIX-4] Gunakan myToken yang sudah di-capture di awal Automation.lua
            -- bukan mengambil ulang _G.LatestRunToken di sini,
            -- sehingga semua sub-modul punya token yang sama dan konsisten
            local ok2, runErr = pcall(function()
                exported(subTabObj, Window, myToken)
            end)
            if not ok2 then
                warn("SayzHub Runtime Error [" .. fileName .. "]: " .. tostring(runErr))
            end
        else
            warn("SayzHub: Modul " .. fileName .. " tidak mengembalikan fungsi.")
        end
    end

    LoadFitur("AutoPnB.lua", PnBSub)
    LoadFitur("AutoCollect.lua", CollectSub)
end
