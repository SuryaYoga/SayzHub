return function(SubTab, Window)
    -- [[ 1. SETUP & VARIABLES ]] --
    local LP = game:GetService("Players").LocalPlayer
    local WorldTiles = require(game.ReplicatedStorage.WorldTiles)
    local movementModule = require(LP.PlayerScripts.PlayerMovement)

    -- Ambil setting dari Global atau set default
    getgenv().AutoCollect = getgenv().AutoCollect or false
    getgenv().StepDelay = getgenv().StepDelay or 0.05

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

        for _, folder in pairs({ "Drops", "Gems" }) do
            local container = workspace:FindFirstChild(folder)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    if not badItems[item] then
                        local d = (root.Position - item:GetPivot().Position).Magnitude
                        if d < dist then
                            dist = d
                            target = item
                        end
                    end
                end
            end
        end
        return target
    end

    local function isWalkable(gx, gy, currentY)
        if gx < LIMIT.MIN_X or gx > LIMIT.MAX_X or gy < LIMIT.MIN_Y or gy > LIMIT.MAX_Y then
            return false
        end
        if lockedDoors[gx .. "," .. gy] then
            return false
        end

        if WorldTiles[gx] and WorldTiles[gx][gy] then
            local l1 = WorldTiles[gx][gy][1]
            local itemName = (type(l1) == "table") and l1[1] or l1
            if itemName then
                local n = string.lower(tostring(itemName))
                if string.find(n, "door") then
                    return true
                end
                if string.find(n, "frame") then
                    -- (tetap sama seperti code lama kamu)
                    if currentY and gy > currentY then return true end
                    return true
                end
                return false
            end
        end
        return true
    end

    -- BFS sederhana (versi lama kamu) biar "lurus" dan stabil
    local function findSmartPath(startX, startY, targetX, targetY)
        local queue = { { x = startX, y = startY, path = {} } }
        local visited = { [startX .. "," .. startY] = true }
        local directions = {
            { x = 1, y = 0 }, { x = -1, y = 0 },
            { x = 0, y = 1 }, { x = 0, y = -1 }
        }

        local limit = 0
        while #queue > 0 do
            limit = limit + 1
            if limit > 4000 then return nil end

            local current = table.remove(queue, 1)
            if current.x == targetX and current.y == targetY then
                return current.path
            end

            for _, d in ipairs(directions) do
                local nx, ny = current.x + d.x, current.y + d.y
                local key = nx .. "," .. ny
                if (not visited[key]) and isWalkable(nx, ny, current.y) then
                    visited[key] = true
                    local newPath = { unpack(current.path) }
                    table.insert(newPath, Vector3.new(nx * 4.5, ny * 4.5, 0))
                    table.insert(queue, { x = nx, y = ny, path = newPath })
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
                if doorDatabase[key] then
                    lockedDoors[key] = true
                end
            end
        end
    end

    -- [[ 3. UI ELEMENTS ]] --
    SubTab:AddSection("Collect Master")
    SubTab:AddToggle("Enable Auto Collect", getgenv().AutoCollect, function(state)
        getgenv().AutoCollect = state
        if state then
            InitDoorDatabase()
        end
    end)

    SubTab:AddSection("Settings")

    -- GANTI SLIDER -> INPUT TEKS (min 0.01 max 0.2)
    SubTab:AddInput("Step Delay (0.01 - 0.20)", "0.05", function(v)
        local n = tonumber(v)
        if not n then
            if Window and Window.Notify then
                Window:Notify("StepDelay harus angka.", 2, "danger")
            end
            return
        end
        if n < 0.01 then n = 0.01 end
        if n > 0.20 then n = 0.20 end
        getgenv().StepDelay = n
        if Window and Window.Notify then
            Window:Notify("StepDelay set: " .. tostring(n), 2, "ok")
        end
    end, tostring(getgenv().StepDelay))

    SubTab:AddButton("Reset Blacklist (Bad Items)", function()
        badItems = {}
        lockedDoors = {}
        if Window and Window.Notify then
            Window:Notify("Blacklist cleared!", 2, "ok")
        end
    end)

    -- IMPORTANT: Library baru AddLabel() mengembalikan HANDLE (punya :SetText)
    local StatusLabel = SubTab:AddLabel("Status: Idle")

    -- helper update label aman
    local function setStatus(text)
        if StatusLabel and StatusLabel.SetText then
            StatusLabel:SetText(text)
        end
    end

    -- [[ 4. GRAVITY BYPASS ]] --
    task.spawn(function()
        while true do
            if getgenv().AutoCollect then
                pcall(function()
                    if movementModule.VelocityY < 0 then
                        movementModule.VelocityY = 0
                    end
                    movementModule.Grounded = true
                end)
                task.wait(0.05)
            else
                task.wait(0.2)
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
                        setStatus("Status: Pathfinding to item...")

                        local sx = math.floor(Hitbox.Position.X / 4.5 + 0.5)
                        local sy = math.floor(Hitbox.Position.Y / 4.5 + 0.5)
                        local tp = target:GetPivot().Position
                        local tx = math.floor(tp.X / 4.5 + 0.5)
                        local ty = math.floor(tp.Y / 4.5 + 0.5)

                        local path = findSmartPath(sx, sy, tx, ty)
                        if path then
                            for _, point in ipairs(path) do
                                if not getgenv().AutoCollect then break end

                                Hitbox.CFrame = CFrame.new(point.X, point.Y, Hitbox.Position.Z)
                                movementModule.Position = Hitbox.Position
                                task.wait(getgenv().StepDelay)

                                -- Deteksi Stuck (Pintu)
                                local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                                local charPos = hrp and hrp.Position
                                if charPos then
                                    local dist2 = (Vector2.new(charPos.X, charPos.Y) - Vector2.new(point.X, point.Y)).Magnitude
                                    if dist2 > 4.5 then
                                        scanAndLockNearbyDoor(
                                            math.floor(point.X / 4.5 + 0.5),
                                            math.floor(point.Y / 4.5 + 0.5)
                                        )
                                        break
                                    end
                                end
                            end
                        else
                            badItems[target] = true
                        end
                    else
                        setStatus("Status: Scanning for items...")
                    end
                else
                    setStatus("Status: Paused")
                end
            end)

            task.wait(0.2)
        end
    end)
end
