return function(Window)
    -- 1. Setup Tab & SubTab
    local OtomatisTab = Window:AddMainTab("Automation")
    local PnBSub = OtomatisTab:AddSubTab("Auto PnB")
    local CollectSub = OtomatisTab:AddSubTab("Auto Collect")

    -- 2) Ambil pembuat URL dari main kalau ada (lebih fleksibel)
    local GetRaw = getgenv().GetRaw
    local function MakeUrl(pathOrFile)
        if type(GetRaw) == "function" then
            -- pathOrFile contoh: "Automation/AutoPnB.lua"
            return GetRaw(pathOrFile)
        end
        -- fallback kalau GetRaw belum diset
        return "https://raw.githubusercontent.com/SuryaYoga/SayzHub/main/" .. tostring(pathOrFile)
    end

    -- 3. Loader yang aman
    local function LoadFitur(path, subTabObj)
        local fullUrl = MakeUrl(path)

        -- HttpGet aman
        local okHttp, code = pcall(function()
            return game:HttpGet(fullUrl)
        end)
        if not okHttp or type(code) ~= "string" then
            warn("❌ Gagal HttpGet / 404: " .. tostring(fullUrl))
            return
        end

        -- Compile
        local chunk, err = loadstring(code)
        if not chunk then
            warn("❌ Syntax Error di file " .. tostring(path) .. ": " .. tostring(err))
            return
        end

        -- Execute chunk -> harus return function(SubTab, Window)
        local okRun, exported = pcall(chunk)
        if not okRun then
            warn("❌ Error saat load chunk " .. tostring(path) .. ": " .. tostring(exported))
            return
        end

        if type(exported) ~= "function" then
            warn("❌ " .. tostring(path) .. " harus `return function(SubTab, Window) ... end`")
            return
        end

        -- Jalankan modul
        local okExec, runErr = pcall(function()
            exported(subTabObj, Window)
        end)
        if not okExec then
            warn("❌ Error saat menjalankan isi " .. tostring(path) .. ": " .. tostring(runErr))
        end
    end

    -- 4. Eksekusi
    LoadFitur("Automation/AutoPnB.lua", PnBSub)
    LoadFitur("Automation/AutoCollect.lua", CollectSub)
end
