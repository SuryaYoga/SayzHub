return function(SubTab, Window)
    -- ========================================
    -- [1] VARIABEL & SETUP (SINKRONISASI PUSAT)
    -- ========================================
    
    -- Cek apakah tabel utama ada, jika tidak ada buat tabel darurat agar tidak error
    if not getgenv().SayzSettings then getgenv().SayzSettings = {} end
    if not getgenv().SayzSettings.PnB then
        getgenv().SayzSettings.PnB = {
            Master = false,
            Place = false,
            Break = false,
            Scanning = false,
            TargetID = nil,
            DelayScale = 1,
            ActualDelay = 0.12,
            PlaceDelay = 0.1,
            SelectedTiles = {},
            OriginGrid = nil,
            LockPosition = false,
            BreakMode = "Mode 1 (Fokus)"
        }
    end

    -- Sekarang kita ambil variabelnya dengan aman
    local PnB = getgenv().SayzSettings.PnB 
    local worldData = require(game.ReplicatedStorage.WorldTiles)
    local LP = game.Players.LocalPlayer
    
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
    local InfoLabel = SubTab:AddLabel("ID Aktif: " .. tostring(PnB.TargetID or "None"))
    local StokLabel = SubTab:AddLabel("Total Stok: 0")

    SubTab:AddSection("SETTING")
    SubTab:AddInput("Speed Scale (Min 0.1)", tostring(PnB.DelayScale or 1), function(v)
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
    -- [4] MAIN LOOP (DENGAN KILL SWITCH KETAT)
    -- ========================================
    local MyRunID = getgenv().SayzLatestRunID -- Menangkap ID eksekusi saat ini

    task.spawn(function()
        -- Loop Utama
        while true do
            -- CEK KILL SWITCH: Berhenti jika ID berubah atau UI di-close
            if getgenv().SayzLatestRunID ~= MyRunID or not getgenv().SayzSettings then
                print("PnB: Loop lama dihentikan.")
                break 
            end

            if PnB.Master then
                pcall(function()
                    local char = LP.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    if not root then return end

                    -- Tentukan Base Grid (Lock Position Logic)
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

                    -- Ambil Area Info
                    local areaData, filledCount = getAreaInfo()
                    local maxTiles = #areaData

                    -- [[ LOGIKA PLACE ]] --
                    if PnB.Place and maxTiles > 0 and filledCount < maxTiles then
                        if filledCount == 0 or _G.LastPnBState == "Placing" then
                            _G.LastPnBState = "Placing"
                            if getActiveAmount() > 0 then
                                for _, tile in ipairs(areaData) do
                                    -- EMERGENCY CHECK di tengah perulangan pasang
                                    if getgenv().SayzLatestRunID ~= MyRunID or not PnB.Master then break end
                                    
                                    if not tile.isFilled then
                                        game.ReplicatedStorage.Remotes.PlayerPlaceItem:FireServer(tile.pos, PnB.TargetID, 1)
                                        task.wait(PnB.PlaceDelay)
                                    end
                                end
                            end
                        end
                    end

                    areaData, filledCount = getAreaInfo()

                    -- [[ LOGIKA BREAK ]] --
                    if PnB.Break and filledCount > 0 then
                        if filledCount == maxTiles or _G.LastPnBState == "Breaking" or (not PnB.Place) then
                            _G.LastPnBState = "Breaking"
                            
                            if PnB.BreakMode == "Mode 1 (Fokus)" then
                                for _, tile in ipairs(areaData) do
                                    -- EMERGENCY CHECK sebelum pindah ke blok berikutnya
                                    if getgenv().SayzLatestRunID ~= MyRunID or not PnB.Master then break end
                                    
                                    if tile.isFilled then
                                        while PnB.Master and PnB.Break do
                                            -- EMERGENCY CHECK di tengah-tengah mukul (biar langsung berhenti)
                                            if getgenv().SayzLatestRunID ~= MyRunID then break end
                                            
                                            local check = worldData[tile.pos.X] and worldData[tile.pos.X][tile.pos.Y] and worldData[tile.pos.X][tile.pos.Y][tile.layer]
                                            if check == nil then break end 
                                            game.ReplicatedStorage.Remotes.PlayerFist:FireServer(tile.pos)
                                            task.wait(0.035)
                                        end
                                    end
                                end
                            else -- Mode Sweep
                                while filledCount > 0 and PnB.Master and PnB.Break do
                                    -- EMERGENCY CHECK di tengah perulangan sweep
                                    if getgenv().SayzLatestRunID ~= MyRunID then break end
                                    
                                    for _, tile in ipairs(areaData) do
                                        if tile.isFilled and getgenv().SayzLatestRunID == MyRunID then
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




