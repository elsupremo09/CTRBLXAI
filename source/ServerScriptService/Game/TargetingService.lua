
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
local ArmorPassiveService = require(script.Parent.ArmorPassiveService)
local StatusService = require(script.Parent.StatusService)


local RaceData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("RaceData")
)

-- Effective Elevation: tile elevation + 5 if unit has Flight status.
-- DB: "Flight treats unit as Tile Elevation + 5"
local function getEffectiveElevation(unit)
	local tileElev = GameConstants.GetElevation(unit.tileX, unit.tileY)
	if StatusService.HasStatus(unit, "Flight") then
		return tileElev + 5
	end
	return tileElev
end

-- Melee elevation restriction: melee attacks (range 1-2) limited to ±2 elevation.
-- Giant race tag overrides to ±5.
-- DB: "Melee attacks can only target units within +/-2 elevation levels of the attacker.
--      Giant race tag overrides this to +/-5."
local function isMeleeElevationLegal(actor, target, attackRange)
	if not attackRange or attackRange > 2 then return true end -- ranged, no limit
	local atkElev = getEffectiveElevation(actor)
	local defElev = GameConstants.GetElevation(target.tileX, target.tileY)
	local elevDiff = math.abs(atkElev - defElev)
	-- Giant: ±5
	local maxDiff = 2
	local raceEntry = RaceData[actor.raceId]
	if raceEntry and raceEntry.tags then
		for _, tag in ipairs(raceEntry.tags) do
			if tag == "Giant" then maxDiff = 5; break end
		end
	end
	return elevDiff <= maxDiff
end

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
	local armorOffset = ArmorPassiveService.GetMovementRangeBonus(unit)
	return math.max(1, base + raceOffset + armorOffset)
end

local function getJump(unit)
	if unit.derivedStats and unit.derivedStats.jump then
		return unit.derivedStats.jump
	end
	local dex = unit.effectiveStats and unit.effectiveStats.DEX or 10
	local raceJump = RacePassiveService.GetJumpModifier(unit)
	local armorJump = ArmorPassiveService.GetJumpBonus(unit)
	return 1 + math.floor(dex / 60) + raceJump + armorJump
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
	local parent     = {}
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
			elseif GameConstants.IsImpassableTerrain(nx, ny) then
				-- skip (Quicksand etc.)
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
								parent[key] = tileKey(current.x, current.y)

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

	-- Reconstruct path for each candidate by tracing parent chain
	for _, cand in ipairs(candidates) do
		local path = {}
		local ck = tileKey(cand.tileX, cand.tileY)
		local pk = parent[ck]
		while pk and pk ~= startKey do
			local px, py = pk:match("^(%d+),(%d+)$")
			px, py = tonumber(px), tonumber(py)
			local terrain = GameConstants.GetTerrainId(px, py)
			table.insert(path, 1, { tileX = px, tileY = py, terrain = terrain or "Clear" })
			pk = parent[pk]
		end
		-- Add destination terrain
		cand.terrain = GameConstants.GetTerrainId(cand.tileX, cand.tileY) or "Clear"
		cand.path = path
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
-- projectileType: nil/"Direct"/"Channeled" = units block LoS.
--                 "Arc" = units do NOT block (arc clears over them),
--                         but terrain BlocksLoS still applies.
--------------------------------------------------

function TargetingService.HasLineOfSight(x1, y1, x2, y2, allUnits, attackerElevation, projectileType)
	-- Adjacent tiles always have LoS
	if chebyshevDistance(x1, y1, x2, y2) <= 1 then
		return true
	end

	-- Giant race tag: ranged attacks targeting a Giant ignore LoS and blockers.
	-- DB: "Ranged attacks targeting the Giant ignore LoS and blockers."
	if allUnits then
		for _, u in ipairs(allUnits) do
			if u.tileX == x2 and u.tileY == y2 and u.isAlive and u.raceId then
				local raceEntry = RaceData[u.raceId]
				if raceEntry and raceEntry.tags then
					for _, tag in ipairs(raceEntry.tags) do
						if tag == "Giant" then return true end
					end
				end
			end
		end
	end

	-- Build a lookup of tiles occupied by standing units (block LoS).
	-- Arc projectiles use arc clearance instead of direct LoS:
	--   Arc Peak Elevation = Attacker Elevation + Arc Height (default 3)
	--   Clear if Arc Peak >= Blocker Elevation + 2
	local isArc = (projectileType == "Arc")
	local unitOccupied = {}
	if allUnits then
		for _, u in ipairs(allUnits) do
			if u.isAlive then
				local key = u.tileX .. "," .. u.tileY
				local uElev = GameConstants.GetElevation(u.tileX, u.tileY)
				unitOccupied[key] = uElev
			end
		end
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

		-- Check if a standing unit occupies this intermediate tile
		if allUnits then
			local key = cx .. "," .. cy
			local blockerElev = unitOccupied[key]
			if blockerElev then
				local atkElev = attackerElevation or GameConstants.GetElevation(x1, y1)

				if isArc then
					-- Arc clearance: Arc Peak Elevation >= Blocker Elevation + 2
					-- Arc Peak = Attacker Elevation + Arc Height (default 3)
					local arcPeak = atkElev + 3
					if arcPeak < blockerElev + 2 then
						return false
					end
				else
					-- Direct/Channeled/None: bypass if attacker >= 3 above blocker
					if atkElev < blockerElev + 3 then
						return false
					end
				end
			end
		end
	end
end

--------------------------------------------------
-- ATTACK CANDIDATES (Chebyshev range, enemy only)
--------------------------------------------------

function TargetingService.GetAttackCandidates(actor, allUnits, range)
	range = range or 1
	range = range + RacePassiveService.GetRangeModifier(actor)
	-- Support minimum range (ranged weapons cannot hit adjacent targets)
	local minRange = actor.weaponMinRange or 1

	local candidates = {}

	for _, unit in ipairs(allUnits) do
		if unit.isAlive and unit.side ~= actor.side then
			local dist = chebyshevDistance(actor.tileX, actor.tileY, unit.tileX, unit.tileY)
			if dist <= range
				and dist >= minRange
				and TargetingService.HasLineOfSight(actor.tileX, actor.tileY, unit.tileX, unit.tileY,
					allUnits, getEffectiveElevation(actor), actor.weaponProjectileType)
				and isMeleeElevationLegal(actor, unit, range)
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
	-- range = -1 means inherit from weapon
	local baseRange = (skillDef.range == -1) and (actor.weaponMaxRange or 1) or (skillDef.range or 1)
	-- Missing 4 fix: Bonus Skill Range from INT
	-- Rule: Bonus Skill Range = floor(INT / 75) + Flat bonuses
	local bonusRange = actor.derivedStats and actor.derivedStats.bonusSkillRange
		or math.floor((actor.effectiveStats and actor.effectiveStats.INT or 10) / 75)
	local range = baseRange + bonusRange
	if range < 1 then range = 1 end  -- Safety: negative bonusRange must not reduce below 1
	print(string.format("[SkillCand] %s using %s | skillRange=%s baseRange=%d bonusRange=%d range=%d | weaponMaxRange=%s INT=%s derivedBSR=%s",
		actor.name, skillDef.name or skillDef.id, tostring(skillDef.range),
		baseRange, bonusRange, range, tostring(actor.weaponMaxRange),
		tostring(actor.effectiveStats and actor.effectiveStats.INT),
		tostring(actor.derivedStats and actor.derivedStats.bonusSkillRange)))
	local targetRules = skillDef.targetRules or "Enemy Unit"
	local candidates = {}

	for _, unit in ipairs(allUnits) do
		if not unit.isAlive then
			-- skip dead units
		elseif chebyshevDistance(actor.tileX, actor.tileY, unit.tileX, unit.tileY) > range then
			-- skip out of range
			print(string.format("[SkillCand] %s REJECTED %s: out of range (dist=%d > range=%d)",
				actor.name, unit.name, chebyshevDistance(actor.tileX, actor.tileY, unit.tileX, unit.tileY), range))
		else
			-- Check LoS (healing/ally skills skip LoS for now)
			-- Projectile type: skill override or weapon default
			local projType = skillDef.projectileType
			if not projType or projType == "Inherit" then
				projType = actor.weaponProjectileType
			end
			local hasLos = targetRules == "Ally Unit, Self"
				or TargetingService.HasLineOfSight(actor.tileX, actor.tileY, unit.tileX, unit.tileY,
					allUnits, getEffectiveElevation(actor), projType)
			if not hasLos then
				-- blocked by obstacle
				print(string.format("[SkillCand] %s REJECTED %s: no LoS (proj=%s)", actor.name, unit.name, tostring(projType)))
			elseif not isMeleeElevationLegal(actor, unit, baseRange) then
				-- melee elevation too different
				print(string.format("[SkillCand] %s REJECTED %s: elevation (baseRange=%d)", actor.name, unit.name, baseRange))
			elseif targetRules == "Enemy Unit" then
				if unit.side ~= actor.side then
					table.insert(candidates, unit)
				else
					print(string.format("[SkillCand] %s REJECTED %s: same side", actor.name, unit.name))
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
	-- Cleave = primary target + up to 2 flanking units perpendicular to attack direction.
	-- Max 3 hits. Secondary tiles are adjacent to BOTH attacker AND target, on the sides.
	-- Elevation filter: secondary must be ±2 elevation from attacker.
	local targets = {}
	table.insert(targets, primaryTarget)

	-- Direction vector from attacker to target
	local dx = primaryTarget.tileX - actor.tileX
	local dy = primaryTarget.tileY - actor.tileY

	-- Perpendicular directions (the two flanking tiles)
	-- For cardinal: (1,0)→perps are (0,1),(0,-1). For diagonal: (1,1)→perps are (1,-1),(-1,1)
	local perp1X, perp1Y, perp2X, perp2Y
	if dx == 0 then     -- N or S attack
		perp1X, perp1Y = -1, dy
		perp2X, perp2Y = 1, dy
	elseif dy == 0 then -- E or W attack
		perp1X, perp1Y = dx, -1
		perp2X, perp2Y = dx, 1
	else                -- diagonal attack
		perp1X, perp1Y = dx, 0
		perp2X, perp2Y = 0, dy
	end

	local atkElev = getEffectiveElevation(actor)
	local flankTiles = {
		{ x = actor.tileX + perp1X, y = actor.tileY + perp1Y },
		{ x = actor.tileX + perp2X, y = actor.tileY + perp2Y },
	}

	for _, tile in ipairs(flankTiles) do
		local tileElev = GameConstants.GetElevation(tile.x, tile.y)
		if math.abs(tileElev - atkElev) <= 2 then
			for _, unit in ipairs(allUnits) do
				if unit.isAlive and unit.side ~= actor.side
					and unit.id ~= primaryTarget.id
					and unit.tileX == tile.x and unit.tileY == tile.y then
					table.insert(targets, unit)
				end
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
	-- range = -1 means inherit from weapon
	local range = (skillDef.range == -1) and (actor.weaponMaxRange or 1) or (skillDef.range or 1)
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
		local attackRange = (actor.weaponMaxRange or 1) + RacePassiveService.GetRangeModifier(actor)
		local candidates = TargetingService.GetAttackCandidates(actor, allUnits, attackRange)
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

--------------------------------------------------
-- AOE PATTERN TILE GENERATORS  (Slice 3)
--
-- Each function returns an array of {tileX, tileY} positions
-- that the pattern covers.  CommandService collects units on
-- those tiles, filters by targetRules, and resolves each hit.
--
-- DB rules:
--   - AOE elevation limit: ±2 from center/anchor (default)
--   - Center Spread AOE does not pass through BlocksAOE
--   - Selected Area AOE affects valid tiles directly
--   - Caster-origin patterns use caster's current tile
--
-- Elevation + BlocksAOE filtering is done by the caller,
-- not inside these generators (keeps them pure geometry).
--------------------------------------------------

-- Circle: all tiles within Chebyshev distance <= radius of center
function TargetingService.GetCircleTiles(centerX, centerY, radius, mapWidth, mapHeight)
	local tiles = {}
	for dy = -radius, radius do
		for dx = -radius, radius do
			if math.max(math.abs(dx), math.abs(dy)) <= radius then
				local tx, ty = centerX + dx, centerY + dy
				if isInsideMap(tx, ty, mapWidth, mapHeight) then
					table.insert(tiles, { tileX = tx, tileY = ty })
				end
			end
		end
	end
	return tiles
end

-- Ring: only the outer edge of a circle (distance == radius)
function TargetingService.GetRingTiles(centerX, centerY, radius, mapWidth, mapHeight)
	local tiles = {}
	for dy = -radius, radius do
		for dx = -radius, radius do
			if math.max(math.abs(dx), math.abs(dy)) == radius then
				local tx, ty = centerX + dx, centerY + dy
				if isInsideMap(tx, ty, mapWidth, mapHeight) then
					table.insert(tiles, { tileX = tx, tileY = ty })
				end
			end
		end
	end
	return tiles
end

-- Cross: cardinal lines of length N from center (+ center itself)
function TargetingService.GetCrossTiles(centerX, centerY, radius, mapWidth, mapHeight)
	local tiles = { { tileX = centerX, tileY = centerY } }
	local dirs = { {0,-1}, {0,1}, {-1,0}, {1,0} }
	for _, d in ipairs(dirs) do
		for i = 1, radius do
			local tx, ty = centerX + d[1]*i, centerY + d[2]*i
			if isInsideMap(tx, ty, mapWidth, mapHeight) then
				table.insert(tiles, { tileX = tx, tileY = ty })
			end
		end
	end
	return tiles
end

-- Line: N tiles in a direction from origin (exclusive of origin)
-- direction = {dx, dy} normalized to -1/0/1
function TargetingService.GetLineTiles(originX, originY, dx, dy, length, mapWidth, mapHeight)
	local tiles = {}
	for i = 1, length do
		local tx, ty = originX + dx*i, originY + dy*i
		if isInsideMap(tx, ty, mapWidth, mapHeight) then
			table.insert(tiles, { tileX = tx, tileY = ty })
		end
	end
	return tiles
end

-- Cone: expanding triangle in a direction, depth N
-- At distance d from origin, width = 2d-1 tiles perpendicular to direction
-- direction = {dx, dy} (cardinal or diagonal)
function TargetingService.GetConeTiles(originX, originY, dx, dy, depth, mapWidth, mapHeight)
	local tiles = {}
	-- Determine perpendicular direction
	local perpDx, perpDy
	if dx == 0 then
		perpDx, perpDy = 1, 0
	elseif dy == 0 then
		perpDx, perpDy = 0, 1
	else
		-- Diagonal: perpendicular is the two cardinals
		perpDx, perpDy = -dy, dx
	end

	for d = 1, depth do
		-- Center tile at distance d
		local cx, cy = originX + dx*d, originY + dy*d
		-- Width expands: at d=1 width=1, d=2 width=3, d=3 width=5
		local spread = d - 1
		for s = -spread, spread do
			local tx = cx + perpDx * s
			local ty = cy + perpDy * s
			if isInsideMap(tx, ty, mapWidth, mapHeight) then
				table.insert(tiles, { tileX = tx, tileY = ty })
			end
		end
	end
	return tiles
end

-- Adjacent Area: all 8 tiles around a center (not including center)
function TargetingService.GetAdjacentTiles(centerX, centerY, mapWidth, mapHeight)
	local tiles = {}
	for dy = -1, 1 do
		for dx = -1, 1 do
			if not (dx == 0 and dy == 0) then
				local tx, ty = centerX + dx, centerY + dy
				if isInsideMap(tx, ty, mapWidth, mapHeight) then
					table.insert(tiles, { tileX = tx, tileY = ty })
				end
			end
		end
	end
	return tiles
end

--------------------------------------------------
-- GetAOETargets: unified AOE resolution
--
-- Given an aoePattern string, origin, target/direction,
-- returns all affected {tileX, tileY} positions.
-- CommandService calls this then filters for units.
--------------------------------------------------

function TargetingService.GetAOETargetTiles(aoePattern, actor, targetTileX, targetTileY, mapWidth, mapHeight)
	-- Parse pattern type and parameter
	local patternType, param = aoePattern:match("^(%a+)(%d*)$")
	param = tonumber(param) or 1

	if patternType == "Circle" then
		return TargetingService.GetCircleTiles(targetTileX, targetTileY, param, mapWidth, mapHeight)

	elseif patternType == "Ring" then
		return TargetingService.GetRingTiles(targetTileX, targetTileY, param, mapWidth, mapHeight)

	elseif patternType == "Cross" then
		return TargetingService.GetCrossTiles(targetTileX, targetTileY, param, mapWidth, mapHeight)

	elseif patternType == "Line" then
		-- Direction from actor toward target
		local ddx = targetTileX - actor.tileX
		local ddy = targetTileY - actor.tileY
		local dx = ddx ~= 0 and (ddx > 0 and 1 or -1) or 0
		local dy = ddy ~= 0 and (ddy > 0 and 1 or -1) or 0
		return TargetingService.GetLineTiles(actor.tileX, actor.tileY, dx, dy, param, mapWidth, mapHeight)

	elseif patternType == "Cone" then
		local ddx = targetTileX - actor.tileX
		local ddy = targetTileY - actor.tileY
		local dx = ddx ~= 0 and (ddx > 0 and 1 or -1) or 0
		local dy = ddy ~= 0 and (ddy > 0 and 1 or -1) or 0
		return TargetingService.GetConeTiles(actor.tileX, actor.tileY, dx, dy, param, mapWidth, mapHeight)

	elseif patternType == "Adjacent" then
		return TargetingService.GetAdjacentTiles(targetTileX, targetTileY, mapWidth, mapHeight)

	elseif patternType == "Spread" then
		-- 3x3 Center Spread = Circle radius 1
		return TargetingService.GetCircleTiles(targetTileX, targetTileY, 1, mapWidth, mapHeight)

	elseif patternType == "Impact" then
		-- Impact 1 = Cross radius 1 (3×3 cross)
		return TargetingService.GetCrossTiles(targetTileX, targetTileY, 1, mapWidth, mapHeight)

	elseif patternType == "Cleave" then
		-- Cleave is handled separately via GetCleaveTargets (unit-based, not tile-based)
		return {}

	else
		print(string.format("[TargetingService] Unknown AOE pattern: %s", aoePattern))
		return {}
	end
end

--------------------------------------------------
-- AOE SPREAD BLOCKING
-- Center Spread AOE does not pass through BlocksAOE objects.
-- Uses Bresenham walk from center to tile; if any intermediate
-- tile has a BlocksAOE blocker, the target tile is blocked.
-- DB: "Walls, closed doors, sealed barriers, and solid map
-- objects tagged BlocksAOE block spread."
--------------------------------------------------

function TargetingService.IsAOEBlocked(centerX, centerY, targetX, targetY)
	-- Walk from center toward target, checking intermediate tiles
	local dx = targetX - centerX
	local dy = targetY - centerY
	local steps = math.max(math.abs(dx), math.abs(dy))
	if steps <= 1 then return false end  -- adjacent tiles never blocked

	for i = 1, steps - 1 do
		local t = i / steps
		local ix = centerX + math.floor(dx * t + 0.5)
		local iy = centerY + math.floor(dy * t + 0.5)
		if GameConstants.HasBlockerTag(ix, iy, "BlocksAOE") then
			return true
		end
	end

	-- Also blocked if the target tile itself is a BlocksAOE object
	if GameConstants.HasBlockerTag(targetX, targetY, "BlocksAOE") then
		return true
	end
	return false
end

--------------------------------------------------
-- Chain targeting: jumps from target to nearest
-- valid enemy within jumpRange, up to maxTargets.
-- Returns array of units in chain order.
--
-- DB: Chain skills select first target at commitment.
-- Jump distance default = 2 tiles (Chebyshev).
--------------------------------------------------

function TargetingService.GetChainTargets(firstTarget, allUnits, attackerSide, maxTargets, jumpRange)
	jumpRange = jumpRange or 2
	local chain = { firstTarget }
	local seen = { [firstTarget.id] = true }
	local current = firstTarget

	for _ = 2, maxTargets do
		local bestUnit = nil
		local bestDist = math.huge

		for _, u in ipairs(allUnits) do
			if u.isAlive and u.side ~= attackerSide and not seen[u.id] then
				local dist = chebyshevDistance(current.tileX, current.tileY, u.tileX, u.tileY)
				if dist <= jumpRange and dist < bestDist then
					bestDist = dist
					bestUnit = u
				end
			end
		end

		if not bestUnit then break end
		table.insert(chain, bestUnit)
		seen[bestUnit.id] = true
		current = bestUnit
	end

	return chain
end

return TargetingService
