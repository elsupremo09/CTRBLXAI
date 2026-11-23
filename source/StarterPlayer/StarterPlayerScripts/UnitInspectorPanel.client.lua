-- UnitInspectorPanel.client.lua
-- CTRBLXAI | 5-Tab Unit Inspector (Stats / Passive / Gears / Skills / Outfit)
--
-- Opens when player clicks unit portrait or fires InspectUnit.
-- Server sends full data package; client renders a tabbed panel.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local GuiService        = game:GetService("GuiService")

local player = Players.LocalPlayer
-- Forward-declared (2026-10-29) so the Passive tab's Gear Passives list can use the same slot
-- labels as the Gears tab; assigned with the equipment-tab constants further down.
local SLOT_LABELS

local BattleEvents = require(
	ReplicatedStorage
		:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("Remotes", 10)
		:WaitForChild("BattleEvents", 10)
)
local GameConstants = require(
	ReplicatedStorage
		:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("Shared", 10)
		:WaitForChild("GameConstants", 10)
)
local Theme = require(
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("UI", 10):WaitForChild("Theme", 10)
)
local LoadoutScreen = require(
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("UI", 10):WaitForChild("LoadoutScreen", 10)
)
-- Shared portrait-overlay helper (ApplyPortrait). Acyclic: UIComponents requires
-- only Theme, already required above.
local UIComponents = require(
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("UI", 10):WaitForChild("UIComponents", 10)
)
-- Shared Loadout level label (MakeLevelLabel) for the Gears tab cards (2026-11-09).
-- Acyclic: InventoryControls requires only Theme.
local InventoryControls = require(
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("UI", 10):WaitForChild("InventoryControls", 10)
)
-- MockLoadoutData owns mapServerItem (server item -> loadout UI item). Optional:
-- if it fails to load, the inspector falls back to its local mapping.
local ObjectData = nil
do
	local okOD, resOD = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Content", 10):WaitForChild("ObjectData", 10))
	end)
	if okOD then ObjectData = resOD else warn("[UnitInspector] ObjectData unavailable: " .. tostring(resOD)) end
end
local MockLoadoutData = nil
do
	local ok, res = pcall(function()
		return require(ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
			:WaitForChild("UI", 10):WaitForChild("MockLoadoutData", 10))
	end)
	if ok then MockLoadoutData = res else warn("[UnitInspector] MockLoadoutData unavailable: " .. tostring(res)) end
end
-- Outfit tab (loadout_ui_spec 92-97). Optional: if UGC fails to load, the other tabs still work.
local UGCInspectorOutfit = nil
do
	local okU, resU = pcall(function()
		return require(ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
			:WaitForChild("UI", 10):WaitForChild("UGCInspectorOutfit", 10))
	end)
	if okU then UGCInspectorOutfit = resU else warn("[UnitInspector] UGCInspectorOutfit unavailable: " .. tostring(resU)) end
end

--------------------------------------------------
-- STATE
--------------------------------------------------

local panelGui = nil
local clickOutsideConn = nil
local detailOverlayGui = nil
-- OBS Phase 2c-0: the OBS object tile shown in the full inspector, so ObjectChanged
-- can refresh/close it live. nil when no object panel is open.
local _openObjX, _openObjY, _openObjName = nil, nil, nil
-- Units sharing the inspected tile (alive first, then KO'd) + current index, for the cycle button.
local tileCycleIds: {string} = {}
local tileCycleIndex = 1

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local closeDetailOverlay  -- forward declaration
closeDetailOverlay = function()
	if detailOverlayGui then detailOverlayGui:Destroy(); detailOverlayGui = nil end
end

-- Mouse position in the SAME space as GuiObject.AbsolutePosition (2026-11-10 fix).
-- GetMouseLocation includes the top-bar inset; AbsolutePosition does not (logged: frame
-- AbsolutePosition.Y = 0 while it drew at the inset line), so subtract the inset.
local function mouseInGuiSpace(): Vector2
	return UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
end

local function destroyPanel()
	closeDetailOverlay()
	if UGCInspectorOutfit then UGCInspectorOutfit.Cleanup() end -- PRF-004
	if panelGui then panelGui:Destroy(); panelGui = nil end
	if clickOutsideConn then clickOutsideConn:Disconnect(); clickOutsideConn = nil end
	_openObjX, _openObjY, _openObjName = nil, nil, nil
end

local function createLabel(parent, props)
	local lbl = Instance.new("TextLabel")
	lbl.Size = props.Size or UDim2.new(1, 0, 0, 16)
	lbl.BackgroundTransparency = props.BgTrans or 1
	lbl.BackgroundColor3 = props.BgColor or Theme.Colors.Panel
	lbl.Font = props.Font or Theme.Font.Primary
	lbl.TextSize = props.TextSize or Theme.Text.Body()
	lbl.TextColor3 = props.Color or Theme.Colors.TextPrimary
	lbl.TextXAlignment = props.Align or Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Top
	lbl.TextWrapped = true
	lbl.RichText = true
	lbl.Text = props.Text or ""
	lbl.BorderSizePixel = 0
	lbl.LayoutOrder = props.Order or 0
	-- Optional: grow to fit wrapped text (2026-10-29, the Passive tab's half-width columns).
	if props.AutoY then lbl.AutomaticSize = Enum.AutomaticSize.Y end
	lbl.Parent = parent
	if props.Padding then
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, props.Padding)
		pad.Parent = lbl
	end
	return lbl
end

local function createSection(parent, title, order)
	return createLabel(parent, {
		Text = "  " .. title,
		Size = UDim2.new(1, 0, 0, 18),
		BgTrans = 0.3,
		BgColor = Theme.Colors.PanelRaised,
		Font = Theme.Font.PrimaryBold,
		TextSize = Theme.Text.Body(),
		Color = Theme.Colors.TextSecondary,
		Order = order,
	})
end

-- Shared: render active effects as a horizontal, drag-scrollable icon strip.
-- Height scales with the inspector panel (panelH). Tap an icon to toggle its
-- name + duration. Native tools: ScrollingFrame (horizontal) + UIListLayout.
local function renderActiveEffects(content, data, startOrder, panelH)
	local effectOrder = startOrder
	panelH = panelH or 420

	-- Strip height scales with the panel: ~16% of panel height, clamped.
	local iconSize = math.clamp(math.floor(panelH * 0.11), 32, 56)
	local labelH = 16
	local stripH = iconSize + labelH + 8

	if not data.statuses or #data.statuses == 0 then
		createLabel(content, { Text = "  No active effects.", Order = effectOrder,
			TextSize = Theme.Text.Small(), Color = Theme.Colors.TextDisabled })
		return effectOrder + 1
	end

	-- Horizontal drag-scroll strip (sized to full width, height scales with panel)
	local strip = Instance.new("ScrollingFrame")
	strip.Name = "ActiveEffectsStrip"
	strip.Size = UDim2.new(1, 0, 0, stripH)
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.ScrollingDirection = Enum.ScrollingDirection.X
	strip.AutomaticCanvasSize = Enum.AutomaticSize.X
	strip.CanvasSize = UDim2.new(0, 0, 0, 0)
	strip.ScrollBarThickness = 4
	strip.ScrollBarImageColor3 = Theme.Colors.TextSecondary
	strip.ElasticBehavior = Enum.ElasticBehavior.Always
	strip.LayoutOrder = effectOrder
	strip.Parent = content

	local hList = Instance.new("UIListLayout")
	hList.FillDirection = Enum.FillDirection.Horizontal
	hList.SortOrder = Enum.SortOrder.LayoutOrder
	hList.Padding = UDim.new(0, 6)
	hList.VerticalAlignment = Enum.VerticalAlignment.Top
	hList.Parent = strip

	for i = 1, #data.statuses do
		local s = data.statuses[i]
		local sid = s.id or s.name or "Unknown"
		local sColor = Theme.GetStatusColor and Theme.GetStatusColor(sid) or Theme.Colors.Warning

		-- Cell holds the icon (fixed) + a name label underneath (shown on tap)
		local cell = Instance.new("Frame")
		cell.Size = UDim2.fromOffset(iconSize, stripH)
		cell.BackgroundTransparency = 1
		cell.BorderSizePixel = 0
		cell.LayoutOrder = i
		cell.Parent = strip

		-- Icon button (tap to toggle name)
		local badge = Instance.new("ImageButton")
		badge.Size = UDim2.fromOffset(iconSize, iconSize)
		badge.Position = UDim2.fromOffset(0, 0)
		badge.BackgroundColor3 = sColor
		badge.BackgroundTransparency = 1
		badge.BorderSizePixel = 0
		badge.AutoButtonColor = false
		badge.Parent = cell
		Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 4)

		local statusAsset = Theme.GetStatusIcon(sid) or s.sourceIcon
		if statusAsset then
			local img = Instance.new("ImageLabel")
			img.Size = UDim2.fromScale(1, 1)
			img.BackgroundTransparency = 1
			img.Image = statusAsset
			img.ScaleType = Enum.ScaleType.Fit
			img.Parent = badge
		else
			badge.BackgroundTransparency = 0.3
			local badgeLbl = Instance.new("TextLabel")
			badgeLbl.Size = UDim2.fromScale(1, 1)
			badgeLbl.BackgroundTransparency = 1
			badgeLbl.Font = Theme.Font.PrimaryBold
			badgeLbl.TextSize = Theme.Text.Small()
			badgeLbl.TextColor3 = Theme.Colors.TextPrimary
			badgeLbl.Text = string.sub(sid, 1, 2)
			badgeLbl.Parent = badge
		end

		-- Stack count badge (top-right of icon)
		if s.stacks and s.stacks > 1 then
			local stk = Instance.new("TextLabel")
			stk.Size = UDim2.fromOffset(16, 14)
			stk.AnchorPoint = Vector2.new(1, 0)
			stk.Position = UDim2.new(1, -1, 0, 1)
			stk.BackgroundColor3 = Theme.Colors.Background
			stk.BackgroundTransparency = 0.25
			stk.BorderSizePixel = 0
			stk.Font = Theme.Font.PrimaryBold
			stk.TextSize = Theme.Text.Badge()
			stk.TextColor3 = Theme.Colors.TextPrimary
			stk.Text = "x" .. s.stacks
			stk.ZIndex = 3
			stk.Parent = badge
			Instance.new("UICorner", stk).CornerRadius = UDim.new(0, 3)
		end

		-- Tap the icon → open the SAME shared quick-peek card the battle HUD uses, via the
		-- _G bridge, so there is ONE card implementation (no duplicate). Replaces the old
		-- tiny name-only toggle, which barely told the player anything (user request
		-- 2026-10-26). `s` carries id + live duration / next-tick / stacks; the card fills in
		-- the status TYPE and description from the shared status definitions.
		badge.Activated:Connect(function()
			if _G.CTRBLXAI_ShowStatusPeek then _G.CTRBLXAI_ShowStatusPeek(s, strip) end
		end)
	end

	effectOrder = effectOrder + 1
	return effectOrder
end

--------------------------------------------------

--------------------------------------------------
-- DETAIL OVERLAY (item/skill popup from Equip/Skills tabs)
--------------------------------------------------


local function showItemDetail(eq, slotName)
	closeDetailOverlay()
	if not eq then return end

	-- Map InspectUnit equipment data → LoadoutScreen UI item format
	local rangeStr = nil
	if eq.minRange and eq.maxRange then
		rangeStr = eq.minRange .. "-" .. eq.maxRange
	end
	local isWeapon = (eq.damage and eq.damage > 0) or false
	local passives = {}
	if eq.passiveName and eq.passiveName ~= "" then
		table.insert(passives, { icon = "[*]", name = eq.passiveName, desc = eq.passiveDesc or "" })
	end
	local uiItem = {
		id = eq.name or "?",
		name = eq.displayName or eq.name or "Unknown",
		cat = slotName or "Equipment",
		sub = eq.handClass or slotName or "",
		hands = eq.handClass,
		lv = eq.itemLevel or 1,
		rarity = eq.rarity or "Common",
		icon = eq.icon or "?",
		isWeapon = isWeapon,
		flavor = eq.flavor or "",
		tags = {},
		baseStats = isWeapon and {
			Attack = eq.damage,
			Range = rangeStr,
			Pattern = eq.patternLabel, -- batch 8b (W4): server label; nil = Single, no row
			Defense = eq.defense,
			WT = eq.wt,
			RTDelay = eq.rtDelay,
		} or {
			Defense = eq.defense,
			HP = eq.hp,
			MP = eq.mp,
			WT = eq.wt,
		},
		passives = passives,
		bonusStats = {},
		bonusPassives = {},
	}
	-- Build tags from available info
	if eq.handClass then table.insert(uiItem.tags, eq.handClass) end
	if slotName then table.insert(uiItem.tags, slotName) end
	-- Map bonus lines if available
	if eq.resolvedBonus then
		-- bonusStats must be a dict {STR=2, DEX=1} (buildBonusView indexes by key name)
		-- bonusPassives must be an array {{name=..., icon=..., desc=...}}
		if eq.resolvedBonus.stats then
			for statName, value in pairs(eq.resolvedBonus.stats) do
				uiItem.bonusStats[statName] = value
			end
		end
		if eq.resolvedBonus.passives then
			for _, p in ipairs(eq.resolvedBonus.passives) do
				table.insert(uiItem.bonusPassives, { name = p.name or "?", icon = p.icon or "[*]", desc = p.desc or "" })
			end
		end
	elseif eq.bonusLines then
		-- Fallback: raw bonus lines (legacy, unlikely to work but safe)
		for _, bl in ipairs(eq.bonusLines) do
			if type(bl) == "table" and bl.name then uiItem.bonusStats[bl.name] = bl.value or 0 end
		end
	end

	-- Prefer the loadout screen's own mapper on the shared server entry so the
	-- battle inspector's item detail is identical to the loadout item detail.
	if eq.invEntry and MockLoadoutData and MockLoadoutData.MapServerItem then
		local ok, mapped = pcall(MockLoadoutData.MapServerItem, eq.invEntry)
		if ok and mapped then
			uiItem = mapped
		else
			warn("[UnitInspector] MapServerItem failed, using fallback mapping: " .. tostring(mapped))
		end
	end

	-- Create overlay
	local gui = Instance.new("ScreenGui")
	gui.Name = "InspectorItemDetail"
	gui.DisplayOrder = 150
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	detailOverlayGui = gui

	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.Text = ""; backdrop.BorderSizePixel = 0
	backdrop.AutoButtonColor = false -- no hover colour (project_rules 243)
	backdrop.Parent = gui

	-- Panel (left-docked, matching loadout screen layout)
	local panel = Theme.MakePanel("InspItemDetail",
		UDim2.new(0.55, 0, 0.9, 0),
		UDim2.new(0, 8, 0.05, 0),
		Vector2.new(0, 0),
		gui)
	panel.ClipsDescendants = true

	-- Padding to keep content inside the 9-slice frame border (~10px each side)
	local padObj = Instance.new("UIPadding", panel)
	padObj.PaddingTop = UDim.new(0, 10)
	padObj.PaddingLeft = UDim.new(0, 12)
	padObj.PaddingRight = UDim.new(0, 12)
	padObj.PaddingBottom = UDim.new(0, 10)

	-- Close only when clicking OUTSIDE the panel.
	-- The panel is an ImageLabel (does not consume clicks), so we check bounds manually.
	backdrop.Activated:Connect(function()
		local mouse = mouseInGuiSpace()  -- same space as AbsolutePosition (2026-11-10)
		local pos = panel.AbsolutePosition
		local sz = panel.AbsoluteSize
		if mouse.X >= pos.X and mouse.X <= pos.X + sz.X
			and mouse.Y >= pos.Y and mouse.Y <= pos.Y + sz.Y then
			return -- click was inside the panel, ignore
		end
		closeDetailOverlay()
	end)

	-- Render using LoadoutScreen's real detail builder
	LoadoutScreen.BuildItemDetail(panel, uiItem)

	-- BACK button
	local fb = Theme.FooterBar
	local backBtn = Theme.MakeButton(gui, "BACK", "Secondary")
	backBtn.Size = UDim2.new(0, fb.BTN_W, 0, fb.BTN_H)
	backBtn.Position = UDim2.new(1, -fb.PAD, 1, -fb.PAD)
	backBtn.AnchorPoint = Vector2.new(1, 1)
	backBtn.Activated:Connect(closeDetailOverlay)
end

-- Raw power line (before target defense / hit quality / facing). Server computes
-- it with the same CombatResolver helpers real combat uses.
local function skillPowerText(skill)
	if skill.isHealing and skill.estimatedHeal then
		return "Heal " .. tostring(skill.estimatedHeal), true
	end
	local isDamage = false
	for _, tag in ipairs(skill.tags or {}) do
		if tag == "Direct Damage" then isDamage = true; break end
	end
	if isDamage and skill.estimatedDamage and skill.estimatedDamage > 0 then
		return "Dmg " .. tostring(skill.estimatedDamage), false
	end
	return nil, false
end

local function showSkillDetail(skill)
	closeDetailOverlay()
	if not skill then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "InspectorSkillDetail"
	gui.DisplayOrder = 150
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	detailOverlayGui = gui

	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.Text = ""; backdrop.BorderSizePixel = 0
	backdrop.AutoButtonColor = false -- no hover colour (project_rules 243)
	backdrop.Parent = gui
	backdrop.Activated:Connect(closeDetailOverlay)

	local panel = Theme.MakePanel("InspSkillDetail",
		UDim2.new(0.55, 0, 0.8, 0),
		UDim2.new(0, 8, 0.1, 0),
		Vector2.new(0, 0),
		gui)
	panel.ClipsDescendants = true

	-- Padding to keep content inside the 9-slice frame border
	local panelPad = Instance.new("UIPadding", panel)
	panelPad.PaddingTop = UDim.new(0, 10)
	panelPad.PaddingLeft = UDim.new(0, 12)
	panelPad.PaddingRight = UDim.new(0, 12)
	panelPad.PaddingBottom = UDim.new(0, 10)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.Position = UDim2.fromOffset(0, 0)
	scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 3
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel

	local layout = Instance.new("UIListLayout", scroll)
	layout.Padding = UDim.new(0, 3)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	local order = 0
	local function row(text, opts)
		order = order + 1
		opts = opts or {}
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 0, opts.height or 16)
		lbl.BackgroundTransparency = 1; lbl.BorderSizePixel = 0
		lbl.Font = opts.font or Theme.Font.Primary
		lbl.TextSize = opts.textSize or Theme.Text.Small()
		lbl.TextColor3 = opts.color or Theme.Colors.TextPrimary
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextWrapped = true
		lbl.AutomaticSize = Enum.AutomaticSize.Y
		lbl.Text = text or ""
		lbl.LayoutOrder = order
		lbl.Parent = scroll
	end

	-- Icon + name header
	if skill.icon and string.find(skill.icon, "rbxassetid://") then
		local icoFrame = Instance.new("Frame")
		icoFrame.Size = UDim2.new(1, 0, 0, 52)
		icoFrame.BackgroundTransparency = 1; icoFrame.BorderSizePixel = 0
		icoFrame.LayoutOrder = 0; icoFrame.Parent = scroll
		local ico = Instance.new("ImageLabel")
		ico.Size = UDim2.fromOffset(48, 48)
		ico.Position = UDim2.fromOffset(2, 2)
		ico.BackgroundTransparency = 1
		ico.Image = skill.icon; ico.ScaleType = Enum.ScaleType.Fit
		ico.Parent = icoFrame
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(1, -58, 0, 20)
		nameLbl.Position = UDim2.fromOffset(56, 4)
		nameLbl.BackgroundTransparency = 1; nameLbl.BorderSizePixel = 0
		nameLbl.Font = Theme.Font.PrimaryBold
		nameLbl.TextSize = Theme.Text.Heading()
		nameLbl.TextColor3 = Theme.Colors.TextPrimary
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.Text = skill.name or skill.id or "?"; nameLbl.Parent = icoFrame
		local subLbl = Instance.new("TextLabel")
		subLbl.Size = UDim2.new(1, -58, 0, 14)
		subLbl.Position = UDim2.fromOffset(56, 26)
		subLbl.BackgroundTransparency = 1; subLbl.BorderSizePixel = 0
		subLbl.Font = Theme.Font.Mono; subLbl.TextSize = Theme.Text.Small()
		subLbl.TextColor3 = Theme.Colors.TextSecondary
		subLbl.TextXAlignment = Enum.TextXAlignment.Left
		subLbl.Text = string.format("MP:%d  RT:%d  Range:%d", skill.mpCost or 0, skill.rtCost or 0, skill.range or 1)
		subLbl.Parent = icoFrame
	else
		row(skill.name or skill.id or "?", { font = Theme.Font.PrimaryBold, textSize = Theme.Text.Heading() })
	end

	row(string.format("MP: %d   RT: %d   Range: %d", skill.mpCost or 0, skill.rtCost or 0, skill.range or 1), { font = Theme.Font.Mono })
	local pwrText, pwrIsHeal = skillPowerText(skill)
	if pwrText then
		row(pwrText .. " (before target defense)", { font = Theme.Font.Mono,
			color = pwrIsHeal and Theme.Colors.Success or Theme.Colors.Danger })
	end
	row("Target: " .. (skill.targetRules or "?") .. "   Pattern: " .. (skill.pattern or "?"), { color = Theme.Colors.TextSecondary })

	-- Tags
	if skill.tags and #skill.tags > 0 then
		row(table.concat(skill.tags, ", "), { color = Theme.Colors.TextDisabled })
	end

	-- Description
	if skill.description and skill.description ~= "" then
		row(skill.description, { height = 40, color = Theme.Colors.TextSecondary })
	end

	-- Effects
	if skill.effects and skill.effects ~= "" then
		row("EFFECTS", { font = Theme.Font.PrimaryBold, color = Theme.Colors.TextGold })
		row(skill.effects, { height = 60, color = Theme.Colors.TextSecondary })
	end

	-- Augments
	if skill.augments and #skill.augments > 0 then
		row("AUGMENTS", { font = Theme.Font.PrimaryBold, color = Theme.Colors.Info })
		for _, aug in ipairs(skill.augments) do
			local augRow = Instance.new("Frame")
			augRow.Size = UDim2.new(1, 0, 0, 36)
			augRow.BackgroundColor3 = Theme.Colors.PanelRaised
			augRow.BackgroundTransparency = 0.4
			augRow.BorderSizePixel = 0
			order = order + 1
			augRow.LayoutOrder = order
			augRow.Parent = scroll
			Instance.new("UICorner", augRow).CornerRadius = UDim.new(0, 4)
			if aug.icon and string.find(aug.icon, "rbxassetid://") then
				local ico = Instance.new("ImageLabel")
				ico.Size = UDim2.fromOffset(30, 30)
				ico.Position = UDim2.fromOffset(3, 3)
				ico.BackgroundTransparency = 1
				ico.Image = aug.icon; ico.ScaleType = Enum.ScaleType.Fit
				ico.Parent = augRow
			end
			local augName = Instance.new("TextLabel")
			augName.Size = UDim2.new(1, -40, 0, 14)
			augName.Position = UDim2.fromOffset(36, 2)
			augName.BackgroundTransparency = 1; augName.BorderSizePixel = 0
			augName.Font = Theme.Font.PrimaryBold; augName.TextSize = Theme.Text.Small()
			augName.TextColor3 = Theme.Colors.TextPrimary
			augName.TextXAlignment = Enum.TextXAlignment.Left
			augName.Text = aug.name or aug.id or "?"; augName.Parent = augRow
			if aug.description and aug.description ~= "" then
				local augDesc = Instance.new("TextLabel")
				augDesc.Size = UDim2.new(1, -40, 0, 12)
				augDesc.Position = UDim2.fromOffset(36, 18)
				augDesc.BackgroundTransparency = 1; augDesc.BorderSizePixel = 0
				augDesc.Font = Theme.Font.Primary; augDesc.TextSize = Theme.Text.Tiny()
				augDesc.TextColor3 = Theme.Colors.TextSecondary
				augDesc.TextXAlignment = Enum.TextXAlignment.Left
				augDesc.TextTruncate = Enum.TextTruncate.AtEnd
				augDesc.Text = aug.description; augDesc.Parent = augRow
			end
		end
	end
end


-- TAB: BASIC (Active Effects + Traits)
--------------------------------------------------

local function renderPassiveTab(content, data, panelH)
	local order = 1

	-- ACTIVE EFFECTS stays full width on top (battle-only status strip).
	createSection(content, "ACTIVE EFFECTS", order); order = order + 1
	order = renderActiveEffects(content, data, order, panelH)

	-- Two columns below (user 2026-10-29), mirroring the Loadout Info > Passives view:
	-- left = the unit's own passives (perk, flaw, race, doctrine), right = gear passives.
	-- Labels grow to fit (AutoY) because the columns are half width.
	local cols = Instance.new("Frame")
	cols.Name = "PassiveColumns"
	cols.Size = UDim2.new(1, 0, 0, 0)
	cols.AutomaticSize = Enum.AutomaticSize.Y
	cols.BackgroundTransparency = 1; cols.BorderSizePixel = 0
	cols.LayoutOrder = order; order = order + 1
	local function makeCol(name: string, xScale: number, xOffset: number): Frame
		local c = Instance.new("Frame")
		c.Name = name
		c.Size = UDim2.new(0.5, -3, 0, 0)
		c.Position = UDim2.new(xScale, xOffset, 0, 0)
		c.AutomaticSize = Enum.AutomaticSize.Y
		c.BackgroundTransparency = 1; c.BorderSizePixel = 0
		local lay = Instance.new("UIListLayout")
		lay.Padding = UDim.new(0, 1)
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.Parent = c
		c.Parent = cols
		return c
	end
	local left = makeCol("OwnPassives", 0, 0)
	local right = makeCol("GearPassives", 0.5, 3)
	cols.Parent = content -- parent last (NET-004)

	local lo = 0
	local function nl() lo = lo + 1; return lo end
	local ro = 0
	local function nr() ro = ro + 1; return ro end

	-- ===== LEFT: Perk, Flaw, Race, Doctrine (same order as the Loadout Info tab) =====
	local function renderTrait(trait, isPerk)
		createSection(left, isPerk and "PERSONAL PERK" or "PERSONAL FLAW", nl())
		local tierTxt = trait.tier and (" [" .. trait.tier:gsub("^%l", string.upper) .. "]") or ""
		createLabel(left, {
			Text = (trait.name or "Unknown") .. tierTxt,
			Size = UDim2.new(1, 0, 0, 14), AutoY = true,
			Font = Theme.Font.PrimaryBold,
			Color = isPerk and Theme.Colors.RarityEpic or Theme.Colors.Danger,
			Order = nl(),
		})
		if trait.effect and trait.effect ~= "" then
			createLabel(left, {
				Text = trait.effect,
				Size = UDim2.new(1, 0, 0, 0), AutoY = true,
				TextSize = Theme.Text.Small(),
				Color = Theme.Colors.TextSecondary,
				Order = nl(),
			})
		end
	end
	if data.perk or data.flaw then
		if data.perk then renderTrait(data.perk, true) end
		if data.flaw then renderTrait(data.flaw, false) end
	else
		createSection(left, "PERSONAL TRAITS", nl())
		createLabel(left, { Text = "  No traits assigned", Order = nl(), AutoY = true,
			TextSize = Theme.Text.Small(), Color = Theme.Colors.TextDisabled })
	end

	createSection(left, "RACE PASSIVE", nl())
	if data.racePassiveName then
		createLabel(left, {
			Text = data.racePassiveName,
			Size = UDim2.new(1, 0, 0, 14), AutoY = true,
			Font = Theme.Font.PrimaryBold,
			Color = Theme.Colors.RarityEpic,
			Order = nl(),
		})
		if data.racePassiveEffect and data.racePassiveEffect ~= "" then
			createLabel(left, {
				Text = data.racePassiveEffect,
				Size = UDim2.new(1, 0, 0, 0), AutoY = true,
				TextSize = Theme.Text.Small(),
				Color = Theme.Colors.TextSecondary,
				Order = nl(),
			})
		end
	else
		createLabel(left, { Text = "  No race assigned", Order = nl(), AutoY = true,
			TextSize = Theme.Text.Small(), Color = Theme.Colors.TextDisabled })
	end

	createSection(left, "DOCTRINE", nl())
	if data.doctrine then
		createLabel(left, {
			Text = (data.doctrine.name or data.doctrineId or "Unknown"),
			Size = UDim2.new(1, 0, 0, 14), AutoY = true,
			Font = Theme.Font.PrimaryBold,
			Color = Theme.Colors.Info,
			Order = nl(),
		})
		-- The raw DoctrineData entry stores its passive as passiveName/passiveEffect (2026-10-23).
		local docPassiveName = data.doctrine.passiveName
		local docPassiveEffect = data.doctrine.passiveEffect or data.doctrine.effect or data.doctrine.description
		if docPassiveName and docPassiveName ~= "" then
			createLabel(left, {
				Text = docPassiveName,
				Size = UDim2.new(1, 0, 0, 14), AutoY = true,
				Font = Theme.Font.PrimaryBold,
				Color = Theme.Colors.RarityEpic,
				Order = nl(),
			})
		end
		if docPassiveEffect and docPassiveEffect ~= "" then
			createLabel(left, {
				Text = docPassiveEffect,
				Size = UDim2.new(1, 0, 0, 0), AutoY = true,
				TextSize = Theme.Text.Small(),
				Color = Theme.Colors.TextSecondary,
				Order = nl(),
			})
		end
		-- Stat package
		if data.doctrine.statPackage then
			local parts = {}
			for stat, val in pairs(data.doctrine.statPackage) do
				if val ~= 0 then
					local color = val > 0 and "rgb(100,255,100)" or "rgb(255,100,100)"
					table.insert(parts, string.format('<font color="%s">%s %+d%%</font>', color, stat, val))
				end
			end
			if #parts > 0 then
				createLabel(left, { Text = "Stats: " .. table.concat(parts, "  "),
					Order = nl(), Padding = 8, AutoY = true })
			end
		end
	else
		createLabel(left, { Text = "  No doctrine assigned", Order = nl(), AutoY = true,
			TextSize = Theme.Text.Small(), Color = Theme.Colors.TextDisabled })
	end

	-- ===== RIGHT: GEAR PASSIVES (same server-built list as the Loadout Info tab) =====
	-- Slot name first, then one "Name - description" line per passive; switched-off
	-- passives dimmed with the reason.
	createSection(right, "GEAR PASSIVES", nr())
	local function esc(t)
		return (string.gsub(tostring(t), "[&<>]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" }))
	end
	local function gpLabel(text, color, bold, rich)
		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, 0, 0, 0); t.AutomaticSize = Enum.AutomaticSize.Y
		t.BackgroundTransparency = 1; t.BorderSizePixel = 0
		t.Font = bold and Theme.Font.PrimaryBold or Theme.Font.Primary
		t.TextSize = Theme.Text.Small(); t.TextColor3 = color
		t.TextXAlignment = Enum.TextXAlignment.Left; t.TextYAlignment = Enum.TextYAlignment.Top
		t.TextWrapped = true; t.RichText = rich == true
		t.Text = text
		t.LayoutOrder = nr()
		t.Parent = right -- parent last (NET-004)
	end
	local groups = data.gearPassives
	if type(groups) ~= "table" or #groups == 0 then
		gpLabel("No passives from equipped gear", Theme.Colors.TextDisabled, false)
	else
		local nameHex = Theme.Colors.TextPrimary:ToHex()
		for _, g in ipairs(groups) do
			gpLabel((SLOT_LABELS and SLOT_LABELS[g.slot]) or string.upper(tostring(g.slot)), Theme.Colors.TextGold, true)
			for _, p in ipairs(g.passives or {}) do
				local on = p.active == true
				local cnt = tonumber(p.count) or 1
				local nm = esc(p.name) .. (cnt > 1 and (" ×" .. cnt) or "")
				local line = on and ('<font color="#' .. nameHex .. '"><b>' .. nm .. "</b></font>") or ("<b>" .. nm .. "</b>")
				if p.desc and p.desc ~= "" then line = line .. " - " .. esc(p.desc) end
				if p.note then line = line .. "  ·  " .. esc(p.note) end
				if p.reason then line = line .. "  ·  " .. esc(p.reason) end
				gpLabel(line, on and Theme.Colors.TextSecondary or Theme.Colors.TextDisabled, false, true)
			end
		end
	end
end

--------------------------------------------------
-- TAB: STATS
--------------------------------------------------

local function renderStatsTab(content, data)
	local ps = data.primaryStats or {}
	local derived = data.derivedStats or {}
	local STAT_ORDER = {"STR", "AGI", "INT", "VIT", "DEX", "LUK"}

	-- Multiplier-based stats display as signed % vs the 1.0 baseline (match Info-tab,
	-- user ruling 2026-10-23): 0.830 -> -17.00%, 1.230 -> +23.00%, baseline -> +0.00%.
	local PCT_SIGNED = { debuffResist = true, rtDelayResist = true, skillPotency = true, healEfficiency = true }
	local function signedPct(v) return string.format("%+.2f%%", ((v or 1) - 1) * 100) end
	-- One formatter so a row and its explain-popup "current value" can never disagree.
	local function formatDerivedValue(key, val)
		if val == nil then return "-" end
		if PCT_SIGNED[key] then return signedPct(val) end
		local meta = GameConstants.STAT_META and GameConstants.STAT_META[key]
		return tostring(val) .. (meta and meta.unit or "")
	end

	-- Tap-to-explain popup (ported from the loadout Info panel, user ruling 2026-10-23).
	-- Closes over `data` (ps/derived). Reuses the panel's existing overlay teardown
	-- (closeDetailOverlay / detailOverlayGui) so the click-outside guard treats it like
	-- the gear/skill detail popups. Forward-declared so addRow can reference it.
	local openStatExplain

	local function addSection(col, title, order)
		local hdr = Instance.new("TextLabel")
		hdr.Size = UDim2.new(1, 0, 0, 16)
		hdr.BackgroundColor3 = Theme.Colors.PanelRaised
		hdr.BackgroundTransparency = 0.3
		hdr.Font = Theme.Font.PrimaryBold
		hdr.TextSize = Theme.Text.Small()
		hdr.TextColor3 = Theme.Colors.TextSecondary
		hdr.TextXAlignment = Enum.TextXAlignment.Left
		hdr.RichText = true; hdr.BorderSizePixel = 0
		hdr.Text = " " .. title; hdr.LayoutOrder = order
		hdr.Parent = col
		Instance.new("UICorner", hdr).CornerRadius = UDim.new(0, 3)
		return order + 1
	end

	-- statKey (optional): when set, the row is tappable and opens the explainer.
	local function addRow(col, text, order, statKey)
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 0, 14)
		lbl.BackgroundTransparency = 1; lbl.BorderSizePixel = 0
		lbl.Font = Theme.Font.Mono
		lbl.TextSize = Theme.Text.Small()
		lbl.TextColor3 = Theme.Colors.TextPrimary
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.RichText = true; lbl.TextWrapped = true
		lbl.Text = " " .. text; lbl.LayoutOrder = order
		lbl.Parent = col
		if statKey then
			local tap = Instance.new("TextButton")
			tap.Size = UDim2.fromScale(1, 1)
			tap.BackgroundTransparency = 1; tap.Text = ""
			tap.BorderSizePixel = 0; tap.AutoButtonColor = false
			tap.ZIndex = 2; tap.Parent = lbl
			tap.Activated:Connect(function() openStatExplain(statKey) end)
		end
		return order + 1
	end

	local function addDerived(col, keys, order)
		for _, key in ipairs(keys) do
			local val = derived[key]
			if val ~= nil then
				local meta = GameConstants.STAT_META and GameConstants.STAT_META[key]
				local label = meta and meta.label or key
				order = addRow(col, string.format("%s: <b>%s</b>", label, formatDerivedValue(key, val)), order, key)
			end
		end
		return order
	end

	-- Explain popup definition (assigned to the forward-declared local above).
	openStatExplain = function(key)
		closeDetailOverlay()
		local META = GameConstants.STAT_META or {}
		local function isPrimary(k)
			for _, s in ipairs(STAT_ORDER) do if s == k then return true end end
			return false
		end
		local gui = Instance.new("ScreenGui")
		gui.Name = "InspectorStatExplain"
		gui.DisplayOrder = 150
		gui.ResetOnSpawn = false
		gui.Parent = player:WaitForChild("PlayerGui")
		detailOverlayGui = gui
		local backdrop = Instance.new("TextButton")
		backdrop.Size = UDim2.fromScale(1, 1)
		backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
		backdrop.BackgroundTransparency = 0.5
		backdrop.AutoButtonColor = false
		backdrop.Text = ""; backdrop.BorderSizePixel = 0
		backdrop.Parent = gui
		backdrop.Activated:Connect(closeDetailOverlay)
		local panel = Theme.MakePanel("InspStatExplain", UDim2.new(0, 300, 0, 240), UDim2.new(0.5, 0, 0.5, 0), Vector2.new(0.5, 0.5), gui)
		panel.ClipsDescendants = true
		local pp = Instance.new("UIPadding", panel)
		pp.PaddingTop = UDim.new(0, 10); pp.PaddingLeft = UDim.new(0, 12)
		pp.PaddingRight = UDim.new(0, 12); pp.PaddingBottom = UDim.new(0, 10)
		local list = Instance.new("ScrollingFrame")
		list.Size = UDim2.new(1, 0, 1, -24)
		list.BackgroundTransparency = 1; list.BorderSizePixel = 0
		list.ScrollBarThickness = 3
		list.CanvasSize = UDim2.new(0, 0, 0, 0)
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.Parent = panel
		local ll = Instance.new("UIListLayout", list)
		ll.Padding = UDim.new(0, 4); ll.SortOrder = Enum.SortOrder.LayoutOrder
		local lo = 0
		local function addLine(txt, color, bold, wrap)
			lo += 1
			local t = Instance.new("TextLabel")
			t.Size = UDim2.new(1, 0, 0, 16); t.AutomaticSize = Enum.AutomaticSize.Y
			t.BackgroundTransparency = 1
			t.Font = bold and Theme.Font.PrimaryBold or Theme.Font.Primary
			t.TextSize = bold and Theme.Text.Body() or Theme.Text.Small()
			t.TextColor3 = color or Theme.Colors.TextPrimary
			t.TextXAlignment = Enum.TextXAlignment.Left
			t.TextWrapped = wrap ~= false
			t.Text = txt; t.LayoutOrder = lo; t.Parent = list
		end
		if isPrimary(key) then
			local info = ps[key] or {}
			local base = info.base or 0
			local total = info.total or base
			local bonus = info.bonus or (total - base)
			addLine(key, Theme.Colors.TextGold, true)
			local pdesc = (GameConstants.PRIMARY_STAT_DESC or {})[key]
			if pdesc then addLine(pdesc, Theme.Colors.TextPrimary, false); addLine("", nil, false) end
			addLine("Base (race growth + allocated):  " .. base, Theme.Colors.TextSecondary)
			local bonusNote = (bonus ~= 0) and ("  (" .. (bonus > 0 and "+" or "") .. bonus .. " from gear / doctrine / race)") or ""
			addLine("Effective:  " .. total .. bonusNote, Theme.Colors.TextSecondary)
			addLine("", nil, false)
			addLine("Powers these stats:", Theme.Colors.TextPrimary, true)
			for dkey, meta in pairs(META) do
				if meta.parent == key then
					addLine("- " .. (meta.label or dkey) .. ":  " .. (meta.formula or ""), Theme.Colors.TextSecondary)
				end
			end
		else
			local meta = META[key]
			if not meta then
				addLine(key, Theme.Colors.TextGold, true)
				addLine("No breakdown available for this stat.", Theme.Colors.TextSecondary)
			else
				addLine(meta.label or key, Theme.Colors.TextGold, true)
				if meta.desc then addLine(meta.desc, Theme.Colors.TextPrimary, false); addLine("", nil, false) end
				addLine("Formula:  " .. (meta.formula or "-"), Theme.Colors.TextSecondary)
				if key == "baseRt" then
					addLine("Own base (player unit):  400", Theme.Colors.TextSecondary)
					addLine("+ Effective Armor WT:  " .. (derived.baseRtArmorWt or 0), Theme.Colors.TextSecondary)
				end
				local parent = meta.parent
				if parent then
					local pv = ps[parent] and ps[parent].total
					addLine("Depends on " .. parent .. (pv and ("  (currently " .. pv .. ")") or ""), Theme.Colors.TextSecondary)
				end
				addLine("Current value:  " .. formatDerivedValue(key, derived[key]), Theme.Colors.TextPrimary, true)
			end
		end
		Theme.MakeBarButton(panel, "Close", "Secondary", closeDetailOverlay, {
			name = "Btn_InspStatExplainClose", autoWidth = false, minHeight = 20,
			size = UDim2.new(0, 80, 0, 20), position = UDim2.new(1, -80, 1, -20),
		})
	end

	-- 3-column container
	local colRow = Instance.new("Frame")
	colRow.Size = UDim2.new(1, 0, 0, 0)
	colRow.AutomaticSize = Enum.AutomaticSize.Y
	colRow.BackgroundTransparency = 1; colRow.BorderSizePixel = 0
	colRow.LayoutOrder = 1; colRow.Parent = content

	local function makeCol(xScale, xOffset)
		local col = Instance.new("Frame")
		col.Size = UDim2.new(0.333, -4, 0, 0)
		col.AutomaticSize = Enum.AutomaticSize.Y
		col.Position = UDim2.new(xScale, xOffset, 0, 0)
		col.BackgroundTransparency = 1; col.BorderSizePixel = 0
		col.Parent = colRow
		local lay = Instance.new("UIListLayout", col)
		lay.Padding = UDim.new(0, 2)
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		return col
	end

	local col1 = makeCol(0, 0)
	local col2 = makeCol(0.333, 2)
	local col3 = makeCol(0.666, 4)

	-- COLUMN 1: Primary Stats + Combat
	local o1 = 1
	o1 = addSection(col1, "PRIMARY STATS", o1)
	for _, stat in ipairs(STAT_ORDER) do
		local info = ps[stat]
		local total = info and info.total or 0
		local base = info and info.base or total
		local bonus = info and info.bonus or 0
		-- Display (user ruling 2026-10-23): TOTAL first, then (base +/- net modifier).
		-- No parentheses when nothing modifies the stat. Mirrors the loadout Info panel.
		local parenStr = bonus > 0 and string.format(' (%d <font color="rgb(100,255,100)">+ %d</font>)', base, bonus)
			or bonus < 0 and string.format(' (%d <font color="rgb(255,100,100)">- %d</font>)', base, -bonus) or ""
		o1 = addRow(col1, string.format("%s: <b>%d</b>%s", stat, total, parenStr), o1, stat)
	end
	o1 = addSection(col1, "COMBAT", o1)
	o1 = addDerived(col1, {"attackPower", "effectiveWt", "precision", "evasiveness", "basicAttackRt"}, o1)

	-- COLUMN 2: Defense + Resources + Movement
	local o2 = 1
	o2 = addSection(col2, "DEFENSE", o2)
	o2 = addDerived(col2, {"defensePower", "debuffResist", "rtDelayResist", "stability"}, o2)
	o2 = addSection(col2, "RESOURCES", o2)
	o2 = addDerived(col2, {"maxHp", "maxMp", "mpRegen"}, o2)
	o2 = addSection(col2, "MOVEMENT", o2)
	o2 = addDerived(col2, {"movementRange", "jump", "force"}, o2)

	-- COLUMN 3: Skills + Other
	local o3 = 1
	o3 = addSection(col3, "SKILLS", o3)
	o3 = addDerived(col3, {"skillPotency", "bonusSkillRange", "channelReduction", "healEfficiency"}, o3)
	o3 = addSection(col3, "OTHER", o3)
	o3 = addDerived(col3, {"discoveryRadius", "unitFortune", "baseRt", "startingRt"}, o3)
end

--------------------------------------------------
-- TAB: EQUIPMENT (grid layout like LoadoutScreen)
--------------------------------------------------

local SLOT_ORDER = {"MainHand", "OffHand", "Head", "Body", "Gloves", "Feet", "Accessory", "Doctrine"}
SLOT_LABELS = {
	MainHand = "MAIN HAND", OffHand = "OFF-HAND", Head = "HEAD",
	Body = "BODY", Gloves = "GLOVES", Feet = "FEET",
	Accessory = "ACCESSORY", Doctrine = "DOCTRINE",
}

-- GEARS TAB CARDS (user 2026-11-08 11:52 PM): 3 columns. Columns 1-2 = the gear slots, column 3 =
-- the unit's equipped consumables (data.consumables from InspectUnit, built from the same
-- unit.consumableSlots as the battle Items menu - no new remote). Each card: icon on the left with
-- the level badge on it (gear) or the uses badge (consumable), then the text right next to the icon:
-- slot label, then the name on two rows. Rarity = frame colour only (the "Lv.X Rarity" line is gone).
-- Cards are 52 px tall (>= 44 px touch target, project_rules 244); widths are Scale (mobile-first).
local CARD_H = 52
local CARD_ICON = 44
local CARD_PAD = 4
local CARD_TEXT_X = CARD_PAD + CARD_ICON + 4

-- White text with a black outline (the game-wide text style, project_rules 243/244 notes).
local function outlineText(lbl: TextLabel, color: Color3?)
	lbl.TextColor3 = color or Color3.new(1, 1, 1)
	lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
	lbl.TextStrokeTransparency = 0
end

-- One text line/block in the card's text column (left-aligned, starts right after the icon).
local function cardText(card: Instance, text: string, y: number, h: number, size: number, font: Enum.Font,
	wrap: boolean, color: Color3?): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -(CARD_TEXT_X + 3), 0, h)
	lbl.Position = UDim2.fromOffset(CARD_TEXT_X, y)
	lbl.BackgroundTransparency = 1; lbl.BorderSizePixel = 0
	lbl.Font = font; lbl.TextSize = size
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Top
	lbl.TextWrapped = wrap
	lbl.TextTruncate = Enum.TextTruncate.AtEnd
	lbl.Text = text
	outlineText(lbl, color)
	lbl.ZIndex = 2
	lbl.Parent = card
	return lbl
end

-- Icon square on the left of a card. Returns the holder so a badge can sit on the icon.
local function cardIcon(card: Instance, icon: string?): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Icon"
	holder.Size = UDim2.fromOffset(CARD_ICON, CARD_ICON)
	holder.Position = UDim2.fromOffset(CARD_PAD, CARD_PAD)
	holder.BackgroundTransparency = 1; holder.BorderSizePixel = 0
	if icon and string.find(icon, "rbxassetid://") then
		local ico = Instance.new("ImageLabel")
		ico.Size = UDim2.fromScale(1, 1)
		ico.BackgroundTransparency = 1
		ico.Image = icon
		ico.ScaleType = Enum.ScaleType.Fit
		ico.Parent = holder
	end
	holder.Parent = card
	return holder
end

-- Empty slot card body: "- Empty -" centred, dimmed.
local function cardEmptyText(card: Instance)
	local emptyLbl = Instance.new("TextLabel")
	emptyLbl.Size = UDim2.new(1, 0, 0, 20)
	emptyLbl.Position = UDim2.new(0, 0, 0.5, -10)
	emptyLbl.BackgroundTransparency = 1; emptyLbl.BorderSizePixel = 0
	emptyLbl.Font = Theme.Font.Primary; emptyLbl.TextSize = Theme.Text.Small()
	emptyLbl.Text = "- Empty -"
	outlineText(emptyLbl, Theme.Colors.TextDisabled)
	emptyLbl.Parent = card
end

local function renderEquipmentTab(content, data)
	local slotH = Theme.Text.Tiny() + 2
	local nameY = 3 + slotH
	local nameH = Theme.Text.Small() * 2 + 4 -- two rows (TextWrapped)

	-- Row holding the 2-column gear grid (left 2/3) and the consumable column (right 1/3).
	local row = Instance.new("Frame")
	row.Name = "GearsColumns"
	row.Size = UDim2.new(1, 0, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.BackgroundTransparency = 1; row.BorderSizePixel = 0
	row.LayoutOrder = 1

	local grid = Instance.new("Frame")
	grid.Name = "GearGrid"
	grid.Size = UDim2.new(2 / 3, -2, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.BackgroundTransparency = 1; grid.BorderSizePixel = 0
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0.5, -2, 0, CARD_H)
	gridLayout.CellPadding = UDim2.new(0, 4, 0, 4)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	grid.Parent = row

	for idx, slot in ipairs(SLOT_ORDER) do
		local item = data.equipment and data.equipment[slot]
		-- Doctrine is special
		local isDoctrine = slot == "Doctrine"

		local tile = Instance.new("TextButton")
		tile.Text = ""
		tile.BorderSizePixel = 0
		tile.AutoButtonColor = false -- no mouse-over colour change (project_rules 243); tap still works
		tile.LayoutOrder = idx
		Instance.new("UICorner", tile).CornerRadius = UDim.new(0, 4)

		if isDoctrine then
			-- Doctrine card (user default 2026-11-09): same layout as the gear cards - icon spot on the
			-- left (stays empty if the doctrine has no icon), "DOCTRINE" + the name on two rows beside it,
			-- white text with a black outline. Gold accent kept as the card tint. No new data.
			tile.BackgroundColor3 = Theme.Colors.RarityLegendary
			tile.BackgroundTransparency = 0.75
			local docName = data.doctrine and data.doctrine.name or "None"
			cardIcon(tile, data.doctrine and data.doctrine.icon)
			cardText(tile, "DOCTRINE", 3, slotH, Theme.Text.Tiny(), Theme.Font.Primary, false)
			cardText(tile, docName, nameY, nameH, Theme.Text.Small(), Theme.Font.PrimaryBold, true)
			-- Doctrine click → detail
			tile.Activated:Connect(function() showItemDetail({name = docName, rarity = "Legendary", icon = data.doctrine and data.doctrine.icon, itemLevel = 0}, "DOCTRINE") end)
		elseif item then
			local rc = Theme.GetRarityColor(item.rarity)
			tile.BackgroundColor3 = rc
			tile.BackgroundTransparency = Theme.ItemTile.BgTransparency
			-- Rarity border (the only rarity cue now)
			local stroke = Instance.new("UIStroke", tile)
			stroke.Color = rc; stroke.Thickness = Theme.ItemTile.StrokeThickness
			-- Icon (left) with the level badge on it: the shared Loadout level label, top-left.
			local iconHolder = cardIcon(tile, item.icon)
			local lvLbl = InventoryControls.MakeLevelLabel(iconHolder, "Lv." .. (item.itemLevel or 1))
			outlineText(lvLbl)
			-- Text right next to the icon: slot label, then the name on two rows.
			cardText(tile, SLOT_LABELS[slot] or slot, 3, slotH, Theme.Text.Tiny(), Theme.Font.Primary, false)
			cardText(tile, item.displayName or item.name or "?", nameY, nameH, Theme.Text.Small(),
				Theme.Font.PrimaryBold, true)
			tile.Activated:Connect(function() showItemDetail(item, SLOT_LABELS[slot] or slot) end)
		else
			tile.BackgroundColor3 = Theme.Colors.Panel
			tile.BackgroundTransparency = 0.6
			tile.AutoButtonColor = false
			-- Slot label
			local slotLbl = Instance.new("TextLabel")
			slotLbl.Size = UDim2.new(1, -4, 0, 12)
			slotLbl.Position = UDim2.fromOffset(4, 2)
			slotLbl.BackgroundTransparency = 1; slotLbl.BorderSizePixel = 0
			slotLbl.Font = Theme.Font.Primary; slotLbl.TextSize = Theme.Text.Tiny()
			slotLbl.TextXAlignment = Enum.TextXAlignment.Left
			slotLbl.Text = SLOT_LABELS[slot] or slot
			outlineText(slotLbl, Theme.Colors.TextDisabled)
			slotLbl.Parent = tile
			cardEmptyText(tile)
		end
		tile.Parent = grid -- parent last (NET-004)
	end

	-- COLUMN 3: equipped consumables (one card per slot the server sends: filled + unlocked empty).
	local consCol = Instance.new("Frame")
	consCol.Name = "ConsumableColumn"
	consCol.Size = UDim2.new(1 / 3, -2, 0, 0)
	consCol.Position = UDim2.new(2 / 3, 2, 0, 0)
	consCol.AutomaticSize = Enum.AutomaticSize.Y
	consCol.BackgroundTransparency = 1; consCol.BorderSizePixel = 0
	local consLayout = Instance.new("UIListLayout")
	consLayout.Padding = UDim.new(0, 4)
	consLayout.SortOrder = Enum.SortOrder.LayoutOrder
	consLayout.Parent = consCol

	local cons = data.consumables or {}
	if #cons == 0 then
		cons = { { slotIndex = 1, empty = true } } -- no slots sent: show one empty card, not a blank column
	end
	local catColors = LoadoutScreen.ConsCategoryColors or {}
	for i, c in ipairs(cons) do
		local card = Instance.new("Frame")
		card.Name = "Consumable" .. tostring(c.slotIndex or i)
		card.Size = UDim2.new(1, 0, 0, CARD_H)
		card.BorderSizePixel = 0
		card.LayoutOrder = c.slotIndex or i
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 4)
		if c.empty then
			card.BackgroundColor3 = Theme.Colors.Panel
			card.BackgroundTransparency = 0.6
			cardEmptyText(card)
		else
			-- Same card style as gear: category colour tint + border (the Loadout consumable colours).
			local cc = catColors[c.category] or Theme.Colors.TextSecondary
			card.BackgroundColor3 = cc
			card.BackgroundTransparency = Theme.ItemTile.BgTransparency
			local stroke = Instance.new("UIStroke", card)
			stroke.Color = cc; stroke.Thickness = Theme.ItemTile.StrokeThickness
			local iconHolder = cardIcon(card, c.icon)
			-- Uses badge on the icon, top-right (the Loadout count-badge look: Theme.ItemTile tokens).
			local usesText = string.format("x%d/%d", c.currentCharges or 0, c.maxCharges or 0)
			local t = Theme.ItemTile
			local badge = Instance.new("TextLabel")
			badge.Size = UDim2.fromOffset(Theme.BadgeFitW(usesText, Theme.Font.Mono, t.CountBadgeW),
				math.max(t.CountBadgeH, Theme.Text.BadgeLineH()))
			badge.AnchorPoint = Vector2.new(1, 0)
			badge.Position = UDim2.new(1, 0, 0, 0)
			badge.BackgroundColor3 = t.CountBadgeBg
			badge.BackgroundTransparency = t.CountBadgeBgTransparency
			badge.BorderSizePixel = 0
			badge.Font = Theme.Font.Mono
			badge.TextSize = Theme.Text.Badge()
			badge.Text = usesText
			-- Used up = red (as before); otherwise white. Black outline either way.
			outlineText(badge, if (c.currentCharges or 0) > 0 then nil else Theme.Colors.Danger)
			badge.ZIndex = 3
			Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 3)
			badge.Parent = iconHolder
			-- Text next to the icon: category (in the slot-label row), then the name on two rows.
			if c.category and c.category ~= "" then
				cardText(card, string.upper(c.category), 3, slotH, Theme.Text.Tiny(), Theme.Font.Primary, false)
			end
			cardText(card, c.name or "?", nameY, nameH, Theme.Text.Small(), Theme.Font.PrimaryBold, true)
		end
		card.Parent = consCol -- parent last (NET-004)
	end
	consCol.Parent = row

	row.Parent = content -- parent last (NET-004)
end

--------------------------------------------------
-- TAB: SKILLS (loadout-style rows with icons)
--------------------------------------------------

local function renderSkillsTab(content, data)
	local order = 1

	if not data.skills or #data.skills == 0 then
		createLabel(content, { Text = "  No skills equipped.", Order = order,
			Color = Theme.Colors.TextDisabled })
		return
	end

	for idx, skill in ipairs(data.skills) do
		-- Skill row: portrait (left) + name/info (right)
		local row = Instance.new("TextButton")
		row.Size = UDim2.new(1, 0, 0, 48)
		row.BackgroundColor3 = Theme.Colors.PanelRaised
		row.BackgroundTransparency = 0.4
		row.Text = ""; row.AutoButtonColor = false -- no hover colour (project_rules 243)
		row.BorderSizePixel = 0
		row.LayoutOrder = order
		row.Parent = content
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

		-- Skill icon (left, 44x44)
		if skill.icon and string.find(skill.icon, "rbxassetid://") then
			local ico = Instance.new("ImageLabel")
			ico.Size = UDim2.fromOffset(44, 44)
			ico.Position = UDim2.fromOffset(2, 2)
			ico.BackgroundTransparency = 1
			ico.Image = skill.icon
			ico.ScaleType = Enum.ScaleType.Fit
			ico.Parent = row
		else
			-- Fallback: slot number badge
			local badge = Instance.new("Frame")
			badge.Size = UDim2.fromOffset(44, 44)
			badge.Position = UDim2.fromOffset(2, 2)
			badge.BackgroundColor3 = Theme.Colors.Surface
			badge.BackgroundTransparency = 0.3
			badge.BorderSizePixel = 0
			badge.Parent = row
			Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 4)
			local numLbl = Instance.new("TextLabel")
			numLbl.Size = UDim2.fromScale(1, 1)
			numLbl.BackgroundTransparency = 1
			numLbl.Font = Theme.Font.PrimaryBold
			numLbl.TextSize = Theme.Text.Heading()
			numLbl.TextColor3 = Theme.Colors.TextSecondary
			numLbl.Text = tostring(idx)
			numLbl.Parent = badge
		end

		-- Skill name (bold)
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(1, -54, 0, 16)
		nameLbl.Position = UDim2.fromOffset(50, 2)
		nameLbl.BackgroundTransparency = 1; nameLbl.BorderSizePixel = 0
		nameLbl.Font = Theme.Font.PrimaryBold
		nameLbl.TextSize = Theme.Text.Body()
		nameLbl.TextColor3 = Theme.Colors.TextPrimary
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.Text = skill.name or skill.id or "?"
		nameLbl.Parent = row

		-- MP / RT / Range line
		local pwrText = skillPowerText(skill)
		local infoText = string.format("MP:%d  RT:%d  Range:%d  %s%s",
			skill.mpCost or 0, skill.rtCost or 0, skill.range or 1, skill.pattern or "",
			pwrText and ("  " .. pwrText) or "")
		local infoLbl = Instance.new("TextLabel")
		infoLbl.Size = UDim2.new(1, -54, 0, 12)
		infoLbl.Position = UDim2.fromOffset(50, 18)
		infoLbl.BackgroundTransparency = 1; infoLbl.BorderSizePixel = 0
		infoLbl.Font = Theme.Font.Mono; infoLbl.TextSize = Theme.Text.Tiny()
		infoLbl.TextColor3 = Theme.Colors.TextSecondary
		infoLbl.TextXAlignment = Enum.TextXAlignment.Left
		infoLbl.Text = infoText; infoLbl.Parent = row

		-- Tags line
		if skill.tags and #skill.tags > 0 then
			local tagLbl = Instance.new("TextLabel")
			tagLbl.Size = UDim2.new(1, -54, 0, 12)
			tagLbl.Position = UDim2.fromOffset(50, 32)
			tagLbl.BackgroundTransparency = 1; tagLbl.BorderSizePixel = 0
			tagLbl.Font = Theme.Font.Primary; tagLbl.TextSize = Theme.Text.Tiny()
			tagLbl.TextColor3 = Theme.Colors.TextDisabled
			tagLbl.TextXAlignment = Enum.TextXAlignment.Left
			tagLbl.Text = table.concat(skill.tags, " | ")
			tagLbl.Parent = row
		end

		row.Activated:Connect(function() showSkillDetail(skill) end)
		order = order + 1
	end
end

--------------------------------------------------
-- MAIN PANEL BUILDER
--------------------------------------------------

local function buildPanel(data)
	destroyPanel()
	if not data then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "UnitInspectorPanel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 140
	-- Full-screen coordinates like the BattleHUD (IgnoreGuiInset = true), so the window can
	-- line up with the HUD's View / Log / Map row (user 2026-10-29). Also makes the
	-- click-outside test below (GetMouseLocation vs AbsolutePosition) use one coordinate space.
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")
	panelGui = gui

	local cam = workspace.CurrentCamera
	local vpW = cam and cam.ViewportSize.X or 1920
	local vpH = cam and cam.ViewportSize.Y or 480
	local isMobile = vpW < 1024
	local panelW = isMobile and math.min(math.floor(vpW * 0.62), 480) or 420
	-- Top edge = top of the BattleHUD View / Log / Map row, measured live and converted into
	-- this ScreenGui's space (UI-001). Height runs down to Theme.FooterBar.PAD above the
	-- screen bottom (same margin as the command bar) so the frame never touches the edge.
	-- Fallback when the HUD row is missing: the old spot (6 px below the Roblox top bar).
	local panelTop = GuiService:GetGuiInset().Y + 6
	local hudGui = player.PlayerGui:FindFirstChild("BattleHUD")
	local vmRow = hudGui and hudGui:FindFirstChild("ViewModeButtons", true)
	if vmRow and vmRow:IsA("GuiObject") then
		local originMark = Instance.new("Frame")
		originMark.Size = UDim2.fromOffset(0, 0); originMark.BackgroundTransparency = 1
		originMark.Parent = gui
		panelTop = math.floor(vmRow.AbsolutePosition.Y - originMark.AbsolutePosition.Y + 0.5)
		originMark:Destroy()
	end
	local bottomPad = (Theme.FooterBar and Theme.FooterBar.PAD) or 8
	local screenH = if gui.AbsoluteSize.Y > 0 then gui.AbsoluteSize.Y else vpH
	local panelH = math.max(200, math.min(screenH - panelTop - bottomPad, if isMobile then 420 else 500))

	-- Main frame (9-slice ornate panel)
	local frame = Theme.MakePanel("InspectorFrame",
		UDim2.new(0, panelW, 0, panelH),
		UDim2.new(0, 6, 0, panelTop),
		Vector2.new(0, 0),
		gui)
	frame.ClipsDescendants = true

	-- Padding to keep content inside the 9-slice frame border
	local framePad = Instance.new("UIPadding", frame)
	framePad.PaddingTop = UDim.new(0, 10)
	framePad.PaddingLeft = UDim.new(0, 10)
	framePad.PaddingRight = UDim.new(0, 10)
	framePad.PaddingBottom = UDim.new(0, 10)

	-- PORTRAIT (upper-left, 48x48)
	local PORTRAIT_SIZE = 64
	local HEADER_H = 72

	local portrait = Instance.new("Frame")
	portrait.Size = UDim2.fromOffset(PORTRAIT_SIZE, PORTRAIT_SIZE)
	portrait.Position = UDim2.fromOffset(6, 4)
	portrait.BackgroundColor3 = Theme.GetSideColor and Theme.GetSideColor(data.side) or Theme.Colors.Player
	portrait.BackgroundTransparency = 0.2
	portrait.BorderSizePixel = 0
	portrait.Parent = frame
	Instance.new("UICorner", portrait).CornerRadius = UDim.new(0, 6)

	-- Initials
	local initials = string.sub(data.name or "??", 1, 2)
	local initLbl = Instance.new("TextLabel")
	initLbl.Size = UDim2.fromScale(1, 1)
	initLbl.BackgroundTransparency = 1
	initLbl.Font = Theme.Font.PrimaryBold
	initLbl.TextSize = Theme.Text.Title()
	initLbl.TextColor3 = Theme.Colors.TextPrimary
	initLbl.Text = initials
	initLbl.Parent = portrait

	-- Portrait face overlay (enemy/neutral/NPC). nil for players/summons → initials.
	UIComponents.ApplyPortrait(portrait, data.portraitAssetId, initLbl)
	UIComponents.ApplyUnitFrame(portrait) -- 2026-11-20 unit frame, side colour kept

	-- Level badge (top-left of portrait)
	if data.level then
		local lvBadge = Instance.new("Frame")
		-- Fit "LvN" at the badge text size (2026-11-07: "Lv10"+ clipped 22px at the 10px phone floor).
		lvBadge.Size = UDim2.fromOffset(Theme.BadgeFitW("Lv" .. tostring(data.level), Theme.Font.Mono, 22), math.max(12, Theme.Text.Badge() + 2))
		lvBadge.Position = UDim2.fromOffset(0, 0)
		lvBadge.BackgroundColor3 = Theme.Colors.BadgeBg
		lvBadge.BackgroundTransparency = 0.3
		lvBadge.BorderSizePixel = 0
		lvBadge.ZIndex = 3
		lvBadge.Parent = portrait
		Instance.new("UICorner", lvBadge).CornerRadius = UDim.new(0, 3)
		local lvLbl = Instance.new("TextLabel")
		lvLbl.Size = UDim2.fromScale(1, 1)
		lvLbl.BackgroundTransparency = 1
		lvLbl.Font = Theme.Font.Mono; lvLbl.TextSize = Theme.Text.Badge()
		lvLbl.TextColor3 = Theme.Colors.TextPrimary
		lvLbl.Text = "Lv" .. data.level
		lvLbl.ZIndex = 3
		lvLbl.Parent = lvBadge
	end

	-- Header text (right of portrait)
	local TEXT_LEFT = PORTRAIT_SIZE + 14
	local headerName = Instance.new("TextLabel")
	headerName.Size = UDim2.new(1, -(TEXT_LEFT + 32), 0, 18)
	headerName.Position = UDim2.fromOffset(TEXT_LEFT, 6)
	headerName.BackgroundTransparency = 1; headerName.BorderSizePixel = 0
	headerName.Font = Theme.Font.PrimaryBold
	headerName.TextSize = Theme.Text.Heading()
	headerName.TextColor3 = Theme.Colors.TextPrimary
	headerName.TextXAlignment = Enum.TextXAlignment.Left
	headerName.RichText = true
	local sideStr = data.side and (" [" .. data.side .. "]") or ""
	local raceStr = data.raceName or data.raceId or ""
	local koStr = if data.isAlive == false or (data.currentHp or 1) <= 0 then "  <font color=\"#FF5050\">[KO]</font>" else ""
	headerName.Text = (data.name or "Unit") .. sideStr .. "  " .. raceStr .. koStr
	headerName.Parent = frame

	-- HP/MP line
	local hpMpLbl = Instance.new("TextLabel")
	hpMpLbl.Size = UDim2.new(1, -(TEXT_LEFT + 4), 0, 14)
	hpMpLbl.Position = UDim2.fromOffset(TEXT_LEFT, 28)
	hpMpLbl.BackgroundTransparency = 1; hpMpLbl.BorderSizePixel = 0
	hpMpLbl.Font = Theme.Font.Mono
	hpMpLbl.TextSize = Theme.Text.Small()
	hpMpLbl.TextColor3 = Theme.Colors.TextSecondary
	hpMpLbl.TextXAlignment = Enum.TextXAlignment.Left
	hpMpLbl.Text = string.format("HP %d/%d  MP %d/%d",
		data.currentHp or 0, data.maxHp or 0, data.currentMp or 0, data.maxMp or 0)
	hpMpLbl.Parent = frame

	-- AP/RT/Tile line
	local apRtLbl = Instance.new("TextLabel")
	apRtLbl.Size = UDim2.new(1, -(TEXT_LEFT + 4), 0, 14)
	apRtLbl.Position = UDim2.fromOffset(TEXT_LEFT, 44)
	apRtLbl.BackgroundTransparency = 1; apRtLbl.BorderSizePixel = 0
	apRtLbl.Font = Theme.Font.Mono
	apRtLbl.TextSize = Theme.Text.Small()
	apRtLbl.TextColor3 = Theme.Colors.TextSecondary
	apRtLbl.TextXAlignment = Enum.TextXAlignment.Left
	local coordStr = ""
	if data.tileX and data.tileY then
		local elev = 1
		if type(_G.CTRBLXAI_GetElevation) == "function" then
			elev = _G.CTRBLXAI_GetElevation(data.tileX, data.tileY) or 1
		end
		coordStr = string.format("  Tile(%d,%d) Elev %d", data.tileX, data.tileY, elev)
	end
	apRtLbl.Text = "AP " .. (data.currentAp or 0) .. "  RT " .. (data.remainingRt or 0) .. coordStr
	apRtLbl.Parent = frame

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 24, 0, 24)
	closeBtn.Position = UDim2.new(1, -28, 0, 7)
	closeBtn.BackgroundColor3 = Theme.Colors.Danger
	closeBtn.Font = Theme.Font.PrimaryBold
	closeBtn.TextSize = Theme.Text.Title()
	closeBtn.TextColor3 = Theme.Colors.TextPrimary
	closeBtn.Text = "X"
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = false -- no hover colour (project_rules 243)
	closeBtn.Parent = frame
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 4)
	closeBtn.Activated:Connect(destroyPanel)

	-- CYCLE button: only when more than one unit (alive and/or KO'd) shares this tile.
	if #tileCycleIds > 1 then
		local cycleBtn = Instance.new("TextButton")
		cycleBtn.Name = "CycleUnits"
		cycleBtn.Size = UDim2.new(0, 52, 0, 24)
		cycleBtn.Position = UDim2.new(1, -86, 0, 7)
		cycleBtn.BackgroundColor3 = Theme.Colors.Surface
		cycleBtn.Font = Theme.Font.PrimaryBold
		cycleBtn.TextSize = Theme.Text.Small()
		cycleBtn.TextColor3 = Theme.Colors.TextPrimary
		cycleBtn.Text = `{tileCycleIndex}/{#tileCycleIds} >`
		cycleBtn.BorderSizePixel = 0
		cycleBtn.AutoButtonColor = false -- no hover colour (project_rules 243)
		cycleBtn.Parent = frame
		Instance.new("UICorner", cycleBtn).CornerRadius = UDim.new(0, 4)
		cycleBtn.Activated:Connect(function()
			tileCycleIndex = (tileCycleIndex % #tileCycleIds) + 1
			BattleEvents.InspectUnitRequest:FireServer(tileCycleIds[tileCycleIndex])
		end)
		-- Keep the name from running under the cycle button.
		headerName.Size = UDim2.new(1, -(TEXT_LEFT + 90), 0, 18)
	end

	-- Tab bar
	local TAB_Y = HEADER_H + 2
	local TAB_H = Theme.MinSize.TabButton -- 24 px bar buttons (user ruling 2026-10-08)
	local tabBar = Instance.new("Frame")
	tabBar.Size = UDim2.new(1, 0, 0, TAB_H + 4)
	tabBar.Position = UDim2.fromOffset(0, TAB_Y)
	tabBar.BackgroundColor3 = Theme.Colors.Background
	tabBar.BackgroundTransparency = 0.3
	tabBar.BorderSizePixel = 0
	tabBar.Parent = frame

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tabLayout.Padding = UDim.new(0, 4)
	-- Sort by each tab's layoutOrder (2026-10-30). Without this the default Name sort put the
	-- tabs in alphabetical order (Gears, Outfit, Passive, Skills, Stats) instead of
	-- Stats > Passive > Gears > Skills > Outfit. Same fix as the Loadout tab bar.
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabBar

	-- Content area (scrolling)
	local CONTENT_Y = TAB_Y + TAB_H + 8
	local contentFrame = Instance.new("ScrollingFrame")
	contentFrame.Name = "TabContent"
	contentFrame.Size = UDim2.new(1, -8, 1, -(CONTENT_Y + 4))
	contentFrame.Position = UDim2.fromOffset(4, CONTENT_Y)
	contentFrame.BackgroundTransparency = 1
	contentFrame.BorderSizePixel = 0
	contentFrame.ScrollBarThickness = 4
	contentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	contentFrame.Parent = frame

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.Padding = UDim.new(0, 1)
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Parent = contentFrame
	-- Keep the canvas in sync when content height changes after the first pass (2026-10-29):
	-- auto-sized text (Gear Passives) can finish sizing after the one-time task.defer measure
	-- in renderTab, which would clip the bottom section. Lives as long as the layout (no leak).
	contentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		contentFrame.CanvasSize = UDim2.new(0, 0, 0, contentLayout.AbsoluteContentSize.Y + 10)
	end)

	-- Tab rendering
	local function renderTab(tabName)
		for _, child in ipairs(contentFrame:GetChildren()) do
			if child:IsA("GuiObject") then child:Destroy() end
		end
		if UGCInspectorOutfit then UGCInspectorOutfit.Cleanup() end -- PRF-004: preview drag connections

		if tabName == "passive" then
			renderPassiveTab(contentFrame, data, panelH)
		elseif tabName == "stats" then
			renderStatsTab(contentFrame, data)
		elseif tabName == "equipment" then
			renderEquipmentTab(contentFrame, data)
		elseif tabName == "skills" then
			renderSkillsTab(contentFrame, data)
		elseif tabName == "outfit" and UGCInspectorOutfit then
			-- The popup is tracked as the detail overlay, so the click-outside guard and
			-- closeDetailOverlay treat it like the gear popup.
			UGCInspectorOutfit.Render(contentFrame, data, {
				setOverlay = function(g) detailOverlayGui = g end,
				closeOverlay = closeDetailOverlay,
			})
		end

		-- Update canvas size
		task.defer(function()
			contentFrame.CanvasSize = UDim2.new(0, 0, 0, contentLayout.AbsoluteContentSize.Y + 10)
		end)
	end

	-- Tab order matches the Loadout screen (user 2026-10-29): Stats, Passive, Gears, Skills,
	-- then Outfit last. Opens on Stats, like the Loadout Info tab.
	local tabs = { {"stats", "Stats"}, {"passive", "Passive"}, {"equipment", "Gears"}, {"skills", "Skills"} }
	if UGCInspectorOutfit then table.insert(tabs, {"outfit", "Outfit"}) end -- 5th tab (loadout_ui_spec 92)
	-- Old 9-slice text bars (user ruling 2026-10-08): Active = bronze, Inactive = navy.
	-- The highlight moves in place with Theme.SetTabState; .Activated works for touch too.
	local tabBtns = {}
	for i, tab in ipairs(tabs) do
		tabBtns[tab[1]] = Theme.MakeTabButton(tabBar, tab[2], if tab[1] == "stats" then "Active" else "Inactive", function()
			for id, b in pairs(tabBtns) do
				Theme.SetTabState(b, if id == tab[1] then "Active" else "Inactive")
			end
			renderTab(tab[1])
		end, {
			name = "Tab_" .. tab[2],
			-- Scale width so 5 tabs always fit the panel on phones; text shrinks to fit.
			size = UDim2.new(1 / #tabs, -4, 0, TAB_H),
			textSize = Theme.Text.Body(),
			layoutOrder = i,
			-- Tab icons (2026-11-15): Theme.BattleButtonIcons.TabStats / TabPassive / ...
			icon = Theme.BattleButtonIcons and Theme.BattleButtonIcons["Tab" .. tab[2]]
				or (tab[1] == "equipment" and Theme.BattleButtonIcons and Theme.BattleButtonIcons.TabGears) or nil,
			iconSize = 16, -- 16 px on every screen: at 20 "Passive" fell to 9-10 px in 413-420 px panels (2026-11-15)
		})
	end

	-- Initial render
	renderTab("stats")

	-- Click-outside-to-close
	if clickOutsideConn then clickOutsideConn:Disconnect() end
	clickOutsideConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		task.defer(function()
			if not panelGui or not frame or not frame.Parent then return end
			-- Don't close inspector while a detail overlay is open (it has its own dismiss logic)
			if detailOverlayGui then return end
			local mousePos = mouseInGuiSpace()
			local absPos = frame.AbsolutePosition
			local absSize = frame.AbsoluteSize
			if mousePos.X < absPos.X or mousePos.X > absPos.X + absSize.X
				or mousePos.Y < absPos.Y or mousePos.Y > absPos.Y + absSize.Y then
				destroyPanel()
			end
		end)
	end)
end

--------------------------------------------------
-- EVENT: Server sends unit data for inspection
--------------------------------------------------

BattleEvents.InspectUnitResponse.OnClientEvent:Connect(function(data)
	if data then
		buildPanel(data)
	end
end)

-- Expose a global so BattleVisualClient can trigger inspection
_G.CTRBLXAI_OpenInspectorPanel = function(unitId, tileUnitIds)
	if unitId then
		if type(tileUnitIds) == "table" and #tileUnitIds > 0 and table.find(tileUnitIds, unitId) then
			tileCycleIds = tileUnitIds
		else
			tileCycleIds = { unitId }
		end
		tileCycleIndex = table.find(tileCycleIds, unitId) or 1
		BattleEvents.InspectUnitRequest:FireServer(unitId)
	end
end

_G.CTRBLXAI_CloseInspectorPanel = destroyPanel

-- 2026-11-09: lets panels drawn UNDER the inspector (e.g. the turn-order bar) ignore taps
-- that land on the inspector window. Without this, a tap on the inspector's lower part
-- also reached the turn-order slot underneath and swapped/closed the inspector.
-- Uses the same screen space as the click-outside check (GetMouseLocation includes the
-- top-bar inset, so add it back for ScreenGuis that do not ignore the inset).
_G.CTRBLXAI_IsTapOverInspector = function(): boolean
	if not panelGui or not panelGui.Parent then return false end
	local frame = panelGui:FindFirstChild("InspectorFrame")
	if not frame or not frame:IsA("GuiObject") or not frame.Visible then return false end
	local m = mouseInGuiSpace()
	local p, sz = frame.AbsolutePosition, frame.AbsoluteSize
	return m.X >= p.X and m.X <= p.X + sz.X and m.Y >= p.Y and m.Y <= p.Y + sz.Y
end

--------------------------------------------------
-- MAP OBJECT INSPECTOR (same framed panel, object fields instead of unit tabs)
--------------------------------------------------
local function buildObjectPanel(objectName: string, tileX: number?, tileY: number?)
	destroyPanel()
	local def = ObjectData and ObjectData.Objects and ObjectData.Objects[objectName]
	if not def then
		warn(`[UnitInspector] No ObjectData entry for object: {objectName}`)
		return
	end
	_openObjX, _openObjY, _openObjName = tileX, tileY, objectName  -- OBS Phase 2c-0 live-refresh target
	local gui = Instance.new("ScreenGui")
	gui.Name = "UnitInspectorPanel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 140
	gui.Parent = player:WaitForChild("PlayerGui")
	panelGui = gui
	local cam = workspace.CurrentCamera
	local vpW = cam and cam.ViewportSize.X or 1920
	local isMobile = vpW < 1024
	local panelW = isMobile and math.min(math.floor(vpW * 0.62), 480) or 420
	local panelH = isMobile and math.min(math.floor((cam and cam.ViewportSize.Y or 480) * 0.6), 320) or 360
	local frame = Theme.MakePanel("InspectorFrame", UDim2.new(0, panelW, 0, panelH), UDim2.new(0, 6, 0, 6), Vector2.new(0, 0), gui)
	frame.ClipsDescendants = true
	local fp = Instance.new("UIPadding")
	fp.PaddingTop = UDim.new(0, 12); fp.PaddingBottom = UDim.new(0, 12)
	fp.PaddingLeft = UDim.new(0, 14); fp.PaddingRight = UDim.new(0, 14)
	fp.Parent = frame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 4
	scroll.Parent = frame
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 4)
	list.Parent = scroll
	local order = 0
	local function row(text: string, font, size: number, color: Color3)
		order += 1
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, -6, 0, 0)
		l.AutomaticSize = Enum.AutomaticSize.Y
		l.TextWrapped = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Font = font
		l.TextSize = size
		l.TextColor3 = color
		l.Text = text
		l.LayoutOrder = order
		l.Parent = scroll
	end
	row("MAP OBJECT", Theme.Font.PrimaryBold, Theme.Text.Small(), Theme.Colors.TextSecondary)
	row(objectName, Theme.Font.PrimaryBold, Theme.Text.Heading and Theme.Text.Heading() or Theme.Text.Body(), Theme.Colors.Warning)
	if def.category then row(def.category, Theme.Font.Primary, Theme.Text.Small(), Theme.Colors.TextSecondary) end
	if tileX and tileY then row(`Tile ({tileX}, {tileY})`, Theme.Font.Mono, Theme.Text.Small(), Theme.Colors.TextSecondary) end
	row(if def.passable then "Passable" else "Impassable", Theme.Font.Primary, Theme.Text.Body(), if def.passable then Theme.Colors.Success else Theme.Colors.Danger)
	-- OBS Phase 2a: blocker-prop / billboard readout (map_gen_rules rows 90/91).
	do
		local isOBS = false
		if def.tags then
			for _, tg in ipairs(def.tags) do if tg == "OBS" then isOBS = true break end end
		end
		if isOBS then
			row("Blocks line of sight", Theme.Font.Primary, Theme.Text.Body(), Theme.Colors.Danger)
			if def.isUnbreakable then
				row("Unbreakable. Immovable. Elevation-immune.", Theme.Font.Primary, Theme.Text.Body(), Theme.Colors.TextPrimary)
			elseif type(def.hitsToDestroy) == "number" then
				-- OBS Phase 2c-0: live HP from the client object-hp cache (ObjectChanged);
				-- falls back to full HP before any hit.
				local curHp = def.hitsToDestroy
				if tileX and tileY and _G.CTRBLXAI_GetObjectHp then
					local h = _G.CTRBLXAI_GetObjectHp(tileX, tileY)
					if type(h) == "number" then curHp = h end
				end
				row(string.format("HP %d/%d", curHp, def.hitsToDestroy), Theme.Font.PrimaryBold, Theme.Text.Body(), Theme.Colors.TextPrimary)
				row(string.format("Push: needs Force > %d", def.nativeStability or 3), Theme.Font.Primary, Theme.Text.Small(), Theme.Colors.TextSecondary)
			end
		end
	end
	if def.primaryEffect then
		row("EFFECT", Theme.Font.PrimaryBold, Theme.Text.Small(), Theme.Colors.TextSecondary)
		row(def.primaryEffect, Theme.Font.Primary, Theme.Text.Body(), Theme.Colors.TextPrimary)
	end
	if def.activation then row(`Activation: {def.activation}`, Theme.Font.Primary, Theme.Text.Small(), Theme.Colors.TextPrimary) end
	if def.interactRT then row(`Interact RT: {def.interactRT}`, Theme.Font.Mono, Theme.Text.Small(), Theme.Colors.TextPrimary) end
	if def.uses then row(`Uses: {def.uses}`, Theme.Font.Primary, Theme.Text.Small(), Theme.Colors.TextPrimary) end
	-- Player note only (2026-10-30, user-approved). def.notes is designer-only and is
	-- never shown (loadout_ui_spec 54). playerNote is nil until authored in the DB.
	if def.playerNote and def.playerNote ~= "" and def.playerNote ~= "\u{2014}" then
		row(def.playerNote, Theme.Font.Primary, Theme.Text.Tiny(), Theme.Colors.TextSecondary)
	end
	-- Click outside closes (same behaviour as the unit inspector).
	if clickOutsideConn then clickOutsideConn:Disconnect() end
	clickOutsideConn = UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		task.defer(function()
			if not panelGui or not frame.Parent then return end
			local m = mouseInGuiSpace()
			local p, sz = frame.AbsolutePosition, frame.AbsoluteSize
			if m.X < p.X or m.X > p.X + sz.X or m.Y < p.Y or m.Y > p.Y + sz.Y then destroyPanel() end
		end)
	end)
end

_G.CTRBLXAI_OpenObjectInspector = function(objectName, tileX, tileY)
	if type(objectName) == "string" and objectName ~= "" then buildObjectPanel(objectName, tileX, tileY) end
end

-- OBS Phase 2c-0: BattleVisualClient's ObjectChanged handler calls this so an open
-- object inspector updates live: rebuild with the new HP (read from the client
-- cache) or close the panel when the object was destroyed.
-- newName (optional, A3 2026-10-28): post-unmask display type -> rebuild under that name.
_G.CTRBLXAI_NotifyObjectChanged = function(x, y, newHp, destroyed, newName)
	if _openObjX ~= x or _openObjY ~= y then return end
	if destroyed then
		destroyPanel()
	elseif type(newName) == "string" and newName ~= "" then
		buildObjectPanel(newName, x, y)
	elseif _openObjName then
		buildObjectPanel(_openObjName, x, y)
	end
end
