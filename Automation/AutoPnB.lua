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
    }

    local LIMIT = { MIN_X = 0, MAX_X = 100, MIN_Y = 6, MAX_Y = 60 }
    local lockedDoors = {}
    local badItems = {}
    local doorDatabase = {}

    -- ========================================
    -- [2] UI ELEMENTS
    -- ========================================

    SubTab:AddSection("EKSEKUSI")
    getgenv().SayzUI_Handles["PnB_Master"]    = SubTab:AddToggle("Master Switch",  PnB.Master, function(t) PnB.Master = t end)
    getgenv().SayzUI_Handles["PnB_Break"]     = SubTab:AddToggle("Enable Break",   PnB.Break,  function(t) PnB.Break  = t end)
    getgenv().SayzUI_Handles["PnB_Place"]     = SubTab:AddToggle("Enable Place",   PnB.Place,  function(t) PnB.Place  = t end)

    SubTab:AddButton("Scan ID Item (Pasang 1 Blok Manual)", function()
        PnB.Scanning = true
        Window:Notify("Pasang 1 blok manual untuk scan!", 3, "info")
    end)
    local InfoLabel = SubTab:AddLabel("ID Aktif   : None")
    local StokLabel = SubTab:AddLabel("Total Stok : 0")

    SubTab:AddSection("SMART COLLECT")
    getgenv().SayzUI_Handles["SmartCollect_PnB"] = SubTab:AddToggle("Enable Smart Collect (Setelah Break)", getgenv().SmartCollect_Enabled, function(t)
        getgenv().SmartCollect_Enabled = t
        if t then
            if not PnB.LockPosition then
                Window:Notify("⚠️ Aktifkan Lock Position agar grid tidak bergeser saat collect!", 5, "warn")
            end
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
    getgenv().SayzUI_Handles["TakeGems_PnB"] = SubTab:AddToggle("Collect Gems", getgenv().TakeGems_PnB, function(t)
        getgenv().TakeGems_PnB = t
    end)
    getgenv().SayzUI_Handles["StepDelaySlider_PnB"] = SubTab:AddSlider("Movement Speed", 0.01, 0.2, getgenv().StepDelay, function(val)
        getgenv().StepDelay = val
    end, 2)
    local CollectStatusLabel = SubTab:AddLabel("Collect Status: Idle")

    SubTab:AddSection("SETTING")
    getgenv().SayzUI_Handles["PnB_SpeedScale"] = SubTab:AddInput("Speed Scale (Min 0.1)", "1", function(v)
        local val = tonumber(v) or 1
        if val < 0.1 then val = 0.1 end
        PnB.DelayScale  = val
        PnB.ActualDelay = val * 0.12
    end)
    getgenv().SayzUI_Handles["PnB_BreakMode"] = SubTab:AddDropdown("Multi-Break Mode", {"Mode 1 (Fokus)", "Mode 2 (Rata)"}, PnB.BreakMode, function(v)
        PnB.BreakMode = v
    end)

    SubTab:AddSection("GRID TARGET (5x5)")
    SubTab:AddGridSelector(function(selectedTable)
        PnB.SelectedTiles = selectedTable
        local char = LP.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            PnB.OriginGrid = {
                x = math.floor(root.Position.X / 4.5 + 0.5),
                y = math.floor(root.Position.Y / 4.5 + 0.5)
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
                x = math.floor(root.Position.X / 4.5 + 0.5),
                y = math.floor(root.Position.Y / 4.5 + 0.5)
            }
            Window:Notify("Position Refreshed!", 2, "ok")
        end
    end)

    SubTab:AddSection("AUTO DROP")
    getgenv().SayzUI_Handles["AutoDrop_PnB"] = SubTab:AddToggle("Enable Auto Drop (Setelah Collect)", getgenv().AutoDrop_PnB_Enabled, function(t)
        getgenv().AutoDrop_PnB_Enabled = t
    end)

    SubTab:AddButton("Scan ID Item Drop (Drop Manual 1x)", function()
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

    SubTab:AddLabel("↩ Return Point : Otomatis mengikuti Origin PnB")
    local DropStatusLabel = SubTab:AddLabel("Drop Status: Idle")

    SubTab:AddSection("PANDUAN PENGGUNAAN")
    SubTab:AddParagraph("Versi", "AutoPnB v10 - 04 Mar 2026\n- Fix WalkToDropPoint: retry loop + fallback teleport\n- Fix walkback collect & drop: retry loop\n- Fix isWalkableDrop solid\n- A* parent pointer")
    SubTab:AddLabel("1. Aktifkan Master, Break, dan Place.")
    SubTab:AddLabel("2. Tambah Smart Collect untuk ambil item drop.")
    SubTab:AddLabel("3. Tambah Auto Drop untuk drop item otomatis.")
    SubTab:AddLabel("Urutan: Break → Collect → Drop → Place")

    -- ========================================
    -- [3] HELPER FUNCTIONS
    -- ========================================

    local function getActiveAmount()
        local total = 0
        local success, invModule = pcall(function()
            return require(game.ReplicatedStorage.Modules.Inventory)
        end)
        if success and invModule and invModule.Stacks then
            for _, stack in pairs(invModule.Stacks) do
                if stack and tostring(stack.Id) == tostring(PnB.TargetID) then
                    total = total + (stack.Amount or 0)
                end
            end
        end
        return total
    end

    local function getSlotByPnBID()
        if not InventoryMod or not InventoryMod.Stacks then return nil end
        for slotIndex, data in pairs(InventoryMod.Stacks) do
            if type(data) == "table" and data.Id then
                if tostring(data.Id) == tostring(PnB.TargetID) then
                    if not data.Amount or data.Amount > 0 then
                        return slotIndex
                    end
                end
            end
        end
        return nil
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

    if not _G.OldHookSet then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            local args = {...}
            if _G.LatestRunToken == myToken and PnB.Scanning and self.Name == "PlayerPlaceItem" and method == "FireServer" then
                local slotIndex = args[2]
                if slotIndex and InventoryMod and InventoryMod.Stacks then
                    local data = InventoryMod.Stacks[slotIndex]
                    if data and data.Id then
                        PnB.TargetID = tostring(data.Id)
                        PnB.Scanning = false
                        Window:Notify("ID Scanned: " .. PnB.TargetID, 2, "ok")
                    end
                end
            end
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

    -- Cache blacklist positions - dibangun sekali sebelum pathfinding, bukan per-node
    -- Ini fix utama freeze: isWalkable tidak lagi loop workspace.Drops tiap node
    local blacklistPosCache = {}
    local function rebuildBlacklistCache()
        blacklistPosCache = {}
        local folders = {"Drops"}
        if getgenv().TakeGems_PnB then table.insert(folders, "Gems") end
        for _, folderName in pairs(folders) do
            local container = workspace:FindFirstChild(folderName)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    local id = item:GetAttribute("id") or item.Name
                    if getgenv().ItemBlacklist_PnB[id] then
                        local itPos = item:GetPivot().Position
                        local itX = math.floor(itPos.X / 4.5 + 0.5)
                        local itY = math.floor(itPos.Y / 4.5 + 0.5)
                        blacklistPosCache[itX .. "," .. itY] = true
                    end
                end
            end
        end
    end

    local function isWalkable(gx, gy)
        if gx < LIMIT.MIN_X or gx > LIMIT.MAX_X or gy < LIMIT.MIN_Y or gy > LIMIT.MAX_Y then
            return false, false
        end
        if lockedDoors[gx .. "," .. gy] then
            return false, false
        end
        local hasBlacklist = blacklistPosCache[gx .. "," .. gy] or false
        if worldData[gx] and worldData[gx][gy] then
            local l1 = worldData[gx][gy][1]
            local itemName = (type(l1) == "table") and l1[1] or l1
            if itemName then
                local n = string.lower(tostring(itemName))
                if string.find(n, "door") or string.find(n, "frame") or string.find(n, "sapling") then
                    return true, hasBlacklist
                end
                return false, false
            end
        end
        return true, hasBlacklist
    end

    -- Sama logikanya dengan isWalkable AutoDF:
    -- block apapun = tidak walkable, KECUALI door/frame/sapling
    local function isWalkableDrop(gx, gy)
        if gx < LIMIT.MIN_X or gx > LIMIT.MAX_X or gy < LIMIT.MIN_Y or gy > LIMIT.MAX_Y then
            return false
        end
        if lockedDoors[gx .. "," .. gy] then return false end
        if worldData[gx] and worldData[gx][gy] then
            local l1 = worldData[gx][gy][1]
            local itemName = (type(l1) == "table") and l1[1] or l1
            if itemName then
                local n = string.lower(tostring(itemName))
                if string.find(n, "door") or string.find(n, "frame") or string.find(n, "sapling") then
                    return true
                end
                return false  -- semua block lain tidak bisa dilewati
            end
        end
        return true
    end

    -- A* pathfinding untuk SmartCollect - pakai parent pointer, tidak copy path
    local function findSmartPath(startX, startY, targetX, targetY)
        local function h(x, y) return math.abs(x - targetX) + math.abs(y - targetY) end
        local startKey = startX .. "," .. startY
        local queue   = {{x=startX, y=startY, g=0, f=h(startX,startY), parent=nil}}
        local visited = {[startKey] = 0}
        local dirs    = {{x=1,y=0},{x=-1,y=0},{x=0,y=1},{x=0,y=-1}}
        local found   = nil
        local limit   = 0
        while #queue > 0 do
            if _G.LatestRunToken ~= myToken then break end
            limit = limit + 1
            if limit > 10000 then break end
            local minIdx, minF = 1, queue[1].f
            for i = 2, #queue do
                if queue[i].f < minF then minF = queue[i].f; minIdx = i end
            end
            local cur = table.remove(queue, minIdx)
            if cur.x == targetX and cur.y == targetY then found = cur break end
            for _, d in ipairs(dirs) do
                local nx, ny = cur.x + d.x, cur.y + d.y
                local nkey   = nx .. "," .. ny
                local walkable, isBlacklisted = isWalkable(nx, ny)
                if walkable then
                    local moveCost = isBlacklisted and getgenv().AvoidanceStrength or 1
                    local ng = cur.g + moveCost
                    if not visited[nkey] or ng < visited[nkey] then
                        visited[nkey] = ng
                        table.insert(queue, {x=nx, y=ny, g=ng, f=ng+h(nx,ny), parent=cur})
                    end
                end
            end
        end
        if not found then return nil end
        -- Rekonstruksi path dari parent pointer
        local path, node = {}, found
        while node.parent ~= nil do
            table.insert(path, 1, Vector3.new(node.x * 4.5, node.y * 4.5, 0))
            node = node.parent
        end
        return path
    end

    -- A* pathfinding untuk AutoDrop - pakai parent pointer
    local function findSmartPathDrop(startX, startY, targetX, targetY)
        local function h(x, y) return math.abs(x - targetX) + math.abs(y - targetY) end
        local startKey = startX .. "," .. startY
        local queue   = {{x=startX, y=startY, g=0, f=h(startX,startY), parent=nil}}
        local visited = {[startKey] = 0}
        local dirs    = {{x=1,y=0},{x=-1,y=0},{x=0,y=1},{x=0,y=-1}}
        local found   = nil
        local limit   = 0
        while #queue > 0 do
            if _G.LatestRunToken ~= myToken then break end
            limit = limit + 1
            if limit > 10000 then break end
            local minIdx, minF = 1, queue[1].f
            for i = 2, #queue do
                if queue[i].f < minF then minF = queue[i].f; minIdx = i end
            end
            local cur = table.remove(queue, minIdx)
            if cur.x == targetX and cur.y == targetY then found = cur break end
            for _, d in ipairs(dirs) do
                local nx, ny = cur.x + d.x, cur.y + d.y
                local nkey   = nx .. "," .. ny
                if isWalkableDrop(nx, ny) then
                    local ng = cur.g + 1
                    if not visited[nkey] or ng < visited[nkey] then
                        visited[nkey] = ng
                        table.insert(queue, {x=nx, y=ny, g=ng, f=ng+h(nx,ny), parent=cur})
                    end
                end
            end
        end
        if not found then return nil end
        local path, node = {}, found
        while node.parent ~= nil do
            table.insert(path, 1, Vector3.new(node.x * 4.5, node.y * 4.5, 0))
            node = node.parent
        end
        return path
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
        rebuildBlacklistCache()
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
        end
        return true
    end

    -- Balik ke posisi x,y, loop retry sampai benar-benar sampai
    local function walkBackToPos(Hitbox, targetX, targetY)
        local maxRetry = 5
        local retry = 0
        while retry < maxRetry do
            if _G.LatestRunToken ~= myToken or not PnB.Master then break end
            local sx = math.floor(Hitbox.Position.X / 4.5 + 0.5)
            local sy = math.floor(Hitbox.Position.Y / 4.5 + 0.5)
            if sx == targetX and sy == targetY then break end

            rebuildBlacklistCache()
            local path = findSmartPath(sx, sy, targetX, targetY)
            if not path then
                -- Fallback teleport
                CollectStatusLabel:SetText("Collect: Teleport balik...")
                Hitbox.CFrame = CFrame.new(targetX * 4.5, targetY * 4.5, Hitbox.Position.Z)
                movementModule.Position = Hitbox.Position
                task.wait(0.2)
                break
            end

            for i, point in ipairs(path) do
                if _G.LatestRunToken ~= myToken or not PnB.Master then break end
                CollectStatusLabel:SetText(string.format("Collect: Returning (%d/%d)...", i, #path))
                Hitbox.CFrame = CFrame.new(point.X, point.Y, Hitbox.Position.Z)
                movementModule.Position = Hitbox.Position
                task.wait(getgenv().StepDelay)
            end

            retry = retry + 1
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

    local function WalkToDropPoint(Hitbox, targetX, targetY)
        local maxRetry = 5
        local retry = 0
        while retry < maxRetry do
            if not PnB.Master or not getgenv().AutoDrop_PnB_Enabled or _G.LatestRunToken ~= myToken then break end
            local curX = math.floor(Hitbox.Position.X / 4.5 + 0.5)
            local curY = math.floor(Hitbox.Position.Y / 4.5 + 0.5)
            if curX == targetX and curY == targetY then break end
            local path = findSmartPathDrop(curX, curY, targetX, targetY)
            if not path then
                -- Fallback teleport
                DropStatusLabel:SetText("Drop: Teleport ke Drop Point...")
                Hitbox.CFrame = CFrame.new(targetX * 4.5, targetY * 4.5, Hitbox.Position.Z)
                movementModule.Position = Hitbox.Position
                task.wait(0.2)
                break
            end
            for i, point in ipairs(path) do
                if not PnB.Master or not getgenv().AutoDrop_PnB_Enabled or _G.LatestRunToken ~= myToken then break end
                DropStatusLabel:SetText(string.format("Drop: Jalan ke Drop Point (%d/%d)...", i, #path))
                Hitbox.CFrame = CFrame.new(point.X, point.Y, Hitbox.Position.Z)
                movementModule.Position = Hitbox.Position
                task.wait(getgenv().StepDelay)
            end
            retry = retry + 1
        end
    end

    -- Tidak dipakai lagi tapi tetap ada untuk kompatibilitas
    local function WalkBackFromDrop(Hitbox, originGrid) end

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
    -- [7] MAIN LOOP
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            if PnB.Master then
                pcall(function()
                    local char = LP.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    if not root then return end

                    -- baseGrid selalu dari OriginGrid yang sudah di-set
                    -- Tidak dihitung ulang dari posisi player supaya tidak bergeser
                    if not PnB.OriginGrid then
                        PnB.OriginGrid = {
                            x = math.floor((root.Position.X / 4.475) + 0.5),
                            y = math.floor(((root.Position.Y - 2.5) / 4.435) + 0.5)
                        }
                    end
                    local baseGrid = PnB.OriginGrid

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

                    -- Reset lockedDoors tiap siklus baru supaya path tidak makin sempit
                    lockedDoors = {}

                    -- SIKLUS 1: BREAK
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

                    -- SIKLUS 2: SMART COLLECT
                    if _G.LastPnBState == "Collecting" and getgenv().SmartCollect_Enabled then
                        local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)
                        if not Hitbox then
                            if getgenv().AutoDrop_PnB_Enabled then
                                _G.LastPnBState = "Dropping"
                            else
                                _G.LastPnBState = "Placing"
                            end
                            return
                        end

                        -- Simpan posisi player sebelum mulai collect
                        local returnX = math.floor(Hitbox.Position.X / 4.5 + 0.5)
                        local returnY = math.floor(Hitbox.Position.Y / 4.5 + 0.5)

                        while _G.LatestRunToken == myToken and PnB.Master and getgenv().SmartCollect_Enabled do
                            local drops = getDropsInGrid(baseGrid)
                            if #drops == 0 then
                                CollectStatusLabel:SetText("Collect: Done! Kembali ke posisi awal...")
                                walkBackToPos(Hitbox, returnX, returnY)
                                CollectStatusLabel:SetText("Collect: Idle")
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

                    -- SIKLUS 3: AUTO DROP
                    if _G.LastPnBState == "Dropping" and getgenv().AutoDrop_PnB_Enabled then
                        local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)

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

                        if currentAmount > DropSettings.MaxStack then
                            -- Simpan posisi sebelum jalan ke drop point
                            local dropReturnX = math.floor(Hitbox.Position.X / 4.5 + 0.5)
                            local dropReturnY = math.floor(Hitbox.Position.Y / 4.5 + 0.5)

                            DropStatusLabel:SetText(string.format("Drop: Ke Drop Point (%d,%d)...", DropSettings.DropPoint.x, DropSettings.DropPoint.y))
                            WalkToDropPoint(Hitbox, DropSettings.DropPoint.x, DropSettings.DropPoint.y)

                            if not PnB.Master or _G.LatestRunToken ~= myToken then return end

                            local uiSnapshot = SnapshotUI()
                            DoDropAll(uiSnapshot)

                            if not PnB.Master or _G.LatestRunToken ~= myToken then return end

                            -- Balik ke posisi sebelum drop, retry sampai sampai
                            local dropMaxRetry = 5
                            local dropRetry = 0
                            while dropRetry < dropMaxRetry do
                                if _G.LatestRunToken ~= myToken or not PnB.Master then break end
                                local sx = math.floor(Hitbox.Position.X / 4.5 + 0.5)
                                local sy = math.floor(Hitbox.Position.Y / 4.5 + 0.5)
                                if sx == dropReturnX and sy == dropReturnY then break end
                                DropStatusLabel:SetText(string.format("Drop: Balik ke posisi awal (%d,%d)...", dropReturnX, dropReturnY))
                                local path = findSmartPathDrop(sx, sy, dropReturnX, dropReturnY)
                                if not path then
                                    Hitbox.CFrame = CFrame.new(dropReturnX * 4.5, dropReturnY * 4.5, Hitbox.Position.Z)
                                    movementModule.Position = Hitbox.Position
                                    task.wait(0.2)
                                    break
                                end
                                for i, point in ipairs(path) do
                                    if _G.LatestRunToken ~= myToken or not PnB.Master then break end
                                    DropStatusLabel:SetText(string.format("Drop: Balik (%d/%d)...", i, #path))
                                    Hitbox.CFrame = CFrame.new(point.X, point.Y, Hitbox.Position.Z)
                                    movementModule.Position = Hitbox.Position
                                    task.wait(getgenv().StepDelay)
                                end
                                dropRetry = dropRetry + 1
                            end
                            DropStatusLabel:SetText("Drop Status: Idle")
                        else
                            DropStatusLabel:SetText(string.format("Drop: Skip (Jumlah: %d/%d)", currentAmount, DropSettings.MaxStack))
                        end

                        _G.LastPnBState = "Placing"
                        return
                    end

                    -- SIKLUS 4: PLACE
                    if PnB.Place and maxTiles > 0 then
                        areaData, filledCount = getAreaInfo()
                        if filledCount < maxTiles and (_G.LastPnBState == "Placing" or _G.LastPnBState == "Waiting") then
                            _G.LastPnBState = "Placing"
                            if getActiveAmount() > 0 then
                                for _, tile in ipairs(areaData) do
                                    if _G.LatestRunToken ~= myToken or not PnB.Master then break end
                                    if not tile.isFilled and PnB.Master then
                                        local slotIndex = getSlotByPnBID()
                                        if slotIndex then
                                            game.ReplicatedStorage.Remotes.PlayerPlaceItem:FireServer(tile.pos, slotIndex, 1)
                                        end
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
