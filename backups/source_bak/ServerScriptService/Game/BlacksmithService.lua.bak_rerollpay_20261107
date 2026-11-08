--!strict
-- BlacksmithService.lua
-- CTRBLXAI | Slice 6 — Base Management (Batch 1 of 3)
--
-- OWNS (per service_boundaries 'Blacksmith Service'):
--   Equipment level upgrade/downgrade transactions and each item's levelling record
--   (v2, LOCKED USER DECISION 2026-11-01).
--
-- READS:
--   Target item, upgrade gold formula (economy_framework 19), 1 mercury per level
--   (materials_system 2/20), the Blacksmith level (gold discount), player gold/mercury.
--
-- WRITES:
--   Modified item handed back to persistence; gold + mercury debited in ONE atomic charge.
--
-- MUST NOT OWN:
--   New item generation, loot tables, combat.
--
-- PRIMARY INTERFACE:
--   ResolveUpgradeCost(item, targetLevel), GetUpgradeCurve(item, maxLevel)
--   ValidateUpgrade(playerId, item, targetLevel)
--   CommitUpgrade(playerId, item, targetLevel)
--   CommitDowngrade(playerId, item, targetLevel)
--   ResolveDismantle(item), CommitDismantle(playerId, item)   (v2 build step 2)
--
-- FAILURE BOUNDARY:
--   Atomic — gold + mercury charged ONLY on success. Downgrade is FREE and unlimited
--   (nothing refunded). NEVER creates a new item: it mutates itemLevel on the existing
--   instance and preserves the authored rolls.
--
-- ─────────────────────────────────────────────────────────────────────────
-- LOCKED DATA — copied verbatim from CTRBLXAI.db. Do NOT invent or tune here.
-- ─────────────────────────────────────────────────────────────────────────
--
--   economy_framework 19 (v2): gold per level = Base Value × Rarity Mult × 0.30 ×
--     (1 + Target Level / 25) × (1 − 0.03 × (Blacksmith Level − 1)), rounded down on a
--     RUNNING TOTAL (guild_facilities 48), plus 1 mercury per level for every rarity.
--   economy_framework 11 (Base Value by Slot): 1H=100, 2H=150, Off-Hand=60, Body=80,
--     Head=60, Gloves=50, Feet=50, Accessory=70.
--   economy_framework 12 (Rarity Multiplier): Common 1.0, Uncommon 1.5, Rare 2.5,
--     Epic 4.0, Exalted 5.5, Legendary 7.0, Mythic 12.0, Transcendent 20.0, Unique 15.0.
--   economy_framework 21 / guild_facilities 47 (Downgrade): free and unlimited; the
--     dropped levels' levelling credit and mercury are lost (re-upgrading pays again).
--
--   guild_facilities 51 (Dismantle Output, v2): destroys the item, NO gold, no randomness,
--     Fortune never applies. Mercury = ceil(item level / 10). By CURRENT rarity, crystals /
--     sulfur: Common 0/0, Uncommon 1/0, Rare 2/0, Epic 3/0, Exalted 4/1, Legendary 6/2,
--     Mythic 8/3, Transcendent 10/4, Unique 10/3. Rune gems: 1 per bonus line (numeric
--     lines and bonus passives), none from Unique items. A numeric line above T4 becomes
--     the same family's T4 gem; a passive whose minimum rarity is above Epic gives no gem.
--     The base item's native passive is not a bonus line. Rune-forged items are treated
--     exactly like any other item (USER DECISION 2026-11-01).
--   guild_facilities 52 (Dismantle Limits) are enforced by the caller (GuildMenuService:
--     equipped / staged items); this service only refuses unknown rarities.
--
--   item_rarity_rules: an upgrade changes ONLY itemLevel; the rarity Bonus BP budget and
--     the authored bonus lines are level-invariant (never re-rolled).
--
-- DEPENDENCIES ARE INJECTED (dependency injection) to avoid circular requires
-- and to not hard-couple to the (not-yet-built) currency/material layer.

local BlacksmithService = {}

--------------------------------------------------
-- LOCKED CONSTANTS (mirror of DB — see header)
--------------------------------------------------

-- economy_framework id=11 — Base Value by Slot
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

-- economy_framework 12 — Rarity Multiplier, held as WHOLE numbers R = multiplier × 10
-- (guild_facilities 48) so every gold sum is exact integer maths (implementation_plan 53).
-- Keyed by rarity NAME string, which is how item.rarityId is stored by ItemGenerator.
local RARITY_R = table.freeze({
	Common       = 10,
	Uncommon     = 15,
	Rare         = 25,
	Epic         = 40,
	Exalted      = 55,
	Legendary    = 70,
	Mythic       = 120,
	Transcendent = 200,
	Unique       = 150,
})

local PAID_DIVISOR = 250000      -- guild_facilities 48: Paid(C, R) = floor(C × R / 250,000)
local MERCURY_PER_LEVEL = 1      -- materials_system 2/20: every rarity
local MAX_BLACKSMITH_LEVEL = 10

-- guild_facilities 51 — dismantle yield by CURRENT rarity.
local DISMANTLE_CRYSTALS = table.freeze({
	Common = 0, Uncommon = 1, Rare = 2, Epic = 3, Exalted = 4,
	Legendary = 6, Mythic = 8, Transcendent = 10, Unique = 10,
})
local DISMANTLE_SULFUR = table.freeze({
	Common = 0, Uncommon = 0, Rare = 0, Epic = 0, Exalted = 1,
	Legendary = 2, Mythic = 3, Transcendent = 4, Unique = 3,
})
local GEM_MAX_TIER = 4               -- Epic-allowed tier (materials_system 4/40)
local GEM_MAX_RARITY = "Epic"        -- passives above this give no gem
local ABOVE_EPIC = table.freeze({ Exalted = true, Legendary = true, Mythic = true, Transcendent = true })
local MAX_ITEM_LEVEL = 99        -- unit/level cap (unit_progression id=48)
local MIN_ITEM_LEVEL = 1

--------------------------------------------------
-- INJECTED DEPENDENCIES
--------------------------------------------------

local _equipmentService: any = nil   -- DetermineSlot(item), Is2HEquipped (not used here)
local _weaponData: any = nil         -- GetByArchetypeId(id)
local _armorData: any = nil          -- GetByArchetypeId(id)
local _currency: any = nil           -- CurrencyService.AsProvider(): GetGold / CanAfford / Debit
local _blacksmithLevel: any = nil    -- () -> Blacksmith building level (gold discount)
local _inventory: any = nil          -- InventoryService: GetItem / RemoveItem (dismantle)
local _bonusData: any = nil          -- BonusData content: GetAttribute / GetPassive / GetFamilyTiers / RARITY_ORDER
local _persistItem: any = nil        -- function(playerId, item) -> hand modified item back

function BlacksmithService.SetEquipmentService(svc: any) _equipmentService = svc end
function BlacksmithService.SetWeaponData(d: any) _weaponData = d end
function BlacksmithService.SetArmorData(d: any) _armorData = d end
function BlacksmithService.SetCurrencyProvider(svc: any) _currency = svc end
function BlacksmithService.SetItemPersist(fn: any) _persistItem = fn end
function BlacksmithService.SetBlacksmithLevelProvider(fn: any) _blacksmithLevel = fn end
function BlacksmithService.SetInventoryService(svc: any) _inventory = svc end
function BlacksmithService.SetBonusData(d: any) _bonusData = d end

--------------------------------------------------
-- CURRENCY NOTE
--
-- The injected currency provider (CurrencyService.AsProvider) must offer GetGold,
-- CanAfford, Debit and (for dismantling) Credit. If none is injected, Validate reports blocked and Commit
-- refuses — it NEVER upgrades for free. With no Blacksmith level provider the
-- discount is 0% (Blacksmith L1).
--------------------------------------------------

--------------------------------------------------
-- SLOT / BASE VALUE RESOLUTION
--------------------------------------------------

local function resolveSlotKey(item: any): string?
	-- Prefer the injected EquipmentService slot determination (single source).
	local slot
	if _equipmentService and _equipmentService.DetermineSlot then
		slot = _equipmentService.DetermineSlot(item)
	end

	-- Weapons: distinguish 1H vs 2H vs Off-Hand for base value.
	if _weaponData and _weaponData.GetByArchetypeId then
		local wArch = _weaponData.GetByArchetypeId(item.baseArchetypeId)
		if wArch then
			if wArch.category == "OffHand" then
				return "OffHand"
			end
			-- WeaponData marks two-handed weapons with handClass = "2H" (BUG-073, 2026-11-01:
			-- this used to read fields WeaponData never had, so every 2H weapon was priced as 1H).
			if wArch.handClass == "2H" then
				return "MainHand2H"
			end
			return "MainHand1H"
		end
	end

	-- Armor: slot name maps directly to a base-value key.
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

--------------------------------------------------
-- LEVELLING RECORD + CREDIT (equipment_schema 20, guild_facilities 47-48 — v2)
--
-- item.levellingRecord = { free = F, pairs = { { hi, b }, ... } }
--   F    = the level the item arrived at (never paid for; old items = their level).
--   pair = levels (previous hi, or F) + 1 .. hi were bought at Blacksmith level b.
-- Credit of one bought level t at Blacksmith level b:
--   slotValue × 3 × (25 + t) × (100 − 3 × (b − 1))
-- Gold that a credit C is worth at rarity R (multiplier × 10):
--   Paid(C, R) = floor(C × R / 250,000)
-- Upgrade gold = Paid(C_new, R) − Paid(C_old, R): a running total, so a multi-level
-- upgrade and +1 steps cost exactly the same (economy_framework 19). The Runeforge
-- catch-up reads the same credit (build step 4).
--------------------------------------------------

local function currentBlacksmithLevel(): number
	local lvl = if _blacksmithLevel then tonumber(_blacksmithLevel()) else nil
	return math.clamp(math.floor(lvl or 1), 1, MAX_BLACKSMITH_LEVEL)
end

local function levelCredit(base: number, t: number, b: number): number
	return base * 3 * (25 + t) * (100 - 3 * (b - 1))
end

local function paid(credit: number, r: number): number
	return math.floor(credit * r / PAID_DIVISOR)
end

-- The item's record. Creates the default (arrived at its current level) when missing,
-- and resets it with a warning if it no longer ends at the item's level.
local function recordOf(item: any): any
	local rec = item.levellingRecord
	if type(rec) ~= "table" or type(rec.free) ~= "number" or type(rec.pairs) ~= "table" then
		rec = { free = item.itemLevel, pairs = {} }
		item.levellingRecord = rec
		return rec
	end
	local last = rec.pairs[#rec.pairs]
	local top = if last then last[1] else rec.free
	if top ~= item.itemLevel then
		warn(`[BlacksmithService] Levelling record of {tostring(item.instanceId)} ends at L{tostring(top)} but the item is L{tostring(item.itemLevel)} -- reset (levelling credit 0)`)
		rec = { free = item.itemLevel, pairs = {} }
		item.levellingRecord = rec
	end
	return rec
end

local function creditOf(item: any, base: number): number
	local rec = recordOf(item)
	local credit = 0
	local prev = rec.free
	for _, pr in rec.pairs do
		for t = prev + 1, pr[1] do
			credit += levelCredit(base, t, pr[2])
		end
		prev = pr[1]
	end
	return credit
end

-- Runeforge helpers (v2 build step 4): the item's slot value, and the levelling catch-up
-- when the Runeforge raises its rarity (guild_facilities 48: Paid(C, R_new) - Paid(C, R_old),
-- no discount). nil when the slot or a rarity is unknown.
function BlacksmithService.GetBaseValue(item: any): number?
	return baseValueOf(item)
end

function BlacksmithService.CatchUpGold(item: any, fromRarity: string, toRarity: string): number?
	local base = baseValueOf(item)
	local r1, r2 = RARITY_R[fromRarity], RARITY_R[toRarity]
	if not base or not r1 or not r2 then return nil end
	local credit = creditOf(item, base)
	return paid(credit, r2) - paid(credit, r1)
end

--------------------------------------------------
-- COST RESOLUTION
-- Returns: { gold = n, mercury = n, blacksmithLevel = b } or nil + err.
--------------------------------------------------

function BlacksmithService.ResolveUpgradeCost(item: any, targetLevel: number)
	if type(item) ~= "table" or type(item.itemLevel) ~= "number" then
		return nil, "Invalid item"
	end
	if type(targetLevel) ~= "number" or targetLevel <= item.itemLevel then
		return nil, "Target level must be above current level"
	end
	if targetLevel > MAX_ITEM_LEVEL then
		return nil, "Target level exceeds max (" .. MAX_ITEM_LEVEL .. ")"
	end

	local base = baseValueOf(item)
	if not base then
		return nil, "Could not resolve item base value (unknown archetype/slot)"
	end
	local r = RARITY_R[item.rarityId]
	if not r then
		return nil, "Unknown rarity: " .. tostring(item.rarityId)
	end

	local target = math.floor(targetLevel)
	local b = currentBlacksmithLevel()
	local before = creditOf(item, base)
	local after = before
	for t = item.itemLevel + 1, target do
		after += levelCredit(base, t, b)
	end
	return {
		gold = paid(after, r) - paid(before, r),
		mercury = (target - item.itemLevel) * MERCURY_PER_LEVEL,
		blacksmithLevel = b,
	}
end

-- GetUpgradeCurve: per-level INCREMENTAL cost from the item's current level up to
-- maxLevel, so the client can show a running total while staging several levels.
-- Each entry is { toLevel, gold, mercury }. Summing the first N entries equals exactly
-- what the server charges to reach current+N (the staged commit goes +1 at a time and
-- the gold is a running total).
function BlacksmithService.GetUpgradeCurve(item: any, maxLevel: number)
	if type(item) ~= "table" or type(item.itemLevel) ~= "number" then return {} end
	local cap = math.min(math.floor(tonumber(maxLevel) or 0), MAX_ITEM_LEVEL)
	local curve = {}
	local prevGold = 0
	for lvl = item.itemLevel + 1, cap do
		local c = BlacksmithService.ResolveUpgradeCost(item, lvl)
		if not c then break end
		table.insert(curve, { toLevel = lvl, gold = c.gold - prevGold, mercury = MERCURY_PER_LEVEL })
		prevGold = c.gold
	end
	return curve
end

--------------------------------------------------
-- PRIMARY INTERFACE: ValidateUpgrade
-- Returns: ok(boolean), reason(string|nil), cost(table|nil). Charges NOTHING.
--------------------------------------------------

function BlacksmithService.ValidateUpgrade(playerId: string, item: any, targetLevel: number)
	local cost, err = BlacksmithService.ResolveUpgradeCost(item, targetLevel)
	if not cost then
		return false, err, nil
	end
	if not (_currency and _currency.CanAfford and _currency.GetGold) then
		return false, "Currency unavailable (no store wired)", cost
	end
	if not _currency.CanAfford(playerId, { gold = cost.gold, mercury = cost.mercury }) then
		if (_currency.GetGold(playerId) or 0) < cost.gold then
			return false, "Insufficient gold", cost
		end
		return false, "Not enough mercury", cost
	end
	return true, nil, cost
end

--------------------------------------------------
-- PRIMARY INTERFACE: CommitUpgrade
-- One atomic charge (gold + mercury), then the level change and the levelling record
-- on the EXISTING instance (never re-rolls, never creates a new item).
-- Returns: ok(boolean), result(table|string)
--------------------------------------------------

function BlacksmithService.CommitUpgrade(playerId: string, item: any, targetLevel: number)
	local ok, reason, cost = BlacksmithService.ValidateUpgrade(playerId, item, targetLevel)
	if not ok or not cost then
		print(string.format("[BlacksmithService] Upgrade REJECTED | %s | (nothing charged)", tostring(reason)))
		return false, reason or "Upgrade rejected"
	end
	if not (_currency and _currency.Debit) then
		return false, "Currency spend path not wired"
	end

	local charged, why = _currency.Debit(playerId, { gold = cost.gold, mercury = cost.mercury })
	if not charged then
		return false, `{tostring(why or "Payment failed")} -- nothing charged`
	end

	local prevLevel = item.itemLevel
	local newLevel = math.clamp(math.floor(targetLevel), MIN_ITEM_LEVEL, MAX_ITEM_LEVEL)
	-- Record the Blacksmith level these levels were bought at (guild_facilities 48).
	local rec = recordOf(item)
	local last = rec.pairs[#rec.pairs]
	if last and last[2] == cost.blacksmithLevel then
		last[1] = newLevel
	else
		table.insert(rec.pairs, { newLevel, cost.blacksmithLevel })
	end
	item.itemLevel = newLevel

	if _persistItem then
		_persistItem(playerId, item)
	end

	print(string.format("[BlacksmithService] UPGRADED %s L%d->L%d | %dg + %d mercury (Blacksmith L%d)",
		tostring(item.instanceId), prevLevel, item.itemLevel, cost.gold, cost.mercury, cost.blacksmithLevel))

	return true, { instanceId = item.instanceId, fromLevel = prevLevel, toLevel = item.itemLevel, cost = cost }
end

--------------------------------------------------
-- PRIMARY INTERFACE: CommitDowngrade  (economy_framework 21, guild_facilities 47 — FREE)
--
-- Free and unlimited; nothing is refunded. The item loses the levelling credit of the
-- dropped levels: record pairs above the new level are removed, the pair covering it is
-- cut to end there, and the arrival level F drops with it if needed. Re-upgrading pays
-- full price again.
-- Returns: ok(boolean), result(table|string)
--------------------------------------------------

function BlacksmithService.CommitDowngrade(playerId: string, item: any, targetLevel: number)
	if type(item) ~= "table" or type(item.itemLevel) ~= "number" then
		return false, "Invalid item"
	end
	if type(targetLevel) ~= "number" or targetLevel >= item.itemLevel then
		return false, "Downgrade target must be below current level"
	end
	if targetLevel < MIN_ITEM_LEVEL then
		return false, "Target level below minimum (" .. MIN_ITEM_LEVEL .. ")"
	end

	local newLevel = math.floor(targetLevel)
	local rec = recordOf(item)
	local kept = {}
	local prev = rec.free
	for _, pr in rec.pairs do
		if pr[1] <= newLevel then
			table.insert(kept, pr)
			prev = pr[1]
		else
			if prev < newLevel then
				table.insert(kept, { newLevel, pr[2] })
			end
			break
		end
	end
	rec.pairs = kept
	if newLevel < rec.free then
		rec.free = newLevel
	end

	local prevLevel = item.itemLevel
	item.itemLevel = newLevel

	if _persistItem then
		_persistItem(playerId, item)
	end

	print(string.format("[BlacksmithService] DOWNGRADED %s L%d->L%d | FREE (nothing refunded; levelling credit of the dropped levels lost)",
		tostring(item.instanceId), prevLevel, item.itemLevel))

	return true, { instanceId = item.instanceId, fromLevel = prevLevel, toLevel = item.itemLevel, cost = { gold = 0, mercury = 0 } }
end

--------------------------------------------------
-- DISMANTLE (guild_facilities 51-52, materials_system 4/40 — v2 build step 2)
--------------------------------------------------

-- Rune gem for one numeric bonus line: the line's own attribute ID, or for a tier above
-- T4 the same family's T4 ID (the Epic cap). Returns gemId, wasCapped.
local function numericGem(lineId: string): (string?, boolean)
	local attr = _bonusData.GetAttribute(lineId)
	if not attr then
		return nil, false
	end
	if (attr.tier or 0) <= GEM_MAX_TIER then
		return lineId, false
	end
	local bestId, bestTier = nil, 0
	for _, t in _bonusData.GetFamilyTiers(attr.family) do
		if t.tier <= GEM_MAX_TIER and t.tier > bestTier then
			bestId, bestTier = t.id, t.tier
		end
	end
	return bestId, bestId ~= nil
end

-- What dismantling this item would give. Read-only; charges and changes nothing.
-- Returns { mercury, crystals, sulfur, gems = { [gemId] = n }, gemCount, cappedLines,
--           lostPassives = { name }, unknownLines, aboveEpic, unique } or nil + reason.
function BlacksmithService.ResolveDismantle(item: any)
	if type(item) ~= "table" or type(item.itemLevel) ~= "number" then
		return nil, "Invalid item"
	end
	local rarity = item.rarityId
	if DISMANTLE_CRYSTALS[rarity] == nil then
		return nil, "Unknown rarity: " .. tostring(rarity)
	end
	if not _bonusData then
		return nil, "Bonus data not wired"
	end

	local level = math.clamp(math.floor(item.itemLevel), MIN_ITEM_LEVEL, MAX_ITEM_LEVEL)
	local result = {
		mercury = math.ceil(level / 10),
		crystals = DISMANTLE_CRYSTALS[rarity],
		sulfur = DISMANTLE_SULFUR[rarity],
		gems = {} :: { [string]: number },
		gemCount = 0,
		cappedLines = 0,
		lostPassives = {} :: { string },
		unknownLines = 0,
		aboveEpic = ABOVE_EPIC[rarity] == true,
		unique = rarity == "Unique",
	}
	if result.unique then
		return result -- Unique items give no rune gems
	end

	local function addGem(id: string)
		result.gems[id] = (result.gems[id] or 0) + 1
		result.gemCount += 1
	end
	for _, line in item.bonusLines or {} do
		local id = type(line) == "table" and line.id or nil
		local gem, capped = nil, false
		if type(id) == "string" then
			gem, capped = numericGem(id)
		end
		if gem then
			addGem(gem)
			if capped then result.cappedLines += 1 end
		else
			result.unknownLines += 1
			warn(`[BlacksmithService] Dismantle: unknown bonus line {tostring(id)} on {tostring(item.instanceId)} (no gem)`)
		end
	end
	local maxOrder = _bonusData.RARITY_ORDER[GEM_MAX_RARITY]
	for _, pid in item.bonusPassiveIds or {} do
		local def = type(pid) == "string" and _bonusData.GetPassive(pid) or nil
		if not def then
			result.unknownLines += 1
			warn(`[BlacksmithService] Dismantle: unknown bonus passive {tostring(pid)} on {tostring(item.instanceId)} (no gem)`)
		elseif (_bonusData.RARITY_ORDER[def.minRarity] or 0) > maxOrder then
			table.insert(result.lostPassives, def.name or pid)
		else
			addGem(pid)
		end
	end
	return result
end

-- Destroys the item and credits its yield. Atomic: the item is removed first (no
-- duping); if removal fails nothing is credited. Equipped / staged checks are the
-- caller's job (guild_facilities 52). Returns ok, result | reason.
function BlacksmithService.CommitDismantle(playerId: string, item: any)
	local yield, err = BlacksmithService.ResolveDismantle(item)
	if not yield then
		return false, err or "Cannot dismantle"
	end
	if not (_inventory and _inventory.RemoveItem and _inventory.GetItem) then
		return false, "Inventory path not wired"
	end
	if not (_currency and _currency.Credit) then
		return false, "Currency path not wired"
	end
	if _inventory.GetItem(playerId, item.instanceId) ~= item then
		return false, "Item not owned"
	end

	local removed, remErr = _inventory.RemoveItem(playerId, item.instanceId)
	if not removed then
		return false, "Could not remove item: " .. tostring(remErr)
	end
	_currency.Credit(playerId, {
		mercury = yield.mercury,
		crystals = yield.crystals,
		sulfur = yield.sulfur,
		gems = yield.gems,
	})

	print(string.format("[BlacksmithService] DISMANTLED %s (%s L%d) | +%d mercury +%d crystals +%d sulfur +%d rune gem(s)%s",
		tostring(item.instanceId), tostring(item.rarityId), item.itemLevel, yield.mercury, yield.crystals,
		yield.sulfur, yield.gemCount,
		if #yield.lostPassives > 0 then ` | lost passives: {table.concat(yield.lostPassives, ", ")}` else ""))

	return true, { instanceId = item.instanceId, yield = yield }
end

return BlacksmithService
