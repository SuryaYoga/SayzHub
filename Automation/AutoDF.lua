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
    local MAX_SCAN_Y  = 60

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

    local function shouldSkip(itemName)
        if not itemName then return false end
        local n = string.lower(tostring(itemName))
        if string.find(n, "lock") then return true end
        if string.find(n, "door") then return true end
        if n == "bedrock"         then return true end
        return false
    end

    local function isLockArea(gx, gy)
        local tile = worldData[gx] and worldData[gx][gy]
        if not tile then return false end
        for _, layerData in pairs(tile) do
            if type(layerData) == "table" then
                for k, v in pairs(layerData) do
                    if tostring(v) == "lock_area" then return true end
                    if tostring(k) == "lock_area" then return true end
                end
            elseif type(layerData) == "string" then
                if string.lower(layerData) == "lock_area" then return true end
            end
        end
        return false
    end

    local function getTileLayer1(gx, gy)
        local tile = worldData[gx] and worldData[gx][gy]
        if not tile or tile[1] == nil then return nil end
        local itemName = (type(tile[1]) == "table") and tile[1][1] or tile[1]
        if shouldSkip(itemName) then return nil end 
        return itemName
    end

    local function isTileEmpty(gx, gy)
        local tile = worldData[gx] and worldData[gx][gy]
        return not tile or (tile[1] == nil and tile[2] == nil)
    end

    -- ========================================
    -- [3] ACTION FUNCTIONS
    -- ========================================

    local function breakTile(gx, gy, playerX)
        if isLockArea(gx, gy) then return end
        playerX = playerX or gx
        local playerY = gy + 2
        local pos = Vector2.new(gx, gy)

        for layer = 1, 2 do
            while _G.LatestRunToken == myToken and getgenv().DirtFarm_Enabled do
                local tile = worldData[gx] and worldData[gx][gy]
                if not tile or tile[layer] == nil then break end
                local itemName = (type(tile[layer]) == "table") and tile[layer][1] or tile[layer]
                if shouldSkip(itemName) then break end

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
    end

    local function getDirtSlot()
        local InventoryMod = require(LP.PlayerScripts:FindFirstChild("InventoryModule") or LP.PlayerScripts:FindFirstChild("Inventory"))
        local stacks = InventoryMod.Stacks or InventoryMod.stacks
        if not stacks then return nil end
        for i, stack in pairs(stacks) do
            if stack and tostring(stack.Id) == "dirt" then return i, stack.Amount or 0 end
        end
        return nil, 0
    end

    local function placeDirt(gx, gy)
        local slotIdx, amount = getDirtSlot()
        if not slotIdx or amount <= 0 then return false end
        PlayerPlace:FireServer(Vector2.new(gx, gy), slotIdx, 1)
        task.wait(0.08)
        return true
    end

    -- ========================================
    -- [4] UI & GRAVITY BYPASS
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

    SubTab:AddSection("DIRT FARM")
    getgenv().SayzUI_Handles["DirtFarm_Master"] = SubTab:AddToggle("Enable Dirt Farm", getgenv().DirtFarm_Enabled, function(t) getgenv().DirtFarm_Enabled = t end)
    
    SubTab:AddSection("STATUS")
    local StatusLabel = SubTab:AddLabel("Status : Idle")
    local PhaseLabel  = SubTab:AddLabel("Fase   : -")
    local PosLabel    = SubTab:AddLabel("Posisi : -")

    -- ========================================
    -- [5] MAIN LOOP
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            if getgenv().DirtFarm_Enabled then
                pcall(function()
                    -- [DETEKSI TOPBLOCK] Abaikan Door/Lock/Bedrock
                    local startY = WORLD_MIN_Y
                    for gx = WORLD_MIN_X, WORLD_MAX_X do
                        for gy = MAX_SCAN_Y, WORLD_MIN_Y, -1 do
                            if getTileLayer1(gx, gy) then
                                if gy > startY then startY = gy end
                                break
                            end
                        end
                    end

                    -- FASE 1 & 2 (Kolom Pinggir) - Singkat
                    PhaseLabel:SetText("Fase: 1 & 2 - Pembersihan Samping")
                    for _, xSide in ipairs({0, 1, 99, 100}) do
                        for gy = MAX_SCAN_Y, WORLD_MIN_Y, -1 do
                            if not getgenv().DirtFarm_Enabled then break end
                            if not isTileEmpty(xSide, gy) and not isLockArea(xSide, gy) then
                                walkTo(xSide, gy + 1, StatusLabel, "Cleaning Side")
                                breakTile(xSide, gy, xSide)
                            end
                        end
                    end

                    -- FASE 3: BREAK ZIGZAG (Mulai dari startY)
                    PhaseLabel:SetText("Fase: 3 - Break Zigzag")
                    local currentPlayerRow = startY + 1
                    local goingRight = true
                    while currentPlayerRow - 2 >= WORLD_MIN_Y do
                        if not getgenv().DirtFarm_Enabled then break end
                        local breakRow = currentPlayerRow - 2
                        local xStart, xEnd, xStep = goingRight and 2 or 98, goingRight and 98 or 2, goingRight and 1 or -1

                        for gx = xStart, xEnd, xStep do
                            if not getgenv().DirtFarm_Enabled then break end
                            if getTileLayer1(gx, breakRow) and not isLockArea(gx, breakRow) then
                                if not isAtPosition(gx, currentPlayerRow) then moveTo(gx, currentPlayerRow) end
                                breakTile(gx, breakRow, gx)
                            end
                        end
                        currentPlayerRow = currentPlayerRow - 2
                        goingRight = not goingRight
                    end

                    -- FASE 4: PLACE DIRT (Naik melintasi Pintu)
                    PhaseLabel:SetText("Fase: 4 - Place Dirt")
                    local cy = WORLD_MIN_Y
                    goingRight = true
                    while cy <= MAX_SCAN_Y do
                        if not getgenv().DirtFarm_Enabled then break end
                        local xStart, xEnd, xStep = goingRight and 2 or 98, goingRight and 98 or 2, goingRight and 1 or -1
                        local hasPlaced = false

                        for gx = xStart, xEnd, xStep do
                            local placeY = cy + 1
                            -- Pasang jika KOSONG (bukan Pintu/Lock) dan bukan area kunci
                            if isTileEmpty(gx, placeY) and not isLockArea(gx, placeY) then
                                if not isAtPosition(gx, cy) then moveTo(gx, cy) end
                                if placeDirt(gx, placeY) then hasPlaced = true end
                            end
                        end
                        
                        -- Jika sudah di atas tanah asli (startY) dan baris sudah kosong semua, berhenti
                        if cy > startY and not hasPlaced then break end
                        
                        cy = cy + 2
                        goingRight = not goingRight
                    end

                    -- SELESAI
                    getgenv().DirtFarm_Enabled = false
                    if getgenv().SayzUI_Handles["DirtFarm_Master"] then getgenv().SayzUI_Handles["DirtFarm_Master"]:Set(false) end
                    Window:Notify("Farming Selesai!", 3)
                end)
            end
            task.wait(1)
        end
    end)
end
