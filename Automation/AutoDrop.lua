return function(SubTab, Window, myToken)
    -- ========================================
    -- [1] SETUP & VARIABLES
    -- ========================================
    local Players           = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LP                = Players.LocalPlayer
    local WorldTiles        = require(game.ReplicatedStorage.WorldTiles)
    local movementModule    = require(LP.PlayerScripts.PlayerMovement)

    local Drop = {
        Enabled      = false,
        TargetID     = nil,
        MaxStack     = 200,
        KeepAmount   = 200,
        DropDelay    = 0.5,
        StepDelay    = 0.05,
        DropPoint    = nil,
        ReturnPoint  = nil,
        Scanning     = false,
    }

    local LIMIT       = { MIN_X = 0, MAX_X = 100, MIN_Y = 6, MAX_Y = 60 }
    local lockedDoors = {}

    local PlayerDrop    = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlayerDrop")
    local UIPromptEvent = ReplicatedStorage:WaitForChild("Managers"):WaitForChild("UIManager"):WaitForChild("UIPromptEvent")

    local UIManager
    pcall(function() UIManager = require(ReplicatedStorage:WaitForChild("Managers"):WaitForChild("UIManager")) end)

    local InventoryMod
    pcall(function() InventoryMod = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Inventory")) end)

    -- ========================================
    -- [2] UI
    -- ========================================
    SubTab:AddSection("EKSEKUSI")
    getgenv().SayzUI_Handles["AutoDrop_Master"] = SubTab:AddToggle("Enable Auto Drop", Drop.Enabled, function(t)
        Drop.Enabled = t
    end)

    SubTab:AddSection("TARGET ITEM")
    SubTab:AddButton("Scan ID Item (Drop 1 item manual)", function()
        Drop.Scanning = true
        Window:Notify("Drop 1 item manual untuk scan ID!", 3, "info")
    end)
    local ScanLabel = SubTab:AddLabel("ID Target: None")
    local StokLabel = SubTab:AddLabel("Stok Sekarang: 0")

    getgenv().SayzUI_Handles["AutoDrop_MaxStack"] = SubTab:AddInput("Max Stack (Drop jika lebih dari)", tostring(Drop.MaxStack), function(v)
        local val = tonumber(v)
        if val and val > 0 then Drop.MaxStack = val end
    end)
    getgenv().SayzUI_Handles["AutoDrop_KeepAmount"] = SubTab:AddInput("Keep Amount (Sisakan)", tostring(Drop.KeepAmount), function(v)
        local val = tonumber(v)
        if val and val >= 0 then Drop.KeepAmount = val end
    end)

    SubTab:AddSection("POSISI")
    SubTab:AddButton("Set Drop Point (Posisi Sekarang)", function()
        local HitboxFolder = workspace:FindFirstChild("Hitbox")
        local MyHitbox = HitboxFolder and HitboxFolder:FindFirstChild(LP.Name)
        if MyHitbox then
            Drop.DropPoint = {
                x = math.floor(MyHitbox.Position.X / 4.5 + 0.5),
                y = math.floor(MyHitbox.Position.Y / 4.5 + 0.5)
            }
            DropPointLabel:SetText(string.format("Drop Point: (%d, %d)", Drop.DropPoint.x, Drop.DropPoint.y))
            Window:Notify(string.format("Drop Point set: (%d, %d)", Drop.DropPoint.x, Drop.DropPoint.y), 2, "ok")
        else
            Window:Notify("Hitbox tidak ditemukan!", 2, "danger")
        end
    end)
    local DropPointLabel = SubTab:AddLabel("Drop Point: Belum diset")

    SubTab:AddButton("Set Return Point (Posisi Sekarang)", function()
        local HitboxFolder = workspace:FindFirstChild("Hitbox")
        local MyHitbox = HitboxFolder and HitboxFolder:FindFirstChild(LP.Name)
        if MyHitbox then
            Drop.ReturnPoint = {
                x = math.floor(MyHitbox.Position.X / 4.5 + 0.5),
                y = math.floor(MyHitbox.Position.Y / 4.5 + 0.5)
            }
            ReturnPointLabel:SetText(string.format("Return Point: (%d, %d)", Drop.ReturnPoint.x, Drop.ReturnPoint.y))
            Window:Notify(string.format("Return Point set: (%d, %d)", Drop.ReturnPoint.x, Drop.ReturnPoint.y), 2, "ok")
        else
            Window:Notify("Hitbox tidak ditemukan!", 2, "danger")
        end
    end)
    local ReturnPointLabel = SubTab:AddLabel("Return Point: Belum diset")

    SubTab:AddSection("SPEED")
    getgenv().SayzUI_Handles["AutoDrop_StepDelay"] = SubTab:AddSlider("Movement Speed", 0.01, 0.2, Drop.StepDelay, function(val)
        Drop.StepDelay = val
    end, 2)
    getgenv().SayzUI_Handles["AutoDrop_DropDelay"] = SubTab:AddSlider("Drop Delay", 0.1, 2, Drop.DropDelay, function(val)
        Drop.DropDelay = val
    end, 1)

    SubTab:AddSection("STATUS")
    local StatusLabel = SubTab:AddLabel("Status: Idle")

    -- ========================================
    -- [3] SCAN HOOK
    -- Tangkap saat PlayerDrop di-fire manual → ambil ID dari slot
    -- ========================================
    if not _G.AutoDropHookSet then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            local args = {...}
            if Drop.Scanning and method == "FireServer" and self == PlayerDrop then
                local slot = args[1]
                if slot and InventoryMod and InventoryMod.Stacks then
                    local data = InventoryMod.Stacks[slot]
                    if data and data.Id then
                        Drop.TargetID = data.Id
                        Drop.Scanning = false
                        Window:Notify("ID Scanned: " .. tostring(data.Id), 2, "ok")
                    end
                end
            end
            return oldNamecall(self, ...)
        end)
        _G.AutoDropHookSet = true
    end

    -- ========================================
    -- [4] INVENTORY HELPERS
    -- ========================================
    local function GetSlotByItemID(targetID)
        if not InventoryMod or not InventoryMod.Stacks then return nil end
        for slotIndex, data in pairs(InventoryMod.Stacks) do
            if type(data) == "table" and data.Id then
                if tostring(data.Id) == tostring(targetID) then
                    if not data.Amount or data.Amount > 0 then return slotIndex end
                end
            end
        end
        return nil
    end

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

    -- ========================================
    -- [5] RESTORE UI
    -- ========================================
    local function ForceRestoreUI()
        pcall(function()
            if UIManager and type(UIManager.ClosePrompt) == "function" then UIManager:ClosePrompt() end
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
            local targetUIs = {"topbar","gems","playerui","hotbar","crosshair","mainhud","stats","inventory","backpack","menu","bottombar","buttons"}
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

    -- ========================================
    -- [6] DROP LOGIC
    -- ========================================
    local function ExecuteDropBatch(slotIndex, dropAmount)
        pcall(function() PlayerDrop:FireServer(slotIndex) end)
        task.wait(0.2)
        pcall(function()
            UIPromptEvent:FireServer({ ButtonAction = "drp", Inputs = { amt = tostring(dropAmount) } })
        end)
        task.wait(0.1)
        pcall(function()
            for _, gui in pairs(LP.PlayerGui:GetDescendants()) do
                if gui:IsA("Frame") and string.find(string.lower(gui.Name), "prompt") then gui.Visible = false end
            end
        end)
    end

    local function DropUntilClean()
        while _G.LatestRunToken == myToken do
            local current = GetItemAmount(Drop.TargetID)
            local toDrop  = current - Drop.KeepAmount
            if toDrop <= 0 then break end
            local slot = GetSlotByItemID(Drop.TargetID)
            if not slot then break end
            local batchAmount = math.min(toDrop, 200)
            StatusLabel:SetText(string.format("Status: Dropping %d...", batchAmount))
            ExecuteDropBatch(slot, batchAmount)
            task.wait(Drop.DropDelay)
        end
        ForceRestoreUI()
    end

    -- ========================================
    -- [7] SMART PATH (A* identik AutoCollect)
    -- ========================================
    local function isWalkable(gx, gy)
        if gx < LIMIT.MIN_X or gx > LIMIT.MAX_X or gy < LIMIT.MIN_Y or gy > LIMIT.MAX_Y then return false end
        if lockedDoors[gx..","..gy] then return false end
        if WorldTiles[gx] and WorldTiles[gx][gy] then
            local l1 = WorldTiles[gx][gy][1]
            local itemName = (type(l1) == "table") and l1[1] or l1
            if itemName then
                local n = string.lower(tostring(itemName))
                if string.find(n, "door") or string.find(n, "frame") then return true end
                return false
            end
        end
        return true
    end

    local function findSmartPath(startX, startY, targetX, targetY)
        local queue   = {{x=startX, y=startY, path={}, cost=0}}
        local visited = {[startX..","..startY] = 0}
        local dirs    = {{x=1,y=0},{x=-1,y=0},{x=0,y=1},{x=0,y=-1}}
        local limit   = 0
        while #queue > 0 do
            if _G.LatestRunToken ~= myToken then break end
            limit = limit + 1
            if limit > 4000 then break end
            table.sort(queue, function(a, b) return a.cost < b.cost end)
            local cur = table.remove(queue, 1)
            if cur.x == targetX and cur.y == targetY then return cur.path end
            for _, d in ipairs(dirs) do
                local nx, ny = cur.x + d.x, cur.y + d.y
                if isWalkable(nx, ny) then
                    local newCost = cur.cost + 1
                    if not visited[nx..","..ny] or newCost < visited[nx..","..ny] then
                        visited[nx..","..ny] = newCost
                        local newPath = {unpack(cur.path)}
                        table.insert(newPath, Vector3.new(nx * 4.5, ny * 4.5, 0))
                        table.insert(queue, {x=nx, y=ny, path=newPath, cost=newCost})
                    end
                end
            end
        end
        return nil
    end

    local function WalkToGrid(targetX, targetY)
        local HitboxFolder = workspace:FindFirstChild("Hitbox")
        local MyHitbox = HitboxFolder and HitboxFolder:FindFirstChild(LP.Name)
        if not MyHitbox then StatusLabel:SetText("Status: Hitbox tidak ditemukan!") return false end

        local sx = math.floor(MyHitbox.Position.X / 4.5 + 0.5)
        local sy = math.floor(MyHitbox.Position.Y / 4.5 + 0.5)
        if sx == targetX and sy == targetY then return true end

        local path = findSmartPath(sx, sy, targetX, targetY)
        if not path then StatusLabel:SetText("Status: Path tidak ditemukan!") return false end

        for i, point in ipairs(path) do
            if _G.LatestRunToken ~= myToken or not Drop.Enabled then break end
            StatusLabel:SetText(string.format("Status: Jalan (%d/%d)", i, #path))
            MyHitbox.CFrame = CFrame.new(point.X, point.Y, MyHitbox.Position.Z)
            movementModule.Position = MyHitbox.Position
            task.wait(Drop.StepDelay)

            local char = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if char then
                local dist = (Vector2.new(char.Position.X, char.Position.Y) - Vector2.new(point.X, point.Y)).Magnitude
                if dist > 5 then
                    lockedDoors[math.floor(point.X/4.5+0.5)..","..math.floor(point.Y/4.5+0.5)] = true
                    break
                end
            end
        end
        return true
    end

    -- ========================================
    -- [8] GRAVITY BYPASS
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait()
            if Drop.Enabled then
                pcall(function()
                    if movementModule.VelocityY < 0 then movementModule.VelocityY = 0 end
                    movementModule.Grounded = true
                end)
            end
        end
    end)

    -- ========================================
    -- [9] MAIN LOOP
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            pcall(function()
                if Drop.TargetID then
                    ScanLabel:SetText("ID Target: " .. tostring(Drop.TargetID))
                    StokLabel:SetText("Stok Sekarang: " .. GetItemAmount(Drop.TargetID))
                end
            end)

            if Drop.Enabled then
                pcall(function()
                    if not Drop.TargetID then
                        StatusLabel:SetText("Status: Belum scan ID item!")
                        return
                    end
                    if not Drop.DropPoint then
                        StatusLabel:SetText("Status: Belum set Drop Point!")
                        return
                    end
                    if not Drop.ReturnPoint then
                        StatusLabel:SetText("Status: Belum set Return Point!")
                        return
                    end

                    local current = GetItemAmount(Drop.TargetID)
                    if current <= Drop.MaxStack then
                        StatusLabel:SetText(string.format("Status: Monitoring... (%d/%d)", current, Drop.MaxStack))
                        return
                    end

                    -- [1] Jalan ke drop point
                    StatusLabel:SetText("Status: Jalan ke Drop Point...")
                    WalkToGrid(Drop.DropPoint.x, Drop.DropPoint.y)

                    -- [2] Drop sampai bersih
                    if Drop.Enabled then DropUntilClean() end

                    -- [3] Balik ke return point
                    if Drop.Enabled and _G.LatestRunToken == myToken then
                        StatusLabel:SetText("Status: Balik ke Return Point...")
                        WalkToGrid(Drop.ReturnPoint.x, Drop.ReturnPoint.y)
                        StatusLabel:SetText("Status: Selesai, monitoring...")
                    end
                end)
            else
                StatusLabel:SetText("Status: Nonaktif")
            end

            task.wait(1)
        end
    end)
end
