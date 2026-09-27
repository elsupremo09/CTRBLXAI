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
	-- Sea-level model (dev-locked 2026-09-24): sea = cfg.seaLevel, floor = cfg.floor.
	-- Water rests at/below sea level; rock rises toward the biome max.
	local bMin  = cfg.min          -- land band minimum
	local bMax  = cfg.max          -- land band maximum (biome peak)
	local sea   = cfg.seaLevel or 5
	local floor = cfg.floor  or 1
	local bMid  = math.floor((sea + bMax) / 2)   -- rocky high ground begins here

	-- Priority 1: Deep — sunken well below sea level (watery pits).
	if hasTag(terrainId, "Deep") then
		return floor, math.max(floor, sea - 2), false
	end

	-- Priority 2: Frozen / Slippery — ice sits right at the waterline.
	if hasAnyTag(terrainId, { "Frozen", "Slippery" }) then
		return math.max(floor, sea - 1), sea, false
	end

	-- Priority 3: Molten (lava) — low channels, just below sea level.
	if hasTag(terrainId, "Molten") then
		return floor + 1, math.max(floor + 1, sea - 1), false
	end

	-- Priority 4: Liquid / Water / Sticky (Shallow Water, Mud, Swamp) — at waterline.
	if hasAnyTag(terrainId, { "Liquid", "Water", "Sticky" }) then
		return math.max(floor, sea - 1), sea, false
	end

	-- Priority 5: Loose (Sand, Quicksand) — low land at/above sea.
	if hasTag(terrainId, "Loose") then
		return sea, bMid, false
	end

	-- Priority 6: Organic (Grassland, Clover, Wooden Floor) — gentle land.
	if hasTag(terrainId, "Organic") then
		return sea, bMid, false
	end

	-- Priority 7: Natural (Clear) — flexible, sea to biome max.
	if hasTag(terrainId, "Natural") then
		return math.max(floor, sea - 1), bMax, false
	end

	-- Priority 8: Stone (Rocky) — elevated terrain, the cliff material.
	if hasTag(terrainId, "Stone") then
		return bMid, bMax, false
	end

	-- Priority 9: Fragile (Cracked Ground) — upper band.
	if hasTag(terrainId, "Fragile") then
		local lowerBound = bMid + 1
		if lowerBound > bMax then lowerBound = bMax end
		return lowerBound, bMax, false
	end

	-- Priority 10: Metal, or Flammable-without-Organic (structures).
	-- Match surrounding neighbor average (deferred to phase 1b).
	if hasTag(terrainId, "Metal") then
		return sea, bMax, true
	end
	if hasTag(terrainId, "Flammable") and not hasTag(terrainId, "Organic") then
		return sea, bMax, true
	end

	-- Priority 11: Corrupted / Arcane / Portal — sea to max.
	if hasAnyTag(terrainId, { "Corrupted", "Arcane", "Portal" }) then
		return sea, bMax, false
	end

	-- Fallback: sea level to biome max.
	return sea, bMax, false
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

	-- Global elevation scale (single-source from MapService via cfg).
	local sea   = cfg.seaLevel or 5
	local floorE = cfg.floor   or 1
	local peakE  = cfg.peak    or 20

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
				floorE, peakE
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
							tile.elevation + noise, floorE, peakE
						)
					elseif hasTag(terrain, "Stone") then
						local noise = rng:NextInteger(0, 1)
						tile.elevation = math.clamp(
							tile.elevation + noise, floorE, peakE
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
	-- ADV tiles gain +advBonus elevation, clamped to global peak.
	-- ADV is NOT in LAN_FAMILY anymore, so Phase 4 will not flatten this.
	---------------------------------------------------------
	local advBonus = cfg.advBonus or 1

	for y = 1, h do
		for x = 1, w do
			local tile = tiles[y][x]
			if tile.marker == "ADV" then
				tile.elevation = math.min(tile.elevation + advBonus, peakE)
			end
		end
	end

	---------------------------------------------------------
	-- PHASE 3: Gradient smoothing (2 passes)
	-- For each non-protected tile, if any cardinal neighbor has an
	-- elevation diff > 6, pull this tile 1 step toward that neighbor.
	-- Threshold raised 3→6 (dev-locked 2026-09-24) so tactical cliffs of
	-- 3–6 levels survive; only extreme >6 spikes soften.
	-- Stone-tagged tiles (Rocky — the cliff material) are exempt from BOTH
	-- up and down pulls, so ridges and cliff faces are fully preserved.
	---------------------------------------------------------
	for _ = 1, 2 do
		for y = 1, h do
			for x = 1, w do
				local tile = tiles[y][x]
				if not tile.protected then
					local isStone = hasTag(tile.terrain, "Stone")
					-- Stone is the cliff material — never smooth it in either direction.
					if not isStone then
						for _, dir in ipairs(CARDINAL) do
							local nx, ny = x + dir.x, y + dir.y
							if isInBounds(nx, ny, w, h) then
								local diff = tile.elevation - tiles[ny][nx].elevation
								if diff > 6 then
									tile.elevation = tile.elevation - 1
								elseif diff < -6 then
									tile.elevation = tile.elevation + 1
								end
							end
						end
						tile.elevation = math.clamp(tile.elevation, floorE, peakE)
					end
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
									tile.elevation, floorE, peakE
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
	--   (a) NOT reachable from the walkable base (≤ sea level) via
	--       ≤1 diff steps, AND
	--   (b) ALL of its cardinal in-bounds neighbors are also
	--       at biome max elevation (interior of a plateau).
	-- Edge tiles and cliff faces (at least one lower neighbor)
	-- are preserved even when unreachable.
	-- Seeds from ≤ sea level (dev-locked 2026-09-24): pits are now at
	-- elevation 1, so the OLD "seed from elevation==1" seeded from pit
	-- bottoms. The walkable ground baseline is sea level and below.
	-- Max 10 iterations to converge.
	---------------------------------------------------------
	for _ = 1, 10 do
		-- BFS flood from all walkable-base tiles (elevation ≤ sea level).
		local reachable = {}
		local queue     = {}
		local qHead     = 1

		for y = 1, h do
			for x = 1, w do
				if tiles[y][x].elevation <= sea then
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

	---------------------------------------------------------
	-- PHASE 6: Corridor connectivity repair (dev-locked 2026-09-24)
	-- After de-flattening (HZD/BLK/ADV excluded from LAN_FAMILY), the
	-- PD→ED walkable path is no longer guaranteed: the traversal route
	-- can cross non-LAN tiles (NEU etc.) or LAN islands sitting at wildly
	-- different elevations, which fractures the ≤1-step connectivity walk
	-- (see validateConnectivity in MapService). This pass guarantees a
	-- traversable corridor WITHOUT flattening the whole combat area:
	--   1. Find one PD→ED path over all passable tiles (LAN-preferred).
	--   2. Forward-grade each tile on that path to within ±1 of its
	--      predecessor, forming a ≤1 ramp end to end.
	-- Only the ~1-tile-wide corridor is touched; every off-corridor tile
	-- keeps its elevation, so cliffs/ridges survive. Prototyped against
	-- T04 (0/400 connectivity failures after repair, ~3 tiles graded/map).
	---------------------------------------------------------
	do
		-- Collect PD sources and ED goals.
		local pdList = {}
		local edSet  = {}
		for y = 1, h do
			for x = 1, w do
				local m = tiles[y][x].marker
				if m == "PD" then
					table.insert(pdList, { x = x, y = y })
				elseif m == "ED" then
					edSet[coordKey(x, y)] = true
				end
			end
		end

		if #pdList > 0 and next(edSet) ~= nil then
			-- Passability helper: terrain must be passable (elevation is what
			-- we are repairing, so it is NOT a constraint on the path search).
			local function pathPassable(tile)
				local tDef = TerrainData.Types[tile.terrain]
				return tDef and tDef.passable ~= false
			end

			-- Multi-source BFS with parent tracking. Neighbor order prefers
			-- LAN tiles (keeps the corridor on the intended lane where possible)
			-- then is coordinate-stable for determinism.
			local parent = {}
			local queue  = {}
			local qHead  = 1
			for _, pos in ipairs(pdList) do
				local key = coordKey(pos.x, pos.y)
				if parent[key] == nil then
					parent[key] = false  -- sentinel root
					table.insert(queue, pos)
				end
			end

			local goalKey = nil
			while qHead <= #queue do
				local cur    = queue[qHead]
				qHead        = qHead + 1
				local curKey = coordKey(cur.x, cur.y)
				if edSet[curKey] then
					goalKey = curKey
					break
				end
				-- Gather in-bounds, passable, unvisited neighbors.
				local nbrs = {}
				for _, dir in ipairs(CARDINAL) do
					local nx, ny = cur.x + dir.x, cur.y + dir.y
					if isInBounds(nx, ny, w, h) then
						local nKey = coordKey(nx, ny)
						if parent[nKey] == nil and pathPassable(tiles[ny][nx]) then
							table.insert(nbrs, { x = nx, y = ny, key = nKey })
						end
					end
				end
				-- LAN-preferred, then stable by (y, x).
				table.sort(nbrs, function(a, b)
					local aLan = tiles[a.y][a.x].marker == "LAN"
					local bLan = tiles[b.y][b.x].marker == "LAN"
					if aLan ~= bLan then return aLan end
					if a.y ~= b.y then return a.y < b.y end
					return a.x < b.x
				end)
				for _, n in ipairs(nbrs) do
					parent[n.key] = cur
					table.insert(queue, { x = n.x, y = n.y })
				end

				ops = ops + 1
				if ops % YIELD_INTERVAL == 0 then task.wait() end
			end

			-- Reconstruct path and forward-grade it to a ≤1 ramp.
			if goalKey then
				local path = {}
				local ck   = goalKey
				while ck do
					local node = parent[ck]
					-- decode key back to coords
					local px = ck % 100000
					local py = (ck - px) / 100000
					table.insert(path, { x = px, y = py })
					if node == false or node == nil then break end
					ck = coordKey(node.x, node.y)
				end
				-- path is goal→...→PD; walk from PD end forward.
				for i = #path - 1, 1, -1 do
					local prev = path[i + 1]
					local cur  = path[i]
					local pe   = tiles[prev.y][prev.x].elevation
					local ce   = tiles[cur.y][cur.x].elevation
					if ce > pe + 1 then
						tiles[cur.y][cur.x].elevation = math.clamp(pe + 1, floorE, peakE)
					elseif ce < pe - 1 then
						tiles[cur.y][cur.x].elevation = math.clamp(pe - 1, floorE, peakE)
					end
				end
			end
		end
	end

	return mapState
end

return ElevationPass
