return function(SubTab, Window, myToken)
    -- ========================================
    -- [1] SETUP
    -- ========================================
    local Players        = game:GetService("Players")
    local RunService     = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local LP             = Players.LocalPlayer
    local Camera         = workspace.CurrentCamera

    local movementModule
    pcall(function()
        movementModule = require(LP.PlayerScripts:WaitForChild("PlayerMovement"))
    end)

    local Cheat = getgenv().SayzSettings.Cheat or {}
    getgenv().SayzSettings.Cheat = Cheat

    -- ========================================
    -- [2] MOD FLY
    -- ========================================
    SubTab:AddSection("MOVEMENT")

    Cheat.Fly      = Cheat.Fly or false
    Cheat.FlySpeed = Cheat.FlySpeed or 50

    getgenv().SayzUI_Handles["Cheat_Fly"] = SubTab:AddToggle("Mod Fly", Cheat.Fly, function(t)
        Cheat.Fly = t
        if not t then
            -- Restore gravity saat dimatikan
            pcall(function()
                if movementModule then
                    movementModule.Grounded = false
                end
            end)
        end
        Window:Notify(t and "Mod Fly ON" or "Mod Fly OFF", 2, t and "ok" or "danger")
    end)

    getgenv().SayzUI_Handles["Cheat_FlySpeed"] = SubTab:AddSlider("Fly Speed", 10, 200, Cheat.FlySpeed, function(val)
        Cheat.FlySpeed = val
    end, 0)

    -- Fly loop
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait()
            if Cheat.Fly then
                pcall(function()
                    if not movementModule then return end

                    -- Bypass gravity
                    if movementModule.VelocityY < 0 then movementModule.VelocityY = 0 end
                    movementModule.Grounded = true

                    -- Gerak naik/turun pakai Space & C / Left Shift
                    local vel = movementModule.VelocityY or 0
                    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                        movementModule.VelocityY = Cheat.FlySpeed
                    elseif UserInputService:IsKeyDown(Enum.KeyCode.C)
                        or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
                        movementModule.VelocityY = -Cheat.FlySpeed
                    else
                        movementModule.VelocityY = 0
                    end
                end)
            end
        end
    end)

    -- ========================================
    -- [3] ANTI GRAVITY
    -- ========================================
    Cheat.AntiGravity = Cheat.AntiGravity or false

    getgenv().SayzUI_Handles["Cheat_AntiGravity"] = SubTab:AddToggle("Anti Gravity", Cheat.AntiGravity, function(t)
        Cheat.AntiGravity = t
        Window:Notify(t and "Anti Gravity ON" or "Anti Gravity OFF", 2, t and "ok" or "danger")
    end)

    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait()
            if Cheat.AntiGravity and not Cheat.Fly then
                pcall(function()
                    if movementModule then
                        if movementModule.VelocityY < 0 then movementModule.VelocityY = 0 end
                        movementModule.Grounded = true
                    end
                end)
            end
        end
    end)

    -- ========================================
    -- [4] SPEED HACK
    -- ========================================
    Cheat.Speed        = Cheat.Speed or false
    Cheat.SpeedMult    = Cheat.SpeedMult or 2
    local originalSpeed = nil

    getgenv().SayzUI_Handles["Cheat_Speed"] = SubTab:AddToggle("Speed Hack", Cheat.Speed, function(t)
        Cheat.Speed = t
        pcall(function()
            if not movementModule then return end
            if t then
                originalSpeed = originalSpeed or movementModule.Speed or 16
                movementModule.Speed = originalSpeed * Cheat.SpeedMult
            else
                if originalSpeed then
                    movementModule.Speed = originalSpeed
                end
            end
        end)
        Window:Notify(t and "Speed Hack ON" or "Speed Hack OFF", 2, t and "ok" or "danger")
    end)

    getgenv().SayzUI_Handles["Cheat_SpeedMult"] = SubTab:AddSlider("Speed Multiplier", 1, 10, Cheat.SpeedMult, function(val)
        Cheat.SpeedMult = val
        if Cheat.Speed then
            pcall(function()
                if movementModule and originalSpeed then
                    movementModule.Speed = originalSpeed * val
                end
            end)
        end
    end, 1)

    -- ========================================
    -- [5] ZOOM KAMERA
    -- ========================================
    SubTab:AddSection("VISUAL")

    Cheat.Zoom     = Cheat.Zoom or false
    Cheat.ZoomDist = Cheat.ZoomDist or 30

    getgenv().SayzUI_Handles["Cheat_Zoom"] = SubTab:AddToggle("Custom Zoom", Cheat.Zoom, function(t)
        Cheat.Zoom = t
        if not t then
            -- Restore zoom default
            pcall(function()
                Camera.FieldOfView = 70
            end)
        end
        Window:Notify(t and "Custom Zoom ON" or "Custom Zoom OFF", 2, t and "ok" or "danger")
    end)

    getgenv().SayzUI_Handles["Cheat_ZoomDist"] = SubTab:AddSlider("Zoom Level", 10, 120, Cheat.ZoomDist, function(val)
        Cheat.ZoomDist = val
        if Cheat.Zoom then
            pcall(function() Camera.FieldOfView = val end)
        end
    end, 0)

    -- Zoom loop (maintain saat Zoom aktif)
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait(0.5)
            if Cheat.Zoom then
                pcall(function() Camera.FieldOfView = Cheat.ZoomDist end)
            end
        end
    end)

    -- ========================================
    -- [6] FULL BRIGHT
    -- ========================================
    Cheat.FullBright = Cheat.FullBright or false
    local originalBrightness = nil
    local Lighting = game:GetService("Lighting")

    getgenv().SayzUI_Handles["Cheat_FullBright"] = SubTab:AddToggle("Full Bright", Cheat.FullBright, function(t)
        Cheat.FullBright = t
        pcall(function()
            if t then
                originalBrightness = originalBrightness or {
                    Brightness        = Lighting.Brightness,
                    ClockTime         = Lighting.ClockTime,
                    FogEnd            = Lighting.FogEnd,
                    GlobalShadows     = Lighting.GlobalShadows,
                    Ambient           = Lighting.Ambient,
                    OutdoorAmbient    = Lighting.OutdoorAmbient,
                }
                Lighting.Brightness     = 2
                Lighting.ClockTime      = 14
                Lighting.FogEnd         = 100000
                Lighting.GlobalShadows  = false
                Lighting.Ambient        = Color3.fromRGB(178, 178, 178)
                Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
            else
                if originalBrightness then
                    Lighting.Brightness     = originalBrightness.Brightness
                    Lighting.ClockTime      = originalBrightness.ClockTime
                    Lighting.FogEnd         = originalBrightness.FogEnd
                    Lighting.GlobalShadows  = originalBrightness.GlobalShadows
                    Lighting.Ambient        = originalBrightness.Ambient
                    Lighting.OutdoorAmbient = originalBrightness.OutdoorAmbient
                end
            end
        end)
        Window:Notify(t and "Full Bright ON" or "Full Bright OFF", 2, t and "ok" or "danger")
    end)

    -- ========================================
    -- [7] ANTI HIT
    -- ========================================
    SubTab:AddSection("MISC")

    Cheat.AntiHit = Cheat.AntiHit or false

    getgenv().SayzUI_Handles["Cheat_AntiHit"] = SubTab:AddToggle("Anti Hit", Cheat.AntiHit, function(t)
        Cheat.AntiHit = t
        Window:Notify(t and "Anti Hit ON" or "Anti Hit OFF", 2, t and "ok" or "danger")
    end)

    -- Anti Hit: bypass damage lewat Humanoid
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait()
            if Cheat.AntiHit then
                pcall(function()
                    local char = LP.Character
                    if not char then return end
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum then
                        hum.Health = hum.MaxHealth
                    end
                end)
            end
        end
    end)

    -- ========================================
    -- [8] CLEANUP saat token mati
    -- ========================================
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait(1)
        end
        -- Restore semua cheat saat re-execute / close
        pcall(function()
            Camera.FieldOfView = 70
            if movementModule then
                movementModule.Grounded = false
                if originalSpeed then movementModule.Speed = originalSpeed end
            end
            if originalBrightness then
                Lighting.Brightness     = originalBrightness.Brightness
                Lighting.ClockTime      = originalBrightness.ClockTime
                Lighting.FogEnd         = originalBrightness.FogEnd
                Lighting.GlobalShadows  = originalBrightness.GlobalShadows
                Lighting.Ambient        = originalBrightness.Ambient
                Lighting.OutdoorAmbient = originalBrightness.OutdoorAmbient
            end
        end)
    end)
end
