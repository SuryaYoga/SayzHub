return function(Window)
    -- [[ 1. SETUP TAB ]] --
    local OtomatisTab = Window:AddMainTab("Automation")
    local PnBSub = OtomatisTab:AddSubTab("Auto PnB")
    local CollectSub = OtomatisTab:AddSubTab("Auto Collect")

    -- [[ 2. KONFIGURASI INTERNAL ]] --
    -- Sesuaikan Username dan Repo kamu di sini agar 100% akurat
    local user = "SuryaYoga"
    local repo = "SayzHub"
    local branch = "main"
    local folder = "Automation/"

    -- Fungsi lokal untuk merakit URL Raw GitHub
    local function getLocalRaw(fileName)
        return string.format("https://raw.githubusercontent.com/%s/%s/refs/heads/%s/%s", user, repo, branch, fileName)
    end

    -- [[ 3. FUNGSI PEMANGGIL AMAN ]] --
    local function SafeLoad(fileName, subTabObj)
        local url = getLocalRaw(fileName)
        
        local success, code = pcall(game.HttpGet, game, url)
        
        if success and code and #code > 0 then
            local func, err = loadstring(code)
            if func then
                -- Jalankan fungsi kodenya
                local runSuccess, result = pcall(func)
                
                if runSuccess and type(result) == "function" then
                    -- Oper SubTab dan Window ke file fitur
                    result(subTabObj, Window)
                elseif not runSuccess then
                    warn("❌ Runtime Error di " .. fileName .. ": " .. tostring(result))
                end
            else
                warn("❌ Syntax Error di " .. fileName .. ": " .. tostring(err))
            end
        else
            warn("❌ HTTP 404: File tidak ditemukan di URL: " .. url)
        end
    end

    -- [[ 4. EKSEKUSI ]] --
    SafeLoad("AutoPnB.lua", PnBSub)
    SafeLoad("AutoCollect.lua", CollectSub)
end
