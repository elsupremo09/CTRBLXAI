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
local ArmorData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("ArmorData")
)
local RaceData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("RaceData")
)
-- Rarity order for load validation of the starting rarity (equipment_schema 19).
local BonusData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("BonusData")
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
local _testGuard = false -- set below (Studio test guard)

-- Load-failure guard (save_data_contract: "Never replace valid save with blank on
-- load failure"). If Load errors for a player (DataStore down, HTTP 403 with Studio
-- API access off, schema newer than code), that player's real save is unknown, so
-- every Save for them is refused for the rest of the session. "No save found" (a
-- new player) is NOT a failure and saves normally.
local _loadFailed: { [string]: string } = {}
-- Dev "Delete save" (2026-10-31, Tester D-1): once a save is deleted, every later save this
-- session is refused, so a quit save cannot write the deleted progress back from memory.
-- Only the Studio dev panel calls Delete.
local _deletedThisSession: { [string]: boolean } = {}

-- Load result when another live server still holds the save lock (user ruling 2026-11-19 3:03 PM):
-- Main kicks the player with SaveService.LOCKED_MESSAGE instead of opening the save read-only.
SaveService.LOCKED = "SAVE_LOCKED"
SaveService.LOCKED_MESSAGE = "Your save is still open on another server. Please rejoin in a minute."

local function failLoad(playerId, reason)
	_loadFailed[playerId] = reason
	warn("[SaveService] Saving DISABLED for " .. playerId .. " this session: " .. reason)
	return nil, reason
end

-- Reason string while saving is blocked for this player, else nil.
function SaveService.GetLoadFailure(playerId)
	return _loadFailed[playerId]
end

function SaveService.SetMode(mode)
	assert(mode == "memory" or mode == "studio" or mode == "production",
		"SaveService.SetMode: mode must be 'memory', 'studio', or 'production'.")
	if _testGuard and mode ~= "memory" then
		warn("[SaveService] SetMode(" .. mode .. ") refused: test guard keeps memory mode this session")
		return
	end
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

-- Studio TEST GUARD (2026-11-16, after a test session wrote a furniture migration into the
-- real save before memory mode was switched on). A test sets the workspace attribute
-- "CTRBLXAI_TestMemorySave" = true in EDIT mode before pressing Play; the Play copy keeps
-- it, so memory mode is active BEFORE the save loads. Load then reads the real Studio save
-- read-only (so tests use real data) and every Save stays in memory. Studio only: the
-- attribute is ignored in live servers. Normal Studio play (no attribute) is unchanged.
if RunService:IsStudio() and workspace:GetAttribute("CTRBLXAI_TestMemorySave") == true then
	_testGuard = true
	_mode = "memory"
	print("[SaveService] Mode set: memory (test guard)")
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
		local ok, store = pcall(function()
			return DataStoreService:GetDataStore(storeName)
		end)
		if not ok then
			warn("[SaveService] DataStore unavailable (" .. tostring(store) .. ") — falling back to memory mode")
			_mode = "memory"
			return nil
		end
		_datastores[storeName] = store
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
-- SESSION LOCK (real-time Dispatch build step 1, 2026-11-19; unit_progression 77)
--
-- One live server per save. Real-time Dispatch pays out by the server clock, so if the
-- same save were open in two servers both could collect the same hours. The lock lives in
-- its OWN key ("lock_v1_<id>" in "<namespace>_Lock"), so the save data is unchanged and
-- every old save loads as before.
--   Claim   : at the start of Load (studio / production only). Free, already ours, or
--             stale -> claimed. Held by another live server -> wait and retry (2+4+8+8 s),
--             then Load returns SaveService.LOCKED and Main kicks the player (2026-11-19).
--   Refresh : every 30 s. If another server holds it now, saving stops (lock lost).
--   Release : Main calls ReleaseLock after the quit save -> the next server claims at once.
--   Stale   : not refreshed for 240 s (Studio 120 s) = free (crashed server / killed Studio).
--   Save    : refused unless we hold the lock and refreshed it within (stale - 30) s.
-- Memory mode (tests, Studio test guard, dev memorySave) never reads or writes the lock.
--------------------------------------------------

local HttpService = game:GetService("HttpService")
local LOCK_KEY = "lock_v%d_%s"
local LOCK_REFRESH = 30
local LOCK_STALE = if RunService:IsStudio() then 120 else 240
local LOCK_SAVE_GRACE = LOCK_STALE - 30
local LOCK_RETRY_WAITS = { 2, 4, 8, 8 }
-- Our own id: game.JobId is "" in Studio, so two Studio sessions would look the same.
local SESSION_ID = HttpService:GenerateGUID(false)

type LockState = { store: any, key: string, lastRefresh: number, lost: boolean, released: boolean, busy: boolean }
local _locks: { [string]: LockState } = {}

local function lockValue(t: number)
	return { session = SESSION_ID, jobId = game.JobId, placeId = game.PlaceId, t = t }
end

-- One claim attempt. Returns claimed, current holder (when not claimed), error text.
local function tryClaim(store, key: string): (boolean, any, string?)
	local claimed, holder = false, nil
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(current)
			local now = os.time()
			claimed, holder = false, current
			local free = type(current) ~= "table"
				or current.session == SESSION_ID
				or (now - (tonumber(current.t) or 0)) > LOCK_STALE
			if not free then return nil end -- another live server holds it: no write
			claimed = true
			return lockValue(now)
		end)
	end)
	if not ok then return false, nil, tostring(err) end
	return claimed, holder, nil
end

local function startLockRefresh(playerId: string)
	task.spawn(function()
		while true do
			task.wait(LOCK_REFRESH)
			local st = _locks[playerId]
			if not st or st.released or st.lost then return end
			st.busy = true
			local stillOurs: boolean? = nil
			local ok, err = pcall(function()
				st.store:UpdateAsync(st.key, function(current)
					if type(current) == "table" and current.session ~= SESSION_ID then
						stillOurs = false -- someone else claimed it (we went stale): never take it back
						return nil
					end
					stillOurs = true
					return lockValue(os.time())
				end)
			end)
			st.busy = false
			if ok and stillOurs == true then
				st.lastRefresh = os.clock()
			elseif ok and stillOurs == false then
				st.lost = true
				_loadFailed[playerId] = "save lock lost: this save was opened in another server"
				warn("[SaveService] Save lock LOST for " .. playerId .. " — saving stops this session")
				return
			else
				warn("[SaveService] Save lock refresh failed (will retry): " .. tostring(err))
			end
		end
	end)
end

-- Claims the lock for this save. Returns ok, reason, heldElsewhere.
local function acquireLock(playerId: string): (boolean, string?, boolean)
	if _mode == "memory" then return true, nil, false end
	local store = getDataStore("Lock")
	if not store then return true, nil, false end -- fell back to memory mode: nothing to lock
	local key = string.format(LOCK_KEY, SCHEMA_VERSION, playerId)
	local errors, waits = 0, 0
	while true do
		local claimed, holder, err = tryClaim(store, key)
		if claimed then
			_locks[playerId] = { store = store, key = key, lastRefresh = os.clock(), lost = false, released = false, busy = false }
			startLockRefresh(playerId)
			print("[SaveService] Save lock claimed | " .. playerId .. " | session " .. string.sub(SESSION_ID, 1, 8))
			return true, nil, false
		end
		if err then
			errors += 1
			warn(string.format("[SaveService] Save lock claim failed (attempt %d/%d): %s", errors, MAX_RETRIES, err))
			if errors >= MAX_RETRIES then
				return false, "save lock could not be claimed: " .. err, false
			end
			task.wait(RETRY_DELAY)
		else
			waits += 1
			local w = LOCK_RETRY_WAITS[waits]
			local where = if type(holder) == "table" then tostring(holder.jobId) .. " / place " .. tostring(holder.placeId) else "?"
			if not w then
				return false, "save is open in another server (" .. where .. ")", true
			end
			warn(string.format("[SaveService] Save is open in another server (%s) — waiting %d s", where, w))
			task.wait(w)
		end
	end
end

-- Whether a real Save may write now (memory mode always may).
local function lockAllowsSave(playerId: string): (boolean, string?)
	if _mode == "memory" then return true, nil end
	local st = _locks[playerId]
	if not st then return false, "no save lock held (released or never claimed)" end
	if st.lost then return false, "save lock lost to another server" end
	if st.released then return false, "save lock already released" end
	local age = os.clock() - st.lastRefresh
	if age > LOCK_SAVE_GRACE then
		return false, string.format("save lock not refreshed for %d s", math.floor(age))
	end
	return true, nil
end

-- Frees the save for the next server. Call AFTER the last save (Main saveOnQuit).
function SaveService.ReleaseLock(playerId: string)
	local st = _locks[playerId]
	if not st or st.released then return end
	st.released = true
	local t0 = os.clock()
	while st.busy and os.clock() - t0 < 10 do
		task.wait(0.1)
	end
	if not st.lost then
		local ok, err = pcall(function()
			st.store:UpdateAsync(st.key, function(current)
				if type(current) == "table" and current.session ~= SESSION_ID then
					return nil -- another server's lock now: leave it alone
				end
				local v = lockValue(0) -- t = 0 -> stale -> the next server claims at once
				v.released = true
				return v
			end)
		end)
		if ok then
			print("[SaveService] Save lock released | " .. playerId)
		else
			warn("[SaveService] Save lock release failed (frees itself after " .. LOCK_STALE .. " s): " .. tostring(err))
		end
	end
	_locks[playerId] = nil
end

-- True while this server holds a live lock for the save (memory mode: always true).
function SaveService.HasLock(playerId: string): boolean
	return (lockAllowsSave(playerId))
end

--------------------------------------------------
-- ENCODING: Runtime state → compact save format
-- Never saves: names, descriptions, effective stats, derived values
--------------------------------------------------

-- Levelling record (equipment_schema 20, v2 2026-11-01) as a flat array
-- { F, hi1, b1, hi2, b2, ... }. Not written for the default (arrived at its current
-- level, no bought levels), so most items cost no extra bytes.
local function encodeLevellingRecord(item)
	local rec = item.levellingRecord
	if type(rec) ~= "table" or type(rec.free) ~= "number" or type(rec.pairs) ~= "table" then return nil end
	if #rec.pairs == 0 and rec.free == item.itemLevel then return nil end
	local out = { rec.free }
	for _, pr in ipairs(rec.pairs) do
		table.insert(out, pr[1])
		table.insert(out, pr[2])
	end
	return out
end

-- Validates a saved record against the item level. A missing or broken record means
-- the item arrived at its current level with no bought levels (credit 0) — the rule
-- for items saved before v2 (save_data_contract 3). Pairs must rise, stay within the
-- item level, use Blacksmith levels 1-10 and end exactly at the item level.
local function decodeLevellingRecord(encoded)
	local lvl = math.max(1, math.floor(tonumber(encoded.lvl) or 1))
	local default = { free = lvl, pairs = {} }
	local lr = encoded.lr
	if type(lr) ~= "table" then return default end
	local free = tonumber(lr[1])
	if not (free and free == math.floor(free) and free >= 1 and free <= lvl) then
		warn("[SaveService] Invalid levelling record (free level) on " .. tostring(encoded.iid) .. " -- reset")
		return default
	end
	local pairsOut = {}
	local prev = free
	local i = 2
	while lr[i] ~= nil do
		local hi, b = tonumber(lr[i]), tonumber(lr[i + 1])
		if not (hi and b and hi == math.floor(hi) and b == math.floor(b) and hi > prev and hi <= lvl and b >= 1 and b <= 10) then
			warn("[SaveService] Invalid levelling record (pair) on " .. tostring(encoded.iid) .. " -- reset")
			return default
		end
		table.insert(pairsOut, { hi, b })
		prev = hi
		i += 2
	end
	if prev ~= lvl then
		warn("[SaveService] Levelling record does not end at the item level on " .. tostring(encoded.iid) .. " -- reset")
		return default
	end
	if #pairsOut > 10 then
		warn("[SaveService] Levelling record on " .. tostring(encoded.iid) .. " has " .. #pairsOut .. " pairs (more than 10) -- kept")
	end
	return { free = free, pairs = pairsOut }
end

-- Open (paid, not yet chosen) Runeforge reroll (USER RULING 2026-11-07): the paid sets are
-- saved on the item so leaving and rejoining shows the SAME sets. Written only while a choice
-- is open. Compact: { s = sulfur paid, o = { { bln = {{id, tier}}, bps = {id}, dn = name? } } }.
local MAX_PENDING_SETS = 8
local function encodePendingReroll(item)
	local p = item.pendingReroll
	if type(p) ~= "table" or type(p.sets) ~= "table" or #p.sets == 0 then return nil end
	local o = {}
	for _, set in ipairs(p.sets) do
		local bln = {}
		for _, line in ipairs(set.bonusLines or {}) do
			table.insert(bln, { line.id, line.tier })
		end
		table.insert(o, { bln = bln, bps = set.bonusPassiveIds or {}, dn = set.name })
	end
	return { s = p.sulfur, o = o }
end

-- Anything malformed is dropped (warned), never half-loaded.
local function decodePendingReroll(encoded)
	local e = encoded.prr
	if e == nil then return nil end
	if type(e) ~= "table" or type(e.o) ~= "table" or #e.o == 0 or #e.o > MAX_PENDING_SETS then
		warn(`[SaveService] Dropped a malformed open reroll on item {tostring(encoded.iid)}`)
		return nil
	end
	local sets = {}
	for _, s in ipairs(e.o) do
		if type(s) ~= "table" or type(s.bln) ~= "table" or type(s.bps) ~= "table" then
			warn(`[SaveService] Dropped a malformed open reroll on item {tostring(encoded.iid)}`)
			return nil
		end
		local lines = {}
		for _, bl in ipairs(s.bln) do
			if type(bl) ~= "table" or type(bl[1]) ~= "string" then
				warn(`[SaveService] Dropped a malformed open reroll on item {tostring(encoded.iid)}`)
				return nil
			end
			table.insert(lines, { id = bl[1], tier = bl[2] })
		end
		local passives = {}
		for _, pid in ipairs(s.bps) do
			if type(pid) == "string" then table.insert(passives, pid) end
		end
		table.insert(sets, {
			bonusLines = lines,
			bonusPassiveIds = passives,
			name = if type(s.dn) == "string" then s.dn else nil,
		})
	end
	return { sets = sets, sulfur = math.max(0, math.floor(tonumber(e.s) or 0)) }
end

local function encodeItem(item)
	-- Compact: { archetypeNumericId, level, rarityId, bonusLines[], passiveIds[] }
	local archetype = WeaponData.GetByArchetypeId(item.baseArchetypeId)
	if not archetype then
		archetype = ArmorData.GetByArchetypeId(item.baseArchetypeId)
	end
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
		dn  = item.displayName,
		-- Acquisition record (equipment_schema 18-20, v2 2026-11-01). Written only when it
		-- differs from the default, so most items cost no extra bytes: levelling record =
		-- arrived at the current level, starting rarity = current rarity, rerolls = 0.
		lr  = encodeLevellingRecord(item),
		sr  = if item.startingRarity ~= nil and item.startingRarity ~= item.rarityId then item.startingRarity else nil,
		rc  = if type(item.rerollCount) == "number" and item.rerollCount > 0 then item.rerollCount else nil,
		-- 'rune-forged' tracking tag (USER DECISION 2026-11-01): written only when set.
		rf  = if item.runeForged == true then 1 else nil,
		-- Open reroll choice (USER RULING 2026-11-07): written only while one is open.
		prr = encodePendingReroll(item),
		-- NEW badge (USER RULING 2026-11-08): written only while the item is unseen.
		nw  = if item.isNew == true then 1 else nil,
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
		displayName      = encoded.dn,
		-- Acquisition record (equipment_schema 18-20, save_data_contract 3, v2). Missing on
		-- older saves: those items arrived at their CURRENT level and rarity and owe no
		-- catch-up for past levels. An old `sl` (pre-v2 starting level) is ignored.
		levellingRecord  = decodeLevellingRecord(encoded),
		-- Must be a known rarity and never above the current one (equipment_schema 19);
		-- otherwise it falls back to the current rarity.
		startingRarity   = (function()
			local order = BonusData.RARITY_ORDER
			local sr = encoded.sr
			if type(sr) == "string" and order[sr] and order[encoded.rar] and order[sr] <= order[encoded.rar] then
				return sr
			end
			return encoded.rar
		end)(),
		runeForged       = encoded.rf == 1 or encoded.rf == true,
		rerollCount      = math.max(0, math.floor(tonumber(encoded.rc) or 0)),
		-- Missing on older saves and on items with no open reroll choice (no migration).
		pendingReroll    = decodePendingReroll(encoded),
		-- NEW badge (2026-11-08): missing on older saves = already seen.
		isNew            = if encoded.nw == 1 or encoded.nw == true then true else nil,
	}
end

local function encodeUnit(unitState)
	-- unitState from PersistentStateService
	-- equipSlots: { MainHand = instanceId, OffHand = instanceId } added by doSave caller
	return {
		hp  = unitState.currentHp,
		mp  = unitState.currentMp,
		mhp = unitState.maxHp,
		mmp = unitState.maxMp,
		ko  = unitState.isKO,
		eq  = unitState.equipSlots or nil,
		rid = unitState.raceId or nil,
		pks = unitState.perkIds or {},
		dbs = unitState.drawbackIds or {},
		doc = unitState.doctrineId or nil,
		dsk = unitState.selectedDoctrineSkill or nil,
		skl = unitState.skillLoadout or nil,
		sap = unitState.statAllocation or nil,
		rec = unitState.records or nil,
		con = unitState.consumableSlots or nil,
		-- Player-chosen 2D portrait asset ID (option B). nil = no choice yet
		-- (display falls back to the colored box). Headshot mode (option A) is
		-- deferred until worn-UGC is persisted, so only the asset ID is saved here.
		por = unitState.portraitAssetId or nil,
		-- 1 = the player removed the portrait on purpose (2026-11-09); written only when
		-- set, so units that never cleared one save exactly as before.
		pcl = if unitState.portraitCleared == true then 1 else nil,
		-- Player-chosen body/skin tint as {r,g,b} 0-255 ints (nil = template colors).
		bcl = unitState.bodyColor or nil,
	}
end

-- Race renames (2026-10-09): a saved race ID that was later renamed loads as the
-- current ID (RaceData.LegacyIds). Unknown IDs are kept as-is (unchanged behaviour).
-- Returns (raceId, wasConverted).
local function convertSavedRaceId(raceId)
	if raceId == nil then return nil, false end
	local current, converted = RaceData.Resolve(raceId)
	if converted then return current, true end
	return raceId, false
end

local function decodeUnit(encoded, unitId)
	-- The unit's raceId (rid) and its progression record's raceId (rec.raceId) are
	-- both saved; convert either if it holds a legacy ID. One warning per unit.
	local fromId, toId = nil, nil
	local raceId, ridConverted = convertSavedRaceId(encoded.rid)
	if ridConverted then fromId, toId = encoded.rid, raceId end
	local records = encoded.rec or nil
	if type(records) == "table" and records.raceId ~= nil then
		local recRace, recConverted = convertSavedRaceId(records.raceId)
		if recConverted and fromId == nil then fromId, toId = records.raceId, recRace end
		records.raceId = recRace
	end
	if fromId then
		warn(string.format("[SaveService] converted legacy race id %s -> %s (unit %s)",
			tostring(fromId), tostring(toId), tostring(unitId)))
	end
	return {
		currentHp = encoded.hp,
		currentMp = encoded.mp,
		maxHp     = encoded.mhp,
		maxMp     = encoded.mmp,
		isKO      = encoded.ko or false,
		mpRegenAccumulator = 0,
		equipSlots = encoded.eq or nil,
		raceId     = raceId,
		perkIds    = encoded.pks or {},
		drawbackIds = encoded.dbs or {},
		doctrineId = encoded.doc or nil,
		selectedDoctrineSkill = encoded.dsk or nil,
		skillLoadout = encoded.skl or nil,
		statAllocation = encoded.sap or nil,
		records = records,
		consumableSlots = encoded.con or nil,
		-- Player-chosen 2D portrait asset ID (option B); nil = colored-box fallback.
		portraitAssetId = encoded.por or nil,
		-- Player removed the portrait on purpose. Missing on older saves = never cleared.
		portraitCleared = if encoded.pcl == 1 or encoded.pcl == true then true else nil,
		-- Player-chosen body/skin tint {r,g,b} 0-255 ints; nil = template colors.
		bodyColor = encoded.bcl or nil,
	}
end

--------------------------------------------------
-- PUBLIC: SAVE
--
-- Accepts the full runtime state and persists it.
-- Returns: success (bool), error (string|nil)
--------------------------------------------------

function SaveService.Save(playerId, rosterState, inventoryItems, progression, currencies)
	assert(type(playerId) == "string", "SaveService.Save: playerId required")

	-- Every save path (battle end, hub close, guild actions, dev commands) ends here.
	if _loadFailed[playerId] then
		warn("[Save] Skipped — load failed this session, refusing to overwrite the real save ("
			.. _loadFailed[playerId] .. ")")
		return false, "Save blocked: load failed this session"
	end
	if _deletedThisSession[playerId] then
		warn("[Save] Skipped — save was deleted this session; restart to begin fresh")
		return false, "Save blocked: save deleted this session"
	end
	-- Session lock (2026-11-19): only the server holding the lock may write the real save.
	local lockOk, lockWhy = lockAllowsSave(playerId)
	if not lockOk then
		warn("[Save] Skipped — " .. tostring(lockWhy))
		return false, "Save blocked: " .. tostring(lockWhy)
	end

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
		-- Key 2 = "Inventory + Currencies" (save_data_contract). Gold + the 5
		-- material counters live here alongside items (materials_system id30).
		-- Passed in by the orchestrator from CurrencyService.Export(); optional
		-- so legacy 4-arg callers are unaffected.
		currencies = (type(currencies) == "table") and currencies or nil,
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
			playerId, (function() local n=0; for _ in pairs(rosterData.units or {}) do n=n+1 end; return n end)(), -- keyed table: count like the real-mode line (2026-11-18)
			#inventoryData.items))
		if _testGuard then
			warn("[SaveService] TEST GUARD ON — progress is NOT being saved. Clear workspace attribute CTRBLXAI_TestMemorySave.")
		end
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
	local readOnlyReason: string? = nil -- set when another server holds the save lock

	if _mode == "memory" then
		rosterRaw = memGet(getKey(KEY_ROSTER, playerId))
		inventoryRaw = memGet(getKey(KEY_INVENTORY, playerId))
		progressionRaw = memGet(getKey(KEY_PROGRESSION, playerId))
		if _testGuard and rosterRaw == nil and inventoryRaw == nil and progressionRaw == nil then
			-- Test guard: read the real Studio save once, read-only. Nothing here writes.
			local function devStore(keyType: string)
				local ok, store = pcall(function()
					return DataStoreService:GetDataStore("CTRBLXAI_Dev_" .. keyType)
				end)
				return if ok then store else nil
			end
			local err
			rosterRaw, err = safeGetAsync(devStore("Roster"), getKey(KEY_ROSTER, playerId))
			if err then return failLoad(playerId, "Roster load failed (test guard): " .. err) end
			inventoryRaw, err = safeGetAsync(devStore("Inventory"), getKey(KEY_INVENTORY, playerId))
			if err then return failLoad(playerId, "Inventory load failed (test guard): " .. err) end
			progressionRaw, err = safeGetAsync(devStore("Progression"), getKey(KEY_PROGRESSION, playerId))
			if err then return failLoad(playerId, "Progression load failed (test guard): " .. err) end
			print("[SaveService] Test guard: real Studio save read (read-only); saves stay in memory")
		end
	else
		-- Session lock (2026-11-19): claim before reading. Held by another live server after
		-- the waits -> return SaveService.LOCKED (Main kicks; nothing is read or written).
		local lockOk, lockErr, heldElsewhere = acquireLock(playerId)
		if not lockOk then
			if not heldElsewhere then
				return failLoad(playerId, tostring(lockErr))
			end
			-- Held by another live server after the waits: do NOT read the save. Saving stays blocked
			-- and Main kicks the player (2026-11-19 3:03 PM). This session never owned the lock.
			_loadFailed[playerId] = "save is open in another server: " .. tostring(lockErr)
			warn("[SaveService] Save locked by another server for " .. playerId .. ": " .. tostring(lockErr))
			return nil, SaveService.LOCKED
		end

		local store1 = getDataStore("Roster")
		local store2 = getDataStore("Inventory")
		local store3 = getDataStore("Progression")

		local err
		rosterRaw, err = safeGetAsync(store1, getKey(KEY_ROSTER, playerId))
		if err then
			warn("[SaveService] LOAD FAILED (roster): " .. err)
			return failLoad(playerId, "Roster load failed: " .. err)
		end

		inventoryRaw, err = safeGetAsync(store2, getKey(KEY_INVENTORY, playerId))
		if err then
			warn("[SaveService] LOAD FAILED (inventory): " .. err)
			return failLoad(playerId, "Inventory load failed: " .. err)
		end

		progressionRaw, err = safeGetAsync(store3, getKey(KEY_PROGRESSION, playerId))
		if err then
			warn("[SaveService] LOAD FAILED (progression): " .. err)
			return failLoad(playerId, "Progression load failed: " .. err)
		end
	end

	_loadFailed[playerId] = nil -- reads succeeded; only a schema mismatch below re-blocks
	if readOnlyReason then
		-- Data loads normally so the player sees it, but nothing is written this session.
		_loadFailed[playerId] = readOnlyReason
		warn("[SaveService] Save loaded READ-ONLY for " .. playerId .. ": " .. readOnlyReason)
	end

	-- No save exists (new player)
	if not rosterRaw and not inventoryRaw and not progressionRaw then
		print("[SaveService] No save found for " .. playerId .. " — new player")
		return nil, nil
	end

	-- Validate schema version
	if rosterRaw and rosterRaw.schemaVersion and rosterRaw.schemaVersion > SCHEMA_VERSION then
		return failLoad(playerId, "Save schema newer than code (v" .. rosterRaw.schemaVersion .. " > v" .. SCHEMA_VERSION .. ")")
	end

	-- Decode roster
	local roster = {}
	if rosterRaw and rosterRaw.units then
		for unitId, encoded in pairs(rosterRaw.units) do
			roster[unitId] = decodeUnit(encoded, unitId)
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

	-- Decode currencies (Key 2 — Inventory + Currencies). May be absent on
	-- a pre-currency save or a brand-new player; nil is returned and the
	-- orchestrator leaves CurrencyService at its starting balance.
	local currencies = (inventoryRaw and type(inventoryRaw.currencies) == "table")
		and inventoryRaw.currencies or nil

	-- Decode progression
	local progression = progressionRaw and progressionRaw.data or {}

	print(string.format("[SaveService] LOADED (%s) | %s | Units:%d Items:%d",
		_mode, playerId,
		(function() local n=0; for _ in pairs(roster) do n=n+1 end; return n end)(),
		(function() local n=0; for _ in pairs(inventory) do n=n+1 end; return n end)()
	))

	return { roster = roster, inventory = inventory, progression = progression, currencies = currencies }, nil
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
	if _mode ~= "memory" then
		-- Tester WARN 1 (2026-11-19): a server without the save lock (read-only) must never delete the real save.
		local okLock, why = lockAllowsSave(playerId)
		if not okLock then
			warn("[SaveService] Delete refused -- " .. tostring(why))
			return false
		end
	end
	-- Block every later save this session (see _deletedThisSession).
	_deletedThisSession[playerId] = true
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
	print("[SaveService] Deleted save for " .. playerId .. " -- saving is OFF until you restart")
	return true
end

return SaveService
