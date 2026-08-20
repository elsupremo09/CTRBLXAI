-- BattleVisualClient.client.lua
-- CTRBLXAI | Slice 1 Visual
--
-- Listens to BattleEvents fired by the server and renders:
--   - Unit tokens (colored cylinders) on the correct tiles
--   - HP bars above each unit (BillboardGui)
--   - A floating damage number when a unit is hit
--   - A result banner when the battle ends
--
-- RULE: This script only displays. It never sends commands to the server
-- and never modifies any game state.

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local player = Players.LocalPlayer

--------------------------------------------------
-- WAIT FOR REMOTES
--------------------------------------------------

local BattleEvents = require(
	ReplicatedStorage
		:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("Remotes", 10)
		:WaitForChild("BattleEvents", 10)
)

--------------------------------------------------
-- MAP CONFIGURATION
-- Must match the values in Main.server.lua.
-- The client doesn't generate the map — it just
-- needs to know tile size to position tokens.
--------------------------------------------------

local TILE_SIZE   = 5    -- studs per tile (matches TemplateViewer)
local TILE_HEIGHT = 0.6  -- height of a tile Part

-- Where tile (1,1) starts in world space.
-- TemplateViewer centers the map at (0, 0).
-- Map is 8x8 for Slice 1.
local MAP_WIDTH   = 8
local MAP_HEIGHT  = 8

local MAP_OFFSET_X = -(MAP_WIDTH  * TILE_SIZE / 2)
local MAP_OFFSET_Z = -(MAP_HEIGHT * TILE_SIZE / 2)

local function tileToWorld(tileX, tileY)
	return Vector3.new(
		MAP_OFFSET_X + (tileX - 0.5) * TILE_SIZE,
		TILE_HEIGHT + 1.0,   -- sit on top of tile + small lift
		MAP_OFFSET_Z + (tileY - 0.5) * TILE_SIZE
	)
end

--------------------------------------------------
-- VISUAL SETTINGS
--------------------------------------------------

local UNIT_RADIUS    = 0.9   -- cylinder radius
local UNIT_HEIGHT    = 1.8   -- cylinder height

local SIDE_COLORS = {
	Player = Color3.fromRGB(70, 140, 255),   -- blue
	Enemy  = Color3.fromRGB(220, 60, 60),    -- red
}

local DEFEATED_COLOR = Color3.fromRGB(80, 80, 80)

local HP_BAR_HEIGHT  = 0.3   -- studs, height of the green bar
local HP_BAR_WIDTH   = TILE_SIZE * 0.8

local MOVE_TWEEN_TIME   = 0.45
local DAMAGE_FLOAT_TIME = 0.9

--------------------------------------------------
-- STATE
--   unitTokens[unitId] = { part, hpBar, hpFill, label }
--   unitData[unitId]   = serialized unit table from server
--------------------------------------------------

local unitTokens = {}
local unitData   = {}

-- Container folder so we don't pollute workspace root.
local visualFolder = Instance.new("Folder")
visualFolder.Name   = "BattleVisuals"
visualFolder.Parent = workspace

--------------------------------------------------
-- TOKEN CREATION
--------------------------------------------------

local function createHpBar(parent, maxHp)
	-- HP bar billboard — sits just above the cylinder top
	local billboard = Instance.new("BillboardGui")
	billboard.Name        = "HpBillboard"
	billboard.Size        = UDim2.new(0, 80, 0, 10)
	billboard.StudsOffset = Vector3.new(0, UNIT_HEIGHT * 0.5 + 0.3, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent      = parent

	-- Background (dark bar)
	local bg = Instance.new("Frame")
	bg.Name                  = "BG"
	bg.Size                  = UDim2.fromScale(1, 1)
	bg.BackgroundColor3      = Color3.fromRGB(40, 40, 40)
	bg.BorderSizePixel        = 0
	bg.Parent                = billboard

	-- Green fill
	local fill = Instance.new("Frame")
	fill.Name                = "Fill"
	fill.Size                = UDim2.fromScale(1, 1)
	fill.BackgroundColor3    = Color3.fromRGB(80, 200, 80)
	fill.BorderSizePixel      = 0
	fill.Parent               = bg

	-- Name label — separate BillboardGui sitting higher than the HP bar
	local nameBillboard = Instance.new("BillboardGui")
	nameBillboard.Name        = "NameBillboard"
	nameBillboard.Size        = UDim2.new(0, 100, 0, 16)
	nameBillboard.StudsOffset = Vector3.new(0, UNIT_HEIGHT * 0.5 + 1.0, 0)
	nameBillboard.AlwaysOnTop = false
	nameBillboard.Parent      = parent

	local label = Instance.new("TextLabel")
	label.Name               = "NameLabel"
	label.Size               = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3         = Color3.fromRGB(255, 255, 255)
	label.TextSize           = 12
	label.Font               = Enum.Font.SourceSansBold
	label.TextStrokeTransparency = 0.4
	label.Parent             = nameBillboard

	return billboard, fill, label
end

local function spawnToken(unit)
	local part = Instance.new("Part")
	part.Name      = "Unit_" .. unit.id
	part.Shape     = Enum.PartType.Cylinder
	part.Size      = Vector3.new(UNIT_HEIGHT, UNIT_RADIUS * 2, UNIT_RADIUS * 2)
	part.CFrame    = CFrame.new(tileToWorld(unit.tileX, unit.tileY))
		* CFrame.Angles(0, 0, math.rad(90))  -- stand the cylinder upright
	part.Anchored  = true
	part.CanCollide = false
	part.CanQuery   = false   -- mouse clicks pass through to the tile below
	part.CastShadow = true
	part.Color     = SIDE_COLORS[unit.side] or Color3.fromRGB(180, 180, 180)
	part.Material  = Enum.Material.SmoothPlastic
	part.Parent    = visualFolder

	local billboard, fill, label = createHpBar(part, unit.maxHp)
	label.Text = unit.name

	unitTokens[unit.id] = {
		part      = part,
		billboard = billboard,
		fill      = fill,
		label     = label,
	}
end

--------------------------------------------------
-- HP BAR UPDATE
--------------------------------------------------

local function updateHpBar(unitId, currentHp, maxHp)
	local token = unitTokens[unitId]
	if not token then return end

	local pct = math.clamp(currentHp / maxHp, 0, 1)

	-- Color shifts green → yellow → red as HP falls
	local r = math.round(255 * (1 - pct))
	local g = math.round(255 * pct)
	token.fill.BackgroundColor3 = Color3.fromRGB(r, g, 30)
	token.fill.Size = UDim2.fromScale(pct, 1)

	token.label.Text = string.format(
		"%s  %d/%d",
		unitData[unitId] and unitData[unitId].name or unitId,
		currentHp,
		maxHp
	)
end

--------------------------------------------------
-- FLOATING SKILL LABEL
-- Shows the skill name above the attacker when a skill is used.
-- Floats upward and fades out, same style as damage numbers
-- but in a golden/skill color so it reads differently.
--------------------------------------------------

local SKILL_FLOAT_TIME = 1.1

local function showSkillLabel(worldPos, skillName)
	local anchor = Instance.new("Part")
	anchor.Anchored    = true
	anchor.CanCollide  = false
	anchor.CanQuery    = false
	anchor.Transparency = 1
	anchor.Size        = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position    = worldPos + Vector3.new(0, 2.5, 0)
	anchor.Parent      = visualFolder

	local billboard = Instance.new("BillboardGui")
	billboard.Size        = UDim2.new(0, 160, 0, 28)
	billboard.StudsOffset = Vector3.new(0, 0, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent      = anchor

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font                   = Enum.Font.SourceSansBold
	label.TextSize               = 18
	label.TextColor3             = Color3.fromRGB(255, 210, 60)  -- gold
	label.TextStrokeTransparency = 0.2
	label.Text                   = "✦ " .. skillName
	label.Parent                 = billboard

	TweenService:Create(anchor,
		TweenInfo.new(SKILL_FLOAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = anchor.Position + Vector3.new(0, 3.5, 0) }
	):Play()
	TweenService:Create(label,
		TweenInfo.new(SKILL_FLOAT_TIME * 0.6, Enum.EasingStyle.Linear,
			Enum.EasingDirection.In, 0, false, SKILL_FLOAT_TIME * 0.4),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()

	task.delay(SKILL_FLOAT_TIME + 0.1, function()
		anchor:Destroy()
	end)
end

--------------------------------------------------
-- FLOATING DAMAGE NUMBER
--------------------------------------------------

local function showDamageNumber(worldPos, damage, isCrit)
	local billboard = Instance.new("BillboardGui")
	billboard.Size        = UDim2.new(0, 80, 0, 36)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee     = nil

	-- Attach to a temporary invisible part at the hit location
	local anchor = Instance.new("Part")
	anchor.Anchored   = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size       = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position   = worldPos
	anchor.Parent     = visualFolder

	billboard.Parent  = anchor

	local label = Instance.new("TextLabel")
	label.Size                  = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font                  = Enum.Font.SourceSansBold
	label.TextSize              = isCrit and 28 or 22
	label.TextColor3            = isCrit
		and Color3.fromRGB(255, 220, 0)
		or  Color3.fromRGB(255, 80,  80)
	label.TextStrokeTransparency = 0.2
	label.Text                  = "-" .. tostring(damage)
	label.Parent                = billboard

	-- Float upward and fade out
	local tweenUp = TweenService:Create(
		anchor,
		TweenInfo.new(DAMAGE_FLOAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = worldPos + Vector3.new(0, 4, 0) }
	)
	local tweenFade = TweenService:Create(
		label,
		TweenInfo.new(DAMAGE_FLOAT_TIME * 0.7, Enum.EasingStyle.Linear,
			Enum.EasingDirection.In, 0, false, DAMAGE_FLOAT_TIME * 0.3),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	)

	tweenUp:Play()
	tweenFade:Play()

	task.delay(DAMAGE_FLOAT_TIME + 0.1, function()
		anchor:Destroy()
	end)
end

--------------------------------------------------
-- RESULT BANNER
--------------------------------------------------

local function showResultBanner(winner)
	local gui = Instance.new("ScreenGui")
	gui.Name          = "BattleResultGui"
	gui.ResetOnSpawn  = false
	gui.Parent        = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Size                = UDim2.new(0, 500, 0, 100)
	frame.AnchorPoint         = Vector2.new(0.5, 0.5)
	frame.Position            = UDim2.new(0.5, 0, 0.5, 0)
	frame.BackgroundColor3    = Color3.fromRGB(10, 10, 10)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel      = 0
	frame.Parent              = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent       = frame

	local label = Instance.new("TextLabel")
	label.Size                  = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font                  = Enum.Font.SourceSansBold
	label.TextSize              = 42
	label.TextStrokeTransparency = 0.3

	if winner == "Player" then
		label.Text       = "⚔  VICTORY"
		label.TextColor3 = Color3.fromRGB(100, 220, 100)
	else
		label.Text       = "☠  DEFEAT"
		label.TextColor3 = Color3.fromRGB(220, 80, 80)
	end

	label.Parent = frame

	-- Fade in
	frame.BackgroundTransparency = 1
	label.TextTransparency       = 1
	label.TextStrokeTransparency = 1

	TweenService:Create(frame,
		TweenInfo.new(0.5), { BackgroundTransparency = 0.2 }
	):Play()
	TweenService:Create(label,
		TweenInfo.new(0.5), { TextTransparency = 0, TextStrokeTransparency = 0.3 }
	):Play()
end

--------------------------------------------------
-- TURN INDICATOR
--------------------------------------------------

local activeTurnLabel = nil

local function showTurnIndicator(unitId, ct)
	local unit = unitData[unitId]
	if not unit then return end

	-- Update the unit's name label to show it's active
	local token = unitTokens[unitId]
	if token then
		token.label.Text = string.format(
			"▶ %s  %d/%d",
			unit.name,
			unit.currentHp or unit.maxHp,
			unit.maxHp
		)
		token.label.TextColor3 = Color3.fromRGB(255, 230, 80)
	end
end

local function clearTurnIndicator(unitId)
	local unit = unitData[unitId]
	local token = unitTokens[unitId]
	if not token or not unit then return end

	token.label.TextColor3 = Color3.fromRGB(255, 255, 255)
	token.label.Text = string.format(
		"%s  %d/%d",
		unit.name,
		unit.currentHp or unit.maxHp,
		unit.maxHp
	)
end

--------------------------------------------------
-- EVENT HANDLERS
--------------------------------------------------

BattleEvents.BattleStarted.OnClientEvent:Connect(function(data)
	-- Clear any leftover visuals from a previous run.
	for _, child in ipairs(visualFolder:GetChildren()) do
		child:Destroy()
	end
	unitTokens = {}
	unitData   = {}

	for _, unit in ipairs(data.units) do
		unitData[unit.id] = unit
		spawnToken(unit)
		updateHpBar(unit.id, unit.currentHp, unit.maxHp)
	end
end)

BattleEvents.TurnStarted.OnClientEvent:Connect(function(data)
	showTurnIndicator(data.unitId, data.ct)
end)

BattleEvents.UnitMoved.OnClientEvent:Connect(function(data)
	local token = unitTokens[data.unitId]
	if not token then return end

	-- Update stored position
	if unitData[data.unitId] then
		unitData[data.unitId].tileX = data.tileX
		unitData[data.unitId].tileY = data.tileY
	end

	-- Smooth glide to new tile
	TweenService:Create(
		token.part,
		TweenInfo.new(MOVE_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = CFrame.new(tileToWorld(data.tileX, data.tileY))
			* CFrame.Angles(0, 0, math.rad(90)) }
	):Play()
end)

BattleEvents.UnitActed.OnClientEvent:Connect(function(data)
	-- Update HP bar on the target
	updateHpBar(data.targetId, data.targetHp, data.targetMaxHp)

	-- Update cached HP
	if unitData[data.targetId] then
		unitData[data.targetId].currentHp = data.targetHp
	end

	-- Show floating damage number above the target
	local targetToken = unitTokens[data.targetId]
	if targetToken then
		-- If this was a skill, show the skill name above the attacker first.
		if data.skillName then
			local actorToken = unitTokens[data.actorId]
			if actorToken then
				showSkillLabel(actorToken.part.Position, data.skillName)
			end
		end

		showDamageNumber(
			targetToken.part.Position,
			data.damage,
			false
		)
	end
end)

BattleEvents.UnitDefeated.OnClientEvent:Connect(function(data)
	local token = unitTokens[data.unitId]
	if not token then return end

	-- Tint the token grey and sink it into the ground
	token.part.Color = DEFEATED_COLOR

	TweenService:Create(
		token.part,
		TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = token.part.CFrame * CFrame.new(0, -UNIT_HEIGHT * 0.8, 0),
		  Transparency = 0.6 }
	):Play()

	-- Grey out the HP bar
	if token.fill then
		token.fill.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		token.fill.Size = UDim2.fromScale(0, 1)
	end
	if token.label then
		token.label.Text = (unitData[data.unitId] and unitData[data.unitId].name or data.unitId)
			.. "  ✝"
		token.label.TextColor3 = Color3.fromRGB(160, 160, 160)
	end

	if unitData[data.unitId] then
		unitData[data.unitId].isAlive = false
	end
end)

BattleEvents.TurnEnded.OnClientEvent:Connect(function(data)
	clearTurnIndicator(data.unitId)
end)

BattleEvents.BattleEnded.OnClientEvent:Connect(function(data)
	-- Sync all final unit states
	for _, unit in ipairs(data.units) do
		unitData[unit.id] = unit
		updateHpBar(unit.id, unit.currentHp, unit.maxHp)
	end

	showResultBanner(data.winner)
end)

--------------------------------------------------
-- UNIT STAT INSPECTOR PANEL
-- Click any unit cylinder to select it.
-- A panel slides in from the right showing all stats.
-- Click anywhere else (or the same unit) to deselect.
--------------------------------------------------

local Camera = workspace.CurrentCamera

-- The ScreenGui that holds the panel
local inspectorGui = Instance.new("ScreenGui")
inspectorGui.Name         = "UnitInspectorGui"
inspectorGui.ResetOnSpawn = false
inspectorGui.Parent       = player:WaitForChild("PlayerGui")

-- Outer panel frame — slides in from the right
local panel = Instance.new("Frame")
panel.Name                = "UnitPanel"
panel.Size                = UDim2.new(0, 220, 0, 340)
panel.AnchorPoint         = Vector2.new(0, 0.5)
panel.Position            = UDim2.new(0, 12, 0.5, 0)  -- left side, always on screen
panel.BackgroundColor3    = Color3.fromRGB(15, 15, 20)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel     = 0
panel.Parent              = inspectorGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent       = panel

-- Colored side stripe (changes with unit side)
local stripe = Instance.new("Frame")
stripe.Name              = "Stripe"
stripe.Size              = UDim2.new(0, 4, 1, 0)
stripe.Position          = UDim2.new(0, 0, 0, 0)
stripe.BackgroundColor3  = Color3.fromRGB(70, 140, 255)
stripe.BorderSizePixel   = 0
stripe.Parent            = panel

local stripeCorner = Instance.new("UICorner")
stripeCorner.CornerRadius = UDim.new(0, 8)
stripeCorner.Parent       = stripe

-- Content label (we'll set its text when a unit is selected)
local content = Instance.new("TextLabel")
content.Name                 = "Content"
content.Size                 = UDim2.new(1, -16, 1, -12)
content.Position             = UDim2.new(0, 12, 0, 8)
content.BackgroundTransparency = 1
content.Font                 = Enum.Font.Code
content.TextSize             = 13
content.TextColor3           = Color3.fromRGB(220, 220, 220)
content.TextXAlignment       = Enum.TextXAlignment.Left
content.TextYAlignment       = Enum.TextYAlignment.Top
content.TextWrapped          = true
content.RichText             = true
content.Text                 = "<font color='#666666'>Click a unit or tile\nto inspect.</font>"
content.Parent               = panel

local selectedUnitId = nil
local _isSelectingUnit = false  -- recursion guard

-- Panel is always visible — no slide needed.
-- This stub is kept so existing call sites don't break.
local function slidePanel(_visible) end

local function buildStatText(unit)
	-- Side color tag for RichText
	local sideColor = unit.side == "Player" and "#4A8CFF" or "#DC3C3C"
	local aliveTag  = unit.isAlive and "" or "  <font color='#888888'>✝ DEFEATED</font>"

	local s = unit.stats or {}

	-- Derive display values from stats using the DB formulas
	local hp    = unit.maxHp
	local moveR = 3 + math.floor((s.AGI or 0) / 60)
	local jump  = 1 + math.floor((s.DEX or 0) / 60)

	-- Skill display name lookup (Slice 1 only two skills)
	local skillNames = {
		skill_power_strike  = "Power Strike",
		skill_precise_shot  = "Precise Shot",
	}
	local skillLabel = unit.skillId
		and (skillNames[unit.skillId] or unit.skillId)
		or  "—"

	return string.format(
		"<font color='%s'><b>%s</b></font>%s\n" ..
		"<font color='#888888'>%s</font>\n\n" ..
		"<b>HP</b>   %d / %d\n" ..
		"<b>AP</b>   %d   <font color='#888888'>RT %d</font>\n\n" ..
		"<font color='#AAAAAA'>── STATS ──</font>\n" ..
		"STR  %2d   AGI  %2d\n" ..
		"INT  %2d   VIT  %2d\n" ..
		"DEX  %2d   LUK  %2d\n\n" ..
		"<font color='#AAAAAA'>── DERIVED ──</font>\n" ..
		"Move  %d   Jump  %d\n\n" ..
		"<font color='#AAAAAA'>── SKILL ──</font>\n" ..
		"%s",
		sideColor, unit.name, aliveTag,
		unit.side,
		unit.currentHp, hp,
		unit.currentAp or 0, unit.remainingRt or 0,
		s.STR or 0, s.AGI or 0,
		s.INT or 0, s.VIT or 0,
		s.DEX or 0, s.LUK or 0,
		moveR, jump,
		skillLabel
	)
end

local function selectUnit(unitId)
	local unit = unitData[unitId]
	if not unit then return end

	selectedUnitId = unitId

	-- Update stripe color to match side
	stripe.BackgroundColor3 = SIDE_COLORS[unit.side]
		or Color3.fromRGB(180, 180, 180)

	content.Text = buildStatText(unit)

	-- Tell TemplateInspector to select the tile this unit is standing on.
	-- Only call outward if we weren't triggered by a tile selection (breaks recursion).
	if not _isSelectingUnit and type(_G.CTRBLXAI_SelectTileAt) == "function" then
		_G.CTRBLXAI_SelectTileAt(unit.tileX, unit.tileY)
	end
end

-- Publish to _G so TemplateInspector can call us when a tile is clicked.
-- selectUnitAtTile: given tile grid coords, selects the unit standing there (if any).
_G.CTRBLXAI_SelectUnitAtTile = function(tileX, tileY)
	_isSelectingUnit = true
	for id, data in pairs(unitData) do
		if data.isAlive
			and data.tileX == tileX
			and data.tileY == tileY
		then
			selectUnit(id)
			_isSelectingUnit = false
			return
		end
	end
	-- No unit on this tile — show placeholder.
	selectedUnitId = nil
	stripe.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
	content.Text = "<font color='#666666'>No unit on\nthis tile.</font>"
	_isSelectingUnit = false
end

-- World-position-based bridge: TemplateInspector passes the tile's world X/Z.
-- We find the unit whose token is closest to that position (within half a tile).
_G.CTRBLXAI_SelectUnitNearWorldPos = function(worldX, worldZ)
	local TILE_SIZE = 5
	local MAX_DIST_SQ = (TILE_SIZE * 0.6) ^ 2  -- must be within 60% of a tile

	_isSelectingUnit = true
	local bestId   = nil
	local bestDist = MAX_DIST_SQ
	for id, data in pairs(unitData) do
		if data.isAlive then
			local token = unitTokens[id]
			if token and token.part then
				local dx = token.part.Position.X - worldX
				local dz = token.part.Position.Z - worldZ
				local dist = dx * dx + dz * dz
				if dist < bestDist then
					bestDist = dist
					bestId   = id
				end
			end
		end
	end
	if bestId then
		selectUnit(bestId)
	else
		selectedUnitId = nil
		stripe.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
		content.Text = "<font color='#666666'>No unit on\nthis tile.</font>"
	end
	_isSelectingUnit = false
end

-- Click detection — fire a ray from the mouse into the world
local mouse = player:GetMouse()

mouse.Button1Down:Connect(function()
	local target = mouse.Target
	if not target then
		selectedUnitId = nil
		slidePanel(false)
		return
	end

	-- Check if the clicked part is a unit token
	-- Token names are "Unit_<unitId>"
	local name = target.Name
	if string.sub(name, 1, 5) == "Unit_" then
		local unitId = string.sub(name, 6)
		selectUnit(unitId)
	else
		selectedUnitId = nil
		slidePanel(false)
	end
end)

-- Keep the panel content live — refresh on every UnitActed event
-- so HP and AP shown in the panel stay current while selected.
BattleEvents.UnitActed.OnClientEvent:Connect(function(data)
	if selectedUnitId then
		local unit = unitData[selectedUnitId]
		if unit then
			content.Text = buildStatText(unit)
		end
	end
end)

BattleEvents.TurnStarted.OnClientEvent:Connect(function(data)
	if selectedUnitId then
		local unit = unitData[selectedUnitId]
		if unit then
			content.Text = buildStatText(unit)
		end
	end
end)
