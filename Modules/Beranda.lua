return function(Window)
    -- ========================================
    -- TAB 1: Beranda
    -- ========================================
    local BerandaTab = Window:AddMainTab("Beranda")

    -- 1. SUBTAB HOME
    local Home = BerandaTab:AddSubTab("Home")
    Home:AddLabel("SayzUI v1 - Beranda")
    Home:AddParagraph("Info", "asade kontol 🗿")

    Home:AddSection("Links")
    local function copyLink(label, url)
        local ok = pcall(function()
            if setclipboard then setclipboard(url) else error("setclipboard not supported") end
        end)
        if ok then Window:Notify(label .. " copied!", 2, "ok") else Window:Notify(url, 4, "info") end
    end

    Home:AddButton("Copy Discord Invite", function() copyLink("Discord", "https://discord.gg/XXXXXXX") end)
    Home:AddButton("Copy Changelog", function() copyLink("Changelog", "https://pastebin.com/XXXXXXX") end)

    Home:AddSection("Quick")
    Home:AddButton("Test Notify", function() Window:Notify("SayzUI v1 BlueWhite aktif ✅", 2, "ok") end)
    Home:AddParagraph("Tips", "Tekan [K] untuk toggle UI. Minimize ada di topbar.")

    -- 2. SUBTAB INFORMASI
    local Info = BerandaTab:AddSubTab("Informasi")
    Info:AddSection("Tentang Script")
    Info:AddParagraph("Deskripsi", "rusakkk game nyaaaa")

    -- 3. SUBTAB TUTORIAL
    local Tutorial = BerandaTab:AddSubTab("Tutorial")
    Tutorial:AddSection("Cara Pakai")
    Tutorial:AddParagraph("Langkah-langkah", "1) Jalankan script\n2) Pilih tab\n3) Enjoy!")

    -- 4. SUBTAB SINYAL & STATISTIK
    local SinyalSub = BerandaTab:AddSubTab("Sinyal & Statistik")

    SinyalSub:AddSection("Koneksi & Jaringan")
    local _, PingLabel = SinyalSub:AddLabel("Ping: Menghitung...")
    local _, SinyalLabel = SinyalSub:AddLabel("Kualitas: Mengecek...")
    local _, RegionLabel = SinyalSub:AddLabel("Server Region: Menghitung...")

    SinyalSub:AddSection("Statistik Karakter")
    local _, PlayTimeLabel = SinyalSub:AddLabel("Waktu Bermain: 00:00:00")
    local _, FPSLabel = SinyalSub:AddLabel("FPS: 0")
    SinyalSub:AddLabel("Username: " .. game.Players.LocalPlayer.Name)

    SinyalSub:AddSection("Aksi")
    SinyalSub:AddButton("Cek Ping (Notifikasi)", function()
        local ping = math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue())
        if ping <= 0 then ping = math.floor(game.Players.LocalPlayer:GetNetworkPing() * 1000) end
        Window:Notify("Ping: " .. ping .. "ms", 2, "info")
    end)

    SinyalSub:AddButton("Salin Link Server", function()
        local url = "https://www.roblox.com/games/" .. tostring(game.PlaceId) .. "?jobId=" .. tostring(game.JobId)
        local ok = pcall(function()
            assert(setclipboard, "setclipboard not supported")
            setclipboard(url)
        end)
        if ok then
            Window:Notify("Link JobId berhasil disalin!", 2, "ok")
        else
            Window:Notify(url, 4, "info")
        end
    end)

    -- ========================================
    -- LOGIKA UPDATE REAL-TIME (Pindahan dari Main)
    -- ========================================
    task.spawn(function()
        local startTime = tick()
        local RunService = game:GetService("RunService")
        
        while true do
            pcall(function()
                -- 1. Hitung Ping
                local pingValue = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
                if pingValue <= 0 then
                    pingValue = game.Players.LocalPlayer:GetNetworkPing() * 1000
                end
                local ping = math.floor(pingValue)
                
                -- 2. Hitung FPS
                local dt = RunService.RenderStepped:Wait()
                local fps = math.floor(1 / dt)
                
                -- 3. Update Label
                PingLabel:Set("Ping: " .. ping .. " ms")
                FPSLabel:Set("FPS: " .. fps)
                
                -- 4. Logika Kualitas Sinyal
                local kualitas = ""
                if ping < 100 then kualitas = "Sangat Baik (Hijau)"
                elseif ping < 200 then kualitas = "Cukup Baik (Kuning)"
                else kualitas = "Buruk / Lag (Merah)" end
                SinyalLabel:Set("Kualitas: " .. kualitas)
                
                -- 5. Update Server ID
                RegionLabel:Set("Server ID: " .. string.sub(game.JobId, 1, 8))
                
                -- 6. Update Waktu Bermain
                local diff = tick() - startTime
                local h = math.floor(diff / 3600)
                local m = math.floor((diff % 3600) / 60)
                local s = math.floor(diff % 60)
                PlayTimeLabel:Set(string.format("Waktu Bermain: %02d:%02d:%02d", h, m, s))
            end)
            task.wait(1)
        end
    end)

end

