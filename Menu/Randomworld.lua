return function(SubTab, Window, myToken)
    -- ========================================
    -- [1] SETUP
    -- ========================================
    local tp = game:GetService("ReplicatedStorage"):WaitForChild("tp")

    local RW = {
        WithNumber = false,
        WordLength = 5,
    }

    -- Karakter yang dipakai untuk generate nama world
    local CHARS_ALPHA  = "abcdefghijklmnopqrstuvwxyz"
    local CHARS_ALPHANUM = "abcdefghijklmnopqrstuvwxyz0123456789"

    local function randomWorldName(length, withNumber)
        local chars = withNumber and CHARS_ALPHANUM or CHARS_ALPHA
        local result = ""
        for i = 1, length do
            local idx = math.random(1, #chars)
            result = result .. string.sub(chars, idx, idx)
        end
        return result
    end

    -- ========================================
    -- [2] UI
    -- ========================================
    SubTab:AddSection("PENGATURAN")

    getgenv().SayzUI_Handles["RW_WithNumber"] = SubTab:AddToggle("With Number", RW.WithNumber, function(t)
        RW.WithNumber = t
    end)

    getgenv().SayzUI_Handles["RW_WordLength"] = SubTab:AddSlider("Panjang Nama", 1, 100, RW.WordLength, function(val)
        RW.WordLength = val
    end, 0)

    SubTab:AddSection("AKSI")

    local PreviewLabel = SubTab:AddLabel("World: -")
    local StatusLabel  = SubTab:AddLabel("Status: Idle")

    SubTab:AddButton("🎲 Generate & Teleport", function()
        local worldName = randomWorldName(RW.WordLength, RW.WithNumber)
        PreviewLabel:SetText("World: " .. worldName)
        StatusLabel:SetText("Status: Teleporting...")

        local ok, err = pcall(function()
            tp:FireServer(worldName)
        end)

        if ok then
            StatusLabel:SetText("Status: Berhasil masuk " .. worldName)
            Window:Notify("Teleport ke: " .. worldName, 3, "ok")
        else
            StatusLabel:SetText("Status: Gagal!")
            Window:Notify("Gagal teleport: " .. tostring(err), 3, "danger")
        end
    end)

    SubTab:AddButton("🔄 Generate Ulang (Tanpa Teleport)", function()
        local worldName = randomWorldName(RW.WordLength, RW.WithNumber)
        PreviewLabel:SetText("World: " .. worldName)
        StatusLabel:SetText("Status: Preview saja")
    end)

end
