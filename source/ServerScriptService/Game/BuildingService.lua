--!strict
-- BuildingService.lua
-- CTRBLXAI | Slice 8 step 1 (2026-11-16) — buildings open by Renown Rank, upgraded from the
-- Guild Hall.
--
-- Rules (docs\CTRBLXAI.db guild_facilities 3, 8, 89, 90, 97, 98; USER RULING 2026-11-16 1:53 PM):
--   * Renown Rank ALONE opens a building (the Guild Hall no longer gates or caps anything).
--   * A building is open if Rank >= its unlock Rank, OR its saved level is 2+, OR it is on the
--     save's "opened buildings" list. Once open it never closes.
--   * Level 1 of every building is free; gold buys L2..L10 (cost tables guild_facilities 26-88).
--   * Every building is upgraded from ONE list (the Guild Hall tab). Reason order:
--     Rank lock -> Max level -> (Blacksmith: no effect yet) -> Not enough gold.
--
-- OWNS: the unlock table, the cost tables, the opened list + "New" marks, the upgrade rows.
-- MUST NOT OWN: building levels (GuildMenuService), gold (CurrencyService), Rank (RenownService).
-- Those are INJECTED via Init (ARC-004 / ARC-006, nil-safe) so there is no require cycle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Guild Hall rooms / spots / bonus cap / rarity gates for the next-level lines (one source, DAT-001).
local FurnitureData: any = require(ReplicatedStorage:WaitForChild("Content"):WaitForChild("FurnitureData"))

local BuildingService = {}

local MAX_LEVEL = 10

-- Display order of the Guild Hall list (open rows keep this order; locked rows go to the
-- bottom in unlock order).
local ORDER = table.freeze({
	"GuildHall", "QuestBoard", "Tavern", "Merchant", "Blacksmith", "Apothecary",
	"Runeforge", "TrainingGrounds", "Crucible", "Dungeon",
})

-- guild_facilities 8 / 89: unlock Rank per building (screens included: Dispatch has no levels).
local UNLOCK_RANK: { [string]: number } = table.freeze({
	GuildHall = 1, QuestBoard = 1, Tavern = 1, Merchant = 1,
	Blacksmith = 3, Dispatch = 5, Apothecary = 8, Runeforge = 12,
	TrainingGrounds = 16, Crucible = 20, Dungeon = 25,
})

local DISPLAY: { [string]: string } = table.freeze({
	GuildHall = "Guild Hall", QuestBoard = "Quest Board", Tavern = "Tavern", Merchant = "Merchant",
	Blacksmith = "Blacksmith", Dispatch = "Dispatch", Apothecary = "Apothecary", Runeforge = "Runeforge",
	TrainingGrounds = "Training Grounds", Crucible = "Crucible", Dungeon = "Dungeon",
})

-- Gold price of reaching level n (index n). Level 1 is free (USER RULING 2026-11-16), so
-- index 1 is never charged. guild_facilities 26-30, 49, 65, 72, 80, 88.
local COSTS: { [string]: { number } } = table.freeze({
	GuildHall       = { 267, 317, 400, 517, 667, 850, 1067, 1317, 1600, 1917 },
	Tavern          = { 211, 244, 300, 378, 478, 600, 744, 911, 1100, 1311 },
	Blacksmith      = { 325, 400, 525, 700, 925, 1200, 1525, 1900, 2325, 2800 },
	Merchant        = { 211, 244, 300, 378, 478, 600, 744, 911, 1100, 1311 },
	QuestBoard      = { 189, 216, 261, 324, 405, 504, 621, 756, 909, 1080 },
	Runeforge       = { 267, 317, 400, 517, 667, 850, 1067, 1317, 1600, 1917 },
	Crucible        = { 211, 244, 300, 378, 478, 600, 744, 911, 1100, 1311 },
	Apothecary      = { 157, 177, 211, 259, 320, 395, 484, 586, 702, 832 },
	TrainingGrounds = { 234, 275, 344, 440, 564, 715, 894, 1100, 1334, 1595 },
	Dungeon         = { 234, 275, 344, 440, 564, 715, 894, 1100, 1334, 1595 },
})

-- Renown Rank gate per level (USER RULINGS 2026-11-17 5:18 / 5:23 PM, guild_facilities 115, slope 8x):
-- level n (n >= 2) needs Renown Rank max(unlock Rank + RANK_GATE_STEP x (n - 1), RANK_GATE_SLOPE x (n - 1)),
-- so level 10 needs Rank 72. Gold costs are unchanged. The Blacksmith keeps its own stricter rule
-- ("No effect until Renown Rank {n}", blacksmithEffectRank). The gate only stops the NEXT upgrade:
-- levels a save already has never drop.
local RANK_GATE_STEP = 2
local RANK_GATE_SLOPE = 8

-- Rarity order for "Unlocks: {rarity} ..." lines (a higher top rarity at the next level).
local RARITY_RANK: { [string]: number } = table.freeze({
	Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Exalted = 5, Legendary = 6, Mythic = 7, Transcendent = 8,
})
local RARITY_LIST = table.freeze({ "Common", "Uncommon", "Rare", "Epic", "Exalted", "Legendary", "Mythic", "Transcendent" })

-- Old saves (made before this build) had buildings open by Guild Hall level. On their first
-- load every building they could already use goes on the opened list (guild_facilities 97).
local LEGACY_GH_UNLOCK: { [string]: number } = table.freeze({
	GuildHall = 1, QuestBoard = 1, Tavern = 1, Merchant = 1, Blacksmith = 1, Dispatch = 1,
	Apothecary = 4, Runeforge = 4, TrainingGrounds = 5, Crucible = 5, Dungeon = 6,
})

local RATE_LIMIT_SECONDS = 0.25 -- SEC-001

--------------------------------------------------
-- INJECTED (Init) — all nil-safe
--------------------------------------------------
type Deps = {
	getRank: (() -> number)?,
	getLevel: ((string) -> number)?,
	applyLevel: ((string, number) -> ())?,  -- the ONE level setter (shared with the dev tool)
	getGold: (() -> number)?,
	spendGold: ((number) -> (boolean, string?))?,
	canUpgradeNow: (() -> boolean)?,       -- menu open at the guild base (not in a battle)
	dungeonLevelInfo: ((number) -> any)?,  -- party cap / Bag / Courier / stages for a level
	levelInfo: ((string, number) -> any)?,  -- a building's numbers at a level (its own service's table)
	markDirty: (() -> ())?,
	onOpened: (({ string }) -> ())?,       -- side effects when buildings open (stat rebuild)
}
local deps: Deps = {}

local opened: { [string]: boolean } = {}
local newMark: { [string]: boolean } = {}
local lastCallAt: { [number]: number } = {}

local function rank(): number
	local r = deps.getRank and deps.getRank() or 1
	return math.max(1, math.floor(tonumber(r) or 1))
end

local function levelOf(name: string): number
	local l = deps.getLevel and deps.getLevel(name) or 1
	return math.clamp(math.floor(tonumber(l) or 1), 1, MAX_LEVEL)
end

function BuildingService.Init(d: Deps)
	deps = d
end

function BuildingService.Display(name: string): string
	return DISPLAY[name] or name
end

function BuildingService.UnlockRank(name: string): number
	return UNLOCK_RANK[name] or 1
end

--- True if the building is open: Rank reached, level 2+, or already on the opened list.
function BuildingService.IsOpen(name: string): boolean
	if opened[name] then return true end
	if rank() >= BuildingService.UnlockRank(name) then return true end
	if COSTS[name] and levelOf(name) >= 2 then return true end
	return false
end

--- Puts every building that is open now on the saved list. Returns the display names of the
--- buildings that opened since the last call (unlock order), for the Rank-up banner.
function BuildingService.Refresh(): { string }
	local fresh: { string } = {}
	local names: { string } = {}
	for n in UNLOCK_RANK do table.insert(names, n) end
	table.sort(names, function(a: string, b: string)
		local ra, rb = UNLOCK_RANK[a], UNLOCK_RANK[b]
		if ra ~= rb then return ra < rb end
		return a < b
	end)
	local changed = false
	for _, n in names do
		if not opened[n] and BuildingService.IsOpen(n) then
			opened[n] = true
			changed = true
			-- "New" mark only for buildings past Rank 1 (the starting set is not "new").
			if UNLOCK_RANK[n] > 1 then
				newMark[n] = true
				table.insert(fresh, n)
			end
		end
	end
	if changed and deps.markDirty then deps.markDirty() end
	if #fresh > 0 and deps.onOpened then
		local ok, err = pcall(deps.onOpened, fresh)
		if not ok then warn("[BuildingService] onOpened failed: " .. tostring(err)) end
	end
	local shown: { string } = {}
	for _, n in fresh do table.insert(shown, DISPLAY[n] or n) end
	if #fresh > 0 then print(`[BuildingService] Opened by Renown Rank {rank()}: {table.concat(shown, ", ")}`) end
	return shown
end

--- Open state + lock Rank + "New" mark for every building, for the guild nav.
function BuildingService.OpenState(): { [string]: any }
	local out: { [string]: any } = {}
	for n, r in UNLOCK_RANK do
		out[n] = { open = BuildingService.IsOpen(n), unlockRank = r, display = DISPLAY[n] or n, new = newMark[n] == true }
	end
	return out
end

function BuildingService.ClearNew(name: any)
	if type(name) == "string" and newMark[name] then
		newMark[name] = nil
		if deps.markDirty then deps.markDirty() end
	end
end

--------------------------------------------------
-- UPGRADE LIST
--------------------------------------------------

-- Blacksmith level n only does something once Rank + 5 passes (n - 1) x 10
-- (Blacksmith cap = min(Rank + 5, building x 10, ...), guild_facilities 12 / Simulator fix 4).
local function blacksmithEffectRank(n: number): number
	return math.max(1, 10 * (n - 1) - 4)
end

--- Renown Rank a building needs for level n (guild_facilities 115). Blacksmith: its own rule.
function BuildingService.RankForLevel(name: string, n: number): number
	if n <= 1 then return 1 end
	if name == "Blacksmith" then return blacksmithEffectRank(n) end
	return math.max(BuildingService.UnlockRank(name) + RANK_GATE_STEP * (n - 1), RANK_GATE_SLOPE * (n - 1))
end

--------------------------------------------------
-- NEXT-LEVEL LINES (USER RULING 2026-11-17 5:18 PM, guild_facilities 113)
-- Every change from level `from` to `to`. Approved formats: "{thing} {a} → {b}", "Unlocks: {thing}",
-- "+1 furniture slot", "+1 quest slot", "+1 card", the Dungeon party / Bag / Courier / stage lines.
-- Numbers come from each building's own table (FurnitureData, the services via deps.levelInfo,
-- dungeonLevelInfo), never copies here. Lines marked DRAFT below wait for user approval.
--------------------------------------------------

local function infoFor(name: string, level: number): any?
	local fn = deps.levelInfo
	if not fn then return nil end
	local ok, v = pcall(fn, name, level)
	if ok and type(v) == "table" then return v end
	return nil
end

local function change(out: { string }, label: string, a: any, b: any, unit: string?)
	if a == nil or b == nil or a == b then return end
	local u = unit or ""
	table.insert(out, `{label} {tostring(a)}{u} → {tostring(b)}{u}`)
end

local function unlock(out: { string }, thing: string)
	table.insert(out, `Unlocks: {thing}`) -- GH-NEXT-UNLOCK
end

-- "Unlocks: {Rarity} {suffix}" when the next level's top rarity is higher.
local function unlockRarity(out: { string }, aTop: any, bTop: any, suffix: string)
	if type(bTop) ~= "string" then return end
	local ra = if type(aTop) == "string" then (RARITY_RANK[aTop] or 0) else 0
	local rb = RARITY_RANK[bTop] or 0
	if rb > ra then unlock(out, `{bTop} {suffix}`) end
end

-- "Unlocks: {label}" for every key whose unlock level is exactly `to`, in a fixed order.
local function unlockAt(out: { string }, levels: any, to: number, order: { string }, labels: { [string]: string })
	if type(levels) ~= "table" then return end
	for _, k in order do
		if levels[k] == to and labels[k] then unlock(out, labels[k]) end
	end
end

local APOTHECARY_TYPES = table.freeze({ "Support", "Utility", "Control", "Environment", "Deployable" })
local APOTHECARY_TYPE_LABEL = table.freeze({
	Support = "Support items", Utility = "Utility items", Control = "Control items", -- "Control items" approved
	Environment = "Environment items", Deployable = "Deployable items",              -- same format (DRAFT words)
})
local CARD_TYPES = table.freeze({ "BasicAug", "ControlUtility", "AdvancedAug" })
local CARD_TYPE_LABEL = table.freeze({ -- DRAFT words (guild_facilities 78 unlock list)
	BasicAug = "Basic augments", ControlUtility = "Control & Utility skills", AdvancedAug = "Advanced augments",
})
local REROLL_ORDER = table.freeze({ "Exalted", "Legendary", "Mythic", "Transcendent" })
local REROLL_LABEL = table.freeze({
	Exalted = "Exalted rerolls", Legendary = "Legendary rerolls", -- "Legendary rerolls" approved
	Mythic = "Mythic rerolls", Transcendent = "Transcendent rerolls",
})
local BS_ORDER = table.freeze({ "Rare", "Epic", "Exalted", "Legendary", "Mythic" })
local BS_LABEL = table.freeze({
	Rare = "Rare upgrades", Epic = "Epic upgrades", Exalted = "Exalted upgrades", -- "Epic upgrades" approved
	Legendary = "Legendary upgrades", Mythic = "Mythic upgrades",
})

local function nextLines(name: string, from: number, to: number): { string }
	local out: { string } = {}
	if name == "GuildHall" then
		local V4 = FurnitureData.V4
		local fa, fb = V4.FloorSpots(from), V4.FloorSpots(to)
		if fb - fa == 1 then
			table.insert(out, "+1 furniture slot") -- approved GH-SLOT-GAIN
		else
			change(out, "Furniture slots", fa, fb) -- DRAFT (L9 → L10 adds 2)
		end
		change(out, "Wall spots", V4.WallSpots(from), V4.WallSpots(to)) -- DRAFT
		change(out, "Furniture bonus cap", V4.CapFor(from), V4.CapFor(to)) -- approved
		for _, room in V4.Rooms do
			if room.gh == to then unlock(out, tostring(room.name)) end -- e.g. "Unlocks: Strategy Room"
		end
		for _, r in V4.RarityOrder do
			local def = V4.Rarities[r]
			if def and def.gate == to and to > 1 then unlock(out, `{r} furniture`) end -- e.g. "Legendary furniture"
		end
	elseif name == "QuestBoard" then
		table.insert(out, "+1 quest slot") -- approved (L1 = 3 quests, +1 per level)
	elseif name == "Dungeon" then
		local fn = deps.dungeonLevelInfo
		local a: any, b: any = nil, nil
		if fn then
			local okA, va = pcall(fn, from)
			local okB, vb = pcall(fn, to)
			if okA and type(va) == "table" then a = va end
			if okB and type(vb) == "table" then b = vb end
		end
		if a and b then
			change(out, "Party size", a.party, b.party)       -- approved
			change(out, "Bag", a.bag, b.bag)                  -- approved
			change(out, "Courier pack", a.courier, b.courier) -- approved
			change(out, "Dungeons offered", a.choices, b.choices) -- approved
			if (tonumber(b.maxTier) or 0) > (tonumber(a.maxTier) or 0) and type(b.topTier) == "string" then
				unlock(out, `{b.topTier} dungeons`) -- "Hard dungeons" approved; "Medium dungeons" same format
			end
			if b.endless and not a.endless then
				unlock(out, "Endless stages") -- approved
			elseif (tonumber(b.stages) or 0) > (tonumber(a.stages) or 0) then
				table.insert(out, `Stage {b.stages} opens`) -- approved
			end
		end
	else
		local a, b = infoFor(name, from), infoFor(name, to)
		if not (a and b) then return out end
		if name == "Tavern" then
			change(out, "Recruits", a.recruits, b.recruits) -- approved
			if b.quality and not a.quality then unlock(out, "Quality recruits") end
			if b.elite and not a.elite then unlock(out, "Elite recruits") end
		elseif name == "Merchant" then
			change(out, "Shelf", a.shelf, b.shelf) -- approved
			unlockRarity(out, a.top, b.top, "gear") -- "Epic gear" / "Exalted gear" approved
		elseif name == "Blacksmith" then
			change(out, "Max item level", a.maxItemLevel, b.maxItemLevel) -- approved
			change(out, "Upgrade discount", a.discount, b.discount, "%") -- approved
			unlockAt(out, b.rarityUnlock, to, BS_ORDER, BS_LABEL)
		elseif name == "Apothecary" then
			change(out, "Shelf", a.shelf, b.shelf)                   -- approved
			change(out, "Buy discount", a.discount, b.discount, "%") -- approved
			change(out, "Refill cost", a.refill, b.refill, "%")      -- approved
			unlockAt(out, b.typeUnlock, to, APOTHECARY_TYPES, APOTHECARY_TYPE_LABEL)
			unlockRarity(out, a.top, b.top, "items") -- DRAFT words ("Rare items" ...)
			if b.charges and not a.charges then unlock(out, "+25% max charges") end -- DRAFT
			if b.slot and not a.slot then unlock(out, "+1 consumable slot") end      -- approved
		elseif name == "Runeforge" then
			change(out, "Forge discount", a.discount, b.discount, "%") -- approved
			unlockRarity(out, a.forge, b.forge, "forging") -- "Epic forging" approved
			unlockAt(out, b.rerollUnlock, to, REROLL_ORDER, REROLL_LABEL)
		elseif name == "TrainingGrounds" then
			local sa, sb = tonumber(a.shelf), tonumber(b.shelf)
			if sa and sb and sb - sa == 1 then table.insert(out, "+1 card") else change(out, "Shelf", sa, sb) end -- approved
			change(out, "Buy discount", a.discount, b.discount, "%") -- approved
			unlockRarity(out, a.top, b.top, "cards") -- "Epic cards" / "Legendary cards" approved
			unlockAt(out, b.typeUnlock, to, CARD_TYPES, CARD_TYPE_LABEL)
			if b.doctrines and not a.doctrines then unlock(out, "Doctrines") end -- approved (guild_facilities 78)
			if b.slot2 and not a.slot2 then unlock(out, "2nd augment slot (Lv 80+ units)") end -- approved
		elseif name == "Crucible" then
			change(out, "Items needed", a.needed, b.needed) -- approved
			if a.boost ~= b.boost and a.boost ~= nil and b.boost ~= nil then
				table.insert(out, `Level boost +{a.boost} → +{b.boost}`) -- approved
			end
			change(out, "Merge discount", a.discount, b.discount, "%") -- DRAFT
			unlockRarity(out, a.top, b.top, "results") -- "Exalted results" approved
		end
	end
	return out
end

-- One row: what the Guild Hall list shows for a building, and whether Upgrade may be pressed.
-- Reason order (guild_facilities 115): locked -> Max level -> Rank too low -> Blacksmith no effect
-- -> not enough gold.
local function rowFor(name: string, gold: number): any
	local lvl = levelOf(name)
	local open = BuildingService.IsOpen(name)
	local row: any = {
		name = name, display = DISPLAY[name] or name, level = lvl, maxLevel = MAX_LEVEL,
		open = open, unlockRank = BuildingService.UnlockRank(name), canUpgrade = false,
	}
	if not open then
		row.reason = `Opens at Renown Rank {row.unlockRank}` -- approved GH-ROW-LOCKED
		return row
	end
	if lvl >= MAX_LEVEL then
		row.reason = "Max level"
		return row
	end
	local to = lvl + 1
	local cost = COSTS[name][to]
	row.cost = cost
	row.next = `Level {lvl} → {to}` -- approved GH-ROW-NEXT (kept for older clients)
	local okLines, lines: any = pcall(nextLines, name, lvl, to)
	if not okLines then
		warn("[BuildingService] next-level lines failed for " .. name .. ": " .. tostring(lines))
		lines = {}
	end
	row.nextLines = lines
	local need = BuildingService.RankForLevel(name, to)
	local r = rank()
	row.rankNeed = need
	row.rankOk = r >= need
	if name == "Blacksmith" then
		if not row.rankOk then
			row.reason = `No effect until Renown Rank {need}` -- approved BS-NOEFFECT
			row.noEffect = true
			return row
		end
		row.rankText = `Renown Rank {need} reached` -- GH-NEXT-RANK-OK
	elseif not row.rankOk then
		row.rankText = `Next level needs Renown Rank {need}` -- GH-NEXT-RANK (red)
		row.reason = row.rankText
		row.rankLow = true
		return row
	else
		row.rankText = `Renown Rank {need} reached` -- GH-NEXT-RANK-OK (grey)
	end
	if gold < cost then
		row.reason = `Not enough gold ({gold} / {cost})`
		return row
	end
	row.canUpgrade = true
	return row
end

--- The Guild Hall upgrade list: open buildings first (fixed order), locked ones at the bottom
--- in unlock order.
function BuildingService.List(): { any }
	local gold = deps.getGold and deps.getGold() or 0
	local openRows, lockedRows = {}, {}
	for _, n in ORDER do
		local r = rowFor(n, gold)
		table.insert(if r.open then openRows else lockedRows, r)
	end
	table.sort(lockedRows, function(a: any, b: any)
		if a.unlockRank ~= b.unlockRank then return a.unlockRank < b.unlockRank end
		return a.name < b.name
	end)
	for _, r in lockedRows do table.insert(openRows, r) end
	return openRows
end

--- Server-side upgrade (SEC-001: the client sends a building name only; the server checks
--- everything and prices it). Returns (ok, message).
function BuildingService.Upgrade(player: Player, name: any): (boolean, string)
	local now = os.clock()
	local last = lastCallAt[player.UserId]
	if last and now - last < RATE_LIMIT_SECONDS then return false, "Too fast — try again" end
	lastCallAt[player.UserId] = now
	if type(name) ~= "string" or #name > 32 or not COSTS[name] then return false, "Unknown building" end
	if not (deps.canUpgradeNow and deps.canUpgradeNow()) then
		return false, "You can't upgrade buildings during a battle." -- approved rank text 16
	end
	local gold = deps.getGold and deps.getGold() or 0
	local row = rowFor(name, gold)
	if not row.canUpgrade then return false, row.reason or "Not allowed" end
	if not (deps.spendGold and deps.applyLevel) then return false, "Gold unavailable" end
	local okPay, why = deps.spendGold(row.cost)
	if not okPay then return false, tostring(why or "Not enough gold") end
	deps.applyLevel(name, row.level + 1)
	local now2 = levelOf(name)
	print(`[BuildingService] {name} upgraded L{row.level} -> L{now2} for {row.cost} gold`)
	return true, `{row.display} is now level {now2}!` -- approved rank text 11
end

--------------------------------------------------
-- SAVE (rides GuildMenuService's payload)
--------------------------------------------------

--- Approved lock line (guild_facilities 98): "{Building} unlocks at Renown Rank {n}. Complete quests to earn Renown."
function BuildingService.LockLine(name: string): string
	return `{DISPLAY[name] or name} unlocks at Renown Rank {UNLOCK_RANK[name] or 1}. Complete quests to earn Renown.`
end

function BuildingService.Export(): any
	local o, m = {}, {}
	for n in opened do table.insert(o, n) end
	for n in newMark do table.insert(m, n) end
	table.sort(o); table.sort(m)
	return { opened = o, newMarks = m }
end

--- data = the saved table (nil on saves from before this build). legacyBuildings = the saved
--- building levels; when data is nil and they exist, this is an old save: convert it once.
function BuildingService.Import(data: any, legacyBuildings: any)
	opened, newMark = {}, {}
	if type(data) == "table" then
		for _, n in (type(data.opened) == "table" and data.opened or {}) do
			if type(n) == "string" and UNLOCK_RANK[n] then opened[n] = true end
		end
		for _, n in (type(data.newMarks) == "table" and data.newMarks or {}) do
			if type(n) == "string" and UNLOCK_RANK[n] and opened[n] then newMark[n] = true end
		end
		return
	end
	if type(legacyBuildings) == "table" then
		local gh = math.clamp(math.floor(tonumber(legacyBuildings.GuildHall) or 1), 1, MAX_LEVEL)
		local added: { string } = {}
		for n, need in LEGACY_GH_UNLOCK do
			if gh >= need then
				opened[n] = true
				table.insert(added, n)
			end
		end
		table.sort(added)
		print(`[BuildingService] Old save converted (Guild Hall L{gh}): opened {table.concat(added, ", ")}`)
	end
end

--- W4: run the same open side effects as a live open (Apothecary stat rebuild). Called by
--- GuildMenuService.Import after the Apothecary import. At BOOT this is a no-op: Import runs
--- before GuildMenuService.Init wires deps, and there are no units yet. Units built later at
--- boot already include the Apothecary bonus (it is read from the level provider), so nothing
--- is lost. It only does work if a save is imported after Init (Tester W4-a, 2026-11-16).
--- The rebuild recomputes from scratch, so calling it again is harmless.
function BuildingService.RunLoadHooks()
	if opened.Apothecary and deps.onOpened then
		local ok, err = pcall(deps.onOpened, { "Apothecary" })
		if not ok then warn("[BuildingService] onOpened (load) failed: " .. tostring(err)) end
	end
end

return BuildingService
