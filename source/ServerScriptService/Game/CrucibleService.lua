--!strict
-- CrucibleService.lua
-- CTRBLXAI | Crucible: merge gear into the next rarity (USER DECISION 2026-11-02, 11th facility).
--
-- RULES (design doc workshop_design_options_20261101.md, approved 2026-11-02 with one change):
--   * Inputs: 3-5 items of the SAME BASE ITEM (same archetype, e.g. 5 Great Bows) and the same
--     rarity, Common to Exalted. Count needed by Crucible level: 5 (L1-3), 4 (L4-7), 3 (L8-10).
--     Equipped items (incl. units out on dispatch) are refused; the caller enforces that.
--   * Result: the same base item at the next rarity, with a FRESH bonus-line roll under the normal
--     loot rules. The roll is fixed by the inputs (seed from their instance IDs) and the lines are
--     never shown before confirming, so a merge cannot be fished.
--   * Result level = floor(average of ALL inputs) + level boost (0,0,1,1,2,2,3,3,4,5 at L1-10),
--     capped at the map-level cap and 99. The boost never lowers the average.
--   * It is a NEW item: not rune-forged, starting rarity = the new rarity, levelling record starts
--     at its level (InventoryService.AddItem fills these). Levelling paid on the inputs is lost.
--   * Highest rarity that can come out by level: Uncommon L1, Rare L4, Epic L7, Exalted L9,
--     Legendary L10. Mythic and above never.
--   * Cost: crystals to Uncommon 2 / Rare 3 / Epic 6 / Exalted 8 / Legendary 12 (never discounted);
--     sulfur to Exalted 1 / Legendary 2; gold (guild_facilities 63, whole-number maths) =
--     floor(slot value x R x (49 + result level) x (100 - discount %) / 100000), R = the NEW
--     rarity's multiplier x 10 (Uncommon 15, Rare 25, Epic 40, Exalted 55, Legendary 70),
--     discount = 3% per Crucible level above L1. (= 0.5 x slot x mult x level mult, discounted.)
--   * One confirm prompt (client); destroys the inputs; cannot be undone; nothing refunded.
--
-- OWNS: merge planning and the merge transaction.
-- MUST NOT OWN: item generation (ItemGenerator), slot values (BlacksmithService.GetBaseValue), balances
--   (CurrencyService), inventory storage (InventoryService), facility levels (GuildMenuService).
-- Dependencies are injected by Main (ARC-006) and are nil-safe.

local CrucibleService = {}

--------------------------------------------------
-- CONSTANTS (locked by the 2026-11-02 user decision)
--------------------------------------------------

local MAX_LEVEL = 10
local MAX_ITEM_LEVEL = 99
local DISCOUNT_PER_LEVEL = 3 -- % per Crucible level above L1
local MAX_INPUTS = 5

local NEXT_RARITY = table.freeze({
	Common = "Uncommon", Uncommon = "Rare", Rare = "Epic", Epic = "Exalted", Exalted = "Legendary",
})
local RARITY_ORDER = table.freeze({
	Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Exalted = 5, Legendary = 6,
})
local INPUTS_NEEDED = table.freeze({ 5, 5, 5, 4, 4, 4, 4, 3, 3, 3 })
local LEVEL_BOOST = table.freeze({ 0, 0, 1, 1, 2, 2, 3, 3, 4, 5 })
local CRYSTALS_TO = table.freeze({ Uncommon = 2, Rare = 3, Epic = 6, Exalted = 8, Legendary = 12 })
local SULFUR_TO = table.freeze({ Exalted = 1, Legendary = 2 })
-- Rarity multiplier x 10 (economy_framework rarity multipliers) for the whole-number fee.
local RARITY_R10 = table.freeze({ Uncommon = 15, Rare = 25, Epic = 40, Exalted = 55, Legendary = 70 })

local function capacityRarity(level: number): string?
	if level >= 10 then return "Legendary" end
	if level >= 9 then return "Exalted" end
	if level >= 7 then return "Epic" end
	if level >= 4 then return "Rare" end
	if level >= 1 then return "Uncommon" end
	return nil
end

local function unlockLevelFor(rarity: string): number
	if rarity == "Legendary" then return 10 end
	if rarity == "Exalted" then return 9 end
	if rarity == "Epic" then return 7 end
	if rarity == "Rare" then return 4 end
	return 1
end

--------------------------------------------------
-- INJECTED DEPENDENCIES
--------------------------------------------------

local _currency: any = nil      -- CurrencyService: CanAfford / Debit / Credit
local _inventory: any = nil     -- InventoryService: GetItem / RemoveItem / AddItem
local _itemGen: any = nil       -- ItemGenerator.Generate
local _baseValue: any = nil     -- (item) -> slot base value (BlacksmithService.GetBaseValue)
local _level: any = nil         -- () -> effective Crucible level (0 = not unlocked)
local _levelCap: any = nil      -- () -> map-level cap for the result
local _isBlocked: any = nil     -- (item) -> reason string if the item may not be used, else nil

function CrucibleService.SetCurrencyService(svc: any) _currency = svc end
function CrucibleService.SetInventoryService(svc: any) _inventory = svc end
function CrucibleService.SetItemGenerator(g: any) _itemGen = g end
function CrucibleService.SetBaseValue(fn: any) _baseValue = fn end
function CrucibleService.SetLevelProvider(fn: any) _level = fn end
function CrucibleService.SetLevelCapProvider(fn: any) _levelCap = fn end
function CrucibleService.SetBlockedCheck(fn: any) _isBlocked = fn end

local function currentLevel(): number
	local lvl = if _level then tonumber(_level()) else nil
	return math.clamp(math.floor(lvl or 0), 0, MAX_LEVEL)
end

local function hashString(s: string): number
	local h = 0
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 2147483647
	end
	return h
end

--------------------------------------------------
-- PUBLIC: facility state
--------------------------------------------------

function CrucibleService.GetState(): any
	local lvl = currentLevel()
	return {
		level = lvl,
		needed = if lvl >= 1 then INPUTS_NEEDED[lvl] else nil,
		boost = if lvl >= 1 then LEVEL_BOOST[lvl] else 0,
		capacity = capacityRarity(lvl),
		discountPct = math.max(0, DISCOUNT_PER_LEVEL * (lvl - 1)),
	}
end

-- Why an item can never go into the Crucible (rarity or block), or nil if it can.
function CrucibleService.ItemBlockedReason(item: any): string?
	if type(item) ~= "table" or type(item.itemLevel) ~= "number" or type(item.baseArchetypeId) ~= "string" then
		return "Invalid item"
	end
	if not NEXT_RARITY[item.rarityId] then
		return `{tostring(item.rarityId)} items cannot be merged`
	end
	if _isBlocked then
		local why = _isBlocked(item)
		if why then return why end
	end
	return nil
end

--------------------------------------------------
-- PUBLIC: plan (pure; charges and changes nothing)
--
-- instanceIds = { id, ... } (exactly the number needed at this Crucible level).
-- Returns plan or nil + reason. plan = { archetypeId, fromRarity, toRarity, toLevel, gold,
--   crystals, sulfur, items = { item, ... }, seed, crucibleLevel }
--------------------------------------------------

function CrucibleService.PlanMerge(playerId: string, instanceIds: any)
	if not (_inventory and _itemGen and _baseValue) then
		return nil, "Crucible not wired"
	end
	local lvl = currentLevel()
	if lvl < 1 then
		return nil, "The Crucible is not built yet (needs Guild Hall L5)"
	end
	if type(instanceIds) ~= "table" or #instanceIds == 0 or #instanceIds > MAX_INPUTS then
		return nil, "Choose the items to merge"
	end
	local needed = INPUTS_NEEDED[lvl]
	if #instanceIds ~= needed then
		return nil, `Crucible L{lvl} merges exactly {needed} items`
	end

	local items = {}
	local seen: { [string]: boolean } = {}
	local archetypeId: string? = nil
	local rarity: string? = nil
	local levelSum = 0
	for _, id in instanceIds do
		if type(id) ~= "string" or #id > 80 then return nil, "Invalid item" end
		if seen[id] then return nil, "The same item was chosen twice" end
		seen[id] = true
		local item = _inventory.GetItem(playerId, id)
		if not item then return nil, "Item not owned" end
		local why = CrucibleService.ItemBlockedReason(item)
		if why then return nil, `{tostring(item.displayName or id)}: {why}` end
		if archetypeId == nil then
			archetypeId = item.baseArchetypeId
			rarity = item.rarityId
		elseif item.baseArchetypeId ~= archetypeId then
			return nil, "All items must be the same base item"
		elseif item.rarityId ~= rarity then
			return nil, "All items must be the same rarity"
		end
		levelSum += item.itemLevel
		table.insert(items, item)
	end

	local fromRarity = rarity :: string
	local toRarity = NEXT_RARITY[fromRarity] :: string
	local cap = capacityRarity(lvl) :: string
	if RARITY_ORDER[toRarity] > RARITY_ORDER[cap] then
		return nil, `Making {toRarity} items needs Crucible L{unlockLevelFor(toRarity)} (yours is L{lvl})`
	end

	local average = math.floor(levelSum / #items)
	local mapCap = math.floor(tonumber(_levelCap and _levelCap()) or MAX_ITEM_LEVEL)
	-- The boost never goes above the map-level cap; it never lowers the average either.
	local toLevel = math.min(MAX_ITEM_LEVEL, math.max(average, math.min(average + LEVEL_BOOST[lvl], mapCap)))

	local sorted = table.clone(instanceIds)
	table.sort(sorted)
	local seed = hashString(table.concat(sorted, "|") .. "|crucible")

	local slotValue = _baseValue(items[1])
	if type(slotValue) ~= "number" then
		return nil, "Could not price this item"
	end
	local discount = math.max(0, DISCOUNT_PER_LEVEL * (lvl - 1))
	-- Whole-number maths (guild_facilities 63; D-2 fix 2026-11-02): no decimal rounding drift.
	local gold = (math.floor(slotValue) * RARITY_R10[toRarity] * (49 + toLevel) * (100 - discount)) // 100000

	return {
		archetypeId = archetypeId,
		fromRarity = fromRarity,
		toRarity = toRarity,
		toLevel = toLevel,
		averageLevel = average,
		gold = gold,
		crystals = CRYSTALS_TO[toRarity] or 0,
		sulfur = SULFUR_TO[toRarity] or 0,
		items = items,
		seed = seed,
		crucibleLevel = lvl,
		discountPct = discount,
	}
end

--------------------------------------------------
-- PUBLIC: commit
-- Returns true, { item, plan } or false, reason. No partial transaction: if the new item cannot
-- be added, the inputs go back and the payment is refunded.
--------------------------------------------------

function CrucibleService.CommitMerge(playerId: string, instanceIds: any)
	local plan, why = CrucibleService.PlanMerge(playerId, instanceIds)
	if not plan then
		return false, why or "Cannot merge"
	end
	if not (_currency and _currency.Debit and _inventory.RemoveItem and _inventory.AddItem) then
		return false, "Crucible not wired"
	end
	-- Generate first: a generation failure costs nothing.
	local okGen, newItem, genErr = pcall(_itemGen.Generate, {
		baseArchetypeId = plan.archetypeId,
		itemLevel = plan.toLevel,
		rarity = plan.toRarity,
		seed = plan.seed,
		sourceType = "Crucible",
	})
	if not okGen or type(newItem) ~= "table" then
		return false, `Could not create the merged item: {tostring(if okGen then genErr else newItem)}`
	end

	local cost = { gold = plan.gold, crystals = plan.crystals, sulfur = plan.sulfur }
	local paid, payWhy = _currency.Debit(playerId, cost)
	if not paid then
		return false, `{tostring(payWhy or "Payment failed")} -- nothing charged`
	end

	local removed = {}
	for _, item in plan.items do
		local okRm = _inventory.RemoveItem(playerId, item.instanceId)
		if okRm == false then
			for _, back in removed do _inventory.AddItem(playerId, back) end
			if _currency.Credit then _currency.Credit(playerId, cost) end
			return false, "Could not take the input items -- nothing charged"
		end
		table.insert(removed, item)
	end

	local added = _inventory.AddItem(playerId, newItem, { markNew = true })
	if added == false then
		for _, back in removed do _inventory.AddItem(playerId, back) end
		if _currency.Credit then _currency.Credit(playerId, cost) end
		return false, "Could not add the merged item -- nothing charged"
	end

	print(string.format("[CrucibleService] MERGED %d x %s %s -> %s L%d (%s) | -%dg -%d crystals -%d sulfur | Crucible L%d",
		#plan.items, tostring(plan.archetypeId), plan.fromRarity, plan.toRarity, plan.toLevel,
		tostring(newItem.instanceId), plan.gold, plan.crystals, plan.sulfur, plan.crucibleLevel))
	return true, { item = newItem, plan = plan }
end

return table.freeze(CrucibleService)
