--!strict
-- RuneforgeService.lua
-- CTRBLXAI | Runeforge (v2 build step 4, 2026-11-01) — server rules only (the screen is step 5).
--
-- OWNS (service_boundaries 18, v2 LOCKED USER DECISION 2026-11-01):
--   Forge transactions (install rune gems on Common-Epic items, raise rarity) and sulfur
--   rerolls of items above Epic. Rarity never goes down.
--
-- READS:
--   Target item (bonus lines, rarity, level, levelling record via BlacksmithService,
--   reroll count), the Runeforge level, rune gem storage + crystals + sulfur + gold
--   (CurrencyService), bonus attribute content (BonusData), the loot generator's
--   gear-type compatibility and naming (ItemGenerator).
--
-- WRITES:
--   The modified item (lines, rarity, name, runeForged tag, reroll count), handed to the
--   persist hook; gold + crystals + gems or sulfur debited in ONE atomic charge.
--
-- MUST NOT OWN:
--   New item generation, loot tables, combat, prices outside guild_facilities 43/55.
--
-- LOCKED DATA (CTRBLXAI.db, v2) — copied, not invented:
--   guild_facilities 42/44: forge Common-Epic items only; each gem is a new line or replaces
--     an existing line (destroyed, no gem back); one line per attribute family; bonus passive
--     slots 1 (2H: 2). New rarity = max(current, rarest line's minimum rarity, lowest rarity
--     whose budget holds the total BP: Uncommon 100 / Rare 150 / Epic 200, 2H doubled).
--   guild_facilities 43: crystals — every rarity step crossed: to Uncommon 3, to Rare 6, to
--     Epic 12; a forge that keeps the rarity costs 2 / 4 / 8 (Uncommon / Rare / Epic).
--   guild_facilities 45/53: capacity Uncommon at L1, Rare at L4, Epic at L7; forge + swap fee
--     discount 3% per level above L1.
--   guild_facilities 48/55: gold = forge fee on the rarity difference (multiplier Common 0,
--     Uncommon 1.5, Rare 2.5, Epic 4.0) + levelling catch-up (no discount), or the swap fee
--     (slot × 0.5 × rarity multiplier) when rarity is kept. Rounded down, whole numbers.
--   guild_facilities 54: rerolls of Exalted / Legendary (2/3/4 sets at L8/9/10), Mythic (2/3 at
--     L9/10), Transcendent (2 at L10); sulfur 1/2/3/4; sets fixed by item ID + reroll count;
--     'Keep current' always offered; sulfur paid either way; rarity never changes.
--   guild_facilities 56: a gem goes only on gear that could roll it as loot (ItemGenerator's
--     own gear-type check, BUG-054); at most one elemental transform / pattern conversion.
--   USER DECISION 2026-11-01: rune-forged items get a tracking tag (item.runeForged) and are
--     otherwise treated exactly like any other item (selling, dismantling).
--
-- DEPENDENCIES ARE INJECTED (no circular require). All nil-safe: missing wiring refuses.

local RuneforgeService = {}

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

local MAX_RUNEFORGE_LEVEL = 10
local MAX_INSTALLS = 8               -- request bound (SEC-001); an item has far fewer lines
local MAX_GEM_TIER = 4               -- rune gems are Epic tier at most (materials_system 4)
local DISCOUNT_PER_LEVEL = 3         -- % per Runeforge level above L1 (gf 45)

local FORGEABLE = table.freeze({ Common = true, Uncommon = true, Rare = true, Epic = true })
local STEP_RARITIES = table.freeze({ "Uncommon", "Rare", "Epic" })
local STEP_CRYSTALS = table.freeze({ Uncommon = 3, Rare = 6, Epic = 12 })
local KEEP_CRYSTALS = table.freeze({ Uncommon = 2, Rare = 4, Epic = 8 })
-- Forge fee multiplier ×10 (gf 55: Common counts as 0 for this fee only).
local FORGE_M10 = table.freeze({ Common = 0, Uncommon = 15, Rare = 25, Epic = 40 })
-- Swap fee rarity multiplier ×10 (economy_framework 12).
local SWAP_R10 = table.freeze({ Uncommon = 15, Rare = 25, Epic = 40 })

local REROLL_SULFUR = table.freeze({ Exalted = 1, Legendary = 2, Mythic = 3, Transcendent = 4 })
local REROLL_SETS = table.freeze({
	Exalted      = table.freeze({ [8] = 2, [9] = 3, [10] = 4 }),
	Legendary    = table.freeze({ [8] = 2, [9] = 3, [10] = 4 }),
	Mythic       = table.freeze({ [9] = 2, [10] = 3 }),
	Transcendent = table.freeze({ [10] = 2 }),
})
local REROLL_UNLOCK = table.freeze({ Exalted = 8, Legendary = 8, Mythic = 9, Transcendent = 10 })

--------------------------------------------------
-- INJECTED DEPENDENCIES
--------------------------------------------------

local _currency: any = nil        -- CurrencyService.AsProvider(): CanAfford / Debit / GetGold
local _inventory: any = nil       -- InventoryService: GetItem
local _bonusData: any = nil       -- BonusData content
local _itemGen: any = nil         -- ItemGenerator: GetCompatibleGems / GetExclusiveGroup / ComposeName / RollBonusSet
local _blacksmith: any = nil      -- BlacksmithService: GetBaseValue / CatchUpGold
local _weaponData: any = nil
local _armorData: any = nil
local _level: any = nil           -- () -> effective Runeforge level (0 = not unlocked)
local _persistItem: any = nil     -- (playerId, item) -> rebuild the holder's stats

function RuneforgeService.SetCurrencyProvider(svc: any) _currency = svc end
function RuneforgeService.SetInventoryService(svc: any) _inventory = svc end
function RuneforgeService.SetBonusData(d: any) _bonusData = d end
function RuneforgeService.SetItemGenerator(g: any) _itemGen = g end
function RuneforgeService.SetBlacksmithService(svc: any) _blacksmith = svc end
function RuneforgeService.SetWeaponData(d: any) _weaponData = d end
function RuneforgeService.SetArmorData(d: any) _armorData = d end
function RuneforgeService.SetLevelProvider(fn: any) _level = fn end
function RuneforgeService.SetItemPersist(fn: any) _persistItem = fn end

--------------------------------------------------
-- SMALL HELPERS
--------------------------------------------------

local function order(rarity: string?): number
	return (_bonusData and rarity and _bonusData.RARITY_ORDER[rarity]) or 0
end

local function currentLevel(): number
	local lvl = if _level then tonumber(_level()) else nil
	return math.clamp(math.floor(lvl or 0), 0, MAX_RUNEFORGE_LEVEL)
end

local function capacityRarity(level: number): string?
	if level >= 7 then return "Epic" end
	if level >= 4 then return "Rare" end
	if level >= 1 then return "Uncommon" end
	return nil
end

local function discountPct(level: number): number
	return math.max(0, DISCOUNT_PER_LEVEL * (level - 1))
end

local function archetypeOf(item: any): any?
	local id = item.baseArchetypeId
	return (_weaponData and _weaponData.GetByArchetypeId(id)) or (_armorData and _armorData.GetByArchetypeId(id)) or nil
end

local function is2H(item: any): boolean
	local a = archetypeOf(item)
	return a ~= nil and a.handClass == "2H"
end

-- Short player-facing name of a rune gem ("STR Bonus T2", "Charge").
function RuneforgeService.DescribeGem(gemId: string): any?
	if not _bonusData then return nil end
	local attr = _bonusData.GetAttribute(gemId)
	if attr then
		return { id = gemId, kind = "stat", name = `{attr.family} T{attr.tier}`, family = attr.family,
			tier = attr.tier, bp = attr.bpCost, minRarity = attr.minRarity }
	end
	local p = _bonusData.GetPassive(gemId)
	if p then
		return { id = gemId, kind = "passive", name = p.name or gemId, family = gemId, tier = 0,
			bp = p.bpCost, minRarity = p.minRarity, desc = p.desc }
	end
	return nil
end

-- A stored gem must be Epic tier at most (dismantle already guarantees it; checked again).
local function isInstallableGem(gemId: string): boolean
	if not _bonusData then return false end
	local attr = _bonusData.GetAttribute(gemId)
	if attr then return (attr.tier or 0) <= MAX_GEM_TIER end
	local p = _bonusData.GetPassive(gemId)
	if p then return order(p.minRarity) <= order("Epic") end
	return false
end

-- Lowest of Uncommon / Rare / Epic whose normal budget holds `bp` (gf 44 c). nil = too much.
local function budgetRarity(bp: number, twoHanded: boolean): string?
	if bp <= 0 then return "Common" end
	for _, r in STEP_RARITIES do
		if bp <= _bonusData.GetBonusBp(r, twoHanded) then return r end
	end
	return nil
end

-- Stable 31-bit hash of the item ID (reroll sets: gf 54).
local function idHash(id: string): number
	local h = 0
	for i = 1, #id do
		h = (h * 31 + string.byte(id, i)) % 2147483647
	end
	return h
end

local function setSeed(item: any, setNo: number): number
	local rc = math.max(0, math.floor(tonumber(item.rerollCount) or 0))
	return (idHash(tostring(item.instanceId)) + rc * 7919 + setNo * 104729) % 2147483647
end

-- Gem IDs (numeric + passive) this item could roll as loot (gf 56, BUG-054 check).
function RuneforgeService.CompatibleGems(item: any): { [string]: boolean }
	if not (_itemGen and _itemGen.GetCompatibleGems) then return {} end
	return _itemGen.GetCompatibleGems(item.baseArchetypeId)
end

--------------------------------------------------
-- FORGE PLAN (pure: prices and validates, changes nothing)
--
-- installs = { { gem = gemId, replace = existingLineId? }, ... }
-- Returns plan or nil + reason. plan = { newRarity, raised, lines, passives, totalBp,
--   crystals, gold, forgeFee, swapFee, catchUp, gems = { [gemId] = n }, replaced = { id } }
--------------------------------------------------

function RuneforgeService.PlanForge(item: any, installs: any)
	if not (_bonusData and _itemGen and _blacksmith) then
		return nil, "Runeforge not wired"
	end
	if type(item) ~= "table" or type(item.itemLevel) ~= "number" then
		return nil, "Invalid item"
	end
	local level = currentLevel()
	if level < 1 then
		return nil, "The Runeforge is not built yet (needs Guild Hall L4)"
	end
	local rarity = item.rarityId
	if rarity == "Unique" then
		return nil, "Unique items cannot be rune-forged"
	end
	if not FORGEABLE[rarity] then
		return nil, `{tostring(rarity)} items cannot take rune gems (sulfur rerolls only)`
	end
	if type(installs) ~= "table" or #installs == 0 then
		return nil, "Choose at least one rune gem"
	end
	if #installs > MAX_INSTALLS then
		return nil, "Too many rune gems in one forge"
	end

	local twoHanded = is2H(item)
	local maxPassives = if twoHanded then 2 else 1
	local compatible = RuneforgeService.CompatibleGems(item)

	-- Working copy of the item's lines.
	local lines: { any } = {}
	for _, l in item.bonusLines or {} do
		if type(l) == "table" and type(l.id) == "string" then
			table.insert(lines, { id = l.id, tier = l.tier })
		end
	end
	local passives: { string } = {}
	for _, pid in item.bonusPassiveIds or {} do
		if type(pid) == "string" then table.insert(passives, pid) end
	end
	local original: { [string]: boolean } = {}
	for _, l in lines do original[l.id] = true end
	for _, pid in passives do original[pid] = true end

	local function removeLine(id: string): boolean
		for i, l in lines do
			if l.id == id then table.remove(lines, i); return true end
		end
		for i, pid in passives do
			if pid == id then table.remove(passives, i); return true end
		end
		return false
	end

	local gemsUsed: { [string]: number } = {}
	local replaced: { string } = {}
	local newFamilies: { [string]: boolean } = {}
	local replacedSet: { [string]: boolean } = {}

	for _, ins in installs do
		if type(ins) ~= "table" or type(ins.gem) ~= "string" or #ins.gem > 64 then
			return nil, "Invalid rune gem"
		end
		local gem: string = ins.gem
		local rep: string? = if type(ins.replace) == "string" then ins.replace else nil
		if not isInstallableGem(gem) then
			return nil, `Unknown rune gem {gem}`
		end
		if not compatible[gem] then
			local d = RuneforgeService.DescribeGem(gem)
			return nil, `{if d then d.name else gem} cannot go on this item`
		end
		if rep ~= nil then
			if not original[rep] or replacedSet[rep] then
				return nil, "The line to replace is not on this item"
			end
		end

		local attr = _bonusData.GetAttribute(gem)
		if attr then
			if newFamilies[attr.family] then
				return nil, `Two {attr.family} gems in one forge`
			end
			newFamilies[attr.family] = true
			-- One line per family (gf 44): a gem of a family the item has replaces that line.
			local sameFamily: string? = nil
			for _, l in lines do
				local la = _bonusData.GetAttribute(l.id)
				if la and la.family == attr.family then sameFamily = l.id end
			end
			if sameFamily then
				if rep ~= nil and rep ~= sameFamily then
					return nil, `The item already has a {attr.family} line; this gem replaces it`
				end
				rep = sameFamily
			end
			if rep ~= nil then
				removeLine(rep)
				replacedSet[rep] = true
				table.insert(replaced, rep)
			end
			table.insert(lines, { id = gem, tier = attr.tier })
		else
			-- Passive gem.
			if newFamilies[gem] or table.find(passives, gem) then
				return nil, "The item already has that passive"
			end
			newFamilies[gem] = true
			if rep ~= nil then
				removeLine(rep)
				replacedSet[rep] = true
				table.insert(replaced, rep)
			end
			if #passives >= maxPassives then
				return nil, "No free bonus passive slot. Choose a passive to replace."
			end
			local grp = _itemGen.GetExclusiveGroup(gem)
			if grp then
				for _, pid in passives do
					if _itemGen.GetExclusiveGroup(pid) == grp then
						return nil, "Only one elemental change or attack-shape change per item"
					end
				end
			end
			table.insert(passives, gem)
		end
		gemsUsed[gem] = (gemsUsed[gem] or 0) + 1
	end

	-- New rarity (gf 44): current, rarest line, budget.
	local totalBp = 0
	local rarest = rarity
	for _, l in lines do
		local a = _bonusData.GetAttribute(l.id)
		if a then
			totalBp += a.bpCost or 0
			if order(a.minRarity) > order(rarest) then rarest = a.minRarity end
		end
	end
	for _, pid in passives do
		local p = _bonusData.GetPassive(pid)
		if p then
			totalBp += p.bpCost or 0
			if order(p.minRarity) > order(rarest) then rarest = p.minRarity end
		end
	end
	local byBudget = budgetRarity(totalBp, twoHanded)
	if not byBudget then
		return nil, "Too many bonus points: the total is above the Epic budget"
	end
	local newRarity = rarity
	if order(rarest) > order(newRarity) then newRarity = rarest end
	if order(byBudget) > order(newRarity) then newRarity = byBudget end
	if not FORGEABLE[newRarity] then
		return nil, "These gems would make the item rarer than Epic"
	end

	-- Capacity by Runeforge level (gf 54).
	local cap = capacityRarity(level) :: string
	if order(newRarity) > order(cap) then
		local need = if newRarity == "Epic" then 7 else 4
		return nil, `{newRarity} forging needs Runeforge L{need} (yours is L{level})`
	end

	local raised = order(newRarity) > order(rarity)

	-- Crystals (gf 43).
	local crystals = 0
	if raised then
		for _, r in STEP_RARITIES do
			if order(r) > order(rarity) and order(r) <= order(newRarity) then
				crystals += STEP_CRYSTALS[r]
			end
		end
	else
		crystals = KEEP_CRYSTALS[rarity] or 0
	end

	-- Gold (gf 48 / 55), whole-number maths, rounded down.
	local base = _blacksmith.GetBaseValue(item)
	if not base then
		return nil, "Could not resolve the item's slot value"
	end
	local d = discountPct(level)
	local forgeFee, swapFee, catchUp = 0, 0, 0
	if raised then
		local function p(r: string): number
			return (base * FORGE_M10[r] * (100 - d)) // 1000
		end
		forgeFee = p(newRarity) - p(rarity)
		local cu = _blacksmith.CatchUpGold(item, rarity, newRarity)
		if cu == nil then
			return nil, "Could not work out the levelling catch-up"
		end
		catchUp = cu
	else
		swapFee = (base * SWAP_R10[rarity] * (100 - d)) // 2000
	end

	return {
		newRarity = newRarity,
		raised = raised,
		lines = lines,
		passives = passives,
		totalBp = totalBp,
		crystals = crystals,
		gold = forgeFee + swapFee + catchUp,
		forgeFee = forgeFee,
		swapFee = swapFee,
		catchUp = catchUp,
		gems = gemsUsed,
		replaced = replaced,
		runeforgeLevel = level,
	}
end

--------------------------------------------------
-- FORGE COMMIT — one atomic charge, then the item changes.
-- Returns ok, result | reason.
--------------------------------------------------

function RuneforgeService.CommitForge(playerId: string, item: any, installs: any)
	local plan, why = RuneforgeService.PlanForge(item, installs)
	if not plan then
		return false, why or "Cannot forge"
	end
	if not (_currency and _currency.CanAfford and _currency.Debit) then
		return false, "Currency path not wired"
	end
	if not (_inventory and _inventory.GetItem and _inventory.GetItem(playerId, item.instanceId) == item) then
		return false, "Item not owned"
	end
	local cost = { gold = plan.gold, crystals = plan.crystals, gems = plan.gems }
	local paid, payWhy = _currency.Debit(playerId, cost)
	if not paid then
		return false, `{tostring(payWhy or "Payment failed")} -- nothing charged`
	end

	local fromRarity = item.rarityId
	item.bonusLines = plan.lines
	item.bonusPassiveIds = plan.passives
	item.rarityId = plan.newRarity
	item.runeForged = true -- tracking tag only (USER DECISION 2026-11-01)
	local newName = _itemGen.ComposeName(item.baseArchetypeId, plan.lines, plan.passives)
	if newName then item.displayName = newName end

	if _persistItem then
		_persistItem(playerId, item)
	end

	local gemCount = 0
	for _, n in plan.gems do gemCount += n end
	print(string.format("[RuneforgeService] FORGED %s %s -> %s | %d gem(s), %d replaced | -%dg (forge %d, swap %d, catch-up %d) -%d crystals | Runeforge L%d",
		tostring(item.instanceId), tostring(fromRarity), plan.newRarity, gemCount, #plan.replaced,
		plan.gold, plan.forgeFee, plan.swapFee, plan.catchUp, plan.crystals, plan.runeforgeLevel))

	return true, { instanceId = item.instanceId, fromRarity = fromRarity, plan = plan }
end

--------------------------------------------------
-- SULFUR REROLLS (gf 54) — items above Epic
--------------------------------------------------

-- The N fixed sets offered for this item now. Free to look at; the sets only change after
-- a PAID reroll (reroll count + 1), so leaving and rejoining never changes them.
-- Returns { sets = { { lines, passives, name } }, sulfur, setCount } or nil + reason.
function RuneforgeService.GetRerollOffer(item: any)
	if not (_bonusData and _itemGen) then
		return nil, "Runeforge not wired"
	end
	if type(item) ~= "table" or type(item.itemLevel) ~= "number" then
		return nil, "Invalid item"
	end
	local rarity = item.rarityId
	if rarity == "Unique" then
		return nil, "Unique items cannot be rerolled"
	end
	local sulfur = REROLL_SULFUR[rarity]
	if not sulfur then
		return nil, `{tostring(rarity)} items are changed with rune gems, not sulfur rerolls`
	end
	local level = currentLevel()
	local count = REROLL_SETS[rarity][level]
	if not count then
		if level < 1 then
			return nil, "The Runeforge is not built yet (needs Guild Hall L4)"
		end
		return nil, `{rarity} rerolls need Runeforge L{REROLL_UNLOCK[rarity]} (yours is L{level})`
	end
	local sets = {}
	for k = 1, count do
		local set = _itemGen.RollBonusSet(item.baseArchetypeId, item.itemLevel, rarity, setSeed(item, k))
		if not set then
			return nil, "Could not build the reroll options"
		end
		set.name = _itemGen.ComposeName(item.baseArchetypeId, set.bonusLines, set.bonusPassiveIds)
		table.insert(sets, set)
	end
	return { sets = sets, sulfur = sulfur, setCount = count, runeforgeLevel = level }
end

-- choice 0 = keep the current lines, 1..N = take that set. Sulfur is paid either way.
function RuneforgeService.CommitReroll(playerId: string, item: any, choice: any)
	local offer, why = RuneforgeService.GetRerollOffer(item)
	if not offer then
		return false, why or "Cannot reroll"
	end
	if type(choice) ~= "number" or choice ~= choice or choice % 1 ~= 0 or choice < 0 or choice > offer.setCount then
		return false, "Invalid choice"
	end
	if not (_currency and _currency.Debit) then
		return false, "Currency path not wired"
	end
	if not (_inventory and _inventory.GetItem and _inventory.GetItem(playerId, item.instanceId) == item) then
		return false, "Item not owned"
	end
	local paid, payWhy = _currency.Debit(playerId, { sulfur = offer.sulfur })
	if not paid then
		return false, `{tostring(payWhy or "Payment failed")} -- nothing charged`
	end

	if choice > 0 then
		local set = offer.sets[choice]
		item.bonusLines = set.bonusLines
		item.bonusPassiveIds = set.bonusPassiveIds
		if set.name then item.displayName = set.name end
	end
	-- Every PAID reroll counts, also 'Keep current' (gf 54).
	item.rerollCount = math.max(0, math.floor(tonumber(item.rerollCount) or 0)) + 1
	item.runeForged = true -- tracking tag only (USER DECISION 2026-11-01)

	if _persistItem then
		_persistItem(playerId, item)
	end

	print(string.format("[RuneforgeService] REROLLED %s (%s) | choice %d of %d%s | -%d sulfur | reroll count %d",
		tostring(item.instanceId), tostring(item.rarityId), choice, offer.setCount,
		if choice == 0 then " (kept current)" else "", offer.sulfur, item.rerollCount))

	return true, { instanceId = item.instanceId, choice = choice, rerollCount = item.rerollCount }
end

--------------------------------------------------
-- SCREEN HELPERS
--------------------------------------------------

function RuneforgeService.GetState(): any
	local level = currentLevel()
	return {
		level = level,
		capacity = capacityRarity(level),
		discountPct = if level >= 1 then discountPct(level) else 0,
	}
end

function RuneforgeService.IsForgeable(item: any): (boolean, string?)
	if item.rarityId == "Unique" then return false, "Unique items cannot be rune-forged" end
	if FORGEABLE[item.rarityId] then return true, nil end
	return false, "Above Epic: sulfur rerolls only"
end

function RuneforgeService.RerollInfo(item: any): any?
	local sulfur = REROLL_SULFUR[item.rarityId]
	if not sulfur then return nil end
	local level = currentLevel()
	return {
		sulfur = sulfur,
		setCount = REROLL_SETS[item.rarityId][level],
		unlockLevel = REROLL_UNLOCK[item.rarityId],
	}
end

return RuneforgeService
