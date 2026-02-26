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
    local blacklistCoords = {}

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

    local function UpdateBlacklistCache()
        blacklistCoords = {}
        for _, folder in pairs({"Drops", "Gems"}) do
            local c = workspace:FindFirstChild(folder)
            if c then
                for _, item in pairs(c:GetChildren()) do
                    local id = item:GetAttribute("id") or item.Name
                    if getgenv().ItemBlacklist[id] then
                        local ix = math.floor(item:GetPivot().Position.X/4.5+0.5)
                        local iy = math.floor(item:GetPivot().Position.Y/4.5+0.5)
                        blacklistCoords[ix .. "," .. iy] = true
                    end
                end
            end
        end
    end

    local function isWalkable(gx, gy, currentY)
        if gx < LIMIT.MIN_X or gx > LIMIT.MAX_X or gy < LIMIT.MIN_Y or gy > LIMIT.MAX_Y then return false, false end
        if lockedDoors[gx .. "," .. gy] then return false, false end 

        local walkable = true
        if WorldTiles[gx] and WorldTiles[gx][gy] then
            local l1 = WorldTiles[gx][gy][1]
            local itemName = (type(l1) == "table") and l1[1] or l1
            if itemName then
                local n = string.lower(tostring(itemName))
                if not (string.find(n, "door") or string.find(n, "frame")) then
                    walkable = false 
                end
            end
        end
        return walkable, (blacklistCoords[gx .. "," .. gy] or false)
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
                local canPass, isBlacklisted = isWalkable(nx, ny, current.y)
                
                if canPass then
                    local moveCost = isBlacklisted and 100 or 1
                    local newCost = current.cost + moveCost
                    if not visited[nx .. "," .. ny] or newCost < visited[nx .. "," .. ny] then
                        visited[nx .. "," .. ny] = newCost
                        local newPath = {unpack(current.path)}
                        table.insert(newPath, Vector3.new(nx * 4.5, ny * 4.5, 0))
                        table.insert(queue, {x = nx, y = ny, path = newPath, cost = newCost})
                    end
                end
            end
        end
        return nil
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
    SubTab:AddSection("CONTROL PANEL")
    SubTab:AddToggle("Enable Auto Collect", getgenv().AutoCollect, function(s) 
        getgenv().AutoCollect = s 
        if s then InitDoorDatabase() end
    end)
    SubTab:AddToggle("Take Gems", getgenv().TakeGems, function(s) getgenv().TakeGems = s end)
    
    -- Input Teks untuk Delay
    SubTab:AddInput("Step Delay", tostring(getgenv().StepDelay), function(v)
        getgenv().StepDelay = tonumber(v) or 0.05
    end)

    -- ITEM FILTER (Sekarang di atas Live Statistics)
    SubTab:AddSection("ITEM FILTER")
    local MultiDrop
    MultiDrop = SubTab:AddMultiDropdown("Blacklist Items", {}, function(selected)
        getgenv().ItemBlacklist = selected
        UpdateBlacklistCache()
    end)

    SubTab:AddButton("Scan World Items", function()
        local items = {}
        local folders = {"Drops"}
        if getgenv().TakeGems then table.insert(folders, "Gems") end
        for _, f in pairs(folders) do
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
        MultiDrop:ClearAll() -- Fungsi ini harus ada di Library.lua
        UpdateBlacklistCache()
        Window:Notify("Filters & Blacklist Reset!", 2)
    end)

    -- LIVE STATISTICS
    SubTab:AddSection("LIVE STATISTICS")
    local ItemLabel = SubTab:AddLabel("Items on Map: 0")
    local TargetLabel = SubTab:AddLabel("Targeting: None")
    local StatusLabel = SubTab:AddLabel("Status: Idle")

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
            local success, err = pcall(function()
                if getgenv().AutoCollect then
                    local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
                    
                    if Hitbox then
                        -- Scan Target
                        local target, dist = nil, 500
                        local folders = {"Drops"}
                        if getgenv().TakeGems then table.insert(folders, "Gems") end
                        
                        local mapCount = 0
                        for _, f in pairs(folders) do
                            local c = workspace:FindFirstChild(f)
                            if c then 
                                mapCount = mapCount + #c:GetChildren()
                                for _, item in pairs(c:GetChildren()) do
                                    local id = item:GetAttribute("id") or item.Name
                                    if not getgenv().ItemBlacklist[id] and not badItems[item] then
                                        local d = (Hitbox.Position - item:GetPivot().Position).Magnitude
                                        if d < dist then dist = d; target = item end
                                    end
                                end
                            end
                        end
                        ItemLabel:SetText("Items on Map: " .. mapCount)

                        if target then
                            TargetLabel:SetText("Target: " .. (target:GetAttribute("id") or target.Name))
                            StatusLabel:SetText("Status: Pathfinding...")
                            
                            local sx, sy = math.floor(Hitbox.Position.X/4.5+0.5), math.floor(Hitbox.Position.Y/4.5+0.5)
                            local tx, ty = math.floor(target:GetPivot().Position.X/4.5+0.5), math.floor(target:GetPivot().Position.Y/4.5+0.5)

                            local path = findSmartPath(sx, sy, tx, ty)
                            if path then
                                for _, point in ipairs(path) do
                                    if not getgenv().AutoCollect then break end
                                    Hitbox.CFrame = CFrame.new(point.X, point.Y, Hitbox.Position.Z)
                                    movementModule.Position = Hitbox.Position
                                    task.wait(getgenv().StepDelay)

                                    -- Deteksi Stuck
                                    local char = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                                    if char and (Vector2.new(char.Position.X, char.Position.Y) - Vector2.new(point.X, point.Y)).Magnitude > 4.5 then
                                        scanAndLockNearbyDoor(math.floor(point.X/4.5+0.5), math.floor(point.Y/4.5+0.5))
                                        break 
                                    end
                                end
                            else
                                badItems[target] = true
                            end
                        else
                            TargetLabel:SetText("Targeting: None")
                            StatusLabel:SetText("Status: Scanning...")
                        end
                    end
                else
                    StatusLabel:SetText("Status: Paused")
                end
            end)
            task.wait(0.2)
        end
    end)
end
