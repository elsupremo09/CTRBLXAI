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
--   7b Pocket breaker (2026-11-21, SIM_pocket_breaker R1): Jump-1 walker
--      (up <= 1, down <= 3); grades the cheapest <=1-step ramp out of one-way
--      pockets and pockets holding PD/ED/OBJ/POI; key-snap fallback; guarded
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
-- POCKET BREAKER (Phase 7b) + JUMP-1 WALKABILITY ANALYSIS (2026-11-21)
-- Source: SIM_pocket_breaker_20261121, recommendation R1-final (user decision
-- 2026-11-21: keep base Jump 1 and repair stuck pockets in generation; R2 ramp
-- guarantee NOT adopted). KEY-SNAP fallback ALLOWED by USER RULING 2026-11-21
-- 2:47 PM: a walled-in PD/ED/OBJ/POI tile may have ONLY its elevation regraded;
-- its marker, terrain and object never change.
--
-- Walker = a base unit, mirroring TargetingService.GetMoveCandidates /
-- GetWalkJumpLimits at base Jump:
--   * 8 directions; a diagonal is dropped only when BOTH orthogonal corners are
--     blockers (OBS in either form = tile.isObstacle, i.e. runtime IsBlocked);
--   * a step is legal when climb <= WALK_UP and drop <= WALK_DOWN;
--   * not standable: OBS, passable == false terrain, Quicksand (Sinking; the AI
--     never paths through it), Molten (lethal) and chasm/gap floors (isGap).
-- Objects are placed AFTER this pass (MapService Step 8), so they are not part of
-- this walker; validateConnectivity / validateLanesPassable re-check them.
-- Repair-only: never rejects, re-seeds or regenerates a map.
--------------------------------------------------

-- Base Jump = DB core_stats "1 + floor(DEX / 60)" at the base DEX band
-- (GameConstants derived stats / StatCalcService.GetJump). There is no shared
-- BASE_JUMP constant to read; the drop limit follows TargetingService
-- getDownwardJump (Jump + 2).
local WALK_UP   = 1
local WALK_DOWN = WALK_UP + 2

local POCKET_BUDGET_RAMPS      = 20   -- ramp applications per map (accepted or undone)
local POCKET_BUDGET_TILES      = 80   -- tiles regraded per map
local POCKET_MAX_COST          = 12   -- strict search
local POCKET_MAX_COST_FALLBACK = 16   -- relaxed / key-snap searches
local POCKET_YIELD_OPS         = 2000 -- yield cadence (PRF-003), matches the report
local POCKET_UNREPAIRED_LOG    = 10   -- unrepaired pockets kept in the audit
local POCKET_KEY_MARKERS = { PD = true, ED = true, OBJ = true, POI = true }

local DIR8 = {
	{ x =  0, y =  1 }, { x =  0, y = -1 }, { x =  1, y =  0 }, { x = -1, y =  0 },
	{ x =  1, y =  1 }, { x =  1, y = -1 }, { x = -1, y =  1 }, { x = -1, y = -1 },
}

-- Stage ids for the per-job fallback ladder (report section 7 step 9).
local STAGE_STRICT, STAGE_RELAXED, STAGE_KEYSNAP = 1, 2, 3

-- Busy-time accounting + periodic yield shared by every flood / search here.
local pocketOps, pocketBusy, pocketSeg = 0, 0, 0
local function pocketTick()
	pocketOps = pocketOps + 1
	if pocketOps % POCKET_YIELD_OPS == 0 then
		pocketBusy = pocketBusy + (os.clock() - pocketSeg)
		task.wait()
		pocketSeg = os.clock()
	end
end

local function stepLegal(fromElev, toElev)
	local d = toElev - fromElev
	return d <= WALK_UP and -d <= WALK_DOWN
end

--- Static walk graph. Standability and legal directions never change while
--- ramps regrade elevation, so only the elevation check is done live.
local function buildWalkGraph(tiles, w, h)
	local n = w * h
	local stand, blocker, tileOf, isKey = {}, {}, {}, {}
	local pdList = {}
	for y = 1, h do
		for x = 1, w do
			local i = (y - 1) * w + x
			local t = tiles[y][x]
			tileOf[i] = t
			blocker[i] = t.isObstacle == true and t.obsForm ~= "spike" -- W2: only object-form OBS seals corners (DB row 77)
			local tDef = TerrainData.Types[t.terrain]
			local ok = not t.isObstacle and not t.isGap
				and tDef ~= nil and tDef.passable ~= false
				and t.terrain ~= "Quicksand"
				and not hasTag(t.terrain, "Molten")
			stand[i] = ok
			isKey[i] = ok and POCKET_KEY_MARKERS[t.marker] == true
			if ok and t.marker == "PD" then table.insert(pdList, i) end
		end
	end
	local nbrs = {}
	for y = 1, h do
		for x = 1, w do
			local i = (y - 1) * w + x
			local list = {}
			if stand[i] then
				for _, d in ipairs(DIR8) do
					local nx, ny = x + d.x, y + d.y
					if isInBounds(nx, ny, w, h) then
						local j = (ny - 1) * w + nx
						if stand[j] then
							local sealed = false
							if d.x ~= 0 and d.y ~= 0 then
								sealed = blocker[(y - 1) * w + nx] and blocker[(ny - 1) * w + x]
							end
							if not sealed then table.insert(list, j) end
						end
					end
				end
			end
			nbrs[i] = list
		end
	end
	return { w = w, h = h, n = n, stand = stand, nbrs = nbrs,
		tileOf = tileOf, isKey = isKey, pdList = pdList }
end

--- Forward flood (walk away from PD) or reverse flood (tiles that can walk TO PD).
local function floodWalk(g, reverse)
	local seen, q, head = {}, {}, 1
	for _, s in ipairs(g.pdList) do
		if not seen[s] then seen[s] = true; table.insert(q, s) end
	end
	local tileOf, nbrs = g.tileOf, g.nbrs
	while head <= #q do
		local i = q[head]; head = head + 1
		pocketTick()
		local ei = tileOf[i].elevation
		for _, j in ipairs(nbrs[i]) do
			if not seen[j] then
				local ej = tileOf[j].elevation
				-- reverse: the walker steps j -> i
				local legal = if reverse then stepLegal(ej, ei) else stepLegal(ei, ej)
				if legal then
					seen[j] = true
					table.insert(q, j)
				end
			end
		end
	end
	return seen
end

--- F = reachable from PD, B = can walk back to PD, Main = F and B,
--- trapCount = one-way trap tiles (F minus B).
local function computeFlows(g)
	local F = floodWalk(g, false)
	local B = floodWalk(g, true)
	local main, trapCount = {}, 0
	for i = 1, g.n do
		if F[i] then
			if B[i] then main[i] = true else trapCount = trapCount + 1 end
		end
	end
	return { F = F, B = B, main = main, trapCount = trapCount }
end

--- Group the standable tiles outside Main into pockets (connected through legal
--- moves in either direction, same class): "trap" = cannot walk back to PD
--- (oneWay when any tile is enterable from PD), "exit" = can leave, cannot enter.
local function computeGroups(g, an)
	local F, B, main = an.F, an.B, an.main
	local tileOf, nbrs = g.tileOf, g.nbrs
	local groups, groupOf = {}, {}
	for i = 1, g.n do
		if g.stand[i] and not main[i] and not groupOf[i] then
			local isTrap = not B[i]
			local grp = { kind = if isTrap then "trap" else "exit",
				tiles = { i }, oneWay = false, hasKey = false, keyCount = 0, inSet = {} }
			groupOf[i] = grp
			local q, head = grp.tiles, 1
			while head <= #q do
				local v = q[head]; head = head + 1
				pocketTick()
				grp.inSet[v] = true
				if isTrap and F[v] then grp.oneWay = true end
				if g.isKey[v] then grp.hasKey = true; grp.keyCount = grp.keyCount + 1 end
				local ev = tileOf[v].elevation
				for _, u in ipairs(nbrs[v]) do
					if not groupOf[u] and not main[u] and ((not B[u]) == isTrap) then
						local eu = tileOf[u].elevation
						if stepLegal(ev, eu) or stepLegal(eu, ev) then
							groupOf[u] = grp
							table.insert(q, u)
						end
					end
				end
			end
			table.insert(groups, grp)
		end
	end
	an.groups = groups
	return an
end

local function isRepairTarget(grp)
	return (grp.kind == "trap" and grp.oneWay and #grp.tiles > 1) or grp.hasKey
end

--- Strongly connected parts of one pocket (iterative Kosaraju over legal moves
--- restricted to the pocket) plus a sink flag (no legal move to another part).
local function pocketSCCs(g, grp)
	local tileOf, nbrs, inSet = g.tileOf, g.nbrs, grp.inSet
	local visited, order = {}, {}
	for _, s in ipairs(grp.tiles) do
		if not visited[s] then
			visited[s] = true
			local stack, ptr = { s }, { [s] = 1 }
			while #stack > 0 do
				local v = stack[#stack]
				local list = nbrs[v]
				local k = ptr[v]
				local pushed = false
				while k <= #list do
					local u = list[k]
					k = k + 1
					if inSet[u] and not visited[u]
						and stepLegal(tileOf[v].elevation, tileOf[u].elevation) then
						visited[u] = true
						ptr[u] = 1
						table.insert(stack, u)
						pushed = true
						break
					end
				end
				ptr[v] = k
				if not pushed then
					table.remove(stack)
					table.insert(order, v)
				end
			end
		end
	end
	local comp, comps = {}, {}
	for oi = #order, 1, -1 do
		local s = order[oi]
		if not comp[s] then
			local cid = #comps + 1
			local members, st = {}, { s }
			comp[s] = cid
			while #st > 0 do
				local v = table.remove(st)
				pocketTick()
				table.insert(members, v)
				for _, u in ipairs(nbrs[v]) do
					if inSet[u] and not comp[u]
						and stepLegal(tileOf[u].elevation, tileOf[v].elevation) then
						comp[u] = cid
						table.insert(st, u)
					end
				end
			end
			comps[cid] = members
		end
	end
	local isSink = {}
	for cid, members in ipairs(comps) do
		local sink = true
		for _, v in ipairs(members) do
			for _, u in ipairs(nbrs[v]) do
				if inSet[u] and comp[u] ~= cid
					and stepLegal(tileOf[v].elevation, tileOf[u].elevation) then
					sink = false
					break
				end
			end
			if not sink then break end
		end
		isSink[cid] = sink
	end
	return comps, isSink
end

--- Repair jobs (report step 6): key pockets first, then larger pockets. Each SCC
--- holding a key tile -> connect to Main; each sink SCC of a trap pocket ->
--- connect to B (upstream parts then drain through it).
local function buildJobs(g, an)
	local targets = {}
	for _, grp in ipairs(an.groups) do
		if isRepairTarget(grp) then table.insert(targets, grp) end
	end
	table.sort(targets, function(a, b)
		if a.hasKey ~= b.hasKey then return a.hasKey end
		if #a.tiles ~= #b.tiles then return #a.tiles > #b.tiles end
		return a.tiles[1] < b.tiles[1]
	end)
	local jobs = {}
	for _, grp in ipairs(targets) do
		local comps, isSink = pocketSCCs(g, grp)
		local keyJobs, sinkJobs = {}, {}
		for cid, members in ipairs(comps) do
			local hasKey, minI = false, math.huge
			for _, v in ipairs(members) do
				if g.isKey[v] then hasKey = true end
				if v < minI then minI = v end
			end
			if hasKey then
				table.insert(keyJobs, { tiles = members, goal = "main", group = grp, key = "M" .. minI })
			elseif grp.kind == "trap" and isSink[cid] then
				table.insert(sinkJobs, { tiles = members, goal = "back", group = grp, key = "B" .. minI })
			end
		end
		for _, j in ipairs(keyJobs) do table.insert(jobs, j) end
		for _, j in ipairs(sinkJobs) do table.insert(jobs, j) end
	end
	return jobs
end

-- Binary min-heap on (cost, state); the state id breaks ties -> deterministic.
local function heapLess(hc, hs, a, b)
	return hc[a] < hc[b] or (hc[a] == hc[b] and hs[a] < hs[b])
end
local function heapPush(hc, hs, c, s)
	local n = #hc + 1
	hc[n], hs[n] = c, s
	while n > 1 do
		local p = math.floor(n / 2)
		if not heapLess(hc, hs, n, p) then break end
		hc[p], hc[n] = hc[n], hc[p]
		hs[p], hs[n] = hs[n], hs[p]
		n = p
	end
end
local function heapPop(hc, hs)
	local n = #hc
	local c, s = hc[1], hs[1]
	hc[1], hs[1] = hc[n], hs[n]
	hc[n], hs[n] = nil, nil
	n = n - 1
	local i = 1
	while true do
		local l, r, m = 2 * i, 2 * i + 1, i
		if l <= n and heapLess(hc, hs, l, m) then m = l end
		if r <= n and heapLess(hc, hs, r, m) then m = r end
		if m == i then break end
		hc[m], hc[i] = hc[i], hc[m]
		hs[m], hs[i] = hs[i], hs[m]
		i = m
	end
	return c, s
end

--- May tile i be regraded at this stage? (report step 8)
local function canEdit(ctx, i, stage)
	if ctx.lockStatic[i] or ctx.used[i] or ctx.frozen[i] then return false end
	if ctx.g.isKey[i] then
		-- KEY-SNAP (user ruling 2026-11-21): only a key tile INSIDE this pocket.
		return stage >= STAGE_KEYSNAP and ctx.jobSet[i] == true
	end
	if ctx.liquid[i] and stage < STAGE_RELAXED then return false end
	return true
end

--- Neighbours of an OBS spike may only be LOWERED (keeps the >= +5 spike rule).
local function editDirOk(ctx, i, newElev)
	return not (ctx.spikeNb[i] and newElev > ctx.g.tileOf[i].elevation)
end

--- Cheapest cardinal staircase (every step <= 1, so it walks both ways at
--- Jump 1) from the job's tiles to the goal set (report step 7). Dijkstra over
--- (tile, elevation) states. Returns the edit list or nil + reason.
local function rampSearch(ctx, job, an, stage, maxCost)
	local g = ctx.g
	local tileOf, stand, w, h = g.tileOf, g.stand, g.w, g.h
	local floorE, peakE = ctx.floorE, ctx.peakE
	local goalSet = if job.goal == "main" then an.main else an.B
	local dist, parent = {}, {}
	local hc, hs = {}, {}
	local function relax(s, c, from)
		if c <= maxCost and (dist[s] == nil or c < dist[s]) then
			dist[s] = c
			parent[s] = from
			heapPush(hc, hs, c, s)
		end
	end
	local single = #job.tiles == 1
	for _, i in ipairs(job.tiles) do
		local e0 = tileOf[i].elevation
		relax(i * 32 + e0, 0, false)
		if (single or (g.isKey[i] and stage >= STAGE_KEYSNAP)) and canEdit(ctx, i, stage) then
			for e = floorE, peakE do
				if e ~= e0 and editDirOk(ctx, i, e) then relax(i * 32 + e, 1, false) end
			end
		end
	end
	while #hc > 0 do
		local c, s = heapPop(hc, hs)
		if c <= dist[s] then
			pocketTick()
			local i = math.floor(s / 32)
			local e = s - i * 32
			if goalSet[i] and e == tileOf[i].elevation then
				-- Reconstruct; a tile may not be used at two different heights.
				local edits, seenE = {}, {}
				local cur = s
				while cur do
					local ci = math.floor(cur / 32)
					local ce = cur - ci * 32
					if seenE[ci] ~= nil and seenE[ci] ~= ce then return nil, "self-crossing ramp" end
					if seenE[ci] == nil then
						seenE[ci] = ce
						if ce ~= tileOf[ci].elevation then table.insert(edits, { i = ci, e = ce }) end
					end
					cur = parent[cur]
				end
				return edits, nil
			end
			local x = (i - 1) % w + 1
			local y = (i - x) / w + 1
			for _, d in ipairs(CARDINAL) do
				local nx, ny = x + d.x, y + d.y
				if isInBounds(nx, ny, w, h) then
					local j = (ny - 1) * w + nx
					if stand[j] then
						local ej0 = tileOf[j].elevation
						for de = -1, 1 do
							local e2 = e + de
							if e2 >= floorE and e2 <= peakE then
								if e2 == ej0 then
									relax(j * 32 + e2, c, s)
								elseif canEdit(ctx, j, stage) and editDirOk(ctx, j, e2) then
									local cost = 1
									if ctx.adv[j] then cost = cost + 0.5 end
									if ctx.liquid[j] then cost = cost + 1 end
									relax(j * 32 + e2, c + cost, s)
								end
							end
						end
					end
				end
			end
		end
	end
	return nil, "no ramp within cost"
end

--- Raise-floor fallback (report step 9.4): only if EVERY pocket tile is editable
--- (key-snap rules), clamp the pocket to [m, m+1], m = lowest adjacent Main tile.
local function raiseFloorEdits(ctx, job, an)
	local g = ctx.g
	local tileOf, w, h = g.tileOf, g.w, g.h
	local m = nil
	for _, i in ipairs(job.group.tiles) do
		if not canEdit(ctx, i, STAGE_KEYSNAP) then return nil end
		local x = (i - 1) % w + 1
		local y = (i - x) / w + 1
		for _, d in ipairs(CARDINAL) do
			local nx, ny = x + d.x, y + d.y
			if isInBounds(nx, ny, w, h) then
				local j = (ny - 1) * w + nx
				if an.main[j] and (m == nil or tileOf[j].elevation < m) then m = tileOf[j].elevation end
			end
		end
	end
	if m == nil then return nil end
	local edits = {}
	for _, i in ipairs(job.group.tiles) do
		local e0 = tileOf[i].elevation
		local e = math.clamp(e0, m, math.min(m + 1, ctx.peakE))
		if e ~= e0 then
			if not editDirOk(ctx, i, e) then return nil end
			table.insert(edits, { i = i, e = e })
		end
	end
	if #edits == 0 then return nil end
	return edits
end

--- Four-cardinal |diff| <= 1 walk over passable terrain: the same rule as
--- MapService validateConnectivity / laneReachesED / auditGapCrossings
--- (objects are not placed yet). laneSet: LAN tiles outside it are walls.
local function cardinalReaches(tiles, w, h, sources, blocked, laneSet, isGoal)
	local seen, q, head = {}, {}, 1
	for _, p in ipairs(sources) do
		local k = coordKey(p.x, p.y)
		if not seen[k] and not (blocked and blocked[k]) then
			seen[k] = true
			table.insert(q, p)
		end
	end
	while head <= #q do
		local cur = q[head]; head = head + 1
		pocketTick()
		if isGoal(cur.x, cur.y) then return true end
		local tile = tiles[cur.y][cur.x]
		for _, dir in ipairs(CARDINAL) do
			local nx, ny = cur.x + dir.x, cur.y + dir.y
			if isInBounds(nx, ny, w, h) then
				local k = coordKey(nx, ny)
				if not seen[k] and not (blocked and blocked[k]) then
					local n = tiles[ny][nx]
					local tDef = TerrainData.Types[n.terrain]
					local laneOk = laneSet == nil or n.marker ~= "LAN" or laneSet[k] == true
					if laneOk and tDef and tDef.passable ~= false
						and math.abs(tile.elevation - n.elevation) <= 1 then
						seen[k] = true
						table.insert(q, { x = nx, y = ny })
					end
				end
			end
		end
	end
	return false
end

--- Spine pairs (LAN family, <= 1 rule of Phase 4) around the edited tiles that
--- break the Jump-1 lane. Only key-snap can touch a spine tile (PD/ED).
local function spineBreaks(ctx, edits)
	local g = ctx.g
	local tileOf, w, h = g.tileOf, g.w, g.h
	local count = 0
	for _, ed in ipairs(edits) do
		local t = tileOf[ed.i]
		if isSpine(t) then
			local x = (ed.i - 1) % w + 1
			local y = (ed.i - x) / w + 1
			for _, d in ipairs(CARDINAL) do
				local nx, ny = x + d.x, y + d.y
				if isInBounds(nx, ny, w, h) then
					local n = tileOf[(ny - 1) * w + nx]
					if isSpine(n) and not cliffStepExempt(t, n)
						and math.abs(t.elevation - n.elevation) > 1 then
						count = count + 1
					end
				end
			end
		end
	end
	return count
end

--- No-regression guard (report step 10). Applies the edits, rechecks, and
--- reverts on any regression. Returns ok, newFlows|nil, reason|nil.
--- Structurally safe by the editable rules (never re-checked): OBS tiles and the
--- OBS spike >= +5 rule (spike neighbours lower only), gap floors / banks / span
--- chain (Gap Hard Invariant + gap depth), LAN tiles and the Phase-6 corridor.
local function applyGuarded(ctx, edits, an)
	local g = ctx.g
	local tileOf, tiles, w, h = g.tileOf, ctx.tiles, g.w, g.h
	local spineBefore = spineBreaks(ctx, edits)
	local old = {}
	for k, ed in ipairs(edits) do
		old[k] = tileOf[ed.i].elevation
		tileOf[ed.i].elevation = ed.e
	end
	local function undo(reason)
		for k, ed in ipairs(edits) do tileOf[ed.i].elevation = old[k] end
		return false, nil, reason
	end
	local nf = computeFlows(g)
	for i in pairs(an.main) do
		if not nf.main[i] then return undo("tile left Main") end
	end
	for i in pairs(an.F) do
		if not nf.F[i] then return undo("tile lost PD reach") end
	end
	if nf.trapCount > an.trapCount then return undo("new one-way trap") end
	if spineBreaks(ctx, edits) > spineBefore then return undo("LAN spine break") end
	local isED = function(x, y) return tiles[y][x].marker == "ED" end
	if ctx.v6Before and not cardinalReaches(tiles, w, h, ctx.pdCoords, nil, nil, isED) then
		return undo("V6 PD->ED path")
	end
	for _, lane in ipairs(ctx.lanesBefore) do
		if not cardinalReaches(tiles, w, h, ctx.pdCoords, nil, lane, isED) then
			return undo("lane passability")
		end
	end
	for _, ch in ipairs(ctx.chokesBefore) do
		local bx, by = ch.bankOut.x, ch.bankOut.y
		if cardinalReaches(tiles, w, h, { ch.bankIn }, ch.blocked, nil,
			function(x, y) return x == bx and y == by end) then
			return undo("chokepoint leak")
		end
	end
	return true, nf, nil
end

--- One repair job through the fallback ladder: strict -> relaxed (liquid tiles)
--- -> key-snap -> raise floor -> give up. A guard undo freezes those tiles and
--- retries once; a second undo gives the job up.
local function attemptJob(ctx, job, an)
	ctx.frozen = {}
	ctx.jobSet = job.group.inSet
	local lastReason = "no ramp within cost"
	local undos = 0
	local function tryEdits(edits, stage)
		if ctx.ramps >= POCKET_BUDGET_RAMPS
			or ctx.tilesChanged + #edits > POCKET_BUDGET_TILES then
			return "budget"
		end
		ctx.ramps = ctx.ramps + 1
		local ok, nf, why = applyGuarded(ctx, edits, an)
		if ok then
			ctx.accepted = ctx.accepted + 1
			ctx.tilesChanged = ctx.tilesChanged + #edits
			for _, ed in ipairs(edits) do
				ctx.used[ed.i] = true
				if ctx.g.isKey[ed.i] then ctx.keySnaps = ctx.keySnaps + 1 end
			end
			if stage == STAGE_RELAXED then ctx.relaxed = ctx.relaxed + 1 end
			if stage == STAGE_KEYSNAP then ctx.keySnapRamps = ctx.keySnapRamps + 1 end
			if stage == 4 then ctx.raiseFloors = ctx.raiseFloors + 1 end
			return "ok", nf
		end
		ctx.undone = ctx.undone + 1
		lastReason = "guard: " .. tostring(why)
		for _, ed in ipairs(edits) do ctx.frozen[ed.i] = true end
		undos = undos + 1
		return "undone"
	end
	for stage = STAGE_STRICT, STAGE_KEYSNAP do
		local maxCost = if stage == STAGE_STRICT then POCKET_MAX_COST else POCKET_MAX_COST_FALLBACK
		while true do
			local edits, why = rampSearch(ctx, job, an, stage, maxCost)
			if not edits or #edits == 0 then
				if why then lastReason = why end
				break
			end
			local res, nf = tryEdits(edits, stage)
			if res == "ok" then return true, nf, nil end
			if res == "budget" then return false, nil, "budget" end
			if undos >= 2 then return false, nil, lastReason end
		end
	end
	local edits = raiseFloorEdits(ctx, job, an)
	if edits then
		local res, nf = tryEdits(edits, 4)
		if res == "ok" then return true, nf, nil end
		if res == "budget" then return false, nil, "budget" end
	end
	return false, nil, lastReason
end

--- Phase 7b driver. Returns the audit table (mapState.elevationAudit.pocketBreaker).
local function runPocketBreaker(mapState)
	local tiles, w, h = mapState.tiles, mapState.width, mapState.height
	local cfg = mapState.biomeElevation
	pocketSeg = os.clock()
	pocketBusy = 0

	local g = buildWalkGraph(tiles, w, h)
	local an = computeGroups(g, computeFlows(g))

	local found, foundOneWay, foundKey, sealedEmpty = 0, 0, 0, 0
	for _, grp in ipairs(an.groups) do
		if isRepairTarget(grp) then
			found = found + 1
			if grp.hasKey then foundKey = foundKey + 1 else foundOneWay = foundOneWay + 1 end
		elseif grp.kind == "trap" and not grp.oneWay then
			sealedEmpty = sealedEmpty + 1
		end
	end

	-- Static editability (report step 8). Never: non-standable, Phase-6 corridor,
	-- bridge spans, gap floors, gap span chains, gap banks (cardinal neighbours of
	-- a gap, keeps gap depth), LAN, Deep water. Liquid tiles: relaxed stage only.
	local lockStatic, liquid, adv, spikeNb = {}, {}, {}, {}
	local chainTiles = {}
	for _, gap in ipairs(mapState.bridgeGaps or {}) do
		for _, c in ipairs(gap.chain or {}) do chainTiles[coordKey(c.x, c.y)] = true end
		for _, s in ipairs(gap.spanTiles or {}) do chainTiles[coordKey(s.x, s.y)] = true end
	end
	local pdCoords = {}
	for y = 1, h do
		for x = 1, w do
			local i = (y - 1) * w + x
			local t = tiles[y][x]
			if t.marker == "PD" then table.insert(pdCoords, { x = x, y = y }) end
			local lock = not g.stand[i] or t.isCorridor == true or t.isBridge == true
				or t.isGap == true or chainTiles[coordKey(x, y)] == true
				or t.marker == "LAN" or hasTag(t.terrain, "Deep")
			if not lock then
				for _, d in ipairs(DIR8) do -- W1 (Tester 2026-11-21): diagonal gap banks too, so no off-span diagonal climb-out
					local nx, ny = x + d.x, y + d.y
					if isInBounds(nx, ny, w, h) and tiles[ny][nx].isGap then lock = true; break end
				end
			end
			lockStatic[i] = lock
			liquid[i] = hasAnyTag(t.terrain, { "Liquid", "Frozen", "Slippery", "Water", "Sticky" })
			adv[i] = t.marker == "ADV"
			for _, d in ipairs(DIR8) do
				local nx, ny = x + d.x, y + d.y
				if isInBounds(nx, ny, w, h) and tiles[ny][nx].obsForm == "spike" then
					spikeNb[i] = true
					break
				end
			end
		end
	end

	local audit = {
		pocketsFound = found, oneWayFound = foundOneWay, keyPocketsFound = foundKey,
		sealedEmptyLeft = sealedEmpty, pocketsFixed = 0, unrepairedCount = 0,
		ramps = 0, rampsUndone = 0, tilesChanged = 0, keySnaps = 0, keySnapRamps = 0,
		relaxedRamps = 0, raiseFloors = 0, budgetHit = false, unrepaired = {}, ms = 0,
	}
	if #g.pdList == 0 then
		pocketBusy = pocketBusy + (os.clock() - pocketSeg)
		audit.ms = pocketBusy * 1000
		audit.skipped = "no standable PD tile"
		print("[ElevationPass] Phase 7b pocket breaker: skipped (no standable PD tile), 0 tile(s) changed")
		return audit
	end
	if found == 0 then
		pocketBusy = pocketBusy + (os.clock() - pocketSeg)
		audit.ms = pocketBusy * 1000
		print(string.format(
			"[ElevationPass] Phase 7b pocket breaker: 0 pocket(s) to repair (%d sealed-empty left), 0 tile(s) changed, %.1f ms",
			sealedEmpty, audit.ms))
		return audit
	end

	-- Baselines for the no-regression guard (only checks that pass now must keep passing).
	local isED = function(x, y) return tiles[y][x].marker == "ED" end
	local v6Before = cardinalReaches(tiles, w, h, pdCoords, nil, nil, isED)
	local lanesBefore = {}
	do
		local seenLan = {}
		for y = 1, h do
			for x = 1, w do
				local k0 = coordKey(x, y)
				if tiles[y][x].marker == "LAN" and not seenLan[k0] then
					local laneSet, q, head = { [k0] = true }, { { x = x, y = y } }, 1
					seenLan[k0] = true
					while head <= #q do
						local cur = q[head]; head = head + 1
						for _, d in ipairs(CARDINAL) do
							local nx, ny = cur.x + d.x, cur.y + d.y
							local nk = coordKey(nx, ny)
							if isInBounds(nx, ny, w, h) and tiles[ny][nx].marker == "LAN" and not seenLan[nk] then
								seenLan[nk] = true
								laneSet[nk] = true
								table.insert(q, { x = nx, y = ny })
							end
						end
					end
					if cardinalReaches(tiles, w, h, pdCoords, nil, laneSet, isED) then
						table.insert(lanesBefore, laneSet)
					end
				end
			end
		end
	end
	local chokesBefore = {}
	for _, gap in ipairs(mapState.bridgeGaps or {}) do
		local chain = gap.chain or {}
		if gap.gapType == "chokepoint" and #chain >= 2 then
			local blocked = {}
			for _, s in ipairs(gap.spanTiles or {}) do blocked[coordKey(s.x, s.y)] = true end
			local bankOut = chain[#chain]
			local leaks = cardinalReaches(tiles, w, h, { chain[1] }, blocked, nil,
				function(x, y) return x == bankOut.x and y == bankOut.y end)
			if not leaks then
				table.insert(chokesBefore, { bankIn = chain[1], bankOut = bankOut, blocked = blocked })
			end
		end
	end

	local ctx = {
		g = g, tiles = tiles, floorE = cfg.floor or 1, peakE = cfg.peak or 20,
		lockStatic = lockStatic, liquid = liquid, adv = adv, spikeNb = spikeNb,
		used = {}, frozen = {}, jobSet = {},
		pdCoords = pdCoords, v6Before = v6Before, lanesBefore = lanesBefore, chokesBefore = chokesBefore,
		ramps = 0, accepted = 0, undone = 0, tilesChanged = 0, keySnaps = 0,
		keySnapRamps = 0, relaxed = 0, raiseFloors = 0,
	}

	-- Repair loop (report step 11): re-flood after every accepted ramp.
	local failReasonAt = {}
	local failed = {}
	while true do
		local progressed = false
		for _, job in ipairs(buildJobs(g, an)) do
			if not failed[job.key] then
				local ok, nf, why = attemptJob(ctx, job, an)
				if ok then
					an = computeGroups(g, nf)
					progressed = true
					break
				end
				failed[job.key] = true
				for _, i in ipairs(job.tiles) do failReasonAt[i] = why end
				if why == "budget" then audit.budgetHit = true; break end
			end
		end
		if not progressed or audit.budgetHit then break end
	end

	-- Residual audit (report step 12).
	local residual = 0
	for _, grp in ipairs(an.groups) do
		if isRepairTarget(grp) then
			residual = residual + 1
			if #audit.unrepaired < POCKET_UNREPAIRED_LOG then
				local reason = "not attempted"
				for _, i in ipairs(grp.tiles) do
					if failReasonAt[i] then reason = failReasonAt[i]; break end
				end
				local i1 = grp.tiles[1]
				local x1 = (i1 - 1) % w + 1
				table.insert(audit.unrepaired, {
					x = x1, y = (i1 - x1) / w + 1, size = #grp.tiles, kind = grp.kind,
					oneWay = grp.oneWay, keyTiles = grp.keyCount, reason = reason,
				})
			end
		end
	end
	audit.unrepairedCount = residual
	audit.pocketsFixed = math.max(0, found - residual)
	audit.ramps = ctx.accepted
	audit.rampsUndone = ctx.undone
	audit.tilesChanged = ctx.tilesChanged
	audit.keySnaps = ctx.keySnaps
	audit.keySnapRamps = ctx.keySnapRamps
	audit.relaxedRamps = ctx.relaxed
	audit.raiseFloors = ctx.raiseFloors
	pocketBusy = pocketBusy + (os.clock() - pocketSeg)
	audit.ms = pocketBusy * 1000

	-- LOG-001: one summary line per map (no per-tile output).
	print(string.format(
		"[ElevationPass] Phase 7b pocket breaker: %d pocket(s) found (%d one-way, %d with key tile; %d sealed-empty left), %d fixed, %d unrepaired; %d ramp(s) (%d undone by guard), %d tile(s) changed, %d key-snap(s), %d relaxed, %d raise-floor%s; %.1f ms",
		found, foundOneWay, foundKey, sealedEmpty, audit.pocketsFixed, residual,
		audit.ramps, audit.rampsUndone, audit.tilesChanged, audit.keySnaps,
		audit.relaxedRamps, audit.raiseFloors,
		audit.budgetHit and " (budget hit)" or "", audit.ms))
	return audit
end

--- Jump-1 walkability of the current map (the same walker Phase 7b repairs
--- against). Single source for ValidationPass V13. Read-only.
--- Index of tile (x, y) = (y - 1) * width + x.
function ElevationPass.AnalyzeWalkability(mapState)
	local g = buildWalkGraph(mapState.tiles, mapState.width, mapState.height)
	local an = computeGroups(g, computeFlows(g))
	local oneWay, keyOutside = 0, 0
	for _, grp in ipairs(an.groups) do
		if grp.kind == "trap" and grp.oneWay and #grp.tiles > 1 then oneWay = oneWay + 1 end
		keyOutside = keyOutside + grp.keyCount
	end
	return {
		width = g.w,
		main = an.main,       -- [index] = true: reach PD and walk back
		reach = an.F,         -- [index] = true: reachable from PD
		back = an.B,          -- [index] = true: can walk back to PD
		trapTiles = an.trapCount,
		oneWayPockets = oneWay,
		keyTilesOutsideMain = keyOutside,
		walkUp = WALK_UP,
		walkDown = WALK_DOWN,
	}
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
		-- OBS TWO-FORM SYSTEM (2026-10-12, map_gen_rules rows 75-92). Each contiguous
		-- OBS strip picks ONE form, seeded from the map seed via mapState.rng.obsFormRng
		-- (a dedicated child RNG created in MapService.createSeedContext; it is appended
		-- last so it does NOT perturb the other generation streams / existing seeds):
		--   SPIKE     -> raised +OBS_SPIKE terrain (unchanged math); scalable by high Jump.
		--   BLOCKER   -> normal elevation, tile.obsForm='blocker'; MapService.placeObjects
		--                materializes an impassable "OBS Blocker" object. (Flight pass-over,
		--                3-hit break, and push are PHASE 2 — Phase 1 = permanent wall.)
		--   BILLBOARD -> like blocker but tile.obsForm='billboard' -> "Ad Billboard" object
		--                (elevation-immune / unbreakable / immovable). At most ONE per map,
		--                on the OBS cluster NEAREST THE MAP CENTER (rows 79/84), any size.
		-- V5 SAFETY (runFinalValidation): an impassable object needs an adjacent passable
		-- interaction tile, so a cluster too THICK (any tile lacks a non-OBS passable
		-- cardinal neighbor) is FORCED to SPIKE — V5 then always holds and reachability is
		-- unaffected (OBS still blocks in BOTH forms: spike via elevation, blocker via object).
		-- DETERMINISM: clusters are built row-major (stable) and rolls draw in that order,
		-- so a given seed reproduces the same forms.
		local obsFormRng = mapState.rng and mapState.rng.obsFormRng

		-- 1) Group OBS tiles into 8-connected clusters, row-major (deterministic).
		local seen, clusters = {}, {}
		for y = 1, h do
			for x = 1, w do
				if tiles[y][x].marker == "OBS" and not seen[x .. "," .. y] then
					local cluster = {}
					local stack = { { x = x, y = y } }
					seen[x .. "," .. y] = true
					while #stack > 0 do
						local p = table.remove(stack)
						table.insert(cluster, p)
						for _, dir in ipairs(OBS_NEIGHBORS_8) do
							local nx, ny = p.x + dir.x, p.y + dir.y
							if isInBounds(nx, ny, w, h) and tiles[ny][nx].marker == "OBS"
								and not seen[nx .. "," .. ny] then
								seen[nx .. "," .. ny] = true
								table.insert(stack, { x = nx, y = ny })
							end
						end
					end
					table.insert(clusters, cluster)
				end
			end
		end

		-- 2) V5 thinness gate: every tile needs a non-OBS, passable-terrain cardinal neighbor.
		local function thinEnough(cluster)
			for _, p in ipairs(cluster) do
				local ok = false
				for _, dir in ipairs(CARDINAL) do
					local nx, ny = p.x + dir.x, p.y + dir.y
					if isInBounds(nx, ny, w, h) then
						local n = tiles[ny][nx]
						local tDef = TerrainData.Types[n.terrain]
						if n.marker ~= "OBS" and tDef and tDef.passable ~= false then
							ok = true
							break
						end
					end
				end
				if not ok then return false end
			end
			return true
		end

		local function roll()
			-- No RNG (should not happen) -> deterministic all-spike fallback (0 < 0.5 is false path).
			return obsFormRng and obsFormRng:NextNumber() or 1
		end

		-- 3) V5 thinness per cluster (reused for billboard eligibility AND the blocker roll).
		--    A cluster that is not thin can only ever be a SPIKE: blocker and billboard are
		--    both impassable OBJECTS, and V5 requires every impassable tile to keep an
		--    adjacent passable interaction tile. So a thick cluster is never billboard/blocker.
		local thin = {}
		for i, cluster in ipairs(clusters) do
			thin[i] = thinEnough(cluster)
		end

		-- 4) Billboard = the ONE OBS cluster NEAREST THE MAP CENTER (map_gen_rules rows 79/84):
		--    at most one per map, 1:1, independent of cluster size. Eligibility is limited to
		--    THIN clusters only (an impassable billboard on a thick cluster would break V5 /
		--    reachability exactly like a blocker would), so if the geometric centre cluster is
		--    thick the nearest THIN cluster wins; if NO cluster is thin there is no billboard.
		--    Distance = squared Euclidean from the cluster centroid to the map midpoint
		--    ((w+1)/2,(h+1)/2). Reachability is unaffected: the chosen cluster is OBS and
		--    impassable in every form, so billboard-vs-spike/blocker only changes HOW it blocks.
		local billboardIdx = nil
		do
			local cx, cy = (w + 1) / 2, (h + 1) / 2
			local bestD, tied = nil, {}
			for i, cluster in ipairs(clusters) do
				if thin[i] then
					local sx, sy = 0, 0
					for _, p in ipairs(cluster) do sx, sy = sx + p.x, sy + p.y end
					local n = #cluster
					local dx, dy = (sx / n) - cx, (sy / n) - cy
					local d = dx * dx + dy * dy
					if bestD == nil or d < bestD then
						bestD, tied = d, { i }
					elseif d == bestD then
						table.insert(tied, i)
					end
				end
			end
			if #tied == 1 then
				billboardIdx = tied[1]
			elseif #tied > 1 then
				-- Exact-tie break: deterministic draw from obsFormRng (seed-reproducible).
				local pick = obsFormRng and (math.floor(obsFormRng:NextNumber() * #tied) + 1) or 1
				if pick > #tied then pick = #tied end
				billboardIdx = tied[pick]
			end
		end

		-- Single-tile Ad Billboard (2026-10-15, Option 3): within the chosen cluster the
		-- billboard occupies exactly ONE tile — the one nearest the map centre (pure geometry,
		-- NO RNG, row-major tie-break -> deterministic). Every tile of a THIN cluster has a
		-- passable-terrain cardinal neighbour (thinEnough), so any tile is terrain-eligible;
		-- the object-level walled-in safety net (MapService placeObjects, BUG-042) still drops
		-- the single tile if a pool object leaves it with no passable neighbour.
		local function pickBillboardTile(cluster)
			local mcx, mcy = (w + 1) / 2, (h + 1) / 2
			local best, bestD = nil, nil
			for _, p in ipairs(cluster) do
				local dx, dy = p.x - mcx, p.y - mcy
				local d = dx * dx + dy * dy
				if bestD == nil or d < bestD then
					best, bestD = p, d
				end
			end
			return best
		end

		-- 5) Resolve + apply each cluster's form. The nearest-centre cluster HOSTS the one
		--    single-tile billboard (its other tiles become blocker-form OBS); every OTHER
		--    cluster takes the existing spike-vs-blocker roll unchanged.
		local spikeTiles, blockerStrips, billboardPlaced, maxRaised = 0, 0, false, 0
		for i, cluster in ipairs(clusters) do
			local form = "spike"
			local billboardPos = nil
			if i == billboardIdx then
				-- This cluster hosts the lone Ad Billboard: its tiles are blocker-form OBS,
				-- except the single centre-nearest tile picked here (Option 3, 2026-10-15).
				-- (Old behaviour marked EVERY tile "billboard" -> one Ad Billboard object per
				-- tile -> multiple panels; now it is exactly one object.)
				form = "blocker"
				billboardPos = pickBillboardTile(cluster)
				billboardPlaced = true
			else
				local r = roll()
				if thin[i] and r < 0.5 then
					form = "blocker"
				end
			end

			if form == "spike" then
				-- Measure each spike against NON-OBS 8-way neighbors only (blob tiles don't
				-- inflate each other); raise + flag isObstacle so later phases leave it intact.
				for _, pos in ipairs(cluster) do
					local tile = tiles[pos.y][pos.x]
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
					tile.elevation  = math.min(maxNb + OBS_SPIKE, peakE)
					tile.isObstacle = true
					tile.obsForm    = "spike"
					if tile.elevation > maxRaised then maxRaised = tile.elevation end
					spikeTiles = spikeTiles + 1
				end
			else
				-- BLOCKER / BILLBOARD: elevation stays NORMAL (not raised). We DO flag
				-- isObstacle so the generation validators that gate on it treat the strip
				-- as the wall it will be at runtime — specifically V13 OBJ-reachability
				-- (ValidationPass checks `not isObstacle`) runs BEFORE objects are
				-- materialized, so without this flag an objective reachable ONLY through a
				-- blocker strip would pass validation yet be walled off in game. Here
				-- isObstacle means "impassable OBS, elevation-locked", NOT "raised spike":
				-- it only steers generation (wall + no elevation grading). Runtime movement
				-- and LoS use GameConstants.IsBlocked (the materialized tile.object), never
				-- this flag. MapService.placeObjects materializes the object from obsForm.
				for _, pos in ipairs(cluster) do
					local t = tiles[pos.y][pos.x]
					-- Single-tile billboard: only the chosen tile is "billboard"; the rest of
					-- the cluster stays blocker-form OBS (preserves the barrier; one object).
					if billboardPos and pos.x == billboardPos.x and pos.y == billboardPos.y then
						t.obsForm = "billboard"
					else
						t.obsForm = form
					end
					t.isObstacle = true
				end
				blockerStrips = blockerStrips + 1
			end
		end

		if #clusters > 0 then
			print(string.format("[ElevationPass] Phase 2b: OBS two-form — %d strip(s): %d spike tile(s) (max %d, peak %d), %d blocker/billboard strip(s)%s.",
				#clusters, spikeTiles, maxRaised, peakE, blockerStrips,
				billboardPlaced and " (incl. 1 ad billboard)" or ""))
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
	-- PHASE 7b: Pocket breaker (2026-11-21, SIM_pocket_breaker_20261121 R1-final)
	-- Runs after 6b (cliff re-assert would undo the notches) and after 7 (gap
	-- depth is final, gap banks are locked). Repair-only, guarded, budgeted.
	-- See runPocketBreaker above for the walker, editable rules and guard.
	---------------------------------------------------------
	local pocketAudit = runPocketBreaker(mapState)

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
		pocketBreaker    = pocketAudit,
	}

	return mapState
end

return ElevationPass
