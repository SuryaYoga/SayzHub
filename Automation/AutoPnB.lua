return function(SubTab, Window, myToken)
    -- ========================================
    -- [1] VARIABEL & SETUP (SINKRON TOKEN)
    -- ========================================
    local PnB = getgenv().SayzSettings.PnB 
    local worldData = require(game.ReplicatedStorage.WorldTiles)
    local LP = game.Players.LocalPlayer
    local movementModule = require(LP.PlayerScripts.PlayerMovement)
    local IM = require(game:GetService("ReplicatedStorage").Managers.ItemsManager)
    
    local LIMIT = { MIN_X = 0, MAX_X = 100, MIN_Y = 6, MAX_Y = 60 }
    local lockedDoors = {}
    _G.LastPnBState = "Waiting" 

    -- ========================================
    -- [2] PATHFINDING CORE (COPY DARI AUTOCOLLECT ABANG)
    -- ========================================
    local function isWalkable(gx, gy)
        if gx < LIMIT.MIN_X or gx > LIMIT.MAX_X or gy < LIMIT.MIN_Y or gy > LIMIT.MAX_Y then return false, false end
        if lockedDoors[gx .. "," .. gy] then return false, false end 
        if worldData[gx] and worldData[gx][gy] then
            local l1 = worldData[gx][gy][1]
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
                    local moveCost = 1
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

    -- ========================================
    -- [3] UI ELEMENTS (FITUR PNB UTUH 100%)
    -- ========================================
    SubTab:AddSection("EKSEKUSI")
    getgenv().SayzUI_Handles["PnB_Master"] = SubTab:AddToggle("Master Switch", PnB.Master, function(t) PnB.Master = t end)
    getgenv().SayzUI_Handles["PnB_Place"] = SubTab:AddToggle("Enable Place", PnB.Place, function(t) PnB.Place = t end)
    getgenv().SayzUI_Handles["PnB_Break"] = SubTab:AddToggle("Enable Break", PnB.Break, function(t) PnB.Break = t end)
    -- Toggle tambahan untuk collect
    getgenv().SayzUI_Handles["PnB_SmartCollect"] = SubTab:AddToggle("Smart Collect (Grid)", PnB.AutoCollectInGrid, function(t) PnB.AutoCollectInGrid = t end)

    SubTab:AddSection("SCANNER")
    SubTab:AddButton("Scan ID Item", function() PnB.Scanning = true end)
    local InfoLabel = SubTab:AddLabel("ID Aktif: None")
    local StokLabel = SubTab:AddLabel("Total Stok: 0")

    SubTab:AddSection("SETTING")
    getgenv().SayzUI_Handles["PnB_SpeedScale"] = SubTab:AddInput("Speed Scale (Min 0.1)", "1", function(v)
        local val = tonumber(v) or 1
        PnB.DelayScale = (val < 0.1) and 0.1 or val
        PnB.ActualDelay = PnB.DelayScale * 0.12
    end)

    SubTab:AddSection("GRID TARGET (5x5)")
    SubTab:AddGridSelector(function(selectedTable)
        PnB.SelectedTiles = selectedTable
        local char = LP.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            PnB.OriginGrid = { x = math.floor((root.Position.X / 4.475) + 0.5), y = math.floor(((root.Position.Y - 2.5) / 4.435) + 0.5) }
        end
    end)

    getgenv().SayzUI_Handles["PnB_LockPosition"] = SubTab:AddToggle("Lock Position", PnB.LockPosition, function(t) PnB.LockPosition = t end)
    getgenv().SayzUI_Handles["PnB_BreakMode"] = SubTab:AddDropdown("Multi-Break Mode", {"Mode 1 (Fokus)", "Mode 2 (Rata)"}, PnB.BreakMode, function(v) PnB.BreakMode = v end)

    -- ========================================
    -- [4] FUNCTIONS HELPER
    -- ========================================
    local function GetDropsInGrid(targets)
        local drops = {}
        for _, tile in ipairs(targets) do
            for _, folder in pairs({"Drops", "Gems"}) do
                local container = workspace:FindFirstChild(folder)
                if container then
                    for _, item in pairs(container:GetChildren()) do
                        local pos = item:GetPivot().Position
                        local ix, iy = math.floor(pos.X/4.5+0.5), math.floor(pos.Y/4.5+0.5)
                        if ix == tile.pos.X and iy == tile.pos.Y then table.insert(drops, item) end
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

    -- Hook Metamethod Scanner (ASLI)
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
    -- [5] MAIN LOOP (URUTAN KAKU & JALAN KAKI)
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            if PnB.Master then
                pcall(function()
                    local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
                    if not Hitbox then return end
                    local baseGrid = (PnB.LockPosition and PnB.OriginGrid) or { x = math.floor((Hitbox.Position.X / 4.475) + 0.5), y = math.floor(((Hitbox.Position.Y - 2.5) / 4.435) + 0.5) }

                    -- 1. Scan Grid
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
                        local tileData = worldData[tx] and worldData[tx][ty]
                        local isFilled = tileData and tileData[1] ~= nil
                        table.insert(targets, {pos = Vector2.new(tx, ty), isFilled = isFilled})
                        if isFilled then currentFilled = currentFilled + 1 end
                    end

                    -- PHASE A: BREAK (Pukul sampai ludes)
                    if PnB.Break and currentFilled > 0 then
                        _G.LastPnBState = "Breaking"
                        for _, tile in ipairs(targets) do
                            if _G.LatestRunToken ~= myToken or not PnB.Master then break end
                            if tile.isFilled then
                                while PnB.Master and PnB.Break and worldData[tile.pos.X][tile.pos.Y][1] ~= nil do
                                    game.ReplicatedStorage.Remotes.PlayerFist:FireServer(tile.pos); task.wait(0.035)
                                end
                            end
                        end
                    end

                    -- PHASE B: COLLECT (JALAN KAKI 100% IDENTIK AUTOCOLLECT)
                    local drops = GetDropsInGrid(targets)
                    if PnB.AutoCollectInGrid and PnB.Master and #drops > 0 then
                        _G.LastPnBState = "Collecting"
                        while #drops > 0 and PnB.Master and PnB.AutoCollectInGrid do
                            if _G.LatestRunToken ~= myToken then break end
                            local item = drops[1]
                            if item and item.Parent then
                                local sx, sy = math.floor(Hitbox.Position.X/4.5+0.5), math.floor(Hitbox.Position.Y/4.5+0.5)
                                local tx, ty = math.floor(item:GetPivot().Position.X/4.5+0.5), math.floor(item:GetPivot().Position.Y/4.5+0.5)
                                local path = findSmartPath(sx, sy, tx, ty)
                                if path then
                                    for _, pt in ipairs(path) do
                                        if _G.LatestRunToken ~= myToken then break end
                                        -- CARA JALAN ASLI ABANG
                                        Hitbox.CFrame = CFrame.new(pt.X, pt.Y, Hitbox.Position.Z)
                                        movementModule.Position = Hitbox.Position
                                        task.wait(getgenv().StepDelay or 0.05)
                                    end
                                    task.wait(0.2) -- Scan ulang di lokasi
                                end
                            end
                            drops = GetDropsInGrid(targets)
                        end
                        -- BALIK KE ORIGIN (JALAN PERLAHAN PAKAI SMARTPATH)
                        local curX, curY = math.floor(Hitbox.Position.X/4.5+0.5), math.floor(Hitbox.Position.Y/4.5+0.5)
                        local backPath = findSmartPath(curX, curY, baseGrid.x, baseGrid.y)
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
                    local canPlaceNow = (not PnB.AutoCollectInGrid) or (PnB.AutoCollectInGrid and #finalDrops == 0)
                    if PnB.Place and currentFilled < #targets and canPlaceNow then
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
            task.wait(0.1)
        end
    end)

    -- CHANGELOG VERIFICATION
    SubTab:AddParagraph("Update Log", "**Perbaikan Terakhir:**\n1. Copy-Paste 100% pergerakan `Hitbox` & `movementModule` dari AutoCollect.\n2. Scan item dikunci hanya pada tile grid.\n3. Logika `while` pada Collect: mungut item sampai grid beneran 0 baru jalan pulang.\n4. Balik ke posisi awal sekarang pakai SmartPath (berjalan), bukan teleport.\n5. Mengembalikan seluruh fitur UI PnB asli.")
end
