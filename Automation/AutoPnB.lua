return function(SubTab, Window, myToken)
    -- ========================================
    -- [1] SETUP, MODULES & VARIABLES
    -- ========================================
    local PnB = getgenv().SayzSettings.PnB 
    local worldData = require(game.ReplicatedStorage.WorldTiles)
    local LP = game.Players.LocalPlayer
    local movementModule = require(LP.PlayerScripts.PlayerMovement)
    local IM = require(game:GetService("ReplicatedStorage").Managers.ItemsManager)
    
    -- Sync Global Settings untuk Auto Collect
    getgenv().StepDelay = getgenv().StepDelay or 0.05
    PnB.SmartCollect = PnB.SmartCollect or false -- Toggle baru
    
    _G.LastPnBState = "Waiting" 
    local lockedDoors = {}
    local badItems = {}

    -- ========================================
    -- [2] UI ELEMENTS (NO DELETIONS)
    -- ========================================
    SubTab:AddSection("EKSEKUSI")
    getgenv().SayzUI_Handles["PnB_Master"] = SubTab:AddToggle("Master Switch", PnB.Master, function(t) PnB.Master = t end)
    getgenv().SayzUI_Handles["PnB_Place"] = SubTab:AddToggle("Enable Place", PnB.Place, function(t) PnB.Place = t end)
    getgenv().SayzUI_Handles["PnB_Break"] = SubTab:AddToggle("Enable Break", PnB.Break, function(t) PnB.Break = t end)
    getgenv().SayzUI_Handles["PnB_SmartCollect"] = SubTab:AddToggle("Smart Collect Drop", PnB.SmartCollect, function(t) PnB.SmartCollect = t end)

    SubTab:AddSection("SCANNER")
    SubTab:AddButton("Scan ID Item", function()
        PnB.Scanning = true
        Window:Notify("Pasang 1 blok manual untuk scan!", 3, "info")
    end)
    local InfoLabel = SubTab:AddLabel("ID Aktif: None")
    local StokLabel = SubTab:AddLabel("Total Stok: 0")
    local StatusLabel = SubTab:AddLabel("Status: Idle")

    SubTab:AddSection("SETTING")
    SubTab:AddInput("Speed Scale (Min 0.1)", "1", function(v)
        local val = tonumber(v) or 1
        PnB.DelayScale = math.max(0.1, val)
        PnB.ActualDelay = PnB.DelayScale * 0.12
    end)
    SubTab:AddSlider("Walking Speed", 0.01, 0.2, getgenv().StepDelay, function(val) getgenv().StepDelay = val end, 2)

    SubTab:AddSection("GRID TARGET (5x5)")
    SubTab:AddGridSelector(function(selectedTable)
        PnB.SelectedTiles = selectedTable
        local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if root then
            PnB.OriginGrid = {
                x = math.floor((root.Position.X / 4.475) + 0.5),
                y = math.floor(((root.Position.Y - 2.5) / 4.435) + 0.5)
            }
        end
    end)

    getgenv().SayzUI_Handles["PnB_LockPosition"] = SubTab:AddToggle("Lock Position", PnB.LockPosition, function(t) PnB.LockPosition = t end)
    getgenv().SayzUI_Handles["PnB_BreakMode"] = SubTab:AddDropdown("Multi-Break Mode", {"Mode 1 (Fokus)", "Mode 2 (Rata)"}, PnB.BreakMode, function(v) PnB.BreakMode = v end)

    -- ========================================
    -- [3] CORE ALGORITHMS (A* & UTILS)
    -- ========================================
    local function getActiveAmount()
        local total = 0
        local success, invModule = pcall(function() return require(game.ReplicatedStorage.Modules.Inventory) end)
        if success and invModule.Stacks then
            local targetIndex = tonumber(PnB.TargetID)
            local baseStack = invModule.Stacks[targetIndex]
            if baseStack and baseStack.Id then
                for _, stack in pairs(invModule.Stacks) do
                    if stack and stack.Id == baseStack.Id then total = total + (stack.Amount or 0) end
                end
            end
        end
        return total
    end

    local function isWalkable(gx, gy)
        if lockedDoors[gx .. "," .. gy] then return false end
        if worldData[gx] and worldData[gx][gy] then
            local l1 = worldData[gx][gy][1]
            local n = string.lower(tostring((type(l1) == "table") and l1[1] or l1))
            if string.find(n, "door") or string.find(n, "frame") then return true end
            return false
        end
        return true
    end

    local function findSmartPath(startX, startY, targetX, targetY)
        local queue = {{x = startX, y = startY, path = {}, cost = 0}}
        local visited = {[startX .. "," .. startY] = 0}
        local directions = {{x=1,y=0}, {x=-1,y=0}, {x=0,y=1}, {x=0,y=-1}}
        local limit = 0
        while #queue > 0 do
            limit = limit + 1
            if limit > 2000 or _G.LatestRunToken ~= myToken then break end
            table.sort(queue, function(a, b) return a.cost < b.cost end)
            local curr = table.remove(queue, 1)
            if curr.x == targetX and curr.y == targetY then return curr.path end
            for _, d in ipairs(directions) do
                local nx, ny = curr.x + d.x, curr.y + d.y
                if isWalkable(nx, ny) then
                    if not visited[nx .. "," .. ny] then
                        visited[nx .. "," .. ny] = curr.cost + 1
                        local newPath = {unpack(curr.path)}
                        table.insert(newPath, Vector3.new(nx * 4.475, (ny * 4.435) + 2.5, 0))
                        table.insert(queue, {x=nx, y=ny, path=newPath, cost=curr.cost+1})
                    end
                end
            end
        end
        return nil
    end

    -- ========================================
    -- [4] GRAVITY BYPASS (STABILITY)
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait()
            if PnB.Master and (_G.LastPnBState == "Collecting" or PnB.LockPosition) then
                pcall(function()
                    movementModule.VelocityY = 0
                    movementModule.Grounded = true
                end)
            end
        end
    end)

    -- ========================================
    -- [5] MAIN STATE MACHINE LOOP
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            if PnB.Master then
                pcall(function()
                    local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
                    if not Hitbox then return end

                    -- Mendapatkan Base Posisi
                    local baseGrid = PnB.OriginGrid or {
                        x = math.floor(Hitbox.Position.X / 4.475 + 0.5),
                        y = math.floor((Hitbox.Position.Y - 2.5) / 4.435 + 0.5)
                    }

                    -- Function helper Area
                    local function getAreaStatus()
                        local currentFilled = 0
                        local targets = {}
                        for coordKey, active in pairs(PnB.SelectedTiles) do
                            if active then
                                local p = string.split(coordKey, ",")
                                local tx, ty = baseGrid.x + tonumber(p[1]), baseGrid.y + tonumber(p[2])
                                local tile = worldData[tx] and worldData[tx][ty]
                                local exists = tile and (tile[1] ~= nil or tile[2] ~= nil)
                                if exists then currentFilled = currentFilled + 1 end
                                table.insert(targets, {pos = Vector2.new(tx, ty), isFilled = exists, layer = (tile and tile[1]) and 1 or 2})
                            end
                        end
                        return targets, currentFilled
                    end

                    -- Function scan item di area 5x5 saja
                    local function getDropsInGrid()
                        local drops = {}
                        local container = workspace:FindFirstChild("Drops")
                        if not container then return drops end
                        for _, item in pairs(container:GetChildren()) do
                            local ip = item:GetPivot().Position
                            local ix, iy = math.floor(ip.X/4.475+0.5), math.floor((ip.Y-2.5)/4.435+0.5)
                            for coordKey, active in pairs(PnB.SelectedTiles) do
                                if active then
                                    local p = string.split(coordKey, ",")
                                    if ix == (baseGrid.x + tonumber(p[1])) and iy == (baseGrid.y + tonumber(p[2])) then
                                        table.insert(drops, item)
                                    end
                                end
                            end
                        end
                        return drops
                    end

                    local areaData, filledCount = getAreaStatus()

                    -- STATE 1: BREAKING
                    if PnB.Break and filledCount > 0 and (_G.LastPnBState == "Breaking" or _G.LastPnBState == "Waiting") then
                        _G.LastPnBState = "Breaking"
                        StatusLabel:SetText("Status: Breaking Grid...")
                        for _, tile in ipairs(areaData) do
                            if not PnB.Master or _G.LatestRunToken ~= myToken then break end
                            if tile.isFilled then
                                while worldData[tile.pos.X][tile.pos.Y][tile.layer] ~= nil and PnB.Master do
                                    game.ReplicatedStorage.Remotes.PlayerFist:FireServer(tile.pos)
                                    task.wait(0.035)
                                    if PnB.BreakMode == "Mode 2 (Rata)" then break end
                                end
                            end
                        end
                    end

                    -- STATE 2: SMART COLLECT (Hanya jalan jika grid sudah pecah semua)
                    areaData, filledCount = getAreaStatus()
                    local drops = getDropsInGrid()
                    if PnB.SmartCollect and filledCount == 0 and #drops > 0 then
                        _G.LastPnBState = "Collecting"
                        StatusLabel:SetText("Status: Collecting Drops ("..#drops..")")
                        
                        for _, item in ipairs(drops) do
                            if not PnB.Master or _G.LatestRunToken ~= myToken or not item.Parent then break end
                            local sx, sy = math.floor(Hitbox.Position.X/4.475+0.5), math.floor((Hitbox.Position.Y-2.5)/4.435+0.5)
                            local ip = item:GetPivot().Position
                            local tx, ty = math.floor(ip.X/4.475+0.5), math.floor((ip.Y-2.5)/4.435+0.5)
                            
                            local path = findSmartPath(sx, sy, tx, ty)
                            if path then
                                for _, point in ipairs(path) do
                                    Hitbox.CFrame = CFrame.new(point.X, point.Y, Hitbox.Position.Z)
                                    movementModule.Position = Hitbox.Position
                                    task.wait(getgenv().StepDelay)
                                end
                            end
                        end
                        
                        -- Kembali ke Origin setelah bersih
                        StatusLabel:SetText("Status: Returning to Origin")
                        local ox, oy = baseGrid.x, baseGrid.y
                        local currX, currY = math.floor(Hitbox.Position.X/4.475+0.5), math.floor((Hitbox.Position.Y-2.5)/4.435+0.5)
                        local backPath = findSmartPath(currX, currY, ox, oy)
                        if backPath then
                            for _, point in ipairs(backPath) do
                                Hitbox.CFrame = CFrame.new(point.X, point.Y, Hitbox.Position.Z)
                                movementModule.Position = Hitbox.Position
                                task.wait(getgenv().StepDelay)
                            end
                        end
                    end

                    -- STATE 3: PLACING (Hanya jalan jika grid kosong & item sudah bersih)
                    drops = getDropsInGrid()
                    areaData, filledCount = getAreaStatus()
                    if PnB.Place and filledCount < #areaData and #drops == 0 then
                        _G.LastPnBState = "Placing"
                        StatusLabel:SetText("Status: Placing Blocks...")
                        if getActiveAmount() > 0 then
                            for _, tile in ipairs(areaData) do
                                if not PnB.Master or _G.LatestRunToken ~= myToken then break end
                                if not tile.isFilled then
                                    game.ReplicatedStorage.Remotes.PlayerPlaceItem:FireServer(tile.pos, PnB.TargetID, 1)
                                    task.wait(PnB.PlaceDelay or 0.1)
                                end
                            end
                        end
                        _G.LastPnBState = "Waiting"
                    end
                end)
            end
            
            -- UI Updates
            pcall(function()
                InfoLabel:SetText("ID Aktif: " .. (PnB.TargetID or "None"))
                StokLabel:SetText("Total Stok: " .. getActiveAmount())
            end)
            task.wait(0.05)
        end
    end)
end
