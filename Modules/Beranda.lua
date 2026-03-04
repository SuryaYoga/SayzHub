return function(Window)
    local Settings = getgenv().SayzSettings
    local myToken = _G.LatestRunToken

    -- ========================================
    -- TAB 1: Beranda
    -- ========================================
    local BerandaTab = Window:AddMainTab("Beranda")

    -- 1. SUBTAB HOME
    local Home = BerandaTab:AddSubTab("Home")
    Home:AddLabel("SayzUI v1 - Beranda")
    Home:AddParagraph("Info", "Selamat datang di SayzHub, " .. game.Players.LocalPlayer.DisplayName .. "!")

    Home:AddSection("Links & Sosial Media")
    local function copyLink(label, url)
        if setclipboard then 
            setclipboard(url) 
            Window:Notify(label .. " disalin!", 2, "ok")
        else 
            Window:Notify("Executor tidak mendukung clipboard", 2, "danger") 
        end
    end

    Home:AddButton("Copy Discord Invite", function() copyLink("Discord", "https://discord.gg/XXXXXXX") end)
    Home:AddButton("Follow TikTok", function() copyLink("TikTok", "https://www.tiktok.com/@username_kamu") end)
    
    Home:AddSection("Quick Actions")
    Home:AddButton("Re-Execute Script", function() 
        loadstring(game:HttpGet(getgenv().GetRaw("Main.lua")))() 
    end)
    Home:AddButton("Hancurkan UI", function() Window:Destroy() end)

    -- 2. SUBTAB TUTORIAL & INFO
    local TutorSub = BerandaTab:AddSubTab("Panduan Umum")
    TutorSub:AddSection("Dasar Penggunaan")
    TutorSub:AddParagraph("Tombol Menu", "Tekan [K] untuk menyembunyikan menu. Jika menggunakan Mobile, gunakan tombol Drag melayang untuk membuka.")
    TutorSub:AddParagraph("Safety", "Gunakan Step Delay di atas 0.05 agar akun lebih aman dari deteksi server.")
    TutorSub:AddParagraph("Fitur Spesifik", "Tutorial detail untuk tiap fitur (PnB/AutoCollect) bisa kamu temukan di bagian bawah masing-masing fitur tersebut.")

    -- 3. SUBTAB CHANGELOG
    local LogSub = BerandaTab:AddSubTab("Changelog")
    LogSub:AddSection("Versi 3.1 (Latest)")
    LogSub:AddLabel("- Fixed: Dropdown Z-Index & Clips")
    LogSub:AddLabel("- Added: Decimal Support for Sliders")
    LogSub:AddLabel("- Added: Anti-AFK & Token Loop Control")
    LogSub:AddLabel("- Added: Tutorial & Credits Tab")

    -- 4. SUBTAB SINYAL & STATISTIK
    local SinyalSub = BerandaTab:AddSubTab("Statistik")

    SinyalSub:AddSection("Koneksi & Jaringan")
    local PingLabel    = SinyalSub:AddLabel("Ping: -- ms")
    local SinyalLabel  = SinyalSub:AddLabel("Kualitas: --")
    local RegionLabel  = SinyalSub:AddLabel("Server ID: --")

    SinyalSub:AddSection("Statistik Karakter")
    local PlayTimeLabel = SinyalSub:AddLabel("Waktu Bermain: 00:00:00")
    local FPSLabel      = SinyalSub:AddLabel("FPS: --")
    local UserLabel     = SinyalSub:AddLabel("User: " .. game.Players.LocalPlayer.Name)

    SinyalSub:AddSection("Aksi Server")
    SinyalSub:AddButton("Salin Link Server (JobId)", function()
        copyLink("JobId", "https://www.roblox.com/games/" .. game.PlaceId .. "?jobId=" .. game.JobId)
    end)

    -- ========================================
    -- ANTI AFK
    -- ========================================
    SinyalSub:AddSection("Anti AFK")

    local afkEnabled    = true  -- default ON
    local lastAFKTime   = "Belum jalan"
    local nextAFKIn     = 180   -- detik
    local afkCountdown  = nextAFKIn

    local AFKStatusLabel    = SinyalSub:AddLabel("Status    : Aktif")
    local AFKLastLabel      = SinyalSub:AddLabel("Terakhir  : Belum jalan")
    local AFKCountdownLabel = SinyalSub:AddLabel("Berikutnya: 03:00")

    getgenv().SayzUI_Handles["AntiAFK"] = SinyalSub:AddToggle("Anti AFK", afkEnabled, function(t)
        afkEnabled = t
        AFKStatusLabel:SetText("Status    : " .. (t and "Aktif" or "Nonaktif"))
        Window:Notify(t and "Anti AFK ON" or "Anti AFK OFF", 2, t and "ok" or "danger")
    end)

    -- Anti AFK loop
    task.spawn(function()
        local VirtualUser = game:GetService("VirtualUser")
        while _G.LatestRunToken == myToken do
            task.wait(1)
            if afkEnabled then
                afkCountdown = afkCountdown - 1
                -- Update countdown label
                local m = math.floor(afkCountdown / 60)
                local s = afkCountdown % 60
                AFKCountdownLabel:SetText(string.format("Berikutnya: %02d:%02d", m, s))

                if afkCountdown <= 0 then
                    -- Jalankan anti afk
                    pcall(function()
                        VirtualUser:CaptureController()
                        VirtualUser:ClickButton1(Vector2.new(0, 0), CFrame.new())
                        task.wait(0.1)
                    end)
                    -- Update label terakhir
                    local t2 = os.date("%H:%M:%S")
                    AFKLastLabel:SetText("Terakhir  : " .. t2)
                    -- Reset countdown
                    afkCountdown = nextAFKIn
                end
            else
                -- Kalau nonaktif reset countdown
                afkCountdown = nextAFKIn
                AFKCountdownLabel:SetText(string.format("Berikutnya: %02d:%02d", math.floor(nextAFKIn/60), nextAFKIn%60))
            end
        end
    end)

    -- ========================================
    -- LOGIKA UPDATE REAL-TIME
    -- ========================================
    task.spawn(function()
        local startTime = tick()
        local RunService = game:GetService("RunService")
        local Stats = game:GetService("Stats")
        
        local fps = 0
        local conn = RunService.RenderStepped:Connect(function(dt)
            fps = math.floor(1/dt)
        end)

        while _G.LatestRunToken == myToken do
            pcall(function()
                local pingValue = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
                if pingValue <= 0 then pingValue = game.Players.LocalPlayer:GetNetworkPing() * 1000 end
                local ping = math.floor(pingValue)
                PingLabel:SetText("Ping: " .. ping .. " ms")

                FPSLabel:SetText("FPS: " .. fps)

                local kualitas = (ping < 100 and "Sangat Baik") or (ping < 200 and "Cukup Baik") or "Buruk (Lag)"
                SinyalLabel:SetText("Kualitas: " .. kualitas)

                RegionLabel:SetText("Server ID: " .. string.sub(game.JobId, 1, 8))
                
                local diff = tick() - startTime
                local h, m, s = math.floor(diff/3600), math.floor((diff%3600)/60), math.floor(diff%60)
                PlayTimeLabel:SetText(string.format("Waktu Bermain: %02d:%02d:%02d", h, m, s))
            end)
            task.wait(1)
        end
        conn:Disconnect()
    end)
end
