local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CTRBLXAI = ReplicatedStorage:WaitForChild("CTRBLXAI")

local TileDefinitions = require(
	CTRBLXAI
		:WaitForChild("Shared")
		:WaitForChild("TileDefinitions")
)

local GameConstants = require(
	CTRBLXAI
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

local Template = require(
	CTRBLXAI
		:WaitForChild("Templates")
		:WaitForChild("T01_FrontlinePressure")
)

local RegionGenerator = require(
	ServerScriptService:WaitForChild("RegionGenerator")
)

local TerrainTextures = require(
	CTRBLXAI
		:WaitForChild("Shared")
		:WaitForChild("TerrainTextures")
)

--------------------------------------------------
-- SETTINGS
--------------------------------------------------

local TILE_SIZE = 5
local TILE_HEIGHT = 0.6
local TILE_MATERIAL = Enum.Material.SmoothPlastic

local GRID_COLOR = Color3.fromRGB(20, 20, 20)
local GRID_MATERIAL = Enum.Material.SmoothPlastic
local GRID_THICKNESS = 0.6

local DEFAULT_ELEVATION = 5

local BIOME_ID = "Plains"
local REGION_COUNT = 3
local MINIMUM_REGION_PERCENT = 0.25

local REGION_SEED = nil
local INITIAL_VIEW_MODE = "REGION"

--------------------------------------------------
-- VALIDATE SETTINGS
--------------------------------------------------

assert(
	INITIAL_VIEW_MODE == "REGION"
		or INITIAL_VIEW_MODE == "TEMPLATE",
	'INITIAL_VIEW_MODE must be "REGION" or "TEMPLATE".'
)

--------------------------------------------------
-- GENERATE REGION OWNERSHIP
--------------------------------------------------

local regionResult = RegionGenerator.Generate({
	Width = Template.Width,
	Height = Template.Height,
	BiomeId = BIOME_ID,
	RegionCount = REGION_COUNT,
	MinimumRegionPercent = MINIMUM_REGION_PERCENT,
	Seed = REGION_SEED,
})

assert(
	regionResult.Width == Template.Width,
	"Region width does not match template width."
)

assert(
	regionResult.Height == Template.Height,
	"Region height does not match template height."
)

local regionById = {}

for _, region in ipairs(regionResult.Regions) do
	regionById[region.Id] = region
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

mapFolder:SetAttribute(
	"TemplateId",
	Template.Id
)

mapFolder:SetAttribute(
	"TemplateName",
	Template.Name
)

mapFolder:SetAttribute(
	"BiomeId",
	regionResult.BiomeId
)

mapFolder:SetAttribute(
	"RegionCount",
	#regionResult.Regions
)

mapFolder:SetAttribute(
	"MinimumRegionPercent",
	regionResult.MinimumRegionPercent
)

mapFolder:SetAttribute(
	"MinimumRegionTileCount",
	regionResult.MinimumRegionTileCount
)

mapFolder:SetAttribute(
	"InitialViewMode",
	INITIAL_VIEW_MODE
)

mapFolder:SetAttribute(
	"TileMaterial",
	TILE_MATERIAL.Name
)

if regionResult.Seed ~= nil then
	mapFolder:SetAttribute(
		"RegionSeed",
		regionResult.Seed
	)
end

mapFolder.Parent = workspace

--------------------------------------------------
-- MAP POSITIONING
--------------------------------------------------

local mapWidthStuds =
	Template.Width * TILE_SIZE

local mapHeightStuds =
	Template.Height * TILE_SIZE

local offsetX =
	-(mapWidthStuds / 2)

local offsetZ =
	-(mapHeightStuds / 2)

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function getTilePosition(x, y)
	return Vector3.new(
		offsetX + ((x - 0.5) * TILE_SIZE),
		TILE_HEIGHT / 2,
		offsetZ + ((y - 0.5) * TILE_SIZE)
	)
end

local function getTemplateColor(marker)
	return TileDefinitions[marker]
		or Color3.fromRGB(255, 0, 255)
end

local function getRegionData(x, y)
	local row = regionResult.Grid[y]

	assert(
		row ~= nil,
		string.format(
			"Region row %d is missing.",
			y
		)
	)

	local regionId = row[x]

	assert(
		regionId ~= nil,
		string.format(
			"Tile (%d, %d) has no Region ID.",
			x,
			y
		)
	)

	local region = regionById[regionId]

	assert(
		region ~= nil,
		string.format(
			'Region "%s" metadata is missing.',
			tostring(regionId)
		)
	)

	return region
end

local function getInitialDisplayColor(
	templateColor,
	regionColor
)
	if INITIAL_VIEW_MODE == "TEMPLATE" then
		return templateColor
	end

	return regionColor
end

local function makeSurfacesSmooth(part)
	part.TopSurface =
		Enum.SurfaceType.Smooth

	part.BottomSurface =
		Enum.SurfaceType.Smooth

	part.LeftSurface =
		Enum.SurfaceType.Smooth

	part.RightSurface =
		Enum.SurfaceType.Smooth

	part.FrontSurface =
		Enum.SurfaceType.Smooth

	part.BackSurface =
		Enum.SurfaceType.Smooth
end

--------------------------------------------------
-- TILE CREATION
--------------------------------------------------

local function createTile(x, y, marker)
	local templateColor =
		getTemplateColor(marker)

	local region =
		getRegionData(x, y)

	local tile = Instance.new("Part")

	tile.Name = string.format(
		"Tile_%02d_%02d_%s",
		x,
		y,
		marker
	)

	tile.Anchored = true
	tile.Material = TILE_MATERIAL
	tile.CastShadow = false

	makeSurfacesSmooth(tile)

	tile.Color = getInitialDisplayColor(
		templateColor,
		region.DebugColor
	)

	tile.Size = Vector3.new(
		TILE_SIZE,
		TILE_HEIGHT,
		TILE_SIZE
	)

	tile.Position =
		getTilePosition(x, y)

	tile.CanCollide = true
	tile.CanTouch = true
	tile.CanQuery = true

	--------------------------------------------------
	-- TILE IDENTITY
	--------------------------------------------------

	tile:SetAttribute(
		"IsTemplateTile",
		true
	)

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
		templateColor
	)

	--------------------------------------------------
	-- BIOME LAYER
	--------------------------------------------------

	tile:SetAttribute(
		"BiomeId",
		region.BiomeId
	)

	--------------------------------------------------
	-- REGION LAYER
	--------------------------------------------------

	tile:SetAttribute(
		"RegionId",
		region.Id
	)

	tile:SetAttribute(
		"RegionDebugColor",
		region.DebugColor
	)

	--------------------------------------------------
	-- PROTOTYPE TILE DATA
	--------------------------------------------------

	tile:SetAttribute(
		"Elevation",
		DEFAULT_ELEVATION
	)

	tile:SetAttribute(
		"Terrain",
		"Prototype"
	)

	tile:SetAttribute(
		"Effect",
		"None"
	)

	tile:SetAttribute(
		"Passable",
		true
	)

	--------------------------------------------------
	-- PROTOTYPE OBJECT DATA
	--------------------------------------------------

	tile:SetAttribute(
		"ObjectName",
		"None"
	)

	tile:SetAttribute(
		"ObjectCategory",
		"None"
	)

	tile:SetAttribute(
		"ObjectPassabilityImpact",
		"None"
	)

	tile.Parent = mapFolder
end

--------------------------------------------------
-- GRID OVERLAY
--------------------------------------------------

local function createGridLine(
	name,
	position,
	size
)
	local line = Instance.new("Part")

	line.Name = name
	line.Anchored = true
	line.Material = GRID_MATERIAL
	line.Color = GRID_COLOR
	line.Size = size
	line.Position = position
	line.CastShadow = false

	makeSurfacesSmooth(line)

	line.CanCollide = false
	line.CanTouch = false
	line.CanQuery = false

	line.Parent = mapFolder
end

local function createGridOverlay()
	for x = 0, Template.Width do
		createGridLine(
			"GridLine_V_" .. x,
			Vector3.new(
				offsetX + (x * TILE_SIZE),
				TILE_HEIGHT + 0.06,
				0
			),
			Vector3.new(
				GRID_THICKNESS,
				0.06,
				mapHeightStuds
			)
		)
	end

	for y = 0, Template.Height do
		createGridLine(
			"GridLine_H_" .. y,
			Vector3.new(
				0,
				TILE_HEIGHT + 0.06,
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

-- Presentation-only map metadata for client camera bounds
mapFolder:SetAttribute(
	"MapWidth",
	Template.Width
)
mapFolder:SetAttribute(
	"MapHeight",
	Template.Height
)
mapFolder:SetAttribute(
	"TileSize",
	TILE_SIZE
)

--------------------------------------------------
-- RENDER MAP
--------------------------------------------------

local markerCounts = {}
local renderedRegionCounts = {}

for y = 1, Template.Height do
	for x = 1, Template.Width do
		local marker =
			Template.Grid[y]
			and Template.Grid[y][x]
			or "NEU"

		local regionId =
			regionResult.Grid[y][x]

		markerCounts[marker] =
			(markerCounts[marker] or 0) + 1

		renderedRegionCounts[regionId] =
			(renderedRegionCounts[regionId] or 0)
			+ 1

		createTile(x, y, marker)
	end
end

createGridOverlay()

--------------------------------------------------
-- DEBUG OUTPUT
--------------------------------------------------

print("====================================")
print("CTRBLXAI Template Viewer Loaded")
print("====================================")

print(
	"Template:",
	Template.Id,
	Template.Name
)

print(
	"Size:",
	Template.Width,
	"x",
	Template.Height
)

print("Tile Size:", TILE_SIZE)
print("Tile Material:", TILE_MATERIAL.Name)

print(
	"Map Studs:",
	mapWidthStuds,
	"x",
	mapHeightStuds
)

print(
	"Initial View:",
	INITIAL_VIEW_MODE
)

print(
	"Biome:",
	regionResult.BiomeId
)

print(
	"Region Count:",
	#regionResult.Regions
)

print(
	"Minimum Region Tiles:",
	regionResult.MinimumRegionTileCount
)

if regionResult.Seed ~= nil then
	print(
		"Region Seed:",
		regionResult.Seed
	)
else
	print("Region Seed: Random")
end

print("")
print("Marker Counts")

for marker, count in pairs(markerCounts) do
	print(marker, count)
end

print("")
print("Region Counts")

for _, region in ipairs(
	regionResult.Regions
) do
	local count =
		renderedRegionCounts[region.Id]
		or 0

	local percentage =
		(
			count
			/ (
				Template.Width
				* Template.Height
			)
		) * 100

	print(
		region.Id,
		"Tiles:",
		count,
		"Percent:",
		string.format(
			"%.2f%%",
			percentage
		)
	)
end

print("====================================")

--------------------------------------------------
-- SLICE 2: APPLY BATTLE ELEVATION TO TILES
--
-- The 8×8 battle grid maps onto template tiles (12-19, 7-14).
-- Battle tile (bx, by) = template tile (bx + 11, by + 6).
-- Adjust the Y position and Size.Y of those tiles based on the
-- elevation map in GameConstants.
--------------------------------------------------

local BATTLE_OFFSET_X = 11  -- battle tile 1 → template col 12
local BATTLE_OFFSET_Y = 6   -- battle tile 1 → template row 7
local ELEVATION_STEP  = 2.5 -- extra Y studs per elevation level above 1

local ELEVATED_COLOR  = Color3.fromRGB(180, 170, 150) -- stone look for raised tiles
local PEAK_COLOR      = Color3.fromRGB(220, 200, 160) -- high peak (elevation 3)
local MUD_COLOR       = Color3.fromRGB(90, 70, 40)    -- mud terrain tint
local BLOCKER_COLOR   = Color3.fromRGB(50, 50, 55)    -- dark grey for impassable objects

local battleTileCount = 0

for _, child in ipairs(mapFolder:GetChildren()) do
	if child:IsA("BasePart") and child:GetAttribute("IsTemplateTile") then
		local tx = child:GetAttribute("X")
		local ty = child:GetAttribute("Y")

		if tx and ty then
			-- Convert template coords to battle coords
			local bx = tx - BATTLE_OFFSET_X
			local by = ty - BATTLE_OFFSET_Y

			-- Check if this tile is within the 8×8 battle grid
			if bx >= 1 and bx <= 8 and by >= 1 and by <= 8 then
				local elev = GameConstants.GetElevation(bx, by)
				local tileHeight = TILE_HEIGHT + (elev - 1) * ELEVATION_STEP
				local surfaceY = tileHeight / 2

				child.Size = Vector3.new(child.Size.X, tileHeight, child.Size.Z)
				child.Position = Vector3.new(child.Position.X, surfaceY, child.Position.Z)

				child:SetAttribute("Elevation", elev)
				local terrainName = GameConstants.GetTerrainId(bx, by)
				child:SetAttribute("Terrain", terrainName)

				-- Apply terrain texture with random rotation/flip
				TerrainTextures.Apply(child, terrainName)

				if elev >= 3 then
					child.Color = PEAK_COLOR
					child.Material = Enum.Material.SmoothPlastic
				elseif elev >= 2 then
					child.Color = ELEVATED_COLOR
					child.Material = Enum.Material.SmoothPlastic
				end

				-- Tint Mud tiles
				if GameConstants.GetTerrainId(bx, by) == "Mud" then
					child.Color = MUD_COLOR
					child.Material = Enum.Material.SmoothPlastic
				end

				-- Render blockers as dark cubes on top of the tile
				if GameConstants.IsBlocked(bx, by) then
					child:SetAttribute("Passable", false)
					child:SetAttribute("ObjectName", "Blocker")
					child:SetAttribute("ObjectCategory", "Obstacle")
					child:SetAttribute("ObjectPassabilityImpact", "Impassable")
					local blockerHeight = ELEVATION_STEP * 1.5
					local blocker = Instance.new("Part")
					blocker.Name      = string.format("Blocker_%d_%d", bx, by)
					blocker.Anchored  = true
					blocker.CanCollide = true
					blocker.CanQuery  = false
					blocker.CastShadow = true
					blocker.Material  = Enum.Material.SmoothPlastic
					blocker.Color     = BLOCKER_COLOR
					blocker.Size      = Vector3.new(TILE_SIZE * 0.7, blockerHeight, TILE_SIZE * 0.7)
					blocker.Position  = Vector3.new(
						child.Position.X,
						surfaceY + tileHeight / 2 + blockerHeight / 2,
						child.Position.Z
					)
					blocker.Parent = mapFolder
				end

				battleTileCount = battleTileCount + 1
			end
		end
	end
end

print(string.format("[TemplateViewer] Battle elevation applied to %d tiles.", battleTileCount))
