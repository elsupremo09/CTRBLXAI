-- ElevationPass.lua
-- CTRBLXAI | Feature Coherence System — Round 1
--
-- Assigns terrain-correlated elevation to each tile.
-- Uses terrain tags (from TerrainData) to determine elevation ranges,
-- then smooths gradients and enforces the LAN Jump=1 constraint.
--
-- Phases:
--   1  Tag-based initial assignment (Round 3: low ground uses cfg.baseBand,
--      ridge cliff-edge Rocky starts at baseBand.hi + cfg.cliffDrop)
--   1b Neighbor-averaging for structural terrain (Metal, etc.)
--   1c Elevation noise within uniform regions
--   2  ADV marker bonus
--   3  Gradient smoothing (2 passes, non-protected tiles, Stone / cliff-edge /
--      gap tiles exempt; cliff-step pairs that are not spine-to-spine exempt)
--   3b Cliff-face enforcement (Round 3): ridge cliff-edge tiles (FeaturePass
--      placeRidge -> tile.isCliffEdge) hold a >= cfg.cliffDrop step over
--      adjacent non-ridge low ground
--   4  LAN constraint enforcement (3 passes, SPINE tiles only = LAN family
--      minus deliberate gap tiles)
--   5  Slope reachability — lower isolated max-elevation plateaus
--   6  Corridor connectivity repair (PD->ED <=1 ramp; avoids cliff edges when
--      possible, never routes through gap tiles; ALL corridor tiles graded)
--   6b Cliff re-assert (raise-only, off-corridor ridge cliff edges)
--   6c Bridge span deck grading (bank -> span -> bank, <=1 steps)
--   7  Gap depth: deliberate gap tiles sink >= drop below every bank
--   8  Audit -> mapState.elevationAudit
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

--- Spine = the traversable LAN-family lane. Deliberate gap tiles
--- (FeaturePass placeGapsAndSpans -> tile.isGap) are cut OUT of the spine:
--- they are chasm floor, crossed only by the bridge span.
local function isSpine(tile)
	-- Deliberate bridge span tiles (isBridge) are part of the spine: the span
	-- is the lane's crossing over the gap.
	return (LAN_FAMILY[tile.marker] == true or tile.isBridge == true)
		and not tile.isGap
end

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

local function getTagElevationRange(terrainId, cfg, tile)
	-- Sea-level model (dev-locked 2026-09-24): sea = cfg.seaLevel, floor = cfg.floor.
	-- Water rests at/below sea level; rock rises toward the biome max.
	local bMin  = cfg.min          -- land band minimum
	local bMax  = cfg.max          -- land band maximum (biome peak)
	local sea   = cfg.seaLevel or 5
	local floor = cfg.floor  or 1
	-- Round 3 (biomes spec rows 16-26): high-ground start comes from the DB
	-- band (cfg.bMid); the legacy formula is kept as the fallback.
	local bMid  = cfg.bMid or math.floor((sea + bMax) / 2)
	-- Typical low-ground band (spec col_4). nil -> legacy sea..bMid ranges.
	local base   = cfg.baseBand
	local baseLo = base and base.lo or sea
	local baseHi = base and math.min(base.hi, bMid) or bMid
	local cliffDrop = cfg.cliffDrop or 2

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

	-- Priority 5: Loose (Sand, Quicksand) — low land in the base band.
	if hasTag(terrainId, "Loose") then
		if base then return baseLo, baseHi, false end
		return sea, bMid, false
	end

	-- Priority 6: Organic (Grassland, Clover, Wooden Floor) — gentle land.
	if hasTag(terrainId, "Organic") then
		if base then return baseLo, baseHi, false end
		return sea, bMid, false
	end

	-- Priority 7: Natural (Clear) — base band (Round 3: the spec's "rest low";
	-- legacy was sea-1..biome max, which scattered random high ground).
	if hasTag(terrainId, "Natural") then
		if base then return baseLo, baseHi, false end
		return math.max(floor, sea - 1), bMax, false
	end

	-- Priority 8: Stone (Rocky) — elevated terrain, the cliff material.
	-- Ridge cliff-edge tiles (placeRidge -> isCliffEdge) reserve the cliff-face
	-- step: they start at least cfg.cliffDrop above the top of the base band.
	-- Round 3: region-FLOOR Rocky (not claimed by any feature, not a ridge,
	-- not ADV) is ordinary low ground and sits in the base band, so the map's
	-- high ground is the deliberate features the spinePct budget controls.
	if hasTag(terrainId, "Stone") then
		if tile and tile.isCliffEdge then
			local lo = math.min(bMax, math.max(bMid, baseHi + cliffDrop))
			return lo, bMax, false
		end
		if base and tile and not tile.featured and not tile.isRidge
			and tile.marker ~= "ADV" then
			return baseLo, baseHi, false
		end
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

	-- Priority 11: Corrupted / Arcane / Portal — base band (Tainted Ground is
	-- the Corrupted biome floor; its "modest rises" come from ridges / ADV).
	if hasAnyTag(terrainId, { "Corrupted", "Arcane", "Portal" }) then
		if base then return baseLo, baseHi, false end
		return sea, bMax, false
	end

	-- Fallback: base band (legacy: sea level to biome max).
	if base then return baseLo, baseHi, false end
	return sea, bMax, false
end

--- Cliff-edge tile: a ridge perimeter tile marked by FeaturePass placeRidge
--- (tile.isCliffEdge) that is still Stone (a later feature may have
--- repainted it) and is neither spine nor gap.
local function isCliffTile(tile)
	return tile.isCliffEdge == true
		and not tile.isGap
		and not isSpine(tile)
		and hasTag(tile.terrain, "Stone")
end

--- Cliff-step exemption (Round 3, biomes spec row 27). A deliberate cliff
--- STEP between a and b survives smoothing / flattening when the pair is NOT
--- spine-to-spine and at least one side is the cliff material (Stone or a
--- ridge cliff edge). Spine-to-spine adjacency is always held to <= 1.
local function cliffStepExempt(a, b)
	if isSpine(a) and isSpine(b) then return false end
	return isCliffTile(a) or isCliffTile(b)
		or hasTag(a.terrain, "Stone") or hasTag(b.terrain, "Stone")
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
			local eMin, eMax, needsAvg = getTagElevationRange(tile.terrain, cfg, tile)

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
	-- PHASE 2b: OBS elevation spike (added Sep 30 2026; design corrected 2026-10-05)
	-- OBS (formerly BLK) is a raised-terrain SPIKE, NOT an absolute wall. An OBS
	-- tile is raised to OBS_SPIKE elevation above its 8-way-adjacent non-OBS
	-- neighbors, CLAMPED at the global peak (never above the legal [floor,peak]
	-- range). Terrain is inherited from whatever the region floor / features
	-- already placed (OBS is NOT terrain-dependent). The tile is flagged
	-- isObstacle so later phases (3 smoothing, 5 slope-reachability, 6 corridor-
	-- repair) leave the spike intact rather than grading it back to a walkable step.
	-- OBS is intentionally TRAVERSABLE by Flight / high-jump units (the +5 spike is
	-- a movement cost, not a hard block); the truly-impassable variant is a FUTURE
	-- placed structure OBJECT (routed through the blocker-object path), not terrain.
	---------------------------------------------------------
	-- OBS design (user-corrected 2026-10-05): an OBS tile is a LOCAL spike —
	-- at least OBS_SPIKE elevation above its 8-WAY-adjacent NON-OBS neighbors —
	-- NOT a flat wall slammed to a global height. The result is CLAMPED at the
	-- global peak (peakE); it never exceeds the legal [floor,peak] range (so V2
	-- stays clean and walls in already-high terrain don't tower absurdly). This
	-- replaces the old lazy `peakE + OBS_SPIKE` (=25) floor that forced every OBS
	-- tile to the same height and visually walled off large areas.
	local OBS_SPIKE = 5           -- min elevation gap above neighbors (locked)
	local OBS_NEIGHBORS_8 = {
		{ x =  0, y =  1 }, { x =  0, y = -1 }, { x =  1, y =  0 }, { x = -1, y =  0 },
		{ x =  1, y =  1 }, { x =  1, y = -1 }, { x = -1, y =  1 }, { x = -1, y = -1 },
	}
	do
		-- Two-pass so an OBS tile's height is measured against NON-OBS neighbors
		-- only (adjacent OBS tiles in a blob don't inflate each other).
		local obsList = {}
		for y = 1, h do
			for x = 1, w do
				if tiles[y][x].marker == "OBS" then
					table.insert(obsList, { x = x, y = y })
				end
			end
		end
		local maxRaised = 0
		for _, pos in ipairs(obsList) do
			local tile = tiles[pos.y][pos.x]
			-- Highest NON-OBS 8-way neighbor sets the base this spike rises above.
			local maxNb = floorE
			for _, dir in ipairs(OBS_NEIGHBORS_8) do
				local nx, ny = pos.x + dir.x, pos.y + dir.y
				if isInBounds(nx, ny, w, h) then
					local n = tiles[ny][nx]
					if n.marker ~= "OBS" and n.elevation > maxNb then
						maxNb = n.elevation
					end
				end
			end
			-- Local +OBS_SPIKE spike, clamped to the global peak (never above peakE).
			tile.elevation  = math.min(maxNb + OBS_SPIKE, peakE)
			tile.isObstacle = true
			if tile.elevation > maxRaised then maxRaised = tile.elevation end
		end
		if #obsList > 0 then
			print(string.format("[ElevationPass] Phase 2b: raised %d OBS tile(s) to a local +%d spike (max %d, clamped to peak %d).",
				#obsList, OBS_SPIKE, maxRaised, peakE))
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
					-- Round 3: ridge cliff edges and deliberate gap tiles are exempt too
					-- (gap depth is set in Phase 7).
					-- Sep 30 2026: OBS walls (isObstacle, raised above peak in Phase 2b)
					-- are exempt so smoothing never grades the wall back down.
					if not isStone and not tile.isCliffEdge and not tile.isGap
						and not tile.isObstacle then
						for _, dir in ipairs(CARDINAL) do
							local nx, ny = x + dir.x, y + dir.y
							if isInBounds(nx, ny, w, h) then
								local neighbor = tiles[ny][nx]
								-- Round 3: a deliberate cliff step (not spine-to-spine)
								-- is not softened from the low side either.
								if not cliffStepExempt(tile, neighbor) then
									local diff = tile.elevation - neighbor.elevation
									if diff > 6 then
										tile.elevation = tile.elevation - 1
									elseif diff < -6 then
										tile.elevation = tile.elevation + 1
									end
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
	-- PHASE 3b: Cliff-face enforcement (Round 3, biomes spec row 27)
	-- Every ridge cliff-edge tile (FeaturePass placeRidge -> isCliffEdge) must
	-- stand >= cfg.cliffDrop above each adjacent non-ridge, non-gap neighbour.
	--   1. Raise the ridge tile (capped at the biome max; never lowered).
	--   2. If the cap prevents it, lower the LOW neighbour — only when that
	--      neighbour is off the spine, unprotected, not a bridge span and not
	--      Stone (floor: one below the base band).
	-- Ridge interior tiles are then lifted to at least (edge - 1) so the ridge
	-- reads as a solid block rather than a rim.
	-- Spine tiles are never moved here, so the PD->ED lane is untouched.
	---------------------------------------------------------
	local cliffDrop = cfg.cliffDrop or 2
	local baseBand  = cfg.baseBand
	local lowFloor  = math.max(floorE, (baseBand and baseBand.lo or sea) - 1)
	do
		for y = 1, h do
			for x = 1, w do
				local tile = tiles[y][x]
				if isCliffTile(tile) then
					local cap = math.max(tile.elevation, cfg.max)
					for _, dir in ipairs(CARDINAL) do
						local nx, ny = x + dir.x, y + dir.y
						if isInBounds(nx, ny, w, h) then
							local n = tiles[ny][nx]
							if not n.isCliffEdge and not n.isRidge and not n.isGap then
								local need = n.elevation + cliffDrop
								if tile.elevation < need then
									tile.elevation = math.min(need, cap)
								end
								if tile.elevation - n.elevation < cliffDrop
									and not isSpine(n) and not n.protected
									and not n.isBridge and not hasTag(n.terrain, "Stone")
								then
									n.elevation = math.max(lowFloor, tile.elevation - cliffDrop)
								end
							end
						end
					end
					tile.elevation = math.clamp(tile.elevation, floorE, peakE)
				end

				ops = ops + 1
				if ops % YIELD_INTERVAL == 0 then task.wait() end
			end
		end
		-- Ridge interior: no lower than its highest cliff-edge neighbour - 1.
		for y = 1, h do
			for x = 1, w do
				local tile = tiles[y][x]
				if tile.isRidge and not tile.isCliffEdge and not tile.isGap
					and hasTag(tile.terrain, "Stone") then
					local best = tile.elevation
					for _, dir in ipairs(CARDINAL) do
						local nx, ny = x + dir.x, y + dir.y
						if isInBounds(nx, ny, w, h) and tiles[ny][nx].isCliffEdge then
							best = math.max(best, tiles[ny][nx].elevation - 1)
						end
					end
					tile.elevation = math.clamp(best, floorE, peakE)
				end
			end
		end
	end

	---------------------------------------------------------
	-- PHASE 4: LAN constraint enforcement (3 passes)
	-- Adjacent SPINE tiles (LAN family minus deliberate gap tiles) must
	-- differ by ≤ 1 (Jump=1). Round 3: the constraint applies ONLY to
	-- spine-to-spine adjacency; a spine tile next to a ridge cliff edge or a
	-- gap is not a spine pair, so the cliff / chasm step is preserved.
	---------------------------------------------------------
	for _ = 1, 3 do
		for y = 1, h do
			for x = 1, w do
				local tile = tiles[y][x]
				if isSpine(tile) then
					for _, dir in ipairs(CARDINAL) do
						local nx, ny = x + dir.x, y + dir.y
						if isInBounds(nx, ny, w, h) then
							local neighbor = tiles[ny][nx]
							if isSpine(neighbor) and not cliffStepExempt(tile, neighbor) then
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
				-- Sep 30 2026: never lower an OBS wall (isObstacle); it is an
				-- intentionally-unreachable spike above the peak, not a stray plateau.
				if tiles[y][x].elevation == cfg.max and not tiles[y][x].isObstacle then
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

	-- Round 3 corridor bookkeeping (read by Phases 6b and 8).
	local corridorSet      = {}
	local corridorLen      = 0
	local corridorCutCliff = false

	---------------------------------------------------------
	-- PHASE 6: Corridor connectivity repair (dev-locked 2026-09-24)
	-- After de-flattening (HZD/OBS/ADV excluded from LAN_FAMILY), the
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
			-- Round 3: deliberate gap tiles are never corridor (the corridor must
			-- use the bridge span); ridge cliff edges are avoided on the first
			-- search so the corridor does not grade a cliff away, and only used
			-- by the fallback search if no cliff-free route exists.
			local function pathPassable(tile, avoidCliffs)
				if tile.isGap then return false end
				-- Sep 30 2026: OBS walls are never corridor material. Without this,
				-- the repair could route THROUGH an OBS tile (its inherited terrain
				-- is passable) and then grade the wall down to a <=1 ramp, destroying
				-- the impassable wall to force a path. Exclude it so the corridor
				-- routes AROUND OBS instead.
				if tile.isObstacle then return false end
				if avoidCliffs and isCliffTile(tile) then return false end
				local tDef = TerrainData.Types[tile.terrain]
				return tDef and tDef.passable ~= false
			end

			-- Multi-source BFS with parent tracking. Neighbor order prefers
			-- LAN tiles (keeps the corridor on the intended lane where possible)
			-- then is coordinate-stable for determinism.
			local parent, goalKey
			local function searchCorridor(avoidCliffs)
				parent = {}
				goalKey = nil
				local queue  = {}
				local qHead  = 1
				for _, pos in ipairs(pdList) do
					local key = coordKey(pos.x, pos.y)
					if parent[key] == nil then
						parent[key] = false  -- sentinel root
						table.insert(queue, pos)
					end
				end

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
							if parent[nKey] == nil and pathPassable(tiles[ny][nx], avoidCliffs) then
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
			end

			searchCorridor(true)
			if not goalKey then
				-- Fallback: allow the corridor over ridge cliff edges (connectivity
				-- always wins over a cliff).
				searchCorridor(false)
				corridorCutCliff = goalKey ~= nil
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
				-- Round 3: EVERY corridor tile is graded (LAN family included) —
				-- the cliff exemption never applies on the corridor.
				for _, p in ipairs(path) do
					corridorSet[coordKey(p.x, p.y)] = true
					-- MapService.placeObjects keeps non-passable objects off the
					-- corridor (it is often the only route once gaps are cut).
					tiles[p.y][p.x].isCorridor = true
				end
				corridorLen = #path
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

	---------------------------------------------------------
	-- PHASE 6b: Cliff re-assert (Round 3)
	-- Corridor grading may have lifted a corridor tile beside a ridge.
	-- Off-corridor ridge cliff edges are raised again (raise-only, capped at
	-- the biome max) so the >= cliffDrop face survives. Corridor tiles are
	-- never touched here, so the PD->ED ramp from Phase 6 stays intact.
	---------------------------------------------------------
	for y = 1, h do
		for x = 1, w do
			local tile = tiles[y][x]
			if isCliffTile(tile) and not corridorSet[coordKey(x, y)] then
				local cap = math.max(tile.elevation, cfg.max)
				for _, dir in ipairs(CARDINAL) do
					local nx, ny = x + dir.x, y + dir.y
					if isInBounds(nx, ny, w, h) then
						local n = tiles[ny][nx]
						if not n.isCliffEdge and not n.isRidge and not n.isGap then
							local need = n.elevation + cliffDrop
							if tile.elevation < need then
								tile.elevation = math.min(need, cap)
							end
						end
					end
				end
			end
		end
	end

	---------------------------------------------------------
	-- PHASE 6c: Bridge span deck grading (Round 3, biomes spec row 28)
	-- Each deliberate gap's span chain { bankIn, span1..spanN, bankOut } is
	-- graded so the deck is a <=1-step crossing. Only span tiles move; the
	-- banks keep their elevation. When the banks differ by more than N+1 the
	-- deck cannot be made walkable by moving the span alone; the bank that is
	-- NOT on the Phase 6 corridor is then pulled to within reach (the
	-- corridor is never touched). If both banks are corridor tiles the chain
	-- is already graded. Anything still unwalkable is rejected by
	-- MapService.validateGapSpans and the attempt loop re-rolls.
	---------------------------------------------------------
	for _, gap in ipairs(mapState.bridgeGaps or {}) do
		local chain = gap.chain
		if chain and #chain >= 3 then
			local ca, cb = chain[1], chain[#chain]
			local a = tiles[ca.y][ca.x]
			local b = tiles[cb.y][cb.x]
			local steps = #chain - 1
			local diff  = b.elevation - a.elevation
			if math.abs(diff) > steps then
				local aOnCorridor = corridorSet[coordKey(ca.x, ca.y)] == true
				local bOnCorridor = corridorSet[coordKey(cb.x, cb.y)] == true
				if not bOnCorridor then
					if diff > 0 then
						b.elevation = a.elevation + steps
					else
						b.elevation = a.elevation - steps
					end
				elseif not aOnCorridor then
					if diff > 0 then
						a.elevation = b.elevation - steps
					else
						a.elevation = b.elevation + steps
					end
				end
				diff = b.elevation - a.elevation
			end
			if math.abs(diff) <= steps then
				for i = 2, #chain - 1 do
					local c = chain[i]
					local frac = (i - 1) / steps
					tiles[c.y][c.x].elevation = math.clamp(
						a.elevation + math.floor(diff * frac + 0.5), floorE, peakE)
				end
			end
		end
	end

	---------------------------------------------------------
	-- PHASE 7: Gap depth (Round 3, biomes spec row 28)
	-- Deliberate gap tiles sink below every non-gap neighbour by at least
	-- the gap depth (tile.gapDepth, default cfg.cliffDrop), capped at the gap
	-- terrain's own tag ceiling and floored at the global floor. Off-span the
	-- gap is therefore not walkable (>= 2 step) and reads as a real chasm /
	-- moat / lava channel; the span (Phase 6c) is the crossing.
	---------------------------------------------------------
	local gapTiles, gapLeaks = 0, 0
	for y = 1, h do
		for x = 1, w do
			local tile = tiles[y][x]
			if tile.isGap then
				gapTiles = gapTiles + 1
				local depth = math.max(2, tile.gapDepth or cliffDrop)
				local minN  = nil
				for _, dir in ipairs(CARDINAL) do
					local nx, ny = x + dir.x, y + dir.y
					if isInBounds(nx, ny, w, h) then
						local n = tiles[ny][nx]
						if not n.isGap and not hasAnyTag(n.terrain, { "Deep", "Molten" }) then
							if minN == nil or n.elevation < minN then minN = n.elevation end
						end
					end
				end
				local _, tagHi = getTagElevationRange(tile.terrain, cfg, tile)
				local e = tagHi
				if minN then e = math.min(tagHi, minN - depth) end
				tile.elevation = math.clamp(e, floorE, peakE)
			end
		end
	end

	---------------------------------------------------------
	-- PHASE 8: Audit (advisory; read by MapService / sample-map tooling)
	---------------------------------------------------------
	local bMid = cfg.bMid or math.floor((sea + cfg.max) / 2)
	local highCount, cliffEdges, cliffFaced = 0, 0, 0
	for y = 1, h do
		for x = 1, w do
			local tile = tiles[y][x]
			if tile.elevation >= bMid and not tile.isGap then
				highCount = highCount + 1
			end
			if isCliffTile(tile) then
				cliffEdges = cliffEdges + 1
				local faced = false
				for _, dir in ipairs(CARDINAL) do
					local nx, ny = x + dir.x, y + dir.y
					if isInBounds(nx, ny, w, h) then
						local n = tiles[ny][nx]
						if not n.isCliffEdge and not n.isRidge
							and tile.elevation - n.elevation >= cliffDrop then
							faced = true
						end
					end
				end
				if faced then cliffFaced = cliffFaced + 1 end
			end
			if tile.isGap then
				-- Leak = a dry-land neighbour within one step of the gap floor
				-- (i.e. somewhere the chasm could be walked into off-span).
				-- Adjacent pre-existing Deep Water / lava pools are not dry land.
				for _, dir in ipairs(CARDINAL) do
					local nx, ny = x + dir.x, y + dir.y
					if isInBounds(nx, ny, w, h) then
						local n = tiles[ny][nx]
						if not n.isGap and not hasAnyTag(n.terrain, { "Deep", "Molten" })
							and math.abs(n.elevation - tile.elevation) <= 1 then
							gapLeaks = gapLeaks + 1
						end
					end
				end
			end
		end
	end
	mapState.elevationAudit = {
		cliffDrop        = cliffDrop,
		bMid             = bMid,
		spinePctTarget   = cfg.spinePct,
		highGroundPct    = highCount / (w * h),
		cliffEdgeTiles   = cliffEdges,
		cliffFacedTiles  = cliffFaced,
		corridorLen      = corridorLen,
		corridorCutCliff = corridorCutCliff,
		gapTiles         = gapTiles,
		gapLeaks         = gapLeaks,
	}

	return mapState
end

return ElevationPass
