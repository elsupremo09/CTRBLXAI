-- BattleVisualClient.client.lua
-- CTRBLXAI | Slice 7B v3 — State-Machine Battle Client
--
-- Responsibilities:
--   - 3D unit tokens, billboard HP/MP, floating text, tile highlights
--   - Receives RemoteEvents → updates data → tells BattleHUD which state
--   - Handles mouse input → advances state machine
--   - Timeline simulation
--   - Never creates 2D ScreenGui panels (BattleHUD owns all 2D)

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()

local BattleEvents = require(
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("Remotes", 10):WaitForChild("BattleEvents", 10)
)
local GameConstants = require(
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("Shared", 10):WaitForChild("GameConstants", 10)
)
local BattleHUD = require(
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("UI", 10):WaitForChild("BattleHUD", 10)
)
local Theme = require(
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("UI", 10):WaitForChild("Theme", 10)
)

--------------------------------------------------
-- MAP CONFIGURATION
--------------------------------------------------

local TILE_SIZE = 5
local TILE_BASE_HEIGHT = 0.6
local ELEVATION_STEP = 2.5
local MAP_WIDTH, MAP_HEIGHT = 8, 8
local MAP_OFFSET_X = -75 + 11 * TILE_SIZE
local MAP_OFFSET_Z = -50 + 6 * TILE_SIZE
local BATTLE_OFFSET_X, BATTLE_OFFSET_Y = 11, 6

local elevationMap = nil

local function getElevation(tx, ty)
	if elevationMap then local r = elevationMap[ty]; if r then return r[tx] or 1 end end; return 1
end
local function tileSurfaceY(elev) return TILE_BASE_HEIGHT + ((elev or 1) - 1) * ELEVATION_STEP end
local function tileToWorld(tx, ty)
	return Vector3.new(MAP_OFFSET_X + (tx - 0.5) * TILE_SIZE, tileSurfaceY(getElevation(tx, ty)) + 1, MAP_OFFSET_Z + (ty - 0.5) * TILE_SIZE)
end
local function templateToBattle(x, y)
	local bx, by = x - BATTLE_OFFSET_X, y - BATTLE_OFFSET_Y
	if bx >= 1 and bx <= MAP_WIDTH and by >= 1 and by <= MAP_HEIGHT then return bx, by end
	return nil, nil
end

--------------------------------------------------
-- STATE
--------------------------------------------------

local unitTokens   = {}
local unitData     = {}
local visualFolder = Instance.new("Folder"); visualFolder.Name = "BattleVisuals"; visualFolder.Parent = workspace

local isPlayerTurn    = false
local currentPrompt   = nil
local timelineSnapshot = nil
local currentBattleCt  = 0
local activeUnitId    = nil  -- who is currently acting (for timeline NOW marker)
local inputMode       = nil -- "move","attack","skill"
local selectedSkill   = nil
local highlightParts  = {}
local aimTarget       = nil

--------------------------------------------------
-- HIGHLIGHTS
--------------------------------------------------

local function clearHighlights()
	for _, p in ipairs(highlightParts) do p:Destroy() end
	highlightParts = {}
end

local function createTileHighlight(tx, ty, color, transparency)
	local pos = Vector3.new(MAP_OFFSET_X + (tx-0.5)*TILE_SIZE, tileSurfaceY(getElevation(tx,ty))+0.12, MAP_OFFSET_Z + (ty-0.5)*TILE_SIZE)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery = true, false, false
	p.Size = Vector3.new(TILE_SIZE*0.82, 0.1, TILE_SIZE*0.82)
	p.Position = pos
	p.Color = color
	p.Transparency = transparency or 0.55
	p.Material = Enum.Material.Neon
	p.Parent = visualFolder
	table.insert(highlightParts, p)
end

--------------------------------------------------
-- 3D TOKENS
--------------------------------------------------

local function spawnToken(unit)
	local part = Instance.new("Part")
	part.Name = "Unit_" .. unit.id
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(1.8, 1.8, 1.8)
	part.CFrame = CFrame.new(tileToWorld(unit.tileX, unit.tileY)) * CFrame.Angles(0,0,math.rad(90))
	part.Anchored, part.CanCollide, part.CanQuery = true, false, true
	part.Color = Theme.GetSideColor(unit.side)
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = visualFolder

	-- HP billboard
	local hpBb = Instance.new("BillboardGui"); hpBb.Size = UDim2.new(0,80,0,8)
	hpBb.StudsOffset = Vector3.new(0, 1.3, 0); hpBb.AlwaysOnTop = false; hpBb.Parent = part
	local hpBg = Instance.new("Frame"); hpBg.Size = UDim2.fromScale(1,1)
	hpBg.BackgroundColor3 = Color3.fromRGB(20,20,25); hpBg.BorderSizePixel = 0; hpBg.Parent = hpBb
	Instance.new("UICorner", hpBg).CornerRadius = UDim.new(0,2)
	local hpFill = Instance.new("Frame"); hpFill.Name = "Fill"
	hpFill.Size = UDim2.fromScale(1,1); hpFill.BackgroundColor3 = Theme.Colors.HP
	hpFill.BorderSizePixel = 0; hpFill.Parent = hpBg
	Instance.new("UICorner", hpFill).CornerRadius = UDim.new(0,2)

	-- MP billboard
	local mpBb = Instance.new("BillboardGui"); mpBb.Size = UDim2.new(0,60,0,4)
	mpBb.StudsOffset = Vector3.new(0, 1.05, 0); mpBb.AlwaysOnTop = false; mpBb.Parent = part
	local mpBg = Instance.new("Frame"); mpBg.Size = UDim2.fromScale(1,1)
	mpBg.BackgroundColor3 = Color3.fromRGB(15,15,30); mpBg.BorderSizePixel = 0; mpBg.Parent = mpBb
	Instance.new("UICorner", mpBg).CornerRadius = UDim.new(0,2)
	local mpFill = Instance.new("Frame"); mpFill.Name = "Fill"
	mpFill.Size = UDim2.fromScale(1,1); mpFill.BackgroundColor3 = Theme.Colors.MP
	mpFill.BorderSizePixel = 0; mpFill.Parent = mpBg
	Instance.new("UICorner", mpFill).CornerRadius = UDim.new(0,2)

	-- Name label
	local nameBb = Instance.new("BillboardGui"); nameBb.Size = UDim2.new(0,120,0,16)
	nameBb.StudsOffset = Vector3.new(0, 1.7, 0); nameBb.AlwaysOnTop = false; nameBb.Parent = part
	local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.fromScale(1,1)
	lbl.BackgroundTransparency = 1; lbl.TextColor3 = Theme.Colors.TextPrimary
	lbl.TextSize = 12; lbl.Font = Theme.Font.PrimaryBold; lbl.TextStrokeTransparency = 0.4
	lbl.Text = unit.name; lbl.Parent = nameBb

	unitTokens[unit.id] = { part = part, fill = hpFill, mpFill = mpFill, label = lbl }
end

local function updateHpBar(uid, hp, maxHp)
	local t = unitTokens[uid]; if not t then return end
	local r = math.clamp(hp/maxHp, 0, 1)
	t.fill.BackgroundColor3 = Theme.GetHPColor(r)
	TweenService:Create(t.fill, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {Size = UDim2.fromScale(r,1)}):Play()
	t.label.Text = string.format("%s %d/%d", unitData[uid] and unitData[uid].name or uid, hp, maxHp)
end

local function updateMpBar(uid, mp, maxMp)
	local t = unitTokens[uid]; if not t or maxMp <= 0 then return end
	TweenService:Create(t.mpFill, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {Size = UDim2.fromScale(math.clamp(mp/maxMp,0,1),1)}):Play()
end

--------------------------------------------------
-- FLOATING TEXT
--------------------------------------------------

local function showFloatingText(worldPos, text, color, dur)
	dur = dur or 0.9
	local anchor = Instance.new("Part"); anchor.Anchored = true; anchor.CanCollide = false
	anchor.CanQuery = false; anchor.Transparency = 1; anchor.Size = Vector3.new(0.1,0.1,0.1)
	anchor.Position = worldPos + Vector3.new(0,2,0); anchor.Parent = visualFolder
	local bb = Instance.new("BillboardGui"); bb.Size = UDim2.new(0,160,0,36); bb.AlwaysOnTop = true; bb.Parent = anchor
	local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.fromScale(1,1); lbl.BackgroundTransparency = 1
	lbl.Font = Theme.Font.PrimaryBold; lbl.TextSize = 20; lbl.TextColor3 = color
	lbl.TextStrokeTransparency = 0.2; lbl.Text = text; lbl.Parent = bb
	TweenService:Create(anchor, TweenInfo.new(dur, Enum.EasingStyle.Quad), {Position = worldPos + Vector3.new(0,5,0)}):Play()
	TweenService:Create(lbl, TweenInfo.new(dur*0.6, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, dur*0.4), {TextTransparency=1, TextStrokeTransparency=1}):Play()
	task.delay(dur + 0.1, function() anchor:Destroy() end)
end

--------------------------------------------------
-- TIMELINE SIMULATION
--------------------------------------------------

local function simulateTurnOrder(snapshot, count, previewUnitId, previewNewRt, previewEvent)
	local units = {}
	for _, u in ipairs(snapshot) do
		table.insert(units, { id = u.id, name = u.name, side = u.side, remainingRt = u.remainingRt, isEvent = false, isActive = u.isActive or false })
		if u.isChanneling and u.channelRt and u.channelRt > 0 then
			table.insert(units, { id = u.id.."_ch", name = u.channeledSkillName or "Skill", side = u.side, remainingRt = u.channelRt, isEvent = true })
		end
	end
	if previewEvent then table.insert(units, { id = "pev", name = previewEvent.name, side = previewEvent.side, remainingRt = previewEvent.rt or 100, isEvent = true }) end
	if previewUnitId and previewNewRt then
		for _, u in ipairs(units) do if u.id == previewUnitId then u.remainingRt = previewNewRt; break end end
	end

	local result, elapsed = {}, 0
	local nextRound = math.ceil((currentBattleCt+1)/1000)*1000
	local roundNum = math.ceil((currentBattleCt+1)/1000)+1

	for _ = 1, count*2 do
		if #units == 0 then break end
		local minRt = math.huge
		for _, u in ipairs(units) do if u.remainingRt < minRt then minRt = u.remainingRt end end
		if minRt == math.huge then break end

		while currentBattleCt + elapsed + minRt >= nextRound and #result < count do
			table.insert(result, { name = "R"..roundNum, side = "Neutral", isRound = true, isActive = false })
			nextRound = nextRound + 1000; roundNum = roundNum + 1
		end
		elapsed = elapsed + minRt
		for _, u in ipairs(units) do u.remainingRt = u.remainingRt - minRt end

		local ready = {}
		for _, u in ipairs(units) do if u.remainingRt <= 0 then table.insert(ready, u) end end
		table.sort(ready, function(a,b) return a.id < b.id end)
		for _, u in ipairs(ready) do
			table.insert(result, { id = u.id, name = u.name, side = u.side, rt = 0, isEvent = u.isEvent, isRound = false, isActive = false })
			u.remainingRt = u.isEvent and 99999 or 450
			if #result >= count then break end
		end
		if #result >= count then break end
	end
	return result
end

local function updateTimeline(snapshot, previewUnitId, previewNewRt, previewEvent)
	if not snapshot or #snapshot == 0 then BattleHUD.UpdateTimeline({}); return end
	local tl = simulateTurnOrder(snapshot, 10, previewUnitId, previewNewRt, previewEvent)

	-- ALWAYS place the active unit at array index 1 (renders rightmost due to
	-- BattleHUD LayoutOrder = slotCount - i + 1). Independent of preview state.
	if activeUnitId then
		-- Step 1: Find and remove active unit from wherever simulation placed it
		local activeIdx = nil
		for i, e in ipairs(tl) do
			if not e.isEvent and not e.isRound and e.id == activeUnitId then
				activeIdx = i; break
			end
		end

		local activeEntry
		if activeIdx then
			activeEntry = table.remove(tl, activeIdx)
		else
			-- Fallback: build from timelineSnapshot if simulation excluded it
			local fallbackName = activeUnitId
			local fallbackSide = "Player"
			if timelineSnapshot then
				for _, s in ipairs(timelineSnapshot) do
					if s.id == activeUnitId then
						fallbackName = s.name; fallbackSide = s.side; break
					end
				end
			end
			activeEntry = { id = activeUnitId, name = fallbackName, side = fallbackSide, rt = 0, isEvent = false, isRound = false }
		end

		-- Step 2: Mark active; ensure all others are not active
		activeEntry.isActive = true
		for _, e in ipairs(tl) do e.isActive = false end

		-- Step 3: Insert at index 1 (rightmost position)
		table.insert(tl, 1, activeEntry)
	end

	-- Attach RT values
	for _, e in ipairs(tl) do
		if not e.isRound and not e.isEvent and timelineSnapshot then
			for _, s in ipairs(timelineSnapshot) do if s.id == e.id then e.rt = s.remainingRt; break end end
		end
	end

	BattleHUD.UpdateTimeline(tl)
end

--------------------------------------------------
-- ACTION BAR (builds data, tells HUD to enter ActionSelection)
--------------------------------------------------

local function enterActionSelection()
	if not currentPrompt then return end
	local prompt = currentPrompt
	inputMode = nil; selectedSkill = nil; clearHighlights()

	local moveEnabled = prompt.moveCandidates and #prompt.moveCandidates > 0
	local atkEnabled = prompt.attackTargets and #prompt.attackTargets > 0
	local hasSkills = prompt.skills and #prompt.skills > 0

	local function enterSkillSelection()
		inputMode = nil; selectedSkill = nil; clearHighlights()
		local entries = {}
		for _, skill in ipairs(prompt.skills or {}) do
			local canUse = skill.canUse and skill.targets and #skill.targets > 0
			table.insert(entries, {
				id = skill.id, name = skill.name, mpCost = skill.mpCost or 0, rtCost = skill.rtCost or 0,
				enabled = canUse,
				onPress = function()
					selectedSkill = skill; inputMode = "skill"; clearHighlights()
					BattleHUD.SetSkillData({
						name = skill.name, tags = table.concat(skill.tags or {}, ", "),
						mpCost = skill.mpCost, rtCost = skill.rtCost, range = skill.range,
						pattern = skill.pattern, channelTime = skill.channelTime,
						effects = skill.description or "",
					})
					-- Preview RT on timeline
					local pRt = (skill.rtCost or 60) + (prompt.unitBaseRt or 400) + (prompt.turnRtAccrued or 0)
					local pEv = skill.channelTime and skill.channelTime > 0 and { name = skill.name, side = "Player", rt = skill.channelTime } or nil
					updateTimeline(timelineSnapshot, prompt.unitId, pRt, pEv)
					-- Highlight targets
					local c = skill.isHealing and Color3.fromRGB(60,180,80) or Color3.fromRGB(180,150,60)
					for _, t in ipairs(skill.targets) do createTileHighlight(t.tileX, t.tileY, c, 0.5) end
					storedActorData.onBack = enterSkillSelection
					BattleHUD.SetState("TargetSelection")
				end,
			})
		end
		storedActorData.skillEntries = entries
		storedActorData.onBack = enterActionSelection
		BattleHUD.SetState("SkillSelection")
	end

	local actions = {
		{ id="Attack", text="Attack", enabled=atkEnabled, onPress=function()
			inputMode = "attack"; selectedSkill = nil; clearHighlights()
			BattleHUD.SetSkillData({ name="Basic Attack", tags="Physical",
				mpCost=0, rtCost=prompt.attackRt or 0, range=prompt.weaponRange or 1, pattern="Single",
				effects="Weapon Dmg: "..(prompt.weaponDamage or 0).." | RT Delay: "..(prompt.weaponRtDelay or 0) })
		local pRt = (prompt.attackRt or 80) + (prompt.unitBaseRt or 400) + (prompt.turnRtAccrued or 0)
			updateTimeline(timelineSnapshot, prompt.unitId, pRt)
			local c = Color3.fromRGB(200, 150, 60)
			for _, t in ipairs(prompt.attackTargets) do createTileHighlight(t.tileX, t.tileY, c, 0.5) end
			storedActorData.onBack = enterActionSelection
			BattleHUD.SetState("TargetSelection")
		end },
		{ id="Skill", text="Skill", enabled=hasSkills, onPress=enterSkillSelection },
		{ id="Move", text="Move", enabled=moveEnabled, onPress=function()
			inputMode = "move"; selectedSkill = nil; clearHighlights()
			local pRt = math.round((prompt.unitBaseRt or 400)*0.0625*2) + (prompt.unitBaseRt or 400) + (prompt.turnRtAccrued or 0)
			updateTimeline(timelineSnapshot, prompt.unitId, pRt)
			for _, tile in ipairs(prompt.moveCandidates) do createTileHighlight(tile.tileX, tile.tileY, Color3.fromRGB(60,120,180), 0.5) end
			storedActorData.onBack = enterActionSelection
			BattleHUD.SetSkillData(nil)
			BattleHUD.SetState("TargetSelection")
		end },
		{ id="Guard", text="Guard", enabled=not prompt.guardUsed, onPress=function()
			clearHighlights(); isPlayerTurn = false; inputMode = nil
			BattleHUD.SetState("Resolving")
			BattleEvents.PlayerCommand:FireServer({ actionType = "Guard" })
		end },
		{ id="Interact", text="Interact", enabled=false },
		{ id="Wait", text="Wait", enabled=true, onPress=function()
			clearHighlights(); isPlayerTurn = false; inputMode = nil
			BattleHUD.SetState("Resolving")
			BattleEvents.PlayerCommand:FireServer({ actionType = "Wait" })
		end },
	}

	storedActorData = {
		id = prompt.unitId, name = prompt.unitName, side = prompt.unitSide or "Player",
		currentHp = prompt.currentHp, maxHp = prompt.maxHp,
		currentMp = prompt.currentMp, maxMp = prompt.maxMp,
		currentAp = prompt.currentAp, remainingRt = (prompt.unitBaseRt or 400) + (prompt.turnRtAccrued or 0),
		actions = actions,
	}
	BattleHUD.SetActorData(storedActorData)
	BattleHUD.SetSkillData(nil)
	BattleHUD.SetTargetData(nil)
	BattleHUD.SetPreviewData(nil)
	BattleHUD.SetState("ActionSelection")
	updateTimeline(timelineSnapshot, nil, nil)
end

--------------------------------------------------
-- TILE SELECTION
--------------------------------------------------

local mapFolder = workspace:WaitForChild("TemplateViewerMap", 15)

local function getTileUnderMouse()
	local target = mouse.Target
	if target and target:IsA("BasePart") and target:GetAttribute("IsTemplateTile") then return target end
	if target and target:IsA("BasePart") then
		local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Include
		local parts = {}
		if mapFolder then for _, c in ipairs(mapFolder:GetChildren()) do
			if c:IsA("BasePart") and c:GetAttribute("IsTemplateTile") then table.insert(parts, c) end
		end end
		rp.FilterDescendantsInstances = parts
		local res = workspace:Raycast(Vector3.new(target.Position.X, target.Position.Y + 50, target.Position.Z), Vector3.new(0,-100,0), rp)
		return res and res.Instance or nil
	end
	return nil
end

local function tileToBattle(part)
	if not part then return nil, nil end
	local x, y = part:GetAttribute("X"), part:GetAttribute("Y")
	if x and y then return templateToBattle(x, y) end
	return nil, nil
end

--------------------------------------------------
-- COMMIT + CANCEL
--------------------------------------------------

local function commitCommand(command)
	clearHighlights(); isPlayerTurn = false; inputMode = nil; selectedSkill = nil; aimTarget = nil
	BattleHUD.SetState("Resolving")
	BattleEvents.PlayerCommand:FireServer(command)
end

local function cancelToTargeting()
	aimTarget = nil
	BattleHUD.SetTargetData(nil)
	BattleHUD.SetPreviewData(nil)
	-- Re-highlight valid targets
	if inputMode == "move" then
		clearHighlights()
		for _, tile in ipairs(currentPrompt.moveCandidates) do createTileHighlight(tile.tileX, tile.tileY, Color3.fromRGB(60,120,180), 0.5) end
	elseif inputMode == "attack" then
		clearHighlights()
		for _, t in ipairs(currentPrompt.attackTargets) do createTileHighlight(t.tileX, t.tileY, Color3.fromRGB(200,150,60), 0.5) end
	elseif inputMode == "skill" and selectedSkill then
		clearHighlights()
		local c = selectedSkill.isHealing and Color3.fromRGB(60,180,80) or Color3.fromRGB(180,150,60)
		for _, t in ipairs(selectedSkill.targets) do createTileHighlight(t.tileX, t.tileY, c, 0.5) end
	end
	BattleHUD.SetState("TargetSelection")
end

--------------------------------------------------
-- CLICK HANDLER
--------------------------------------------------

mouse.Button1Down:Connect(function()
	local tilePart = getTileUnderMouse()
	local bx, by = tileToBattle(tilePart)
	if not bx then return end
	if not isPlayerTurn or not inputMode then return end

	local state = BattleHUD.GetState()

	-- If in Preview state, clicking elsewhere cancels back to targeting
	if state == "Preview" then
		cancelToTargeting()
		return
	end

	-- TargetSelection: find valid target
	if state == "TargetSelection" then
		if inputMode == "move" then
			for _, tile in ipairs(currentPrompt.moveCandidates) do
				if tile.tileX == bx and tile.tileY == by then
					aimTarget = tile; clearHighlights()
					createTileHighlight(bx, by, Color3.fromRGB(255,220,60), 0.35)
					BattleHUD.SetPreviewData({
						onConfirm = function() commitCommand({ actionType = "Move", tileX = bx, tileY = by, pathCost = tile.pathCost }) end,
						onBack = cancelToTargeting,
					})
					BattleHUD.SetState("Preview")
					return
				end
			end
		elseif inputMode == "attack" then
			for _, t in ipairs(currentPrompt.attackTargets) do
				if t.tileX == bx and t.tileY == by then
					aimTarget = t; clearHighlights()
					createTileHighlight(bx, by, Color3.fromRGB(255,220,60), 0.35)
					BattleHUD.SetTargetData(unitData[t.id])
					BattleHUD.SetPreviewData({
						estimatedDamage = t.predicted or 0,
						hpAfter = unitData[t.id] and math.max(0, (unitData[t.id].currentHp or 0) - (t.predicted or 0)) or nil,
						rtDelay = currentPrompt.weaponRtDelay or 0,
						statusEffect = "None",
						onConfirm = function() commitCommand({ actionType = "Attack", targetId = t.id }) end,
						onBack = cancelToTargeting,
					})
					BattleHUD.SetState("Preview")
					return
				end
			end
		elseif inputMode == "skill" and selectedSkill then
			for _, t in ipairs(selectedSkill.targets) do
				if t.tileX == bx and t.tileY == by then
					aimTarget = t; clearHighlights()
					createTileHighlight(bx, by, Color3.fromRGB(255,220,60), 0.35)
					BattleHUD.SetTargetData(unitData[t.id])
					local statusEff = selectedSkill.appliesStatus or "None"
					BattleHUD.SetPreviewData({
						estimatedDamage = t.predicted or 0,
						isHealing = (t.predType == "healing"),
						hpAfter = unitData[t.id] and math.max(0, (unitData[t.id].currentHp or 0) - (t.predicted or 0)) or nil,
						rtDelay = 0,
						statusEffect = statusEff,
						mpSpent = selectedSkill.mpCost,
						onConfirm = function()
							local isChannel = selectedSkill.channelTime and selectedSkill.channelTime > 0
							commitCommand({ actionType = "Skill", skillId = selectedSkill.id, targetId = t.id })
						end,
						onBack = cancelToTargeting,
					})
					BattleHUD.SetState("Preview")
					return
				end
			end
		end
	end
end)

--------------------------------------------------
-- EVENT HANDLERS
--------------------------------------------------

BattleEvents.BattleStarted.OnClientEvent:Connect(function(data)
	BattleHUD.Cleanup()
	for _, c in ipairs(visualFolder:GetChildren()) do c:Destroy() end
	unitTokens = {}; unitData = {}; elevationMap = data.elevationMap
	for _, unit in ipairs(data.units) do
		unitData[unit.id] = unit; spawnToken(unit)
		updateHpBar(unit.id, unit.currentHp, unit.maxHp)
		updateMpBar(unit.id, unit.currentMp or 0, unit.maxMp or 0)
	end
end)

BattleEvents.TurnStarted.OnClientEvent:Connect(function(data)
	activeUnitId = data.unitId
	if unitData[data.unitId] then
		unitData[data.unitId].statuses = data.statuses
		if data.currentMp then unitData[data.unitId].currentMp = data.currentMp
			updateMpBar(data.unitId, data.currentMp, data.maxMp or unitData[data.unitId].maxMp or 0) end
	end
	if data.allUnitsRt and #data.allUnitsRt > 0 then
		timelineSnapshot = data.allUnitsRt; updateTimeline(data.allUnitsRt, nil, nil)
	end
	local token = unitTokens[data.unitId]
	if token then token.label.TextColor3 = Theme.Colors.TextGold end
end)

BattleEvents.TurnOrderUpdate.OnClientEvent:Connect(function(data)
	if not data then return end
	if data.units and #data.units > 0 then
		timelineSnapshot = data.units
		if data.currentCt then currentBattleCt = data.currentCt end
		if not aimTarget and (not isPlayerTurn or not inputMode) then updateTimeline(data.units, nil, nil) end
	end
end)

BattleEvents.PlayerTurnPrompt.OnClientEvent:Connect(function(prompt)
	currentPrompt = prompt
	activeUnitId = prompt.unitId
	timelineSnapshot = prompt.timeline
	if prompt.currentCt then currentBattleCt = prompt.currentCt end
	isPlayerTurn = true; inputMode = nil; selectedSkill = nil
	enterActionSelection()
end)

BattleEvents.UnitMoved.OnClientEvent:Connect(function(data)
	local token = unitTokens[data.unitId]; if not token then return end
	if unitData[data.unitId] then unitData[data.unitId].tileX = data.tileX; unitData[data.unitId].tileY = data.tileY end
	TweenService:Create(token.part, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {CFrame = CFrame.new(tileToWorld(data.tileX, data.tileY)) * CFrame.Angles(0,0,math.rad(90))}):Play()
end)

BattleEvents.UnitActed.OnClientEvent:Connect(function(data)
	updateHpBar(data.targetId, data.targetHp, data.targetMaxHp)
	if unitData[data.targetId] then unitData[data.targetId].currentHp = data.targetHp end
	local tt = unitTokens[data.targetId]
	if tt then
		if data.skillName then
			local at = unitTokens[data.actorId]
			if at then showFloatingText(at.part.Position, data.skillName, Theme.Colors.TextGold, 1.1) end
		end
		showFloatingText(tt.part.Position, "-"..data.damage, Theme.Colors.Danger)
	end
end)

BattleEvents.DotDamage.OnClientEvent:Connect(function(data)
	updateHpBar(data.unitId, data.currentHp, data.maxHp)
	if unitData[data.unitId] then unitData[data.unitId].currentHp = data.currentHp end
	local t = unitTokens[data.unitId]
	if t then showFloatingText(t.part.Position, "-"..data.damage.." "..data.statusId, Theme.GetStatusColor(data.statusId)) end
end)

BattleEvents.HealingApplied.OnClientEvent:Connect(function(data)
	updateHpBar(data.targetId, data.targetHp, data.targetMaxHp)
	if unitData[data.targetId] then unitData[data.targetId].currentHp = data.targetHp end
	local tt = unitTokens[data.targetId]
	if tt then
		if data.skillName then local at = unitTokens[data.actorId]; if at then showFloatingText(at.part.Position, data.skillName, Theme.Colors.Success, 1.1) end end
		showFloatingText(tt.part.Position, "+"..data.amount, Theme.Colors.Success)
	end
end)

BattleEvents.StatusApplied.OnClientEvent:Connect(function(data)
	if unitData[data.unitId] then
		if not unitData[data.unitId].statuses then unitData[data.unitId].statuses = {} end
		local found = false
		for _, ex in ipairs(unitData[data.unitId].statuses) do
			if ex.id == data.statusId then ex.remainingTurns = data.remainingTurns; found = true; break end
		end
		if not found then table.insert(unitData[data.unitId].statuses, { id = data.statusId, remainingTurns = data.remainingTurns or 0 }) end
	end
	local t = unitTokens[data.unitId]
	if t then showFloatingText(t.part.Position + Vector3.new(0,1,0), "+"..data.statusId, Theme.GetStatusColor(data.statusId), 1.2) end
end)

BattleEvents.StatusExpired.OnClientEvent:Connect(function(data)
	if unitData[data.unitId] and unitData[data.unitId].statuses then
		for i, s in ipairs(unitData[data.unitId].statuses) do if s.id == data.statusId then table.remove(unitData[data.unitId].statuses, i); break end end
	end
	local t = unitTokens[data.unitId]
	if t then showFloatingText(t.part.Position + Vector3.new(0,1,0), "-"..data.statusId, Theme.Colors.TextSecondary, 1.2) end
end)

BattleEvents.ChannelFizzled.OnClientEvent:Connect(function(data)
	local t = unitTokens[data.actorId]
	if t then showFloatingText(t.part.Position, (data.skillName or "Skill").." fizzled!", Theme.Colors.Warning, 1.5) end
end)

BattleEvents.TurnEnded.OnClientEvent:Connect(function(data)
	local t = unitTokens[data.unitId]; if t then t.label.TextColor3 = Theme.Colors.TextPrimary end
	if unitData[data.unitId] then
		unitData[data.unitId].statuses = data.statuses
		if data.currentMp then unitData[data.unitId].currentMp = data.currentMp; updateMpBar(data.unitId, data.currentMp, unitData[data.unitId].maxMp or 0) end
	end
end)

BattleEvents.UnitDefeated.OnClientEvent:Connect(function(data)
	local t = unitTokens[data.unitId]; if t then t.part.Color = Color3.fromRGB(60,60,60); t.part.Transparency = 0.4 end
	if unitData[data.unitId] then unitData[data.unitId].isAlive = false end
end)

BattleEvents.GuardActivated.OnClientEvent:Connect(function(data)
	-- Show shield stance indicator on the unit
	local token = unitTokens[data.unitId]
	if token then
		showFloatingText(token.part.Position, "🛡 GUARD", Color3.fromRGB(100, 200, 255), 1.2)
		-- Tint the token slightly blue to indicate Guard stance
		token.part.Color = Color3.fromRGB(80, 140, 200)
	end
	if unitData[data.unitId] then
		unitData[data.unitId].isGuarding = true
	end
end)

BattleEvents.BattleEnded.OnClientEvent:Connect(function(data)
	isPlayerTurn = false; inputMode = nil; clearHighlights()
	BattleHUD.SetState("BattleEnded")

	-- Show result
	local gui = Instance.new("ScreenGui"); gui.Name = "BattleResult"; gui.ResetOnSpawn = false
	gui.DisplayOrder = 90; gui.Parent = player:WaitForChild("PlayerGui")
	local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.fromOffset(300,60)
	lbl.AnchorPoint = Vector2.new(0.5,0.5); lbl.Position = UDim2.fromScale(0.5,0.4)
	lbl.BackgroundColor3 = Theme.Colors.Background; lbl.BackgroundTransparency = 0.2
	lbl.Font = Theme.Font.Display; lbl.TextSize = 28; lbl.BorderSizePixel = 0
	lbl.TextColor3 = data.winner == "Player" and Theme.Colors.TextGold or Theme.Colors.Danger
	lbl.Text = data.winner == "Player" and "VICTORY" or "DEFEAT"; lbl.Parent = gui
	Instance.new("UICorner", lbl).CornerRadius = Theme.CornerRadius.lg
	task.delay(5, function() if gui.Parent then gui:Destroy() end; BattleHUD.Cleanup() end)
end)

_G.CTRBLXAI_SelectTileAt = function() end

print("[CTRBLXAI] BattleVisualClient v3 loaded.")
