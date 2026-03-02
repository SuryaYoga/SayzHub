return function(SubTab, Window, myToken)
    -- ========================================
    -- [1] SETUP
    -- ========================================
    local LP               = game:GetService("Players").LocalPlayer
    local UserInputService = game:GetService("UserInputService")
    local movementModule   = require(LP.PlayerScripts.PlayerMovement)

    local Cheat = getgenv().SayzSettings.Cheat or {}
    getgenv().SayzSettings.Cheat = Cheat

    -- ========================================
    -- [2] MOD FLY
    -- Toggle ON/OFF lewat UI
    -- Tekan F saat toggle ON → suspend fly sementara (tidak matiin toggle)
    -- ========================================
    SubTab:AddSection("MOVEMENT")

    Cheat.Fly        = Cheat.Fly or false
    local flySuspend = false  -- true saat F ditekan, fly pause tanpa matiin toggle

    getgenv().SayzUI_Handles["Cheat_Fly"] = SubTab:AddToggle("Mod Fly", Cheat.Fly, function(t)
        Cheat.Fly  = t
        flySuspend = false  -- reset suspend saat toggle diubah
        Window:Notify(t and "Mod Fly ON (F = suspend)" or "Mod Fly OFF", 2, t and "ok" or "danger")
    end)

    -- Tombol F: suspend/resume fly tanpa ubah toggle
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if _G.LatestRunToken ~= myToken then return end
        if input.KeyCode == Enum.KeyCode.F and Cheat.Fly then
            flySuspend = not flySuspend
        end
    end)

    -- Fly loop
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait()
            if Cheat.Fly and not flySuspend then
                pcall(function()
                    if movementModule.VelocityY < 0 then
                        movementModule.VelocityY = 0
                    end
                    movementModule.Grounded = true
                end)
            end
        end
    end)

    -- ========================================
    -- [3] ANTI GRAVITY (MOON JUMP)
    -- ========================================
    Cheat.AntiGravity = Cheat.AntiGravity or false

    getgenv().SayzUI_Handles["Cheat_AntiGravity"] = SubTab:AddToggle("Anti Gravity", Cheat.AntiGravity, function(t)
        Cheat.AntiGravity = t
        pcall(function()
            if t then
                movementModule.MaxJump = 999999
                movementModule.RemainingJumps = 999999
            else
                movementModule.MaxJump = 1
                movementModule.RemainingJumps = 1
            end
        end)
        Window:Notify(t and "Anti Gravity ON" or "Anti Gravity OFF", 2, t and "ok" or "danger")
    end)

    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait(0.1)
            if Cheat.AntiGravity then
                pcall(function()
                    movementModule.MaxJump = 999999
                    if movementModule.Jumping then
                        movementModule.JumpHoldTime = movementModule.JumpHoldTime - 0.05
                    end
                end)
            end
        end
    end)

    -- ========================================
    -- [4] SPEED HACK
    -- ========================================
    Cheat.Speed     = Cheat.Speed or false
    Cheat.SpeedMult = Cheat.SpeedMult or 3

    getgenv().SayzUI_Handles["Cheat_Speed"] = SubTab:AddToggle("Speed Hack", Cheat.Speed, function(t)
        Cheat.Speed = t
        Window:Notify(t and "Speed Hack ON" or "Speed Hack OFF", 2, t and "ok" or "danger")
    end)

    getgenv().SayzUI_Handles["Cheat_SpeedMult"] = SubTab:AddSlider("Speed Multiplier", 1, 10, Cheat.SpeedMult, function(val)
        Cheat.SpeedMult = val
    end, 1)

    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait()
            if Cheat.Speed then
                pcall(function()
                    if movementModule.MoveX ~= 0 then
                        movementModule.MoveX = movementModule.MoveX * Cheat.SpeedMult
                    end
                end)
            end
        end
    end)

    -- ========================================
    -- [5] ANTI DAMAGE + ANTI HIT
    -- Hook PlayerHurtMe → cancel damage + freeze posisi sementara
    -- Hook PlayerMovementPackets → block saat freeze aktif
    -- ========================================
    SubTab:AddSection("PROTECTION")

    Cheat.AntiDamage = Cheat.AntiDamage or false
    Cheat.AntiHit    = Cheat.AntiHit or false
    local freezePos  = false  -- true saat sedang freeze posisi

    getgenv().SayzUI_Handles["Cheat_AntiDamage"] = SubTab:AddToggle("Anti Damage", Cheat.AntiDamage, function(t)
        Cheat.AntiDamage = t
        Window:Notify(t and "Anti Damage ON" or "Anti Damage OFF", 2, t and "ok" or "danger")
    end)

    getgenv().SayzUI_Handles["Cheat_AntiHit"] = SubTab:AddToggle("Anti Hit", Cheat.AntiHit, function(t)
        Cheat.AntiHit = t
        Window:Notify(t and "Anti Hit ON" or "Anti Hit OFF", 2, t and "ok" or "danger")
    end)

    if not _G.AntiDamageHookSet then
        local Remotes         = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
        local PlayerHurtMe    = Remotes:WaitForChild("PlayerHurtMe")
        local MovementPackets = Remotes:WaitForChild("PlayerMovementPackets")

        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            if _G.LatestRunToken ~= myToken then return oldNamecall(self, ...) end
            local method = getnamecallmethod()

            if method == "FireServer" then
                -- Cancel damage
                if self == PlayerHurtMe and Cheat.AntiDamage then
                    -- Freeze posisi sebentar supaya tidak mental
                    if not freezePos then
                        freezePos = true
                        task.delay(0.6, function() freezePos = false end)
                    end
                    return
                end

                -- Block movement packet saat freeze (anti mental)
                if self == MovementPackets and (Cheat.AntiDamage or Cheat.AntiHit) and freezePos then
                    return
                end
            end

            return oldNamecall(self, ...)
        end)
        _G.AntiDamageHookSet = true
    end

    -- Anti Hit: freeze posisi saat ada velocity spike dari luar
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait()
            if Cheat.AntiHit then
                pcall(function()
                    local char = LP.Character
                    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        local vel = hrp.AssemblyLinearVelocity
                        -- Kalau ada dorongan horizontal tiba-tiba, freeze posisi
                        if math.abs(vel.X) > 5 then
                            hrp.AssemblyLinearVelocity = Vector3.new(0, vel.Y, vel.Z)
                            if not freezePos then
                                freezePos = true
                                task.delay(0.6, function() freezePos = false end)
                            end
                        end
                    end
                end)
            end
        end
    end)

end
