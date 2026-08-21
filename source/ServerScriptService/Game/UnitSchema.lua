-- UnitSchema.lua
-- CTRBLXAI | Slice 3
--
-- HP formula: HP = 50 + VIT × 4
-- MP formula: MP = 20 + INT × 2 (new in Slice 3)

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

		-- Core stats
		baseStats     = {
			STR = definition.stats.STR or 10,
			AGI = definition.stats.AGI or 10,
			INT = definition.stats.INT or 10,
			VIT = definition.stats.VIT or 10,
			DEX = definition.stats.DEX or 10,
			LUK = definition.stats.LUK or 10,
		},
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

		-- Magic points (Slice 3)
		maxMp         = maxMp,
		currentMp     = maxMp,

		-- Weapon stats
		weaponDamage  = definition.weaponDamage or 10,
		weaponWt      = definition.weaponWt or 40,

		-- Timeline
		remainingRt   = definition.startingRt or DEFAULT_RT,

		-- Turn resources
		currentAp     = 0,

		-- Skills (Slice 3: units can have multiple skills)
		skillIds      = definition.skillIds or {},
		-- Legacy single skill support
		skillId       = definition.skillId or nil,

		-- Status effects
		statusInstances = {},

		-- Level (for tie-breaking)
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
		"[%s | %s | HP:%d/%d | MP:%d/%d | AP:%d | RT:%d | Tile:(%d,%d)]",
		unit.name,
		unit.side,
		unit.currentHp,
		unit.maxHp,
		unit.currentMp or 0,
		unit.maxMp or 0,
		unit.currentAp,
		unit.remainingRt,
		unit.tileX,
		unit.tileY
	)
end

return UnitSchema
