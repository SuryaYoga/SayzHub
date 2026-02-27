return function(SubTab, Window, myToken)
    -- ========================================
    -- [1] VARIABEL & SETUP (SINKRON TOKEN)
    -- ========================================
    local PnB = getgenv().SayzSettings.PnB 
    local WorldTiles = require(game.ReplicatedStorage.WorldTiles)
    local movementModule = require(game.Players.LocalPlayer.PlayerScripts.PlayerMovement)
    local LP = game.Players.LocalPlayer
    local IM = require(game:GetService("ReplicatedStorage").Managers.ItemsManager)
    
    local LIMIT = { MIN_X = 0, MAX_X = 100, MIN_Y = 6, MAX_Y = 60 }
    local lockedDoors, badItems = {}, {}
    _G.LastPnBState = "Waiting" 

    -- ========================================
    -- [2] PATHFINDING CORE (DIAMBIL DARI CONTOH)
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
    -- [3] UI ELEMENTS (DIPASTIKAN LENGKAP)
    -- ========================================
    SubTab:AddSection("EKSEKUSI")
    getgenv().SayzUI_Handles["PnB_Master"] = SubTab:AddToggle("Master Switch", PnB.Master, function(t) PnB.Master = t end)
    getgenv().SayzUI_Handles["PnB_Place"] = SubTab:AddToggle("Enable Place", PnB.Place, function(t) PnB.Place = t end)
    getgenv().SayzUI_Handles["PnB_Break"] = SubTab:AddToggle("Enable Break", PnB.Break, function(t) PnB.Break = t end)
    getgenv().SayzUI_Handles["PnB_SmartCollect"] = SubTab:AddToggle("Walk to Collect (Grid)", PnB.AutoCollectInGrid, function(t) PnB.AutoCollectInGrid = t end)

    SubTab:AddSection("SCANNER")
    SubTab:AddButton("Scan ID Item", function() PnB.Scanning = true; Window:Notify("Pasang 1 blok manual!", 3) end)
    local InfoLabel = SubTab:AddLabel("ID Aktif: " .. (PnB.TargetID or "None"))
    local StokLabel = SubTab:AddLabel("Total Stok: 0")

    SubTab:AddSection("SETTING")
    getgenv().SayzUI_Handles["PnB_SpeedScale"] = SubTab:AddInput("Speed PnB Scale", "1", function(v)
        local val = tonumber(v) or 1
        PnB.DelayScale = (val < 0.1) and 0.1 or val
        PnB.ActualDelay = PnB.DelayScale * 0.12
    end)
    
    getgenv().SayzUI_Handles["PnB_StepDelay"] = SubTab:AddInput("Walk Speed (StepDelay)", tostring(getgenv().StepDelay or 0.05), function(v)
        local val = tonumber(v)
        if val then getgenv().StepDelay = val end
    end)

    getgenv().SayzUI_Handles["PnB_LockPosition"] = SubTab:AddToggle("Lock Position", PnB.LockPosition, function(t) PnB.LockPosition = t end)
    getgenv().SayzUI_Handles["PnB_BreakMode"] = SubTab:AddDropdown("Multi-Break Mode", {"Mode 1 (Fokus)", "Mode 2 (Rata)"}, PnB.BreakMode or "Mode 1 (Fokus)", function(v) PnB.BreakMode = v end)

    SubTab:AddSection("GRID TARGET (5x5)")
    SubTab:AddGridSelector(function(selectedTable)
        PnB.SelectedTiles = selectedTable
        local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
        if Hitbox then
            PnB.OriginGrid = { x = math.floor(Hitbox.Position.X/4.5+0.5), y = math.floor(Hitbox.Position.Y/4.5+0.5) }
        end
    end)

    -- ========================================
    -- [4] HELPERS & SCANNER HOOK
    -- ========================================
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

    local function GetDropsInGrid(areaData)
        local drops = {}
        for _, tile in ipairs(areaData) do
            for _, folder in pairs({"Drops", "Gems"}) do
                local container = workspace:FindFirstChild(folder)
                if container then
                    for _, item in pairs(container:GetChildren()) do
                        local pos = item:GetPivot().Position
                        if not badItems[item] and math.floor(pos.X/4.5+0.5) == tile.pos.X and math.floor(pos.Y/4.5+0.5) == tile.pos.Y then
                            table.insert(drops, item)
                        end
                    end
                end
            end
        end
        return drops
    end

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
    -- [5] MAIN LOOP (URUTAN KAKU)
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
                    for coordKey, active in pairs(PnB.SelectedTiles or {}) do
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

                    -- PHASE A: BREAK (Hanya Pukul)
                    if PnB.Break and currentFilled > 0 then
                        _G.LastPnBState = "Breaking"
                        for _, tile in ipairs(targets) do
                            if _G.LatestRunToken ~= myToken or not PnB.Master then break end
                            if tile.isFilled then
                                while PnB.Master and PnB.Break do
                                    if _G.LatestRunToken ~= myToken then break end
                                    local check = WorldTiles[tile.pos.X] and WorldTiles[tile.pos.X][tile.pos.Y] and WorldTiles[tile.pos.X][tile.pos.Y][1]
                                    if not check then break end 
                                    game.ReplicatedStorage.Remotes.PlayerFist:FireServer(tile.pos)
                                    task.wait(0.035)
                                end
                            end
                        end
                    end

                    -- PHASE B: FULL COLLECT (WALK - IDENTIK CONTOH)
                    local drops = GetDropsInGrid(targets)
                    if PnB.AutoCollectInGrid and PnB.Master and currentFilled == 0 and #drops > 0 then
                        _G.LastPnBState = "Collecting"
                        while #drops > 0 and PnB.Master and PnB.AutoCollectInGrid do
                            if _G.LatestRunToken ~= myToken then break end
                            local item = drops[1]
                            if item and item.Parent then
                                local path = findSmartPath(math.floor(Hitbox.Position.X/4.5+0.5), math.floor(Hitbox.Position.Y/4.5+0.5), math.floor(item:GetPivot().Position.X/4.5+0.5), math.floor(item:GetPivot().Position.Y/4.5+0.5))
                                if path then
                                    for _, pt in ipairs(path) do
                                        if _G.LatestRunToken ~= myToken then break end
                                        Hitbox.CFrame = CFrame.new(pt.X, pt.Y, Hitbox.Position.Z)
                                        movementModule.Position = Hitbox.Position
                                        task.wait(getgenv().StepDelay or 0.05)
                                    end
                                else badItems[item] = true end
                            end
                            drops = GetDropsInGrid(targets)
                            task.wait(0.1)
                        end
                        -- Balik ke Origin (Jalan juga)
                        local backPath = findSmartPath(math.floor(Hitbox.Position.X/4.5+0.5), math.floor(Hitbox.Position.Y/4.5+0.5), baseGrid.x, baseGrid.y)
                        if backPath then
                            for _, pt in ipairs(backPath) do
                                if _G.LatestRunToken ~= myToken then break end
                                Hitbox.CFrame = CFrame.new(pt.X, pt.Y, Hitbox.Position.Z)
                                movementModule.Position = Hitbox.Position
                                task.wait(getgenv().StepDelay or 0.05)
                            end
                        end
                    end

                    -- PHASE C: PLACE
                    local finalDrops = GetDropsInGrid(targets)
                    local canPlace = (not PnB.AutoCollectInGrid) or (PnB.AutoCollectInGrid and #finalDrops == 0)
                    if PnB.Place and currentFilled < #targets and canPlace then
                        _G.LastPnBState = "Placing"
                        for _, tile in ipairs(targets) do
                            if _G.LatestRunToken ~= myToken or not PnB.Master then break end
                            if not tile.isFilled then
                                game.ReplicatedStorage.Remotes.PlayerPlaceItem:FireServer(tile.pos, PnB.TargetID, 1)
                                task.wait(PnB.PlaceDelay or 0.05)
                            end
                        end
                    end
                end)
            end
            
            pcall(function()
                InfoLabel:SetText("ID Aktif: " .. tostring(PnB.TargetID or "None"))
                StokLabel:SetText("Total Stok: " .. getActiveAmount())
            end)
            task.wait(0.1)
        end
    end)

    SubTab:AddParagraph("Update Log", "**Apa yang Diperbaiki:**\n1. Mengembalikan semua UI (Speed Scale, Scanner, Break Mode).\n2. Memperbaiki logika pergerakan SmartPath agar identik 100% dengan AutoCollect asli.\n3. Urutan kerja tetap: Pukul -> Jalan Mungut (Jika ON) -> Pasang Blok.\n4. Menambahkan pencegahan crash (BadItem Filter & Jeda 0.1s).")
end
