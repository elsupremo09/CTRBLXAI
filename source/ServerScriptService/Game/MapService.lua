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
	T09 = require(
		ReplicatedStorage
			:WaitForChild("CTRBLXAI")
			:WaitForChild("Templates")
			:WaitForChild("T09_HazardGauntlet")
	),
	T10 = require(
		ReplicatedStorage
			:WaitForChild("CTRBLXAI")
			:WaitForChild("Templates")
			:WaitForChild("T10_ObstacleWarren")
	),
	T11 = require(
		ReplicatedStorage
			:WaitForChild("CTRBLXAI")
			:WaitForChild("Templates")
			:WaitForChild("T11_ObjectiveStandoff")
	),
	T12 = require(
		ReplicatedStorage
			:WaitForChild("CTRBLXAI")
			:WaitForChild("Templates")
			:WaitForChild("T12_ElevatedObjective")
	),
	T13 = require(
		ReplicatedStorage
			:WaitForChild("CTRBLXAI")
			:WaitForChild("Templates")
			:WaitForChild("T13_HighlandContest")
	),
	T14 = require(
		ReplicatedStorage
			:WaitForChild("CTRBLXAI")
			:WaitForChild("Templates")
			:WaitForChild("T14_BrokenHighlands")
	),
	T15 = require(
		ReplicatedStorage
			:WaitForChild("CTRBLXAI")
			:WaitForChild("Templates")
			:WaitForChild("T15_ObjectiveSiege")
	),
	T16 = require(
		ReplicatedStorage
			:WaitForChild("CTRBLXAI")
			:WaitForChild("Templates")
			:WaitForChild("T16_TreasureWarren")
	),
	T17 = require(
		ReplicatedStorage
			:WaitForChild("CTRBLXAI")
			:WaitForChild("Templates")
			:WaitForChild("T17_WideHazardFront")
	),
	T18 = require(
		ReplicatedStorage
			:WaitForChild("CTRBLXAI")
			:WaitForChild("Templates")
			:WaitForChild("T18_WatlandExpanse")
	),
	T19 = require(
		ReplicatedStorage
			:WaitForChild("CTRBLXAI")
			:WaitForChild("Templates")
			:WaitForChild("T19_GreatDivide")
	),
	T20 = require(
		ReplicatedStorage
			:WaitForChild("CTRBLXAI")
			:WaitForChild("Templates")
			:WaitForChild("T20_RiverVale")
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
		{ type = "Grassland", weight = 35 },
		{ type = "Clearing",  weight = 20 },
		{ type = "Farmland",  weight = 15 },
		{ type = "Forest",    weight = 12 },
		{ type = "Riverbank", weight = 10 },
		{ type = "Village",   weight = 8 },
		-- Town (regions row 23 / open_decisions 'Town region + region-level object
		-- weights — Dev wiring'): Designer-recommended Plains weight 5.
		{ type = "Town",      weight = 5 },
	},
	Forest = {
		{ type = "Forest",    weight = 35 },
		{ type = "Clearing",  weight = 18 },
		{ type = "Grassland", weight = 12 },
		{ type = "Riverbank", weight = 12 },
		{ type = "Marsh",     weight = 13 },
		{ type = "Rocky",     weight = 10 },
	},
	Desert = {
		{ type = "Rocky",         weight = 30 },
		{ type = "Beach",         weight = 22 },
		{ type = "Clearing",      weight = 15 },
		{ type = "Grassland",     weight = 8 },
		{ type = "Ruins",         weight = 13 },
		{ type = "Mountain Pass", weight = 12 },
	},
	Swamp = {
		{ type = "Marsh",     weight = 38 },
		{ type = "Riverbank", weight = 22 },
		{ type = "Forest",    weight = 13 },
		{ type = "Clearing",  weight = 12 },
		{ type = "Graveyard", weight = 15 },
	},
	Highlands = {
		{ type = "Rocky",         weight = 30 },
		{ type = "Mountain Pass", weight = 28 },
		{ type = "Grassland",     weight = 12 },
		{ type = "Clearing",      weight = 8 },
		{ type = "Riverbank",     weight = 12 },
		{ type = "Cave Chamber",  weight = 10 },
	},
	Tundra = {
		{ type = "Frozen Lake",   weight = 35 },
		{ type = "Rocky",         weight = 22 },
		{ type = "Grassland",     weight = 12 },
		{ type = "Clearing",      weight = 8 },
		{ type = "Mountain Pass", weight = 13 },
		{ type = "Riverbank",     weight = 10 },
	},
	Volcano = {
		{ type = "Volcanic Rock", weight = 35 },
		{ type = "Lava Channel",  weight = 20 },
		{ type = "Rocky",         weight = 15 },
		{ type = "Clearing",      weight = 8 },
		{ type = "Cave Chamber",  weight = 12 },
		{ type = "Ruins",         weight = 10 },
	},
	Cave = {
		{ type = "Cave Chamber", weight = 38 },
		{ type = "Rocky",        weight = 22 },
		{ type = "Clearing",     weight = 15 },
		{ type = "Lava Channel", weight = 13 },
		{ type = "Riverbank",    weight = 12 },
	},
	Ruins = {
		{ type = "Ruins",     weight = 35 },
		{ type = "Rocky",     weight = 18 },
		{ type = "Graveyard", weight = 13 },
		{ type = "Clearing",  weight = 12 },
		{ type = "Forest",    weight = 12 },
		{ type = "Village",   weight = 10 },
	},
	Castle = {
		{ type = "Castle Courtyard", weight = 32 },
		{ type = "Castle Interior",  weight = 24 },
		{ type = "Rocky",            weight = 12 },
		{ type = "Clearing",         weight = 10 },
		{ type = "Village",          weight = 12 },
		{ type = "Farmland",         weight = 10 },
		-- Town (regions row 23 / open_decisions Dev wiring): Castle weight 10.
		{ type = "Town",             weight = 10 },
	},
	Corrupted = {
		{ type = "Corrupted", weight = 38 },
		{ type = "Graveyard", weight = 22 },
		{ type = "Marsh",     weight = 13 },
		{ type = "Forest",    weight = 12 },
		{ type = "Ruins",     weight = 15 },
	},
}

-- Elevation range per biome.
-- lanMin/lanMax: constrained range for LAN-family tiles.
-- advBonus: extra elevation added to ADV marker tiles.
-- Global elevation scale (dev-locked 2026-09-24): sea level = 5, floor = 1, peak = 20.
-- Water rests at/below sea level; rock rises toward peak. See ElevationScale_Design.md.
local SEA_LEVEL = 5
local ELEV_FLOOR = 1
local ELEV_PEAK  = 20

-- BIOME ELEVATION BANDS (Round 3 ridge/cliff + bridge rework, 2026-09-29).
-- TRANSCRIBED from CTRBLXAI.db table `biomes`, rows 16-26
-- (BIOME ELEVATION BANDS SPEC). Studio cannot read the DB at runtime, so the
-- values below are a faithful copy -- the DB spec is the source of truth; if
-- the spec changes, re-transcribe this table.
--   min / max  : col_2  Elev Min / Max (band)
--   bMid       : col_3  high-ground (Rocky) start elevation
--   baseBand   : col_4  typical low-ground band { lo, hi }
--   spinePct   : col_4  fraction of the map that is spine/high ground (elev >= bMid)
--   cliffDrop  : col_5  deliberate Rocky ridge cliff-face step. Human decision
--                       (locked 2026-09-29): 2 for low-relief biomes, 3 for
--                       Highlands / Volcano / Castle.
--   advBonus   : col_7  ADV marker bonus
--   gapPolicy  : col_6  bridge / gap policy (consumed by FeaturePass
--                       placeGapsAndSpans). chance = per-map roll that any gap
--                       is placed; maxGaps = cap; gapTerrain = impassable-by-
--                       depth gap floor (EFFECT-BEARING chasm-floor terrain,
--                       map_gen_rules row 59, user ruling 2026-10-02);
--                       gapFloorEffect = optional permanent floor TILE EFFECT
--                       seeded on every gap tile (Vines / Tar Pit; rows 59/67);
--                       spans = span kinds (FeaturePass
--                       BRIDGE_SPAN_DEFS); widthMin/Max = gap width = span
--                       length; halfLen = max gap reach either side of the span.
--                       Gap MIX (user-locked 2026-09-29): each placed gap rolls
--                       CHOKEPOINT 30% / SHORTCUT 70% (FeaturePass
--                       GAP_CHOKE_CHANCE). A chokepoint strip is extended along
--                       the lane cross-section until both ends seal (edge / wall),
--                       at most chokeMaxExtend tiles past halfLen per side
--                       (default FeaturePass GAP_CHOKE_MAX_EXTEND); otherwise it
--                       falls back to a shortcut. Optional per-biome overrides:
--                       chokeChance, chokeMaxExtend (none set here).
--                       Frequencies are the Dev reading of the col_6 prose
--                       ("Rare" / "Occasional" / "Frequent" / "Signature").
local BIOME_ELEVATION = {
	Plains = {    -- col_6: Rare. Occasional shallow creek gap, 1-2 tile Wooden Floor span; no true chasms.
		min = 5, max = 9, advBonus = 3,
		bMid = 7, baseBand = { lo = 5, hi = 6 }, spinePct = 0.15, cliffDrop = 2,
		-- Chasm floor (map_gen_rules row 59): Grassland + Vines (overgrown ditch).
		gapPolicy = { chance = 0.25, maxGaps = 1, gapTerrain = "Grassland", gapFloorEffect = "Vines",
			spans = { "Plank" }, widthMin = 1, widthMax = 2, halfLen = 3 },
	},
	Forest = {    -- col_6: Occasional stream gap crossed by a short Wooden Floor span.
		min = 5, max = 9, advBonus = 3,
		bMid = 7, baseBand = { lo = 5, hi = 6 }, spinePct = 0.20, cliffDrop = 2,
		-- Chasm floor (map_gen_rules row 59): Grassland + Vines (bramble ravine).
		gapPolicy = { chance = 0.50, maxGaps = 1, gapTerrain = "Grassland", gapFloorEffect = "Vines",
			spans = { "Plank" }, widthMin = 1, widthMax = 2, halfLen = 4 },
	},
	Desert = {    -- col_6: Dry wadi gaps (low Sand troughs) between mesas; short spans.
		min = 5, max = 11, advBonus = 3,
		bMid = 8, baseBand = { lo = 5, hi = 7 }, spinePct = 0.25, cliffDrop = 2,
		-- Chasm floor (map_gen_rules rows 59/66): Quicksand sinking pit — LETHAL by
		-- design (Sinking KO at 2500 CT unless Water->Mud / Flight / teleport).
		gapPolicy = { chance = 0.50, maxGaps = 1, gapTerrain = "Quicksand",
			spans = { "Plank" }, widthMin = 1, widthMax = 2, halfLen = 4 },
	},
	Swamp = {     -- col_6: Frequent water gaps (Deep Water) crossed by Wooden Floor plank spans.
		min = 4, max = 7, advBonus = 2,
		bMid = 6, baseBand = { lo = 4, hi = 5 }, spinePct = 0.10, cliffDrop = 2,
		gapPolicy = { chance = 1.00, maxGaps = 2, gapTerrain = "Deep Water",
			spans = { "Plank" }, widthMin = 1, widthMax = 3, halfLen = 5 },
	},
	Highlands = { -- col_6: Signature gap biome: deep chasms spanned by Wooden Floor / Rocky causeway bridges.
		min = 6, max = 20, advBonus = 5,
		bMid = 12, baseBand = { lo = 6, hi = 11 }, spinePct = 0.45, cliffDrop = 3,
		gapPolicy = { chance = 1.00, maxGaps = 2, gapTerrain = "Deep Water",
			spans = { "Plank", "Causeway" }, widthMin = 2, widthMax = 3, halfLen = 8 },
	},
	Tundra = {    -- col_6: Ice-sheet gaps / cracked-ice channels; Rocky-path bridges.
		min = 4, max = 9, advBonus = 3,
		bMid = 7, baseBand = { lo = 4, hi = 6 }, spinePct = 0.20, cliffDrop = 2,
		gapPolicy = { chance = 0.50, maxGaps = 1, gapTerrain = "Deep Water",
			spans = { "Causeway" }, widthMin = 1, widthMax = 2, halfLen = 4 },
	},
	Volcano = {   -- col_6: Lava-channel gaps (Molten) crossed by Rocky causeway spans.
		min = 5, max = 16, advBonus = 4,
		bMid = 10, baseBand = { lo = 5, hi = 9 }, spinePct = 0.35, cliffDrop = 3,
		gapPolicy = { chance = 0.80, maxGaps = 2, gapTerrain = "Molten",
			spans = { "Causeway" }, widthMin = 1, widthMax = 3, halfLen = 6 },
	},
	Cave = {      -- col_6: Underground chasm gaps (Deep Water pools / pits); narrow Rocky or Wooden Floor spans.
		min = 4, max = 12, advBonus = 3,
		bMid = 8, baseBand = { lo = 4, hi = 7 }, spinePct = 0.30, cliffDrop = 2,
		gapPolicy = { chance = 0.60, maxGaps = 1, gapTerrain = "Deep Water",
			spans = { "Causeway", "Plank" }, widthMin = 1, widthMax = 2, halfLen = 4 },
	},
	Ruins = {     -- col_6: Broken-floor gaps (collapsed floor / pits) crossed by intact Wooden Floor spans.
		min = 5, max = 12, advBonus = 3,
		bMid = 8, baseBand = { lo = 5, hi = 7 }, spinePct = 0.25, cliffDrop = 2,
		gapPolicy = { chance = 0.60, maxGaps = 1, gapTerrain = "Cracked Ground",
			spans = { "Plank" }, widthMin = 1, widthMax = 2, halfLen = 4 },
	},
	Castle = {    -- col_6: Moat gaps (Deep Water) crossed by Wooden Floor drawbridge spans.
		min = 5, max = 14, advBonus = 4,
		bMid = 9, baseBand = { lo = 5, hi = 8 }, spinePct = 0.30, cliffDrop = 3,
		-- Chasm floor (map_gen_rules row 59): Rocky stone moat bed + Tar Pit ('pitch moat').
		gapPolicy = { chance = 0.80, maxGaps = 1, gapTerrain = "Rocky", gapFloorEffect = "Tar Pit",
			spans = { "Drawbridge" }, widthMin = 1, widthMax = 2, halfLen = 6 },
	},
	Corrupted = { -- col_6: Tainted mire gaps (Swamp low troughs) crossed by short spans.
		min = 5, max = 9, advBonus = 3,
		bMid = 7, baseBand = { lo = 5, hi = 6 }, spinePct = 0.20, cliffDrop = 2,
		-- Chasm floor (map_gen_rules row 59): Tainted Ground (tainted pit).
		gapPolicy = { chance = 0.50, maxGaps = 1, gapTerrain = "Tainted Ground",
			spans = { "Plank" }, widthMin = 1, widthMax = 2, halfLen = 4 },
	},
}

-- Fallback band (unknown biome): Plains-like, no deliberate gaps.
local DEFAULT_ELEVATION = {
	min = 5, max = 9, advBonus = 3,
	bMid = 7, baseBand = { lo = 5, hi = 6 }, spinePct = 0.15, cliffDrop = 2,
	gapPolicy = nil,
}

-- Object placement density per template marker (fraction of tiles).
-- 0 = no objects allowed in that marker zone.
local MARKER_OBJECT_DENSITY = {
	PD  = 0,
	ED  = 0,
	LAN = 0.02,
	HZD = 0.12,
	OBS = 0,   -- impassable wall (formerly BLK 0.15); no objects on walls
	POI = 0.08,
	ADV = 0.08,
	NEU = 0.03,
	WAT = 0.04,
}

-- Object spawn budget + mix rules (user-locked 2026-10-04).
-- Count is driven from a budget (~5% of tiles) rather than independent per-tile dice.
-- Objects must be reachable from a deploy zone and never on peak-elevation or gap tiles.
local OBJECT_BUDGET_RATE   = 0.05   -- target objects = 5% of map tiles
local OBJECT_BUDGET_MIN    = 8      -- clamp floor
local OBJECT_BUDGET_MAX    = 45     -- clamp ceiling
local BLOCKER_MAX_FRACTION = 0.35   -- blockers may be at most 35% of placed objects
local INTERACT_MIN_SPACING = 3      -- min Manhattan distance between two interactables
local MAX_COPIES_PER_OBJECT = 2    -- same object may appear at most this many times per map (user rule 2026-10-06)

-- Markers that require passable terrain (PD/ED/LAN).
local PASSABLE_REQUIRED = {
	PD  = true,
	ED  = true,
	LAN = true,
}

-- (LAN_FAMILY removed 2026-09-25: runFinalValidation V6 swapped from a
-- LAN-family flatness check to a PD→ED walkability check, so this set has
-- no remaining readers. Connectivity is guaranteed by ElevationPass Phase 6.)

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

-- TEMPLATE ROTATION / INVERSION (added Sep 30 2026)
-- Templates are authored in ONE canonical orientation; the generator may
-- rotate/invert the WHOLE grid at generation time (locked rule). This is a
-- rigid transform of the entire grid applied ONCE here, before any pass runs,
-- so every downstream pass (regions, floor, features, elevation, connectivity,
-- deployment) sees a normal template and needs no orientation awareness. All
-- internal relationships (PD↔ED distance, LAN connectivity, OBJ reachability)
-- are preserved because every tile moves together.
--
-- orientation: 0..7 = rot(0/90/180/270) × mirror(false/true).
-- 90°/270° swap width/height (non-square templates become their transpose).
-- Returns a NEW { Grid, Width, Height }; the source template is never mutated.
local function transformTemplate(template, orientation)
	local grid = template.Grid
	local W, H = template.Width, template.Height
	local rot    = orientation % 4          -- 0,1,2,3 quarter-turns
	local mirror = orientation >= 4          -- horizontal flip after rotation

	-- Read a source cell with rotation applied. (nx,ny) are 1-based in the
	-- OUTPUT grid; map back to source coords per the rotation.
	local outW, outH
	if rot == 1 or rot == 3 then
		outW, outH = H, W
	else
		outW, outH = W, H
	end

	local newGrid = {}
	for ny = 1, outH do
		newGrid[ny] = {}
		for nx = 1, outW do
			local sx, sy
			if rot == 0 then
				sx, sy = nx, ny
			elseif rot == 1 then           -- 90° clockwise
				sx, sy = ny, (H - nx + 1)
			elseif rot == 2 then           -- 180°
				sx, sy = (W - nx + 1), (H - ny + 1)
			else                            -- rot == 3, 270° clockwise
				sx, sy = (W - ny + 1), nx
			end
			local mx = sx
			if mirror then mx = W - sx + 1 end  -- horizontal mirror in source X
			newGrid[ny][nx] = grid[sy] and grid[sy][mx] or "NEU"
		end
	end
	return { Grid = newGrid, Width = outW, Height = outH }
end

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
-- STEP 7b: VALIDATE GAP SPANS (Round 3 rework, biomes spec row 28)
-- Every deliberate gap placed by FeaturePass.placeGapsAndSpans must still
-- have at least one USABLE bridge span: span tiles flagged isBridge, on
-- passable terrain, not blocked by a non-passable object, and walkable
-- end to end (bank -> span tiles -> bank, each step <= 1 elevation).
-- Orphan gap tiles (isGap with no registered gap record) also fail.
-- A failure rejects the map; the attempt loop re-rolls (bounded by
-- MAX_GENERATION_ATTEMPTS), so a gap without a span can never ship.
--------------------------------------------------

local function validateGapSpans(mapState)
	local tiles = mapState.tiles
	local w, h  = mapState.width, mapState.height
	local gaps  = mapState.bridgeGaps or {}

	local known = {}
	for _, gap in ipairs(gaps) do
		known[gap.id] = true
	end

	-- Orphan gap tiles.
	for y = 1, h do
		for x = 1, w do
			local t = tiles[y][x]
			if t.isGap and not known[t.gapId] then
				return false, string.format(
					"Gap tile (%d,%d) has no registered gap/span (gapId=%s)",
					x, y, tostring(t.gapId))
			end
		end
	end

	local function tileWalkable(t)
		local tDef = TerrainData.Types[t.terrain]
		if not tDef or tDef.passable == false then return false end
		if t.isGap then return false end
		if t.object ~= nil then
			local oDef = ObjectData.Objects[t.object]
			if not (oDef and oDef.passable) then return false end
		end
		return true
	end

	for _, gap in ipairs(gaps) do
		local chain = gap.chain  -- { bankIn, span1..spanN, bankOut }
		local spanCount = 0
		if chain then
			for i = 2, #chain - 1 do
				local c = chain[i]
				local t = tiles[c.y][c.x]
				if t.isBridge and t.bridgeSpanId == gap.id then
					spanCount = spanCount + 1
				end
			end
		end
		if spanCount == 0 then
			return false, string.format("Gap %s has no bridge span", tostring(gap.id))
		end
		-- Usable: every chain tile walkable, every step <= 1.
		for i = 1, #chain do
			local c = chain[i]
			if not isInBounds(c.x, c.y, w, h) or not tileWalkable(tiles[c.y][c.x]) then
				return false, string.format(
					"Gap %s span chain tile (%d,%d) not walkable", tostring(gap.id), c.x, c.y)
			end
			if i > 1 then
				local p = chain[i - 1]
				local d = math.abs(tiles[c.y][c.x].elevation - tiles[p.y][p.x].elevation)
				if d > 1 then
					return false, string.format(
						"Gap %s span not walkable: step %d at (%d,%d)", tostring(gap.id), d, c.x, c.y)
				end
			end
		end
	end

	return true, nil
end

--------------------------------------------------
-- STEP 11b: GAP MIX AUDIT (Round 3 tuning, advisory — never rejects a map)
-- For every deliberate gap, on the FINAL map (terrain + elevation <= 1 +
-- objects, four-cardinal, same rules as validateConnectivity):
--   sealed : its two banks do NOT connect without its span, i.e. the span
--            is the only crossing between them (intent of a CHOKEPOINT).
--   forced : PD -> ED is impossible without its span (the span is on every
--            PD -> ED route; a two-lane map can seal a lane yet not force).
--   poiAdvReachable (only gaps with sealedOnPoiAdv, Round 3 gap mix v2):
--            every POI/ADV region the chokepoint sealed against still has a
--            tile reachable from PD without this span, and no tile of it that
--            PD can reach at all is reachable ONLY across this span.
-- Written to gap.sealed / gap.forced and generationAudit.gapMix. A
-- chokepoint that is not sealed is reported (advisory) but not re-rolled.
--------------------------------------------------

local function auditGapCrossings(mapState)
	local tiles = mapState.tiles
	local w, h  = mapState.width, mapState.height

	local function walkReach(starts, blocked)
		local seen = {}
		local queue, qHead = {}, 1
		for _, s in ipairs(starts) do
			local k = coordKey(s.x, s.y)
			if not seen[k] and not blocked[k] then
				seen[k] = true
				table.insert(queue, s)
			end
		end
		while qHead <= #queue do
			local cur  = queue[qHead]
			qHead      = qHead + 1
			local tile = tiles[cur.y][cur.x]
			for _, dir in ipairs(CARDINAL) do
				local nx, ny = cur.x + dir.x, cur.y + dir.y
				if isInBounds(nx, ny, w, h) then
					local k = coordKey(nx, ny)
					if not seen[k] and not blocked[k] then
						local n    = tiles[ny][nx]
						local tDef = TerrainData.Types[n.terrain]
						local oDef = n.object and ObjectData.Objects[n.object]
						if tDef and tDef.passable ~= false
							and (n.object == nil or (oDef and oDef.passable))
							and math.abs(tile.elevation - n.elevation) <= 1 then
							seen[k] = true
							table.insert(queue, { x = nx, y = ny })
						end
					end
				end
			end
		end
		return seen
	end

	local pdList, edList = {}, {}
	for y = 1, h do
		for x = 1, w do
			local m = tiles[y][x].marker
			if m == "PD" then
				table.insert(pdList, { x = x, y = y })
			elseif m == "ED" then
				table.insert(edList, { x = x, y = y })
			end
		end
	end

	local fpMix = mapState.gapMixAudit or {}
	local mix = { chokepoint = 0, shortcut = 0, fallback = 0,
		chokeSealed = 0, chokeForced = 0, shortcutForced = 0,
		rolledChoke = fpMix.rolledChoke or 0,
		-- Round 3 gap mix v2: POI/ADV seals (FeaturePass counts + final-map check).
		poiAdvSealed = 0, poiAdvReachable = 0,
		poiAdvTried = fpMix.poiAdvTried or 0,
		poiAdvRefused = fpMix.poiAdvRefused or 0 }
	local fromPDAll = nil   -- PD reach with every span open (lazy)
	for _, gap in ipairs(mapState.bridgeGaps or {}) do
		local blocked = {}
		for _, s in ipairs(gap.spanTiles or {}) do
			blocked[coordKey(s.x, s.y)] = true
		end
		local chain = gap.chain or {}
		local sealed, forced = false, false
		if #chain >= 2 then
			local bankOut = chain[#chain]
			local fromIn  = walkReach({ chain[1] }, blocked)
			sealed = not fromIn[coordKey(bankOut.x, bankOut.y)]
		end
		local fromPD = walkReach(pdList, blocked)
		forced = true
		for _, e in ipairs(edList) do
			if fromPD[coordKey(e.x, e.y)] then
				forced = false
				break
			end
		end
		gap.sealed = sealed
		gap.forced = forced
		if gap.sealedOnPoiAdv then
			fromPDAll = fromPDAll or walkReach(pdList, {})
			local ok, done = true, {}
			for _, p in ipairs(gap.poiAdvSealTiles or {}) do
				local k0 = coordKey(p.x, p.y)
				if not done[k0] then
					local marker   = tiles[p.y][p.x].marker
					local anyReach = false
					local queue, qHead = { { x = p.x, y = p.y } }, 1
					done[k0] = true
					while qHead <= #queue do
						local cur = queue[qHead]
						qHead = qHead + 1
						local ck = coordKey(cur.x, cur.y)
						if fromPD[ck] then
							anyReach = true
						elseif fromPDAll[ck] then
							ok = false          -- only reachable across this span
						end
						for _, dir in ipairs(CARDINAL) do
							local nx, ny = cur.x + dir.x, cur.y + dir.y
							if isInBounds(nx, ny, w, h) then
								local nk = coordKey(nx, ny)
								if not done[nk] and tiles[ny][nx].marker == marker then
									done[nk] = true
									table.insert(queue, { x = nx, y = ny })
								end
							end
						end
					end
					if not anyReach then ok = false end
				end
			end
			gap.poiAdvReachable = ok
			mix.poiAdvSealed = mix.poiAdvSealed + 1
			if ok then
				mix.poiAdvReachable = mix.poiAdvReachable + 1
			else
				warn(string.format(
					"[MapService] Gap mix (advisory): chokepoint %s sealed on POI/ADV but that "
						.. "POI/ADV is only reachable across its span on the final map",
					tostring(gap.id)))
			end
		end
		if gap.gapType == "chokepoint" then
			mix.chokepoint = mix.chokepoint + 1
			if sealed then mix.chokeSealed = mix.chokeSealed + 1 end
			if forced then mix.chokeForced = mix.chokeForced + 1 end
			if not sealed then
				warn(string.format(
					"[MapService] Gap mix (advisory): chokepoint %s is not sealed on the final map",
					tostring(gap.id)))
			end
		else
			mix.shortcut = mix.shortcut + 1
			if gap.chokeFallback then mix.fallback = mix.fallback + 1 end
			if forced then mix.shortcutForced = mix.shortcutForced + 1 end
		end
	end
	return mix
end

--------------------------------------------------
-- STEP 8: PLACE OBJECTS
-- Per-tile roll against marker density.
-- Object selected from a REGION-AWARE pool (Slice 5, 2026-10-02): the tile's
-- region object weights (RegionData <- DB regions "Object Weights"; map_gen_rules
-- 6.3 "Region owns local object weights"; open_decisions 'Town region +
-- region-level object weights — Dev wiring') blended over the biome object
-- weights (BiomeData <- DB biomes "Object Weights"). Graceful skip for object
-- names that are not real ObjectData objects yet (House, Wall, Fence, Crate,
-- Cart, Tombstone, Coffin, Tree, Boulder, Door, Bridge, ...).
-- LAN tiles only get passable objects.
-- Non-passable objects require an adjacent passable
-- empty tile for interaction.
--------------------------------------------------

-- Regions-table shorthand -> real ObjectData catalog id (objects_encounters names).
-- Only applied when the target id exists; anything else is skipped.
local REGION_OBJECT_ALIASES = {
	["Chest"]        = "Treasure Chest",
	["Warrior Tomb"] = "Warrior's Tomb",
	["Library"]      = "Library of Enlightenment",
	["Altar"]        = "Altar of Sacrifice",
	["Seer Hut"]     = "Seer's Hut",
}

-- Share of each object draw owned by the REGION pool when that region has at
-- least one resolvable object (the biome pool keeps the remainder). Each pool is
-- normalised to sum 1 first, so the share is independent of the raw weight
-- magnitudes. Dev default — the DB defines no blend ratio (flagged to Designer;
-- tunable).
local REGION_OBJECT_SHARE = 0.5

-- Weight slot for region-pool names that are not real objects yet. Their weight is
-- KEPT (drawn as "place nothing") instead of being redistributed, so live objects
-- keep their DB-authored relative frequency (e.g. Town's Den of Thieves stays 2/88
-- of the Town share, not 2/31). Effect: content-blocked regions generate sparse.
local NO_OBJECT_KEY = "__no_object__"

local function resolveRegionObjectId(name)
	if ObjectData.Objects[name] then return name end
	local alias = REGION_OBJECT_ALIASES[name]
	if alias and ObjectData.Objects[alias] then return alias end
	return nil
end

local function sortedKeys(t)
	local keys = {}
	for k in pairs(t) do table.insert(keys, k) end
	table.sort(keys)
	return keys
end

--- Effective object weights for one region type (cached per placeObjects call).
--- Returns { weights = {id = w}, skipped = {name...}, live = {id...}, regionLive = bool }.
local function buildRegionObjectPool(biome, regionType, cache)
	local cacheKey = regionType or "?"
	if cache[cacheKey] then return cache[cacheKey] end

	local biomeW, bTotal = {}, 0
	local bw = biome.objectWeights or {}
	for _, id in ipairs(sortedKeys(bw)) do
		local wgt = bw[id]
		if ObjectData.Objects[id] and wgt and wgt > 0 then
			biomeW[id] = wgt
			bTotal = bTotal + wgt
		end
	end

	local regionW, rTotal, rLive, skipped, live = {}, 0, 0, {}, {}
	local rDef = regionType and RegionData[regionType]
	local rw = (rDef and rDef.objectWeights) or {}
	for _, name in ipairs(sortedKeys(rw)) do
		local wgt = rw[name]
		if wgt and wgt > 0 then
			local id = resolveRegionObjectId(name) or NO_OBJECT_KEY
			regionW[id] = (regionW[id] or 0) + wgt
			rTotal = rTotal + wgt
			if id ~= NO_OBJECT_KEY then
				rLive = rLive + wgt
				table.insert(live, id)
			else
				table.insert(skipped, name)
			end
		end
	end

	-- Region share applies only when the region has at least one real object.
	local rShare = (rLive > 0) and REGION_OBJECT_SHARE or 0
	if bTotal == 0 and rLive > 0 then rShare = 1 end
	local bShare = (bTotal > 0) and (1 - rShare) or 0

	local out = {}
	for _, id in ipairs(sortedKeys(biomeW)) do
		out[id] = (out[id] or 0) + bShare * biomeW[id] / bTotal
	end
	if rShare > 0 then
		for _, id in ipairs(sortedKeys(regionW)) do
			out[id] = (out[id] or 0) + rShare * regionW[id] / rTotal
		end
	end

	local entry = { weights = out, skipped = skipped, live = live, regionLive = rLive > 0 }
	cache[cacheKey] = entry
	return entry
end

local function placeObjects(tiles, w, h, biome, rng, regionTypeMap)
	local placedObjects   = {}
	local objectIdCounter = 0
	local ops             = 0
	local poolCache       = {}

	local function validObject(objId)
		return ObjectData.Objects[objId] ~= nil
	end
	local function validPassableObject(objId)
		local o = ObjectData.Objects[objId]
		return o ~= nil and o.passable
	end

	-- Peak elevation for this biome: objects/NPCs must NOT spawn on peak tiles
	-- (user rule 2026-10-04). placeObjects runs AFTER ElevationPass, so tile.elevation
	-- is final here. Peak = the biome's configured max elevation.
	local band    = BIOME_ELEVATION[biome and biome.id] or DEFAULT_ELEVATION
	local peakE   = band and band.max or ELEV_PEAK

	-- Accessibility: BFS flood from all PD tiles over passable, non-blocked,
	-- elevation-step<=1 tiles (same movement rule as validateConnectivity). Only
	-- tiles in this reachable set may host an object/NPC.
	local reachable = {}
	do
		local queue, head = {}, 1
		for y = 1, h do
			for x = 1, w do
				if tiles[y][x].marker == "PD" then
					local k = coordKey(x, y)
					if not reachable[k] then reachable[k] = true; table.insert(queue, { x = x, y = y }) end
				end
			end
		end
		while head <= #queue do
			local cur = queue[head]; head = head + 1
			local tile = tiles[cur.y][cur.x]
			for _, dir in ipairs(CARDINAL) do
				local nx, ny = cur.x + dir.x, cur.y + dir.y
				if isInBounds(nx, ny, w, h) then
					local nKey = coordKey(nx, ny)
					if not reachable[nKey] then
						local nTile = tiles[ny][nx]
						local tDef  = TerrainData.Types[nTile.terrain]
						local pass  = tDef and tDef.passable ~= false
						local elevOk = math.abs(tile.elevation - nTile.elevation) <= 1
						if pass and elevOk then
							reachable[nKey] = true
							table.insert(queue, { x = nx, y = ny })
						end
					end
				end
			end
		end
	end

	-- Object BUDGET: ~5% of tiles, clamped. Count driven from the budget instead of an
	-- independent per-tile dice roll, so maps are reliably populated-but-not-cluttered.
	local totalTiles = w * h
	local budget = math.floor(totalTiles * OBJECT_BUDGET_RATE + 0.5)
	budget = math.max(OBJECT_BUDGET_MIN, math.min(OBJECT_BUDGET_MAX, budget))

	-- Gather ELIGIBLE candidate tiles: reachable, not peak, not gap/bridge, empty,
	-- marker density > 0. Each carries its marker density as the draw weight.
	local candidates = {}
	for y = 1, h do
		for x = 1, w do
			local tile    = tiles[y][x]
			local density = MARKER_OBJECT_DENSITY[tile.marker] or 0
			if density > 0
				and tile.object == nil
				and not tile.isGap and not tile.isBridge
				and tile.elevation < peakE                 -- exclude peak tiles
				and reachable[coordKey(x, y)]              -- must be reachable from PD
			then
				table.insert(candidates, { x = x, y = y, weight = density, tile = tile })
			end
			ops = ops + 1
			if ops % YIELD_INTERVAL == 0 then task.wait() end
		end
	end

	-- Balanced-mix tracking.
	local blockerCount, interactCount = 0, 0
	local typeCount = {}  -- copies placed per object type (MAX_COPIES_PER_OBJECT cap)
	local placedInteractTiles = {}  -- for spacing rule
	local function classify(objDef)
		if objDef and objDef.passable == false then return "blocker" end
		-- Interactables = the meaningful categories a unit acts on.
		local c = objDef and objDef.category
		if c == "Aura" or c == "Event" or c == "Exploration" or c == "Siege" then return "interactable" end
		return "deco"
	end
	local function farFromInteractables(x, y)
		for _, t in ipairs(placedInteractTiles) do
			if math.abs(t.x - x) + math.abs(t.y - y) < INTERACT_MIN_SPACING then return false end
		end
		return true
	end

	-- Deterministic weighted draw WITHOUT replacement until the budget is met.
	local placed = 0
	while placed < budget and #candidates > 0 do
		local total = 0
		for _, c in ipairs(candidates) do total = total + c.weight end
		if total <= 0 then break end
		local r = rng:NextNumber() * total
		local acc, pickIdx = 0, nil
		for idx, c in ipairs(candidates) do
			acc = acc + c.weight
			if r <= acc then pickIdx = idx break end
		end
		pickIdx = pickIdx or #candidates
		local cand = table.remove(candidates, pickIdx)
		local x, y, tile = cand.x, cand.y, cand.tile

		-- Choose an object from the region-aware pool.
		local validator = (tile.marker == "LAN" or tile.isCorridor or tile.isBridgeApproach)
			and validPassableObject or validObject
		local regionType = regionTypeMap and tile.regionId and regionTypeMap[tile.regionId] or nil
		local pool = buildRegionObjectPool(biome, regionType, poolCache)
		local selected = weightedSelect(
			pool.weights, rng,
			function(id) return id == NO_OBJECT_KEY or (validator(id) and (typeCount[id] or 0) < MAX_COPIES_PER_OBJECT) end,
			nil
		)
		if selected == NO_OBJECT_KEY then selected = nil end

		if selected then
			local objDef = ObjectData.Objects[selected]
			local kind   = classify(objDef)
			local canPlace = true

			-- Balanced mix: cap blockers; space interactables apart.
			if kind == "blocker" then
				if blockerCount >= math.ceil(budget * BLOCKER_MAX_FRACTION) then canPlace = false end
			elseif kind == "interactable" then
				if not farFromInteractables(x, y) then canPlace = false end
			end

			-- Non-passable objects still need an adjacent passable empty tile.
			if canPlace and objDef and not objDef.passable then
				local hasAdj = false
				for _, dir in ipairs(CARDINAL) do
					local ax, ay = x + dir.x, y + dir.y
					if isInBounds(ax, ay, w, h) then
						local adj  = tiles[ay][ax]
						local aDef = TerrainData.Types[adj.terrain]
						if aDef and aDef.passable ~= false and adj.object == nil then hasAdj = true break end
					end
				end
				canPlace = hasAdj
			end

			if canPlace then
				objectIdCounter = objectIdCounter + 1
				tile.object = selected
				typeCount[selected] = (typeCount[selected] or 0) + 1
				if kind == "blocker" then blockerCount = blockerCount + 1
				elseif kind == "interactable" then
					interactCount = interactCount + 1
					table.insert(placedInteractTiles, { x = x, y = y })
				end
				table.insert(placedObjects, { id = "obj_" .. objectIdCounter, type = selected, x = x, y = y })
				placed = placed + 1
			end
		end

		ops = ops + 1
		if ops % YIELD_INTERVAL == 0 then task.wait() end
	end

	print(string.format(
		"[MapService] placeObjects | budget %d, placed %d (%d blocker, %d interactable, %d other) over %d tiles; peak>=%d excluded, unreachable excluded.",
		budget, placed, blockerCount, interactCount, placed - blockerCount - interactCount, totalTiles, peakE))

	-- Audit (unchanged): which region pools contributed / skipped.
	local poolAudit = {}
	for _, rType in ipairs(sortedKeys(poolCache)) do
		local e = poolCache[rType]
		poolAudit[rType] = { regionLive = e.regionLive, live = e.live, skipped = e.skipped }
		if #e.skipped > 0 then
			print(string.format(
				"[MapService] Region object pool '%s': %d live object(s); skipped (not in ObjectData yet): %s",
				rType, #e.live, table.concat(e.skipped, ", ")))
		end
	end

	return placedObjects, poolAudit
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

-- maxPlayer / maxEnemy: per-side anchor caps. Enemy side is passed the actual
-- generated enemy count (up to ~18) so no enemies stack on one tile; player side
-- is the quest's deployable party size (max 7). Both nil-safe (dev-locked 2026-09-26).
local function placeDeploymentAnchors(tiles, w, h, rng, maxPlayer, maxEnemy)
	local playerCap = maxPlayer or 7
	local enemyCap  = maxEnemy or 18
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

	local player = {}
	local enemy  = {}

	for i = 1, math.min(playerCap, #pdCandidates) do
		table.insert(player, pdCandidates[i])
	end
	for i = 1, math.min(enemyCap, #edCandidates) do
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
				-- Standing object height in elevation levels (nil = unspecified).
				-- Stone Pillar = 4 (objects_encounters row 9, revised 2026-10-02).
				height     = objDef.standingHeight,
			})
		end
	end
	return blockers
end

--- Extract flat 2D grids for GameConstants from tile data.
local function buildGrids(tiles, w, h)
	local elevGrid    = {}
	local terrainGrid = {}
	local objectGrid  = {}

	for y = 1, h do
		elevGrid[y]    = {}
		terrainGrid[y] = {}
		objectGrid[y]  = {}
		for x = 1, w do
			elevGrid[y][x]    = tiles[y][x].elevation
			terrainGrid[y][x] = tiles[y][x].terrain
			objectGrid[y][x]  = tiles[y][x].object  -- nil if no object
		end
	end

	return elevGrid, terrainGrid, objectGrid
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

	-- V6: PD→ED walkability (dev-locked 2026-09-25).
	-- REPLACED the obsolete "LAN-family adjacent diff ≤ 1" flatness rule,
	-- which contradicted the current design (a LAN lane may ramp along its
	-- length, and LAN may form separate islands at different elevations).
	-- The correct invariant is that a ≤1-step path exists from PD to ED,
	-- which ElevationPass Phase 6 guarantees. (V2 above already asserts this
	-- via validateConnectivity; this is the named V6 guard kept in place.)
	local v6ok, v6err = validateConnectivity(tiles, w, h)
	if not v6ok then
		table.insert(errors, "V6 walkability: " .. (v6err or "no PD→ED path"))
	end

	-- V9 (Round 3): every deliberate gap has >= 1 usable bridge span
	-- (post-object re-check; the pre-object check is in the attempt loop).
	local gapOk, gapErr = validateGapSpans(mapState)
	if not gapOk then
		table.insert(errors, "Gap/span: " .. (gapErr or "gap without span"))
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
	-- w, h are set per-attempt AFTER rotation (rotation may swap them).

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

		-- Step 3b: Whole-template rotation/inversion (generation-time, Sep 30 2026).
		-- Pick one of 8 orientations deterministically from this attempt's seed,
		-- transform the WHOLE grid rigidly, and use the transformed grid + its
		-- (possibly swapped) dimensions for everything downstream. Applied here,
		-- before region generation, so no pass sees mixed coordinates.
		local orientation = Random.new(seedCtx.seed):NextInteger(0, 7)
		local oriented    = transformTemplate(template, orientation)
		local w, h        = oriented.Width, oriented.Height

		print(string.format(
			"[MapService] Attempt %d/%d  seed=%d  biome=%s  template=%s  orient=%d  dims=%dx%d",
			attempt, MAX_GENERATION_ATTEMPTS,
			seedCtx.seed, biomeId, templateId, orientation, w, h))

		-- Step 4: Initialize tile grid with markers (from the oriented grid).
		local tiles = initializeTiles(w, h, oriented)

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

		-- Repeat penalty (dev-locked 2026-09-25): draws are sequential and
		-- remember prior picks. Each time a region type is chosen, its weight
		-- is multiplied by 0.5 for subsequent draws — so a fresh type is
		-- favored, but a repeat is still possible (soft penalty, not a ban;
		-- required because most pools have fewer types than a map has regions).
		local regionTypeMap = {}
		local usedCount     = {}   -- region type → times already picked this map
		local REPEAT_FACTOR = 0.5
		for _, region in ipairs(regionResult.Regions) do
			-- Build a penalized copy of the pool based on what's been used.
			local penalized = {}
			for _, e in ipairs(pool) do
				local uses   = usedCount[e.type] or 0
				local factor = REPEAT_FACTOR ^ uses   -- 1, 0.5, 0.25, ...
				table.insert(penalized, {
					type   = e.type,
					weight = e.weight * factor,
				})
			end
			local chosen = weightedSelectArray(penalized, seedCtx.terrainRng)
			regionTypeMap[region.Id] = chosen
			usedCount[chosen] = (usedCount[chosen] or 0) + 1
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
			biomeElevation = (function()
				-- Single-source the global scale onto the per-biome band (DAT: define once).
				local band = BIOME_ELEVATION[biomeId] or DEFAULT_ELEVATION
				local base = band.baseBand or DEFAULT_ELEVATION.baseBand
				return {
					min       = band.min,
					max       = band.max,
					advBonus  = band.advBonus,
					seaLevel  = SEA_LEVEL,
					floor     = ELEV_FLOOR,
					peak      = ELEV_PEAK,
					-- Round 3 band spec (biomes rows 16-26) -> ElevationPass / FeaturePass.
					bMid      = band.bMid or math.floor((SEA_LEVEL + band.max) / 2),
					baseBand  = { lo = base.lo, hi = base.hi },
					spinePct  = band.spinePct or DEFAULT_ELEVATION.spinePct,
					cliffDrop = band.cliffDrop or DEFAULT_ELEVATION.cliffDrop,
					gapPolicy = band.gapPolicy,  -- FeaturePass placeGapsAndSpans (nil = no gaps)
				}
			end)(),
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

		-- Step 7b: Every deliberate gap must have a usable span (Round 3).
		-- Failure = rejected map -> re-roll (bounded by the attempt cap).
		local gapOk, gapErr = validateGapSpans(mapState)
		if not gapOk then
			warn("[MapService] Gap/span validation fail: " .. (gapErr or ""))
			lastErrors = { gapErr or "gap without span" }
			continue
		end

		-- Step 8: Place objects.
		local objects, objectPoolAudit = placeObjects(tiles, w, h, biome, seedCtx.objectRng, regionTypeMap)
		mapState.objectPoolAudit = objectPoolAudit

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
		local elevGrid, terrainGrid, objectGrid = buildGrids(tiles, w, h)
		local blockers              = buildBlockers(objects)

		-- Populate final mapState fields for downstream consumers.
		mapState.deploymentZones = deployZones
		mapState.objects         = objects
		mapState.battleCondition = battleCondition
		mapState.elevationGrid   = elevGrid
		mapState.terrainGrid     = terrainGrid
		mapState.objectGrid      = objectGrid
		mapState.blockers        = blockers

		-- Runtime chasm-floor + span data (consumed by GameConstants.SetGeneratedMap
		-- and TileEffectService at battle start):
		--   chasmFloorTiles    : every deliberate gap tile (map_gen_rules rows 59/65)
		--   floorEffects       : gap tiles carrying a permanent floor TILE EFFECT
		--                        (Vines / Tar Pit; rows 59/67) -> per-tile base slot
		--   protectedSpanTiles : bridge span tiles (isBridge) — PROTECTED from
		--                        lowering / cracking / terrain transforms (row 60)
		local chasmFloorTiles, floorEffects, protectedSpanTiles = {}, {}, {}
		for ty = 1, h do
			for tx = 1, w do
				local t = tiles[ty][tx]
				if t.isGap then
					table.insert(chasmFloorTiles, { x = tx, y = ty, gapId = t.gapId })
					if t.gapFloorEffect then
						table.insert(floorEffects, { x = tx, y = ty, effectId = t.gapFloorEffect })
					end
				end
				if t.isBridge then
					table.insert(protectedSpanTiles, { x = tx, y = ty,
						spanId = t.bridgeSpanId, safetyNet = t.bridgeRepair == true })
				end
			end
		end
		mapState.chasmFloorTiles    = chasmFloorTiles
		mapState.floorEffects       = floorEffects
		mapState.protectedSpanTiles = protectedSpanTiles
		mapState.generationAudit = {
			attempts         = attempt,
			seed             = seedCtx.seed,
			validationPassed = false,
			-- Round 3 gap mix (advisory): chokepoint / shortcut counts, fallbacks,
			-- and how many spans are sealed / forced on the final map.
			gapMix           = auditGapCrossings(mapState),
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
