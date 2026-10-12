--!strict
-- UGCOutfitService.lua
-- CTRBLXAI | UGC Rental & Ownership — availability, enemy outfits, model looks
--
-- 1) AVAILABILITY (ugc_rules curation_eligibility): a curated item is usable only
--    if MarketplaceService:GetProductInfo says it is for sale, not a limited /
--    resale-only item, not sold out, and its AssetTypeId fits its slot.
--    Cached; FAILS CLOSED (unknown / error = not available). Paired entries
--    (ugc_rules 51): both parts must fit the slot; a bundle's own sale status
--    decides, otherwise every part must be buyable.
--    POOL (ugc_rules 49/50): StartAvailabilityLoop re-verifies every entry in the
--    background (~AVAILABILITY_REFRESH_SECONDS); battles only read the cached
--    pool and never query. Until the first pass finishes, enemies wear nothing
--    (player units are still dressed — ApplyLook checks a missing entry itself).
-- 2) ENEMY OUTFITS (ugc_rules Enemy Outfits): per battle, up to
--    ENEMY_DISTINCT_ITEMS_PER_BATTLE distinct items — half pushed toward items the
--    player does NOT have in the cart and does NOT own, the rest random from the
--    verified pool (owned items may appear only there). Off-sale items are never
--    in the pool (ugc_rules 42). Pushed pool short -> random fills.
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
--   SetStateProvider(UGCService)  -- IsOwned / IsInCart / IsSlotAllowed / GetUnitLookIds;
--                                    also hands UGCService WasLookNotWorn / ClearLookRecords
--                                    via SetLookFailureProvider (BUG-022)

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local DataStoreService = game:GetService("DataStoreService")
local Content = ReplicatedStorage:WaitForChild("Content")
local UGCCatalogData = require(Content:WaitForChild("UGCCatalogData"))
local RaceData = require(Content:WaitForChild("RaceData")) :: any

local UGCOutfitService = {}

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

local AVAILABLE_TTL = UGCCatalogData.AVAILABILITY_REFRESH_SECONDS -- re-verify every entry (ugc_rules 49)
local FAILED_RETRY_TTL = 60   -- seconds before re-checking after an API error; also the loop beat
local CHECK_SPACING = 0.1     -- seconds between GetProductInfo calls (throttle-friendly)
-- Body-color provider (injected by Main.server): given (playerId, unitId) returns
-- the unit's chosen body tint as a Color3, or nil if none. Kept as an injected
-- callback (like SetStateProvider) so UGCOutfitService needs no handle on the live
-- units table — avoids a require cycle. nil-safe at every use.
local _bodyColorGetter: any = nil
function UGCOutfitService.SetBodyColorProvider(fn: any)
	_bodyColorGetter = fn
end
local AVAIL_SAVE_SECONDS = 120 -- periodic persist of the availability cache (test-mode: own DataStore)
local AVAIL_STORE_KEY = "catalog_v1" -- single key holds the whole availability map (public catalog data)
local LOOK_LOOKUP_ATTEMPTS = 3 -- on-the-spot lookups for a PLAYER unit's look (BUG-022)
local LOOK_RETRY_BACKOFF = 1.0 -- seconds; waits 1 s then 2 s between those attempts
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

type Availability = {
	isAvailable: boolean,
	isOffSale: boolean, -- KNOWN off sale / limited / sold out ("Off sale" marker)
	typeName: string?,  -- part 1 asset type (kept across API errors for templates)
	typeName2: string?, -- part 2 asset type (paired entries)
	checkedAt: number,
	reason: string?,
	isFree: boolean?,      -- live price is 0 (ugc_rules 57); only meaningful when isAvailable
	creatorName: string?, -- part 1 creator, for the inspector worn-item popup
	priceRobux: number?,   -- live Robux price kept for the details panel + price filter/sort (nil = unknown)
	description: string?,  -- marketplace description kept for the details panel (nil = unknown)
}

local _availability: { [number]: Availability } = {}
local _templates: { [number]: Instance } = {}
local _loadingWaiters: { [number]: { thread } } = {}
local _enemyLooks: { [string]: { number } } = {}
local _enemyRaces: { [string]: string } = {} -- enemy unitId -> race name this battle (inspector preview)
-- BUG-022 (ugc_rules 50): per-battle record of player items that were / were not
-- put on a unit. Read and cleared by UGCService at battle end.
local _lookWorn: { [string]: { [number]: boolean } } = {}
local _lookFailed: { [string]: { [number]: boolean } } = {}
local _cacheFolder: Folder? = nil
local _watchConn: RBXScriptConnection? = nil
local _watchPlayerId: string? = nil
local _isRefreshing = false
local _isPoolReady = false   -- first full availability pass finished
local _isLoopStarted = false
local _saveMode: (() -> string)? = nil -- forwarded by Main (SaveService.GetMode), like UGCRatingService
local _availStore: DataStore? = nil
local _availDirty = false -- a query changed the cache since the last successful save
local _availSaveStarted = false

local _state: any = nil
function UGCOutfitService.SetStateProvider(svc: any)
	_state = svc
	-- Hands UGCService the look-failure query (ARC-006: no require cycle, no extra Main wiring).
	if svc and svc.SetLookFailureProvider then svc.SetLookFailureProvider(UGCOutfitService) end
	-- Free items (ugc_rules 57): same self-wiring, so Main needs no new line.
	if svc and svc.SetFreeProvider then svc.SetFreeProvider(UGCOutfitService.IsFree) end
	-- Details panel data (creator / Robux price / description): same self-wiring.
	if svc and svc.SetCreatorProvider then svc.SetCreatorProvider(UGCOutfitService.GetCreatorName) end
	if svc and svc.SetPriceProvider then svc.SetPriceProvider(UGCOutfitService.GetPriceRobux) end
	if svc and svc.SetDescriptionProvider then svc.SetDescriptionProvider(UGCOutfitService.GetDescription) end
end

--------------------------------------------------
-- AVAILABILITY
--------------------------------------------------

local function slotAccepts(slot: string, typeName: string): boolean
	local names = UGCCatalogData.SLOT_ASSET_TYPES[slot]
	if not names then return false end
	return table.find(names, typeName) ~= nil
end

-- Asset type of one part, if it fits the entry's slot (nil otherwise).
local function partType(item: UGCCatalogData.UGCItem, info: any): string?
	if type(info) ~= "table" then return nil end
	local typeName = TYPE_NAME_BY_ID[info.AssetTypeId or -1]
	if typeName and slotAccepts(item.slot, typeName) then return typeName end
	return nil
end

-- Why an ASSET can't be bought right now (nil = buyable): for sale, not
-- limited / resale-only, not sold out. Bundles use bundleSaleProblem below.
local function saleProblem(info: any): string?
	if type(info) ~= "table" then return "No product info" end
	if info.IsForSale ~= true then
		return "Off sale"
	end
	local collectible = info.CollectiblesItemDetails
	local isLimited = info.IsLimited == true or info.IsLimitedUnique == true
		or (type(collectible) == "table" and collectible.IsLimited == true)
	if isLimited then
		return "Limited / resale only"
	end
	-- Remaining is only a real stock count for capped items. Unlimited
	-- "Collectible Item" UGC reports Remaining=0 and TotalQuantity=0 while on sale.
	local hasStockCap = type(collectible) == "table" and type(collectible.TotalQuantity) == "number"
		and collectible.TotalQuantity > 0
	if hasStockCap and type(info.Remaining) == "number" and info.Remaining <= 0 then
		return "Sold out"
	end
	return nil
end

local function positivePrice(v: any): boolean
	return type(v) == "number" and v > 0
end

-- Why a BUNDLE can't be bought right now (nil = buyable). BUG-028 (2026-10-09):
-- GetProductInfo(id, Enum.InfoType.Bundle) returns only BundleType, Description,
-- Id, Items, Name, PriceDiscountDetails and UserBasePriceInRobux -- there is NO
-- IsForSale / IsLimited / Remaining field (confirmed from a Studio log), so the
-- asset check above always said "Off sale". A bundle is treated as buyable when
-- Roblox reports a positive Robux price; anything else fails closed.
-- KNOWN LIMITATION: in-game bundle info has no sale-status field, so a bundle
-- taken off sale but still priced may show as available. Its purchase window
-- then simply fails and nothing is granted, because ownership is always
-- verified server-side before any access or refund (SEC-002).
-- FREE BUNDLES (ugc_rules 57, 2026-10-09): a free bundle reports price 0, which the
-- positive-price rule above would call "Off sale". It counts as buyable ONLY when the
-- catalog entry carries the DB-verified isFreeBundle hint AND Roblox reports a price of
-- exactly 0 now. A priced bundle never takes this path, and a missing price still fails
-- closed. Same limitation as priced bundles: a free bundle taken off sale but still
-- reported at 0 may show as available; its purchase window fails and nothing is granted.
local function bundleSaleProblem(info: any, isFreeHint: boolean?): string?
	if type(info) ~= "table" then return "No product info" end
	if positivePrice(info.UserBasePriceInRobux) then return nil end
	if isFreeHint == true and info.UserBasePriceInRobux == 0 then return nil end
	local discount = info.PriceDiscountDetails
	if type(discount) == "table" then
		if positivePrice(discount.PriceInRobux) or positivePrice(discount.DiscountedPrice)
			or positivePrice(discount.DiscountedPriceInRobux) or positivePrice(discount.OriginalPrice)
		then
			return nil
		end
	end
	return "Off sale"
end

-- An asset is free when it is on sale at 0 Robux (some free items report no price but
-- IsPublicDomain). Unknown price = not free: the item just keeps the paid flow.
local function isFreeAsset(info: any): boolean
	if type(info) ~= "table" or info.IsForSale ~= true then return false end
	return info.PriceInRobux == 0 or (info.PriceInRobux == nil and info.IsPublicDomain == true)
end

local function creatorOf(info: any): string?
	local c = type(info) == "table" and info.Creator or nil
	return if type(c) == "table" and type(c.Name) == "string" then c.Name else nil
end

-- Live Robux price from the same GetProductInfo reply (nil = unknown). Kept for the
-- details panel and the price filter/sort — no extra API call.
local function priceOf(info: any): number?
	if type(info) ~= "table" then return nil end
	local p = info.PriceInRobux
	return if type(p) == "number" then p else nil
end

-- Marketplace description from the same reply (nil/empty = none). Trimmed for display.
local function descriptionOf(info: any): string?
	if type(info) ~= "table" then return nil end
	local d = info.Description
	if type(d) ~= "string" or d == "" then return nil end
	return d
end

local function fetchInfo(id: number, infoType: Enum.InfoType): (boolean, any)
	return pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, infoType)
end

-- Queries Roblox for one catalog entry (yields). Fails closed on any API error
-- but keeps previously known part types so cached templates still resolve.
local function queryEntry(entryId: number, previous: Availability?): Availability
	local now = os.clock()
	local item = UGCCatalogData.Items[entryId]
	local function apiError(id: number, err: any): Availability
		warn(`[UGCOutfitService] GetProductInfo failed for {id}: {err}`)
		return { isAvailable = false, isOffSale = false,
			typeName = if previous then previous.typeName else nil,
			typeName2 = if previous then previous.typeName2 else nil,
			checkedAt = now, reason = "API error" }
	end

	local ok, info = fetchInfo(entryId, Enum.InfoType.Asset)
	if not ok then return apiError(entryId, info) end
	local typeName = partType(item, info)
	local problem = saleProblem(info)
	local isFree = isFreeAsset(info)
	local creatorName = creatorOf(info)
	local priceRobux = priceOf(info)
	local description = descriptionOf(info)

	local typeName2: string? = nil
	local assetId2 = item.assetId2
	if assetId2 then
		task.wait(CHECK_SPACING)
		local ok2, info2 = fetchInfo(assetId2, Enum.InfoType.Asset)
		if not ok2 then return apiError(assetId2, info2) end
		typeName2 = partType(item, info2)
		problem = problem or saleProblem(info2)
		isFree = isFree and isFreeAsset(info2) -- a pair is free only if both parts are
	end
	if not typeName or (assetId2 ~= nil and not typeName2) then
		return { isAvailable = false, isOffSale = false, typeName = typeName, typeName2 = typeName2,
			checkedAt = now, reason = "Asset type does not match slot" }
	end

	local bundleId = item.bundleId
	if bundleId then
		-- Bundle parts are often not sold alone: the bundle's status decides.
		task.wait(CHECK_SPACING)
		local okB, infoB = fetchInfo(bundleId, Enum.InfoType.Bundle)
		if not okB then return apiError(bundleId, infoB) end
		problem = bundleSaleProblem(infoB, item.isFreeBundle)
		isFree = item.isFreeBundle == true and type(infoB) == "table" and infoB.UserBasePriceInRobux == 0
		-- Bundle price lives in UserBasePriceInRobux; its description replaces the part's.
		if type(infoB) == "table" then
			local bp = infoB.UserBasePriceInRobux
			priceRobux = if type(bp) == "number" then bp else priceRobux
			description = descriptionOf(infoB) or description
		end
	end
	if problem then
		return { isAvailable = false, isOffSale = true, typeName = typeName, typeName2 = typeName2,
			checkedAt = now, reason = problem }
	end
	return { isAvailable = true, isOffSale = false, typeName = typeName, typeName2 = typeName2, checkedAt = now,
		isFree = isFree, creatorName = creatorName, priceRobux = priceRobux, description = description }
end

-- Yields. Re-checks one entry only if its cache entry is stale.
-- Returns (isAvailable, didQuery).
local function checkEntry(entryId: number): (boolean, boolean)
	if not UGCCatalogData.Items[entryId] then return false, false end
	local cached = _availability[entryId]
	if cached then
		-- skipRecheck (known free, never goes off sale): once we have a good result,
		-- reuse it forever — the first check still runs to learn the item's part type.
		local item = UGCCatalogData.Items[entryId]
		if item and item.skipRecheck and cached.isAvailable and cached.reason ~= "API error" then
			return cached.isAvailable, false
		end
		local ttl = if cached.reason == "API error" then FAILED_RETRY_TTL else AVAILABLE_TTL
		if os.clock() - cached.checkedAt < ttl then
			return cached.isAvailable, false
		end
	end
	local result = queryEntry(entryId, cached)
	_availability[entryId] = result
	_availDirty = true -- cache changed; persist on next save beat
	if not result.isAvailable and result.reason ~= "API error" then
		print(`[UGCOutfitService] {entryId} excluded: {result.reason}`)
	end
	return result.isAvailable, true
end

-- Yields. Re-checks one entry if its cache entry is stale.
function UGCOutfitService.CheckAvailability(assetId: number): boolean
	return (checkEntry(assetId))
end

-- Non-yielding cached answer (fail closed). Used by UGCService.
function UGCOutfitService.IsAvailable(assetId: number): boolean
	local cached = _availability[assetId]
	return cached ~= nil and cached.isAvailable
end

-- Non-yielding: true only when the last check KNEW the item was off sale.
function UGCOutfitService.IsOffSale(assetId: number): boolean
	local cached = _availability[assetId]
	return cached ~= nil and cached.isOffSale
end

-- Non-yielding: true only when the last check found the item on sale at 0 Robux
-- (ugc_rules 57). Unknown / unavailable = not free (it keeps the paid flow).
function UGCOutfitService.IsFree(assetId: number): boolean
	local cached = _availability[assetId]
	return cached ~= nil and cached.isAvailable and cached.isFree == true
end

-- Non-yielding: creator name from the last check, if Roblox reported one.
function UGCOutfitService.GetCreatorName(assetId: number): string?
	local cached = _availability[assetId]
	return cached and cached.creatorName
end

-- Non-yielding: live Robux price from the last check (nil = unknown / not yet checked).
function UGCOutfitService.GetPriceRobux(assetId: number): number?
	local cached = _availability[assetId]
	return cached and cached.priceRobux
end

-- Non-yielding: marketplace description from the last check (nil = none / unknown).
function UGCOutfitService.GetDescription(assetId: number): string?
	local cached = _availability[assetId]
	return cached and cached.description
end

function UGCOutfitService.IsPoolReady(): boolean
	return _isPoolReady
end

--------------------------------------------------
-- AVAILABILITY PERSISTENCE (test-mode option 2+3)
-- Public catalog sale-status, NOT per-player ownership, so it lives in its own
-- game DataStore (mirrors UGCRatingService), never the player save. Timestamps are
-- stored as os.time() (wall clock) and converted back to this server's os.clock()
-- on load, so staleness (os.clock() - checkedAt vs TTL) still works after a restart.
-- Fails safe: any DataStore problem leaves the in-memory cache as-is (empty -> rebuild).
--------------------------------------------------

function UGCOutfitService.SetSaveModeProvider(fn: () -> string) _saveMode = fn end

local function availStore(): DataStore?
	local mode = _saveMode and _saveMode() or "memory"
	if mode == "memory" then return nil end
	if _availStore then return _availStore end
	local namespace = if mode == "studio" then "CTRBLXAI_Dev" else "CTRBLXAI_Live" -- SaveService naming
	local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, namespace .. "_UGCAvailability")
	if not ok then
		warn(`[UGCOutfitService] Availability DataStore unavailable: {store}`)
		return nil
	end
	_availStore = store
	return store
end

-- Load the saved catalog availability into memory (yields). Converts saved
-- wall-clock timestamps to this server's clock. Returns the number of entries loaded.
function UGCOutfitService.LoadPersistedAvailability(): number
	local store = availStore()
	if not store then return 0 end
	local ok, raw = pcall(store.GetAsync, store, AVAIL_STORE_KEY)
	if not ok then
		warn(`[UGCOutfitService] Availability load failed: {raw}`)
		return 0
	end
	if type(raw) ~= "table" then return 0 end
	local savedNow = tonumber(raw.savedAt)
	local entries = raw.entries
	if type(entries) ~= "table" or not savedNow then return 0 end
	local nowClock = os.clock()
	local loaded = 0
	for key, e in entries do
		local id = tonumber(key)
		if id and type(e) == "table" and _availability[id] == nil then
			-- age of the saved entry in seconds = (save time - its check time); keep it
			-- the same age on this server's clock so TTL comparisons still hold.
			local savedCheckedAt = tonumber(e.checkedAt) or savedNow
			local ageSeconds = math.max(0, savedNow - savedCheckedAt)
			_availability[id] = {
				isAvailable = e.isAvailable == true,
				isOffSale = e.isOffSale == true,
				typeName = e.typeName, typeName2 = e.typeName2,
				checkedAt = nowClock - ageSeconds,
				reason = e.reason,
				isFree = e.isFree, creatorName = e.creatorName,
				priceRobux = e.priceRobux, description = e.description,
			}
			loaded += 1
		end
	end
	if loaded > 0 then
		_isPoolReady = true -- first battle can use last-known-good data immediately
		print(`[UGCOutfitService] Loaded {loaded} persisted availability entr(y/ies); pool ready from save`)
	end
	return loaded
end

-- Persist the current availability cache under one key (yields). UpdateAsync so a
-- future multi-server setup can't clobber the record; writes wall-clock timestamps.
function UGCOutfitService.SavePersistedAvailability()
	if not _availDirty then return end
	local store = availStore()
	if not store then return end
	local nowClock, nowWall = os.clock(), os.time()
	local entries: { [string]: any } = {}
	for id, a in _availability do
		if a.reason ~= "API error" then -- don't persist transient API failures
			local ageSeconds = math.max(0, nowClock - a.checkedAt)
			entries[tostring(id)] = {
				isAvailable = a.isAvailable, isOffSale = a.isOffSale,
				typeName = a.typeName, typeName2 = a.typeName2,
				checkedAt = nowWall - ageSeconds, -- wall clock
				reason = a.reason, isFree = a.isFree, creatorName = a.creatorName,
				priceRobux = a.priceRobux, description = a.description,
			}
		end
	end
	local ok, err = pcall(function()
		store:UpdateAsync(AVAIL_STORE_KEY, function()
			return { savedAt = nowWall, entries = entries }
		end)
	end)
	if ok then
		_availDirty = false
	else
		warn(`[UGCOutfitService] Availability save failed: {err}`)
	end
end

-- Yields. One pass over every curated entry; only stale entries are queried.
function UGCOutfitService.RefreshAvailability()
	if _isRefreshing then return end
	_isRefreshing = true
	local ids = {}
	for id in UGCCatalogData.Items do table.insert(ids, id) end
	table.sort(ids)
	local available, queried = 0, 0
	for _, id in ids do
		local isAvailable, didQuery = checkEntry(id)
		if isAvailable then available += 1 end
		if didQuery then
			queried += 1
			task.wait(CHECK_SPACING)
		end
	end
	_isRefreshing = false
	local wasReady = _isPoolReady
	_isPoolReady = true
	if queried > 0 or not wasReady then
		print(`[UGCOutfitService] Availability refreshed: {available}/{#ids} curated item(s) usable ({queried} checked)`)
	end
end

-- availability_pool_refresh (ugc_rules 49): first pass now (yields — call in
-- task.spawn), then a background loop. Each beat re-queries only stale entries,
-- so every item is re-verified about every AVAILABILITY_REFRESH_SECONDS and API
-- errors retry after FAILED_RETRY_TTL. Battles never query (PRF-001/PRF-002).
function UGCOutfitService.StartAvailabilityLoop()
	if _isLoopStarted then return end
	_isLoopStarted = true
	-- option 2: seed from the saved catalog so the first battle has data without waiting.
	pcall(UGCOutfitService.LoadPersistedAvailability)
	-- option 3: the first live pass still runs now to refresh/extend what was loaded.
	UGCOutfitService.RefreshAvailability()
	if not _availSaveStarted then
		_availSaveStarted = true
		task.spawn(function()
			while true do
				task.wait(AVAIL_SAVE_SECONDS)
				UGCOutfitService.SavePersistedAvailability()
			end
		end)
		game:BindToClose(function() UGCOutfitService.SavePersistedAvailability() end)
	end
	task.spawn(function()
		while true do
			task.wait(FAILED_RETRY_TTL)
			UGCOutfitService.RefreshAvailability()
		end
	end)
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
local function loadTemplate(assetId: number, typeName: string?): Instance?
	local cached = _templates[assetId]
	if cached then return cached end
	local waiters = _loadingWaiters[assetId]
	if waiters then
		table.insert(waiters, coroutine.running())
		return coroutine.yield()
	end
	_loadingWaiters[assetId] = {}

	local result: Instance? = nil
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

local function hasPartTypes(item: UGCCatalogData.UGCItem, av: Availability?): boolean
	return av ~= nil and av.typeName ~= nil and (item.assetId2 == nil or av.typeName2 ~= nil)
end

-- Yields. PLAYER looks only (ugc_rules 50, BUG-022): resolve an entry's part
-- types now if the pool hasn't. API errors are retried a bounded number of
-- times with backoff (bypasses the 60 s failed-retry TTL); a slot mismatch is
-- not retried. Returns nil if the types still can't be resolved.
local function resolvePartTypes(entryId: number, item: UGCCatalogData.UGCItem): Availability?
	for attempt = 1, LOOK_LOOKUP_ATTEMPTS do
		local av = _availability[entryId]
		if hasPartTypes(item, av) then return av end
		if av and av.reason ~= "API error" then break end -- definitive (slot mismatch): no retry
		if attempt > 1 then task.wait(LOOK_RETRY_BACKOFF * (attempt - 1)) end
		_availability[entryId] = queryEntry(entryId, av)
	end
	local av = _availability[entryId]
	return if hasPartTypes(item, av) then av else nil
end

local function markLook(set: { [string]: { [number]: boolean } }, playerId: string, entryId: number)
	local entries = set[playerId]
	if not entries then
		entries = {}
		set[playerId] = entries
	end
	entries[entryId] = true
end

-- Yields. Replaces any previous UGC on the model with assetIds. Properties are
-- set on each clone before it is parented (NET-004). ownerPlayerId is passed
-- for PLAYER units only: their items are recorded as worn / not worn so a
-- battle is never charged for an item no unit visibly wore (BUG-022).
-- Apply a player-chosen body/skin tint to an R15 model. Sets all six BodyColors
-- regions to one Color3 (creating the BodyColors instance if the race template
-- lacks one). Clothing/accessories are NOT affected (their textures cover the
-- body) — only visible skin takes the tint, which is expected for R15. nil color
-- is a no-op (model keeps its template colors). Reused by battle dressing
-- (onModelAdded) and the loadout Preview so the tint shows in both.
function UGCOutfitService.ApplyBodyColor(model: Model, color: Color3?)
	if not model or typeof(color) ~= "Color3" then return end
	local bc = model:FindFirstChildOfClass("BodyColors")
	if not bc then
		bc = Instance.new("BodyColors")
		bc.Parent = model
	end
	bc.HeadColor3 = color
	bc.TorsoColor3 = color
	bc.LeftArmColor3 = color
	bc.RightArmColor3 = color
	bc.LeftLegColor3 = color
	bc.RightLegColor3 = color
end

function UGCOutfitService.ApplyLook(model: Model, assetIds: { number }, ownerPlayerId: string?)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	for _, child in model:GetChildren() do
		if child:GetAttribute(ASSET_ATTRIBUTE) ~= nil then child:Destroy() end
	end
	local applied = 0
	for _, entryId in assetIds do
		local item = UGCCatalogData.Items[entryId]
		if not item then continue end
		-- FIT_BLOCKLIST: skip items known to attach/scale badly on the caged body.
		if UGCCatalogData.FIT_BLOCKLIST[entryId] then continue end
		local av: Availability? = _availability[entryId]
		-- availability_cold_start (ugc_rules 50): only ENEMY outfits wait for the
		-- pool. Player units always wear what they own / trial / rent, so if the
		-- background pass hasn't reached this entry yet, check it now (yields;
		-- ApplyLook already runs in task.spawn). Enemy looks only ever come from
		-- the ready pool, so the lookup practically never runs for them.
		if not hasPartTypes(item, av) then
			if ownerPlayerId then
				av = resolvePartTypes(entryId, item)
			else
				checkEntry(entryId)
				av = _availability[entryId]
			end
		end
		-- paired_items (ugc_rules 51): both parts of an L/R pair are worn together.
		local parts: { { id: number, typeName: string } } = {}
		local type1 = av and av.typeName
		local type2 = av and av.typeName2
		if type1 and (item.assetId2 == nil or type2) then
			table.insert(parts, { id = entryId, typeName = type1 })
			if item.assetId2 and type2 then
				table.insert(parts, { id = item.assetId2, typeName = type2 })
			end
		end
		local partsWorn = 0
		for _, part in parts do
			local template = loadTemplate(part.id, part.typeName)
			if not template or model.Parent == nil then continue end
			local clone = prepareClone(template, entryId)
			if clone:IsA("Accessory") then
				humanoid:AddAccessory(clone)
			else
				-- Classic Shirt/Pants: the UGC piece replaces the rig's own one.
				local existing = model:FindFirstChildOfClass(clone.ClassName)
				if existing and existing:GetAttribute(ASSET_ATTRIBUTE) == nil then existing:Destroy() end
				clone.Parent = model
			end
			applied += 1
			partsWorn += 1
		end
		-- BUG-022: record the outcome for battle-end charging (player units only;
		-- a model removed mid-dress is not recorded).
		if ownerPlayerId and model.Parent ~= nil then
			if #parts > 0 and partsWorn == #parts then
				markLook(_lookWorn, ownerPlayerId, entryId)
			else
				markLook(_lookFailed, ownerPlayerId, entryId)
				warn(`[UGCOutfitService] could not dress {model.Name} in {entryId} — battle not charged (unless another deployed unit wears it)`)
			end
		end
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

-- Free items (the skipRecheck set) are a FAILSAFE: they should appear on enemies
-- much less often than paid items, but still occasionally, and still fill in when
-- paid items run short. FREE_PICK_WEIGHT is each free item's draw weight vs a paid
-- item's weight of 1 — lower = rarer. Weighted draw without replacement: paid items
-- are strongly favoured, but an all-free remaining pool still returns a free item
-- (so enemies are never left undressed).
local FREE_PICK_WEIGHT = 0.15

local function isFreeItem(id: number): boolean
	local item = UGCCatalogData.Items[id]
	return item ~= nil and item.skipRecheck == true
end

-- Weighted pick without replacement: paid weight 1, free weight FREE_PICK_WEIGHT.
local function takeWeighted(list: { number }, rng: Random): number?
	if #list == 0 then return nil end
	local total = 0
	for _, id in list do
		total += if isFreeItem(id) then FREE_PICK_WEIGHT else 1
	end
	local roll = rng:NextNumber() * total
	local acc = 0
	for idx, id in list do
		acc += if isFreeItem(id) then FREE_PICK_WEIGHT else 1
		if roll <= acc then
			return table.remove(list, idx)
		end
	end
	return table.remove(list) -- float guard: fall back to the last item
end

-- enemyUnits: array (deterministic order). rng: seeded Random owned by caller.
function UGCOutfitService.PlanEnemyOutfits(playerId: string, enemyUnits: { any }, rng: Random)
	table.clear(_enemyLooks)
	table.clear(_enemyRaces)
	-- Inspector preview of enemy looks (loadout_ui_spec 96): remember every enemy's race,
	-- recorded before any early return so undressed enemies still preview.
	for _, unit in enemyUnits do
		local rn = if type(unit.id) == "string" and not unit.isSummon then raceNameOf(unit) else nil
		if rn then _enemyRaces[unit.id] = rn end
	end
	if not _state then
		warn("[UGCOutfitService] State provider not wired — no enemy outfits")
		return
	end
	-- availability_cold_start (ugc_rules 50): never wait — skip this battle.
	if not _isPoolReady then
		print("[UGCOutfitService] Availability check not finished — enemies wear no UGC this battle")
		return
	end
	local pool = {}
	for id in UGCCatalogData.Items do
		-- FIT_BLOCKLIST: never put a known-misfit item on an enemy.
		if UGCOutfitService.IsAvailable(id) and not UGCCatalogData.FIT_BLOCKLIST[id] then table.insert(pool, id) end
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
		if not _state.IsOwned(playerId, id) and not _state.IsInCart(playerId, id) then
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
		-- Weighted: paid items strongly preferred, free items (failsafe) rare.
		local id = takeWeighted(randomPool, rng)
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

-- Race of an enemy unit in the current battle (nil = not an enemy of this battle).
function UGCOutfitService.GetEnemyRace(unitId: string): string?
	return _enemyRaces[unitId]
end

function UGCOutfitService.GetWornIds(playerId: string, unitId: string): { number }
	local enemyLook = _enemyLooks[unitId]
	if enemyLook then return table.clone(enemyLook) end
	if _state then return _state.GetUnitLookIds(playerId, unitId) end
	return {}
end

-- BUG-022 (ugc_rules 50): true when dressing failed for this player item on
-- every unit that tried it this battle (lookup / template error). Non-yielding;
-- read by UGCService.OnBattleCompleted, which then skips the charge.
function UGCOutfitService.WasLookNotWorn(playerId: string, entryId: number): boolean
	local failed = _lookFailed[playerId]
	if not failed or not failed[entryId] then return false end
	local worn = _lookWorn[playerId]
	return not (worn and worn[entryId])
end

-- Called by UGCService after every battle-end usage step (all paths).
function UGCOutfitService.ClearLookRecords(playerId: string)
	_lookFailed[playerId] = nil
	_lookWorn[playerId] = nil
end

local function onModelAdded(child: Instance)
	if not child:IsA("Model") or not _watchPlayerId then return end
	local unitId = string.match(child.Name, "^Unit_(.+)$")
	if not unitId then return end
	-- Body/skin tint (player choice). Enemy units never have one → nil → no-op.
	-- Applied immediately (independent of UGC dressing); cheap and does not yield.
	if _bodyColorGetter and not _enemyLooks[unitId] then
		local ok, color = pcall(_bodyColorGetter, _watchPlayerId, unitId)
		if ok and color then UGCOutfitService.ApplyBodyColor(child, color) end
	end
	local ids = UGCOutfitService.GetWornIds(_watchPlayerId, unitId)
	if #ids == 0 then return end
	-- Enemy looks are not the player's items: only player units record wear (BUG-022).
	local owner = if _enemyLooks[unitId] then nil else _watchPlayerId
	task.spawn(UGCOutfitService.ApplyLook, child, ids, owner)
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

--------------------------------------------------
-- LOOK PREVIEW (Outfit tab "Preview", 2026-10-08) — read-only, changes no state.
--------------------------------------------------
local PREVIEW_FOLDER_NAME = "UGCPreview"
local PREVIEW_MODEL_NAME = "PreviewModel"

-- Builds a display copy of the unit's race model wearing assetIds and parents it
-- under the player's PlayerGui (replicates only to that player). Yields while
-- accessories load. Returns (ok, error?). Nothing here is ever saved or charged.
function UGCOutfitService.BuildPreview(player: Player, raceName: string?, assetIds: { number }, unitId: string?, playerId: string?): (boolean, string?)
	local raceModels = ServerStorage:FindFirstChild("RaceModels")
	local template = raceName and raceModels and raceModels:FindFirstChild(raceName)
	if not template or not template:IsA("Model") then
		return false, "No model for this race yet"
	end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then return false, "Player not ready" end
	local folder = pg:FindFirstChild(PREVIEW_FOLDER_NAME)
	if not folder then
		local f = Instance.new("Folder")
		f.Name = PREVIEW_FOLDER_NAME
		f.Parent = pg -- NET-004
		folder = f
	end
	local model = template:Clone()
	model.Name = PREVIEW_MODEL_NAME
	-- Display only: no scripts, no physics.
	for _, d in model:GetDescendants() do
		if d:IsA("BaseScript") then
			d:Destroy() -- MEM-002
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end
	-- Dress off-tree in a temporary holder so ApplyLook's "model removed" checks pass,
	-- then swap it in for the previous preview in one step.
	local holder = Instance.new("Folder")
	holder.Name = "UGCPreviewBuild"
	holder.Parent = ServerStorage
	model.Parent = holder
	-- nil owner: not a battle look, never recorded. Protected so the holder never leaks.
	local ok, err = pcall(UGCOutfitService.ApplyLook, model, assetIds, nil)
	if not ok then
		warn(`[UGCOutfitService] Preview dressing failed: {err}`)
		holder:Destroy() -- MEM-002: model goes with it
		return false, "Could not build the preview"
	end
	-- Body/skin tint on the preview so the loadout picker shows the chosen color
	-- live. Needs the SAME playerId key the getter stores under (not player.UserId;
	-- the project keys units under a fixed id like "player_1"). nil unitId/playerId
	-- (enemy inspector preview) or no chosen color → no-op.
	if unitId and playerId and _bodyColorGetter then
		local okC, color = pcall(_bodyColorGetter, playerId, unitId)
		if okC and color then UGCOutfitService.ApplyBodyColor(model, color) end
	end
	for _, old in folder:GetChildren() do old:Destroy() end -- MEM-002
	model.Parent = folder
	holder:Destroy()
	return true, nil
end

function UGCOutfitService.StopWatching()
	if _watchConn then
		_watchConn:Disconnect()
		_watchConn = nil
	end
end

return UGCOutfitService
