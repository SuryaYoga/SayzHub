return function(SubTab, Window, myToken)
    -- [[ 1. SETUP & VARIABLES ]] --
    local LP = game:GetService("Players").LocalPlayer
    local WorldTiles = require(game.ReplicatedStorage.WorldTiles)
    local movementModule = require(LP.PlayerScripts.PlayerMovement)
    local IM = require(game:GetService("ReplicatedStorage").Managers.ItemsManager)

    getgenv().AutoCollect       = getgenv().AutoCollect       or false
    getgenv().TakeGems          = getgenv().TakeGems          or true
    getgenv().StepDelay         = getgenv().StepDelay         or 0.05
    getgenv().ItemBlacklist     = getgenv().ItemBlacklist     or {}
    getgenv().AvoidanceStrength = getgenv().AvoidanceStrength or 50

    local LIMIT = { MIN_X = 0, MAX_X = 100, MIN_Y = 6, MAX_Y = 60 }
    local doorDatabase = {}
    local lockedDoors  = {}
    local badItems     = {}
    local currentPool  = {}

    -- =============================================
    -- [[ 2. TILE HELPERS ]]
    -- =============================================

    -- Whitelist tile yang bisa dilewati karakter.
    -- Default: tile yang ada di worldData = solid (hard block).
    -- Tambahin di sini kalau ketemu tile baru yang bisa dilewati.
    local function isPassableTile(n)
        if string.find(n, "door")       then return true end
        if string.find(n, "frame")      then return true end
        if string.find(n, "sapling")    then return true end
        if string.find(n, "background") then return true end
        -- tambahin tile passable lain di sini
        return false
    end

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

    -- Cek apakah tile (gx,gy) punya item blacklist di atasnya
    local function hasBlacklistedItemAt(gx, gy)
        local folders = {"Drops"}
        if getgenv().TakeGems then table.insert(folders, "Gems") end
        for _, folderName in pairs(folders) do
            local container = workspace:FindFirstChild(folderName)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    local itPos = item:GetPivot().Position
                    local itX = math.floor(itPos.X / 4.5 + 0.5)
                    local itY = math.floor(itPos.Y / 4.5 + 0.5)
                    if itX == gx and itY == gy then
                        local id = item:GetAttribute("id") or item.Name
                        if getgenv().ItemBlacklist[id] then
                            return true
                        end
                    end
                end
            end
        end
        return false
    end

    -- isWalkable standar: hard block solid + lockedDoor, soft avoidance item filter
    local function isWalkable(gx, gy)
        if gx < LIMIT.MIN_X or gx > LIMIT.MAX_X or gy < LIMIT.MIN_Y or gy > LIMIT.MAX_Y then
            return false, false
        end
        if lockedDoors[gx .. "," .. gy] then
            return false, false
        end
        local hasBlacklist = hasBlacklistedItemAt(gx, gy)
        if WorldTiles[gx] and WorldTiles[gx][gy] then
            local l1 = WorldTiles[gx][gy][1]
            local itemName = (type(l1) == "table") and l1[1] or l1
            if itemName then
                local n = string.lower(tostring(itemName))
                if isPassableTile(n) then
                    return true, hasBlacklist
                end
                return false, false  -- solid tile
            end
        end
        return true, hasBlacklist  -- tile kosong
    end



    -- =============================================
    -- [[ 3. PATHFINDING ]]
    -- findSmartPath: ganti table.sort tiap iterasi
    -- → linear scan cari minimum (lebih ringan)
    -- =============================================

    local function findSmartPath(startX, startY, targetX, targetY)
        local queue   = {{x = startX, y = startY, path = {}, cost = 0}}
        local visited = {[startX .. "," .. startY] = 0}
        local dirs    = {
            {x=1,y=0},{x=-1,y=0},
            {x=0,y=1},{x=0,y=-1}
        }
        local limitCount = 0
        while #queue > 0 do
            if _G.LatestRunToken ~= myToken then break end
            limitCount = limitCount + 1
            if limitCount > 4000 then break end

            -- Linear scan cari node cost terendah (O(n) vs O(n log n) sort)
            local minIdx, minCost = 1, queue[1].cost
            for i = 2, #queue do
                if queue[i].cost < minCost then
                    minCost = queue[i].cost
                    minIdx  = i
                end
            end
            local current = table.remove(queue, minIdx)

            if current.x == targetX and current.y == targetY then
                return current.path
            end

            for _, d in ipairs(dirs) do
                local nx, ny = current.x + d.x, current.y + d.y
                local walkable, isBlacklisted = isWalkable(nx, ny)
                if walkable then
                    local moveCost = isBlacklisted and getgenv().AvoidanceStrength or 1
                    local newCost  = current.cost + moveCost
                    if not visited[nx..","..ny] or newCost < visited[nx..","..ny] then
                        visited[nx..","..ny] = newCost
                        local newPath = {unpack(current.path)}
                        table.insert(newPath, Vector3.new(nx * 4.5, ny * 4.5, 0))
                        table.insert(queue, {x=nx, y=ny, path=newPath, cost=newCost})
                    end
                end
            end
        end
        return nil
    end

    -- =============================================
    -- [[ 4. RAYCAST GRID (seleksi kandidat) ]]
    -- Cek lurus dari (sx,sy) ke (tx,ty) tile per tile.
    -- Kalau ada solid tile atau item filter di tengah = blocked.
    -- Ringan: O(distance), tidak perlu queue/sort sama sekali.
    -- =============================================

    local function raycastClear(sx, sy, tx, ty)
        local dx = tx - sx
        local dy = ty - sy
        local steps = math.max(math.abs(dx), math.abs(dy))
        if steps == 0 then return true end

        for i = 1, steps - 1 do  -- tidak cek tile start dan tile target
            local cx = math.floor(sx + (dx / steps) * i + 0.5)
            local cy = math.floor(sy + (dy / steps) * i + 0.5)

            -- Cek solid tile
            local walkable, _ = isWalkable(cx, cy)
            if not walkable then return false end

            -- Cek item filter (hard block untuk seleksi)
            if hasBlacklistedItemAt(cx, cy) then return false end
        end
        return true
    end

    -- =============================================
    -- [[ 5. ITEM SELECTION ]]
    -- Raycast tiap kandidat → pilih paling jauh yang bersih
    -- =============================================

    local function GetBestTarget(Hitbox)
        local sx = math.floor(Hitbox.Position.X / 4.5 + 0.5)
        local sy = math.floor(Hitbox.Position.Y / 4.5 + 0.5)

        local folders = {"Drops"}
        if getgenv().TakeGems then table.insert(folders, "Gems") end

        local bestItem = nil
        local bestDist = -1
        local fallbackItem = nil
        local fallbackDist = math.huge

        for _, folder in pairs(folders) do
            local container = workspace:FindFirstChild(folder)
            if container then
                for _, item in pairs(container:GetChildren()) do
                    if not badItems[item] then
                        local id = item:GetAttribute("id") or item.Name
                        if not getgenv().ItemBlacklist[id] then
                            local pos  = item:GetPivot().Position
                            local tx   = math.floor(pos.X / 4.5 + 0.5)
                            local ty   = math.floor(pos.Y / 4.5 + 0.5)
                            local dist = (Vector2.new(pos.X, pos.Y) - Vector2.new(
                                Hitbox.Position.X, Hitbox.Position.Y
                            )).Magnitude

                            -- Raycast: bersih dari solid & item filter?
                            if raycastClear(sx, sy, tx, ty) then
                                -- Kandidat bersih → pilih paling jauh
                                if dist > bestDist then
                                    bestDist = dist
                                    bestItem = item
                                end
                            else
                                -- Tidak bersih → simpan sebagai fallback nearest
                                if dist < fallbackDist then
                                    fallbackDist = dist
                                    fallbackItem = item
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Prioritas: kandidat bersih paling jauh
        -- Fallback: nearest biasa kalau semua terhalang
        return bestItem or fallbackItem
    end

    -- =============================================
    -- [[ 5. WALK TO POINT ]]
    -- =============================================

    local function WalkToTarget(Hitbox, target, StatusLabel, TargetLabel)
        local tx = math.floor(target:GetPivot().Position.X / 4.5 + 0.5)
        local ty = math.floor(target:GetPivot().Position.Y / 4.5 + 0.5)
        local sx = math.floor(Hitbox.Position.X / 4.5 + 0.5)
        local sy = math.floor(Hitbox.Position.Y / 4.5 + 0.5)

        local path = findSmartPath(sx, sy, tx, ty)
        if not path then
            badItems[target] = true
            return false
        end

        local tName = IM.GetName(target:GetAttribute("id") or target.Name) or "Item"
        TargetLabel:SetText("Target: " .. tName)

        for i, point in ipairs(path) do
            if not getgenv().AutoCollect or _G.LatestRunToken ~= myToken then break end

            StatusLabel:SetText("Status: Walking (" .. i .. "/" .. #path .. ")")
            Hitbox.CFrame = CFrame.new(point.X, point.Y, Hitbox.Position.Z)
            movementModule.Position = Hitbox.Position
            task.wait(getgenv().StepDelay)

            -- Deteksi rubberband / pintu tertutup
            -- Tunggu beberapa frame dulu sebelum cek supaya server settle
            task.wait(getgenv().StepDelay)
            local char = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if char then
                local dist = (
                    Vector2.new(char.Position.X, char.Position.Y) -
                    Vector2.new(point.X, point.Y)
                ).Magnitude

                if dist > 5 then
                    -- Cari pintu di jalur yang menyebabkan stuck
                    -- (bukan blacklist tile random)
                    local doorFound = false
                    for _, p in ipairs(path) do
                        local px = math.floor(p.X / 4.5 + 0.5)
                        local py = math.floor(p.Y / 4.5 + 0.5)
                        if doorDatabase[px .. "," .. py] then
                            lockedDoors[px .. "," .. py] = true
                            doorFound = true
                            break
                        end
                    end
                    -- Kalau tidak ada pintu di jalur sama sekali,
                    -- kemungkinan rubberband biasa — jangan blacklist apapun
                    if not doorFound then
                        -- skip step ini saja, lanjut path berikutnya
                        -- (tidak blacklist item maupun tile)
                    end
                    return false
                end
            end
        end
        return true
    end

    -- =============================================
    -- [[ 6. UI ELEMENTS ]]
    -- =============================================

    SubTab:AddSection("Auto Collect Master")

    getgenv().SayzUI_Handles["AutoCollectEnabled"] = SubTab:AddToggle("Enable Auto Collect", getgenv().AutoCollect, function(state)
        getgenv().AutoCollect = state
        if state then
            InitDoorDatabase()
            badItems = {}  -- reset tiap enable
        end
    end)

    getgenv().SayzUI_Handles["TakeGemsToggle"] = SubTab:AddToggle("Collect Gems", getgenv().TakeGems, function(state)
        getgenv().TakeGems = state
    end)

    SubTab:AddSection("Path & Speed Settings")

    getgenv().SayzUI_Handles["StepDelaySlider"] = SubTab:AddSlider("Movement Speed", 0.01, 0.2, getgenv().StepDelay, function(val)
        getgenv().StepDelay = val
    end, 2)

    getgenv().SayzUI_Handles["AvoidanceInput"] = SubTab:AddInput("Avoidance Radius (Cost)", tostring(getgenv().AvoidanceStrength), function(v)
        local val = tonumber(v)
        if val then
            getgenv().AvoidanceStrength = val
            Window:Notify("Avoidance set to: " .. val, 2)
        end
    end)

    SubTab:AddSection("Filter Management")
    local FilterLabel = SubTab:AddLabel("Active Blacklist: None")

    local MultiDrop
    MultiDrop = SubTab:AddMultiDropdown("Filter Items", currentPool, function(selected)
        getgenv().ItemBlacklist = selected
        local list = {}
        for k, _ in pairs(selected) do table.insert(list, k) end
        FilterLabel:SetText(#list > 0 and "Active Blacklist: " .. table.concat(list, ", ") or "Active Blacklist: None")
    end)
    getgenv().SayzUI_Handles["ItemFilterDropdown"] = MultiDrop

    SubTab:AddButton("Scan World Items", function()
        local found = {}
        for _, f in pairs({"Drops", "Gems"}) do
            local c = workspace:FindFirstChild(f)
            if c then
                for _, i in pairs(c:GetChildren()) do
                    local id = i:GetAttribute("id") or i.Name
                    if not table.find(found, id) then table.insert(found, id) end
                end
            end
        end
        currentPool = found
        MultiDrop:UpdateList(found)
        Window:Notify("Found " .. #found .. " item types.", 2)
    end)

    SubTab:AddButton("Reset All Filters", function()
        getgenv().ItemBlacklist = {}
        badItems     = {}
        lockedDoors  = {}
        FilterLabel:SetText("Active Blacklist: None")
        if MultiDrop and MultiDrop.Set then
            MultiDrop:Set({})
        end
        Window:Notify("All settings cleared!", 2)
    end)

    SubTab:AddSection("Status Dashboard")
    local StatusLabel = SubTab:AddLabel("Status: Idle")
    local TargetLabel = SubTab:AddLabel("Target: None")

    -- =============================================
    -- [[ 7. GRAVITY BYPASS ]]
    -- =============================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait()
            if getgenv().AutoCollect then
                pcall(function()
                    if movementModule.VelocityY < 0 then movementModule.VelocityY = 0 end
                    movementModule.Grounded = true
                end)
            end
        end
    end)

    -- =============================================
    -- [[ 8. MAIN LOOP ]]
    -- =============================================
    InitDoorDatabase()
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            pcall(function()
                if getgenv().AutoCollect then
                    local Hitbox = workspace:FindFirstChild("Hitbox") and workspace.Hitbox:FindFirstChild(LP.Name)

                    if not Hitbox then
                        StatusLabel:SetText("Status: Hitbox tidak ditemukan!")
                        TargetLabel:SetText("Target: None")
                        return
                    end

                    -- Reset badItems tiap siklus supaya tidak numpuk
                    -- (item yang sudah hilang otomatis tidak ada di workspace)
                    -- Cukup bersihkan instance yang sudah tidak valid
                    for item, _ in pairs(badItems) do
                        if not item.Parent then
                            badItems[item] = nil
                        end
                    end

                    local target = GetBestTarget(Hitbox)

                    if target then
                        local ok = WalkToTarget(Hitbox, target, StatusLabel, TargetLabel)
                        if not ok then
                            -- Tidak langsung blacklist item —
                            -- WalkToTarget sudah handle (blacklist hanya kalau path nil)
                            StatusLabel:SetText("Status: Rerouting...")
                        end
                    else
                        TargetLabel:SetText("Target: None")
                        StatusLabel:SetText("Status: Scanning...")
                    end
                else
                    StatusLabel:SetText("Status: Paused")
                    TargetLabel:SetText("Target: None")
                end
            end)
            task.wait(0.2)
        end
    end)
end
