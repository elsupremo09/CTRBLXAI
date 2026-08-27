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

local function calcPrecision(dex)
	return dex / (dex + 200)
end

local function calcEvasiveness(agi)
	return agi / (agi + 200)
end

local function calcHitQuality(attackerDex, defenderAgi)
	local precision   = calcPrecision(attackerDex)
	local evasiveness = calcEvasiveness(defenderAgi)
	return 1 + (precision - evasiveness)
end

local function calcAttackPower(weaponDamage, attackerStr)
	return weaponDamage * (1 + attackerStr / 200)
end

local function calcDefensePower(defense, defenderVit)
	if defense <= 0 then return 0 end
	return defense * (1 + defenderVit / 300)
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

	local ap = calcAttackPower(weaponDamage, aStats.STR)
	local dp = calcDefensePower(0, dStats.VIT)
	local effectiveDefense = calcEffectiveDefense(ap, dp)
	local hitQuality = calcHitQuality(aStats.DEX, dStats.AGI)

	local positionalMod = GameConstants.GetPositionalModifier(
		attacker.tileX, attacker.tileY,
		defender.tileX, defender.tileY
	)

	local rawDamage   = ap - effectiveDefense
	-- Combat Fortune: LUK difference modifies damage (step 7 in pipeline)
	local fortuneMod = GameConstants.CalcCombatFortune(aStats.LUK, dStats.LUK)

	local finalDamage = math.max(0, math.round(rawDamage * hitQuality * positionalMod * fortuneMod))

	-- Step 8: Guard and other final mitigation
	if defender.isGuarding then
		local mitigation = GameConstants.GUARD_MITIGATION + (defender.guardBonus or 0)
		mitigation = math.min(mitigation, GameConstants.GUARD_CAP)
		finalDamage = math.max(0, math.round(finalDamage * (1 - mitigation)))
	end

	return {
		type           = "Damage",
		targetId       = defender.id,
		attackPower    = ap,
		defensePower   = dp,
		rawDamage      = rawDamage,
		hitQuality     = hitQuality,
		positionalMod  = positionalMod,
		finalDamage    = finalDamage,
		appliesStatus  = nil,
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
		sp = sp * (1 + aStats.STR / 200)
	end

	local dp = calcDefensePower(0, dStats.VIT)
	local effectiveDefense = calcEffectiveDefense(sp, dp)
	local hitQuality = calcHitQuality(aStats.DEX, dStats.AGI)

	local positionalMod = GameConstants.GetPositionalModifier(
		attacker.tileX, attacker.tileY,
		defender.tileX, defender.tileY
	)

	local rawDamage   = sp - effectiveDefense
	-- Combat Fortune: LUK difference modifies damage (step 7 in pipeline)
	local fortuneMod = GameConstants.CalcCombatFortune(aStats.LUK, dStats.LUK)

	local finalDamage = math.max(0, math.round(rawDamage * hitQuality * positionalMod * fortuneMod))

	-- Step 8: Guard and other final mitigation
	if defender.isGuarding then
		local mitigation = GameConstants.GUARD_MITIGATION + (defender.guardBonus or 0)
		mitigation = math.min(mitigation, GameConstants.GUARD_CAP)
		finalDamage = math.max(0, math.round(finalDamage * (1 - mitigation)))
	end

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
	local skillPotency = 1 + int / (200 + int)

	-- Healing formula (base)
	local baseHeal = 10 + 0.35 * int + weaponDamage * 0.30

	-- Healing Efficiency: target's VIT increases received healing
	-- Rule: Healing Efficiency = Healing × (1 + VIT / 300)
	local targetVit = target.effectiveStats and target.effectiveStats.VIT or 10
	local healEfficiency = 1 + targetVit / 300
	local finalHeal = math.max(1, math.round(baseHeal * skillPotency * healEfficiency))

	return {
		type         = "Healing",
		targetId     = target.id,
		finalHealing = finalHeal,
		sourceUnitId = caster.id,
	}
end

--------------------------------------------------
-- PUBLIC: APPLY OUTCOME (damage or healing)
--------------------------------------------------

function CombatResolver.ApplyOutcome(outcome, target)
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

	local statusApplied = nil
	if outcome.appliesStatus and actual > 0 and target.isAlive then
		-- For Burn, pass the actual fire damage dealt
		local fireDmg = nil
		if outcome.appliesStatus == "Burn" then
			fireDmg = actual
		end
		StatusService.ApplyStatus(
			target,
			outcome.appliesStatus,
			outcome.sourceUnitId or "unknown",
			fireDmg
		)
		statusApplied = outcome.appliesStatus
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
