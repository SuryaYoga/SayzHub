return function(SubTab, Window)
    -- ========================================
    -- [1] VARIABEL & SETUP
    -- ========================================
    -- Merujuk ke Pusat Data di Main.lua
    local PnB = getgenv().SayzSettings.PnB 
    local worldData = require(game.ReplicatedStorage.WorldTiles)
    local LP = game.Players.LocalPlayer
    
    -- Variabel internal untuk status transisi
    _G.LastPnBState = "Waiting" 

    -- ========================================
    -- [2] UI ELEMENTS
    -- ========================================
    SubTab:AddSection("EKSEKUSI")
    SubTab:AddToggle("Master Switch", PnB.Master, function(t) PnB.Master = t end)
    SubTab:AddToggle("Enable Place", PnB.Place, function(t) PnB.Place = t end)
    SubTab:AddToggle("Enable Break", PnB.Break, function(t) PnB.Break = t end)

    SubTab:AddSection("SCANNER")
    SubTab:AddButton("Scan ID Item", function()
        PnB.Scanning = true
        Window:Notify("Pasang 1 blok manual untuk scan!", 3, "info")
    end)
    local InfoLabel = SubTab:AddLabel("ID Aktif: None")
    local StokLabel = SubTab:AddLabel("Total Stok: 0")

    SubTab:AddSection("SETTING")
    -- Default value mengambil dari tabel PnB.DelayScale
    SubTab:AddInput("Speed Scale (Min 0.1)", tostring(PnB.DelayScale), function(v)
        local val = tonumber(v) or 1
        if val < 0.1 then val = 0.1 end
        PnB.DelayScale = val
        PnB.ActualDelay = val * 0.12
    end)

    SubTab:AddSection("GRID TARGET (5x5)")
    SubTab:AddGridSelector(function(selectedTable)
        PnB.SelectedTiles = selectedTable
        
        -- Auto-Set Origin saat memilih grid
        local char = LP.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            PnB.OriginGrid = {
                x = math.floor((root.Position.X / 4.475) + 0.5),
                y = math.floor(((root.Position.Y - 2.5) / 4.435) + 0.5)
            }
        end
    end)

    SubTab:AddToggle("Lock Position", PnB.LockPosition, function(t) 
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

    SubTab:AddDropdown("Multi-Break Mode", {"Mode 1 (Fokus)", "Mode 2 (Rata)"}, PnB.BreakMode, function(v)
        PnB.BreakMode = v
    end)

    -- ========================================
    -- [3] FUNCTIONS HELPER
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
        pcall(function()
            InfoLabel:SetText("ID Aktif: " .. tostring(PnB.TargetID or "None"))
            StokLabel:SetText("Total Stok: " .. getActiveAmount())
        end)
    end

    -- Hook Metamethod untuk Scanner
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        if PnB.Scanning and self.Name == "PlayerPlaceItem" and method == "FireServer" then
            PnB.TargetID = args[2]
            PnB.Scanning = false
            Window:Notify("ID Scanned: " .. tostring(args[2]), 2, "ok")
        end
        return oldNamecall(self, ...)
    end)

    -- ========================================
    -- [4] MAIN LOOP (EKSEKUSI)
    -- ========================================
    task.spawn(function()
        while true do
            if PnB.Master then
                pcall(function()
                    local char = LP.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    if not root then return end

                    -- Tentukan Base Grid
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

                    -- Ambil data target dari Grid Selector
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

                    -- LOGIKA PLACE
                    if PnB.Place and maxTiles > 0 and filledCount < maxTiles then
                        if filledCount == 0 or _G.LastPnBState == "Placing" then
                            _G.LastPnBState = "Placing"
                            if getActiveAmount() > 0 then
                                for _, tile in ipairs(areaData) do
                                    if not tile.isFilled and PnB.Master then
                                        game.ReplicatedStorage.Remotes.PlayerPlaceItem:FireServer(tile.pos, PnB.TargetID, 1)
                                        task.wait(PnB.PlaceDelay)
                                    end
                                end
                            end
                        end
                    end

                    areaData, filledCount = getAreaInfo()

                    -- LOGIKA BREAK
                    if PnB.Break and filledCount > 0 then
                        if filledCount == maxTiles or _G.LastPnBState == "Breaking" or (not PnB.Place) then
                            _G.LastPnBState = "Breaking"
                            if PnB.BreakMode == "Mode 1 (Fokus)" then
                                for _, tile in ipairs(areaData) do
                                    if tile.isFilled then
                                        while PnB.Master and PnB.Break do
                                            local check = worldData[tile.pos.X] and worldData[tile.pos.X][tile.pos.Y] and worldData[tile.pos.X][tile.pos.Y][tile.layer]
                                            if check == nil then break end 
                                            game.ReplicatedStorage.Remotes.PlayerFist:FireServer(tile.pos)
                                            task.wait(0.035)
                                        end
                                    end
                                end
                            else -- Mode Sweep
                                while filledCount > 0 and PnB.Master and PnB.Break do
                                    for _, tile in ipairs(areaData) do
                                        if tile.isFilled then
                                            game.ReplicatedStorage.Remotes.PlayerFist:FireServer(tile.pos)
                                            task.wait(0.02)
                                        end
                                    end
                                    areaData, filledCount = getAreaInfo()
                                end
                            end
                            if filledCount == 0 then
                                _G.LastPnBState = "Waiting"
                                task.wait(PnB.ActualDelay)
                            end
                        end
                    end
                end)
            end
            updatePnBVisuals()
            task.wait(0.01)
        end
    end)
end
