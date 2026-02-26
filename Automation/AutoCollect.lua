return function(SubTab, Window)
    -- [[ 1. SETUP & VARIABLES ]] --
    local LP = game:GetService("Players").LocalPlayer
    local WorldTiles = require(game.ReplicatedStorage.WorldTiles)
    local movementModule = require(LP.PlayerScripts.PlayerMovement)
    local IM = require(game:GetService("ReplicatedStorage").Managers.ItemsManager)

    getgenv().AutoCollect = getgenv().AutoCollect or false
    getgenv().TakeGems = getgenv().TakeGems or true 
    getgenv().StepDelay = getgenv().StepDelay or 0.05 
    getgenv().ItemBlacklist = getgenv().ItemBlacklist or {} 

    local LIMIT = { MIN_X = 0, MAX_X = 100, MIN_Y = 6, MAX_Y = 60 }
    local doorDatabase = {} 
    local lockedDoors = {} 
    local badItems = {} 
    local currentPool = {"dirt"} 

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

    local function getBlacklistItemAt(gx, gy)
        local folders = {"Drops"}
        if getgenv().TakeGems then table.insert(folders, "Gems") end
        for _, folder in pairs(folders) do
            local container = workspace:FindFirstChild(folder)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    local itX, itY = math.floor(item:GetPivot().Position.X/4.5+0.5), math.floor(item:GetPivot().Position.Y/4.5+0.5)
                    if itX == gx and itY == gy then
                        local id = item:GetAttribute("id") or item.Name
                        if getgenv().ItemBlacklist[id] then return true end
                    end
                end
            end
        end
        return false
    end

    local function isWalkable(gx, gy)
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

    local function findSmartPath(startX, startY, targetX, targetY)
        local queue = {{x = startX, y = startY, path = {}, cost = 0}}
        local visited = {[startX .. "," .. startY] = 0}
        local directions = {{x=1, y=0}, {x=-1, y=0}, {x=0, y=1}, {x=0, y=-1}}
        local limit = 0
        while #queue > 0 do
            limit = limit + 1
            if limit > 3000 then break end 
            table.sort(queue, function(a, b) return a.cost < b.cost end)
            local current = table.remove(queue, 1)
            if current.x == targetX and current.y == targetY then return current.path end
            for _, d in ipairs(directions) do
                local nx, ny = current.x + d.x, current.y + d.y
                local walkable, isBlacklisted = isWalkable(nx, ny)
                if walkable then
                    local moveCost = isBlacklisted and 100 or 1
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
                    if not badItems[item] and not getgenv().ItemBlacklist[id] then
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

    -- [[ 3. UI ELEMENTS ]] --

    SubTab:AddSection("Auto Collect Master")
    SubTab:AddToggle("Enable Auto Collect", getgenv().AutoCollect, function(state)
        getgenv().AutoCollect = state
        if state then InitDoorDatabase() end
    end)

    -- TOGGLE GEMS
    SubTab:AddToggle("Collect Gems", getgenv().TakeGems, function(state)
        getgenv().TakeGems = state
    end)

    SubTab:AddInput("Step Delay (Decimal)", tostring(getgenv().StepDelay), function(v)
        local val = tonumber(v)
        if val then
            getgenv().StepDelay = math.max(val, 0.01)
            Window:Notify("Speed set to: " .. getgenv().StepDelay, 2)
        end
    end)

    SubTab:AddSection("Filter Management")
    local FilterLabel = SubTab:AddLabel("Active Blacklist: None")

    local MultiDrop
    MultiDrop = SubTab:AddMultiDropdown("Add/Remove Blacklist", currentPool, function(selected)
        getgenv().ItemBlacklist = selected
        local items = {}
        for k, _ in pairs(selected) do table.insert(items, k) end
        FilterLabel:SetText(#items > 0 and "Active Blacklist: " .. table.concat(items, ", ") or "Active Blacklist: None")
    end)

    SubTab:AddButton("Scan Items in World", function()
        local found = {}
        for _, folder in pairs({"Drops", "Gems"}) do
            local container = workspace:FindFirstChild(folder)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    local id = item:GetAttribute("id") or item.Name
                    if not table.find(found, id) then table.insert(found, id) end
                end
            end
        end
        if #found > 0 then
            currentPool = found
            MultiDrop:UpdateList(found)
            Window:Notify("Scan complete! " .. #found .. " items found.", 2)
        end
    end)

    SubTab:AddButton("Reset All Filters", function()
        getgenv().ItemBlacklist = {}
        badItems = {}
        lockedDoors = {}
        FilterLabel:SetText("Active Blacklist: None")
        -- Perbaikan: Membersihkan dropdown UI
        if MultiDrop.Set then MultiDrop:Set({}) end 
        Window:Notify("Filters & UI Cleared!", 2)
    end)

    SubTab:AddSection("Status Dashboard")
    local StatusLabel = SubTab:AddLabel("Status: Idle")
    local TargetLabel = SubTab:AddLabel("Current Item: None")
    local PathLabel = SubTab:AddLabel("Safety: N/A")

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
                        local targetName = IM.GetName(target:GetAttribute("id") or target.Name) or "Item"
                        TargetLabel:SetText("Current Item: " .. targetName)
                        
                        local sx, sy = math.floor(Hitbox.Position.X/4.5+0.5), math.floor(Hitbox.Position.Y/4.5+0.5)
                        local tx, ty = math.floor(target:GetPivot().Position.X/4.5+0.5), math.floor(target:GetPivot().Position.Y/4.5+0.5)

                        local path = findSmartPath(sx, sy, tx, ty)
                        if path then
                            -- Cek jalur keseluruhan
                            local terpaksa = false
                            for _, p in ipairs(path) do
                                if getBlacklistItemAt(math.floor(p.X/4.5+0.5), math.floor(p.Y/4.5+0.5)) then
                                    terpaksa = true; break
                                end
                            end
                            PathLabel:SetText("Safety: " .. (terpaksa and "⚠️ FORCED PATH" or "✅ SAFE ROUTE"))

                            -- LOOP JALAN
                            for i, point in ipairs(path) do
                                if not getgenv().AutoCollect then break end
                                
                                StatusLabel:SetText("Status: Walking (" .. i .. "/" .. #path .. ")")
                                Hitbox.CFrame = CFrame.new(point.X, point.Y, Hitbox.Position.Z)
                                movementModule.Position = Hitbox.Position
                                task.wait(getgenv().StepDelay)

                                -- Deteksi Stuck
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
                        TargetLabel:SetText("Current Item: None")
                        StatusLabel:SetText("Status: Scanning...")
                        PathLabel:SetText("Safety: N/A")
                    end
                else
                    StatusLabel:SetText("Status: Paused")
                end
            end)
            task.wait(0.2)
        end
    end)
end
