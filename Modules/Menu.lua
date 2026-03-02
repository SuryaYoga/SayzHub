return function(Window)
    local MenuTab = Window:AddMainTab("Menu")
    local CheatsSub = MenuTab:AddSubTab("Cheats")

    local myToken = _G.LatestRunToken

    local function LoadFitur(fileName, subTabObj)
        local fullUrl = getgenv().GetRaw("Menu/" .. fileName)
        local maxRetries = 3
        local code = nil
        local success = false

        for i = 1, maxRetries do
            success, code = pcall(function()
                return game:HttpGet(fullUrl)
            end)
            if success and type(code) == "string" then break end
            task.wait(1.5)
        end

        if not success then
            Window:Notify("Gagal download: " .. fileName, 5, "danger")
            warn("❌ SayzHub: Gagal memuat modul setelah 3x percobaan.")
            return
        end

        local chunk, err = loadstring(code)
        if not chunk then
            warn("❌ SayzHub Syntax Error [" .. fileName .. "]: " .. tostring(err))
            return
        end

        local ok, exported = pcall(chunk)
        if ok and type(exported) == "function" then
            local ok2, runErr = pcall(function()
                exported(subTabObj, Window, myToken)
            end)
            if not ok2 then
                warn("❌ SayzHub Runtime Error [" .. fileName .. "]: " .. tostring(runErr))
            end
        else
            warn("❌ SayzHub: Modul " .. fileName .. " tidak mengembalikan fungsi.")
        end
    end

    LoadFitur("Cheats.lua", CheatsSub)
end
