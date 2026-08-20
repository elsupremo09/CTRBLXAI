-- CombatResolver.lua
-- CTRBLXAI | Slice 1
--
-- Calculates the numerical result of an attack or skill hit.
-- Returns an outcome table — does NOT write to unit state directly.
-- The caller (CommandService) applies the outcome.
--
-- Slice 1 scope:
--   Basic Attack and a single damage skill.
--   Full 9-step damage sequence from the DB (core_stats — damage sequence):
--     1. Attack Power / Skill Power
--     2. Defense (Slice 1: units have no equipment, Defense = 0)
--     3. Outgoing Damage category modifiers (Slice 1: none)
--     4. Hit Quality  (Precision - Evasiveness)
--     5. Positional Modifier (Slice 1: none)
--     6. Element Modifier (Slice 1: no weaknesses)
--     7. Combat Fortune (Slice 1: skipped — LUK delta lookup deferred)
--     8. Guard / final mitigation (Slice 1: no Guard)
--     9. Round once
--
-- Formulas (locked, from DB):
--   Basic Attack Power = Weapon Damage * (1 + STR / 200)
--     Slice 1: no weapons. Weapon Damage is provided by the caller
--     (hardcoded in the unit definition for now).
--   Defense Power = Defense * (1 + VIT / 300)   [Defense = 0 in Slice 1]
--   Effective Defense = (AP * DP) / (AP + DP)
--   Raw Damage = AP - Effective Defense
--   Hit Quality = 1 + (Precision - Evasiveness)
--     Precision   = DEX / (DEX + 200)
--     Evasiveness = AGI / (AGI + 200)
--   Final Damage = round(Raw Damage * Hit Quality)
--   Minimum final damage = 0 (no universal minimum-1 rule).

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
	-- Slice 1: no equipment, Defense = 0.
	-- Effective Defense = (AP * DP) / (AP + DP)
	-- When DP = 0, Effective Defense = 0.
	if defense <= 0 then return 0 end
	local dp = defense * (1 + defenderVit / 300)
	return dp
end

local function calcEffectiveDefense(attackPower, defensePower)
	if attackPower <= 0 then return 0 end
	if defensePower <= 0 then return 0 end
	return (attackPower * defensePower) / (attackPower + defensePower)
end

--------------------------------------------------
-- PUBLIC: RESOLVE BASIC ATTACK
--
-- attacker, defender: unit tables (from UnitSchema)
-- weaponDamage: the weapon's base damage value (number)
--   In Slice 1, the caller passes a hardcoded value per unit.
--
-- Returns an outcome table:
--   {
--     type         = "Damage",
--     targetId     = defender.id,
--     rawDamage    = <number>,
--     hitQuality   = <number>,
--     finalDamage  = <number>,  -- the value to subtract from HP
--     attackPower  = <number>,  -- for debug
--     defensePower = <number>,  -- for debug
--   }
--------------------------------------------------

function CombatResolver.ResolveBasicAttack(attacker, defender, weaponDamage)
	assert(
		type(attacker) == "table" and type(defender) == "table",
		"ResolveBasicAttack: attacker and defender must be unit tables."
	)
	assert(
		type(weaponDamage) == "number" and weaponDamage >= 0,
		"ResolveBasicAttack: weaponDamage must be a non-negative number."
	)

	local aStats = attacker.effectiveStats
	local dStats = defender.effectiveStats

	-- Step 1: Attack Power
	local ap = calcAttackPower(weaponDamage, aStats.STR)

	-- Step 2: Defense
	local dp = calcDefensePower(0, dStats.VIT) -- Defense = 0 in Slice 1
	local effectiveDefense = calcEffectiveDefense(ap, dp)

	-- Step 3: Outgoing Damage category modifiers — none in Slice 1.

	-- Step 4: Hit Quality
	local hitQuality = calcHitQuality(aStats.DEX, dStats.AGI)

	-- Steps 5-8: Positional, Element, Combat Fortune, Guard — none in Slice 1.

	-- Step 9: Raw Damage then round once.
	local rawDamage   = ap - effectiveDefense
	local finalDamage = math.max(0, math.round(rawDamage * hitQuality))

	return {
		type         = "Damage",
		targetId     = defender.id,
		attackPower  = ap,
		defensePower = dp,
		rawDamage    = rawDamage,
		hitQuality   = hitQuality,
		finalDamage  = finalDamage,
	}
end

--------------------------------------------------
-- PUBLIC: RESOLVE SKILL
--
-- Slice 1: A skill provides its own Power value (authored number).
-- The skill may or may not inherit STR scaling — declared in the
-- skill definition via inheritStr = true/false.
--
-- skillDef fields used here:
--   power        (number) — base skill damage value
--   inheritStr   (bool)   — if true, multiply by (1 + STR/200)
--   range        (number) — used by TargetingService, not here
--
-- Returns the same outcome shape as ResolveBasicAttack.
--------------------------------------------------

function CombatResolver.ResolveSkill(attacker, defender, skillDef)
	assert(
		type(attacker) == "table" and type(defender) == "table",
		"ResolveSkill: attacker and defender must be unit tables."
	)
	assert(
		type(skillDef) == "table" and type(skillDef.power) == "number",
		"ResolveSkill: skillDef must have a numeric power field."
	)

	local aStats = attacker.effectiveStats
	local dStats = defender.effectiveStats

	-- Step 1: Skill Power
	local sp = skillDef.power
	if skillDef.inheritStr then
		sp = sp * (1 + aStats.STR / 200)
	end

	-- Step 2: Defense (0 in Slice 1)
	local dp = calcDefensePower(0, dStats.VIT)
	local effectiveDefense = calcEffectiveDefense(sp, dp)

	-- Step 4: Hit Quality
	local hitQuality = calcHitQuality(aStats.DEX, dStats.AGI)

	-- Step 9: Round once.
	local rawDamage   = sp - effectiveDefense
	local finalDamage = math.max(0, math.round(rawDamage * hitQuality))

	return {
		type         = "Damage",
		targetId     = defender.id,
		attackPower  = sp,
		defensePower = dp,
		rawDamage    = rawDamage,
		hitQuality   = hitQuality,
		finalDamage  = finalDamage,
	}
end

--------------------------------------------------
-- PUBLIC: APPLY OUTCOME
--   Writes the outcome's finalDamage to the target unit.
--   Returns the actual HP change (capped at current HP).
--------------------------------------------------

function CombatResolver.ApplyOutcome(outcome, defender)
	assert(
		outcome.type == "Damage",
		"ApplyOutcome: only Damage outcomes are supported in Slice 1."
	)

	local actual = UnitSchema_ApplyDamage(outcome.finalDamage, defender)

	print(string.format(
		"[CombatResolver] %s takes %d damage (AP:%.1f HQ:%.2f) | HP: %d/%d %s",
		defender.name,
		outcome.finalDamage,
		outcome.attackPower,
		outcome.hitQuality,
		defender.currentHp,
		defender.maxHp,
		defender.isAlive and "" or "| DEFEATED"
	))

	return actual
end

-- NOTE: CombatResolver.ApplyOutcome calls UnitSchema.ApplyDamage but
-- cannot require UnitSchema here without a circular path in Slice 1.
-- CommandService owns the require chain. It passes a bound function
-- via CombatResolver.BindApplyDamage() below.

local _applyDamage = nil

function CombatResolver.BindApplyDamage(fn)
	_applyDamage = fn
end

-- Override the inner call once the binding exists.
function UnitSchema_ApplyDamage(amount, unit)
	if _applyDamage then
		return _applyDamage(unit, amount)
	end
	-- Fallback (should not happen if CommandService binds correctly).
	local actual = math.min(unit.currentHp, amount)
	unit.currentHp = unit.currentHp - actual
	if unit.currentHp <= 0 then
		unit.isAlive   = false
		unit.currentHp = 0
		unit.currentAp = 0
	end
	return actual
end

return CombatResolver
