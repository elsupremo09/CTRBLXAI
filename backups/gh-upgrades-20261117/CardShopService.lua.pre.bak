--!strict
-- CardShopService.lua
-- CTRBLXAI | Training Grounds card shop (USER DECISION 2026-11-04; Designer proposal C2-C5).
-- Buys and sells skill cards, augment cards and doctrines.
--
--   Shelf 4,4,5,5,6,6,7,7,8,8 by level; restock every 5 completed battles (seeded, own seed).
--   Rarity odds per slot (Rare/Epic/Legendary) by level; Epic L4, Legendary L8; drop a rarity
--   when none are unlocked. Types: Attack+Support skills L1, basic augments L2, Control &
--   Utility skills L3, advanced augments L4, from L6 one slot is always a doctrine.
--   Price = floor(value x rarity x level mult x (100 - 3(L-1)) / 100); value augment 60,
--   skill 100, doctrine 1,000 flat (no rarity). Level mult = 1 + (map level - 1) x 0.02.
--   Sell = floor(list / 16), loose copies only (equipped / bound cards are not loose).
--
-- Rules/maths only. Card inventory, doctrine inventory, levels and battle count are INJECTED
-- (ARC-004 / ARC-006, nil-safe). Gold goes through CurrencyService. The server prices
-- everything (SEC-001).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Game = ServerScriptService:WaitForChild("Game")
local Content = ReplicatedStorage:WaitForChild("Content")

local CurrencyService = require(Game:WaitForChild("CurrencyService"))
local DoctrineInventoryService = require(Game:WaitForChild("DoctrineInventoryService"))
local SkillData: any = require(Content:WaitForChild("SkillData"))
local AugmentData: any = require(Content:WaitForChild("AugmentData"))
local DoctrineData: any = require(Content:WaitForChild("DoctrineData"))

local CardShopService = {}

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

local SHELF_SIZE = table.freeze({ 4, 4, 5, 5, 6, 6, 7, 7, 8, 8 })
local ODDS = table.freeze({ -- Rare / Epic / Legendary %
	{ 100, 0, 0 }, { 100, 0, 0 }, { 100, 0, 0 }, { 85, 15, 0 }, { 75, 25, 0 },
	{ 70, 30, 0 }, { 60, 40, 0 }, { 55, 35, 10 }, { 50, 35, 15 }, { 45, 35, 20 },
})
local RARITIES = table.freeze({ "Rare", "Epic", "Legendary" })
local RARITY_MULT = table.freeze({ Rare = 2.5, Epic = 4.0, Legendary = 7.0 })
local VALUE = table.freeze({ Augment = 60, Skill = 100, Doctrine = 1000 })
local TYPE_UNLOCK = table.freeze({ Attack = 1, Support = 1, BasicAug = 2, ControlUtility = 3, AdvancedAug = 4 })
local DOCTRINE_LEVEL = 6
local RESTOCK_BATTLES = 5
local SELL_DIVISOR = 16

-- Fixed shop rarity (Designer proposal C3 / Appendix 1). Not listed = Rare.
local SKILL_LEGENDARY = table.freeze({
	["Phoenix Rite"] = true, ["Conjure Mender"] = true, ["Conjure Sentinel"] = true, ["Conjure Wisp"] = true,
	["Summon Decoy"] = true, ["Summon Turret"] = true, ["Summon Ward Totem"] = true,
})
local SKILL_EPIC = table.freeze({
	["Chain Spark"] = true, ["Decimating Swing"] = true, ["Dragon Dive"] = true, ["Fissure Line"] = true,
	["Gale Thrust"] = true, ["Glacial Wave"] = true, ["Ignite Ground"] = true, ["Meteor Marker"] = true,
	["Pyroclasm"] = true, ["Retribution Shell"] = true, ["Shadow Rake"] = true, ["Siphon Pulse"] = true,
	["Sweeping Cut"] = true, ["Thunderclap"] = true, ["Tidal Crash"] = true, ["Venom Burst"] = true,
	["Voltaic Chain"] = true, ["Bulwark Field"] = true, ["Consecrate"] = true, ["Counter Stance"] = true,
	["Empowering Aura"] = true, ["Mending Rain"] = true, ["Misdirection"] = true, ["Riposte Stance"] = true,
	["Sanctify"] = true, ["War Cry"] = true, ["Blinding Flash"] = true, ["Flash Freeze"] = true,
	["Miasma Cloud"] = true, ["Rainfall Zone"] = true, ["Static Field"] = true,
})
local AUG_EPIC_FAMILY = table.freeze({
	["Conditional Amplifier"] = true, ["Timing"] = true, ["Terrain Effect"] = true,
	["Summoning"] = true, ["Kill Trigger"] = true, ["Death Explosion"] = true,
})
local AUG_LEGENDARY_FAMILY = table.freeze({
	["Element Conversion"] = true, ["Pattern"] = true, ["Resource Conversion"] = true, ["Reward"] = true,
})

--------------------------------------------------
-- INJECTED
--------------------------------------------------

local _getLevel: (() -> number)? = nil
local _getCards: (() -> any)? = nil       -- cardInventory { skillCards, augmentCards }
local _getMapLevel: (() -> number)? = nil
local _getBattles: (() -> number)? = nil
local _getNonce: (() -> number)? = nil

local bought: { key: string, slots: { [number]: boolean } } = { key = "", slots = {} }

function CardShopService.Init(deps: any)
	_getLevel = deps.getLevel
	_getCards = deps.getCards
	_getMapLevel = deps.getMapLevel
	_getBattles = deps.getBattles
	_getNonce = deps.getNonce
end

function CardShopService.GetLevel(): number
	local l = _getLevel and _getLevel() or 0
	return math.clamp(math.floor(tonumber(l) or 0), 0, 10)
end

--------------------------------------------------
-- CARD CLASSIFICATION
--------------------------------------------------

local function hasTag(tags: any, t: string): boolean
	for _, x in tags or {} do
		if x == t then return true end
	end
	return false
end

-- kind: "Skill" | "Augment" | "Doctrine"; returns rarity, type key
function CardShopService.Classify(kind: string, id: string): (string?, string?)
	if kind == "Skill" then
		local def = SkillData[id]
		if type(def) ~= "table" or string.sub(id, 1, 4) ~= "SKL-" then return nil, nil end
		local rarity = if SKILL_LEGENDARY[def.name] then "Legendary" elseif SKILL_EPIC[def.name] then "Epic" else "Rare"
		local tags = def.tags
		local t = "ControlUtility"
		if hasTag(tags, "Direct Damage") then
			t = "Attack"
		elseif hasTag(tags, "Healing") or hasTag(tags, "Buff") or hasTag(tags, "Shield") then
			t = "Support"
		end
		return rarity, t
	elseif kind == "Augment" then
		local def = AugmentData[id]
		if type(def) ~= "table" then return nil, nil end
		if AUG_LEGENDARY_FAMILY[def.family] then return "Legendary", "AdvancedAug" end
		if AUG_EPIC_FAMILY[def.family] then return "Epic", "AdvancedAug" end
		return "Rare", "BasicAug"
	elseif kind == "Doctrine" then
		if type(DoctrineData[id]) ~= "table" then return nil, nil end
		return "Doctrine", "Doctrine"
	end
	return nil, nil
end

local function mapLevel(): number
	local l = _getMapLevel and _getMapLevel() or 1
	return math.clamp(math.floor(tonumber(l) or 1), 1, 99)
end

-- List price (no discount): value x rarity x level multiplier.
function CardShopService.ListPrice(kind: string, id: string): number
	local rarity = CardShopService.Classify(kind, id)
	if not rarity then return 0 end
	local lvlMult = 1 + (mapLevel() - 1) * 0.02
	local mult = if kind == "Doctrine" then 1 else (RARITY_MULT[rarity] or 2.5)
	return math.floor(VALUE[kind] * mult * lvlMult + 1e-9)
end

function CardShopService.BuyPrice(kind: string, id: string): number
	local disc = math.max(0, 3 * (CardShopService.GetLevel() - 1))
	local lvlMult = 1 + (mapLevel() - 1) * 0.02
	local rarity = CardShopService.Classify(kind, id)
	if not rarity then return 0 end
	local mult = if kind == "Doctrine" then 1 else (RARITY_MULT[rarity] or 2.5)
	return math.floor(VALUE[kind] * mult * lvlMult * (100 - disc) / 100 + 1e-9)
end

function CardShopService.SellPrice(kind: string, id: string): number
	return CardShopService.ListPrice(kind, id) // SELL_DIVISOR
end

--------------------------------------------------
-- SHELF
--------------------------------------------------

local function shelfKey(): string
	local b = _getBattles and _getBattles() or 0
	local n = _getNonce and _getNonce() or 0
	return `{b // RESTOCK_BATTLES}:{n}:{CardShopService.GetLevel()}`
end

local function sortedKeys(t: any): { string }
	local out = {}
	for k in t do table.insert(out, k) end
	table.sort(out)
	return out
end

function CardShopService.GetShelf(): { any }
	local level = CardShopService.GetLevel()
	if level < 1 then return {} end
	-- Pools by rarity of every unlocked card (skills + augments).
	local pools: { [string]: { any } } = { Rare = {}, Epic = {}, Legendary = {} }
	for _, id in sortedKeys(SkillData) do
		local r, t = CardShopService.Classify("Skill", id)
		if r and t and (TYPE_UNLOCK[t] or 99) <= level then table.insert(pools[r], { kind = "Skill", id = id }) end
	end
	for _, id in sortedKeys(AugmentData) do
		local r, t = CardShopService.Classify("Augment", id)
		if r and t and (TYPE_UNLOCK[t] or 99) <= level then table.insert(pools[r], { kind = "Augment", id = id }) end
	end
	local b = _getBattles and _getBattles() or 0
	local n = _getNonce and _getNonce() or 0
	local rng = Random.new(12001 + (b // RESTOCK_BATTLES) * 173 + n * 7919 + level * 29)
	local key = shelfKey()
	local boughtSlots = if bought.key == key then bought.slots else {}
	local used: { [string]: boolean } = {}
	local shelf = {}
	local size = SHELF_SIZE[level]
	for slot = 1, size do
		local pick: any = nil
		if slot == size and level >= DOCTRINE_LEVEL then
			local docs = {}
			for _, id in sortedKeys(DoctrineData) do
				if type(DoctrineData[id]) == "table" then table.insert(docs, id) end
			end
			if #docs > 0 then pick = { kind = "Doctrine", id = docs[rng:NextInteger(1, #docs)] } end
		else
			local roll = rng:NextInteger(1, 100)
			local ri, acc = 1, 0
			for i = 1, 3 do
				acc += ODDS[level][i]
				if roll <= acc then ri = i; break end
			end
			for r = ri, 1, -1 do
				local free = {}
				for _, c in pools[RARITIES[r]] do
					if not used[c.kind .. c.id] then table.insert(free, c) end
				end
				if #free > 0 then
					pick = free[rng:NextInteger(1, #free)]
					break
				end
			end
		end
		if pick then
			used[pick.kind .. pick.id] = true
			local rarity = CardShopService.Classify(pick.kind, pick.id)
			table.insert(shelf, {
				slot = slot, kind = pick.kind, id = pick.id, rarity = rarity,
				price = CardShopService.BuyPrice(pick.kind, pick.id),
				listPrice = CardShopService.ListPrice(pick.kind, pick.id),
				bought = boughtSlots[slot] == true,
			})
		end
	end
	return shelf
end

-- Loose (sellable) copies the player owns: { kind, id, count, sellPrice, rarity }.
function CardShopService.GetOwned(playerId: string): { any }
	local out = {}
	local cards = _getCards and _getCards()
	if cards then
		for _, id in sortedKeys(cards.skillCards or {}) do
			local n = cards.skillCards[id]
			if n and n > 0 and CardShopService.Classify("Skill", id) then
				table.insert(out, { kind = "Skill", id = id, count = n, sellPrice = CardShopService.SellPrice("Skill", id),
					rarity = (CardShopService.Classify("Skill", id)) })
			end
		end
		for _, id in sortedKeys(cards.augmentCards or {}) do
			local n = cards.augmentCards[id]
			if n and n > 0 and CardShopService.Classify("Augment", id) then
				table.insert(out, { kind = "Augment", id = id, count = n, sellPrice = CardShopService.SellPrice("Augment", id),
					rarity = (CardShopService.Classify("Augment", id)) })
			end
		end
	end
	local stacks = DoctrineInventoryService.GetLooseStacks(playerId)
	for _, id in sortedKeys(stacks) do
		table.insert(out, { kind = "Doctrine", id = id, count = stacks[id].count,
			sellPrice = CardShopService.SellPrice("Doctrine", id), rarity = "Doctrine" })
	end
	return out
end

--------------------------------------------------
-- COMMIT (one item per confirm: buy a shelf slot, or sell one loose copy)
--------------------------------------------------

function CardShopService.Buy(playerId: string, slot: number): any
	local cards = _getCards and _getCards()
	if not cards then return { ok = false, error = "Cards not ready" } end
	local entry: any = nil
	for _, e in CardShopService.GetShelf() do
		if e.slot == slot then entry = e end
	end
	if not entry or entry.bought then return { ok = false, error = "That card is no longer available" } end
	local gold = (CurrencyService.GetBalance(playerId) or {}).gold or 0
	if gold < entry.price then return { ok = false, error = "Not enough gold" } end
	CurrencyService.Debit(playerId, { gold = entry.price })
	if entry.kind == "Skill" then
		cards.skillCards[entry.id] = (cards.skillCards[entry.id] or 0) + 1
	elseif entry.kind == "Augment" then
		cards.augmentCards[entry.id] = (cards.augmentCards[entry.id] or 0) + 1
	else
		DoctrineInventoryService.Mint(playerId, entry.id)
	end
	local key = shelfKey()
	if bought.key ~= key then bought = { key = key, slots = {} } end
	bought.slots[slot] = true
	print(`[CardShop] Bought {entry.kind} {entry.id} for {entry.price}g`)
	return { ok = true, kind = entry.kind, id = entry.id, cost = entry.price }
end

function CardShopService.Sell(playerId: string, kind: string, id: string): any
	local cards = _getCards and _getCards()
	if not cards then return { ok = false, error = "Cards not ready" } end
	if not CardShopService.Classify(kind, id) then return { ok = false, error = "Unknown card" } end
	if kind == "Skill" or kind == "Augment" then
		local t = if kind == "Skill" then cards.skillCards else cards.augmentCards
		if (t[id] or 0) < 1 then return { ok = false, error = "You don't own a loose copy" } end
		t[id] -= 1
		if t[id] <= 0 then t[id] = nil end
	else
		local stack = DoctrineInventoryService.GetLooseStacks(playerId)[id]
		if not stack then return { ok = false, error = "You don't own a loose copy" } end
		local ok = DoctrineInventoryService.RemoveInstance(playerId, stack.instanceId)
		if not ok then return { ok = false, error = "Could not sell" } end
	end
	local gain = CardShopService.SellPrice(kind, id)
	if gain > 0 then CurrencyService.Credit(playerId, { gold = gain }) end
	print(`[CardShop] Sold {kind} {id} for {gain}g`)
	return { ok = true, kind = kind, id = id, gain = gain }
end

--------------------------------------------------
-- SAVE (guildMenu.cardShop)
--------------------------------------------------

function CardShopService.Export(): any
	local slots = {}
	for s in bought.slots do table.insert(slots, s) end
	table.sort(slots)
	return { key = bought.key, slots = slots }
end

function CardShopService.Import(data: any)
	bought = { key = "", slots = {} }
	if type(data) ~= "table" or type(data.key) ~= "string" or #data.key > 40 or type(data.slots) ~= "table" then return end
	local slots: { [number]: boolean } = {}
	for i, s in data.slots do
		if i > 8 then break end
		if type(s) == "number" and s % 1 == 0 and s >= 1 and s <= 8 then slots[s] = true end
	end
	bought = { key = data.key, slots = slots }
end

return CardShopService
