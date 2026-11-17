--!strict
-- LoadoutSkillDetail.lua
-- CTRBLXAI | Loadout screen SKILLS tab: detail windows for inventory skill / augment cards
-- and for equipped skill / attached augment slots.
-- Split out of LoadoutScreen.lua (2026-11-10, ARC-005 file-size split, step 3). Behaviour unchanged.
-- Host state (the one open detail overlay, the one open dropdown) is reached through `ctx`
-- -- no require of LoadoutScreen, so no circular dependency (dependency injection).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CTRBLXAI_UI = ReplicatedStorage:WaitForChild("CTRBLXAI", 10):WaitForChild("UI", 10)
local AugmentCompatibility = require(ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
	:WaitForChild("Shared", 10):WaitForChild("AugmentCompatibility", 10))
local MockData    = require(CTRBLXAI_UI:WaitForChild("MockLoadoutData", 10))
local Theme       = require(CTRBLXAI_UI:WaitForChild("Theme", 10))
local LoadoutSkillUtil = require(CTRBLXAI_UI:WaitForChild("LoadoutSkillUtil", 10))

local LoadoutSkillDetail: any = {}

local ctx: any = nil
-- Host helpers, bound in Init (thin wrappers so a later reassignment in the host is seen).
local function buildDetailHeader(...) return ctx.buildDetailHeader(...) end
local function buildSkillsContent(...) return ctx.buildSkillsContent(...) end
local function closeDetail(...) return ctx.closeDetail(...) end
local function getPlayerGui(...) return ctx.getPlayerGui(...) end
local function makeLabel(...) return ctx.makeLabel(...) end
local function openAugmentSlotPicker(...) return ctx.openAugmentSlotPicker(...) end
local function openSkillSlotPicker(...) return ctx.openSkillSlotPicker(...) end
local function pad(...) return ctx.pad(...) end
local STYPE_COLORS = LoadoutSkillUtil.STYPE_COLORS
local STYPE_ICONS = LoadoutSkillUtil.STYPE_ICONS
local buildSkillDescription = LoadoutSkillUtil.BuildSkillDescription
local cleanEffects = LoadoutSkillUtil.CleanEffects
local getElement = LoadoutSkillUtil.GetElement
local getSkillType = LoadoutSkillUtil.GetSkillType
local simplifyPattern = LoadoutSkillUtil.SimplifyPattern
local simplifyRange = LoadoutSkillUtil.SimplifyRange

local openAugmentCardDetail, openEquippedAugmentDetail, openEquippedSkillDetail, openSkillCardDetail


-- openSkillCardDetail: Detail overlay for inventory skill card
-- ==================================================================
openSkillCardDetail = function(sk)
	closeDetail()
	if ctx.getActiveDropdown() then ctx.getActiveDropdown():Destroy(); ctx.setActiveDropdown(nil) end

	local _unit = MockData.GetSelectedUnit()
	local def = sk.def or MockData.GetSkillDef(sk.id)
	local tags = (def and def.tags) or sk.tags or {}
	local stype = getSkillType(tags)
	local stc = STYPE_COLORS[stype] or STYPE_COLORS.Utility
	local _elem = getElement(tags)

	-- Overlay ScreenGui
	local detailOverlay = Instance.new("ScreenGui"); ctx.setDetailOverlay(detailOverlay)
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
	backdrop.Activated:Connect(closeDetail)

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
	local _hdrRow = addRow(scroll, 72)
	local _hdrH = buildDetailHeader(_hdrRow, {
		iconText = STYPE_ICONS[stype] or "[*]",
		iconImage = def and def.icon or nil,
		iconBg = stc.bg,
		iconColor = stc.icon,
		iconStrokeColor = stc.icon,
		name = def and def.name or sk.name or "?",
		tags = tags,
		description = descText or "",
	})
	-- Header row grows when the description wraps past it (2026-11-01).
	if _hdrH > 72 then _hdrRow.Size = UDim2.new(1, 0, 0, _hdrH) end

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
				Size = UDim2.new(1, -8, 0, Theme.Text.BadgeLineH()),
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
				Size = UDim2.new(1, -8, 0, Theme.Text.BadgeLineH()),
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
	-- Dungeon mode Bag tag (SB-19 / SB-20 retired 2026-11-16: BagTagText returns nil), bottom-left beside the buttons.
	local bagTagText = MockData.BagTagText("skillCards", sk.id)
	if bagTagText then
		local tl = makeLabel(detailOverlay, { Text = bagTagText, Size = UDim2.new(0, 220, 0, fb.BTN_H),
			Position = UDim2.new(0, fb.PAD, 1, -fb.PAD), TextSize = math.max(10, Theme.Text.Small()), Font = Theme.Font.PrimaryBold,
			TextColor3 = Theme.Colors.TextSecondary, TextXAlignment = Enum.TextXAlignment.Left })
		tl.AnchorPoint = Vector2.new(0, 1); tl.Name = "BagTag"
	end
end

-- ==================================================================
-- openAugmentCardDetail: Detail overlay for inventory augment card
-- ==================================================================
openAugmentCardDetail = function(aug)
	closeDetail()
	if ctx.getActiveDropdown() then ctx.getActiveDropdown():Destroy(); ctx.setActiveDropdown(nil) end

	local def = aug.def or MockData.GetAugmentDef(aug.id)

	local detailOverlay = Instance.new("ScreenGui"); ctx.setDetailOverlay(detailOverlay)
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
	backdrop.Activated:Connect(closeDetail)

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
	local _hdrRow = addRow(scroll, 72)
	local _hdrH = buildDetailHeader(_hdrRow, {
		iconText = "[o]",
		iconImage = def and def.icon or nil,
		iconBg = Color3.fromRGB(74, 53, 16),
		iconColor = Theme.Colors.TextGold,
		iconStrokeColor = Theme.Colors.TextGold,
		name = def and def.name or aug.name or "?",
		tags = augTags,
		description = augDescText,
	})
	-- Header row grows when the description wraps past it (2026-11-01).
	if _hdrH > 72 then _hdrRow.Size = UDim2.new(1, 0, 0, _hdrH) end

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
			Size = UDim2.new(1, -8, 0, Theme.Text.BadgeLineH()),
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
			Size = UDim2.new(1, -8, 0, Theme.Text.BadgeLineH()),
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
	-- Dungeon mode Bag tag (SB-19 / SB-20 retired 2026-11-16: BagTagText returns nil), bottom-left beside the buttons.
	local bagTagText = MockData.BagTagText("augmentCards", aug.id)
	if bagTagText then
		local tl = makeLabel(detailOverlay, { Text = bagTagText, Size = UDim2.new(0, 220, 0, fb.BTN_H),
			Position = UDim2.new(0, fb.PAD, 1, -fb.PAD), TextSize = math.max(10, Theme.Text.Small()), Font = Theme.Font.PrimaryBold,
			TextColor3 = Theme.Colors.TextSecondary, TextXAlignment = Enum.TextXAlignment.Left })
		tl.AnchorPoint = Vector2.new(0, 1); tl.Name = "BagTag"
	end
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
	local _fakeCard = {
		id = skillId, name = name, tags = tags, def = def, mockSkill = mockSkill,
		mpCost = def and def.mpCostFormula or (mockSkill and mockSkill.mpCost) or 0,
		rtCost = def and def.rtCostFormula or (mockSkill and mockSkill.rtCost) or 0,
		qty = 1, isSkill = true,
	}

	-- Reuse skill detail overlay code via a flag
	-- For simplicity, build a simpler equipped view
	local detailOverlay = Instance.new("ScreenGui"); ctx.setDetailOverlay(detailOverlay)
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
	backdrop.Activated:Connect(closeDetail)

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
	local _hdrRow = addRow(scroll, 72)
	local _hdrH = buildDetailHeader(_hdrRow, {
		iconText = STYPE_ICONS[stype] or "[*]",
		iconImage = def and def.icon or nil,
		iconBg = stc.bg,
		iconColor = stc.icon,
		iconStrokeColor = stc.icon,
		name = name,
		tags = tags,
		description = eqDescText or "",
	})
	-- Header row grows when the description wraps past it (2026-11-01).
	if _hdrH > 72 then _hdrRow.Size = UDim2.new(1, 0, 0, _hdrH) end
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
			local lockedTxt = (a == 2 and not (MockData.Slot2Open or {})[unit.id])
				and (" - " .. tostring(MockData.Slot2LockedText or "Locked")) or ""
			makeLabel(ar, { Text = "[o] Empty Augment Slot " .. a .. lockedTxt,
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

	local detailOverlay = Instance.new("ScreenGui"); ctx.setDetailOverlay(detailOverlay)
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
	backdrop.Activated:Connect(closeDetail)

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
	local eqAugDef = MockData.GetAugmentDef(augmentId)
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
	-- If this equipped augment no longer fits its skill (e.g. after a weapon swap), say why:
	-- it does nothing in battle until swapped (tags-only rule, 2026-10-26).
	local slotLine = "Slot " .. slotNum .. "  |  Augment " .. augSlotNum
	do
		local eqLoadout = MockData.GetSkillLoadout(unit.id)
		local eqSlot = type(eqLoadout) == "table" and eqLoadout[slotNum]
		local eqSkillId = if type(eqSlot) == "table" then eqSlot.skillId else eqSlot
		if eqSkillId and eqSkillId ~= "none" then
			local fitsNow, missingNow = AugmentCompatibility.Check(eqSkillId, augmentId, MockData.GetWeaponProfile(unit.id))
			if not fitsNow and #missingNow > 0 then
				slotLine = slotLine .. "  |  Inactive: needs " .. table.concat(missingNow, ", ")
			end
		end
	end
	makeLabel(panel, { Text = slotLine,
		Size = UDim2.new(1, 0, 0, 12),
		Position = UDim2.new(0, 0, 0, nextY),
		TextSize = Theme.Text.Tiny(), TextColor3 = Theme.Colors.Info })

	-- Cost
	if def and def.costFormula then
		makeLabel(panel, { Text = "Cost: " .. def.costFormula,
			Size = UDim2.new(1, 0, 0, 14),
			-- Below the slot line, which moves down with a long description (2026-11-01).
			Position = UDim2.new(0, 0, 0, math.max(88, nextY + 18)),
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


function LoadoutSkillDetail.Init(c: any)
	ctx = c
end
LoadoutSkillDetail.OpenAugmentCardDetail = function(...) return openAugmentCardDetail(...) end
LoadoutSkillDetail.OpenEquippedAugmentDetail = function(...) return openEquippedAugmentDetail(...) end
LoadoutSkillDetail.OpenEquippedSkillDetail = function(...) return openEquippedSkillDetail(...) end
LoadoutSkillDetail.OpenSkillCardDetail = function(...) return openSkillCardDetail(...) end

return LoadoutSkillDetail
