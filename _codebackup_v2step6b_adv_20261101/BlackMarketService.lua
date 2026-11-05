--!strict
-- BlackMarketService.lua
-- CTRBLXAI | Black Market map object = a paid in-battle shop (v2 build step 6b, 2026-11-01).
--
-- DESIGN (CTRBLXAI.db objects_encounters 31, LOCKED - USER DECISION 2026-11-01 v2):
--   * Interacting is free and repeatable. The stock is 6 items, rolled ONCE per object per
--     battle from the battle seed + the object ID. It never refills; each item is bought once.
--   * Each slot rolls Rare 75% / Epic 25% (never Exalted or above). Item level = the map level
--     (the same level the Merchant shelf and battle loot use), random slot (weapons, off-hands,
--     armour - the same pool as loot and the Merchant), normal loot bonus lines.
--   * Price = floor(Merchant price x 75 / 100). Merchant price = MerchantService.PriceToBuy
--     (economy_framework 15). Merchant level, Fortune and Gold Boost never change it.
--   * Gold comes straight from the balance during the battle; no credit, no refund. A bought
--     item goes into the inventory at once and is kept whatever the battle result.
--   * Breaking the object ends further buying.
--
-- OWNS: the stock of each Black Market in the current battle and the buy transaction.
-- MUST NOT OWN: the gold balance (CurrencyService), item generation (ItemGenerator), prices
--   (MerchantService.PriceToBuy), the inventory (InventoryService).
-- SECURITY (SEC-001 / SEC-002): the client sends only (objectId, slot). The server checks the
--   player, battle, object, slot and gold, and sets the price itself.
-- Dependencies are injected by Main (ARC-006) and are nil-safe.

local BlackMarketService = {}

local SLOT_COUNT = 6
local RARE_CHANCE_PCT = 75          -- Rare 75% / Epic 25%
local PRICE_PCT = 75                -- 25% off the Merchant price
local RATE_LIMIT_SECONDS = 0.2
local SEED_OFFSET = 424243          -- keeps this roll apart from other battle-seed rolls

--------------------------------------------------
-- INJECTED DEPENDENCIES
--------------------------------------------------

local _itemGenerator: any = nil
local _merchant: any = nil
local _currency: any = nil
local _inventory: any = nil
local _itemDisplay: any = nil
local _weaponData: any = nil
local _armorData: any = nil
local _player: Player? = nil
local _onOpened: ((payload: any) -> ())? = nil

function BlackMarketService.SetItemGenerator(svc: any) _itemGenerator = svc end
function BlackMarketService.SetMerchantService(svc: any) _merchant = svc end
function BlackMarketService.SetCurrencyService(svc: any) _currency = svc end
function BlackMarketService.SetInventoryService(svc: any) _inventory = svc end
function BlackMarketService.SetItemDisplay(svc: any) _itemDisplay = svc end
function BlackMarketService.SetContentData(weaponData: any, armorData: any)
	_weaponData = weaponData
	_armorData = armorData
end
function BlackMarketService.SetSessionPlayer(p: Player?) _player = p end
-- Called with the shop payload when a player unit opens a Black Market (Main fires the remote).
function BlackMarketService.SetOpenedHandler(fn: ((payload: any) -> ())?) _onOpened = fn end

--------------------------------------------------
-- BATTLE STATE
--------------------------------------------------

local _state: any = nil            -- current battle state (nil = no battle; buying refused)
local lastCallAt: { [string]: number } = {}

-- Main calls this when a battle starts / ends.
function BlackMarketService.BeginBattle(state: any)
	_state = state
	if state then state.blackMarkets = {} end
end

function BlackMarketService.EndBattle()
	_state = nil
end

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function hashString(s: string): number
	local h = 0
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 2147483647
	end
	return h
end

local cachedPool: { string }? = nil
local function equipPool(): { string }
	if cachedPool then return cachedPool end
	local pool: { string } = {}
	if _weaponData and _weaponData.Archetypes then
		for id, def in _weaponData.Archetypes do
			if def.category == "Weapon" or def.category == "OffHand" then
				table.insert(pool, id)
			end
		end
	end
	if _armorData and _armorData.Archetypes then
		for id, def in _armorData.Archetypes do
			if def.category == "Armor" then
				table.insert(pool, id)
			end
		end
	end
	table.sort(pool)
	cachedPool = pool
	return pool
end

local function objectAlive(state: any, objId: string): boolean
	for _, o in state.objects or {} do
		if o.id == objId and o.type == "Black Market" then
			return true
		end
	end
	return false
end

local function goldOf(playerId: string): number
	if not (_currency and _currency.GetBalance) then return 0 end
	local b = _currency.GetBalance(playerId)
	return (b and b.gold) or 0
end

-- Roll (once) and return the stock of one Black Market in this battle.
local function stockFor(state: any, objId: string): { any }?
	state.blackMarkets = state.blackMarkets or {}
	local existing = state.blackMarkets[objId]
	if existing then return existing end
	if not (_itemGenerator and _itemGenerator.GenerateFromPool and _merchant and _merchant.PriceToBuy) then
		warn("[BlackMarketService] ItemGenerator / MerchantService not wired")
		return nil
	end
	local pool = equipPool()
	if #pool == 0 then
		warn("[BlackMarketService] No equipment archetypes to stock")
		return nil
	end
	local level = math.max(1, math.floor(tonumber(state.mapLevel) or 1))
	local baseSeed = ((tonumber(state.battleSeed) or 0) + hashString(objId) + SEED_OFFSET) % 2147483647
	local rng = Random.new(baseSeed)
	local slots = {}
	for slot = 1, SLOT_COUNT do
		local rarity = if rng:NextInteger(1, 100) <= RARE_CHANCE_PCT then "Rare" else "Epic"
		local archetypeId = pool[rng:NextInteger(1, #pool)]
		local slotSeed = baseSeed + slot * 7919
		local ok, item = pcall(_itemGenerator.GenerateFromPool, { archetypeId }, level, rarity, slotSeed, "BlackMarket")
		local merchantPrice = if ok and type(item) == "table" then _merchant.PriceToBuy(item) else nil
		if ok and type(item) == "table" and merchantPrice then
			table.insert(slots, {
				slot = slot,
				item = item,
				price = math.floor(merchantPrice * PRICE_PCT / 100),
				bought = false,
			})
		else
			warn(`[BlackMarketService] Slot {slot} could not be stocked ({archetypeId}, {rarity}): {tostring(item)}`)
		end
	end
	state.blackMarkets[objId] = slots
	print(`[BlackMarketService] {objId} stocked {#slots} item(s) at level {level}`)
	return slots
end

local function payloadFor(state: any, objId: string, playerId: string): any?
	local slots = stockFor(state, objId)
	if not slots then return nil end
	local items = {}
	for _, s in slots do
		local item = s.item
		table.insert(items, {
			slot = s.slot,
			name = item.displayName or item.name or item.baseArchetypeId,
			level = item.itemLevel,
			rarity = item.rarityId,
			price = s.price,
			bought = s.bought,
			detail = if _itemDisplay and _itemDisplay.buildItemEntry then _itemDisplay.buildItemEntry(item) else nil,
		})
	end
	return { objectId = objId, items = items, gold = goldOf(playerId) }
end

--------------------------------------------------
-- PUBLIC
--------------------------------------------------

-- ObjectEffectService's Black Market handler calls this when a unit interacts.
-- Only a player unit opens the shop screen; an enemy interaction does nothing.
function BlackMarketService.Open(actor: any, objInstance: any, state: any): boolean
	if not (state and objInstance and objInstance.id) then return false end
	if not (actor and actor.side == "Player") then
		print("[BlackMarketService] Interaction by a non-player unit: no shop")
		return true
	end
	local playerId = state.ownerPlayerId
	if type(playerId) ~= "string" then
		warn("[BlackMarketService] Battle state has no owner player id")
		return false
	end
	-- The interaction passes the live battle state (covers any battle start path).
	_state = state
	local payload = payloadFor(state, objInstance.id, playerId)
	if not payload then return false end
	if _onOpened then _onOpened(payload) end
	print(`[BlackMarketService] {tostring(actor.name)} opens the Black Market ({objInstance.id})`)
	return true
end

-- Remote handler body: (player, objectId, slot) -> { ok, slot?, gold?, name?, error? }
function BlackMarketService.HandleBuy(plr: Player, objectId: any, slot: any): any
	if _player and plr ~= _player then return { ok = false, error = "Not your battle" } end
	if typeof(objectId) ~= "string" or #objectId > 64 or typeof(slot) ~= "number" then
		return { ok = false, error = "Bad request" }
	end
	if slot ~= math.floor(slot) or slot < 1 or slot > SLOT_COUNT then
		return { ok = false, error = "Bad request" }
	end
	local now = os.clock()
	local rk = `{plr.UserId}:buy`
	if lastCallAt[rk] and now - lastCallAt[rk] < RATE_LIMIT_SECONDS then
		return { ok = false, error = "Too fast, try again" }
	end
	lastCallAt[rk] = now

	local state = _state
	if not state then return { ok = false, error = "The battle is over" } end
	local playerId = state.ownerPlayerId
	if type(playerId) ~= "string" then return { ok = false, error = "No player" } end
	local slots = state.blackMarkets and state.blackMarkets[objectId]
	if not slots then return { ok = false, error = "This Black Market has not been opened" } end
	if not objectAlive(state, objectId) then
		return { ok = false, error = "The Black Market is gone" }
	end
	local entry = nil
	for _, s in slots do
		if s.slot == slot then entry = s end
	end
	if not entry then return { ok = false, error = "Nothing in that slot" } end
	if entry.bought then return { ok = false, error = "Already bought" } end
	if not (_currency and _currency.Debit and _inventory and _inventory.AddItem) then
		return { ok = false, error = "Shop not available" }
	end
	if goldOf(playerId) < entry.price then
		return { ok = false, error = "Not enough gold" }
	end
	-- No partial transaction: charge, then add; if the add fails, give the gold back.
	local paid, why = _currency.Debit(playerId, { gold = entry.price })
	if not paid then return { ok = false, error = why or "Not enough gold" } end
	local added, addErr = _inventory.AddItem(playerId, entry.item)
	if not added then
		if _currency.Credit then _currency.Credit(playerId, { gold = entry.price }) end
		warn(`[BlackMarketService] AddItem failed, gold returned: {tostring(addErr)}`)
		return { ok = false, error = "Could not add the item" }
	end
	entry.bought = true
	local name = entry.item.displayName or entry.item.name or entry.item.baseArchetypeId
	print(`[BlackMarketService] Bought slot {slot} ({tostring(name)}, {entry.item.rarityId} L{entry.item.itemLevel}) for {entry.price}g`)
	return { ok = true, slot = slot, gold = goldOf(playerId), name = name }
end

return BlackMarketService
