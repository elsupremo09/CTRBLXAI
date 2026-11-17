--!strict
-- RuneforgeService.lua
-- CTRBLXAI | Runeforge (v2 build step 4, 2026-11-01) — server rules only (the screen is step 5).
--
-- OWNS (service_boundaries 18, v2 LOCKED USER DECISION 2026-11-01):
--   Forge transactions (install rune gems on Common-Epic items, raise rarity) and sulfur
--   rerolls of items above Epic. Gems never lower the rarity; removing a line can
--   (guild_facilities 84, USER DECISION 2026-11-07).
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
--     USER DECISION 2026-11-01 (over-budget loot): the points the item already has never count
--     against it. The budget check only raises the rarity when the new total is above BOTH the
--     current rarity's budget AND the item's own total before the forge.
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
--     USER RULING 2026-11-07 (pay first): the sets are made and shown only AFTER the sulfur is
--     paid (PayReroll). The paid sets are saved on the item (item.pendingReroll) until the
--     player picks one or keeps the current lines (CommitReroll). While a choice is open the
--     item cannot be rerolled again, forged, sold, dismantled or merged.
--   guild_facilities 56: a gem goes only on gear that could roll it as loot (ItemGenerator's
--     own gear-type check, BUG-054); at most one elemental transform / pattern conversion.
--   guild_facilities 84 (USER DECISION 2026-11-07): a pick may REMOVE a line ({ remove = id })
--     for gold only (the swap fee of gf 55 at the current rarity, per removed line); the line
--     is destroyed (no gem back). With a removal in the forge the rarity follows the new total
--     (lowest rarity whose budget holds it, never below the rarest remaining line) and the
--     over-budget-loot allowance no longer applies. Removing every line leaves a Common item.
--   USER DECISION 2026-11-01: rune-forged items get a tracking tag (item.runeForged) and are
--     otherwise treated exactly like any other item (selling, dismantling).
--
-- DEPENDENCIES ARE INJECTED (no circular require). All nil-safe: missing wiring refuses.

local RuneforgeService = {}
local BuildingService = require(script.Parent:WaitForChild("BuildingService")) -- pure module (no requires), lock text only

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

-- Shown by every service that refuses an item with an open (paid, not yet chosen) reroll
-- (USER RULING 2026-11-07). BlacksmithService / MerchantService use the same wording.
local PENDING_REROLL_REASON = "Reroll choice pending: pick a set or keep the current lines at the Runeforge first"
RuneforgeService.PENDING_REROLL_REASON = PENDING_REROLL_REASON

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

-- BONUS-POINT BUDGET (2026-11-07, user request: show the budget on the Runeforge screen).
-- ONE formula, used by PlanForge and BudgetOf (DAT-001 / AP-021): the screen only shows these
-- numbers, it never works them out.
local function linesBp(lines: { any }, passives: { string }): number
	local bp = 0
	for _, l in lines do
		local a = _bonusData.GetAttribute(l.id)
		if a then bp += a.bpCost or 0 end
	end
	for _, pid in passives do
		local p = _bonusData.GetPassive(pid)
		if p then bp += p.bpCost or 0 end
	end
	return bp
end

-- Most bonus points a forge may leave on the item (gf 44 c + gf 54): the capacity rarity's
-- budget at this Runeforge level, or the item's own total before the forge if that is higher.
local function maxBudgetBp(rarity: string?, twoHanded: boolean, originalBp: number, level: number): number
	local currentBudget = if rarity == "Common" or rarity == nil then 0 else _bonusData.GetBonusBp(rarity, twoHanded)
	local cap = capacityRarity(level)
	local capBudget = if cap then _bonusData.GetBonusBp(cap, twoHanded) else 0
	return math.max(currentBudget, originalBp, capBudget)
end

--------------------------------------------------
-- FORGE PLAN (pure: prices and validates, changes nothing)
--
-- installs = { { gem = gemId, replace = existingLineId? } | { remove = existingLineId }, ... }
-- Returns plan or nil + reason. plan = { newRarity, raised, dropped, lines, passives, totalBp,
--   crystals, gold, forgeFee, swapFee, catchUp, removalFee, gems = { [gemId] = n },
--   replaced = { id }, removed = { id } }
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
		return nil, BuildingService.LockLine("Runeforge") -- approved lock line (guild_facilities 98)
	end
	local rarity = item.rarityId
	if rarity == "Unique" then
		return nil, "Unique items cannot be rune-forged"
	end
	if type(item.pendingReroll) == "table" then
		return nil, PENDING_REROLL_REASON
	end
	if not FORGEABLE[rarity] then
		return nil, `{tostring(rarity)} items cannot take rune gems (sulfur rerolls only)`
	end
	if type(installs) ~= "table" or #installs == 0 then
		return nil, "Choose at least one rune gem or a line to remove"
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
	-- The item's own total before the forge (over-budget loot ruling, 2026-11-01).
	local originalBp = linesBp(lines, passives)
	local maxBp = maxBudgetBp(rarity, twoHanded, originalBp, level)

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
	local removed: { string } = {}

	for _, ins in installs do
		-- Remove a line (gf 84): gold only, the line is destroyed. A removed line counts as
		-- taken, so no gem can replace it in the same forge and it can't be removed twice.
		if type(ins) == "table" and ins.remove ~= nil then
			local rem = ins.remove
			if type(rem) ~= "string" or #rem > 64 or ins.gem ~= nil or ins.replace ~= nil then
				return nil, "Invalid line to remove"
			end
			if not original[rem] then
				return nil, "The line to remove is not on this item"
			end
			if replacedSet[rem] then
				return nil, "That line is already being replaced by another gem in this forge"
			end
			removeLine(rem)
			replacedSet[rem] = true
			table.insert(removed, rem)
			continue
		end
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
			if not original[rep] then
				return nil, "The line to replace is not on this item"
			end
			if replacedSet[rep] then
				return nil, "That line is already being replaced by another gem in this forge"
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
	local totalBp = linesBp(lines, passives)
	local rarest = rarity
	for _, l in lines do
		local a = _bonusData.GetAttribute(l.id)
		if a and order(a.minRarity) > order(rarest) then rarest = a.minRarity end
	end
	for _, pid in passives do
		local p = _bonusData.GetPassive(pid)
		if p and order(p.minRarity) > order(rarest) then rarest = p.minRarity end
	end
	-- Budget numbers for the screen (display only): returned with a refusal that is caused
	-- by going over the budget, so the screen can say "over budget by N".
	-- A forge with a removal (gf 84): the rarity follows the new total, so the rarest line only
	-- counts from the lines that stay, and the over-budget allowance is used up. The most it
	-- may hold is then the capacity rarity's budget (gf 54).
	local hasRemoval = #removed > 0
	if hasRemoval then
		rarest = "Common"
		for _, l in lines do
			local a = _bonusData.GetAttribute(l.id)
			if a and order(a.minRarity) > order(rarest) then rarest = a.minRarity end
		end
		for _, pid in passives do
			local p = _bonusData.GetPassive(pid)
			if p and order(p.minRarity) > order(rarest) then rarest = p.minRarity end
		end
		local capR = capacityRarity(level)
		maxBp = if capR then _bonusData.GetBonusBp(capR, twoHanded) else 0
	end
	local budget = { used = totalBp, max = maxBp }
	-- Over-budget loot (USER DECISION 2026-11-01): a total that stays within the current
	-- rarity's budget, or within the item's own total before the forge, keeps the rarity.
	local currentBudget = if rarity == "Common" then 0 else _bonusData.GetBonusBp(rarity, twoHanded)
	local allowance = math.max(currentBudget, originalBp)
	local byBudget
	-- A forge that only removes lines (gf 84, USER RULING 2026-11-07): rarity may drop or
	-- stay, never rise. Without this cap an over-budget loot item would lose its allowance
	-- and could be raised for the removal fee alone (Tester F-1).
	local removalOnly = false
	if hasRemoval then
		local gemPicks = 0
		for _, n in gemsUsed do gemPicks += n end
		removalOnly = gemPicks == 0
		byBudget = budgetRarity(totalBp, twoHanded)
		if removalOnly and (byBudget == nil or order(byBudget) > order(rarity)) then
			byBudget = rarity
		end
	else
		byBudget = if totalBp <= allowance then rarity else budgetRarity(totalBp, twoHanded)
	end
	if not byBudget then
		return nil, "Too many bonus points: the total is above the Epic budget", budget
	end
	-- Without a removal the rarity never goes down (gf 44 a); with one it starts from Common.
	local newRarity = if hasRemoval then "Common" else rarity
	if order(rarest) > order(newRarity) then newRarity = rarest end
	if order(byBudget) > order(newRarity) then newRarity = byBudget end
	if removalOnly and order(newRarity) > order(rarity) then newRarity = rarity end
	if not FORGEABLE[newRarity] then
		return nil, "These gems would make the item rarer than Epic"
	end

	-- Capacity by Runeforge level (gf 54).
	local cap = capacityRarity(level) :: string
	if order(newRarity) > order(cap) then
		local need = if newRarity == "Epic" then 7 else 4
		return nil, `{newRarity} forging needs Runeforge L{need} (yours is L{level})`, budget
	end

	local raised = order(newRarity) > order(rarity)
	local dropped = order(newRarity) < order(rarity)
	local gemCount = 0
	for _, n in gemsUsed do gemCount += n end

	-- Gem-part price rarity (USER RULING 2026-11-07, gf 84): when a forge both removes a line
	-- and installs a gem and the rarity DROPS, the gem part (crystals + swap fee) is priced at
	-- the new, lower rarity. Every other case keeps the starting rarity. Removal fee unchanged.
	local priceRarity = if hasRemoval and dropped then newRarity else rarity
	-- Crystals (gf 43). A forge that only removes lines costs gold only (gf 84).
	local crystals = 0
	if gemCount == 0 then
		crystals = 0
	elseif raised then
		for _, r in STEP_RARITIES do
			if order(r) > order(rarity) and order(r) <= order(newRarity) then
				crystals += STEP_CRYSTALS[r]
			end
		end
	else
		crystals = KEEP_CRYSTALS[priceRarity] or 0
	end

	-- Gold (gf 48 / 55), whole-number maths, rounded down.
	local base = _blacksmith.GetBaseValue(item)
	if not base then
		return nil, "Could not resolve the item's slot value"
	end
	local d = discountPct(level)
	local forgeFee, swapFee, catchUp = 0, 0, 0
	-- Removal fee (gf 84): the swap fee of gf 55 at the item's current rarity, per removed line.
	local removalFee = #removed * ((base * (SWAP_R10[rarity] or 0) * (100 - d)) // 2000)
	if gemCount == 0 then
		-- Only removals: no forge / swap fee, no catch-up.
	elseif raised then
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
		swapFee = (base * (SWAP_R10[priceRarity] or 0) * (100 - d)) // 2000
	end

	return {
		newRarity = newRarity,
		raised = raised,
		dropped = dropped,
		lines = lines,
		passives = passives,
		totalBp = totalBp,
		maxBp = maxBp,
		crystals = crystals,
		gold = forgeFee + swapFee + catchUp + removalFee,
		forgeFee = forgeFee,
		swapFee = swapFee,
		catchUp = catchUp,
		removalFee = removalFee,
		gems = gemsUsed,
		replaced = replaced,
		removed = removed,
		runeforgeLevel = level,
	}
end

--------------------------------------------------
-- CANDIDATE CHECK (2026-11-06). For each candidate gem, would the forge still be accepted if it
-- were added to the current installs? Runs PlanForge itself, so the bonus-point budget, the
-- rarity cap, the Runeforge level cap and the gem limit all come from the ONE server formula;
-- the screen only greys out what this says no to. Pure: changes nothing.
-- candidates = { { gem = gemId, replace = lineId? }, ... }. Returns { [i] = true | reason }.
--------------------------------------------------

RuneforgeService.MAX_INSTALLS = MAX_INSTALLS

-- Display only ((?) guide, 2026-11-07): where each forge rarity cap starts and the lowest
-- reroll unlock level, built from the same rule tables (capacityRarity / REROLL_UNLOCK).
function RuneforgeService.CapacitySteps(): { { level: number, rarity: string } }
	local out, last = {}, nil
	for lvl = 0, MAX_RUNEFORGE_LEVEL do
		local r = capacityRarity(lvl)
		if r and r ~= last then
			table.insert(out, { level = lvl, rarity = r })
			last = r
		end
	end
	return out
end
function RuneforgeService.RerollMinLevel(): number
	local m = MAX_RUNEFORGE_LEVEL
	for _, l in REROLL_UNLOCK do
		if l < m then m = l end
	end
	return m
end
RuneforgeService.MAX_CANDIDATES = 256 -- request bound (SEC-001); an item fits ~110 gem types

-- Second result (2026-11-07): { [i] = points over the budget, 0 if not a budget refusal }
-- for every candidate, so the screen can show "over budget by N" (numbers from PlanForge itself).
function RuneforgeService.CheckCandidates(item: any, installs: any, candidates: any): ({ any }, { [number]: number })
	local out: { any } = {}
	local over: { [number]: number } = {}
	if type(candidates) ~= "table" then return out, over end
	local base: { any } = if type(installs) == "table" then installs else {}
	for i, cand in candidates do
		if i > RuneforgeService.MAX_CANDIDATES then break end
		local trial = table.clone(base)
		table.insert(trial, cand)
		local plan, why, budget = RuneforgeService.PlanForge(item, trial)
		out[i] = if plan then true else tostring(why)
		-- Dense list (0 = not a budget refusal): sparse number keys would arrive as text keys
		-- over a remote.
		over[i] = if not plan and type(budget) == "table" and budget.used > budget.max
			then budget.used - budget.max else 0
	end
	return out, over
end

-- Budget of the item with the given picks (none = as it is now): { used, max } or nil.
-- Display only (2026-11-07). With picks it is PlanForge's own total; with none it uses the
-- same two helpers PlanForge uses.
function RuneforgeService.BudgetOf(item: any, installs: any?): { used: number, max: number }?
	if not (_bonusData and _itemGen and _blacksmith) or type(item) ~= "table" then return nil end
	if type(installs) == "table" and #installs > 0 then
		local plan, _, budget = RuneforgeService.PlanForge(item, installs)
		if plan then return { used = plan.totalBp, max = plan.maxBp } end
		return if type(budget) == "table" then budget else nil
	end
	local lines: { any } = {}
	for _, l in item.bonusLines or {} do
		if type(l) == "table" and type(l.id) == "string" then table.insert(lines, { id = l.id }) end
	end
	local passives: { string } = {}
	for _, pid in item.bonusPassiveIds or {} do
		if type(pid) == "string" then table.insert(passives, pid) end
	end
	local used = linesBp(lines, passives)
	return { used = used, max = maxBudgetBp(item.rarityId, is2H(item), used, currentLevel()) }
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
	if newName then
		item.displayName = newName
	elseif #plan.lines == 0 and #plan.passives == 0 then
		item.displayName = nil -- no lines left (gf 84): plain base name, like a Common loot item
	end

	if _persistItem then
		_persistItem(playerId, item)
	end

	local gemCount = 0
	for _, n in plan.gems do gemCount += n end
	print(string.format("[RuneforgeService] FORGED %s %s -> %s | %d gem(s), %d replaced, %d removed | -%dg (forge %d, swap %d, catch-up %d, removal %d) -%d crystals | Runeforge L%d",
		tostring(item.instanceId), tostring(fromRarity), plan.newRarity, gemCount, #plan.replaced, #plan.removed,
		plan.gold, plan.forgeFee, plan.swapFee, plan.catchUp, plan.removalFee, plan.crystals, plan.runeforgeLevel))

	return true, { instanceId = item.instanceId, fromRarity = fromRarity, plan = plan }
end

--------------------------------------------------
-- SULFUR REROLLS (gf 54) — items above Epic
--
-- PAY FIRST (USER RULING 2026-11-07):
--   1. PayReroll: sulfur is debited, THEN the N sets are made (same seed as always: item ID +
--      reroll count + set number), the reroll count goes up by 1, and the sets are saved on the
--      item as item.pendingReroll = { sets = { { bonusLines, bonusPassiveIds, name } }, sulfur }.
--   2. CommitReroll: the player picks one of those saved sets (1..N) or keeps the current lines
--      (0). Either way the open choice is cleared. Nothing is charged here.
--   Leaving / rejoining in between shows the SAME saved sets again (SaveService keeps them).
--------------------------------------------------

-- PAY FIRST (USER RULING 2026-11-07):
--   1. PayReroll: sulfur is debited, THEN the N sets are made (same seed as always: item ID +
--      reroll count + set number), the reroll count goes up by 1, and the sets are saved on the
--      item as item.pendingReroll = { sets = { { bonusLines, bonusPassiveIds, name } }, sulfur }.
--   2. CommitReroll: the player picks one of those saved sets (1..N) or keeps the current lines
--      (0). Either way the open choice is cleared. Nothing is charged here.
--   Leaving / rejoining in between shows the SAME saved sets again (SaveService keeps them).

-- The open (paid, not yet chosen) reroll on this item, or nil.
local function pendingOf(item: any): any?
	local p = if type(item) == "table" then item.pendingReroll else nil
	if type(p) == "table" and type(p.sets) == "table" and #p.sets > 0 then return p end
	return nil
end

function RuneforgeService.HasPendingReroll(item: any): boolean
	return pendingOf(item) ~= nil
end

-- May a NEW reroll be paid for this item now? Returns { sulfur, setCount, runeforgeLevel } or
-- nil + reason. Pure: builds nothing, charges nothing.
local function rerollTerms(item: any)
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
			return nil, BuildingService.LockLine("Runeforge") -- approved lock line (guild_facilities 98)
		end
		return nil, `{rarity} rerolls need Runeforge L{REROLL_UNLOCK[rarity]} (yours is L{level})`
	end
	return { sulfur = sulfur, setCount = count, runeforgeLevel = level }
end

-- The N sets for the item's CURRENT reroll count (deterministic: gf 54 seed). Copies, so the
-- saved offer never shares tables with the generator. nil if a set cannot be built.
local function buildSets(item: any, count: number): { any }?
	local sets = {}
	for k = 1, count do
		local set = _itemGen.RollBonusSet(item.baseArchetypeId, item.itemLevel, item.rarityId, setSeed(item, k))
		if not set then
			return nil
		end
		local lines = {}
		for _, l in set.bonusLines or {} do
			if type(l) == "table" and type(l.id) == "string" then table.insert(lines, table.clone(l)) end
		end
		local passives = {}
		for _, pid in set.bonusPassiveIds or {} do
			if type(pid) == "string" then table.insert(passives, pid) end
		end
		table.insert(sets, {
			bonusLines = lines,
			bonusPassiveIds = passives,
			name = _itemGen.ComposeName(item.baseArchetypeId, lines, passives),
		})
	end
	return sets
end

-- What the Reroll tab shows. With an open choice: { pending = true, sets, sulfur, setCount }.
-- Without: { pending = false, sulfur, setCount } (NO sets: they exist only after paying).
-- nil + reason when the item cannot be rerolled at all.
function RuneforgeService.GetRerollOffer(item: any)
	local p = pendingOf(item)
	if p then
		return { pending = true, sets = p.sets, sulfur = tonumber(p.sulfur) or 0, setCount = #p.sets }
	end
	local terms, why = rerollTerms(item)
	if not terms then return nil, why end
	return { pending = false, sulfur = terms.sulfur, setCount = terms.setCount, runeforgeLevel = terms.runeforgeLevel }
end

-- Pay the sulfur, then make and save the sets. Returns ok, { setCount, rerollCount } | reason.
function RuneforgeService.PayReroll(playerId: string, item: any)
	if pendingOf(item) then
		return false, "Choose from the reroll you already paid for first"
	end
	local terms, why = rerollTerms(item)
	if not terms then
		return false, why or "Cannot reroll"
	end
	if not (_currency and _currency.Debit) then
		return false, "Currency path not wired"
	end
	if not (_inventory and _inventory.GetItem and _inventory.GetItem(playerId, item.instanceId) == item) then
		return false, "Item not owned"
	end
	-- Build first so a failure never costs sulfur; the player only SEES them after paying.
	local sets = buildSets(item, terms.setCount)
	if not sets then
		return false, "Could not build the reroll options -- nothing charged"
	end
	local paid, payWhy = _currency.Debit(playerId, { sulfur = terms.sulfur })
	if not paid then
		return false, `{tostring(payWhy or "Payment failed")} -- nothing charged`
	end

	item.pendingReroll = { sets = sets, sulfur = terms.sulfur }
	-- Every PAID reroll counts, also one that ends in 'Keep current' (gf 54).
	item.rerollCount = math.max(0, math.floor(tonumber(item.rerollCount) or 0)) + 1
	item.runeForged = true -- tracking tag only (USER DECISION 2026-11-01)

	if _persistItem then
		_persistItem(playerId, item)
	end

	print(string.format("[RuneforgeService] REROLL PAID %s (%s) | -%d sulfur | %d sets saved, waiting for a choice | reroll count %d",
		tostring(item.instanceId), tostring(item.rarityId), terms.sulfur, #sets, item.rerollCount))

	return true, { instanceId = item.instanceId, setCount = #sets, rerollCount = item.rerollCount }
end

-- Close the open choice: 0 = keep the current lines, 1..N = take that saved set. Charges
-- nothing (the sulfur was paid in PayReroll).
function RuneforgeService.CommitReroll(playerId: string, item: any, choice: any)
	local p = pendingOf(item)
	if not p then
		return false, "No paid reroll to choose from -- pay for a reroll first"
	end
	if type(choice) ~= "number" or choice ~= choice or choice % 1 ~= 0 or choice < 0 or choice > #p.sets then
		return false, "Invalid choice"
	end
	if not (_inventory and _inventory.GetItem and _inventory.GetItem(playerId, item.instanceId) == item) then
		return false, "Item not owned"
	end

	if choice > 0 then
		local set = p.sets[choice]
		local lines = {}
		for _, l in set.bonusLines or {} do table.insert(lines, table.clone(l)) end
		item.bonusLines = lines
		item.bonusPassiveIds = table.clone(set.bonusPassiveIds or {})
		if set.name then item.displayName = set.name end
	end
	item.pendingReroll = nil

	if _persistItem then
		_persistItem(playerId, item)
	end

	print(string.format("[RuneforgeService] REROLL CHOSEN %s (%s) | choice %d of %d%s | reroll count %d",
		tostring(item.instanceId), tostring(item.rarityId), choice, #p.sets,
		if choice == 0 then " (kept current)" else "", tonumber(item.rerollCount) or 0))

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
	local p = pendingOf(item)
	return {
		sulfur = if p then tonumber(p.sulfur) or sulfur else sulfur,
		setCount = if p then #p.sets else REROLL_SETS[item.rarityId][level],
		unlockLevel = REROLL_UNLOCK[item.rarityId],
		-- A paid reroll is waiting for a choice (USER RULING 2026-11-07).
		pending = p ~= nil,
	}
end

return RuneforgeService
