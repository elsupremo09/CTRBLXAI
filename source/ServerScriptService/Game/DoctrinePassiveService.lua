-- DoctrinePassiveService.lua
-- CTRBLXAI | Doctrine Passive Functions (all 32 doctrines)
--
-- Centralized query interface for doctrine passive effects.
-- Other services call these to apply doctrine-based modifiers.
-- Units without a doctrineId receive neutral (no-op) values.
-- Break status disables ALL doctrine passives (checked early in every function).
--
-- Per-turn state is stored on the unit table with _doc* prefix.
-- OnTurnStart MUST be called at the start of each unit turn to reset flags.
--
-- Hook sites:
--   CombatResolver  → GetDamageDealtModifier, GetDamageReceivedModifier,
--                      GetDamageReductionModifier, GetLifestealAmount, etc.
--   CommandService   → GetMpCostModifier, GetSkillRtModifier, GetBasicAttackRtModifier
--   EquipmentService → (stat packages applied separately via DoctrineData)
--   BattleCoordinator → OnTurnStart, OnSkillResolved, OnDamageTaken

local DoctrinePassiveService = {}

local StatusService = require(script.Parent.StatusService)

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function getDoctrineId(unit)
	return unit and unit.doctrineId or nil
end

--- Returns true if unit has Break status (disables all doctrine passives).
local function isBroken(unit)
	if not unit or not unit.statusInstances then return false end
	for _, inst in ipairs(unit.statusInstances) do
		if inst.id == "Break" then return true end
	end
	return false
end

--- Chebyshev distance (game standard for all range checks).
local function chebyshevDist(a, b)
	if not a or not b then return math.huge end
	if not a.tileX or not a.tileY or not b.tileX or not b.tileY then return math.huge end
	return math.max(math.abs(a.tileX - b.tileX), math.abs(a.tileY - b.tileY))
end

--- Returns true if at least one standing ally is within Chebyshev range.
local function hasAllyInRange(unit, allUnits, range)
	if not allUnits then return false end
	for _, other in ipairs(allUnits) do
		if other ~= unit
			and other.isAlive
			and other.side == unit.side
			and chebyshevDist(unit, other) <= range
		then
			return true
		end
	end
	return false
end

--- Duelist equipment: naturally legal 1H main hand, empty off-hand, no Colossal Arsenal.
local function isDuelistEquipValid(unit)
	if not unit then return false end
	if unit.weaponHandClass ~= "1H" then return false end
	-- Off-hand must be empty
	if unit.equipmentSlots and unit.equipmentSlots.OffHand then return false end
	-- Titan Colossal Arsenal disqualifies
	if unit.raceId == "RACE-TITAN" then return false end
	return true
end

--- Juggernaut equipment: naturally legal 2H melee main hand at 100% normal use.
local function isJuggernautEquipValid(unit)
	if not unit then return false end
	if unit.weaponHandClass ~= "2H" then return false end
	-- Must be melee (no projectile type means melee delivery)
	if unit.weaponProjectileType and unit.weaponProjectileType ~= "" then return false end
	-- Titan Colossal Arsenal (equips 2H as 1H) disqualifies — not "100% normal use"
	if unit.raceId == "RACE-TITAN" then return false end
	return true
end

--- Shield equipped in off-hand.
local function isShieldEquipped(unit)
	if not unit or not unit.equipmentSlots then return false end
	local offHand = unit.equipmentSlots.OffHand
	if not offHand then return false end
	return offHand.type == "Shield" or offHand.category == "Shield"
		or offHand.itemType == "shield"
end

--- Returns true if target has the Undead tag or an undead race.
local function isUndead(target)
	if not target then return false end
	local raceId = target.raceId or ""
	if raceId == "RACE-ZOMBIE" or raceId == "RACE-LICH" or raceId == "RACE-VAMPIRE" then
		return true
	end
	if target.tags and target.tags.Undead then return true end
	return false
end

--- Returns true if unit has a specific status effect.
local function hasStatus(unit, statusId)
	if not unit or not unit.statusInstances then return false end
	for _, inst in ipairs(unit.statusInstances) do
		if inst.id == statusId then return true end
	end
	return false
end

--- Returns true if attacker is at higher elevation than defender.
local function hasElevationAdvantage(attacker, defender)
	if not attacker or not defender then return false end
	local aElev = attacker.elevation or attacker.tileZ or 0
	local dElev = defender.elevation or defender.tileZ or 0
	return aElev > dElev
end

--- Valid elemental tags for Elementalist tracking.
local VALID_ELEMENTS = {
	Fire = true, Ice = true, Water = true, Electric = true,
	Earth = true, Poison = true, Dark = true, Holy = true,
}

--------------------------------------------------
-- DAMAGE DEALT MODIFIER
-- Returns a multiplier applied to final damage dealt by this unit.
-- Called from CombatResolver after base damage is calculated.
--
-- Args:
--   attacker:    unit table (the damage source)
--   defender:    target unit table
--   element:     damage element string or nil ("Physical"/nil = physical)
--   isSkill:     boolean (true if this is a Skill resolution)
--   isBasicAttack: boolean
--   context:     optional table {
--     isDirectDamageSkill = bool,    -- Skill has Direct Damage tag
--     additionalTargetsHit = number, -- for Stormbringer chain bonus
--   }
--
-- Note: Juggernaut BA bonus is in GetBasicAttackDamageModifier.
-- Duelist BA bonus is in GetBasicAttackDamageModifier.
--------------------------------------------------

function DoctrinePassiveService.GetDamageDealtModifier(attacker, defender, element, isSkill, isBasicAttack, context)
	local docId = getDoctrineId(attacker)
	if not docId or isBroken(attacker) then return 1.0 end

	local mod = 1.0
	local isDDS = context and context.isDirectDamageSkill

	-- BERSERKER — Blood Frenzy: HP <50% → all final damage dealt +20%
	if docId == "DOC-BERSERKER" then
		if attacker.currentHp and attacker.maxHp
			and attacker.currentHp < (attacker.maxHp * 0.5)
		then
			mod = mod * 1.20
		end
	end

	-- JUGGERNAUT — Two-Handed Mastery: Direct Damage Skill +15% (2H melee equipped)
	-- (Basic Attack portion handled in GetBasicAttackDamageModifier)
	if docId == "DOC-JUGGERNAUT" and isSkill and isDDS then
		if isJuggernautEquipValid(attacker) then
			mod = mod * 1.15
		end
	end

	-- ASSASSIN — Killing Intent: DDS +20% vs targets that haven't acted this round
	if docId == "DOC-ASSASSIN" and isSkill and isDDS then
		if defender and not defender.hasActedThisRound then
			mod = mod * 1.20
		end
	end

	-- DRAGOON — Aerial Supremacy: DDS +20% from higher elevation
	-- (positional defense bypass handled in GetPositionalDefenseIgnore)
	if docId == "DOC-DRAGOON" and isSkill and isDDS then
		if hasElevationAdvantage(attacker, defender) then
			mod = mod * 1.20
		end
	end

	-- TEMPLAR — Radiant Judgment: Holy damage +15%; +30% vs Undead (replaces, does not stack)
	if docId == "DOC-TEMPLAR" then
		if element == "Holy" then
			if isUndead(defender) then
				mod = mod * 1.30
			else
				mod = mod * 1.15
			end
		end
	end

	-- STORMBRINGER — Conductivity:
	--   Electric +25% vs Wet targets
	--   Electric Skills: +5% per additional target hit (cap +20%)
	--   Wet bonus and multi-target bonus stack additively
	if docId == "DOC-STORMBRINGER" and element == "Electric" then
		if defender and hasStatus(defender, "Wet") then
			mod = mod * 1.25
		end
		if context and context.additionalTargetsHit and context.additionalTargetsHit > 0 then
			local chainBonus = math.min(context.additionalTargetsHit * 0.05, 0.20)
			mod = mod * (1.0 + chainBonus)
		end
	end

	-- SKIRMISHER — Harrying Strikes: DDS +15% after moving 2+ tiles this turn
	-- (Bleed application handled in ShouldApplyBleed)
	if docId == "DOC-SKIRMISHER" and isSkill and isDDS then
		if (attacker._docSkirmisherTilesMoved or 0) >= 2 then
			mod = mod * 1.15
		end
	end

	-- ELEMENTALIST — Elemental Convergence:
	--   Elemental Skill damage +12%; +18% if different element from last Skill used
	if docId == "DOC-ELEMENTALIST" and isSkill and element and VALID_ELEMENTS[element] then
		local lastEl = attacker._docElementalistLastElement
		if lastEl and lastEl ~= element then
			mod = mod * 1.18 -- different element: +18%
		else
			mod = mod * 1.12 -- same or first element: +12%
		end
	end

	-- MONK — Flowing Strikes: same-target repeated DDS +10% per prior hit (cap +30%)
	if docId == "DOC-MONK" and isSkill and isDDS then
		local lastTargetId = attacker._docMonkLastTargetId
		local defenderId = defender and (defender.id or defender.unitId)
		if lastTargetId and defenderId and lastTargetId == defenderId then
			local hitCount = attacker._docMonkHitCount or 0
			local bonus = math.min(hitCount * 0.10, 0.30)
			if bonus > 0 then
				mod = mod * (1.0 + bonus)
			end
		end
	end

	-- SENTINEL — Vengeful Riposte: after taking damage, next DDS +20%
	-- (charge consumed in OnSkillResolved)
	if docId == "DOC-SENTINEL" and isSkill and isDDS then
		if attacker._docSentinelCharged then
			mod = mod * 1.20
		end
	end

	return mod
end

--------------------------------------------------
-- DAMAGE RECEIVED MODIFIER
-- Returns a multiplier on final damage received.
-- Values > 1.0 mean the unit takes MORE damage.
-- Called from CombatResolver after finalDamage is calculated.
--
-- Proximity-based DR (Vanguard, Shieldbearer) uses
-- GetDamageReductionModifier instead (requires allUnits).
--------------------------------------------------

function DoctrinePassiveService.GetDamageReceivedModifier(defender, attacker, element, isSkill)
	local docId = getDoctrineId(defender)
	if not docId or isBroken(defender) then return 1.0 end

	local mod = 1.0

	-- BERSERKER — Blood Frenzy: HP <50% → direct damage received +10%
	if docId == "DOC-BERSERKER" then
		if defender.currentHp and defender.maxHp
			and defender.currentHp < (defender.maxHp * 0.5)
		then
			mod = mod * 1.10
		end
	end

	return mod
end

--------------------------------------------------
-- HEALING MODIFIER
-- Returns a multiplier on healing potency when this unit heals a target.
-- Called from CombatResolver for Healing-tagged Skills.
--------------------------------------------------

function DoctrinePassiveService.GetHealingModifier(healer, target)
	local docId = getDoctrineId(healer)
	if not docId or isBroken(healer) then return 1.0 end

	-- CLERIC — Sacred Bond: healing +15%; +25% if target <30% max HP (replaces)
	if docId == "DOC-CLERIC" then
		if target and target.currentHp and target.maxHp
			and target.currentHp < (target.maxHp * 0.30)
		then
			return 1.25
		end
		return 1.15
	end

	return 1.0
end

--------------------------------------------------
-- MP COST MODIFIER
-- Returns a multiplier for Skill MP costs.
-- Called from CommandService before MP validation.
--
-- Arcanist: first Skill per turn gets -25% ordinary MP cost (min 1).
-- The caller must enforce the min-1 floor after multiplying.
--------------------------------------------------

function DoctrinePassiveService.GetMpCostModifier(unit, isFirstSkillThisTurn)
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 1.0 end

	-- ARCANIST — Arcane Efficiency: first Skill per turn, MP cost -25%
	if docId == "DOC-ARCANIST" then
		if isFirstSkillThisTurn then
			return 0.75
		end
	end

	return 1.0
end

--------------------------------------------------
-- SKILL RT MODIFIER
-- Returns a multiplier for Skill RT cost.
-- Called from CommandService when committing a Skill.
--
-- context (optional): { isUtilitySkill = bool }
-- Trickster only applies to first Utility Skill per turn.
-- Shieldbearer guard-RT bonus applies to next Skill after Guard damage.
--------------------------------------------------

function DoctrinePassiveService.GetSkillRtModifier(unit, context)
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 1.0 end

	local mod = 1.0

	-- TRICKSTER — Fleeting Step: first Utility Skill per turn, RT -25%
	if docId == "DOC-TRICKSTER" then
		local isUtility = context and context.isUtilitySkill
		if isUtility and not unit._docTricksterUsedUtility then
			mod = mod * 0.75
		end
	end

	-- SHIELDBEARER — Aegis Protocol: after taking Guard damage, next Skill RT -25%
	if docId == "DOC-SHIELDBEARER" and isShieldEquipped(unit) then
		if unit._docShieldbearerGuardRtReady then
			mod = mod * 0.75
		end
	end

	return mod
end

--------------------------------------------------
-- BASIC ATTACK RT MODIFIER
-- Returns a multiplier for Basic Attack RT cost.
-- Called from CommandService / CombatResolver for BA RT calc.
--------------------------------------------------

function DoctrinePassiveService.GetBasicAttackRtModifier(unit)
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 1.0 end

	-- DUELIST — Single-Weapon Mastery: BA RT -15%
	if docId == "DOC-DUELIST" and isDuelistEquipValid(unit) then
		return 0.85
	end

	return 1.0
end

--------------------------------------------------
-- BASIC ATTACK DAMAGE MODIFIER
-- Returns a multiplier on Basic Attack final damage.
-- Called from CombatResolver for BA damage calc.
--------------------------------------------------

function DoctrinePassiveService.GetBasicAttackDamageModifier(unit)
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 1.0 end

	-- JUGGERNAUT — Two-Handed Mastery: BA final damage +15%
	if docId == "DOC-JUGGERNAUT" and isJuggernautEquipValid(unit) then
		return 1.15
	end

	-- DUELIST — Single-Weapon Mastery: BA final damage +20%
	if docId == "DOC-DUELIST" and isDuelistEquipValid(unit) then
		return 1.20
	end

	return 1.0
end

--------------------------------------------------
-- SKILL POTENCY MODIFIER
-- Returns a multiplier on Skill Potency (applied before damage calc).
-- Called from CombatResolver for eligible Skills.
--
-- Spellblade: +10% for Physical DDS with positive Weapon Attack Power scaling.
-- The caller is responsible for verifying the Skill is a Physical DDS
-- with weapon scaling before applying this modifier.
--------------------------------------------------

function DoctrinePassiveService.GetSkillPotencyModifier(unit)
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 1.0 end

	-- SPELLBLADE — Arcane Edge: Skill Potency +10%
	if docId == "DOC-SPELLBLADE" then
		return 1.10
	end

	return 1.0
end

--------------------------------------------------
-- HIT QUALITY MODIFIER
-- Returns a float offset added to Hit Quality.
-- Called from CombatResolver hit-check pipeline.
--
-- Ranger: +0.15 if unit has not moved this turn.
-- Duelist: +0.15 if single-weapon mastery conditions met.
--------------------------------------------------

function DoctrinePassiveService.GetHitQualityModifier(unit)
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 0 end

	local bonus = 0

	-- RANGER — Steady Aim: +0.15 Hit Quality if not moved this turn
	if docId == "DOC-RANGER" then
		if not unit._docRangerMoved then
			bonus = bonus + 0.15
		end
	end

	-- DUELIST — Single-Weapon Mastery: Hit Quality +0.15
	if docId == "DOC-DUELIST" and isDuelistEquipValid(unit) then
		bonus = bonus + 0.15
	end

	return bonus
end

--------------------------------------------------
-- EVASIVENESS MODIFIER
-- Returns a float offset added to Evasiveness.
-- Called from CombatResolver evasion pipeline.
--------------------------------------------------

function DoctrinePassiveService.GetEvasivenessModifier(unit)
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 0 end

	-- DUELIST — Single-Weapon Mastery: Evasiveness +10%
	if docId == "DOC-DUELIST" and isDuelistEquipValid(unit) then
		return 0.10
	end

	return 0
end

--------------------------------------------------
-- PROJECTILE RANGE MODIFIER
-- Returns an integer offset to projectile Maximum Range.
-- Minimum Range is unchanged.
-- Called from TargetingService.
--------------------------------------------------

function DoctrinePassiveService.GetProjectileRangeModifier(unit)
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 0 end

	-- RANGER — Steady Aim: projectile Maximum Range +1 (if not moved)
	if docId == "DOC-RANGER" then
		if not unit._docRangerMoved then
			return 1
		end
	end

	return 0
end

--------------------------------------------------
-- DAMAGE REDUCTION MODIFIER
-- Returns a multiplier < 1.0 for damage reduction.
-- Checks proximity-based effects (requires allUnits).
-- Called from CombatResolver after finalDamage is calculated.
--
-- Also checks Paladin Divine Aegis temporary DR.
--------------------------------------------------

function DoctrinePassiveService.GetDamageReductionModifier(unit, allUnits)
	if not unit then return 1.0 end
	-- Note: Break check is per-doctrine below; Paladin DR can be on non-Paladin units.

	local mod = 1.0
	local docId = getDoctrineId(unit)

	-- VANGUARD — Bulwark: direct damage received -10% if ally within range 2
	if docId == "DOC-VANGUARD" and not isBroken(unit) then
		if hasAllyInRange(unit, allUnits, 2) then
			mod = mod * 0.90
		end
	end

	-- SHIELDBEARER — Aegis Protocol: direct damage received -12% if shield equipped
	if docId == "DOC-SHIELDBEARER" and not isBroken(unit) then
		if isShieldEquipped(unit) then
			mod = mod * 0.88
		end
	end

	-- PALADIN — Divine Aegis: +10% DR for 1 turn (applied by Paladin OnSkillResolved)
	-- This flag can exist on ANY unit (Paladin grants it to healed allies)
	if (unit._docPaladinDrTurnsRemaining or 0) > 0 then
		mod = mod * 0.90
	end

	return mod
end

--------------------------------------------------
-- STABILITY MODIFIER
-- Returns an integer offset to Stability.
-- Called from CombatResolver knockback/displacement calc.
--------------------------------------------------

function DoctrinePassiveService.GetStabilityModifier(unit, allUnits)
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 0 end

	-- VANGUARD — Bulwark: Stability +1 if ally within range 2
	if docId == "DOC-VANGUARD" then
		if hasAllyInRange(unit, allUnits, 2) then
			return 1
		end
	end

	return 0
end

--------------------------------------------------
-- DEBUFF DURATION MODIFIER
-- Returns a multiplier on authored debuff duration.
-- Applied BEFORE Debuff Resistance and boss modifiers.
-- Excludes Permanent, Unlimited, and instant debuffs.
-- Called from StatusService when applying debuffs.
--------------------------------------------------

function DoctrinePassiveService.GetDebuffDurationModifier(unit)
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 1.0 end

	-- SHADOWBINDER — Malignancy: debuff duration +20%
	if docId == "DOC-SHADOWBINDER" then
		return 1.20
	end

	return 1.0
end

--------------------------------------------------
-- BUFF DURATION MODIFIER
-- Returns an integer offset (turns) to buff duration.
-- Applied at buff creation.
-- Called from StatusService when applying buffs.
--------------------------------------------------

function DoctrinePassiveService.GetBuffDurationModifier(unit)
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 0 end

	-- ENCHANTER — Lingering Enchantment: buff duration +1 turn
	if docId == "DOC-ENCHANTER" then
		return 1
	end

	return 0
end

--------------------------------------------------
-- TERRAIN DURATION MODIFIER
-- Returns an integer offset (turns) to terrain effect duration.
-- Applied at terrain creation.
-- Called from TileEffectService when creating terrain.
--------------------------------------------------

function DoctrinePassiveService.GetTerrainDurationModifier(unit)
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 0 end

	-- GEOMANCER — Terrain Mastery: terrain effects +1 turn
	if docId == "DOC-GEOMANCER" then
		return 1
	end

	return 0
end

--------------------------------------------------
-- TERRAIN DAMAGE MODIFIER
-- Returns a multiplier on terrain damage dealt by this unit's owned terrain.
-- Called from TileEffectService / TileCrossEffectService.
--------------------------------------------------

function DoctrinePassiveService.GetTerrainDamageModifier(unit)
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 1.0 end

	-- GEOMANCER — Terrain Mastery: terrain damage +20%
	if docId == "DOC-GEOMANCER" then
		return 1.20
	end

	return 1.0
end

--------------------------------------------------
-- ON SKILL RESOLVED (post-resolution hook)
-- Called after a Skill fully resolves. Handles:
--   Ascetic MP restore, Sentinel charge consumption,
--   Monk hit tracking, Elementalist element tracking,
--   Paladin Divine Aegis, Arcanist/Trickster flag consumption,
--   Shieldbearer RT bonus consumption.
--
-- context (optional): {
--   spentMp = bool,             -- Skill consumed MP
--   isDirectDamageSkill = bool,
--   isHealingSkill = bool,
--   isHolySkill = bool,
--   isUtilitySkill = bool,
-- }
--------------------------------------------------

function DoctrinePassiveService.OnSkillResolved(unit, target, element, context)
	local docId = getDoctrineId(unit)
	if not unit then return end

	-- === Ascetic — Inner Reserve: restore 5% Max MP after first MP-spending Skill ===
	if docId == "DOC-ASCETIC" and not isBroken(unit) then
		local spentMp = context and context.spentMp
		if spentMp and not unit._docAsceticUsedMpSkill then
			unit._docAsceticUsedMpSkill = true
			local restore = math.max(1, math.round(unit.maxMp * 0.05))
			unit.currentMp = math.min(unit.maxMp, unit.currentMp + restore)
			print(string.format(
				"[DoctrinePassiveService] Ascetic Inner Reserve: %s restores %d MP (%d/%d)",
				unit.name, restore, unit.currentMp, unit.maxMp
			))
		end
	end

	-- === Sentinel — Vengeful Riposte: consume charge on DDS ===
	if docId == "DOC-SENTINEL" and not isBroken(unit) then
		local isDDS = context and context.isDirectDamageSkill
		if isDDS and unit._docSentinelCharged then
			unit._docSentinelCharged = false
			print(string.format(
				"[DoctrinePassiveService] Sentinel Vengeful Riposte: %s consumed charge",
				unit.name
			))
		end
	end

	-- === Monk — Flowing Strikes: track hits per target this turn ===
	if docId == "DOC-MONK" and not isBroken(unit) then
		local isDDS = context and context.isDirectDamageSkill
		if isDDS and target then
			local targetId = target.id or target.unitId
			if targetId then
				if unit._docMonkLastTargetId == targetId then
					unit._docMonkHitCount = (unit._docMonkHitCount or 0) + 1
				else
					unit._docMonkLastTargetId = targetId
					unit._docMonkHitCount = 1
				end
			end
		end
	end

	-- === Elementalist — Elemental Convergence: track last element used ===
	if docId == "DOC-ELEMENTALIST" and not isBroken(unit) then
		if element and VALID_ELEMENTS[element] then
			unit._docElementalistLastElement = element
		end
	end

	-- === Paladin — Divine Aegis: grant +10% DR for 1 turn ===
	if docId == "DOC-PALADIN" and not isBroken(unit) then
		local isHolyOrHealing = (context and (context.isHolySkill or context.isHealingSkill))
		if isHolyOrHealing then
			-- Paladin gains DR
			unit._docPaladinDrTurnsRemaining = 1
			print(string.format(
				"[DoctrinePassiveService] Paladin Divine Aegis: %s gains +10%% DR (1 turn)",
				unit.name
			))
			-- If Skill healed a target, target also gains DR
			if context.isHealingSkill and target and target ~= unit then
				target._docPaladinDrTurnsRemaining = 1
				print(string.format(
					"[DoctrinePassiveService] Paladin Divine Aegis: %s grants +10%% DR to %s",
					unit.name, target.name
				))
			end
		end
	end

	-- === Arcanist — mark first Skill consumed ===
	if docId == "DOC-ARCANIST" and not isBroken(unit) then
		unit._docArcanistUsedSkill = true
	end

	-- === Trickster — mark first Utility Skill consumed ===
	if docId == "DOC-TRICKSTER" and not isBroken(unit) then
		local isUtility = context and context.isUtilitySkill
		if isUtility then
			unit._docTricksterUsedUtility = true
		end
	end

	-- === Shieldbearer — consume Guard RT bonus ===
	if docId == "DOC-SHIELDBEARER" and unit._docShieldbearerGuardRtReady then
		unit._docShieldbearerGuardRtReady = false
	end
end

--------------------------------------------------
-- ON DAMAGE TAKEN
-- Called when a unit takes direct HP damage from an enemy.
-- Sets Sentinel Vengeful Riposte charge.
--------------------------------------------------

function DoctrinePassiveService.OnDamageTaken(unit, damageAmount, sourceUnit)
	local docId = getDoctrineId(unit)
	if not docId or not unit.isAlive then return end

	-- SENTINEL — Vengeful Riposte: after taking damage, charge next DDS +20%
	if docId == "DOC-SENTINEL" and not isBroken(unit) then
		unit._docSentinelCharged = true
		print(string.format(
			"[DoctrinePassiveService] Sentinel Vengeful Riposte: %s is charged (+20%% next DDS)",
			unit.name
		))
	end
end

--------------------------------------------------
-- ON TURN START
-- Called at the beginning of each unit turn.
-- Resets all per-turn doctrine state flags.
-- MUST be called for every unit, every turn.
--------------------------------------------------

function DoctrinePassiveService.OnTurnStart(unit)
	if not unit then return end

	-- Arcanist: reset first-Skill flag
	unit._docArcanistUsedSkill = false

	-- Trickster: reset first-Utility-Skill flag
	unit._docTricksterUsedUtility = false

	-- Monk: reset hit tracking
	unit._docMonkLastTargetId = nil
	unit._docMonkHitCount = 0

	-- Ranger: reset moved flag
	unit._docRangerMoved = false

	-- Skirmisher: reset tiles moved
	unit._docSkirmisherTilesMoved = 0

	-- Ascetic: reset MP-skill flag
	unit._docAsceticUsedMpSkill = false

	-- Shieldbearer Guard RT bonus: persists across turns (consumed on Skill commit)
	-- (do NOT reset here — it lasts until consumed or round end)

	-- Paladin Divine Aegis: decrement turn counter
	if unit._docPaladinDrTurnsRemaining and unit._docPaladinDrTurnsRemaining > 0 then
		unit._docPaladinDrTurnsRemaining = unit._docPaladinDrTurnsRemaining - 1
	end

	-- Gunner Suppression: decrement turn counter on affected targets
	if unit._docGunnerSuppressionTurns and unit._docGunnerSuppressionTurns > 0 then
		unit._docGunnerSuppressionTurns = unit._docGunnerSuppressionTurns - 1
	end
end

--------------------------------------------------
-- ON ROUND END
-- Called at the end of each round.
-- Clears round-scoped state (Sentinel charge, Shieldbearer RT bonus).
--------------------------------------------------

function DoctrinePassiveService.OnRoundEnd(unit)
	if not unit then return end

	-- Sentinel: charge expires at round end if not consumed
	if unit._docSentinelCharged then
		unit._docSentinelCharged = false
	end

	-- Shieldbearer: Guard RT bonus expires at round end
	if unit._docShieldbearerGuardRtReady then
		unit._docShieldbearerGuardRtReady = false
	end
end

--------------------------------------------------
-- LIFESTEAL AMOUNT
-- Returns HP to recover after dealing Dark damage.
-- Called from CombatResolver.ApplyOutcome after damage is applied.
--
-- Reaper — Soul Rend:
--   12% of Dark damage dealt as HP recovery.
--   If target defeated by this damage, +10% max HP bonus.
--------------------------------------------------

function DoctrinePassiveService.GetLifestealAmount(unit, darkDamageDealt, targetDefeated)
	local docId = getDoctrineId(unit)
	if docId ~= "DOC-REAPER" or isBroken(unit) then return 0 end
	if darkDamageDealt <= 0 then return 0 end

	local heal = math.max(1, math.round(darkDamageDealt * 0.12))
	if targetDefeated then
		heal = heal + math.max(1, math.round(unit.maxHp * 0.10))
	end

	print(string.format(
		"[DoctrinePassiveService] Reaper Soul Rend: %s recovers %d HP%s",
		unit.name, heal, targetDefeated and " (kill bonus)" or ""
	))

	return heal
end

--------------------------------------------------
-- SHOULD APPLY BLEED
-- Returns true if this unit's attack should apply 1 stack of Bleed.
-- Called from CombatResolver after a DDS hits.
--
-- Skirmisher — Harrying Strikes: apply Bleed after moving 2+ tiles.
--------------------------------------------------

function DoctrinePassiveService.ShouldApplyBleed(unit)
	local docId = getDoctrineId(unit)
	if docId ~= "DOC-SKIRMISHER" or isBroken(unit) then return false end
	return (unit._docSkirmisherTilesMoved or 0) >= 2
end

--------------------------------------------------
-- ALLY DAMAGE AURA MODIFIER
-- Returns a damage multiplier this unit gains from nearby Warlord allies.
-- The Warlord itself does NOT benefit from its own aura.
-- Called from CombatResolver for the attacking unit.
--
-- Also checks Tactician aura for Skill RT (see GetAllySkillRtAuraModifier).
--------------------------------------------------

function DoctrinePassiveService.GetAllyDamageAuraModifier(unit, allUnits)
	if not unit or not allUnits or isBroken(unit) then return 1.0 end

	-- Check if any Warlord ally (not self) is within range 3
	for _, other in ipairs(allUnits) do
		if other ~= unit
			and other.isAlive
			and other.side == unit.side
			and getDoctrineId(other) == "DOC-WARLORD"
			and not isBroken(other)
			and chebyshevDist(unit, other) <= 3
		then
			return 1.10 -- +10% direct final damage
		end
	end

	return 1.0
end

--------------------------------------------------
-- ALLY SKILL RT AURA MODIFIER
-- Returns an RT multiplier this unit gains from nearby Tactician allies.
-- The Tactician itself does NOT benefit from its own aura.
-- Excludes Channel, Activation, Move, Basic Attack, Guard, Item, Interact.
-- Called from CommandService when computing Skill RT cost.
--------------------------------------------------

function DoctrinePassiveService.GetAllySkillRtAuraModifier(unit, allUnits)
	if not unit or not allUnits or isBroken(unit) then return 1.0 end

	-- Check if any Tactician ally (not self) is within range 3
	for _, other in ipairs(allUnits) do
		if other ~= unit
			and other.isAlive
			and other.side == unit.side
			and getDoctrineId(other) == "DOC-TACTICIAN"
			and not isBroken(other)
			and chebyshevDist(unit, other) <= 3
		then
			return 0.90 -- Skill RT -10%
		end
	end

	return 1.0
end

--------------------------------------------------
-- POSITIONAL DEFENSE IGNORE
-- Returns fraction of target's positional defense bonus to ignore (0.0–1.0).
-- Called from CombatResolver before positional defense is applied.
--
-- Dragoon — Aerial Supremacy: ignore 50% positional defense from elevation.
--------------------------------------------------

function DoctrinePassiveService.GetPositionalDefenseIgnore(attacker, defender)
	local docId = getDoctrineId(attacker)
	if not docId or isBroken(attacker) then return 0 end

	if docId == "DOC-DRAGOON" then
		if hasElevationAdvantage(attacker, defender) then
			return 0.50
		end
	end

	return 0
end

--------------------------------------------------
-- WEAPON RT DELAY MODIFIER
-- Returns a multiplier on delivered Weapon RT Delay.
-- Called from CombatResolver when calculating the RT penalty
-- inflicted on the target by this unit's attack.
--------------------------------------------------

function DoctrinePassiveService.GetWeaponRtDelayModifier(unit)
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 1.0 end

	-- JUGGERNAUT — Two-Handed Mastery: delivered Weapon RT Delay +15%
	if docId == "DOC-JUGGERNAUT" and isJuggernautEquipValid(unit) then
		return 1.15
	end

	-- DUELIST — Single-Weapon Mastery: delivered Weapon RT Delay +15%
	if docId == "DOC-DUELIST" and isDuelistEquipValid(unit) then
		return 1.15
	end

	return 1.0
end

--------------------------------------------------
-- POISON/VENOM TICK MODIFIER
-- Returns a multiplier on Poison and Venom tick damage dealt by this unit.
-- Called from StatusService when processing Poison/Venom ticks.
--
-- Plague Doctor — Virulence: Poison and Venom tick damage +25%.
--------------------------------------------------

function DoctrinePassiveService.GetPoisonTickModifier(unit)
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 1.0 end

	if docId == "DOC-PLAGUE-DOCTOR" then
		return 1.25
	end

	return 1.0
end

--------------------------------------------------
-- DEBUFF RESISTANCE PENETRATION
-- Returns a fraction (0.0–1.0) of target's Debuff Resistance to ignore.
-- Only applies to Dark-tagged debuffs from Plague Doctor.
-- Called from StatusService when resolving debuff application.
--
-- Plague Doctor — Virulence: Dark-tagged debuffs ignore 15% Debuff Resistance.
--------------------------------------------------

function DoctrinePassiveService.GetDebuffResistancePenetration(unit, debuffElement)
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 0 end

	if docId == "DOC-PLAGUE-DOCTOR" then
		if debuffElement == "Dark" or debuffElement == "Poison" then
			return 0.15
		end
	end

	return 0
end

--------------------------------------------------
-- BUFF EFFECT MODIFIER
-- Returns a multiplier on buff numerical effects.
-- Applied at buff creation (multiplicative with base values).
-- Called from StatusService when applying buffs.
--
-- Enchanter — Lingering Enchantment: buff effects +10%.
--------------------------------------------------

function DoctrinePassiveService.GetBuffEffectModifier(unit)
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 1.0 end

	if docId == "DOC-ENCHANTER" then
		return 1.10
	end

	return 1.0
end

--------------------------------------------------
-- ON MOVEMENT USED
-- Called when a unit moves. Updates movement tracking.
-- Required for Ranger (Steady Aim invalidation) and
-- Skirmisher (Harrying Strikes activation).
--------------------------------------------------

function DoctrinePassiveService.OnMovementUsed(unit, tilesMoved)
	if not unit then return end

	-- Ranger: any movement disables Steady Aim for rest of turn
	if getDoctrineId(unit) == "DOC-RANGER" then
		unit._docRangerMoved = true
	end

	-- Skirmisher: accumulate tiles moved this turn
	unit._docSkirmisherTilesMoved = (unit._docSkirmisherTilesMoved or 0)
		+ (tilesMoved or 0)
end

--------------------------------------------------
-- ON GUARD DAMAGE TAKEN
-- Called when a Shieldbearer takes damage while Guarding.
-- Sets the RT bonus flag for next Skill.
-- Called from CombatResolver when Guard absorbs damage.
--------------------------------------------------

function DoctrinePassiveService.OnGuardDamageTaken(unit)
	local docId = getDoctrineId(unit)
	if docId ~= "DOC-SHIELDBEARER" or isBroken(unit) then return end
	if not isShieldEquipped(unit) then return end

	unit._docShieldbearerGuardRtReady = true
	print(string.format(
		"[DoctrinePassiveService] Shieldbearer Aegis Protocol: %s Guard-damage → next Skill RT -25%%",
		unit.name
	))
end

--------------------------------------------------
-- APPLY GUNNER SUPPRESSION
-- Applies movement reduction to target after a ranged DDS hit.
-- Called from CombatResolver after confirming hit.
--
-- Gunner — Suppressive Fire:
--   Target movement range -1 for next turn.
--   Multi-hit: each additional hit extends by 1 turn (cap 3).
--------------------------------------------------

function DoctrinePassiveService.ApplyGunnerSuppression(attacker, target, hitCount)
	local docId = getDoctrineId(attacker)
	if docId ~= "DOC-GUNNER" or isBroken(attacker) then return end
	if not target then return end

	local duration = math.min(hitCount or 1, 3)
	target._docGunnerSuppressionTurns = math.max(
		target._docGunnerSuppressionTurns or 0,
		duration
	)

	print(string.format(
		"[DoctrinePassiveService] Gunner Suppressive Fire: %s suppresses %s (Move -1, %d turns)",
		attacker.name, target.name, duration
	))
end

--------------------------------------------------
-- GET MOVEMENT REDUCTION
-- Returns an integer offset to movement range from Gunner Suppression.
-- Called from TargetingService.getMovementRange.
--------------------------------------------------

function DoctrinePassiveService.GetMovementReduction(unit)
	if not unit then return 0 end
	if (unit._docGunnerSuppressionTurns or 0) > 0 then
		return -1
	end
	return 0
end

--------------------------------------------------
-- BLOCKED DOCTRINE PASSIVES
-- These doctrines' passives require systems that don't exist yet.
-- Functions created for forward-compatibility; return neutral values.
--------------------------------------------------

--- BLOCKED: Thief — Fortune Hand
--- Requires fortune/reward system beyond current implementation.
--- Would add 50% of Thief's Fortune stat to Expedition Fortune for rewards.
function DoctrinePassiveService.GetFortuneBonus(unit)
	-- BLOCKED: requires fortune/reward system
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 0 end
	if docId == "DOC-THIEF" then
		-- When fortune system exists: return math.round(unit.fortune * 0.50)
		return 0
	end
	return 0
end

--- BLOCKED: Twinblade — Dual-Wield Discipline
--- Requires dual-wield combat system.
--- Would permit dual wield at 75% numerical properties.
function DoctrinePassiveService.IsDualWieldEnabled(unit)
	-- BLOCKED: requires dual-wield system
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return false end
	if docId == "DOC-TWINBLADE" then
		-- When dual-wield system exists: check two 1H weapons, return true
		return false
	end
	return false
end

--- BLOCKED: Twinblade — Dual-Wield off-hand scaling factor
function DoctrinePassiveService.GetDualWieldScaling(unit)
	-- BLOCKED: requires dual-wield system
	return 1.0
end

--- BLOCKED: Conjurer — Bound Host
--- Requires summon system.
--- Would grant summons +10% Max HP, +10% damage, +10% healing at creation.
function DoctrinePassiveService.GetSummonBonuses(unit)
	-- BLOCKED: requires summon system
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return nil end
	if docId == "DOC-CONJURER" then
		-- When summon system exists:
		-- return { hpBonus = 1.10, damageBonus = 1.10, healingBonus = 1.10 }
		return nil
	end
	return nil
end

--- BLOCKED: Warden — Earthen Resilience
--- Requires natural terrain detection and enemy movement cost modification.
--- Would grant allies +8% DR and +1 enemy movement cost within range 2.
function DoctrinePassiveService.GetWardenAuraDR(unit, allUnits)
	-- BLOCKED: requires natural terrain system and movement cost modification
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 1.0 end
	if docId == "DOC-WARDEN" then
		-- When terrain system supports it:
		-- if standingOnNaturalTerrain(unit) and hasAllyInRange(unit, allUnits, 2) then
		--     return 0.92  -- +8% DR
		-- end
		return 1.0
	end
	return 1.0
end

function DoctrinePassiveService.GetWardenEnemyMoveCostIncrease(unit, allUnits)
	-- BLOCKED: requires movement cost modification system
	return 0
end

return DoctrinePassiveService
