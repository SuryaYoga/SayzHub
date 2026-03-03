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

    local Remotes     = ReplicatedStorage:WaitForChild("Remotes")
    local PlayerFist  = Remotes:WaitForChild("PlayerFist")
    local PlayerPlace = Remotes:WaitForChild("PlayerPlaceItem")
    local MovPacket   = Remotes:WaitForChild("PlayerMovementPackets"):WaitForChild(LP.Name)

    getgenv().DirtFarm_Enabled    = getgenv().DirtFarm_Enabled    or false
    getgenv().DirtFarm_BreakDelay = getgenv().DirtFarm_BreakDelay or 0.035
    getgenv().DirtFarm_StepDelay  = getgenv().DirtFarm_StepDelay  or 0.12
    getgenv().DirtFarm_WoodFrame  = getgenv().DirtFarm_WoodFrame  or false

    local GRID_SIZE   = 4.5
    local OFFSET_Y    = -0.249640
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

    local function isTileEmpty(gx, gy)
        local tile = worldData[gx] and worldData[gx][gy]
        return not tile or (tile[1] == nil and tile[2] == nil)
    end

    -- ========================================
    -- [3] SKIP / LOCK CHECKS
    -- ========================================

    local function shouldSkip(itemName)
        if not itemName then return false end
        local n = string.lower(tostring(itemName))
        if string.find(n, "lock") then return true end
        if string.find(n, "door") then return true end
        if n == "bedrock"         then return true end
        return false
    end

    -- Struktur lock_area: tile["5"] = "lock_area"
    local function isLockArea(gx, gy)
        local tile = worldData[gx] and worldData[gx][gy]
        if not tile then return false end
        if tile["5"] == "lock_area" or tile[5] == "lock_area" then return true end
        for k, v in pairs(tile) do
            if tostring(v) == "lock_area" then return true end
            if type(v) == "table" then
                for k2, v2 in pairs(v) do
                    if tostring(v2) == "lock_area" then return true end
                end
            end
        end
        return false
    end

    -- Struktur lock owner: tile[1] = ["small_lock", {owner=USERID, area=[...]}]
    local function getLockOwner(gx, gy)
        local tile = worldData[gx] and worldData[gx][gy]
        if not tile or not tile[1] then return nil end
        local layer1 = tile[1]
        if type(layer1) == "table" and type(layer1[2]) == "table" and layer1[2].owner then
            return layer1[2].owner
        end
        return nil
    end

    local function findLockOwnerNear(gx, gy)
        for radius = 0, 5 do
            for dy = -radius, radius do
                for dx = -radius, radius do
                    local owner = getLockOwner(gx + dx, gy + dy)
                    if owner then return owner end
                end
            end
        end
        return nil
    end

    -- Boleh akses kalau bukan lock area, atau lock area milik LP sendiri
    local function canAccess(gx, gy)
        if not isLockArea(gx, gy) then return true end
        local owner = findLockOwnerNear(gx, gy)
        if not owner then return true end
        return owner == LP.UserId
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

    -- ========================================
    -- [4] PATHFINDING
    -- ========================================

    local function isWalkable(gx, gy)
        if gx < WORLD_MIN_X or gx > WORLD_MAX_X or gy < WORLD_MIN_Y or gy > 60 then
            return false
        end
        if isLockArea(gx, gy) and not canAccess(gx, gy) then return false end
        if worldData[gx] and worldData[gx][gy] and worldData[gx][gy][1] ~= nil then
            local l1 = worldData[gx][gy][1]
            local n  = string.lower(tostring((type(l1) == "table") and l1[1] or l1))
            if string.find(n, "sapling") then return true end
            if string.find(n, "door")    then return true end
            if string.find(n, "lock")    then return true end
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

    local function walkTo(gx, gy, StatusLabel, label)
        local Hitbox = getHitbox()
        if not Hitbox then return end
        local sx, sy = getGridPos()
        if sx == gx and sy == gy then return end
        local path = findSmartPath(sx, sy, gx, gy)
        if not path then
            moveTo(gx, gy)
            task.wait(0.2)
            return
        end
        for i, point in ipairs(path) do
            if not getgenv().DirtFarm_Enabled or _G.LatestRunToken ~= myToken then break end
            if StatusLabel then
                StatusLabel:SetText(string.format("Status: %s (%d/%d)", label or "Jalan", i, #path))
            end
            local px = math.floor(point.X / GRID_SIZE + 0.5)
            local py = math.floor(point.Y / GRID_SIZE + 0.5)
            moveTo(px, py)
            task.wait(getgenv().DirtFarm_StepDelay)
        end
        if not isAtPosition(gx, gy) then
            moveTo(gx, gy)
            task.wait(0.15)
        end
    end

    -- ========================================
    -- [5] BREAK & PLACE
    -- ========================================

    -- Break dari 1 tile di atas player (Fase 0, 1, 2)
    local function breakTileFromAbove(gx, gy, playerX)
        if not canAccess(gx, gy) then return end
        playerX = playerX or gx
        local pos = Vector2.new(gx, gy)
        while _G.LatestRunToken == myToken and getgenv().DirtFarm_Enabled do
            if not getTileLayer1(gx, gy) then break end
            if not canAccess(gx, gy) then break end
            if isAtPosition(playerX, gy + 1) then
                pcall(function() MovPacket:FireServer(worldPos(playerX, gy + 1)) end)
                PlayerFist:FireServer(pos)
                task.wait(getgenv().DirtFarm_BreakDelay)
            else
                moveTo(playerX, gy + 1)
                task.wait(0.1)
            end
        end
        while _G.LatestRunToken == myToken and getgenv().DirtFarm_Enabled do
            if not getTileLayer2(gx, gy) then break end
            if not canAccess(gx, gy) then break end
            if isAtPosition(playerX, gy + 1) then
                pcall(function() MovPacket:FireServer(worldPos(playerX, gy + 1)) end)
                PlayerFist:FireServer(pos)
                task.wait(getgenv().DirtFarm_BreakDelay)
            else
                moveTo(playerX, gy + 1)
                task.wait(0.1)
            end
        end
    end

    -- Break dari 2 tile di atas player (Fase 3 zigzag)
    local function breakTile(gx, gy, playerX)
        if not canAccess(gx, gy) then return end
        playerX = playerX or gx
        local playerY = gy + 2
        local pos = Vector2.new(gx, gy)
        while _G.LatestRunToken == myToken and getgenv().DirtFarm_Enabled do
            if not getTileLayer1(gx, gy) then break end
            if not canAccess(gx, gy) then break end
            if isAtPosition(playerX, playerY) then
                pcall(function() MovPacket:FireServer(worldPos(playerX, playerY)) end)
                PlayerFist:FireServer(pos)
                task.wait(getgenv().DirtFarm_BreakDelay)
            else
                moveTo(playerX, playerY)
                task.wait(0.1)
            end
        end
        while _G.LatestRunToken == myToken and getgenv().DirtFarm_Enabled do
            if not getTileLayer2(gx, gy) then break end
            if not canAccess(gx, gy) then break end
            if isAtPosition(playerX, playerY) then
                pcall(function() MovPacket:FireServer(worldPos(playerX, playerY)) end)
                PlayerFist:FireServer(pos)
                task.wait(getgenv().DirtFarm_BreakDelay)
            else
                moveTo(playerX, playerY)
                task.wait(0.1)
            end
        end
    end

    -- Inventory module, path sama seperti autopnb
    local InventoryMod
    pcall(function() InventoryMod = require(game.ReplicatedStorage.Modules.Inventory) end)

    local function getSlot(itemId)
        if not InventoryMod or not InventoryMod.Stacks then return nil, 0 end
        for slotIndex, data in pairs(InventoryMod.Stacks) do
            if type(data) == "table" and data.Id then
                if tostring(data.Id) == tostring(itemId) then
                    local amount = data.Amount or 0
                    if amount > 0 then
                        return slotIndex, amount
                    end
                end
            end
        end
        return nil, 0
    end

    local function placeItem(gx, gy, itemId)
        local slotIdx, amount = getSlot(itemId)
        if not slotIdx or amount <= 0 then return false end
        PlayerPlace:FireServer(Vector2.new(gx, gy), slotIdx, 1)
        task.wait(0.1)
        return true
    end

    local function harvestTile(gx, gy)
        if not canAccess(gx, gy) then return end
        local pos = Vector2.new(gx, gy)
        while _G.LatestRunToken == myToken and getgenv().DirtFarm_Enabled do
            local tile = worldData[gx] and worldData[gx][gy]
            if not tile or tile[1] == nil then break end
            local itemName = (type(tile[1]) == "table") and tile[1][1] or tile[1]
            if shouldSkip(itemName) then break end
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

    local function collectDropsInArea(minX, maxX, areaY, StatusLabel)
        StatusLabel:SetText("Status: Collecting drops...")
        for attempt = 1, 3 do
            local found = false
            local container = workspace:FindFirstChild("Drops")
            if container then
                for _, item in pairs(container:GetChildren()) do
                    if not getgenv().DirtFarm_Enabled or _G.LatestRunToken ~= myToken then break end
                    local pos = item:GetPivot().Position
                    local ix = math.floor(pos.X / GRID_SIZE + 0.5)
                    local iy = math.floor((pos.Y - OFFSET_Y) / GRID_SIZE + 0.5)
                    if ix >= minX and ix <= maxX and math.abs(iy - areaY) <= 3 then
                        found = true
                        walkTo(ix, iy, StatusLabel, "Collect")
                        task.wait(0.2)
                    end
                end
            end
            if not found then break end
            task.wait(0.3)
        end
    end

    local function plantAndHarvest(currentX, currentY, StatusLabel)
        local slotIdx = getSlot("dirt_sapling")
        if not slotIdx then
            Window:Notify("Tidak ada dirt_sapling di inventory!", 3)
            return
        end
        StatusLabel:SetText("Status: Menanam sapling...")
        local goLeft = currentX > 50
        local plantedPositions = {}
        for i = 1, 10 do
            if not getgenv().DirtFarm_Enabled or _G.LatestRunToken ~= myToken then break end
            slotIdx = getSlot("dirt_sapling")
            if not slotIdx then break end
            local plantX = goLeft and (currentX - i + 1) or (currentX + i - 1)
            plantX = math.clamp(plantX, WORLD_MIN_X + 2, WORLD_MAX_X - 2)
            if canAccess(plantX, currentY) then
                walkTo(plantX, currentY, StatusLabel, "Ke titik tanam")
                PlayerPlace:FireServer(Vector2.new(plantX, currentY), slotIdx, 1)
                table.insert(plantedPositions, {x = plantX, y = currentY})
                task.wait(0.15)
            end
        end
        for i = 30, 1, -1 do
            if not getgenv().DirtFarm_Enabled or _G.LatestRunToken ~= myToken then break end
            StatusLabel:SetText(string.format("Status: Menunggu panen (%ds)...", i))
            task.wait(1)
        end
        StatusLabel:SetText("Status: Memanen...")
        for _, plantPos in ipairs(plantedPositions) do
            if not getgenv().DirtFarm_Enabled or _G.LatestRunToken ~= myToken then break end
            if canAccess(plantPos.x, plantPos.y) then
                walkTo(plantPos.x, plantPos.y, StatusLabel, "Panen")
                harvestTile(plantPos.x, plantPos.y)
            end
        end
        if #plantedPositions > 0 then
            local xs = {}
            for _, p in ipairs(plantedPositions) do table.insert(xs, p.x) end
            collectDropsInArea(math.min(table.unpack(xs)), math.max(table.unpack(xs)), currentY, StatusLabel)
        end
    end

    -- ========================================
    -- [6] GRAVITY BYPASS
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
    -- [7] UI
    -- ========================================
    SubTab:AddSection("DIRT FARM")
    getgenv().SayzUI_Handles["DirtFarm_Master"] = SubTab:AddToggle("Enable Dirt Farm", getgenv().DirtFarm_Enabled, function(t)
        getgenv().DirtFarm_Enabled = t
    end)
    getgenv().SayzUI_Handles["DirtFarm_WoodFrame"] = SubTab:AddToggle("Fase Finish: Pasang Wooden Frame", getgenv().DirtFarm_WoodFrame, function(t)
        getgenv().DirtFarm_WoodFrame = t
    end)
    getgenv().SayzUI_Handles["DirtFarm_BreakDelay"] = SubTab:AddSlider("Break Delay", 0.01, 0.2, getgenv().DirtFarm_BreakDelay, function(val)
        getgenv().DirtFarm_BreakDelay = val
    end, 2)
    getgenv().SayzUI_Handles["DirtFarm_StepDelay"] = SubTab:AddSlider("Move Speed", 0.05, 0.2, getgenv().DirtFarm_StepDelay, function(val)
        getgenv().DirtFarm_StepDelay = val
    end, 2)

    SubTab:AddSection("STATUS")
    local StatusLabel = SubTab:AddLabel("Status  : Idle")
    local PhaseLabel  = SubTab:AddLabel("Fase    : -")
    local PosLabel    = SubTab:AddLabel("Posisi  : -")

    SubTab:AddSection("PANDUAN")
    SubTab:AddParagraph("Versi", "v12 - 03 Mar 2026\n- Fix fase 4: parity = startY%2, X=0,1,99,100 tidak di-place, scan bawah ke atas\n- Fix fase 0: parity (startY-1)%2, border X=0,1,99,100 break semua row\n- Fase 4: cy+2 naik ke atas (y besar = atas)sihin block yang sudah di-place")
    SubTab:AddParagraph("Alur Bot",
        "Fase 0: Bersihkan block di atas main door (skip door/bedrock/lock).\n" ..
        "Fase 1 & 2: Break kolom paling kiri (X=0,1) dan kanan (X=99,100) dari atas ke bawah.\n" ..
        "Fase 3: Break zigzag X=2-98. Player di atas top block, break 2 tile di bawah player, turun 2-2 sampai bawah.\n" ..
        "Fase 4: Place dirt zigzag dari bawah ke atas, 1 tile di atas player. Kalau dirt habis otomatis farming sapling.\n" ..
        "Fase 5: Scan dan bersihkan magma/lava, langsung ganti dengan dirt.\n" ..
        "Fase Finish (toggle): Pasang wooden_frame di X=1 dan X=99 tiap baris yang ada block-nya."
    )
    SubTab:AddParagraph("Catatan",
        "Bot otomatis skip bedrock, door, lock item, dan lock area milik orang lain.\n" ..
        "Lock area milik kamu sendiri tetap bisa diakses dan di-break.\n" ..
        "Door bisa dilewati bot.\n" ..
        "Matikan toggle untuk stop kapan saja."
    )

    -- ========================================
    -- [8] MAIN LOOP
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            if getgenv().DirtFarm_Enabled then
                pcall(function()

                    -- Detect startY = y bedrock, doorY = startY+1
                    local startY = WORLD_MIN_Y
                    local doorY  = WORLD_MIN_Y
                    for gx = WORLD_MIN_X, WORLD_MAX_X do
                        if worldData[gx] then
                            for gy = 60, WORLD_MIN_Y, -1 do
                                local tile = worldData[gx][gy]
                                if tile then
                                    local n1 = tile[1] and string.lower(tostring((type(tile[1])=="table") and tile[1][1] or tile[1])) or ""
                                    local n2 = tile[2] and string.lower(tostring((type(tile[2])=="table") and tile[2][1] or tile[2])) or ""
                                    if n1 == "bedrock" or n2 == "bedrock" then
                                        if gy > startY then
                                            startY = gy
                                            doorY  = gy + 1
                                        end
                                        break
                                    end
                                end
                            end
                        end
                    end

                    -- ============================
                    -- FASE 0: Clear block di atas door
                    -- Parity: X=2-98 hanya break row (startY-1)%2, X=0,1,99,100 break semua
                    -- ============================
                    PhaseLabel:SetText("Fase: 0 - Clear Atas Door")
                    do
                        local breakParity = (startY - 1) % 2
                        for gy = 60, doorY + 1, -1 do
                            if not getgenv().DirtFarm_Enabled or _G.LatestRunToken ~= myToken then break end
                            for gx = WORLD_MIN_X, WORLD_MAX_X do
                                if not getgenv().DirtFarm_Enabled or _G.LatestRunToken ~= myToken then break end
                                if not isTileEmpty(gx, gy) and canAccess(gx, gy) then
                                    local isBorder = (gx <= 1 or gx >= 99)
                                    local parityOk = (gy % 2) == breakParity
                                    if isBorder or parityOk then
                                        if getTileLayer1(gx, gy) or getTileLayer2(gx, gy) then
                                            PosLabel:SetText(string.format("Posisi: (%d,%d)", gx, gy))
                                            walkTo(gx, gy + 1, StatusLabel, "Clear atas")
                                            breakTileFromAbove(gx, gy)
                                        end
                                    end
                                end
                            end
                        end
                    end

                    -- ============================
                    -- FASE 1: Break kolom kiri (X=0 dan X=1)
                    -- ============================
                    PhaseLabel:SetText("Fase: 1 - Break Kiri")
                    for gy = startY - 1, WORLD_MIN_Y, -1 do
                        if not getgenv().DirtFarm_Enabled or _G.LatestRunToken ~= myToken then break end
                        local has0 = not isTileEmpty(0, gy) and canAccess(0, gy) and (getTileLayer1(0,gy) or getTileLayer2(0,gy))
                        local has1 = not isTileEmpty(1, gy) and canAccess(1, gy) and (getTileLayer1(1,gy) or getTileLayer2(1,gy))
                        if has0 or has1 then
                            PosLabel:SetText(string.format("Posisi: (0-1, %d)", gy))
                            walkTo(0, gy + 1, StatusLabel, "Break kiri")
                            if has0 then breakTileFromAbove(0, gy, 0) end
                            if has1 then breakTileFromAbove(1, gy, 0) end
                        end
                    end

                    -- ============================
                    -- FASE 2: Break kolom kanan (X=99 dan X=100)
                    -- ============================
                    PhaseLabel:SetText("Fase: 2 - Break Kanan")
                    for gy = startY - 1, WORLD_MIN_Y, -1 do
                        if not getgenv().DirtFarm_Enabled or _G.LatestRunToken ~= myToken then break end
                        local has99  = not isTileEmpty(99,  gy) and canAccess(99,  gy) and (getTileLayer1(99,gy)  or getTileLayer2(99,gy))
                        local has100 = not isTileEmpty(100, gy) and canAccess(100, gy) and (getTileLayer1(100,gy) or getTileLayer2(100,gy))
                        if has99 or has100 then
                            PosLabel:SetText(string.format("Posisi: (99-100, %d)", gy))
                            walkTo(100, gy + 1, StatusLabel, "Break kanan")
                            if has100 then breakTileFromAbove(100, gy, 100) end
                            if has99  then breakTileFromAbove(99,  gy, 100) end
                        end
                    end

                    -- ============================
                    -- FASE 3: Break langsung ke target
                    -- Scan semua tile breakable sekali,
                    -- langsung walkTo player ke (gx, gy+2) tanpa jalan row per row
                    -- Kalau list habis → scan ulang sekali, kalau tetap kosong → fase 4
                    -- ============================
                    PhaseLabel:SetText("Fase: 3 - Break Zigzag")

                    local function collectBreakTargets()
                        if not startY then return {} end
                        local targets = {}
                        -- Player selalu di startY+1, jangkauan break = 2 tile ke bawah
                        -- Jadi breakRow dimulai dari startY-1 lalu turun 2-2 (parity sama)
                        -- Contoh: startY=36 → breakRow = 35, 33, 31, 29, ...
                        local breakRow = startY - 1
                        while breakRow >= WORLD_MIN_Y do
                            for gx = 2, 98 do
                                if not isTileEmpty(gx, breakRow) and canAccess(gx, breakRow) then
                                    if getTileLayer1(gx, breakRow) or getTileLayer2(gx, breakRow) then
                                        table.insert(targets, {gx = gx, gy = breakRow})
                                    end
                                end
                            end
                            breakRow = breakRow - 2
                        end
                        return targets
                    end

                    -- Scan awal
                    local breakTargets = collectBreakTargets()

                    if #breakTargets == 0 then
                        StatusLabel:SetText("Status: Fase 3 - Tidak ada block, lanjut...")
                    else
                        local idx = 1
                        while true do
                            if not getgenv().DirtFarm_Enabled or _G.LatestRunToken ~= myToken then break end

                            -- Ambil target berikutnya dari list
                            local target = breakTargets[idx]

                            -- Kalau list sudah habis, scan ulang sekali
                            if not target then
                                breakTargets = collectBreakTargets()
                                if #breakTargets == 0 then break end  -- benar-benar habis → fase 4
                                idx = 1
                                target = breakTargets[idx]
                            end

                            -- Cek tile ini masih perlu di-break (mungkin sudah kosong karena efek sebelumnya)
                            if isTileEmpty(target.gx, target.gy) or not canAccess(target.gx, target.gy)
                            or (not getTileLayer1(target.gx, target.gy) and not getTileLayer2(target.gx, target.gy)) then
                                idx = idx + 1
                                continue
                            end

                            -- Langsung walkTo ke posisi player (target.gy + 2) tanpa jalan row per row
                            local playerRow = target.gy + 2
                            if not isAtPosition(target.gx, playerRow) then
                                walkTo(target.gx, playerRow, StatusLabel, "Ke target break")
                            end

                            PosLabel:SetText(string.format("Player:(%d,%d) Break:(%d,%d)", target.gx, playerRow, target.gx, target.gy))
                            breakTile(target.gx, target.gy, target.gx)

                            -- Tile sudah di-break, lanjut ke target berikutnya
                            idx = idx + 1
                        end
                    end

                    -- ============================
                    -- FASE 4: Place dirt
                    -- Scan semua tile yang perlu di-place:
                    --   X=2-98: hanya placeRow dengan parity sama dengan (startY+2)%2
                    --   X=0,1,99,100: semua row kosong
                    -- Batas atas: placeY <= startY-1 (tidak boleh place di topblock/atasnya)
                    -- Urutkan dari y paling bawah, naik ke atas
                    -- Player di placeY-1, place di placeY
                    -- ============================
                    PhaseLabel:SetText("Fase: 4 - Place Dirt")

                    local function collectPlaceTargets()
                        if not startY then return {} end
                        local targets = {}
                        -- Parity place = parity startY (topblock genap → place genap)
                        -- Scan dari startY+2 naik ke 60, step +2 (parity sama dengan startY)
                        -- X=0,1,99,100 tidak di-place (biarin kosong)
                        local placeRow = startY + 2
                        while placeRow <= 60 do
                            for gx = 2, 98 do
                                if isTileEmpty(gx, placeRow) and canAccess(gx, placeRow)
                                and not shouldSkip((function()
                                    local t = worldData[gx] and worldData[gx][placeRow]
                                    if not t or not t[1] then return nil end
                                    return (type(t[1])=="table") and t[1][1] or t[1]
                                end)()) then
                                    table.insert(targets, {gx = gx, gy = placeRow})
                                end
                            end
                            placeRow = placeRow + 2
                        end
                        -- Urutkan dari y paling bawah ke atas
                        table.sort(targets, function(a, b)
                            if a.gy ~= b.gy then return a.gy < b.gy end
                            return a.gx < b.gx
                        end)
                        return targets
                    end

                    local placeTargets = collectPlaceTargets()

                    if #placeTargets == 0 then
                        StatusLabel:SetText("Status: Fase 4 - Tidak ada tile kosong, lanjut...")
                    else
                        local pidx = 1
                        while true do
                            if not getgenv().DirtFarm_Enabled or _G.LatestRunToken ~= myToken then break end

                            local target = placeTargets[pidx]

                            -- List habis, scan ulang sekali
                            if not target then
                                placeTargets = collectPlaceTargets()
                                if #placeTargets == 0 then break end
                                pidx = 1
                                target = placeTargets[pidx]
                            end

                            -- Skip kalau sudah ada block (mungkin sudah di-place sebelumnya)
                            if not isTileEmpty(target.gx, target.gy) then
                                pidx = pidx + 1
                                continue
                            end

                            -- Player di placeY - 1 (1 tile di bawah target)
                            local playerY = target.gy - 1
                            if not isAtPosition(target.gx, playerY) then
                                walkTo(target.gx, playerY, StatusLabel, "Place dirt")
                            end

                            PosLabel:SetText(string.format("Player:(%d,%d) Place:(%d,%d)", target.gx, playerY, target.gx, target.gy))
                            local placed = placeItem(target.gx, target.gy, "dirt")
                            if not placed then
                                plantAndHarvest(target.gx, playerY, StatusLabel)
                                placeItem(target.gx, target.gy, "dirt")
                            end
                            task.wait(0.05)

                            pidx = pidx + 1
                        end
                    end

                    -- ============================
                    -- FASE 5: Bersihkan magma/lava → replace dirt
                    -- ============================
                    PhaseLabel:SetText("Fase: 5 - Bersihkan Magma")
                    do
                        local magmaFound = true
                        while magmaFound and getgenv().DirtFarm_Enabled and _G.LatestRunToken == myToken do
                            magmaFound = false
                            for gx = WORLD_MIN_X, WORLD_MAX_X do
                                if worldData[gx] then
                                    for gy = WORLD_MIN_Y, 60 do
                                        if not getgenv().DirtFarm_Enabled or _G.LatestRunToken ~= myToken then break end
                                        local tile = worldData[gx][gy]
                                        if tile and tile[1] then
                                            local n = string.lower(tostring((type(tile[1])=="table") and tile[1][1] or tile[1]))
                                            if (string.find(n, "magma") or string.find(n, "lava")) and canAccess(gx, gy) then
                                                magmaFound = true
                                                PosLabel:SetText(string.format("Magma: (%d,%d)", gx, gy))
                                                walkTo(gx, gy + 1, StatusLabel, "Ke magma")
                                                local pos = Vector2.new(gx, gy)
                                                while _G.LatestRunToken == myToken and getgenv().DirtFarm_Enabled do
                                                    local t2 = worldData[gx] and worldData[gx][gy]
                                                    if not t2 or not t2[1] then break end
                                                    local nn = string.lower(tostring((type(t2[1])=="table") and t2[1][1] or t2[1]))
                                                    if not (string.find(nn, "magma") or string.find(nn, "lava")) then break end
                                                    if isAtPosition(gx, gy + 1) then
                                                        pcall(function() MovPacket:FireServer(worldPos(gx, gy + 1)) end)
                                                        PlayerFist:FireServer(pos)
                                                        task.wait(getgenv().DirtFarm_BreakDelay)
                                                    else
                                                        moveTo(gx, gy + 1)
                                                        task.wait(0.1)
                                                    end
                                                end
                                                placeItem(gx, gy, "dirt")
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end

                    -- ============================
                    -- FASE FINISH: Wooden Frame di X=1 dan X=99
                    -- ============================
                    if getgenv().DirtFarm_WoodFrame then
                        PhaseLabel:SetText("Fase: Finish - Wooden Frame")
                        local rowsWithBlock = {}
                        for gy = WORLD_MIN_Y, startY do
                            for gx = 2, 98 do
                                if not isTileEmpty(gx, gy) then
                                    rowsWithBlock[gy] = true
                                    break
                                end
                            end
                        end
                        for gy = WORLD_MIN_Y, startY do
                            if not getgenv().DirtFarm_Enabled or _G.LatestRunToken ~= myToken then break end
                            if rowsWithBlock[gy] and canAccess(1, gy) then
                                PosLabel:SetText(string.format("Wooden Frame: (1,%d)", gy))
                                walkTo(1, gy + 1, StatusLabel, "Frame kiri")
                                placeItem(1, gy, "wooden_frame")
                            end
                        end
                        for gy = WORLD_MIN_Y, startY do
                            if not getgenv().DirtFarm_Enabled or _G.LatestRunToken ~= myToken then break end
                            if rowsWithBlock[gy] and canAccess(99, gy) then
                                PosLabel:SetText(string.format("Wooden Frame: (99,%d)", gy))
                                walkTo(99, gy + 1, StatusLabel, "Frame kanan")
                                placeItem(99, gy, "wooden_frame")
                            end
                        end
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
