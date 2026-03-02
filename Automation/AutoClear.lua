return function(SubTab, Window, myToken)
    -- ========================================
    -- [1] SETUP & VARIABLES
    -- ========================================
    local Players           = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LP                = Players.LocalPlayer
    local worldData         = require(ReplicatedStorage.WorldTiles)
    local movementModule    = require(LP.PlayerScripts.PlayerMovement)

    local PlayerFist   = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlayerFist")
    local MovPacket    = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlayerMovementPackets"):WaitForChild(LP.Name)

    getgenv().AutoClear_Enabled    = getgenv().AutoClear_Enabled    or false
    getgenv().AutoClear_BreakDelay = getgenv().AutoClear_BreakDelay or 0.035
    getgenv().AutoClear_StepDelay  = getgenv().AutoClear_StepDelay  or 0.05

    local WORLD_MIN_X = 0
    local WORLD_MAX_X = 100
    local WORLD_MIN_Y = 6
    local WORLD_MAX_Y = 60



    -- ========================================
    -- [2] HELPER FUNCTIONS
    -- ========================================

    local function shouldSkip(itemName)
        if not itemName then return false end
        local n = string.lower(tostring(itemName))
        if string.find(n, "lock") then return true end
        if string.find(n, "door") then return true end
        if n == "bedrock"         then return true end
        return false
    end

    local function isLockArea(gx, gy)
        local tile = worldData[gx] and worldData[gx][gy]
        if not tile then return false end
        -- Cek semua layer dan semua key di tile
        for _, layerData in pairs(tile) do
            if type(layerData) == "table" then
                for k, v in pairs(layerData) do
                    if tostring(v) == "lock_area" then return true end
                    if tostring(k) == "lock_area" then return true end
                end
            elseif type(layerData) == "string" then
                if string.lower(layerData) == "lock_area" then return true end
            end
        end
        return false
    end

    local function getTileLayers(gx, gy)
        local tile = worldData[gx] and worldData[gx][gy]
        if not tile then return false, false end
        local hasBlock, hasBg = false, false
        if tile[1] ~= nil then
            local itemName = (type(tile[1]) == "table") and tile[1][1] or tile[1]
            if itemName and not shouldSkip(itemName) then hasBlock = true end
        end
        if tile[2] ~= nil then
            local itemName = (type(tile[2]) == "table") and tile[2][1] or tile[2]
            if itemName and not shouldSkip(itemName) then hasBg = true end
        end
        return hasBlock, hasBg
    end

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

    -- ========================================
    -- [3] PATHFINDING
    -- ========================================

    local function isWalkable(gx, gy)
        if gx < WORLD_MIN_X or gx > WORLD_MAX_X or gy < WORLD_MIN_Y or gy > WORLD_MAX_Y then
            return false
        end
        -- Lock area = hard block (bot tidak perlu masuk ke sana)
        if isLockArea(gx, gy) then return false end
        -- Tile ada isi apapun di layer 1 = hard block
        if worldData[gx] and worldData[gx][gy] and worldData[gx][gy][1] ~= nil then
            return false
        end
        return true
    end

    local function findSmartPath(startX, startY, targetX, targetY)
        local startKey = startX .. "," .. startY
        local queue    = {{x = startX, y = startY, cost = 0, parent = nil}}
        local visited  = {[startKey] = 0}
        local dirs     = {
            {x=1,y=0},{x=-1,y=0},
            {x=0,y=1},{x=0,y=-1}
        }
        local found      = nil
        local limitCount = 0

        while #queue > 0 do
            if _G.LatestRunToken ~= myToken then break end
            limitCount = limitCount + 1
            if limitCount > 4000 then break end

            -- Linear scan cari cost terendah
            local minIdx, minCost = 1, queue[1].cost
            for i = 2, #queue do
                if queue[i].cost < minCost then
                    minCost = queue[i].cost
                    minIdx  = i
                end
            end
            local current = table.remove(queue, minIdx)

            if current.x == targetX and current.y == targetY then
                found = current
                break
            end

            for _, d in ipairs(dirs) do
                local nx, ny = current.x + d.x, current.y + d.y
                local nkey   = nx .. "," .. ny
                if isWalkable(nx, ny) then
                    local newCost = current.cost + 1
                    if not visited[nkey] or newCost < visited[nkey] then
                        visited[nkey] = newCost
                        table.insert(queue, {x=nx, y=ny, cost=newCost, parent=current})
                    end
                end
            end
        end

        if not found then return nil end

        -- Reconstruct path
        local path = {}
        local node = found
        while node.parent ~= nil do
            table.insert(path, 1, Vector3.new(node.x * 4.5, node.y * 4.5, 0))
            node = node.parent
        end
        return path
    end

    -- ========================================
    -- [4] MOVEMENT
    -- ========================================

    local function walkToGrid(gx, gy, StatusLabel)
        local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
        if not Hitbox then return end

        local sx = math.floor(Hitbox.Position.X / 4.5 + 0.5)
        local sy = math.floor(Hitbox.Position.Y / 4.5 + 0.5)

        if sx == gx and sy == gy then return end

        local path = findSmartPath(sx, sy, gx, gy)
        if not path then
            -- Fallback teleport
            Hitbox.CFrame = CFrame.new(gx * 4.5, gy * 4.5, Hitbox.Position.Z)
            movementModule.Position = Hitbox.Position
            pcall(function() MovPacket:FireServer(gx * 4.5, gy * 4.5) end)
            task.wait(0.2)
            return
        end

        for i, point in ipairs(path) do
            if not getgenv().AutoClear_Enabled or _G.LatestRunToken ~= myToken then break end
            if StatusLabel then
                StatusLabel:SetText(string.format("Status  : Jalan (%d/%d)...", i, #path))
            end

            local px = math.floor(point.X / 4.5 + 0.5)
            local py = math.floor(point.Y / 4.5 + 0.5)

            -- Set posisi
            Hitbox.CFrame = CFrame.new(point.X, point.Y, Hitbox.Position.Z)
            movementModule.Position = Hitbox.Position
            pcall(function() MovPacket:FireServer(point.X, point.Y) end)
            task.wait(getgenv().AutoClear_StepDelay)

            -- Tunggu karakter beneran sampai di step ini (max 0.5 detik)
            local waitCount = 0
            while not isAtPosition(px, py) and waitCount < 10 do
                pcall(function() MovPacket:FireServer(point.X, point.Y) end)
                task.wait(0.05)
                waitCount = waitCount + 1
            end
        end
    end

    -- Cek apakah karakter sudah beneran di posisi grid (gx, gy)
    local function isAtPosition(gx, gy)
        local char = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not char then return false end
        local cx = math.floor(char.Position.X / 4.5 + 0.5)
        local cy = math.floor(char.Position.Y / 4.5 + 0.5)
        return cx == gx and cy == gy
    end

    -- Break tile (gx, gy) — hanya mukul kalau karakter sudah di (gx, gy+1)
    local function breakTile(gx, gy)
        if isLockArea(gx, gy) then return end
        local pos     = Vector2.new(gx, gy)
        local maxHits = 30
        local hits    = 0
        local stuckWait = 0

        while _G.LatestRunToken == myToken and getgenv().AutoClear_Enabled do
            local hasBlock, hasBg = getTileLayers(gx, gy)
            if not hasBlock and not hasBg then break end
            if hits >= maxHits then break end

            -- Cek posisi karakter dulu sebelum mukul
            if isAtPosition(gx, gy + 1) then
                pcall(function() MovPacket:FireServer(gx * 4.5, (gy + 1) * 4.5) end)
                PlayerFist:FireServer(pos)
                hits = hits + 1
                stuckWait = 0
                task.wait(getgenv().AutoClear_BreakDelay)
            else
                -- Karakter belum di posisi / dibalikin server — sync ulang dan tunggu
                pcall(function()
                    local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
                    if Hitbox then
                        Hitbox.CFrame = CFrame.new(gx * 4.5, (gy + 1) * 4.5, Hitbox.Position.Z)
                        movementModule.Position = Hitbox.Position
                        MovPacket:FireServer(gx * 4.5, (gy + 1) * 4.5)
                    end
                end)
                stuckWait = stuckWait + 1
                if stuckWait > 20 then break end
                task.wait(0.1)
            end
        end
    end

    -- ========================================
    -- [5] UI ELEMENTS
    -- ========================================

    SubTab:AddSection("AUTO CLEAR")
    getgenv().SayzUI_Handles["AutoClear_Master"] = SubTab:AddToggle("Enable Auto Clear", getgenv().AutoClear_Enabled, function(t)
        getgenv().AutoClear_Enabled = t
    end)
    getgenv().SayzUI_Handles["AutoClear_BreakDelay"] = SubTab:AddSlider("Break Delay", 0.01, 0.2, getgenv().AutoClear_BreakDelay, function(val)
        getgenv().AutoClear_BreakDelay = val
    end, 2)
    getgenv().SayzUI_Handles["AutoClear_StepDelay"] = SubTab:AddSlider("Move Speed", 0.01, 0.2, getgenv().AutoClear_StepDelay, function(val)
        getgenv().AutoClear_StepDelay = val
    end, 2)

    SubTab:AddSection("STATUS")
    local StatusLabel   = SubTab:AddLabel("Status  : Idle")
    local PosLabel      = SubTab:AddLabel("Posisi  : -")
    local ProgressLabel = SubTab:AddLabel("Progress: -")

    SubTab:AddSection("PANDUAN")
    SubTab:AddLabel("1. Aktifkan Enable Auto Clear.")
    SubTab:AddLabel("2. Bot otomatis detect posisi paling")
    SubTab:AddLabel("   atas world lalu mulai break.")
    SubTab:AddLabel("3. Arah: kiri→kanan turun, kanan→kiri")
    SubTab:AddLabel("   turun (zig-zag) sampai bawah.")
    SubTab:AddLabel("4. Skip: bedrock, semua lock, semua door,")
    SubTab:AddLabel("   dan tile dalam area lock.")
    SubTab:AddLabel("5. Bot jalan ke tile via SmartPath.")
    SubTab:AddLabel("6. Matikan toggle untuk stop kapan saja.")

    -- ========================================
    -- [6] GRAVITY BYPASS
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
    -- [7] MAIN LOOP
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            if getgenv().AutoClear_Enabled then
                pcall(function()
                    StatusLabel:SetText("Status  : Mendeteksi area...")

                    local startY    = findTopY()
                    local totalCols = WORLD_MAX_X - WORLD_MIN_X + 1
                    local totalRows = startY - WORLD_MIN_Y + 1
                    local totalTiles = totalCols * totalRows
                    local doneCount  = 0
                    local goingRight = true

                    for gy = startY, WORLD_MIN_Y, -1 do
                        if not getgenv().AutoClear_Enabled or _G.LatestRunToken ~= myToken then break end

                        local xStart = goingRight and WORLD_MIN_X or WORLD_MAX_X
                        local xEnd   = goingRight and WORLD_MAX_X or WORLD_MIN_X
                        local xStep  = goingRight and 1 or -1

                        for gx = xStart, xEnd, xStep do
                            if not getgenv().AutoClear_Enabled or _G.LatestRunToken ~= myToken then break end

                            local hasBlock, hasBg = getTileLayers(gx, gy)
                            if (hasBlock or hasBg) and not isLockArea(gx, gy) then
                                -- Jalan ke 1 tile di atas target
                                walkToGrid(gx, gy + 1, StatusLabel)
                                task.wait(0.05)

                                -- Break tile sampai kosong
                                StatusLabel:SetText(string.format("Status  : Breaking (%d,%d)...", gx, gy))
                                breakTile(gx, gy)
                            end

                            doneCount = doneCount + 1
                            PosLabel:SetText(string.format("Posisi  : (%d, %d)", gx, gy))
                            ProgressLabel:SetText(string.format("Progress: %d/%d (%.1f%%)",
                                doneCount, totalTiles, (doneCount / totalTiles) * 100))
                        end

                        goingRight = not goingRight
                    end

                    if getgenv().AutoClear_Enabled then
                        StatusLabel:SetText("Status  : Selesai!")
                        ProgressLabel:SetText("Progress: 100%")
                        getgenv().AutoClear_Enabled = false
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
