return function(Window)
    -- ========================================
    -- TAB 1: Beranda
    -- ========================================
    local BerandaTab = Window:AddMainTab("Beranda")

    -- 1. SUBTAB HOME
    local Home = BerandaTab:AddSubTab("Home")
    Home:AddLabel("SayzUI v1 - Beranda")
    Home:AddParagraph("Info", "SayzHub modular system aktif.")

    -- 2. SUBTAB SINYAL & STATISTIK
    local SinyalSub = BerandaTab:AddSubTab("Sinyal & Statistik")

    SinyalSub:AddSection("Koneksi & Jaringan")
    
    -- PERBAIKAN: Library SayzUI mengembalikan [Frame, Functions]
    -- Kita pakai variabel kedua agar bisa panggil :Set()
    local _, PingLib = SinyalSub:AddLabel("Ping: Menghitung...")
    local _, SinyalLib = SinyalSub:AddLabel("Kualitas: Mengecek...")
    local _, RegionLib = SinyalSub:AddLabel("Server ID: Menghitung...")

    SinyalSub:AddSection("Statistik Karakter")
    local _, TimeLib = SinyalSub:AddLabel("Waktu Bermain: 00:00:00")
    local _, FPSLib = SinyalSub:AddLabel("FPS: 0")
    SinyalSub:AddLabel("Username: " .. game.Players.LocalPlayer.Name)

    -- ========================================
    -- LOGIKA UPDATE REAL-TIME
    -- ========================================
    task.spawn(function()
        local startTime = tick()
        local RunService = game:GetService("RunService")
        
        while true do
            -- Kita pakai pcall agar aman jika script di-stop
            local success, err = pcall(function()
                -- 1. Hitung Ping
                local stats = game:GetService("Stats")
                local pingValue = stats.Network.ServerStatsItem["Data Ping"]:GetValue()
                if pingValue <= 0 then
                    pingValue = game.Players.LocalPlayer:GetNetworkPing() * 1000
                end
                local ping = math.floor(pingValue)
                
                -- 2. Hitung FPS
                local dt = RunService.RenderStepped:Wait()
                local fps = math.floor(1 / dt)
                
                -- 3. Update Label menggunakan fungsi :Set() dari library
                if PingLib and PingLib.Set then
                    PingLib:Set("Ping: " .. ping .. " ms")
                end
                
                if FPSLib and FPSLib.Set then
                    FPSLib:Set("FPS: " .. fps)
                end
                
                -- 4. Logika Kualitas
                local kualitas = "Buruk"
                if ping < 100 then kualitas = "Sangat Baik"
                elseif ping < 200 then kualitas = "Cukup Baik" end
                
                if SinyalLib and SinyalLib.Set then
                    SinyalLib:Set("Kualitas: " .. kualitas)
                end
                
                -- 5. Server ID & Time
                if RegionLib and RegionLib.Set then
                    RegionLib:Set("Server ID: " .. string.sub(game.JobId, 1, 8))
                end
                
                local diff = tick() - startTime
                local h, m, s = math.floor(diff/3600), math.floor((diff%3600)/60), math.floor(diff%60)
                if TimeLib and TimeLib.Set then
                    TimeLib:Set(string.format("Waktu Bermain: %02d:%02d:%02d", h, m, s))
                end
            end)
            
            if not success then
                warn("SayzUI Error: " .. tostring(err))
                break
            end
            task.wait(1)
        end
    end)

    -- Tombol aksi tambahan
    SinyalSub:AddSection("Aksi")
    SinyalSub:AddButton("Salin Link Server", function()
        setclipboard("https://www.roblox.com/games/" .. game.PlaceId .. "?jobId=" .. game.JobId)
        Window:Notify("Link JobId disalin!", 2)
    end)
end
