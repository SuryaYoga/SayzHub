-- [FIX-1] Sekarang terima myToken dari SafeLoad di Main.lua (konsisten)
return function(Window, myToken)
    -- Fallback jika dipanggil tanpa myToken (backward compat)
    myToken = myToken or _G.LatestRunToken

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

    -- 2. SUBTAB PANDUAN UMUM
    local TutorSub = BerandaTab:AddSubTab("Panduan Umum")
    TutorSub:AddSection("Dasar Penggunaan")
    TutorSub:AddParagraph("Tombol Menu", "Tekan [K] untuk menyembunyikan menu. Jika menggunakan Mobile, gunakan tombol Drag melayang untuk membuka.")
    TutorSub:AddParagraph("Safety", "Gunakan Step Delay di atas 0.05 agar akun lebih aman dari deteksi server.")
    TutorSub:AddParagraph("Fitur Spesifik", "Tutorial detail untuk tiap fitur (PnB/AutoCollect) bisa kamu temukan di bagian bawah masing-masing fitur tersebut.")

    -- 3. SUBTAB CHANGELOG
    local LogSub = BerandaTab:AddSubTab("Changelog")
    LogSub:AddSection("Versi 3.2 (Latest)")
    LogSub:AddLabel("- Fixed: AddToggle sekarang return handle Get/Set")
    LogSub:AddLabel("- Fixed: Loading bar RenderStepped disconnect setelah selesai")
    LogSub:AddLabel("- Fixed: Handle _apply aman dipanggil sebelum tab di-render")
    LogSub:AddLabel("- Fixed: Dropdown janitor leak (UIS.InputBegan menumpuk)")
    LogSub:AddLabel("- Fixed: Slider drag reset saat window kehilangan fokus")
    LogSub:AddLabel("- Fixed: Toast dibatasi max 5 sekaligus")
    LogSub:AddSection("Versi 3.1")
    LogSub:AddLabel("- Fixed: Dropdown Z-Index & Clips")
    LogSub:AddLabel("- Added: Decimal Support for Sliders")
    LogSub:AddLabel("- Added: Anti-AFK & Token Loop Control")

    -- 4. SUBTAB STATISTIK
    local SinyalSub = BerandaTab:AddSubTab("Statistik")

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
        copyLink("JobId", "https://www.roblox.com/games/" .. game.PlaceId .. "?jobId=" .. game.JobId)
    end)

    -- ========================================
    -- LOGIKA UPDATE REAL-TIME (DENGAN KILL-SWITCH)
    -- ========================================
    task.spawn(function()
        local startTime = tick()
        local RunService = game:GetService("RunService")
        local Stats = game:GetService("Stats")

        local fps = 0

        -- [FIX-5] Simpan koneksi RenderStepped agar bisa di-disconnect bersama loop
        local fpsConn = RunService.RenderStepped:Connect(function(dt)
            if dt > 0 then
                fps = math.floor(1 / dt)
            end
        end)

        while _G.LatestRunToken == myToken do
            pcall(function()
                -- Update Ping
                local pingValue = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
                if pingValue <= 0 then
                    pingValue = game.Players.LocalPlayer:GetNetworkPing() * 1000
                end
                local ping = math.floor(pingValue)
                PingLabel:SetText("Ping: " .. ping .. " ms")

                -- Update FPS
                FPSLabel:SetText("FPS: " .. fps)

                -- Kualitas Sinyal
                local kualitas = (ping < 100 and "Sangat Baik") or (ping < 200 and "Cukup Baik") or "Buruk (Lag)"
                SinyalLabel:SetText("Kualitas: " .. kualitas)

                -- Server ID & Playtime
                RegionLabel:SetText("Server ID: " .. string.sub(game.JobId, 1, 8))

                local diff = tick() - startTime
                local h = math.floor(diff / 3600)
                local m = math.floor((diff % 3600) / 60)
                local s = math.floor(diff % 60)
                PlayTimeLabel:SetText(string.format("Waktu Bermain: %02d:%02d:%02d", h, m, s))
            end)
            task.wait(1)
        end

        -- [FIX-5] Disconnect FPS counter saat token berubah / window ditutup
        fpsConn:Disconnect()
    end)
end
