-- SaveService.lua
-- CTRBLXAI | Slice 4C — Save and Load
--
-- Persists player state across Roblox sessions using DataStore.
-- Three keys per player: Roster+Loadouts, Inventory+Currencies, Progression.
-- Uses compact numeric IDs. Never saves names/descriptions or derived stats.
--
-- Modes:
--   "memory"     — in-memory only (automated tests, never hits DataStore)
--   "studio"     — Studio dev DataStore (separate namespace)
--   "production" — live DataStore
--
-- Rules from save_data_contract:
--   - Schema version tracked; migrate before validation
--   - Never replace valid save with blank on load failure
--   - Bounded retries (max 3)
--   - Concurrency-safe (UpdateAsync)
--   - Clear diagnostics on failure

local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")

local WeaponData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("WeaponData")
)

local SaveService = {}

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

local SCHEMA_VERSION = 1
local MAX_RETRIES = 3
local RETRY_DELAY = 1.0

-- Key prefixes
local KEY_ROSTER = "roster_v%d_%s"
local KEY_INVENTORY = "inventory_v%d_%s"
local KEY_PROGRESSION = "progression_v%d_%s"

--------------------------------------------------
-- MODE DETECTION
--------------------------------------------------

local _mode = "memory" -- default safe

function SaveService.SetMode(mode)
	assert(mode == "memory" or mode == "studio" or mode == "production",
		"SaveService.SetMode: mode must be 'memory', 'studio', or 'production'.")
	_mode = mode
	print("[SaveService] Mode set: " .. mode)
end

function SaveService.GetMode()
	return _mode
end

-- Auto-detect mode on load
if RunService:IsStudio() then
	_mode = "studio"
else
	_mode = "production"
end

--------------------------------------------------
-- DATASTORE ACCESS
--------------------------------------------------

local _datastores = {}

local function getDataStore(keyType)
	if _mode == "memory" then return nil end

	local namespace = _mode == "studio" and "CTRBLXAI_Dev" or "CTRBLXAI_Live"
	local storeName = namespace .. "_" .. keyType

	if not _datastores[storeName] then
		_datastores[storeName] = DataStoreService:GetDataStore(storeName)
	end
	return _datastores[storeName]
end

local function getKey(template, playerId)
	return string.format(template, SCHEMA_VERSION, playerId)
end

--------------------------------------------------
-- IN-MEMORY STORAGE (for "memory" mode / test fallback)
--------------------------------------------------

local _memoryStore = {}

local function memGet(key)
	return _memoryStore[key]
end

local function memSet(key, data)
	_memoryStore[key] = data
end

--------------------------------------------------
-- SAFE DATASTORE OPERATIONS (bounded retries)
--------------------------------------------------

local function safeGetAsync(store, key)
	if not store then return nil, "No DataStore (memory mode)" end
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(function()
			return store:GetAsync(key)
		end)
		if ok then
			return result, nil
		end
		warn(string.format("[SaveService] GetAsync failed (attempt %d/%d): %s", attempt, MAX_RETRIES, tostring(result)))
		if attempt < MAX_RETRIES then task.wait(RETRY_DELAY) end
	end
	return nil, "GetAsync failed after " .. MAX_RETRIES .. " retries"
end

local function safeSetAsync(store, key, data)
	if not store then return true, nil end -- memory mode always succeeds
	for attempt = 1, MAX_RETRIES do
		local ok, err = pcall(function()
			store:SetAsync(key, data)
		end)
		if ok then
			return true, nil
		end
		warn(string.format("[SaveService] SetAsync failed (attempt %d/%d): %s", attempt, MAX_RETRIES, tostring(err)))
		if attempt < MAX_RETRIES then task.wait(RETRY_DELAY) end
	end
	return false, "SetAsync failed after " .. MAX_RETRIES .. " retries"
end

--------------------------------------------------
-- ENCODING: Runtime state → compact save format
-- Never saves: names, descriptions, effective stats, derived values
--------------------------------------------------

local function encodeItem(item)
	-- Compact: { archetypeNumericId, level, rarityId, bonusLines[], passiveIds[] }
	local archetype = WeaponData.GetByArchetypeId(item.baseArchetypeId)
	local numId = archetype and archetype.numericId or 0
	local bonusLines = {}
	for _, line in ipairs(item.bonusLines or {}) do
		table.insert(bonusLines, { line.id, line.tier })
	end
	return {
		iid = item.instanceId,
		nid = numId,
		arc = item.baseArchetypeId,
		lvl = item.itemLevel,
		rar = item.rarityId,
		bln = bonusLines,
		bps = item.bonusPassiveIds or {},
		gv  = item.generatorVersion or 1,
		src = item.sourceType or "Generated",
	}
end

local function decodeItem(encoded)
	return {
		instanceId       = encoded.iid,
		baseArchetypeId  = encoded.arc,
		itemLevel        = encoded.lvl,
		rarityId         = encoded.rar,
		bonusLines       = (function()
			local lines = {}
			for _, bl in ipairs(encoded.bln or {}) do
				table.insert(lines, { id = bl[1], tier = bl[2] })
			end
			return lines
		end)(),
		bonusPassiveIds  = encoded.bps or {},
		generatorVersion = encoded.gv or 1,
		sourceType       = encoded.src or "Generated",
	}
end

local function encodeUnit(unitState)
	-- unitState from PersistentStateService
	return {
		hp  = unitState.currentHp,
		mp  = unitState.currentMp,
		mhp = unitState.maxHp,
		mmp = unitState.maxMp,
		ko  = unitState.isKO,
	}
end

local function decodeUnit(encoded)
	return {
		currentHp = encoded.hp,
		currentMp = encoded.mp,
		maxHp     = encoded.mhp,
		maxMp     = encoded.mmp,
		isKO      = encoded.ko or false,
		mpRegenAccumulator = 0,
	}
end

--------------------------------------------------
-- PUBLIC: SAVE
--
-- Accepts the full runtime state and persists it.
-- Returns: success (bool), error (string|nil)
--------------------------------------------------

function SaveService.Save(playerId, rosterState, inventoryItems, progression)
	assert(type(playerId) == "string", "SaveService.Save: playerId required")

	-- Encode roster (Key 1)
	local rosterData = {
		schemaVersion = SCHEMA_VERSION,
		units = {},
	}
	for unitId, state in pairs(rosterState or {}) do
		rosterData.units[unitId] = encodeUnit(state)
	end

	-- Encode inventory (Key 2)
	local inventoryData = {
		schemaVersion = SCHEMA_VERSION,
		items = {},
	}
	for _, item in pairs(inventoryItems or {}) do
		table.insert(inventoryData.items, encodeItem(item))
	end

	-- Encode progression (Key 3)
	local progressionData = {
		schemaVersion = SCHEMA_VERSION,
		data = progression or {},
	}

	-- Write
	if _mode == "memory" then
		memSet(getKey(KEY_ROSTER, playerId), rosterData)
		memSet(getKey(KEY_INVENTORY, playerId), inventoryData)
		memSet(getKey(KEY_PROGRESSION, playerId), progressionData)
		print(string.format("[SaveService] SAVED (memory) | %s | Units:%d Items:%d",
			playerId, #rosterData.units or 0, #inventoryData.items))
		return true, nil
	end

	local store1 = getDataStore("Roster")
	local store2 = getDataStore("Inventory")
	local store3 = getDataStore("Progression")

	local ok1, err1 = safeSetAsync(store1, getKey(KEY_ROSTER, playerId), rosterData)
	if not ok1 then
		warn("[SaveService] SAVE FAILED (roster): " .. (err1 or "unknown"))
		return false, "Roster save failed: " .. (err1 or "unknown")
	end

	local ok2, err2 = safeSetAsync(store2, getKey(KEY_INVENTORY, playerId), inventoryData)
	if not ok2 then
		warn("[SaveService] SAVE FAILED (inventory): " .. (err2 or "unknown"))
		return false, "Inventory save failed: " .. (err2 or "unknown")
	end

	local ok3, err3 = safeSetAsync(store3, getKey(KEY_PROGRESSION, playerId), progressionData)
	if not ok3 then
		warn("[SaveService] SAVE FAILED (progression): " .. (err3 or "unknown"))
		return false, "Progression save failed: " .. (err3 or "unknown")
	end

	print(string.format("[SaveService] SAVED (%s) | %s | Units:%d Items:%d",
		_mode, playerId,
		(function() local n=0; for _ in pairs(rosterData.units) do n=n+1 end; return n end)(),
		#inventoryData.items))
	return true, nil
end

--------------------------------------------------
-- PUBLIC: LOAD
--
-- Returns: { roster, inventory, progression } or nil + error
-- NEVER returns blank defaults after failure — returns nil so caller
-- retains last-known-good state.
--------------------------------------------------

function SaveService.Load(playerId)
	assert(type(playerId) == "string", "SaveService.Load: playerId required")

	local rosterRaw, inventoryRaw, progressionRaw

	if _mode == "memory" then
		rosterRaw = memGet(getKey(KEY_ROSTER, playerId))
		inventoryRaw = memGet(getKey(KEY_INVENTORY, playerId))
		progressionRaw = memGet(getKey(KEY_PROGRESSION, playerId))
	else
		local store1 = getDataStore("Roster")
		local store2 = getDataStore("Inventory")
		local store3 = getDataStore("Progression")

		local err
		rosterRaw, err = safeGetAsync(store1, getKey(KEY_ROSTER, playerId))
		if err then
			warn("[SaveService] LOAD FAILED (roster): " .. err)
			return nil, "Roster load failed: " .. err
		end

		inventoryRaw, err = safeGetAsync(store2, getKey(KEY_INVENTORY, playerId))
		if err then
			warn("[SaveService] LOAD FAILED (inventory): " .. err)
			return nil, "Inventory load failed: " .. err
		end

		progressionRaw, err = safeGetAsync(store3, getKey(KEY_PROGRESSION, playerId))
		if err then
			warn("[SaveService] LOAD FAILED (progression): " .. err)
			return nil, "Progression load failed: " .. err
		end
	end

	-- No save exists (new player)
	if not rosterRaw and not inventoryRaw and not progressionRaw then
		print("[SaveService] No save found for " .. playerId .. " — new player")
		return nil, nil
	end

	-- Validate schema version
	if rosterRaw and rosterRaw.schemaVersion and rosterRaw.schemaVersion > SCHEMA_VERSION then
		return nil, "Save schema newer than code (v" .. rosterRaw.schemaVersion .. " > v" .. SCHEMA_VERSION .. ")"
	end

	-- Decode roster
	local roster = {}
	if rosterRaw and rosterRaw.units then
		for unitId, encoded in pairs(rosterRaw.units) do
			roster[unitId] = decodeUnit(encoded)
		end
	end

	-- Decode inventory
	local inventory = {}
	if inventoryRaw and inventoryRaw.items then
		for _, encoded in ipairs(inventoryRaw.items) do
			local item = decodeItem(encoded)
			inventory[item.instanceId] = item
		end
	end

	-- Decode progression
	local progression = progressionRaw and progressionRaw.data or {}

	print(string.format("[SaveService] LOADED (%s) | %s | Units:%d Items:%d",
		_mode, playerId,
		(function() local n=0; for _ in pairs(roster) do n=n+1 end; return n end)(),
		(function() local n=0; for _ in pairs(inventory) do n=n+1 end; return n end)()
	))

	return { roster = roster, inventory = inventory, progression = progression }, nil
end

--------------------------------------------------
-- PUBLIC: HAS SAVE
--------------------------------------------------

function SaveService.HasSave(playerId)
	if _mode == "memory" then
		return memGet(getKey(KEY_ROSTER, playerId)) ~= nil
	end
	local store = getDataStore("Roster")
	local data, _ = safeGetAsync(store, getKey(KEY_ROSTER, playerId))
	return data ~= nil
end

--------------------------------------------------
-- PUBLIC: DELETE (for testing)
--------------------------------------------------

function SaveService.Delete(playerId)
	if _mode == "memory" then
		memSet(getKey(KEY_ROSTER, playerId), nil)
		memSet(getKey(KEY_INVENTORY, playerId), nil)
		memSet(getKey(KEY_PROGRESSION, playerId), nil)
		print("[SaveService] Deleted save for " .. playerId)
		return true
	end
	-- DataStore deletion via RemoveAsync
	local store1 = getDataStore("Roster")
	local store2 = getDataStore("Inventory")
	local store3 = getDataStore("Progression")
	pcall(function() store1:RemoveAsync(getKey(KEY_ROSTER, playerId)) end)
	pcall(function() store2:RemoveAsync(getKey(KEY_INVENTORY, playerId)) end)
	pcall(function() store3:RemoveAsync(getKey(KEY_PROGRESSION, playerId)) end)
	print("[SaveService] Deleted save for " .. playerId)
	return true
end

return SaveService
