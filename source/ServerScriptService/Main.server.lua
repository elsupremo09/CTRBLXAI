-- Main.server.lua
-- CTRBLXAI | Slice 3 — "Skills and Real Combat"
--
-- Player-controlled units wait for client input.
-- Enemy units use AI.
--
-- Player input flow:
--   1. Server sends PlayerTurnPrompt with available actions
--   2. Client shows Skill Cards + Move highlights + Attack option
--   3. Player clicks → client fires PlayerCommand
--   4. Server validates and commits
--   5. If AP remains, send another prompt. If AP=0, turn ends.

local ServerScriptService = game:GetService("ServerScriptService")
local Players             = game:GetService("Players")
local Game = ServerScriptService:WaitForChild("Game")

local UnitSchema              = require(Game:WaitForChild("UnitSchema"))
local BattleCoordinator       = require(Game:WaitForChild("BattleCoordinator"))
local CommandService          = require(Game:WaitForChild("CommandService"))
local TargetingService        = require(Game:WaitForChild("TargetingService"))
local BattleVisualBroadcaster = require(Game:WaitForChild("BattleVisualBroadcaster"))
local StatusService           = require(Game:WaitForChild("StatusService"))
local CombatResolver          = require(Game:WaitForChild("CombatResolver"))
local ItemGenerator           = require(Game:WaitForChild("ItemGenerator"))
local InventoryService        = require(Game:WaitForChild("InventoryService"))
local EquipmentService        = require(Game:WaitForChild("EquipmentService"))

local WeaponData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("WeaponData")
)
local DoctrineData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("DoctrineData")
)

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

local BattleEvents = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Remotes")
		:WaitForChild("BattleEvents")
)

--------------------------------------------------
-- TILE OCCUPANCY HELPERS
--------------------------------------------------

local mapFolder = workspace:WaitForChild("TemplateViewerMap")

local BATTLE_OFFSET_X = 11
local BATTLE_OFFSET_Y = 6

local function findTilePart(x, y)
	local templateX = x + BATTLE_OFFSET_X
	local templateY = y + BATTLE_OFFSET_Y
	for _, child in ipairs(mapFolder:GetChildren()) do
		if child:GetAttribute("X") == templateX and child:GetAttribute("Y") == templateY then
			return child
		end
	end
	return nil
end

local function setTileOccupant(x, y, name, category, impact)
	local tile = findTilePart(x, y)
	if not tile then return end
	tile:SetAttribute("ObjectName", name)
	tile:SetAttribute("ObjectCategory", category)
	tile:SetAttribute("ObjectPassabilityImpact", impact)
end

local function clearTileOccupant(x, y)
	setTileOccupant(x, y, "None", "None", "None")
end

--------------------------------------------------
-- MAP SETUP
--------------------------------------------------

local MAP_WIDTH  = 8
local MAP_HEIGHT = 8

CommandService.SetMapDimensions(MAP_WIDTH, MAP_HEIGHT)

--------------------------------------------------
-- SKILL REGISTRATION
--------------------------------------------------

for _, skillDef in pairs(GameConstants.SKILLS) do
	CommandService.RegisterSkill(skillDef)
end

--------------------------------------------------
-- UNIT DEFINITIONS
-- Player units have controller = "Player" (waits for input)
-- Enemy units have controller = "AI"
--
-- Slice 4A: Units now get equipment via ItemGenerator + EquipmentService.
-- Player ID for inventory ownership:
--------------------------------------------------

local PLAYER_ID = "player_1"
InventoryService.InitPlayer(PLAYER_ID)

-- Helper: generate a weapon, add to inventory, equip on unit
local function equipGeneratedWeapon(unit, archetypeId, itemLevel, rarity, seed)
	local item = ItemGenerator.Generate({
		baseArchetypeId = archetypeId,
		itemLevel = itemLevel,
		rarity = rarity,
		seed = seed,
		sourceType = "Debug",
	})
	if not item then
		warn("[Main] Failed to generate weapon: " .. archetypeId)
		return
	end
	InventoryService.AddItem(PLAYER_ID, item)
	EquipmentService.Equip(unit, item, "MainHand")
end

local hero = UnitSchema.Create({
	id           = "unit_hero",
	name         = "Hero",
	side         = "Player",
	controller   = "Player",
	tileX        = 4,
	tileY        = 2,
	stats        = { STR = 18, AGI = 14, INT = 8, VIT = 16, DEX = 12, LUK = 10 },
	skillIds     = { "skill_power_strike", "skill_sweeping_cut" },
})
equipGeneratedWeapon(hero, "WPN-SWORD", 5, "Uncommon", 1001)

local mage = UnitSchema.Create({
	id           = "unit_mage",
	name         = "Mage",
	side         = "Player",
	controller   = "Player",
	tileX        = 3,
	tileY        = 1,
	stats        = { STR = 6, AGI = 10, INT = 20, VIT = 10, DEX = 14, LUK = 8 },
	skillIds     = { "skill_fire_bolt", "skill_healing_light" },
})
equipGeneratedWeapon(mage, "WPN-WAND", 5, "Uncommon", 1002)

local ranger = UnitSchema.Create({
	id           = "unit_ranger",
	name         = "Ranger",
	side         = "Player",
	controller   = "Player",
	tileX        = 5,
	tileY        = 3,
	stats        = { STR = 12, AGI = 16, INT = 8, VIT = 12, DEX = 18, LUK = 10 },
	skillIds     = { "skill_crippling_shot", "skill_venom_strike" },
})
equipGeneratedWeapon(ranger, "WPN-CROSSBOW", 5, "Uncommon", 1003)

local grunt = UnitSchema.Create({
	id           = "unit_grunt",
	name         = "Grunt",
	side         = "Enemy",
	controller   = "AI",
	tileX        = 5,
	tileY        = 7,
	stats        = { STR = 14, AGI = 10, INT = 6, VIT = 14, DEX = 8, LUK = 6 },
	skillIds     = { "skill_venom_strike", "skill_crippling_shot" },
})
equipGeneratedWeapon(grunt, "WPN-SPEAR", 5, "Common", 2001)

local pyro = UnitSchema.Create({
	id           = "unit_pyro",
	name         = "Pyro",
	side         = "Enemy",
	controller   = "AI",
	tileX        = 6,
	tileY        = 7,
	stats        = { STR = 8, AGI = 12, INT = 16, VIT = 10, DEX = 10, LUK = 8 },
	skillIds     = { "skill_fire_bolt", "skill_power_strike" },
})
equipGeneratedWeapon(pyro, "WPN-STAFF", 5, "Common", 2002)

local shaman = UnitSchema.Create({
	id           = "unit_shaman",
	name         = "Shaman",
	side         = "Enemy",
	controller   = "AI",
	tileX        = 4,
	tileY        = 8,
	stats        = { STR = 6, AGI = 8, INT = 18, VIT = 14, DEX = 12, LUK = 10 },
	skillIds     = { "skill_healing_light", "skill_crippling_shot" },
})
equipGeneratedWeapon(shaman, "WPN-WAND", 5, "Common", 2003)

local allUnitsList = { hero, mage, ranger, grunt, pyro, shaman }
for _, u in ipairs(allUnitsList) do
	setTileOccupant(u.tileX, u.tileY, u.name, "Unit (" .. u.side .. ")", "Blocking")
end

print("====================================")
print("CTRBLXAI — Slice 3: Skills and Real Combat")
print("====================================")
for _, u in ipairs(allUnitsList) do
	print(string.format("  %s", UnitSchema.Describe(u)))
end
print("====================================")

--------------------------------------------------
-- BATTLE STATE
--------------------------------------------------

local state = BattleCoordinator.CreateBattleState(allUnitsList)

task.wait(2)
BattleVisualBroadcaster.BattleStarted(state.units)

--------------------------------------------------
-- CHANNEL INTERRUPT HOOK
--------------------------------------------------

local function checkChannelInterrupt(unit, statusId)
	if unit.isChanneling and StatusService.IsChannelDisruptor(statusId) then
		BattleCoordinator.InterruptChanneling(unit, statusId .. " applied")
		return true
	end
	return false
end

--------------------------------------------------
-- PLAYER TURN: Build prompt data
--
-- Sends the player all info needed to choose an action:
--   - Available skills (with MP check)
--   - Move candidates (tiles they can walk to)
--   - Attack candidates (enemies in melee range)
--------------------------------------------------

local function buildTurnPrompt(unit)
	-- Timeline data: all alive units sorted by remainingRt (who acts soonest)
	local timeline = {}
	for _, u in ipairs(state.units) do
		if u.isAlive then
			table.insert(timeline, {
				id          = u.id,
				name        = u.name,
				side        = u.side,
				remainingRt = u.remainingRt,
				currentHp   = u.currentHp,
				maxHp       = u.maxHp,
				isChanneling = u.isChanneling or false,
				channelRt   = u.channelRt or 0,
				channeledSkillName = u.channelingData and u.channelingData.skillDef and u.channelingData.skillDef.name or nil,
			})
		end
	end
	table.sort(timeline, function(a, b) return a.remainingRt < b.remainingRt end)

	local skills = {}
	for _, sid in ipairs(unit.skillIds or {}) do
		local def = CommandService.GetSkill(sid)
		if def then
			local canUse = UnitSchema.HasEnoughMp(unit, def.mpCost or 0)
			local candidates = TargetingService.GetSkillCandidates(unit, state.units, def)
			local targetIds = {}
			for _, c in ipairs(candidates) do
				-- Pre-calculate predicted value for this target
				local predicted = 0
				local predType = "damage"
				if def.isHealing then
					local healResult = CombatResolver.ResolveHealing(unit, c, def)
					predicted = healResult.finalHealing or 0
					predType = "healing"
				else
					local dmgResult = CombatResolver.ResolveSkill(unit, c, def)
					predicted = dmgResult.finalDamage or 0
				end
				table.insert(targetIds, {
					id        = c.id,
					name      = c.name,
					tileX     = c.tileX,
					tileY     = c.tileY,
					predicted = predicted,
					predType  = predType,
				})
			end

			table.insert(skills, {
				id          = def.id,
				name        = def.name,
				willEndTurn = (def.channelTime or 0) > 0, -- warn player: channeling ends turn
				mpCost      = def.mpCost or 0,
				range       = def.range or 1,
				pattern     = def.pattern or "Single",
				targetRules = def.targetRules or "Enemy Unit",
				isHealing   = def.isHealing or false,
				channelTime = def.channelTime or 0,
				canUse      = canUse,
				targets     = targetIds,
				tags        = def.tags or {},
				rtCost      = def.rtCost or 60,
				power       = def.power or 0,
				description = def.isHealing and "Heals ally" or (def.appliesStatus and ("Applies " .. def.appliesStatus) or "Damages target"),
			})
		end
	end

	local moveTiles = TargetingService.GetMoveCandidates(unit, state.units, MAP_WIDTH, MAP_HEIGHT)
	local moveCandidates = {}
	for _, tile in ipairs(moveTiles) do
		table.insert(moveCandidates, { tileX = tile.tileX, tileY = tile.tileY, pathCost = tile.pathCost })
	end

	local attackCandidates = TargetingService.GetAttackCandidates(unit, state.units, unit.weaponMaxRange or 1)
	local attackTargets = {}
	for _, c in ipairs(attackCandidates) do
		-- Pre-calculate predicted basic attack damage for aim phase
		local atkResult = CombatResolver.ResolveBasicAttack(unit, c, unit.weaponDamage or 10)
		table.insert(attackTargets, {
			id        = c.id,
			name      = c.name,
			tileX     = c.tileX,
			tileY     = c.tileY,
			predicted = atkResult.finalDamage or 0,
		})
	end

	return {
		unitId         = unit.id,
		unitName       = unit.name,
		unitSide       = unit.side,
		currentAp      = unit.currentAp,
		currentMp      = unit.currentMp,
		maxMp          = unit.maxMp,
		currentHp      = unit.currentHp,
		maxHp          = unit.maxHp,
		tileX          = unit.tileX,
		tileY          = unit.tileY,
		skills         = skills,
		moveCandidates = moveCandidates,
		attackTargets  = attackTargets,
		timeline       = timeline,
		currentCt      = state.ct,
		-- RT cost data so client can preview turn order shifts
		unitBaseRt = StatusService.GetModifiedBaseRt(unit),
		attackRt   = math.round(
			StatusService.GetModifiedBaseRt(unit) * GameConstants.BASIC_ATTACK_RT_FACTOR
		) + math.round(GameConstants.CalcEffectiveWt(
			unit.weaponWt or 40, unit.effectiveStats and unit.effectiveStats.STR or 10
		)),
		waitRt     = math.round(
			StatusService.GetModifiedBaseRt(unit) * GameConstants.REST_RT_MULTIPLIER
		),
		weaponRtDelay = unit.weaponRtDelay or 0,
		weaponDamage  = unit.weaponDamage or 10,
	}
end

--------------------------------------------------
-- PLAYER TURN: Wait for player command
--
-- Sends prompt, then yields until the client fires PlayerCommand.
-- Returns the command payload or nil on timeout.
--------------------------------------------------

local PLAYER_TURN_TIMEOUT = 120 -- seconds

local pendingCommand = nil
local commandReceived = Instance.new("BindableEvent")

BattleEvents.PlayerCommand.OnServerEvent:Connect(function(player, command)
	-- Accept commands from any connected player (single-player for now)
	pendingCommand = command
	commandReceived:Fire()
end)

local function waitForPlayerCommand(unit, playerObj)
	-- Send prompt to client
	local prompt = buildTurnPrompt(unit)
	print(string.format(
		"[Main] Sending PlayerTurnPrompt to %s for %s (AP:%d, Skills:%d, Moves:%d)",
		playerObj.Name, unit.name, unit.currentAp, #prompt.skills, #prompt.moveCandidates
	))
	BattleEvents.PlayerTurnPrompt:FireClient(playerObj, prompt)

	-- Wait for response
	pendingCommand = nil
	local startTime = tick()

	while not pendingCommand do
		local elapsed = tick() - startTime
		if elapsed > PLAYER_TURN_TIMEOUT then
			print("[Main] Player turn TIMEOUT — auto-waiting.")
			return { actionType = "Wait" }
		end
		commandReceived.Event:Wait()
	end

	local cmd = pendingCommand
	pendingCommand = nil
	return cmd
end

--------------------------------------------------
-- PLAYER TURN: Execute one player command
-- Returns: action table for broadcasting, or nil
--------------------------------------------------

local function executePlayerCommand(unit, command)
	local actionType = command.actionType

	if actionType == "Wait" then
		CommandService.ValidateAndCommit(state, unit.id, "Wait", nil)
		return { actionType = "Wait", unit = unit }
	end

	if actionType == "Move" then
		local selection = { tileX = command.tileX, tileY = command.tileY, pathCost = command.pathCost }
		local oldX, oldY = unit.tileX, unit.tileY
		local ok, reason = CommandService.ValidateAndCommit(state, unit.id, "Move", selection)
		if ok then
			return { actionType = "Move", unit = unit, oldTileX = oldX, oldTileY = oldY }
		else
			warn("[Main] Player move rejected: " .. (reason or "unknown"))
			return nil
		end
	end

	if actionType == "Attack" then
		-- Find the target unit by ID
		local target = nil
		for _, u in ipairs(state.units) do
			if u.id == command.targetId then
				target = u
				break
			end
		end
		if not target then
			warn("[Main] Player attack: target not found")
			return nil
		end

		local hpBefore = target.currentHp
		local statusesBefore = #target.statusInstances
		local ok, reason = CommandService.ValidateAndCommit(state, unit.id, "Attack", target)
		if ok then
			local newStatus = nil
			if #target.statusInstances > statusesBefore then
				newStatus = target.statusInstances[#target.statusInstances].id
			end
			return {
				actionType    = "Attack",
				unit          = unit,
				target        = target,
				damage        = hpBefore - target.currentHp,
				statusApplied = newStatus,
			}
		else
			warn("[Main] Player attack rejected: " .. (reason or "unknown"))
			return nil
		end
	end

	if actionType == "Skill" then
		-- Find the target unit by ID
		local target = nil
		for _, u in ipairs(state.units) do
			if u.id == command.targetId then
				target = u
				break
			end
		end
		if not target then
			warn("[Main] Player skill: target not found")
			return nil
		end

		local skillDef = CommandService.GetSkill(command.skillId)
		if not skillDef then
			warn("[Main] Player skill: unknown skill " .. tostring(command.skillId))
			return nil
		end

		-- Snapshot ALL units' HP before commit (for AOE detection)
		local hpSnapshot = {}
		local statusSnapshot = {}
		local burnSnapshot = {}
		for _, u in ipairs(state.units) do
			hpSnapshot[u.id] = u.currentHp
			statusSnapshot[u.id] = #u.statusInstances
			-- Snapshot burn stored value for accumulation detection
			local burnInst = StatusService.HasStatus(u, "Burn")
			burnSnapshot[u.id] = burnInst and burnInst.storedBurn or 0
		end

		local selection = { target = target, skillId = command.skillId }

		local ok, reason = CommandService.ValidateAndCommit(state, unit.id, "Skill", selection)
		if ok then
			-- Detect ALL units that were affected (for AOE skills)
			local results = {}
			for _, u in ipairs(state.units) do
				local prevHp = hpSnapshot[u.id] or u.currentHp
				local hpDiff = prevHp - u.currentHp
				local prevStatuses = statusSnapshot[u.id] or 0
				local newStatus = nil
				if #u.statusInstances > prevStatuses then
					newStatus = u.statusInstances[#u.statusInstances].id
				else
					-- Detect refreshed/accumulated statuses (instance count didn't change)
					if skillDef.appliesStatus and hpDiff > 0 then
						local inst = StatusService.HasStatus(u, skillDef.appliesStatus)
						if inst then
							newStatus = skillDef.appliesStatus
						end
					end
				end
				if hpDiff ~= 0 or newStatus then
					table.insert(results, {
						actionType    = "Skill",
						unit          = unit,
						target        = u,
						skillName     = skillDef.name,
						damage        = math.max(0, hpDiff),
						healing       = math.max(0, -hpDiff),
						statusApplied = newStatus,
						isChanneling  = unit.isChanneling,
					})
				end
			end

			-- Return first result (broadcastActions handles one at a time)
			-- But we need to return ALL results for AOE
			if #results == 1 then
				return results[1]
			elseif #results > 1 then
				-- Return a special multi-hit result
				return { actionType = "MultiHit", actions = results }
			else
				-- No visible change (e.g. channel commit)
				return {
					actionType   = "Skill",
					unit         = unit,
					target       = target,
					skillName    = skillDef.name,
					damage       = 0,
					healing      = 0,
					isChanneling = unit.isChanneling,
				}
			end
		else
			warn("[Main] Player skill rejected: " .. (reason or "unknown"))
			return nil
		end
	end

	warn("[Main] Unknown player command: " .. tostring(actionType))
	return nil
end

--------------------------------------------------
-- PLAYER TURN: Full loop (keeps prompting until AP=0 or Wait)
--------------------------------------------------

local function broadcastActions(actions, activeUnit)
	for _, action in ipairs(actions) do
		if action.actionType == "Move" then
			clearTileOccupant(action.oldTileX, action.oldTileY)
			local u = action.unit
			setTileOccupant(u.tileX, u.tileY, u.name, "Unit (" .. u.side .. ")", "Blocking")
			BattleVisualBroadcaster.UnitMoved(action.unit)

		elseif action.actionType == "Attack" or action.actionType == "Skill" then
			local target = action.target
			if target then
				if action.healing and action.healing > 0 then
					BattleVisualBroadcaster.HealingApplied(
						action.unit, target, action.healing, action.skillName
					)
				elseif action.isChanneling then
					-- Channel commit visual — no damage yet
				else
					local outcome = {
						finalDamage   = action.damage or 0,
						type          = "Damage",
						statusApplied = action.statusApplied,
					}
					BattleVisualBroadcaster.UnitActed(
						action.unit, target, outcome, action.skillName
					)

					if not target.isAlive then
						clearTileOccupant(target.tileX, target.tileY)
					end

					if action.statusApplied then
						local statusInst = StatusService.HasStatus(target, action.statusApplied)
						if statusInst then
							BattleVisualBroadcaster.StatusApplied(
								target, action.statusApplied, statusInst.remainingTurns
							)
						end
						checkChannelInterrupt(target, action.statusApplied)
					end
				end
			end
		end
	end

	-- After each broadcast batch, send updated timeline so client sees
	-- real-time turn order changes (especially during AI turns)
	local timelineUpdate = {}
	for _, u in ipairs(state.units) do
		if u.isAlive then
			table.insert(timelineUpdate, {
				id = u.id, name = u.name, side = u.side,
				remainingRt = u.remainingRt, isChanneling = u.isChanneling or false,
				channelRt = u.channelRt or 0,
				channeledSkillName = u.channelingData and u.channelingData.skillDef and u.channelingData.skillDef.name or nil,
			})
		end
	end
	BattleEvents.TurnOrderUpdate:FireAllClients({ units = timelineUpdate, currentCt = state.ct })
end


local function runPlayerTurn(unit)
	local actions = {}

	-- Find the first connected player (single-player game)
	local playerObj = Players:GetPlayers()[1]
	if not playerObj then
		warn("[Main] No player connected — AI fallback")
		CommandService.ValidateAndCommit(state, unit.id, "Wait", nil)
		return {}
	end

	while BattleCoordinator.GetPhase(state) == "TurnOpen" and unit.currentAp > 0 and unit.isAlive do
		local command = waitForPlayerCommand(unit, playerObj)
		local action = executePlayerCommand(unit, command)

		if action then
			-- Handle MultiHit (AOE) results
			if action.actionType == "MultiHit" then
				for _, subAction in ipairs(action.actions) do
					table.insert(actions, subAction)
				end
				broadcastActions(action.actions, unit)
			else
				table.insert(actions, action)
				broadcastActions({ action }, unit)
			end

			-- If it was Wait, turn ended inside CommandService
			if action.actionType == "Wait" then
				break
			end
		else
			-- Command rejected — send prompt again
		end
	end

	-- Close turn if still open
	if BattleCoordinator.GetPhase(state) == "TurnOpen" then
		CommandService.ValidateAndCommit(state, unit.id, "Wait", nil)
	end

	return actions
end

--------------------------------------------------
-- AI LOGIC (same as before)
--------------------------------------------------

local function findLowestAlly(unit, allUnits)
	local lowest = nil
	local lowestPct = 1.0
	for _, other in ipairs(allUnits) do
		if other.isAlive and other.side == unit.side then
			local pct = other.currentHp / other.maxHp
			if pct < lowestPct then
				lowestPct = pct
				lowest = other
			end
		end
	end
	return lowest, lowestPct
end

local function runAiTurn(unit)
	local allUnits = state.units
	local actions  = {}

	local function tryCommit(actionType, selection, skillName)
		if BattleCoordinator.GetPhase(state) ~= "TurnOpen" then
			return false
		end

		local targetUnit = nil
		if actionType == "Attack" then
			targetUnit = selection
		elseif actionType == "Skill" then
			targetUnit = selection and selection.target
		end
		local hpBefore = targetUnit and targetUnit.currentHp or 0
		local statusesBefore = targetUnit and #targetUnit.statusInstances or 0

		local oldTileX = unit.tileX
		local oldTileY = unit.tileY

		local ok, _ = CommandService.ValidateAndCommit(
			state, unit.id, actionType, selection
		)

		if ok and actionType ~= "Wait" then
			local damage = 0
			local healing = 0
			if targetUnit then
				local hpDiff = hpBefore - targetUnit.currentHp
				if hpDiff > 0 then
					damage = hpDiff
				elseif hpDiff < 0 then
					healing = -hpDiff
				end
			end

			local newStatus = nil
			if targetUnit and #targetUnit.statusInstances > statusesBefore then
				newStatus = targetUnit.statusInstances[#targetUnit.statusInstances].id
			else
				-- Detect refreshed/accumulated statuses (e.g. Burn accumulation)
				if targetUnit and actionType == "Skill" and selection and selection.skillId then
					local def = CommandService.GetSkill(selection.skillId)
					if def and def.appliesStatus and damage > 0 then
						local inst = StatusService.HasStatus(targetUnit, def.appliesStatus)
						if inst then newStatus = def.appliesStatus end
					end
				end
			end

			table.insert(actions, {
				actionType     = actionType,
				unit           = unit,
				oldTileX       = oldTileX,
				oldTileY       = oldTileY,
				target         = targetUnit,
				skillName      = skillName,
				damage         = damage,
				healing        = healing,
				statusApplied  = newStatus,
				isChanneling   = unit.isChanneling,
			})

			if newStatus and targetUnit then
				checkChannelInterrupt(targetUnit, newStatus)
			end
		end

		return ok
	end

	local acted = false
	-- Track if we have a deferred channeling skill to use as last action
	local deferredChannel = nil

	-- 1. Heal if ally below 50%
	local healSkillDef = nil
	for _, sid in ipairs(unit.skillIds or {}) do
		local def = CommandService.GetSkill(sid)
		if def and def.isHealing then
			healSkillDef = def
			break
		end
	end

	if healSkillDef and UnitSchema.HasEnoughMp(unit, healSkillDef.mpCost or 0) then
		local lowestAlly, lowestPct = findLowestAlly(unit, allUnits)
		if lowestAlly and lowestPct < 0.50 then
			-- If channeling skill and AP > 1, defer it (do other actions first)
			local isChannel = (healSkillDef.channelTime or 0) > 0
			if isChannel and unit.currentAp > 1 then
				deferredChannel = { skillDef = healSkillDef, targetId = lowestAlly.id }
			else
				local candidates = TargetingService.GetSkillCandidates(unit, allUnits, healSkillDef)
				for _, c in ipairs(candidates) do
					if c.id == lowestAlly.id then
						local ok = tryCommit("Skill",
							{ target = c, skillId = healSkillDef.id },
							healSkillDef.name
						)
						if ok then acted = true; break end
					end
				end
			end
		end
	end

	-- 2. Offensive skills
	if not acted then
		for _, sid in ipairs(unit.skillIds or {}) do
			local def = CommandService.GetSkill(sid)
			if def and not def.isHealing and UnitSchema.HasEnoughMp(unit, def.mpCost or 0) then
				-- If channeling and AP > 1, defer
				local isChannel = (def.channelTime or 0) > 0
				if isChannel and unit.currentAp > 1 then
					if not deferredChannel then
						local candidates = TargetingService.GetSkillCandidates(unit, allUnits, def)
						if #candidates > 0 then
							deferredChannel = { skillDef = def, targetId = candidates[1].id }
						end
					end
				else
					local candidates = TargetingService.GetSkillCandidates(unit, allUnits, def)
					if #candidates > 0 then
						local ok = tryCommit("Skill",
							{ target = candidates[1], skillId = def.id }, def.name)
						if ok then acted = true; break end
					end
				end
			end
		end
	end

	-- Second action
	if acted and BattleCoordinator.GetPhase(state) == "TurnOpen" and unit.currentAp > 0 then
		local attackCandidates = TargetingService.GetAttackCandidates(unit, allUnits, unit.weaponMaxRange or 1)
		if #attackCandidates > 0 then
			tryCommit("Attack", attackCandidates[1], nil)
		end
	end

	-- 3. Basic attack
	if not acted then
		local attackCandidates = TargetingService.GetAttackCandidates(unit, allUnits, unit.weaponMaxRange or 1)
		if #attackCandidates > 0 then
			acted = true
			tryCommit("Attack", attackCandidates[1], nil)
			if BattleCoordinator.GetPhase(state) == "TurnOpen" and unit.currentAp > 0 then
				attackCandidates = TargetingService.GetAttackCandidates(unit, allUnits, unit.weaponMaxRange or 1)
				if #attackCandidates > 0 then
					tryCommit("Attack", attackCandidates[1], nil)
				end
			end
		end
	end

	-- 4. Move toward enemy
	if not acted then
		local nearestEnemy = nil
		local nearestDist  = math.huge
		for _, other in ipairs(allUnits) do
			if other.isAlive and other.side ~= unit.side then
				local d = math.max(
					math.abs(other.tileX - unit.tileX),
					math.abs(other.tileY - unit.tileY)
				)
				if d < nearestDist then
					nearestDist  = d
					nearestEnemy = other
				end
			end
		end

		if nearestEnemy then
			local moveCandidates = TargetingService.GetMoveCandidates(unit, allUnits, MAP_WIDTH, MAP_HEIGHT)
			local bestTile, bestDist = nil, math.huge
			for _, tile in ipairs(moveCandidates) do
				local d = math.max(
					math.abs(tile.tileX - nearestEnemy.tileX),
					math.abs(tile.tileY - nearestEnemy.tileY)
				)
				if d < bestDist then bestDist = d; bestTile = tile end
			end
			if bestTile then tryCommit("Move", bestTile, nil) end
		end

		if BattleCoordinator.GetPhase(state) == "TurnOpen" and unit.currentAp > 0 then
			local usedSkill = false
			for _, sid in ipairs(unit.skillIds or {}) do
				local def = CommandService.GetSkill(sid)
				if def and not def.isHealing and UnitSchema.HasEnoughMp(unit, def.mpCost or 0) then
					local candidates = TargetingService.GetSkillCandidates(unit, allUnits, def)
					if #candidates > 0 then
						tryCommit("Skill", { target = candidates[1], skillId = def.id }, def.name)
						usedSkill = true; break
					end
				end
			end
			if not usedSkill then
				local attackCandidates = TargetingService.GetAttackCandidates(unit, allUnits, unit.weaponMaxRange or 1)
				if #attackCandidates > 0 then tryCommit("Attack", attackCandidates[1], nil) end
			end
		end
	end

	-- 5. Execute deferred channeling skill (last action, so no AP is wasted)
	if deferredChannel and BattleCoordinator.GetPhase(state) == "TurnOpen" and unit.currentAp > 0 then
		local def = deferredChannel.skillDef
		local targetId = deferredChannel.targetId
		-- Find the target unit
		local target = nil
		for _, u in ipairs(allUnits) do
			if u.id == targetId and u.isAlive then target = u; break end
		end
		if target and UnitSchema.HasEnoughMp(unit, def.mpCost or 0) then
			local candidates = TargetingService.GetSkillCandidates(unit, allUnits, def)
			for _, c in ipairs(candidates) do
				if c.id == targetId then
					tryCommit("Skill", { target = c, skillId = def.id }, def.name)
					break
				end
			end
		end
	end

	if BattleCoordinator.GetPhase(state) == "TurnOpen" then
		CommandService.ValidateAndCommit(state, unit.id, "Wait", nil)
	end

	return actions
end

--------------------------------------------------
-- HANDLE CHANNELING ACTIVATION
--------------------------------------------------

local function handleChannelingActivation(activeUnit)
	-- Grab skill name before activation clears channeling data
	local channeledSkillName = activeUnit.channelingData
		and activeUnit.channelingData.skillDef
		and (activeUnit.channelingData.skillDef.name or activeUnit.channelingData.skillDef.id)
		or "Unknown"

	local success, result = CommandService.ActivateChanneledSkill(state, activeUnit)
	local actions = {}

	if not success then
		-- Fizzle: target died, MP insufficient, etc.
		BattleVisualBroadcaster.ChannelFizzled(activeUnit, channeledSkillName, result or "fizzled")
	elseif result then
		if result.type == "Healing" then
			table.insert(actions, {
				actionType = "Skill", unit = activeUnit, target = result.target,
				skillName = result.skillName, healing = result.healing, damage = 0,
			})
		elseif result.type == "AOE" then
			for _, entry in ipairs(result.targets or {}) do
				table.insert(actions, {
					actionType = "Skill", unit = activeUnit, target = entry.target,
					skillName = result.skillName, damage = entry.outcome.finalDamage,
					healing = 0, statusApplied = entry.outcome.appliesStatus,
				})
			end
		elseif result.type == "Damage" then
			table.insert(actions, {
				actionType = "Skill", unit = activeUnit, target = result.target,
				skillName = result.skillName, damage = result.damage,
				healing = 0, statusApplied = result.statusApplied,
			})
		end
	end

	if BattleCoordinator.GetPhase(state) == "TurnOpen" then
		BattleCoordinator.EndTurn(state)
	end

	return actions
end

--------------------------------------------------
-- BROADCAST ACTIONS HELPER
--------------------------------------------------


--------------------------------------------------
-- BATTLE LOOP
--------------------------------------------------

local MAX_TURNS = 200
local turnCount = 0

while BattleCoordinator.GetPhase(state) ~= "BattleOver" and turnCount < MAX_TURNS do
	local activeUnit = BattleCoordinator.AdvanceClock(state)
	if not activeUnit then break end

	turnCount = turnCount + 1

	-- Process DoT
	local dotEvents = state.dotEvents or {}
	state.dotEvents = nil

	for _, dot in ipairs(dotEvents) do
		if activeUnit.isAlive then
			local actual = UnitSchema.ApplyDamage(activeUnit, dot.damage)
			print(string.format(
				"[DoT] %s takes %d %s damage | HP: %d/%d%s",
				activeUnit.name, actual, dot.statusId,
				activeUnit.currentHp, activeUnit.maxHp,
				activeUnit.isAlive and "" or " | DEFEATED"
			))
			BattleVisualBroadcaster.DotDamage(activeUnit, dot.statusId, actual)
		end
	end

	-- If unit died to DoT
	if not activeUnit.isAlive then
		clearTileOccupant(activeUnit.tileX, activeUnit.tileY)
		if activeUnit.isChanneling then
			BattleCoordinator.InterruptChanneling(activeUnit, "death")
		end
		BattleCoordinator.EndTurn(state)
		BattleVisualBroadcaster.TurnEnded(activeUnit, 0)
		if BattleCoordinator.GetPhase(state) == "BattleOver" then break end
		continue
	end

	BattleVisualBroadcaster.TurnStarted(activeUnit, state.ct, state.units)

	-- Determine turn handler
	local actions
	local wasChanneling = BattleCoordinator.IsChanneling(activeUnit)
	if BattleCoordinator.IsChanneling(activeUnit) then
		actions = handleChannelingActivation(activeUnit)
	elseif activeUnit.controller == "Player" then
		actions = runPlayerTurn(activeUnit)
	else
		actions = runAiTurn(activeUnit)
	end

	-- Broadcast
	-- AI actions: broadcast all at once after turn.
	-- Player actions: broadcast immediately per-action inside runPlayerTurn.
	-- Channeling activations: always broadcast here (player didn't trigger them manually).
	if activeUnit.controller ~= "Player" or wasChanneling then
		broadcastActions(actions, activeUnit)
	end

	-- Safety close
	if BattleCoordinator.GetPhase(state) == "TurnOpen" then
		CommandService.ValidateAndCommit(state, activeUnit.id, "Wait", nil)
	end

	BattleVisualBroadcaster.TurnEnded(activeUnit, activeUnit.remainingRt)
end

--------------------------------------------------
-- RESULT
--------------------------------------------------

print("====================================")
local phase  = BattleCoordinator.GetPhase(state)
local winner = BattleCoordinator.GetWinner(state)

if phase == "BattleOver" then
	print(string.format("BATTLE OVER — %s wins! (%d turns)", winner, turnCount))
else
	print(string.format("BATTLE TIMED OUT after %d turns.", turnCount))
end
print("====================================")
for _, u in ipairs(allUnitsList) do
	print(string.format("  %s", UnitSchema.Describe(u)))
end
print("====================================")

BattleVisualBroadcaster.BattleEnded(winner or "None", state.units)
