-- CommandService.lua
-- CTRBLXAI | Slice 3
--
-- The single entry point for all unit actions.
-- Implements the 9-step Command Pipeline.
--
-- Slice 3 channeling rules:
--   - Skills with channelTime > 0 enter Channeling state on commit.
--   - MP is CHECKED at commit (must be sufficient) but NOT spent.
--   - MP is SPENT at activation (when channel completes).
--   - If MP is insufficient at activation (e.g. enemy drained mana), skill fizzles.
--   - Silence, Stun, or any disabling status interrupts channeling.
--   - Damage does NOT interrupt channeling.
--
-- Also:
--   - AOE skills (Cleave pattern) resolve against multiple targets.
--   - Healing skills target allies/self.
--   - MP cost deducted on instant skills.

local UnitSchema        = require(script.Parent.UnitSchema)
local TargetingService  = require(script.Parent.TargetingService)
local CombatResolver    = require(script.Parent.CombatResolver)
local BattleCoordinator = require(script.Parent.BattleCoordinator)
local StatusService     = require(script.Parent.StatusService)
local BattleVisualBroadcaster = require(script.Parent.BattleVisualBroadcaster)
local DisplacementService = require(script.Parent.DisplacementService)

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

-- Bind UnitSchema helpers into CombatResolver.
CombatResolver.BindApplyDamage(UnitSchema.ApplyDamage)
CombatResolver.BindApplyHealing(UnitSchema.ApplyHealing)

local CommandService = {}

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

local MOVE_RT_FACTOR         = GameConstants.MOVE_RT_FACTOR
local BASIC_ATTACK_RT_FACTOR = GameConstants.BASIC_ATTACK_RT_FACTOR

--------------------------------------------------
-- SKILL REGISTRY
--------------------------------------------------

local skillRegistry = {}

function CommandService.RegisterSkill(skillDef)
	assert(
		type(skillDef.id) == "string",
		"RegisterSkill: skillDef must have an id string."
	)
	skillRegistry[skillDef.id] = skillDef
end

function CommandService.GetSkill(skillId)
	return skillRegistry[skillId]
end

function CommandService.GetAllSkills()
	return skillRegistry
end

local function lookupSkill(skillId)
	return skillRegistry[skillId]
end

--------------------------------------------------
-- MAP STATE
--------------------------------------------------

local _mapWidth  = 8
local _mapHeight = 8

function CommandService.SetMapDimensions(width, height)
	_mapWidth  = width
	_mapHeight = height
end

--------------------------------------------------
-- RT CALCULATION
--------------------------------------------------

local function calcMoveRt(actor, tilesMoving)
	local modBaseRt = StatusService.GetModifiedBaseRt(actor)
	local perTile = modBaseRt * MOVE_RT_FACTOR
	return math.round(perTile * tilesMoving)
end

local function calcBasicAttackBaseRt(actor)
	-- DB formula: Basic Attack RT = round(Modified Base RT × 0.10) + Effective Weapon WT
	-- Effective WT = raw WT × (1 - STR/(200+STR)) — STR reduces burden
	local modBaseRt = StatusService.GetModifiedBaseRt(actor)
	local str = actor.effectiveStats and actor.effectiveStats.STR or 10
	local effectiveWt = GameConstants.CalcEffectiveWt(actor.weaponWt or 0, str)
	return math.round(modBaseRt * BASIC_ATTACK_RT_FACTOR) + math.round(effectiveWt)
end

--------------------------------------------------
-- PUBLIC: GetSkillCandidates (for AI and client)
--------------------------------------------------

function CommandService.GetSkillCandidates(actor, allUnits, skillId)
	local skillDef = lookupSkill(skillId)
	if not skillDef then return {} end
	return TargetingService.GetSkillCandidates(actor, allUnits, skillDef)
end

--------------------------------------------------
-- PUBLIC: GetUnitSkills (for client Skill Card UI)
--------------------------------------------------

function CommandService.GetUnitSkills(unit)
	local skills = {}
	for _, sid in ipairs(unit.skillIds or {}) do
		local def = lookupSkill(sid)
		if def then
			table.insert(skills, def)
		end
	end
	if #skills == 0 and unit.skillId then
		local def = lookupSkill(unit.skillId)
		if def then
			table.insert(skills, def)
		end
	end
	return skills
end

--------------------------------------------------
-- PUBLIC: ActivateChanneledSkill
--
-- Called when a channeling unit's turn comes up.
-- Checks MP, spends it, resolves the skill.
-- Returns: success (bool), result info table or nil
--------------------------------------------------

function CommandService.ActivateChanneledSkill(state, unit)
	if not unit.isChanneling or not unit.channelingData then
		return false, "Unit is not channeling."
	end

	local data     = unit.channelingData
	local skillDef = data.skillDef
	local target   = data.target
	local mpCost   = data.mpCost or 0

	-- Clear channeling state first (regardless of outcome)
	unit.isChanneling   = false
	unit.channelingData = nil

	-- Check if target is still alive (for offensive/healing skills)
	if target and not target.isAlive then
		print(string.format(
			"[CommandService] Channel FIZZLE | %s | [%s] — target %s is dead",
			unit.name, skillDef.name or skillDef.id, target.name
		))
		return false, "Target died during channel."
	end

	-- Check MP at activation — if insufficient, fizzle
	if not UnitSchema.HasEnoughMp(unit, mpCost) then
		print(string.format(
			"[CommandService] Channel FIZZLE | %s | [%s] — MP insufficient (%d/%d needed)",
			unit.name, skillDef.name or skillDef.id, unit.currentMp, mpCost
		))
		return false, "MP insufficient at activation."
	end

	-- SPEND MP now
	UnitSchema.SpendMp(unit, mpCost)

	-- RT cost for the activation itself is minimal (skill already "charged")
	local activationRt = skillDef.rtCost or math.round(
		StatusService.GetModifiedBaseRt(unit) * 0.10
	)
	BattleCoordinator.AccrueRt(state, activationRt)

	-- Resolve the skill
	local result = {}

	if skillDef.isHealing then
		local outcome = CombatResolver.ResolveHealing(unit, target, skillDef)
		local actual = CombatResolver.ApplyOutcome(outcome, target)
		result.type     = "Healing"
		result.target   = target
		result.healing  = actual
		result.skillName = skillDef.name

		print(string.format(
			"[CommandService] Channel ACTIVATE [%s] | %s -> %s | Heal:%d | MP:%d",
			skillDef.name, unit.name, target.name, actual, mpCost
		))

	elseif skillDef.aoePattern == "Cleave" then
		local targets = TargetingService.GetCleaveTargets(unit, target, state.units)
		local totalDmg = 0
		local hitCount = 0
		local allOutcomes = {}
		for _, t in ipairs(targets) do
			if t.isAlive then
				local outcome = CombatResolver.ResolveSkill(unit, t, skillDef)
				CombatResolver.ApplyOutcome(outcome, t)
				totalDmg = totalDmg + outcome.finalDamage
				hitCount = hitCount + 1
				table.insert(allOutcomes, { target = t, outcome = outcome })
			end
		end
		result.type      = "AOE"
		result.targets   = allOutcomes
		result.totalDmg  = totalDmg
		result.hitCount  = hitCount
		result.skillName = skillDef.name

		print(string.format(
			"[CommandService] Channel ACTIVATE [%s] AOE | %s | Hits:%d | Dmg:%d | MP:%d",
			skillDef.name, unit.name, hitCount, totalDmg, mpCost
		))
	else
		-- Single target damage
		local outcome = CombatResolver.ResolveSkill(unit, target, skillDef)
		local actualDmg, statusApplied = CombatResolver.ApplyOutcome(outcome, target)
		result.type          = "Damage"
		result.target        = target
		result.damage        = outcome.finalDamage
		result.statusApplied = statusApplied
		result.skillName     = skillDef.name

		print(string.format(
			"[CommandService] Channel ACTIVATE [%s] | %s -> %s | Dmg:%d | MP:%d%s",
			skillDef.name, unit.name, target.name,
			outcome.finalDamage, mpCost,
			statusApplied and (" | +" .. statusApplied) or ""
		))
	end

	return true, result
end

--------------------------------------------------
-- PUBLIC: ValidateAndCommit
--------------------------------------------------

function CommandService.ValidateAndCommit(
	state,
	actorId,
	actionType,
	selection
)
	-- STEP 1: Receive command
	local actor = nil
	for _, unit in ipairs(state.units) do
		if unit.id == actorId then
			actor = unit
			break
		end
	end

	if not actor then
		return false, "Actor not found: " .. tostring(actorId)
	end

	-- STEP 2: Turn gate
	if state.phase ~= "TurnOpen" then
		return false, "No turn is open."
	end
	if state.activeUnit ~= actor then
		return false, actor.name .. " is not the active unit."
	end

	-- STEP 3: Action availability
	if not actor.isAlive then
		return false, actor.name .. " is defeated."
	end
	if actionType ~= "Wait" and actor.currentAp <= 0 then
		return false, actor.name .. " has no AP remaining."
	end

	-- STEP 4: Loadout legality (stub)

	-- STEP 5: Selection validation
	local skillDef = nil

	if actionType == "Skill" then
		if type(selection) ~= "table" or not selection.skillId then
			return false, "Skill command requires a selection with skillId."
		end

		skillDef = lookupSkill(selection.skillId)
		if not skillDef then
			return false, "Unknown skill: " .. tostring(selection.skillId)
		end

		-- MP check (must have enough — not spent yet for channeled skills)
		local mpCost = skillDef.mpCost or 0
		if not UnitSchema.HasEnoughMp(actor, mpCost) then
			return false, string.format(
				"%s does not have enough MP (%d/%d needed).",
				actor.name, actor.currentMp, mpCost
			)
		end

		local targetSelection = {
			target      = selection.target,
			skillRange  = skillDef.range or 1,
			targetRules = skillDef.targetRules or "Enemy Unit",
		}

		local valid, reason = TargetingService.ValidateSelection(
			actor, "Skill", targetSelection,
			state.units, _mapWidth, _mapHeight
		)
		if not valid then return false, reason end
	elseif actionType ~= "Wait" and actionType ~= "Guard" and actionType ~= "Push" then
		-- Move and Attack need target/tile validation
		local valid, reason = TargetingService.ValidateSelection(
			actor, actionType, selection,
			state.units, _mapWidth, _mapHeight
		)
		if not valid then return false, reason end
	end

	-- STEP 6: Cost evaluation
	local apCost = (actionType == "Wait") and 0 or 1
	if apCost > 0 and actor.currentAp < apCost then
		return false, actor.name .. " does not have enough AP."
	end

	-- STEP 7: Snapshot (stub)

	-- STEP 8: Atomic commit
	actor.currentAp = actor.currentAp - apCost

	if actionType == "Move" then
		local pathCost
		if selection.pathCost ~= nil then
			pathCost = selection.pathCost
		else
			local dx = math.abs(selection.tileX - actor.tileX)
			local dy = math.abs(selection.tileY - actor.tileY)
			pathCost = dx + dy
		end
		local rtCost = calcMoveRt(actor, pathCost)
		BattleCoordinator.AccrueRt(state, rtCost)

		actor.tileX = selection.tileX
		actor.tileY = selection.tileY

		print(string.format(
			"[CommandService] MOVE | %s -> (%d,%d) | RT:%d | AP left:%d",
			actor.name, actor.tileX, actor.tileY,
			rtCost, actor.currentAp
		))

	elseif actionType == "Attack" then
		local target = selection
		-- calcBasicAttackBaseRt already includes Effective Weapon WT
		local rtCost = calcBasicAttackBaseRt(actor)

		local weaponDamage = actor.weaponDamage or 10
		local outcome = CombatResolver.ResolveBasicAttack(actor, target, weaponDamage)
		CombatResolver.ApplyOutcome(outcome, target)
		BattleCoordinator.AccrueRt(state, rtCost)

		-- Missing 7: Apply Weapon RT Delay to target (reduced by target VIT)
		local rawDelay = actor.weaponRtDelay or 0
		if rawDelay > 0 and target.isAlive then
			local targetVit = target.effectiveStats and target.effectiveStats.VIT or 10
			local actualDelay = GameConstants.CalcRtDelayResistance(rawDelay, targetVit)
			target.remainingRt = target.remainingRt + math.max(0, actualDelay)
		end

		print(string.format(
			"[CommandService] ATTACK | %s -> %s | Dmg:%d | RT:%d | AP left:%d",
			actor.name, target.name,
			outcome.finalDamage, rtCost, actor.currentAp
		))

	elseif actionType == "Skill" then
		local target = selection.target
		local mpCost = skillDef.mpCost or 0

		-- Check if this is a CHANNELED skill
		if skillDef.channelTime and skillDef.channelTime > 0 then
			-- CHANNELED SKILL: don't spend MP, don't resolve.
			-- Set up channeling state, end turn with channel RT.
			local dex = actor.effectiveStats and actor.effectiveStats.DEX or 10
			local channelRt = GameConstants.CalcChannelTime(skillDef.channelTime, dex)

			BattleCoordinator.StartChanneling(actor, {
				skillDef = skillDef,
				target   = target,
				mpCost   = mpCost,
			})

			-- Force end turn with channel RT as the wait time
			-- Use remaining AP to signal "turn is done"
			actor.currentAp = 0
			BattleCoordinator.EndTurnChanneling(state, channelRt)

			print(string.format(
				"[CommandService] SKILL COMMIT (CHANNEL) [%s] | %s -> %s | Channel RT:%d | MP reserved:%d",
				skillDef.name or skillDef.id,
				actor.name, target.name,
				channelRt, mpCost
			))

			return true, nil -- Turn already ended by EndTurnChanneling
		end

		-- INSTANT SKILL: spend MP and resolve immediately
		UnitSchema.SpendMp(actor, mpCost)

		local baseRtCost = skillDef.rtCost or math.round(
			StatusService.GetModifiedBaseRt(actor) * 0.10
		)

		if skillDef.isHealing then
			local outcome = CombatResolver.ResolveHealing(actor, target, skillDef)
			CombatResolver.ApplyOutcome(outcome, target)
			BattleCoordinator.AccrueRt(state, baseRtCost)

			print(string.format(
				"[CommandService] SKILL [%s] | %s -> %s | Heal:%d | MP:%d | RT:%d | AP left:%d",
				skillDef.name or skillDef.id,
				actor.name, target.name,
				outcome.finalHealing, mpCost, baseRtCost, actor.currentAp
			))

		elseif skillDef.aoePattern == "Cleave" then
			local targets = TargetingService.GetCleaveTargets(
				actor, target, state.units
			)
			local totalDmg = 0
			local hitCount = 0
			for _, t in ipairs(targets) do
				if t.isAlive then
					local outcome = CombatResolver.ResolveSkill(actor, t, skillDef)
					CombatResolver.ApplyOutcome(outcome, t)
					totalDmg = totalDmg + outcome.finalDamage
					hitCount = hitCount + 1
				end
			end
			BattleCoordinator.AccrueRt(state, baseRtCost)

			print(string.format(
				"[CommandService] SKILL [%s] AOE | %s | Hits:%d | TotalDmg:%d | MP:%d | RT:%d | AP left:%d",
				skillDef.name or skillDef.id,
				actor.name, hitCount, totalDmg, mpCost, baseRtCost, actor.currentAp
			))
		else
			local outcome = CombatResolver.ResolveSkill(actor, target, skillDef)
			local actualDmg, statusApplied = CombatResolver.ApplyOutcome(outcome, target)
			BattleCoordinator.AccrueRt(state, baseRtCost)

			local rawDelay = actor.weaponRtDelay or 0
			if rawDelay > 0 and target.isAlive then
				local targetVit = target.effectiveStats and target.effectiveStats.VIT or 10
				local actualDelay = GameConstants.CalcRtDelayResistance(rawDelay, targetVit)
				target.remainingRt = target.remainingRt + math.max(0, actualDelay)
			end

			print(string.format(
				"[CommandService] SKILL [%s] | %s -> %s | Dmg:%d | MP:%d | RT:%d | AP left:%d%s",
				skillDef.name or skillDef.id,
				actor.name, target.name,
				outcome.finalDamage, mpCost, baseRtCost, actor.currentAp,
				statusApplied and (" | +" .. statusApplied) or ""
			))
		end

	elseif actionType == "Wait" then
		print(string.format("[CommandService] WAIT | %s", actor.name))
		BattleCoordinator.EndTurn(state)
		return true, nil

	elseif actionType == "Guard" then
		-- Guard: 1 AP, once per turn, enters Guard stance
		if actor.guardUsedThisTurn then
			return false, "Guard already used this turn"
		end

		-- Calculate Guard RT
		-- Guard RT = round(Modified Base RT × 0.10) + 50% of Effective Armor Off-Hand WT
		local modBaseRt = StatusService.GetModifiedBaseRt(actor)
		local offHandWt = 0
		if actor.weaponHandClass ~= "2H" then
			-- Get off-hand WT (if a shield/off-hand is equipped)
			if actor.equipmentSlots and actor.equipmentSlots.OffHand then
				local offHandItem = actor.equipmentSlots.OffHand
				offHandWt = offHandItem.scaledWt or offHandItem.wt or 0
			end
		end
		local guardRt = math.round(modBaseRt * GameConstants.GUARD_RT_BASE_FACTOR)
			+ math.round(offHandWt * GameConstants.GUARD_OFFHAND_WT_FACTOR)

		-- Apply Guard as a proper status (dispellable buff, removed by CC)
		StatusService.ApplyStatus(actor, "Guard", actor.id)
		actor.guardUsedThisTurn = true
		BattleCoordinator.AccrueRt(state, guardRt)

		print(string.format(
			"[CommandService] GUARD | %s | RT:%d | OffHandWT:%d | AP left:%d",
			actor.name, guardRt, offHandWt, actor.currentAp
		))

		-- Calculate effective mitigation for display
		local mitigation = GameConstants.GUARD_MITIGATION + (actor.guardBonus or 0)
		mitigation = math.min(mitigation, GameConstants.GUARD_CAP)
		BattleVisualBroadcaster.GuardActivated(actor, guardRt, mitigation)

	elseif actionType == "Push" then
		-- Push: 1 AP, push adjacent enemy away
		-- selection = target unit
		local target = selection
		if not target or not target.isAlive then
			return false, "Push target is invalid or defeated."
		end

		-- Must be adjacent (Chebyshev distance 1)
		local dist = math.max(
			math.abs(actor.tileX - target.tileX),
			math.abs(actor.tileY - target.tileY)
		)
		if dist > 1 then
			return false, "Push target must be adjacent."
		end

		-- Push RT = round(Modified Base RT × 0.10)
		local modBaseRt = StatusService.GetModifiedBaseRt(actor)
		local pushRt = math.round(modBaseRt * GameConstants.GUARD_RT_BASE_FACTOR)
		BattleCoordinator.AccrueRt(state, pushRt)

		-- Resolve displacement
		local force = 1
		if actor.derivedStats and actor.derivedStats.force then
			force = actor.derivedStats.force
		elseif actor.effectiveStats and actor.effectiveStats.STR then
			force = 1 + math.floor(actor.effectiveStats.STR / 60)
		end
		local direction = DisplacementService.GetPushDirection(actor, target)
		local result = DisplacementService.ResolvePush(
			actor, target, force, direction,
			GameConstants.KNOCKBACK_SOURCE_MODIFIERS.GlobalPush,
			state.units
		)

		-- Apply position change
		target.tileX = result.finalTileX
		target.tileY = result.finalTileY

		-- Apply collision/fall damage
		local totalPushDmg = 0
		if result.wallCollision and result.wallCollision.damage > 0 then
			totalPushDmg = totalPushDmg + result.wallCollision.damage
		end
		if result.fallDamage and result.fallDamage > 0 then
			totalPushDmg = totalPushDmg + result.fallDamage
		end
		if totalPushDmg > 0 then
			UnitSchema.ApplyDamage(target, totalPushDmg)
		end

		-- Broadcast
		BattleVisualBroadcaster.UnitPushed(actor, target, result)

		print(string.format(
			"[CommandService] PUSH | %s -> %s | Force:%d | Moved:%d to (%d,%d) | Dmg:%d | RT:%d | AP left:%d",
			actor.name, target.name, force,
			result.tilesDisplaced, result.finalTileX, result.finalTileY,
			totalPushDmg, pushRt, actor.currentAp
		))

	end

	-- STEP 9: Handoff
	if actor.currentAp <= 0 then
		BattleCoordinator.EndTurn(state)
	end

	return true, nil
end

return CommandService
