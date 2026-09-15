-- MapService.lua
-- CTRBLXAI | Feature Coherence System — Round 1
--
-- Thin orchestrator calling pass modules in sequence.
-- 11-step deterministic pipeline: biome + template → playable battlefield.
--
-- Pass pipeline:
--   FloorPass      — Floor terrain per region (uniform, no scatter)
--   FeaturePass    — 14 feature types (Round 2-4, stub)
--   TransitionPass — Prohibitions + buffers (Round 2, stub)
--   ElevationPass  — Terrain-correlated elevation
--   ValidationPass — Coherence validation (Round 5, stub)
--
-- This module does not create Roblox Instances.
-- It produces a data table consumed by GameConstants.SetGeneratedMap().
--
-- Location: ServerScriptService/Game/MapService.lua

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local Content = ReplicatedStorage:WaitForChild("Content")
local BiomeData   = require(Content:WaitForChild("BiomeData"))
local RegionData  = require(Content:WaitForChild("RegionData"))
local TerrainData = require(Content:WaitForChild("TerrainData"))
local ObjectData  = require(Content:WaitForChild("ObjectData"))

local RegionGenerator = require(
	ServerScriptService:WaitForChild("RegionGenerator")
)

-- Pass modules (sibling scripts in Game/).
local FloorPass     = require(script.Parent:WaitForChild("FloorPass"))
local ElevationPass = require(script.Parent:WaitForChild("ElevationPass"))
local FeaturePass     = require(script.Parent:WaitForChild("FeaturePass"))
local TransitionPass  = require(script.Parent:WaitForChild("TransitionPass"))
local ValidationPass  = require(script.Parent:WaitForChild("ValidationPass"))

-- Template registry — add future templates here.
local TemplateRegistry = {
	T01 = require(
		ReplicatedStorage
			:WaitForChild("CTRBLXAI")
			:WaitForChild("Templates")
			:WaitForChild("T01_FrontlinePressure")
	),
	T02 = require(
		ReplicatedStorage
			:WaitForChild("CTRBLXAI")
			:WaitForChild("Templates")
			:WaitForChild("T02_SplitPressure")
	),
	T03 = require(
		ReplicatedStorage
			:WaitForChild("CTRBLXAI")
			:WaitForChild("Templates")
			:WaitForChild("T03_BrokenCrossing")
	),
	T04 = require(
		ReplicatedStorage
			:WaitForChild("CTRBLXAI")
			:WaitForChild("Templates")
			:WaitForChild("T04_BossRingFixed")
	),
	T05 = require(
		ReplicatedStorage
			:WaitForChild("CTRBLXAI")
			:WaitForChild("Templates")
			:WaitForChild("T05_DefenseCenter")
	),
	T06 = require(
		ReplicatedStorage
			:WaitForChild("CTRBLXAI")
			:WaitForChild("Templates")
			:WaitForChild("T06_AdvantageContest")
	),
	T07 = require(
		ReplicatedStorage
			:WaitForChild("CTRBLXAI")
			:WaitForChild("Templates")
			:WaitForChild("T07_WaveSurvival")
	),
	T08 = require(
		ReplicatedStorage
			:WaitForChild("CTRBLXAI")
			:WaitForChild("Templates")
			:WaitForChild("T08_AmbushPincer")
	),
}

local MapService = {}

--------------------------------------------------
-- MAP CACHE
-- First Generate() call produces the map; subsequent
-- calls with the same biome+template return the cache.
--------------------------------------------------
local _cachedMap = nil
--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

local CARDINAL = {
	{ x =  0, y =  1 },
	{ x =  0, y = -1 },
	{ x =  1, y =  0 },
	{ x = -1, y =  0 },
}

local MAX_GENERATION_ATTEMPTS = 3
local YIELD_INTERVAL          = 100   -- task.wait() every N operations
local MAX_SEED                = 2147483647  -- 2^31 - 1

-- Biome → eligible region type pool.
-- Each generated region is assigned a type from this pool.
local BIOME_REGION_POOLS = {
	Plains = {
		{ type = "Grassland", weight = 50 },
		{ type = "Clearing",  weight = 30 },
		{ type = "Farmland",  weight = 20 },
	},
	Forest = {
		{ type = "Forest",    weight = 45 },
		{ type = "Clearing",  weight = 25 },
		{ type = "Grassland", weight = 15 },
		{ type = "Riverbank", weight = 15 },
	},
	Desert = {
		{ type = "Rocky",     weight = 40 },
		{ type = "Beach",     weight = 30 },
		{ type = "Clearing",  weight = 20 },
		{ type = "Grassland", weight = 10 },
	},
	Swamp = {
		{ type = "Marsh",     weight = 45 },
		{ type = "Riverbank", weight = 25 },
		{ type = "Forest",    weight = 15 },
		{ type = "Clearing",  weight = 15 },
	},
	Highlands = {
		{ type = "Rocky",         weight = 40 },
		{ type = "Mountain Pass", weight = 35 },
		{ type = "Grassland",     weight = 15 },
		{ type = "Clearing",      weight = 10 },
	},
	Tundra = {
		{ type = "Frozen Lake", weight = 45 },
		{ type = "Rocky",       weight = 30 },
		{ type = "Grassland",   weight = 15 },
		{ type = "Clearing",    weight = 10 },
	},
	Volcano = {
		{ type = "Volcanic Rock", weight = 45 },
		{ type = "Lava Channel",  weight = 25 },
		{ type = "Rocky",         weight = 20 },
		{ type = "Clearing",      weight = 10 },
	},
	Cave = {
		{ type = "Cave Chamber", weight = 50 },
		{ type = "Rocky",        weight = 30 },
		{ type = "Clearing",     weight = 20 },
	},
	Ruins = {
		{ type = "Ruins",     weight = 45 },
		{ type = "Rocky",     weight = 25 },
		{ type = "Graveyard", weight = 15 },
		{ type = "Clearing",  weight = 15 },
	},
	Castle = {
		{ type = "Castle Courtyard", weight = 40 },
		{ type = "Castle Interior",  weight = 30 },
		{ type = "Rocky",            weight = 15 },
		{ type = "Clearing",         weight = 15 },
	},
	Corrupted = {
		{ type = "Corrupted", weight = 45 },
		{ type = "Graveyard", weight = 25 },
		{ type = "Marsh",     weight = 15 },
		{ type = "Forest",    weight = 15 },
	},
}

-- Elevation range per biome.
-- lanMin/lanMax: constrained range for LAN-family tiles.
-- advBonus: extra elevation added to ADV marker tiles.
local BIOME_ELEVATION = {
	Plains = {
		min      = 1,
		max      = 3,
		lanMin   = 1,
		lanMax   = 2,
		advBonus = 2,
	},
	Forest = {
		min = 1, max = 3, lanMin = 1, lanMax = 2, advBonus = 2,
	},
	Desert = {
		min = 1, max = 4, lanMin = 1, lanMax = 3, advBonus = 2,
	},
	Swamp = {
		min = 1, max = 2, lanMin = 1, lanMax = 2, advBonus = 1,
	},
	Highlands = {
		min = 1, max = 6, lanMin = 1, lanMax = 3, advBonus = 2,
	},
	Tundra = {
		min = 1, max = 3, lanMin = 1, lanMax = 2, advBonus = 2,
	},
	Volcano = {
		min = 1, max = 5, lanMin = 1, lanMax = 3, advBonus = 2,
	},
	Cave = {
		min = 1, max = 4, lanMin = 1, lanMax = 3, advBonus = 2,
	},
	Ruins = {
		min = 1, max = 4, lanMin = 1, lanMax = 3, advBonus = 2,
	},
	Castle = {
		min = 1, max = 5, lanMin = 1, lanMax = 3, advBonus = 2,
	},
	Corrupted = {
		min = 1, max = 3, lanMin = 1, lanMax = 2, advBonus = 2,
	},
}

local DEFAULT_ELEVATION = {
	min = 1, max = 3, lanMin = 1, lanMax = 2, advBonus = 1,
}

-- Object placement density per template marker (fraction of tiles).
-- 0 = no objects allowed in that marker zone.
local MARKER_OBJECT_DENSITY = {
	PD  = 0,
	ED  = 0,
	LAN = 0.02,
	HZD = 0.12,
	BLK = 0.15,
	POI = 0.08,
	ADV = 0.08,
	NEU = 0.03,
	WAT = 0.04,
}

-- Markers that require passable terrain (PD/ED/LAN).
local PASSABLE_REQUIRED = {
	PD  = true,
	ED  = true,
	LAN = true,
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

--------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------

local function isInBounds(x, y, w, h)
	return x >= 1 and x <= w and y >= 1 and y <= h
end

local function coordKey(x, y)
	return y * 100000 + x
end

--- Weighted random selection from a { key = weight } table.
--- `validator` filters entries (nil = accept all).
--- Keys are sorted alphabetically for deterministic iteration order.
--- Returns fallback when no valid entries exist.
local function weightedSelect(weights, rng, validator, fallback)
	local entries = {}
	local total   = 0

	for key, w in pairs(weights) do
		if (not validator) or validator(key) then
			total = total + w
			table.insert(entries, { key = key, w = w })
		end
	end

	if total == 0 then
		return fallback
	end

	-- Sort for deterministic traversal regardless of hash order.
	table.sort(entries, function(a, b) return a.key < b.key end)

	local roll = rng:NextNumber() * total
	local acc  = 0

	for _, e in ipairs(entries) do
		acc = acc + e.w
		if roll <= acc then
			return e.key
		end
	end

	return entries[#entries].key
end

--- Weighted select from an array of { type = string, weight = number }.
local function weightedSelectArray(pool, rng)
	local total = 0
	for _, e in ipairs(pool) do
		total = total + e.weight
	end

	if total == 0 then
		return pool[1] and pool[1].type or "Grassland"
	end

	local roll = rng:NextNumber() * total
	local acc  = 0

	for _, e in ipairs(pool) do
		acc = acc + e.weight
		if roll <= acc then return e.type end
	end

	return pool[#pool].type
end

--------------------------------------------------
-- TERRAIN VALIDATORS
-- Used by FeaturePass (Round 2) and object placement.
-- Gracefully skips unresolved terrain IDs.
--------------------------------------------------

local function validTerrain(id)
	return TerrainData.Types[id] ~= nil
end

local function validPassableTerrain(id)
	local t = TerrainData.Types[id]
	return t ~= nil and t.passable ~= false
end

--------------------------------------------------
-- STEP 1 + 2: LOAD TEMPLATE AND BIOME
--------------------------------------------------

local function loadTemplate(templateId)
	local template = TemplateRegistry[templateId]
	if not template then
		error("[MapService] Unknown template: " .. tostring(templateId))
	end
	return template
end

local function loadBiome(biomeId)
	local biome = BiomeData[biomeId]
	if not biome then
		error("[MapService] Unknown biome: " .. tostring(biomeId))
	end
	return biome
end

--------------------------------------------------
-- STEP 3: SEED CONTEXT
-- Derives sub-seeds from the master seed so that each
-- phase of generation uses an independent RNG stream.
-- Same master seed → same sub-seeds → deterministic.
--------------------------------------------------

local function createSeedContext(seed)
	if seed == nil then
		seed = math.floor(os.clock() * 1000000) % MAX_SEED
		if seed < 1 then seed = 1 end
	end

	local master = Random.new(seed)

	return {
		seed         = seed,
		regionSeed   = master:NextInteger(1, MAX_SEED),
		terrainRng   = Random.new(master:NextInteger(1, MAX_SEED)),
		elevationRng = Random.new(master:NextInteger(1, MAX_SEED)),
		objectRng    = Random.new(master:NextInteger(1, MAX_SEED)),
		conditionRng = Random.new(master:NextInteger(1, MAX_SEED)),
		deployRng    = Random.new(master:NextInteger(1, MAX_SEED)),
		featureRng   = Random.new(master:NextInteger(1, MAX_SEED)),
	}
end

--------------------------------------------------
-- STEP 4: INITIALIZE TILES
-- Create the tile grid with template markers.
-- Terrain and elevation are filled by the passes.
--------------------------------------------------

local function initializeTiles(w, h, template)
	local tiles = {}

	for y = 1, h do
		tiles[y] = {}

		for x = 1, w do
			local marker = (template.Grid[y] and template.Grid[y][x]) or "NEU"

			tiles[y][x] = {
				terrain   = nil,      -- FloorPass fills this
				elevation = 1,        -- ElevationPass fills this
				object    = nil,
				regionId  = nil,      -- stamped after RegionGenerator
				marker    = marker,
				protected = false,    -- FloorPass marks PD/ED/LAN
			}
		end
	end

	return tiles
end

--------------------------------------------------
-- STEP 7: VALIDATE CONNECTIVITY
-- BFS from all PD tiles through passable tiles with
-- elevation diff ≤ 1 (4-cardinal only).
-- Succeeds when at least one ED tile is reachable.
--------------------------------------------------

local function validateConnectivity(tiles, w, h)
	local pdPositions = {}
	local edSet       = {}

	for y = 1, h do
		for x = 1, w do
			local marker = tiles[y][x].marker
			if marker == "PD" then
				table.insert(pdPositions, { x = x, y = y })
			elseif marker == "ED" then
				edSet[coordKey(x, y)] = true
			end
		end
	end

	if #pdPositions == 0 then return false, "No PD tiles" end
	if next(edSet) == nil then return false, "No ED tiles" end

	-- BFS from all PD tiles.
	local visited   = {}
	local queue     = {}
	local queueHead = 1

	for _, pos in ipairs(pdPositions) do
		local key = coordKey(pos.x, pos.y)
		if not visited[key] then
			visited[key] = true
			table.insert(queue, pos)
		end
	end

	while queueHead <= #queue do
		local cur  = queue[queueHead]
		queueHead  = queueHead + 1
		local tile = tiles[cur.y][cur.x]

		-- Reached an ED tile — map is connected.
		if edSet[coordKey(cur.x, cur.y)] then
			return true, nil
		end

		for _, dir in ipairs(CARDINAL) do
			local nx, ny = cur.x + dir.x, cur.y + dir.y
			if isInBounds(nx, ny, w, h) then
				local nKey = coordKey(nx, ny)
				if not visited[nKey] then
					local nTile = tiles[ny][nx]

					-- Passable terrain?
					local tDef = TerrainData.Types[nTile.terrain]
					local pass = tDef and tDef.passable ~= false

					-- Not blocked by a non-passable object?
					local noBlock = nTile.object == nil
						or (ObjectData.Objects[nTile.object]
							and ObjectData.Objects[nTile.object].passable)

					-- Elevation difference ≤ 1?
					local elevOk = math.abs(
						tile.elevation - nTile.elevation
					) <= 1

					if pass and noBlock and elevOk then
						visited[nKey] = true
						table.insert(queue, { x = nx, y = ny })
					end
				end
			end
		end
	end

	return false, "No path from PD to ED"
end

--------------------------------------------------
-- STEP 8: PLACE OBJECTS
-- Per-tile roll against marker density.
-- Object selected from biome weights (graceful skip
-- for unresolved object IDs).
-- LAN tiles only get passable objects.
-- Non-passable objects require an adjacent passable
-- empty tile for interaction.
--------------------------------------------------

local function placeObjects(tiles, w, h, biome, rng)
	local placedObjects   = {}
	local objectIdCounter = 0
	local ops             = 0

	-- Validators for object selection.
	local function validObject(objId)
		return ObjectData.Objects[objId] ~= nil
	end

	local function validPassableObject(objId)
		local o = ObjectData.Objects[objId]
		return o ~= nil and o.passable
	end

	for y = 1, h do
		for x = 1, w do
			local tile    = tiles[y][x]
			local marker  = tile.marker
			local density = MARKER_OBJECT_DENSITY[marker] or 0

			if density > 0 and tile.object == nil then
				if rng:NextNumber() < density then
					-- LAN tiles: passable objects only.
					local validator = (marker == "LAN")
						and validPassableObject or validObject

					local selected = weightedSelect(
						biome.objectWeights, rng, validator, nil
					)

					if selected then
						local objDef   = ObjectData.Objects[selected]
						local canPlace = true

						-- Non-passable objects need at least one
						-- adjacent passable empty tile.
						if objDef and not objDef.passable then
							local hasAdj = false
							for _, dir in ipairs(CARDINAL) do
								local adjX = x + dir.x
								local adjY = y + dir.y
								if isInBounds(adjX, adjY, w, h) then
									local adj  = tiles[adjY][adjX]
									local aDef = TerrainData.Types[adj.terrain]
									if aDef
										and aDef.passable ~= false
										and adj.object == nil
									then
										hasAdj = true
										break
									end
								end
							end
							canPlace = hasAdj
						end

						if canPlace then
							objectIdCounter    = objectIdCounter + 1
							tile.object        = selected
							table.insert(placedObjects, {
								id   = "obj_" .. objectIdCounter,
								type = selected,
								x    = x,
								y    = y,
							})
						end
					end
				end
			end

			ops = ops + 1
			if ops % YIELD_INTERVAL == 0 then task.wait() end
		end
	end

	return placedObjects
end

--------------------------------------------------
-- STEP 9: SELECT BATTLE CONDITION
-- Weighted random from biome condition weights.
--------------------------------------------------

local function selectBattleCondition(biome, rng)
	return weightedSelect(
		biome.battleConditionWeights, rng, nil, "Clear"
	)
end

--------------------------------------------------
-- STEP 10: PLACE DEPLOYMENT ANCHORS
-- Selects passable, unoccupied tiles from PD/ED zones.
-- Shuffle deterministically, then take first N.
--------------------------------------------------

local function placeDeploymentAnchors(tiles, w, h, rng)
	local pdCandidates = {}
	local edCandidates = {}

	for y = 1, h do
		for x = 1, w do
			local tile = tiles[y][x]
			local tDef = TerrainData.Types[tile.terrain]
			local passable    = tDef and tDef.passable ~= false
			local unoccupied  = tile.object == nil

			if passable and unoccupied then
				if tile.marker == "PD" then
					table.insert(pdCandidates, { x = x, y = y })
				elseif tile.marker == "ED" then
					table.insert(edCandidates, { x = x, y = y })
				end
			end
		end
	end

	-- Deterministic Fisher-Yates shuffle.
	local function shuffle(list)
		for i = #list, 2, -1 do
			local j = rng:NextInteger(1, i)
			list[i], list[j] = list[j], list[i]
		end
	end

	shuffle(pdCandidates)
	shuffle(edCandidates)

	-- Take first N anchors (up to 6 per side).
	local maxAnchors = 6
	local player = {}
	local enemy  = {}

	for i = 1, math.min(maxAnchors, #pdCandidates) do
		table.insert(player, pdCandidates[i])
	end
	for i = 1, math.min(maxAnchors, #edCandidates) do
		table.insert(enemy, edCandidates[i])
	end

	return { player = player, enemy = enemy }
end

--------------------------------------------------
-- STEP 11: FINAL VALIDATION
-- Runs invariants from the Validation Matrix.
-- Returns (passed, errorList).
--------------------------------------------------

--- Build blocker list for GameConstants from placed objects.
local function buildBlockers(objects)
	local blockers = {}
	for _, obj in ipairs(objects) do
		local objDef = ObjectData.Objects[obj.type]
		if objDef and not objDef.passable then
			table.insert(blockers, {
				tileX      = obj.x,
				tileY      = obj.y,
				objectType = obj.type,
				tags       = { "BlocksAOE", "BlocksLoS" },
			})
		end
	end
	return blockers
end

--- Extract flat 2D grids for GameConstants from tile data.
local function buildGrids(tiles, w, h)
	local elevGrid    = {}
	local terrainGrid = {}

	for y = 1, h do
		elevGrid[y]    = {}
		terrainGrid[y] = {}
		for x = 1, w do
			elevGrid[y][x]    = tiles[y][x].elevation
			terrainGrid[y][x] = tiles[y][x].terrain
		end
	end

	return elevGrid, terrainGrid
end

--- Run all validation invariants.
local function runFinalValidation(mapState)
	local errors = {}
	local tiles  = mapState.tiles
	local w, h   = mapState.width, mapState.height

	-- V1: Every tile has a resolved terrain and finite elevation.
	for y = 1, h do
		for x = 1, w do
			local t = tiles[y][x]
			if not t.terrain or not TerrainData.Types[t.terrain] then
				table.insert(errors,
					string.format("(%d,%d) unresolved terrain: %s",
						x, y, tostring(t.terrain)))
			end
			if not t.elevation or t.elevation ~= t.elevation then
				table.insert(errors,
					string.format("(%d,%d) invalid elevation", x, y))
			end
		end
	end

	-- V2: PD→ED connectivity.
	local connected, connErr = validateConnectivity(tiles, w, h)
	if not connected then
		table.insert(errors, "Connectivity: " .. (connErr or "unknown"))
	end

	-- V3: Deployment anchors exist.
	if #mapState.deploymentZones.player == 0 then
		table.insert(errors, "No player deployment anchors")
	end
	if #mapState.deploymentZones.enemy == 0 then
		table.insert(errors, "No enemy deployment anchors")
	end

	-- V4: Object references resolve.
	for _, obj in ipairs(mapState.objects) do
		if not ObjectData.Objects[obj.type] then
			table.insert(errors, "Unknown object: " .. obj.type)
		end
	end

	-- V5: Non-passable objects have an adjacent passable interaction tile.
	for _, obj in ipairs(mapState.objects) do
		local def = ObjectData.Objects[obj.type]
		if def and not def.passable then
			local hasAdj = false
			for _, dir in ipairs(CARDINAL) do
				local nx, ny = obj.x + dir.x, obj.y + dir.y
				if isInBounds(nx, ny, w, h) then
					local adj  = tiles[ny][nx]
					local aDef = TerrainData.Types[adj.terrain]
					if aDef and aDef.passable ~= false and adj.object == nil then
						hasAdj = true
						break
					end
				end
			end
			if not hasAdj then
				table.insert(errors,
					obj.id .. " (" .. obj.type .. ") no adjacent passable tile")
			end
		end
	end

	-- V6: LAN-family adjacent elevation diff ≤ 1.
	for y = 1, h do
		for x = 1, w do
			local tile = tiles[y][x]
			if LAN_FAMILY[tile.marker] then
				for _, dir in ipairs(CARDINAL) do
					local nx, ny = x + dir.x, y + dir.y
					if isInBounds(nx, ny, w, h) then
						local n = tiles[ny][nx]
						if LAN_FAMILY[n.marker] then
							if math.abs(tile.elevation - n.elevation) > 1 then
								table.insert(errors,
									string.format(
										"LAN elev breach (%d,%d)=%d ↔ (%d,%d)=%d",
										x, y, tile.elevation,
										nx, ny, n.elevation))
							end
						end
					end
				end
			end
		end
	end

	-- V7: Determinism — structural check only.
	-- Full round-trip test is done externally.
	-- (Same seed + same content version must produce same map.)

	-- V8: Bounded generation — enforced by the attempt loop.

	return #errors == 0, errors
end

--------------------------------------------------
-- PUBLIC API
--------------------------------------------------

--- Clear the cached map so the next Generate() call
--- produces a fresh map even for the same biome+template.
--- Used by DevCommand Regenerate.
function MapService.ClearCache()
	_cachedMap = nil
end

--- Generate a complete playable battlefield.
--- @param biomeId string — Key in BiomeData (e.g. "Plains").
--- @param templateId string — Key in TemplateRegistry (e.g. "T01").
--- @param seed number|nil — Master seed. nil = auto.
--- @return table mapState — Full map state for GameConstants.
function MapService.Generate(biomeId, templateId, seed)
	assert(type(biomeId) == "string",
		"[MapService] biomeId must be a string")
	assert(type(templateId) == "string",
		"[MapService] templateId must be a string")

	-- Return cached map if one exists for the same biome+template.
	if _cachedMap
		and _cachedMap.biomeId == biomeId
		and _cachedMap.templateId == templateId then
		return _cachedMap
	end

	-- Step 1: Load template.
	local template = loadTemplate(templateId)
	local w, h     = template.Width, template.Height

	-- Step 2: Load biome.
	local biome = loadBiome(biomeId)

	local lastErrors = {}

	for attempt = 1, MAX_GENERATION_ATTEMPTS do
		-- Step 3: Create seed context.
		-- Offset seed on retries so each attempt explores a new map.
		local attemptSeed = seed
		if attempt > 1 and seed ~= nil then
			attemptSeed = seed + attempt
		end

		local seedCtx = createSeedContext(attemptSeed)

		print(string.format(
			"[MapService] Attempt %d/%d  seed=%d  biome=%s  template=%s",
			attempt, MAX_GENERATION_ATTEMPTS,
			seedCtx.seed, biomeId, templateId))

		-- Step 4: Initialize tile grid with markers.
		local tiles = initializeTiles(w, h, template)

		-- Step 5a: Generate region ownership grid.
		local regionResult = RegionGenerator.Generate({
			Width                     = w,
			Height                    = h,
			BiomeId                   = biome.id,
			RegionCount               = 3,
			MinimumRegionPercent      = 0.15,
			MaximumGenerationAttempts = 50,
			Seed                      = seedCtx.regionSeed,
		})

		-- Stamp region IDs onto tiles.
		for y = 1, h do
			for x = 1, w do
				tiles[y][x].regionId = regionResult.Grid[y][x]
			end
		end

		-- Step 5b: Assign a region type to each generated region.
		local pool = BIOME_REGION_POOLS[biome.id]
			or { { type = "Grassland", weight = 100 } }

		local regionTypeMap = {}
		for _, region in ipairs(regionResult.Regions) do
			regionTypeMap[region.Id] = weightedSelectArray(
				pool, seedCtx.terrainRng
			)
		end

		-- Build mapState for the pass pipeline.
		local mapState = {
			width          = w,
			height         = h,
			biomeId        = biomeId,
			templateId     = templateId,
			seed           = seedCtx.seed,
			template       = template,
			biome          = biome,
			regionResult   = regionResult,
			regionTypeMap  = regionTypeMap,
			tiles          = tiles,
			rng            = seedCtx,
			biomeElevation = BIOME_ELEVATION[biomeId] or DEFAULT_ELEVATION,
		}

		--======================================================
		-- PASS PIPELINE
		--======================================================
		mapState = FloorPass.Run(mapState)
		mapState = FeaturePass.Run(mapState)
		mapState = TransitionPass.Run(mapState)
		mapState = ElevationPass.Run(mapState)
		mapState = ValidationPass.Run(mapState)

		-- Step 7: Validate connectivity (pre-object).
		local conn, connErr = validateConnectivity(tiles, w, h)
		if not conn then
			warn("[MapService] Pre-object connectivity fail: " .. (connErr or ""))
			lastErrors = { connErr or "connectivity" }
			continue
		end

		-- Step 8: Place objects.
		local objects = placeObjects(tiles, w, h, biome, seedCtx.objectRng)

		-- Re-check connectivity after object placement.
		local conn2, connErr2 = validateConnectivity(tiles, w, h)
		if not conn2 then
			warn("[MapService] Post-object connectivity fail: " .. (connErr2 or ""))
			lastErrors = { connErr2 or "post-object connectivity" }
			continue
		end

		-- Step 9: Select battle condition.
		local battleCondition = selectBattleCondition(biome, seedCtx.conditionRng)

		-- Step 10: Place deployment anchors.
		local deployZones = placeDeploymentAnchors(tiles, w, h, seedCtx.deployRng)

		-- Build auxiliary data for GameConstants.
		local elevGrid, terrainGrid = buildGrids(tiles, w, h)
		local blockers              = buildBlockers(objects)

		-- Populate final mapState fields for downstream consumers.
		mapState.deploymentZones = deployZones
		mapState.objects         = objects
		mapState.battleCondition = battleCondition
		mapState.elevationGrid   = elevGrid
		mapState.terrainGrid     = terrainGrid
		mapState.blockers        = blockers
		mapState.generationAudit = {
			attempts         = attempt,
			seed             = seedCtx.seed,
			validationPassed = false,
		}

		-- Step 11: Final validation.
		local valid, errors = runFinalValidation(mapState)

		if valid then
			mapState.generationAudit.validationPassed = true
			-- Include ValidationPass report in audit (advisory).
			if mapState.validationReport then
				mapState.generationAudit.validationReport = mapState.validationReport
				if not mapState.validationReport.passed then
					warn(string.format("[MapService] ValidationPass advisory: %d violation(s)",
						mapState.validationReport.totalViolations or 0))
				end
			end

			print(string.format(
				"[MapService] Generated %dx%d  seed=%d  regions=%d  objects=%d  condition=%s  attempt=%d",
				w, h, seedCtx.seed,
				regionResult.RegionCount, #objects,
				battleCondition, attempt))

			-- Log region type assignments.
			for regionId, regionTypeName in pairs(regionTypeMap) do
				print(string.format(
					"[MapService]   %s → %s", regionId, regionTypeName))
			end

			-- Strip internal pipeline fields before caching.
			mapState.rng            = nil
			mapState.template       = nil
			mapState.biome          = nil
			mapState.biomeElevation = nil

			_cachedMap = mapState
			return _cachedMap
		end

		-- Log and retry.
		for _, err in ipairs(errors) do
			warn("[MapService] Validation: " .. err)
		end
		lastErrors = errors
	end

	error(string.format(
		"[MapService] Generation FAILED after %d attempts. Errors: %s",
		MAX_GENERATION_ATTEMPTS,
		table.concat(lastErrors, "; ")))
end

return MapService
