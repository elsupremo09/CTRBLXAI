-- MapRenderer.lua
-- CTRBLXAI | Slice 5 — Shared map rendering module
--
-- Extracted from TemplateViewer.server.lua so both
-- TemplateViewer and DevCommand (Regenerate) can render
-- MapService output into workspace Instances.
--
-- API:
--   MapRenderer.Render(generatedMap, viewMode) → Folder (unparented)
--   MapRenderer.SetViewMode(mapFolder, mode)   → nil
--
-- Location: ServerScriptService/Game/MapRenderer.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local MapRenderer = {}

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

local TILE_SIZE      = 5
local TILE_HEIGHT    = 0.6
local TILE_MATERIAL  = Enum.Material.SmoothPlastic
local ELEVATION_STEP = 2.5

local GRID_COLOR     = Color3.fromRGB(20, 20, 20)

-- HYBRID TERRAIN SYSTEM
-- Natural terrains: 3D voxel terrain (workspace.Terrain:FillBlock).
-- Man-made/magical terrains: visible tile Parts with SurfaceGui textures.
-- This gives organic 3D visuals for nature + crisp flat geometry for structures.

-- Man-made/magical terrains that keep visible tile Parts with SurfaceGui textures.
local SURFACEGUI_TERRAINS = {
	Metal                  = true,
	["Magic Circle"]       = true,
	["Wooden Floor"]       = true,
	["Monolith (One-way)"] = true,
	["Monolith (Two-way)"] = true,
}

-- Voxel material per natural terrain (17 entries, each unique).
local TERRAIN_VOXEL = {
	Clear              = Enum.Material.Ground,       -- brown earth
	Grassland          = Enum.Material.Grass,        -- 3D grass blades
	["Clover Field"]   = Enum.Material.LeafyGrass,   -- flat leafy green (no 3D blades)
	Forest             = Enum.Material.Limestone,    -- pale earthy forest floor
	Rocky              = Enum.Material.Rock,          -- grey rock
	Sand               = Enum.Material.Sand,          -- warm sand
	Mud                = Enum.Material.Mud,            -- wet brown mud
	Swamp              = Enum.Material.Slate,          -- dark wet stone
	["Shallow Water"]  = Enum.Material.Glacier,       -- pale reflective surface
	["Deep Water"]     = Enum.Material.Water,          -- translucent water
	Ice                = Enum.Material.Ice,             -- reflective ice
	Molten             = Enum.Material.CrackedLava,    -- glowing lava
	["Tainted Ground"] = Enum.Material.Basalt,         -- dark corrupted
	["Cracked Ground"] = Enum.Material.Asphalt,        -- dark cracked, no glow
	Quicksand          = Enum.Material.Sandstone,      -- pale stone-sand
	["Stone Road"]     = Enum.Material.Cobblestone,    -- cobble road
	["Dirt Road"]      = Enum.Material.Pavement,       -- packed grey-brown road
}

-- Fill depth for terrain voxels. Must be >= 4 studs (one full voxel cell)
-- to fully saturate voxels and prevent neighbor materials from bleeding in.
local TERRAIN_FILL_DEPTH = 8
local GRID_MATERIAL  = Enum.Material.SmoothPlastic
local GRID_THICKNESS = 0.08

local BLOCKER_COLOR  = Color3.fromRGB(50, 50, 55)

--------------------------------------------------
-- TERRAIN FALLBACK COLORS
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
-- HELPERS
--------------------------------------------------

local function getTerrainColor(terrainId)
	return TERRAIN_COLORS[terrainId]
		or Color3.fromRGB(200, 190, 170)
end

local function getTileHeight(elevation)
	return TILE_HEIGHT
		+ (elevation - 1) * ELEVATION_STEP
end

local function getTilePosition(x, y, elevation, offsetX, offsetZ)
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

local function getDisplayColor(viewMode, terrainId, regionColor, marker)
	if viewMode == "TEMPLATE" then
		return getTemplateColor(marker)
	elseif viewMode == "REGION" then
		return regionColor or Color3.fromRGB(128, 128, 128)
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

--- Build region → debug color lookup from generated map data.
local function buildRegionColorMap(generatedMap)
	local regionColorMap = {}
	local idx  = 0
	local seen = {}

	for y = 1, generatedMap.height do
		for x = 1, generatedMap.width do
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

	return regionColorMap
end

--------------------------------------------------
-- TILE CREATION
--------------------------------------------------

local function createTile(x, y, tileData, viewMode, regionColorMap, generatedMap, offsetX, offsetZ, mapFolder)
	local terrainId  = tileData.terrain
	local elevation  = tileData.elevation
	local regionId   = tileData.regionId
	local marker     = tileData.marker
	local objectName = tileData.object

	local regionColor = regionColorMap[regionId]
		or Color3.fromRGB(128, 128, 128)

	local tileHeight = getTileHeight(elevation)
	local position   = getTilePosition(x, y, elevation, offsetX, offsetZ)

	local tile = Instance.new("Part")

	tile.Name = string.format("Tile_%02d_%02d", x, y)

	tile.Anchored   = true
	tile.Material   = TILE_MATERIAL
	tile.CastShadow = false

	makeSurfacesSmooth(tile)

	tile.Size = Vector3.new(TILE_SIZE, tileHeight, TILE_SIZE)
	tile.Position = position
	tile.Color = getDisplayColor(viewMode, terrainId, regionColor, marker)

	tile.CanCollide = true
	tile.CanTouch   = true
	tile.CanQuery   = true

	-- TILE IDENTITY
	tile:SetAttribute("IsTemplateTile", true)
	tile:SetAttribute("X", x)
	tile:SetAttribute("Y", y)

	-- TEMPLATE LAYER
	tile:SetAttribute("TemplateMarker", marker)
	tile:SetAttribute("TemplateColor", getTemplateColor(marker))

	-- BIOME LAYER
	tile:SetAttribute("BiomeId", generatedMap.biomeId)

	-- REGION LAYER
	tile:SetAttribute("RegionId", regionId or "unknown")
	tile:SetAttribute("RegionDebugColor", regionColor)

	-- TERRAIN DATA
	tile:SetAttribute("Elevation", elevation)
	tile:SetAttribute("Terrain", terrainId)
	tile:SetAttribute("TerrainColor", getTerrainColor(terrainId))

	-- Effect (none at map gen).
	tile:SetAttribute("Effect", "None")

	-- Passability.
	local passable = true
	if terrainId == "Quicksand" then
		passable = false
	end
	tile:SetAttribute("Passable", passable)

	-- OBJECT DATA
	if objectName then
		tile:SetAttribute("ObjectName", objectName)
		tile:SetAttribute("ObjectCategory", "MapObject")
		tile:SetAttribute("ObjectPassabilityImpact", "Occupied")
	else
		tile:SetAttribute("ObjectName", "None")
		tile:SetAttribute("ObjectCategory", "None")
		tile:SetAttribute("ObjectPassabilityImpact", "None")
	end

	-- APPLY TERRAIN VISUALS (TERRAIN view mode)
	if viewMode == "TERRAIN" then
		if SURFACEGUI_TERRAINS[terrainId] then
			-- Man-made/magical: visible tile Part with custom SurfaceGui texture.
			TerrainTextures.Apply(tile, terrainId)
			tile.Color = Color3.fromRGB(20, 20, 20)
		else
			-- Natural: fill 3D voxel terrain, hide tile Part.
			local voxelMat = TERRAIN_VOXEL[terrainId]
			if voxelMat then
				local topY = position.Y + tileHeight / 2
				local fillCenterY = topY - TERRAIN_FILL_DEPTH / 2
				workspace.Terrain:FillBlock(
					CFrame.new(position.X, fillCenterY, position.Z),
					Vector3.new(TILE_SIZE, TERRAIN_FILL_DEPTH, TILE_SIZE),
					voxelMat
				)
			end
			tile.Transparency = 1
		end
	end

	tile.Parent = mapFolder
end

--------------------------------------------------
-- BLOCKER RENDERING
--------------------------------------------------

local function renderBlockers(generatedMap, mapFolder)
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
				child:SetAttribute("ObjectName", blocker.objectType)
				child:SetAttribute("ObjectCategory", "Obstacle")
				child:SetAttribute("ObjectPassabilityImpact", "Impassable")

				-- Create visual blocker cube.
				local blockerHeight = ELEVATION_STEP * 1.5

				local blockerPart = Instance.new("Part")
				blockerPart.Name = string.format("Blocker_%d_%d", bx, by)
				blockerPart.Anchored   = true
				blockerPart.CanCollide = true
				blockerPart.CanQuery   = false
				blockerPart.CastShadow = true
				blockerPart.Material   = Enum.Material.SmoothPlastic
				blockerPart.Color      = BLOCKER_COLOR

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
--------------------------------------------------

local function createGridLine(name, position, size, mapFolder)
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

local function createGridOverlay(mapWidth, mapHeight, _maxElevation, offsetX, offsetZ, mapFolder, generatedMap)
	-- Per-tile grid edges that follow elevation.
	-- Each tile gets a south edge and an east edge at its own top-surface height.
	for y = 1, mapHeight do
		for x = 1, mapWidth do
			local elev = generatedMap.tiles[y] and generatedMap.tiles[y][x] and generatedMap.tiles[y][x].elevation or 1
			-- Raise grid lines 2 studs above tile surface so they sit above
			-- terrain voxels (which have organic shapes extending above Part height).
			local topY = getTileHeight(elev) + 2.0
			-- South edge (along X axis at tile's south Z boundary)
			createGridLine(
				"Grid_S_" .. x .. "_" .. y,
				Vector3.new(
					offsetX + ((x - 0.5) * TILE_SIZE),
					topY,
					offsetZ + (y * TILE_SIZE)
				),
				Vector3.new(TILE_SIZE, 0.04, GRID_THICKNESS),
				mapFolder
			)
			-- East edge (along Z axis at tile's east X boundary)
			createGridLine(
				"Grid_E_" .. x .. "_" .. y,
				Vector3.new(
					offsetX + (x * TILE_SIZE),
					topY,
					offsetZ + ((y - 0.5) * TILE_SIZE)
				),
				Vector3.new(GRID_THICKNESS, 0.04, TILE_SIZE),
				mapFolder
			)
		end
	end
end

--------------------------------------------------
-- PUBLIC API
--------------------------------------------------

--- Render a generated map into a Folder of Parts.
--- The Folder is NOT parented — caller must parent to workspace.
---
--- @param generatedMap table — Output from MapService.Generate()
--- @param viewMode string — "TERRAIN", "REGION", or "TEMPLATE"
--- @return Folder — The map folder (unparented)
function MapRenderer.Render(generatedMap, viewMode)
	viewMode = viewMode or "TERRAIN"

	assert(
		viewMode == "TERRAIN"
			or viewMode == "REGION"
			or viewMode == "TEMPLATE",
		'[MapRenderer] viewMode must be "TERRAIN", "REGION", or "TEMPLATE".'
	)

	local mapWidth  = generatedMap.width
	local mapHeight = generatedMap.height

	local regionColorMap = buildRegionColorMap(generatedMap)

	local mapFolder = Instance.new("Folder")
	mapFolder.Name = "TemplateViewerMap"

	mapFolder:SetAttribute("TemplateId", generatedMap.templateId)
	mapFolder:SetAttribute("BiomeId", generatedMap.biomeId)
	mapFolder:SetAttribute("Seed", generatedMap.seed)
	mapFolder:SetAttribute("InitialViewMode", viewMode)
	mapFolder:SetAttribute("TileMaterial", TILE_MATERIAL.Name)
	mapFolder:SetAttribute("MapWidth", mapWidth)
	mapFolder:SetAttribute("MapHeight", mapHeight)
	mapFolder:SetAttribute("TileSize", TILE_SIZE)

	local mapWidthStuds  = mapWidth * TILE_SIZE
	local mapHeightStuds = mapHeight * TILE_SIZE

	local offsetX = -(mapWidthStuds / 2)
	local offsetZ = -(mapHeightStuds / 2)

	-- Clear any existing terrain voxels from previous map.
	if viewMode == "TERRAIN" then
		workspace.Terrain:Clear()
	end

	-- Create tiles.
	for y = 1, mapHeight do
		for x = 1, mapWidth do
			createTile(
				x, y,
				generatedMap.tiles[y][x],
				viewMode,
				regionColorMap,
				generatedMap,
				offsetX, offsetZ,
				mapFolder
			)
		end
	end

	-- Render blockers.
	renderBlockers(generatedMap, mapFolder)

	-- Grid overlay — sits above highest biome elevation.
	local maxElev = 3
	local elevCfg = generatedMap._biomeElevation
	if elevCfg and elevCfg.max then
		maxElev = elevCfg.max
	else
		-- Scan tiles for actual max.
		for y = 1, mapHeight do
			for x = 1, mapWidth do
				local e = generatedMap.tiles[y][x].elevation
				if e > maxElev then maxElev = e end
			end
		end
	end
	createGridOverlay(mapWidth, mapHeight, maxElev, offsetX, offsetZ, mapFolder, generatedMap)

	print(string.format(
		"[MapRenderer] Rendered %dx%d  biome=%s  template=%s  seed=%d  view=%s",
		mapWidth, mapHeight,
		generatedMap.biomeId, generatedMap.templateId,
		generatedMap.seed, viewMode
	))

	return mapFolder
end

--- Toggle the view mode on an already-rendered map folder.
--- Swaps tile colors and shows/hides terrain textures.
---
--- @param folder Folder — The TemplateViewerMap folder.
--- @param mode string — "TERRAIN", "REGION", or "TEMPLATE".
function MapRenderer.SetViewMode(folder, mode)
	assert(
		mode == "TERRAIN"
			or mode == "REGION"
			or mode == "TEMPLATE",
		'[MapRenderer] mode must be "TERRAIN", "REGION", or "TEMPLATE".'
	)

	-- When switching TO terrain mode, fill voxels; otherwise clear them.
	if mode == "TERRAIN" then
		workspace.Terrain:Clear()
	else
		workspace.Terrain:Clear()
	end

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute("IsTemplateTile") then
			if mode == "TERRAIN" then
				local terrainId = child:GetAttribute("Terrain")
				if terrainId and SURFACEGUI_TERRAINS[terrainId] then
					-- Man-made/magical: show tile + apply texture.
					child.Transparency = 0
					child.Material = TILE_MATERIAL
					child.Color = Color3.fromRGB(20, 20, 20)
					if not child:FindFirstChild("TerrainTexture") then
						TerrainTextures.Apply(child, terrainId)
					end
					-- Show existing SurfaceGuis.
					for _, gui in ipairs(child:GetChildren()) do
						if gui:IsA("SurfaceGui") then gui.Enabled = true end
					end
				else
					-- Natural: fill voxels, hide tile.
					if terrainId then
						local voxelMat = TERRAIN_VOXEL[terrainId]
						if voxelMat then
							local _topY = child.Position.Y + child.Size.Y / 2
							local _fillCY = _topY - TERRAIN_FILL_DEPTH / 2
							workspace.Terrain:FillBlock(
								CFrame.new(child.Position.X, _fillCY, child.Position.Z),
								Vector3.new(child.Size.X, TERRAIN_FILL_DEPTH, child.Size.Z),
								voxelMat
							)
						end
					end
					child.Transparency = 1
					-- Hide any SurfaceGuis from prior mode.
					for _, gui in ipairs(child:GetChildren()) do
						if gui:IsA("SurfaceGui") then gui.Enabled = false end
					end
				end

			elseif mode == "REGION" then
				child.Transparency = 0
				child.Material = TILE_MATERIAL
				child.Color = child:GetAttribute("RegionDebugColor")
					or Color3.fromRGB(128, 128, 128)

			elseif mode == "TEMPLATE" then
				child.Transparency = 0
				child.Material = TILE_MATERIAL
				child.Color = child:GetAttribute("TemplateColor")
					or Color3.fromRGB(255, 0, 255)
			end
		end
	end

	folder:SetAttribute("InitialViewMode", mode)
	print("[MapRenderer] View mode: " .. mode)
end

return MapRenderer
