--!strict
-- FurnitureService.lua
-- CTRBLXAI | Guild Hall furniture. v4 rebuild STEP 2 of 5 (2026-11-16): rolled piece INSTANCES,
-- room spots, save format v2 + old-save conversion. Rules: docs\CTRBLXAI.db guild_facilities 91-108
-- (v4 APPROVED 7:02 PM; data in FurnitureData.V4).
--
-- STEP 2 SCOPE (deliberate):
--   * Owns piece instances { uid, id, rarity, lines, sig, fixed } instead of owned flags.
--   * Rolls instances with the V4 rarity / pool / point tables (seeded; Fortune never applies).
--   * Places them in ROOM SPOTS (V4.Rooms by Guild Hall level; floor spots by category, wall
--     spots take Wall pieces). Pieces that don't fit go to storage. Nothing is ever deleted.
--   * Computes the V4 totals (cap 8 x GH, 40 per kind, threshold +2 / +1 per kind shared by
--     player and enemy lines) and exposes them via V4Totals() / State().v4 -- NOT applied yet
--     (unit stats = step 3, enemies = step 4).
--   * Units keep TODAY'S stats: BonusFor() returns the legacy (block 1) totals computed from the
--     placed instances' piece ids, exactly as before (cap 6 x GH, family 30, same piece once).
--   * Old remotes keep working (Buy / Place / Remove / Craft / CraftRows / Seen / State); State()
--     still sends the old fields (slots = floor spots, decor = wall spots, owned ids, shop).
--
-- OWNS: piece instances, room placements, the computed totals, the notice flag.
-- MUST NOT OWN: gold (CurrencyService), Guild Hall level (GuildMenuService), Rank (RenownService),
-- unit stats (EquipmentService reads BonusFor). All injected via Init (ARC-004 / ARC-006).
--
-- v5 build STEP 1 (2026-11-16, guild_facilities 92/101/102/107/110): units now get the V4 PLAYER totals
-- (FurnitureTotals.BonusTable) instead of the legacy block-1 totals; DispatchFeeDelta reads the V4
-- fixed bucket (War Table, same -5g); State() slotStatus/points/cap show the V4 numbers. Welcome
-- Straw Cot + Scribe's Desk are fixed 8-point pieces (row 110). Enemy lines still unapplied (step 2).
-- The legacy totals are still computed (unused by units) until the old UI fields are retired.
--
-- v5 build step A (2026-11-16): roller -> FurnitureRoll, spots + totals -> FurnitureTotals, save v2
-- export/import -> FurnitureSaveV2 (moved word-for-word, no behaviour change). State stays here.

-- v5 build STEP 3 (2026-11-16, guild_facilities 109 / loot_progression 15): the gold shop is retired (Buy
-- returns FUR-NO-SHOP, never charges); quest bosses drop no furniture (RollBossPiece retired); GrantDrop takes
-- a rolled dungeon piece (DungeonFurniture); no new piece at 400 owned (save safety, warn() only).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FurnitureData = require(ReplicatedStorage:WaitForChild("Content"):WaitForChild("FurnitureData"))
local V4: any = FurnitureData.V4

local FurnitureService = {}

local FurnitureRoll = require(script.Parent:WaitForChild("FurnitureRoll")) -- step A split (no cycle)
local FurnitureTotals = require(script.Parent:WaitForChild("FurnitureTotals")) -- step A split (no cycle)
local FurnitureSaveV2 = require(script.Parent:WaitForChild("FurnitureSaveV2")) -- step A split (no cycle)

local WELCOME_GIFT = table.freeze({ "FUR-01", "FUR-06" }) -- Straw Cot + Scribe's Desk (row 97)
local BANNER_ID = "FUR-22"
local PEDESTAL_ID = "FUR-21"
local PEDESTAL_RANK = 32

-- Approved text (guild_facilities 98).
local TXT_DUP = "You already have this piece out."
local TXT_LOCKED_RUN = "You can't change furniture during a battle or dungeon run."
local TXT_NO_SHOP = "Find furniture in the Dungeon, or craft it." -- FUR-NO-SHOP (guild_facilities 112, approved 8:07 PM)
-- Step 4b (USER APPROVAL 2026-11-16 11:02 PM, DRAFT_furnish_rooms_text_20261116.md lines 4-5):
local TXT_CRAFT_FULL = "Furniture storage is full (400)." -- FUR-CRAFT-FULL
local function txtStorageFull(piece: string): string
	return `Furniture storage is full (400). {piece} was left behind.` -- FUR-STORAGE-FULL
end
local TXT_ALREADY_OWNED = "Already owned" -- approved step-3 craft line (fixed pieces are once only, row 110)

type Deps = {
	getGuildHallLevel: (() -> number)?,
	getRank: (() -> number)?,
	getGold: (() -> number)?,
	spendGold: ((number) -> (boolean, string?))?,
	canChangeNow: (() -> boolean)?,
	canBuyNow: (() -> boolean)?,
	isPlayerUnit: ((any) -> boolean)?,
	rebuildAll: (() -> ())?,
	markDirty: (() -> ())?,
	getMaterials: (() -> { [string]: number })?,
	spendCost: (({ [string]: number }) -> (boolean, string?))?,
	isBuildingOpen: ((string) -> boolean)?,
}
local deps: Deps = {}

type Line = { kind: string, value: number, points: number, enemy: boolean?, threshold: boolean?, signature: boolean? }
type Inst = { uid: string, id: string, rarity: string, lines: { Line }, fixed: boolean?, looks: boolean?, src: string?, welcome: boolean? }

local instances: { [string]: Inst } = {}
local placement: { [string]: string } = {}   -- spotKey -> uid
local nextUid = 1
local noticePending = false
local convSeed = 0
local pendingPlace: { string }? = nil         -- old-save conversion: uids to place at Init (GH known)
local leftBehind: { string } = {}             -- step 4b (WARN-A): FUR-STORAGE-FULL lines not yet shown (not saved)
local imported = false                        -- step 4b: Import ran (old/existing save); else a new player

-- Computed.
local legacyBonus: { [string]: number } = {}
local legacyStatus: { [string]: string } = {} -- spotKey -> ok | capped | invalid
local legacyPoints = 0
local v4Totals: any = { player = {}, enemy = {}, fixed = {}, threshold = {}, points = 0, cap = 8, status = {}, lineStatus = {} }
local unitBonus: { [string]: number } = {} -- step 1: V4 player totals as unit.furnitureBonus keys

--------------------------------------------------
-- helpers
--------------------------------------------------

local function ghLevel(): number
	local l = deps.getGuildHallLevel and deps.getGuildHallLevel() or 1
	return math.clamp(math.floor(tonumber(l) or 1), 1, 10)
end

local function rank(): number
	local r = deps.getRank and deps.getRank() or 1
	return math.max(1, math.floor(tonumber(r) or 1))
end

local hash = FurnitureRoll.Hash

local function newUid(): string
	local u = "f" .. tostring(nextUid)
	nextUid += 1
	return u
end

type Spot = { key: string, room: string, roomName: string, wall: boolean, accepts: { string }? }

local spotsFor = FurnitureTotals.SpotsFor
local fits = FurnitureTotals.Fits

local function placedKey(uid: string): string?
	for k, u in placement do if u == uid then return k end end
	return nil
end

local SOURCE_KEY = FurnitureRoll.SOURCE_KEY

--- Roll one new instance of a piece (FurnitureRoll). forcedRarity (old-save conversion / dev) skips the rarity roll.
local function rollInstance(id: string, src: string, rng: Random, forcedRarity: string?): Inst?
	return FurnitureRoll.RollInstance(id, src, rng, forcedRarity, newUid, ghLevel)
end

local function recompute()
	local gh = ghLevel()
	legacyBonus, legacyStatus, legacyPoints = FurnitureTotals.RecomputeLegacy(gh, placement, instances)
	v4Totals = FurnitureTotals.RecomputeV4(gh, placement, instances)
	unitBonus = FurnitureTotals.BonusTable(v4Totals)
end

-- Row 110 (agent default, vetoable): the welcome Straw Cot + Scribe's Desk are FIXED at 8 points:
-- one player line, Common (Straw Cot +4 Max HP, Scribe's Desk +2 Max MP). Re-applied on every
-- load, so it is a data rule, not a re-roll.
local function normalizeWelcome(inst: Inst)
	local k = V4.WelcomeKinds[inst.id]
	if not (inst.welcome and k) then return end
	local price = V4.PointPrice[k]
	local pts = V4.WelcomePoints
	inst.rarity = "Common"
	inst.lines = { { kind = k, value = math.floor(pts / price), points = math.floor(pts / price) * price } }
end

local function changed()
	recompute()
	if deps.markDirty then deps.markDirty() end
	if deps.rebuildAll then
		local ok, err = pcall(deps.rebuildAll)
		if not ok then warn("[FurnitureService] rebuild failed: " .. tostring(err)) end
	end
end

--------------------------------------------------
-- placement
--------------------------------------------------

local function nameOut(inst: Inst, exceptUid: string?): boolean
	local p = V4.Get(inst.id)
	if p and p.category == "Bed" then return false end -- every bed counts (D5)
	for _, u in placement do
		local o = instances[u]
		if o and o.uid ~= inst.uid and o.uid ~= exceptUid and o.id == inst.id then return true end
	end
	return false
end

--- First free spot that fits, or nil. preferWall: try wall spots first.
local function firstFreeSpot(inst: Inst, gh: number): Spot?
	local floor, wall = spotsFor(gh)
	for _, list in { floor, wall } do
		for _, s in list do
			if placement[s.key] == nil and fits(inst, s) then return s end
		end
	end
	return nil
end

local function placeFirstFree(inst: Inst): boolean
	if placedKey(inst.uid) then return true end
	if nameOut(inst) then return false end
	local s = firstFreeSpot(inst, ghLevel())
	if not s then return false end
	placement[s.key] = inst.uid
	return true
end

local function addInstance(inst: Inst)
	instances[inst.uid] = inst
end

-- W2 fix (2026-11-16): compare uids by number ("f2" before "f10"), not as text.
local function uidNum(uid: string): number
	return tonumber(string.match(uid, "%d+") or "") or math.huge
end

local function firstInstanceOf(id: string, unplacedOnly: boolean): Inst?
	local best: Inst? = nil
	for _, inst in instances do
		if inst.id == id and (not unplacedOnly or placedKey(inst.uid) == nil) then
			if best == nil or uidNum(inst.uid) < uidNum(best.uid) then best = inst end
		end
	end
	return best
end

local function owns(id: string): boolean
	for _, inst in instances do if inst.id == id then return true end end
	return false
end

-- v5 step 3 save safety (agent default; Scrap / storage cap deferred by the user, row 111): no NEW piece
-- is created once the player owns GrantLimit (400) pieces. No approved "storage full" text exists, so the
-- piece is skipped with a warn() log only (never invent player text).
local function atGrantLimit(why: string): boolean
	local n = 0
	for _ in instances do n += 1 end
	if n < FurnitureSaveV2.GRANT_LIMIT then return false end
	warn(`[FurnitureService] {n} pieces owned (limit {FurnitureSaveV2.GRANT_LIMIT}): no new piece ({why})`)
	return true
end

--------------------------------------------------
-- grants (Pedestal at Rank 32, Banner at Guild Hall 10)
--------------------------------------------------

local function grantFixed(id: string, why: string): boolean
	if owns(id) then return false end
	local inst = rollInstance(id, "grant", Random.new(hash(id .. tostring(convSeed))), "Common")
	if not inst then return false end
	addInstance(inst)
	placeFirstFree(inst)
	print(`[FurnitureService] {why}`)
	return true
end

local function ensureGrants(): (boolean, boolean)
	local any, pedestalNow = false, false
	if rank() >= PEDESTAL_RANK and grantFixed(PEDESTAL_ID, `Trophy Pedestal granted (Renown Rank {PEDESTAL_RANK})`) then
		any, pedestalNow = true, true
	end
	if ghLevel() >= 10 and grantFixed(BANNER_ID, "Guild Banner granted (Guild Hall L10)") then any = true end
	return any, pedestalNow
end

-- W-C: drop placements whose room/spot is not open at this Guild Hall level, whose category
-- doesn't fit, or that break the one-per-name rule (beds exempt). The piece goes to storage
-- (stays owned); nothing is deleted.
local function validatePlacement(): number
	local gh = ghLevel()
	local floor, wall = spotsFor(gh)
	local byKey: { [string]: Spot } = {}
	for _, s in floor do byKey[s.key] = s end
	for _, s in wall do byKey[s.key] = s end
	local keys = {}
	for k in placement do table.insert(keys, k) end
	table.sort(keys)
	local seenName: { [string]: boolean } = {}
	local moved = 0
	for _, k in keys do
		local inst = instances[placement[k]]
		local s = byKey[k]
		local p = inst and V4.Get(inst.id)
		local ok = inst ~= nil and s ~= nil and p ~= nil and fits(inst, s)
		if ok and p and p.category ~= "Bed" then
			if seenName[p.id] then ok = false else seenName[p.id] = true end
		end
		if not ok then
			placement[k] = nil
			moved += 1
			print(`[FurnitureService] Saved spot {k} invalid -> {inst and inst.id or "?"} to storage`)
		end
	end
	return moved
end

local function runPendingPlacement()
	local list = pendingPlace
	if not list then return end
	pendingPlace = nil
	for _, uid in list do
		local inst = instances[uid]
		if inst and not placeFirstFree(inst) then
			print(`[FurnitureService] Conversion: {inst.id} {inst.rarity} -> storage (no fitting spot)`)
		end
	end
end

function FurnitureService.Init(d: Deps)
	deps = d
	local placedNow = pendingPlace ~= nil
	local moved = validatePlacement() -- W-C: saved spots checked against the real Guild Hall level
	if moved > 0 then placedNow = true end
	runPendingPlacement() -- old-save conversion places once the real Guild Hall level is known
	local granted = ensureGrants()
	if (placedNow or granted) and deps.markDirty then pcall(deps.markDirty) end
	recompute()
	if next(unitBonus) ~= nil and deps.rebuildAll then
		local ok, err = pcall(deps.rebuildAll)
		if not ok then warn("[FurnitureService] rebuild at Init failed: " .. tostring(err)) end
	end
	local n = 0
	for _ in instances do n += 1 end
	print(`[FurnitureService] Initialized | Guild Hall L{ghLevel()} | pieces {n} | bonus points {legacyPoints}/{FurnitureData.CapFor(ghLevel())} (legacy, unused) | v4 points {v4Totals.points}/{v4Totals.cap} (applied to units)`)
end

--------------------------------------------------
-- READ
--------------------------------------------------

--- Furniture bonus for one of the player's units (step 1: V4 player totals; nil = none / enemy).
function FurnitureService.BonusFor(unit: any): { [string]: number }?
	if type(unit) ~= "table" then return nil end
	-- v5 step 2 (gf 108): an enemy gets its battle-start weakening stamp (FurnitureEnemy), never player lines.
	if unit.side == "Enemy" then
		local fe = unit._furnEnemy
		if type(fe) == "table" and next(fe) ~= nil then return fe end
		return nil
	end
	if not (deps.isPlayerUnit and deps.isPlayerUnit(unit)) then return nil end
	if next(unitBonus) == nil then return nil end
	return unitBonus
end

-- Dispatch fee change (War Table -5g, fixed piece). Kept as-is (agent default 2026-11-16 9:05 PM).
function FurnitureService.DispatchFeeDelta(): number
	return math.floor(unitBonus.dispatchFee or 0)
end

--- V4 totals (computed only; steps 3 / 4 apply them).
function FurnitureService.V4Totals(): any
	return v4Totals
end

-- v5 step 3 (guild_facilities 95/99/105/109): the gold shop is retired; no rows are sent (the client hides
-- the Shop heading when the list is empty).
local function shopRows(): { any }
	return {}
end

local function instView(inst: Inst): any
	local lines = {}
	for _, l in inst.lines do
		table.insert(lines, { kind = l.kind, value = l.value, points = l.points, enemy = l.enemy, threshold = l.threshold, signature = l.signature })
	end
	return { uid = inst.uid, id = inst.id, rarity = inst.rarity, lines = lines, fixed = inst.fixed, looks = inst.looks, spot = placedKey(inst.uid) }
end

-- Step 4b (row 110): a NEW player (no save was imported) gets the welcome Straw Cot + Scribe's Desk once,
-- fixed 8 points, no old-save notice. Pieces are never deleted (no Scrap yet), so "nothing owned and nothing
-- imported" only happens on a fresh save. Runs from State(), which the client calls once the save is loaded.
local function ensureNewPlayerGift(): boolean
	if imported or next(instances) ~= nil then return false end
	imported = true -- once per session
	convSeed = hash("gift-new")
	local rng = Random.new(convSeed)
	for _, id in WELCOME_GIFT do
		local inst = rollInstance(id, "shop", rng, V4.Migration.CraftedDroppedBossGift)
		if inst then
			inst.welcome = true
			normalizeWelcome(inst)
			addInstance(inst)
			placeFirstFree(inst)
		end
	end
	print("[FurnitureService] New player: welcome gift Straw Cot + Scribe's Desk (fixed 8 points)")
	return true
end

function FurnitureService.State(): any
	local gifted = ensureNewPlayerGift()
	if ensureGrants() or gifted then changed() end
	local gh = ghLevel()
	local floor, wall = spotsFor(gh)
	local s, st, dc = {}, {}, {}
	for i, sp in floor do
		local u = placement[sp.key]
		s[i] = (u and instances[u] and instances[u].id) or false
		st[i] = v4Totals.status[sp.key] or "" -- step 1: V4 status (what units get)
	end
	for i, sp in wall do
		local u = placement[sp.key]
		dc[i] = (u and instances[u] and instances[u].id) or false
	end
	local ownedSet: { [string]: boolean } = {}
	local insts = {}
	for _, inst in instances do
		ownedSet[inst.id] = true
		table.insert(insts, instView(inst))
	end
	table.sort(insts, function(a, b) return a.uid < b.uid end)
	local ownedList = {}
	for id in ownedSet do table.insert(ownedList, id) end
	table.sort(ownedList)
	local spots = {}
	for _, list in { floor, wall } do
		for _, sp in list do
			local u = placement[sp.key]
			table.insert(spots, { key = sp.key, room = sp.room, roomName = sp.roomName, wall = sp.wall, accepts = sp.accepts,
				uid = u, status = v4Totals.status[sp.key] })
		end
	end
	return {
		-- old fields (UI until step 5)
		guildHallLevel = gh, slots = s, slotStatus = st, decor = dc,
		points = v4Totals.points, cap = v4Totals.cap, -- step 1: V4 points / cap (8 x GH)
		owned = ownedList, shop = shopRows(),
		locked = not (deps.canChangeNow and deps.canChangeNow()),
		notice = noticePending,
		leftBehind = table.clone(leftBehind), -- step 4b (WARN-A): FUR-STORAGE-FULL lines to show once
		pieceCount = #insts, grantLimit = FurnitureSaveV2.GRANT_LIMIT,
		-- v4 (step 2): rooms / spots / instances / totals (not applied yet)
		v4 = { spots = spots, instances = insts, totals = v4Totals },
	}
end

--------------------------------------------------
-- ACTIONS (SEC-001: the client sends ids / slot numbers only; the server checks + prices)
--------------------------------------------------

local function validSlot(n: any): number?
	if type(n) ~= "number" or n ~= n or n % 1 ~= 0 or n < 1 or n > 64 then return nil end
	return n
end

local function rngFor(tag: string): Random
	return Random.new(hash(tag .. ":" .. tostring(nextUid) .. ":" .. tostring(os.clock())))
end

-- FUR-NO-SPOT (row 98 v3 line 22): rooms (open at this Guild Hall level first) whose spots take this piece.
local function noSpotText(inst: Inst): string
	local p = V4.Get(inst.id)
	local names: { string } = {}
	for _, gh in { ghLevel(), 10 } do
		for _, r in V4.RoomsFor(gh) do
			local ok = false
			if p and p.category == "Wall" then ok = (r.wall or 0) > 0
			elseif p then for _, acc in r.floor do if table.find(acc, p.category) then ok = true end end end
			if ok and not table.find(names, r.name) then table.insert(names, r.name) end
		end
		if #names > 0 then break end
	end
	return `No free spot for this piece. It fits in: {table.concat(names, ", ")}.`
end

function FurnitureService.Buy(_id: any): (boolean, string?)
	-- v5 step 3 (guild_facilities 109): the gold shop is retired. Never charges gold.
	return false, TXT_NO_SHOP
end

--- Put a piece into a spot. id = instance uid or piece id (first unplaced copy). slot = index in
--- the floor list (isDecor false) or wall list (isDecor true). If the spot doesn't fit the piece,
--- the first free fitting spot is used instead (keeps the step-1 UI working).
function FurnitureService.Place(id: any, slot: any, isDecor: any): (boolean, string?)
	if not (deps.canChangeNow and deps.canChangeNow()) then return false, TXT_LOCKED_RUN end
	if type(id) ~= "string" then return false, "Unknown piece" end
	local inst = instances[id] or firstInstanceOf(id, true) or firstInstanceOf(id, false)
	if not inst then return false, "Unknown piece" end
	local floor, wall = spotsFor(ghLevel())
	local target: Spot? = nil
	if type(slot) == "string" then
		-- step 4b rooms screen: a spot key ("Room/f1") or "auto" (first free spot that fits)
		if slot ~= "auto" then
			for _, l2 in { floor, wall } do
				for _, sp in l2 do if sp.key == slot then target = sp end end
			end
			if target == nil then return false, "Unknown slot" end
		end
	else
		local n = validSlot(slot)
		if not n then return false, "Unknown slot" end
		target = (if isDecor == true then wall else floor)[n]
	end
	if target == nil or not fits(inst, target) then
		if placedKey(inst.uid) then return true, nil end -- already out and the asked spot doesn't fit: keep it
		target = nil
		for _, l2 in { floor, wall } do
			for _, s in l2 do
				if placement[s.key] == nil and fits(inst, s) then target = s break end
			end
			if target then break end
		end
	end
	if not target then return false, noSpotText(inst) end
	local cur = placedKey(inst.uid)
	if cur == target.key then return true, nil end
	if nameOut(inst, placement[target.key]) and not cur then return false, TXT_DUP end -- swapping the same name in one spot is fine
	if cur then placement[cur] = nil end
	placement[target.key] = inst.uid -- replaces what was there (that piece goes to storage)
	changed()
	return true, nil
end

function FurnitureService.Remove(slot: any, isDecor: any): (boolean, string?)
	if not (deps.canChangeNow and deps.canChangeNow()) then return false, TXT_LOCKED_RUN end
	local floor, wall = spotsFor(ghLevel())
	local key: string? = nil
	if type(slot) == "string" then
		key = slot
	else
		local n = validSlot(slot)
		if not n then return false, "Unknown slot" end
		local sp = (if isDecor == true then wall else floor)[n]
		key = sp and sp.key or nil
	end
	if not key then return false, "Unknown slot" end
	placement[key] = nil
	changed()
	return true, nil
end

--------------------------------------------------
-- STEP 3 flows (crafting, drops, rank rewards) now create rolled instances
--------------------------------------------------

local function matName(k: string, n: number): string
	if k == "mercury" then return "Mercury" end
	if k == "crystals" then return if n == 1 then "Crystal" else "Crystals" end
	return k
end

function FurnitureService.Owns(id: any): boolean
	return type(id) == "string" and owns(id)
end

--- v5 step 3 (guild_facilities 109): a piece that came home from the Dungeon (DungeonFurniture.OnRunEnd).
--- entry = a rolled run piece { id, r, l, st, b } (rolled in the run; re-checked here, gets a new uid).
--- An old in-progress run's plain piece id (saved before step 3) is rolled now with the stage-1 Elite
--- weights (plan OPEN-2, agent default). Duplicates allowed; extra copies go to storage.
function FurnitureService.GrantDrop(entry: any, why: string?): boolean
	if atGrantLimit(tostring(why)) then
		-- step 4b (WARN-A): tell the player once (shown by the Guild menu on return to base / Furnish tab)
		local eid = if type(entry) == "table" then entry.id else entry
		local ep = V4.Get(eid)
		if ep and #leftBehind < 20 then table.insert(leftBehind, txtStorageFull(ep.name)) end
		return false
	end
	local inst: Inst? = nil
	if type(entry) == "table" and type(entry.l) == "table" then
		local id, rar, lines = FurnitureSaveV2.CleanEntry(entry)
		local p = id and V4.Get(id)
		if not (id and rar and lines and p) then return false end
		inst = { uid = newUid(), id = id, rarity = rar, lines = lines, src = if entry.b then "boss" else "dungeon",
			fixed = if p.fixed then true else nil, looks = if p.looksOnly then true else nil }
	else
		local id = if type(entry) == "table" then entry.id else entry
		if not V4.Get(id) then return false end
		local w = V4.Sources.EliteWeights
		local rng = rngFor("drop" .. tostring(id))
		local rar = FurnitureRoll.RollRarityFrom(rng, { Common = w.Common, Uncommon = w.Uncommon, Rare = w.Rare + w.Epic }, ghLevel(), V4.Get(id).rarityStepBonus)
		inst = rollInstance(id, "dungeon", rng, rar)
	end
	if not inst then return false end
	addInstance(inst)
	if not inst.looks and deps.canChangeNow and deps.canChangeNow() then placeFirstFree(inst) end
	local p = V4.Get(inst.id)
	print(`[FurnitureService] Drop granted | {inst.id} {p and p.name or "?"} ({inst.rarity}) | {tostring(why)}`)
	changed()
	return true
end

--- Retired by v5 (loot_progression 15 / guild_facilities 109): quest bosses no longer drop furniture.
function FurnitureService.RollBossPiece(_chance: number): string?
	return nil
end

--- Guild Hall level (v5 step 3: DungeonFurniture rolls run pieces with the real Guild Hall gates).
function FurnitureService.GuildHallLevel(): number
	return ghLevel()
end

function FurnitureService.GrantRankRewards(): boolean
	local any, pedestalNow = ensureGrants()
	if any then changed() end
	return pedestalNow
end

-- v5 crafting (guild_facilities 110, build step 4b): one recipe per rolled type + the fixed pieces that lost
-- their shop (V4.Craft). Rolled pieces are repeatable (gold sink), rarity Common 40 / Uncommon 43 / Rare 17,
-- capped at Rare, Guild Hall gates apply (Oak Bed +1 step first, then the Rare cap). Fixed pieces: once only.
local CRAFT_RARE_IDX = table.find(V4.RarityOrder, V4.Craft.MaxRarity) or 3

local function recipeFor(id: any, building: any): any?
	if type(id) ~= "string" or type(building) ~= "string" then return nil end
	for _, r in (V4.Craft.Recipes[building] or {}) do
		if r.id == id then return r end
	end
	return nil
end

local function grantCount(): number
	local n = 0
	for _ in instances do n += 1 end
	return n
end

local function craftReason(r: any): string?
	if r.once and owns(r.id) then return TXT_ALREADY_OWNED end
	if not (deps.canChangeNow and deps.canChangeNow()) then return TXT_LOCKED_RUN end
	if grantCount() >= FurnitureSaveV2.GRANT_LIMIT then return TXT_CRAFT_FULL end -- step 4b (WARN-B)
	local gold = deps.getGold and deps.getGold() or 0
	if gold < r.gold then return `Not enough gold ({gold} / {r.gold})` end
	local have = deps.getMaterials and deps.getMaterials() or {}
	local h = tonumber(have.mercury) or 0
	if (r.mercury or 0) > 0 and h < r.mercury then return `Not enough {matName("mercury", r.mercury)} ({h} / {r.mercury})` end
	return nil
end

function FurnitureService.CraftRows(building: any): { any }
	local rows = {}
	if type(building) ~= "string" then return rows end
	for _, r in (V4.Craft.Recipes[building] or {}) do
		local p = V4.Get(r.id)
		local old = FurnitureData.Get(r.id)
		if p then
			local reason = craftReason(r)
			local text = if p.fixed then (old and old.text or "") else "Rarity is random (up to Rare)." -- FUR-CRAFT-RANDOM
			table.insert(rows, { id = r.id, name = p.name, text = text, price = r.gold,
				matName = if (r.mercury or 0) > 0 then matName("mercury", r.mercury) else nil, matN = r.mercury,
				owned = r.once == true and owns(r.id), canCraft = reason == nil, reason = reason })
		end
	end
	return rows
end

function FurnitureService.Craft(id: any, building: any): (boolean, string?)
	local r = recipeFor(id, building)
	local p = r and V4.Get(r.id)
	if not (r and p) then return false, "Unknown piece" end
	if not (deps.isBuildingOpen and deps.isBuildingOpen(building)) then return false, "Unknown piece" end
	local why = craftReason(r)
	if why then return false, why end -- includes FUR-CRAFT-FULL at 400, checked before anything is charged
	if not deps.spendCost then return false, "Gold unavailable" end
	local cost: { [string]: number } = { gold = r.gold }
	if (r.mercury or 0) > 0 then cost.mercury = r.mercury end
	local okPay, err = deps.spendCost(cost)
	if not okPay then return false, tostring(err or "Not enough gold") end
	local rng = rngFor("craft" .. r.id)
	local rar: string? = nil
	if not (p.fixed or p.looksOnly) then
		rar = FurnitureRoll.RollRarityFrom(rng, V4.Craft.Weights, ghLevel(), p.rarityStepBonus)
		local idx = table.find(V4.RarityOrder, rar) or 1
		if idx > CRAFT_RARE_IDX then rar = V4.RarityOrder[CRAFT_RARE_IDX] end -- Rare cap (row 110)
	end
	local inst = rollInstance(r.id, "craft", rng, rar)
	if not inst then return false, "Unknown piece" end
	addInstance(inst)
	if not inst.looks then placeFirstFree(inst) end
	print(`[FurnitureService] Crafted {r.id} {p.name} ({inst.rarity}) at {building} | {r.gold} gold + {r.mercury or 0} mercury`)
	changed()
	if inst.fixed then return true, `{p.name} crafted! It's in your Guild Hall.` end -- approved step-3 line 4
	return true, `{inst.rarity} {p.name} crafted! It's in your Guild Hall.` -- FUR-CRAFTED-RARITY (v3 line 10)
end

-- Step 4b (WARN-A): FUR-STORAGE-FULL lines waiting to be shown; AckLeftBehind clears them.
function FurnitureService.AckLeftBehind()
	table.clear(leftBehind)
end

function FurnitureService.ClearNotice()
	if noticePending then
		noticePending = false
		if deps.markDirty then deps.markDirty() end
	end
end

function FurnitureService.OnGuildHallChanged()
	ensureGrants()
	changed()
end

--------------------------------------------------
-- SAVE (format v2) + old-save conversion
--------------------------------------------------

function FurnitureService.Export(): any
	return FurnitureSaveV2.Export(instances, placement, nextUid, noticePending, convSeed)
end


-- Old v1 save -> v2 (row 97 / V4.Migration): every owned piece -> one instance of the same type,
-- rolled once with a fixed seed per save (never re-rolls). Shop-bought -> Common; crafted /
-- dropped / boss / welcome gift -> Uncommon. Fixed and looks-only pieces stay as they are.
-- Placement happens at Init (needs the real Guild Hall level): old slots first, then decor,
-- each into the first free spot that fits; everything else to storage. Nothing is lost.
local function convertV1(data: any)
	local ids: { string } = {}
	local seenId: { [string]: boolean } = {}
	for _, id in (type(data.owned) == "table" and data.owned or {}) do
		if type(id) == "string" and V4.Get(id) and not seenId[id] then table.insert(ids, id) seenId[id] = true end
	end
	table.sort(ids)
	convSeed = hash("conv:" .. table.concat(ids, ","))
	local rng = Random.new(convSeed)
	local byId: { [string]: string } = {}
	for _, id in ids do
		local p = V4.Get(id)
		local rar: string = V4.Migration.ShopBought
		if p.source ~= "Shop" or table.find(WELCOME_GIFT, id) then rar = V4.Migration.CraftedDroppedBossGift end
		local inst = rollInstance(id, SOURCE_KEY[p.source] or "shop", rng, rar)
		if inst and table.find(WELCOME_GIFT, id) then inst.welcome = true end -- W-G: owned Cot / Desk = the gift
		if inst then
			addInstance(inst)
			byId[id] = inst.uid
		end
	end
	local order: { string } = {}
	local queued: { [string]: boolean } = {}
	for _, list in { data.slots, data.decor } do
		for _, id in (type(list) == "table" and list or {}) do
			local u = type(id) == "string" and byId[id] or nil
			if u and not queued[u] then table.insert(order, u) queued[u] = true end
		end
	end
	pendingPlace = order
	noticePending = data.notice == true
	print(`[FurnitureService] Old save converted to v2: {#ids} piece(s), {#order} to place at Init`)
end

function FurnitureService.Import(data: any, saveExisted: boolean?)
	instances, placement, nextUid, noticePending, convSeed, pendingPlace = {}, {}, 1, false, 0, nil
	imported = true -- step 4b: an existing save (gift handled below); a new player never calls Import
	if type(data) == "table" and data.v == FurnitureSaveV2.VERSION then
		nextUid, noticePending, convSeed = FurnitureSaveV2.ImportV2(data, instances, placement)
		if data.wv ~= 1 then
			-- v2 saves written before step 1 carry no welcome flag: the lowest-uid Straw Cot and
			-- Scribe's Desk are the welcome gift (same W-G rule as the v1 conversion).
			for _, wid in WELCOME_GIFT do
				local w = firstInstanceOf(wid, false)
				if w then w.welcome = true end
			end
		end
	elseif type(data) == "table" then
		convertV1(data)
	elseif saveExisted then
		convSeed = hash("gift")
		local rng = Random.new(convSeed)
		local order = {}
		for _, id in WELCOME_GIFT do
			local inst = rollInstance(id, "shop", rng, V4.Migration.CraftedDroppedBossGift)
			if inst then inst.welcome = true addInstance(inst) table.insert(order, inst.uid) end
		end
		pendingPlace = order
		noticePending = true
		print("[FurnitureService] Old save: welcome gift Straw Cot + Scribe's Desk (fixed 8 points), notice pending")
	end
	for _, inst in instances do normalizeWelcome(inst) end
	recompute()
end

-- Dev only (Main DevDungeon op "furn", memory-mode saves only).
function FurnitureService.DevSetOwned(id: any, own: boolean): boolean
	if type(id) ~= "string" or not V4.Get(id) then return false end
	if own then
		if atGrantLimit("dev " .. id) then return false end
		local inst = rollInstance(id, "dungeon", rngFor("dev" .. id))
		if not inst then return false end
		addInstance(inst)
		placeFirstFree(inst)
	else
		for u, inst in instances do
			if inst.id == id then
				local k = placedKey(u)
				if k then placement[k] = nil end
				instances[u] = nil
			end
		end
	end
	changed()
	return true
end

return FurnitureService
