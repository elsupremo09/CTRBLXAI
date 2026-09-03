-- TargetingService.lua
-- CTRBLXAI | Slice 3 (AOE Patterns + Ally Targeting)
--
-- Slice 3 additions:
--   - GetSkillCandidates: returns valid targets based on skill's targetRules
--   - GetCleaveTargets: given a primary target + caster, returns all units hit by Cleave
--   - Ally targeting: skills with "Ally Unit, Self" target rules can target allies or self

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

local RacePassiveService = require(script.Parent.RacePassiveService)

local TargetingService = {}

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

local BASE_MOVEMENT_RANGE = 3

local DIRECTIONS = {
	{ dx =  1, dy =  0, cost = 1.0 },
	{ dx = -1, dy =  0, cost = 1.0 },
	{ dx =  0, dy =  1, cost = 1.0 },
	{ dx =  0, dy = -1, cost = 1.0 },
	{ dx =  1, dy =  1, cost = 1.5 },
	{ dx = -1, dy =  1, cost = 1.5 },
	{ dx =  1, dy = -1, cost = 1.5 },
	{ dx = -1, dy = -1, cost = 1.5 },
}

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function getMovementRange(unit)
	local base = 0
	if unit.derivedStats and unit.derivedStats.movementRange then
		base = unit.derivedStats.movementRange
	else
		local agi = unit.effectiveStats and unit.effectiveStats.AGI or 10
		base = BASE_MOVEMENT_RANGE + math.floor(agi / 60)
	end
	local raceOffset = RacePassiveService.GetMovementRangeModifier(unit)
	return math.max(1, base + raceOffset)
end

local function getJump(unit)
	if unit.derivedStats and unit.derivedStats.jump then
		return unit.derivedStats.jump
	end
	local dex = unit.effectiveStats and unit.effectiveStats.DEX or 10
	return 1 + math.floor(dex / 60)
end

local function getDownwardJump(unit)
	return getJump(unit) + 2
end

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

local function chebyshevDistance(ax, ay, bx, by)
	return math.max(math.abs(ax - bx), math.abs(ay - by))
end

--------------------------------------------------
-- MOVE CANDIDATES (unchanged from Slice 2)
--------------------------------------------------

function TargetingService.GetMoveCandidates(actor, allUnits, mapWidth, mapHeight)
	local range      = getMovementRange(actor)
	local jump       = getJump(actor)
	local downJump   = getDownwardJump(actor)
	local occupancy  = buildOccupancyMap(allUnits)

	local visited    = {}
	local candidates = {}

	local queue      = { { x = actor.tileX, y = actor.tileY, cost = 0 } }
	local startKey   = tileKey(actor.tileX, actor.tileY)
	visited[startKey] = 0

	local head = 1
	while head <= #queue do
		local current = queue[head]
		head = head + 1

		local currentElev = GameConstants.GetElevation(current.x, current.y)

		for _, dir in ipairs(DIRECTIONS) do
			local nx = current.x + dir.dx
			local ny = current.y + dir.dy

			if isInsideMap(nx, ny, mapWidth, mapHeight) then
				local key = tileKey(nx, ny)

				if GameConstants.IsBlocked(nx, ny) then
					-- skip
				else
					local terrainCost = GameConstants.GetTerrainCost(nx, ny)
					local stepCost = dir.cost * terrainCost
					local newCost  = current.cost + stepCost

					if newCost <= range
						and (visited[key] == nil or visited[key] > newCost)
					then
						local nextElev = GameConstants.GetElevation(nx, ny)
						local elevDiff = nextElev - currentElev

						local elevLegal = true
						if elevDiff > 0 then
							elevLegal = elevDiff <= jump
						elseif elevDiff < 0 then
							elevLegal = math.abs(elevDiff) <= downJump
						end

						if elevLegal then
							local occupant = occupancy[key]
							local passable = (occupant == nil)
								or (occupant ~= actor and occupant.side == actor.side)

							if passable then
								visited[key] = newCost

								if occupant == nil then
									table.insert(candidates, {
										tileX = nx, tileY = ny, pathCost = newCost
									})
								end

								table.insert(queue, { x = nx, y = ny, cost = newCost })
							end
						end
					end
				end
			end
		end
	end

	return candidates
end

--------------------------------------------------
-- LINE OF SIGHT (Bresenham's line through grid)
--
-- Returns true if there is clear LoS from (x1,y1) to (x2,y2).
-- LoS is blocked if ANY tile along the line is a blocker.
-- The start and end tiles themselves do NOT block.
-- Range 1 (adjacent) always has LoS (melee can't be blocked).
--------------------------------------------------

function TargetingService.HasLineOfSight(x1, y1, x2, y2)
	-- Adjacent tiles always have LoS
	if chebyshevDistance(x1, y1, x2, y2) <= 1 then
		return true
	end

	-- Bresenham's line algorithm
	local dx = math.abs(x2 - x1)
	local dy = math.abs(y2 - y1)
	local sx = x1 < x2 and 1 or -1
	local sy = y1 < y2 and 1 or -1
	local err = dx - dy
	local cx, cy = x1, y1

	while true do
		local e2 = 2 * err
		if e2 > -dy then err = err - dy; cx = cx + sx end
		if e2 < dx then err = err + dx; cy = cy + sy end

		-- If we've reached the destination, LoS is clear
		if cx == x2 and cy == y2 then return true end

		-- Check if this intermediate tile is a blocker
		if GameConstants.IsBlocked(cx, cy) then
			return false
		end
	end
end

--------------------------------------------------
-- ATTACK CANDIDATES (Chebyshev range, enemy only)
--------------------------------------------------

function TargetingService.GetAttackCandidates(actor, allUnits, range)
	range = range or 1
	-- Support minimum range (ranged weapons cannot hit adjacent targets)
	local minRange = actor.weaponMinRange or 1

	local candidates = {}

	for _, unit in ipairs(allUnits) do
		if unit.isAlive and unit.side ~= actor.side then
			local dist = chebyshevDistance(actor.tileX, actor.tileY, unit.tileX, unit.tileY)
			if dist <= range
				and dist >= minRange
				and TargetingService.HasLineOfSight(actor.tileX, actor.tileY, unit.tileX, unit.tileY)
			then
				table.insert(candidates, unit)
			end
		end
	end

	return candidates
end

--------------------------------------------------
-- SKILL CANDIDATES (Slice 3)
-- Returns valid target units based on the skill's targetRules.
--   "Enemy Unit"       → enemies in range
--   "Ally Unit, Self"  → allies + self in range
--------------------------------------------------

function TargetingService.GetSkillCandidates(actor, allUnits, skillDef)
	local baseRange = skillDef.range or 1
	-- Missing 4 fix: Bonus Skill Range from INT
	-- Rule: Bonus Skill Range = floor(INT / 75) + Flat bonuses
	local bonusRange = actor.derivedStats and actor.derivedStats.bonusSkillRange
		or math.floor((actor.effectiveStats and actor.effectiveStats.INT or 10) / 75)
	local range = baseRange + bonusRange
	local targetRules = skillDef.targetRules or "Enemy Unit"
	local candidates = {}

	for _, unit in ipairs(allUnits) do
		if not unit.isAlive then
			-- skip dead units
		elseif chebyshevDistance(actor.tileX, actor.tileY, unit.tileX, unit.tileY) > range then
			-- skip out of range
		else
			-- Check LoS (healing/ally skills skip LoS for now)
			local hasLos = targetRules == "Ally Unit, Self"
				or TargetingService.HasLineOfSight(actor.tileX, actor.tileY, unit.tileX, unit.tileY)
			if not hasLos then
				-- blocked by obstacle
			elseif targetRules == "Enemy Unit" then
				if unit.side ~= actor.side then
					table.insert(candidates, unit)
				end
			elseif targetRules == "Ally Unit, Self" then
				if unit.side == actor.side then
					table.insert(candidates, unit)
				end
			end
		end
	end

	return candidates
end

--------------------------------------------------
-- CLEAVE TARGETS (Slice 3)
--
-- Cleave hits all enemies within range 1 of the caster that are
-- also within 1 tile of the primary target (forming a 3-tile arc).
-- The primary target is always included.
-- Returns a list of units (primary target first).
--------------------------------------------------

function TargetingService.GetCleaveTargets(actor, primaryTarget, allUnits)
	-- Cleave = all enemies within range 1 of the CASTER (not constrained to target).
	-- Primary target is always included. The caster swings at everything adjacent.
	local targets = {}
	local seen = { [primaryTarget.id] = true }
	table.insert(targets, primaryTarget)

	for _, unit in ipairs(allUnits) do
		if unit.isAlive
			and unit.side ~= actor.side
			and unit.id ~= primaryTarget.id
			and not seen[unit.id]
		then
			local distToCaster = chebyshevDistance(
				actor.tileX, actor.tileY, unit.tileX, unit.tileY
			)

			-- Hit everyone within range 1 of the caster
			if distToCaster <= 1 then
				table.insert(targets, unit)
				seen[unit.id] = true
			end
		end
	end

	return targets
end

--------------------------------------------------
-- GET VALID SKILL TILES (Slice 3 — for client highlighting)
--
-- Returns all tile positions within skill range (for highlighting).
--------------------------------------------------

function TargetingService.GetSkillRangeTiles(actor, skillDef, mapWidth, mapHeight)
	local range = skillDef.range or 1
	local tiles = {}

	for dy = -range, range do
		for dx = -range, range do
			if math.max(math.abs(dx), math.abs(dy)) <= range then
				local tx = actor.tileX + dx
				local ty = actor.tileY + dy
				if isInsideMap(tx, ty, mapWidth, mapHeight) then
					table.insert(tiles, { tileX = tx, tileY = ty })
				end
			end
		end
	end

	return tiles
end

--------------------------------------------------
-- VALIDATE SELECTION (updated for Slice 3)
--------------------------------------------------

function TargetingService.ValidateSelection(
	actor,
	actionType,
	selection,
	allUnits,
	mapWidth,
	mapHeight
)
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
			if c.tileX == selection.tileX and c.tileY == selection.tileY then
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
		if type(selection) ~= "table" or not selection.isAlive then
			return false, "Attack selection must be a living unit."
		end
		if selection.side == actor.side then
			return false, "Cannot attack an ally."
		end

		-- Use actor's equipped weapon range for validation
		local candidates = TargetingService.GetAttackCandidates(actor, allUnits, actor.weaponMaxRange or 1)
		for _, c in ipairs(candidates) do
			if c == selection then
				return true, nil
			end
		end

		return false, string.format(
			"Target %s is out of basic attack range.", selection.name
		)
	end

	if actionType == "Skill" then
		if type(selection) ~= "table" or type(selection.target) ~= "table" then
			return false, "Skill selection must be a table with a target field."
		end

		local target     = selection.target
		local skillRange = selection.skillRange or 1
		local targetRules = selection.targetRules or "Enemy Unit"

		if not target.isAlive then
			return false, "Target is not alive."
		end

		-- Validate target allegiance based on skill target rules
		if targetRules == "Enemy Unit" then
			if target.side == actor.side then
				return false, "Cannot target an ally with this offensive skill."
			end
		elseif targetRules == "Ally Unit, Self" then
			if target.side ~= actor.side then
				return false, "Cannot target an enemy with this support skill."
			end
		end

		-- Range check (Chebyshev)
		local dist = chebyshevDistance(actor.tileX, actor.tileY, target.tileX, target.tileY)
		if dist > skillRange then
			return false, string.format(
				"Target %s is out of skill range (%d). Distance: %d.",
				target.name, skillRange, dist
			)
		end

		return true, nil
	end

	return false, "Unknown actionType: " .. tostring(actionType)
end

return TargetingService
