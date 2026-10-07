-- RacePassiveService.lua
-- CTRBLXAI | Slice 4F — Race Passive Functions
--
-- Centralized query interface for race passive effects.
-- Other services call these to apply race-based modifiers.
-- Units without a raceId receive neutral (no-op) values.

local RacePassiveService = {}

local StatusService = require(script.Parent.StatusService)


local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)
--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function getRaceId(unit)
	return unit and unit.raceId or nil
end

local function isOnWaterTile(unit)
	if not unit or not unit.tileX or not unit.tileY then return false end
	local terrainId = GameConstants.GetTerrainId(unit.tileX, unit.tileY)
	return terrainId == "Shallow Water"
		or terrainId == "Deep Water"
		or terrainId == "Ice"
		or terrainId == "Swamp"
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

	-- MERMAID — Tidecaller: off water, all stats -10% → damage dealt -10%
	if raceId == "RACE-MERMAID" then
		if not isOnWaterTile(attacker) then
			mod = mod * 0.90
		end
	end

	-- MERMAID — Tidecaller: off water, all stats -10% → damage received +10%
	if raceId == "RACE-MERMAID" then
		if not isOnWaterTile(defender) then
			mod = mod * 1.10
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
	-- (Hide-on-hit: implemented via RacePassiveService.OnDamageReceived)
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
-- JUMP MODIFIER
-- Returns an integer offset to jump height.
-- Called from TargetingService.getJump.
--------------------------------------------------

function RacePassiveService.GetJumpModifier(unit)
	local raceId = getRaceId(unit)
	if not raceId then return 0 end

	-- ELF — Elven Focus: Jump +1
	if raceId == "RACE-ELF" then return 1 end

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

--------------------------------------------------
-- VAMPIRE LIFESTEAL
-- Returns the HP to heal on the attacker after dealing damage.
-- Called from CombatResolver.ApplyOutcome after damage is applied.
--
-- DB (Vampire passive): Heal 15% of direct damage dealt,
-- reduced to 5% for AOE damage.
-- Day/night stat modifier: DEFERRED (no time-of-day system).
--------------------------------------------------

function RacePassiveService.GetLifestealAmount(attacker, actualDamage, isAOE)
	local raceId = getRaceId(attacker)
	if raceId ~= "RACE-VAMPIRE" then return 0 end
	if actualDamage <= 0 then return 0 end

	local rate = isAOE and 0.05 or 0.15
	return math.max(1, math.round(actualDamage * rate))
end

--------------------------------------------------
-- SHADOW HIDE-ON-HIT
-- After receiving direct damage, gain Hide for 1 turn.
-- Called from CombatResolver.ApplyOutcome after damage is applied.
--
-- DB (Shadow passive): "After receiving direct damage, gain
-- Hide for one turn."
--------------------------------------------------

function RacePassiveService.OnDamageReceived(defender, actualDamage, sourceUnitId)
	local raceId = getRaceId(defender)
	if not raceId then return end
	if actualDamage <= 0 or not defender.isAlive then return end

	-- SHADOW — Umbral Veil: gain Hide for 1 turn on damage
	if raceId == "RACE-SHADOW" then
		StatusService.ApplyStatus(defender, "Hide", sourceUnitId or "passive")
		-- Override duration to 1 turn (base Hide is 3 turns)
		if defender.statusInstances then
			for _, inst in ipairs(defender.statusInstances) do
				if inst.id == "Hide" then
					inst.remainingTurns = 1
					break
				end
			end
		end
		print(string.format(
			"[RacePassiveService] Shadow Umbral Veil: %s gains Hide (1 turn)", defender.name
		))
	end
end

--------------------------------------------------
-- LICH ELEMENT→STATUS OVERRIDE
-- Returns the status to apply for a given element, overriding
-- the default element→status triggers.
-- Returns nil if no override (use default behavior).
--
-- DB (Lich passive): "Fire→Burn, Water→Frozen, Earth→Petrify,
-- Dark→Poison"
--------------------------------------------------

function RacePassiveService.GetElementStatusOverride(attacker, element)
	local raceId = getRaceId(attacker)
	if raceId ~= "RACE-LICH" then return nil end

	if element == "Fire" then return "Burn"       -- same as default
	elseif element == "Water" then return "Frozen" -- default is Wet
	elseif element == "Earth" then return "Petrify"-- no default
	elseif element == "Dark" then return "Poison"  -- no default
	end
	return nil
end

--------------------------------------------------
-- MERMAID — TIDECALLER
-- Range +1 while on Water/Wet/Ice tile.
-- All primary stats -10% while NOT on Water/Wet/Ice.
--------------------------------------------------

function RacePassiveService.GetRangeModifier(unit)
	local raceId = getRaceId(unit)
	if raceId ~= "RACE-MERMAID" then return 0 end
	if isOnWaterTile(unit) then return 1 end
	return 0
end

function RacePassiveService.GetMermaidStatPenalty(unit)
	local raceId = getRaceId(unit)
	if raceId ~= "RACE-MERMAID" then return nil end
	if isOnWaterTile(unit) then return nil end
	-- Not on water: all primary stats -10%
	return {
		STR = -0.10, AGI = -0.10, INT = -0.10,
		VIT = -0.10, DEX = -0.10, LUK = -0.10,
	}
end

--------------------------------------------------
-- ZOMBIE — UNDYING
-- Revive 3 turns after KO with 50% Max HP.
-- Uses CT accumulation: when a KO'd Zombie accumulates
-- 3000 CT (equivalent of 3 turns), revive.
--------------------------------------------------

local ZOMBIE_REVIVE_CT = 3000

function RacePassiveService.ProcessZombieRevive(unit, ctPassed)
	local raceId = getRaceId(unit)
	if raceId ~= "RACE-ZOMBIE" then return false end
	if unit.isAlive then return false end

	if not unit.zombieReviveUsed then
		if not unit.zombieKoCt then unit.zombieKoCt = 0 end
		unit.zombieKoCt = unit.zombieKoCt + ctPassed

		if unit.zombieKoCt >= ZOMBIE_REVIVE_CT then
			-- Revive with 50% Max HP
			unit.isAlive = true
			unit.currentHp = math.ceil(unit.maxHp * 0.50)
			unit.remainingRt = unit.startingRt or 400
			unit.zombieReviveUsed = true
			unit.zombieKoCt = nil
			print(string.format(
				"[RacePassiveService] Zombie Undying: %s revives with %d/%d HP",
				unit.name, unit.currentHp, unit.maxHp
			))
			return true
		end
	end
	return false
end

function RacePassiveService.OnUnitKO(unit)
	local raceId = getRaceId(unit)
	if raceId == "RACE-ZOMBIE" and not unit.zombieReviveUsed then
		unit.zombieKoCt = 0
		print(string.format(
			"[RacePassiveService] Zombie Undying: %s KO'd — revive timer started",
			unit.name
		))
	end
end

--------------------------------------------------
-- ANDROID — EXTENDING ARMS
-- Push becomes Pull (reverse direction).
-- Push Force +3.
-- Push cannot target adjacent units (distance must be > 1).
--------------------------------------------------

function RacePassiveService.GetPushOverride(unit)
	local raceId = getRaceId(unit)
	if raceId ~= "RACE-ANDROID" then return nil end
	return {
		reverseDirection = true,  -- Pull instead of Push
		forceBonus = 3,           -- +3 Force
		minDistance = 2,          -- Cannot target adjacent
		maxDistance = 4,          -- Extended reach (1 base + 3 bonus)
		label = "Pull",          -- Display label
	}
end

return RacePassiveService
