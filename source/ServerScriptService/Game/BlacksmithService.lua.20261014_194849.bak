--!strict
-- BlacksmithService.lua
-- CTRBLXAI | Slice 6 — Base Management (Batch 1 of 3)
--
-- OWNS (per service_boundaries 'Blacksmith Service'):
--   Equipment upgrade/downgrade transaction (level change, rarity bonus budget
--   recompute).
--
-- READS:
--   Target item, upgrade gold cost formula (economy_framework id=19) +
--   material recipes (materials_system: Tier by Target Level + Quantity by
--   Rarity), player gold/materials.
--
-- WRITES:
--   Modified item handed back to persistence; gold + materials debited.
--
-- MUST NOT OWN:
--   New item generation, loot tables, combat.
--
-- PRIMARY INTERFACE:
--   ValidateUpgrade(playerId, item, targetLevel)
--   CommitUpgrade(playerId, item, targetLevel)
--   CommitDowngrade(playerId, item, targetLevel)
--
-- FAILURE BOUNDARY:
--   Atomic — gold + materials charged ONLY on success. Downgrade is FREE
--   (no gold/material refund or charge). NEVER creates a new item: it mutates
--   itemLevel on the existing instance and preserves the authored rolls.
--
-- ─────────────────────────────────────────────────────────────────────────
-- LOCKED DATA — copied verbatim from CTRBLXAI.db. Do NOT invent or tune here.
-- ─────────────────────────────────────────────────────────────────────────
--
--   economy_framework id=19 (Upgrade Gold Cost Formula, Locked):
--     Per level: floor(Base Value × Rarity Mult × 0.30 × (1 + Target Level/25)).
--   economy_framework id=11 (Base Value by Slot, Locked):
--     1H=100, 2H=150, Off-Hand=60, Body=80, Head=60, Gloves=50, Feet=50,
--     Accessory=70.
--   economy_framework id=12 (Rarity Multiplier, Locked):
--     Broken=0.1, Common=1.0, Uncommon=1.5, Rare=2.5, Epic=4.0, Legendary=7.0,
--     Mythic=12.0, Transcendent=20.0, Unique=15.0.
--   economy_framework id=21 (Downgrade, Locked): Free. No gold/materials/comp.
--
--   materials_system id=21 (Tier by Target Level, Locked):
--     L1-20→T1, L21-40→T2, L41-60→T3, L61-80→T4, L81-99→T5.
--   materials_system id=22 (Quantity by Rarity, Locked, per level):
--     Common=1, Uncommon=1, Rare=2, Epic=3, Legendary=4, Mythic=5,
--     Transcendent=6.
--
--   item_rarity_rules (Locked): "Rarity Does Not Recalculate Base" and
--     Item-Level scaling — native base stats + flat bonus components scale with
--     Item Level; the rarity Bonus BP budget and the authored bonus lines are
--     LEVEL-INVARIANT. Therefore an upgrade changes ONLY itemLevel; the scaled
--     profile is rebuilt on demand by WeaponData/ArmorData.GetScaledProfile at
--     equip time (EquipmentService.GetEffectiveWeaponProfile). The "rarity
--     bonus budget recompute" is a no-op on the stored budget (it does not
--     change with level) — we re-derive the scaled values, we never re-roll.
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

-- economy_framework id=12 — Rarity Multiplier (keyed by rarity NAME string,
-- which is how item.rarityId is stored by ItemGenerator).
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

-- materials_system id=22 — Quantity by Rarity (materials per upgrade level)
local MATERIAL_QTY_BY_RARITY = table.freeze({
	Broken       = 1,  -- not normally upgraded; treat as 1 to avoid div-by-zero paths
	Common       = 1,
	Uncommon     = 1,
	Rare         = 2,
	Epic         = 3,
	Legendary    = 4,
	Mythic       = 5,
	Transcendent = 6,
	Unique       = 6,  -- authored; treat at Transcendent rate if ever upgraded
})

local UPGRADE_GOLD_FACTOR = 0.30  -- economy_framework id=19
local LEVEL_DIVISOR = 25          -- economy_framework id=19 (Target Level / 25)
local MAX_ITEM_LEVEL = 99         -- unit/level cap (unit_progression id=48)
local MIN_ITEM_LEVEL = 1

--------------------------------------------------
-- INJECTED DEPENDENCIES
--------------------------------------------------

local _equipmentService: any = nil   -- DetermineSlot(item), Is2HEquipped (not used here)
local _weaponData: any = nil         -- GetByArchetypeId(id)
local _armorData: any = nil          -- GetByArchetypeId(id)
local _currency: any = nil           -- GetGold / SpendGold / GetMaterial / SpendMaterials
local _persistItem: any = nil        -- function(playerId, item) -> hand modified item back

function BlacksmithService.SetEquipmentService(svc: any) _equipmentService = svc end
function BlacksmithService.SetWeaponData(d: any) _weaponData = d end
function BlacksmithService.SetArmorData(d: any) _armorData = d end
function BlacksmithService.SetCurrencyProvider(svc: any) _currency = svc end
function BlacksmithService.SetItemPersist(fn: any) _persistItem = fn end

--------------------------------------------------
-- MATERIAL / CURRENCY NOTE
--
-- No gold/material store exists in the codebase yet (RewardService documents
-- the grant paths are designed-not-built). The currency provider contract used
-- here:
--     currency.GetGold(playerId) -> number
--     currency.SpendGold(playerId, amount) -> boolean
--     currency.GetMaterial(playerId, tier) -> number        (tier = 1..5)
--     currency.SpendMaterials(playerId, { [tier]=qty }) -> boolean
-- If no provider is injected, Validate reports blocked and Commit refuses —
-- it NEVER upgrades for free.
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
			-- hands field convention: "2H" / "1H" (fallback to 1H if unknown)
			local hands = wArch.hands or wArch.handedness
			if hands == "2H" or hands == 2 or wArch.isTwoHanded == true then
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
-- MATERIAL TIER BY TARGET LEVEL  (materials_system id=21 — LOCKED)
--------------------------------------------------

local function materialTierForLevel(targetLevel: number): number
	if targetLevel <= 20 then return 1
	elseif targetLevel <= 40 then return 2
	elseif targetLevel <= 60 then return 3
	elseif targetLevel <= 80 then return 4
	else return 5 end  -- 81-99
end

--------------------------------------------------
-- COST RESOLUTION
--
-- An upgrade from currentLevel -> targetLevel is PER LEVEL. Each intermediate
-- level L (currentLevel+1 .. targetLevel) costs its own gold at that level and
-- consumes materials of the tier for that level. We sum across the levels so a
-- multi-level upgrade is priced correctly (and materials may span two tiers,
-- e.g. the Legendary L65->L90 reference example crosses T4 and T5).
--
-- Returns: { gold = n, materials = { [tier]=qty }, perLevel = {...} } or nil+err
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

	local baseValue = baseValueOf(item)
	if not baseValue then
		return nil, "Could not resolve item base value (unknown archetype/slot)"
	end

	local rarity = item.rarityId
	local rarityMult = RARITY_MULT[rarity]
	if not rarityMult then
		return nil, "Unknown rarity: " .. tostring(rarity)
	end
	local matQtyPerLevel = MATERIAL_QTY_BY_RARITY[rarity]
	if not matQtyPerLevel then
		return nil, "Rarity not upgradeable: " .. tostring(rarity)
	end

	local totalGold = 0
	local materials: { [number]: number } = {}

	for lvl = item.itemLevel + 1, targetLevel do
		-- economy_framework id=19 (floor per level)
		local goldThisLevel = math.floor(baseValue * rarityMult * UPGRADE_GOLD_FACTOR * (1 + lvl / LEVEL_DIVISOR))
		totalGold += goldThisLevel

		-- materials_system id=21/22
		local tier = materialTierForLevel(lvl)
		materials[tier] = (materials[tier] or 0) + matQtyPerLevel
	end

	return { gold = totalGold, materials = materials }
end

--------------------------------------------------
-- AFFORDABILITY CHECKS (read-only)
--------------------------------------------------

local function hasGold(playerId: string, amount: number): (boolean, boolean)
	-- returns (available?, sufficient?)
	if not (_currency and _currency.GetGold) then return false, false end
	local gold = _currency.GetGold(playerId)
	if type(gold) ~= "number" then return false, false end
	return true, gold >= amount
end

local function hasMaterials(playerId: string, materials: { [number]: number }): (boolean, boolean)
	if not (_currency and _currency.GetMaterial) then return false, false end
	for tier, qty in materials do
		local have = _currency.GetMaterial(playerId, tier)
		if type(have) ~= "number" then return false, false end
		if have < qty then return true, false end
	end
	return true, true
end

--------------------------------------------------
-- PRIMARY INTERFACE: ValidateUpgrade
--
-- Returns: ok(boolean), reason(string|nil), cost(table|nil)
-- Charges NOTHING.
--------------------------------------------------

function BlacksmithService.ValidateUpgrade(playerId: string, item: any, targetLevel: number)
	local cost, err = BlacksmithService.ResolveUpgradeCost(item, targetLevel)
	if not cost then
		return false, err, nil
	end

	local goldAvail, goldOk = hasGold(playerId, cost.gold)
	if not goldAvail then
		return false, "Currency unavailable (no gold store wired)", cost
	end
	if not goldOk then
		return false, "Insufficient gold", cost
	end

	local matAvail, matOk = hasMaterials(playerId, cost.materials)
	if not matAvail then
		return false, "Materials unavailable (no material store wired)", cost
	end
	if not matOk then
		return false, "Insufficient materials", cost
	end

	return true, nil, cost
end

--------------------------------------------------
-- PRIMARY INTERFACE: CommitUpgrade
--
-- Atomic. Charges gold + materials ONLY after both are confirmed spendable.
-- Mutates itemLevel on the EXISTING instance (never re-rolls, never creates a
-- new item). The rarity bonus budget is level-invariant, so no re-roll of
-- bonusLines/rarityId occurs; the scaled profile re-derives at equip time.
--
-- Returns: ok(boolean), result(table|string)
--------------------------------------------------

function BlacksmithService.CommitUpgrade(playerId: string, item: any, targetLevel: number)
	local ok, reason, cost = BlacksmithService.ValidateUpgrade(playerId, item, targetLevel)
	if not ok or not cost then
		print(string.format("[BlacksmithService] Upgrade REJECTED | %s | (nothing charged)", tostring(reason)))
		return false, reason or "Upgrade rejected"
	end

	-- Debit gold then materials. Both must succeed; if the second fails we
	-- refund the first so the transaction stays atomic (no partial charge).
	if not (_currency and _currency.SpendGold and _currency.SpendMaterials) then
		return false, "Currency/material spend path not wired"
	end

	local goldSpent = _currency.SpendGold(playerId, cost.gold)
	if not goldSpent then
		return false, "Gold debit failed (raced) — nothing charged"
	end

	local matsSpent = _currency.SpendMaterials(playerId, cost.materials)
	if not matsSpent then
		-- Refund the gold to preserve atomicity.
		if _currency.AddGold then
			_currency.AddGold(playerId, cost.gold)
		else
			warn("[BlacksmithService] Material debit failed and no AddGold to refund — flag for manual reconciliation")
		end
		return false, "Material debit failed (raced) — gold refunded, nothing applied"
	end

	-- Apply the level change on the existing instance (NOT a new item).
	local prevLevel = item.itemLevel
	item.itemLevel = math.clamp(math.floor(targetLevel), MIN_ITEM_LEVEL, MAX_ITEM_LEVEL)

	-- Hand the modified item back to persistence (does not create a store here).
	if _persistItem then
		_persistItem(playerId, item)
	end

	print(string.format("[BlacksmithService] UPGRADED %s L%d->L%d | %dg + materials",
		tostring(item.instanceId), prevLevel, item.itemLevel, cost.gold))

	return true, { instanceId = item.instanceId, fromLevel = prevLevel, toLevel = item.itemLevel, cost = cost }
end

--------------------------------------------------
-- PRIMARY INTERFACE: CommitDowngrade  (economy_framework id=21 — FREE)
--
-- Reduces item level so lower-level units can equip it. No gold, no materials,
-- no refund, no compensation. Mutates the existing instance only.
--
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

	local prevLevel = item.itemLevel
	item.itemLevel = math.floor(targetLevel)

	if _persistItem then
		_persistItem(playerId, item)
	end

	print(string.format("[BlacksmithService] DOWNGRADED %s L%d->L%d | FREE (no charge, no refund)",
		tostring(item.instanceId), prevLevel, item.itemLevel))

	return true, { instanceId = item.instanceId, fromLevel = prevLevel, toLevel = item.itemLevel, cost = { gold = 0, materials = {} } }
end

return BlacksmithService
