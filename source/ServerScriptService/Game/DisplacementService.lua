-- DisplacementService.lua
-- CTRBLXAI | Slice 2 — Displacement Resolution Engine
--
-- Resolves forced movement (push, knockback). This module handles
-- the PHYSICS of what happens when a unit is displaced — tile-by-tile
-- resolution, wall collisions, fall damage, occupied-destination fallback.
--
-- It does NOT handle:
--   - Command validation, AP/RT costs (Slice 3 — CommandService)
--   - Broadcasting visual events (caller does that with the result)
--   - Action menu or UI (Slice 7)
--
-- Callers:
--   - Push global action (Slice 3 integration)
--   - Weapon knockback passives (Hammer/Club)
--   - Any future skill with authored displacement
--
-- DB sources:
--   movement_targeting.Elevation & Displacement (all displacement rules)
--   project_rules.Push Action (push-specific rules)
--   core_stats.STR → Force, core_stats.VIT → Stability

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

local DisplacementService = {}

--------------------------------------------------
-- MAP DIMENSIONS (set by caller or default to 8×8)
--------------------------------------------------

local _mapWidth  = 8
local _mapHeight = 8

function DisplacementService.SetMapDimensions(width, height)
	_mapWidth  = width
	_mapHeight = height
end

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function isInsideMap(x, y)
	return x >= 1 and x <= _mapWidth and y >= 1 and y <= _mapHeight
end

-- Find the occupying unit at a tile (nil if empty).
local function getUnitAt(allUnits, tileX, tileY)
	for _, unit in ipairs(allUnits) do
		if unit.isAlive and unit.tileX == tileX and unit.tileY == tileY then
			return unit
		end
	end
	return nil
end

-- Get what type of collision object a blocker is.
-- For Slice 2, all blockers are Stone Wall. Future slices
-- add per-blocker object types from the map data.
local function getBlockerCollisionType(tileX, tileY)
	-- Future: read from tile object metadata.
	return "StoneWall"
end

-- Find the nearest valid unoccupied tile to (tileX, tileY).
-- Used when a unit is pushed into an occupied tile and needs
-- to land somewhere nearby.
-- Searches in a spiral outward. Returns {tileX, tileY} or nil.
local function findNearestEmptyTile(allUnits, originX, originY, excludeUnit)
	-- BFS from origin, looking for the first passable + unoccupied tile.
	local visited = {}
	local queue = {{ x = originX, y = originY }}
	visited[originX .. "," .. originY] = true

	local dirs = {
		{0,1}, {0,-1}, {1,0}, {-1,0},
		{1,1}, {1,-1}, {-1,1}, {-1,-1},
	}

	local head = 1
	while head <= #queue do
		local cur = queue[head]
		head = head + 1

		-- Check if this tile is a valid landing spot
		if isInsideMap(cur.x, cur.y)
			and not GameConstants.IsBlocked(cur.x, cur.y)
		then
			local occupant = getUnitAt(allUnits, cur.x, cur.y)
			if occupant == nil or occupant == excludeUnit then
				return { tileX = cur.x, tileY = cur.y }
			end
		end

		-- Expand neighbors
		for _, d in ipairs(dirs) do
			local nx, ny = cur.x + d[1], cur.y + d[2]
			local key = nx .. "," .. ny
			if isInsideMap(nx, ny) and not visited[key] then
				visited[key] = true
				table.insert(queue, { x = nx, y = ny })
			end
		end
	end

	return nil -- no valid tile found (shouldn't happen on a real map)
end

--------------------------------------------------
-- CORE: ResolvePush
--
-- Resolves a single forced-displacement event tile by tile.
--
-- Parameters:
--   pusher        — unit doing the pushing
--   target        — unit being pushed
--   force         — attacker's Force value (already computed, e.g. derivedStats.force)
--   direction     — { dx = ±1, dy = ±1 } unit vector away from pusher
--   sourceModifier — 1.0 for Global Action Push, 0.5 for Skill knockback
--   allUnits      — all units in the battle (for occupancy checks)
--
-- Returns a result table:
--   {
--     pushed         = true/false,     -- whether any displacement occurred
--     tilesDisplaced = N,              -- how many tiles the target actually moved
--     finalTileX     = X,              -- target's final grid X
--     finalTileY     = Y,              -- target's final grid Y
--     wallCollision  = { damage = N, colliderType = "StoneWall" } or nil,
--     fallDamage     = N or nil,       -- total fall damage taken (0 if none)
--     blockedBy      = "unit"/"blocker"/"edge"/"elevation"/nil,
--     totalFallHeight = N or nil,      -- cumulative elevation drop during push
--   }
--
-- IMPORTANT: This function does NOT write to unit state. It only
-- reads positions and stats, then returns the result. The caller
-- (CommandService / CombatResolver) applies the actual HP changes
-- and position updates, then broadcasts events.
--------------------------------------------------

function DisplacementService.ResolvePush(pusher, target, force, direction, sourceModifier, allUnits)
	assert(type(pusher) == "table", "ResolvePush: pusher must be a unit table.")
	assert(type(target) == "table", "ResolvePush: target must be a unit table.")
	assert(type(direction) == "table" and direction.dx and direction.dy,
		"ResolvePush: direction must be {dx, dy}.")

	sourceModifier = sourceModifier or 1.0

	-- Step 1: Calculate push distance.
	-- Force = pusher's derived force (1 + floor(STR/60))
	-- Stability = target's derived stability (1 + floor(VIT/60))
	local targetStability = 1
	if target.derivedStats and target.derivedStats.stability then
		targetStability = target.derivedStats.stability
	elseif target.effectiveStats and target.effectiveStats.VIT then
		targetStability = 1 + math.floor(target.effectiveStats.VIT / 60)
	end

	local pushDistance = math.max(0, force - targetStability)

	-- If distance is 0, push fails — target is too stable.
	if pushDistance == 0 then
		print(string.format(
			"[DisplacementService] Push RESISTED | %s (Force %d) -> %s (Stability %d) | Distance: 0",
			pusher.name, force, target.name, targetStability
		))
		return {
			pushed         = false,
			tilesDisplaced = 0,
			finalTileX     = target.tileX,
			finalTileY     = target.tileY,
			wallCollision  = nil,
			fallDamage     = nil,
			blockedBy      = nil,
			totalFallHeight = 0,
		}
	end

	-- Step 2: Resolve tile-by-tile displacement.
	local dx = direction.dx
	local dy = direction.dy
	local currentX = target.tileX
	local currentY = target.tileY
	local currentElev = GameConstants.GetElevation(currentX, currentY)

	local tilesDisplaced = 0
	local blockedBy = nil
	local wallCollisionResult = nil
	local totalFallHeight = 0
	local startElev = currentElev

	for step = 1, pushDistance do
		local nextX = currentX + dx
		local nextY = currentY + dy

		-- Check 1: map bounds
		if not isInsideMap(nextX, nextY) then
			blockedBy = "edge"
			local blockedTiles = pushDistance - tilesDisplaced
			wallCollisionResult = {
				damage = GameConstants.CalcWallCollisionDamage(
					target.maxHp, blockedTiles, pusher.effectiveStats.STR,
					"StoneWall", sourceModifier
				),
				colliderType = "edge",
			}
			break
		end

		-- Check 2: blocker (impassable object)
		if GameConstants.IsBlocked(nextX, nextY) then
			blockedBy = "blocker"
			local blockerType = getBlockerCollisionType(nextX, nextY)
			local blockedTiles = pushDistance - tilesDisplaced
			wallCollisionResult = {
				damage = GameConstants.CalcWallCollisionDamage(
					target.maxHp, blockedTiles, pusher.effectiveStats.STR,
					blockerType, sourceModifier
				),
				colliderType = blockerType,
			}
			break
		end

		-- Check 3: elevation — forced upward is blocked
		local nextElev = GameConstants.GetElevation(nextX, nextY)
		if nextElev > currentElev then
			-- Cannot displace upward. Wall collision triggers.
			blockedBy = "elevation"
			local blockedTiles = pushDistance - tilesDisplaced
			wallCollisionResult = {
				damage = GameConstants.CalcWallCollisionDamage(
					target.maxHp, blockedTiles, pusher.effectiveStats.STR,
					"StoneWall", sourceModifier
				),
				colliderType = "elevation",
			}
			break
		end

		-- Check 4: occupancy — another unit on the tile
		local occupant = getUnitAt(allUnits, nextX, nextY)
		if occupant and occupant ~= target and occupant ~= pusher then
			-- Collision with another unit. Stop here.
			blockedBy = "unit"
			local blockedTiles = pushDistance - tilesDisplaced
			wallCollisionResult = {
				damage = GameConstants.CalcWallCollisionDamage(
					target.maxHp, blockedTiles, pusher.effectiveStats.STR,
					"Unit", sourceModifier
				),
				colliderType = "Unit",
				collidedUnitId = occupant.id,
			}
			break
		end

		-- Tile is clear — move target here.
		-- Track fall height (only forced downward counts).
		if nextElev < currentElev then
			totalFallHeight = totalFallHeight + (currentElev - nextElev)
		end

		currentX = nextX
		currentY = nextY
		currentElev = nextElev
		tilesDisplaced = tilesDisplaced + 1
	end

	-- Step 3: If pushed into an occupied tile (unit collision),
	-- find the nearest valid empty tile for the target to land on.
	if blockedBy == "unit" then
		-- Target stays at currentX, currentY (the last clear tile).
		-- If no tiles were displaced, try to find nearest empty around current pos.
		if tilesDisplaced == 0 then
			local fallback = findNearestEmptyTile(allUnits, currentX, currentY, target)
			if fallback then
				currentX = fallback.tileX
				currentY = fallback.tileY
			end
		end
	end

	-- Step 4: Calculate fall damage from cumulative forced downward drop.
	local fallDamage = 0
	if totalFallHeight >= GameConstants.FALL_DAMAGE_MIN_HEIGHT then
		fallDamage = GameConstants.CalcFallDamage(target.maxHp, totalFallHeight)
	end

	-- Build result.
	local result = {
		pushed          = tilesDisplaced > 0,
		tilesDisplaced  = tilesDisplaced,
		finalTileX      = currentX,
		finalTileY      = currentY,
		wallCollision   = wallCollisionResult,
		fallDamage      = fallDamage > 0 and fallDamage or nil,
		blockedBy       = blockedBy,
		totalFallHeight = totalFallHeight,
	}

	print(string.format(
		"[DisplacementService] Push | %s -> %s | Force:%d Stab:%d Dist:%d | Moved:%d to (%d,%d)%s%s%s",
		pusher.name, target.name,
		force, targetStability, pushDistance,
		tilesDisplaced, currentX, currentY,
		wallCollisionResult and string.format(" | WallDmg:%d (%s)", wallCollisionResult.damage, wallCollisionResult.colliderType) or "",
		fallDamage > 0 and string.format(" | FallDmg:%d (drop %d)", fallDamage, totalFallHeight) or "",
		blockedBy and (" | BlockedBy:" .. blockedBy) or ""
	))

	return result
end

--------------------------------------------------
-- HELPER: Calculate push direction from pusher to target.
-- Returns {dx, dy} as a unit direction (each component is -1, 0, or 1).
-- Direction is AWAY from pusher (target moves further from pusher).
--------------------------------------------------

function DisplacementService.GetPushDirection(pusher, target)
	local rawDx = target.tileX - pusher.tileX
	local rawDy = target.tileY - pusher.tileY

	-- Normalize to -1, 0, or 1 per axis.
	local dx = 0
	local dy = 0
	if rawDx > 0 then dx = 1 elseif rawDx < 0 then dx = -1 end
	if rawDy > 0 then dy = 1 elseif rawDy < 0 then dy = -1 end

	-- Edge case: pusher and target on the same tile (shouldn't happen).
	if dx == 0 and dy == 0 then
		dx = 1 -- default push east
	end

	return { dx = dx, dy = dy }
end

return DisplacementService
