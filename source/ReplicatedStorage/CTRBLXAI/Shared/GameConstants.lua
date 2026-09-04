-- GameConstants.lua
-- CTRBLXAI | Shared numeric constants (Slice 3: Skills and Real Combat)
--
-- Single source of truth for constants that are used by more than one
-- server module. Require this module instead of defining local copies.
--
-- Location: ReplicatedStorage/CTRBLXAI/Shared/GameConstants
-- (ReplicatedStorage so both server and future client modules can access it)

local GameConstants = {}

--------------------------------------------------
-- TIMELINE  (from DB: core_stats — Timeline AP RT)
--------------------------------------------------

GameConstants.BASE_RT_STANDARD = 400
GameConstants.AP_PER_TURN_STANDARD = 2

GameConstants.BASE_RT_BOSS     = 300
GameConstants.AP_PER_TURN_BOSS = 3

GameConstants.REST_RT_MULTIPLIER = 0.75

--------------------------------------------------
-- ACTION RT COST MULTIPLIERS
--------------------------------------------------

GameConstants.MOVE_RT_FACTOR         = 0.0625
GameConstants.BASIC_ATTACK_RT_FACTOR = 0.10
-- Guard
GameConstants.GUARD_MITIGATION      = 0.35   -- base 35% damage reduction
GameConstants.GUARD_CAP             = 0.80   -- maximum Guard mitigation (passives can add up to cap)
GameConstants.GUARD_RT_BASE_FACTOR  = 0.10   -- round(Modified Base RT × this)
GameConstants.GUARD_OFFHAND_WT_FACTOR = 0.50 -- + 50% of Effective Armor Off-Hand WT


--------------------------------------------------
-- ELEVATION  (from DB: movement_targeting — Elevation & Displacement)
--------------------------------------------------

GameConstants.ELEVATION_MAP = {
	{ 1, 1, 1, 1, 1, 1, 1, 1 }, -- row 1
	{ 1, 1, 2, 2, 2, 2, 1, 1 }, -- row 2
	{ 1, 2, 3, 2, 2, 3, 2, 1 }, -- row 3
	{ 1, 2, 2, 1, 1, 2, 2, 1 }, -- row 4
	{ 1, 2, 2, 1, 1, 2, 2, 1 }, -- row 5
	{ 1, 2, 3, 2, 2, 3, 2, 1 }, -- row 6
	{ 1, 1, 2, 2, 2, 2, 1, 1 }, -- row 7
	{ 1, 1, 1, 1, 1, 1, 1, 1 }, -- row 8
}

function GameConstants.GetElevation(tileX, tileY)
	local row = GameConstants.ELEVATION_MAP[tileY]
	if row then
		return row[tileX] or 1
	end
	return 1
end

--------------------------------------------------
-- TERRAIN TYPES  (from DB: terrain_effects)
--------------------------------------------------

GameConstants.TERRAIN_TYPES = {
	Clear     = { id = "Clear",     moveCost = 1 },
	Grassland = { id = "Grassland", moveCost = 1 },
	Rocky     = { id = "Rocky",     moveCost = 1 },
	Mud       = { id = "Mud",       moveCost = 2 },
}

GameConstants.TERRAIN_MAP = {
	{ "Clear",     "Clear",     "Clear",     "Grassland", "Grassland", "Clear",     "Clear",     "Clear"     },
	{ "Clear",     "Grassland", "Rocky",     "Grassland", "Grassland", "Rocky",     "Grassland", "Clear"     },
	{ "Clear",     "Rocky",     "Rocky",     "Rocky",     "Rocky",     "Rocky",     "Rocky",     "Clear"     },
	{ "Clear",     "Rocky",     "Rocky",     "Mud",       "Mud",       "Rocky",     "Rocky",     "Clear"     },
	{ "Clear",     "Rocky",     "Rocky",     "Mud",       "Mud",       "Rocky",     "Rocky",     "Clear"     },
	{ "Clear",     "Rocky",     "Rocky",     "Rocky",     "Rocky",     "Rocky",     "Rocky",     "Clear"     },
	{ "Clear",     "Grassland", "Rocky",     "Grassland", "Grassland", "Rocky",     "Grassland", "Clear"     },
	{ "Clear",     "Clear",     "Clear",     "Grassland", "Grassland", "Clear",     "Clear",     "Clear"     },
}

function GameConstants.GetTerrainCost(tileX, tileY)
	local row = GameConstants.TERRAIN_MAP[tileY]
	if row then
		local terrainId = row[tileX]
		if terrainId and GameConstants.TERRAIN_TYPES[terrainId] then
			return GameConstants.TERRAIN_TYPES[terrainId].moveCost
		end
	end
	return 1
end

function GameConstants.GetTerrainId(tileX, tileY)
	local row = GameConstants.TERRAIN_MAP[tileY]
	if row then
		return row[tileX] or "Clear"
	end
	return "Clear"
end

--------------------------------------------------
-- BLOCKERS
--------------------------------------------------

GameConstants.BLOCKERS = {
	{ tileX = 4, tileY = 3 },
	{ tileX = 5, tileY = 6 },
	{ tileX = 2, tileY = 4 },
	{ tileX = 7, tileY = 5 },
}

function GameConstants.IsBlocked(tileX, tileY)
	for _, b in ipairs(GameConstants.BLOCKERS) do
		if b.tileX == tileX and b.tileY == tileY then
			return true
		end
	end
	return false
end

--------------------------------------------------
-- POSITIONAL DAMAGE MODIFIER
--------------------------------------------------

GameConstants.POSITIONAL_MODIFIER_PER_LEVEL = 0.10
GameConstants.POSITIONAL_MODIFIER_MIN       = 0.70
GameConstants.POSITIONAL_MODIFIER_MAX       = 1.30

function GameConstants.GetPositionalModifier(attackerTileX, attackerTileY, defenderTileX, defenderTileY)
	local aElev = GameConstants.GetElevation(attackerTileX, attackerTileY)
	local dElev = GameConstants.GetElevation(defenderTileX, defenderTileY)
	local diff  = aElev - dElev
	local mod   = 1 + GameConstants.POSITIONAL_MODIFIER_PER_LEVEL * diff
	return math.clamp(mod, GameConstants.POSITIONAL_MODIFIER_MIN, GameConstants.POSITIONAL_MODIFIER_MAX)
end

--------------------------------------------------
-- STATUS DEFINITIONS  (from DB: elements_statuses)
--
-- Slice 3 adds: Poison and Burn (DoT debuffs)
-- Poison: 5 turns, Damage = round(MaxHP × 0.15 × DebuffResistance)
--         Reapplication: refresh duration. Undead immune.
-- Burn:   3 turns, stored damage model.
--         On application: storedBurn = round(fireDamageDealt × 0.20)
--         Tick = round(storedBurn × DebuffResistance)
--         Reapplication: adds stored Burn damage and extends duration
--------------------------------------------------

GameConstants.STATUSES = {
	Slow = {
		id           = "Slow",
		kind         = "Debuff",
		duration     = 3,
		reapply      = "refresh",
		rtMultiplier = 1.10,
		dotType      = nil,
	},
	Poison = {
		id           = "Poison",
		kind         = "Debuff",
		duration     = 5,
		reapply      = "refresh",
		rtMultiplier = nil,
		dotType      = "Poison",
		-- Damage = round(MaxHP × 0.15 × debuffResistance)
		-- debuffResistance defaults to 1.0 (no resistance system yet)
		dotFraction  = 0.15,
	},
	Burn = {
		id           = "Burn",
		kind         = "Debuff",
		duration     = 3,
		reapply      = "accumulate", -- adds stored damage + extends duration
		rtMultiplier = nil,
		dotType      = "Burn",
		-- storedBurn set on application; tick = round(storedBurn × debuffResistance)
		burnFraction = 0.20,
	},
	Guard = {
		id           = "Guard",
		kind         = "Buff",
		duration     = 2,        -- survives the EndTurn tick on the application turn;
		                         -- expires at EndTurn of the unit's NEXT ready turn
		reapply      = "refresh",
		dispellable  = true,     -- removed by Purge/Dispel
		removedByCC  = true,     -- removed by hard CC (Sleep, Petrify, Stun when defined)
		dotType      = nil,
	},

	-- ===== DAMAGE OVER TIME (new) =====

	Venom = {
		id           = "Venom",
		kind         = "Debuff",
		duration     = nil,       -- Unlimited until cured
		reapply      = "stack",   -- Venom Strength +1 on reapply
	},

	Bleed = {
		id           = "Bleed",
		kind         = "Debuff",
		duration     = nil,
		durationCt   = 2000,
		reapply      = "chain",   -- Refresh self + apply Raptured
	},

	Raptured = {
		id           = "Raptured",
		kind         = "Debuff",
		duration     = 5,
		reapply      = "chain",   -- Refresh self + apply Wounded
	},

	Wounded = {
		id           = "Wounded",
		kind         = "Debuff",
		duration     = 3,
		reapply      = "chain",   -- Refresh self + apply Bleed
	},

	-- ===== HAZARD CONDITIONS =====

	Drowning = {
		id           = "Drowning",
		kind         = "Debuff",
		duration     = nil,       -- Unlimited while valid
		reapply      = "none",
		implemented  = false,     -- BLOCKED: needs water tile system
	},

	Sinking = {
		id           = "Sinking",
		kind         = "Debuff",
		duration     = nil,       -- Unlimited while valid
		reapply      = "none",
		blocks       = { Move = true },
		implemented  = false,     -- BLOCKED: needs sinking tile system
	},

	-- ===== DEBUFFS =====

	Blind = {
		id           = "Blind",
		kind         = "Debuff",
		duration     = nil,
		durationCt   = 2000,
		reapply      = "refresh",
	},

	Confuse = {
		id           = "Confuse",
		kind         = "Debuff",
		duration     = 3,
		reapply      = "refresh",
	},

	Silence = {
		id           = "Silence",
		kind         = "Debuff",
		duration     = nil,
		durationCt   = 2000,
		reapply      = "refresh",
		blocks       = { Skills = true },
	},

	Mute = {
		id           = "Mute",
		kind         = "Debuff",
		duration     = nil,
		durationCt   = 3000,
		reapply      = "refresh",
	},

	Break = {
		id           = "Break",
		kind         = "Debuff",
		duration     = nil,
		durationCt   = 3000,
		reapply      = "refresh",
	},

	Disarmed = {
		id           = "Disarmed",
		kind         = "Debuff",
		duration     = nil,
		durationCt   = 3000,
		reapply      = "refresh",
		blocks       = { BasicAttack = true },
	},

	Pinned = {
		id           = "Pinned",
		kind         = "Debuff",
		duration     = nil,
		durationCt   = 1000,
		reapply      = "refresh",
		blocks       = { Move = true },
	},

	Crippled = {
		id           = "Crippled",
		kind         = "Debuff",
		duration     = 5,
		reapply      = "refresh",
	},

	["Mana Burn"] = {
		id           = "Mana Burn",
		kind         = "Debuff",
		duration     = 3,
		reapply      = "refresh",
	},

	Petrify = {
		id           = "Petrify",
		kind         = "Debuff",
		duration     = nil,
		durationCt   = 1500,
		reapply      = "refresh",
		blocks       = { All = true },
		skipsTurn    = true,
	},

	-- ===== TEMPO MODIFIERS =====

	Haste = {
		id           = "Haste",
		kind         = "Buff",
		duration     = 3,
		reapply      = "refresh",
		rtMultiplier = 0.90,
	},

	Frenzy = {
		id           = "Frenzy",
		kind         = "Buff",
		duration     = 3,
		reapply      = "refresh",
	},

	Wet = {
		id           = "Wet",
		kind         = "Debuff",
		duration     = 5,
		reapply      = "refresh",
	},

	Frozen = {
		id           = "Frozen",
		kind         = "Debuff",
		duration     = 3,
		reapply      = "refresh",
	},

	-- ===== SPECIAL CONDITIONS =====

	Undead = {
		id           = "Undead",
		kind         = "Special",
		duration     = nil,       -- Permanent or temporary
		reapply      = "none",
	},

	Overflow = {
		id           = "Overflow",
		kind         = "Buff",
		duration     = 3,
		reapply      = "extend",
		implemented  = false,     -- BLOCKED: pending clarification
	},

	-- ===== HEALING / RESOURCE BUFFS =====

	Regeneration = {
		id           = "Regeneration",
		kind         = "Buff",
		duration     = nil,
		durationCt   = 3000,
		reapply      = "extend",
	},

	Recharge = {
		id           = "Recharge",
		kind         = "Buff",
		duration     = nil,
		durationCt   = 1200,
		reapply      = "refresh",
	},

	-- ===== COMBAT BUFFS =====

	Hide = {
		id           = "Hide",
		kind         = "Buff",
		duration     = 3,
		reapply      = "refresh",
	},

	Blessed = {
		id           = "Blessed",
		kind         = "Buff",
		duration     = 4,
		reapply      = "refresh",
	},

	Cursed = {
		id           = "Cursed",
		kind         = "Debuff",
		duration     = 4,
		reapply      = "refresh",
	},

	Enlightened = {
		id           = "Enlightened",
		kind         = "Buff",
		duration     = nil,
		durationCt   = 3000,
		reapply      = "stack",
	},

	-- ===== STATE BUFFS =====

	Flight = {
		id           = "Flight",
		kind         = "Buff",
		duration     = 3,
		reapply      = "refresh",
	},

	["Giant Transformation"] = {
		id           = "Giant Transformation",
		kind         = "Buff",
		duration     = nil,
		durationCt   = 3000,
		reapply      = "refresh",
	},

	-- ===== COMBAT STATES =====

	["Knock-out"] = {
		id           = "Knock-out",
		kind         = "Special",
		duration     = nil,
		durationCt   = 3000,
		reapply      = "none",
		blocks       = { All = true },
		skipsTurn    = true,
	},

	Rush = {
		id           = "Rush",
		kind         = "Buff",
		duration     = 4,
		reapply      = "refresh",
	},

	Weakened = {
		id           = "Weakened",
		kind         = "Debuff",
		duration     = nil,
		durationCt   = 2000,
		reapply      = "refresh",
	},

	-- ===== HARD CONTROL =====

	Sleep = {
		id           = "Sleep",
		kind         = "Debuff",
		duration     = 2,
		reapply      = "none",
		blocks       = { All = true },
		skipsTurn    = true,
	},

	["Sleep Immunity"] = {
		id           = "Sleep Immunity",
		kind         = "Buff",
		duration     = 2,
		reapply      = "refresh",
		undispellable = true,
	},

	-- ===== DEFERRED =====

	Stun = {
		id           = "Stun",
		kind         = "Debuff",
		duration     = nil,
		reapply      = "refresh",
		blocks       = { All = true },
		skipsTurn    = true,
		implemented  = false,     -- DEFERRED: no DB definition yet
	},
}

--------------------------------------------------
-- SKILL DEFINITIONS (Slice 3: expanded catalog)
--
-- Simplified for implementation. Full formulas from DB are adapted
-- for our current Effective Skill Level = 1 demo.
-- L = Effective Skill Level (using 1 for now)
-- Weapon WT = weaponWt on the unit
-- Weapon Attack Power = weaponDamage × (1 + STR/200) [for Physical]
--------------------------------------------------

GameConstants.SKILLS = {
	-- ===== SINGLE TARGET DAMAGE =====
	power_strike = {
		id            = "skill_power_strike",
		name          = "Power Strike",
		tags          = { "Direct Damage", "Physical" },
		targetRules   = "Enemy Unit",
		range         = 1,
		pattern       = "Single",
		mpCost        = 3,  -- round(3 + 0.08×(1-1)) = 3
		rtCost        = 60, -- simplified: round(weaponWt × 1.25) approx
		channelTime   = 0,
		power         = 1.25, -- multiplier on Weapon Attack Power
		inheritStr    = true,
		appliesStatus = nil,
		aoePattern    = nil,
	},
	crippling_shot = {
		id            = "skill_crippling_shot",
		name          = "Crippling Shot",
		tags          = { "Direct Damage", "Physical", "Debuff" },
		targetRules   = "Enemy Unit",
		range         = 3,
		pattern       = "Single",
		mpCost        = 3,
		rtCost        = 40,
		channelTime   = 0,
		power         = 0.80, -- weaker shot but applies Slow
		inheritStr    = true,
		appliesStatus = "Slow",
		aoePattern    = nil,
	},

	-- ===== AOE DAMAGE (Cleave) =====
	-- DB: SKL-SWEEPING-CUT: Authored Cleave, range 1, power 0.90×WAP
	sweeping_cut = {
		id            = "skill_sweeping_cut",
		name          = "Sweeping Cut",
		tags          = { "Direct Damage", "Physical" },
		targetRules   = "Enemy Unit",
		range         = 1,
		pattern       = "Cleave", -- hits all enemies adjacent to caster in a 3-tile arc
		mpCost        = 4, -- round(4 + 0.10×(1-1)) = 4
		rtCost        = 75, -- round(weaponWt × 1.50) approx
		channelTime   = 0,
		power         = 0.90,
		inheritStr    = true,
		appliesStatus = nil,
		-- Cleave pattern: the 3 tiles in front of the caster (based on facing toward target)
		-- Implementation: hits primary target + all other enemies within range 1
		-- that are within 1 tile of the primary target.
		aoePattern    = "Cleave",
	},

	-- ===== FIRE SKILL (applies Burn) =====
	-- DB: SKL-FIRE-BOLT: range 4, power 1.10×WAP, Fire damage → generates Burn
	fire_bolt = {
		id            = "skill_fire_bolt",
		name          = "Fire Bolt",
		tags          = { "Direct Damage", "Fire" },
		targetRules   = "Enemy Unit",
		range         = 4,
		pattern       = "Single",
		mpCost        = 3,
		rtCost        = 50,
		channelTime   = 0,
		power         = 1.10,
		inheritStr    = true,
		appliesStatus = "Burn", -- Burn generated from Fire damage dealt
		aoePattern    = nil,
	},

	-- ===== POISON SKILL =====
	-- No direct DB entry for a "poison bolt" — we'll use a custom skill
	-- that applies Poison. Inspired by Frostbind structure.
	venom_strike = {
		id            = "skill_venom_strike",
		name          = "Venom Strike",
		tags          = { "Direct Damage", "Physical", "Poison" },
		targetRules   = "Enemy Unit",
		range         = 1,
		pattern       = "Single",
		mpCost        = 3,
		rtCost        = 50,
		channelTime   = 0,
		power         = 0.70,
		inheritStr    = true,
		appliesStatus = "Poison",
		aoePattern    = nil,
	},

	-- ===== HEALING =====
	-- DB: SKL-HEALING-LIGHT: ally/self, range 4, Channel 100 CT
	-- Power = (10 + 0.25L + 0.35INT + WeaponDmg×0.30) × SkillPotency
	-- Simplified for Slice 3: flat healing = 10 + 0.35×INT + weaponDamage×0.30
	healing_light = {
		id            = "skill_healing_light",
		name          = "Healing Light",
		tags          = { "Healing", "Holy" },
		targetRules   = "Ally Unit, Self",
		range         = 4,
		pattern       = "Single",
		mpCost        = 4, -- round(4 + 0.12×(1-1)) = 4
		rtCost        = 25, -- round(weaponWt × 0.50) approx
		channelTime   = 100, -- 100 CT channel (demonstrates Channel Time)
		power         = 0,  -- uses custom healing formula
		inheritStr    = false,
		appliesStatus = nil,
		aoePattern    = nil,
		isHealing     = true,
	},
}

--------------------------------------------------
-- EVENT QUEUE LIMITS (from DB: trigger_safety)
--------------------------------------------------

GameConstants.EVENT_QUEUE_HARD_CAP       = 128
GameConstants.EVENT_QUEUE_YIELD_INTERVAL = 32
GameConstants.MAX_SECONDARY_EVENTS       = 20

--------------------------------------------------
-- CHANNEL TIME FORMULA (from DB: core_stats — DEX)
-- Channel Time = Base Channel Time × (1 - DEX / (300 + DEX))
--------------------------------------------------

function GameConstants.CalcChannelTime(baseChannelTime, dex)
	if baseChannelTime <= 0 then return 0 end
	local reduction = dex / (300 + dex)
	return math.max(1, math.round(baseChannelTime * (1 - reduction)))
end

--------------------------------------------------
-- SHARED COMBAT FORMULAS
--------------------------------------------------

-- Bug 1 fix: STR reduces Effective Weapon WT
-- Rule: Effective WT = WT × (1 - STR/(200+STR)) if WT>=0
--        Effective WT = WT × (1 + STR/(200+STR)) if WT<0
function GameConstants.CalcEffectiveWt(rawWt, str)
	str = str or 0
	rawWt = rawWt or 0
	if rawWt >= 0 then
		return rawWt * (1 - str / (200 + str))
	else
		return rawWt * (1 + str / (200 + str))
	end
end

-- Missing 5: Combat Fortune (LUK damage modifier)
-- Rule: Modifier = 0.40 × DeltaLUK / (abs(DeltaLUK) + 150)
--       Multiplier = 1 + Modifier
function GameConstants.CalcCombatFortune(attackerLuk, defenderLuk)
	local delta = (attackerLuk or 10) - (defenderLuk or 10)
	local modifier = 0.40 * delta / (math.abs(delta) + 150)
	return 1 + modifier
end

-- Missing 6: LUK Starting RT
-- Rule: Starting RT = round(Base RT × (1 - 0.30 × LUK / (100 + LUK)))
function GameConstants.CalcStartingRt(baseRt, luk)
	luk = luk or 10
	return math.round(baseRt * (1 - 0.30 * luk / (100 + luk)))
end

-- RT Delay Resistance (VIT reduces incoming RT Delay)
-- Rule: Incoming RT Delay × (1 - VIT / (300 + VIT))
function GameConstants.CalcRtDelayResistance(rawDelay, targetVit)
	targetVit = targetVit or 10
	local resist = 1 - targetVit / (300 + targetVit)
	return math.round(rawDelay * resist)
end

--------------------------------------------------
-- SHARED DERIVED STAT FORMULAS
--
-- Primitive functions used by ComputeDerivedStats and by services
-- that need to recalculate with dynamic inputs (e.g. CombatResolver
-- calculating attack power with a different weapon mid-action).
-- Each function returns the RAW (unrounded) value.
--------------------------------------------------

function GameConstants.CalcAttackPower(weaponDmg, str)
	return weaponDmg * (1 + str / 200)
end

function GameConstants.CalcDefensePower(def, vit)
	if def <= 0 then return 0 end
	return def * (1 + vit / 300)
end

function GameConstants.CalcPrecision(dex)
	return dex / (dex + 200)
end

function GameConstants.CalcEvasiveness(agi)
	return agi / (agi + 200)
end

function GameConstants.CalcSkillPotency(int)
	return 1 + int / (200 + int)
end

function GameConstants.CalcHealEfficiency(vit)
	return 1 + vit / 300
end

--------------------------------------------------
-- DERIVED STATS COMPUTATION
--
-- Builds the full derivedStats table from a unit's effectiveStats + weapon data.
-- Called after every stat rebuild (equip, doctrine, buff/debuff).
-- Returns { derivedStats = {...}, statBreakdown = {...} }
--------------------------------------------------

function GameConstants.ComputeDerivedStats(unit)
	local s = unit.effectiveStats or {}
	local str = s.STR or 10
	local agi = s.AGI or 10
	local int = s.INT or 10
	local vit = s.VIT or 10
	local dex = s.DEX or 10
	local luk = s.LUK or 10

	local weaponDamage  = unit.weaponDamage or 10
	local weaponWt      = unit.weaponWt or 20
	local weaponRtDelay = unit.weaponRtDelay or 0
	local weaponDefense = unit.weaponDefense or 0

	local derived = {
		-- STR derived
		attackPower     = math.round(GameConstants.CalcAttackPower(weaponDamage, str) * 10) / 10,
		effectiveWt     = math.round(GameConstants.CalcEffectiveWt(weaponWt, str)),
		rtDelayBonus    = math.round(weaponRtDelay * (1 + math.min(str / (200 + str), 0.75)) * 10) / 10,
		force           = 1 + math.floor(str / 60),

		-- AGI derived
		movementRange   = 3 + math.floor(agi / 60),
		evasiveness     = math.round(GameConstants.CalcEvasiveness(agi) * 1000) / 10, -- store as % (e.g. 6.5)

		-- INT derived
		skillPotency    = math.round(GameConstants.CalcSkillPotency(int) * 1000) / 1000,
		maxMp           = 20 + int * 2,
		bonusSkillRange = math.floor(int / 75),
		mpRegen         = 2 + math.floor(int / 40),

		-- VIT derived
		maxHp           = 50 + vit * 4,
		healEfficiency  = math.round(GameConstants.CalcHealEfficiency(vit) * 1000) / 1000,
		defensePower    = math.round(GameConstants.CalcDefensePower(weaponDefense, vit) * 10) / 10,
		debuffResist    = math.round((1 - vit / (300 + vit)) * 1000) / 1000, -- no Calc* for this composite
		rtDelayResist   = math.round((1 - vit / (300 + vit)) * 1000) / 1000,
		stability       = math.floor(vit / 60),

		-- DEX derived
		precision       = math.round(GameConstants.CalcPrecision(dex) * 1000) / 10, -- store as % (e.g. 5.7)
		jump            = 1 + math.floor(dex / 60),
		channelReduction = math.round(dex / (300 + dex) * 1000) / 10, -- store as % reduction

		-- LUK derived
		discoveryRadius = 1 + math.floor(luk / 60),
		unitFortune     = math.round(luk / (luk + 200) * 1000) / 10, -- store as %
		startingRt      = GameConstants.CalcStartingRt(GameConstants.BASE_RT_STANDARD, luk),

		-- Composite combat stats
		basicAttackRt   = math.round(GameConstants.BASE_RT_STANDARD * GameConstants.BASIC_ATTACK_RT_FACTOR)
			+ math.round(GameConstants.CalcEffectiveWt(weaponWt, str)),
	}

	-- Store on unit
	unit.derivedStats = derived

	-- Build primary stat breakdown (base vs bonus)
	local base = unit.baseStats or s
	unit.primaryStats = {}
	for _, stat in ipairs({"STR", "AGI", "INT", "VIT", "DEX", "LUK"}) do
		local baseVal = base[stat] or 10
		local totalVal = s[stat] or 10
		unit.primaryStats[stat] = {
			base  = baseVal,
			bonus = totalVal - baseVal,
			total = totalVal,
		}
	end

	return derived
end

--------------------------------------------------
-- DISPLACEMENT FORMULAS (from DB: movement_targeting — Elevation & Displacement)
--
-- Wall Collision Damage = round(MaxHP × 0.04 × BlockedTiles × (1 + STR/200) × CollisionMult × BossHpMod × SourceMod)
-- Fall Damage = round(MaxHP × 0.04 × (FallHeight - 2)^1.5)  [only if FallHeight >= 3]
-- Push Distance = max(0, Force - Stability)
--------------------------------------------------

GameConstants.COLLISION_MULTIPLIERS = {
	Unit       = 0.8,
	WoodenWall = 1.0,
	StoneWall  = 1.2,
	Pillar     = 1.3,
	Spikes     = 1.6,
}

GameConstants.KNOCKBACK_SOURCE_MODIFIERS = {
	GlobalPush     = 1.0,
	SkillKnockback = 0.5,
}

GameConstants.FALL_DAMAGE_MIN_HEIGHT = 3 -- forced drops below this cause no fall damage

function GameConstants.CalcWallCollisionDamage(targetMaxHp, blockedTiles, attackerStr, collisionType, sourceModifier)
	local collisionMult = GameConstants.COLLISION_MULTIPLIERS[collisionType] or 1.0
	local bossMod = 1.0 -- Boss HP% modifier stub — no bosses in Slice 2
	return math.round(targetMaxHp * 0.04 * blockedTiles * (1 + attackerStr / 200) * collisionMult * bossMod * sourceModifier)
end

function GameConstants.CalcFallDamage(targetMaxHp, fallHeight)
	if fallHeight < GameConstants.FALL_DAMAGE_MIN_HEIGHT then return 0 end
	return math.round(targetMaxHp * 0.04 * (fallHeight - 2) ^ 1.5)
end

-- Stat metadata for client UI breakdown (formula strings + parent stat)
GameConstants.STAT_META = {
	attackPower     = { label = "Attack Power",     formula = "WeaponDmg × (1 + STR/200)", parent = "STR" },
	effectiveWt     = { label = "Effective WT",     formula = "Weapon WT × (1 - STR/(200+STR))", parent = "STR" },
	rtDelayBonus    = { label = "RT Delay Bonus",   formula = "Base RT Delay × (1 + min(STR/(200+STR), 0.75))", parent = "STR" },
	force           = { label = "Force",            formula = "1 + floor(STR / 60)", parent = "STR" },
	movementRange   = { label = "Movement Range",   formula = "3 + floor(AGI / 60)", parent = "AGI" },
	evasiveness     = { label = "Evasiveness",      formula = "AGI / (AGI + 200)", parent = "AGI", unit = "%" },
	skillPotency    = { label = "Skill Potency",    formula = "1 + INT / (200 + INT)", parent = "INT", unit = "×" },
	maxMp           = { label = "Max MP",           formula = "20 + INT × 2", parent = "INT" },
	bonusSkillRange = { label = "Bonus Skill Range", formula = "floor(INT / 75)", parent = "INT" },
	mpRegen         = { label = "MP Regen",         formula = "2 + floor(INT / 40) per 1000 CT", parent = "INT" },
	maxHp           = { label = "Max HP",           formula = "50 + VIT × 4", parent = "VIT" },
	healEfficiency  = { label = "Heal Efficiency",  formula = "1 + VIT / 300", parent = "VIT", unit = "×" },
	defensePower    = { label = "Defense Power",    formula = "Defense × (1 + VIT / 300)", parent = "VIT" },
	debuffResist    = { label = "Debuff Resist",    formula = "1 - VIT / (300 + VIT)", parent = "VIT", unit = "×" },
	rtDelayResist   = { label = "RT Delay Resist",  formula = "1 - VIT / (300 + VIT)", parent = "VIT", unit = "×" },
	stability       = { label = "Stability",        formula = "floor(VIT / 60)", parent = "VIT" },
	precision       = { label = "Precision",        formula = "DEX / (DEX + 200)", parent = "DEX", unit = "%" },
	jump            = { label = "Jump",             formula = "1 + floor(DEX / 60)", parent = "DEX" },
	channelReduction = { label = "Channel Speed",   formula = "DEX / (300 + DEX) reduction", parent = "DEX", unit = "%" },
	discoveryRadius = { label = "Discovery Radius", formula = "1 + floor(LUK / 60)", parent = "LUK" },
	unitFortune     = { label = "Unit Fortune",     formula = "LUK / (LUK + 200)", parent = "LUK", unit = "%" },
	startingRt      = { label = "Starting RT",      formula = "round(400 × (1 - 0.30 × LUK/(100+LUK)))", parent = "LUK" },
	basicAttackRt   = { label = "Basic Attack RT",  formula = "round(Base RT × 0.10) + Effective WT", parent = "STR" },
}

return GameConstants
