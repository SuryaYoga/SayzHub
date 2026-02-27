return function(Window)
    -- Ambil referensi setting (jika nanti butuh simpan info user di config)
    local Settings = getgenv().SayzSettings

    -- ========================================
    -- TAB 1: Beranda
    -- ========================================
    local BerandaTab = Window:AddMainTab("Beranda")

    -- 1. SUBTAB HOME
    local Home = BerandaTab:AddSubTab("Home")
    Home:AddLabel("SayzUI v1 - Beranda")
    Home:AddParagraph("Info", "Selamat datang di SayzHub!")

    Home:AddSection("Links")
    local function copyLink(label, url)
        local ok = pcall(function()
            if setclipboard then setclipboard(url) else error("Unsupported") end
        end)
        if ok then Window:Notify(label .. " copied!", 2, "ok") else Window:Notify("Failed to copy", 2, "error") end
    end

    Home:AddButton("Copy Discord Invite", function() copyLink("Discord", "https://discord.gg/XXXXXXX") end)
    
    Home:AddSection("Quick Actions")
    Home:AddButton("Re-Execute Script", function() 
        loadstring(game:HttpGet(getgenv().GetRaw("main.lua")))() 
    end)
    Home:AddParagraph("Tips", "Tekan [K] untuk menyembunyikan UI.\nScript akan otomatis load saat pindah world.")

    -- 2. SUBTAB SINYAL & STATISTIK
    local SinyalSub = BerandaTab:AddSubTab("Sinyal & Statistik")

    SinyalSub:AddSection("Koneksi & Jaringan")
    local PingLabel = SinyalSub:AddLabel("Ping: -- ms")
    local SinyalLabel = SinyalSub:AddLabel("Kualitas: --")
    local RegionLabel = SinyalSub:AddLabel("Server ID: --")

    SinyalSub:AddSection("Statistik Karakter")
    local PlayTimeLabel = SinyalSub:AddLabel("Waktu Bermain: 00:00:00")
    local FPSLabel = SinyalSub:AddLabel("FPS: --")
    local UserLabel = SinyalSub:AddLabel("User: " .. game.Players.LocalPlayer.Name)

    SinyalSub:AddSection("Aksi Server")
    SinyalSub:AddButton("Salin Link Server (JobId)", function()
        setclipboard("https://www.roblox.com/games/" .. game.PlaceId .. "?jobId=" .. game.JobId)
        Window:Notify("Link JobId disalin!", 2, "ok")
    end)

    -- ========================================
    -- LOGIKA UPDATE REAL-TIME
    -- ========================================
    task.spawn(function()
        local startTime = tick()
        local RunService = game:GetService("RunService")
        local Stats = game:GetService("Stats")
        
        -- Loop cepat untuk FPS
        local fps = 0
        RunService.RenderStepped:Connect(function(dt)
            fps = math.floor(1/dt)
        end)

        -- Loop 1 detik untuk label lainnya (biar tidak berat)
        while true do
            pcall(function()
                -- 1. Update Ping
                local pingValue = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
                if pingValue <= 0 then
                    pingValue = game.Players.LocalPlayer:GetNetworkPing() * 1000
                end
                local ping = math.floor(pingValue)
                PingLabel:SetText("Ping: " .. ping .. " ms")

                -- 2. Update FPS
                FPSLabel:SetText("FPS: " .. fps)

                -- 3. Kualitas Sinyal
                local kualitas = (ping < 100 and "Sangat Baik") or (ping < 200 and "Cukup Baik") or "Buruk (Lag)"
                SinyalLabel:SetText("Kualitas: " .. kualitas)

                -- 4. Server ID & Playtime
                RegionLabel:SetText("Server ID: " .. string.sub(game.JobId, 1, 8))
                
                local diff = tick() - startTime
                local h, m, s = math.floor(diff/3600), math.floor((diff%3600)/60), math.floor(diff%60)
                PlayTimeLabel:SetText(string.format("Waktu Bermain: %02d:%02d:%02d", h, m, s))
            end)
            task.wait(1)
        end
    end)
end
