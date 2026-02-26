return function(Window)
    local OtomatisTab = Window:AddMainTab("Automation")
    local PnBSub = OtomatisTab:AddSubTab("Auto PnB")
    local CollectSub = OtomatisTab:AddSubTab("Auto Collect")

    -- SESUAIKAN PATH INI DENGAN STRUKTUR REPO KAMU
    -- contoh: kalau file ada di folder "Automation/"
    local rawPath = "https://raw.githubusercontent.com/SuryaYoga/SayzHub/main/Automation/"
    -- kalau ternyata file kamu ada di "Modules/Automation/" ganti jadi:
    -- local rawPath = "https://raw.githubusercontent.com/SuryaYoga/SayzHub/main/Modules/Automation/"

    local function LoadFitur(fileName, subTabObj)
        local fullUrl = rawPath .. fileName

        local success, code = pcall(function()
            return game:HttpGet(fullUrl)
        end)

        if not success or type(code) ~= "string" then
            warn("❌ HTTP gagal / 404: " .. fullUrl)
            return
        end

        local chunk, err = loadstring(code)
        if not chunk then
            warn("❌ Syntax Error di " .. fileName .. ": " .. tostring(err))
            return
        end

        local ok, exported = pcall(chunk)
        if not ok then
            warn("❌ Error saat eval " .. fileName .. ": " .. tostring(exported))
            return
        end

        if type(exported) ~= "function" then
            warn("❌ " .. fileName .. " harus: return function(SubTab, Window) ... end")
            return
        end

        local ok2, runErr = pcall(function()
            exported(subTabObj, Window)
        end)
        if not ok2 then
            warn("❌ Error runtime " .. fileName .. ": " .. tostring(runErr))
        end
    end

    LoadFitur("AutoPnB.lua", PnBSub)
    LoadFitur("AutoCollect.lua", CollectSub)
end
