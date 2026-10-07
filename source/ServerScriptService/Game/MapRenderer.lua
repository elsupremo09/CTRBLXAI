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
-- Vertical studs per elevation level. Reduced 2.5→1.2 (dev-locked 2026-09-24)
-- for the expanded 1–20 elevation scale: peak (20) now renders ≈ 23 studs
-- tall instead of ≈ 48, keeping tall maps camera/LoS-friendly and proportionate.
local ELEVATION_STEP = 1.2

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

-- VOXEL KEEP-SET (user decision, Sep 24 2026): only these terrains stay 3D voxel
-- terrain in the default battle render — Grassland (3D grass blades) and both
-- waters (animated). EVERYTHING ELSE renders as a per-tile Part with a SurfaceGui
-- terrain texture (crisp per-tile look, stud-free via SurfaceGui). This inverts the
-- old default (which voxelised all natural terrain).
local VOXEL_KEEP = {
	Grassland        = true,
	["Deep Water"]    = true,
	["Shallow Water"] = true,
}

-- REFLECTIVE TERRAINS (user decision, Sep 25 2026): these render with a native
-- REFLECTIVE Roblox material + Reflectance instead of the flat SurfaceGui texture,
-- so the surface actually catches the skybox and reads shiny. Trade-off: a tile
-- here shows the native material look, NOT its uploaded texture image (a SurfaceGui
-- is flat 2D and cannot reflect). Add more terrains here to make them shiny.
-- Each entry: material + reflectance (0..1) + optional color.
local REFLECTIVE_TERRAINS = {
	-- Metal reverted to the textured path Sep 25 2026 (native reflective metal read
	-- as a mirror, not metal). Add entries here to make a terrain natively reflective.
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
	["Shallow Water"]  = Enum.Material.Water,          -- animated water; rendered as sand bed + thin water cap (see fillTerrainVoxelColumn)
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
-- Map floor Y (user decision, Oct 4 2026): voxel tiles fill DOWN to this common
-- floor instead of a fixed 8-stud slab, so tall/elevated tiles are solid columns
-- to the base with NO floating underside (the "floating earth" look). Elevation-1
-- tiles top out at getTileHeight(1)=TILE_HEIGHT=0.6, so a floor a few studs below
-- 0 gives every column a solid base. Visual-only: fill depth does NOT change tile
-- collision / move cost / occupancy (those come from tile data).
local FLOOR_Y = -4
-- Shallow Water renders as a solid sand bed with a thin animated Water cap on
-- top. The translucent cap lets the bed show through, reading as shallow; Deep
-- Water uses a full Water column. Water hue/waves are GLOBAL Terrain properties
-- (cannot be set per-tile), so shallow vs deep is distinguished by depth only.
local SHALLOW_WATER_CAP = 1.5   -- studs of Water on top of the bed

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

-- Fill a tile's terrain voxel column. Centralizes the FillBlock logic so the
-- initial render and view-mode-switch paths stay identical (no divergence).
local function fillTerrainVoxelColumn(cx: number, topY: number, cz: number, sx: number, sz: number, terrainId: string, dropToY: number?)
	local voxelMat = TERRAIN_VOXEL[terrainId]
	if not voxelMat then return end

	-- Fill DOWN to the common map floor so no tile floats. Clamp to at least
	-- TERRAIN_FILL_DEPTH so the lowest tiles still fully saturate voxels.
	local colDepth = math.max(topY - FLOOR_Y, TERRAIN_FILL_DEPTH)

	if terrainId == "Shallow Water" then
		-- Thin animated Water cap on top...
		workspace.Terrain:FillBlock(
			CFrame.new(cx, topY - SHALLOW_WATER_CAP / 2, cz),
			Vector3.new(sx, SHALLOW_WATER_CAP, sz),
			Enum.Material.Water
		)
		-- ...sand bed for everything below the cap, down to the floor (no float).
		local bedDepth = colDepth - SHALLOW_WATER_CAP
		local bedTopY  = topY - SHALLOW_WATER_CAP
		if bedDepth > 0 then
			workspace.Terrain:FillBlock(
				CFrame.new(cx, bedTopY - bedDepth / 2, cz),
				Vector3.new(sx, bedDepth, sz),
				Enum.Material.Sand
			)
		end
	else
		workspace.Terrain:FillBlock(
			CFrame.new(cx, topY - colDepth / 2, cz),
			Vector3.new(sx, colDepth, sz),
			voxelMat
		)
	end

	-- WATERFALL FACE: if this is a water tile sitting ABOVE an adjacent water tile,
	-- dropToY is that lower neighbour's water SURFACE Y. Extend a solid Water sheet
	-- straight down from this tile's own surface to that lower surface so the two
	-- waters read as one connected flow instead of a floating pool. Visual-only
	-- Terrain voxel write — tile elevation / move cost / occupancy are unchanged.
	-- The drop face is always Water (even for Shallow Water, whose body is a sand
	-- bed) so the fall reads as water, never floating sand.
	if dropToY and dropToY < topY then
		local fallDepth = topY - dropToY
		if fallDepth > 0 then
			workspace.Terrain:FillBlock(
				CFrame.new(cx, topY - fallDepth / 2, cz),
				Vector3.new(sx, fallDepth, sz),
				Enum.Material.Water
			)
		end
	end
end

-- Water terrains (both count as "water" for waterfall connection).
local WATER_TERRAINS = {
	["Deep Water"]    = true,
	["Shallow Water"] = true,
}

-- Shared waterfall helper. For a water tile at (x,y) with elevation selfElev,
-- return the LOWEST adjacent (cardinal) water neighbour's SURFACE Y that is below
-- this tile — or nil if no lower water neighbour. lookupFn(nx, ny) must return
-- (terrain, elevation) or (nil, nil) when off-map. Fed from generatedMap in the
-- initial render and from sibling tile-Part attributes on a view-mode switch, so
-- both paths stay consistent (waterfalls survive a view toggle).
local function lowestWaterNeighborSurfaceY(x: number, y: number, selfElev: number, lookupFn): number?
	local lowestY = nil
	local dirs = { {1,0}, {-1,0}, {0,1}, {0,-1} }
	for _, d in ipairs(dirs) do
		local nTerrain, nElev = lookupFn(x + d[1], y + d[2])
		if nTerrain and WATER_TERRAINS[nTerrain] and nElev and nElev < selfElev then
			local nSurfaceY = getTileHeight(nElev)
			if lowestY == nil or nSurfaceY < lowestY then
				lowestY = nSurfaceY
			end
		end
	end
	return lowestY
end
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

-- Forward declaration: createTile (below) calls spawnObjectModel, which is defined
-- further down. In Lua a `local function` is not visible before its line, so without
-- this forward-declare spawnObjectModel is nil at the call site (crash:
-- "attempt to call a nil value" at the object-model spawn). Declaring the local here
-- and assigning it later (plain `function spawnObjectModel`) closes the gap.
local spawnObjectModel

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
	-- Hybrid default: VOXEL_KEEP terrains (Grassland + both Waters) render as 3D
	-- voxel terrain; EVERY other terrain renders as a per-tile Part with a SurfaceGui
	-- terrain texture (stud-free). Man-made terrains already had textures — they now
	-- fall into the same per-tile path as the rest.
	if viewMode == "TERRAIN" then
		if VOXEL_KEEP[terrainId] then
			-- Voxel keep-set: fill 3D voxel terrain, hide the tile Part.
			if TERRAIN_VOXEL[terrainId] then
				local topY = position.Y + tileHeight / 2
				-- Waterfall: if this water tile sits above an adjacent water tile,
				-- extend a Water sheet down to that lower neighbour's surface. Neighbour
				-- data comes from generatedMap here (initial render path).
				local dropToY = nil
				if WATER_TERRAINS[terrainId] then
					dropToY = lowestWaterNeighborSurfaceY(x, y, elevation, function(nx, ny)
						local row = generatedMap.tiles[ny]
						local nd = row and row[nx]
						if nd then return nd.terrain, nd.elevation end
						return nil, nil
					end)
				end
				fillTerrainVoxelColumn(position.X, topY, position.Z, TILE_SIZE, TILE_SIZE, terrainId, dropToY)
			end
			tile.Transparency = 1
		elseif REFLECTIVE_TERRAINS[terrainId] then
			-- Reflective terrain: native shiny material (catches skybox), NOT a flat
			-- SurfaceGui texture. Shows the material look in exchange for real shine.
			local r = REFLECTIVE_TERRAINS[terrainId]
			tile.Transparency = 0
			tile.Material    = r.material
			tile.Reflectance = r.reflectance
			tile.Color       = r.color or getTerrainColor(terrainId)
		else
			-- Everything else: per-tile Part with a SurfaceGui terrain texture.
			if TerrainTextures and TerrainTextures.Assets and TerrainTextures.Assets[terrainId] then
				TerrainTextures.Apply(tile, terrainId)
				tile.Color = Color3.fromRGB(20, 20, 20)
			else
				-- No texture for this terrain: show the Part with its terrain material/color.
				tile.Material = TERRAIN_VOXEL[terrainId] or TILE_MATERIAL
				tile.Color = getTerrainColor(terrainId)
			end
		end
	end

	tile.Parent = mapFolder

	-- MAP OBJECT MODEL: if this tile carries a map object, spawn its real model
	-- from ServerStorage/Map Objects (passable AND impassable — visual only).
	-- renderBlockers (impassable list) runs after and will NOT double-spawn: it
	-- checks for an existing model on the tile first. Only in TERRAIN view mode.
	if viewMode == "TERRAIN" and objectName and objectName ~= "None" then
		local tileTopY = tile.Position.Y + tileHeight / 2
		spawnObjectModel(objectName, tile, tileTopY, x .. "_" .. y)
	end
end

--------------------------------------------------
-- MAP OBJECT MODELS (ServerStorage > Map Objects)
--------------------------------------------------
-- Resolve a map object's model by name from ServerStorage/Map Objects. User
-- renamed the Studio models to match ObjectData keys (incl. case) on Oct 4 2026;
-- a normalized (case/space-insensitive) fallback is kept as a cheap safety net.
local _mapObjFolder = nil
local function getMapObjectsFolder()
	if _mapObjFolder and _mapObjFolder.Parent then return _mapObjFolder end
	local ss = game:GetService("ServerStorage")
	_mapObjFolder = ss:FindFirstChild("Map Objects")
	return _mapObjFolder
end

local function normalizeName(s)
	return string.lower((string.gsub(tostring(s), "%s+", "")))
end

local function findObjectModel(objectName)
	local folder = getMapObjectsFolder()
	if not folder or not objectName then return nil end
	-- 1) exact name
	local m = folder:FindFirstChild(objectName)
	if m and m:IsA("Model") then return m end
	-- 2) normalized (case/space-insensitive) fallback
	local target = normalizeName(objectName)
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") and normalizeName(child.Name) == target then
			return child
		end
	end
	return nil
end

-- Spawn a map object's model standing on the tile top. Returns the clone, or nil
-- if no model exists (caller then draws the fallback cube). Visual-only — does
-- NOT set passability (the caller owns that from object data).
-- NOTE: plain `function` (not `local function`) so this assigns to the forward-
-- declared `local spawnObjectModel` above, making it visible to createTile.
function spawnObjectModel(objectName, tileChild, tileTopY, uniqueKey)
	local template = findObjectModel(objectName)
	if not template then return nil end
	local clone = template:Clone()
	clone.Name = string.format("MapObjModel_%s_%s", tostring(objectName), tostring(uniqueKey or ""))
	-- Stand the model on the tile top. PivotTo places the model's pivot at the
	-- given CFrame; map-object models are authored with their pivot at the base,
	-- so pivot at the tile-top centre sits them on the surface.
	local cx = tileChild.Position.X
	local cz = tileChild.Position.Z
	local okPivot = pcall(function()
		clone:PivotTo(CFrame.new(cx, tileTopY, cz))
	end)
	if not okPivot then
		-- Model without a usable pivot: skip the model, let caller fall back.
		clone:Destroy()
		return nil
	end
	-- Not every model is authored with its pivot at the base (e.g. Healing Spring sat
	-- half-buried). Ground by actual geometry: lift/lower so the lowest point of the
	-- model's bounding box sits exactly on the tile top.
	if clone:IsA("Model") then
		pcall(function()
			local bbCf, bbSize = clone:GetBoundingBox()
			local dy = tileTopY - (bbCf.Position.Y - bbSize.Y / 2)
			if math.abs(dy) > 0.05 then
				clone:PivotTo(clone:GetPivot() + Vector3.new(0, dy, 0))
			end
		end)
	end
	-- Anchor every part so the model doesn't fall / drift (visual prop).
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false  -- visual only; movement blocking is via tile Passable attr
		end
	end
	if clone:IsA("BasePart") then
		clone.Anchored = true
		clone.CanCollide = false
	end
	clone.Parent = tileChild.Parent  -- same mapFolder as the tile
	return clone
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

				-- Prefer the real ServerStorage model; fall back to a cube if none.
				-- createTile may have ALREADY spawned a model for this tile's object
				-- (passable+impassable pass). Avoid double-spawning: only spawn here
				-- if the mapFolder has no existing model clone for this tile.
				local existing = mapFolder:FindFirstChild(string.format("MapObjModel_%s_%s", tostring(blocker.objectType), bx .. "_" .. by))
				local tileTopY = child.Position.Y + tileHeight / 2
				local modelClone = existing or spawnObjectModel(blocker.objectType, child, tileTopY, bx .. "_" .. by)
				if not modelClone then
					-- Fallback: visual blocker cube.
					local blockerHeight = ELEVATION_STEP * 1.5
					local blockerPart = Instance.new("Part")
					blockerPart.Name = string.format("Blocker_%d_%d", bx, by)
					blockerPart.Anchored   = true
					blockerPart.CanCollide = true
					blockerPart.CanQuery   = false
					blockerPart.CastShadow = true
					blockerPart.Material   = Enum.Material.SmoothPlastic
					blockerPart.Color      = BLOCKER_COLOR
					blockerPart.Size = Vector3.new(TILE_SIZE * 0.7, blockerHeight, TILE_SIZE * 0.7)
					blockerPart.Position = Vector3.new(
						child.Position.X,
						child.Position.Y + tileHeight / 2 + blockerHeight / 2,
						child.Position.Z
					)
					blockerPart.Parent = mapFolder
				end
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
			-- Raise grid lines 3 studs above tile surface so they sit above
			-- terrain voxels (which have organic shapes extending above Part height).
			local topY = getTileHeight(elev) + 3.0
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
	-- Grid lines are now PAINTED on per-tile top-face SurfaceGuis (see
	-- TerrainTextures.Apply GridEdge) so they follow tile elevation and don't float.
	-- Voxel tiles (grass/water) intentionally have no grid. The old floating-Part
	-- overlay is disabled (functions kept for reference / possible dev use).
	-- createGridOverlay(mapWidth, mapHeight, maxElev, offsetX, offsetZ, mapFolder, generatedMap)

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
				if terrainId and VOXEL_KEEP[terrainId] then
					-- Voxel keep-set: fill voxels, hide tile, hide any prior SurfaceGuis.
					if TERRAIN_VOXEL[terrainId] then
						local _topY = child.Position.Y + child.Size.Y / 2
						-- Waterfall (view-switch path): no generatedMap here, so read the
						-- neighbour's Terrain/Elevation from its sibling tile Part's attributes.
						-- Keeps this consistent with the initial-render path so waterfalls
						-- survive a view-mode toggle.
						local _dropToY = nil
						if WATER_TERRAINS[terrainId] then
							local _cx = child:GetAttribute("X")
							local _cy = child:GetAttribute("Y")
							local _cElev = child:GetAttribute("Elevation")
							if _cx and _cy and _cElev then
								_dropToY = lowestWaterNeighborSurfaceY(_cx, _cy, _cElev, function(nx, ny)
									local nTile = folder:FindFirstChild(string.format("Tile_%02d_%02d", nx, ny))
									if nTile then
										return nTile:GetAttribute("Terrain"), nTile:GetAttribute("Elevation")
									end
									return nil, nil
								end)
							end
						end
						fillTerrainVoxelColumn(child.Position.X, _topY, child.Position.Z, child.Size.X, child.Size.Z, terrainId, _dropToY)
					end
					child.Transparency = 1
					for _, gui in ipairs(child:GetChildren()) do
						if gui:IsA("SurfaceGui") then gui.Enabled = false end
					end
				elseif terrainId and REFLECTIVE_TERRAINS[terrainId] then
					-- Reflective terrain: native shiny material, disable any texture GUI.
					local r = REFLECTIVE_TERRAINS[terrainId]
					child.Transparency = 0
					child.Material    = r.material
					child.Reflectance = r.reflectance
					child.Color       = r.color or (child:GetAttribute("TerrainColor")) or Color3.fromRGB(170, 175, 185)
					for _, gui in ipairs(child:GetChildren()) do
						if gui:IsA("SurfaceGui") then gui.Enabled = false end
					end
				else
					-- Everything else: per-tile Part with a SurfaceGui terrain texture.
					child.Transparency = 0
					if terrainId and TerrainTextures and TerrainTextures.Assets and TerrainTextures.Assets[terrainId] then
						child.Material = TILE_MATERIAL
						child.Color = Color3.fromRGB(20, 20, 20)
						if not child:FindFirstChild("TerrainTexture") then
							TerrainTextures.Apply(child, terrainId)
						end
						for _, gui in ipairs(child:GetChildren()) do
							if gui:IsA("SurfaceGui") then gui.Enabled = true end
						end
					else
						-- No texture: show Part with its terrain material/color.
						child.Material = TERRAIN_VOXEL[terrainId] or TILE_MATERIAL
						local tc = child:GetAttribute("TerrainColor")
						if typeof(tc) == "Color3" then child.Color = tc end
					end
				end

			elseif mode == "REGION" then
				-- Debug color must show on the Part face, so DISABLE the per-tile
				-- SurfaceGui terrain texture (it would otherwise cover the color and
				-- only the voxel tiles — which have no SurfaceGui — would change).
				child.Transparency = 0
				child.Reflectance = 0
				child.Material = TILE_MATERIAL
				child.Color = child:GetAttribute("RegionDebugColor")
					or Color3.fromRGB(128, 128, 128)
				for _, gui in ipairs(child:GetChildren()) do
					if gui:IsA("SurfaceGui") then gui.Enabled = false end
				end

			elseif mode == "TEMPLATE" then
				child.Transparency = 0
				child.Reflectance = 0
				child.Material = TILE_MATERIAL
				child.Color = child:GetAttribute("TemplateColor")
					or Color3.fromRGB(255, 0, 255)
				for _, gui in ipairs(child:GetChildren()) do
					if gui:IsA("SurfaceGui") then gui.Enabled = false end
				end
			end
		end
	end

	folder:SetAttribute("InitialViewMode", mode)
	print("[MapRenderer] View mode: " .. mode)
end

--- Terrain-render switch: PER-TILE mode.
--- Clears the voxel terrain (server-only op) and shows the natural tile Parts
--- with per-terrain Material + color, so the tile-Part surface is actually
--- VISIBLE (not buried under voxels). Man-made/SurfaceGui tiles keep their
--- texture. This is the server half of the Per-tile terrain-render switch —
--- the client cannot clear voxels itself (workspace.Terrain is server-only).
--- @param folder Folder — The TemplateViewerMap folder.
function MapRenderer.ClearVoxelsForPerTile(folder)
	if not folder then return end
	workspace.Terrain:Clear()
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute("IsTemplateTile") then
			local terrainId = child:GetAttribute("Terrain")
			if terrainId and SURFACEGUI_TERRAINS[terrainId] then
				-- Man-made/magical tiles keep their SurfaceGui texture.
				child.Transparency = 0
				child.Material = TILE_MATERIAL
				child.Color = Color3.fromRGB(20, 20, 20)
				if not child:FindFirstChild("TerrainTexture") then
					TerrainTextures.Apply(child, terrainId)
				end
				for _, gui in ipairs(child:GetChildren()) do
					if gui:IsA("SurfaceGui") then gui.Enabled = true end
				end
			else
				-- Natural tiles: show the Part surface with its terrain color/material.
				child.Transparency = 0
				-- Reuse the same per-terrain material the voxels use, so the Part surface
				-- reads like the natural terrain (Grass/Rock/Sand/...), not flat plastic.
				child.Material = TERRAIN_VOXEL[terrainId] or TILE_MATERIAL
				local tc = child:GetAttribute("TerrainColor")
				if typeof(tc) == "Color3" then child.Color = tc end
			end
		end
	end
	folder:SetAttribute("TerrainRenderMode", "PerTile")
	print("[MapRenderer] Terrain render: PER-TILE (voxels cleared, tile Parts shown)")
end

--- Terrain-render switch: MESH mode server half.
--- Clears voxel terrain (server-only) AND hides ALL tile Parts, because in Mesh
--- mode the client-built heightmap mesh IS the visible ground surface — the tile
--- Parts must not show (they caused studs/shine/clutter under the mesh). SurfaceGui
--- man-made tiles are also hidden here (their texture would float over the mesh).
function MapRenderer.ClearVoxelsHideTiles(folder)
	if not folder then return end
	workspace.Terrain:Clear()
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute("IsTemplateTile") then
			child.Transparency = 1
			for _, gui in ipairs(child:GetChildren()) do
				if gui:IsA("SurfaceGui") then gui.Enabled = false end
			end
		end
	end
	folder:SetAttribute("TerrainRenderMode", "Mesh")
	print("[MapRenderer] Terrain render: MESH (voxels cleared, tile Parts hidden)")
end

--------------------------------------------------
-- RUNTIME SINGLE-OBJECT RENDER (Slice 5 blockers: Forge object-spawn, Mimic
-- reveal). Draws ONE object into a LIVE mapFolder using the same visuals as
-- renderBlockers (tile attributes + a blocker cube for non-passable objects).
-- Positions relative to the EXISTING tile Part (found by X/Y attributes) so no
-- offset recomputation is needed. The new Part is a server instance in
-- mapFolder, so Roblox replication shows it on all clients automatically.
--
-- instance: { id, type, x, y }  (generator shape)
-- Returns true if rendered, false if the tile Part was not found.
--------------------------------------------------
function MapRenderer.RenderOneObject(mapFolder, instance)
	if not (mapFolder and instance and instance.x and instance.y) then
		return false
	end
	local ObjectData = require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Content"):WaitForChild("ObjectData")
	)
	local def = ObjectData.Objects and ObjectData.Objects[instance.type]
	local nonPassable = def and def.passable == false

	for _, child in ipairs(mapFolder:GetChildren()) do
		if child:GetAttribute("X") == instance.x
			and child:GetAttribute("Y") == instance.y then
			-- Tag the tile with the object (matches createTile's attribute scheme).
			child:SetAttribute("ObjectName", instance.type)
			child:SetAttribute("ObjectCategory", "MapObject")
			if nonPassable then
				child:SetAttribute("Passable", false)
				child:SetAttribute("ObjectPassabilityImpact", "Occupied")
			end
			-- Render the real model for EVERY object (passable or not). Model is
			-- visual-only; passability is set above from object data.
			local tileTopY = child.Position.Y + child.Size.Y / 2
			local modelClone = spawnObjectModel(instance.type, child, tileTopY, instance.x .. "_" .. instance.y)
			if not modelClone and nonPassable then
				-- No model AND it blocks: fall back to the blocker cube so the
				-- impassable tile still reads as occupied. Passable objects with no
				-- model simply show nothing (unchanged from before).
				local blockerHeight = ELEVATION_STEP * 1.5
				local cube = Instance.new("Part")
				cube.Name = string.format("MapObject_%s_%d_%d", tostring(instance.type), instance.x, instance.y)
				cube.Anchored   = true
				cube.CanCollide = true
				cube.CanQuery   = false
				cube.CastShadow = true
				cube.Material   = Enum.Material.SmoothPlastic
				cube.Color      = BLOCKER_COLOR
				cube.Size = Vector3.new(TILE_SIZE * 0.7, blockerHeight, TILE_SIZE * 0.7)
				cube.Position = Vector3.new(
					child.Position.X,
					child.Position.Y + (child.Size.Y / 2) + (blockerHeight / 2),
					child.Position.Z
				)
				cube.Parent = mapFolder
			end
			return true
		end
	end
	return false
end

--------------------------------------------------
-- RUNTIME OBJECT REMOVAL (Mimic reveal). Destroys the object's model / fallback
-- cube for a live instance and clears the tile's object attributes. Passability
-- reverts to the terrain rule createTile uses (Quicksand = impassable).
--------------------------------------------------
function MapRenderer.RemoveOneObject(mapFolder, instance)
	if not (mapFolder and instance and instance.x and instance.y) then
		return false
	end
	local key = instance.x .. "_" .. instance.y
	local names = {
		string.format("MapObjModel_%s_%s", tostring(instance.type), key),
		string.format("MapObject_%s_%d_%d", tostring(instance.type), instance.x, instance.y),
		string.format("Blocker_%d_%d", instance.x, instance.y),
	}
	for _, n in names do
		local inst = mapFolder:FindFirstChild(n)
		if inst then inst:Destroy() end
	end
	for _, child in mapFolder:GetChildren() do
		if child:GetAttribute("X") == instance.x and child:GetAttribute("Y") == instance.y then
			child:SetAttribute("ObjectName", nil)
			child:SetAttribute("ObjectCategory", nil)
			child:SetAttribute("ObjectPassabilityImpact", nil)
			child:SetAttribute("Passable", child:GetAttribute("Terrain") ~= "Quicksand")
			return true
		end
	end
	return false
end

--------------------------------------------------
-- RUNTIME TILE RESHAPE (Slice 5 blocker #3: Stone Pillar fallen span). Mutates
-- a live tile Part's terrain color + height/position to a new terrain+elevation.
-- The tile is a server Part in mapFolder, so the change replicates to clients.
-- Server-side GameConstants.TERRAIN_MAP / ELEVATION_MAP must be updated SEPARATELY
-- by the caller (this only does the visual + the tile's own attributes).
--------------------------------------------------
function MapRenderer.ReshapeTile(mapFolder, x, y, newTerrain, newElevation)
	if not (mapFolder and x and y) then return false end
	for _, child in ipairs(mapFolder:GetChildren()) do
		if child:GetAttribute("X") == x and child:GetAttribute("Y") == y
			and child:GetAttribute("IsTemplateTile") then
			if newElevation then
				local h = getTileHeight(newElevation)
				local pos = child.Position
				child.Size = Vector3.new(TILE_SIZE, h, TILE_SIZE)
				child.Position = Vector3.new(pos.X, h / 2, pos.Z)
				child:SetAttribute("Elevation", newElevation)
			end
			if newTerrain then
				child:SetAttribute("Terrain", newTerrain)
				local tc = getTerrainColor(newTerrain)
				child:SetAttribute("TerrainColor", tc)
				-- Only recolor if currently in TERRAIN view (don't fight REGION/TEMPLATE view).
				child.Color = tc
			end
			return true
		end
	end
	return false
end

return MapRenderer
