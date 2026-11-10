--!strict
-- LoadoutGears.lua
-- CTRBLXAI | Loadout screen GEARS tab: equipped loadout panel (gear / consumable slots) and the
-- inventory browser (filter bar, item grid, sort / rarity / type menus).
-- Split out of LoadoutScreen.lua (2026-11-10, ARC-005 file-size split, step 8). Behaviour unchanged.
-- Host state (panels, equipped sub-tab, inventory filter / rarity / sort / selection, the one open
-- dropdown) is reached through `ctx` -- no require of LoadoutScreen (no circular dependency).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CTRBLXAI_UI = ReplicatedStorage:WaitForChild("CTRBLXAI", 10):WaitForChild("UI", 10)
local ConsumableData = require(ReplicatedStorage:WaitForChild("Content", 10)
	:WaitForChild("ConsumableData", 10))
local InventoryControls = require(CTRBLXAI_UI:WaitForChild("InventoryControls", 10))
local MockData    = require(CTRBLXAI_UI:WaitForChild("MockLoadoutData", 10))
local Theme       = require(CTRBLXAI_UI:WaitForChild("Theme", 10))

local LoadoutGears: any = {}

local ctx: any = nil
-- Host helpers, bound in Init (thin wrappers so a later reassignment in the host is seen).
local function buildConsumableGrid(...) return ctx.buildConsumableGrid(...) end
local function clearChildren(...) return ctx.clearChildren(...) end
local function getPlayerGui(...) return ctx.getPlayerGui(...) end
local function getRarityColor(...) return ctx.getRarityColor(...) end
local function makeLabel(...) return ctx.makeLabel(...) end
local function openEquippedConsumableDetail(...) return ctx.openEquippedConsumableDetail(...) end
local function openItemDetail(...) return ctx.openItemDetail(...) end
local function pad(...) return ctx.pad(...) end
local EQUIP_SLOTS: any = nil -- host table, set in Init (one definition)

local buildInventory

local CATEGORY_FILTERS = {
	{ id = "All",       label = "All",    icon = Theme.Icons.AllTypes },
	{ id = "MainHand",  label = "Main",   icon = Theme.Icons.MainHand },
	{ id = "OffHand",   label = "Off",    icon = Theme.Icons.OffHand },
	{ id = "Head",      label = "Head",   icon = Theme.Icons.Head },
	{ id = "Torso",     label = "Torso",  icon = Theme.Icons.Torso },
	{ id = "Arms",      label = "Arms",   icon = Theme.Icons.Arms },
	{ id = "Legs",      label = "Legs",   icon = Theme.Icons.Legs },
	{ id = "Accessory", label = "Acc",    icon = Theme.Icons.Accessory },
	{ id = "Consumable",label = "Use",    icon = Theme.Icons.Consumable },
	{ id = "Doctrine",  label = "Doct",   icon = Theme.Icons.Doctrine },
}
local RARITY_OPTIONS = { "All", "Common", "Uncommon", "Rare", "Epic", "Legendary" }
local SORT_OPTIONS = {
	{ label = "Lv \xe2\x86\x93", field = "lv", desc = true },
	{ label = "Lv \xe2\x86\x91", field = "lv", desc = false },
	{ label = "Name", field = "name", desc = false },
	{ label = "Rarity", field = "rarity", desc = true },
	{ label = "New First", field = "new", desc = true },
	{ label = "New Last", field = "new", desc = false },
}

-- EQUIPPED LOADOUT (4 columns x 2 rows + consumables)
--------------------------------------------------


local function buildEquippedLoadout()
	if not ctx.getEquippedPanel() then return end
	clearChildren(ctx.getEquippedPanel())
	pad(ctx.getEquippedPanel(), 6, 6, 6, 6)

	local unit = MockData.GetSelectedUnit()
	if not unit then return end

	local layout = Instance.new("UIListLayout", ctx.getEquippedPanel())
	layout.Padding = UDim.new(0, 3)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	-- Tab switcher: GEAR / CONSUMABLES (shared InventoryControls.MakeSubTabs, 2026-11-08)
	local SUBTAB_H = InventoryControls.SubTabHeight -- same height as the Outfit Worn/Preview sub-tabs (user ruling 2026-10-08)
	InventoryControls.MakeSubTabs(ctx.getEquippedPanel(), { { id = "gear", label = "GEAR" }, { id = "cons", label = "CONSUMABLES" } },
		ctx.getEquippedTab(), function(id)
			ctx.setEquippedTab(id)
			buildEquippedLoadout()
			if ctx.getEquippedTab() == "cons" then
				buildConsumableGrid()
			else
				buildInventory()
			end
		end, 0)

	-- Content area below tabs
	local content = Instance.new("Frame")
	content.Size = UDim2.new(1, 0, 1, -(SUBTAB_H + 6)) -- below the sub-tabs + list gap
	content.BackgroundTransparency = 1
	content.LayoutOrder = 1
	content.Parent = ctx.getEquippedPanel()

	if ctx.getEquippedTab() == "gear" then
		-- 4 col x 2 row equipment grid (icon-only, no slot labels)
		local eqGrid = Instance.new("Frame")
		eqGrid.Size = UDim2.new(1, 0, 1, 0)
		eqGrid.BackgroundTransparency = 1
		eqGrid.Parent = content

		local gridLayout = Instance.new("UIGridLayout", eqGrid)
		gridLayout.CellSize = UDim2.new(0.5, -2, 0.25, -2)
		gridLayout.CellPadding = UDim2.new(0, 3, 0, 3)
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder

		-- Check if main hand weapon is 2H (disables off-hand)
		local mainItem = MockData.GetEquipped(unit.id, "MainHand")
		local mainIs2H = mainItem and (mainItem.hands == "Two-Handed" or mainItem.hands == "2H") or false


		for i, slotDef in ipairs(EQUIP_SLOTS) do
			local item = MockData.GetEquipped(unit.id, slotDef.slot)
			-- Doctrine is not a regular inventory item — build from server data
			if not item and slotDef.slot == "Doctrine" then
				item = MockData.GetEquippedDoctrine(unit.id)
			end
			local isOffHandDisabled = (slotDef.slot == "OffHand" and mainIs2H)


			local tile = Instance.new("TextButton")
			if item then
				local rc = getRarityColor(item.rarity)
				tile.BackgroundColor3 = rc
				tile.BackgroundTransparency = 0.75
			else
				tile.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
				tile.BackgroundTransparency = 0.6
			end
			tile.BorderSizePixel = 0
			if isOffHandDisabled then
				tile.BackgroundColor3 = Theme.Colors.Background
				tile.BackgroundTransparency = 0.3
				tile.AutoButtonColor = false
			end

			tile.Text = ""
			tile.AutoButtonColor = true
			tile.LayoutOrder = i
			tile.Parent = eqGrid
			Instance.new("UICorner", tile).CornerRadius = UDim.new(0, 4)

			if item then
				-- Icon (centered) — use uploaded image if available
				if item.icon and string.find(item.icon, "rbxassetid://") then
					local PAD = 2
					local ico = Instance.new("ImageLabel")
					-- Square: side length = tile height minus 2*PAD
					ico.Size = UDim2.new(1, -2*PAD, 1, -2*PAD)
					ico.SizeConstraint = Enum.SizeConstraint.RelativeYY
					ico.Position = UDim2.new(1, -PAD, 0, PAD)
					ico.AnchorPoint = Vector2.new(1, 0)
					ico.BackgroundTransparency = 1
					ico.Image = item.icon
					ico.ScaleType = Enum.ScaleType.Fit
					ico.Parent = tile
				else
					makeLabel(tile, { Text = item.icon or "?", Size = UDim2.new(1, 0, 0, 24),
						Position = UDim2.new(0, 0, 0.15, 0),
						TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center })
				end

				-- Slot type label (left side, vertically centered)
				local slotLbl = makeLabel(tile, { Text = slotDef.label,
					Size = UDim2.new(0.5, 0, 0.5, 0),
					Position = UDim2.new(0, 3, 0.15, 0),
					TextSize = Theme.Text.Badge(), Font = Theme.Font.PrimaryBold,
					TextColor3 = Theme.Colors.TextDisabled,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = true })
				if slotLbl then slotLbl.ZIndex = 3 end

				-- Name (bottom area)
				local nameBg = Instance.new("Frame")
				nameBg.Size = UDim2.new(1, 0, 0, 14)
				nameBg.Position = UDim2.new(0, 0, 1, -14)
				nameBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
				nameBg.BackgroundTransparency = 0.4
				nameBg.BorderSizePixel = 0
				nameBg.ZIndex = 3
				nameBg.Parent = tile
				local eqNameLbl = makeLabel(nameBg, { Text = item.name, Size = UDim2.new(1, -4, 1, 0),
					Position = UDim2.new(0, 2, 0, 0),
					TextSize = Theme.Text.Small(), TextColor3 = getRarityColor(item.rarity),
					TextXAlignment = Enum.TextXAlignment.Left })
				if eqNameLbl then eqNameLbl.ZIndex = 3 end

				-- Level
				if item.lv and item.lv > 0 then
					local eqLvLbl = makeLabel(tile, { Text = "Lv" .. item.lv, Size = UDim2.new(0, 28, 0, 10),
						Position = UDim2.new(0, 2, 0, 2),
						TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextSecondary,
						TextXAlignment = Enum.TextXAlignment.Left })
					if eqLvLbl then eqLvLbl.ZIndex = 3 end
				end
			else
				-- Empty slot or disabled off-hand
				if isOffHandDisabled then
					makeLabel(tile, { Text = "2H", Size = UDim2.new(1, 0, 0, 20),
						Position = UDim2.new(0, 0, 0.3, 0),
						TextSize = Theme.Text.Body(), TextColor3 = Theme.Colors.TextDisabled,
						TextXAlignment = Enum.TextXAlignment.Center,
						Font = Theme.Font.PrimaryBold })
					makeLabel(tile, { Text = "OFF-HAND", Size = UDim2.new(1, 0, 0, 12),
						Position = UDim2.new(0, 0, 1, -14),
						TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextDisabled,
						TextXAlignment = Enum.TextXAlignment.Center })
				else
					-- Empty slot: show slot icon image + label
					local SLOT_ICON_MAP = {
						MainHand = Theme.Icons.MainHand, OffHand = Theme.Icons.OffHand,
						Head = Theme.Icons.Head, Torso = Theme.Icons.Torso,
						Arms = Theme.Icons.Arms, Legs = Theme.Icons.Legs,
						Accessory = Theme.Icons.Accessory, Doctrine = Theme.Icons.Doctrine,
					}
					local slotIcon = SLOT_ICON_MAP[slotDef.slot]
					if slotIcon then
						local ico = Instance.new("ImageLabel")
						ico.Size = UDim2.new(0.55, 0, 0.55, 0)
						ico.Position = UDim2.new(0.5, 0, 0.45, 0)
						ico.AnchorPoint = Vector2.new(0.5, 0.5)
						ico.BackgroundTransparency = 1
						ico.Image = slotIcon
						ico.ScaleType = Enum.ScaleType.Fit
						ico.ImageTransparency = 0.5
						ico.Parent = tile
					end
					makeLabel(tile, { Text = slotDef.label,
						Size = UDim2.new(1, -4, 0, 12),
						Position = UDim2.new(0, 2, 1, -14),
						TextSize = Theme.Text.Badge(), Font = Theme.Font.PrimaryBold,
						TextColor3 = Theme.Colors.TextDisabled,
						TextXAlignment = Enum.TextXAlignment.Center })
				end
			end

			-- Click: filter inventory to this slot type
			tile.Activated:Connect(function()
				if isOffHandDisabled then return end
				-- Every slot (2026-10-20): filter the inventory to this slot's category AND, if
				-- something is equipped, open its detail on top of the filtered list. The Doctrine
				-- slot value is "Doctrine", so the same path filters doctrines too.
				ctx.setCurrentFilter(slotDef.slot)
				ctx.setDetailFromSlot(slotDef.slot)  -- which slot the equipped detail belongs to (off-hand weapon)
				ctx.setSelectedItemId(nil)
				buildInventory()
				if item then
					-- Doctrine opens info-only (always one equipped); gear opens with UNEQUIP.
					openItemDetail(item, nil, true)
				end
			end)
		end

	else -- consumables tab
		local consGrid = Instance.new("Frame")
		consGrid.Size = UDim2.new(1, 0, 1, 0)
		consGrid.BackgroundTransparency = 1
		consGrid.Parent = content

		-- Slot tiles (2026-11-09 user request): the SAME tile as the Consumables inventory grid
		-- (Theme.MakeItemTile portrait: inset square icon, category border, top-right xN badge,
		-- two-row name strip). Cells keep the inventory tile shape (Theme.ItemTile.GridAspect),
		-- as large as fits 3 x 2 here, clamped to the inventory grid min/max cell width.
		local tileT = Theme.ItemTile
		local SLOT_GAP = 3
		local areaW, areaH = consGrid.AbsoluteSize.X, consGrid.AbsoluteSize.Y
		local slotW
		if areaW < 100 or areaH < 100 then
			slotW = (Theme.ItemTileCell(areaH)) -- panel not measured yet: inventory-grid size
		else
			slotW = math.floor(math.min((areaW - SLOT_GAP * 2) / 3, (areaH - SLOT_GAP) / 2 / tileT.GridAspect))
			slotW = math.clamp(slotW, tileT.GridMinCell, tileT.GridMaxCell)
		end
		local slotH = math.floor(slotW * tileT.GridAspect)

		local gridLayout = Instance.new("UIGridLayout", consGrid)
		gridLayout.CellSize = UDim2.fromOffset(slotW, slotH)
		gridLayout.CellPadding = UDim2.fromOffset(SLOT_GAP, SLOT_GAP)
		gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder

		-- White text with a black outline so slot numbers / [X] read on any tile tint.
		local function outlinedLabel(parent, text, size, pos, textSize, align)
			local lbl = makeLabel(parent, { Text = text, Size = size, Position = pos, TextSize = textSize,
				Font = Theme.Font.PrimaryBold, TextColor3 = Theme.Colors.TextPrimary, TextXAlignment = align })
			lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
			lbl.TextStrokeTransparency = 0
			lbl.ZIndex = 4
			return lbl
		end

		for i = 1, 6 do
			local slotKey = "Cons" .. i
			local locked = MockData.IsConsSlotLocked(unit.id, slotKey)
			local item = MockData.GetEquipped(unit.id, slotKey)

			local cell
			if item and not locked then
				-- The equipped-slot item carries a placeholder icon "?" (server-side), so the real
				-- icon and category come from ConsumableData by id (2026-10-20 lookup kept).
				local cdef = ConsumableData.GetById(item.consumableId or item.id)
				local cat = cdef and cdef.category
				-- Read via the module export: CONS_CATEGORY_COLORS is declared further down this file.
				local accent = (cat and ctx.getConsCategoryColors() and ctx.getConsCategoryColors()[cat])
					or Theme.Colors.TextSecondary
				cell = Theme.MakeItemTile({
					parent = consGrid,
					accentColor = accent,
					cellW = slotW,
					icon = cdef and cdef.icon or nil,
					iconText = item.icon or "[C]",
					name = item.name,
					countText = "x" .. (item.qty or 1),
					layoutOrder = i,
					portrait = true,
					onClick = function()
						openEquippedConsumableDetail(unit.id, i, item)
					end,
				})
			else
				-- Locked ([X]) or empty (—) slot: same tile frame (corner + thin border), no tap action.
				cell = Instance.new("TextButton")
				cell.Size = UDim2.fromScale(1, 1)
				cell.BackgroundColor3 = if locked then Theme.Colors.LockedSlot else Theme.Colors.Panel
				cell.BackgroundTransparency = if locked then 0.7 else 0.3
				cell.BorderSizePixel = 0
				cell.Text = ""
				cell.AutoButtonColor = false -- rule 243: no mouse-over colour
				cell.LayoutOrder = i
				Instance.new("UICorner", cell).CornerRadius = UDim.new(0, tileT.CornerRadius)
				local stroke = Instance.new("UIStroke", cell)
				stroke.Color = Theme.Colors.TextDisabled
				stroke.Thickness = tileT.StrokeThickness
				outlinedLabel(cell, if locked then "[X]" else "—", UDim2.fromScale(1, 1), UDim2.new(),
					if locked then 18 else 20, Enum.TextXAlignment.Center)
				cell.Parent = consGrid -- NET-004: parent last
			end

			-- Slot number (top-left), over the tile.
			outlinedLabel(cell, tostring(i), UDim2.new(0, 14, 0, 14), UDim2.new(0, 3, 0, 1),
				Theme.Text.Small(), Enum.TextXAlignment.Left)
		end
	end
end

--------------------------------------------------
-- INVENTORY BROWSER (left side, full)
--------------------------------------------------

local filterBar, itemGrid, footerLabel

local function _buildFilterBar(parent)
	if filterBar then clearChildren(filterBar) end
	filterBar = Instance.new("Frame")
	filterBar.Size = UDim2.new(1, 0, 0, 36)
	filterBar.BackgroundTransparency = 1
	filterBar.LayoutOrder = 1
	filterBar.Parent = parent

	local fl = Instance.new("UIListLayout", filterBar)
	fl.FillDirection = Enum.FillDirection.Horizontal
	fl.Padding = UDim.new(0, 3)
	fl.VerticalAlignment = Enum.VerticalAlignment.Center

	for i, f in ipairs(CATEGORY_FILTERS) do
		local chip = Instance.new("TextButton")
		chip.Size = UDim2.new(0, 52, 0, 32)
		chip.BackgroundColor3 = Theme.Colors.Panel
		chip.BackgroundTransparency = (ctx.getCurrentFilter() == f.id) and 0.1 or 0.5
		chip.BorderSizePixel = 0
		chip.Font = Theme.Font.Primary
		chip.TextSize = 9
		chip.TextColor3 = (ctx.getCurrentFilter() == f.id) and Theme.Colors.TextGold or Theme.Colors.TextSecondary
		chip.Text = f.icon .. "\n" .. f.label
		chip.LayoutOrder = i
		chip.Parent = filterBar
		Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 4)

		if ctx.getCurrentFilter() == f.id then
			local stroke = Instance.new("UIStroke", chip)
			stroke.Color = Theme.Colors.TextGold
			stroke.Thickness = 1
		end

		chip.Activated:Connect(function()
			ctx.setCurrentFilter(f.id)
			ctx.setSelectedItemId(nil)
			buildInventory()
		end)
	end
end

local function buildItemGrid(parent)
	if itemGrid then itemGrid:Destroy() end

	local unit = MockData.GetSelectedUnit()
	if not unit then return end

	itemGrid = Instance.new("ScrollingFrame")
	itemGrid.Name = "ItemGrid"
	itemGrid.Size = UDim2.new(1, 0, 1, -30)
	itemGrid.Position = UDim2.new(0, 0, 0, 28)
	itemGrid.BackgroundTransparency = 1
	itemGrid.BorderSizePixel = 0
	itemGrid.ScrollBarThickness = 4
	itemGrid.ScrollBarImageColor3 = Theme.Colors.TextSecondary
	itemGrid.CanvasSize = UDim2.new(0, 0, 0, 0)
	itemGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	itemGrid.Parent = parent

	local grid = Instance.new("UIGridLayout", itemGrid)
	grid.CellPadding = InventoryControls.GridCellPadding
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirection = Enum.FillDirection.Horizontal

	-- Compute cell size: responsive to screen — minimum 3 rows visible, max 96px wide.
	-- Shared formula (Theme.ItemTileCell, 2026-11-07) so the Runeforge uses the same tiles.
	local cellW, cellH = Theme.ItemTileCell(itemGrid.AbsoluteSize.Y)
	grid.CellSize = UDim2.new(0, cellW, 0, cellH)

	local items = MockData.GetFilteredItems(ctx.getCurrentFilter())
	-- Twinblade dual wield (2026-10-28): the OFF-HAND list also offers 1H weapons, which then
	-- equip into the off hand (server re-checks the Twinblade / 1H rules).
	if ctx.getCurrentFilter() == "OffHand" then
		local _u = MockData.GetSelectedUnit()
		if _u and MockData.GetUnitDoctrineId and MockData.GetUnitDoctrineId(_u.id) == "DOC-TWINBLADE" then
			local merged = table.clone(items)
			for _, it in ipairs(MockData.GetFilteredItems("MainHand")) do
				if it.hands == "1H" or it.hands == "One-Handed" then table.insert(merged, it) end
			end
			items = merged
		end
	end

	-- Rarity filter
	if ctx.getCurrentRarity() ~= "All" then
		local filtered = {}
		for _, item in ipairs(items) do
			if item.rarity == ctx.getCurrentRarity() then table.insert(filtered, item) end
		end
		items = filtered
	end

	-- Sort
	local RARITY_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Exalted = 5, Legendary = 6 }
	local sortOpt = SORT_OPTIONS[ctx.getCurrentSort()] or SORT_OPTIONS[1]
	table.sort(items, function(a, b)
		if sortOpt.field == "name" then
			return (a.name or "") < (b.name or "")
		elseif sortOpt.field == "rarity" then
			local ra, rb = RARITY_RANK[a.rarity] or 0, RARITY_RANK[b.rarity] or 0
			if ra ~= rb then
				if sortOpt.desc then return ra > rb else return ra < rb end
			end
			return false
		elseif sortOpt.field == "new" then
			local na = a.isNew and 1 or 0
			local nb = b.isNew and 1 or 0
			if na ~= nb then
				-- desc = "New First" (new items on top), asc = "New Last" (new at bottom)
				if sortOpt.desc then return na > nb else return na < nb end
			end
			-- Tie-break: sort by name within same new/old group
			return (a.name or "") < (b.name or "")
		else -- lv (default)
			local la, lb = a.lv or 0, b.lv or 0
			if la ~= lb then
				if sortOpt.desc then return la > lb else return la < lb end
			end
			return false
		end
	end)

	for i, item in ipairs(items) do
		local isEquipped, isEquippedByOther
		if item.cat == "Doctrine" then
			isEquipped = item.isCurrent == true
			isEquippedByOther = false
		else
			isEquipped = MockData.IsEquipped(item.id, unit.id)
			isEquippedByOther = false
			if not isEquipped then
				isEquippedByOther = MockData.IsEquippedByAny(item.id)
			end
		end
		local isSelected = (ctx.getSelectedItemId() == item.id)

		-- Shared tile (Theme.MakeItemTile portrait, 2026-11-09 user request): the same look and
		-- size as the Consumables grid — equal top/left/right inset around a square icon, two-row
		-- name strip, rarity tint + border, gold when selected, no hover colour (rule 243). The
		-- extras are layered on top exactly as before: Lv label (top-left), xN count for stackable
		-- items (top-right), equipped "E" + NEW markers (InventoryControls.AddTileMarkers).
		-- Stackable items (Doctrine, Consumable) show their count, never a level; the current
		-- doctrine shows no count (only one is ever held). A count item is never gear-equipped
		-- here, so the count badge never collides with the top-right "E" marker.
		local isCountItem = (item.cat == "Doctrine") or (item.cat == "Consumable")
		local hasCountBadge = isCountItem and not (item.cat == "Doctrine" and item.isCurrent)
		local card = Theme.MakeItemTile({
			parent = itemGrid,
			accentColor = getRarityColor(item.rarity),
			cellW = cellW,
			icon = item.icon,
			iconText = item.icon or "?", -- shown only when there is no uploaded image
			name = item.name,
			countText = if hasCountBadge then "x" .. (item.qty or 1) else nil,
			selected = isSelected,
			layoutOrder = i,
			portrait = true,
		})
		local gearLvW = 0  -- width of the top-left Lv label (gear only); NEW badge drops below it if they would touch
		local _lvLbl
		if not isCountItem then
			_lvLbl, gearLvW = InventoryControls.MakeLevelLabel(card, "Lv." .. (item.lv or 1))
		end
		InventoryControls.AddTileMarkers(card, cellW, gearLvW, isEquipped == true, isEquippedByOther == true,
			item.isNew == true, hasCountBadge)
		-- OVER-LEVEL GEAR (user 2026-11-10): item level above this unit's level cannot be
		-- equipped (server refuses, LoadoutRequestHandlers). Grey the tile + red Lv so it reads
		-- before the tap. Still tappable so the detail can be read.
		if not isCountItem and (item.lv or 1) > (tonumber(unit.level) or 1) then
			local shade = Instance.new("Frame")
			shade.Name = "OverLevelShade"
			shade.Size = UDim2.fromScale(1, 1)
			shade.BackgroundColor3 = Color3.new(0, 0, 0)
			shade.BackgroundTransparency = 0.45
			shade.BorderSizePixel = 0
			shade.ZIndex = 8
			shade.Active = false
			Instance.new("UICorner", shade).CornerRadius = UDim.new(0, 4)
			shade.Parent = card
			if _lvLbl then
				_lvLbl.TextColor3 = Theme.Colors.Danger
				_lvLbl.ZIndex = 9
			end
		end

		card.Activated:Connect(function()
			local newBadge = card:FindFirstChild("NewBadge") -- seen now (2026-11-08)
			if newBadge then newBadge:Destroy() end
			if item.cat == "Doctrine" then
				-- Open the doctrine's info window like weapons/consumables (2026-10-20). The
				-- equipped copy opens info-only (isEquippedMode); a spare shows an EQUIP action.
				openItemDetail(item, nil, item.isCurrent == true)
				return
			end
			openItemDetail(item, nil)
		end)
	end

	-- Footer
	if footerLabel then footerLabel:Destroy() end
	footerLabel = makeLabel(parent, { Text = "Owned: " .. #MockData.Inventory .. " / 50",
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 10, 1, -18),
		TextSize = 9, TextColor3 = Theme.Colors.TextDisabled })
end

buildInventory = function()
	if not ctx.getInventoryPanel() then return end
	clearChildren(ctx.getInventoryPanel())
	pad(ctx.getInventoryPanel(), 8, 8, 8, 8)

	-- Single toolbar row: Search + Type + Rarity + Sort (bar height: InventoryControls)
	local ctrlRow = Instance.new("Frame")
	ctrlRow.Size = UDim2.new(1, 0, 0, InventoryControls.BarHeight)
	ctrlRow.Position = UDim2.new(0, 0, 0, 0)
	ctrlRow.BackgroundTransparency = 1
	ctrlRow.Parent = ctx.getInventoryPanel()

	local ctrlLayout = Instance.new("UIListLayout", ctrlRow)
	ctrlLayout.FillDirection = Enum.FillDirection.Horizontal
	ctrlLayout.Padding = UDim.new(0, 3)
	ctrlLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	-- Search box
	local search = Instance.new("TextBox")
	search.Size = UDim2.new(1, -195, 1, 0)
	search.BackgroundColor3 = Theme.Colors.Surface
	search.BackgroundTransparency = 0.2
	search.Font = Theme.Font.Primary
	search.TextSize = Theme.Text.Small()
	search.TextColor3 = Theme.Colors.TextPrimary
	search.PlaceholderText = "Search items..."
	search.PlaceholderColor3 = Theme.Colors.TextDisabled
	search.Text = ""
	search.BorderSizePixel = 0
	search.ClearTextOnFocus = false
	search.LayoutOrder = 1
	search.Parent = ctrlRow
	Instance.new("UICorner", search).CornerRadius = UDim.new(0, 3)

	-- Type / Rarity / Sort dropdown buttons
	local filterLabel = ctx.getCurrentFilter() == "All" and "Type" or (ctx.getCurrentFilter() )
	local rarityLabel = ctx.getCurrentRarity() == "All" and "Rarity" or (ctx.getCurrentRarity() )
	local sortLabel = SORT_OPTIONS[ctx.getCurrentSort()].label 

	-- Shared dropdown helper: opens a menu below the anchor button
	local function closeDropdown()
		if ctx.getActiveDropdown() then ctx.getActiveDropdown():Destroy(); ctx.setActiveDropdown(nil) end
	end

	local function showDropdown(anchorBtn, options, onSelect)
		closeDropdown()
		-- Shared Loadout menu (InventoryControls.ShowMenu, 2026-11-08): unchanged look.
		ctx.setActiveDropdown(InventoryControls.ShowMenu(getPlayerGui(), anchorBtn, options, onSelect, closeDropdown))
	end

	local function makeDropdown(text, order, isActive, iconAsset)
		return InventoryControls.MakeFilterButton(ctrlRow, text, order, isActive, iconAsset)
	end

	-- Type filter button — cycles through category filters
	local typeBtn = makeDropdown(filterLabel, 2, ctx.getCurrentFilter() ~= "All", Theme.Icons.Filter)
	typeBtn.Activated:Connect(function()
		local opts = {}
		for _, f in ipairs(CATEGORY_FILTERS) do
			table.insert(opts, { label = f.label, value = f.id, icon = f.icon, active = (ctx.getCurrentFilter() == f.id) })
		end
		showDropdown(typeBtn, opts, function(val)
			ctx.setCurrentFilter(val)
			if val == "All" then
				ctx.setCurrentRarity("All")  -- reset rarity too for full reset
			end
			ctx.setSelectedItemId(nil)
			buildInventory()
		end)
	end)

	-- Rarity filter button — cycles through rarity options
	local rarityBtn = makeDropdown(rarityLabel, 3, ctx.getCurrentRarity() ~= "All", Theme.Icons.Filter)
	rarityBtn.Activated:Connect(function()
		local opts = {}
		for _, r in ipairs(RARITY_OPTIONS) do
			local _clr = r == "All" and Theme.Colors.TextPrimary or getRarityColor(r)
			local displayLabel = r == "All" and "All Rarities" or r
			table.insert(opts, { label = displayLabel, value = r, active = (ctx.getCurrentRarity() == r) })
		end
		showDropdown(rarityBtn, opts, function(val)
			ctx.setCurrentRarity(val)
			ctx.setSelectedItemId(nil)
			buildInventory()
		end)
	end)

	-- Sort button — cycles through sort modes
	local sortBtn = makeDropdown(sortLabel, 4, false, Theme.Icons.Sort)
	sortBtn.Activated:Connect(function()
		local opts = {}
		for si, s in ipairs(SORT_OPTIONS) do
			table.insert(opts, { label = s.label, value = si, active = (ctx.getCurrentSort() == si) })
		end
		showDropdown(sortBtn, opts, function(val)
			ctx.setCurrentSort(val)
			buildInventory()
		end)
	end)

	buildItemGrid(ctx.getInventoryPanel())
end


function LoadoutGears.Init(c: any)
	ctx = c
	EQUIP_SLOTS = c.EQUIP_SLOTS
end
LoadoutGears.BuildEquippedLoadout = function(...) return buildEquippedLoadout(...) end
LoadoutGears.BuildInventory = function(...) return buildInventory(...) end

return LoadoutGears
