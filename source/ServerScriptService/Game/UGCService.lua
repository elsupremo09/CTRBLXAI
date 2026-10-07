--!strict
-- UGCService.lua
-- CTRBLXAI | UGC Rental & Ownership — server authority (ARC-001)
--
-- Rules: CTRBLXAI.db ugc_rules (locked 2026-10-07), mirrored in UGCCatalogData.
--   * Free try-on: 5 battles, once per item, ever. Any number of items at once.
--     A trial is NOT a rental (does not raise the price).
--   * Gold rental: 30 battles. Price = base x 2^(previous paid rentals of that
--     item, per player). Never resets, no cap. Renting while active adds 30.
--   * Usage: -1 per battle (at battle END only) per item worn by ANY deployed
--     player unit, however many units wore it.
--   * Expiry: unequips from every unit, item shown "expired" (red) until it is
--     rented again or bought.
--   * Owned on Roblox (PlayerOwnsAsset): free, permanent, no count, no gold.
--     Ownership is NEVER saved — always re-verified live.
--   * Prompt-on-first-equip: the first time an unowned item is equipped, the
--     server calls MarketplaceService:PromptPurchase (Roblox "Experiences using
--     Marketplace Items" policy, 2023). The Buy button is always available.
--   * Wishlist: cap 50, blocked with "Wishlist full (50)", auto-removed on buy.
--   * Ratings: like/dislike per player; aggregate totals are PRIVATE developer
--     data, batched per server into a DataStore (UpdateAsync, bounded retries).
--
-- This service never touches the player save DataStore: Main.server.lua folds
-- Export() into the existing progression payload (Key 3), like GuildService.
--
-- Injections (ARC-004 / ARC-006 — all nil-safe):
--   SetCurrencyService(svc)          -- CurrencyService (Debit/GetBalance)
--   SetAvailabilityProvider(fn)      -- (assetId) -> boolean   (on-sale check, cached)
--   SetUnitRaceProvider(fn)          -- (playerId, unitId) -> (isOwnedUnit, raceName?)
--   SetPlayerLevelProvider(fn)       -- (playerId) -> number   (price level)
--   SetSaveModeProvider(fn)          -- () -> "memory" | "studio" | "production"
--   SetChangeNotifier(fn)            -- (playerId, reason, { assetId }) -> ()

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UGCCatalogData = require(ReplicatedStorage:WaitForChild("Content"):WaitForChild("UGCCatalogData"))

local UGCService = {}

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

local SAVE_VERSION = 1

-- Average battle gold (rental price input). Battle gold GRANTS are not
-- implemented in code yet (RewardService only holds multipliers), so the price
-- is derived from the documented economy, in ONE place (avgBattleGold below):
--   economy_framework id 42 (Verified): ~165,000 battle gold over ~547 battles
--   economy_framework id 8 (Locked): Battle Completion Gold = Base x (1 + Map Level / 50)
-- Level shape uses id 8's (1 + L/50); it is anchored so the L1..L99 mean equals
-- the verified benchmark (mean of 1 + L/50 over 1..99 is exactly 2).
-- ASSUMPTION (flagged to Designer): battles are spread evenly across levels.
local BENCHMARK_BATTLE_GOLD = 165000
local BENCHMARK_BATTLES = 547
local GOLD_LEVEL_DIVISOR = 50
local MIN_LEVEL, MAX_LEVEL = 1, 99
local MEAN_LEVEL_FACTOR = 1 + ((MIN_LEVEL + MAX_LEVEL) / 2) / GOLD_LEVEL_DIVISOR -- = 2

-- Ratings aggregate (private developer data)
local RATING_FLUSH_SECONDS = 300
local MAX_RETRIES = 3 -- mirrors SaveService (save_data_contract: bounded retries)
local RETRY_DELAY = 1.0
local OWNERSHIP_RECHECK_ATTEMPTS = 3 -- purchase ownership can lag a moment

--------------------------------------------------
-- TYPES / STATE
--------------------------------------------------

type Rental = { mode: string, remaining: number } -- mode: "trial" | "rent"

type PlayerState = {
	player: Player?,
	owned: { [number]: boolean },       -- live ownership cache (NEVER saved)
	rentals: { [number]: Rental },
	rentCount: { [number]: number },     -- paid rentals per item (price escalation)
	trialUsed: { [number]: boolean },
	expired: { [number]: boolean },      -- shown red until re-rented or bought
	prompted: { [number]: boolean },     -- first-equip purchase prompt already shown
	equips: { [string]: { [string]: number } }, -- unitId -> slot -> assetId
	wishlist: { [number]: boolean },
	wishlistCount: number,
	votes: { [number]: number },         -- 1 like / -1 dislike
	isBattleActive: boolean,
}

type RatingDelta = { likes: number, dislikes: number }

local _states: { [string]: PlayerState } = {}
local _pendingRatings: { [number]: RatingDelta } = {}
local _isFlushing = false
local _isFlushLoopStarted = false

local _currency: any = nil
local _isAvailable: ((number) -> boolean)? = nil
local _unitRace: ((string, string) -> (boolean, string?))? = nil
local _playerLevel: ((string) -> number)? = nil
local _saveMode: (() -> string)? = nil
local _notify: ((string, string, { number }) -> ())? = nil

function UGCService.SetCurrencyService(svc: any) _currency = svc end
function UGCService.SetAvailabilityProvider(fn: (number) -> boolean) _isAvailable = fn end
function UGCService.SetUnitRaceProvider(fn: (string, string) -> (boolean, string?)) _unitRace = fn end
function UGCService.SetPlayerLevelProvider(fn: (string) -> number) _playerLevel = fn end
function UGCService.SetSaveModeProvider(fn: () -> string) _saveMode = fn end
function UGCService.SetChangeNotifier(fn: (string, string, { number }) -> ()) _notify = fn end

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function stateOf(playerId: string): PlayerState?
	return _states[playerId]
end

local function itemOf(assetId: number): UGCCatalogData.UGCItem?
	return UGCCatalogData.Items[assetId]
end

local function isAvailable(assetId: number): boolean
	-- Fail closed: no provider / unknown availability = not usable (curation_eligibility).
	return _isAvailable ~= nil and _isAvailable(assetId) == true
end

local function isPositiveInt(n: any): boolean
	return type(n) == "number" and n == n and n > 0 and n < 2 ^ 53 and math.floor(n) == n
end

local function sortedIds(set: { [number]: any }): { number }
	local ids = {}
	for id in set do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

local function notify(playerId: string, reason: string, assetIds: { number })
	if _notify and #assetIds > 0 then
		_notify(playerId, reason, assetIds)
	end
end

local function unequipEverywhere(s: PlayerState, assetId: number)
	for _, slots in s.equips do
		for slot, id in slots do
			if id == assetId then
				slots[slot] = nil
			end
		end
	end
end

-- Live PlayerOwnsAsset. Fails CLOSED (false) on API error: no free use on error.
local function checkOwnedLive(s: PlayerState, assetId: number): boolean
	local player = s.player
	if not player or player.Parent == nil then
		return s.owned[assetId] == true
	end
	local ok, result = pcall(MarketplaceService.PlayerOwnsAsset, MarketplaceService, player, assetId)
	if not ok then
		warn(`[UGCService] PlayerOwnsAsset failed for {assetId}: {result}`)
		return s.owned[assetId] == true
	end
	if result == true then
		s.owned[assetId] = true
		return true
	end
	s.owned[assetId] = nil
	return false
end

-- Owned supersedes any rental / expiry / wishlist entry (wishlist_auto_remove).
local function applyOwned(s: PlayerState, assetId: number)
	s.owned[assetId] = true
	s.rentals[assetId] = nil
	s.expired[assetId] = nil
	if s.wishlist[assetId] then
		s.wishlist[assetId] = nil
		s.wishlistCount -= 1
	end
end

local function hasAccess(s: PlayerState, assetId: number): boolean
	if s.owned[assetId] then return true end
	local r = s.rentals[assetId]
	return r ~= nil and r.remaining > 0
end

local function statusOf(s: PlayerState, assetId: number): string
	if s.owned[assetId] then return "owned" end
	local r = s.rentals[assetId]
	if r and r.remaining > 0 then return r.mode end
	if s.expired[assetId] then return "expired" end
	return "locked"
end

--------------------------------------------------
-- RULE QUERIES (shared with UGCOutfitService via injection)
--------------------------------------------------

-- ugc_race_slot_blocks (cosmetic). nil race = unknown race -> allowed.
function UGCService.IsSlotAllowed(raceName: string?, slot: string): boolean
	if not UGCCatalogData.SLOT_SET[slot] then return false end
	if raceName == nil then return true end
	local blocks = UGCCatalogData.RACE_SLOT_BLOCKS[raceName]
	return not (blocks and blocks[slot])
end

function UGCService.IsOwned(playerId: string, assetId: number): boolean
	local s = stateOf(playerId)
	return s ~= nil and s.owned[assetId] == true
end

function UGCService.IsMarked(playerId: string, assetId: number): boolean
	local s = stateOf(playerId)
	return s ~= nil and s.wishlist[assetId] == true
end

-- THE single shared helper for average battle gold at a level (see CONSTANTS).
local function avgBattleGold(level: number): number
	local lvl = math.clamp(math.floor(level), MIN_LEVEL, MAX_LEVEL)
	local benchmarkAvg = BENCHMARK_BATTLE_GOLD / BENCHMARK_BATTLES
	return benchmarkAvg * (1 + lvl / GOLD_LEVEL_DIVISOR) / MEAN_LEVEL_FACTOR
end

local function priceLevel(playerId: string): number
	local lvl = _playerLevel and _playerLevel(playerId) or MIN_LEVEL
	if type(lvl) ~= "number" or lvl ~= lvl then
		return MIN_LEVEL
	end
	return math.clamp(math.floor(lvl), MIN_LEVEL, MAX_LEVEL)
end

-- Rental price for the NEXT paid rental of this item for this player.
function UGCService.GetRentPrice(playerId: string, assetId: number): number
	local s = stateOf(playerId)
	local count = s and s.rentCount[assetId] or 0
	local level = priceLevel(playerId)
	local base = UGCCatalogData.RENT_BASE_BATTLE_RATIO * avgBattleGold(level)
	return math.round(base * UGCCatalogData.RENT_ESCALATION ^ count)
end

--------------------------------------------------
-- LIFECYCLE
--------------------------------------------------

function UGCService.InitPlayer(playerId: string, player: Player?)
	local s = _states[playerId]
	if s then
		s.player = player or s.player
		return
	end
	_states[playerId] = {
		player = player,
		owned = {}, rentals = {}, rentCount = {}, trialUsed = {}, expired = {},
		prompted = {}, equips = {}, wishlist = {}, wishlistCount = 0, votes = {},
		isBattleActive = false,
	}
end

-- Release per-player state (prevents a per-player leak on leave).
function UGCService.ClearPlayer(playerId: string)
	_states[playerId] = nil
end

-- Re-verify ownership of every curated item (yields — call in task.spawn).
function UGCService.RefreshOwnership(playerId: string)
	local s = stateOf(playerId)
	if not s then return end
	local owned = 0
	for _, assetId in sortedIds(UGCCatalogData.Items) do
		if checkOwnedLive(s, assetId) then
			applyOwned(s, assetId)
			owned += 1
		end
	end
	print(`[UGCService] Ownership refreshed for {playerId}: {owned} curated item(s) owned`)
end

-- Equip/Unequip are locked from deployment start to battle end so the looks
-- spawned on the models always match what gets charged at battle end.
function UGCService.SetBattleActive(playerId: string, isActive: boolean)
	local s = stateOf(playerId)
	if s then s.isBattleActive = isActive end
end

--------------------------------------------------
-- ACTIONS (every caller is server code; remotes go through UGCRemoteHandler)
-- Return: (ok, errorMessage?, data?)
--------------------------------------------------

function UGCService.StartTrial(playerId: string, assetId: number): (boolean, string?, any)
	local s = stateOf(playerId)
	if not s or not itemOf(assetId) then return false, "Unknown item" end
	if checkOwnedLive(s, assetId) then
		applyOwned(s, assetId)
		return false, "You own this item — it is free forever"
	end
	if not isAvailable(assetId) then return false, "This item is not on sale" end
	if s.trialUsed[assetId] then return false, "Free trial already used for this item" end
	local r = s.rentals[assetId]
	if r and r.remaining > 0 then return false, "This item is already active" end
	s.trialUsed[assetId] = true
	s.expired[assetId] = nil
	s.rentals[assetId] = { mode = "trial", remaining = UGCCatalogData.TRIAL_BATTLES }
	print(`[UGCService] {playerId} started free trial of {assetId} ({UGCCatalogData.TRIAL_BATTLES} battles)`)
	return true, nil, { remaining = UGCCatalogData.TRIAL_BATTLES }
end

function UGCService.Rent(playerId: string, assetId: number): (boolean, string?, any)
	local s = stateOf(playerId)
	if not s or not itemOf(assetId) then return false, "Unknown item" end
	if checkOwnedLive(s, assetId) then
		applyOwned(s, assetId)
		return false, "You own this item — it is free forever"
	end
	if not isAvailable(assetId) then return false, "This item is not on sale" end
	if not _currency then return false, "Currency not wired" end

	local price = UGCService.GetRentPrice(playerId, assetId)
	local ok, err = _currency.Debit(playerId, { gold = price })
	if not ok then return false, err or "Insufficient gold" end

	local count = (s.rentCount[assetId] or 0) + 1
	s.rentCount[assetId] = count
	local current = s.rentals[assetId]
	local carry = if current and current.remaining > 0 then current.remaining else 0
	local remaining = carry + UGCCatalogData.RENT_BATTLES
	s.rentals[assetId] = { mode = "rent", remaining = remaining }
	s.expired[assetId] = nil
	print(string.format("[UGCService] %s rented %d for %d gold (rental #%d, level %d, avg battle gold %.1f) — %d battles left",
		playerId, assetId, price, count, priceLevel(playerId), avgBattleGold(priceLevel(playerId)), remaining))
	return true, nil, { price = price, remaining = remaining, nextPrice = UGCService.GetRentPrice(playerId, assetId) }
end

-- Server-side purchase prompt (curated items only).
function UGCService.PromptPurchase(playerId: string, assetId: number): (boolean, string?)
	local s = stateOf(playerId)
	if not s or not itemOf(assetId) then return false, "Unknown item" end
	if s.owned[assetId] then return false, "You already own this item" end
	if not isAvailable(assetId) then return false, "This item is not on sale" end
	local player = s.player
	if not player or player.Parent == nil then return false, "Player not in game" end
	local ok, err = pcall(MarketplaceService.PromptPurchase, MarketplaceService, player, assetId)
	if not ok then
		warn(`[UGCService] PromptPurchase failed for {assetId}: {err}`)
		return false, "Could not open the purchase prompt"
	end
	return true, nil
end

function UGCService.Equip(playerId: string, unitId: string, assetId: number): (boolean, string?, any)
	local s = stateOf(playerId)
	local item = itemOf(assetId)
	if not s or not item then return false, "Unknown item" end
	if s.isBattleActive then return false, "Looks cannot change during a battle" end
	if not _unitRace then return false, "Roster not wired" end
	local isOwnedUnit, raceName = _unitRace(playerId, unitId)
	if not isOwnedUnit then return false, "Unit not found" end
	if not UGCService.IsSlotAllowed(raceName, item.slot) then
		return false, `{raceName or "This unit"} cannot wear {item.slot} items`
	end

	-- ownership_persistence: re-verified live on equip.
	local isOwned = s.owned[assetId] == true or checkOwnedLive(s, assetId)
	if isOwned then
		applyOwned(s, assetId)
	else
		if not isAvailable(assetId) then return false, "This item is not on sale" end
		if not hasAccess(s, assetId) then
			return false, "Start a free trial, rent, or buy this item first"
		end
	end

	s.equips[unitId] = s.equips[unitId] or {}
	s.equips[unitId][item.slot] = assetId

	-- prompt_on_first_equip (policy compliance): once per unowned item.
	local didPrompt = false
	if not isOwned and not s.prompted[assetId] then
		s.prompted[assetId] = true
		didPrompt = UGCService.PromptPurchase(playerId, assetId)
	end
	return true, nil, { slot = item.slot, prompted = didPrompt }
end

function UGCService.Unequip(playerId: string, unitId: string, slot: string): (boolean, string?)
	local s = stateOf(playerId)
	if not s then return false, "No UGC state" end
	if not UGCCatalogData.SLOT_SET[slot] then return false, "Invalid slot" end
	if s.isBattleActive then return false, "Looks cannot change during a battle" end
	local slots = s.equips[unitId]
	if slots then
		slots[slot] = nil
		if next(slots) == nil then s.equips[unitId] = nil end
	end
	return true, nil
end

function UGCService.SetWishlist(playerId: string, assetId: number, isMarked: boolean): (boolean, string?)
	local s = stateOf(playerId)
	if not s or not itemOf(assetId) then return false, "Unknown item" end
	if isMarked then
		if s.wishlist[assetId] then return true, nil end
		if s.owned[assetId] then return false, "You already own this item" end
		if s.wishlistCount >= UGCCatalogData.WISHLIST_CAP then
			return false, UGCCatalogData.WISHLIST_FULL_MESSAGE
		end
		s.wishlist[assetId] = true
		s.wishlistCount += 1
	elseif s.wishlist[assetId] then
		s.wishlist[assetId] = nil
		s.wishlistCount -= 1
	end
	return true, nil
end

-- vote: 1 like, -1 dislike, 0 clear. Player sees only their own vote.
function UGCService.Rate(playerId: string, assetId: number, vote: number): (boolean, string?)
	local s = stateOf(playerId)
	if not s or not itemOf(assetId) then return false, "Unknown item" end
	if vote ~= 1 and vote ~= -1 and vote ~= 0 then return false, "Invalid vote" end
	local previous = s.votes[assetId] or 0
	if previous == vote then return true, nil end
	s.votes[assetId] = if vote ~= 0 then vote else nil

	local d = _pendingRatings[assetId] or { likes = 0, dislikes = 0 }
	d.likes += (if vote == 1 then 1 else 0) - (if previous == 1 then 1 else 0)
	d.dislikes += (if vote == -1 then 1 else 0) - (if previous == -1 then 1 else 0)
	_pendingRatings[assetId] = d
	return true, nil
end

-- Robux purchase finished (PromptPurchaseFinished said isPurchased). Never trust
-- the signal alone: re-verify with PlayerOwnsAsset (yields).
function UGCService.OnPurchaseFinished(playerId: string, assetId: number): boolean
	local s = stateOf(playerId)
	if not s or not itemOf(assetId) then return false end
	for attempt = 1, OWNERSHIP_RECHECK_ATTEMPTS do
		if checkOwnedLive(s, assetId) then
			applyOwned(s, assetId)
			print(`[UGCService] {playerId} bought {assetId} — permanent free use`)
			notify(playerId, "purchased", { assetId })
			return true
		end
		task.wait(RETRY_DELAY * attempt)
	end
	warn(`[UGCService] Purchase of {assetId} reported but ownership not confirmed for {playerId}`)
	return false
end

-- Battle END (any outcome). deployedUnitIds = the player's deployed roster units.
-- Each rented/trial item worn by >= 1 of them loses exactly 1 battle.
function UGCService.OnBattleCompleted(playerId: string, deployedUnitIds: { string }): { decremented: { number }, expired: { number } }
	local result = { decremented = {}, expired = {} }
	local s = stateOf(playerId)
	if not s then return result end
	s.isBattleActive = false

	local worn: { [number]: boolean } = {}
	for _, unitId in deployedUnitIds do
		local slots = s.equips[unitId]
		if slots then
			for _, assetId in slots do
				worn[assetId] = true
			end
		end
	end

	for _, assetId in sortedIds(worn) do
		local r = s.rentals[assetId]
		if r and not s.owned[assetId] then
			r.remaining -= 1
			table.insert(result.decremented, assetId)
			if r.remaining <= 0 then
				s.rentals[assetId] = nil
				s.expired[assetId] = true
				unequipEverywhere(s, assetId)
				table.insert(result.expired, assetId)
			end
		end
	end
	print(`[UGCService] Battle end for {playerId}: {#result.decremented} item use(s) counted, {#result.expired} expired`)
	notify(playerId, "expired", result.expired)
	return result
end

--------------------------------------------------
-- READ
--------------------------------------------------

-- Asset ids a player unit visibly wears (only items it still has access to).
function UGCService.GetUnitLookIds(playerId: string, unitId: string): { number }
	local out = {}
	local s = stateOf(playerId)
	local slots = s and s.equips[unitId]
	if not s or not slots then return out end
	for _, slot in UGCCatalogData.SLOTS do
		local id = slots[slot]
		if id and itemOf(id) and hasAccess(s, id) then
			table.insert(out, id)
		end
	end
	return out
end

-- Customize screen / UGC merchant view. Only curated items are listed.
-- unitId (optional): adds per-slot eligibility + that unit's equips.
function UGCService.GetView(playerId: string, unitId: string?): any
	local s = stateOf(playerId)
	if not s then return nil end
	local raceName: string? = nil
	local hasUnit = false
	if unitId and _unitRace then
		hasUnit, raceName = _unitRace(playerId, unitId)
	end
	local items = {}
	for _, assetId in sortedIds(UGCCatalogData.Items) do
		local item = UGCCatalogData.Items[assetId]
		local r = s.rentals[assetId]
		table.insert(items, {
			assetId = assetId,
			name = item.name,
			slot = item.slot,
			status = statusOf(s, assetId), -- owned | trial | rent | expired | locked
			remaining = if r then r.remaining else 0,
			isTrialUsed = s.trialUsed[assetId] == true,
			rentPrice = UGCService.GetRentPrice(playerId, assetId),
			rentCount = s.rentCount[assetId] or 0,
			isAvailable = isAvailable(assetId),
			isMarked = s.wishlist[assetId] == true,
			vote = s.votes[assetId] or 0,
			isEligible = if hasUnit then UGCService.IsSlotAllowed(raceName, item.slot) else nil,
		})
	end
	local gold = 0
	if _currency then
		local ok, bal = pcall(_currency.GetBalance, playerId)
		if ok and type(bal) == "table" then gold = bal.gold or 0 end
	end
	return {
		items = items,
		gold = gold,
		wishlistCount = s.wishlistCount,
		wishlistCap = UGCCatalogData.WISHLIST_CAP,
		isBattleActive = s.isBattleActive,
		equips = if hasUnit and unitId then s.equips[unitId] else nil,
	}
end

--------------------------------------------------
-- RATINGS AGGREGATE (private; per-server batching)
--------------------------------------------------

local _ratingStore: DataStore? = nil

local function ratingStore(): DataStore?
	local mode = _saveMode and _saveMode() or "memory"
	if mode == "memory" then return nil end
	if _ratingStore then return _ratingStore end
	local namespace = if mode == "studio" then "CTRBLXAI_Dev" else "CTRBLXAI_Live" -- SaveService naming
	local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, namespace .. "_UGCRatings")
	if not ok then
		warn(`[UGCService] Ratings DataStore unavailable: {store}`)
		return nil
	end
	_ratingStore = store
	return store
end

function UGCService.FlushRatings()
	if _isFlushing or next(_pendingRatings) == nil then return end
	_isFlushing = true
	local batch = _pendingRatings
	_pendingRatings = {}
	local store = ratingStore()
	if not store then
		print("[UGCService] Ratings flush skipped (memory mode) — batch discarded")
		_isFlushing = false
		return
	end
	for assetId, d in batch do
		if d.likes == 0 and d.dislikes == 0 then continue end
		local isSaved = false
		for attempt = 1, MAX_RETRIES do
			local ok, err = pcall(function()
				store:UpdateAsync(`asset_{assetId}`, function(old: any)
					local t = if type(old) == "table" then old else {}
					t.likes = math.max(0, (tonumber(t.likes) or 0) + d.likes)
					t.dislikes = math.max(0, (tonumber(t.dislikes) or 0) + d.dislikes)
					return t
				end)
			end)
			if ok then
				isSaved = true
				break
			end
			warn(`[UGCService] Ratings UpdateAsync {assetId} attempt {attempt}/{MAX_RETRIES} failed: {err}`)
			task.wait(RETRY_DELAY * attempt)
		end
		if not isSaved then
			-- Re-queue for the next flush rather than lose the votes.
			local p = _pendingRatings[assetId] or { likes = 0, dislikes = 0 }
			p.likes += d.likes
			p.dislikes += d.dislikes
			_pendingRatings[assetId] = p
		end
	end
	_isFlushing = false
end

function UGCService.StartRatingFlush()
	if _isFlushLoopStarted then return end
	_isFlushLoopStarted = true
	task.spawn(function()
		while true do
			task.wait(RATING_FLUSH_SECONDS)
			UGCService.FlushRatings()
		end
	end)
	game:BindToClose(function()
		UGCService.FlushRatings()
	end)
end

--------------------------------------------------
-- PERSISTENCE (folded into progression Key 3 by Main.server.lua)
-- Saved shape (string keys — DataStore JSON safe):
--   { v = 1,
--     r  = { ["<id>"] = { m = "t" | "r", n = remaining } },
--     c  = { ["<id>"] = paidRentalCount },
--     t  = { id, ... }  -- trial used
--     x  = { id, ... }  -- expired (red)
--     p  = { id, ... }  -- first-equip prompt shown
--     w  = { id, ... }  -- wishlist
--     rv = { ["<id>"] = 1 | -1 },
--     e  = { [unitId] = { [slot] = id } } }
-- Ownership is NEVER saved. Data for items no longer curated is KEPT (so a
-- re-curated item keeps its price history), but only curated items are usable.
--------------------------------------------------

local function idList(set: { [number]: boolean }): { number }
	return sortedIds(set)
end

function UGCService.Export(playerId: string): any
	local s = stateOf(playerId)
	if not s then return nil end
	local r, c, rv = {}, {}, {}
	for id, rental in s.rentals do
		if rental.remaining > 0 then
			r[tostring(id)] = { m = if rental.mode == "trial" then "t" else "r", n = rental.remaining }
		end
	end
	for id, count in s.rentCount do c[tostring(id)] = count end
	for id, vote in s.votes do rv[tostring(id)] = vote end
	local e = {}
	for unitId, slots in s.equips do
		local isKept = true
		if _unitRace then isKept = (_unitRace(playerId, unitId)) end
		if isKept and next(slots) ~= nil then e[unitId] = slots end
	end
	return {
		v = SAVE_VERSION, r = r, c = c,
		t = idList(s.trialUsed), x = idList(s.expired), p = idList(s.prompted),
		w = idList(s.wishlist), rv = rv, e = e,
	}
end

local function importIdSet(src: any, into: { [number]: boolean }): number
	local n = 0
	if type(src) ~= "table" then return n end
	for _, id in src do
		if isPositiveInt(id) and not into[id] then
			into[id] = true
			n += 1
		end
	end
	return n
end

function UGCService.Import(playerId: string, data: any)
	UGCService.InitPlayer(playerId, nil)
	local s = _states[playerId]
	if type(data) ~= "table" then return end -- old saves: no UGC payload

	if type(data.r) == "table" then
		for k, rental in data.r do
			local id = tonumber(k)
			if id and isPositiveInt(id) and type(rental) == "table" and isPositiveInt(rental.n) then
				s.rentals[id] = { mode = if rental.m == "t" then "trial" else "rent", remaining = rental.n }
			end
		end
	end
	if type(data.c) == "table" then
		for k, count in data.c do
			local id = tonumber(k)
			if id and isPositiveInt(id) and isPositiveInt(count) then s.rentCount[id] = count end
		end
	end
	if type(data.rv) == "table" then
		for k, vote in data.rv do
			local id = tonumber(k)
			if id and isPositiveInt(id) and (vote == 1 or vote == -1) then s.votes[id] = vote end
		end
	end
	importIdSet(data.t, s.trialUsed)
	importIdSet(data.x, s.expired)
	importIdSet(data.p, s.prompted)

	if type(data.w) == "table" then
		for _, id in data.w do
			if s.wishlistCount >= UGCCatalogData.WISHLIST_CAP then break end
			if isPositiveInt(id) and not s.wishlist[id] then
				s.wishlist[id] = true
				s.wishlistCount += 1
			end
		end
	end

	if type(data.e) == "table" then
		for unitId, slots in data.e do
			if type(unitId) == "string" and type(slots) == "table" then
				local clean = {}
				for slot, id in slots do
					if type(slot) == "string" and UGCCatalogData.SLOT_SET[slot] and isPositiveInt(id) then
						clean[slot] = id
					end
				end
				if next(clean) ~= nil then s.equips[unitId] = clean end
			end
		end
	end
	print(`[UGCService] Imported UGC state for {playerId}`)
end

return UGCService
