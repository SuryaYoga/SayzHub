return function(SubTab, Window, myToken)
    -- ========================================
    -- [1] SETUP & SETTINGS
    -- ========================================
    local PnB = getgenv().SayzSettings.PnB 
    local WorldTiles = require(game.ReplicatedStorage.WorldTiles)
    local movementModule = require(game.Players.LocalPlayer.PlayerScripts.PlayerMovement)
    local LP = game.Players.LocalPlayer
    local IM = require(game:GetService("ReplicatedStorage").Managers.ItemsManager)
    
    local LIMIT = { MIN_X = 0, MAX_X = 100, MIN_Y = 6, MAX_Y = 60 }
    local lockedDoors = {}
    _G.LastPnBState = "Waiting" 

    -- ========================================
    -- [2] SMARTPATH (IDENTIK AUTOCOLLECT)
    -- ========================================
    local function isWalkable(gx, gy)
        if gx < LIMIT.MIN_X or gx > LIMIT.MAX_X or gy < LIMIT.MIN_Y or gy > LIMIT.MAX_Y then return false end
        if lockedDoors[gx .. "," .. gy] then return false end 
        if WorldTiles[gx] and WorldTiles[gx][gy] then
            local l1 = WorldTiles[gx][gy][1]
            local itemName = (type(l1) == "table") and l1[1] or l1
            if itemName and (string.find(string.lower(tostring(itemName)), "door") or string.find(string.lower(tostring(itemName)), "frame")) then 
                return true 
            end
            if itemName then return false end
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
            if limitCount > 3000 then break end 
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
    -- [3] UI ELEMENTS (FITUR LENGKAP)
    -- ========================================
    SubTab:AddSection("KONTROL UTAMA")
    getgenv().SayzUI_Handles["PnB_Master"] = SubTab:AddToggle("Master Switch", PnB.Master, function(t) PnB.Master = t end)
    getgenv().SayzUI_Handles["PnB_Place"] = SubTab:AddToggle("Enable Place", PnB.Place, function(t) PnB.Place = t end)
    getgenv().SayzUI_Handles["PnB_Break"] = SubTab:AddToggle("Enable Break", PnB.Break, function(t) PnB.Break = t end)
    getgenv().SayzUI_Handles["PnB_SmartCollect"] = SubTab:AddToggle("Smart Collect (Lock Grid)", PnB.AutoCollectInGrid, function(t) PnB.AutoCollectInGrid = t end)

    SubTab:AddSection("PENGATURAN & SCANNER")
    SubTab:AddButton("Scan ID Item", function() PnB.Scanning = true; Window:Notify("Pasang 1 blok manual!", 2) end)
    local InfoLabel = SubTab:AddLabel("ID: " .. (PnB.TargetID or "None"))
    local StokLabel = SubTab:AddLabel("Stok: 0")

    getgenv().SayzUI_Handles["PnB_SpeedScale"] = SubTab:AddInput("PnB Speed Scale", "1", function(v) PnB.DelayScale = tonumber(v) or 1 end)
    getgenv().SayzUI_Handles["PnB_StepDelay"] = SubTab:AddInput("Walk Step Delay", tostring(getgenv().StepDelay or 0.05), function(v) getgenv().StepDelay = tonumber(v) or 0.05 end)
    getgenv().SayzUI_Handles["PnB_LockPosition"] = SubTab:AddToggle("Lock Base Position", PnB.LockPosition, function(t) PnB.LockPosition = t end)

    SubTab:AddSection("GRID SELECTOR")
    SubTab:AddGridSelector(function(selectedTable)
        PnB.SelectedTiles = selectedTable
        local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
        if Hitbox then PnB.OriginGrid = { x = math.floor(Hitbox.Position.X/4.5+0.5), y = math.floor(Hitbox.Position.Y/4.5+0.5) } end
    end)

    -- ========================================
    -- [4] SCRIPT LOGIC
    -- ========================================
    local function GetDropsOnlyInGrid(areaData)
        local drops = {}
        for _, tile in ipairs(areaData) do
            for _, folder in pairs({"Drops", "Gems"}) do
                local container = workspace:FindFirstChild(folder)
                if container then
                    for _, item in pairs(container:GetChildren()) do
                        local pos = item:GetPivot().Position
                        if math.floor(pos.X/4.5+0.5) == tile.pos.X and math.floor(pos.Y/4.5+0.5) == tile.pos.Y then
                            table.insert(drops, item)
                        end
                    end
                end
            end
        end
        return drops
    end

    task.spawn(function()
        while _G.LatestRunToken == myToken do
            if PnB.Master then
                pcall(function()
                    local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
                    if not Hitbox then return end
                    local basePos = PnB.OriginGrid or { x = math.floor(Hitbox.Position.X/4.5+0.5), y = math.floor(Hitbox.Position.Y/4.5+0.5) }

                    -- Mapping Grid
                    local targets, currentFilled = {}, 0
                    for coordKey, active in pairs(PnB.SelectedTiles or {}) do
                        if active then
                            local p = string.split(coordKey, ",")
                            local tx, ty = basePos.x + tonumber(p[1]), basePos.y + tonumber(p[2])
                            local block = WorldTiles[tx] and WorldTiles[tx][ty] and WorldTiles[tx][ty][1] ~= nil
                            table.insert(targets, {pos = Vector2.new(tx, ty), isFilled = block})
                            if block then currentFilled = currentFilled + 1 end
                        end
                    end

                    -- 1. BREAK PHASE
                    if PnB.Break and currentFilled > 0 then
                        _G.LastPnBState = "Breaking"
                        for _, tile in ipairs(targets) do
                            if tile.isFilled then
                                while PnB.Master and PnB.Break and WorldTiles[tile.pos.X][tile.pos.Y][1] ~= nil do
                                    game.ReplicatedStorage.Remotes.PlayerFist:FireServer(tile.pos)
                                    task.wait(0.035)
                                end
                            end
                        end
                    end

                    -- 2. COLLECT PHASE (LOCK IN GRID)
                    local drops = GetDropsOnlyInGrid(targets)
                    if PnB.AutoCollectInGrid and #drops > 0 then
                        _G.LastPnBState = "Collecting"
                        while #drops > 0 and PnB.Master do
                            local item = drops[1]
                            if item and item.Parent then
                                local targetX, targetY = math.floor(item:GetPivot().Position.X/4.5+0.5), math.floor(item:GetPivot().Position.Y/4.5+0.5)
                                local path = findSmartPath(math.floor(Hitbox.Position.X/4.5+0.5), math.floor(Hitbox.Position.Y/4.5+0.5), targetX, targetY)
                                if path then
                                    for _, pt in ipairs(path) do
                                        Hitbox.CFrame = CFrame.new(pt.X, pt.Y, Hitbox.Position.Z)
                                        movementModule.Position = Hitbox.Position
                                        task.wait(getgenv().StepDelay or 0.05)
                                    end
                                    task.wait(0.2) -- DIEM SEJENAK UNTUK SCAN ULANG
                                end
                            end
                            drops = GetDropsOnlyInGrid(targets) -- Scan ulang grid
                        end
                        
                        -- SETELAH HABIS, TUNGGU BENTAR BARU BALIK PELAN
                        task.wait(0.3)
                        local backPath = findSmartPath(math.floor(Hitbox.Position.X/4.5+0.5), math.floor(Hitbox.Position.Y/4.5+0.5), basePos.x, basePos.y)
                        if backPath then
                            for _, pt in ipairs(backPath) do
                                Hitbox.CFrame = CFrame.new(pt.X, pt.Y, Hitbox.Position.Z)
                                movementModule.Position = Hitbox.Position
                                task.wait(getgenv().StepDelay or 0.05)
                            end
                        end
                    end

                    -- 3. PLACE PHASE
                    if PnB.Place and currentFilled < #targets then
                        local checkDrops = GetDropsOnlyInGrid(targets)
                        if not PnB.AutoCollectInGrid or #checkDrops == 0 then
                            _G.LastPnBState = "Placing"
                            for _, tile in ipairs(targets) do
                                if not tile.isFilled then
                                    game.ReplicatedStorage.Remotes.PlayerPlaceItem:FireServer(tile.pos, PnB.TargetID, 1)
                                    task.wait(0.05)
                                end
                            end
                        end
                    end
                end)
            end
            task.wait(0.1)
        end
    end)
    
    -- Visual Update
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            pcall(function()
                InfoLabel:SetText("ID: " .. (PnB.TargetID or "None"))
                local total = 0
                local inv = require(game.ReplicatedStorage.Modules.Inventory)
                if inv and inv.Stacks and PnB.TargetID then
                    for _, s in pairs(inv.Stacks) do if s.Id == inv.Stacks[tonumber(PnB.TargetID)].Id then total = total + s.Amount end end
                end
                StokLabel:SetText("Stok: " .. total)
            end)
            task.wait(0.5)
        end
    end)
end
