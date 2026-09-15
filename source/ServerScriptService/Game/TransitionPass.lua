-- TransitionPass.lua
-- CTRBLXAI | Feature Coherence System — Round 2
--
-- Enforces terrain compatibility rules after FeaturePass.
--
-- Phase 1: Hard prohibition enforcement.
--   Scans all 4-cardinal adjacencies against 11 prohibited pairs.
--   Replaces the non-feature-side tile with a compatible buffer.
--   3 passes to resolve cascading violations.
--
-- Phase 2: Soft transition buffer insertion.
--   Inserts gradual terrain transitions (e.g. Mud shorelines)
--   on the "To" side only if that tile is currently the specified
--   terrain. 2 passes.
--
-- Does NOT touch protected tiles (PD/ED/LAN).
-- Does NOT touch elevation.
--
-- Location: ServerScriptService/Game/TransitionPass.lua

local TransitionPass = {}

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

--------------------------------------------------
-- HARD PROHIBITION LOOKUP TABLES
--------------------------------------------------

--- Water terrains (Shallow Water, Deep Water).
local WATER_TERRAINS = {
	["Shallow Water"] = true,
	["Deep Water"]    = true,
}

--- Organic/flammable terrains incompatible with Molten.
local MOLTEN_INCOMPATIBLE = {
	["Grassland"]    = true,
	["Clover Field"] = true,
	["Wooden Floor"] = true,
	["Swamp"]        = true,
	["Ice"]          = true,
}

--- Water-family terrains incompatible with Quicksand.
local QUICKSAND_WATER = {
	["Shallow Water"] = true,
	["Deep Water"]    = true,
	["Swamp"]         = true,
}

--------------------------------------------------
-- PHASE 1: HARD PROHIBITION DETECTION
--------------------------------------------------

--- Check if (terrainA, terrainB) violates a hard prohibition.
--- Returns: bufferTerrain, preferredReplace ("A" or "B").
---   preferredReplace = the side that SHOULD be replaced.
---   "A" → replace tile A with buffer.
---   "B" → replace tile B with buffer.
--- Returns nil, nil if no violation.
local function getHardViolation(terrainA, terrainB)
	-- Molten cannot touch Water, Ice, or organic.
	if terrainA == "Molten" then
		if WATER_TERRAINS[terrainB] or MOLTEN_INCOMPATIBLE[terrainB] then
			return "Rocky", "B"
		end
	end
	if terrainB == "Molten" then
		if WATER_TERRAINS[terrainA] or MOLTEN_INCOMPATIBLE[terrainA] then
			return "Rocky", "A"
		end
	end

	-- Deep Water: can only touch Deep Water, Shallow Water, Rocky, Mud.
	if terrainA == "Deep Water" then
		if not WATER_TERRAINS[terrainB]
			and terrainB ~= "Rocky" and terrainB ~= "Mud" then
			return "Shallow Water", "B"
		end
	end
	if terrainB == "Deep Water" then
		if not WATER_TERRAINS[terrainA]
			and terrainA ~= "Rocky" and terrainA ~= "Mud" then
			return "Shallow Water", "A"
		end
	end

	-- Ice + Sand → Clear between.
	if terrainA == "Ice" and terrainB == "Sand" then return "Clear", "B" end
	if terrainA == "Sand" and terrainB == "Ice" then return "Clear", "A" end

	-- Quicksand + water → Sand between.
	if terrainA == "Quicksand" and QUICKSAND_WATER[terrainB] then
		return "Sand", "B"
	end
	if terrainB == "Quicksand" and QUICKSAND_WATER[terrainA] then
		return "Sand", "A"
	end

	-- Tainted Ground + Ice → Clear between.
	if terrainA == "Tainted Ground" and terrainB == "Ice" then
		return "Clear", "B"
	end
	if terrainA == "Ice" and terrainB == "Tainted Ground" then
		return "Clear", "A"
	end

	return nil, nil
end

--- Count how many 4-cardinal neighbors share the same terrain.
--- Higher = tile is more interior to a cluster → preserve it.
local function countMatchingNeighbors(x, y, tiles, w, h)
	local terrain = tiles[y][x].terrain
	local count   = 0
	for _, dir in ipairs(CARDINAL) do
		local nx, ny = x + dir.x, y + dir.y
		if isInBounds(nx, ny, w, h)
			and tiles[ny][nx].terrain == terrain then
			count = count + 1
		end
	end
	return count
end

--------------------------------------------------
-- PHASE 2: SOFT TRANSITION RULES
-- { from, toSet, buffer, exceptSet }
-- toSet   = set of terrains that trigger the buffer
--           (nil = special "any non-water" logic)
-- exceptSet = terrains on the "To" side that should NOT
--           be overwritten even if they match.
--------------------------------------------------

local SOFT_RULES = {
	{
		from      = "Shallow Water",
		toSet     = { ["Grassland"] = true },
		buffer    = "Mud",
		exceptSet = {},
	},
	{
		from      = "Deep Water",
		toSet     = nil,  -- special: any non-water
		buffer    = "Shallow Water",
		exceptSet = {
			["Shallow Water"] = true,
			["Deep Water"]    = true,
			["Mud"]           = true,
		},
	},
	{
		from      = "Ice",
		toSet     = { ["Grassland"] = true },
		buffer    = "Clear",
		exceptSet = {},
	},
	{
		from      = "Molten",
		toSet     = { ["Clear"] = true },
		buffer    = "Rocky",
		exceptSet = {},
	},
	{
		from      = "Metal",
		toSet     = { ["Grassland"] = true },
		buffer    = "Clear",
		exceptSet = {},
	},
	{
		from      = "Wooden Floor",
		toSet     = { ["Grassland"] = true },
		buffer    = "Clear",
		exceptSet = {},
	},
}

--------------------------------------------------
-- RUN
--------------------------------------------------

--- Enforce terrain compatibility rules on all tiles.
--- @param mapState table — the shared pipeline state
--- @return mapState (modified in-place)
function TransitionPass.Run(mapState)
	local tiles = mapState.tiles
	local w     = mapState.width
	local h     = mapState.height
	local ops   = 0

	---------------------------------------------------------
	-- PHASE 1: Hard prohibition enforcement (3 passes).
	---------------------------------------------------------
	for pass = 1, 3 do
		local anyChange = false

		for y = 1, h do
			for x = 1, w do
				local tileA = tiles[y][x]

				for _, dir in ipairs(CARDINAL) do
					local nx, ny = x + dir.x, y + dir.y
					if isInBounds(nx, ny, w, h) then
						local tileB = tiles[ny][nx]
						local buffer, preferred =
							getHardViolation(tileA.terrain, tileB.terrain)

						if buffer then
							-- Determine which tile to replace.
							local replaceA = (preferred == "A")

							-- If preferred side is protected, try the other.
							if replaceA and tileA.protected then
								replaceA = false
							end
							if not replaceA and tileB.protected then
								replaceA = true
							end

							-- Tie-break using cluster size if both are
							-- non-protected and the preferred side has a
							-- LARGER local cluster than the other side.
							if not tileA.protected and not tileB.protected then
								local matchA = countMatchingNeighbors(
									x, y, tiles, w, h)
								local matchB = countMatchingNeighbors(
									nx, ny, tiles, w, h)
								if matchA > matchB then
									-- A is more interior → preserve A.
									replaceA = false
								elseif matchB > matchA then
									-- B is more interior → preserve B.
									replaceA = true
								end
								-- On tie: keep the preferred direction.
							end

							-- Apply.
							if replaceA and not tileA.protected then
								tileA.terrain = buffer
								anyChange     = true
							elseif not replaceA and not tileB.protected then
								tileB.terrain = buffer
								anyChange     = true
							end
							-- else: both protected — cannot fix.
						end
					end
				end

				ops = ops + 1
				if ops % YIELD_INTERVAL == 0 then task.wait() end
			end
		end

		if not anyChange then break end
	end

	---------------------------------------------------------
	-- PHASE 2: Soft transition buffer insertion (2 passes).
	-- "Only insert if the target tile IS the 'To' terrain."
	---------------------------------------------------------
	for _ = 1, 2 do
		for _, rule in ipairs(SOFT_RULES) do
			for y = 1, h do
				for x = 1, w do
					if tiles[y][x].terrain == rule.from then
						for _, dir in ipairs(CARDINAL) do
							local nx, ny = x + dir.x, y + dir.y
							if isInBounds(nx, ny, w, h) then
								local nTile = tiles[ny][nx]
								if not nTile.protected then
									local shouldReplace = false

									if rule.toSet == nil then
										-- "Any non-water" special case.
										if not WATER_TERRAINS[nTile.terrain]
											and not rule.exceptSet[nTile.terrain] then
											shouldReplace = true
										end
									elseif rule.toSet[nTile.terrain] then
										shouldReplace = true
									end

									if shouldReplace then
										nTile.terrain = rule.buffer
									end
								end
							end
						end
					end

					ops = ops + 1
					if ops % YIELD_INTERVAL == 0 then task.wait() end
				end
			end
		end
	end

	print("[TransitionPass] Complete.")
	return mapState
end

return TransitionPass
