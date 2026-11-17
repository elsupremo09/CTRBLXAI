--!strict
-- ApothecaryService.lua
-- CTRBLXAI | Apothecary facility (USER DECISION 2026-11-03; DB guild_facilities 67-73).
--
-- Replaces the unbuilt Workshop. Jobs:
--   * a seeded consumable shelf (buy) + selling owned loose copies
--   * PAID refill of consumable charges on return to base (from the start of the game)
--   * L9: +25% max charges   * L10: +1 consumable slot for every unit
--
-- Owns the rules/maths only. Owned copies (cardInventory.consumables), the roster and the
-- facility level are INJECTED (ARC-004 / ARC-006, nil-safe). Gold goes through
-- CurrencyService. Requires no service that requires it (no cycle, AP-013).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Game = ServerScriptService:WaitForChild("Game")
local Content = ReplicatedStorage:WaitForChild("Content")

local CurrencyService = require(Game:WaitForChild("CurrencyService"))
local ConsumableData: any = require(Content:WaitForChild("ConsumableData"))

local ApothecaryService = {}

--------------------------------------------------
-- CONSTANTS (guild_facilities 68-71)
--------------------------------------------------

local SHELF_SIZE = table.freeze({ 4, 4, 5, 5, 6, 6, 7, 7, 7, 8 })
-- Tier odds per shelf slot, Common / Uncommon / Rare / Epic (%).
local TIER_ODDS = table.freeze({
	{ 100, 0, 0, 0 }, { 90, 10, 0, 0 }, { 85, 15, 0, 0 }, { 70, 15, 15, 0 }, { 60, 15, 25, 0 },
	{ 50, 15, 35, 0 }, { 45, 15, 40, 0 }, { 40, 12, 40, 8 }, { 35, 12, 43, 10 }, { 30, 12, 46, 12 },
})
local TIERS = table.freeze({ "Common", "Uncommon", "Rare", "Epic" })
-- Category unlock level.
local TYPE_UNLOCK = table.freeze({
	Recovery = 1, Damage = 1, Support = 2, Utility = 3, Control = 4, Environment = 5, Deployable = 6,
})
local RESTOCK_BATTLES = 5
local SELL_PCT = 20
local CHARGE_BONUS_LEVEL = 9 -- +25% max charges
local SLOT_BONUS_LEVEL = 10  -- +1 consumable slot
local MAX_BOUGHT_SAVE = 16

--------------------------------------------------
-- INJECTED
--------------------------------------------------

local _getLevel: (() -> number)? = nil
local _getOwned: (() -> { [string]: number })? = nil
local _getUnits: (() -> { [string]: any })? = nil
local _getBattles: (() -> number)? = nil
local _getNonce: (() -> number)? = nil

-- Persisted (Export/Import): auto-refill switch + bought slots of the current shelf.
local autoRefill = true
-- Last return-to-base refill (session only), for the base screen message (declared before use).
local lastReturn: any = nil
local bought: { key: string, slots: { [number]: boolean } } = { key = "", slots = {} }

function ApothecaryService.Init(deps: any)
	_getLevel = deps.getLevel
	_getOwned = deps.getOwned
	_getUnits = deps.getUnits
	_getBattles = deps.getBattles
	_getNonce = deps.getNonce
end

--------------------------------------------------
-- LEVEL MATHS
--------------------------------------------------

-- Effective Apothecary level: 0 = not open yet (Renown Rank rule applied by the provider).
function ApothecaryService.GetLevel(): number
	local l = _getLevel and _getLevel() or 0
	return math.clamp(math.floor(tonumber(l) or 0), 0, 10)
end

-- Full-refill rate % of list price: 75 before it is built and at L1, 25 at L10 (row 69).
function ApothecaryService.RefillRate(level: number?): number
	local l = level or ApothecaryService.GetLevel()
	if l <= 1 then return 75 end
	return 75 - math.round(50 * (l - 1) / 9)
end

function ApothecaryService.BuyDiscountPct(level: number?): number
	local l = level or ApothecaryService.GetLevel()
	return math.max(0, 3 * (l - 1))
end

function ApothecaryService.ListPrice(id: string): number
	local def = ConsumableData.GetById(id)
	return def and def.shopPrice or 0
end

function ApothecaryService.BuyPrice(id: string): number
	local list = ApothecaryService.ListPrice(id)
	return (list * (100 - ApothecaryService.BuyDiscountPct())) // 100
end

-- Sell value of one owned (full) loose copy: floor(list x 20%).
function ApothecaryService.SellPrice(id: string): number
	return (ApothecaryService.ListPrice(id) * SELL_PCT) // 100
end

-- Item max charges with the L9 bonus (floor x1.25). The Reinforced Cartridge adds on top
-- elsewhere (EquipmentService). Called by EquipmentService for every equipped slot.
function ApothecaryService.GetMaxCharges(def: any): number
	local base = (def and def.maxCharges) or 1
	if ApothecaryService.GetLevel() >= CHARGE_BONUS_LEVEL then
		return math.floor(base * 1.25)
	end
	return base
end

-- An equipped item counts as FULL when it has at least its own max (L9 bonus included).
-- Reinforced Cartridge extra charges are free battle charges, so they never make an item
-- "partly used" (fixes the Cartridge on/off edge cases, Tester WARN 2/3, 2026-11-03).
function ApothecaryService.IsFull(slot: any): boolean
	if type(slot) ~= "table" or not slot.consumableId then return true end
	local def = ConsumableData.GetById(slot.consumableId)
	if not def then return true end
	return (slot.currentCharges or 0) >= ApothecaryService.GetMaxCharges(def)
end

-- +1 consumable slot for every unit at L10 (row 70; the 3..6 clamp stays with the caller).
function ApothecaryService.SlotBonus(): number
	return if ApothecaryService.GetLevel() >= SLOT_BONUS_LEVEL then 1 else 0
end

-- Cost of the first k missing charges of an item whose paid max is m:
-- ceil(list x k x rate / (m x 100)), integer maths (row 69). Charge i costs
-- cumulative(i) - cumulative(i-1), so one-at-a-time adds up to exactly the full price.
local function cumulativeCost(list: number, k: number, m: number, rate: number): number
	if k <= 0 or m <= 0 then return 0 end
	local num = list * k * rate
	local den = m * 100
	return (num + den - 1) // den
end

--------------------------------------------------
-- REFILL (return to base)
--------------------------------------------------

-- Dungeon build step 3 (project_rules 266): units in an active dungeon run are never refilled at
-- return to base (only the dungeon Merchant refills them). Injected by Main; nil = none skipped.
local _skipUnit: ((string) -> boolean)? = nil
function ApothecaryService.SetSkipUnit(fn: ((string) -> boolean)?) _skipUnit = fn end

local function sortedUnitIds(units: { [string]: any }, only: { [string]: boolean }?): { string }
	local ids = {}
	for id in units do
		-- only = the dungeon Merchant's party refill (step 6): those units, and the skip rule does not apply.
		if only then
			if only[id] then table.insert(ids, id) end
		elseif not (_skipUnit and _skipUnit(id)) then table.insert(ids, id) end
	end
	table.sort(ids, function(a: string, b: string)
		-- Hero first, then id order (stable "roster order").
		if a == "unit_hero" then return b ~= "unit_hero" end
		if b == "unit_hero" then return false end
		return a < b
	end)
	return ids
end

-- Plan or perform the refill of every equipped item missing charges. Paid charges are the
-- ones below the Apothecary max; any Reinforced Cartridge extra above it refills free.
-- Gold short: one charge at a time, roster then slot order, stop at the first unaffordable
-- charge; gold never goes below 0. Returns { cost, refilled, skippedCharges, needGold }.
-- opts (Dungeon build step 6, 2026-11-14): { onlyUnits = { [id] = true }, priceMult = 1.5 } = the dungeon
-- Merchant refill for the run party at the Apothecary formula x1.5 (Q9). nil = the normal refill.
function ApothecaryService.Refill(playerId: string, commit: boolean, opts: any?): any
	local units = _getUnits and _getUnits() or {}
	local only = if type(opts) == "table" and type(opts.onlyUnits) == "table" then opts.onlyUnits else nil
	local mult = if type(opts) == "table" and type(opts.priceMult) == "number" and opts.priceMult > 0 then opts.priceMult else 1
	local rate = ApothecaryService.RefillRate()
	local gold = (CurrencyService.GetBalance(playerId) or {}).gold or 0
	local spent, refilled, skipped, needGold = 0, 0, 0, 0
	local stopped = false
	for _, uid in sortedUnitIds(units, only) do
		local unit = units[uid]
		for idx = 1, 6 do
			local slot = unit.consumableSlots and unit.consumableSlots[idx]
			if type(slot) == "table" and slot.consumableId then
				local def = ConsumableData.GetById(slot.consumableId)
				local cur = slot.currentCharges or 0
				local slotMax = slot.maxCharges or 1
				if def and cur < slotMax then
					local list = math.round((def.shopPrice or 0) * mult) -- x1.5 for the dungeon Merchant (Q9)
					local paidMax = math.min(ApothecaryService.GetMaxCharges(def), slotMax)
					local paidMissing = math.max(0, paidMax - cur)
					local done = 0
					for i = 1, paidMissing do
						local c = cumulativeCost(list, i, paidMax, rate) - cumulativeCost(list, i - 1, paidMax, rate)
						if stopped or spent + c > gold then
							stopped = true
							skipped += paidMissing - done
							needGold += cumulativeCost(list, paidMissing, paidMax, rate) - cumulativeCost(list, done, paidMax, rate)
							break
						end
						spent += c
						done = i
					end
					local newCur = cur + done
					if done == paidMissing then newCur = slotMax end -- free extra (Cartridge) charges
					if newCur > cur then
						refilled += newCur - cur
						if commit then slot.currentCharges = newCur end
					end
				end
			end
		end
	end
	if commit and spent > 0 then
		CurrencyService.Debit(playerId, { gold = spent })
	end
	return { cost = spent, refilled = refilled, skippedCharges = skipped, needGold = needGold, rate = rate }
end

-- Return-to-base hook (Main). Before the Apothecary exists the switch is not reachable, so
-- auto-refill is always on (Designer default 2026-11-03).
function ApothecaryService.OnReturnToBase(playerId: string): any?
	if ApothecaryService.GetLevel() >= 1 and not autoRefill then return nil end
	local res = ApothecaryService.Refill(playerId, true)
	lastReturn = res
	print(`[Apothecary] Refill on return: {res.refilled} charge(s) for {res.cost}g at {res.rate}%`
		.. (if res.skippedCharges > 0 then ` | {res.skippedCharges} not refilled - need {res.needGold}g` else ""))
	return res
end

-- Reported once, then cleared, so the note does not repeat on later menu opens.
function ApothecaryService.TakeLastReturn(): any
	local r = lastReturn
	lastReturn = nil
	return r
end

function ApothecaryService.GetAutoRefill(): boolean
	return autoRefill
end

function ApothecaryService.SetAutoRefill(on: boolean)
	autoRefill = on == true
end

--------------------------------------------------
-- SHELF (buy)
--------------------------------------------------

local function shelfKey(): string
	local b = _getBattles and _getBattles() or 0
	local n = _getNonce and _getNonce() or 0
	return `{b // RESTOCK_BATTLES}:{n}:{ApothecaryService.GetLevel()}`
end

local function shelfSeed(): number
	local b = _getBattles and _getBattles() or 0
	local n = _getNonce and _getNonce() or 0
	return 9001 + (b // RESTOCK_BATTLES) * 131 + n * 7919
end

-- Seeded shelf for the current level/restock window. Same save + battle count = same shelf.
function ApothecaryService.GetShelf(): { any }
	local level = ApothecaryService.GetLevel()
	if level < 1 then return {} end
	local pools: { [string]: { string } } = { Common = {}, Uncommon = {}, Rare = {}, Epic = {} }
	for _, id in ConsumableData.GetAllIds() do
		local def = ConsumableData.GetById(id)
		local unlock = def and TYPE_UNLOCK[def.category]
		if def and not def.parked and unlock and unlock <= level and pools[def.tier] then
			table.insert(pools[def.tier], id)
		end
	end
	local rng = Random.new(shelfSeed() + level * 17)
	local odds = TIER_ODDS[level]
	local used: { [string]: boolean } = {}
	local key = shelfKey()
	local boughtSlots = if bought.key == key then bought.slots else {}
	local shelf = {}
	for slot = 1, SHELF_SIZE[level] do
		local roll = rng:NextInteger(1, 100)
		local tierIdx, acc = 1, 0
		for t = 1, 4 do
			acc += odds[t]
			if roll <= acc then tierIdx = t; break end
		end
		local pick: string? = nil
		for t = tierIdx, 1, -1 do -- empty tier -> next tier down
			local free = {}
			for _, id in pools[TIERS[t]] do
				if not used[id] then table.insert(free, id) end
			end
			if #free > 0 then
				pick = free[rng:NextInteger(1, #free)]
				break
			end
		end
		if pick then
			used[pick] = true
			table.insert(shelf, { slot = slot, id = pick, price = ApothecaryService.BuyPrice(pick),
				listPrice = ApothecaryService.ListPrice(pick), bought = boughtSlots[slot] == true })
		end
	end
	return shelf
end

-- Buy shelf slots + sell owned copies in one commit. buySlots = { slot }, sell = { [id] = n }.
-- Re-prices everything server-side (SEC-001). All-or-nothing on gold.
function ApothecaryService.Commit(playerId: string, buySlots: { number }, sell: { [string]: number }): any
	local owned = _getOwned and _getOwned()
	if not owned then return { ok = false, error = "Inventory not ready" } end
	local shelf = ApothecaryService.GetShelf()
	local bySlot: { [number]: any } = {}
	for _, e in shelf do bySlot[e.slot] = e end
	local cost, gain = 0, 0
	local buys = {}
	local seen: { [number]: boolean } = {}
	for _, s in buySlots do
		local e = bySlot[s]
		if not e or e.bought or seen[s] then return { ok = false, error = "That shelf item is no longer available" } end
		seen[s] = true
		cost += e.price
		table.insert(buys, e)
	end
	for id, n in sell do
		if (owned[id] or 0) < n then return { ok = false, error = "You don't own that many" } end
		gain += ApothecaryService.SellPrice(id) * n
	end
	local gold = (CurrencyService.GetBalance(playerId) or {}).gold or 0
	if gold + gain < cost then return { ok = false, error = "Not enough gold" } end
	-- Commit.
	for id, n in sell do
		owned[id] = (owned[id] or 0) - n
		if owned[id] <= 0 then owned[id] = nil end
	end
	local key = shelfKey()
	if bought.key ~= key then bought = { key = key, slots = {} } end
	for _, e in buys do
		owned[e.id] = (owned[e.id] or 0) + 1
		bought.slots[e.slot] = true
	end
	if gain > 0 then CurrencyService.Credit(playerId, { gold = gain }) end
	if cost > 0 then CurrencyService.Debit(playerId, { gold = cost }) end
	print(`[Apothecary] Bought {#buys} for {cost}g, sold for {gain}g`)
	return { ok = true, bought = #buys, cost = cost, gain = gain }
end

--------------------------------------------------
-- SAVE (guildMenu.apothecary)
--------------------------------------------------

function ApothecaryService.Export(): any
	local slots = {}
	for s in bought.slots do table.insert(slots, s) end
	table.sort(slots)
	return { auto = autoRefill, key = bought.key, slots = slots }
end

function ApothecaryService.Import(data: any)
	autoRefill = true
	bought = { key = "", slots = {} }
	if type(data) ~= "table" then return end
	if data.auto == false then autoRefill = false end
	if type(data.key) == "string" and #data.key <= 32 and type(data.slots) == "table" then
		local slots: { [number]: boolean } = {}
		local n = 0
		for _, s in data.slots do
			if type(s) == "number" and s % 1 == 0 and s >= 1 and s <= 8 and n < MAX_BOUGHT_SAVE then
				slots[s] = true
				n += 1
			end
		end
		bought = { key = data.key, slots = slots }
	end
end

return ApothecaryService
