--!strict
-- TileHighlightManager.lua
-- Client-side tile highlights using tall neon border walls.
--
-- Instead of painting the tile surface (occluded by terrain voxels),
-- each highlighted tile gets 4 thin vertical Neon Parts along its
-- edges — a glowing fence/cage clearly visible above organic terrain.
--
-- API is unchanged from previous version:
--   TileHighlightManager.Init({ tileSize, mapOffsetX, mapOffsetZ, visualFolder })
--   TileHighlightManager.Add(tx, ty, styleName, groupName, overrideColor, overrideTrans)
--   TileHighlightManager.Remove(tx, ty)
--   TileHighlightManager.ClearGroup(groupName)
--   TileHighlightManager.ClearAll()
--   TileHighlightManager.InvalidateCache()

local TileHighlightManager = {}

-- ============================================================
-- CONFIG
-- ============================================================

local WALL_HEIGHT    = 1       -- studs tall per border wall
local WALL_THICKNESS = 0.08    -- studs thin (thinner than grid lines)
local SURFACE_OFFSET = 0.1     -- wall base slightly above terrain surface
local PAD_THICKNESS  = 0.2     -- thin invisible click pad at tile surface
local RAY_START_Y    = 200
local RAY_LENGTH     = 400

-- ============================================================
-- STATE
-- ============================================================

local _tileSize   = 5
local _mapOffsetX = 0
local _mapOffsetZ = 0
local _visualFolder: Instance? = nil
local _padFolder: Folder? = nil

-- heightCache[key] = terrain surface Y at tile center
local heightCache: {[string]: number} = {}

-- wallPool[key] = { n: Part, s: Part, e: Part, w: Part }
local wallPool: {[string]: {[string]: Part}} = {}

-- padPool[key] = invisible queryable click pad covering the tile footprint
local padPool: {[string]: BasePart} = {}

-- activeHighlights[key] = { walls: table, group: string }
local activeHighlights: {[string]: any} = {}

-- groups[groupName] = array of tile keys
local groups: {[string]: {string}} = {}

-- Raycast params (rebuilt on Init)
local _rayParams: RaycastParams? = nil

local function tileKey(tx: number, ty: number): string
	return tx .. "_" .. ty
end

-- ============================================================
-- RAYCAST HELPERS
-- ============================================================

local function ensureRayParams(): RaycastParams
	if _rayParams then return _rayParams end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local excludes: {Instance} = {}
	for _, name in { "TemplateViewerMap", "UnitModels", "BattleVisuals", "DeploymentParts", "GridOverlay" } do
		local f = workspace:FindFirstChild(name)
		if f then table.insert(excludes, f) end
	end
	rp.FilterDescendantsInstances = excludes
	_rayParams = rp
	return rp
end

--- Single center-point raycast to find terrain surface Y for a tile.
local function getSurfaceY(tx: number, ty: number): number
	local key = tileKey(tx, ty)
	if heightCache[key] then return heightCache[key] end

	local wx = _mapOffsetX + (tx - 0.5) * _tileSize
	local wz = _mapOffsetZ + (ty - 0.5) * _tileSize

	local result = workspace:Raycast(
		Vector3.new(wx, RAY_START_Y, wz),
		Vector3.new(0, -RAY_LENGTH, 0),
		ensureRayParams()
	)
	local y = result and result.Position.Y or 0
	heightCache[key] = y
	return y
end

-- ============================================================
-- WALL CREATION & POOLING
-- ============================================================

local function createWallPart(): Part
	local p = Instance.new("Part")
	p.Anchored       = true
	p.CanCollide      = false
	p.CanQuery        = false
	p.CastShadow      = false
	p.Material         = Enum.Material.Neon
	p.TopSurface       = Enum.SurfaceType.Smooth
	p.FrontSurface     = Enum.SurfaceType.Smooth
	p.BackSurface      = Enum.SurfaceType.Smooth
	p.LeftSurface      = Enum.SurfaceType.Smooth
	p.RightSurface     = Enum.SurfaceType.Smooth
	p.BottomSurface    = Enum.SurfaceType.Smooth
	return p
end

--- Get or create the 4 wall Parts for a tile (pooled).
local function getOrCreateWalls(tx: number, ty: number): {[string]: Part}
	local key = tileKey(tx, ty)
	if wallPool[key] then return wallPool[key] end

	local wx   = _mapOffsetX + (tx - 0.5) * _tileSize
	local wz   = _mapOffsetZ + (ty - 0.5) * _tileSize
	local half = _tileSize / 2
	local surfY = getSurfaceY(tx, ty)
	local midY  = surfY + WALL_HEIGHT / 2 + SURFACE_OFFSET

	-- North edge (Z-)
	local n   = createWallPart()
	n.Name    = "HL_N_" .. key
	n.Size    = Vector3.new(_tileSize, WALL_HEIGHT, WALL_THICKNESS)
	n.Position = Vector3.new(wx, midY, wz - half)

	-- South edge (Z+)
	local s   = createWallPart()
	s.Name    = "HL_S_" .. key
	s.Size    = Vector3.new(_tileSize, WALL_HEIGHT, WALL_THICKNESS)
	s.Position = Vector3.new(wx, midY, wz + half)

	-- West edge (X-)
	local w   = createWallPart()
	w.Name    = "HL_W_" .. key
	w.Size    = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, _tileSize)
	w.Position = Vector3.new(wx - half, midY, wz)

	-- East edge (X+)
	local e   = createWallPart()
	e.Name    = "HL_E_" .. key
	e.Size    = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, _tileSize)
	e.Position = Vector3.new(wx + half, midY, wz)

	local walls = { n = n, s = s, e = e, w = w }
	wallPool[key] = walls
	return walls
end

--- Get or create the invisible click-pad for a tile (pooled).
--- Covers the full tile footprint at the tile surface. Thin pads (unlike
--- the tall terrain boxes) do NOT occlude their neighbors, so the tile you
--- click is the tile you see highlighted (removes the parallax offset).
local function getOrCreatePad(tx: number, ty: number): BasePart
	local key = tileKey(tx, ty)
	if padPool[key] then return padPool[key] end

	local wx    = _mapOffsetX + (tx - 0.5) * _tileSize
	local wz    = _mapOffsetZ + (ty - 0.5) * _tileSize
	local surfY = getSurfaceY(tx, ty)

	-- NET-004: set all properties BEFORE parenting (parented later in Add)
	local pad = Instance.new("Part")
	pad.Name         = "TileClickPad_" .. key
	pad.Anchored     = true
	pad.CanCollide   = false
	pad.CanTouch     = false
	pad.CanQuery     = true   -- must be hittable by click raycasts
	pad.CastShadow   = false
	pad.Transparency = 1      -- fully invisible
	pad.Size         = Vector3.new(_tileSize, PAD_THICKNESS, _tileSize)
	pad.Position     = Vector3.new(wx, surfY + SURFACE_OFFSET, wz)
	-- Template coords (same space the tile Parts use): DeploymentUI reads X/Y
	-- directly; BattleVisualClient converts via templateToBattle.
	pad:SetAttribute("X", tx)
	pad:SetAttribute("Y", ty)
	pad:SetAttribute("IsTemplateTile", true)
	pad:SetAttribute("IsTileClickPad", true)

	padPool[key] = pad
	return pad
end

-- ============================================================
-- HIGHLIGHT STYLES
-- ============================================================

TileHighlightManager.Styles = {
	move       = { color = Color3.fromRGB(80, 160, 255),  transparency = 0.65 },
	target     = { color = Color3.fromRGB(255, 80, 80),   transparency = 0.55 },
	selected   = { color = Color3.fromRGB(255, 220, 60),  transparency = 0.50 },
	aoe        = { color = Color3.fromRGB(255, 160, 40),  transparency = 0.60 },
	invalid    = { color = Color3.fromRGB(180, 180, 180), transparency = 0.75 },
	current    = { color = Color3.fromRGB(100, 200, 255), transparency = 0.60 },
	deploy     = { color = Color3.fromRGB(80, 140, 220),  transparency = 0.60 },
	path       = { color = Color3.fromRGB(100, 180, 255), transparency = 0.55 },
	pathDest   = { color = Color3.fromRGB(240, 200, 60),  transparency = 0.45 },
}

--- Override styles (pass Theme colors after Init).
function TileHighlightManager.SetStyles(styles: {[string]: any})
	for k, v in styles do
		TileHighlightManager.Styles[k] = v
	end
end

-- ============================================================
-- INITIALIZATION
-- ============================================================

--- Call once per map load.
function TileHighlightManager.Init(params: {
	mapFolder: Folder?,
	tileSize: number?,
	mapOffsetX: number?,
	mapOffsetZ: number?,
	visualFolder: Instance?,
})
	_tileSize     = params.tileSize or 5
	_mapOffsetX   = params.mapOffsetX or 0
	_mapOffsetZ   = params.mapOffsetZ or 0
	_visualFolder = params.visualFolder

	-- Clear previous map data
	TileHighlightManager.ClearAll()
	heightCache = {}
	_rayParams = nil
	for _, walls in wallPool do
		for _, p in walls do p:Destroy() end
	end
	wallPool = {}
	for _, pad in padPool do pad:Destroy() end
	padPool = {}

	-- (Re)create the click-pad folder (fresh per map load)
	if _padFolder then _padFolder:Destroy() end
	local pf = Instance.new("Folder")
	pf.Name = "TileClickPads"
	pf.Parent = _visualFolder or workspace
	_padFolder = pf

	print("[TileHL] Initialized - neon border walls + click pads, wallH=" .. WALL_HEIGHT)
end

-- ============================================================
-- PUBLIC API
-- ============================================================

--- Add a highlight to a tile (4 neon border walls).
function TileHighlightManager.Add(
	tx: number, ty: number,
	styleName: string?, groupName: string?,
	overrideColor: Color3?, overrideTrans: number?
)
	local key = tileKey(tx, ty)
	groupName = groupName or "default"

	-- Already highlighted — skip
	if activeHighlights[key] then return end

	local style = styleName and TileHighlightManager.Styles[styleName] or nil
	local color = overrideColor or (style and style.color) or Color3.fromRGB(200, 170, 50)
	local trans = overrideTrans or (style and style.transparency) or 0.30

	local walls = getOrCreateWalls(tx, ty)
	local pad = getOrCreatePad(tx, ty)

	local parent = _visualFolder or workspace
	for _, p in walls do
		p.Color        = color
		p.Transparency = trans
		pcall(function() p.Parent = parent end)
	end
	pad.Parent = _padFolder or parent

	activeHighlights[key] = { walls = walls, pad = pad, group = groupName }

	if not groups[groupName] then groups[groupName] = {} end
	table.insert(groups[groupName], key)
end

--- Remove highlight from a single tile.
function TileHighlightManager.Remove(tx: number, ty: number)
	local key = tileKey(tx, ty)
	local entry = activeHighlights[key]
	if not entry then return end
	for _, p in entry.walls do p.Parent = nil end
	if entry.pad then entry.pad.Parent = nil end
	activeHighlights[key] = nil
end

--- Clear all highlights in a group.
function TileHighlightManager.ClearGroup(groupName: string)
	local keys = groups[groupName]
	if not keys then return end
	for _, key in keys do
		local entry = activeHighlights[key]
		if entry then
			for _, p in entry.walls do p.Parent = nil end
			if entry.pad then entry.pad.Parent = nil end
			activeHighlights[key] = nil
		end
	end
	groups[groupName] = nil
end

--- Clear ALL highlights.
function TileHighlightManager.ClearAll()
	for _, entry in activeHighlights do
		for _, p in entry.walls do p.Parent = nil end
		if entry.pad then entry.pad.Parent = nil end
	end
	activeHighlights = {}
	groups = {}
end

--- Invalidate caches (call after map regeneration).
function TileHighlightManager.InvalidateCache()
	TileHighlightManager.ClearAll()
	heightCache = {}
	_rayParams = nil
	for _, walls in wallPool do
		for _, p in walls do p:Destroy() end
	end
	wallPool = {}
	for _, pad in padPool do pad:Destroy() end
	padPool = {}
	if _padFolder then _padFolder:Destroy(); _padFolder = nil end
end

--- Always available (no EditableMesh dependency).
function TileHighlightManager.IsAvailable(): boolean
	return true
end

--- Returns the folder of invisible click-pads for highlighted tiles.
--- Click handlers raycast this FIRST (Include filter); a hit resolves the
--- tile via the pad's X/Y attributes with no parallax offset.
function TileHighlightManager.GetPadFolder(): Folder?
	return _padFolder
end

return TileHighlightManager
