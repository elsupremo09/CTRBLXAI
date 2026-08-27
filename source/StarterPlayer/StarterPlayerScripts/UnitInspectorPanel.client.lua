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
	lbl.BackgroundColor3 = props.BgColor or Color3.fromRGB(20, 20, 30)
	lbl.Font = props.Font or Enum.Font.SourceSans
	lbl.TextSize = props.TextSize or 11
	lbl.TextColor3 = props.Color or Color3.fromRGB(200, 200, 200)
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
		BgColor = Color3.fromRGB(30, 30, 45),
		Font = Enum.Font.SourceSansBold,
		TextSize = 11,
		Color = Color3.fromRGB(180, 180, 220),
		Order = order,
	})
end

--------------------------------------------------
-- TAB: STATS
--------------------------------------------------

local function renderStatsTab(content, data)
	local order = 1

	-- Primary stats
	createSection(content, "PRIMARY STATS", order); order = order + 1
	local ps = data.primaryStats or {}
	for _, stat in ipairs({"STR", "AGI", "INT", "VIT", "DEX", "LUK"}) do
		local info = ps[stat]
		local total = info and info.total or 0
		local base = info and info.base or total
		local bonus = info and info.bonus or 0
		local bonusStr = bonus > 0 and string.format(' <font color="rgb(100,255,100)">+%d</font>', bonus)
			or bonus < 0 and string.format(' <font color="rgb(255,100,100)">%d</font>', bonus) or ""
		createLabel(content, {
			Text = string.format("  %s: <b>%d</b>%s  (base %d)", stat, total, bonusStr, base),
			Order = order, Padding = 4,
		})
		order = order + 1
	end

	-- Derived stats by category
	local derived = data.derivedStats or {}
	local categories = {
		{ "COMBAT", {"attackPower", "effectiveWt", "precision", "evasiveness", "basicAttackRt"} },
		{ "DEFENSE", {"defensePower", "debuffResist", "rtDelayResist", "stability"} },
		{ "RESOURCES", {"maxHp", "maxMp", "mpRegen"} },
		{ "MOVEMENT", {"movementRange", "jump", "force"} },
		{ "SKILLS", {"skillPotency", "bonusSkillRange", "channelReduction", "healEfficiency"} },
		{ "OTHER", {"discoveryRadius", "unitFortune", "startingRt"} },
	}

	for _, cat in ipairs(categories) do
		createSection(content, cat[1], order); order = order + 1
		for _, key in ipairs(cat[2]) do
			local val = derived[key]
			if val then
				local meta = GameConstants.STAT_META and GameConstants.STAT_META[key]
				local label = meta and meta.label or key
				local suffix = meta and meta.unit or ""
				createLabel(content, {
					Text = string.format("  %s: <b>%s%s</b>", label, tostring(val), suffix),
					Order = order, Padding = 4,
				})
				order = order + 1
			end
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
				Order = order, Color = Color3.fromRGB(120, 120, 120),
			})
			order = order + 1
		end
	end

	-- Doctrine
	createSection(content, "📖 DOCTRINE", order); order = order + 1
	if data.doctrine then
		createLabel(content, {
			Text = "  " .. (data.doctrine.name or data.doctrineId or "Unknown"),
			Order = order, Font = Enum.Font.SourceSansBold,
			Color = Color3.fromRGB(220, 200, 100),
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
				Color = Color3.fromRGB(160, 200, 160),
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
	frame.Size = UDim2.new(0, 320, 0, 480)
	frame.AnchorPoint = Vector2.new(0, 0)
	frame.Position = UDim2.new(0, 10, 0, 80)
	frame.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
	frame.BackgroundTransparency = 0.03
	frame.BorderSizePixel = 0
	frame.Parent = gui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

	-- Header (name, HP, MP)
	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, 0, 0, 38)
	header.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	header.BackgroundTransparency = 0.2
	header.BorderSizePixel = 0
	header.Font = Enum.Font.SourceSansBold
	header.TextSize = 13
	header.TextColor3 = Color3.fromRGB(255, 240, 200)
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.RichText = true
	header.Text = string.format("  <b>%s</b>  [%s]", data.name or "Unit", data.side or "?")
	header.Parent = frame
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 8)

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 24, 0, 24)
	closeBtn.Position = UDim2.new(1, -28, 0, 7)
	closeBtn.BackgroundColor3 = Color3.fromRGB(80, 30, 30)
	closeBtn.Font = Enum.Font.SourceSansBold
	closeBtn.TextSize = 14
	closeBtn.TextColor3 = Color3.fromRGB(255, 200, 200)
	closeBtn.Text = "✗"
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent = frame
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 4)
	closeBtn.MouseButton1Click:Connect(destroyPanel)

	-- Tab bar
	local tabBar = Instance.new("Frame")
	tabBar.Size = UDim2.new(1, 0, 0, 26)
	tabBar.Position = UDim2.new(0, 0, 0, 38)
	tabBar.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
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
		end

		-- Update canvas size
		task.defer(function()
			contentFrame.CanvasSize = UDim2.new(0, 0, 0, contentLayout.AbsoluteContentSize.Y + 10)
		end)
	end

	-- Create tab buttons
	local tabs = { {"stats", "Stats"}, {"equipment", "Equipment"}, {"skills", "Skills"} }
	for _, tab in ipairs(tabs) do
		local tabBtn = Instance.new("TextButton")
		tabBtn.Size = UDim2.new(0, 90, 0, 22)
		tabBtn.BackgroundColor3 = tab[1] == "stats" and Color3.fromRGB(50, 60, 80) or Color3.fromRGB(30, 30, 40)
		tabBtn.Font = Enum.Font.SourceSansBold
		tabBtn.TextSize = 12
		tabBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
		tabBtn.Text = tab[2]
		tabBtn.BorderSizePixel = 0
		tabBtn.Parent = tabBar
		Instance.new("UICorner", tabBtn).CornerRadius = UDim.new(0, 4)

		tabBtn.MouseButton1Click:Connect(function()
			-- Update tab button visuals
			for _, child in ipairs(tabBar:GetChildren()) do
				if child:IsA("TextButton") then
					child.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
				end
			end
			tabBtn.BackgroundColor3 = Color3.fromRGB(50, 60, 80)
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
