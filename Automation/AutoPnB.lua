return function(SubTab, Window, myToken)
    -- ========================================
    -- [1] SETUP & VARIABLES
    -- ========================================
    local PnB = getgenv().SayzSettings.PnB 
    local WorldTiles = require(game.ReplicatedStorage.WorldTiles)
    local movementModule = require(game.Players.LocalPlayer.PlayerScripts.PlayerMovement)
    local LP = game.Players.LocalPlayer
    local IM = require(game:GetService("ReplicatedStorage").Managers.ItemsManager)
    
    local LIMIT = { MIN_X = 0, MAX_X = 100, MIN_Y = 6, MAX_Y = 60 }
    local lockedDoors = {}
    _G.LastPnBState = "Waiting" 
    PnB.CollectDelay = PnB.CollectDelay or 0.05

    -- ========================================
    -- [2] PATHFINDING CORE (100% SESUAI AUTOCOLLECT ABANG)
    -- ========================================
    local function isWalkable(gx, gy)
        if gx < LIMIT.MIN_X or gx > LIMIT.MAX_X or gy < LIMIT.MIN_Y or gy > LIMIT.MAX_Y then return false, false end
        if lockedDoors[gx .. "," .. gy] then return false, false end 
        if WorldTiles[gx] and WorldTiles[gx][gy] then
            local l1 = WorldTiles[gx][gy][1]
            local itemName = (type(l1) == "table") and l1[1] or l1
            if itemName then
                local n = string.lower(tostring(itemName))
                if string.find(n, "door") or string.find(n, "frame") then return true, false end
                return false, false 
            end
        end
        return true, false
    end

    local function findSmartPath(startX, startY, targetX, targetY)
        local queue = {{x = startX, y = startY, path = {}, cost = 0}}
        local visited = {[startX .. "," .. startY] = 0}
        local directions = {{x = 1, y = 0}, {x = -1, y = 0}, {x = 0, y = 1}, {x = 0, y = -1}}
        local limitCount = 0
        while #queue > 0 do
            if _G.LatestRunToken ~= myToken then break end
            limitCount = limitCount + 1
            if limitCount > 4000 then break end 
            table.sort(queue, function(a, b) return a.cost < b.cost end)
            local current = table.remove(queue, 1)
            if current.x == targetX and current.y == targetY then return current.path end
            for _, d in ipairs(directions) do
                local nx, ny = current.x + d.x, current.y + d.y
                local walkable = isWalkable(nx, ny)
                if walkable then
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
    -- [3] UI ELEMENTS
    -- ========================================
    SubTab:AddSection("EKSEKUSI UTAMA")
    getgenv().SayzUI_Handles["PnB_Master"] = SubTab:AddToggle("Master Switch", PnB.Master, function(t) PnB.Master = t end)
    getgenv().SayzUI_Handles["PnB_Place"] = SubTab:AddToggle("Enable Place", PnB.Place, function(t) PnB.Place = t end)
    getgenv().SayzUI_Handles["PnB_Break"] = SubTab:AddToggle("Enable Break", PnB.Break, function(t) PnB.Break = t end)
    getgenv().SayzUI_Handles["PnB_SmartCollect"] = SubTab:AddToggle("Smart Collect (Grid Only)", PnB.AutoCollectInGrid, function(t) PnB.AutoCollectInGrid = t end)

    SubTab:AddSection("SCANNER")
    SubTab:AddButton("Scan ID Item", function() PnB.Scanning = true; Window:Notify("Pasang 1 blok manual!", 3) end)
    local InfoLabel = SubTab:AddLabel("ID Aktif: None")
    local StokLabel = SubTab:AddLabel("Total Stok: 0")

    SubTab:AddSection("SETTING")
    getgenv().SayzUI_Handles["PnB_SpeedScale"] = SubTab:AddInput("Speed PnB Scale", "1", function(v)
        local val = tonumber(v) or 1
        PnB.DelayScale = (val < 0.1) and 0.1 or val
        PnB.ActualDelay = PnB.DelayScale * 0.12
    end)
    
    getgenv().SayzUI_Handles["PnB_CollectDelay"] = SubTab:AddInput("Collect Walk Delay", tostring(PnB.CollectDelay), function(v)
        local val = tonumber(v)
        if val then PnB.CollectDelay = val end
    end)

    getgenv().SayzUI_Handles["PnB_LockPosition"] = SubTab:AddToggle("Lock Position", PnB.LockPosition, function(t) PnB.LockPosition = t end)
    getgenv().SayzUI_Handles["PnB_BreakMode"] = SubTab:AddDropdown("Multi-Break Mode", {"Mode 1 (Fokus)", "Mode 2 (Rata)"}, PnB.BreakMode, function(v) PnB.BreakMode = v end)

    SubTab:AddSection("GRID TARGET")
    SubTab:AddGridSelector(function(selectedTable)
        PnB.SelectedTiles = selectedTable
        local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if root then
            PnB.OriginGrid = { x = math.floor(root.Position.X/4.5+0.5), y = math.floor(root.Position.Y/4.5+0.5) }
        end
    end)

    -- ========================================
    -- [4] HELPER FUNCTIONS
    -- ========================================
    local function GetDropsInGrid(areaData)
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

    local function getActiveAmount()
        local total = 0
        local success, invModule = pcall(function() return require(game.ReplicatedStorage.Modules.Inventory) end)
        if success and invModule and invModule.Stacks then
            local targetIndex = tonumber(PnB.TargetID)
            if targetIndex and invModule.Stacks[targetIndex] then
                local targetItemId = invModule.Stacks[targetIndex].Id
                for _, stack in pairs(invModule.Stacks) do
                    if stack and stack.Id == targetItemId then total = total + (stack.Amount or 0) end
                end
            end
        end
        return total
    end

    -- Hook Scanner
    if not _G.OldHookSet then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            local args = {...}
            if PnB.Scanning and self.Name == "PlayerPlaceItem" and method == "FireServer" then
                PnB.TargetID = args[2]; PnB.Scanning = false; Window:Notify("ID Scanned: "..tostring(args[2]), 2)
            end
            return oldNamecall(self, ...)
        end)
        _G.OldHookSet = true
    end

    -- ========================================
    -- [5] MAIN TASK LOOP (URUTAN ASLI)
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            if PnB.Master then
                pcall(function()
                    local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
                    if not Hitbox then return end

                    local baseGrid = (PnB.LockPosition and PnB.OriginGrid) or { x = math.floor(Hitbox.Position.X/4.5+0.5), y = math.floor(Hitbox.Position.Y/4.5+0.5) }

                    -- Refresh Grid
                    local targets, currentFilled, selectedList = {}, 0, {}
                    for coordKey, active in pairs(PnB.SelectedTiles) do
                        if active then
                            local parts = string.split(coordKey, ",")
                            table.insert(selectedList, {ox = tonumber(parts[1]), oy = tonumber(parts[2])})
                        end
                    end
                    table.sort(selectedList, function(a, b) if a.oy ~= b.oy then return a.oy > b.oy end return a.ox < b.ox end)
                    for _, offset in ipairs(selectedList) do
                        local tx, ty = baseGrid.x + offset.ox, baseGrid.y + offset.oy
                        local tileData = WorldTiles[tx] and WorldTiles[tx][ty]
                        local blockExist = tileData and tileData[1] ~= nil
                        table.insert(targets, {pos = Vector2.new(tx, ty), isFilled = blockExist})
                        if blockExist then currentFilled = currentFilled + 1 end
                    end

                    -- PHASE 1: BREAK
                    if PnB.Break and currentFilled > 0 then
                        _G.LastPnBState = "Breaking"
                        for _, tile in ipairs(targets) do
                            if _G.LatestRunToken ~= myToken or not PnB.Master then break end
                            if tile.isFilled then
                                while PnB.Master and PnB.Break do
                                    if _G.LatestRunToken ~= myToken then break end
                                    local check = WorldTiles[tile.pos.X] and WorldTiles[tile.pos.X][tile.pos.Y] and WorldTiles[tile.pos.X][tile.pos.Y][1]
                                    if check == nil then break end 
                                    game.ReplicatedStorage.Remotes.PlayerFist:FireServer(tile.pos); task.wait(0.035)
                                end
                            end
                        end
                    end

                    -- PHASE 2: COLLECT (IDENTIK AUTOCOLLECT ABANG)
                    local drops = GetDropsInGrid(targets)
                    if PnB.AutoCollectInGrid and PnB.Master and #drops > 0 then
                        _G.LastPnBState = "Collecting"
                        for _, item in ipairs(drops) do
                            if _G.LatestRunToken ~= myToken or not PnB.Master then break end
                            if item.Parent then
                                local sx, sy = math.floor(Hitbox.Position.X/4.5+0.5), math.floor(Hitbox.Position.Y/4.5+0.5)
                                local tx, ty = math.floor(item:GetPivot().Position.X/4.5+0.5), math.floor(item:GetPivot().Position.Y/4.5+0.5)
                                local path = findSmartPath(sx, sy, tx, ty)
                                if path then
                                    for _, pt in ipairs(path) do
                                        if _G.LatestRunToken ~= myToken then break end
                                        Hitbox.CFrame = CFrame.new(pt.X, pt.Y, Hitbox.Position.Z)
                                        movementModule.Position = Hitbox.Position
                                        task.wait(PnB.CollectDelay)
                                    end
                                end
                            end
                        end
                        -- Balik ke Origin
                        local curX, curY = math.floor(Hitbox.Position.X/4.5+0.5), math.floor(Hitbox.Position.Y/4.5+0.5)
                        local backPath = findSmartPath(curX, curY, baseGrid.x, baseGrid.y)
                        if backPath then
                            for _, pt in ipairs(backPath) do
                                Hitbox.CFrame = CFrame.new(pt.X, pt.Y, Hitbox.Position.Z)
                                movementModule.Position = Hitbox.Position
                                task.wait(PnB.CollectDelay)
                            end
                        end
                    end

                    -- PHASE 3: PLACE
                    local dropsRemaining = #GetDropsInGrid(targets)
                    local canPlace = (not PnB.AutoCollectInGrid) or (PnB.AutoCollectInGrid and dropsRemaining == 0)
                    if PnB.Place and currentFilled < #targets and canPlace then
                        _G.LastPnBState = "Placing"
                        for _, tile in ipairs(targets) do
                            if _G.LatestRunToken ~= myToken or not PnB.Master then break end
                            if not tile.isFilled then
                                game.ReplicatedStorage.Remotes.PlayerPlaceItem:FireServer(tile.pos, PnB.TargetID, 1); task.wait(0.05)
                            end
                        end
                    end
                end)
            end
            pcall(function()
                InfoLabel:SetText("ID Aktif: " .. tostring(PnB.TargetID or "None"))
                StokLabel:SetText("Total Stok: " .. getActiveAmount())
            end)
            task.wait(0.01)
        end
    end)

    SubTab:AddSection("CHANGELOG / DEBUG")
    SubTab:AddParagraph("Update Status", "1. Fix SmartPath Collect (Identik 1:1 dengan AutoCollect abang).\n2. Fix Logika Antrean: Break -> Collect -> Place.\n3. Tambah Input 'Collect Walk Delay'.\n4. Fix Muter-muter (Sinkronisasi koordinat 4.5).")
end
