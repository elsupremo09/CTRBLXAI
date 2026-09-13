-- TemplateViewer.server.lua
-- CTRBLXAI | Slice 5 Phase 4 — Renders MapService-generated battlefield
--
-- Renders the full 30×20 tile grid with terrain textures, elevation
-- height, region ownership, and placed objects from MapService output.
--
-- View modes (toggle via INITIAL_VIEW_MODE):
--   TERRAIN  (default) — terrain textures + dark backing
--   REGION   — region debug colors
--   TEMPLATE — template marker colors
--
-- Architecture:
--   TemplateViewer calls MapService.Generate() with the same parameters
--   as Main.server.lua (deterministic — same seed = same map).
--   The mapFolder is parented to workspace AFTER all tiles are created
--   so Main's WaitForChild("TemplateViewerMap") blocks until rendering
--   is complete.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CTRBLXAI = ReplicatedStorage:WaitForChild("CTRBLXAI")

local TileDefinitions = require(
	CTRBLXAI
		:WaitForChild("Shared")
		:WaitForChild("TileDefinitions")
)

local TerrainTextures = require(
	CTRBLXAI
		:WaitForChild("Shared")
		:WaitForChild("TerrainTextures")
)

local MapService = require(
	ServerScriptService
		:WaitForChild("Game")
		:WaitForChild("MapService")
)

--------------------------------------------------
-- SETTINGS
--------------------------------------------------

local TILE_SIZE      = 5
local TILE_HEIGHT    = 0.6
local TILE_MATERIAL  = Enum.Material.SmoothPlastic
local ELEVATION_STEP = 2.5

local GRID_COLOR     = Color3.fromRGB(20, 20, 20)
local GRID_MATERIAL  = Enum.Material.SmoothPlastic
local GRID_THICKNESS = 0.08

local BIOME_ID    = "Plains"
local TEMPLATE_ID = "T01"
local MAP_SEED    = 12345

local INITIAL_VIEW_MODE = "TERRAIN"

local BLOCKER_COLOR = Color3.fromRGB(50, 50, 55)

--------------------------------------------------
-- TERRAIN FALLBACK COLORS
-- Used as the tile Part base color and stored as the
-- TerrainColor attribute for view-mode toggling.
-- In TERRAIN mode, TerrainTextures.Apply() adds the
-- image overlay and the Part color is set to dark
-- (20,20,20) so the texture dominates.
--------------------------------------------------

local TERRAIN_COLORS = {
	Clear                  = Color3.fromRGB(200, 190, 170),
	Grassland              = Color3.fromRGB( 90, 160,  60),
	["Clover Field"]       = Color3.fromRGB( 80, 180,  70),
	Sand                   = Color3.fromRGB(210, 190, 130),
	Rocky                  = Color3.fromRGB(140, 135, 130),
	Mud                    = Color3.fromRGB( 90,  70,  40),
	Swamp                  = Color3.fromRGB( 60,  80,  50),
	["Shallow Water"]      = Color3.fromRGB( 80, 140, 200),
	["Deep Water"]         = Color3.fromRGB( 40,  80, 160),
	Ice                    = Color3.fromRGB(180, 220, 240),
	Metal                  = Color3.fromRGB(160, 160, 170),
	Molten                 = Color3.fromRGB(220, 100,  30),
	["Magic Circle"]       = Color3.fromRGB(150, 100, 200),
	["Tainted Ground"]     = Color3.fromRGB(100,  60, 100),
	["Cracked Ground"]     = Color3.fromRGB(150, 140, 120),
	Quicksand              = Color3.fromRGB(180, 160, 100),
	["Wooden Floor"]       = Color3.fromRGB(160, 120,  70),
	["Monolith (One-way)"] = Color3.fromRGB(100, 100, 180),
	["Monolith (Two-way)"] = Color3.fromRGB(100, 180, 100),
	["Dirt Road"]          = Color3.fromRGB(160, 130,  90),
	Forest                 = Color3.fromRGB( 40, 100,  30),
	["Stone Road"]         = Color3.fromRGB(150, 150, 140),
}

local function getTerrainColor(terrainId)
	return TERRAIN_COLORS[terrainId]
		or Color3.fromRGB(200, 190, 170)
end

--------------------------------------------------
-- REGION DEBUG PALETTE
--------------------------------------------------

local REGION_DEBUG_PALETTE = {
	Color3.fromRGB(220, 100, 100),
	Color3.fromRGB(100, 180, 100),
	Color3.fromRGB(100, 130, 220),
	Color3.fromRGB(220, 200,  80),
	Color3.fromRGB(180, 100, 220),
	Color3.fromRGB(100, 200, 200),
	Color3.fromRGB(220, 140,  80),
	Color3.fromRGB(180, 180, 180),
}

--------------------------------------------------
-- VALIDATE SETTINGS
--------------------------------------------------

assert(
	INITIAL_VIEW_MODE == "TERRAIN"
		or INITIAL_VIEW_MODE == "REGION"
		or INITIAL_VIEW_MODE == "TEMPLATE",
	'INITIAL_VIEW_MODE must be "TERRAIN", "REGION", or "TEMPLATE".'
)

--------------------------------------------------
-- GENERATE MAP VIA MAPSERVICE
-- Same parameters as Main.server.lua.
-- Deterministic: same seed = identical map.
--------------------------------------------------

local generatedMap = MapService.Generate(
	BIOME_ID, TEMPLATE_ID, MAP_SEED
)

local MAP_WIDTH  = generatedMap.width
local MAP_HEIGHT = generatedMap.height

-- Build region → debug color lookup.
local regionColorMap = {}

do
	local idx  = 0
	local seen = {}

	for y = 1, MAP_HEIGHT do
		for x = 1, MAP_WIDTH do
			local rid = generatedMap.tiles[y][x].regionId
			if rid and not seen[rid] then
				seen[rid] = true
				idx = idx + 1
				regionColorMap[rid] = REGION_DEBUG_PALETTE[
					((idx - 1) % #REGION_DEBUG_PALETTE) + 1
				]
			end
		end
	end
end

--------------------------------------------------
-- CLEANUP
--------------------------------------------------

local oldMap = workspace:FindFirstChild(
	"TemplateViewerMap"
)

if oldMap then
	oldMap:Destroy()
end

local mapFolder = Instance.new("Folder")

mapFolder.Name = "TemplateViewerMap"

mapFolder:SetAttribute("TemplateId", TEMPLATE_ID)
mapFolder:SetAttribute("BiomeId", generatedMap.biomeId)
mapFolder:SetAttribute("Seed", generatedMap.seed)
mapFolder:SetAttribute("InitialViewMode", INITIAL_VIEW_MODE)
mapFolder:SetAttribute("TileMaterial", TILE_MATERIAL.Name)
mapFolder:SetAttribute("MapWidth", MAP_WIDTH)
mapFolder:SetAttribute("MapHeight", MAP_HEIGHT)
mapFolder:SetAttribute("TileSize", TILE_SIZE)

-- NOTE: mapFolder is parented to workspace AFTER all tiles
-- are created. This ensures Main.server.lua's WaitForChild
-- blocks until the entire map is ready.

--------------------------------------------------
-- MAP POSITIONING
--------------------------------------------------

local mapWidthStuds  = MAP_WIDTH * TILE_SIZE
local mapHeightStuds = MAP_HEIGHT * TILE_SIZE

local offsetX = -(mapWidthStuds / 2)
local offsetZ = -(mapHeightStuds / 2)

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function getTileHeight(elevation)
	return TILE_HEIGHT
		+ (elevation - 1) * ELEVATION_STEP
end

local function getTilePosition(x, y, elevation)
	local h = getTileHeight(elevation)

	return Vector3.new(
		offsetX + ((x - 0.5) * TILE_SIZE),
		h / 2,
		offsetZ + ((y - 0.5) * TILE_SIZE)
	)
end

local function getTemplateColor(marker)
	return TileDefinitions[marker]
		or Color3.fromRGB(255, 0, 255)
end

local function getDisplayColor(terrainId, regionId, marker)
	if INITIAL_VIEW_MODE == "TEMPLATE" then
		return getTemplateColor(marker)
	elseif INITIAL_VIEW_MODE == "REGION" then
		return regionColorMap[regionId]
			or Color3.fromRGB(128, 128, 128)
	end

	-- TERRAIN mode: fallback color (texture covers this).
	return getTerrainColor(terrainId)
end

local function makeSurfacesSmooth(part)
	part.TopSurface    = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.LeftSurface   = Enum.SurfaceType.Smooth
	part.RightSurface  = Enum.SurfaceType.Smooth
	part.FrontSurface  = Enum.SurfaceType.Smooth
	part.BackSurface   = Enum.SurfaceType.Smooth
end

--------------------------------------------------
-- TILE CREATION
--------------------------------------------------

local function createTile(x, y, tileData)
	local terrainId  = tileData.terrain
	local elevation  = tileData.elevation
	local regionId   = tileData.regionId
	local marker     = tileData.marker
	local objectName = tileData.object

	local tileHeight = getTileHeight(elevation)
	local position   = getTilePosition(x, y, elevation)

	local tile = Instance.new("Part")

	tile.Name = string.format(
		"Tile_%02d_%02d",
		x,
		y
	)

	tile.Anchored   = true
	tile.Material   = TILE_MATERIAL
	tile.CastShadow = false

	makeSurfacesSmooth(tile)

	tile.Size = Vector3.new(
		TILE_SIZE,
		tileHeight,
		TILE_SIZE
	)

	tile.Position = position
	tile.Color    = getDisplayColor(
		terrainId, regionId, marker
	)

	tile.CanCollide = true
	tile.CanTouch   = true
	tile.CanQuery   = true

	--------------------------------------------------
	-- TILE IDENTITY
	--------------------------------------------------

	tile:SetAttribute("IsTemplateTile", true)
	tile:SetAttribute("X", x)
	tile:SetAttribute("Y", y)

	--------------------------------------------------
	-- TEMPLATE LAYER
	--------------------------------------------------

	tile:SetAttribute(
		"TemplateMarker",
		marker
	)

	tile:SetAttribute(
		"TemplateColor",
		getTemplateColor(marker)
	)

	--------------------------------------------------
	-- BIOME LAYER
	--------------------------------------------------

	tile:SetAttribute(
		"BiomeId",
		generatedMap.biomeId
	)

	--------------------------------------------------
	-- REGION LAYER
	--------------------------------------------------

	tile:SetAttribute(
		"RegionId",
		regionId or "unknown"
	)

	tile:SetAttribute(
		"RegionDebugColor",
		regionColorMap[regionId]
			or Color3.fromRGB(128, 128, 128)
	)

	--------------------------------------------------
	-- TERRAIN DATA (from MapService)
	--------------------------------------------------

	tile:SetAttribute("Elevation", elevation)
	tile:SetAttribute("Terrain", terrainId)

	tile:SetAttribute(
		"TerrainColor",
		getTerrainColor(terrainId)
	)

	-- Effect (none at map gen — TileEffectService sets
	-- these during battle).
	tile:SetAttribute("Effect", "None")

	-- Passability (terrain-level check).
	local passable = true

	if terrainId == "Quicksand" then
		passable = false
	end

	tile:SetAttribute("Passable", passable)

	--------------------------------------------------
	-- OBJECT DATA
	--------------------------------------------------

	if objectName then
		tile:SetAttribute("ObjectName", objectName)
		tile:SetAttribute("ObjectCategory", "MapObject")
		tile:SetAttribute(
			"ObjectPassabilityImpact",
			"Occupied"
		)
	else
		tile:SetAttribute("ObjectName", "None")
		tile:SetAttribute("ObjectCategory", "None")
		tile:SetAttribute(
			"ObjectPassabilityImpact",
			"None"
		)
	end

	--------------------------------------------------
	-- APPLY TERRAIN TEXTURE (TERRAIN view mode)
	--------------------------------------------------

	if INITIAL_VIEW_MODE == "TERRAIN" then
		TerrainTextures.Apply(tile, terrainId)
		-- Dark backing so texture edges look clean.
		tile.Color = Color3.fromRGB(20, 20, 20)
	end

	tile.Parent = mapFolder
end

--------------------------------------------------
-- BLOCKER RENDERING
-- Non-passable objects rendered as dark cubes above
-- their tile. Updates tile attributes accordingly.
--------------------------------------------------

local function renderBlockers()
	for _, blocker in ipairs(generatedMap.blockers) do
		local bx = blocker.tileX
		local by = blocker.tileY

		local tileData  = generatedMap.tiles[by][bx]
		local elevation = tileData.elevation
		local tileHeight = getTileHeight(elevation)

		-- Find the tile Part and update attributes.
		for _, child in ipairs(mapFolder:GetChildren()) do
			if child:GetAttribute("X") == bx
				and child:GetAttribute("Y") == by
			then
				child:SetAttribute("Passable", false)

				child:SetAttribute(
					"ObjectName",
					blocker.objectType
				)

				child:SetAttribute(
					"ObjectCategory",
					"Obstacle"
				)

				child:SetAttribute(
					"ObjectPassabilityImpact",
					"Impassable"
				)

				-- Create visual blocker cube.
				local blockerHeight =
					ELEVATION_STEP * 1.5

				local blockerPart =
					Instance.new("Part")

				blockerPart.Name = string.format(
					"Blocker_%d_%d",
					bx,
					by
				)

				blockerPart.Anchored   = true
				blockerPart.CanCollide = true
				blockerPart.CanQuery   = false
				blockerPart.CastShadow = true
				blockerPart.Material   =
					Enum.Material.SmoothPlastic
				blockerPart.Color = BLOCKER_COLOR

				blockerPart.Size = Vector3.new(
					TILE_SIZE * 0.7,
					blockerHeight,
					TILE_SIZE * 0.7
				)

				blockerPart.Position = Vector3.new(
					child.Position.X,
					child.Position.Y
						+ tileHeight / 2
						+ blockerHeight / 2,
					child.Position.Z
				)

				blockerPart.Parent = mapFolder
				break
			end
		end
	end
end

--------------------------------------------------
-- GRID OVERLAY
-- Positioned above the maximum biome elevation so
-- grid lines do not clip into elevated tiles.
-- Semi-transparent so they do not obstruct the view.
--------------------------------------------------

local function createGridLine(
	name,
	position,
	size
)
	local line = Instance.new("Part")

	line.Name        = name
	line.Anchored    = true
	line.Material    = GRID_MATERIAL
	line.Color       = GRID_COLOR
	line.Size        = size
	line.Position    = position
	line.CastShadow  = false
	line.Transparency = 0.5

	makeSurfacesSmooth(line)

	line.CanCollide = false
	line.CanTouch   = false
	line.CanQuery   = false

	line.Parent = mapFolder
end

local function createGridOverlay()
	-- Grid sits just above the highest possible tile.
	-- Plains max elevation = 3.
	local maxElevation = 3
	local gridY = getTileHeight(maxElevation) + 0.06

	for x = 0, MAP_WIDTH do
		createGridLine(
			"GridLine_V_" .. x,
			Vector3.new(
				offsetX + (x * TILE_SIZE),
				gridY,
				0
			),
			Vector3.new(
				GRID_THICKNESS,
				0.06,
				mapHeightStuds
			)
		)
	end

	for y = 0, MAP_HEIGHT do
		createGridLine(
			"GridLine_H_" .. y,
			Vector3.new(
				0,
				gridY,
				offsetZ + (y * TILE_SIZE)
			),
			Vector3.new(
				mapWidthStuds,
				0.03,
				GRID_THICKNESS
			)
		)
	end
end

--------------------------------------------------
-- RENDER MAP
--------------------------------------------------

local markerCounts  = {}
local terrainCounts = {}

for y = 1, MAP_HEIGHT do
	for x = 1, MAP_WIDTH do
		local tileData = generatedMap.tiles[y][x]

		markerCounts[tileData.marker] =
			(markerCounts[tileData.marker] or 0) + 1

		terrainCounts[tileData.terrain] =
			(terrainCounts[tileData.terrain] or 0) + 1

		createTile(x, y, tileData)
	end
end

renderBlockers()
createGridOverlay()

-- Parent LAST — Main.server.lua WaitForChild blocks
-- until this line, guaranteeing all tiles exist.
mapFolder.Parent = workspace

--------------------------------------------------
-- DEBUG OUTPUT
--------------------------------------------------

print("====================================")
print("CTRBLXAI Template Viewer Loaded")
print("====================================")

print(string.format(
	"Template: %s",
	TEMPLATE_ID
))

print(string.format(
	"Size: %d x %d",
	MAP_WIDTH,
	MAP_HEIGHT
))

print(string.format(
	"Biome: %s",
	BIOME_ID
))

print(string.format(
	"Seed: %d",
	generatedMap.seed
))

print(string.format(
	"Initial View: %s",
	INITIAL_VIEW_MODE
))

print("Tile Size:", TILE_SIZE)
print("Tile Material:", TILE_MATERIAL.Name)

print(string.format(
	"Map Studs: %d x %d",
	mapWidthStuds,
	mapHeightStuds
))

print(string.format(
	"Objects: %d",
	#generatedMap.objects
))

print(string.format(
	"Blockers: %d",
	#generatedMap.blockers
))

print(string.format(
	"Battle Condition: %s",
	generatedMap.battleCondition
))

print("")
print("Marker Counts:")

for marker, count in pairs(markerCounts) do
	print(string.format(
		"  %s: %d",
		marker,
		count
	))
end

print("")
print("Terrain Counts:")

for terrain, count in pairs(terrainCounts) do
	print(string.format(
		"  %s: %d",
		terrain,
		count
	))
end

print("")
print("Region Colors:")

for rid, color in pairs(regionColorMap) do
	print(string.format(
		"  %s: RGB(%d, %d, %d)",
		rid,
		math.floor(color.R * 255),
		math.floor(color.G * 255),
		math.floor(color.B * 255)
	))
end

print("====================================")

print(string.format(
	"[TemplateViewer] Rendered %d tiles with"
		.. " generated terrain and elevation.",
	MAP_WIDTH * MAP_HEIGHT
))
