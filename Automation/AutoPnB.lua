return function(SubTab, Window, myToken)
    local PnB = getgenv().SayzSettings.PnB 
    local worldData = require(game.ReplicatedStorage.WorldTiles)
    local LP = game.Players.LocalPlayer
    
    _G.LastPnBState = "Waiting" 

    -- ========================================
    -- [UI ELEMENTS]
    -- ========================================
    SubTab:AddSection("EKSEKUSI UTAMA")
    getgenv().SayzUI_Handles["PnB_Master"] = SubTab:AddToggle("Master Switch", PnB.Master, function(t) PnB.Master = t end)
    getgenv().SayzUI_Handles["PnB_Place"] = SubTab:AddToggle("Enable Place", PnB.Place, function(t) PnB.Place = t end)
    getgenv().SayzUI_Handles["PnB_Break"] = SubTab:AddToggle("Enable Break", PnB.Break, function(t) PnB.Break = t end)
    
    -- Toggle khusus untuk Smart Collect di Grid
    getgenv().SayzUI_Handles["PnB_SmartCollect"] = SubTab:AddToggle("Smart Collect (In Grid)", PnB.AutoCollectInGrid, function(t) 
        PnB.AutoCollectInGrid = t 
    end)

    SubTab:AddSection("SCANNER & INFO")
    SubTab:AddButton("Scan ID Item", function()
        PnB.Scanning = true
        Window:Notify("Pasang 1 blok manual untuk scan!", 3, "info")
    end)
    local InfoLabel = SubTab:AddLabel("ID Aktif: None")
    local StokLabel = SubTab:AddLabel("Total Stok: 0")

    SubTab:AddSection("PENGATURAN")
    getgenv().SayzUI_Handles["PnB_SpeedScale"] = SubTab:AddInput("Speed Scale", "1", function(v)
        local val = tonumber(v) or 1
        if val < 0.1 then val = 0.1 end
        PnB.DelayScale = val
        PnB.ActualDelay = val * 0.12
    end)

    getgenv().SayzUI_Handles["PnB_LockPos"] = SubTab:AddToggle("Lock Position", PnB.LockPosition, function(t) 
        PnB.LockPosition = t 
    end)

    SubTab:AddSection("GRID SELECTOR")
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

    -- ========================================
    -- [HELPER FUNCTIONS]
    -- ========================================
    local function GetDropsInGrid(areaData)
        local drops = {}
        for _, tile in ipairs(areaData) do
            for _, folder in pairs({"Drops", "Gems"}) do
                local container = workspace:FindFirstChild(folder)
                if container then
                    for _, item in pairs(container:GetChildren()) do
                        local pos = item:GetPivot().Position
                        local ix, iy = math.floor(pos.X/4.5+0.5), math.floor(pos.Y/4.5+0.5)
                        if ix == tile.pos.X and iy == tile.pos.Y then
                            table.insert(drops, item)
                        end
                    end
                end
            end
        end
        return drops
    end

    local function getActiveAmount()
        local total = 0
        local success, invModule = pcall(function() return require(game.ReplicatedStorage.Modules.Inventory) end)
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

    -- ========================================
    -- [LOOP EKSEKUSI]
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            if PnB.Master then
                pcall(function()
                    local char = LP.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    if not root then return end

                    -- Tentukan Origin
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

                    -- Fungsi internal untuk update data grid setiap siklus
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
                            local tx, ty = baseGrid.x + offset.ox, baseGrid.y + offset.oy
                            local tileData = worldData[tx] and worldData[tx][ty]
                            local blockExist = tileData and tileData[1] ~= nil
                            local isFilled = blockExist or (tileData and tileData[2] ~= nil)
                            table.insert(targets, {pos = Vector2.new(tx, ty), isFilled = isFilled, layer = blockExist and 1 or 2})
                            if isFilled then currentFilled = currentFilled + 1 end
                        end
                        return targets, currentFilled
                    end

                    local areaData, filledCount = getAreaInfo()
                    local maxTiles = #areaData

                    -- 1. BREAK STATE
                    if PnB.Break and filledCount > 0 and (_G.LastPnBState == "Breaking" or filledCount == maxTiles or not PnB.Place) then
                        _G.LastPnBState = "Breaking"
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
                    end

                    -- 2. SMART COLLECT STATE (Setelah Break Berhasil)
                    if PnB.AutoCollectInGrid and PnB.Master then
                        local drops = GetDropsInGrid(areaData)
                        if #drops > 0 then
                            local originalPos = root.CFrame
                            for _, item in ipairs(drops) do
                                if _G.LatestRunToken ~= myToken or not PnB.Master then break end
                                if item.Parent then
                                    root.CFrame = item:GetPivot()
                                    task.wait(0.05)
                                end
                            end
                            root.CFrame = originalPos
                            task.wait(0.1)
                        end
                    end

                    -- 3. PLACE STATE
                    areaData, filledCount = getAreaInfo()
                    if PnB.Place and filledCount < maxTiles and (_G.LastPnBState == "Placing" or filledCount == 0) then
                        _G.LastPnBState = "Placing"
                        if getActiveAmount() > 0 then
                            for _, tile in ipairs(areaData) do
                                if _G.LatestRunToken ~= myToken or not PnB.Master then break end
                                if not tile.isFilled then
                                    game.ReplicatedStorage.Remotes.PlayerPlaceItem:FireServer(tile.pos, PnB.TargetID, 1)
                                    task.wait(PnB.PlaceDelay or 0.05)
                                end
                            end
                        end
                    end

                    if filledCount == 0 and not PnB.Place then _G.LastPnBState = "Waiting" end
                end)
            end
            pcall(function()
                InfoLabel:SetText("ID Aktif: " .. tostring(PnB.TargetID or "None"))
                StokLabel:SetText("Total Stok: " .. getActiveAmount())
            end)
            task.wait(0.01)
        end
    end)
end
