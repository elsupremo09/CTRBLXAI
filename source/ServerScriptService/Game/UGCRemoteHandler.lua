--!strict
-- UGCRemoteHandler.lua
-- CTRBLXAI | UGC Rental & Ownership — remote gate (SEC-001 / SEC-002 / SEC-003)
--
-- Every UGC remote passes the same gate: right player (session player), per-player
-- per-request rate limit, strict argument types. The client sends ids only; all
-- prices, ownership and results are decided by UGCService / UGCOutfitService.
--
-- Threat model (SEC-003):
--   * Free items via fake purchase  -> PromptPurchaseFinished is re-verified with
--     PlayerOwnsAsset before anything is granted (UGCService.OnPurchaseFinished).
--   * Cheap rentals via client price -> price is computed server-side only.
--   * Dodging the battle charge      -> Equip/Unequip locked while a battle runs.
--   * Off-sale / non-curated items   -> every action checks the curated catalog
--     and the cached GetProductInfo result (fail closed).
--   * Remote spam / throttle abuse   -> rate limit per request type.
--   * Ballot stuffing                -> one vote per player per item, changes only
--     adjust the delta; totals are private (never sent to clients).
--   * Fake bulk checkout result      -> PromptBulkPurchaseFinished is client-only,
--     so the client only ASKS for verification; the server re-checks every
--     pending entry with PlayerOwnsAsset (UGCService.VerifyCheckout).
--   * Refund farming (ugc_rules 53)  -> the rent refund needs OUR prompt + live
--     ownership, is paid once per paid rental (cleared from the save), and a
--     declined prompt clears the marker (UGCService.ClearPendingPurchase); every
--     marker also expires and is resolved by the server itself (BUG-025).
--   * Enemy preview (inspector)      -> only units the outfit service planned this battle; worn
--     look only, no try-on; same 0.5 s Preview limit; display copy only (no state).
--   * Mid-battle purchases / spam    -> checkout and Buy are refused during battle
--     (buy_timing, ugc_rules 21/45); checkout/verify have longer rate limits.
--
-- Init(deps):
--   deps.playerId      : string           -- Main's PLAYER_ID (save/currency key)
--   deps.sessionPlayer : Player
--   deps.ugc           : UGCService
--   deps.outfit        : UGCOutfitService

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UGCEvents = require(ReplicatedStorage:WaitForChild("CTRBLXAI"):WaitForChild("Remotes"):WaitForChild("UGCEvents")) :: any
local UGCCatalogData = require(ReplicatedStorage:WaitForChild("Content"):WaitForChild("UGCCatalogData"))

local UGCRemoteHandler = {}

local RATE_LIMIT_SECONDS = 0.25 -- SEC-001: per-player, per-request minimum spacing
-- Heavier requests (each opens a prompt or makes several ownership calls).
local RATE_LIMIT_OVERRIDES: { [string]: number } = { Checkout = 2, Preview = 0.5 }
local MAX_TRY_ON = 11 -- one per UGC slot (SEC-001: bounded input)
-- CartVerify is never refused by the rate limit (a refused verify left purchase markers set,
-- BUG-025): calls are serialized per player and spaced, with at most one waiting (SEC-001).
local VERIFY_SPACING_SECONDS = 3
local VERIFY_POLL_SECONDS = 0.25
local MAX_UNIT_ID_LENGTH = 64

local _playerId: string? = nil
local _sessionPlayer: Player? = nil
local _ugc: any = nil
local _outfit: any = nil
local _lastCallAt: { [string]: number } = {}
local _verifyBusy: { [string]: boolean } = {}
local _verifyQueued: { [string]: boolean } = {}
local _connections: { RBXScriptConnection } = {}
local _isInitialized = false

--------------------------------------------------
-- VALIDATION
--------------------------------------------------

local function isAssetId(v: any): boolean
	return type(v) == "number" and v == v and v > 0 and v < 2 ^ 53 and math.floor(v) == v
end

local function isUnitId(v: any): boolean
	return type(v) == "string" and #v > 0 and #v <= MAX_UNIT_ID_LENGTH
end

local function fail(msg: string)
	return { ok = false, error = msg }
end

-- Readiness + right player (no rate limit). Returns an error message or nil.
local function sessionGate(player: Player): string?
	if not _isInitialized or not _ugc or not _playerId then return "UGC not ready" end
	if _sessionPlayer and player ~= _sessionPlayer then return "Not your session" end
	return nil
end

-- Common gate (SEC-001). Returns an error message or nil.
local function guard(player: Player, key: string): string?
	local sg = sessionGate(player); if sg then return sg end
	local now = os.clock()
	local rk = `{player.UserId}:{key}`
	local last = _lastCallAt[rk]
	if last and now - last < (RATE_LIMIT_OVERRIDES[key] or RATE_LIMIT_SECONDS) then return "Too fast — try again" end
	_lastCallAt[rk] = now
	return nil
end

local function result(ok: boolean, err: string?, data: any)
	if not ok then return fail(err or "Request failed") end
	return { ok = true, data = data }
end

--------------------------------------------------
-- HANDLERS
--------------------------------------------------

local function onGetView(player: Player, unitId: any)
	local g = guard(player, "View"); if g then return fail(g) end
	if unitId ~= nil and not isUnitId(unitId) then return fail("Invalid unit") end
	return { ok = true, data = _ugc.GetView(_playerId, unitId) }
end

local function onGetWorn(player: Player, unitId: any)
	local g = guard(player, "Worn"); if g then return fail(g) end
	if not isUnitId(unitId) then return fail("Invalid unit") end
	local pid = _playerId :: string
	local ids = if _outfit then _outfit.GetWornIds(pid, unitId) else _ugc.GetUnitLookIds(pid, unitId)
	local items = {}
	for _, id in ids do
		local item = UGCCatalogData.Items[id]
		if item then
			-- The requesting player's OWN status for each item (loadout_ui_spec 94); works for
			-- enemy units too (their looks come from UGCOutfitService). Facts only (NET-003).
			local status, remaining = "locked", 0
			if _ugc.GetItemStatus then status, remaining = _ugc.GetItemStatus(pid, id) end
			table.insert(items, {
				assetId = id, name = item.name, slot = item.slot,
				assetId2 = item.assetId2, bundleId = item.bundleId,
				isOwned = _ugc.IsOwned(pid, id), isInCart = _ugc.IsInCart(pid, id),
				isOffSale = if _outfit then _outfit.IsOffSale(id) else false,
				isFree = if _outfit and _outfit.IsFree then _outfit.IsFree(id) else false,
				creator = if _outfit and _outfit.GetCreatorName then _outfit.GetCreatorName(id) else nil,
				status = status, remaining = remaining,
			})
		end
	end
	return { ok = true, data = { items = items } }
end

local function onTrial(player: Player, assetId: any)
	local g = guard(player, "Trial"); if g then return fail(g) end
	if not isAssetId(assetId) then return fail("Invalid item") end
	return result(_ugc.StartTrial(_playerId, assetId))
end

local function onRent(player: Player, assetId: any)
	local g = guard(player, "Rent"); if g then return fail(g) end
	if not isAssetId(assetId) then return fail("Invalid item") end
	return result(_ugc.Rent(_playerId, assetId))
end

local function onEquip(player: Player, unitId: any, assetId: any)
	local g = guard(player, "Equip"); if g then return fail(g) end
	if not isUnitId(unitId) or not isAssetId(assetId) then return fail("Invalid request") end
	return result(_ugc.Equip(_playerId, unitId, assetId))
end

local function onUnequip(player: Player, unitId: any, slot: any)
	local g = guard(player, "Unequip"); if g then return fail(g) end
	if not isUnitId(unitId) or type(slot) ~= "string" or not UGCCatalogData.SLOT_SET[slot] then
		return fail("Invalid request")
	end
	return result(_ugc.Unequip(_playerId, unitId, slot))
end

local function onCart(player: Player, assetId: any, isInCart: any)
	local g = guard(player, "Cart"); if g then return fail(g) end
	if not isAssetId(assetId) or type(isInCart) ~= "boolean" then return fail("Invalid request") end
	return result(_ugc.SetInCart(_playerId, assetId, isInCart))
end

local function onCheckout(player: Player)
	local g = guard(player, "Checkout"); if g then return fail(g) end
	return result(_ugc.CheckoutCart(_playerId))
end

-- BUG-025: queued, never refused. One verify runs at a time per player; one more may wait
-- its turn; further calls while one waits fold into it (it re-checks every pending entry).
local function onCartVerify(player: Player)
	local g = sessionGate(player); if g then return fail(g) end
	local rk = `{player.UserId}:CartVerify`
	if _verifyBusy[rk] then
		if _verifyQueued[rk] then return { ok = true, data = { purchased = {}, isQueued = true } } end
		_verifyQueued[rk] = true
		while _verifyBusy[rk] do task.wait(VERIFY_POLL_SECONDS) end
		_verifyQueued[rk] = nil
	end
	_verifyBusy[rk] = true
	local last = _lastCallAt[rk]
	if last and os.clock() - last < VERIFY_SPACING_SECONDS then task.wait(VERIFY_SPACING_SECONDS - (os.clock() - last)) end
	_lastCallAt[rk] = os.clock()
	local ok, vOk, vErr, vData = pcall(_ugc.VerifyCheckout, _playerId)
	_verifyBusy[rk] = nil
	if not ok then
		warn(`[UGCRemoteHandler] VerifyCheckout failed: {vOk}`)
		return fail("Could not check your purchase")
	end
	return result(vOk, vErr, vData)
end

local function onRate(player: Player, assetId: any, vote: any)
	local g = guard(player, "Rate"); if g then return fail(g) end
	if not isAssetId(assetId) or (vote ~= 1 and vote ~= 0 and vote ~= -1) then return fail("Invalid request") end
	return result(_ugc.Rate(_playerId, assetId, vote))
end

-- Look preview (Outfit tab). Read-only: builds a display model, changes no state.
-- tryOnIds: items shown on top of the worn outfit (same slot replaced). Any curated
-- item may be tried on (previewing before renting/buying is the point); race slot
-- blocks still apply, same as equipping.
local function onPreview(player: Player, unitId: any, tryOnIds: any)
	local g = guard(player, "Preview"); if g then return fail(g) end
	if not isUnitId(unitId) then return fail("Invalid unit") end
	if tryOnIds ~= nil and type(tryOnIds) ~= "table" then return fail("Invalid try-on list") end
	if not _outfit or not _outfit.BuildPreview then return fail("Preview unavailable") end
	local pid = _playerId :: string
	local isOwnedUnit, raceName = _ugc.GetUnitRace(pid, unitId)
	if not isOwnedUnit then
		-- Inspector Outfit tab (loadout_ui_spec 96): an ENEMY of the current battle may be
		-- previewed wearing exactly its battle look. Still read-only: BuildPreview only makes
		-- a display copy under this player's PlayerGui (no equip, save, trial or battle look).
		-- No try-on on enemies (Try on is Outfit-tab only, id 83).
		local enemyRace = if _outfit.GetEnemyRace then _outfit.GetEnemyRace(unitId) else nil
		if not enemyRace then return fail("Unknown unit") end
		if type(tryOnIds) == "table" and next(tryOnIds) ~= nil then return fail("Try on is not available here") end
		raceName = enemyRace
	end
	-- Start from what the unit wears, keyed by slot.
	local bySlot: { [string]: number } = {}
	local worn = if _outfit.GetWornIds then _outfit.GetWornIds(pid, unitId) else _ugc.GetUnitLookIds(pid, unitId)
	for _, id in worn do
		local item = UGCCatalogData.Items[id]
		if item then bySlot[item.slot] = id end
	end
	local count = 0
	for _, id in (tryOnIds or {}) :: { any } do
		count += 1
		if count > MAX_TRY_ON then return fail("Too many try-on items") end
		if not isAssetId(id) then return fail("Invalid item") end
		local item = UGCCatalogData.Items[id]
		if not item then return fail("Not a curated item") end
		if _ugc.IsSlotAllowed(raceName, item.slot) then bySlot[item.slot] = id end
	end
	local ids = {}
	for _, slot in UGCCatalogData.SLOTS do
		if bySlot[slot] then table.insert(ids, bySlot[slot]) end
	end
	-- Pass unitId + pid ONLY for the player's own unit so the preview shows its
	-- body tint. Enemy previews (isOwnedUnit false) pass nil → no tint lookup.
	local previewUnitId = if isOwnedUnit then unitId else nil
	local previewPid = if isOwnedUnit then pid else nil
	local ok, err = _outfit.BuildPreview(player, raceName, ids, previewUnitId, previewPid)
	if not ok then return fail(err or "Preview failed") end
	return { ok = true, data = { modelName = "PreviewModel", folderName = "UGCPreview" } }
end

local function onPurchase(player: Player, assetId: any)
	local g = guard(player, "Purchase"); if g then return fail(g) end
	if not isAssetId(assetId) then return fail("Invalid item") end
	return result(_ugc.PromptPurchase(_playerId, assetId))
end

--------------------------------------------------
-- INIT
--------------------------------------------------

function UGCRemoteHandler.Init(deps: any)
	if _isInitialized then return end
	if type(deps) ~= "table" or not deps.ugc or type(deps.playerId) ~= "string" then
		warn("[UGCRemoteHandler] Init missing deps — UGC remotes disabled")
		return
	end
	_playerId = deps.playerId
	_sessionPlayer = deps.sessionPlayer
	_ugc = deps.ugc
	_outfit = deps.outfit
	_isInitialized = true

	UGCEvents.GetUGCView.OnServerInvoke = onGetView
	UGCEvents.GetUnitWornUGC.OnServerInvoke = onGetWorn
	UGCEvents.RequestUGCTrial.OnServerInvoke = onTrial
	UGCEvents.RequestUGCRent.OnServerInvoke = onRent
	UGCEvents.RequestUGCEquip.OnServerInvoke = onEquip
	UGCEvents.RequestUGCUnequip.OnServerInvoke = onUnequip
	UGCEvents.RequestUGCCart.OnServerInvoke = onCart
	UGCEvents.RequestUGCCheckout.OnServerInvoke = onCheckout
	UGCEvents.RequestUGCCartVerify.OnServerInvoke = onCartVerify
	UGCEvents.RequestUGCRate.OnServerInvoke = onRate
	UGCEvents.RequestUGCPurchase.OnServerInvoke = onPurchase
	if UGCEvents.RequestUGCPreview then UGCEvents.RequestUGCPreview.OnServerInvoke = onPreview end

	-- Server -> client facts (expiry at battle end, confirmed purchases).
	-- extra: e.g. { gold = n } for "refunded" (ugc_rules 53). Facts only (NET-003).
	_ugc.SetChangeNotifier(function(_pid: string, reason: string, assetIds: { number }, extra: any?)
		local p = _sessionPlayer
		if p and p.Parent then
			UGCEvents.UGCStateChanged:FireClient(p, { reason = reason, assetIds = assetIds, extra = extra })
		end
	end)

	-- Fires for prompts opened from the server OR the client. Re-verified inside
	-- OnPurchaseFinished — the signal alone grants nothing.
	table.insert(_connections, MarketplaceService.PromptPurchaseFinished:Connect(
		function(player: Player, assetId: number, isPurchased: boolean)
			if not _playerId then return end
			if _sessionPlayer and player ~= _sessionPlayer then return end
			if not isAssetId(assetId) then return end
			-- Either part of a pair resolves to its catalog entry (paired_items, id 51).
			local entryId = UGCCatalogData.ENTRY_BY_ASSET[assetId]
			if not entryId then return end
			if not isPurchased then
				-- Declined: a later Roblox-website purchase is not an in-game one (ids 44/53).
				_ugc.ClearPendingPurchase(_playerId, entryId)
				return
			end
			task.spawn(_ugc.OnPurchaseFinished, _playerId, entryId)
		end))

	-- Paired entries sold as a bundle (ugc_catalog.bundle_id). Same rule: the
	-- signal only triggers a re-verification of every entry using that bundle.
	table.insert(_connections, MarketplaceService.PromptBundlePurchaseFinished:Connect(
		function(player: Player, bundleId: number, wasPurchased: boolean)
			if not _playerId then return end
			if _sessionPlayer and player ~= _sessionPlayer then return end
			if not isAssetId(bundleId) then return end
			for entryId, item in UGCCatalogData.Items do
				if item.bundleId == bundleId then
					if wasPurchased then
						task.spawn(_ugc.OnPurchaseFinished, _playerId, entryId)
					else
						_ugc.ClearPendingPurchase(_playerId, entryId) -- declined (ids 44/53)
					end
				end
			end
		end))

	print("[UGCRemoteHandler] UGC remotes wired")
end

function UGCRemoteHandler.Shutdown()
	for _, c in _connections do c:Disconnect() end
	table.clear(_connections)
	table.clear(_lastCallAt)
	table.clear(_verifyBusy)
	table.clear(_verifyQueued)
end

return UGCRemoteHandler
