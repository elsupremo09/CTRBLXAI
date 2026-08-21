-- BattleVisualClient.client.lua
-- CTRBLXAI | Slice 3 — Player Input + Timeline Bar
--
-- Structure:
--   1. Services & Variables
--   2. Map helpers
--   3. Highlight management
--   4. Token creation & bar updates
--   5. Floating text
--   6. Timeline bar
--   7. Action bar UI
--   8. Tile selection logic (same pattern as TemplateInspector)
--   9. mouse.Button1Down click handler
--   10. Event handlers (BattleStarted, TurnStarted, etc.)

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()

local BattleEvents = require(
	ReplicatedStorage
		:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("Remotes", 10)
		:WaitForChild("BattleEvents", 10)
)

--------------------------------------------------
-- 1. MAP CONFIGURATION
--------------------------------------------------

local TILE_SIZE        = 5
local TILE_BASE_HEIGHT = 0.6
local ELEVATION_STEP   = 2.5
local MAP_WIDTH        = 8
local MAP_HEIGHT       = 8

local MAP_OFFSET_X = -75 + 11 * TILE_SIZE
local MAP_OFFSET_Z = -50 + 6 * TILE_SIZE

local BATTLE_OFFSET_X = 11
local BATTLE_OFFSET_Y = 6

local elevationMap = nil

local function getElevation(tileX, tileY)
	if not elevationMap then return 1 end
	local row = elevationMap[tileY]
	if row then return row[tileX] or 1 end
	return 1
end

local function tileSurfaceY(elevation)
	return TILE_BASE_HEIGHT + ((elevation or 1) - 1) * ELEVATION_STEP
end

local function tileToWorld(tileX, tileY)
	local elev = getElevation(tileX, tileY)
	return Vector3.new(
		MAP_OFFSET_X + (tileX - 0.5) * TILE_SIZE,
		tileSurfaceY(elev) + 1.0,
		MAP_OFFSET_Z + (tileY - 0.5) * TILE_SIZE
	)
end

local function templateToBattle(templateX, templateY)
	local bx = templateX - BATTLE_OFFSET_X
	local by = templateY - BATTLE_OFFSET_Y
	if bx >= 1 and bx <= MAP_WIDTH and by >= 1 and by <= MAP_HEIGHT then
		return bx, by
	end
	return nil, nil
end

--------------------------------------------------
-- 2. VISUAL SETTINGS & STATE
--------------------------------------------------

local UNIT_RADIUS    = 0.9
local UNIT_HEIGHT    = 1.8
local SIDE_COLORS    = {
	Player = Color3.fromRGB(70, 140, 255),
	Enemy  = Color3.fromRGB(220, 60, 60),
}
local DEFEATED_COLOR  = Color3.fromRGB(80, 80, 80)
local MOVE_TWEEN_TIME = 0.45

local unitTokens   = {}
local unitData     = {}
local visualFolder = Instance.new("Folder")
visualFolder.Name   = "BattleVisuals"
visualFolder.Parent = workspace

local isPlayerTurn    = false
local currentPrompt   = nil
local inputMode       = nil  -- nil, "move", "attack", "skill"
local selectedSkill   = nil
local highlightParts  = {}

--------------------------------------------------
-- 3. HIGHLIGHT MANAGEMENT
--------------------------------------------------

local function clearHighlights()
	for _, part in ipairs(highlightParts) do
		part:Destroy()
	end
	highlightParts = {}
end

local function createTileHighlight(tileX, tileY, color, transparency)
	local elev = getElevation(tileX, tileY)
	local pos = Vector3.new(
		MAP_OFFSET_X + (tileX - 0.5) * TILE_SIZE,
		tileSurfaceY(elev) + 0.15,
		MAP_OFFSET_Z + (tileY - 0.5) * TILE_SIZE
	)

	local part = Instance.new("Part")
	part.Name         = "Highlight_" .. tileX .. "_" .. tileY
	part.Anchored     = true
	part.CanCollide   = false
	part.CanQuery     = false  -- invisible to raycasts so it doesn't block mouse.Target
	part.Size         = Vector3.new(TILE_SIZE * 0.85, 0.15, TILE_SIZE * 0.85)
	part.Position     = pos
	part.Color        = color
	part.Transparency = transparency or 0.5
	part.Material     = Enum.Material.Neon
	part.Parent       = visualFolder

	table.insert(highlightParts, part)
	return part
end

--------------------------------------------------
-- 4. TOKEN CREATION & BAR UPDATES
--------------------------------------------------

local function createHpBar(parent)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HpBillboard"
	billboard.Size = UDim2.new(0, 80, 0, 10)
	billboard.StudsOffset = Vector3.new(0, UNIT_HEIGHT * 0.5 + 0.3, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent = parent

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	bg.BorderSizePixel = 0
	bg.Parent = billboard

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
	fill.BorderSizePixel = 0
	fill.Parent = bg

	local mpBb = Instance.new("BillboardGui")
	mpBb.Size = UDim2.new(0, 60, 0, 4)
	mpBb.StudsOffset = Vector3.new(0, UNIT_HEIGHT * 0.5 + 0.0, 0)
	mpBb.AlwaysOnTop = false
	mpBb.Parent = parent

	local mpBg = Instance.new("Frame")
	mpBg.Size = UDim2.fromScale(1, 1)
	mpBg.BackgroundColor3 = Color3.fromRGB(20, 20, 50)
	mpBg.BorderSizePixel = 0
	mpBg.Parent = mpBb

	local mpFill = Instance.new("Frame")
	mpFill.Name = "Fill"
	mpFill.Size = UDim2.fromScale(1, 1)
	mpFill.BackgroundColor3 = Color3.fromRGB(80, 120, 220)
	mpFill.BorderSizePixel = 0
	mpFill.Parent = mpBg

	local nameBb = Instance.new("BillboardGui")
	nameBb.Size = UDim2.new(0, 120, 0, 16)
	nameBb.StudsOffset = Vector3.new(0, UNIT_HEIGHT * 0.5 + 1.0, 0)
	nameBb.AlwaysOnTop = false
	nameBb.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextSize = 12
	label.Font = Enum.Font.SourceSansBold
	label.TextStrokeTransparency = 0.4
	label.Parent = nameBb

	return fill, label, mpFill
end

local function spawnToken(unit)
	local part = Instance.new("Part")
	part.Name = "Unit_" .. unit.id
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(UNIT_HEIGHT, UNIT_RADIUS * 2, UNIT_RADIUS * 2)
	part.CFrame = CFrame.new(tileToWorld(unit.tileX, unit.tileY)) * CFrame.Angles(0, 0, math.rad(90))
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.CastShadow = true
	part.Color = SIDE_COLORS[unit.side] or Color3.fromRGB(180, 180, 180)
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = visualFolder

	local fill, label, mpFill = createHpBar(part)
	label.Text = unit.name

	unitTokens[unit.id] = { part = part, fill = fill, label = label, mpFill = mpFill }
end

local function updateHpBar(unitId, currentHp, maxHp)
	local token = unitTokens[unitId]
	if not token then return end
	local pct = math.clamp(currentHp / maxHp, 0, 1)
	token.fill.BackgroundColor3 = Color3.fromRGB(math.round(255 * (1 - pct)), math.round(255 * pct), 30)
	token.fill.Size = UDim2.fromScale(pct, 1)
	local name = unitData[unitId] and unitData[unitId].name or unitId
	token.label.Text = string.format("%s %d/%d", name, currentHp, maxHp)
end

local function updateMpBar(unitId, currentMp, maxMp)
	local token = unitTokens[unitId]
	if not token or not token.mpFill or maxMp <= 0 then return end
	token.mpFill.Size = UDim2.fromScale(math.clamp(currentMp / maxMp, 0, 1), 1)
end

--------------------------------------------------
-- 5. FLOATING TEXT
--------------------------------------------------

local function showFloatingText(worldPos, text, color, duration)
	duration = duration or 0.9
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position = worldPos + Vector3.new(0, 2, 0)
	anchor.Parent = visualFolder

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 160, 0, 36)
	bb.AlwaysOnTop = true
	bb.Parent = anchor

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.SourceSansBold
	lbl.TextSize = 20
	lbl.TextColor3 = color
	lbl.TextStrokeTransparency = 0.2
	lbl.Text = text
	lbl.Parent = bb

	TweenService:Create(anchor,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = worldPos + Vector3.new(0, 5, 0) }
	):Play()
	TweenService:Create(lbl,
		TweenInfo.new(duration * 0.6, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, duration * 0.4),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()
	task.delay(duration + 0.1, function() anchor:Destroy() end)
end

--------------------------------------------------
-- 6. CT TIMELINE BAR
--------------------------------------------------

local timelineGui = nil

local function updateTimeline(timeline)
	if timelineGui then timelineGui:Destroy() end
	if not timeline or #timeline == 0 then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "TimelineGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 90
	gui.Parent = player:WaitForChild("PlayerGui")
	timelineGui = gui

	local bar = Instance.new("Frame")
	bar.Name = "TimelineBar"
	bar.Size = UDim2.new(0, math.min(#timeline * 60, 600), 0, 50)
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 8)
	bar.BackgroundColor3 = Color3.fromRGB(10, 10, 20)
	bar.BackgroundTransparency = 0.25
	bar.BorderSizePixel = 0
	bar.Parent = gui

	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 6)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.Parent = bar

	for i, entry in ipairs(timeline) do
		local portrait = Instance.new("Frame")
		portrait.Name = entry.name
		portrait.Size = UDim2.new(0, 44, 0, 42)
		portrait.BackgroundColor3 = entry.side == "Player"
			and Color3.fromRGB(40, 80, 160) or Color3.fromRGB(140, 40, 40)
		portrait.BackgroundTransparency = 0.15
		portrait.BorderSizePixel = 0
		portrait.Parent = bar

		Instance.new("UICorner", portrait).CornerRadius = UDim.new(0, 4)

		if i == 1 then
			portrait.BackgroundTransparency = 0
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(255, 230, 80)
			stroke.Thickness = 2
			stroke.Parent = portrait
		end

		local initial = Instance.new("TextLabel")
		initial.Size = UDim2.fromScale(1, 0.6)
		initial.Position = UDim2.new(0, 0, 0, 2)
		initial.BackgroundTransparency = 1
		initial.Font = Enum.Font.SourceSansBold
		initial.TextSize = 16
		initial.TextColor3 = Color3.fromRGB(255, 255, 255)
		initial.Text = string.sub(entry.name, 1, 3)
		initial.Parent = portrait

		local rtLabel = Instance.new("TextLabel")
		rtLabel.Size = UDim2.new(1, 0, 0, 14)
		rtLabel.Position = UDim2.new(0, 0, 1, -14)
		rtLabel.BackgroundTransparency = 1
		rtLabel.Font = Enum.Font.SourceSans
		rtLabel.TextSize = 10
		rtLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
		rtLabel.Text = i == 1 and "NOW" or tostring(entry.remainingRt)
		rtLabel.Parent = portrait

		if entry.isChanneling then
			local ch = Instance.new("TextLabel")
			ch.Size = UDim2.new(0, 12, 0, 12)
			ch.Position = UDim2.new(1, -12, 0, 0)
			ch.BackgroundTransparency = 1
			ch.Font = Enum.Font.SourceSansBold
			ch.TextSize = 10
			ch.TextColor3 = Color3.fromRGB(255, 200, 60)
			ch.Text = "◎"
			ch.Parent = portrait
		end
	end
end

--------------------------------------------------
-- 7. ACTION BAR UI
--------------------------------------------------

local actionBarGui = nil

local function destroyActionBar()
	if actionBarGui then actionBarGui:Destroy(); actionBarGui = nil end
end

local function createActionBar(prompt)
	destroyActionBar()

	local gui = Instance.new("ScreenGui")
	gui.Name = "ActionBarGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100
	gui.Parent = player:WaitForChild("PlayerGui")
	actionBarGui = gui

	local container = Instance.new("Frame")
	container.Name = "ActionBar"
	container.Size = UDim2.new(0, 720, 0, 90)
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 0.92, 0)
	container.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	container.BackgroundTransparency = 0.15
	container.BorderSizePixel = 0
	container.Active = false
	container.Parent = gui

	Instance.new("UICorner", container).CornerRadius = UDim.new(0, 8)

	local info = Instance.new("TextLabel")
	info.Size = UDim2.new(1, -10, 0, 20)
	info.Position = UDim2.new(0, 5, 0, 2)
	info.BackgroundTransparency = 1
	info.Font = Enum.Font.SourceSansBold
	info.TextSize = 13
	info.TextColor3 = Color3.fromRGB(200, 200, 200)
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.Text = string.format("▶ %s | AP:%d | MP:%d/%d | HP:%d/%d",
		prompt.unitName, prompt.currentAp, prompt.currentMp, prompt.maxMp,
		prompt.currentHp, prompt.maxHp)
	info.Parent = container

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -10, 0, 55)
	row.Position = UDim2.new(0, 5, 0, 25)
	row.BackgroundTransparency = 1
	row.Active = false
	row.Parent = container

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.Padding = UDim.new(0, 6)
	rowLayout.Parent = row

	local function makeButton(name, text, subtext, color, enabled, callback)
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.Size = UDim2.new(0, 115, 0, 55)
		btn.BackgroundColor3 = enabled and color or Color3.fromRGB(40, 40, 40)
		btn.BackgroundTransparency = enabled and 0.1 or 0.5
		btn.BorderSizePixel = 0
		btn.Font = Enum.Font.SourceSansBold
		btn.TextSize = 13
		btn.TextColor3 = enabled and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(100, 100, 100)
		btn.Text = text .. (subtext ~= "" and ("\n" .. subtext) or "")
		btn.TextWrapped = true
		btn.Parent = row
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
		if enabled then btn.MouseButton1Click:Connect(callback) end
		return btn
	end

	makeButton("Move", "⬡ Move", "", Color3.fromRGB(50, 120, 50), #prompt.moveCandidates > 0, function()
		inputMode = "move"; selectedSkill = nil; clearHighlights()
		for _, tile in ipairs(prompt.moveCandidates) do
			createTileHighlight(tile.tileX, tile.tileY, Color3.fromRGB(50, 200, 50), 0.55)
		end
	end)

	makeButton("Attack", "⚔ Attack", "", Color3.fromRGB(180, 60, 60), #prompt.attackTargets > 0, function()
		inputMode = "attack"; selectedSkill = nil; clearHighlights()
		for _, t in ipairs(prompt.attackTargets) do
			createTileHighlight(t.tileX, t.tileY, Color3.fromRGB(255, 60, 60), 0.45)
		end
	end)

	makeButton("Wait", "⏸ Wait", "", Color3.fromRGB(80, 80, 80), true, function()
		clearHighlights(); destroyActionBar(); isPlayerTurn = false; inputMode = nil
		BattleEvents.PlayerCommand:FireServer({ actionType = "Wait" })
	end)

	for _, skill in ipairs(prompt.skills) do
		local canUse = skill.canUse and #skill.targets > 0
		local subtext = string.format("MP:%d R:%d", skill.mpCost, skill.range)
		local color = skill.isHealing and Color3.fromRGB(50, 150, 50) or Color3.fromRGB(80, 80, 180)

		makeButton(skill.id, "✦ " .. skill.name, subtext, color, canUse, function()
			inputMode = "skill"; selectedSkill = skill; clearHighlights()
			local hColor = skill.isHealing and Color3.fromRGB(50, 220, 50) or Color3.fromRGB(180, 80, 255)
			for _, t in ipairs(skill.targets) do
				createTileHighlight(t.tileX, t.tileY, hColor, 0.45)
			end
		end)
	end

	updateTimeline(prompt.timeline)
end

--------------------------------------------------
-- 7b. UNIT INSPECTOR PANEL (left side)
--
-- Shows when any unit tile is clicked:
--   Name, Side, HP, MP, AP, RT, Stats, Skills, Statuses
--------------------------------------------------

local unitInspectorGui = nil

local function showUnitInspector(uid)
	if unitInspectorGui then unitInspectorGui:Destroy() end

	local data = unitData[uid]
	if not data then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "UnitInspectorGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 80
	gui.Parent = player:WaitForChild("PlayerGui")
	unitInspectorGui = gui

	local panel = Instance.new("Frame")
	panel.Name = "UnitPanel"
	panel.Size = UDim2.new(0, 180, 0, 340)
	panel.Position = UDim2.new(0, 12, 0, 80)
	panel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Active = false
	panel.Parent = gui

	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)

	-- Left stripe (colored by side)
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 4, 1, -8)
	stripe.Position = UDim2.new(0, 4, 0, 4)
	stripe.BackgroundColor3 = data.side == "Player"
		and Color3.fromRGB(70, 140, 255) or Color3.fromRGB(220, 60, 60)
	stripe.BorderSizePixel = 0
	stripe.Parent = panel
	Instance.new("UICorner", stripe).CornerRadius = UDim.new(0, 2)

	-- Content label (monospaced RichText)
	local content = Instance.new("TextLabel")
	content.Size = UDim2.new(1, -18, 1, -8)
	content.Position = UDim2.new(0, 14, 0, 4)
	content.BackgroundTransparency = 1
	content.Font = Enum.Font.RobotoMono
	content.TextSize = 12
	content.TextColor3 = Color3.fromRGB(220, 220, 220)
	content.TextXAlignment = Enum.TextXAlignment.Left
	content.TextYAlignment = Enum.TextYAlignment.Top
	content.RichText = true
	content.TextWrapped = true
	content.Parent = panel

	-- Build text
	local nameColor = data.side == "Player" and "rgb(100,180,255)" or "rgb(255,100,100)"
	local lines = {}
	table.insert(lines, string.format('<font color="%s"><b>%s</b></font>', nameColor, data.name))
	table.insert(lines, data.side)
	table.insert(lines, "")
	table.insert(lines, string.format("HP  %d / %d", data.currentHp or 0, data.maxHp or 0))
	table.insert(lines, string.format("MP  %d / %d", data.currentMp or 0, data.maxMp or 0))
	table.insert(lines, string.format("AP  %d   RT %d", data.currentAp or 0, data.remainingRt or 0))
	table.insert(lines, "")

	-- Stats
	if data.stats then
		table.insert(lines, "— STATS —")
		table.insert(lines, string.format("STR %d  AGI %d", data.stats.STR or 0, data.stats.AGI or 0))
		table.insert(lines, string.format("INT %d  VIT %d", data.stats.INT or 0, data.stats.VIT or 0))
		table.insert(lines, string.format("DEX %d  LUK %d", data.stats.DEX or 0, data.stats.LUK or 0))
		table.insert(lines, "")
	end

	-- Skills
	if data.skillIds and #data.skillIds > 0 then
		table.insert(lines, "— SKILLS —")
		for _, sid in ipairs(data.skillIds) do
			-- Show short name (strip "skill_" prefix, replace _ with space)
			local display = string.gsub(sid, "^skill_", "")
			display = string.gsub(display, "_", " ")
			display = display:sub(1,1):upper() .. display:sub(2)
			table.insert(lines, display)
		end
		table.insert(lines, "")
	end

	-- Statuses
	if data.statuses and #data.statuses > 0 then
		table.insert(lines, "— STATUS —")
		for _, s in ipairs(data.statuses) do
			local statusColor = s.id == "Poison" and "rgb(80,200,80)"
				or s.id == "Burn" and "rgb(255,140,40)"
				or "rgb(180,80,255)"
			table.insert(lines, string.format('<font color="%s">%s</font> (%d)', statusColor, s.id, s.remainingTurns or 0))
		end
	end

	content.Text = table.concat(lines, "\n")
end

local function hideUnitInspector()
	if unitInspectorGui then unitInspectorGui:Destroy(); unitInspectorGui = nil end
end

--------------------------------------------------
-- 8. TILE SELECTION LOGIC
--    (Same proven pattern as TemplateInspector)
--------------------------------------------------

local mapFolder = workspace:WaitForChild("TemplateViewerMap", 15)

local function isTemplateTile(instance)
	return instance
		and instance:IsA("BasePart")
		and instance:GetAttribute("IsTemplateTile") == true
end

local function findTileAtPosition(worldPos)
	-- Raycast straight DOWN from the position, include ONLY template tile parts.
	-- This is identical to TemplateInspector's findTileAtPosition.
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	local tileParts = {}
	if mapFolder then
		for _, child in ipairs(mapFolder:GetChildren()) do
			if child:IsA("BasePart") and child:GetAttribute("IsTemplateTile") == true then
				table.insert(tileParts, child)
			end
		end
	end
	rayParams.FilterDescendantsInstances = tileParts
	local origin = Vector3.new(worldPos.X, worldPos.Y + 50, worldPos.Z)
	local result = workspace:Raycast(origin, Vector3.new(0, -100, 0), rayParams)
	return result and result.Instance or nil
end

local function getTileUnderMouse()
	-- Identical logic to TemplateInspector:
	-- 1. Check mouse.Target — if it's a template tile, use it directly
	-- 2. Otherwise, find the tile beneath whatever was clicked
	local target = mouse.Target
	if isTemplateTile(target) then
		return target
	elseif target and target:IsA("BasePart") then
		return findTileAtPosition(target.Position)
	end
	return nil
end

local function tileToBattle(tilePart)
	if not tilePart then return nil, nil end
	local templateX = tilePart:GetAttribute("X")
	local templateY = tilePart:GetAttribute("Y")
	if templateX and templateY then
		return templateToBattle(templateX, templateY)
	end
	return nil, nil
end

--------------------------------------------------
-- 9. CLICK HANDLER
--    Uses mouse.Button1Down (same as TemplateInspector)
--------------------------------------------------

mouse.Button1Down:Connect(function()
	local tilePart = getTileUnderMouse()
	local bx, by = tileToBattle(tilePart)

	-- Always show unit inspector when clicking a tile with a unit
	if bx then
		for uid, data in pairs(unitData) do
			if data.tileX == bx and data.tileY == by and data.isAlive ~= false then
				showUnitInspector(uid)
				break
			end
		end
	end

	-- If not in player input mode, stop here (inspector-only click)
	if not isPlayerTurn or not inputMode then return end
	if not bx then return end

	if inputMode == "move" then
		for _, tile in ipairs(currentPrompt.moveCandidates) do
			if tile.tileX == bx and tile.tileY == by then
				clearHighlights(); destroyActionBar()
				isPlayerTurn = false; inputMode = nil
				BattleEvents.PlayerCommand:FireServer({
					actionType = "Move", tileX = bx, tileY = by, pathCost = tile.pathCost
				})
				return
			end
		end

	elseif inputMode == "attack" then
		for _, t in ipairs(currentPrompt.attackTargets) do
			if t.tileX == bx and t.tileY == by then
				clearHighlights(); destroyActionBar()
				isPlayerTurn = false; inputMode = nil
				BattleEvents.PlayerCommand:FireServer({
					actionType = "Attack", targetId = t.id
				})
				return
			end
		end

	elseif inputMode == "skill" and selectedSkill then
		for _, t in ipairs(selectedSkill.targets) do
			if t.tileX == bx and t.tileY == by then
				clearHighlights(); destroyActionBar()
				isPlayerTurn = false; inputMode = nil
				BattleEvents.PlayerCommand:FireServer({
					actionType = "Skill", skillId = selectedSkill.id, targetId = t.id
				})
				return
			end
		end
	end
end)

--------------------------------------------------
-- 10. EVENT HANDLERS
--------------------------------------------------

BattleEvents.BattleStarted.OnClientEvent:Connect(function(data)
	for _, child in ipairs(visualFolder:GetChildren()) do child:Destroy() end
	unitTokens = {}
	unitData   = {}
	elevationMap = data.elevationMap

	for _, unit in ipairs(data.units) do
		unitData[unit.id] = unit
		spawnToken(unit)
		updateHpBar(unit.id, unit.currentHp, unit.maxHp)
		updateMpBar(unit.id, unit.currentMp or 0, unit.maxMp or 0)
	end
end)

BattleEvents.TurnStarted.OnClientEvent:Connect(function(data)
	if unitData[data.unitId] then
		unitData[data.unitId].statuses = data.statuses
		if data.currentMp then
			unitData[data.unitId].currentMp = data.currentMp
			updateMpBar(data.unitId, data.currentMp, data.maxMp or unitData[data.unitId].maxMp or 0)
		end
	end
	local token = unitTokens[data.unitId]
	if token then
		token.label.TextColor3 = Color3.fromRGB(255, 230, 80)
	end
	showUnitInspector(data.unitId)
end)

BattleEvents.PlayerTurnPrompt.OnClientEvent:Connect(function(prompt)
	currentPrompt = prompt
	isPlayerTurn  = true
	inputMode     = nil
	selectedSkill = nil
	createActionBar(prompt)
end)

BattleEvents.UnitMoved.OnClientEvent:Connect(function(data)
	local token = unitTokens[data.unitId]
	if not token then return end
	if unitData[data.unitId] then
		unitData[data.unitId].tileX = data.tileX
		unitData[data.unitId].tileY = data.tileY
	end
	TweenService:Create(token.part,
		TweenInfo.new(MOVE_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = CFrame.new(tileToWorld(data.tileX, data.tileY)) * CFrame.Angles(0, 0, math.rad(90)) }
	):Play()
end)

BattleEvents.UnitActed.OnClientEvent:Connect(function(data)
	updateHpBar(data.targetId, data.targetHp, data.targetMaxHp)
	if unitData[data.targetId] then unitData[data.targetId].currentHp = data.targetHp end

	local targetToken = unitTokens[data.targetId]
	if targetToken then
		if data.skillName then
			local actorToken = unitTokens[data.actorId]
			if actorToken then
				showFloatingText(actorToken.part.Position, "✦ " .. data.skillName, Color3.fromRGB(255, 210, 60), 1.1)
			end
		end
		showFloatingText(targetToken.part.Position, "-" .. data.damage, Color3.fromRGB(255, 80, 80))
	end
end)

BattleEvents.DotDamage.OnClientEvent:Connect(function(data)
	updateHpBar(data.unitId, data.currentHp, data.maxHp)
	if unitData[data.unitId] then unitData[data.unitId].currentHp = data.currentHp end
	local token = unitTokens[data.unitId]
	if token then
		local color = data.statusId == "Poison" and Color3.fromRGB(60, 200, 60)
			or data.statusId == "Burn" and Color3.fromRGB(255, 140, 40)
			or Color3.fromRGB(200, 80, 200)
		showFloatingText(token.part.Position, "-" .. data.damage .. " " .. data.statusId, color)
	end
end)

BattleEvents.HealingApplied.OnClientEvent:Connect(function(data)
	updateHpBar(data.targetId, data.targetHp, data.targetMaxHp)
	if unitData[data.targetId] then unitData[data.targetId].currentHp = data.targetHp end
	local targetToken = unitTokens[data.targetId]
	if targetToken then
		if data.skillName then
			local actorToken = unitTokens[data.actorId]
			if actorToken then
				showFloatingText(actorToken.part.Position, "✦ " .. data.skillName, Color3.fromRGB(80, 220, 80), 1.1)
			end
		end
		showFloatingText(targetToken.part.Position, "+" .. data.amount, Color3.fromRGB(80, 220, 80))
	end
end)

BattleEvents.StatusApplied.OnClientEvent:Connect(function(data)
	local token = unitTokens[data.unitId]
	if token then
		local color = data.statusId == "Poison" and Color3.fromRGB(80, 200, 80)
			or data.statusId == "Burn" and Color3.fromRGB(255, 140, 40)
			or Color3.fromRGB(180, 80, 255)
		showFloatingText(token.part.Position + Vector3.new(0, 1, 0), "▼ " .. data.statusId, color, 1.2)
	end
end)

BattleEvents.StatusExpired.OnClientEvent:Connect(function(data)
	local token = unitTokens[data.unitId]
	if token then
		showFloatingText(token.part.Position + Vector3.new(0, 1, 0), "✗ " .. data.statusId, Color3.fromRGB(180, 180, 180), 1.2)
	end
end)

BattleEvents.UnitDefeated.OnClientEvent:Connect(function(data)
	local token = unitTokens[data.unitId]
	if not token then return end
	if unitData[data.unitId] then unitData[data.unitId].isAlive = false end
	token.part.Color = DEFEATED_COLOR
	token.part.Transparency = 0.5
end)

BattleEvents.TurnEnded.OnClientEvent:Connect(function(data)
	local token = unitTokens[data.unitId]
	if token then token.label.TextColor3 = Color3.fromRGB(255, 255, 255) end
	if data.currentMp and unitData[data.unitId] then
		unitData[data.unitId].currentMp = data.currentMp
		updateMpBar(data.unitId, data.currentMp, unitData[data.unitId].maxMp or 0)
	end
	clearHighlights()
	destroyActionBar()
	isPlayerTurn = false
	inputMode = nil
end)

BattleEvents.BattleEnded.OnClientEvent:Connect(function(data)
	clearHighlights()
	destroyActionBar()
	isPlayerTurn = false
	if timelineGui then timelineGui:Destroy(); timelineGui = nil end

	local gui = Instance.new("ScreenGui")
	gui.Name = "BattleResultGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 110
	gui.Parent = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 500, 0, 100)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Parent = gui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.SourceSansBold
	lbl.TextSize = 42
	lbl.TextStrokeTransparency = 0.3
	lbl.Parent = frame
	if data.winner == "Player" then
		lbl.Text = "⚔  VICTORY"
		lbl.TextColor3 = Color3.fromRGB(100, 220, 100)
	else
		lbl.Text = "☠  DEFEAT"
		lbl.TextColor3 = Color3.fromRGB(220, 80, 80)
	end
end)
