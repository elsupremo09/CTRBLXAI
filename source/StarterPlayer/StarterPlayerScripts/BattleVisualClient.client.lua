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
local timelineSnapshot = nil  -- all alive units' RT snapshot, for simulation
local currentBattleCt  = 0    -- current battle CT (for round boundary calculation)
local inputMode       = nil  -- nil, "move", "attack", "skill"
local selectedSkill   = nil
local highlightParts  = {}
local aimTarget       = nil  -- target data during aim phase (before confirm)
local aimConfirmGui   = nil  -- confirm/cancel buttons during aim phase
local predictionGui   = nil  -- floating predicted damage/healing label

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

	return fill, label, mpFill, billboard, mpBb, nameBb
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

	local fill, label, mpFill, hpBillboard, mpBillboard, nameBillboard = createHpBar(part)
	label.Text = unit.name

	unitTokens[unit.id] = { part = part, fill = fill, label = label, mpFill = mpFill,
		hpBillboard = hpBillboard, mpBillboard = mpBillboard, nameBillboard = nameBillboard }
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

-- simulateTurnOrder: given a snapshot of all units' current remainingRt,
-- simulate the next `count` turns and return them in order.
-- previewUnitId + previewNewRt: optionally override one unit's RT
-- (used to preview what the bar will look like after an action).
-- Uses BASE_RT = 450 as a rough "what happens after this future turn" estimate.
local BASE_FUTURE_RT = 450

local function simulateTurnOrder(snapshot, count, previewUnitId, previewNewRt, previewEvent)
	-- Deep copy snapshot; also inject channeled skill activations as separate events
	local units = {}
	for _, u in ipairs(snapshot) do
		table.insert(units, {
			id          = u.id,
			name        = u.name,
			side        = u.side,
			remainingRt = u.remainingRt,
			isChanneling = u.isChanneling or false,
			isEvent     = false,
		})
		-- If unit is channeling, add a separate "event" entry for the activation
		if u.isChanneling and u.channelRt and u.channelRt > 0 then
			table.insert(units, {
				id          = u.id .. "_channel",
				name        = u.channeledSkillName or "Skill",
				side        = u.side,
				remainingRt = u.channelRt,
				isChanneling = false,
				isEvent     = true, -- marks this as a delayed effect, not a unit turn
				ownerId     = u.id,
			})
		end
	end

	-- Inject a preview event (e.g. Healing Light activation) when player is
	-- selecting a channeled skill — so they can see where it lands in the bar
	if previewEvent then
		table.insert(units, {
			id          = "preview_event",
			name        = previewEvent.name or "Skill",
			side        = previewEvent.side or "Player",
			remainingRt = previewEvent.rt or 100,
			isChanneling = false,
			isEvent     = true,
		})
	end

	-- Apply preview override
	if previewUnitId and previewNewRt then
		for _, u in ipairs(units) do
			if u.id == previewUnitId then
				u.remainingRt = previewNewRt
				break
			end
		end
	end

	local result = {}
	-- Round markers: based on CT. Every 1000 CT = new round.
	-- Track elapsed CT in the simulation to know when boundaries are crossed.
	local elapsedCt = 0
	local nextRoundCt = math.ceil((currentBattleCt + 1) / 1000) * 1000  -- next 1000 boundary
	local roundNumber = math.ceil((currentBattleCt + 1) / 1000) + 1     -- what round number that is

	for _ = 1, count * 2 do
		if #units == 0 then break end

		-- Find the minimum RT
		local minRt = math.huge
		for _, u in ipairs(units) do
			if u.remainingRt < minRt then minRt = u.remainingRt end
		end
		if minRt == math.huge then break end

		-- Check if advancing by minRt crosses a round boundary
		local ctAfterAdvance = currentBattleCt + elapsedCt + minRt
		while ctAfterAdvance >= nextRoundCt and #result < count do
			table.insert(result, {
				id       = "round_" .. tostring(roundNumber),
				name     = "R" .. tostring(roundNumber),
				side     = "Neutral",
				isEvent  = true,
				isRound  = true,
				isChanneling = false,
				isPreview = false,
			})
			nextRoundCt = nextRoundCt + 1000
			roundNumber = roundNumber + 1
		end

		elapsedCt = elapsedCt + minRt

		-- Advance all units
		for _, u in ipairs(units) do
			u.remainingRt = u.remainingRt - minRt
		end

		-- Collect ready entries (RT <= 0)
		local ready = {}
		for _, u in ipairs(units) do
			if u.remainingRt <= 0 then
				table.insert(ready, u)
			end
		end
		table.sort(ready, function(a, b) return a.id < b.id end)

		for _, u in ipairs(ready) do
			table.insert(result, {
				id          = u.id,
				name        = u.name,
				side        = u.side,
				remainingRt = 0,
				isEvent     = u.isEvent,
				isChanneling = u.isChanneling,
				isPreview   = (previewUnitId ~= nil and u.id == previewUnitId and #result == 0),
			})
			-- Events (channel activations) fire once and disappear
			if u.isEvent then
				u.remainingRt = 99999 -- effectively remove from simulation
			else
				u.remainingRt = BASE_FUTURE_RT
			end
			if #result >= count then break end
		end

		if #result >= count then break end
	end

	return result
end

-- Forward declaration (defined later, but called from portrait click closures)
local showUnitInspector

local function updateTimeline(snapshot, previewUnitId, previewNewRt, previewEvent)
	if timelineGui then timelineGui:Destroy() end
	if not snapshot or #snapshot == 0 then return end

	-- Generate 12 upcoming turn slots (includes channel activation events)
	-- timeline[1] = active NOW, timeline[12] = furthest future
	local timeline = simulateTurnOrder(snapshot, 10, previewUnitId, previewNewRt, previewEvent)
	if #timeline == 0 then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "TimelineGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 90
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")
	timelineGui = gui

	-- Bar container: top-center
	local slotCount = #timeline
	local normalW = 39
	local activeW = 50
	local barWidth = (slotCount - 1) * (normalW + 2) + activeW + 16

	local bar = Instance.new("Frame")
	bar.Name = "TimelineBar"
	bar.Size = UDim2.new(0, math.min(barWidth, 580), 0, 52)
	bar.AnchorPoint = Vector2.new(1, 0)
	bar.Position = UDim2.new(1, -10, 0, 4)
	bar.BackgroundColor3 = Color3.fromRGB(10, 10, 20)
	bar.BackgroundTransparency = 0.25
	bar.BorderSizePixel = 0
	bar.Parent = gui
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 6)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 2)
	layout.Parent = bar

	-- Mana Khemia style: rightmost = NOW (active), leftmost = furthest future
	-- timeline[1] = NOW, timeline[N] = furthest future
	-- LayoutOrder: give furthest future the LOWEST value (leftmost)
	-- and NOW the HIGHEST value (rightmost)
	for i, entry in ipairs(timeline) do
		local isActive = (i == 1) and not previewUnitId
		local isPreviewSlot = entry.isPreview
		local isEvent = entry.isEvent

		local slotW = isActive and activeW or normalW
		local slotH = isActive and 46 or 37

		local portrait = Instance.new("TextButton")
		portrait.Name = entry.name .. "_" .. tostring(i)
		portrait.Size = UDim2.new(0, slotW, 0, slotH)
		portrait.BorderSizePixel = 0
		portrait.Text = ""
		portrait.AutoButtonColor = false
		-- LayoutOrder: higher = further right. Slot 1 (NOW) = highest.
		portrait.LayoutOrder = slotCount - i + 1
		portrait.Parent = bar

		-- Color based on type
		if isEvent then
			if entry.isRound then
				-- Round marker: narrow pill with round number
				portrait.Size = UDim2.new(0, 22, 0, 37)
				portrait.BackgroundColor3 = Color3.fromRGB(180, 180, 50)
				portrait.BackgroundTransparency = 0.2
			else
				portrait.BackgroundColor3 = entry.side == "Player"
					and Color3.fromRGB(60, 40, 140) or Color3.fromRGB(140, 60, 20)
				portrait.BackgroundTransparency = 0.05
			end
		else
			portrait.BackgroundColor3 = entry.side == "Player"
				and Color3.fromRGB(40, 80, 160) or Color3.fromRGB(140, 40, 40)
			portrait.BackgroundTransparency = 0.15
		end

		Instance.new("UICorner", portrait).CornerRadius = UDim.new(0, 4)

		-- Active (NOW) slot: gold border, magnified, full opacity
		if isActive then
			portrait.BackgroundTransparency = 0
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(255, 230, 80)
			stroke.Thickness = 2
			stroke.Parent = portrait
		elseif isPreviewSlot then
			-- Preview: shows where active unit will land after chosen action
			portrait.BackgroundTransparency = 0
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(200, 200, 200)
			stroke.Thickness = 2
			stroke.Parent = portrait
		end

		-- Name label
		local initial = Instance.new("TextLabel")
		initial.Size = UDim2.fromScale(1, 0.65)
		initial.Position = UDim2.new(0, 0, 0, 2)
		initial.BackgroundTransparency = 1
		initial.Font = Enum.Font.SourceSansBold
		initial.TextSize = isActive and 15 or (isEvent and 9 or 12)
		initial.TextColor3 = isEvent
			and Color3.fromRGB(255, 200, 100) or Color3.fromRGB(255, 255, 255)
		if isEvent then
			if entry.isRound then
				initial.TextSize = 9
				initial.Text = entry.name  -- "R2", "R3", etc.
			else
				initial.Text = string.sub(entry.name, 1, 5)
			end
		else
			initial.Text = string.sub(entry.name, 1, 3)
		end
		initial.Parent = portrait

		-- Bottom label
		local rtLabel = Instance.new("TextLabel")
		rtLabel.Size = UDim2.new(1, 0, 0, 14)
		rtLabel.Position = UDim2.new(0, 0, 1, -14)
		rtLabel.BackgroundTransparency = 1
		rtLabel.Font = Enum.Font.SourceSans
		rtLabel.TextSize = 10
		rtLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
		local labelText = ""
		if isActive then
			labelText = "NOW"
		elseif isPreviewSlot then
			labelText = "← YOU"
		elseif isEvent then
			if entry.isRound then
				labelText = ""
			else
				labelText = "◎ ACT"
			end
		else
			-- Show current RT for non-active unit portraits
			local rt = 0
			if timelineSnapshot then
				for _, snap in ipairs(timelineSnapshot) do
					if snap.id == entry.id then rt = snap.remainingRt; break end
				end
			end
			labelText = tostring(rt)
		end
		rtLabel.Text = labelText
		rtLabel.Parent = portrait

		-- Click handler: show RT tooltip and select the unit's tile
		if not entry.isRound then
			portrait.MouseButton1Click:Connect(function()
				-- Find the unit in unitData (skip events that don't map to a unit)
				local uid = entry.id
				-- For channel events, the id is "unitId_channel" — extract the owner
				if entry.isEvent and string.find(uid, "_channel") then
					uid = string.gsub(uid, "_channel", "")
				end
				if uid and unitData[uid] then
					-- Select the unit's tile (triggers tile inspector + highlight)
					local data = unitData[uid]
					if data.tileX and data.tileY and _G.CTRBLXAI_SelectTileAt then
						_G.CTRBLXAI_SelectTileAt(data.tileX + BATTLE_OFFSET_X, data.tileY + BATTLE_OFFSET_Y)
					end
					-- Show unit inspector panel
					showUnitInspector(uid)
				end
			end)
		end
	end
end



--------------------------------------------------
-- 7. ACTION BAR UI
--------------------------------------------------

local actionBarGui = nil

-- Forward-declare skill tooltip (needed by destroyActionBar)
local skillTooltipGui = nil
local function hideSkillTooltip()
	if skillTooltipGui then skillTooltipGui:Destroy(); skillTooltipGui = nil end
end

-- Forward-declare aim phase (needed by action bar callbacks + click handler)
local function destroyAimPhase()
	if aimConfirmGui then aimConfirmGui:Destroy(); aimConfirmGui = nil end
	if predictionGui then predictionGui:Destroy(); predictionGui = nil end
	aimTarget = nil
end

local function showPrediction(targetId, value, predType)
	if predictionGui then predictionGui:Destroy() end

	-- Use a ScreenGui label above the confirm buttons for guaranteed visibility
	local gui = Instance.new("ScreenGui")
	gui.Name = "PredictionGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 115
	gui.Parent = player:WaitForChild("PlayerGui")
	predictionGui = gui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 160, 0, 36)
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 0.76, 0)
	label.BackgroundColor3 = predType == "healing"
		and Color3.fromRGB(20, 60, 20) or Color3.fromRGB(80, 15, 15)
	label.BackgroundTransparency = 0.1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.SourceSansBold
	label.TextSize = 20
	label.TextColor3 = predType == "healing"
		and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
	if predType == "healing" then
		label.Text = "Heal: +" .. tostring(value)
	else
		label.Text = "Dmg: -" .. tostring(value)
	end
	label.Parent = gui
	Instance.new("UICorner", label).CornerRadius = UDim.new(0, 6)
end

local function showAimConfirm(onConfirm, onCancel)
	if aimConfirmGui then aimConfirmGui:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = "AimConfirmGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 110
	gui.Parent = player:WaitForChild("PlayerGui")
	aimConfirmGui = gui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 220, 0, 45)
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 0.82, 0)
	frame.BackgroundColor3 = Color3.fromRGB(10, 10, 20)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = gui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.Parent = frame

	local function makeBtn(text, color, callback)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 90, 0, 32)
		btn.BackgroundColor3 = color
		btn.Font = Enum.Font.SourceSansBold
		btn.TextSize = 14
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.Text = text
		btn.BorderSizePixel = 0
		btn.Parent = frame
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
		btn.MouseButton1Click:Connect(callback)
		return btn
	end

	makeBtn("✓ Confirm", Color3.fromRGB(40, 140, 40), onConfirm)
	makeBtn("✗ Cancel", Color3.fromRGB(120, 40, 40), onCancel)
end

local function destroyActionBar()
	if actionBarGui then actionBarGui:Destroy(); actionBarGui = nil end
	hideSkillTooltip()
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
		-- Preview: use average 2-tile move RT as approximation
		local previewRt = math.round((prompt.unitBaseRt or 400) * 0.0625 * 2) + (prompt.unitBaseRt or 400)
		updateTimeline(timelineSnapshot, prompt.unitId, previewRt)
		for _, tile in ipairs(prompt.moveCandidates) do
			createTileHighlight(tile.tileX, tile.tileY, Color3.fromRGB(50, 200, 50), 0.55)
		end
	end)

	makeButton("Attack", "⚔ Attack", "", Color3.fromRGB(180, 60, 60), #prompt.attackTargets > 0, function()
		inputMode = "attack"; selectedSkill = nil; clearHighlights()
		-- Preview: use attack RT cost
		local previewRt = (prompt.attackRt or 80) + (prompt.unitBaseRt or 400)
		updateTimeline(timelineSnapshot, prompt.unitId, previewRt)
		for _, t in ipairs(prompt.attackTargets) do
			createTileHighlight(t.tileX, t.tileY, Color3.fromRGB(255, 60, 60), 0.45)
		end
	end)

	makeButton("Wait", "⏸ Wait", "", Color3.fromRGB(80, 80, 80), true, function()
		-- Preview: wait RT (rest)
		updateTimeline(timelineSnapshot, prompt.unitId, prompt.waitRt or 300)
		clearHighlights(); destroyActionBar(); isPlayerTurn = false; inputMode = nil
		BattleEvents.PlayerCommand:FireServer({ actionType = "Wait" })
	end)

	for _, skill in ipairs(prompt.skills) do
		local canUse = skill.canUse and #skill.targets > 0
		local subtext = string.format("MP:%d R:%d", skill.mpCost, skill.range)
		local color = skill.isHealing and Color3.fromRGB(50, 150, 50) or Color3.fromRGB(80, 80, 180)

		local btn = makeButton(skill.id, "✦ " .. skill.name, subtext, color, canUse, function()
			inputMode = "skill"; selectedSkill = skill; clearHighlights(); destroyAimPhase()
			-- Preview: skill RT cost + base RT
			local previewRt = (skill.rtCost or 60) + (prompt.unitBaseRt or 400)
			local previewEvent = nil
			if skill.channelTime and skill.channelTime > 0 then
				-- Insert a separate event portrait for the channel activation
				-- Unit's next turn is after commit RT; activation is a separate event
				previewEvent = {
					name = skill.name,
					side = prompt.unitSide or "Player",
					rt   = skill.channelTime,
				}
			end
			updateTimeline(timelineSnapshot, prompt.unitId, previewRt, previewEvent)
			local hColor = skill.isHealing and Color3.fromRGB(50, 220, 50) or Color3.fromRGB(180, 80, 255)
			for _, t in ipairs(skill.targets) do
				createTileHighlight(t.tileX, t.tileY, hColor, 0.45)
			end
		end)

		-- Tooltip on hover: show skill details
		if btn then
			btn.MouseEnter:Connect(function()
				hideSkillTooltip()
				local gui = Instance.new("ScreenGui")
				gui.Name = "SkillTooltipGui"
				gui.ResetOnSpawn = false
				gui.DisplayOrder = 120
				gui.Parent = player:WaitForChild("PlayerGui")
				skillTooltipGui = gui

				local tip = Instance.new("TextLabel")
				tip.Size = UDim2.new(0, 200, 0, 80)
				tip.AnchorPoint = Vector2.new(0.5, 1)
				tip.Position = UDim2.new(0.5, 0, 0.78, 0)
				tip.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
				tip.BackgroundTransparency = 0.05
				tip.BorderSizePixel = 0
				tip.Font = Enum.Font.SourceSans
				tip.TextSize = 12
				tip.TextColor3 = Color3.fromRGB(220, 220, 220)
				tip.TextWrapped = true
				tip.TextYAlignment = Enum.TextYAlignment.Top
				tip.Text = string.format(
					"%s\n%s\nPower: %s | Range: %d | RT: %d\nMP: %d | Pattern: %s%s",
					skill.name,
					skill.description or "",
					skill.power and tostring(skill.power) or "—",
					skill.range or 1,
					skill.rtCost or 0,
					skill.mpCost or 0,
					skill.pattern or "Single",
					skill.channelTime and skill.channelTime > 0 and ("\nChannel: " .. skill.channelTime .. " CT") or ""
				)
				tip.Parent = gui
				Instance.new("UICorner", tip).CornerRadius = UDim.new(0, 6)
				Instance.new("UIPadding", tip).PaddingLeft = UDim.new(0, 6)
			end)
			btn.MouseLeave:Connect(function()
				hideSkillTooltip()
			end)
		end
	end

	-- Initial display: show current state (no preview)
	updateTimeline(timelineSnapshot, nil, nil)
end

--------------------------------------------------
-- 7b. UNIT INSPECTOR PANEL (left side)
--
-- Shows when any unit tile is clicked:
--   Name, Side, HP, MP, AP, RT, Stats, Skills, Statuses
--------------------------------------------------

local unitInspectorGui = nil

showUnitInspector = function(uid)
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
		table.insert(lines, "")  -- space before status buttons
	end

	content.Text = table.concat(lines, "\n")

	-- Status buttons (clickable, below the text content)
	if data.statuses and #data.statuses > 0 then
		-- Calculate vertical offset for status buttons based on text lines
		local textLineCount = #lines
		local statusStartY = 4 + textLineCount * 14  -- approx 14px per line

		local statusDetailLabel = nil  -- shared detail panel, toggled per status

		for idx, s in ipairs(data.statuses) do
			local statusColor = s.id == "Poison" and Color3.fromRGB(80, 200, 80)
				or s.id == "Burn" and Color3.fromRGB(255, 140, 40)
				or s.id == "Slow" and Color3.fromRGB(180, 80, 255)
				or Color3.fromRGB(150, 150, 255)

			local valueStr = string.format("%dt", s.remainingTurns or 0)
			if s.nextDamage and s.nextDamage > 0 then
				valueStr = valueStr .. string.format("  -%d", s.nextDamage)
			end

			local btn = Instance.new("TextButton")
			btn.Name = "Status_" .. s.id
			btn.Size = UDim2.new(1, -18, 0, 16)
			btn.Position = UDim2.new(0, 14, 0, statusStartY + (idx - 1) * 18)
			btn.BackgroundTransparency = 1
			btn.BorderSizePixel = 0
			btn.Font = Enum.Font.RobotoMono
			btn.TextSize = 12
			btn.TextColor3 = statusColor
			btn.TextXAlignment = Enum.TextXAlignment.Left
			btn.Text = string.format("▸ %s  %s", s.id, valueStr)
			btn.Parent = panel

			btn.MouseButton1Click:Connect(function()
				-- Toggle detail panel for this status
				if statusDetailLabel then
					statusDetailLabel:Destroy()
					statusDetailLabel = nil
				end

				-- Build detail text
				local details = {}
				table.insert(details, string.format("<b>%s</b>", s.id))

				-- Description based on status type
				if s.id == "Poison" then
					table.insert(details, "DoT — 15% Max HP per turn")
					table.insert(details, "Undead immune. Refreshes on reapply.")
				elseif s.id == "Burn" then
					table.insert(details, "DoT — Stored fire damage ticks each turn")
					table.insert(details, "Reapply adds damage + extends duration.")
					table.insert(details, "Water removes Burn.")
				elseif s.id == "Slow" then
					table.insert(details, "Base RT × 1.10 (10% slower)")
					table.insert(details, "Affects Base RT-derived costs only.")
				else
					table.insert(details, "Status effect")
				end

				table.insert(details, "")
				table.insert(details, string.format("Duration: %d turns remaining", s.remainingTurns or 0))
				if s.nextDamage and s.nextDamage > 0 then
					table.insert(details, string.format("Next tick: -%d damage", s.nextDamage))
				end
				if s.storedBurn and s.storedBurn > 0 then
					table.insert(details, string.format("Stored burn: %d total", s.storedBurn))
				end

				local detailFrame = Instance.new("TextLabel")
				detailFrame.Name = "StatusDetail"
				detailFrame.Size = UDim2.new(0, 170, 0, 90)
				detailFrame.Position = UDim2.new(0, 8, 0, statusStartY + (#data.statuses) * 18 + 4)
				detailFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
				detailFrame.BackgroundTransparency = 0.05
				detailFrame.BorderSizePixel = 0
				detailFrame.Font = Enum.Font.SourceSans
				detailFrame.TextSize = 11
				detailFrame.TextColor3 = Color3.fromRGB(200, 200, 200)
				detailFrame.TextXAlignment = Enum.TextXAlignment.Left
				detailFrame.TextYAlignment = Enum.TextYAlignment.Top
				detailFrame.TextWrapped = true
				detailFrame.RichText = true
				detailFrame.Text = table.concat(details, "\n")
				detailFrame.Parent = panel
				Instance.new("UICorner", detailFrame).CornerRadius = UDim.new(0, 4)
				Instance.new("UIPadding", detailFrame).PaddingLeft = UDim.new(0, 4)
				statusDetailLabel = detailFrame
			end)
		end

		-- Expand panel height to fit statuses + potential detail
		local extraHeight = (#data.statuses * 18) + 100
		panel.Size = UDim2.new(0, 180, 0, math.max(340, statusStartY + extraHeight))
	end
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
--    Two-phase: (1) select target → aim phase, (2) confirm → commit
--------------------------------------------------

local function commitCommand(command)
	clearHighlights(); destroyActionBar(); destroyAimPhase()
	isPlayerTurn = false; inputMode = nil; selectedSkill = nil; aimTarget = nil
	BattleEvents.PlayerCommand:FireServer(command)
end

local function cancelAim()
	destroyAimPhase()
	aimTarget = nil
	if inputMode == "move" then
		clearHighlights()
		for _, tile in ipairs(currentPrompt.moveCandidates) do
			createTileHighlight(tile.tileX, tile.tileY, Color3.fromRGB(50, 200, 50), 0.55)
		end
	elseif inputMode == "attack" then
		clearHighlights()
		for _, t in ipairs(currentPrompt.attackTargets) do
			createTileHighlight(t.tileX, t.tileY, Color3.fromRGB(255, 60, 60), 0.45)
		end
	elseif inputMode == "skill" and selectedSkill then
		clearHighlights()
		local hColor = selectedSkill.isHealing and Color3.fromRGB(50, 220, 50) or Color3.fromRGB(180, 80, 255)
		for _, t in ipairs(selectedSkill.targets) do
			createTileHighlight(t.tileX, t.tileY, hColor, 0.45)
		end
	end
end

mouse.Button1Down:Connect(function()
	local tilePart = getTileUnderMouse()
	local bx, by = tileToBattle(tilePart)

	-- Always show unit inspector on unit click
	if bx then
		for uid, data in pairs(unitData) do
			if data.tileX == bx and data.tileY == by and data.isAlive ~= false then
				showUnitInspector(uid)
				break
			end
		end
	end

	-- If in aim phase and clicking elsewhere, cancel aim
	if aimTarget then
		cancelAim()
		return
	end

	-- If not in input mode, just inspector
	if not isPlayerTurn or not inputMode then return end
	if not bx then return end

	if inputMode == "move" then
		for _, tile in ipairs(currentPrompt.moveCandidates) do
			if tile.tileX == bx and tile.tileY == by then
				aimTarget = tile
				clearHighlights()
				createTileHighlight(bx, by, Color3.fromRGB(255, 255, 80), 0.35)
				showAimConfirm(function()
					commitCommand({ actionType = "Move", tileX = bx, tileY = by, pathCost = tile.pathCost })
				end, cancelAim)
				return
			end
		end

	elseif inputMode == "attack" then
		for _, t in ipairs(currentPrompt.attackTargets) do
			if t.tileX == bx and t.tileY == by then
				aimTarget = t
				clearHighlights()
				createTileHighlight(bx, by, Color3.fromRGB(255, 255, 80), 0.35)
				showPrediction(t.id, t.predicted or 0, "damage")
				showAimConfirm(function()
					commitCommand({ actionType = "Attack", targetId = t.id })
				end, cancelAim)
				return
			end
		end

	elseif inputMode == "skill" and selectedSkill then
		for _, t in ipairs(selectedSkill.targets) do
			if t.tileX == bx and t.tileY == by then
				aimTarget = t
				clearHighlights()
				createTileHighlight(bx, by, Color3.fromRGB(255, 255, 80), 0.35)
				showPrediction(t.id, t.predicted or 0, t.predType or "damage")
				showAimConfirm(function()
					commitCommand({ actionType = "Skill", skillId = selectedSkill.id, targetId = t.id })
				end, cancelAim)
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
	-- Use the authoritative snapshot from the server
	if data.allUnitsRt and #data.allUnitsRt > 0 then
		timelineSnapshot = data.allUnitsRt
		updateTimeline(data.allUnitsRt, nil, nil)
	end
	local token = unitTokens[data.unitId]
	if token then
		token.label.TextColor3 = Color3.fromRGB(255, 230, 80)
	end
	showUnitInspector(data.unitId)
end)

-- Real-time turn order updates (fires after each AI action too)
BattleEvents.TurnOrderUpdate.OnClientEvent:Connect(function(data)
	if not data then return end
	local snapshot = data.units
	local ct = data.currentCt
	if snapshot and #snapshot > 0 then
		timelineSnapshot = snapshot
		if ct then currentBattleCt = ct end
		-- Only update if player isn't actively previewing an action
		if not aimTarget and (not isPlayerTurn or not inputMode) then
			updateTimeline(snapshot, nil, nil)
		end
	end
end)

BattleEvents.PlayerTurnPrompt.OnClientEvent:Connect(function(prompt)
	currentPrompt = prompt
	timelineSnapshot = prompt.timeline
	if prompt.currentCt then currentBattleCt = prompt.currentCt end
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
		-- Update local unitData so inspector shows it immediately
		if unitData[data.unitId] then
			if not unitData[data.unitId].statuses then
				unitData[data.unitId].statuses = {}
			end
			table.insert(unitData[data.unitId].statuses, {
				id             = data.statusId,
				remainingTurns = data.remainingTurns or 0,
				nextDamage     = data.nextDamage,
				storedBurn     = data.storedBurn,
			})
		end
		local color = data.statusId == "Poison" and Color3.fromRGB(80, 200, 80)
			or data.statusId == "Burn" and Color3.fromRGB(255, 140, 40)
			or Color3.fromRGB(180, 80, 255)
		showFloatingText(token.part.Position + Vector3.new(0, 1, 0), "▼ " .. data.statusId, color, 1.2)
	end
end)

BattleEvents.StatusExpired.OnClientEvent:Connect(function(data)
	local token = unitTokens[data.unitId]
	if token then
		-- Remove from local unitData
		if unitData[data.unitId] and unitData[data.unitId].statuses then
			for i, s in ipairs(unitData[data.unitId].statuses) do
				if s.id == data.statusId then
					table.remove(unitData[data.unitId].statuses, i)
					break
				end
			end
		end
		showFloatingText(token.part.Position + Vector3.new(0, 1, 0), "✗ " .. data.statusId, Color3.fromRGB(180, 180, 180), 1.2)
	end
end)

BattleEvents.UnitDefeated.OnClientEvent:Connect(function(data)
	local token = unitTokens[data.unitId]
	if not token then return end
	if unitData[data.unitId] then unitData[data.unitId].isAlive = false end
	token.part.Color = DEFEATED_COLOR
	token.part.Transparency = 0.5
	-- Hide HP/MP/Name bars for KO'd units
	if token.hpBillboard then token.hpBillboard.Enabled = false end
	if token.mpBillboard then token.mpBillboard.Enabled = false end
	if token.nameBillboard then token.nameBillboard.Enabled = false end
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
