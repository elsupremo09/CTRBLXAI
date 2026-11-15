--!strict
-- GuildScreen.lua
-- CTRBLXAI | Shared full-screen frame for guild building screens (2026-10-31, user ruling).
--
-- Each guild building (Merchant now; Tavern, Blacksmith, Dispatch, Adventurer's Guild later)
-- is its OWN full screen, like the Loadout screen: it opens over the guild menu and Back
-- returns to it. The guild menu is a temporary hub; later each screen is opened by its NPC
-- or structure, so a screen must not depend on the menu's layout.
--
-- Layout (landscape):
--   header  : title (left, clear of Roblox's top-left buttons) | status | gold (right)
--   Main    : left panel  (~62%) -- grids / lists
--   Side    : right panel (~38%) -- inspector
--   Buttons : lower-right group under Side -- EVERY button of the screen (user ruling
--             2026-10-31: all buttons in one area, lower right)
--
-- Display only. Callers fill Main / Side / Buttons and own all behavior. Every instance is a
-- descendant of the ScreenGui, so Destroy() cleans everything (MEM-002 / PRF-004).

local GuiService = game:GetService("GuiService")

local WAIT = 10

local themeModule = script.Parent:WaitForChild("Theme", WAIT)
if not themeModule then
	error("[GuildScreen] Theme module not found")
end
-- Found at runtime via WaitForChild; the editor cannot follow that path (editor-only cast).
local Theme: any = (require :: any)(themeModule)

local GuildScreen = {}

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

local SIDE_SHARE = 0.38       -- right column width share
local MARGIN = 8              -- screen edge / panel gap (px)
local MIN_HEADER_H = 40       -- header height when the Roblox top bar is shorter
local ROW_GAP = 4             -- gap between button rows
local PANEL_PAD = 8           -- inner padding of the ornate panels
local PROMPT_W = 340          -- confirmation prompt box (px)
local PROMPT_H = 170

--------------------------------------------------
-- HELPERS (properties before Parent, NET-004)
--------------------------------------------------

local function makeText(parent: Instance, size: number, color: Color3, bold: boolean?): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.BorderSizePixel = 0
	lbl.Font = if bold then Theme.Font.PrimaryBold else Theme.Font.Primary
	lbl.TextSize = size
	lbl.TextColor3 = color
	lbl.TextWrapped = true
	lbl.TextTruncate = Enum.TextTruncate.AtEnd
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.Text = ""
	lbl.Parent = parent
	return lbl
end

local function makeHolder(name: string, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function addPadding(parent: Instance, px: number)
	local pad = Instance.new("UIPadding") -- one UIPadding per frame (Roblox honours only one)
	pad.PaddingLeft = UDim.new(0, px)
	pad.PaddingRight = UDim.new(0, px)
	pad.PaddingTop = UDim.new(0, px)
	pad.PaddingBottom = UDim.new(0, px)
	pad.Parent = parent
end

local function clearChildren(holder: Instance)
	for _, child in holder:GetChildren() do
		child:Destroy()
	end
end

--------------------------------------------------
-- PUBLIC
--------------------------------------------------

-- Button row height for callers sizing their rows (44 px touch minimum, loadout_ui_spec 73).
GuildScreen.ROW_H = Theme.MinSize.TouchTarget
GuildScreen.ROW_GAP = ROW_GAP

-- opts: name (ScreenGui name), title, parent (PlayerGui).
-- Returns a screen table: Gui, Main, Side, Buttons, and the methods below.
function GuildScreen.Create(opts: { name: string, title: string, parent: Instance }): any
	local gui = Instance.new("ScreenGui")
	gui.Name = opts.name
	gui.ResetOnSpawn = false
	-- Full-screen backdrop covers the top bar too; content is offset below it in layout().
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = Theme.FullScreen.DisplayOrder -- same layer as the Loadout screen
	-- Sibling: children always draw over their parent, so the prompt (a later, higher-ZIndex
	-- sibling of the backdrop) always sits on top of the screen.
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.FullScreen.BackgroundColor
	backdrop.BackgroundTransparency = Theme.FullScreen.BackgroundTransparency
	backdrop.BorderSizePixel = 0
	backdrop.Active = true -- swallow taps so nothing underneath reacts
	backdrop.Parent = gui

	-- Header: title | status | gold
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.BorderSizePixel = 0
	header.Parent = backdrop
	local title = makeText(header, Theme.Text.Title(), Theme.Colors.TextGold, true)
	title.Name = "Title"
	title.Font = Theme.Font.Display
	title.Text = opts.title
	title.Size = UDim2.new(0.3, 0, 1, 0)
	local status = makeText(header, Theme.Text.Small(), Theme.Colors.TextSecondary)
	status.Name = "Status"
	status.Size = UDim2.new(0.4, 0, 1, 0)
	status.Position = UDim2.new(0.3, 0, 0, 0)
	status.TextXAlignment = Enum.TextXAlignment.Center
	local gold = makeText(header, Theme.Text.Body(), Theme.Colors.TextPrimary, true)
	gold.Name = "Gold"
	gold.Size = UDim2.new(0.3, 0, 1, 0)
	gold.Position = UDim2.new(0.7, 0, 0, 0)
	gold.TextXAlignment = Enum.TextXAlignment.Right

	-- Main (left) and Side (right) ornate panels; Buttons group (lower right).
	local mainPanel = Theme.MakePanel("MainPanel", UDim2.new(), UDim2.new(), nil, backdrop)
	addPadding(mainPanel, PANEL_PAD)
	local main = makeHolder("Main", mainPanel)
	local sidePanel = Theme.MakePanel("SidePanel", UDim2.new(), UDim2.new(), nil, backdrop)
	addPadding(sidePanel, PANEL_PAD)
	local side = makeHolder("Side", sidePanel)
	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.AnchorPoint = Vector2.new(1, 1)
	buttons.BackgroundTransparency = 1
	buttons.BorderSizePixel = 0
	buttons.Parent = backdrop

	Theme.MakeScreenBorder(backdrop)

	local self: any = {
		Gui = gui,
		Main = main,
		Side = side,
		Buttons = buttons,
	}
	local buttonRows = 1

	-- KEEP SCROLL (2026-11-06, user bug): every screen rebuilds Main on each tap (select an
	-- item, stage a level, queue a dismantle), which destroyed the item grid and jumped the
	-- list back to the top. Clear(scrollKey) remembers the grid's scroll position, and the
	-- rebuilt grid gets it back when the key is the same (same tab). A different key (tab
	-- switch), Show() (a fresh visit) or ResetScroll() (new search/filter) start at the top.
	local lastScrollKey: string? = nil
	local pendingScroll: Vector2? = nil

	local function restoreScroll(grid: ScrollingFrame, pos: Vector2)
		-- AutomaticCanvasSize resolves during layout; until then the position clamps to 0,
		-- so apply now and again when the canvas size settles (before the frame draws).
		local function apply(): boolean
			if grid.Parent == nil then return true end
			local maxY = math.max(0, grid.AbsoluteCanvasSize.Y - grid.AbsoluteWindowSize.Y)
			grid.CanvasPosition = Vector2.new(0, math.min(pos.Y, maxY))
			return maxY >= pos.Y
		end
		if apply() then return end
		local conn: RBXScriptConnection? = nil
		conn = grid:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
			if apply() and conn then conn:Disconnect() end
		end)
		-- A shorter list (items removed) never reaches the old position: stop listening.
		task.delay(1, function()
			if conn and conn.Connected then conn:Disconnect() end
		end)
	end

	-- Same keep-scroll for any other scroll list a screen rebuilds (2026-11-07: the
	-- Runeforge side panel). Caller passes the rebuilt frame and the position it saved.
	self.RestoreScroll = restoreScroll

	-- The connection lives with Main (destroyed with the ScreenGui, PRF-004).
	main.DescendantAdded:Connect(function(d: Instance)
		local pos = pendingScroll
		if pos and d.Name == "Grid" and d:IsA("ScrollingFrame") then
			pendingScroll = nil
			restoreScroll(d, pos)
		end
	end)

	-- Positions depend on the Roblox top bar, so they are recomputed on every Show().
	local function layout()
		local insetY = GuiService:GetGuiInset().Y
		local headerH = math.max(MIN_HEADER_H, insetY)
		-- Title starts right of Roblox's own top-left buttons (they always draw on top).
		local leftX = math.max(MARGIN * 2, GuiService.TopbarInset.Min.X + MARGIN)
		header.Position = UDim2.fromOffset(leftX, 0)
		header.Size = UDim2.new(1, -(leftX + MARGIN * 2), 0, headerH)

		local top = headerH + MARGIN // 2
		local buttonsH = buttonRows * GuildScreen.ROW_H + (buttonRows - 1) * ROW_GAP
		mainPanel.Position = UDim2.fromOffset(MARGIN, top)
		mainPanel.Size = UDim2.new(1 - SIDE_SHARE, -MARGIN * 1.5, 1, -(top + MARGIN))
		sidePanel.Position = UDim2.new(1 - SIDE_SHARE, MARGIN // 2, 0, top)
		sidePanel.Size = UDim2.new(SIDE_SHARE, -MARGIN * 1.5, 1, -(top + MARGIN * 2 + buttonsH))
		buttons.Position = UDim2.new(1, -MARGIN, 1, -MARGIN)
		buttons.Size = UDim2.new(SIDE_SHARE, -MARGIN * 1.5, 0, buttonsH)
	end

	-- Number of button rows the caller will build (sizes the Buttons group and Side panel).
	function self.SetButtonRows(n: number)
		buttonRows = math.max(1, n)
		layout()
	end

	function self.SetGold(text: string)
		gold.Text = text
	end

	-- Server answers / errors (moved here from the guild menu status line while this is open).
	function self.SetStatus(text: string, isError: boolean?)
		status.Text = text
		status.TextColor3 = if isError then Theme.Colors.Danger else Theme.Colors.Success
	end

	-- Confirmation prompt (2026-10-31, user ruling): a modal box over the whole screen with
	-- Cancel + one confirm button. Confirm closes the prompt, then runs onConfirm. Taps
	-- outside the box are absorbed (the overlay is a Modal button) and do nothing.
	local prompt: Instance? = nil

	function self.ClosePrompt()
		if prompt then
			prompt:Destroy()
			prompt = nil
		end
	end

	function self.Prompt(message: string, confirmText: string, confirmStyle: string, onConfirm: () -> ())
		self.ClosePrompt()
		local overlay = Instance.new("TextButton")
		overlay.Name = "Prompt"
		overlay.Text = ""
		overlay.AutoButtonColor = false
		overlay.Modal = true
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.BackgroundColor3 = Color3.new(0, 0, 0)
		overlay.BackgroundTransparency = 0.4
		overlay.BorderSizePixel = 0
		overlay.ZIndex = 20

		local box = Instance.new("Frame")
		box.Name = "Box"
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromScale(0.5, 0.5)
		box.Size = UDim2.fromOffset(PROMPT_W, PROMPT_H)
		box.BackgroundColor3 = Theme.Colors.PanelRaised
		box.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = Theme.CornerRadius.md
		corner.Parent = box
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = Theme.Colors.Border
		stroke.Thickness = Theme.BorderThickness.Default
		stroke.Parent = box

		local msg = makeText(box, Theme.Text.Body(), Theme.Colors.TextPrimary)
		msg.TextTruncate = Enum.TextTruncate.None
		msg.TextXAlignment = Enum.TextXAlignment.Center
		msg.TextYAlignment = Enum.TextYAlignment.Center
		msg.Size = UDim2.new(1, -24, 1, -(GuildScreen.ROW_H + 30))
		msg.Position = UDim2.fromOffset(12, 10)
		msg.Text = message

		local row = Instance.new("Frame")
		row.Name = "Buttons"
		row.Size = UDim2.new(1, -24, 0, GuildScreen.ROW_H)
		row.Position = UDim2.new(0, 12, 1, -(GuildScreen.ROW_H + 10))
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.Padding = UDim.new(0, 8)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = row
		local half = UDim2.new(0.5, -4, 1, 0)
		Theme.MakeBarButton(row, "Cancel", "Secondary", function()
			self.ClosePrompt()
		end, { name = "Btn_PromptCancel", size = half, autoWidth = false,
			minHeight = GuildScreen.ROW_H, layoutOrder = 1 })
		Theme.MakeBarButton(row, confirmText, confirmStyle, function()
			self.ClosePrompt()
			onConfirm()
		end, { name = "Btn_PromptConfirm", size = half, autoWidth = false,
			minHeight = GuildScreen.ROW_H, layoutOrder = 2 })
		row.Parent = box
		box.Parent = overlay
		overlay.Parent = gui -- parent last (NET-004)
		prompt = overlay
	end

	-- Empties Main / Side / Buttons for a full re-render. scrollKey (e.g. the current tab):
	-- when it matches the previous Clear, the rebuilt "Grid" keeps its scroll position.
	function self.Clear(scrollKey: string?)
		local old = main:FindFirstChild("Grid", true)
		if scrollKey ~= nil and scrollKey == lastScrollKey and old and old:IsA("ScrollingFrame") then
			pendingScroll = old.CanvasPosition
		else
			pendingScroll = nil
		end
		lastScrollKey = scrollKey
		clearChildren(main)
		clearChildren(side)
		clearChildren(buttons)
	end

	-- The next rebuild starts the grid at the top (new search or filter).
	function self.ResetScroll()
		lastScrollKey = nil
		pendingScroll = nil
	end

	function self.Show()
		self.ResetScroll() -- each visit starts at the top
		layout()
		gui.Enabled = true
	end

	function self.Hide()
		self.ClosePrompt()
		gui.Enabled = false
	end

	function self.IsShown(): boolean
		return gui.Enabled
	end

	function self.Destroy()
		gui:Destroy()
	end

	layout()
	gui.Parent = opts.parent -- parent last (NET-004)
	return self
end

return table.freeze(GuildScreen)
