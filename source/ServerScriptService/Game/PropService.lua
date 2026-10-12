--!strict
-- PropService.lua
-- CTRBLXAI | Slice 7 (visual polish) — decorative prop placement. VISUAL ONLY.
--
-- Places two prop families into a rendered map folder:
--   1. Blocker props on OBS wall tiles (already impassable — nothing changes).
--   2. Tile props (ground clutter) on free, passable tiles.
--
-- Guarantees:
--   * Never reads or writes passability, LoS, objects, or any game state.
--   * Every part: Anchored, CanCollide/CanQuery/CanTouch = false, so unit-grounding
--     raycasts and tile clicks pass straight through props.
--   * Deterministic: own Random seeded from the map seed (same seed = same props).
--   * Scripts inside cloned props are stripped (props are inert decoration).
--   * Built into an unparented folder, parented LAST (NET-004). Destroyed with
--     the map folder (MEM-002).
--
-- API:
--   PropService.Populate(generatedMap, mapFolder)    → nil   (Render, TERRAIN view)
--   PropService.SetVisible(mapFolder, visible)       → nil   (SetViewMode)
--   PropService.ClearTile(mapFolder, x, y)           → nil   (runtime reshape/spawn)

local ServerStorage = game:GetService("ServerStorage")

local PropData = require(script.Parent.PropData)

local PropService = {}

local CFG = PropData.Config
local TILE_SIZE = 5            -- matches MapRenderer TILE_SIZE (see note in MapRenderer)
local PROPS_FOLDER = "DecorProps"
local RNG_SALT = 7919

type Entry = {
	names: { string },
	tag: string?,
	regions: { string }?,
	biomes: { string }?,
	notBiomes: { string }?,
	landmark: boolean?,
}
type Pos = { x: number, y: number }

--------------------------------------------------
-- ASSET LOOKUP (cached per server; variants grouped by exact name)
--------------------------------------------------

local _variantCache: { [string]: { [string]: { Instance } } } = {}
local _audited: { [string]: boolean } = {}

local function findFolder(names: { string }): Instance?
	local root = ServerStorage:FindFirstChild(CFG.ROOT_FOLDER)
	if not root then return nil end
	for _, n in names do
		local f = root:FindFirstChild(n)
		if f then return f end
	end
	return nil
end

local function getVariants(kind: string, folderNames: { string }, entries: { Entry }): { [string]: { Instance } }
	local cached = _variantCache[kind]
	if cached then return cached end
	local byName: { [string]: { Instance } } = {}
	local folder = findFolder(folderNames)
	if not folder then
		warn(`[PropService] ServerStorage/{CFG.ROOT_FOLDER}/{folderNames[1]} not found — {kind} props skipped.`)
		_variantCache[kind] = byName
		return byName
	end
	for _, child in folder:GetChildren() do
		if child:IsA("Model") or child:IsA("BasePart") then
			local list = byName[child.Name]
			if not list then
				list = {}
				byName[child.Name] = list
			end
			table.insert(list, child)
		end
	end
	-- One-time audit: table entries without a model, models without a table entry.
	if not _audited[kind] then
		_audited[kind] = true
		local listed: { [string]: boolean } = {}
		for _, e in entries do
			for _, n in e.names do
				listed[n] = true
				if not byName[n] then
					warn(`[PropService] {kind}: table lists "{n}" but no model by that name exists.`)
				end
			end
		end
		for n in byName do
			if not listed[n] and not CFG.EXCLUDED_NAMES[n] then
				warn(`[PropService] {kind}: model "{n}" is not in PropData — it will never spawn.`)
			end
		end
	end
	_variantCache[kind] = byName
	return byName
end

--------------------------------------------------
-- FILTERS
--------------------------------------------------

local function listHas(list: { string }?, value: string?): boolean
	if not list or not value then return false end
	for _, v in list do
		if v == value then return true end
	end
	return false
end

local function entryFits(e: Entry, regionType: string?, biomeId: string?): boolean
	if e.biomes and not listHas(e.biomes, biomeId) then return false end
	if e.notBiomes and listHas(e.notBiomes, biomeId) then return false end
	if e.regions and not listHas(e.regions, regionType) then return false end
	return true
end

local function shuffle<T>(rng: Random, list: { T })
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

local function isTwoTile(name: string): boolean
	return string.find(name, "1x2", 1, true) ~= nil
end

--------------------------------------------------
-- SPAWN
--------------------------------------------------

local function boundsOf(inst: Instance): (CFrame, Vector3)
	if inst:IsA("Model") then
		return inst:GetBoundingBox()
	end
	local p = inst :: BasePart
	return p.CFrame, p.Size
end

local function scaleBy(inst: Instance, f: number)
	if math.abs(f - 1) < 1e-3 then return end
	if inst:IsA("Model") then
		inst:ScaleTo(inst:GetScale() * f)
	elseif inst:IsA("BasePart") then
		inst.Size = inst.Size * f
	end
end

local function makeInert(inst: Instance)
	local all = inst:GetDescendants()
	table.insert(all, inst)
	for _, d in all do
		if d:IsA("BaseScript") or d:IsA("ModuleScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d:SetAttribute("PropBaseTransparency", d.Transparency)
		end
	end
end

-- Clone a variant, fit it, rotate (90° steps keep the footprint inside the tile),
-- and ground it by its real bounding box on the tile top.
local function spawnProp(
	template: Instance, centre: Vector3, rng: Random,
	fitToTile: boolean, scaleJitter: number, maxOffset: number,
	yawOverride: number?
): Instance?
	local clone = template:Clone()
	makeInert(clone)

	local ok = pcall(function()
		local _, size = boundsOf(clone)
		local f = 1
		if fitToTile then
			f = math.min(1, TILE_SIZE / math.max(size.X, 1e-3), TILE_SIZE / math.max(size.Z, 1e-3),
				CFG.MAX_HEIGHT / math.max(size.Y, 1e-3))
			f *= 1 - rng:NextNumber() * scaleJitter
		end
		scaleBy(clone, f)

		local _, s2 = boundsOf(clone)
		local foot = math.max(s2.X, s2.Z)
		local slack = math.max(0, (TILE_SIZE - foot) / 2)
		local off = math.min(maxOffset, slack)
		local ox = (rng:NextNumber() * 2 - 1) * off
		local oz = (rng:NextNumber() * 2 - 1) * off
		local yaw = yawOverride or (rng:NextInteger(0, 3) * math.pi / 2)

		local target = CFrame.new(centre.X + ox, centre.Y, centre.Z + oz) * CFrame.Angles(0, yaw, 0)
		if clone:IsA("Model") then
			clone:PivotTo(target)
			local bb, bs = clone:GetBoundingBox()
			local dy = centre.Y - (bb.Position.Y - bs.Y / 2)
			clone:PivotTo(clone:GetPivot() + Vector3.new(0, dy, 0))
		else
			local p = clone :: BasePart
			p.CFrame = target + Vector3.new(0, p.Size.Y / 2, 0)
		end
	end)
	if not ok then
		clone:Destroy()
		return nil
	end
	return clone
end

--------------------------------------------------
-- MAP HELPERS
--------------------------------------------------

local function buildTileLookup(mapFolder: Instance): { [string]: BasePart }
	local lookup: { [string]: BasePart } = {}
	for _, child in mapFolder:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("IsTemplateTile") then
			lookup[`{child:GetAttribute("X")},{child:GetAttribute("Y")}`] = child
		end
	end
	return lookup
end

local function tileTop(part: BasePart): Vector3
	return Vector3.new(part.Position.X, part.Position.Y + part.Size.Y / 2, part.Position.Z)
end

local function tag(inst: Instance, kind: string, x: number, y: number)
	inst:SetAttribute("PropKind", kind)
	inst:SetAttribute("PropTileX", x)
	inst:SetAttribute("PropTileY", y)
end

local DIR4 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

--------------------------------------------------
-- BLOCKER PROPS (OBS clusters)
--------------------------------------------------

local function placeBlockers(gm: any, tiles: { [string]: BasePart }, out: Folder, rng: Random): number
	local variants = getVariants("Blockers", CFG.BLOCKER_FOLDERS, PropData.Blockers :: any)
	if next(variants) == nil then return 0 end
	-- OBS DECORATION RETIRED (user ruling 2026-10-12, map_gen_rules rows 75-78): an OBS
	-- strip is EITHER a raised SPIKE (bare terrain — no props) OR a BLOCKER/BILLBOARD
	-- object materialized onto the tile (tile.object), which MapRenderer.renderBlockers
	-- draws from ServerStorage > Map Objects (or a fallback blocker part). Decorative
	-- blocker props must NEVER be layered on top of OBS tiles again (the over-decoration
	-- bug). This pass therefore places nothing; the per-cluster code below is left intact
	-- (unreferenced) in case a non-OBS decorative use is wired later.
	return 0
	--[==[ RETIRED 2026-10-12 (see the active note above). A LEVELED long comment is used
	-- because the dead body below contains chained-index syntax that forms a plain
	-- long-comment terminator and would otherwise close an unleveled comment early.
	local w, h = gm.width, gm.height
	local regionTypes = gm.regionTypeMap or {}

	local function isObs(x: number, y: number): boolean
		local row = gm.tiles[y]
		local t = row and row[x]
		return t ~= nil and (t.marker == "OBS" or t.isObstacle == true)
	end

	-- 4-way flood fill into clusters (array order → deterministic).
	local seen: { [string]: boolean } = {}
	local clusters: { { Pos } } = {}
	for y = 1, h do
		for x = 1, w do
			if isObs(x, y) and not seen[`{x},{y}`] then
				local cluster: { Pos } = {}
				local stack: { Pos } = { { x = x, y = y } }
				seen[`{x},{y}`] = true
				while #stack > 0 do
					local p = table.remove(stack) :: Pos
					table.insert(cluster, p)
					for _, d in DIR4 do
						local nx, ny = p.x + d[1], p.y + d[2]
						if nx >= 1 and nx <= w and ny >= 1 and ny <= h and isObs(nx, ny) and not seen[`{nx},{ny}`] then
							seen[`{nx},{ny}`] = true
							table.insert(stack, { x = nx, y = ny })
						end
					end
				end
				table.insert(clusters, cluster)
			end
		end
	end
	shuffle(rng, clusters)

	local uses: { [string]: number } = {}
	local soloPos: { Pos } = {}
	local placed = 0

	local function regionOf(cluster: { Pos }): string?
		local count: { [string]: number } = {}
		local best, bestN = nil, 0
		for _, p in cluster do
			local rid = gm.tiles[p.y][p.x].regionId
			local rt = rid and regionTypes[rid]
			if rt then
				count[rt] = (count[rt] or 0) + 1
				if count[rt] > bestN then best, bestN = rt, count[rt] end
			end
		end
		return best
	end

	local function soloClear(p: Pos): boolean
		for _, s in soloPos do
			if math.abs(s.x - p.x) <= 1 and math.abs(s.y - p.y) <= 1 then return false end
		end
		return true
	end

	local function candidates(regionType: string?, wantTag: string?): { string }
		local list: { string } = {}
		for _, e in PropData.Blockers :: any do
			if (wantTag == nil or e.tag == wantTag) and entryFits(e, regionType, gm.biomeId) then
				for _, n in e.names do
					local cap = if e.tag == "S" then CFG.SOLO_PER_NAME else CFG.BLOCKER_USES_PER_NAME
					if variants[n] and (uses[n] or 0) < cap then
						table.insert(list, n)
					end
				end
			end
		end
		table.sort(list)
		shuffle(rng, list)
		return list
	end

	local soloNames: { [string]: boolean } = {}
	for _, e in PropData.Blockers :: any do
		if e.tag == "S" then
			for _, n in e.names do soloNames[n] = true end
		end
	end

	local function put(name: string, p: Pos): boolean
		local part = tiles[`{p.x},{p.y}`]
		local vlist = variants[name]
		if not part or not vlist then return false end
		local v = vlist[rng:NextInteger(1, #vlist)]
		-- No resize (authored size). Free yaw + small offset so neighbours never
		-- line up like arranged decorations.
		local inst = spawnProp(v, tileTop(part), rng, false, 0, CFG.BLOCKER_MAX_OFFSET, rng:NextNumber() * 2 * math.pi)
		if not inst then return false end
		tag(inst, "Blocker", p.x, p.y)
		inst.Name = `Prop_{name}_{p.x}_{p.y}`
		inst.Parent = out
		placed += 1
		return true
	end

	for _, cluster in clusters do
		local rt = regionOf(cluster)
		if #cluster == 1 then
			local p = cluster[1]
			for _, name in candidates(rt, nil) do
				local solo = soloNames[name] == true
				if not solo or soloClear(p) then
					if put(name, p) then
						uses[name] = (uses[name] or 0) + 1
						if solo then table.insert(soloPos, p) end
						break
					end
				end
			end
		else
			-- Optional single solo on an edge tile.
			local soloTile: Pos? = nil
			if rng:NextNumber() < CFG.CLUSTER_SOLO_CHANCE then
				local edges: { Pos } = {}
				for _, p in cluster do
					for _, d in DIR4 do
						if not isObs(p.x + d[1], p.y + d[2]) then
							table.insert(edges, p)
							break
						end
					end
				end
				shuffle(rng, edges)
				local soloList = candidates(rt, "S")
				for _, p in edges do
					if soloList[1] and soloClear(p) and put(soloList[1], p) then
						uses[soloList[1]] = (uses[soloList[1]] or 0) + 1
						table.insert(soloPos, p)
						soloTile = p
						break
					end
				end
			end
			-- Groupable fill (1..N names, repeats allowed inside this cluster).
			local picks: { string } = {}
			for _, n in candidates(rt, "G") do
				if #picks >= CFG.CLUSTER_GROUPABLE_NAMES then break end
				table.insert(picks, n)
			end
			if #picks > 0 then
				for _, n in picks do uses[n] = (uses[n] or 0) + 1 end
				-- Each tile avoids the names already on its 4-neighbours (when the
				-- pick list allows) so a cluster reads as a natural mix, not a row
				-- of identical props.
				local assigned: { [string]: string } = {}
				for _, p in cluster do
					if not (soloTile and soloTile.x == p.x and soloTile.y == p.y) then
						local avoid: { [string]: boolean } = {}
						for _, d in DIR4 do
							local nn = assigned[`{p.x + d[1]},{p.y + d[2]}`]
							if nn then avoid[nn] = true end
						end
						local options: { string } = {}
						for _, n in picks do
							if not avoid[n] then table.insert(options, n) end
						end
						if #options == 0 then options = picks end
						local name = options[rng:NextInteger(1, #options)]
						if put(name, p) then assigned[`{p.x},{p.y}`] = name end
					end
				end
			end
		end
	end
	return placed
	]==]
end

--------------------------------------------------
-- TILE PROPS (ground clutter)
--------------------------------------------------

local function placeTileProps(gm: any, tiles: { [string]: BasePart }, out: Folder, rng: Random): number
	local variants = getVariants("Tiles", CFG.TILE_FOLDERS, PropData.Tiles :: any)
	if next(variants) == nil then return 0 end
	local w, h = gm.width, gm.height
	local regionTypes = gm.regionTypeMap or {}
	local used: { [string]: boolean } = {}

	local function eligible(x: number, y: number): boolean
		if x < 1 or x > w or y < 1 or y > h or used[`{x},{y}`] then return false end
		local t = gm.tiles[y][x]
		if not t or t.marker == "OBS" or t.isObstacle or t.isGap or t.isBridge then return false end
		if t.object and t.object ~= "None" then return false end
		if CFG.EXCLUDED_TERRAIN[t.terrain] then return false end
		local part = tiles[`{x},{y}`]
		return part ~= nil and part:GetAttribute("Passable") ~= false
	end

	local nameCount: { [string]: number } = {}
	local landmarks: { Pos } = {}
	local placed = 0

	local function spaced(x: number, y: number): boolean
		for _, l in landmarks do
			if math.max(math.abs(l.x - x), math.abs(l.y - y)) < CFG.LANDMARK_SPACING then return false end
		end
		return true
	end

	for y = 1, h do
		for x = 1, w do
			if eligible(x, y) then
				local t = gm.tiles[y][x]
				local density = CFG.TILE_DENSITY
				if CFG.REDUCED_MARKERS[t.marker] then density *= CFG.DEPLOY_DENSITY_MULT end
				if rng:NextNumber() < density then
					local rt = t.regionId and regionTypes[t.regionId]
					local pool: { { name: string, landmark: boolean } } = {}
					for _, e in PropData.Tiles :: any do
						if entryFits(e, rt, gm.biomeId) then
							local lm = e.landmark == true
							if not lm or (#landmarks < CFG.LANDMARK_MAX and spaced(x, y)) then
								local cap = if lm then CFG.LANDMARK_PER_NAME else CFG.TILE_PER_NAME
								for _, n in e.names do
									if variants[n] and (nameCount[n] or 0) < cap then
										table.insert(pool, { name = n, landmark = lm })
									end
								end
							end
						end
					end
					if #pool > 0 then
						local pick = pool[rng:NextInteger(1, #pool)]
						local vlist = variants[pick.name]
						local v = vlist[rng:NextInteger(1, #vlist)]
						local part = tiles[`{x},{y}`]
						local centre = tileTop(part)
						local inst: Instance? = nil
						local other: Pos? = nil
						if isTwoTile(pick.name) then
							-- Unscaled, laid across this tile and one same-height neighbour.
							local dirs = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }
							shuffle(rng, dirs)
							for _, d in dirs do
								local nx, ny = x + d[1], y + d[2]
								if eligible(nx, ny) and gm.tiles[ny][nx].elevation == t.elevation then
									local np = tiles[`{nx},{ny}`]
									local mid = (centre + tileTop(np)) / 2
									local yaw = if d[1] ~= 0 then 0 else math.pi / 2
									if rng:NextNumber() < 0.5 then yaw += math.pi end
									inst = spawnProp(v, mid, rng, false, 0, 0, yaw)
									other = { x = nx, y = ny }
									break
								end
							end
						else
							inst = spawnProp(v, centre, rng, true, CFG.TILE_SCALE_JITTER, CFG.TILE_MAX_OFFSET)
						end
						if inst then
							tag(inst, "Tile", x, y)
							inst.Name = `Prop_{pick.name}_{x}_{y}`
							if other then
								inst:SetAttribute("PropTileX2", other.x)
								inst:SetAttribute("PropTileY2", other.y)
								used[`{other.x},{other.y}`] = true
							end
							inst.Parent = out
							used[`{x},{y}`] = true
							nameCount[pick.name] = (nameCount[pick.name] or 0) + 1
							if pick.landmark then table.insert(landmarks, { x = x, y = y }) end
							placed += 1
						end
					end
				end
			end
		end
	end
	return placed
end

--------------------------------------------------
-- PUBLIC
--------------------------------------------------

function PropService.Populate(generatedMap: any, mapFolder: Instance)
	if not (generatedMap and mapFolder and generatedMap.tiles) then return end
	local existing = mapFolder:FindFirstChild(PROPS_FOLDER)
	if existing then existing:Destroy() end

	local rng = Random.new((tonumber(generatedMap.seed) or 0) + RNG_SALT)
	local tiles = buildTileLookup(mapFolder)
	local out = Instance.new("Folder")
	out.Name = PROPS_FOLDER

	local nBlock = placeBlockers(generatedMap, tiles, out, rng)
	local nTile = placeTileProps(generatedMap, tiles, out, rng)

	out.Parent = mapFolder  -- parent last (NET-004)
	print(`[PropService] Placed {nBlock} blocker prop(s), {nTile} tile prop(s)  biome={generatedMap.biomeId} seed={generatedMap.seed}`)
end

function PropService.SetVisible(mapFolder: Instance, visible: boolean)
	local f = mapFolder and mapFolder:FindFirstChild(PROPS_FOLDER)
	if not f then return end
	for _, d in f:GetDescendants() do
		if d:IsA("BasePart") then
			local base = d:GetAttribute("PropBaseTransparency")
			d.Transparency = if visible then (if typeof(base) == "number" then base else 0) else 1
		end
	end
end

-- Remove any prop standing on (x, y). Used when a tile is reshaped or a runtime
-- object spawns there, so props never float or overlap.
function PropService.ClearTile(mapFolder: Instance, x: number, y: number)
	local f = mapFolder and mapFolder:FindFirstChild(PROPS_FOLDER)
	if not f then return end
	for _, child in f:GetChildren() do
		local a = child:GetAttribute("PropTileX") == x and child:GetAttribute("PropTileY") == y
		local b = child:GetAttribute("PropTileX2") == x and child:GetAttribute("PropTileY2") == y
		if a or b then child:Destroy() end
	end
end

return PropService
