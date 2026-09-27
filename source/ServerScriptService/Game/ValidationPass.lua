-- ValidationPass.lua
-- CTRBLXAI | Feature Coherence System — Round 5
--
-- Final coherence validation after all passes have run.
-- Checks the DB's Validation Matrix plus feature-specific coherence rules.
-- Reports violations but does NOT fix them (read-only audit).
--
-- Pipeline position: runs AFTER ElevationPass (last pass).
-- Does NOT modify any tiles.
--
-- 12 checks (V1-V12):
--   V1:  Terrain Fill           — every tile has a valid terrain ID
--   V2:  Elevation Fill         — every tile has elevation in biome range
--   V3:  Terrain Reference      — every terrain ID resolves in TerrainData
--   V4:  Hard Prohibition Clean — no cardinal pair violates hard prohibitions
--   V5:  Deep Water Interior    — Deep Water has only water-family neighbors
--   V6:  LAN Jump=1             — adjacent LAN-family tiles ≤ 1 elev diff
--   V7:  Protected Passability  — PD/ED/LAN tiles have passable terrain
--   V8:  Quicksand Safety       — Quicksand has Sand on all 4 cardinals
--   V9:  Molten Buffer          — Molten has Rocky/Sand on all non-Molten cardinals
--   V10: Minimum Feature Cluster — no isolated special terrain tiles
--   V11: Deployment Anchors     — ≥ 3 PD + ≥ 3 ED anchors
--   V12: Biome-Specific Checks  — biome-required terrains present
--
-- Location: ServerScriptService/Game/ValidationPass.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Content      = ReplicatedStorage:WaitForChild("Content")
local TerrainData  = require(Content:WaitForChild("TerrainData"))
local ObjectData   = require(Content:WaitForChild("ObjectData"))

local ValidationPass = {}

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

local CARDINAL = {
	{ x =  0, y =  1 },
	{ x =  0, y = -1 },
	{ x =  1, y =  0 },
	{ x = -1, y =  0 },
}

local function isInBounds(x, y, w, h)
	return x >= 1 and x <= w and y >= 1 and y <= h
end

-- (LAN_FAMILY removed 2026-09-24: V6 repurposed from LAN-family pairwise
-- flatness to a PD→ED connectivity BFS, which does not need this set.)

-- Water-family terrains for Deep Water interior check.
local WATER_FAMILY = {
	["Shallow Water"] = true,
	["Deep Water"]    = true,
	["Swamp"]         = true,
	["Mud"]           = true,
}

-- Organic/water terrains incompatible with Molten (cardinal).
local MOLTEN_INCOMPATIBLE = {
	["Grassland"]     = true,
	["Clover Field"]  = true,
	["Wooden Floor"]  = true,
	["Swamp"]         = true,
	["Ice"]           = true,
	["Shallow Water"] = true,
	["Deep Water"]    = true,
}

-- Quicksand water-family incompatibility.
local QUICKSAND_WATER = {
	["Shallow Water"] = true,
	["Deep Water"]    = true,
	["Swamp"]         = true,
}

-- Special terrain types that need cluster validation (V10).
local CLUSTER_TERRAINS = {
	["Shallow Water"] = true,
	["Deep Water"]    = true,
	["Molten"]        = true,
	["Ice"]           = true,
}

-- Compatible neighbor terrains for cluster check.
local CLUSTER_COMPAT = {
	["Shallow Water"] = { ["Shallow Water"] = true, ["Deep Water"] = true, ["Mud"] = true, ["Swamp"] = true },
	["Deep Water"]    = { ["Deep Water"] = true, ["Shallow Water"] = true },
	["Molten"]        = { ["Molten"] = true, ["Rocky"] = true },
	["Ice"]           = { ["Ice"] = true, ["Shallow Water"] = true, ["Rocky"] = true },
}

--------------------------------------------------
-- HARD PROHIBITION CHECK (mirrors TransitionPass Phase 1)
-- Returns violation string or nil.
--------------------------------------------------

local function checkHardProhibition(terrainA, terrainB)
	-- Molten cannot touch Water, Ice, or organic.
	if terrainA == "Molten" then
		if MOLTEN_INCOMPATIBLE[terrainB] then
			return "Molten|" .. terrainB
		end
	end
	if terrainB == "Molten" then
		if MOLTEN_INCOMPATIBLE[terrainA] then
			return terrainA .. "|Molten"
		end
	end

	-- Deep Water: can only touch Deep Water, Shallow Water, Rocky, Mud.
	if terrainA == "Deep Water" then
		if not WATER_FAMILY[terrainB]
			and terrainB ~= "Rocky" then
			return "Deep Water|" .. terrainB
		end
	end
	if terrainB == "Deep Water" then
		if not WATER_FAMILY[terrainA]
			and terrainA ~= "Rocky" then
			return terrainA .. "|Deep Water"
		end
	end

	-- Ice + Sand.
	if (terrainA == "Ice" and terrainB == "Sand")
		or (terrainA == "Sand" and terrainB == "Ice") then
		return "Ice|Sand"
	end

	-- Quicksand + water.
	if terrainA == "Quicksand" and QUICKSAND_WATER[terrainB] then
		return "Quicksand|" .. terrainB
	end
	if terrainB == "Quicksand" and QUICKSAND_WATER[terrainA] then
		return terrainA .. "|Quicksand"
	end

	-- Tainted Ground + Ice.
	if (terrainA == "Tainted Ground" and terrainB == "Ice")
		or (terrainA == "Ice" and terrainB == "Tainted Ground") then
		return "Tainted Ground|Ice"
	end

	return nil
end

--------------------------------------------------
-- RUN
--------------------------------------------------

--- Run all 12 validation checks against the completed mapState.
--- Adds mapState.validationReport. Does NOT modify tiles.
--- @param mapState table — the shared pipeline state (post-ElevationPass)
--- @return mapState (unmodified tiles, report added)
function ValidationPass.Run(mapState)
	local tiles   = mapState.tiles
	local w       = mapState.width
	local h       = mapState.height
	local biomeId = mapState.biomeId
	local biomeElev = mapState.biomeElevation

	local checks = {}

	--------------------------------------------------
	-- V1: Terrain Fill
	--------------------------------------------------
	local v1Violations = {}
	for y = 1, h do
		for x = 1, w do
			local t = tiles[y][x].terrain
			if t == nil then
				table.insert(v1Violations,
					string.format("(%d,%d) nil terrain", x, y))
			end
		end
	end
	table.insert(checks, {
		id = "V1", name = "Terrain Fill",
		passed = #v1Violations == 0,
		violations = #v1Violations > 0 and v1Violations or nil,
	})

	--------------------------------------------------
	-- V2: Elevation Fill
	--------------------------------------------------
	local v2Violations = {}
	-- Validate against the GLOBAL elevation scale, not the per-biome land
	-- band. Water/pits legitimately sit below the biome's land min (down to
	-- the global floor), and ADV bonuses can reach the global peak
	-- (dev-locked 2026-09-24: floor=1, peak=20).
	local eMin         = biomeElev and biomeElev.floor or 1
	local effectiveMax = biomeElev and biomeElev.peak  or 20
	for y = 1, h do
		for x = 1, w do
			local e = tiles[y][x].elevation
			if e == nil or e ~= e then
				table.insert(v2Violations,
					string.format("(%d,%d) invalid elevation: %s", x, y, tostring(e)))
			elseif e < eMin or e > effectiveMax then
				table.insert(v2Violations,
					string.format("(%d,%d) elevation %d outside [%d,%d]",
						x, y, e, eMin, effectiveMax))
			end
		end
	end
	table.insert(checks, {
		id = "V2", name = "Elevation Fill",
		passed = #v2Violations == 0,
		violations = #v2Violations > 0 and v2Violations or nil,
	})

	--------------------------------------------------
	-- V3: Terrain Reference Resolution
	--------------------------------------------------
	local v3Violations = {}
	local seenBadTerrain = {}
	for y = 1, h do
		for x = 1, w do
			local t = tiles[y][x].terrain
			if t and not TerrainData.Types[t] and not seenBadTerrain[t] then
				seenBadTerrain[t] = true
				table.insert(v3Violations,
					string.format("Unresolved terrain ID: '%s' (first at %d,%d)", t, x, y))
			end
		end
	end
	table.insert(checks, {
		id = "V3", name = "Terrain Reference",
		passed = #v3Violations == 0,
		violations = #v3Violations > 0 and v3Violations or nil,
	})

	--------------------------------------------------
	-- V4: Hard Prohibition Clean
	-- Check all 4-cardinal adjacent pairs.
	-- Only report first 20 violations to avoid flooding.
	--------------------------------------------------
	local v4Violations = {}
	local v4Limit = 20
	for y = 1, h do
		for x = 1, w do
			if #v4Violations >= v4Limit then break end
			local tA = tiles[y][x].terrain
			-- Check only right and down to avoid double-counting.
			for _, dir in ipairs(CARDINAL) do
				if dir.x > 0 or dir.y > 0 then
					local nx, ny = x + dir.x, y + dir.y
					if isInBounds(nx, ny, w, h) then
						local tB = tiles[ny][nx].terrain
						if tA and tB then
							local viol = checkHardProhibition(tA, tB)
							if viol then
								table.insert(v4Violations,
									string.format("(%d,%d)↔(%d,%d): %s",
										x, y, nx, ny, viol))
							end
						end
					end
				end
			end
		end
	end
	table.insert(checks, {
		id = "V4", name = "Hard Prohibition Clean",
		passed = #v4Violations == 0,
		violations = #v4Violations > 0 and v4Violations or nil,
	})

	--------------------------------------------------
	-- V5: Deep Water Interior
	-- Every Deep Water tile must have only water-family or Rocky neighbors.
	--------------------------------------------------
	local v5Violations = {}
	for y = 1, h do
		for x = 1, w do
			if tiles[y][x].terrain == "Deep Water" then
				for _, dir in ipairs(CARDINAL) do
					local nx, ny = x + dir.x, y + dir.y
					if isInBounds(nx, ny, w, h) then
						local nt = tiles[ny][nx].terrain
						if nt and not WATER_FAMILY[nt] and nt ~= "Rocky" then
							table.insert(v5Violations,
								string.format("(%d,%d) Deep Water neighbor (%d,%d)=%s",
									x, y, nx, ny, nt))
							break  -- one violation per tile is enough
						end
					else
						-- Edge of map — Deep Water at border is acceptable.
					end
				end
			end
		end
	end
	table.insert(checks, {
		id = "V5", name = "Deep Water Interior",
		passed = #v5Violations == 0,
		violations = #v5Violations > 0 and v5Violations or nil,
	})

	--------------------------------------------------
	-- V6: PD→ED Connectivity (dev-locked 2026-09-24)
	-- REPURPOSED: the old check asserted "all LAN-family neighbors ≤1
	-- apart", which was the obsolete flat-everything contract. After the
	-- elevation rework, HZD/BLK/ADV legitimately sit at cliff elevations,
	-- so pairwise LAN-family flatness is no longer the invariant. The real
	-- invariant is: a ≤1-step walkable path exists from PD to ED. This
	-- mirrors validateConnectivity (the actual generation gate) and is
	-- guaranteed by ElevationPass Phase 6 (corridor ramp).
	--------------------------------------------------
	local v6Violations = {}
	do
		-- BFS from all PD tiles over passable, ≤1-elevation-step tiles.
		local function keyOf(x, y) return y * 100000 + x end
		local pdList, edSet = {}, {}
		for y = 1, h do
			for x = 1, w do
				local m = tiles[y][x].marker
				if m == "PD" then
					table.insert(pdList, { x = x, y = y })
				elseif m == "ED" then
					edSet[keyOf(x, y)] = true
				end
			end
		end

		local reachedED = false
		if #pdList > 0 and next(edSet) ~= nil then
			local visited, queue, qHead = {}, {}, 1
			for _, pos in ipairs(pdList) do
				local k = keyOf(pos.x, pos.y)
				if not visited[k] then visited[k] = true; table.insert(queue, pos) end
			end
			while qHead <= #queue do
				local cur  = queue[qHead]; qHead = qHead + 1
				local tile = tiles[cur.y][cur.x]
				if edSet[keyOf(cur.x, cur.y)] then reachedED = true; break end
				for _, dir in ipairs(CARDINAL) do
					local nx, ny = cur.x + dir.x, cur.y + dir.y
					if isInBounds(nx, ny, w, h) then
						local nk = keyOf(nx, ny)
						if not visited[nk] then
							local nTile = tiles[ny][nx]
							local tDef  = TerrainData.Types[nTile.terrain]
							local pass  = tDef and tDef.passable ~= false
							local noBlock = nTile.object == nil
								or (ObjectData.Objects[nTile.object]
									and ObjectData.Objects[nTile.object].passable)
							local elevOk = math.abs(tile.elevation - nTile.elevation) <= 1
							if pass and noBlock and elevOk then
								visited[nk] = true
								table.insert(queue, { x = nx, y = ny })
							end
						end
					end
				end
			end
		end
		if not reachedED then
			table.insert(v6Violations, "No ≤1-step PD→ED path exists")
		end
	end
	table.insert(checks, {
		id = "V6", name = "PD→ED Connectivity",
		passed = #v6Violations == 0,
		violations = #v6Violations > 0 and v6Violations or nil,
	})

	--------------------------------------------------
	-- V7: Protected Tile Passability
	-- PD/ED/LAN tiles must have passable terrain.
	--------------------------------------------------
	local v7Violations = {}
	local PASSABLE_REQUIRED = { PD = true, ED = true, LAN = true }
	for y = 1, h do
		for x = 1, w do
			local tile = tiles[y][x]
			if PASSABLE_REQUIRED[tile.marker] then
				local tDef = TerrainData.Types[tile.terrain]
				if tDef and tDef.passable == false then
					table.insert(v7Violations,
						string.format("(%d,%d) %s marker has impassable terrain: %s",
							x, y, tile.marker, tostring(tile.terrain)))
				end
			end
		end
	end
	table.insert(checks, {
		id = "V7", name = "Protected Passability",
		passed = #v7Violations == 0,
		violations = #v7Violations > 0 and v7Violations or nil,
	})

	--------------------------------------------------
	-- V8: Quicksand Safety
	-- Every Quicksand tile needs Sand on all 4 cardinals.
	-- No Quicksand on PD/ED/LAN tiles.
	--------------------------------------------------
	local v8Violations = {}
	for y = 1, h do
		for x = 1, w do
			local tile = tiles[y][x]
			if tile.terrain == "Quicksand" then
				-- Protected marker check.
				if tile.marker == "PD" or tile.marker == "ED"
					or tile.marker == "LAN" then
					table.insert(v8Violations,
						string.format("(%d,%d) Quicksand on %s marker",
							x, y, tile.marker))
				end
				-- Cardinal Sand check.
				for _, dir in ipairs(CARDINAL) do
					local nx, ny = x + dir.x, y + dir.y
					if isInBounds(nx, ny, w, h) then
						local nt = tiles[ny][nx].terrain
						if nt ~= "Sand" and nt ~= "Quicksand" then
							table.insert(v8Violations,
								string.format("(%d,%d) Quicksand neighbor (%d,%d)=%s (need Sand)",
									x, y, nx, ny, tostring(nt)))
							break
						end
					else
						table.insert(v8Violations,
							string.format("(%d,%d) Quicksand at map edge", x, y))
						break
					end
				end
			end
		end
	end
	table.insert(checks, {
		id = "V8", name = "Quicksand Safety",
		passed = #v8Violations == 0,
		violations = #v8Violations > 0 and v8Violations or nil,
	})

	--------------------------------------------------
	-- V9: Molten Buffer
	-- Every Molten tile needs Rocky or Sand (or Molten) on all 4 cardinals.
	-- No organic/water neighbors.
	--------------------------------------------------
	local v9Violations = {}
	for y = 1, h do
		for x = 1, w do
			if tiles[y][x].terrain == "Molten" then
				for _, dir in ipairs(CARDINAL) do
					local nx, ny = x + dir.x, y + dir.y
					if isInBounds(nx, ny, w, h) then
						local nt = tiles[ny][nx].terrain
						if nt and MOLTEN_INCOMPATIBLE[nt] then
							table.insert(v9Violations,
								string.format("(%d,%d) Molten neighbor (%d,%d)=%s",
									x, y, nx, ny, nt))
							break
						end
					end
				end
			end
		end
	end
	table.insert(checks, {
		id = "V9", name = "Molten Buffer",
		passed = #v9Violations == 0,
		violations = #v9Violations > 0 and v9Violations or nil,
	})

	--------------------------------------------------
	-- V10: Minimum Feature Clusters
	-- No isolated single special-terrain tiles.
	-- Each must have ≥ 1 compatible cardinal neighbor.
	--------------------------------------------------
	local v10Violations = {}
	for y = 1, h do
		for x = 1, w do
			local t = tiles[y][x].terrain
			if t and CLUSTER_TERRAINS[t] then
				local compat = CLUSTER_COMPAT[t]
				local hasNeighbor = false
				for _, dir in ipairs(CARDINAL) do
					local nx, ny = x + dir.x, y + dir.y
					if isInBounds(nx, ny, w, h) then
						local nt = tiles[ny][nx].terrain
						if nt and compat[nt] then
							hasNeighbor = true
							break
						end
					end
				end
				if not hasNeighbor then
					table.insert(v10Violations,
						string.format("(%d,%d) isolated %s tile", x, y, t))
				end
			end
		end
	end
	table.insert(checks, {
		id = "V10", name = "Min Feature Clusters",
		passed = #v10Violations == 0,
		violations = #v10Violations > 0 and v10Violations or nil,
	})

	--------------------------------------------------
	-- V11: Deployment Anchor Count
	-- At least 3 PD and 3 ED passable, unoccupied tiles.
	--------------------------------------------------
	local pdCount = 0
	local edCount = 0
	for y = 1, h do
		for x = 1, w do
			local tile = tiles[y][x]
			local tDef = TerrainData.Types[tile.terrain]
			local passable   = tDef and tDef.passable ~= false
			local unoccupied = tile.object == nil
			if passable and unoccupied then
				if tile.marker == "PD" then
					pdCount = pdCount + 1
				elseif tile.marker == "ED" then
					edCount = edCount + 1
				end
			end
		end
	end
	local v11Violations = {}
	if pdCount < 3 then
		table.insert(v11Violations,
			string.format("Only %d PD anchors (need ≥ 3)", pdCount))
	end
	if edCount < 3 then
		table.insert(v11Violations,
			string.format("Only %d ED anchors (need ≥ 3)", edCount))
	end
	table.insert(checks, {
		id = "V11", name = "Deployment Anchors",
		passed = #v11Violations == 0,
		violations = #v11Violations > 0 and v11Violations or nil,
	})

	--------------------------------------------------
	-- V12: Biome-Specific Checks
	--------------------------------------------------
	local v12Violations = {}

	-- Build a set of all terrain types on the map for fast lookup.
	local terrainPresent = {}
	for y = 1, h do
		for x = 1, w do
			local t = tiles[y][x].terrain
			if t then terrainPresent[t] = true end
		end
	end

	-- Biome-required terrains.
	local BIOME_REQUIREMENTS = {
		Tundra    = { terrain = "Ice",            label = "Ice" },
		Volcano   = { terrain = "Molten",         label = "Molten" },
		Swamp     = { terrain = "Swamp",          label = "Swamp" },
		Castle    = { terrains = { "Metal", "Wooden Floor" },
		              label = "Metal or Wooden Floor" },
		Corrupted = { terrain = "Tainted Ground", label = "Tainted Ground" },
		Cave      = { terrain = "Rocky",          label = "Rocky" },
	}

	local req = BIOME_REQUIREMENTS[biomeId]
	if req then
		local found = false
		if req.terrain then
			found = terrainPresent[req.terrain] == true
		elseif req.terrains then
			for _, t in ipairs(req.terrains) do
				if terrainPresent[t] then found = true; break end
			end
		end
		if not found then
			table.insert(v12Violations,
				string.format("%s: no %s tiles found", biomeId, req.label))
		end
	end

	table.insert(checks, {
		id = "V12", name = "Biome Checks",
		passed = #v12Violations == 0,
		violations = #v12Violations > 0 and v12Violations or nil,
	})

	--------------------------------------------------
	-- Build report and print summary.
	--------------------------------------------------
	local passedCount   = 0
	local failedIds     = {}
	local totalViolations = 0

	for _, check in ipairs(checks) do
		if check.passed then
			passedCount = passedCount + 1
		else
			table.insert(failedIds, check.id)
			if check.violations then
				totalViolations = totalViolations + #check.violations
			end
		end
	end

	local allPassed = passedCount == #checks

	mapState.validationReport = {
		passed          = allPassed,
		checks          = checks,
		totalViolations = totalViolations,
	}

	if allPassed then
		print(string.format(
			"[ValidationPass] PASSED (%d/%d checks)",
			passedCount, #checks))
	else
		print(string.format(
			"[ValidationPass] FAILED (%d/%d checks, %d violation(s): %s)",
			passedCount, #checks, totalViolations,
			table.concat(failedIds, ", ")))
		-- Log first few violations per failed check.
		for _, check in ipairs(checks) do
			if not check.passed and check.violations then
				print(string.format("  [%s] %s:", check.id, check.name))
				local logLimit = math.min(5, #check.violations)
				for vi = 1, logLimit do
					print("    " .. check.violations[vi])
				end
				if #check.violations > logLimit then
					print(string.format(
						"    ... and %d more", #check.violations - logLimit))
				end
			end
		end
	end

	return mapState
end

return ValidationPass
