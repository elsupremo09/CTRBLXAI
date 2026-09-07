-- CombatResolver.lua
-- CTRBLXAI | Slice 3 (AOE, Healing, Burn/Poison generation)
--
-- Calculates the numerical result of an attack or skill hit.
-- Returns an outcome table — does NOT write to unit state directly.
--
-- Slice 3 additions:
--   - ResolveHealing: calculates healing amount
--   - Burn status application uses actual fire damage dealt
--   - AOE outcomes return multiple results

local StatusService = require(script.Parent.StatusService)
local RacePassiveService = require(script.Parent.RacePassiveService)
local DoctrinePassiveService = require(script.Parent.DoctrinePassiveService)
local ArmorPassiveService = require(script.Parent.ArmorPassiveService)
local BattleVisualBroadcaster = require(script.Parent.BattleVisualBroadcaster)

local RaceData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("RaceData")
)

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

local CombatResolver = {}

--------------------------------------------------
-- INTERNAL FORMULA HELPERS
--------------------------------------------------

-- Known element tags. Anything in this set found in a skill's .tags array
-- is treated as the skill's element. First match wins.
local ELEMENT_SET = {
	Physical = true, Fire = true, Water = true, Ice = true,
	Poison = true, Dark = true, Holy = true, Electric = true,
}

local function extractElement(tags)
	if not tags then return "Physical" end
	for _, tag in ipairs(tags) do
		if ELEMENT_SET[tag] then return tag end
	end
	return "Physical"
end

-- Returns true if unit has the Undead race tag
local function isUndead(unit)
	if not unit.raceId then return false end
	local raceEntry = RaceData[unit.raceId]
	if raceEntry and raceEntry.tags then
		for _, tag in ipairs(raceEntry.tags) do
			if tag == "Undead" then return true end
		end
	end
	return false
end

--------------------------------------------------
-- ELEMENT DAMAGE INTERACTIONS (Phase 3)
--
-- Modifies finalDamage based on element vs defender status.
-- Returns: modifiedDamage, removedStatuses (table of IDs)
--
-- Rules from DB (elements_statuses):
--   Fire vs Wet/Frozen    → damage ×0.50, removes Wet/Frozen
--   Physical vs Frozen    → damage ×1.50
--   Water vs Frozen       → damage ×1.50
--   Water vs Burn         → removes Burn, Water damage ×0.50
--   Holy vs Undead        → damage ×2.0
--   Dark vs Undead        → heals instead (handled separately)
--------------------------------------------------

local function applyElementInteractions(defender, element, finalDamage)
	local removed = {}

	local hasWet    = StatusService.HasStatus(defender, "Wet")
	local hasFrozen = StatusService.HasStatus(defender, "Frozen")
	local hasBurn   = StatusService.HasStatus(defender, "Burn")
	local undead    = isUndead(defender)

	if element == "Fire" then
		-- Fire vs Wet: halved, removes Wet
		if hasWet then
			finalDamage = math.max(0, math.round(finalDamage * 0.50))
			StatusService.RemoveStatus(defender, "Wet")
			table.insert(removed, "Wet")
		end
		-- Fire vs Frozen: halved, removes Frozen
		if hasFrozen then
			finalDamage = math.max(0, math.round(finalDamage * 0.50))
			StatusService.RemoveStatus(defender, "Frozen")
			table.insert(removed, "Frozen")
		end

	elseif element == "Physical" then
		-- Physical vs Frozen: ×1.50
		if hasFrozen then
			finalDamage = math.max(0, math.round(finalDamage * 1.50))
		end

	elseif element == "Water" then
		-- Water vs Frozen: ×1.50
		if hasFrozen then
			finalDamage = math.max(0, math.round(finalDamage * 1.50))
		end
		-- Water vs Burn: removes Burn, Water damage halved
		if hasBurn then
			finalDamage = math.max(0, math.round(finalDamage * 0.50))
			StatusService.RemoveStatus(defender, "Burn")
			table.insert(removed, "Burn")
		end

	elseif element == "Holy" then
		-- Holy vs Undead: ×2.0
		if undead then
			finalDamage = math.max(0, math.round(finalDamage * 2.0))
		end
	end

	-- Electric: no interactions yet (DB: "Future interactions not finalized")

	return finalDamage, removed
end

-- Element→status triggers. Applied after damage resolves.
-- Skips if the skill already applied the same status via appliesStatus.
-- Broadcasts StatusImmune if the status was blocked by immunity.
local function applyElementStatusTriggers(sourceUnitId, defender, element, actualDamage, alreadyApplied, attackerUnit)
	if actualDamage <= 0 or not defender.isAlive then return end

	local function tryApply(statusId, fireDmg)
		local applied, _, immuneReason = StatusService.ApplyStatus(defender, statusId, sourceUnitId, fireDmg)
		if not applied and immuneReason then
			BattleVisualBroadcaster.StatusImmune(defender, statusId, immuneReason)
		end
	end

	-- LICH — Arcane Corruption: override element→status mapping
	-- DB: Fire→Burn, Water→Frozen, Earth→Petrify, Dark→Poison
	if attackerUnit then
		local override = RacePassiveService.GetElementStatusOverride(attackerUnit, element)
		if override and override ~= alreadyApplied then
			local fireDmg = (element == "Fire") and actualDamage or nil
			tryApply(override, fireDmg)
			print(string.format("[CombatResolver] Lich Arcane Corruption: %s → %s", element, override))
			return   -- skip default triggers
		end
	end

	if element == "Fire" and alreadyApplied ~= "Burn" then
		tryApply("Burn", actualDamage)
	elseif element == "Water" then
		tryApply("Wet")
	elseif element == "Ice" then
		-- Ice on Wet target → convert Wet to Frozen
		if StatusService.HasStatus(defender, "Wet") then
			StatusService.RemoveStatus(defender, "Wet")
			tryApply("Frozen")
		end
	elseif element == "Poison" and alreadyApplied ~= "Poison" then
		tryApply("Poison")
	end
end

local function calcHitQuality(attackerDex, defenderAgi, attackerUnit)
	local precision   = GameConstants.CalcPrecision(attackerDex)
	local evasiveness = GameConstants.CalcEvasiveness(defenderAgi)
	-- Blind: Final Precision = Precision × 0.50 (DB: elements_statuses)
	if attackerUnit and StatusService.HasStatus(attackerUnit, "Blind") then
		precision = precision * 0.50
	end
	return 1 + (precision - evasiveness)
end

local function calcEffectiveDefense(attackPower, defensePower)
	if attackPower <= 0 then return 0 end
	if defensePower <= 0 then return 0 end
	return (attackPower * defensePower) / (attackPower + defensePower)
end

--------------------------------------------------
-- PUBLIC: RESOLVE BASIC ATTACK
--------------------------------------------------

function CombatResolver.ResolveBasicAttack(attacker, defender, weaponDamage)
	assert(
		type(attacker) == "table" and type(defender) == "table",
		"ResolveBasicAttack: attacker and defender must be unit tables."
	)

	local aStats = attacker.effectiveStats
	local dStats = defender.effectiveStats

	local ap = GameConstants.CalcAttackPower(weaponDamage, aStats.STR)
	local dp = GameConstants.CalcDefensePower(0, dStats.VIT)
	local effectiveDefense = calcEffectiveDefense(ap, dp)
	local hitQuality = calcHitQuality(aStats.DEX, dStats.AGI, attacker)

	local positionalMod = GameConstants.GetPositionalModifier(
		attacker.tileX, attacker.tileY,
		defender.tileX, defender.tileY
	)

	local rawDamage   = ap - effectiveDefense
	-- Combat Fortune: LUK difference modifies damage (step 7 in pipeline)
	local fortuneMod = GameConstants.CalcCombatFortune(aStats.LUK, dStats.LUK)

	local finalDamage = math.max(0, math.round(rawDamage * hitQuality * positionalMod * fortuneMod))

	-- Race passive modifiers (Slice 4F)
	-- Basic Attack: element=nil, isAOE=false, isPhysical=true
	local raceDealtMod = RacePassiveService.GetDamageDealtModifier(attacker, nil, false)
	local raceRecvMod  = RacePassiveService.GetDamageReceivedModifier(defender, nil, false, true)
	-- Doctrine passive modifiers (Slice 4H)
	local docBADmgMod = DoctrinePassiveService.GetBasicAttackDamageModifier(attacker)
	local docDealtMod = DoctrinePassiveService.GetDamageDealtModifier(attacker, defender, nil, false, true, nil)
	local docRecvMod  = DoctrinePassiveService.GetDamageReceivedModifier(defender, attacker, nil, false)
	finalDamage = math.max(0, math.round(finalDamage * raceDealtMod * raceRecvMod * docBADmgMod * docDealtMod * docRecvMod))

	-- Step 8: Guard and other final mitigation
	-- Check Guard via status instances (Guard is now a proper status)
	local hasGuard = false
	if defender.statusInstances then
		for _, inst in ipairs(defender.statusInstances) do
			if inst.id == "Guard" then hasGuard = true; break end
		end
	end
	if hasGuard then
		local mitigation = GameConstants.GUARD_MITIGATION + (defender.guardBonus or 0)
		mitigation = math.min(mitigation, GameConstants.GUARD_CAP)
		finalDamage = math.max(0, math.round(finalDamage * (1 - mitigation)))
	end

	-- Step 9: Petrify damage reduction
	-- Petrify: normal damage ×0.70, HP%-based damage ×0.25
	if StatusService.HasStatus(defender, "Petrify") then
		finalDamage = math.max(0, math.round(finalDamage * 0.70))
		print(string.format(
			"[CombatResolver] Petrify reduces damage to %d (×0.70)", finalDamage
		))
	end

	-- Step 10: Element interactions (Phase 3)
	-- Basic Attack element = weapon element or Physical
	local attackElement = attacker.weaponElement or "Physical"

	-- Step 6b: Terrain occupy bonus — attacker's tile element bonus
	-- Flight bypasses terrain bonuses
	if not StatusService.HasStatus(attacker, "Flight") then
		local terrainBonus = GameConstants.GetTerrainOccupyBonus(
			GameConstants.GetTerrainId(attacker.tileX, attacker.tileY),
			attackElement
		)
		if terrainBonus ~= 1 then
			print(string.format("[CombatResolver] Terrain occupy bonus: %s ×%.2f",
				GameConstants.GetTerrainId(attacker.tileX, attacker.tileY), terrainBonus))
			finalDamage = math.max(0, math.round(finalDamage * terrainBonus))
		end
	end

	-- Dark vs Undead: convert damage to healing
	if attackElement == "Dark" and isUndead(defender) then
		return {
			type         = "Healing",
			targetId     = defender.id,
			finalHealing = finalDamage,
			sourceUnitId = attacker.id,
			element      = attackElement,
		}
	end

	finalDamage = applyElementInteractions(defender, attackElement, finalDamage)

	return {
		type           = "Damage",
		targetId       = defender.id,
		attackPower    = ap,
		defensePower   = dp,
		rawDamage      = rawDamage,
		hitQuality     = hitQuality,
		positionalMod  = positionalMod,
		finalDamage    = finalDamage,
		appliesStatus  = RacePassiveService.GetBasicAttackStatus(attacker),
		element        = attackElement,
		sourceUnitId   = attacker.id,
	}
end

--------------------------------------------------
-- PUBLIC: RESOLVE SKILL (damage skill, single target)
--------------------------------------------------

function CombatResolver.ResolveSkill(attacker, defender, skillDef)
	assert(
		type(attacker) == "table" and type(defender) == "table",
		"ResolveSkill: attacker and defender must be unit tables."
	)

	local aStats = attacker.effectiveStats
	local dStats = defender.effectiveStats

	-- Skill Power = Weapon Attack Power × power multiplier
	local weaponDamage = attacker.weaponDamage or 10
	local sp = weaponDamage * (skillDef.power or 1.0)
	if skillDef.inheritStr then
		sp = GameConstants.CalcAttackPower(sp, aStats.STR)
	end

	local dp = GameConstants.CalcDefensePower(0, dStats.VIT)
	local effectiveDefense = calcEffectiveDefense(sp, dp)
	local hitQuality = calcHitQuality(aStats.DEX, dStats.AGI, attacker)

	local positionalMod = GameConstants.GetPositionalModifier(
		attacker.tileX, attacker.tileY,
		defender.tileX, defender.tileY
	)

	local rawDamage   = sp - effectiveDefense
	-- Combat Fortune: LUK difference modifies damage (step 7 in pipeline)
	local fortuneMod = GameConstants.CalcCombatFortune(aStats.LUK, dStats.LUK)

	local finalDamage = math.max(0, math.round(rawDamage * hitQuality * positionalMod * fortuneMod))

	-- Race passive modifiers (Slice 4F)
	-- Extract element from skill tags (Phase 3)
	local skillElement = extractElement(skillDef.tags)
	local skillIsAOE = skillDef.aoePattern ~= nil and skillDef.aoePattern ~= "Single"
	local skillIsPhysical = (skillElement == nil or skillElement == "Physical" or skillElement == "")
	local raceDealtMod = RacePassiveService.GetDamageDealtModifier(attacker, skillElement, skillIsAOE)
	local raceRecvMod  = RacePassiveService.GetDamageReceivedModifier(defender, skillElement, skillIsAOE, skillIsPhysical)
	-- Doctrine passive modifiers (Slice 4H)
	local docSkillPotency = DoctrinePassiveService.GetSkillPotencyModifier(attacker)
	local docDealtMod = DoctrinePassiveService.GetDamageDealtModifier(attacker, defender, skillElement, true, false, nil)
	local docRecvMod  = DoctrinePassiveService.GetDamageReceivedModifier(defender, attacker, skillElement, true)
	finalDamage = math.max(0, math.round(finalDamage * raceDealtMod * raceRecvMod * docSkillPotency * docDealtMod * docRecvMod))

	-- Step 8: Guard and other final mitigation
	local hasGuardSkill = false
	if defender.statusInstances then
		for _, inst in ipairs(defender.statusInstances) do
			if inst.id == "Guard" then hasGuardSkill = true; break end
		end
	end
	if hasGuardSkill then
		local mitigation = GameConstants.GUARD_MITIGATION + (defender.guardBonus or 0)
		mitigation = math.min(mitigation, GameConstants.GUARD_CAP)
		finalDamage = math.max(0, math.round(finalDamage * (1 - mitigation)))
	end

	-- Step 9: Petrify damage reduction
	if StatusService.HasStatus(defender, "Petrify") then
		finalDamage = math.max(0, math.round(finalDamage * 0.70))
		print(string.format(
			"[CombatResolver] Petrify reduces skill damage to %d (×0.70)", finalDamage
		))
	end

	-- Step 10: Element interactions (Phase 3)

	-- Step 6b: Terrain occupy bonus — attacker's tile element bonus
	-- Flight bypasses terrain bonuses
	if not StatusService.HasStatus(attacker, "Flight") then
		local terrainBonusSkill = GameConstants.GetTerrainOccupyBonus(
			GameConstants.GetTerrainId(attacker.tileX, attacker.tileY),
			skillElement or "Physical"
		)
		if terrainBonusSkill ~= 1 then
			print(string.format("[CombatResolver] Terrain occupy bonus (skill): %s ×%.2f",
				GameConstants.GetTerrainId(attacker.tileX, attacker.tileY), terrainBonusSkill))
			finalDamage = math.max(0, math.round(finalDamage * terrainBonusSkill))
		end
	end

	-- Dark vs Undead: convert damage to healing
	if skillElement == "Dark" and isUndead(defender) then
		return {
			type         = "Healing",
			targetId     = defender.id,
			finalHealing = finalDamage,
			sourceUnitId = attacker.id,
			element      = skillElement,
		}
	end

	finalDamage = applyElementInteractions(defender, skillElement, finalDamage)

	return {
		type           = "Damage",
		targetId       = defender.id,
		attackPower    = sp,
		defensePower   = dp,
		rawDamage      = rawDamage,
		hitQuality     = hitQuality,
		positionalMod  = positionalMod,
		finalDamage    = finalDamage,
		appliesStatus  = skillDef.appliesStatus or nil,
		element        = skillElement,
		sourceUnitId   = attacker.id,
	}
end

--------------------------------------------------
-- PUBLIC: RESOLVE HEALING (Slice 3)
--
-- Healing Light formula (simplified for L=1):
--   HealAmount = round((10 + 0.35×INT + WeaponDamage×0.30) × SkillPotency)
--   SkillPotency = 1 + INT / (200 + INT)
--------------------------------------------------

function CombatResolver.ResolveHealing(caster, target, skillDef)
	assert(
		type(caster) == "table" and type(target) == "table",
		"ResolveHealing: caster and target must be unit tables."
	)

	local cStats = caster.effectiveStats
	local int = cStats.INT or 10
	local weaponDamage = caster.weaponDamage or 10

	-- Skill Potency Multiplier = 1 + INT / (200 + INT)
	local skillPotency = GameConstants.CalcSkillPotency(int)

	-- Healing formula (base)
	local baseHeal = 10 + 0.35 * int + weaponDamage * 0.30

	-- Healing Efficiency: target's VIT increases received healing
	local targetVit = target.effectiveStats and target.effectiveStats.VIT or 10
	local healEfficiency = GameConstants.CalcHealEfficiency(targetVit)
	local finalHeal = math.max(1, math.round(baseHeal * skillPotency * healEfficiency))

	-- Phase 3: Undead healing reversal
	-- Non-Dark healing vs Undead → converted to damage
	local healElement = extractElement(skillDef.tags)
	if isUndead(target) and healElement ~= "Dark" then
		print(string.format(
			"[CombatResolver] Undead healing reversal: %s receives %d damage instead of healing",
			target.name, finalHeal
		))
		return {
			type         = "Damage",
			targetId     = target.id,
			finalDamage  = finalHeal,
			attackPower  = 0,
			defensePower = 0,
			rawDamage    = finalHeal,
			hitQuality   = 1.0,
			positionalMod = 1.0,
			appliesStatus = nil,
			element      = healElement,
			sourceUnitId = caster.id,
		}
	end

	return {
		type         = "Healing",
		targetId     = target.id,
		finalHealing = finalHeal,
		sourceUnitId = caster.id,
	}
end

--------------------------------------------------
-- PUBLIC: APPLY OUTCOME (damage or healing)
-- attacker (optional): unit table of the source, used for Confuse backlash.
-- Callers that have the attacker unit should pass it.
--------------------------------------------------

function CombatResolver.ApplyOutcome(outcome, target, attacker)
	if outcome.type == "Healing" then
		local actual = UnitSchema_ApplyHealing(outcome.finalHealing, target)
		print(string.format(
			"[CombatResolver] %s healed for %d | HP: %d/%d",
			target.name, actual, target.currentHp, target.maxHp
		))
		return actual, nil
	end

	-- Damage outcome
	assert(outcome.type == "Damage", "ApplyOutcome: unsupported outcome type.")

	local actual = UnitSchema_ApplyDamage(outcome.finalDamage, target)

	-- Track who dealt the killing blow (for unit records)
	if not target.isAlive and attacker then
		target._killedBy = attacker.id
	end

	-- Phase 2: Check for damage-triggered status removal (e.g. Sleep)
	StatusService.OnDamageReceived(target, actual)

	local statusApplied = nil
	if outcome.appliesStatus and actual > 0 and target.isAlive then
		-- For Burn, pass the actual fire damage dealt
		local fireDmg = nil
		if outcome.appliesStatus == "Burn" then
			fireDmg = actual
		end
		local applied, _, immuneReason = StatusService.ApplyStatus(
			target,
			outcome.appliesStatus,
			outcome.sourceUnitId or "unknown",
			fireDmg
		)
		if applied then
			statusApplied = outcome.appliesStatus
		elseif not applied and immuneReason then
			BattleVisualBroadcaster.StatusImmune(target, outcome.appliesStatus, immuneReason)
		end
	end

	-- Phase 3: Element→status triggers (Fire→Burn, Water→Wet, Ice→Frozen, Poison→Poison)
	-- Only fires if actual damage > 0 and target alive.
	-- Skips if the same status was already applied by appliesStatus above.
	if outcome.element and actual > 0 and target.isAlive then
		applyElementStatusTriggers(outcome.sourceUnitId or "unknown", target, outcome.element, actual, statusApplied, attacker)
	end

	-- Confuse backlash: when a confused unit deals damage, it takes
	-- backlash = round(finalDamage × 0.30 × debuffResist)
	-- DB: "backlash = round(Final Enemy HP Damage × 0.30 × Debuff Resistance)"
	if attacker and actual > 0 and StatusService.HasStatus(attacker, "Confuse") then
		local debuffResist = attacker.derivedStats and attacker.derivedStats.debuffResist or 1.0
		local backlash = math.max(0, math.round(actual * 0.30 * debuffResist))
		if backlash > 0 and attacker.isAlive then
			UnitSchema_ApplyDamage(backlash, attacker)
			print(string.format(
				"[CombatResolver] Confuse backlash: %s takes %d self-damage", attacker.name, backlash
			))
		end
	end

	-- Vampire lifesteal: heal attacker for % of damage dealt
	-- TRG-010: Uses UnitSchema_ApplyHealing directly (not ApplyOutcome),
	-- so it cannot recursively trigger lifesteal or other generated effects.
	if attacker and actual > 0 and attacker.isAlive then
		local isAOE = outcome.isAOE or false
		local lifesteal = RacePassiveService.GetLifestealAmount(attacker, actual, isAOE)
		if lifesteal > 0 then
			UnitSchema_ApplyHealing(lifesteal, attacker)
			print(string.format(
				"[CombatResolver] Vampire lifesteal: %s heals %d (%.0f%% of %d)",
				attacker.name, lifesteal, isAOE and 5 or 15, actual
			))
		end
	end

	-- Doctrine lifesteal: Reaper Soul Rend (Slice 4H)
	if attacker and actual > 0 and attacker.isAlive then
		local docLifesteal = DoctrinePassiveService.GetLifestealAmount(attacker, actual, outcome.isAOE or false)
		if docLifesteal > 0 then
			UnitSchema_ApplyHealing(docLifesteal, attacker)
			print(string.format(
				"[CombatResolver] Doctrine lifesteal: %s heals %d", attacker.name, docLifesteal
			))
		end
	end

	-- Shadow Hide-on-hit: defender gains Hide after taking damage
	if actual > 0 then
		RacePassiveService.OnDamageReceived(target, actual, outcome.sourceUnitId)
		DoctrinePassiveService.OnDamageTaken(target)
	end

	local posLabel = ""
	if outcome.positionalMod and outcome.positionalMod ~= 1.0 then
		local pct = math.round((outcome.positionalMod - 1) * 100)
		posLabel = string.format(" | Pos:%+d%%", pct)
	end

	print(string.format(
		"[CombatResolver] %s takes %d damage (AP:%.1f HQ:%.2f%s) | HP: %d/%d %s%s",
		target.name,
		outcome.finalDamage,
		outcome.attackPower,
		outcome.hitQuality,
		posLabel,
		target.currentHp,
		target.maxHp,
		target.isAlive and "" or "| DEFEATED",
		statusApplied and (" | +" .. statusApplied) or ""
	))

	-- Zombie KO timer: start revive countdown on death
	if not target.isAlive then
		RacePassiveService.OnUnitKO(target)
	end

	return actual, statusApplied
end

--------------------------------------------------
-- BIND APPLY DAMAGE / HEALING
--------------------------------------------------

local _applyDamage = nil
local _applyHealing = nil

function CombatResolver.BindApplyDamage(fn)
	_applyDamage = fn
end

function CombatResolver.BindApplyHealing(fn)
	_applyHealing = fn
end

function UnitSchema_ApplyDamage(amount, unit)
	if _applyDamage then
		return _applyDamage(unit, amount)
	end
	local actual = math.min(unit.currentHp, amount)
	unit.currentHp = unit.currentHp - actual
	if unit.currentHp <= 0 then
		-- Armor passive: survive lethal damage at 1 HP (once per battle)
		if ArmorPassiveService.CanSurviveLethalDamage(unit) then
			unit.currentHp = 1
			print(string.format("[CombatResolver] %s survived lethal damage via armor passive (1 HP)", unit.name))
			return actual - 1
		end
		unit.isAlive   = false
		unit.currentHp = 0
		unit.currentAp = 0
	end
	return actual
end

function UnitSchema_ApplyHealing(amount, unit)
	if _applyHealing then
		return _applyHealing(unit, amount)
	end
	local actual = math.min(unit.maxHp - unit.currentHp, amount)
	unit.currentHp = unit.currentHp + actual
	return actual
end

return CombatResolver
