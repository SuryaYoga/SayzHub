return function(SubTab, Window, myToken)
    local Players           = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LP                = Players.LocalPlayer
    local worldData         = require(ReplicatedStorage.WorldTiles)
    local movementModule    = require(LP.PlayerScripts.PlayerMovement)

    local PlayerFist = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlayerFist")
    local MovPacket  = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlayerMovementPackets"):WaitForChild(LP.Name)

    getgenv().AutoClear_Enabled    = getgenv().AutoClear_Enabled    or false
    getgenv().AutoClear_BreakDelay = getgenv().AutoClear_BreakDelay or 0.035
    getgenv().AutoClear_StepDelay  = getgenv().AutoClear_StepDelay  or 0.12

    local WORLD_MIN_X = 0
    local WORLD_MAX_X = 100
    local WORLD_MIN_Y = 6
    local WORLD_MAX_Y = 60
    local GRID_SIZE   = 4.5
    local OFFSET_Y    = -0.249640

    -- ========================================
    -- [2] HELPERS
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
            local n = (type(tile[1]) == "table") and tile[1][1] or tile[1]
            if n and not shouldSkip(n) then hasBlock = true end
        end
        if tile[2] ~= nil then
            local n = (type(tile[2]) == "table") and tile[2][1] or tile[2]
            if n and not shouldSkip(n) then hasBg = true end
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

    local function isAtPosition(gx, gy)
        local char = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not char then return false end
        local cx = math.floor(char.Position.X / GRID_SIZE + 0.5)
        local cy = math.floor((char.Position.Y - OFFSET_Y) / GRID_SIZE + 0.5)
        return cx == gx and cy == gy
    end

    -- ========================================
    -- [3] PATHFINDING
    -- ========================================

    local function isWalkable(gx, gy)
        if gx < WORLD_MIN_X or gx > WORLD_MAX_X or gy < WORLD_MIN_Y or gy > WORLD_MAX_Y then
            return false
        end
        if isLockArea(gx, gy) then return false end
        if worldData[gx] and worldData[gx][gy] and worldData[gx][gy][1] ~= nil then
            return false
        end
        return true
    end

    local function findSmartPath(startX, startY, targetX, targetY)
        local startKey = startX .. "," .. startY
        local queue    = {{x=startX, y=startY, cost=0, parent=nil}}
        local visited  = {[startKey] = 0}
        local dirs     = {{x=1,y=0},{x=-1,y=0},{x=0,y=1},{x=0,y=-1}}
        local found    = nil
        local limit    = 0

        while #queue > 0 do
            if _G.LatestRunToken ~= myToken then break end
            limit = limit + 1
            if limit > 4000 then break end

            local minIdx, minCost = 1, queue[1].cost
            for i = 2, #queue do
                if queue[i].cost < minCost then
                    minCost = queue[i].cost
                    minIdx  = i
                end
            end
            local cur = table.remove(queue, minIdx)

            if cur.x == targetX and cur.y == targetY then
                found = cur
                break
            end

            for _, d in ipairs(dirs) do
                local nx, ny = cur.x + d.x, cur.y + d.y
                local nkey   = nx .. "," .. ny
                if isWalkable(nx, ny) then
                    local nc = cur.cost + 1
                    if not visited[nkey] or nc < visited[nkey] then
                        visited[nkey] = nc
                        table.insert(queue, {x=nx, y=ny, cost=nc, parent=cur})
                    end
                end
            end
        end

        if not found then return nil end
        local path, node = {}, found
        while node.parent ~= nil do
            table.insert(path, 1, Vector3.new(node.x * GRID_SIZE, node.y * GRID_SIZE, 0))
            node = node.parent
        end
        return path
    end

    -- ========================================
    -- [4] MOVEMENT
    -- ========================================

    local function moveTo(gx, gy)
        local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
        if not Hitbox then return end
        local wx = gx * GRID_SIZE
        local wy = gy * GRID_SIZE + OFFSET_Y
        Hitbox.CFrame = CFrame.new(wx, wy, Hitbox.Position.Z)
        movementModule.Position = Hitbox.Position
        pcall(function() MovPacket:FireServer(wx, wy) end)
    end

    local function snapToGrid()
        local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
        if not Hitbox then return end
        local snappedX = math.floor(Hitbox.Position.X / GRID_SIZE + 0.5) * GRID_SIZE
        local snappedY = math.floor(Hitbox.Position.Y / GRID_SIZE + 0.5) * GRID_SIZE + OFFSET_Y
        Hitbox.CFrame = CFrame.new(snappedX, snappedY, Hitbox.Position.Z)
        movementModule.Position = Hitbox.Position
        pcall(function() MovPacket:FireServer(snappedX, snappedY) end)
    end

    local function walkToGrid(gx, gy, StatusLabel)
        local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
        if not Hitbox then return end

        local sx = math.floor(Hitbox.Position.X / GRID_SIZE + 0.5)
        local sy = math.floor((Hitbox.Position.Y - OFFSET_Y) / GRID_SIZE + 0.5)
        if sx == gx and sy == gy then return end

        local path = findSmartPath(sx, sy, gx, gy)
        if not path then
            moveTo(gx, gy)
            task.wait(0.2)
            return
        end

        for i, point in ipairs(path) do
            if not getgenv().AutoClear_Enabled or _G.LatestRunToken ~= myToken then break end
            if StatusLabel then
                StatusLabel:SetText(string.format("Status  : Jalan (%d/%d)...", i, #path))
            end
            local px = math.floor(point.X / GRID_SIZE + 0.5)
            local py = math.floor(point.Y / GRID_SIZE + 0.5)
            moveTo(px, py)
            task.wait(getgenv().AutoClear_StepDelay)
        end

        if not isAtPosition(gx, gy) then
            moveTo(gx, gy)
            task.wait(0.15)
        end
    end

    local function breakTile(gx, gy)
        if isLockArea(gx, gy) then return end
        local pos = Vector2.new(gx, gy)

        while _G.LatestRunToken == myToken and getgenv().AutoClear_Enabled do
            local tile   = worldData[gx] and worldData[gx][gy]
            local layer1 = tile and tile[1]
            if not layer1 then break end
            local itemName = (type(layer1) == "table") and layer1[1] or layer1
            if shouldSkip(itemName) then break end
            if isAtPosition(gx, gy + 1) then
                pcall(function() MovPacket:FireServer(gx * GRID_SIZE, (gy+1) * GRID_SIZE + OFFSET_Y) end)
                PlayerFist:FireServer(pos)
                task.wait(getgenv().AutoClear_BreakDelay)
            else
                moveTo(gx, gy + 1)
                task.wait(0.1)
            end
        end

        while _G.LatestRunToken == myToken and getgenv().AutoClear_Enabled do
            local tile   = worldData[gx] and worldData[gx][gy]
            local layer2 = tile and tile[2]
            if not layer2 then break end
            local itemName = (type(layer2) == "table") and layer2[1] or layer2
            if shouldSkip(itemName) then break end
            if isAtPosition(gx, gy + 1) then
                pcall(function() MovPacket:FireServer(gx * GRID_SIZE, (gy+1) * GRID_SIZE + OFFSET_Y) end)
                PlayerFist:FireServer(pos)
                task.wait(getgenv().AutoClear_BreakDelay)
            else
                moveTo(gx, gy + 1)
                task.wait(0.1)
            end
        end
    end

    -- ========================================
    -- [5] UI
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
    SubTab:AddLabel("2. Bot detect posisi atas world otomatis.")
    SubTab:AddLabel("3. Arah zig-zag kiri-kanan turun.")
    SubTab:AddLabel("4. Skip: bedrock, lock, door, lock area.")
    SubTab:AddLabel("5. Matikan toggle untuk stop.")

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
                    movementModule.Grounded = true
                    if movementModule.VelocityY < 0 then movementModule.VelocityY = 0 end
                    task.wait(0.1)
                    snapToGrid()

                    StatusLabel:SetText("Status  : Mendeteksi area...")
                    local startY     = findTopY()
                    local totalTiles = (WORLD_MAX_X - WORLD_MIN_X + 1) * (startY - WORLD_MIN_Y + 1)
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
                                walkToGrid(gx, gy + 1, StatusLabel)
                                StatusLabel:SetText(string.format("Status  : Breaking (%d,%d)...", gx, gy))
                                breakTile(gx, gy)
                            end

                            doneCount = doneCount + 1
                            PosLabel:SetText(string.format("Posisi  : (%d, %d)", gx, gy))
                            ProgressLabel:SetText(string.format("Progress: %d/%d (%.1f%%)",
                                doneCount, totalTiles, (doneCount/totalTiles)*100))
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
