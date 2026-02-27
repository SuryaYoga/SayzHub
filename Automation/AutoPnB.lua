return function(SubTab, Window, myToken)
    -- ========================================
    -- [1] SETUP & SETTINGS
    -- ========================================
    local PnB = getgenv().SayzSettings.PnB 
    local worldData = require(game.ReplicatedStorage.WorldTiles)
    local LP = game.Players.LocalPlayer
    
    _G.LastPnBState = "Waiting" 

    -- ========================================
    -- [2] UI ELEMENTS
    -- ========================================
    SubTab:AddSection("EKSEKUSI UTAMA")
    getgenv().SayzUI_Handles["PnB_Master"] = SubTab:AddToggle("Master Switch", PnB.Master, function(t) PnB.Master = t end)
    getgenv().SayzUI_Handles["PnB_Place"] = SubTab:AddToggle("Enable Place", PnB.Place, function(t) PnB.Place = t end)
    getgenv().SayzUI_Handles["PnB_Break"] = SubTab:AddToggle("Enable Break", PnB.Break, function(t) PnB.Break = t end)
    
    getgenv().SayzUI_Handles["PnB_SmartCollect"] = SubTab:AddToggle("Smart Collect (Grid)", PnB.AutoCollectInGrid, function(t) 
        PnB.AutoCollectInGrid = t 
    end)

    SubTab:AddSection("SCANNER & INFO")
    SubTab:AddButton("Scan ID Item", function()
        PnB.Scanning = true
        Window:Notify("Pasang 1 blok manual untuk scan!", 3, "info")
    end)
    local InfoLabel = SubTab:AddLabel("ID Aktif: None")
    local StokLabel = SubTab:AddLabel("Total Stok: 0")

    -- ========================================
    -- [3] HELPER FUNCTIONS
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
            if targetIndex and invModule.Stacks[targetIndex] then
                local targetItemId = invModule.Stacks[targetIndex].Id
                for _, stack in pairs(invModule.Stacks) do
                    if stack and stack.Id == targetItemId then
                        total = total + (stack.Amount or 0)
                    end
                end
            end
        end
        return total
    end

    -- Scanner Hook
    if not _G.OldHookSet then
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
        _G.OldHookSet = true
    end

    -- ========================================
    -- [4] DYNAMIC MAIN LOOP
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            if PnB.Master then
                pcall(function()
                    local char = LP.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    if not root then return end

                    local baseGrid = (PnB.LockPosition and PnB.OriginGrid) or {
                        x = math.floor((root.Position.X / 4.475) + 0.5),
                        y = math.floor(((root.Position.Y - 2.5) / 4.435) + 0.5)
                    }

                    local function getAreaInfo()
                        local targets, currentFilled, selectedList = {}, 0, {}
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
                            local wallExist = tileData and tileData[2] ~= nil
                            local isFilled = blockExist or wallExist
                            table.insert(targets, {pos = Vector2.new(tx, ty), isFilled = isFilled, layer = blockExist and 1 or 2})
                            if isFilled then currentFilled = currentFilled + 1 end
                        end
                        return targets, currentFilled
                    end

                    local areaData, filledCount = getAreaInfo()
                    local maxTiles = #areaData

                    -- ----------------------------------------------------
                    -- PRIORITAS 1: BREAK (Harus bersih dulu)
                    -- ----------------------------------------------------
                    if PnB.Break and filledCount > 0 then
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

                    -- ----------------------------------------------------
                    -- PRIORITAS 2: SMART COLLECT (Jika aktif, harus ambil dulu)
                    -- ----------------------------------------------------
                    areaData, filledCount = getAreaInfo() -- Refresh data
                    local drops = GetDropsInGrid(areaData)
                    
                    if PnB.AutoCollectInGrid and PnB.Master and #drops > 0 then
                        _G.LastPnBState = "Collecting"
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

                    -- ----------------------------------------------------
                    -- PRIORITAS 3: PLACE (Hanya jika Break selesai & (Collect mati atau Barang habis))
                    -- ----------------------------------------------------
                    areaData, filledCount = getAreaInfo() -- Refresh lagi
                    local dropsNow = GetDropsInGrid(areaData)
                    
                    -- Logika Cerdas: Boleh Place kalau (Auto Collect Mati) ATAU (Auto Collect Nyala dan Barang di Grid sudah 0)
                    local canPlace = (not PnB.AutoCollectInGrid) or (PnB.AutoCollectInGrid and #dropsNow == 0)

                    if PnB.Place and filledCount < maxTiles and canPlace then
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

                    if filledCount == 0 and #dropsNow == 0 then _G.LastPnBState = "Waiting" end
                end)
            end
            
            pcall(function()
                InfoLabel:SetText("ID Aktif: " .. tostring(PnB.TargetID or "None"))
                StokLabel:SetText("Total Stok: " .. getActiveAmount())
            end)
            task.wait(0.1)
        end
    end)
end
