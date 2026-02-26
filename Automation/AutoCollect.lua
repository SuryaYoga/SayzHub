return function(SubTab, Window)
    -- [[ 1. SETUP & VARIABLES ]] --
    local LP = game:GetService("Players").LocalPlayer
    local WorldTiles = require(game.ReplicatedStorage.WorldTiles)
    local movementModule = require(LP.PlayerScripts.PlayerMovement)
    local IM = require(game:GetService("ReplicatedStorage").Managers.ItemsManager)

    getgenv().AutoCollect = getgenv().AutoCollect or false
    getgenv().StepDelay = getgenv().StepDelay or 0.05 
    getgenv().ItemBlacklist = getgenv().ItemBlacklist or {} -- Filter tersimpan

    local LIMIT = { MIN_X = 0, MAX_X = 100, MIN_Y = 6, MAX_Y = 60 }
    local doorDatabase = {} 
    local lockedDoors = {} 
    local badItems = {} 
    local itemPool = {"dirt", "dirt_sapling", "stone", "lava", "gravel"}

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
                    -- Filter: Jangan ambil jika di-blacklist user atau stuck (badItems)
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
                if string.find(n, "frame") then return true end
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

    -- BAGIAN ATAS: TOGGLE
    SubTab:AddSection("Collect Master")
    SubTab:AddToggle("Enable Auto Collect", getgenv().AutoCollect, function(state)
        getgenv().AutoCollect = state
        if state then InitDoorDatabase() end
    end)

    -- BAGIAN TENGAH: FILTER MANAGEMENT
    SubTab:AddSection("Filter Management")
    
    local ActiveFilterLabel = SubTab:AddLabel("Active Blacklist: None")

    local function RefreshLabel()
        local list = {}
        for id, _ in pairs(getgenv().ItemBlacklist) do
            table.insert(list, IM.GetName(id) or id)
        end
        ActiveFilterLabel:SetText(#list == 0 and "Active Blacklist: None" or "🚫 Blocked: " .. table.concat(list, ", "))
    end

    -- Fitur Baru: MultiDropdown (Klik Simpan untuk aktifkan filter)
    SubTab:AddMultiDropdown("Select Blacklist Items", itemPool, function(selectedTable)
        getgenv().ItemBlacklist = selectedTable
        RefreshLabel()
        Window:Notify("Filter Saved!", 2)
    end)

    -- Fitur Baru: GridSelector (Misal untuk area scan)
    SubTab:AddSection("Scan Area (Grid 5x5)")
    SubTab:AddGridSelector(function(selectedTiles)
        -- Logic grid bisa kamu isi di sini
        print("Tiles selected")
    end)

    SubTab:AddButton("Clear All Filters", function()
        getgenv().ItemBlacklist = {}
        badItems = {}
        lockedDoors = {}
        RefreshLabel()
        Window:Notify("Reset Complete!", 2)
    end)

    -- BAGIAN BAWAH: SETTINGS
    SubTab:AddSection("Settings")

    -- Menggunakan Button + Prompt karena slider library sering tidak support desimal
    SubTab:AddButton("Set Step Speed (Current: "..getgenv().StepDelay..")", function()
        Window:Prompt("Speed Config", "Enter decimal (e.g. 0.05):", function(val)
            local n = tonumber(val)
            if n then
                getgenv().StepDelay = n
                Window:Notify("Speed updated to: " .. n, 2)
            end
        end)
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
    RefreshLabel()

    task.spawn(function()
        while true do
            pcall(function()
                if getgenv().AutoCollect then
                    local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
                    local target = GetNearestItem()
                    
                    if Hitbox and target then
                        local itemName = IM.GetName(target:GetAttribute("id") or target.Name) or "Item"
                        StatusLabel:SetText("Status: Going to " .. itemName)
                        
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
                            badItems[target] = true -- Tandai item tak terjangkau
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
