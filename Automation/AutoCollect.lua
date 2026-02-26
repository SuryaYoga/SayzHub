return function(SubTab, Window)
    -- [[ 1. SETUP & VARIABLES ]] --
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
    local badItems = {} 
    local currentPool = {"dirt"} -- Initial isi dropdown sebelum scan

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

        for _, folder in pairs({"Drops", "Gems"}) do
            local container = workspace:FindFirstChild(folder)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    local itemId = item:GetAttribute("id") or item.Name
                    -- Filter badItems (stuck) dan ItemBlacklist (user selected)
                    if not badItems[item] and not getgenv().ItemBlacklist[itemId] then
                        local d = (root.Position - item:GetPivot().Position).Magnitude
                        if d < dist then dist = d; target = item end
                    end
                end
            end
        end
        return target
    end

    -- Tambahkan fungsi pengecekan item di koordinat tertentu
local function getBlacklistItemAt(gx, gy)
    for _, folder in pairs({"Drops", "Gems"}) do
        local container = workspace:FindFirstChild(folder)
        if container then
            for _, item in pairs(container:GetChildren()) do
                local itX, itY = math.floor(item:GetPivot().Position.X/4.5+0.5), math.floor(item:GetPivot().Position.Y/4.5+0.5)
                if itX == gx and itY == gy then
                    local id = item:GetAttribute("id") or item.Name
                    if getgenv().ItemBlacklist[id] then
                        return true -- Ada item yang diblokir di sini
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

local function findSmartPath(startX, startY, targetX, targetY)
    -- Queue sekarang menyimpan 'priority' (seberapa bersih jalurnya)
    local queue = {{x = startX, y = startY, path = {}, cost = 0}}
    local visited = {[startX .. "," .. startY] = 0} -- Simpan cost terkecil ke tile ini
    local directions = {{x=1, y=0}, {x=-1, y=0}, {x=0, y=1}, {x=0, y=-1}}
    
    local bestPath = nil
    local minCost = math.huge

    local limit = 0
    while #queue > 0 do
        limit = limit + 1
        if limit > 5000 then break end 
        
        -- Urutkan queue berdasarkan cost terendah (Dijkstra-lite)
        table.sort(queue, function(a, b) return a.cost < b.cost end)
        local current = table.remove(queue, 1)

        if current.x == targetX and current.y == targetY then
            return current.path -- Jalur terbaik ditemukan
        end

        for _, d in ipairs(directions) do
            local nx, ny = current.x + d.x, current.y + d.y
            local walkable, isBlacklisted = isWalkable(nx, ny, current.y)
            
            if walkable then
                -- JIKA LEWAT ITEM BLACKLIST, KASIH BEBAN BERAT (Cost + 100)
                -- JIKA JALAN BERSIH, BEBAN RINGAN (Cost + 1)
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

    -- INPUT DELAY (MENGGUNAKAN ADDINPUT)
    SubTab:AddInput("Step Delay (Decimal)", tostring(getgenv().StepDelay), function(v)
        local val = tonumber(v)
        if val then
            if val < 0.01 then val = 0.01 end -- Safety limit
            getgenv().StepDelay = val
            Window:Notify("Speed set to: " .. val, 2)
        end
    end)

    SubTab:AddSection("Filter Management")
    local FilterLabel = SubTab:AddLabel("Active Blacklist: None")

SubTab:AddMultiDropdown("Add/Remove Blacklist", currentPool, function(selected)
    getgenv().ItemBlacklist = selected
    local items = {}
    for k, _ in pairs(selected) do table.insert(items, k) end
    
    if #items > 0 then
        FilterLabel:SetText("Active Blacklist: " .. table.concat(items, ", "))
    else
        FilterLabel:SetText("Active Blacklist: None")
    end
end)
    -- TOMBOL SCAN UNTUK MENGISI DROPDOWN
    SubTab:AddButton("Scan Items in World", function()
        local found = {}
        for _, folder in pairs({"Drops", "Gems"}) do
            local container = workspace:FindFirstChild(folder)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    local id = item:GetAttribute("id") or item.Name
                    if not table.find(found, id) then
                        table.insert(found, id)
                    end
                end
            end
        end
        
        if #found > 0 then
            currentPool = found
            MultiDrop:UpdateList(found) -- Update list di dropdown secara realtime
            Window:Notify("Scan complete! " .. #found .. " items found.", 2)
        else
            Window:Notify("No items found on ground.", 2)
        end
    end)

    SubTab:AddButton("Reset All Filters", function()
        getgenv().ItemBlacklist = {}
        badItems = {}
        lockedDoors = {}
        FilterLabel:SetText("🚫 Blacklist: None")
        Window:Notify("Filters cleared!", 2)
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

    -- [[ 5. MAIN LOOP ]] --
    InitDoorDatabase()
    task.spawn(function()
        while true do
            pcall(function()
                if getgenv().AutoCollect then
                    local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
                    local target = GetNearestItem()
                    
                    if Hitbox and target then
                        StatusLabel:SetText("Status: Collecting " .. (IM.GetName(target:GetAttribute("id") or target.Name) or "Item"))
                        local sx, sy = math.floor(Hitbox.Position.X/4.5+0.5), math.floor(Hitbox.Position.Y/4.5+0.5)
                        local tx, ty = math.floor(target:GetPivot().Position.X/4.5+0.5), math.floor(target:GetPivot().Position.Y/4.5+0.5)

                        -- Di dalam loop task.spawn utama
                        local path = findSmartPath(sx, sy, tx, ty)
                        if path then
                            -- Cek apakah di jalur ini ada blacklist yang terpaksa dilewati
                            local terpaksa = false
                            for _, p in ipairs(path) do
                                if getBlacklistItemAt(math.floor(p.X/4.5+0.5), math.floor(p.Y/4.5+0.5)) then
                                    terpaksa = true; break
                                end
                            end
                        
                            if terpaksa then
                                StatusLabel:SetText("Status: Pathing (Forced through blacklist)")
                            else
                                StatusLabel:SetText("Status: Pathing (Safe Route)")
                            end

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
                        StatusLabel:SetText("Status: Scanning for items...")
                    end
                else
                    StatusLabel:SetText("Status: Paused")
                end
            end)
            task.wait(0.2)
        end
    end)
end

