return function(SubTab, Window, myToken)
    -- ========================================
    -- [1] SETUP & VARIABLES (STABLE)
    -- ========================================
    local PnB = getgenv().SayzSettings.PnB 
    local WorldTiles = require(game.ReplicatedStorage.WorldTiles)
    local movementModule = require(game.Players.LocalPlayer.PlayerScripts.PlayerMovement)
    local LP = game.Players.LocalPlayer
    local IM = require(game:GetService("ReplicatedStorage").Managers.ItemsManager)
    
    local LIMIT = { MIN_X = 0, MAX_X = 100, MIN_Y = 6, MAX_Y = 60 }
    local lockedDoors, badItems = {}, {} -- badItems untuk cegah loop maut
    _G.LastPnBState = "Waiting" 

    -- ========================================
    -- [2] GRAVITY BYPASS (SAFE MODE)
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait(0.1) -- Jeda agar tidak makan CPU
            if PnB.Master and PnB.AutoCollectInGrid then
                pcall(function()
                    if movementModule.VelocityY < 0 then movementModule.VelocityY = 0 end
                    movementModule.Grounded = true 
                end)
            end
        end
    end)

    -- ========================================
    -- [3] SMARTPATH CORE (100% IDENTIK)
    -- ========================================
    local function isWalkable(gx, gy)
        if gx < LIMIT.MIN_X or gx > LIMIT.MAX_X or gy < LIMIT.MIN_Y or gy > LIMIT.MAX_Y then return false end
        if lockedDoors[gx .. "," .. gy] then return false end 
        if WorldTiles[gx] and WorldTiles[gx][gy] then
            local l1 = WorldTiles[gx][gy][1]
            local itemName = (type(l1) == "table") and l1[1] or l1
            if itemName then
                local n = string.lower(tostring(itemName))
                if string.find(n, "door") or string.find(n, "frame") then return true end
                return false 
            end
        end
        return true
    end

    local function findSmartPath(startX, startY, targetX, targetY)
        local queue = {{x = startX, y = startY, path = {}, cost = 0}}
        local visited = {[startX .. "," .. startY] = 0}
        local directions = {{x = 1, y = 0}, {x = -1, y = 0}, {x = 0, y = 1}, {x = 0, y = -1}}
        local limitCount = 0
        while #queue > 0 do
            if _G.LatestRunToken ~= myToken then break end
            limitCount = limitCount + 1
            if limitCount > 2000 then break end -- Dipersempit agar tidak crash
            table.sort(queue, function(a, b) return a.cost < b.cost end)
            local current = table.remove(queue, 1)
            if current.x == targetX and current.y == targetY then return current.path end
            for _, d in ipairs(directions) do
                local nx, ny = current.x + d.x, current.y + d.y
                if isWalkable(nx, ny) then
                    local newTotalCost = current.cost + 1
                    if not visited[nx .. "," .. ny] or newTotalCost < visited[nx .. "," .. ny] then
                        visited[nx .. "," .. ny] = newTotalCost
                        local newPath = {unpack(current.path)}
                        table.insert(newPath, Vector3.new(nx * 4.5, ny * 4.5, 0))
                        table.insert(queue, {x = nx, y = ny, path = newPath, cost = newTotalCost})
                    end
                end
            end
        end
        return nil
    end

    -- ========================================
    -- [4] UI & HELPERS
    -- ========================================
    SubTab:AddSection("EKSEKUSI UTAMA")
    getgenv().SayzUI_Handles["PnB_Master"] = SubTab:AddToggle("Master Switch", PnB.Master, function(t) PnB.Master = t end)
    getgenv().SayzUI_Handles["PnB_SmartCollect"] = SubTab:AddToggle("Walk to Collect (Grid)", PnB.AutoCollectInGrid, function(t) PnB.AutoCollectInGrid = t end)
    
    local InfoLabel = SubTab:AddLabel("ID Aktif: None")
    
    local function GetDropsInGrid(areaData)
        local drops = {}
        for _, tile in ipairs(areaData) do
            for _, folder in pairs({"Drops", "Gems"}) do
                local container = workspace:FindFirstChild(folder)
                if container then
                    for _, item in pairs(container:GetChildren()) do
                        if not badItems[item] then -- Filter item yang bikin macet
                            local pos = item:GetPivot().Position
                            if math.floor(pos.X/4.5+0.5) == tile.pos.X and math.floor(pos.Y/4.5+0.5) == tile.pos.Y then
                                table.insert(drops, item)
                            end
                        end
                    end
                end
            end
        end
        return drops
    end

    -- ========================================
    -- [5] MAIN LOOP (ANTI-CRASH)
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            if PnB.Master then
                pcall(function()
                    local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
                    if not Hitbox then return end

                    local baseGrid = PnB.OriginGrid or { x = math.floor(Hitbox.Position.X/4.5+0.5), y = math.floor(Hitbox.Position.Y/4.5+0.5) }

                    -- Scan Area
                    local targets, currentFilled, selectedList = {}, 0, {}
                    for coordKey, active in pairs(PnB.SelectedTiles or {}) do
                        if active then
                            local parts = string.split(coordKey, ",")
                            table.insert(selectedList, {ox = tonumber(parts[1]), oy = tonumber(parts[2])})
                        end
                    end
                    for _, offset in ipairs(selectedList) do
                        local tx, ty = baseGrid.x + offset.ox, baseGrid.y + offset.oy
                        local tileData = WorldTiles[tx] and WorldTiles[tx][ty]
                        local blockExist = tileData and tileData[1] ~= nil
                        table.insert(targets, {pos = Vector2.new(tx, ty), isFilled = blockExist})
                        if blockExist then currentFilled = currentFilled + 1 end
                    end

                    -- PHASE A: BREAK
                    if PnB.Break and currentFilled > 0 then
                        _G.LastPnBState = "Breaking"
                        for _, tile in ipairs(targets) do
                            if _G.LatestRunToken ~= myToken or not PnB.Master then break end
                            if tile.isFilled then
                                while PnB.Master and PnB.Break do
                                    task.wait(0.035)
                                    local check = WorldTiles[tile.pos.X] and WorldTiles[tile.pos.X][tile.pos.Y] and WorldTiles[tile.pos.X][tile.pos.Y][1]
                                    if not check or _G.LatestRunToken ~= myToken then break end
                                    game.ReplicatedStorage.Remotes.PlayerFist:FireServer(tile.pos)
                                end
                            end
                        end
                    end

                    -- PHASE B: SMART COLLECT (WITH STUCK GUARD)
                    local drops = GetDropsInGrid(targets)
                    if PnB.AutoCollectInGrid and PnB.Master and currentFilled == 0 and #drops > 0 then
                        _G.LastPnBState = "Collecting"
                        local maxAttempts = 10 -- Batas biar gak infinite loop
                        while #drops > 0 and maxAttempts > 0 do
                            maxAttempts = maxAttempts - 1
                            local item = drops[1]
                            if item and item.Parent then
                                local sx, sy = math.floor(Hitbox.Position.X/4.5+0.5), math.floor(Hitbox.Position.Y/4.5+0.5)
                                local tx, ty = math.floor(item:GetPivot().Position.X/4.5+0.5), math.floor(item:GetPivot().Position.Y/4.5+0.5)
                                local path = findSmartPath(sx, sy, tx, ty)
                                if path then
                                    for _, pt in ipairs(path) do
                                        Hitbox.CFrame = CFrame.new(pt.X, pt.Y, Hitbox.Position.Z)
                                        movementModule.Position = Hitbox.Position
                                        task.wait(getgenv().StepDelay or 0.05)
                                    end
                                else
                                    badItems[item] = true -- Tandai barang bermasalah
                                end
                            end
                            drops = GetDropsInGrid(targets)
                            task.wait(0.1)
                        end
                        -- Balik ke Origin
                        local backPath = findSmartPath(math.floor(Hitbox.Position.X/4.5+0.5), math.floor(Hitbox.Position.Y/4.5+0.5), baseGrid.x, baseGrid.y)
                        if backPath then
                            for _, pt in ipairs(backPath) do
                                Hitbox.CFrame = CFrame.new(pt.X, pt.Y, Hitbox.Position.Z)
                                movementModule.Position = Hitbox.Position
                                task.wait(getgenv().StepDelay or 0.05)
                            end
                        end
                    end

                    -- PHASE C: PLACE
                    if PnB.Place and currentFilled < #targets then
                        _G.LastPnBState = "Placing"
                        for _, tile in ipairs(targets) do
                            if _G.LatestRunToken ~= myToken or not PnB.Master then break end
                            if not tile.isFilled then
                                game.ReplicatedStorage.Remotes.PlayerPlaceItem:FireServer(tile.pos, PnB.TargetID, 1)
                                task.wait(0.05)
                            end
                        end
                    end
                end)
            end
            task.wait(0.2) -- Jeda loop utama (Biar GA CRASH)
        end
    end)
    
    SubTab:AddParagraph("Update Status", "FIXED CRASH: Menambahkan stuck-guard pada loop collecting dan memperlambat jeda loop utama untuk kestabilan memori.")
end
