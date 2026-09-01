-- UnitSchema.lua
-- CTRBLXAI | Slice 4A — Equipment Foundation
--
-- HP formula: HP = 50 + VIT × 4
-- MP formula: MP = 20 + INT × 2
--
-- Slice 4B changes:
--   - Create() accepts optional currentHp/currentMp for persistent resource loading
--   - mpRegenAccumulator field for fractional MP regen tracking

-- Slice 4A changes:
--   - Equipment slots added to unit state
--   - Doctrine reference added
--   - Weapon stats read from equipped weapon (not flat input)
--   - effectiveStats rebuilt by EquipmentService (not copied from input)
--   - Backwards-compatible: if no equipment, uses legacy flat values

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

local RaceData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("RaceData")
)

local UnitSchema = {}

--------------------------------------------------
-- FORMULAS
--------------------------------------------------

local function calcMaxHp(vit)
	return 50 + vit * 4
end

local function calcMaxMp(int)
	return 20 + int * 2
end

--------------------------------------------------
-- DEFAULTS
--------------------------------------------------

local DEFAULT_AP = 3
local DEFAULT_RT = 100

--------------------------------------------------
-- CREATE
--
-- definition fields:
--   REQUIRED: id, side, controller, tileX, tileY, stats
--   OPTIONAL: equipmentSlots, doctrineId, weaponDamage (legacy),
--             weaponWt (legacy), skillIds, startingRt, level
--
-- If equipmentSlots.MainHand is provided, weapon stats come from there.
-- Otherwise falls back to legacy flat weaponDamage/weaponWt.
--------------------------------------------------

function UnitSchema.Create(definition)
	assert(type(definition) == "table", "UnitSchema.Create: definition must be a table.")
	assert(type(definition.id) == "string" and #definition.id > 0,
		"UnitSchema.Create: id must be a non-empty string.")
	assert(definition.side == "Player" or definition.side == "Enemy",
		'UnitSchema.Create: side must be "Player" or "Enemy".')
	assert(definition.controller == "Player" or definition.controller == "AI",
		'UnitSchema.Create: controller must be "Player" or "AI".')
	assert(type(definition.tileX) == "number" and type(definition.tileY) == "number",
		"UnitSchema.Create: tileX and tileY must be numbers.")

	-- Resolve base stats: race-derived (4F) or legacy flat table
	local resolvedStats
	local raceId = definition.raceId or nil
	local level = definition.level or 1

	if raceId then
		-- Race-derived: base stats = startingStat + floor(growth × (level - 1))
		resolvedStats = RaceData.CalcBaseStats(raceId, level)
		assert(resolvedStats, "UnitSchema.Create: invalid raceId: " .. tostring(raceId))
	elseif definition.stats then
		-- Legacy: raw stat table (enemies, test units)
		resolvedStats = definition.stats
	else
		error("UnitSchema.Create: either raceId or stats must be provided.")
	end

	local vit = resolvedStats.VIT or 10
	local int = resolvedStats.INT or 10
	local maxHp = calcMaxHp(vit)
	local maxMp = definition.maxMp or calcMaxMp(int)

	local unit = {
		-- Identity
		id            = definition.id,
		name          = definition.name or definition.id,

		-- Battle team
		side          = definition.side,
		controller    = definition.controller,

		-- Position
		tileX         = definition.tileX,
		tileY         = definition.tileY,
		facing        = definition.facing or "South",

		-- Race identity (Slice 4F)
		raceId        = raceId,

		-- Perks and drawbacks (Slice 4F — fields only, content catalog pending)
		perkIds       = definition.perkIds or {},
		drawbackIds   = definition.drawbackIds or {},

		-- Core stats (permanent base — race growth + allocation)
		baseStats     = {
			STR = resolvedStats.STR or 10,
			AGI = resolvedStats.AGI or 10,
			INT = resolvedStats.INT or 10,
			VIT = resolvedStats.VIT or 10,
			DEX = resolvedStats.DEX or 10,
			LUK = resolvedStats.LUK or 10,
		},
		-- Effective stats (rebuilt by EquipmentService after doctrine+equipment)
		effectiveStats = {
			STR = resolvedStats.STR or 10,
			AGI = resolvedStats.AGI or 10,
			INT = resolvedStats.INT or 10,
			VIT = resolvedStats.VIT or 10,
			DEX = resolvedStats.DEX or 10,
			LUK = resolvedStats.LUK or 10,
		},

		-- Hit points
		maxHp         = maxHp,
		currentHp     = definition.currentHp or maxHp,

		-- Magic points
		maxMp         = maxMp,
		currentMp     = definition.currentMp or maxMp,

		-- MP Regen accumulator (Slice 4B: fractional CT-based regen)
		mpRegenAccumulator = 0,

		-- Weapon stats (populated by EquipmentService.RebuildUnitStats or legacy)
		weaponDamage  = definition.weaponDamage or 10,
		weaponWt      = definition.weaponWt or 40,
		weaponRtDelay = definition.weaponRtDelay or 0,
		weaponDefense = definition.weaponDefense or 0,
		weaponMinRange = definition.weaponMinRange or 1,
		weaponMaxRange = definition.weaponMaxRange or 1,
		weaponPattern = definition.weaponPattern or "Single",
		weaponProjectileType = definition.weaponProjectileType or nil,
		weaponHandClass = definition.weaponHandClass or "1H",

		-- Equipment (Slice 4A)
		equipmentSlots = definition.equipmentSlots or nil,
		doctrineId     = definition.doctrineId or nil,

		-- Timeline: Starting RT uses LUK formula if no explicit override
		-- Rule: Starting RT = round(Base RT × (1 - 0.30 × LUK / (100 + LUK)))
		remainingRt   = definition.startingRt
			or GameConstants.CalcStartingRt(GameConstants.BASE_RT_STANDARD, resolvedStats.LUK or 10),

		-- Turn resources
		currentAp     = 0,

		-- Skills (units can have multiple skills)
		skillIds      = definition.skillIds or {},
		-- Legacy single skill support
		skillId       = definition.skillId or nil,

		-- Status effects
		statusInstances = {},

		-- Level (persistent — drives race stat growth, tie-breaking, item level)
		level         = definition.level or 1,

		-- Alive flag
		isAlive       = true,
	}

	-- Migrate single skillId into skillIds array if needed
	if unit.skillId and #unit.skillIds == 0 then
		table.insert(unit.skillIds, unit.skillId)
	end

	-- Compute derived stats from effective stats + weapon data
	GameConstants.ComputeDerivedStats(unit)

	return unit
end

--------------------------------------------------
-- HELPERS
--------------------------------------------------

function UnitSchema.CanAct(unit)
	return unit.isAlive and unit.currentAp > 0
end

function UnitSchema.Kill(unit)
	unit.isAlive   = false
	unit.currentHp = 0
	unit.currentAp = 0
end

function UnitSchema.ApplyDamage(unit, amount)
	assert(amount >= 0, "ApplyDamage: amount must be >= 0.")
	local actual = math.min(unit.currentHp, amount)
	unit.currentHp = unit.currentHp - actual
	if unit.currentHp <= 0 then
		UnitSchema.Kill(unit)
	end
	return actual
end

function UnitSchema.ApplyHealing(unit, amount)
	assert(amount >= 0, "ApplyHealing: amount must be >= 0.")
	local actual = math.min(unit.maxHp - unit.currentHp, amount)
	unit.currentHp = unit.currentHp + actual
	return actual
end

function UnitSchema.SpendMp(unit, amount)
	assert(amount >= 0, "SpendMp: amount must be >= 0.")
	if unit.currentMp < amount then return false end
	unit.currentMp = unit.currentMp - amount
	return true
end

function UnitSchema.HasEnoughMp(unit, amount)
	return unit.currentMp >= amount
end

function UnitSchema.RefreshAp(unit)
	unit.currentAp = DEFAULT_AP
end

function UnitSchema.Describe(unit)
	return string.format(
		"[%s | %s | HP:%d/%d | MP:%d/%d | AP:%d | RT:%d | Tile:(%d,%d) | WpnDmg:%d WT:%d]",
		unit.name,
		unit.side,
		unit.currentHp,
		unit.maxHp,
		unit.currentMp or 0,
		unit.maxMp or 0,
		unit.currentAp,
		unit.remainingRt,
		unit.tileX,
		unit.tileY,
		unit.weaponDamage or 0,
		unit.weaponWt or 0
	)
end

return UnitSchema
