return function(SubTab, Window, myToken)
    -- [[ LOCALIZED GLOBALS FOR PERFORMANCE ]] --
    local v3new, cfnew, taskwait = Vector3.new, CFrame.new, task.wait
    local mfloor, mabs, msort = math.floor, math.abs, table.sort
    local insert, remove, unpack = table.insert, table.remove, table.unpack

    -- [[ 1. SETUP & CONFIG ]] --
    local LP = game:GetService("Players").LocalPlayer
    local WorldTiles = require(game.ReplicatedStorage.WorldTiles)
    local movementModule = require(LP.PlayerScripts.PlayerMovement)
    local IM = require(game:GetService("ReplicatedStorage").Managers.ItemsManager)

    local Settings = getgenv().SayzSettings.AutoCollect
    local LIMIT = { MIN_X = 0, MAX_X = 100, MIN_Y = 6, MAX_Y = 60 }
    
    local doorDatabase, lockedDoors, badItems, currentPool = {}, {}, {}, {}

    -- [[ 2. HELPER FUNCTIONS ]] --

    local function getHeuristic(x1, y1, x2, y2)
        return mabs(x1 - x2) + mabs(y1 - y2)
    end

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

    local function isWalkable(gx, gy)
        if gx < LIMIT.MIN_X or gx > LIMIT.MAX_X or gy < LIMIT.MIN_Y or gy > LIMIT.MAX_Y then return false, false end
        if lockedDoors[gx .. "," .. gy] then return false, false end 

        local hasBlacklist = false
        local folders = {"Drops", (getgenv().TakeGems and "Gems" or nil)}
        for _, f in pairs(folders) do
            local container = workspace:FindFirstChild(f)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    local pos = item:GetPivot().Position
                    if mfloor(pos.X / 4.5 + 0.5) == gx and mfloor(pos.Y / 4.5 + 0.5) == gy then
                        if getgenv().ItemBlacklist[item:GetAttribute("id") or item.Name] then
                            hasBlacklist = true; break
                        end
                    end
                end
            end
        end

        if WorldTiles[gx] and WorldTiles[gx][gy] then
            local l1 = WorldTiles[gx][gy][1]
            local itemName = (type(l1) == "table") and l1[1] or l1
            if itemName then
                local n = string.lower(tostring(itemName))
                if string.find(n, "door") or string.find(n, "frame") then return true, hasBlacklist end
                return false, false 
            end
        end
        return true, hasBlacklist
    end

    local function findSmartPath(startX, startY, targetX, targetY)
        local queue = {{x = startX, y = startY, path = {}, cost = 0, priority = 0}}
        local visited = {[startX .. "," .. startY] = 0}
        local directions = {{x = 1, y = 0}, {x = -1, y = 0}, {x = 0, y = 1}, {x = 0, y = -1}}
        
        while #queue > 0 do
            if _G.LatestRunToken ~= myToken then break end
            msort(queue, function(a, b) return a.priority < b.priority end)
            local current = remove(queue, 1)

            if current.x == targetX and current.y == targetY then return current.path end

            for _, d in ipairs(directions) do
                local nx, ny = current.x + d.x, current.y + d.y
                local walkable, isBlacklisted = isWalkable(nx, ny)

                if walkable then
                    local moveCost = isBlacklisted and getgenv().AvoidanceStrength or 1
                    local newTotalCost = current.cost + moveCost

                    if not visited[nx .. "," .. ny] or newTotalCost < visited[nx .. "," .. ny] then
                        visited[nx .. "," .. ny] = newTotalCost
                        local newPath = {unpack(current.path)}
                        insert(newPath, v3new(nx * 4.5, ny * 4.5, 0))
                        
                        insert(queue, {
                            x = nx, y = ny, path = newPath, cost = newTotalCost,
                            priority = newTotalCost + getHeuristic(nx, ny, targetX, targetY)
                        })
                    end
                end
            end
        end
        return nil
    end

    local function GetNearestItem()
        local target, minDist = nil, 250000 -- 500^2
        local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not root then return nil end

        local folders = {"Drops", (getgenv().TakeGems and "Gems" or nil)}
        for _, f in pairs(folders) do
            local c = workspace:FindFirstChild(f)
            if c then
                for _, item in pairs(c:GetChildren()) do
                    local id = item:GetAttribute("id") or item.Name
                    if not badItems[item] and not getgenv().ItemBlacklist[id] then
                        local mag = (root.Position - item:GetPivot().Position).sqrMagnitude
                        if mag < minDist then minDist = mag; target = item end
                    end
                end
            end
        end
        return target
    end

    -- [[ 3. UI INTEGRATION (CONFIG READY) ]] --
    SubTab:AddSection("Auto Collect Pro")
    getgenv().SayzUI_Handles["AC_Master"] = SubTab:AddToggle("Master Switch", getgenv().AutoCollect, function(v) 
        getgenv().AutoCollect = v; if v then InitDoorDatabase() end 
    end)
    getgenv().SayzUI_Handles["AC_Gems"] = SubTab:AddToggle("Take Gems", getgenv().TakeGems, function(v) getgenv().TakeGems = v end)

    SubTab:AddSection("Movement & Path")
    getgenv().SayzUI_Handles["AC_Speed"] = SubTab:AddSlider("Step Delay", 0.01, 0.2, getgenv().StepDelay, function(v) getgenv().StepDelay = v end, 2)
    getgenv().SayzUI_Handles["AC_Cost"] = SubTab:AddInput("Avoidance Cost", tostring(getgenv().AvoidanceStrength), function(v) getgenv().AvoidanceStrength = tonumber(v) or 50 end)

    SubTab:AddSection("Filters")
    local MultiDrop = SubTab:AddMultiDropdown("Blacklist Items", currentPool, function(s) getgenv().ItemBlacklist = s end)
    getgenv().SayzUI_Handles["AC_Filter"] = MultiDrop

    SubTab:AddButton("Refresh World Scan", function()
        local found = {}
        for _, f in pairs({"Drops", "Gems"}) do
            local c = workspace:FindFirstChild(f)
            if c then for _, i in pairs(c:GetChildren()) do
                local id = i:GetAttribute("id") or i.Name
                if not table.find(found, id) then insert(found, id) end
            end end
        end
        currentPool = found; MultiDrop:UpdateList(found)
        Window:Notify("Scanned " .. #found .. " items", 2, "ok")
    end)

    -- [[ 4. LOOPS ]] --
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            taskwait()
            if getgenv().AutoCollect then
                pcall(function()
                    movementModule.VelocityY = (movementModule.VelocityY < 0) and 0 or movementModule.VelocityY
                    movementModule.Grounded = true 
                end)
            end
        end
    end)

    task.spawn(function()
        while _G.LatestRunToken == myToken do
            if getgenv().AutoCollect then
                local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
                local target = GetNearestItem()
                if Hitbox and target then
                    local sx, sy = mfloor(Hitbox.Position.X/4.5+0.5), mfloor(Hitbox.Position.Y/4.5+0.5)
                    local tx, ty = mfloor(target:GetPivot().Position.X/4.5+0.5), mfloor(target:GetPivot().Position.Y/4.5+0.5)
                    local path = findSmartPath(sx, sy, tx, ty)
                    if path then
                        for _, point in ipairs(path) do
                            if not getgenv().AutoCollect or _G.LatestRunToken ~= myToken then break end
                            Hitbox.CFrame = cfnew(point.X, point.Y, Hitbox.Position.Z)
                            movementModule.Position = Hitbox.Position
                            taskwait(getgenv().StepDelay)
                            -- Stuck detection
                            if (v3new(LP.Character.HumanoidRootPart.Position.X, LP.Character.HumanoidRootPart.Position.Y, 0) - v3new(point.X, point.Y, 0)).Magnitude > 5 then
                                lockedDoors[mfloor(point.X/4.5+0.5)..","..mfloor(point.Y/4.5+0.5)] = true; break
                            end
                        end
                    else badItems[target] = true end
                end
            end
            taskwait(0.1)
        end
    end)
end
