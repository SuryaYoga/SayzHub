return function(SubTab, Window, myToken)
    -- ========================================
    -- [1] SETUP & VARIABLES
    -- ========================================
    local PnB = getgenv().SayzSettings.PnB
    local worldData = require(game.ReplicatedStorage.WorldTiles)
    local LP = game.Players.LocalPlayer
    local movementModule = require(LP.PlayerScripts.PlayerMovement)
    local IM = require(game:GetService("ReplicatedStorage").Managers.ItemsManager)

    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Remotes       = ReplicatedStorage:WaitForChild("Remotes")
    local Managers      = ReplicatedStorage:WaitForChild("Managers")
    local PlayerDrop    = Remotes:FindFirstChild("PlayerDrop")
    local UIPromptEvent = Managers:WaitForChild("UIManager"):FindFirstChild("UIPromptEvent")

    local UIManager
    pcall(function() UIManager = require(Managers:WaitForChild("UIManager")) end)

    local InventoryMod
    pcall(function() InventoryMod = require(ReplicatedStorage.Modules.Inventory) end)

    -- State machine state
    -- States: "Breaking" → "Collecting" → "Dropping" → "Placing" → "Waiting"
    _G.LastPnBState = "Waiting"

    -- Smart Collect globals
    getgenv().SmartCollect_Enabled = getgenv().SmartCollect_Enabled or false
    getgenv().StepDelay = getgenv().StepDelay or 0.05
    getgenv().AvoidanceStrength = getgenv().AvoidanceStrength or 50
    getgenv().TakeGems_PnB = getgenv().TakeGems_PnB or false
    getgenv().ItemBlacklist_PnB = getgenv().ItemBlacklist_PnB or {}

    -- Auto Drop globals
    getgenv().AutoDrop_PnB_Enabled = getgenv().AutoDrop_PnB_Enabled or false
    local DropSettings = {
        TargetID    = nil,
        Scanning    = false,
        MaxStack    = 200,
        KeepAmount  = 200,
        DropDelay   = 0.5,
        DropPoint   = nil,
        -- ReturnPoint TIDAK ada — otomatis pakai PnB.OriginGrid
    }

    local LIMIT = { MIN_X = 0, MAX_X = 100, MIN_Y = 6, MAX_Y = 60 }
    local lockedDoors = {}
    local badItems = {}
    local doorDatabase = {}

    -- ========================================
    -- [2] UI ELEMENTS
    -- ========================================

    SubTab:AddSection("EKSEKUSI")
    getgenv().SayzUI_Handles["PnB_Master"] = SubTab:AddToggle("Master Switch", PnB.Master, function(t) PnB.Master = t end)
    getgenv().SayzUI_Handles["PnB_Place"] = SubTab:AddToggle("Enable Place", PnB.Place, function(t) PnB.Place = t end)
    getgenv().SayzUI_Handles["PnB_Break"] = SubTab:AddToggle("Enable Break", PnB.Break, function(t) PnB.Break = t end)

    SubTab:AddSection("SMART COLLECT (Integrasi PnB)")
    getgenv().SayzUI_Handles["SmartCollect_PnB"] = SubTab:AddToggle("Enable Smart Collect (Setelah Break)", getgenv().SmartCollect_Enabled, function(t)
        getgenv().SmartCollect_Enabled = t
        if t then
            doorDatabase = {}
            for gx, columns in pairs(worldData) do
                for gy, tileData in pairs(columns) do
                    local l1 = tileData[1]
                    local itemName = (type(l1) == "table") and l1[1] or l1
                    if itemName and string.find(string.lower(tostring(itemName)), "door") then
                        doorDatabase[gx .. "," .. gy] = true
                    end
                end
            end
        end
    end)
    getgenv().SayzUI_Handles["TakeGems_PnB"] = SubTab:AddToggle("Collect Gems (Smart Collect)", getgenv().TakeGems_PnB, function(t)
        getgenv().TakeGems_PnB = t
    end)
    getgenv().SayzUI_Handles["StepDelaySlider_PnB"] = SubTab:AddSlider("Movement Speed (Smart Collect)", 0.01, 0.2, getgenv().StepDelay, function(val)
        getgenv().StepDelay = val
    end, 2)

    local CollectStatusLabel = SubTab:AddLabel("Collect Status: Idle")

    -- ========================================
    -- AUTO DROP SECTION
    -- ========================================
    SubTab:AddSection("AUTO DROP (Integrasi PnB)")

    getgenv().SayzUI_Handles["AutoDrop_PnB"] = SubTab:AddToggle("Enable Auto Drop (Setelah Collect)", getgenv().AutoDrop_PnB_Enabled, function(t)
        getgenv().AutoDrop_PnB_Enabled = t
    end)

    SubTab:AddButton("Scan ID Item (Drop Manual 1x)", function()
        DropSettings.Scanning = true
        Window:Notify("Drop 1 item manual untuk scan ID-nya!", 3, "info")
    end)
    local DropScanLabel   = SubTab:AddLabel("Drop Target ID : None")
    local DropAmountLabel = SubTab:AddLabel("Jumlah Item    : 0")

    getgenv().SayzUI_Handles["AutoDrop_MaxStack"] = SubTab:AddInput("Max Stack (drop jika melebihi)", tostring(DropSettings.MaxStack), function(v)
        local val = tonumber(v)
        if val and val > 0 then DropSettings.MaxStack = val end
    end)
    getgenv().SayzUI_Handles["AutoDrop_KeepAmt"] = SubTab:AddInput("Keep Amount (sisa setelah drop)", tostring(DropSettings.KeepAmount), function(v)
        local val = tonumber(v)
        if val and val >= 0 then DropSettings.KeepAmount = val end
    end)
    getgenv().SayzUI_Handles["AutoDrop_DropDelay"] = SubTab:AddSlider("Drop Delay", 0.1, 2, DropSettings.DropDelay, function(val)
        DropSettings.DropDelay = val
    end, 1)

    -- Drop Point: set posisi + manual input
    local DropPointLabel = SubTab:AddLabel("Drop Point : Belum diset")

    local function updateDropPointLabel()
        if DropSettings.DropPoint then
            DropPointLabel:SetText(string.format("Drop Point : (%d, %d)", DropSettings.DropPoint.x, DropSettings.DropPoint.y))
        end
    end

    local function getCurrentGridPos()
        local HitboxFolder = workspace:FindFirstChild("Hitbox")
        local MyHitbox = HitboxFolder and HitboxFolder:FindFirstChild(LP.Name)
        if MyHitbox then
            return {
                x = math.floor(MyHitbox.Position.X / 4.5 + 0.5),
                y = math.floor(MyHitbox.Position.Y / 4.5 + 0.5)
            }
        end
        local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if root then
            return {
                x = math.floor(root.Position.X / 4.5 + 0.5),
                y = math.floor(root.Position.Y / 4.5 + 0.5)
            }
        end
        return nil
    end

    SubTab:AddButton("📍 Set Drop Point (Posisi Sekarang)", function()
        local pos = getCurrentGridPos()
        if pos then
            DropSettings.DropPoint = pos
            updateDropPointLabel()
            Window:Notify(string.format("Drop Point: (%d, %d)", pos.x, pos.y), 2, "ok")
        else
            Window:Notify("Gagal baca posisi! Isi manual di bawah.", 2, "danger")
        end
    end)
    SubTab:AddInput("Drop X (manual)", "0", function(v)
        local val = tonumber(v)
        if val then
            DropSettings.DropPoint = DropSettings.DropPoint or {x = 0, y = 0}
            DropSettings.DropPoint.x = math.floor(val)
            updateDropPointLabel()
        end
    end)
    SubTab:AddInput("Drop Y (manual)", "0", function(v)
        local val = tonumber(v)
        if val then
            DropSettings.DropPoint = DropSettings.DropPoint or {x = 0, y = 0}
            DropSettings.DropPoint.y = math.floor(val)
            updateDropPointLabel()
        end
    end)

    -- Info: Return Point otomatis dari Origin PnB
    SubTab:AddLabel("↩ Return Point : Otomatis (Origin PnB)")

    local DropStatusLabel = SubTab:AddLabel("Drop Status: Idle")

    -- ========================================
    -- SCANNER
    -- ========================================
    SubTab:AddSection("SCANNER")
    SubTab:AddButton("Scan ID Item (PnB)", function()
        PnB.Scanning = true
        Window:Notify("Pasang 1 blok manual untuk scan!", 3, "info")
    end)
    local InfoLabel = SubTab:AddLabel("ID Aktif: None")
    local StokLabel = SubTab:AddLabel("Total Stok: 0")

    SubTab:AddSection("SETTING")
    getgenv().SayzUI_Handles["PnB_SpeedScale"] = SubTab:AddInput("Speed Scale (Min 0.1)", "1", function(v)
        local val = tonumber(v) or 1
        if val < 0.1 then val = 0.1 end
        PnB.DelayScale = val
        PnB.ActualDelay = val * 0.12
    end)

    SubTab:AddSection("GRID TARGET (5x5)")
    SubTab:AddGridSelector(function(selectedTable)
        PnB.SelectedTiles = selectedTable
        local char = LP.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            PnB.OriginGrid = {
                x = math.floor((root.Position.X / 4.475) + 0.5),
                y = math.floor(((root.Position.Y - 2.5) / 4.435) + 0.5)
            }
        end
    end)

    getgenv().SayzUI_Handles["PnB_LockPosition"] = SubTab:AddToggle("Lock Position", PnB.LockPosition, function(t)
        PnB.LockPosition = t
    end)

    SubTab:AddButton("Refresh Position / Set Origin", function()
        local char = LP.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            PnB.OriginGrid = {
                x = math.floor((root.Position.X / 4.475) + 0.5),
                y = math.floor(((root.Position.Y - 2.5) / 4.435) + 0.5)
            }
            Window:Notify("Position Refreshed!", 2, "ok")
        end
    end)

    getgenv().SayzUI_Handles["PnB_BreakMode"] = SubTab:AddDropdown("Multi-Break Mode", {"Mode 1 (Fokus)", "Mode 2 (Rata)"}, PnB.BreakMode, function(v)
        PnB.BreakMode = v
    end)

    -- ========================================
    -- [3] HELPER FUNCTIONS
    -- ========================================

    local function getActiveAmount()
        local total = 0
        local success, invModule = pcall(function()
            return require(game.ReplicatedStorage.Modules.Inventory)
        end)
        if success and invModule and invModule.Stacks then
            local targetIndex = tonumber(PnB.TargetID)
            local baseStack = invModule.Stacks[targetIndex]
            if baseStack and baseStack.Id then
                local targetItemId = baseStack.Id
                for _, stack in pairs(invModule.Stacks) do
                    if stack and stack.Id == targetItemId then
                        total = total + (stack.Amount or 0)
                    end
                end
            end
        end
        return total
    end

    local function updatePnBVisuals()
        if _G.LatestRunToken ~= myToken then return end
        pcall(function()
            InfoLabel:SetText("ID Aktif: " .. tostring(PnB.TargetID or "None"))
            StokLabel:SetText("Total Stok: " .. getActiveAmount())
        end)
        pcall(function()
            if DropSettings.TargetID then
                DropScanLabel:SetText("Drop Target ID : " .. tostring(DropSettings.TargetID))
                -- Hitung jumlah drop target
                local total = 0
                if InventoryMod and InventoryMod.Stacks then
                    for _, data in pairs(InventoryMod.Stacks) do
                        if type(data) == "table" and data.Id then
                            if tostring(data.Id) == tostring(DropSettings.TargetID) then
                                total = total + (data.Amount or 1)
                            end
                        end
                    end
                end
                DropAmountLabel:SetText("Jumlah Item    : " .. total)
            end
        end)
    end

    -- Hook Scanner (PnB item scan + Drop item scan)
    if not _G.OldHookSet then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            local args = {...}
            -- PnB scanner (place item)
            if _G.LatestRunToken == myToken and PnB.Scanning and self.Name == "PlayerPlaceItem" and method == "FireServer" then
                PnB.TargetID = args[2]
                PnB.Scanning = false
                Window:Notify("ID Scanned: " .. tostring(args[2]), 2, "ok")
            end
            -- Drop scanner (drop item)
            if _G.LatestRunToken == myToken and DropSettings.Scanning and method == "FireServer" then
                if self == PlayerDrop then
                    local slotIndex = args[1]
                    if slotIndex and InventoryMod and InventoryMod.Stacks then
                        local data = InventoryMod.Stacks[slotIndex]
                        if data and data.Id then
                            DropSettings.TargetID = tostring(data.Id)
                            DropSettings.Scanning = false
                            DropScanLabel:SetText("Drop Target ID : " .. DropSettings.TargetID)
                            Window:Notify("Drop ID Scanned: " .. DropSettings.TargetID, 2, "ok")
                        end
                    end
                end
            end
            return oldNamecall(self, ...)
        end)
        _G.OldHookSet = true
    end

    -- ========================================
    -- [4] SMART COLLECT CORE FUNCTIONS
    -- ========================================

    local function isWalkable(gx, gy)
        if gx < LIMIT.MIN_X or gx > LIMIT.MAX_X or gy < LIMIT.MIN_Y or gy > LIMIT.MAX_Y then
            return false, false
        end
        if lockedDoors[gx .. "," .. gy] then
            return false, false
        end
        local hasBlacklist = false
        local folders = {"Drops"}
        if getgenv().TakeGems_PnB then table.insert(folders, "Gems") end
        for _, folderName in pairs(folders) do
            local container = workspace:FindFirstChild(folderName)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    local itPos = item:GetPivot().Position
                    local itX = math.floor(itPos.X / 4.5 + 0.5)
                    local itY = math.floor(itPos.Y / 4.5 + 0.5)
                    if itX == gx and itY == gy then
                        local id = item:GetAttribute("id") or item.Name
                        if getgenv().ItemBlacklist_PnB[id] then
                            hasBlacklist = true
                        end
                    end
                end
            end
        end
        if worldData[gx] and worldData[gx][gy] then
            local l1 = worldData[gx][gy][1]
            local itemName = (type(l1) == "table") and l1[1] or l1
            if itemName then
                local n = string.lower(tostring(itemName))
                if string.find(n, "door") or string.find(n, "frame") then
                    return true, hasBlacklist
                end
                return false, false
            end
        end
        return true, hasBlacklist
    end

    -- isWalkable versi drop (tanpa blacklist item, tidak perlu berat)
    local function isWalkableDrop(gx, gy)
        if gx < LIMIT.MIN_X or gx > LIMIT.MAX_X or gy < LIMIT.MIN_Y or gy > LIMIT.MAX_Y then
            return false
        end
        if lockedDoors[gx .. "," .. gy] then
            return false
        end
        if worldData[gx] and worldData[gx][gy] then
            local l1 = worldData[gx][gy][1]
            local itemName = (type(l1) == "table") and l1[1] or l1
            if itemName then
                local n = string.lower(tostring(itemName))
                local SOLID_TILES = {
                    bedrock = true, dirt = true, stone = true,
                    gravel = true, small_lock = true,
                }
                if SOLID_TILES[n] then return false end
                return true
            end
        end
        return true
    end

    local function findSmartPath(startX, startY, targetX, targetY)
        local queue = {{x = startX, y = startY, path = {}, cost = 0}}
        local visited = {[startX .. "," .. startY] = 0}
        local directions = {
            {x = 1, y = 0}, {x = -1, y = 0},
            {x = 0, y = 1}, {x = 0, y = -1}
        }
        local limitCount = 0
        while #queue > 0 do
            if _G.LatestRunToken ~= myToken then break end
            limitCount = limitCount + 1
            if limitCount > 4000 then break end
            table.sort(queue, function(a, b) return a.cost < b.cost end)
            local current = table.remove(queue, 1)
            if current.x == targetX and current.y == targetY then
                return current.path
            end
            for _, d in ipairs(directions) do
                local nx, ny = current.x + d.x, current.y + d.y
                local walkable, isBlacklisted = isWalkable(nx, ny)
                if walkable then
                    local moveCost = isBlacklisted and getgenv().AvoidanceStrength or 1
                    local newTotalCost = current.cost + moveCost
                    if not visited[nx .. "," .. ny] or newTotalCost < visited[nx .. "," .. ny] then
                        visited[nx .. "," .. ny] = newTotalCost
                        local newPath = {unpack(current.path)}
                        table.insert(newPath, Vector3.new(nx * 4.5, ny * 4.5, 0))
                        table.insert(queue, {
                            x = nx,
                            y = ny,
                            path = newPath,
                            cost = newTotalCost
                        })
                    end
                end
            end
        end
        return nil
    end

    -- findSmartPath versi drop (cost flat, pakai isWalkableDrop)
    local function findSmartPathDrop(startX, startY, targetX, targetY)
        local queue = {{x = startX, y = startY, path = {}, cost = 0}}
        local visited = {[startX .. "," .. startY] = 0}
        local directions = {
            {x = 1, y = 0}, {x = -1, y = 0},
            {x = 0, y = 1}, {x = 0, y = -1}
        }
        local limitCount = 0
        while #queue > 0 do
            if _G.LatestRunToken ~= myToken then break end
            limitCount = limitCount + 1
            if limitCount > 4000 then break end
            table.sort(queue, function(a, b) return a.cost < b.cost end)
            local current = table.remove(queue, 1)
            if current.x == targetX and current.y == targetY then
                return current.path
            end
            for _, d in ipairs(directions) do
                local nx, ny = current.x + d.x, current.y + d.y
                if isWalkableDrop(nx, ny) then
                    local newCost = current.cost + 1
                    if not visited[nx .. "," .. ny] or newCost < visited[nx .. "," .. ny] then
                        visited[nx .. "," .. ny] = newCost
                        local newPath = {unpack(current.path)}
                        table.insert(newPath, Vector3.new(nx * 4.5, ny * 4.5, 0))
                        table.insert(queue, {
                            x = nx,
                            y = ny,
                            path = newPath,
                            cost = newCost
                        })
                    end
                end
            end
        end
        return nil
    end

    local function getDropsInGrid(baseGrid)
        local drops = {}
        local selectedList = {}
        for coordKey, active in pairs(PnB.SelectedTiles) do
            if active then
                local parts = string.split(coordKey, ",")
                table.insert(selectedList, {
                    ox = tonumber(parts[1]),
                    oy = tonumber(parts[2])
                })
            end
        end
        local gridSet = {}
        for _, offset in ipairs(selectedList) do
            local tx = baseGrid.x + offset.ox
            local ty = baseGrid.y + offset.oy
            gridSet[tx .. "," .. ty] = true
        end
        local folders = {"Drops"}
        if getgenv().TakeGems_PnB then table.insert(folders, "Gems") end
        for _, folderName in pairs(folders) do
            local container = workspace:FindFirstChild(folderName)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    if not badItems[item] then
                        local itPos = item:GetPivot().Position
                        local itX = math.floor(itPos.X / 4.5 + 0.5)
                        local itY = math.floor(itPos.Y / 4.5 + 0.5)
                        if gridSet[itX .. "," .. itY] then
                            local id = item:GetAttribute("id") or item.Name
                            if not getgenv().ItemBlacklist_PnB[id] then
                                table.insert(drops, item)
                            end
                        end
                    end
                end
            end
        end
        return drops
    end

    local function walkToPoint(Hitbox, targetItem)
        local sx = math.floor(Hitbox.Position.X / 4.5 + 0.5)
        local sy = math.floor(Hitbox.Position.Y / 4.5 + 0.5)
        local tx = math.floor(targetItem:GetPivot().Position.X / 4.5 + 0.5)
        local ty = math.floor(targetItem:GetPivot().Position.Y / 4.5 + 0.5)
        local path = findSmartPath(sx, sy, tx, ty)
        if not path then
            badItems[targetItem] = true
            return false
        end
        for i, point in ipairs(path) do
            if _G.LatestRunToken ~= myToken or not PnB.Master or not getgenv().SmartCollect_Enabled then break end
            CollectStatusLabel:SetText("Collect: Walking (" .. i .. "/" .. #path .. ")")
            Hitbox.CFrame = CFrame.new(point.X, point.Y, Hitbox.Position.Z)
            movementModule.Position = Hitbox.Position
            task.wait(getgenv().StepDelay)
            local char = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if char then
                local dist = (Vector2.new(char.Position.X, char.Position.Y) - Vector2.new(point.X, point.Y)).Magnitude
                if dist > 5 then
                    local px = math.floor(point.X / 4.5 + 0.5)
                    local py = math.floor(point.Y / 4.5 + 0.5)
                    lockedDoors[px .. "," .. py] = true
                    return false
                end
            end
        end
        return true
    end

    local function walkBackToOrigin(Hitbox, originGrid)
        local sx = math.floor(Hitbox.Position.X / 4.5 + 0.5)
        local sy = math.floor(Hitbox.Position.Y / 4.5 + 0.5)
        local path = findSmartPath(sx, sy, originGrid.x, originGrid.y)
        if not path then return end
        for i, point in ipairs(path) do
            if _G.LatestRunToken ~= myToken or not PnB.Master then break end
            CollectStatusLabel:SetText("Collect: Returning (" .. i .. "/" .. #path .. ")")
            Hitbox.CFrame = CFrame.new(point.X, point.Y, Hitbox.Position.Z)
            movementModule.Position = Hitbox.Position
            task.wait(getgenv().StepDelay)
        end
    end

    -- ========================================
    -- [5] AUTO DROP CORE FUNCTIONS
    -- ========================================

    local function GetDropItemAmount()
        local total = 0
        if not InventoryMod or not InventoryMod.Stacks then return total end
        for _, data in pairs(InventoryMod.Stacks) do
            if type(data) == "table" and data.Id then
                if tostring(data.Id) == tostring(DropSettings.TargetID) then
                    total = total + (data.Amount or 1)
                end
            end
        end
        return total
    end

    local function GetSlotByDropItemID()
        if not InventoryMod or not InventoryMod.Stacks then return nil end
        for slotIndex, data in pairs(InventoryMod.Stacks) do
            if type(data) == "table" and data.Id then
                if tostring(data.Id) == tostring(DropSettings.TargetID) then
                    if not data.Amount or data.Amount > 0 then
                        return slotIndex
                    end
                end
            end
        end
        return nil
    end

    local function SnapshotUI()
        local snapshot = {}
        pcall(function()
            for _, gui in pairs(LP.PlayerGui:GetChildren()) do
                if gui:IsA("ScreenGui") then
                    snapshot[gui.Name] = gui.Enabled
                end
            end
        end)
        return snapshot
    end

    local function RestoreUIFromSnapshot(snapshot)
        pcall(function()
            if UIManager and type(UIManager.ClosePrompt) == "function" then
                UIManager:ClosePrompt()
            end
        end)
        pcall(function()
            for _, gui in pairs(LP.PlayerGui:GetDescendants()) do
                if gui:IsA("Frame") and string.find(string.lower(gui.Name), "prompt") then
                    gui.Visible = false
                end
            end
        end)
        task.wait(0.1)
        pcall(function()
            for _, gui in pairs(LP.PlayerGui:GetChildren()) do
                if gui:IsA("ScreenGui") and snapshot[gui.Name] ~= nil then
                    gui.Enabled = snapshot[gui.Name]
                end
            end
        end)
    end

    local function ExecuteDropBatch(slotIndex, dropAmount)
        if not PlayerDrop or not UIPromptEvent then return false end
        pcall(function() PlayerDrop:FireServer(slotIndex) end)
        task.wait(0.2)
        pcall(function()
            UIPromptEvent:FireServer({
                ButtonAction = "drp",
                Inputs = { amt = tostring(dropAmount) }
            })
        end)
        task.wait(0.1)
        pcall(function()
            for _, gui in pairs(LP.PlayerGui:GetDescendants()) do
                if gui:IsA("Frame") and string.find(string.lower(gui.Name), "prompt") then
                    gui.Visible = false
                end
            end
        end)
        return true
    end

    local function DoDropAll(snapshot)
        while _G.LatestRunToken == myToken and PnB.Master and getgenv().AutoDrop_PnB_Enabled do
            local current = GetDropItemAmount()
            local toDrop  = current - DropSettings.KeepAmount
            if toDrop <= 0 then break end
            local slot = GetSlotByDropItemID()
            if not slot then break end
            local batchAmount = math.min(toDrop, 200)
            DropStatusLabel:SetText(string.format("Drop: Dropping %d...", batchAmount))
            local ok = ExecuteDropBatch(slot, batchAmount)
            if not ok then break end
            task.wait(DropSettings.DropDelay)
        end
        RestoreUIFromSnapshot(snapshot)
    end

    -- Jalan ke Drop Point menggunakan findSmartPathDrop (retry saat stuck)
    local function WalkToDropPoint(Hitbox, targetX, targetY)
        local startZ = Hitbox.Position.Z
        local maxRetry = 10
        local retry = 0
        while _G.LatestRunToken == myToken and PnB.Master and getgenv().AutoDrop_PnB_Enabled do
            local curX = math.floor(Hitbox.Position.X / 4.5 + 0.5)
            local curY = math.floor(Hitbox.Position.Y / 4.5 + 0.5)
            if curX == targetX and curY == targetY then break end
            retry = retry + 1
            if retry > maxRetry then break end
            local path = findSmartPathDrop(curX, curY, targetX, targetY)
            if not path then break end
            local stuck = false
            for i, point in ipairs(path) do
                if not PnB.Master or not getgenv().AutoDrop_PnB_Enabled or _G.LatestRunToken ~= myToken then return end
                DropStatusLabel:SetText(string.format("Drop: Jalan ke Drop Point (%d/%d)...", i, #path))
                Hitbox.CFrame = CFrame.new(point.X, point.Y, startZ)
                movementModule.Position = Hitbox.Position
                task.wait(getgenv().StepDelay)
                local char = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                if char then
                    local dist = (Vector2.new(char.Position.X, char.Position.Y) - Vector2.new(point.X, point.Y)).Magnitude
                    if dist > 5 then
                        local px = math.floor(point.X / 4.5 + 0.5)
                        local py = math.floor(point.Y / 4.5 + 0.5)
                        lockedDoors[px .. "," .. py] = true
                        stuck = true
                        break
                    end
                end
            end
            if not stuck then break end
        end
    end

    -- Balik ke Origin dari Drop Point (pakai findSmartPathDrop juga)
    local function WalkBackFromDrop(Hitbox, originGrid)
        local startZ = Hitbox.Position.Z
        local sx = math.floor(Hitbox.Position.X / 4.5 + 0.5)
        local sy = math.floor(Hitbox.Position.Y / 4.5 + 0.5)
        local path = findSmartPathDrop(sx, sy, originGrid.x, originGrid.y)
        if not path then return end
        for i, point in ipairs(path) do
            if _G.LatestRunToken ~= myToken or not PnB.Master then break end
            DropStatusLabel:SetText(string.format("Drop: Balik ke Origin (%d/%d)...", i, #path))
            Hitbox.CFrame = CFrame.new(point.X, point.Y, startZ)
            movementModule.Position = Hitbox.Position
            task.wait(getgenv().StepDelay)
        end
        DropStatusLabel:SetText("Drop Status: Idle")
    end

    -- ========================================
    -- [6] GRAVITY BYPASS
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait()
            if getgenv().SmartCollect_Enabled and _G.LastPnBState == "Collecting" then
                pcall(function()
                    if movementModule.VelocityY < 0 then movementModule.VelocityY = 0 end
                    movementModule.Grounded = true
                end)
            end
            if getgenv().AutoDrop_PnB_Enabled and _G.LastPnBState == "Dropping" then
                pcall(function()
                    if movementModule.VelocityY < 0 then movementModule.VelocityY = 0 end
                    movementModule.Grounded = true
                end)
            end
        end
    end)

    -- ========================================
    -- [7] MAIN LOOP — STRICT STATE MACHINE
    -- Break → Collecting → Dropping → Placing → Waiting
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            if PnB.Master then
                pcall(function()
                    local char = LP.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    if not root then return end

                    local baseGrid
                    if PnB.LockPosition and PnB.OriginGrid then
                        baseGrid = PnB.OriginGrid
                    else
                        baseGrid = {
                            x = math.floor((root.Position.X / 4.475) + 0.5),
                            y = math.floor(((root.Position.Y - 2.5) / 4.435) + 0.5)
                        }
                        PnB.OriginGrid = baseGrid
                    end

                    local function getAreaInfo()
                        local targets = {}
                        local currentFilled = 0
                        local selectedList = {}
                        for coordKey, active in pairs(PnB.SelectedTiles) do
                            if active then
                                local parts = string.split(coordKey, ",")
                                table.insert(selectedList, {ox = tonumber(parts[1]), oy = tonumber(parts[2])})
                            end
                        end
                        table.sort(selectedList, function(a, b)
                            if a.oy ~= b.oy then return a.oy > b.oy end
                            return a.ox < b.ox
                        end)
                        for _, offset in ipairs(selectedList) do
                            local tx = baseGrid.x + offset.ox
                            local ty = baseGrid.y + offset.oy
                            local tileData = worldData[tx] and worldData[tx][ty]
                            local blockExist = tileData and tileData[1] ~= nil
                            local wallExist = tileData and tileData[2] ~= nil
                            local isFilled = blockExist or wallExist
                            table.insert(targets, {
                                pos = Vector2.new(tx, ty),
                                isFilled = isFilled,
                                layer = blockExist and 1 or (wallExist and 2 or 1)
                            })
                            if isFilled then currentFilled = currentFilled + 1 end
                        end
                        return targets, currentFilled
                    end

                    local areaData, filledCount = getAreaInfo()
                    local maxTiles = #areaData

                    -- ==========================
                    -- SIKLUS 1: BREAK
                    -- ==========================
                    if PnB.Break and filledCount > 0 then
                        if filledCount == maxTiles or _G.LastPnBState == "Breaking" or _G.LastPnBState == "Waiting" or (not PnB.Place) then
                            _G.LastPnBState = "Breaking"
                            if PnB.BreakMode == "Mode 1 (Fokus)" then
                                for _, tile in ipairs(areaData) do
                                    if _G.LatestRunToken ~= myToken or not PnB.Master then break end
                                    if tile.isFilled then
                                        while PnB.Master and PnB.Break do
                                            if _G.LatestRunToken ~= myToken then break end
                                            local check = worldData[tile.pos.X] and worldData[tile.pos.X][tile.pos.Y] and worldData[tile.pos.X][tile.pos.Y][tile.layer]
                                            if check == nil then break end
                                            game.ReplicatedStorage.Remotes.PlayerFist:FireServer(tile.pos)
                                            task.wait(0.035)
                                        end
                                    end
                                end
                            else
                                while filledCount > 0 and PnB.Master and PnB.Break do
                                    if _G.LatestRunToken ~= myToken then break end
                                    for _, tile in ipairs(areaData) do
                                        if _G.LatestRunToken ~= myToken then break end
                                        if tile.isFilled then
                                            game.ReplicatedStorage.Remotes.PlayerFist:FireServer(tile.pos)
                                            task.wait(0.02)
                                        end
                                    end
                                    areaData, filledCount = getAreaInfo()
                                end
                            end

                            areaData, filledCount = getAreaInfo()
                            if filledCount == 0 then
                                if getgenv().SmartCollect_Enabled then
                                    _G.LastPnBState = "Collecting"
                                elseif getgenv().AutoDrop_PnB_Enabled then
                                    _G.LastPnBState = "Dropping"
                                else
                                    _G.LastPnBState = "Placing"
                                end
                            end
                            return
                        end
                    end

                    -- ==========================
                    -- SIKLUS 2: SMART COLLECT
                    -- ==========================
                    if _G.LastPnBState == "Collecting" and getgenv().SmartCollect_Enabled then
                        local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
                        if not Hitbox then
                            -- Tanpa hitbox, skip langsung ke drop / place
                            if getgenv().AutoDrop_PnB_Enabled then
                                _G.LastPnBState = "Dropping"
                            else
                                _G.LastPnBState = "Placing"
                            end
                            return
                        end

                        while _G.LatestRunToken == myToken and PnB.Master and getgenv().SmartCollect_Enabled do
                            local drops = getDropsInGrid(baseGrid)
                            if #drops == 0 then
                                CollectStatusLabel:SetText("Collect: Done! Kembali ke Origin...")
                                walkBackToOrigin(Hitbox, baseGrid)
                                CollectStatusLabel:SetText("Collect: Idle")
                                -- Setelah collect selesai, cek apakah perlu drop
                                if getgenv().AutoDrop_PnB_Enabled then
                                    _G.LastPnBState = "Dropping"
                                else
                                    _G.LastPnBState = "Placing"
                                end
                                break
                            end

                            local nearest = nil
                            local nearestDist = math.huge
                            for _, drop in ipairs(drops) do
                                local d = (Hitbox.Position - drop:GetPivot().Position).Magnitude
                                if d < nearestDist then
                                    nearestDist = d
                                    nearest = drop
                                end
                            end

                            if nearest then
                                local tName = IM.GetName(nearest:GetAttribute("id") or nearest.Name) or "Item"
                                CollectStatusLabel:SetText("Collect: → " .. tName)
                                local success = walkToPoint(Hitbox, nearest)
                                if not success then
                                    badItems[nearest] = true
                                end
                            end

                            task.wait(0.1)
                        end

                        return
                    end

                    -- ==========================
                    -- SIKLUS 3: AUTO DROP
                    -- Hanya jalan ke drop point jika amount > MaxStack
                    -- Return Point = PnB.OriginGrid (otomatis)
                    -- ==========================
                    if _G.LastPnBState == "Dropping" and getgenv().AutoDrop_PnB_Enabled then
                        local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)

                        -- Cek syarat dasar
                        if not DropSettings.TargetID then
                            DropStatusLabel:SetText("Drop: Scan ID dulu!")
                            _G.LastPnBState = "Placing"
                            return
                        end
                        if not DropSettings.DropPoint then
                            DropStatusLabel:SetText("Drop: Set Drop Point dulu!")
                            _G.LastPnBState = "Placing"
                            return
                        end
                        if not Hitbox then
                            DropStatusLabel:SetText("Drop: Hitbox tidak ditemukan!")
                            _G.LastPnBState = "Placing"
                            return
                        end

                        local currentAmount = GetDropItemAmount()

                        -- Cek apakah target drop tercapai
                        if currentAmount > DropSettings.MaxStack then
                            -- [1] Jalan ke Drop Point
                            DropStatusLabel:SetText(string.format("Drop: Ke Drop Point (%d,%d)...", DropSettings.DropPoint.x, DropSettings.DropPoint.y))
                            WalkToDropPoint(Hitbox, DropSettings.DropPoint.x, DropSettings.DropPoint.y)

                            if not PnB.Master or _G.LatestRunToken ~= myToken then return end

                            -- [2] Eksekusi drop
                            local uiSnapshot = SnapshotUI()
                            DoDropAll(uiSnapshot)

                            if not PnB.Master or _G.LatestRunToken ~= myToken then return end

                            -- [3] Balik ke Origin PnB (bukan Return Point manual — otomatis)
                            DropStatusLabel:SetText(string.format("Drop: Balik ke Origin (%d,%d)...", baseGrid.x, baseGrid.y))
                            WalkBackFromDrop(Hitbox, baseGrid)
                        else
                            -- Amount tidak cukup untuk drop, langsung lanjut Place
                            DropStatusLabel:SetText(string.format("Drop: Skip (Jumlah: %d/%d)", currentAmount, DropSettings.MaxStack))
                        end

                        _G.LastPnBState = "Placing"
                        return
                    end

                    -- ==========================
                    -- SIKLUS 4: PLACE
                    -- ==========================
                    if PnB.Place and maxTiles > 0 then
                        areaData, filledCount = getAreaInfo()
                        if filledCount < maxTiles and (_G.LastPnBState == "Placing" or _G.LastPnBState == "Waiting") then
                            _G.LastPnBState = "Placing"
                            if getActiveAmount() > 0 then
                                for _, tile in ipairs(areaData) do
                                    if _G.LatestRunToken ~= myToken or not PnB.Master then break end
                                    if not tile.isFilled and PnB.Master then
                                        game.ReplicatedStorage.Remotes.PlayerPlaceItem:FireServer(tile.pos, PnB.TargetID, 1)
                                        task.wait(PnB.PlaceDelay)
                                    end
                                end
                            end
                            areaData, filledCount = getAreaInfo()
                            if filledCount == maxTiles then
                                _G.LastPnBState = "Waiting"
                                task.wait(PnB.ActualDelay)
                            end
                        end
                    end

                    -- Handle kondisi hanya Break tanpa Place
                    if PnB.Break and not PnB.Place then
                        areaData, filledCount = getAreaInfo()
                        if filledCount == 0 and _G.LastPnBState ~= "Collecting" and _G.LastPnBState ~= "Dropping" then
                            _G.LastPnBState = "Waiting"
                            task.wait(PnB.ActualDelay)
                        end
                    end

                end)
            end
            updatePnBVisuals()
            task.wait(0.01)
        end
        print("SayzHub: PnB + SmartCollect + AutoDrop Loop terminated safely.")
    end)
end
