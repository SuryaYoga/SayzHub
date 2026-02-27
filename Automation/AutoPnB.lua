return function(SubTab, Window, myToken)
    -- ========================================
    -- [1] SETUP & VARIABLES
    -- ========================================
    local PnB = getgenv().SayzSettings.PnB
    local worldData = require(game.ReplicatedStorage.WorldTiles)
    local LP = game.Players.LocalPlayer
    local movementModule = require(LP.PlayerScripts.PlayerMovement)
    local IM = require(game:GetService("ReplicatedStorage").Managers.ItemsManager)

    _G.LastPnBState = "Waiting"

    -- [FIX-3] SmartCollect pakai namespace dari SayzSettings.PnB.SmartCollect
    -- TIDAK lagi pakai getgenv().StepDelay / getgenv().AvoidanceStrength global
    -- agar tidak bentrok dengan AutoCollect tab yang punya settings sendiri
    local SC = PnB.SmartCollect

    local LIMIT = { MIN_X = 0, MAX_X = 100, MIN_Y = 6, MAX_Y = 60 }
    local lockedDoors = {}
    local badItems = {}

    -- ========================================
    -- [2] UI ELEMENTS
    -- ========================================
    SubTab:AddSection("EKSEKUSI")
    getgenv().SayzUI_Handles["PnB_Master"] = SubTab:AddToggle("Master Switch", PnB.Master, function(t) PnB.Master = t end)
    getgenv().SayzUI_Handles["PnB_Place"] = SubTab:AddToggle("Enable Place", PnB.Place, function(t) PnB.Place = t end)
    getgenv().SayzUI_Handles["PnB_Break"] = SubTab:AddToggle("Enable Break", PnB.Break, function(t) PnB.Break = t end)

    SubTab:AddSection("SMART COLLECT (Integrasi PnB)")
    getgenv().SayzUI_Handles["SmartCollect_PnB"] = SubTab:AddToggle("Enable Smart Collect (Setelah Break)", SC.Enabled, function(t)
        SC.Enabled = t
        if t then
            -- Init door database saat diaktifkan
            for gx, columns in pairs(worldData) do
                for gy, tileData in pairs(columns) do
                    local l1 = tileData[1]
                    local itemName = (type(l1) == "table") and l1[1] or l1
                    if itemName and string.find(string.lower(tostring(itemName)), "door") then
                        -- door database di-handle di isWalkable via lockedDoors
                    end
                end
            end
        end
    end)

    getgenv().SayzUI_Handles["TakeGems_PnB"] = SubTab:AddToggle("Collect Gems (Smart Collect)", SC.TakeGems, function(t)
        SC.TakeGems = t
    end)

    -- [FIX-3] Slider ini sekarang update SC.StepDelay, BUKAN getgenv().StepDelay global
    getgenv().SayzUI_Handles["StepDelaySlider_PnB"] = SubTab:AddSlider("Movement Speed (Smart Collect)", 0.01, 0.2, SC.StepDelay, function(val)
        SC.StepDelay = val
    end, 2)

    local CollectStatusLabel = SubTab:AddLabel("Collect Status: Idle")

    SubTab:AddSection("SCANNER")
    SubTab:AddButton("Scan ID Item", function()
        PnB.Scanning = true
        Window:Notify("Pasang 1 blok manual untuk scan!", 3, "info")
    end)
    local InfoLabel = SubTab:AddLabel("ID Aktif: None")
    local StokLabel = SubTab:AddLabel("Total Stok: 0")

    SubTab:AddSection("SETTING")
    getgenv().SayzUI_Handles["PnB_SpeedScale"] = SubTab:AddInput("Speed Scale (Min 0.1)", "1", function(v)
        local val = tonumber(v) or 1
        if val < 0.1 then val = 0.1 end
        PnB.DelayScale = val
        PnB.ActualDelay = val * 0.12
    end)

    SubTab:AddSection("GRID TARGET (5x5)")
    SubTab:AddGridSelector(function(selectedTable)
        PnB.SelectedTiles = selectedTable
        local char = LP.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            PnB.OriginGrid = {
                x = math.floor((root.Position.X / 4.475) + 0.5),
                y = math.floor(((root.Position.Y - 2.5) / 4.435) + 0.5)
            }
        end
    end)

    getgenv().SayzUI_Handles["PnB_LockPosition"] = SubTab:AddToggle("Lock Position", PnB.LockPosition, function(t)
        PnB.LockPosition = t
    end)

    SubTab:AddButton("Refresh Position / Set Origin", function()
        local char = LP.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            PnB.OriginGrid = {
                x = math.floor((root.Position.X / 4.475) + 0.5),
                y = math.floor(((root.Position.Y - 2.5) / 4.435) + 0.5)
            }
            Window:Notify("Position Refreshed!", 2, "ok")
        end
    end)

    getgenv().SayzUI_Handles["PnB_BreakMode"] = SubTab:AddDropdown("Multi-Break Mode", {"Mode 1 (Fokus)", "Mode 2 (Rata)"}, PnB.BreakMode, function(v)
        PnB.BreakMode = v
    end)

    -- ========================================
    -- [3] HELPER FUNCTIONS
    -- ========================================
    local function getActiveAmount()
        local total = 0
        local success, invModule = pcall(function()
            return require(game.ReplicatedStorage.Modules.Inventory)
        end)
        if success and invModule and invModule.Stacks then
            local targetIndex = tonumber(PnB.TargetID)
            local baseStack = invModule.Stacks[targetIndex]
            if baseStack and baseStack.Id then
                local targetItemId = baseStack.Id
                for _, stack in pairs(invModule.Stacks) do
                    if stack and stack.Id == targetItemId then
                        total = total + (stack.Amount or 0)
                    end
                end
            end
        end
        return total
    end

    local function updatePnBVisuals()
        if _G.LatestRunToken ~= myToken then return end
        pcall(function()
            InfoLabel:SetText("ID Aktif: " .. tostring(PnB.TargetID or "None"))
            StokLabel:SetText("Total Stok: " .. getActiveAmount())
        end)
    end

    -- [FIX-2] Hook scanner sekarang selalu terpasang per token baru
    -- _G.OldHookSet sudah di-reset di Main.lua setiap re-execute
    if not _G.OldHookSet then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            local args = {...}
            if _G.LatestRunToken == myToken and PnB.Scanning
                and self.Name == "PlayerPlaceItem" and method == "FireServer" then
                PnB.TargetID = args[2]
                PnB.Scanning = false
                Window:Notify("ID Scanned: " .. tostring(args[2]), 2, "ok")
            end
            return oldNamecall(self, ...)
        end)
        _G.OldHookSet = true
    end

    -- ========================================
    -- [4] SMART COLLECT CORE FUNCTIONS
    -- [FIX-3] Semua pakai SC.StepDelay & SC.AvoidanceStrength — tidak campur global
    -- ========================================
    local function isWalkable(gx, gy)
        if gx < LIMIT.MIN_X or gx > LIMIT.MAX_X or gy < LIMIT.MIN_Y or gy > LIMIT.MAX_Y then
            return false, false
        end
        if lockedDoors[gx .. "," .. gy] then
            return false, false
        end

        local hasBlacklist = false
        local folders = {"Drops"}
        if SC.TakeGems then table.insert(folders, "Gems") end
        for _, folderName in pairs(folders) do
            local container = workspace:FindFirstChild(folderName)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    local itPos = item:GetPivot().Position
                    local itX = math.floor(itPos.X / 4.5 + 0.5)
                    local itY = math.floor(itPos.Y / 4.5 + 0.5)
                    if itX == gx and itY == gy then
                        local id = item:GetAttribute("id") or item.Name
                        if (getgenv().SayzSettings.PnB.ItemBlacklist or {})[id] then
                            hasBlacklist = true
                        end
                    end
                end
            end
        end

        if worldData[gx] and worldData[gx][gy] then
            local l1 = worldData[gx][gy][1]
            local itemName = (type(l1) == "table") and l1[1] or l1
            if itemName then
                local n = string.lower(tostring(itemName))
                if string.find(n, "door") or string.find(n, "frame") then
                    return true, hasBlacklist
                end
                return false, false
            end
        end
        return true, hasBlacklist
    end

    local function findSmartPath(startX, startY, targetX, targetY)
        local queue = {{x = startX, y = startY, path = {}, cost = 0}}
        local visited = {[startX .. "," .. startY] = 0}
        local directions = {
            {x = 1, y = 0}, {x = -1, y = 0},
            {x = 0, y = 1}, {x = 0, y = -1}
        }
        local limitCount = 0
        while #queue > 0 do
            if _G.LatestRunToken ~= myToken then break end
            limitCount = limitCount + 1
            if limitCount > 4000 then break end
            table.sort(queue, function(a, b) return a.cost < b.cost end)
            local current = table.remove(queue, 1)
            if current.x == targetX and current.y == targetY then
                return current.path
            end
            for _, d in ipairs(directions) do
                local nx, ny = current.x + d.x, current.y + d.y
                local walkable, isBlacklisted = isWalkable(nx, ny)
                if walkable then
                    -- [FIX-3] Pakai SC.AvoidanceStrength bukan getgenv().AvoidanceStrength
                    local moveCost = isBlacklisted and SC.AvoidanceStrength or 1
                    local newTotalCost = current.cost + moveCost
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

    local function getDropsInGrid(baseGrid)
        local drops = {}
        local gridSet = {}
        for coordKey, active in pairs(PnB.SelectedTiles) do
            if active then
                local parts = string.split(coordKey, ",")
                local tx = baseGrid.x + tonumber(parts[1])
                local ty = baseGrid.y + tonumber(parts[2])
                gridSet[tx .. "," .. ty] = true
            end
        end

        local folders = {"Drops"}
        if SC.TakeGems then table.insert(folders, "Gems") end
        for _, folderName in pairs(folders) do
            local container = workspace:FindFirstChild(folderName)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    if not badItems[item] then
                        local itPos = item:GetPivot().Position
                        local itX = math.floor(itPos.X / 4.5 + 0.5)
                        local itY = math.floor(itPos.Y / 4.5 + 0.5)
                        if gridSet[itX .. "," .. itY] then
                            table.insert(drops, item)
                        end
                    end
                end
            end
        end
        return drops
    end

    local function walkToPoint(Hitbox, targetItem)
        local sx = math.floor(Hitbox.Position.X / 4.5 + 0.5)
        local sy = math.floor(Hitbox.Position.Y / 4.5 + 0.5)
        local tx = math.floor(targetItem:GetPivot().Position.X / 4.5 + 0.5)
        local ty = math.floor(targetItem:GetPivot().Position.Y / 4.5 + 0.5)

        local path = findSmartPath(sx, sy, tx, ty)
        if not path then
            badItems[targetItem] = true
            return false
        end

        for i, point in ipairs(path) do
            if _G.LatestRunToken ~= myToken or not PnB.Master or not SC.Enabled then break end
            CollectStatusLabel:SetText("Collect: Walking (" .. i .. "/" .. #path .. ")")
            Hitbox.CFrame = CFrame.new(point.X, point.Y, Hitbox.Position.Z)
            movementModule.Position = Hitbox.Position
            -- [FIX-3] Pakai SC.StepDelay bukan getgenv().StepDelay
            task.wait(SC.StepDelay)

            local char = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if char then
                local dist = (Vector2.new(char.Position.X, char.Position.Y) - Vector2.new(point.X, point.Y)).Magnitude
                if dist > 5 then
                    local px = math.floor(point.X / 4.5 + 0.5)
                    local py = math.floor(point.Y / 4.5 + 0.5)
                    lockedDoors[px .. "," .. py] = true
                    return false
                end
            end
        end
        return true
    end

    local function walkBackToOrigin(Hitbox, originGrid)
        local sx = math.floor(Hitbox.Position.X / 4.5 + 0.5)
        local sy = math.floor(Hitbox.Position.Y / 4.5 + 0.5)
        local path = findSmartPath(sx, sy, originGrid.x, originGrid.y)
        if not path then return end
        for i, point in ipairs(path) do
            if _G.LatestRunToken ~= myToken or not PnB.Master then break end
            CollectStatusLabel:SetText("Collect: Returning (" .. i .. "/" .. #path .. ")")
            Hitbox.CFrame = CFrame.new(point.X, point.Y, Hitbox.Position.Z)
            movementModule.Position = Hitbox.Position
            task.wait(SC.StepDelay)
        end
    end

    -- ========================================
    -- [5] GRAVITY BYPASS
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait()
            if SC.Enabled and _G.LastPnBState == "Collecting" then
                pcall(function()
                    if movementModule.VelocityY < 0 then movementModule.VelocityY = 0 end
                    movementModule.Grounded = true
                end)
            end
        end
    end)

    -- ========================================
    -- [6] MAIN LOOP — STRICT STATE MACHINE
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            if PnB.Master then
                pcall(function()
                    local char = LP.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    if not root then return end

                    local baseGrid
                    if PnB.LockPosition and PnB.OriginGrid then
                        baseGrid = PnB.OriginGrid
                    else
                        baseGrid = {
                            x = math.floor((root.Position.X / 4.475) + 0.5),
                            y = math.floor(((root.Position.Y - 2.5) / 4.435) + 0.5)
                        }
                        PnB.OriginGrid = baseGrid
                    end

                    local function getAreaInfo()
                        local targets = {}
                        local currentFilled = 0
                        local selectedList = {}
                        for coordKey, active in pairs(PnB.SelectedTiles) do
                            if active then
                                local parts = string.split(coordKey, ",")
                                table.insert(selectedList, {ox = tonumber(parts[1]), oy = tonumber(parts[2])})
                            end
                        end
                        table.sort(selectedList, function(a, b)
                            if a.oy ~= b.oy then return a.oy > b.oy end
                            return a.ox < b.ox
                        end)
                        for _, offset in ipairs(selectedList) do
                            local tx = baseGrid.x + offset.ox
                            local ty = baseGrid.y + offset.oy
                            local tileData = worldData[tx] and worldData[tx][ty]
                            local blockExist = tileData and tileData[1] ~= nil
                            local wallExist = tileData and tileData[2] ~= nil
                            local isFilled = blockExist or wallExist
                            table.insert(targets, {
                                pos = Vector2.new(tx, ty),
                                isFilled = isFilled,
                                layer = blockExist and 1 or (wallExist and 2 or 1)
                            })
                            if isFilled then currentFilled = currentFilled + 1 end
                        end
                        return targets, currentFilled
                    end

                    local areaData, filledCount = getAreaInfo()
                    local maxTiles = #areaData

                    -- SIKLUS 1: BREAK
                    if PnB.Break and filledCount > 0 then
                        if filledCount == maxTiles or _G.LastPnBState == "Breaking"
                            or _G.LastPnBState == "Waiting" or (not PnB.Place) then
                            _G.LastPnBState = "Breaking"
                            if PnB.BreakMode == "Mode 1 (Fokus)" then
                                for _, tile in ipairs(areaData) do
                                    if _G.LatestRunToken ~= myToken or not PnB.Master then break end
                                    if tile.isFilled then
                                        while PnB.Master and PnB.Break do
                                            if _G.LatestRunToken ~= myToken then break end
                                            local check = worldData[tile.pos.X]
                                                and worldData[tile.pos.X][tile.pos.Y]
                                                and worldData[tile.pos.X][tile.pos.Y][tile.layer]
                                            if check == nil then break end
                                            game.ReplicatedStorage.Remotes.PlayerFist:FireServer(tile.pos)
                                            task.wait(0.035)
                                        end
                                    end
                                end
                            else
                                while filledCount > 0 and PnB.Master and PnB.Break do
                                    if _G.LatestRunToken ~= myToken then break end
                                    for _, tile in ipairs(areaData) do
                                        if _G.LatestRunToken ~= myToken then break end
                                        if tile.isFilled then
                                            game.ReplicatedStorage.Remotes.PlayerFist:FireServer(tile.pos)
                                            task.wait(0.02)
                                        end
                                    end
                                    areaData, filledCount = getAreaInfo()
                                end
                            end

                            areaData, filledCount = getAreaInfo()
                            if filledCount == 0 then
                                _G.LastPnBState = SC.Enabled and "Collecting" or "Placing"
                            end
                            return
                        end
                    end

                    -- SIKLUS 2: SMART COLLECT
                    if _G.LastPnBState == "Collecting" and SC.Enabled then
                        local Hitbox = workspace:FindFirstChild("Hitbox")
                            and workspace.Hitbox:FindFirstChild(LP.Name)
                        if not Hitbox then
                            _G.LastPnBState = "Placing"
                            return
                        end

                        while _G.LatestRunToken == myToken and PnB.Master and SC.Enabled do
                            local drops = getDropsInGrid(baseGrid)
                            if #drops == 0 then
                                CollectStatusLabel:SetText("Collect: Done! Kembali ke Origin...")
                                walkBackToOrigin(Hitbox, baseGrid)
                                _G.LastPnBState = "Placing"
                                CollectStatusLabel:SetText("Collect: Idle")
                                break
                            end

                            local nearest, nearestDist = nil, math.huge
                            for _, drop in ipairs(drops) do
                                local d = (Hitbox.Position - drop:GetPivot().Position).Magnitude
                                if d < nearestDist then
                                    nearestDist = d
                                    nearest = drop
                                end
                            end

                            if nearest then
                                local tName = IM.GetName(nearest:GetAttribute("id") or nearest.Name) or "Item"
                                CollectStatusLabel:SetText("Collect: → " .. tName)
                                local ok = walkToPoint(Hitbox, nearest)
                                if not ok then badItems[nearest] = true end
                            end

                            task.wait(0.1)
                        end
                        return
                    end

                    -- SIKLUS 3: PLACE
                    if PnB.Place and maxTiles > 0 then
                        areaData, filledCount = getAreaInfo()
                        if filledCount < maxTiles
                            and (_G.LastPnBState == "Placing" or _G.LastPnBState == "Waiting") then
                            _G.LastPnBState = "Placing"
                            if getActiveAmount() > 0 then
                                for _, tile in ipairs(areaData) do
                                    if _G.LatestRunToken ~= myToken or not PnB.Master then break end
                                    if not tile.isFilled then
                                        game.ReplicatedStorage.Remotes.PlayerPlaceItem:FireServer(
                                            tile.pos, PnB.TargetID, 1)
                                        task.wait(PnB.PlaceDelay)
                                    end
                                end
                            end
                            areaData, filledCount = getAreaInfo()
                            if filledCount == maxTiles then
                                _G.LastPnBState = "Waiting"
                                task.wait(PnB.ActualDelay)
                            end
                        end
                    end

                    if PnB.Break and not PnB.Place then
                        areaData, filledCount = getAreaInfo()
                        if filledCount == 0 and _G.LastPnBState ~= "Collecting" then
                            _G.LastPnBState = "Waiting"
                            task.wait(PnB.ActualDelay)
                        end
                    end
                end)
            end
            updatePnBVisuals()
            task.wait(0.01)
        end
        print("SayzHub: PnB + SmartCollect Loop terminated safely.")
    end)
end
