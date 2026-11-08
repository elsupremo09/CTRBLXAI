--!strict
-- DevToolsPanel.lua
-- CTRBLXAI | Always-on Studio dev panel (2026-10-31, user decision: two dev panels).
--
-- Shown on EVERY screen (guild menu, Merchant, Loadout, battle), drawn above all game UI.
-- Holds the general tools; the battle DEV panel (BattleVisualClient) keeps only the tools
-- that need a live battle map.
--   SHOPS      Refresh all shops (Merchant + Tavern + Dispatch; kept in the save)
--   BUILDINGS  Guild Hall / Tavern / Merchant / Blacksmith / Runeforge level - / +
--              (the Runeforge and Apothecary work only from Guild Hall L4, the Crucible from L5; all capped at the Guild Hall level)
--   GENERAL    Gold +10,000, Mercury +100, Grant all cards, Save now, Delete save, Reset UGC trial/rent
--
-- Studio only: GuildMenu.client requires this only in Studio, and the server refuses every
-- dev request outside Studio. Display + input only: the panel sends an action name and ids;
-- the server validates and applies (SEC-001 / SEC-002). Created once per session and kept for
-- the whole session (ResetOnSpawn = false), so its few connections live as long as it does.

local UserInputService = game:GetService("UserInputService")

local DevToolsPanel = {}

--------------------------------------------------
-- TYPES / CONSTANTS
--------------------------------------------------

export type Context = {
	parent: Instance,                  -- PlayerGui
	devGuild: RemoteFunction?,         -- GuildEvents.DevGuild (answers with building levels)
	devCommand: RemoteEvent?,          -- BattleEvents.DevCommand (existing general dev actions)
	onShopsRefreshed: () -> (),        -- guild menu drops stale pending buys and redraws
	onLevelsChanged: () -> (),
	onGoldChanged: () -> (),
}

local DISPLAY_ORDER = 500           -- above every game screen (highest game layer is 310)
local PANEL_W = 196
local TITLE_H = 16
local EXPANDED_H = 330
local BTN_H = 18
local CONFIRM_WINDOW = 2.5          -- seconds to tap a guarded button a second time
local GOLD_REFRESH_DELAY = 0.6      -- DevCommand sends no answer; refresh the gold line after this
local BUILDINGS = { "GuildHall", "Tavern", "Merchant", "Blacksmith", "Runeforge", "Crucible", "Apothecary", "TrainingGrounds" }
local LEVEL_MIN, LEVEL_MAX = 1, 10  -- guild_facilities: Max Level 10 (server clamps too)

local COLOR_PANEL = Color3.fromRGB(28, 28, 38)
local COLOR_TITLE = Color3.fromRGB(45, 45, 60)
local COLOR_ACCENT = Color3.fromRGB(120, 200, 255) -- blue, so it is never confused with the
                                                    -- yellow battle DEV panel
local COLOR_TEXT = Color3.fromRGB(230, 230, 230)
local COLOR_OK = Color3.fromRGB(150, 220, 150)
local COLOR_ERR = Color3.fromRGB(255, 120, 120)

--------------------------------------------------
-- STATE
--------------------------------------------------

local ctx: Context? = nil
local gui: ScreenGui? = nil
local isBusy = false
local levels: { [string]: number } = {}
local levelLabels: { [string]: TextLabel } = {}
local statusLabel: TextLabel? = nil

--------------------------------------------------
-- HELPERS (properties before Parent, NET-004)
--------------------------------------------------

local function setStatus(text: string, isError: boolean?)
	local s = statusLabel
	if not s then return end
	s.Text = text
	s.TextColor3 = if isError then COLOR_ERR else COLOR_OK
end

local function makeLabel(parent: Instance, text: string, color: Color3, order: number): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.BorderSizePixel = 0
	lbl.Font = Enum.Font.SourceSansBold
	lbl.TextSize = 11
	lbl.TextColor3 = color
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Size = UDim2.new(1, 0, 0, 14)
	lbl.LayoutOrder = order
	lbl.Text = text
	lbl.Parent = parent
	return lbl
end

local function makeBtn(parent: Instance, text: string, color: Color3, order: number, onTap: () -> ()): TextButton
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, BTN_H)
	btn.BackgroundColor3 = color
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Font = Enum.Font.SourceSansBold
	btn.TextSize = 11
	btn.TextColor3 = Color3.new(1, 1, 1) -- bar/tab button rule: pure white text
	btn.TextStrokeColor3 = Color3.new(0, 0, 0) -- + black outline (same method as Theme)
	btn.TextStrokeTransparency = 0
	btn.LayoutOrder = order
	btn.Text = text
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = btn
	btn.Activated:Connect(onTap) -- dies with the button
	btn.Parent = parent
	return btn
end

-- Guarded button: the first tap arms it ("CONFIRM? ..."), a second tap within the window runs it.
local function makeConfirmBtn(parent: Instance, text: string, color: Color3, order: number, onConfirm: () -> ())
	local armed = false
	local btn: TextButton
	btn = makeBtn(parent, text, color, order, function()
		if not armed then
			armed = true
			btn.Text = `CONFIRM? {text}`
			task.delay(CONFIRM_WINDOW, function()
				if armed and btn.Parent then
					armed = false
					btn.Text = text
				end
			end)
			return
		end
		armed = false
		btn.Text = text
		onConfirm()
	end)
end

--------------------------------------------------
-- SERVER CALLS
--------------------------------------------------

local function renderLevels()
	for _, name in BUILDINGS do
		local lbl = levelLabels[name]
		if lbl then lbl.Text = `{name}  L{levels[name] or "?"}` end
	end
end

-- Ask the server (GuildEvents.DevGuild). On success the answer carries the building levels.
local function devGuild(payload: { [string]: any }): any?
	local c = ctx
	local remote = c and c.devGuild
	if not remote then
		setStatus("Dev remote missing", true)
		return nil
	end
	if isBusy then return nil end
	isBusy = true
	local ok, res = pcall(remote.InvokeServer, remote, payload)
	isBusy = false
	if not ok then
		setStatus(`Server did not answer: {tostring(res)}`, true)
		return nil
	end
	if type(res) ~= "table" or res.ok == false then
		setStatus(if type(res) == "table" then tostring(res.error) else "Unexpected answer", true)
		return nil
	end
	if type(res.buildings) == "table" then
		for _, name in BUILDINGS do
			local v = res.buildings[name]
			if type(v) == "number" then levels[name] = v end
		end
		renderLevels()
	end
	return res
end

local function devCommand(action: string)
	local c = ctx
	local remote = c and c.devCommand
	if not remote then
		setStatus("Dev command remote missing", true)
		return
	end
	remote:FireServer({ action = action })
end

--------------------------------------------------
-- BUILD
--------------------------------------------------

local function addGroup(body: Instance, title: string, order: number): Frame
	local group = Instance.new("Frame")
	group.Name = `Group_{title}`
	group.Size = UDim2.new(1, 0, 0, 0)
	group.AutomaticSize = Enum.AutomaticSize.Y
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.LayoutOrder = order
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 2)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = group
	makeLabel(group, title, COLOR_ACCENT, 0)
	group.Parent = body
	return group
end

local function addLevelRow(group: Instance, name: string, order: number)
	local row = Instance.new("Frame")
	row.Name = `Level_{name}`
	row.Size = UDim2.new(1, 0, 0, BTN_H)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	local lbl = makeLabel(row, `{name}  L?`, COLOR_TEXT, 0)
	lbl.Size = UDim2.new(1, -(BTN_H * 2 + 8), 1, 0)
	levelLabels[name] = lbl
	local function step(delta: number)
		local cur = levels[name]
		if not cur then
			setStatus("Levels not loaded yet", true)
			return
		end
		local target = math.clamp(cur + delta, LEVEL_MIN, LEVEL_MAX)
		if target == cur then return end
		local res = devGuild({ action = "SetBuildingLevel", building = name, level = target })
		if res then
			setStatus(`{name} set to L{levels[name] or target}`)
			local c = ctx
			if c then c.onLevelsChanged() end
		end
	end
	local minus = makeBtn(row, "-", Color3.fromRGB(110, 70, 30), 1, function() step(-1) end)
	minus.Size = UDim2.fromOffset(BTN_H, BTN_H)
	minus.Position = UDim2.new(1, -(BTN_H * 2 + 4), 0, 0)
	local plus = makeBtn(row, "+", Color3.fromRGB(40, 100, 50), 2, function() step(1) end)
	plus.Size = UDim2.fromOffset(BTN_H, BTN_H)
	plus.Position = UDim2.new(1, -BTN_H, 0, 0)
	row.Parent = group
end

local function build(c: Context)
	local screen = Instance.new("ScreenGui")
	screen.Name = "DevTools"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = DISPLAY_ORDER
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local root = Instance.new("Frame")
	root.Name = "DevToolsPanel"
	root.Size = UDim2.fromOffset(PANEL_W, TITLE_H)
	root.Position = UDim2.fromOffset(320, 4) -- right of the battle DEV panel (x 130, w 184)
	root.BackgroundColor3 = COLOR_PANEL
	root.BackgroundTransparency = 0.05
	root.BorderSizePixel = 0
	root.Active = true
	root.ClipsDescendants = true
	local rootCorner = Instance.new("UICorner")
	rootCorner.CornerRadius = UDim.new(0, 6)
	rootCorner.Parent = root
	local rootStroke = Instance.new("UIStroke")
	rootStroke.Color = COLOR_ACCENT
	rootStroke.Thickness = 1
	rootStroke.Parent = root

	local title = Instance.new("TextButton")
	title.Name = "TitleBar"
	title.Size = UDim2.new(1, 0, 0, TITLE_H)
	title.BackgroundColor3 = COLOR_TITLE
	title.BackgroundTransparency = 0.2
	title.BorderSizePixel = 0
	title.AutoButtonColor = false
	title.Font = Enum.Font.SourceSansBold
	title.TextSize = 10
	title.TextColor3 = COLOR_ACCENT
	title.Text = "> DEV TOOLS  (drag)"
	title.Parent = root

	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.Size = UDim2.new(1, 0, 1, -TITLE_H)
	body.Position = UDim2.fromOffset(0, TITLE_H)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 4
	body.ScrollBarImageColor3 = COLOR_ACCENT
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.CanvasSize = UDim2.new()
	body.Visible = false
	local bodyList = Instance.new("UIListLayout")
	bodyList.Padding = UDim.new(0, 6)
	bodyList.SortOrder = Enum.SortOrder.LayoutOrder
	bodyList.Parent = body
	local bodyPad = Instance.new("UIPadding")
	bodyPad.PaddingTop = UDim.new(0, 3)
	bodyPad.PaddingLeft = UDim.new(0, 4)
	bodyPad.PaddingRight = UDim.new(0, 6)
	bodyPad.PaddingBottom = UDim.new(0, 4)
	bodyPad.Parent = body
	body.Parent = root

	-- SHOPS
	local gShops = addGroup(body, "SHOPS", 1)
	makeConfirmBtn(gShops, "REFRESH ALL SHOPS", Color3.fromRGB(40, 70, 110), 1, function()
		local res = devGuild({ action = "RefreshShops" })
		if res then
			setStatus(`Shops refreshed (#{res.shopRefresh or "?"})`)
			c.onShopsRefreshed()
		end
	end)

	-- BUILDINGS
	local gLevels = addGroup(body, "BUILDING LEVELS", 2)
	for i, name in BUILDINGS do
		addLevelRow(gLevels, name, i)
	end

	-- GENERAL (same DevCommand actions the battle panel used to hold)
	local gGeneral = addGroup(body, "GENERAL", 3)
	makeBtn(gGeneral, "GOLD +10,000", Color3.fromRGB(90, 75, 20), 1, function()
		devCommand("DevAddGold")
		setStatus("Gold +10,000 requested")
		task.delay(GOLD_REFRESH_DELAY, c.onGoldChanged)
	end)
	makeBtn(gGeneral, "MERCURY +100", Color3.fromRGB(70, 75, 90), 2, function()
		devCommand("DevAddMercury")
		setStatus("Mercury +100 requested")
		task.delay(GOLD_REFRESH_DELAY, c.onGoldChanged)
	end)
	makeBtn(gGeneral, "GRANT +100 ALL MATERIALS", Color3.fromRGB(75, 60, 95), 3, function()
		devCommand("DevGrantAllMaterials")
		setStatus("+100 gold/mercury/crystals/sulfur requested")
		task.delay(GOLD_REFRESH_DELAY, c.onGoldChanged)
	end)
	makeBtn(gGeneral, "GRANT ALL CARDS", Color3.fromRGB(40, 80, 55), 4, function()
		devCommand("DevGrantAllCards")
		setStatus("Grant all cards requested (see Output)")
	end)
	makeBtn(gGeneral, "SAVE NOW", Color3.fromRGB(30, 60, 80), 5, function()
		devCommand("SaveNow")
		setStatus("Save requested (see Output)")
	end)
	makeConfirmBtn(gGeneral, "DELETE SAVE", Color3.fromRGB(80, 20, 20), 6, function()
		devCommand("DeleteSave")
		setStatus("Delete save requested -- restart to begin fresh")
	end)
	makeConfirmBtn(gGeneral, "RESET UGC TRIAL/RENT", Color3.fromRGB(70, 45, 80), 7, function()
		devCommand("DevResetUGCRecords")
		setStatus("UGC reset requested (see Output)")
	end)

	local status = makeLabel(body, "", COLOR_OK, 10)
	status.TextWrapped = true
	status.Size = UDim2.new(1, 0, 0, 0)
	status.AutomaticSize = Enum.AutomaticSize.Y
	statusLabel = status

	-- Expand / collapse (a tap that was really a drag does not toggle).
	local expanded = false
	local dragMoved = false
	title.Activated:Connect(function()
		if dragMoved then
			dragMoved = false
			return
		end
		expanded = not expanded
		body.Visible = expanded
		root.Size = UDim2.fromOffset(PANEL_W, if expanded then EXPANDED_H else TITLE_H)
		title.Text = if expanded then "v DEV TOOLS  (drag)" else "> DEV TOOLS  (drag)"
		if expanded then devGuild({ action = "GetLevels" }) end -- fresh levels each time it opens
	end)

	-- Drag the title bar to move the panel.
	local dragging = false
	local dragStart = Vector3.zero
	local startPos = root.Position
	title.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragMoved = false
			dragStart = input.Position
			startPos = root.Position
		end
	end)
	title.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	-- One connection for the whole session (the panel is never rebuilt).
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if not dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local delta = input.Position - dragStart
		if math.abs(delta.X) + math.abs(delta.Y) > 4 then dragMoved = true end
		root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end)

	root.Parent = screen
	screen.Parent = c.parent -- parent last (NET-004)
	gui = screen
end

--------------------------------------------------
-- PUBLIC
--------------------------------------------------

-- Builds the panel once. Later calls only swap the callbacks.
function DevToolsPanel.Init(c: Context)
	ctx = c
	if gui then return end
	build(c)
	print("[DevToolsPanel] Ready (Studio or owner dev access) -- drag the blue DEV TOOLS bar")
end

return table.freeze(DevToolsPanel)
