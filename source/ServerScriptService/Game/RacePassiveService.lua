-- RacePassiveService.lua
-- CTRBLXAI | Slice 4F — Race Passive Functions
--
-- Centralized query interface for race passive effects.
-- Other services call these to apply race-based modifiers.
-- Units without a raceId receive neutral (no-op) values.

local RacePassiveService = {}

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function getRaceId(unit)
	return unit and unit.raceId or nil
end

local function isElemental(element)
	-- "Elemental" means any non-nil, non-Physical element
	return element ~= nil and element ~= "Physical" and element ~= ""
end

--------------------------------------------------
-- DAMAGE DEALT MODIFIER
-- Returns a multiplier applied to final damage dealt by this unit.
-- Called from CombatResolver after finalDamage is calculated.
--
-- Args:
--   attacker: unit table
--   element: skill element string or nil (Basic Attack = nil/Physical)
--   isAOE: boolean
--------------------------------------------------

function RacePassiveService.GetDamageDealtModifier(attacker, element, isAOE)
	local raceId = getRaceId(attacker)
	if not raceId then return 1.0 end

	local mod = 1.0

	-- ORC — Bloodlust: below 50% HP, final damage +15%
	if raceId == "RACE-ORC" then
		if attacker.currentHp and attacker.maxHp and attacker.currentHp < (attacker.maxHp * 0.5) then
			mod = mod * 1.15
		end
	end

	-- ELEMENTAL SPIRIT — Elemental Flux: elemental damage dealt +30%
	if raceId == "RACE-ELEMENTAL-SPIRIT" then
		if isElemental(element) then
			mod = mod * 1.30
		end
	end

	return mod
end

--------------------------------------------------
-- DAMAGE RECEIVED MODIFIER
-- Returns a multiplier applied to final damage received by this unit.
-- Called from CombatResolver after finalDamage is calculated.
--
-- Args:
--   defender: unit table
--   element: skill element string or nil
--   isAOE: boolean
--   isPhysical: boolean (true for Basic Attacks and physical skills)
--------------------------------------------------

function RacePassiveService.GetDamageReceivedModifier(defender, element, isAOE, isPhysical)
	local raceId = getRaceId(defender)
	if not raceId then return 1.0 end

	local mod = 1.0

	-- DWARF — Stout Resilience: direct physical damage received -10%
	if raceId == "RACE-DWARF" then
		if isPhysical then
			mod = mod * 0.90
		end
	end

	-- FAIRY — Fae Grace: AOE damage received -25%
	if raceId == "RACE-FAIRY" then
		if isAOE then
			mod = mod * 0.75
		end
	end

	-- SHADOW — Umbral Veil: elemental damage received +10%
	-- (Hide-on-hit part is PENDING — no Hide status exists yet)
	if raceId == "RACE-SHADOW" then
		if isElemental(element) then
			mod = mod * 1.10
		end
	end

	-- ELEMENTAL SPIRIT — Elemental Flux: elemental damage received +30%
	if raceId == "RACE-ELEMENTAL-SPIRIT" then
		if isElemental(element) then
			mod = mod * 1.30
		end
	end

	-- LICH — Arcane Corruption: Light damage received +50%
	if raceId == "RACE-LICH" then
		if element == "Light" or element == "Holy" then
			mod = mod * 1.50
		end
	end

	return mod
end

--------------------------------------------------
-- MP COST MODIFIER
-- Returns a multiplier for skill MP costs.
-- Called from CommandService before MP validation.
--------------------------------------------------

function RacePassiveService.GetMpCostModifier(unit)
	local raceId = getRaceId(unit)
	if not raceId then return 1.0 end

	-- ELF — Elven Focus: Skill MP Cost -20%
	if raceId == "RACE-ELF" then
		return 0.80
	end

	return 1.0
end

--------------------------------------------------
-- MOVEMENT RANGE MODIFIER
-- Returns an integer offset to movement range.
-- Called from TargetingService.getMovementRange.
--------------------------------------------------

function RacePassiveService.GetMovementRangeModifier(unit)
	local raceId = getRaceId(unit)
	if not raceId then return 0 end

	-- DWARF — Stout Resilience: Movement Range -1
	if raceId == "RACE-DWARF" then return -1 end

	-- ZOMBIE — Undying: Movement Range -1
	if raceId == "RACE-ZOMBIE" then return -1 end

	-- GOLEM — Fortified Frame: Movement Range -1
	if raceId == "RACE-GOLEM" then return -1 end

	return 0
end

--------------------------------------------------
-- GUARD MITIGATION BONUS
-- Returns a float bonus added to base Guard mitigation.
-- Called from CommandService Guard block and CombatResolver Guard check.
--------------------------------------------------

function RacePassiveService.GetGuardMitigationBonus(unit)
	local raceId = getRaceId(unit)
	if not raceId then return 0 end

	-- GOLEM — Fortified Frame: Guard mitigation +20%
	if raceId == "RACE-GOLEM" then
		return 0.20
	end

	return 0
end

--------------------------------------------------
-- TITAN 2H-AS-1H
-- Returns true if this unit can equip 2H melee weapons as 1H.
--------------------------------------------------

function RacePassiveService.CanEquip2HAsWith1H(unit)
	local raceId = getRaceId(unit)
	return raceId == "RACE-TITAN"
end

--------------------------------------------------
-- STAT MODIFIERS (permanent race penalties)
-- Returns a table of { stat = multiplier } for stats
-- that get a permanent percentage penalty.
-- Applied in EquipmentService.RebuildUnitStats AFTER
-- all other bonuses, BEFORE HP/MP derivation.
--------------------------------------------------

function RacePassiveService.GetStatModifiers(unit)
	local raceId = getRaceId(unit)
	if not raceId then return nil end

	-- ORC — Bloodlust: INT -15% (permanent)
	if raceId == "RACE-ORC" then
		return { INT = -0.15 }
	end

	-- FAIRY — Fae Grace: STR -15% (permanent)
	if raceId == "RACE-FAIRY" then
		return { STR = -0.15 }
	end

	return nil
end

--------------------------------------------------
-- BASIC ATTACK STATUS APPLICATION
-- Returns a status ID to apply on Basic Attack hit,
-- or nil if no status applies.
--------------------------------------------------

function RacePassiveService.GetBasicAttackStatus(unit)
	local raceId = getRaceId(unit)
	if not raceId then return nil end

	-- GOBLIN — Cunning: Basic Attacks apply Poison
	if raceId == "RACE-GOBLIN" then
		return "Poison"
	end

	return nil
end

return RacePassiveService
