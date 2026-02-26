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

    -- FUNGSI BARU: Bikin peta koordinat blacklist biar gak berat (ANTI CRASH)
    local function getBlacklistMap()
        local map = {}
        for _, folderName in pairs({"Drops", "Gems"}) do
            local container = workspace:FindFirstChild(folderName)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    local id = item:GetAttribute("id") or item.Name
                    if getgenv().ItemBlacklist[id] then
                        local pos = item:GetPivot().Position
                        local gx, gy = math.floor(pos.X/4.5+0.5), math.floor(pos.Y/4.5+0.5)
                        map[gx .. "," .. gy] = true
                    end
                end
            end
        end
        return map
    end

    local function isWalkable(gx, gy, blacklistMap)
        if gx < LIMIT.MIN_X or gx > LIMIT.MAX_X or gy < LIMIT.MIN_Y or gy > LIMIT.MAX_Y then return false, false end
        if lockedDoors[gx .. "," .. gy] then return false, false end 

        local isBlacklisted = blacklistMap[gx .. "," .. gy] or false

        if WorldTiles[gx] and WorldTiles[gx][gy] then
            local l1 = WorldTiles[gx][gy][1]
            local itemName = (type(l1) == "table") and l1[1] or l1
            if itemName then
                local n = string.lower(tostring(itemName))
                if string.find(n, "door") or string.find(n, "frame") then 
                    return true, isBlacklisted 
                end
                return false, false 
            end
        end
        return true, isBlacklisted
    end

    local function findSmartPath(startX, startY, targetX, targetY, blacklistMap)
        local queue = {{x = startX, y = startY, path = {}, cost = 0}}
        local visited = {[startX .. "," .. startY] = 0}
        local directions = {{x=1, y=0}, {x=-1, y=0}, {x=0, y=1}, {x=0, y=-1}}
        
        local limit = 0
        while #queue > 0 do
            limit = limit + 1
            if limit > 2000 then break end -- Limit diperkecil agar tidak hang
            
            table.sort(queue, function(a, b) return a.cost < b.cost end)
            local current = table.remove(queue, 1)

            if current.x == targetX and current.y == targetY then return current.path end

            for _, d in ipairs(directions) do
                local nx, ny = current.x + d.x, current.y + d.y
                local walkable, isBlacklisted = isWalkable(nx, ny, blacklistMap)
                
                if walkable then
                    local moveCost = isBlacklisted and 100 or 1
                    local newTotalCost = current.cost + moveCost
                    
                    local key = nx .. "," .. ny
                    if not visited[key] or newTotalCost < visited[key] then
                        visited[key] = newTotalCost
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

    -- [[ 3. UI ELEMENTS ]] --
    -- (Bagian UI tetap sama seperti kode kamu sebelumnya)
    SubTab:AddSection("Auto Collect Master")
    SubTab:AddToggle("Enable Auto Collect", getgenv().AutoCollect, function(state)
        getgenv().AutoCollect = state
        if state then InitDoorDatabase() end
    end)
    SubTab:AddToggle("Collect Gems", getgenv().TakeGems, function(s) getgenv().TakeGems = s end)
    SubTab:AddInput("Step Delay", tostring(getgenv().StepDelay), function(v)
        getgenv().StepDelay = tonumber(v) or 0.05
    end)

    SubTab:AddSection("Filter Management")
    local FilterLabel = SubTab:AddLabel("Active Blacklist: None")
    local MultiDrop; MultiDrop = SubTab:AddMultiDropdown("Add/Remove Blacklist", currentPool, function(selected)
        getgenv().ItemBlacklist = selected
        local items = {} for k, _ in pairs(selected) do table.insert(items, k) end
        FilterLabel:SetText(#items > 0 and "Active Blacklist: " .. table.concat(items, ", ") or "Active Blacklist: None")
    end)

    SubTab:AddButton("Scan Items in World", function()
        local found = {}
        for _, f in pairs({"Drops", "Gems"}) do
            local c = workspace:FindFirstChild(f)
            if c then for _, i in pairs(c:GetChildren()) do
                local id = i:GetAttribute("id") or i.Name
                if not table.find(found, id) then table.insert(found, id) end
            end end
        end
        if #found > 0 then currentPool = found; MultiDrop:UpdateList(found) end
    end)

    SubTab:AddButton("Reset All Filters", function()
        getgenv().ItemBlacklist = {}; badItems = {}; lockedDoors = {}
        FilterLabel:SetText("Active Blacklist: None")
        if MultiDrop.ClearAll then MultiDrop:ClearAll() end
    end)

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

    -- [[ 5. MAIN LOOP - STABLE VERSION ]] --
    InitDoorDatabase()
    task.spawn(function()
        while true do
            if getgenv().AutoCollect then
                local success, err = pcall(function()
                    local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
                    local target = GetNearestItem()
                    
                    if Hitbox and target then
                        local targetName = IM.GetName(target:GetAttribute("id") or target.Name) or "Item"
                        local sx, sy = math.floor(Hitbox.Position.X/4.5+0.5), math.floor(Hitbox.Position.Y/4.5+0.5)
                        local tx, ty = math.floor(target:GetPivot().Position.X/4.5+0.5), math.floor(target:GetPivot().Position.Y/4.5+0.5)

                        -- Update peta blacklist satu kali sebelum cari jalur
                        local currentBlacklistMap = getBlacklistMap()
                        local path = findSmartPath(sx, sy, tx, ty, currentBlacklistMap)
                        
                        if path then
                            for _, point in ipairs(path) do
                                if not getgenv().AutoCollect then break end
                                
                                local px, py = math.floor(point.X/4.5+0.5), math.floor(point.Y/4.5+0.5)
                                local isTerpaksa = currentBlacklistMap[px .. "," .. py]
                                
                                StatusLabel:SetText("Status: " .. (isTerpaksa and "⚠️ Forced" or "✅ Safe") .. " -> " .. targetName)

                                Hitbox.CFrame = CFrame.new(point.X, point.Y, Hitbox.Position.Z)
                                movementModule.Position = Hitbox.Position
                                task.wait(getgenv().StepDelay)

                                -- Deteksi Stuck
                                local charPos = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") and LP.Character.HumanoidRootPart.Position
                                if charPos and (Vector2.new(charPos.X, charPos.Y) - Vector2.new(point.X, point.Y)).Magnitude > 4.5 then
                                    lockedDoors[px .. "," .. py] = true
                                    break 
                                end
                            end
                        else
                            badItems[target] = true
                        end
                    else
                        StatusLabel:SetText("Status: Scanning...")
                    end
                end)
                if not success then warn("AutoCollect Error: " .. tostring(err)) end
            else
                StatusLabel:SetText("Status: Paused")
            end
            task.wait(0.1)
        end
    end)
end
