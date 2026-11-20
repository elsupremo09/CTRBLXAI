--!strict
-- LoadoutConsumables.lua
-- CTRBLXAI | Loadout screen: consumable grid + consumable detail / slot picker / equipped detail.
-- Split out of LoadoutScreen.lua (2026-11-10, ARC-005 file-size split, step 1 of 10).
-- Behaviour unchanged. Host state it shares (inventory panel, equipped sub-tab, the one open
-- detail overlay) is reached through `ctx` from LoadoutScreen.Init -- no require of
-- LoadoutScreen, so no circular dependency (ARC rules: dependency injection).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CTRBLXAI_UI = ReplicatedStorage:WaitForChild("CTRBLXAI", 10):WaitForChild("UI", 10)
local Theme       = require(CTRBLXAI_UI:WaitForChild("Theme", 10))
local MockData    = require(CTRBLXAI_UI:WaitForChild("MockLoadoutData", 10))
local BattleEvents = require(ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
	:WaitForChild("Remotes", 10):WaitForChild("BattleEvents", 10))
local ConsumableData = require(ReplicatedStorage:WaitForChild("Content", 10)
	:WaitForChild("ConsumableData", 10))
-- Dungeon map use (silver/Bag step 3, 2026-11-16; rule 266): which items work on the map + the dungeon remote.
local MapUse: any = require(ReplicatedStorage:WaitForChild("CTRBLXAI", 10):WaitForChild("Shared", 10)
	:WaitForChild("DungeonMapUse", 10))
local GuildEvents: any = require(ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
	:WaitForChild("Remotes", 10):WaitForChild("GuildEvents", 10))
local TipController: any = nil -- New-player tips (2026-11-19): guarded, a missing module never breaks this screen
do
	local okTip, tipMod = pcall(function() return (require :: any)(CTRBLXAI_UI:WaitForChild("TipController", 10)) end)
	if okTip then TipController = tipMod else warn("[LoadoutConsumables] tips unavailable: " .. tostring(tipMod)) end
end

local LoadoutConsumables: any = {}

local ctx: any = nil
-- Host helpers, bound in Init (thin wrappers so a later reassignment in the host is seen).
local function clearChildren(...) return ctx.clearChildren(...) end
local function makeLabel(...) return ctx.makeLabel(...) end
local function pad(...) return ctx.pad(...) end
local function getPlayerGui() return ctx.getPlayerGui() end
local function closeDetail() return ctx.closeDetail() end
local function buildDetailHeader(...) return ctx.buildDetailHeader(...) end
local function buildEquippedLoadout(...) return ctx.buildEquippedLoadout(...) end

local buildConsumableGrid, openConsumableDetail, openConsumableSlotPicker, openEquippedConsumableDetail

--------------------------------------------------
-- CONSUMABLE GRID & DETAIL (inventory-style browse)
--------------------------------------------------

local CONS_CATEGORY_ORDER = { "All", "Recovery", "Support", "Utility", "Control", "Damage", "Environment", "Deployable" }
local CONS_CATEGORY_COLORS = {
	Recovery = Color3.fromRGB(80, 220, 120),
	Support = Color3.fromRGB(100, 180, 240),
	Utility = Color3.fromRGB(200, 180, 100),
	Control = Color3.fromRGB(200, 120, 200),
	Damage = Color3.fromRGB(220, 80, 80),
	Environment = Color3.fromRGB(120, 180, 80),
	Deployable = Color3.fromRGB(180, 140, 100),
}
-- Read-only export (2026-11-09): the battle inspector's Gears tab consumable cards use the same
-- category colours (DAT-001: one colour table, no copy). Callers must not modify it.
LoadoutConsumables.ConsCategoryColors = CONS_CATEGORY_COLORS

local consFilter = "All"
local consSearch = ""

buildConsumableGrid = function()
	if not ctx.getInventoryPanel() then return end
	clearChildren(ctx.getInventoryPanel())
	pad(ctx.getInventoryPanel(), 8, 8, 8, 8)
	local ctrlRow = Instance.new("Frame")
	ctrlRow.Size = UDim2.new(1, 0, 0, 24)
	ctrlRow.Position = UDim2.new(0, 0, 0, 0)
	ctrlRow.BackgroundTransparency = 1
	ctrlRow.Parent = ctx.getInventoryPanel()
	local ctrlLayout = Instance.new("UIListLayout", ctrlRow)
	ctrlLayout.FillDirection = Enum.FillDirection.Horizontal
	ctrlLayout.Padding = UDim.new(0, 3)
	ctrlLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	local search = Instance.new("TextBox")
	search.Size = UDim2.new(1, -90, 1, 0)
	search.BackgroundColor3 = Theme.Colors.Surface
	search.BackgroundTransparency = 0.2
	search.Font = Theme.Font.Primary
	search.TextSize = Theme.Text.Small()
	search.TextColor3 = Theme.Colors.TextPrimary
	search.PlaceholderText = "Search..."
	search.PlaceholderColor3 = Theme.Colors.TextDisabled
	search.Text = consSearch
	search.BorderSizePixel = 0
	search.ClearTextOnFocus = false
	search.LayoutOrder = 1
	search.Parent = ctrlRow
	Instance.new("UICorner", search).CornerRadius = UDim.new(0, 3)
	search.FocusLost:Connect(function()
		consSearch = search.Text
		buildConsumableGrid()
	end)
	local catLabel = consFilter == "All" and "Type" or consFilter
	local catBtn = Instance.new("TextButton")
	catBtn.Size = UDim2.new(0, 85, 1, 0)
	catBtn.BackgroundColor3 = Theme.Colors.Surface
	catBtn.BackgroundTransparency = 0.2
	catBtn.Font = Theme.Font.PrimaryBold
	catBtn.TextSize = Theme.Text.Small()
	catBtn.TextColor3 = Theme.Colors.TextPrimary
	catBtn.Text = catLabel
	catBtn.BorderSizePixel = 0
	catBtn.LayoutOrder = 2
	catBtn.Parent = ctrlRow
	Instance.new("UICorner", catBtn).CornerRadius = UDim.new(0, 3)
	catBtn.Activated:Connect(function()
		local curIdx = 1
		for idx, cat in ipairs(CONS_CATEGORY_ORDER) do
			if cat == consFilter then curIdx = idx; break end
		end
		curIdx = (curIdx % #CONS_CATEGORY_ORDER) + 1
		consFilter = CONS_CATEGORY_ORDER[curIdx]
		buildConsumableGrid()
	end)
	local allIds = ConsumableData.GetAllIds()
	local items = {}
	for _, cid in ipairs(allIds) do
		local def = ConsumableData.GetById(cid)
		-- Parked items (DB Status PARKED, user 2026-10-27) are not offered.
		-- Ownership (2026-11-03): only consumables the player owns a loose copy of are listed.
		local ownedN = (MockData.ConsOwned or {})[cid] or 0
		if def and not def.parked and ownedN > 0 then
			local cat = def.category or "?"
			if consFilter ~= "All" and cat ~= consFilter then continue end
			if consSearch ~= "" and not string.find(string.lower(def.name or ""), string.lower(consSearch), 1, true) then continue end
			table.insert(items, { id = cid, name = def.name or cid, category = cat, owned = ownedN,
				maxCharges = def.maxCharges or 1, tier = def.tier or "Common",
				rtCost = def.rtCost or 0, range = def.range or 0,
				targetRules = def.targetRules or "", pattern = def.pattern or "",
				effectFormula = def.effectFormula or "", icon = def.icon or nil,
				-- Player-facing text (display only). nil until authored in DB (2026-10-30).
				displayText = def.displayText, displayDetail = def.displayDetail,
				economy = def.economy or "", profile = def.profile or "",
				duration = def.duration or "Instant", scalingBasis = def.scalingBasis or "",
				tags = def.tags or {} })
		end
	end
	local catOrder = {}
	for idx, cat in ipairs(CONS_CATEGORY_ORDER) do catOrder[cat] = idx end
	table.sort(items, function(a, b)
		local ca = catOrder[a.category] or 99
		local cb = catOrder[b.category] or 99
		if ca ~= cb then return ca < cb end
		return a.name < b.name
	end)
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Size = UDim2.new(1, 0, 1, -30)
	scrollFrame.Position = UDim2.new(0, 0, 0, 28)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 3
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = ctx.getInventoryPanel()
	-- Cell sizing IDENTICAL to the Gears/Skills grids so consumable tiles are the same
	-- size and shape across every inventory screen (2026-10-20 uniformity fix). Previously
	-- this used a divergent copy (GAP 3, no -16 padding, 200px height fallback) which made
	-- the tiles smaller. Constants, containerW-16, <100 fallbacks (400/300), GAP 4, ASPECT
	-- 1.2 and CellPadding (0,4,0,3) now all match buildItemGrid exactly.
	-- 2026-11-07: the formula itself now lives once in Theme.ItemTileCell (DAT-001).
	local cellW, cellH = Theme.ItemTileCell(scrollFrame.AbsoluteSize.Y)
	local gridLayout = Instance.new("UIGridLayout", scrollFrame)
	gridLayout.CellSize = UDim2.new(0, cellW, 0, cellH)
	gridLayout.CellPadding = UDim2.new(0, 4, 0, 3)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	for idx, ci in ipairs(items) do
		local catColor = CONS_CATEGORY_COLORS[ci.category] or Theme.Colors.TextSecondary
		-- Shared inventory-tile builder (2026-10-20): the approved tile look now lives in ONE
		-- place, Theme.MakeItemTile, so consumables / merchant screens / any future inventory
		-- grid render identically. This replaces the inline tile build that mirrored the Gears
		-- tile; the visual is unchanged (category accent, inset icon, top-right count, name strip).
		Theme.MakeItemTile({
			parent = scrollFrame,
			accentColor = catColor,
			cellW = cellW,
			icon = ci.icon,
			name = ci.name,
			countText = "x" .. (ci.owned or 0), -- owned copies (charges shown in the detail)
			layoutOrder = idx,
			-- 2026-11-09 user request: Skills/Augments-size square portrait + two-row name.
			portrait = true,
			onClick = function() openConsumableDetail(ci) end,
		})
	end
	if #items == 0 then
		makeLabel(ctx.getInventoryPanel(), { Text = "You don't own any consumables yet.",
			Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, 40),
			TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextSecondary })
	end
	makeLabel(ctx.getInventoryPanel(), { Text = string.format("Showing: %d owned", #items),
		Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -14),
		TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextDisabled,
		TextXAlignment = Enum.TextXAlignment.Left })
end

openConsumableDetail = function(ci)
	closeDetail()
	local unit = MockData.GetSelectedUnit()
	if not unit then return end
	local detailOverlay = Instance.new("ScreenGui"); ctx.setDetailOverlay(detailOverlay)
	detailOverlay.Name = "ConsDetail"; detailOverlay.DisplayOrder = 110
	detailOverlay.ResetOnSpawn = false; detailOverlay.Parent = getPlayerGui()
	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.Overlay; backdrop.BackgroundTransparency = 0.5
	backdrop.Text = ""; backdrop.BorderSizePixel = 0
	backdrop.Parent = detailOverlay; backdrop.Activated:Connect(closeDetail)
	local panel = Theme.MakePanel("ConsDetail", UDim2.new(0.55, 0, 0.9, 0),
		UDim2.new(0, 8, 0.05, 0), Vector2.new(0, 0), detailOverlay)
	panel.ClipsDescendants = true; pad(panel, 10, 10, 10, 10)
	local catColor = CONS_CATEGORY_COLORS[ci.category] or Theme.Colors.TextSecondary
	local hdrH = buildDetailHeader(panel, {
		iconImage = (ci.icon and string.find(ci.icon, "rbxassetid://")) and ci.icon or nil,
		iconText = "[C]", name = ci.name,
		subtitleText = ci.category .. " | " .. ci.economy .. " | " .. ci.profile,
		subtitleColor = catColor, tags = ci.tags, tagColor = catColor,
		description = ci.displayText or ci.effectFormula })
	-- Stats start below the header, which grows with a long description (2026-11-01).
	local yOff = math.max(100, hdrH + 30)
	local function addStatRow(label, value)
		makeLabel(panel, { Text = label, Size = UDim2.new(0.4, 0, 0, 16), Position = UDim2.new(0, 0, 0, yOff),
			TextSize = Theme.Text.Small(), Font = Theme.Font.Primary,
			TextColor3 = Theme.Colors.TextSecondary, TextXAlignment = Enum.TextXAlignment.Left })
		makeLabel(panel, { Text = tostring(value), Size = UDim2.new(0.55, 0, 0, 16), Position = UDim2.new(0.42, 0, 0, yOff),
			TextSize = Theme.Text.Small(), Font = Theme.Font.PrimaryBold,
			TextColor3 = Theme.Colors.TextPrimary, TextXAlignment = Enum.TextXAlignment.Left })
		yOff = yOff + 18
	end
	local div = Instance.new("Frame"); div.Size = UDim2.new(0.9, 0, 0, 1)
	div.Position = UDim2.new(0.05, 0, 0, yOff); div.BackgroundColor3 = Theme.Colors.TextDisabled
	div.BackgroundTransparency = 0.5; div.BorderSizePixel = 0; div.Parent = panel
	yOff = yOff + 6
	addStatRow("Charges:", tostring(ci.maxCharges)); addStatRow("RT Cost:", tostring(ci.rtCost))
	addStatRow("Range:", tostring(ci.range)); addStatRow("Target:", ci.targetRules)
	addStatRow("Pattern:", ci.pattern); addStatRow("Duration:", ci.duration)
	addStatRow("Scaling:", ci.scalingBasis)
	-- Approved "more info" line (exact numbers), Loadout item details only (user 2026-10-30).
	if ci.displayDetail and ci.displayDetail ~= "" then
		local dl = makeLabel(panel, { Text = ci.displayDetail, Size = UDim2.new(0.97, 0, 0, 0),
			Position = UDim2.new(0, 0, 0, yOff + 4), TextSize = Theme.Text.Small(), Font = Theme.Font.Primary,
			TextColor3 = Theme.Colors.TextSecondary, TextWrapped = true })
		dl.TextYAlignment = Enum.TextYAlignment.Top
		-- Grow to fit the wrapped text so long lines are never cut off (2026-10-30).
		dl.TextTruncate = Enum.TextTruncate.None
		dl.AutomaticSize = Enum.AutomaticSize.Y
		yOff = yOff + 60
	end
	local fb = Theme.FooterBar
	-- Dungeon mode Bag tag (SB-19 / SB-20 retired 2026-11-16: BagTagText returns nil), bottom-left beside the buttons.
	local bagTagText = MockData.BagTagText("consumables", ci.id)
	if bagTagText then
		local tl = makeLabel(detailOverlay, { Text = bagTagText, Size = UDim2.new(0, 220, 0, fb.BTN_H),
			Position = UDim2.new(0, fb.PAD, 1, -fb.PAD), TextSize = math.max(10, Theme.Text.Small()), Font = Theme.Font.PrimaryBold,
			TextColor3 = Theme.Colors.TextSecondary, TextXAlignment = Enum.TextXAlignment.Left })
		tl.AnchorPoint = Vector2.new(0, 1); tl.Name = "BagTag"
	end
	-- Dungeon mode (step 3): a Bag copy of a heal / MP / revive item gets "Use" (SB-23) on the selected unit.
	local dungeon = MockData.DungeonMode == true
	local inBag = dungeon and ((MockData.MapUsable or {})[ci.id] or 0) > 0
	local canUse = inBag and MapUse.Get(ci.id) ~= nil
	local nBtn = if canUse then 3 else 2
	local btnBar = Instance.new("Frame"); btnBar.Name = "ConsBtnBar"
	btnBar.Size = UDim2.new(0, fb.BTN_W * nBtn + fb.BTN_GAP * (nBtn - 1) + fb.PAD, 0, fb.BTN_H)
	btnBar.Position = UDim2.new(1, -fb.PAD, 1, -fb.PAD); btnBar.AnchorPoint = Vector2.new(1, 1)
	btnBar.BackgroundTransparency = 1; btnBar.Parent = detailOverlay
	local btnLayout = Instance.new("UIListLayout", btnBar)
	btnLayout.FillDirection = Enum.FillDirection.Horizontal
	btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	btnLayout.Padding = UDim.new(0, fb.BTN_GAP)
	local backBtn = Theme.MakeButton(btnBar, "BACK", "Secondary"); backBtn.LayoutOrder = 2
	backBtn.Activated:Connect(closeDetail)
	local equipBtn = Theme.MakeButton(btnBar, "EQUIP", "Primary"); equipBtn.LayoutOrder = 1
	equipBtn.Activated:Connect(function() closeDetail(); openConsumableSlotPicker(unit.id, ci) end)
	if inBag then
		-- Status line above the buttons: SB-24 for battle-only items, or the server's refusal after Use.
		local note = makeLabel(panel, { Text = if canUse then "" else "Only usable in battle.", -- SB-24
			Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -(fb.BTN_H + fb.PAD + 18)),
			TextSize = math.max(10, Theme.Text.Small()), Font = Theme.Font.Primary,
			TextColor3 = Theme.Colors.TextSecondary, TextXAlignment = Enum.TextXAlignment.Left })
		note.Name = "MapUseNote"
		if canUse then
			local useBtn = Theme.MakeButton(btnBar, "Use", "Primary"); useBtn.LayoutOrder = 0 -- SB-23
			useBtn.Name = "Btn_Use"
			useBtn.Activated:Connect(function()
				local ok, res = pcall(function()
					return GuildEvents.DungeonAction:InvokeServer({ action = "UseItem", consumableId = ci.id, unitId = unit.id })
				end)
				if not ok or type(res) ~= "table" or res.ok == false then
					note.Text = if ok and type(res) == "table" and type(res.error) == "string" then res.error else "Something went wrong. Try again."
					note.TextColor3 = Theme.Colors.Danger
					return
				end
				closeDetail()
				if ctx.reload then ctx.reload() end
			end)
		end
	end
end

openConsumableSlotPicker = function(unitId, ci)
	closeDetail()
	local unit = MockData.GetSelectedUnit()
	if not unit then return end
	local detailOverlay = Instance.new("ScreenGui"); ctx.setDetailOverlay(detailOverlay); detailOverlay.Name = "ConsSlotPicker"
	detailOverlay.DisplayOrder = 115; detailOverlay.ResetOnSpawn = false
	detailOverlay.Parent = getPlayerGui()
	local backdrop = Instance.new("TextButton"); backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.Overlay; backdrop.BackgroundTransparency = 0.5
	backdrop.Text = ""; backdrop.BorderSizePixel = 0; backdrop.Parent = detailOverlay
	backdrop.Activated:Connect(closeDetail)
	local popup = Theme.MakePanel("ConsSlotPicker", UDim2.new(0, 260, 0, 240),
		UDim2.new(0.5, 0, 0.5, 0), Vector2.new(0.5, 0.5), detailOverlay)
	popup.ClipsDescendants = true; pad(popup, 10, 10, 10, 10)
	makeLabel(popup, { Text = "Equip " .. ci.name .. " to slot:", Size = UDim2.new(1, 0, 0, 18),
		Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Body(), TextColor3 = Theme.Colors.TextGold })
	local scroll = Instance.new("ScrollingFrame"); scroll.Size = UDim2.new(1, 0, 1, -44)
	scroll.Position = UDim2.new(0, 0, 0, 22); scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 3
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0); scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = popup
	local sLayout = Instance.new("UIListLayout", scroll); sLayout.Padding = UDim.new(0, 3)
	sLayout.SortOrder = Enum.SortOrder.LayoutOrder
	for slotIdx = 1, 6 do
		local slotKey = "Cons" .. slotIdx
		local locked = MockData.IsConsSlotLocked(unitId, slotKey)
		local existing = MockData.GetEquipped(unitId, slotKey)
		local rowBtn = Instance.new("TextButton"); rowBtn.Size = UDim2.new(1, 0, 0, 28)
		rowBtn.BackgroundColor3 = locked and Theme.Colors.Background or Theme.Colors.PanelRaised
		rowBtn.BackgroundTransparency = locked and 0.5 or 0.2
		rowBtn.BorderSizePixel = 0; rowBtn.Text = ""; rowBtn.AutoButtonColor = not locked
		rowBtn.LayoutOrder = slotIdx; rowBtn.Parent = scroll
		Instance.new("UICorner", rowBtn).CornerRadius = UDim.new(0, 4)
		local slotText = "Slot " .. slotIdx
		if locked then slotText = slotText .. "  [LOCKED]"
		elseif existing then slotText = slotText .. ": " .. (existing.name or "?") .. " (replace)"
		else slotText = slotText .. ": Empty" end
		makeLabel(rowBtn, { Text = slotText, Size = UDim2.new(1, -8, 1, 0), Position = UDim2.new(0, 4, 0, 0),
			Font = Theme.Font.Primary, TextSize = Theme.Text.Small(),
			TextColor3 = locked and Theme.Colors.TextDisabled or Theme.Colors.TextPrimary })
		if locked then
			-- New-player tip: first tap on a locked slot (TIP-LOCK-01). Display only, no request.
			rowBtn.Activated:Connect(function() if TipController then TipController.Trigger("TIP-LOCK-01") end end)
		else
			rowBtn.Activated:Connect(function()
				local result = BattleEvents.RequestEquipConsumable:InvokeServer(unitId, slotIdx, ci.id)
				if not (result and result.ok) then
					-- Refused: show the reason on the row (e.g. the item there is partly used).
					local reasonLabel = rowBtn:FindFirstChildWhichIsA("TextLabel")
					if reasonLabel then reasonLabel.Text = "Slot " .. slotIdx .. ": " .. tostring(result and result.reason or "Refused") end
					warn("[Loadout] Equip refused: " .. tostring(result and result.reason))
					return
				end
				closeDetail()
				if result and result.ok then
					if TipController then TipController.Trigger("TIP-CON-01") end -- new-player tip (first consumable equipped)
					-- Mirror the server's owned-copy change (one taken, the replaced one returned).
					local own = MockData.ConsOwned
					local prev = MockData.Equipped[unitId] and MockData.Equipped[unitId][slotKey]
					local prevId = type(prev) == "table" and prev.consumableId or nil
					if own and prevId ~= ci.id then
						own[ci.id] = math.max(0, (own[ci.id] or 0) - 1)
						if own[ci.id] == 0 then own[ci.id] = nil end
						if prevId then own[prevId] = (own[prevId] or 0) + 1 end
					end
					if not MockData.Equipped[unitId] then MockData.Equipped[unitId] = {} end
					MockData.Equipped[unitId][slotKey] = { id = ci.id, consumableId = ci.id, name = ci.name,
						cat = "Consumable", sub = ci.category, icon = ci.icon or "[C]", qty = ci.maxCharges,
						effect = ci.effectFormula }
					buildEquippedLoadout()
					if ctx.getEquippedTab() == "cons" then buildConsumableGrid() end
				end
			end)
		end
	end
	Theme.MakeIconButton(popup, "Back", closeDetail, {
		name = "Btn_Cancel",
		size = UDim2.new(0, 18, 0, 18),
		position = UDim2.new(0.5, 0, 1, -20),
		anchor = Vector2.new(0.5, 0),
	})
end

openEquippedConsumableDetail = function(unitId, slotIdx, item)
	closeDetail()
	local def = ConsumableData.GetById(item.consumableId or item.id)
	local ci = { id = item.consumableId or item.id, name = item.name or "Unknown",
		category = (def and def.category) or item.sub or "?",
		maxCharges = (def and def.maxCharges) or item.qty or 1,
		rtCost = (def and def.rtCost) or 0, range = (def and def.range) or 0,
		targetRules = (def and def.targetRules) or "", pattern = (def and def.pattern) or "",
		effectFormula = (def and def.effectFormula) or item.effect or "",
		displayText = def and def.displayText or nil,
		displayDetail = def and def.displayDetail or nil,
		icon = (def and def.icon) or item.icon or nil,
		economy = (def and def.economy) or "", profile = (def and def.profile) or "",
		duration = (def and def.duration) or "Instant", scalingBasis = (def and def.scalingBasis) or "",
		tags = (def and def.tags) or {} }
	local detailOverlay = Instance.new("ScreenGui"); ctx.setDetailOverlay(detailOverlay); detailOverlay.Name = "ConsEqDetail"
	detailOverlay.DisplayOrder = 110; detailOverlay.ResetOnSpawn = false
	detailOverlay.Parent = getPlayerGui()
	local backdrop = Instance.new("TextButton"); backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.Overlay; backdrop.BackgroundTransparency = 0.5
	backdrop.Text = ""; backdrop.BorderSizePixel = 0; backdrop.Parent = detailOverlay
	backdrop.Activated:Connect(closeDetail)
	local catColor = CONS_CATEGORY_COLORS[ci.category] or Theme.Colors.TextSecondary
	local panel = Theme.MakePanel("ConsEqDetail", UDim2.new(0.55, 0, 0.9, 0),
		UDim2.new(0, 8, 0.05, 0), Vector2.new(0, 0), detailOverlay)
	panel.ClipsDescendants = true; pad(panel, 10, 10, 10, 10)
	local hdrH = buildDetailHeader(panel, {
		iconImage = (ci.icon and string.find(ci.icon, "rbxassetid://")) and ci.icon or nil,
		iconText = "[C]", name = ci.name,
		subtitleText = "Slot " .. slotIdx .. " | " .. ci.category, subtitleColor = catColor,
		tags = ci.tags, tagColor = catColor, description = ci.displayText or ci.effectFormula })
	-- Stats start below the header, which grows with a long description (2026-11-01).
	local yOff = math.max(100, hdrH + 30)
	local function addStatRow(label, value)
		makeLabel(panel, { Text = label, Size = UDim2.new(0.4, 0, 0, 16), Position = UDim2.new(0, 0, 0, yOff),
			TextSize = Theme.Text.Small(), Font = Theme.Font.Primary,
			TextColor3 = Theme.Colors.TextSecondary, TextXAlignment = Enum.TextXAlignment.Left })
		makeLabel(panel, { Text = tostring(value), Size = UDim2.new(0.55, 0, 0, 16), Position = UDim2.new(0.42, 0, 0, yOff),
			TextSize = Theme.Text.Small(), Font = Theme.Font.PrimaryBold,
			TextColor3 = Theme.Colors.TextPrimary, TextXAlignment = Enum.TextXAlignment.Left })
		yOff = yOff + 18
	end
	local div = Instance.new("Frame"); div.Size = UDim2.new(0.9, 0, 0, 1)
	div.Position = UDim2.new(0.05, 0, 0, yOff); div.BackgroundColor3 = Theme.Colors.TextDisabled
	div.BackgroundTransparency = 0.5; div.BorderSizePixel = 0; div.Parent = panel; yOff = yOff + 6
	addStatRow("Charges:", tostring(ci.maxCharges)); addStatRow("RT Cost:", tostring(ci.rtCost))
	addStatRow("Range:", tostring(ci.range)); addStatRow("Target:", ci.targetRules)
	addStatRow("Pattern:", ci.pattern)
	-- Approved "more info" line (exact numbers), Loadout item details only (user 2026-10-30).
	if ci.displayDetail and ci.displayDetail ~= "" then
		local dl = makeLabel(panel, { Text = ci.displayDetail, Size = UDim2.new(0.97, 0, 0, 0),
			Position = UDim2.new(0, 0, 0, yOff + 4), TextSize = Theme.Text.Small(), Font = Theme.Font.Primary,
			TextColor3 = Theme.Colors.TextSecondary, TextWrapped = true })
		dl.TextYAlignment = Enum.TextYAlignment.Top
		-- Grow to fit the wrapped text so long lines are never cut off (2026-10-30).
		dl.TextTruncate = Enum.TextTruncate.None
		dl.AutomaticSize = Enum.AutomaticSize.Y
		yOff = yOff + 60
	end
	local fb = Theme.FooterBar
	local btnBar = Instance.new("Frame"); btnBar.Name = "ConsEqBtnBar"
	btnBar.Size = UDim2.new(0, fb.BTN_W * 2 + fb.BTN_GAP + fb.PAD, 0, fb.BTN_H)
	btnBar.Position = UDim2.new(1, -fb.PAD, 1, -fb.PAD); btnBar.AnchorPoint = Vector2.new(1, 1)
	btnBar.BackgroundTransparency = 1; btnBar.Parent = detailOverlay
	local btnLayout = Instance.new("UIListLayout", btnBar)
	btnLayout.FillDirection = Enum.FillDirection.Horizontal
	btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	btnLayout.Padding = UDim.new(0, fb.BTN_GAP)
	local backBtn = Theme.MakeButton(btnBar, "BACK", "Secondary"); backBtn.LayoutOrder = 2
	backBtn.Activated:Connect(closeDetail)
	local unBtn = Theme.MakeButton(btnBar, "UNEQUIP", "Primary"); unBtn.LayoutOrder = 1
	unBtn.Activated:Connect(function()
		local result = BattleEvents.RequestUnequipConsumable:InvokeServer(unitId, slotIdx)
		if not (result and result.ok) then
			-- Refused (e.g. partly used: refill at base first). Keep the panel open and say why.
			unBtn.Text = if result and result.reason and string.find(result.reason, "partly used", 1, true)
				then "PARTLY USED" else "REFUSED"
			warn("[Loadout] Unequip refused: " .. tostring(result and result.reason))
			return
		end
		closeDetail()
		if result and result.ok then
			local prev = MockData.Equipped[unitId] and MockData.Equipped[unitId]["Cons" .. slotIdx]
			local prevId = type(prev) == "table" and prev.consumableId or nil
			if prevId and MockData.ConsOwned then
				MockData.ConsOwned[prevId] = (MockData.ConsOwned[prevId] or 0) + 1
			end
			if MockData.Equipped[unitId] then MockData.Equipped[unitId]["Cons" .. slotIdx] = nil end
			buildEquippedLoadout()
			if ctx.getEquippedTab() == "cons" then buildConsumableGrid() end
		end
	end)
end


function LoadoutConsumables.Init(c: any)
	ctx = c
end
LoadoutConsumables.BuildGrid = function(...) return buildConsumableGrid(...) end
LoadoutConsumables.OpenDetail = function(...) return openConsumableDetail(...) end
LoadoutConsumables.OpenSlotPicker = function(...) return openConsumableSlotPicker(...) end
LoadoutConsumables.OpenEquippedDetail = function(...) return openEquippedConsumableDetail(...) end

return LoadoutConsumables
