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
local RacePassiveService  = require(script.Parent.RacePassiveService)
local DoctrinePassiveService = require(script.Parent.DoctrinePassiveService)
local ArmorPassiveService = require(script.Parent.ArmorPassiveService)
local AugmentEffectService = require(script.Parent.AugmentEffectService)

local ConsumableData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("ConsumableData")
)

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

-- Optional: TileEffectService injected at runtime
local _tileEffectService = nil
function CommandService.SetTileEffectService(tes)
	_tileEffectService = tes
end
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

function CommandService.RegisterSkillAlias(aliasKey, skillDef)
	-- Store the same skillDef under an alias key (e.g. legacy "skill_power_strike")
	skillRegistry[aliasKey] = skillDef
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
	-- Frozen: all RT costs ×2. Wet: movement RT ×1.25.
	local frozenMult = StatusService.GetAllRtMultiplier(actor)
	local wetMult    = StatusService.GetMovementRtMultiplier(actor)
	return math.round(perTile * tilesMoving * frozenMult * wetMult)
end

local function calcBasicAttackBaseRt(actor)
	-- DB formula: Basic Attack RT = round(Modified Base RT × 0.10) + Effective Weapon WT
	-- Effective WT = raw WT × (1 - STR/(200+STR)) — STR reduces burden
	-- Armor WT added to total burden (4G.9: heavy armor slows all actions)
	local modBaseRt = StatusService.GetModifiedBaseRt(actor)
	local str = actor.effectiveStats and actor.effectiveStats.STR or 10
	local totalWt = (actor.weaponWt or 0) + (actor.armorWt or 0)
	local effectiveWt = GameConstants.CalcEffectiveWt(totalWt, str)
	local baseAttackRt = math.round(modBaseRt * BASIC_ATTACK_RT_FACTOR) + math.round(effectiveWt)
	-- Frozen: all RT costs ×2
	return math.round(baseAttackRt * StatusService.GetAllRtMultiplier(actor))
end

--------------------------------------------------
-- ITEM TARGET VALIDATION
--
-- Validates that a consumable item's target satisfies the
-- targetRules from ConsumableData. Range is Chebyshev distance.
--------------------------------------------------

local function validateItemTarget(actor, target, consumableDef)
	local rules = consumableDef.targetRules or "Self"
	local range = consumableDef.range or 0

	-- Self / Self-origin: must target self (or no explicit target needed)
	if rules == "Self" then
		if not target or target.id ~= actor.id then
			return false, "This item can only target yourself."
		end
		return true, nil
	end

	if rules == "Self-origin" or rules == "Self and Allies" then
		-- Self-centered AOE: user is the implicit center
		return true, nil
	end

	-- KO Ally: special — target must be dead
	if rules == "KO Ally" then
		if not target then
			return false, "This item requires a KO'd ally target."
		end
		if target.side ~= actor.side then
			return false, "This item can only target an ally."
		end
		if target.isAlive then
			return false, "This item can only target a KO'd unit."
		end
		local dist = math.max(
			math.abs(actor.tileX - (target.tileX or 0)),
			math.abs(actor.tileY - (target.tileY or 0))
		)
		if dist > range then
			return false, "Target is out of range."
		end
		return true, nil
	end

	-- Ground / Tile targeting: target is a coordinate table { tileX, tileY }
	if rules == "Ground" or rules == "Tile" or rules == "Enemy or Ground" then
		if not target then
			return false, "This item requires a target location."
		end
		local tx = target.tileX or 0
		local ty = target.tileY or 0
		local dist = math.max(
			math.abs(actor.tileX - tx),
			math.abs(actor.tileY - ty)
		)
		if dist > range then
			return false, "Target is out of range."
		end
		return true, nil
	end

	-- All remaining rules require a living unit target
	if not target then
		return false, "This item requires a target."
	end
	if not target.isAlive then
		return false, "Target is defeated."
	end

	-- Chebyshev range check
	local dist = math.max(
		math.abs(actor.tileX - (target.tileX or 0)),
		math.abs(actor.tileY - (target.tileY or 0))
	)
	if dist > range then
		return false, "Target is out of range."
	end

	if rules == "Self or Ally" then
		if target.side ~= actor.side then
			return false, "This item can only target yourself or an ally."
		end
	elseif rules == "Ally" then
		if target.side ~= actor.side or target.id == actor.id then
			return false, "This item can only target an ally (not yourself)."
		end
	elseif rules == "Enemy" or rules == "Enemy Unit" then
		if target.side == actor.side then
			return false, "This item can only target an enemy."
		end
	elseif rules == "Any Unit" then
		-- Any living unit is valid (isAlive already checked above)
	end

	return true, nil
end

--------------------------------------------------
-- ITEM EFFECT RESOLUTION
--
-- Parses effectFormula from ConsumableData and applies the
-- immediate effect. Returns a result table for broadcasting.
--
-- Supported categories:
--   A) HP Recovery   — "Restore N% ... Max HP"
--   B) MP Recovery   — "Restore N% ... Max MP"
--   C) Status Cure   — "Remove [status] and [status]"
--   D) Direct Damage  — "Deal [element] damage equal to N% Weapon Attack Power"
--   E) Status Apply   — "Apply [status] for N turns"
--   F) Unimplemented  — anything else (logged, skipped)
--
-- NOTE: AI item usage would hook into CommandService.GetItemCandidates
-- (not yet implemented — see Main.server.lua AI turn logic).
--------------------------------------------------

local function resolveItemEffect(user, target, consumableDef, allUnits)
	local formula = consumableDef.effectFormula or ""
	local result = {
		effectType  = "Unknown",
		amount      = 0,
		statusId    = nil,
		element     = nil,
		description = formula,
	}

	-- A) HP Recovery: "Restore N% ... Max HP"
	local hpPct = formula:match("Restore (%d+)%%.-Max HP")
	if hpPct then
		local pct = tonumber(hpPct)
		local heal = math.ceil((target.maxHp or 1) * pct / 100)
		UnitSchema.ApplyHealing(target, heal)
		result.effectType = "HpRestore"
		result.amount     = heal
		return result
	end

	-- B) MP Recovery: "Restore N% ... Max MP"
	local mpPct = formula:match("Restore (%d+)%%.-Max MP")
	if mpPct then
		local pct = tonumber(mpPct)
		local restore = math.max(1, math.ceil((target.maxMp or 1) * pct / 100))
		local before  = target.currentMp or 0
		target.currentMp = math.min((target.maxMp or 1), before + restore)
		result.effectType = "MpRestore"
		result.amount     = target.currentMp - before
		return result
	end

	-- C) Status Cure: "Remove [status] and/or [status]"
	if formula:match("^Remove ") then
		local statusPart = formula:gsub("^Remove ", ""):gsub("%.$", "")
		-- Normalise separators: ", and " → ", " then " and " → ", "
		statusPart = statusPart:gsub(", and ", ", "):gsub(" and ", ", ")
		local statuses = {}
		for s in statusPart:gmatch("[^,]+") do
			local trimmed = s:match("^%s*(.-)%s*$")
			if trimmed and trimmed ~= "" then
				table.insert(statuses, trimmed)
			end
		end
		for _, statusName in ipairs(statuses) do
			StatusService.RemoveStatus(target, statusName)
		end
		result.effectType = "StatusCure"
		result.statusId   = table.concat(statuses, ", ")
		return result
	end

	-- D) Direct Damage: "Deal [Element] damage equal to N% Weapon Attack Power"
	local element, dmgPct = formula:match("Deal (%a+) damage equal to (%d+)%%")
	if element and dmgPct then
		local pct = tonumber(dmgPct)
		local attackPower = user.weaponDamage or 10
		local damage = math.round(attackPower * pct / 100)
		UnitSchema.ApplyDamage(target, damage)
		result.effectType = "Damage"
		result.amount     = damage
		result.element    = element
		return result
	end

	-- E) Status Application: "Apply [status] for N turns"
	local statusName, turns = formula:match("Apply (.+) for (%d+) turns")
	if statusName and turns then
		StatusService.ApplyStatus(target, statusName, user.id)
		result.effectType = "StatusApply"
		result.statusId   = statusName
		result.amount     = tonumber(turns)
		return result
	end

	-- F) Unimplemented formula — log and skip
	print("[Item] Effect not yet implemented: " .. formula)
	result.effectType = "Unimplemented"
	return result
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
	-- Use rtMult if available, else legacy rtCost, else baseRt × 0.10
	local activationRt
	if skillDef.rtMult then
		activationRt = math.round(GameConstants.CalcEffectiveWt((unit.weaponWt or 10) + (unit.armorWt or 0), (unit.effectiveStats or {}).STR or 10) * skillDef.rtMult)
	else
		activationRt = skillDef.rtCost or math.round(
			StatusService.GetModifiedBaseRt(unit) * 0.10
		)
	end
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

	elseif skillDef.aoePattern and skillDef.aoePattern:sub(1,5) == "Chain" then
		-- Chain AOE: jump from target to target with damage falloff
		local maxTargets = tonumber(skillDef.aoePattern:match("%d+")) or 3
		local chainTargets = TargetingService.GetChainTargets(
			target, state.units, unit.side, maxTargets, 2
		)
		local totalDmg = 0
		local hitCount = 0
		local falloff = 1.0
		local falloffRate = skillDef.chainFalloff or 0.80
		local allOutcomes = {}
		for _, u in ipairs(chainTargets) do
			if u.isAlive then
				local outcome = CombatResolver.ResolveSkill(unit, u, skillDef)
				outcome.finalDamage = math.max(0, math.round(outcome.finalDamage * falloff))
				outcome.isAOE = true
				CombatResolver.ApplyOutcome(outcome, u, unit)
				totalDmg = totalDmg + outcome.finalDamage
				hitCount = hitCount + 1
				table.insert(allOutcomes, { target = u, outcome = outcome })
				falloff = falloff * falloffRate
			end
		end
		result.type      = "AOE"
		result.targets   = allOutcomes
		result.totalDmg  = totalDmg
		result.hitCount  = hitCount
		result.skillName = skillDef.name
		print(string.format(
			"[CommandService] Channel ACTIVATE [%s] Chain(%d/%d) | %s | Hits:%d | Dmg:%d | MP:%d",
			skillDef.name, hitCount, maxTargets, unit.name, hitCount, totalDmg, mpCost
		))

	elseif skillDef.aoePattern and skillDef.aoePattern ~= "Cleave" then
		-- Generic AOE: tile-based pattern resolution
		local aoeTiles = TargetingService.GetAOETargetTiles(
			skillDef.aoePattern, unit,
			target.tileX, target.tileY,
			_mapWidth, _mapHeight
		)
		local totalDmg = 0
		local hitCount = 0
		local allOutcomes = {}
		-- AOE elevation filter: ±2 from center tile (DB default)
		local centerElev = GameConstants.GetElevation(target.tileX, target.tileY)
		-- AOE is indiscriminate by default (DB: friendly fire rule)
		local targetRules = skillDef.targetRules or "Enemy Unit"
		local hitsAllies = targetRules == "Ally Unit, Enemy Unit, Self"
			or targetRules == "Ground, including occupied Ground"
			or (not targetRules:find("Ally") == nil and not targetRules:find("Enemy") == nil)
		for _, tile in ipairs(aoeTiles) do
			local tileElev = GameConstants.GetElevation(tile.tileX, tile.tileY)
			if math.abs(tileElev - centerElev) <= 2 then  -- ±2 elevation limit
			-- BlocksAOE: Center Spread AOE does not pass through BlocksAOE objects
			if not TargetingService.IsAOEBlocked(target.tileX, target.tileY, tile.tileX, tile.tileY) then
			  for _, u in ipairs(state.units) do
				if u.isAlive and u.tileX == tile.tileX and u.tileY == tile.tileY
					and u.id ~= unit.id then  -- never hit self unless targetRules includes Self
					-- Indiscriminate by default: hit both sides
					local outcome = CombatResolver.ResolveSkill(unit, u, skillDef)
					outcome.isAOE = true
					CombatResolver.ApplyOutcome(outcome, u, unit)
					totalDmg = totalDmg + outcome.finalDamage
					hitCount = hitCount + 1
					table.insert(allOutcomes, { target = u, outcome = outcome })
				end
				end
			  end
			end
			end
		result.type      = "AOE"
		result.targets   = allOutcomes
		result.totalDmg  = totalDmg
		result.hitCount  = hitCount
		result.skillName = skillDef.name
		print(string.format(
			"[CommandService] Channel ACTIVATE [%s] AOE(%s) | %s | Hits:%d | Dmg:%d | MP:%d",
			skillDef.name, skillDef.aoePattern, unit.name, hitCount, totalDmg, mpCost
		))

		-- Skill→tile effect bridge (channeling activation)
		if skillDef.createsTileEffect and _tileEffectService then
			local centerElev = GameConstants.GetElevation(target.tileX, target.tileY)
			for _, tile in ipairs(aoeTiles) do
				local tileElev = GameConstants.GetElevation(tile.tileX, tile.tileY)
				if math.abs(tileElev - centerElev) <= 2
					and not TargetingService.IsAOEBlocked(target.tileX, target.tileY, tile.tileX, tile.tileY) then
					_tileEffectService.ApplyTileEffect(
						tile.tileX, tile.tileY, skillDef.createsTileEffect, unit.id
					)
				end
			end
		end

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

	-- STEP 3b: Status-based action blocking (Phase 2)
	-- Silence → blocks Skills, Disarmed → blocks Attack, Pinned → blocks Move,
	-- Sleep/Petrify/KO → blocks All. Guard/Wait never blocked.
	local blocked, blockReason = StatusService.IsActionBlocked(actor, actionType)
	if blocked then
		return false, actor.name .. " cannot " .. actionType .. ": " .. blockReason
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


		local mpCost = skillDef.mpCost or 0
		mpCost = math.max(0, math.round(mpCost * RacePassiveService.GetMpCostModifier(actor)))
		mpCost = math.max(0, math.round(mpCost * DoctrinePassiveService.GetMpCostModifier(actor, actor._docFirstSkillUsed ~= true)))
		mpCost = math.max(0, math.round(mpCost * AugmentEffectService.GetMpCostMultiplier(actor, selection.skillId)))

		-- Mana Burn: Extra MP Cost = round(Max MP × 0.20)
		-- DB: "Extra MP Cost = round(Max MP × 0.20). Total MP Spent = Skill MP Cost + Extra."
		local manaBurnExtra = 0
		if StatusService.HasStatus(actor, "Mana Burn") then
			manaBurnExtra = math.round((actor.maxMp or 20) * 0.20)
			mpCost = mpCost + manaBurnExtra
		end

		if not UnitSchema.HasEnoughMp(actor, mpCost) then
			return false, string.format(
				"%s does not have enough MP (%d/%d needed).",
				actor.name, actor.currentMp, mpCost
			)
		end

		local targetSelection = {
			target      = selection.target,
			-- range = -1 means inherit from weapon
			skillRange  = (skillDef.range == -1)
				and (actor.weaponMaxRange or 1)
				or (skillDef.range or 1),
			targetRules = skillDef.targetRules or "Enemy Unit",
		}

		local valid, reason = TargetingService.ValidateSelection(
			actor, "Skill", targetSelection,
			state.units, _mapWidth, _mapHeight
		)
		if not valid then return false, reason end
	elseif actionType == "Item" then
		-- Item action: use a consumable from an equipped slot
		if type(selection) ~= "table" or not selection.itemSlotIndex then
			return false, "Item command requires a selection with itemSlotIndex."
		end

		local slotIndex = selection.itemSlotIndex
		local slots = actor.consumableSlots
		if not slots or not slots[slotIndex] then
			return false, "No consumable equipped in slot " .. tostring(slotIndex) .. "."
		end

		local slot = slots[slotIndex]
		if not slot.consumableId or slot.consumableId == "" then
			return false, "Consumable slot " .. tostring(slotIndex) .. " is empty."
		end

		local consumableDef = ConsumableData.Items[slot.consumableId]
		if not consumableDef then
			return false, "Unknown consumable: " .. tostring(slot.consumableId)
		end

		if (slot.currentCharges or 0) <= 0 then
			return false, consumableDef.name .. " has no charges remaining."
		end

		-- Validate target against the consumable's targetRules and range
		local target = selection.target
		local valid, reason = validateItemTarget(actor, target, consumableDef)
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

		-- Terrain cross effects: check destination terrain for cross penalties/effects
		local terrainData = GameConstants.GetTerrainData(actor.tileX, actor.tileY)
		if terrainData then
			-- Apply crossCost as extra RT (terrains like Sand +1, Swamp +2)
			-- Note: base moveCost is already handled by GetTerrainCost in pathfinding.
			-- crossCost is for future terrains not yet on the map.
			if terrainData.crossCost and terrainData.crossCost > 0 then
				local extraRt = math.round(terrainData.crossCost * StatusService.GetModifiedBaseRt(actor) * GameConstants.MOVE_RT_FACTOR)
				BattleCoordinator.AccrueRt(state, extraRt)
			end

			-- Terrain trigger on enter: Deep Water → Drowning, etc.
			if terrainData.triggerEffect == "Drowning" and StatusService then
				StatusService.ApplyStatus(actor, "Drowning", "terrain")
				print(string.format("[CommandService] Terrain trigger: %s enters %s → Drowning",
					actor.name, terrainData.id))
			end
		end

		-- Tile effect cross check (Burning, Poison Cloud, etc.)
		if _tileEffectService then
			_tileEffectService.OnUnitEntersTile(actor, actor.tileX, actor.tileY)
		end

	elseif actionType == "Attack" then
		local target = selection
		-- calcBasicAttackBaseRt already includes Effective Weapon WT
		local rtCost = calcBasicAttackBaseRt(actor)

		local weaponDamage = actor.weaponDamage or 10

		-- Weapon pattern AOE resolution
		local weaponPattern = actor.weaponPattern or "Single"
		local totalDmg = 0
		local hitCount = 0

		if weaponPattern == "ImpactSplash" then
			local splashTargets = TargetingService.GetImpactSplashTargets(actor, target, state.units)
			for _, entry in ipairs(splashTargets) do
				if entry.unit.isAlive then
					local outcome = CombatResolver.ResolveBasicAttack(actor, entry.unit, weaponDamage)
					outcome.finalDamage = math.max(0, math.round(outcome.finalDamage * entry.dmgMult))
					if entry.dmgMult < 1.0 then outcome.isAOE = true end
					CombatResolver.ApplyOutcome(outcome, entry.unit, actor)
					totalDmg = totalDmg + outcome.finalDamage
					hitCount = hitCount + 1
				end
			end
		elseif weaponPattern == "Line2" then
			local lineTargets = TargetingService.GetLine2Targets(actor, target, state.units)
			for _, entry in ipairs(lineTargets) do
				if entry.unit.isAlive then
					local outcome = CombatResolver.ResolveBasicAttack(actor, entry.unit, weaponDamage)
					CombatResolver.ApplyOutcome(outcome, entry.unit, actor)
					totalDmg = totalDmg + outcome.finalDamage
					hitCount = hitCount + 1
				end
			end
		elseif weaponPattern == "Cleave" then
			local cleaveTargets = TargetingService.GetCleaveTargets(actor, target, state.units)
			for _, u in ipairs(cleaveTargets) do
				if u.isAlive then
					local outcome = CombatResolver.ResolveBasicAttack(actor, u, weaponDamage)
					if u.id ~= target.id then
						outcome.finalDamage = math.max(0, math.round(outcome.finalDamage * 0.5))
						outcome.isAOE = true
					end
					CombatResolver.ApplyOutcome(outcome, u, actor)
					totalDmg = totalDmg + outcome.finalDamage
					hitCount = hitCount + 1
				end
			end
		elseif weaponPattern == "Adjacent" then
			-- Adjacent: primary + units on both sides of target (perpendicular), 50% splash
			local adjTargets = TargetingService.GetCleaveTargets(actor, target, state.units)
			for _, u in ipairs(adjTargets) do
				if u.isAlive then
					local outcome = CombatResolver.ResolveBasicAttack(actor, u, weaponDamage)
					if u.id ~= target.id then
						outcome.finalDamage = math.max(0, math.round(outcome.finalDamage * 0.5))
						outcome.isAOE = true
					end
					CombatResolver.ApplyOutcome(outcome, u, actor)
					totalDmg = totalDmg + outcome.finalDamage
					hitCount = hitCount + 1
				end
			end
		else
			-- Single-target (default)
			local outcome = CombatResolver.ResolveBasicAttack(actor, target, weaponDamage)
			CombatResolver.ApplyOutcome(outcome, target, actor)
			totalDmg = outcome.finalDamage
			hitCount = 1
		end

		BattleCoordinator.AccrueRt(state, rtCost)

		-- Apply Weapon RT Delay to primary target (reduced by target VIT)
		local rawDelay = actor.weaponRtDelay or 0
		if rawDelay > 0 and target.isAlive then
			local targetVit = target.effectiveStats and target.effectiveStats.VIT or 10
			local actualDelay = GameConstants.CalcRtDelayResistance(rawDelay, targetVit)
			target.remainingRt = target.remainingRt + math.max(0, actualDelay)
		end

		-- Giant race tag: melee Basic Attacks gain Knockback (primary target only)
		if target.isAlive and actor.raceId then
			local RaceData = require(game:GetService("ReplicatedStorage"):WaitForChild("Content"):WaitForChild("RaceData"))
			local raceEntry = RaceData[actor.raceId]
			if raceEntry and raceEntry.tags then
				for _, tag in ipairs(raceEntry.tags) do
					if tag == "Giant" then
						local force = actor.derivedStats and actor.derivedStats.force or 1
						local stability = target.derivedStats and target.derivedStats.stability or 0
						local pushDist = math.max(0, force - stability)
						if pushDist > 0 then
							local direction = DisplacementService.GetPushDirection(actor, target)
							DisplacementService.ResolvePush(
								target, direction, pushDist, actor, state,
								GameConstants.KNOCKBACK_SOURCE_MODIFIERS.Skill
							)
						end
						break
					end
				end
			end
		end

		print(string.format(
			"[CommandService] ATTACK %s | %s -> %s | Dmg:%d Hits:%d | RT:%d | AP left:%d",
			weaponPattern ~= "Single" and ("["..weaponPattern.."]") or "",
			actor.name, target.name,
			totalDmg, hitCount, rtCost, actor.currentAp
		))

	elseif actionType == "Skill" then
		local target = selection.target
		local mpCost = skillDef.mpCost or 0
		mpCost = math.max(0, math.round(mpCost * RacePassiveService.GetMpCostModifier(actor)))
		mpCost = math.max(0, math.round(mpCost * DoctrinePassiveService.GetMpCostModifier(actor, actor._docFirstSkillUsed ~= true)))

		-- Mana Burn: Extra MP Cost (same as validation path)
		local manaBurnExtra = 0
		if StatusService.HasStatus(actor, "Mana Burn") then
			manaBurnExtra = math.round((actor.maxMp or 20) * 0.20)
			mpCost = mpCost + manaBurnExtra
		end

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

		-- Mana Burn damage: round(Total MP Spent × 0.50 × Debuff Resistance)
		if manaBurnExtra > 0 and actor.isAlive then
			local debuffResist = actor.derivedStats and actor.derivedStats.debuffResist or 1.0
			local manaBurnDmg = math.round(mpCost * 0.50 * debuffResist)
			if manaBurnDmg > 0 then
				UnitSchema.ApplyDamage(actor, manaBurnDmg)
				print(string.format("[CommandService] Mana Burn: %s takes %d damage (MP spent: %d)",
					actor.name, manaBurnDmg, mpCost))
			end
		end

		-- Skill RT cost: rtMult × Effective Weapon WT (from DB formula)
		-- Fallback: rtCost (legacy) or baseRt × 0.10
		local baseRtCost
		if skillDef.rtMult then
			baseRtCost = math.round(GameConstants.CalcEffectiveWt((actor.weaponWt or 10) + (actor.armorWt or 0), (actor.effectiveStats or {}).STR or 10) * skillDef.rtMult)
		else
			baseRtCost = skillDef.rtCost or math.round(StatusService.GetModifiedBaseRt(actor) * 0.10)
		end
		-- Frozen: all RT costs ×2
		baseRtCost = math.round(baseRtCost * StatusService.GetAllRtMultiplier(actor))

		if skillDef.isHealing then
			local outcome = CombatResolver.ResolveHealing(actor, target, skillDef)
			CombatResolver.ApplyOutcome(outcome, target, actor)
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
					CombatResolver.ApplyOutcome(outcome, t, actor)
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

		elseif skillDef.aoePattern and skillDef.aoePattern:sub(1,5) == "Chain" then
			-- Chain AOE: jump from target to target with damage falloff
			local maxTargets = tonumber(skillDef.aoePattern:match("%d+")) or 3
			local chainTargets = TargetingService.GetChainTargets(
				target, state.units, actor.side, maxTargets, 2
			)
			local totalDmg = 0
			local hitCount = 0
			local falloff = 1.0
			local falloffRate = skillDef.chainFalloff or 0.80
			for idx, u in ipairs(chainTargets) do
				if u.isAlive then
					local outcome = CombatResolver.ResolveSkill(actor, u, skillDef)
					-- Apply chain falloff
					outcome.finalDamage = math.max(0, math.round(outcome.finalDamage * falloff))
					outcome.isAOE = true
					CombatResolver.ApplyOutcome(outcome, u, actor)
					totalDmg = totalDmg + outcome.finalDamage
					hitCount = hitCount + 1
					falloff = falloff * falloffRate
				end
			end
			BattleCoordinator.AccrueRt(state, baseRtCost)

			print(string.format(
				"[CommandService] SKILL [%s] Chain(%d/%d) | %s | Hits:%d | TotalDmg:%d | MP:%d | RT:%d | AP left:%d",
				skillDef.name or skillDef.id, hitCount, maxTargets,
				actor.name, hitCount, totalDmg, mpCost, baseRtCost, actor.currentAp
			))

		elseif skillDef.aoePattern and skillDef.aoePattern ~= "Cleave" and skillDef.aoePattern ~= "InheritWeapon" then
			-- Generic AOE: tile-based pattern resolution
			local aoeTiles = TargetingService.GetAOETargetTiles(
				skillDef.aoePattern, actor,
				target.tileX, target.tileY,
				_mapWidth, _mapHeight
			)
			local totalDmg = 0
			local hitCount = 0
			-- AOE elevation filter: ±2 from center tile (DB default)
			local centerElev = GameConstants.GetElevation(target.tileX, target.tileY)
			for _, tile in ipairs(aoeTiles) do
				local tileElev = GameConstants.GetElevation(tile.tileX, tile.tileY)
				if math.abs(tileElev - centerElev) <= 2 then
				-- BlocksAOE: Center Spread AOE does not pass through BlocksAOE
				if not TargetingService.IsAOEBlocked(target.tileX, target.tileY, tile.tileX, tile.tileY) then
				for _, u in ipairs(state.units) do
					if u.isAlive and u.tileX == tile.tileX and u.tileY == tile.tileY
						and u.id ~= actor.id then
						local outcome = CombatResolver.ResolveSkill(actor, u, skillDef)
						outcome.isAOE = true
						CombatResolver.ApplyOutcome(outcome, u, actor)
						totalDmg = totalDmg + outcome.finalDamage
						hitCount = hitCount + 1
					end
				end
				end
			end
			end  -- tile loop (for aoeTiles)
			BattleCoordinator.AccrueRt(state, baseRtCost)

			print(string.format(
				"[CommandService] SKILL [%s] AOE(%s) | %s | Hits:%d | TotalDmg:%d | MP:%d | RT:%d | AP left:%d",
				skillDef.name or skillDef.id, skillDef.aoePattern,
				actor.name, hitCount, totalDmg, mpCost, baseRtCost, actor.currentAp
			))

			-- Skill→tile effect bridge: create tile effects on AOE tiles
			if skillDef.createsTileEffect and _tileEffectService then
				for _, tile in ipairs(aoeTiles) do
					local tileElev = GameConstants.GetElevation(tile.tileX, tile.tileY)
					if math.abs(tileElev - centerElev) <= 2
						and not TargetingService.IsAOEBlocked(target.tileX, target.tileY, tile.tileX, tile.tileY) then
						_tileEffectService.ApplyTileEffect(
							tile.tileX, tile.tileY, skillDef.createsTileEffect, actor.id
						)
					end
				end
			end

		else
			-- Check for "Inherit Weapon Pattern" skills
			local inheritedPattern = nil
			if skillDef.aoePattern == "InheritWeapon" then
				inheritedPattern = actor.weaponPattern or "Single"
			end

			if inheritedPattern and inheritedPattern ~= "Single" then
				-- Weapon pattern AOE via inherited skill
				local totalDmg = 0
				local hitCount = 0
				local aoeTargets

				if inheritedPattern == "ImpactSplash" then
					aoeTargets = TargetingService.GetImpactSplashTargets(actor, target, state.units)
				elseif inheritedPattern == "Line2" then
					aoeTargets = TargetingService.GetLine2Targets(actor, target, state.units)
				elseif inheritedPattern == "Cleave" then
					-- Re-use Cleave with 50% secondary
					local cleaveUnits = TargetingService.GetCleaveTargets(actor, target, state.units)
					aoeTargets = {}
					for _, u in ipairs(cleaveUnits) do
						local mult = (u.id == target.id) and 1.0 or 0.5
						table.insert(aoeTargets, { unit = u, dmgMult = mult })
					end
				elseif inheritedPattern == "Adjacent" then
					local adjUnits = TargetingService.GetCleaveTargets(actor, target, state.units)
					aoeTargets = {}
					for _, u in ipairs(adjUnits) do
						local mult = (u.id == target.id) and 1.0 or 0.5
						table.insert(aoeTargets, { unit = u, dmgMult = mult })
					end
				end

				if aoeTargets then
					for _, entry in ipairs(aoeTargets) do
						if entry.unit.isAlive then
							local outcome = CombatResolver.ResolveSkill(actor, entry.unit, skillDef)
							outcome.finalDamage = math.max(0, math.round(outcome.finalDamage * entry.dmgMult))
							if entry.dmgMult < 1.0 then outcome.isAOE = true end
							CombatResolver.ApplyOutcome(outcome, entry.unit, actor)
							totalDmg = totalDmg + outcome.finalDamage
							hitCount = hitCount + 1
						end
					end
				end
				BattleCoordinator.AccrueRt(state, baseRtCost)

				print(string.format(
					"[CommandService] SKILL [%s] Inherit[%s] | %s | Hits:%d | TotalDmg:%d | MP:%d | RT:%d | AP left:%d",
					skillDef.name or skillDef.id, inheritedPattern,
					actor.name, hitCount, totalDmg, mpCost, baseRtCost, actor.currentAp
				))

			else
			-- Single-target (default)
			local outcome = CombatResolver.ResolveSkill(actor, target, skillDef)
			local actualDmg, statusApplied = CombatResolver.ApplyOutcome(outcome, target, actor)
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
		-- Frozen: all RT costs ×2
		guardRt = math.round(guardRt * StatusService.GetAllRtMultiplier(actor))

		-- Apply Guard as a proper status (dispellable buff, removed by CC)
		StatusService.ApplyStatus(actor, "Guard", actor.id)
		actor.guardBonus = RacePassiveService.GetGuardMitigationBonus(actor)
		local armorGuardBonus = ArmorPassiveService.GetGuardMitigationBonus(actor)
		actor.guardUsedThisTurn = true
		BattleCoordinator.AccrueRt(state, guardRt)

		print(string.format(
			"[CommandService] GUARD | %s | RT:%d | OffHandWT:%d | AP left:%d",
			actor.name, guardRt, offHandWt, actor.currentAp
		))

		-- Calculate effective mitigation for display
		local mitigation = GameConstants.GUARD_MITIGATION + (actor.guardBonus or 0) + armorGuardBonus
		mitigation = math.min(mitigation, GameConstants.GUARD_CAP)
		BattleVisualBroadcaster.GuardActivated(actor, guardRt, mitigation)

	elseif actionType == "Push" then
		-- Push: 1 AP, push adjacent enemy away (Android: Pull with extended range)
		-- selection = target unit
		local target = selection
		if not target or not target.isAlive then
			return false, "Push target is invalid or defeated."
		end

		-- Android override: Pull with extended range, cannot target adjacent
		local pushOverride = RacePassiveService.GetPushOverride(actor)
		local maxPushDist = pushOverride and pushOverride.maxDistance or 1
		local minPushDist = pushOverride and pushOverride.minDistance or 1

		local dist = math.max(
			math.abs(actor.tileX - target.tileX),
			math.abs(actor.tileY - target.tileY)
		)
		if dist > maxPushDist then
			return false, "Target is out of range."
		end
		if dist < minPushDist then
			return false, "Target is too close."
		end

		-- Push RT = round(Modified Base RT × 0.10)
		local modBaseRt = StatusService.GetModifiedBaseRt(actor)
		local pushRt = math.round(modBaseRt * GameConstants.GUARD_RT_BASE_FACTOR)
		-- Frozen: all RT costs ×2
		pushRt = math.round(pushRt * StatusService.GetAllRtMultiplier(actor))
		BattleCoordinator.AccrueRt(state, pushRt)

		-- Resolve displacement
		local force = 1
		if actor.derivedStats and actor.derivedStats.force then
			force = actor.derivedStats.force
		end
		if pushOverride and pushOverride.forceBonus then
			force = force + pushOverride.forceBonus
		end
		local direction = DisplacementService.GetPushDirection(actor, target)
		if pushOverride and pushOverride.reverseDirection then
			direction = { x = -direction.x, y = -direction.y }
		end
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

		-- Apply collision damage to the collided unit (both units absorb the impact)
		if result.wallCollision
			and result.wallCollision.collidedUnitId
			and result.wallCollision.collidedUnitDamage
			and result.wallCollision.collidedUnitDamage > 0
		then
			for _, u in ipairs(state.units) do
				if u.id == result.wallCollision.collidedUnitId and u.isAlive then
					UnitSchema.ApplyDamage(u, result.wallCollision.collidedUnitDamage)
					print(string.format(
						"[CommandService] COLLISION | %s also takes %d damage from impact",
						u.name, result.wallCollision.collidedUnitDamage
					))
					break
				end
			end
		end

		-- Broadcast
		BattleVisualBroadcaster.UnitPushed(actor, target, result)

		local actionLabel = pushOverride and pushOverride.label or "PUSH"
		print(string.format(
			"[CommandService] %s | %s -> %s | Force:%d | Moved:%d to (%d,%d) | Dmg:%d | RT:%d | AP left:%d",
			actionLabel, actor.name, target.name, force,
			result.tilesDisplaced, result.finalTileX, result.finalTileY,
			totalPushDmg, pushRt, actor.currentAp
		))

	elseif actionType == "Item" then
		-- ITEM ACTION: use a consumable from the unit's equipped slot.
		-- Validation already confirmed slot, charges, target, and range.
		local slotIndex    = selection.itemSlotIndex
		local target       = selection.target
		local slot         = actor.consumableSlots[slotIndex]
		local consumableDef = ConsumableData.Items[slot.consumableId]

		-- Deduct 1 charge (item stays equipped at 0 charges but is unusable)
		slot.currentCharges = slot.currentCharges - 1

		-- RT cost comes from the consumable definition (fixed, not weapon-scaled)
		local rtCost = consumableDef.rtCost or 80
		-- Frozen: all RT costs ×2
		rtCost = math.round(rtCost * StatusService.GetAllRtMultiplier(actor))
		BattleCoordinator.AccrueRt(state, rtCost)

		-- Resolve the consumable's effect
		local effectResult = resolveItemEffect(actor, target, consumableDef, state.units)

		-- Broadcast via existing UnitActed event (client sees actionType = "Item")
		-- NOTE: BattleVisualBroadcaster.UnitActed currently infers actionType from
		-- skillName presence. A dedicated "ItemUsed" broadcast method should be added
		-- to BVB in a future update for proper client-side item animations.
		if BattleVisualBroadcaster.UnitActed then
			BattleVisualBroadcaster.UnitActed(actor, target, {
				finalDamage    = effectResult.amount or 0,
				statusApplied  = effectResult.statusId,
			}, consumableDef.name)
		end

		print(string.format(
			"[CommandService] ITEM [%s] | %s -> %s | Effect:%s | Amount:%d | RT:%d | Charges:%d/%d | AP left:%d",
			consumableDef.name,
			actor.name,
			target and target.name or "ground",
			effectResult.effectType,
			effectResult.amount or 0,
			rtCost,
			slot.currentCharges,
			slot.maxCharges or consumableDef.maxCharges or 0,
			actor.currentAp
		))

	end  -- end if/elseif action chain

	-- STEP 9: Handoff
	if actor.currentAp <= 0 then
		BattleCoordinator.EndTurn(state)
	end

	return true, nil
end

return CommandService
