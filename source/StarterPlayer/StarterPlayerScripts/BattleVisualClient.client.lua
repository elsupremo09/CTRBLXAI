-- BattleVisualClient.client.lua
-- CTRBLXAI | Slice 7B v3 — State-Machine Battle Client
--
-- Responsibilities:
--   - 3D unit tokens, billboard HP/MP, floating text, tile highlights
--   - Receives RemoteEvents → updates data → tells BattleHUD which state
--   - Handles mouse input → advances state machine
--   - Timeline simulation
--   - Never creates 2D ScreenGui panels (BattleHUD owns all 2D)

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()

local BattleEvents = require(
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("Remotes", 10):WaitForChild("BattleEvents", 10)
)
local GameConstants = require(
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("Shared", 10):WaitForChild("GameConstants", 10)
)
local BattleHUD = require(
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("UI", 10):WaitForChild("BattleHUD", 10)
)
local Theme = require(
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("UI", 10):WaitForChild("Theme", 10)
)
-- Terrain surface textures (per-terrain asset IDs) for the Option-1 textured mesh.
local _ttOk, TerrainTextures = pcall(function()
	return require(
		ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
			:WaitForChild("Shared", 10):WaitForChild("TerrainTextures", 10)
	)
end)
if not _ttOk then warn("[TerrainMesh] TerrainTextures require failed: " .. tostring(TerrainTextures)); TerrainTextures = nil end

local LoadoutScreen = require(
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("UI", 10):WaitForChild("LoadoutScreen", 10)
)

local CameraController = require(
	player:WaitForChild("PlayerScripts")
		:WaitForChild("CameraController", 10)
)
local _vfxOk, VFXController = pcall(require,
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("Shared", 10):WaitForChild("VFXController", 10)
)
if not _vfxOk then warn("[BVC] VFXController failed to load: " .. tostring(VFXController)); VFXController = nil end
-- Combat sound effects (client-side; mirrors VFXController). Blank registry
-- slots are skipped silently, so this is harmless until ids are filled in.
local _sndOk, SoundController = pcall(require,
	game:GetService("ReplicatedStorage"):WaitForChild("CTRBLXAI", 10)
		:WaitForChild("Shared", 10):WaitForChild("SoundController", 10))
if not _sndOk then warn("[BVC] SoundController failed to load: " .. tostring(SoundController)); SoundController = nil end

local _thlOk, TileHL = pcall(require,
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("Shared", 10):WaitForChild("TileHighlightManager", 10)
)
if not _thlOk then warn("[BVC] TileHighlightManager failed: " .. tostring(TileHL)); TileHL = nil end

--------------------------------------------------
-- MAP CONFIGURATION
--------------------------------------------------

local TILE_SIZE = 5
local TILE_BASE_HEIGHT = 0.6
-- Must match server MapRenderer.ELEVATION_STEP (dev-locked 2026-09-24: 1.2 for the
-- expanded 1–20 elevation scale). Drives client selection ring, camera focus,
-- hover tooltips, and ray-miss fallback positioning. Keep in sync with server.
local ELEVATION_STEP = 1.2
local MAP_WIDTH, MAP_HEIGHT = 30, 20
local MAP_OFFSET_X = -75
local MAP_OFFSET_Z = -50
local BATTLE_OFFSET_X, BATTLE_OFFSET_Y = 0, 0

local elevationMap = nil

local function getElevation(tx, ty)
	if elevationMap then local r = elevationMap[ty]; if r then return r[tx] or 1 end end; return 1
end
local function tileSurfaceY(elev) return TILE_BASE_HEIGHT + ((elev or 1) - 1) * ELEVATION_STEP end
local R15_STAND_OFFSET_DEFAULT = 2.35  -- fallback if HipHeight can't be read
local function tileToWorld(tx, ty)
	return Vector3.new(MAP_OFFSET_X + (tx - 0.5) * TILE_SIZE, tileSurfaceY(getElevation(tx, ty)) + 1, MAP_OFFSET_Z + (ty - 0.5) * TILE_SIZE)
end
local function tileToWorldR15(tx, ty, hipHeight)
	-- Returns the HRP center position for an R15 model standing on this tile.
	-- hipHeight = distance from feet (tile surface) to HRP center.
	local offset = hipHeight or R15_STAND_OFFSET_DEFAULT
	return Vector3.new(MAP_OFFSET_X + (tx - 0.5) * TILE_SIZE, tileSurfaceY(getElevation(tx, ty)) + offset, MAP_OFFSET_Z + (ty - 0.5) * TILE_SIZE)
end

-- Raycast down to the ACTUAL rendered ground at a tile center. Roblox Terrain
-- voxels quantize to a ~4-stud grid, so the visible surface can sit up to ~2
-- studs above the flat tile-Part top (tileSurfaceY). Placing feet at
-- tileSurfaceY buries the unit in the voxel hill after a move. This returns
-- the true surface Y; falls back to grid math on a ray miss.
-- Excludes overlays that float above ground (TileHighlights frames/pads,
-- GridOverlay), unit models, and battle visuals — but KEEPS TemplateViewerMap
-- so man-made SurfaceGui-terrain tiles (no voxel fill) still register.
local function groundSurfaceY(tx, ty)
	local wx = MAP_OFFSET_X + (tx - 0.5) * TILE_SIZE
	local wz = MAP_OFFSET_Z + (ty - 0.5) * TILE_SIZE
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local ex = {}
	for _, name in { "UnitModels", "BattleVisuals", "DeploymentParts", "GridOverlay", "TileHighlights" } do
		local f = workspace:FindFirstChild(name)
		if f then table.insert(ex, f) end
	end
	-- Exclude map-object models (MapObjModel_*) too: they live INSIDE the map
	-- folder next to the tile Parts, so without this a unit spawning on an object
	-- tile would ground to the decorative model's geometry (floating or sunk)
	-- instead of the terrain surface. Added Oct 5 2026 (burial regression after
	-- object models were introduced).
	local mapFolder = workspace:FindFirstChild("TemplateViewerMap")
	if mapFolder then
		for _, child in ipairs(mapFolder:GetChildren()) do
			if string.sub(child.Name, 1, 12) == "MapObjModel_" then
				table.insert(ex, child)
			end
		end
	end
	rp.FilterDescendantsInstances = ex
	local res = workspace:Raycast(Vector3.new(wx, 200, wz), Vector3.new(0, -400, 0), rp)
	if res then return res.Position.Y end
	return tileSurfaceY(getElevation(tx, ty))  -- fallback: grid math on ray miss
end

-- R15 world position grounded to the real terrain surface (see groundSurfaceY).
local function tileToWorldR15Grounded(tx, ty, hipHeight)
	local offset = hipHeight or R15_STAND_OFFSET_DEFAULT
	return Vector3.new(MAP_OFFSET_X + (tx - 0.5) * TILE_SIZE, groundSurfaceY(tx, ty) + offset, MAP_OFFSET_Z + (ty - 0.5) * TILE_SIZE)
end

-- Grounded twin of tileToWorld (surface + 1) for the cylinder fallback token.
local function tileToWorldGrounded(tx, ty)
	return Vector3.new(MAP_OFFSET_X + (tx - 0.5) * TILE_SIZE, groundSurfaceY(tx, ty) + 1, MAP_OFFSET_Z + (ty - 0.5) * TILE_SIZE)
end

-- WATERFALL SPLASH: scan the terrain grid and place a persistent "Splashing Water"
-- VFX on each waterfall BASE tile — a water tile that has a cardinally-adjacent
-- water neighbour at a HIGHER elevation (i.e. water falls onto it). The splash
-- sits on the base tile's surface, nudged toward the higher neighbour so it reads
-- as the point where the fall lands. Uses the SAME water rule as the server-side
-- waterfall fill (both waters count), so splashes line up with the water sheets.
-- Client-side + visual-only; cleared and rebuilt on every MapDataSync.
local WATERFALL_WATER = { ["Deep Water"] = true, ["Shallow Water"] = true }
local function placeWaterfallSplashes()
	if not VFXController or not VFXController.AddWaterfallSplash then return end
	pcall(VFXController.ClearWaterfallSplashes)
	local reg = VFXController.GetRegistry and VFXController.GetRegistry() or nil
	local assetName = reg and reg.Waterfall or "Splashing Water"
	local dirs = { {1,0}, {-1,0}, {0,1}, {0,-1} }
	-- A splash only appears at a REAL waterfall: the higher water neighbour must be
	-- at least this many elevation levels above the lower water tile. A 1-2 level
	-- water step still shows the connecting water sheet (server-side) but NO splash,
	-- so gently-sloped pools don't spam splashes everywhere — only genuine drops.
	local WATERFALL_MIN_DROP = 3
	for ty = 1, MAP_HEIGHT do
		for tx = 1, MAP_WIDTH do
			local tId = GameConstants.GetTerrainId(tx, ty)
			if WATERFALL_WATER[tId] then
				local selfElev = getElevation(tx, ty)
				-- Find a cardinal water neighbour that is higher by a real DROP
				-- (>= WATERFALL_MIN_DROP levels) — i.e. water genuinely falls onto me.
				local nudgeX, nudgeZ, found = 0, 0, false
				for _, d in ipairs(dirs) do
					local nx, ny = tx + d[1], ty + d[2]
					local nId = GameConstants.GetTerrainId(nx, ny)
					if nId and WATERFALL_WATER[nId] and (getElevation(nx, ny) - selfElev) >= WATERFALL_MIN_DROP then
						found = true
						-- Nudge toward the higher neighbour (where the fall lands).
						nudgeX = nudgeX + d[1]
						nudgeZ = nudgeZ + d[2]
					end
				end
				if found then
					local base = tileToWorld(tx, ty)  -- base tile surface (+1)
					local pos = base + Vector3.new(nudgeX * (TILE_SIZE * 0.35), 0, nudgeZ * (TILE_SIZE * 0.35))
					pcall(VFXController.AddWaterfallSplash, tx, ty, assetName, pos)
				end
			end
		end
	end
end
local function templateToBattle(x, y)
	local bx, by = x - BATTLE_OFFSET_X, y - BATTLE_OFFSET_Y
	if bx >= 1 and bx <= MAP_WIDTH and by >= 1 and by <= MAP_HEIGHT then return bx, by end
	return nil, nil
end

--------------------------------------------------
-- STATE
--------------------------------------------------

local unitTokens   = {}
local unitData     = {}

-- Compute legal push landing tiles along the FIXED away-direction from pusher→target.
-- Mirrors DisplacementService.ResolvePush interrupt logic: stops at map edge, blocker,
-- forced-upward elevation, or an occupied tile. Returns array of {tileX,tileY,distance}
-- for distances 1..maxDist that the target can actually reach (clear tiles only).
local function computePushLandingTiles(actorX, actorY, targetX, targetY, maxDist)
	local rawDx, rawDy = targetX - actorX, targetY - actorY
	local dx, dy = 0, 0
	if rawDx > 0 then dx = 1 elseif rawDx < 0 then dx = -1 end
	if rawDy > 0 then dy = 1 elseif rawDy < 0 then dy = -1 end
	if dx == 0 and dy == 0 then dx = 1 end
	local tiles = {}
	local cx, cy = targetX, targetY
	local curElev = getElevation(cx, cy)
	for step = 1, math.max(0, maxDist) do
		local nx, ny = cx + dx, cy + dy
		-- map bounds
		if nx < 1 or nx > MAP_WIDTH or ny < 1 or ny > MAP_HEIGHT then break end
		-- blocker
		if GameConstants.IsBlocked(nx, ny) then break end
		-- forced upward elevation blocks
		local nElev = getElevation(nx, ny)
		if nElev > curElev then break end
		-- occupancy (another unit)
		local occupied = false
		for _, d in pairs(unitData) do
			if d.isAlive ~= false and d.tileX == nx and d.tileY == ny then occupied = true; break end
		end
		if occupied then break end
		-- clear tile — legal landing spot
		table.insert(tiles, { tileX = nx, tileY = ny, distance = step })
		cx, cy, curElev = nx, ny, nElev
	end
	return tiles
end
local visualFolder = Instance.new("Folder"); visualFolder.Name = "BattleVisuals"; visualFolder.Parent = workspace

local isPlayerTurn    = false
local currentPrompt   = nil
local timelineSnapshot = nil
local currentBattleCt  = 0
local currentTimePhase = "Dawn"  -- time-of-day phase (updated by TimePhaseChanged); read by updateTimeline for the bar's time icon
local activeUnitId    = nil  -- who is currently acting (for timeline NOW marker)
local devLastInspectedId = nil -- tracks last tile-clicked unit for Kill At Tile (dev only)
local inputMode       = nil -- "move","attack","skill"
local selectedSkill   = nil
local selectedItem    = nil -- consumable entry selected during ItemSelection
local highlightParts  = {}
local aimTarget       = nil
-- Push distance sub-stage: after choosing a push target, player picks a stop tile
-- (1..max) along the fixed away-direction. pushLandingTiles holds the legal path.
local pushTargetSel   = nil  -- the chosen push target entry
local pushLandingTiles = nil -- array of {tileX,tileY,distance} along away-ray
local pathHighlightParts = {}  -- separate from highlightParts so move-range stays visible
local storedActorData = nil -- shared across enterActionSelection and click handlers

-- Battle presentation: single table of everything the HUD needs to display
local bp = {
	state = "Idle",
	actor = nil,
	target = nil,
	skill = nil,
	preview = nil,
	tile = nil,
	inspectedEntityId = nil,
}

--------------------------------------------------
-- HIGHLIGHTS
--------------------------------------------------

local function clearHighlights()
	if TileHL then TileHL.ClearGroup("battle") end
	highlightParts = {}
	-- Also clear path highlights
	if TileHL then TileHL.ClearGroup("path") end
	for _, obj in ipairs(pathHighlightParts) do obj:Destroy() end -- arrows (WedgeParts)
	pathHighlightParts = {}
end

-- Highlight styles — delegates to TileHighlightManager (EditableMesh terrain-conforming).
-- Fallback to a simple Part if TileHL is unavailable.
local HIGHLIGHT_STYLES = {
	move     = { color = Theme.Colors.TileMove,     transparency = 0.50 },
	target   = { color = Theme.Colors.TileTarget,   transparency = 0.40 },
	selected = { color = Theme.Colors.TileSelected,  transparency = 0.25 },
	aoe      = { color = Theme.Colors.TileAOE,      transparency = 0.40 },
	invalid  = { color = Theme.Colors.TileInvalid,   transparency = 0.65 },
	current  = { color = Theme.Colors.Info,          transparency = 0.40 },
}

local function tileKey(tx, ty) return tx .. "_" .. ty end

local function createTileHighlight(bx, by, colorOrStyle, _transparency)
	local tx, ty = bx + BATTLE_OFFSET_X, by + BATTLE_OFFSET_Y

	if TileHL then
		local styleName = type(colorOrStyle) == "string" and colorOrStyle or nil
		local overColor = type(colorOrStyle) ~= "string" and colorOrStyle or nil
		TileHL.Add(tx, ty, styleName, "battle", overColor, _transparency)
		table.insert(highlightParts, tileKey(tx, ty))
	end
end

-- Skill-target tile color by skill TAGS (user spec Sep 25 2026). Priority:
--   1. Direct Damage -> red     (wins even if also Debuff/Utility)
--   2. Debuff        -> purple
--   3. Healing/Buff  -> green
--   4. Utility       -> yellow  (pure movement/positioning skills)
--   fallback         -> muddy gold (untagged skill)
-- Returns a Color3. Reads skill.tags (array of strings), present on the client
-- skill object (same field bp.skill uses).
local SKILL_COLOR_DMG    = Color3.fromRGB(255, 80, 80)   -- red
local SKILL_COLOR_DEBUFF = Color3.fromRGB(180, 90, 220)  -- purple
local SKILL_COLOR_HEAL   = Color3.fromRGB(60, 180, 80)   -- green
local SKILL_COLOR_UTIL   = Color3.fromRGB(255, 220, 60)  -- yellow
local SKILL_COLOR_FALLBACK = Color3.fromRGB(180, 150, 60) -- muddy gold
local function skillTargetColor(skill)
	if not skill then return SKILL_COLOR_FALLBACK end
	local has = {}
	for _, tag in ipairs(skill.tags or {}) do has[tag] = true end
	-- isHealing flag is authoritative for heals even if tags omit 'Healing'.
	-- Direct Damage wins even over Summon: a summon that is a SECONDARY rider on a
	-- damage skill (e.g. "summon a zombie on killing blow") is fundamentally a damage
	-- skill and reads RED. Summon otherwise takes priority over Debuff/Heal/Buff/
	-- Utility, so a PRIMARY summon (its main purpose) reads YELLOW — including a
	-- summon that also heals or debuffs (per user spec Sep 25 2026: Summon is priority
	-- unless it is a secondary effect of a damage skill).
	if has["Direct Damage"] then return SKILL_COLOR_DMG end
	if has["Summon"] then return SKILL_COLOR_UTIL end
	if has["Debuff"] then return SKILL_COLOR_DEBUFF end
	if skill.isHealing or has["Healing"] or has["Buff"] then return SKILL_COLOR_HEAL end
	if has["Utility"] then return SKILL_COLOR_UTIL end
	return SKILL_COLOR_FALLBACK
end

-- Item-target tile color by consumable CATEGORY (user spec Sep 25 2026). Items
-- carry a `category` field (7-type taxonomy) rather than skill-style tags:
--   Damage -> red · Control -> purple · Recovery/Support -> green ·
--   Utility/Environment/Deployable -> yellow · fallback -> gold.
local ITEM_CATEGORY_COLOR = {
	Damage      = SKILL_COLOR_DMG,
	Control     = SKILL_COLOR_DEBUFF,
	Recovery    = SKILL_COLOR_HEAL,
	Support     = SKILL_COLOR_HEAL,
	Utility     = SKILL_COLOR_UTIL,
	Environment = SKILL_COLOR_UTIL,
	Deployable  = SKILL_COLOR_UTIL,
}
local function itemTargetColor(item)
	if not item then return SKILL_COLOR_FALLBACK end
	-- isHealing is authoritative for green even if category is unusual.
	if item.isHealing then return SKILL_COLOR_HEAL end
	return ITEM_CATEGORY_COLOR[item.category or ""] or SKILL_COLOR_FALLBACK
end
-- PATH HIGHLIGHTS (rendered separately so move-range stays visible)

local PATH_HAZARDS = {
	Molten           = { warn = "Burn",    color = Color3.fromRGB(255, 100, 30) },
	["Tainted Ground"] = { warn = "MP drain", color = Color3.fromRGB(160, 60, 180) },
	["Deep Water"]   = { warn = "Drowning", color = Color3.fromRGB(40, 80, 160) },
	["Shallow Water"]= { warn = "+1 cost",  color = Color3.fromRGB(80, 160, 220) },
	Ice              = { warn = "Slide",    color = Color3.fromRGB(180, 220, 255) },
	Sand             = { warn = "+1 cost",  color = Color3.fromRGB(200, 180, 100) },
	Mud              = { warn = "+1 cost",  color = Color3.fromRGB(140, 100, 60) },
	Swamp            = { warn = "+2 cost",  color = Color3.fromRGB(80, 120, 60) },
}

local function clearMovePath()
	if TileHL then TileHL.ClearGroup("path") end
	for _, p in ipairs(pathHighlightParts) do p:Destroy() end -- arrows only
	pathHighlightParts = {}
end

local function renderMovePath(path, destX, destY)
	clearMovePath()

	-- Build full ordered list: intermediate path tiles + destination
	local fullPath = {}
	for _, step in ipairs(path or {}) do
		table.insert(fullPath, { tileX = step.tileX, tileY = step.tileY, terrain = step.terrain })
	end
	table.insert(fullPath, { tileX = destX, tileY = destY, isDest = true })

	for i, step in ipairs(fullPath) do
		local tx, ty = step.tileX, step.tileY
		local elev = getElevation(tx, ty)
		local surfaceY = tileSurfaceY(elev) + 3.5

		-- Path tile highlight via Highlight instance
		local hazard = PATH_HAZARDS[step.terrain]
		local tileColor
		if step.isDest then
			tileColor = Color3.fromRGB(240, 200, 60) -- gold destination
		elseif hazard then
			tileColor = hazard.color
		else
			tileColor = Color3.fromRGB(100, 180, 255) -- bright path blue
		end

		-- Path tile highlight via TileHighlightManager
		if TileHL then
			local ptx, pty = tx + BATTLE_OFFSET_X, ty + BATTLE_OFFSET_Y
			local pathStyle = step.isDest and "pathDest" or "path"
			TileHL.Add(ptx, pty, pathStyle, "path", tileColor, step.isDest and 0.15 or 0.30)
		end

		-- (Floating white Neon arrow indicators removed Sep 25 2026 per user — the
		-- path tile highlights above are sufficient; the arrows read as shiny white
		-- clutter. The blue path tiles + gold destination remain via TileHL.)
	end
end

--------------------------------------------------
-- UNIT SELECTION RING (glowing disc under a unit)
--------------------------------------------------

local selectionRing = nil

local function showSelectionRing(uid)
	if selectionRing then selectionRing:Destroy(); selectionRing = nil end
	local data = unitData[uid]
	if not data or data.isAlive == false then return end
	local worldPos = tileToWorld(data.tileX, data.tileY)

	local ring = Instance.new("Part")
	ring.Name = "SelectionRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.15, TILE_SIZE * 0.7, TILE_SIZE * 0.7)
	ring.CFrame = CFrame.new(worldPos - Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored, ring.CanCollide, ring.CanQuery = true, false, false
	ring.Color = Theme.Colors.BorderFocused
	ring.Transparency = 0.3
	ring.Material = Enum.Material.Neon
	ring.Parent = visualFolder
	selectionRing = ring
end

local function hideSelectionRing()
	if selectionRing then selectionRing:Destroy(); selectionRing = nil end
end

--------------------------------------------------
-- 3D TOKENS
--------------------------------------------------

-- Orient a unit to its facing: rotate the R15 model in place (same CFrame.lookAt
-- convention the move handler uses, so it agrees with the walk animation) AND
-- show a stud-free SurfaceGui chevron on the ground pointing the same way. The
-- chevron is the primary cue for cylinder-fallback units (no model to rotate).
local function orientUnitToFacing(unitId, facing, skipModelRotate)
	local token = unitTokens[unitId]
	if not token or not token.part then return end
	local vec = GameConstants.FACING_VECTORS[facing]
	if not vec then return end
	local mag = math.sqrt(vec.dx * vec.dx + vec.dy * vec.dy)
	if mag == 0 then return end
	local worldDir = Vector3.new(vec.dx / mag, 0, vec.dy / mag)

	-- 1) Rotate the R15 model in place (cylinders have no model).
	if token.model and not skipModelRotate then
		local pivot = token.model:GetPivot()
		local p = pivot.Position
		pcall(function() token.model:PivotTo(CFrame.lookAt(p, p + worldDir)) end)
	end

	-- 2) Ground chevron (lazy-created, one per token). Stud-free SurfaceGui on an
	-- invisible plane — same technique as the facing arrows/tile frames.
	local pad = token.facePad
	if not pad then
		pad = Instance.new("Part")
		pad.Name         = "FaceIndicator_" .. tostring(unitId)
		pad.Anchored     = true
		pad.CanCollide   = false
		pad.CanQuery     = false
		pad.CastShadow   = false
		pad.Transparency = 1
		pad.Size         = Vector3.new(2.5, 0.1, 2.5)   -- halved per request
		local sg = Instance.new("SurfaceGui")
		sg.Face           = Enum.NormalId.Top
		sg.SizingMode     = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud  = 48
		sg.LightInfluence = 0
		sg.Parent         = pad
		-- Facing arrow = uploaded green-arrow Image (asset 111086634875547),
		-- drawn pointing UP so rotation 0 = world-North. It rides inside the
		-- "Glyph" container so the atan2(dx,-dy) rotation below points it head-
		-- forward along the unit's world facing (camera-proof). ImageLabel on a
		-- SurfaceGui is stud-free (no part face). Image is left untinted so the
		-- arrow keeps its own green; set ImageColor3 to tint per-state if wanted.
		local glyphRoot = Instance.new("ImageLabel")
		glyphRoot.Name             = "Glyph"
		glyphRoot.AnchorPoint      = Vector2.new(0.5, 0.5)
		glyphRoot.Position         = UDim2.fromScale(0.5, 0.5)
		glyphRoot.Size             = UDim2.fromScale(1, 1)
		glyphRoot.BackgroundTransparency = 1
		glyphRoot.Image            = "rbxassetid://111086634875547"
		glyphRoot.ScaleType        = Enum.ScaleType.Fit
		glyphRoot.Parent           = sg
		pad.Parent = visualFolder
		token.facePad = pad
	end
	-- Float the chevron ABOVE the unit's head, not on the ground. Ground-level
	-- placement (even offset forward) was buried by tall grass and occluded by
	-- voxel terrain at the 45-degree camera. Overhead clears all terrain, is
	-- always visible, and stays model-independent (reads facing + position only).
	-- A small forward nudge along the facing keeps the pointing direction clear.
	-- Store the facing direction so the per-frame follow loop can keep the small
	-- forward lean without recomputing facing every frame.
	token._faceDir = worldDir
	-- Immediate placement (the Heartbeat follow below keeps it glued afterward).
	pad.CFrame = CFrame.new(
		token.part.Position.X + worldDir.X * FACE_FWD_NUDGE,
		token.part.Position.Y + FACE_OVERHEAD_H,
		token.part.Position.Z + worldDir.Z * FACE_FWD_NUDGE
	)
	local glyph = pad:FindFirstChild("Glyph", true)
	if glyph then
		-- Top-face GUI: up (-Y) maps to world -Z (North). Clockwise per (dx,dy).
		-- The uploaded arrow art points DOWN, and testing showed the result was a
		-- consistent 90 deg CCW off, so the total offset is 270 deg (180 for the
		-- down-pointing art + 90 to correct the observed CCW skew). This makes the
		-- arrowhead point along the unit's true world facing.
		glyph.Rotation = math.deg(math.atan2(vec.dx, -vec.dy)) + 270
	end
end

-- Facing-indicator placement constants (shared by orientUnitToFacing + follow loop)
FACE_OVERHEAD_H  = 5.5   -- studs above the unit anchor
FACE_FWD_NUDGE   = 0.6   -- slight lean toward the faced direction

-- Continuously glue each unit's facing arrow above the unit so it follows moves,
-- knockback, and any displacement in real time. Discrete repositioning (spawn /
-- facing-choice / one delayed call after a move) left the arrow stranded on
-- multi-move and mid-tween cases. Position-only per frame (cheap for <=6 units);
-- rotation changes only on facing change, handled in orientUnitToFacing.
RunService.Heartbeat:Connect(function()
	for _, token in pairs(unitTokens) do
		local pad = token.facePad
		if pad and pad.Parent and token.part then
			local dir = token._faceDir or Vector3.zero
			pad.CFrame = CFrame.new(
				token.part.Position.X + dir.X * FACE_FWD_NUDGE,
				token.part.Position.Y + FACE_OVERHEAD_H,
				token.part.Position.Z + dir.Z * FACE_FWD_NUDGE
			)
		end
	end
end)

-- HP-bar name label: ONE source of truth for its text + colour, so spawn, HP
-- updates and turn start/end can't drift apart (they previously overwrote the
-- tier star with the plain name and recoloured enemy names gold/white).
-- Enemy names are always red; players are gold while active, light otherwise.
local function unitNameColor(u, isActive)
	if u and u.side == "Enemy" then return Theme.Colors.Danger end
	if u and u.side == "Neutral" then return Theme.Colors.Warning end
	return isActive and Theme.Colors.TextGold or Theme.Colors.TextPrimary
end

-- Plain name text for the HP-bar label (the tier star is a separate ImageLabel,
-- applied by applyUnitNameStar — image assets, not a text glyph, so no font risk).
local function unitNameLabelText(u)
	if not u then return "" end
	return tostring(u.name or u.id or "")
end

-- Tier star images: gold for Elite, silver for Veteran, hidden otherwise.
local TIER_STAR_IMAGE = {
	Elite   = "rbxassetid://134634995983546",  -- gold star
	Veteran = "rbxassetid://126540666012445",  -- silver star
}
-- Show/hide + set the token's tier-star ImageLabel from the unit's enemyType.
local function applyUnitNameStar(token, u)
	if not token or not token.star then return end
	local img = u and u.enemyType and TIER_STAR_IMAGE[u.enemyType] or nil
	if img then
		token.star.Image = img
		token.star.Visible = true
	else
		token.star.Visible = false
	end
end

-- Base R15 animations played on character models in response to combat events.
-- Free default R15 animation ids are used for now (user may swap specific ids
-- later, same as the walk track). Reliable free ids: idle/walk/run/jump exist;
-- Roblox has no guaranteed "hit"/"death" default, so hit uses a short reaction
-- and KO uses a fall/faint — flagged as generic until specific ids are supplied.
local R15_ANIM = {
	Idle       = "rbxassetid://507766666",  -- default R15 idle (looped)
	Hit        = "rbxassetid://507768375",  -- default R15 "cheer"/react — generic flinch stand-in
	KO         = "rbxassetid://507765000",  -- default R15 fall-ish — generic KO stand-in
	Attack     = "rbxassetid://507768375",  -- generic melee swing stand-in
	Projectile = "rbxassetid://507767714",  -- default R15 run-ish — generic bow/gun draw stand-in
	Cast       = "rbxassetid://507770677",  -- default R15 point/wave — generic spell-cast stand-in
	ItemUse    = "rbxassetid://507770239",  -- default R15 wave — generic item-use stand-in
}

-- Get-or-create the Humanoid's Animator for a token's R15 model (nil for cylinders).
local function getUnitAnimator(token)
	if not token or not token.model then return nil end
	local hum = token.model:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	return animator
end

-- Play (and cache) a named base animation on a unit's model. kind is a key in
-- R15_ANIM. opts: { loop=bool, fade=number, stopAfter=number }. Cylinders no-op.
local function playUnitAnim(token, kind, opts)
	opts = opts or {}
	local id = R15_ANIM[kind]
	if not id then return end
	local animator = getUnitAnimator(token)
	if not animator then return end  -- cylinder fallback: no animations
	token._animTracks = token._animTracks or {}
	local track = token._animTracks[kind]
	if not track then
		local ok, t = pcall(function()
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			return animator:LoadAnimation(anim)
		end)
		if ok and t then
			track = t
			track.Looped = opts.loop == true
			token._animTracks[kind] = track
		end
	end
	if not track then return end
	track.Looped = opts.loop == true
	track:Play(opts.fade or 0.1)
	if opts.stopAfter and not opts.loop then
		task.delay(opts.stopAfter, function()
			if track and track.IsPlaying then track:Stop(0.15) end
		end)
	end
	return track
end

-- Stop a unit's looping idle (e.g. on KO so the body doesn't keep breathing).
local function stopUnitIdle(token)
	if token and token._animTracks and token._animTracks.Idle and token._animTracks.Idle.IsPlaying then
		token._animTracks.Idle:Stop(0.2)
	end
end

local function spawnToken(unit)
	-- Try to find a server-spawned R15 model for this unit
	local model = nil
	local anchorPart = nil
	-- Look for server-spawned R15 model in workspace/UnitModels
	local unitModelsFolder = workspace:FindFirstChild("UnitModels")
	if unitModelsFolder then
		model = unitModelsFolder:FindFirstChild("Unit_" .. unit.id)
	end

	if model and model:IsA("Model") then
		-- R15 model found — use its HumanoidRootPart as the anchor
		anchorPart = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
		if anchorPart then
			-- Position model feet on tile surface.
			-- PivotTo places the model's PIVOT (which is at the feet for R15 rigs)
			-- at the given CFrame. So we just need the tile surface Y, no HipHeight math.
			-- Ground feet to the real voxel surface (not the buried tile-Part top),
			-- matching the grounded move path so R15 units don't spawn buried.
			local feetY = groundSurfaceY(unit.tileX, unit.tileY)
			local feetPos = Vector3.new(
				MAP_OFFSET_X + (unit.tileX - 0.5) * TILE_SIZE,
				feetY,
				MAP_OFFSET_Z + (unit.tileY - 0.5) * TILE_SIZE
			)
			model:PivotTo(CFrame.new(feetPos))
			anchorPart.Anchored = true
			-- Disable the built-in Humanoid name/health display above the model —
			-- it duplicates the name already shown inside the HP-bar billboard.
			local _hum = model:FindFirstChildOfClass("Humanoid")
			if _hum then
				_hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				_hum.NameDisplayDistance = 0
				_hum.HealthDisplayDistance = 0
			end
			-- Reparent to visualFolder if not already there
			if model.Parent ~= visualFolder then
				model.Parent = visualFolder
			end
		else
			-- Model has no HumanoidRootPart — treat as invalid, fall back
			model = nil
		end
	end

	-- Fallback: create cylinder placeholder if no R15 model
	if not anchorPart then
		local part = Instance.new("Part")
		part.Name = "Unit_" .. unit.id
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(1.8, 1.8, 1.8)
		part.CFrame = CFrame.new(tileToWorldGrounded(unit.tileX, unit.tileY)) * CFrame.Angles(0,0,math.rad(90))
		part.Anchored, part.CanCollide, part.CanQuery = true, false, true
		part.Color = Theme.GetSideColor(unit.side)
		part.Material = Enum.Material.SmoothPlastic
		part.Parent = visualFolder
		anchorPart = part
	end

	-- HP + MP billboard. A dedicated star column sits to the LEFT of the bars so
	-- the tier star is clearly visible (not crammed inside the HP fill). The left
	-- column is ALWAYS reserved (star hidden for Grunts/players) so every unit's
	-- bars line up at the same screen position regardless of tier.
	local STAR_SIZE = 26  -- tier star size
	local BAR_W    = 48   -- px width of the HP/MP bars
	local BAR_STACK_H = 13           -- HP(9) + MP(4)
	local STAR_GAP = 1    -- px gap between the MP bar and the star below it
	-- Billboard holds the HP+MP bar stack on top and the tier star centered BELOW.
	local BB_H = BAR_STACK_H + STAR_GAP + STAR_SIZE
	local barBb = Instance.new("BillboardGui"); barBb.Size = UDim2.new(0, BAR_W, 0, BB_H)
	local BAR_TOP = 0                -- bars sit at the top of the billboard
	-- Raise the billboard so the taller bar+star cluster clears the model's head.
	-- The star hangs ~27px below the bars; the extra StudsOffset lifts the whole
	-- billboard up so the star sits just under the bar near the head top, not over it.
	barBb.StudsOffset = Vector3.new(0, model and 3.8 or 2.0, 0)
	barBb.AlwaysOnTop = true; barBb.Parent = anchorPart

	-- Tier star: ImageLabel centered BELOW the HP/MP bars (gold = Elite, silver =
	-- Veteran). Hidden for Grunts/players (applyUnitNameStar toggles .Visible).
	local starImg = Instance.new("ImageLabel")
	starImg.Name = "TierStar"
	starImg.BackgroundTransparency = 1
	starImg.AnchorPoint = Vector2.new(0.5, 0)
	starImg.Position = UDim2.new(0.5, 0, 0, BAR_STACK_H + STAR_GAP)  -- centered, below the bars
	starImg.Size = UDim2.fromOffset(STAR_SIZE, STAR_SIZE)
	starImg.ScaleType = Enum.ScaleType.Fit
	starImg.ZIndex = 3
	starImg.Visible = false
	starImg.Parent = barBb

	-- HP bar (9px tall — fits name text inside), full width at the top
	local hpBg = Instance.new("Frame")
	hpBg.Size = UDim2.new(0, BAR_W, 0, 9)
	hpBg.Position = UDim2.new(0, 0, 0, BAR_TOP)
	hpBg.BackgroundColor3 = Theme.Colors.Panel; hpBg.BorderSizePixel = 0; hpBg.Parent = barBb
	Instance.new("UICorner", hpBg).CornerRadius = UDim.new(0,2)
	local hpStroke = Instance.new("UIStroke", hpBg)
	hpStroke.Color = Theme.Colors.BadgeBg; hpStroke.Thickness = 1
	local hpFill = Instance.new("Frame"); hpFill.Name = "Fill"
	hpFill.Size = UDim2.fromScale(1,1); hpFill.BackgroundColor3 = Theme.Colors.HP
	hpFill.BorderSizePixel = 0; hpFill.Parent = hpBg
	Instance.new("UICorner", hpFill).CornerRadius = UDim.new(0,2)

	-- Name label (inside HP bar)
	local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.fromScale(1,1)
	lbl.BackgroundTransparency = 1
	lbl.TextSize = 8; lbl.Font = Theme.Font.PrimaryBold
	-- Crisp black outline on the name (all units).
	lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
	lbl.TextStrokeTransparency = 0
	-- Enemy names render red; players keep the default light color (active = gold).
	lbl.TextColor3 = unitNameColor(unit)
	lbl.Text = unitNameLabelText(unit)
	lbl.ZIndex = 2
	lbl.Parent = hpBg

	-- MP bar (bottom portion: 4px, directly below HP), aligned under the HP bar
	local mpBg = Instance.new("Frame")
	mpBg.Size = UDim2.new(0, BAR_W, 0, 4)
	mpBg.Position = UDim2.new(0, 0, 0, BAR_TOP + 9)
	mpBg.BackgroundColor3 = Theme.Colors.Panel; mpBg.BorderSizePixel = 0; mpBg.Parent = barBb
	Instance.new("UICorner", mpBg).CornerRadius = UDim.new(0,2)
	local mpStroke = Instance.new("UIStroke", mpBg)
	mpStroke.Color = Theme.Colors.BadgeBg; mpStroke.Thickness = 1
	local mpFill = Instance.new("Frame"); mpFill.Name = "Fill"
	mpFill.Size = UDim2.fromScale(1,1); mpFill.BackgroundColor3 = Theme.Colors.MP
	mpFill.BorderSizePixel = 0; mpFill.Parent = mpBg
	Instance.new("UICorner", mpFill).CornerRadius = UDim.new(0,2)

	-- Measure the actual pivot-to-HRP offset from the live model.
	-- Model:GetPivot() returns the feet position; HRP.Position is the hip center.
	-- The difference is the correct standing offset for this model.
	local _hipH = R15_STAND_OFFSET_DEFAULT
	if model and anchorPart then
		-- PivotTo places the model's pivot (feet) at the target position.
		-- HRP center sits above the pivot by: HipHeight + 0.5*HRP.Size.Y
		-- But with scaling, these values may differ from the template.
		-- Safest: measure from the live model after it's in workspace.
		local pivotY = model:GetPivot().Position.Y
		local hrpY = anchorPart.Position.Y
		_hipH = math.abs(hrpY - pivotY)
		if _hipH < 0.5 then _hipH = R15_STAND_OFFSET_DEFAULT end  -- sanity fallback
	end
	unitTokens[unit.id] = { part = anchorPart, model = model, fill = hpFill, mpFill = mpFill, label = lbl, star = starImg, hipHeight = _hipH }
	-- Set the tier star (gold Elite / silver Veteran / hidden otherwise). Tier is
	-- fixed for the battle, so applying once at spawn is enough; the star is its
	-- own ImageLabel so HP/turn label updates never disturb it.
	applyUnitNameStar(unitTokens[unit.id], unit)
	-- Base idle animation so standing R15 units aren't frozen stiff (looped; no-op
	-- for cylinder fallbacks). Hit/KO/Attack one-shots play over this on events.
	playUnitAnim(unitTokens[unit.id], "Idle", { loop = true, fade = 0.3 })
	-- Show initial facing for EVERY unit (players + enemies) from spawn. Default to
	-- "S" if the payload omits facing so an indicator always appears.
	orientUnitToFacing(unit.id, unit.facing or "S")
	-- [RIGPROBE] TEMPORARY: measure the R15 rig's real forward axis vs the facing
	-- it was told to show, so the model-facing correction angle can be set exactly.
	-- Remove once the offset is locked in. Prints only for R15 models.
	if model and anchorPart then
		task.defer(function()
			local fv = GameConstants.FACING_VECTORS[unit.facing or "S"]
			if not fv then return end
			local mag = math.sqrt(fv.dx*fv.dx + fv.dy*fv.dy)
			if mag == 0 then return end
			local wantDir = Vector3.new(fv.dx/mag, 0, fv.dy/mag)  -- direction the ARROW points
			local look = anchorPart.CFrame.LookVector  -- where the MODEL front points
			local lookFlat = Vector3.new(look.X, 0, look.Z)
			if lookFlat.Magnitude < 0.001 then return end
			lookFlat = lookFlat.Unit
			-- signed yaw from wantDir -> lookFlat, degrees (how far the rig front is off)
			local dot = math.clamp(wantDir:Dot(lookFlat), -1, 1)
			local cross = wantDir.X*lookFlat.Z - wantDir.Z*lookFlat.X
			local deg = math.deg(math.atan2(cross, dot))
			print(string.format("[RIGPROBE] %s facing=%s want=(%.2f,%.2f) look=(%.2f,%.2f) rigOffsetDeg=%.1f",
				tostring(unit.id), tostring(unit.facing or "S"), wantDir.X, wantDir.Z, lookFlat.X, lookFlat.Z, deg))
		end)
	end
end

local function updateHpBar(uid, hp, maxHp)
	local t = unitTokens[uid]; if not t then return end
	-- Guard against a nil/zero maxHp (stale or partial payloads — e.g. a unit
	-- serialized with maxHp=0 during deployment, or a death-time snapshot). Without
	-- this, hp/maxHp is a divide-by-zero -> nan -> UDim2.fromScale(nan,1) renders a
	-- BROKEN/empty bar. Mirror updateMpBar's guard: keep the last good bar instead.
	-- Still refresh the name label so it stays correct.
	if not hp or not maxHp or maxHp <= 0 then
		t.label.Text = unitData[uid] and unitNameLabelText(unitData[uid]) or uid
		return
	end
	local r = math.clamp(hp/maxHp, 0, 1)
	t.fill.BackgroundColor3 = Theme.GetHPColor(r)
	TweenService:Create(t.fill, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {Size = UDim2.fromScale(r,1)}):Play()
	t.label.Text = unitData[uid] and unitNameLabelText(unitData[uid]) or uid
end

local function updateMpBar(uid, mp, maxMp)
	local t = unitTokens[uid]; if not t or maxMp <= 0 then return end
	TweenService:Create(t.mpFill, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {Size = UDim2.fromScale(math.clamp(mp/maxMp,0,1),1)}):Play()
end

--------------------------------------------------
-- FLOATING TEXT
--------------------------------------------------

local function showFloatingText(worldPos, text, color, dur)
	dur = dur or 0.9
	local anchor = Instance.new("Part"); anchor.Anchored = true; anchor.CanCollide = false
	anchor.CanQuery = false; anchor.Transparency = 1; anchor.Size = Vector3.new(0.1,0.1,0.1)
	anchor.Position = worldPos + Vector3.new(0,2,0); anchor.Parent = visualFolder
	local bb = Instance.new("BillboardGui"); bb.Size = UDim2.new(0,160,0,36); bb.AlwaysOnTop = true; bb.Parent = anchor
	local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.fromScale(1,1); lbl.BackgroundTransparency = 1
	lbl.Font = Theme.Font.PrimaryBold; lbl.TextSize = 20; lbl.TextColor3 = color
	lbl.TextStrokeTransparency = 0.2; lbl.Text = text; lbl.Parent = bb
	TweenService:Create(anchor, TweenInfo.new(dur, Enum.EasingStyle.Quad), {Position = worldPos + Vector3.new(0,5,0)}):Play()
	TweenService:Create(lbl, TweenInfo.new(dur*0.6, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, dur*0.4), {TextTransparency=1, TextStrokeTransparency=1}):Play()
	task.delay(dur + 0.1, function() anchor:Destroy() end)
end

-- Specialized combat feedback (larger damage, smaller status/info)
local function showDamageText(worldPos, amount, isHeal)
	local text = isHeal and ("+"..amount) or ("-"..amount)
	local color = isHeal and Theme.Colors.Success or Theme.Colors.Danger
	-- Use larger text for damage
	local dur = 1.1
	local anchor = Instance.new("Part"); anchor.Anchored = true; anchor.CanCollide = false
	anchor.CanQuery = false; anchor.Transparency = 1; anchor.Size = Vector3.new(0.1,0.1,0.1)
	anchor.Position = worldPos + Vector3.new(0, 2.5, 0); anchor.Parent = visualFolder
	local bb = Instance.new("BillboardGui"); bb.Size = UDim2.new(0,140,0,40); bb.AlwaysOnTop = true; bb.Parent = anchor
	local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.fromScale(1,1); lbl.BackgroundTransparency = 1
	lbl.Font = Theme.Font.Display; lbl.TextSize = 26; lbl.TextColor3 = color
	lbl.TextStrokeTransparency = 0.1; lbl.TextStrokeColor3 = Color3.fromRGB(0,0,0)
	lbl.Text = text; lbl.Parent = bb
	TweenService:Create(anchor, TweenInfo.new(dur, Enum.EasingStyle.Quad), {Position = worldPos + Vector3.new(0,6,0)}):Play()
	TweenService:Create(lbl, TweenInfo.new(dur*0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, dur*0.5), {TextTransparency=1, TextStrokeTransparency=1}):Play()
	task.delay(dur + 0.1, function() anchor:Destroy() end)
end

local function showStatusText(worldPos, text, color)
	showFloatingText(worldPos + Vector3.new(0, 0.5, 0), text, color or Theme.Colors.Info, 1.2)
end

--------------------------------------------------
-- ACTION ANNOUNCE LABEL (stays ~2s above the unit's head, does NOT rise)
--------------------------------------------------
-- One label per unit at a time; a new action replaces the old one. The label
-- billboard is parented to the unit's own token part so it follows the unit if
-- it moves during the display window.
local actionLabels = {}  -- [unitId] = { gui = BillboardGui, token = tokenPart, expireAt = clock }

local function showActionAnnounce(unitId, label)
	local token = unitTokens[unitId]
	if not token or not token.part then return end
	if type(label) ~= "string" or label == "" then return end
	-- Remove any existing label for this unit (replace, don't stack).
	local existing = actionLabels[unitId]
	if existing and existing.gui then existing.gui:Destroy() end
	local bb = Instance.new("BillboardGui")
	bb.Name = "ActionAnnounce"
	bb.Size = UDim2.new(0, 150, 0, 26)
	bb.StudsOffset = Vector3.new(0, token.model and 4.2 or 2.6, 0)  -- above the HP bar
	bb.AlwaysOnTop = true
	bb.MaxDistance = 200
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 0.35
	lbl.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	lbl.BorderSizePixel = 0
	lbl.Font = Theme.Font.PrimaryBold
	lbl.TextSize = 16
	lbl.TextColor3 = Theme.Colors.TextGold
	lbl.TextStrokeTransparency = 0.3
	lbl.Text = label
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = lbl
	lbl.Parent = bb
	bb.Parent = token.part  -- parent last (NET-004); follows the unit token
	actionLabels[unitId] = { gui = bb, expireAt = os.clock() + 2.0 }
	-- Fade + destroy after ~2s. Guard against replacement: only destroy if still ours.
	task.delay(2.0, function()
		local cur = actionLabels[unitId]
		if cur and cur.gui == bb then
			if bb and bb.Parent then
				pcall(function()
					TweenService:Create(lbl, TweenInfo.new(0.3), { TextTransparency = 1, BackgroundTransparency = 1, TextStrokeTransparency = 1 }):Play()
				end)
			end
			task.delay(0.35, function() if bb then bb:Destroy() end end)
			actionLabels[unitId] = nil
		end
	end)
end

local function clearActionLabel(unitId)
	local existing = actionLabels[unitId]
	if existing and existing.gui then existing.gui:Destroy() end
	actionLabels[unitId] = nil
end

-- Server status summaries (TurnStarted/TurnEnded) don't carry the fallback
-- sourceIcon we learned from StatusApplied. Carry it forward so iconless-status
-- pills keep their borrowed skill/augment icon across turn ticks.
local function mergeStatusSourceIcons(unitId, newList)
	if type(newList) ~= "table" then return newList end
	local prev = unitData[unitId] and unitData[unitId].statuses
	if type(prev) == "table" then
		local byId = {}
		for _, st in ipairs(prev) do
			if st.id and (st.sourceIcon or st.sourceDesc or st.sourceDuration) then
				byId[st.id] = { icon = st.sourceIcon, desc = st.sourceDesc, dur = st.sourceDuration }
			end
		end
		for _, st in ipairs(newList) do
			local carried = st.id and byId[st.id]
			if carried then
				if not st.sourceIcon then st.sourceIcon = carried.icon end
				if not st.sourceDesc then st.sourceDesc = carried.desc end
				if not st.sourceDuration then st.sourceDuration = carried.dur end
			end
		end
	end
	return newList
end

--------------------------------------------------
-- LOOPING DEBUFF VFX (follows the unit until cured / KO)
--------------------------------------------------
-- For each unit with one or more active DEBUFFS, cycle their VFX: play one for
-- DEBUFF_VFX_PLAY seconds, wait DEBUFF_VFX_GAP, then the next (round-robin).
-- A single Heartbeat scheduler drives all units (PRF-001: no per-unit loops).
local DEBUFF_VFX_PLAY = 2.0   -- seconds each effect shows
local DEBUFF_VFX_GAP  = 0.5   -- seconds of silence between effects
local debuffLoops = {}  -- [unitId] = { ids = {statusId,...}, idx = n, nextAt = clock, active = clone }

-- Which status ids count as debuffs we should loop VFX for. Driven by the
-- status 'kind' table mirrored from GameConstants (Debuff kind only).
local DEBUFF_KINDS = nil
local function isDebuffStatus(statusId)
	if not statusId then return false end
	if DEBUFF_KINDS == nil then
		DEBUFF_KINDS = {}
		local ok, statuses = pcall(function() return GameConstants.STATUSES end)
		if ok and type(statuses) == "table" then
			for id, def in pairs(statuses) do
				if type(def) == "table" and def.kind == "Debuff" then DEBUFF_KINDS[id] = true end
			end
		end
	end
	return DEBUFF_KINDS[statusId] == true
end

-- Rebuild a unit's debuff list from unitData; start/stop its loop as needed.
local function refreshDebuffLoop(unitId)
	local ud = unitData[unitId]
	local token = unitTokens[unitId]
	local ids = {}
	if ud and ud.isAlive ~= false and ud.statuses and token then
		for _, st in ipairs(ud.statuses) do
			if st.id and isDebuffStatus(st.id) then table.insert(ids, st.id) end
		end
	end
	if #ids == 0 then
		local loop = debuffLoops[unitId]
		if loop and loop.active and loop.active.Parent then pcall(function() loop.active:Destroy() end) end
		debuffLoops[unitId] = nil
		return
	end
	local loop = debuffLoops[unitId]
	if not loop then
		debuffLoops[unitId] = { ids = ids, idx = 0, nextAt = 0, active = nil }
	else
		loop.ids = ids
		if loop.idx > #ids then loop.idx = 0 end
	end
end

-- One scheduler for all units. Advances each unit's round-robin on its own clock.
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for unitId, loop in pairs(debuffLoops) do
		local token = unitTokens[unitId]
		local ud = unitData[unitId]
		if not token or not token.part or not ud or ud.isAlive == false or #loop.ids == 0 then
			if loop.active and loop.active.Parent then pcall(function() loop.active:Destroy() end) end
			debuffLoops[unitId] = nil
		elseif now >= loop.nextAt then
			-- Stop the previous effect if still around, then play the next id.
			if loop.active and loop.active.Parent then pcall(function() loop.active:Destroy() end) end
			loop.active = nil
			loop.idx = (loop.idx % #loop.ids) + 1
			local sid = loop.ids[loop.idx]
			if VFXController then
				local assetName = VFXController.ResolveStatus and VFXController.ResolveStatus(sid) or nil
				if assetName and VFXController.PlayAsset then
					local ok, clone = pcall(VFXController.PlayAsset, assetName, token.part.Position, DEBUFF_VFX_PLAY)
					loop.active = (ok and clone) or nil
				end
				if not loop.active then pcall(VFXController.StatusBurst, token.part.Position, sid) end
			end
			-- Next effect after this one finishes plus the gap.
			loop.nextAt = now + DEBUFF_VFX_PLAY + DEBUFF_VFX_GAP
		end
	end
end)

--------------------------------------------------
-- PERSISTENT LOOP VFX (channel / guard / stance) — standalone, NOT round-robined
-- with the debuff scheduler above. Each unit can hold several keyed loops at once
-- (e.g. 'channel', 'guard', 'stance'); each plays ONE asset continuously, replayed
-- when its clone expires, until explicitly stopped by a lifecycle event.
--------------------------------------------------
local PERSIST_VFX_LIFETIME = 1.5  -- each replay lasts this long, then is replayed (user-set 1.5s Sep 28 2026)
-- persistentLoops[unitId][key] = { asset = name, nextAt = clock, active = clone }
local persistentLoops = {}

local function startPersistentLoop(unitId, key, assetName)
	if not unitId or not key or type(assetName) ~= "string" or assetName == "" then return end
	local byUnit = persistentLoops[unitId]
	if not byUnit then byUnit = {}; persistentLoops[unitId] = byUnit end
	local loop = byUnit[key]
	if loop then
		loop.asset = assetName  -- retarget in place
	else
		byUnit[key] = { asset = assetName, nextAt = 0, active = nil }
	end
end

local function stopPersistentLoop(unitId, key)
	local byUnit = persistentLoops[unitId]
	if not byUnit then return end
	local loop = byUnit[key]
	if loop then
		if loop.active and loop.active.Parent then pcall(function() loop.active:Destroy() end) end
		byUnit[key] = nil
	end
	if next(byUnit) == nil then persistentLoops[unitId] = nil end
end

local function stopAllPersistentLoops(unitId)
	local byUnit = persistentLoops[unitId]
	if not byUnit then return end
	for _, loop in pairs(byUnit) do
		if loop.active and loop.active.Parent then pcall(function() loop.active:Destroy() end) end
	end
	persistentLoops[unitId] = nil
end

-- Stance pills are client-only (synthetic id not in STATUSES) and clear by
-- dropping off the server status summary on the unit's next turn. When that
-- happens the unit has no synthetic status left, so stop its Charging loop.
local function syncStanceLoop(unitId)
	local byUnit = persistentLoops[unitId]
	if not byUnit or not byUnit["stance"] then return end
	local ud = unitData[unitId]
	local stillStance = false
	if ud and ud.statuses then
		for _, st in ipairs(ud.statuses) do
			if st.id and GameConstants.STATUSES and GameConstants.STATUSES[st.id] == nil then
				stillStance = true; break
			end
		end
	end
	if not stillStance then stopPersistentLoop(unitId, "stance") end
end

-- One scheduler for all persistent loops. Replays each asset when its clone ends;
-- keeps it glued to the unit. Independent of the debuff round-robin.
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for unitId, byUnit in pairs(persistentLoops) do
		local token = unitTokens[unitId]
		local ud = unitData[unitId]
		if not token or not token.part or not ud or ud.isAlive == false then
			stopAllPersistentLoops(unitId)
		else
			for _, loop in pairs(byUnit) do
				if now >= loop.nextAt then
					if loop.active and loop.active.Parent then pcall(function() loop.active:Destroy() end) end
					loop.active = nil
					if VFXController and VFXController.PlayAsset then
						local ok, clone = pcall(VFXController.PlayAsset, loop.asset, token.part.Position, PERSIST_VFX_LIFETIME)
						loop.active = (ok and clone) or nil
					end
					loop.nextAt = now + PERSIST_VFX_LIFETIME
				end
			end
		end
	end
end)

--------------------------------------------------
-- TIMELINE SIMULATION
--------------------------------------------------

local function simulateTurnOrder(snapshot, count, previewUnitId, previewNewRt, previewEvent)
	local units = {}
	for _, u in ipairs(snapshot) do
		table.insert(units, { id = u.id, name = u.name, side = u.side, remainingRt = u.remainingRt, isEvent = false, isActive = u.isActive or false })
		-- TWO-TIMER MODEL: the channel event sits at its REMAINING channel time
		-- (deadline minus current CT), INDEPENDENT of the caster's own RT entry above.
		-- Both entries coexist: the caster (its real RT) and the spell (its deadline).
		local chRemain = u.channelRemaining or u.channelRt
		if u.isChanneling and chRemain and chRemain > 0 then
			table.insert(units, { id = u.id.."_ch", name = (u.channeledSkillName or "Skill") .. (u.channelPhase == "Activation" and " (landing)" or ""), side = u.side, remainingRt = chRemain, isEvent = true, channeledSkillIcon = u.channeledSkillIcon, casterSide = u.side })
		end
	end
	if previewEvent then table.insert(units, { id = "pev", name = previewEvent.name, side = previewEvent.side, remainingRt = previewEvent.rt or 100, isEvent = true }) end
	if previewUnitId and previewNewRt then
		for _, u in ipairs(units) do if u.id == previewUnitId then u.remainingRt = previewNewRt; break end end
	end

	local result, elapsed = {}, 0
	local nextRound = math.ceil((currentBattleCt+1)/1000)*1000
	local roundNum = math.ceil((currentBattleCt+1)/1000)+1

	for _ = 1, count*2 do
		if #units == 0 then break end
		local minRt = math.huge
		for _, u in ipairs(units) do if u.remainingRt < minRt then minRt = u.remainingRt end end
		if minRt == math.huge then break end

		while currentBattleCt + elapsed + minRt >= nextRound and #result < count do
			table.insert(result, { name = "R"..roundNum, side = "Neutral", isRound = true, isActive = false })
			nextRound = nextRound + 1000; roundNum = roundNum + 1
		end
		elapsed = elapsed + minRt
		for _, u in ipairs(units) do u.remainingRt = u.remainingRt - minRt end

		local ready = {}
		for _, u in ipairs(units) do if u.remainingRt <= 0 then table.insert(ready, u) end end
		table.sort(ready, function(a,b) return a.id < b.id end)
		for _, u in ipairs(ready) do
			table.insert(result, { id = u.id, name = u.name, side = u.side, rt = 0, isEvent = u.isEvent, isRound = false, isActive = false, channeledSkillIcon = u.channeledSkillIcon, casterSide = u.casterSide })
			u.remainingRt = u.isEvent and 99999 or 450
			if #result >= count then break end
		end
		if #result >= count then break end
	end
	return result
end

local function updateTimeline(snapshot, previewUnitId, previewNewRt, previewEvent)
	if not snapshot or #snapshot == 0 then
		BattleHUD.UpdateTimeline({}, { phase = currentTimePhase, ctRemaining = 1000 - (currentBattleCt % 1000) })
		return
	end
	local tl = simulateTurnOrder(snapshot, 12, previewUnitId, previewNewRt, previewEvent)

	-- Build the final entries list:
	-- [1] = pinned NOW active unit
	-- [2..] = future events in RT order, including the active unit's ghost

	local finalEntries = {}

	-- Pinned NOW slot
	if activeUnitId then
		local nowName = activeUnitId
		local nowSide = "Player"
		local nowTileX, nowTileY
		if unitData[activeUnitId] then
			nowName = unitData[activeUnitId].name or activeUnitId
			nowSide = unitData[activeUnitId].side or "Player"
			nowTileX = unitData[activeUnitId].tileX
			nowTileY = unitData[activeUnitId].tileY
		elseif timelineSnapshot then
			for _, s in ipairs(timelineSnapshot) do
				if s.id == activeUnitId then nowName = s.name; nowSide = s.side; break end
			end
		end
		table.insert(finalEntries, {
			id = activeUnitId, name = nowName, side = nowSide,
			tileX = nowTileX, tileY = nowTileY,
			rt = 0, isActive = true, isGhost = false,
			isEvent = false, isRound = false,
		})
	end

	-- Remaining entries from simulation (future turns)
	local activeSeenCount = 0
	local seenUnits = {}  -- track first occurrence of each unit
	local hasPreviewRt = (previewUnitId ~= nil and previewNewRt ~= nil)
	for _, e in ipairs(tl) do
		-- Enrich with tile data for click resolution
		local enriched = {
			id = e.id, name = e.name, side = e.side, rt = e.rt,
			isActive = false, isEvent = e.isEvent or false, isRound = e.isRound or false,
			isGhost = false,
		}

		-- Active unit ghost logic:
		-- Without preview: simulation has active unit at RT=0 (current turn) + RT=450 (next).
		--   Skip 1st (duplicate of NOW), keep 2nd as ghost.
		-- With preview: simulation has active unit at RT=previewNewRt (next turn) only.
		--   Keep 1st as ghost (it's already at the correct position).
		if activeUnitId and not e.isEvent and not e.isRound and e.id == activeUnitId then
			activeSeenCount = activeSeenCount + 1
			if not hasPreviewRt and activeSeenCount == 1 then
				enriched = nil  -- current turn duplicate (no preview active)
			elseif activeSeenCount == 2 then
				enriched.isGhost = true
				enriched.rt = previewNewRt or enriched.rt
			elseif hasPreviewRt and activeSeenCount == 1 then
				enriched.isGhost = true
				enriched.rt = previewNewRt or enriched.rt
			else
				enriched = nil  -- far future, skip
			end
		end

		-- Skip duplicate appearances of non-active units (keep only first)
		if enriched and not e.isEvent and not e.isRound and not enriched.isGhost then
			if seenUnits[e.id] then
				enriched = nil
			else
				seenUnits[e.id] = true
			end
		end

		if enriched then
			-- Attach tile coordinates from unitData
			local baseId = e.id
			-- Channel events have id like "unit_ch" — extract the base unit id
			if e.isEvent and type(e.id) == "string" and string.sub(e.id, -3) == "_ch" then
				baseId = string.sub(e.id, 1, -4)
				enriched.casterId = baseId
				enriched.casterName = unitData[baseId] and unitData[baseId].name or nil
				enriched.casterSide = (unitData[baseId] and unitData[baseId].side) or e.casterSide
				enriched.channeledSkillIcon = e.channeledSkillIcon
			end
			if unitData[baseId] then
				enriched.tileX = unitData[baseId].tileX
				enriched.tileY = unitData[baseId].tileY
			end

			-- Attach RT from snapshot
			-- Don't overwrite ghost RT — it carries the simulation-computed future RT
			if not e.isRound and not e.isEvent and not enriched.isGhost and timelineSnapshot then
				for _, s in ipairs(timelineSnapshot) do
					if s.id == e.id then enriched.rt = s.remainingRt; break end
				end
			end

			table.insert(finalEntries, enriched)
		end
	end

	-- Time-of-day + CT countdown for the bar's right end. Phase + CT come from the
	-- server clock (currentTimePhase / currentBattleCt); CT counts DOWN to the next
	-- 1000-CT round boundary (where the phase flips), starting at 1000.
	local _timeInfo = { phase = currentTimePhase, ctRemaining = 1000 - (currentBattleCt % 1000) }
	BattleHUD.UpdateTimeline(finalEntries, _timeInfo)
end

--------------------------------------------------
-- ACTION BAR (builds data, tells HUD to enter ActionSelection)
--------------------------------------------------

-- Forward declaration: commitCommand is defined further below (after the
-- targeting helpers), but self-target Preview closures inside
-- enterActionSelection reference it before that point. Declaring the local
-- here ensures every closure captures the same upvalue (not a nil global).
local commitCommand

local function enterActionSelection()
	if not currentPrompt then return end
	local prompt = currentPrompt
	inputMode = nil; selectedSkill = nil; clearHighlights()

	local moveEnabled = prompt.moveCandidates and #prompt.moveCandidates > 0
	local atkEnabled = prompt.attackTargets and #prompt.attackTargets > 0
	local hasSkills = prompt.skills and #prompt.skills > 0

	local function enterSkillSelection()
		inputMode = nil; selectedSkill = nil; clearHighlights()
		local entries = {}
		for _, skill in ipairs(prompt.skills or {}) do
			local canUse = skill.canUse and (
				skill.selfTarget
				or skill.groundTarget
				or (skill.targets and #skill.targets > 0)
			)
			table.insert(entries, {
				id = skill.id, name = skill.name, mpCost = skill.mpCost or 0, rtCost = skill.rtCost or 0,
				enabled = canUse,
				onPress = function()
					-- SELF-TARGET: auto-commit immediately, no tile selection
					if skill.selfTarget then
						selectedSkill = skill; inputMode = nil; clearHighlights()
						-- Self-target skills skip tile selection, so highlight the caster's
						-- OWN tile (colored by the skill's classifier: self-buff→green,
						-- self-utility→yellow, etc.) so there's still a frame during preview.
						createTileHighlight(storedActorData.tileX or 0, storedActorData.tileY or 0, skillTargetColor(skill), 0.4)
						local skillRtCost = skill.rtCost or 60
						local isChannel = skill.channelTime and skill.channelTime > 0
						bp.skill = {
							name = skill.name, tags = table.concat(skill.tags or {}, ", "),
							mpCost = skill.mpCost, rtCost = skill.rtCost, range = skill.range,
							pattern = skill.pattern, channelTime = skill.channelTime,
							effects = skill.description or "",
						}
						bp.preview = {
							actionType = "Skill", skillName = skill.name,
							description = skill.description or "",
							actorName = prompt.unitName,
							actorMpBefore = prompt.currentMp, actorMpAfter = (prompt.currentMp or 0) - (skill.mpCost or 0),
							actorApBefore = prompt.currentAp, actorApAfter = (prompt.currentAp or 1) - 1,
							actorRtAfter = skillRtCost + (prompt.unitBaseRt or 400) + (prompt.turnRtAccrued or 0),
							targetName = prompt.unitName .. " (Self)",
							channelTime = isChannel and skill.channelTime or nil,
							onConfirm = function() commitCommand({ actionType = "Skill", skillId = skill.id, targetId = prompt.unitId }) end,
							onBack = enterSkillSelection,
						}
						bp.state = "Preview"; BattleHUD.Render(bp)
						return
					end
					selectedSkill = skill; inputMode = "skill"; clearHighlights()
					bp.skill = {
						name = skill.name, tags = table.concat(skill.tags or {}, ", "),
						mpCost = skill.mpCost, rtCost = skill.rtCost, range = skill.range,
						pattern = skill.pattern, channelTime = skill.channelTime,
						effects = skill.description or "",
					}
					local pRt = (skill.rtCost or 60) + (prompt.unitBaseRt or 400) + (prompt.turnRtAccrued or 0)
					local pEv = skill.channelTime and skill.channelTime > 0 and { name = skill.name, side = "Player", rt = skill.channelTime } or nil
					updateTimeline(timelineSnapshot, prompt.unitId, pRt, pEv)
					local c = skillTargetColor(skill)
					if skill.groundTarget then
						-- Ground targeting: highlight all tiles in range (reuse move highlight pattern)
						local gr = skill.computedRange or 5
						for dy = -gr, gr do
							for dx = -gr, gr do
								createTileHighlight((storedActorData.tileX or 0) + dx, (storedActorData.tileY or 0) + dy, c, 0.5)
							end
						end
					else
						for _, t in ipairs(skill.targets) do createTileHighlight(t.tileX, t.tileY, c, 0.5) end
					end
					storedActorData.onBack = enterSkillSelection
					bp.state = "TargetSelection"; BattleHUD.Render(bp)
				end,
			})
		end
		storedActorData.skillEntries = entries
		storedActorData.onBack = enterActionSelection
		bp.state = "SkillSelection"; BattleHUD.Render(bp)
	end

	local function enterItemSelection()
		inputMode = nil; selectedSkill = nil; selectedItem = nil; clearHighlights()
		local entries = {}
		for _, item in ipairs(prompt.consumableSlots or {}) do
			local canUse = (item.currentCharges or 0) > 0 and (
				item.selfTarget
				or item.groundTarget
				or (item.targets and #item.targets > 0)
			)
			table.insert(entries, {
				id = item.slotIndex,
				name = string.format("%s (%d/%d)", item.name, item.currentCharges or 0, item.maxCharges or 0),
				rtCost = item.rtCost or 0,
				enabled = canUse,
				onPress = function()
					-- SELF-TARGET: preview then auto-commit on self
					if item.selfTarget then
						selectedItem = item; inputMode = nil; clearHighlights()
						-- Self-target items skip tile selection, so highlight the caster's
						-- OWN tile (light green = heal/beneficial) so there's still a frame.
						createTileHighlight(storedActorData.tileX or 0, storedActorData.tileY or 0, SKILL_COLOR_HEAL, 0.4)
						bp.preview = {
							actionType = "Item",
							skillName = item.name,
							actorName = prompt.unitName,
							actorApBefore = prompt.currentAp,
							actorApAfter = (prompt.currentAp or 1) - 1,
							actorRtAfter = (item.rtCost or 80) + (prompt.unitBaseRt or 400) + (prompt.turnRtAccrued or 0),
							targetName = prompt.unitName .. " (Self)",
							isHealing = item.isHealing or false,
							description = "Item description placeholder.",
							onConfirm = function()
								commitCommand({ actionType = "Item", itemSlotIndex = item.slotIndex, targetId = prompt.unitId })
							end,
							onBack = enterItemSelection,
						}
						bp.state = "Preview"; BattleHUD.Render(bp)
						return
					end
					-- UNIT or GROUND target: enter target selection
					selectedItem = item; inputMode = "item"; clearHighlights()
					local pRt = (item.rtCost or 80) + (prompt.unitBaseRt or 400) + (prompt.turnRtAccrued or 0)
					updateTimeline(timelineSnapshot, prompt.unitId, pRt)
					-- Show the item's description panel during targeting (like skills).
					bp.skill = { name = item.name or "Item", tags = item.category or "",
						mpCost = 0, rtCost = item.rtCost or 0, range = item.range or 0,
						pattern = item.pattern or "Single", effects = "Item description placeholder." }
					local c = itemTargetColor(item)
					if item.groundTarget then
						local gr = item.range or 0
						for dy = -gr, gr do
							for dx = -gr, gr do
								createTileHighlight((storedActorData.tileX or 0) + dx, (storedActorData.tileY or 0) + dy, c, 0.5)
							end
						end
					else
						for _, t in ipairs(item.targets or {}) do createTileHighlight(t.tileX, t.tileY, c, 0.5) end
					end
					storedActorData.onBack = enterItemSelection
					bp.state = "TargetSelection"; BattleHUD.Render(bp)
				end,
			})
		end
		storedActorData.itemEntries = entries
		storedActorData.onBack = enterActionSelection
		bp.state = "ItemSelection"; BattleHUD.Render(bp)
	end

	-- 4x2 grid: Attack, Skill, Move, Item, Guard, Interact, Wait, Stance
	local actions = {
		{ id="Move", text="Move", enabled=moveEnabled, onPress=function()
			inputMode = "move"; selectedSkill = nil; clearHighlights()
			local pRt = math.round((prompt.unitBaseRt or 400)*0.0625*2) + (prompt.unitBaseRt or 400) + (prompt.turnRtAccrued or 0)
			updateTimeline(timelineSnapshot, prompt.unitId, pRt)
			for _, tile in ipairs(prompt.moveCandidates) do createTileHighlight(tile.tileX, tile.tileY, "move") end
			storedActorData.onBack = enterActionSelection
			-- Show an action description panel during targeting (like skills/attack).
			bp.skill = { name = "Move", tags = "", mpCost = 0, rtCost = 0, range = 0, pattern = "",
				effects = "Move to a highlighted tile. RT scales with distance and terrain." }
			bp.state = "TargetSelection"; BattleHUD.Render(bp)
		end },
		{ id="Commands", text="Commands", enabled=true, isSubmenu=true, subActions={
			{ id="Attack", text="Attack", enabled=atkEnabled, onPress=function()
				inputMode = "attack"; selectedSkill = nil; clearHighlights()
				bp.skill = { name="Basic Attack", tags="Physical",
					mpCost=0, rtCost=prompt.attackRt or 0, range=prompt.weaponRange or 1, pattern="Single",
					effects="Weapon Dmg: "..(prompt.weaponDamage or 0).." | RT Delay: "..(prompt.weaponRtDelay or 0) }
				local pRt = (prompt.attackRt or 80) + (prompt.unitBaseRt or 400) + (prompt.turnRtAccrued or 0)
				updateTimeline(timelineSnapshot, prompt.unitId, pRt)
				local c = SKILL_COLOR_DMG  -- basic attack = direct damage = red
				for _, t in ipairs(prompt.attackTargets) do createTileHighlight(t.tileX, t.tileY, c, 0.5) end
				storedActorData.onBack = enterActionSelection
				bp.state = "TargetSelection"; BattleHUD.Render(bp)
			end },
			{ id="Interact", text="Interact",
				enabled = (prompt.interactAvailable == true),
				onPress = function()
					inputMode = "interact"; selectedSkill = nil; clearHighlights()
					local previewRt = (prompt.unitBaseRt or 400) + (prompt.turnRtAccrued or 0)
					updateTimeline(timelineSnapshot, prompt.unitId, previewRt)
					-- Highlight every Interact candidate tile (recruit/ally/revive/object).
					for _, t in ipairs(prompt.interactTargets or {}) do
						createTileHighlight(t.tileX, t.tileY, SKILL_COLOR_UTIL, 0.45)
					end
					bp.skill = { name = "Interact", tags = "Utility", mpCost = 0,
						rtCost = 0, range = 1, pattern = "Single",
						effects = "Interact with an adjacent target: recruit a near-dead enemy, speed up an ally, revive a KO'd ally, or activate a map object." }
					storedActorData.onBack = enterActionSelection
					bp.state = "TargetSelection"; BattleHUD.Render(bp)
				end },
			{ id="Push", text="Push", enabled=#(prompt.pushTargets or {}) > 0, onPress=function()
				inputMode = "push"; selectedSkill = nil; clearHighlights()
				local previewRt = (prompt.pushRt or 40) + (prompt.unitBaseRt or 400)
				updateTimeline(timelineSnapshot, prompt.unitId, previewRt)
				for _, t in ipairs(prompt.pushTargets or {}) do
					createTileHighlight(t.tileX, t.tileY, SKILL_COLOR_UTIL, 0.45)  -- push = repositioning = yellow
				end
				bp.skill = { name = "Push", tags = "Utility", mpCost = 0, rtCost = prompt.pushRt or 40,
					range = 1, pattern = "Single", effects = "Shove an adjacent target one tile away." }
				storedActorData.onBack = enterActionSelection
				bp.state = "TargetSelection"; BattleHUD.Render(bp)
			end },
			{ id="Guard", text="Guard", enabled=not prompt.guardUsed, onPress=function()
				clearHighlights(); isPlayerTurn = false; inputMode = nil
				bp.state = "Resolving"; BattleHUD.Render(bp)
				BattleHUD.AddLogEntry((prompt.unitName or "Unit") .. " guards.")
				BattleEvents.PlayerCommand:FireServer({ actionType = "Guard" })
			end },
		}},
		{ id="Skill", text="Skills", enabled=hasSkills, onPress=enterSkillSelection },
		{ id="Item", text="Items", enabled=(prompt.consumableSlots and #prompt.consumableSlots > 0), onPress=enterItemSelection },
		{ id="Wait", text="Wait", enabled=true, onPress=function()
			clearHighlights(); isPlayerTurn = false; inputMode = nil
			bp.state = "Resolving"; BattleHUD.Render(bp)
			BattleHUD.AddLogEntry((prompt.unitName or "Unit") .. " waits.")
			BattleEvents.PlayerCommand:FireServer({ actionType = "Wait" })
		end },
	}

	-- Get actor tile info
	local actorUnit = unitData[prompt.unitId]
	local actorTileX = actorUnit and actorUnit.tileX or 0
	local actorTileY = actorUnit and actorUnit.tileY or 0
	local actorElev = getElevation(actorTileX, actorTileY)

	storedActorData = {
		id = prompt.unitId, name = prompt.unitName, side = prompt.unitSide or "Player",
		currentHp = prompt.currentHp, maxHp = prompt.maxHp,
		currentMp = prompt.currentMp, maxMp = prompt.maxMp,
		currentAp = prompt.currentAp, maxAp = prompt.maxAp or 2,
		remainingRt = (prompt.unitBaseRt or 400) + (prompt.turnRtAccrued or 0),
		doctrine = prompt.doctrine or "",
		level = prompt.level,
		race = prompt.race or nil,
		tileX = actorTileX, tileY = actorTileY, elevation = actorElev,
		statuses = actorUnit and actorUnit.statuses or {},
		actions = actions,
	}
	bp.actor = storedActorData
	bp.skill = nil
	bp.target = nil
	bp.preview = nil

	bp.state = "ActionSelection"; BattleHUD.Render(bp)
	-- Pass base RT so ghost shows where unit will be if they end turn now
	updateTimeline(timelineSnapshot, prompt.unitId, (prompt.unitBaseRt or 400) + (prompt.turnRtAccrued or 0))
end

--------------------------------------------------
-- TILE SELECTION
--------------------------------------------------

local mapFolder = workspace:FindFirstChild("TemplateViewerMap")  -- nil until quest map renders; updated in MapDataSync handler

-- Find the invisible tile Part for a given battle coordinate.
-- Used by Highlight-based tile indicators (no floating Parts needed).
local function getTilePart(bx, by)
	if not mapFolder then return nil end
	local tx, ty = bx + BATTLE_OFFSET_X, by + BATTLE_OFFSET_Y
	local name = string.format("Tile_%02d_%02d", tx, ty)
	return mapFolder:FindFirstChild(name)
end


local function getTileUnderMouse()
	-- Click-pads first: thin invisible pads coincident with tile highlights.
	-- They do not occlude neighbors, so the pad hit is the tile the player
	-- sees under the cursor (removes elevation parallax offset).
	local cam0 = workspace.CurrentCamera
	if cam0 and TileHL then
		local padFolder = TileHL.GetPadFolder()
		if padFolder then
			local rpp = RaycastParams.new()
			rpp.FilterType = Enum.RaycastFilterType.Include
			rpp.FilterDescendantsInstances = { padFolder }
			local ray0 = cam0:ScreenPointToRay(mouse.X, mouse.Y)
			local pres = workspace:Raycast(ray0.Origin, ray0.Direction * 500, rpp)
			if pres and pres.Instance then return pres.Instance end
		end
	end
	local target = mouse.Target
	if target and target:IsA("BasePart") and target:GetAttribute("IsTemplateTile") then return target end
	-- Fallback: mouse hit terrain voxels, grid lines, highlight walls, or a
	-- non-tile Part. Use camera:ScreenPointToRay with Include filter for ONLY
	-- tile Parts (not the whole mapFolder — grid lines are also in there and
	-- would intercept the ray before reaching tiles).
	local cam = workspace.CurrentCamera
	if cam and mapFolder then
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Include
		local tileParts = {}
		for _, c in ipairs(mapFolder:GetChildren()) do
			if c:IsA("BasePart") and c:GetAttribute("IsTemplateTile") then table.insert(tileParts, c) end
		end
		rp.FilterDescendantsInstances = tileParts
		local ray = cam:ScreenPointToRay(mouse.X, mouse.Y)
		local res = workspace:Raycast(ray.Origin, ray.Direction * 500, rp)
		return res and res.Instance or nil
	end
	return nil
end

local function tileToBattle(part)
	if not part then return nil, nil end
	local x, y = part:GetAttribute("X"), part:GetAttribute("Y")
	if x and y then return templateToBattle(x, y) end
	return nil, nil
end

--------------------------------------------------
-- COMMIT + CANCEL
--------------------------------------------------

-- Assigns into the forward-declared `commitCommand` local (see above).
function commitCommand(command)
	clearHighlights(); isPlayerTurn = false; inputMode = nil; selectedSkill = nil; selectedItem = nil; aimTarget = nil
	bp.state = "Resolving"; BattleHUD.Render(bp)
	BattleEvents.PlayerCommand:FireServer(command)
end

local function cancelToTargeting()
	aimTarget = nil
	bp.target = nil
	bp.preview = nil
	-- Re-highlight valid targets
	if inputMode == "move" then
		clearHighlights()
		for _, tile in ipairs(currentPrompt.moveCandidates) do createTileHighlight(tile.tileX, tile.tileY, "move") end
	elseif inputMode == "attack" then
		clearHighlights()
		for _, t in ipairs(currentPrompt.attackTargets) do createTileHighlight(t.tileX, t.tileY, "target") end
	elseif inputMode == "skill" and selectedSkill then
		clearHighlights()
		local c = skillTargetColor(selectedSkill)
		if selectedSkill.groundTarget then
			-- Ground skills (e.g. Meteor Marker) highlight a RANGE box around the
			-- caster, not the .targets marker — mirror enterSkillSelection so back-out
			-- re-shows the range instead of just the caster tile.
			local gr = selectedSkill.computedRange or 5
			for dy = -gr, gr do
				for dx = -gr, gr do
					createTileHighlight((storedActorData.tileX or 0) + dx, (storedActorData.tileY or 0) + dy, c, 0.5)
				end
			end
		else
			for _, t in ipairs(selectedSkill.targets) do createTileHighlight(t.tileX, t.tileY, c, 0.5) end
		end
	elseif inputMode == "item" and selectedItem then
		clearHighlights()
		local c = itemTargetColor(selectedItem)
		if selectedItem.groundTarget then
			local gr = selectedItem.range or 0
			for dy = -gr, gr do
				for dx = -gr, gr do
					createTileHighlight((storedActorData.tileX or 0) + dx, (storedActorData.tileY or 0) + dy, c, 0.5)
				end
			end
		else
			for _, t in ipairs(selectedItem.targets or {}) do createTileHighlight(t.tileX, t.tileY, c, 0.5) end
		end
	elseif inputMode == "interact" then
		clearHighlights()
		for _, t in ipairs(currentPrompt.interactTargets or {}) do createTileHighlight(t.tileX, t.tileY, SKILL_COLOR_UTIL, 0.45) end
	elseif inputMode == "push" then
		clearHighlights()
		for _, t in ipairs(currentPrompt.pushTargets or {}) do createTileHighlight(t.tileX, t.tileY, SKILL_COLOR_UTIL, 0.45) end
	elseif inputMode == "push_distance" and pushTargetSel then
		clearHighlights()
		createTileHighlight(pushTargetSel.tileX, pushTargetSel.tileY, "selected")
		for _, lt in ipairs(pushLandingTiles or {}) do createTileHighlight(lt.tileX, lt.tileY, SKILL_COLOR_UTIL, 0.45) end
	end
	bp.state = "TargetSelection"; BattleHUD.Render(bp)
end

--------------------------------------------------
-- CLICK HANDLER
--------------------------------------------------


local function processTileClick(bx, by)

	-- During deployment: allow tile inspection but skip combat flow.
	-- BattleHUD view mode provides tile + object info during placement.

	-- Find occupant for tile info
	local occupantName = nil
	for uid, data in pairs(unitData) do
		if data.tileX == bx and data.tileY == by and data.isAlive ~= false then
			occupantName = data.name
			break
		end
	end

	-- Always update tile info
	local terrainId = GameConstants.GetTerrainId(bx, by)
	local elevation = getElevation(bx, by)
	local moveCost = GameConstants.GetTerrainCost(bx, by)
	-- Look up map object at this tile
	local objectName = GameConstants.GetObjectAt(bx, by)

	bp.tile = {
		x = bx,
		y = by,
		terrainName = terrainId,
		elevation = elevation,
		moveCost = moveCost,
		coords = string.format("(%d, %d)", bx, by),
		occupantName = occupantName,
		objectName = objectName,
		effect = (_G.CTRBLXAI_GetTileEffect and _G.CTRBLXAI_GetTileEffect(bx, by)) or nil,
	}
	BattleHUD.Render(bp)
	
	-- Inspect unit by clicking — works in ALL states.
	-- KO'd units stay inspectable. Gather EVERY unit on the tile (alive first,
	-- then KO'd, stable by id) so the inspector can cycle between them.
	local clickedUnit = false
	local tileUnits = {}
	for uid, data in pairs(unitData) do
		if data.tileX == bx and data.tileY == by then
			table.insert(tileUnits, data)
		end
	end
	table.sort(tileUnits, function(a, b)
		local aAlive = a.isAlive ~= false
		local bAlive = b.isAlive ~= false
		if aAlive ~= bAlive then return aAlive end
		return tostring(a.id) < tostring(b.id)
	end)
	local primary = tileUnits[1]
	if primary then
		clickedUnit = true
		-- Combat targeting still keys off the LIVING occupant only.
		if primary.isAlive ~= false then
			bp.inspectedEntityId = primary.id
			bp.target = primary
			BattleHUD.Render(bp)
		else
			-- Only KO'd units here: drop any stale selection from an earlier click.
			bp.inspectedEntityId = nil
		end
		-- Open full inspector during: Idle, View mode, or Deployment phase
		local hudState = BattleHUD.GetState()
		local canInspect = (hudState == "Idle") or (hudState == "EnemyTurn")
			or BattleHUD.IsViewMode()
			or _G.CTRBLXAI_DeploymentActive
		if canInspect and _G.CTRBLXAI_OpenInspectorPanel then
			local ids = {}
			for _, u in ipairs(tileUnits) do table.insert(ids, u.id) end
			_G.CTRBLXAI_OpenInspectorPanel(primary.id, ids)
		end
	end
	-- F1 fix (2026-10-04): clicking an EMPTY tile clears the stale unit selection so
	-- the newest click decides the dev-tool target (bp.tile holds the clicked tile).
	if not clickedUnit then
		bp.inspectedEntityId = nil
	end
	-- Map object inspection: an object tile with no unit on it opens the object inspector.
	if not clickedUnit and objectName and objectName ~= "None" then
		local hudStateObj = BattleHUD.GetState()
		local canInspectObj = (hudStateObj == "Idle") or (hudStateObj == "EnemyTurn") or BattleHUD.IsViewMode() or _G.CTRBLXAI_DeploymentActive
		if canInspectObj and _G.CTRBLXAI_OpenObjectInspector then
			_G.CTRBLXAI_OpenObjectInspector(objectName, bx, by)
		end
	end
	
	-- View mode or deployment: tile + unit info updated above, skip combat flow
	if BattleHUD.IsViewMode() then return end
	if _G.CTRBLXAI_DeploymentActive then return end

	if not isPlayerTurn or not inputMode then return end
	
	local state = bp.state
	
	-- If in Preview state, clicking elsewhere cancels back to targeting
	if state == "Preview" then
		cancelToTargeting()
		return
	end
	
	-- TargetSelection: find valid target
	if state == "TargetSelection" then
		if inputMode == "move" then
			for _, tile in ipairs(currentPrompt.moveCandidates) do
				if tile.tileX == bx and tile.tileY == by then
					aimTarget = tile
				-- Keep move-range highlights, layer path on top
				-- Mark the selected destination tile as "selected" (yellow)
				-- so it stands out from the blue move-range tiles
				createTileHighlight(bx, by, "selected")
					clearMovePath()
					renderMovePath(tile.path, bx, by)
					-- Build path hazard list for preview panel
					local pathHazards = {}
					for _, step in ipairs(tile.path or {}) do
						local h = PATH_HAZARDS[step.terrain]
						if h then
							table.insert(pathHazards, {
								tileX = step.tileX, tileY = step.tileY,
								terrain = step.terrain, warn = h.warn,
							})
						end
					end
					-- Also check destination terrain
					local destH = PATH_HAZARDS[tile.terrain]
					if destH then
						table.insert(pathHazards, { tileX = bx, tileY = by, terrain = tile.terrain, warn = destH.warn })
					end
					local moveRt = tile.pathCost or 0
					bp.preview = {
						actionType = "Move",
						actorName = currentPrompt.unitName,
						fromTile = string.format("(%d,%d)", storedActorData.tileX or 0, storedActorData.tileY or 0),
						toTile = string.format("(%d,%d)", bx, by),
						destTerrain = tile.terrain or "Clear",
						pathLength = #(tile.path or {}) + 1,
						pathHazards = pathHazards,
						actorApBefore = currentPrompt.currentAp, actorApAfter = (currentPrompt.currentAp or 1) - 1,
						actorRtAfter = moveRt + (currentPrompt.unitBaseRt or 400) + (currentPrompt.turnRtAccrued or 0),
						onConfirm = function() commitCommand({ actionType = "Move", tileX = bx, tileY = by, pathCost = tile.pathCost }) end,
						onBack = function() clearMovePath(); cancelToTargeting() end,
					}
					bp.state = "Preview"; BattleHUD.Render(bp)
					return
				end
			end
		elseif inputMode == "attack" then
			for _, t in ipairs(currentPrompt.attackTargets) do
				if t.tileX == bx and t.tileY == by then
					aimTarget = t; clearHighlights()
					createTileHighlight(bx, by, "selected")
					bp.target = unitData[t.id]
					local tgtData = unitData[t.id]
					bp.preview = {
						actionType = "Attack",
						actorName = currentPrompt.unitName,
						actorMpBefore = currentPrompt.currentMp, actorMpAfter = currentPrompt.currentMp, -- no MP cost
						actorApBefore = currentPrompt.currentAp, actorApAfter = (currentPrompt.currentAp or 1) - 1,
						actorRtAfter = (currentPrompt.attackRt or 80) + (currentPrompt.unitBaseRt or 400) + (currentPrompt.turnRtAccrued or 0),
						targetName = t.name,
						targetHpBefore = tgtData and tgtData.currentHp or 0,
						targetHpAfter = tgtData and math.max(0, (tgtData.currentHp or 0) - (t.predicted or 0)) or 0,
						estimatedDamage = t.predicted or 0,
						targetRtDelay = GameConstants.CalcRtDelayResistance(currentPrompt.weaponRtDelay or 0, tgtData and tgtData.stats and tgtData.stats.VIT or 10),
						statusEffect = "None",
						onConfirm = function() commitCommand({ actionType = "Attack", targetId = t.id }) end,
						onBack = cancelToTargeting,
					}
					bp.state = "Preview"; BattleHUD.Render(bp)
					return
				end
			end
		elseif inputMode == "skill" and selectedSkill then
			-- GROUND TARGETING: any tile click in range is valid
			if selectedSkill.groundTarget then
				local gr = selectedSkill.computedRange or 5
				local actX = storedActorData.tileX or 0
				local actY = storedActorData.tileY or 0
				local dist = math.max(math.abs(bx - actX), math.abs(by - actY))
				if dist <= gr then
					aimTarget = { tileX = bx, tileY = by }; clearHighlights()
					createTileHighlight(bx, by, "selected")
					local skillRtCost = selectedSkill.rtCost or 60
					local isChannel = selectedSkill.channelTime and selectedSkill.channelTime > 0
					bp.preview = {
						actionType = "Skill",
						skillName = selectedSkill.name,
						skillTags = bp.skill and bp.skill.tags or nil,
						actorName = currentPrompt.unitName,
						actorMpBefore = currentPrompt.currentMp,
						actorMpAfter = (currentPrompt.currentMp or 0) - (selectedSkill.mpCost or 0),
						actorApBefore = currentPrompt.currentAp,
						actorApAfter = (currentPrompt.currentAp or 1) - 1,
						actorRtAfter = skillRtCost + (currentPrompt.unitBaseRt or 400) + (currentPrompt.turnRtAccrued or 0),
						targetName = string.format("Ground (%d,%d)", bx, by),
						channelTime = isChannel and selectedSkill.channelTime or nil,
						channelResolveCt = isChannel and (currentBattleCt or 0) + (selectedSkill.channelTime or 0) or nil,
						onConfirm = function()
							commitCommand({ actionType = "Skill", skillId = selectedSkill.id, tileX = bx, tileY = by })
						end,
						onBack = cancelToTargeting,
					}
					bp.state = "Preview"; BattleHUD.Render(bp)
					return
				end
			end
			-- UNIT TARGETING: match clicked tile to a candidate unit
			for _, t in ipairs(selectedSkill.targets or {}) do
				if t.tileX == bx and t.tileY == by then
					aimTarget = t; clearHighlights()
					-- CHARGE skills (damage + movement): keep the TARGET tile in the
					-- skill's damage color (red), highlight the server-computed LANDING
					-- tile in yellow, and draw the straight charge PATH in the white/
					-- blooming move-path visual. Non-charge skills keep the plain
					-- yellow 'selected' confirmation highlight on the target.
					if selectedSkill.isCharge and t.landingTileX then
						-- Draw the white charge PATH first (its destination paints the
						-- landing tile gold), THEN overpaint the landing tile yellow and
						-- the target tile red — so those two win the in-place recolor.
						if t.chargePath then renderMovePath(t.chargePath, t.landingTileX, t.landingTileY) end
						createTileHighlight(t.landingTileX, t.landingTileY, "selected")     -- landing = yellow (last = wins)
						createTileHighlight(bx, by, skillTargetColor(selectedSkill), 0.4)  -- target stays red
					else
						createTileHighlight(bx, by, "selected")
					end
					bp.target = unitData[t.id]
					local statusEff = selectedSkill.appliesStatus or "None"
					local statusDur = 0
					if statusEff ~= "None" and GameConstants.STATUSES and GameConstants.STATUSES[statusEff] then
						statusDur = GameConstants.STATUSES[statusEff].duration or 0
					end
					local isHeal = (t.predType == "healing")
					local tgtData = unitData[t.id]
					local tgtHpBefore = tgtData and tgtData.currentHp or 0
					local tgtMaxHp = tgtData and tgtData.maxHp or tgtHpBefore
					local tgtHpAfter
					if isHeal then
						tgtHpAfter = math.min(tgtMaxHp, tgtHpBefore + (t.predicted or 0))
					else
						tgtHpAfter = math.max(0, tgtHpBefore - (t.predicted or 0))
					end
					local skillRtCost = selectedSkill.rtCost or 60
					local isChannel = selectedSkill.channelTime and selectedSkill.channelTime > 0
					bp.preview = {
						actionType = "Skill",
						skillName = selectedSkill.name,
						skillTags = bp.skill and bp.skill.tags or nil,
						actorName = currentPrompt.unitName,
						actorMpBefore = currentPrompt.currentMp,
						actorMpAfter = (currentPrompt.currentMp or 0) - (selectedSkill.mpCost or 0),
						actorApBefore = currentPrompt.currentAp,
						actorApAfter = (currentPrompt.currentAp or 1) - 1,
						actorRtAfter = skillRtCost + (currentPrompt.unitBaseRt or 400) + (currentPrompt.turnRtAccrued or 0),
						targetName = t.name,
						targetHpBefore = tgtHpBefore,
						targetHpAfter = tgtHpAfter,
						estimatedDamage = t.predicted or 0,
						isHealing = isHeal,
						targetRtDelay = (not isHeal) and GameConstants.CalcRtDelayResistance(currentPrompt.weaponRtDelay or 0, tgtData and tgtData.stats and tgtData.stats.VIT or 10) or 0,
						statusEffect = statusEff,
						statusDuration = statusDur,
						channelTime = isChannel and selectedSkill.channelTime or nil,
						channelResolveCt = isChannel and (currentBattleCt or 0) + (selectedSkill.channelTime or 0) or nil,
						onConfirm = function()
							commitCommand({ actionType = "Skill", skillId = selectedSkill.id, targetId = t.id })
						end,
						onBack = cancelToTargeting,
					}
					bp.state = "Preview"; BattleHUD.Render(bp)
					return
				end
			end

		elseif inputMode == "interact" then
			-- Click an Interact candidate tile → Preview → commit. One stage:
			-- the server re-validates the kind + target and dispatches the native.
			for _, t in ipairs(currentPrompt.interactTargets or {}) do
				if t.tileX == bx and t.tileY == by then
					aimTarget = t; clearHighlights()
					createTileHighlight(bx, by, "selected")
					if t.id then bp.target = unitData[t.id] end
					local desc
					if t.interactKind == "recruitEnemy" then
						desc = "Recruit " .. (t.name or "enemy") .. " — becomes a neutral ally."
					elseif t.interactKind == "allyRtHelp" then
						desc = "Aid " .. (t.name or "ally") .. " — cut their current RT by 35%."
					elseif t.interactKind == "reviveAlly" then
						desc = "Resuscitate " .. (t.name or "ally") .. " (channeled) — revives at low HP."
					elseif t.interactKind == "mapObject" then
						desc = "Activate " .. (t.name or "object") .. "."
					else
						desc = "Interact with " .. (t.name or "target") .. "."
					end
					bp.preview = {
						actionType = "Interact",
						actorName = currentPrompt.unitName,
						actorApBefore = currentPrompt.currentAp, actorApAfter = (currentPrompt.currentAp or 1) - 1,
						actorRtAfter = (t.rtPreview or 0) + (currentPrompt.unitBaseRt or 400) + (currentPrompt.turnRtAccrued or 0),
						targetName = t.name,
						description = desc,
						onConfirm = function()
							commitCommand({
								actionType = "Interact",
								interactKind = t.interactKind,
								targetId = t.id,
								objectId = t.objectId,
							})
						end,
						onBack = cancelToTargeting,
					}
					bp.state = "Preview"; BattleHUD.Render(bp)
					return
				end
			end

		elseif inputMode == "push" then
			-- Stage 1: choose push TARGET. Then enter distance sub-stage (pick stop tile 1..max).
			for _, t in ipairs(currentPrompt.pushTargets or {}) do
				if t.tileX == bx and t.tileY == by then
					pushTargetSel = t
					local actX = storedActorData and storedActorData.tileX or currentPrompt.tileX or 0
					local actY = storedActorData and storedActorData.tileY or currentPrompt.tileY or 0
					pushLandingTiles = computePushLandingTiles(actX, actY, t.tileX, t.tileY, t.maxPushDistance or 0)
					if #pushLandingTiles == 0 then
						-- No reachable clear tile (blocked/resisted). Preserve legacy: commit full push.
						aimTarget = t; clearHighlights()
						createTileHighlight(bx, by, "selected")
						bp.target = unitData[t.id]
						bp.preview = {
							actionType = "Push",
							actorName = currentPrompt.unitName,
							actorApBefore = currentPrompt.currentAp, actorApAfter = (currentPrompt.currentAp or 1) - 1,
							actorRtAfter = (currentPrompt.pushRt or 40) + (currentPrompt.unitBaseRt or 400) + (currentPrompt.turnRtAccrued or 0),
							targetName = t.name,
							description = "Push " .. (t.name or "target") .. " (blocked — collision)",
							onConfirm = function() commitCommand({ actionType = "Push", targetId = t.id }) end,
							onBack = cancelToTargeting,
						}
						bp.state = "Preview"; BattleHUD.Render(bp)
						return
					end
					-- Enter distance sub-stage: highlight the target + legal landing tiles.
					inputMode = "push_distance"
					clearHighlights()
					createTileHighlight(t.tileX, t.tileY, "selected")
					for _, lt in ipairs(pushLandingTiles) do
						createTileHighlight(lt.tileX, lt.tileY, SKILL_COLOR_UTIL, 0.45)
					end
					bp.state = "TargetSelection"; BattleHUD.Render(bp)
					return
				end
			end
		elseif inputMode == "push_distance" and pushTargetSel then
			-- Stage 2: choose the STOP tile along the fixed away-ray (distance 1..max).
			for _, lt in ipairs(pushLandingTiles or {}) do
				if lt.tileX == bx and lt.tileY == by then
					local t = pushTargetSel
					local chosenDist = lt.distance
					aimTarget = t; clearHighlights()
					createTileHighlight(t.tileX, t.tileY, "selected")
					createTileHighlight(bx, by, SKILL_COLOR_UTIL, 0.25)
					bp.target = unitData[t.id]
					bp.preview = {
						actionType = "Push",
						actorName = currentPrompt.unitName,
						actorApBefore = currentPrompt.currentAp, actorApAfter = (currentPrompt.currentAp or 1) - 1,
						actorRtAfter = (currentPrompt.pushRt or 40) + (currentPrompt.unitBaseRt or 400) + (currentPrompt.turnRtAccrued or 0),
						targetName = t.name,
						description = string.format("Push %s %d tile%s away", t.name or "target", chosenDist, chosenDist == 1 and "" or "s"),
						onConfirm = function() commitCommand({ actionType = "Push", targetId = t.id, pushDistance = chosenDist }) end,
						onBack = function()
							inputMode = "push"; pushLandingTiles = nil; pushTargetSel = nil
							cancelToTargeting()
						end,
					}
					bp.state = "Preview"; BattleHUD.Render(bp)
					return
				end
			end
		elseif inputMode == "item" and selectedItem then
			-- GROUND TARGETING: any tile click in range is valid
			if selectedItem.groundTarget then
				local gr = selectedItem.range or 0
				local actX = storedActorData.tileX or 0
				local actY = storedActorData.tileY or 0
				local dist = math.max(math.abs(bx - actX), math.abs(by - actY))
				if dist <= gr then
					aimTarget = { tileX = bx, tileY = by }; clearHighlights()
					createTileHighlight(bx, by, "selected")
					bp.preview = {
						actionType = "Item",
						skillName = selectedItem.name,
						actorName = currentPrompt.unitName,
						actorApBefore = currentPrompt.currentAp,
						actorApAfter = (currentPrompt.currentAp or 1) - 1,
						actorRtAfter = (selectedItem.rtCost or 80) + (currentPrompt.unitBaseRt or 400) + (currentPrompt.turnRtAccrued or 0),
						targetName = string.format("Ground (%d,%d)", bx, by),
						description = "Item description placeholder.",
						onConfirm = function()
							commitCommand({ actionType = "Item", itemSlotIndex = selectedItem.slotIndex, tileX = bx, tileY = by })
						end,
						onBack = cancelToTargeting,
					}
					bp.state = "Preview"; BattleHUD.Render(bp)
					return
				end
			end
			-- UNIT TARGETING: match clicked tile to a candidate unit
			for _, t in ipairs(selectedItem.targets or {}) do
				if t.tileX == bx and t.tileY == by then
					aimTarget = t; clearHighlights()
					createTileHighlight(bx, by, "selected")
					bp.target = unitData[t.id]
					local tgtData = unitData[t.id]
					bp.preview = {
						actionType = "Item",
						skillName = selectedItem.name,
						actorName = currentPrompt.unitName,
						actorApBefore = currentPrompt.currentAp,
						actorApAfter = (currentPrompt.currentAp or 1) - 1,
						actorRtAfter = (selectedItem.rtCost or 80) + (currentPrompt.unitBaseRt or 400) + (currentPrompt.turnRtAccrued or 0),
						targetName = t.name,
						isHealing = selectedItem.isHealing or false,
						description = "Item description placeholder.",
						onConfirm = function()
							commitCommand({ actionType = "Item", itemSlotIndex = selectedItem.slotIndex, targetId = t.id })
						end,
						onBack = cancelToTargeting,
					}
					bp.state = "Preview"; BattleHUD.Render(bp)
					return
				end
			end
		end
	end
end


-- TILE SELECTION: Mouse (immediate on click) + Touch (deferred to tap intent)
UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	-- Guard: ignore clicks consumed by GUI buttons/panels
	if gameProcessedEvent then return end
	-- Only handle MOUSE left click here. Touch is handled by tap intent below.
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

	-- Additional guard: check if mouse is over a visible HUD panel
	if CameraController.IsOverUI(input.Position) then return end

	local tilePart = getTileUnderMouse()
	local bx, by = tileToBattle(tilePart)
	if not bx then return end

	processTileClick(bx, by)
end)

--------------------------------------------------
-- TOUCH TAP POLLING
-- Checks each frame for a completed tap from CameraController.
-- On tap, raycasts from the tap screen position to find a tile.
--------------------------------------------------

game:GetService("RunService").Heartbeat:Connect(function()
	local tapPos = CameraController.ConsumeTapIntent()
	if not tapPos then return end

	-- Raycast from tap position to find tile
	local cam = workspace.CurrentCamera
	if not cam then return end
	local ray = cam:ScreenPointToRay(tapPos.X, tapPos.Y)
	-- Click-pads first (parallax-immune); fall back to tile Parts.
	if TileHL then
		local padFolder = TileHL.GetPadFolder()
		if padFolder then
			local rpp = RaycastParams.new()
			rpp.FilterType = Enum.RaycastFilterType.Include
			rpp.FilterDescendantsInstances = { padFolder }
			local pres = workspace:Raycast(ray.Origin, ray.Direction * 500, rpp)
			if pres and pres.Instance then
				local pbx, pby = tileToBattle(pres.Instance)
				if pbx then processTileClick(pbx, pby); return end
			end
		end
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	local tileParts = {}
	if mapFolder then
		for _, c in ipairs(mapFolder:GetChildren()) do
			if c:IsA("BasePart") and c:GetAttribute("IsTemplateTile") then
				table.insert(tileParts, c)
			end
		end
	end
	rayParams.FilterDescendantsInstances = tileParts
	local result = workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)
	local tilePart = result and result.Instance or nil
	if not tilePart then return end

	local bx, by = tileToBattle(tilePart)
	if not bx then return end

	processTileClick(bx, by)
end)

--------------------------------------------------
-- HOVER TOOLTIP (shows unit name/HP on mouse hover)
--------------------------------------------------

local lastHoveredUnitId = nil

game:GetService("RunService").RenderStepped:Connect(function()
	if not next(unitData) then
		if lastHoveredUnitId then
			lastHoveredUnitId = nil
			BattleHUD.HideTooltip()
		end
		return
	end

	-- Check what tile is under the mouse
	local tilePart = getTileUnderMouse()
	if not tilePart then
		if lastHoveredUnitId then
			lastHoveredUnitId = nil
			BattleHUD.HideTooltip()
		end
		return
	end

	local bx, by = tileToBattle(tilePart)
	if not bx then
		if lastHoveredUnitId then
			lastHoveredUnitId = nil
			BattleHUD.HideTooltip()
		end
		return
	end

	-- Find unit on this tile
	local hoveredUnit = nil
	for _, data in pairs(unitData) do
		if data.tileX == bx and data.tileY == by and data.isAlive ~= false then
			hoveredUnit = data
			break
		end
	end

	if hoveredUnit then
		-- Don't show tooltip for the unit we're already inspecting
		if hoveredUnit.id == bp.inspectedEntityId then
			if lastHoveredUnitId then
				lastHoveredUnitId = nil
				BattleHUD.HideTooltip()
			end
			return
		end
		if hoveredUnit.id ~= lastHoveredUnitId then
			lastHoveredUnitId = hoveredUnit.id
			local hpText = string.format("HP %d/%d", hoveredUnit.currentHp or 0, hoveredUnit.maxHp or 0)
			local mpText = string.format("MP %d/%d", hoveredUnit.currentMp or 0, hoveredUnit.maxMp or 0)
			local sideColor = hoveredUnit.side == "Player" and Theme.Colors.Success or Theme.Colors.Danger
			local tooltipLines = {
				{ text = hpText, color = Theme.Colors.TextPrimary },
				{ text = mpText, color = Theme.Colors.TextSecondary },
			}
			-- Add status effects
			if hoveredUnit.statuses and #hoveredUnit.statuses > 0 then
				local statusParts = {}
				for _, s in ipairs(hoveredUnit.statuses) do
					local name = s.id or s.name or "?"
					local turns = s.remainingTurns and ("(" .. s.remainingTurns .. ")") or ""
					table.insert(statusParts, name .. turns)
				end
				table.insert(tooltipLines, { text = table.concat(statusParts, " "), color = Theme.Colors.Warning })
			end
			BattleHUD.ShowTooltip({
				title = hoveredUnit.name or "Unit",
				portrait = string.sub(hoveredUnit.name or "?", 1, 2),
				portraitColor = sideColor,
				lines = tooltipLines,
				position = UDim2.new(0, mouse.X + 16, 0, mouse.Y - 10),
				anchorPoint = Vector2.new(0, 1),
				maxWidth = 160,
			})
		end
	else
		if lastHoveredUnitId then
			lastHoveredUnitId = nil
			BattleHUD.HideTooltip()
		end
	end
end)


--------------------------------------------------
-- DEV OPTIONS PANEL (temporary, remove when Slice 7 UI provides buttons)
-- Visible only during battle. Blocks input across its bounds.
--------------------------------------------------

local devCameraPanel = nil
local devPanelConnections = {} -- F-A: input connections to disconnect on destroy/recreate
local devSelectedTile = nil -- {x, y} for Kill Unit targeting

local function createDevCameraPanel()
	if not RunService:IsStudio() then return end
	if devCameraPanel then devCameraPanel:Destroy() end
	-- F-A: clear any connections from a prior panel instance (recreated on BattleStarted
	-- and on MapDataSync/Regenerate) so UserInputService listeners don't pile up.
	for _, conn in ipairs(devPanelConnections) do
		if conn then conn:Disconnect() end
	end
	table.clear(devPanelConnections)

	local gui = Instance.new("ScreenGui")
	gui.Name = "DevOptions"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 95
	gui.Parent = player:WaitForChild("PlayerGui")
	devCameraPanel = gui

	local devExpanded = false
	local dragMoved = false -- F-B: true while a real title-bar drag is happening
	local PANEL_W = 184

	-- Root frame (draggable via the title bar). Not a ScrollingFrame itself; the
	-- scrolling body lives inside so the header/selection line stay pinned.
	local root = Instance.new("Frame")
	root.Name = "DevPanel"
	root.Size = UDim2.fromOffset(PANEL_W, 16)
	root.Position = UDim2.new(0, 130, 0, 4)
	root.AnchorPoint = Vector2.new(0, 0)
	root.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
	root.BackgroundTransparency = 0.05
	root.BorderSizePixel = 0
	root.Active = true
	root.ClipsDescendants = true
	root.Parent = gui
	Instance.new("UICorner", root).CornerRadius = UDim.new(0, 6)
	local rootStroke = Instance.new("UIStroke", root)
	rootStroke.Color = Color3.fromRGB(200, 200, 50); rootStroke.Thickness = 1

	-- Title bar (drag handle + expand/collapse toggle).
	local title = Instance.new("TextButton")
	title.Name = "TitleBar"
	title.Size = UDim2.new(1, 0, 0, 16)
	title.Position = UDim2.new(0, 0, 0, 0)
	title.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
	title.BackgroundTransparency = 0.2
	title.Font = Enum.Font.SourceSansBold; title.TextSize = 10
	title.TextColor3 = Color3.fromRGB(200, 200, 50)
	title.Text = "> DEV  (drag)"; title.AutoButtonColor = false
	title.BorderSizePixel = 0; title.Parent = root
	Instance.new("UICorner", title).CornerRadius = UDim.new(0, 6)

	-- Selection line: shows what the tools will act on (updated on demand).
	local selLabel = Instance.new("TextLabel")
	selLabel.Name = "SelectionLine"
	selLabel.Size = UDim2.new(1, -6, 0, 14)
	selLabel.Position = UDim2.new(0, 3, 0, 17)
	selLabel.BackgroundTransparency = 1
	selLabel.Font = Enum.Font.SourceSans; selLabel.TextSize = 10
	selLabel.TextColor3 = Color3.fromRGB(150, 220, 150)
	selLabel.TextXAlignment = Enum.TextXAlignment.Left
	selLabel.Text = "Sel: (none)"; selLabel.Visible = false
	selLabel.Parent = root

	-- Scrolling body holds all the groups/controls.
	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.Size = UDim2.new(1, 0, 1, -32)
	body.Position = UDim2.new(0, 0, 0, 32)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Active = true
	body.CanvasSize = UDim2.new(0, 0, 0, 0)
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollBarThickness = 4
	body.ScrollBarImageColor3 = Color3.fromRGB(200, 200, 50)
	body.ScrollingDirection = Enum.ScrollingDirection.Y
	body.ScrollingEnabled = false
	body.Visible = false
	body.Parent = root
	local bodyLayout = Instance.new("UIListLayout", body)
	bodyLayout.Padding = UDim.new(0, 2)
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	local bodyPad = Instance.new("UIPadding", body)
	bodyPad.PaddingTop = UDim.new(0, 3); bodyPad.PaddingLeft = UDim.new(0, 3)
	bodyPad.PaddingRight = UDim.new(0, 3); bodyPad.PaddingBottom = UDim.new(0, 3)

	-- selection resolver (shared by all action buttons) + live label refresh.
	local function selectedTile()
		local iid = bp and bp.inspectedEntityId
		local idata = iid and unitData[iid]
		if idata and idata.tileX and idata.tileY then
			return idata.tileX, idata.tileY, idata
		end
		if bp and bp.tile and bp.tile.x and bp.tile.y then
			return bp.tile.x, bp.tile.y, nil
		end
		return nil
	end
	local function refreshSelLabel()
		local tx, ty, idata = selectedTile()
		if not tx then
			selLabel.Text = "Sel: (none - click a tile/unit)"
		elseif idata then
			selLabel.Text = string.format("Sel: %s @ (%d,%d)", idata.name or "unit", tx, ty)
		else
			selLabel.Text = string.format("Sel: tile (%d,%d)", tx, ty)
		end
	end

	-------------------------------------------------------------
	-- Group infrastructure: a header that expands/collapses its rows.
	-------------------------------------------------------------
	local groups = {}       -- name -> { header, container, open }
	local orderCounter = 0
	local function nextOrder() orderCounter = orderCounter + 1; return orderCounter end

	local function addGroup(name, color)
		local header = Instance.new("TextButton")
		header.Size = UDim2.new(1, 0, 0, 18)
		header.BackgroundColor3 = color or Color3.fromRGB(55, 55, 72)
		header.BackgroundTransparency = 0.15
		header.Font = Enum.Font.SourceSansBold; header.TextSize = 11
		header.TextColor3 = Color3.fromRGB(230, 230, 170)
		header.Text = "+ " .. name
		header.LayoutOrder = nextOrder()
		header.BorderSizePixel = 0; header.Parent = body
		Instance.new("UICorner", header).CornerRadius = UDim.new(0, 4)

		local container = Instance.new("Frame")
		container.Name = name .. "_rows"
		container.Size = UDim2.new(1, 0, 0, 0)
		container.AutomaticSize = Enum.AutomaticSize.Y
		container.BackgroundTransparency = 1
		container.LayoutOrder = nextOrder()
		container.Visible = false
		container.Parent = body
		local cl = Instance.new("UIListLayout", container)
		cl.Padding = UDim.new(0, 2); cl.SortOrder = Enum.SortOrder.LayoutOrder

		local g = { header = header, container = container, open = false }
		header.MouseButton1Click:Connect(function()
			g.open = not g.open
			container.Visible = g.open
			header.Text = (g.open and "- " or "+ ") .. name
		end)
		groups[name] = g
		return g
	end

	local function makeBtn(parent, text, callback, color)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, 22)
		btn.BackgroundColor3 = color or Color3.fromRGB(50, 50, 65)
		btn.BackgroundTransparency = 0.2
		btn.Font = Enum.Font.SourceSans; btn.TextSize = 11
		btn.TextColor3 = Color3.fromRGB(220, 220, 220)
		btn.Text = text; btn.LayoutOrder = nextOrder()
		btn.BorderSizePixel = 0; btn.Parent = parent
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
		btn.MouseButton1Click:Connect(callback)
		return btn
	end

	-- Tap-twice-to-confirm wrapper for destructive buttons.
	local function makeConfirmBtn(parent, text, callback, color)
		local armed = false
		local btn
		btn = makeBtn(parent, text, function()
			if not armed then
				armed = true
				btn.Text = "CONFIRM? " .. text
				btn.BackgroundColor3 = Color3.fromRGB(120, 90, 20)
				task.delay(2.5, function()
					if armed and btn and btn.Parent then
						armed = false
						btn.Text = text
						btn.BackgroundColor3 = color or Color3.fromRGB(80, 30, 30)
					end
				end)
			else
				armed = false
				btn.Text = text
				btn.BackgroundColor3 = color or Color3.fromRGB(80, 30, 30)
				callback()
			end
		end, color)
		return btn
	end

	-------------------------------------------------------------
	-- Dropdown: a button that opens a scrollable, searchable list.
	-- onPick(value) fires on selection. Returns { get = fn, setItems = fn }.
	-------------------------------------------------------------
	local openDropdown = nil  -- only one open at a time
	local function makeDropdown(parent, labelPrefix, items, onPick)
		local state = { items = items, value = items[1], prefix = labelPrefix }

		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, 22)
		btn.BackgroundColor3 = Color3.fromRGB(58, 48, 68)
		btn.BackgroundTransparency = 0.15
		btn.Font = Enum.Font.SourceSans; btn.TextSize = 11
		btn.TextColor3 = Color3.fromRGB(225, 220, 235)
		btn.Text = labelPrefix .. ": " .. tostring(state.value)
		btn.LayoutOrder = nextOrder()
		btn.BorderSizePixel = 0; btn.Parent = parent
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

		-- The list popup is parented to the ScreenGui (floats above body), positioned
		-- under the button each time it opens.
		local pop = Instance.new("Frame")
		pop.Name = "Dropdown"
		pop.Size = UDim2.fromOffset(PANEL_W - 8, 190)
		pop.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
		pop.BorderSizePixel = 0
		pop.Visible = false
		pop.ZIndex = 50
		pop.Parent = gui
		Instance.new("UICorner", pop).CornerRadius = UDim.new(0, 4)
		local ps = Instance.new("UIStroke", pop); ps.Color = Color3.fromRGB(200, 200, 50); ps.Thickness = 1

		local search = Instance.new("TextBox")
		search.Size = UDim2.new(1, -6, 0, 20)
		search.Position = UDim2.new(0, 3, 0, 3)
		search.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
		search.Font = Enum.Font.SourceSans; search.TextSize = 11
		search.TextColor3 = Color3.fromRGB(230, 230, 230)
		search.PlaceholderText = "search..."
		search.Text = ""; search.ClearTextOnFocus = false
		search.ZIndex = 51; search.BorderSizePixel = 0; search.Parent = pop
		Instance.new("UICorner", search).CornerRadius = UDim.new(0, 3)

		local listScroll = Instance.new("ScrollingFrame")
		listScroll.Size = UDim2.new(1, -6, 1, -27)
		listScroll.Position = UDim2.new(0, 3, 0, 25)
		listScroll.BackgroundTransparency = 1
		listScroll.BorderSizePixel = 0
		listScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		listScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		listScroll.ScrollBarThickness = 4
		listScroll.ZIndex = 51
		listScroll.Parent = pop
		local lsl = Instance.new("UIListLayout", listScroll)
		lsl.Padding = UDim.new(0, 1); lsl.SortOrder = Enum.SortOrder.LayoutOrder

		local function closePop()
			pop.Visible = false
			if openDropdown == pop then openDropdown = nil end
		end

		local function rebuild(filter)
			for _, c in ipairs(listScroll:GetChildren()) do
				if c:IsA("TextButton") then c:Destroy() end
			end
			filter = (filter or ""):lower()
			for _, item in ipairs(state.items) do
				if filter == "" or tostring(item):lower():find(filter, 1, true) then
					local row = Instance.new("TextButton")
					row.Size = UDim2.new(1, 0, 0, 18)
					row.BackgroundColor3 = Color3.fromRGB(44, 44, 56)
					row.BackgroundTransparency = 0.2
					row.Font = Enum.Font.SourceSans; row.TextSize = 11
					row.TextColor3 = Color3.fromRGB(225, 225, 225)
					row.Text = tostring(item)
					row.ZIndex = 52; row.BorderSizePixel = 0; row.Parent = listScroll
					row.MouseButton1Click:Connect(function()
						state.value = item
						btn.Text = labelPrefix .. ": " .. tostring(item)
						closePop()
						if onPick then onPick(item) end
					end)
				end
			end
		end

		search:GetPropertyChangedSignal("Text"):Connect(function()
			rebuild(search.Text)
		end)

		btn.MouseButton1Click:Connect(function()
			if pop.Visible then closePop(); return end
			if openDropdown and openDropdown ~= pop then openDropdown.Visible = false end
			-- position under the button (absolute coords)
			local ap = btn.AbsolutePosition
			local sz = btn.AbsoluteSize
			pop.Position = UDim2.fromOffset(ap.X, ap.Y + sz.Y + 2)
			search.Text = ""
			rebuild("")
			pop.Visible = true
			openDropdown = pop
		end)

		return {
			get = function() return state.value end,
			setItems = function(newItems)
				state.items = newItems
				state.value = newItems[1]
				btn.Text = labelPrefix .. ": " .. tostring(state.value)
			end,
		}
	end

	-------------------------------------------------------------
	-- GROUP: Battle (destructive actions guarded)
	-------------------------------------------------------------
	local gBattle = addGroup("BATTLE", Color3.fromRGB(60, 50, 45))
	makeConfirmBtn(gBattle.container, "INSTANT WIN", function()
		BattleEvents.DevCommand:FireServer({ action = "InstantWin" })
	end, Color3.fromRGB(30, 80, 30))
	makeConfirmBtn(gBattle.container, "INSTANT LOSE", function()
		BattleEvents.DevCommand:FireServer({ action = "InstantLose" })
	end, Color3.fromRGB(80, 30, 30))
	makeConfirmBtn(gBattle.container, "KILL AT TILE", function()
		local iid = bp and bp.inspectedEntityId
		local idata = iid and unitData[iid]
		if idata and idata.tileX and idata.tileY then
			BattleEvents.DevCommand:FireServer({ action = "KillAtTile", tileX = idata.tileX, tileY = idata.tileY })
		else
			warn("[Dev] No unit selected -- click a unit first, then KILL AT TILE")
		end
	end, Color3.fromRGB(80, 50, 20))
	makeConfirmBtn(gBattle.container, "DELETE SAVE", function()
		BattleEvents.DevCommand:FireServer({ action = "DeleteSave" })
	end, Color3.fromRGB(80, 20, 20))
	makeBtn(gBattle.container, "SAVE NOW", function()
		BattleEvents.DevCommand:FireServer({ action = "SaveNow" })
	end, Color3.fromRGB(30, 60, 80))

	-------------------------------------------------------------
	-- GROUP: Map
	-------------------------------------------------------------
	local gMap = addGroup("MAP", Color3.fromRGB(45, 60, 45))
	makeBtn(gMap.container, "VIEW: TERRAIN", function()
		BattleEvents.DevCommand:FireServer({ action = "ViewMode", mode = "TERRAIN" })
	end, Color3.fromRGB(40, 70, 40))
	makeBtn(gMap.container, "VIEW: REGION", function()
		BattleEvents.DevCommand:FireServer({ action = "ViewMode", mode = "REGION" })
	end, Color3.fromRGB(40, 50, 70))
	makeBtn(gMap.container, "VIEW: TEMPLATE", function()
		BattleEvents.DevCommand:FireServer({ action = "ViewMode", mode = "TEMPLATE" })
	end, Color3.fromRGB(60, 50, 50))
	local biomeList = { "Plains","Forest","Desert","Swamp","Highlands","Tundra","Volcano","Cave","Ruins","Castle","Corrupted" }
	local templateList = { "T01","T02","T03","T04","T05","T06","T07","T08" }
	local biomeDd = makeDropdown(gMap.container, "BIOME", biomeList, nil)
	local tmplDd = makeDropdown(gMap.container, "TMPL", templateList, nil)
	makeBtn(gMap.container, "REGENERATE MAP", function()
		BattleEvents.DevCommand:FireServer({ action = "Regenerate", biome = biomeDd.get(), template = tmplDd.get() })
	end, Color3.fromRGB(80, 60, 20))

	-------------------------------------------------------------
	-- GROUP: Status
	-------------------------------------------------------------
	local gStatus = addGroup("STATUS", Color3.fromRGB(58, 48, 68))
	local statusList = {
		"Burn","Poison","Venom","Bleed","Wounded","Raptured","Slow","Haste","Frozen","Wet",
		"Blind","Confuse","Silence","Mute","Disarmed","Pinned","Crippled","Petrify","Sleep",
		"Stun","Guard","Blessed","Cursed","Enlightened","Flight","Rush","Weakened","Hide",
		"Regeneration","Recharge","Overflow","Mana Burn","Drowning","Sinking","Frenzy",
		"Giant Transformation","Rally","Spell Focus","Battle Rage","Rune Ward","CounterStance",
	}
	local statusDd = makeDropdown(gStatus.container, "STATUS", statusList, nil)
	makeBtn(gStatus.container, "APPLY STATUS", function()
		local tx, ty = selectedTile()
		if not tx then warn("[Dev] Select a unit first, then APPLY STATUS") return end
		BattleEvents.DevCommand:FireServer({ action = "GrantStatus", tileX = tx, tileY = ty, statusId = statusDd.get() })
	end, Color3.fromRGB(50, 70, 50))
	makeBtn(gStatus.container, "CLEAR STATUSES", function()
		local tx, ty = selectedTile()
		if not tx then warn("[Dev] Select a unit first") return end
		BattleEvents.DevCommand:FireServer({ action = "RemoveStatus", tileX = tx, tileY = ty, statusId = "ALL" })
	end, Color3.fromRGB(70, 50, 50))
	local weatherList = {
		"Clear","Rain","Heatwave","Strong Wind","Snow Storm","Thunderstorm","Severe Hail",
		"Dark Eclipse","Holy Aurora","Mana Storm","Meteor Storm","Volcanic Eruptions",
		"Earthquake","Hunger Virus","Wild Growth",
	}
	local weatherDd = makeDropdown(gStatus.container, "WX", weatherList, nil)
	makeBtn(gStatus.container, "SET WEATHER", function()
		BattleEvents.DevCommand:FireServer({ action = "SetWeather", condition = weatherDd.get() })
	end, Color3.fromRGB(40, 60, 75))

	-------------------------------------------------------------
	-- GROUP: Spawn
	-------------------------------------------------------------
	local gSpawn = addGroup("SPAWN", Color3.fromRGB(45, 60, 55))
	local sideList = { "Enemy", "Neutral", "Player" }
	local tierList = { "Grunt", "Veteran", "Elite" }
	local sideDd = makeDropdown(gSpawn.container, "SIDE", sideList, nil)
	local tierDd = makeDropdown(gSpawn.container, "TIER", tierList, nil)
	makeBtn(gSpawn.container, "SPAWN AT TILE", function()
		local tx, ty = selectedTile()
		if not tx then warn("[Dev] Select a tile/unit first, then SPAWN AT TILE") return end
		BattleEvents.DevCommand:FireServer({ action = "SpawnUnit", tileX = tx, tileY = ty, side = sideDd.get(), tier = tierDd.get() })
	end, Color3.fromRGB(40, 65, 55))
	makeBtn(gSpawn.container, "SPAWN GROUP (x3)", function()
		local tx, ty = selectedTile()
		if not tx then warn("[Dev] Select a tile/unit first") return end
		BattleEvents.DevCommand:FireServer({ action = "SpawnGroup", tileX = tx, tileY = ty, side = sideDd.get(), tier = tierDd.get(), count = 3 })
	end, Color3.fromRGB(45, 60, 50))

	-- Object spawn: category dropdown drives the object dropdown's items.
	local objCats = {
		{ cat = "Siege",       items = { "Ballista", "Catapult", "Ice Spike", "Stone Pillar" } },
		{ cat = "Hazard",      items = { "Bear Trap", "Spike Trap", "Snare Trap", "Land Mine", "Bomb Barrel", "Oil Sluice", "Steam Valve" } },
		{ cat = "Exploration", items = { "Treasure Chest", "Mimic", "Cursed Chest", "Healing Spring", "Magic Spring", "Campfire", "Blood Fountain", "Astrolabe", "Potion Desk", "Crystal Ball", "Eye of the Magi", "Black Market" } },
		{ cat = "Aura",        items = { "War Banner", "Cursed Statue", "Rally Flag", "Star Axis", "Burning Cauldron", "War Horn", "Runed Boulder" } },
		{ cat = "Event",       items = { "Idol of Fortune", "Fountain of Fortune", "Tavern", "Necro Tome Stand", "Cover of Darkness", "Dragon Utopia", "Chaos Statue", "Angel Statue", "Obelisk", "Forge", "Witch Hut", "Mysterious Boulder", "Glow Crystal", "Pandora's Box", "Swan Pond" } },
	}
	local catNames = {}
	for _, c in ipairs(objCats) do catNames[#catNames + 1] = c.cat end
	local objDd  -- forward ref
	local catDd = makeDropdown(gSpawn.container, "OBJ CAT", catNames, function(picked)
		for _, c in ipairs(objCats) do
			if c.cat == picked and objDd then objDd.setItems(c.items) end
		end
	end)
	objDd = makeDropdown(gSpawn.container, "OBJ", objCats[1].items, nil)
	makeBtn(gSpawn.container, "SPAWN OBJECT", function()
		local tx, ty = selectedTile()
		if not tx then warn("[Dev] Select a tile first, then SPAWN OBJECT") return end
		BattleEvents.DevCommand:FireServer({ action = "SpawnObject", tileX = tx, tileY = ty, objectType = objDd.get() })
	end, Color3.fromRGB(70, 60, 40))

	-------------------------------------------------------------
	-- Expand / collapse (title) + viewport height cap
	-------------------------------------------------------------
	title.MouseButton1Click:Connect(function()
		-- F-B: a click that ended a real drag must NOT toggle the panel.
		if dragMoved then dragMoved = false; return end
		devExpanded = not devExpanded
		if devExpanded then
			local cam = workspace.CurrentCamera
			local vpY = (cam and cam.ViewportSize and cam.ViewportSize.Y) or 760
			local h = math.min(560, math.floor(vpY * 0.85))
			root.Size = UDim2.fromOffset(PANEL_W, h)
			title.Text = "v DEV OPTIONS  (drag)"
			selLabel.Visible = true
			body.Visible = true
			body.ScrollingEnabled = true
			refreshSelLabel()
		else
			root.Size = UDim2.fromOffset(PANEL_W, 16)
			title.Text = "> DEV  (drag)"
			selLabel.Visible = false
			body.Visible = false
			body.ScrollingEnabled = false
			if openDropdown then openDropdown.Visible = false; openDropdown = nil end
		end
	end)

	-- Refresh the selection line whenever the pointer is pressed anywhere (cheap,
	-- so the "Sel:" line tracks the latest tile/unit click without polling).
	devPanelConnections[#devPanelConnections + 1] = UserInputService.InputBegan:Connect(function(input, gp)
		if not devExpanded then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			task.defer(refreshSelLabel)
		end
	end)

	-------------------------------------------------------------
	-- Dragging: drag the title bar to move the whole panel.
	-------------------------------------------------------------
	do
		local dragging = false
		local dragStart, startPos
		title.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				dragMoved = false  -- F-B: reset; set true only if the pointer actually moves
				dragStart = input.Position
				startPos = root.Position
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then dragging = false end
				end)
			end
		end)
		devPanelConnections[#devPanelConnections + 1] = UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch) then
				local delta = input.Position - dragStart
				if math.abs(delta.X) + math.abs(delta.Y) > 4 then dragMoved = true end  -- F-B: real drag
				root.Position = UDim2.new(
					startPos.X.Scale, startPos.X.Offset + delta.X,
					startPos.Y.Scale, startPos.Y.Offset + delta.Y)
			end
		end)
	end
end

local function destroyDevCameraPanel()
	-- F-A: disconnect input listeners so they don't accumulate across battles/regenerates.
	for _, conn in ipairs(devPanelConnections) do
		if conn then conn:Disconnect() end
	end
	table.clear(devPanelConnections)
	if devCameraPanel then devCameraPanel:Destroy(); devCameraPanel = nil end
end

--------------------------------------------------
-- EVENT HANDLERS
--------------------------------------------------

-- TILE-EFFECT VFX: server broadcasts TileEffectApplied/Removed (Burning, Poison Cloud...).
-- Show a persistent VFX on the tile while the effect lasts (VFXRegistry.ByTileEffect).
local activeTileEffects: {[string]: string} = {}  -- "x,y" -> effectId (for tile inspector)
BattleEvents.TileEffectApplied.OnClientEvent:Connect(function(data)
	if data and data.tileX and data.tileY then activeTileEffects[`{data.tileX},{data.tileY}`] = data.effectId end
	if not (VFXController and VFXController.SetTileEffect and data and data.tileX and data.tileY) then return end
	local pos = tileToWorldGrounded(data.tileX, data.tileY) - Vector3.new(0, 0.9, 0)
	pcall(VFXController.SetTileEffect, data.tileX, data.tileY, data.effectId, pos)
end)

BattleEvents.TileEffectRemoved.OnClientEvent:Connect(function(data)
	if data and data.tileX and data.tileY then activeTileEffects[`{data.tileX},{data.tileY}`] = nil end
	if not (VFXController and VFXController.ClearTileEffect and data and data.tileX and data.tileY) then return end
	pcall(VFXController.ClearTileEffect, data.tileX, data.tileY)
end)

_G.CTRBLXAI_GetTileEffect = function(x, y) return activeTileEffects[`{x},{y}`] end

BattleEvents.BattleStarted.OnClientEvent:Connect(function(data)
	if SoundController then SoundController.StopAllChannels() end
	if VFXController and VFXController.ClearAllTileEffects then pcall(VFXController.ClearAllTileEffects) end
	table.clear(activeTileEffects)
	if BattleHUD.SetActiveEvent then BattleHUD.SetActiveEvent(nil) end
	-- Supply playable battlefield bounds to camera (8×8 battle grid)
	-- NOTE: Future procedural maps must supply these dynamically.
	CameraController.SetBattlefieldBounds({
		minX = MAP_OFFSET_X,
		maxX = MAP_OFFSET_X + MAP_WIDTH * TILE_SIZE,
		minZ = MAP_OFFSET_Z,
		maxZ = MAP_OFFSET_Z + MAP_HEIGHT * TILE_SIZE,
		tileSize = TILE_SIZE,
		source = "battle_client",
	})

	-- Enter battle control mode (disable default controls, hide character)
	-- Pass center of battle grid as initial focus
	local centerX = MAP_OFFSET_X + (MAP_WIDTH * TILE_SIZE) / 2
	local centerZ = MAP_OFFSET_Z + (MAP_HEIGHT * TILE_SIZE) / 2
	CameraController.EnterBattle(Vector3.new(centerX, 0, centerZ))

	-- Collapse TemplateInspector panels during battle
	if type(_G.CTRBLXAI_SetInspectorCollapsed) == "function" then
		_G.CTRBLXAI_SetInspectorCollapsed(true)
	end

	createDevCameraPanel()

	BattleHUD.Cleanup()
	bp = { state = "Idle", actor = nil, target = nil, skill = nil, preview = nil, tile = nil, inspectedEntityId = nil }
	for _, c in ipairs(visualFolder:GetChildren()) do c:Destroy() end
	unitTokens = {}; unitData = {}; elevationMap = data.elevationMap
	for _, l in pairs(actionLabels) do if l.gui then l.gui:Destroy() end end
	actionLabels = {}
	for _, lp in pairs(debuffLoops) do if lp.active and lp.active.Parent then pcall(function() lp.active:Destroy() end) end end
	debuffLoops = {}
	for uid in pairs(persistentLoops) do stopAllPersistentLoops(uid) end
	persistentLoops = {}
	for _, unit in ipairs(data.units) do
		unitData[unit.id] = unit; spawnToken(unit)
		updateHpBar(unit.id, unit.currentHp, unit.maxHp)
		updateMpBar(unit.id, unit.currentMp or 0, unit.maxMp or 0)
	end
	-- VFX: init post-processing + clear stale highlights
	local mf = workspace:FindFirstChild("TemplateViewerMap")
	local biome = mf and mf:GetAttribute("BiomeId") or "Plains"
	if VFXController then pcall(VFXController.Init, biome); pcall(VFXController.ClearAllHighlights) end
end)

-- Reinforcement: a single unit entered the battle mid-fight. Build its token
-- the same way BattleStarted does per unit, so it renders identically.
BattleEvents.UnitSpawned.OnClientEvent:Connect(function(data)
	local unit = data and data.unit
	if not unit or not unit.id then return end
	if unitTokens[unit.id] then return end  -- already present; ignore duplicate
	unitData[unit.id] = unit
	spawnToken(unit)
	updateHpBar(unit.id, unit.currentHp, unit.maxHp)
	updateMpBar(unit.id, unit.currentMp or 0, unit.maxMp or 0)
	if orientUnitToFacing and unit.facing then
		pcall(orientUnitToFacing, unit.id, unit.facing)
	end
end)

-- Time cycle: receive the current time-of-day phase (Dawn/Day/Dusk/Night).
-- currentTimePhase declared earlier (near currentBattleCt) so updateTimeline can read it.
BattleEvents.TimePhaseChanged.OnClientEvent:Connect(function(data)
	local phase = data and data.phase
	if not phase then return end
	currentTimePhase = phase
	print("[BattleVisualClient] Time phase: " .. tostring(phase))
end)

-- DRAMATIC BATTLEFIELD-EVENT BANNER: a center-screen announcement that slides in,
-- scale-punches, holds ~2s, then fades. Fired by the server when a battlefield
-- event triggers (BattlefieldEventAnnounced). Visual-only. Reuses its own
-- ScreenGui so it layers above the HUD and never disturbs other panels.
local _eventBannerGui = nil
local function showEventBanner(eventName)
	if type(eventName) ~= "string" or eventName == "" then return end
	-- Tear down any prior banner so rapid events don't stack.
	if _eventBannerGui then _eventBannerGui:Destroy(); _eventBannerGui = nil end

	local gui = Instance.new("ScreenGui")
	gui.Name = "BattlefieldEventBanner"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100   -- above the HUD
	gui.Parent = player:WaitForChild("PlayerGui")
	_eventBannerGui = gui

	-- Dim behind the banner (brief, subtle).
	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.ZIndex = 1
	dim.Parent = gui

	-- Center banner container (slides in + scale-punch).
	local banner = Instance.new("Frame")
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.42)
	banner.Size = UDim2.fromScale(0.0, 0.14)   -- start collapsed; tween to full width
	banner.BackgroundColor3 = Theme.Colors.Background or Color3.fromRGB(20, 20, 24)
	banner.BackgroundTransparency = 0.15
	banner.BorderSizePixel = 0
	banner.ZIndex = 2
	banner.Parent = gui
	Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 6)

	-- Gold accent bars top + bottom.
	local accentTop = Instance.new("Frame")
	accentTop.Size = UDim2.new(1, 0, 0, 3)
	accentTop.Position = UDim2.fromScale(0, 0)
	accentTop.BackgroundColor3 = Theme.Colors.TextGold or Color3.fromRGB(230, 190, 90)
	accentTop.BorderSizePixel = 0
	accentTop.ZIndex = 3
	accentTop.Parent = banner
	local accentBot = accentTop:Clone()
	accentBot.Position = UDim2.new(0, 0, 1, -3)
	accentBot.Parent = banner

	-- Event name text.
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 1)
	title.BackgroundTransparency = 1
	title.Font = Theme.Font.PrimaryBold
	title.TextScaled = true
	title.TextColor3 = Theme.Colors.TextGold or Color3.fromRGB(235, 205, 120)
	title.TextStrokeColor3 = Color3.new(0, 0, 0)
	title.TextStrokeTransparency = 0.2
	title.Text = string.upper(eventName)
	title.TextTransparency = 1
	title.ZIndex = 4
	title.Parent = banner
	local titlePad = Instance.new("UIPadding", title)
	titlePad.PaddingLeft = UDim.new(0, 24); titlePad.PaddingRight = UDim.new(0, 24)
	titlePad.PaddingTop = UDim.new(0, 8); titlePad.PaddingBottom = UDim.new(0, 8)
	local titleConstraint = Instance.new("UITextSizeConstraint", title)
	titleConstraint.MaxTextSize = 48

	-- Animate: dim in, banner slide/scale open, text fade in; hold; then fade out.
	TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 0.5 }):Play()
	TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(0.6, 0.14) }):Play()
	task.delay(0.15, function()
		if title and title.Parent then
			TweenService:Create(title, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
		end
	end)

	-- Hold ~2s, then fade everything and clean up.
	task.delay(2.2, function()
		if not (gui and gui.Parent) then return end
		TweenService:Create(dim, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(title, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
		task.delay(0.45, function()
			if gui then gui:Destroy() end
			if _eventBannerGui == gui then _eventBannerGui = nil end
		end)
	end)
end

BattleEvents.BattlefieldEventAnnounced.OnClientEvent:Connect(function(data)
	if data and BattleHUD.SetActiveEvent then BattleHUD.SetActiveEvent(data.eventName) end
	local name = data and data.eventName
	if not name or data.quiet then return end
	showEventBanner(name)
end)

-- Weather/crisis: receive the active condition (one combined slot, per round).
-- Stored for display; a visible weather label / VFX is a follow-up.
local currentWeather = "Clear"
BattleEvents.WeatherChanged.OnClientEvent:Connect(function(data)
	local cond = data and data.condition
	if not cond then return end
	currentWeather = cond
	if BattleHUD.SetWeather then BattleHUD.SetWeather(cond) end
	print("[BattleVisualClient] Weather: " .. tostring(cond))
end)

BattleEvents.TurnStarted.OnClientEvent:Connect(function(data)
	activeUnitId = data.unitId
	bp.inspectedEntityId = nil  -- new turn resets inspection
	-- VFX: highlight active unit (gold outline)
	local _at = unitTokens[data.unitId]
	if _at and VFXController then pcall(VFXController.SetActiveUnit, data.unitId, _at.part) end
	-- Camera: auto-focus on unit taking its turn. For AI (Enemy) turns, lock a
	-- fixed isometric view for the whole turn; the player's chosen zoom/view is
	-- captured and restored when their own turn begins (PlayerTurnPrompt).
	local _side = unitData[data.unitId] and unitData[data.unitId].side or "Player"
	if _at then
		if _side ~= "Player" then
			CameraController.BeginScriptedView()
			CameraController.ScriptedFocus(_at.part.Position)
		else
			CameraController.FocusActiveUnit(_at.part.Position)
		end
	end
	if unitData[data.unitId] then
		unitData[data.unitId].statuses = mergeStatusSourceIcons(data.unitId, data.statuses)
		syncStanceLoop(data.unitId)
		refreshDebuffLoop(data.unitId)
		-- Clear Guard buff (expires on new turn) and restore token color
		if unitData[data.unitId].isGuarding then
			unitData[data.unitId].isGuarding = false
			local token = unitTokens[data.unitId]
			if token and not token.model then token.part.Color = Theme.GetSideColor(unitData[data.unitId].side) end
			-- Remove Guard from visible statuses
			for i, s in ipairs(unitData[data.unitId].statuses or {}) do
				if s.id == "Guard" then table.remove(unitData[data.unitId].statuses, i); break end
			end
		end
		if data.currentMp then unitData[data.unitId].currentMp = data.currentMp
			updateMpBar(data.unitId, data.currentMp, data.maxMp or unitData[data.unitId].maxMp or 0) end
	end
	if data.allUnitsRt and #data.allUnitsRt > 0 then
		timelineSnapshot = data.allUnitsRt; updateTimeline(data.allUnitsRt, nil, nil)
	end
	local token = unitTokens[data.unitId]
	if token then token.label.TextColor3 = unitNameColor(unitData[data.unitId], true) end
	showSelectionRing(data.unitId)
	-- Enemy / neutral turn: keep the unit panel up and show the ACTIVE unit instead of
	-- hiding it. Player turns are handled by PlayerTurnPrompt (full action data).
	local _u = unitData[data.unitId]
	if _u and _u.side ~= "Player" and not BattleHUD.IsViewMode() then
		bp.actor = {
			id = _u.id, name = _u.name, side = _u.side,
			currentHp = _u.currentHp, maxHp = _u.maxHp,
			currentMp = data.currentMp or _u.currentMp, maxMp = data.maxMp or _u.maxMp,
			currentAp = _u.currentAp, maxAp = _u.maxAp or 2,
			remainingRt = _u.remainingRt,
			doctrine = _u.doctrine or "", level = _u.level, race = _u.race,
			tileX = _u.tileX, tileY = _u.tileY,
			elevation = getElevation(_u.tileX or 0, _u.tileY or 0),
			statuses = _u.statuses or {},
			actions = {},
		}
		bp.skill = nil; bp.target = nil; bp.preview = nil
		bp.state = "EnemyTurn"
		BattleHUD.Render(bp)
	end
end)

BattleEvents.TurnOrderUpdate.OnClientEvent:Connect(function(data)
	if not data then return end
	if data.units and #data.units > 0 then
		timelineSnapshot = data.units
		if data.currentCt then currentBattleCt = data.currentCt end
		if not aimTarget and (not isPlayerTurn or not inputMode) then updateTimeline(data.units, nil, nil) end
	end
end)

BattleEvents.PlayerTurnPrompt.OnClientEvent:Connect(function(prompt)
	if SoundController then SoundController.PlayTurnChime() end
	currentPrompt = prompt
	activeUnitId = prompt.unitId
	-- Exit view mode so the action panel renders correctly.
	-- Without this, Render returns early and the action buttons never appear.
	if BattleHUD.IsViewMode() then
		BattleHUD.ToggleViewMode()
	end
	timelineSnapshot = prompt.timeline
	if prompt.currentCt then currentBattleCt = prompt.currentCt end
	isPlayerTurn = true; inputMode = nil; selectedSkill = nil
	CameraController.EndScriptedView()  -- restore the player's last chosen zoom + view
	enterActionSelection()
end)

BattleEvents.UnitMoved.OnClientEvent:Connect(function(data)
	local token = unitTokens[data.unitId]; if not token then return end
	if SoundController then SoundController.PlayMove() end
	if unitData[data.unitId] then unitData[data.unitId].tileX = data.tileX; unitData[data.unitId].tileY = data.tileY end
	if token.model then
		-- R15 model: handle elevation changes with arc tween
		local destPos = tileToWorldR15Grounded(data.tileX, data.tileY, token.hipHeight)
		local currentPos = token.part.Position
		local dir = (destPos - currentPos) * Vector3.new(1, 0, 1)  -- XZ only
		local lookCF = if dir.Magnitude > 0.1
			then CFrame.lookAt(destPos, destPos + dir)
			else CFrame.new(destPos)

		-- If elevation changes, arc over terrain: rise → travel → land
		local elevDiff = math.abs(destPos.Y - currentPos.Y)
		if elevDiff > 0.5 then
			local peakY = math.max(currentPos.Y, destPos.Y) + 1.5
			local midXZ = (currentPos + destPos) / 2
			local riseCF = CFrame.lookAt(
				Vector3.new(currentPos.X, peakY, currentPos.Z),
				Vector3.new(destPos.X, peakY, destPos.Z))
			-- Rise (fast)
			TweenService:Create(token.part, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame = riseCF}):Play()
			-- Travel + land (after rise)
			task.delay(0.15, function()
				if token.part and token.part.Parent then
					TweenService:Create(token.part, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame = lookCF}):Play()
				end
			end)
		else
			-- Flat movement: simple tween
			TweenService:Create(token.part, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {CFrame = lookCF}):Play()
		end
		-- Play walk animation during tween.
		-- AnimateScript (LocalScript) doesn't run in workspace Models,
		-- so we create an Animator if needed and load the animation directly.
		local humanoid = token.model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if not animator then
				animator = Instance.new("Animator")
				animator.Parent = humanoid
			end
			if not token._walkTrack then
				local ok, track = pcall(function()
					local walkAnim = Instance.new("Animation")
					walkAnim.AnimationId = "rbxassetid://507777826"  -- default R15 walk
					return animator:LoadAnimation(walkAnim)
				end)
				if ok and track then token._walkTrack = track end
			end
			if token._walkTrack then token._walkTrack:Play() end
			-- Stop walk after tween completes
			task.delay(0.5, function()
				if token._walkTrack and token._walkTrack.IsPlaying then
					token._walkTrack:Stop(0.2)
				end
			end)
		end
	else
		-- Cylinder fallback: keep 90-degree rotation (grounded to real surface)
		local destPos = tileToWorldGrounded(data.tileX, data.tileY)
		TweenService:Create(token.part, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {CFrame = CFrame.new(destPos) * CFrame.Angles(0,0,math.rad(90))}):Play()
	end

	-- Move selection ring to follow active unit
	if selectionRing and data.unitId == activeUnitId then
		local newPos = tileToWorld(data.tileX, data.tileY) - Vector3.new(0, 0.7, 0)
		TweenService:Create(selectionRing, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {CFrame = CFrame.new(newPos) * CFrame.Angles(0,0,math.rad(90))}):Play()
	end
	-- Camera: follow the active unit when it moves
	if data.unitId == activeUnitId then
		CameraController.FocusActiveUnit(tileToWorld(data.tileX, data.tileY))
	end
	-- Once the move tween finishes (flat 0.45s / arced 0.15+0.35s), settle BOTH the
	-- chevron AND the model body to the unit's OFFICIAL facing (the 8-way value the
	-- arrow + combat use), not the raw walk vector the tween aimed at. The tween
	-- animates the body toward the walk direction for the walk itself; this final
	-- settle (skipModelRotate=false) aligns the body with the arrow so they never
	-- diverge after a move. The 0.5s delay lands right as the tween ends, so it
	-- does not fight the animation.
	task.delay(0.5, function()
		local f = unitData[data.unitId] and unitData[data.unitId].facing
		if f then orientUnitToFacing(data.unitId, f, false) end
	end)
end)

BattleEvents.UnitActed.OnClientEvent:Connect(function(data)
	updateHpBar(data.targetId, data.targetHp, data.targetMaxHp)
	if unitData[data.targetId] then unitData[data.targetId].currentHp = data.targetHp end
	local tt = unitTokens[data.targetId]
	if tt then
		-- Camera: frame both actor and target during action resolution
		local _actorToken = unitTokens[data.actorId]
		if CameraController.IsScriptedView() then
			-- AI turn: keep the fixed iso view; just re-center on the action.
			CameraController.ScriptedFocus(tt.part.Position)
		elseif _actorToken and _actorToken.part ~= tt.part then
			CameraController.SaveZoom()
			CameraController.FocusTwoTargets(_actorToken.part.Position, tt.part.Position)
			-- Restore zoom after action visuals settle
			task.delay(1.5, function() CameraController.RestoreZoom() end)
		end
		if data.skillName then
			local at = unitTokens[data.actorId]
			if at then showFloatingText(at.part.Position, data.skillName, Theme.Colors.TextGold, 1.1) end
		end
		-- Only show a damage number when real damage landed. Self-target / no-hit
		-- skills (e.g. Riposte Stance) resolve with damage=0 and must NOT show '-0'.
		if (data.damage or 0) > 0 then showDamageText(tt.part.Position, data.damage, false) end
		-- Base animations: brief hit-reaction flinch on the target when damage lands,
		-- and an attack swing on the actor. One-shots over the looped idle (R15 only).
		if (data.damage or 0) > 0 then playUnitAnim(tt, "Hit", { stopAfter = 0.6 }) end
		-- Actor action animation: a SKILL plays a cast motion; a basic attack from
		-- range (same dist>7.5 proxy the VFX uses just below) plays a projectile
		-- draw/shoot; an adjacent basic attack plays the melee swing. Free-default
		-- stand-ins (swap specific ids later). One-shots over the looped idle.
		do
			local _at = unitTokens[data.actorId]
			if _at then
				local _kind = "Attack"
				if data.skillId then
					_kind = "Cast"
				elseif tt and tt.part and _at.part and (_at.part.Position - tt.part.Position).Magnitude > 7.5 then
					_kind = "Projectile"
				end
				playUnitAnim(_at, _kind, { stopAfter = 0.6 })
			end
		end
		-- VFX: prefer a pre-made asset resolved from the skill (element/tags) or the
		-- melee/ranged fallback; keep the programmatic beam/slash if no asset maps.
		local _actor = unitTokens[data.actorId]
		if _actor and VFXController then
			local dist = (_actor.part.Position - tt.part.Position).Magnitude
			local isRanged = dist > 7.5
			-- SFX: skill hit resolves by tags; a plain basic attack (no skillId)
			-- uses the melee/projectile slot (same ranged signal as the VFX).
			if SoundController then
				if data.skillId then SoundController.PlaySkill(data.skillId)
				else SoundController.PlayAttack(isRanged) end
			end
			local assetName = nil
			if data.skillId and VFXController.ResolveSkill then
				assetName = VFXController.ResolveSkill(data.skillId)
			end
			if not assetName then
				local reg = VFXController.GetRegistry and VFXController.GetRegistry() or nil
				if reg then assetName = isRanged and reg.Ranged or reg.Melee end
			end
			local played = nil
			if assetName and VFXController.PlayAsset then
				-- For ranged, play at target impact point; melee also reads well there.
				-- Capture the RETURN (clone or nil), not just pcall's ok flag — a graceful
				-- miss returns nil and must fall through to the programmatic effect.
				local ok, clone = pcall(VFXController.PlayAsset, assetName, tt.part.Position, 1.5)
				played = ok and clone or nil
			end
			if not played then
				-- Programmatic fallback (original behaviour).
				if isRanged then
					pcall(VFXController.RangedBeam, _actor.part.Position, tt.part.Position)
				else
					pcall(VFXController.MeleeSlash, _actor.part.Position, tt.part.Position)
				end
			end
		end
		if VFXController then pcall(VFXController.DamageImpact, tt.part.Position) end
		-- Brief red target highlight (1s)
		if VFXController then pcall(VFXController.SetPersistHighlight, data.targetId, tt.part, "target"); task.delay(1.0, function() pcall(VFXController.ClearHighlight, data.targetId) end) end
	end
	-- Battle log
	local actorName = unitData[data.actorId] and unitData[data.actorId].name or "?"
	local targetName = unitData[data.targetId] and unitData[data.targetId].name or "?"
	local logText = data.skillName
		and (actorName.." used "..data.skillName.." → "..targetName..". -"..data.damage.." HP")
		or (actorName.." attacks "..targetName..". -"..data.damage.." HP")
	if data.statusApplied and data.statusApplied ~= "" then
		logText = logText .. " +" .. data.statusApplied
	end
	if data.rtDelay and data.rtDelay > 0 then
		logText = logText .. " RT+" .. data.rtDelay
	end
	BattleHUD.AddLogEntry(logText)

	-- Show resolution result in preview panel
	bp.preview = {
		actionType = "Result",
		actorName = actorName,
		targetName = targetName,
		skillName = data.skillName,
		damage = data.damage,
		statusApplied = data.statusApplied,
		rtDelay = data.rtDelay,
	}
	BattleHUD.Render(bp)
end)

BattleEvents.DotDamage.OnClientEvent:Connect(function(data)
	updateHpBar(data.unitId, data.currentHp, data.maxHp)
	-- VFX: subtle DOT tick particles
	local _dt = unitTokens[data.unitId]
	if _dt and VFXController then pcall(VFXController.DotTick, _dt.part.Position, data.statusId) end
	if unitData[data.unitId] then unitData[data.unitId].currentHp = data.currentHp end
	local t = unitTokens[data.unitId]
	if t then showDamageText(t.part.Position, data.damage, false)
		showStatusText(t.part.Position, data.statusId, Theme.GetStatusColor(data.statusId)) end
	local uName = unitData[data.unitId] and unitData[data.unitId].name or "?"
	BattleHUD.AddLogEntry(uName.." takes "..data.damage.." "..data.statusId.." damage.")
end)

BattleEvents.HealingApplied.OnClientEvent:Connect(function(data)
	updateHpBar(data.targetId, data.targetHp, data.targetMaxHp)
	if unitData[data.targetId] then unitData[data.targetId].currentHp = data.targetHp end
	local tt = unitTokens[data.targetId]
	if tt then
		-- Camera: frame healer and target
		local _healActor = unitTokens[data.actorId]
		if CameraController.IsScriptedView() then
			CameraController.ScriptedFocus(tt.part.Position)
		elseif _healActor and _healActor.part ~= tt.part then
			CameraController.SaveZoom()
			CameraController.FocusTwoTargets(_healActor.part.Position, tt.part.Position)
			task.delay(1.5, function() CameraController.RestoreZoom() end)
		end
		if data.skillName then local at = unitTokens[data.actorId]; if at then showFloatingText(at.part.Position, data.skillName, Theme.Colors.Success, 1.1) end end
		showDamageText(tt.part.Position, data.amount, true)
		if SoundController then SoundController.PlayHeal() end
		-- VFX: pre-made heal asset if mapped, else programmatic heal particles.
		if VFXController then
			local reg = VFXController.GetRegistry and VFXController.GetRegistry() or nil
			local healAsset = reg and reg.Heal or nil
			local ok, clone = false, nil
			if healAsset and VFXController.PlayAsset then
				ok, clone = pcall(VFXController.PlayAsset, healAsset, tt.part.Position, 1.5)
			end
			if not (ok and clone) then pcall(VFXController.HealEffect, tt.part.Position) end
		end
	end
	local actorName = unitData[data.actorId] and unitData[data.actorId].name or "?"
	local targetName = unitData[data.targetId] and unitData[data.targetId].name or "?"
	BattleHUD.AddLogEntry(actorName.." heals "..targetName..". +"..data.amount.." HP")

	-- Show resolution result
	bp.preview = {
		actionType = "Result",
		actorName = actorName,
		targetName = targetName,
		skillName = data.skillName,
		healing = data.amount,
	}
	BattleHUD.Render(bp)
end)

BattleEvents.StatusApplied.OnClientEvent:Connect(function(data)
	if unitData[data.unitId] then
		if not unitData[data.unitId].statuses then unitData[data.unitId].statuses = {} end
		local found = false
		for _, ex in ipairs(unitData[data.unitId].statuses) do
			if ex.id == data.statusId then
				ex.remainingTurns = data.remainingTurns
				if data.sourceIcon then ex.sourceIcon = data.sourceIcon end
				if data.sourceDesc then ex.sourceDesc = data.sourceDesc end
				if data.sourceDuration then ex.sourceDuration = data.sourceDuration end
				found = true; break
			end
		end
		if not found then table.insert(unitData[data.unitId].statuses, { id = data.statusId, remainingTurns = data.remainingTurns or 0, sourceIcon = data.sourceIcon, sourceDesc = data.sourceDesc, sourceDuration = data.sourceDuration }) end
	end
	refreshDebuffLoop(data.unitId)
	-- Persistent standalone loops (NOT round-robined with debuffs):
	-- Guard status -> Shield-01 while active; stance pill (synthetic id not in
	-- STATUSES, carries sourceIcon) -> Charging while active.
	do
		local reg = VFXController and VFXController.GetRegistry and VFXController.GetRegistry() or nil
		if reg then
			if data.statusId == "Guard" and reg.GuardLoop then
				startPersistentLoop(data.unitId, "guard", reg.GuardLoop)
				if SoundController then SoundController.PlayGuard() end
			else
				local isRealStatus = GameConstants.STATUSES and GameConstants.STATUSES[data.statusId] ~= nil
				if not isRealStatus and reg.Stance then
					startPersistentLoop(data.unitId, "stance", reg.Stance)
				end
			end
		end
	end
	local t = unitTokens[data.unitId]
	if t then
		showStatusText(t.part.Position, "+"..data.statusId, Theme.GetStatusColor(data.statusId))
		-- SFX: play a buff/debuff sound based on the status kind (skip Guard — it
		-- has its own sound above; synthetic stance pills have no STATUSES def).
		if SoundController and data.statusId ~= "Guard" then
			local _def = GameConstants.STATUSES and GameConstants.STATUSES[data.statusId]
			if _def and _def.kind then SoundController.PlayStatus(_def.kind) end
		end
		-- VFX: pre-made status asset if mapped, else programmatic colored burst.
		if VFXController then
			local statusAsset = VFXController.ResolveStatus and VFXController.ResolveStatus(data.statusId) or nil
			local ok, clone = false, nil
			if statusAsset and VFXController.PlayAsset then
				ok, clone = pcall(VFXController.PlayAsset, statusAsset, t.part.Position, 1.6)
			end
			if not (ok and clone) then pcall(VFXController.StatusBurst, t.part.Position, data.statusId) end
		end
	end
end)

BattleEvents.StatusExpired.OnClientEvent:Connect(function(data)
	if unitData[data.unitId] and unitData[data.unitId].statuses then
		for i, s in ipairs(unitData[data.unitId].statuses) do if s.id == data.statusId then table.remove(unitData[data.unitId].statuses, i); break end end
	end
	refreshDebuffLoop(data.unitId)
	if data.statusId == "Guard" then stopPersistentLoop(data.unitId, "guard") end
	local t = unitTokens[data.unitId]
	if t then showStatusText(t.part.Position, "-"..data.statusId, Theme.Colors.TextSecondary) end
end)

-- Action announce: label above the acting unit's head for ~2s (Move / Basic
-- Attack / skill or item name / Guard / Push). Server fires on every AP commit.
BattleEvents.ActionAnnounced.OnClientEvent:Connect(function(data)
	if not data or not data.unitId then return end
	showActionAnnounce(data.unitId, data.label)
end)

BattleEvents.ChannelFizzled.OnClientEvent:Connect(function(data)
	local t = unitTokens[data.actorId]
	if t then showFloatingText(t.part.Position, (data.skillName or "Skill").." fizzled!", Theme.Colors.Warning, 1.5) end
	if data.actorId then stopPersistentLoop(data.actorId, "channel") end
end)

-- Channel loop lifecycle: start Charging 1 (damage) / Charging 2 (heal) on the
-- caster; stop on execute (ChannelEnded) or interrupt (ChannelFizzled above).
BattleEvents.ChannelStarted.OnClientEvent:Connect(function(data)
	if not data or not data.unitId then return end
	local reg = VFXController and VFXController.GetRegistry and VFXController.GetRegistry() or nil
	local asset = reg and (data.isHealing and reg.ChannelHeal or reg.ChannelDamage) or nil
	if asset then startPersistentLoop(data.unitId, "channel", asset) end
	if SoundController then SoundController.StartChannel(data.unitId) end
end)

BattleEvents.ChannelEnded.OnClientEvent:Connect(function(data)
	if data and data.unitId then stopPersistentLoop(data.unitId, "channel") end
	if SoundController then SoundController.StopChannel(data.unitId) end
end)

-- Multi-target (Cleave) flourish: play Multi-Slash ON THE ATTACKER once. Each
-- struck target already played its own Hit via UnitActed.
BattleEvents.MultiTargetHit.OnClientEvent:Connect(function(data)
	if not data or not data.unitId then return end
	local at = unitTokens[data.unitId]
	local reg = VFXController and VFXController.GetRegistry and VFXController.GetRegistry() or nil
	if at and reg and reg.MultiTarget and VFXController.PlayAsset then
		pcall(VFXController.PlayAsset, reg.MultiTarget, at.part.Position, 1.2)
	end
end)

BattleEvents.TurnEnded.OnClientEvent:Connect(function(data)
	local t = unitTokens[data.unitId]; if t then t.label.TextColor3 = unitNameColor(unitData[data.unitId]) end
	hideSelectionRing()
	if unitData[data.unitId] then
		unitData[data.unitId].statuses = mergeStatusSourceIcons(data.unitId, data.statuses)
		syncStanceLoop(data.unitId)
		if data.currentMp then unitData[data.unitId].currentMp = data.currentMp; updateMpBar(data.unitId, data.currentMp, unitData[data.unitId].maxMp or 0) end
		refreshDebuffLoop(data.unitId)
	end
end)

BattleEvents.UnitDefeated.OnClientEvent:Connect(function(data)
	local t = unitTokens[data.unitId]
	-- Unit LEFT the map (e.g. Merchant Caravan exit): vanish quietly — no KO
	-- smoke/sound/anim/grey body — and forget the token. Real defeats never set this.
	if data and data.removeUnit then
		if t then
			stopAllPersistentLoops(data.unitId)
			clearActionLabel(data.unitId)
			if SoundController then SoundController.StopChannel(data.unitId) end
			if t.model and t.model.Parent then t.model:Destroy() end
			if t.part and t.part.Parent then t.part:Destroy() end
			-- Facing arrow pad lives in visualFolder (not under the token), so remove it too.
			if t.facePad and t.facePad.Parent then t.facePad:Destroy() end
		end
		if VFXController then pcall(VFXController.ClearHighlight, data.unitId) end
		unitTokens[data.unitId] = nil
		unitData[data.unitId] = nil
		return
	end
	if t then
		if not t.model then
			-- Cylinder fallback: dim the part directly
			t.part.Color = Color3.fromRGB(60,60,60); t.part.Transparency = 0.4
		end
		-- R15 and cylinder both get VFX highlight (handled below)
	end
	if unitData[data.unitId] then unitData[data.unitId].isAlive = false end
	refreshDebuffLoop(data.unitId)  -- unit dead -> loop self-clears
	clearActionLabel(data.unitId)
	stopAllPersistentLoops(data.unitId)
	if SoundController then
		SoundController.StopChannel(data.unitId)  -- stop any channel loop on death
		SoundController.PlayKO()
	end
	-- VFX: KO smoke puff + persistent grey highlight
	if t then
		if VFXController then pcall(VFXController.KOEffect, t.part.Position) end
		if VFXController then pcall(VFXController.SetPersistHighlight, data.unitId, t.part, "ko") end
		-- Base KO animation: stop the looped idle and play a fall/faint one-shot (R15 only).
		stopUnitIdle(t)
		playUnitAnim(t, "KO", { stopAfter = 2.0 })
	end
end)

BattleEvents.GuardActivated.OnClientEvent:Connect(function(data)
	local token = unitTokens[data.unitId]
	local mitigationPct = math.round((data.mitigation or 0.35) * 100)

	if token then
		showFloatingText(token.part.Position, "GUARD " .. mitigationPct .. "%", Color3.fromRGB(100, 200, 255), 1.2)
		if not token.model then token.part.Color = Color3.fromRGB(80, 140, 200) end
		-- VFX: guard highlight (light blue outline)
		if VFXController then pcall(VFXController.SetPersistHighlight, data.unitId, token.part, "guard") end
	end
	if unitData[data.unitId] then
		unitData[data.unitId].isGuarding = true
		-- Add Guard as a visible buff status (1 turn, shows mitigation %)
		if not unitData[data.unitId].statuses then
			unitData[data.unitId].statuses = {}
		end
		-- Remove existing guard entry if re-applied (shouldn't happen, but safe)
		for i, s in ipairs(unitData[data.unitId].statuses) do
			if s.id == "Guard" then table.remove(unitData[data.unitId].statuses, i); break end
		end
		table.insert(unitData[data.unitId].statuses, {
			id = "Guard",
			remainingTurns = 1,
			value = mitigationPct .. "%",
		})
	end
end)

BattleEvents.UnitPushed.OnClientEvent:Connect(function(data)
	local targetToken = unitTokens[data.targetId]
	local pusherToken = unitTokens[data.pusherId]

	-- Update local unit data position
	if unitData[data.targetId] then
		unitData[data.targetId].tileX = data.finalTileX
		unitData[data.targetId].tileY = data.finalTileY
	end

	-- Animate target moving to new position
	if targetToken and data.pushed then
		TweenService:Create(targetToken.part,
			TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(tileToWorld(data.finalTileX, data.finalTileY)) * CFrame.Angles(0, 0, math.rad(90)) }
		):Play()
	end

	-- Show push text + damage floats
	if pusherToken then
		showFloatingText(pusherToken.part.Position, "PUSH", Color3.fromRGB(255, 180, 40), 1.1)
	end
	local totalDmg = (data.wallDamage or 0) + (data.fallDamage or 0)
	if totalDmg > 0 and targetToken then
		showFloatingText(targetToken.part.Position, "-" .. totalDmg, Color3.fromRGB(255, 100, 40))
		updateHpBar(data.targetId, data.targetHp, data.targetMaxHp)
	end
end)

BattleEvents.BattleEnded.OnClientEvent:Connect(function(data)
	if SoundController then SoundController.StopAllChannels() end
	if VFXController and VFXController.ClearAllTileEffects then pcall(VFXController.ClearAllTileEffects) end
	if BattleHUD.SetActiveEvent then BattleHUD.SetActiveEvent(nil) end
	isPlayerTurn = false; inputMode = nil; clearHighlights()
	hideSelectionRing()
	bp.state = "BattleEnded"; BattleHUD.Render(bp)

	-- Show result
	local gui = Instance.new("ScreenGui"); gui.Name = "BattleResult"; gui.ResetOnSpawn = false
	gui.DisplayOrder = 90; gui.Parent = player:WaitForChild("PlayerGui")
	local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.fromOffset(300,60)
	lbl.AnchorPoint = Vector2.new(0.5,0.5); lbl.Position = UDim2.fromScale(0.5,0.4)
	lbl.BackgroundColor3 = Theme.Colors.Background; lbl.BackgroundTransparency = 0.2
	lbl.Font = Theme.Font.Display; lbl.TextSize = Theme.Text.Title() + Theme.Scaled(12); lbl.BorderSizePixel = 0
	lbl.TextColor3 = data.winner == "Player" and Theme.Colors.TextGold or Theme.Colors.Danger
	lbl.Text = data.winner == "Player" and "VICTORY" or "DEFEAT"; lbl.Parent = gui
	Instance.new("UICorner", lbl).CornerRadius = Theme.CornerRadius.lg
	task.delay(5, function()
		if gui.Parent then gui:Destroy() end
		BattleHUD.Cleanup()
		bp = { state = "Idle", actor = nil, target = nil, skill = nil, preview = nil, tile = nil, inspectedEntityId = nil }
		destroyDevCameraPanel()
		CameraController.ExitBattle()
		-- Expand TemplateInspector panels after battle
		if type(_G.CTRBLXAI_SetInspectorCollapsed) == "function" then
			_G.CTRBLXAI_SetInspectorCollapsed(false)
		end
	end)
end)

_G.CTRBLXAI_SelectTileAt = function() end

-- ── View-mode support: grid visibility + per-tile elevation numbers ──
-- Grid Parts (Grid_S_*/Grid_E_*) are server-built inside TemplateViewerMap and
-- replicated. We toggle their visibility client-side per view mode (NET-001:
-- client owns visuals). Elevation number labels are created lazily on first
-- Top-view entry and cached in a dedicated folder, then just shown/hidden.
local elevLabelFolder = nil

local function setGridVisible(visible)
	local mf = workspace:FindFirstChild("TemplateViewerMap")
	if not mf then return end
	for _, ch in ipairs(mf:GetChildren()) do
		if ch:IsA("BasePart") and string.sub(ch.Name, 1, 5) == "Grid_" then
			ch.Transparency = visible and 0.5 or 1
		end
	end
end

local function buildElevationLabels()
	if elevLabelFolder and elevLabelFolder.Parent then return end
	elevLabelFolder = Instance.new("Folder")
	elevLabelFolder.Name = "ElevationLabels"
	if not elevationMap then elevLabelFolder.Parent = workspace; return end
	for ty, row in pairs(elevationMap) do
		for tx, elev in pairs(row) do
			local pad = Instance.new("Part")
			pad.Anchored = true; pad.CanCollide = false; pad.CanQuery = false
			pad.CanTouch = false; pad.CastShadow = false; pad.Transparency = 1
			pad.Size = Vector3.new(TILE_SIZE * 0.9, 0.05, TILE_SIZE * 0.9)
			pad.CFrame = CFrame.new(MAP_OFFSET_X + (tx - 0.5) * TILE_SIZE, tileSurfaceY(elev) + 3.1, MAP_OFFSET_Z + (ty - 0.5) * TILE_SIZE)
			local sg = Instance.new("SurfaceGui")
			sg.Face = Enum.NormalId.Top; sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			sg.PixelsPerStud = 24; sg.LightInfluence = 0; sg.AlwaysOnTop = true; sg.Parent = pad
			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.fromScale(1,1); lbl.BackgroundTransparency = 1
			lbl.Text = tostring(elev); lbl.TextScaled = false; lbl.TextSize = 28; lbl.Font = Theme.Font.PrimaryBold
			lbl.TextColor3 = Color3.fromRGB(255,255,255)
			local st = Instance.new("UIStroke"); st.Thickness = 2; st.Color = Color3.new(0,0,0); st.Parent = lbl
			lbl.Parent = sg
			pad.Parent = elevLabelFolder
		end
	end
	elevLabelFolder.Parent = workspace
end

local function setElevationLabelsVisible(visible)
	if visible then
		buildElevationLabels()
	end
	if elevLabelFolder then elevLabelFolder.Parent = visible and workspace or nil end
end

_G.CTRBLXAI_SetViewMode = function(mode)
	CameraController.SetViewMode(mode)
	-- Grid hidden only in Side view; visible in Isometric + Top.
	setGridVisible(mode ~= "Side")
	-- Elevation numbers only in Top view.
	setElevationLabelsVisible(mode == "Top")
end

-- ── TERRAIN RENDER SWITCHER (Phase 1: Voxel <-> Per-tile Parts) ──
-- 3-way client-side visual swap so the player can A/B terrain looks live.
-- Voxel: server-authoritative FillBlock terrain (natural tile Parts hidden).
-- PerTile: show the replicated tile Parts themselves with per-terrain PBR
--   Material + color (grids + clicks become exact on real Parts).
-- Mesh: (Phase 3) client heightmap mesh — not yet built.
-- NET-001: client owns visuals; the authoritative tile Parts + data never change,
-- only their skin. Voxel writes are server-only, so selecting Voxel round-trips.
local currentTerrainRender = "Voxel"  -- Voxel | PerTile | Mesh

-- Per-terrain PBR material for Per-tile mode (client-side visual only).
local TERRAIN_TILE_MATERIAL = {
	Clear = Enum.Material.Ground, Grassland = Enum.Material.Grass,
	["Clover Field"] = Enum.Material.LeafyGrass, Forest = Enum.Material.LeafyGrass,
	Rocky = Enum.Material.Rock, Sand = Enum.Material.Sand, Mud = Enum.Material.Mud,
	Swamp = Enum.Material.Slate, ["Shallow Water"] = Enum.Material.Sand,
	["Deep Water"] = Enum.Material.Slate, Ice = Enum.Material.Glacier,
	Molten = Enum.Material.CrackedLava, ["Tainted Ground"] = Enum.Material.Basalt,
	["Cracked Ground"] = Enum.Material.Asphalt, Quicksand = Enum.Material.Sandstone,
	["Stone Road"] = Enum.Material.Cobblestone, ["Dirt Road"] = Enum.Material.Pavement,
}

-- Show/hide the replicated tile Parts as solid material tiles (Per-tile mode).
-- When false, natural tiles are hidden (Transparency=1) so voxels/mesh show instead;
-- man-made SurfaceGui tiles are left as-is (they are always visible tile Parts).
local function setPerTileVisible(visible)
	local mf = workspace:FindFirstChild("TemplateViewerMap")
	if not mf then return end
	for _, ch in ipairs(mf:GetChildren()) do
		if ch:IsA("BasePart") and ch:GetAttribute("IsTemplateTile") then
			local terrainId = ch:GetAttribute("Terrain")
			-- Man-made/SurfaceGui tiles carry their own texture; skip re-skinning them.
			local hasSurfaceGui = ch:FindFirstChildOfClass("SurfaceGui") ~= nil
			if not hasSurfaceGui then
				if visible then
					ch.Transparency = 0
					ch.Material = TERRAIN_TILE_MATERIAL[terrainId] or Enum.Material.Ground
					local tc = ch:GetAttribute("TerrainColor")
					if typeof(tc) == "Color3" then ch.Color = tc end
				else
					ch.Transparency = 1
				end
			end
		end
	end
end

-- ── TERRAIN MESH (Phase 3 prototype): EditableMesh heightmap ──
-- Builds ONE conforming surface whose vertices sit at each tile's elevation, so
-- the ground slopes smoothly between tiles (vs flat-topped Per-tile blocks).
-- PROTOTYPE: single neutral material, no per-terrain texturing yet — the point
-- is to judge the sloped-mesh LOOK before investing in texturing. Client-side
-- (NET-001): built from the replicated elevationMap after the server clears voxels.
-- EditableMesh/CreateMeshPartAsync can fail or be unavailable — all guarded; on
-- failure we fall back to leaving the Per-tile Parts visible.
-- Option 1 terrain: one welded, UV-mapped, TEXTURED MeshPart PER terrain type
-- (a MeshPart has a single texture slot, so 22 terrains = up to 22 parts). All
-- live under this folder so cleanup is one Destroy. MEM-002.
local terrainMeshFolder = nil

local function clearTerrainMesh()
	if terrainMeshFolder then terrainMeshFolder:Destroy(); terrainMeshFolder = nil end  -- MEM-002
end

-- Bilinear-interpolated ground height at a fractional tile coordinate (fx in
-- [1..MAP_WIDTH], fy in [1..MAP_HEIGHT]) so subdivided vertices follow the slope
-- between tile-center elevations. Clamps to map bounds.
local function meshHeightAt(fx, fy)
	local x0 = math.clamp(math.floor(fx), 1, MAP_WIDTH)
	local x1 = math.clamp(x0 + 1, 1, MAP_WIDTH)
	local y0 = math.clamp(math.floor(fy), 1, MAP_HEIGHT)
	local y1 = math.clamp(y0 + 1, 1, MAP_HEIGHT)
	local tx = fx - x0
	local ty = fy - y0
	local function e(ex, ey) return (elevationMap[ey] and elevationMap[ey][ex]) or 1 end
	local e00, e10 = e(x0, y0), e(x1, y0)
	local e01, e11 = e(x0, y1), e(x1, y1)
	local top = e00 + (e10 - e00) * tx
	local bot = e01 + (e11 - e01) * tx
	local elev = top + (bot - top) * ty
	return tileSurfaceY(elev)
end

-- Grid-line thickness as a fraction of a tile (small = thin line). The outer
-- border ring of each tile's faces is colored black (the baked grid line); the
-- inner square is the terrain fill color. Baked into the mesh so lines conform
-- to the terrain slope (no floating Parts, no PNG). SetFaceColors provides the
-- per-face black/fill coloring (confirmed available on this engine).
local GRID_LINE_FRAC = 0.03
local GRID_LINE_COLOR = Color3.fromRGB(15, 15, 15)

local function buildTerrainMesh()
	clearTerrainMesh()
	if not elevationMap then warn("[TerrainMesh] no elevationMap"); return false end
	local AssetService = game:GetService("AssetService")

	-- Option 1: one welded, UV-mapped, TEXTURED MeshPart PER terrain type.
	-- Tiles are grouped by GameConstants.GetTerrainId; each group builds its own
	-- EditableMesh with: welded vertices (smooth normals within the terrain),
	-- planar UVs (kills the studs — no-UV meshes fall back to the studded material
	-- projection), the terrain's TextureID, and per-face vertex colors that MULTIPLY
	-- the texture: white on fill faces (texture shows true) and black on the border
	-- ring (baked grid line over the texture). One texture slot per part = per-terrain
	-- parts. Man-made terrains without slope still texture fine here.
	local m = GRID_LINE_FRAC
	local fracs = { 0.0, m, 1.0 - m, 1.0 }
	local UV_TILE_SPAN = 1.0  -- texture repeats once per tile (u,v in tile units)

	local folder = Instance.new("Folder")
	folder.Name = "TerrainMeshParts"

	-- Group tile coords by terrain id.
	local groups = {}  -- terrainId -> { {tx,ty}, ... }
	for ty = 1, MAP_HEIGHT do
		for tx = 1, MAP_WIDTH do
			local tid = GameConstants.GetTerrainId(tx, ty)
			groups[tid] = groups[tid] or {}
			table.insert(groups[tid], { tx, ty })
		end
	end

	local totalFaces = 0
	local builtParts = 0

	-- Build one MeshPart per terrain group.
	for terrainId, tiles in pairs(groups) do
		local ok, em = pcall(function() return AssetService:CreateEditableMesh() end)
		if not ok or not em then
			warn("[TerrainMesh] CreateEditableMesh failed for " .. tostring(terrainId) .. ": " .. tostring(em))
		else
			local vertCache = {}  -- 'ix_iy' -> vertex id (weld within this terrain group)
			local blackFaces, fillFaces = {}, {}

			local function lineIndex(tileIdx, sub)
				if sub == 4 then return 3 * tileIdx end
				return 3 * (tileIdx - 1) + (sub - 1)
			end
			local function getVert(tx, ty, gx, gy)
				local ix = lineIndex(tx, gx)
				local iy = lineIndex(ty, gy)
				local k = ix .. "_" .. iy
				local existing = vertCache[k]
				if existing then return existing end
				local fx = (tx - 1) + fracs[gx]
				local fy = (ty - 1) + fracs[gy]
				local wx = MAP_OFFSET_X + fx * TILE_SIZE
				local wz = MAP_OFFSET_Z + fy * TILE_SIZE
				local wy = meshHeightAt(tx - 0.5 + (fracs[gx] - 0.5), ty - 0.5 + (fracs[gy] - 0.5))
				local vid = em:AddVertex(Vector3.new(wx, wy, wz))
				vertCache[k] = vid
				return vid
			end
			-- UV for a vertex: planar projection in tile units (repeats once per tile).
			local uvCache = {}
			local function getUV(tx, ty, gx, gy)
				local fx = (tx - 1) + fracs[gx]
				local fy = (ty - 1) + fracs[gy]
				local k = string.format("%.4f_%.4f", fx, fy)
				local existing = uvCache[k]
				if existing then return existing end
				local uid = em:AddUV(Vector2.new(fx / UV_TILE_SPAN, fy / UV_TILE_SPAN))
				uvCache[k] = uid
				return uid
			end

			local buildOk, buildErr = pcall(function()
				for _, tc in ipairs(tiles) do
					local tx, ty = tc[1], tc[2]
					for gy = 1, 3 do
						for gx = 1, 3 do
							local a = getVert(tx, ty, gx,     gy)
							local b = getVert(tx, ty, gx + 1, gy)
							local c = getVert(tx, ty, gx + 1, gy + 1)
							local d = getVert(tx, ty, gx,     gy + 1)
							local f1 = em:AddTriangle(a, c, b)
							local f2 = em:AddTriangle(a, d, c)
							-- Assign UVs per face corner (matches the triangle winding).
							local ua = getUV(tx, ty, gx,     gy)
							local ub = getUV(tx, ty, gx + 1, gy)
							local uc = getUV(tx, ty, gx + 1, gy + 1)
							local ud = getUV(tx, ty, gx,     gy + 1)
							if type(em.SetFaceUVs) == "function" then
								em:SetFaceUVs(f1, { ua, uc, ub })
								em:SetFaceUVs(f2, { ua, ud, uc })
							end
							if gx == 2 and gy == 2 then
								table.insert(fillFaces, f1); table.insert(fillFaces, f2)
							else
								table.insert(blackFaces, f1); table.insert(blackFaces, f2)
							end
						end
					end
				end
			end)
			if not buildOk then
				warn("[TerrainMesh] build failed for " .. tostring(terrainId) .. ": " .. tostring(buildErr))
			else
				-- Face colors MULTIPLY the texture: white=texture true, black=grid line.
				pcall(function()
					if type(em.AddColor) == "function" and type(em.SetFaceColors) == "function" then
						local whiteId = em:AddColor(Color3.new(1, 1, 1), 1)
						local blackId = em:AddColor(GRID_LINE_COLOR, 1)
						for _, fid in ipairs(fillFaces) do em:SetFaceColors(fid, { whiteId, whiteId, whiteId }) end
						for _, fid in ipairs(blackFaces) do em:SetFaceColors(fid, { blackId, blackId, blackId }) end
					end
				end)

				local createOk, part = pcall(function()
					return AssetService:CreateMeshPartAsync(Content.fromObject(em))
				end)
				if not createOk or not part then
					warn("[TerrainMesh] CreateMeshPartAsync failed for " .. tostring(terrainId) .. ": " .. tostring(part))
				else
					part.Name = "TerrainMesh_" .. tostring(terrainId):gsub("%s+", "_")
					part.Anchored = true
					part.CanCollide = false
					part.CanQuery = false
					part.CanTouch = false
					part.CastShadow = false
					part.Material = Enum.Material.SmoothPlastic
					-- Apply the terrain's surface texture (UVs make it map correctly; the
					-- texture replaces the studded no-UV fallback).
					local assetId = TerrainTextures and TerrainTextures.Assets and TerrainTextures.Assets[terrainId]
					if assetId then
						pcall(function() part.TextureID = assetId end)
					end
					part.CFrame = CFrame.new(0, 0, 0)
					part.Parent = folder
					totalFaces = totalFaces + #fillFaces + #blackFaces
					builtParts = builtParts + 1
				end
			end
		end
	end

	if builtParts == 0 then
		warn("[TerrainMesh] no terrain parts built"); folder:Destroy(); return false
	end
	folder.Parent = workspace:FindFirstChild("TemplateViewerMap") or workspace
	terrainMeshFolder = folder
	print("[TerrainMesh] built " .. builtParts .. " per-terrain textured meshes (" .. totalFaces .. " faces, " .. MAP_WIDTH .. "x" .. MAP_HEIGHT .. " tiles)")
	return true
end

_G.CTRBLXAI_SetTerrainRender = function(mode)
	if mode ~= "Voxel" and mode ~= "PerTile" and mode ~= "Mesh" then return end
	currentTerrainRender = mode
	if mode == "PerTile" then
		clearTerrainMesh()
		setGridVisible(true)
		-- Show tile Parts immediately for a responsive feel, AND ask the server to
		-- CLEAR the voxel terrain — the client cannot clear voxels itself, so without
		-- this the tile Parts stay buried under the voxels (the bug the user hit).
		setPerTileVisible(true)
		if BattleEvents.DevCommand then
			BattleEvents.DevCommand:FireServer({ action = "TerrainRender", mode = "PerTile" })
		end
	elseif mode == "Voxel" then
		clearTerrainMesh()
		setGridVisible(true)
		-- Hide the per-tile skins; ask the server to (re)build voxel terrain.
		setPerTileVisible(false)
		if BattleEvents.DevCommand then
			BattleEvents.DevCommand:FireServer({ action = "TerrainRender", mode = "Voxel" })
		end
	elseif mode == "Mesh" then
		-- Hide per-tile skins AND the floating Grid_* Parts — the baked mesh has its
		-- own conforming grid lines, and the tile Parts are hidden server-side.
		setPerTileVisible(false)
		setGridVisible(false)
		if BattleEvents.DevCommand then
			BattleEvents.DevCommand:FireServer({ action = "TerrainRender", mode = "Mesh" })
		end
		local built = buildTerrainMesh()
		if not built then
			warn("[TerrainRender] Mesh build failed — falling back to Per-tile view")
			setPerTileVisible(true)
		end
	else
		clearTerrainMesh()
	end
	print("[TerrainRender] mode -> " .. mode)
end

_G.CTRBLXAI_GetElevation = function(tileX, tileY)
	if elevationMap and elevationMap[tileY] then
		return elevationMap[tileY][tileX] or 1
	end
	return 1
end


_G.CTRBLXAI_TimelineClickTile = function(tileX, tileY)
	if tileX and tileY then
		processTileClick(tileX, tileY)

		-- Focus camera on the clicked unit's tile
		CameraController.FocusActiveUnit(tileToWorld(tileX, tileY))

		-- Highlight the tile with "selected" style
		clearHighlights()
		createTileHighlight(tileX, tileY, "selected")

		-- Show quick-look tooltip (same as hover)
		local hoveredUnit = nil
		for _, data in pairs(unitData) do
			if data.tileX == tileX and data.tileY == tileY and data.isAlive ~= false then
				hoveredUnit = data
				break
			end
		end
		if hoveredUnit then
			local hpText = string.format("HP %d/%d", hoveredUnit.currentHp or 0, hoveredUnit.maxHp or 0)
			local mpText = string.format("MP %d/%d", hoveredUnit.currentMp or 0, hoveredUnit.maxMp or 0)
			local tooltipLines = {
				{ text = hpText, color = Theme.Colors.TextPrimary },
				{ text = mpText, color = Theme.Colors.TextSecondary },
			}
			if hoveredUnit.statuses and #hoveredUnit.statuses > 0 then
				local statusParts = {}
				for _, s in ipairs(hoveredUnit.statuses) do
					table.insert(statusParts, (s.id or "?") .. (s.remainingTurns and ("(" .. s.remainingTurns .. ")") or ""))
				end
				table.insert(tooltipLines, { text = table.concat(statusParts, " "), color = Theme.Colors.Warning })
			end
			local worldPos = tileToWorld(tileX, tileY)
			local cam = workspace.CurrentCamera
			local screenPos = cam and cam:WorldToScreenPoint(worldPos) or Vector3.new(400, 200, 0)
			BattleHUD.ShowTooltip({
				title = hoveredUnit.name or "Unit",
				portrait = string.sub(hoveredUnit.name or "?", 1, 2),
				portraitColor = Theme.GetSideColor(hoveredUnit.side),
				lines = tooltipLines,
				position = UDim2.new(0, screenPos.X, 0, screenPos.Y - 20),
				anchorPoint = Vector2.new(0.5, 1),
				maxWidth = 160,
			})
		end
	end
end


print("[CTRBLXAI] BattleVisualClient v3 loaded.")


--------------------------------------------------
-- LOADOUT HUB (Slice 4D — minimal functional placeholder)
-- Slice 7 owns final visual presentation.
--------------------------------------------------

local loadoutHubGui = nil

local function destroyLoadoutHub()
	if loadoutHubGui then loadoutHubGui:Destroy(); loadoutHubGui = nil end
end

local function createLoadoutHub(phase)
	destroyLoadoutHub()

	local gui = Instance.new("ScreenGui")
	gui.Name = "LoadoutHub"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 90
	gui.Parent = player:WaitForChild("PlayerGui")
	loadoutHubGui = gui

	local frame = Instance.new("Frame")
	frame.Name = "HubFrame"
	frame.Size = UDim2.new(0.92, 0, 0.88, 0) -- responsive: 92% width, 88% height (fits mobile)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Theme.Colors.Background
	frame.BackgroundTransparency = 0.02
	frame.BorderSizePixel = 0
	frame.Active = true
	frame.Parent = gui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
	local hubConstraint = Instance.new("UISizeConstraint", frame)
	hubConstraint.MaxSize = Vector2.new(560, 480)
	local stroke = Instance.new("UIStroke", frame)
	stroke.Color = Theme.Colors.Border; stroke.Thickness = 1

	-- Title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 28)
	title.Position = UDim2.new(0, 0, 0, 4)
	title.BackgroundTransparency = 1
	title.Font = Theme.Font.PrimaryBold; title.TextSize = Theme.Text.Title()
	title.TextColor3 = Theme.Colors.TextGold
	title.Text = phase == "PreBattle" and "⚔ LOADOUT HUB" or "⚔ LOADOUT HUB (Post-Battle)"
	title.Parent = frame

	-- Output area (scrollable text)
	local outputFrame = Instance.new("ScrollingFrame")
	outputFrame.Name = "Output"
	outputFrame.Size = UDim2.new(1, -16, 1, -140)
	outputFrame.Position = UDim2.new(0, 8, 0, 34)
	outputFrame.BackgroundColor3 = Theme.Colors.Surface
	outputFrame.BackgroundTransparency = 0.1
	outputFrame.BorderSizePixel = 0
	outputFrame.ScrollBarThickness = 6
	outputFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	outputFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	outputFrame.Parent = frame
	Instance.new("UICorner", outputFrame).CornerRadius = UDim.new(0, 4)

	local outputLayout = Instance.new("UIListLayout", outputFrame)
	outputLayout.SortOrder = Enum.SortOrder.LayoutOrder; outputLayout.Padding = UDim.new(0, 2)

	local outputText = Instance.new("TextLabel")
	outputText.Name = "Text"
	outputText.Size = UDim2.new(1, -8, 0, 0)
	outputText.Position = UDim2.new(0, 4, 0, 2)
	outputText.AutomaticSize = Enum.AutomaticSize.Y
	outputText.BackgroundTransparency = 1
	outputText.Font = Enum.Font.Code; outputText.TextSize = 11
	outputText.TextColor3 = Color3.fromRGB(190, 190, 190)
	outputText.TextXAlignment = Enum.TextXAlignment.Left
	outputText.TextYAlignment = Enum.TextYAlignment.Top
	outputText.TextWrapped = true
	outputText.RichText = true
	outputText.Text = "Loadout Hub ready. Use buttons below."
	outputText.LayoutOrder = 0
	outputText.Parent = outputFrame

	local function setOutput(txt)
		outputText.Text = txt
		-- Remove any clickable line buttons from previous view
		for _, child in ipairs(outputFrame:GetChildren()) do
			if child:IsA("TextButton") then child:Destroy() end
		end
	end

	-- Render clickable lines in the output area
	-- Each line is a TextButton; clicking it calls onClickFn(lineData)
	local function setClickableLines(header, lineEntries)
		-- lineEntries = { {text, color, onClick} }
		outputText.Text = header
		for _, child in ipairs(outputFrame:GetChildren()) do
			if child:IsA("TextButton") then child:Destroy() end
		end
		for idx, entry in ipairs(lineEntries) do
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(1, -8, 0, 0)
			btn.AutomaticSize = Enum.AutomaticSize.Y
			btn.Position = UDim2.new(0, 4, 0, 0)
			btn.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
			btn.BackgroundTransparency = 0.5
			btn.BorderSizePixel = 0
			btn.Font = Enum.Font.Code; btn.TextSize = 11
			btn.TextColor3 = entry.color or Color3.fromRGB(190, 190, 190)
			btn.TextXAlignment = Enum.TextXAlignment.Left
			btn.TextWrapped = true
			btn.RichText = true
			btn.Text = entry.text
			btn.LayoutOrder = idx + 1
			btn.Parent = outputFrame
			Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 2)
			if entry.onClick then
				btn.MouseButton1Click:Connect(entry.onClick)
			end
		end
	end


	-- Input fields for equip/unequip
	local inputRow = Instance.new("Frame")
	inputRow.Size = UDim2.new(1, -16, 0, 24)
	inputRow.Position = UDim2.new(0, 8, 1, -130)
	inputRow.BackgroundTransparency = 1
	inputRow.Parent = frame

	local unitInput = Instance.new("TextBox")
	unitInput.Size = UDim2.fromOffset(130, 22)
	unitInput.Position = UDim2.new(0, 0, 0, 0)
	unitInput.PlaceholderText = "unit_hero"
	unitInput.Text = ""
	unitInput.Font = Enum.Font.Code; unitInput.TextSize = 10
	unitInput.TextColor3 = Color3.fromRGB(220, 220, 220)
	unitInput.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
	unitInput.BorderSizePixel = 0
	unitInput.ClearTextOnFocus = false
	unitInput.Parent = inputRow
	Instance.new("UICorner", unitInput).CornerRadius = UDim.new(0, 3)

	local itemInput = Instance.new("TextBox")
	itemInput.Size = UDim2.fromOffset(160, 22)
	itemInput.Position = UDim2.new(0, 134, 0, 0)
	itemInput.PlaceholderText = "item_1001_1"
	itemInput.Text = ""
	itemInput.Font = Enum.Font.Code; itemInput.TextSize = 10
	itemInput.TextColor3 = Color3.fromRGB(220, 220, 220)
	itemInput.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
	itemInput.BorderSizePixel = 0
	itemInput.ClearTextOnFocus = false
	itemInput.Parent = inputRow
	Instance.new("UICorner", itemInput).CornerRadius = UDim.new(0, 3)

	-- Button row
	local btnRow = Instance.new("Frame")
	btnRow.Size = UDim2.new(1, -16, 0, 66)
	btnRow.Position = UDim2.new(0, 8, 1, -100)
	btnRow.BackgroundTransparency = 1
	btnRow.Parent = frame

	local btnLayout = Instance.new("UIGridLayout", btnRow)
	btnLayout.CellSize = UDim2.fromOffset(115, 28)
	btnLayout.CellPadding = UDim2.fromOffset(4, 4)
	btnLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local function hubBtn(text, order, callback, color)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 100, 0, 28)
		btn.BackgroundColor3 = color or Theme.Colors.Surface
		btn.BackgroundTransparency = 0.15
		btn.Font = Theme.Font.PrimaryBold; btn.TextSize = Theme.Text.Body()
		btn.TextColor3 = Theme.Colors.TextPrimary
		btn.Text = text; btn.LayoutOrder = order
		btn.BorderSizePixel = 0; btn.Parent = btnRow
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
		btn.MouseButton1Click:Connect(callback)
		return btn
	end

	hubBtn("VIEW ROSTER", 1, function()
		setOutput("Loading roster...")
		local roster = BattleEvents.GetRosterData:InvokeServer()
		if not roster then setOutput("Failed to get roster."); return end
		local entries = {}
		for uid, data in pairs(roster) do
			local hpColor = data.isKO and "rgb(150,150,150)" or (data.currentHp / data.maxHp > 0.5 and "rgb(100,200,100)" or "rgb(200,100,100)")
			local offTag = (data.equippedOffHandName and data.equippedOffHandName ~= "none") and (" | Off:" .. data.equippedOffHandName) or ""
			local lineText = string.format(
				'<font color="%s">%s</font> L%d | HP:%d/%d MP:%d/%d%s | Wpn:%s%s | <font color="rgb(100,160,220)">%s</font>',
				hpColor, data.name, data.level,
				data.currentHp, data.maxHp, data.currentMp, data.maxMp,
				data.isKO and " [KO]" or "",
				data.equippedWeaponName, offTag,
				uid
			)
			local capturedUid = uid
			table.insert(entries, {
				text = lineText,
				onClick = function() unitInput.Text = capturedUid end,
			})
		end
		setClickableLines("<b>ROSTER</b> (click a unit to fill Unit ID)\n", entries)
	end)

	hubBtn("VIEW INVENTORY", 2, function()
		setOutput("Loading inventory...")
		local items = BattleEvents.GetInventoryData:InvokeServer()
		if not items then setOutput("Failed to get inventory."); return end
		local entries = {}
		for _, item in ipairs(items) do
			local rarityColor = ({
				Broken = "rgb(120,120,120)", Common = "rgb(200,200,200)",
				Uncommon = "rgb(100,200,100)", Rare = "rgb(100,150,255)",
				Epic = "rgb(180,100,255)", Legendary = "rgb(255,180,50)",
			})[item.rarity] or "rgb(200,200,200)"
			local slotTag = item.equippedSlot and (" [" .. item.equippedSlot .. "]") or ""
			local eqTag = item.equippedBy and string.format(' <font color="rgb(255,200,80)">← %s%s</font>', item.equippedBy, slotTag) or ""
			local lineText = string.format(
				'<font color="%s">[%s]</font> %s L%d | Dmg:%d WT:%d Def:%d | +%dattr +%dpass | ID:%s%s',
				rarityColor, item.rarity, item.name, item.itemLevel,
				item.damage, item.wt, item.defense,
				item.bonusCount, item.passiveCount, item.instanceId,
				eqTag
			)
			local capturedId = item.instanceId
			table.insert(entries, {
				text = lineText,
				color = Color3.fromRGB(190, 190, 190),
				onClick = function() itemInput.Text = capturedId end,
			})
		end
		setClickableLines(string.format("<b>INVENTORY (%d items)</b> (click an item to fill Item ID)\n", #items), entries)
	end)

	hubBtn("EQUIP", 3, function()
		setOutput("EQUIP: Enter unitId and instanceId in the boxes below, then press CONFIRM EQUIP.\n\nUnit IDs: unit_hero, unit_mage, unit_ranger\nItem IDs: see VIEW INVENTORY")
	end)

	hubBtn("UNEQUIP", 4, function()
		setOutput("UNEQUIP: Enter unitId below, then press CONFIRM UNEQUIP.\nSlot defaults to MainHand.\n\nUnit IDs: unit_hero, unit_mage, unit_ranger")
	end)

	if phase == "PreBattle" then
		hubBtn("START BATTLE", 5, function()
			destroyLoadoutHub()
			BattleEvents.StartBattle:FireServer()
		end, Color3.fromRGB(40, 100, 40))
	else
		-- PostBattle: DONE button closes hub and signals server to continue
		hubBtn("DONE", 5, function()
			destroyLoadoutHub()
			BattleEvents.StartBattle:FireServer()
		end, Color3.fromRGB(40, 120, 60))
	end

	-- Dev tools in Loadout Hub
	hubBtn("SAVE NOW", 6, function()
		BattleEvents.DevCommand:FireServer({ action = "SaveNow" })
		setOutput("Save requested...")
	end, Color3.fromRGB(30, 60, 80))

	hubBtn("DELETE SAVE", 7, function()
		BattleEvents.DevCommand:FireServer({ action = "DeleteSave" })
		setOutput("Delete save requested...")
	end, Color3.fromRGB(80, 20, 20))


	local confirmEquip = Instance.new("TextButton")
	confirmEquip.Size = UDim2.fromOffset(85, 22)
	confirmEquip.Position = UDim2.new(0, 298, 0, 0)
	confirmEquip.Text = "CONFIRM EQUIP"
	confirmEquip.Font = Theme.Font.PrimaryBold; confirmEquip.TextSize = Theme.Text.Small()
	confirmEquip.TextColor3 = Color3.fromRGB(220, 220, 220)
	confirmEquip.BackgroundColor3 = Color3.fromRGB(40, 80, 40)
	confirmEquip.BorderSizePixel = 0
	confirmEquip.Parent = inputRow
	Instance.new("UICorner", confirmEquip).CornerRadius = UDim.new(0, 3)
	confirmEquip.MouseButton1Click:Connect(function()
		local uid = unitInput.Text
		local iid = itemInput.Text
		if uid == "" or iid == "" then setOutput("Enter both unit ID and item ID."); return end
		setOutput("Equipping...")
		local result = BattleEvents.RequestEquip:InvokeServer(uid, iid)
		if result and result.ok then
			setOutput(string.format("Equipped %s on %s (%s)", result.name or iid, uid, result.slot or "?"))
		else
			setOutput("Equip failed: " .. (result and result.reason or "unknown"))
		end
	end)

	local confirmUnequip = Instance.new("TextButton")
	confirmUnequip.Size = UDim2.fromOffset(95, 22)
	confirmUnequip.Position = UDim2.new(0, 387, 0, 0)
	confirmUnequip.Text = "CONFIRM UNEQUIP"
	confirmUnequip.Font = Theme.Font.PrimaryBold; confirmUnequip.TextSize = Theme.Text.Small()
	confirmUnequip.TextColor3 = Color3.fromRGB(220, 220, 220)
	confirmUnequip.BackgroundColor3 = Color3.fromRGB(80, 40, 40)
	confirmUnequip.BorderSizePixel = 0
	confirmUnequip.Parent = inputRow
	Instance.new("UICorner", confirmUnequip).CornerRadius = UDim.new(0, 3)
	confirmUnequip.MouseButton1Click:Connect(function()
		local uid = unitInput.Text
		if uid == "" then setOutput("Enter unit ID."); return end
		setOutput("Unequipping...")
		local result = BattleEvents.RequestUnequip:InvokeServer(uid, "MainHand")
		if result and result.ok then
			setOutput(string.format("Unequipped MainHand on %s", uid))
		else
			setOutput("Unequip failed: " .. (result and result.reason or "unknown"))
		end
	end)
end

--------------------------------------------------
-- REWARD SCREEN (Slice 4D — minimal functional placeholder)
--------------------------------------------------

local rewardGui = nil
local rewardBackBtn = nil

BattleEvents.RewardScreen.OnClientEvent:Connect(function(data)
	if rewardGui then rewardGui:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = "RewardScreen"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 92
	gui.Parent = player:WaitForChild("PlayerGui")
	rewardGui = gui

	-- Local makeLabel helper (same signature as BattleHUD's)
	local function makeLabel(parent, text, props)
		local lbl = Instance.new("TextLabel")
		lbl.Size = props.size or UDim2.new(1, 0, 0, 14)
		lbl.Position = props.pos or UDim2.new(0, 0, 0, 0)
		lbl.BackgroundTransparency = 1
		lbl.BorderSizePixel = 0
		lbl.Font = props.font or Theme.Font.Primary
		lbl.TextSize = props.textSize or Theme.Text.Body()
		lbl.TextColor3 = props.color or Theme.Colors.TextPrimary
		lbl.TextXAlignment = props.align or Enum.TextXAlignment.Left
		lbl.TextWrapped = props.wrap or false
		lbl.Text = text or ""
		lbl.LayoutOrder = props.order or 0
		lbl.Parent = parent
		return lbl
	end

	-- Dim backdrop
	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.Colors.Overlay
	backdrop.BackgroundTransparency = 0.4
	backdrop.BorderSizePixel = 0
	backdrop.Parent = gui

	-- Main panel using Theme
	local frame = Theme.MakePanel("VictoryPanel",
		UDim2.new(0.70, 0, 0.85, 0),
		UDim2.new(0.5, 0, 0.5, 0),
		Vector2.new(0.5, 0.5),
		gui)
	frame.ClipsDescendants = true

	local framePad = Instance.new("UIPadding", frame)
	framePad.PaddingTop = UDim.new(0, 10)
	framePad.PaddingLeft = UDim.new(0, 12)
	framePad.PaddingRight = UDim.new(0, 12)
	framePad.PaddingBottom = UDim.new(0, 10)

	-- VICTORY! title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 24)
	title.BackgroundTransparency = 1
	title.Font = Theme.Font.PrimaryBold
	title.TextSize = Theme.Text.Title()
	title.TextColor3 = Theme.Colors.TextGold
	title.Text = "VICTORY!"
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.Parent = frame

	-- Recovery summary
	local recY = 26
	if data.recovery and #data.recovery > 0 then
		local recoveryText = ""
		for _, r in ipairs(data.recovery) do
			local hpGain = (r.hpGain and r.hpGain > 0) and ("HP+" .. r.hpGain) or ""
			local mpGain = (r.mpGain and r.mpGain > 0) and ("MP+" .. r.mpGain) or ""
			local gains = hpGain .. (hpGain ~= "" and mpGain ~= "" and " " or "") .. mpGain
			if gains ~= "" then
				recoveryText = recoveryText .. (r.name or "?") .. ": " .. gains .. "  "
			end
		end
		if recoveryText ~= "" then
			local recLabel = Instance.new("TextLabel")
			recLabel.Size = UDim2.new(1, 0, 0, 14)
			recLabel.Position = UDim2.new(0, 0, 0, recY)
			recLabel.BackgroundTransparency = 1
			recLabel.Font = Theme.Font.Mono
			recLabel.TextSize = Theme.Text.Tiny()
			recLabel.TextColor3 = Theme.Colors.Success
			recLabel.TextXAlignment = Enum.TextXAlignment.Left
			recLabel.Text = recoveryText
			recLabel.Parent = frame
			recY = recY + 16
		end
	end

	-- Loot header
	local lootLabel = Instance.new("TextLabel")
	lootLabel.Size = UDim2.new(1, 0, 0, 14)
	lootLabel.Position = UDim2.new(0, 0, 0, recY)
	lootLabel.BackgroundTransparency = 1
	lootLabel.Font = Theme.Font.PrimaryBold
	lootLabel.TextSize = Theme.Text.Small()
	lootLabel.TextColor3 = Theme.Colors.TextSecondary
	lootLabel.TextXAlignment = Enum.TextXAlignment.Left
	lootLabel.Text = "LOOT"
	lootLabel.Parent = frame

	-- Loot grid
	local rewards = data.rewards or {}
	local gridY = recY + 18

	local lootGrid = Instance.new("ScrollingFrame")
	lootGrid.Size = UDim2.new(1, 0, 1, -(gridY + 40))
	lootGrid.Position = UDim2.new(0, 0, 0, gridY)
	lootGrid.BackgroundTransparency = 1
	lootGrid.BorderSizePixel = 0
	lootGrid.ScrollBarThickness = 3
	lootGrid.ScrollBarImageColor3 = Theme.Colors.TextSecondary
	lootGrid.CanvasSize = UDim2.new(0, 0, 0, 0)
	lootGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	lootGrid.Parent = frame

	local grid = Instance.new("UIGridLayout", lootGrid)
	grid.CellSize = UDim2.new(0, 72, 0, 82)
	grid.CellPadding = UDim2.new(0, 4, 0, 3)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirection = Enum.FillDirection.Horizontal

	-- Hand class -> icon mapping
	local HAND_ICONS = {
		["1H"] = "\xe2\x9a\x94", ["2H"] = "\xe2\x9a\x94",
		["Off-Hand"] = "\xf0\x9f\x9b\xa1",
	}

	-- Detail overlay state
	local detailFrame = nil
	local detailGui = nil

	local function closeRewardDetail()
		if detailFrame then detailFrame:Destroy(); detailFrame = nil end
		if detailGui then detailGui:Destroy(); detailGui = nil end
	end

	for idx, item in ipairs(rewards) do
		local rc = Theme.GetRarityColor(item.rarity)

		local card = Instance.new("TextButton")
		card.Size = UDim2.new(1, 0, 1, 0)
		card.BackgroundColor3 = rc
		card.BackgroundTransparency = 0.75
		card.BorderSizePixel = 0
		card.Text = ""
		card.AutoButtonColor = true
		card.LayoutOrder = idx
		card.Parent = lootGrid
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 4)
		local cardStroke = Instance.new("UIStroke", card)
		cardStroke.Color = rc
		cardStroke.Thickness = 1.5

		-- Level badge (top-left)
		local lvBg = Instance.new("Frame")
		lvBg.Size = item.isCard and UDim2.new(0, 48, 0, 14) or UDim2.new(0, 36, 0, 14)
		lvBg.Position = UDim2.new(0, 2, 0, 2)
		lvBg.BackgroundColor3 = Theme.Colors.BadgeBg
		lvBg.BackgroundTransparency = 0.3
		lvBg.BorderSizePixel = 0
		lvBg.ZIndex = 3
		lvBg.Parent = card
		Instance.new("UICorner", lvBg).CornerRadius = UDim.new(0, 3)
		local CARD_BADGE = {
			SkillCard = "SKILL",
			AugmentCard = "AUGMENT",
			Doctrine = "DOCTRINE",
			Consumable = "ITEM",
		}
		local badgeText = "Lv." .. (item.itemLevel or 1)
		if item.isCard and item.category then
			badgeText = CARD_BADGE[item.category] or item.category
		end
		local lvl = Instance.new("TextLabel")
		lvl.Size = UDim2.fromScale(1, 1)
		lvl.BackgroundTransparency = 1
		lvl.Font = Theme.Font.Mono
		lvl.TextSize = Theme.Text.Tiny()
		lvl.TextColor3 = Theme.Colors.TextSecondary
		lvl.TextXAlignment = Enum.TextXAlignment.Center
		lvl.Text = badgeText
		lvl.ZIndex = 3
		lvl.Parent = lvBg

		-- Icon (center) -- use archetype image if available
		local iconId = item.icon or HAND_ICONS[item.handClass]
		if iconId and string.find(iconId, "rbxassetid://") then
			local img = Instance.new("ImageLabel")
			img.Size = UDim2.new(1, -4, 1, -4)
			img.Position = UDim2.new(0, 2, 0, 2)
			img.BackgroundTransparency = 1
			img.Image = iconId
			img.ScaleType = Enum.ScaleType.Crop
			img.Parent = card
		else
			local icon = Instance.new("TextLabel")
			icon.Size = UDim2.new(1, 0, 0, 28)
			icon.Position = UDim2.new(0, 0, 0.15, 0)
			icon.BackgroundTransparency = 1
			icon.Font = Theme.Font.Primary
			icon.TextSize = 24
			icon.TextColor3 = Theme.Colors.TextPrimary
			icon.TextXAlignment = Enum.TextXAlignment.Center
			icon.Text = "[*]"
			icon.Parent = card
		end

		-- Name strip (bottom)
		local nameBg = Instance.new("Frame")
		nameBg.Size = UDim2.new(1, 0, 0, 14)
		nameBg.Position = UDim2.new(0, 0, 1, -14)
		nameBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		nameBg.BackgroundTransparency = 0.4
		nameBg.BorderSizePixel = 0
		nameBg.ZIndex = 3
		nameBg.Parent = card
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -4, 1, 0)
		nameLabel.Position = UDim2.new(0, 2, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Theme.Font.Primary
		nameLabel.TextSize = Theme.Text.Small()
		nameLabel.TextColor3 = Theme.Colors.TextPrimary
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Text = item.name or "?"
		nameLabel.ZIndex = 3
		nameLabel.Parent = nameBg

		-- Click -> detail view
		card.MouseButton1Click:Connect(function()
			closeRewardDetail()

			-- Build detail panel (left side, like loadout detail)
			-- Detail overlay: separate ScreenGui with higher DisplayOrder
			detailGui = Instance.new("ScreenGui")
			detailGui.Name = "LootDetailOverlay"
			detailGui.ResetOnSpawn = false
			detailGui.DisplayOrder = 93
			detailGui.Parent = player:WaitForChild("PlayerGui")

			detailFrame = Theme.MakePanel("LootDetail",
				UDim2.new(0.55, 0, 0.90, 0),
				UDim2.new(0, 6, 0.5, 0),
				Vector2.new(0, 0.5),
				detailGui)
			detailFrame.ClipsDescendants = true

			local dp = Instance.new("UIPadding", detailFrame)
			dp.PaddingTop = UDim.new(0, 10)
			dp.PaddingLeft = UDim.new(0, 12)
			dp.PaddingRight = UDim.new(0, 12)
			dp.PaddingBottom = UDim.new(0, 10)

			if item.isCard then
				-- Non-equipment card detail (simple text layout)
				local scrollArea = Instance.new("ScrollingFrame")
				scrollArea.Size = UDim2.new(1, 0, 1, 0)
				scrollArea.BackgroundTransparency = 1
				scrollArea.BorderSizePixel = 0
				scrollArea.ScrollBarThickness = 3
				scrollArea.ScrollBarImageColor3 = Theme.Colors.TextSecondary
				scrollArea.CanvasSize = UDim2.new(0, 0, 0, 0)
				scrollArea.AutomaticCanvasSize = Enum.AutomaticSize.Y
				scrollArea.Parent = detailFrame
				local layout = Instance.new("UIListLayout", scrollArea)
				layout.SortOrder = Enum.SortOrder.LayoutOrder
				layout.Padding = UDim.new(0, 6)

				local rc = Theme.GetRarityColor(item.rarity)
				local CARD_TYPE_LABEL = {
					SkillCard = "Skill Card", AugmentCard = "Augment Card",
					Doctrine = "Doctrine", Consumable = "Consumable",
				}
				local catLabel = CARD_TYPE_LABEL[item.category] or "Card"

				makeLabel(scrollArea, catLabel, { font = Theme.Font.Mono, textSize = Theme.Text.Tiny(), color = Theme.Colors.TextSecondary, order = 1 })
				makeLabel(scrollArea, item.name or "Unknown", { font = Theme.Font.PrimaryBold, textSize = Theme.Text.Title(), color = rc, order = 2 })
				makeLabel(scrollArea, item.rarity or "Common", { font = Theme.Font.Mono, textSize = Theme.Text.Small(), color = rc, order = 3 })

				-- Description
				if item.desc and item.desc ~= "" then
					local descLbl = makeLabel(scrollArea, item.desc, {
						font = Theme.Font.Primary, textSize = Theme.Text.Body(),
						color = Theme.Colors.TextPrimary, order = 5, wrap = true,
					})
					descLbl.Size = UDim2.new(1, 0, 0, 60)
					descLbl.AutomaticSize = Enum.AutomaticSize.Y
				end

				-- Category-specific fields
				if item.category == "SkillCard" then
					if item.mpCost then makeLabel(scrollArea, "MP Cost: " .. item.mpCost, { font = Theme.Font.Mono, textSize = Theme.Text.Small(), color = Theme.Colors.TextSecondary, order = 10 }) end
					if item.element then makeLabel(scrollArea, "Element: " .. item.element, { font = Theme.Font.Mono, textSize = Theme.Text.Small(), color = Theme.Colors.TextSecondary, order = 11 }) end
				elseif item.category == "AugmentCard" then
					if item.family then makeLabel(scrollArea, "Family: " .. item.family, { font = Theme.Font.Mono, textSize = Theme.Text.Small(), color = Theme.Colors.TextSecondary, order = 10 }) end
				elseif item.category == "Doctrine" then
					if item.passiveName then makeLabel(scrollArea, "Passive: " .. item.passiveName, { font = Theme.Font.PrimaryBold, textSize = Theme.Text.Small(), color = Theme.Colors.TextGold, order = 10 }) end
					if item.passiveEffect then
						local peLbl = makeLabel(scrollArea, item.passiveEffect, { font = Theme.Font.Primary, textSize = Theme.Text.Tiny(), color = Theme.Colors.TextSecondary, order = 11, wrap = true })
						peLbl.Size = UDim2.new(1, 0, 0, 40)
						peLbl.AutomaticSize = Enum.AutomaticSize.Y
					end
				elseif item.category == "Consumable" then
					if item.conCategory then makeLabel(scrollArea, "Type: " .. item.conCategory, { font = Theme.Font.Mono, textSize = Theme.Text.Small(), color = Theme.Colors.TextSecondary, order = 10 }) end
					if item.maxCharges then makeLabel(scrollArea, "Charges: " .. item.maxCharges, { font = Theme.Font.Mono, textSize = Theme.Text.Small(), color = Theme.Colors.TextSecondary, order = 11 }) end
				end
			else
				-- Equipment detail (existing path)
				local uiItem = {
					id = item.name .. "_loot",
					name = item.name or "Unknown",
					cat = item.isArmor and (({Body="Torso",Gloves="Arms",Feet="Legs"})[item.slot] or item.slot or "Accessory")
						or (item.handClass == "Off-Hand" and "OffHand" or "MainHand"),
					sub = item.handClass or "1H",
					hands = item.handClass,
					lv = item.itemLevel or 1,
					rarity = item.rarity or "Common",
					icon = item.icon or HAND_ICONS[item.handClass] or "[*]",
					qty = 1,
					isWeapon = item.isWeapon or (item.category == "Weapon"),
					tags = {},
					baseStats = {
						Attack = item.damage or 0,
						Range = (item.minRange or 1) .. "-" .. (item.maxRange or 1),
						Defense = item.defense or 0,
						WT = item.wt or 0,
						RTDelay = item.rtDelay or 0,
					},
					passives = {},
					bonusStats = item.bonusStats or {},
					bonusPassives = item.bonusPassives or {},
					flavor = "",
				}
				if item.handClass then table.insert(uiItem.tags, item.handClass) end
				if item.isArmor and item.slot then
					table.insert(uiItem.tags, item.slot)
				elseif item.equipCategory and item.equipCategory ~= "OffHand" and item.equipCategory ~= "Weapon" then
					table.insert(uiItem.tags, item.equipCategory)
				end
				if item.projectileType then
					table.insert(uiItem.tags, item.projectileType)
				elseif uiItem.isWeapon then
					table.insert(uiItem.tags, "Melee")
				end
				if item.element then table.insert(uiItem.tags, item.element) end
				if item.nativePassiveId then
					table.insert(uiItem.passives, {
						name = item.nativePassiveId,
						icon = "[*]",
						desc = item.nativePassiveDesc or "",
					})
				elseif item.passiveName and item.passiveName ~= "" then
					table.insert(uiItem.passives, {
						name = item.passiveName,
						icon = "[*]",
						desc = item.passiveDesc or "",
					})
				end
				LoadoutScreen.BuildItemDetail(detailFrame, uiItem)
			end

			-- Show BACK button in the button bar
			rewardBackBtn.Visible = true
		end)
	end

	-- ============ BUTTON BAR (bottom-right, Theme.FooterBar standard) ============
	local fb = Theme.FooterBar
	local btnBar = Instance.new("Frame")
	btnBar.Name = "RewardBtnBar"
	btnBar.BackgroundTransparency = 1
	btnBar.AnchorPoint = Vector2.new(1, 1)
	btnBar.Position = UDim2.new(1, -fb.PAD, 1, -fb.PAD)
	btnBar.Parent = gui

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, fb.BTN_GAP)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = btnBar

	-- 1st from right: CONTINUE (Primary)
	local continueBtn = Theme.MakeButton(btnBar, "CONTINUE", "Primary", function()
		closeRewardDetail()
		if rewardGui then rewardGui:Destroy(); rewardGui = nil end
		BattleEvents.RewardContinue:FireServer()
	end, { size = UDim2.new(0, fb.BTN_W, 0, fb.BTN_H) })
	continueBtn.LayoutOrder = 2

	-- 2nd from right: BACK (Secondary, hidden by default)
	rewardBackBtn = Theme.MakeButton(btnBar, "BACK", "Secondary", function()
		closeRewardDetail()
		rewardBackBtn.Visible = false
	end, { size = UDim2.new(0, fb.BTN_W, 0, fb.BTN_H) })
	rewardBackBtn.LayoutOrder = 1
	rewardBackBtn.Visible = false

	btnBar.Size = UDim2.new(0, 2 * fb.BTN_W + fb.BTN_GAP, 0, fb.BTN_H)
end)

--------------------------------------------------
-- LOADOUT HUB EVENT HANDLER
--------------------------------------------------

BattleEvents.LoadoutHubOpen.OnClientEvent:Connect(function(data)
	local phase = data and data.phase or "PostBattle"
	-- Open new Loadout Screen (Slice 7) instead of old hub
	if _G.CTRBLXAI_OpenLoadout then
		_G.CTRBLXAI_OpenLoadout()
	else
		-- Fallback to old hub if new screen not loaded yet
		createLoadoutHub(phase)
	end
end)

-- Deployment phase: populate unitData with enemy/player positions
-- so processTileClick can find units for the inspector.
BattleEvents.DeploymentPhase.OnClientEvent:Connect(function(data)
	-- Add enemy units to unitData (they have fixed positions)
	if data.enemyUnits then
		for _, eu in ipairs(data.enemyUnits) do
			unitData[eu.id] = {
				id        = eu.id,
				name      = eu.name,
				side      = eu.side or "Enemy",
				tileX     = eu.tileX,
				tileY     = eu.tileY,
				isAlive   = true,
				currentHp = 0,
				maxHp     = 0,
			}
		end
	end
	print(string.format("[BVC] DeploymentPhase: %d enemy units added to unitData",
		data.enemyUnits and #data.enemyUnits or 0))
end)

-- When a player unit is deployed, add it to unitData for inspector access
BattleEvents.UnitDeployed.OnClientEvent:Connect(function(data)
	if data.unitId and data.tileX and data.tileY then
		if not unitData[data.unitId] then
			unitData[data.unitId] = { id = data.unitId, name = data.unitId, side = "Player", isAlive = true, currentHp = 0, maxHp = 0 }
		end
		unitData[data.unitId].tileX = data.tileX
		unitData[data.unitId].tileY = data.tileY
	end
end)

-- When a player unit is undeployed, clear its tile position
BattleEvents.UnitUndeployed.OnClientEvent:Connect(function(data)
	if data.unitId and unitData[data.unitId] then
		unitData[data.unitId].tileX = 0
		unitData[data.unitId].tileY = 0
	end
end)
-- Receive generated map data (terrain/elevation/blockers) from server
BattleEvents.MapDataSync.OnClientEvent:Connect(function(mapData)
	if mapData and GameConstants.SetGeneratedMap then
		GameConstants.SetGeneratedMap(mapData)
		-- Update map dimensions and offsets when server sends new size
		-- (e.g. Regenerate switching T01 30×20 → T04 20×20).
		if mapData.mapWidth and mapData.mapHeight then
			MAP_WIDTH   = mapData.mapWidth
			MAP_HEIGHT  = mapData.mapHeight
			MAP_OFFSET_X = -(MAP_WIDTH  * TILE_SIZE) / 2
			MAP_OFFSET_Z = -(MAP_HEIGHT * TILE_SIZE) / 2
		end
		-- Also update BVC's local elevation map so getElevation() returns correct values
		-- before BattleStarted fires (e.g. during view mode / tile inspector)
		if mapData.elevationGrid then elevationMap = mapData.elevationGrid end
		-- Map changed: drop cached elevation labels so Top view rebuilds them.
		if elevLabelFolder then elevLabelFolder:Destroy(); elevLabelFolder = nil end
		-- Init VFX post-processing + biome atmosphere
		local mf = workspace:FindFirstChild("TemplateViewerMap")
		if mf then mapFolder = mf end  -- Update module-level ref for tile selection
		local biome = mf and mf:GetAttribute("BiomeId") or "Plains"
		-- Ensure dev panel (view mode buttons) is available as soon as a map exists,
		-- not just after BattleStarted.  Safe to call multiple times — it destroys
		-- the old panel first.
		createDevCameraPanel()
		if VFXController then pcall(VFXController.Init, biome) end
		-- Place persistent waterfall splash VFX at waterfall bases (visual-only).
		placeWaterfallSplashes()
	print("[BattleVisualClient] MapDataSync received — terrain/elevation updated on client")
	-- Initialize terrain-conforming tile highlights
	if TileHL then
		local mf = workspace:FindFirstChild("TemplateViewerMap")
		local mw = mapData.width or MAP_WIDTH
		local mh = mapData.height or MAP_HEIGHT
		local mOffX = -(mw * TILE_SIZE) / 2
		local mOffZ = -(mh * TILE_SIZE) / 2
		TileHL.Init({
			mapFolder    = mf,
			tileSize     = TILE_SIZE,
			mapOffsetX   = mOffX,
			mapOffsetZ   = mOffZ,
			visualFolder = visualFolder,
		})
		-- Set styles with Theme colors
		TileHL.SetStyles({
			move     = { color = Theme.Colors.TileMove,    transparency = 0.50, material = Enum.Material.Neon },
			target   = { color = Theme.Colors.TileTarget,  transparency = 0.40, material = Enum.Material.Neon },
			selected = { color = Theme.Colors.TileSelected, transparency = 0.25, material = Enum.Material.Neon },
			aoe      = { color = Theme.Colors.TileAOE,     transparency = 0.40, material = Enum.Material.Neon },
			invalid  = { color = Theme.Colors.TileInvalid,  transparency = 0.65, material = Enum.Material.SmoothPlastic },
			current  = { color = Theme.Colors.Info,         transparency = 0.40, material = Enum.Material.Neon },
			deploy   = { color = Theme.Colors.Player,       transparency = 0.40, material = Enum.Material.Neon },
			path     = { color = Color3.fromRGB(100, 180, 255), transparency = 0.30, material = Enum.Material.Neon },
			pathDest = { color = Color3.fromRGB(240, 200, 60),  transparency = 0.15, material = Enum.Material.Neon },
		})
	end
	end
end)

--------------------------------------------------
-- FACING SYSTEM — Client handlers
--------------------------------------------------

-- Track facing per unit for local display
local function updateUnitFacing(unitId, facing)
	if unitData[unitId] then
		unitData[unitId].facing = facing
	end
	-- Rotate the model + update the ground chevron so the choice is visible.
	orientUnitToFacing(unitId, facing)
end

-- FacingChanged: server broadcasts when a unit's facing changes
BattleEvents.FacingChanged.OnClientEvent:Connect(function(data)
	if data and data.unitId and data.facing then
		updateUnitFacing(data.unitId, data.facing)
	end
end)

-- ItemUsed: server broadcasts when a unit uses a consumable item.
-- Updates the target's HP/MP bars (the effect already applied server-side),
-- shows floating combat text, and logs the usage.
BattleEvents.ItemUsed.OnClientEvent:Connect(function(data)
	if not data then return end
	local actorName  = (data.actorId and unitData[data.actorId] and unitData[data.actorId].name)
		or data.actorName or "?"
	local targetName = (data.targetId and unitData[data.targetId] and unitData[data.targetId].name)
		or data.targetName or "?"
	local amount     = data.amount or 0
	local effectType = data.effectType or ""
	-- SFX: map the item's effect to a sound bucket (payload carries effectType,
	-- not the consumable category). HpRestore/MpRestore -> Recovery, Damage ->
	-- Damage, anything else -> Default.
	if SoundController then
		local _cat = "Default"
		if effectType == "HpRestore" or effectType == "MpRestore" then _cat = "Recovery"
		elseif effectType == "Damage" then _cat = "Damage" end
		SoundController.PlayItem(_cat)
	end
	-- Base animation: the actor plays a generic item-use motion (free-default
	-- stand-in; R15 models only, cylinders no-op).
	do local _au = data.actorId and unitTokens[data.actorId]; if _au then playUnitAnim(_au, "ItemUse", { stopAfter = 0.7 }) end end

	-- Refresh the target unit's bars from the effect result. The server already
	-- mutated HP/MP; pull the freshest values we know client-side and nudge bars.
	local tgt = data.targetId and unitData[data.targetId] or nil
	local tgtToken = data.targetId and unitTokens[data.targetId] or nil

	if effectType == "HpRestore" and tgt then
		tgt.currentHp = math.min((tgt.maxHp or amount), (tgt.currentHp or 0) + amount)
		updateHpBar(data.targetId, tgt.currentHp, tgt.maxHp or tgt.currentHp)
		if tgtToken and tgtToken.part then showDamageText(tgtToken.part.Position, amount, true) end
	elseif effectType == "Damage" and tgt then
		tgt.currentHp = math.max(0, (tgt.currentHp or 0) - amount)
		updateHpBar(data.targetId, tgt.currentHp, tgt.maxHp or 1)
		if tgtToken and tgtToken.part then showDamageText(tgtToken.part.Position, amount, false) end
	elseif effectType == "MpRestore" and tgt then
		tgt.currentMp = math.min((tgt.maxMp or amount), (tgt.currentMp or 0) + amount)
		updateMpBar(data.targetId, tgt.currentMp, tgt.maxMp or tgt.currentMp)
		if tgtToken and tgtToken.part then
			showFloatingText(tgtToken.part.Position, "+"..amount.." MP", Theme.Colors.Info or Color3.fromRGB(80,160,255), 1.0)
		end
	elseif tgtToken and tgtToken.part then
		-- Status cure / apply / other: show a small info popup
		local info = data.statusId and tostring(data.statusId) or (effectType ~= "" and effectType or "used")
		showFloatingText(tgtToken.part.Position, info, Theme.Colors.TextSecondary or Color3.fromRGB(200,200,200), 1.0)
	end

	-- Build a readable effect summary for the battle log.
	local summary
	if effectType == "HpRestore" then
		summary = "healed " .. targetName .. " +" .. amount .. " HP"
	elseif effectType == "MpRestore" then
		summary = "restored " .. amount .. " MP to " .. targetName
	elseif effectType == "StatusCure" then
		summary = "cured " .. (data.statusId or "status") .. " on " .. targetName
	elseif effectType == "StatusApply" then
		summary = "applied " .. (data.statusId or "status") .. " to " .. targetName
	elseif effectType == "Damage" then
		summary = "dealt " .. amount .. " " .. (data.element or "") .. " to " .. targetName
	else
		summary = "on " .. targetName
	end
	BattleHUD.AddLogEntry(string.format("%s used %s — %s", actorName, data.itemName or "item", summary))
end)

-- FacingPrompt: server asks player to choose a direction via the ground ring.
-- Used for Guard/Wait facing AND for siege aiming (Ballista cardinal bolt —
-- aimMode="siege" in the payload); renders the same ring for any FacingPrompt
-- carrying a unitId + known position.
BattleEvents.FacingPrompt.OnClientEvent:Connect(function(data)
	if not data or not data.unitId then return end

	-- World-space facing arrows (camera-proof). 8 flat SurfaceGui arrow planes
	-- sit on the ground ringing the unit, each pointing along its WORLD direction via
	-- GameConstants.FACING_VECTORS (dx,dy -> world X,Z). Because they live in 3D
	-- space they rotate WITH the map, so orbiting the camera never changes which
	-- world direction an arrow means. Replaces the old screen-fixed 3x3 button
	-- grid, where screen-up stopped meaning world-north once the camera orbited.
	local udata = unitData[data.unitId]
	if not udata or not udata.tileX or not udata.tileY then return end
	local tx, ty = udata.tileX, udata.tileY

	local ARROW_RING   = 8.25  -- studs from tile center out to each arrow (25% reduction; ring+plane scaled together so 2*ring*sin(22.5) >= plane still holds)
	local ARROW_HEIGHT = 5.5   -- studs above ground so arrows clear SURROUNDING higher terrain (raised from 2.0; matches overhead-indicator clearance). Note: only lifts the arrows physically — a unit boxed by very tall cliffs could still occlude the click target. Future top-view/minimap facing UI is the full ceiling-buster.
	local ARROW_LEN    = 2.2
	local ARROW_WID    = 1.4


	local baseWX  = MAP_OFFSET_X + (tx - 0.5) * TILE_SIZE
	local baseWZ  = MAP_OFFSET_Z + (ty - 0.5) * TILE_SIZE
	local groundY = groundSurfaceY(tx, ty) + ARROW_HEIGHT

	local folder = Instance.new("Folder")
	folder.Name = "FacingArrows"
	folder.Parent = workspace

	local chosen = false
	local conns = {}  -- PRF-004: track connections, disconnect on cleanup

	-- Hide THIS unit's overhead facing arrow while its choice arrows are on screen.
	-- The choice arrows use the SAME green arrow image, so they now communicate the
	-- unit's facing directly and the overhead one would be redundant clutter. It is
	-- restored on cleanup (choice made or prompt torn down); FacingChanged then
	-- re-orients it to the chosen direction.
	local promptToken = unitTokens[data.unitId]
	local overheadGlyph = promptToken and promptToken.facePad and promptToken.facePad:FindFirstChild("Glyph", true)
	if overheadGlyph then overheadGlyph.Visible = false end

	local function cleanup()
		for _, c in conns do c:Disconnect() end
		table.clear(conns)
		if overheadGlyph then overheadGlyph.Visible = true end
		if folder and folder.Parent then folder:Destroy() end  -- MEM-002
	end

	local ARROW_PLANE = 6.0   -- studs; flat plane footprint per arrow (25% reduction; ring reduced in lockstep to keep no-overlap)

	for dir, vec in GameConstants.FACING_VECTORS do
		local mag = math.sqrt(vec.dx * vec.dx + vec.dy * vec.dy)
		local nx, nz = vec.dx / mag, vec.dy / mag
		local pos = Vector3.new(baseWX + nx * ARROW_RING, groundY, baseWZ + nz * ARROW_RING)

		-- Flat INVISIBLE carrier plane. A SurfaceGui on its Top face draws the
		-- arrow glyph, so there is no visible part surface (no studs, ever) -
		-- same stud-free technique the tile-highlight frames use. Kept axis-
		-- aligned; the glyph is rotated in 2D to point along its world dir, so
		-- it stays camera-proof (rotates WITH the map, not the screen).
		-- NET-004: all properties before parenting.
		local plane = Instance.new("Part")
		plane.Name         = "Face_" .. dir
		plane.Anchored     = true
		plane.CanCollide   = false
		plane.CanQuery     = true    -- ClickDetector needs it hittable
		plane.CastShadow   = false
		plane.Transparency = 1       -- invisible carrier; SurfaceGui does the drawing
		plane.Size         = Vector3.new(ARROW_PLANE, 0.1, ARROW_PLANE)
		plane.CFrame       = CFrame.new(pos)

		local sg = Instance.new("SurfaceGui")
		sg.Face           = Enum.NormalId.Top
		sg.SizingMode     = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud  = 48
		sg.LightInfluence = 0        -- fullbright glyph, ignores world lighting
		sg.AlwaysOnTop    = true   -- draw the arrow glyph OVER terrain so it is never visually buried (click target is still the carrier Part below)
		sg.Parent         = plane

		-- Use the SAME green arrow image as the overhead facing indicator, so the
		-- choose-facing arrows and the per-unit facing arrow are visually identical.
		-- This teaches the player that a green arrow == facing direction, and a
		-- full-bleed image reads much larger than the old TextScaled triangle.
		local lbl = Instance.new("ImageLabel")
		lbl.Size                   = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Image                  = "rbxassetid://111086634875547"
		lbl.ScaleType              = Enum.ScaleType.Fit
		-- Same rotation convention as the overhead indicator (+270 for the
		-- down-pointing green art) so each choice arrow points along its world dir.
		lbl.Rotation               = math.deg(math.atan2(vec.dx, -vec.dy)) + 270
		-- No UIStroke: a stroke on the full-bleed ImageLabel traced the label's
		-- rectangular border (visible squares around each arrow), not the arrow shape.
		-- The green arrows read fine against terrain on their own.
		lbl.Parent                 = sg

		local cd = Instance.new("ClickDetector")
		cd.MaxActivationDistance = 1000
		cd.Parent = plane

		plane.Parent = folder

		table.insert(conns, cd.MouseClick:Connect(function()
			if chosen then return end
			chosen = true
			BattleEvents.SetFacing:FireServer({ unitId = data.unitId, facing = dir })
			print(string.format("[BVC] Facing chosen: %s -> %s", data.unitId, dir))
			cleanup()
		end))
	end

	-- Turn-based: no timer. Arrows stay until the player chooses a facing.
end)
