-- MapService.lua
-- CTRBLXAI | Slice 5 Phase 2 — Procedural Map Generator
--
-- 11-step deterministic pipeline: biome + template → playable battlefield.
--
-- Initial delivery scope: Plains biome + T01 template.
-- Pipeline architecture supports any biome/template — only Plains+T01
-- is tested end-to-end.
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

-- Template registry — add future templates here.
local TemplateRegistry = {
	T01 = require(
		ReplicatedStorage
			:WaitForChild("CTRBLXAI")
			:WaitForChild("Templates")
			:WaitForChild("T01_FrontlinePressure")
	),
}

local MapService = {}

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
	-- Future biomes add entries here.
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
		advBonus = 1,
	},
	-- Future biomes add entries here.
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
		return fallback or "Clear"
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
-- Used by weightedSelect to filter the biome/region
-- weight tables. Gracefully skips unresolved terrain IDs
-- (e.g. "Forest Floor", "Road") — redistributes weight
-- to resolved entries.
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
	}
end

--------------------------------------------------
-- STEP 4: GENERATE BASE TERRAIN
-- Fill every tile with terrain from biome weights.
-- Template markers are applied. PD/ED/LAN get passable
-- terrain only.
--------------------------------------------------

local function generateBaseTerrain(w, h, template, biome, rng)
	local tiles = {}
	local ops   = 0

	for y = 1, h do
		tiles[y] = {}

		for x = 1, w do
			local marker = (template.Grid[y] and template.Grid[y][x]) or "NEU"

			local validator = PASSABLE_REQUIRED[marker]
				and validPassableTerrain or validTerrain

			tiles[y][x] = {
				terrain   = weightedSelect(
					biome.terrainWeights, rng, validator, "Clear"
				),
				elevation = 1,
				object    = nil,
				regionId  = nil,
				marker    = marker,
			}

			ops = ops + 1
			if ops % YIELD_INTERVAL == 0 then task.wait() end
		end
	end

	return tiles
end

--------------------------------------------------
-- STEP 5: SHAPE REGIONS
-- 5a: Generate region ownership grid via RegionGenerator.
-- 5b: Assign a region type (e.g. Grassland, Clearing) to
--     each generated region from the biome pool.
-- 5c: Override terrain per region's terrain weights.
--     Unresolved terrain IDs are skipped (graceful fallback).
--------------------------------------------------

local function shapeRegions(tiles, w, h, biome, seedCtx)
	-- 5a: Region ownership grid.
	local regionResult = RegionGenerator.Generate({
		Width                     = w,
		Height                    = h,
		BiomeId                   = biome.id,
		RegionCount               = 3,
		MinimumRegionPercent      = 0.15,
		MaximumGenerationAttempts = 50,
		Seed                      = seedCtx.regionSeed,
	})

	-- 5b: Map each generated region ID to a region type.
	local pool = BIOME_REGION_POOLS[biome.id]
		or { { type = "Grassland", weight = 100 } }

	local regionTypeMap = {} -- regionId → RegionData key
	for _, region in ipairs(regionResult.Regions) do
		regionTypeMap[region.Id] = weightedSelectArray(pool, seedCtx.terrainRng)
	end

	-- 5c: Override terrain using region weights.
	local ops = 0

	for y = 1, h do
		for x = 1, w do
			local tile     = tiles[y][x]
			local regionId = regionResult.Grid[y][x]
			tile.regionId  = regionId

			local regionTypeName = regionTypeMap[regionId]
			local regionType     = RegionData[regionTypeName]

			if regionType and regionType.terrainWeights then
				local validator = PASSABLE_REQUIRED[tile.marker]
					and validPassableTerrain or validTerrain

				tile.terrain = weightedSelect(
					regionType.terrainWeights,
					seedCtx.terrainRng,
					validator,
					"Clear"
				)
			end

			ops = ops + 1
			if ops % YIELD_INTERVAL == 0 then task.wait() end
		end
	end

	return regionResult, regionTypeMap
end

--------------------------------------------------
-- STEP 6: ASSIGN ELEVATION
-- Biome-appropriate variance. Plains = low (1-3).
-- LAN-family tiles smoothed to ensure adjacent tiles
-- differ by ≤ 1 (Jump=1 constraint from DB).
--------------------------------------------------

local function assignElevation(tiles, w, h, biome, rng)
	local cfg = BIOME_ELEVATION[biome.id]
		or { min = 1, max = 3, lanMin = 1, lanMax = 2, advBonus = 1 }

	-- First pass: initial elevation based on marker type.
	for y = 1, h do
		for x = 1, w do
			local tile   = tiles[y][x]
			local marker = tile.marker

			if marker == "PD" or marker == "ED" then
				tile.elevation = cfg.min
			elseif marker == "ADV" then
				tile.elevation = math.min(
					cfg.lanMax + cfg.advBonus, cfg.max
				)
			elseif marker == "LAN" or marker == "HZD" or marker == "BLK" then
				tile.elevation = rng:NextInteger(cfg.lanMin, cfg.lanMax)
			elseif marker == "POI" then
				tile.elevation = rng:NextInteger(cfg.min, cfg.lanMax)
			else -- NEU
				tile.elevation = rng:NextInteger(cfg.min, cfg.max)
			end
		end
	end

	-- Smoothing passes: enforce adjacent LAN-family tiles
	-- differ by ≤ 1 elevation. Three passes is sufficient
	-- for the 30×20 grid.
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
			end
		end
	end
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

		-- Step 4: Generate base terrain.
		local tiles = generateBaseTerrain(w, h, template, biome, seedCtx.terrainRng)

		-- Step 5: Shape regions and override terrain.
		local regionResult, regionTypeMap =
			shapeRegions(tiles, w, h, biome, seedCtx)

		-- Step 6: Assign elevation.
		assignElevation(tiles, w, h, biome, seedCtx.elevationRng)

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

		local mapState = {
			width           = w,
			height          = h,
			biomeId         = biomeId,
			templateId      = templateId,
			seed            = seedCtx.seed,
			tiles           = tiles,
			deploymentZones = deployZones,
			objects         = objects,
			battleCondition = battleCondition,
			-- Pre-built grids for GameConstants.SetGeneratedMap().
			elevationGrid   = elevGrid,
			terrainGrid     = terrainGrid,
			blockers        = blockers,
			generationAudit = {
				attempts         = attempt,
				seed             = seedCtx.seed,
				validationPassed = false,
			},
		}

		-- Step 11: Final validation.
		local valid, errors = runFinalValidation(mapState)

		if valid then
			mapState.generationAudit.validationPassed = true

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

			return mapState
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
