-- ElevationPass.lua
-- CTRBLXAI | Feature Coherence System — Round 1
--
-- Assigns terrain-correlated elevation to each tile.
-- Uses terrain tags (from TerrainData) to determine elevation ranges,
-- then smooths gradients and enforces the LAN Jump=1 constraint.
--
-- Six phases:
--   1  Tag-based initial assignment
--   1b Neighbor-averaging for structural terrain (Metal, etc.)
--   1c Elevation noise within uniform regions
--   2  ADV marker bonus
--   3  Gradient smoothing (2 passes, non-protected tiles, Stone exempt from downward pull)
--   4  LAN constraint enforcement (3 passes, LAN-family tiles)
--   5  Slope reachability — lower isolated max-elevation plateaus
--
-- Location: ServerScriptService/Game/ElevationPass.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Content     = ReplicatedStorage:WaitForChild("Content")
local TerrainData = require(Content:WaitForChild("TerrainData"))

local ElevationPass = {}

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

local CARDINAL = {
	{ x =  0, y =  1 },
	{ x =  0, y = -1 },
	{ x =  1, y =  0 },
	{ x = -1, y =  0 },
}

-- Markers belonging to the LAN-connected family.
-- Adjacent tiles within this family must have elevation diff ≤ 1.
local LAN_FAMILY = {
	PD  = true,
	ED  = true,
	LAN = true,
	HZD = true,
	BLK = true,
	ADV = true,
}

local YIELD_INTERVAL = 100

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function isInBounds(x, y, w, h)
	return x >= 1 and x <= w and y >= 1 and y <= h
end

local function coordKey(x, y)
	return y * 100000 + x
end

--- Check whether a terrain type carries a specific tag.
local function hasTag(terrainId, tagName)
	local tDef = TerrainData.Types[terrainId]
	if not tDef or not tDef.tags then return false end
	for _, tag in ipairs(tDef.tags) do
		if tag == tagName then return true end
	end
	return false
end

--- Check whether a terrain type carries ANY of the listed tags.
local function hasAnyTag(terrainId, tagNames)
	local tDef = TerrainData.Types[terrainId]
	if not tDef or not tDef.tags then return false end
	for _, tag in ipairs(tDef.tags) do
		for _, target in ipairs(tagNames) do
			if tag == target then return true end
		end
	end
	return false
end

--------------------------------------------------
-- TAG → ELEVATION RANGE
-- Returns (minElev, maxElev, needsNeighborAvg).
-- Priority order reflects terrain physics:
--   frozen < liquid < loose/organic < natural
--   < stone < fragile < structural < magical
--------------------------------------------------

local function getTagElevationRange(terrainId, cfg)
	local bMin = cfg.min
	local bMax = cfg.max
	local bMid = math.floor((bMin + bMax) / 2)

	-- Priority 1: Frozen / Slippery — frozen surfaces sit low.
	if hasAnyTag(terrainId, { "Frozen", "Slippery" }) then
		return bMin, math.min(bMin + 1, bMax), false
	end

	-- Priority 2: Liquid / Water / Deep / Molten / Sticky — pool at floor.
	if hasAnyTag(terrainId, { "Liquid", "Water", "Deep", "Molten", "Sticky" }) then
		return bMin, bMin, false
	end

	-- Priority 3: Loose (Sand, Quicksand) — low ground.
	if hasTag(terrainId, "Loose") then
		return bMin, bMid, false
	end

	-- Priority 4: Organic (Grassland, Clover, Wooden Floor) — gentle terrain.
	if hasTag(terrainId, "Organic") then
		return bMin, bMid, false
	end

	-- Priority 5: Natural (Clear) — flexible, full range.
	if hasTag(terrainId, "Natural") then
		return bMin, bMax, false
	end

	-- Priority 6: Stone (Rocky) — elevated terrain.
	if hasTag(terrainId, "Stone") then
		return bMid, bMax, false
	end

	-- Priority 7: Fragile (Cracked Ground) — upper half.
	if hasTag(terrainId, "Fragile") then
		local lowerBound = bMid + 1
		if lowerBound > bMax then lowerBound = bMax end
		return lowerBound, bMax, false
	end

	-- Priority 8: Metal, or Flammable-without-Organic (structures).
	-- Match surrounding neighbor average (deferred to phase 1b).
	if hasTag(terrainId, "Metal") then
		return bMin, bMax, true
	end
	if hasTag(terrainId, "Flammable") and not hasTag(terrainId, "Organic") then
		return bMin, bMax, true
	end

	-- Priority 9: Corrupted / Arcane / Portal — full range.
	if hasAnyTag(terrainId, { "Corrupted", "Arcane", "Portal" }) then
		return bMin, bMax, false
	end

	-- Fallback: full biome range.
	return bMin, bMax, false
end

--------------------------------------------------
-- RUN
--------------------------------------------------

--- Assign terrain-correlated elevation to every tile.
--- @param mapState table — the shared pipeline state
--- @return mapState (modified in-place)
function ElevationPass.Run(mapState)
	local tiles = mapState.tiles
	local w     = mapState.width
	local h     = mapState.height
	local rng   = mapState.rng.elevationRng
	local cfg   = mapState.biomeElevation

	local ops = 0

	-- Collect tiles that need neighbor-averaging (phase 1b).
	local deferredTiles = {}

	---------------------------------------------------------
	-- PHASE 1: Tag-based initial elevation
	---------------------------------------------------------
	for y = 1, h do
		for x = 1, w do
			local tile = tiles[y][x]
			local eMin, eMax, needsAvg = getTagElevationRange(tile.terrain, cfg)

			if needsAvg then
				-- Placeholder; resolved in phase 1b after neighbors are assigned.
				tile.elevation = math.floor((cfg.min + cfg.max) / 2)
				table.insert(deferredTiles, { x = x, y = y })
			elseif eMin == eMax then
				tile.elevation = eMin
			else
				tile.elevation = rng:NextInteger(eMin, eMax)
			end

			ops = ops + 1
			if ops % YIELD_INTERVAL == 0 then task.wait() end
		end
	end

	---------------------------------------------------------
	-- PHASE 1b: Neighbor-averaging for structural terrain
	-- (Metal, non-Organic Flammable).
	-- Uses the average of cardinal neighbors' elevations.
	---------------------------------------------------------
	for _, pos in ipairs(deferredTiles) do
		local tile    = tiles[pos.y][pos.x]
		local sum     = 0
		local count   = 0

		for _, dir in ipairs(CARDINAL) do
			local nx, ny = pos.x + dir.x, pos.y + dir.y
			if isInBounds(nx, ny, w, h) then
				sum   = sum + tiles[ny][nx].elevation
				count = count + 1
			end
		end

		if count > 0 then
			tile.elevation = math.clamp(
				math.floor(sum / count + 0.5),
				cfg.min, cfg.max
			)
		end
	end

	---------------------------------------------------------
	-- PHASE 1c: Elevation noise within uniform regions
	-- Breaks up monotony of large same-terrain areas.
	--   Natural (Clear):  ±1 random noise
	--   Stone   (Rocky):  0 to +1 (bias upward)
	-- Skip Liquid, Frozen, Protected tiles entirely.
	---------------------------------------------------------
	for y = 1, h do
		for x = 1, w do
			local tile = tiles[y][x]
			if not tile.protected then
				local terrain = tile.terrain
				-- Skip liquid / frozen — they need consistent elevation.
				if not hasAnyTag(terrain, { "Liquid", "Frozen" }) then
					if hasTag(terrain, "Natural") then
						local noise = rng:NextInteger(-1, 1)
						tile.elevation = math.clamp(
							tile.elevation + noise, cfg.min, cfg.max
						)
					elseif hasTag(terrain, "Stone") then
						local noise = rng:NextInteger(0, 1)
						tile.elevation = math.clamp(
							tile.elevation + noise, cfg.min, cfg.max
						)
					end
				end
			end

			ops = ops + 1
			if ops % YIELD_INTERVAL == 0 then task.wait() end
		end
	end

	---------------------------------------------------------
	-- PHASE 2: ADV marker bonus
	-- ADV tiles gain +advBonus elevation, clamped to biome max.
	---------------------------------------------------------
	local advBonus = cfg.advBonus or 1

	for y = 1, h do
		for x = 1, w do
			local tile = tiles[y][x]
			if tile.marker == "ADV" then
				tile.elevation = math.min(tile.elevation + advBonus, cfg.max)
			end
		end
	end

	---------------------------------------------------------
	-- PHASE 3: Gradient smoothing (2 passes)
	-- For each non-protected tile, if any cardinal neighbor
	-- has elevation diff > 3, pull this tile 1 step toward
	-- that neighbor.
	-- Stone-tagged tiles are exempt from DOWNWARD pulls,
	-- preserving rocky ridges and cliff edges. Stone tiles
	-- can still be pulled upward toward higher neighbors.
	---------------------------------------------------------
	for _ = 1, 2 do
		for y = 1, h do
			for x = 1, w do
				local tile = tiles[y][x]
				if not tile.protected then
					local isStone = hasTag(tile.terrain, "Stone")
					for _, dir in ipairs(CARDINAL) do
						local nx, ny = x + dir.x, y + dir.y
						if isInBounds(nx, ny, w, h) then
							local diff = tile.elevation - tiles[ny][nx].elevation
							if diff > 3 then
								-- Tile is higher than neighbor by > 3.
								-- Skip downward pull for Stone tiles.
								if not isStone then
									tile.elevation = tile.elevation - 1
								end
							elseif diff < -3 then
								-- Tile is lower than neighbor by > 3.
								-- Upward pull is always allowed.
								tile.elevation = tile.elevation + 1
							end
						end
					end
					tile.elevation = math.clamp(tile.elevation, cfg.min, cfg.max)
				end

				ops = ops + 1
				if ops % YIELD_INTERVAL == 0 then task.wait() end
			end
		end
	end

	---------------------------------------------------------
	-- PHASE 4: LAN constraint enforcement (3 passes)
	-- Adjacent LAN-family tiles must differ by ≤ 1 (Jump=1).
	---------------------------------------------------------
	for _ = 1, 3 do
		for y = 1, h do
			for x = 1, w do
				local tile = tiles[y][x]
				if LAN_FAMILY[tile.marker] then
					for _, dir in ipairs(CARDINAL) do
						local nx, ny = x + dir.x, y + dir.y
						if isInBounds(nx, ny, w, h) then
							local neighbor = tiles[ny][nx]
							if LAN_FAMILY[neighbor.marker] then
								local diff = tile.elevation - neighbor.elevation
								if diff > 1 then
									tile.elevation = neighbor.elevation + 1
								elseif diff < -1 then
									tile.elevation = neighbor.elevation - 1
								end
								tile.elevation = math.clamp(
									tile.elevation, cfg.min, cfg.max
								)
							end
						end
					end
				end

				ops = ops + 1
				if ops % YIELD_INTERVAL == 0 then task.wait() end
			end
		end
	end

	---------------------------------------------------------
	-- PHASE 5: Slope reachability
	-- Prevents large unreachable high plateaus while allowing
	-- isolated peaks and cliff faces to persist.
	-- A max-elevation tile is only lowered if it is:
	--   (a) NOT reachable from elevation 1 via ≤1 diff steps, AND
	--   (b) ALL of its cardinal in-bounds neighbors are also
	--       at biome max elevation (interior of a plateau).
	-- Edge tiles and cliff faces (at least one lower neighbor)
	-- are preserved even when unreachable.
	-- Max 10 iterations to converge.
	---------------------------------------------------------
	for _ = 1, 10 do
		-- BFS flood from all elevation-1 tiles.
		local reachable = {}
		local queue     = {}
		local qHead     = 1

		for y = 1, h do
			for x = 1, w do
				if tiles[y][x].elevation == 1 then
					local key = coordKey(x, y)
					reachable[key] = true
					table.insert(queue, { x = x, y = y })
				end
			end
		end

		while qHead <= #queue do
			local cur = queue[qHead]
			qHead     = qHead + 1

			for _, dir in ipairs(CARDINAL) do
				local nx, ny = cur.x + dir.x, cur.y + dir.y
				if isInBounds(nx, ny, w, h) then
					local nKey = coordKey(nx, ny)
					if not reachable[nKey] then
						local diff = math.abs(
							tiles[cur.y][cur.x].elevation
								- tiles[ny][nx].elevation
						)
						if diff <= 1 then
							reachable[nKey] = true
							table.insert(queue, { x = nx, y = ny })
						end
					end
				end
			end
		end

		-- Lower only unreachable max-elevation tiles whose
		-- cardinal neighbors are ALL also at max elevation
		-- (plateau interiors). Cliff-edge tiles are kept.
		local lowered = false
		for y = 1, h do
			for x = 1, w do
				if tiles[y][x].elevation == cfg.max then
					if not reachable[coordKey(x, y)] then
						-- Check: are all in-bounds cardinal neighbors at max?
						local allMaxNeighbors = true
						for _, dir in ipairs(CARDINAL) do
							local nx, ny = x + dir.x, y + dir.y
							if isInBounds(nx, ny, w, h) then
								if tiles[ny][nx].elevation ~= cfg.max then
									allMaxNeighbors = false
									break
								end
							end
						end
						if allMaxNeighbors then
							tiles[y][x].elevation = tiles[y][x].elevation - 1
							lowered = true
						end
					end
				end
			end
		end

		if not lowered then break end
	end

	return mapState
end

return ElevationPass
