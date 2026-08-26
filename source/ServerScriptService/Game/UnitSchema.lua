-- UnitSchema.lua
-- CTRBLXAI | Slice 4A — Equipment Foundation
--
-- HP formula: HP = 50 + VIT × 4
-- MP formula: MP = 20 + INT × 2
--
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
	assert(type(definition.stats) == "table", "UnitSchema.Create: stats must be a table.")

	local vit = definition.stats.VIT or 10
	local int = definition.stats.INT or 10
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

		-- Core stats (permanent base — race growth + allocation)
		baseStats     = {
			STR = definition.stats.STR or 10,
			AGI = definition.stats.AGI or 10,
			INT = definition.stats.INT or 10,
			VIT = definition.stats.VIT or 10,
			DEX = definition.stats.DEX or 10,
			LUK = definition.stats.LUK or 10,
		},
		-- Effective stats (rebuilt by EquipmentService after doctrine+equipment)
		effectiveStats = {
			STR = definition.stats.STR or 10,
			AGI = definition.stats.AGI or 10,
			INT = definition.stats.INT or 10,
			VIT = definition.stats.VIT or 10,
			DEX = definition.stats.DEX or 10,
			LUK = definition.stats.LUK or 10,
		},

		-- Hit points
		maxHp         = maxHp,
		currentHp     = maxHp,

		-- Magic points
		maxMp         = maxMp,
		currentMp     = maxMp,

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
			or GameConstants.CalcStartingRt(GameConstants.BASE_RT_STANDARD, definition.stats.LUK or 10),

		-- Turn resources
		currentAp     = 0,

		-- Skills (units can have multiple skills)
		skillIds      = definition.skillIds or {},
		-- Legacy single skill support
		skillId       = definition.skillId or nil,

		-- Status effects
		statusInstances = {},

		-- Level (for tie-breaking and item level assignment)
		level         = definition.level or 1,

		-- Alive flag
		isAlive       = true,
	}

	-- Migrate single skillId into skillIds array if needed
	if unit.skillId and #unit.skillIds == 0 then
		table.insert(unit.skillIds, unit.skillId)
	end

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
