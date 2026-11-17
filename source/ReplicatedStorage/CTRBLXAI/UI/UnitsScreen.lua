--!strict
-- UnitsScreen.lua
-- CTRBLXAI | Guild Units full screen (user 2026-11-13 1:41 / 1:42 PM). Its own screen like the
-- Merchant / Dispatch, so the guild nav takes no space. Back returns to the guild menu.
--
-- Layout (GuildScreen, fullMain): one scrolling grid, 3 cards per row side by side.
--   card = [portrait + "Lv.N" badge] [name (2 rows) / race / doctrine] [HP cur/max + bar, MP cur/max + bar]
--   AWAY units: whole card dimmed (bars included) with an AWAY tag.
--   Tap a card = open the Loadout with that unit selected, on the INFO tab (no Loadout button).
--   BOTTOM lower right: [Back]
--
-- Display + input only (ARC-001 / SEC-002): data comes from GetGuildUnits through the opener's
-- cache; a tap only asks the opener to open the Loadout for a unit id. Context is nil-safe.

local WAIT = 10

local uiFolder = script.Parent
local themeModule = uiFolder:WaitForChild("Theme", WAIT)
local guildScreenModule = uiFolder:WaitForChild("GuildScreen", WAIT)
local uiComponentsModule = uiFolder:WaitForChild("UIComponents", WAIT)
if not themeModule or not guildScreenModule then
	error("[UnitsScreen] Theme / GuildScreen module not found")
end
-- Found at runtime via WaitForChild; the editor cannot follow that path (editor-only cast).
local Theme: any = (require :: any)(themeModule)
local GuildScreen: any = (require :: any)(guildScreenModule)
local UIComponents: any = if uiComponentsModule then (require :: any)(uiComponentsModule) else nil

local UnitsScreen = {}

export type Context = {
	parent: Instance,                         -- PlayerGui
	getUnits: () -> any?,                     -- GetGuildUnits answer (cached by the opener)
	openUnit: (unitId: string) -> (),         -- open the Loadout on INFO for this unit
	requestBack: (close: () -> ()) -> (),     -- Confirm/Discard prompt, then close
	onClosed: () -> (),                       -- opener re-shows itself
	setStatus: (text: string, isError: boolean?) -> (),
}

local COLS = 3
local GAP = 4
local DIM = 0.5 -- same dim as the Dispatch / Merchant tiles

local ctx: Context? = nil
local screen: any = nil
local isOpen = false
local render: () -> () = function() end

--------------------------------------------------
-- HELPERS (properties before Parent, NET-004)
--------------------------------------------------

local function makeText(parent: Instance?, text: string, size: number, color: Color3, bold: boolean?): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.BorderSizePixel = 0
	lbl.Font = if bold then Theme.Font.PrimaryBold else Theme.Font.Primary
	lbl.TextSize = size
	lbl.TextColor3 = color
	lbl.TextWrapped = false
	lbl.TextTruncate = Enum.TextTruncate.AtEnd
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.Text = text
	lbl.ZIndex = 2
	-- Long words ("Elementalist", 4-digit HP) shrink to fit, never below the 10 px phone floor.
	lbl.TextScaled = true
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = size
	fit.MinTextSize = math.min(size, 10)
	fit.Parent = lbl
	lbl.Parent = parent
	return lbl
end

local function cardHeight(): number
	return math.max(58, Theme.Text.Small() * 4 + 12) -- 2 name rows + race + doctrine
end

local function bar(parent: Instance, y: number, key: string, cur: number?, max: number?, color: Color3, ts: number)
	local c, m = cur or 0, max or 0
	local t = makeText(parent, `{key} {c}/{m}`, ts, Theme.Colors.TextPrimary)
	t.Font = Theme.Font.Mono
	t.Size = UDim2.new(1, 0, 0, ts + 2)
	t.Position = UDim2.fromOffset(0, y)
	local bg = Instance.new("Frame")
	bg.Name = key .. "Bar"
	bg.Size = UDim2.new(1, 0, 0, 5)
	bg.Position = UDim2.fromOffset(0, y + ts + 3)
	bg.BackgroundColor3 = Theme.Colors.EmptySlot
	bg.BorderSizePixel = 0
	bg.ZIndex = 2
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = color
	fill.Size = UDim2.fromScale(if m > 0 then math.clamp(c / m, 0, 1) else 0, 1)
	fill.ZIndex = 2
	fill.Parent = bg
	bg.Parent = parent
end

local function makeCard(grid: Instance, u: any, order: number)
	local h = cardHeight()
	local ps = h - 8
	local ts = Theme.Text.Small()
	local card = Instance.new("TextButton")
	card.Name = "Card_" .. tostring(u.id)
	card.Text = ""
	card.AutoButtonColor = false -- no hover colour change (user rule)
	card.BackgroundColor3 = Theme.Colors.Surface
	card.BackgroundTransparency = 0.2
	card.BorderSizePixel = 0
	card.LayoutOrder = order
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius.sm
	corner.Parent = card

	-- Portrait + level badge (top-left, like the Loadout header portrait).
	local face = Instance.new("Frame")
	face.Name = "Portrait"
	face.Size = UDim2.fromOffset(ps, ps)
	face.Position = UDim2.fromOffset(4, 4)
	face.BackgroundColor3 = Theme.Colors.Player
	face.BackgroundTransparency = 0.2
	face.BorderSizePixel = 0
	face.ZIndex = 1
	local fc = Instance.new("UICorner")
	fc.CornerRadius = Theme.CornerRadius.sm
	fc.Parent = face
	local ini = makeText(face, string.sub(tostring(u.name or "?"), 1, 2), ts, Theme.Colors.TextPrimary, true)
	ini.Size = UDim2.fromScale(1, 1)
	ini.TextXAlignment = Enum.TextXAlignment.Center
	if UIComponents then UIComponents.ApplyPortrait(face, u.portraitAssetId, ini) end
	local lvText = "Lv." .. tostring(u.unitLevel or "?")
	local badge = makeText(face, lvText, math.max(10, Theme.Text.Tiny()), Theme.Colors.TextPrimary) -- 10 px phone floor
	badge.Name = "LevelBadge"
	badge.Font = Theme.Font.Mono
	badge.BackgroundColor3 = Color3.new(0, 0, 0)
	badge.BackgroundTransparency = 0.3
	badge.TextTruncate = Enum.TextTruncate.None
	badge.Size = UDim2.fromOffset(Theme.BadgeFitW and Theme.BadgeFitW(lvText, Theme.Font.Mono, 26) or 30, math.max(10, Theme.Text.Tiny()) + 3)
	badge.ZIndex = 4 -- above the portrait image (face.ZIndex + 1)
	face.Parent = card

	-- Name (up to 2 rows), race, doctrine.
	local left = ps + 10
	local info = Instance.new("Frame")
	info.Name = "Info"
	info.BackgroundTransparency = 1
	info.Position = UDim2.fromOffset(left, 4)
	info.Size = UDim2.new(0.5, -(left // 2 + 4), 1, -8) -- text and stats share the space right of the portrait
	-- Name only (spec: name, race, doctrine); no "(hired)" tag.
	local nameLbl = makeText(info, tostring(u.name or "?"), ts, Theme.Colors.TextGold, true)
	nameLbl.Name = "Name"
	nameLbl.TextWrapped = true
	nameLbl.TextYAlignment = Enum.TextYAlignment.Top
	nameLbl.Size = UDim2.new(1, 0, 0, ts * 2 + 2)
	local race = makeText(info, tostring(u.race or "?"), ts, Theme.Colors.TextSecondary)
	race.Name = "Race"
	race.Size = UDim2.new(1, 0, 0, ts + 2)
	race.Position = UDim2.fromOffset(0, ts * 2 + 3)
	local doc = makeText(info, tostring(u.doctrine or "?"), ts, Theme.Colors.TextSecondary)
	doc.Name = "Doctrine"
	doc.Size = UDim2.new(1, 0, 0, ts + 2)
	doc.Position = UDim2.fromOffset(0, ts * 3 + 5)
	info.Parent = card

	-- HP / MP values and bars (right part of the card).
	local stats = Instance.new("Frame")
	stats.Name = "Stats"
	stats.BackgroundTransparency = 1
	stats.AnchorPoint = Vector2.new(1, 0.5)
	stats.Position = UDim2.new(1, -6, 0.5, 0)
	stats.Size = UDim2.new(0.5, -(left // 2 + 8), 0, (ts + 9) * 2 + 4)
	bar(stats, 0, "HP", u.hp, u.maxHp, Theme.Colors.HP, ts)
	bar(stats, ts + 13, "MP", u.mp, u.maxMp, Theme.Colors.MP, ts)
	stats.Parent = card

	if u.away then
		local dim = Instance.new("Frame")
		dim.Name = "Dim"
		dim.Size = UDim2.fromScale(1, 1)
		dim.BackgroundColor3 = Color3.new(0, 0, 0)
		dim.BackgroundTransparency = DIM
		dim.BorderSizePixel = 0
		dim.Active = false
		dim.ZIndex = 5
		local dc = Instance.new("UICorner")
		dc.CornerRadius = Theme.CornerRadius.sm
		dc.Parent = dim
		-- Dungeon units: approved "Exploring a dungeon" (2026-11-13 8:24 PM); dispatched keep AWAY.
		local tag = makeText(dim, if u.awayReason == "dungeon" then "Exploring a dungeon" else "AWAY", Theme.Text.Small(), Theme.Colors.TextPrimary, true)
		tag.TextXAlignment = Enum.TextXAlignment.Right
		tag.TextYAlignment = Enum.TextYAlignment.Bottom
		tag.Size = UDim2.new(1, -6, 1, -3)
		tag.ZIndex = 6
		dim.Parent = card
	end

	local uid = u.id
	card.Activated:Connect(function()
		local c = ctx
		if c and uid then c.openUnit(uid) end
	end)
	card.Parent = grid
end

local function buildGrid(res: any)
	local main = screen.Main
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid" -- GuildScreen keeps the scroll position for a frame named Grid
	grid.Size = UDim2.fromScale(1, 1)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 4
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	local layout = Instance.new("UIGridLayout")
	-- Scale width: 3 per row on any screen; the 6 px leaves room for the scrollbar.
	layout.CellSize = UDim2.new(1 / COLS, -(GAP * (COLS - 1) + 6) / COLS, 0, cardHeight())
	layout.CellPadding = UDim2.fromOffset(GAP, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for i, u in res.units or {} do
		makeCard(grid, u, i)
	end
	grid.Parent = main
end

local function buildButtons()
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
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	local b = Theme.MakeIconButton(nil, "Back", function()
		c.requestBack(UnitsScreen.Close)
	end, { name = "Btn_BACK", size = UDim2.fromOffset(GuildScreen.ROW_H, GuildScreen.ROW_H) })
	b.LayoutOrder = 1
	b.Parent = row
	row.Parent = screen.Buttons
end

render = function()
	local c = ctx
	if not c or not screen or not isOpen then return end
	screen.Clear("Units")
	local res = c.getUnits() -- nil on a server error (shown in the status line)
	if res then buildGrid(res) end
	buildButtons()
end

--------------------------------------------------
-- PUBLIC (same shape as the other guild screens)
--------------------------------------------------

function UnitsScreen.Init(c: Context)
	ctx = c
end

function UnitsScreen.IsOpen(): boolean
	return isOpen
end

function UnitsScreen.GetGui(): ScreenGui?
	return if isOpen and screen then screen.Gui else nil
end

function UnitsScreen.Open()
	local c = ctx
	if not c then
		warn("[UnitsScreen] Open called before Init")
		return
	end
	if not screen then
		screen = GuildScreen.Create({ name = "UnitsScreen", title = "UNITS", parent = c.parent, fullMain = true })
		screen.SetButtonRows(1)
	end
	isOpen = true
	screen.SetStatus("")
	screen.Show()
	render()
end

-- Back path: hide and hand control back to the opener.
function UnitsScreen.Close()
	if not isOpen then return end
	isOpen = false
	if screen then screen.ClosePrompt(); screen.Hide() end
	local c = ctx
	if c then c.onClosed() end
end

-- Forced hide (menu closed by the server, or the Loadout opens on top): no onClosed.
function UnitsScreen.Hide()
	if not isOpen then return end
	isOpen = false
	if screen then screen.ClosePrompt(); screen.Hide() end
end

function UnitsScreen.Render()
	render()
end

function UnitsScreen.SetGold(text: string)
	if screen then screen.SetGold(text) end
end

function UnitsScreen.SetStatus(text: string, isError: boolean?)
	if screen then screen.SetStatus(text, isError) end
end


return table.freeze(UnitsScreen)
