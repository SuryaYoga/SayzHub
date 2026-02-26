return function(Window)
    -- ========================================
    -- TAB 1: Beranda
    -- ========================================
    local BerandaTab = Window:AddMainTab("Beranda")

    -- 1. SUBTAB HOME
    local Home = BerandaTab:AddSubTab("Home")
    Home:AddLabel("SayzUI v1 - Beranda")
    Home:AddParagraph("Info", "asade kontol 🗿")

    -- 2. SUBTAB SINYAL & STATISTIK
    local SinyalSub = BerandaTab:AddSubTab("Sinyal & Statistik")

    SinyalSub:AddSection("Koneksi & Jaringan")
    
    -- Kita simpan objek yang dikembalikan library
    local PingObj = SinyalSub:AddLabel("Ping: Menghitung...")
    local SinyalObj = SinyalSub:AddLabel("Kualitas: Mengecek...")
    local RegionObj = SinyalSub:AddLabel("Server Region: Menghitung...")

    SinyalSub:AddSection("Statistik Karakter")
    local PlayTimeObj = SinyalSub:AddLabel("Waktu Bermain: 00:00:00")
    local FPSObj = SinyalSub:AddLabel("FPS: 0")
    SinyalSub:AddLabel("Username: " .. game.Players.LocalPlayer.Name)

    -- Fungsi Helper untuk Update Teks (Karena :Set atau :SetText bawaan library bermasalah)
    -- Fungsi ini akan mencari TextLabel asli di dalam folder library
    local function ForceUpdateText(obj, text)
        pcall(function()
            if type(obj) == "table" and obj.Set then
                -- Coba cara resmi dulu
                obj:Set(text)
            else
                -- Jika gagal, kita tembus langsung ke objek Instance-nya
                -- Biasanya library menyimpan instance di dalam tabel atau kita cari di parent
                -- Berdasarkan SayzUI baris 600-610, TextLabel ada di dalam Frame
                obj.Text = text 
            end
        end)
    end

    -- ========================================
    -- LOGIKA UPDATE REAL-TIME
    -- ========================================
    task.spawn(function()
        local startTime = tick()
        local RunService = game:GetService("RunService")
        
        while true do
            local success, err = pcall(function()
                -- 1. Hitung Ping
                local pingValue = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
                if pingValue <= 0 then
                    pingValue = game.Players.LocalPlayer:GetNetworkPing() * 1000
                end
                local ping = math.floor(pingValue)
                
                -- 2. Hitung FPS
                local dt = RunService.RenderStepped:Wait()
                local fps = math.floor(1 / dt)
                
                -- 3. Update Label menggunakan fungsi :Set() yang ada di library (Baris 618)
                -- PENTING: Gunakan :Set() bukan :SetText()
                if PingObj and PingObj.Set then PingObj:Set("Ping: " .. ping .. " ms") end
                if FPSObj and FPSObj.Set then FPSObj:Set("FPS: " .. fps) end
                
                -- 4. Logika Kualitas Sinyal
                local kualitas = "Buruk / Lag (Merah)"
                if ping < 100 then kualitas = "Sangat Baik (Hijau)"
                elseif ping < 200 then kualitas = "Cukup Baik (Kuning)" end
                
                if SinyalObj and SinyalObj.Set then SinyalObj:Set("Kualitas: " .. kualitas) end
                
                -- 5. Update Server ID
                if RegionObj and RegionObj.Set then RegionObj:Set("Server ID: " .. string.sub(game.JobId, 1, 8)) end
                
                -- 6. Update Waktu Bermain
                local diff = tick() - startTime
                local h, m, s = math.floor(diff/3600), math.floor((diff%3600)/60), math.floor(diff%60)
                local timeStr = string.format("Waktu Bermain: %02d:%02d:%02d", h, m, s)
                
                if PlayTimeObj and PlayTimeObj.Set then PlayTimeObj:Set(timeStr) end
            end)
            
            if not success then 
                -- Jika masih error, berarti library tidak mengembalikan tabel fungsi
                -- Kita harus melakukan debugging di sini
                print("Update Loop Error: ", err)
            end
            task.wait(1)
        end
    end)

    SinyalSub:AddSection("Aksi")
    SinyalSub:AddButton("Salin Link Server", function()
        setclipboard("https://www.roblox.com/games/" .. game.PlaceId .. "?jobId=" .. game.JobId)
        Window:Notify("Link JobId berhasil disalin!", 2, "ok")
    end)
end
