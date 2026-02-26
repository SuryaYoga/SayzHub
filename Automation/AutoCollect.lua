return function(SubTab, Window)
    local LP = game:GetService("Players").LocalPlayer
    local WorldTiles = require(game.ReplicatedStorage.WorldTiles)
    local movementModule = require(LP.PlayerScripts.PlayerMovement)

    getgenv().AutoCollect = getgenv().AutoCollect or false
    getgenv().TakeGems = getgenv().TakeGems or true 
    getgenv().StepDelay = getgenv().StepDelay or 0.05 
    getgenv().ItemBlacklist = getgenv().ItemBlacklist or {} 

    local LIMIT = { MIN_X = 0, MAX_X = 100, MIN_Y = 6, MAX_Y = 60 }
    local doorDatabase = {} 
    local lockedDoors = {} 
    local badItems = {} 
    local blacklistCoords = {}

    local function InitDoorDatabase()
        doorDatabase = {}
        for gx, columns in pairs(WorldTiles) do
            for gy, tileData in pairs(columns) do
                local l1 = tileData[1]
                local itemName = (type(l1) == "table") and l1[1] or l1
                if itemName and string.find(string.lower(tostring(itemName)), "door") then
                    doorDatabase[gx .. "," .. gy] = true
                end
            end
        end
    end

    local function UpdateBlacklistCache()
        blacklistCoords = {}
        for _, folder in pairs({"Drops", "Gems"}) do
            local c = workspace:FindFirstChild(folder)
            if c then
                for _, item in pairs(c:GetChildren()) do
                    local id = item:GetAttribute("id") or item.Name
                    if getgenv().ItemBlacklist[id] then
                        local ix = math.floor(item:GetPivot().Position.X/4.5+0.5)
                        local iy = math.floor(item:GetPivot().Position.Y/4.5+0.5)
                        blacklistCoords[ix .. "," .. iy] = true
                    end
                end
            end
        end
    end

    -- [[ UI SECTION ]] --
    SubTab:AddSection("CONTROL PANEL")
    SubTab:AddToggle("Enable Auto Collect", getgenv().AutoCollect, function(s) 
        getgenv().AutoCollect = s 
        if s then InitDoorDatabase() end
    end)
    SubTab:AddToggle("Collect Gems", getgenv().TakeGems, function(s) getgenv().TakeGems = s end)
    
    SubTab:AddInput("Step Delay", tostring(getgenv().StepDelay), function(v)
        getgenv().StepDelay = tonumber(v) or 0.05
    end)

    -- ITEM FILTER (SEKARANG DI ATAS)
    SubTab:AddSection("ITEM FILTER")
    local MultiDrop
    MultiDrop = sub:AddMultiDropdown("Blacklist Items", {}, function(selected)
        getgenv().ItemBlacklist = selected
        UpdateBlacklistCache()
    end)

    SubTab:AddButton("Scan World Items", function()
        local items = {}
        local folders = {"Drops"}
        if getgenv().TakeGems then table.insert(folders, "Gems") end
        for _, f in pairs(folders) do
            local c = workspace:FindFirstChild(f)
            if c then for _, item in pairs(c:GetChildren()) do
                local id = item:GetAttribute("id") or item.Name
                if not table.find(items, id) then table.insert(items, id) end
            end end
        end
        MultiDrop:UpdateList(items)
    end)

    SubTab:AddButton("Reset Filters & Bad Items", function()
        getgenv().ItemBlacklist = {}
        badItems = {}
        lockedDoors = {}
        MultiDrop:ClearAll() -- Memanggil fungsi reset di Library
        UpdateBlacklistCache()
        Window:Notify("Memory & Blacklist Cleared!", 2)
    end)

    -- LIVE STATISTICS (SEKARANG DI BAWAH)
    SubTab:AddSection("LIVE STATISTICS")
    local ItemLabel = SubTab:AddLabel("Items on Map: 0")
    local TargetLabel = SubTab:AddLabel("Target: None")
    local StatusLabel = SubTab:AddLabel("Status: Idle")

    -- [[ CORE LOGIC & MAIN LOOP - TETAP UTUH ]] --
    -- (Bagian findSmartPath, Gravity Bypass, dan Loop tetap sama seperti sebelumnya)
    -- ... (Saya asumsikan kamu menempelkan logic loop dari script "gemuk" sebelumnya)
