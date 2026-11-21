--!strict
-- GuildHallScreen.lua
-- CTRBLXAI | Guild Hall full screen (user 2026-11-17 4:40 PM): its own screen like the Merchant /
-- Blacksmith, replacing the old "Guild Hall" page of the guild menu.
--
-- Layout (GuildScreen): header "GUILD HALL" | status | gold.
--   Main  : Buildings = one item tile per building (same icon as its guild-menu button, "Lv.N"),
--                       locked buildings dimmed;
--           Furnish   = Loadout search / Type / Rarity / sort bar, bonus line, then each open room as
--                       a row of spot tiles, locked rooms as a line, then Storage tiles. With a search
--                       or filter active: one flat grid of the matching pieces. Every piece is an item
--                       tile (rarity frame + portrait).
--   Side  : Buildings | Furnish sub-tabs on top (Merchant / Loadout pattern, user 2026-11-17 5:50 PM),
--           the inspector for the tapped tile below them.
--   Buttons (lower right): Buildings: Upgrade — N gold | Back.  Furnish: Place / Remove / Swap | Back.
--
-- Display + input only (ARC-001 / SEC-002): the server builds every row, prices and checks every
-- upgrade (BuildingService) and every furniture move (FurnitureService). Only approved text:
-- guild_facilities 98 / 112 (GH-*, FUR-*, BS-NOEFFECT, rank lines), the 11:02 PM furnish lines.
-- Furniture wording comes from FurnishScreen (one place); its picker / swap popup is reused.

local WAIT = 10

local uiFolder = script.Parent
local themeModule = uiFolder:WaitForChild("Theme", WAIT)
local guildScreenModule = uiFolder:WaitForChild("GuildScreen", WAIT)
local inspectorModule = uiFolder:WaitForChild("MerchantInspector", WAIT)
local furnishModule = uiFolder:WaitForChild("FurnishScreen", WAIT)
local controlsModule = uiFolder:WaitForChild("InventoryControls", WAIT)
if not themeModule or not guildScreenModule then
	error("[GuildHallScreen] Theme / GuildScreen module not found")
end
-- Found at runtime via WaitForChild; the editor cannot follow that path (editor-only cast).
local Theme: any = (require :: any)(themeModule)
local GuildScreen: any = (require :: any)(guildScreenModule)
local MerchantInspector: any = if inspectorModule then (require :: any)(inspectorModule) else nil
local FurnishScreen: any = if furnishModule then (require :: any)(furnishModule) else nil
local InventoryControls: any = if controlsModule then (require :: any)(controlsModule) else nil
if not MerchantInspector then warn("[GuildHallScreen] MerchantInspector missing -- no building grid") end
if not FurnishScreen then warn("[GuildHallScreen] FurnishScreen missing -- no Furnish tab") end
if not InventoryControls then warn("[GuildHallScreen] InventoryControls missing -- no Furnish search bar") end
-- New-player tips (2026-11-19, SYS-07): the Tips log opens from here. Guarded: no module = no button.
local TipController: any = nil
do
	local okTip, tipMod = pcall(function() return (require :: any)(uiFolder:WaitForChild("TipController", WAIT)) end)
	if okTip then TipController = tipMod else warn("[GuildHallScreen] tips unavailable -- no Tips button: " .. tostring(tipMod)) end
end

local GuildHallScreen = {}

export type Context = {
	parent: Instance,                               -- PlayerGui
	GuildEvents: any,
	FurnitureData: any,
	call: (remote: any, ...any) -> any?,            -- guild menu call(): nil on refusal (error shown)
	isBusy: () -> boolean,
	setBusy: (v: boolean) -> (),
	invalidatePageCache: () -> (),
	refreshOverview: () -> (),
	requestBack: (close: () -> ()) -> (),           -- Confirm/Discard prompt, then close
	onClosed: () -> (),                             -- opener re-shows itself
	setStatus: (text: string, isError: boolean?) -> (),
}

-- Building -> Theme.GuildIcons key: the SAME icon as its guild-menu nav button (user 4:40 PM).
local BUILDING_ICON: { [string]: string } = {
	GuildHall = "Townhall", QuestBoard = "AdventurersGuild", Tavern = "Recruitment", Merchant = "GearMerchant",
	Blacksmith = "Blacksmith", Apothecary = "Apothecary", Runeforge = "Runeforge",
	TrainingGrounds = "TrainingGrounds", Crucible = "Crucible", Dungeon = "Dungeon", Dispatch = "Dispatch",
}

local TAB_H = Theme.MinSize.TouchTarget -- fallback tab height (no InventoryControls)
local SUBTAB_H = if InventoryControls then InventoryControls.SubTabHeight else TAB_H -- Merchant / Loadout sub-tabs
local SUBTAB_GAP = if InventoryControls then InventoryControls.SubTabGap else 6
local BAR_H = if InventoryControls then InventoryControls.BarHeight else 24 -- Loadout search / filter bar
local BAR_BTNS_W = 3 * 62 + 3 * 3 -- three Loadout filter buttons + gaps (LoadoutGears search width)
-- Furnish bar options: Loadout labels ("Type", "Rarity", "All", "All Rarities", "Name") and the
-- furniture category / rarity names the Furnish screen already shows (FUR-SPOT-FITS, rarity lines).
local FURN_TYPES = { "All", "Bed", "Comfort", "Study", "Training", "Martial", "Display", "Fortune", "Logistics", "Special", "Wall" } -- 4 added: user 2026-11-17 6:04 PM
local FURN_SORTS = { { label = "Rarity", field = "rarity" }, { label = "Name", field = "name" } }
local INFO_H = 20
local GAP = 4
local DIM = 0.5 -- same dim as the Merchant / Dispatch tiles

local ctx: Context? = nil
local screen: any = nil
local isOpen = false
local tab = "Buildings" -- GH-TAB-UPGRADE / GH-TAB-FURNISH
local buildingRes: any = nil
local furnRes: any = nil
local selBuilding: string? = nil
local selFurn: string? = nil -- "spot:<key>" or "inst:<uid>"
local furnSearch = ""         -- Furnish bar state (kept while the screen is open, reset on Open)
local furnType = "All"
local furnRarity = "All"
local furnSort = 1
local activeMenu: ScreenGui? = nil
local sideBody: Frame? = nil  -- right panel area under the sub-tabs
local render: () -> () = function() end

local function closeMenu()
	if activeMenu then activeMenu:Destroy() end
	activeMenu = nil
end

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
	lbl.TextWrapped = true
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Top
	lbl.Size = UDim2.new(1, 0, 0, 0)
	lbl.AutomaticSize = Enum.AutomaticSize.Y
	lbl.Text = text
	lbl.Parent = parent
	return lbl
end

local function addDim(tile: Instance)
	local d = Instance.new("Frame")
	d.Name = "Dim"
	d.Size = UDim2.fromScale(1, 1)
	d.BackgroundColor3 = Color3.new(0, 0, 0)
	d.BackgroundTransparency = DIM
	d.BorderSizePixel = 0
	d.Active = false
	d.ZIndex = 6
	d.Parent = tile
end

-- Inspector panel: a scrolling list of lines (filled by the caller through add()).
local function makeInspector(): (ScrollingFrame, (text: string, size: number, color: Color3, bold: boolean?) -> ())
	local sc = Instance.new("ScrollingFrame")
	sc.Name = "Detail"
	sc.Size = UDim2.fromScale(1, 1)
	sc.BackgroundTransparency = 1
	sc.BorderSizePixel = 0
	sc.ScrollBarThickness = 4
	sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sc.CanvasSize = UDim2.new()
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 2)
	pad.Parent = sc
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 3)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = sc
	local order = 0
	local function add(text: string, size: number, color: Color3, bold: boolean?)
		if text == "" then return end
		order += 1
		local l = makeText(sc, text, size, color, bold)
		l.LayoutOrder = order
	end
	return sc, add
end

local function buttonRow(): (Frame, UIListLayout)
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
	return row, layout
end

local function addBack(row: Frame)
	local c = ctx
	if not c then return end
	local b = Theme.MakeIconButton(nil, "Back", function()
		c.requestBack(GuildHallScreen.Close)
	end, { name = "Btn_BACK", size = UDim2.fromOffset(GuildScreen.ROW_H, GuildScreen.ROW_H) })
	b.LayoutOrder = 99
	b.Parent = row
end

-- Buildings | Furnish sub-tabs at the top of the RIGHT panel, the inspector area below them
-- (same pattern as the Merchant Buy | Sell tabs: InventoryControls.MakeSubTabs, Loadout sizes).
local function buildTabs(side: Instance): Frame
	local c = ctx
	local function pick(t: any)
		if tab == t or (c and c.isBusy()) then return end
		closeMenu()
		tab = t
		if t == "Furnish" then furnRes = nil else buildingRes = nil end -- fresh data per visit
		render()
	end
	if InventoryControls then
		local row = InventoryControls.MakeSubTabs(side, {
			{ id = "Buildings", label = "Buildings" }, -- GH-TAB-UPGRADE
			{ id = "Furnish", label = "Furnish" },     -- GH-TAB-FURNISH
		}, tab, pick)
		row.Name = "GuildHallTabs"
	else
		local bar = Instance.new("Frame")
		bar.Name = "GuildHallTabs"
		bar.BackgroundTransparency = 1
		bar.Size = UDim2.new(1, 0, 0, SUBTAB_H)
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Horizontal
		list.Padding = UDim.new(0, SUBTAB_GAP)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = bar
		for i, t in { "Buildings", "Furnish" } do
			Theme.MakeTabButton(bar, t, if tab == t then "Active" else "Inactive", function() pick(t) end,
				{ name = "Tab_" .. t, size = UDim2.new(0.5, -SUBTAB_GAP // 2, 1, 0), layoutOrder = i })
		end
		bar.Parent = side
	end
	local holder = Instance.new("Frame")
	holder.Name = "DetailHolder"
	holder.Size = UDim2.new(1, 0, 1, -(SUBTAB_H + SUBTAB_GAP))
	holder.Position = UDim2.fromOffset(0, SUBTAB_H + SUBTAB_GAP)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Parent = side
	return holder
end

local function makeGridFrame(main: Instance, top: number): ScrollingFrame
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid" -- GuildScreen keeps the scroll position for a frame named Grid
	grid.Position = UDim2.fromOffset(0, top)
	grid.Size = UDim2.new(1, 0, 1, -top)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 4
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	return grid
end

--------------------------------------------------
-- BUILDINGS TAB (upgrade list as tiles; text from the server rows, guild_facilities 98)
--------------------------------------------------

local function findRow(rows: { any }, name: string?): any?
	for _, r in rows do if r.name == name then return r end end
	return rows[1]
end

local function upgrade(row: any)
	local c = ctx
	if not c or c.isBusy() or not row.canUpgrade then return end
	-- Same confirm line as the old Guild Hall page (approved), in the shared gold prompt.
	screen.Prompt(`Upgrade {row.display} to level {row.level + 1} for {row.cost} gold?`, "Upgrade", "Primary", function()
		c.setBusy(true)
		local r = c.call(c.GuildEvents.BuildingAction, { action = "Upgrade", building = row.name })
		c.setBusy(false)
		if r then
			c.setStatus(tostring(r.message or ""))
			c.invalidatePageCache()
			c.refreshOverview()
			buildingRes = r
			render()
		end
	end)
end

local function renderBuildings()
	local c = ctx
	if not c then return end
	if not buildingRes then buildingRes = c.call(c.GuildEvents.BuildingAction, { action = "List" }) end
	local rows: { any } = if type(buildingRes) == "table" and type(buildingRes.rows) == "table" then buildingRes.rows else {}
	local sel = findRow(rows, selBuilding)
	selBuilding = sel and sel.name or nil

	local main = screen.Main
	local grid = makeGridFrame(main, 0)
	local entries: { any } = {}
	for _, r in rows do
		table.insert(entries, {
			key = r.name, name = tostring(r.display or r.name), level = if r.open then tonumber(r.level) else nil,
			rarity = "Common", queued = not r.open or r.noEffect == true,
			detail = { icon = Theme.GuildIcons[BUILDING_ICON[r.name] or ""] },
		})
	end
	if MerchantInspector then
		MerchantInspector.BuildGrid(grid, {
			entries = entries, selectedKey = selBuilding, width = 0,
			heightHint = (main :: any).AbsoluteSize.Y,
			onSelect = function(key: any)
				selBuilding = key
				render()
			end,
		})
	end
	grid.Parent = main

	-- Inspector (USER RULING 2026-11-17 5:18 PM, guild_facilities 113): name, "Level n / max",
	-- "Next level" + every change for the next level, the Renown Rank line (red if too low, grey when
	-- reached), then the reason. All lines come from the server row (BuildingService); scrolls if long.
	local sc, add = makeInspector()
	if sel then
		add(tostring(sel.display or sel.name), Theme.Text.Heading(), Theme.Colors.TextGold, true)
		add(`Level {sel.level} / {sel.maxLevel}`, Theme.Text.Body(), Theme.Colors.TextPrimary)
		if type(sel.description) == "string" and sel.description ~= "" then -- e.g. DISPATCH-BLD-DESC
			add(sel.description, Theme.Text.Small(), Theme.Colors.TextSecondary)
		end
		local lines = sel.nextLines
		if type(lines) == "table" and #lines > 0 then
			add("Next level", Theme.Text.Body(), Theme.Colors.TextGold, true) -- GH-NEXT-HEAD
			for _, line in lines do
				add(tostring(line), Theme.Text.Body(), Theme.Colors.TextPrimary)
			end
		elseif sel.next then
			add(tostring(sel.next), Theme.Text.Body(), Theme.Colors.TextPrimary) -- older server rows
		end
		if type(sel.rankText) == "string" then
			add(sel.rankText, Theme.Text.Small(), if sel.rankOk then Theme.Colors.TextSecondary else Theme.Colors.Danger)
		end
		if sel.reason and sel.reason ~= sel.rankText then
			add(tostring(sel.reason), Theme.Text.Small(),
				if sel.open and not sel.noEffect and sel.reason ~= "Max level" then Theme.Colors.Danger else Theme.Colors.TextSecondary)
		end
	end
	sc.Parent = sideBody or screen.Side

	local row = buttonRow()
	if sel and sel.open and sel.cost then
		Theme.MakeBarButton(row, `Upgrade — {sel.cost} gold`, if sel.canUpgrade then "Primary" else "Disabled", function()
			upgrade(sel)
		end, { name = "Btn_Upgrade", minHeight = GuildScreen.ROW_H, layoutOrder = 1 })
	end
	if TipController then -- Tips log (SYS-07): every seen tip + the Show tips switch
		Theme.MakeBarButton(row, "Tips", "Secondary", function() TipController.OpenLog() end,
			{ name = "Btn_Tips", minHeight = GuildScreen.ROW_H, layoutOrder = 2 })
	end
	addBack(row)
	row.Parent = screen.Buttons
end

--------------------------------------------------
-- FURNISH TAB (rooms + storage as item tiles; wording from FurnishScreen)
--------------------------------------------------

local function pieceRarity(inst: any): string
	local r = inst.rarity
	if inst.fixed or inst.looks or type(r) ~= "string" or r == "None" or r == "Fixed" then return "Common" end
	return r
end

local function pieceTile(parent: Instance, cellW: number, order: number, inst: any?, key: string, label: string, dim: boolean)
	local name = label
	local icon: string? = nil
	local rarity = "Common"
	if inst then
		local p = ctx and ctx.FurnitureData.V4.Get(inst.id)
		name = if p then tostring(p.name) else tostring(inst.id)
		icon = Theme.FurnitureIcons and Theme.FurnitureIcons[tostring(inst.id)] or nil
		rarity = pieceRarity(inst)
	end
	local tile = Theme.MakeItemTile({
		parent = parent,
		accentColor = Theme.GetRarityColor(rarity),
		cellW = cellW,
		icon = icon,
		iconText = string.sub(name, 1, 1),
		name = name,
		selected = selFurn == key,
		layoutOrder = order,
		portrait = true,
		onClick = function()
			selFurn = key
			render()
		end,
	})
	if dim then addDim(tile) end
end

local function section(grid: Instance, order: number, heading: string, cellW: number, cellH: number): Frame
	if heading ~= "" then
		local h = makeText(grid, heading, Theme.Text.Small(), Theme.Colors.TextGold, true)
		h.LayoutOrder = order
	end
	local f = Instance.new("Frame")
	f.Name = "Tiles"
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.new(1, -6, 0, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.LayoutOrder = order + 1
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.fromOffset(cellW, cellH)
	gl.CellPadding = UDim2.fromOffset(GAP, GAP)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = f
	f.Parent = grid
	return f
end

local function renderFurnish()
	local c = ctx
	if not c or not FurnishScreen then
		local row = buttonRow(); addBack(row); row.Parent = screen.Buttons
		return
	end
	if not furnRes then furnRes = c.call(c.GuildEvents.FurnitureAction, { action = "State" }) end
	local f = type(furnRes) == "table" and furnRes.furniture or nil
	local main = screen.Main
	local FD = c.FurnitureData
	if type(f) ~= "table" or not FD then
		local row = buttonRow(); addBack(row); row.Parent = screen.Buttons
		return
	end
	local v4 = type(f.v4) == "table" and f.v4 or {}
	local totals = type(v4.totals) == "table" and v4.totals or {}
	local spots: { any } = type(v4.spots) == "table" and v4.spots or {}
	local insts: { any } = type(v4.instances) == "table" and v4.instances or {}
	local gh = tonumber(f.guildHallLevel) or 1
	local locked = f.locked == true
	local lineStatusAll = type(totals.lineStatus) == "table" and totals.lineStatus or {}
	local byUid: { [string]: any } = {}
	local storage: { any } = {}
	local anyEnemy, anyThreshold = false, false
	for _, inst in insts do
		byUid[tostring(inst.uid)] = inst
		if inst.spot == nil then table.insert(storage, inst) end
	end
	FurnishScreen.SortStorage(storage)
	local spotByKey: { [string]: any } = {}
	for _, sp in spots do
		spotByKey[tostring(sp.key)] = sp
		local inst = sp.uid and byUid[tostring(sp.uid)]
		for _, l in (inst and type(inst.lines) == "table" and inst.lines or {}) do
			if l.enemy then anyEnemy = true end
			if l.threshold then anyThreshold = true end
		end
	end
	local function fittingCount(sp: any): number
		local n = 0
		for _, s2 in storage do if FurnishScreen.FitsSpot(s2, sp) then n += 1 end end
		return n
	end

	-- Info line: FUR-CAP (+ FUR-THRESHOLD-SHARED / -COUNT) (+ FUR-LOCKED-RUN).
	local info: { string } = { `Bonus: {FurnishScreen.Num(f.points or totals.points or 0)} / {FurnishScreen.Num(f.cap or totals.cap or 0)}` }
	if anyThreshold then
		local n = 0
		for _ in (type(totals.threshold) == "table" and totals.threshold or {}) do n += 1 end
		table.insert(info, if anyEnemy then `Special bonuses (yours + enemy): {n}/2` else `Special bonuses: {n}/2`)
	end
	if locked then table.insert(info, "You can't change furniture during a battle or dungeon run.") end
	-- Search / Type / Rarity / sort bar: the Loadout GEARS bar (InventoryControls, same sizes and
	-- labels; user 2026-11-17 5:50 PM). Typing rebuilds only the grid, so the keyboard stays open.
	local fillGrid: () -> () = function() end
	local barTop = 0
	if InventoryControls then
		local ctrlRow = Instance.new("Frame")
		ctrlRow.Name = "FurnishBar"
		ctrlRow.Size = UDim2.new(1, 0, 0, BAR_H)
		ctrlRow.BackgroundTransparency = 1
		ctrlRow.BorderSizePixel = 0
		local ctrlLayout = Instance.new("UIListLayout")
		ctrlLayout.FillDirection = Enum.FillDirection.Horizontal
		ctrlLayout.Padding = UDim.new(0, InventoryControls.ControlGap)
		ctrlLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		ctrlLayout.SortOrder = Enum.SortOrder.LayoutOrder
		ctrlLayout.Parent = ctrlRow

		local search = Instance.new("TextBox") -- same box as the Loadout search
		search.Name = "Search"
		search.Size = UDim2.new(1, -BAR_BTNS_W, 1, 0)
		search.BackgroundColor3 = Theme.Colors.Surface
		search.BackgroundTransparency = 0.2
		search.Font = Theme.Font.Primary
		search.TextSize = Theme.Text.Small()
		search.TextColor3 = Theme.Colors.TextPrimary
		search.PlaceholderText = "Search items..." -- Loadout placeholder (approved)
		search.PlaceholderColor3 = Theme.Colors.TextDisabled
		search.Text = furnSearch
		search.BorderSizePixel = 0
		search.ClearTextOnFocus = false
		search.LayoutOrder = 1
		search.Parent = ctrlRow
		Instance.new("UICorner", search).CornerRadius = UDim.new(0, 3)

		local function showMenu(anchor: GuiObject, opts: { any }, onSelect: (any, number) -> ())
			closeMenu()
			activeMenu = InventoryControls.ShowMenu(c.parent, anchor, opts, onSelect, closeMenu)
		end
		local typeBtn = InventoryControls.MakeFilterButton(ctrlRow, if furnType == "All" then "Type" else furnType, 2,
			furnType ~= "All", Theme.Icons.Filter)
		typeBtn.Activated:Connect(function()
			local opts = {}
			for _, id in FURN_TYPES do table.insert(opts, { label = id, value = id, active = furnType == id }) end
			showMenu(typeBtn, opts, function(v: any)
				furnType = tostring(v)
				if furnType == "All" then furnRarity = "All" end -- full reset, like the Loadout Type menu
				render()
			end)
		end)
		local rarityBtn = InventoryControls.MakeFilterButton(ctrlRow, if furnRarity == "All" then "Rarity" else furnRarity, 3,
			furnRarity ~= "All", Theme.Icons.Filter)
		rarityBtn.Activated:Connect(function()
			local names: { string } = {}
			for name in FD.V4.Rarities do table.insert(names, name) end
			table.sort(names, function(x, y) return FD.V4.Rarities[x].step < FD.V4.Rarities[y].step end)
			local opts = { { label = "All Rarities", value = "All", active = furnRarity == "All" } }
			for _, name in names do table.insert(opts, { label = name, value = name, active = furnRarity == name }) end
			showMenu(rarityBtn, opts, function(v: any)
				furnRarity = tostring(v)
				render()
			end)
		end)
		local sortBtn = InventoryControls.MakeFilterButton(ctrlRow, (FURN_SORTS[furnSort] or FURN_SORTS[1]).label, 4,
			false, Theme.Icons.Sort)
		sortBtn.Activated:Connect(function()
			local opts = {}
			for si, s in FURN_SORTS do table.insert(opts, { label = s.label, value = si, active = furnSort == si }) end
			showMenu(sortBtn, opts, function(v: any)
				furnSort = tonumber(v) or 1
				render()
			end)
		end)
		ctrlRow.Parent = main
		barTop = BAR_H + GAP
		search:GetPropertyChangedSignal("Text"):Connect(function()
			furnSearch = search.Text
			fillGrid()
		end)
	end

	local infoL = makeText(main, table.concat(info, "   ·   "), Theme.Text.Small(), Theme.Colors.TextSecondary)
	infoL.AutomaticSize = Enum.AutomaticSize.None
	infoL.Size = UDim2.new(1, 0, 0, INFO_H)
	infoL.Position = UDim2.fromOffset(0, barTop)
	infoL.TextWrapped = false
	infoL.TextTruncate = Enum.TextTruncate.AtEnd
	infoL.TextScaled = true
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = Theme.Text.Small()
	fit.MinTextSize = math.min(Theme.Text.Small(), 10)
	fit.Parent = infoL

	local top = barTop + INFO_H + GAP
	-- Two tile rows fit the phone height; Loadout tile recipe (Theme.ItemTileCell).
	local cellW, cellH = Theme.ItemTileCell(math.max(100, ((main :: any).AbsoluteSize.Y - top) * 1.4))

	local function pieceName(inst: any): string
		local p = FD.V4.Get(inst.id)
		return if p then tostring(p.name) else tostring(inst.id)
	end
	local function rarityStep(inst: any): number
		local r = FD.V4.Rarities[pieceRarity(inst)]
		return if r then r.step else 0
	end
	-- Sort (Loadout "Rarity" = highest first, "Name" = A-Z); name, then key, breaks ties.
	local function sortPieces(list: { any })
		local so = FURN_SORTS[furnSort] or FURN_SORTS[1]
		table.sort(list, function(x: any, y: any)
			if so.field == "rarity" then
				local rx, ry = rarityStep(x.inst), rarityStep(y.inst)
				if rx ~= ry then return rx > ry end
			end
			local nx, ny = pieceName(x.inst), pieceName(y.inst)
			if nx ~= ny then return nx < ny end
			return tostring(x.key) < tostring(y.key)
		end)
	end
	local function query(): string
		return string.lower(string.match(furnSearch, "^%s*(.-)%s*$") or "")
	end
	local function matches(inst: any): boolean
		local p = FD.V4.Get(inst.id)
		if furnType ~= "All" and (not p or p.category ~= furnType) then return false end
		if furnRarity ~= "All" and pieceRarity(inst) ~= furnRarity then return false end
		local q = query()
		if q ~= "" and not string.find(string.lower(pieceName(inst)), q, 1, true) then return false end
		return true
	end

	-- Selection: keep the tapped tile, else the first tile shown.
	local firstKey: string? = nil
	fillGrid = function()
		local old = main:FindFirstChild("Grid")
		if old then old:Destroy() end
		firstKey = nil
		local grid = makeGridFrame(main, top)
		local gl = Instance.new("UIListLayout")
		gl.Padding = UDim.new(0, GAP)
		gl.SortOrder = Enum.SortOrder.LayoutOrder
		gl.Parent = grid

		if query() ~= "" or furnType ~= "All" or furnRarity ~= "All" then
			-- Search / filter active: one flat grid of the matching pieces (placed and in storage);
			-- the inspector shows the room of a placed piece.
			local list: { any } = {}
			for _, sp in spots do
				local inst = sp.uid and byUid[tostring(sp.uid)]
				if inst and matches(inst) then
					table.insert(list, { inst = inst, key = "spot:" .. tostring(sp.key),
						dim = sp.status == "capped" or sp.status == "invalid" })
				end
			end
			for _, inst in storage do
				if matches(inst) then table.insert(list, { inst = inst, key = "inst:" .. tostring(inst.uid), dim = false }) end
			end
			sortPieces(list)
			local tiles = section(grid, 1, "", cellW, cellH)
			for i, e in list do
				firstKey = firstKey or e.key
				pieceTile(tiles, cellW, i, e.inst, e.key, "", e.dim)
			end
		else
			local order = 0
			for _, room in FD.V4.Rooms do
				order += 2
				if room.gh > gh then
					local l = makeText(grid, `{room.name}\nUnlocks at Guild Hall level {room.gh}.`, Theme.Text.Small(), Theme.Colors.TextDisabled) -- FUR-ROOM-LOCKED
					l.LayoutOrder = order
				else
					local mine: { any } = {}
					local fl, flMax, wl, wlMax = 0, 0, 0, 0
					for _, sp in spots do
						if sp.room == room.id then
							table.insert(mine, sp)
							if sp.wall then wlMax += 1 if sp.uid then wl += 1 end
							else flMax += 1 if sp.uid then fl += 1 end end
						end
					end
					local tiles = section(grid, order, `{room.name} — Floor {fl}/{flMax} · Wall {wl}/{wlMax}`, cellW, cellH) -- FUR-CAT-COUNT
					for i, sp in mine do
						local key = "spot:" .. tostring(sp.key)
						firstKey = firstKey or key
						local inst = sp.uid and byUid[tostring(sp.uid)]
						if inst then
							pieceTile(tiles, cellW, i, inst, key, "", sp.status == "capped" or sp.status == "invalid")
						else
							pieceTile(tiles, cellW, i, nil, key, if sp.wall then "Wall decoration — empty" else "Empty slot", true)
						end
					end
				end
			end
			order += 2
			local shown: { any } = {}
			for _, inst in storage do table.insert(shown, { inst = inst, key = "inst:" .. tostring(inst.uid) }) end
			sortPieces(shown)
			local stTiles = section(grid, order, `Storage ({#storage})`, cellW, cellH) -- FUR-STORAGE-TITLE
			for i, e in shown do
				firstKey = firstKey or e.key
				pieceTile(stTiles, cellW, i, e.inst, e.key, "", false)
			end
			if #storage == 0 then
				local l = makeText(grid, "No furniture in storage.\nFind furniture in the Dungeon, or craft it.", Theme.Text.Small(), Theme.Colors.TextSecondary) -- FUR-STORAGE-EMPTY + FUR-NO-SHOP
				l.LayoutOrder = order + 2
			end
		end
		grid.Parent = main
	end
	fillGrid()

	-- Resolve the selection (a moved / removed piece falls back to the first tile).
	local selSpot: any = nil
	local selInst: any = nil
	if selFurn and string.sub(selFurn, 1, 5) == "spot:" then selSpot = spotByKey[string.sub(selFurn, 6)] end
	if selFurn and string.sub(selFurn, 1, 5) == "inst:" then
		selInst = byUid[string.sub(selFurn, 6)]
		if selInst and selInst.spot ~= nil then selInst = nil end
	end
	if not selSpot and not selInst then
		selFurn = firstKey
		if firstKey and string.sub(firstKey, 1, 5) == "spot:" then selSpot = spotByKey[string.sub(firstKey, 6)] end
		if firstKey and string.sub(firstKey, 1, 5) == "inst:" then selInst = byUid[string.sub(firstKey, 6)] end
	end

	-- Inspector: name (rarity colour), room, bonus lines and status (FurnishScreen wording).
	local sc, add = makeInspector()
	local shown = selInst or (selSpot and selSpot.uid and byUid[tostring(selSpot.uid)]) or nil
	if shown then
		local txt = FurnishScreen.PieceText(shown, selSpot and selSpot.status or nil,
			if selSpot then lineStatusAll[tostring(shown.uid)] else nil)
		local lines = string.split(txt, "\n")
		add(lines[1] or "", Theme.Text.Heading(), Theme.GetRarityColor(pieceRarity(shown)), true)
		if selSpot and selSpot.roomName then add(tostring(selSpot.roomName), Theme.Text.Small(), Theme.Colors.TextSecondary) end
		for i = 2, #lines do
			for _, part in string.split(lines[i], "  ·  ") do
				add(part, Theme.Text.Body(), Theme.Colors.TextPrimary)
			end
		end
	elseif selSpot then
		add(if selSpot.wall then "Wall decoration — empty" else "Empty slot", Theme.Text.Heading(), Theme.Colors.TextPrimary, true)
		if selSpot.roomName then add(tostring(selSpot.roomName), Theme.Text.Small(), Theme.Colors.TextSecondary) end
		if not selSpot.wall then
			add(table.concat(type(selSpot.accepts) == "table" and selSpot.accepts or {}, ", "), Theme.Text.Body(), Theme.Colors.TextPrimary) -- FUR-SPOT-FITS
		end
	end
	sc.Parent = sideBody or screen.Side

	-- Buttons: same actions and server calls as the old Furnish rows.
	local row = buttonRow()
	if selSpot and selSpot.uid then
		Theme.MakeBarButton(row, "Remove", if locked then "Disabled" else "Secondary", function()
			if not locked then FurnishScreen.Call({ action = "Remove", slot = selSpot.key }) end
		end, { name = "Btn_Remove", minHeight = GuildScreen.ROW_H, layoutOrder = 1 })
		local canSwap = (not locked) and fittingCount(selSpot) > 0
		Theme.MakeBarButton(row, "Swap", if canSwap then "Primary" else "Disabled", function() -- FUR-SWAP
			if canSwap then FurnishScreen.OpenPick(selSpot, storage, locked) end
		end, { name = "Btn_Swap", minHeight = GuildScreen.ROW_H, layoutOrder = 2 })
	elseif selSpot then
		local canPlace = (not locked) and fittingCount(selSpot) > 0
		Theme.MakeBarButton(row, "Place", if canPlace then "Primary" else "Disabled", function()
			if canPlace then FurnishScreen.OpenPick(selSpot, storage, locked) end
		end, { name = "Btn_Place", minHeight = GuildScreen.ROW_H, layoutOrder = 1 })
	elseif selInst then
		Theme.MakeBarButton(row, "Place", if locked then "Disabled" else "Primary", function()
			-- First free spot that fits (server picks; FUR-NO-SPOT if none).
			if not locked then FurnishScreen.Call({ action = "Place", piece = selInst.uid, slot = "auto" }) end
		end, { name = "Btn_Place", minHeight = GuildScreen.ROW_H, layoutOrder = 1 })
	end
	addBack(row)
	row.Parent = screen.Buttons

	-- WARN-A: pieces left behind at the 400 limit (also shown on return to base).
	if type(f.leftBehind) == "table" and #f.leftBehind > 0 then
		c.setStatus(table.concat(f.leftBehind, "\n"), true) -- FUR-STORAGE-FULL
		f.leftBehind = nil
		task.spawn(function() pcall(function() c.GuildEvents.FurnitureAction:InvokeServer({ action = "AckLeftBehind" }) end) end)
	end
end

render = function()
	if not ctx or not screen or not isOpen then return end
	closeMenu()
	screen.Clear(tab)
	sideBody = buildTabs(screen.Side)
	if tab == "Furnish" then renderFurnish() else renderBuildings() end
end

--------------------------------------------------
-- PUBLIC (same shape as the other guild screens)
--------------------------------------------------

function GuildHallScreen.Init(c: Context)
	ctx = c
	-- Every FurnitureAction answer (Place / Remove / Swap from the picker) redraws this screen.
	if FurnishScreen and FurnishScreen.SetOnResult then
		FurnishScreen.SetOnResult(function(res: any)
			furnRes = res
			render()
		end)
	end
end

function GuildHallScreen.IsOpen(): boolean
	return isOpen
end

function GuildHallScreen.GetGui(): ScreenGui?
	return if isOpen and screen then screen.Gui else nil
end

-- startTab: "Buildings" (default) or "Furnish".
function GuildHallScreen.Open(startTab: string?)
	local c = ctx
	if not c then
		warn("[GuildHallScreen] Open called before Init")
		return
	end
	if not screen then
		screen = GuildScreen.Create({ name = "GuildHallScreen", title = "GUILD HALL", parent = c.parent , crest = Theme.GuildIcons.Townhall, autoCurrencies = true }) -- 2026-11-20 user: nav button icon + currency icons -- GH-TITLE
		screen.SetButtonRows(1)
	end
	tab = if startTab == "Furnish" then "Furnish" else "Buildings"
	buildingRes, furnRes = nil, nil
	furnSearch, furnType, furnRarity, furnSort = "", "All", "All", 1
	isOpen = true
	screen.SetStatus("")
	screen.Show()
	render()
end

-- Back path: hide and hand control back to the opener.
function GuildHallScreen.Close()
	if not isOpen then return end
	isOpen = false
	closeMenu()
	if FurnishScreen and FurnishScreen.ClosePick then FurnishScreen.ClosePick() end
	if screen then screen.ClosePrompt(); screen.Hide() end
	local c = ctx
	if c then c.onClosed() end
end

-- Forced hide (menu closed by the server): no onClosed.
function GuildHallScreen.Hide()
	if not isOpen then return end
	isOpen = false
	closeMenu()
	if FurnishScreen and FurnishScreen.ClosePick then FurnishScreen.ClosePick() end
	if screen then screen.ClosePrompt(); screen.Hide() end
end

-- Fresh data (dev building change, overview refresh) and redraw.
function GuildHallScreen.Render()
	buildingRes, furnRes = nil, nil
	render()
end

function GuildHallScreen.SetGold(text: string)
	if screen then screen.SetGold(text) end
end

function GuildHallScreen.SetStatus(text: string, isError: boolean?)
	if screen then screen.SetStatus(text, isError) end
end

return table.freeze(GuildHallScreen)
