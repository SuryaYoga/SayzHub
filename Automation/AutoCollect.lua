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
                    if not badItems[item] and not getgenv().ItemBlacklist[itemId] then
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

    -- [[ 3. UI ELEMENTS ]] --
    
    -- TOGGLE PALING ATAS
    SubTab:AddSection("Collect Master")
    SubTab:AddToggle("Enable Auto Collect", getgenv().AutoCollect, function(state)
        getgenv().AutoCollect = state
        if state then InitDoorDatabase() end
    end)

    -- FILTER MANAGEMENT DI TENGAH
    SubTab:AddSection("Filter Management")
    
    local ActiveFilterLabel = SubTab:AddLabel("Active Blacklist: None")

    local function RefreshFilterDisplay()
        local listStr = ""
        local count = 0
        for id, _ in pairs(getgenv().ItemBlacklist) do
            count = count + 1
            local name = IM.GetName(id) or id
            listStr = listStr .. name .. ", "
        end
        if count == 0 then
            ActiveFilterLabel:SetText("Active Blacklist: None")
        else
            ActiveFilterLabel:SetText("🚫 Blocked: " .. listStr:sub(1, -3))
        end
    end

    -- Karena dropdown library ini statis, kita pakai dropdown awal untuk item dasar
    SubTab:AddDropdown("Quick Filter", {"dirt", "dirt_sapling"}, function(selected)
        getgenv().ItemBlacklist[selected] = not getgenv().ItemBlacklist[selected] and true or nil
        RefreshFilterDisplay()
    end)

    -- Gunakan Window:Prompt (Baris 248 Library) untuk scan dan input ID manual
    SubTab:AddButton("Scan World & Add ID", function()
        -- Kita scan dulu world-nya
        local found = {}
        for _, folder in pairs({"Drops", "Gems"}) do
            local c = workspace:FindFirstChild(folder)
            if c then
                for _, item in pairs(c:GetChildren()) do
                    local id = item:GetAttribute("id") or item.Name
                    local name = IM.GetName(id) or id
                    if not table.find(found, name) then table.insert(found, name .. " (" .. id .. ")") end
                end
            end
        end
        
        local displayFound = #found > 0 and table.concat(found, ", ") or "No items on ground"
        
        -- Munculkan Prompt untuk input ID (Bisa lihat list dari console/label)
        Window:Prompt("Enter ID String to Block", "Found in world: " .. displayFound, function(val)
            if val and val ~= "" then
                getgenv().ItemBlacklist[val] = true
                RefreshFilterDisplay()
                Window:Notify("Added " .. val .. " to blacklist", 2)
            end
        end)
    end)

    SubTab:AddButton("Clear All Filters", function()
        getgenv().ItemBlacklist = {}
        badItems = {}
        RefreshFilterDisplay()
        Window:Notify("Filters Cleared!", 2)
    end)

    -- SETTINGS DI BAWAH
    SubTab:AddSection("Settings")

    -- Solusi Speed Desimal pake Window:Prompt (Baris 248 Library)
    SubTab:AddButton("Set Step Speed (Current: " .. getgenv().StepDelay .. ")", function()
        Window:Prompt("Enter Decimal Speed", "Example: 0.05 or 0.02", function(val)
            local num = tonumber(val)
            if num then
                getgenv().StepDelay = num
                Window:Notify("Speed set to " .. num, 2)
            else
                Window:Notify("Invalid Number!", 2)
            end
        end)
    end)

    local StatusLabel = SubTab:AddLabel("Status: Idle")

    -- [[ 4. MAIN LOOP & BYPASS ]] --
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

    InitDoorDatabase()
    RefreshFilterDisplay()
    
    task.spawn(function()
        while true do
            pcall(function()
                if getgenv().AutoCollect then
                    local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
                    local target = GetNearestItem()
                    if Hitbox and target then
                        StatusLabel:SetText("Status: Collecting " .. (target:GetAttribute("id") or "Item"))
                        local sx, sy = math.floor(Hitbox.Position.X/4.5+0.5), math.floor(Hitbox.Position.Y/4.5+0.5)
                        local tx, ty = math.floor(target:GetPivot().Position.X/4.5+0.5), math.floor(target:GetPivot().Position.Y/4.5+0.5)
                        local path = findSmartPath(sx, sy, tx, ty)
                        if path then
                            for _, point in ipairs(path) do
                                if not getgenv().AutoCollect then break end
                                Hitbox.CFrame = CFrame.new(point.X, point.Y, Hitbox.Position.Z)
                                movementModule.Position = Hitbox.Position
                                task.wait(getgenv().StepDelay)
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
