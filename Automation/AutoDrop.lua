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

    -- ========================================
    -- [2] UI ELEMENTS
    -- ========================================
    SubTab:AddSection("EKSEKUSI")
    getgenv().SayzUI_Handles["AutoDrop_Master"] = SubTab:AddToggle("Enable Auto Drop", Drop.Enabled, function(t)
        Drop.Enabled = t
    end)

    -- ---- TARGET ITEM ----
    SubTab:AddSection("TARGET ITEM")
    SubTab:AddButton("Scan ID Item (Drop Manual 1x)", function()
        Drop.Scanning = true
        Window:Notify("Drop 1 item manual untuk scan ID-nya!", 3, "info")
    end)
    local ScanLabel   = SubTab:AddLabel("ID Target : None")
    local AmountLabel = SubTab:AddLabel("Jumlah    : 0")

    -- ---- SETTING ----
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

    -- ---- POSISI ----
    SubTab:AddSection("POSISI")

    -- Label dideklarasi DULUAN agar bisa diupdate dari callback tombol
    local DropPointLabel   = SubTab:AddLabel("Drop Point  : Belum diset")
    local ReturnPointLabel = SubTab:AddLabel("Return Point: Belum diset")

    -- Helper update label
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

    -- Helper ambil posisi grid sekarang (coba hitbox, fallback HRP)
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

    -- DROP POINT
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
    -- Fallback input manual
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

    -- RETURN POINT
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
    -- Fallback input manual
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

    -- ---- STATUS ----
    SubTab:AddSection("STATUS")
    local StatusLabel = SubTab:AddLabel("Status: Idle")

    -- ========================================
    -- [3] SCAN HOOK
    -- Intercept PlayerDrop:FireServer() saat Scanning = true
    -- Ambil ID item dari slot yang di-drop
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
    -- [4] CORE FUNCTIONS
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

    local function ForceRestoreUI()
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
            if UIManager then
                if type(UIManager.ShowHUD) == "function" then UIManager:ShowHUD() end
                if type(UIManager.ShowUI)  == "function" then UIManager:ShowUI()  end
            end
        end)
        pcall(function()
            local targetUIs = { "topbar","gems","playerui","hotbar","crosshair","mainhud","stats","inventory","backpack","menu","bottombar","buttons" }
            for _, gui in pairs(LP.PlayerGui:GetDescendants()) do
                if gui:IsA("Frame") or gui:IsA("ScreenGui") or gui:IsA("ImageLabel") then
                    local gName = string.lower(gui.Name)
                    for _, tName in ipairs(targetUIs) do
                        if string.find(gName, tName) and not string.find(gName, "prompt") then
                            if gui:IsA("ScreenGui") then gui.Enabled = true else gui.Visible = true end
                        end
                    end
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

    local function DoDropAll()
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
        ForceRestoreUI()
    end

    local function WalkToPoint(targetX, targetY)
        local HitboxFolder = workspace:FindFirstChild("Hitbox")
        local MyHitbox = HitboxFolder and HitboxFolder:FindFirstChild(LP.Name)
        if not MyHitbox then return end

        local startZ = MyHitbox.Position.Z
        while _G.LatestRunToken == myToken do
            local curX = math.floor(MyHitbox.Position.X / 4.5 + 0.5)
            local curY = math.floor(MyHitbox.Position.Y / 4.5 + 0.5)
            if curX == targetX and curY == targetY then break end

            local nextX, nextY = curX, curY
            if curX ~= targetX then
                nextX = curX + (targetX > curX and 1 or -1)
            elseif curY ~= targetY then
                nextY = curY + (targetY > curY and 1 or -1)
            end

            local newPos = Vector3.new(nextX * 4.5, nextY * 4.5, startZ)
            MyHitbox.CFrame = CFrame.new(newPos)
            pcall(function()
                if movementModule then movementModule.Position = newPos end
            end)
            task.wait(Drop.StepDelay)
        end
    end

    -- ========================================
    -- [5] LABEL UPDATE REAL-TIME
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
    -- [6] MAIN LOOP
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

                    -- [1] Jalan ke drop point
                    StatusLabel:SetText(string.format("Status: Jalan ke Drop Point (%d,%d)...", Drop.DropPoint.x, Drop.DropPoint.y))
                    WalkToPoint(Drop.DropPoint.x, Drop.DropPoint.y)

                    -- [2] Drop
                    DoDropAll()

                    -- [3] Balik ke return point
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
