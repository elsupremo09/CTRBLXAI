--!strict
-- UGCOutfitService.lua
-- CTRBLXAI | UGC Rental & Ownership — availability, enemy outfits, model looks
--
-- 1) AVAILABILITY (ugc_rules curation_eligibility): a curated item is usable only
--    if MarketplaceService:GetProductInfo says it is for sale, not a limited /
--    resale-only item, not sold out, and its AssetTypeId fits its slot.
--    Cached; FAILS CLOSED (unknown / error = not available).
-- 2) ENEMY OUTFITS (ugc_rules Enemy Outfits): per battle, up to
--    ENEMY_DISTINCT_ITEMS_PER_BATTLE distinct items — half pushed toward items the
--    player has NOT marked and does NOT own, the rest random from the curated
--    pool (owned items may appear only there). Pushed pool short -> random fills.
--    Each enemy wears up to ENEMY_ITEMS_PER_ENEMY, one per slot, race slot blocks
--    apply. Deterministic: the caller passes a seeded Random and pools are sorted.
-- 3) LOOKS ON MODELS (enemy_outfit_apply_point: server-side at spawn): watches
--    workspace.UnitModels and dresses each "Unit_<id>" R15 model as it is
--    parented (covers every spawn path in Main.server.lua). Accessories come from
--    a per-asset template cache in ServerStorage (MEM-003) built once with
--    Players:CreateHumanoidModelFromDescription, so the race rig's own body,
--    colours and scale are never touched. Clones reuse one mesh per asset
--    (DRW-002).
--
-- Injections (ARC-004 / ARC-006, nil-safe):
--   SetStateProvider(UGCService)  -- IsOwned / IsMarked / IsSlotAllowed / GetUnitLookIds

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Content = ReplicatedStorage:WaitForChild("Content")
local UGCCatalogData = require(Content:WaitForChild("UGCCatalogData"))
local RaceData = require(Content:WaitForChild("RaceData")) :: any

local UGCOutfitService = {}

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

local AVAILABLE_TTL = 600     -- seconds before re-checking a for-sale item
local FAILED_RETRY_TTL = 60   -- seconds before re-checking after an API error
local CHECK_SPACING = 0.1     -- seconds between GetProductInfo calls (throttle-friendly)
local MODELS_FOLDER_NAME = "UnitModels"
local CACHE_FOLDER_NAME = "UGCAssetCache"
local ASSET_ATTRIBUTE = "UGCAssetId"

-- Rigid accessory AssetType name -> HumanoidDescription property (Roblox API).
local RIGID_PROPERTY: { [string]: string } = {
	Hat = "HatAccessory",
	HairAccessory = "HairAccessory",
	FaceAccessory = "FaceAccessory",
	NeckAccessory = "NeckAccessory",
	ShoulderAccessory = "ShouldersAccessory",
	FrontAccessory = "FrontAccessory",
	BackAccessory = "BackAccessory",
	WaistAccessory = "WaistAccessory",
}

-- Layered clothing AssetType name -> Enum.AccessoryType name (Roblox API).
local LAYERED_TYPE: { [string]: string } = {
	TShirtAccessory = "TShirt",
	ShirtAccessory = "Shirt",
	PantsAccessory = "Pants",
	JacketAccessory = "Jacket",
	SweaterAccessory = "Sweater",
	ShortsAccessory = "Shorts",
	LeftShoeAccessory = "LeftShoe",
	RightShoeAccessory = "RightShoe",
	DressSkirtAccessory = "DressSkirt",
}

-- Enum.AssetType value -> allowed name, built from the data module (no literals).
local TYPE_NAME_BY_ID: { [number]: string } = {}
for _, names in UGCCatalogData.SLOT_ASSET_TYPES do
	for _, name in names do
		local ok, enumItem = pcall(function()
			return (Enum.AssetType :: any)[name]
		end)
		if ok and enumItem then
			TYPE_NAME_BY_ID[enumItem.Value] = name
		else
			warn(`[UGCOutfitService] Unknown Enum.AssetType '{name}' in SLOT_ASSET_TYPES`)
		end
	end
end

--------------------------------------------------
-- STATE
--------------------------------------------------

type Availability = { isAvailable: boolean, typeName: string?, checkedAt: number, reason: string? }

local _availability: { [number]: Availability } = {}
local _templates: { [number]: Instance } = {}
local _loadingWaiters: { [number]: { thread } } = {}
local _enemyLooks: { [string]: { number } } = {}
local _cacheFolder: Folder? = nil
local _watchConn: RBXScriptConnection? = nil
local _watchPlayerId: string? = nil
local _isRefreshing = false

local _state: any = nil
function UGCOutfitService.SetStateProvider(svc: any) _state = svc end

--------------------------------------------------
-- AVAILABILITY
--------------------------------------------------

local function slotAccepts(slot: string, typeName: string): boolean
	local names = UGCCatalogData.SLOT_ASSET_TYPES[slot]
	if not names then return false end
	return table.find(names, typeName) ~= nil
end

local function evaluate(assetId: number, info: any): Availability
	local now = os.clock()
	local item = UGCCatalogData.Items[assetId]
	if type(info) ~= "table" then
		return { isAvailable = false, checkedAt = now, reason = "No product info" }
	end
	local typeName = TYPE_NAME_BY_ID[info.AssetTypeId or -1]
	if not item or not typeName or not slotAccepts(item.slot, typeName) then
		return { isAvailable = false, checkedAt = now, reason = "Asset type does not match slot" }
	end
	if info.IsForSale ~= true then
		return { isAvailable = false, typeName = typeName, checkedAt = now, reason = "Off sale" }
	end
	local collectible = info.CollectiblesItemDetails
	local isLimited = info.IsLimited == true or info.IsLimitedUnique == true
		or (type(collectible) == "table" and collectible.IsLimited == true)
	if isLimited then
		return { isAvailable = false, typeName = typeName, checkedAt = now, reason = "Limited / resale only" }
	end
	if type(info.Remaining) == "number" and info.Remaining <= 0 then
		return { isAvailable = false, typeName = typeName, checkedAt = now, reason = "Sold out" }
	end
	return { isAvailable = true, typeName = typeName, checkedAt = now }
end

-- Yields. Re-checks one item if its cache entry is stale.
function UGCOutfitService.CheckAvailability(assetId: number): boolean
	if not UGCCatalogData.Items[assetId] then return false end
	local cached = _availability[assetId]
	if cached then
		local ttl = if cached.reason == "API error" then FAILED_RETRY_TTL else AVAILABLE_TTL
		if os.clock() - cached.checkedAt < ttl then
			return cached.isAvailable
		end
	end
	local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, assetId, Enum.InfoType.Asset)
	local result: Availability
	if ok then
		result = evaluate(assetId, info)
	else
		warn(`[UGCOutfitService] GetProductInfo failed for {assetId}: {info}`)
		-- Fail closed, but keep a previously known type so cached templates still resolve.
		result = { isAvailable = false, typeName = cached and cached.typeName or nil,
			checkedAt = os.clock(), reason = "API error" }
	end
	_availability[assetId] = result
	if not result.isAvailable and result.reason ~= "API error" then
		print(`[UGCOutfitService] {assetId} excluded: {result.reason}`)
	end
	return result.isAvailable
end

-- Non-yielding cached answer (fail closed). Used by UGCService.
function UGCOutfitService.IsAvailable(assetId: number): boolean
	local cached = _availability[assetId]
	return cached ~= nil and cached.isAvailable
end

-- Yields. Checks every curated item; call in task.spawn at startup.
function UGCOutfitService.RefreshAvailability()
	if _isRefreshing then return end
	_isRefreshing = true
	local ids = {}
	for id in UGCCatalogData.Items do table.insert(ids, id) end
	table.sort(ids)
	local available = 0
	for _, id in ids do
		if UGCOutfitService.CheckAvailability(id) then available += 1 end
		task.wait(CHECK_SPACING)
	end
	_isRefreshing = false
	print(`[UGCOutfitService] Availability refreshed: {available}/{#ids} curated item(s) usable`)
end

--------------------------------------------------
-- ASSET TEMPLATES (ServerStorage cache, MEM-003)
--------------------------------------------------

local function cacheFolder(): Folder
	if _cacheFolder and _cacheFolder.Parent then return _cacheFolder end
	local existing = ServerStorage:FindFirstChild(CACHE_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		_cacheFolder = existing
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = CACHE_FOLDER_NAME
	f.Parent = ServerStorage -- NET-004
	_cacheFolder = f
	return f
end

local function buildDescription(assetId: number, typeName: string): HumanoidDescription?
	local desc = Instance.new("HumanoidDescription")
	if typeName == "Shirt" then
		desc.Shirt = assetId
	elseif typeName == "Pants" then
		desc.Pants = assetId
	elseif RIGID_PROPERTY[typeName] then
		(desc :: any)[RIGID_PROPERTY[typeName]] = tostring(assetId)
	elseif LAYERED_TYPE[typeName] then
		desc:SetAccessories({
			{ AssetId = assetId, AccessoryType = (Enum.AccessoryType :: any)[LAYERED_TYPE[typeName]], IsLayered = true, Order = 1 },
		}, false)
	else
		desc:Destroy()
		return nil
	end
	return desc
end

-- Yields. One template per asset per server; concurrent callers wait for the
-- first load instead of loading twice.
local function loadTemplate(assetId: number): Instance?
	local cached = _templates[assetId]
	if cached then return cached end
	local waiters = _loadingWaiters[assetId]
	if waiters then
		table.insert(waiters, coroutine.running())
		return coroutine.yield()
	end
	_loadingWaiters[assetId] = {}

	local result: Instance? = nil
	local av = _availability[assetId]
	local typeName = av and av.typeName
	local desc = typeName and buildDescription(assetId, typeName) or nil
	if desc then
		local ok, model = pcall(Players.CreateHumanoidModelFromDescription, Players, desc, Enum.HumanoidRigType.R15)
		desc:Destroy()
		if ok and model then
			local found: Instance? = nil
			if typeName == "Shirt" then
				found = model:FindFirstChildOfClass("Shirt")
			elseif typeName == "Pants" then
				found = model:FindFirstChildOfClass("Pants")
			else
				found = model:FindFirstChildOfClass("Accessory")
			end
			if found then
				found.Parent = cacheFolder()
				result = found
				_templates[assetId] = found
			else
				warn(`[UGCOutfitService] Asset {assetId} produced no wearable instance`)
			end
			model:Destroy() -- MEM-002
		else
			warn(`[UGCOutfitService] Could not load asset {assetId}: {model}`)
		end
	end

	local pending = _loadingWaiters[assetId] or {}
	_loadingWaiters[assetId] = nil
	for _, th in pending do
		task.spawn(th, result)
	end
	return result
end

local function prepareClone(template: Instance, assetId: number): Instance
	local clone = template:Clone()
	clone:SetAttribute(ASSET_ATTRIBUTE, assetId)
	-- Cosmetic only: never collide, touch or block tile/unit raycasts.
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
		end
	end
	return clone
end

-- Yields. Replaces any previous UGC on the model with assetIds. Properties are
-- set on each clone before it is parented (NET-004).
function UGCOutfitService.ApplyLook(model: Model, assetIds: { number })
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	for _, child in model:GetChildren() do
		if child:GetAttribute(ASSET_ATTRIBUTE) ~= nil then child:Destroy() end
	end
	local applied = 0
	for _, assetId in assetIds do
		local template = loadTemplate(assetId)
		if not template or model.Parent == nil then continue end
		local clone = prepareClone(template, assetId)
		if clone:IsA("Accessory") then
			humanoid:AddAccessory(clone)
		else
			-- Classic Shirt/Pants: the UGC piece replaces the rig's own one.
			local existing = model:FindFirstChildOfClass(clone.ClassName)
			if existing and existing:GetAttribute(ASSET_ATTRIBUTE) == nil then existing:Destroy() end
			clone.Parent = model
		end
		applied += 1
	end
	if applied > 0 then
		print(`[UGCOutfitService] {model.Name} wears {applied} UGC item(s)`)
	end
end

--------------------------------------------------
-- ENEMY OUTFIT PLAN
--------------------------------------------------

local function raceNameOf(unit: any): string?
	local race = unit.raceId and RaceData.GetRace(unit.raceId) or nil
	return race and race.name or nil
end

local function takeRandom(list: { number }, rng: Random): number?
	if #list == 0 then return nil end
	local i = rng:NextInteger(1, #list)
	return table.remove(list, i)
end

-- enemyUnits: array (deterministic order). rng: seeded Random owned by caller.
function UGCOutfitService.PlanEnemyOutfits(playerId: string, enemyUnits: { any }, rng: Random)
	table.clear(_enemyLooks)
	if not _state then
		warn("[UGCOutfitService] State provider not wired — no enemy outfits")
		return
	end
	local pool = {}
	for id in UGCCatalogData.Items do
		if UGCOutfitService.IsAvailable(id) then table.insert(pool, id) end
	end
	table.sort(pool)
	if #pool == 0 then
		print("[UGCOutfitService] No available curated items — enemies wear no UGC")
		return
	end

	local distinct = math.min(UGCCatalogData.ENEMY_DISTINCT_ITEMS_PER_BATTLE, #pool)
	local pushedTarget = math.floor(distinct / 2)
	local chosen: { number } = {}
	local chosenSet: { [number]: boolean } = {}

	local pushedPool = {}
	for _, id in pool do
		if not _state.IsOwned(playerId, id) and not _state.IsMarked(playerId, id) then
			table.insert(pushedPool, id)
		end
	end
	for _ = 1, pushedTarget do
		local id = takeRandom(pushedPool, rng)
		if not id then break end
		table.insert(chosen, id)
		chosenSet[id] = true
	end
	local pushedCount = #chosen

	local randomPool = {}
	for _, id in pool do
		if not chosenSet[id] then table.insert(randomPool, id) end
	end
	while #chosen < distinct do
		local id = takeRandom(randomPool, rng)
		if not id then break end
		table.insert(chosen, id)
		chosenSet[id] = true
	end

	local dressed = 0
	for _, unit in enemyUnits do
		if unit.isSummon or type(unit.id) ~= "string" then continue end
		local raceName = raceNameOf(unit)
		local order = table.clone(chosen)
		local look: { number } = {}
		local usedSlots: { [string]: boolean } = {}
		while #look < UGCCatalogData.ENEMY_ITEMS_PER_ENEMY do
			local id = takeRandom(order, rng)
			if not id then break end
			local slot = UGCCatalogData.Items[id].slot
			if not usedSlots[slot] and _state.IsSlotAllowed(raceName, slot) then
				usedSlots[slot] = true
				table.insert(look, id)
			end
		end
		if #look > 0 then
			_enemyLooks[unit.id] = look
			dressed += 1
		end
	end
	print(`[UGCOutfitService] Enemy outfits: {#chosen} distinct item(s) ({pushedCount} pushed), {dressed} enemy unit(s) dressed`)
end

--------------------------------------------------
-- MODEL WATCHER + INSPECTOR READ
--------------------------------------------------

function UGCOutfitService.GetWornIds(playerId: string, unitId: string): { number }
	local enemyLook = _enemyLooks[unitId]
	if enemyLook then return table.clone(enemyLook) end
	if _state then return _state.GetUnitLookIds(playerId, unitId) end
	return {}
end

local function onModelAdded(child: Instance)
	if not child:IsA("Model") or not _watchPlayerId then return end
	local unitId = string.match(child.Name, "^Unit_(.+)$")
	if not unitId then return end
	local ids = UGCOutfitService.GetWornIds(_watchPlayerId, unitId)
	if #ids == 0 then return end
	task.spawn(UGCOutfitService.ApplyLook, child, ids)
end

-- Starts dressing models parented to workspace.UnitModels (creates the folder if
-- needed — Main's spawn code already uses FindFirstChild first). One connection
-- per server, tracked (PRF-004).
function UGCOutfitService.WatchUnitModels(playerId: string)
	_watchPlayerId = playerId
	if _watchConn then return end
	local folder = workspace:FindFirstChild(MODELS_FOLDER_NAME)
	if not folder then
		local f = Instance.new("Folder")
		f.Name = MODELS_FOLDER_NAME
		f.Parent = workspace -- NET-004
		folder = f
	end
	_watchConn = (folder :: Instance).ChildAdded:Connect(onModelAdded)
	for _, child in (folder :: Instance):GetChildren() do
		onModelAdded(child)
	end
end

function UGCOutfitService.StopWatching()
	if _watchConn then
		_watchConn:Disconnect()
		_watchConn = nil
	end
end

return UGCOutfitService
