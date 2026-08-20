-- UnitSchema.lua
-- CTRBLXAI | Slice 1
--
-- HP formula (from DB: core_stats — VIT):
--   HP = 50 + VIT × 4
-- Callers do NOT pass maxHp — it is derived from VIT automatically.

--------------------------------------------------
-- HP FORMULA
--------------------------------------------------

local function calcMaxHp(vit)
	return 50 + vit * 4
end
-- Creates and validates a unit's runtime data.
-- A "unit" is any combatant on the battlefield (player or enemy).
--
-- Slice 1 scope: HP, stats, position, RT, AP, side, name.
-- Full fields (doctrine, augments, equipment, statuses) are stubs
-- that will be filled in later slices.

local UnitSchema = {}

--------------------------------------------------
-- DEFAULTS
--------------------------------------------------

-- How many AP a unit starts each turn with.
-- Full formula lives in the DB (core_stats). Using 3 for Slice 1.
local DEFAULT_AP = 3

-- Starting RT for all units in Slice 1.
-- Lower RT = acts sooner. Full CT/RT formula comes in Slice 2+.
local DEFAULT_RT = 100

--------------------------------------------------
-- CREATE
--------------------------------------------------

-- Creates a new unit table from a definition.
--
-- definition fields:
--   id          (string)  -- unique ID, e.g. "unit_hero_01"
--   name        (string)  -- display name, e.g. "Hero"
--   side        (string)  -- "Player" or "Enemy"
--   controller  (string)  -- "Player" or "AI"
--   tileX       (number)  -- starting column on the map
--   tileY       (number)  -- starting row on the map
--   stats       (table)   -- { STR, AGI, INT, VIT, DEX, LUK }
--   maxHp       (number)  -- maximum hit points
--   skillId     (string)  -- the one skill this unit knows (Slice 1)

function UnitSchema.Create(definition)
	assert(
		type(definition) == "table",
		"UnitSchema.Create: definition must be a table."
	)
	assert(
		type(definition.id) == "string"
			and #definition.id > 0,
		"UnitSchema.Create: id must be a non-empty string."
	)
	assert(
		definition.side == "Player"
			or definition.side == "Enemy",
		'UnitSchema.Create: side must be "Player" or "Enemy".'
	)
	assert(
		definition.controller == "Player"
			or definition.controller == "AI",
		'UnitSchema.Create: controller must be "Player" or "AI".'
	)
	assert(
		type(definition.tileX) == "number"
			and type(definition.tileY) == "number",
		"UnitSchema.Create: tileX and tileY must be numbers."
	)
	assert(
		type(definition.stats) == "table",
		"UnitSchema.Create: stats must be a table."
	)

	local unit = {
		-- Identity
		id            = definition.id,
		name          = definition.name or definition.id,

		-- Battle team
		side          = definition.side,
		controller    = definition.controller,

		-- Position on the map grid
		tileX         = definition.tileX,
		tileY         = definition.tileY,
		facing        = definition.facing or "South",

		-- Core stats (STR/AGI/INT/VIT/DEX/LUK)
		-- base_stats are what the unit was created with.
		-- effective_stats are recalculated when statuses/doctrine apply.
		-- In Slice 1 they are identical.
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
		-- Derived from VIT: HP = 50 + VIT × 4
		maxHp         = calcMaxHp(definition.stats.VIT or 10),
		currentHp     = calcMaxHp(definition.stats.VIT or 10),

		-- MP (stub — not used in Slice 1)
		maxMp         = definition.maxMp or 0,
		currentMp     = definition.maxMp or 0,

		-- Timeline
		remainingRt   = definition.startingRt or DEFAULT_RT,

		-- Turn resources
		currentAp     = 0, -- set to DEFAULT_AP at start of each turn

		-- Skills (Slice 1: one skill per unit)
		skillId       = definition.skillId or nil,

		-- Status effects (stub — filled in Slice 2+)
		statusInstances = {},

		-- Alive flag
		isAlive       = true,
	}

	return unit
end

--------------------------------------------------
-- HELPERS
--------------------------------------------------

-- Returns true if the unit can still act (alive and has AP left).
function UnitSchema.CanAct(unit)
	return unit.isAlive and unit.currentAp > 0
end

-- Marks a unit as defeated.
function UnitSchema.Kill(unit)
	unit.isAlive   = false
	unit.currentHp = 0
	unit.currentAp = 0
end

-- Applies damage to a unit. Returns the actual damage dealt.
-- Does NOT check triggers or statuses — that is CombatResolver's job.
function UnitSchema.ApplyDamage(unit, amount)
	assert(amount >= 0, "ApplyDamage: amount must be >= 0.")

	local actual = math.min(unit.currentHp, amount)
	unit.currentHp = unit.currentHp - actual

	if unit.currentHp <= 0 then
		UnitSchema.Kill(unit)
	end

	return actual
end

-- Restores AP at the start of a turn.
function UnitSchema.RefreshAp(unit)
	unit.currentAp = DEFAULT_AP
end

-- Returns a short readable summary of the unit (for print/debug).
function UnitSchema.Describe(unit)
	return string.format(
		"[%s | %s | HP:%d/%d | AP:%d | RT:%d | Tile:(%d,%d)]",
		unit.name,
		unit.side,
		unit.currentHp,
		unit.maxHp,
		unit.currentAp,
		unit.remainingRt,
		unit.tileX,
		unit.tileY
	)
end

return UnitSchema
