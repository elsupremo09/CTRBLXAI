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
local GameConstants = require(
	game:GetService("ReplicatedStorage"):WaitForChild("CTRBLXAI"):WaitForChild("Shared"):WaitForChild("GameConstants")
)

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
	-- Needs an actual main-hand weapon (unarmed units default weaponHandClass to "1H"). 2026-10-28.
	if not (unit.equipmentSlots and unit.equipmentSlots.MainHand) then return false end
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
	-- Item instances carry baseArchetypeId only (the old .type/.category/.itemType checks never
	-- matched, so Shieldbearer never saw a shield). Shield and Buckler are the off-hand shields.
	return offHand.baseArchetypeId == "OFF-SHIELD" or offHand.baseArchetypeId == "OFF-BUCKLER"
		or offHand.type == "Shield" or offHand.category == "Shield" or offHand.itemType == "shield"
end

--- Returns true if target has the Undead tag or an undead race.
local function isUndead(target)
	if not target then return false end
	local raceId = target.raceId or ""
	if raceId == "RACE-ZOMBIE" or raceId == "RACE-LICH" or raceId == "RACE-VAMPIRE" then
		return true
	end
	if target.tags and target.tags.Undead then return true end
	for _, inst in ipairs(target.statusInstances or {}) do
		if inst.id == "Undead" then return true end  -- Undead status (e.g. raised corpse)
	end
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
	-- Units never carry an .elevation field, so this used to compare 0 with 0 and the Dragoon passive
	-- never fired. Read the tile elevation (+5 while flying, same as TargetingService).
	if not (attacker.tileX and defender.tileX) then return false end
	local function effElev(u)
		local e = GameConstants.GetElevation(u.tileX, u.tileY)
		if StatusService.HasStatus(u, "Flight") then e = e + 5 end
		return e
	end
	return effElev(attacker) > effElev(defender)
end

--- Valid elemental tags for Elementalist tracking.
local VALID_ELEMENTS = {
	Fire = true, Ice = true, Water = true, Electric = true,
	Earth = true, Poison = true, Dark = true, Holy = true,
}

local function skillHasTag(skillDef, tag)
	if type(skillDef) ~= "table" or type(skillDef.tags) ~= "table" then return false end
	for _, t in ipairs(skillDef.tags) do
		if t == tag then return true end
	end
	return false
end

--- True when the skill carries the "Direct Damage" tag (DDS in the doctrine rules).
function DoctrinePassiveService.IsDirectDamageSkill(skillDef)
	return skillHasTag(skillDef, "Direct Damage")
end

--- Context + element for OnSkillResolved (2026-10-28), built from the skill tags.
--- mpSpent = MP actually paid (0 for HP / Blood casting pays HP, not MP).
function DoctrinePassiveService.BuildSkillContext(skillDef, mpSpent)
	local element = nil
	if type(skillDef) == "table" and type(skillDef.tags) == "table" then
		for _, t in ipairs(skillDef.tags) do
			if VALID_ELEMENTS[t] then element = t; break end
		end
	end
	return {
		spentMp = (mpSpent or 0) > 0,
		isDirectDamageSkill = skillHasTag(skillDef, "Direct Damage"),
		isHealingSkill = skillHasTag(skillDef, "Healing"),
		isHolySkill = skillHasTag(skillDef, "Holy"),
		isUtilitySkill = skillHasTag(skillDef, "Utility"),
	}, element
end

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
		-- _actedThisRound is the per-1000-CT-round flag BattleCoordinator maintains (was a wrong field
		-- name, hasActedThisRound, which nothing ever set). 2026-10-28.
		if defender and not defender._actedThisRound then
			mod = mod * 1.20
		end
	end

	-- DRAGOON — Aerial Supremacy: DDS +20% from higher elevation
	-- (melee defense-ignore from higher ground handled in GetDefenseIgnore)
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
		-- DB: the Wet bonus and the multi-target bonus stack ADDITIVELY (was multiplied). 2026-10-28.
		local sb = 0
		-- DB trigger: "Stormbringer's Electric-tagged SKILL hits a target that is Wet" -- Skills only (not
		-- basic attacks or items, which now pass their element / isSkill=false). 2026-10-29.
		if isSkill and defender and hasStatus(defender, "Wet") then
			sb = sb + 0.25
		end
		if isSkill and context and context.additionalTargetsHit and context.additionalTargetsHit > 0 then
			sb = sb + math.min(context.additionalTargetsHit * 0.05, 0.20)
		end
		mod = mod * (1.0 + sb)
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

-- skillDef / isPhysical (2026-10-28): Spellblade only boosts a Physical Direct Damage Skill with
-- Weapon Attack Power scaling (DB). With no skillDef (Info panel) Spellblade returns 1.0.
function DoctrinePassiveService.GetSkillPotencyModifier(unit, skillDef, isPhysical)
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 1.0 end

	-- SPELLBLADE — Arcane Edge: Skill Potency +10% on eligible Skills only
	if docId == "DOC-SPELLBLADE" then
		if skillDef and isPhysical and skillHasTag(skillDef, "Direct Damage") and skillHasTag(skillDef, "Weapon Scaling") then
			return 1.10
		end
		return 1.0
	end

	-- CHEMIST — Field Chemistry drawback: Skill Potency -25% (traded for consumable mastery). 2026-10-20
	-- Skills only: a consumable item (resolved as a pseudo-skill flagged isItem) is not a Skill and
	-- must not lose 25% (checklist fix 2026-10-29).
	if docId == "DOC-CHEMIST" then
		if skillDef and skillDef.isItem then return 1.0 end
		return 0.75
	end

	return 1.0
end

--------------------------------------------------
-- CONSUMABLE ITEM MODIFIERS (2026-10-20)
-- Chemist: Consumable Item RT Cost -20% (multiplier 0.80).
-- Artificer: Consumable Item Maximum Range +1 (flat tile bonus).
-- Both are doctrine passives; disabled by Break like the rest.
--------------------------------------------------
function DoctrinePassiveService.GetConsumableRtModifier(unit)
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 1.0 end
	if docId == "DOC-CHEMIST" then
		return 0.80
	end
	return 1.0
end

function DoctrinePassiveService.GetConsumableRangeBonus(unit)
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 0 end
	if docId == "DOC-ARTIFICER" then
		return 1
	end
	return 0
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

-- projectileType (2026-10-28): the attack's projectile type; melee (nil / "") gets no bonus.
function DoctrinePassiveService.GetProjectileRangeModifier(unit, projectileType)
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return 0 end
	if projectileType == nil or projectileType == "" then return 0 end

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

-- Battle-log line for doctrine effects the player otherwise cannot see (re-check 2026-10-29).
-- Deferred require: BattleVisualBroadcaster is never needed at load time here.
local function docLog(text, unitId)
	local ok, bvb = pcall(function() return (require :: any)(script.Parent.BattleVisualBroadcaster) end)
	if ok and bvb and bvb.Log then bvb.Log("buff", text, unitId) end
end

-- Paladin Divine Aegis (DB): "if the Skill healed an ally, that ally also gains +10% damage reduction
-- for 1 turn". Called by CombatResolver.ApplyOutcome for each unit a Paladin's skill really healed.
function DoctrinePassiveService.OnPaladinHealedAlly(caster, target, healed)
	if not (caster and target) or caster == target or (healed or 0) <= 0 then return end
	if target.side ~= caster.side then return end
	if getDoctrineId(caster) ~= "DOC-PALADIN" or isBroken(caster) then return end
	target._docPaladinDrTurnsRemaining = 1
	print(string.format("[DoctrinePassiveService] Paladin Divine Aegis: %s grants +10%% DR to %s", caster.name, target.name))
	docLog(`{target.name}: Divine Aegis -10% damage taken for 1 turn.`, target.id)
end

-- Geomancer Terrain Mastery (DB "Geomancer commits a Skill that creates or modifies terrain"): true
-- only while the unit is resolving one of its own Skills (set by CommandService doctrineBeginCast).
function DoctrinePassiveService.IsCastingSkill(unit)
	return unit ~= nil and unit._docCastingSkill == true
end

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
			docLog(`{unit.name} unleashes Vengeful Riposte (+20%).`, unit.id)
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
			docLog(`{unit.name}: Divine Aegis -10% damage taken for 1 turn.`, unit.id)
			-- Allies the Skill actually healed get their DR in CombatResolver.ApplyOutcome
			-- (DoctrinePassiveService.OnPaladinHealedAlly), so area heals cover every ally healed and a
			-- target that was not healed gets nothing (checklist fix 2026-10-29).
		end
	end

	-- Once-per-turn flags below are marked at COMMIT for channeled skills (MarkSkillCommitted);
	-- the deferred activation (context.deferred) must not mark them again in a later turn.
	local deferred = context and context.deferred
	-- === Arcanist — mark first Skill consumed ===
	if docId == "DOC-ARCANIST" and not isBroken(unit) and not deferred then
		unit._docArcanistUsedSkill = true
	end

	-- === Trickster — mark first Utility Skill consumed ===
	if docId == "DOC-TRICKSTER" and not isBroken(unit) and not deferred then
		local isUtility = context and context.isUtilitySkill
		if isUtility then
			unit._docTricksterUsedUtility = true
		end
	end

	-- === Shieldbearer — consume Guard RT bonus ===
	if docId == "DOC-SHIELDBEARER" and unit._docShieldbearerGuardRtReady and not deferred then
		unit._docShieldbearerGuardRtReady = false
	end
end

--- Channeled skill COMMIT (2026-10-28): its RT and MP discounts were decided now, so the
--- once-per-turn Arcanist / Trickster / Shieldbearer flags are consumed now too.
function DoctrinePassiveService.MarkSkillCommitted(unit, context)
	if not unit then return end
	local docId = getDoctrineId(unit)
	if docId == "DOC-ARCANIST" then unit._docArcanistUsedSkill = true end
	if docId == "DOC-TRICKSTER" and context and context.isUtilitySkill then unit._docTricksterUsedUtility = true end
	if docId == "DOC-SHIELDBEARER" then unit._docShieldbearerGuardRtReady = false end
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
		if not unit._docSentinelCharged then
			docLog(`{unit.name} is charged: next damage skill +20% (Vengeful Riposte).`, unit.id)
		end
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
	unit._docCastingSkill = nil  -- safety: a cast that never reached its after-skill step
	-- Twinblade TRG-016 safety net (Break changes also sync immediately via StatusService).
	DoctrinePassiveService.SyncDualWield(unit)

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

	-- Gunner Suppression: a pending turn becomes ACTIVE for this turn (Move -1), then counts down.
	-- (Decrementing first, as before, ended a 1-turn suppression before the victim could move.)
	if unit._docGunnerSuppressionTurns and unit._docGunnerSuppressionTurns > 0 then
		unit._docGunnerSuppressActive = true
		unit._docGunnerSuppressionTurns = unit._docGunnerSuppressionTurns - 1
	else
		unit._docGunnerSuppressActive = false
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
-- DEFENSE IGNORE (Dragoon Aerial Supremacy)
-- USER RULING 2026-10-28 (replaces the DB "ignore 50% of positional defense from elevation",
-- which could never trigger: elevation defense only exists when the TARGET is higher).
-- Dragoon with a MELEE weapon, attacking from higher elevation than the target, ignores 50% of
-- the target's Defense. Applies to Direct Damage Skills AND Basic Attacks (user ruling
-- 2026-10-28). skillDef nil = Basic Attack. Returns the fraction to ignore (0.0-1.0).
-- Called from CombatResolver.ResolveSkill / ResolveBasicAttack. Pure read (AI-preview safe).
--------------------------------------------------

function DoctrinePassiveService.GetDefenseIgnore(attacker, defender, skillDef)
	local docId = getDoctrineId(attacker)
	if docId ~= "DOC-DRAGOON" or isBroken(attacker) then return 0 end
	-- Melee weapon = no projectile type (same test Juggernaut uses).
	if attacker.weaponProjectileType and attacker.weaponProjectileType ~= "" then return 0 end
	if skillDef ~= nil and not skillHasTag(skillDef, "Direct Damage") then return 0 end
	if hasElevationAdvantage(attacker, defender) then
		return 0.50
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
		-- DB Passive_Effect: Dark-tagged debuffs only (2026-10-28; Poison removed).
		if debuffElement == "Dark" then
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
	if (target._docGunnerSuppressionTurns or 0) < duration then
		docLog(`{target.name} is suppressed: Move -1 for {duration} turn(s).`, target.id)
	end
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
	if unit._docGunnerSuppressActive then
		return -1
	end
	return 0
end

--------------------------------------------------
-- BLOCKED DOCTRINE PASSIVES
-- These doctrines' passives require systems that don't exist yet.
-- Functions created for forward-compatibility; return neutral values.
--------------------------------------------------

--- Thief — Fortune Hand (USER RULING 2026-10-28, replaces the DB "add 50% of Thief Fortune to
--- Expedition Fortune for that reward", which had no reward roll to act on: Steal takes the
--- target's real gear piece). A successful steal (Steal skill, or Mug's KO-steal) by a Thief also
--- earns gold equal to the Thief's level. Player side only; paid with battle gold on a win.
function DoctrinePassiveService.GetStealGold(unit)
	if getDoctrineId(unit) ~= "DOC-THIEF" or isBroken(unit) then return 0 end
	if unit.side ~= "Player" then return 0 end
	return math.max(0, math.floor(unit.level or 1))
end

--- Twinblade — Dual-Wield Discipline (built 2026-10-28). DB project_rules 56/63/64, TRG-016:
--- two naturally legal 1H weapons (MainHand + a 1H weapon in OffHand), each kept at 75% of its
--- numerical properties; Break inactivates the off hand without unequipping it. A unit that is
--- not a Twinblade (or is Broken) keeps the off-hand weapon assigned but it does nothing.
local DUAL_WIELD_SCALE = 0.75

local function natural1HWeaponArch(item)
	if not item then return nil end
	local WeaponData = (require :: any)(game:GetService("ReplicatedStorage"):WaitForChild("Content"):WaitForChild("WeaponData"))
	local arch = WeaponData.GetByArchetypeId(item.baseArchetypeId)
	if arch and arch.category == "Weapon" and arch.handClass == "1H" then return arch end
	return nil
end

--- True when this archetype may go in the OffHand slot of this unit as a second weapon.
function DoctrinePassiveService.CanEquipOffHandWeapon(unit, archetype)
	if not (unit and archetype) then return false end
	if getDoctrineId(unit) ~= "DOC-TWINBLADE" then return false end
	if archetype.category ~= "Weapon" or archetype.handClass ~= "1H" then return false end
	local mh = unit.equipmentSlots and unit.equipmentSlots.MainHand
	return mh == nil or natural1HWeaponArch(mh) ~= nil
end

--- Dual wield is ACTIVE: Twinblade, not Broken, natural 1H weapon in both hands.
function DoctrinePassiveService.IsDualWieldEnabled(unit)
	if getDoctrineId(unit) ~= "DOC-TWINBLADE" or isBroken(unit) then return false end
	local slots = unit.equipmentSlots
	if not slots then return false end
	return natural1HWeaponArch(slots.MainHand) ~= nil and natural1HWeaponArch(slots.OffHand) ~= nil
end

--- TRG-016 (Break): if the unit's live dual-wield state no longer matches its built stats, rebuild
--- once so the off hand goes inactive (main hand back to 100%) or active again. Idempotent: does
--- nothing when already in sync. Deferred require of EquipmentService (cycle-safe).
function DoctrinePassiveService.SyncDualWield(unit)
	if not unit or getDoctrineId(unit) ~= "DOC-TWINBLADE" then return end
	if (unit.dualWieldActive == true) ~= DoctrinePassiveService.IsDualWieldEnabled(unit) then
		(require :: any)(script.Parent.EquipmentService).RebuildUnitStats(unit)
	end
end

--- Numerical-property retention for each weapon while dual wielding (1.0 otherwise).
function DoctrinePassiveService.GetDualWieldScaling(unit)
	return if DoctrinePassiveService.IsDualWieldEnabled(unit) then DUAL_WIELD_SCALE else 1.0
end

--- BLOCKED: Conjurer — Bound Host
--- Requires summon system.
--- Would grant summons +10% Max HP, +10% damage, +10% healing at creation.
function DoctrinePassiveService.GetSummonBonuses(unit)
	-- BLOCKED: requires summon system
	local docId = getDoctrineId(unit)
	if not docId or isBroken(unit) then return nil end
	if docId == "DOC-CONJURER" then
		-- Summons exist now (2026-10-28): snapshot at creation in CommandService.spawnSummonFor
		-- (Max HP, damage via summonDamageMult, healing via summonHealMult).
		return { hpBonus = 1.10, damageBonus = 1.10, healingBonus = 1.10 }
	end
	return nil
end

--- Warden — Earthen Resilience (built 2026-10-28; tile effects + move-cost hooks exist now).
--- "Natural terrain" = the tile carries no terrain effect created by a unit (map terrain and
--- floor effects count as natural; Geomancer / skill-made terrain does not).
local function isOnNaturalTerrain(unit)
	if not (unit and unit.tileX and unit.tileY) then return false end
	local ok, tes = pcall(function() return (require :: any)(script.Parent.TileEffectService) end)
	if not ok or not tes or not tes.GetTileEffect then return true end
	local eff = tes.GetTileEffect(unit.tileX, unit.tileY)
	if not eff or not eff.ownerId then return true end
	local units = StatusService.GetAuraUnits and StatusService.GetAuraUnits() or nil
	for _, u in ipairs(units or {}) do
		if u.id == eff.ownerId then return false end
	end
	return true
end

--- A standing, unbroken Warden on natural terrain.
local function isActiveWarden(u)
	return u and u.isAlive and getDoctrineId(u) == "DOC-WARDEN" and not isBroken(u) and isOnNaturalTerrain(u)
end

--- Damage-received multiplier: 0.92 when this unit stands on natural terrain within Range 2 of an
--- active same-side Warden (the Warden itself included). Multiple Wardens do not stack.
function DoctrinePassiveService.GetWardenAuraDR(unit, allUnits)
	if not unit or not allUnits or not isOnNaturalTerrain(unit) then return 1.0 end
	for _, w in ipairs(allUnits) do
		if w.side == unit.side and chebyshevDist(unit, w) <= 2 and isActiveWarden(w) then
			return 0.92
		end
	end
	return 1.0
end

--- Area denial: +1 movement cost for a mover entering a tile within Range 2 of an active
--- ENEMY Warden. Multiple Wardens do not stack. Returns 0 or 1.
function DoctrinePassiveService.GetWardenEnemyMoveCostIncrease(mover, tileX, tileY, allUnits)
	if not mover or not allUnits then return 0 end
	for _, w in ipairs(allUnits) do
		if w.side ~= mover.side and w.tileX and w.tileY
			and math.max(math.abs(w.tileX - tileX), math.abs(w.tileY - tileY)) <= 2
			and isActiveWarden(w) then
			return 1
		end
	end
	return 0
end

--- Wardens on the other side that currently project area denial (for the move search).
function DoctrinePassiveService.GetActiveEnemyWardens(mover, allUnits)
	local out = {}
	if not mover then return out end
	for _, w in ipairs(allUnits or {}) do
		if w.side ~= mover.side and w.tileX and isActiveWarden(w) then table.insert(out, w) end
	end
	return out
end

return DoctrinePassiveService
