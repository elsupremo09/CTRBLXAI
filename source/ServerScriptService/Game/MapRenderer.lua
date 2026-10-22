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

-- Shared tile-geometry constants (single source of truth, 2026-10-20).
local GameConstants = require(
	CTRBLXAI
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

-- Slice 7 visual polish: decorative blocker/tile props (visual only).
-- PropService has its own TILE_SIZE = 5 mirror; keep in sync with TILE_SIZE below.
local PropService = require(script.Parent.PropService)

-- Object definitions (category/activation/tags). Module-level so BOTH spawnObjectModel
-- (interactable-only PointLight gate) and RenderOneObject can read it. (2026-10-16)
local ObjectData = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("ObjectData")
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
-- Now sourced from GameConstants (single source of truth, 2026-10-20) so the
-- renderer, server placement, and client can never drift apart.
local ELEVATION_STEP = GameConstants.ELEVATION_STEP

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
	-- Store the region TYPE NAME too (e.g. "Forest"), not just the id. The runtime push
	-- path (RenderOneObject) has no generatedMap/regionTypeMap, so the resolved type name
	-- must travel ON the tile for OBS-blocker prop selection to work after a push. (2026-10-16)
	local regionTypeName = generatedMap and generatedMap.regionTypeMap and regionId
		and generatedMap.regionTypeMap[regionId] or nil
	tile:SetAttribute("RegionType", regionTypeName or "unknown")
	tile:SetAttribute("RegionDebugColor", regionColor)

	-- TERRAIN DATA
	tile:SetAttribute("Elevation", elevation)
	tile:SetAttribute("Terrain", terrainId)
	tile:SetAttribute("TerrainColor", getTerrainColor(terrainId))

	-- Effect (none at map gen).
	tile:SetAttribute("Effect", "None")

	-- Passability. (2026-10-11: Quicksand is now PASSABLE deadly terrain — units can
	-- walk onto it and start sinking. No base terrain is client-impassable anymore;
	-- chasm/pit gating is enforced server-side by elevation depth, not a Passable flag.)
	tile:SetAttribute("Passable", true)

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
		spawnObjectModel(objectName, tile, tileTopY, x .. "_" .. y, generatedMap and generatedMap.seed)
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

-- AD BILLBOARD MODEL POOL (multi-model, 2026-10-15 USER DECISION; supersedes the
-- single "Old Roblox Billboard" alias). The single-tile "Ad Billboard" object renders
-- from a SEEDED-RANDOM pick among ALL Models in ServerStorage/"Map Objects" (or
-- ServerStorage root) whose NAME STARTS WITH "Billboard" (normalized, case/space-
-- insensitive). The obstacle TYPE KEY stays "Ad Billboard"; only the MODEL lookup
-- changed. Each chosen model may carry 1..N flat ad-surface Parts named AdFace1,
-- AdFace2, ... (see prepareBillboardAdFaces) for a future real Roblox AdGui; ads stay out of
-- scope until the game is ad-eligible (map_gen_rules row 80). The pick is deterministic
-- per map seed and consumes NO map-gen RNG (seedPickIndex is a pure hash of the seed),
-- so map layout/forms are byte-identical to before for the same seed. Empty pool ->
-- nil -> existing neon-panel fallback (no crash). See map_gen_rules rows 79/85/93 and
-- objects_encounters row 84 (2026-10-15 multi-model/multi-face).
local BILLBOARD_MODEL_PREFIX = "billboard"  -- normalized name prefix for the pool

local function findModelInFolder(folder, name)
	if not folder or not name then return nil end
	local m = folder:FindFirstChild(name)
	if m and m:IsA("Model") then return m end
	local target = normalizeName(name)
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") and normalizeName(child.Name) == target then
			return child
		end
	end
	return nil
end

-- Collect every Model whose normalized name starts with "billboard", from the
-- "Map Objects" folder first then ServerStorage root. De-duplicated by instance.
-- Returned in a STABLE order (name-sorted) so the seeded pick is reproducible
-- regardless of Explorer/child ordering.
local function collectBillboardPool()
	local pool = {}
	local seen = {}
	local function scan(folder)
		if not folder then return end
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Model") and not seen[child]
				and string.sub(normalizeName(child.Name), 1, #BILLBOARD_MODEL_PREFIX) == BILLBOARD_MODEL_PREFIX
			then
				seen[child] = true
				table.insert(pool, child)
			end
		end
	end
	scan(getMapObjectsFolder())
	scan(game:GetService("ServerStorage"))
	table.sort(pool, function(a, b)
		if a.Name == b.Name then return tostring(a) < tostring(b) end
		return a.Name < b.Name
	end)
	return pool
end

-- Deterministic index in [1, n] derived purely from the map seed (no RNG stream
-- consumed, so existing map-gen draws are unperturbed). Simple 32-bit integer hash.
local function seedPickIndex(seed, n)
	if n <= 0 then return nil end
	local s = tonumber(seed) or 0
	local h = (math.floor(s) % 2147483647 + 2147483647) % 2147483647
	-- a couple of integer mixes so near-seeds don't map to the same model
	h = (h * 1103515245 + 12345) % 2147483648
	h = (h + math.floor(h / 65536)) % 2147483648
	return (h % n) + 1
end

local function findObjectModel(objectName, seed)
	if not objectName then return nil end
	local folder = getMapObjectsFolder()
	-- AD BILLBOARD: seeded-random pick from the "Billboard"-prefix model pool.
	if objectName == "Ad Billboard" then
		local pool = collectBillboardPool()
		if #pool == 0 then return nil end  -- -> neon-panel fallback
		local idx = seedPickIndex(seed, #pool) or 1
		return pool[idx]
	end
	-- Non-billboard objects: exact / normalized by the object's own name, in Map
	-- Objects (unchanged behavior for every other object type).
	return findModelInFolder(folder, objectName)
end
-- AD BILLBOARD AD-FACE PREP (multi-face, 2026-10-15 USER DECISION). Finds every
-- descendant Part named "AdFace" + an integer (AdFace1, AdFace2, ...) in a billboard
-- model clone and marks it as a static ad surface. Our code attaches NO ClickDetector
-- and NO GUI button (NEVER clickable, per map_gen_rules row 79 / objects_encounters
-- row 84); it also strips any ClickDetector a model author may have left on the model
-- or its ad faces, so the billboard can never steal a tap from tile targeting. The
-- placeholder decal is authored on each AdFace part by the model builder (display-only).
-- A model with NO AdFace# part still renders fine as an obstacle (no ad surface). The
-- future real Roblox immersive-ad AdGui attaches to these tagged faces when the game
-- is ad-eligible (map_gen_rules row 80) -- not created here.
local function prepareBillboardAdFaces(clone)
	if not clone then return 0 end
	-- Never clickable: remove any ClickDetector anywhere in the model.
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("ClickDetector") then
			d:Destroy()
		end
	end
	-- Tag each AdFace#. CollectionService tag + attribute so the live-ad hook can find
	-- them in one query later without re-scanning names (OPT-002: avoid repeat walks).
	local CollectionService = game:GetService("CollectionService")
	local count = 0
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") and string.match(d.Name, "^AdFace%d+$") then
			d:SetAttribute("IsAdFace", true)
			CollectionService:AddTag(d, "AdFace")
			count += 1
		end
	end
	clone:SetAttribute("AdFaceCount", count)
	return count
end

-- Spawn a map object's model standing on the tile top. Returns the clone, or nil
-- if no model exists (caller then draws the fallback cube). Visual-only — does
-- NOT set passability (the caller owns that from object data).
-- NOTE: plain `function` (not `local function`) so this assigns to the forward-
-- declared `local spawnObjectModel` above, making it visible to createTile.
function spawnObjectModel(objectName, tileChild, tileTopY, uniqueKey, seed)
	-- `seed` (optional) selects the Ad Billboard model deterministically from the
	-- "Billboard"-prefix pool; nil for non-billboard objects (ignored by findObjectModel).
	-- OBS BLOCKER (BUG-047, 2026-10-16): there is no model named "OBS Blocker". Its visual
	-- is a REGION-APPROPRIATE blocker prop (objects_encounters row 83 + regions object-weight
	-- data), picked from the SAME PropData.Blockers set via PropService.PickBlockerModel. The
	-- region TYPE NAME + biome travel on the tile (RegionType/BiomeId attrs) so this resolves
	-- identically on the map-build path AND the runtime push path. Seeded by seed + tile key
	-- so the model is stable per map and follows the object when pushed. nil -> caller draws
	-- its existing fallback cube (region genuinely has no available blocker prop).
	local template
	if objectName == "OBS Blocker" then
		local regionType = tileChild and tileChild:GetAttribute("RegionType")
		local biomeId = tileChild and tileChild:GetAttribute("BiomeId")
		template = PropService.PickBlockerModel(regionType, biomeId, seed, uniqueKey)
	else
		template = findObjectModel(objectName, seed)
	end
	if not template then return nil end
	local clone = template:Clone()
	clone.Name = string.format("MapObjModel_%s_%s", tostring(objectName), tostring(uniqueKey or ""))
	-- Tile identity so a click on the object resolves to the tile it stands on.
	clone:SetAttribute("ObjTileX", tileChild:GetAttribute("X"))
	clone:SetAttribute("ObjTileY", tileChild:GetAttribute("Y"))
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
	-- AD BILLBOARD multi-face prep (2026-10-15): if this is a billboard model, mark
	-- every AdFace1..AdFaceN part as an ad surface and GUARANTEE it is never clickable
	-- (strip any ClickDetector a model author may have left; attach none ourselves).
	-- The real Roblox AdGui hook (future, ads not eligible yet) attaches to these same
	-- faces. All property writes happen BEFORE Parent (NET-004) above/here.
	if objectName == "Ad Billboard" then
		prepareBillboardAdFaces(clone)
	end
	-- MAP-OBJECT POINTLIGHT (user request 2026-10-16): one lightweight PointLight per
	-- object so props read clearly, especially at night. Attached to a dedicated tiny
	-- invisible anchor part at the model top-centre (models have no PrimaryPart), so the
	-- light sits INSIDE the object, travels with it when pushed (RenderOneObject uses this
	-- same spawn path), and is destroyed with it. Mobile-first: conservative Brightness/
	-- Range + Shadows off keep per-object cost low (one light per OBJECT, not per part).
	-- Values are eyeball-tunable; adjust on user feedback like the night-lighting pass.
	-- Properties set BEFORE Parent (NET-004). Tagged OBJECT_POINTLIGHT for later tuning.
	-- GLOW GATE (user ruling 2026-10-16, category rule): the light marks beneficial/useful
	-- POINTS OF INTEREST. Every object glows EXCEPT category "Hazard" and category "Obstacle".
	-- This lights interactables + passive-aura objects (War Banner, Cursed Statue, Necro Tome
	-- Stand) and leaves DARK: all traps + Bomb Barrel + Ice Spike + Oil Sluice + Steam Valve
	-- (category "Hazard") and OBS Blocker + Ad Billboard (category "Obstacle"). Darkness itself
	-- is meant to hide hazards. Data-driven by ObjectData.category so it never drifts from a
	-- hardcoded name list; a new object glows unless its category is Hazard/Obstacle.
	local _objDef = ObjectData.Objects and ObjectData.Objects[objectName]
	local _objCategory = _objDef and _objDef.category
	local _shouldGlow = _objDef ~= nil
		and _objCategory ~= "Hazard"
		and _objCategory ~= "Obstacle"
	if _shouldGlow then
		local lightAnchor = Instance.new("Part")
		lightAnchor.Name = "OBJECT_POINTLIGHT_ANCHOR"
		lightAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
		lightAnchor.Transparency = 1
		lightAnchor.Anchored = true
		lightAnchor.CanCollide = false
		lightAnchor.CanQuery = false
		lightAnchor.CanTouch = false
		lightAnchor.CastShadow = false
		-- Position at the model/part centre, lifted slightly so the light sits within the prop.
		local anchorPos
		if clone:IsA("Model") then
			local okbb, bbCf, bbSize = pcall(function() return clone:GetBoundingBox() end)
			if okbb and bbCf then
				anchorPos = bbCf.Position + Vector3.new(0, (bbSize and bbSize.Y or 2) * 0.25, 0)
			else
				anchorPos = Vector3.new(cx, tileTopY + 1.5, cz)
			end
		else
			anchorPos = (clone :: any).Position
		end
		lightAnchor.Position = anchorPos
		local light = Instance.new("PointLight")
		light.Name = "OBJECT_POINTLIGHT"
		light.Brightness = 1.4      -- modest; readable at night without washing out day
		light.Range = 8             -- small radius so many objects do not flood the scene
		light.Color = Color3.fromRGB(255, 244, 214)  -- warm-neutral
		light.Shadows = false       -- shadows are the expensive part; off for mobile budget
		light.Parent = lightAnchor
		lightAnchor.Parent = clone
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
				local modelClone = existing or spawnObjectModel(blocker.objectType, child, tileTopY, bx .. "_" .. by, generatedMap and generatedMap.seed)
				if not modelClone then
					local blockerHeight = ELEVATION_STEP * 1.5
					local blockerPart = Instance.new("Part")
					blockerPart.Name = string.format("Blocker_%d_%d", bx, by)
					blockerPart.Anchored   = true
					blockerPart.CanCollide = true
					blockerPart.CanQuery   = false
					blockerPart.CastShadow = true
					blockerPart.Material   = Enum.Material.SmoothPlastic
					blockerPart.Color      = BLOCKER_COLOR
					if blocker.objectType == "Ad Billboard" then
						-- AD BILLBOARD (map_gen_rules row 79): a tall, flat panel standing on
						-- the strip, sized to clear Roblox's immersive-ad minimum (>= 8 x 4.5
						-- studs). PHASE 1 = static panel only; real ad units are out of scope
						-- until the game is ad-eligible (row 80). AdGui attach hook below.
						local panelH = math.max(ELEVATION_STEP * 3, 5)
						blockerPart.Name  = string.format("AdBillboard_%d_%d", bx, by)
						blockerPart.Color = Color3.fromRGB(28, 28, 38)
						blockerPart.Material = Enum.Material.Neon
						blockerPart.Size  = Vector3.new(TILE_SIZE * 0.95, panelH, TILE_SIZE * 0.18)
						blockerPart.Position = Vector3.new(
							child.Position.X,
							child.Position.Y + tileHeight / 2 + panelH / 2,
							child.Position.Z
						)
						-- PHASE 2 / ELIGIBILITY HOOK (do NOT create now — ads not eligible yet,
						-- map_gen_rules row 80). When live, attach a Roblox immersive-ad panel:
						--   local adGui = Instance.new("AdGui")
						--   adGui.Face = Enum.NormalId.Front
						--   adGui.EnableVideoAds = true   -- image + autoplaying (muted) video
						--   adGui.Parent = blockerPart
					else
						-- Fallback: visual blocker cube (OBS Blocker or any model-less object).
						blockerPart.Size = Vector3.new(TILE_SIZE * 0.7, blockerHeight, TILE_SIZE * 0.7)
						blockerPart.Position = Vector3.new(
							child.Position.X,
							child.Position.Y + tileHeight / 2 + blockerHeight / 2,
							child.Position.Z
						)
					end
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

	-- Decorative props (OBS blocker dressing + ground clutter). Visual only;
	-- TERRAIN view only so debug colors stay readable.
	if viewMode == "TERRAIN" then
		PropService.Populate(generatedMap, mapFolder)
	end

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

	PropService.SetVisible(folder, mode == "TERRAIN")

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
	-- ObjectData is required at module scope (top of file); no local re-require needed. (2026-10-16)
	local def = ObjectData.Objects and ObjectData.Objects[instance.type]
	local nonPassable = def and def.passable == false

	for _, child in ipairs(mapFolder:GetChildren()) do
		if child:GetAttribute("X") == instance.x
			and child:GetAttribute("Y") == instance.y then
			-- A runtime object now owns this tile: drop any decorative prop on it.
			PropService.ClearTile(mapFolder, instance.x, instance.y)
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
			local modelClone = spawnObjectModel(instance.type, child, tileTopY, instance.x .. "_" .. instance.y, mapFolder:GetAttribute("Seed"))
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
-- reverts to the terrain rule createTile uses (all base terrain now passable).
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
			child:SetAttribute("Passable", true)
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
			-- Height/terrain is changing: remove props so none float or sink.
			PropService.ClearTile(mapFolder, x, y)
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

--------------------------------------------------
-- SINGLE-TILE VOXEL CLEAR (BUG-002 GAP 2 fix, 2026-10-22).
-- VOXEL_KEEP terrains (Grassland + both Waters) render as a server Roblox-Terrain
-- voxel column (fillTerrainVoxelColumn, FillBlock). When one of those transforms
-- mid-battle to a NON-voxel terrain, ReshapeTile re-skins the tile Part but the
-- stale voxel column remains visible on top (the client cannot clear voxels —
-- workspace.Terrain is server-only). This clears ONLY that one tile's voxel column
-- by filling Air over the SAME region the build filled, computed from the tile
-- Part's own position/size (TILE_SIZE wide, column top = Part top, down to FLOOR_Y).
-- CRITICAL (regression guard): this is a LOCALIZED FillBlock, NOT workspace.Terrain:Clear()
-- (which would wipe the whole map). Neighbour tiles are untouched. Visual-only — tile
-- elevation / move cost / occupancy are unchanged. Returns true if a column was cleared.
function MapRenderer.ClearTileVoxelColumn(mapFolder, x, y)
	if not (mapFolder and x and y) then return false end
	for _, child in ipairs(mapFolder:GetChildren()) do
		if child:GetAttribute("X") == x and child:GetAttribute("Y") == y
			and child:GetAttribute("IsTemplateTile") then
			-- Column geometry mirrors fillTerrainVoxelColumn: centre X/Z = Part centre,
			-- top Y = Part top (Position.Y + Size.Y/2), size X/Z = TILE_SIZE, depth down
			-- to FLOOR_Y clamped to >= TERRAIN_FILL_DEPTH so the lowest tiles fully clear.
			local cx = child.Position.X
			local cz = child.Position.Z
			local topY = child.Position.Y + child.Size.Y / 2
			-- Add a small top margin so the thin Shallow-Water cap (and any sub-voxel
			-- rounding at the surface) is fully removed, and clear down to the floor.
			local TOP_MARGIN = 2
			local clearTop = topY + TOP_MARGIN
			local colDepth = math.max(clearTop - FLOOR_Y, TERRAIN_FILL_DEPTH)
			workspace.Terrain:FillBlock(
				CFrame.new(cx, clearTop - colDepth / 2, cz),
				Vector3.new(TILE_SIZE, colDepth, TILE_SIZE),
				Enum.Material.Air
			)
			return true
		end
	end
	return false
end

--------------------------------------------------
-- AD BILLBOARD RUNTIME IMAGE CYCLE (2026-10-15 USER DECISION; map_gen_rules 79/85,
-- objects_encounters 84). This is the "live-ad hook" reserved by prepareBillboardAdFaces.
--
-- WHAT: at battle start, read the Decal objects in ServerStorage > "Billboard Ad Images"
-- and paint their image onto every AdFace1..N part on the map (all faces show the SAME
-- image at once, per spec), then cycle to the next image every 20 seconds. The starting
-- image is chosen deterministically from the MAP SEED via a DEDICATED derived seed stream
-- (mapSeed + AD_IMAGE_SEED_OFFSET) so it does NOT consume or perturb map-gen / obsFormRng
-- RNG (project rule: same seed + content version = same result stays byte-identical).
--
-- WHY SERVER: the image pool lives in ServerStorage, which the client cannot read
-- (MEM-003); the chosen image is authoritative shared state (ARC-001); and a swap every
-- 20 s is a low-frequency property write, NOT the per-frame tween/particle/animation work
-- NET-001 forbids on the server. Each AdFace Decal is a server instance inside mapFolder,
-- so writing its image replicates to every client automatically (one write / face / 20 s).
--
-- RUNTIME IMAGE PROPERTY (CRITICAL, 2026-10-15 user runtime finding): on the user's current
-- Studio/Roblox version the legacy Decal `Texture` property does NOTHING — the face stays
-- blank. The working image property is the newer SurfaceAppearance-style `ColorMapContent`
-- (Content value). So setAdFaceImage() writes `ColorMapContent` FIRST (as a Content built
-- from the asset id), and FALLS BACK to the legacy `Texture` string only if ColorMapContent
-- is absent / not assignable on that Decal (older runtimes). BOTH writes are pcall-guarded
-- so a property that does not exist on a given runtime raises no error. We never set ONLY
-- the legacy Texture.
--
-- NEVER CLICKABLE: we attach no ClickDetector / GUI button here; prepareBillboardAdFaces
-- already strips any author-left ClickDetector. EMPTY / MISSING folder: faces are left on
-- their authored placeholder decal (blank/neon), no crash, no cycle thread started.
--------------------------------------------------

-- Dedicated derived-seed offset for the ad-image stream (own stream, so map layout/forms
-- for a given seed are unchanged). Follows the project's "+NNNNN derived seed" convention.
local AD_IMAGE_SEED_OFFSET = 51000
local AD_IMAGE_CYCLE_SECONDS = 20
local AD_IMAGE_FOLDER_NAME = "Billboard Ad Images"

-- Only one cycle runs at a time. A new battle / Regenerate reassigns the map folder, so we
-- explicitly cancel the previous cycle before starting a new one (PRF-004: no leaked thread).
local _activeAdCycleThread: thread? = nil

-- Collect the ordered list of ad image asset ids from ServerStorage > "Billboard Ad Images".
-- Each child Decal contributes its image: prefer the Decal's own ColorMapContent/Texture if
-- the author set one, else fall back to nothing for that entry. Returns a STABLE, name-sorted
-- list of { assetId = string?, content = Content? } so the seeded pick is reproducible. Empty
-- list => caller leaves faces blank (no crash).
local function collectAdImages()
	local ServerStorage = game:GetService("ServerStorage")
	local folder = ServerStorage:FindFirstChild(AD_IMAGE_FOLDER_NAME)
	if not folder then
		return {}  -- missing folder -> blank faces, no crash (spec)
	end
	local decals = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Decal") then
			table.insert(decals, child)
		end
	end
	table.sort(decals, function(a, b)
		if a.Name == b.Name then return tostring(a) < tostring(b) end
		return a.Name < b.Name
	end)
	local images = {}
	for _, decal in ipairs(decals) do
		local assetId: string? = nil
		-- Read whichever image property the author populated on the source Decal.
		pcall(function()
			local c = (decal :: any).ColorMapContent
			if typeof(c) == "Content" then
				-- Content built fromUri exposes .Uri; fromAssetId may instead expose a
				-- numeric asset id. Read whichever is populated.
				if c.Uri and c.Uri ~= "" then
					assetId = c.Uri
				elseif (c :: any).AssetId then
					assetId = "rbxassetid://" .. tostring((c :: any).AssetId)
				end
			end
		end)
		if not assetId then
			pcall(function()
				local t = (decal :: any).Texture
				if type(t) == "string" and t ~= "" then
					assetId = t
				end
			end)
		end
		if assetId then
			table.insert(images, assetId)
		end
	end
	return images
end

-- Write one image asset id onto a single AdFace Decal. ColorMapContent FIRST (current API,
-- the only property that renders on the user's version), legacy Texture fallback, both
-- pcall-guarded so a missing property never errors. Returns true if either write succeeded.
local function setAdFaceImage(decal: Decal, assetId: string): boolean
	if not decal or not assetId or assetId == "" then return false end
	-- ColorMapContent is the newer SurfaceAppearance-style property and is the ONLY one
	-- that renders on the user's current Studio version. It requires a Content OBJECT
	-- (not a raw string): Content.fromUri(uri) for a "rbxassetid://..."/URL string, or
	-- Content.fromAssetId(number) for a bare numeric id. We build a Content first and only
	-- treat ColorMapContent as succeeding if a Content was actually built AND assigned.
	local content = nil
	pcall(function()
		-- Our collected ids are strings; prefer fromUri. If the string is a bare number,
		-- also try fromAssetId. Guard each in case a given runtime lacks that constructor.
		local okUri = pcall(function()
			content = Content.fromUri(assetId)
		end)
		if (not okUri or content == nil) then
			local numId = tonumber(assetId)
			if numId then
				pcall(function()
					content = Content.fromAssetId(numId)
				end)
			end
		end
	end)
	if content ~= nil then
		local anyDecal = decal :: any
		local okAssign = pcall(function()
			anyDecal.ColorMapContent = content
		end)
		if okAssign then
			return true
		end
	end
	-- Fallback: legacy Texture (older Studio versions where ColorMapContent is absent or
	-- the Content API/property is not assignable on this runtime). Raw string is correct here.
	local anyDecalTex = decal :: any
	local okTexture = pcall(function()
		anyDecalTex.Texture = assetId
	end)
	return okTexture
end

-- Paint `assetId` onto every AdFace Decal under the given map folder. All faces share the
-- SAME image (spec: cycle ALL faces together). Faces are found via the "AdFace" tag set by
-- prepareBillboardAdFaces; for each tagged BasePart we drive its child Decal(s).
--
-- Broad-face auto-create (BUG-046): when an AdFace part has NO authored Decal, we create our
-- own display-only Decal so the folder images have somewhere to live. A Decal only shows on
-- the single Face it is assigned to, so a Front-only default renders BLANK whenever the sign's
-- visible broad side is not the part's Front face. Instead we create a Decal on BOTH broad
-- faces of the part -- the opposite face-pair whose normal runs along the part's THINNEST Size
-- axis (a thin panel's two big flat faces). This makes the image readable from front and back
-- regardless of how the model author oriented the part. Auto-created decals are named
-- "AdFaceDecal" and REUSED across the 20s cycle (never stacked).
local function broadFaceNormals(face: BasePart): { Enum.NormalId }
	-- The broad faces are perpendicular to the thinnest dimension (their normal IS the thin axis).
	local s = face.Size
	-- thin X -> Right/Left ; thin Y -> Top/Bottom ; thin Z -> Front/Back
	if s.X <= s.Y and s.X <= s.Z then
		return { Enum.NormalId.Right, Enum.NormalId.Left }
	elseif s.Y <= s.X and s.Y <= s.Z then
		return { Enum.NormalId.Top, Enum.NormalId.Bottom }
	else
		return { Enum.NormalId.Front, Enum.NormalId.Back }
	end
end

local function paintAllAdFaces(mapFolder: Instance, assetId: string)
	local CollectionService = game:GetService("CollectionService")
	for _, face in ipairs(CollectionService:GetTagged("AdFace")) do
		-- Only touch faces that belong to THIS map folder (ignore stale tags from a prior map).
		if face:IsA("BasePart") and face:IsDescendantOf(mapFolder) then
			local painted = false
			for _, d in ipairs(face:GetChildren()) do
				-- A Texture is a SUBCLASS of Decal and TILES across the surface (repeats
				-- per StudsPerTile) instead of stretching to fill, so a model that ships a
				-- Texture on its AdFace panel rendered the ad as a repeating grid. It is NOT
				-- a valid fill surface: destroy it (MEM-002) and do NOT mark painted, so the
				-- broad-face create branch below makes a proper stretch-fill Decal instead.
				if d:IsA("Texture") then
					d:Destroy()
				elseif d:IsA("Decal") then
					-- A TRUE Decal (not a Texture) stretches to fill; repaint it.
					if setAdFaceImage(d, assetId) then painted = true end
				end
			end
			-- No authored placeholder Decal on this face: create display-only Decals on BOTH
			-- broad faces (BUG-046) so the sign shows regardless of part orientation. The repaint
			-- loop above already handled any decals that exist (incl. our own on later cycles), so
			-- `painted` is only false the FIRST time -- the broad-face create runs once; thereafter
			-- the two "AdFaceDecal" children are found and repainted above (no pile-up). Properties
			-- set BEFORE Parent (NET-004). Never clickable (a Decal cannot receive clicks; we add no
			-- detector).
			if not painted then
				for _, normalId in ipairs(broadFaceNormals(face)) do
					local decal = Instance.new("Decal")
					decal.Name = "AdFaceDecal"
					decal.Face = normalId
					setAdFaceImage(decal, assetId)
					decal.Parent = face
				end
			end
		end
	end
end

--- Start the ad-image cycle for a freshly rendered map folder.
--- @param mapFolder Folder returned by MapRenderer.Render (already parented to workspace).
--- @param mapSeed   number the generated map's seed (generatedMap.seed); drives the seeded
---                   starting image via a DEDICATED derived stream (no map-gen perturbation).
--- Safe to call every battle start / Regenerate: it cancels any prior cycle first. If the
--- image folder is empty/missing, faces are left blank and NO thread is started. The cycle
--- self-terminates when mapFolder leaves the DataModel (next map Destroy / Regenerate).
function MapRenderer.StartAdImageCycle(mapFolder: Instance?, mapSeed: number?)
	-- Cancel any previous cycle (prevents two loops fighting over the faces).
	if _activeAdCycleThread then
		pcall(task.cancel, _activeAdCycleThread)
		_activeAdCycleThread = nil
	end
	if not mapFolder then return end

	local images = collectAdImages()
	if #images == 0 then
		-- Empty / missing "Billboard Ad Images" folder: blank faces, no crash, no cycle.
		print("[MapRenderer] Ad image cycle: no images in ServerStorage > '"
			.. AD_IMAGE_FOLDER_NAME .. "' — faces left blank.")
		return
	end

	-- Seeded starting index from a DEDICATED derived stream (does not touch map-gen RNG).
	local seed = (tonumber(mapSeed) or os.time()) + AD_IMAGE_SEED_OFFSET
	local startIndex = Random.new(seed):NextInteger(1, #images)

	-- Paint the starting image immediately so faces are correct the instant the map appears.
	paintAllAdFaces(mapFolder, images[startIndex])

	if #images < 2 then
		-- A single image never needs cycling; it is already painted. No thread needed.
		print(string.format("[MapRenderer] Ad image cycle: 1 image, start painted (seed %d).", seed))
		return
	end

	local index = startIndex
	_activeAdCycleThread = task.spawn(function()
		while true do
			task.wait(AD_IMAGE_CYCLE_SECONDS)
			-- Self-terminate when the map folder is gone (battle ended / Regenerate / next quest).
			if not mapFolder or not mapFolder:IsDescendantOf(game) then
				break
			end
			index = (index % #images) + 1
			paintAllAdFaces(mapFolder, images[index])
		end
		_activeAdCycleThread = nil
	end)
	print(string.format(
		"[MapRenderer] Ad image cycle: %d image(s), start #%d, every %ds (seed %d).",
		#images, startIndex, AD_IMAGE_CYCLE_SECONDS, seed))
end

--- Explicitly stop the ad-image cycle (optional; the loop also self-terminates when the
--- map folder is destroyed). Safe to call when no cycle is running.
function MapRenderer.StopAdImageCycle()
	if _activeAdCycleThread then
		pcall(task.cancel, _activeAdCycleThread)
		_activeAdCycleThread = nil
	end
end

return MapRenderer
