-- TargetingService.lua
-- CTRBLXAI | Slice 1
--
-- Answers two questions:
--   1. EnumerateCandidates: which tiles/units can this unit reach
--      for Move or Attack right now?
--   2. ValidateSelection: is this specific tile/unit a legal choice?
--
-- Slice 1 scope (flat map, no elevation, no LoS, no AOE patterns):
--   - Move: flood-fill within Movement Range, terrain cost = 1 per tile.
--   - Attack (Basic Attack): adjacent tiles (range 1), enemy units only.
--   - Skill: single-target, range from skill definition, enemy units only.
--
-- Does NOT own: damage math, status effects, or combat resolution.

local TargetingService = {}

--------------------------------------------------
-- CONSTANTS
--   Movement Range formula (from DB: core_stats — AGI)
--   Movement Range = 3 + floor(AGI / 60) + Bonuses - Penalties
--   Slice 1: no bonuses/penalties, flat terrain cost = 1.
--------------------------------------------------

local BASE_MOVEMENT_RANGE = 3

-- All 8 directions.
-- cost = movement budget consumed per step.
-- Cardinal = 1.0 × terrain cost. Diagonal = 1.5 × terrain cost.
-- (DB: core_stats — Movement, Diagonal step = Terrain Cost × 1.5)
local DIRECTIONS = {
	{ dx =  1, dy =  0, cost = 1.0 },  -- E
	{ dx = -1, dy =  0, cost = 1.0 },  -- W
	{ dx =  0, dy =  1, cost = 1.0 },  -- S
	{ dx =  0, dy = -1, cost = 1.0 },  -- N
	{ dx =  1, dy =  1, cost = 1.5 },  -- SE
	{ dx = -1, dy =  1, cost = 1.5 },  -- SW
	{ dx =  1, dy = -1, cost = 1.5 },  -- NE
	{ dx = -1, dy = -1, cost = 1.5 },  -- NW
}

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function getMovementRange(unit)
	local agi = unit.effectiveStats and unit.effectiveStats.AGI or 10
	return BASE_MOVEMENT_RANGE + math.floor(agi / 60)
end

-- Builds a fast lookup: key "x,y" -> unit, for all alive units.
local function buildOccupancyMap(units)
	local map = {}
	for _, unit in ipairs(units) do
		if unit.isAlive then
			local key = unit.tileX .. "," .. unit.tileY
			map[key] = unit
		end
	end
	return map
end

local function tileKey(x, y)
	return x .. "," .. y
end

local function isInsideMap(x, y, mapWidth, mapHeight)
	return x >= 1 and x <= mapWidth
		and y >= 1 and y <= mapHeight
end

--------------------------------------------------
-- MOVE CANDIDATES
--   BFS flood-fill within Movement Range.
--   Returns a list of { tileX, tileY } tables.
--   Rules (Slice 1, flat terrain):
--     - Can pass through allies, cannot end on allies.
--     - Cannot pass through enemies, cannot end on enemies.
--     - Terrain cost = 1 per cardinal step.
--------------------------------------------------

function TargetingService.GetMoveCandidates(actor, allUnits, mapWidth, mapHeight)
	local range      = getMovementRange(actor)
	local occupancy  = buildOccupancyMap(allUnits)

	-- visited[key] = cheapest cost to reach this tile
	local visited    = {}
	local candidates = {}

	-- BFS queue: each entry is { x, y, costSoFar }
	local queue      = { { x = actor.tileX, y = actor.tileY, cost = 0 } }
	local startKey   = tileKey(actor.tileX, actor.tileY)
	visited[startKey] = 0

	local head = 1
	while head <= #queue do
		local current = queue[head]
		head = head + 1

		for _, dir in ipairs(DIRECTIONS) do
			local nx   = current.x + dir.dx
			local ny   = current.y + dir.dy
			local key  = tileKey(nx, ny)
			local newCost = current.cost + dir.cost  -- cardinal=1.0, diagonal=1.5

			if isInsideMap(nx, ny, mapWidth, mapHeight)
				and newCost <= range
				and (visited[key] == nil or visited[key] > newCost)
			then
				local occupant = occupancy[key]

				-- Can pass through allies, blocked by enemies.
				local passable = (occupant == nil)
					or (occupant ~= actor and occupant.side == actor.side)

				if passable then
					visited[key] = newCost

					-- Can only END on empty tiles.
					if occupant == nil then
					-- pathCost = actual movement budget consumed to reach this tile.
					table.insert(candidates, { tileX = nx, tileY = ny, pathCost = newCost })
					end

					table.insert(queue, { x = nx, y = ny, cost = newCost })
				end
			end
		end
	end

	return candidates
end

--------------------------------------------------
-- ATTACK CANDIDATES
--   Returns enemy units within weapon range.
--   Slice 1: Basic Attack range = 1 (adjacent only).
--   skillRange parameter lets a skill override the range.
--------------------------------------------------

function TargetingService.GetAttackCandidates(actor, allUnits, range)
	range = range or 1
	local candidates = {}

	for _, unit in ipairs(allUnits) do
		if unit.isAlive
			and unit.side ~= actor.side
		then
			local dx = math.abs(unit.tileX - actor.tileX)
			local dy = math.abs(unit.tileY - actor.tileY)

			-- Chebyshev distance for Slice 1 (max(dx,dy) <= range).
			-- The DB targeting rules distinguish cardinal vs diagonal;
			-- for a range-1 basic attack this is equivalent.
			if math.max(dx, dy) <= range then
				table.insert(candidates, unit)
			end
		end
	end

	return candidates
end

--------------------------------------------------
-- VALIDATE SELECTION
--   Returns true + nil, or false + reason string.
--
--   actionType: "Move" | "Attack" | "Skill" | "Wait"
--   selection:
--     Move   -> { tileX, tileY }
--     Attack -> unit table
--     Skill  -> { target = unit, skillRange = number }
--     Wait   -> nil (always valid)
--------------------------------------------------

function TargetingService.ValidateSelection(
	actor,
	actionType,
	selection,
	allUnits,
	mapWidth,
	mapHeight
)
	-- Wait is always valid.
	if actionType == "Wait" then
		return true, nil
	end

	if actionType == "Move" then
		if type(selection) ~= "table"
			or type(selection.tileX) ~= "number"
			or type(selection.tileY) ~= "number"
		then
			return false, "Move selection must be a table with tileX and tileY."
		end

		local candidates = TargetingService.GetMoveCandidates(
			actor, allUnits, mapWidth, mapHeight
		)

		for _, c in ipairs(candidates) do
			if c.tileX == selection.tileX
				and c.tileY == selection.tileY
			then
				return true, nil
			end
		end

		return false, string.format(
			"Tile (%d,%d) is not reachable from (%d,%d) with range %d.",
			selection.tileX, selection.tileY,
			actor.tileX, actor.tileY,
			getMovementRange(actor)
		)
	end

	if actionType == "Attack" then
		if type(selection) ~= "table"
			or not selection.isAlive
		then
			return false, "Attack selection must be a living unit."
		end
		if selection.side == actor.side then
			return false, "Cannot attack an ally."
		end

		local candidates = TargetingService.GetAttackCandidates(actor, allUnits, 1)
		for _, c in ipairs(candidates) do
			if c == selection then
				return true, nil
			end
		end

		return false, string.format(
			"Target %s is out of basic attack range.",
			selection.name
		)
	end

	if actionType == "Skill" then
		if type(selection) ~= "table"
			or type(selection.target) ~= "table"
		then
			return false, "Skill selection must be a table with a target field."
		end

		local target     = selection.target
		local skillRange = selection.skillRange or 1

		if not target.isAlive then
			return false, "Target is not alive."
		end
		if target.side == actor.side then
			return false, "Cannot target an ally with this skill."
		end

		local candidates = TargetingService.GetAttackCandidates(
			actor, allUnits, skillRange
		)
		for _, c in ipairs(candidates) do
			if c == target then
				return true, nil
			end
		end

		return false, string.format(
			"Target %s is out of skill range (%d).",
			target.name,
			skillRange
		)
	end

	return false, "Unknown actionType: " .. tostring(actionType)
end

return TargetingService
