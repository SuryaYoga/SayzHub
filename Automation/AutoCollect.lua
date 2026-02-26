return function(SubTab, Window)
    -- [[ 1. SETUP & VARIABLES ]] --
    local LP = game:GetService("Players").LocalPlayer
    local WorldTiles = require(game.ReplicatedStorage.WorldTiles)
    local movementModule = require(LP.PlayerScripts.PlayerMovement)

    getgenv().AutoCollect = getgenv().AutoCollect or false
    getgenv().TakeGems = getgenv().TakeGems or true 
    getgenv().StepDelay = getgenv().StepDelay or 0.05 
    getgenv().ItemBlacklist = getgenv().ItemBlacklist or {} 

    local LIMIT = { MIN_X = 0, MAX_X = 100, MIN_Y = 6, MAX_Y = 60 }
    local doorDatabase = {} 
    local lockedDoors = {} 
    local badItems = {} 

    -- [[ 2. CORE FUNCTIONS ]] --

    local function InitDoorDatabase()
        doorDatabase = {}
        for gx, columns in pairs(WorldTiles) do
            for gy, tileData in pairs(columns) do
                local l1 = tileData[1]
                local itemName = (type(l1) == "table") and l1[1] or l1
                if itemName and string.find(string.lower(tostring(itemName)), "door") then
                    doorDatabase[gx .. "," .. gy] = true
                end
            end
        end
    end

    -- Fungsi Pengecekan Item Blacklist di Koordinat (Favoritmu)
    local function getBlacklistItemAt(gx, gy)
        for _, folder in pairs({"Drops", "Gems"}) do
            local container = workspace:FindFirstChild(folder)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    local itX, itY = math.floor(item:GetPivot().Position.X/4.5+0.5), math.floor(item:GetPivot().Position.Y/4.5+0.5)
                    if itX == gx and itY == gy then
                        local id = item:GetAttribute("id") or item.Name
                        if getgenv().ItemBlacklist[id] then
                            return true 
                        end
                    end
                end
            end
        end
        return false
    end

    local function isWalkable(gx, gy, currentY)
        if gx < LIMIT.MIN_X or gx > LIMIT.MAX_X or gy < LIMIT.MIN_Y or gy > LIMIT.MAX_Y then return false, false end
        if lockedDoors[gx .. "," .. gy] then return false, false end 

        if WorldTiles[gx] and WorldTiles[gx][gy] then
            local l1 = WorldTiles[gx][gy][1]
            local itemName = (type(l1) == "table") and l1[1] or l1
            if itemName then
                local n = string.lower(tostring(itemName))
                if string.find(n, "door") or string.find(n, "frame") then 
                    return true, getBlacklistItemAt(gx, gy) 
                end
                return false, false 
            end
        end
        return true, getBlacklistItemAt(gx, gy)
    end

    -- Pathfinding Pintar (Dijkstra-lite)
    local function findSmartPath(startX, startY, targetX, targetY)
        local queue = {{x = startX, y = startY, path = {}, cost = 0}}
        local visited = {[startX .. "," .. startY] = 0}
        local directions = {{x=1, y=0}, {x=-1, y=0}, {x=0, y=1}, {x=0, y=-1}}
        
        local limit = 0
        while #queue > 0 do
            limit = limit + 1
            if limit > 5000 then break end 
            
            table.sort(queue, function(a, b) return a.cost < b.cost end)
            local current = table.remove(queue, 1)

            if current.x == targetX and current.y == targetY then
                return current.path 
            end

            for _, d in ipairs(directions) do
                local nx, ny = current.x + d.x, current.y + d.y
                local walkable, isBlacklisted = isWalkable(nx, ny, current.y)
                
                if walkable then
                    local moveCost = isBlacklisted and 100 or 1
                    local newTotalCost = current.cost + moveCost
                    
                    local posKey = nx .. "," .. ny
                    if not visited[posKey] or newTotalCost < visited[posKey] then
                        visited[posKey] = newTotalCost
                        local newPath = {unpack(current.path)}
                        table.insert(newPath, Vector3.new(nx * 4.5, ny * 4.5, 0))
                        table.insert(queue, {x = nx, y = ny, path = newPath, cost = newTotalCost})
                    end
                end
            end
        end
        return nil
    end

    local function GetNearestItem()
        local target, dist = nil, 500
        local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not root then return nil end

        local folders = {"Drops"}
        if getgenv().TakeGems then table.insert(folders, "Gems") end

        for _, folder in pairs(folders) do
            local container = workspace:FindFirstChild(folder)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    local id = item:GetAttribute("id") or item.Name
                    if not getgenv().ItemBlacklist[id] and not badItems[item] then
                        local d = (root.Position - item:GetPivot().Position).Magnitude
                        if d < dist then dist = d; target = item end
                    end
                end
            end
        end
        return target
    end

    local function scanAndLockNearbyDoor(gx, gy)
        local radius = 3 
        for dx = -radius, radius do
            for dy = -radius, radius do
                local key = (gx + dx) .. "," .. (gy + dy)
                if doorDatabase[key] then lockedDoors[key] = true end
            end
        end
    end

    -- [[ 3. UI SECTION ]] --
    SubTab:AddSection("CONTROL PANEL")
    SubTab:AddToggle("Enable Auto Collect", getgenv().AutoCollect, function(state)
        getgenv().AutoCollect = state
        if state then InitDoorDatabase() end
    end)
    SubTab:AddToggle("Collect Gems", getgenv().TakeGems, function(s) getgenv().TakeGems = s end)
    SubTab:AddInput("Step Delay", tostring(getgenv().StepDelay), function(v)
        getgenv().StepDelay = tonumber(v) or 0.05
    end)

    SubTab:AddSection("ITEM FILTER")
    local FilterLabel = SubTab:AddLabel("🚫 Blacklist: None")

    local MultiDrop
    MultiDrop = SubTab:AddMultiDropdown("Blacklist Items", {}, function(selected)
        getgenv().ItemBlacklist = selected
        local names = {}
        for name, _ in pairs(selected) do table.insert(names, name) end
        
        if #names == 0 then
            FilterLabel:SetText("🚫 Blacklist: None")
        else
            local text = table.concat(names, ", ", 1, math.min(#names, 3))
            if #names > 3 then text = text .. " (+" .. (#names-3) .. ")" end
            FilterLabel:SetText("🚫 Blacklist: " .. text)
        end
    end)

    SubTab:AddButton("Scan World Items", function()
        local items = {}
        for _, f in pairs({"Drops", "Gems"}) do
            local c = workspace:FindFirstChild(f)
            if c then for _, item in pairs(c:GetChildren()) do
                local id = item:GetAttribute("id") or item.Name
                if not table.find(items, id) then table.insert(items, id) end
            end end
        end
        MultiDrop:UpdateList(items)
    end)

    SubTab:AddButton("Reset All Filters", function()
        getgenv().ItemBlacklist = {}
        badItems = {}
        lockedDoors = {}
        FilterLabel:SetText("🚫 Blacklist: None")
        if MultiDrop.ClearAll then MultiDrop:ClearAll() end
        Window:Notify("Cleared!", 2)
    end)

    SubTab:AddSection("LIVE STATISTICS")
    local StatusLabel = SubTab:AddLabel("Status: Idle")
    local TargetLabel = SubTab:AddLabel("Target: None")

    -- [[ 4. GRAVITY BYPASS ]] --
    task.spawn(function()
        while task.wait() do
            if getgenv().AutoCollect then
                pcall(function()
                    if movementModule.VelocityY < 0 then movementModule.VelocityY = 0 end
                    movementModule.Grounded = true 
                end)
            end
        end
    end)

    -- [[ 5. MAIN LOOP ]] --
    InitDoorDatabase()
    task.spawn(function()
        while true do
            pcall(function()
                if getgenv().AutoCollect then
                    local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
                    local target = GetNearestItem()
                    
                    if Hitbox and target then
                        TargetLabel:SetText("Target: " .. (target:GetAttribute("id") or target.Name))
                        StatusLabel:SetText("Status: Moving...")
                        
                        local sx, sy = math.floor(Hitbox.Position.X/4.5+0.5), math.floor(Hitbox.Position.Y/4.5+0.5)
                        local tx, ty = math.floor(target:GetPivot().Position.X/4.5+0.5), math.floor(target:GetPivot().Position.Y/4.5+0.5)

                        local path = findSmartPath(sx, sy, tx, ty)
                        if path then
                            for _, point in ipairs(path) do
                                if not getgenv().AutoCollect then break end
                                -- Gerakan Karakter
                                Hitbox.CFrame = CFrame.new(point.X, point.Y, Hitbox.Position.Z)
                                movementModule.Position = Hitbox.Position
                                
                                -- JEDA UTAMA: Jika masih "kecepetan", naikkan StepDelay di UI (misal 0.07)
                                task.wait(getgenv().StepDelay)

                                -- Deteksi Stuck Pintu
                                local charPos = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") and LP.Character.HumanoidRootPart.Position
                                if charPos and (Vector2.new(charPos.X, charPos.Y) - Vector2.new(point.X, point.Y)).Magnitude > 4.5 then
                                    scanAndLockNearbyDoor(math.floor(point.X/4.5+0.5), math.floor(point.Y/4.5+0.5))
                                    break 
                                end
                            end
                        else
                            badItems[target] = true
                        end
                    else
                        TargetLabel:SetText("Target: None")
                        StatusLabel:SetText("Status: Scanning...")
                    end
                else
                    StatusLabel:SetText("Status: Paused")
                end
            end)
            -- Jeda antar pencarian item baru (Sangat penting buat kestabilan)
            task.wait(0.2) 
        end
    end)
end
