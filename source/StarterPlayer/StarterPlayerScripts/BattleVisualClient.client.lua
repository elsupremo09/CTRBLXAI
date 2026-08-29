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
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")

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

local CameraController = require(
	player:WaitForChild("PlayerScripts")
		:WaitForChild("CameraController", 10)
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
local storedActorData = nil -- shared across enterActionSelection and click handlers

--------------------------------------------------
-- HIGHLIGHTS
--------------------------------------------------

local function clearHighlights()
	for _, p in ipairs(highlightParts) do p:Destroy() end
	highlightParts = {}
end

-- Highlight modes with distinct visual styles
local HIGHLIGHT_STYLES = {
	move     = { color = Color3.fromRGB(50, 100, 170), transparency = 0.55, material = Enum.Material.SmoothPlastic },
	target   = { color = Color3.fromRGB(200, 170, 50),  transparency = 0.50, material = Enum.Material.Neon },
	selected = { color = Color3.fromRGB(255, 220, 60),  transparency = 0.35, material = Enum.Material.Neon },
	aoe      = { color = Color3.fromRGB(200, 100, 40),  transparency = 0.50, material = Enum.Material.Neon },
	invalid  = { color = Color3.fromRGB(100, 30, 30),   transparency = 0.70, material = Enum.Material.SmoothPlastic },
	current  = { color = Color3.fromRGB(80, 160, 255),  transparency = 0.50, material = Enum.Material.Neon },
}

local function createTileHighlight(tx, ty, colorOrStyle, transparency)
	local style = type(colorOrStyle) == "string" and HIGHLIGHT_STYLES[colorOrStyle] or nil
	local color = style and style.color or colorOrStyle or Color3.fromRGB(200, 170, 50)
	local trans = style and style.transparency or transparency or 0.55
	local mat = style and style.material or Enum.Material.Neon

	local elev = getElevation(tx, ty)
	local pos = Vector3.new(MAP_OFFSET_X + (tx-0.5)*TILE_SIZE, tileSurfaceY(elev)+0.12, MAP_OFFSET_Z + (ty-0.5)*TILE_SIZE)

	local p = Instance.new("Part")
	p.Name = "HL_"..tx.."_"..ty
	p.Anchored, p.CanCollide, p.CanQuery = true, false, false
	p.Size = Vector3.new(TILE_SIZE*0.80, 0.08, TILE_SIZE*0.80)
	p.Position = pos
	p.Color = color
	p.Transparency = trans
	p.Material = mat
	p.Parent = visualFolder
	table.insert(highlightParts, p)
end

--------------------------------------------------
-- UNIT SELECTION RING (glowing disc under a unit)
--------------------------------------------------

local selectionRing = nil

local function showSelectionRing(uid)
	if selectionRing then selectionRing:Destroy(); selectionRing = nil end
	local data = unitData[uid]
	if not data or data.isAlive == false then return end
	local worldPos = tileToWorld(data.tileX, data.tileY)

	local ring = Instance.new("Part")
	ring.Name = "SelectionRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.15, TILE_SIZE * 0.7, TILE_SIZE * 0.7)
	ring.CFrame = CFrame.new(worldPos - Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored, ring.CanCollide, ring.CanQuery = true, false, false
	ring.Color = Theme.Colors.BorderFocused
	ring.Transparency = 0.3
	ring.Material = Enum.Material.Neon
	ring.Parent = visualFolder
	selectionRing = ring
end

local function hideSelectionRing()
	if selectionRing then selectionRing:Destroy(); selectionRing = nil end
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

-- Specialized combat feedback (larger damage, smaller status/info)
local function showDamageText(worldPos, amount, isHeal)
	local text = isHeal and ("+"..amount) or ("-"..amount)
	local color = isHeal and Theme.Colors.Success or Theme.Colors.Danger
	-- Use larger text for damage
	local dur = 1.1
	local anchor = Instance.new("Part"); anchor.Anchored = true; anchor.CanCollide = false
	anchor.CanQuery = false; anchor.Transparency = 1; anchor.Size = Vector3.new(0.1,0.1,0.1)
	anchor.Position = worldPos + Vector3.new(0, 2.5, 0); anchor.Parent = visualFolder
	local bb = Instance.new("BillboardGui"); bb.Size = UDim2.new(0,140,0,40); bb.AlwaysOnTop = true; bb.Parent = anchor
	local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.fromScale(1,1); lbl.BackgroundTransparency = 1
	lbl.Font = Theme.Font.Display; lbl.TextSize = 26; lbl.TextColor3 = color
	lbl.TextStrokeTransparency = 0.1; lbl.TextStrokeColor3 = Color3.fromRGB(0,0,0)
	lbl.Text = text; lbl.Parent = bb
	TweenService:Create(anchor, TweenInfo.new(dur, Enum.EasingStyle.Quad), {Position = worldPos + Vector3.new(0,6,0)}):Play()
	TweenService:Create(lbl, TweenInfo.new(dur*0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, dur*0.5), {TextTransparency=1, TextStrokeTransparency=1}):Play()
	task.delay(dur + 0.1, function() anchor:Destroy() end)
end

local function showStatusText(worldPos, text, color)
	showFloatingText(worldPos + Vector3.new(0, 0.5, 0), text, color or Theme.Colors.Info, 1.2)
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
					local pRt = (skill.rtCost or 60) + (prompt.unitBaseRt or 400) + (prompt.turnRtAccrued or 0)
					local pEv = skill.channelTime and skill.channelTime > 0 and { name = skill.name, side = "Player", rt = skill.channelTime } or nil
					updateTimeline(timelineSnapshot, prompt.unitId, pRt, pEv)
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

	-- 4x2 grid: Attack, Skill, Move, Item, Guard, Interact, Wait, Stance
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
			for _, tile in ipairs(prompt.moveCandidates) do createTileHighlight(tile.tileX, tile.tileY, "move") end
			storedActorData.onBack = enterActionSelection
			BattleHUD.SetSkillData(nil)
			BattleHUD.SetState("TargetSelection")
		end },
		{ id="Item", text="Item", enabled=false },
		{ id="Guard", text="Guard", enabled=not prompt.guardUsed, onPress=function()
			clearHighlights(); isPlayerTurn = false; inputMode = nil
			BattleHUD.SetState("Resolving")
			BattleHUD.AddLogEntry((prompt.unitName or "Unit") .. " guards.")
			BattleEvents.PlayerCommand:FireServer({ actionType = "Guard" })
		end },
		{ id="Interact", text="Interact", enabled=false },
		{ id="Wait", text="Wait", enabled=true, onPress=function()
			clearHighlights(); isPlayerTurn = false; inputMode = nil
			BattleHUD.SetState("Resolving")
			BattleHUD.AddLogEntry((prompt.unitName or "Unit") .. " waits.")
			BattleEvents.PlayerCommand:FireServer({ actionType = "Wait" })
		end },
		{ id="Stance", text="Stance", enabled=false },
	}

	-- Get actor tile info
	local actorUnit = unitData[prompt.unitId]
	local actorTileX = actorUnit and actorUnit.tileX or 0
	local actorTileY = actorUnit and actorUnit.tileY or 0
	local actorElev = getElevation(actorTileX, actorTileY)

	storedActorData = {
		id = prompt.unitId, name = prompt.unitName, side = prompt.unitSide or "Player",
		currentHp = prompt.currentHp, maxHp = prompt.maxHp,
		currentMp = prompt.currentMp, maxMp = prompt.maxMp,
		currentAp = prompt.currentAp, maxAp = prompt.maxAp or 2,
		remainingRt = (prompt.unitBaseRt or 400) + (prompt.turnRtAccrued or 0),
		doctrine = prompt.doctrine or "",
		level = prompt.level,
		tileX = actorTileX, tileY = actorTileY, elevation = actorElev,
		statuses = actorUnit and actorUnit.statuses or {},
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
		for _, tile in ipairs(currentPrompt.moveCandidates) do createTileHighlight(tile.tileX, tile.tileY, "move") end
	elseif inputMode == "attack" then
		clearHighlights()
		for _, t in ipairs(currentPrompt.attackTargets) do createTileHighlight(t.tileX, t.tileY, "target") end
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


local function processTileClick(bx, by)
	
	-- Always show tile info
	local terrainId = GameConstants.GetTerrainId(bx, by)
	local elevation = getElevation(bx, by)
	local moveCost = GameConstants.GetTerrainCost(bx, by)
	BattleHUD.ShowTileInfo({
		terrainName = terrainId,
		elevation = elevation,
		moveCost = moveCost,
		coords = string.format("(%d, %d)", bx, by),
	})
	
	-- Always allow inspecting units by clicking (shows in right panel)
	for uid, data in pairs(unitData) do
		if data.tileX == bx and data.tileY == by and data.isAlive ~= false then
			local state = BattleHUD.GetState()
			if state == "ActionSelection" or state == "SkillSelection" or state == "Idle" then
				BattleHUD.ShowInspectUnit(data)
			end
			break
		end
	end
	
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
					createTileHighlight(bx, by, "selected")
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
					createTileHighlight(bx, by, "selected")
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
					createTileHighlight(bx, by, "selected")
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
end


-- TILE SELECTION: Mouse (immediate on click) + Touch (deferred to tap intent)
UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	-- Guard: ignore clicks consumed by GUI buttons/panels
	if gameProcessedEvent then return end
	-- Only handle MOUSE left click here. Touch is handled by tap intent below.
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

	-- Additional guard: check if mouse is over a visible HUD panel
	if CameraController.IsOverUI(input.Position) then return end

	local tilePart = getTileUnderMouse()
	local bx, by = tileToBattle(tilePart)
	if not bx then return end

	processTileClick(bx, by)
end)

--------------------------------------------------
-- TOUCH TAP POLLING
-- Checks each frame for a completed tap from CameraController.
-- On tap, raycasts from the tap screen position to find a tile.
--------------------------------------------------

game:GetService("RunService").Heartbeat:Connect(function()
	local tapPos = CameraController.ConsumeTapIntent()
	if not tapPos then return end

	-- Raycast from tap position to find tile
	local cam = workspace.CurrentCamera
	if not cam then return end
	local ray = cam:ViewportPointToRay(tapPos.X, tapPos.Y)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	local tileParts = {}
	if mapFolder then
		for _, c in ipairs(mapFolder:GetChildren()) do
			if c:IsA("BasePart") and c:GetAttribute("IsTemplateTile") then
				table.insert(tileParts, c)
			end
		end
	end
	rayParams.FilterDescendantsInstances = tileParts
	local result = workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)
	local tilePart = result and result.Instance or nil
	if not tilePart then return end

	local bx, by = tileToBattle(tilePart)
	if not bx then return end

	processTileClick(bx, by)
end)


--------------------------------------------------
-- DEV CAMERA TEST PANEL (temporary, remove when Slice 7 UI provides buttons)
-- Visible only during battle. Blocks input across its bounds.
--------------------------------------------------

local devCameraPanel = nil

local function createDevCameraPanel()
	if not RunService:IsStudio() then return end
	if devCameraPanel then devCameraPanel:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = "DevCameraTest"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 95
	gui.Parent = player:WaitForChild("PlayerGui")
	devCameraPanel = gui

	local frame = Instance.new("Frame")
	frame.Name = "DevPanel"
	frame.Size = UDim2.fromOffset(120, 100)
	frame.Position = UDim2.new(0.5, 0, 0, 4)
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Active = true  -- blocks input passthrough
	frame.Parent = gui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
	local stroke = Instance.new("UIStroke", frame)
	stroke.Color = Color3.fromRGB(200, 200, 50); stroke.Thickness = 1

	local layout = Instance.new("UIListLayout", frame)
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	local pad = Instance.new("UIPadding", frame)
	pad.PaddingTop = UDim.new(0, 3); pad.PaddingLeft = UDim.new(0, 3)
	pad.PaddingRight = UDim.new(0, 3)

	-- Title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 14)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.SourceSansBold; title.TextSize = 9
	title.TextColor3 = Color3.fromRGB(200, 200, 50)
	title.Text = "DEV CAMERA TEST"; title.LayoutOrder = 0
	title.Parent = frame

	local function makeBtn(text, order, callback)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, 22)
		btn.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
		btn.BackgroundTransparency = 0.2
		btn.Font = Enum.Font.SourceSans; btn.TextSize = 11
		btn.TextColor3 = Color3.fromRGB(220, 220, 220)
		btn.Text = text; btn.LayoutOrder = order
		btn.BorderSizePixel = 0; btn.Parent = frame
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
		btn.MouseButton1Click:Connect(callback)
		return btn
	end

	makeBtn("FOCUS ACTIVE", 1, function()
		local uid = activeUnitId
		local udata = uid and unitData[uid]
		if udata and udata.tileX and udata.tileY then
			CameraController.FocusActiveUnit(tileToWorld(udata.tileX, udata.tileY))
		else
			local cx = MAP_OFFSET_X + (MAP_WIDTH * TILE_SIZE) / 2
			local cz = MAP_OFFSET_Z + (MAP_HEIGHT * TILE_SIZE) / 2
			CameraController.FocusActiveUnit(Vector3.new(cx, 0, cz))
		end
	end)

	makeBtn("FOCUS SELECTED", 2, function()
		local iid = BattleHUD.GetInspectedUnitId()
		local idata = iid and unitData[iid]
		if idata and idata.tileX and idata.tileY then
			CameraController.FocusSelectedUnit(tileToWorld(idata.tileX, idata.tileY))
		end
	end)

	makeBtn("RESET CAMERA", 3, function()
		local uid = activeUnitId
		local udata = uid and unitData[uid]
		local focusPos = nil
		if udata and udata.tileX and udata.tileY then
			focusPos = tileToWorld(udata.tileX, udata.tileY)
		end
		CameraController.ResetTacticalView(focusPos)
	end)
end

local function destroyDevCameraPanel()
	if devCameraPanel then devCameraPanel:Destroy(); devCameraPanel = nil end
end

--------------------------------------------------
-- EVENT HANDLERS
--------------------------------------------------

BattleEvents.BattleStarted.OnClientEvent:Connect(function(data)
	-- Supply playable battlefield bounds to camera (8×8 battle grid)
	-- NOTE: Future procedural maps must supply these dynamically.
	CameraController.SetBattlefieldBounds({
		minX = MAP_OFFSET_X,
		maxX = MAP_OFFSET_X + MAP_WIDTH * TILE_SIZE,
		minZ = MAP_OFFSET_Z,
		maxZ = MAP_OFFSET_Z + MAP_HEIGHT * TILE_SIZE,
		tileSize = TILE_SIZE,
		source = "battle_client",
	})

	-- Enter battle control mode (disable default controls, hide character)
	-- Pass center of battle grid as initial focus
	local centerX = MAP_OFFSET_X + (MAP_WIDTH * TILE_SIZE) / 2
	local centerZ = MAP_OFFSET_Z + (MAP_HEIGHT * TILE_SIZE) / 2
	CameraController.EnterBattle(Vector3.new(centerX, 0, centerZ))

	createDevCameraPanel()

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
		-- Clear Guard buff (expires on new turn) and restore token color
		if unitData[data.unitId].isGuarding then
			unitData[data.unitId].isGuarding = false
			local token = unitTokens[data.unitId]
			if token then token.part.Color = Theme.GetSideColor(unitData[data.unitId].side) end
			-- Remove Guard from visible statuses
			for i, s in ipairs(unitData[data.unitId].statuses or {}) do
				if s.id == "Guard" then table.remove(unitData[data.unitId].statuses, i); break end
			end
		end
		if data.currentMp then unitData[data.unitId].currentMp = data.currentMp
			updateMpBar(data.unitId, data.currentMp, data.maxMp or unitData[data.unitId].maxMp or 0) end
	end
	if data.allUnitsRt and #data.allUnitsRt > 0 then
		timelineSnapshot = data.allUnitsRt; updateTimeline(data.allUnitsRt, nil, nil)
	end
	local token = unitTokens[data.unitId]
	if token then token.label.TextColor3 = Theme.Colors.TextGold end
	showSelectionRing(data.unitId)
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

	-- Move selection ring to follow active unit
	if selectionRing and data.unitId == activeUnitId then
		local newPos = tileToWorld(data.tileX, data.tileY) - Vector3.new(0, 0.7, 0)
		TweenService:Create(selectionRing, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {CFrame = CFrame.new(newPos) * CFrame.Angles(0,0,math.rad(90))}):Play()
	end
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
		showDamageText(tt.part.Position, data.damage, false)
	end
	-- Battle log
	local actorName = unitData[data.actorId] and unitData[data.actorId].name or "?"
	local targetName = unitData[data.targetId] and unitData[data.targetId].name or "?"
	local logText = data.skillName and (actorName.." used "..data.skillName.." on "..targetName..". -"..data.damage.." HP")
		or (actorName.." attacks "..targetName..". -"..data.damage.." HP")
	BattleHUD.AddLogEntry(logText)
end)

BattleEvents.DotDamage.OnClientEvent:Connect(function(data)
	updateHpBar(data.unitId, data.currentHp, data.maxHp)
	if unitData[data.unitId] then unitData[data.unitId].currentHp = data.currentHp end
	local t = unitTokens[data.unitId]
	if t then showDamageText(t.part.Position, data.damage, false)
		showStatusText(t.part.Position, data.statusId, Theme.GetStatusColor(data.statusId)) end
	local uName = unitData[data.unitId] and unitData[data.unitId].name or "?"
	BattleHUD.AddLogEntry(uName.." takes "..data.damage.." "..data.statusId.." damage.")
end)

BattleEvents.HealingApplied.OnClientEvent:Connect(function(data)
	updateHpBar(data.targetId, data.targetHp, data.targetMaxHp)
	if unitData[data.targetId] then unitData[data.targetId].currentHp = data.targetHp end
	local tt = unitTokens[data.targetId]
	if tt then
		if data.skillName then local at = unitTokens[data.actorId]; if at then showFloatingText(at.part.Position, data.skillName, Theme.Colors.Success, 1.1) end end
		showDamageText(tt.part.Position, data.amount, true)
	end
	local actorName = unitData[data.actorId] and unitData[data.actorId].name or "?"
	local targetName = unitData[data.targetId] and unitData[data.targetId].name or "?"
	BattleHUD.AddLogEntry(actorName.." heals "..targetName..". +"..data.amount.." HP")
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
	if t then showStatusText(t.part.Position, "+"..data.statusId, Theme.GetStatusColor(data.statusId)) end
end)

BattleEvents.StatusExpired.OnClientEvent:Connect(function(data)
	if unitData[data.unitId] and unitData[data.unitId].statuses then
		for i, s in ipairs(unitData[data.unitId].statuses) do if s.id == data.statusId then table.remove(unitData[data.unitId].statuses, i); break end end
	end
	local t = unitTokens[data.unitId]
	if t then showStatusText(t.part.Position, "-"..data.statusId, Theme.Colors.TextSecondary) end
end)

BattleEvents.ChannelFizzled.OnClientEvent:Connect(function(data)
	local t = unitTokens[data.actorId]
	if t then showFloatingText(t.part.Position, (data.skillName or "Skill").." fizzled!", Theme.Colors.Warning, 1.5) end
end)

BattleEvents.TurnEnded.OnClientEvent:Connect(function(data)
	local t = unitTokens[data.unitId]; if t then t.label.TextColor3 = Theme.Colors.TextPrimary end
	hideSelectionRing()
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
	local token = unitTokens[data.unitId]
	local mitigationPct = math.round((data.mitigation or 0.35) * 100)

	if token then
		showFloatingText(token.part.Position, "GUARD " .. mitigationPct .. "%", Color3.fromRGB(100, 200, 255), 1.2)
		token.part.Color = Color3.fromRGB(80, 140, 200)
	end
	if unitData[data.unitId] then
		unitData[data.unitId].isGuarding = true
		-- Add Guard as a visible buff status (1 turn, shows mitigation %)
		if not unitData[data.unitId].statuses then
			unitData[data.unitId].statuses = {}
		end
		-- Remove existing guard entry if re-applied (shouldn't happen, but safe)
		for i, s in ipairs(unitData[data.unitId].statuses) do
			if s.id == "Guard" then table.remove(unitData[data.unitId].statuses, i); break end
		end
		table.insert(unitData[data.unitId].statuses, {
			id = "Guard",
			remainingTurns = 1,
			value = mitigationPct .. "%",
		})
	end
end)

BattleEvents.BattleEnded.OnClientEvent:Connect(function(data)
	isPlayerTurn = false; inputMode = nil; clearHighlights()
	hideSelectionRing()
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
	task.delay(5, function()
		if gui.Parent then gui:Destroy() end
		BattleHUD.Cleanup()
		destroyDevCameraPanel()
		CameraController.ExitBattle()
	end)
end)

_G.CTRBLXAI_SelectTileAt = function() end



print("[CTRBLXAI] BattleVisualClient v3 loaded.")
