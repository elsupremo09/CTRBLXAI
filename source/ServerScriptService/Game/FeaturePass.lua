-- FeaturePass.lua
-- CTRBLXAI | Feature Coherence System — Round 4
--
-- Places connected terrain features within regions.
-- Features replace floor terrain tiles to create recognizable geographic
-- elements (lakes, lava channels, rock formations, structures, etc.).
--
-- Pipeline position: runs AFTER FloorPass, BEFORE TransitionPass.
-- Does NOT touch elevation (ElevationPass handles that later).
-- Does NOT touch protected tiles (PD/ED/LAN).
-- Uses mapState.rng.featureRng for all random decisions (determinism).
--
-- 17 feature types (Round 1-2: 1-7, Round 3: 8-13, Round 4: 14-17):
--   1. Water Body       — Shallow Water ring → Deep Water core → Mud shoreline
--   2. Rock Formation   — Rocky core → Cracked Ground edges
--   3. Lava Channel     — Molten channel → Rocky/Sand buffer
--   4. Frozen Lake      — Ice core → Shallow Water thaw edge → Rocky shore
--   5. Wetland          — Swamp core → Mud edge → Shallow Water pockets
--   6. Sandy Expanse    — Sand area → Quicksand hazards
--   7. Corruption       — Magic Circle center → Tainted Ground radial
--   8. Structure        — Metal/Wooden Floor rectangular building + Clear border
--   9. Fortification    — Rocky wall segment with gate gaps
--  10. Moat             — Shallow Water parallel to Fortification + bridge
--  11. Ruin Structure   — Rocky/Cracked Ground broken rectangle with gaps
--  12. Ridge / Cliff    — Linear Rocky near ADV tiles (ElevationPass makes tall)
--  13. Bridge / Pass    — Repair pass: ensures no LAN tile is impassable
--  14. Road / Path      — Clear road connecting eligible regions + shoulders
--  15. River            — Shallow Water channel with Mud banks (cross-region)
--  16. Cave Corridor    — Clear passage connecting Cave Chambers
--  17. Forest Density   — Clover Field scatter in Forest regions
--
-- Location: ServerScriptService/Game/FeaturePass.lua

local FeaturePass = {}

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

local CARDINAL = {
	{ x =  0, y =  1 },
	{ x =  0, y = -1 },
	{ x =  1, y =  0 },
	{ x = -1, y =  0 },
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

--- Deterministic Fisher-Yates shuffle.
local function shuffleArray(arr, rng)
	for i = #arr, 2, -1 do
		local j = rng:NextInteger(1, i)
		arr[i], arr[j] = arr[j], arr[i]
	end
end

--- Pick a random seed tile from candidates that is not in usedSet.
local function pickSeed(candidates, usedSet, rng)
	local valid = {}
	for _, pos in ipairs(candidates) do
		if not usedSet[coordKey(pos.x, pos.y)] then
			table.insert(valid, pos)
		end
	end
	if #valid == 0 then return nil end
	return valid[rng:NextInteger(1, #valid)]
end

--- Check if all 4-cardinal neighbors of (x,y) are in blobSet.
--- Returns false if any neighbor is out of bounds.
local function allCardinalInBlob(x, y, w, h, blobSet)
	for _, dir in ipairs(CARDINAL) do
		local nx, ny = x + dir.x, y + dir.y
		if not isInBounds(nx, ny, w, h) then return false end
		if not blobSet[coordKey(nx, ny)] then return false end
	end
	return true
end

--------------------------------------------------
-- BLOB GROWTH — BFS
--------------------------------------------------

--- Grow a connected blob from a seed tile using randomized BFS.
--- Returns: blob (array of {x,y}), blobSet (coordKey → true).
--- Grows within same region, skips protected and usedSet tiles.
local function growBlob(seed, targetSize, rng, tiles, w, h, regionId, usedSet)
	local blob    = {}
	local blobSet = {}
	local queue    = {}
	local queueSet = {}

	local seedKey = coordKey(seed.x, seed.y)
	if usedSet[seedKey] or tiles[seed.y][seed.x].protected then
		return blob, blobSet
	end

	-- Start with seed.
	blobSet[seedKey] = true
	table.insert(blob, seed)

	-- Enqueue seed's valid neighbors.
	for _, dir in ipairs(CARDINAL) do
		local nx, ny = seed.x + dir.x, seed.y + dir.y
		if isInBounds(nx, ny, w, h) then
			local nKey  = coordKey(nx, ny)
			local nTile = tiles[ny][nx]
			if nTile.regionId == regionId and not nTile.protected
				and not usedSet[nKey] and not blobSet[nKey]
				and not queueSet[nKey] then
				table.insert(queue, { x = nx, y = ny })
				queueSet[nKey] = true
			end
		end
	end

	-- BFS: pick random frontier tile, add to blob, enqueue its neighbors.
	while #blob < targetSize and #queue > 0 do
		local idx    = rng:NextInteger(1, #queue)
		local picked = queue[idx]
		local pKey   = coordKey(picked.x, picked.y)

		-- Swap-remove from queue.
		queue[idx]    = queue[#queue]
		queue[#queue] = nil
		queueSet[pKey] = nil

		if not blobSet[pKey] and not usedSet[pKey] then
			blobSet[pKey] = true
			table.insert(blob, picked)

			-- Enqueue picked's valid neighbors.
			for _, dir in ipairs(CARDINAL) do
				local nx, ny = picked.x + dir.x, picked.y + dir.y
				if isInBounds(nx, ny, w, h) then
					local nKey  = coordKey(nx, ny)
					local nTile = tiles[ny][nx]
					if nTile.regionId == regionId and not nTile.protected
						and not usedSet[nKey] and not blobSet[nKey]
						and not queueSet[nKey] then
						table.insert(queue, { x = nx, y = ny })
						queueSet[nKey] = true
					end
				end
			end
		end
	end

	return blob, blobSet
end

--- Grow a linear blob (for channels and ridges).
--- Extends in a random primary direction, then widens if channelWidth > 1.
local function growLinearBlob(seed, targetLength, channelWidth, rng, tiles, w, h, regionId, usedSet)
	local blob    = {}
	local blobSet = {}

	-- Pick primary direction.
	local dirIdx     = rng:NextInteger(1, 4)
	local primaryDir = CARDINAL[dirIdx]
	local reverseDir = { x = -primaryDir.x, y = -primaryDir.y }

	-- Perpendicular directions for widening.
	local perpDirs
	if primaryDir.x == 0 then
		perpDirs = { { x = 1, y = 0 }, { x = -1, y = 0 } }
	else
		perpDirs = { { x = 0, y = 1 }, { x = 0, y = -1 } }
	end

	-- Helper: try to add a tile to the centerline.
	local centerline = {}
	local function tryAdd(cx, cy)
		if not isInBounds(cx, cy, w, h) then return false end
		local key  = coordKey(cx, cy)
		local tile = tiles[cy][cx]
		if blobSet[key] or usedSet[key] then return false end
		if tile.regionId ~= regionId or tile.protected then return false end
		blobSet[key] = true
		table.insert(centerline, { x = cx, y = cy })
		return true
	end

	-- Grow forward from seed.
	local cx, cy = seed.x, seed.y
	for _ = 1, targetLength do
		if not tryAdd(cx, cy) then break end
		cx = cx + primaryDir.x
		cy = cy + primaryDir.y
	end

	-- Grow backward from seed (skip seed itself).
	cx = seed.x + reverseDir.x
	cy = seed.y + reverseDir.y
	for _ = 1, targetLength - #centerline do
		if #centerline >= targetLength then break end
		if not tryAdd(cx, cy) then break end
		cx = cx + reverseDir.x
		cy = cy + reverseDir.y
	end

	-- Copy centerline to blob.
	for _, pos in ipairs(centerline) do
		table.insert(blob, pos)
	end

	-- Widen perpendicular.
	if channelWidth > 1 then
		for _, pos in ipairs(centerline) do
			for _, pDir in ipairs(perpDirs) do
				local nx, ny = pos.x + pDir.x, pos.y + pDir.y
				if isInBounds(nx, ny, w, h) then
					local nKey  = coordKey(nx, ny)
					local nTile = tiles[ny][nx]
					if not blobSet[nKey] and not usedSet[nKey]
						and nTile.regionId == regionId
						and not nTile.protected then
						blobSet[nKey] = true
						table.insert(blob, { x = nx, y = ny })
					end
				end
			end
		end
	end

	return blob, blobSet
end

--------------------------------------------------
-- DIJKSTRA PATHFINDING (cross-region features)
--------------------------------------------------

--- Trace a shortest path from (startX, startY) to (endX, endY).
--- costFn(tile) → cost > 0 (passable), or 0 (impassable).
--- Returns: array of {x, y} forming the path, or nil if unreachable.
--- Deterministic: ties broken by coordKey order (lower key wins).
local function tracePath(tiles, w, h, startX, startY, endX, endY, costFn)
	local startKey = coordKey(startX, startY)
	local endKey   = coordKey(endX, endY)

	local dist    = { [startKey] = 0 }
	local prev    = {}
	local closed  = {}
	local open    = { startKey }
	local inOpen  = { [startKey] = true }

	while #open > 0 do
		-- Linear-scan min in open set; ties broken by lower coordKey.
		local bestIdx  = 1
		local bestDist = dist[open[1]] or math.huge
		local bestKey  = open[1]
		for i = 2, #open do
			local k = open[i]
			local d = dist[k] or math.huge
			if d < bestDist or (d == bestDist and k < bestKey) then
				bestIdx  = i
				bestDist = d
				bestKey  = k
			end
		end

		-- Swap-remove from open.
		open[bestIdx]   = open[#open]
		open[#open]     = nil
		inOpen[bestKey] = nil

		if closed[bestKey] then continue end
		closed[bestKey] = true

		if bestKey == endKey then break end

		-- Decode key → x, y.
		local by = math.floor(bestKey / 100000)
		local bx = bestKey - by * 100000

		for _, dir in ipairs(CARDINAL) do
			local nx, ny = bx + dir.x, by + dir.y
			if isInBounds(nx, ny, w, h) then
				local nKey = coordKey(nx, ny)
				if not closed[nKey] then
					local cost = costFn(tiles[ny][nx])
					if cost > 0 then
						local nd = bestDist + cost
						if not dist[nKey] or nd < dist[nKey] then
							dist[nKey] = nd
							prev[nKey] = bestKey
							if not inOpen[nKey] then
								table.insert(open, nKey)
								inOpen[nKey] = true
							end
						end
					end
				end
			end
		end
	end

	-- Reconstruct path from end to start.
	if not dist[endKey] then return nil end

	local path = {}
	local ck   = endKey
	while ck and ck ~= startKey do
		local cy = math.floor(ck / 100000)
		local cx = ck - cy * 100000
		table.insert(path, 1, { x = cx, y = cy })
		ck = prev[ck]
	end
	table.insert(path, 1, { x = startX, y = startY })

	return path
end

--------------------------------------------------
-- REGION → FEATURE CONFIG
-- Each region type maps to an array of feature placements.
-- Fields: type, minCount, maxCount, minSize, maxSize,
--         minCluster, linear (optional), depends (optional).
--------------------------------------------------

local REGION_FEATURES = {
	["Grassland"] = {
		{ type = "WaterBody", minCount = 0, maxCount = 1,
		  minSize = 5, maxSize = 10, minCluster = 3 },
	},
	["Farmland"]         = {},
	["Village"] = {
		{ type = "Structure", minCount = 1, maxCount = 2,
		  minSize = 4, maxSize = 12, minCluster = 4 },
	},
	["Forest"]           = {},
	["Clearing"]         = {},
	["Rocky"] = {
		{ type = "RockFormation", minCount = 1, maxCount = 2,
		  minSize = 4, maxSize = 15, minCluster = 3 },
		{ type = "Ridge", minCount = 0, maxCount = 1,
		  minSize = 3, maxSize = 8, minCluster = 3 },
	},
	["Mountain Pass"] = {
		{ type = "RockFormation", minCount = 1, maxCount = 2,
		  minSize = 4, maxSize = 12, minCluster = 3, linear = true },
		{ type = "Ridge", minCount = 0, maxCount = 1,
		  minSize = 3, maxSize = 8, minCluster = 3 },
	},
	["Riverbank"] = {
		{ type = "WaterBody", minCount = 1, maxCount = 1,
		  minSize = 5, maxSize = 20, minCluster = 3 },
	},
	["Marsh"] = {
		{ type = "Wetland", minCount = 1, maxCount = 1,
		  minSize = 8, maxSize = 25, minCluster = 5 },
	},
	["Frozen Lake"] = {
		{ type = "FrozenLake", minCount = 1, maxCount = 1,
		  minSize = 6, maxSize = 25, minCluster = 4 },
	},
	["Volcanic Rock"] = {
		{ type = "RockFormation", minCount = 1, maxCount = 2,
		  minSize = 4, maxSize = 12, minCluster = 3 },
		{ type = "LavaChannel", minCount = 0, maxCount = 1,
		  minSize = 3, maxSize = 6, minCluster = 2 },
	},
	["Lava Channel"] = {
		{ type = "LavaChannel", minCount = 1, maxCount = 1,
		  minSize = 5, maxSize = 12, minCluster = 2, linear = true },
	},
	["Ruins"] = {
		{ type = "RuinStructure", minCount = 1, maxCount = 2,
		  minSize = 4, maxSize = 20, minCluster = 4 },
	},
	["Castle Courtyard"] = {
		{ type = "Fortification", minCount = 1, maxCount = 1,
		  minSize = 4, maxSize = 10, minCluster = 4 },
		{ type = "Moat", minCount = 0, maxCount = 1,
		  minSize = 3, maxSize = 10, minCluster = 3,
		  depends = "Fortification" },
	},
	["Castle Interior"] = {
		{ type = "Structure", minCount = 1, maxCount = 2,
		  minSize = 4, maxSize = 12, minCluster = 4 },
	},
	["Graveyard"] = {
		{ type = "CorruptionSpread", minCount = 1, maxCount = 1,
		  minSize = 5, maxSize = 15, minCluster = 3 },
	},
	["Corrupted"] = {
		{ type = "CorruptionSpread", minCount = 1, maxCount = 2,
		  minSize = 5, maxSize = 15, minCluster = 3 },
	},
	["Beach"] = {
		{ type = "SandyExpanse", minCount = 1, maxCount = 1,
		  minSize = 5, maxSize = 20, minCluster = 3 },
	},
	["Dock"] = {
		{ type = "WaterBody", minCount = 0, maxCount = 1,
		  minSize = 5, maxSize = 10, minCluster = 3 },
	},
	["Cave Chamber"] = {
		{ type = "RockFormation", minCount = 1, maxCount = 2,
		  minSize = 4, maxSize = 12, minCluster = 3 },
	},
}

--------------------------------------------------
-- WAT MARKER → FEATURE TYPE (biome-based)
-- Round 2: only WAT markers handled.
-- ADV/HZD/BLK/NEU markers deferred to Round 5.
--------------------------------------------------

local WAT_BIOME_FEATURE = {
	Plains    = "WaterBody",
	Forest    = "WaterBody",
	Swamp     = "WaterBody",
	Desert    = "WaterBody",
	Highlands = "WaterBody",
	Tundra    = "FrozenLake",
	Volcano   = "LavaChannel",
	Cave      = "WaterBody",
	Ruins     = "WaterBody",
	Castle    = nil,          -- Moat placed via region features, not WAT markers
	Corrupted = nil,          -- No water in corrupted zones
}

local WAT_FEATURE_DEFAULTS = {
	WaterBody   = { minSize = 5,  maxSize = 20, minCluster = 3 },
	FrozenLake  = { minSize = 6,  maxSize = 25, minCluster = 4 },
	LavaChannel = { minSize = 5,  maxSize = 12, minCluster = 2 },
}

--------------------------------------------------
-- HZD MARKER → HAZARD TERRAIN (biome-based)
-- Phase 2b: biome-appropriate hazard for HZD clusters.
--------------------------------------------------

local HZD_BIOME_HAZARD = {
	Plains    = "Mud",
	Forest    = "Mud",
	Desert    = "Sand",           -- with optional Quicksand
	Swamp     = "Swamp",
	Highlands = "Ice",
	Tundra    = "Ice",
	Volcano   = "Molten",         -- requires Rocky buffer
	Cave      = "Cracked Ground",
	Ruins     = "Cracked Ground",
	Castle    = "Mud",
	Corrupted = "Tainted Ground",
}

--------------------------------------------------
-- NEU MARKER → FEATURE POOL (biome-based)
-- Phase 2b: 0-2 random features from weighted pool.
-- Each entry: { type = featureType, weight = number }.
-- "nothing" entries add chance of zero features.
--------------------------------------------------

local NEU_BIOME_POOL = {
	Plains    = {
		{ type = "WaterBody",        weight = 40 },
		{ type = "RockFormation",    weight = 30 },
	},
	Forest    = {
		{ type = "WaterBody",        weight = 30 },
		{ type = "RockFormation",    weight = 20 },
	},
	Desert    = {
		{ type = "SandyExpanse",     weight = 40 },
		{ type = "RockFormation",    weight = 30 },
	},
	Swamp     = {
		{ type = "Wetland",          weight = 40 },
		{ type = "WaterBody",        weight = 30 },
	},
	Highlands = {
		{ type = "RockFormation",    weight = 50 },
		{ type = "Ridge",            weight = 20 },
	},
	Tundra    = {
		{ type = "FrozenLake",       weight = 40 },
		{ type = "RockFormation",    weight = 30 },
	},
	Volcano   = {
		{ type = "LavaChannel",      weight = 30 },
		{ type = "RockFormation",    weight = 40 },
	},
	Cave      = {
		{ type = "RockFormation",    weight = 50 },
	},
	Ruins     = {
		{ type = "RuinStructure",    weight = 40 },
		{ type = "RockFormation",    weight = 30 },
	},
	Castle    = {
		{ type = "Structure",        weight = 30 },
		{ type = "RockFormation",    weight = 20 },
	},
	Corrupted = {
		{ type = "CorruptionSpread", weight = 40 },
	},
}

-- Default sizes for NEU-spawned features (override REGION_FEATURES defaults).
local NEU_FEATURE_DEFAULTS = {
	minSize    = 4,
	maxSize    = 12,
	minCluster = 3,
}

--------------------------------------------------
-- FEATURE PLACERS
-- Each function: (candidates, minSize, maxSize, minCluster,
--                 opts, rng, tiles, w, h, regionId, usedSet)
-- Returns: number of tiles consumed (blob + border).
--------------------------------------------------

----- 1. Water Body ----------------------------
local function placeWaterBody(candidates, minSize, maxSize, minCluster, opts, rng, tiles, w, h, regionId, usedSet)
	local seed = pickSeed(candidates, usedSet, rng)
	if not seed then return 0 end

	local targetSize = rng:NextInteger(minSize, math.max(minSize, maxSize))
	local blob, blobSet = growBlob(seed, targetSize, rng, tiles, w, h, regionId, usedSet)

	if #blob < minCluster then return 0 end

	-- Classify: interior (all 4 neighbors in blob) → Deep Water, else Shallow Water.
	local interiorSet = {}
	for _, pos in ipairs(blob) do
		if allCardinalInBlob(pos.x, pos.y, w, h, blobSet) then
			interiorSet[coordKey(pos.x, pos.y)] = true
		end
	end

	local tilesUsed = 0

	for _, pos in ipairs(blob) do
		local key = coordKey(pos.x, pos.y)
		if interiorSet[key] then
			tiles[pos.y][pos.x].terrain = "Deep Water"
		else
			tiles[pos.y][pos.x].terrain = "Shallow Water"
		end
		usedSet[key] = true
		tilesUsed    = tilesUsed + 1
	end

	-- Mud shoreline on land-side neighbors (same region, not protected, not used).
	local borderApplied = {}
	for _, pos in ipairs(blob) do
		for _, dir in ipairs(CARDINAL) do
			local nx, ny = pos.x + dir.x, pos.y + dir.y
			if isInBounds(nx, ny, w, h) then
				local nKey  = coordKey(nx, ny)
				local nTile = tiles[ny][nx]
				if not blobSet[nKey] and not borderApplied[nKey]
					and not nTile.protected and not usedSet[nKey]
					and nTile.regionId == regionId then
					local nTerrain = nTile.terrain
					-- Only place Mud on dry-land terrains.
					if nTerrain ~= "Shallow Water" and nTerrain ~= "Deep Water"
						and nTerrain ~= "Mud" and nTerrain ~= "Molten"
						and nTerrain ~= "Quicksand" then
						nTile.terrain      = "Mud"
						borderApplied[nKey] = true
						usedSet[nKey]       = true
						tilesUsed           = tilesUsed + 1
					end
				end
			end
		end
	end

	return tilesUsed
end

----- 2. Rock Formation -----------------------
local function placeRockFormation(candidates, minSize, maxSize, minCluster, opts, rng, tiles, w, h, regionId, usedSet)
	local seed = pickSeed(candidates, usedSet, rng)
	if not seed then return 0 end

	local targetSize = rng:NextInteger(minSize, math.max(minSize, maxSize))
	local blob, blobSet

	if opts and opts.linear then
		blob, blobSet = growLinearBlob(
			seed, targetSize, 1, rng, tiles, w, h, regionId, usedSet)
	else
		blob, blobSet = growBlob(
			seed, targetSize, rng, tiles, w, h, regionId, usedSet)
	end

	if #blob < minCluster then return 0 end

	-- All blob tiles → Rocky.
	local tilesUsed = 0
	for _, pos in ipairs(blob) do
		tiles[pos.y][pos.x].terrain = "Rocky"
		usedSet[coordKey(pos.x, pos.y)] = true
		tilesUsed = tilesUsed + 1
	end

	-- 10-20% of perimeter tiles → Cracked Ground.
	local edges = {}
	for _, pos in ipairs(blob) do
		if not allCardinalInBlob(pos.x, pos.y, w, h, blobSet) then
			table.insert(edges, pos)
		end
	end

	if #edges > 0 then
		local crackFraction = 0.10 + rng:NextNumber() * 0.10
		local crackCount    = math.max(1,
			math.floor(#edges * crackFraction + 0.5))
		crackCount = math.min(crackCount, #edges)

		shuffleArray(edges, rng)
		for i = 1, crackCount do
			tiles[edges[i].y][edges[i].x].terrain = "Cracked Ground"
		end
	end

	return tilesUsed
end

----- 3. Lava Channel -------------------------
local function placeLavaChannel(candidates, minSize, maxSize, minCluster, opts, rng, tiles, w, h, regionId, usedSet)
	local seed = pickSeed(candidates, usedSet, rng)
	if not seed then return 0 end

	local blob, blobSet

	if opts and opts.linear then
		-- Channel: 1-2 wide, 5-12 long.
		local channelWidth  = rng:NextInteger(1, 2)
		local channelLength = rng:NextInteger(
			math.max(5, minSize), math.max(5, maxSize))
		blob, blobSet = growLinearBlob(
			seed, channelLength, channelWidth, rng, tiles, w, h, regionId, usedSet)
	else
		-- Pool: small blob.
		local poolSize = rng:NextInteger(minSize, math.max(minSize, maxSize))
		blob, blobSet = growBlob(
			seed, poolSize, rng, tiles, w, h, regionId, usedSet)
	end

	if #blob < minCluster then return 0 end

	-- All blob tiles → Molten.
	local tilesUsed = 0
	for _, pos in ipairs(blob) do
		tiles[pos.y][pos.x].terrain = "Molten"
		usedSet[coordKey(pos.x, pos.y)] = true
		tilesUsed = tilesUsed + 1
	end

	-- Mandatory 1-tile Rocky/Sand buffer around all Molten tiles.
	-- Applied to ALL non-protected neighbors regardless of region (safety).
	local bufferApplied = {}
	for _, pos in ipairs(blob) do
		for _, dir in ipairs(CARDINAL) do
			local nx, ny = pos.x + dir.x, pos.y + dir.y
			if isInBounds(nx, ny, w, h) then
				local nKey  = coordKey(nx, ny)
				local nTile = tiles[ny][nx]
				if not blobSet[nKey] and not bufferApplied[nKey]
					and not nTile.protected then
					local nTerrain = nTile.terrain
					if nTerrain ~= "Rocky" and nTerrain ~= "Sand"
						and nTerrain ~= "Molten" then
						nTile.terrain       = "Rocky"
						bufferApplied[nKey] = true
						-- Only count toward budget if same region.
						if nTile.regionId == regionId then
							usedSet[nKey] = true
							tilesUsed     = tilesUsed + 1
						end
					end
				end
			end
		end
	end

	return tilesUsed
end

----- 4. Frozen Lake --------------------------
local function placeFrozenLake(candidates, minSize, maxSize, minCluster, opts, rng, tiles, w, h, regionId, usedSet)
	local seed = pickSeed(candidates, usedSet, rng)
	if not seed then return 0 end

	local targetSize = rng:NextInteger(minSize, math.max(minSize, maxSize))
	local blob, blobSet = growBlob(
		seed, targetSize, rng, tiles, w, h, regionId, usedSet)

	if #blob < minCluster then return 0 end

	-- Identify perimeter tiles (at least one non-blob cardinal neighbor).
	local perimeter = {}
	for _, pos in ipairs(blob) do
		if not allCardinalInBlob(pos.x, pos.y, w, h, blobSet) then
			table.insert(perimeter, pos)
		end
	end

	-- Set all blob tiles to Ice (core).
	local tilesUsed = 0
	for _, pos in ipairs(blob) do
		tiles[pos.y][pos.x].terrain = "Ice"
		usedSet[coordKey(pos.x, pos.y)] = true
		tilesUsed = tilesUsed + 1
	end

	-- Thawing edge: ~30% of perimeter → Shallow Water.
	if #perimeter > 0 then
		local thawCount = math.max(1,
			math.floor(#perimeter * 0.30 + 0.5))
		thawCount = math.min(thawCount, #perimeter)

		shuffleArray(perimeter, rng)
		for i = 1, thawCount do
			tiles[perimeter[i].y][perimeter[i].x].terrain = "Shallow Water"
		end
	end

	-- Shore: border tiles outside blob → Rocky or Clear.
	local borderApplied = {}
	for _, pos in ipairs(blob) do
		for _, dir in ipairs(CARDINAL) do
			local nx, ny = pos.x + dir.x, pos.y + dir.y
			if isInBounds(nx, ny, w, h) then
				local nKey  = coordKey(nx, ny)
				local nTile = tiles[ny][nx]
				if not blobSet[nKey] and not borderApplied[nKey]
					and not nTile.protected and not usedSet[nKey]
					and nTile.regionId == regionId then
					nTile.terrain       = "Rocky"
					borderApplied[nKey] = true
					usedSet[nKey]       = true
					tilesUsed           = tilesUsed + 1
				end
			end
		end
	end

	return tilesUsed
end

----- 5. Wetland ------------------------------
local function placeWetland(candidates, minSize, maxSize, minCluster, opts, rng, tiles, w, h, regionId, usedSet)
	local seed = pickSeed(candidates, usedSet, rng)
	if not seed then return 0 end

	local targetSize = rng:NextInteger(minSize, math.max(minSize, maxSize))
	local blob, blobSet = growBlob(
		seed, targetSize, rng, tiles, w, h, regionId, usedSet)

	if #blob < minCluster then return 0 end

	-- Classify: interior → Swamp, perimeter → Mud.
	local interior  = {}
	local tilesUsed = 0

	for _, pos in ipairs(blob) do
		local key = coordKey(pos.x, pos.y)
		usedSet[key] = true
		tilesUsed    = tilesUsed + 1

		if allCardinalInBlob(pos.x, pos.y, w, h, blobSet) then
			tiles[pos.y][pos.x].terrain = "Swamp"
			table.insert(interior, pos)
		else
			tiles[pos.y][pos.x].terrain = "Mud"
		end
	end

	-- Shallow Water pockets: 1-3 interior tiles.
	if #interior > 0 then
		local pocketCount = rng:NextInteger(1, math.min(3, #interior))
		shuffleArray(interior, rng)
		for i = 1, pocketCount do
			tiles[interior[i].y][interior[i].x].terrain = "Shallow Water"
		end
	end

	return tilesUsed
end

----- 6. Sandy Expanse ------------------------
local function placeSandyExpanse(candidates, minSize, maxSize, minCluster, opts, rng, tiles, w, h, regionId, usedSet)
	local seed = pickSeed(candidates, usedSet, rng)
	if not seed then return 0 end

	local targetSize = rng:NextInteger(minSize, math.max(minSize, maxSize))
	local blob, blobSet = growBlob(
		seed, targetSize, rng, tiles, w, h, regionId, usedSet)

	if #blob < minCluster then return 0 end

	-- All blob tiles → Sand.
	local tilesUsed = 0
	for _, pos in ipairs(blob) do
		tiles[pos.y][pos.x].terrain = "Sand"
		usedSet[coordKey(pos.x, pos.y)] = true
		tilesUsed = tilesUsed + 1
	end

	-- Quicksand hazards: 0-2 tiles.
	-- Must have Sand on all 4 cardinal neighbors and not be protected.
	local quicksandCount = rng:NextInteger(0, 2)
	if quicksandCount > 0 then
		local eligible = {}
		for _, pos in ipairs(blob) do
			if not tiles[pos.y][pos.x].protected
				and allCardinalInBlob(pos.x, pos.y, w, h, blobSet) then
				table.insert(eligible, pos)
			end
		end

		if #eligible > 0 then
			shuffleArray(eligible, rng)
			for i = 1, math.min(quicksandCount, #eligible) do
				local pos = eligible[i]
				-- Verify all 4 cardinal neighbors are still Sand
				-- (a prior Quicksand placement could break this).
				local allSand = true
				for _, dir in ipairs(CARDINAL) do
					local nx, ny = pos.x + dir.x, pos.y + dir.y
					if not isInBounds(nx, ny, w, h)
						or tiles[ny][nx].terrain ~= "Sand" then
						allSand = false
						break
					end
				end
				if allSand then
					tiles[pos.y][pos.x].terrain = "Quicksand"
				end
			end
		end
	end

	return tilesUsed
end

----- 7. Corruption Spread --------------------
local function placeCorruptionSpread(candidates, minSize, maxSize, minCluster, opts, rng, tiles, w, h, regionId, usedSet)
	local seed = pickSeed(candidates, usedSet, rng)
	if not seed then return 0 end

	local targetSize = rng:NextInteger(minSize, math.max(minSize, maxSize))
	local blob, blobSet = growBlob(
		seed, targetSize, rng, tiles, w, h, regionId, usedSet)

	if #blob < minCluster then return 0 end

	-- Center (first 1-2 tiles in blob = closest to seed) → Magic Circle.
	-- Remainder → Tainted Ground.
	local centerCount = rng:NextInteger(1, math.min(2, #blob))
	local tilesUsed   = 0

	for i, pos in ipairs(blob) do
		local key = coordKey(pos.x, pos.y)
		usedSet[key] = true
		tilesUsed    = tilesUsed + 1

		if i <= centerCount then
			tiles[pos.y][pos.x].terrain = "Magic Circle"
		else
			tiles[pos.y][pos.x].terrain = "Tainted Ground"
		end
	end

	return tilesUsed
end

--------------------------------------------------
-- STRUCTURAL FEATURE PLACERS (Round 3: types 8-13)
--------------------------------------------------

----- 8. Structure (Building) -----------------
--- Rectangular Metal/Wooden Floor building with 1-tile Clear border.
--- Tries up to 3 random seeds for a valid rectangular footprint.
local function placeStructure(candidates, minSize, maxSize, minCluster,
		opts, rng, tiles, w, h, regionId, usedSet)
	local regionType  = (opts and opts.regionType) or "Village"
	local metalChance = (regionType == "Castle Interior") and 0.60 or 0.40

	-- Try up to 3 random seeds for rectangular placement.
	for _ = 1, 3 do
		local seed = pickSeed(candidates, usedSet, rng)
		if not seed then return 0 end

		local bw = rng:NextInteger(2, 3)  -- width  2–3
		local bh = rng:NextInteger(2, 4)  -- height 2–4

		-- Check if all tiles in the rectangle are available.
		local footprint = {}
		local ok = true
		for dy = 0, bh - 1 do
			for dx = 0, bw - 1 do
				local tx, ty = seed.x + dx, seed.y + dy
				if not isInBounds(tx, ty, w, h) then ok = false; break end
				local key  = coordKey(tx, ty)
				local tile = tiles[ty][tx]
				if tile.protected or usedSet[key]
					or tile.regionId ~= regionId then
					ok = false; break
				end
				table.insert(footprint, { x = tx, y = ty })
			end
			if not ok then break end
		end

		if ok and #footprint >= minCluster then
			local tilesUsed = 0

			-- Assign Metal or Wooden Floor to footprint tiles.
			for _, pos in ipairs(footprint) do
				local key = coordKey(pos.x, pos.y)
				if rng:NextNumber() < metalChance then
					tiles[pos.y][pos.x].terrain = "Metal"
				else
					tiles[pos.y][pos.x].terrain = "Wooden Floor"
				end
				usedSet[key] = true
				tilesUsed    = tilesUsed + 1
			end

			-- 1-tile Clear border (courtyard / clearing).
			local borderApplied = {}
			for _, pos in ipairs(footprint) do
				for _, dir in ipairs(CARDINAL) do
					local nx, ny = pos.x + dir.x, pos.y + dir.y
					if isInBounds(nx, ny, w, h) then
						local nKey  = coordKey(nx, ny)
						local nTile = tiles[ny][nx]
						if not usedSet[nKey] and not borderApplied[nKey]
							and not nTile.protected
							and nTile.regionId == regionId then
							nTile.terrain       = "Clear"
							borderApplied[nKey] = true
							usedSet[nKey]       = true
							tilesUsed           = tilesUsed + 1
						end
					end
				end
			end

			return tilesUsed
		end
	end

	return 0
end

----- 9. Fortification (Wall) -----------------
--- Linear Rocky wall segment with gate gaps (passable breaks).
--- Exports wall data via opts._fortResult for Moat placement.
local function placeFortification(candidates, minSize, maxSize, minCluster,
		opts, rng, tiles, w, h, regionId, usedSet)
	-- Pick wall direction (horizontal or vertical).
	local isHoriz = rng:NextNumber() < 0.5
	local dir = isHoriz and { x = 1, y = 0 } or { x = 0, y = 1 }
	local rev = { x = -dir.x, y = -dir.y }

	local seed = pickSeed(candidates, usedSet, rng)
	if not seed then return 0 end

	-- Grow forward from seed.
	local line    = {}
	local lineSet = {}
	local cx, cy  = seed.x, seed.y
	for _ = 1, maxSize do
		if not isInBounds(cx, cy, w, h) then break end
		local key  = coordKey(cx, cy)
		local tile = tiles[cy][cx]
		if tile.protected or usedSet[key]
			or tile.regionId ~= regionId then break end
		table.insert(line, { x = cx, y = cy })
		lineSet[key] = true
		cx = cx + dir.x
		cy = cy + dir.y
	end

	-- Grow backward (skip seed).
	cx = seed.x + rev.x
	cy = seed.y + rev.y
	local targetLen = rng:NextInteger(math.max(minSize, 4), maxSize)
	while #line < targetLen do
		if not isInBounds(cx, cy, w, h) then break end
		local key  = coordKey(cx, cy)
		local tile = tiles[cy][cx]
		if tile.protected or usedSet[key]
			or tile.regionId ~= regionId then break end
		table.insert(line, 1, { x = cx, y = cy })
		lineSet[key] = true
		cx = cx + rev.x
		cy = cy + rev.y
	end

	if #line < minCluster then return 0 end

	-- Determine gate gaps: at least 1 gap per 5 tiles of wall.
	-- Prefer positions adjacent to LAN tiles.
	local gapInterval = rng:NextInteger(4, 5)
	local gateIndices = {}

	local function isNearLan(pos)
		for _, d in ipairs(CARDINAL) do
			local nx, ny = pos.x + d.x, pos.y + d.y
			if isInBounds(nx, ny, w, h)
				and tiles[ny][nx].marker == "LAN" then
				return true
			end
		end
		return false
	end

	-- First pass: mark gate candidates near LAN.
	for i, pos in ipairs(line) do
		if isNearLan(pos) then
			gateIndices[i] = true
		end
	end

	-- Second pass: fill remaining gaps at interval.
	local sinceLastGap = 0
	for i = 1, #line do
		sinceLastGap = sinceLastGap + 1
		if gateIndices[i] then
			sinceLastGap = 0
		elseif sinceLastGap >= gapInterval then
			gateIndices[i] = true
			sinceLastGap   = 0
		end
	end

	-- Guarantee: at least 1 gap per 5 tiles.
	if next(gateIndices) == nil and #line >= 5 then
		local mid = math.ceil(#line / 2)
		gateIndices[mid] = true
	end

	-- Place wall tiles (Rocky) and skip gates (passable).
	local tilesUsed = 0
	local wallTiles = {}

	for i, pos in ipairs(line) do
		local key = coordKey(pos.x, pos.y)
		if not gateIndices[i] then
			tiles[pos.y][pos.x].terrain = "Rocky"
			usedSet[key] = true
			tilesUsed    = tilesUsed + 1
			table.insert(wallTiles, pos)
		end
		-- Gate tiles are left as floor terrain (passable).
	end

	-- Export wall data for Moat placement.
	if opts then
		opts._fortResult = {
			wallTiles = wallTiles,
			wallLine  = line,
			wallDir   = dir,
		}
	end

	return tilesUsed
end

----- 10. Moat --------------------------------
--- Shallow Water channel parallel to a Fortification wall.
--- Bridge (Wooden Floor) where the moat is adjacent to LAN tiles.
--- Requires opts.wallLine and opts.wallDir from a prior Fortification.
local function placeMoat(candidates, minSize, maxSize, minCluster,
		opts, rng, tiles, w, h, regionId, usedSet)
	local wallLine = opts and opts.wallLine
	local wallDir  = opts and opts.wallDir
	if not wallLine or #wallLine == 0 then return 0 end

	-- Pick one side of the wall (perpendicular).
	local perpDirs
	if wallDir.x == 0 then
		perpDirs = { { x = 1, y = 0 }, { x = -1, y = 0 } }
	else
		perpDirs = { { x = 0, y = 1 }, { x = 0, y = -1 } }
	end

	-- Prefer the side facing away from PD (deployment).
	local pdCount1, pdCount2 = 0, 0
	for _, pos in ipairs(wallLine) do
		local nx1, ny1 = pos.x + perpDirs[1].x, pos.y + perpDirs[1].y
		if isInBounds(nx1, ny1, w, h)
			and tiles[ny1][nx1].marker == "PD" then
			pdCount1 = pdCount1 + 1
		end
		local nx2, ny2 = pos.x + perpDirs[2].x, pos.y + perpDirs[2].y
		if isInBounds(nx2, ny2, w, h)
			and tiles[ny2][nx2].marker == "PD" then
			pdCount2 = pdCount2 + 1
		end
	end
	-- Fewer PD tiles = away from deployment.
	local side
	if pdCount1 <= pdCount2 then
		side = perpDirs[1]
	else
		side = perpDirs[2]
	end

	-- Place Shallow Water parallel to each wall-line tile.
	local tilesUsed = 0
	for _, pos in ipairs(wallLine) do
		local nx, ny = pos.x + side.x, pos.y + side.y
		if isInBounds(nx, ny, w, h) then
			local nKey  = coordKey(nx, ny)
			local nTile = tiles[ny][nx]
			if not nTile.protected and not usedSet[nKey]
				and nTile.regionId == regionId then
				-- Bridge at LAN-adjacent crossings.
				local nearLan = false
				for _, d in ipairs(CARDINAL) do
					local lx, ly = nx + d.x, ny + d.y
					if isInBounds(lx, ly, w, h)
						and tiles[ly][lx].marker == "LAN" then
						nearLan = true
						break
					end
				end

				if nearLan then
					nTile.terrain = "Wooden Floor"
				else
					nTile.terrain = "Shallow Water"
				end
				usedSet[nKey] = true
				tilesUsed     = tilesUsed + 1
			end
		end
	end

	return tilesUsed
end

----- 11. Ruin Structure ----------------------
--- Broken rectangular building: Rocky + Cracked Ground with 30-50% gaps.
local function placeRuinStructure(candidates, minSize, maxSize, minCluster,
		opts, rng, tiles, w, h, regionId, usedSet)
	-- Try up to 3 seeds for rectangular placement.
	for _ = 1, 3 do
		local seed = pickSeed(candidates, usedSet, rng)
		if not seed then return 0 end

		local bw = rng:NextInteger(3, 4)  -- width  3–4
		local bh = rng:NextInteger(3, 5)  -- height 3–5

		-- Build full rectangle.
		local fullRect = {}
		local ok = true
		for dy = 0, bh - 1 do
			for dx = 0, bw - 1 do
				local tx, ty = seed.x + dx, seed.y + dy
				if not isInBounds(tx, ty, w, h) then ok = false; break end
				local key  = coordKey(tx, ty)
				local tile = tiles[ty][tx]
				if tile.protected or usedSet[key]
					or tile.regionId ~= regionId then
					ok = false; break
				end
				table.insert(fullRect, { x = tx, y = ty })
			end
			if not ok then break end
		end

		if not ok or #fullRect < minCluster then continue end

		-- Remove 30-50% of tiles randomly (gaps = broken look).
		local removeFraction = 0.30 + rng:NextNumber() * 0.20
		local removeCount    = math.floor(#fullRect * removeFraction + 0.5)
		removeCount = math.min(removeCount, #fullRect - minCluster)

		shuffleArray(fullRect, rng)
		local removed = {}
		for i = 1, removeCount do
			removed[i] = true
		end

		-- Place remaining tiles: 70-80% Rocky, 20-30% Cracked Ground.
		local tilesUsed = 0
		for i, pos in ipairs(fullRect) do
			if not removed[i] then
				local key = coordKey(pos.x, pos.y)
				if rng:NextNumber() < 0.25 then
					tiles[pos.y][pos.x].terrain = "Cracked Ground"
				else
					tiles[pos.y][pos.x].terrain = "Rocky"
				end
				usedSet[key] = true
				tilesUsed    = tilesUsed + 1
			end
			-- Removed tiles stay as floor terrain (gaps).
		end

		return tilesUsed
	end

	return 0
end

----- 12. Ridge / Cliff -----------------------
--- Linear Rocky formation near ADV tiles. ElevationPass will make
--- these tall because Rocky → Stone tag → mid-to-max elevation.
local function placeRidge(candidates, minSize, maxSize, minCluster,
		opts, rng, tiles, w, h, regionId, usedSet)
	-- Ridge requires ADV tiles in the region.
	local advTiles = opts and opts.advTiles
	if not advTiles or #advTiles == 0 then return 0 end

	-- Pick a seed near an ADV tile.
	local seed    = advTiles[rng:NextInteger(1, #advTiles)]
	local seedKey = coordKey(seed.x, seed.y)

	-- If seed is protected or used, try a cardinal neighbor.
	if usedSet[seedKey] or tiles[seed.y][seed.x].protected then
		local found = false
		for _, dir in ipairs(CARDINAL) do
			local nx, ny = seed.x + dir.x, seed.y + dir.y
			if isInBounds(nx, ny, w, h) then
				local nKey  = coordKey(nx, ny)
				local nTile = tiles[ny][nx]
				if not nTile.protected and not usedSet[nKey]
					and nTile.regionId == regionId then
					seed  = { x = nx, y = ny }
					found = true
					break
				end
			end
		end
		if not found then return 0 end
	end

	-- Grow a linear formation through/near the ADV tiles.
	local targetLen   = rng:NextInteger(
		math.max(3, minSize), math.max(3, maxSize))
	local ridgeWidth  = rng:NextInteger(1, 2)
	local blob, blobSet = growLinearBlob(
		seed, targetLen, ridgeWidth,
		rng, tiles, w, h, regionId, usedSet)

	if #blob < minCluster then return 0 end

	-- Assign Rocky terrain to all ridge tiles.
	local tilesUsed = 0
	for _, pos in ipairs(blob) do
		tiles[pos.y][pos.x].terrain = "Rocky"
		usedSet[coordKey(pos.x, pos.y)] = true
		tilesUsed = tilesUsed + 1
	end

	return tilesUsed
end

--------------------------------------------------
-- BRIDGE / PASS REPAIR (type 13)
-- Safety net: ensures no LAN tile has impassable terrain.
-- Runs once at the end of FeaturePass.Run().
--------------------------------------------------

local WATER_TERRAINS = {
	["Shallow Water"] = true,
	["Deep Water"]    = true,
	["Swamp"]         = true,
}
local LAVA_TERRAINS = {
	["Molten"] = true,
}
local IMPASSABLE_FIX = {
	["Deep Water"] = true,
	["Molten"]     = true,
	["Quicksand"]  = true,
}

local function repairBridgePass(tiles, w, h)
	local repaired = 0
	for y = 1, h do
		for x = 1, w do
			local tile = tiles[y][x]
			if tile.marker == "LAN" then
				local terrain = tile.terrain
				if WATER_TERRAINS[terrain] then
					tile.terrain = "Wooden Floor"
					repaired     = repaired + 1
				elseif LAVA_TERRAINS[terrain] then
					tile.terrain = "Rocky"
					repaired     = repaired + 1
				elseif IMPASSABLE_FIX[terrain] then
					tile.terrain = "Clear"
					repaired     = repaired + 1
				end
			end
		end
	end
	if repaired > 0 then
		print(string.format(
			"[FeaturePass] Bridge/Pass repair: fixed %d LAN tile(s).", repaired))
	end
end

--------------------------------------------------
-- FEATURE DISPATCHER
--------------------------------------------------

local FEATURE_PLACERS = {
	WaterBody        = placeWaterBody,
	RockFormation    = placeRockFormation,
	LavaChannel      = placeLavaChannel,
	FrozenLake       = placeFrozenLake,
	Wetland          = placeWetland,
	SandyExpanse     = placeSandyExpanse,
	CorruptionSpread = placeCorruptionSpread,
	Structure        = placeStructure,
	Fortification    = placeFortification,
	Moat             = placeMoat,
	RuinStructure    = placeRuinStructure,
	Ridge            = placeRidge,
}

--- Place a single feature instance.
--- Returns number of tiles consumed.
local function placeFeature(featureType, candidates, minSize, maxSize, minCluster, opts, rng, tiles, w, h, regionId, usedSet)
	local placer = FEATURE_PLACERS[featureType]
	if not placer then return 0 end
	return placer(candidates, minSize, maxSize, minCluster, opts, rng, tiles, w, h, regionId, usedSet)
end

--------------------------------------------------
-- RUN
--------------------------------------------------

--- Place terrain features in all regions.
--- @param mapState table — the shared pipeline state
--- @return mapState (modified in-place)
function FeaturePass.Run(mapState)
	local tiles         = mapState.tiles
	local w             = mapState.width
	local h             = mapState.height
	local rng           = mapState.rng.featureRng
	local biomeId       = mapState.biomeId
	local regionTypeMap = mapState.regionTypeMap
	local regions       = mapState.regionResult.Regions

	----------------------------------------------------
	-- Build per-region tile lists (deterministic y,x scan).
	----------------------------------------------------
	local regionTilesMap = {}   -- regionId → array of {x,y}
	local regionWatMap   = {}   -- regionId → array of {x,y}
	local regionAdvMap   = {}   -- regionId → array of {x,y} (ADV marker tiles)
	local regionHzdMap   = {}   -- regionId → array of {x,y} (HZD marker tiles)
	local regionBlkMap   = {}   -- regionId → array of {x,y} (BLK marker tiles)
	local regionNeuMap   = {}   -- regionId → array of {x,y} (NEU marker tiles)

	for _, region in ipairs(regions) do
		regionTilesMap[region.Id] = {}
		regionWatMap[region.Id]   = {}
		regionAdvMap[region.Id]   = {}
		regionHzdMap[region.Id]   = {}
		regionBlkMap[region.Id]   = {}
		regionNeuMap[region.Id]   = {}
	end

	local ops = 0
	for y = 1, h do
		for x = 1, w do
			local tile = tiles[y][x]
			local rid  = tile.regionId
			if rid and regionTilesMap[rid] then
				-- ADV/HZD/BLK/NEU tiles are not protected; collect separately.
				if tile.marker == "ADV" then
					table.insert(regionAdvMap[rid], { x = x, y = y })
				elseif tile.marker == "HZD" then
					table.insert(regionHzdMap[rid], { x = x, y = y })
				elseif tile.marker == "BLK" then
					table.insert(regionBlkMap[rid], { x = x, y = y })
				elseif tile.marker == "NEU" then
					table.insert(regionNeuMap[rid], { x = x, y = y })
				end
				if not tile.protected then
					table.insert(regionTilesMap[rid], { x = x, y = y })
					if tile.marker == "WAT" then
						table.insert(regionWatMap[rid], { x = x, y = y })
					end
				end
			end
			ops = ops + 1
			if ops % YIELD_INTERVAL == 0 then task.wait() end
		end
	end

	----------------------------------------------------
	-- Process each region in array order (deterministic).
	----------------------------------------------------
	for _, region in ipairs(regions) do
		local rid        = region.Id
		local regionType = regionTypeMap[rid]
		local available  = regionTilesMap[rid]
		local watTiles   = regionWatMap[rid]

		if #available == 0 then continue end

		-- Feature budget: 40-60% of non-protected tiles.
		local fillFraction = 0.40 + rng:NextNumber() * 0.20
		local budget       = math.floor(#available * fillFraction)
		local usedCount    = 0
		local usedSet      = {}  -- coordKey → true

		--------------------------------------------
		-- Phase 1: WAT marker features (Round 2).
		--------------------------------------------
		if #watTiles >= 5 then
			local watFeatureType = WAT_BIOME_FEATURE[biomeId]
			if watFeatureType then
				local defaults = WAT_FEATURE_DEFAULTS[watFeatureType]
				if defaults then
					-- Clamp max size to remaining budget.
					local adjMax = math.min(defaults.maxSize, budget - usedCount)
					if adjMax >= defaults.minCluster then
						-- For lava channel WAT, let rng decide linear vs pool.
						local watOpts = nil
						if watFeatureType == "LavaChannel" then
							watOpts = { linear = rng:NextNumber() < 0.5 }
						end

						local placed = placeFeature(
							watFeatureType, watTiles,
							defaults.minSize, adjMax,
							defaults.minCluster, watOpts,
							rng, tiles, w, h, rid, usedSet)
						usedCount = usedCount + placed
					end
				end
			end
		end

		--------------------------------------------
		-- Phase 2: Region-type features.
		--------------------------------------------
		local featureDefs  = REGION_FEATURES[regionType] or {}
		local regionCtx    = {}   -- cross-feature data (e.g. Fortification → Moat)

		for _, fDef in ipairs(featureDefs) do
			if usedCount >= budget then break end

			-- Dependency check: skip if required feature was not placed.
			if fDef.depends == "Fortification" and not regionCtx.fortResult then
				continue
			end

			-- Ridge requires ADV tiles in this region.
			local advTiles = regionAdvMap[rid]
			if fDef.type == "Ridge" and (not advTiles or #advTiles == 0) then
				continue
			end

			local count = rng:NextInteger(fDef.minCount, fDef.maxCount)
			for _ = 1, count do
				if usedCount >= budget then break end

				-- Clamp max size to remaining budget.
				local adjMax = math.min(fDef.maxSize, budget - usedCount)
				if adjMax < fDef.minCluster then break end

				local opts = nil
				if fDef.linear then
					opts = { linear = true }
				end

				-- Round 3: per-type opts setup.
				if fDef.type == "Structure" then
					opts = opts or {}
					opts.regionType = regionType
				elseif fDef.type == "Fortification" then
					opts = opts or {}
				elseif fDef.type == "Moat" then
					opts = opts or {}
				-- Pass wall data from Fortification.
					opts.wallLine  = regionCtx.fortResult.wallLine
					opts.wallDir   = regionCtx.fortResult.wallDir
				elseif fDef.type == "Ridge" then
					opts = opts or {}
					opts.advTiles = advTiles
				end

				local placed = placeFeature(
					fDef.type, available,
					fDef.minSize, adjMax,
					fDef.minCluster, opts,
					rng, tiles, w, h, rid, usedSet)
				usedCount = usedCount + placed

				-- Capture Fortification output for Moat.
				if fDef.type == "Fortification" and opts
					and opts._fortResult then
					regionCtx.fortResult = opts._fortResult
				end
			end
		end

		ops = ops + 1
		if ops % YIELD_INTERVAL == 0 then task.wait() end
	end

	----------------------------------------------------
	-- Phase 2b: ADV/HZD/BLK/NEU marker features (Round 5).
	-- Runs after Phase 2 so region features have priority,
	-- but before Phase 4 (cross-region) so paths route
	-- around marker-placed terrain.
	----------------------------------------------------

	--- BFS flood-fill to find connected clusters of marker tiles.
	--- Returns array of clusters, each = array of {x,y}.
	local function findMarkerClustersOpt(markerTiles)
		local tileSet  = {}
		for _, pos in ipairs(markerTiles) do
			tileSet[coordKey(pos.x, pos.y)] = pos
		end
		local visited  = {}
		local clusters = {}
		for _, pos in ipairs(markerTiles) do
			local key = coordKey(pos.x, pos.y)
			if not visited[key] then
				local cluster = {}
				local queue   = { pos }
				local qHead   = 1
				visited[key]  = true
				while qHead <= #queue do
					local cur = queue[qHead]
					qHead     = qHead + 1
					table.insert(cluster, cur)
					for _, dir in ipairs(CARDINAL) do
						local nx, ny = cur.x + dir.x, cur.y + dir.y
						local nKey   = coordKey(nx, ny)
						if not visited[nKey] and tileSet[nKey] then
							visited[nKey] = true
							table.insert(queue, tileSet[nKey])
						end
					end
				end
				table.insert(clusters, cluster)
			end
		end
		return clusters
	end

	local phase2bTotal = 0

	for _, region in ipairs(regions) do
		local rid = region.Id

		-- Shared usedSet for Phase 2b within this region.
		-- We do NOT share usedSet with Phase 1/2 because those
		-- already ran; instead, check tile state directly.
		local usedSet2b = {}

		-- Helper: is a tile already featured or protected?
		local function isTileAvailable(x, y)
			local key  = coordKey(x, y)
			if usedSet2b[key] then return false end
			local tile = tiles[y][x]
			if tile.protected then return false end
			return true
		end

		--------------------------------------------
		-- ADV Marker Trigger: Rocky terrain for clusters ≥ 3.
		--------------------------------------------
		local advTiles   = regionAdvMap[rid]
		if advTiles and #advTiles >= 3 then
			local advClusters = findMarkerClustersOpt(advTiles)
			for _, cluster in ipairs(advClusters) do
				if #cluster >= 3 then
					local advPlaced = 0
					for _, pos in ipairs(cluster) do
						if isTileAvailable(pos.x, pos.y) then
							local tile = tiles[pos.y][pos.x]
							-- Only set Rocky if not already Rocky
							-- (Ridge from Round 3 may have set it).
							if tile.terrain ~= "Rocky" then
								tile.terrain = "Rocky"
							end
							usedSet2b[coordKey(pos.x, pos.y)] = true
							advPlaced = advPlaced + 1
						end
					end
					if advPlaced > 0 then
						phase2bTotal = phase2bTotal + advPlaced
					end
				end
			end
		end

		--------------------------------------------
		-- HZD Marker Trigger: Biome-appropriate hazard for clusters ≥ 3.
		--------------------------------------------
		local hzdTiles = regionHzdMap[rid]
		if hzdTiles and #hzdTiles >= 3 then
			local hazardTerrain = HZD_BIOME_HAZARD[biomeId]
			if hazardTerrain then
				local hzdClusters = findMarkerClustersOpt(hzdTiles)
				for _, cluster in ipairs(hzdClusters) do
					if #cluster >= 3 then
						local hzdPlaced = 0

						if hazardTerrain == "Molten" then
							-- Volcano HZD: 2-4 Molten tiles, then Rocky buffer.
							local moltenCount = rng:NextInteger(2, math.min(4, #cluster))
							local moltenSet   = {}
							shuffleArray(cluster, rng)
							for ci = 1, moltenCount do
								local pos = cluster[ci]
								if isTileAvailable(pos.x, pos.y) then
									tiles[pos.y][pos.x].terrain = "Molten"
									local key = coordKey(pos.x, pos.y)
									usedSet2b[key] = true
									moltenSet[key] = true
									hzdPlaced = hzdPlaced + 1
								end
							end
							-- Rocky buffer around Molten (reuses Lava Channel safety logic).
							for key in pairs(moltenSet) do
								local my = math.floor(key / 100000)
								local mx = key - my * 100000
								for _, dir in ipairs(CARDINAL) do
									local bx, by = mx + dir.x, my + dir.y
									if isInBounds(bx, by, w, h) then
										local bKey  = coordKey(bx, by)
										local bTile = tiles[by][bx]
										if not moltenSet[bKey]
											and not bTile.protected
											and bTile.terrain ~= "Rocky"
											and bTile.terrain ~= "Sand"
											and bTile.terrain ~= "Molten" then
											bTile.terrain    = "Rocky"
											usedSet2b[bKey]  = true
											hzdPlaced        = hzdPlaced + 1
										end
									end
								end
							end

						elseif hazardTerrain == "Sand" then
							-- Desert HZD: Sand cluster, with 1-2 Quicksand if ≥ 5 tiles.
							local sandSet = {}
							for _, pos in ipairs(cluster) do
								if isTileAvailable(pos.x, pos.y) then
									tiles[pos.y][pos.x].terrain = "Sand"
									local key = coordKey(pos.x, pos.y)
									usedSet2b[key] = true
									sandSet[key]   = true
									hzdPlaced      = hzdPlaced + 1
								end
							end
							-- Quicksand: 1-2 tiles if cluster ≥ 5, needs all 4 Sand neighbors.
							if #cluster >= 5 then
								local qsCount   = rng:NextInteger(1, 2)
								local qsEligible = {}
								for _, pos in ipairs(cluster) do
									if sandSet[coordKey(pos.x, pos.y)]
										and allCardinalInBlob(pos.x, pos.y, w, h, sandSet) then
										table.insert(qsEligible, pos)
									end
								end
								if #qsEligible > 0 then
									shuffleArray(qsEligible, rng)
									for qi = 1, math.min(qsCount, #qsEligible) do
										local pos = qsEligible[qi]
										-- Re-verify all 4 neighbors are Sand.
										local allSand = true
										for _, dir in ipairs(CARDINAL) do
											local nx, ny = pos.x + dir.x, pos.y + dir.y
											if not isInBounds(nx, ny, w, h)
												or tiles[ny][nx].terrain ~= "Sand" then
												allSand = false
												break
											end
										end
										if allSand then
											tiles[pos.y][pos.x].terrain = "Quicksand"
										end
									end
								end
							end
						else
							-- General case: set all cluster tiles to hazard terrain.
							for _, pos in ipairs(cluster) do
								if isTileAvailable(pos.x, pos.y) then
									tiles[pos.y][pos.x].terrain = hazardTerrain
									usedSet2b[coordKey(pos.x, pos.y)] = true
									hzdPlaced = hzdPlaced + 1
								end
							end
						end

						if hzdPlaced > 0 then
							phase2bTotal = phase2bTotal + hzdPlaced
						end
					end
				end
			end
		end

		--------------------------------------------
		-- BLK Marker Trigger: 40-60% Rocky with gaps for clusters ≥ 3.
		--------------------------------------------
		local blkTiles = regionBlkMap[rid]
		if blkTiles and #blkTiles >= 3 then
			local blkClusters = findMarkerClustersOpt(blkTiles)
			for _, cluster in ipairs(blkClusters) do
				if #cluster >= 3 then
					local blkFraction = 0.40 + rng:NextNumber() * 0.20
					local blkTarget   = math.floor(#cluster * blkFraction + 0.5)
					blkTarget = math.max(1, blkTarget)
					shuffleArray(cluster, rng)
					local blkPlaced = 0
					for _, pos in ipairs(cluster) do
						if blkPlaced >= blkTarget then break end
						if isTileAvailable(pos.x, pos.y) then
							tiles[pos.y][pos.x].terrain = "Rocky"
							usedSet2b[coordKey(pos.x, pos.y)] = true
							blkPlaced = blkPlaced + 1
						end
					end
					phase2bTotal = phase2bTotal + blkPlaced
				end
			end
		end

		--------------------------------------------
		-- NEU Marker Trigger: 0-2 random features for clusters ≥ 8.
		--------------------------------------------
		local neuTiles = regionNeuMap[rid]
		if neuTiles and #neuTiles >= 8 then
			local neuPool = NEU_BIOME_POOL[biomeId]
			if neuPool and #neuPool > 0 then
				local neuClusters = findMarkerClustersOpt(neuTiles)
				for _, cluster in ipairs(neuClusters) do
					if #cluster >= 8 then
						-- Budget: 40-60% of cluster.
						local neuFrac   = 0.40 + rng:NextNumber() * 0.20
						local neuBudget = math.floor(#cluster * neuFrac)
						local neuUsed   = 0

						-- Roll 0-2 features.
						local featureCount = rng:NextInteger(0, 2)
						for _ = 1, featureCount do
							if neuUsed >= neuBudget then break end

							-- Weighted selection from pool.
							local totalW = 0
							for _, entry in ipairs(neuPool) do
								totalW = totalW + entry.weight
							end
							-- Add "nothing" chance (30% base).
							local nothingW = totalW * 0.43  -- ~30% of total including nothing
							totalW = totalW + nothingW

							local roll = rng:NextNumber() * totalW
							local acc  = 0
							local selectedType = nil
							for _, entry in ipairs(neuPool) do
								acc = acc + entry.weight
								if roll <= acc then
									selectedType = entry.type
									break
								end
							end

							if selectedType then
								-- Build a usedSet for this NEU feature placement
								-- combining our 2b used tiles.
								local neuUsedSet = {}
								for k, v in pairs(usedSet2b) do
									neuUsedSet[k] = v
								end

								local adjMax = math.min(
									NEU_FEATURE_DEFAULTS.maxSize,
									neuBudget - neuUsed)
								if adjMax >= NEU_FEATURE_DEFAULTS.minCluster then
									-- Ridge in NEU requires ADV tiles (likely none).
									local neuOpts = nil
									if selectedType == "Ridge" then
										local advT = regionAdvMap[rid]
										if not advT or #advT == 0 then
											-- Skip Ridge in NEU — no ADV tiles.
											selectedType = nil
										else
											neuOpts = { advTiles = advT }
										end
									elseif selectedType == "LavaChannel" then
										neuOpts = { linear = rng:NextNumber() < 0.5 }
									end

									if selectedType then
										local placed = placeFeature(
											selectedType, cluster,
											NEU_FEATURE_DEFAULTS.minSize,
											adjMax,
											NEU_FEATURE_DEFAULTS.minCluster,
											neuOpts,
											rng, tiles, w, h, rid, neuUsedSet)
										neuUsed = neuUsed + placed
										phase2bTotal = phase2bTotal + placed
										-- Merge back into usedSet2b.
										for k, v in pairs(neuUsedSet) do
											usedSet2b[k] = v
										end
									end
								end
							end
						end
					end
				end
			end
		end

		ops = ops + 1
		if ops % YIELD_INTERVAL == 0 then task.wait() end
	end

	if phase2bTotal > 0 then
		print(string.format(
			"[FeaturePass] Phase 2b: Placed %d marker-triggered tile(s) (ADV/HZD/BLK/NEU).",
			phase2bTotal))
	end

	----------------------------------------------------
	-- Build cross-region context for Phases 4 & 5.
	----------------------------------------------------

	-- Region adjacency: regionId → { neighborId → true }.
	local adjMap = {}
	for _, region in ipairs(regions) do
		adjMap[region.Id] = {}
	end
	for y = 1, h do
		for x = 1, w do
			local rid = tiles[y][x].regionId
			if rid and adjMap[rid] then
				for _, d in ipairs(CARDINAL) do
					local nx, ny = x + d.x, y + d.y
					if isInBounds(nx, ny, w, h) then
						local nrid = tiles[ny][nx].regionId
						if nrid and nrid ~= rid and adjMap[nrid] then
							adjMap[rid][nrid] = true
						end
					end
				end
			end
		end
	end

	-- Region centroids (nearest non-protected tile to average position).
	local centroids = {}
	for _, region in ipairs(regions) do
		local rid = region.Id
		local rt  = regionTilesMap[rid]
		if rt and #rt > 0 then
			local sx, sy = 0, 0
			for _, p in ipairs(rt) do sx = sx + p.x; sy = sy + p.y end
			local cx = math.floor(sx / #rt + 0.5)
			local cy = math.floor(sy / #rt + 0.5)
			local best, bd = rt[1], math.huge
			for _, p in ipairs(rt) do
				local d2 = math.abs(p.x - cx) + math.abs(p.y - cy)
				if d2 < bd then bd = d2; best = p end
			end
			centroids[rid] = best
		end
	end

	----------------------------------------------------
	-- Phase 4: Cross-region features (Road, River, Cave Corridor).
	-- Runs after Phase 1+2 so paths route around placed features.
	----------------------------------------------------

	-- Biome gating tables.
	local ROAD_BIOMES   = { Plains = true, Forest = true, Ruins = true, Castle = true }
	local ROAD_REGIONS  = { Farmland = true, Village = true, ["Castle Courtyard"] = true }
	local RIVER_BIOMES  = { Plains = true, Forest = true, Swamp = true }

	-- Terrains that cross-region placement must not overwrite.
	local NO_OVERWRITE = {
		["Deep Water"]     = true,
		["Molten"]         = true,
		["Metal"]          = true,
		["Wooden Floor"]   = true,
		["Magic Circle"]   = true,
		["Tainted Ground"] = true,
		["Quicksand"]      = true,
		["Ice"]            = true,
	}

	-- 4a. Road / Path -------------------------------------------------
	if ROAD_BIOMES[biomeId] then
		-- Identify primary road regions.
		local primaryRids = {}
		for _, region in ipairs(regions) do
			if ROAD_REGIONS[regionTypeMap[region.Id]] then
				table.insert(primaryRids, region.Id)
			end
		end

		if #primaryRids > 0 then
			-- Expand to include regions adjacent to primary road regions.
			local roadEligible = {}
			for _, rid in ipairs(primaryRids) do
				roadEligible[rid] = true
				for nrid in pairs(adjMap[rid] or {}) do
					roadEligible[nrid] = true
				end
			end

			-- Road cost function.
			local function roadCost(tile)
				if tile.protected then return 100 end
				local t = tile.terrain
				if t == "Clear" or t == "Grassland" or t == "Clover Field" then
					return 1
				end
				if t == "Rocky" or t == "Cracked Ground" then return 1 end
				if t == "Mud" or t == "Sand" then return 2 end
				if t == "Shallow Water" then return 10 end
				if t == "Swamp" then return 5 end
				if t == "Metal" or t == "Wooden Floor" then return 3 end
				if t == "Ice" then return 3 end
				if t == "Deep Water" or t == "Molten" or t == "Quicksand" then
					return 0  -- impassable
				end
				return 2
			end

			-- Build sorted list of eligible region IDs.
			local ridList = {}
			for rid in pairs(roadEligible) do
				table.insert(ridList, rid)
			end
			table.sort(ridList)

			-- Connect adjacent eligible pairs (deterministic order).
			local connPairs = {}
			for _, ridA in ipairs(ridList) do
				local nbrs = {}
				for nrid in pairs(adjMap[ridA] or {}) do
					if roadEligible[nrid] then
						table.insert(nbrs, nrid)
					end
				end
				table.sort(nbrs)
				for _, ridB in ipairs(nbrs) do
					local pk = (ridA < ridB)
						and (ridA .. ":" .. ridB)
						or  (ridB .. ":" .. ridA)
					if not connPairs[pk] then
						connPairs[pk] = true
						local cA = centroids[ridA]
						local cB = centroids[ridB]
						if cA and cB then
							local path = tracePath(tiles, w, h,
								cA.x, cA.y, cB.x, cB.y, roadCost)
							if path and #path >= 2 then
								-- Road tiles → Clear.
								for _, pos in ipairs(path) do
									local tile = tiles[pos.y][pos.x]
									if not tile.protected
										and not NO_OVERWRITE[tile.terrain] then
										tile.terrain = "Clear"
									end
								end
								-- Shoulder tiles (1 wide each side) → Grassland.
								for pi = 1, #path - 1 do
									local cur = path[pi]
									local nxt = path[pi + 1]
									local dx  = nxt.x - cur.x
									local dy  = nxt.y - cur.y
									local perpDirs
									if dx == 0 then
										perpDirs = {
											{ x = 1, y = 0 },
											{ x = -1, y = 0 },
										}
									else
										perpDirs = {
											{ x = 0, y = 1 },
											{ x = 0, y = -1 },
										}
									end
									for _, pd in ipairs(perpDirs) do
										local sx, sy = cur.x + pd.x, cur.y + pd.y
										if isInBounds(sx, sy, w, h) then
											local sTile = tiles[sy][sx]
											if not sTile.protected
												and not NO_OVERWRITE[sTile.terrain]
												and sTile.terrain ~= "Clear"
												and sTile.terrain ~= "Grassland" then
												sTile.terrain = "Grassland"
											end
										end
									end
								end
							end
						end
					end
				end
			end

			local roadCount = 0
			for _ in pairs(connPairs) do roadCount = roadCount + 1 end
			if roadCount > 0 then
				print(string.format(
					"[FeaturePass] Phase 4a: Placed %d road(s).", roadCount))
			end
		end
	end

	-- 4b. River -------------------------------------------------------
	if RIVER_BIOMES[biomeId] then
		local riverbankRids = {}
		for _, region in ipairs(regions) do
			if regionTypeMap[region.Id] == "Riverbank" then
				table.insert(riverbankRids, region.Id)
			end
		end

		if #riverbankRids > 0 then
			-- River cost function (prefers low/wet terrain).
			local function riverCost(tile)
				if tile.protected then return 100 end
				local t = tile.terrain
				if t == "Shallow Water" or t == "Deep Water" then return 0.5 end
				if t == "Mud" or t == "Swamp" then return 1 end
				if t == "Grassland" or t == "Clover Field"
					or t == "Clear" then return 2 end
				if t == "Sand" then return 2 end
				if t == "Rocky" or t == "Cracked Ground" then return 3 end
				if t == "Molten" or t == "Metal"
					or t == "Wooden Floor" then return 0 end
				if t == "Magic Circle" or t == "Tainted Ground" then
					return 0
				end
				return 3
			end

			-- Pick axis for river flow (N↔S or W↔E).
			local edgeAxis = rng:NextInteger(1, 2)

			-- Find Riverbank tiles closest to each edge.
			local function findEdgeTile(targetEdge, isMin, rids)
				local best, bd = nil, math.huge
				for _, rid in ipairs(rids) do
					local rt = regionTilesMap[rid]
					if rt then
						for _, p in ipairs(rt) do
							local val = (edgeAxis == 1) and p.y or p.x
							local target = isMin and 1 or
								((edgeAxis == 1) and h or w)
							local d = math.abs(val - target)
							if d < bd or (d == bd and best
								and coordKey(p.x, p.y) < coordKey(best.x, best.y)) then
								bd   = d
								best = p
							end
						end
					end
				end
				return best
			end

			local startTile = findEdgeTile(nil, true, riverbankRids)
			local endTile   = findEdgeTile(nil, false, riverbankRids)

			if startTile and endTile
				and (startTile.x ~= endTile.x
					or startTile.y ~= endTile.y) then

				local riverPath = tracePath(tiles, w, h,
					startTile.x, startTile.y,
					endTile.x, endTile.y, riverCost)

				if riverPath and #riverPath >= 8 then
					-- Build channel tile set (centerline + optional widening).
					local riverWidth = rng:NextInteger(1, 2)
					local channelSet   = {}
					local channelTiles = {}

					for _, pos in ipairs(riverPath) do
						local key = coordKey(pos.x, pos.y)
						if not channelSet[key] then
							channelSet[key] = true
							table.insert(channelTiles, pos)
						end
					end

					-- Widen by adding perpendicular tiles.
					if riverWidth > 1 then
						for pi = 1, #riverPath - 1 do
							local cur = riverPath[pi]
							local nxt = riverPath[pi + 1]
							local dx  = nxt.x - cur.x
							local dy  = nxt.y - cur.y
							local perpDirs
							if dx == 0 then
								perpDirs = {
									{ x = 1, y = 0 },
									{ x = -1, y = 0 },
								}
							else
								perpDirs = {
									{ x = 0, y = 1 },
									{ x = 0, y = -1 },
								}
							end
							local sideIdx = (pi % 2 == 0) and 1 or 2
							local pd = perpDirs[sideIdx]
							local wx, wy = cur.x + pd.x, cur.y + pd.y
							if isInBounds(wx, wy, w, h) then
								local wk = coordKey(wx, wy)
								if not channelSet[wk] then
									channelSet[wk] = true
									table.insert(channelTiles,
										{ x = wx, y = wy })
								end
							end
						end
					end

					-- Channel → Shallow Water (skip LAN and protected).
					for _, pos in ipairs(channelTiles) do
						local tile = tiles[pos.y][pos.x]
						if not tile.protected
							and tile.marker ~= "LAN"
							and tile.terrain ~= "Shallow Water"
							and tile.terrain ~= "Deep Water" then
							tile.terrain = "Shallow Water"
						end
					end

					-- Banks → Mud (1 tile each side of channel).
					for _, pos in ipairs(channelTiles) do
						for _, dir in ipairs(CARDINAL) do
							local bx, by = pos.x + dir.x, pos.y + dir.y
							if isInBounds(bx, by, w, h) then
								local bKey  = coordKey(bx, by)
								local bTile = tiles[by][bx]
								if not channelSet[bKey]
									and not bTile.protected
									and bTile.terrain ~= "Mud"
									and bTile.terrain ~= "Shallow Water"
									and bTile.terrain ~= "Deep Water"
									and not NO_OVERWRITE[bTile.terrain] then
									bTile.terrain = "Mud"
								end
							end
						end
					end

					print(string.format(
						"[FeaturePass] Phase 4b: Placed river (%d channel tiles).",
						#channelTiles))
				end
			end
		end
	end

	-- 4c. Cave Corridor -----------------------------------------------
	if biomeId == "Cave" then
		local caveRids = {}
		for _, region in ipairs(regions) do
			if regionTypeMap[region.Id] == "Cave Chamber" then
				table.insert(caveRids, region.Id)
			end
		end

		if #caveRids >= 2 then
			-- Corridor cost function (carves through rock).
			local function corridorCost(tile)
				if tile.protected then return 100 end
				local t = tile.terrain
				if t == "Clear" then return 0.5 end
				if t == "Rocky" or t == "Cracked Ground" then return 1 end
				if t == "Grassland" or t == "Mud" then return 1 end
				if t == "Shallow Water" or t == "Deep Water" then
					return 5
				end
				if t == "Molten" then return 0 end
				return 2
			end

			table.sort(caveRids)
			local corridorCount = 0
			local connCave = {}

			for i = 1, #caveRids do
				for j = i + 1, #caveRids do
					local ridA = caveRids[i]
					local ridB = caveRids[j]
					if adjMap[ridA] and adjMap[ridA][ridB] then
						local pk = ridA .. ":" .. ridB
						if not connCave[pk] then
							connCave[pk] = true
							local cA = centroids[ridA]
							local cB = centroids[ridB]
							if cA and cB then
								local path = tracePath(tiles, w, h,
									cA.x, cA.y, cB.x, cB.y,
									corridorCost)
								if path and #path >= 2 then
									-- Corridor width: 2-3.
									local corrWidth = rng:NextInteger(2, 3)

									-- Build widened corridor set.
									local corrSet   = {}
									local corrTiles = {}

									for _, pos in ipairs(path) do
										local key = coordKey(pos.x, pos.y)
										if not corrSet[key] then
											corrSet[key] = true
											table.insert(corrTiles, pos)
										end
									end

									-- Widen perpendicular.
									for pi = 1, #path - 1 do
										local cur = path[pi]
										local nxt = path[pi + 1]
										local dx  = nxt.x - cur.x
										local dy  = nxt.y - cur.y
										local perpDirs
										if dx == 0 then
											perpDirs = {
												{ x = 1, y = 0 },
												{ x = -1, y = 0 },
											}
										else
											perpDirs = {
												{ x = 0, y = 1 },
												{ x = 0, y = -1 },
											}
										end
										for _, pd in ipairs(perpDirs) do
											for step = 1,
												corrWidth - 1 do
												local wx = cur.x + pd.x * step
												local wy = cur.y + pd.y * step
												if isInBounds(wx, wy, w, h) then
													local wk = coordKey(wx, wy)
													if not corrSet[wk] then
														corrSet[wk] = true
														table.insert(corrTiles,
															{ x = wx, y = wy })
													end
												end
											end
										end
									end

									-- Set corridor tiles to Clear.
									for _, pos in ipairs(corrTiles) do
										local tile = tiles[pos.y][pos.x]
										if not tile.protected
											and not NO_OVERWRITE[tile.terrain] then
											tile.terrain = "Clear"
										end
									end
									corridorCount = corridorCount + 1
								end
							end
						end
					end
				end
			end

			if corridorCount > 0 then
				print(string.format(
					"[FeaturePass] Phase 4c: Placed %d cave corridor(s).",
					corridorCount))
			end
		end
	end

	----------------------------------------------------
	-- Phase 5: Forest density (Clover Field scatter).
	-- Replaces 20-40% of Grassland tiles in Forest regions.
	----------------------------------------------------
	if biomeId == "Forest" then
		local cloverTotal = 0
		for _, region in ipairs(regions) do
			if regionTypeMap[region.Id] == "Forest" then
				local rt = regionTilesMap[region.Id]
				if rt then
					local grassTiles = {}
					for _, p in ipairs(rt) do
						local tile = tiles[p.y][p.x]
						if not tile.protected
							and tile.terrain == "Grassland" then
							table.insert(grassTiles, p)
						end
					end
					if #grassTiles > 0 then
						local frac = 0.20 + rng:NextNumber() * 0.20
						local count = math.floor(#grassTiles * frac + 0.5)
						count = math.min(count, #grassTiles)
						shuffleArray(grassTiles, rng)
						for ci = 1, count do
							local p = grassTiles[ci]
							tiles[p.y][p.x].terrain = "Clover Field"
							cloverTotal = cloverTotal + 1
						end
					end
				end
			end
		end
		if cloverTotal > 0 then
			print(string.format(
				"[FeaturePass] Phase 5: Scattered %d Clover Field tile(s).",
				cloverTotal))
		end
	end

	----------------------------------------------------
	-- Phase 3: Bridge / Pass repair (type 13).
	-- Defensive: ensure no LAN tile is impassable.
	----------------------------------------------------
	repairBridgePass(tiles, w, h)

	print(string.format("[FeaturePass] Complete. Processed %d regions.", #regions))
	return mapState
end

return FeaturePass
