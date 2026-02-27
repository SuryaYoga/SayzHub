--// SayzUI v3.1 (Custom UI Library) - by Sayz
--// Layout: Top Main Tabs, Left Sub Tabs, Right Content
--// Added: Loading overlay, Minimize, Close confirm, Toggle Keybind
--// Added UI Controls: Label, Section, Button, Toggle, Slider, Input, Dropdown, Paragraph
--// Added Toast Notify (small popup)
--// Added: Get/Set handles for Toggle/Slider/Input/Dropdown
--// Added: K ignores when typing (focused TextBox)
--// Added: Mini opener drag + snap
--// No external libraries.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")


local SayzUI = {}
SayzUI.__index = SayzUI

-- ===== Helpers =====
local function mk(className, props)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do
		inst[k] = v
	end
	return inst
end

local function corner(parent, r)
	return mk("UICorner", { CornerRadius = UDim.new(0, r or 10), Parent = parent })
end

local function stroke(parent, thickness, transparency, color)
	local s = mk("UIStroke", {
		Thickness = thickness or 1,
		Transparency = transparency or 0.6,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent
	})
	if color then s.Color = color end
	return s
end

local function padding(parent, l, t, r, b)
	return mk("UIPadding", {
		PaddingLeft = UDim.new(0, l or 0),
		PaddingTop = UDim.new(0, t or 0),
		PaddingRight = UDim.new(0, r or 0),
		PaddingBottom = UDim.new(0, b or 0),
		Parent = parent
	})
end

local function list(parent, fillDir, pad, sortOrder)
	return mk("UIListLayout", {
		FillDirection = fillDir or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, pad or 8),
		SortOrder = sortOrder or Enum.SortOrder.LayoutOrder,
		Parent = parent
	})
end

local function safeDestroyExisting(parent, name)
	local old = parent:FindFirstChild(name)
	if old then old:Destroy() end
end

local function isKeyCode(v)
	return typeof(v) == "EnumItem" and v.EnumType == Enum.KeyCode
end

local function clamp(n, a, b)
	if n < a then return a end
	if n > b then return b end
	return n
end

local function safeCall(cb, ...)
	if type(cb) ~= "function" then return end
	local ok, err = pcall(cb, ...)
	if not ok then
		warn("[SayzUI callback error]", err)
	end
end

-- ===== Theme Presets (stored in library) =====
local Themes = {}

Themes.DefaultDark = {
	Bg = Color3.fromRGB(14, 14, 16),
	Panel = Color3.fromRGB(18, 18, 22),
	Panel2 = Color3.fromRGB(22, 22, 28),
	Top = Color3.fromRGB(20, 20, 26),
	Stroke = Color3.fromRGB(70, 70, 85),

	Text = Color3.fromRGB(235, 235, 235),
	Muted = Color3.fromRGB(160, 160, 160),
	Accent = Color3.fromRGB(120, 120, 255),

	Button = Color3.fromRGB(34, 34, 42),
	ButtonHover = Color3.fromRGB(44, 44, 56),

	Danger = Color3.fromRGB(210, 70, 70),
	Ok = Color3.fromRGB(70, 170, 110),
}

Themes.BlueWhite = {
	Bg = Color3.fromRGB(245, 248, 255),
	Panel = Color3.fromRGB(255, 255, 255),
	Panel2 = Color3.fromRGB(248, 250, 255),
	Top = Color3.fromRGB(235, 242, 255),
	Stroke = Color3.fromRGB(170, 190, 230),

	Text = Color3.fromRGB(20, 26, 40),
	Muted = Color3.fromRGB(90, 105, 130),
	Accent = Color3.fromRGB(45, 125, 255),

	Button = Color3.fromRGB(230, 240, 255),
	ButtonHover = Color3.fromRGB(215, 232, 255),

	Danger = Color3.fromRGB(220, 70, 70),
	Ok = Color3.fromRGB(60, 160, 110),
}

local Theme = Themes.BlueWhite -- default

-- ===== Connection tracking =====
local function makeJanitor()
	local j = { _items = {} }
	function j:Add(x)
		table.insert(self._items, x)
		return x
	end
	function j:Cleanup()
		for i = #self._items, 1, -1 do
			local it = self._items[i]
			self._items[i] = nil
			pcall(function()
				if typeof(it) == "RBXScriptConnection" then
					it:Disconnect()
				elseif type(it) == "function" then
					it()
				elseif it and it.Destroy then
					it:Destroy()
				end
			end)
		end
	end
	return j
end

-- ===== Core =====
function SayzUI.new()
	local self = setmetatable({}, SayzUI)
	return self
end

function SayzUI:GetThemes()
	local names = {}
	for k, _ in pairs(Themes) do table.insert(names, k) end
	table.sort(names)
	return names
end

function SayzUI:CreateWindow(opts)
	_G.LatestRunToken = (_G.LatestRunToken or 0) + 1
	opts = opts or {}
	local title = opts.Title or "Sayz Hub"
	local subtitle = opts.Subtitle or "UI Framework"
	local guiName = opts.GuiName or "SayzHub_UI"
	local onClose = opts.OnClose
	local keybind = opts.ToggleKeybind

	if keybind == nil then
		keybind = Enum.KeyCode.K
	elseif type(keybind) == "string" then
		keybind = Enum.KeyCode[keybind] or Enum.KeyCode.K
	elseif not isKeyCode(keybind) then
		keybind = Enum.KeyCode.K
	end

	-- Theme selection from main script
	if opts.Theme then
		if type(opts.Theme) == "string" and Themes[opts.Theme] then
			Theme = Themes[opts.Theme]
		elseif type(opts.Theme) == "table" then
			Theme = opts.Theme
		end
	end

	local player = Players.LocalPlayer
	local pgui = player:WaitForChild("PlayerGui")
	safeDestroyExisting(pgui, guiName)

	local janitor = makeJanitor()

	-- ScreenGui
	local gui = mk("ScreenGui", {
		Name = guiName,
		DisplayOrder = 999,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		Parent = pgui,
	})

	-- Toast holder
	local toastHolder = mk("Frame", {
		Name = "ToastHolder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -14),
		Size = UDim2.new(0, 320, 0, 200),
		Parent = gui
	})
	local toastLayout = list(toastHolder, Enum.FillDirection.Vertical, 8)
	toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	toastLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom

	local function toast(msg, dur, kind)
		dur = tonumber(dur) or 2.2
		kind = kind or "info"

		local bg = Theme.Panel
		local accent = Theme.Accent
		if kind == "ok" then accent = Theme.Ok end
		if kind == "danger" then accent = Theme.Danger end

		local t = mk("Frame", {
			BackgroundColor3 = bg,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 44),
			Parent = toastHolder
		})
		corner(t, 12)
		stroke(t, 1, 0.55, Theme.Stroke)

		local bar = mk("Frame", {
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 5, 1, 0),
			Parent = t
		})
		corner(bar, 12)

		mk("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 14, 0, 0),
			Size = UDim2.new(1, -18, 1, 0),
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Text,
			Text = tostring(msg),
			Parent = t
		})

		task.delay(dur, function()
			if t and t.Parent then
				t:Destroy()
			end
		end)
	end

	-- Main frame
	local main = mk("Frame", {
		Name = "Main",
		Size = UDim2.new(0, 780, 0, 480),
		Position = UDim2.new(0.5, -390, 0.5, -240),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Parent = gui,
	})
	corner(main, 14)
	stroke(main, 1, 0.45, Theme.Stroke)

	-- Top bar
	local top = mk("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundColor3 = Theme.Top,
		BorderSizePixel = 0,
		Parent = main,
	})
	corner(top, 14)
	mk("Frame", {
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.new(0, 0, 1, -14),
		BackgroundColor3 = Theme.Top,
		BorderSizePixel = 0,
		Parent = top,
	})
	padding(top, 14, 10, 14, 10)

	local titleBlock = mk("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, 260, 1, 0), Parent = top })
	mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		Font = Enum.Font.GothamSemibold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Text,
		Text = title,
		Parent = titleBlock
	})
	mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 22),
		Size = UDim2.new(1, 0, 0, 16),
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Muted,
		Text = subtitle,
		Parent = titleBlock
	})

	local topTabs = mk("Frame", {
		Name = "MainTabs",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 270, 0, 0),
		Size = UDim2.new(1, -370, 1, 0),
		Parent = top
	})
	local topTabsLayout2 = list(topTabs, Enum.FillDirection.Horizontal, 8)
	topTabsLayout2.VerticalAlignment = Enum.VerticalAlignment.Center

	local function makeTopBtn(txt)
		local b = mk("TextButton", {
			Size = UDim2.new(0, 44, 0, 34),
			BackgroundColor3 = Theme.Button,
			BorderSizePixel = 0,
			Text = txt,
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextColor3 = Theme.Text,
			AutoButtonColor = false,
			Parent = top
		})
		corner(b, 10)

		janitor:Add(b.MouseEnter:Connect(function() b.BackgroundColor3 = Theme.ButtonHover end))
		janitor:Add(b.MouseLeave:Connect(function() b.BackgroundColor3 = Theme.Button end))

		return b
	end

	local closeBtn = makeTopBtn("X")
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, 0, 0.5, 0)

	local minBtn = makeTopBtn("-")
	minBtn.AnchorPoint = Vector2.new(1, 0.5)
	minBtn.Position = UDim2.new(1, -54, 0.5, 0)

	-- Body
	local body = mk("Frame", {
		Name = "Body",
		Position = UDim2.new(0, 0, 0, 58),
		Size = UDim2.new(1, 0, 1, -58),
		BackgroundTransparency = 1,
		Parent = main
	})

	local sidebar = mk("Frame", {
		Name = "Sidebar",
		Position = UDim2.new(0, 12, 0, 12),
		Size = UDim2.new(0, 230, 1, -24),
		BackgroundColor3 = Theme.Panel2,
		BorderSizePixel = 0,
		Parent = body
	})
	corner(sidebar, 14)
	stroke(sidebar, 1, 0.6, Theme.Stroke)
	padding(sidebar, 12, 12, 12, 12)

	local subTabsHolder = mk("Frame", {
		Name = "SubTabs",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = sidebar
	})
	list(subTabsHolder, Enum.FillDirection.Vertical, 8)

	local contentWrap = mk("Frame", {
		Name = "ContentWrap",
		Position = UDim2.new(0, 254, 0, 12),
		Size = UDim2.new(1, -266, 1, -24),
		BackgroundColor3 = Theme.Panel2,
		BorderSizePixel = 0,
		Parent = body
	})
	corner(contentWrap, 14)
	stroke(contentWrap, 1, 0.6, Theme.Stroke)
	padding(contentWrap, 14, 14, 14, 14)

	local contentTitle = mk("TextLabel", {
		Name = "ContentTitle",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		Font = Enum.Font.GothamSemibold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Text,
		Text = "Welcome",
		Parent = contentWrap
	})

	local contentArea = mk("ScrollingFrame", {
		Name = "Content",
		Position = UDim2.new(0, 0, 0, 26),
		Size = UDim2.new(1, 0, 1, -26),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = contentWrap
	})
	list(contentArea, Enum.FillDirection.Vertical, 10)
	padding(contentArea, 0, 0, 6, 10)

	-- Minimized opener
	local mini = mk("TextButton", {
		Name = "MiniOpen",
		Visible = false,
		Size = UDim2.new(0, 120, 0, 34),
		Position = UDim2.new(0, 14, 0.5, -17),
		BackgroundColor3 = Theme.Top,
		BorderSizePixel = 0,
		Text = "Sayz Hub",
		Font = Enum.Font.GothamSemibold,
		TextSize = 13,
		TextColor3 = Theme.Text,
		AutoButtonColor = false,
		Parent = gui
	})
	corner(mini, 12)
	stroke(mini, 1, 0.65, Theme.Stroke)

	-- Loading overlay
	local loading = mk("Frame", {
		Name = "LoadingOverlay",
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.15,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = true,
		Parent = gui
	})

	-- IMPORTANT: hide main while loading
	main.Visible = false

	local loadingPanel = mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 360, 0, 160),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Parent = loading
	})
	corner(loadingPanel, 14)
	stroke(loadingPanel, 1, 0.5, Theme.Stroke)
	padding(loadingPanel, 16, 16, 16, 16)

	mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 22),
		Font = Enum.Font.GothamSemibold,
		TextSize = 18,
		TextColor3 = Theme.Text,
		Text = title,
		Parent = loadingPanel
	})

	local loadingText = mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 34),
		Size = UDim2.new(1, 0, 0, 18),
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = Theme.Muted,
		Text = "Loading...",
		Parent = loadingPanel
	})

	local barBg = mk("Frame", {
		Position = UDim2.new(0, 0, 0, 78),
		Size = UDim2.new(1, 0, 0, 10),
		BackgroundColor3 = Theme.Panel2,
		BorderSizePixel = 0,
		Parent = loadingPanel
	})
	corner(barBg, 8)
	stroke(barBg, 1, 0.7, Theme.Stroke)

	local barFill = mk("Frame", {
		Size = UDim2.new(0.12, 0, 1, 0),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = barBg
	})
	corner(barFill, 8)

	mk("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 18),
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = Theme.Muted,
		Text = "Tip: Press [" .. tostring(keybind.Name) .. "] to toggle UI",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = loadingPanel
	})

	-- Confirm modal
	local modal = mk("Frame", {
		Name = "ConfirmModal",
		Visible = false,
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.35,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = gui
	})

	local modalPanel = mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 380, 0, 170),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Parent = modal
	})
	corner(modalPanel, 14)
	stroke(modalPanel, 1, 0.5, Theme.Stroke)
	padding(modalPanel, 16, 16, 16, 16)

	mk("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		Font = Enum.Font.GothamSemibold,
		TextSize = 16,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Close Sayz Hub?",
		Parent = modalPanel
	})

	mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 34),
		Size = UDim2.new(1, 0, 0, 44),
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Are you sure you want to close and stop this script?",
		Parent = modalPanel
	})

	local modalBtns = mk("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 42),
		Parent = modalPanel
	})
	local modalLayout = list(modalBtns, Enum.FillDirection.Horizontal, 10)
	modalLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	modalLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	local function makeActionBtn(text, bg)
		local b = mk("TextButton", {
			Size = UDim2.new(0, 110, 0, 34),
			BackgroundColor3 = bg,
			BorderSizePixel = 0,
			Text = text,
			Font = Enum.Font.GothamSemibold,
			TextSize = 13,
			TextColor3 = Theme.Text,
			AutoButtonColor = false,
			Parent = modalBtns
		})
		corner(b, 10)
		return b
	end

	local btnNo = makeActionBtn("Cancel", Theme.Button)
	local btnYes = makeActionBtn("Yes, Close", Theme.Danger)

	-- ===== Window object =====
	local Window = {}
	Window._janitor = janitor
	Window._gui = gui
	Window._main = main
	Window._mini = mini
	Window._modal = modal
	Window._loading = loading
	Window._loadingText = loadingText
	Window._barFill = barFill
	Window._toast = toast
	Window._closed = false
	Window._minimized = false

	Window._topTabs = topTabs
	Window._subTabsHolder = subTabsHolder
	Window._contentArea = contentArea
	Window._contentTitle = contentTitle
	Window._mainTabs = {}
	Window._activeMain = nil
	Window._activeSub = nil

	-- ===== Content helpers =====
	local function clearContent()
		for _, ch in ipairs(contentArea:GetChildren()) do
			if ch:IsA("GuiObject") then ch:Destroy() end
		end
	end

	local function setContentTitle(t)
		contentTitle.Text = t or "Content"
	end

	local function makeBtn(text)
		local b = mk("TextButton", {
			BackgroundColor3 = Theme.Button,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 120, 0, 32),
			Font = Enum.Font.GothamSemibold,
			TextSize = 13,
			Text = tostring(text),
			TextColor3 = Theme.Text,
			AutoButtonColor = false,
		})
		b:SetAttribute("SayzActive", false)

		corner(b, 10)

		janitor:Add(b.MouseEnter:Connect(function()
			if not b:GetAttribute("SayzActive") then
				b.BackgroundColor3 = Theme.ButtonHover
			end
		end))

		janitor:Add(b.MouseLeave:Connect(function()
			if not b:GetAttribute("SayzActive") then
				b.BackgroundColor3 = Theme.Button
			end
		end))

		return b
	end

	-- ===== Active Highlight Helpers (Theme-based) =====
	local ACTIVE_TEXT = Color3.fromRGB(255, 255, 255)

	local function setMainTabStyle(btn, active)
		if not btn then return end
		btn:SetAttribute("SayzActive", active)
		btn.BackgroundColor3 = active and Theme.Accent or Theme.Button
		btn.TextColor3 = active and ACTIVE_TEXT or Theme.Text
	end

	local function setSubTabStyle(btn, active)
		if not btn then return end
		btn:SetAttribute("SayzActive", active)
		btn.BackgroundColor3 = active and Theme.Accent or Theme.Button
		btn.TextColor3 = active and ACTIVE_TEXT or Theme.Text

		local bar = btn:FindFirstChild("LeftBar")
		if bar then
			bar.Visible = active and true or false
		end
	end

	local function rowCard()
		local card = mk("Frame", {
			BackgroundColor3 = Theme.Panel,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 42),
			Parent = contentArea
		})
		corner(card, 12)
		stroke(card, 1, 0.65, Theme.Stroke)
		padding(card, 12, 10, 12, 10)
		return card
	end

	-- ===== Public: Toast notify =====
	function Window:Notify(msg, dur, kind)
		toast(msg, dur, kind)
	end

	-- ===== Loading API =====
	function Window:SetLoadingText(text) Window._loadingText.Text = tostring(text) end
	function Window:SetLoadingProgress(alpha)
		alpha = clamp(alpha or 0, 0, 1)
		Window._barFill.Size = UDim2.new(alpha, 0, 1, 0)
	end

	function Window:FinishLoading()
		if Window._loading then
			Window._loading.Visible = false
		end
		-- Only show main if not minimized
		if not Window._minimized then
			if Window._main then Window._main.Visible = true end
			if Window._mini then Window._mini.Visible = false end
		end
	end

	if opts.ShowLoading ~= false then
		local t0 = os.clock()
		local dur = tonumber(opts.LoadingDuration) or 1.2
		Window:SetLoadingText(opts.LoadingText or "Loading...")
		janitor:Add(RunService.RenderStepped:Connect(function()
			if Window._closed then return end
			local a = (os.clock() - t0) / dur
			Window:SetLoadingProgress(a)
			if a >= 1 then
				Window:FinishLoading()
			end
		end))
	else
		Window:FinishLoading()
	end

	-- ===== Visibility API =====
	function Window:Minimize()
		Window._minimized = true
		if Window._main then Window._main.Visible = false end
		if Window._mini then Window._mini.Visible = true end
	end

	function Window:Restore()
		Window._minimized = false
		if Window._mini then Window._mini.Visible = false end
		if Window._main then Window._main.Visible = true end
	end

	function Window:Toggle()
		if Window._minimized then
			Window:Restore()
		else
			Window:Minimize()
		end
	end

	-- ===== Close / Destroy =====
	function Window:Destroy(reason)
		if Window._closed then return end
		Window._closed = true
		safeCall(onClose, reason or "closed")
		janitor:Cleanup()
		if gui then gui:Destroy() end
	end

	function Window:ShowCloseConfirm() modal.Visible = true end
	function Window:HideCloseConfirm() modal.Visible = false end

	-- ===== Wire buttons =====
	janitor:Add(mini.MouseButton1Click:Connect(function() Window:Restore() end))

	-- Mini opener drag + snap
	do
		local draggingMini = false
		local dragStartPos
		local startUDim

		local function snapMini()
			local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
			if not vp then return end

			local mSize = mini.AbsoluteSize
			local mPos = mini.AbsolutePosition

			local margin = 12
			local minX = margin
			local minY = margin
			local maxX = vp.X - mSize.X - margin
			local maxY = vp.Y - mSize.Y - margin

			local clampedX = math.clamp(mPos.X, minX, maxX)
			local clampedY = math.clamp(mPos.Y, minY, maxY)

			local distLeft = clampedX - minX
			local distRight = maxX - clampedX
			local finalX = (distLeft <= distRight) and minX or maxX

			mini.Position = UDim2.new(0, finalX, 0, clampedY)
		end

		janitor:Add(mini.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				draggingMini = true
				dragStartPos = input.Position
				startUDim = mini.Position

				local c
				c = input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						draggingMini = false
						if c then c:Disconnect() end
						snapMini()
					end
				end)
				janitor:Add(c)
			end
		end))

		janitor:Add(UIS.InputChanged:Connect(function(input)
			if not draggingMini then return end
			if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
				local delta = input.Position - dragStartPos
				mini.Position = UDim2.new(
					startUDim.X.Scale, startUDim.X.Offset + delta.X,
					startUDim.Y.Scale, startUDim.Y.Offset + delta.Y
				)
			end
		end))

		task.defer(function()
			task.wait(0.05)
			if mini and mini.Parent then
				snapMini()
			end
		end)
	end

	janitor:Add(minBtn.MouseButton1Click:Connect(function() Window:Minimize() end))
	janitor:Add(closeBtn.MouseButton1Click:Connect(function() Window:ShowCloseConfirm() end))
	janitor:Add(btnNo.MouseButton1Click:Connect(function() Window:HideCloseConfirm() end))
	janitor:Add(btnYes.MouseButton1Click:Connect(function() 
	    _G.LatestRunToken = (_G.LatestRunToken or 0) + 1 
	    Window:Destroy("confirmed_close") 
	end))

	-- ===== Toggle keybind (K) - ignore when typing in TextBox =====
	janitor:Add(UIS.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if UIS:GetFocusedTextBox() then return end -- IMPORTANT: ignore typing
		if input.KeyCode == keybind then
			Window:Toggle()
		end
	end))

	-- Dragging on topbar (window draggable)
	do
		local dragging = false
		local dragStart, startPos
		janitor:Add(top.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				dragStart = input.Position
				startPos = main.Position

				local c
				c = input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						dragging = false
						if c then c:Disconnect() end
					end
				end)
				janitor:Add(c)
			end
		end))
		janitor:Add(UIS.InputChanged:Connect(function(input)
			if not dragging then return end
			if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
				local delta = input.Position - dragStart
				main.Position = UDim2.new(
					startPos.X.Scale, startPos.X.Offset + delta.X,
					startPos.Y.Scale, startPos.Y.Offset + delta.Y
				)
			end
		end))
	end

	-- ===== Main Tabs / Sub Tabs API =====
	function Window:AddMainTab(tabName)
		local tab = { Name = tostring(tabName), SubTabs = {} }

		local tabBtn = makeBtn(tabName)
		tabBtn.Parent = topTabs
		tab._btn = tabBtn
		setMainTabStyle(tabBtn, false)

		local function setActiveMain()
			if Window._activeMain and Window._activeMain._btn then
				setMainTabStyle(Window._activeMain._btn, false)
			end
			Window._activeMain = tab
			setMainTabStyle(tab._btn, true)

			for _, ch in ipairs(subTabsHolder:GetChildren()) do
				if ch:IsA("GuiObject") then ch:Destroy() end
			end

			for _, stDef in ipairs(tab.SubTabs) do
				stDef._render()
			end

			if tab.SubTabs[1] then
				tab.SubTabs[1]:Select()
			else
				clearContent()
				setContentTitle(tabName)
			end
		end

		janitor:Add(tabBtn.MouseButton1Click:Connect(setActiveMain))

		function tab:AddSubTab(subName)
			local sub = { Name = tostring(subName), _items = {} }
			local subBtn

			function sub._render()
				subBtn = mk("TextButton", {
					BackgroundColor3 = Theme.Button,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 34),
					Font = Enum.Font.GothamSemibold,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = Theme.Text,
					Text = "   " .. sub.Name,
					AutoButtonColor = false,
					Parent = subTabsHolder
				})
				corner(subBtn, 10)

				sub._btn = subBtn
				setSubTabStyle(subBtn, false)

				local leftBar = mk("Frame", {
					Name = "LeftBar",
					BackgroundColor3 = Theme.Panel,
					BorderSizePixel = 0,
					Position = UDim2.new(0, 6, 0.5, -10),
					Size = UDim2.new(0, 4, 0, 20),
					Visible = false,
					Parent = subBtn
				})
				corner(leftBar, 6)

				janitor:Add(subBtn.MouseEnter:Connect(function()
					if not subBtn:GetAttribute("SayzActive") then
						subBtn.BackgroundColor3 = Theme.ButtonHover
					end
				end))
				janitor:Add(subBtn.MouseLeave:Connect(function()
					if not subBtn:GetAttribute("SayzActive") then
						subBtn.BackgroundColor3 = Theme.Button
					end
				end))

				janitor:Add(subBtn.MouseButton1Click:Connect(function() sub:Select() end))
			end

			function sub:Select()
				if Window._activeSub and Window._activeSub._btn then
					setSubTabStyle(Window._activeSub._btn, false)
				end

				Window._activeSub = sub
				if sub._btn then
					setSubTabStyle(sub._btn, true)
				end

				clearContent()
				setContentTitle(tab.Name .. " • " .. sub.Name)
				for _, item in ipairs(sub._items) do item() end
			end

			function sub:AddToggle(text, defaultValue, callback)
                table.insert(sub._items, function()
                    local card = rowCard()

                    local lbl = mk("TextLabel", {
                        BackgroundTransparency = 1,
                        Size = UDim2.new(1, -60, 1, 0),
                        Font = Enum.Font.GothamSemibold,
                        TextSize = 13,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        TextColor3 = Theme.Text,
                        Text = tostring(text),
                        Parent = card
                    })

                    local state = defaultValue and true or false

                    local tbtn = mk("TextButton", {
                        AnchorPoint = Vector2.new(1, 0.5),
                        Position = UDim2.new(1, 0, 0.5, 0),
                        Size = UDim2.new(0, 46, 0, 26),
                        BackgroundColor3 = state and Theme.Accent or Theme.Button,
                        BorderSizePixel = 0,
                        Text = "",
                        AutoButtonColor = false,
                        Parent = card
                    })
                    corner(tbtn, 13)

                    local knob = mk("Frame", {
                        Size = UDim2.new(0, 20, 0, 20),
                        Position = state and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10),
                        BackgroundColor3 = Theme.Panel,
                        BorderSizePixel = 0,
                        Parent = tbtn
                    })
                    corner(knob, 10)
                    stroke(knob, 1, 0.8, Theme.Stroke)

                    local function set(v)
                        state = v and true or false
                        tbtn.BackgroundColor3 = state and Theme.Accent or Theme.Button
                        knob.Position = state and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10)
                        if callback then callback(state) end
                    end

                    janitor:Add(tbtn.MouseButton1Click:Connect(function()
                        set(not state)
                    end))

                    -- return handle (for future use)
                    card:SetAttribute("SayzToggle", true)
                end)
                return sub
            end

			-- ===== Controls =====
			function sub:AddSection(text)
				table.insert(sub._items, function()
					mk("TextLabel", {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 18),
						Font = Enum.Font.GothamSemibold,
						TextSize = 13,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextColor3 = Theme.Text,
						Text = tostring(text),
						Parent = contentArea
					})
				end)
				return sub
			end

			function sub:AddLabel(text)
    			local labelTable = {} -- Tabel untuk menyimpan fungsi update
    			local labelInstance = nil -- Tempat menyimpan objek TextLabel

    			table.insert(sub._items, function()
        			labelInstance = mk("TextLabel", {
            			BackgroundTransparency = 1,
            			Size = UDim2.new(1, 0, 0, 18),
            			Font = Enum.Font.Gotham,
            			TextSize = 13,
            			TextXAlignment = Enum.TextXAlignment.Left,
            			TextColor3 = Theme.Muted,
            			Text = tostring(text),
            			Parent = contentArea
        			})
    			end)

    			-- Tambahkan fungsi SetText agar bisa dipanggil dari luar
    			function labelTable:SetText(newText)
        			if labelInstance then
            			labelInstance.Text = tostring(newText)
        			end
    			end

    			return labelTable -- Kembalikan tabel fungsinya, bukan 'sub'
			end

			function sub:AddParagraph(titleText, bodyText)
				table.insert(sub._items, function()
					local card = mk("Frame", {
						BackgroundColor3 = Theme.Panel,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 88),
						Parent = contentArea
					})
					corner(card, 12)
					stroke(card, 1, 0.65, Theme.Stroke)
					padding(card, 12, 10, 12, 10)

					mk("TextLabel", {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 18),
						Font = Enum.Font.GothamSemibold,
						TextSize = 13,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextColor3 = Theme.Text,
						Text = tostring(titleText),
						Parent = card
					})

					mk("TextLabel", {
						BackgroundTransparency = 1,
						Position = UDim2.new(0, 0, 0, 22),
						Size = UDim2.new(1, 0, 1, -22),
						Font = Enum.Font.Gotham,
						TextSize = 12,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextColor3 = Theme.Muted,
						TextWrapped = true,
						Text = tostring(bodyText),
						Parent = card
					})
					
				end)
				return sub
			end

			function sub:AddButton(text, callback)
				table.insert(sub._items, function()
					local btn = makeBtn(text)
					btn.Size = UDim2.new(0, 200, 0, 34)
					btn.Parent = contentArea
					janitor:Add(btn.MouseButton1Click:Connect(function()
						safeCall(callback)
					end))
				end)
				return sub
			end

			-- ===== Multi-Select Dropdown (Fixed for Reset & ZIndex) =====
			function sub:AddMultiDropdown(text, listItems, callback)
			    listItems = listItems or {}
			    local handle = { _items = listItems, Selected = {}, _rebuild = nil }
			    local TempItems = {}
			    local dropBtn -- Didefinisikan di luar agar bisa diakses handle:Set
			
			    table.insert(sub._items, function()
			        local open = false
			        local card = rowCard()
			        -- Agar tidak tertutup UI game, pastikan ScreenGui induk memiliki DisplayOrder tinggi
			        card.ZIndex = 1100 
			
			        mk("TextLabel", {
			            BackgroundTransparency = 1,
			            Size = UDim2.new(0.4, 0, 1, 0),
			            Font = Enum.Font.GothamSemibold,
			            TextSize = 13,
			            TextColor3 = Theme.Text,
			            TextXAlignment = Enum.TextXAlignment.Left,
			            Text = tostring(text),
			            Parent = card
			        })
			
			        dropBtn = mk("TextButton", {
			            BackgroundColor3 = Theme.Button,
			            Position = UDim2.new(0.45, 0, 0, 0),
			            Size = UDim2.new(0.55, 0, 1, 0),
			            Font = Enum.Font.Gotham,
			            TextSize = 12,
			            TextColor3 = Theme.Text,
			            Text = "Select Items... ▼",
			            Parent = card
			        })
			        corner(dropBtn, 8)
					task.defer(function()
			            if dropBtn then
			                dropBtn.Text = "Select Items... ▼"
			                dropBtn.TextColor3 = Theme.Text
			            end
			        end)
			
			        local listContainer = mk("ScrollingFrame", {
			            Visible = false,
			            BackgroundColor3 = Theme.Panel,
			            Position = UDim2.new(0, 0, 1, 4),
			            Size = UDim2.new(1, 0, 0, 150),
			            ZIndex = 1000, -- NAIKKAN SANGAT TINGGI agar di depan hotbar
			            ScrollBarThickness = 4,
			            BorderSizePixel = 0,
			            Parent = dropBtn
			        })
			        corner(listContainer, 8)
			        list(listContainer, Enum.FillDirection.Vertical, 2)
			        padding(listContainer, 4, 4, 4, 4)
			
			        local function rebuild()
			            for _, ch in ipairs(listContainer:GetChildren()) do
			                if ch:IsA("TextButton") or ch:IsA("Frame") then ch:Destroy() end
			            end
			
			            local header = mk("Frame", {
			                Size = UDim2.new(1, 0, 0, 25),
			                BackgroundTransparency = 1,
			                ZIndex = 1001,
			                Parent = listContainer
			            })
			            
			            local cancel = mk("TextButton", {
			                Size = UDim2.new(0, 22, 0, 22),
			                Position = UDim2.new(0, 2, 0, 0),
			                BackgroundColor3 = Color3.fromRGB(231, 76, 60),
			                Text = "✕",
			                TextColor3 = Color3.new(1,1,1),
			                Font = Enum.Font.GothamBold,
			                ZIndex = 1002,
			                Parent = header
			            })
			            corner(cancel, 6)
			
			            local save = mk("TextButton", {
			                Size = UDim2.new(0, 22, 0, 22),
			                Position = UDim2.new(1, -24, 0, 0),
			                BackgroundColor3 = Color3.fromRGB(46, 204, 113),
			                Text = "✓",
			                TextColor3 = Color3.new(1,1,1),
			                Font = Enum.Font.GothamBold,
			                ZIndex = 1002,
			                Parent = header
			            })
			            corner(save, 6)
			
			            save.MouseButton1Click:Connect(function()
			                handle.Selected = {}
			                local count = 0
			                for k, v in pairs(TempItems) do 
			                    handle.Selected[k] = v 
			                    count = count + 1
			                end
			                dropBtn.Text = (count > 0 and count .. " Selected ▼") or "Select Items... ▼"
			                open = false; listContainer.Visible = false; card.ZIndex = 1
			                if callback then callback(handle.Selected) end
			            end)
			
			            cancel.MouseButton1Click:Connect(function()
			                open = false; listContainer.Visible = false; card.ZIndex = 1
			            end)
			
			            for _, val in ipairs(handle._items) do
			                local valStr = tostring(val)
			                local isSel = TempItems[valStr]
			                local itemBtn = mk("TextButton", {
			                    BackgroundColor3 = isSel and Theme.Accent or Theme.Button,
			                    Size = UDim2.new(1, -8, 0, 28),
			                    Text = "  " .. valStr,
			                    TextColor3 = isSel and Color3.new(1,1,1) or Theme.Text,
			                    TextXAlignment = Enum.TextXAlignment.Left,
			                    Font = Enum.Font.Gotham,
			                    TextSize = 11,
			                    ZIndex = 1001,
			                    Parent = listContainer
			                })
			                corner(itemBtn, 4)
			                itemBtn.MouseButton1Click:Connect(function()
			                    TempItems[valStr] = not TempItems[valStr] and true or nil
			                    rebuild()
			                end)
			            end
			            listContainer.CanvasSize = UDim2.new(0,0,0, (#handle._items * 30) + 40)
			        end
			
			        handle._rebuild = rebuild
			        
			        -- FUNGSI RESET TERBARU
			        function handle:Set(targetTable)
			            handle.Selected = targetTable or {}
			            TempItems = {}
			            for k, v in pairs(handle.Selected) do TempItems[k] = v end
			            
			            local count = 0
			            for _ in pairs(handle.Selected) do count = count + 1 end
			            
			            if dropBtn then
			                dropBtn.Text = (count > 0 and count .. " Selected ▼") or "Select Items... ▼"
			            end
			            if open then rebuild() end
			        end
			
			        dropBtn.MouseButton1Click:Connect(function()
			            open = not open
			            listContainer.Visible = open
			            if open then
			                card.ZIndex = 500 -- Card naik saat terbuka agar list di atas elemen lain
			                TempItems = {}
			                for k, v in pairs(handle.Selected) do TempItems[k] = v end
			                rebuild()
			            else 
			                card.ZIndex = 1 
			            end
			        end)
			    end)
			
			    function handle:UpdateList(newList)
			        handle._items = newList or {}
			        if handle._rebuild then handle._rebuild() end
			    end
			
			    return handle
			end

			-- atur grid

			function sub:AddGridSelector(callback)
    			table.insert(sub._items, function()
        			local GridContainer = Instance.new("Frame")
        			local UIGridLayout = Instance.new("UIGridLayout")

        			GridContainer.Name = "GridContainer"
        			GridContainer.Parent = contentArea
        			GridContainer.BackgroundTransparency = 1
        			-- Sesuaikan lebar agar pas dengan 5 kolom
        			GridContainer.Size = UDim2.new(0, 240, 0, 240) 
        			-- Posisikan di tengah agar cantik
        			GridContainer.Position = UDim2.new(0.5, -120, 0, 0) 

        			UIGridLayout.Parent = GridContainer
        			UIGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
        			UIGridLayout.FillDirection = Enum.FillDirection.Horizontal
        			-- KUNCI UTAMA: Batasi hanya 5 kotak per baris
        			UIGridLayout.FillDirectionMaxCells = 5 
        			UIGridLayout.CellPadding = UDim2.new(0, 5, 0, 5)
        			UIGridLayout.CellSize = UDim2.new(0, 42, 0, 42)
        			UIGridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

        			local selectedTiles = {}

        			-- Loop untuk membuat 25 kotak
        			for y = 2, -2, -1 do
            			for x = -2, 2 do
                			local coord = x .. "," .. y
                			local TileBtn = Instance.new("TextButton")
                			TileBtn.Parent = GridContainer
                			-- Urutan Layout agar tidak berantakan
                			TileBtn.LayoutOrder = (2-y)*5 + (x+2) 
                			TileBtn.Text = (x == 0 and y == 0) and "P" or "" 
                			TileBtn.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
                			TileBtn.BorderSizePixel = 0
                
                			local UICorner = Instance.new("UICorner")
                			UICorner.CornerRadius = UDim.new(0, 6)
                			UICorner.Parent = TileBtn

                			janitor:Add(TileBtn.MouseButton1Click:Connect(function()
                    			if x == 0 and y == 0 then return end
                    
                    			if selectedTiles[coord] then
                        			selectedTiles[coord] = nil
                        			TileBtn.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
                    			else
                        			selectedTiles[coord] = true
                        			TileBtn.BackgroundColor3 = Color3.fromRGB(52, 152, 219)
                    			end
                    			safeCall(callback, selectedTiles)
                			end))
            			end
        			end
    			end)
    			return sub
			end

			-- ===== Input (with Get/Set handle) =====
			function sub:AddInput(text, placeholder, callback, defaultText)
				local handle = {
					Value = tostring(defaultText or ""),
					_apply = nil,
				}

				function handle:Get()
					return self.Value
				end

				function handle:Set(v, silent)
					v = tostring(v or "")
					self.Value = v
					if self._apply then
						self._apply(v, not silent)
					elseif (not silent) then
						safeCall(callback, v)
					end
				end

				table.insert(sub._items, function()
					local card = mk("Frame", {
						BackgroundColor3 = Theme.Panel,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 60),
						Parent = contentArea
					})
					corner(card, 12)
					stroke(card, 1, 0.65, Theme.Stroke)
					padding(card, 12, 10, 12, 10)

					mk("TextLabel", {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 18),
						Font = Enum.Font.GothamSemibold,
						TextSize = 13,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextColor3 = Theme.Text,
						Text = tostring(text),
						Parent = card
					})

					local box = mk("TextBox", {
						Position = UDim2.new(0, 0, 0, 24),
						Size = UDim2.new(1, 0, 0, 24),
						BackgroundColor3 = Theme.Panel2,
						BorderSizePixel = 0,
						ClearTextOnFocus = false,
						Font = Enum.Font.Gotham,
						TextSize = 12,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextColor3 = Theme.Text,
						PlaceholderText = placeholder or "",
						PlaceholderColor3 = Theme.Muted,
						Text = handle.Value,
						Parent = card
					})
					corner(box, 10)
					stroke(box, 1, 0.75, Theme.Stroke)
					padding(box, 10, 0, 10, 0)

					local function apply(v, fireCb)
						handle.Value = tostring(v or "")
						box.Text = handle.Value
						if fireCb then
							safeCall(callback, handle.Value)
						end
					end

					handle._apply = apply

					janitor:Add(box.FocusLost:Connect(function()
						apply(box.Text, true)
					end))
				end)

				return handle
			end

			-- ===== Slider (with Get/Set handle) =====
			function sub:AddSlider(text, minV, maxV, defaultV, callback)
				local minN = tonumber(minV) or 0
				local maxN = tonumber(maxV) or 100
				if maxN == minN then maxN = minN + 1 end

				local startVal = tonumber(defaultV)
				if startVal == nil then startVal = minN end
				startVal = clamp(startVal, minN, maxN)
				startVal = math.floor(startVal + 0.5)

				local handle = {
					Value = startVal,
					_apply = nil,
					_min = minN,
					_max = maxN,
				}

				function handle:Get()
					return self.Value
				end

				function handle:Set(v, silent)
					v = tonumber(v) or self.Value
					v = clamp(v, self._min, self._max)
					v = math.floor(v + 0.5)
					self.Value = v
					if self._apply then
						self._apply(v, not silent)
					elseif (not silent) then
						safeCall(callback, v)
					end
				end

				table.insert(sub._items, function()
					local card = mk("Frame", {
						BackgroundColor3 = Theme.Panel,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 62),
						Parent = contentArea
					})
					corner(card, 12)
					stroke(card, 1, 0.65, Theme.Stroke)
					padding(card, 12, 10, 12, 10)

					local topRow = mk("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), Parent = card })

					mk("TextLabel", {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, -80, 1, 0),
						Font = Enum.Font.GothamSemibold,
						TextSize = 13,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextColor3 = Theme.Text,
						Text = tostring(text),
						Parent = topRow
					})

					local valLbl = mk("TextLabel", {
						BackgroundTransparency = 1,
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, 0, 0, 0),
						Size = UDim2.new(0, 80, 1, 0),
						Font = Enum.Font.Gotham,
						TextSize = 12,
						TextXAlignment = Enum.TextXAlignment.Right,
						TextColor3 = Theme.Muted,
						Text = tostring(handle.Value),
						Parent = topRow
					})

					local track = mk("Frame", {
						Position = UDim2.new(0, 0, 0, 28),
						Size = UDim2.new(1, 0, 0, 10),
						BackgroundColor3 = Theme.Panel2,
						BorderSizePixel = 0,
						Parent = card
					})
					corner(track, 10)
					stroke(track, 1, 0.75, Theme.Stroke)

					local fill = mk("Frame", {
						Size = UDim2.new((handle.Value - minN) / (maxN - minN), 0, 1, 0),
						BackgroundColor3 = Theme.Accent,
						BorderSizePixel = 0,
						Parent = track
					})
					corner(fill, 10)

					local function apply(v, fireCb)
						handle.Value = v
						valLbl.Text = tostring(handle.Value)
						fill.Size = UDim2.new((handle.Value - minN) / (maxN - minN), 0, 1, 0)
						if fireCb then
							safeCall(callback, handle.Value)
						end
					end

					handle._apply = apply
					apply(handle.Value, false)

					local dragging = false
					local function setFromX(x, fireCb)
						local abs = track.AbsolutePosition.X
						local w = track.AbsoluteSize.X
						local a = clamp((x - abs) / w, 0, 1)
						local v = minN + (maxN - minN) * a
						v = math.floor(v + 0.5)
						apply(v, fireCb)
					end

					janitor:Add(track.InputBegan:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							dragging = true
							setFromX(input.Position.X, true)
						end
					end))
					janitor:Add(track.InputEnded:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							dragging = false
						end
					end))
					janitor:Add(UIS.InputChanged:Connect(function(input)
						if not dragging then return end
						if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
							setFromX(input.Position.X, true)
						end
					end))
				end)

				return handle
			end

			-- ===== Dropdown (with Get/Set handle) =====
			function sub:AddDropdown(text, listItems, default, callback)
				listItems = listItems or {}
				local current = default
				if current == nil then
					current = listItems[1]
				end

				local handle = {
					Value = current,
					_apply = nil,
					_items = listItems,
				}

				function handle:Get()
					return self.Value
				end

				function handle:Set(v, silent)
					self.Value = v
					if self._apply then
						self._apply(v, not silent)
					elseif (not silent) then
						safeCall(callback, v)
					end
				end

				table.insert(sub._items, function()
					local open = false
					local card = rowCard()
					card.ClipsDescendants = false
					card.ZIndex = 1

					mk("TextLabel", {
						BackgroundTransparency = 1,
						Size = UDim2.new(0.4, 0, 1, 0),
						Font = Enum.Font.GothamSemibold,
						TextSize = 13,
						TextColor3 = Theme.Text,
						TextXAlignment = Enum.TextXAlignment.Left,
						Text = tostring(text),
						Parent = card
					})

					local dropBtn = mk("TextButton", {
						BackgroundColor3 = Theme.Button,
						Position = UDim2.new(0.45, 0, 0, 0),
						Size = UDim2.new(0.55, 0, 1, 0),
						Font = Enum.Font.Gotham,
						TextSize = 13,
						TextColor3 = Theme.Text,
						Text = tostring(handle.Value) .. "  ▼",
						AutoButtonColor = false,
						Parent = card
					})
					corner(dropBtn, 8)
					stroke(dropBtn, 1, 0.7, Theme.Stroke)

					local listContainer = mk("Frame", {
						Name = "DropList",
						Visible = false,
						BackgroundColor3 = Theme.Panel,
						BorderSizePixel = 0,
						Position = UDim2.new(0, 0, 1, 4),
						Size = UDim2.new(1, 0, 0, 0),
						ZIndex = 100,
						Parent = dropBtn
					})
					corner(listContainer, 8)
					stroke(listContainer, 1, 0.5, Theme.Accent)

					local ll = list(listContainer, Enum.FillDirection.Vertical, 2)
					ll.HorizontalAlignment = Enum.HorizontalAlignment.Center
					padding(listContainer, 4, 4, 4, 4)

					local function rebuild()
						-- hapus item lama (jangan hapus layout/padding)
						for _, ch in ipairs(listContainer:GetChildren()) do
							if ch:IsA("TextButton") then
								ch:Destroy()
							end
						end

						for _, val in ipairs(handle._items) do
							local isSel = (val == handle.Value)
							local itemBtn = mk("TextButton", {
								BackgroundColor3 = isSel and Theme.Accent or Theme.Button,
								Size = UDim2.new(1, 0, 0, 30),
								Font = Enum.Font.Gotham,
								TextSize = 12,
								TextColor3 = isSel and Color3.new(1, 1, 1) or Theme.Text,
								Text = tostring(val),
								ZIndex = 101,
								AutoButtonColor = false,
								Parent = listContainer
							})
							corner(itemBtn, 6)

							janitor:Add(itemBtn.MouseButton1Click:Connect(function()
								open = false
								listContainer.Visible = false
								card.ZIndex = 1

								handle:Set(val, false)
							end))
						end

						listContainer.Size = UDim2.new(1, 0, 0, (#handle._items * 32) + 8)
					end

					local function apply(v, fireCb)
						handle.Value = v
						dropBtn.Text = tostring(v) .. "  ▼"
						if open then
							rebuild()
						end
						if fireCb then
							safeCall(callback, v)
						end
					end

					handle._apply = apply
					apply(handle.Value, false)

					janitor:Add(dropBtn.MouseButton1Click:Connect(function()
						open = not open
						listContainer.Visible = open
						if open then
							card.ZIndex = 100
							rebuild()
						else
							card.ZIndex = 1
						end
					end))

					-- close when clicking outside
					janitor:Add(UIS.InputBegan:Connect(function(input, gpe)
						if gpe then return end
						if not open then return end
						if input.UserInputType ~= Enum.UserInputType.MouseButton1
							and input.UserInputType ~= Enum.UserInputType.Touch then
							return
						end

						local mousePos = UIS:GetMouseLocation()
						local btnPos, btnSize = dropBtn.AbsolutePosition, dropBtn.AbsoluteSize
						local listPos, listSize = listContainer.AbsolutePosition, listContainer.AbsoluteSize

						local function inRect(p, pos, size)
							return p.X >= pos.X and p.X <= (pos.X + size.X)
								and p.Y >= pos.Y and p.Y <= (pos.Y + size.Y)
						end

						if inRect(mousePos, btnPos, btnSize) or (listContainer.Visible and inRect(mousePos, listPos, listSize)) then
							return
						end

						open = false
						listContainer.Visible = false
						card.ZIndex = 1
					end))
				end)

				return handle
			end

			table.insert(tab.SubTabs, sub)
			return sub
		end

		table.insert(Window._mainTabs, tab)

		-- auto select first tab if none active
		if not Window._activeMain then
    		setActiveMain()
		end

		return tab
	end

	-- ===== Default notifications =====
	if opts.ShowWelcomeToast ~= false then
		task.delay(0.1, function()
			if not Window._closed then
				Window:Notify("Loaded. Press [" .. keybind.Name .. "] to toggle UI.", 2.2, "ok")
			end
		end)
	end

	return Window
end

return SayzUI.new()
