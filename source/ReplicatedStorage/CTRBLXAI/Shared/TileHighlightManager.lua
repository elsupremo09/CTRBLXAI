--!strict
-- TileHighlightManager.lua
-- Client-side tile highlights using 4 thin Neon bars forming a glowing square
-- outline (Neon is emissive and feeds Bloom, so the outline glows).
--
-- Each highlighted tile gets ONE thin invisible carrier Part; four Neon bars
-- (its children) form the square edges, plus a faint Neon fill plane for a
-- subtle interior tint. The carrier translates upward on a looping tween for
-- the "rising energy frame" effect; the bars/fill rise in lockstep.
--
-- A separate invisible click-pad (unchanged) handles tile targeting so the
-- visual style can change freely without touching click resolution.
--
-- Public API (unchanged):
--   TileHighlightManager.Init({ tileSize, mapOffsetX, mapOffsetZ, visualFolder })
--   TileHighlightManager.Add(tx, ty, styleName, groupName, overrideColor, overrideTrans)
--   TileHighlightManager.Remove(tx, ty)
--   TileHighlightManager.ClearGroup(groupName)
--   TileHighlightManager.ClearAll()
--   TileHighlightManager.InvalidateCache()
--   TileHighlightManager.GetPadFolder()

local TweenService = game:GetService("TweenService")

local TileHighlightManager = {}

-- ============================================================
-- CONFIG
-- ============================================================

local FRAME_THICKNESS = 0.2     -- studs - thin invisible plane carrying the SurfaceGui
local SURFACE_OFFSET  = 0.15    -- studs above terrain surface (base height of the frame)
local RISE_HEIGHT     = 2.0     -- studs the frame travels upward each loop
local GLOW_OUTLINE_TRANSPARENCY = 0.2   -- Neon edge-bar (rising outline) transparency; lower = stronger glow
local GLOW_FILL_TRANSPARENCY    = 0.88  -- subtle Neon interior tint; high = faint (not a bright square)
local GLOW_BAR_W                = 0.35  -- studs; thickness of each Neon outline bar
local PAD_THICKNESS   = 0.2     -- thin invisible click pad at tile surface
local RAY_START_Y     = 200
local RAY_LENGTH      = 400

-- Looping rising animation (PRF-001 / native_tools: TweenService, engine-level,
-- NOT per-frame Heartbeat polling). 2.4s rise + 0.6s pause, repeats forever.
-- reverses=true so the frame rises (2.4s), eases back DOWN (2.4s), then PAUSES
-- 0.6s at the BOTTOM before rising again (the inter-repeat delay lands at the
-- start/bottom, not the peak). Gentle breathing pulse. -1 = loop forever.
local RISE_INFO = TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, -1, true, 0.6)

-- ============================================================
-- STATE
-- ============================================================

local _tileSize   = 5
local _mapOffsetX = 0
local _mapOffsetZ = 0
local _visualFolder: Instance? = nil
local _hlFolder: Folder? = nil
local _padFolder: Folder? = nil

-- heightCache[key] = terrain surface Y at tile center
local heightCache: {[string]: number} = {}

-- framePool[key] = { part: Part, bars: {Part}, fill: Part, baseY: number, wx: number, wz: number }
local framePool: {[string]: any} = {}

-- padPool[key] = invisible queryable click pad covering the tile footprint
local padPool: {[string]: BasePart} = {}

-- activeHighlights[key] = { frame, pad, tweens, group }
local activeHighlights: {[string]: any} = {}

-- groups[groupName] = array of tile keys
local groups: {[string]: {string}} = {}

-- Raycast params (rebuilt on Init)
local _rayParams: RaycastParams? = nil

-- (Neon glow planes bloom regardless of color — no luminance boosting needed.)

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
	-- Surface raycast must HIT the real ground: per-tile tile Parts (which live in
	-- TemplateViewerMap) OR the voxel Terrain (grass/water). So we must NOT exclude
	-- TemplateViewerMap anymore — after the per-tile terrain switch, excluding it
	-- meant the ray hit nothing on per-tile tiles (voxels cleared) → surfaceY=0 →
	-- highlight placed underground/invisible. We still exclude the transient visual
	-- folders so the ray never lands on a highlight, unit, or deployment marker.
	for _, name in { "UnitModels", "BattleVisuals", "DeploymentParts", "GridOverlay", "TileHighlights" } do
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
-- FRAME CREATION & POOLING (Neon bar outline)
-- ============================================================

--- Get or create the SurfaceGui outline frame for a tile (pooled).
--- A thin invisible carrier Part hosts 4 Neon edge bars (glowing square outline)
--- plus a faint Neon fill plane. Neon geometry glows via Bloom; no studs.
local function getOrCreateFrame(tx: number, ty: number): any
	local key = tileKey(tx, ty)
	if framePool[key] then return framePool[key] end

	local wx    = _mapOffsetX + (tx - 0.5) * _tileSize
	local wz    = _mapOffsetZ + (ty - 0.5) * _tileSize
	local baseY = getSurfaceY(tx, ty) + SURFACE_OFFSET

	-- NET-004: set all properties BEFORE parenting (parented later in Add).
	local part = Instance.new("Part")
	part.Name        = "TileFrame_" .. key
	part.Anchored    = true
	part.CanCollide  = false
	part.CanQuery    = false
	part.CastShadow  = false
	part.Transparency = 1  -- invisible carrier; the SurfaceGui does the drawing
	part.Size        = Vector3.new(_tileSize, FRAME_THICKNESS, _tileSize)
	part.CFrame      = CFrame.new(wx, baseY, wz)

	-- GLOWING RISING OUTLINE: four thin Neon bars forming the square edge. Neon is
	-- emissive geometry (feeds Bloom) — the ONLY thing that glows here. The old
	-- non-glowing UIStroke border was removed Sep 25 2026 per user. Bars are children
	-- of the carrier Part so they auto-hide/destroy with it; tweened in lockstep in
	-- animateFrame so the whole outline rises together.
	local function makeBar(name, sizeX, sizeZ, offX, offZ)
		local bar = Instance.new("Part")
		bar.Name         = name
		bar.Anchored     = true
		bar.CanCollide   = false
		bar.CanQuery     = false
		bar.CanTouch     = false
		bar.CastShadow   = false
		bar.Material     = Enum.Material.Neon
		bar.Color        = Color3.fromRGB(255, 255, 255)
		bar.Transparency = GLOW_OUTLINE_TRANSPARENCY
		bar.Size         = Vector3.new(sizeX, 0.08, sizeZ)
		bar.CFrame       = CFrame.new(wx + offX, baseY, wz + offZ)
		bar.Parent       = part
		return bar
	end
	local edge = _tileSize / 2 - GLOW_BAR_W / 2
	local bars = {
		makeBar("GlowBar_N", _tileSize, GLOW_BAR_W, 0, -edge),
		makeBar("GlowBar_S", _tileSize, GLOW_BAR_W, 0,  edge),
		makeBar("GlowBar_W", GLOW_BAR_W, _tileSize, -edge, 0),
		makeBar("GlowBar_E", GLOW_BAR_W, _tileSize,  edge, 0),
	}

	-- Subtle interior fill tint (faint Neon plane) — a hint of glow inside the frame,
	-- NOT the bright filled square. High transparency keeps it subtle.
	local fill = Instance.new("Part")
	fill.Name         = "GlowFill"
	fill.Anchored     = true
	fill.CanCollide   = false
	fill.CanQuery     = false
	fill.CanTouch     = false
	fill.CastShadow   = false
	fill.Material     = Enum.Material.Neon
	fill.Color        = Color3.fromRGB(255, 255, 255)
	fill.Transparency = GLOW_FILL_TRANSPARENCY
	fill.Size         = Vector3.new(_tileSize * 0.9, 0.06, _tileSize * 0.9)
	fill.CFrame       = CFrame.new(wx, baseY, wz)
	fill.Parent       = part

	local frame = { part = part, bars = bars, fill = fill, baseY = baseY, wx = wx, wz = wz }
	framePool[key] = frame
	return frame
end

--- Start the looping rising tween on a tile's frame plane. Returns the tween
--- (wrapped in a table) so callers can cancel it on cleanup (PRF-004).
local function animateFrame(frame: any): {Tween}
	local wx, wz, baseY = frame.wx, frame.wz, frame.baseY
	frame.part.CFrame = CFrame.new(wx, baseY, wz)
	local tw = TweenService:Create(frame.part, RISE_INFO, {
		CFrame = CFrame.new(wx, baseY + RISE_HEIGHT, wz),
	})
	tw:Play()
	local tweens = { tw }
	-- Rise the Neon outline bars + fill in lockstep with the border. They are anchored
	-- children, so they do NOT follow the parent CFrame tween automatically — tween
	-- each with the same RISE_INFO so the whole frame rises together.
	local function riseChild(child)
		if not child then return end
		-- Reset to the TRUE surface baseY, NOT the child's current Y. Pooled frames
		-- are reused, and Tween:Cancel() leaves a child wherever it stopped mid-rise;
		-- capturing that drifted Y as the base made re-shown outlines start mid-air.
		-- X/Z never drift (only Y is tweened), so keep them; force Y back to baseY.
		local cx, cz = child.Position.X, child.Position.Z
		child.CFrame = CFrame.new(cx, baseY, cz)
		local t2 = TweenService:Create(child, RISE_INFO, {
			CFrame = CFrame.new(cx, baseY + RISE_HEIGHT, cz),
		})
		t2:Play()
		table.insert(tweens, t2)
	end
	if frame.bars then for _, bar in frame.bars do riseChild(bar) end end
	riseChild(frame.fill)
	return tweens
end

--- Get or create the invisible click-pad for a tile (pooled).
--- Covers the full tile footprint at the tile surface. Thin pads (unlike the
--- tall terrain boxes) do NOT occlude neighbors, so the tile you click is the
--- tile you see highlighted (removes the parallax offset).
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
	move       = { color = Color3.fromRGB(80, 160, 255) },
	target     = { color = Color3.fromRGB(255, 80, 80) },
	selected   = { color = Color3.fromRGB(255, 220, 60) },
	aoe        = { color = Color3.fromRGB(255, 160, 40) },
	invalid    = { color = Color3.fromRGB(180, 180, 180) },
	current    = { color = Color3.fromRGB(100, 200, 255) },
	deploy     = { color = Color3.fromRGB(80, 140, 220) },
	path       = { color = Color3.fromRGB(100, 180, 255) },
	pathDest   = { color = Color3.fromRGB(240, 200, 60) },
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
	for _, frame in framePool do frame.part:Destroy() end
	framePool = {}
	for _, pad in padPool do pad:Destroy() end
	padPool = {}

	-- (Re)create manager-OWNED folders as TOP-LEVEL in workspace.
	-- Critical: do NOT nest under the caller's visualFolder. The battle client
	-- wipes BattleVisuals at battle start, which previously destroyed our pooled
	-- instances out from under the pools and crashed Add(). Owning our own
	-- top-level folder decouples our lifecycle from the caller's.
	if _hlFolder then _hlFolder:Destroy() end
	local hf = Instance.new("Folder")
	hf.Name = "TileHighlights"
	hf.Parent = workspace
	_hlFolder = hf

	local pf = Instance.new("Folder")
	pf.Name = "TileClickPads"
	pf.Parent = hf
	_padFolder = pf

	print("[TileHL] Initialized - SurfaceGui outline frame + click pads")
end

-- ============================================================
-- PUBLIC API
-- ============================================================

--- Add a highlight to a tile (SurfaceGui outline frame).
function TileHighlightManager.Add(
	tx: number, ty: number,
	styleName: string?, groupName: string?,
	overrideColor: Color3?, overrideTrans: number?
)
	local key = tileKey(tx, ty)
	groupName = groupName or "default"

	local style = styleName and TileHighlightManager.Styles[styleName] or nil
	local color = overrideColor or (style and style.color) or Color3.fromRGB(200, 170, 50)

	-- Already highlighted — recolor the existing frame in place (e.g. a move
	-- tile becoming the "selected" confirmation tile: blue -> yellow) instead
	-- of skipping. Keeps existing frame/pad/tween; no duplicate group entry.
	if activeHighlights[key] then
		if activeHighlights[key].frame.bars then for _, bar in activeHighlights[key].frame.bars do bar.Color = color end end
		if activeHighlights[key].frame.fill then activeHighlights[key].frame.fill.Color = color end
		return
	end

	local frame = getOrCreateFrame(tx, ty)
	local pad = getOrCreatePad(tx, ty)

	local parent = _hlFolder or workspace
	if frame.bars then for _, bar in frame.bars do bar.Color = color end end
	if frame.fill then frame.fill.Color = color end
	frame.part.Parent = parent
	pad.Parent = _padFolder or parent

	-- Looping rising animation; tween tracked for cleanup (PRF-004).
	local tweens = animateFrame(frame)

	activeHighlights[key] = { frame = frame, pad = pad, tweens = tweens, group = groupName }

	if not groups[groupName] then groups[groupName] = {} end
	table.insert(groups[groupName], key)
end

--- Remove highlight from a single tile.
function TileHighlightManager.Remove(tx: number, ty: number)
	local key = tileKey(tx, ty)
	local entry = activeHighlights[key]
	if not entry then return end
	if entry.tweens then for _, tw in entry.tweens do tw:Cancel() end end
	if entry.frame then entry.frame.part.Parent = nil end
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
			if entry.tweens then for _, tw in entry.tweens do tw:Cancel() end end
			if entry.frame then entry.frame.part.Parent = nil end
			if entry.pad then entry.pad.Parent = nil end
			activeHighlights[key] = nil
		end
	end
	groups[groupName] = nil
end

--- Clear ALL highlights.
function TileHighlightManager.ClearAll()
	for _, entry in activeHighlights do
		if entry.tweens then for _, tw in entry.tweens do tw:Cancel() end end
		if entry.frame then entry.frame.part.Parent = nil end
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
	for _, frame in framePool do frame.part:Destroy() end
	framePool = {}
	for _, pad in padPool do pad:Destroy() end
	padPool = {}
	if _padFolder then _padFolder:Destroy(); _padFolder = nil end
	if _hlFolder then _hlFolder:Destroy(); _hlFolder = nil end
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
