--!strict
-- LoadoutItemDetail.lua
-- CTRBLXAI | Loadout screen: item detail overlay (openItemDetail), solo item detail content and
-- the shared detail header (also used by consumable / skill detail windows). Reached from the
-- victory screen and unit inspector through LoadoutScreen.BuildItemDetail (API unchanged).
-- Split out of LoadoutScreen.lua (2026-11-10, ARC-005 file-size split, step 7). Behaviour unchanged.
-- Host state (the one open detail overlay, the one open dropdown, inventory filter) is reached
-- through `ctx` -- no require of LoadoutScreen, so no circular dependency (dependency injection).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService       = game:GetService("TextService")
local CTRBLXAI_UI = ReplicatedStorage:WaitForChild("CTRBLXAI", 10):WaitForChild("UI", 10)
local MockData    = require(CTRBLXAI_UI:WaitForChild("MockLoadoutData", 10))
local Theme       = require(CTRBLXAI_UI:WaitForChild("Theme", 10))

local LoadoutItemDetail: any = {}

local ctx: any = nil
-- Host helpers, bound in Init (thin wrappers so a later reassignment in the host is seen).
local function buildComparisonContent(...) return ctx.buildComparisonContent(...) end
local function closeDetail(...) return ctx.closeDetail(...) end
local function getPlayerGui(...) return ctx.getPlayerGui(...) end
local function getRarityColor(...) return ctx.getRarityColor(...) end
local function makeDescCard(...) return ctx.makeDescCard(...) end
local function makeLabel(...) return ctx.makeLabel(...) end
local function pad(...) return ctx.pad(...) end
local BONUS_STAT_ORDER: any = nil -- host table, set in Init (one definition)

local buildSoloDetailContent, openItemDetail



openItemDetail = function(item, compareItem, isEquippedMode)
	closeDetail()
	if ctx.getActiveDropdown() then ctx.getActiveDropdown():Destroy(); ctx.setActiveDropdown(nil) end
	if not item then return end
	MockData.MarkSeen(item) -- opening the detail = seen (NEW badge, 2026-11-08)

	local unit = MockData.GetSelectedUnit()

	-- Full-screen overlay
	local detailOverlay = Instance.new("ScreenGui"); ctx.setDetailOverlay(detailOverlay)
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
	backdrop.Activated:Connect(closeDetail)

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
		buildSoloDetailContent(panel, item, unit and unit.id)
	end

	-- ============ BUTTON BAR (fixed bottom-right of SCREEN, outside the panel) ============
	-- Matches battle UI Execute/Back position: bottom-right, anchored (1,1).

	-- Collect buttons: COMPARE(1) | EQUIP(2) | BACK(3) right-aligned
	local btnDefs = {}
	local order = 1

	-- Tertiary: COMPARE or DETAILS (leftmost, optional)
	if not compareItem and unit and item.cat ~= "Doctrine" then
		local slot = item.cat
		local equippedItem = MockData.GetEquipped(unit.id, slot)
		if equippedItem and equippedItem.id ~= item.id then
			table.insert(btnDefs, { text = "COMPARE", style = "Tertiary", order = order, onClick = function()
				openItemDetail(item, equippedItem)
			end })
			order = order + 1
		end
	end
	-- Doctrine COMPARE (2026-10-20): spare doctrine vs the unit's equipped doctrine, using
	-- the server's per-unit delta path (percentage packages -> real stat changes).
	if not compareItem and unit and item.cat == "Doctrine" and not isEquippedMode then
		local equippedDoc = MockData.GetEquippedDoctrine and MockData.GetEquippedDoctrine(unit.id)
		if equippedDoc and equippedDoc.doctrineId ~= item.doctrineId then
			table.insert(btnDefs, { text = "COMPARE", style = "Tertiary", order = order, onClick = function()
				openItemDetail(item, equippedDoc)
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
		-- A weapon shown from the OFF-HAND slot is unequipped from the off hand (Twinblade).
		if ctx.getDetailFromSlot() == "OffHand" and item.cat == "MainHand" then eqSlot = "OffHand" end
		if eqSlot ~= "Doctrine" then
			table.insert(btnDefs, { text = "UNEQUIP", style = "Primary", order = order, onClick = function()
				if unit then
					MockData.MockUnequip(unit.id, eqSlot)
					closeDetail()
					ctx.refresh()
				end
			end })
			order = order + 1
		end
	else
		table.insert(btnDefs, { text = "EQUIP", style = "Primary", order = order, onClick = function()
			if unit then
				if item.cat == "Doctrine" then
					-- Doctrines equip by owned-instance (swap); replaced copy returns to the stash.
					if item.instanceId and MockData.ServerEquipDoctrine then
						MockData.ServerEquipDoctrine(unit.id, item.instanceId)
					end
				else
					local slot = item.cat
					-- Browsing the OFF-HAND list: a 1H weapon goes to the off hand (Twinblade).
					if ctx.getCurrentFilter() == "OffHand" and item.cat == "MainHand" then slot = "OffHand" end
					MockData.MockEquip(unit.id, slot, item.id)
				end
				closeDetail()
				ctx.refresh()
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
	if not compareItem and unit then
		local diagSlot = item.cat
		local diagEquipped = MockData.GetEquipped(unit.id, diagSlot)
		if diagEquipped then
		end
	end
	for _, def in ipairs(btnDefs) do
	end

	-- [DIAG] Deferred layout dump (after 1 frame)
	task.defer(function()
		if not btnBar or not btnBar.Parent then
			return
		end

		-- Detail panel

		-- UIListLayout
		local layout = btnBar:FindFirstChildWhichIsA("UIListLayout")
		if layout then
		end

		-- Per-button
		local prevRight = nil
		for _, child in ipairs(btnBar:GetChildren()) do
			if child:IsA("ImageButton") then
				local ap = child.AbsolutePosition
				local as = child.AbsoluteSize
				-- Compute gap from previous button
				if prevRight then
					local _gap = ap.X - prevRight
				end
				prevRight = ap.X + as.X
			end
		end

		-- SliceCenter recap
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

-- "Equipped by" line (2026-11-06): which OTHER unit currently wears this gear, so the
-- detail tells the player before EQUIP moves it (server auto-unequips the previous
-- holder, LoadoutRequestHandlers RequestEquip). Display only; read from the client's
-- copy of the server inventory (MockData.Equipped) and roster names (MockData.Units).
local HOLDER_SLOT_NAMES = { MainHand = "Main Hand", OffHand = "Off-Hand", Head = "Head",
	Torso = "Torso", Arms = "Arms", Legs = "Legs", Accessory = "Accessory" }
local function findOtherHolder(itemId, viewerUnitId)
	if not itemId or not viewerUnitId then return nil end
	for unitId, eq in pairs(MockData.Equipped or {}) do
		if unitId ~= viewerUnitId and type(eq) == "table" then
			-- Gear slots only (W1): doctrine/consumable keys can never match.
			for slot in pairs(HOLDER_SLOT_NAMES) do
				local eqId = eq[slot]
				if eqId ~= nil and eqId == itemId then
					local name = unitId
					for _, u in ipairs(MockData.GetAllUnits() or {}) do
						if u.id == unitId then name = u.name or unitId; break end
					end
					return name, HOLDER_SLOT_NAMES[slot] or tostring(slot)
				end
			end
		end
	end
	return nil
end

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
	if opts.holderText and opts.holderText ~= "" then
		local holderLbl = makeLabel(parent, { Text = opts.holderText,
			Size = UDim2.new(1, -DETAIL_TEXT_X, 0, 14),
			Position = UDim2.new(0, DETAIL_TEXT_X, 0, tagY),
			TextSize = Theme.Text.Small(), Font = Theme.Font.PrimaryBold,
			TextColor3 = Color3.new(1, 1, 1) })
		holderLbl.Name = "EquippedByLine"
		holderLbl.TextStrokeColor3 = Color3.new(0, 0, 0)
		holderLbl.TextStrokeTransparency = 0
		-- Long unit names wrap to a second line instead of being cut with "...".
		holderLbl.TextWrapped = true
		holderLbl.TextTruncate = Enum.TextTruncate.None
		local holderH = 14
		local holderW = holderLbl.AbsoluteSize.X
		if holderW > 0 then
			local hb = TextService:GetTextSize(opts.holderText, holderLbl.TextSize, holderLbl.Font, Vector2.new(holderW, 10000))
			holderH = math.max(14, math.ceil(hb.Y) + 2)
		end
		holderLbl.Size = UDim2.new(1, -DETAIL_TEXT_X, 0, holderH)
		tagY = tagY + holderH + 2
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
		local descLbl = makeLabel(parent, { Text = desc,
			Size = UDim2.new(1, -DETAIL_TEXT_X, 0, 28),
			Position = UDim2.new(0, DETAIL_TEXT_X, 0, tagY),
			TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.TextSecondary,
			TextWrapped = true })
		-- Grow to fit the wrapped text instead of cutting it off with "..." (2026-11-01).
		-- Measured now because callers place rows below by the returned height. Never
		-- shorter than the old 28 px box, so short descriptions look the same.
		descLbl.TextTruncate = Enum.TextTruncate.None
		local descH = 28
		local descW = descLbl.AbsoluteSize.X
		if descW > 0 then
			local bounds = TextService:GetTextSize(desc, descLbl.TextSize, descLbl.Font, Vector2.new(descW, 10000))
			descH = math.max(28, math.ceil(bounds.Y) + 2)
		end
		descLbl.Size = UDim2.new(1, -DETAIL_TEXT_X, 0, descH)
		tagY = tagY + descH + 2
	end
	return math.max(tagY + 2, DETAIL_PORTRAIT + 4)
end


buildSoloDetailContent = function(panel, item, viewerUnitId)
	local rc = getRarityColor(item.rarity)
	local holderName, holderSlot = findOtherHolder(item.id, viewerUnitId)
	local holderText = holderName
		and string.format("Equipped by %s (%s) · EQUIP moves it", holderName, holderSlot) or nil

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
		holderText = holderText,
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
		local rightList = Instance.new("UIListLayout")
		rightList.FillDirection = Enum.FillDirection.Vertical
		rightList.SortOrder = Enum.SortOrder.LayoutOrder
		rightList.Padding = UDim.new(0, 6)
		rightList.Parent = rightCol
		local bs = item.baseStats or {}

		if item.isDoctrine then
			-- Doctrine stat package: six signed PERCENTAGE modifiers (sum 0). Shown here in
			-- the detail's left column (green = bonus, red = penalty) (2026-10-20).
			local pkg = item.docStatPackage or {}
			local pkgOrder = { "STR", "AGI", "INT", "VIT", "DEX", "LUK" }
			local anyPkg = false
			for _, sn in ipairs(pkgOrder) do
				local v = pkg[sn]
				if v and v ~= 0 then
					anyPkg = true
					local sign = v > 0 and "+" or ""
					local row = Instance.new("Frame")
					row.Size = UDim2.new(1, 0, 0, 16)
					row.Position = UDim2.new(0, 0, 0, statY)
					row.BackgroundTransparency = 1
					row.Parent = leftCol
					makeLabel(row, { Text = sn, Size = UDim2.new(0.6, 0, 1, 0),
						TextSize = Theme.Text.Body(), TextColor3 = Theme.Colors.TextSecondary })
					makeLabel(row, { Text = sign .. v .. "%", Size = UDim2.new(0.4, 0, 1, 0),
						Position = UDim2.new(0.6, 0, 0, 0),
						TextSize = Theme.Text.Body(),
						TextColor3 = v > 0 and Theme.Colors.Success or Theme.Colors.Danger,
						Font = Theme.Font.PrimaryBold, TextXAlignment = Enum.TextXAlignment.Right })
					statY = statY + 18
				end
			end
			if not anyPkg then
				makeLabel(leftCol, { Text = "No stat changes", Size = UDim2.new(1, 0, 0, 14),
					Position = UDim2.new(0, 0, 0, statY),
					TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextDisabled })
			end
		elseif item.isWeapon then
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
					-- Stat icon left of the name (2026-11-12, user ruling 10:49 PM); no icon = blank gap.
					Theme.AddStatIcon(row, Theme.GetGearStatIcon(s.label, false), 0)
					makeLabel(row, { Text = s.label, Size = UDim2.new(0.6, -Theme.StatIconGap, 1, 0),
						Position = UDim2.new(0, Theme.StatIconGap, 0, 0),
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
					-- Stat icon left of the name (2026-11-12, user ruling 10:49 PM); no icon = blank gap.
					Theme.AddStatIcon(row, Theme.GetGearStatIcon(s.label, false), 0)
					makeLabel(row, { Text = s.label, Size = UDim2.new(0.6, -Theme.StatIconGap, 1, 0),
						Position = UDim2.new(0, Theme.StatIconGap, 0, 0),
						TextSize = Theme.Text.Body(), TextColor3 = Theme.Colors.TextSecondary })
					makeLabel(row, { Text = tostring(s.value), Size = UDim2.new(0.4, 0, 1, 0),
						Position = UDim2.new(0.6, 0, 0, 0),
						TextSize = Theme.Text.Body(), TextColor3 = Theme.Colors.TextPrimary,
						Font = Theme.Font.PrimaryBold, TextXAlignment = Enum.TextXAlignment.Right })
					statY = statY + 18
				end
			end
		end

		-- RIGHT: Archetype passives. Cards auto-size to fully show the wrapped
		-- description (2026-10-23: was a fixed 18px box that clipped long text).
		-- rightCol flows via its UIListLayout, so no manual Y cursor is needed.
		local pHeader = makeLabel(rightCol, { Text = "PASSIVES", Size = UDim2.new(1, 0, 0, 12),
			Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextSecondary })
		pHeader.LayoutOrder = 0
		if item.passives and #item.passives > 0 then
			for idx, p in ipairs(item.passives) do
				makeDescCard(rightCol, p.name or "Passive", Theme.Colors.Success,
					p.desc or "", Theme.Colors.PanelRaised, 0.3, idx)
			end
		else
			local noneLbl = makeLabel(rightCol, { Text = "None", Size = UDim2.new(1, 0, 0, 14),
				TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextDisabled })
			noneLbl.LayoutOrder = 1
		end

		-- Doctrine: list the skills it OFFERS (its choice set) under the passive.
		if item.isDoctrine and item.skills and #item.skills > 0 then
			local sHeader = makeLabel(rightCol, { Text = "SKILLS OFFERED", Size = UDim2.new(1, 0, 0, 12),
				Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextSecondary })
			sHeader.LayoutOrder = 50
			for sidx, sk in ipairs(item.skills) do
				makeDescCard(rightCol, sk.name or "Skill", Theme.Colors.Info,
					sk.desc or "", Theme.Colors.PanelRaised, 0.4, 50 + sidx)
			end
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
		local rightList = Instance.new("UIListLayout")
		rightList.FillDirection = Enum.FillDirection.Vertical
		rightList.SortOrder = Enum.SortOrder.LayoutOrder
		rightList.Padding = UDim.new(0, 6)
		rightList.Parent = rightCol
		local statY = 14
		local bs = item.bonusStats or {}
		local hasAny = false
		for _, sn in ipairs(BONUS_STAT_ORDER) do
			local bv = bs[sn]
			if bv and bv ~= 0 then
				hasAny = true
				local bp = (item.bonusStatPcts or {})[sn]
				local pctTxt = (bp and bp ~= 0) and ("  " .. (bp > 0 and "+" or "") .. bp .. "%") or ""
				local sign = bv > 0 and "+" or ""
				-- Stat icon left of the name (2026-11-12, user ruling 10:49 PM); no icon = blank gap.
				local brow = Instance.new("Frame")
				brow.Size = UDim2.new(1, 0, 0, 14)
				brow.Position = UDim2.new(0, 0, 0, statY)
				brow.BackgroundTransparency = 1
				brow.Parent = leftCol
				Theme.AddStatIcon(brow, Theme.GetGearStatIcon(sn, true), 4)
				makeLabel(brow, { Text = sn .. "  " .. sign .. bv .. pctTxt,
					Size = UDim2.new(1, -(4 + Theme.StatIconGap), 1, 0), Position = UDim2.new(0, 4 + Theme.StatIconGap, 0, 0),
					TextSize = Theme.Text.Body(), TextColor3 = Theme.Colors.Success })
				statY = statY + 16
			end
		end
		if not hasAny then
			makeLabel(leftCol, { Text = "None", Size = UDim2.new(1, 0, 0, 14),
				Position = UDim2.new(0, 4, 0, statY),
				TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextDisabled })
		end

		-- RIGHT: Bonus passives. Auto-sizing cards (2026-10-23) so long bonus-
		-- passive descriptions are never clipped. rightCol flows via UIListLayout.
		local bpHeader = makeLabel(rightCol, { Text = "BONUS PASSIVES", Size = UDim2.new(1, 0, 0, 12),
			Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextSecondary })
		bpHeader.LayoutOrder = 0
		local bp = item.bonusPassives or {}
		if #bp > 0 then
			for idx, p in ipairs(bp) do
				makeDescCard(rightCol, p.name or "Passive", Theme.Colors.Info,
					p.desc or "", Theme.Colors.PanelRaised, 0.3, idx)
			end
		else
			local noneLbl = makeLabel(rightCol, { Text = "None", Size = UDim2.new(1, 0, 0, 14),
				TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextDisabled })
			noneLbl.LayoutOrder = 1
		end
	end

	-- Show base view initially
	buildBaseView()

	-- Toggle button (lower-left of panel). Doctrines have no separate bonus view
	-- (their stat package shows in the base view), so the toggle is hidden for them.
	if not item.isDoctrine then
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
	toggleBtn.Activated:Connect(function()
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
end


function LoadoutItemDetail.Init(c: any)
	ctx = c
	BONUS_STAT_ORDER = c.BONUS_STAT_ORDER
end
LoadoutItemDetail.BuildDetailHeader = function(...) return buildDetailHeader(...) end
LoadoutItemDetail.BuildSoloDetailContent = function(...) return buildSoloDetailContent(...) end
LoadoutItemDetail.FindOtherHolder = function(...) return findOtherHolder(...) end
LoadoutItemDetail.OpenItemDetail = function(...) return openItemDetail(...) end

return LoadoutItemDetail
