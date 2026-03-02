return function(SubTab, Window, myToken)
    -- ========================================
    -- [1] SETUP
    -- ========================================
    local LP = game:GetService("Players").LocalPlayer

    local Visual = getgenv().SayzSettings.Visual or {}
    getgenv().SayzSettings.Visual = Visual

    -- ========================================
    -- [2] ZOOM
    -- Ubah CameraMaxZoomDistance di LocalPlayer
    -- Default game: 3000
    -- ========================================
    SubTab:AddSection("CAMERA")

    Visual.Zoom     = Visual.Zoom or false
    Visual.ZoomDist = Visual.ZoomDist or 3000

    local function applyZoom(dist)
        pcall(function() LP.CameraMaxZoomDistance = dist end)
    end

    getgenv().SayzUI_Handles["Visual_Zoom"] = SubTab:AddToggle("Custom Zoom", Visual.Zoom, function(t)
        Visual.Zoom = t
        if t then
            applyZoom(Visual.ZoomDist)
        else
            applyZoom(3000)  -- restore default
        end
        Window:Notify(t and "Custom Zoom ON" or "Custom Zoom OFF", 2, t and "ok" or "danger")
    end)

    getgenv().SayzUI_Handles["Visual_ZoomDist"] = SubTab:AddSlider("Zoom Distance", 3000, 20000, Visual.ZoomDist, function(val)
        Visual.ZoomDist = val
        if Visual.Zoom then
            applyZoom(val)
        end
    end, 0)

    -- Maintain zoom saat character respawn
    task.spawn(function()
        while _G.LatestRunToken == myToken do
            task.wait(1)
            if Visual.Zoom then
                applyZoom(Visual.ZoomDist)
            end
        end
        -- Cleanup saat token mati
        applyZoom(3000)
    end)

end
