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
-- Header currency strip (icon + number), same builder as the guild home header (2026-11-17).
local currencyStripModule = script.Parent:WaitForChild("CurrencyStrip", WAIT)
local CurrencyStrip: any = if currencyStripModule then (require :: any)(currencyStripModule) else nil

local GuildScreen = {}

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

local SIDE_SHARE = 0.38       -- right column width share
local MARGIN = 8              -- screen edge / panel gap (px)
local MIN_HEADER_H = 40       -- header height when the Roblox top bar is shorter
local ROW_GAP = 4             -- gap between button rows
local PANEL_PAD = 8           -- inner padding of the ornate panels
local FRAME_EDGE = 4          -- visible edge line of the ornate panel frame (px)
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
-- SHARED FRAME (header | ornate Main + Side panels | lower-right Buttons)
--------------------------------------------------

-- Builds the screen parts inside `backdrop`; used by Create (own ScreenGui) and CreateView
-- (a layer inside an open screen). f.rows = button rows; f.Layout() places everything below
-- the Roblox top bar (moved word for word from Create, 2026-11-17).
-- hopts.crest (2026-11-17, user: the dungeon header mimics the guild base header): a gold-framed
-- header with the crest left, the title, the status line under the title, a two-line details block
-- right of the title (where the guild base shows Rank; SetDetails) and the currencies on the right.
local function buildFrame(backdrop: GuiObject, titleText: string, fullMain: boolean?, hopts: { crest: string? }?): any
	local framed = hopts ~= nil and hopts.crest ~= nil
	-- Header: title | status | gold
	local header: GuiObject
	local details: Frame? = nil
	local detailLines: { TextLabel } = {}
	local strip: any = nil -- header currency strip (SetCurrencies)
	local placeText: () -> () = function() end -- framed header: re-fit the text to the width left of the strip
	if framed then
		header = Theme.MakePanel("Header", UDim2.new(), UDim2.new(), nil, backdrop)
		local hp = Instance.new("UIPadding") -- same side padding as the guild base header (clears the corners)
		hp.PaddingLeft = UDim.new(0, 14)
		hp.PaddingRight = UDim.new(0, 14)
		hp.PaddingTop = UDim.new(0, 4)
		hp.PaddingBottom = UDim.new(0, 4)
		hp.Parent = header
	else
		local plain = Instance.new("Frame")
		plain.Name = "Header"
		plain.BackgroundTransparency = 1
		plain.BorderSizePixel = 0
		plain.Parent = backdrop
		header = plain
	end
	local title = makeText(header, Theme.Text.Title(), Theme.Colors.TextGold, true)
	title.Name = "Title"
	title.Font = Theme.Font.Display
	title.Text = titleText
	title.Size = UDim2.new(0.3, 0, 1, 0)
	local status = makeText(header, Theme.Text.Small(), Theme.Colors.TextSecondary)
	status.Name = "Status"
	status.Size = UDim2.new(0.4, 0, 1, 0)
	status.Position = UDim2.new(0.3, 0, 0, 0)
	status.TextXAlignment = Enum.TextXAlignment.Center
	if framed and hopts then
		local crest = Instance.new("ImageLabel")
		crest.Name = "Crest"
		crest.BackgroundTransparency = 1
		crest.ScaleType = Enum.ScaleType.Fit
		crest.Image = hopts.crest or ""
		crest.Size = UDim2.fromScale(1, 1)
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 1
		ar.DominantAxis = Enum.DominantAxis.Height
		ar.Parent = crest
		crest.Parent = header
		-- Status under the title (guild base look), auto-fit down to the 10 px phone floor.
		status.TextXAlignment = Enum.TextXAlignment.Left
		status.TextScaled = true
		local fit = Instance.new("UITextSizeConstraint")
		fit.MaxTextSize = Theme.Text.Small()
		fit.MinTextSize = 10
		fit.Parent = status
		local block = Instance.new("Frame")
		block.Name = "Details"
		block.BackgroundTransparency = 1
		block.BorderSizePixel = 0
		for i = 1, 2 do
			-- Both lines white, regular (user 2026-11-17 12:00 PM: Difficulty like Battle Field Condition).
			local l = makeText(block, Theme.Text.Small(), Theme.Colors.TextPrimary)
			l.Name = "Line" .. i
			l.TextWrapped = false
			l.TextScaled = true
			l.Size = UDim2.fromScale(1, 0.5)
			l.Position = UDim2.fromScale(0, (i - 1) * 0.5)
			local c = Instance.new("UITextSizeConstraint")
			c.MaxTextSize = Theme.Text.Small()
			c.MinTextSize = 10
			c.Parent = l
			detailLines[i] = l
		end
		block.Parent = header
		details = block
		-- User 2026-11-17 11:39 AM: three stacked lines right of the crest (title, then the two
		-- details lines); the status sits on the title row after the title. The currency strip is the
		-- guild base's (right 60%, same fit), and the text gets the width left of the visible icons.
		title.TextScaled = true
		local tfit = Instance.new("UITextSizeConstraint")
		tfit.MaxTextSize = Theme.Text.Title()
		tfit.MinTextSize = 12
		tfit.Parent = title
		local function place()
			local cw = crest.AbsoluteSize.X + 6
			local innerW = header.AbsoluteSize.X - 28 -- 14 px side padding each side
			local used = if strip and strip.Strip.Visible then strip.ContentWidth() + 10 else math.floor(innerW * 0.6)
			local w = math.max(40, innerW - cw - used)
			title.Position = UDim2.fromOffset(cw, 0)
			title.Size = UDim2.new(0, w, 0.44, 0)
			local sx = math.min(w, title.TextBounds.X + 8)
			status.Position = UDim2.new(0, cw + sx, 0, 0)
			status.Size = UDim2.new(0, math.max(0, w - sx), 0.44, 0)
			block.Position = UDim2.new(0, cw, 0.44, 0)
			block.Size = UDim2.new(0, w, 0.56, 0)
		end
		placeText = place
		place()
		title:GetPropertyChangedSignal("TextBounds"):Connect(place)
		crest:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
		header:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	end
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
	buttons.ZIndex = 2 -- above Main when Main runs to the bottom (SetMainToBottom, 2026-11-17)
	buttons.Parent = backdrop

	local f: any = { Main = main, Side = side, Buttons = buttons, Title = title, rows = 1, mainToBottom = false }

	function f.Layout()
		local buttonRows = f.rows
		local insetY = GuiService:GetGuiInset().Y
		local headerH = math.max(MIN_HEADER_H, insetY)
		-- Title starts right of Roblox's own top-left buttons (they always draw on top).
		local leftX = math.max(MARGIN * 2, GuiService.TopbarInset.Min.X + MARGIN
			+ (if GuiService.TopbarInset.Min.X > 0 then Theme.TopbarReserve else 0)) -- Feedback button slot (2026-11-17)
		local headerY = 0
		header.Position = UDim2.fromOffset(leftX, headerY)
		header.Size = UDim2.new(1, -(leftX + MARGIN * 2), 0, headerH)
		local top = headerY + headerH + MARGIN // 2
		if framed then
			-- Same box as the guild base header (GuildMenu fitHeaderToTopbar, user 2026-11-17 11:39 AM):
			-- 12% of the screen high at 2% from the top, right of Roblox's buttons; panels start at 16%.
			-- User 2026-11-17 12:00 PM: the header runs down to the top of the main frame (no gap) and
			-- its right edge lines up with the main frame's right edge (screen width - MARGIN).
			local tlx = GuiService.TopbarInset.Min.X
			if tlx > 0 then tlx += Theme.TopbarReserve end -- Feedback button slot (2026-11-17)
			local bh = backdrop.AbsoluteSize.Y
			local hy = if bh > 0 then math.floor(bh * 0.02 + 0.5) else 0
			if bh > 0 then top = math.floor(bh * 0.16 + 0.5) end
			local hh = math.max(MIN_HEADER_H, top - hy)
			if tlx > 0 then
				header.Position = UDim2.new(0, tlx + 8, 0, hy)
				header.Size = UDim2.new(1, -(tlx + 8 + MARGIN), 0, hh)
			else
				header.Position = UDim2.new(0.02, 0, 0, hy)
				header.Size = UDim2.new(0.98, -MARGIN, 0, hh)
			end
			top = hy + hh
		end
		local buttonsH = buttonRows * GuildScreen.ROW_H + (buttonRows - 1) * ROW_GAP
		mainPanel.Position = UDim2.fromOffset(MARGIN, top)
		mainPanel.Size = UDim2.new(1 - SIDE_SHARE, -MARGIN * 1.5, 1, -(top + MARGIN))
		sidePanel.Position = UDim2.new(1 - SIDE_SHARE, MARGIN // 2, 0, top)
		sidePanel.Size = UDim2.new(SIDE_SHARE, -MARGIN * 1.5, 1, -(top + MARGIN * 2 + buttonsH))
		buttons.Position = UDim2.new(1, -MARGIN, 1, -MARGIN)
		buttons.Size = UDim2.new(SIDE_SHARE, -MARGIN * 1.5, 0, buttonsH)
		if fullMain then
			mainPanel.Size = UDim2.new(1, -MARGIN * 2, 1, -(top + MARGIN * 2 + buttonsH))
			-- Dungeon map (user 2026-11-17 11:22 AM): Main runs down to the button row's bottom edge;
			-- the buttons sit over its lower right (the caller keeps that corner free).
			if f.mainToBottom then
				mainPanel.Size = UDim2.new(1, -MARGIN * 2, 1, -(top + MARGIN))
				-- User 2026-11-17 12:00 PM: buttons sit inside the frame, ~2 px clear of its edge line.
				buttons.Position = UDim2.new(1, -(MARGIN + FRAME_EDGE + 2), 1, -(MARGIN + FRAME_EDGE + 2))
			end
			sidePanel.Visible = false
		end
	end

	if framed then -- plain gold text (fallback until the numbers arrive) on the right half
		gold.Size = UDim2.new(0.5, 0, 1, 0)
		gold.Position = UDim2.new(0.5, 0, 0, 0)
	end

	function f.SetGold(text: string)
		gold.Text = text
	end

	-- Icon + number currencies in the gold slot (dungeon header, user 2026-11-17), the guild home
	-- look. list = { { key, text } } in display order (key = Theme.GuildIcons name; a key without
	-- art shows its text only); bottom = keys for the second row when one row does not fit.
	-- nil restores the plain gold text. The strip takes the right 45%; status keeps the middle.
	local stripKeys = ""
	function f.SetCurrencies(list: { { any } }?, bottom: { [string]: boolean }?)
		if not list or not CurrencyStrip then
			if strip then strip.Strip.Visible = false end
			gold.Visible = true
			if not framed then status.Size = UDim2.new(0.4, 0, 1, 0) end
			return
		end
		local keys: { string } = {}
		for _, e in list do table.insert(keys, tostring(e[1])) end
		local sig = table.concat(keys, ",")
		if not strip or sig ~= stripKeys then
			if strip then strip.Strip:Destroy() end
			-- Framed header: the guild base strip exactly (right 60%, user 2026-11-17 11:39 AM); plain: right 45%.
			local share = if framed then 0.6 else 0.45
			strip = CurrencyStrip.Create(header, { keys = keys, bottomKeys = bottom,
				size = UDim2.fromScale(share, 1), position = UDim2.fromScale(1 - share, 0), name = "Currencies" })
			stripKeys = sig
			if framed and strip.OnContentChanged then strip.OnContentChanged(placeText) end
		end
		for _, e in list do strip.Set(tostring(e[1]), tostring(e[2])) end
		strip.Strip.Visible = true
		gold.Visible = false
		if not framed then status.Size = UDim2.new(0.25, 0, 1, 0) end
		if framed then placeText() end
	end

	-- Framed header only: the two-line details block right of the title (nil / "" hides a line).
	function f.SetDetails(line1: string?, line2: string?)
		if not details then return end
		detailLines[1].Text = line1 or ""
		detailLines[2].Text = line2 or ""
		details.Visible = (line1 or "") ~= "" or (line2 or "") ~= ""
	end

	-- Server answers / errors (moved here from the guild menu status line while this is open).
	function f.SetStatus(text: string, isError: boolean?)
		status.Text = text
		status.TextColor3 = if isError then Theme.Colors.Danger else Theme.Colors.Success
	end

	-- Framed header is sized in screen %, so re-place it when the screen size changes.
	if framed then backdrop:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() f.Layout() end) end
	return f
end

--------------------------------------------------
-- PUBLIC
--------------------------------------------------

-- Button row height for callers sizing their rows (44 px touch minimum, loadout_ui_spec 73).
GuildScreen.ROW_H = Theme.MinSize.TouchTarget
GuildScreen.ROW_GAP = ROW_GAP

-- opts: name (ScreenGui name), title, parent (PlayerGui).
-- Returns a screen table: Gui, Main, Side, Buttons, and the methods below.
-- opts.fullMain (2026-11-13, Units screen): Main spans the full width above the Buttons row and
-- the Side panel is hidden (screens with nothing to inspect).
-- opts.crest (2026-11-17): gold-framed header like the guild base (crest, title, status, details, currencies).
function GuildScreen.Create(opts: { name: string, title: string, parent: Instance, fullMain: boolean?, crest: string? }): any
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

	-- Header, ornate Main / Side panels and the Buttons group (shared with CreateView).
	local f = buildFrame(backdrop, opts.title, opts.fullMain, if opts.crest then { crest = opts.crest } else nil)
	local main, side, buttons = f.Main, f.Side, f.Buttons

	Theme.MakeScreenBorder(backdrop)

	local self: any = {
		Gui = gui,
		Main = main,
		Side = side,
		Buttons = buttons,
	}

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
		f.Layout()
	end

	-- Number of button rows the caller will build (sizes the Buttons group and Side panel).
	function self.SetButtonRows(n: number)
		f.rows = math.max(1, n)
		layout()
	end

	self.SetGold = f.SetGold
	self.SetCurrencies = f.SetCurrencies
	self.SetDetails = f.SetDetails
	-- Header title text (dungeon: the chosen biome, user 2026-11-17 11:22 AM).
	function self.SetTitle(text: string) f.Title.Text = text end
	-- fullMain screens: Main down to the bottom edge, buttons over its lower right (dungeon map).
	function self.SetMainToBottom(on: boolean)
		if f.mainToBottom == on then return end
		f.mainToBottom = on
		layout()
	end
	-- Server answers / errors (moved here from the guild menu status line while this is open).
	self.SetStatus = f.SetStatus

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

	function self.Prompt(message: string, confirmText: string, confirmStyle: string, onConfirm: () -> (), cancelText: string?)
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

		-- Ornate gold panel frame like every other panel (user 2026-11-17 10:06 AM).
		local box = Theme.MakePanel("Box", UDim2.fromOffset(PROMPT_W, PROMPT_H), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), nil)

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
		-- 2026-11-18 user: confirmations use the shared icon pair (Back = cancel, check = confirm),
		-- like Loadout and the dungeon Bag popups. confirmText / cancelText stay as the buttons'
		-- accessibility names only; the message itself says what the check does.
		local iconSize = UDim2.fromOffset(GuildScreen.ROW_H, GuildScreen.ROW_H)
		local cancelBtn = Theme.MakeIconButton(row, "Back", function()
			self.ClosePrompt()
		end, { name = "Btn_PromptCancel", size = iconSize })
		cancelBtn.LayoutOrder = 1
		cancelBtn:SetAttribute("Label", cancelText or "Cancel")
		local okBtn = Theme.MakeIconButton(row, "Confirm", function()
			self.ClosePrompt()
			onConfirm()
		end, { name = "Btn_PromptConfirm", size = iconSize, disabled = confirmStyle == "Disabled",
			tint = if confirmStyle == "Tertiary" or confirmStyle == "Danger" then Theme.DestructiveIconTint else nil })
		okBtn.LayoutOrder = 2
		okBtn:SetAttribute("Label", confirmText)
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

--------------------------------------------------
-- VIEWS AND MODAL BOXES INSIDE AN OPEN SCREEN (2026-11-17, user: the dungeon screens did not
-- follow the established style -- plain dark boxes, title under the Roblox top bar)
--------------------------------------------------

local CLEAR = 12 -- modal box gap to the screen edges and below the Roblox top bar (12-24 px rule)

-- Modal layer that swallows taps; child of a ScreenGui with IgnoreGuiInset = true (any GuildScreen).
local function makeModal(name: string, color: Color3, transparency: number): TextButton
	local o = Instance.new("TextButton")
	o.Name = name
	o.Text = ""
	o.AutoButtonColor = false
	o.Modal = true
	o.Size = UDim2.fromScale(1, 1)
	o.BackgroundColor3 = color
	o.BackgroundTransparency = transparency
	o.BorderSizePixel = 0
	o.ZIndex = 20
	return o
end

-- A full screen drawn over an open GuildScreen (dungeon Bag / Merchant / Treasure): the same
-- header (title | status | gold), ornate Main + Side panels and lower-right Buttons as Create.
-- The caller parents view.Root (then fills Main / Side / Buttons) and destroys Root to close.
function GuildScreen.CreateView(opts: { name: string, title: string, fullMain: boolean?, buttonRows: number? }): any
	local root = makeModal(opts.name, Theme.FullScreen.BackgroundColor, Theme.FullScreen.BackgroundTransparency)
	local f = buildFrame(root, opts.title, opts.fullMain)
	Theme.MakeScreenBorder(root)
	f.Root = root
	f.rows = math.max(1, opts.buttonRows or 1)
	function f.SetTitle(text: string)
		f.Title.Text = text
	end
	f.Layout()
	return f
end

-- Dimmed modal with one box in the guild popup style (the Prompt / FacilityInfo box: raised
-- panel, rounded corners, border line), kept clear of the screen edges and below the Roblox top
-- bar. opts.fill: fixed box using the whole safe height (widthScale of the width, up to maxW px);
-- otherwise the box grows with its content (AutomaticSize Y) up to the safe height.
-- Returns the overlay (caller parents it last) and the box (padded) to fill.
function GuildScreen.MakeModalBox(name: string, opts: { maxW: number?, widthScale: number?, fill: boolean?, pad: number? }?): (TextButton, any)
	local o2 = opts or {}
	local insetY = GuiService:GetGuiInset().Y
	local cam = workspace.CurrentCamera
	local vh = if cam then cam.ViewportSize.Y else 382
	local maxH = math.max(120, vh - insetY - CLEAR * 2)
	local overlay = makeModal(name, Color3.new(0, 0, 0), 0.4)
	-- Ornate gold panel frame, the same art as every guild screen panel (user 2026-11-17 10:06 AM:
	-- "use the panel design for ALL screens such as the ? panel"). Theme.MakePanel = the one frame builder.
	local box = Theme.MakePanel("Box", UDim2.new(), UDim2.new(), nil, nil)
	box.ClipsDescendants = true
	box.ZIndex = 21
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(o2.maxW or 500, maxH)
	limit.Parent = box
	if o2.fill then
		box.AnchorPoint = Vector2.new(0.5, 0)
		box.Position = UDim2.new(0.5, 0, 0, insetY + CLEAR)
		box.Size = UDim2.new(o2.widthScale or 0.94, 0, 0, maxH)
	else
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.new(0.5, 0, 0.5, insetY // 2)
		box.Size = UDim2.new(o2.widthScale or 0.86, 0, 0, 0)
		box.AutomaticSize = Enum.AutomaticSize.Y
	end
	addPadding(box, math.max(o2.pad or 12, Theme.PanelFrame.MinPadding + 4)) -- clear the frame's corner ornaments
	box.Parent = overlay
	return overlay, box
end

return table.freeze(GuildScreen)
