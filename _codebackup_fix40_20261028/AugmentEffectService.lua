-- AugmentEffectService.lua
-- CTRBLXAI | Augment Effect Resolution Service
--
-- Resolves augment effects during combat.  Called by CombatResolver
-- and CommandService when skills are used.
--
-- Five hook points in the combat pipeline:
--   1. GetMpCostMultiplier   — before MP deduction     (CommandService)
--   2. OnDamageCalculation   — during ResolveSkill      (CombatResolver)
--   3. OnDamageResolved      — after damage, target alive (CombatResolver)
--   4. OnKill                — target dies from skill    (CombatResolver)
--   5. OnSkillComplete       — after entire skill        (CombatResolver)
--
-- Important rules:
--   • Recursion guard: augment-triggered effects do NOT retrigger augments.
--   • "Once per supported resolution" = once per skill use, not per AOE target.
--   • Log every activation with [AugmentEffect] prefix.
--   • AugmentData effect fields are prose — status mappings are hardcoded.

local StatusService = require(script.Parent.StatusService)
local UnitSchema = require(script.Parent.UnitSchema) -- Phase 1 augment fix (2026-10-24): Mana Rupture bonus damage via the shield-respecting damage path
local BattleVisualBroadcaster = require(script.Parent.BattleVisualBroadcaster)
local TileEffectService = require(script.Parent.TileEffectService)       -- Phase 4 augment fix (2026-10-24): terrain-ground augments
local DisplacementService = require(script.Parent.DisplacementService)   -- Phase 4 augment fix (2026-10-24): displacement augments

local AugmentData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("AugmentData")
)

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

-- Shared tags-only augment compatibility (2026-10-26).
local AugmentCompatibility = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("AugmentCompatibility")
)

local AugmentEffectService = {}

-- [LOG] Augment debug spam gate (2026-10-16). GetMpCostMultiplier is called by the
-- AI once per skill candidate during EVERY scoring pass (not once per committed
-- action), so its per-augment "MP cost multiplier ×N" print fired hundreds of times
-- per battle and buried real signals in Output. The computation is read-only (it only
-- reads AugmentData.costFormula and multiplies a local — no state mutation), so this
-- is purely a logging-volume issue. Gate the multiplier print behind this flag
-- (default false); flip to true only when debugging augment MP math.
local DEBUG_AUGMENT = false

--------------------------------------------------
-- MODULE STATE
--------------------------------------------------

-- Recursion guard: prevents augment-triggered effects (DoT damage,
-- displacement collisions) from retriggering augments.
local _processingAugment = false

-- Resolution tracking: ensures "Once per supported resolution" augments
-- fire exactly once per skill use, not per AOE target.
-- Call BeginResolution() before processing a skill's targets and
-- EndResolution() after the skill fully resolves.
local _firedThisResolution = {}

-- Pending displacement set by OnDamageResolved.  Caller queries
-- GetPendingDisplacement() after each target to see if a displacement
-- effect was triggered.
local _pendingDisplacement = nil

--------------------------------------------------
-- RESOLUTION LIFECYCLE
--------------------------------------------------

function AugmentEffectService.BeginResolution()
	_firedThisResolution = {}
	_pendingDisplacement = nil
end

function AugmentEffectService.EndResolution()
	_firedThisResolution = {}
	_pendingDisplacement = nil
end

function AugmentEffectService.GetPendingDisplacement()
	local d = _pendingDisplacement
	_pendingDisplacement = nil
	return d
end

local function markFired(augmentId)
	_firedThisResolution[augmentId] = true
end

local function hasFired(augmentId)
	return _firedThisResolution[augmentId] == true
end

--------------------------------------------------
-- LOOKUP TABLES  (hardcoded because DB effect field is prose)
--------------------------------------------------

-- Debuff: augment ID → status to apply on DEFENDER.
-- Includes future IDs the designer has planned but may not yet exist
-- in AugmentData; the service is lenient about missing definitions.
local STATUS_DELIVERY_MAP = {
	["AUG-BLEEDING-EDGE-SUPPORT"] = "Bleed",
	["AUG-VENOMOUS-SUPPORT"]      = "Poison",
	["AUG-BLINDING-SUPPORT"]      = "Blind",
	["AUG-CRIPPLING-SUPPORT"]     = "Crippled",
	["AUG-SILENCING-SUPPORT"]     = "Silence",
	["AUG-SLOWING-SUPPORT"]       = "Slow",
	["AUG-WEAKENING-SUPPORT"]     = "Weakened",
	["AUG-FREEZING-SUPPORT"]      = "Frozen",
	["AUG-MANA-BURN-SUPPORT"]     = "Mana Burn",
	["AUG-DROWNING-SUPPORT"]      = "Drowning",
	["AUG-CONFUSING-SUPPORT"]     = "Confuse",
	["AUG-SLEEP-SUPPORT"]         = "Sleep",
	["AUG-PETRIFY-SUPPORT"]       = "Petrify",
	["AUG-CURSING-SUPPORT"]       = "Cursed",
	["AUG-BREAKING-SUPPORT"]      = "Break",
	["AUG-STUNNING-SUPPORT"]      = "Stun",
	-- Augment coverage fix (2026-10-24): these authored debuff-support augments had no
	-- effect handler; they deliver their named status on a damaging hit exactly like the
	-- siblings above (all target existing GameConstants.STATUSES ids).
	["AUG-BREAK-SUPPORT"]         = "Break",
	["AUG-BURNING-SUPPORT"]       = "Burn",
	["AUG-DISARMING-SUPPORT"]     = "Disarmed",
	["AUG-MUTING-SUPPORT"]        = "Mute",
	["AUG-PINNING-SUPPORT"]       = "Pinned",
	["AUG-WETTING-SUPPORT"]       = "Wet",
	-- Timing augment delivering a status on hit (2026-10-24): Sluggish Blow applies Slow.
	["AUG-SLUGGISH-BLOW"]         = "Slow",
}

-- Buff: augment ID → status to apply on ATTACKER (self-buff).
-- Card durations (DB augments, "apply <buff> to the target for N turns"). CT-based statuses use
-- 1000 CT per turn (one round), the convention used elsewhere (e.g. Zombie 3000 CT = 3 turns).
local SUPPORT_TURNS = {
	Haste = 2, Regeneration = 3, Recharge = 3, Blessed = 2, Enlightened = 2, Rush = 1, Frenzy = 2,
}

local BUFF_DELIVERY_MAP = {
	["AUG-HASTE-SUPPORT"]         = "Haste",
	["AUG-REGENERATION-SUPPORT"]  = "Regeneration",
	["AUG-RECHARGE-SUPPORT"]      = "Recharge",
	["AUG-FRENZY-SUPPORT"]        = "Frenzy",
	["AUG-RUSH-SUPPORT"]          = "Rush",
	["AUG-ENLIGHTENED-SUPPORT"]   = "Enlightened",
	["AUG-ENLIGHTEN-SUPPORT"]     = "Enlightened",   -- DB spelling variant
	["AUG-BLESSED-SUPPORT"]       = "Blessed",
}

-- Element conversion: augment ID → element the skill's damage becomes (2026-10-24 fix).
-- Consumed by OnDamageCalculation (now wired into CombatResolver.ResolveSkill).
local ELEMENT_CONVERSION_MAP = {
	["AUG-FIRE-CONVERSION"]     = "Fire",
	["AUG-ICE-CONVERSION"]      = "Ice",
	["AUG-ELECTRIC-CONVERSION"] = "Electric",
	["AUG-EARTH-CONVERSION"]    = "Earth",
	["AUG-HOLY-CONVERSION"]     = "Holy",
	["AUG-DARK-CONVERSION"]     = "Dark",
	["AUG-POISON-CONVERSION"]   = "Poison",
}

-- Stat Scaling: augment ID → stat name that replaces STR for weapon
-- damage calculation.
local STAT_SCALING_MAP = {
	["AUG-AGI-SCALING"] = "AGI",
	["AUG-INT-SCALING"] = "INT",
	["AUG-VIT-SCALING"] = "VIT",
	["AUG-DEX-SCALING"] = "DEX",
	["AUG-LUK-SCALING"] = "LUK",
}

-- Families handled by each hook.  Used for catch-all stub logging so
-- that unimplemented augments get a helpful message instead of silence.
local DAMAGE_RESOLVED_FAMILIES = {
	["Debuff"] = true,
	["Buff"]   = true,
	["Recovery"]        = true,
	["Purge"]           = true,
	["Displacement"]    = true,
	["Terrain Effect"]  = true,
}

local KILL_FAMILIES = {
	["Kill Trigger"]    = true,
	["Death Explosion"] = true,
	["Reward"]          = true,
}

local SKILL_COMPLETE_FAMILIES = {
	["Timing"]    = true,
	["Defensive"] = true,
}

--------------------------------------------------
-- INTERNAL HELPERS
--------------------------------------------------

local function getAugmentName(augmentId)
	local def = AugmentData[augmentId]
	return def and def.name or augmentId
end

local function getAugmentFamily(augmentId)
	local def = AugmentData[augmentId]
	return def and def.family or "Unknown"
end

local function getDeliveryFrequency(augmentId)
	local def = AugmentData[augmentId]
	return def and def.deliveryFrequency or "Once per supported resolution"
end

--- Parse "MP Cost ×1.20" → 1.20.  Returns nil for non-MP formulas.
local function parseMpMultiplier(costFormula)
	if not costFormula then return nil end
	if not string.find(costFormula, "MP Cost") then return nil end
	-- Number always appears after "MP Cost" and some non-digit chars (×, space)
	local num = string.match(costFormula, "MP Cost[^%d]*(%d+%.%d+)")
	if not num then return nil end
	return tonumber(num)
end

--- Returns true if a unit has any active debuff.
local function hasAnyDebuff(unit)
	if not unit.statusInstances then return false end
	for _, inst in ipairs(unit.statusInstances) do
		local def = GameConstants.STATUSES[inst.id]
		if def and def.kind == "Debuff" then
			return true
		end
	end
	return false
end

--- Remove one random purgeable buff.
--- Purgeable = kind "Buff" and not undispellable.
--- Returns removed status ID or nil.
local function removeRandomBuff(unit)
	if not unit.statusInstances then return nil end
	local candidates = {}
	for i, inst in ipairs(unit.statusInstances) do
		local def = GameConstants.STATUSES[inst.id]
		if def and def.kind == "Buff" and not def.undispellable then
			table.insert(candidates, i)
		end
	end
	if #candidates == 0 then return nil end
	local pick = candidates[math.random(1, #candidates)]
	local removedId = unit.statusInstances[pick].id
	table.remove(unit.statusInstances, pick)
	return removedId
end

--- Remove ALL purgeable buffs.  Returns list of removed status IDs.
local function removeAllBuffs(unit)
	if not unit.statusInstances then return {} end
	local removed = {}
	local i = 1
	while i <= #unit.statusInstances do
		local inst = unit.statusInstances[i]
		local def = GameConstants.STATUSES[inst.id]
		if def and def.kind == "Buff" and not def.undispellable then
			table.insert(removed, inst.id)
			table.remove(unit.statusInstances, i)
		else
			i = i + 1
		end
	end
	return removed
end

--- Remove one random debuff.  Returns removed status ID or nil.
local function removeRandomDebuff(unit)
	if not unit.statusInstances then return nil end
	local candidates = {}
	for i, inst in ipairs(unit.statusInstances) do
		local def = GameConstants.STATUSES[inst.id]
		if def and def.kind == "Debuff" then
			table.insert(candidates, i)
		end
	end
	if #candidates == 0 then return nil end
	local pick = candidates[math.random(1, #candidates)]
	local removedId = unit.statusInstances[pick].id
	table.remove(unit.statusInstances, pick)
	return removedId
end

--- Heal a unit directly.  Returns actual HP restored.
--- NOTE: Bypasses CombatResolver.BindApplyHealing.  Augment healing is
--- intentionally direct to stay outside the bound-function pipeline and
--- avoid recursive trigger chains.
local function healUnit(unit, amount)
	if not unit.isAlive then return 0 end
	-- Festering Wound anti-heal (2026-10-25): reduce augment-sourced direct healing too.
	local _hrm = StatusService.GetHealingReceivedMult(unit)
	if _hrm ~= 1 then amount = math.max(0, math.floor(amount * _hrm)) end
	local missing = (unit.maxHp or 0) - (unit.currentHp or 0)
	local actual = math.min(missing, math.max(0, math.floor(amount)))
	unit.currentHp = (unit.currentHp or 0) + actual
	if actual > 0 then StatusService.WeakenVenomOnHeal(unit) end  -- healing weakens Venom (2026-10-26)
	return actual
end

--- Restore MP directly.  Returns actual MP restored.
local function restoreMp(unit, amount)
	if not unit.currentMp or not unit.maxMp then return 0 end
	local missing = unit.maxMp - unit.currentMp
	local actual = math.min(missing, math.max(0, math.floor(amount)))
	unit.currentMp = unit.currentMp + actual
	return actual
end

--- Should this augment be skipped because it already fired this
--- resolution and its delivery frequency is once-per-resolution?
local function shouldSkipForFrequency(augmentId)
	if not hasFired(augmentId) then return false end
	local freq = getDeliveryFrequency(augmentId)
	-- Per-target frequencies: fire on every hit/target, no skip
	if freq == "Per qualifying target" or freq == "Per successful hit"
		or freq == "Once per supported resolution" then
		return false
	end
	return true  -- truly once-per-skill (future use)
end

--------------------------------------------------
-- PUBLIC: GetAugmentsForSkill
--
-- Resolves which augments are attached to a given skill
-- on a given unit.
--
-- Unit shape:
--   unit.selectedDoctrineSkill = "DOC-BERSERKER-01"
--   unit.doctrineAugments     = { "AUG-X", "AUG-Y" }
--   unit.skillLoadout = {
--       slot2 = { skillId = "SKL-X", augments = { "AUG-A", "AUG-B" } },
--       slot3 = ..., slot4 = ...
--   }
--------------------------------------------------

-- Only augments that currently FIT the skill are active (tags-only rule, 2026-10-26). An
-- augment that stopped fitting (e.g. a weapon swap changed a "Weapon Shape" skill from Single
-- to Area) shows greyed out in the loadout and does nothing in battle. Also densifies the
-- 2-slot list: an augment in slot 2 with slot 1 empty is no longer dropped by ipairs callers.
local function activeAugments(unit: any, skillId: any, list: any): { string }
	local out = {}
	if type(list) ~= "table" then return out end
	local weapon = AugmentCompatibility.WeaponProfileFromUnit(unit)
	for i = 1, 2 do
		local augId = list[i]
		if augId and AugmentCompatibility.Check(skillId, augId, weapon) then
			table.insert(out, augId)
		end
	end
	return out
end

function AugmentEffectService.GetAugmentsForSkill(unit, skillId)
	if not unit or not skillId then return {} end

	-- Mute: disables skill augments only (base skill remains usable). DB
	-- (elements_statuses id 63): "Disables skill augments only." Suppress at
	-- this single choke point so both the MP-cost path and the damage path
	-- see no augments while Mute is active — mirrors how Break disables passives.
	if StatusService.HasStatus(unit, "Mute") then
		return {}
	end

	-- Doctrine skill (slot 1)
	if skillId == unit.selectedDoctrineSkill then
		return activeAugments(unit, skillId, unit.doctrineAugments)
	end

	-- Skill loadout (slots 2, 3, 4)
	if unit.skillLoadout then
		for _, slotKey in ipairs({ "slot2", "slot3", "slot4" }) do
			local slotData = unit.skillLoadout[slotKey]
			if slotData and slotData.skillId == skillId then
				return activeAugments(unit, skillId, slotData.augments)
			end
		end
	end

	return {}
end

--------------------------------------------------
-- 1. GetMpCostMultiplier
--
-- Called by CommandService BEFORE the MP check.
-- Reads costFormula from AugmentData for each augment attached
-- to this skill and multiplies together all MP cost multipliers.
--
-- Returns: number  (1.0 = no change)
--------------------------------------------------

function AugmentEffectService.GetMpCostMultiplier(unit, skillId)
	local augmentIds = AugmentEffectService.GetAugmentsForSkill(unit, skillId)
	if #augmentIds == 0 then return 1.0 end

	local finalMultiplier = 1.0

	for _, augId in ipairs(augmentIds) do
		local augDef = AugmentData[augId]
		if augDef and augDef.costFormula then
			local mp = parseMpMultiplier(augDef.costFormula)
			if mp then
				finalMultiplier = finalMultiplier * mp
				if DEBUG_AUGMENT then
					print(string.format(
						"[AugmentEffect] %s MP cost multiplier ×%.2f",
						augDef.name, mp
					))
				end
			end
		end
	end

	return finalMultiplier
end

-- RT cost multiplier from attached augments: parses "RT Cost ×N" (e.g. Shared Resolve
-- "MP Cost ×3.00; RT Cost ×2.00" -> 2.00). Only active (compatible) augments count. 1.0 if none.
function AugmentEffectService.GetRtCostMultiplier(unit, skillId)
	local mult = 1.0
	for _, augId in ipairs(AugmentEffectService.GetAugmentsForSkill(unit, skillId)) do
		local augDef = AugmentData[augId]
		local f = augDef and augDef.costFormula
		if f and string.find(f, "RT Cost") then
			local num = tonumber(string.match(f, "RT Cost[^%d]*(%d+%.?%d*)"))
			if num then
				mult = mult * num
			end
		end
	end
	return mult
end

-- Shared Resolve (AUG-SHARED-RESOLVE): the supported self-buff goes to every standing ally.
function AugmentEffectService.HasSharedResolve(unit, skillId): boolean
	for _, augId in ipairs(AugmentEffectService.GetAugmentsForSkill(unit, skillId)) do
		if augId == "AUG-SHARED-RESOLVE" then
			return true
		end
	end
	return false
end

--------------------------------------------------
-- 2. OnDamageCalculation
--
-- Called during ResolveSkill to modify the damage calculation.
-- Families: Stat Scaling, Conditional Amplifier, Element Conversion,
--           Penetration.
--
-- Returns: {
--   damageMultiplier = number (1.0 default),
--   elementOverride  = string or nil,
--   statOverride     = string or nil  ("AGI","INT","VIT","DEX","LUK"),
--   armorPiercing    = number or nil  (fraction of defense to ignore),
-- }
--------------------------------------------------

function AugmentEffectService.OnDamageCalculation(attacker, defender, skillDef, augmentIds)
	local result = {
		damageMultiplier = 1.0,
		elementOverride  = nil,
		statOverride     = nil,
		armorPiercing    = nil,
	}

	if not augmentIds or #augmentIds == 0 then return result end

	for _, augId in ipairs(augmentIds) do
		local augName = getAugmentName(augId)
		local family  = getAugmentFamily(augId)

		-- ===== STAT SCALING =====
		if STAT_SCALING_MAP[augId] then
			result.statOverride = STAT_SCALING_MAP[augId]
			print(string.format(
				"[AugmentEffect] %s triggered: weapon damage stat → %s",
				augName, result.statOverride
			))

		-- ===== CONDITIONAL AMPLIFIER =====
		elseif augId == "AUG-PREDATOR-STRIKE" then
			-- +25% damage if target has any debuff
			if hasAnyDebuff(defender) then
				result.damageMultiplier = result.damageMultiplier * 1.25
				print(string.format(
					"[AugmentEffect] %s triggered on %s (+25%% damage, target has debuff)",
					augName, defender.name
				))
			end

		elseif augId == "AUG-SHATTER-BLOW" then
			-- +30% damage if target has Break
			if StatusService.HasStatus(defender, "Break") then
				result.damageMultiplier = result.damageMultiplier * 1.30
				print(string.format(
					"[AugmentEffect] %s triggered on %s (+30%% damage, target has Break)",
					augName, defender.name
				))
			end

		elseif augId == "AUG-VENOM-BURST" then
			-- +40% damage if target has Poison or Venom
			if StatusService.HasStatus(defender, "Poison")
				or StatusService.HasStatus(defender, "Venom") then
				result.damageMultiplier = result.damageMultiplier * 1.40
				print(string.format(
					"[AugmentEffect] %s triggered on %s (+40%% damage, target has Poison/Venom)",
					augName, defender.name
				))
			end

		-- ===== PENETRATION =====
		elseif augId == "AUG-ARMOR-PIERCING" then
			result.armorPiercing = 0.50
			print(string.format(
				"[AugmentEffect] %s triggered: ignore 50%% defense", augName
			))

		-- ===== ELEMENT CONVERSION  (2026-10-24: wired) =====
		elseif ELEMENT_CONVERSION_MAP[augId] then
			result.elementOverride = ELEMENT_CONVERSION_MAP[augId]
			print(string.format(
				"[AugmentEffect] %s: damage element converted to %s",
				augName, result.elementOverride
			))

		-- ===== CONDITIONAL AMPLIFIER — remaining (2026-10-24: wired) =====
		elseif augId == "AUG-HEIGHTS-ADVANTAGE" then
			local aElev = GameConstants.GetElevation and attacker.tileX and GameConstants.GetElevation(attacker.tileX, attacker.tileY) or 0
			local dElev = GameConstants.GetElevation and defender.tileX and GameConstants.GetElevation(defender.tileX, defender.tileY) or 0
			if aElev > dElev then
				result.damageMultiplier = result.damageMultiplier * 1.35
				print(string.format("[AugmentEffect] %s triggered (+35%% from higher ground)", augName))
			end

		elseif augId == "AUG-DESPERATION" then
			local hpFrac = (attacker.maxHp and attacker.maxHp > 0) and ((attacker.currentHp or 0) / attacker.maxHp) or 1
			if hpFrac < 0.30 then
				result.damageMultiplier = result.damageMultiplier * 1.60
				print(string.format("[AugmentEffect] %s triggered (+60%%, caster below 30%% HP)", augName))
			end

		elseif augId == "AUG-FOCUSED-FINISHER" then
			local hpFrac = (defender.maxHp and defender.maxHp > 0) and ((defender.currentHp or 0) / defender.maxHp) or 1
			if hpFrac < 0.25 then
				result.damageMultiplier = result.damageMultiplier * 1.50
				print(string.format("[AugmentEffect] %s triggered (+50%%, target below 25%% HP)", augName))
			end

		-- PRIORITY SURGE (reworked 2026-10-26, Timing): +30%% vs a target that has NOT yet taken a turn
		-- in the current 1000-CT round. defender._actedThisRound is maintained by BattleCoordinator
		-- (reset for all units at each round boundary; set true when a unit's turn opens). Per-target,
		-- so it evaluates correctly for each target of an AOE skill.
		elseif augId == "AUG-PRIORITY-SURGE" then
			if not defender._actedThisRound then
				result.damageMultiplier = result.damageMultiplier * 1.30
				print(string.format("[AugmentEffect] %s triggered (+30%%, %s has not acted this round)", augName, defender.name))
			end

		-- Families processed in other hooks are silently skipped here.
		end
	end

	return result
end

--------------------------------------------------
-- 3. OnDamageResolved
--
-- Called AFTER damage is applied and target is still alive.
-- Trigger condition: damage > 0.
-- Families: Debuff, Buff, Recovery, Purge,
--           Displacement, Terrain Effect.
--
-- Returns: nil
--------------------------------------------------

-- Battle unit-list cache (2026-10-24 augment fix). Same proven pattern TileEffectService
-- uses: CommandService passes the live state.units ref at resolution start so radius /
-- push augments can see the field. nil-safe everywhere it is read.
local _augAllUnits = nil
function AugmentEffectService.SetBattleUnits(units)
	if type(units) == "table" then _augAllUnits = units end
end

-- Summon handler injected by CommandService (2026-10-24): spawns a decoy/turret next to a
-- caster. DI because spawnSummonFor is CommandService-local; nil-safe (no-op if not wired).
local _summonHandler = nil
function AugmentEffectService.SetSummonHandler(fn)
	if type(fn) == "function" then _summonHandler = fn end
end

-- Channel-interrupt handler injected by Main (2026-10-24): BattleCoordinator.InterruptChanneling.
-- DI keeps AugmentEffectService free of a BattleCoordinator require. nil-safe (no-op if unwired).
local _interruptHandler = nil
function AugmentEffectService.SetInterruptHandler(fn)
	if type(fn) == "function" then _interruptHandler = fn end
end

-- Knockback handler injected by Main (2026-10-26, user-approved fix): CommandService's shared
-- knockback (moves the unit, springs traps, collision / fall damage, entry effects, client
-- visual). Before this, the four displacement augments called ResolvePush, which only
-- COMPUTES a result, and threw the result away -- nobody ever moved.
local _knockbackHandler = nil
function AugmentEffectService.SetKnockbackHandler(fn)
	if type(fn) == "function" then _knockbackHandler = fn end
end
local function augDisplace(pusher, target, force, dir, distance, isPull)
	if _knockbackHandler then
		return _knockbackHandler(pusher, target, force, dir, distance, isPull)
	end
	warn("[AugmentEffect] knockback handler not wired -- displacement skipped")
	return nil
end

-- Chebyshev-radius enemy scan over the cached unit list (nil-safe; empty when no list).
local function enemiesWithin(originX, originY, radius, attackerSide)
	local out = {}
	if not (_augAllUnits and originX and originY) then return out end
	for _, u in ipairs(_augAllUnits) do
		if u.isAlive and u.side ~= attackerSide and not u.isGroundTarget and u.tileX and u.tileY then
			if math.max(math.abs(u.tileX - originX), math.abs(u.tileY - originY)) <= radius then
				table.insert(out, u)
			end
		end
	end
	return out
end

-- Kill-credit rule (user ruling 2026-10-26; DB trigger_safety TRG-006/TRG-007). Kill augments
-- fire only when the skill defeats a REAL enemy of the caster:
--   * opposite side and not Neutral (a neutral that turned hostile has already switched its
--     side to "Enemy", so it counts; allies and untouched neutrals never do)
--   * not summoned by a skill, augment or item (SpawnSummon stamps isSummon and
--     killTriggerEligible = false on every summon)
--   * never revived this battle (_revivedThisBattle, stamped at every revive site)
-- Objects never reach OnKill (only units die). Applies both ways: enemy casters get nothing
-- for killing summoned or revived player units either.
function AugmentEffectService.IsKillCreditEligible(attacker: any, defender: any): boolean
	if not (attacker and defender) then return false end
	if defender.side == attacker.side or defender.side == "Neutral" then return false end
	if defender.isSummon or defender.killTriggerEligible == false then return false end
	if defender._revivedThisBattle then return false end
	return true
end

-- Like enemiesWithin, but untouched Neutrals are excluded: the "enemies only" death effects
-- (Toxic / Shattering / Terrifying Death, Overkill Splash) hit real enemies of the caster only.
local function hostileEnemiesWithin(originX: any, originY: any, radius: any, attackerSide: any)
	local out = {}
	for _, u in ipairs(enemiesWithin(originX, originY, radius, attackerSide)) do
		if u.side ~= "Neutral" then
			table.insert(out, u)
		end
	end
	return out
end

-- Terrain-ground augment → tile effect id it lays on the damaged tile (2026-10-24).
-- Only effects that already exist in GameConstants.TILE_EFFECTS are mapped; Darkened/Holy
-- ground are intentionally absent (no such tile effect exists yet — design/content gap).
-- Ground augments that cover EVERY tile the skill affects (range, area, pattern), damaging or
-- not (user ruling 2026-10-26). Applied once per cast in OnSkillComplete.
local WHOLE_AREA_GROUND = {
	["AUG-WET-GROUND"]    = true,
	["AUG-FROZEN-GROUND"] = true,
	["AUG-POISON-CLOUD"]  = true,
}

local TERRAIN_GROUND_MAP = {
	["AUG-BURNING-GROUND"] = "Burning",
	["AUG-WET-GROUND"]     = "Wet",
	["AUG-FROZEN-GROUND"]  = "Frozen",
	["AUG-POISON-CLOUD"]   = "Poison Cloud",
	["AUG-ELECTRIC-FIELD"] = "Static Cloud",
}

function AugmentEffectService.OnDamageResolved(attacker, defender, damage, skillDef, augmentIds, allUnits, shieldAbsorbed)
	if _processingAugment then return end
	if not augmentIds or #augmentIds == 0 then return end
	if damage <= 0 then return end
	if type(allUnits) == "table" then _augAllUnits = allUnits end

	_processingAugment = true

	for _, augId in ipairs(augmentIds) do
		local augName = getAugmentName(augId)
		local family  = getAugmentFamily(augId)

		-- ===============================================
		-- STATUS DELIVERY  (apply debuff to DEFENDER)
		-- ===============================================
		local statusToApply = STATUS_DELIVERY_MAP[augId]
		if statusToApply then
			if not shouldSkipForFrequency(augId) and defender.isAlive then
				StatusService.ApplyStatus(defender, statusToApply, attacker.id)
				markFired(augId)
				local inst = StatusService.HasStatus(defender, statusToApply)
				if inst then
					local _augIcon = AugmentData[augId] and AugmentData[augId].icon or nil
					BattleVisualBroadcaster.StatusApplied(defender, statusToApply, inst.remainingTurns, _augIcon)
				end
				print(string.format(
					"[AugmentEffect] %s triggered on %s (apply %s)",
					augName, defender.name, statusToApply
				))
			end

		-- ===============================================
		-- BUFF DELIVERY  (apply buff to ATTACKER)
		-- ===============================================
		elseif BUFF_DELIVERY_MAP[augId] then
			-- Delivered after the skill resolves, to the skill's target(s) (DB card; see
			-- OnSkillComplete). Nothing happens on damage (was: self-buff on hit, fix 2026-10-28).

		-- ===============================================
		-- TERRAIN GROUND (2026-10-24 augment fix): lay an existing tile effect on the
		-- damaged unit's tile. For AOE skills this hook fires per damaged unit, so each
		-- affected tile gets the terrain. Reuses TileEffectService.ApplyTileEffect.
		-- ===============================================
		elseif TERRAIN_GROUND_MAP[augId] then
			-- Wet/Frozen Ground and Poison Cloud cover the skill's whole area instead (laid once in
			-- OnSkillComplete, damaging or not; ruling 2026-10-26). Burning Ground stays per hit.
			if not WHOLE_AREA_GROUND[augId] and not shouldSkipForFrequency(augId) and defender.tileX and defender.tileY then
				TileEffectService.ApplyTileEffect(defender.tileX, defender.tileY, TERRAIN_GROUND_MAP[augId], attacker.id, _augAllUnits)
				markFired(augId)
				print(string.format("[AugmentEffect] %s: laid %s on (%d,%d)", augName, TERRAIN_GROUND_MAP[augId], defender.tileX, defender.tileY))
			end

		-- ===============================================
		-- DISPLACEMENT (2026-10-24 augment fix): single-target knockback / pull on hit.
		-- Push 1 tile via the shared DisplacementService (collision/occupancy aware). The
		-- authored "slight weapon-damage scaling reduction" is a balance number owned by
		-- the Designer (CTRBLXAI.db) — the MECHANIC (the push) is wired here; no arbitrary
		-- scaling penalty is invented.
		-- ===============================================
		elseif augId == "AUG-FORCEFUL-STRIKE" then
			if not shouldSkipForFrequency(augId) and defender.isAlive then
				local dir = DisplacementService.GetPushDirection(attacker, defender)
				augDisplace(attacker, defender, (attacker.derivedStats and attacker.derivedStats.force) or 1, dir, 1, false)  -- push
				markFired(augId)
				print(string.format("[AugmentEffect] %s: knocked %s back 1 tile", augName, defender.name))
			end

		elseif augId == "AUG-PULLING-STRIKE" then
			if not shouldSkipForFrequency(augId) and defender.isAlive then
				local out = DisplacementService.GetPushDirection(attacker, defender)
				local dir = { dx = -out.dx, dy = -out.dy }  -- invert: pull toward the caster
				augDisplace(attacker, defender, (attacker.derivedStats and attacker.derivedStats.force) or 1, dir, 1, true)  -- pull toward the caster
				markFired(augId)
				print(string.format("[AugmentEffect] %s: pulled %s 1 tile closer", augName, defender.name))
			end

		-- ===============================================
		-- DISPLACEMENT — Swap Strike (2026-10-24): swap caster<->target tiles after
		-- damage. Self-contained (swap tiles + UnitMoved broadcasts), mirrors the
		-- CommandService applySwap primitive. nil-safe; needs both alive and distinct.
		-- ===============================================
		elseif augId == "AUG-SWAP-STRIKE" then
			if not shouldSkipForFrequency(augId) and attacker.isAlive and defender.isAlive
				and defender.id ~= attacker.id and attacker.tileX and defender.tileX
				and not defender._displacementImmune and not attacker._displacementImmune
				-- D5 fix (2026-10-27): no swap through a lock (Gravity Pylon aura / Phase Locked on
				-- either unit) and no self-relocation for a Phase Locked attacker.
				and not StatusService.IsTeleportLocked(attacker) and not StatusService.IsTeleportLocked(defender)
				and not StatusService.IsRelocationLocked(attacker) then
				local ax, ay = attacker.tileX, attacker.tileY
				attacker.tileX, attacker.tileY = defender.tileX, defender.tileY
				defender.tileX, defender.tileY = ax, ay
				if BattleVisualBroadcaster.UnitMoved then
					BattleVisualBroadcaster.UnitMoved(attacker)
					BattleVisualBroadcaster.UnitMoved(defender)
				end
				markFired(augId)
				print(string.format("[AugmentEffect] %s: %s swapped places with %s", augName, attacker.name, defender.name))
			end

		-- ===============================================
		-- TIMING — Delay Strike (2026-10-24): increase the target's time-to-next-turn by
		-- 20% (bump current remainingRt). Immediate; no turn-engine change needed.
		-- ===============================================
		elseif augId == "AUG-DELAY-STRIKE" then
			if not shouldSkipForFrequency(augId) and defender.isAlive then
				defender.remainingRt = math.max(1, math.round((defender.remainingRt or 0) * 1.20))
				markFired(augId)
				print(string.format("[AugmentEffect] %s: %s's next turn delayed 20%% (RT %d)", augName, defender.name, defender.remainingRt))
			end

		-- ===============================================
		-- TIMING — Interrupt (2026-10-24): cancel the target's channel if mid-cast (the
		-- handler itself refuses uninterruptible activation phases). Injected DI handler.
		-- ===============================================
		elseif augId == "AUG-INTERRUPT" then
			if not shouldSkipForFrequency(augId) and defender.isChanneling and _interruptHandler then
				local ok = _interruptHandler(defender, "Interrupt")
				markFired(augId)
				print(string.format("[AugmentEffect] %s: interrupt on %s -> %s", augName, defender.name, tostring(ok)))
			end

		-- ===============================================
		-- RECOVERY — Siphon Barrier (2026-10-25): if this hit removed shield/barrier from the
		-- target, recover MP = 20% of the amount removed. shieldAbsorbed is the damage soaked
		-- by the target's shield this hit (from UnitSchema.ApplyDamage via CombatResolver).
		-- ===============================================
		elseif augId == "AUG-SIPHON-BARRIER" then
			if not shouldSkipForFrequency(augId) and attacker.isAlive and (shieldAbsorbed or 0) > 0 then
				local mp = math.floor((shieldAbsorbed or 0) * 0.20)
				if mp > 0 then restoreMp(attacker, mp) end
				markFired(augId)
				print(string.format("[AugmentEffect] %s: %s siphoned %d MP (20%% of %d barrier removed)", augName, attacker.name, mp, shieldAbsorbed))
			end

		-- ===============================================
		-- RECOVERY — Vitality Surge (2026-10-24): flat heal = 5% of caster max HP on a
		-- damaging hit (not damage-based). Reuses healUnit.
		-- ===============================================
		elseif augId == "AUG-VITALITY-SURGE" then
			if not shouldSkipForFrequency(augId) and attacker.isAlive then
				local heal = math.floor((attacker.maxHp or 0) * 0.05)
				if heal > 0 then healUnit(attacker, heal) end
				markFired(augId)
				print(string.format("[AugmentEffect] %s: %s recovered %d HP (5%% max HP)", augName, attacker.name, heal))
			end

		-- ===============================================
		-- DEFENSIVE — Barrier on Hit (2026-10-24): after dealing HP damage the caster gains
		-- a barrier = 15% of damage dealt. Mapped onto the existing shield subsystem
		-- (StatusService.ApplyShield). "Until next turn" is modelled as the caster's own
		-- turn length in CT (base RT), so it naturally lapses around their next action.
		-- ===============================================
		elseif augId == "AUG-BARRIER-ON-HIT" then
			if not shouldSkipForFrequency(augId) and attacker.isAlive then
				local barrier = math.floor((damage or 0) * 0.15)
				if barrier > 0 then
					local dur = attacker.startingRt or 400
					StatusService.ApplyShield(attacker, barrier, dur, attacker.id)
					if BattleVisualBroadcaster.ShieldChanged then
						BattleVisualBroadcaster.ShieldChanged(attacker, barrier, "grant")
					end
				end
				markFired(augId)
				print(string.format("[AugmentEffect] %s: %s gained a %d barrier (15%% of %d dmg)", augName, attacker.name, barrier, damage or 0))
			end

		-- ===============================================
		-- DEFENSIVE — Draining Ward (2026-10-25): after dealing damage, caster gains a small
		-- absorb ward = 20% of damage dealt, via the shield system. FIDELITY NOTE: the authored
		-- intent is "absorbs the next MAGIC damage" — shields here are untyped, so this ward
		-- currently absorbs ANY damage (not magic-only). Upgrading to element-typed absorb is a
		-- small follow-up; flagged, not silently diverged.
		-- ===============================================
		elseif augId == "AUG-DRAINING-WARD" then
			if not shouldSkipForFrequency(augId) and attacker.isAlive then
				local ward = math.floor((damage or 0) * 0.20)
				if ward > 0 then
					StatusService.ApplyShield(attacker, ward, attacker.startingRt or 400, attacker.id)
					if BattleVisualBroadcaster.ShieldChanged then
						BattleVisualBroadcaster.ShieldChanged(attacker, ward, "grant")
					end
				end
				markFired(augId)
				print(string.format("[AugmentEffect] %s: %s gained a %d ward (20%% of %d dmg)", augName, attacker.name, ward, damage or 0))
			end

		-- ===============================================
		-- RECOVERY — Lifesteal
		-- ===============================================
		elseif augId == "AUG-LIFESTEAL" then
			if not shouldSkipForFrequency(augId) and attacker.isAlive then
				local healAmount = math.floor(damage * 0.20)
				if healAmount > 0 then
					local actual = healUnit(attacker, healAmount)
					print(string.format(
						"[AugmentEffect] %s triggered: %s heals %d (20%% of %d damage)",
						augName, attacker.name, actual, damage
					))
				end
				markFired(augId)
			end

		-- ===============================================
		-- RECOVERY — Mana Leech
		-- ===============================================
		elseif augId == "AUG-MANA-LEECH" then
			if not shouldSkipForFrequency(augId) and attacker.isAlive then
				local mpAmount = math.floor(damage * 0.15)
				if mpAmount > 0 then
					local actual = restoreMp(attacker, mpAmount)
					print(string.format(
						"[AugmentEffect] %s triggered: %s restores %d MP (15%% of %d damage)",
						augName, attacker.name, actual, damage
					))
				end
				markFired(augId)
			end

		-- ===============================================
		-- MP ATTACK — Mana Erosion / Mana Rupture (2026-10-24 augment fix)
		-- Erosion drains the defender's MP on hit; Rupture destroys MP AND deals
		-- bonus damage equal to the MP removed (routed through UnitSchema.ApplyDamage
		-- so it respects the shield gate — no bypass). Drain magnitude defaults to
		-- 15% of the defender's Max MP, matching the Mana Leech sibling scale.
		-- ===============================================
		elseif augId == "AUG-MANA-EROSION-SUPPORT" then
			if not shouldSkipForFrequency(augId) and defender.isAlive then
				local drain = math.floor((defender.maxMp or 0) * 0.15)
				local before = defender.currentMp or 0
				defender.currentMp = math.max(0, before - drain)
				local removed = before - defender.currentMp
				markFired(augId)
				print(string.format("[AugmentEffect] %s: drained %d MP from %s", augName, removed, defender.name))
			end

		elseif augId == "AUG-MANA-RUPTURE-SUPPORT" then
			if not shouldSkipForFrequency(augId) and defender.isAlive then
				local drain = math.floor((defender.maxMp or 0) * 0.15)
				local before = defender.currentMp or 0
				defender.currentMp = math.max(0, before - drain)
				local removed = before - defender.currentMp
				if removed > 0 then
					UnitSchema.ApplyDamage(defender, removed, "Mana Rupture")
				end
				markFired(augId)
				print(string.format("[AugmentEffect] %s: destroyed %d MP on %s + %d bonus damage", augName, removed, defender.name, removed))
			end

		-- ===============================================
		-- RECOVERY — Overhealing Shield  (stub shield part)
		-- ===============================================
		elseif augId == "AUG-OVERHEALING-SHIELD" then
			-- Built in CombatResolver.ApplyOutcome's heal branch (excess healing -> barrier), 2026-10-28.

		-- ===============================================
		-- PURGE — Purging Strike  (per qualifying target)
		-- ===============================================
		elseif augId == "AUG-PURGING-STRIKE" then
			if defender.isAlive then
				local removed = removeRandomBuff(defender)
				if removed then
					print(string.format(
						"[AugmentEffect] %s triggered on %s (removed buff: %s)",
						augName, defender.name, removed
					))
				else
					print(string.format(
						"[AugmentEffect] %s on %s — no purgeable buff found",
						augName, defender.name
					))
				end
			end

		-- ===============================================
		-- PURGE — Mass Purge  (AOE skills only)
		-- ===============================================
		elseif augId == "AUG-MASS-PURGE" then
			local isAOE = skillDef
				and skillDef.aoePattern
				and skillDef.aoePattern ~= "Single"
			if isAOE and defender.isAlive then
				local removed = removeAllBuffs(defender)
				if #removed > 0 then
					print(string.format(
						"[AugmentEffect] %s triggered on %s (removed %d buffs: %s)",
						augName, defender.name, #removed, table.concat(removed, ", ")
					))
				else
					print(string.format(
						"[AugmentEffect] %s on %s — no purgeable buff found",
						augName, defender.name
					))
				end
			elseif not isAOE then
				print(string.format(
					"[AugmentEffect] %s skipped: skill is not AOE", augName
				))
			end

		-- ===============================================
		-- PURGE — Deep Purge  (1 random buff + 1 random debuff)
		-- ===============================================
		elseif augId == "AUG-DEEP-PURGE" then
			if not shouldSkipForFrequency(augId) and defender.isAlive then
				local removedBuff   = removeRandomBuff(defender)
				local removedDebuff = removeRandomDebuff(defender)
				markFired(augId)
				print(string.format(
					"[AugmentEffect] %s triggered on %s (buff: %s, debuff: %s)",
					augName, defender.name,
					removedBuff or "none", removedDebuff or "none"
				))
			end
		-- ===============================================
		-- CATCH-ALL STUBS for families handled by this hook
		-- ===============================================
		elseif DAMAGE_RESOLVED_FAMILIES[family] then
			if not shouldSkipForFrequency(augId) then
				markFired(augId)
				print(string.format(
					"[AugmentEffect] %s not yet implemented (%s)",
					augName, family
				))
			end

		-- Families handled by other hooks (Stat Scaling, Element Conversion,
		-- Conditional Amplifier, Penetration, Kill Trigger, Death Explosion,
		-- Reward, Timing, Defensive, Pattern, Resource Conversion, Summoning)
		-- are silently skipped here.
		end
	end

	_processingAugment = false
end

--------------------------------------------------
-- 4. OnKill
--
-- Called when the target dies from skill damage.
-- Families: Kill Trigger, Death Explosion, Reward.
--
-- Returns: nil
--------------------------------------------------

function AugmentEffectService.OnKill(attacker, defender, skillDef, augmentIds, ctx)
	ctx = ctx or {}
	if _processingAugment then return end
	if not augmentIds or #augmentIds == 0 then return end
	-- Kill-credit gate: allies, neutrals, summons and revived units never trigger kill augments.
	if not AugmentEffectService.IsKillCreditEligible(attacker, defender) then
		print(string.format(
			"[AugmentEffect] Kill augments skipped: %s's kill of %s is not kill-credit eligible (ally/neutral/summon/revived)",
			tostring(attacker and attacker.name), tostring(defender and defender.name)
		))
		return
	end

	_processingAugment = true

	for _, augId in ipairs(augmentIds) do
		local augName = getAugmentName(augId)
		local family  = getAugmentFamily(augId)

		-- ===== KILL TRIGGER — Executioner =====
		if augId == "AUG-EXECUTIONER" then
			if not shouldSkipForFrequency(augId) then
				local mpRestore = math.floor((attacker.maxMp or 0) * 0.10)
				if mpRestore > 0 then
					local actual = restoreMp(attacker, mpRestore)
					print(string.format(
						"[AugmentEffect] %s triggered: %s restores %d MP (10%% maxMP) on kill",
						augName, attacker.name, actual
					))
				end
				markFired(augId)
			end

		-- ===== KILL TRIGGER — Blood Harvest =====
		elseif augId == "AUG-BLOOD-HARVEST" then
			if not shouldSkipForFrequency(augId) then
				local healAmount = math.floor((attacker.maxHp or 0) * 0.15)
				if healAmount > 0 then
					local actual = healUnit(attacker, healAmount)
					print(string.format(
						"[AugmentEffect] %s triggered: %s heals %d HP (15%% maxHP) on kill",
						augName, attacker.name, actual
					))
				end
				markFired(augId)
			end

		-- ===== KILL TRIGGER — Soul Harvest =====
		elseif augId == "AUG-SOUL-HARVEST" then
			if not shouldSkipForFrequency(augId) then
				StatusService.ApplyStatus(attacker, "Haste", attacker.id)
				markFired(augId)
				print(string.format(
					"[AugmentEffect] %s triggered: %s gains Haste on kill",
					augName, attacker.name
				))
			end

		-- ===== KILL TRIGGER — Purifying Kill (2026-10-24 augment fix) =====
		elseif augId == "AUG-PURIFYING-KILL" then
			if not shouldSkipForFrequency(augId) then
				StatusService.RemoveRandomDebuff(attacker)
				markFired(augId)
				print(string.format("[AugmentEffect] %s: removed a debuff from %s on kill", augName, attacker.name))
			end

		-- ===== DEATH EXPLOSION — Toxic Death (2026-10-24): Poison enemies within 2 =====
		elseif augId == "AUG-TOXIC-DEATH" then
			if not shouldSkipForFrequency(augId) then
				local victims = hostileEnemiesWithin(defender.tileX, defender.tileY, 2, attacker.side)
				for _, u in ipairs(victims) do
					StatusService.ApplyStatus(u, "Poison", attacker.id)
				end
				markFired(augId)
				print(string.format("[AugmentEffect] %s: Poisoned %d enemies near %s's death", augName, #victims, defender.name))
			end

		-- ===== DEATH EXPLOSION — Terrifying Death (2026-10-24): push enemies within 3 =====
		elseif augId == "AUG-TERRIFYING-DEATH" then
			if not shouldSkipForFrequency(augId) then
				local dx0, dy0 = defender.tileX, defender.tileY
				local victims = hostileEnemiesWithin(dx0, dy0, 3, attacker.side)
				for _, u in ipairs(victims) do
					local rawx, rawy = (u.tileX or dx0) - dx0, (u.tileY or dy0) - dy0
					local dir = { dx = (rawx>0 and 1) or (rawx<0 and -1) or 0, dy = (rawy>0 and 1) or (rawy<0 and -1) or 0 }
					if dir.dx == 0 and dir.dy == 0 then dir.dx = 1 end
					augDisplace(defender, u, (attacker.derivedStats and attacker.derivedStats.force) or 1, dir, 1, false)  -- push away from the death tile
				end
				markFired(augId)
				print(string.format("[AugmentEffect] %s: pushed %d enemies from %s's death", augName, #victims, defender.name))
			end

		-- ===== DEATH EXPLOSION — Explosive Death (2026-10-24): fire dmg to adjacent =====
		elseif augId == "AUG-EXPLOSIVE-DEATH" then
			if not shouldSkipForFrequency(augId) then
				local dmg = math.floor((defender.maxHp or 0) * 0.25)
				local victims = enemiesWithin(defender.tileX, defender.tileY, 1, attacker.side)
				for _, u in ipairs(victims) do
					if dmg > 0 then UnitSchema.ApplyDamage(u, dmg, "Explosive Death") end
				end
				markFired(augId)
				print(string.format("[AugmentEffect] %s: %d fire damage to %d adjacent (25%% of %s maxHP)", augName, dmg, #victims, defender.name))
			end

		-- ===== KILL TRIGGER — Kill Momentum MP (2026-10-24): refund 30% of the skill's
		-- MP cost on a kill. skillDef comes from ctx via ApplyOutcome; no-op if unknown.
		elseif augId == "AUG-KILL-MOMENTUM-MP" then
			if not shouldSkipForFrequency(augId) and skillDef then
				local baseMp = GameConstants.CalcSkillMpCost(attacker, skillDef, 1.0) or 0
				local refund = math.floor(baseMp * 0.30)
				if refund > 0 then restoreMp(attacker, refund) end
				markFired(augId)
				print(string.format("[AugmentEffect] %s: %s refunded %d MP (30%% of skill cost) on kill", augName, attacker.name, refund))
			end

		-- ===== KILL TRIGGER — Overkill Splash (2026-10-24): if the killing hit dealt more
		-- than lethal, splash the excess to the nearest enemy, capped at 50% of the hit.
		elseif augId == "AUG-OVERKILL-SPLASH" then
			if not shouldSkipForFrequency(augId) then
				local excess = ctx.overkill or 0
				local cap = math.floor((ctx.hitDamage or 0) * 0.50)
				local splash = math.min(excess, cap)
				if splash > 0 then
					-- nearest living enemy to the corpse (Chebyshev), within 2 tiles.
					local victims = hostileEnemiesWithin(defender.tileX, defender.tileY, 2, attacker.side)
					local best, bestD = nil, math.huge
					for _, u in ipairs(victims) do
						local d = math.max(math.abs((u.tileX or 0) - (defender.tileX or 0)), math.abs((u.tileY or 0) - (defender.tileY or 0)))
						if d < bestD then best, bestD = u, d end
					end
					if best then
						UnitSchema.ApplyDamage(best, splash, "Overkill Splash")
						print(string.format("[AugmentEffect] %s: splashed %d overkill to %s", augName, splash, best.name))
					end
				end
				markFired(augId)
			end

		-- ===== TIMING — Momentum (2026-10-24): on kill, reduce caster next-turn CT by 30%
		-- (one-shot mult consumed by EndTurn). =====
		elseif augId == "AUG-MOMENTUM" then
			attacker._nextTurnCtMult = (attacker._nextTurnCtMult or 1) * 0.70
			print(string.format("[AugmentEffect] %s: %s next-turn CT -30%% on kill", augName, attacker.name))

		-- ===== DEATH — Shattering Death (2026-10-24): enemies within 2 tiles of the corpse
		-- get Sundered (-20% Physical Defense, 2 turns). =====
		elseif augId == "AUG-SHATTERING-DEATH" then
			local victims = hostileEnemiesWithin(defender.tileX, defender.tileY, 2, attacker.side)
			for _, u in ipairs(victims) do
				StatusService.ApplyStatus(u, "Sundered", attacker.id)
			end
			print(string.format("[AugmentEffect] %s: Sundered %d enemies near %s's death", augName, #victims, defender.name))

		-- ===== DEFENSIVE — Fortify on Kill (2026-10-25): on a kill the caster takes 25% less
		-- damage for a round (_fortifyMult 0.75), cleared at the caster's next EndTurn. =====
		elseif augId == "AUG-FORTIFY-ON-KILL" then
			attacker._fortifyMult = 0.75
			print(string.format("[AugmentEffect] %s: %s fortified (-25%% damage taken this round)", augName, attacker.name))

		-- ===== REWARD — Gold Harvest (2026-10-25): stamp the slain enemy so battle-end gold
		-- (computeBattleGold) pays +25% for this kill. =====
		elseif augId == "AUG-GOLD-HARVEST" then
			defender._goldHarvested = true
			print(string.format("[AugmentEffect] %s: %s will drop +25%% gold", augName, defender.name))

		-- ===== REWARD — Treasure Hunter (2026-10-25): stamp the slain enemy so battle-end loot
		-- generation bumps rarity by 1 tier (Main reads the flag, passes bonusRarityTiers). =====
		elseif augId == "AUG-TREASURE-HUNTER" then
			defender._treasureHunted = true
			print(string.format("[AugmentEffect] %s: %s will drop higher-rarity loot", augName, defender.name))

		-- ===== CATCH-ALL STUBS for kill-phase families =====
		elseif KILL_FAMILIES[family] then
			if not shouldSkipForFrequency(augId) then
				markFired(augId)
				print(string.format(
					"[AugmentEffect] %s not yet implemented (%s)",
					augName, family
				))
			end

		-- Families handled by other hooks are silently skipped.
		end
	end

	_processingAugment = false
end

--------------------------------------------------
-- 5. OnSkillComplete
--
-- Called after the entire skill resolution completes.
-- Families: Timing, Defensive — ALL STUBBED.
-- These need RT manipulation and reactive trigger systems.
--
-- Returns: nil
--------------------------------------------------

function AugmentEffectService.OnSkillComplete(attacker, skillDef, augmentIds, ctx)
	if not augmentIds or #augmentIds == 0 then return end
	ctx = ctx or {}
	local state = ctx.state

	-- NOTE: OnSkillComplete fires exactly ONCE per skill cast (from CommandService, instant
	-- + channeled exits), so these once-per-cast augments do NOT use the frequency gate /
	-- markFired (whose per-resolution reset is never called — see audit). Direct, nil-safe.
	for _, augId in ipairs(augmentIds) do
		local augName = getAugmentName(augId)
		local family  = getAugmentFamily(augId)

		-- SUMMONING (2026-10-24): spawn a decoy / turret next to the caster after the skill.
		-- Reuses the authored summon profiles (SKL-SUMMON-DECOY / SKL-SUMMON-TURRET) via the
		-- injected CommandService spawner; no-op if the spawner or state is unavailable.
		if augId == "AUG-DECOY-SPAWN" or augId == "AUG-TURRET-SPAWN" then
			if _summonHandler and state then
				local summonSkill = (augId == "AUG-DECOY-SPAWN") and "SKL-SUMMON-DECOY" or "SKL-SUMMON-TURRET"
				_summonHandler(attacker, summonSkill, state)
				print(string.format("[AugmentEffect] %s: spawned %s near %s", augName, summonSkill, attacker.name))
			end

		-- AOE DISPLACEMENT (2026-10-24): scatter pushes enemies 1 tile AWAY from the impact
		-- center; vortex pulls them 1 tile TOWARD it. Center comes from ctx; affected set is
		-- enemies within Chebyshev radius 2 of center (faithful footprint approximation —
		-- flagged in handoff). Push distance 1 is authored. Reuses DisplacementService.
		elseif augId == "AUG-SCATTER-STRIKE" or augId == "AUG-VORTEX-STRIKE" then
			if ctx.centerX and ctx.centerY then
				local toward = (augId == "AUG-VORTEX-STRIKE")
				local force = (attacker.derivedStats and attacker.derivedStats.force) or 1
				local victims = enemiesWithin(ctx.centerX, ctx.centerY, 2, attacker.side)
				for _, u in ipairs(victims) do
					local rawx = (u.tileX or ctx.centerX) - ctx.centerX
					local rawy = (u.tileY or ctx.centerY) - ctx.centerY
					local sgx = (rawx > 0 and 1) or (rawx < 0 and -1) or 0
					local sgy = (rawy > 0 and 1) or (rawy < 0 and -1) or 0
					local dir = toward and { dx = -sgx, dy = -sgy } or { dx = sgx, dy = sgy }
					if dir.dx == 0 and dir.dy == 0 then dir.dx = 1 end
					augDisplace(attacker, u, force, dir, 1, toward)  -- vortex = pull toward the impact centre
				end
				print(string.format("[AugmentEffect] %s: %s %d enemies %s impact center",
					augName, toward and "pulled" or "scattered", #victims, toward and "toward" or "from"))
			end

		-- SUPPORT DELIVERY (DB cards, built 2026-10-28): "After the supported Skill resolves, apply
		-- <buff> to the target for N turns." Targets = the units the skill helped (ctx.supportTargets,
		-- worked out by CommandService); units the cast damaged never get it.
		elseif BUFF_DELIVERY_MAP[augId] then
			local sid = BUFF_DELIVERY_MAP[augId]
			local turns = SUPPORT_TURNS[sid]
			local icon = AugmentData[augId] and AugmentData[augId].icon or nil
			for _, u in ipairs(ctx.supportTargets or {}) do
				if u.isAlive then
					local before = StatusService.HasStatus(u, sid)
					local r0t = before and before.remainingTurns
					local r0c = before and before.remainingCt
					local _, _, immuneReason = StatusService.ApplyStatus(u, sid, attacker.id)
					if immuneReason then
						-- Immune: nothing applied or refreshed (UAT 2026-10-28 D4).
						BattleVisualBroadcaster.StatusImmune(u, sid, immuneReason)
					else
						local inst = StatusService.HasStatus(u, sid)
						local def = GameConstants.STATUSES[sid]
						if inst and turns and def then
							local isCt = inst.remainingCt ~= nil
							local card = if isCt then turns * 1000 else turns
							if not before then
								-- New: scale the default to the card length, so an applier bonus such
								-- as Lore keeps its share.
								local base = if isCt then def.durationCt else def.duration
								if base and base > 0 then
									local v = math.max(1, math.round((if isCt then inst.remainingCt else inst.remainingTurns) * card / base))
									if isCt then inst.remainingCt = v else inst.remainingTurns = v end
								end
							else
								-- Reapplied: an "extend" status adds the card length; others keep
								-- whichever is longer, the old time or the card length.
								local r0 = (if isCt then r0c else r0t) or 0
								local v = if def.reapply == "extend" then r0 + card else math.max(r0, card)
								if isCt then inst.remainingCt = v else inst.remainingTurns = v end
							end
						end
						if inst then
							BattleVisualBroadcaster.StatusApplied(u, sid, inst.remainingTurns, icon)
							print(string.format("[AugmentEffect] %s: %s gets %s", augName, u.name, sid))
						end
					end
				end
			end

		-- TERRAIN — Darkened Ground (2026-10-25): lay Darkened Ground (heal -20%) on the
		-- target's tile + 4 orthogonal neighbours (cross, 5 tiles). Reuses ApplyTileEffect.
		elseif augId == "AUG-DARKENED-GROUND" then
			if ctx.centerX and ctx.centerY then
				local cx, cy = ctx.centerX, ctx.centerY
				for _, d in ipairs({ {0,0}, {1,0}, {-1,0}, {0,1}, {0,-1} }) do
					TileEffectService.ApplyTileEffect(cx + d[1], cy + d[2], "Darkened Ground", attacker.id, _augAllUnits)
				end
				print(string.format("[AugmentEffect] %s: laid Darkened Ground (cross) at (%d,%d)", augName, cx, cy))
			end

		-- TERRAIN — Holy Ground (2026-10-25): lay Holy Ground on the CASTER's tile + 4
		-- orthogonal neighbours (cross, 5 tiles). Owner-side units heal / undead burn each
		-- turn (TileEffectService.applyHolyGroundEndTurn). ownerId = caster so side resolves.
		elseif augId == "AUG-HOLY-GROUND" then
			if attacker.tileX and attacker.tileY then
				local cx, cy = attacker.tileX, attacker.tileY
				for _, d in ipairs({ {0,0}, {1,0}, {-1,0}, {0,1}, {0,-1} }) do
					TileEffectService.ApplyTileEffect(cx + d[1], cy + d[2], "Holy Ground", attacker.id, _augAllUnits)
				end
				print(string.format("[AugmentEffect] %s: laid Holy Ground (cross) at (%d,%d)", augName, cx, cy))
			end

		-- PURGE — Self-Cleanse (2026-10-25): remove one debuff from the caster after the skill.
		elseif augId == "AUG-SELF-CLEANSE" then
			StatusService.RemoveRandomDebuff(attacker)
			print(string.format("[AugmentEffect] %s: cleansed a debuff from %s", augName, attacker.name))

		-- DEFENSIVE — Retaliation Guard (2026-10-25): the next incoming attack deals 20% less to
		-- the caster. Consumed on the next hit in ApplyOutcome; cleared at the caster's EndTurn.
		elseif augId == "AUG-RETALIATION-GUARD" then
			attacker._retaliationGuard = 0.80
			print(string.format("[AugmentEffect] %s: %s guarded (next incoming hit -20%%)", augName, attacker.name))

		-- DEFENSIVE — Threat Reduction (2026-10-25): enemy AI values the caster 20% less as an
		-- attack target until its next turn. Flag read by AIService.scoreAttack; cleared at EndTurn.
		elseif augId == "AUG-THREAT-REDUCTION" then
			attacker._threatFactor = 0.80
			print(string.format("[AugmentEffect] %s: %s threat -20%% until next turn", augName, attacker.name))

		-- DEFENSIVE — Steadfast Strike (2026-10-24): caster becomes immune to knockback /
		-- pull / swap until their next turn. Flag checked by DisplacementService.ResolvePush
		-- and applySwap; cleared in BattleCoordinator.EndTurn (one-shot, like the CT mult).
		elseif augId == "AUG-STEADFAST-STRIKE" then
			attacker._displacementImmune = true
			print(string.format("[AugmentEffect] %s: %s is displacement-immune until next turn", augName, attacker.name))

		-- TIMING — Quicken Self (2026-10-24): reduce the caster's NEXT-turn CT by 15% via a
		-- one-shot multiplier BattleCoordinator.EndTurn consumes. Stacks multiplicatively if
		-- another CT augment also stamped this cast.
		elseif augId == "AUG-QUICKEN-SELF" then
			attacker._nextTurnCtMult = (attacker._nextTurnCtMult or 1) * 0.85
			print(string.format("[AugmentEffect] %s: %s next-turn CT -15%%", augName, attacker.name))

		-- TERRAIN — Wet Ground / Frozen Ground / Poison Cloud (ruling 2026-10-26): lay the effect on
		-- every tile the skill covered (ctx.affectedTiles from CommandService), damaging or not.
		elseif WHOLE_AREA_GROUND[augId] then
			local effectId = TERRAIN_GROUND_MAP[augId]
			local tiles = ctx.affectedTiles
			if (not tiles or #tiles == 0) and ctx.centerX and ctx.centerY then
				tiles = { { x = ctx.centerX, y = ctx.centerY } }
			end
			for _, t in ipairs(tiles or {}) do
				TileEffectService.ApplyTileEffect(t.x, t.y, effectId, attacker.id, _augAllUnits)
			end
			print(string.format("[AugmentEffect] %s: laid %s on %d tile(s)", augName, tostring(effectId), #(tiles or {})))

		elseif SKILL_COMPLETE_FAMILIES[family] then
			print(string.format(
				"[AugmentEffect] %s not yet implemented (%s — needs RT/reactive trigger system)",
				augName, family
			))
		end
	end
end

return AugmentEffectService
