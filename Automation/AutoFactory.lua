return function(SubTab, Window, myToken)
    -- ========================================
    -- [1] SETUP & VARIABLES
    -- ========================================
    local LP        = game.Players.LocalPlayer
    local RS        = game:GetService("ReplicatedStorage")
    local worldData = require(RS.WorldTiles)
    local movementModule = require(LP.PlayerScripts.PlayerMovement)
    local IM        = require(RS.Managers.ItemsManager)

    local PlayerPlace = RS.Remotes.PlayerPlaceItem
    local PlayerFist  = RS.Remotes.PlayerFist
    local PlayerDrop  = RS.Remotes:FindFirstChild("PlayerDrop")
    local UIPromptEvent = RS.Managers:WaitForChild("UIManager"):FindFirstChild("UIPromptEvent")
    local MovPacket   = RS.Remotes:WaitForChild("PlayerMovementPackets"):WaitForChild(LP.Name)

    local InventoryMod
    pcall(function() InventoryMod = require(RS.Modules.Inventory) end)

    local Factory = {
        Enabled     = false,
        RowY        = nil,   -- Y baris farming (posisi player)
        SeedID      = nil,   -- ID seed
        BlockID     = nil,   -- ID block untuk PnB
        HarvestDelay = 30,   -- detik tunggu sebelum harvest
        ScanningS   = false, -- scanning seed
        ScanningB   = false, -- scanning block
        PlantedTime = nil,   -- tick() saat selesai tanam
        PlantedXs   = {},    -- posisi yang ditanam
        FirstStart  = true,  -- flag pertama kali start
    }

    local DropSettings = {
        Enabled     = false,
        TargetID    = nil,
        MaxStack    = 200,
        KeepAmount  = 200,
        DropDelay   = 0.5,
        DropPoint   = nil,
        Scanning    = false,
    }

    local WORLD_MIN_X, WORLD_MAX_X = 0, 100
    local WORLD_MIN_Y, WORLD_MAX_Y = 6, 60

    -- ========================================
    -- [2] UI
    -- ========================================
    SubTab:AddSection("EKSEKUSI")
    getgenv().SayzUI_Handles["Factory_Master"] = SubTab:AddToggle("Master Switch", false, function(t)
        Factory.Enabled = t
        if t then
            Factory.FirstStart = true  -- reset setiap kali diaktifkan
            local HitboxFolder = workspace:FindFirstChild("Hitbox")
            local MyHitbox = HitboxFolder and HitboxFolder:FindFirstChild(LP.Name)
            local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if MyHitbox then
                Factory.RowY = math.floor(MyHitbox.Position.Y / 4.5 + 0.5)
            elseif root then
                Factory.RowY = math.floor(root.Position.Y / 4.5 + 0.5)
            end
            if Factory.RowY then
                Window:Notify(string.format("Baris Y diset ke %d", Factory.RowY), 3, "ok")
            end
        end
    end)

    local RowLabel = SubTab:AddLabel("Baris Y : Belum diset")
    SubTab:AddButton("📍 Set Baris Y (Posisi Sekarang)", function()
        local HitboxFolder = workspace:FindFirstChild("Hitbox")
        local MyHitbox = HitboxFolder and HitboxFolder:FindFirstChild(LP.Name)
        local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if MyHitbox then
            Factory.RowY = math.floor(MyHitbox.Position.Y / 4.5 + 0.5)
        elseif root then
            Factory.RowY = math.floor(root.Position.Y / 4.5 + 0.5)
        end
        if Factory.RowY then
            RowLabel:SetText("Baris Y : " .. Factory.RowY)
            Window:Notify("Baris Y = " .. Factory.RowY, 2, "ok")
        end
    end)

    SubTab:AddSection("SEED")
    SubTab:AddButton("Scan ID Seed (Tanem 1 Manual)", function()
        Factory.ScanningS = true
        Window:Notify("Tanem 1 seed manual untuk scan!", 3, "info")
    end)
    local SeedLabel = SubTab:AddLabel("Seed ID : Belum diset")

    SubTab:AddSection("BLOCK PnB")
    SubTab:AddButton("Scan ID Block (Pasang 1 Manual)", function()
        Factory.ScanningB = true
        Window:Notify("Pasang 1 block manual untuk scan!", 3, "info")
    end)
    local BlockLabel = SubTab:AddLabel("Block ID : Belum diset")

    SubTab:AddSection("TIMING")
    getgenv().SayzUI_Handles["Factory_Delay"] = SubTab:AddInput("Delay Harvest (detik)", "30", function(v)
        local val = tonumber(v)
        if val and val > 0 then Factory.HarvestDelay = val end
    end)
    SubTab:AddLabel("Tips: 1 menit = 60, 1 jam = 3600")
    SubTab:AddButton("🌾 Harvest Sekarang (Skip Delay)", function()
        if Factory.PlantedTime then
            Factory.PlantedTime = tick() - Factory.HarvestDelay
            Window:Notify("Harvest akan dimulai di iterasi berikutnya!", 2, "ok")
        else
            Window:Notify("Tidak ada tanaman yang sedang ditunggu.", 2, "warn")
        end
    end)

    SubTab:AddSection("AUTO DROP")
    getgenv().SayzUI_Handles["Factory_Drop"] = SubTab:AddToggle("Enable Auto Drop", false, function(t)
        DropSettings.Enabled = t
    end)
    SubTab:AddButton("Scan ID Item Drop (Drop Manual 1x)", function()
        DropSettings.Scanning = true
        Window:Notify("Drop 1 item manual untuk scan ID-nya!", 3, "info")
    end)
    local DropIDLabel    = SubTab:AddLabel("Drop ID    : Belum diset")
    local DropAmtLabel   = SubTab:AddLabel("Jumlah     : 0")
    getgenv().SayzUI_Handles["Factory_MaxStack"] = SubTab:AddInput("Max Stack (drop jika lebih)", "200", function(v)
        local val = tonumber(v) if val and val > 0 then DropSettings.MaxStack = val end
    end)
    getgenv().SayzUI_Handles["Factory_KeepAmt"] = SubTab:AddInput("Keep Amount", "200", function(v)
        local val = tonumber(v) if val and val >= 0 then DropSettings.KeepAmount = val end
    end)
    getgenv().SayzUI_Handles["Factory_DropDelay"] = SubTab:AddSlider("Drop Delay", 0.1, 2, 0.5, function(v)
        DropSettings.DropDelay = v
    end, 1)
    local DropPointLabel = SubTab:AddLabel("Drop Point : Belum diset")
    SubTab:AddButton("📍 Set Drop Point (Posisi Sekarang)", function()
        local HitboxFolder = workspace:FindFirstChild("Hitbox")
        local MyHitbox = HitboxFolder and HitboxFolder:FindFirstChild(LP.Name)
        local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        local x, y
        if MyHitbox then
            x = math.floor(MyHitbox.Position.X / 4.5 + 0.5)
            y = math.floor(MyHitbox.Position.Y / 4.5 + 0.5)
        elseif root then
            x = math.floor(root.Position.X / 4.5 + 0.5)
            y = math.floor(root.Position.Y / 4.5 + 0.5)
        end
        if x then
            DropSettings.DropPoint = {x=x, y=y}
            DropPointLabel:SetText(string.format("Drop Point : (%d, %d)", x, y))
            Window:Notify(string.format("Drop Point: (%d,%d)", x, y), 2, "ok")
        end
    end)

    SubTab:AddSection("STATUS")
    local StatusLabel = SubTab:AddLabel("Status: Idle")
    local StepLabel   = SubTab:AddLabel("Fase: -")

    SubTab:AddSection("PANDUAN")
    SubTab:AddParagraph("Versi", "AutoFactory v8 - 04 Mar 2026\n- Fix collect PnB: scan x=0 saja (tile break), bukan x=0-2\n- Gems langsung diambil tanpa filter\n- Nearest first collect\n- Loop fleksibel: sapling→harvest, block→PnB, seed→tanam")
    SubTab:AddLabel("1. Berdiri di baris Y yang mau di-farm.")
    SubTab:AddLabel("2. Aktifkan Master → Y otomatis tersimpan.")
    SubTab:AddLabel("3. Scan ID Seed dan ID Block PnB.")
    SubTab:AddLabel("4. Set Delay Harvest sesuai waktu tumbuh.")
    SubTab:AddLabel("5. [Opsional] Set Auto Drop.")
    SubTab:AddLabel("Urutan: Plant → Tunggu → Harvest → Collect → PnB x=0 → Drop → Ulang")

    -- ========================================
    -- [3] SCAN HOOK
    -- ========================================
    if not _G.FactoryHookSet then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            local args = {...}
            if _G.LatestRunToken == myToken then
                -- Scan seed
                if Factory.ScanningS and method == "FireServer" and self.Name == "PlayerPlaceItem" then
                    local slotIndex = args[2]
                    if slotIndex and InventoryMod and InventoryMod.Stacks then
                        local data = InventoryMod.Stacks[slotIndex]
                        if data and data.Id then
                            Factory.SeedID = tostring(data.Id)
                            Factory.ScanningS = false
                            SeedLabel:SetText("Seed ID : " .. Factory.SeedID)
                            Window:Notify("Seed ID: " .. Factory.SeedID, 2, "ok")
                        end
                    end
                end
                -- Scan block PnB
                if Factory.ScanningB and method == "FireServer" and self.Name == "PlayerPlaceItem" then
                    local slotIndex = args[2]
                    if slotIndex and InventoryMod and InventoryMod.Stacks then
                        local data = InventoryMod.Stacks[slotIndex]
                        if data and data.Id then
                            Factory.BlockID = tostring(data.Id)
                            Factory.ScanningB = false
                            BlockLabel:SetText("Block ID : " .. Factory.BlockID)
                            Window:Notify("Block ID: " .. Factory.BlockID, 2, "ok")
                        end
                    end
                end
                -- Scan drop
                if DropSettings.Scanning and method == "FireServer" and self == PlayerDrop then
                    local slotIndex = args[1]
                    if slotIndex and InventoryMod and InventoryMod.Stacks then
                        local data = InventoryMod.Stacks[slotIndex]
                        if data and data.Id then
                            DropSettings.TargetID = tostring(data.Id)
                            DropSettings.Scanning = false
                            DropIDLabel:SetText("Drop ID    : " .. DropSettings.TargetID)
                            Window:Notify("Drop ID: " .. DropSettings.TargetID, 2, "ok")
                        end
                    end
                end
            end
            return oldNamecall(self, ...)
        end)
        _G.FactoryHookSet = true
    end

    -- ========================================
    -- [4] HELPER FUNCTIONS
    -- ========================================
    local function getHitbox()
        local HitboxFolder = workspace:FindFirstChild("Hitbox")
        return HitboxFolder and HitboxFolder:FindFirstChild(LP.Name)
    end

    local function getGridPos()
        local hb = getHitbox()
        if hb then
            return math.floor(hb.Position.X / 4.5 + 0.5),
                   math.floor(hb.Position.Y / 4.5 + 0.5)
        end
        local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if root then
            return math.floor(root.Position.X / 4.5 + 0.5),
                   math.floor(root.Position.Y / 4.5 + 0.5)
        end
        return nil, nil
    end

    local function isWalkable(gx, gy)
        if gx < WORLD_MIN_X or gx > WORLD_MAX_X or gy < WORLD_MIN_Y or gy > WORLD_MAX_Y then
            return false
        end
        if worldData[gx] and worldData[gx][gy] then
            local l1 = worldData[gx][gy][1]
            local itemName = (type(l1) == "table") and l1[1] or l1
            if itemName then
                local n = string.lower(tostring(itemName))
                if string.find(n, "door") or string.find(n, "frame") or string.find(n, "sapling") then
                    return true
                end
                return false
            end
        end
        return true
    end

    -- A* pathfinding dengan parent pointer
    local function findPath(startX, startY, targetX, targetY)
        local function h(x, y) return math.abs(x-targetX) + math.abs(y-targetY) end
        local queue   = {{x=startX, y=startY, g=0, f=h(startX,startY), parent=nil}}
        local visited = {[startX..","..startY] = 0}
        local dirs    = {{x=1,y=0},{x=-1,y=0},{x=0,y=1},{x=0,y=-1}}
        local found, limit = nil, 0
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
                local nx, ny = cur.x+d.x, cur.y+d.y
                local nkey = nx..","..ny
                if isWalkable(nx, ny) then
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
            table.insert(path, 1, {x=node.x, y=node.y})
            node = node.parent
        end
        return path
    end

    local function walkTo(tx, ty, label, hint)
        local maxRetry = 5
        local retry = 0
        while retry < maxRetry do
            if _G.LatestRunToken ~= myToken or not Factory.Enabled then break end
            local cx, cy = getGridPos()
            if not cx then break end
            if cx == tx and cy == ty then break end
            local path = findPath(cx, cy, tx, ty)
            if not path then
                -- Fallback teleport
                local hb = getHitbox()
                if hb then
                    hb.CFrame = CFrame.new(tx*4.5, ty*4.5, hb.Position.Z)
                    movementModule.Position = hb.Position
                    task.wait(0.2)
                end
                break
            end
            for i, pt in ipairs(path) do
                if _G.LatestRunToken ~= myToken or not Factory.Enabled then break end
                if label then label:SetText(string.format("%s (%d/%d)", hint or "Jalan", i, #path)) end
                local hb = getHitbox()
                if hb then
                    local wx, wy = pt.x*4.5, pt.y*4.5
                    hb.CFrame = CFrame.new(wx, wy, hb.Position.Z)
                    movementModule.Position = hb.Position
                    pcall(function() MovPacket:FireServer(wx, wy) end)
                end
                task.wait(0.05)
            end
            local ax, ay = getGridPos()
            if ax == tx and ay == ty then break end
            retry = retry + 1
        end
    end

    -- Scan baris Y: cari semua X yang ada block di Y-1 (bawah baris)
    local function scanPlantableX(rowY)
        local result = {}
        for gx = WORLD_MIN_X+2, WORLD_MAX_X-2 do
            local belowY = rowY - 1
            if worldData[gx] and worldData[gx][belowY] then
                local l1 = worldData[gx][belowY][1]
                local itemName = (type(l1) == "table") and l1[1] or l1
                if itemName then
                    -- Ada block di bawah = bisa ditanam
                    -- Cek tile di rowY sendiri kosong
                    local tileAbove = worldData[gx][rowY]
                    local aboveFg = tileAbove and tileAbove[1]
                    if not aboveFg then
                        table.insert(result, gx)
                    end
                end
            end
        end
        return result
    end

    local function getSlotByID(id)
        if not InventoryMod or not InventoryMod.Stacks then return nil end
        for slotIndex, data in pairs(InventoryMod.Stacks) do
            if type(data) == "table" and data.Id then
                if tostring(data.Id) == tostring(id) then
                    if not data.Amount or data.Amount > 0 then
                        return slotIndex, data.Amount or 1
                    end
                end
            end
        end
        return nil, 0
    end

    local function getItemAmount(id)
        local total = 0
        if not InventoryMod or not InventoryMod.Stacks then return 0 end
        for _, data in pairs(InventoryMod.Stacks) do
            if type(data) == "table" and data.Id then
                if tostring(data.Id) == tostring(id) then
                    total = total + (data.Amount or 1)
                end
            end
        end
        return total
    end

    -- ========================================
    -- [5] FASE FUNCTIONS
    -- ========================================

    -- FASE 1: PLANT
    -- Scan tile di rowY yang kosong & ada block di bawah → tanam
    -- Tunggu worldData konfirmasi ada sapling sebelum pindah ke tile berikutnya
    local function doPlant(rowY)
        StepLabel:SetText("Fase: Plant")
        if not Factory.SeedID then
            Window:Notify("Seed ID belum di-scan!", 3, "danger")
            return {}
        end

        local plantableXs = scanPlantableX(rowY)
        if #plantableXs == 0 then
            StatusLabel:SetText("Status: Tidak ada tempat tanam!")
            return {}
        end

        local planted = {}
        for _, gx in ipairs(plantableXs) do
            if _G.LatestRunToken ~= myToken or not Factory.Enabled then break end
            local slotIdx, amt = getSlotByID(Factory.SeedID)
            if not slotIdx or amt <= 0 then
                StatusLabel:SetText("Status: Seed habis!")
                break
            end
            -- Cek tile masih kosong
            local tile = worldData[gx] and worldData[gx][rowY]
            if tile and tile[1] then continue end -- sudah ada isi, skip

            walkTo(gx, rowY, StatusLabel, "Plant → X="..gx)
            if _G.LatestRunToken ~= myToken or not Factory.Enabled then break end

            -- Tanam lalu tunggu worldData konfirmasi ada sapling (max 2 detik)
            slotIdx = getSlotByID(Factory.SeedID)
            if not slotIdx then break end
            PlayerPlace:FireServer(Vector2.new(gx, rowY), slotIdx, 1)

            local confirmed = false
            for _ = 1, 20 do -- max 2 detik (20 x 0.1)
                task.wait(0.1)
                local t = worldData[gx] and worldData[gx][rowY]
                local fg = t and t[1]
                local name = fg and (type(fg)=="table" and fg[1] or fg) or nil
                if name then
                    confirmed = true
                    break
                end
            end

            if confirmed then
                table.insert(planted, gx)
            end
        end

        StatusLabel:SetText(string.format("Status: Tanam selesai (%d titik)", #planted))
        return planted
    end

    -- FASE 2: TUNGGU
    local function doWait(seconds)
        StepLabel:SetText("Fase: Tunggu Harvest")
        for i = seconds, 1, -1 do
            if _G.LatestRunToken ~= myToken or not Factory.Enabled then return false end
            StatusLabel:SetText(string.format("Status: Tunggu %ds lagi...", i))
            task.wait(1)
        end
        return true
    end

    -- FASE 3: HARVEST
    -- Scan rowY, harvest dari x kecil ke besar supaya drop ke-collect saat jalan ke kanan
    -- Tunggu tile benar-benar hancur (worldData kosong) sebelum pindah ke tile berikutnya
    local function doHarvest(rowY, plantedXs)
        StepLabel:SetText("Fase: Harvest")

        -- Scan ulang worldData untuk tile yang masih ada tanaman
        local toHarvest = {}
        for _, gx in ipairs(plantedXs) do
            local tile = worldData[gx] and worldData[gx][rowY]
            local fg = tile and tile[1]
            if fg then
                table.insert(toHarvest, gx)
            end
        end

        -- Dari x kecil ke besar - drop ke-collect otomatis saat jalan ke kanan menuju PnB
        table.sort(toHarvest, function(a, b) return a < b end)

        for _, gx in ipairs(toHarvest) do
            if _G.LatestRunToken ~= myToken or not Factory.Enabled then break end
            walkTo(gx, rowY, StatusLabel, "Harvest → X="..gx)
            if _G.LatestRunToken ~= myToken or not Factory.Enabled then break end

            -- Pukul sampai tile benar-benar hancur (worldData kosong)
            local maxHits = 30
            local hits = 0
            while hits < maxHits do
                if _G.LatestRunToken ~= myToken or not Factory.Enabled then break end
                local tile = worldData[gx] and worldData[gx][rowY]
                if not (tile and tile[1]) then break end -- sudah hancur
                PlayerFist:FireServer(Vector2.new(gx, rowY))
                task.wait(0.05)
                hits = hits + 1
            end
        end

        -- Jalan ke x=1, drop ke-collect otomatis sepanjang jalan
        StatusLabel:SetText("Status: Jalan ke PnB...")
        walkTo(1, rowY, StatusLabel, "Ke PnB x=1")
        StatusLabel:SetText("Status: Harvest selesai")
    end

    -- FASE 4: COLLECT DROP DI BARIS
    local function doCollect(rowY)
        StepLabel:SetText("Fase: Collect Drop")
        local hb = getHitbox()
        if not hb then return end

        local maxCycles = 20
        local cycle = 0
        while cycle < maxCycles do
            if _G.LatestRunToken ~= myToken or not Factory.Enabled then break end

            -- Cari semua drop di baris rowY
            local drops = {}
            local container = workspace:FindFirstChild("Drops")
            if container then
                for _, item in pairs(container:GetChildren()) do
                    local itPos = item:GetPivot().Position
                    local itY = math.floor(itPos.Y / 4.5 + 0.5)
                    if itY == rowY then
                        table.insert(drops, item)
                    end
                end
            end
            if #drops == 0 then break end

            -- Ambil yang paling dekat
            local nearest, nearestDist = nil, math.huge
            for _, drop in ipairs(drops) do
                local d = (hb.Position - drop:GetPivot().Position).Magnitude
                if d < nearestDist then nearestDist = d; nearest = drop end
            end
            if not nearest then break end

            local itPos = nearest:GetPivot().Position
            local itX = math.floor(itPos.X / 4.5 + 0.5)
            local itY = math.floor(itPos.Y / 4.5 + 0.5)
            StatusLabel:SetText(string.format("Status: Collect drop di X=%d", itX))
            walkTo(itX, itY, nil, nil)
            task.wait(0.1)
            cycle = cycle + 1
        end
        StatusLabel:SetText("Status: Collect selesai")
    end

    -- FASE 5: PnB di x=0, baris rowY
    -- Ikutin cara AutoPnB: langsung FireServer ke tile, tidak perlu jalan ke sana
    -- Collect drop di x=0 setelah break, baru place
    local function doPnB(rowY)
        if not Factory.BlockID then
            Window:Notify("Block ID belum di-scan!", 3, "danger")
            return
        end

        local pnbPos = Vector2.new(0, rowY)
        local lastX, lastY = nil, nil  -- track posisi terakhir, gerak hanya kalau berubah

        -- Helper collect drop di x=0: hanya gerak kalau ada drop, dan posisi berubah
        local badItemsPnB = {}
        local function collectAtX0()
            local hb = getHitbox()
            if not hb then return end
            local maxCycles = 30
            local c = 0
            while c < maxCycles do
                if _G.LatestRunToken ~= myToken or not Factory.Enabled then break end
                local drops = {}
                for _, folderName in ipairs({"Drops", "Gems"}) do
                    local container = workspace:FindFirstChild(folderName)
                    if container then
                        for _, item in pairs(container:GetChildren()) do
                            if not badItemsPnB[item] then
                                local itPos = item:GetPivot().Position
                                local itX = math.floor(itPos.X / 4.5 + 0.5)
                                local itY = math.floor(itPos.Y / 4.5 + 0.5)
                                if itY == rowY and itX == 0 then
                                    table.insert(drops, {item=item, x=itX, y=itY})
                                end
                            end
                        end
                    end
                end
                if #drops == 0 then break end
                -- Nearest first
                local nearest, nearestDist = nil, math.huge
                for _, d in ipairs(drops) do
                    local dist = (hb.Position - d.item:GetPivot().Position).Magnitude
                    if dist < nearestDist then nearestDist = dist; nearest = d end
                end
                if nearest then
                    if lastX ~= nearest.x or lastY ~= nearest.y then
                        local wx, wy = nearest.x*4.5, nearest.y*4.5
                        hb.CFrame = CFrame.new(wx, wy, hb.Position.Z)
                        movementModule.Position = hb.Position
                        pcall(function() MovPacket:FireServer(wx, wy) end)
                        lastX, lastY = nearest.x, nearest.y
                        -- Tunggu item ke-collect (cek tiap 0.1s max 0.5s)
                        for _ = 1, 5 do
                            task.wait(0.1)
                            if not nearest.item or not nearest.item.Parent then break end
                        end
                    else
                        -- Posisi sama tapi item masih ada = stuck
                        badItemsPnB[nearest.item] = true
                    end
                end
                c = c + 1
            end
        end

        local cycleLimit = 300
        local cycle = 0
        while cycle < cycleLimit do
            if _G.LatestRunToken ~= myToken or not Factory.Enabled then break end

            local tile = worldData[0] and worldData[0][rowY]
            local hasFg = tile and tile[1] ~= nil

            if hasFg then
                -- Ada block → BREAK langsung (tidak perlu gerak ke sana)
                StepLabel:SetText("Fase: PnB [Break]")
                StatusLabel:SetText("Status: Break x=0...")
                PlayerFist:FireServer(pnbPos)
                task.wait(0.035)
            else
                -- Tile kosong → cek drop dulu
                local hasDropAtX0 = false
                for _, folderName in ipairs({"Drops", "Gems"}) do
                    local container = workspace:FindFirstChild(folderName)
                    if container then
                        for _, item in pairs(container:GetChildren()) do
                            if not badItemsPnB[item] then
                                local itPos = item:GetPivot().Position
                                if math.floor(itPos.X/4.5+0.5) == 0 and
                                   math.floor(itPos.Y/4.5+0.5) == rowY then
                                    hasDropAtX0 = true
                                    break
                                end
                            end
                        end
                    end
                    if hasDropAtX0 then break end
                end

                if hasDropAtX0 then
                    StepLabel:SetText("Fase: PnB [Collect]")
                    StatusLabel:SetText("Status: Collect drop dulu...")
                    collectAtX0()
                    -- Balik ke x=1 setelah collect
                    local hb = getHitbox()
                    if hb then
                        local wx, wy = 1*4.5, rowY*4.5
                        hb.CFrame = CFrame.new(wx, wy, hb.Position.Z)
                        movementModule.Position = hb.Position
                        pcall(function() MovPacket:FireServer(wx, wy) end)
                        task.wait(0.05)
                    end
                else
                    -- Bersih → place langsung (tidak perlu gerak)
                    StepLabel:SetText("Fase: PnB [Place]")
                    StatusLabel:SetText("Status: Place x=0...")
                    local slotIdx, amt = getSlotByID(Factory.BlockID)
                    if not slotIdx or amt <= 0 then
                        StatusLabel:SetText("Status: Block habis!")
                        break
                    end
                    PlayerPlace:FireServer(pnbPos, slotIdx, 1)
                    task.wait(0.12)
                    -- Cek ter-place
                    local t = worldData[0] and worldData[0][rowY]
                    if not (t and t[1]) then break end -- block habis = selesai
                end
            end

            cycle = cycle + 1
        end

        StepLabel:SetText("Fase: PnB selesai")
        StatusLabel:SetText("Status: PnB selesai")
    end

    -- FASE 6: AUTO DROP
    local function doAutoDrop(rowY)
        if not DropSettings.Enabled or not DropSettings.TargetID or not DropSettings.DropPoint then return end
        StepLabel:SetText("Fase: Auto Drop")

        local current = getItemAmount(DropSettings.TargetID)
        if current <= DropSettings.MaxStack then
            StatusLabel:SetText(string.format("Status: Skip drop (%d/%d)", current, DropSettings.MaxStack))
            return
        end

        -- Jalan ke drop point
        local hb = getHitbox()
        if not hb then return end
        local dpx, dpy = DropSettings.DropPoint.x, DropSettings.DropPoint.y
        walkTo(dpx, dpy, StatusLabel, "Drop Point")
        if _G.LatestRunToken ~= myToken or not Factory.Enabled then return end

        -- Drop
        while _G.LatestRunToken == myToken and Factory.Enabled and DropSettings.Enabled do
            local cur = getItemAmount(DropSettings.TargetID)
            local toDrop = cur - DropSettings.KeepAmount
            if toDrop <= 0 then break end
            local slot = getSlotByID(DropSettings.TargetID)
            if not slot then break end
            local batch = math.min(toDrop, 200)
            StatusLabel:SetText(string.format("Status: Drop %d...", batch))
            pcall(function() PlayerDrop:FireServer(slot) end)
            task.wait(0.2)
            pcall(function()
                UIPromptEvent:FireServer({ButtonAction="drp", Inputs={amt=tostring(batch)}})
            end)
            task.wait(DropSettings.DropDelay)
        end

        -- Balik ke baris
        walkTo(1, rowY, StatusLabel, "Balik ke baris")
        StatusLabel:SetText("Status: Drop selesai")
    end

    -- ========================================
    -- [6] GRAVITY BYPASS
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait()
            if Factory.Enabled then
                pcall(function()
                    if movementModule.VelocityY < 0 then movementModule.VelocityY = 0 end
                    movementModule.Grounded = true
                end)
            end
        end
    end)

    -- ========================================
    -- [7] UPDATE LABELS
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait(1)
            pcall(function()
                if Factory.RowY then RowLabel:SetText("Baris Y : " .. Factory.RowY) end
                if DropSettings.TargetID then
                    local amt = getItemAmount(DropSettings.TargetID)
                    DropAmtLabel:SetText("Jumlah     : " .. amt)
                end
            end)
        end
    end)

    -- ========================================
    -- [8] MAIN LOOP
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait(0.1)
            if not Factory.Enabled then
                StatusLabel:SetText("Status: Idle")
                StepLabel:SetText("Fase: -")
            else
                pcall(function()
                    if not Factory.RowY then
                        StatusLabel:SetText("Status: Set Baris Y dulu!")
                        return
                    end
                    if not Factory.SeedID then
                        StatusLabel:SetText("Status: Scan Seed ID dulu!")
                        return
                    end
                    if not Factory.BlockID then
                        StatusLabel:SetText("Status: Scan Block ID dulu!")
                        return
                    end

                    local rowY = Factory.RowY

                    -- Scan tile di rowY: ada sapling yang perlu di-harvest?
                    local function scanSaplingsInRow()
                        local found = {}
                        local plantableXs = scanPlantableX(rowY)
                        -- Scan semua x yang bisa ditanam + cek tile rowY ada sapling
                        for gx = WORLD_MIN_X+2, WORLD_MAX_X-2 do
                            local tile = worldData[gx] and worldData[gx][rowY]
                            local fg = tile and tile[1]
                            local name = fg and (type(fg)=="table" and fg[1] or fg) or nil
                            if name then
                                local n = string.lower(tostring(name))
                                if string.find(n, "sapling") or string.find(n, "crop") or string.find(n, "seed") then
                                    table.insert(found, gx)
                                end
                            end
                        end
                        return found
                    end

                    -- CEK 1: Ada sapling di baris + sudah lewat delay? → Harvest
                    local saplings = scanSaplingsInRow()
                    if #saplings > 0 then
                        -- Pertama kali start dan PlantedTime belum diset
                        -- Tanya user mau harvest sekarang atau tunggu delay dulu
                        if Factory.FirstStart and not Factory.PlantedTime then
                            StepLabel:SetText("Fase: Menunggu konfirmasi")
                            StatusLabel:SetText("Status: Ada sapling! Harvest sekarang atau tunggu delay?")
                            Window:Notify("Ada sapling di baris! Pilih: harvest sekarang (klik Harvest Sekarang) atau tunggu delay.", 5, "warn")
                            -- Set PlantedTime = sekarang - HarvestDelay supaya langsung harvest
                            -- User bisa klik tombol "Harvest Sekarang" atau biarkan tunggu delay
                            Factory.PlantedTime = tick() -- tunggu delay dari sekarang
                            Factory.FirstStart = false
                            task.wait(1)
                            return
                        end
                        Factory.FirstStart = false

                        local now = tick()
                        local plantedTime = Factory.PlantedTime or (now - Factory.HarvestDelay)
                        local elapsed = now - plantedTime
                        local remaining = Factory.HarvestDelay - elapsed

                        if remaining > 0 then
                            StepLabel:SetText("Fase: Menunggu Harvest")
                            StatusLabel:SetText(string.format("Status: Tunggu %ds lagi...", math.ceil(remaining)))
                            task.wait(1)
                            return
                        end

                        -- Sudah waktunya harvest
                        StepLabel:SetText("Fase: Harvest")
                        StatusLabel:SetText(string.format("Status: Harvest %d sapling...", #saplings))
                        table.sort(saplings, function(a,b) return a > b end)
                        doHarvest(rowY, saplings)
                        Factory.PlantedTime = nil
                        Factory.PlantedXs = {}
                        if not Factory.Enabled or _G.LatestRunToken ~= myToken then return end
                        doAutoDrop(rowY)
                        return
                    end
                    Factory.FirstStart = false

                    -- CEK 2: Ada block di inventory? → PnB di x=0
                    local blockSlot, blockAmt = getSlotByID(Factory.BlockID)
                    if blockSlot and blockAmt > 0 then
                        StepLabel:SetText("Fase: PnB")
                        doPnB(rowY)
                        if not Factory.Enabled or _G.LatestRunToken ~= myToken then return end
                        doAutoDrop(rowY)
                        return
                    end

                    -- CEK 3: Ada seed di inventory? → Tanam dulu
                    local seedSlot, seedAmt = getSlotByID(Factory.SeedID)
                    if seedSlot and seedAmt > 0 then
                        StepLabel:SetText("Fase: Plant")
                        local planted = doPlant(rowY)
                        if not Factory.Enabled or _G.LatestRunToken ~= myToken then return end
                        if #planted > 0 then
                            -- Simpan waktu tanam untuk countdown harvest
                            Factory.PlantedTime = tick()
                            Factory.PlantedXs = planted
                        end
                        return
                    end

                    -- CEK 4: Seed kosong dan block kosong → notif, tetap loop
                    StepLabel:SetText("Fase: Menunggu")
                    StatusLabel:SetText("Status: Seed kosong! Isi seed dulu...")
                    task.wait(3)
                end)
            end
        end
        print("SayzHub: AutoFactory loop terminated.")
    end)
end
