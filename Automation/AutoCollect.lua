return function(SubTab, Window)
    -- [[ 1. SETUP & REFERENCES ]] --
    local LP = game:GetService("Players").LocalPlayer
    local WorldTiles = require(game.ReplicatedStorage.WorldTiles)
    local movementModule = require(LP.PlayerScripts.PlayerMovement)
    local IM = require(game:GetService("ReplicatedStorage").Managers.ItemsManager)

    -- Merujuk ke Pusat Data di Main.lua
    local S = getgenv().SayzSettings.AutoCollect

    local LIMIT = { MIN_X = 0, MAX_X = 100, MIN_Y = 6, MAX_Y = 60 }
    local doorDatabase = {} 
    local lockedDoors = {} 
    local badItems = {} 
    local currentPool = {} 

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
        if S.TakeGems then table.insert(folders, "Gems") end
        for _, folderName in pairs(folders) do
            local container = workspace:FindFirstChild(folderName)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    local itPos = item:GetPivot().Position
                    local itX = math.floor(itPos.X / 4.5 + 0.5)
                    local itY = math.floor(itPos.Y / 4.5 + 0.5)
                    
                    if itX == gx and itY == gy then
                        local id = item:GetAttribute("id") or item.Name
                        if S.ItemBlacklist[id] then return true end
                    end
                end
            end
        end
        return false
    end

    local function isWalkable(gx, gy)
        if gx < LIMIT.MIN_X or gx > LIMIT.MAX_X or gy < LIMIT.MIN_Y or gy > LIMIT.MAX_Y then 
            return false, false 
        end
        if lockedDoors[gx .. "," .. gy] then return false, false end 

        local hasBlacklist = getBlacklistItemAt(gx, gy)

        if WorldTiles[gx] and WorldTiles[gx][gy] then
            local l1 = WorldTiles[gx][gy][1]
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
        local directions = {{x = 1, y = 0}, {x = -1, y = 0}, {x = 0, y = 1}, {x = 0, y = -1}}
        
        local limitCount = 0
        while #queue > 0 do
            limitCount = limitCount + 1
            if limitCount > 4000 then break end 

            table.sort(queue, function(a, b) return a.cost < b.cost end)
            local current = table.remove(queue, 1)

            if current.x == targetX and current.y == targetY then return current.path end

            for _, d in ipairs(directions) do
                local nx, ny = current.x + d.x, current.y + d.y
                local walkable, isBlacklisted = isWalkable(nx, ny)

                if walkable then
                    local moveCost = isBlacklisted and S.AvoidanceStrength or 1
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
        if S.TakeGems then table.insert(folders, "Gems") end

        for _, folder in pairs(folders) do
            local container = workspace:FindFirstChild(folder)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    local id = item:GetAttribute("id") or item.Name
                    if not badItems[item] and not S.ItemBlacklist[id] then
                        local d = (root.Position - item:GetPivot().Position).Magnitude
                        if d < dist then dist = d; target = item end
                    end
                end
            end
        end
        return target
    end

    -- [[ 3. UI ELEMENTS ]] --

    SubTab:AddSection("Auto Collect Master")
    SubTab:AddToggle("Enable Auto Collect", S.Enabled, function(state)
        S.Enabled = state
        if state then InitDoorDatabase() end
    end)

    SubTab:AddToggle("Collect Gems", S.TakeGems, function(state)
        S.TakeGems = state
    end)

    SubTab:AddSection("Path & Speed Settings")
    SubTab:AddSlider("Movement Speed", 0.01, 0.2, S.StepDelay, function(val)
        S.StepDelay = val
    end)

    SubTab:AddInput("Avoidance Cost", tostring(S.AvoidanceStrength), function(v)
        local val = tonumber(v)
        if val then S.AvoidanceStrength = val end
    end)

    SubTab:AddSection("Filter Management")
    local FilterLabel = SubTab:AddLabel("Active Blacklist: None")
    local MultiDrop
    MultiDrop = SubTab:AddMultiDropdown("Filter Items", currentPool, function(selected)
        S.ItemBlacklist = selected
        local list = {}
        for k, _ in pairs(selected) do table.insert(list, k) end
        FilterLabel:SetText(#list > 0 and "Active Blacklist: " .. table.concat(list, ", ") or "Active Blacklist: None")
    end)

    SubTab:AddButton("Scan World Items", function()
        local found = {}
        for _, f in pairs({"Drops", "Gems"}) do
            local c = workspace:FindFirstChild(f)
            if c then
                for _, i in pairs(c:GetChildren()) do
                    local id = i:GetAttribute("id") or i.Name
                    if not table.find(found, id) then table.insert(found, id) end
                end
            end
        end
        currentPool = found
        MultiDrop:UpdateList(found)
    end)

    -- TOMBOL RESET DIPISAH
    SubTab:AddButton("Reset Item Filters", function()
        S.ItemBlacklist = {}
        badItems = {} 
        FilterLabel:SetText("Active Blacklist: None")
        if MultiDrop and MultiDrop.Set then MultiDrop:Set({}) end
        Window:Notify("Items reset!", 2)
    end)

    SubTab:AddButton("Reset Door Memory", function()
        lockedDoors = {}
        Window:Notify("Doors memory cleared!", 2)
    end)

    SubTab:AddSection("Status Dashboard")
    local StatusLabel = SubTab:AddLabel("Status: Idle")
    local TargetLabel = SubTab:AddLabel("Target: None")

    -- [[ 4. GRAVITY BYPASS ]] --
    task.spawn(function()
        while task.wait() do
            if S.Enabled then
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
                if S.Enabled then
                    local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
                    local target = GetNearestItem()
                    
                    if Hitbox and target then
                        local tName = IM.GetName(target:GetAttribute("id") or target.Name) or "Item"
                        TargetLabel:SetText("Target: " .. tName)
                        
                        local sx, sy = math.floor(Hitbox.Position.X/4.5+0.5), math.floor(Hitbox.Position.Y/4.5+0.5)
                        local tx, ty = math.floor(target:GetPivot().Position.X/4.5+0.5), math.floor(target:GetPivot().Position.Y/4.5+0.5)

                        local path = findSmartPath(sx, sy, tx, ty)
                        if path then
                            for i, point in ipairs(path) do
                                if not S.Enabled then break end
                                StatusLabel:SetText("Status: Walking (" .. i .. "/" .. #path .. ")")
                                Hitbox.CFrame = CFrame.new(point.X, point.Y, Hitbox.Position.Z)
                                movementModule.Position = Hitbox.Position
                                task.wait(S.StepDelay)

                                -- Deteksi Stuck lebih ketat (dist > 2)
                                local char = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                                if char then
                                    local dist = (Vector2.new(char.Position.X, char.Position.Y) - Vector2.new(point.X, point.Y)).Magnitude
                                    if dist > 2 then
                                        lockedDoors[math.floor(point.X/4.5+0.5) .. "," .. math.floor(point.Y/4.5+0.5)] = true
                                        break
                                    end
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
            task.wait(0.2)
        end
    end)
end
