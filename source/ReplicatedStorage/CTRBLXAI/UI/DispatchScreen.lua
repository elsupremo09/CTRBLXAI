--!strict
-- DispatchScreen.lua
-- CTRBLXAI | Dispatch full screen (2026-11-11, user-approved layout: mirrored Option A with every
-- button in the lower right). Its own screen like the Merchant / Tavern; opened from the guild
-- menu today, by the Dispatch board structure later. Back returns to whatever opened it.
--
-- Layout (GuildScreen):
--   LEFT   info line (slots, fee, keep one home), the selected mission's details, the unit
--          portrait grid (tap = pick / unpick; away or queued units are dimmed and labelled),
--          and an "Out now:" strip of units away with battles left
--   RIGHT  mission cards (name, reward, tier, battles away); tap = select. Queued missions hidden.
--   BOTTOM ONE row of square icons, lower right:  [?] [X cancel] [check send] [Back]
--          ? = what Dispatch does; X = clear the current pick; check = queue the dispatch into the
--          guild menu's pending list; Back = the usual Confirm / Discard prompt, then close.
--
-- Display + input only (ARC-001 / SEC-002). Missions, fee, slots and rewards come from the
-- server (GetDispatchBoard); the pending list is owned by the opener (guild menu basket) and is
-- committed by its Confirm, which sends only mission and unit ids. The reward is shown
-- generically (rewardMaterial + rewardAmount, falling back to rewardMercury), so a change to what
-- missions pay needs server data only. Context is nil-safe (ARC-006).

local WAIT = 10

local uiFolder = script.Parent
local themeModule = uiFolder:WaitForChild("Theme", WAIT)
local guildScreenModule = uiFolder:WaitForChild("GuildScreen", WAIT)
local controlsModule = uiFolder:WaitForChild("InventoryControls", WAIT)
if not themeModule or not guildScreenModule then
	error("[DispatchScreen] Theme / GuildScreen module not found")
end
-- Found at runtime via WaitForChild; the editor cannot follow that path (editor-only cast).
local Theme: any = (require :: any)(themeModule)
local GuildScreen: any = (require :: any)(guildScreenModule)
local InventoryControls: any = if controlsModule then (require :: any)(controlsModule) else nil

local DispatchScreen = {}

--------------------------------------------------
-- TYPES / CONSTANTS / STATE
--------------------------------------------------

export type Staged = { missionId: string, unitIds: { string }, fee: number }

-- Injected by the opener (guild menu today).
export type Context = {
	parent: Instance,                                         -- PlayerGui
	getBoard: () -> any?,                                     -- GetDispatchBoard answer (cached)
	getStaged: () -> { Staged },                              -- pending dispatches (read only)
	queue: (missionId: string, unitIds: { string }, fee: number) -> (),
	pendingCount: () -> number,
	recall: ((missionId: string) -> any?)?,                   -- Dispatch Recall (server answer or nil)
	requestBack: (close: () -> ()) -> (),                     -- Confirm/Discard prompt, then close
	onClosed: () -> (),                                       -- opener re-shows itself
	setStatus: (text: string, isError: boolean?) -> (),
}

local BUTTON_ROWS = 1
local MAX_PICK = 3            -- server MAX_DISPATCH_PICK (GuildMenuService); USER RULING 2026-11-12 (was 7)
local CARD_H = 46             -- mission card height (>= 44 px touch target)
local STRIP_H = 44            -- "Out now:" strip height: its pills are tap targets (>= 44 px, Recall)
local DIM = 0.5               -- dim overlay for away / queued tiles (same as the Merchant)
local HELP_MAX_W = 560

local MATERIAL_NAMES: { [string]: string } = {
	mercury = "Mercury", crystals = "Crystals", sulfur = "Sulfur", gems = "Rune gems",
}

local ctx: Context? = nil
local screen: any = nil
local isOpen = false
local selectedMission: string? = nil
local selectedUnits: { [string]: boolean } = {}
local selectedRecall: string? = nil -- away mission picked in the Out now strip (Recall)
local helpOverlay: Instance? = nil

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
	lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.Text = text
	lbl.Parent = parent
	return lbl
end

local function addLine(parent: Instance, order: number, text: string, size: number, color: Color3, bold: boolean?)
	local lbl = makeText(nil, text, size, color, bold)
	lbl.Size = UDim2.new(1, 0, 0, 0)
	lbl.AutomaticSize = Enum.AutomaticSize.Y
	lbl.LayoutOrder = order
	lbl.Parent = parent
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

local function battles(n: number): string
	return if n == 1 then "1 battle" else `{n} battles`
end

-- Placeholder name until missions carry their own (Designer brief, 2026-11-11).
local function missionName(m: any): string
	if type(m.name) == "string" and m.name ~= "" then return m.name end
	return `Tier {m.tier or "?"} mission`
end

-- Display name of an away mission, from any of its units (same naming as the mission cards).
local function awayMissionName(u: any): string
	return missionName({ name = u.awayMissionName, tier = u.awayMissionTier })
end

-- Generic reward: rewardMaterial + rewardAmount (display fields), else today's rewardMercury.
local function rewardText(m: any): string
	local mat = if type(m.rewardMaterial) == "string" then m.rewardMaterial else "mercury"
	local amount = tonumber(m.rewardAmount) or tonumber(m.rewardMercury) or 0
	return `{amount} {MATERIAL_NAMES[mat] or mat}`
end

--------------------------------------------------
-- STATE FROM THE BOARD + PENDING LIST
--------------------------------------------------

local function derive(res: any): any
	local c = ctx
	local stagedUnits: { [string]: boolean } = {}
	local stagedMissions: { [string]: boolean } = {}
	local nStaged, stagedFee = 0, 0
	if c then
		for _, d in c.getStaged() do
			nStaged += 1
			stagedFee += d.fee or 0
			stagedMissions[d.missionId] = true
			for _, uid in d.unitIds do stagedUnits[uid] = true end
		end
	end
	local missions = {}
	local selected: any = nil
	for _, m in res.missions or {} do
		if not stagedMissions[m.missionId] then
			table.insert(missions, m)
			if m.missionId == selectedMission then selected = m end
		end
	end
	if not selected then selectedMission = nil end
	local homeCount = 0
	local byId: { [string]: any } = {}
	for _, u in res.units or {} do
		byId[u.id] = u
		if not u.away and not stagedUnits[u.id] then homeCount += 1 end
	end
	-- The recall pick must still be an away mission (it may have returned or been recalled).
	local recallUnit: any = nil
	if selectedRecall then
		for _, u in res.units or {} do
			if u.away and u.awayMissionId == selectedRecall then recallUnit = u; break end
		end
		if not recallUnit then selectedRecall = nil end
	end
	-- Drop picks that are no longer pickable (sent, queued, or gone).
	for uid in selectedUnits do
		local u = byId[uid]
		if not u or u.away or stagedUnits[uid] then selectedUnits[uid] = nil end
	end
	local nPicked = 0
	for _ in selectedUnits do nPicked += 1 end
	return {
		missions = missions, selected = selected, stagedUnits = stagedUnits,
		nStaged = nStaged, stagedFee = stagedFee,
		slotsUsed = (res.slotsUsed or 0) + nStaged, slotCap = res.slotCap or 1,
		homeCount = homeCount, nPicked = nPicked, fee = res.feeGold or 0, recallUnit = recallUnit,
	}
end

--------------------------------------------------
-- RENDER
--------------------------------------------------

local render: () -> () -- forward declaration (taps re-render)

local function addDim(tile: Instance, label: string)
	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = DIM
	dim.BorderSizePixel = 0
	dim.Active = false
	dim.ZIndex = 5
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.ItemTile.CornerRadius)
	corner.Parent = dim
	local long = #label > 8 -- "Exploring a dungeon" (2026-11-13 8:24 PM): 2 lines, 10 px floor
	local tag = makeText(nil, label, if long then math.max(10, Theme.Text.Badge()) else Theme.Text.Badge(), Theme.Colors.TextPrimary, true)
	tag.Size = UDim2.new(1, -4, 0, if long then 26 else 16)
	if long then tag.TextWrapped = true; tag.Position = UDim2.new(0, 2, 0.3, 0) end
	if not long then tag.Position = UDim2.new(0, 0, 0.35, 0) end
	tag.TextXAlignment = Enum.TextXAlignment.Center
	tag.ZIndex = 6
	tag.Parent = dim
	dim.Parent = tile
end

-- Portrait icons are a fixed px square; keep their border equal when the cells re-fit.
local function refitIcons(scroll: Instance, cellW: number)
	local t = Theme.ItemTile
	local inset = math.max(t.IconInsetMin, math.round(cellW * t.IconInsetFactor))
	for _, tile in scroll:GetChildren() do
		if tile:IsA("TextButton") then
			for _, ch in tile:GetChildren() do
				if ch:IsA("ImageLabel") and ch.Name ~= "ItemFrame" then -- never resize the ornate frame
					ch.Size = UDim2.new(1, -inset * 2, 0, cellW - inset * 2 - Theme.ItemTileFramePad() * 2)
					ch.Position = UDim2.fromOffset(inset, inset)
				end
			end
		end
	end
end

-- Unit portraits, same tile recipe as the guild-screen grids (Theme.MakeItemTile, Loadout cell).
local function buildUnitGrid(grid: ScrollingFrame, res: any, st: any, heightHint: number)
	local cellW, cellH = Theme.ItemTileCell(heightHint)
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(cellW, cellH)
	layout.CellPadding = if InventoryControls then InventoryControls.GridCellPadding else UDim2.fromOffset(4, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	-- The real height is known only after layout (UI-001): re-fit once. Owned by the grid.
	grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local gh = grid.AbsoluteSize.Y
		if gh < 100 then return end
		local w2, h2 = Theme.ItemTileCell(gh)
		if layout.CellSize.X.Offset ~= w2 or layout.CellSize.Y.Offset ~= h2 then
			layout.CellSize = UDim2.fromOffset(w2, h2)
			refitIcons(grid, w2)
		end
	end)
	for i, u in res.units or {} do
		local uid = u.id
		local blocked = if u.away then (if u.awayReason == "dungeon" then "Exploring a dungeon" else "AWAY") elseif st.stagedUnits[uid] then "QUEUED" else nil
		local picked = selectedUnits[uid] == true
		local tile = Theme.MakeItemTile({
			parent = grid,
			accentColor = Theme.GetRarityColor("Common"),
			cellW = cellW,
			icon = asImage(u.portraitAssetId),
			iconText = string.sub(tostring(u.name or "?"), 1, 1),
			name = tostring(u.name or "?"),
			selected = picked,
			layoutOrder = i,
			portrait = true,
			onClick = function()
				if blocked then return end
				if picked then
					selectedUnits[uid] = nil
				elseif st.nPicked >= MAX_PICK then
					local c = ctx
					if c then c.setStatus(`Send at most {MAX_PICK} units per mission`, true) end
					return
				else
					selectedUnits[uid] = true
				end
				render()
			end,
		})
		if u.level ~= nil and InventoryControls then
			InventoryControls.MakeLevelLabel(tile, `Lv.{u.level}`)
		end
		if blocked then addDim(tile, blocked) end
	end
end

local function buildOutNow(main: Instance, res: any)
	local away = {}
	for _, u in res.units or {} do
		if u.away then table.insert(away, u) end
	end
	if #away == 0 then return end
	local strip = Instance.new("ScrollingFrame")
	strip.Name = "OutNow"
	strip.Size = UDim2.new(1, 0, 0, STRIP_H)
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.ScrollBarThickness = 0
	strip.ScrollingDirection = Enum.ScrollingDirection.X
	strip.AutomaticCanvasSize = Enum.AutomaticSize.X
	strip.CanvasSize = UDim2.new()
	strip.LayoutOrder = 20
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = strip
	local head = makeText(nil, "Out now:", Theme.Text.Small(), Theme.Colors.TextGold, true)
	head.Size = UDim2.new(0, 0, 1, 0)
	head.AutomaticSize = Enum.AutomaticSize.X
	head.LayoutOrder = 0
	head.Parent = strip
	local done = tonumber(res.battlesCompleted) or 0
	for i, u in away do
		local left = if tonumber(u.returnBattle) then math.max(1, u.returnBattle - done) else nil
		-- Tap target (Recall, 2026-11-12): a pill picks its unit's mission; every pill of the
		-- picked mission is outlined gold. Tap-only, no hover colour (rule 243).
		local mid = u.awayMissionId
		local isPicked = mid ~= nil and mid == selectedRecall
		local pill = Instance.new("TextButton")
		pill.Name = `Away_{u.id}`
		pill.AutoButtonColor = false
		pill.Font = Theme.Font.Primary
		pill.TextSize = Theme.Text.Small()
		pill.TextColor3 = Theme.Colors.TextPrimary
		pill.Text = if u.awayReason == "dungeon" then `{u.name}  ·  Exploring a dungeon` else `{u.name}  ·  {if left then battles(left) .. " left" else "away"}`
		pill.Size = UDim2.new(0, 0, 1, 0) -- full strip height = 44 px touch target
		pill.AutomaticSize = Enum.AutomaticSize.X
		pill.BackgroundColor3 = Theme.Colors.PanelRaised
		pill.BackgroundTransparency = 0
		pill.BorderSizePixel = 0
		pill.LayoutOrder = i
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.Parent = pill
		local corner = Instance.new("UICorner")
		corner.CornerRadius = Theme.CornerRadius.sm
		corner.Parent = pill
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = if isPicked then Theme.Colors.TextGold else Theme.Colors.Border
		stroke.Thickness = if isPicked then Theme.ItemTile.SelectedStrokeThickness else Theme.ItemTile.StrokeThickness
		stroke.Parent = pill
		if mid then
			pill.Activated:Connect(function() -- dies with the pill on re-render (PRF-004)
				selectedRecall = if selectedRecall == mid then nil else mid
				render()
			end)
		end
		pill.Parent = strip
	end
	strip.Parent = main
end

-- LEFT: info line, selected mission, unit grid, "Out now:" strip.
local function buildMain(res: any, st: any)
	local main = screen.Main
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = main
	addLine(main, 1, `Slots {st.slotsUsed}/{st.slotCap}   ·   Fee {st.fee}g per mission   ·   Keep 1 unit home`,
		Theme.Text.Small(), Theme.Colors.TextSecondary)
	local m = st.selected
	if m then
		addLine(main, 2, missionName(m), Theme.Text.Heading(), Theme.Colors.TextGold, true)
		addLine(main, 3, `Tier {m.tier}  ·  back after {battles(m.duration or 1)}`, Theme.Text.Small(), Theme.Colors.TextSecondary)
		addLine(main, 4, `Reward: {rewardText(m)}   +{m.xp or 0} XP per unit`, Theme.Text.Body(), Theme.Colors.TextPrimary, true)
		addLine(main, 5, `{st.nPicked} selected  ·  {st.homeCount - st.nPicked} stay home`, Theme.Text.Small(), Theme.Colors.TextSecondary)
	else
		addLine(main, 2, "Pick a mission on the right, then tap the units to send.", Theme.Text.Body(), Theme.Colors.TextSecondary)
	end
	buildOutNow(main, res)
	-- Height left for the grid = Main minus everything above / below it (UI-001 hint).
	local usedH, rows = 0, 0
	for _, ch in main:GetChildren() do
		if ch:IsA("GuiObject") then
			usedH += ch.AbsoluteSize.Y
			rows += 1
		end
	end
	local hint = main.AbsoluteSize.Y - usedH - list.Padding.Offset * (rows + 1)
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Size = UDim2.fromScale(1, 0)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 4
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.LayoutOrder = 10
	local flex = Instance.new("UIFlexItem") -- grid fills the height between the notes and the strip
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = grid
	buildUnitGrid(grid, res, st, hint)
	grid.Parent = main
end

local function missionCard(parent: Instance, m: any, order: number, isSelected: boolean)
	local card = Instance.new("TextButton")
	card.Name = `Mission_{m.missionId}`
	card.Text = ""
	card.AutoButtonColor = false -- tap-only, no hover colour (rule 243)
	card.Size = UDim2.new(1, 0, 0, CARD_H)
	card.BackgroundColor3 = if isSelected then Theme.ItemTile.SelectedBgColor else Theme.Colors.PanelRaised
	card.BackgroundTransparency = if isSelected then Theme.ItemTile.SelectedBgTransparency else 0
	card.BorderSizePixel = 0
	card.LayoutOrder = order
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.ItemTile.CornerRadius)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = if isSelected then Theme.Colors.TextGold else Theme.Colors.Border
	stroke.Thickness = if isSelected then Theme.ItemTile.SelectedStrokeThickness else Theme.ItemTile.StrokeThickness
	stroke.Parent = card
	local name = makeText(nil, missionName(m), Theme.Text.Body(), Theme.Colors.TextPrimary, true)
	name.Size = UDim2.new(1, -12, 0.5, 0)
	name.Position = UDim2.fromOffset(6, 2)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Parent = card
	local sub = makeText(nil, `{rewardText(m)}  ·  Tier {m.tier}  ·  {battles(m.duration or 1)}`,
		Theme.Text.Small(), Theme.Colors.TextSecondary)
	sub.Size = UDim2.new(1, -12, 0.5, -2)
	sub.Position = UDim2.new(0, 6, 0.5, 0)
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	sub.Parent = card
	local mid = m.missionId
	card.Activated:Connect(function()
		if selectedMission == mid then return end
		selectedMission = mid
		render()
	end)
	card.Parent = parent
end

-- RIGHT: pending note + mission cards.
local function buildSide(res: any, st: any)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Missions"
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 2)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 2)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = scroll
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = scroll
	if st.nStaged > 0 then
		addLine(scroll, 0, `Pending: {st.nStaged} dispatch(es), -{st.stagedFee}g. Confirm or discard when you leave (Back).`,
			Theme.Text.Small(), Theme.Colors.Warning)
	end
	if #st.missions == 0 then
		addLine(scroll, 1, "No missions available (all queued, or none left until the next battle).",
			Theme.Text.Small(), Theme.Colors.TextSecondary)
	end
	if st.slotsUsed >= st.slotCap then
		addLine(scroll, 2, "All dispatch slots are in use (queued or active).",
			Theme.Text.Small(), Theme.Colors.TextSecondary)
	end
	for i, m in st.missions do
		missionCard(scroll, m, 10 + i, m.missionId == selectedMission)
	end
	scroll.Parent = screen.Side
end

--------------------------------------------------
-- HELP POPUP (? button)
--------------------------------------------------

local function closeHelp()
	if helpOverlay then
		helpOverlay:Destroy()
		helpOverlay = nil
	end
end

local function openHelp(fee: number)
	if not screen then return end
	closeHelp()
	local overlay = Instance.new("TextButton")
	overlay.Name = "DispatchHelp"
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
	box.Size = UDim2.new(0.8, 0, 0, 0)
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.BackgroundColor3 = Theme.Colors.PanelRaised
	box.BorderSizePixel = 0
	local maxW = Instance.new("UISizeConstraint")
	maxW.MaxSize = Vector2.new(HELP_MAX_W, math.huge)
	maxW.Parent = box
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.CornerRadius.md
	corner.Parent = box
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.Colors.Border
	stroke.Thickness = Theme.BorderThickness.Default
	stroke.Parent = box
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = box
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = box

	addLine(box, 1, "What is Dispatch?", Theme.Text.Heading(), Theme.Colors.TextGold, true)
	local bullets = {
		"Send units on missions while the rest of your guild fights. They miss battles until they come back.",
		"Each mission says how long it lasts, e.g. \"back after 3 battles\". A very long battle can count as 2.",
		"When they return, every unit sent earns the mission's XP, and the mission pays the material shown on it. Up to 3 units per mission.",
		`Each mission costs {fee} gold. Your Renown Rank sets how many missions can run at once.`,
		"At least one unit must stay home. Units away still recover HP after your victories.",
		"You can recall a mission early from the Out now list. The units return with no reward.",
		"Upgrade the Dispatch at the Guild Hall for lower fees and more missions.", -- DISPATCH-HELP-UPGRADE (approved 2026-11-18)
	}
	for i, b in bullets do
		addLine(box, 1 + i, `•  {b}`, Theme.Text.Body(), Theme.Colors.TextPrimary)
	end
	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.Size = UDim2.new(1, 0, 0, GuildScreen.ROW_H)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.LayoutOrder = 10
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = row
	Theme.MakeBarButton(row, "Got it", "Primary", closeHelp, {
		name = "Btn_HelpClose", minHeight = GuildScreen.ROW_H, layoutOrder = 1,
	})
	row.Parent = box
	box.Parent = overlay
	overlay.Parent = screen.Gui -- parent last (NET-004)
	helpOverlay = overlay
end

--------------------------------------------------
-- BUTTONS (one row, lower right)
--------------------------------------------------

local function send(st: any)
	local c = ctx
	local m = st.selected
	if not c or not m then return end
	local ids: { string } = {}
	for uid in selectedUnits do table.insert(ids, uid) end
	table.sort(ids)
	-- Same guards as the old Dispatch page; the server re-checks everything on Confirm.
	if #ids < 1 then c.setStatus("Pick at least one unit", true) return end
	if #ids > MAX_PICK then c.setStatus(`Send at most {MAX_PICK} units per mission`, true) return end
	if st.homeCount - #ids < 1 then c.setStatus("Keep at least one unit home", true) return end
	if st.slotsUsed >= st.slotCap then c.setStatus("No free dispatch slot", true) return end
	c.queue(m.missionId, ids, st.fee)
	selectedMission = nil
	selectedUnits = {}
	c.setStatus(`Dispatch queued ({#ids} unit(s), {st.fee}g). Confirm when you leave (Back).`)
	render()
end

-- Recall (USER RULING 2026-11-12): confirm, then the server ends the mission now. No reward,
-- no fee refund. Live action: the server answer is shown, then the board is re-fetched.
local function recall(st: any)
	local c = ctx
	local u = st.recallUnit
	if not c or not screen or not u or not u.awayMissionId then return end
	if not c.recall then
		c.setStatus("Recall is not available", true)
		return
	end
	local mid: string = u.awayMissionId
	local name = awayMissionName(u)
	screen.Prompt(`Recall {name}? All units on it return now. No reward, and the fee is not refunded.`,
		"Recall", "Danger", function() -- 2026-11-18: destructive (darker check)
			local recallFn = c.recall
			local res = if recallFn then recallFn(mid) else nil
			if res then
				selectedRecall = nil
				local n = if type(res.returnedUnitIds) == "table" then #res.returnedUnitIds else 0
				c.setStatus(`Recalled {name}: {n} unit(s) back home.`)
				print(`[DispatchScreen] Recalled {mid} ({n} unit(s))`)
			end
			render()
		end)
end

local function buildButtons(st: any?)
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
	local fee = if st then st.fee else 0
	local hasPick = selectedMission ~= nil or next(selectedUnits) ~= nil or selectedRecall ~= nil
	local canSend = st ~= nil and st.selected ~= nil and st.nPicked > 0 and st.slotsUsed < st.slotCap
	-- Recall shows only while an away mission is picked in the Out now strip (approved label).
	if st and st.recallUnit then
		Theme.MakeBarButton(row, "Recall", "Primary", function() recall(st) end, {
			name = "Btn_Recall", minHeight = GuildScreen.ROW_H, layoutOrder = 0,
		})
	end
	iconButton(row, "Help", "Btn_Help", 1, true, function()
		openHelp(fee)
	end)
	iconButton(row, "X", "Btn_Cancel", 2, hasPick, function()
		selectedMission = nil
		selectedUnits = {}
		selectedRecall = nil
		render()
	end)
	iconButton(row, "Confirm", "Btn_Send", 3, canSend, function()
		if st then send(st) end
	end)
	iconButton(row, "Back", "Btn_BACK", 4, true, function()
		c.requestBack(DispatchScreen.Close)
	end)
	row.Parent = screen.Buttons
end

render = function()
	local c = ctx
	if not c or not screen or not isOpen then return end
	screen.Clear("Dispatch") -- same screen keeps the unit grid's scroll position
	local res = c.getBoard() -- nil on a server error (the error is shown in the status line)
	if not res then
		local list = Instance.new("UIListLayout")
		list.Parent = screen.Main
		addLine(screen.Main, 1, "The dispatch board is not available right now.", Theme.Text.Body(), Theme.Colors.TextSecondary)
		buildButtons(nil)
		return
	end
	local st = derive(res)
	buildMain(res, st)
	buildSide(res, st)
	buildButtons(st)
end

--------------------------------------------------
-- PUBLIC (same shape as the other guild screens)
--------------------------------------------------

function DispatchScreen.Init(c: Context)
	ctx = c
end

function DispatchScreen.IsOpen(): boolean
	return isOpen
end

-- ScreenGui while open (the opener parents its Confirm/Discard prompt here), else nil.
function DispatchScreen.GetGui(): ScreenGui?
	return if isOpen and screen then screen.Gui else nil
end

function DispatchScreen.Open()
	local c = ctx
	if not c then
		warn("[DispatchScreen] Open called before Init")
		return
	end
	if not screen then
		screen = GuildScreen.Create({ name = "DispatchScreen", title = "DISPATCH", parent = c.parent })
		screen.SetButtonRows(BUTTON_ROWS)
	end
	selectedMission = nil
	selectedUnits = {}
	selectedRecall = nil
	isOpen = true
	screen.SetStatus("")
	screen.Show()
	render()
	print("[DispatchScreen] Opened")
end

-- Back path: hide and hand control back to the opener.
function DispatchScreen.Close()
	if not isOpen then return end
	isOpen = false
	closeHelp()
	if screen then screen.ClosePrompt() end
	if screen then screen.Hide() end
	local c = ctx
	if c then c.onClosed() end
	print("[DispatchScreen] Closed")
end

-- Forced hide (menu closed by the server): no onClosed, the opener is going away too.
function DispatchScreen.Hide()
	if not isOpen then return end
	isOpen = false
	closeHelp()
	if screen then screen.ClosePrompt() end
	if screen then screen.Hide() end
end

function DispatchScreen.Render()
	render()
end

function DispatchScreen.SetGold(text: string)
	if screen then screen.SetGold(text) end
end

function DispatchScreen.SetStatus(text: string, isError: boolean?)
	if screen then screen.SetStatus(text, isError) end
end


return table.freeze(DispatchScreen)
