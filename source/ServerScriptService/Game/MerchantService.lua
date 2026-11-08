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
--   ExportPurchases(playerId) / ImportPurchases(playerId, data)  bought shelf slots (save)
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
--   economy_framework row 15 (Shop Price) — USER DECISION 2026-10-30:
--     Shop Price   = round(Base Value × Rarity Mult × Level Mult × Markup).
--     Markup ×4.0 for Common / Uncommon / Rare, ×6.0 for Epic / Exalted.
--     Sell Value   = floor(Base Value × Rarity Mult × Level Mult × 0.25).
--     (row 16: buy/sell ratio 16:1, or 24:1 for Epic / Exalted; no profitable loops.)
--   economy_framework (Item Value, Locked):
--     Level Multiplier = 1 + (Item Level − 1) × 0.02.  (L1 ×1.00, L50 ×1.98, L99 ×2.96)
--     Rarity Multiplier: Common 1.0, Uncommon 1.5, Rare 2.5, Epic 4.0,
--       Exalted 5.5, Legendary 7.0, Mythic 12.0, Transcendent 20.0, Unique 15.0.
--   economy_framework id=11 (Base Value by Slot, Locked):
--     1H=100, 2H=150, Off-Hand=60, Body=80, Head=60, Gloves=50, Feet=50, Accessory=70.
--   economy_framework rows 18 / 48 + guild_facilities row 15 (Shop Stock / Merchant)
--   — USER DECISION 2026-10-30:
--     Shelf slots by Merchant level L1..L10 = 5,5,6,7,7,8,9,10,10,10 (+1 on each
--     level that unlocks no new rarity). Each slot rolls its own rarity from the
--     level's odds (MERCHANT_RARITY_ODDS): Uncommon from L2, Rare from L5, Epic 15%
--     from L9, Exalted 5% at L10. Nothing above Exalted is ever stocked.
--     Stock items roll at the current Map Level; stock rerolls every 5 completed battles.
--   Max Merchant level 10.
--
-- ────────────────────────────────────────────────────────────────────────────
-- OPEN NOTE (kept for the Designer):
--   FLAG-M3  ITEM LEVEL of generated stock: "up to current Map Level" locks the
--            CEILING, not the exact level each stock item rolls at. We roll each
--            stock item at the Map Level (the ceiling) deterministically; a
--            Designer may want a spread below the ceiling.
--   (FLAG-M1 per-slot mix and FLAG-M2 Rare-in-shop tension were resolved by the
--   2026-10-30 user decision above.)

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
-- Higher shop markup for top rarities (USER DECISION 2026-10-30, per Simulator: keeps shop
-- Epics near loot pace in the L50-80 tight phase). In DB: economy_framework rows 15/16.
local SHOP_MARKUP_BY_RARITY = table.freeze({ Epic = 6.0, Exalted = 6.0 })
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
	Common       = 1.0,
	Uncommon     = 1.5,
	Rare         = 2.5,
	Epic         = 4.0,
	Exalted      = 5.5,
	Legendary    = 7.0,
	Mythic       = 12.0,
	Transcendent = 20.0,
	Unique       = 15.0,
})

-- Merchant level -> shelf slots and per-slot rarity odds (USER DECISION 2026-10-30).
-- Supersedes the locked "1 slot per level, Uncommon at L5, Rare at L8, never Epic" rules.
local MERCHANT_MAX_LEVEL = 10
-- 5 slots at L1; +1 on every level that unlocks no new rarity (L3, L4, L6, L7, L8).
local MERCHANT_SLOTS_BY_LEVEL = table.freeze({ 5, 5, 6, 7, 7, 8, 9, 10, 10, 10 })
-- Percent chance per slot (each row sums to 100). New rarity unlocks: Uncommon L2,
-- Rare L5, Epic L9, Exalted L10. Common/Uncommon stay possible at max level.
local MERCHANT_RARITY_ODDS = table.freeze({
	table.freeze({ Common = 100 }),
	table.freeze({ Common = 90, Uncommon = 10 }),
	table.freeze({ Common = 80, Uncommon = 20 }),
	table.freeze({ Common = 70, Uncommon = 30 }),
	table.freeze({ Common = 55, Uncommon = 40, Rare = 5 }),
	table.freeze({ Common = 45, Uncommon = 45, Rare = 10 }),
	table.freeze({ Common = 35, Uncommon = 45, Rare = 20 }),
	table.freeze({ Common = 25, Uncommon = 45, Rare = 30 }),
	table.freeze({ Common = 15, Uncommon = 35, Rare = 35, Epic = 15 }),
	table.freeze({ Common = 10, Uncommon = 30, Rare = 40, Epic = 15, Exalted = 5 }),
})
-- Roll order, lowest to highest. Also the only rarities a shop can ever stock.
local ODDS_ORDER = table.freeze({ "Common", "Uncommon", "Rare", "Epic", "Exalted" })

-- Rarity rank (same order as BonusData.RARITY_ORDER); used for the stock ceiling check.
local RARITY_RANK = table.freeze({
	Common = 1, Uncommon = 2, Rare = 3,
	Epic = 4, Exalted = 5, Legendary = 6, Mythic = 7, Transcendent = 8, Unique = 9,
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
-- STATE: bought shelf slots (2026-10-31, user decision). Stock is regenerated from a fixed
-- seed, so without this a restart / rejoin rebuilt the shelf with items already bought
-- (same items, same instance ids). Bought slots now stay empty until the stock changes.
-- One record per shelf of the CURRENT 5-battle window (2026-10-31, Tester D-1): the shelf
-- depends on the map level (base = L1, a quest = its level), so switching between them must
-- not wipe the other shelf's purchases. A new reroll window clears every record.
-- Saved by GuildMenuService (progression.guildMenu.merchantBought).
--   purchases[playerId] = { rerollKey = n, shelves = { ["r:l:m:s"] = { [slotNumber] = true } } }
--------------------------------------------------

-- lastBuy[key] = order of the latest buy on that shelf (higher = newer). The save keeps the
-- 12 most recently bought-from shelves, so the current shelf is never dropped (Tester D-2).
type Purchases = {
	rerollKey: number,
	shelves: { [string]: { [number]: boolean } },
	lastBuy: { [string]: number },
	buySeq: number,
}
local purchases: { [string]: Purchases } = {}
local MAX_SHELVES = 12        -- shelves kept per window (load / save bound; one per map level seen)

-- Largest shelf any Merchant level has (load validation bound for saved slot numbers).
local MAX_SHELF_SLOTS = 0
for _, n in MERCHANT_SLOTS_BY_LEVEL do
	MAX_SHELF_SLOTS = math.max(MAX_SHELF_SLOTS, n)
end
local MAX_STOCK_KEY_LEN = 64

local function stockKeyOf(rerollKey: number, lvlCeiling: number, mLevel: number, seed: number?): string
	return `{rerollKey}:{lvlCeiling}:{mLevel}:{seed or 0}`
end

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
			-- WeaponData marks two-handed weapons with handClass = "2H" (BUG-073, 2026-11-01).
			if wArch.handClass == "2H" then
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

local function oddsFor(mLevel: number): { [string]: number }
	return MERCHANT_RARITY_ODDS[math.clamp(math.floor(mLevel), 1, MERCHANT_MAX_LEVEL)]
end

-- Shelf slots for a Merchant level (USER DECISION 2026-10-30). 0 when not built.
local function slotsFor(mLevel: number): number
	if mLevel <= 0 then return 0 end
	return MERCHANT_SLOTS_BY_LEVEL[math.clamp(math.floor(mLevel), 1, MERCHANT_MAX_LEVEL)]
end

-- The highest rarity the current Merchant level can stock (any non-zero chance).
local function maxStockRarity(mLevel: number): string
	local odds = oddsFor(mLevel)
	local top = "Common"
	for _, r in ODDS_ORDER do
		if (odds[r] or 0) > 0 then top = r end
	end
	return top
end

-- Roll one slot's rarity from the level's odds. Deterministic: uses the stock rng.
local function rollRarity(rng: Random, mLevel: number): string
	local odds = oddsFor(mLevel)
	local roll = rng:NextInteger(1, 100)
	local acc = 0
	for _, r in ODDS_ORDER do
		acc += odds[r] or 0
		if roll <= acc then return r end
	end
	return "Common"
end

--------------------------------------------------
-- PRICING (LOCKED FORMULAS)
--------------------------------------------------

-- Shop Price = round(Base Value × Rarity Mult × Level Mult × Markup). Markup ×4.0, or
-- ×6.0 for Epic/Exalted (USER DECISION 2026-10-30). Sell value is unchanged.
function MerchantService.PriceToBuy(item: any): number?
	if type(item) ~= "table" then return nil end
	local baseValue = baseValueOf(item)
	if not baseValue then return nil end
	local rarityMult = RARITY_MULT[item.rarityId]
	if not rarityMult then return nil end
	local lvlMult = levelMultiplier(item.itemLevel)
	-- round() per the DB (NOT floor — buy uses round, sell uses floor).
	local markup = SHOP_MARKUP_BY_RARITY[item.rarityId] or SHOP_MARKUP
	return math.round(baseValue * rarityMult * lvlMult * markup)
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
-- Deterministic given (seed, mapLevel, merchantLevel, rerollKey). Slot count and
-- per-slot rarity odds come from the Merchant level (USER DECISION 2026-10-30:
-- MERCHANT_SLOTS_BY_LEVEL / MERCHANT_RARITY_ODDS). Each slot is filled by
-- generating an item through the EXISTING ItemGenerator at the Map Level ceiling
-- (FLAG-M3).
--
-- Returns: {
--   stock       = { { offerIndex, item, buyPrice }... },
--   slots       = number (MERCHANT_SLOTS_BY_LEVEL for the merchant level),
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
		return { stock = {}, slots = slotsFor(mLevel), maxRarity = maxStockRarity(mLevel),
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

	-- Bought slots of THIS shelf stay empty. Other shelves of the same window keep their
	-- records; a new reroll window starts with nothing bought.
	local stockKey = stockKeyOf(rerollKey, lvlCeiling, mLevel, seed)
	local rec = purchases[playerId]
	if not rec or rec.rerollKey ~= rerollKey then
		rec = { rerollKey = rerollKey, shelves = {}, lastBuy = {}, buySeq = 0 }
		purchases[playerId] = rec
	end
	local boughtSlots = rec.shelves[stockKey] or {}
	local skipped = 0

	local stock = {}
	for slot = 1, slotsFor(mLevel) do
		-- Each slot rolls its own rarity from the level's odds (USER DECISION 2026-10-30).
		local rarity = rollRarity(rng, mLevel)

		local archetypeId = pool[rng:NextInteger(1, #pool)]
		local slotSeed = baseSeed + slot * 7919
		-- Generate through the EXISTING generator; "Shop" context tag mirrors the
		-- "Loot" tag RewardService passes.
		local item, genErr = _itemGenerator.GenerateFromPool({ archetypeId }, lvlCeiling, rarity, slotSeed, "Shop")
		if item then
			-- Enforce the Shop Stock ceiling defensively: never stock above the
			-- permitted rarity even if the generator substituted upward.
			local gotRank = RARITY_RANK[item.rarityId] or 0
			if gotRank <= topRank then
				local buyPrice = MerchantService.PriceToBuy(item)
				-- Every slot is still generated (keeps the roll sequence identical); a bought
				-- slot is just not offered again.
				if boughtSlots[slot] then
					skipped += 1
				elseif buyPrice then
					table.insert(stock, {
						offerIndex = #stock + 1,
						slot = slot,
						stockKey = stockKey, -- server-only; not sent to the client
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
		"[MerchantService] Stock for %s | Merchant L%d | %d slot(s) | up to L%d %s | rerollKey %d | %d already bought",
		playerId, mLevel, #stock, lvlCeiling, topRarity, rerollKey, skipped))

	return { stock = stock, slots = slotsFor(mLevel), maxRarity = topRarity, rerollKey = rerollKey }
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
	local added, addErr = _inventory.AddItem(playerId, offer.item, { markNew = true })
	if not added then
		-- Refund so no partial transaction remains.
		if _currency.AddGold then
			_currency.AddGold(playerId, price)
		else
			warn("[MerchantService] AddItem failed and no AddGold to refund — FLAG for manual reconciliation")
		end
		return false, "Could not add item (refunded): " .. tostring(addErr)
	end

	-- Remember the shelf slot so a later rebuild (restart, rejoin, level switch) leaves it empty.
	local rec = purchases[playerId]
	if rec and type(offer.slot) == "number" and type(offer.stockKey) == "string" then
		local shelf = rec.shelves[offer.stockKey]
		if not shelf then
			shelf = {}
			rec.shelves[offer.stockKey] = shelf
		end
		shelf[offer.slot] = true
		rec.buySeq += 1
		rec.lastBuy[offer.stockKey] = rec.buySeq
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
-- Any rarity CAN be sold, including Legendary and above. The shop-stock rules
-- (economy_framework row 18: Epic from Merchant L9, Exalted from L10, nothing
-- above Exalted) govern what the shop STOCKS to buy, not what the player may
-- sell. Sell Value uses the ×0.25 floor formula regardless of rarity.
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
	-- An open (paid) Runeforge reroll must be chosen first (USER RULING 2026-11-07); same
	-- wording as RuneforgeService.PENDING_REROLL_REASON.
	if type(item.pendingReroll) == "table" then
		return false, "Reroll choice pending: pick a set or keep the current lines at the Runeforge first"
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
-- SAVE: bought shelf slots (rides GuildMenuService's progression payload; no second store)
--------------------------------------------------

-- nil when nothing is bought (keeps the save small). DataStore-safe: plain arrays only.
--   { rerollKey = n, shelves = { { key = "r:l:m:s", slots = { 1, 4 } }, ... } }
function MerchantService.ExportPurchases(playerId: string): any?
	local rec = purchases[playerId]
	if not rec then return nil end
	local keys: { string } = {}
	for key, slots in rec.shelves do
		if next(slots) ~= nil then table.insert(keys, key) end
	end
	if #keys == 0 then return nil end
	-- Newest first (ties by key so the order is stable); the cap below drops the oldest.
	table.sort(keys, function(a: string, b: string): boolean
		local ta = rec.lastBuy[a] or 0
		local tb = rec.lastBuy[b] or 0
		if ta ~= tb then return ta > tb end
		return a < b
	end)
	local shelves = {}
	for i, key in keys do
		if i > MAX_SHELVES then break end
		local slots: { number } = {}
		for s in rec.shelves[key] do table.insert(slots, s) end
		table.sort(slots)
		table.insert(shelves, { key = key, slots = slots })
	end
	return { rerollKey = rec.rerollKey, shelves = shelves }
end

local function readSlots(list: any): ({ [number]: boolean }, number)
	local slots: { [number]: boolean } = {}
	local count = 0
	if type(list) ~= "table" then return slots, 0 end
	for _, s in list do
		if type(s) == "number" and s % 1 == 0 and s >= 1 and s <= MAX_SHELF_SLOTS and not slots[s] then
			slots[s] = true
			count += 1
		end
	end
	return slots, count
end

local function validKey(key: any): boolean
	return type(key) == "string" and #key > 0 and #key <= MAX_STOCK_KEY_LEN
end

-- Load validation: wrong types, oversized keys, out-of-range slots and extra shelves are
-- ignored. Old saves (no data) start with nothing bought. Also reads the one-shelf format
-- written earlier on 2026-10-31 ({ stockKey, slots }).
function MerchantService.ImportPurchases(playerId: string, data: any)
	purchases[playerId] = nil
	if type(data) ~= "table" then return end
	local rec: Purchases
	local total = 0
	if type(data.shelves) == "table" and type(data.rerollKey) == "number" and data.rerollKey % 1 == 0 then
		rec = { rerollKey = data.rerollKey, shelves = {}, lastBuy = {}, buySeq = 0 }
		local keptKeys: { string } = {}
		for _, entry in data.shelves do
			if #keptKeys >= MAX_SHELVES then break end
			if type(entry) == "table" and validKey(entry.key) and rec.shelves[entry.key] == nil then
				local slots, count = readSlots(entry.slots)
				if count > 0 then
					rec.shelves[entry.key] = slots
					table.insert(keptKeys, entry.key)
					total += count
				end
			end
		end
		-- The save lists shelves newest first; rebuild the buy order from that.
		for i, key in keptKeys do
			rec.lastBuy[key] = #keptKeys - i + 1
		end
		rec.buySeq = #keptKeys
	elseif validKey(data.stockKey) then
		-- Earlier one-shelf format: the reroll key is the first part of the stock key.
		local r = tonumber(string.match(data.stockKey, "^(%d+):"))
		if not r then return end
		local slots, count = readSlots(data.slots)
		rec = { rerollKey = r, shelves = { [data.stockKey] = slots }, lastBuy = { [data.stockKey] = 1 }, buySeq = 1 }
		total = count
	else
		return
	end
	purchases[playerId] = rec
	local shelfCount = 0
	for _ in rec.shelves do shelfCount += 1 end
	print(`[MerchantService] Imported purchases for {playerId} | {total} bought slot(s) on {shelfCount} shelf(s) | window {rec.rerollKey}`)
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
