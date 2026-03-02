return function(SubTab, Window, myToken)
    -- ========================================
    -- [1] SETUP & VARIABLES
    -- ========================================
    local Players           = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LP                = Players.LocalPlayer
    local worldData         = require(ReplicatedStorage.WorldTiles)
    local movementModule    = require(LP.PlayerScripts.PlayerMovement)
    local IM                = require(ReplicatedStorage.Managers.ItemsManager)

    local Remotes      = ReplicatedStorage:WaitForChild("Remotes")
    local PlayerFist   = Remotes:WaitForChild("PlayerFist")
    local PlayerPlace  = Remotes:WaitForChild("PlayerPlaceItem")
    local MovPacket    = Remotes:WaitForChild("PlayerMovementPackets"):WaitForChild(LP.Name)

    getgenv().DirtFarm_Enabled    = getgenv().DirtFarm_Enabled    or false
    getgenv().DirtFarm_BreakDelay = getgenv().DirtFarm_BreakDelay or 0.035
    getgenv().DirtFarm_StepDelay  = getgenv().DirtFarm_StepDelay  or 0.12

    local GRID_SIZE = 4.5
    local OFFSET_Y  = -0.249640
    local WORLD_MIN_X = 0
    local WORLD_MAX_X = 100
    local WORLD_MIN_Y = 6

    -- ========================================
    -- [2] HELPERS
    -- ========================================

    local function worldPos(gx, gy)
        return gx * GRID_SIZE, gy * GRID_SIZE + OFFSET_Y
    end

    local function getHitbox()
        return workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
    end

    local function getGridPos()
        local Hitbox = getHitbox()
        if not Hitbox then return 0, 0 end
        return
            math.floor(Hitbox.Position.X / GRID_SIZE + 0.5),
            math.floor((Hitbox.Position.Y - OFFSET_Y) / GRID_SIZE + 0.5)
    end

    local function isAtPosition(gx, gy)
        local cx, cy = getGridPos()
        return cx == gx and cy == gy
    end

    local function moveTo(gx, gy)
        local Hitbox = getHitbox()
        if not Hitbox then return end
        local wx, wy = worldPos(gx, gy)
        Hitbox.CFrame = CFrame.new(wx, wy, Hitbox.Position.Z)
        movementModule.Position = Hitbox.Position
        pcall(function() MovPacket:FireServer(wx, wy) end)
    end

    -- Pathfinding
    local function isWalkable(gx, gy)
        if gx < WORLD_MIN_X or gx > WORLD_MAX_X or gy < WORLD_MIN_Y or gy > 60 then
            return false
        end
        if worldData[gx] and worldData[gx][gy] and worldData[gx][gy][1] ~= nil then
            local l1 = worldData[gx][gy][1]
            local n = string.lower(tostring((type(l1) == "table") and l1[1] or l1))
            -- Sapling bisa dilewati
            if string.find(n, "sapling") then return true end
            return false
        end
        return true
    end

    local function findSmartPath(startX, startY, targetX, targetY)
        local startKey = startX .. "," .. startY
        local queue    = {{x=startX, y=startY, cost=0, parent=nil}}
        local visited  = {[startKey] = 0}
        local dirs     = {{x=1,y=0},{x=-1,y=0},{x=0,y=1},{x=0,y=-1}}
        local found    = nil
        local limit    = 0
        while #queue > 0 do
            if _G.LatestRunToken ~= myToken then break end
            limit = limit + 1
            if limit > 4000 then break end
            local minIdx, minCost = 1, queue[1].cost
            for i = 2, #queue do
                if queue[i].cost < minCost then
                    minCost = queue[i].cost
                    minIdx  = i
                end
            end
            local cur = table.remove(queue, minIdx)
            if cur.x == targetX and cur.y == targetY then found = cur break end
            for _, d in ipairs(dirs) do
                local nx, ny = cur.x + d.x, cur.y + d.y
                local nkey   = nx .. "," .. ny
                if isWalkable(nx, ny) then
                    local nc = cur.cost + 1
                    if not visited[nkey] or nc < visited[nkey] then
                        visited[nkey] = nc
                        table.insert(queue, {x=nx, y=ny, cost=nc, parent=cur})
                    end
                end
            end
        end
        if not found then return nil end
        local path, node = {}, found
        while node.parent ~= nil do
            table.insert(path, 1, Vector3.new(node.x * GRID_SIZE, node.y * GRID_SIZE, 0))
            node = node.parent
        end
        return path
    end

    -- Jalan ke (gx, gy) pakai SmartPath
    local function walkTo(gx, gy, StatusLabel, label)
        local Hitbox = getHitbox()
        if not Hitbox then return end

        local sx, sy = getGridPos()
        if sx == gx and sy == gy then return end

        local path = findSmartPath(sx, sy, gx, gy)
        if not path then
            local wx, wy = worldPos(gx, gy)
            Hitbox.CFrame = CFrame.new(wx, wy, Hitbox.Position.Z)
            movementModule.Position = Hitbox.Position
            pcall(function() MovPacket:FireServer(wx, wy) end)
            task.wait(0.2)
            return
        end

        for i, point in ipairs(path) do
            if not getgenv().DirtFarm_Enabled or _G.LatestRunToken ~= myToken then break end
            if StatusLabel then
                StatusLabel:SetText(string.format("Status: %s (%d/%d)", label or "Jalan", i, #path))
            end
            local wx = math.floor(point.X / GRID_SIZE + 0.5) * GRID_SIZE
            local wy = math.floor(point.Y / GRID_SIZE + 0.5) * GRID_SIZE + OFFSET_Y
            Hitbox.CFrame = CFrame.new(wx, wy, Hitbox.Position.Z)
            movementModule.Position = Hitbox.Position
            pcall(function() MovPacket:FireServer(wx, wy) end)
            task.wait(getgenv().DirtFarm_StepDelay)
        end

        if not isAtPosition(gx, gy) then
            local wx, wy = worldPos(gx, gy)
            Hitbox.CFrame = CFrame.new(wx, wy, Hitbox.Position.Z)
            movementModule.Position = Hitbox.Position
            pcall(function() MovPacket:FireServer(wx, wy) end)
            task.wait(0.15)
        end
    end

    local function isTileEmpty(gx, gy)
        local tile = worldData[gx] and worldData[gx][gy]
        return not tile or (tile[1] == nil and tile[2] == nil)
    end

    local function shouldSkip(itemName)
        if not itemName then return false end
        local n = string.lower(tostring(itemName))
        if string.find(n, "lock")    then return true end
        if string.find(n, "door")    then return true end
        if n == "bedrock"            then return true end
        return false
    end

    local function getTileLayer1(gx, gy)
        local tile = worldData[gx] and worldData[gx][gy]
        if not tile or tile[1] == nil then return nil end
        local itemName = (type(tile[1]) == "table") and tile[1][1] or tile[1]
        if shouldSkip(itemName) then return nil end
        return itemName
    end

    local function getTileLayer2(gx, gy)
        local tile = worldData[gx] and worldData[gx][gy]
        if not tile or tile[2] == nil then return nil end
        local itemName = (type(tile[2]) == "table") and tile[2][1] or tile[2]
        if shouldSkip(itemName) then return nil end
        return itemName
    end

    -- Break tile (gx, gy) sampai kosong, player harus di (gx, gy+1)
    local function breakTile(gx, gy)
        local pos = Vector2.new(gx, gy)

        -- Layer 1
        while _G.LatestRunToken == myToken and getgenv().DirtFarm_Enabled do
            if not getTileLayer1(gx, gy) then break end
            if isAtPosition(gx, gy + 1) then
                pcall(function() MovPacket:FireServer(worldPos(gx, gy + 1)) end)
                PlayerFist:FireServer(pos)
                task.wait(getgenv().DirtFarm_BreakDelay)
            else
                moveTo(gx, gy + 1)
                task.wait(0.1)
            end
        end

        -- Layer 2 (background)
        while _G.LatestRunToken == myToken and getgenv().DirtFarm_Enabled do
            if not getTileLayer2(gx, gy) then break end
            if isAtPosition(gx, gy + 1) then
                pcall(function() MovPacket:FireServer(worldPos(gx, gy + 1)) end)
                PlayerFist:FireServer(pos)
                task.wait(getgenv().DirtFarm_BreakDelay)
            else
                moveTo(gx, gy + 1)
                task.wait(0.1)
            end
        end
    end

    -- Cari slot dirt_sapling di inventory
    local function getDirtSaplingSlot()
        local InventoryMod = require(LP.PlayerScripts:FindFirstChild("InventoryModule") 
            or LP.PlayerScripts:FindFirstChild("Inventory"))
        if not InventoryMod then return nil end
        local stacks = InventoryMod.Stacks or InventoryMod.stacks
        if not stacks then return nil end
        for i, stack in pairs(stacks) do
            if stack and tostring(stack.Id) == "dirt_sapling" then
                return i, stack.Amount or 0
            end
        end
        return nil, 0
    end

    -- Cari slot dirt di inventory
    local function getDirtSlot()
        local InventoryMod = require(LP.PlayerScripts:FindFirstChild("InventoryModule")
            or LP.PlayerScripts:FindFirstChild("Inventory"))
        if not InventoryMod then return nil end
        local stacks = InventoryMod.Stacks or InventoryMod.stacks
        if not stacks then return nil end
        for i, stack in pairs(stacks) do
            if stack and tostring(stack.Id) == "dirt" then
                return i, stack.Amount or 0
            end
        end
        return nil, 0
    end

    -- Place dirt di (gx, gy)
    local function placeDirt(gx, gy)
        local slotIdx, amount = getDirtSlot()
        if not slotIdx or amount <= 0 then return false end
        PlayerPlace:FireServer(Vector2.new(gx, gy), slotIdx, 1)
        task.wait(0.1)
        return true
    end

    -- Break sapling di tile yang sama dengan player (gx, gy)
    local function harvestTile(gx, gy)
        local pos = Vector2.new(gx, gy)
        while _G.LatestRunToken == myToken and getgenv().DirtFarm_Enabled do
            local tile = worldData[gx] and worldData[gx][gy]
            if not tile or tile[1] == nil then break end
            if isAtPosition(gx, gy) then
                pcall(function() MovPacket:FireServer(worldPos(gx, gy)) end)
                PlayerFist:FireServer(pos)
                task.wait(getgenv().DirtFarm_BreakDelay)
            else
                moveTo(gx, gy)
                task.wait(0.1)
            end
        end
    end

    -- Collect semua drop item di range X, Y area panen
    local function collectDropsInArea(minX, maxX, areaY, StatusLabel)
        StatusLabel:SetText("Status: Collecting drops...")
        local maxAttempts = 3
        for attempt = 1, maxAttempts do
            local found = false
            local folders = {"Drops"}
            for _, folderName in pairs(folders) do
                local container = workspace:FindFirstChild(folderName)
                if container then
                    for _, item in pairs(container:GetChildren()) do
                        if not getgenv().DirtFarm_Enabled or _G.LatestRunToken ~= myToken then break end
                        local pos = item:GetPivot().Position
                        local ix = math.floor(pos.X / GRID_SIZE + 0.5)
                        local iy = math.floor((pos.Y - OFFSET_Y) / GRID_SIZE + 0.5)
                        -- Cek apakah item ada di area panen
                        if ix >= minX and ix <= maxX and math.abs(iy - areaY) <= 3 then
                            found = true
                            walkTo(ix, iy, StatusLabel, "Collect")
                            task.wait(0.2)
                        end
                    end
                end
            end
            if not found then break end
            task.wait(0.3)
        end
    end

    -- Tanam 10 dirt_sapling, tunggu 30s, panen, collect
    local function plantAndHarvest(currentX, currentY, StatusLabel)
        local slotIdx = getDirtSaplingSlot()
        if not slotIdx then
            Window:Notify("Tidak ada dirt_sapling di inventory!", 3)
            return
        end

        StatusLabel:SetText("Status: Menanam sapling...")
        local goLeft = currentX > 50
        local plantedPositions = {}

        for i = 1, 10 do
            if not getgenv().DirtFarm_Enabled or _G.LatestRunToken ~= myToken then break end
            slotIdx = getDirtSaplingSlot()
            if not slotIdx then break end

            local plantX = goLeft and (currentX - i + 1) or (currentX + i - 1)
            plantX = math.clamp(plantX, WORLD_MIN_X + 2, WORLD_MAX_X - 2)

            walkTo(plantX, currentY, StatusLabel, "Ke titik tanam")
            -- Plant di tile yang sama dengan posisi player
            PlayerPlace:FireServer(Vector2.new(plantX, currentY), slotIdx, 1)
            table.insert(plantedPositions, {x = plantX, y = currentY})
            task.wait(0.15)
        end

        -- Tunggu 30 detik
        for i = 30, 1, -1 do
            if not getgenv().DirtFarm_Enabled or _G.LatestRunToken ~= myToken then break end
            StatusLabel:SetText(string.format("Status: Menunggu panen (%ds)...", i))
            task.wait(1)
        end

        -- Panen: break sapling di tile yang sama dengan player
        StatusLabel:SetText("Status: Memanen...")
        for _, plantPos in ipairs(plantedPositions) do
            if not getgenv().DirtFarm_Enabled or _G.LatestRunToken ~= myToken then break end
            walkTo(plantPos.x, plantPos.y, StatusLabel, "Panen")
            harvestTile(plantPos.x, plantPos.y)
        end

        -- Collect drop yang ketinggalan di area panen
        local minX = math.min(table.unpack((function()
            local xs = {}
            for _, p in ipairs(plantedPositions) do table.insert(xs, p.x) end
            return xs
        end)()))
        local maxX = math.max(table.unpack((function()
            local xs = {}
            for _, p in ipairs(plantedPositions) do table.insert(xs, p.x) end
            return xs
        end)()))
        collectDropsInArea(minX, maxX, currentY, StatusLabel)
    end

    -- ========================================
    -- [3] GRAVITY BYPASS
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait()
            if getgenv().DirtFarm_Enabled then
                pcall(function()
                    if movementModule.VelocityY < 0 then movementModule.VelocityY = 0 end
                    movementModule.Grounded = true
                end)
            end
        end
    end)

    -- ========================================
    -- [4] UI
    -- ========================================
    SubTab:AddSection("DIRT FARM")
    getgenv().SayzUI_Handles["DirtFarm_Master"] = SubTab:AddToggle("Enable Dirt Farm", getgenv().DirtFarm_Enabled, function(t)
        getgenv().DirtFarm_Enabled = t
    end)
    getgenv().SayzUI_Handles["DirtFarm_BreakDelay"] = SubTab:AddSlider("Break Delay", 0.01, 0.2, getgenv().DirtFarm_BreakDelay, function(val)
        getgenv().DirtFarm_BreakDelay = val
    end, 2)
    getgenv().SayzUI_Handles["DirtFarm_StepDelay"] = SubTab:AddSlider("Move Speed", 0.05, 0.2, getgenv().DirtFarm_StepDelay, function(val)
        getgenv().DirtFarm_StepDelay = val
    end, 2)

    SubTab:AddSection("STATUS")
    local StatusLabel   = SubTab:AddLabel("Status  : Idle")
    local PhaseLabel    = SubTab:AddLabel("Fase    : -")
    local PosLabel      = SubTab:AddLabel("Posisi  : -")

    SubTab:AddSection("PANDUAN")
    SubTab:AddLabel("Fase 1: Break kolom kiri (X=0,1) dari atas ke bawah")
    SubTab:AddLabel("Fase 2: Break kolom kanan (X=99,100) dari atas ke bawah")
    SubTab:AddLabel("Fase 3: Break zigzag X=2-98, break 2 tile di bawah player")
    SubTab:AddLabel("Fase 4: Naik, place dirt 1 tile di atas kepala")
    SubTab:AddLabel("        Kalau dirt habis: tanam 10 sapling, tunggu 30s, panen")

    -- ========================================
    -- [5] MAIN LOOP
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            if getgenv().DirtFarm_Enabled then
                pcall(function()

                    -- Detect Y paling atas yang ada block
                    local startY = WORLD_MIN_Y
                    for gx = WORLD_MIN_X, WORLD_MAX_X do
                        for gy = 60, WORLD_MIN_Y, -1 do
                            if not isTileEmpty(gx, gy) then
                                if gy > startY then startY = gy end
                                break
                            end
                        end
                    end

                    -- ============================
                    -- FASE 1: Break kolom kiri
                    -- ============================
                    PhaseLabel:SetText("Fase: 1 - Break Kiri")
                    for _, col in ipairs({0, 1}) do
                        walkTo(col, startY + 1, StatusLabel, "Ke kiri")
                        local y = startY
                        while y >= WORLD_MIN_Y and getgenv().DirtFarm_Enabled and _G.LatestRunToken == myToken do
                            PosLabel:SetText(string.format("Posisi: (%d, %d)", col, y))
                            -- Break tile di bawah player (y-1 dari posisi player)
                            local cx, cy = getGridPos()
                            breakTile(col, cy - 1)
                            -- Turun 1
                            walkTo(col, cy - 1, StatusLabel, "Turun kiri")
                            y = y - 1
                        end
                    end

                    -- ============================
                    -- FASE 2: Break kolom kanan
                    -- ============================
                    PhaseLabel:SetText("Fase: 2 - Break Kanan")
                    for _, col in ipairs({100, 99}) do
                        walkTo(col, startY + 1, StatusLabel, "Ke kanan")
                        local y = startY
                        while y >= WORLD_MIN_Y and getgenv().DirtFarm_Enabled and _G.LatestRunToken == myToken do
                            PosLabel:SetText(string.format("Posisi: (%d, %d)", col, y))
                            local cx, cy = getGridPos()
                            breakTile(col, cy - 1)
                            walkTo(col, cy - 1, StatusLabel, "Turun kanan")
                            y = y - 1
                        end
                    end

                    -- ============================
                    -- FASE 3: Break zigzag
                    -- ============================
                    PhaseLabel:SetText("Fase: 3 - Break Zigzag")
                    walkTo(2, startY + 1, StatusLabel, "Ke start zigzag")

                    local goingRight = true
                    local cx, cy = getGridPos()

                    while cy > WORLD_MIN_Y + 2 and getgenv().DirtFarm_Enabled and _G.LatestRunToken == myToken do
                        local xStart = goingRight and 2 or 98
                        local xEnd   = goingRight and 98 or 2
                        local xStep  = goingRight and 1 or -1

                        for gx = xStart, xEnd, xStep do
                            if not getgenv().DirtFarm_Enabled or _G.LatestRunToken ~= myToken then break end
                            walkTo(gx, cy, StatusLabel, "Zigzag break")
                            PosLabel:SetText(string.format("Posisi: (%d, %d)", gx, cy))
                            -- Break 2 tile di bawah player
                            breakTile(gx, cy - 2)
                        end

                        -- Turun 2
                        cy = cy - 2
                        if cy < WORLD_MIN_Y + 2 then break end
                        walkTo(goingRight and 98 or 2, cy, StatusLabel, "Turun zigzag")
                        goingRight = not goingRight
                    end

                    -- ============================
                    -- FASE 4: Place dirt zigzag (naik dari bawah)
                    -- ============================
                    PhaseLabel:SetText("Fase: 4 - Place Dirt")

                    -- Naik ke posisi paling bawah dulu
                    walkTo(2, WORLD_MIN_Y + 2, StatusLabel, "Ke start place")
                    cx, cy = getGridPos()
                    goingRight = true

                    while cy <= startY and getgenv().DirtFarm_Enabled and _G.LatestRunToken == myToken do
                        local xStart = goingRight and 2 or 98
                        local xEnd   = goingRight and 98 or 2
                        local xStep  = goingRight and 1 or -1

                        for gx = xStart, xEnd, xStep do
                            if not getgenv().DirtFarm_Enabled or _G.LatestRunToken ~= myToken then break end

                            walkTo(gx, cy, StatusLabel, "Place dirt")
                            PosLabel:SetText(string.format("Posisi: (%d, %d)", gx, cy))

                            -- Place dirt 1 tile di atas kepala
                            local placed = placeDirt(gx, cy + 1)
                            if not placed then
                                -- Dirt habis, tanam sapling dulu
                                plantAndHarvest(gx, cy, StatusLabel)
                                -- Coba place lagi setelah panen
                                placeDirt(gx, cy + 1)
                            end
                            task.wait(0.1)
                        end

                        -- Naik 2
                        cy = cy + 2
                        if cy > startY then break end
                        walkTo(goingRight and 98 or 2, cy, StatusLabel, "Naik place")
                        goingRight = not goingRight
                    end

                    -- Selesai
                    if getgenv().DirtFarm_Enabled then
                        PhaseLabel:SetText("Fase: Selesai!")
                        StatusLabel:SetText("Status: Dirt Farm selesai!")
                        getgenv().DirtFarm_Enabled = false
                        if getgenv().SayzUI_Handles["DirtFarm_Master"] then
                            getgenv().SayzUI_Handles["DirtFarm_Master"]:Set(false)
                        end
                        Window:Notify("Dirt Farm selesai!", 3, "ok")
                    end
                end)
            else
                StatusLabel:SetText("Status  : Idle")
                PhaseLabel:SetText("Fase    : -")
            end
            task.wait(0.5)
        end
    end)
end
