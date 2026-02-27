return function(SubTab, Window, myToken)
    -- ========================================
    -- [0] CONFIG-READY SETTINGS (Sync dengan Main.lua)
    -- ========================================
    local Settings = getgenv().SayzSettings.AutoCollect

    -- Variabel Internal Lokal
    local lockedDoors = {}
    local badItems = {}
    local currentPool = {}
    local doorDatabase = {}

    -- [[ 1. SETUP & VARIABLES ]] --
    local LP = game:GetService("Players").LocalPlayer
    local WorldTiles = require(game.ReplicatedStorage.WorldTiles)
    local movementModule = require(LP.PlayerScripts.PlayerMovement)
    local IM = require(game:GetService("ReplicatedStorage").Managers.ItemsManager)

    -- Limit World
    local LIMIT = { MIN_X = 0, MAX_X = 100, MIN_Y = 6, MAX_Y = 60 }

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
        if Settings.TakeGems then table.insert(folders, "Gems") end
        for _, folderName in pairs(folders) do
            local container = workspace:FindFirstChild(folderName)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    local itPos = item:GetPivot().Position
                    local itX = math.floor(itPos.X / 4.5 + 0.5)
                    local itY = math.floor(itPos.Y / 4.5 + 0.5)
                    
                    if itX == gx and itY == gy then
                        local id = item:GetAttribute("id") or item.Name
                        if Settings.ItemBlacklist[id] then 
                            return true 
                        end
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
        
        if lockedDoors[gx .. "," .. gy] then 
            return false, false 
        end 

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

    local function getDistance(x1, y1, x2, y2)
        return math.abs(x1 - x2) + math.abs(y1 - y2)
    end

    local function findSmartPath(startX, startY, targetX, targetY)
        local queue = {{x = startX, y = startY, path = {}, cost = 0, priority = 0}}
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

            table.sort(queue, function(a, b) return a.priority < b.priority end)
            local current = table.remove(queue, 1)

            if current.x == targetX and current.y == targetY then 
                return current.path 
            end

            for _, d in ipairs(directions) do
                local nx, ny = current.x + d.x, current.y + d.y
                local walkable, isBlacklisted = isWalkable(nx, ny)

                if walkable then
                    local moveCost = isBlacklisted and Settings.AvoidanceStrength or 1
                    local newTotalCost = current.cost + moveCost

                    if not visited[nx .. "," .. ny] or newTotalCost < visited[nx .. "," .. ny] then
                        visited[nx .. "," .. ny] = newTotalCost
                        local newPath = {unpack(current.path)}
                        table.insert(newPath, Vector3.new(nx * 4.5, ny * 4.5, 0))
                        
                        local priority = newTotalCost + getDistance(nx, ny, targetX, targetY)
                        
                        table.insert(queue, {
                            x = nx, 
                            y = ny, 
                            path = newPath, 
                            cost = newTotalCost,
                            priority = priority
                        })
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
        if Settings.TakeGems then table.insert(folders, "Gems") end

        for _, folder in pairs(folders) do
            local container = workspace:FindFirstChild(folder)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    local id = item:GetAttribute("id") or item.Name
                    if not badItems[item] and not Settings.ItemBlacklist[id] then
                        local d = (root.Position - item:GetPivot().Position).Magnitude
                        if d < dist then 
                            dist = d
                            target = item 
                        end
                    end
                end
            end
        end
        return target
    end

    -- [[ 3. UI ELEMENTS ]] --
    SubTab:AddSection("Auto Collect Master")
    
    getgenv().SayzUI_Handles["AC_Toggle"] = SubTab:AddToggle("Enable Auto Collect", Settings.Enabled, function(state)
        Settings.Enabled = state
        if state then InitDoorDatabase() end
    end)

    getgenv().SayzUI_Handles["AC_Gems"] = SubTab:AddToggle("Collect Gems", Settings.TakeGems, function(state)
        Settings.TakeGems = state
    end)

    SubTab:AddSection("Path & Speed Settings")
    
    getgenv().SayzUI_Handles["AC_Speed"] = SubTab:AddSlider("Movement Speed", 0.01, 1.0, Settings.StepDelay, function(val)
        Settings.StepDelay = val
    end, 2)

    getgenv().SayzUI_Handles["AC_Avoidance"] = SubTab:AddInput("Avoidance Strength", tostring(Settings.AvoidanceStrength), function(v)
        local val = tonumber(v)
        if val then Settings.AvoidanceStrength = val end
    end)

    SubTab:AddSection("Filter Management")
    local FilterLabel = SubTab:AddLabel("Active Blacklist: None")

    local MultiDrop
    MultiDrop = SubTab:AddMultiDropdown("Filter Items", currentPool, function(selected)
        Settings.ItemBlacklist = selected
        local count = 0
        for _ in pairs(selected) do count = count + 1 end
        FilterLabel:SetText(count > 0 and "Active Blacklist: " .. count .. " items" or "Active Blacklist: None")
    end)
    getgenv().SayzUI_Handles["AC_Filter"] = MultiDrop

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
        Window:Notify("Found " .. #found .. " item types.", 2)
    end)

    SubTab:AddButton("Reset All Filters", function()
        Settings.ItemBlacklist = {}
        badItems = {}
        FilterLabel:SetText("Active Blacklist: None")
        if MultiDrop and MultiDrop.Set then MultiDrop:Set({}) end
        Window:Notify("Filters Reset!", 2)
    end)

    SubTab:AddSection("Status Dashboard")
    local StatusLabel = SubTab:AddLabel("Status: Idle")
    local TargetLabel = SubTab:AddLabel("Target: None")

    -- [[ 4. GRAVITY BYPASS ]] --
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait()
            if Settings.Enabled then
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
        while _G.LatestRunToken == myToken do
            pcall(function()
                if Settings.Enabled then
                    local char = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                    local target = GetNearestItem()
                    
                    if char and target then
                        local tName = IM.GetName(target:GetAttribute("id") or target.Name) or "Item"
                        TargetLabel:SetText("Target: " .. tName)
                        
                        local sx, sy = math.floor(char.Position.X/4.5+0.5), math.floor(char.Position.Y/4.5+0.5)
                        local tx, ty = math.floor(target:GetPivot().Position.X/4.5+0.5), math.floor(target:GetPivot().Position.Y/4.5+0.5)

                        local path = findSmartPath(sx, sy, tx, ty)
                        if path then
                            for i, point in ipairs(path) do
                                if _G.LatestRunToken ~= myToken or not Settings.Enabled then break end
                                
                                -- FIX ARAH HADAP (ROTATION)
                                local direction = (point.X > char.Position.X) and 0 or math.pi
                                char.CFrame = CFrame.new(point.X, point.Y, char.Position.Z) * CFrame.Angles(0, direction, 0)
                                
                                StatusLabel:SetText("Status: Walking (" .. i .. "/" .. #path .. ")")
                                movementModule.Position = char.Position
                                task.wait(Settings.StepDelay)

                                -- Deteksi Stuck
                                local dist = (Vector2.new(char.Position.X, char.Position.Y) - Vector2.new(point.X, point.Y)).Magnitude
                                if dist > 5 then
                                    local px, py = math.floor(point.X/4.5+0.5), math.floor(point.Y/4.5+0.5)
                                    lockedDoors[px .. "," .. py] = true
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
            task.wait(0.1)
        end
    end)
end
