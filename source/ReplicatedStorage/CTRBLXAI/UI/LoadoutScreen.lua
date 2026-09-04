-- LoadoutScreen.lua
-- CTRBLXAI | Slice 7 — Equipment Loadout Screen
-- Replaces pre/post-battle loadout. Uses ornate 9-slice panel frames.
-- Presentation only — no gameplay logic.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local CTRBLXAI_UI = ReplicatedStorage:WaitForChild("CTRBLXAI", 10):WaitForChild("UI", 10)
local Theme       = require(CTRBLXAI_UI:WaitForChild("Theme", 10))
local MockData    = require(CTRBLXAI_UI:WaitForChild("MockLoadoutData", 10))
local BattleEvents = require(ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
	:WaitForChild("Remotes", 10):WaitForChild("BattleEvents", 10))

local LoadoutScreen = {}

local screenGui, rootFrame
local unitHeaderPanel, equippedPanel, inventoryPanel
local currentFilter = "All"
local selectedItemId = nil

-- Drag state
local currentRarity = "All"
local RARITY_OPTIONS = { "All", "Common", "Uncommon", "Rare", "Epic", "Legendary" }

-- Active dropdown (only one open at a time)
local activeDropdown = nil

local currentSort = 1
local SORT_OPTIONS = {
	{ label = "Lv \xe2\x86\x93", field = "lv", desc = true },
	{ label = "Lv \xe2\x86\x91", field = "lv", desc = false },
	{ label = "Name", field = "name", desc = false },
	{ label = "Rarity", field = "rarity", desc = true },
	{ label = "New First", field = "new", desc = true },
	{ label = "New Last", field = "new", desc = false },
}

local CATEGORY_FILTERS = {
	{ id = "All",       label = "All",    icon = "⊞" },
	{ id = "MainHand",  label = "Main",   icon = "⚔" },
	{ id = "OffHand",   label = "Off",    icon = "🛡" },
	{ id = "Head",      label = "Head",   icon = "🪖" },
	{ id = "Torso",     label = "Torso",  icon = "🦺" },
	{ id = "Arms",      label = "Arms",   icon = "🧤" },
	{ id = "Legs",      label = "Legs",   icon = "🥾" },
	{ id = "Accessory", label = "Acc",    icon = "💍" },
	{ id = "Consumable",label = "Use",    icon = "🧪" },
	{ id = "Doctrine",  label = "Doct",   icon = "📜" },
}

local EQUIP_SLOTS = {
	{ slot = "MainHand",  label = "MAIN HAND" },
	{ slot = "OffHand",   label = "OFF-HAND" },
	{ slot = "Head",      label = "HEAD" },
	{ slot = "Torso",     label = "TORSO" },
	{ slot = "Arms",      label = "ARMS" },
	{ slot = "Legs",      label = "LEGS" },
	{ slot = "Accessory", label = "ACCESSORY" },
	{ slot = "Doctrine",  label = "DOCTRINE" },
}

local STAT_ORDER = { "STR", "INT", "DEX", "AGI", "VIT", "LUK" }

--------------------------------------------------
-- FORWARD DECLARATIONS (functions used before definition)
--------------------------------------------------
local buildInventory
local openItemDetail, closeDetail
local buildSoloDetailContent, buildComparisonContent

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function getPlayerGui()
	return player:WaitForChild("PlayerGui")
end

local function clearChildren(frame)
	if not frame then return end
	for _, child in ipairs(frame:GetChildren()) do
		if not child:IsA("UICorner") and not child:IsA("UIPadding") and not child:IsA("UISizeConstraint") then
			child:Destroy()
		end
	end
end

local function makePanel(name, size, position, anchor, parent, opts)
	return Theme.MakePanel(name, size, position, anchor, parent, opts)
end

local function makeLabel(parent, props)
	local lbl = Instance.new("TextLabel")
	lbl.Size = props.Size or UDim2.new(1, 0, 0, 14)
	lbl.Position = props.Position or UDim2.new(0, 0, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.BorderSizePixel = 0
	lbl.Font = props.Font or Theme.Font.Primary
	lbl.TextSize = props.TextSize or Theme.Text.Body()
	lbl.TextColor3 = props.TextColor3 or Theme.Colors.TextPrimary
	lbl.Text = props.Text or ""
	lbl.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	lbl.TextTruncate = Enum.TextTruncate.AtEnd
	lbl.LayoutOrder = props.LayoutOrder or 0
	lbl.RichText = props.RichText or false
	if props.TextWrapped then lbl.TextWrapped = true end
	lbl.Parent = parent
	return lbl
end

local function getRarityColor(rarity)
	local map = {
		Common = Theme.Colors.RarityCommon,
		Uncommon = Theme.Colors.RarityUncommon,
		Rare = Theme.Colors.RarityRare,
		Epic = Theme.Colors.RarityEpic,
		Legendary = Theme.Colors.RarityLegendary,
	}
	return map[rarity] or Theme.Colors.RarityCommon
end

local function pad(frame, top, left, right, bottom)
	local p = Instance.new("UIPadding", frame)
	p.PaddingTop = UDim.new(0, top or 10)
	p.PaddingLeft = UDim.new(0, left or 10)
	p.PaddingRight = UDim.new(0, right or 10)
	p.PaddingBottom = UDim.new(0, bottom or 10)
end

--------------------------------------------------
-- TAB BAR
--------------------------------------------------

local tabBarGui = nil
local optionsDropdown = nil

local function buildTabBar()
	if tabBarGui then tabBarGui:Destroy() end
	if optionsDropdown then optionsDropdown:Destroy(); optionsDropdown = nil end
	local panel
	tabBarGui, panel = Theme.MakeTabBar("LoadoutTabBar", getPlayerGui())

	local tb = Theme.TabBar
	local bar = Instance.new("Frame")
	bar.Name = "TabBar"
	bar.Size = UDim2.new(1, -tb.InnerPadX * 2, 1, -tb.InnerPadY * 2)
	bar.Position = UDim2.new(0, tb.InnerPadX, 0, tb.InnerPadY)
	bar.BackgroundTransparency = 1
	bar.Parent = panel

	local layout = Instance.new("UIListLayout", bar)
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, tb.TabSpacing)

	local tabs = { "INFO", "EQUIPMENT", "SKILLS" }
	for _, name in ipairs(tabs) do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, tb.TabWidth, 1, 0)
		btn.BackgroundTransparency = 1
		btn.Font = Theme.Font.PrimaryBold
		btn.TextSize = tb.TabTextSize
		btn.Text = name
		btn.BorderSizePixel = 0
		btn.Parent = bar

		if name == "EQUIPMENT" then
			btn.TextColor3 = tb.ActiveColor
			local underline = Instance.new("Frame")
			underline.Size = UDim2.new(0.8, 0, 0, tb.UnderlineHeight)
			underline.Position = UDim2.new(0.1, 0, 1, -tb.UnderlineHeight)
			underline.BackgroundColor3 = tb.ActiveColor
			underline.BorderSizePixel = 0
			underline.Parent = btn
		else
			btn.TextColor3 = tb.InactiveColor
		end
	end

	-- OPTIONS button (right-aligned, outside the centered tabs)
	local optBtn = Instance.new("TextButton")
	optBtn.Size = UDim2.new(0, 66, 0, 24)
	optBtn.Position = UDim2.new(1, -8, 0, 8)
	optBtn.AnchorPoint = Vector2.new(1, 0)
	optBtn.BackgroundColor3 = Theme.Colors.Surface
	optBtn.BackgroundTransparency = 0.3
	optBtn.Font = Theme.Font.PrimaryBold
	optBtn.TextSize = Theme.Text.Small()
	optBtn.TextColor3 = Theme.Colors.TextSecondary
	optBtn.Text = "OPTIONS"
	optBtn.BorderSizePixel = 0
	optBtn.Parent = tabBarGui
	Instance.new("UICorner", optBtn).CornerRadius = UDim.new(0, 4)

	optBtn.MouseButton1Click:Connect(function()
		-- Toggle dropdown
		if optionsDropdown then
			optionsDropdown:Destroy()
			optionsDropdown = nil
			return
		end

		optionsDropdown = Instance.new("ScreenGui")
		optionsDropdown.Name = "OptionsDropdown"
		optionsDropdown.DisplayOrder = 115
		optionsDropdown.ResetOnSpawn = false
		optionsDropdown.Parent = getPlayerGui()

		-- Backdrop to close on outside click
		local backdrop = Instance.new("TextButton")
		backdrop.Size = UDim2.fromScale(1, 1)
		backdrop.BackgroundTransparency = 1
		backdrop.Text = ""
		backdrop.Parent = optionsDropdown
		backdrop.MouseButton1Click:Connect(function()
			if optionsDropdown then optionsDropdown:Destroy(); optionsDropdown = nil end
		end)

		-- Menu panel below the OPTIONS button
		local menuItems = {
			{ text = "Start Battle", color = Theme.Colors.Success, action = function()
				if optionsDropdown then optionsDropdown:Destroy(); optionsDropdown = nil end
				LoadoutScreen.Hide()
				BattleEvents.StartBattle:FireServer()
			end },
			{ text = "Save Now", color = Theme.Colors.Info, action = function()
				BattleEvents.DevCommand:FireServer({ action = "SaveNow" })
				if optionsDropdown then optionsDropdown:Destroy(); optionsDropdown = nil end
			end },
			{ text = "Delete Save", color = Theme.Colors.Danger, action = function()
				BattleEvents.DevCommand:FireServer({ action = "DeleteSave" })
				if optionsDropdown then optionsDropdown:Destroy(); optionsDropdown = nil end
			end },
		}

		local rowH = 28
		local menuW = 110
		local menuH = #menuItems * rowH + 6
		local menuPanel = Instance.new("Frame")
		menuPanel.Size = UDim2.new(0, menuW, 0, menuH)
		-- Right-align: menu's right edge aligns with button's right edge
		local menuX = optBtn.AbsolutePosition.X + optBtn.AbsoluteSize.X - menuW
		menuPanel.Position = UDim2.new(0, menuX, 0, optBtn.AbsolutePosition.Y + optBtn.AbsoluteSize.Y + 2)
		menuPanel.BackgroundColor3 = Theme.Colors.Panel
		menuPanel.BorderSizePixel = 0
		menuPanel.Parent = optionsDropdown
		Instance.new("UICorner", menuPanel).CornerRadius = UDim.new(0, 4)
		Instance.new("UIStroke", menuPanel).Color = Theme.Colors.Border
		pad(menuPanel, 3, 3, 3, 3)

		local menuLayout = Instance.new("UIListLayout", menuPanel)
		menuLayout.Padding = UDim.new(0, 2)
		menuLayout.SortOrder = Enum.SortOrder.LayoutOrder

		for idx, mi in ipairs(menuItems) do
			local row = Instance.new("TextButton")
			row.Size = UDim2.new(1, 0, 0, rowH - 2)
			row.BackgroundColor3 = mi.color
			row.BackgroundTransparency = 0.75
			row.Font = Theme.Font.PrimaryBold
			row.TextSize = Theme.Text.Small()
			row.TextColor3 = Theme.Colors.TextPrimary
			row.Text = mi.text
			row.BorderSizePixel = 0
			row.LayoutOrder = idx
			row.Parent = menuPanel
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, 3)
			row.MouseButton1Click:Connect(mi.action)
		end
	end)
end

--------------------------------------------------
-- UNIT HEADER (upper-right, compact)
--------------------------------------------------

local function buildUnitHeader()
	if not unitHeaderPanel then return end
	clearChildren(unitHeaderPanel)
	pad(unitHeaderPanel, 8, 10, 10, 8)

	local unit = MockData.GetSelectedUnit()
	if not unit then return end

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 44)
	row.BackgroundTransparency = 1
	row.Parent = unitHeaderPanel

	-- Portrait
	local portrait = Instance.new("Frame")
	portrait.Size = UDim2.new(0, 44, 0, 44)
	portrait.BackgroundColor3 = Theme.Colors.Player
	portrait.BackgroundTransparency = 0.2
	portrait.BorderSizePixel = 0
	portrait.Parent = row
	Instance.new("UICorner", portrait).CornerRadius = UDim.new(0, 5)

	local pText = Instance.new("TextLabel")
	pText.Size = UDim2.new(1, 0, 0, 32)
	pText.BackgroundTransparency = 1
	pText.Font = Theme.Font.PrimaryBold
	pText.TextSize = Theme.Text.Title()
	pText.TextColor3 = Theme.Colors.TextPrimary
	pText.Text = string.sub(unit.name, 1, 2)
	pText.Parent = portrait

	local lvlBadge = Instance.new("TextLabel")
	lvlBadge.Size = UDim2.new(0, 28, 0, 12)
	lvlBadge.Position = UDim2.new(0, 0, 0, 0)
	lvlBadge.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	lvlBadge.BackgroundTransparency = 0.3
	lvlBadge.Font = Theme.Font.Mono
	lvlBadge.TextSize = Theme.Text.Tiny()
	lvlBadge.TextColor3 = Theme.Colors.TextPrimary
	lvlBadge.Text = "Lv." .. unit.level
	lvlBadge.BorderSizePixel = 0
	lvlBadge.TextXAlignment = Enum.TextXAlignment.Left
	lvlBadge.Parent = portrait

	-- Unallocated stat points indicator (red dot, top-right of portrait)
	if unit.unallocatedPoints and unit.unallocatedPoints > 0 then
		local alertDot = Instance.new("Frame")
		alertDot.Size = UDim2.new(0, 10, 0, 10)
		alertDot.Position = UDim2.new(1, -12, 0, 2)
		alertDot.BackgroundColor3 = Theme.Colors.Danger
		alertDot.BorderSizePixel = 0
		alertDot.Parent = portrait
		Instance.new("UICorner", alertDot).CornerRadius = UDim.new(0.5, 0)
	end

	-- Name + Race
	makeLabel(row, { Text = unit.name, Position = UDim2.new(0, 52, 0, 2),
		Size = UDim2.new(1, -100, 0, 18), Font = Theme.Font.PrimaryBold,
		TextSize = Theme.Text.Heading(), TextColor3 = Theme.Colors.Player })
	makeLabel(row, { Text = unit.raceName,
		Position = UDim2.new(0, 52, 0, 20),
		Size = UDim2.new(1, -100, 0, 14), TextSize = Theme.Text.Small(),
		TextColor3 = Theme.Colors.TextSecondary })

	-- Switch unit button
	local switchBtn = Instance.new("TextButton")
	switchBtn.Size = UDim2.new(0, 28, 0, 28)
	switchBtn.Position = UDim2.new(1, -28, 0, 8)
	switchBtn.BackgroundColor3 = Theme.Colors.Surface
	switchBtn.BackgroundTransparency = 0.3
	switchBtn.Font = Theme.Font.PrimaryBold
	switchBtn.TextSize = 16
	switchBtn.TextColor3 = Theme.Colors.TextSecondary
	switchBtn.Text = "⇆"
	switchBtn.BorderSizePixel = 0
	switchBtn.Parent = row
	Instance.new("UICorner", switchBtn).CornerRadius = UDim.new(0, 4)
	switchBtn.MouseButton1Click:Connect(function()
		MockData.NextUnit()
		LoadoutScreen.Refresh()
	end)
end

--------------------------------------------------
-- PRIMARY STATS (3x2 grid below header)
--------------------------------------------------


--------------------------------------------------
-- EQUIPPED LOADOUT (4 columns x 2 rows + consumables)
--------------------------------------------------

local equippedTab = "gear"  -- "gear" or "cons"

local function buildEquippedLoadout()
	if not equippedPanel then return end
	clearChildren(equippedPanel)
	pad(equippedPanel, 6, 6, 6, 6)

	local unit = MockData.GetSelectedUnit()
	if not unit then return end

	local layout = Instance.new("UIListLayout", equippedPanel)
	layout.Padding = UDim.new(0, 3)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	-- Tab switcher: GEAR / CONSUMABLES
	local tabRow = Instance.new("Frame")
	tabRow.Size = UDim2.new(1, 0, 0, 18)
	tabRow.BackgroundTransparency = 1
	tabRow.LayoutOrder = 0
	tabRow.Parent = equippedPanel

	local tabLayout = Instance.new("UIListLayout", tabRow)
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)

	for _, tabDef in ipairs({ { id = "gear", label = "GEAR" }, { id = "cons", label = "CONSUMABLES" } }) do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 80, 1, 0)
		btn.BackgroundTransparency = 1
		btn.Font = Theme.Font.PrimaryBold
		btn.TextSize = Theme.Text.Small()
		btn.Text = tabDef.label
		btn.BorderSizePixel = 0
		btn.Parent = tabRow

		if tabDef.id == equippedTab then
			btn.TextColor3 = Theme.Colors.TextGold
			local underline = Instance.new("Frame")
			underline.Size = UDim2.new(0.8, 0, 0, 2)
			underline.Position = UDim2.new(0.1, 0, 1, -2)
			underline.BackgroundColor3 = Theme.Colors.TextGold
			underline.BorderSizePixel = 0
			underline.Parent = btn
		else
			btn.TextColor3 = Theme.Colors.TextSecondary
		end

		btn.MouseButton1Click:Connect(function()
			equippedTab = tabDef.id
			buildEquippedLoadout()
		end)
	end

	-- Content area below tabs
	local content = Instance.new("Frame")
	content.Size = UDim2.new(1, 0, 1, -24)
	content.BackgroundTransparency = 1
	content.LayoutOrder = 1
	content.Parent = equippedPanel

	if equippedTab == "gear" then
		-- 4 col x 2 row equipment grid (icon-only, no slot labels)
		local eqGrid = Instance.new("Frame")
		eqGrid.Size = UDim2.new(1, 0, 1, 0)
		eqGrid.BackgroundTransparency = 1
		eqGrid.Parent = content

		local gridLayout = Instance.new("UIGridLayout", eqGrid)
		gridLayout.CellSize = UDim2.new(0.5, -2, 0.25, -2)
		gridLayout.CellPadding = UDim2.new(0, 3, 0, 3)
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder

		for i, slotDef in ipairs(EQUIP_SLOTS) do
			local item = MockData.GetEquipped(unit.id, slotDef.slot)

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
			tile.Text = ""
			tile.AutoButtonColor = true
			tile.LayoutOrder = i
			tile.Parent = eqGrid
			Instance.new("UICorner", tile).CornerRadius = UDim.new(0, 4)

			if item then
				-- Icon (centered, large)
				makeLabel(tile, { Text = item.icon or "?", Size = UDim2.new(1, 0, 0, 24),
					Position = UDim2.new(0, 0, 0.15, 0),
					TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center })

				-- Name (bottom area)
				local nameBg = Instance.new("Frame")
				nameBg.Size = UDim2.new(1, 0, 0, 14)
				nameBg.Position = UDim2.new(0, 0, 1, -14)
				nameBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
				nameBg.BackgroundTransparency = 0.4
				nameBg.BorderSizePixel = 0
				nameBg.Parent = tile
				makeLabel(nameBg, { Text = item.name, Size = UDim2.new(1, -4, 1, 0),
					Position = UDim2.new(0, 2, 0, 0),
					TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextPrimary,
					TextXAlignment = Enum.TextXAlignment.Left })

				-- Level
				if item.lv and item.lv > 0 then
					makeLabel(tile, { Text = "Lv" .. item.lv, Size = UDim2.new(0, 28, 0, 10),
						Position = UDim2.new(0, 2, 0, 2),
						TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextSecondary,
						TextXAlignment = Enum.TextXAlignment.Left })
				end
			else
				-- Empty slot
				makeLabel(tile, { Text = "—", Size = UDim2.new(1, 0, 1, 0),
					TextSize = 20, TextColor3 = Theme.Colors.TextDisabled,
					TextXAlignment = Enum.TextXAlignment.Center })
			end

			-- Click: filter inventory to this slot type
			tile.MouseButton1Click:Connect(function()
				if item then
					-- Item equipped: open detail view with UNEQUIP
					openItemDetail(item, nil, true)
				else
					-- Empty slot: filter inventory to this slot type
					currentFilter = slotDef.slot
					if slotDef.slot == "Doctrine" then currentFilter = "Doctrine" end
					buildInventory()
				end
			end)
		end

	else -- consumables tab
		local consGrid = Instance.new("Frame")
		consGrid.Size = UDim2.new(1, 0, 1, 0)
		consGrid.BackgroundTransparency = 1
		consGrid.Parent = content

		local gridLayout = Instance.new("UIGridLayout", consGrid)
		gridLayout.CellSize = UDim2.new(1/3, -3, 0.5, -2)
		gridLayout.CellPadding = UDim2.new(0, 3, 0, 3)
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder

		for i = 1, 6 do
			local slotKey = "Cons" .. i
			local locked = MockData.ConsSlotLocked[slotKey]
			local item = MockData.GetEquipped(unit.id, slotKey)

			local cell = Instance.new("TextButton")
			cell.BackgroundColor3 = locked and Color3.fromRGB(10, 10, 15) or Theme.Colors.Panel
			cell.BackgroundTransparency = locked and 0.7 or 0.3
			cell.BorderSizePixel = 0
			cell.Text = ""
			cell.LayoutOrder = i
			cell.Parent = consGrid
			Instance.new("UICorner", cell).CornerRadius = UDim.new(0, 4)

			-- Slot number
			makeLabel(cell, { Text = tostring(i), Size = UDim2.new(0, 12, 0, 10),
				Position = UDim2.new(0, 2, 0, 1),
				TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextDisabled })

			if locked then
				makeLabel(cell, { Text = "🔒", Size = UDim2.new(1, 0, 1, 0),
					TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center,
					TextColor3 = Theme.Colors.TextDisabled })
			elseif item then
				makeLabel(cell, { Text = item.icon or "🧪", Size = UDim2.new(1, 0, 0, 28),
					Position = UDim2.new(0, 0, 0, 4),
					TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center })
				if item.qty and item.qty > 1 then
					makeLabel(cell, { Text = "x" .. item.qty,
						Size = UDim2.new(0, 20, 0, 10),
						Position = UDim2.new(1, -22, 0, 2),
						TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextPrimary,
						TextXAlignment = Enum.TextXAlignment.Right,
						Font = Theme.Font.PrimaryBold })
				end
				makeLabel(cell, { Text = item.name, Size = UDim2.new(1, -4, 0, 12),
					Position = UDim2.new(0, 2, 1, -14),
					TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextSecondary,
					TextXAlignment = Enum.TextXAlignment.Center })
			else
				makeLabel(cell, { Text = "—", Size = UDim2.new(1, 0, 1, 0),
					TextSize = 20, TextColor3 = Theme.Colors.TextDisabled,
					TextXAlignment = Enum.TextXAlignment.Center })
			end
		end
	end
end

--------------------------------------------------
-- INVENTORY BROWSER (left side, full)
--------------------------------------------------

local filterBar, itemGrid, footerLabel

local function buildFilterBar(parent)
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
		chip.BackgroundTransparency = (currentFilter == f.id) and 0.1 or 0.5
		chip.BorderSizePixel = 0
		chip.Font = Theme.Font.Primary
		chip.TextSize = 9
		chip.TextColor3 = (currentFilter == f.id) and Theme.Colors.TextGold or Theme.Colors.TextSecondary
		chip.Text = f.icon .. "\n" .. f.label
		chip.LayoutOrder = i
		chip.Parent = filterBar
		Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 4)

		if currentFilter == f.id then
			local stroke = Instance.new("UIStroke", chip)
			stroke.Color = Theme.Colors.TextGold
			stroke.Thickness = 1
		end

		chip.MouseButton1Click:Connect(function()
			currentFilter = f.id
			selectedItemId = nil
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
	grid.CellSize = UDim2.new(0, 72, 1/3, -4)
	grid.CellPadding = UDim2.new(0, 4, 0, 3)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirection = Enum.FillDirection.Horizontal

	local items = MockData.GetFilteredItems(currentFilter)

	-- Rarity filter
	if currentRarity ~= "All" then
		local filtered = {}
		for _, item in ipairs(items) do
			if item.rarity == currentRarity then table.insert(filtered, item) end
		end
		items = filtered
	end

	-- Sort
	local RARITY_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }
	local sortOpt = SORT_OPTIONS[currentSort] or SORT_OPTIONS[1]
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
		local isEquipped = MockData.IsEquipped(item.id, unit.id)
		local isSelected = (selectedItemId == item.id)

		local card = Instance.new("TextButton")
		card.Size = UDim2.new(1, 0, 1, 0)  -- sized by UIGridLayout CellSize
		if isSelected then
			card.BackgroundColor3 = Color3.fromRGB(40, 35, 20)
			card.BackgroundTransparency = 0.05
		else
			card.BackgroundColor3 = getRarityColor(item.rarity)
			card.BackgroundTransparency = 0.75
		end
		card.BorderSizePixel = 0
		card.Text = ""
		card.AutoButtonColor = true
		card.LayoutOrder = i
		card.Parent = itemGrid
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 4)

		-- Rarity frame border
		local stroke = Instance.new("UIStroke", card)
		stroke.Color = isSelected and Theme.Colors.TextGold or getRarityColor(item.rarity)
		stroke.Thickness = isSelected and 2 or 1.5

		-- Level (top-left)
		local lvlText = item.cat == "Consumable" and ("×" .. (item.qty or 1)) or ("Lv." .. (item.lv or 1))
		makeLabel(card, { Text = lvlText, Size = UDim2.new(0, 36, 0, 12),
			Position = UDim2.new(0, 3, 0, 2),
			TextSize = 9, TextColor3 = Theme.Colors.TextSecondary,
			Font = Theme.Font.Mono })

		-- Equipped marker (top-right)
		if isEquipped then
			local marker = Instance.new("Frame")
			marker.Size = UDim2.new(0, 14, 0, 12)
			marker.Position = UDim2.new(1, -16, 0, 2)
			marker.BackgroundColor3 = Theme.Colors.TextGold
			marker.BorderSizePixel = 0
			marker.Parent = card
			Instance.new("UICorner", marker).CornerRadius = UDim.new(0, 2)
			makeLabel(marker, { Text = "E", Size = UDim2.fromScale(1, 1),
				TextSize = 8, Font = Theme.Font.PrimaryBold,
				TextColor3 = Color3.fromRGB(0, 0, 0),
				TextXAlignment = Enum.TextXAlignment.Center })
		end

		-- NEW badge (top-right, below equipped marker if both)
		if item.isNew then
			local newBadge = Instance.new("Frame")
			newBadge.Size = UDim2.new(0, 22, 0, 12)
			newBadge.Position = UDim2.new(1, -24, 0, isEquipped and 16 or 2)
			newBadge.BackgroundColor3 = Theme.Colors.Success
			newBadge.BorderSizePixel = 0
			newBadge.Parent = card
			Instance.new("UICorner", newBadge).CornerRadius = UDim.new(0, 2)
			makeLabel(newBadge, { Text = "NEW", Size = UDim2.fromScale(1, 1),
				TextSize = Theme.Text.Badge(), Font = Theme.Font.PrimaryBold,
				TextColor3 = Color3.fromRGB(0, 0, 0),
				TextXAlignment = Enum.TextXAlignment.Center })
		end

		-- Icon (center)
		makeLabel(card, { Text = item.icon or "?", Size = UDim2.new(1, 0, 0, 28),
			Position = UDim2.new(0, 0, 0.15, 0),
			TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center })

		-- Name (bottom)
		local nameBg = Instance.new("Frame")
		nameBg.Size = UDim2.new(1, 0, 0, 14)
		nameBg.Position = UDim2.new(0, 0, 1, -14)
		nameBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		nameBg.BackgroundTransparency = 0.4
		nameBg.BorderSizePixel = 0
		nameBg.Parent = card
		makeLabel(nameBg, { Text = item.name, Size = UDim2.new(1, -4, 1, 0),
			Position = UDim2.new(0, 2, 0, 0),
			TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextPrimary,
			TextXAlignment = Enum.TextXAlignment.Left })

		card.MouseButton1Click:Connect(function()
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
	if not inventoryPanel then return end
	clearChildren(inventoryPanel)
	pad(inventoryPanel, 8, 8, 8, 8)

	-- Single toolbar row: Search + Type + Rarity + Sort
	local ctrlRow = Instance.new("Frame")
	ctrlRow.Size = UDim2.new(1, 0, 0, 24)
	ctrlRow.Position = UDim2.new(0, 0, 0, 0)
	ctrlRow.BackgroundTransparency = 1
	ctrlRow.Parent = inventoryPanel

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
	local filterLabel = currentFilter == "All" and "Type ▾" or (currentFilter .. " ▾")
	local rarityLabel = currentRarity == "All" and "Rarity ▾" or (currentRarity .. " ▾")
	local sortLabel = SORT_OPTIONS[currentSort].label .. " ▾"

	-- Shared dropdown helper: opens a menu below the anchor button
	local function closeDropdown()
		if activeDropdown then activeDropdown:Destroy(); activeDropdown = nil end
	end

	local function showDropdown(anchorBtn, options, onSelect)
		closeDropdown()

		local rowH = 22
		local menuH = #options * rowH + 4
		local menuW = math.max(anchorBtn.AbsoluteSize.X, 80)

		-- ScreenGui overlay to capture outside clicks
		activeDropdown = Instance.new("ScreenGui")
		activeDropdown.Name = "DropdownOverlay"
		activeDropdown.DisplayOrder = 105
		activeDropdown.ResetOnSpawn = false
		activeDropdown.Parent = getPlayerGui()

		-- Invisible full-screen backdrop to close on outside click
		local ddBackdrop = Instance.new("TextButton")
		ddBackdrop.Size = UDim2.fromScale(1, 1)
		ddBackdrop.BackgroundTransparency = 1
		ddBackdrop.Text = ""
		ddBackdrop.Parent = activeDropdown
		ddBackdrop.MouseButton1Click:Connect(closeDropdown)

		-- Menu panel, positioned below the anchor button
		local menuPanel = Instance.new("Frame")
		menuPanel.Size = UDim2.new(0, menuW, 0, menuH)
		menuPanel.Position = UDim2.new(0, anchorBtn.AbsolutePosition.X, 0, anchorBtn.AbsolutePosition.Y + anchorBtn.AbsoluteSize.Y + 2)
		menuPanel.BackgroundColor3 = Theme.Colors.Panel
		menuPanel.BorderSizePixel = 0
		menuPanel.ZIndex = 50
		menuPanel.Parent = activeDropdown
		Instance.new("UICorner", menuPanel).CornerRadius = UDim.new(0, 4)
		local menuStroke = Instance.new("UIStroke", menuPanel)
		menuStroke.Color = Theme.Colors.Border
		menuStroke.Thickness = 1

		local menuLayout = Instance.new("UIListLayout", menuPanel)
		menuLayout.Padding = UDim.new(0, 0)
		menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
		pad(menuPanel, 2, 2, 2, 2)

		for idx, opt in ipairs(options) do
			local row = Instance.new("TextButton")
			row.Size = UDim2.new(1, 0, 0, rowH)
			row.BackgroundColor3 = Theme.Colors.PanelRaised
			row.BackgroundTransparency = opt.active and 0.2 or 0.6
			row.Font = Theme.Font.Primary
			row.TextSize = Theme.Text.Small()
			row.TextColor3 = opt.active and Theme.Colors.TextGold or Theme.Colors.TextPrimary
			row.Text = opt.label
			row.BorderSizePixel = 0
			row.LayoutOrder = idx
			row.ZIndex = 51
			row.Parent = menuPanel
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, 3)
			row.MouseButton1Click:Connect(function()
				closeDropdown()
				onSelect(opt.value, idx)
			end)
		end
	end

	local function makeDropdown(text, order, isActive)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 62, 1, 0)
		btn.BackgroundColor3 = Theme.Colors.Surface
		btn.BackgroundTransparency = 0.2
		btn.Font = Theme.Font.Primary
		btn.TextSize = Theme.Text.Small()
		btn.TextColor3 = isActive and Theme.Colors.TextGold or Theme.Colors.TextSecondary
		btn.Text = text
		btn.BorderSizePixel = 0
		btn.LayoutOrder = order
		btn.Parent = ctrlRow
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 3)
		return btn
	end

	-- Type filter button — cycles through category filters
	local typeBtn = makeDropdown(filterLabel, 2, currentFilter ~= "All")
	typeBtn.MouseButton1Click:Connect(function()
		local opts = {}
		table.insert(opts, { label = "⊞ All Types", value = "All", active = (currentFilter == "All") })
		for _, f in ipairs(CATEGORY_FILTERS) do
			if f.id ~= "All" then
				table.insert(opts, { label = f.icon .. " " .. f.label, value = f.id, active = (currentFilter == f.id) })
			end
		end
		showDropdown(typeBtn, opts, function(val)
			currentFilter = val
			if val == "All" then
				currentRarity = "All"  -- reset rarity too for full reset
			end
			selectedItemId = nil
			buildInventory()
		end)
	end)

	-- Rarity filter button — cycles through rarity options
	local rarityBtn = makeDropdown(rarityLabel, 3, currentRarity ~= "All")
	rarityBtn.MouseButton1Click:Connect(function()
		local opts = {}
		for _, r in ipairs(RARITY_OPTIONS) do
			local clr = r == "All" and Theme.Colors.TextPrimary or getRarityColor(r)
			local displayLabel = r == "All" and "All Rarities" or r
			table.insert(opts, { label = displayLabel, value = r, active = (currentRarity == r) })
		end
		showDropdown(rarityBtn, opts, function(val)
			currentRarity = val
			selectedItemId = nil
			buildInventory()
		end)
	end)

	-- Sort button — cycles through sort modes
	local sortBtn = makeDropdown(sortLabel, 4, false)
	sortBtn.MouseButton1Click:Connect(function()
		local opts = {}
		for si, s in ipairs(SORT_OPTIONS) do
			table.insert(opts, { label = s.label, value = si, active = (currentSort == si) })
		end
		showDropdown(sortBtn, opts, function(val)
			currentSort = val
			buildInventory()
		end)
	end)

	buildItemGrid(inventoryPanel)
end

--------------------------------------------------
-- ITEM DETAIL OVERLAY (full-screen modal)
--------------------------------------------------

local detailOverlay = nil

closeDetail = function()
	if detailOverlay then detailOverlay:Destroy(); detailOverlay = nil end
end

openItemDetail = function(item, compareItem, isEquippedMode)
	closeDetail()
	if activeDropdown then activeDropdown:Destroy(); activeDropdown = nil end
	if not item then return end

	local unit = MockData.GetSelectedUnit()

	-- Full-screen overlay
	detailOverlay = Instance.new("ScreenGui")
	detailOverlay.Name = "ItemDetailOverlay"
	detailOverlay.DisplayOrder = 110
	detailOverlay.ResetOnSpawn = false
	detailOverlay.Parent = getPlayerGui()

	-- Dim backdrop
	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.Overlay
	backdrop.BackgroundTransparency = 0.4
	backdrop.Text = ""
	backdrop.BorderSizePixel = 0
	backdrop.Parent = detailOverlay
	backdrop.MouseButton1Click:Connect(closeDetail)

	-- Center panel
	-- Anchored to left edge. Width: 55% solo, 70% comparison.
	-- Full height minus small top/bottom margin.
	local wScale = compareItem and 0.70 or 0.55
	local hScale = 0.90
	local panel = Theme.MakePanel("DetailPanel",
		UDim2.new(wScale, 0, hScale, 0),
		UDim2.new(0, 6, 0.5, 0),
		Vector2.new(0, 0.5),
		detailOverlay)
	panel.ClipsDescendants = true

	pad(panel, 10, 12, 12, 10)

	if compareItem then
		-- ============ COMPARISON MODE ============
		buildComparisonContent(panel, item, compareItem, unit)
	else
		-- ============ SOLO DETAIL MODE ============
		buildSoloDetailContent(panel, item)
	end

	-- ============ BUTTON BAR (fixed bottom-right of SCREEN, outside the panel) ============
	-- Matches battle UI Execute/Back position: bottom-right, anchored (1,1).
	-- Right-to-left: EQUIP (rightmost), BACK, COMPARE (if applicable).
	local PAD = 8
	local BTN_W = 80
	local BTN_H = 32
	local BTN_GAP = 4

	-- Container bar — positioned on the overlay, not inside the panel
	local btnBar = Instance.new("Frame")
	btnBar.Name = "DetailBtnBar"
	btnBar.BackgroundTransparency = 1
	btnBar.AnchorPoint = Vector2.new(1, 1)
	btnBar.Position = UDim2.new(1, -PAD, 1, -PAD)
	btnBar.Parent = detailOverlay

	local btnIndex = 0  -- counts from right edge

	local function addFooterBtn(text, color, onClick)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, BTN_W, 0, BTN_H)
		btn.Position = UDim2.new(1, -(BTN_W + BTN_GAP) * btnIndex, 0, 0)
		btn.AnchorPoint = Vector2.new(1, 0)
		btn.BackgroundColor3 = color
		btn.BackgroundTransparency = 0.15
		btn.Font = Theme.Font.PrimaryBold
		btn.TextSize = Theme.Text.Body()
		btn.TextColor3 = Theme.Colors.TextPrimary
		btn.Text = text
		btn.BorderSizePixel = 0
		btn.Parent = btnBar
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
		btn.MouseButton1Click:Connect(onClick)
		btnIndex = btnIndex + 1
		return btn
	end

	-- 1st from right: EQUIP or UNEQUIP
	if isEquippedMode then
		local eqSlot = item.cat
		-- Don't allow unequipping Doctrine
		if eqSlot ~= "Doctrine" then
			addFooterBtn("UNEQUIP", Theme.Colors.Danger, function()
				if unit then
					MockData.MockUnequip(unit.id, eqSlot)
					closeDetail()
					LoadoutScreen.Refresh()
				end
			end)
		end
	else
		addFooterBtn("EQUIP", Theme.Colors.Success, function()
			if unit then
				local slot = item.cat
				MockData.MockEquip(unit.id, slot, item.id)
				closeDetail()
				LoadoutScreen.Refresh()
			end
		end)
	end

	-- 2nd from right: BACK
	addFooterBtn("BACK", Theme.Colors.Surface, closeDetail)

	-- 3rd from right: COMPARE (only in solo mode when an equipped item exists to compare)
	if not compareItem and unit then
		local slot = item.cat
		local equippedItem = MockData.GetEquipped(unit.id, slot)
		if equippedItem and equippedItem.id ~= item.id then
			addFooterBtn("COMPARE", Theme.Colors.Surface, function()
				openItemDetail(item, equippedItem)
			end)
		end
	end

	-- 3rd from right: DETAILS (only in compare mode — returns to solo detail view)
	if compareItem then
		addFooterBtn("DETAILS", Theme.Colors.Surface, function()
			openItemDetail(item, nil)
		end)
	end

	-- Size the bar to fit all buttons
	btnBar.Size = UDim2.new(0, (BTN_W + BTN_GAP) * btnIndex, 0, BTN_H)
end

--------------------------------------------------
-- SOLO DETAIL CONTENT (reference image 1)
--------------------------------------------------

buildSoloDetailContent = function(panel, item)
	local rc = getRarityColor(item.rarity)

	-- Item header: portrait + name + subtitle + tags + flavor
	local headerY = 0
	local portraitSize = 64

	-- Portrait (larger, rarity-tinted)
	local iconFrame = Instance.new("Frame")
	iconFrame.Size = UDim2.new(0, portraitSize, 0, portraitSize)
	iconFrame.Position = UDim2.new(0, 0, 0, headerY)
	iconFrame.BackgroundColor3 = rc
	iconFrame.BackgroundTransparency = 0.75
	iconFrame.BorderSizePixel = 0
	iconFrame.Parent = panel
	Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(0, 6)
	local iconStroke = Instance.new("UIStroke", iconFrame)
	iconStroke.Color = rc
	iconStroke.Thickness = 1.5
	makeLabel(iconFrame, { Text = item.icon or "?", Size = UDim2.fromScale(1, 1),
		TextSize = 30, TextXAlignment = Enum.TextXAlignment.Center })

	local textX = portraitSize + 8
	-- Name
	makeLabel(panel, { Text = item.name, Size = UDim2.new(1, -textX, 0, 18),
		Position = UDim2.new(0, textX, 0, headerY),
		Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Heading(),
		TextColor3 = Theme.Colors.TextPrimary })

	-- Subtitle: Lv.X · Rarity · SubType
	local subParts = {}
	if item.lv and item.lv > 0 then table.insert(subParts, "Lv." .. item.lv) end
	table.insert(subParts, item.rarity or "Common")
	if item.sub then table.insert(subParts, item.sub) end
	makeLabel(panel, { Text = table.concat(subParts, "  ·  "),
		Size = UDim2.new(1, -textX, 0, 14),
		Position = UDim2.new(0, textX, 0, headerY + 18),
		TextSize = Theme.Text.Small(), TextColor3 = rc })

	-- Tags
	local tagY = headerY + 34
	if item.tags and #item.tags > 0 then
		local tagRow = Instance.new("Frame")
		tagRow.Size = UDim2.new(1, -textX, 0, 16)
		tagRow.Position = UDim2.new(0, textX, 0, tagY)
		tagRow.BackgroundTransparency = 1
		tagRow.Parent = panel
		local tagLayout = Instance.new("UIListLayout", tagRow)
		tagLayout.FillDirection = Enum.FillDirection.Horizontal
		tagLayout.Padding = UDim.new(0, 3)
		for ti, tag in ipairs(item.tags) do
			local chip = Instance.new("Frame")
			chip.Size = UDim2.new(0, #tag * 5 + 10, 0, 14)
			chip.BackgroundColor3 = Theme.Colors.Surface
			chip.BackgroundTransparency = 0.3
			chip.BorderSizePixel = 0
			chip.LayoutOrder = ti
			chip.Parent = tagRow
			Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 7)
			makeLabel(chip, { Text = tag, Size = UDim2.fromScale(1, 1),
				TextSize = Theme.Text.Badge(), TextColor3 = Theme.Colors.TextSecondary,
				TextXAlignment = Enum.TextXAlignment.Center })
		end
		tagY = tagY + 18
	end

	-- Flavor text (below tags)
	if item.flavor then
		makeLabel(panel, { Text = item.flavor,
			Size = UDim2.new(1, -textX, 0, 16),
			Position = UDim2.new(0, textX, 0, tagY),
			TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextDisabled,
			TextWrapped = true, Font = Enum.Font.SourceSansItalic })
		tagY = tagY + 18
	end

	-- Divider
	local divY = math.max(tagY + 2, portraitSize + 4)
	local div = Instance.new("Frame")
	div.Size = UDim2.new(1, 0, 0, 1)
	div.Position = UDim2.new(0, 0, 0, divY)
	div.BackgroundColor3 = Theme.Colors.Border
	div.BorderSizePixel = 0
	div.Parent = panel

	-- Content area: two columns below divider
	local bodyY = divY + 6
	local halfW = 0.48

	-- Container for switchable content (base vs bonus)
	local contentFrame = Instance.new("Frame")
	contentFrame.Size = UDim2.new(1, 0, 1, -(bodyY + 30))
	contentFrame.Position = UDim2.new(0, 0, 0, bodyY)
	contentFrame.BackgroundTransparency = 1
	contentFrame.Parent = panel

	-- State: which view is shown
	local showingBonus = false

	local function buildBaseView()
		for _, child in ipairs(contentFrame:GetChildren()) do child:Destroy() end

		local leftCol = Instance.new("Frame")
		leftCol.Size = UDim2.new(halfW, 0, 1, 0)
		leftCol.Position = UDim2.new(0, 0, 0, 0)
		leftCol.BackgroundTransparency = 1
		leftCol.Parent = contentFrame

		local rightCol = Instance.new("Frame")
		rightCol.Size = UDim2.new(halfW, 0, 1, 0)
		rightCol.Position = UDim2.new(1 - halfW, 0, 0, 0)
		rightCol.BackgroundTransparency = 1
		rightCol.Parent = contentFrame

		-- LEFT: Base stats
		local statY = 0
		local bs = item.baseStats or {}

		if item.isWeapon then
			-- Weapon: Attack, Range, Defense, WT, RT Delay
			local weaponStats = {
				{ label = "Attack", value = bs.Attack },
				{ label = "Range", value = bs.Range },
				{ label = "Defense", value = bs.Defense },
				{ label = "WT", value = bs.WT },
				{ label = "RT Delay", value = bs.RTDelay },
			}
			for _, s in ipairs(weaponStats) do
				if s.value ~= nil then
					local row = Instance.new("Frame")
					row.Size = UDim2.new(1, 0, 0, 16)
					row.Position = UDim2.new(0, 0, 0, statY)
					row.BackgroundTransparency = 1
					row.Parent = leftCol
					makeLabel(row, { Text = s.label, Size = UDim2.new(0.6, 0, 1, 0),
						TextSize = Theme.Text.Body(), TextColor3 = Theme.Colors.TextSecondary })
					makeLabel(row, { Text = tostring(s.value), Size = UDim2.new(0.4, 0, 1, 0),
						Position = UDim2.new(0.6, 0, 0, 0),
						TextSize = Theme.Text.Body(), TextColor3 = Theme.Colors.TextPrimary,
						Font = Theme.Font.PrimaryBold, TextXAlignment = Enum.TextXAlignment.Right })
					statY = statY + 18
				end
			end
		else
			-- Non-weapon: Defense, HP, MP, WT
			local armorStats = {
				{ label = "Defense", value = bs.Defense },
				{ label = "HP", value = bs.HP },
				{ label = "MP", value = bs.MP },
				{ label = "WT", value = bs.WT },
			}
			for _, s in ipairs(armorStats) do
				if s.value ~= nil and s.value ~= 0 then
					local row = Instance.new("Frame")
					row.Size = UDim2.new(1, 0, 0, 16)
					row.Position = UDim2.new(0, 0, 0, statY)
					row.BackgroundTransparency = 1
					row.Parent = leftCol
					makeLabel(row, { Text = s.label, Size = UDim2.new(0.6, 0, 1, 0),
						TextSize = Theme.Text.Body(), TextColor3 = Theme.Colors.TextSecondary })
					makeLabel(row, { Text = tostring(s.value), Size = UDim2.new(0.4, 0, 1, 0),
						Position = UDim2.new(0.6, 0, 0, 0),
						TextSize = Theme.Text.Body(), TextColor3 = Theme.Colors.TextPrimary,
						Font = Theme.Font.PrimaryBold, TextXAlignment = Enum.TextXAlignment.Right })
					statY = statY + 18
				end
			end
		end

		-- RIGHT: Archetype passives
		makeLabel(rightCol, { Text = "PASSIVES", Size = UDim2.new(1, 0, 0, 12),
			Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextSecondary })
		local passY = 14
		if item.passives and #item.passives > 0 then
			for _, p in ipairs(item.passives) do
				local pCard = Instance.new("Frame")
				pCard.Size = UDim2.new(1, 0, 0, 48)
				pCard.Position = UDim2.new(0, 0, 0, passY)
				pCard.BackgroundColor3 = Theme.Colors.PanelRaised
				pCard.BackgroundTransparency = 0.3
				pCard.BorderSizePixel = 0
				pCard.Parent = rightCol
				Instance.new("UICorner", pCard).CornerRadius = UDim.new(0, 4)
				makeLabel(pCard, { Text = p.icon or "✦", Size = UDim2.new(0, 28, 0, 28),
					Position = UDim2.new(0, 3, 0, 3),
					TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center })
				makeLabel(pCard, { Text = p.name or "Passive",
					Size = UDim2.new(1, -36, 0, 14), Position = UDim2.new(0, 34, 0, 1),
					Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Body(),
					TextColor3 = Theme.Colors.Success })
				makeLabel(pCard, { Text = p.desc or "",
					Size = UDim2.new(1, -36, 0, 28), Position = UDim2.new(0, 34, 0, 16),
					TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextSecondary,
					TextWrapped = true })
				passY = passY + 52
			end
		else
			makeLabel(rightCol, { Text = "None", Size = UDim2.new(1, 0, 0, 14),
				Position = UDim2.new(0, 0, 0, passY),
				TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextDisabled })
		end
	end

	local function buildBonusView()
		for _, child in ipairs(contentFrame:GetChildren()) do child:Destroy() end

		local leftCol = Instance.new("Frame")
		leftCol.Size = UDim2.new(halfW, 0, 1, 0)
		leftCol.Position = UDim2.new(0, 0, 0, 0)
		leftCol.BackgroundTransparency = 1
		leftCol.Parent = contentFrame

		local rightCol = Instance.new("Frame")
		rightCol.Size = UDim2.new(halfW, 0, 1, 0)
		rightCol.Position = UDim2.new(1 - halfW, 0, 0, 0)
		rightCol.BackgroundTransparency = 1
		rightCol.Parent = contentFrame

		-- LEFT: Bonus numerical stats
		makeLabel(leftCol, { Text = "BONUS STATS", Size = UDim2.new(1, 0, 0, 12),
			Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextSecondary })
		local statY = 14
		local bs = item.bonusStats or {}
		local BONUS_ORDER = { "STR", "INT", "DEX", "AGI", "VIT", "LUK", "HP", "MP", "Fortune", "Precision", "Evasiveness" }
		local hasAny = false
		for _, sn in ipairs(BONUS_ORDER) do
			local bv = bs[sn]
			if bv and bv ~= 0 then
				hasAny = true
				local sign = bv > 0 and "+" or ""
				makeLabel(leftCol, { Text = sn .. "  " .. sign .. bv,
					Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 4, 0, statY),
					TextSize = Theme.Text.Body(), TextColor3 = Theme.Colors.Success })
				statY = statY + 16
			end
		end
		if not hasAny then
			makeLabel(leftCol, { Text = "None", Size = UDim2.new(1, 0, 0, 14),
				Position = UDim2.new(0, 4, 0, statY),
				TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextDisabled })
		end

		-- RIGHT: Bonus passives
		makeLabel(rightCol, { Text = "BONUS PASSIVES", Size = UDim2.new(1, 0, 0, 12),
			Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextSecondary })
		local passY = 14
		local bp = item.bonusPassives or {}
		if #bp > 0 then
			for _, p in ipairs(bp) do
				local pCard = Instance.new("Frame")
				pCard.Size = UDim2.new(1, 0, 0, 48)
				pCard.Position = UDim2.new(0, 0, 0, passY)
				pCard.BackgroundColor3 = Theme.Colors.PanelRaised
				pCard.BackgroundTransparency = 0.3
				pCard.BorderSizePixel = 0
				pCard.Parent = rightCol
				Instance.new("UICorner", pCard).CornerRadius = UDim.new(0, 4)
				makeLabel(pCard, { Text = p.icon or "✦", Size = UDim2.new(0, 28, 0, 28),
					Position = UDim2.new(0, 3, 0, 3),
					TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center })
				makeLabel(pCard, { Text = p.name or "Passive",
					Size = UDim2.new(1, -36, 0, 14), Position = UDim2.new(0, 34, 0, 1),
					Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Body(),
					TextColor3 = Theme.Colors.Info })
				makeLabel(pCard, { Text = p.desc or "",
					Size = UDim2.new(1, -36, 0, 28), Position = UDim2.new(0, 34, 0, 16),
					TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextSecondary,
					TextWrapped = true })
				passY = passY + 52
			end
		else
			makeLabel(rightCol, { Text = "None", Size = UDim2.new(1, 0, 0, 14),
				Position = UDim2.new(0, 0, 0, passY),
				TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextDisabled })
		end
	end

	-- Show base view initially
	buildBaseView()

	-- Toggle button (lower-left of panel)
	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Size = UDim2.new(0, 90, 0, 24)
	toggleBtn.Position = UDim2.new(0, 0, 1, -28)
	toggleBtn.BackgroundColor3 = Theme.Colors.Surface
	toggleBtn.BackgroundTransparency = 0.2
	toggleBtn.Font = Theme.Font.PrimaryBold
	toggleBtn.TextSize = 10
	toggleBtn.TextColor3 = Theme.Colors.TextSecondary
	toggleBtn.Text = "Show Bonus >"
	toggleBtn.BorderSizePixel = 0
	toggleBtn.Parent = panel
	Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 4)
	toggleBtn.MouseButton1Click:Connect(function()
		showingBonus = not showingBonus
		if showingBonus then
			buildBonusView()
			toggleBtn.Text = "< Show Base"
		else
			buildBaseView()
			toggleBtn.Text = "Show Bonus >"
		end
	end)
end


--------------------------------------------------
-- COMPARISON CONTENT (reference image 2)
--------------------------------------------------

buildComparisonContent = function(panel, selectedItem, currentItem, unit)
	-- Compact header: two item cards side by side (persistent, not affected by toggle)
	local headerY = 0
	local cardH = 40
	local halfW = 0.46

	-- CURRENT label + card (left)
	makeLabel(panel, { Text = "CURRENT", Size = UDim2.new(halfW, 0, 0, 12),
		Position = UDim2.new(0, 0, 0, headerY),
		TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextSecondary,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.Font.PrimaryBold })

	local curCard = Instance.new("Frame")
	curCard.Size = UDim2.new(halfW, 0, 0, cardH)
	curCard.Position = UDim2.new(0, 0, 0, headerY + 14)
	curCard.BackgroundColor3 = getRarityColor(currentItem.rarity)
	curCard.BackgroundTransparency = 0.75
	curCard.BorderSizePixel = 0
	curCard.Parent = panel
	Instance.new("UICorner", curCard).CornerRadius = UDim.new(0, 4)
	Instance.new("UIStroke", curCard).Color = getRarityColor(currentItem.rarity)
	makeLabel(curCard, { Text = currentItem.icon or "?", Size = UDim2.new(0, 28, 1, 0),
		TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center })
	makeLabel(curCard, { Text = currentItem.name,
		Size = UDim2.new(1, -32, 0, 14), Position = UDim2.new(0, 30, 0, 3),
		Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Small(),
		TextColor3 = Theme.Colors.TextPrimary })
	makeLabel(curCard, { Text = "Lv." .. (currentItem.lv or 0) .. "  (Equipped)",
		Size = UDim2.new(1, -32, 0, 12), Position = UDim2.new(0, 30, 0, 18),
		TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextSecondary })

	-- SELECTED label + card (right)
	makeLabel(panel, { Text = "SELECTED", Size = UDim2.new(halfW, 0, 0, 12),
		Position = UDim2.new(1 - halfW, 0, 0, headerY),
		TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextSecondary,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.Font.PrimaryBold })

	local selCard = Instance.new("Frame")
	selCard.Size = UDim2.new(halfW, 0, 0, cardH)
	selCard.Position = UDim2.new(1 - halfW, 0, 0, headerY + 14)
	selCard.BackgroundColor3 = getRarityColor(selectedItem.rarity)
	selCard.BackgroundTransparency = 0.75
	selCard.BorderSizePixel = 0
	selCard.Parent = panel
	Instance.new("UICorner", selCard).CornerRadius = UDim.new(0, 4)
	local selStroke = Instance.new("UIStroke", selCard)
	selStroke.Color = Theme.Colors.TextGold
	selStroke.Thickness = 2
	makeLabel(selCard, { Text = selectedItem.icon or "?", Size = UDim2.new(0, 28, 1, 0),
		TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center })
	makeLabel(selCard, { Text = selectedItem.name,
		Size = UDim2.new(1, -32, 0, 14), Position = UDim2.new(0, 30, 0, 3),
		Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Small(),
		TextColor3 = Theme.Colors.TextPrimary })
	makeLabel(selCard, { Text = "Lv." .. (selectedItem.lv or 0),
		Size = UDim2.new(1, -32, 0, 12), Position = UDim2.new(0, 30, 0, 18),
		TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextSecondary })

	-- Divider
	local divY = headerY + 14 + cardH + 4
	local div = Instance.new("Frame")
	div.Size = UDim2.new(1, 0, 0, 1)
	div.Position = UDim2.new(0, 0, 0, divY)
	div.BackgroundColor3 = Theme.Colors.Border
	div.BorderSizePixel = 0
	div.Parent = panel

	-- Content container (switchable)
	local bodyY = divY + 4
	local contentFrame = Instance.new("Frame")
	contentFrame.Size = UDim2.new(1, 0, 1, -(bodyY + 30))
	contentFrame.Position = UDim2.new(0, 0, 0, bodyY)
	contentFrame.BackgroundTransparency = 1
	contentFrame.Parent = panel

	local showingBonus = false

	-- Helper: build a stat comparison row
	local COMPARE_STATS = { "Attack", "Range", "Defense", "WT", "RTDelay" }
	local COMPARE_LABELS = { Attack="Attack", Range="Range", Defense="Defense", WT="WT", RTDelay="RT Delay" }
	local LOWER_IS_BETTER = { WT = true, RTDelay = true }
	local STAT_ORDER = { "STR", "INT", "DEX", "AGI", "VIT", "LUK" }

	local function addStatRow(parent, label, cvStr, svStr, delta, isGood, y)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 16)
		row.Position = UDim2.new(0, 0, 0, y)
		row.BackgroundTransparency = 1
		row.Parent = parent
		makeLabel(row, { Text = cvStr, Size = UDim2.new(0.18, 0, 1, 0),
			TextSize = Theme.Text.Body(), TextColor3 = Theme.Colors.TextPrimary,
			TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.Font.PrimaryBold })
		makeLabel(row, { Text = label, Size = UDim2.new(0.24, 0, 1, 0),
			Position = UDim2.new(0.18, 0, 0, 0),
			TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextSecondary,
			TextXAlignment = Enum.TextXAlignment.Center })
		makeLabel(row, { Text = svStr, Size = UDim2.new(0.18, 0, 1, 0),
			Position = UDim2.new(0.54, 0, 0, 0),
			TextSize = Theme.Text.Body(), TextColor3 = Theme.Colors.TextPrimary,
			TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.Font.PrimaryBold })
		if delta and delta ~= "" then
			makeLabel(row, { Text = delta, Size = UDim2.new(0.14, 0, 1, 0),
				Position = UDim2.new(0.78, 0, 0, 0),
				TextSize = Theme.Text.Small(), Font = Theme.Font.PrimaryBold,
				TextColor3 = isGood and Theme.Colors.Success or Theme.Colors.Danger,
				TextXAlignment = Enum.TextXAlignment.Center })
		end
	end

	local function addPassiveCard(parent, name, desc, isLost, y, xScale)
		local card = Instance.new("Frame")
		card.Size = UDim2.new(0.48, 0, 0, 36)
		card.Position = UDim2.new(xScale, 0, 0, y)
		card.BackgroundColor3 = isLost and Theme.Colors.Danger or Theme.Colors.Success
		card.BackgroundTransparency = 0.85
		card.BorderSizePixel = 0
		card.Parent = parent
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 4)
		local tagColor = isLost and Theme.Colors.Danger or Theme.Colors.Success
		local suffix = isLost and " (Lost)" or " (Gained)"
		makeLabel(card, { Text = name .. suffix,
			Size = UDim2.new(1, -6, 0, 12), Position = UDim2.new(0, 3, 0, 2),
			Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Small(),
			TextColor3 = tagColor })
		makeLabel(card, { Text = desc or "",
			Size = UDim2.new(1, -6, 0, 18), Position = UDim2.new(0, 3, 0, 14),
			TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextSecondary,
			TextWrapped = true })
	end

	-- ============ BASE COMPARE VIEW ============
	local function buildBaseCompare()
		for _, child in ipairs(contentFrame:GetChildren()) do child:Destroy() end

		local curStats = currentItem.baseStats or {}
		local selStats = selectedItem.baseStats or {}
		local rowY = 0

		for _, key in ipairs(COMPARE_STATS) do
			local cv = curStats[key]
			local sv = selStats[key]
			if cv ~= nil or sv ~= nil then
				local delta = ""
				local isGood = false
				local cvNum = tonumber(cv)
				local svNum = tonumber(sv)
				if cvNum and svNum then
					local diff = svNum - cvNum
					if diff ~= 0 then
						local lowerBetter = LOWER_IS_BETTER[key]
						isGood = (lowerBetter and diff < 0) or (not lowerBetter and diff > 0)
						local sign = diff > 0 and "+" or ""
						delta = sign .. diff
					end
				elseif type(cv) == "string" and type(sv) == "string" and cv ~= sv then
					delta = "~"
				end
				addStatRow(contentFrame, COMPARE_LABELS[key] or key,
					tostring(cv or "—"), tostring(sv or "—"), delta, isGood, rowY)
				rowY = rowY + 18
			end
		end

		-- Archetype passive comparison
		rowY = rowY + 4
		makeLabel(contentFrame, { Text = "PASSIVES",
			Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 0, rowY),
			Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Tiny(),
			TextColor3 = Theme.Colors.TextSecondary,
			TextXAlignment = Enum.TextXAlignment.Center })
		rowY = rowY + 14

		local curPN = {}
		if currentItem.passives then for _, p in ipairs(currentItem.passives) do curPN[p.name] = p end end
		local selPN = {}
		if selectedItem.passives then for _, p in ipairs(selectedItem.passives) do selPN[p.name] = p end end

		if currentItem.passives then
			for _, p in ipairs(currentItem.passives) do
				if not selPN[p.name] then
					addPassiveCard(contentFrame, p.name, p.desc, true, rowY, 0)
				end
			end
		end
		if selectedItem.passives then
			for _, p in ipairs(selectedItem.passives) do
				if not curPN[p.name] then
					addPassiveCard(contentFrame, p.name, p.desc, false, rowY, 0.52)
					rowY = rowY + 40
				end
			end
		end
	end

	-- ============ BONUS COMPARE VIEW ============
	local function buildBonusCompare()
		for _, child in ipairs(contentFrame:GetChildren()) do child:Destroy() end

		-- Side-by-side: left = current item bonuses, right = selected item bonuses
		local leftCol = Instance.new("Frame")
		leftCol.Size = UDim2.new(0.48, 0, 1, 0)
		leftCol.Position = UDim2.new(0, 0, 0, 0)
		leftCol.BackgroundTransparency = 1
		leftCol.Parent = contentFrame

		local rightCol = Instance.new("Frame")
		rightCol.Size = UDim2.new(0.48, 0, 1, 0)
		rightCol.Position = UDim2.new(0.52, 0, 0, 0)
		rightCol.BackgroundTransparency = 1
		rightCol.Parent = contentFrame

		-- Helper: list bonus stats + passives for one item into a column
		local function fillBonusColumn(col, bonusStats, bonusPassives)
			local y = 0

			-- Bonus numerical stats
			makeLabel(col, { Text = "BONUS STATS", Size = UDim2.new(1, 0, 0, 12),
				Position = UDim2.new(0, 0, 0, y),
				Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Tiny(),
				TextColor3 = Theme.Colors.TextSecondary })
			y = y + 14

			local bs = bonusStats or {}
			local hasStats = false
			for _, sn in ipairs(STAT_ORDER) do
				local bv = bs[sn]
				if bv and bv ~= 0 then
					hasStats = true
					local sign = bv > 0 and "+" or ""
					makeLabel(col, { Text = sn .. "  " .. sign .. bv,
						Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 4, 0, y),
						TextSize = Theme.Text.Body(), TextColor3 = Theme.Colors.Success })
					y = y + 16
				end
			end
			if not hasStats then
				makeLabel(col, { Text = "None", Size = UDim2.new(1, 0, 0, 12),
					Position = UDim2.new(0, 4, 0, y),
					TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextDisabled })
				y = y + 14
			end

			-- Bonus passives
			y = y + 4
			makeLabel(col, { Text = "BONUS PASSIVES", Size = UDim2.new(1, 0, 0, 12),
				Position = UDim2.new(0, 0, 0, y),
				Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Tiny(),
				TextColor3 = Theme.Colors.TextSecondary })
			y = y + 14

			local bp = bonusPassives or {}
			if #bp > 0 then
				for _, p in ipairs(bp) do
					local pCard = Instance.new("Frame")
					pCard.Size = UDim2.new(1, 0, 0, 40)
					pCard.Position = UDim2.new(0, 0, 0, y)
					pCard.BackgroundColor3 = Theme.Colors.PanelRaised
					pCard.BackgroundTransparency = 0.3
					pCard.BorderSizePixel = 0
					pCard.Parent = col
					Instance.new("UICorner", pCard).CornerRadius = UDim.new(0, 4)
					makeLabel(pCard, { Text = p.name or "Passive",
						Size = UDim2.new(1, -6, 0, 12), Position = UDim2.new(0, 3, 0, 2),
						Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Small(),
						TextColor3 = Theme.Colors.Info })
					makeLabel(pCard, { Text = p.desc or "",
						Size = UDim2.new(1, -6, 0, 22), Position = UDim2.new(0, 3, 0, 14),
						TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextSecondary,
						TextWrapped = true })
					y = y + 44
				end
			else
				makeLabel(col, { Text = "None", Size = UDim2.new(1, 0, 0, 12),
					Position = UDim2.new(0, 4, 0, y),
					TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextDisabled })
			end
		end

		fillBonusColumn(leftCol, currentItem.bonusStats, currentItem.bonusPassives)
		fillBonusColumn(rightCol, selectedItem.bonusStats, selectedItem.bonusPassives)
	end


	-- Show base view initially
	buildBaseCompare()

	-- Toggle button (lower-left of panel)
	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Size = UDim2.new(0, 90, 0, 24)
	toggleBtn.Position = UDim2.new(0, 0, 1, -28)
	toggleBtn.BackgroundColor3 = Theme.Colors.Surface
	toggleBtn.BackgroundTransparency = 0.2
	toggleBtn.Font = Theme.Font.PrimaryBold
	toggleBtn.TextSize = Theme.Text.Small()
	toggleBtn.TextColor3 = Theme.Colors.TextSecondary
	toggleBtn.Text = "Show Bonus >"
	toggleBtn.BorderSizePixel = 0
	toggleBtn.Parent = panel
	Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 4)
	toggleBtn.MouseButton1Click:Connect(function()
		showingBonus = not showingBonus
		if showingBonus then
			buildBonusCompare()
			toggleBtn.Text = "< Show Base"
		else
			buildBaseCompare()
			toggleBtn.Text = "Show Bonus >"
		end
	end)
end


-- SCREEN BUILD
--------------------------------------------------

function LoadoutScreen.Show()
	if screenGui and screenGui.Parent then return end

	screenGui, rootFrame = Theme.MakeFullScreen("LoadoutScreen", getPlayerGui())

	-- Remove outer screen border — inner panels' own 9-slice corners
	-- provide the corner ornaments at the screen edges they each own
	local sb = rootFrame:FindFirstChild("ScreenBorder")
	if sb then sb:Destroy() end

	-- Tab bar (top center)
	buildTabBar()

	-- RIGHT COLUMN (30% width, flush to right/top/bottom edges)
	local rightCol = Instance.new("Frame")
	rightCol.Name = "RightCol"
	rightCol.Size = UDim2.new(0.30, 0, 1, 0)
	rightCol.Position = UDim2.new(0.70, 0, 0, 0)
	rightCol.BackgroundTransparency = 1
	rightCol.Parent = rootFrame

	-- Unit header (top of right column)
	unitHeaderPanel = makePanel("UnitHeader",
		UDim2.new(1, 0, 0, 60),
		UDim2.new(0, 0, 0, 0), nil, rightCol)


	-- Equipped loadout (below unit header)
	local gap = Theme.FullScreen.PanelGap
	local headerH = 60
	equippedPanel = makePanel("EquippedLoadout",
		UDim2.new(1, 0, 1, -(headerH + gap)),
		UDim2.new(0, 0, 0, headerH + gap), nil, rightCol)

	-- LEFT COLUMN: Inventory (70% width, flush to left/top/bottom edges)
	inventoryPanel = makePanel("Inventory",
		UDim2.new(0.70, 0, 1, 0),
		UDim2.new(0, 0, 0, 0), nil, rootFrame)

	LoadoutScreen.Refresh()
end

function LoadoutScreen.Refresh()
	buildUnitHeader()
	buildEquippedLoadout()
	buildInventory()
end

function LoadoutScreen.Hide()
	closeDetail()
	if activeDropdown then activeDropdown:Destroy(); activeDropdown = nil end
	if optionsDropdown then optionsDropdown:Destroy(); optionsDropdown = nil end
	if tabBarGui then tabBarGui:Destroy(); tabBarGui = nil end
	if screenGui then screenGui:Destroy(); screenGui = nil end
	rootFrame = nil
	unitHeaderPanel = nil
	equippedPanel = nil
	inventoryPanel = nil
end

function LoadoutScreen.Toggle()
	if screenGui and screenGui.Parent then
		LoadoutScreen.Hide()
	else
		LoadoutScreen.Show()
	end
end

return LoadoutScreen
