return function(SubTab, Window)
    -- [[ 1. SETUP & VARIABLES ]] --
    local LP = game:GetService("Players").LocalPlayer
    local WorldTiles = require(game.ReplicatedStorage.WorldTiles)
    local movementModule = require(LP.PlayerScripts.PlayerMovement)
    local IM = require(game:GetService("ReplicatedStorage").Managers.ItemsManager)

    -- Ambil setting dari Global atau set default
    getgenv().AutoCollect = getgenv().AutoCollect or false
    getgenv().StepDelay = getgenv().StepDelay or 0.05 
    getgenv().IgnoreGems = getgenv().IgnoreGems or false
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

        -- Folder yang akan dicek
        local folders = {"Drops"}
        if not getgenv().IgnoreGems then table.insert(folders, "Gems") end

        for _, folderName in pairs(folders) do
            local container = workspace:FindFirstChild(folderName)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    -- CEK FILTER (Blacklist & BadItems)
                    local itemId = item:GetAttribute("id") or item.Name
                    if not badItems[item] and not getgenv().ItemBlacklist[itemId] then
                        local d = (root.Position - item:GetPivot().Position).Magnitude
                        if d < dist then dist = d; target = item end
                    end
                end
            end
        end
        return target
    end

    -- [[ 3. NEW FEATURE FUNCTIONS ]] --

    local function ScanWorldDrops()
        local summary = {}
        local totalAll = 0
        local GEMS_VALUE_MAP = { [0] = 1, [1] = 5, [2] = 10, [3] = 50, [4] = 100 }
        local folders = { ["Drops"] = false, ["Gems"] = true }

        for folderName, isGemsFolder in pairs(folders) do
            local container = workspace:FindFirstChild(folderName)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    local id = item:GetAttribute("id") or item.Name
                    local nValue = item:GetAttribute("n") or 0
                    local amount = 0

                    if isGemsFolder then
                        id = "Gems"
                        amount = GEMS_VALUE_MAP[nValue] or 1
                    else
                        id = id or "Unknown"
                        amount = item:GetAttribute("amount") or 1
                    end

                    summary[id] = (summary[id] or 0) + amount
                    totalAll = totalAll + amount
                end
            end
        end
        return summary, totalAll
    end

    -- Logika Navigasi (tetap sama)
    local function isWalkable(gx, gy, currentY)
        if gx < LIMIT.MIN_X or gx > LIMIT.MAX_X or gy < LIMIT.MIN_Y or gy > LIMIT.MAX_Y then return false end
        if lockedDoors[gx .. "," .. gy] then return false end 
        if WorldTiles[gx] and WorldTiles[gx][gy] then
            local l1 = WorldTiles[gx][gy][1]
            local itemName = (type(l1) == "table") and l1[1] or l1
            if itemName then
                local n = string.lower(tostring(itemName))
                if string.find(n, "door") then return true end
                if string.find(n, "frame") then return (not currentY or gy >= currentY) end
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

    -- [[ 4. UI ELEMENTS ]] --
    SubTab:AddSection("Collect Master")
    SubTab:AddToggle("Enable Auto Collect", getgenv().AutoCollect, function(state)
        getgenv().AutoCollect = state
        if state then InitDoorDatabase() end
    end)
    
    SubTab:AddToggle("Ignore All Gems", getgenv().IgnoreGems, function(state)
        getgenv().IgnoreGems = state
    end)

    SubTab:AddSection("Settings & Scanners")
    SubTab:AddSlider("Step Speed", 0.01, 0.2, 0.05, function(val) getgenv().StepDelay = val end)
    
    SubTab:AddButton("Scan World Drops (F9)", function()
        local result, total = ScanWorldDrops()
        print("--- [WORLD SCAN] ---")
        for id, count in pairs(result) do
            local name = (id == "Gems") and "Gems" or IM.GetName(id)
            print("- " .. name .. " (" .. tostring(id) .. "): " .. count)
        end
        print("Total Wealth: " .. total)
        Window:Notify("Check F9 Console for results!", 3, "ok")
    end)

    SubTab:AddSection("Filter Management")
    
    -- Dropdown dari Database
    local allItemNames = {}
    local nameToId = {}
    for id, data in pairs(IM.ItemsData) do
        local n = data.Name or tostring(id)
        table.insert(allItemNames, n)
        nameToId[n] = id
    end
    table.sort(allItemNames)

    SubTab:AddDropdown("Add to Blacklist", allItemNames, function(selected)
        local id = nameToId[selected]
        getgenv().ItemBlacklist[id] = true
        Window:Notify("Blacklisted: " .. selected, 2, "ok")
    end)

    SubTab:AddButton("Edit / Clear Blacklist", function()
        local listText = ""
        for id, _ in pairs(getgenv().ItemBlacklist) do listText = listText .. id .. "," end
        Window:PromptInput("Edit Blacklist (IDs separated by comma)", listText, function(val)
            local newTbl = {}
            for id in string.gmatch(val, '([^, ]+)') do newTbl[id] = true end
            getgenv().ItemBlacklist = newTbl
            Window:Notify("Blacklist Updated!", 2, "ok")
        end)
    end)

    SubTab:AddButton("Reset All (Including Bad Items)", function()
        badItems = {}
        lockedDoors = {}
        getgenv().ItemBlacklist = {}
        Window:Notify("All filters reset!", 2, "ok")
    end)

    local StatusLabel = SubTab:AddLabel("Status: Idle")

    -- [[ 5. GRAVITY BYPASS ]] --
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

    -- [[ 6. MAIN LOOP ]] --
    InitDoorDatabase()
    task.spawn(function()
        while true do
            local success, err = pcall(function()
                if getgenv().AutoCollect then
                    local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
                    local target = GetNearestItem()
                    
                    if Hitbox and target then
                        StatusLabel:SetText("Status: Pathfinding to " .. target.Name)
                        local sx, sy = math.floor(Hitbox.Position.X/4.5+0.5), math.floor(Hitbox.Position.Y/4.5+0.5)
                        local tx, ty = math.floor(target:GetPivot().Position.X/4.5+0.5), math.floor(target:GetPivot().Position.Y/4.5+0.5)

                        local path = findSmartPath(sx, sy, tx, ty)
                        if path then
                            for _, point in ipairs(path) do
                                if not getgenv().AutoCollect then break end
                                Hitbox.CFrame = CFrame.new(point.X, point.Y, Hitbox.Position.Z)
                                movementModule.Position = Hitbox.Position
                                task.wait(getgenv().StepDelay)

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
