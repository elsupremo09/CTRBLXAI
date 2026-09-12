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
local ConsumableData = require(ReplicatedStorage:WaitForChild("Content", 10)
	:WaitForChild("ConsumableData", 10))

local LoadoutScreen = {}

local screenGui, rootFrame
local unitHeaderPanel, equippedPanel, inventoryPanel, statPanel
local skillsPanel      -- left column for skills tab
local infoPanel        -- left column for info tab  
local currentTab = "EQUIPMENT" 
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

local BONUS_STAT_ORDER = {
	"STR", "INT", "DEX", "AGI", "VIT", "LUK",
	"HP", "MP", "Attack", "Defense", "RT Delay", "WT",
	"Precision", "Evasiveness", "Fortune", "Skill Potency",
	"Healing", "Debuff Resist", "RT Delay Resist",
}

--------------------------------------------------
-- CONSUMABLE PICKER POPUP
--------------------------------------------------

--------------------------------------------------
-- FORWARD DECLARATIONS (functions used before definition)
--------------------------------------------------
local buildInventory
local openItemDetail, closeDetail
local buildSoloDetailContent, buildComparisonContent
local switchTab, buildSkillsContent, buildInfoContent, buildStatPanel
local buildSkillLoadout
local openSkillCardDetail, openAugmentCardDetail
local openSkillSlotPicker, openAugmentSlotPicker
local openEquippedSkillDetail, openEquippedAugmentDetail
local openConsumableDetail, openConsumableSlotPicker, openEquippedConsumableDetail
local buildConsumableGrid


-- Skills tab state
local selectedSkillCardId = nil
local skillSubTab = "SKILL"     -- "SKILL" or "AUGMENT"
local skillTypeFilter = "All"
local skillTagFilter = "All"
local skillSortIndex = 1
local skillSearchText = ""

local SKILL_SORT_OPTIONS_SK = {
	{ label = "Name", field = "name", desc = false },
	{ label = "MP v", field = "mpCost", desc = true },
	{ label = "MP ^", field = "mpCost", desc = false },
	{ label = "RT v", field = "rtCost", desc = true },
	{ label = "RT ^", field = "rtCost", desc = false },
}

local SKILL_TYPE_FILTERS = { "All", "Damage", "Heal", "Buff", "Debuff", "Utility" }
local SKILL_TAG_FILTERS = { "All", "Fire", "Ice", "Electric", "Holy", "Dark", "Poison", "Physical" }

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function getPlayerGui()
	return player:WaitForChild("PlayerGui")
end

-- Public: build item detail content into any panel (for reuse by victory screen etc.)
function LoadoutScreen.BuildItemDetail(panel, item)
	buildSoloDetailContent(panel, item)
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

		if name == currentTab then
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

		btn.MouseButton1Click:Connect(function()
			if currentTab ~= name then
				currentTab = name
				switchTab()
			end
		end)
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

	-- Prev unit button (left of portrait)
	local prevBtn = Instance.new("ImageButton")
	prevBtn.Size = UDim2.new(0, 18, 0, 28)
	prevBtn.Position = UDim2.new(0, 0, 0, 8)
	prevBtn.BackgroundColor3 = Theme.Colors.Surface
	prevBtn.BackgroundTransparency = 0.4
	prevBtn.Image = Theme.Icons.ArrowLeft
	prevBtn.ScaleType = Enum.ScaleType.Fit
	prevBtn.BorderSizePixel = 0
	prevBtn.Parent = row
	Instance.new("UICorner", prevBtn).CornerRadius = UDim.new(0, 3)
	prevBtn.MouseButton1Click:Connect(function()
		MockData.PrevUnit()
		LoadoutScreen.Refresh()
	end)

	-- Portrait
	local portraitX = 22
	local portrait = Instance.new("Frame")
	portrait.Size = UDim2.new(0, 44, 0, 44)
	portrait.Position = UDim2.new(0, portraitX, 0, 0)
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
	local textX = portraitX + 52
	makeLabel(row, { Text = unit.name, Position = UDim2.new(0, textX, 0, 2),
		Size = UDim2.new(1, -(textX + 26), 0, 18), Font = Theme.Font.PrimaryBold,
		TextSize = Theme.Text.Heading(), TextColor3 = Theme.Colors.Player })
	makeLabel(row, { Text = unit.raceName,
		Position = UDim2.new(0, textX, 0, 20),
		Size = UDim2.new(1, -(textX + 26), 0, 14), TextSize = Theme.Text.Small(),
		TextColor3 = Theme.Colors.TextSecondary })

	-- Next unit button (right side)
	local nextBtn = Instance.new("ImageButton")
	nextBtn.Size = UDim2.new(0, 18, 0, 28)
	nextBtn.Position = UDim2.new(1, -18, 0, 8)
	nextBtn.BackgroundColor3 = Theme.Colors.Surface
	nextBtn.BackgroundTransparency = 0.4
	nextBtn.Image = Theme.Icons.ArrowRight
	nextBtn.ScaleType = Enum.ScaleType.Fit
	nextBtn.BorderSizePixel = 0
	nextBtn.Parent = row
	Instance.new("UICorner", nextBtn).CornerRadius = UDim.new(0, 3)
	nextBtn.MouseButton1Click:Connect(function()
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
			if equippedTab == "cons" then
				buildConsumableGrid()
			else
				buildInventory()
			end
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
			tile.MouseButton1Click:Connect(function()
				if isOffHandDisabled then return end
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
				makeLabel(cell, { Text = "[X]", Size = UDim2.new(1, 0, 1, 0),
					TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center,
					TextColor3 = Theme.Colors.TextDisabled })
			elseif item then
				makeLabel(cell, { Text = item.icon or "[C]", Size = UDim2.new(1, 0, 0, 28),
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
				cell.MouseButton1Click:Connect(function()
					openEquippedConsumableDetail(unit.id, i, item)
				end)
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
	grid.CellPadding = UDim2.new(0, 4, 0, 3)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirection = Enum.FillDirection.Horizontal

	-- Compute cell size: responsive to screen — minimum 3 rows visible, max 96px wide
	local MAX_CELL = 96
	local MIN_CELL = 48
	local ASPECT = 1.2
	local GAP = 4
	local containerW = itemGrid.AbsoluteSize.X - 16 -- subtract padding
	local containerH = itemGrid.AbsoluteSize.Y
	if containerW < 100 then containerW = 400 end -- fallback
	if containerH < 100 then containerH = 300 end -- fallback
	-- Height-first: ensure 3 rows fit
	local maxCellH = math.floor((containerH - 2 * GAP) / 3)
	local cellW = math.floor(maxCellH / ASPECT)
	cellW = math.clamp(cellW, MIN_CELL, MAX_CELL)
	local cellH = math.floor(cellW * ASPECT)
	grid.CellSize = UDim2.new(0, cellW, 0, cellH)
	local iconFrame = math.max(3, math.round(cellW * 0.05))

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
		local isEquippedByOther = false
		if not isEquipped then
			isEquippedByOther = MockData.IsEquippedByAny(item.id)
		end
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
		local lvLbl = makeLabel(card, { Text = lvlText, Size = UDim2.new(0, 36, 0, 12),
			Position = UDim2.new(0, 3, 0, 2),
			TextSize = 9, TextColor3 = Theme.Colors.TextSecondary,
			Font = Theme.Font.Mono })
		if lvLbl then lvLbl.ZIndex = 3 end

		-- Equipped marker (top-right): gold = this unit, grey = another unit
		if isEquipped or isEquippedByOther then
			local marker = Instance.new("Frame")
			marker.Size = UDim2.new(0, 14, 0, 12)
			marker.Position = UDim2.new(1, -16, 0, 2)
			marker.BackgroundColor3 = isEquipped and Theme.Colors.TextGold or Theme.Colors.TextDisabled
			marker.BorderSizePixel = 0
			marker.ZIndex = 3
			marker.Parent = card
			Instance.new("UICorner", marker).CornerRadius = UDim.new(0, 2)
			local eLbl = makeLabel(marker, { Text = "E", Size = UDim2.fromScale(1, 1),
				TextSize = 8, Font = Theme.Font.PrimaryBold,
				TextColor3 = Color3.fromRGB(0, 0, 0),
				TextXAlignment = Enum.TextXAlignment.Center })
			if eLbl then eLbl.ZIndex = 3 end
		end

		-- NEW badge (top-right, below equipped marker if both)
		if item.isNew then
			local newBadge = Instance.new("Frame")
			newBadge.Size = UDim2.new(0, 22, 0, 12)
			newBadge.Position = UDim2.new(1, -24, 0, isEquipped and 16 or 2)
			newBadge.BackgroundColor3 = Theme.Colors.Success
			newBadge.BorderSizePixel = 0
			newBadge.ZIndex = 3
			newBadge.Parent = card
			Instance.new("UICorner", newBadge).CornerRadius = UDim.new(0, 2)
			local newLbl = makeLabel(newBadge, { Text = "NEW", Size = UDim2.fromScale(1, 1),
				TextSize = Theme.Text.Badge(), Font = Theme.Font.PrimaryBold,
				TextColor3 = Color3.fromRGB(0, 0, 0),
				TextXAlignment = Enum.TextXAlignment.Center })
			if newLbl then newLbl.ZIndex = 3 end
		end

		-- Icon (center) — use uploaded image if available, else text
		if item.icon and string.find(item.icon, "rbxassetid://") then
			local ico = Instance.new("ImageLabel")
			local icoSidePx = cellW - iconFrame * 2
			ico.Size = UDim2.new(1, -iconFrame * 2, 0, icoSidePx)
			ico.Position = UDim2.fromOffset(iconFrame, iconFrame)
			ico.BackgroundTransparency = 1
			ico.Image = item.icon
			ico.ScaleType = Enum.ScaleType.Fit
			ico.Parent = card
		else
			makeLabel(card, { Text = item.icon or "?", Size = UDim2.new(1, 0, 0, 28),
				Position = UDim2.new(0, 0, 0.15, 0),
				TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center })
		end

		-- Name (bottom)
		local nameBg = Instance.new("Frame")
		nameBg.Size = UDim2.new(1, 0, 0, 14)
		nameBg.Position = UDim2.new(0, 0, 1, -14)
		nameBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		nameBg.BackgroundTransparency = 0.4
		nameBg.BorderSizePixel = 0
		nameBg.ZIndex = 3
		nameBg.Parent = card
		local nameLbl = makeLabel(nameBg, { Text = item.name, Size = UDim2.new(1, -4, 1, 0),
			Position = UDim2.new(0, 2, 0, 0),
			TextSize = Theme.Text.Small(), TextColor3 = getRarityColor(item.rarity),
			TextXAlignment = Enum.TextXAlignment.Left })
		if nameLbl then nameLbl.ZIndex = 3 end

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
	local filterLabel = currentFilter == "All" and "Type" or (currentFilter )
	local rarityLabel = currentRarity == "All" and "Rarity" or (currentRarity )
	local sortLabel = SORT_OPTIONS[currentSort].label 

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
			row.BorderSizePixel = 0
			row.LayoutOrder = idx
			row.ZIndex = 51
			row.Parent = menuPanel
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, 3)
			-- Icon + text layout
			local hasImage = opt.icon and string.find(opt.icon, "rbxassetid://")
			if hasImage then
				row.Text = ""
				local ico = Instance.new("ImageLabel")
				ico.Size = UDim2.new(0, 16, 0, 16)
				ico.Position = UDim2.new(0, 4, 0.5, -8)
				ico.BackgroundTransparency = 1
				ico.Image = opt.icon
				ico.ScaleType = Enum.ScaleType.Fit
				ico.ZIndex = 52
				ico.Parent = row
				local lbl = Instance.new("TextLabel")
				lbl.Size = UDim2.new(1, -24, 1, 0)
				lbl.Position = UDim2.new(0, 22, 0, 0)
				lbl.BackgroundTransparency = 1
				lbl.Font = Theme.Font.Primary
				lbl.TextSize = Theme.Text.Small()
				lbl.TextColor3 = opt.active and Theme.Colors.TextGold or Theme.Colors.TextPrimary
				lbl.TextXAlignment = Enum.TextXAlignment.Left
				lbl.Text = opt.label
				lbl.ZIndex = 52
				lbl.Parent = row
			else
				row.Text = opt.label
			end
			row.MouseButton1Click:Connect(function()
				closeDropdown()
				onSelect(opt.value, idx)
			end)
		end
	end

	local function makeDropdown(text, order, isActive, iconAsset)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 62, 1, 0)
		btn.BackgroundColor3 = Theme.Colors.Surface
		btn.BackgroundTransparency = 0.2
		btn.BorderSizePixel = 0
		btn.LayoutOrder = order
		btn.Parent = ctrlRow
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 3)
		if iconAsset then
			btn.Text = ""
			local ico = Instance.new("ImageLabel")
			ico.Size = UDim2.new(0, 14, 0, 14)
			ico.Position = UDim2.new(0, 3, 0.5, -7)
			ico.BackgroundTransparency = 1
			ico.Image = iconAsset
			ico.ScaleType = Enum.ScaleType.Fit
			ico.ImageColor3 = isActive and Theme.Colors.TextGold or Theme.Colors.TextSecondary
			ico.Parent = btn
			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.new(1, -19, 1, 0)
			lbl.Position = UDim2.new(0, 19, 0, 0)
			lbl.BackgroundTransparency = 1
			lbl.Font = Theme.Font.Primary
			lbl.TextSize = Theme.Text.Small()
			lbl.TextColor3 = isActive and Theme.Colors.TextGold or Theme.Colors.TextSecondary
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.TextTruncate = Enum.TextTruncate.AtEnd
			lbl.Text = text
			lbl.Parent = btn
		else
			btn.Font = Theme.Font.Primary
			btn.TextSize = Theme.Text.Small()
			btn.TextColor3 = isActive and Theme.Colors.TextGold or Theme.Colors.TextSecondary
			btn.Text = text
		end
		return btn
	end

	-- Type filter button — cycles through category filters
	local typeBtn = makeDropdown(filterLabel, 2, currentFilter ~= "All", Theme.Icons.Filter)
	typeBtn.MouseButton1Click:Connect(function()
		local opts = {}
		for _, f in ipairs(CATEGORY_FILTERS) do
			table.insert(opts, { label = f.label, value = f.id, icon = f.icon, active = (currentFilter == f.id) })
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
	local rarityBtn = makeDropdown(rarityLabel, 3, currentRarity ~= "All", Theme.Icons.Filter)
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
	local sortBtn = makeDropdown(sortLabel, 4, false, Theme.Icons.Sort)
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

	-- Collect buttons: COMPARE(1) | EQUIP(2) | BACK(3) right-aligned
	local btnDefs = {}
	local order = 1

	-- Tertiary: COMPARE or DETAILS (leftmost, optional)
	if not compareItem and unit then
		local slot = item.cat
		local equippedItem = MockData.GetEquipped(unit.id, slot)
		if equippedItem and equippedItem.id ~= item.id then
			table.insert(btnDefs, { text = "COMPARE", style = "Tertiary", order = order, onClick = function()
				openItemDetail(item, equippedItem)
			end })
			order = order + 1
		end
	end
	if compareItem then
		table.insert(btnDefs, { text = "DETAILS", style = "Tertiary", order = order, onClick = function()
			openItemDetail(item, nil)
		end })
		order = order + 1
	end

	-- Primary: EQUIP or UNEQUIP
	if isEquippedMode then
		local eqSlot = item.cat
		if eqSlot ~= "Doctrine" then
			table.insert(btnDefs, { text = "UNEQUIP", style = "Primary", order = order, onClick = function()
				if unit then
					MockData.MockUnequip(unit.id, eqSlot)
					closeDetail()
					LoadoutScreen.Refresh()
				end
			end })
			order = order + 1
		end
	else
		table.insert(btnDefs, { text = "EQUIP", style = "Primary", order = order, onClick = function()
			if unit then
				local slot = item.cat
				MockData.MockEquip(unit.id, slot, item.id)
				closeDetail()
				LoadoutScreen.Refresh()
			end
		end })
		order = order + 1
	end

	-- Secondary: BACK (always rightmost)
	table.insert(btnDefs, { text = "BACK", style = "Secondary", order = order, onClick = closeDetail })

	-- Build button row: bottom-right of SCREEN, on the overlay ScreenGui
	local btnCount = #btnDefs
	local fb = Theme.FooterBar
	local totalW = btnCount * fb.BTN_W + (btnCount - 1) * fb.BTN_GAP
	local btnBar = Instance.new("Frame")
	btnBar.Name = "DetailBtnBar"
	btnBar.Size = UDim2.new(0, totalW, 0, fb.BTN_H)
	btnBar.BackgroundTransparency = 1
	btnBar.AnchorPoint = Vector2.new(1, 1)
	btnBar.Position = UDim2.new(1, -fb.PAD, 1, -fb.PAD)
	btnBar.Parent = detailOverlay

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, fb.BTN_GAP)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = btnBar

	for _, def in ipairs(btnDefs) do
		local btn = Theme.MakeButton(btnBar, def.text, def.style, def.onClick, {
			size = UDim2.new(0, fb.BTN_W, 0, fb.BTN_H),
		})
		btn.LayoutOrder = def.order
	end

	-- [DIAG] COMPARE gating conditions
	print("[DIAG-COMPARE] compareItem = " .. tostring(compareItem))
	print("[DIAG-COMPARE] unit = " .. tostring(unit))
	if not compareItem and unit then
		local diagSlot = item.cat
		local diagEquipped = MockData.GetEquipped(unit.id, diagSlot)
		print("[DIAG-COMPARE] item.cat (slot) = " .. tostring(diagSlot))
		print("[DIAG-COMPARE] equippedItem = " .. tostring(diagEquipped))
		if diagEquipped then
			print("[DIAG-COMPARE] equippedItem.id = " .. tostring(diagEquipped.id) .. " | item.id = " .. tostring(item.id))
			print("[DIAG-COMPARE] ids differ = " .. tostring(diagEquipped.id ~= item.id))
		end
	end
	print("[DIAG-COMPARE] isEquippedMode = " .. tostring(isEquippedMode))
	print("[DIAG-COMPARE] btnCount = " .. tostring(btnCount))
	for _, def in ipairs(btnDefs) do
		print("[DIAG-COMPARE] btnDef: text=" .. def.text .. " style=" .. def.style .. " order=" .. tostring(def.order))
	end

	-- [DIAG] Deferred layout dump (after 1 frame)
	task.defer(function()
		if not btnBar or not btnBar.Parent then
			print("[DIAG-LAYOUT] btnBar destroyed or no parent!")
			return
		end
		print("[DIAG-LAYOUT] ---- BUTTON BAR ----")
		print("[DIAG-LAYOUT] btnBar.Parent = " .. btnBar.Parent:GetFullName())
		print("[DIAG-LAYOUT] btnBar.AbsolutePosition = " .. tostring(btnBar.AbsolutePosition))
		print("[DIAG-LAYOUT] btnBar.AbsoluteSize = " .. tostring(btnBar.AbsoluteSize))
		print("[DIAG-LAYOUT] btnBar.Size = " .. tostring(btnBar.Size))
		print("[DIAG-LAYOUT] btnBar.Visible = " .. tostring(btnBar.Visible))

		-- Detail panel
		print("[DIAG-LAYOUT] ---- DETAIL PANEL ----")
		print("[DIAG-LAYOUT] panel.AbsolutePosition = " .. tostring(panel.AbsolutePosition))
		print("[DIAG-LAYOUT] panel.AbsoluteSize = " .. tostring(panel.AbsoluteSize))
		print("[DIAG-LAYOUT] panel.ClipsDescendants = " .. tostring(panel.ClipsDescendants))

		-- UIListLayout
		local layout = btnBar:FindFirstChildWhichIsA("UIListLayout")
		if layout then
			print("[DIAG-LAYOUT] UIListLayout.AbsoluteContentSize = " .. tostring(layout.AbsoluteContentSize))
			print("[DIAG-LAYOUT] UIListLayout.Padding = " .. tostring(layout.Padding))
		end

		-- Per-button
		print("[DIAG-LAYOUT] ---- INDIVIDUAL BUTTONS ----")
		local prevRight = nil
		for _, child in ipairs(btnBar:GetChildren()) do
			if child:IsA("ImageButton") then
				local ap = child.AbsolutePosition
				local as = child.AbsoluteSize
				print(("[DIAG-LAYOUT] %s | AbsPos=%s | AbsSize=%s | Visible=%s | ImgTransp=%s"):format(
					child.Name, tostring(ap), tostring(as),
					tostring(child.Visible), tostring(child.ImageTransparency)))
				-- Compute gap from previous button
				if prevRight then
					local gap = ap.X - prevRight
					print(("[DIAG-LAYOUT]   ^ gap from previous right edge = %.1f px"):format(gap))
				end
				prevRight = ap.X + as.X
			end
		end

		-- SliceCenter recap
		print("[DIAG-SLICE] BTN_SLICE_CENTER applied = " .. tostring(btnBar:GetChildren()[1] and btnBar:GetChildren()[1]:IsA("ImageButton") and btnBar:GetChildren()[1].SliceCenter or "N/A"))
		print("[DIAG-SLICE] Source images are ORIGINAL 256x50 uploads (trimmed 200x48 were never uploaded)")
	end)

end

--------------------------------------------------
-- SOLO DETAIL CONTENT (reference image 1)
--------------------------------------------------

-- Helper: generate a fallback flavor line for equipment without authored flavor
local function getItemFlavor(item)
	if item.flavor and item.flavor ~= "" then return item.flavor end
	-- Generate basic flavor from item properties
	local parts = {}
	local rarity = item.rarity or "Common"
	if rarity == "Legendary" then
		table.insert(parts, "A legendary")
	elseif rarity == "Epic" then
		table.insert(parts, "A finely crafted")
	elseif rarity == "Rare" then
		table.insert(parts, "A well-forged")
	elseif rarity == "Uncommon" then
		table.insert(parts, "A sturdy")
	else
		table.insert(parts, "A standard")
	end
	-- Category/type
	local sub = item.sub or ""
	local cat = item.cat or ""
	if sub ~= "" then
		table.insert(parts, sub:lower())
	elseif cat == "MainHand" then
		table.insert(parts, "weapon")
	elseif cat == "OffHand" then
		table.insert(parts, "off-hand item")
	elseif cat == "Head" then
		table.insert(parts, "headpiece")
	elseif cat == "Torso" then
		table.insert(parts, "body armor")
	elseif cat == "Arms" then
		table.insert(parts, "pair of gloves")
	elseif cat == "Legs" then
		table.insert(parts, "pair of boots")
	elseif cat == "Accessory" then
		table.insert(parts, "accessory")
	else
		table.insert(parts, "piece of equipment")
	end
	-- Passive hint
	if item.passives and #item.passives > 0 then
		table.insert(parts, "with the " .. item.passives[1].name .. " property.")
	else
		table.insert(parts, "built for the battlefield.")
	end
	return table.concat(parts, " ")
end

--------------------------------------------------
-- SHARED DETAIL HEADER (uniform across all item types)
--------------------------------------------------
local DETAIL_PORTRAIT = 52
local DETAIL_TEXT_X = DETAIL_PORTRAIT + 8

local function buildDetailHeader(parent, opts)
	local iconFrame = Instance.new("Frame")
	iconFrame.Size = UDim2.new(0, DETAIL_PORTRAIT, 0, DETAIL_PORTRAIT)
	iconFrame.Position = UDim2.new(0, 0, 0, 0)
	iconFrame.BackgroundColor3 = opts.iconBg or Theme.Colors.Surface
	iconFrame.BackgroundTransparency = opts.iconBgTransparency or 0.15
	iconFrame.BorderSizePixel = 0
	iconFrame.Parent = parent
	Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(0, 6)
	local stroke = Instance.new("UIStroke", iconFrame)
	stroke.Color = opts.iconStrokeColor or Theme.Colors.Border
	stroke.Thickness = 1.5
	if opts.iconImage and opts.iconImage ~= "" then
		local ico = Instance.new("ImageLabel")
		ico.Size = UDim2.new(1, -4, 1, -4)
		ico.Position = UDim2.new(0, 2, 0, 2)
		ico.BackgroundTransparency = 1
		ico.Image = opts.iconImage
		ico.ScaleType = Enum.ScaleType.Fit
		ico.Parent = iconFrame
	else
		makeLabel(iconFrame, { Text = opts.iconText or "?", Size = UDim2.fromScale(1, 1),
			TextSize = Theme.Text.Title(), TextColor3 = opts.iconColor or Theme.Colors.TextPrimary,
			TextXAlignment = Enum.TextXAlignment.Center })
	end
	if opts.level and opts.level > 0 then
		local lvBadge = Instance.new("Frame")
		lvBadge.Size = UDim2.new(0, 26, 0, 16)
		lvBadge.Position = UDim2.new(0, 0, 0, 0)
		lvBadge.BackgroundColor3 = Theme.Colors.Panel
		lvBadge.BorderSizePixel = 0
		lvBadge.ZIndex = 5
		lvBadge.Parent = iconFrame
		Instance.new("UICorner", lvBadge).CornerRadius = UDim.new(0, 3)
		local bStroke = Instance.new("UIStroke", lvBadge)
		bStroke.Color = Theme.Colors.Border
		bStroke.ZIndex = 5
		local bLbl = makeLabel(lvBadge, { Text = "Lv" .. opts.level,
			Size = UDim2.fromScale(1, 1),
			TextSize = Theme.Text.Tiny(), Font = Theme.Font.PrimaryBold,
			TextColor3 = Theme.Colors.TextGold,
			TextXAlignment = Enum.TextXAlignment.Center })
		if bLbl then bLbl.ZIndex = 5 end
	end
	makeLabel(parent, { Text = opts.name or "?",
		Size = UDim2.new(1, -DETAIL_TEXT_X, 0, 18),
		Position = UDim2.new(0, DETAIL_TEXT_X, 0, 0),
		Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Heading(),
		TextColor3 = Theme.Colors.TextPrimary })
	-- Subtitle: "Lv.X | Rarity" below name
	local tagY = 20
	if opts.level and opts.level > 0 then
		local subParts = { "Lv." .. opts.level }
		if opts.rarity and opts.rarity ~= "" then table.insert(subParts, opts.rarity) end
		makeLabel(parent, { Text = table.concat(subParts, " | "),
			Size = UDim2.new(1, -DETAIL_TEXT_X, 0, 14),
			Position = UDim2.new(0, DETAIL_TEXT_X, 0, tagY),
			TextSize = Theme.Text.Small(), Font = Theme.Font.Primary,
			TextColor3 = opts.subtitleColor or Theme.Colors.TextSecondary })
		tagY = tagY + 16
	end
	local tags = opts.tags or {}
	if #tags > 0 then
		local tagRow = Instance.new("Frame")
		tagRow.Size = UDim2.new(1, -DETAIL_TEXT_X, 0, 16)
		tagRow.Position = UDim2.new(0, DETAIL_TEXT_X, 0, tagY)
		tagRow.BackgroundTransparency = 1
		tagRow.Parent = parent
		local tagLayout = Instance.new("UIListLayout", tagRow)
		tagLayout.FillDirection = Enum.FillDirection.Horizontal
		tagLayout.Padding = UDim.new(0, 3)
		for ti, tag in ipairs(tags) do
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
	local desc = opts.description or ""
	if desc ~= "" then
		makeLabel(parent, { Text = desc,
			Size = UDim2.new(1, -DETAIL_TEXT_X, 0, 28),
			Position = UDim2.new(0, DETAIL_TEXT_X, 0, tagY),
			TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextSecondary,
			TextWrapped = true })
		tagY = tagY + 30
	end
	return math.max(tagY + 2, DETAIL_PORTRAIT + 4)
end


buildSoloDetailContent = function(panel, item)
	local rc = getRarityColor(item.rarity)

	-- Unified header
	local divY = buildDetailHeader(panel, {
		iconText = item.icon or "?",
		iconImage = (item.icon and string.find(item.icon, "rbxassetid://")) and item.icon or nil,
		iconBg = rc,
		iconBgTransparency = 0.75,
		iconColor = Theme.Colors.TextPrimary,
		iconStrokeColor = rc,
		name = item.name,
		tags = item.tags,
		description = getItemFlavor(item),
		level = item.lv,
		rarity = item.rarity,
		subtitleColor = rc,
	})

	-- Divider
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
				pCard.Size = UDim2.new(1, 0, 0, 36)
				pCard.Position = UDim2.new(0, 0, 0, passY)
				pCard.BackgroundColor3 = Theme.Colors.PanelRaised
				pCard.BackgroundTransparency = 0.3
				pCard.BorderSizePixel = 0
				pCard.Parent = rightCol
				Instance.new("UICorner", pCard).CornerRadius = UDim.new(0, 4)
				makeLabel(pCard, { Text = p.name or "Passive",
					Size = UDim2.new(1, -8, 0, 14), Position = UDim2.new(0, 4, 0, 2),
					Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Small(),
					TextColor3 = Theme.Colors.Success })
				makeLabel(pCard, { Text = p.desc or "",
					Size = UDim2.new(1, -8, 0, 18), Position = UDim2.new(0, 4, 0, 16),
					TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextSecondary,
					TextWrapped = true })
				passY = passY + 40
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
		local hasAny = false
		for _, sn in ipairs(BONUS_STAT_ORDER) do
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
				pCard.Size = UDim2.new(1, 0, 0, 36)
				pCard.Position = UDim2.new(0, 0, 0, passY)
				pCard.BackgroundColor3 = Theme.Colors.PanelRaised
				pCard.BackgroundTransparency = 0.3
				pCard.BorderSizePixel = 0
				pCard.Parent = rightCol
				Instance.new("UICorner", pCard).CornerRadius = UDim.new(0, 4)
				makeLabel(pCard, { Text = p.name or "Passive",
					Size = UDim2.new(1, -8, 0, 14), Position = UDim2.new(0, 4, 0, 2),
					Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Small(),
					TextColor3 = Theme.Colors.Info })
				makeLabel(pCard, { Text = p.desc or "",
					Size = UDim2.new(1, -8, 0, 18), Position = UDim2.new(0, 4, 0, 16),
					TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextSecondary,
					TextWrapped = true })
				passY = passY + 40
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
	toggleBtn.Text = "Show Bonus"
	toggleBtn.BorderSizePixel = 0
	toggleBtn.Parent = panel
	Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 4)
	local toggleIcon = Instance.new("ImageLabel")
	toggleIcon.Name = "ToggleIcon"
	toggleIcon.Size = UDim2.new(0, 12, 0, 12)
	toggleIcon.Position = UDim2.new(1, -16, 0.5, -6)
	toggleIcon.BackgroundTransparency = 1
	toggleIcon.Image = Theme.Icons.Expand
	toggleIcon.ScaleType = Enum.ScaleType.Fit
	toggleIcon.ImageColor3 = Theme.Colors.TextSecondary
	toggleIcon.Parent = toggleBtn
	toggleBtn.MouseButton1Click:Connect(function()
		print("[DIAG-TOGGLE] Show Bonus/Base clicked | showingBonus=" .. tostring(not showingBonus))
		showingBonus = not showingBonus
		if showingBonus then
			buildBonusView()
			toggleBtn.Text = "Show Base"
			if toggleBtn:FindFirstChild("ToggleIcon") then toggleBtn.ToggleIcon.Image = Theme.Icons.Collapse end
		else
			buildBaseView()
			toggleBtn.Text = "Show Bonus"
			if toggleBtn:FindFirstChild("ToggleIcon") then toggleBtn.ToggleIcon.Image = Theme.Icons.Expand end
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
			for _, sn in ipairs(BONUS_STAT_ORDER) do
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
	toggleBtn.Text = "Show Bonus"
	toggleBtn.BorderSizePixel = 0
	toggleBtn.Parent = panel
	Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 4)
	local toggleIcon = Instance.new("ImageLabel")
	toggleIcon.Name = "ToggleIcon"
	toggleIcon.Size = UDim2.new(0, 12, 0, 12)
	toggleIcon.Position = UDim2.new(1, -16, 0.5, -6)
	toggleIcon.BackgroundTransparency = 1
	toggleIcon.Image = Theme.Icons.Expand
	toggleIcon.ScaleType = Enum.ScaleType.Fit
	toggleIcon.ImageColor3 = Theme.Colors.TextSecondary
	toggleIcon.Parent = toggleBtn
	toggleBtn.MouseButton1Click:Connect(function()
		showingBonus = not showingBonus
		if showingBonus then
			buildBonusCompare()
			toggleBtn.Text = "Show Base"
			if toggleBtn:FindFirstChild("ToggleIcon") then toggleBtn.ToggleIcon.Image = Theme.Icons.Collapse end
		else
			buildBaseCompare()
			toggleBtn.Text = "Show Bonus"
			if toggleBtn:FindFirstChild("ToggleIcon") then toggleBtn.ToggleIcon.Image = Theme.Icons.Expand end
		end
	end)
end



--------------------------------------------------
-- TAB SWITCHING
--------------------------------------------------

switchTab = function()
	-- Hide all tab-specific panels
	if inventoryPanel then inventoryPanel.Visible = false end
	if equippedPanel then equippedPanel.Visible = false end
	if statPanel then statPanel.Visible = false end
	if skillsPanel then skillsPanel.Visible = false end
	if infoPanel then infoPanel.Visible = false end

	-- Close any open overlays
	closeDetail()
	if activeDropdown then activeDropdown:Destroy(); activeDropdown = nil end

	if currentTab == "EQUIPMENT" then
		if inventoryPanel then inventoryPanel.Visible = true end
		if equippedPanel then equippedPanel.Visible = true end
		-- Reclaim stat panel space
		local eqTop = 60 + (Theme.FullScreen.PanelGap or 2)
		if equippedPanel then equippedPanel.Size = UDim2.new(1, 0, 1, -eqTop); equippedPanel.Position = UDim2.new(0, 0, 0, eqTop) end
		if equippedTab == "cons" then buildConsumableGrid() else buildInventory() end
		buildEquippedLoadout()
	elseif currentTab == "SKILLS" then
		if skillsPanel then skillsPanel.Visible = true end
		if equippedPanel then equippedPanel.Visible = true end
		-- Reclaim stat panel space
		local eqTop = 60 + (Theme.FullScreen.PanelGap or 2)
		if equippedPanel then equippedPanel.Size = UDim2.new(1, 0, 1, -eqTop); equippedPanel.Position = UDim2.new(0, 0, 0, eqTop) end
		buildSkillsContent()
	elseif currentTab == "INFO" then
		if infoPanel then infoPanel.Visible = true end
		if statPanel then statPanel.Visible = true end
		-- Push equipped panel below stat panel
		local gap = Theme.FullScreen.PanelGap or 2
		local topUsed = 60 + gap + 160 + gap
		if equippedPanel then equippedPanel.Size = UDim2.new(1, 0, 1, -topUsed); equippedPanel.Position = UDim2.new(0, 0, 0, topUsed) end
		buildStatPanel()
		buildInfoContent()
	end

	-- Rebuild tab bar to update active highlight
	buildTabBar()
	-- Rebuild unit header (always visible)
	buildUnitHeader()
end

--------------------------------------------------
-- SKILLS TAB CONTENT (v3 — Grid + Loadout Table)
--------------------------------------------------

-- =====================================================
-- SKILLS TAB v3: Grid Layout with Detail Overlays
-- Replaces lines 1843-2881 in LoadoutScreen.lua
-- =====================================================

-- SKILL TYPE classification helper
local function getSkillType(tags)
	if not tags then return "Utility" end
	for _, t in ipairs(tags) do
		if t == "Direct Damage" then return "Damage" end
	end
	for _, t in ipairs(tags) do
		if t == "Healing" then return "Heal" end
	end
	for _, t in ipairs(tags) do
		if t == "Buff" or t == "Shield" then return "Buff" end
	end
	for _, t in ipairs(tags) do
		if t == "Debuff" then return "Debuff" end
	end
	return "Utility"
end

-- Skill-type colour table
local STYPE_COLORS = {
	Damage  = { bg = Color3.fromRGB(74, 26, 26), icon = Color3.fromRGB(248, 113, 113) },
	Heal    = { bg = Color3.fromRGB(26, 58, 26), icon = Color3.fromRGB(74, 222, 128)  },
	Buff    = { bg = Color3.fromRGB(26, 42, 74), icon = Color3.fromRGB(96, 165, 250)  },
	Debuff  = { bg = Color3.fromRGB(42, 26, 74), icon = Color3.fromRGB(192, 132, 252) },
	Utility = { bg = Color3.fromRGB(42, 42, 42), icon = Color3.fromRGB(226, 232, 240) },
}

-- Skill-type emoji icons
-- Helper: simplify pattern text for display
local function simplifyPattern(raw)
	if not raw then return "-" end
	local low = raw:lower()
	if low:find("inherit weapon") or low:find("weapon pattern") then
		return "Weapon"
	end
	-- Strip "Authored " prefix
	local simplified = raw:gsub("^Authored%s+", "")
	return simplified
end

-- Helper: simplify targeting range text for display
local function simplifyRange(raw)
	if not raw then return "-" end
	local low = raw:lower()
	-- Check for weapon range inheritance
	if low:find("inherit") and low:find("weapon range") then
		-- Extract bonus skill range %
		local pct = raw:match("(%d+)%%.-[Bb]onus [Ss]kill [Rr]ange")
		if pct then
			return "Weapon + " .. pct .. "% Bonus Skill Range"
		end
		return "Weapon Range"
	end
	-- Fixed range: "Fixed 4; add 100% inherited Bonus Skill Range"
	local fixedVal = raw:match("[Ff]ixed%s+(%d+)")
	local bonusPct = raw:match("(%d+)%%.-[Bb]onus [Ss]kill [Rr]ange")
	if fixedVal then
		if bonusPct and bonusPct ~= "0" then
			return fixedVal .. " + " .. bonusPct .. "% Bonus Skill Range"
		end
		return fixedVal
	end
	-- Authored range formula
	local formula = raw:match("[Aa]uthored [Rr]ange [Ff]ormula:%s*(.-)%;")
	if formula then
		local inheritance = raw:match("Inheritance%s*=%s*(%d+)%%")
		if inheritance and inheritance ~= "0" then
			return formula .. " + " .. inheritance .. "% Bonus Skill Range"
		end
		return formula
	end
	-- Self range
	if low:find("^self") then return "Self" end
	-- Fallback: return first line only, trimmed
	local firstLine = raw:match("^([^\n]+)")
	if firstLine and #firstLine > 50 then
		return firstLine:sub(1, 47) .. "..."
	end
	return firstLine or raw
end

-- Helper: build a short skill description from its definition
local function buildSkillDescription(def)
	if not def then return "" end
	local parts = {}
	-- Range type
	local range = def.targetingRange or ""
	local rangeLow = range:lower()
	if rangeLow:find("self") then
		table.insert(parts, "Self-targeting")
	elseif rangeLow:find("fixed") then
		table.insert(parts, "Ranged")
	elseif rangeLow:find("weapon range") or rangeLow:find("inherit") then
		table.insert(parts, "Weapon-range")
	else
		table.insert(parts, "Targeted")
	end
	-- Element
	local tags = def.tags or {}
	local elements = { "Fire", "Ice", "Electric", "Holy", "Dark", "Poison", "Water", "Earth" }
	for _, el in ipairs(elements) do
		for _, t in ipairs(tags) do
			if t == el then
				table.insert(parts, el:lower())
				break
			end
		end
	end
	-- Pattern
	local pat = def.pattern or ""
	local patLow = pat:lower()
	if patLow:find("single") then
		table.insert(parts, "single-target")
	elseif patLow:find("cleave") or patLow:find("sweep") then
		table.insert(parts, "cleave")
	elseif patLow:find("line") then
		table.insert(parts, "line")
	elseif patLow:find("circle") or patLow:find("spread") then
		table.insert(parts, "area")
	elseif patLow:find("chain") then
		table.insert(parts, "chain")
	elseif patLow:find("weapon") or patLow:find("inherit") then
		table.insert(parts, "weapon-pattern")
	elseif patLow:find("self") then
		table.insert(parts, "self")
	end
	-- Projectile
	local props = def.properties or ""
	if props:lower():find("projectile") then
		table.insert(parts, "projectile")
	end
	-- Main action from tags
	local hasHeal = false
	local hasDamage = false
	local hasBuff = false
	local hasDebuff = false
	for _, t in ipairs(tags) do
		if t == "Healing" then hasHeal = true end
		if t == "Direct Damage" then hasDamage = true end
		if t == "Buff" or t == "Shield" then hasBuff = true end
		if t == "Debuff" then hasDebuff = true end
	end
	if hasDamage and hasDebuff then
		table.insert(parts, "attack with debuff")
	elseif hasDamage then
		table.insert(parts, "attack")
	elseif hasHeal then
		table.insert(parts, "heal")
	elseif hasBuff then
		table.insert(parts, "buff")
	elseif hasDebuff then
		table.insert(parts, "debuff")
	end
	return table.concat(parts, " ")
end

-- Helper: clean effects text — strip pattern/range/snapshot redundancy
local function cleanEffects(raw)
	if not raw then return "" end
	local text = raw
	-- Remove "Authored Single pattern; " or similar pattern mentions
	text = text:gsub("[Aa]uthored%s+%w+%s+pattern;?%s*", "")
	-- Remove "Inherit Weapon Pattern." type mentions
	text = text:gsub("[Ii]nherit%s+[Ww]eapon%s+[Pp]attern%.?%s*", "")
	-- Remove snapshot timing references
	text = text:gsub("[Ss]napshot%s+at%s+commitment[^%.]*%.?%s*", "")
	-- Remove "persistent/created effects..." noise
	text = text:gsub("persistent/created effects[^%.]*%.?%s*", "")
	-- Remove leading/trailing whitespace and semicolons
	text = text:gsub("^[;%s]+", ""):gsub("[;%s]+$", "")
	-- Capitalize first letter
	if #text > 0 then
		text = text:sub(1, 1):upper() .. text:sub(2)
	end
	return text
end

local STYPE_ICONS = {
	Damage  = "[X]",
	Heal    = "[+]",
	Buff    = "[^]",
	Debuff  = "[v]",
	Utility = "[*]",
}

-- Element colour lookup
local ELEM_COLORS = {
	Fire     = Color3.fromRGB(249, 115, 22),
	Ice      = Color3.fromRGB(56, 189, 248),
	Electric = Color3.fromRGB(250, 204, 21),
	Holy     = Color3.fromRGB(253, 230, 138),
	Dark     = Color3.fromRGB(167, 139, 250),
	Poison   = Color3.fromRGB(134, 239, 172),
	Physical = nil, -- uses TextSecondary
}

local function getElement(tags)
	if not tags then return nil end
	for _, t in ipairs(tags) do
		if ELEM_COLORS[t] then return t end
	end
	return nil
end

-- ==================================================================
-- buildSkillsContent: Main Skills tab
-- Uses skillsPanel (left 70%) for card grid
-- Uses equippedPanel (right 30%) for skill loadout table
-- ==================================================================
buildSkillsContent = function()
	if not skillsPanel then return end
	clearChildren(skillsPanel)
	pad(skillsPanel, 8, 8, 8, 8)

	local unit = MockData.GetSelectedUnit()
	if not unit then return end

	-- Load skill data from server
	if MockData.LoadSkillData then
		MockData.LoadSkillData(unit.id)
	end

	local loadout = MockData.GetSkillLoadout(unit.id)
	local doctrineId = MockData.GetUnitDoctrineId(unit.id)

	-- ============================================================
	-- LEFT: CARD GRID (in skillsPanel)
	-- ============================================================

	-- Filter bar
	local ctrlRow = Instance.new("Frame")
	ctrlRow.Size = UDim2.new(1, 0, 0, 24)
	ctrlRow.Position = UDim2.new(0, 0, 0, 0)
	ctrlRow.BackgroundTransparency = 1
	ctrlRow.Parent = skillsPanel

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
	search.PlaceholderText = "Search cards..."
	search.PlaceholderColor3 = Theme.Colors.TextDisabled
	search.Text = skillSearchText or ""
	search.BorderSizePixel = 0
	search.ClearTextOnFocus = false
	search.LayoutOrder = 1
	search.Parent = ctrlRow
	Instance.new("UICorner", search).CornerRadius = UDim.new(0, 3)

	search.FocusLost:Connect(function()
		skillSearchText = search.Text
		buildSkillsContent()
	end)

	-- Shared dropdown helpers (reuse module-level activeDropdown)
	local function closeDD()
		if activeDropdown then activeDropdown:Destroy(); activeDropdown = nil end
	end

	local function showDD(anchorBtn, options, onSelect)
		closeDD()
		local rowH = 22
		local menuH = #options * rowH + 4
		local menuW = math.max(anchorBtn.AbsoluteSize.X, 80)

		activeDropdown = Instance.new("ScreenGui")
		activeDropdown.Name = "SkillDropdown"
		activeDropdown.DisplayOrder = 105
		activeDropdown.ResetOnSpawn = false
		activeDropdown.Parent = getPlayerGui()

		local ddBack = Instance.new("TextButton")
		ddBack.Size = UDim2.fromScale(1, 1)
		ddBack.BackgroundTransparency = 1
		ddBack.Text = ""
		ddBack.Parent = activeDropdown
		ddBack.MouseButton1Click:Connect(closeDD)

		local mPanel = Instance.new("Frame")
		mPanel.Size = UDim2.new(0, menuW, 0, menuH)
		mPanel.Position = UDim2.new(0,
			anchorBtn.AbsolutePosition.X,
			0, anchorBtn.AbsolutePosition.Y + anchorBtn.AbsoluteSize.Y + 2)
		mPanel.BackgroundColor3 = Theme.Colors.Panel
		mPanel.BorderSizePixel = 0
		mPanel.ZIndex = 50
		mPanel.Parent = activeDropdown
		Instance.new("UICorner", mPanel).CornerRadius = UDim.new(0, 4)
		Instance.new("UIStroke", mPanel).Color = Theme.Colors.Border
		pad(mPanel, 2, 2, 2, 2)

		local mLayout = Instance.new("UIListLayout", mPanel)
		mLayout.Padding = UDim.new(0, 0)
		mLayout.SortOrder = Enum.SortOrder.LayoutOrder

		for idx, opt in ipairs(options) do
			local row = Instance.new("TextButton")
			row.Size = UDim2.new(1, 0, 0, rowH)
			row.BackgroundColor3 = Theme.Colors.PanelRaised
			row.BackgroundTransparency = opt.active and 0.2 or 0.6
			row.Font = Theme.Font.Primary
			row.TextSize = Theme.Text.Small()
			row.TextColor3 = opt.active and Theme.Colors.TextGold or Theme.Colors.TextPrimary
			row.BorderSizePixel = 0
			row.LayoutOrder = idx
			row.ZIndex = 51
			row.Parent = mPanel
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, 3)
			local hasImg = opt.icon and string.find(opt.icon, "rbxassetid://")
			if hasImg then
				row.Text = ""
				local ico = Instance.new("ImageLabel")
				ico.Size = UDim2.new(0, 16, 0, 16)
				ico.Position = UDim2.new(0, 4, 0.5, -8)
				ico.BackgroundTransparency = 1
				ico.Image = opt.icon
				ico.ScaleType = Enum.ScaleType.Fit
				ico.ZIndex = 52
				ico.Parent = row
				local lbl = Instance.new("TextLabel")
				lbl.Size = UDim2.new(1, -24, 1, 0)
				lbl.Position = UDim2.new(0, 22, 0, 0)
				lbl.BackgroundTransparency = 1
				lbl.Font = Theme.Font.Primary
				lbl.TextSize = Theme.Text.Small()
				lbl.TextColor3 = opt.active and Theme.Colors.TextGold or Theme.Colors.TextPrimary
				lbl.TextXAlignment = Enum.TextXAlignment.Left
				lbl.Text = opt.label
				lbl.ZIndex = 52
				lbl.Parent = row
			else
				row.Text = opt.label
			end
			row.MouseButton1Click:Connect(function()
				closeDD()
				onSelect(opt.value, idx)
			end)
		end
	end

	-- Dropdown buttons
	local function makeDDBtn(text, order, isActive, iconAsset)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 62, 1, 0)
		btn.BackgroundColor3 = Theme.Colors.Surface
		btn.BackgroundTransparency = 0.2
		btn.BorderSizePixel = 0
		btn.LayoutOrder = order
		btn.Parent = ctrlRow
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 3)
		if iconAsset then
			btn.Text = ""
			local ico = Instance.new("ImageLabel")
			ico.Size = UDim2.new(0, 14, 0, 14)
			ico.Position = UDim2.new(0, 3, 0.5, -7)
			ico.BackgroundTransparency = 1
			ico.Image = iconAsset
			ico.ScaleType = Enum.ScaleType.Fit
			ico.ImageColor3 = isActive and Theme.Colors.TextGold or Theme.Colors.TextSecondary
			ico.Parent = btn
			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.new(1, -19, 1, 0)
			lbl.Position = UDim2.new(0, 19, 0, 0)
			lbl.BackgroundTransparency = 1
			lbl.Font = Theme.Font.Primary
			lbl.TextSize = Theme.Text.Small()
			lbl.TextColor3 = isActive and Theme.Colors.TextGold or Theme.Colors.TextSecondary
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.TextTruncate = Enum.TextTruncate.AtEnd
			lbl.Text = text
			lbl.Parent = btn
		else
			btn.Font = Theme.Font.Primary
			btn.TextSize = Theme.Text.Small()
			btn.TextColor3 = isActive and Theme.Colors.TextGold or Theme.Colors.TextSecondary
			btn.Text = text
		end
		return btn
	end

	-- Type filter (All / Skill / Augment + subtypes)
	local typeLbl = skillTypeFilter == "All" and "Type" or (skillTypeFilter )
	local typeBtn = makeDDBtn(typeLbl, 2, skillTypeFilter ~= "All", Theme.Icons.Filter)
	typeBtn.MouseButton1Click:Connect(function()
		local opts = {}
		local TYPE_ICONS = {
				All = Theme.Icons.Reset, Damage = Theme.Icons.Damage,
				Heal = Theme.Icons.Heal, Buff = Theme.Icons.Buff,
				Debuff = Theme.Icons.Debuff, Utility = Theme.Icons.Utility,
			}
			for _, ft in ipairs(SKILL_TYPE_FILTERS) do
				table.insert(opts, { label = ft, value = ft, icon = TYPE_ICONS[ft], active = (skillTypeFilter == ft) })
			end
		showDD(typeBtn, opts, function(val)
			skillTypeFilter = val
			selectedSkillCardId = nil
			buildSkillsContent()
		end)
	end)

	-- Tag filter
	local tagLbl = skillTagFilter == "All" and "Tags" or (skillTagFilter )
	local tagBtn = makeDDBtn(tagLbl, 3, skillTagFilter ~= "All", Theme.Icons.Filter)
	tagBtn.MouseButton1Click:Connect(function()
		local opts = {}
		local TAG_ICONS = {
				All = Theme.Icons.Reset, Fire = Theme.Icons.Fire,
				Ice = Theme.Icons.Ice, Electric = Theme.Icons.Electric,
				Holy = Theme.Icons.Holy, Dark = Theme.Icons.Dark,
				Poison = Theme.Icons.Poison, Physical = Theme.Icons.Physical,
			}
			for _, t in ipairs(SKILL_TAG_FILTERS) do
				table.insert(opts, { label = t, value = t, icon = TAG_ICONS[t], active = (skillTagFilter == t) })
			end
		showDD(tagBtn, opts, function(val)
			skillTagFilter = val
			selectedSkillCardId = nil
			buildSkillsContent()
		end)
	end)

	-- Sort
	local sortOpt = SKILL_SORT_OPTIONS_SK[skillSortIndex] or SKILL_SORT_OPTIONS_SK[1]
	local sortBtn = makeDDBtn(sortOpt.label , 4, false, Theme.Icons.Sort)
	sortBtn.MouseButton1Click:Connect(function()
		local opts = {}
		for si, s in ipairs(SKILL_SORT_OPTIONS_SK) do
			table.insert(opts, { label = s.label, value = si, active = (skillSortIndex == si) })
		end
		showDD(sortBtn, opts, function(val)
			skillSortIndex = val
			buildSkillsContent()
		end)
	end)

	-- ---- Build card data from inventory ----
	local skillCards = {}
	local augmentCards = {}

	-- Server skill card inventory
	if MockData.SkillCardInventory then
		for skillId, qty in pairs(MockData.SkillCardInventory) do
			if qty then
				local def = MockData.GetSkillDef(skillId)
				if def then
					table.insert(skillCards, {
						id = skillId, name = def.name or skillId,
						tags = def.tags or {}, mpCost = def.mpCostFormula or "?",
						rtCost = def.rtCostFormula or "?",
						desc = def.effects or "", qty = qty,
						isSkill = true, def = def,
					})
				end
			end
		end
	end

	-- Fallback: also include mock catalog if no server data
	if #skillCards == 0 then
		for _, sk in ipairs(MockData.SkillCatalog or {}) do
			if not sk.isDoctrine then
				table.insert(skillCards, {
					id = sk.id, name = sk.name,
					tags = sk.tags or {}, mpCost = "MP " .. (sk.mpCost or 0),
					rtCost = "RT " .. (sk.rtCost or 0),
					desc = sk.desc or "", qty = sk.qty or 1,
					isSkill = true, mockSkill = sk,
				})
			end
		end
	end

	-- Server augment card inventory
	if MockData.AugmentCardInventory then
		for augId, qty in pairs(MockData.AugmentCardInventory) do
			if qty then
				local def = MockData.GetAugmentDef(augId)
				if def then
					table.insert(augmentCards, {
						id = augId, name = def.name or augId,
						family = def.family or "", costFormula = def.costFormula or "",
						effect = def.effect or "", qty = qty,
						isAugment = true, def = def,
					})
				end
			end
		end
	end

	-- Filter by type
	if skillTypeFilter ~= "All" then
		if skillTypeFilter == "Damage" or skillTypeFilter == "Heal" or skillTypeFilter == "Buff"
			or skillTypeFilter == "Debuff" or skillTypeFilter == "Utility" then
			-- Filter skills only, remove augments
			local filtered = {}
			for _, sk in ipairs(skillCards) do
				if getSkillType(sk.tags) == skillTypeFilter then
					table.insert(filtered, sk)
				end
			end
			skillCards = filtered
			augmentCards = {}
		end
	end

	-- Filter by tag
	if skillTagFilter ~= "All" then
		local filtered = {}
		for _, sk in ipairs(skillCards) do
			local match = false
			for _, t in ipairs(sk.tags or {}) do
				if t == skillTagFilter then match = true; break end
			end
			if match then table.insert(filtered, sk) end
		end
		skillCards = filtered
		-- Augments: filter by required skill tags
		local augFiltered = {}
		for _, aug in ipairs(augmentCards) do
			local def = aug.def
			if def and def.requiredSkillTags then
				for _, rt in ipairs(def.requiredSkillTags) do
					if rt == skillTagFilter then
						table.insert(augFiltered, aug)
						break
					end
				end
			end
		end
		augmentCards = augFiltered
	end

	-- Search filter
	if skillSearchText and skillSearchText ~= "" then
		local q = string.lower(skillSearchText)
		local fSk = {}
		for _, sk in ipairs(skillCards) do
			if string.find(string.lower(sk.name), q, 1, true) then
				table.insert(fSk, sk)
			end
		end
		skillCards = fSk
		local fAug = {}
		for _, aug in ipairs(augmentCards) do
			if string.find(string.lower(aug.name), q, 1, true) then
				table.insert(fAug, aug)
			end
		end
		augmentCards = fAug
	end

	-- Sort skill cards
	local sortDef = SKILL_SORT_OPTIONS_SK[skillSortIndex] or SKILL_SORT_OPTIONS_SK[1]
	table.sort(skillCards, function(a, b)
		if sortDef.field == "name" then
			return (a.name or "") < (b.name or "")
		elseif sortDef.field == "mpCost" then
			local ma = tonumber(tostring(a.mpCost):match("%d+")) or 0
			local mb = tonumber(tostring(b.mpCost):match("%d+")) or 0
			if ma ~= mb then
				if sortDef.desc then return ma > mb else return ma < mb end
			end
			return false
		elseif sortDef.field == "rtCost" then
			local ra = tonumber(tostring(a.rtCost):match("%d+")) or 0
			local rb = tonumber(tostring(b.rtCost):match("%d+")) or 0
			if ra ~= rb then
				if sortDef.desc then return ra > rb else return ra < rb end
			end
			return false
		end
		return false
	end)

	-- Sort augment cards by name
	table.sort(augmentCards, function(a, b)
		return (a.name or "") < (b.name or "")
	end)

	-- ---- Build grid ----
	local cardGrid = Instance.new("ScrollingFrame")
	cardGrid.Name = "SkillCardGrid"
	cardGrid.Size = UDim2.new(1, 0, 1, -30)
	cardGrid.Position = UDim2.new(0, 0, 0, 28)
	cardGrid.BackgroundTransparency = 1
	cardGrid.BorderSizePixel = 0
	cardGrid.ScrollBarThickness = 4
	cardGrid.ScrollBarImageColor3 = Theme.Colors.TextSecondary
	cardGrid.CanvasSize = UDim2.new(0, 0, 0, 0)
	cardGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	cardGrid.Parent = skillsPanel

	local grid = Instance.new("UIGridLayout", cardGrid)
	grid.CellPadding = UDim2.new(0, 4, 0, 3)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirection = Enum.FillDirection.Horizontal

	-- Compute cell size: same logic as equipment grid
	local SK_MAX_CELL = 96
	local SK_MIN_CELL = 48
	local SK_ASPECT = 1.2
	local SK_GAP = 4
	local skContainerW = cardGrid.AbsoluteSize.X - 16
	local skContainerH = cardGrid.AbsoluteSize.Y
	if skContainerW < 100 then skContainerW = 400 end
	if skContainerH < 100 then skContainerH = 300 end
	-- Height-first: ensure 3 rows fit
	local skMaxCellH = math.floor((skContainerH - 2 * SK_GAP) / 3)
	local skCellW = math.floor(skMaxCellH / SK_ASPECT)
	skCellW = math.clamp(skCellW, SK_MIN_CELL, SK_MAX_CELL)
	local skCellH = math.floor(skCellW * SK_ASPECT)
	grid.CellSize = UDim2.new(0, skCellW, 0, skCellH)
	local skIconFrame = math.max(3, math.round(skCellW * 0.05))

	local layoutOrder = 0

	-- Skill tiles
	for _, sk in ipairs(skillCards) do
		local stype = getSkillType(sk.tags)
		local stc = STYPE_COLORS[stype] or STYPE_COLORS.Utility
		local isSel = (selectedSkillCardId == sk.id)

		local skQty = sk.qty or 1
		local card = Instance.new("TextButton")
		card.Size = UDim2.new(1, 0, 1, 0) -- sized by grid
		card.BackgroundColor3 = stc.bg
		card.BackgroundTransparency = (skQty <= 0) and 0.85 or 0.65
		card.BorderSizePixel = 0
		card.Text = ""
		card.AutoButtonColor = (skQty > 0)
		card.LayoutOrder = layoutOrder
		if skQty <= 0 then
			local dim = Instance.new("UIGradient", card)
			dim.Color = ColorSequence.new(Color3.fromRGB(80, 80, 80))
		end
		card.Parent = cardGrid
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 4)

		-- Border: type-colored normally, gold when selected
		local stroke = Instance.new("UIStroke", card)
		stroke.Color = isSel and Theme.Colors.TextGold or stc.icon
		stroke.Thickness = isSel and 2 or 1

		-- Qty badge (top-right, always shown for stackable items)
		local qBadge = Instance.new("Frame")
		qBadge.Size = UDim2.new(0, 22, 0, 12)
		qBadge.Position = UDim2.new(1, -24, 0, 2)
		qBadge.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		qBadge.BackgroundTransparency = 0.4
		qBadge.BorderSizePixel = 0
		qBadge.ZIndex = 3
		qBadge.Parent = card
		Instance.new("UICorner", qBadge).CornerRadius = UDim.new(0, 3)
		local qLbl = makeLabel(qBadge, { Text = "x" .. skQty, Size = UDim2.fromScale(1, 1),
			TextSize = Theme.Text.Badge(), Font = Theme.Font.Mono, TextColor3 = Theme.Colors.TextPrimary,
			TextXAlignment = Enum.TextXAlignment.Center })
		if qLbl then qLbl.ZIndex = 3 end

		-- Icon (full frame) — use uploaded image if available, else type emoji
		local skDef = sk.def or MockData.GetSkillDef(sk.id)
		if skDef and skDef.icon and skDef.icon ~= "" then
			local ico = Instance.new("ImageLabel")
			local skIcoSidePx = skCellW - skIconFrame * 2
			ico.Size = UDim2.new(1, -skIconFrame * 2, 0, skIcoSidePx)
			ico.Position = UDim2.fromOffset(skIconFrame, skIconFrame)
			ico.BackgroundTransparency = 1
			ico.Image = skDef.icon
			ico.ScaleType = Enum.ScaleType.Fit
			ico.Parent = card
		else
			makeLabel(card, { Text = STYPE_ICONS[stype] or "[*]",
				Size = UDim2.new(1, 0, 0, 24),
				Position = UDim2.new(0, 0, 0, 14),
				TextSize = Theme.Text.Title(), TextColor3 = stc.icon,
				TextXAlignment = Enum.TextXAlignment.Center })
		end

		-- Name strip (bottom)
		local nameBg = Instance.new("Frame")
		nameBg.Size = UDim2.new(1, 0, 0, 22)
		nameBg.Position = UDim2.new(0, 0, 1, -22)
		nameBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		nameBg.BackgroundTransparency = 0.45
		nameBg.BorderSizePixel = 0
		nameBg.Parent = card
		makeLabel(nameBg, { Text = sk.name,
			Size = UDim2.new(1, -4, 0, 12),
			Position = UDim2.new(0, 2, 0, 0),
			TextSize = Theme.Text.Tiny(), Font = Theme.Font.PrimaryBold,
			TextColor3 = stc.icon,
			TextXAlignment = Enum.TextXAlignment.Left })

		-- Tags line
		local elem = getElement(sk.tags)
		local tagStr = table.concat(sk.tags or {}, "  |  ")
		makeLabel(nameBg, { Text = tagStr,
			Size = UDim2.new(1, -4, 0, 10),
			Position = UDim2.new(0, 2, 0, 12),
			TextSize = Theme.Text.Badge(),
			TextColor3 = elem and ELEM_COLORS[elem] or Theme.Colors.TextSecondary })

		card.MouseButton1Click:Connect(function()
			openSkillCardDetail(sk)
		end)

		layoutOrder = layoutOrder + 1
	end

	-- Augment tiles
	for _, aug in ipairs(augmentCards) do
		local isSel = (selectedSkillCardId == aug.id)

		local augQty = aug.qty or 1
		local card = Instance.new("TextButton")
		card.Size = UDim2.new(1, 0, 1, 0) -- sized by grid
		card.BackgroundColor3 = Color3.fromRGB(74, 53, 16)
		card.BackgroundTransparency = (augQty <= 0) and 0.85 or 0.7
		card.BorderSizePixel = 0
		card.Text = ""
		card.AutoButtonColor = (augQty > 0)
		card.LayoutOrder = layoutOrder
		if augQty <= 0 then
			local dim = Instance.new("UIGradient", card)
			dim.Color = ColorSequence.new(Color3.fromRGB(80, 80, 80))
		end
		card.Parent = cardGrid
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 4)

		local stroke = Instance.new("UIStroke", card)
		stroke.Color = isSel and Theme.Colors.TextGold or Color3.fromRGB(74, 53, 16)
		stroke.Thickness = isSel and 2 or 1

		-- Cost badge (top-left)
		local costText = aug.costFormula or ""
		local costShort = costText:match("x[%d%.]+") or costText:match("x[%d%.]+") or ""
		if costShort ~= "" then
			local cBadge = Instance.new("Frame")
			cBadge.Size = UDim2.new(0, 28, 0, 12)
			cBadge.Position = UDim2.new(0, 2, 0, 2)
			cBadge.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			cBadge.BackgroundTransparency = 0.4
			cBadge.BorderSizePixel = 0
			cBadge.ZIndex = 3
			cBadge.Parent = card
			Instance.new("UICorner", cBadge).CornerRadius = UDim.new(0, 3)
			makeLabel(cBadge, { Text = costShort, Size = UDim2.fromScale(1, 1),
				TextSize = Theme.Text.Badge(), Font = Theme.Font.Mono, TextColor3 = Theme.Colors.TextGold,
				TextXAlignment = Enum.TextXAlignment.Center })
		end

		-- Qty badge (top-right, always shown for stackable items)
		local qBadge = Instance.new("Frame")
		qBadge.Size = UDim2.new(0, 22, 0, 12)
		qBadge.Position = UDim2.new(1, -24, 0, 2)
		qBadge.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		qBadge.BackgroundTransparency = 0.4
		qBadge.BorderSizePixel = 0
		qBadge.ZIndex = 3
		qBadge.Parent = card
		Instance.new("UICorner", qBadge).CornerRadius = UDim.new(0, 3)
		local qLbl = makeLabel(qBadge, { Text = "x" .. augQty, Size = UDim2.fromScale(1, 1),
			TextSize = Theme.Text.Badge(), Font = Theme.Font.Mono, TextColor3 = Theme.Colors.TextPrimary,
			TextXAlignment = Enum.TextXAlignment.Center })
		if qLbl then qLbl.ZIndex = 3 end

		-- Icon (full frame) — use uploaded image if available, else [o]
		local augDef = aug.def or MockData.GetAugmentDef(aug.id)
		if augDef and augDef.icon and augDef.icon ~= "" then
			local ico = Instance.new("ImageLabel")
			local augIcoSidePx = skCellW - skIconFrame * 2
			ico.Size = UDim2.new(1, -skIconFrame * 2, 0, augIcoSidePx)
			ico.Position = UDim2.fromOffset(skIconFrame, skIconFrame)
			ico.BackgroundTransparency = 1
			ico.Image = augDef.icon
			ico.ScaleType = Enum.ScaleType.Fit
			ico.Parent = card
		else
			makeLabel(card, { Text = "[o]",
				Size = UDim2.new(1, 0, 0, 24),
				Position = UDim2.new(0, 0, 0, 14),
				TextSize = Theme.Text.Title(), TextColor3 = Theme.Colors.TextGold,
				TextXAlignment = Enum.TextXAlignment.Center })
		end

		-- Name strip (bottom)
		local nameBg = Instance.new("Frame")
		nameBg.Size = UDim2.new(1, 0, 0, 22)
		nameBg.Position = UDim2.new(0, 0, 1, -22)
		nameBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		nameBg.BackgroundTransparency = 0.45
		nameBg.BorderSizePixel = 0
		nameBg.Parent = card
		makeLabel(nameBg, { Text = aug.name,
			Size = UDim2.new(1, -4, 0, 12),
			Position = UDim2.new(0, 2, 0, 0),
			TextSize = Theme.Text.Tiny(), Font = Theme.Font.PrimaryBold,
			TextColor3 = Theme.Colors.TextPrimary })
		makeLabel(nameBg, { Text = aug.family or "",
			Size = UDim2.new(1, -4, 0, 10),
			Position = UDim2.new(0, 2, 0, 12),
			TextSize = Theme.Text.Badge(), TextColor3 = Theme.Colors.TextGold })

		card.MouseButton1Click:Connect(function()
			openAugmentCardDetail(aug)
		end)

		layoutOrder = layoutOrder + 1
	end

	-- Empty state: show message if no cards in grid
	if #skillCards == 0 and #augmentCards == 0 then
		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Size = UDim2.new(1, 0, 0, 40)
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.Font = Theme.Font.Primary
		emptyLabel.TextSize = Theme.Text.Body()
		emptyLabel.TextColor3 = Theme.Colors.TextDisabled
		emptyLabel.Text = "No cards available"
		emptyLabel.TextXAlignment = Enum.TextXAlignment.Center
		emptyLabel.Parent = cardGrid
	end

	-- ============================================================
	-- RIGHT: SKILL LOADOUT TABLE (in equippedPanel)
	-- ============================================================
	buildSkillLoadout()
end


-- =====================================================
-- SKILLS TAB v3 Part 2: Loadout Table + Detail Overlays
-- =====================================================

-- ==================================================================
-- buildSkillLoadout: Renders the skill loadout in equippedPanel
-- ==================================================================
buildSkillLoadout = function()
	if not equippedPanel then return end
	clearChildren(equippedPanel)
	pad(equippedPanel, 6, 6, 6, 6)

	local unit = MockData.GetSelectedUnit()
	if not unit then return end

	local loadout = MockData.GetSkillLoadout(unit.id)
	local doctrineId = MockData.GetUnitDoctrineId(unit.id)

	-- Column headers
	local hdrRow = Instance.new("Frame")
	hdrRow.Size = UDim2.new(1, 0, 0, 14)
	hdrRow.Position = UDim2.new(0, 0, 0, 0)
	hdrRow.BackgroundTransparency = 1
	hdrRow.Parent = equippedPanel

	makeLabel(hdrRow, { Text = "SKILLS",
		Size = UDim2.new(0.6, 0, 1, 0), Position = UDim2.new(0, 24, 0, 0),
		Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Tiny(),
		TextColor3 = Theme.Colors.TextSecondary })
	makeLabel(hdrRow, { Text = "AUGMENTS",
		Size = UDim2.new(0.35, 0, 1, 0), Position = UDim2.new(0.65, 0, 0, 0),
		Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Tiny(),
		TextColor3 = Theme.Colors.TextSecondary,
		TextXAlignment = Enum.TextXAlignment.Center })

	-- Scrollable slot container (4 slots visible, 5th by scroll)
	local SLOT_H = 50
	local SLOT_GAP = 3
	local AUG_SZ = 22

	local slotScroll = Instance.new("ScrollingFrame")
	slotScroll.Name = "SlotScroll"
	slotScroll.Size = UDim2.new(1, 0, 1, -18)
	slotScroll.Position = UDim2.new(0, 0, 0, 16)
	slotScroll.BackgroundTransparency = 1
	slotScroll.BorderSizePixel = 0
	slotScroll.ScrollBarThickness = 3
	slotScroll.ScrollBarImageColor3 = Theme.Colors.TextSecondary
	slotScroll.CanvasSize = UDim2.new(0, 0, 0, (SLOT_H + SLOT_GAP) * 5)
	slotScroll.ClipsDescendants = true
	slotScroll.Parent = equippedPanel

	for slot = 1, 5 do
		local slotData = nil
		local skillId = nil
		local skillName = nil
		local augments = {}

		-- Get slot data from server or mock
		if type(loadout) == "table" and loadout[slot] then
			local sd = loadout[slot]
			if type(sd) == "table" then
				slotData = sd
				skillId = sd.skillId
				skillName = sd.skillName
				augments = sd.augments or {}
				if skillId == "none" then skillId = nil end
			else
				skillId = sd
				local sk = MockData.GetSkill(skillId)
				if sk then skillName = sk.name end
			end
		end

		local skillDef = skillId and MockData.GetSkillDef(skillId) or nil
		local mockSkill = skillId and MockData.GetSkill(skillId) or nil
		local tags = (skillDef and skillDef.tags) or (mockSkill and mockSkill.tags) or {}
		local name = (skillDef and skillDef.name) or skillName or (mockSkill and mockSkill.name) or nil

		local slotY = (slot - 1) * (SLOT_H + SLOT_GAP)

		-- Row container
		local rowF = Instance.new("Frame")
		rowF.Size = UDim2.new(1, 0, 0, SLOT_H)
		rowF.Position = UDim2.new(0, 0, 0, slotY)
		rowF.BackgroundColor3 = Theme.Colors.PanelRaised
		rowF.BackgroundTransparency = 0.3
		rowF.BorderSizePixel = 0
		rowF.Parent = slotScroll
		Instance.new("UICorner", rowF).CornerRadius = UDim.new(0, 4)

		-- ---- LOCKED SLOT 5 ----
		if slot == 5 then
			rowF.BackgroundTransparency = 0.6
			makeLabel(rowF, { Text = "[L] Locked - Race Evolution",
				Size = UDim2.new(1, -6, 1, 0),
				Position = UDim2.new(0, 3, 0, 0),
				TextSize = Theme.Text.Tiny(),
				TextColor3 = Theme.Colors.TextDisabled })

		elseif name then
			local stype = getSkillType(tags)
			local stc = STYPE_COLORS[stype] or STYPE_COLORS.Utility

			-- Skill icon (square, fills row height minus padding)
			local icoSz = SLOT_H - 4
			local sIco = Instance.new("TextButton")
			sIco.Name = "SkillIcon"
			sIco.Size = UDim2.new(0, icoSz, 0, icoSz)
			sIco.Position = UDim2.new(0, 2, 0, 2)
			sIco.BackgroundColor3 = stc.bg
			sIco.BackgroundTransparency = 0.15
			sIco.BorderSizePixel = 0
			sIco.Text = ""
			sIco.AutoButtonColor = false
			sIco.Parent = rowF
			Instance.new("UICorner", sIco).CornerRadius = UDim.new(0, 4)
			local slotDef = MockData.GetSkillDef(skillId)
			if slotDef and slotDef.icon and slotDef.icon ~= "" then
				local ico = Instance.new("ImageLabel")
				ico.Size = UDim2.new(1, -4, 1, -4)
				ico.Position = UDim2.new(0, 2, 0, 2)
				ico.BackgroundTransparency = 1
				ico.Image = slotDef.icon
				ico.ScaleType = Enum.ScaleType.Fit
				ico.Parent = sIco
			else
				makeLabel(sIco, { Text = STYPE_ICONS[stype] or "[*]",
					Size = UDim2.fromScale(1, 1), TextSize = Theme.Text.Heading(),
					TextColor3 = stc.icon, TextXAlignment = Enum.TextXAlignment.Center })
			end

			-- Click icon -> same detail view as inventory skill cards
			local capturedDef = MockData.GetSkillDef(skillId)
			local capturedMock = MockData.GetSkill(skillId)
			local capturedSk = {
				id = skillId,
				name = name,
				tags = tags,
				mpCost = capturedDef and capturedDef.mpCostFormula or (capturedMock and capturedMock.mpCost) or "?",
				rtCost = capturedDef and capturedDef.rtCostFormula or (capturedMock and capturedMock.rtCost) or "?",
				desc = capturedDef and capturedDef.effects or "",
				qty = 1,
				isSkill = true,
				def = capturedDef,
				mockSkill = capturedMock,
			}
			sIco.MouseButton1Click:Connect(function()
				openSkillCardDetail(capturedSk)
			end)

			-- Skill name only (no tags, no MP/RT)
			local nameX = icoSz + 6
			local augArea = (AUG_SZ + 2) * 2 + 4
			local nameW = UDim2.new(1, -(nameX + augArea), 1, 0)

			if slot == 1 then
				-- Doctrine: name is clickable for dropdown, show "DOCTRINE" subtitle
				local nameBtn = Instance.new("TextButton")
				nameBtn.Size = UDim2.new(1, -(nameX + augArea), 0, SLOT_H - 12)
				nameBtn.Position = UDim2.new(0, nameX, 0, 0)
				nameBtn.BackgroundTransparency = 1
				nameBtn.Text = ""
				nameBtn.Parent = rowF
				makeLabel(nameBtn, { Text = name,
					Size = UDim2.new(1, 0, 0, 16),
					Position = UDim2.new(0, 0, 0, 2),
					Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Small(),
					TextColor3 = Theme.Colors.TextGold })
				makeLabel(nameBtn, { Text = "DOCTRINE v",
					Size = UDim2.new(1, 0, 0, 10),
					Position = UDim2.new(0, 0, 1, -10),
					TextSize = Theme.Text.Badge(), Font = Theme.Font.PrimaryBold,
					TextColor3 = Theme.Colors.TextMuted or Theme.Colors.TextDisabled })

				-- Click name -> doctrine dropdown
				nameBtn.MouseButton1Click:Connect(function()
					local choices = MockData.GetDoctrineChoices(doctrineId)
					local opts = {}
					for _, cid in ipairs(choices) do
						local cSkill = MockData.GetSkill(cid) or MockData.GetSkillDef(cid)
						if cSkill then
							table.insert(opts, {
								label = cSkill.name,
								value = cid,
								active = (cid == skillId),
							})
						end
					end
					if activeDropdown then activeDropdown:Destroy(); activeDropdown = nil end
					local function closeDD()
						if activeDropdown then activeDropdown:Destroy(); activeDropdown = nil end
					end
					local rowH2 = 24
					local menuH = #opts * rowH2 + 4
					activeDropdown = Instance.new("ScreenGui")
					activeDropdown.Name = "DoctrineDropdown"
					activeDropdown.DisplayOrder = 105
					activeDropdown.ResetOnSpawn = false
					activeDropdown.Parent = getPlayerGui()
					local ddBack = Instance.new("TextButton")
					ddBack.Size = UDim2.fromScale(1, 1)
					ddBack.BackgroundTransparency = 1
					ddBack.Text = ""
					ddBack.Parent = activeDropdown
					ddBack.MouseButton1Click:Connect(closeDD)
					local mPanel = Instance.new("Frame")
					mPanel.Size = UDim2.new(0, 140, 0, menuH)
					mPanel.Position = UDim2.new(0,
						rowF.AbsolutePosition.X + icoSz + 4,
						0, rowF.AbsolutePosition.Y + rowF.AbsoluteSize.Y + 2)
					mPanel.BackgroundColor3 = Theme.Colors.Panel
					mPanel.BorderSizePixel = 0
					mPanel.ZIndex = 50
					mPanel.Parent = activeDropdown
					Instance.new("UICorner", mPanel).CornerRadius = UDim.new(0, 4)
					Instance.new("UIStroke", mPanel).Color = Theme.Colors.Border
					pad(mPanel, 2, 2, 2, 2)
					local mLayout = Instance.new("UIListLayout", mPanel)
					mLayout.Padding = UDim.new(0, 0)
					mLayout.SortOrder = Enum.SortOrder.LayoutOrder
					for idx, opt in ipairs(opts) do
						local mRow = Instance.new("TextButton")
						mRow.Size = UDim2.new(1, 0, 0, rowH2)
						mRow.BackgroundColor3 = Theme.Colors.PanelRaised
						mRow.BackgroundTransparency = opt.active and 0.2 or 0.6
						mRow.Font = Theme.Font.Primary
						mRow.TextSize = Theme.Text.Small()
						mRow.TextColor3 = opt.active and Theme.Colors.TextGold or Theme.Colors.TextPrimary
						mRow.Text = opt.label
						mRow.BorderSizePixel = 0
						mRow.LayoutOrder = idx
						mRow.ZIndex = 51
						mRow.Parent = mPanel
						Instance.new("UICorner", mRow).CornerRadius = UDim.new(0, 3)
						mRow.MouseButton1Click:Connect(function()
							closeDD()
							if MockData.ServerSelectDoctrineSkill then
								MockData.ServerSelectDoctrineSkill(unit.id, opt.value)
							else
								local sl = MockData.SkillLoadout[unit.id]
								if sl then sl[1] = opt.value end
							end
							MockData.LoadSkillData(unit.id)
							buildSkillsContent()
						end)
					end
				end)
			else
				-- Slots 2-4: just show full name
				makeLabel(rowF, { Text = name,
					Size = UDim2.new(1, -(nameX + augArea), 1, 0),
					Position = UDim2.new(0, nameX, 0, 0),
					Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Small(),
					TextColor3 = Theme.Colors.TextPrimary })
			end

			-- Augment icon slots (right side, 2 small squares)
			for a = 1, 2 do
				local augId = augments[a]
				local augDef = augId and MockData.GetAugmentDef(augId)

				local augBtn = Instance.new("TextButton")
				augBtn.Size = UDim2.new(0, AUG_SZ, 0, AUG_SZ)
				augBtn.Position = UDim2.new(1, -(AUG_SZ + 2) * (3 - a), 0, (SLOT_H - AUG_SZ) / 2)
				augBtn.BackgroundColor3 = augDef and Color3.fromRGB(74, 53, 16) or Theme.Colors.Surface
				augBtn.BackgroundTransparency = augDef and 0.3 or 0.6
				augBtn.BorderSizePixel = 0
				augBtn.Text = ""
				augBtn.Parent = rowF
				Instance.new("UICorner", augBtn).CornerRadius = UDim.new(0, 3)

				if augDef then
					-- Show icon image or fallback
					if augDef.icon and augDef.icon ~= "" then
						local ico = Instance.new("ImageLabel")
						ico.Size = UDim2.new(1, -2, 1, -2)
						ico.Position = UDim2.new(0, 1, 0, 1)
						ico.BackgroundTransparency = 1
						ico.Image = augDef.icon
						ico.ScaleType = Enum.ScaleType.Fit
						ico.Parent = augBtn
					else
						makeLabel(augBtn, { Text = "[o]",
							Size = UDim2.fromScale(1, 1),
							TextSize = Theme.Text.Body(), TextColor3 = Theme.Colors.TextGold,
							TextXAlignment = Enum.TextXAlignment.Center })
					end

					local cSlot = slot
					local cAug = a
					augBtn.MouseButton1Click:Connect(function()
						openEquippedAugmentDetail(cSlot, cAug, augId)
					end)
				else
					-- Empty augment slot — click opens augment card inventory detail
					makeLabel(augBtn, { Text = "+",
						Size = UDim2.fromScale(1, 1),
						TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextDisabled,
						TextXAlignment = Enum.TextXAlignment.Center })
					local cSlot = slot
					local cAug = a
					augBtn.MouseButton1Click:Connect(function()
						-- Open a picker showing all augment cards to attach to this specific slot
						openAugmentPickerForSlot(unit.id, cSlot, cAug)
					end)
				end
			end

		else
			-- Empty skill slot
			makeLabel(rowF, { Text = "- Empty -",
				Size = UDim2.new(1, -6, 1, 0),
				Position = UDim2.new(0, 3, 0, 0),
				TextSize = Theme.Text.Small(),
				TextColor3 = Theme.Colors.TextDisabled })
		end
	end

	-- Doctrine note
	makeLabel(equippedPanel, { Text = "Slot 1 = Doctrine skill",
		Size = UDim2.new(1, 0, 0, 12),
		Position = UDim2.new(0, 0, 1, -14),
		TextSize = Theme.Text.Badge(), TextColor3 = Theme.Colors.TextDisabled })
end


-- ==================================================================
-- openSkillCardDetail: Detail overlay for inventory skill card
-- ==================================================================
openSkillCardDetail = function(sk)
	closeDetail()
	if activeDropdown then activeDropdown:Destroy(); activeDropdown = nil end

	local unit = MockData.GetSelectedUnit()
	local def = sk.def or MockData.GetSkillDef(sk.id)
	local tags = (def and def.tags) or sk.tags or {}
	local stype = getSkillType(tags)
	local stc = STYPE_COLORS[stype] or STYPE_COLORS.Utility
	local elem = getElement(tags)

	-- Overlay ScreenGui
	detailOverlay = Instance.new("ScreenGui")
	detailOverlay.Name = "SkillDetailOverlay"
	detailOverlay.DisplayOrder = 110
	detailOverlay.ResetOnSpawn = false
	detailOverlay.Parent = getPlayerGui()

	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.Overlay
	backdrop.BackgroundTransparency = 0.4
	backdrop.Text = ""
	backdrop.BorderSizePixel = 0
	backdrop.Parent = detailOverlay
	backdrop.MouseButton1Click:Connect(closeDetail)

	-- Detail panel (left-docked, 55% width)
	local panel = Theme.MakePanel("SkillDetailPanel",
		UDim2.new(0.55, 0, 0.90, 0),
		UDim2.new(0, 6, 0.5, 0),
		Vector2.new(0, 0.5),
		detailOverlay)
	panel.ClipsDescendants = true

	-- Scrollable content
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -16, 1, -8)
	scroll.Position = UDim2.new(0, 8, 0, 4)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageColor3 = Theme.Colors.TextSecondary
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel

	local layout = Instance.new("UIListLayout", scroll)
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	local order = 0
	local function addRow(parent, height)
		local f = Instance.new("Frame")
		f.Size = UDim2.new(1, 0, 0, height)
		f.BackgroundTransparency = 1
		f.LayoutOrder = order
		f.Parent = parent
		order = order + 1
		return f
	end

	-- Unified header
	local descText = (def and def.description) or buildSkillDescription(def)
	local hdrH = buildDetailHeader(addRow(scroll, 72), {
		iconText = STYPE_ICONS[stype] or "[*]",
		iconImage = def and def.icon or nil,
		iconBg = stc.bg,
		iconColor = stc.icon,
		iconStrokeColor = stc.icon,
		name = def and def.name or sk.name or "?",
		tags = tags,
		description = descText or "",
	})

	-- Divider
	local div = addRow(scroll, 1)
	div.BackgroundColor3 = Theme.Colors.Border
	div.BackgroundTransparency = 0

	-- Stats section
	local statsHdr = addRow(scroll, 12)
	makeLabel(statsHdr, { Text = "STATS", Size = UDim2.fromScale(1, 1),
		Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Tiny(),
		TextColor3 = Theme.Colors.TextSecondary })

	-- Stat rows helper
	local function addStatRow(label, value)
		local r = addRow(scroll, 16)
		makeLabel(r, { Text = label, Size = UDim2.new(0.3, 0, 1, 0),
			TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextSecondary })
		makeLabel(r, { Text = value, Size = UDim2.new(0.7, -4, 1, 0),
			Position = UDim2.new(0.3, 4, 0, 0),
			TextSize = Theme.Text.Small(), Font = Theme.Font.Mono,
			TextColor3 = Theme.Colors.TextPrimary,
			TextXAlignment = Enum.TextXAlignment.Right })
	end

	if def then
		addStatRow("MP Cost", def.mpCostFormula or "-")
		addStatRow("RT Cost", def.rtCostFormula or "-")
		addStatRow("Pattern", simplifyPattern(def.pattern))
		if def.channelTime and def.channelTime > 0 then
			addStatRow("Channel", tostring(def.channelTime) .. " CT")
		end
		if def.activationTime and def.activationTime > 0 then
			addStatRow("Activation", tostring(def.activationTime) .. " CT")
		end

		-- Range box
		if def.targetingRange then
			addStatRow("Range", simplifyRange(def.targetingRange))
		end

		-- Power formula
		if def.powerFormula then
			local pf = addRow(scroll, 30)
			pf.BackgroundColor3 = Theme.Colors.Surface
			pf.BackgroundTransparency = 0.3
			Instance.new("UICorner", pf).CornerRadius = UDim.new(0, 4)
			makeLabel(pf, { Text = "POWER",
				Size = UDim2.new(1, -8, 0, 10),
				Position = UDim2.new(0, 4, 0, 2),
				TextSize = Theme.Text.Badge(), Font = Theme.Font.PrimaryBold,
				TextColor3 = Theme.Colors.TextSecondary })
			makeLabel(pf, { Text = def.powerFormula,
				Size = UDim2.new(1, -8, 0, 14),
				Position = UDim2.new(0, 4, 0, 14),
				TextSize = Theme.Text.Tiny(), Font = Theme.Font.Mono,
				TextColor3 = Theme.Colors.Info })
		end

		-- Effects
		local effectsDisplayText = (def.description) or cleanEffects(def.effects)
		if effectsDisplayText and effectsDisplayText ~= "" then
			local ef = addRow(scroll, 40)
			ef.BackgroundColor3 = Theme.Colors.PanelRaised
			ef.BackgroundTransparency = 0.2
			Instance.new("UICorner", ef).CornerRadius = UDim.new(0, 4)
			makeLabel(ef, { Text = "DESCRIPTION",
				Size = UDim2.new(1, -8, 0, 10),
				Position = UDim2.new(0, 4, 0, 2),
				TextSize = Theme.Text.Badge(), Font = Theme.Font.PrimaryBold,
				TextColor3 = Theme.Colors.TextSecondary })
			makeLabel(ef, { Text = effectsDisplayText,
				Size = UDim2.new(1, -8, 0, 24),
				Position = UDim2.new(0, 4, 0, 14),
				TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextSecondary,
				TextWrapped = true })
		end
	else
		-- Mock skill fallback
		local ms = sk.mockSkill or sk
		addStatRow("MP Cost", "MP " .. tostring(ms.mpCost or 0))
		addStatRow("RT Cost", "RT " .. tostring(ms.rtCost or 0))
		addStatRow("Range", tostring(ms.range or 1))
		addStatRow("Pattern", ms.pattern or "Single")
		if ms.desc and ms.desc ~= "" then
			local ef = addRow(scroll, 30)
			ef.BackgroundColor3 = Theme.Colors.PanelRaised
			ef.BackgroundTransparency = 0.2
			Instance.new("UICorner", ef).CornerRadius = UDim.new(0, 4)
			makeLabel(ef, { Text = ms.desc,
				Size = UDim2.new(1, -8, 1, -4),
				Position = UDim2.new(0, 4, 0, 2),
				TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextSecondary,
				TextWrapped = true })
		end
	end

	-- ---- BUTTON BAR ----
	local fb = Theme.FooterBar
	local btnBar = Instance.new("Frame")
	btnBar.Name = "BtnBar"
	btnBar.BackgroundTransparency = 1
	btnBar.AnchorPoint = Vector2.new(1, 1)
	btnBar.Position = UDim2.new(1, -fb.PAD, 1, -fb.PAD)
	btnBar.Parent = detailOverlay
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, fb.BTN_GAP)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = btnBar

	local btnOrder = 0
	local function addBtn(text, color, onClick)
		local style = "Secondary"
		if color == Theme.Colors.Success or color == Theme.Colors.Danger then
			style = "Primary"
		elseif color == Theme.Colors.Surface then
			if text == "COMPARE" or text == "DETAILS" or text == "SWAP" then
				style = "Tertiary"
			end
		end
		local btn = Theme.MakeButton(btnBar, text, style, onClick, {
			size = UDim2.new(0, fb.BTN_W, 0, fb.BTN_H),
		})
		btn.LayoutOrder = btnOrder
		btnOrder = btnOrder + 1
		return btn
	end

	-- EQUIP -> opens slot picker
	addBtn("EQUIP", Theme.Colors.Success, function()
		closeDetail()
		openSkillSlotPicker(sk)
	end)

	addBtn("BACK", Theme.Colors.Surface, closeDetail)

	btnBar.Size = UDim2.new(0, (btnOrder * fb.BTN_W) + ((btnOrder - 1) * fb.BTN_GAP), 0, fb.BTN_H)
end

-- ==================================================================
-- openAugmentCardDetail: Detail overlay for inventory augment card
-- ==================================================================
openAugmentCardDetail = function(aug)
	closeDetail()
	if activeDropdown then activeDropdown:Destroy(); activeDropdown = nil end

	local def = aug.def or MockData.GetAugmentDef(aug.id)

	detailOverlay = Instance.new("ScreenGui")
	detailOverlay.Name = "AugmentDetailOverlay"
	detailOverlay.DisplayOrder = 110
	detailOverlay.ResetOnSpawn = false
	detailOverlay.Parent = getPlayerGui()

	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.Overlay
	backdrop.BackgroundTransparency = 0.4
	backdrop.Text = ""
	backdrop.BorderSizePixel = 0
	backdrop.Parent = detailOverlay
	backdrop.MouseButton1Click:Connect(closeDetail)

	local panel = Theme.MakePanel("AugmentDetailPanel",
		UDim2.new(0.55, 0, 0.90, 0),
		UDim2.new(0, 6, 0.5, 0),
		Vector2.new(0, 0.5),
		detailOverlay)
	panel.ClipsDescendants = true

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -16, 1, -8)
	scroll.Position = UDim2.new(0, 8, 0, 4)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 3
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel

	local layout = Instance.new("UIListLayout", scroll)
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	local order = 0
	local function addRow(parent, height)
		local f = Instance.new("Frame")
		f.Size = UDim2.new(1, 0, 0, height)
		f.BackgroundTransparency = 1
		f.LayoutOrder = order
		f.Parent = parent
		order = order + 1
		return f
	end

	-- Unified header
	local augTags = {}
	if def and def.family then table.insert(augTags, def.family) end
	local augDescText = (def and def.description) or ""
	local hdrH = buildDetailHeader(addRow(scroll, 72), {
		iconText = "[o]",
		iconImage = def and def.icon or nil,
		iconBg = Color3.fromRGB(74, 53, 16),
		iconColor = Theme.Colors.TextGold,
		iconStrokeColor = Theme.Colors.TextGold,
		name = def and def.name or aug.name or "?",
		tags = augTags,
		description = augDescText,
	})

	-- Requirement tags
	if def then
		local reqTags = def.requiredSkillTags or {}
		if #reqTags > 0 or (def.requiredTargetRules and def.requiredTargetRules ~= "") then
			local tagRow = addRow(scroll, 18)
			local tagL = Instance.new("UIListLayout", tagRow)
			tagL.FillDirection = Enum.FillDirection.Horizontal
			tagL.Padding = UDim.new(0, 4)
			local ti = 0
			for _, rt in ipairs(reqTags) do
				ti = ti + 1
				local chip = Instance.new("Frame")
				chip.Size = UDim2.new(0, #("Req: " .. rt) * 5 + 12, 0, 16)
				chip.BackgroundColor3 = Theme.Colors.Surface
				chip.BackgroundTransparency = 0.3
				chip.BorderSizePixel = 0
				chip.LayoutOrder = ti
				chip.Parent = tagRow
				Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 8)
				Instance.new("UIStroke", chip).Color = Theme.Colors.Border
				makeLabel(chip, { Text = "Req: " .. rt, Size = UDim2.fromScale(1, 1),
					TextSize = Theme.Text.Badge(), Font = Theme.Font.PrimaryBold,
					TextColor3 = Theme.Colors.TextSecondary,
					TextXAlignment = Enum.TextXAlignment.Center })
			end
			if def.requiredTargetRules and def.requiredTargetRules ~= "" then
				ti = ti + 1
				local chip = Instance.new("Frame")
				chip.Size = UDim2.new(0, #("Req: " .. def.requiredTargetRules) * 5 + 12, 0, 16)
				chip.BackgroundColor3 = Theme.Colors.Surface
				chip.BackgroundTransparency = 0.3
				chip.BorderSizePixel = 0
				chip.LayoutOrder = ti
				chip.Parent = tagRow
				Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 8)
				Instance.new("UIStroke", chip).Color = Theme.Colors.Border
				makeLabel(chip, { Text = "Req: " .. def.requiredTargetRules, Size = UDim2.fromScale(1, 1),
					TextSize = Theme.Text.Badge(), Font = Theme.Font.PrimaryBold,
					TextColor3 = Theme.Colors.TextSecondary,
					TextXAlignment = Enum.TextXAlignment.Center })
			end
		end
	end

	-- Effect
	local effText = (def and def.description) or (def and def.effect) or aug.effect or ""
	if effText ~= "" then
		local ef = addRow(scroll, 40)
		ef.BackgroundColor3 = Theme.Colors.PanelRaised
		ef.BackgroundTransparency = 0.2
		Instance.new("UICorner", ef).CornerRadius = UDim.new(0, 4)
		makeLabel(ef, { Text = "EFFECT",
			Size = UDim2.new(1, -8, 0, 10),
			Position = UDim2.new(0, 4, 0, 2),
			TextSize = Theme.Text.Badge(), Font = Theme.Font.PrimaryBold,
			TextColor3 = Theme.Colors.TextSecondary })
		makeLabel(ef, { Text = effText,
			Size = UDim2.new(1, -8, 0, 24),
			Position = UDim2.new(0, 4, 0, 14),
			TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextSecondary,
			TextWrapped = true })
	end

	-- Cost modifier
	if def and def.costFormula then
		local cm = addRow(scroll, 22)
		cm.BackgroundColor3 = Theme.Colors.PanelRaised
		cm.BackgroundTransparency = 0.2
		Instance.new("UICorner", cm).CornerRadius = UDim.new(0, 4)
		makeLabel(cm, { Text = "COST MODIFIER", Size = UDim2.new(0.4, 0, 1, 0),
			Position = UDim2.new(0, 4, 0, 0),
			TextSize = Theme.Text.Badge(), Font = Theme.Font.PrimaryBold, TextColor3 = Theme.Colors.TextSecondary })
		makeLabel(cm, { Text = def.costFormula, Size = UDim2.new(0.5, 0, 1, 0),
			Position = UDim2.new(0.45, 0, 0, 0),
			TextSize = Theme.Text.Body(), Font = Theme.Font.Mono, TextColor3 = Theme.Colors.Danger,
			TextXAlignment = Enum.TextXAlignment.Right })
	end

	-- Details
	if def then
		local function addDetailRow(label, value)
			if not value or value == "" then return end
			local r = addRow(scroll, 16)
			makeLabel(r, { Text = label, Size = UDim2.new(0.4, 0, 1, 0),
				TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextSecondary })
			makeLabel(r, { Text = value, Size = UDim2.new(0.6, 0, 1, 0),
				Position = UDim2.new(0.4, 0, 0, 0),
				TextSize = Theme.Text.Small(), Font = Theme.Font.Mono, TextColor3 = Theme.Colors.TextPrimary,
				TextXAlignment = Enum.TextXAlignment.Right })
		end
		addDetailRow("Trigger", def.trigger)
		addDetailRow("Frequency", def.deliveryFrequency)
		addDetailRow("Snapshot", def.snapshotTiming)
	end

	-- Conflicts
	if def and def.conflicts and def.conflicts ~= "" then
		local cf = addRow(scroll, 36)
		cf.BackgroundColor3 = Color3.fromRGB(60, 20, 20)
		cf.BackgroundTransparency = 0.4
		Instance.new("UICorner", cf).CornerRadius = UDim.new(0, 4)
		makeLabel(cf, { Text = "[!] CONFLICTS",
			Size = UDim2.new(1, -8, 0, 10),
			Position = UDim2.new(0, 4, 0, 2),
			TextSize = Theme.Text.Badge(), Font = Theme.Font.PrimaryBold, TextColor3 = Theme.Colors.Danger })
		makeLabel(cf, { Text = def.conflicts,
			Size = UDim2.new(1, -8, 0, 20),
			Position = UDim2.new(0, 4, 0, 14),
			TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextSecondary, TextWrapped = true })
	end

	-- ---- BUTTON BAR ----
	local fb = Theme.FooterBar
	local btnBar = Instance.new("Frame")
	btnBar.Name = "BtnBar"
	btnBar.BackgroundTransparency = 1
	btnBar.AnchorPoint = Vector2.new(1, 1)
	btnBar.Position = UDim2.new(1, -fb.PAD, 1, -fb.PAD)
	btnBar.Parent = detailOverlay
	local bLayout = Instance.new("UIListLayout")
	bLayout.FillDirection = Enum.FillDirection.Horizontal
	bLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	bLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	bLayout.Padding = UDim.new(0, fb.BTN_GAP)
	bLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bLayout.Parent = btnBar
	local btnOrder = 0
	local function addBtn(text, color, onClick)
		local style = "Secondary"
		if color == Theme.Colors.Success or color == Theme.Colors.Danger then
			style = "Primary"
		elseif color == Theme.Colors.Surface then
			if text == "COMPARE" or text == "DETAILS" or text == "SWAP" then
				style = "Tertiary"
			end
		end
		local btn = Theme.MakeButton(btnBar, text, style, onClick, {
			size = UDim2.new(0, fb.BTN_W, 0, fb.BTN_H),
		})
		btn.LayoutOrder = btnOrder
		btnOrder = btnOrder + 1
	end

	addBtn("ATTACH", Theme.Colors.Success, function()
		closeDetail()
		openAugmentSlotPicker(aug)
	end)
	addBtn("BACK", Theme.Colors.Surface, closeDetail)
	btnBar.Size = UDim2.new(0, (btnOrder * fb.BTN_W) + ((btnOrder - 1) * fb.BTN_GAP), 0, fb.BTN_H)
end

-- ==================================================================
-- openSkillSlotPicker: Modal popup to choose which slot to equip to
-- ==================================================================
openSkillSlotPicker = function(sk)
	closeDetail()
	local unit = MockData.GetSelectedUnit()
	if not unit then return end
	local loadout = MockData.GetSkillLoadout(unit.id)

	detailOverlay = Instance.new("ScreenGui")
	detailOverlay.Name = "SlotPickerOverlay"
	detailOverlay.DisplayOrder = 115
	detailOverlay.ResetOnSpawn = false
	detailOverlay.Parent = getPlayerGui()

	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.Overlay
	backdrop.BackgroundTransparency = 0.5
	backdrop.Text = ""
	backdrop.BorderSizePixel = 0
	backdrop.Parent = detailOverlay
	backdrop.MouseButton1Click:Connect(closeDetail)

	local popup = Theme.MakePanel("SlotPicker",
		UDim2.new(0, 280, 0, 240),
		UDim2.new(0.5, 0, 0.5, 0),
		Vector2.new(0.5, 0.5),
		detailOverlay)
	popup.ClipsDescendants = true
	pad(popup, 10, 10, 10, 10)

	makeLabel(popup, { Text = "> Equip " .. (sk.name or "?") .. " to:",
		Size = UDim2.new(1, 0, 0, 18),
		Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Body(),
		TextColor3 = Theme.Colors.TextPrimary })

	local rowY = 24
	for slot = 1, 5 do
		local disabled = false
		local slotLabel = "Slot " .. slot
		local occupant = "Empty"
		local slotColor = Theme.Colors.Player

		if slot == 1 then
			disabled = true
			slotLabel = "Doctrine Slot"
			occupant = "Doctrine only"
			slotColor = Theme.Colors.TextGold
		elseif slot == 5 then
			disabled = true
			slotLabel = "Slot 5"
			occupant = "Locked - Race Evolution"
			slotColor = Theme.Colors.TextDisabled
		else
			-- Check current occupant
			local sd = type(loadout) == "table" and loadout[slot]
			if sd then
				local occName
				if type(sd) == "table" then
					occName = sd.skillName
					if occName == "none" then occName = nil end
				else
					local ms = MockData.GetSkill(sd) or MockData.GetSkillDef(sd)
					if ms then occName = ms.name end
				end
				if occName then
					occupant = "Replace: " .. occName
				end
			end
		end

		local rowBtn = Instance.new("TextButton")
		rowBtn.Size = UDim2.new(1, 0, 0, 32)
		rowBtn.Position = UDim2.new(0, 0, 0, rowY)
		rowBtn.BackgroundColor3 = Theme.Colors.PanelRaised
		rowBtn.BackgroundTransparency = disabled and 0.6 or 0.2
		rowBtn.BorderSizePixel = 0
		rowBtn.Text = ""
		rowBtn.AutoButtonColor = not disabled
		rowBtn.Parent = popup
		Instance.new("UICorner", rowBtn).CornerRadius = UDim.new(0, 4)

		-- Badge
		local bF = Instance.new("Frame")
		bF.Size = UDim2.new(0, 20, 0, 20)
		bF.Position = UDim2.new(0, 6, 0.5, -10)
		bF.BackgroundColor3 = slotColor
		bF.BackgroundTransparency = disabled and 0.5 or 0
		bF.BorderSizePixel = 0
		bF.Parent = rowBtn
		Instance.new("UICorner", bF).CornerRadius = UDim.new(0.5, 0)
		makeLabel(bF, { Text = tostring(slot), Size = UDim2.fromScale(1, 1),
			TextSize = Theme.Text.Small(), Font = Theme.Font.PrimaryBold,
			TextColor3 = Color3.fromRGB(13, 15, 20),
			TextXAlignment = Enum.TextXAlignment.Center })

		makeLabel(rowBtn, { Text = slotLabel,
			Size = UDim2.new(0.4, -30, 1, 0),
			Position = UDim2.new(0, 32, 0, 0),
			Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Small(),
			TextColor3 = disabled and Theme.Colors.TextDisabled or Theme.Colors.TextPrimary })
		makeLabel(rowBtn, { Text = occupant,
			Size = UDim2.new(0.5, 0, 1, 0),
			Position = UDim2.new(0.48, 0, 0, 0),
			TextSize = Theme.Text.Tiny(),
			TextColor3 = disabled and Theme.Colors.TextDisabled or Theme.Colors.Warning,
			TextXAlignment = Enum.TextXAlignment.Right })

		if not disabled then
			local capturedSlot = slot
			rowBtn.MouseButton1Click:Connect(function()
				closeDetail()
				-- Equip: server auto-handles unequip of existing + augment return
				if MockData.ServerEquipSkillCard then
					MockData.ServerEquipSkillCard(unit.id, capturedSlot, sk.id)
				else
					local sl = MockData.SkillLoadout[unit.id]
					if sl then sl[capturedSlot] = sk.id end
				end
				MockData.LoadSkillData(unit.id)
				buildSkillsContent()
			end)
		end

		rowY = rowY + 36
	end

	-- Cancel
	local cancel = Instance.new("TextButton")
	cancel.Size = UDim2.new(1, 0, 0, 18)
	cancel.Position = UDim2.new(0, 0, 1, -20)
	cancel.BackgroundTransparency = 1
	cancel.Font = Theme.Font.Primary
	cancel.TextSize = Theme.Text.Small()
	cancel.TextColor3 = Theme.Colors.TextSecondary
	cancel.Text = "Cancel"
	cancel.Parent = popup
	cancel.MouseButton1Click:Connect(closeDetail)
end

-- ==================================================================
-- openAugmentPickerForSlot: Show available augment cards to attach to a specific slot
-- Called when clicking an empty "+" augment slot in the loadout table
local function openAugmentPickerForSlot(unitId, slotNum, augSlotNum)
	closeDetail()
	local unit = MockData.GetSelectedUnit()
	if not unit then return end

	-- Build list of available augment cards
	local augCards = {}
	if MockData.AugmentCardInventory then
		for augId, qty in pairs(MockData.AugmentCardInventory) do
			if qty and qty > 0 then
				local def = MockData.GetAugmentDef(augId)
				if def then
					table.insert(augCards, { id = augId, name = def.name or augId, qty = qty, def = def })
				end
			end
		end
	end
	table.sort(augCards, function(a, b) return a.name < b.name end)

	if #augCards == 0 then return end

	detailOverlay = Instance.new("ScreenGui")
	detailOverlay.Name = "AugPickerForSlot"
	detailOverlay.DisplayOrder = 115
	detailOverlay.ResetOnSpawn = false
	detailOverlay.Parent = getPlayerGui()

	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.Overlay
	backdrop.BackgroundTransparency = 0.5
	backdrop.Text = ""
	backdrop.BorderSizePixel = 0
	backdrop.Parent = detailOverlay
	backdrop.MouseButton1Click:Connect(closeDetail)

	local popup = Theme.MakePanel("AugPickerForSlot",
		UDim2.new(0, 280, 0, 300),
		UDim2.new(0.5, 0, 0.5, 0),
		Vector2.new(0.5, 0.5),
		detailOverlay)
	popup.ClipsDescendants = true
	pad(popup, 10, 10, 10, 10)

	makeLabel(popup, { Text = "Attach augment to Slot " .. slotNum .. " Aug " .. augSlotNum .. ":",
		Size = UDim2.new(1, 0, 0, 18),
		Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Body(),
		TextColor3 = Theme.Colors.TextGold })

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, 0, 1, -44)
	scroll.Position = UDim2.new(0, 0, 0, 22)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 3
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = popup

	local sLayout = Instance.new("UIListLayout", scroll)
	sLayout.Padding = UDim.new(0, 3)
	sLayout.SortOrder = Enum.SortOrder.LayoutOrder

	for idx, ac in ipairs(augCards) do
		local rowBtn = Instance.new("TextButton")
		rowBtn.Size = UDim2.new(1, 0, 0, 28)
		rowBtn.BackgroundColor3 = Theme.Colors.PanelRaised
		rowBtn.BackgroundTransparency = 0.2
		rowBtn.BorderSizePixel = 0
		rowBtn.Text = ""
		rowBtn.AutoButtonColor = true
		rowBtn.LayoutOrder = idx
		rowBtn.Parent = scroll
		Instance.new("UICorner", rowBtn).CornerRadius = UDim.new(0, 4)

		-- Icon
		if ac.def and ac.def.icon and ac.def.icon ~= "" then
			local ico = Instance.new("ImageLabel")
			ico.Size = UDim2.new(0, 22, 0, 22)
			ico.Position = UDim2.new(0, 3, 0, 3)
			ico.BackgroundTransparency = 1
			ico.Image = ac.def.icon
			ico.ScaleType = Enum.ScaleType.Fit
			ico.Parent = rowBtn
		end

		makeLabel(rowBtn, { Text = ac.name,
			Size = UDim2.new(1, -32, 1, 0),
			Position = UDim2.new(0, 28, 0, 0),
			Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Small(),
			TextColor3 = Theme.Colors.TextPrimary })

		makeLabel(rowBtn, { Text = "x" .. ac.qty,
			Size = UDim2.new(0, 24, 1, 0),
			Position = UDim2.new(1, -26, 0, 0),
			TextSize = Theme.Text.Badge(), Font = Theme.Font.Mono,
			TextColor3 = Theme.Colors.TextSecondary,
			TextXAlignment = Enum.TextXAlignment.Right })

		rowBtn.MouseButton1Click:Connect(function()
			closeDetail()
			if MockData.ServerAttachAugment then
				MockData.ServerAttachAugment(unitId, slotNum, augSlotNum, ac.id)
			end
			MockData.LoadSkillData(unitId)
			buildSkillsContent()
		end)
	end

	local cancel = Instance.new("TextButton")
	cancel.Size = UDim2.new(1, 0, 0, 18)
	cancel.Position = UDim2.new(0, 0, 1, -20)
	cancel.BackgroundTransparency = 1
	cancel.Font = Theme.Font.Primary
	cancel.TextSize = Theme.Text.Small()
	cancel.TextColor3 = Theme.Colors.TextSecondary
	cancel.Text = "Cancel"
	cancel.Parent = popup
	cancel.MouseButton1Click:Connect(closeDetail)
end

-- openAugmentSlotPicker: Show all 10 augment slots to choose from
-- ==================================================================
openAugmentSlotPicker = function(aug)
	closeDetail()
	local unit = MockData.GetSelectedUnit()
	if not unit then return end
	local loadout = MockData.GetSkillLoadout(unit.id)

	detailOverlay = Instance.new("ScreenGui")
	detailOverlay.Name = "AugSlotPickerOverlay"
	detailOverlay.DisplayOrder = 115
	detailOverlay.ResetOnSpawn = false
	detailOverlay.Parent = getPlayerGui()

	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.Overlay
	backdrop.BackgroundTransparency = 0.5
	backdrop.Text = ""
	backdrop.BorderSizePixel = 0
	backdrop.Parent = detailOverlay
	backdrop.MouseButton1Click:Connect(closeDetail)

	local popup = Theme.MakePanel("AugSlotPicker",
		UDim2.new(0, 320, 0, 360),
		UDim2.new(0.5, 0, 0.5, 0),
		Vector2.new(0.5, 0.5),
		detailOverlay)
	popup.ClipsDescendants = true
	pad(popup, 10, 10, 10, 10)

	makeLabel(popup, { Text = "[o] Attach " .. (aug.name or "?") .. " to:",
		Size = UDim2.new(1, 0, 0, 18),
		Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Body(),
		TextColor3 = Theme.Colors.TextGold })

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, 0, 1, -44)
	scroll.Position = UDim2.new(0, 0, 0, 22)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 3
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = popup

	local sLayout = Instance.new("UIListLayout", scroll)
	sLayout.Padding = UDim.new(0, 3)
	sLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local rowOrder = 0

	for slot = 1, 5 do
		local sd = type(loadout) == "table" and loadout[slot]
		local skillName = nil
		local augments = {}
		local disabled = (slot == 5)

		if sd then
			if type(sd) == "table" then
				skillName = sd.skillName
				if skillName == "none" then skillName = nil end
				augments = sd.augments or {}
			else
				local ms = MockData.GetSkill(sd) or MockData.GetSkillDef(sd)
				if ms then skillName = ms.name end
			end
		end

		if not skillName and slot ~= 5 then
			disabled = true -- no skill in slot = can't attach augment
		end

		for augSlot = 1, 2 do
			local existingAug = augments[augSlot]
			local existingDef = existingAug and MockData.GetAugmentDef(existingAug)

			local rowBtn = Instance.new("TextButton")
			rowBtn.Size = UDim2.new(1, 0, 0, 26)
			rowBtn.BackgroundColor3 = Theme.Colors.PanelRaised
			rowBtn.BackgroundTransparency = disabled and 0.6 or 0.2
			rowBtn.BorderSizePixel = 0
			rowBtn.Text = ""
			rowBtn.AutoButtonColor = not disabled
			rowBtn.LayoutOrder = rowOrder
			rowBtn.Parent = scroll
			Instance.new("UICorner", rowBtn).CornerRadius = UDim.new(0, 4)

			local slotLabel = "Slot " .. slot .. "  |  Aug " .. augSlot
			local occLabel = "Empty"
			if disabled and slot == 5 then
				occLabel = "Locked"
			elseif disabled then
				occLabel = "No skill equipped"
			elseif existingDef then
				occLabel = "Replace: " .. existingDef.name
			end

			makeLabel(rowBtn, { Text = slotLabel,
				Size = UDim2.new(0.35, 0, 1, 0),
				Position = UDim2.new(0, 6, 0, 0),
				Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Tiny(),
				TextColor3 = disabled and Theme.Colors.TextDisabled or Theme.Colors.TextPrimary })
			makeLabel(rowBtn, { Text = skillName or (slot == 5 and "Locked" or "-"),
				Size = UDim2.new(0.25, 0, 1, 0),
				Position = UDim2.new(0.35, 0, 0, 0),
				TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextSecondary })
			makeLabel(rowBtn, { Text = occLabel,
				Size = UDim2.new(0.35, -6, 1, 0),
				Position = UDim2.new(0.62, 0, 0, 0),
				TextSize = Theme.Text.Badge(), TextColor3 = disabled and Theme.Colors.TextDisabled or Theme.Colors.Warning,
				TextXAlignment = Enum.TextXAlignment.Right })

			if not disabled then
				local cSlot, cAug = slot, augSlot
				rowBtn.MouseButton1Click:Connect(function()
					closeDetail()
					if MockData.ServerAttachAugment then
						MockData.ServerAttachAugment(unit.id, cSlot, cAug, aug.id)
					end
					MockData.LoadSkillData(unit.id)
					buildSkillsContent()
				end)
			end

			rowOrder = rowOrder + 1
		end
	end

	local cancel = Instance.new("TextButton")
	cancel.Size = UDim2.new(1, 0, 0, 18)
	cancel.Position = UDim2.new(0, 0, 1, -20)
	cancel.BackgroundTransparency = 1
	cancel.Font = Theme.Font.Primary
	cancel.TextSize = Theme.Text.Small()
	cancel.TextColor3 = Theme.Colors.TextSecondary
	cancel.Text = "Cancel"
	cancel.Parent = popup
	cancel.MouseButton1Click:Connect(closeDetail)
end

-- ==================================================================
-- openEquippedSkillDetail: Detail for an equipped skill slot
-- ==================================================================
openEquippedSkillDetail = function(slotNum, skillId, augments)
	closeDetail()
	local unit = MockData.GetSelectedUnit()
	if not unit then return end

	local def = MockData.GetSkillDef(skillId)
	local mockSkill = MockData.GetSkill(skillId)
	local tags = (def and def.tags) or (mockSkill and mockSkill.tags) or {}
	local name = (def and def.name) or (mockSkill and mockSkill.name) or skillId or "?"
	local stype = getSkillType(tags)
	local stc = STYPE_COLORS[stype] or STYPE_COLORS.Utility

	-- Build the same skill detail panel as openSkillCardDetail
	-- but with UNEQUIP instead of EQUIP, and show equipped augments
	local fakeCard = {
		id = skillId, name = name, tags = tags, def = def, mockSkill = mockSkill,
		mpCost = def and def.mpCostFormula or (mockSkill and mockSkill.mpCost) or 0,
		rtCost = def and def.rtCostFormula or (mockSkill and mockSkill.rtCost) or 0,
		qty = 1, isSkill = true,
	}

	-- Reuse skill detail overlay code via a flag
	-- For simplicity, build a simpler equipped view
	detailOverlay = Instance.new("ScreenGui")
	detailOverlay.Name = "EquippedSkillDetail"
	detailOverlay.DisplayOrder = 110
	detailOverlay.ResetOnSpawn = false
	detailOverlay.Parent = getPlayerGui()

	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.Overlay
	backdrop.BackgroundTransparency = 0.4
	backdrop.Text = ""
	backdrop.BorderSizePixel = 0
	backdrop.Parent = detailOverlay
	backdrop.MouseButton1Click:Connect(closeDetail)

	local panel = Theme.MakePanel("EquippedSkillPanel",
		UDim2.new(0.55, 0, 0.90, 0),
		UDim2.new(0, 6, 0.5, 0),
		Vector2.new(0, 0.5), detailOverlay)
	panel.ClipsDescendants = true

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -16, 1, -8)
	scroll.Position = UDim2.new(0, 8, 0, 4)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 3
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel

	local layout = Instance.new("UIListLayout", scroll)
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	local order = 0
	local function addRow(parent, height)
		local f = Instance.new("Frame")
		f.Size = UDim2.new(1, 0, 0, height)
		f.BackgroundTransparency = 1
		f.LayoutOrder = order
		f.Parent = parent
		order = order + 1
		return f
	end

	-- Unified header
	local eqDescText = (def and def.description) or buildSkillDescription(def)
	local hdrH = buildDetailHeader(addRow(scroll, 72), {
		iconText = STYPE_ICONS[stype] or "[*]",
		iconImage = def and def.icon or nil,
		iconBg = stc.bg,
		iconColor = stc.icon,
		iconStrokeColor = stc.icon,
		name = name,
		tags = tags,
		description = eqDescText or "",
	})
	local slotRow = addRow(scroll, 14)
	makeLabel(slotRow, { Text = "Equipped in Slot " .. slotNum,
		Size = UDim2.fromScale(1, 1),
		TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.Info })

	-- Stats (abbreviated)
	if def then
		local function addSR(l, v)
			local r = addRow(scroll, 14)
			makeLabel(r, { Text = l, Size = UDim2.new(0.3, 0, 1, 0), TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextSecondary })
			makeLabel(r, { Text = v, Size = UDim2.new(0.7, -4, 1, 0), Position = UDim2.new(0.3, 4, 0, 0),
				TextSize = Theme.Text.Small(), Font = Theme.Font.Mono, TextColor3 = Theme.Colors.TextPrimary,
				TextXAlignment = Enum.TextXAlignment.Right })
		end
		addSR("MP Cost", def.mpCostFormula or "-")
		addSR("RT Cost", def.rtCostFormula or "-")
		addSR("Pattern", simplifyPattern(def.pattern))
	end

	-- Attached augments
	local augHdr = addRow(scroll, 14)
	makeLabel(augHdr, { Text = "ATTACHED AUGMENTS", Size = UDim2.fromScale(1, 1),
		Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Tiny(),
		TextColor3 = Theme.Colors.TextGold })

	for a = 1, 2 do
		local augId = augments and augments[a]
		local augDef = augId and MockData.GetAugmentDef(augId)
		if augDef then
			local ar = addRow(scroll, 26)
			ar.BackgroundColor3 = Theme.Colors.PanelRaised
			ar.BackgroundTransparency = 0.2
			Instance.new("UICorner", ar).CornerRadius = UDim.new(0, 4)

			makeLabel(ar, { Text = "[o] " .. augDef.name,
				Size = UDim2.new(0.6, -4, 1, 0),
				Position = UDim2.new(0, 4, 0, 0),
				TextSize = Theme.Text.Small(), Font = Theme.Font.PrimaryBold,
				TextColor3 = Theme.Colors.TextGold })
			makeLabel(ar, { Text = augDef.costFormula or "",
				Size = UDim2.new(0.35, 0, 1, 0),
				Position = UDim2.new(0.62, 0, 0, 0),
				TextSize = Theme.Text.Tiny(), Font = Theme.Font.Mono,
				TextColor3 = Theme.Colors.Danger,
				TextXAlignment = Enum.TextXAlignment.Right })
		else
			local ar = addRow(scroll, 22)
			ar.BackgroundColor3 = Theme.Colors.PanelRaised
			ar.BackgroundTransparency = 0.5
			Instance.new("UICorner", ar).CornerRadius = UDim.new(0, 4)
			makeLabel(ar, { Text = "[o] Empty Augment Slot " .. a,
				Size = UDim2.new(1, -8, 1, 0),
				Position = UDim2.new(0, 4, 0, 0),
				TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextDisabled })
		end
	end

	-- Buttons
	local fb = Theme.FooterBar
	local btnBar = Instance.new("Frame")
	btnBar.Name = "BtnBar"
	btnBar.BackgroundTransparency = 1
	btnBar.AnchorPoint = Vector2.new(1, 1)
	btnBar.Position = UDim2.new(1, -fb.PAD, 1, -fb.PAD)
	btnBar.Parent = detailOverlay
	local bLayout = Instance.new("UIListLayout")
	bLayout.FillDirection = Enum.FillDirection.Horizontal
	bLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	bLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	bLayout.Padding = UDim.new(0, fb.BTN_GAP)
	bLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bLayout.Parent = btnBar
	local btnOrder = 0
	local function addBtn(text, color, onClick)
		local style = "Secondary"
		if color == Theme.Colors.Success or color == Theme.Colors.Danger then
			style = "Primary"
		elseif color == Theme.Colors.Surface then
			if text == "COMPARE" or text == "DETAILS" or text == "SWAP" then
				style = "Tertiary"
			end
		end
		local btn = Theme.MakeButton(btnBar, text, style, onClick, {
			size = UDim2.new(0, fb.BTN_W, 0, fb.BTN_H),
		})
		btn.LayoutOrder = btnOrder
		btnOrder = btnOrder + 1
	end

	-- UNEQUIP: also detaches all augments
	addBtn("UNEQUIP", Theme.Colors.Danger, function()
		closeDetail()
		-- Detach augments first
		for a = 1, 2 do
			if augments and augments[a] then
				if MockData.ServerDetachAugment then
					MockData.ServerDetachAugment(unit.id, slotNum, a)
				end
			end
		end
		-- Then unequip
		if MockData.ServerUnequipSkillCard then
			MockData.ServerUnequipSkillCard(unit.id, slotNum)
		else
			local sl = MockData.SkillLoadout[unit.id]
			if sl then sl[slotNum] = nil end
		end
		MockData.LoadSkillData(unit.id)
		buildSkillsContent()
	end)

	addBtn("BACK", Theme.Colors.Surface, closeDetail)
	btnBar.Size = UDim2.new(0, (btnOrder * fb.BTN_W) + ((btnOrder - 1) * fb.BTN_GAP), 0, fb.BTN_H)
end

-- ==================================================================
-- openEquippedAugmentDetail: Detail for an attached augment
-- ==================================================================
openEquippedAugmentDetail = function(slotNum, augSlotNum, augmentId)
	closeDetail()
	local unit = MockData.GetSelectedUnit()
	if not unit then return end

	local def = MockData.GetAugmentDef(augmentId)
	local name = def and def.name or augmentId or "?"

	detailOverlay = Instance.new("ScreenGui")
	detailOverlay.Name = "EquippedAugDetail"
	detailOverlay.DisplayOrder = 110
	detailOverlay.ResetOnSpawn = false
	detailOverlay.Parent = getPlayerGui()

	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.Overlay
	backdrop.BackgroundTransparency = 0.4
	backdrop.Text = ""
	backdrop.BorderSizePixel = 0
	backdrop.Parent = detailOverlay
	backdrop.MouseButton1Click:Connect(closeDetail)

	local panel = Theme.MakePanel("EquippedAugPanel",
		UDim2.new(0.55, 0, 0.70, 0),
		UDim2.new(0, 6, 0.5, 0),
		Vector2.new(0, 0.5), detailOverlay)
	panel.ClipsDescendants = true
	pad(panel, 10, 10, 10, 10)

	-- Unified header
	local eqAugTags = {}
	if def and def.family then table.insert(eqAugTags, def.family) end
	local eqAugDesc = (def and def.description) or (def and def.effect) or ""
	local eqAugDef = MockData.GetAugmentDef(augId)
	local nextY = buildDetailHeader(panel, {
		iconText = "[o]",
		iconImage = eqAugDef and eqAugDef.icon or nil,
		iconBg = Color3.fromRGB(74, 53, 16),
		iconColor = Theme.Colors.TextGold,
		iconStrokeColor = Theme.Colors.TextGold,
		name = name,
		tags = eqAugTags,
		description = eqAugDesc,
	})
	makeLabel(panel, { Text = "Slot " .. slotNum .. "  |  Augment " .. augSlotNum,
		Size = UDim2.new(1, 0, 0, 12),
		Position = UDim2.new(0, 0, 0, nextY),
		TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.Info })

	-- Cost
	if def and def.costFormula then
		makeLabel(panel, { Text = "Cost: " .. def.costFormula,
			Size = UDim2.new(1, 0, 0, 14),
			Position = UDim2.new(0, 0, 0, 88),
			TextSize = Theme.Text.Body(), Font = Theme.Font.Mono,
			TextColor3 = Theme.Colors.Danger })
	end

	-- Buttons
	local fb = Theme.FooterBar
	local btnBar = Instance.new("Frame")
	btnBar.Name = "BtnBar"
	btnBar.BackgroundTransparency = 1
	btnBar.AnchorPoint = Vector2.new(1, 1)
	btnBar.Position = UDim2.new(1, -fb.PAD, 1, -fb.PAD)
	btnBar.Parent = detailOverlay
	local bLayout = Instance.new("UIListLayout")
	bLayout.FillDirection = Enum.FillDirection.Horizontal
	bLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	bLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	bLayout.Padding = UDim.new(0, fb.BTN_GAP)
	bLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bLayout.Parent = btnBar
	local btnOrder = 0
	local function addBtn(text, color, onClick)
		local style = "Secondary"
		if color == Theme.Colors.Success or color == Theme.Colors.Danger then
			style = "Primary"
		elseif color == Theme.Colors.Surface then
			if text == "COMPARE" or text == "DETAILS" or text == "SWAP" then
				style = "Tertiary"
			end
		end
		local btn = Theme.MakeButton(btnBar, text, style, onClick, {
			size = UDim2.new(0, fb.BTN_W, 0, fb.BTN_H),
		})
		btn.LayoutOrder = btnOrder
		btnOrder = btnOrder + 1
	end

	addBtn("DETACH", Theme.Colors.Danger, function()
		closeDetail()
		if MockData.ServerDetachAugment then
			MockData.ServerDetachAugment(unit.id, slotNum, augSlotNum)
		end
		MockData.LoadSkillData(unit.id)
		buildSkillsContent()
	end)
	addBtn("BACK", Theme.Colors.Surface, closeDetail)
	btnBar.Size = UDim2.new(0, (btnOrder * fb.BTN_W) + ((btnOrder - 1) * fb.BTN_GAP), 0, fb.BTN_H)
end


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

local consFilter = "All"
local consSearch = ""

buildConsumableGrid = function()
	if not inventoryPanel then return end
	clearChildren(inventoryPanel)
	pad(inventoryPanel, 8, 8, 8, 8)
	local ctrlRow = Instance.new("Frame")
	ctrlRow.Size = UDim2.new(1, 0, 0, 24)
	ctrlRow.Position = UDim2.new(0, 0, 0, 0)
	ctrlRow.BackgroundTransparency = 1
	ctrlRow.Parent = inventoryPanel
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
	catBtn.MouseButton1Click:Connect(function()
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
		if def then
			local cat = def.category or "?"
			if consFilter ~= "All" and cat ~= consFilter then continue end
			if consSearch ~= "" and not string.find(string.lower(def.name or ""), string.lower(consSearch), 1, true) then continue end
			table.insert(items, { id = cid, name = def.name or cid, category = cat,
				maxCharges = def.maxCharges or 1, tier = def.tier or "Common",
				rtCost = def.rtCost or 0, range = def.range or 0,
				targetRules = def.targetRules or "", pattern = def.pattern or "",
				effectFormula = def.effectFormula or "", icon = def.icon or nil,
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
	scrollFrame.Parent = inventoryPanel
	local containerW = scrollFrame.AbsoluteSize.X
	if containerW < 10 then containerW = 400 end
	local containerH = scrollFrame.AbsoluteSize.Y
	if containerH < 10 then containerH = 200 end
	local GAP = 3
	local maxCellH = math.floor((containerH - 2 * GAP) / 3)
	local cellW = math.clamp(math.floor(maxCellH / 1.2), 48, 96)
	local cellH = math.floor(cellW * 1.2)
	local gridLayout = Instance.new("UIGridLayout", scrollFrame)
	gridLayout.CellSize = UDim2.new(0, cellW, 0, cellH)
	gridLayout.CellPadding = UDim2.new(0, GAP, 0, GAP)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	for idx, ci in ipairs(items) do
		local catColor = CONS_CATEGORY_COLORS[ci.category] or Theme.Colors.TextSecondary
		local tile = Instance.new("TextButton")
		tile.BackgroundColor3 = catColor
		tile.BackgroundTransparency = 0.75
		tile.BorderSizePixel = 0; tile.Text = ""
		tile.AutoButtonColor = true; tile.LayoutOrder = idx
		tile.Parent = scrollFrame
		Instance.new("UICorner", tile).CornerRadius = UDim.new(0, 4)
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 3, 1, 0)
		stripe.BackgroundColor3 = catColor; stripe.BorderSizePixel = 0
		stripe.Parent = tile
		local qtyFrame = Instance.new("Frame")
		qtyFrame.Size = UDim2.new(0, 22, 0, 12)
		qtyFrame.Position = UDim2.new(1, -24, 0, 2)
		qtyFrame.BackgroundColor3 = Theme.Colors.BadgeBg
		qtyFrame.BackgroundTransparency = 0.4; qtyFrame.BorderSizePixel = 0
		qtyFrame.ZIndex = 3; qtyFrame.Parent = tile
		Instance.new("UICorner", qtyFrame).CornerRadius = UDim.new(0, 3)
		local qtyLabel = makeLabel(qtyFrame, { Text = "x" .. ci.maxCharges,
			Size = UDim2.fromScale(1, 1), TextSize = Theme.Text.Badge(), Font = Theme.Font.Mono,
			TextColor3 = Theme.Colors.TextPrimary, TextXAlignment = Enum.TextXAlignment.Center })
		if qtyLabel then qtyLabel.ZIndex = 3 end
		local nameStrip = Instance.new("Frame")
		nameStrip.Size = UDim2.new(1, 0, 0, 14)
		nameStrip.Position = UDim2.new(0, 0, 1, -14)
		nameStrip.BackgroundColor3 = Color3.new(0, 0, 0)
		nameStrip.BackgroundTransparency = 0.4; nameStrip.BorderSizePixel = 0
		nameStrip.ZIndex = 3; nameStrip.Parent = tile
		local nameLabel = makeLabel(nameStrip, { Text = ci.name,
			Size = UDim2.fromScale(1, 1), Position = UDim2.new(0, 4, 0, 0),
			TextSize = Theme.Text.Tiny(), Font = Theme.Font.Primary,
			TextColor3 = catColor, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd })
		if nameLabel then nameLabel.ZIndex = 3 end
		tile.MouseButton1Click:Connect(function() openConsumableDetail(ci) end)
	end
	makeLabel(inventoryPanel, { Text = string.format("Showing: %d / %d", #items, #allIds),
		Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -14),
		TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextDisabled,
		TextXAlignment = Enum.TextXAlignment.Left })
end

openConsumableDetail = function(ci)
	closeDetail()
	local unit = MockData.GetSelectedUnit()
	if not unit then return end
	detailOverlay = Instance.new("ScreenGui")
	detailOverlay.Name = "ConsDetail"; detailOverlay.DisplayOrder = 110
	detailOverlay.ResetOnSpawn = false; detailOverlay.Parent = getPlayerGui()
	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.Overlay; backdrop.BackgroundTransparency = 0.5
	backdrop.Text = ""; backdrop.BorderSizePixel = 0
	backdrop.Parent = detailOverlay; backdrop.MouseButton1Click:Connect(closeDetail)
	local panel = Theme.MakePanel("ConsDetail", UDim2.new(0.55, 0, 0.9, 0),
		UDim2.new(0, 8, 0.05, 0), Vector2.new(0, 0), detailOverlay)
	panel.ClipsDescendants = true; pad(panel, 10, 10, 10, 10)
	local catColor = CONS_CATEGORY_COLORS[ci.category] or Theme.Colors.TextSecondary
	buildDetailHeader(panel, { iconText = "[C]", name = ci.name,
		subtitleText = ci.category .. " | " .. ci.economy .. " | " .. ci.profile,
		subtitleColor = catColor, tags = ci.tags, tagColor = catColor,
		description = ci.effectFormula })
	local yOff = 100
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
	local fb = Theme.FooterBar
	local btnBar = Instance.new("Frame"); btnBar.Name = "ConsBtnBar"
	btnBar.Size = UDim2.new(0, fb.BTN_W * 2 + fb.BTN_GAP + fb.PAD, 0, fb.BTN_H)
	btnBar.Position = UDim2.new(1, -fb.PAD, 1, -fb.PAD); btnBar.AnchorPoint = Vector2.new(1, 1)
	btnBar.BackgroundTransparency = 1; btnBar.Parent = detailOverlay
	local btnLayout = Instance.new("UIListLayout", btnBar)
	btnLayout.FillDirection = Enum.FillDirection.Horizontal
	btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	btnLayout.Padding = UDim.new(0, fb.BTN_GAP)
	local backBtn = Theme.MakeButton(btnBar, "BACK", "Secondary"); backBtn.LayoutOrder = 2
	backBtn.MouseButton1Click:Connect(closeDetail)
	local equipBtn = Theme.MakeButton(btnBar, "EQUIP", "Primary"); equipBtn.LayoutOrder = 1
	equipBtn.MouseButton1Click:Connect(function() closeDetail(); openConsumableSlotPicker(unit.id, ci) end)
end

openConsumableSlotPicker = function(unitId, ci)
	closeDetail()
	local unit = MockData.GetSelectedUnit()
	if not unit then return end
	detailOverlay = Instance.new("ScreenGui"); detailOverlay.Name = "ConsSlotPicker"
	detailOverlay.DisplayOrder = 115; detailOverlay.ResetOnSpawn = false
	detailOverlay.Parent = getPlayerGui()
	local backdrop = Instance.new("TextButton"); backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.Overlay; backdrop.BackgroundTransparency = 0.5
	backdrop.Text = ""; backdrop.BorderSizePixel = 0; backdrop.Parent = detailOverlay
	backdrop.MouseButton1Click:Connect(closeDetail)
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
		local locked = MockData.ConsSlotLocked[slotKey]
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
		if not locked then
			rowBtn.MouseButton1Click:Connect(function()
				closeDetail()
				local result = BattleEvents.RequestEquipConsumable:InvokeServer(unitId, slotIdx, ci.id)
				if result and result.ok then
					if not MockData.Equipped[unitId] then MockData.Equipped[unitId] = {} end
					MockData.Equipped[unitId][slotKey] = { id = ci.id, consumableId = ci.id, name = ci.name,
						cat = "Consumable", sub = ci.category, icon = ci.icon or "[C]", qty = ci.maxCharges,
						effect = ci.effectFormula }
					buildEquippedLoadout()
				end
			end)
		end
	end
	local cancel = Instance.new("TextButton"); cancel.Size = UDim2.new(1, 0, 0, 18)
	cancel.Position = UDim2.new(0, 0, 1, -20); cancel.BackgroundTransparency = 1
	cancel.Font = Theme.Font.Primary; cancel.TextSize = Theme.Text.Small()
	cancel.TextColor3 = Theme.Colors.TextSecondary; cancel.Text = "Cancel"
	cancel.Parent = popup; cancel.MouseButton1Click:Connect(closeDetail)
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
		icon = (def and def.icon) or item.icon or nil,
		economy = (def and def.economy) or "", profile = (def and def.profile) or "",
		duration = (def and def.duration) or "Instant", scalingBasis = (def and def.scalingBasis) or "",
		tags = (def and def.tags) or {} }
	detailOverlay = Instance.new("ScreenGui"); detailOverlay.Name = "ConsEqDetail"
	detailOverlay.DisplayOrder = 110; detailOverlay.ResetOnSpawn = false
	detailOverlay.Parent = getPlayerGui()
	local backdrop = Instance.new("TextButton"); backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.Overlay; backdrop.BackgroundTransparency = 0.5
	backdrop.Text = ""; backdrop.BorderSizePixel = 0; backdrop.Parent = detailOverlay
	backdrop.MouseButton1Click:Connect(closeDetail)
	local catColor = CONS_CATEGORY_COLORS[ci.category] or Theme.Colors.TextSecondary
	local panel = Theme.MakePanel("ConsEqDetail", UDim2.new(0.55, 0, 0.9, 0),
		UDim2.new(0, 8, 0.05, 0), Vector2.new(0, 0), detailOverlay)
	panel.ClipsDescendants = true; pad(panel, 10, 10, 10, 10)
	buildDetailHeader(panel, { iconText = "[C]", name = ci.name,
		subtitleText = "Slot " .. slotIdx .. " | " .. ci.category, subtitleColor = catColor,
		tags = ci.tags, tagColor = catColor, description = ci.effectFormula })
	local yOff = 100
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
	backBtn.MouseButton1Click:Connect(closeDetail)
	local unBtn = Theme.MakeButton(btnBar, "UNEQUIP", "Primary"); unBtn.LayoutOrder = 1
	unBtn.MouseButton1Click:Connect(function()
		closeDetail()
		local result = BattleEvents.RequestUnequipConsumable:InvokeServer(unitId, slotIdx)
		if result and result.ok then
			if MockData.Equipped[unitId] then MockData.Equipped[unitId]["Cons" .. slotIdx] = nil end
			buildEquippedLoadout()
		end
	end)
end

-- STAT PANEL (right column, below unit header — always visible)
--------------------------------------------------

buildStatPanel = function()
	if not statPanel then return end
	clearChildren(statPanel)
	pad(statPanel, 6, 8, 8, 6)

	local unit = MockData.GetSelectedUnit()
	if not unit then return end

	-- Fetch stats from server
	local ok, statsData = pcall(function()
		return BattleEvents.GetUnitFullStats:InvokeServer(unit.id)
	end)
	if not ok or not statsData or not statsData.ok then
		statsData = { baseStats = {}, effectiveStats = {}, unallocatedPoints = 0 }
	end

	local layout = Instance.new("UIListLayout", statPanel)
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	-- Header with allocation points
	local pts = statsData.unallocatedPoints or 0
	local hdrText = pts > 0 and ("STATS  [" .. pts .. " pts]") or "STATS"
	local hdr = Instance.new("TextLabel")
	hdr.Size = UDim2.new(1, 0, 0, 16); hdr.BackgroundTransparency = 0.3
	hdr.BackgroundColor3 = Theme.Colors.PanelRaised; hdr.BorderSizePixel = 0
	hdr.Font = Theme.Font.PrimaryBold; hdr.TextSize = Theme.Text.Small()
	hdr.TextColor3 = pts > 0 and Theme.Colors.TextGold or Theme.Colors.TextSecondary
	hdr.TextXAlignment = Enum.TextXAlignment.Left
	hdr.Text = "  " .. hdrText; hdr.LayoutOrder = 0; hdr.Parent = statPanel

	local STAT_ORDER = {"STR", "AGI", "INT", "VIT", "DEX", "LUK"}
	local base = statsData.baseStats or {}
	local eff = statsData.effectiveStats or {}

	for si, stat in ipairs(STAT_ORDER) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 20); row.BackgroundTransparency = 1
		row.BorderSizePixel = 0; row.LayoutOrder = si; row.Parent = statPanel

		local statLbl = Instance.new("TextLabel")
		statLbl.Size = UDim2.new(0, 36, 1, 0); statLbl.BackgroundTransparency = 1
		statLbl.Font = Theme.Font.PrimaryBold; statLbl.TextSize = Theme.Text.Small()
		statLbl.TextColor3 = Theme.Colors.TextPrimary
		statLbl.TextXAlignment = Enum.TextXAlignment.Left
		statLbl.Text = " " .. stat; statLbl.Parent = row

		local baseVal = base[stat] or 0
		local effVal = eff[stat] or 0
		local bonus = effVal - baseVal
		local bonusStr = bonus > 0 and (" (+" .. bonus .. ")") or (bonus < 0 and (" (" .. bonus .. ")") or "")

		local valLbl = Instance.new("TextLabel")
		valLbl.Size = UDim2.new(1, -72, 1, 0); valLbl.Position = UDim2.fromOffset(36, 0)
		valLbl.BackgroundTransparency = 1
		valLbl.Font = Theme.Font.Mono; valLbl.TextSize = Theme.Text.Small()
		valLbl.TextColor3 = Theme.Colors.TextPrimary
		valLbl.TextXAlignment = Enum.TextXAlignment.Left
		valLbl.Text = tostring(baseVal) .. bonusStr; valLbl.Parent = row

		if pts > 0 then
			local btn = Theme.MakeButton(row, "+", "Primary", nil, {
				size = UDim2.fromOffset(24, 18),
				position = UDim2.new(1, -28, 0, 1),
			})
			btn.MouseButton1Click:Connect(function()
				local result = BattleEvents.RequestAllocateStat:InvokeServer(unit.id, stat)
				if result and result.ok then
					buildStatPanel() -- refresh after allocation
				end
			end)
		end
	end
end

-- INFO TAB CONTENT (placeholder)
--------------------------------------------------

buildInfoContent = function()
	if not infoPanel then return end
	clearChildren(infoPanel)

	local unit = MockData.GetSelectedUnit()
	if not unit then return end

	-- Fetch full stats from server
	local ok2, statsData = pcall(function()
		return BattleEvents.GetUnitFullStats:InvokeServer(unit.id)
	end)
	if not ok2 or not statsData or not statsData.ok then
		makeLabel(infoPanel, { Text = "Failed to load unit stats.",
			Size = UDim2.new(1, 0, 0, 30), TextColor3 = Theme.Colors.Danger,
			TextSize = Theme.Text.Body() })
		return
	end

	-- =============================================
	-- LEFT COLUMN: Identity + Passives (scrollable)
	-- =============================================
	local leftCol = Instance.new("ScrollingFrame")
	leftCol.Name = "InfoLeft"
	leftCol.Size = UDim2.new(0.50, -2, 1, 0)
	leftCol.Position = UDim2.new(0, 0, 0, 0)
	leftCol.BackgroundTransparency = 1; leftCol.BorderSizePixel = 0
	leftCol.ScrollBarThickness = 3
	leftCol.ScrollBarImageColor3 = Theme.Colors.Surface
	leftCol.CanvasSize = UDim2.new(0, 0, 0, 0)
	leftCol.AutomaticCanvasSize = Enum.AutomaticSize.Y
	leftCol.Parent = infoPanel

	local leftLayout = Instance.new("UIListLayout", leftCol)
	leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
	leftLayout.Padding = UDim.new(0, 4)
	local leftPad = Instance.new("UIPadding", leftCol)
	leftPad.PaddingTop = UDim.new(0, 8); leftPad.PaddingLeft = UDim.new(0, 8)
	leftPad.PaddingRight = UDim.new(0, 4); leftPad.PaddingBottom = UDim.new(0, 12)

	local lOrder = 0
	local function nextL() lOrder = lOrder + 1; return lOrder end

	local function sectionHeader(parent, text, orderFn)
		local hdr = Instance.new("TextLabel")
		hdr.Size = UDim2.new(1, 0, 0, 20)
		hdr.BackgroundColor3 = Theme.Colors.PanelRaised
		hdr.BackgroundTransparency = 0.3
		hdr.Font = Theme.Font.PrimaryBold; hdr.TextSize = Theme.Text.Body()
		hdr.TextColor3 = Theme.Colors.TextSecondary
		hdr.TextXAlignment = Enum.TextXAlignment.Left
		hdr.Text = "  " .. text; hdr.BorderSizePixel = 0
		hdr.LayoutOrder = orderFn(); hdr.Parent = parent
		Instance.new("UIPadding", hdr).PaddingLeft = UDim.new(0, 4)
	end

	local function infoRow(parent, label, value, color, orderFn)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 16)
		row.BackgroundTransparency = 1; row.BorderSizePixel = 0
		row.LayoutOrder = orderFn(); row.Parent = parent
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(0.55, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Font = Theme.Font.Primary; lbl.TextSize = Theme.Text.Small()
		lbl.TextColor3 = Theme.Colors.TextSecondary
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Text = "  " .. label; lbl.Parent = row
		local val = Instance.new("TextLabel")
		val.Size = UDim2.new(0.45, 0, 1, 0)
		val.Position = UDim2.new(0.55, 0, 0, 0)
		val.BackgroundTransparency = 1
		val.Font = Theme.Font.Mono; val.TextSize = Theme.Text.Small()
		val.TextColor3 = color or Theme.Colors.TextPrimary
		val.TextXAlignment = Enum.TextXAlignment.Left
		val.Text = tostring(value); val.Parent = row
	end

	local function descLabel(parent, text, orderFn)
		local d = Instance.new("TextLabel")
		d.Size = UDim2.new(1, 0, 0, 28); d.BackgroundTransparency = 1
		d.Font = Theme.Font.Primary; d.TextSize = Theme.Text.Small()
		d.TextColor3 = Theme.Colors.TextSecondary
		d.TextXAlignment = Enum.TextXAlignment.Left; d.TextWrapped = true
		d.Text = "  " .. text; d.BorderSizePixel = 0
		d.LayoutOrder = orderFn(); d.Parent = parent
	end

	-- Unit identity row
	local identityRow = Instance.new("Frame")
	identityRow.Size = UDim2.new(1, 0, 0, 130)
	identityRow.BackgroundTransparency = 1; identityRow.BorderSizePixel = 0
	identityRow.LayoutOrder = nextL(); identityRow.Parent = leftCol

	local portrait = Instance.new("Frame")
	portrait.Size = UDim2.fromOffset(120, 120)
	portrait.Position = UDim2.fromOffset(0, 4)
	portrait.BackgroundColor3 = Theme.Colors.Player
	portrait.BackgroundTransparency = 0.2; portrait.BorderSizePixel = 0
	portrait.Parent = identityRow
	Instance.new("UICorner", portrait).CornerRadius = Theme.CornerRadius.md
	local pStroke = Instance.new("UIStroke", portrait)
	pStroke.Color = Theme.Colors.TextGold; pStroke.Thickness = 2
	local pLabel = Instance.new("TextLabel")
	pLabel.Size = UDim2.fromScale(1, 1); pLabel.BackgroundTransparency = 1
	pLabel.Font = Theme.Font.PrimaryBold; pLabel.TextSize = 40
	pLabel.TextColor3 = Theme.Colors.TextPrimary
	pLabel.Text = string.sub(statsData.name or "?", 1, 2)
	pLabel.Parent = portrait
	local lvBadge = Instance.new("Frame")
	lvBadge.Size = UDim2.fromOffset(28, 16); lvBadge.Position = UDim2.fromOffset(0, 0)
	lvBadge.BackgroundColor3 = Theme.Colors.BadgeBg; lvBadge.BorderSizePixel = 0
	lvBadge.ZIndex = 3; lvBadge.Parent = portrait
	Instance.new("UICorner", lvBadge).CornerRadius = UDim.new(0, 3)
	local lvLbl = Instance.new("TextLabel")
	lvLbl.Size = UDim2.fromScale(1, 1); lvLbl.BackgroundTransparency = 1
	lvLbl.Font = Theme.Font.PrimaryBold; lvLbl.TextSize = Theme.Text.Badge()
	lvLbl.TextColor3 = Theme.Colors.TextPrimary; lvLbl.ZIndex = 3
	lvLbl.Text = "Lv" .. (statsData.level or 1); lvLbl.Parent = lvBadge

	local textX = 130
	local function identityLabel(text, yPos, font, size, color)
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, -textX, 0, 18)
		l.Position = UDim2.fromOffset(textX, yPos)
		l.BackgroundTransparency = 1
		l.Font = font or Theme.Font.Primary; l.TextSize = size or Theme.Text.Body()
		l.TextColor3 = color or Theme.Colors.TextPrimary
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Text = text; l.Parent = identityRow
	end

	identityLabel(statsData.name or "Unit", 4, Theme.Font.PrimaryBold, Theme.Text.Heading(), Theme.Colors.Player)
	identityLabel(statsData.raceName or "Unknown Race", 26, nil, Theme.Text.Body(), Theme.Colors.TextSecondary)
	identityLabel(statsData.doctrineName or "No Doctrine", 44, nil, Theme.Text.Body(), Theme.Colors.Info)
	identityLabel(string.format("HP %d / %d    MP %d / %d",
		statsData.currentHp or 0, statsData.maxHp or 0,
		statsData.currentMp or 0, statsData.maxMp or 0),
		66, Theme.Font.Mono, Theme.Text.Body(), Theme.Colors.TextPrimary)

	-- Race passive
	if statsData.racePassiveName then
		sectionHeader(leftCol, "RACE PASSIVE", nextL)
		infoRow(leftCol, statsData.racePassiveName, "", Theme.Colors.RarityEpic, nextL)
		if statsData.racePassiveEffect then descLabel(leftCol, statsData.racePassiveEffect, nextL) end
	end

	-- Doctrine passive
	if statsData.doctrinePassiveName then
		sectionHeader(leftCol, "DOCTRINE PASSIVE", nextL)
		infoRow(leftCol, statsData.doctrinePassiveName, "", Theme.Colors.Info, nextL)
		if statsData.doctrinePassiveEffect then descLabel(leftCol, statsData.doctrinePassiveEffect, nextL) end
	end

	-- =============================================
	-- RIGHT COLUMN: Derived Stats (scrollable)
	-- =============================================
	local rightCol = Instance.new("ScrollingFrame")
	rightCol.Name = "InfoRight"
	rightCol.Size = UDim2.new(0.50, -2, 1, 0)
	rightCol.Position = UDim2.new(0.50, 2, 0, 0)
	rightCol.BackgroundTransparency = 1; rightCol.BorderSizePixel = 0
	rightCol.ScrollBarThickness = 3
	rightCol.ScrollBarImageColor3 = Theme.Colors.Surface
	rightCol.CanvasSize = UDim2.new(0, 0, 0, 0)
	rightCol.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rightCol.Parent = infoPanel

	local rightLayout = Instance.new("UIListLayout", rightCol)
	rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rightLayout.Padding = UDim.new(0, 3)
	local rightPad = Instance.new("UIPadding", rightCol)
	rightPad.PaddingTop = UDim.new(0, 8); rightPad.PaddingLeft = UDim.new(0, 4)
	rightPad.PaddingRight = UDim.new(0, 8); rightPad.PaddingBottom = UDim.new(0, 12)

	local rOrder = 0
	local function nextR() rOrder = rOrder + 1; return rOrder end

	local d = statsData.derivedStats or {}

	sectionHeader(rightCol, "COMBAT", nextR)
	infoRow(rightCol, "Attack Power", d.attackPower or 0, nil, nextR)
	infoRow(rightCol, "Effective WT", d.effectiveWt or 0, nil, nextR)
	infoRow(rightCol, "Precision", string.format("%.1f%%", (d.precision or 0) * 100), nil, nextR)
	infoRow(rightCol, "Evasiveness", string.format("%.1f%%", (d.evasiveness or 0) * 100), nil, nextR)
	infoRow(rightCol, "Basic Attack RT", d.basicAttackRt or 0, nil, nextR)

	sectionHeader(rightCol, "DEFENSE", nextR)
	infoRow(rightCol, "Defense Power", d.defensePower or 0, nil, nextR)
	infoRow(rightCol, "Debuff Resist", string.format("%.3fx", d.debuffResist or 1), nil, nextR)
	infoRow(rightCol, "RT Delay Resist", string.format("%.3fx", d.rtDelayResist or 1), nil, nextR)
	infoRow(rightCol, "Stability", d.stability or 0, nil, nextR)

	sectionHeader(rightCol, "RESOURCES", nextR)
	infoRow(rightCol, "Max HP", statsData.maxHp or 0, nil, nextR)
	infoRow(rightCol, "Max MP", statsData.maxMp or 0, nil, nextR)
	infoRow(rightCol, "MP Regen", d.mpRegen or 0, nil, nextR)

	sectionHeader(rightCol, "MOVEMENT", nextR)
	infoRow(rightCol, "Movement Range", d.movementRange or 0, nil, nextR)
	infoRow(rightCol, "Jump", d.jump or 0, nil, nextR)
	infoRow(rightCol, "Force", d.force or 0, nil, nextR)

	sectionHeader(rightCol, "SKILLS", nextR)
	infoRow(rightCol, "Skill Potency", string.format("%.3fx", d.skillPotency or 1), nil, nextR)
	infoRow(rightCol, "Bonus Skill Range", d.bonusSkillRange or 0, nil, nextR)
	infoRow(rightCol, "Channel Speed", string.format("%.1f%%", (d.channelReduction or 0) * 100), nil, nextR)
	infoRow(rightCol, "Heal Efficiency", string.format("%.3fx", d.healEfficiency or 1), nil, nextR)

	sectionHeader(rightCol, "OTHER", nextR)
	infoRow(rightCol, "Discovery Radius", d.discoveryRadius or 0, nil, nextR)
	infoRow(rightCol, "Unit Fortune", string.format("%.1f%%", (d.unitFortune or 0) * 100), nil, nextR)
	infoRow(rightCol, "Starting RT", d.startingRt or 0, nil, nextR)
end

-- SCREEN BUILD
--------------------------------------------------

function LoadoutScreen.Show()
	if screenGui and screenGui.Parent then return end

	-- Fetch real inventory from server (falls back to mock data on failure)
	MockData.LoadFromServer()

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

	-- Stat panel (below unit header — primary stats + allocation)
	local gap = Theme.FullScreen.PanelGap
	local statPanelH = 160
	statPanel = makePanel("StatPanel",
		UDim2.new(1, 0, 0, statPanelH),
		UDim2.new(0, 0, 0, 60 + gap), nil, rightCol)

	-- Equipped loadout (below stat panel)
	local topUsed = 60 + gap + statPanelH + gap
	equippedPanel = makePanel("EquippedLoadout",
		UDim2.new(1, 0, 1, -topUsed),
		UDim2.new(0, 0, 0, topUsed), nil, rightCol)

	-- LEFT COLUMN: Tab-specific panels (70% width, flush to left/top/bottom edges)
	-- Equipment tab: inventory
	inventoryPanel = makePanel("Inventory",
		UDim2.new(0.70, 0, 1, 0),
		UDim2.new(0, 0, 0, 0), nil, rootFrame)

	-- Skills tab: skill loadout
	skillsPanel = makePanel("SkillsPanel",
		UDim2.new(0.70, 0, 1, 0),
		UDim2.new(0, 0, 0, 0), nil, rootFrame)
	skillsPanel.Visible = false

	-- Info tab: unit info
	infoPanel = makePanel("InfoPanel",
		UDim2.new(0.70, 0, 1, 0),
		UDim2.new(0, 0, 0, 0), nil, rootFrame)
	infoPanel.Visible = false

	-- Show the correct tab
	currentTab = "EQUIPMENT"
	LoadoutScreen.Refresh()
end

function LoadoutScreen.Refresh()
	switchTab()
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
	skillsPanel = nil
	infoPanel = nil
end

function LoadoutScreen.Toggle()
	if screenGui and screenGui.Parent then
		LoadoutScreen.Hide()
	else
		LoadoutScreen.Show()
	end
end

return LoadoutScreen
