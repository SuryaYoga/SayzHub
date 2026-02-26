return function(SubTab, Window)
    -- [[ 1. SETUP & SERVICES ]] --
    local LP = game:GetService("Players").LocalPlayer
    local WorldTiles = require(game.ReplicatedStorage.WorldTiles)
    local movementModule = require(LP.PlayerScripts.PlayerMovement)
    local IM = require(game:GetService("ReplicatedStorage").Managers.ItemsManager)

    getgenv().AutoCollect = getgenv().AutoCollect or false
    getgenv().StepDelay = getgenv().StepDelay or 0.05 
    getgenv().ItemBlacklist = getgenv().ItemBlacklist or {} 

    local LIMIT = { MIN_X = 0, MAX_X = 100, MIN_Y = 6, MAX_Y = 60 }
    local doorDatabase = {} 
    local lockedDoors = {} 
    local unreachableItems = {} 
    local blacklistCoords = {}

    -- [[ 2. LOGIC FUNCTIONS ]] --

    local function UpdateBlacklistCache()
        blacklistCoords = {}
        for _, folder in pairs({"Drops", "Gems"}) do
            local container = workspace:FindFirstChild(folder)
            if container then
                for _, item in pairs(container:GetChildren()) do
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

    local function isWalkable(gx, gy)
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
        
        local hasBlacklist = blacklistCoords[gx .. "," .. gy] or false
        return walkable, hasBlacklist
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
                local canPass, isBlocked = isWalkable(nx, ny)
                
                if canPass then
                    local moveCost = isBlocked and 100 or 1
                    local newCost = current.cost + moveCost
                    local key = nx .. "," .. ny
                    
                    if not visited[key] or newCost < visited[key] then
                        visited[key] = newCost
                        local newPath = {unpack(current.path)}
                        table.insert(newPath, Vector3.new(nx * 4.5, ny * 4.5, 0))
                        table.insert(queue, {x = nx, y = ny, path = newPath, cost = newCost})
                    end
                end
            end
        end
        return nil
    end

    -- [[ 3. UI SETUP ]] --
    
    SubTab:AddSection("CONTROL PANEL")
    SubTab:AddToggle("Enable Auto Collect", getgenv().AutoCollect, function(s) 
        getgenv().AutoCollect = s 
        if s then UpdateBlacklistCache() end
    end)

    SubTab:AddInput("Step Delay", tostring(getgenv().StepDelay), function(v)
        local n = tonumber(v)
        if n then getgenv().StepDelay = math.clamp(n, 0.01, 1) end
    end)

    -- LIVE STATISTICS SECTION
    SubTab:AddSection("LIVE STATISTICS")
    local ItemLabel = SubTab:AddLabel("Items on Map: 0")
    local BadLabel = SubTab:AddLabel("Unreachable: 0")
    local TargetLabel = SubTab:AddLabel("Targeting: None")
    local StatusLabel = SubTab:AddLabel("Status: Idle")

    SubTab:AddSection("ITEM FILTER")
    local FilterLabel = SubTab:AddLabel("🚫 Blacklist: 0 items")

    local MultiDrop = SubTab:AddMultiDropdown("Select Blacklist Items", {"dirt"}, function(selected)
        getgenv().ItemBlacklist = selected
        local c = 0; for _ in pairs(selected) do c = c + 1 end
        FilterLabel:SetText("🚫 Blacklist: " .. c .. " items")
        UpdateBlacklistCache()
    end)

    SubTab:AddButton("Scan World Items", function()
        local items = {}
        for _, folder in pairs({"Drops", "Gems"}) do
            local c = workspace:FindFirstChild(folder)
            if c then
                for _, item in pairs(c:GetChildren()) do
                    local id = item:GetAttribute("id") or item.Name
                    if not table.find(items, id) then table.insert(items, id) end
                end
            end
        end
        MultiDrop:UpdateList(items)
        Window:Notify("Scanned " .. #items .. " items", 2)
    end)

    SubTab:AddButton("Reset All (Clear Unreachable)", function()
        unreachableItems = {}
        lockedDoors = {}
        Window:Notify("Bot memory reset!", 2)
    end)

    -- [[ 4. MAIN LOOP ]] --
    task.spawn(function()
        while true do
            if getgenv().AutoCollect then
                pcall(function()
                    local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                    local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
                    
                    if root and Hitbox then
                        -- Statistik: Hitung item di map & unreachable
                        local mapItemCount = 0
                        local unreachCount = 0
                        for _, folder in pairs({"Drops", "Gems"}) do
                            local c = workspace:FindFirstChild(folder)
                            if c then 
                                mapItemCount = mapItemCount + #c:GetChildren() 
                            end
                        end
                        for _ in pairs(unreachableItems) do unreachCount = unreachCount + 1 end
                        
                        ItemLabel:SetText("Items on Map: " .. mapItemCount)
                        BadLabel:SetText("Unreachable: " .. unreachCount)

                        -- Cari Target
                        local target, dist = nil, 500
                        for _, folder in pairs({"Drops", "Gems"}) do
                            local c = workspace:FindFirstChild(folder)
                            if c then
                                for _, item in pairs(c:GetChildren()) do
                                    local id = item:GetAttribute("id") or item.Name
                                    if not getgenv().ItemBlacklist[id] and not unreachableItems[item] then
                                        local d = (root.Position - item:GetPivot().Position).Magnitude
                                        if d < dist then dist = d; target = item end
                                    end
                                end
                            end
                        end

                        if target then
                            local itemName = IM.GetName(target:GetAttribute("id") or target.Name) or "Unknown Item"
                            TargetLabel:SetText("Targeting: " .. itemName)
                            StatusLabel:SetText("Status: Moving to target")

                            UpdateBlacklistCache()
                            local sx, sy = math.floor(Hitbox.Position.X/4.5+0.5), math.floor(Hitbox.Position.Y/4.5+0.5)
                            local tx, ty = math.floor(target:GetPivot().Position.X/4.5+0.5), math.floor(target:GetPivot().Position.Y/4.5+0.5)
                            
                            local path = findSmartPath(sx, sy, tx, ty)
                            if path then
                                for _, p in ipairs(path) do
                                    if not getgenv().AutoCollect then break end
                                    Hitbox.CFrame = CFrame.new(p.X, p.Y, Hitbox.Position.Z)
                                    movementModule.Position = Hitbox.Position
                                    task.wait(getgenv().StepDelay)
                                end
                            else
                                unreachableItems[target] = true
                                TargetLabel:SetText("Targeting: None")
                            end
                        else
                            TargetLabel:SetText("Targeting: None")
                            StatusLabel:SetText("Status: Waiting for items...")
                        end
                    end
                end)
            else
                StatusLabel:SetText("Status: Bot Disabled")
                TargetLabel:SetText("Targeting: None")
            end
            task.wait(0.2)
        end
    end)
end
