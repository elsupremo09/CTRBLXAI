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

-- RaceData: authoritative race lookup for the 2026-10-02 new-race passives.
-- ALL new-race detection goes through RaceData.GetRace(raceId) (nil-safe) --
-- never a direct bracket index into the RaceData module (8-site bug fixed 2026-10-02).
local RaceData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("RaceData")
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

-- New-race detection (2026-10-02 roster). Nil-safe: a nil or unknown raceId
-- (RaceData.GetRace returns nil) is never treated as any race.
local function isRace(unit, raceId)
	local rid = unit and unit.raceId or nil
	if not rid then return false end
	if not RaceData.GetRace(rid) then return false end
	return rid == raceId
end

local function hasTag(tags, wanted)
	if type(tags) ~= "table" then return false end
	for _, t in ipairs(tags) do
		if t == wanted then return true end
	end
	return false
end

-- TIME OF DAY -- no day/night system exists yet.
-- TODO(day/night): when a time-of-day system is built, return "Day" / "Dusk" /
-- "Night" here (and resync stats on a phase change -- see RefreshConditionalStats).
-- Until then this returns nil, so every day/night-gated race passive (Werewolf
-- Moonblood; Vampire's day/night stat swing, also DEFERRED) is DORMANT / no-op.
-- Time-of-day cycle (Dawn/Day/Dusk/Night, one phase per 1000-CT round). Set by
-- BattleCoordinator via SetTimePhase as the battle clock crosses each round
-- boundary. nil until a battle sets it (passives then no-op, as before).
local _currentTimePhase = nil
function RacePassiveService.SetTimePhase(phase)
	_currentTimePhase = phase
end
function RacePassiveService.GetTimePhase()
	return _currentTimePhase
end
local function getTimeOfDay()
	return _currentTimePhase
end

-- Optional TileEffectService (DI) for tile-effect-aware race passives (Treant
-- Forest Wrath reads the Vines effect). Forwarded by CombatResolver.SetTileEffectService.
local _tileEffectService = nil
function RacePassiveService.SetTileEffectService(tes)
	_tileEffectService = tes
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

function RacePassiveService.GetDamageDealtModifier(attacker, element, isAOE, targetUnit)
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

	-- TREANT — Forest Wrath (races row 'Treant', 2026-10-02): +15% damage dealt to
	-- targets standing on Grassland / Forest / Clover Field terrain, or on a tile
	-- carrying the Vines tile effect. ("Forest" is not a TERRAIN_TYPES id today --
	-- kept for forward compatibility; harmless string compare.)
	if targetUnit and targetUnit.tileX and targetUnit.tileY and isRace(attacker, "RACE-TREANT") then
		local tId = GameConstants.GetTerrainId(targetUnit.tileX, targetUnit.tileY)
		local onWildGround = (tId == "Grassland" or tId == "Forest" or tId == "Clover Field")
		if not onWildGround and _tileEffectService and _tileEffectService.GetTileEffect then
			local teff = _tileEffectService.GetTileEffect(targetUnit.tileX, targetUnit.tileY)
			onWildGround = (teff ~= nil and teff.id == "Vines")
		end
		if onWildGround then
			mod = mod * 1.15
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

	-- MERMAID — Tidecaller (races row 'Mermaid'): "All primary stats -10% while not
	-- occupying Water, Wet, or Ice" → as DEFENDER, off water: damage received +10%.
	-- (BUGFIX 2026-10-03: moved here from GetDamageDealtModifier, where it read an
	-- undefined global `defender` and so applied an unconditional +10% dealt.)
	if raceId == "RACE-MERMAID" then
		if not isOnWaterTile(defender) then
			mod = mod * 1.10
		end
	end

	-- CELESTIAL — Radiant Grace (races row 'Celestial', 2026-10-02): Dark damage received +20%
	if element == "Dark" and isRace(defender, "RACE-CELESTIAL") then
		mod = mod * 1.20
	end

	-- DEMON — Infernal Pact (races row 'Demon', 2026-10-02): Holy damage received +20%
	if element == "Holy" and isRace(defender, "RACE-DEMON") then
		mod = mod * 1.20
	end

	-- DRAGONKIN — Dragonscale (races row 'Dragonkin', 2026-10-02): Ice damage received +50%
	if element == "Ice" and isRace(defender, "RACE-DRAGONKIN") then
		mod = mod * 1.50
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

	-- RABBIT FOLK — Hop Step (races row 'Rabbit Folk', 2026-10-02): Movement Range -1
	if isRace(unit, "RACE-RABBIT-FOLK") then return -1 end

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
-- DOWNWARD JUMP MODIFIER (2026-10-02)
-- Integer offset applied ONLY to the downward-jump limit used by voluntary
-- movement (TargetingService.getDownwardJump). Forced displacement is unaffected.
--------------------------------------------------

function RacePassiveService.GetDownwardJumpModifier(unit)
	-- HALFLING — Nimble Steps (races row 'Halfling'): Jump -1 when moving to a
	-- lower elevation (voluntary downward movement only).
	if isRace(unit, "RACE-HALFLING") then return -1 end
	return 0
end

--------------------------------------------------
-- RABBIT FOLK — HOP STEP (2026-10-02)
-- True if this unit may hop a single gap/pit tile in a straight line.
-- Geometry / legality lives in TargetingService.GetMoveCandidates.
--------------------------------------------------

function RacePassiveService.CanHopGap(unit)
	return isRace(unit, "RACE-RABBIT-FOLK")
end

--------------------------------------------------
-- SKILL RANGE MODIFIER (2026-10-02)
-- Integer offset to a skill's targeting range. Applied in BOTH
-- TargetingService.GetSkillCandidates (prompt) and CommandService skill
-- validation so the shown range and the validated range never drift.
--------------------------------------------------

-- Movement skills = skills whose effect relocates the CASTER (DB skills table
-- Effects: Blink teleport, Opportunist's Step path relocation, Skyfall Lance /
-- Dragon Dive leaps, Phantom Exchange swap, Reckless Charge). The data has no
-- "Movement" tag, so they are listed explicitly; isMovement / isCharge flags on
-- a def are also honored.
local MOVEMENT_SKILL_IDS = {
	["SKL-BLINK"]              = true,
	["SKL-OPPORTUNIST-S-STEP"] = true,
	["SKL-SKYFALL-LANCE"]      = true,
	["SKL-DRAGON-DIVE"]        = true,
	["SKL-PHANTOM-EXCHANGE"]   = true,
	["DOC-BERSERKER-01"]       = true,
}

function RacePassiveService.IsMovementSkill(skillDef)
	if type(skillDef) ~= "table" then return false end
	if skillDef.isMovement or skillDef.isCharge then return true end
	return skillDef.id ~= nil and MOVEMENT_SKILL_IDS[skillDef.id] == true
end

function RacePassiveService.GetSkillRangeModifier(unit, skillDef)
	-- HALFLING — Nimble Steps (races row 'Halfling'): Movement skills gain +1 range
	if isRace(unit, "RACE-HALFLING") and RacePassiveService.IsMovementSkill(skillDef) then
		return 1
	end
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

	-- DRAGONKIN — Dragonscale (races row 'Dragonkin', 2026-10-02): while a Burn
	-- instance is active on this unit, all primary stats +15%. (Burn ticks are
	-- nullified in StatusService.ProcessStartOfTurn, but the instance stays so
	-- this still sees it.) Kept in sync mid-battle by RefreshConditionalStats.
	if isRace(unit, "RACE-DRAGONKIN") and unit.statusInstances
		and StatusService.HasStatus(unit, "Burn") then
		return { STR = 0.15, AGI = 0.15, INT = 0.15, VIT = 0.15, DEX = 0.15, LUK = 0.15 }
	end

	-- WEREWOLF — Moonblood (races row 'Werewolf', 2026-10-02): all primary stats
	-- +10% during dusk and night. Reads getTimeOfDay() (time cycle, 2026-10-04).
	-- VAMPIRE — Vampirism day/night swing (races row 'Vampire'): all primary stats
	-- -25% during DAY, +25% during NIGHT (dawn/dusk neutral). Reads the same cycle.
	if isRace(unit, "RACE-VAMPIRE") then
		local tod = getTimeOfDay()
		if tod == "Day" then
			return { STR = -0.25, AGI = -0.25, INT = -0.25, VIT = -0.25, DEX = -0.25, LUK = -0.25 }
		elseif tod == "Night" then
			return { STR = 0.25, AGI = 0.25, INT = 0.25, VIT = 0.25, DEX = 0.25, LUK = 0.25 }
		end
	end

	if isRace(unit, "RACE-WEREWOLF") then
		local tod = getTimeOfDay()
		if tod == "Dusk" or tod == "Night" then
			return { STR = 0.10, AGI = 0.10, INT = 0.10, VIT = 0.10, DEX = 0.10, LUK = 0.10 }
		end
	end

	return nil
end

--------------------------------------------------
-- BASIC ATTACK STATUS APPLICATION
-- Returns a status ID to apply on Basic Attack hit,
-- or nil if no status applies.
--------------------------------------------------

function RacePassiveService.GetBasicAttackStatus(unit, target)
	local raceId = getRaceId(unit)
	if not raceId then return nil end

	-- GOBLIN — Cunning: Basic Attacks apply Poison
	if raceId == "RACE-GOBLIN" then
		return "Poison"
	end

	-- CRAB — Pincer Grip (races row 'Crab', 2026-10-02): Basic Attacks against a
	-- target within range 1 (8 adjacent tiles, Chebyshev distance 1) inflict Wounded.
	if target and unit.tileX and unit.tileY and target.tileX and target.tileY
		and isRace(unit, "RACE-CRAB") then
		local dist = math.max(math.abs(unit.tileX - target.tileX), math.abs(unit.tileY - target.tileY))
		if dist == 1 then
			return "Wounded"
		end
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
-- LIZARDMEN — SPIKED HIDE (2026-10-02)
-- Reflected damage the ATTACKER takes when it lands a MELEE hit on this
-- defender from one of the 8 adjacent tiles (Chebyshev 1). The caller
-- (CombatResolver.ApplyOutcome) owns the melee / not-AOE / adjacency gate and
-- applies the damage DIRECTLY (not via ApplyOutcome), so a reflect can never
-- re-trigger reflects / lifesteal / other reaction hooks (TRG-010 pattern).
-- DB races row 'Lizardmen': reflected damage = the Lizardman's current level.
--------------------------------------------------

function RacePassiveService.GetMeleeReflectDamage(defender)
	if not isRace(defender, "RACE-LIZARDMEN") then return 0 end
	return math.max(0, math.floor(defender.level or 1))
end

--------------------------------------------------
-- OGRE — BRUTISH BULK (2026-10-02)
-- Weapon WT multiplier (EquipmentService.RebuildUnitStats) and on-hit target
-- RT delay (CombatResolver.ApplyOutcome).
-- DB races row 'Ogre': Weapon WT +20%; on a successful hit, bonus RT delay on
-- the TARGET = 50% of this unit's (effective) Weapon WT.
--------------------------------------------------

function RacePassiveService.GetWeaponWtMultiplier(unit)
	if isRace(unit, "RACE-OGRE") then return 1.20 end
	return 1.0
end

function RacePassiveService.GetOnHitRtDelay(attacker)
	if not isRace(attacker, "RACE-OGRE") then return 0 end
	-- Effective Weapon WT = Weapon WT (already x1.20 via RebuildUnitStats) after the
	-- STR reduction -- same formula as CommandService.calcBasicAttackBaseRt.
	local effWt = attacker.derivedStats and attacker.derivedStats.effectiveWt
	if effWt == nil then
		local str = attacker.effectiveStats and attacker.effectiveStats.STR or 10
		effWt = math.round(GameConstants.CalcEffectiveWt(attacker.weaponWt or 0, str))
	end
	return math.max(0, math.round(0.50 * effWt))
end

--------------------------------------------------
-- FELINE — NINE LIVES (2026-10-02)
-- DB races row 'Feline': immune to fall damage (any downward displacement, any
-- height); collision/knockback-impact damage received +20%. Fall damage ONLY --
-- terrain / chasm-floor / tile ground-effects are untouched.
--------------------------------------------------

function RacePassiveService.IsFallDamageImmune(unit)
	return isRace(unit, "RACE-FELINE")
end

function RacePassiveService.GetCollisionDamageMultiplier(unit)
	if isRace(unit, "RACE-FELINE") then return 1.20 end
	return 1.0
end

--------------------------------------------------
-- SKILL POTENCY (INT) CONTRIBUTION MODIFIER (2026-10-02)
-- Skill Potency = 1 + p, p = INT / (200 + INT)  (GameConstants.CalcSkillPotency).
-- Celestial / Demon boost ONLY the INT contribution p by 20% for Holy / Dark
-- tagged SKILLS: potency becomes 1 + 1.20p. Returned as a multiplier on the
-- existing potency: (1 + 1.20p) / (1 + p). Only called from skill resolution
-- (never Basic Attacks or items).
-- DB races rows 'Celestial' (Radiant Grace) / 'Demon' (Infernal Pact).
--------------------------------------------------

function RacePassiveService.GetSkillPotencyMultiplier(unit, skillTags, int)
	local boosted = (hasTag(skillTags, "Holy") and isRace(unit, "RACE-CELESTIAL"))
		or (hasTag(skillTags, "Dark") and isRace(unit, "RACE-DEMON"))
	if not boosted then return 1.0 end
	int = int or (unit.effectiveStats and unit.effectiveStats.INT) or 0
	if int <= 0 then return 1.0 end
	local p = int / (200 + int)
	return (1 + 1.20 * p) / (1 + p)
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

--------------------------------------------------
-- CONDITIONAL STAT SYNC (2026-10-02)
-- Race stat mods that depend on battle state (Dragonkin: Burn active) are folded
-- in by EquipmentService.RebuildUnitStats via GetStatModifiers. This re-runs that
-- canonical, idempotent rebuild ONLY when the condition flips, so effectiveStats /
-- derivedStats track the Burn instance mid-battle.
-- Called from CombatResolver.ApplyOutcome and the BattleCoordinator turn hooks.
-- TODO(day/night): add the Werewolf time-of-day flip here once it exists.
--------------------------------------------------

local _equipmentService = nil
local function rebuildStats(unit)
	if _equipmentService == nil then
		-- Lazy require at RUNTIME: EquipmentService requires this module at load
		-- time; by the time this runs both are cached, so there is no require cycle.
		local ok, es = pcall(function() return require(script.Parent.EquipmentService) end)
		_equipmentService = ok and es or false
	end
	if _equipmentService and _equipmentService.RebuildUnitStats then
		_equipmentService.RebuildUnitStats(unit)
		return true
	end
	return false
end

function RacePassiveService.RefreshConditionalStats(unit)
	if not unit or not unit.isAlive then return false end
	-- DRAGONKIN — Burn-conditional stat bonus.
	if isRace(unit, "RACE-DRAGONKIN") then
		local burning = (unit.statusInstances ~= nil and StatusService.HasStatus(unit, "Burn") ~= nil)
		if (unit._dragonscaleActive == true) == burning then return false end
		unit._dragonscaleActive = burning
		local rebuilt = rebuildStats(unit)
		print(string.format(
			"[RacePassiveService] Dragonkin Dragonscale: %s Burn %s -> primary stats %s (rebuilt=%s)",
			unit.name or "?", burning and "ACTIVE" or "ended", burning and "+15%" or "normal", tostring(rebuilt)
		))
		return rebuilt
	end

	-- VAMPIRE / WEREWOLF — time-of-day stat swings. Resync when the phase-driven
	-- bonus state flips (Day/Night for Vampire; Dusk/Night for Werewolf). Store a
	-- per-unit flag so we rebuild only on change, mirroring Dragonscale.
	if isRace(unit, "RACE-VAMPIRE") or isRace(unit, "RACE-WEREWOLF") then
		local tod = getTimeOfDay()
		local active
		if isRace(unit, "RACE-VAMPIRE") then
			-- Any non-neutral phase changes stats (Day = debuff, Night = buff).
			active = (tod == "Day" or tod == "Night") and tod or false
		else
			active = (tod == "Dusk" or tod == "Night") and true or false
		end
		if unit._todStatActive == active then return false end
		unit._todStatActive = active
		local rebuilt = rebuildStats(unit)
		print(string.format(
			"[RacePassiveService] Time-of-day stats: %s phase=%s -> state=%s (rebuilt=%s)",
			unit.name or "?", tostring(tod), tostring(active), tostring(rebuilt)
		))
		return rebuilt
	end

	return false
end

--------------------------------------------------
-- TURN HOOKS (2026-10-02) -- called by BattleCoordinator.
--   OnTurnStart: when a unit's turn OPENS (after StatusService.ProcessStartOfTurn).
--   OnTurnEnd:   after the unit's EndTurn status tick.
-- BattleCoordinator has no broadcaster handle, so units whose HP / statuses
-- changed are handed to the driver via state.ctStatusUnits (Main refreshes them
-- with UnitStateChanged) -- same pattern as Regeneration / Zombie revive.
--------------------------------------------------

local function queueRefresh(state, unit)
	if not state then return end
	state._racePassiveRefresh = state._racePassiveRefresh or {}
	table.insert(state._racePassiveRefresh, unit)
end

function RacePassiveService.OnTurnStart(unit, state)
	-- Flush end-of-turn refreshes queued by OnTurnEnd. Done here (after
	-- AdvanceClock's CT tick re-created state.ctStatusUnits) so Main sees them.
	if state and state._racePassiveRefresh then
		state.ctStatusUnits = state.ctStatusUnits or {}
		for _, u in ipairs(state._racePassiveRefresh) do
			table.insert(state.ctStatusUnits, u)
		end
		state._racePassiveRefresh = nil
	end

	if not unit or not unit.isAlive then return end

	-- TROLL — Regrowth (races row 'Troll'): at the start of each of its turns,
	-- regenerate 20% of MISSING HP = round(0.20 x (Max HP - Current HP)).
	if unit.maxHp and unit.currentHp and isRace(unit, "RACE-TROLL") then
		local missing = unit.maxHp - unit.currentHp
		local heal = math.round(0.20 * missing)
		if heal > 0 then
			unit.currentHp = math.min(unit.maxHp, unit.currentHp + heal)
			print(string.format(
				"[RacePassiveService] Troll Regrowth: %s heals %d (20%% of %d missing) | HP: %d/%d",
				unit.name or "?", heal, missing, unit.currentHp, unit.maxHp
			))
			if state then
				state.ctStatusUnits = state.ctStatusUnits or {}
				table.insert(state.ctStatusUnits, unit)
			end
		end
	end

	-- DRAGONKIN — keep the Burn-conditional stat bonus in sync.
	if RacePassiveService.RefreshConditionalStats(unit) and state then
		state.ctStatusUnits = state.ctStatusUnits or {}
		table.insert(state.ctStatusUnits, unit)
	end
end

function RacePassiveService.OnTurnEnd(unit, state)
	if not unit or not unit.isAlive then return end

	-- INSECTOID — Molt Cycle (races row 'Insectoid'): at the END of every 3rd turn
	-- (3, 6, 9, ...) ALL statuses -- buffs AND debuffs -- are removed, simultaneously
	-- and unavoidably. The per-battle turn counter lives on the battle state.
	if isRace(unit, "RACE-INSECTOID") then
		local counts
		if state then
			state._moltTurnCounts = state._moltTurnCounts or {}
			counts = state._moltTurnCounts
		else
			unit._moltTurnCounts = unit._moltTurnCounts or {}
			counts = unit._moltTurnCounts
		end
		local key = unit.id or "self"
		local n = (counts[key] or 0) + 1
		counts[key] = n
		if n % 3 == 0 then
			local list = unit.statusInstances
			local removed = {}
			if list then
				for i = #list, 1, -1 do
					table.insert(removed, 1, tostring(list[i].id))
					table.remove(list, i)
				end
			end
			print(string.format(
				"[RacePassiveService] Insectoid Molt Cycle: %s turn %d -> cleared %d status(es) [%s]",
				unit.name or "?", n, #removed, table.concat(removed, ", ")
			))
			if #removed > 0 then queueRefresh(state, unit) end
		end
	end

	-- DRAGONKIN — Burn may have expired in the EndTurn tick (or been molted away).
	if RacePassiveService.RefreshConditionalStats(unit) then
		queueRefresh(state, unit)
	end
end

return RacePassiveService
