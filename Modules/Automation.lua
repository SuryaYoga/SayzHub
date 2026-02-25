return function(Window)
    -- [[ 1. SETUP TAB ]] --
    local OtomatisTab = Window:AddMainTab("Automation")
    local PnBSub = OtomatisTab:AddSubTab("Auto PnB")
    local CollectSub = OtomatisTab:AddSubTab("Auto Collect")

    -- Sesuaikan dengan nama folder di GitHub kamu (Case Sensitive)
    local featurePath = "Automation/" 

    -- [[ 2. FUNGSI PEMANGGIL PINTAR ]] --
    local function SafeLoad(path, subTabObj)
        local url = getgenv().GetRaw(path)
        
        -- Ambil kode dari GitHub
        local success, code = pcall(game.HttpGet, game, url)
        
        if success and code and #code > 0 then
            -- Compile kode menjadi fungsi
            local func, err = loadstring(code)
            
            if func then
                -- Jalankan fungsi dan kirimkan SubTab serta Window utama
                local runSuccess, result = pcall(func)
                
                if runSuccess then
                    if type(result) == "function" then
                        -- Jika file pakai 'return function(SubTab, Window)'
                        result(subTabObj, Window)
                    else
                        -- Jika file isinya kode langsung (tanpa return function)
                        -- Kita bungkus supaya dia tetap kenal variabel 'SubTab' dan 'Window'
                        local wrapper = loadstring("local SubTab, Window = ...; " .. code)
                        if wrapper then
                            pcall(wrapper, subTabObj, Window)
                        end
                    end
                else
                    warn("❌ Runtime Error di " .. path .. ": " .. tostring(result))
                end
            else
                warn("❌ Syntax Error di " .. path .. ": " .. tostring(err))
            end
        else
            warn("❌ HTTP Error: File tidak ditemukan di " .. url)
        end
    end

    -- [[ 3. EKSEKUSI ]] --
    -- Panggil file PnB dan Collect
    SafeLoad(featurePath .. "AutoPnB.lua", PnBSub)
    SafeLoad(featurePath .. "AutoCollect.lua", CollectSub)
end
