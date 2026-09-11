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
local BattleVisualBroadcaster = require(script.Parent.BattleVisualBroadcaster)

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

local AugmentEffectService = {}

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

-- Status Delivery: augment ID → status to apply on DEFENDER.
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
}

-- Buff Delivery: augment ID → status to apply on ATTACKER (self-buff).
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
	["Status Delivery"] = true,
	["Buff Delivery"]   = true,
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
	local missing = (unit.maxHp or 0) - (unit.currentHp or 0)
	local actual = math.min(missing, math.max(0, math.floor(amount)))
	unit.currentHp = (unit.currentHp or 0) + actual
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

function AugmentEffectService.GetAugmentsForSkill(unit, skillId)
	if not unit or not skillId then return {} end

	-- Doctrine skill (slot 1)
	if skillId == unit.selectedDoctrineSkill then
		return unit.doctrineAugments or {}
	end

	-- Skill loadout (slots 2, 3, 4)
	if unit.skillLoadout then
		for _, slotKey in ipairs({ "slot2", "slot3", "slot4" }) do
			local slotData = unit.skillLoadout[slotKey]
			if slotData and slotData.skillId == skillId then
				return slotData.augments or {}
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
				print(string.format(
					"[AugmentEffect] %s MP cost multiplier ×%.2f",
					augDef.name, mp
				))
			end
		end
	end

	return finalMultiplier
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

		-- ===== ELEMENT CONVERSION  (stub — all 7) =====
		elseif family == "Element Conversion" then
			-- TODO: set elementOverride once element conversion pipeline exists
			print(string.format(
				"[AugmentEffect] %s not yet implemented (Element Conversion)",
				augName
			))

		-- ===== CONDITIONAL AMPLIFIER — remaining stubs =====
		elseif family == "Conditional Amplifier" then
			print(string.format(
				"[AugmentEffect] %s not yet implemented (Conditional Amplifier)",
				augName
			))

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
-- Families: Status Delivery, Buff Delivery, Recovery, Purge,
--           Displacement, Terrain Effect.
--
-- Returns: nil
--------------------------------------------------

function AugmentEffectService.OnDamageResolved(attacker, defender, damage, skillDef, augmentIds, allUnits)
	if _processingAugment then return end
	if not augmentIds or #augmentIds == 0 then return end
	if damage <= 0 then return end

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
					BattleVisualBroadcaster.StatusApplied(defender, statusToApply, inst.remainingTurns)
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
			local buffToApply = BUFF_DELIVERY_MAP[augId]
			if not shouldSkipForFrequency(augId) and attacker.isAlive then
				StatusService.ApplyStatus(attacker, buffToApply, attacker.id)
				markFired(augId)
				local inst = StatusService.HasStatus(attacker, buffToApply)
				if inst then
					BattleVisualBroadcaster.StatusApplied(attacker, buffToApply, inst.remainingTurns)
				end
				print(string.format(
					"[AugmentEffect] %s triggered on %s (self-buff %s)",
					augName, attacker.name, buffToApply
				))
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
		-- RECOVERY — Overhealing Shield  (stub shield part)
		-- ===============================================
		elseif augId == "AUG-OVERHEALING-SHIELD" then
			if not shouldSkipForFrequency(augId) then
				markFired(augId)
				print(string.format(
					"[AugmentEffect] %s not yet implemented (Recovery — shield conversion)",
					augName
				))
			end

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
		-- DISPLACEMENT — Forceful Strike  (knockback 1)
		-- ===============================================
		elseif augId == "AUG-FORCEFUL-STRIKE" then
			if not shouldSkipForFrequency(augId) and defender.isAlive then
				_pendingDisplacement = {
					type     = "knockback",
					distance = 1,
					targetId = defender.id,
					sourceId = attacker.id,
				}
				markFired(augId)
				print(string.format(
					"[AugmentEffect] %s triggered on %s (knockback 1 tile)",
					augName, defender.name
				))
			end

		-- ===============================================
		-- DISPLACEMENT — Pulling Strike  (pull 1)
		-- ===============================================
		elseif augId == "AUG-PULLING-STRIKE" then
			if not shouldSkipForFrequency(augId) and defender.isAlive then
				_pendingDisplacement = {
					type     = "pull",
					distance = 1,
					targetId = defender.id,
					sourceId = attacker.id,
				}
				markFired(augId)
				print(string.format(
					"[AugmentEffect] %s triggered on %s (pull 1 tile toward caster)",
					augName, defender.name
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

function AugmentEffectService.OnKill(attacker, defender, skillDef, augmentIds)
	if _processingAugment then return end
	if not augmentIds or #augmentIds == 0 then return end

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

function AugmentEffectService.OnSkillComplete(attacker, skillDef, augmentIds)
	if not augmentIds or #augmentIds == 0 then return end

	for _, augId in ipairs(augmentIds) do
		local augName = getAugmentName(augId)
		local family  = getAugmentFamily(augId)

		if SKILL_COMPLETE_FAMILIES[family] then
			print(string.format(
				"[AugmentEffect] %s not yet implemented (%s — needs RT/reactive trigger system)",
				augName, family
			))
		end
	end
end

return AugmentEffectService
