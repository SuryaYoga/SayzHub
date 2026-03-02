return function(SubTab, Window, myToken)
    -- ========================================
    -- [1] SETUP & VARIABLES
    -- ========================================
    local Players           = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LP                = Players.LocalPlayer
    local worldData         = require(ReplicatedStorage.WorldTiles)
    local movementModule    = require(LP.PlayerScripts.PlayerMovement)

    local PlayerFist = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlayerFist")

    getgenv().AutoClear_Enabled  = getgenv().AutoClear_Enabled  or false
    getgenv().AutoClear_BreakDelay = getgenv().AutoClear_BreakDelay or 0.035

    local WORLD_MIN_X = 0
    local WORLD_MAX_X = 100
    local WORLD_MIN_Y = 6    -- batas bawah (bedrock area)
    local WORLD_MAX_Y = 60   -- batas atas

    -- ========================================
    -- [2] HELPER FUNCTIONS
    -- ========================================

    -- Cek apakah tile ini harus di-skip (tidak boleh di-break)
    local function shouldSkip(itemName)
        if not itemName then return false end
        local n = string.lower(tostring(itemName))
        if string.find(n, "lock") then return true end  -- semua lock variant
        if string.find(n, "door") then return true end  -- semua door variant
        if n == "bedrock"         then return true end
        return false
    end

    -- Cek apakah tile (gx, gy) punya lock_area
    local function isLockArea(gx, gy)
        local tile = worldData[gx] and worldData[gx][gy]
        if not tile then return false end
        for _, layerData in pairs(tile) do
            if type(layerData) == "table" then
                -- Cek apakah ada key "lock_area" di data tile
                for k, v in pairs(layerData) do
                    if tostring(v) == "lock_area" then return true end
                end
            elseif type(layerData) == "string" then
                if string.lower(layerData) == "lock_area" then return true end
            end
        end
        return false
    end

    -- Cek apakah tile punya konten yang perlu di-break (block layer 1 atau background layer 2)
    local function getTileLayers(gx, gy)
        local tile = worldData[gx] and worldData[gx][gy]
        if not tile then return false, false end

        local hasBlock = false
        local hasBg    = false

        -- Layer 1 = foreground block
        if tile[1] ~= nil then
            local itemName = (type(tile[1]) == "table") and tile[1][1] or tile[1]
            if itemName and not shouldSkip(itemName) then
                hasBlock = true
            end
        end
        -- Layer 2 = background
        if tile[2] ~= nil then
            local itemName = (type(tile[2]) == "table") and tile[2][1] or tile[2]
            if itemName and not shouldSkip(itemName) then
                hasBg = true
            end
        end

        return hasBlock, hasBg
    end

    -- Detect Y paling atas yang ada isinya di seluruh world
    local function findTopY()
        local topY = WORLD_MIN_Y
        for gx = WORLD_MIN_X, WORLD_MAX_X do
            for gy = WORLD_MAX_Y, WORLD_MIN_Y, -1 do
                local tile = worldData[gx] and worldData[gx][gy]
                if tile and (tile[1] ~= nil or tile[2] ~= nil) then
                    if gy > topY then topY = gy end
                    break
                end
            end
        end
        return topY
    end

    -- Pindahkan player ke posisi grid (gx, gy+1) — berdiri di atas tile
    local function movePlayerTo(gx, gy)
        local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
        if not Hitbox then return end
        local wx = gx * 4.5
        local wy = (gy + 1) * 4.5  -- berdiri 1 tile di atas target
        Hitbox.CFrame = CFrame.new(wx, wy, Hitbox.Position.Z)
        movementModule.Position = Hitbox.Position
    end

    -- Break tile (gx, gy) sampai benar-benar kosong (block + background)
    local function breakTile(gx, gy)
        if isLockArea(gx, gy) then return end

        local pos = Vector2.new(gx, gy)
        local maxHits = 30  -- maksimal hit supaya tidak infinite loop
        local hits = 0

        while _G.LatestRunToken == myToken and getgenv().AutoClear_Enabled do
            local hasBlock, hasBg = getTileLayers(gx, gy)
            if not hasBlock and not hasBg then break end
            if hits >= maxHits then break end

            PlayerFist:FireServer(pos)
            hits = hits + 1
            task.wait(getgenv().AutoClear_BreakDelay)
        end
    end

    -- ========================================
    -- [3] UI ELEMENTS
    -- ========================================

    SubTab:AddSection("AUTO CLEAR")
    getgenv().SayzUI_Handles["AutoClear_Master"] = SubTab:AddToggle("Enable Auto Clear", getgenv().AutoClear_Enabled, function(t)
        getgenv().AutoClear_Enabled = t
    end)
    getgenv().SayzUI_Handles["AutoClear_BreakDelay"] = SubTab:AddSlider("Break Delay", 0.01, 0.2, getgenv().AutoClear_BreakDelay, function(val)
        getgenv().AutoClear_BreakDelay = val
    end, 2)

    SubTab:AddSection("STATUS")
    local StatusLabel  = SubTab:AddLabel("Status  : Idle")
    local PosLabel     = SubTab:AddLabel("Posisi  : -")
    local ProgressLabel = SubTab:AddLabel("Progress: -")

    SubTab:AddSection("PANDUAN")
    SubTab:AddLabel("1. Aktifkan Enable Auto Clear.")
    SubTab:AddLabel("2. Bot otomatis detect posisi paling")
    SubTab:AddLabel("   atas world lalu mulai break.")
    SubTab:AddLabel("3. Arah: kiri→kanan turun, kanan→kiri")
    SubTab:AddLabel("   turun (zig-zag) sampai bawah.")
    SubTab:AddLabel("4. Skip: bedrock, semua lock, semua door,")
    SubTab:AddLabel("   dan tile dalam area lock.")
    SubTab:AddLabel("5. Matikan toggle untuk stop kapan saja.")

    -- ========================================
    -- [4] GRAVITY BYPASS
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait()
            if getgenv().AutoClear_Enabled then
                pcall(function()
                    if movementModule.VelocityY < 0 then movementModule.VelocityY = 0 end
                    movementModule.Grounded = true
                end)
            end
        end
    end)

    -- ========================================
    -- [5] MAIN LOOP
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            if getgenv().AutoClear_Enabled then
                pcall(function()
                    StatusLabel:SetText("Status  : Mendeteksi area...")

                    -- Detect Y paling atas
                    local startY = findTopY()
                    local totalCols = WORLD_MAX_X - WORLD_MIN_X + 1
                    local totalRows = startY - WORLD_MIN_Y + 1
                    local totalTiles = totalCols * totalRows
                    local doneCount = 0

                    StatusLabel:SetText("Status  : Clearing...")

                    local goingRight = true  -- arah zig-zag

                    for gy = startY, WORLD_MIN_Y, -1 do
                        if not getgenv().AutoClear_Enabled or _G.LatestRunToken ~= myToken then break end

                        local xStart, xEnd, xStep
                        if goingRight then
                            xStart = WORLD_MIN_X
                            xEnd   = WORLD_MAX_X
                            xStep  = 1
                        else
                            xStart = WORLD_MAX_X
                            xEnd   = WORLD_MIN_X
                            xStep  = -1
                        end

                        for gx = xStart, xEnd, xStep do
                            if not getgenv().AutoClear_Enabled or _G.LatestRunToken ~= myToken then break end

                            local hasBlock, hasBg = getTileLayers(gx, gy)
                            if hasBlock or hasBg then
                                -- Pindah player ke atas tile ini
                                movePlayerTo(gx, gy)
                                task.wait(0.05)

                                -- Break tile sampai kosong (block dulu, lalu bg)
                                breakTile(gx, gy)
                            end

                            doneCount = doneCount + 1
                            PosLabel:SetText(string.format("Posisi  : (%d, %d)", gx, gy))
                            ProgressLabel:SetText(string.format("Progress: %d/%d (%.1f%%)",
                                doneCount, totalTiles, (doneCount / totalTiles) * 100))
                        end

                        goingRight = not goingRight  -- balik arah tiap baris
                    end

                    if getgenv().AutoClear_Enabled then
                        StatusLabel:SetText("Status  : Selesai!")
                        getgenv().AutoClear_Enabled = false
                        -- Update toggle UI
                        if getgenv().SayzUI_Handles["AutoClear_Master"] then
                            getgenv().SayzUI_Handles["AutoClear_Master"]:Set(false)
                        end
                        Window:Notify("Auto Clear selesai!", 3, "ok")
                    end
                end)
            else
                StatusLabel:SetText("Status  : Idle")
            end
            task.wait(0.5)
        end
    end)
end
