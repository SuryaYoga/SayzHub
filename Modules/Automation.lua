return function(Window)
    local OtomatisTab = Window:AddMainTab("Automation")
    local PnBSub = OtomatisTab:AddSubTab("Auto PnB")
    local CollectSub = OtomatisTab:AddSubTab("Auto Collect")

    local featurePath = "Automation/" 

    local function SafeLoad(path, tabObj)
        local url = getgenv().GetRaw(path)
        local success, code = pcall(game.HttpGet, game, url)
        
        if success and code then
            local func, err = loadstring(code)
            if func then
                -- Coba panggil sebagai fungsi pembungkus dulu
                local runSuccess, result = pcall(func)
                
                if runSuccess then
                    if type(result) == "function" then
                        -- Jika file mengembalikan fungsi (return function(SubTab))
                        result(tabObj)
                    else
                        -- Jika file berisi kode langsung (Tanpa return function)
                        -- Kita perlu menjalankan ulang dengan variabel 'SubTab' yang terdefinisi
                        local directFunc = loadstring("local SubTab = ...; " .. code)
                        directFunc(tabObj)
                    end
                else
                    warn("❌ Error saat menjalankan " .. path .. ": " .. tostring(result))
                end
            else
                warn("❌ Syntax Error di " .. path .. ": " .. tostring(err))
            end
        else
            warn("❌ Gagal download file: " .. url)
        end
    end

    SafeLoad(featurePath .. "AutoPnB.lua", PnBSub)
    SafeLoad(featurePath .. "AutoCollect.lua", CollectSub)
end
