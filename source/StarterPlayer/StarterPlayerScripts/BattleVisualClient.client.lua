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
local devLastInspectedId = nil -- tracks last tile-clicked unit for Kill At Tile (dev only)
local inputMode       = nil -- "move","attack","skill"
local selectedSkill   = nil
local highlightParts  = {}
local aimTarget       = nil
local storedActorData = nil -- shared across enterActionSelection and click handlers

-- Battle presentation: single table of everything the HUD needs to display
local bp = {
	state = "Idle",
	actor = nil,
	target = nil,
	skill = nil,
	preview = nil,
	tile = nil,
	inspectedEntityId = nil,
}

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
	local tl = simulateTurnOrder(snapshot, 12, previewUnitId, previewNewRt, previewEvent)

	-- Build the final entries list:
	-- [1] = pinned NOW active unit
	-- [2..] = future events in RT order, including the active unit's ghost

	local finalEntries = {}

	-- Pinned NOW slot
	if activeUnitId then
		local nowName = activeUnitId
		local nowSide = "Player"
		local nowTileX, nowTileY
		if unitData[activeUnitId] then
			nowName = unitData[activeUnitId].name or activeUnitId
			nowSide = unitData[activeUnitId].side or "Player"
			nowTileX = unitData[activeUnitId].tileX
			nowTileY = unitData[activeUnitId].tileY
		elseif timelineSnapshot then
			for _, s in ipairs(timelineSnapshot) do
				if s.id == activeUnitId then nowName = s.name; nowSide = s.side; break end
			end
		end
		table.insert(finalEntries, {
			id = activeUnitId, name = nowName, side = nowSide,
			tileX = nowTileX, tileY = nowTileY,
			rt = 0, isActive = true, isGhost = false,
			isEvent = false, isRound = false,
		})
	end

	-- Remaining entries from simulation (future turns)
	local activeSeenCount = 0
	local seenUnits = {}  -- track first occurrence of each unit
	local hasPreviewRt = (previewUnitId ~= nil and previewNewRt ~= nil)
	for _, e in ipairs(tl) do
		-- Enrich with tile data for click resolution
		local enriched = {
			id = e.id, name = e.name, side = e.side, rt = e.rt,
			isActive = false, isEvent = e.isEvent or false, isRound = e.isRound or false,
			isGhost = false,
		}

		-- Active unit ghost logic:
		-- Without preview: simulation has active unit at RT=0 (current turn) + RT=450 (next).
		--   Skip 1st (duplicate of NOW), keep 2nd as ghost.
		-- With preview: simulation has active unit at RT=previewNewRt (next turn) only.
		--   Keep 1st as ghost (it's already at the correct position).
		if activeUnitId and not e.isEvent and not e.isRound and e.id == activeUnitId then
			activeSeenCount = activeSeenCount + 1
			if not hasPreviewRt and activeSeenCount == 1 then
				enriched = nil  -- current turn duplicate (no preview active)
			elseif activeSeenCount == 2 then
				enriched.isGhost = true
				enriched.rt = previewNewRt or enriched.rt
			elseif hasPreviewRt and activeSeenCount == 1 then
				enriched.isGhost = true
				enriched.rt = previewNewRt or enriched.rt
			else
				enriched = nil  -- far future, skip
			end
		end

		-- Skip duplicate appearances of non-active units (keep only first)
		if enriched and not e.isEvent and not e.isRound and not enriched.isGhost then
			if seenUnits[e.id] then
				enriched = nil
			else
				seenUnits[e.id] = true
			end
		end

		if enriched then
			-- Attach tile coordinates from unitData
			local baseId = e.id
			-- Channel events have id like "unit_ch" — extract the base unit id
			if e.isEvent and type(e.id) == "string" and string.sub(e.id, -3) == "_ch" then
				baseId = string.sub(e.id, 1, -4)
				enriched.casterId = baseId
				enriched.casterName = unitData[baseId] and unitData[baseId].name or nil
			end
			if unitData[baseId] then
				enriched.tileX = unitData[baseId].tileX
				enriched.tileY = unitData[baseId].tileY
			end

			-- Attach RT from snapshot
			-- Don't overwrite ghost RT — it carries the simulation-computed future RT
			if not e.isRound and not e.isEvent and not enriched.isGhost and timelineSnapshot then
				for _, s in ipairs(timelineSnapshot) do
					if s.id == e.id then enriched.rt = s.remainingRt; break end
				end
			end

			table.insert(finalEntries, enriched)
		end
	end

	BattleHUD.UpdateTimeline(finalEntries)
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
					bp.skill = {
						name = skill.name, tags = table.concat(skill.tags or {}, ", "),
						mpCost = skill.mpCost, rtCost = skill.rtCost, range = skill.range,
						pattern = skill.pattern, channelTime = skill.channelTime,
						effects = skill.description or "",
					}
					local pRt = (skill.rtCost or 60) + (prompt.unitBaseRt or 400) + (prompt.turnRtAccrued or 0)
					local pEv = skill.channelTime and skill.channelTime > 0 and { name = skill.name, side = "Player", rt = skill.channelTime } or nil
					updateTimeline(timelineSnapshot, prompt.unitId, pRt, pEv)
					local c = skill.isHealing and Color3.fromRGB(60,180,80) or Color3.fromRGB(180,150,60)
					for _, t in ipairs(skill.targets) do createTileHighlight(t.tileX, t.tileY, c, 0.5) end
					storedActorData.onBack = enterSkillSelection
					bp.state = "TargetSelection"; BattleHUD.Render(bp)
				end,
			})
		end
		storedActorData.skillEntries = entries
		storedActorData.onBack = enterActionSelection
		bp.state = "SkillSelection"; BattleHUD.Render(bp)
	end

	-- 4x2 grid: Attack, Skill, Move, Item, Guard, Interact, Wait, Stance
	local actions = {
		{ id="Move", text="Move", enabled=moveEnabled, onPress=function()
			inputMode = "move"; selectedSkill = nil; clearHighlights()
			local pRt = math.round((prompt.unitBaseRt or 400)*0.0625*2) + (prompt.unitBaseRt or 400) + (prompt.turnRtAccrued or 0)
			updateTimeline(timelineSnapshot, prompt.unitId, pRt)
			for _, tile in ipairs(prompt.moveCandidates) do createTileHighlight(tile.tileX, tile.tileY, "move") end
			storedActorData.onBack = enterActionSelection
			bp.skill = nil
			bp.state = "TargetSelection"; BattleHUD.Render(bp)
		end },
		{ id="Commands", text="Commands", enabled=true, isSubmenu=true, subActions={
			{ id="Attack", text="Attack", enabled=atkEnabled, onPress=function()
				inputMode = "attack"; selectedSkill = nil; clearHighlights()
				bp.skill = { name="Basic Attack", tags="Physical",
					mpCost=0, rtCost=prompt.attackRt or 0, range=prompt.weaponRange or 1, pattern="Single",
					effects="Weapon Dmg: "..(prompt.weaponDamage or 0).." | RT Delay: "..(prompt.weaponRtDelay or 0) }
				local pRt = (prompt.attackRt or 80) + (prompt.unitBaseRt or 400) + (prompt.turnRtAccrued or 0)
				updateTimeline(timelineSnapshot, prompt.unitId, pRt)
				local c = Color3.fromRGB(200, 150, 60)
				for _, t in ipairs(prompt.attackTargets) do createTileHighlight(t.tileX, t.tileY, c, 0.5) end
				storedActorData.onBack = enterActionSelection
				bp.state = "TargetSelection"; BattleHUD.Render(bp)
			end },
			{ id="Interact", text="Interact", enabled=false },
			{ id="Push", text="Push", enabled=#(prompt.pushTargets or {}) > 0, onPress=function()
				inputMode = "push"; selectedSkill = nil; clearHighlights()
				local previewRt = (prompt.pushRt or 40) + (prompt.unitBaseRt or 400)
				updateTimeline(timelineSnapshot, prompt.unitId, previewRt)
				for _, t in ipairs(prompt.pushTargets or {}) do
					createTileHighlight(t.tileX, t.tileY, Color3.fromRGB(255, 180, 40), 0.45)
				end
				storedActorData.onBack = enterActionSelection
				bp.state = "TargetSelection"; BattleHUD.Render(bp)
			end },
			{ id="Guard", text="Guard", enabled=not prompt.guardUsed, onPress=function()
				clearHighlights(); isPlayerTurn = false; inputMode = nil
				bp.state = "Resolving"; BattleHUD.Render(bp)
				BattleHUD.AddLogEntry((prompt.unitName or "Unit") .. " guards.")
				BattleEvents.PlayerCommand:FireServer({ actionType = "Guard" })
			end },
		}},
		{ id="Skill", text="Skills", enabled=hasSkills, onPress=enterSkillSelection },
		{ id="Item", text="Items", enabled=false },
		{ id="Wait", text="Wait", enabled=true, onPress=function()
			clearHighlights(); isPlayerTurn = false; inputMode = nil
			bp.state = "Resolving"; BattleHUD.Render(bp)
			BattleHUD.AddLogEntry((prompt.unitName or "Unit") .. " waits.")
			BattleEvents.PlayerCommand:FireServer({ actionType = "Wait" })
		end },
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
		race = prompt.race or nil,
		tileX = actorTileX, tileY = actorTileY, elevation = actorElev,
		statuses = actorUnit and actorUnit.statuses or {},
		actions = actions,
	}
	bp.actor = storedActorData
	bp.skill = nil
	bp.target = nil
	bp.preview = nil

	-- Auto-highlight move range on action selection (spatial awareness)
	clearHighlights()
	if prompt.moveCandidates then
		for _, tile in ipairs(prompt.moveCandidates) do
			createTileHighlight(tile.tileX, tile.tileY, "move")
		end
	end

	bp.state = "ActionSelection"; BattleHUD.Render(bp)
	-- Pass base RT so ghost shows where unit will be if they end turn now
	updateTimeline(timelineSnapshot, prompt.unitId, (prompt.unitBaseRt or 400) + (prompt.turnRtAccrued or 0))
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
	bp.state = "Resolving"; BattleHUD.Render(bp)
	BattleEvents.PlayerCommand:FireServer(command)
end

local function cancelToTargeting()
	aimTarget = nil
	bp.target = nil
	bp.preview = nil
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
	elseif inputMode == "push" then
		clearHighlights()
		for _, t in ipairs(currentPrompt.pushTargets or {}) do createTileHighlight(t.tileX, t.tileY, Color3.fromRGB(255, 180, 40), 0.45) end
	end
	bp.state = "TargetSelection"; BattleHUD.Render(bp)
end

--------------------------------------------------
-- CLICK HANDLER
--------------------------------------------------


local function processTileClick(bx, by)
	
	-- Find occupant for tile info
	local occupantName = nil
	for uid, data in pairs(unitData) do
		if data.tileX == bx and data.tileY == by and data.isAlive ~= false then
			occupantName = data.name
			break
		end
	end

	-- Always update tile info
	local terrainId = GameConstants.GetTerrainId(bx, by)
	local elevation = getElevation(bx, by)
	local moveCost = GameConstants.GetTerrainCost(bx, by)
	bp.tile = {
		terrainName = terrainId,
		elevation = elevation,
		moveCost = moveCost,
		coords = string.format("(%d, %d)", bx, by),
		occupantName = occupantName,
	}
	BattleHUD.Render(bp)
	
	-- Inspect unit by clicking — works in ALL states
	for uid, data in pairs(unitData) do
		if data.tileX == bx and data.tileY == by and data.isAlive ~= false then
			bp.inspectedEntityId = data.id
			bp.target = data
			BattleHUD.Render(bp)
			-- Only auto-open full inspector during Idle (no active turn) — never during
			-- combat flow (ActionSelection, TargetSelection, Preview, SkillSelection)
			local hudState = BattleHUD.GetState()
			if hudState == "Idle" and not BattleHUD.IsViewMode() and _G.CTRBLXAI_OpenInspectorPanel then
				_G.CTRBLXAI_OpenInspectorPanel(data.id)
			end
			break
		end
	end
	
	-- View mode: tile + unit info updated above, skip combat flow
	if BattleHUD.IsViewMode() then return end

	if not isPlayerTurn or not inputMode then return end
	
	local state = bp.state
	
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
					local moveRt = tile.pathCost or 0
					bp.preview = {
						actionType = "Move",
						actorName = currentPrompt.unitName,
						fromTile = string.format("(%d,%d)", storedActorData.tileX or 0, storedActorData.tileY or 0),
						toTile = string.format("(%d,%d)", bx, by),
						actorApBefore = currentPrompt.currentAp, actorApAfter = (currentPrompt.currentAp or 1) - 1,
						actorRtAfter = moveRt + (currentPrompt.unitBaseRt or 400) + (currentPrompt.turnRtAccrued or 0),
						onConfirm = function() commitCommand({ actionType = "Move", tileX = bx, tileY = by, pathCost = tile.pathCost }) end,
						onBack = cancelToTargeting,
					}
					bp.state = "Preview"; BattleHUD.Render(bp)
					return
				end
			end
		elseif inputMode == "attack" then
			for _, t in ipairs(currentPrompt.attackTargets) do
				if t.tileX == bx and t.tileY == by then
					aimTarget = t; clearHighlights()
					createTileHighlight(bx, by, "selected")
					bp.target = unitData[t.id]
					local tgtData = unitData[t.id]
					bp.preview = {
						actionType = "Attack",
						actorName = currentPrompt.unitName,
						actorMpBefore = currentPrompt.currentMp, actorMpAfter = currentPrompt.currentMp, -- no MP cost
						actorApBefore = currentPrompt.currentAp, actorApAfter = (currentPrompt.currentAp or 1) - 1,
						actorRtAfter = (currentPrompt.attackRt or 80) + (currentPrompt.unitBaseRt or 400) + (currentPrompt.turnRtAccrued or 0),
						targetName = t.name,
						targetHpBefore = tgtData and tgtData.currentHp or 0,
						targetHpAfter = tgtData and math.max(0, (tgtData.currentHp or 0) - (t.predicted or 0)) or 0,
						estimatedDamage = t.predicted or 0,
						targetRtDelay = GameConstants.CalcRtDelayResistance(currentPrompt.weaponRtDelay or 0, tgtData and tgtData.stats and tgtData.stats.VIT or 10),
						statusEffect = "None",
						onConfirm = function() commitCommand({ actionType = "Attack", targetId = t.id }) end,
						onBack = cancelToTargeting,
					}
					bp.state = "Preview"; BattleHUD.Render(bp)
					return
				end
			end
		elseif inputMode == "skill" and selectedSkill then
			for _, t in ipairs(selectedSkill.targets) do
				if t.tileX == bx and t.tileY == by then
					aimTarget = t; clearHighlights()
					createTileHighlight(bx, by, "selected")
					bp.target = unitData[t.id]
					local statusEff = selectedSkill.appliesStatus or "None"
					local statusDur = 0
					if statusEff ~= "None" and GameConstants.STATUSES and GameConstants.STATUSES[statusEff] then
						statusDur = GameConstants.STATUSES[statusEff].duration or 0
					end
					local isHeal = (t.predType == "healing")
					local tgtData = unitData[t.id]
					local tgtHpBefore = tgtData and tgtData.currentHp or 0
					local tgtMaxHp = tgtData and tgtData.maxHp or tgtHpBefore
					local tgtHpAfter
					if isHeal then
						tgtHpAfter = math.min(tgtMaxHp, tgtHpBefore + (t.predicted or 0))
					else
						tgtHpAfter = math.max(0, tgtHpBefore - (t.predicted or 0))
					end
					local skillRtCost = selectedSkill.rtCost or 60
					local isChannel = selectedSkill.channelTime and selectedSkill.channelTime > 0
					bp.preview = {
						actionType = "Skill",
						skillName = selectedSkill.name,
						skillTags = bp.skill and bp.skill.tags or nil,
						actorName = currentPrompt.unitName,
						actorMpBefore = currentPrompt.currentMp,
						actorMpAfter = (currentPrompt.currentMp or 0) - (selectedSkill.mpCost or 0),
						actorApBefore = currentPrompt.currentAp,
						actorApAfter = (currentPrompt.currentAp or 1) - 1,
						actorRtAfter = skillRtCost + (currentPrompt.unitBaseRt or 400) + (currentPrompt.turnRtAccrued or 0),
						targetName = t.name,
						targetHpBefore = tgtHpBefore,
						targetHpAfter = tgtHpAfter,
						estimatedDamage = t.predicted or 0,
						isHealing = isHeal,
						targetRtDelay = (not isHeal) and GameConstants.CalcRtDelayResistance(currentPrompt.weaponRtDelay or 0, tgtData and tgtData.stats and tgtData.stats.VIT or 10) or 0,
						statusEffect = statusEff,
						statusDuration = statusDur,
						channelTime = isChannel and selectedSkill.channelTime or nil,
						channelResolveCt = isChannel and (currentBattleCt or 0) + (selectedSkill.channelTime or 0) or nil,
						onConfirm = function()
							commitCommand({ actionType = "Skill", skillId = selectedSkill.id, targetId = t.id })
						end,
						onBack = cancelToTargeting,
					}
					bp.state = "Preview"; BattleHUD.Render(bp)
					return
				end
			end

		elseif inputMode == "push" then
			for _, t in ipairs(currentPrompt.pushTargets or {}) do
				if t.tileX == bx and t.tileY == by then
					aimTarget = t; clearHighlights()
					createTileHighlight(bx, by, "selected")
					bp.target = unitData[t.id]
					bp.preview = {
						actionType = "Push",
						actorName = currentPrompt.unitName,
						actorApBefore = currentPrompt.currentAp, actorApAfter = (currentPrompt.currentAp or 1) - 1,
						actorRtAfter = (currentPrompt.pushRt or 40) + (currentPrompt.unitBaseRt or 400) + (currentPrompt.turnRtAccrued or 0),
						targetName = t.name,
						description = "Push " .. (t.name or "target") .. " away",
						onConfirm = function() commitCommand({ actionType = "Push", targetId = t.id }) end,
						onBack = cancelToTargeting,
					}
					bp.state = "Preview"; BattleHUD.Render(bp)
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
	local ray = cam:ScreenPointToRay(tapPos.X, tapPos.Y)
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
-- HOVER TOOLTIP (shows unit name/HP on mouse hover)
--------------------------------------------------

local lastHoveredUnitId = nil

game:GetService("RunService").RenderStepped:Connect(function()
	if not next(unitData) then
		if lastHoveredUnitId then
			lastHoveredUnitId = nil
			BattleHUD.HideTooltip()
		end
		return
	end

	-- Check what tile is under the mouse
	local tilePart = getTileUnderMouse()
	if not tilePart then
		if lastHoveredUnitId then
			lastHoveredUnitId = nil
			BattleHUD.HideTooltip()
		end
		return
	end

	local bx, by = tileToBattle(tilePart)
	if not bx then
		if lastHoveredUnitId then
			lastHoveredUnitId = nil
			BattleHUD.HideTooltip()
		end
		return
	end

	-- Find unit on this tile
	local hoveredUnit = nil
	for _, data in pairs(unitData) do
		if data.tileX == bx and data.tileY == by and data.isAlive ~= false then
			hoveredUnit = data
			break
		end
	end

	if hoveredUnit then
		-- Don't show tooltip for the unit we're already inspecting
		if hoveredUnit.id == bp.inspectedEntityId then
			if lastHoveredUnitId then
				lastHoveredUnitId = nil
				BattleHUD.HideTooltip()
			end
			return
		end
		if hoveredUnit.id ~= lastHoveredUnitId then
			lastHoveredUnitId = hoveredUnit.id
			local hpText = string.format("HP %d/%d", hoveredUnit.currentHp or 0, hoveredUnit.maxHp or 0)
			local mpText = string.format("MP %d/%d", hoveredUnit.currentMp or 0, hoveredUnit.maxMp or 0)
			local sideColor = hoveredUnit.side == "Player" and Theme.Colors.Success or Theme.Colors.Danger
			local tooltipLines = {
				{ text = hpText, color = Theme.Colors.TextPrimary },
				{ text = mpText, color = Theme.Colors.TextSecondary },
			}
			-- Add status effects
			if hoveredUnit.statuses and #hoveredUnit.statuses > 0 then
				local statusParts = {}
				for _, s in ipairs(hoveredUnit.statuses) do
					local name = s.id or s.name or "?"
					local turns = s.remainingTurns and ("(" .. s.remainingTurns .. ")") or ""
					table.insert(statusParts, name .. turns)
				end
				table.insert(tooltipLines, { text = table.concat(statusParts, " "), color = Theme.Colors.Warning })
			end
			BattleHUD.ShowTooltip({
				title = hoveredUnit.name or "Unit",
				portrait = string.sub(hoveredUnit.name or "?", 1, 2),
				portraitColor = sideColor,
				lines = tooltipLines,
				position = UDim2.new(0, mouse.X + 16, 0, mouse.Y - 10),
				anchorPoint = Vector2.new(0, 1),
				maxWidth = 160,
			})
		end
	else
		if lastHoveredUnitId then
			lastHoveredUnitId = nil
			BattleHUD.HideTooltip()
		end
	end
end)


--------------------------------------------------
-- DEV OPTIONS PANEL (temporary, remove when Slice 7 UI provides buttons)
-- Visible only during battle. Blocks input across its bounds.
--------------------------------------------------

local devCameraPanel = nil
local devSelectedTile = nil -- {x, y} for Kill Unit targeting

local function createDevCameraPanel()
	if not RunService:IsStudio() then return end
	if devCameraPanel then devCameraPanel:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = "DevOptions"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 95
	gui.Parent = player:WaitForChild("PlayerGui")
	devCameraPanel = gui

	local devExpanded = false

	local frame = Instance.new("Frame")
	frame.Name = "DevPanel"
	frame.Size = UDim2.fromOffset(130, 14)
	frame.Position = UDim2.new(0, 130, 0, 4)
	frame.AnchorPoint = Vector2.new(0, 0)
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Active = true
	frame.ClipsDescendants = true
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
	local title = Instance.new("TextButton")
	title.Size = UDim2.new(1, 0, 0, 14)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.SourceSansBold; title.TextSize = 9
	title.TextColor3 = Color3.fromRGB(200, 200, 50)
	title.Text = "▶ DEV"; title.LayoutOrder = 0
	title.AutoButtonColor = false; title.BorderSizePixel = 0
	title.Parent = frame
	title.MouseButton1Click:Connect(function()
		devExpanded = not devExpanded
		if devExpanded then
			frame.Size = UDim2.fromOffset(130, 260)
			title.Text = "▼ DEV OPTIONS"
		else
			frame.Size = UDim2.fromOffset(130, 14)
			title.Text = "▶ DEV"
		end
	end)

	local function makeBtn(text, order, callback, color)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, 22)
		btn.BackgroundColor3 = color or Color3.fromRGB(50, 50, 65)
		btn.BackgroundTransparency = 0.2
		btn.Font = Enum.Font.SourceSans; btn.TextSize = 11
		btn.TextColor3 = Color3.fromRGB(220, 220, 220)
		btn.Text = text; btn.LayoutOrder = order
		btn.BorderSizePixel = 0; btn.Parent = frame
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
		btn.MouseButton1Click:Connect(callback)
		return btn
	end

	-- Camera buttons
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
		local iid = bp.inspectedEntityId
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

	-- Separator
	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, 0, 0, 1)
	sep.BackgroundColor3 = Color3.fromRGB(200, 200, 50)
	sep.BackgroundTransparency = 0.5
	sep.BorderSizePixel = 0; sep.LayoutOrder = 4
	sep.Parent = frame

	-- Battle control buttons
	makeBtn("INSTANT WIN", 5, function()
		BattleEvents.DevCommand:FireServer({ action = "InstantWin" })
	end, Color3.fromRGB(30, 80, 30))

	makeBtn("INSTANT LOSE", 6, function()
		BattleEvents.DevCommand:FireServer({ action = "InstantLose" })
	end, Color3.fromRGB(80, 30, 30))

	makeBtn("KILL AT TILE", 7, function()
		-- Uses the last tile-clicked unit (stored by devLastInspectedId)
		local iid = devLastInspectedId
		local idata = iid and unitData[iid]
		if idata and idata.tileX and idata.tileY then
			BattleEvents.DevCommand:FireServer({
				action = "KillAtTile",
				tileX = idata.tileX,
				tileY = idata.tileY,
			})
		else
			warn("[Dev] No unit selected -- click a unit first, then press KILL AT TILE")
		end
	end, Color3.fromRGB(80, 50, 20))

	makeBtn("DELETE SAVE", 8, function()
		BattleEvents.DevCommand:FireServer({ action = "DeleteSave" })
	end, Color3.fromRGB(80, 20, 20))

	makeBtn("SAVE NOW", 9, function()
		BattleEvents.DevCommand:FireServer({ action = "SaveNow" })
	end, Color3.fromRGB(30, 60, 80))
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

	-- Collapse TemplateInspector panels during battle
	if type(_G.CTRBLXAI_SetInspectorCollapsed) == "function" then
		_G.CTRBLXAI_SetInspectorCollapsed(true)
	end

	createDevCameraPanel()

	BattleHUD.Cleanup()
	bp = { state = "Idle", actor = nil, target = nil, skill = nil, preview = nil, tile = nil, inspectedEntityId = nil }
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
	bp.inspectedEntityId = nil  -- new turn resets inspection
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
	-- Exit view mode so the action panel renders correctly.
	-- Without this, Render returns early and the action buttons never appear.
	if BattleHUD.IsViewMode() then
		BattleHUD.ToggleViewMode()
	end
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
	local logText = data.skillName
		and (actorName.." used "..data.skillName.." → "..targetName..". -"..data.damage.." HP")
		or (actorName.." attacks "..targetName..". -"..data.damage.." HP")
	if data.statusApplied and data.statusApplied ~= "" then
		logText = logText .. " +" .. data.statusApplied
	end
	if data.rtDelay and data.rtDelay > 0 then
		logText = logText .. " RT+" .. data.rtDelay
	end
	BattleHUD.AddLogEntry(logText)

	-- Show resolution result in preview panel
	bp.preview = {
		actionType = "Result",
		actorName = actorName,
		targetName = targetName,
		skillName = data.skillName,
		damage = data.damage,
		statusApplied = data.statusApplied,
		rtDelay = data.rtDelay,
	}
	BattleHUD.Render(bp)
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

	-- Show resolution result
	bp.preview = {
		actionType = "Result",
		actorName = actorName,
		targetName = targetName,
		skillName = data.skillName,
		healing = data.amount,
	}
	BattleHUD.Render(bp)
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

BattleEvents.UnitPushed.OnClientEvent:Connect(function(data)
	local targetToken = unitTokens[data.targetId]
	local pusherToken = unitTokens[data.pusherId]

	-- Update local unit data position
	if unitData[data.targetId] then
		unitData[data.targetId].tileX = data.finalTileX
		unitData[data.targetId].tileY = data.finalTileY
	end

	-- Animate target moving to new position
	if targetToken and data.pushed then
		TweenService:Create(targetToken.part,
			TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(tileToWorld(data.finalTileX, data.finalTileY)) * CFrame.Angles(0, 0, math.rad(90)) }
		):Play()
	end

	-- Show push text + damage floats
	if pusherToken then
		showFloatingText(pusherToken.part.Position, "PUSH", Color3.fromRGB(255, 180, 40), 1.1)
	end
	local totalDmg = (data.wallDamage or 0) + (data.fallDamage or 0)
	if totalDmg > 0 and targetToken then
		showFloatingText(targetToken.part.Position, "-" .. totalDmg, Color3.fromRGB(255, 100, 40))
		updateHpBar(data.targetId, data.targetHp, data.targetMaxHp)
	end
end)

BattleEvents.BattleEnded.OnClientEvent:Connect(function(data)
	isPlayerTurn = false; inputMode = nil; clearHighlights()
	hideSelectionRing()
	bp.state = "BattleEnded"; BattleHUD.Render(bp)

	-- Show result
	local gui = Instance.new("ScreenGui"); gui.Name = "BattleResult"; gui.ResetOnSpawn = false
	gui.DisplayOrder = 90; gui.Parent = player:WaitForChild("PlayerGui")
	local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.fromOffset(300,60)
	lbl.AnchorPoint = Vector2.new(0.5,0.5); lbl.Position = UDim2.fromScale(0.5,0.4)
	lbl.BackgroundColor3 = Theme.Colors.Background; lbl.BackgroundTransparency = 0.2
	lbl.Font = Theme.Font.Display; lbl.TextSize = Theme.Text.Title() + Theme.Scaled(12); lbl.BorderSizePixel = 0
	lbl.TextColor3 = data.winner == "Player" and Theme.Colors.TextGold or Theme.Colors.Danger
	lbl.Text = data.winner == "Player" and "VICTORY" or "DEFEAT"; lbl.Parent = gui
	Instance.new("UICorner", lbl).CornerRadius = Theme.CornerRadius.lg
	task.delay(5, function()
		if gui.Parent then gui:Destroy() end
		BattleHUD.Cleanup()
		bp = { state = "Idle", actor = nil, target = nil, skill = nil, preview = nil, tile = nil, inspectedEntityId = nil }
		destroyDevCameraPanel()
		CameraController.ExitBattle()
		-- Expand TemplateInspector panels after battle
		if type(_G.CTRBLXAI_SetInspectorCollapsed) == "function" then
			_G.CTRBLXAI_SetInspectorCollapsed(false)
		end
	end)
end)

_G.CTRBLXAI_SelectTileAt = function() end

_G.CTRBLXAI_GetElevation = function(tileX, tileY)
	if elevationMap and elevationMap[tileY] then
		return elevationMap[tileY][tileX] or 1
	end
	return 1
end


_G.CTRBLXAI_TimelineClickTile = function(tileX, tileY)
	if tileX and tileY then
		processTileClick(tileX, tileY)

		-- Highlight the tile with "selected" style
		clearHighlights()
		createTileHighlight(tileX, tileY, "selected")

		-- Show quick-look tooltip (same as hover)
		local hoveredUnit = nil
		for _, data in pairs(unitData) do
			if data.tileX == tileX and data.tileY == tileY and data.isAlive ~= false then
				hoveredUnit = data
				break
			end
		end
		if hoveredUnit then
			local hpText = string.format("HP %d/%d", hoveredUnit.currentHp or 0, hoveredUnit.maxHp or 0)
			local mpText = string.format("MP %d/%d", hoveredUnit.currentMp or 0, hoveredUnit.maxMp or 0)
			local tooltipLines = {
				{ text = hpText, color = Theme.Colors.TextPrimary },
				{ text = mpText, color = Theme.Colors.TextSecondary },
			}
			if hoveredUnit.statuses and #hoveredUnit.statuses > 0 then
				local statusParts = {}
				for _, s in ipairs(hoveredUnit.statuses) do
					table.insert(statusParts, (s.id or "?") .. (s.remainingTurns and ("(" .. s.remainingTurns .. ")") or ""))
				end
				table.insert(tooltipLines, { text = table.concat(statusParts, " "), color = Theme.Colors.Warning })
			end
			local worldPos = tileToWorld(tileX, tileY)
			local cam = workspace.CurrentCamera
			local screenPos = cam and cam:WorldToScreenPoint(worldPos) or Vector3.new(400, 200, 0)
			BattleHUD.ShowTooltip({
				title = hoveredUnit.name or "Unit",
				portrait = string.sub(hoveredUnit.name or "?", 1, 2),
				portraitColor = Theme.GetSideColor(hoveredUnit.side),
				lines = tooltipLines,
				position = UDim2.new(0, screenPos.X, 0, screenPos.Y - 20),
				anchorPoint = Vector2.new(0.5, 1),
				maxWidth = 160,
			})
		end
	end
end


print("[CTRBLXAI] BattleVisualClient v3 loaded.")


--------------------------------------------------
-- LOADOUT HUB (Slice 4D — minimal functional placeholder)
-- Slice 7 owns final visual presentation.
--------------------------------------------------

local loadoutHubGui = nil

local function destroyLoadoutHub()
	if loadoutHubGui then loadoutHubGui:Destroy(); loadoutHubGui = nil end
end

local function createLoadoutHub(phase)
	destroyLoadoutHub()

	local gui = Instance.new("ScreenGui")
	gui.Name = "LoadoutHub"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 90
	gui.Parent = player:WaitForChild("PlayerGui")
	loadoutHubGui = gui

	local frame = Instance.new("Frame")
	frame.Name = "HubFrame"
	frame.Size = UDim2.new(0.92, 0, 0.88, 0) -- responsive: 92% width, 88% height (fits mobile)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Theme.Colors.Background
	frame.BackgroundTransparency = 0.02
	frame.BorderSizePixel = 0
	frame.Active = true
	frame.Parent = gui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
	local hubConstraint = Instance.new("UISizeConstraint", frame)
	hubConstraint.MaxSize = Vector2.new(560, 480)
	local stroke = Instance.new("UIStroke", frame)
	stroke.Color = Theme.Colors.Border; stroke.Thickness = 1

	-- Title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 28)
	title.Position = UDim2.new(0, 0, 0, 4)
	title.BackgroundTransparency = 1
	title.Font = Theme.Font.PrimaryBold; title.TextSize = Theme.Text.Title()
	title.TextColor3 = Theme.Colors.TextGold
	title.Text = phase == "PreBattle" and "⚔ LOADOUT HUB" or "⚔ LOADOUT HUB (Post-Battle)"
	title.Parent = frame

	-- Output area (scrollable text)
	local outputFrame = Instance.new("ScrollingFrame")
	outputFrame.Name = "Output"
	outputFrame.Size = UDim2.new(1, -16, 1, -140)
	outputFrame.Position = UDim2.new(0, 8, 0, 34)
	outputFrame.BackgroundColor3 = Theme.Colors.Surface
	outputFrame.BackgroundTransparency = 0.1
	outputFrame.BorderSizePixel = 0
	outputFrame.ScrollBarThickness = 6
	outputFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	outputFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	outputFrame.Parent = frame
	Instance.new("UICorner", outputFrame).CornerRadius = UDim.new(0, 4)

	local outputLayout = Instance.new("UIListLayout", outputFrame)
	outputLayout.SortOrder = Enum.SortOrder.LayoutOrder; outputLayout.Padding = UDim.new(0, 2)

	local outputText = Instance.new("TextLabel")
	outputText.Name = "Text"
	outputText.Size = UDim2.new(1, -8, 0, 0)
	outputText.Position = UDim2.new(0, 4, 0, 2)
	outputText.AutomaticSize = Enum.AutomaticSize.Y
	outputText.BackgroundTransparency = 1
	outputText.Font = Enum.Font.Code; outputText.TextSize = 11
	outputText.TextColor3 = Color3.fromRGB(190, 190, 190)
	outputText.TextXAlignment = Enum.TextXAlignment.Left
	outputText.TextYAlignment = Enum.TextYAlignment.Top
	outputText.TextWrapped = true
	outputText.RichText = true
	outputText.Text = "Loadout Hub ready. Use buttons below."
	outputText.LayoutOrder = 0
	outputText.Parent = outputFrame

	local function setOutput(txt)
		outputText.Text = txt
		-- Remove any clickable line buttons from previous view
		for _, child in ipairs(outputFrame:GetChildren()) do
			if child:IsA("TextButton") then child:Destroy() end
		end
	end

	-- Render clickable lines in the output area
	-- Each line is a TextButton; clicking it calls onClickFn(lineData)
	local function setClickableLines(header, lineEntries)
		-- lineEntries = { {text, color, onClick} }
		outputText.Text = header
		for _, child in ipairs(outputFrame:GetChildren()) do
			if child:IsA("TextButton") then child:Destroy() end
		end
		for idx, entry in ipairs(lineEntries) do
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(1, -8, 0, 0)
			btn.AutomaticSize = Enum.AutomaticSize.Y
			btn.Position = UDim2.new(0, 4, 0, 0)
			btn.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
			btn.BackgroundTransparency = 0.5
			btn.BorderSizePixel = 0
			btn.Font = Enum.Font.Code; btn.TextSize = 11
			btn.TextColor3 = entry.color or Color3.fromRGB(190, 190, 190)
			btn.TextXAlignment = Enum.TextXAlignment.Left
			btn.TextWrapped = true
			btn.RichText = true
			btn.Text = entry.text
			btn.LayoutOrder = idx + 1
			btn.Parent = outputFrame
			Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 2)
			if entry.onClick then
				btn.MouseButton1Click:Connect(entry.onClick)
			end
		end
	end


	-- Input fields for equip/unequip
	local inputRow = Instance.new("Frame")
	inputRow.Size = UDim2.new(1, -16, 0, 24)
	inputRow.Position = UDim2.new(0, 8, 1, -130)
	inputRow.BackgroundTransparency = 1
	inputRow.Parent = frame

	local unitInput = Instance.new("TextBox")
	unitInput.Size = UDim2.fromOffset(130, 22)
	unitInput.Position = UDim2.new(0, 0, 0, 0)
	unitInput.PlaceholderText = "unit_hero"
	unitInput.Text = ""
	unitInput.Font = Enum.Font.Code; unitInput.TextSize = 10
	unitInput.TextColor3 = Color3.fromRGB(220, 220, 220)
	unitInput.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
	unitInput.BorderSizePixel = 0
	unitInput.ClearTextOnFocus = false
	unitInput.Parent = inputRow
	Instance.new("UICorner", unitInput).CornerRadius = UDim.new(0, 3)

	local itemInput = Instance.new("TextBox")
	itemInput.Size = UDim2.fromOffset(160, 22)
	itemInput.Position = UDim2.new(0, 134, 0, 0)
	itemInput.PlaceholderText = "item_1001_1"
	itemInput.Text = ""
	itemInput.Font = Enum.Font.Code; itemInput.TextSize = 10
	itemInput.TextColor3 = Color3.fromRGB(220, 220, 220)
	itemInput.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
	itemInput.BorderSizePixel = 0
	itemInput.ClearTextOnFocus = false
	itemInput.Parent = inputRow
	Instance.new("UICorner", itemInput).CornerRadius = UDim.new(0, 3)

	-- Button row
	local btnRow = Instance.new("Frame")
	btnRow.Size = UDim2.new(1, -16, 0, 66)
	btnRow.Position = UDim2.new(0, 8, 1, -100)
	btnRow.BackgroundTransparency = 1
	btnRow.Parent = frame

	local btnLayout = Instance.new("UIGridLayout", btnRow)
	btnLayout.CellSize = UDim2.fromOffset(115, 28)
	btnLayout.CellPadding = UDim2.fromOffset(4, 4)
	btnLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local function hubBtn(text, order, callback, color)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 100, 0, 28)
		btn.BackgroundColor3 = color or Theme.Colors.Surface
		btn.BackgroundTransparency = 0.15
		btn.Font = Theme.Font.PrimaryBold; btn.TextSize = Theme.Text.Body()
		btn.TextColor3 = Theme.Colors.TextPrimary
		btn.Text = text; btn.LayoutOrder = order
		btn.BorderSizePixel = 0; btn.Parent = btnRow
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
		btn.MouseButton1Click:Connect(callback)
		return btn
	end

	hubBtn("VIEW ROSTER", 1, function()
		setOutput("Loading roster...")
		local roster = BattleEvents.GetRosterData:InvokeServer()
		if not roster then setOutput("Failed to get roster."); return end
		local entries = {}
		for uid, data in pairs(roster) do
			local hpColor = data.isKO and "rgb(150,150,150)" or (data.currentHp / data.maxHp > 0.5 and "rgb(100,200,100)" or "rgb(200,100,100)")
			local offTag = (data.equippedOffHandName and data.equippedOffHandName ~= "none") and (" | Off:" .. data.equippedOffHandName) or ""
			local lineText = string.format(
				'<font color="%s">%s</font> L%d | HP:%d/%d MP:%d/%d%s | Wpn:%s%s | <font color="rgb(100,160,220)">%s</font>',
				hpColor, data.name, data.level,
				data.currentHp, data.maxHp, data.currentMp, data.maxMp,
				data.isKO and " [KO]" or "",
				data.equippedWeaponName, offTag,
				uid
			)
			local capturedUid = uid
			table.insert(entries, {
				text = lineText,
				onClick = function() unitInput.Text = capturedUid end,
			})
		end
		setClickableLines("<b>ROSTER</b> (click a unit to fill Unit ID)\n", entries)
	end)

	hubBtn("VIEW INVENTORY", 2, function()
		setOutput("Loading inventory...")
		local items = BattleEvents.GetInventoryData:InvokeServer()
		if not items then setOutput("Failed to get inventory."); return end
		local entries = {}
		for _, item in ipairs(items) do
			local rarityColor = ({
				Broken = "rgb(120,120,120)", Common = "rgb(200,200,200)",
				Uncommon = "rgb(100,200,100)", Rare = "rgb(100,150,255)",
				Epic = "rgb(180,100,255)", Legendary = "rgb(255,180,50)",
			})[item.rarity] or "rgb(200,200,200)"
			local slotTag = item.equippedSlot and (" [" .. item.equippedSlot .. "]") or ""
			local eqTag = item.equippedBy and string.format(' <font color="rgb(255,200,80)">← %s%s</font>', item.equippedBy, slotTag) or ""
			local lineText = string.format(
				'<font color="%s">[%s]</font> %s L%d | Dmg:%d WT:%d Def:%d | +%dattr +%dpass | ID:%s%s',
				rarityColor, item.rarity, item.name, item.itemLevel,
				item.damage, item.wt, item.defense,
				item.bonusCount, item.passiveCount, item.instanceId,
				eqTag
			)
			local capturedId = item.instanceId
			table.insert(entries, {
				text = lineText,
				color = Color3.fromRGB(190, 190, 190),
				onClick = function() itemInput.Text = capturedId end,
			})
		end
		setClickableLines(string.format("<b>INVENTORY (%d items)</b> (click an item to fill Item ID)\n", #items), entries)
	end)

	hubBtn("EQUIP", 3, function()
		setOutput("EQUIP: Enter unitId and instanceId in the boxes below, then press CONFIRM EQUIP.\n\nUnit IDs: unit_hero, unit_mage, unit_ranger\nItem IDs: see VIEW INVENTORY")
	end)

	hubBtn("UNEQUIP", 4, function()
		setOutput("UNEQUIP: Enter unitId below, then press CONFIRM UNEQUIP.\nSlot defaults to MainHand.\n\nUnit IDs: unit_hero, unit_mage, unit_ranger")
	end)

	if phase == "PreBattle" then
		hubBtn("START BATTLE", 5, function()
			destroyLoadoutHub()
			BattleEvents.StartBattle:FireServer()
		end, Color3.fromRGB(40, 100, 40))
	else
		-- PostBattle: DONE button closes hub and signals server to continue
		hubBtn("DONE", 5, function()
			destroyLoadoutHub()
			BattleEvents.StartBattle:FireServer()
		end, Color3.fromRGB(40, 120, 60))
	end

	-- Dev tools in Loadout Hub
	hubBtn("SAVE NOW", 6, function()
		BattleEvents.DevCommand:FireServer({ action = "SaveNow" })
		setOutput("Save requested...")
	end, Color3.fromRGB(30, 60, 80))

	hubBtn("DELETE SAVE", 7, function()
		BattleEvents.DevCommand:FireServer({ action = "DeleteSave" })
		setOutput("Delete save requested...")
	end, Color3.fromRGB(80, 20, 20))


	local confirmEquip = Instance.new("TextButton")
	confirmEquip.Size = UDim2.fromOffset(85, 22)
	confirmEquip.Position = UDim2.new(0, 298, 0, 0)
	confirmEquip.Text = "CONFIRM EQUIP"
	confirmEquip.Font = Theme.Font.PrimaryBold; confirmEquip.TextSize = Theme.Text.Small()
	confirmEquip.TextColor3 = Color3.fromRGB(220, 220, 220)
	confirmEquip.BackgroundColor3 = Color3.fromRGB(40, 80, 40)
	confirmEquip.BorderSizePixel = 0
	confirmEquip.Parent = inputRow
	Instance.new("UICorner", confirmEquip).CornerRadius = UDim.new(0, 3)
	confirmEquip.MouseButton1Click:Connect(function()
		local uid = unitInput.Text
		local iid = itemInput.Text
		if uid == "" or iid == "" then setOutput("Enter both unit ID and item ID."); return end
		setOutput("Equipping...")
		local result = BattleEvents.RequestEquip:InvokeServer(uid, iid)
		if result and result.ok then
			setOutput(string.format("Equipped %s on %s (%s)", result.name or iid, uid, result.slot or "?"))
		else
			setOutput("Equip failed: " .. (result and result.reason or "unknown"))
		end
	end)

	local confirmUnequip = Instance.new("TextButton")
	confirmUnequip.Size = UDim2.fromOffset(95, 22)
	confirmUnequip.Position = UDim2.new(0, 387, 0, 0)
	confirmUnequip.Text = "CONFIRM UNEQUIP"
	confirmUnequip.Font = Theme.Font.PrimaryBold; confirmUnequip.TextSize = Theme.Text.Small()
	confirmUnequip.TextColor3 = Color3.fromRGB(220, 220, 220)
	confirmUnequip.BackgroundColor3 = Color3.fromRGB(80, 40, 40)
	confirmUnequip.BorderSizePixel = 0
	confirmUnequip.Parent = inputRow
	Instance.new("UICorner", confirmUnequip).CornerRadius = UDim.new(0, 3)
	confirmUnequip.MouseButton1Click:Connect(function()
		local uid = unitInput.Text
		if uid == "" then setOutput("Enter unit ID."); return end
		setOutput("Unequipping...")
		local result = BattleEvents.RequestUnequip:InvokeServer(uid, "MainHand")
		if result and result.ok then
			setOutput(string.format("Unequipped MainHand on %s", uid))
		else
			setOutput("Unequip failed: " .. (result and result.reason or "unknown"))
		end
	end)
end

--------------------------------------------------
-- REWARD SCREEN (Slice 4D — minimal functional placeholder)
--------------------------------------------------

local rewardGui = nil

BattleEvents.RewardScreen.OnClientEvent:Connect(function(data)
	if rewardGui then rewardGui:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = "RewardScreen"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 92
	gui.Parent = player:WaitForChild("PlayerGui")
	rewardGui = gui

	-- Dim backdrop
	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.Overlay
	backdrop.BackgroundTransparency = 0.4
	backdrop.BorderSizePixel = 0
	backdrop.Parent = gui

	-- Main panel using Theme
	local frame = Theme.MakePanel("VictoryPanel",
		UDim2.new(0.70, 0, 0.85, 0),
		UDim2.new(0.5, 0, 0.5, 0),
		Vector2.new(0.5, 0.5),
		gui)
	frame.ClipsDescendants = true

	local framePad = Instance.new("UIPadding", frame)
	framePad.PaddingTop = UDim.new(0, 10)
	framePad.PaddingLeft = UDim.new(0, 12)
	framePad.PaddingRight = UDim.new(0, 12)
	framePad.PaddingBottom = UDim.new(0, 10)

	-- VICTORY! title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 24)
	title.BackgroundTransparency = 1
	title.Font = Theme.Font.PrimaryBold
	title.TextSize = Theme.Text.Title()
	title.TextColor3 = Theme.Colors.TextGold
	title.Text = "VICTORY!"
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.Parent = frame

	-- Recovery summary
	local recY = 26
	if data.recovery and #data.recovery > 0 then
		local recoveryText = ""
		for _, r in ipairs(data.recovery) do
			local hpGain = (r.hpGain and r.hpGain > 0) and ("HP+" .. r.hpGain) or ""
			local mpGain = (r.mpGain and r.mpGain > 0) and ("MP+" .. r.mpGain) or ""
			local gains = hpGain .. (hpGain ~= "" and mpGain ~= "" and " " or "") .. mpGain
			if gains ~= "" then
				recoveryText = recoveryText .. (r.name or "?") .. ": " .. gains .. "  "
			end
		end
		if recoveryText ~= "" then
			local recLabel = Instance.new("TextLabel")
			recLabel.Size = UDim2.new(1, 0, 0, 14)
			recLabel.Position = UDim2.new(0, 0, 0, recY)
			recLabel.BackgroundTransparency = 1
			recLabel.Font = Theme.Font.Mono
			recLabel.TextSize = Theme.Text.Tiny()
			recLabel.TextColor3 = Theme.Colors.Success
			recLabel.TextXAlignment = Enum.TextXAlignment.Left
			recLabel.Text = recoveryText
			recLabel.Parent = frame
			recY = recY + 16
		end
	end

	-- Loot header
	local lootLabel = Instance.new("TextLabel")
	lootLabel.Size = UDim2.new(1, 0, 0, 14)
	lootLabel.Position = UDim2.new(0, 0, 0, recY)
	lootLabel.BackgroundTransparency = 1
	lootLabel.Font = Theme.Font.PrimaryBold
	lootLabel.TextSize = Theme.Text.Small()
	lootLabel.TextColor3 = Theme.Colors.TextSecondary
	lootLabel.TextXAlignment = Enum.TextXAlignment.Left
	lootLabel.Text = "LOOT"
	lootLabel.Parent = frame

	-- Loot grid
	local rewards = data.rewards or {}
	local gridY = recY + 18

	local lootGrid = Instance.new("ScrollingFrame")
	lootGrid.Size = UDim2.new(1, 0, 1, -(gridY + 40))
	lootGrid.Position = UDim2.new(0, 0, 0, gridY)
	lootGrid.BackgroundTransparency = 1
	lootGrid.BorderSizePixel = 0
	lootGrid.ScrollBarThickness = 3
	lootGrid.ScrollBarImageColor3 = Theme.Colors.TextSecondary
	lootGrid.CanvasSize = UDim2.new(0, 0, 0, 0)
	lootGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	lootGrid.Parent = frame

	local grid = Instance.new("UIGridLayout", lootGrid)
	grid.CellSize = UDim2.new(0, 72, 0, 82)
	grid.CellPadding = UDim2.new(0, 4, 0, 3)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirection = Enum.FillDirection.Horizontal

	-- Hand class -> icon mapping
	local HAND_ICONS = {
		["1H"] = "\xe2\x9a\x94", ["2H"] = "\xe2\x9a\x94",
		["Off-Hand"] = "\xf0\x9f\x9b\xa1",
	}

	-- Detail overlay state
	local detailFrame = nil

	local function closeRewardDetail()
		if detailFrame then detailFrame:Destroy(); detailFrame = nil end
	end

	for idx, item in ipairs(rewards) do
		local rc = Theme.GetRarityColor(item.rarity)

		local card = Instance.new("TextButton")
		card.Size = UDim2.new(1, 0, 1, 0)
		card.BackgroundColor3 = rc
		card.BackgroundTransparency = 0.75
		card.BorderSizePixel = 0
		card.Text = ""
		card.AutoButtonColor = true
		card.LayoutOrder = idx
		card.Parent = lootGrid
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 4)
		local cardStroke = Instance.new("UIStroke", card)
		cardStroke.Color = rc
		cardStroke.Thickness = 1.5

		-- Level badge (top-left)
		local lvl = Instance.new("TextLabel")
		lvl.Size = UDim2.new(0, 36, 0, 12)
		lvl.Position = UDim2.new(0, 3, 0, 2)
		lvl.BackgroundTransparency = 1
		lvl.Font = Theme.Font.Mono
		lvl.TextSize = Theme.Text.Tiny()
		lvl.TextColor3 = Theme.Colors.TextSecondary
		lvl.TextXAlignment = Enum.TextXAlignment.Left
		lvl.Text = "Lv" .. (item.itemLevel or 1)
		lvl.Parent = card

		-- Icon (center)
		local icon = Instance.new("TextLabel")
		icon.Size = UDim2.new(1, 0, 0, 28)
		icon.Position = UDim2.new(0, 0, 0.15, 0)
		icon.BackgroundTransparency = 1
		icon.Font = Theme.Font.Primary
		icon.TextSize = 24
		icon.TextColor3 = Theme.Colors.TextPrimary
		icon.TextXAlignment = Enum.TextXAlignment.Center
		icon.Text = HAND_ICONS[item.handClass] or "\xe2\x9a\x94"
		icon.Parent = card

		-- Name strip (bottom)
		local nameBg = Instance.new("Frame")
		nameBg.Size = UDim2.new(1, 0, 0, 14)
		nameBg.Position = UDim2.new(0, 0, 1, -14)
		nameBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		nameBg.BackgroundTransparency = 0.4
		nameBg.BorderSizePixel = 0
		nameBg.Parent = card
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -4, 1, 0)
		nameLabel.Position = UDim2.new(0, 2, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Theme.Font.Primary
		nameLabel.TextSize = Theme.Text.Small()
		nameLabel.TextColor3 = Theme.Colors.TextPrimary
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Text = item.name or "?"
		nameLabel.Parent = nameBg

		-- Click -> detail view
		card.MouseButton1Click:Connect(function()
			closeRewardDetail()

			-- Build detail panel (left side, like loadout detail)
			detailFrame = Theme.MakePanel("LootDetail",
				UDim2.new(0.50, 0, 0.80, 0),
				UDim2.new(0, 6, 0.5, 0),
				Vector2.new(0, 0.5),
				gui)
			detailFrame.ClipsDescendants = true

			local dp = Instance.new("UIPadding", detailFrame)
			dp.PaddingTop = UDim.new(0, 10)
			dp.PaddingLeft = UDim.new(0, 12)
			dp.PaddingRight = UDim.new(0, 12)
			dp.PaddingBottom = UDim.new(0, 10)

			-- Header: icon + name + subtitle
			local dIcon = Instance.new("Frame")
			dIcon.Size = UDim2.new(0, 56, 0, 56)
			dIcon.BackgroundColor3 = rc
			dIcon.BackgroundTransparency = 0.75
			dIcon.BorderSizePixel = 0
			dIcon.Parent = detailFrame
			Instance.new("UICorner", dIcon).CornerRadius = UDim.new(0, 6)
			Instance.new("UIStroke", dIcon).Color = rc
			local dIconText = Instance.new("TextLabel")
			dIconText.Size = UDim2.fromScale(1, 1)
			dIconText.BackgroundTransparency = 1
			dIconText.Font = Theme.Font.Primary
			dIconText.TextSize = 28
			dIconText.TextColor3 = Theme.Colors.TextPrimary
			dIconText.Text = HAND_ICONS[item.handClass] or "\xe2\x9a\x94"
			dIconText.Parent = dIcon

			-- Name
			local dName = Instance.new("TextLabel")
			dName.Size = UDim2.new(1, -64, 0, 18)
			dName.Position = UDim2.new(0, 64, 0, 0)
			dName.BackgroundTransparency = 1
			dName.Font = Theme.Font.PrimaryBold
			dName.TextSize = Theme.Text.Heading()
			dName.TextColor3 = Theme.Colors.TextPrimary
			dName.TextXAlignment = Enum.TextXAlignment.Left
			dName.Text = item.name or "?"
			dName.Parent = detailFrame

			-- Subtitle
			local dSub = Instance.new("TextLabel")
			dSub.Size = UDim2.new(1, -64, 0, 14)
			dSub.Position = UDim2.new(0, 64, 0, 18)
			dSub.BackgroundTransparency = 1
			dSub.Font = Theme.Font.Primary
			dSub.TextSize = Theme.Text.Small()
			dSub.TextColor3 = rc
			dSub.TextXAlignment = Enum.TextXAlignment.Left
			dSub.Text = "Lv." .. (item.itemLevel or 1) .. "  ·  " .. (item.rarity or "Common") .. "  ·  " .. (item.handClass or "")
			dSub.Parent = detailFrame

			-- Tags
			local tagY = 34
			local tagTexts = {}
			if item.handClass then table.insert(tagTexts, item.handClass) end
			if item.category then table.insert(tagTexts, item.category) end
			if #tagTexts > 0 then
				local tagRow = Instance.new("Frame")
				tagRow.Size = UDim2.new(1, -64, 0, 14)
				tagRow.Position = UDim2.new(0, 64, 0, tagY)
				tagRow.BackgroundTransparency = 1
				tagRow.Parent = detailFrame
				local tagLayout = Instance.new("UIListLayout", tagRow)
				tagLayout.FillDirection = Enum.FillDirection.Horizontal
				tagLayout.Padding = UDim.new(0, 3)
				for ti, tag in ipairs(tagTexts) do
					local chip = Instance.new("Frame")
					chip.Size = UDim2.new(0, #tag * 5 + 10, 0, 14)
					chip.BackgroundColor3 = Theme.Colors.Surface
					chip.BackgroundTransparency = 0.3
					chip.BorderSizePixel = 0
					chip.LayoutOrder = ti
					chip.Parent = tagRow
					Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 7)
					local tagLabel = Instance.new("TextLabel")
					tagLabel.Size = UDim2.fromScale(1, 1)
					tagLabel.BackgroundTransparency = 1
					tagLabel.Font = Theme.Font.Primary
					tagLabel.TextSize = Theme.Text.Badge()
					tagLabel.TextColor3 = Theme.Colors.TextSecondary
					tagLabel.TextXAlignment = Enum.TextXAlignment.Center
					tagLabel.Text = tag
					tagLabel.Parent = chip
				end
			end

			-- Divider
			local divY = 56
			local divider = Instance.new("Frame")
			divider.Size = UDim2.new(1, 0, 0, 1)
			divider.Position = UDim2.new(0, 0, 0, divY)
			divider.BackgroundColor3 = Theme.Colors.Border
			divider.BorderSizePixel = 0
			divider.Parent = detailFrame

			-- Base stats
			local statY = divY + 6
			local statDefs = {
				{ label = "Attack", value = item.damage },
				{ label = "Defense", value = item.defense },
				{ label = "WT", value = item.wt },
				{ label = "Bonuses", value = item.bonusCount .. " attributes" },
				{ label = "Passives", value = item.passiveCount .. " bonus" },
			}
			for _, s in ipairs(statDefs) do
				local row = Instance.new("Frame")
				row.Size = UDim2.new(0.5, 0, 0, 16)
				row.Position = UDim2.new(0, 0, 0, statY)
				row.BackgroundTransparency = 1
				row.Parent = detailFrame
				local sLabel = Instance.new("TextLabel")
				sLabel.Size = UDim2.new(0.55, 0, 1, 0)
				sLabel.BackgroundTransparency = 1
				sLabel.Font = Theme.Font.Primary
				sLabel.TextSize = Theme.Text.Body()
				sLabel.TextColor3 = Theme.Colors.TextSecondary
				sLabel.TextXAlignment = Enum.TextXAlignment.Left
				sLabel.Text = s.label
				sLabel.Parent = row
				local sVal = Instance.new("TextLabel")
				sVal.Size = UDim2.new(0.45, 0, 1, 0)
				sVal.Position = UDim2.new(0.55, 0, 0, 0)
				sVal.BackgroundTransparency = 1
				sVal.Font = Theme.Font.PrimaryBold
				sVal.TextSize = Theme.Text.Body()
				sVal.TextColor3 = Theme.Colors.TextPrimary
				sVal.TextXAlignment = Enum.TextXAlignment.Right
				sVal.Text = tostring(s.value)
				sVal.Parent = row
				statY = statY + 18
			end

			-- Back button (inside detail panel, lower-left)
			local backBtn = Instance.new("TextButton")
			backBtn.Size = UDim2.new(0, 70, 0, 24)
			backBtn.Position = UDim2.new(0, 0, 1, -28)
			backBtn.BackgroundColor3 = Theme.Colors.Surface
			backBtn.BackgroundTransparency = 0.2
			backBtn.Font = Theme.Font.PrimaryBold
			backBtn.TextSize = Theme.Text.Small()
			backBtn.TextColor3 = Theme.Colors.TextPrimary
			backBtn.Text = "BACK"
			backBtn.BorderSizePixel = 0
			backBtn.Parent = detailFrame
			Instance.new("UICorner", backBtn).CornerRadius = UDim.new(0, 4)
			backBtn.MouseButton1Click:Connect(closeRewardDetail)
		end)
	end

	-- CONTINUE button (bottom-right of screen, outside panel, like battle Execute)
	local continueBtn = Instance.new("TextButton")
	continueBtn.Size = UDim2.new(0, 100, 0, 32)
	continueBtn.Position = UDim2.new(1, -8, 1, -8)
	continueBtn.AnchorPoint = Vector2.new(1, 1)
	continueBtn.BackgroundColor3 = Theme.Colors.Success
	continueBtn.BackgroundTransparency = 0.15
	continueBtn.Font = Theme.Font.PrimaryBold
	continueBtn.TextSize = Theme.Text.Body()
	continueBtn.TextColor3 = Theme.Colors.TextPrimary
	continueBtn.Text = "CONTINUE"
	continueBtn.BorderSizePixel = 0
	continueBtn.Parent = gui
	Instance.new("UICorner", continueBtn).CornerRadius = UDim.new(0, 4)
	continueBtn.MouseButton1Click:Connect(function()
		if rewardGui then rewardGui:Destroy(); rewardGui = nil end
		BattleEvents.RewardContinue:FireServer()
	end)
end)

--------------------------------------------------
-- LOADOUT HUB EVENT HANDLER
--------------------------------------------------

BattleEvents.LoadoutHubOpen.OnClientEvent:Connect(function(data)
	local phase = data and data.phase or "PostBattle"
	-- Open new Loadout Screen (Slice 7) instead of old hub
	if _G.CTRBLXAI_OpenLoadout then
		_G.CTRBLXAI_OpenLoadout()
	else
		-- Fallback to old hub if new screen not loaded yet
		createLoadoutHub(phase)
	end
end)
