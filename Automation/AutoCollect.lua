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

    local function GetNearestItem()
        local target, dist = nil, 500
        local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not root then return nil end

        -- Cek folder sesuai setting TakeGems
        local folders = {"Drops"}
        if getgenv().TakeGems then table.insert(folders, "Gems") end

        for _, folder in pairs(folders) do
            local container = workspace:FindFirstChild(folder)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    local id = item:GetAttribute("id") or item.Name
                    -- Filter Blacklist dimasukkan di sini
                    if not getgenv().ItemBlacklist[id] and not badItems[item] then
                        local d = (root.Position - item:GetPivot().Position).Magnitude
                        if d < dist then dist = d; target = item end
                    end
                end
            end
        end
        return target
    end

    local function isWalkable(gx, gy, currentY)
        if gx < LIMIT.MIN_X or gx > LIMIT.MAX_X or gy < LIMIT.MIN_Y or gy > LIMIT.MAX_Y then return false end
        if lockedDoors[gx .. "," .. gy] then return false end 

        if WorldTiles[gx] and WorldTiles[gx][gy] then
            local l1 = WorldTiles[gx][gy][1]
            local itemName = (type(l1) == "table") and l1[1] or l1
            if itemName then
                local n = string.lower(tostring(itemName))
                if string.find(n, "door") then return true end
                if string.find(n, "frame") then
                    if currentY and gy > currentY then return true end
                    return true 
                end
                return false 
            end
        end
        return true 
    end

    local function findSmartPath(startX, startY, targetX, targetY)
        local queue = {{x = startX, y = startY, path = {}}}
        local visited = {[startX .. "," .. startY] = true}
        local directions = {{x=1, y=0}, {x=-1, y=0}, {x=0, y=1}, {x=0, y=-1}}
        local limit = 0
        while #queue > 0 do
            limit = limit + 1
            if limit > 4000 then return nil end 
            local current = table.remove(queue, 1)
            if current.x == targetX and current.y == targetY then return current.path end
            for _, d in ipairs(directions) do
                local nx, ny = current.x + d.x, current.y + d.y
                if isWalkable(nx, ny, current.y) and not visited[nx .. "," .. ny] then
                    visited[nx .. "," .. ny] = true
                    local newPath = {unpack(current.path)}
                    table.insert(newPath, Vector3.new(nx * 4.5, ny * 4.5, 0))
                    table.insert(queue, {x = nx, y = ny, path = newPath})
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
    SubTab:AddToggle("Enable Auto Collect", getgenv().AutoCollect, function(state)
        getgenv().AutoCollect = state
        if state then InitDoorDatabase() end
    end)
    SubTab:AddToggle("Collect Gems", getgenv().TakeGems, function(s) getgenv().TakeGems = s end)
    
    SubTab:AddInput("Step Speed Delay", tostring(getgenv().StepDelay), function(val)
        getgenv().StepDelay = tonumber(val) or 0.05
    end)

    -- BAGIAN FILTER (Sesuai request: Nama Item muncul di Label)
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
            local show = table.concat(names, ", ", 1, math.min(#names, 3))
            if #names > 3 then show = show .. " (+" .. (#names-3) .. ")" end
            FilterLabel:SetText("🚫 Blacklist: " .. show)
        end
    end)

    SubTab:AddButton("Scan World Items", function()
        local items = {}
        for _, folder in pairs({"Drops", "Gems"}) do
            local c = workspace:FindFirstChild(folder)
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

    -- [[ 5. MAIN LOOP (PERSIS KODE AMAN KAMU) ]] --
    InitDoorDatabase()
    task.spawn(function()
        while true do
            local success, err = pcall(function()
                if getgenv().AutoCollect then
                    local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
                    local target = GetNearestItem()
                    
                    if Hitbox and target then
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
                                local charPos = LP.Character and LP.Character.HumanoidRootPart.Position
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
            task.wait(0.2) -- Jeda Main Loop tetap 0.2 sesuai kode aman kamu
        end
    end)
end
