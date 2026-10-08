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
--   * Cart (replaces the wishlist, 2026-10-08): cap 50, blocked with
--     "Cart full (50)", auto-removed when owned, saved. Items are added during
--     battle; checkout ONLY outside battle (one bulk prompt, max 20 lines).
--   * Off sale (ugc_rules 41): an active trial/rental is honored to expiry and
--     stays equippable; new trials, rentals and purchases are blocked; the view
--     flags isOffSale so the UI shows an "Off sale" marker instead of Buy.
--   * Purchase (ugc_rules 44/53): a purchase made through OUR prompt (Buy, cart
--     checkout, first-equip prompt) CANCELS the rental and refunds its last paid
--     rent price in gold, once. A Roblox-website purchase PAUSES the rental; a
--     later loss of ownership (refund) resumes it. Ownership is re-checked at
--     battle end before charging (43).
--   * Paired items (51): an entry is owned only if BOTH parts are owned.
--   * Ratings: like/dislike per player (saved here); the PRIVATE aggregate lives
--     in UGCRatingService (split out 2026-10-08, ARC-005).
--
-- This service never touches the player save DataStore: Main.server.lua folds
-- Export() into the existing progression payload (Key 3), like GuildService.
--
-- Injections (ARC-004 / ARC-006 — all nil-safe):
--   SetCurrencyService(svc)          -- CurrencyService (Debit/Credit/GetBalance)
--   SetAvailabilityProvider(fn)      -- (assetId) -> boolean   (on-sale check, cached)
--   SetOffSaleProvider(fn)           -- (assetId) -> boolean   (definitely off sale)
--   SetUnitRaceProvider(fn)          -- (playerId, unitId) -> (isOwnedUnit, raceName?)
--   SetPlayerLevelProvider(fn)       -- (playerId) -> number   (price level)
--   SetSaveModeProvider(fn)          -- () -> "memory" | "studio" | "production"
--   SetChangeNotifier(fn)            -- (playerId, reason, { assetId }, extra?) -> ()
--                                       reasons: purchased | refunded {gold} | expired | battleEnded
--   SetLookFailureProvider(svc)      -- UGCOutfitService (self-wired): WasLookNotWorn / ClearLookRecords
--   SetRatingService(svc)            -- UGCRatingService: RecordVote / Flush / StartFlushLoop

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UGCCatalogData = require(ReplicatedStorage:WaitForChild("Content"):WaitForChild("UGCCatalogData"))

local UGCService = {}

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

local SAVE_VERSION = 3 -- v3 (2026-10-08): + 'lp' last paid rent price (refund, id 53). v2: cart 'k' replaced wishlist 'w'

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

local RETRY_DELAY = 1.0
local OWNERSHIP_RECHECK_ATTEMPTS = 3 -- purchase ownership can lag a moment
-- BUG-025: an in-game purchase marker is honoured only this long after OUR prompt opened (ugc_rules 53).
local PENDING_PURCHASE_WINDOW = 120 -- seconds; a server timer resolves every marker at the end
local PENDING_RESOLVE_GRACE = 15 -- seconds the timer's own ownership check may take

-- Roblox platform limits (MarketplaceService.PromptBulkPurchase, launched
-- 2024-07-10): avatar items only, server scripts only, at most 20 line items.
local BULK_PURCHASE_MAX_LINES = 20

local function enumItem(enumName: string, itemName: string): EnumItem?
	local ok, item = pcall(function()
		return ((Enum :: any)[enumName] :: any)[itemName]
	end)
	return if ok then item else nil
end
local PRODUCT_TYPE_ASSET = enumItem("MarketplaceProductType", "AvatarAsset")
local PRODUCT_TYPE_BUNDLE = enumItem("MarketplaceProductType", "AvatarBundle")

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
	cart: { [number]: boolean },        -- saved (cart_persistence)
	cartCount: number,
	pendingCheckout: { [number]: boolean }, -- entries in any open bulk prompt (cart or pair Buy); merged, never overwritten (BUG-025)
	isVerifying: boolean,
	votes: { [number]: number },         -- 1 like / -1 dislike
	isBattleActive: boolean,
	playerId: string,
	lastRentPrice: { [number]: number }, -- last PAID rent price per item; saved; consumed by the refund (id 53)
	pendingInGame: { [number]: number }, -- OUR prompt opened for it -> marker expiry (os.clock); session only, never saved (BUG-025)
}

local _states: { [string]: PlayerState } = {}

local _currency: any = nil
local _isAvailable: ((number) -> boolean)? = nil
local _isOffSale: ((number) -> boolean)? = nil
local _unitRace: ((string, string) -> (boolean, string?))? = nil
local _playerLevel: ((string) -> number)? = nil
local _saveMode: (() -> string)? = nil
local _notify: ((string, string, { number }, any?) -> ())? = nil
local _lookFailure: any = nil -- BUG-022: items no unit visibly wore this battle
local _ratings: any = nil -- UGCRatingService (private vote aggregate)

function UGCService.SetCurrencyService(svc: any) _currency = svc end
function UGCService.SetAvailabilityProvider(fn: (number) -> boolean) _isAvailable = fn end
function UGCService.SetOffSaleProvider(fn: (number) -> boolean) _isOffSale = fn end
function UGCService.SetUnitRaceProvider(fn: (string, string) -> (boolean, string?)) _unitRace = fn end
function UGCService.SetPlayerLevelProvider(fn: (string) -> number) _playerLevel = fn end
function UGCService.SetSaveModeProvider(fn: () -> string)
	_saveMode = fn
	if _ratings then _ratings.SetSaveModeProvider(fn) end
end
function UGCService.SetChangeNotifier(fn: (string, string, { number }, any?) -> ()) _notify = fn end
function UGCService.SetLookFailureProvider(svc: any) _lookFailure = svc end
function UGCService.SetRatingService(svc: any)
	_ratings = svc
	if svc and _saveMode then svc.SetSaveModeProvider(_saveMode) end
end

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

-- True only when the availability check KNOWS the item is off sale / limited /
-- sold out (drives the "Off sale" marker). Unknown is not off sale.
local function isOffSale(assetId: number): boolean
	return _isOffSale ~= nil and _isOffSale(assetId) == true
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

local function notify(playerId: string, reason: string, assetIds: { number }, extra: any?)
	if _notify and #assetIds > 0 then
		_notify(playerId, reason, assetIds, extra)
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

-- Asset ids that make up one catalog entry (1, or 2 for an L/R pair).
local function partsOf(assetId: number): { number }
	local item = itemOf(assetId)
	if item and item.assetId2 then
		return { assetId, item.assetId2 }
	end
	return { assetId }
end

-- Live PlayerOwnsAsset for one part (yields). nil = API error.
local function ownsPartLive(player: Player, partId: number): boolean?
	local ok, result = pcall(MarketplaceService.PlayerOwnsAsset, MarketplaceService, player, partId)
	if not ok then
		warn(`[UGCService] PlayerOwnsAsset failed for {partId}: {result}`)
		return nil
	end
	return result == true
end

-- Live ownership of a catalog ENTRY: every part must be owned (paired_items, 51).
-- On API error the cached answer is kept: no NEW free use is granted on error.
-- Losing ownership (e.g. a refund) resumes a paused rental (ugc_rules 44); with
-- nothing left, the item is locked and comes off every unit.
local function checkOwnedLive(s: PlayerState, assetId: number): boolean
	local player = s.player
	if not player or player.Parent == nil then
		return s.owned[assetId] == true
	end
	for _, partId in partsOf(assetId) do
		local owns = ownsPartLive(player, partId)
		if owns == nil then
			return s.owned[assetId] == true
		end
		if not owns then
			local wasOwned = s.owned[assetId] == true
			s.owned[assetId] = nil
			if wasOwned then
				local r = s.rentals[assetId]
				if r and r.remaining > 0 then
					print(`[UGCService] {assetId} no longer owned — paused {r.mode} resumes ({r.remaining} battle(s) left)`)
				else
					unequipEverywhere(s, assetId)
					print(`[UGCService] {assetId} no longer owned — locked`)
				end
			end
			return false
		end
	end
	s.owned[assetId] = true
	return true
end

local function removeFromCart(s: PlayerState, assetId: number)
	if s.cart[assetId] then
		s.cart[assetId] = nil
		s.cartCount -= 1
	end
end

-- Owned supersedes expiry and the cart (cart_auto_remove, id 31). A purchase
-- through OUR prompt (pendingInGame) CANCELS the rental and refunds its last paid
-- rent price once (ugc_rules 44/53). Any other purchase (Roblox website) PAUSES
-- the rental: it stays saved and is not charged while the item is owned.
local function applyOwned(s: PlayerState, assetId: number)
	s.owned[assetId] = true
	s.expired[assetId] = nil
	removeFromCart(s, assetId)
	local expiresAt = s.pendingInGame[assetId]
	s.pendingInGame[assetId] = nil
	if not expiresAt or os.clock() > expiresAt then return end -- no / expired marker: pause, no refund (BUG-025)
	s.rentals[assetId] = nil -- cancelled; rentCount kept (re-renting costs the next doubled price)
	local refund = s.lastRentPrice[assetId]
	if not refund or refund <= 0 then return end -- trial only / already refunded: no gold back
	local ok, err = false, "Currency not wired"
	if _currency then ok, err = pcall(_currency.Credit, s.playerId, { gold = refund }) end
	if not ok then
		warn(`[UGCService] Rent refund of {refund} gold for {assetId} failed for {s.playerId}: {err}`)
		return
	end
	s.lastRentPrice[assetId] = nil -- one refund per paid rental (no double credit); gold never clawed back
	print(`[UGCService] {s.playerId} bought {assetId} in game — rental cancelled, {refund} gold refunded`)
	notify(s.playerId, "refunded", { assetId }, { gold = refund })
end

-- BUG-025: marks an entry as bought through OUR prompt, then the SERVER resolves it at the end of the
-- window (owned -> applyOwned refund/cancel; not owned -> cleared). No prompt depends on the client.
local function markInGame(s: PlayerState, assetId: number)
	local expiresAt = os.clock() + PENDING_PURCHASE_WINDOW
	s.pendingInGame[assetId] = expiresAt
	task.delay(PENDING_PURCHASE_WINDOW, function()
		if _states[s.playerId] ~= s or s.pendingInGame[assetId] ~= expiresAt then return end -- resolved / re-marked
		local resolveBy = os.clock() + PENDING_RESOLVE_GRACE
		s.pendingInGame[assetId] = resolveBy
		s.pendingCheckout[assetId] = nil
		if checkOwnedLive(s, assetId) then -- yields; an API error counts as not owned (fail closed)
			applyOwned(s, assetId)
			notify(s.playerId, "purchased", { assetId })
		elseif s.pendingInGame[assetId] == resolveBy then
			s.pendingInGame[assetId] = nil
		end
	end)
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

-- (isOwnedUnit, raceName?) for a roster unit — read-only (look preview, 2026-10-08).
function UGCService.GetUnitRace(playerId: string, unitId: string): (boolean, string?)
	if not _unitRace then return false, nil end
	return _unitRace(playerId, unitId)
end

-- True when the player may wear/try this item at all (owned, trial or rent active).
function UGCService.HasAccess(playerId: string, assetId: number): boolean
	local s = stateOf(playerId)
	return s ~= nil and hasAccess(s, assetId)
end

function UGCService.IsOwned(playerId: string, assetId: number): boolean
	local s = stateOf(playerId)
	return s ~= nil and s.owned[assetId] == true
end

function UGCService.IsInCart(playerId: string, assetId: number): boolean
	local s = stateOf(playerId)
	return s ~= nil and s.cart[assetId] == true
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
		prompted = {}, equips = {}, cart = {}, cartCount = 0, votes = {},
		pendingCheckout = {}, isVerifying = false,
		isBattleActive = false,
		playerId = playerId, lastRentPrice = {}, pendingInGame = {},
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
		elseif not hasAccess(s, assetId) then
			-- Not owned and nothing left to use (e.g. refunded since the last
			-- session): the item is locked, so it cannot stay on a unit.
			unequipEverywhere(s, assetId)
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
	s.lastRentPrice[assetId] = price -- refund source if bought in game (id 53)
	local current = s.rentals[assetId]
	local carry = if current and current.remaining > 0 then current.remaining else 0
	local remaining = carry + UGCCatalogData.RENT_BATTLES
	s.rentals[assetId] = { mode = "rent", remaining = remaining }
	s.expired[assetId] = nil
	print(string.format("[UGCService] %s rented %d for %d gold (rental #%d, level %d, avg battle gold %.1f) — %d battles left",
		playerId, assetId, price, count, priceLevel(playerId), avgBattleGold(priceLevel(playerId)), remaining))
	return true, nil, { price = price, remaining = remaining, nextPrice = UGCService.GetRentPrice(playerId, assetId) }
end

-- Bulk-prompt lines for the part(s) of an unbundled pair NOT owned yet
-- (paired_items, id 51). Shared by Buy and cart checkout. Yields (live check per
-- part); a failed check keeps the part in the prompt (never grants free use).
local function unownedPartLines(player: Player, assetId: number): { any }
	local lines = {}
	for _, partId in partsOf(assetId) do
		if ownsPartLive(player, partId) ~= true then
			table.insert(lines, { Type = PRODUCT_TYPE_ASSET, Id = tostring(partId) })
		end
	end
	return lines
end

-- Opens the right Roblox prompt for ONE catalog entry (paired_items, id 51):
-- bundle -> PromptBundlePurchase; unbundled pair -> one bulk prompt holding the
-- part(s) not yet owned; single asset -> PromptPurchase. Returns (ok, err, mode).
local function promptEntry(player: Player, s: PlayerState, assetId: number): (boolean, string?, string?)
	local item = itemOf(assetId) :: UGCCatalogData.UGCItem
	local ok, err
	local mode = "single"
	if item.bundleId then
		mode = "bundle"
		ok, err = pcall(MarketplaceService.PromptBundlePurchase, MarketplaceService, player, item.bundleId)
	elseif item.assetId2 then
		mode = "bulk"
		if not PRODUCT_TYPE_ASSET then return false, "Could not open the purchase prompt", nil end
		local lines = unownedPartLines(player, assetId)
		if #lines == 0 then return false, "You already own both parts", nil end
		ok, err = pcall(MarketplaceService.PromptBulkPurchase, MarketplaceService, player, lines, {})
		if ok then s.pendingCheckout[assetId] = true end -- merged: never overwrites a cart checkout (BUG-025)
	else
		ok, err = pcall(MarketplaceService.PromptPurchase, MarketplaceService, player, assetId)
	end
	if not ok then
		warn(`[UGCService] Purchase prompt failed for {assetId}: {err}`)
		return false, "Could not open the purchase prompt", nil
	end
	markInGame(s, assetId) -- in-game purchase marker + server resolution (ids 44/53, BUG-025)
	return true, nil, mode
end

-- "Buy for Roblox Avatar" for one curated entry. buy_timing (id 21): purchases
-- finalize outside battle only — during battle the player adds it to the cart.
function UGCService.PromptPurchase(playerId: string, assetId: number): (boolean, string?, any)
	local s = stateOf(playerId)
	if not s or not itemOf(assetId) then return false, "Unknown item" end
	if s.isBattleActive then return false, "Add it to your cart — checkout opens after the battle" end
	if s.owned[assetId] then return false, "You already own this item" end
	if not isAvailable(assetId) then return false, "This item is off sale" end
	local player = s.player
	if not player or player.Parent == nil then return false, "Player not in game" end
	local ok, err, mode = promptEntry(player, s, assetId)
	if not ok then return false, err end
	return true, nil, { mode = mode }
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
		-- offsale_during_rental (id 41): an active trial/rental stays equippable even
		-- if the item went off sale; it just can't be started or re-rented.
		if not hasAccess(s, assetId) then
			return false, "Start a free trial, rent, or buy this item first"
		end
	end

	s.equips[unitId] = s.equips[unitId] or {}
	s.equips[unitId][item.slot] = assetId

	-- prompt_on_first_equip (policy compliance): once per unowned item. Off-sale
	-- items can't be bought, so they are not prompted (and not marked prompted).
	local didPrompt: boolean, promptMode: string? = false, nil
	if not isOwned and not s.prompted[assetId] and isAvailable(assetId) then
		s.prompted[assetId] = true
		local okPrompt, _, promptData = UGCService.PromptPurchase(playerId, assetId)
		didPrompt = okPrompt
		promptMode = if okPrompt and type(promptData) == "table" then promptData.mode else nil -- client verifies "bulk" (BUG-025)
	end
	return true, nil, { slot = item.slot, prompted = didPrompt, promptMode = promptMode }
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

-- Cart (cart_add_source / cart_cap / cart_offsale_items, ids 29/30/47). Adding
-- is allowed during battle. Removing always works, even for ids no longer in
-- the catalog (Tester D1).
function UGCService.SetInCart(playerId: string, assetId: number, isInCart: boolean): (boolean, string?)
	local s = stateOf(playerId)
	if not s then return false, "No UGC state" end
	if not isInCart then
		removeFromCart(s, assetId)
		return true, nil
	end
	if not itemOf(assetId) then return false, "Unknown item" end
	if s.cart[assetId] then return true, nil end
	if s.owned[assetId] then return false, "You already own this item" end
	if s.cartCount >= UGCCatalogData.CART_CAP then
		return false, UGCCatalogData.CART_FULL_MESSAGE
	end
	s.cart[assetId] = true
	s.cartCount += 1
	return true, nil
end

-- cart_checkout_location (id 45): ONLY outside battle. cart_checkout_method
-- (id 48): one PromptBulkPurchase with up to BULK_PURCHASE_MAX_LINES lines (a
-- bundle is 1 line, an unbundled pair is 2). Off-sale items stay in the cart and
-- are skipped (id 47). If the bulk prompt is unavailable, the first item gets a
-- single prompt and the client calls checkout again (sequential fallback).
function UGCService.CheckoutCart(playerId: string): (boolean, string?, any)
	local s = stateOf(playerId)
	if not s then return false, "No UGC state" end
	if s.isBattleActive then return false, "Checkout opens after the battle" end
	local player = s.player
	if not player or player.Parent == nil then return false, "Player not in game" end

	local lines, included, offSale = {}, {}, {}
	for _, assetId in sortedIds(s.cart) do
		local item = itemOf(assetId)
		if not item then continue end
		if s.owned[assetId] then
			removeFromCart(s, assetId)
			continue
		end
		if not isAvailable(assetId) then
			table.insert(offSale, assetId)
			continue
		end
		-- Same lines as Buy: a bundle is 1 line; an unbundled pair lists only its
		-- unowned part(s) (D1 fix, paired_items id 51).
		local entryLines: { any } = if item.bundleId
			then { { Type = PRODUCT_TYPE_BUNDLE, Id = tostring(item.bundleId) } }
			elseif item.assetId2 then unownedPartLines(player, assetId)
			else { { Type = PRODUCT_TYPE_ASSET, Id = tostring(assetId) } }
		if #entryLines == 0 then
			applyOwned(s, assetId) -- every part confirmed owned live
			continue
		end
		if #lines + #entryLines > BULK_PURCHASE_MAX_LINES then break end
		for _, line in entryLines do
			table.insert(lines, line)
		end
		table.insert(included, assetId)
	end
	if #included == 0 then
		return false, if #offSale > 0 then "Everything in your cart is off sale" else "Your cart is empty"
	end

	local data: any = { itemCount = #included, offSale = offSale, cartCount = s.cartCount }
	if PRODUCT_TYPE_ASSET and PRODUCT_TYPE_BUNDLE then
		local ok, err = pcall(MarketplaceService.PromptBulkPurchase, MarketplaceService, player, lines, {})
		if ok then
			for _, id in included do
				s.pendingCheckout[id] = true -- merged with any pending pair Buy (BUG-025)
				markInGame(s, id) -- ids 44/53
			end
			data.mode = "bulk"
			print(`[UGCService] {playerId} checkout: bulk prompt for {#included} item(s), {#lines} line(s)`)
			return true, nil, data
		end
		warn(`[UGCService] PromptBulkPurchase failed — single prompt fallback: {err}`)
	end
	local ok, err, mode = promptEntry(player, s, included[1])
	if not ok then return false, err end
	data.itemCount = 1
	data.mode = mode
	data.isSequential = true
	return true, nil, data
end

-- PromptBulkPurchaseFinished fires on the CLIENT only, so the client asks the
-- server to verify once the bulk prompt closes. Nothing the client says is
-- trusted: every pending entry is re-checked with PlayerOwnsAsset (yields).
function UGCService.VerifyCheckout(playerId: string): (boolean, string?, any)
	local s = stateOf(playerId)
	if not s then return false, "No UGC state" end
	if s.isVerifying then return false, "Already checking your purchase" end
	local remaining = sortedIds(s.pendingCheckout)
	if #remaining == 0 then return true, nil, { purchased = {} } end
	s.isVerifying = true
	table.clear(s.pendingCheckout)
	local purchased = {}
	for attempt = 1, OWNERSHIP_RECHECK_ATTEMPTS do
		local still = {}
		for _, assetId in remaining do
			if checkOwnedLive(s, assetId) then
				applyOwned(s, assetId)
				table.insert(purchased, assetId)
			else
				table.insert(still, assetId)
			end
		end
		remaining = still
		if #remaining == 0 then break end
		if attempt < OWNERSHIP_RECHECK_ATTEMPTS then task.wait(RETRY_DELAY * attempt) end
	end
	s.isVerifying = false
	for _, id in remaining do s.pendingInGame[id] = nil end -- not bought: a later website buy is not refunded
	print(`[UGCService] {playerId} checkout verified: {#purchased} item(s) now owned`)
	notify(playerId, "purchased", purchased)
	return true, nil, { purchased = purchased }
end

-- vote: 1 like, -1 dislike, 0 clear. Player sees only their own vote.
function UGCService.Rate(playerId: string, assetId: number, vote: number): (boolean, string?)
	local s = stateOf(playerId)
	if not s or not itemOf(assetId) then return false, "Unknown item" end
	if vote ~= 1 and vote ~= -1 and vote ~= 0 then return false, "Invalid vote" end
	local previous = s.votes[assetId] or 0
	if previous == vote then return true, nil end
	s.votes[assetId] = if vote ~= 0 then vote else nil
	if _ratings then _ratings.RecordVote(assetId, previous, vote) end
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

-- Our prompt closed WITHOUT a purchase: drop the in-game marker, so a later
-- Roblox-website purchase pauses the rental and gets no refund (ids 44/53).
function UGCService.ClearPendingPurchase(playerId: string, assetId: number)
	local s = stateOf(playerId)
	if s then s.pendingInGame[assetId] = nil end
end

-- Battle END (any outcome). deployedUnitIds = the player's deployed roster units.
-- Each rented/trial item worn by >= 1 of them loses exactly 1 battle.
function UGCService.OnBattleCompleted(playerId: string, deployedUnitIds: { string }): { decremented: { number }, expired: { number } }
	local result = { decremented = {}, expired = {} }
	local s = stateOf(playerId)
	if not s then return result end

	-- D3: looks/cart stay locked (isBattleActive) until the ownership re-checks
	-- (yield) and the usage decrement are done. pcall so the lock is released on
	-- every path, errors included.
	local ok, err = pcall(function()
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
			-- battle_end_ownership_check (id 43): re-check live before charging (yields;
			-- only worn items with a running trial/rental). Owned = paused, no charge.
			if r and r.remaining > 0 and checkOwnedLive(s, assetId) then
				applyOwned(s, assetId)
			elseif r and r.remaining > 0 and _lookFailure and _lookFailure.WasLookNotWorn(playerId, assetId) then
				print(`[UGCService] {assetId} was not visibly worn this battle — not charged`) -- BUG-022 (ugc_rules 50)
			elseif r and r.remaining > 0 then
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
	end)
	if _lookFailure then pcall(_lookFailure.ClearLookRecords, playerId) end -- every path (BUG-022)
	s.isBattleActive = false
	if not ok then
		warn(`[UGCService] Battle-end usage step failed for {playerId}: {err}`)
	end
	print(`[UGCService] Battle end for {playerId}: {#result.decremented} item use(s) counted, {#result.expired} expired`)
	notify(playerId, "expired", result.expired)
	if _notify then _notify(playerId, "battleEnded", result.decremented) end -- screens rebuild after every battle
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
		local status = statusOf(s, assetId)
		table.insert(items, {
			assetId = assetId,
			name = item.name,
			slot = item.slot,
			status = status, -- owned | trial | rent | expired | locked
			statusCategory = UGCCatalogData.STATUS_FILTER_OF[status], -- Permanent | Rented | OutOfUse | nil (loadout_ui_spec 70)
			typeCategory = UGCCatalogData.SLOT_FILTER_TYPE[item.slot], -- Type filter (loadout_ui_spec 69)
			isTrial = status == "trial",
			refundOnBuy = s.lastRentPrice[assetId] or 0, -- gold back if bought in game (id 53)
			remaining = if r then r.remaining else 0,
			isTrialUsed = s.trialUsed[assetId] == true,
			rentPrice = UGCService.GetRentPrice(playerId, assetId),
			rentCount = s.rentCount[assetId] or 0,
			isAvailable = isAvailable(assetId),
			isOffSale = isOffSale(assetId), -- UI: "Off sale" marker instead of Buy (ids 41/47)
			isPaused = s.owned[assetId] == true and r ~= nil and r.remaining > 0, -- id 44
			isInCart = s.cart[assetId] == true,
			assetId2 = item.assetId2,
			bundleId = item.bundleId,
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
		cartCount = s.cartCount,
		cartCap = UGCCatalogData.CART_CAP,
		isBattleActive = s.isBattleActive,
		equips = if hasUnit and unitId then s.equips[unitId] else nil,
	}
end

--------------------------------------------------
-- RATINGS AGGREGATE — moved to UGCRatingService (2026-10-08, ARC-005).
-- Delegators keep the existing public API working.
--------------------------------------------------

function UGCService.FlushRatings()
	if _ratings then _ratings.Flush() end
end

function UGCService.StartRatingFlush()
	if not _ratings then
		warn("[UGCService] Rating service not wired — vote totals are not aggregated")
		return
	end
	_ratings.StartFlushLoop()
end

--------------------------------------------------
-- PERSISTENCE (folded into progression Key 3 by Main.server.lua)
-- Saved shape (string keys — DataStore JSON safe):
--   { v = 3,
--     r  = { ["<id>"] = { m = "t" | "r", n = remaining } },
--     c  = { ["<id>"] = paidRentalCount },
--     t  = { id, ... }  -- trial used
--     x  = { id, ... }  -- expired (red)
--     p  = { id, ... }  -- first-equip prompt shown
--     k  = { id, ... }  -- cart (v2; v1 saves had the wishlist in w -> migrated)
--     rv = { ["<id>"] = 1 | -1 },
--     lp = { ["<id>"] = lastPaidRentPrice },  -- v3: refund source, cleared once refunded (id 53)
--     e  = { [unitId] = { [slot] = id } } }
-- Ownership is NEVER saved. A paused rental of an owned item IS saved (id 44).
-- Data for items no longer curated is KEPT (so a re-curated item keeps its price
-- history) — except the cart, which drops them on Import (Tester D1).
--------------------------------------------------

local function idList(set: { [number]: boolean }): { number }
	return sortedIds(set)
end

function UGCService.Export(playerId: string): any
	local s = stateOf(playerId)
	if not s then return nil end
	local r, c, rv, lp = {}, {}, {}, {}
	for id, rental in s.rentals do
		if rental.remaining > 0 then
			r[tostring(id)] = { m = if rental.mode == "trial" then "t" else "r", n = rental.remaining }
		end
	end
	for id, count in s.rentCount do c[tostring(id)] = count end
	for id, price in s.lastRentPrice do lp[tostring(id)] = price end
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
		k = idList(s.cart), rv = rv, e = e, lp = lp,
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
	if type(data.lp) == "table" then
		for k, price in data.lp do
			local id = tonumber(k)
			if id and isPositiveInt(id) and isPositiveInt(price) then s.lastRentPrice[id] = price end
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

	-- Cart (v2 'k'); v1 saves stored the wishlist in 'w' -> migrated into the cart.
	-- Tester D1 fix: ids no longer in the catalog are dropped, so they never
	-- count toward the cap.
	local cartSrc = if type(data.k) == "table" then data.k else data.w
	if type(cartSrc) == "table" then
		for _, id in cartSrc do
			if s.cartCount >= UGCCatalogData.CART_CAP then break end
			if isPositiveInt(id) and itemOf(id) and not s.cart[id] then
				s.cart[id] = true
				s.cartCount += 1
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
