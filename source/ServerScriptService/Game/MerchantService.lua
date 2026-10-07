--!strict
-- MerchantService.lua
-- CTRBLXAI | Slice 6 — Base Management (Batch 2 of 3)
--
-- OWNS (per service_boundaries 'Merchant Service'):
--   Shop stock generation and the buy/sell transaction. It decides WHAT is in
--   stock and the PRICE, then moves gold through CurrencyService and items
--   through the existing InventoryService path.
--
-- READS:
--   economy_framework (shop price formula, buy/sell ratio, rarity/level mult,
--   base value by slot), guild_facilities (Merchant level -> stock slots and
--   which rarities appear), the current Map Level (passed in), the player's
--   completed-battle count (passed in, for the 5-battle reroll).
--
-- WRITES:
--   Buy  = CurrencyService.Debit(gold) + InventoryService.AddItem (item in).
--   Sell = InventoryService.RemoveItem (item out) + CurrencyService.Credit(gold).
--   It does NOT open a second currency, roster, or inventory store.
--
-- MUST NOT OWN:
--   The gold balance (CurrencyService owns it), item generation internals
--   (ItemGenerator owns them), the Merchant FACILITY purchase/level-up
--   (Slice 8 owns it — this service only READS the current Merchant level).
--
-- PRIMARY INTERFACE:
--   GetStock(playerId, mapLevel, battlesCompleted, seed?)  -> { stock=[...], ... }
--   PriceToBuy(item)                                       -> number
--   PriceToSell(item)                                      -> number
--   BuyItem(playerId, offerIndex, mapLevel, battlesCompleted) -> ok, result|reason
--   SellItem(playerId, instanceId)                         -> ok, result|reason
--
-- FAILURE BOUNDARY (LOCKED):
--   No partial transaction. A buy with insufficient gold charges NOTHING and
--   hands over NO item. A sell that cannot remove the item credits NO gold.
--   Gold moves are atomic via CurrencyService (all-or-nothing Debit/Credit).
--
-- ────────────────────────────────────────────────────────────────────────────
-- LOCKED DATA — copied verbatim from CTRBLXAI.db (economy_framework /
-- guild_facilities). Do NOT invent or tune here. The DB is the single source of
-- truth and is read-only to this agent; these constants mirror it because the
-- DB is not queryable at runtime.
-- ────────────────────────────────────────────────────────────────────────────
--
--   economy_framework (Shop, Locked):
--     Shop Price   = round(Base Value × Rarity Mult × Level Mult × 4.0).  Markup ×4.0.
--     Sell Value   = floor(Base Value × Rarity Mult × Level Mult × 0.25).  Ratio 16:1.
--     (Buy/Sell Ratio 16:1 == markup ×4.0 vs sell ×0.25; no profitable loops.)
--   economy_framework (Item Value, Locked):
--     Level Multiplier = 1 + (Item Level − 1) × 0.02.  (L1 ×1.00, L50 ×1.98, L99 ×2.96)
--     Rarity Multiplier: Broken 0.1, Common 1.0, Uncommon 1.5, Rare 2.5,
--       Epic 4.0, Legendary 7.0, Mythic 12.0, Transcendent 20.0, Unique 15.0.
--   economy_framework id=11 (Base Value by Slot, Locked):
--     1H=100, 2H=150, Off-Hand=60, Body=80, Head=60, Gloves=50, Feet=50, Accessory=70.
--   economy_framework (Shop Stock, Locked):
--     Shops sell Common and Uncommon items up to the current Map Level.
--     Rare+ items are NOT available in shops (loot / blacksmith only).
--     Stock rotation: available items reroll every 5 completed battles.
--   guild_facilities (Merchant, Locked):
--     Each level: +1 stock slot. L5: Uncommon in stock. L8: Rare in stock.
--     Max Level 10. (The L8-Rare line is the ONLY documented exception to the
--     "Rare+ never in shops" rule; it is applied verbatim and FLAGGED below as
--     an apparent tension for the Designer to confirm.)
--
-- ────────────────────────────────────────────────────────────────────────────
-- FLAGS — values whose STRUCTURE is locked but whose exact composition is NOT
-- defined in CTRBLXAI.db as of 2026-10-05. These are implemented as structure
-- and surfaced for a Designer ruling (NOT invented). See the task hand-back.
--   FLAG-M1  Per-slot STOCK COMPOSITION: the DB locks slot COUNT (= Merchant
--            level) and which RARITIES may appear (Common always; Uncommon at
--            L5; Rare at L8) and the level ceiling (up to Map Level), but NOT
--            which equipment ARCHETYPE fills each slot nor the rarity MIX across
--            slots. We fill slots by drawing from the same equip pool
--            RewardService uses, deterministically from the stock seed, choosing
--            the highest rarity the Merchant level permits — a neutral,
--            value-free rule. Designer should lock the intended per-slot mix.
--   FLAG-M2  RARE-IN-SHOP TENSION: guild_facilities Merchant L8 says "Rare items
--            in stock", while the Shop Stock rule says "Rare+ NEVER in shops
--            (loot/blacksmith only)". Both are Locked. We implement the facility
--            line (Rare appears only once Merchant L8 is reached) and FLAG the
--            contradiction rather than silently picking one.
--   FLAG-M3  ITEM LEVEL of generated stock: "up to current Map Level" locks the
--            CEILING, not the exact level each stock item rolls at. We roll each
--            stock item at the Map Level (the ceiling) deterministically; a
--            Designer may want a spread below the ceiling.

local ServerScriptService = game:GetService("ServerScriptService")
local Game = ServerScriptService:WaitForChild("Game")

-- These are DATA/generation modules the EXISTING RewardService already requires
-- the same way; requiring them here does not form a cycle (they are leaf data /
-- generators, not services that require MerchantService).
local Content = game:GetService("ReplicatedStorage"):WaitForChild("Content")
local WeaponData = require(Content:WaitForChild("WeaponData"))
local ArmorData  = require(Content:WaitForChild("ArmorData"))

local MerchantService = {}

--------------------------------------------------
-- LOCKED CONSTANTS (mirror of DB — see header)
--------------------------------------------------

local SHOP_MARKUP = 4.0            -- economy_framework Shop Price ×4.0
local SELL_RATE = 0.25            -- economy_framework Sell Value ×0.25 (16:1)
local LEVEL_MULT_STEP = 0.02       -- Level Multiplier = 1 + (Level−1) × 0.02

-- economy_framework id=11 — Base Value by Slot.
local BASE_VALUE_BY_SLOT = table.freeze({
	MainHand1H = 100,  -- 1H weapon
	MainHand2H = 150,  -- 2H weapon
	OffHand    = 60,
	Body       = 80,
	Head       = 60,
	Gloves     = 50,
	Feet       = 50,
	Accessory  = 70,
})

-- economy_framework — Rarity Multiplier (keyed by rarity NAME, as item.rarityId).
local RARITY_MULT = table.freeze({
	Broken       = 0.1,
	Common       = 1.0,
	Uncommon     = 1.5,
	Rare         = 2.5,
	Epic         = 4.0,
	Legendary    = 7.0,
	Mythic       = 12.0,
	Transcendent = 20.0,
	Unique       = 15.0,
})

-- guild_facilities Merchant (Locked): rarity-unlock by Merchant facility level.
local MERCHANT_UNCOMMON_LEVEL = 5  -- Uncommon items appear at Merchant L5
local MERCHANT_RARE_LEVEL = 8      -- Rare items appear at Merchant L8 (FLAG-M2)
local MERCHANT_MAX_LEVEL = 10

-- Shop Stock rule (Locked): shops sell Common and Uncommon up to Map Level;
-- Rare+ never (except the Merchant-L8 facility line, FLAG-M2). Rarity rank used
-- to pick the best rarity the Merchant level permits.
local RARITY_RANK = table.freeze({
	Broken = 0, Common = 1, Uncommon = 2, Rare = 3,
	Epic = 4, Legendary = 5, Mythic = 6, Transcendent = 7, Unique = 8,
})

local REROLL_BATTLE_INTERVAL = 5   -- economy_framework: reroll every 5 completed battles

--------------------------------------------------
-- INJECTED DEPENDENCIES (dependency injection — no circular require)
--------------------------------------------------

local _currency: any = nil           -- CurrencyService.AsProvider(): GetGold/SpendGold/AddGold
local _inventory: any = nil          -- InventoryService: AddItem / RemoveItem / GetItem
local _equipmentService: any = nil   -- DetermineSlot(item) (same single source Blacksmith uses)
local _itemGenerator: any = nil      -- ItemGenerator.GenerateFromPool(pool, level, rarity, seed, "Shop")
local _merchantLevelProvider: ((string) -> number)? = nil  -- current Merchant facility level

function MerchantService.SetCurrencyProvider(svc: any) _currency = svc end
function MerchantService.SetInventoryService(svc: any) _inventory = svc end
function MerchantService.SetEquipmentService(svc: any) _equipmentService = svc end
function MerchantService.SetItemGenerator(gen: any) _itemGenerator = gen end
function MerchantService.SetMerchantLevelProvider(fn: ((string) -> number)?) _merchantLevelProvider = fn end

--------------------------------------------------
-- STATE: last-generated stock per player (so Buy can resolve an offer index to
-- the exact item that was priced). This is NOT a save store — stock is
-- regenerated deterministically from (seed, mapLevel, merchantLevel) and only
-- cached in-memory for the current session's shop view.
--   shopState[playerId] = { stock = { offer... }, rerollKey = n }
--------------------------------------------------

local shopState: { [string]: { stock: { any }, rerollKey: number } } = {}

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function merchantLevel(playerId: string): number
	if _merchantLevelProvider then
		local lvl = _merchantLevelProvider(playerId)
		if type(lvl) == "number" then
			return math.clamp(math.floor(lvl), 0, MERCHANT_MAX_LEVEL)
		end
	end
	return 0  -- Merchant facility not built (Slice 8) -> no shop. Correct, not a fault.
end

-- Level Multiplier = 1 + (Item Level − 1) × 0.02  (economy_framework, Locked)
local function levelMultiplier(itemLevel: number): number
	local lvl = math.max(1, math.floor(itemLevel or 1))
	return 1 + (lvl - 1) * LEVEL_MULT_STEP
end

-- Resolve the base-value slot key for any item (weapons split 1H/2H/OffHand).
-- Same approach BlacksmithService uses so pricing is consistent across services.
local function resolveSlotKey(item: any): string?
	local slot
	if _equipmentService and _equipmentService.DetermineSlot then
		slot = _equipmentService.DetermineSlot(item)
	end
	if WeaponData and WeaponData.GetByArchetypeId then
		local wArch = WeaponData.GetByArchetypeId(item.baseArchetypeId)
		if wArch then
			if wArch.category == "OffHand" then
				return "OffHand"
			end
			local hands = wArch.hands or wArch.handedness
			if hands == "2H" or hands == 2 or wArch.isTwoHanded == true then
				return "MainHand2H"
			end
			return "MainHand1H"
		end
	end
	if slot and BASE_VALUE_BY_SLOT[slot] then
		return slot
	end
	return nil
end

local function baseValueOf(item: any): number?
	local key = resolveSlotKey(item)
	if not key then return nil end
	return BASE_VALUE_BY_SLOT[key]
end

-- The reroll key advances once every REROLL_BATTLE_INTERVAL completed battles.
local function rerollKeyFor(battlesCompleted: number): number
	local n = math.max(0, math.floor(battlesCompleted or 0))
	return math.floor(n / REROLL_BATTLE_INTERVAL)
end

-- The highest rarity the current Merchant level permits in stock.
-- Common always; Uncommon at L5; Rare at L8 (FLAG-M2). Never Rare+ beyond Rare.
local function maxStockRarity(mLevel: number): string
	if mLevel >= MERCHANT_RARE_LEVEL then
		return "Rare"
	elseif mLevel >= MERCHANT_UNCOMMON_LEVEL then
		return "Uncommon"
	else
		return "Common"
	end
end

--------------------------------------------------
-- PRICING (LOCKED FORMULAS)
--------------------------------------------------

-- Shop Price = round(Base Value × Rarity Mult × Level Mult × 4.0)   (Locked)
function MerchantService.PriceToBuy(item: any): number?
	if type(item) ~= "table" then return nil end
	local baseValue = baseValueOf(item)
	if not baseValue then return nil end
	local rarityMult = RARITY_MULT[item.rarityId]
	if not rarityMult then return nil end
	local lvlMult = levelMultiplier(item.itemLevel)
	-- round() per the DB (NOT floor — buy uses round, sell uses floor).
	return math.round(baseValue * rarityMult * lvlMult * SHOP_MARKUP)
end

-- Sell Value = floor(Base Value × Rarity Mult × Level Mult × 0.25)  (Locked)
function MerchantService.PriceToSell(item: any): number?
	if type(item) ~= "table" then return nil end
	local baseValue = baseValueOf(item)
	if not baseValue then return nil end
	local rarityMult = RARITY_MULT[item.rarityId]
	if not rarityMult then return nil end
	local lvlMult = levelMultiplier(item.itemLevel)
	-- floor() per the DB.
	return math.floor(baseValue * rarityMult * lvlMult * SELL_RATE)
end

--------------------------------------------------
-- STOCK GENERATION
--
-- Deterministic given (seed, mapLevel, merchantLevel, rerollKey). Slot count =
-- Merchant level (each level +1 slot, guild_facilities). Each slot is filled by
-- generating an item through the EXISTING ItemGenerator at the Map Level ceiling
-- (FLAG-M3), at the best rarity the Merchant level permits (FLAG-M1). Rare only
-- appears at Merchant L8 (FLAG-M2).
--
-- Returns: {
--   stock       = { { offerIndex, item, buyPrice }... },
--   slots       = number (= merchant level),
--   maxRarity   = string,
--   rerollKey   = number,
--   reason?     = string  (when the shop is empty / unavailable)
-- }
--------------------------------------------------

function MerchantService.GetStock(playerId: string, mapLevel: number, battlesCompleted: number, seed: number?)
	assert(type(playerId) == "string", "MerchantService.GetStock: playerId required")

	local mLevel = merchantLevel(playerId)
	if mLevel <= 0 then
		shopState[playerId] = { stock = {}, rerollKey = rerollKeyFor(battlesCompleted) }
		return { stock = {}, slots = 0, maxRarity = "Common",
			rerollKey = rerollKeyFor(battlesCompleted), reason = "Merchant facility not available" }
	end

	if not (_itemGenerator and _itemGenerator.GenerateFromPool) then
		return { stock = {}, slots = mLevel, maxRarity = maxStockRarity(mLevel),
			rerollKey = rerollKeyFor(battlesCompleted), reason = "ItemGenerator not wired" }
	end

	local lvlCeiling = math.max(1, math.floor(mapLevel or 1))
	local rerollKey = rerollKeyFor(battlesCompleted)
	local topRarity = maxStockRarity(mLevel)
	local topRank = RARITY_RANK[topRarity] or 1

	-- Build the equip pool the same way RewardService does (weapons + armor).
	local pool: { string } = {}
	for id, def in WeaponData.Archetypes do
		if def.category == "Weapon" or def.category == "OffHand" then
			table.insert(pool, id)
		end
	end
	for id, def in ArmorData.Archetypes do
		if def.category == "Armor" then
			table.insert(pool, id)
		end
	end
	table.sort(pool)

	-- Deterministic RNG: stock only changes when the rerollKey (every 5 battles),
	-- the map level, or the merchant level changes.
	local baseSeed = (seed or 0) + rerollKey * 1000003 + lvlCeiling * 101 + mLevel * 17
	local rng = Random.new(baseSeed)

	local stock = {}
	for slot = 1, mLevel do
		-- FLAG-M1: pick the best rarity the merchant permits for this slot. We
		-- use the top permitted rarity for every slot (value-free); a Designer
		-- may lock a mix. Common is always valid; Uncommon/Rare gated by level.
		local rarity = topRarity
		if RARITY_RANK[rarity] and RARITY_RANK[rarity] > topRank then
			rarity = "Common"
		end

		local archetypeId = pool[rng:NextInteger(1, #pool)]
		local slotSeed = baseSeed + slot * 7919
		-- Generate through the EXISTING generator; "Shop" context tag mirrors the
		-- "Loot" tag RewardService passes.
		local item, genErr = _itemGenerator.GenerateFromPool({ archetypeId }, lvlCeiling, rarity, slotSeed, "Shop")
		if item then
			-- Enforce the Shop Stock ceiling defensively: never stock above the
			-- permitted rarity even if the generator substituted upward.
			local gotRank = RARITY_RANK[item.rarityId] or 0
			if gotRank <= topRank and gotRank <= (RARITY_RANK.Rare) then
				local buyPrice = MerchantService.PriceToBuy(item)
				if buyPrice then
					table.insert(stock, {
						offerIndex = #stock + 1,
						item = item,
						buyPrice = buyPrice,
						rarity = item.rarityId,
						itemLevel = item.itemLevel,
					})
				end
			end
		else
			warn(string.format("[MerchantService] Stock slot %d gen failed: %s", slot, tostring(genErr)))
		end
	end

	shopState[playerId] = { stock = stock, rerollKey = rerollKey }

	print(string.format(
		"[MerchantService] Stock for %s | Merchant L%d | %d slot(s) | up to L%d %s | rerollKey %d",
		playerId, mLevel, #stock, lvlCeiling, topRarity, rerollKey))

	return { stock = stock, slots = mLevel, maxRarity = topRarity, rerollKey = rerollKey }
end

--------------------------------------------------
-- PRIMARY INTERFACE: BuyItem
--
-- Atomic (LOCKED failure boundary): charge gold FIRST via CurrencyService.Debit;
-- only if the debit succeeds is the item handed into inventory. If gold is
-- insufficient the Debit is all-or-nothing and nothing is charged; no item is
-- given. If the item hand-in fails after a successful debit, the gold is
-- refunded (Credit) so the transaction leaves no partial state.
--
-- offerIndex refers to the last GetStock() result for this player. We re-price
-- the exact offered item at buy time (so a stale client price cannot overpay or
-- underpay).
--
-- Returns: ok(boolean), result(table)|reason(string)
--------------------------------------------------

function MerchantService.BuyItem(playerId: string, offerIndex: number, mapLevel: number, battlesCompleted: number)
	assert(type(playerId) == "string", "MerchantService.BuyItem: playerId required")

	local state = shopState[playerId]
	if not state then
		-- Regenerate the stock view if the client is buying before an explicit
		-- GetStock (e.g. after a server restart). Deterministic, same result.
		MerchantService.GetStock(playerId, mapLevel, battlesCompleted)
		state = shopState[playerId]
	end
	if not state or type(offerIndex) ~= "number" then
		return false, "No shop stock to buy from"
	end

	local offer = state.stock[math.floor(offerIndex)]
	if not offer or not offer.item then
		return false, "Invalid shop offer"
	end

	local price = MerchantService.PriceToBuy(offer.item)
	if not price then
		return false, "Could not price item"
	end

	if not (_currency and _currency.SpendGold) then
		return false, "Currency not wired"
	end
	if not (_inventory and _inventory.AddItem) then
		return false, "Inventory path not wired"
	end

	-- 1) Charge gold atomically (CurrencyService.Debit under the hood).
	local charged = _currency.SpendGold(playerId, price)
	if not charged then
		print(string.format("[MerchantService] BUY rejected for %s | insufficient gold (%dg) | nothing charged", playerId, price))
		return false, "Insufficient gold"
	end

	-- 2) Hand the item into the EXISTING inventory path.
	local added, addErr = _inventory.AddItem(playerId, offer.item)
	if not added then
		-- Refund so no partial transaction remains.
		if _currency.AddGold then
			_currency.AddGold(playerId, price)
		else
			warn("[MerchantService] AddItem failed and no AddGold to refund — FLAG for manual reconciliation")
		end
		return false, "Could not add item (refunded): " .. tostring(addErr)
	end

	-- Remove the purchased offer so it cannot be bought twice from the same view.
	table.remove(state.stock, math.floor(offerIndex))
	-- Re-index remaining offers.
	for i, o in state.stock do o.offerIndex = i end

	print(string.format("[MerchantService] BOUGHT %s (%s L%d) for %s | %dg",
		tostring(offer.item.instanceId), tostring(offer.item.rarityId), offer.item.itemLevel or 0, playerId, price))

	return true, { instanceId = offer.item.instanceId, price = price, item = offer.item }
end

--------------------------------------------------
-- PRIMARY INTERFACE: SellItem
--
-- Atomic (LOCKED failure boundary): remove the item from inventory FIRST; only
-- if removal succeeds is gold credited. If the item is not owned or removal
-- fails, no gold is credited. (Removing first prevents duping: you cannot be
-- paid for an item you still hold.)
--
-- Rare+ CAN be sold (the "Rare+ never in shops" rule governs what the shop
-- STOCKS to buy, not what the player may sell). Sell Value uses the locked
-- ×0.25 floor formula regardless of rarity.
--
-- Returns: ok(boolean), result(table)|reason(string)
--------------------------------------------------

function MerchantService.SellItem(playerId: string, instanceId: string)
	assert(type(playerId) == "string", "MerchantService.SellItem: playerId required")

	if not (_inventory and _inventory.GetItem and _inventory.RemoveItem) then
		return false, "Inventory path not wired"
	end
	if not (_currency and _currency.AddGold) then
		return false, "Currency not wired"
	end

	local item = _inventory.GetItem(playerId, instanceId)
	if not item then
		return false, "Item not owned"
	end

	-- Do not sell an equipped item out from under a unit; InventoryService owns
	-- the equipped flag. If the item is equipped, refuse (no partial state).
	if item.equipped == true or item.isEquipped == true then
		return false, "Item is equipped — unequip before selling"
	end

	local payout = MerchantService.PriceToSell(item)
	if not payout then
		return false, "Could not price item for sale"
	end

	-- 1) Remove from inventory first.
	local removed, remErr = _inventory.RemoveItem(playerId, instanceId)
	if not removed then
		return false, "Could not remove item: " .. tostring(remErr)
	end

	-- 2) Credit gold (CurrencyService.Credit under the hood — always safe).
	local newGold = _currency.AddGold(playerId, payout)

	print(string.format("[MerchantService] SOLD %s (%s L%d) for %s | +%dg (gold now %s)",
		tostring(instanceId), tostring(item.rarityId), item.itemLevel or 0, playerId, payout, tostring(newGold)))

	return true, { instanceId = instanceId, payout = payout, goldAfter = newGold }
end

--------------------------------------------------
-- DEBUG
--------------------------------------------------

function MerchantService.Describe(playerId: string): string
	local state = shopState[playerId]
	if not state then return "no stock cached" end
	return string.format("%d offer(s) cached, rerollKey %d", #state.stock, state.rerollKey)
end

return MerchantService
