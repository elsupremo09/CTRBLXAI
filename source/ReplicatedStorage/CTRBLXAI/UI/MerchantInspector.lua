--!strict
-- MerchantInspector.lua
-- CTRBLXAI | Merchant tile grid + item inspector builders, used by MerchantScreen
-- (2026-10-31, user decision: merchant-only inspector first; a shared item inspector for
-- Loadout + Merchant + Blacksmith is a later task). No buttons are built here: every button
-- sits in the screen's single lower-right icon row (MerchantScreen / GuildScreen).
--
-- Display only (ARC-001 / SEC-002): renders the server's item detail table
-- (ItemDisplay.buildItemEntry, sent by GuildMenuService) and reports taps back to the
-- caller. It never computes a price or a stat. BP is never shown (loadout_ui_spec 28).
-- Tiles: Theme.MakeItemTile (shared tile look, loadout_ui_spec 26/27). Tap-only (id 73).
-- Labels reuse the Loadout detail view's existing wording; the price line is the only
-- addition (user ruling 2026-10-31); no other helper text (id 82).

local WAIT = 10

local themeModule = script.Parent:WaitForChild("Theme", WAIT)
if not themeModule then
	error("[MerchantInspector] Theme module not found")
end
-- Found at runtime via WaitForChild; the editor cannot follow that path (editor-only cast).
local Theme: any = (require :: any)(themeModule)
-- Loadout tiles (Runeforge, 2026-11-08): the Loadout's own grid spacing and level label.
local controlsModule = script.Parent:WaitForChild("InventoryControls", WAIT)
local InventoryControls: any = if controlsModule then (require :: any)(controlsModule) else nil

local MerchantInspector = {}

--------------------------------------------------
-- TYPES / CONSTANTS
--------------------------------------------------

export type Entry = {
	key: any,           -- offerIndex (Buy) or instanceId (Sell); passed back on tap
	detail: any?,       -- ItemDisplay.buildItemEntry() table from the server
	name: string,
	level: number?,
	rarity: string?,
	price: number?,     -- nil = not sellable (+ button faded)
	queued: boolean,    -- already pending (dimmed tile; the screen shows - instead of +)
	-- Loadout tiles only (Runeforge, 2026-11-08): the Loadout "E" / NEW markers. equippedBy = the
	-- holder's name (server data); there is no selected unit here, so E is the grey "another unit" E.
	equippedBy: string?,
	isNew: boolean?,
}

export type GridOptions = {
	entries: { Entry },
	selectedKey: any?,
	width: number,      -- px width of the grid area (drives tile size)
	onSelect: (key: any) -> (),
	-- 2026-11-07 (Runeforge): true = Loadout-size tiles (Theme.ItemTileCell from the grid's
	-- real height, kept up to date if it changes). nil/false = the merchant sizing below.
	-- 2026-11-08: also the Loadout grid itself (no inner padding, its cell spacing, its grey
	-- "Lv.N" label instead of the merchant level badge; user: "the Loadout is our model").
	loadoutTiles: boolean?,
	heightHint: number?, -- px grid height to use until the real height is known
}

local GRID_GAP = 4
local MIN_CELL = 56           -- >= 44 px touch target with room for the name strip
local STAT_ROW_H = 18
local QUEUED_DIM = 0.5        -- overlay transparency for pending tiles ("dim only", user 2026-10-31)

-- Same split and order as the Loadout detail view: weapon stats for weapons only; every
-- other item (armor, accessory, off-hand/shield) shows Defense, HP, MP, WT (review fix).
local WEAPON_STATS = {
	{ label = "Attack", field = "damage" },
	{ label = "Range", field = "range" },
	{ label = "Defense", field = "defense" },
	{ label = "WT", field = "wt" },
	{ label = "RT Delay", field = "rtDelay" },
}
local OTHER_STATS = {
	{ label = "Defense", field = "defense" },
	{ label = "HP", field = "hp" },
	{ label = "MP", field = "mp" },
	{ label = "WT", field = "wt" },
}

-- Player-facing slot names (raw ids like "MainHand" are internal).
local SLOT_LABEL: { [string]: string } = {
	MainHand = "Main Hand",
	OffHand = "Off-Hand",
}

--------------------------------------------------
-- SMALL BUILDERS (properties before Parent, NET-004)
--------------------------------------------------

local function makeLabel(parent: Instance, text: string, size: number, color: Color3, bold: boolean?): TextLabel
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

-- Full-width wrapped line in a vertical list (height follows the text).
local function addLine(list: Instance, order: number, text: string, size: number, color: Color3, bold: boolean?)
	local lbl = makeLabel(list, text, size, color, bold)
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
	local l = makeLabel(row, label, Theme.Text.Body(), Theme.Colors.TextSecondary)
	l.Size = UDim2.new(0.6, 0, 1, 0)
	local v = makeLabel(row, value, Theme.Text.Body(), Theme.Colors.TextPrimary, true)
	v.Size = UDim2.new(0.4, 0, 1, 0)
	v.Position = UDim2.new(0.6, 0, 0, 0)
	v.TextXAlignment = Enum.TextXAlignment.Right
	row.Parent = list
end

-- Small corner badge on a tile (level top-left, price top-right).
local function addTileBadge(tile: Instance, text: string, rightSide: boolean)
	local t = Theme.ItemTile
	local badge = Instance.new("TextLabel")
	badge.AutomaticSize = Enum.AutomaticSize.X
	badge.Size = UDim2.new(0, 0, 0, t.CountBadgeH + 2)
	badge.AnchorPoint = if rightSide then Vector2.new(1, 0) else Vector2.new(0, 0)
	badge.Position = if rightSide then UDim2.new(1, -2, 0, 2) else UDim2.new(0, 2, 0, 2)
	badge.BackgroundColor3 = t.CountBadgeBg
	badge.BackgroundTransparency = t.CountBadgeBgTransparency
	badge.BorderSizePixel = 0
	badge.Font = Theme.Font.Mono
	badge.TextSize = Theme.Text.Badge()
	badge.TextColor3 = Theme.Colors.TextPrimary
	badge.Text = text
	badge.ZIndex = 4
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 3)
	pad.PaddingRight = UDim.new(0, 3)
	pad.Parent = badge
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 3)
	corner.Parent = badge
	badge.Parent = tile
end

-- Pending tile: dimmed only, no text (user decision 2026-10-31). Non-Active Frame, so taps
-- still reach the tile button underneath.
local function addDimOverlay(tile: Instance)
	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = QUEUED_DIM
	dim.BorderSizePixel = 0
	dim.Active = false
	dim.ZIndex = 5
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.ItemTile.CornerRadius)
	corner.Parent = dim
	dim.Parent = tile
end

--------------------------------------------------
-- INSPECTOR CONTENT
--------------------------------------------------

local function statValue(detail: any, field: string): string?
	if field == "range" then
		local lo = detail.minRange
		local hi = detail.maxRange
		if hi == nil then return nil end
		return `{lo or hi}-{hi}` -- always min-max, as the Loadout detail ("1-1")
	end
	local v = detail[field]
	if v == nil then return nil end
	return tostring(v)
end

local function fillInspector(list: Instance, entry: Entry)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local detail = entry.detail
	local rarity = entry.rarity or (detail and detail.rarity) or "Common"
	local rarityColor = Theme.GetRarityColor(rarity)

	addLine(list, nextOrder(), entry.name, Theme.Text.Heading(), rarityColor, true)
	local sub = { rarity, `Lv{entry.level or (detail and detail.itemLevel) or 1}` }
	if detail and detail.slot then table.insert(sub, SLOT_LABEL[detail.slot] or tostring(detail.slot)) end
	addLine(list, nextOrder(), table.concat(sub, " | "), Theme.Text.Small(), Theme.Colors.TextSecondary)
	-- Price sits inside the inspector (user ruling 2026-10-31): buy price on Buy, sell price on Sell.
	if entry.price ~= nil then
		addLine(list, nextOrder(), `{entry.price} gold`, Theme.Text.Body(), Theme.Colors.TextGold, true)
	end

	if not detail then
		warn(`[MerchantInspector] No item detail for '{entry.name}' (server sent none)`)
		return
	end

	-- Base stats (Loadout detail labels)
	local stats = if detail.isWeapon then WEAPON_STATS else OTHER_STATS
	for _, s in stats do
		-- Non-weapon rows that are 0 are hidden, as in the Loadout detail view.
		local hideZero = not detail.isWeapon and detail[s.field] == 0
		local value = statValue(detail, s.field)
		if value ~= nil and not hideZero then addStatRow(list, nextOrder(), s.label, value) end
	end

	-- Passive (weapon/off-hand native passive, or armor passive)
	addLine(list, nextOrder(), "PASSIVES", Theme.Text.Small(), Theme.Colors.TextGold, true)
	local pName = if detail.isArmor then detail.passiveName else detail.nativePassiveName
	local pDesc = if detail.isArmor then detail.passiveDesc else detail.nativePassiveDesc
	if pName then
		addLine(list, nextOrder(), tostring(pName), Theme.Text.Body(), Theme.Colors.Success, true)
		if pDesc and pDesc ~= "" then
			addLine(list, nextOrder(), tostring(pDesc), Theme.Text.Small(), Theme.Colors.TextPrimary)
		end
	else
		addLine(list, nextOrder(), "None", Theme.Text.Small(), Theme.Colors.TextDisabled)
	end

	-- Bonus stats (sorted so the order never shuffles between renders)
	addLine(list, nextOrder(), "BONUS STATS", Theme.Text.Small(), Theme.Colors.TextGold, true)
	local bs = detail.bonusStats or {}
	local pcts = detail.bonusStatPcts or {}
	local keys: { string } = {}
	for k in bs do table.insert(keys, k) end
	for k in pcts do
		if bs[k] == nil then table.insert(keys, k) end
	end
	table.sort(keys)
	if #keys == 0 then
		addLine(list, nextOrder(), "None", Theme.Text.Small(), Theme.Colors.TextDisabled)
	end
	for _, k in keys do
		local v = bs[k]
		local p = pcts[k]
		local flat = if v ~= nil then `{if v > 0 then "+" else ""}{v}` else ""
		local pct = if p ~= nil and p ~= 0 then `  {if p > 0 then "+" else ""}{p}%` else ""
		addLine(list, nextOrder(), `{k}  {flat}{pct}`, Theme.Text.Body(), Theme.Colors.TextPrimary)
	end

	-- Bonus passives
	addLine(list, nextOrder(), "BONUS PASSIVES", Theme.Text.Small(), Theme.Colors.TextGold, true)
	local bp = detail.bonusPassives or {}
	if #bp == 0 then
		addLine(list, nextOrder(), "None", Theme.Text.Small(), Theme.Colors.TextDisabled)
	end
	for _, p in bp do
		addLine(list, nextOrder(), tostring(p.name or "Passive"), Theme.Text.Body(), Theme.Colors.Info, true)
		if p.desc and p.desc ~= "" then
			addLine(list, nextOrder(), tostring(p.desc), Theme.Text.Small(), Theme.Colors.TextPrimary)
		end
	end
end

--------------------------------------------------
-- PUBLIC
--------------------------------------------------

-- Selected entry: the caller's key if it is still listed, else the first entry, so the
-- inspector is never empty while the list has items.
function MerchantInspector.ResolveSelected(entries: { Entry }, key: any?): Entry?
	for _, e in entries do
		if e.key == key then return e end
	end
	return entries[1]
end

-- Fills a ScrollingFrame with item tiles (Theme.MakeItemTile + level / price badges;
-- pending items dimmed). Tapping a tile calls opts.onSelect(key).
function MerchantInspector.BuildGrid(scroll: ScrollingFrame, opts: GridOptions)
	local selected = MerchantInspector.ResolveSelected(opts.entries, opts.selectedKey)
	local cellW, cellH
	if opts.loadoutTiles then
		local h = scroll.AbsoluteSize.Y
		if h < 100 then h = opts.heightHint or 0 end
		cellW, cellH = Theme.ItemTileCell(h)
	else
		local gridW = math.max(MIN_CELL * 3, opts.width - 8)
		local cols = math.clamp(math.floor(gridW / 90), 3, 8)
		cellW = math.max(MIN_CELL, math.floor((gridW - GRID_GAP * (cols - 1)) / cols))
		cellH = cellW + Theme.ItemTile.NameBarHeight // 2
	end

	local loadoutGrid = opts.loadoutTiles == true and InventoryControls ~= nil
	if not loadoutGrid then
		local gridPad = Instance.new("UIPadding")
		gridPad.PaddingTop = UDim.new(0, 3)
		gridPad.PaddingLeft = UDim.new(0, 3)
		gridPad.PaddingRight = UDim.new(0, 3)
		gridPad.PaddingBottom = UDim.new(0, 3)
		gridPad.Parent = scroll
	end
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(cellW, cellH)
	gridLayout.CellPadding = if loadoutGrid then InventoryControls.GridCellPadding else UDim2.fromOffset(GRID_GAP, GRID_GAP)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = scroll
	if opts.loadoutTiles then
		-- The grid's real height is only known after layout (UI-001): re-fit once it is.
		-- Owned by the grid, so it goes away with it. Changing CellSize never resizes the grid.
		scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			local h = scroll.AbsoluteSize.Y
			if h < 100 then return end
			local w2, h2 = Theme.ItemTileCell(h)
			if gridLayout.CellSize.X.Offset ~= w2 or gridLayout.CellSize.Y.Offset ~= h2 then
				gridLayout.CellSize = UDim2.fromOffset(w2, h2)
			end
		end)
	end

	for i, e in opts.entries do
		local detail = e.detail
		local key = e.key
		local tile = Theme.MakeItemTile({
			parent = scroll,
			accentColor = Theme.GetRarityColor(e.rarity or "Common"),
			cellW = cellW,
			icon = detail and detail.icon or nil,
			iconText = string.sub(e.name, 1, 1),
			name = e.name,
			selected = selected ~= nil and e.key == selected.key,
			layoutOrder = i,
			onClick = function()
				opts.onSelect(key)
			end,
		})
		if loadoutGrid then
			local _lv, lvW = InventoryControls.MakeLevelLabel(tile, `Lv.{e.level or 1}`)
			InventoryControls.AddTileMarkers(tile, cellW, lvW, false, e.equippedBy ~= nil, e.isNew == true, false)
		else
			addTileBadge(tile, `Lv{e.level or 1}`, false)
		end
		if e.price ~= nil then addTileBadge(tile, `{e.price}g`, true) end
		if e.queued then addDimOverlay(tile) end
	end
end

-- Builds the inspector (scrollable item detail) for one entry, filling parent.
function MerchantInspector.BuildDetail(parent: Instance, entry: Entry?)
	local detailScroll = Instance.new("ScrollingFrame")
	detailScroll.Name = "Detail"
	detailScroll.Size = UDim2.fromScale(1, 1)
	detailScroll.BackgroundTransparency = 1
	detailScroll.BorderSizePixel = 0
	detailScroll.ScrollBarThickness = 4
	detailScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	detailScroll.CanvasSize = UDim2.new()
	local dPad = Instance.new("UIPadding")
	dPad.PaddingLeft = UDim.new(0, 4)
	dPad.PaddingRight = UDim.new(0, 8)
	dPad.PaddingTop = UDim.new(0, 2)
	dPad.PaddingBottom = UDim.new(0, 4)
	dPad.Parent = detailScroll
	local dList = Instance.new("UIListLayout")
	dList.Padding = UDim.new(0, 3)
	dList.SortOrder = Enum.SortOrder.LayoutOrder
	dList.Parent = detailScroll
	if entry then fillInspector(detailScroll, entry) end
	detailScroll.Parent = parent -- parent last (NET-004)
end

return table.freeze(MerchantInspector)
