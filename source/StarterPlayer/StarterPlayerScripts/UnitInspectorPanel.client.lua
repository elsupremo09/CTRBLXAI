-- UnitInspectorPanel.client.lua
-- CTRBLXAI | 4-Tab Unit Inspector (Basic / Stats / Equip / Skills)
--
-- Opens when player clicks unit portrait or fires InspectUnit.
-- Server sends full data package; client renders a tabbed panel.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local player = Players.LocalPlayer

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

--------------------------------------------------
-- STATE
--------------------------------------------------

local panelGui = nil
local currentTab = "basic"
local clickOutsideConn = nil
local detailOverlayGui = nil

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local closeDetailOverlay  -- forward declaration
closeDetailOverlay = function()
	print("[DIAG-CLOSE] closeDetailOverlay called | gui=" .. tostring(detailOverlayGui ~= nil))
	print(debug.traceback("[DIAG-CLOSE] traceback", 2))
	if detailOverlayGui then detailOverlayGui:Destroy(); detailOverlayGui = nil end
end

local function destroyPanel()
	print("[DIAG-CLOSE] destroyPanel called")
	closeDetailOverlay()
	if panelGui then panelGui:Destroy(); panelGui = nil end
	if clickOutsideConn then clickOutsideConn:Disconnect(); clickOutsideConn = nil end
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

-- Shared: render active effects block (icons + duration + damage)
local function renderActiveEffects(content, data, startOrder)
	local effectOrder = startOrder
	if not data.statuses or #data.statuses == 0 then
		createLabel(content, { Text = "  No active effects.", Order = effectOrder,
			TextSize = Theme.Text.Small(), Color = Theme.Colors.TextDisabled })
		return effectOrder + 1
	end

	for i = #data.statuses, 1, -1 do
		local s = data.statuses[i]
		local sid = s.id or s.name or "Unknown"
		local def = GameConstants.STATUSES and GameConstants.STATUSES[sid] or nil
		local sColor = Theme.GetStatusColor and Theme.GetStatusColor(sid) or Theme.Colors.Warning

		-- Duration
		local durStr
		if s.remainingTurns then durStr = s.remainingTurns .. " turns"
		elseif s.remainingCt then durStr = "CT " .. math.floor(s.remainingCt) .. " left"
		elseif def and def.durationCt then durStr = "CT " .. def.durationCt .. " left"
		else durStr = "Permanent" end

		-- Stacks
		local stackStr = s.stacks and s.stacks > 1 and (" x" .. s.stacks) or ""

		-- Row frame
		local hasDesc = def and def.description
		local hasDmg = s.nextDamage and s.nextDamage > 0
		local rowH = 18
		if hasDesc then rowH = rowH + 14 end
		if hasDmg then rowH = rowH + 14 end

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, rowH)
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.LayoutOrder = effectOrder
		row.Parent = content

		-- Icon badge (left)
		local badge = Instance.new("Frame")
		badge.Size = UDim2.fromOffset(28, 28)
		badge.Position = UDim2.fromOffset(4, 2)
		badge.BackgroundColor3 = sColor
		badge.BackgroundTransparency = 1
		badge.BorderSizePixel = 0
		badge.Parent = row
		Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 4)
		local statusAsset = Theme.GetStatusIcon(sid)
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

		-- Name + duration
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(1, -40, 0, 16)
		nameLbl.Position = UDim2.fromOffset(38, 0)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Font = Theme.Font.PrimaryBold
		nameLbl.TextSize = Theme.Text.Body()
		nameLbl.TextColor3 = sColor
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.RichText = true
		nameLbl.Text = sid .. stackStr .. "  (" .. durStr .. ")"
		nameLbl.Parent = row

		local nextY = 16
		-- Description
		if hasDesc then
			local descLbl = Instance.new("TextLabel")
			descLbl.Size = UDim2.new(1, -40, 0, 14)
			descLbl.Position = UDim2.fromOffset(38, nextY)
			descLbl.BackgroundTransparency = 1
			descLbl.Font = Theme.Font.Primary
			descLbl.TextSize = Theme.Text.Small()
			descLbl.TextColor3 = Theme.Colors.TextSecondary
			descLbl.TextXAlignment = Enum.TextXAlignment.Left
			descLbl.Text = def.description
			descLbl.Parent = row
			nextY = nextY + 14
		end

		-- Damage
		if hasDmg then
			local dmgLbl = Instance.new("TextLabel")
			dmgLbl.Size = UDim2.new(1, -40, 0, 14)
			dmgLbl.Position = UDim2.fromOffset(38, nextY)
			dmgLbl.BackgroundTransparency = 1
			dmgLbl.Font = Theme.Font.PrimaryBold
			dmgLbl.TextSize = Theme.Text.Small()
			dmgLbl.TextColor3 = Theme.Colors.Danger
			dmgLbl.TextXAlignment = Enum.TextXAlignment.Left
			dmgLbl.Text = "Next: " .. s.nextDamage .. " dmg"
			dmgLbl.Parent = row
		end

		effectOrder = effectOrder + 1
	end
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
	backdrop.Parent = gui

	-- Panel (left-docked, matching loadout screen layout)
	local panel = Theme.MakePanel("InspItemDetail",
		UDim2.new(0.55, 0, 0.9, 0),
		UDim2.new(0, 8, 0.05, 0),
		Vector2.new(0, 0),
		gui)
	panel.ClipsDescendants = true

	-- Close only when clicking OUTSIDE the panel.
	-- The panel is an ImageLabel (does not consume clicks), so we check bounds manually.
	backdrop.MouseButton1Click:Connect(function()
		local mouse = game:GetService("UserInputService"):GetMouseLocation()
		local pos = panel.AbsolutePosition
		local sz = panel.AbsoluteSize
		print(string.format("[DIAG-CLOSE] backdrop handler | mouse=(%.0f,%.0f) panel=(%.0f,%.0f)-(%.0f,%.0f)", mouse.X, mouse.Y, pos.X, pos.Y, pos.X+sz.X, pos.Y+sz.Y))
		if mouse.X >= pos.X and mouse.X <= pos.X + sz.X
			and mouse.Y >= pos.Y and mouse.Y <= pos.Y + sz.Y then
			print("[DIAG-CLOSE] backdrop BLOCKED (click inside panel)")
			return -- click was inside the panel, ignore
		end
		print("[DIAG-CLOSE] backdrop CLOSING (click outside panel)")
		closeDetailOverlay()
	end)

	-- Render using LoadoutScreen's real detail builder
	LoadoutScreen.BuildItemDetail(panel, uiItem)

	-- BACK button
	local fb = Theme.FooterBar
	local backBtn = Theme.MakeButton(gui, "BACK", "Secondary")
	backBtn.Size = UDim2.new(0, fb.BTN_W, 0, fb.BTN_H)
	backBtn.Position = UDim2.new(1, -fb.PAD - fb.BTN_W, 1, -fb.PAD - fb.BTN_H)
	backBtn.AnchorPoint = Vector2.new(0, 0)
	backBtn.MouseButton1Click:Connect(closeDetailOverlay)
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
	backdrop.Parent = gui
	backdrop.MouseButton1Click:Connect(closeDetailOverlay)

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0.5, 0, 0.7, 0)
	panel.Position = UDim2.new(0, 8, 0.15, 0)
	panel.BackgroundColor3 = Theme.Colors.Background
	panel.BackgroundTransparency = 0.03
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = true
	panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -12, 1, -12)
	scroll.Position = UDim2.fromOffset(6, 6)
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
end


-- TAB: BASIC (Active Effects + Traits)
--------------------------------------------------

local function renderBasicTab(content, data)
	local order = 1

	-- ACTIVE EFFECTS (moved from Stats tab)
	createSection(content, "ACTIVE EFFECTS", order); order = order + 1
	order = renderActiveEffects(content, data, order)

	-- RACE PASSIVE
	createSection(content, "RACE PASSIVE", order); order = order + 1
	if data.racePassiveName then
		createLabel(content, {
			Text = "  " .. data.racePassiveName,
			Size = UDim2.new(1, 0, 0, 14),
			Font = Theme.Font.PrimaryBold,
			Color = Theme.Colors.RarityEpic,
			Order = order,
		}); order = order + 1
		if data.racePassiveEffect and data.racePassiveEffect ~= "" then
			createLabel(content, {
				Text = "  " .. data.racePassiveEffect,
				Size = UDim2.new(1, 0, 0, 28),
				TextSize = Theme.Text.Small(),
				Color = Theme.Colors.TextSecondary,
				Order = order,
			}); order = order + 1
		end
	else
		createLabel(content, { Text = "  No race assigned", Order = order,
			TextSize = Theme.Text.Small(), Color = Theme.Colors.TextDisabled })
		order = order + 1
	end

	-- DOCTRINE
	createSection(content, "DOCTRINE", order); order = order + 1
	if data.doctrine then
		createLabel(content, {
			Text = "  " .. (data.doctrine.name or data.doctrineId or "Unknown"),
			Size = UDim2.new(1, 0, 0, 14),
			Font = Theme.Font.PrimaryBold,
			Color = Theme.Colors.Info,
			Order = order,
		}); order = order + 1
		if data.doctrine.effect or data.doctrine.description then
			createLabel(content, {
				Text = "  " .. (data.doctrine.effect or data.doctrine.description or ""),
				Size = UDim2.new(1, 0, 0, 28),
				TextSize = Theme.Text.Small(),
				Color = Theme.Colors.TextSecondary,
				Order = order,
			}); order = order + 1
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
				createLabel(content, { Text = "  Stats: " .. table.concat(parts, "  "),
					Order = order, Padding = 8 })
				order = order + 1
			end
		end
	else
		createLabel(content, { Text = "  No doctrine assigned", Order = order,
			TextSize = Theme.Text.Small(), Color = Theme.Colors.TextDisabled })
		order = order + 1
	end
end

--------------------------------------------------
-- TAB: STATS
--------------------------------------------------

local function renderStatsTab(content, data)
	local ps = data.primaryStats or {}
	local derived = data.derivedStats or {}

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

	local function addRow(col, text, order)
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
		return order + 1
	end

	local function addDerived(col, keys, order)
		for _, key in ipairs(keys) do
			local val = derived[key]
			if val then
				local meta = GameConstants.STAT_META and GameConstants.STAT_META[key]
				local label = meta and meta.label or key
				local suffix = meta and meta.unit or ""
				order = addRow(col, string.format("%s: <b>%s%s</b>", label, tostring(val), suffix), order)
			end
		end
		return order
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
	for _, stat in ipairs({"STR", "AGI", "INT", "VIT", "DEX", "LUK"}) do
		local info = ps[stat]
		local total = info and info.total or 0
		local base = info and info.base or total
		local bonus = info and info.bonus or 0
		local bonusStr = bonus > 0 and string.format(' <font color="rgb(100,255,100)">+%d</font>', bonus)
			or bonus < 0 and string.format(' <font color="rgb(255,100,100)">%d</font>', bonus) or ""
		o1 = addRow(col1, string.format("%s:<b>%d</b>%s (%d)", stat, total, bonusStr, base), o1)
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
	o3 = addDerived(col3, {"discoveryRadius", "unitFortune", "startingRt"}, o3)
end

--------------------------------------------------
-- TAB: EQUIPMENT (grid layout like LoadoutScreen)
--------------------------------------------------

local SLOT_ORDER = {"MainHand", "OffHand", "Head", "Body", "Gloves", "Feet", "Accessory", "Doctrine"}
local SLOT_LABELS = {
	MainHand = "MAIN HAND", OffHand = "OFF-HAND", Head = "HEAD",
	Body = "BODY", Gloves = "GLOVES", Feet = "FEET",
	Accessory = "ACCESSORY", Doctrine = "DOCTRINE",
}

local function renderEquipmentTab(content, data)
	-- 2-col x 4-row grid
	local grid = Instance.new("Frame")
	grid.Size = UDim2.new(1, 0, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.BackgroundTransparency = 1; grid.BorderSizePixel = 0
	grid.LayoutOrder = 1; grid.Parent = content

	local gridLayout = Instance.new("UIGridLayout", grid)
	gridLayout.CellSize = UDim2.new(0.5, -3, 0, 52)
	gridLayout.CellPadding = UDim2.new(0, 4, 0, 4)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder

	for idx, slot in ipairs(SLOT_ORDER) do
		local item = data.equipment and data.equipment[slot]
		-- Doctrine is special
		local isDoctrine = slot == "Doctrine"

		local tile = Instance.new("TextButton")
		tile.Text = ""
		tile.BorderSizePixel = 0
		tile.AutoButtonColor = (item ~= nil) or isDoctrine
		tile.LayoutOrder = idx
		tile.Parent = grid
		Instance.new("UICorner", tile).CornerRadius = UDim.new(0, 4)

		if isDoctrine then
			-- Doctrine tile
			tile.BackgroundColor3 = Theme.Colors.RarityLegendary
			tile.BackgroundTransparency = 0.75
			local docName = data.doctrine and data.doctrine.name or "None"
			-- Slot label (top-left)
			local slotLbl = Instance.new("TextLabel")
			slotLbl.Size = UDim2.new(1, -4, 0, 12)
			slotLbl.Position = UDim2.fromOffset(4, 2)
			slotLbl.BackgroundTransparency = 1; slotLbl.BorderSizePixel = 0
			slotLbl.Font = Theme.Font.Primary; slotLbl.TextSize = Theme.Text.Tiny()
			slotLbl.TextColor3 = Theme.Colors.TextDisabled
			slotLbl.TextXAlignment = Enum.TextXAlignment.Left
			slotLbl.Text = "DOCTRINE"; slotLbl.Parent = tile
			-- Name
			local nameLbl = Instance.new("TextLabel")
			nameLbl.Size = UDim2.new(1, -4, 0, 14)
			nameLbl.Position = UDim2.fromOffset(4, 34)
			nameLbl.BackgroundTransparency = 1; nameLbl.BorderSizePixel = 0
			nameLbl.Font = Theme.Font.PrimaryBold; nameLbl.TextSize = Theme.Text.Small()
			nameLbl.TextColor3 = Theme.Colors.TextGold
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.Text = docName; nameLbl.Parent = tile
			-- Doctrine click → detail
			tile.MouseButton1Click:Connect(function() showItemDetail({name = docName, rarity = "Legendary", icon = data.doctrine and data.doctrine.icon, itemLevel = 0}, "DOCTRINE") end)
		elseif item then
			local rc = Theme.GetRarityColor(item.rarity)
			tile.BackgroundColor3 = rc
			tile.BackgroundTransparency = 0.75
			-- Rarity border
			local stroke = Instance.new("UIStroke", tile)
			stroke.Color = rc; stroke.Thickness = 1.5
			-- Icon (left side, square)
			if item.icon and string.find(item.icon, "rbxassetid://") then
				local ico = Instance.new("ImageLabel")
				ico.Size = UDim2.new(0, 44, 0, 44)
				ico.Position = UDim2.fromOffset(4, 4)
				ico.BackgroundTransparency = 1
				ico.Image = item.icon
				ico.ScaleType = Enum.ScaleType.Fit
				ico.Parent = tile
			end
			-- Slot label (top-right)
			local slotLbl = Instance.new("TextLabel")
			slotLbl.Size = UDim2.new(0.5, -4, 0, 12)
			slotLbl.Position = UDim2.new(0.5, 0, 0, 2)
			slotLbl.BackgroundTransparency = 1; slotLbl.BorderSizePixel = 0
			slotLbl.Font = Theme.Font.Primary; slotLbl.TextSize = Theme.Text.Tiny()
			slotLbl.TextColor3 = Theme.Colors.TextDisabled
			slotLbl.TextXAlignment = Enum.TextXAlignment.Left
			slotLbl.Text = SLOT_LABELS[slot] or slot; slotLbl.Parent = tile
			-- Item name
			local nameLbl = Instance.new("TextLabel")
			nameLbl.Size = UDim2.new(0.5, -4, 0, 14)
			nameLbl.Position = UDim2.new(0.5, 0, 0, 14)
			nameLbl.BackgroundTransparency = 1; nameLbl.BorderSizePixel = 0
			nameLbl.Font = Theme.Font.PrimaryBold; nameLbl.TextSize = Theme.Text.Small()
			nameLbl.TextColor3 = rc
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
			nameLbl.Text = item.displayName or item.name or "?"; nameLbl.Parent = tile
			-- Level + Rarity
			local infoLbl = Instance.new("TextLabel")
			infoLbl.Size = UDim2.new(0.5, -4, 0, 12)
			infoLbl.Position = UDim2.new(0.5, 0, 0, 28)
			infoLbl.BackgroundTransparency = 1; infoLbl.BorderSizePixel = 0
			infoLbl.Font = Theme.Font.Mono; infoLbl.TextSize = Theme.Text.Tiny()
			infoLbl.TextColor3 = Theme.Colors.TextSecondary
			infoLbl.TextXAlignment = Enum.TextXAlignment.Left
			infoLbl.Text = "Lv." .. (item.itemLevel or 1) .. " " .. (item.rarity or "")
			infoLbl.Parent = tile
			tile.MouseButton1Click:Connect(function() showItemDetail(item, SLOT_LABELS[slot] or slot) end)
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
			slotLbl.TextColor3 = Theme.Colors.TextDisabled
			slotLbl.TextXAlignment = Enum.TextXAlignment.Left
			slotLbl.Text = SLOT_LABELS[slot] or slot; slotLbl.Parent = tile
			-- Empty indicator
			local emptyLbl = Instance.new("TextLabel")
			emptyLbl.Size = UDim2.new(1, 0, 0, 20)
			emptyLbl.Position = UDim2.fromOffset(0, 18)
			emptyLbl.BackgroundTransparency = 1; emptyLbl.BorderSizePixel = 0
			emptyLbl.Font = Theme.Font.Primary; emptyLbl.TextSize = Theme.Text.Small()
			emptyLbl.TextColor3 = Theme.Colors.TextDisabled
			emptyLbl.Text = "- Empty -"; emptyLbl.Parent = tile
		end
	end
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
		row.Text = ""; row.AutoButtonColor = true
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
		local infoText = string.format("MP:%d  RT:%d  Range:%d  %s",
			skill.mpCost or 0, skill.rtCost or 0, skill.range or 1, skill.pattern or "")
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

		row.MouseButton1Click:Connect(function() showSkillDetail(skill) end)
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
	gui.Parent = player:WaitForChild("PlayerGui")
	panelGui = gui

	-- Main frame
	local frame = Instance.new("Frame")
	frame.Name = "InspectorFrame"
	local cam = workspace.CurrentCamera
	local vpW = cam and cam.ViewportSize.X or 1920
	local isMobile = vpW < 1024
	local panelW = isMobile and math.min(math.floor(vpW * 0.62), 480) or 420
	local panelH = isMobile and math.min(math.floor((cam and cam.ViewportSize.Y or 480) * 0.85), 420) or 500
	frame.Size = UDim2.new(0, panelW, 0, panelH)
	frame.AnchorPoint = Vector2.new(0, 0)
	frame.Position = UDim2.new(0, 6, 0, 6)
	frame.BackgroundColor3 = Theme.Colors.Background
	frame.BackgroundTransparency = 0.03
	frame.BorderSizePixel = 0
	frame.Parent = gui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

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

	-- Level badge (top-left of portrait)
	if data.level then
		local lvBadge = Instance.new("Frame")
		lvBadge.Size = UDim2.fromOffset(22, 12)
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
	headerName.Text = (data.name or "Unit") .. sideStr .. "  " .. raceStr
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
	closeBtn.Parent = frame
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 4)
	closeBtn.MouseButton1Click:Connect(destroyPanel)

	-- Tab bar
	local TAB_Y = HEADER_H + 2
	local tabBar = Instance.new("Frame")
	tabBar.Size = UDim2.new(1, 0, 0, 26)
	tabBar.Position = UDim2.fromOffset(0, TAB_Y)
	tabBar.BackgroundColor3 = Theme.Colors.Background
	tabBar.BackgroundTransparency = 0.3
	tabBar.BorderSizePixel = 0
	tabBar.Parent = frame

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tabLayout.Padding = UDim.new(0, 4)
	tabLayout.Parent = tabBar

	-- Content area (scrolling)
	local CONTENT_Y = TAB_Y + 30
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

	-- Tab rendering
	local function renderTab(tabName)
		for _, child in ipairs(contentFrame:GetChildren()) do
			if child:IsA("GuiObject") then child:Destroy() end
		end
		currentTab = tabName

		if tabName == "basic" then
			renderBasicTab(contentFrame, data)
		elseif tabName == "stats" then
			renderStatsTab(contentFrame, data)
		elseif tabName == "equipment" then
			renderEquipmentTab(contentFrame, data)
		elseif tabName == "skills" then
			renderSkillsTab(contentFrame, data)
		end

		-- Update canvas size
		task.defer(function()
			contentFrame.CanvasSize = UDim2.new(0, 0, 0, contentLayout.AbsoluteContentSize.Y + 10)
		end)
	end

	-- Create tab buttons — NEW ORDER: Basic, Stats, Equip, Skills
	local tabs = { {"basic", "Basic"}, {"stats", "Stats"}, {"equipment", "Equip"}, {"skills", "Skills"} }
	for _, tab in ipairs(tabs) do
		local tabBtn = Instance.new("TextButton")
		tabBtn.Size = UDim2.new(0, 70, 0, 22)
		tabBtn.BackgroundColor3 = tab[1] == "basic" and Theme.Colors.Surface or Theme.Colors.PanelRaised
		tabBtn.Font = Theme.Font.PrimaryBold
		tabBtn.TextSize = Theme.Text.Body()
		tabBtn.TextColor3 = Theme.Colors.TextPrimary
		tabBtn.Text = tab[2]
		tabBtn.BorderSizePixel = 0
		tabBtn.Parent = tabBar
		Instance.new("UICorner", tabBtn).CornerRadius = UDim.new(0, 4)

		tabBtn.MouseButton1Click:Connect(function()
			for _, child in ipairs(tabBar:GetChildren()) do
				if child:IsA("TextButton") then
					child.BackgroundColor3 = Theme.Colors.PanelRaised
				end
			end
			tabBtn.BackgroundColor3 = Theme.Colors.Surface
			renderTab(tab[1])
		end)
	end

	-- Initial render
	renderTab("basic")

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
			if detailOverlayGui then print("[DIAG-CLOSE] InputBegan BLOCKED by detailOverlayGui guard"); return end
			print("[DIAG-CLOSE] InputBegan click-outside check running (overlay NOT open)")
			local mousePos = UserInputService:GetMouseLocation()
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
_G.CTRBLXAI_OpenInspectorPanel = function(unitId)
	if unitId then
		BattleEvents.InspectUnitRequest:FireServer(unitId)
	end
end

_G.CTRBLXAI_CloseInspectorPanel = destroyPanel
