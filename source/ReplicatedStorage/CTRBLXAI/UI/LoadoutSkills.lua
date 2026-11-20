--!strict
-- LoadoutSkills.lua
-- CTRBLXAI | Loadout screen SKILLS tab: the skill / augment card grid (filters, sort, search)
-- in the left column. Text helpers come from LoadoutSkillUtil (shared, one definition).
-- Split out of LoadoutScreen.lua (2026-11-10, ARC-005 file-size split, step 5). Behaviour unchanged.
-- Host state (skills panel, the one open dropdown) is reached through `ctx`; the grid filter /
-- sort / search / selection state now lives here. No require of LoadoutScreen (no circular dependency).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CTRBLXAI_UI = ReplicatedStorage:WaitForChild("CTRBLXAI", 10):WaitForChild("UI", 10)
local MockData    = require(CTRBLXAI_UI:WaitForChild("MockLoadoutData", 10))
local Theme       = require(CTRBLXAI_UI:WaitForChild("Theme", 10))
local LoadoutSkillUtil = require(CTRBLXAI_UI:WaitForChild("LoadoutSkillUtil", 10))
local NumberFormat = require(CTRBLXAI_UI:WaitForChild("NumberFormat", 10)) -- no decimals (loadout_ui_spec 129)
local TipController: any = nil -- New-player tips (2026-11-19): guarded, a missing module never breaks this screen
do
	local okTip, tipMod = pcall(function() return (require :: any)(CTRBLXAI_UI:WaitForChild("TipController", 10)) end)
	if okTip then TipController = tipMod else warn("[LoadoutSkills] tips unavailable: " .. tostring(tipMod)) end
end

local LoadoutSkills: any = {}

local ctx: any = nil
-- Host helpers, bound in Init (thin wrappers so a later reassignment in the host is seen).
local function buildSkillLoadout(...) return ctx.buildSkillLoadout(...) end
local function clearChildren(...) return ctx.clearChildren(...) end
local function getPlayerGui(...) return ctx.getPlayerGui(...) end
local function makeLabel(...) return ctx.makeLabel(...) end
local function openAugmentCardDetail(...) return ctx.openAugmentCardDetail(...) end
local function openSkillCardDetail(...) return ctx.openSkillCardDetail(...) end
local function pad(...) return ctx.pad(...) end
local ELEM_COLORS = LoadoutSkillUtil.ELEM_COLORS
local STYPE_COLORS = LoadoutSkillUtil.STYPE_COLORS
local STYPE_ICONS = LoadoutSkillUtil.STYPE_ICONS
local getElement = LoadoutSkillUtil.GetElement
local getSkillType = LoadoutSkillUtil.GetSkillType

local buildSkillsContent

-- Skills tab state
local selectedSkillCardId = nil
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

-- SKILLS TAB v3: Grid Layout with Detail Overlays
-- Replaces lines 1843-2881 in LoadoutScreen.lua
-- =====================================================

-- ==================================================================
-- buildSkillsContent: Main Skills tab
-- Uses skillsPanel (left 70%) for card grid
-- Uses equippedPanel (right 30%) for skill loadout table
-- ==================================================================
buildSkillsContent = function()
	if not ctx.getSkillsPanel() then return end
	clearChildren(ctx.getSkillsPanel())
	pad(ctx.getSkillsPanel(), 8, 8, 8, 8)

	local unit = MockData.GetSelectedUnit()
	if not unit then return end

	-- Load skill data from server
	if MockData.LoadSkillData then
		MockData.LoadSkillData(unit.id)
	end

	local _loadout = MockData.GetSkillLoadout(unit.id)
	local _doctrineId = MockData.GetUnitDoctrineId(unit.id)

	-- ============================================================
	-- LEFT: CARD GRID (in skillsPanel)
	-- ============================================================

	-- Filter bar
	local ctrlRow = Instance.new("Frame")
	ctrlRow.Size = UDim2.new(1, 0, 0, 24)
	ctrlRow.Position = UDim2.new(0, 0, 0, 0)
	ctrlRow.BackgroundTransparency = 1
	ctrlRow.Parent = ctx.getSkillsPanel()

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
		if ctx.getActiveDropdown() then ctx.getActiveDropdown():Destroy(); ctx.setActiveDropdown(nil) end
	end

	local function showDD(anchorBtn, options, onSelect)
		closeDD()
		local rowH = 22
		local menuH = #options * rowH + 4
		local menuW = math.max(anchorBtn.AbsoluteSize.X, 80)

		ctx.setActiveDropdown(Instance.new("ScreenGui"))
		ctx.getActiveDropdown().Name = "SkillDropdown"
		ctx.getActiveDropdown().DisplayOrder = 105
		ctx.getActiveDropdown().ResetOnSpawn = false
		ctx.getActiveDropdown().Parent = getPlayerGui()

		local ddBack = Instance.new("TextButton")
		ddBack.Size = UDim2.fromScale(1, 1)
		ddBack.BackgroundTransparency = 1
		ddBack.Text = ""
		ddBack.Parent = ctx.getActiveDropdown()
		ddBack.Activated:Connect(closeDD)

		local mPanel = Instance.new("Frame")
		mPanel.Size = UDim2.new(0, menuW, 0, menuH)
		mPanel.Position = UDim2.new(0,
			anchorBtn.AbsolutePosition.X,
			0, anchorBtn.AbsolutePosition.Y + anchorBtn.AbsoluteSize.Y + 2)
		mPanel.BackgroundColor3 = Theme.Colors.Panel
		mPanel.BorderSizePixel = 0
		mPanel.ZIndex = 50
		mPanel.Parent = ctx.getActiveDropdown()
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
			row.Activated:Connect(function()
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
	typeBtn.Activated:Connect(function()
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
	tagBtn.Activated:Connect(function()
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
	sortBtn.Activated:Connect(function()
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

	-- Fallback: placeholder catalog ONLY when the server could not be reached.
	-- Previously this also fired when the player simply had 0 skill cards left
	-- (all equipped), showing 6 fake early-dev cards that cannot be equipped.
	if #skillCards == 0 and not MockData._useServerSkillData then
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

	if #augmentCards > 0 and TipController then TipController.Trigger("TIP-AUG-01") end -- new-player tip (augment owned)

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
				-- " OR "-aware: an entry like "Buff OR Healing OR Support" matches the selected
				-- filter tag if the filter is ANY listed option (2026-10-23).
				local matched = false
				for _, rt in ipairs(def.requiredSkillTags) do
					for option in string.gmatch(rt .. " OR ", "%s*(.-)%s* OR ") do
						if option == skillTagFilter then matched = true; break end
					end
					if matched then break end
				end
				if matched then table.insert(augFiltered, aug) end
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
	cardGrid.Parent = ctx.getSkillsPanel()

	local grid = Instance.new("UIGridLayout", cardGrid)
	grid.CellPadding = UDim2.new(0, 4, 0, 3)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirection = Enum.FillDirection.Horizontal

	-- Compute cell size: same logic as equipment grid (shared Theme.ItemTileCell, 2026-11-07)
	local skCellW, skCellH = Theme.ItemTileCell(cardGrid.AbsoluteSize.Y)
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
		nameBg.Size = UDim2.new(1, 0, 0, 12 + Theme.Text.BadgeLineH())  -- 22 desktop; +2 on phone for the 10px tag line (2026-11-07)
		nameBg.Position = UDim2.new(0, 0, 1, -(12 + Theme.Text.BadgeLineH()))
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
			Size = UDim2.new(1, -4, 0, Theme.Text.BadgeLineH()),
			Position = UDim2.new(0, 2, 0, 12),
			TextSize = Theme.Text.Badge(),
			TextColor3 = elem and ELEM_COLORS[elem] or Theme.Colors.TextSecondary })

		card.Activated:Connect(function()
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
		local costShort = NumberFormat.CostShort(costText) -- "×1.20" -> "+20%" (user 2026-11-17)
		if costShort ~= "" then
			local cBadge = Instance.new("Frame")
			cBadge.Size = UDim2.new(0, 32, 0, 12)
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
		nameBg.Size = UDim2.new(1, 0, 0, 12 + Theme.Text.BadgeLineH())  -- 22 desktop; +2 on phone for the 10px tag line (2026-11-07)
		nameBg.Position = UDim2.new(0, 0, 1, -(12 + Theme.Text.BadgeLineH()))
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
			Size = UDim2.new(1, -4, 0, Theme.Text.BadgeLineH()),
			Position = UDim2.new(0, 2, 0, 12),
			TextSize = Theme.Text.Badge(), TextColor3 = Theme.Colors.TextGold })

		card.Activated:Connect(function()
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


--------------------------------------------------


function LoadoutSkills.Init(c: any)
	ctx = c
end
LoadoutSkills.BuildSkillsContent = function(...) return buildSkillsContent(...) end

return LoadoutSkills
