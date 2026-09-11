-- UnitInspectorPanel.client.lua
-- CTRBLXAI | 3-Tab Unit Inspector (Stats / Equipment / Skills)
--
-- Opens when player clicks "View Full Stat Breakdown" or fires InspectUnit.
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

--------------------------------------------------
-- STATE
--------------------------------------------------

local panelGui = nil
local currentTab = "stats"
local clickOutsideConn = nil

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function destroyPanel()
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

--------------------------------------------------
-- TAB: STATS
--------------------------------------------------

local function renderStatsTab(content, data)
	local ps = data.primaryStats or {}
	local derived = data.derivedStats or {}

	-- Helper: render a section header + stat rows into a column frame
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

	-- COLUMN 2: Defense + Resources
	local o2 = 1
	o2 = addSection(col2, "DEFENSE", o2)
	o2 = addDerived(col2, {"defensePower", "debuffResist", "rtDelayResist", "stability"}, o2)
	o2 = addSection(col2, "RESOURCES", o2)
	o2 = addDerived(col2, {"maxHp", "maxMp", "mpRegen"}, o2)
	o2 = addSection(col2, "MOVEMENT", o2)
	o2 = addDerived(col2, {"movementRange", "jump", "force"}, o2)

	-- COLUMN 3: Movement + Skills + Other
	local o3 = 1
	o3 = addSection(col3, "SKILLS", o3)
	o3 = addDerived(col3, {"skillPotency", "bonusSkillRange", "channelReduction", "healEfficiency"}, o3)
	o3 = addSection(col3, "OTHER", o3)
	o3 = addDerived(col3, {"discoveryRadius", "unitFortune", "startingRt"}, o3)

	-- ACTIVE EFFECTS (full width, below columns)
	if data.statuses and #data.statuses > 0 then
		createSection(content, "ACTIVE EFFECTS", 2)
		local effectOrder = 3
		for i = #data.statuses, 1, -1 do
			local s = data.statuses[i]
			local sid = s.id or s.name or "Unknown"
			local def = GameConstants.STATUSES and GameConstants.STATUSES[sid] or nil
			local kind = s.kind or (def and def.kind) or "Debuff"
			local sColor = Theme.GetStatusColor and Theme.GetStatusColor(sid) or Theme.Colors.Warning

			-- Duration
			local durStr
			if s.remainingTurns then durStr = s.remainingTurns .. " turns"
			elseif def and def.durationCt then durStr = "CT-based"
			else durStr = "Permanent" end

			-- Stacks
			local stackStr = s.stacks and s.stacks > 1 and (" x" .. s.stacks) or ""

			-- Row frame: icon badge + name/details
			local row = Instance.new("Frame")
			local hasDesc = def and def.description
			row.Size = UDim2.new(1, 0, 0, hasDesc and 46 or 32)
			row.BackgroundTransparency = 1
			row.BorderSizePixel = 0
			row.LayoutOrder = effectOrder
			row.Parent = content

			-- Colored icon badge (left)
			local badge = Instance.new("Frame")
			badge.Size = UDim2.fromOffset(28, 28)
			badge.Position = UDim2.fromOffset(4, 2)
			badge.BackgroundColor3 = sColor
			badge.BackgroundTransparency = 0.3
			badge.BorderSizePixel = 0
			badge.Parent = row
			Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 4)
			local badgeLbl = Instance.new("TextLabel")
			badgeLbl.Size = UDim2.fromScale(1, 1)
			badgeLbl.BackgroundTransparency = 1
			badgeLbl.Font = Theme.Font.PrimaryBold
			badgeLbl.TextSize = Theme.Text.Small()
			badgeLbl.TextColor3 = Theme.Colors.TextPrimary
			badgeLbl.Text = string.sub(sid, 1, 2)
			badgeLbl.Parent = badge

			-- Name + duration (right of badge)
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

			-- Description line from GameConstants
			local descText = def and def.description or nil
			if descText then
				local descLbl = Instance.new("TextLabel")
				descLbl.Size = UDim2.new(1, -40, 0, 14)
				descLbl.Position = UDim2.fromOffset(38, 16)
				descLbl.BackgroundTransparency = 1
				descLbl.Font = Theme.Font.Primary
				descLbl.TextSize = Theme.Text.Small()
				descLbl.TextColor3 = Theme.Colors.TextSecondary
				descLbl.TextXAlignment = Enum.TextXAlignment.Left
				descLbl.Text = descText
				descLbl.Parent = row
			end

			-- Damage line (below description)
			if s.nextDamage and s.nextDamage > 0 then
				local dmgY = descText and 30 or 16
				local dmgLbl = Instance.new("TextLabel")
				dmgLbl.Size = UDim2.new(1, -40, 0, 14)
				dmgLbl.Position = UDim2.fromOffset(38, dmgY)
				dmgLbl.BackgroundTransparency = 1
				dmgLbl.Font = Theme.Font.PrimaryBold
				dmgLbl.TextSize = Theme.Text.Small()
				dmgLbl.TextColor3 = Theme.Colors.Danger
				dmgLbl.TextXAlignment = Enum.TextXAlignment.Left
				dmgLbl.Text = "Next: " .. s.nextDamage .. " dmg"
				dmgLbl.Parent = row
				-- Expand row height to fit
				row.Size = UDim2.new(1, 0, 0, dmgY + 16)
			end

			effectOrder = effectOrder + 1
		end
	end
end

--------------------------------------------------
-- TAB: EQUIPMENT
--------------------------------------------------

local function renderEquipmentTab(content, data)
	local order = 1
	local slotEmoji = {
		MainHand = "⚔", OffHand = "🛡", Body = "🧥",
		Head = "🎩", Gloves = "🧤", Feet = "👢", Accessory = "💎",
	}
	local slotOrder = {"MainHand", "OffHand", "Body", "Head", "Gloves", "Feet", "Accessory"}

	for _, slot in ipairs(slotOrder) do
		local emoji = slotEmoji[slot] or "•"
		local item = data.equipment and data.equipment[slot]

		if item then
			createSection(content, string.format("%s %s: %s [%s] Lv.%d",
				emoji, slot, item.name, item.rarity, item.itemLevel), order)
			order = order + 1

			local statLine = string.format("  Dmg:%d  WT:%d  Dly:%d  Def:%d  Range:%d  %s",
				item.damage or 0, item.wt or 0, item.rtDelay or 0,
				item.defense or 0, item.maxRange or 1, item.pattern or "Single")
			createLabel(content, { Text = statLine, Order = order, Padding = 8 })
			order = order + 1

			if item.nativePassive then
				createLabel(content, {
					Text = '  <font color="rgb(180,140,255)">Passive: ' .. tostring(item.nativePassive) .. '</font>',
					Order = order, Padding = 8,
				})
				order = order + 1
			end

			if item.bonusLines and #item.bonusLines > 0 then
				for _, bl in ipairs(item.bonusLines) do
					createLabel(content, {
						Text = '  <font color="rgb(100,200,255)">+ ' .. tostring(bl.id or "Bonus") .. '</font>',
						Order = order, Padding = 8,
					})
					order = order + 1
				end
			end
		else
			createLabel(content, {
				Text = string.format("  %s %s: <font color='rgb(80,80,80)'>(empty)</font>", emoji, slot),
				Order = order, Color = Theme.Colors.TextDisabled,
			})
			order = order + 1
		end
	end

	-- Doctrine
	createSection(content, "📖 DOCTRINE", order); order = order + 1
	if data.doctrine then
		createLabel(content, {
			Text = "  " .. (data.doctrine.name or data.doctrineId or "Unknown"),
			Order = order, Font = Theme.Font.PrimaryBold,
			Color = Theme.Colors.TextGold,
		})
		order = order + 1
		if data.doctrine.statPackage then
			local parts = {}
			for stat, val in pairs(data.doctrine.statPackage) do
				if val ~= 0 then
					local color = val > 0 and "rgb(100,255,100)" or "rgb(255,100,100)"
					table.insert(parts, string.format('<font color="%s">%s %+d</font>', color, stat, val))
				end
			end
			if #parts > 0 then
				createLabel(content, { Text = "  Stats: " .. table.concat(parts, "  "), Order = order, Padding = 8 })
				order = order + 1
			end
		end
	else
		createLabel(content, {
			Text = '  <font color="rgb(80,80,80)">(no doctrine equipped)</font>',
			Order = order,
		})
		order = order + 1
	end
end

--------------------------------------------------
-- TAB: SKILLS
--------------------------------------------------

local function renderSkillsTab(content, data)
	local order = 1

	if not data.skills or #data.skills == 0 then
		createLabel(content, { Text = "  No skills equipped.", Order = order })
		return
	end

	for idx, skill in ipairs(data.skills) do
		-- Skill header
		local headerText = string.format("[%d] <b>%s</b>    MP:%d  RT:%d",
			idx, skill.name or skill.id, skill.mpCost or 0, skill.rtCost or 0)
		createSection(content, headerText, order); order = order + 1

		-- Tags
		if skill.tags and #skill.tags > 0 then
			createLabel(content, {
				Text = '  Tags: <font color="rgb(180,180,255)">' .. table.concat(skill.tags, ", ") .. '</font>',
				Order = order, Padding = 8,
			})
			order = order + 1
		end

		-- Range + Pattern
		local rangeLine = string.format("  Range: %d  Pattern: %s  Target: %s",
			skill.range or 1, skill.pattern or "Single", skill.targetRules or "Enemy Unit")
		createLabel(content, { Text = rangeLine, Order = order, Padding = 8 })
		order = order + 1

		-- Power formula
		if skill.powerFormula and skill.powerFormula ~= "" then
			createLabel(content, {
				Text = '  <font color="rgb(255,200,100)">Power: ' .. skill.powerFormula .. '</font>',
				Order = order, Padding = 8, Size = UDim2.new(1, 0, 0, 24),
			})
			order = order + 1
		end

		-- Estimated raw damage (server-computed, before defense)
		if skill.estimatedDamage and skill.estimatedDamage > 0 then
			local dmgColor = skill.isHealing and "rgb(100,255,100)" or "rgb(255,130,80)"
			local dmgLabel = skill.isHealing and "Est. Healing" or "Est. Raw Dmg"
			createLabel(content, {
				Text = string.format('  <font color="%s"><b>%s: %d</b> (before defense)</font>', dmgColor, dmgLabel, skill.estimatedDamage),
				Order = order, Padding = 8,
			})
			order = order + 1
		end

		-- Channel time
		if skill.channelTime and skill.channelTime > 0 then
			createLabel(content, {
				Text = string.format('  <font color="rgb(255,220,80)">Channel: %d CT (reduced by DEX)</font>', skill.channelTime),
				Order = order, Padding = 8,
			})
			order = order + 1
		end

		-- Effects
		if skill.effects and skill.effects ~= "" then
			createLabel(content, {
				Text = "  " .. skill.effects,
				Order = order, Padding = 8, Size = UDim2.new(1, 0, 0, 24),
				Color = Theme.Colors.Success,
			})
			order = order + 1
		end

		-- Special rules
		if skill.specialRules and skill.specialRules ~= "" then
			createLabel(content, {
				Text = '  <font color="rgb(200,160,160)">Special: ' .. skill.specialRules .. '</font>',
				Order = order, Padding = 8, Size = UDim2.new(1, 0, 0, 28),
			})
			order = order + 1
		end
	end
end

--------------------------------------------------
-- MAIN PANEL BUILDER
--------------------------------------------------


local function renderTraitsTab(content, data)
	local order = 1

	-- Section helper
	local function sectionHeader(text, color)
		createLabel(content, {
			Text = text,
			Size = UDim2.new(1, 0, 0, 18),
			TextSize = Theme.Text.Body(),
			Font = Theme.Font.PrimaryBold,
			TextColor3 = color or Theme.Colors.TextGold,
			Order = order,
			Padding = 6,
		})
		order = order + 1
	end

	local function traitEntry(name, desc, color)
		createLabel(content, {
			Text = string.format('<font color="rgb(%d,%d,%d)">%s</font>', color.R*255, color.G*255, color.B*255, name),
			Size = UDim2.new(1, 0, 0, 14),
			TextSize = Theme.Text.Body(),
			Font = Theme.Font.PrimaryBold,
			RichText = true,
			Order = order,
			Padding = 2,
		})
		order = order + 1
		if desc and desc ~= "" then
			createLabel(content, {
				Text = "  " .. desc,
				Size = UDim2.new(1, 0, 0, 28),
				TextSize = Theme.Text.Body(),
				TextWrapped = true,
				TextColor3 = Theme.Colors.TextSecondary,
				Order = order,
				Padding = 0,
			})
			order = order + 1
		end
	end

	-- ACTIVE BUFFS
	local buffs = {}
	local debuffs = {}
	for _, s in ipairs(data.statuses or {}) do
		if s.kind == "Buff" then
			table.insert(buffs, s)
		else
			table.insert(debuffs, s)
		end
	end

	sectionHeader("Active Buffs", Theme.Colors.Success)
	if #buffs > 0 then
		for i = #buffs, 1, -1 do
			local b = buffs[i]
			local sid = b.id or "Unknown"
			local def = GameConstants.STATUSES and GameConstants.STATUSES[sid] or nil
			local durStr
			if b.remainingTurns then durStr = b.remainingTurns .. " turns"
			elseif def and def.durationCt then durStr = "CT-based"
			else durStr = "Permanent" end
			local stackStr = b.stacks and b.stacks > 1 and (" x" .. b.stacks) or ""
			local desc = ""
			if def and def.rtMultiplier then desc = "RT x" .. def.rtMultiplier end
			traitEntry(sid .. stackStr .. "  (" .. durStr .. ")", desc, Theme.Colors.Success)
		end
	else
		createLabel(content, {
			Text = "  None", TextSize = Theme.Text.Small(),
			TextColor3 = Theme.Colors.TextDisabled, Order = order, Padding = 0,
		})
		order = order + 1
	end

	-- ACTIVE DEBUFFS
	sectionHeader("Active Debuffs", Theme.Colors.Warning)
	if #debuffs > 0 then
		for i = #debuffs, 1, -1 do
			local d = debuffs[i]
			local sid = d.id or "Unknown"
			local def = GameConstants.STATUSES and GameConstants.STATUSES[sid] or nil
			local durStr
			if d.remainingTurns then durStr = d.remainingTurns .. " turns"
			elseif def and def.durationCt then durStr = "CT-based"
			else durStr = "Permanent" end
			local stackStr = d.stacks and d.stacks > 1 and (" x" .. d.stacks) or ""
			local desc = ""
			if def and def.dotType then desc = "DoT: " .. def.dotType end
			if def and def.blocks then desc = desc .. (desc ~= "" and " | " or "") .. "Blocks actions" end
			traitEntry(sid .. stackStr .. "  (" .. durStr .. ")", desc, Theme.Colors.Warning)
		end
	else
		createLabel(content, {
			Text = "  None", TextSize = Theme.Text.Small(),
			TextColor3 = Theme.Colors.TextDisabled, Order = order, Padding = 0,
		})
		order = order + 1
	end

	-- RACE PASSIVE
	sectionHeader("Race Passive", Theme.Colors.RarityEpic)
	if data.racePassiveName then
		traitEntry(data.racePassiveName, data.racePassiveEffect or "", Theme.Colors.RarityEpic)
	else
		createLabel(content, {
			Text = "  No race assigned", TextSize = Theme.Text.Small(),
			TextColor3 = Theme.Colors.TextDisabled, Order = order, Padding = 0,
		})
		order = order + 1
	end

	-- DOCTRINE
	sectionHeader("Doctrine", Theme.Colors.Info)
	if data.doctrine then
		traitEntry(data.doctrine.name or data.doctrineId or "Unknown",
			data.doctrine.effect or data.doctrine.description or "", Theme.Colors.Info)
	else
		createLabel(content, {
			Text = "  No doctrine assigned", TextSize = Theme.Text.Small(),
			TextColor3 = Theme.Colors.TextDisabled, Order = order, Padding = 0,
		})
		order = order + 1
	end
end

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
	-- Responsive sizing: use viewport-aware dimensions
	local cam = workspace.CurrentCamera
	local vpW = cam and cam.ViewportSize.X or 1920
	local isMobile = vpW < 1024
	local panelW = isMobile and math.min(math.floor(vpW * 0.62), 480) or 420
	local panelH = isMobile and math.min(math.floor((cam and cam.ViewportSize.Y or 480) * 0.85), 400) or 480
	frame.Size = UDim2.new(0, panelW, 0, panelH)
	frame.AnchorPoint = Vector2.new(0, 0)
	frame.Position = UDim2.new(0, 6, 0, 6)
	frame.BackgroundColor3 = Theme.Colors.Background
	frame.BackgroundTransparency = 0.03
	frame.BorderSizePixel = 0
	frame.Parent = gui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

	-- Header (name + combat info)
	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, 0, 0, 22)
	header.BackgroundColor3 = Theme.Colors.Panel
	header.BackgroundTransparency = 0.2
	header.BorderSizePixel = 0
	header.Font = Theme.Font.PrimaryBold
	header.TextSize = Theme.Text.Heading()
	header.TextColor3 = Theme.Colors.TextPrimary
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.RichText = true
	local levelStr = data.level and ("Lv." .. data.level) or ""
	local raceStr = data.raceId or "—"
	header.Text = string.format("  <b>%s</b>  %s  [%s]  %s", data.name or "Unit", levelStr, data.side or "?", raceStr)
	header.Parent = frame
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 8)

	-- Sub-header: HP/MP, AP/RT, coordinates, elevation
	local subHeader = Instance.new("TextLabel")
	subHeader.Size = UDim2.new(1, 0, 0, 16)
	subHeader.Position = UDim2.new(0, 0, 0, 22)
	subHeader.BackgroundColor3 = Theme.Colors.Panel
	subHeader.BackgroundTransparency = 0.3
	subHeader.BorderSizePixel = 0
	subHeader.Font = Theme.Font.Mono
	subHeader.TextSize = Theme.Text.Body()
	subHeader.TextColor3 = Theme.Colors.TextSecondary
	subHeader.TextXAlignment = Enum.TextXAlignment.Left
	subHeader.RichText = true
	local hpStr = string.format("HP %d/%d  MP %d/%d", data.currentHp or 0, data.maxHp or 0, data.currentMp or 0, data.maxMp or 0)
	local apStr = "AP " .. (data.currentAp or 0) .. "  RT " .. (data.remainingRt or 0)
	local coordStr = ""
	if data.tileX and data.tileY then
		-- Elevation: try elevationMap from BVC via _G, or fall back to 1
		local elev = 1
		if type(_G.CTRBLXAI_GetElevation) == "function" then
			elev = _G.CTRBLXAI_GetElevation(data.tileX, data.tileY) or 1
		end
		coordStr = string.format("  Tile(%d,%d) Elev %d", data.tileX, data.tileY, elev)
	end
	subHeader.Text = "  " .. hpStr .. "  " .. apStr .. coordStr
	subHeader.Parent = frame

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 24, 0, 24)
	closeBtn.Position = UDim2.new(1, -28, 0, 7)
	closeBtn.BackgroundColor3 = Theme.Colors.Danger
	closeBtn.Font = Theme.Font.PrimaryBold
	closeBtn.TextSize = Theme.Text.Title()
	closeBtn.TextColor3 = Theme.Colors.TextPrimary
	closeBtn.Text = "✗"
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = frame
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 4)
	closeBtn.MouseButton1Click:Connect(destroyPanel)

	-- Tab bar
	local tabBar = Instance.new("Frame")
	tabBar.Size = UDim2.new(1, 0, 0, 26)
	tabBar.Position = UDim2.new(0, 0, 0, 38)
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
	local contentFrame = Instance.new("ScrollingFrame")
	contentFrame.Name = "TabContent"
	contentFrame.Size = UDim2.new(1, -8, 1, -72)
	contentFrame.Position = UDim2.new(0, 4, 0, 68)
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
		-- Clear content
		for _, child in ipairs(contentFrame:GetChildren()) do
			if child:IsA("GuiObject") then child:Destroy() end
		end
		currentTab = tabName

		if tabName == "stats" then
			renderStatsTab(contentFrame, data)
		elseif tabName == "equipment" then
			renderEquipmentTab(contentFrame, data)
		elseif tabName == "skills" then
			renderSkillsTab(contentFrame, data)
		elseif tabName == "traits" then
			renderTraitsTab(contentFrame, data)
		end

		-- Update canvas size
		task.defer(function()
			contentFrame.CanvasSize = UDim2.new(0, 0, 0, contentLayout.AbsoluteContentSize.Y + 10)
		end)
	end

	-- Create tab buttons
	local tabs = { {"stats", "Stats"}, {"equipment", "Equip"}, {"skills", "Skills"}, {"traits", "Traits"} }
	for _, tab in ipairs(tabs) do
		local tabBtn = Instance.new("TextButton")
		tabBtn.Size = UDim2.new(0, 70, 0, 22)
		tabBtn.BackgroundColor3 = tab[1] == "stats" and Theme.Colors.Surface or Theme.Colors.PanelRaised
		tabBtn.Font = Theme.Font.PrimaryBold
		tabBtn.TextSize = Theme.Text.Body()
		tabBtn.TextColor3 = Theme.Colors.TextPrimary
		tabBtn.Text = tab[2]
		tabBtn.BorderSizePixel = 0
		tabBtn.Parent = tabBar
		Instance.new("UICorner", tabBtn).CornerRadius = UDim.new(0, 4)

		tabBtn.MouseButton1Click:Connect(function()
			-- Update tab button visuals
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
	renderTab("stats")

	-- Click-outside-to-close: detect mouse clicks that land outside the panel frame
	if clickOutsideConn then clickOutsideConn:Disconnect() end
	clickOutsideConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		-- Small delay to avoid closing from the same click that opened it
		task.defer(function()
			if not panelGui or not frame or not frame.Parent then return end
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
