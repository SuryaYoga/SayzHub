return function(SubTab, Window, myToken)
    -- ========================================
    -- [1] SETUP & VARIABLES
    -- ========================================
    local Players           = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LP                = Players.LocalPlayer

    local Remotes       = ReplicatedStorage:WaitForChild("Remotes")
    local Managers      = ReplicatedStorage:WaitForChild("Managers")
    local PlayerDrop    = Remotes:FindFirstChild("PlayerDrop")
    local UIPromptEvent = Managers:WaitForChild("UIManager"):FindFirstChild("UIPromptEvent")

    local UIManager
    pcall(function() UIManager = require(Managers:WaitForChild("UIManager")) end)

    local InventoryMod
    pcall(function() InventoryMod = require(ReplicatedStorage.Modules.Inventory) end)

    local movementModule
    pcall(function() movementModule = require(LP.PlayerScripts:WaitForChild("PlayerMovement")) end)

    local Drop = {
        Enabled     = false,
        MaxStack    = 200,
        KeepAmount  = 200,
        DropDelay   = 0.5,
        StepDelay   = 0.05,
        TargetID    = nil,
        Scanning    = false,
        DropPoint   = nil,
        ReturnPoint = nil,
    }
    getgenv().SayzSettings.AutoDrop = Drop

    -- Map limits & lockedDoors (shared dengan AutoCollect kalau sudah load)
    -- ========================================
    -- [4] WALK TO POINT
    -- 100% pakai findSmartPath + lockedDoors dari AutoCollect (SayzShared)
    -- Tidak ada duplikat logic di sini
    -- ========================================
    local function WalkToPoint(targetX, targetY)
        local shared = getgenv().SayzShared
        if not shared or not shared.findSmartPath then
            warn("AutoDrop: AutoCollect belum diload, WalkToPoint tidak bisa jalan.")
            return
        end

        local HitboxFolder = workspace:FindFirstChild("Hitbox")
        local MyHitbox = HitboxFolder and HitboxFolder:FindFirstChild(LP.Name)
        if not MyHitbox then return end

        local startZ = MyHitbox.Position.Z

        local maxRetry = 10
        local retry = 0
        while _G.LatestRunToken == myToken and Drop.Enabled do
            local curX = math.floor(MyHitbox.Position.X / 4.5 + 0.5)
            local curY = math.floor(MyHitbox.Position.Y / 4.5 + 0.5)
            if curX == targetX and curY == targetY then break end

            retry = retry + 1
            if retry > maxRetry then
                warn("AutoDrop: Tidak bisa sampai tujuan setelah " .. maxRetry .. "x pathfind.")
                break
            end

            -- Pakai findSmartPath milik AutoCollect langsung
            local path = shared.findSmartPath(curX, curY, targetX, targetY)
            if not path then
                warn("AutoDrop: Tidak ada jalur tersisa.")
                break
            end

            local stuck = false
            for i, point in ipairs(path) do
                if not Drop.Enabled or _G.LatestRunToken ~= myToken then return end

                StatusLabel:SetText(string.format("Status: Jalan (%d/%d)...", i, #path))
                MyHitbox.CFrame = CFrame.new(point.X, point.Y, startZ)
                pcall(function()
                    if movementModule then movementModule.Position = MyHitbox.Position end
                end)
                task.wait(Drop.StepDelay)

                -- Deteksi stuck pintu — tulis langsung ke lockedDoors AutoCollect
                local char = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                if char then
                    local dist = (Vector2.new(char.Position.X, char.Position.Y) - Vector2.new(point.X, point.Y)).Magnitude
                    if dist > 5 then
                        local key = math.floor(point.X/4.5+0.5) .. "," .. math.floor(point.Y/4.5+0.5)
                        shared.lockedDoors[key] = true  -- tulis ke tabel AutoCollect langsung
                        stuck = true
                        break
                    end
                end
            end

            if not stuck then break end
            -- stuck → pathfind ulang, pintu sudah diblok di lockedDoors AutoCollect
        end
    end
    getgenv().SayzUI_Handles["AutoDrop_Master"] = SubTab:AddToggle("Enable Auto Drop", Drop.Enabled, function(t)
        Drop.Enabled = t
    end)

    SubTab:AddSection("TARGET ITEM")
    SubTab:AddButton("Scan ID Item (Drop Manual 1x)", function()
        Drop.Scanning = true
        Window:Notify("Drop 1 item manual untuk scan ID-nya!", 3, "info")
    end)
    local ScanLabel   = SubTab:AddLabel("ID Target : None")
    local AmountLabel = SubTab:AddLabel("Jumlah    : 0")

    SubTab:AddSection("SETTING")
    getgenv().SayzUI_Handles["AutoDrop_MaxStack"] = SubTab:AddInput("Max Stack (drop jika melebihi)", tostring(Drop.MaxStack), function(v)
        local val = tonumber(v)
        if val and val > 0 then Drop.MaxStack = val end
    end)
    getgenv().SayzUI_Handles["AutoDrop_KeepAmt"] = SubTab:AddInput("Keep Amount (sisa setelah drop)", tostring(Drop.KeepAmount), function(v)
        local val = tonumber(v)
        if val and val >= 0 then Drop.KeepAmount = val end
    end)
    getgenv().SayzUI_Handles["AutoDrop_StepDelay"] = SubTab:AddSlider("Movement Speed", 0.01, 0.2, Drop.StepDelay, function(val)
        Drop.StepDelay = val
    end, 2)
    getgenv().SayzUI_Handles["AutoDrop_DropDelay"] = SubTab:AddSlider("Drop Delay", 0.1, 2, Drop.DropDelay, function(val)
        Drop.DropDelay = val
    end, 1)

    SubTab:AddSection("POSISI")

    -- Label dideklarasi DULUAN agar bisa diupdate dari callback tombol
    local DropPointLabel   = SubTab:AddLabel("Drop Point  : Belum diset")
    local ReturnPointLabel = SubTab:AddLabel("Return Point: Belum diset")

    local function updateDropLabel()
        if Drop.DropPoint then
            DropPointLabel:SetText(string.format("Drop Point  : (%d, %d)", Drop.DropPoint.x, Drop.DropPoint.y))
        end
    end
    local function updateReturnLabel()
        if Drop.ReturnPoint then
            ReturnPointLabel:SetText(string.format("Return Point: (%d, %d)", Drop.ReturnPoint.x, Drop.ReturnPoint.y))
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

    -- Drop Point
    SubTab:AddButton("📍 Set Drop Point (Posisi Sekarang)", function()
        local pos = getCurrentGridPos()
        if pos then
            Drop.DropPoint = pos
            updateDropLabel()
            Window:Notify(string.format("Drop Point: (%d, %d)", pos.x, pos.y), 2, "ok")
        else
            Window:Notify("Gagal baca posisi! Isi manual di bawah.", 2, "danger")
        end
    end)
    SubTab:AddInput("Drop X (manual)", "0", function(v)
        local val = tonumber(v)
        if val then
            Drop.DropPoint = Drop.DropPoint or {x = 0, y = 0}
            Drop.DropPoint.x = math.floor(val)
            updateDropLabel()
        end
    end)
    SubTab:AddInput("Drop Y (manual)", "0", function(v)
        local val = tonumber(v)
        if val then
            Drop.DropPoint = Drop.DropPoint or {x = 0, y = 0}
            Drop.DropPoint.y = math.floor(val)
            updateDropLabel()
        end
    end)

    -- Return Point
    SubTab:AddButton("🔙 Set Return Point (Posisi Sekarang)", function()
        local pos = getCurrentGridPos()
        if pos then
            Drop.ReturnPoint = pos
            updateReturnLabel()
            Window:Notify(string.format("Return Point: (%d, %d)", pos.x, pos.y), 2, "ok")
        else
            Window:Notify("Gagal baca posisi! Isi manual di bawah.", 2, "danger")
        end
    end)
    SubTab:AddInput("Return X (manual)", "0", function(v)
        local val = tonumber(v)
        if val then
            Drop.ReturnPoint = Drop.ReturnPoint or {x = 0, y = 0}
            Drop.ReturnPoint.x = math.floor(val)
            updateReturnLabel()
        end
    end)
    SubTab:AddInput("Return Y (manual)", "0", function(v)
        local val = tonumber(v)
        if val then
            Drop.ReturnPoint = Drop.ReturnPoint or {x = 0, y = 0}
            Drop.ReturnPoint.y = math.floor(val)
            updateReturnLabel()
        end
    end)

    SubTab:AddSection("STATUS")
    local StatusLabel = SubTab:AddLabel("Status: Idle")

    -- ========================================
    -- [3] SCAN HOOK
    -- ========================================
    if not _G.AutoDropHookSet then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if _G.LatestRunToken == myToken and Drop.Scanning and method == "FireServer" then
                if self == PlayerDrop then
                    local args = {...}
                    local slotIndex = args[1]
                    if slotIndex and InventoryMod and InventoryMod.Stacks then
                        local data = InventoryMod.Stacks[slotIndex]
                        if data and data.Id then
                            Drop.TargetID = tostring(data.Id)
                            Drop.Scanning = false
                            ScanLabel:SetText("ID Target : " .. Drop.TargetID)
                            Window:Notify("ID Scanned: " .. Drop.TargetID, 2, "ok")
                        end
                    end
                end
            end
            return oldNamecall(self, ...)
        end)
        _G.AutoDropHookSet = true
    end

    -- ========================================
    -- [5] WALK TO POINT (SmartPath + ModFly + cek toggle)
    -- ========================================
    local function WalkToPoint(targetX, targetY)
        local HitboxFolder = workspace:FindFirstChild("Hitbox")
        local MyHitbox = HitboxFolder and HitboxFolder:FindFirstChild(LP.Name)
        if not MyHitbox then return end

        local startZ = MyHitbox.Position.Z
        local sx = math.floor(MyHitbox.Position.X / 4.5 + 0.5)
        local sy = math.floor(MyHitbox.Position.Y / 4.5 + 0.5)

        -- Kalau sudah sampai, tidak perlu pathfind
        if sx == targetX and sy == targetY then return end

        -- Loop pathfind ulang sampai sampai atau toggle mati
        local maxRetry = 10
        local retry = 0
        while _G.LatestRunToken == myToken and Drop.Enabled do
            local curX = math.floor(MyHitbox.Position.X / 4.5 + 0.5)
            local curY = math.floor(MyHitbox.Position.Y / 4.5 + 0.5)
            if curX == targetX and curY == targetY then break end

            retry = retry + 1
            if retry > maxRetry then
                warn("AutoDrop: Tidak bisa sampai tujuan setelah " .. maxRetry .. "x pathfind.")
                break
            end

            local path = findSmartPath(curX, curY, targetX, targetY)
            if not path then
                warn("AutoDrop: SmartPath gagal, tidak ada jalur tersisa.")
                break
            end

            local stuck = false
            for i, point in ipairs(path) do
                if not Drop.Enabled or _G.LatestRunToken ~= myToken then return end

                StatusLabel:SetText(string.format("Status: Jalan (%d/%d)...", i, #path))
                MyHitbox.CFrame = CFrame.new(point.X, point.Y, startZ)
                pcall(function()
                    if movementModule then movementModule.Position = MyHitbox.Position end
                end)
                task.wait(Drop.StepDelay)

                -- Deteksi stuck pintu
                local char = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                if char then
                    local dist = (Vector2.new(char.Position.X, char.Position.Y) - Vector2.new(point.X, point.Y)).Magnitude
                    if dist > 5 then
                        local px = math.floor(point.X / 4.5 + 0.5)
                        local py = math.floor(point.Y / 4.5 + 0.5)
                        local key = px .. "," .. py
                        -- Simpan ke lokal DAN ke shared agar AutoCollect juga tahu
                        lockedDoors[key] = true
                        if getgenv().SayzShared and getgenv().SayzShared.lockedDoors then
                            getgenv().SayzShared.lockedDoors[key] = true
                        end
                        stuck = true
                        break
                    end
                end
            end

            -- Kalau tidak stuck berarti sudah selesai jalan
            if not stuck then break end
            -- Stuck → pathfind ulang dengan jalur yang sudah diblok
        end
    end

    -- ModFly: bypass gravity saat Auto Drop sedang jalan
    -- (sama persis seperti di AutoCollect)
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait()
            if Drop.Enabled then
                pcall(function()
                    if movementModule and movementModule.VelocityY < 0 then
                        movementModule.VelocityY = 0
                    end
                    if movementModule then
                        movementModule.Grounded = true
                    end
                end)
            end
        end
    end)

    -- ========================================
    -- [6] CORE DROP FUNCTIONS
    -- ========================================
    local function GetItemAmount(targetID)
        local total = 0
        if not InventoryMod or not InventoryMod.Stacks then return total end
        for _, data in pairs(InventoryMod.Stacks) do
            if type(data) == "table" and data.Id then
                if tostring(data.Id) == tostring(targetID) then
                    total = total + (data.Amount or 1)
                end
            end
        end
        return total
    end

    local function GetSlotByItemID(targetID)
        if not InventoryMod or not InventoryMod.Stacks then return nil end
        for slotIndex, data in pairs(InventoryMod.Stacks) do
            if type(data) == "table" and data.Id then
                if tostring(data.Id) == tostring(targetID) then
                    if not data.Amount or data.Amount > 0 then
                        return slotIndex
                    end
                end
            end
        end
        return nil
    end

    -- Snapshot state UI sebelum drop, restore setelahnya
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
        -- Tutup prompt dulu
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
        -- Restore ke state sebelum drop
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
        while _G.LatestRunToken == myToken and Drop.Enabled do
            local current = GetItemAmount(Drop.TargetID)
            local toDrop  = current - Drop.KeepAmount
            if toDrop <= 0 then break end

            local slot = GetSlotByItemID(Drop.TargetID)
            if not slot then break end

            local batchAmount = math.min(toDrop, 200)
            StatusLabel:SetText(string.format("Status: Drop %d...", batchAmount))

            local ok = ExecuteDropBatch(slot, batchAmount)
            if not ok then break end

            task.wait(Drop.DropDelay)
        end

        -- Restore UI ke state sebelum drop
        RestoreUIFromSnapshot(snapshot)
    end

    -- ========================================
    -- [7] EXPORT SHARED FUNCTIONS
    -- Dibagikan ke AutoPnB (dan modul lain) lewat getgenv()
    -- ========================================
    getgenv().SayzShared = getgenv().SayzShared or {}
    getgenv().SayzShared.AutoDrop = {
        Drop          = Drop,
        GetItemAmount = GetItemAmount,
        GetSlotByItemID = GetSlotByItemID,
        DoDropAll     = DoDropAll,
        WalkToPoint   = WalkToPoint,
    }

    -- ========================================
    -- [8] LABEL UPDATE REAL-TIME
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            pcall(function()
                if Drop.TargetID then
                    ScanLabel:SetText("ID Target : " .. tostring(Drop.TargetID))
                    AmountLabel:SetText("Jumlah    : " .. GetItemAmount(Drop.TargetID))
                end
            end)
            task.wait(1)
        end
    end)

    -- ========================================
    -- [9] MAIN LOOP
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            if Drop.Enabled then
                pcall(function()
                    if not Drop.TargetID then
                        StatusLabel:SetText("Status: Scan ID dulu!")
                        return
                    end
                    if not Drop.DropPoint then
                        StatusLabel:SetText("Status: Set Drop Point dulu!")
                        return
                    end
                    if not Drop.ReturnPoint then
                        StatusLabel:SetText("Status: Set Return Point dulu!")
                        return
                    end

                    local current = GetItemAmount(Drop.TargetID)
                    if current <= Drop.MaxStack then
                        StatusLabel:SetText(string.format("Status: Monitoring (%d/%d)", current, Drop.MaxStack))
                        return
                    end

                    -- Snapshot UI sebelum apapun dimulai
                    local uiSnapshot = SnapshotUI()

                    -- [1] Jalan ke drop point
                    StatusLabel:SetText(string.format("Status: Ke Drop Point (%d,%d)...", Drop.DropPoint.x, Drop.DropPoint.y))
                    WalkToPoint(Drop.DropPoint.x, Drop.DropPoint.y)

                    -- [2] Cek lagi toggle setelah jalan
                    if not Drop.Enabled or _G.LatestRunToken ~= myToken then return end

                    -- [3] Eksekusi drop (kirim snapshot yang sudah diambil sebelum jalan)
                    DoDropAll(uiSnapshot)

                    -- [4] Balik ke return point
                    if Drop.Enabled and _G.LatestRunToken == myToken then
                        StatusLabel:SetText(string.format("Status: Balik ke (%d,%d)...", Drop.ReturnPoint.x, Drop.ReturnPoint.y))
                        WalkToPoint(Drop.ReturnPoint.x, Drop.ReturnPoint.y)
                        StatusLabel:SetText("Status: Monitoring...")
                    end
                end)
            else
                StatusLabel:SetText("Status: Nonaktif")
            end
            task.wait(1)
        end
    end)
end
