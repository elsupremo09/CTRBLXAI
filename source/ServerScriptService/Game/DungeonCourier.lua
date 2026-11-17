--!strict
-- DungeonCourier.lua
-- CTRBLXAI | EV-17 Courier's Rest + the Bag screen list (silver/Bag redesign steps 4-5, 2026-11-16;
-- project_rules 258 pack size, 261 event pool, 264 run end, 272 EV-17, 278 silver, 279 Bag).
--
--   * Courier's Rest: the player picks Bag items to send home, up to the pack size for the facility level
--     (D.CourierPack: L1-L3 4, L4-L7 6, L8-L10 8), 5 silver per pack slot (D.CourierSilverPerSlot).
--     Gear 1 slot, a consumable stack 1 slot, each skill / augment card 1 slot per copy, each Elite/Boss
--     material kind 1 slot. Normal materials and any amount of Bag gold are free and take no slot.
--     Sent items leave the Bag at once (their slots are free), are safe on every run end (incl. wipeout and
--     early escape) and can't be used again this run. Relics and an owed Smith's Wager item can't be sent.
--   * Bag list: what the Bag screen and the full-Bag popup show (names, rarity, icon, tag, counts).
-- Pure on the run table; no require of DungeonService (no cycle). Run state: run.courierSent (saved).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Content = ReplicatedStorage:WaitForChild("Content")
local SkillData: any = require(Content:WaitForChild("SkillData"))
local AugmentData: any = require(Content:WaitForChild("AugmentData"))
local ConsumableData: any = require(Content:WaitForChild("ConsumableData"))
local BonusData: any = require(Content:WaitForChild("BonusData")) -- rune gem names (same format as RuneforgeService)
local DungeonRules = require(script.Parent:WaitForChild("DungeonRules"))
local DungeonSilver = require(script.Parent:WaitForChild("DungeonSilver")) -- pure, requires DungeonRules only
local ItemDisplay: any = require(script.Parent:WaitForChild("ItemDisplay"))
local DungeonFurniture = require(script.Parent:WaitForChild("DungeonFurniture")) -- furniture step 3 (requires DungeonRules + FurnitureData only: no cycle)
local D = DungeonRules.Data

local MAX_PICKS = 64
local MAT_NAME = table.freeze({ mercury = "Mercury", crystals = "Crystals", sulfur = "Sulfur" })

local Courier = {}

function Courier.PackSize(facilityLevel: any): number
	local t: { number } = D.CourierPack :: any
	return t[math.clamp(math.floor(tonumber(facilityLevel) or 1), 1, #t)]
end

local function isStack(key: string): boolean return string.sub(key, 1, 12) == "consumables:" end

local function cardInfo(key: string): (string, string?)
	local cat, id = string.match(key, "^(%w+):(.+)$")
	local def: any = nil
	if cat == "skillCards" then def = SkillData[id]
	elseif cat == "augmentCards" then def = AugmentData[id]
	elseif cat == "consumables" and id then def = ConsumableData.GetById(id) end
	return (if def and type(def.name) == "string" then def.name else tostring(id or key)), (if def then def.icon else nil)
end

-- Rune gem display name, same as the Runeforge: stat gem "{family} T{tier}", passive gem its name.
local function gemName(id: string): string
	local a = BonusData.NumericalAttributes and BonusData.NumericalAttributes[id]
	if type(a) == "table" and a.family and a.tier then return `{a.family} T{a.tier}` end
	local p = BonusData.BonusPassives and BonusData.BonusPassives[id]
	if type(p) == "table" and type(p.name) == "string" then return p.name end
	return id
end

local function matName(key: string): string
	if MAT_NAME[key] then return MAT_NAME[key] end
	if string.sub(key, 1, 4) == "gem:" then return gemName(string.sub(key, 5)) end
	return key
end

-- Item detail tables for the dungeon inspectors (Merchant / Treasure / Bag, 2026-11-16 7:14 PM user ruling):
-- the same ItemDisplay.buildItemEntry the normal Merchant sends; consumables and cards get a small detail
-- built from their data. Display only (SEC-002): the client never prices or checks anything from these.
function Courier.GearDetail(it: any): any
	if type(it) ~= "table" then return nil end
	local ok, e = pcall(ItemDisplay.buildItemEntry, it)
	if not ok or type(e) ~= "table" then return { instanceId = it.instanceId, name = tostring(it.displayName or "Unknown"), rarity = it.rarityId, itemLevel = it.itemLevel } end
	return e
end

--- Player-facing name: affix name, else the base name (Common items have no displayName; the Merchant
--- showed "?" for them, user screenshot 2026-11-16 7:14 PM).
function Courier.ItemName(it: any): string
	local d = Courier.GearDetail(it)
	return if d and type(d.name) == "string" and d.name ~= "" then d.name else "an item"
end

function Courier.ConsumableDetail(id: string): any
	local def = ConsumableData.GetById(id)
	if type(def) ~= "table" then return nil end
	return { isConsumable = true, name = def.name, rarity = def.tier or "Common", icon = def.icon,
		effectFormula = def.effectFormula, maxCharges = def.maxCharges, rtCost = def.rtCost, range = def.range,
		targetRules = def.targetRules }
end

--- Detail for a Bag card key ("skillCards:ID" / "augmentCards:ID" / "consumables:ID").
function Courier.CardDetail(key: string): any
	local cat, id = string.match(key, "^(%w+):(.+)$")
	if cat == "consumables" and id then return Courier.ConsumableDetail(id) end
	local def: any = nil
	if cat == "skillCards" then def = SkillData[id] elseif cat == "augmentCards" then def = AugmentData[id] end
	if type(def) ~= "table" then return nil end
	return { isCard = true, name = def.name, icon = def.icon, description = def.description }
end

local function gearEntry(it: any, tag: string?): any
	local e = Courier.GearDetail(it) or {}
	return { kind = "gear", id = it.instanceId, name = e.name, rarity = e.rarity, icon = e.icon, level = e.itemLevel, tag = tag, detail = e }
end

local function boughtCards(run: any): { [string]: number }
	return (run.boughtKeep and run.boughtKeep.cards) or {}
end

--- Bag screen / full-Bag popup list. home = DungeonLoadout.HomeItems(run) { gear = { item }, cards = { [key] = n } }.
--- tag: "bought" / "home" (data only: SB-19 / SB-20 retired 2026-11-16 7:22 PM, no text shown), nil = found.
function Courier.BagList(run: any, home: any): any
	if type(run) ~= "table" then return nil end
	local bought = (run.boughtKeep and run.boughtKeep.gear) or {}
	local bc = boughtCards(run)
	local open = (type(run.dgLoad) == "table" and run.dgLoad.open) or {}
	local items = {}
	for _, id in run.bag.gear do
		local it = run.bag.gearItems[id]
		if it then table.insert(items, gearEntry(it, if bought[id] then "bought" else nil)) end
	end
	for key, q in run.bag.cards or {} do
		if type(q) == "number" and q > 0 then
			local name, icon = cardInfo(key)
			local opened = nil
			if isStack(key) then opened = open[string.sub(key, 13)] end
			table.insert(items, { kind = "card", key = key, name = name, icon = icon, n = q, detail = Courier.CardDetail(key),
				tag = if (bc[key] or 0) >= q then "bought" else nil, opened = if type(opened) == "table" then table.clone(opened) else nil,
				max = if isStack(key) then (function() local d = ConsumableData.GetById(string.sub(key, 13)) return d and d.maxCharges end)() else nil })
		end
	end
	for _, it in (home and home.gear) or {} do table.insert(items, gearEntry(it, "home")) end
	for key, q in (home and home.cards) or {} do
		local name, icon = cardInfo(key)
		table.insert(items, { kind = "card", key = key, name = name, icon = icon, n = q, tag = "home", home = true, detail = Courier.CardDetail(key) })
	end
	local held = {}
	for _, e in run.bagHeld or {} do
		if e.kind == "gearItem" and type(e.item) == "table" then table.insert(held, gearEntry(e.item))
		elseif e.kind == "cards" then
			local name, icon = cardInfo(e.key)
			table.insert(held, { kind = "card", key = e.key, name = name, icon = icon, n = e.n, detail = Courier.CardDetail(e.key) })
		end
	end
	return { items = items, held = held, sent = Courier.SentList(run), gold = run.bag.gold or 0 }
end

--- What EV-17 already sent home (Bag screen section "Sent home (safe)", SB-34).
function Courier.SentList(run: any): { any }
	local s = run and run.courierSent
	local out = {}
	if type(s) ~= "table" then return out end
	for _, id in s.gear or {} do
		local it = s.gearItems and s.gearItems[id]
		if it then table.insert(out, gearEntry(it)) end
	end
	for key, q in s.cards or {} do local name, icon = cardInfo(key) table.insert(out, { kind = "card", key = key, name = name, icon = icon, n = q, detail = Courier.CardDetail(key) }) end
	for _, bucket in { "eliteMats", "bossMats", "normalMats" } do
		for key, q in s[bucket] or {} do table.insert(out, { kind = "mat", key = key, name = matName(key), n = q }) end
	end
	if (s.gold or 0) > 0 then table.insert(out, { kind = "gold", n = s.gold }) end
	return out
end

--- EV-17 picker: every Bag thing that can be sent, with its pack-slot cost.
function Courier.Options(run: any): any
	local items = {}
	local bought = (run.boughtKeep and run.boughtKeep.gear) or {}
	local bc = boughtCards(run)
	for _, id in run.bag.gear do
		local it = run.bag.gearItems[id]
		if it then local e = gearEntry(it, if bought[id] then "bought" else nil) e.slots = 1 table.insert(items, e) end
	end
	for key, q in run.bag.cards or {} do
		if type(q) == "number" and q > 0 then
			local name, icon = cardInfo(key)
			table.insert(items, { kind = "card", key = key, name = name, icon = icon, n = q, slots = if isStack(key) then 1 else q,
				tag = if (bc[key] or 0) >= q then "bought" else nil })
		end
	end
	local mats: { [string]: number } = {}
	for _, bucket in { "eliteMats", "bossMats" } do
		for key, q in run.bag[bucket] or {} do if q > 0 then mats[key] = (mats[key] or 0) + q end end
	end
	for key, q in mats do table.insert(items, { kind = "mat", key = key, name = matName(key), n = q, slots = 1 }) end
	for key, q in run.bag.normalMats or {} do
		if q > 0 then table.insert(items, { kind = "normal", key = key, name = matName(key), n = q, slots = 0 }) end
	end
	return { pack = Courier.PackSize(run.card and run.card.facilityLevel), perSlot = D.CourierSilverPerSlot,
		silver = DungeonSilver.Get(run), gold = run.bag.gold or 0, items = items }
end

local function strList(v: any, maxLen: number): { string }?
	if v == nil then return {} end
	if type(v) ~= "table" or #v > MAX_PICKS then return nil end
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	for i, s in v do
		if type(i) ~= "number" or type(s) ~= "string" or #s > maxLen or seen[s] then return nil end
		seen[s] = true
		table.insert(out, s)
	end
	return out
end

local function sentOf(run: any): any
	local s = run.courierSent
	if type(s) ~= "table" then
		s = { gold = 0, normalMats = {}, eliteMats = {}, bossMats = {}, gear = {}, gearItems = {}, cards = {}, open = {} }
		run.courierSent = s
	end
	return s
end

--- Send picks home (server checks everything). picks = { gear = { ids }, cards = { keys }, mats = { keys },
--- normal = bool (all normal materials), gold = bool (all Bag gold) }. Returns ok, { count, cost } | error.
function Courier.Send(run: any, picks: any): (boolean, any)
	if type(run) ~= "table" or type(picks) ~= "table" then return false, "Invalid request" end
	local gear, cards, mats = strList(picks.gear, 128), strList(picks.cards, 64), strList(picks.mats, 64)
	if not (gear and cards and mats) then return false, "Invalid request" end
	if (picks.gold ~= nil and type(picks.gold) ~= "boolean") or (picks.normal ~= nil and type(picks.normal) ~= "boolean") then return false, "Invalid request" end
	local slots = #gear + #mats
	for _, id in gear do if type(run.bag.gearItems[id]) ~= "table" then return false, "Invalid request" end end
	for _, key in cards do
		local q = (run.bag.cards or {})[key]
		if type(q) ~= "number" or q <= 0 then return false, "Invalid request" end
		slots += if isStack(key) then 1 else q
	end
	for _, key in mats do
		if ((run.bag.eliteMats or {})[key] or 0) + ((run.bag.bossMats or {})[key] or 0) <= 0 then return false, "Invalid request" end
	end
	local sendGold = picks.gold == true and (run.bag.gold or 0) > 0
	local sendNormal = picks.normal == true and next(run.bag.normalMats or {}) ~= nil
	if slots > Courier.PackSize(run.card and run.card.facilityLevel) then return false, "Invalid request" end
	if slots == 0 and not sendGold and not sendNormal then return false, "Invalid request" end
	local cost = slots * D.CourierSilverPerSlot
	if cost > 0 and not DungeonSilver.Spend(run, cost, "courier") then return false, "Not enough silver" end
	local s = sentOf(run)
	for _, id in gear do
		local it = run.bag.gearItems[id]
		run.bag.gearItems[id] = nil
		local ix = table.find(run.bag.gear, id)
		if ix then table.remove(run.bag.gear, ix) end
		DungeonSilver.UnmarkBought(run, "gear", id, "sent home") -- safe now: the mark is not needed any more
		table.insert(s.gear, id)
		s.gearItems[id] = it
	end
	for _, key in cards do
		local q = run.bag.cards[key]
		run.bag.cards[key] = nil
		DungeonSilver.UnmarkBought(run, "card", key, "sent home", q)
		s.cards[key] = (s.cards[key] or 0) + q
		if isStack(key) and type(run.dgLoad) == "table" and type(run.dgLoad.open) == "table" then
			-- opened copies keep their charges (Tester F1 rule): they come home at the charges left
			local cid = string.sub(key, 13)
			local list = run.dgLoad.open[cid]
			if type(list) == "table" then
				s.open[cid] = s.open[cid] or {}
				for i, ch in list do if i <= q and type(ch) == "number" then table.insert(s.open[cid], ch) end end
				run.dgLoad.open[cid] = nil
			end
		end
	end
	for _, key in mats do
		for _, bucket in { "eliteMats", "bossMats" } do
			local q = (run.bag[bucket] or {})[key]
			if q and q > 0 then s[bucket][key] = (s[bucket][key] or 0) + q run.bag[bucket][key] = nil end
		end
	end
	if sendNormal then
		for key, q in run.bag.normalMats do s.normalMats[key] = (s.normalMats[key] or 0) + q end
		run.bag.normalMats = {}
	end
	if sendGold then s.gold = (s.gold or 0) + run.bag.gold; run.bag.gold = 0 end
	DungeonFurniture.SendAll(run) -- furniture step 3 (default): found pieces go home with any send, free, no slot
	print(`[DungeonCourier] Sent home | {slots} slot(s), {#gear} gear, {#cards} card key(s), {#mats} mat kind(s){if sendNormal then " + normal mats" else ""}{if sendGold then " + gold" else ""} | {cost} silver`)
	return true, { count = slots, cost = cost }
end

--- Run end (any kind): everything sent home is kept. placeOpened(cid, charges) -> bool puts an opened copy
--- on a party unit at its charges left (DungeonLoadout, same as rule 264 R3); else it comes home as a full copy.
function Courier.OnRunEnd(run: any, outcome: any, placeOpened: ((string, number) -> boolean)?)
	local s = run and run.courierSent
	if type(s) ~= "table" or not (outcome and outcome.kept) then return end
	local kept = outcome.kept
	kept.gold = (kept.gold or 0) + (s.gold or 0)
	for _, bucket in { "normalMats", "eliteMats", "bossMats", "cards" } do
		kept[bucket] = kept[bucket] or {}
		for key, q in s[bucket] or {} do kept[bucket][key] = (kept[bucket][key] or 0) + q end
	end
	kept.gear = table.clone(kept.gear or {})
	kept.gearItems = table.clone(kept.gearItems or {})
	for _, id in s.gear or {} do
		if s.gearItems[id] and not kept.gearItems[id] then table.insert(kept.gear, id) kept.gearItems[id] = s.gearItems[id] end
	end
	for cid, list in s.open or {} do
		local key = "consumables:" .. cid
		for _, ch in list do
			if (kept.cards[key] or 0) > 0 and placeOpened and placeOpened(cid, ch) then
				kept.cards[key] -= 1
				if kept.cards[key] <= 0 then kept.cards[key] = nil end
			end
		end
	end
	print(`[DungeonCourier] Run end ({tostring(outcome.kind)}): sent-home items kept | gear {#(s.gear or {})} | gold {s.gold or 0}`)
	run.courierSent = nil
end

--------------------------------------------------
-- SAVE
--------------------------------------------------

function Courier.Export(run: any): any
	local s = run and run.courierSent
	if type(s) ~= "table" then return nil end
	local items = {}
	for _, id in s.gear do if s.gearItems[id] then table.insert(items, s.gearItems[id]) end end
	return { gold = s.gold, normalMats = s.normalMats, eliteMats = s.eliteMats, bossMats = s.bossMats,
		gearItems = items, cards = s.cards, open = s.open }
end

local function numMap(t: any, maxKey: number): { [string]: number }
	local out: { [string]: number } = {}
	if type(t) ~= "table" then return out end
	local n = 0
	for k, v in t do
		n += 1
		if n > 500 then break end
		if type(k) == "string" and #k <= maxKey and type(v) == "number" and v >= 1 and v <= 1000000 and v % 1 == 0 then out[k] = v end
	end
	return out
end

function Courier.Import(run: any, d: any)
	run.courierSent = nil
	if type(d) ~= "table" then return end -- old saves: nothing sent
	local s = { gold = if type(d.gold) == "number" and d.gold >= 0 and d.gold <= 1000000 and d.gold % 1 == 0 then d.gold else 0,
		normalMats = numMap(d.normalMats, 64), eliteMats = numMap(d.eliteMats, 64), bossMats = numMap(d.bossMats, 64),
		gear = {}, gearItems = {}, cards = numMap(d.cards, 64), open = {} }
	for _, it in (if type(d.gearItems) == "table" then d.gearItems else {}) do
		if #s.gear >= 500 then break end
		if type(it) == "table" and type(it.instanceId) == "string" and #it.instanceId <= 128 and not s.gearItems[it.instanceId] then
			table.insert(s.gear, it.instanceId)
			s.gearItems[it.instanceId] = it
		end
	end
	for cid, list in (if type(d.open) == "table" then d.open else {}) do
		if type(cid) == "string" and #cid <= 64 and type(list) == "table" then
			local l = {}
			for _, ch in list do if type(ch) == "number" and ch >= 1 and ch <= 999 and ch % 1 == 0 and #l < 100 then table.insert(l, ch) end end
			if #l > 0 then s.open[cid] = l end
		end
	end
	run.courierSent = s
end

return Courier
