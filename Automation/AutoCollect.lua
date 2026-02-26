return function(SubTab, Window)
    local LP = game:GetService("Players").LocalPlayer
    local WorldTiles = require(game.ReplicatedStorage.WorldTiles)
    local movementModule = require(LP.PlayerScripts.PlayerMovement)
    local IM = require(game:GetService("ReplicatedStorage").Managers.ItemsManager)

    getgenv().AutoCollect = getgenv().AutoCollect or false
    getgenv().StepDelay = getgenv().StepDelay or 0.05 
    getgenv().ItemBlacklist = getgenv().ItemBlacklist or {} 

    local LIMIT = { MIN_X = 0, MAX_X = 100, MIN_Y = 6, MAX_Y = 60 }
    local unreachableItems = {} 
    local blacklistCoords = {}

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

    local function isWalkable(gx, gy)
        if gx < LIMIT.MIN_X or gx > LIMIT.MAX_X or gy < LIMIT.MIN_Y or gy > LIMIT.MAX_Y then return false, false end
        local walkable = true
        if WorldTiles[gx] and WorldTiles[gx][gy] then
            local l1 = WorldTiles[gx][gy][1]
            local itemName = (type(l1) == "table") and l1[1] or l1
            if itemName then
                local n = string.lower(tostring(itemName))
                if not (string.find(n, "door") or string.find(n, "frame")) then walkable = false end
            end
        end
        return walkable, (blacklistCoords[gx .. "," .. gy] or false)
    end

    local function findSmartPath(startX, startY, targetX, targetY)
        local queue = {{x = startX, y = startY, path = {}, cost = 0}}
        local visited = {[startX .. "," .. startY] = 0}
        while #queue > 0 do
            table.sort(queue, function(a, b) return a.cost < b.cost end)
            local current = table.remove(queue, 1)
            if current.x == targetX and current.y == targetY then return current.path end
            if #current.path > 100 then continue end

            for _, d in ipairs({{x=1,y=0},{x=-1,y=0},{x=0,y=1},{x=0,y=-1}}) do
                local nx, ny = current.x + d.x, current.y + d.y
                local canPass, isBlocked = isWalkable(nx, ny)
                if canPass then
                    local moveCost = isBlocked and 100 or 1
                    local newCost = current.cost + moveCost
                    if not visited[nx..","..ny] or newCost < visited[nx..","..ny] then
                        visited[nx..","..ny] = newCost
                        local newPath = {unpack(current.path)}
                        table.insert(newPath, Vector3.new(nx * 4.5, ny * 4.5, 0))
                        table.insert(queue, {x = nx, y = ny, path = newPath, cost = newCost})
                    end
                end
            end
        end
        return nil
    end

    -- UI
    SubTab:AddSection("CONTROL PANEL")
    SubTab:AddToggle("Enable Auto Collect", getgenv().AutoCollect, function(s) getgenv().AutoCollect = s end)
    SubTab:AddInput("Step Delay", tostring(getgenv().StepDelay), function(v) getgenv().StepDelay = tonumber(v) or 0.05 end)

    SubTab:AddSection("LIVE STATISTICS")
    local ItemLabel = SubTab:AddLabel("Items on Map: 0")
    local BadLabel = SubTab:AddLabel("Unreachable: 0")
    local TargetLabel = SubTab:AddLabel("Targeting: None")
    local StatusLabel = SubTab:AddLabel("Status: Idle")

    SubTab:AddSection("ITEM FILTER")
    local MultiDrop = SubTab:AddMultiDropdown("Blacklist Items", {"dirt"}, function(selected)
        getgenv().ItemBlacklist = selected
        UpdateBlacklistCache()
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

    SubTab:AddButton("Reset Memory", function() unreachableItems = {} end)

    -- LOOP
    task.spawn(function()
        while task.wait(0.2) do
            if getgenv().AutoCollect then
                local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
                if Hitbox then
                    local target, dist = nil, 500
                    local mapCount = 0
                    for _, folder in pairs({"Drops", "Gems"}) do
                        local c = workspace:FindFirstChild(folder)
                        if c then 
                            mapCount = mapCount + #c:GetChildren()
                            for _, item in pairs(c:GetChildren()) do
                                local id = item:GetAttribute("id") or item.Name
                                if not getgenv().ItemBlacklist[id] and not unreachableItems[item] then
                                    local d = (Hitbox.Position - item:GetPivot().Position).Magnitude
                                    if d < dist then dist = d; target = item end
                                end
                            end
                        end
                    end
                    ItemLabel:SetText("Items on Map: " .. mapCount)
                    
                    if target then
                        TargetLabel:SetText("Targeting: " .. (target:GetAttribute("id") or target.Name))
                        UpdateBlacklistCache()
                        local path = findSmartPath(math.floor(Hitbox.Position.X/4.5+0.5), math.floor(Hitbox.Position.Y/4.5+0.5), math.floor(target:GetPivot().Position.X/4.5+0.5), math.floor(target:GetPivot().Position.Y/4.5+0.5))
                        if path then
                            StatusLabel:SetText("Status: Moving...")
                            for _, p in ipairs(path) do
                                if not getgenv().AutoCollect then break end
                                Hitbox.CFrame = CFrame.new(p.X, p.Y, Hitbox.Position.Z)
                                movementModule.Position = Hitbox.Position
                                task.wait(getgenv().StepDelay)
                            end
                        else
                            unreachableItems[target] = true
                        end
                    end
                end
            end
        end
    end)
end
