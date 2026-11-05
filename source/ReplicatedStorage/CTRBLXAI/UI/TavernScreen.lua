--!strict
-- TavernScreen.lua
-- CTRBLXAI | Tavern full screen (2026-10-31, user ruling: same design as the Merchant). Its own
-- screen like the Loadout; opened from the guild menu today, by the Tavern NPC later. Back
-- returns to whatever opened it.
--
-- Layout (GuildScreen):
--   LEFT   recruit tiles (portrait, level badge, fee badge, name; border = quality)
--   RIGHT  recruit inspector: name, quality + level, fee, then what matters in a recruit
--          (user ruling 2026-10-31): race + race passive, personal perk + flaw (permanent),
--          equipped doctrine + its passive, and primary stats
--   BOTTOM ONE row of square icons, lower right:  [+/-] [check] [X] [Back]
--          check and X open a prompt that needs a second confirmation
--
-- Display + input only (ARC-001 / SEC-002): the recruit preview comes from the server
-- (GuildMenuService previewRecruit, same roll as the hire). Pending hires are owned by the
-- opener (guild menu basket) through the injected context; only candidate ids reach the
-- server on Confirm. Context is nil-safe (ARC-006).

local WAIT = 10

local uiFolder = script.Parent
local themeModule = uiFolder:WaitForChild("Theme", WAIT)
local guildScreenModule = uiFolder:WaitForChild("GuildScreen", WAIT)
local inspectorModule = uiFolder:WaitForChild("MerchantInspector", WAIT)
if not themeModule or not guildScreenModule or not inspectorModule then
	error("[TavernScreen] Theme / GuildScreen / MerchantInspector module not found")
end
-- Found at runtime via WaitForChild; the editor cannot follow that path (editor-only cast).
local Theme: any = (require :: any)(themeModule)
local GuildScreen: any = (require :: any)(guildScreenModule)
-- The tile grid is shared with the Merchant (same tile look, badges and dimming).
local TileGrid: any = (require :: any)(inspectorModule)

local TavernScreen = {}

--------------------------------------------------
-- TYPES / STATE
--------------------------------------------------

export type Context = {
	parent: Instance,                                   -- PlayerGui
	getPool: () -> any?,                                -- GetTavernPool answer (cached)
	isQueued: (key: string) -> boolean,
	toggle: (key: string, name: string, price: number?) -> (),
	pendingCount: () -> number,
	summary: () -> any,                                 -- { nHire, hireGold }
	confirm: () -> (),
	discard: () -> (),
	requestBack: (close: () -> ()) -> (),
	onClosed: () -> (),
}

local BUTTON_ROWS = 1
local STAT_ROW_H = 18
local PRIMARY_STATS = { "STR", "AGI", "INT", "VIT", "DEX", "LUK" }
-- Quality shown with the existing rarity colours (Standard grey, Quality green, Elite blue).
local QUALITY_RARITY: { [string]: string } = { Standard = "Common", Quality = "Uncommon", Elite = "Rare" }

local ctx: Context? = nil
local screen: any = nil
local isOpen = false
local selectedKey: string? = nil

--------------------------------------------------
-- BUILDERS (properties before Parent, NET-004)
--------------------------------------------------

local function makeText(parent: Instance, text: string, size: number, color: Color3, bold: boolean?): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.BorderSizePixel = 0
	lbl.Font = if bold then Theme.Font.PrimaryBold else Theme.Font.Primary
	lbl.TextSize = size
	lbl.TextColor3 = color
	lbl.TextWrapped = true
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.Text = text
	lbl.Parent = parent
	return lbl
end

local function addLine(list: Instance, order: number, text: string, size: number, color: Color3, bold: boolean?)
	local lbl = makeText(list, text, size, color, bold)
	lbl.Size = UDim2.new(1, 0, 0, 0)
	lbl.AutomaticSize = Enum.AutomaticSize.Y
	lbl.LayoutOrder = order
end

local function addStatRow(list: Instance, order: number, label: string, value: string)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, STAT_ROW_H)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	local l = makeText(row, label, Theme.Text.Body(), Theme.Colors.TextSecondary)
	l.Size = UDim2.new(0.6, 0, 1, 0)
	local v = makeText(row, value, Theme.Text.Body(), Theme.Colors.TextPrimary, true)
	v.Size = UDim2.new(0.4, 0, 1, 0)
	v.Position = UDim2.new(0.6, 0, 0, 0)
	v.TextXAlignment = Enum.TextXAlignment.Right
	row.Parent = list
end

local function makeNote(parent: Instance, text: string, order: number)
	local lbl = makeText(parent, text, Theme.Text.Small(), Theme.Colors.TextSecondary)
	lbl.Size = UDim2.new(1, 0, 0, 0)
	lbl.AutomaticSize = Enum.AutomaticSize.Y
	lbl.LayoutOrder = order
end

local function iconButton(row: Instance, kind: string, name: string, order: number, enabled: boolean, onTap: () -> ())
	local b = Theme.MakeIconButton(nil, kind, if enabled then onTap else nil, {
		name = name,
		size = UDim2.fromOffset(GuildScreen.ROW_H, GuildScreen.ROW_H),
		disabled = not enabled,
	})
	b.LayoutOrder = order
	b.Parent = row
end

local function asImage(id: any): string?
	if type(id) == "number" then return `rbxassetid://{id}` end
	if type(id) == "string" and id ~= "" then
		return if string.find(id, "rbxassetid://", 1, true) then id else `rbxassetid://{id}`
	end
	return nil
end

local function plural(n: number): string
	return if n == 1 then "recruit" else "recruits"
end

--------------------------------------------------
-- INSPECTOR
--------------------------------------------------

-- Name line (green / red / race / doctrine colour, as the Loadout Info tab) + effect text.
local function addPassive(list: Instance, nextOrder: () -> number, name: string?, effect: string?, color: Color3)
	if not name then return end
	addLine(list, nextOrder(), name, Theme.Text.Body(), color, true)
	if effect and effect ~= "" then
		addLine(list, nextOrder(), effect, Theme.Text.Small(), Theme.Colors.TextPrimary)
	end
end

local function fillRecruit(list: Instance, e: any)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local p = e.preview or {}
	addLine(list, nextOrder(), e.name, Theme.Text.Heading(), Theme.GetRarityColor(e.rarity), true)
	addLine(list, nextOrder(), `{e.quality} | Lv{e.level}`, Theme.Text.Small(), Theme.Colors.TextSecondary)
	if e.price ~= nil then
		addLine(list, nextOrder(), `{e.price} gold`, Theme.Text.Body(), Theme.Colors.TextGold, true)
	end
	if not e.preview then
		warn(`[TavernScreen] No preview for '{e.name}' (server sent none)`)
		return
	end
	-- Race and its passive (permanent)
	addLine(list, nextOrder(), tostring(p.raceName or "?"), Theme.Text.Body(), Theme.Colors.TextPrimary, true)
	addPassive(list, nextOrder, p.racePassiveName, p.racePassiveEffect, Theme.Colors.RarityEpic)
	-- Personal perk + flaw (permanent)
	addPassive(list, nextOrder, p.perkName, p.perkEffect, Theme.Colors.Success)
	addPassive(list, nextOrder, p.flawName, p.flawEffect, Theme.Colors.Danger)
	-- Equipped doctrine and its passive
	addLine(list, nextOrder(), tostring(p.doctrineName or "?"), Theme.Text.Body(), Theme.Colors.TextPrimary, true)
	addPassive(list, nextOrder, p.doctrinePassiveName, p.doctrinePassiveEffect, Theme.Colors.Info)
	-- Primary stats (with the doctrine, perk/flaw and race passive applied, as on hire)
	local stats = p.stats or {}
	for _, key in PRIMARY_STATS do
		local v = stats[key]
		if v ~= nil then addStatRow(list, nextOrder(), key, tostring(v)) end
	end
end

--------------------------------------------------
-- RENDER
--------------------------------------------------

local render: () -> ()

local function buildEntries(res: any): { any }
	local c = ctx
	local entries = {}
	if not c or not res then return entries end
	for _, r in res.pool or {} do
		local p = r.preview or {}
		table.insert(entries, {
			key = r.candidateId,
			name = p.name or "Recruit",
			level = r.level,
			quality = r.quality,
			rarity = QUALITY_RARITY[r.quality] or "Common",
			price = r.cost,
			queued = c.isQueued(r.candidateId),
			preview = r.preview,
			detail = { icon = asImage(p.portraitAssetId) }, -- tile picture
		})
	end
	return entries
end

local function buildMain(res: any, entries: { any }, selected: any?)
	local main = screen.Main
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = main
	-- Existing Tavern notes, kept as on the Merchant.
	if res then
		makeNote(main, `Tavern L{res.tavernLevel or 1}: one recruit per Tavern level. The pool refreshes after each battle. Fee = 200 + 15 x level (+ quality premium).`, 1)
		if #(res.pool or {}) == 0 then
			makeNote(main, if res.reason then tostring(res.reason) else "No recruits left until the next battle.", 2)
		end
	end
	if #entries == 0 then return end
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Size = UDim2.fromScale(1, 0)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 4
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.LayoutOrder = 10
	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = grid
	TileGrid.BuildGrid(grid, {
		entries = entries,
		selectedKey = if selected then selected.key else nil,
		width = math.max(240, main.AbsoluteSize.X - 6),
		onSelect = function(key: any)
			selectedKey = key
			render()
		end,
	})
	grid.Parent = main
end

local function buildSide(selected: any?)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Detail"
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 2)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = scroll
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 3)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = scroll
	if selected then fillRecruit(scroll, selected) end
	scroll.Parent = screen.Side
end

local function promptConfirm()
	local c = ctx
	if not c or not screen then return end
	local s = c.summary()
	screen.Prompt(`Hire {s.nHire} {plural(s.nHire)}: -{s.hireGold} gold`, "Confirm", "Primary", function()
		c.confirm()
		render()
	end)
end

local function promptDiscard()
	local c = ctx
	if not c or not screen then return end
	local s = c.summary()
	local detail = if s.nHire > 0 then ` (hire {s.nHire})` else ""
	screen.Prompt(`Discard all pending changes{detail}?`, "Discard", "Tertiary", function()
		c.discard()
		render()
	end)
end

local function buildButtons(selected: any?)
	local c = ctx
	if not c then return end
	local row = Instance.new("Frame")
	row.Name = "Row1"
	row.Size = UDim2.new(1, 0, 0, GuildScreen.ROW_H)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, GuildScreen.ROW_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	local hasPending = c.pendingCount() > 0
	local isQueued = selected ~= nil and selected.queued
	local canToggle = selected ~= nil and (selected.queued or selected.price ~= nil)
	iconButton(row, if isQueued then "Minus" else "Plus", "Btn_Toggle", 1, canToggle, function()
		if not selected then return end
		selectedKey = selected.key
		c.toggle(selected.key, selected.name, selected.price)
		render()
	end)
	iconButton(row, "Confirm", "Btn_ConfirmAll", 2, hasPending, promptConfirm)
	iconButton(row, "X", "Btn_DiscardAll", 3, hasPending, promptDiscard)
	iconButton(row, "Back", "Btn_BACK", 4, true, function()
		c.requestBack(TavernScreen.Close)
	end)
	row.Parent = screen.Buttons
end

render = function()
	local c = ctx
	if not c or not screen or not isOpen then return end
	screen.Clear()
	local res = c.getPool() -- nil on a server error (shown in the status line)
	local entries = buildEntries(res)
	local selected = TileGrid.ResolveSelected(entries, selectedKey)
	buildMain(res, entries, selected)
	buildSide(selected)
	buildButtons(selected)
end

--------------------------------------------------
-- PUBLIC (same shape as MerchantScreen)
--------------------------------------------------

function TavernScreen.Init(c: Context)
	ctx = c
end

function TavernScreen.IsOpen(): boolean
	return isOpen
end

function TavernScreen.GetGui(): ScreenGui?
	return if isOpen and screen then screen.Gui else nil
end

function TavernScreen.Open()
	local c = ctx
	if not c then
		warn("[TavernScreen] Open called before Init")
		return
	end
	if not screen then
		screen = GuildScreen.Create({ name = "TavernScreen", title = "TAVERN", parent = c.parent })
		screen.SetButtonRows(BUTTON_ROWS)
	end
	isOpen = true
	screen.SetStatus("")
	screen.Show()
	render()
	print("[TavernScreen] Opened")
end

function TavernScreen.Close()
	if not isOpen then return end
	isOpen = false
	if screen then screen.Hide() end
	local c = ctx
	if c then c.onClosed() end
	print("[TavernScreen] Closed")
end

function TavernScreen.Hide()
	if not isOpen then return end
	isOpen = false
	if screen then screen.Hide() end
end

function TavernScreen.Render()
	render()
end

function TavernScreen.SetGold(text: string)
	if screen then screen.SetGold(text) end
end

function TavernScreen.SetStatus(text: string, isError: boolean?)
	if screen then screen.SetStatus(text, isError) end
end

return table.freeze(TavernScreen)
