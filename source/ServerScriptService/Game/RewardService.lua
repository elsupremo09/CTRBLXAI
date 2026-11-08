-- RewardService.lua
-- CTRBLXAI | Slice 4D — Rewards, Inventory, and Loadout Management
--
-- Generates encounter-completion rewards after a qualifying victory.
-- Supports 5 reward categories: Equipment (40%), Skill Card (15%),
-- Augment Card (15%), Doctrine (5%), Consumable (25%).
--
-- Equipment rewards are committed directly to InventoryService.
-- Non-equipment rewards (cards) are returned uncommitted — Main.server
-- commits them to the appropriate inventory (cardInventory, etc.) and
-- sets result.committed = true before calling BuildRewardSummaries.
--
-- Item Level source: Map Level (owned by Slice 5).
-- Placeholder: mapLevel = 1 until Slice 5 provides authoritative value.

local ServerScriptService = game:GetService("ServerScriptService")
local Game = ServerScriptService:WaitForChild("Game")
local Content = game:GetService("ReplicatedStorage"):WaitForChild("Content")

local ItemGenerator    = require(Game:WaitForChild("ItemGenerator"))
local InventoryService = require(Game:WaitForChild("InventoryService"))
-- One source for weapon/off-hand passive names on every screen (2026-10-30).
local GearPassiveSummary = require(Game:WaitForChild("GearPassiveSummary"))

local BonusData       = require(Content:WaitForChild("BonusData"))
local WeaponData      = require(Content:WaitForChild("WeaponData"))
local ArmorData       = require(Content:WaitForChild("ArmorData"))
local SkillData       = require(Content:WaitForChild("SkillData"))
local AugmentData     = require(Content:WaitForChild("AugmentData"))
local DoctrineData    = require(Content:WaitForChild("DoctrineData"))
local ConsumableData  = require(Content:WaitForChild("ConsumableData"))

local RewardService = {}

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

-- Normal encounter category weights (user-defined)
local CATEGORY_WEIGHTS = {
	{ category = "Equipment",   weight = 0.40 },
	{ category = "SkillCard",   weight = 0.15 },
	{ category = "AugmentCard", weight = 0.15 },
	{ category = "Doctrine",    weight = 0.05 },
	{ category = "Consumable",  weight = 0.25 },
}

-- Equipment rarity weights (from DB loot_progression)
local NORMAL_RARITY_WEIGHTS = {
	{ rarity = "Common",    weight = 0.55   },
	{ rarity = "Uncommon",  weight = 0.2429 },
	{ rarity = "Rare",      weight = 0.1214 },
	{ rarity = "Epic",      weight = 0.0595 },
	{ rarity = "Exalted",   weight = 0.025  },
	{ rarity = "Legendary", weight = 0.0012 },
}

-- Rarity rank for card minimum clamping
local RARITY_RANK = {
	Common = 1, Uncommon = 2, Rare = 3,
	Epic = 4, Exalted = 5, Legendary = 6, Mythic = 7,
}

local MIN_REWARDS = 1
local MAX_REWARDS = 2

--------------------------------------------------
-- INTERNAL STATE
--------------------------------------------------

local processedOpportunities = {}
local _rewardSeedCounter = 0

local function generateRewardSeed()
	_rewardSeedCounter = _rewardSeedCounter + 1
	return os.clock() * 1000000 + _rewardSeedCounter
end

--------------------------------------------------
-- PER-BATTLE REWARD MODIFIER (Battlefield Events hook, 2026-10-04)
--
-- Set by BattlefieldEventService during a battle (Leprechaun / Gold Golem /
-- Crystal Golem / Doppelganger / Wandering Scholar / Wandering Mercenaries /
-- Wandering Monster) and read here at reward time. GenerateRewards' signature is
-- UNCHANGED — the modifier is module state. NIL-SAFE: with no modifier set every
-- multiplier is 1 and no rarity shift applies, i.e. identical to the pre-hook
-- behavior.
--
--   goldMult         multiplies battle gold
--   materialMult     multiplies battle materials
--   expMult          multiplies battle EXP
--   bonusRarityTiers shifts rolled reward rarity up N tiers (capped at Legendary)
--   minRarity        optional rarity floor (e.g. "Rare" = "guarantees Rare+ loot")
--
-- HONEST SCOPE: the gold / material / EXP economies (economy_framework,
-- materials_system, unit_progression) are DESIGNED in the DB but NOT yet built in
-- code — nothing in the game grants battle gold, materials or EXP today. The
-- multipliers are therefore stored and exposed (GetGoldMultiplier /
-- GetMaterialMultiplier / GetExpMultiplier / ApplyGold / ApplyMaterial /
-- ApplyExp) for those grant paths to read when they land, and are reported in
-- GenerateRewards' 3rd return value. The rarity shift/floor IS applied now to the
-- items/cards GenerateRewards actually produces.
--------------------------------------------------

local MAX_LOOT_RANK = 6  -- Legendary (highest rarity in NORMAL_RARITY_WEIGHTS)
local RANK_TO_RARITY = {
	[1] = "Common", [2] = "Uncommon", [3] = "Rare",
	[4] = "Epic", [5] = "Exalted", [6] = "Legendary",
}

local _rewardModifier = nil  -- nil = no modifier (all ×1)

local function numOr(v, default)
	if type(v) == "number" and v == v then return v end
	return default
end

-- Replace the active modifier. Missing fields default to neutral values.
function RewardService.SetRewardModifier(mult)
	if type(mult) ~= "table" then
		_rewardModifier = nil
		return
	end
	_rewardModifier = {
		goldMult         = math.max(0, numOr(mult.goldMult, 1)),
		materialMult     = math.max(0, numOr(mult.materialMult, 1)),
		expMult          = math.max(0, numOr(mult.expMult, 1)),
		bonusRarityTiers = math.max(0, math.floor(numOr(mult.bonusRarityTiers, 0))),
		minRarity        = (type(mult.minRarity) == "string" and RARITY_RANK[mult.minRarity]) and mult.minRarity or nil,
	}
	print(string.format("[RewardService] Reward modifier set | gold x%.2f material x%.2f exp x%.2f rarity +%d min=%s",
		_rewardModifier.goldMult, _rewardModifier.materialMult, _rewardModifier.expMult,
		_rewardModifier.bonusRarityTiers, tostring(_rewardModifier.minRarity)))
end

function RewardService.ClearRewardModifier()
	_rewardModifier = nil
end

-- Copy of the active modifier (always a full table; neutral values when unset).
function RewardService.GetRewardModifier()
	local m = _rewardModifier
	return {
		goldMult         = m and m.goldMult or 1,
		materialMult     = m and m.materialMult or 1,
		expMult          = m and m.expMult or 1,
		bonusRarityTiers = m and m.bonusRarityTiers or 0,
		minRarity        = m and m.minRarity or nil,
	}
end

function RewardService.GetGoldMultiplier() return _rewardModifier and _rewardModifier.goldMult or 1 end
function RewardService.GetMaterialMultiplier() return _rewardModifier and _rewardModifier.materialMult or 1 end
function RewardService.GetExpMultiplier() return _rewardModifier and _rewardModifier.expMult or 1 end

-- Victory loot COUNT RANGE (min,max) without rolling the RNG. Used by the live
-- Map Details panel to show "Loot on victory: 1-2 items" honestly — the exact
-- count is a seeded roll done only at battle end (determinism), so the live
-- panel shows the range, never a pre-rolled number. (2026-10-17)
function RewardService.GetRewardCountRange()
	return MIN_REWARDS, MAX_REWARDS
end

-- Convenience for the (future) gold / material / EXP grant paths.
function RewardService.ApplyGold(amount)
	return math.floor(numOr(amount, 0) * RewardService.GetGoldMultiplier() * RewardService.GetFortuneGoldMultiplier())
end
function RewardService.ApplyMaterial(amount)
	return math.floor(numOr(amount, 0) * RewardService.GetMaterialMultiplier())
end
function RewardService.ApplyExp(amount)
	return math.floor(numOr(amount, 0) * RewardService.GetExpMultiplier())
end

-- Apply the rarity shift / floor to a rolled rarity. No modifier -> unchanged.
local function applyRarityModifier(rarity)
	local m = _rewardModifier
	if not m then return rarity end
	local rank = RARITY_RANK[rarity]
	if rank == nil then return rarity end
	rank = rank + (m.bonusRarityTiers or 0)
	if m.minRarity and RARITY_RANK[m.minRarity] then
		rank = math.max(rank, RARITY_RANK[m.minRarity])
	end
	rank = math.clamp(rank, 1, MAX_LOOT_RANK)
	return RANK_TO_RARITY[rank] or rarity
end

--------------------------------------------------
-- WEIGHTED ROLL HELPER
--------------------------------------------------

local function weightedRoll(rng, entries, keyField, weightField)
	local total = 0
	for _, e in ipairs(entries) do
		total = total + e[weightField]
	end
	local roll = rng:NextNumber() * total
	local cum = 0
	for _, e in ipairs(entries) do
		cum = cum + e[weightField]
		if roll <= cum then
			return e[keyField]
		end
	end
	return entries[1][keyField]
end

--------------------------------------------------
-- EXPEDITION FORTUNE (loot_progression, 2026-10-23)
--
-- Module state, mirroring the reward modifier above. Set from the deployed team's
-- post-gear Fortune before reward generation; neutral (0) when unset -> Fortune
-- Multiplier 1.0, no change. Drives per-rarity Adjusted Weights (equipment only)
-- and the Fortune Gold Multiplier. Mythic+ stay ineligible in normal encounters
-- (absent from NORMAL_RARITY_WEIGHTS); zero base weight stays zero.
--------------------------------------------------

local _expeditionFortune = 0  -- 0 .. 1.75

-- Per-rarity Fortune sensitivity (loot_progression "Fortune Sensitivity").
local RARITY_FORTUNE_SENSITIVITY = {
	Common = 0, Uncommon = 0.25, Rare = 0.5, Epic = 0.75, Exalted = 0.85, Legendary = 1, Mythic = 1,
}

-- Unit Fortune = LUK/(LUK+200) + summed gear Fortune (additive, DB). Floored at 0.
local function unitFortune(u)
	local luk = (u.effectiveStats and u.effectiveStats.LUK) or 10
	local lukFortune = luk / (luk + 200)
	local gearFortune = (u.gearDerived and u.gearDerived.fortune) or 0
	return math.max(0, lukFortune + gearFortune)
end

-- Expedition Fortune = top Unit Fortune + 50% 2nd + 25% 3rd across the deployed
-- player team (DB). Summons excluded. Returns 0 for an empty team.
function RewardService.ComputeExpeditionFortune(units)
	local fortunes = {}
	for _, u in ipairs(units or {}) do
		if u and (u.side == "Player" or u.controller == "Player") and not u.isSummon then
			fortunes[#fortunes + 1] = unitFortune(u)
		end
	end
	table.sort(fortunes, function(a, b) return a > b end)
	return (fortunes[1] or 0) + 0.5 * (fortunes[2] or 0) + 0.25 * (fortunes[3] or 0)
end

function RewardService.SetExpeditionFortune(fortune)
	if type(fortune) == "number" and fortune == fortune then
		_expeditionFortune = math.clamp(fortune, 0, 1.75)
	else
		_expeditionFortune = 0
	end
end

function RewardService.ClearExpeditionFortune()
	_expeditionFortune = 0
end

-- Read-only getter (Treasure Hunter, project_rules 227): lets a caller roll at neutral
-- Fortune and then restore exactly what was set. Pure read; changes nothing.
function RewardService.GetExpeditionFortune()
	return _expeditionFortune
end

-- Normalized Expedition Fortune = Expedition Fortune / 1.75 (0 .. 1).
local function normalizedExpeditionFortune()
	return _expeditionFortune / 1.75
end

-- Fortune Gold Multiplier = 1 + 0.50 x Normalized Expedition Fortune (<= 1.50).
function RewardService.GetFortuneGoldMultiplier()
	return 1 + 0.50 * normalizedExpeditionFortune()
end

-- Roll equipment rarity with Fortune quality weighting (loot_progression id 16):
-- Adjusted Weight = Base x (1 + NormExpFortune x Sensitivity[rarity]). Zero base
-- stays zero; no Fortune -> plain base roll. Mythic+ absent from the table so they
-- remain impossible in normal encounters.
local function rollEquipmentRarity(rng)
	local nf = normalizedExpeditionFortune()
	if nf <= 0 then
		return weightedRoll(rng, NORMAL_RARITY_WEIGHTS, "rarity", "weight")
	end
	local adjusted = {}
	for _, e in ipairs(NORMAL_RARITY_WEIGHTS) do
		local sens = RARITY_FORTUNE_SENSITIVITY[e.rarity] or 0
		local w = e.weight * (1 + nf * sens)
		if w < 0 then w = 0 end
		adjusted[#adjusted + 1] = { rarity = e.rarity, weight = w }
	end
	return weightedRoll(rng, adjusted, "rarity", "weight")
end

-- Card rarity: roll equipment weights but clamp to Rare minimum
-- per DB: "Normal Skill Card rarity begins at Rare"
local function rollCardRarity(rng)
	local base = weightedRoll(rng, NORMAL_RARITY_WEIGHTS, "rarity", "weight")
	if (RARITY_RANK[base] or 0) < 3 then
		return applyRarityModifier("Rare")
	end
	-- Battlefield-event rarity shift/floor (nil modifier -> unchanged).
	return applyRarityModifier(base)
end

--------------------------------------------------
-- POOL BUILDERS (cached)
--------------------------------------------------

local cachedEquipPool = nil
local cachedSkillPool = nil
local cachedAugmentPool = nil
local cachedDoctrinePool = nil
local cachedConsumablePool = nil

local function getEquipPool()
	if cachedEquipPool then return cachedEquipPool end
	local pool = {}
	for id, def in pairs(WeaponData.Archetypes) do
		if def.category == "Weapon" or def.category == "OffHand" then
			table.insert(pool, id)
		end
	end
	for id, def in pairs(ArmorData.Archetypes) do
		if def.category == "Armor" then
			table.insert(pool, id)
		end
	end
	table.sort(pool)
	cachedEquipPool = pool
	return pool
end

local function getSkillPool()
	if cachedSkillPool then return cachedSkillPool end
	local pool = {}
	for id, def in pairs(SkillData) do
		-- Event-only skills (EVT-, e.g. the Chaos Necromancer's Raise Dead) are never loot.
		if type(def) == "table" and def.name and string.sub(id, 1, 4) ~= "EVT-" then
			table.insert(pool, id)
		end
	end
	table.sort(pool)
	cachedSkillPool = pool
	return pool
end

local function getAugmentPool()
	if cachedAugmentPool then return cachedAugmentPool end
	local pool = {}
	for id, def in pairs(AugmentData) do
		if type(def) == "table" and def.name then
			table.insert(pool, id)
		end
	end
	table.sort(pool)
	cachedAugmentPool = pool
	return pool
end

local function getDoctrinePool()
	if cachedDoctrinePool then return cachedDoctrinePool end
	local pool = {}
	for id, def in pairs(DoctrineData) do
		if type(def) == "table" and def.name then
			table.insert(pool, id)
		end
	end
	table.sort(pool)
	cachedDoctrinePool = pool
	return pool
end

local function getConsumablePool()
	if cachedConsumablePool then return cachedConsumablePool end
	local pool = {}
	-- Parked items (DB Status PARKED, user 2026-10-27) never drop as rewards.
	for _, cid in ipairs(ConsumableData.GetAllIds()) do
		local d = ConsumableData.GetById(cid)
		if d and not d.parked then table.insert(pool, cid) end
	end
	table.sort(pool)
	cachedConsumablePool = pool
	return pool
end

--------------------------------------------------
-- BOSS REWARD (daily systems decision 8, USER DECISION 2026-11-01; loot_progression 15/25/43,
-- materials_system 41). Main calls these only for one of the first 3 boss wins of the real day.
--   RollBossItem: the guaranteed Rare-or-better item, Mythic max. DECIDED (DEV DEFAULT): the
--     Elite-encounter rarity column (loot_progression 48-55, the same Mythic-max ceiling; Exalted
--     0.025 as in the normal table) limited to Rare and above, then the same Fortune quality
--     weighting as normal equipment: Rare 61% / Epic 23% / Exalted 8% / Legendary 7% / Mythic 0.3%.
--   RollRuneGem: one bonus line of an Epic item of the content level (Rare item below L40),
--     random slot (materials_system 41). Returns the gem id (attribute or passive id).
-- Neither commits anything; Main adds the item with the victory loot and credits the gem.
--------------------------------------------------

local BOSS_RARITY_WEIGHTS = {
	{ rarity = "Rare",      weight = 0.18163636 },
	{ rarity = "Epic",      weight = 0.06962727 },
	{ rarity = "Exalted",   weight = 0.025 },
	{ rarity = "Legendary", weight = 0.02018182 },
	{ rarity = "Mythic",    weight = 0.00100909 },
}

function RewardService.RollBossItem(mapLevel: number)
	local seed = generateRewardSeed()
	local rng = Random.new(seed)
	local nf = normalizedExpeditionFortune()
	local weights = {}
	for _, e in ipairs(BOSS_RARITY_WEIGHTS) do
		local sens = RARITY_FORTUNE_SENSITIVITY[e.rarity] or 0
		weights[#weights + 1] = { rarity = e.rarity, weight = e.weight * (1 + nf * sens) }
	end
	local rarity = weightedRoll(rng, weights, "rarity", "weight")
	local item, err = ItemGenerator.GenerateFromPool(getEquipPool(), math.max(1, math.floor(mapLevel)), rarity, seed, "Boss")
	if not item and rarity == "Mythic" then
		-- Fallback if a Mythic cannot be built for this archetype/level: the next rarity down.
		item, err = ItemGenerator.GenerateFromPool(getEquipPool(), math.max(1, math.floor(mapLevel)), "Legendary", seed, "Boss")
	end
	print(string.format("[RewardService] Boss reward item: %s %s", tostring(rarity),
		if item then tostring(item.displayName or item.instanceId) else ("FAILED " .. tostring(err))))
	return item, err
end

function RewardService.RollRuneGem(mapLevel: number, rarityOverride: string?): string?
	local level = math.max(1, math.floor(mapLevel))
	local rarity = rarityOverride or (if level < 40 then "Rare" else "Epic")
	local seed = generateRewardSeed()
	local item = ItemGenerator.GenerateFromPool(getEquipPool(), level, rarity, seed, "BossGem")
	if not item then return nil end
	local ids = {}
	for _, line in ipairs(item.bonusLines or {}) do
		if type(line) == "table" and type(line.id) == "string" then table.insert(ids, line.id) end
	end
	for _, pid in ipairs(item.bonusPassiveIds or {}) do
		if type(pid) == "string" then table.insert(ids, pid) end
	end
	if #ids == 0 then return nil end
	return ids[Random.new(seed + 1):NextInteger(1, #ids)]
end

-- ELITE REWARD (loot_progression 26/70/71; daily systems decision 12): each won elite encounter
-- gives ONE elite reward opportunity: chance = min(95%, 75% x Fortune Multiplier) (Fortune
-- Multiplier = 1 + Normalized Expedition Fortune, loot_progression 12), then an equipment item
-- from the Elite-encounter rarity table (loot_progression 48-55, Mythic max; Exalted 0.025 as in
-- the normal table) with the normal Fortune quality weighting. Returns the item (not committed)
-- or nil when the chance roll fails.
local ELITE_RARITY_WEIGHTS = {
	{ rarity = "Common",    weight = 0.42 },
	{ rarity = "Uncommon",  weight = 0.28254545 },
	{ rarity = "Rare",      weight = 0.18163636 },
	{ rarity = "Epic",      weight = 0.06962727 },
	{ rarity = "Exalted",   weight = 0.025 },
	{ rarity = "Legendary", weight = 0.02018182 },
	{ rarity = "Mythic",    weight = 0.00100909 },
}

function RewardService.RollEliteReward(mapLevel: number)
	local seed = generateRewardSeed()
	local rng = Random.new(seed)
	local nf = normalizedExpeditionFortune()
	local chance = math.min(0.95, 0.75 * (1 + nf))
	if rng:NextNumber() >= chance then
		print(string.format("[RewardService] Elite reward chance %.0f%% missed", chance * 100))
		return nil
	end
	local weights = {}
	for _, e in ipairs(ELITE_RARITY_WEIGHTS) do
		local sens = RARITY_FORTUNE_SENSITIVITY[e.rarity] or 0
		weights[#weights + 1] = { rarity = e.rarity, weight = e.weight * (1 + nf * sens) }
	end
	local rarity = weightedRoll(rng, weights, "rarity", "weight")
	local level = math.max(1, math.floor(mapLevel))
	local item, err = ItemGenerator.GenerateFromPool(getEquipPool(), level, rarity, seed, "Elite")
	if not item and rarity == "Mythic" then
		item, err = ItemGenerator.GenerateFromPool(getEquipPool(), level, "Legendary", seed, "Elite")
	end
	print(string.format("[RewardService] Elite reward item (chance %.0f%%): %s %s", chance * 100, tostring(rarity),
		if item then tostring(item.displayName or item.instanceId) else ("FAILED " .. tostring(err))))
	return item
end

--------------------------------------------------
-- PUBLIC: GenerateRewards
--
-- Returns:
--   results: array of reward entries (see below)
--   equipCommitted: number of equipment items committed to InventoryService
--
-- Each result entry:
--   Equipment:     { category="Equipment", item=instance, committed=bool }
--   Non-equipment: { category=string, cardData={id,name,desc,...}, committed=false }
--
-- Main.server commits non-equipment rewards and sets committed=true
-- before calling BuildRewardSummaries.
--------------------------------------------------

function RewardService.GenerateRewards(playerId, mapLevel, opportunityId, opts)
	assert(type(playerId) == "string", "RewardService: playerId required")
	assert(type(mapLevel) == "number" and mapLevel >= 1, "RewardService: mapLevel must be >= 1")
	assert(type(opportunityId) == "string", "RewardService: opportunityId required")

	if processedOpportunities[opportunityId] then
		warn("[RewardService] Duplicate opportunity rejected: " .. opportunityId)
		return {}, 0
	end
	processedOpportunities[opportunityId] = true

	local rng = Random.new(generateRewardSeed())
	local rewardCount = rng:NextInteger(MIN_REWARDS, MAX_REWARDS)

	-- Optional caller overrides (additive; existing callers pass nothing and keep
	-- the original behavior). opts.count forces an exact roll count; opts.allowedCategories
	-- restricts which categories can roll — used by objective rewards, which are
	-- gear/skill/augment only (consumables + doctrines excluded, user-locked 2026-10-24).
	local categoryWeights = CATEGORY_WEIGHTS
	-- Treasure Hunter augment (2026-10-25): opts.bonusRarityTiers bumps each equipment drop's
	-- rarity by N tiers for THIS generation only (no global modifier slot touched, so it never
	-- contends with battlefield-event reward modifiers). Default 0 = unchanged.
	local bonusRarityTiers = (type(opts) == "table" and tonumber(opts.bonusRarityTiers)) or 0
	-- Treasure Hunter (project_rules 227, 2026-10-28): opts.noCommit = true rolls and RETURNS the
	-- results without committing anything (equipment is NOT added to the inventory; every entry
	-- comes back committed=false). Default false = existing callers unchanged.
	local noCommit = type(opts) == "table" and opts.noCommit == true
	if type(opts) == "table" then
		if type(opts.count) == "number" and opts.count >= 0 then
			rewardCount = math.floor(opts.count)
		end
		if type(opts.allowedCategories) == "table" then
			local allow = {}
			for _, c in ipairs(opts.allowedCategories) do allow[c] = true end
			local filtered = {}
			for _, entry in ipairs(CATEGORY_WEIGHTS) do
				if allow[entry.category] then filtered[#filtered + 1] = entry end
			end
			if #filtered > 0 then categoryWeights = filtered end
		end
	end

	print(string.format(
		"[RewardService] Generating %d reward(s) for %s | MapLevel=%d | OpportunityId=%s",
		rewardCount, playerId, mapLevel, opportunityId
	))

	local results = {}
	local equipCommitted = 0

	for i = 1, rewardCount do
		local seed = generateRewardSeed()
		local itemRng = Random.new(seed)

		-- Step 1: Roll reward category (restricted set when opts.allowedCategories given)
		local category = weightedRoll(itemRng, categoryWeights, "category", "weight")

		if category == "Equipment" then
			-- Battlefield-event rarity shift/floor (nil modifier -> unchanged).
			local rarity = applyRarityModifier(rollEquipmentRarity(itemRng))
			-- Treasure Hunter per-call tier bump (2026-10-25): raise rank, clamp to max.
			if bonusRarityTiers > 0 then
				local rk = RARITY_RANK[rarity]
				if rk then rarity = RANK_TO_RARITY[math.clamp(rk + bonusRarityTiers, 1, MAX_LOOT_RANK)] or rarity end
			end
			local pool = getEquipPool()
			local item, genErr = ItemGenerator.GenerateFromPool(pool, mapLevel, rarity, seed, "Loot")
			if not item then
				warn(string.format("[RewardService] Equipment gen failed %d: %s", i, genErr or "unknown"))
				table.insert(results, {
					category = "Equipment", committed = false,
					error = genErr or "Generation failed",
				})
			elseif noCommit then
				-- Rolled but held (Treasure Hunter): nothing enters the inventory here.
				print(string.format("[RewardService] Reward %d: Equipment %s HELD (noCommit)", i, tostring(item.instanceId)))
				table.insert(results, { category = "Equipment", item = item, committed = false })
			else
				local ok, addErr = InventoryService.AddItem(playerId, item, { markNew = true })
				if ok then
					equipCommitted = equipCommitted + 1
					local arch = WeaponData.GetByArchetypeId(item.baseArchetypeId)
						or ArmorData.GetByArchetypeId(item.baseArchetypeId)
					print(string.format("[RewardService] Reward %d: Equipment %s | %s L%d %s",
						i, item.instanceId, arch and arch.name or "?",
						item.itemLevel or 0, item.rarityId or "?"))
					table.insert(results, {
						category = "Equipment", item = item, committed = true,
					})
				else
					warn(string.format("[RewardService] Equipment commit failed %d: %s", i, addErr or "unknown"))
					table.insert(results, {
						category = "Equipment", item = item, committed = false,
						error = addErr or "Commit failed",
					})
				end
			end

		elseif category == "SkillCard" then
			local pool = getSkillPool()
			local skillId = pool[itemRng:NextInteger(1, #pool)]
			local def = SkillData[skillId]
			local rarity = rollCardRarity(itemRng)
			print(string.format("[RewardService] Reward %d: SkillCard %s (%s) [%s]",
				i, skillId, def and def.name or "?", rarity))
			table.insert(results, {
				category = "SkillCard", committed = false,
				cardData = {
					id = skillId,
					name = def and def.name or skillId,
					icon = def and def.icon or nil,
					desc = def and def.description or "",
					rarity = rarity,
					mpCost = def and def.mpCost,
					element = def and def.element,
					tags = def and def.tags,
				},
			})

		elseif category == "AugmentCard" then
			local pool = getAugmentPool()
			local augId = pool[itemRng:NextInteger(1, #pool)]
			local def = AugmentData[augId]
			local rarity = rollCardRarity(itemRng)
			print(string.format("[RewardService] Reward %d: AugmentCard %s (%s) [%s]",
				i, augId, def and def.name or "?", rarity))
			table.insert(results, {
				category = "AugmentCard", committed = false,
				cardData = {
					id = augId,
					name = def and def.name or augId,
					icon = def and def.icon or nil,
					desc = def and def.description or "",
					rarity = rarity,
					family = def and def.family,
				},
			})

		elseif category == "Doctrine" then
			local pool = getDoctrinePool()
			local docId = pool[itemRng:NextInteger(1, #pool)]
			local def = DoctrineData[docId]
			local rarity = rollCardRarity(itemRng)
			print(string.format("[RewardService] Reward %d: Doctrine %s (%s) [%s]",
				i, docId, def and def.name or "?", rarity))
			table.insert(results, {
				category = "Doctrine", committed = false,
				cardData = {
					id = docId,
					name = def and def.name or docId,
					icon = def and def.icon or nil,
					desc = def and def.identity or "",
					rarity = rarity,
					passiveName = def and def.passiveName,
					passiveEffect = def and def.passiveEffect,
				},
			})

		elseif category == "Consumable" then
			local pool = getConsumablePool()
			local conId = pool[itemRng:NextInteger(1, #pool)]
			local def = ConsumableData.GetById(conId)
			local rarity = applyRarityModifier(weightedRoll(itemRng, NORMAL_RARITY_WEIGHTS, "rarity", "weight"))
			print(string.format("[RewardService] Reward %d: Consumable %s (%s) [%s]",
				i, conId, def and def.name or "?", rarity))
			table.insert(results, {
				category = "Consumable", committed = false,
				cardData = {
					id = conId,
					name = def and def.name or conId,
					icon = def and def.icon or nil,
					-- Player-facing text first; rule text only as fallback (2026-10-30).
					desc = def and (def.displayText or def.effectFormula) or "",
					rarity = rarity,
					conCategory = def and def.category or "Unknown",
					maxCharges = def and def.maxCharges or 1,
				},
			})
		end
	end

	print(string.format("[RewardService] Done: %d equipment committed, %d total for %s",
		equipCommitted, #results, playerId))

	-- 3rd return (additive; existing callers ignore it): the battlefield-event
	-- reward modifier in effect for this generation (gold/material/EXP multipliers
	-- for the not-yet-built currency grant paths). Neutral values when unset.
	local appliedModifier = RewardService.GetRewardModifier()
	print(string.format("[RewardService] Modifier in effect | gold x%.2f material x%.2f exp x%.2f rarity +%d min=%s",
		appliedModifier.goldMult, appliedModifier.materialMult, appliedModifier.expMult,
		appliedModifier.bonusRarityTiers, tostring(appliedModifier.minRarity)))
	return results, equipCommitted, appliedModifier
end

--------------------------------------------------
-- PUBLIC: BuildRewardSummaries
--
-- Converts committed results into client-safe payload.
-- Call AFTER Main commits non-equipment rewards.
--
-- Equipment:     full stat block (weapon/armor fields)
-- Non-equipment: card display fields (name, desc, category, rarity)
--------------------------------------------------

local BONUS_DISPLAY_KEY = {
	STR = "STR", AGI = "AGI", INT = "INT", VIT = "VIT", DEX = "DEX", LUK = "LUK",
	damage = "Attack", defense = "Defense", rtDelay = "RT Delay", hp = "HP", mp = "MP", wt = "WT",
	precision = "Precision", evasiveness = "Evasiveness", fortune = "Fortune", skillPotency = "Skill Potency",
	healingOutput = "Healing", debuffResist = "Debuff Resist", rtDelayResist = "RT Delay Resist",
}

local function resolveItemBonuses(item)
	local stats = {}
	local passives = {}

	for _, line in ipairs(item.bonusLines or {}) do
		local attr = BonusData.NumericalAttributes[line.id]
		if attr then
			local key = BONUS_DISPLAY_KEY[attr.stat] or attr.family
			local value = 0

			if attr.operation == "PrimaryStat" or attr.operation == "BaseItemStat" then
				local scale = WeaponData.GetScale(item.itemLevel or 1)
				value = math.round((attr.l99Flat or 0) * scale)
			elseif attr.operation == "WeightReduce" then
				local scale = WeaponData.GetScale(item.itemLevel or 1)
				value = -math.round((attr.l99Flat or 0) * scale)
			elseif attr.operation == "Derived" then
				value = math.round((attr.fixedValue or 0) * 100)
			elseif attr.operation == "DerivedMultiplier" then
				value = math.round(((attr.fixedValue or 1) - 1) * 100)
			else
				local scale = WeaponData.GetScale(item.itemLevel or 1)
				value = math.round((attr.l99Flat or 0) * scale)
			end

			if value ~= 0 then
				stats[key] = (stats[key] or 0) + value
			end
		end
	end

	for _, passiveId in ipairs(item.bonusPassiveIds or {}) do
		local passive = BonusData.BonusPassives[passiveId]
		if passive then
			table.insert(passives, { name = passive.name or passiveId, icon = "[*]", desc = passive.desc or "" })
		end
	end

	return stats, passives
end

function RewardService.BuildRewardSummaries(results)
	local summaries = {}
	for _, result in ipairs(results) do
		if not result.committed then
			-- Skip uncommitted (failed) results
		elseif result.category == "Equipment" and result.item then
			-- Equipment summary (full stat block)
			local item = result.item
			local archetype = WeaponData.GetByArchetypeId(item.baseArchetypeId)
			local isArmor = false
			if not archetype then
				archetype = ArmorData.GetByArchetypeId(item.baseArchetypeId)
				isArmor = true
			end
			local profile = isArmor
				and ArmorData.GetScaledProfile(item.baseArchetypeId, item.itemLevel)
				or WeaponData.GetScaledProfile(item.baseArchetypeId, item.itemLevel)

			local summary = {
				name = item.displayName or (archetype and archetype.name) or "Unknown",
				icon = archetype and archetype.icon or nil,
				flavor = archetype and archetype.flavor or nil,
				rarity = item.rarityId,
				itemLevel = item.itemLevel,
				category = "Equipment",
				isCard = false,
				stolen = result.stolen or false,  -- Steal/Mug provenance -> client STOLEN badge (2026-10-24)
				chestReward = result.chestReward or false,  -- chest / salvage loot -> client CHEST badge (2026-11-01)
				wt = profile and profile.wt or 0,
				defense = profile and profile.defense or 0,
				bonusCount = #item.bonusLines,
				passiveCount = #item.bonusPassiveIds,
				isWeapon = not isArmor and archetype and archetype.category == "Weapon" or false,
				isArmor = isArmor,
				damage = (not isArmor) and (profile and profile.damage or 0) or 0,
				rtDelay = (not isArmor) and (profile and profile.rtDelay or 0) or 0,
				minRange = (not isArmor) and (profile and profile.minRange or 1) or 0,
				maxRange = (not isArmor) and (profile and profile.maxRange or 1) or 0,
				handClass = (not isArmor) and (archetype and archetype.handClass or "1H") or nil,
				equipCategory = archetype and (isArmor and "Armor" or archetype.category) or "Unknown",
				nativePassiveId = (not isArmor) and (archetype and archetype.nativePassiveId or nil) or nil,
				nativePassiveName = (not isArmor) and (archetype and archetype.nativePassiveId
					and GearPassiveSummary.NativePassiveName(archetype.nativePassiveId) or nil) or nil,
				nativePassiveDesc = (not isArmor) and (archetype and WeaponData.GetPassiveDesc(archetype.nativePassiveId) or nil) or nil,
				projectileType = (not isArmor) and (archetype and archetype.projectileType or nil) or nil,
				element = (not isArmor) and WeaponData.GetInstanceElement(item) or nil,
				hp = isArmor and (profile and profile.hp or 0) or nil,
				mp = isArmor and (profile and profile.mp or 0) or nil,
				slot = isArmor and (archetype and archetype.slot or nil) or nil,
				-- Display name/text (internal passiveName stays the rules key). 2026-10-31.
				passiveName = isArmor and (GearPassiveSummary.ArmorPassiveDisplay(archetype)) or nil,
				passiveDesc = isArmor and select(2, GearPassiveSummary.ArmorPassiveDisplay(archetype)) or nil,
				bonusStats = nil,
				bonusPassives = nil,
			}
			summary.bonusStats, summary.bonusPassives = resolveItemBonuses(item)
			table.insert(summaries, summary)

		elseif result.cardData then
			-- Non-equipment card summary
			local cd = result.cardData
			table.insert(summaries, {
				name = cd.name or "Unknown",
				icon = cd.icon or nil,
				category = result.category,
				rarity = cd.rarity or "Common",
				isCard = true,
				stolen = result.stolen or false,  -- Treasure Hunter recovered loot -> STOLEN badge (2026-10-28)
				chestReward = result.chestReward or false,  -- chest / salvage loot -> client CHEST badge (2026-11-01)
				cardId = cd.id,
				desc = cd.desc or "",
				-- Skill-specific
				mpCost = cd.mpCost,
				element = cd.element,
				tags = cd.tags,
				-- Augment-specific
				family = cd.family,
				-- Doctrine-specific
				passiveName = cd.passiveName,
				passiveEffect = cd.passiveEffect,
				-- Consumable-specific
				conCategory = cd.conCategory,
				maxCharges = cd.maxCharges,
			})
		end
	end
	return summaries
end

--------------------------------------------------
-- PUBLIC: ClearOpportunity
-- For testing/debug: allow re-processing of an opportunity
--------------------------------------------------

function RewardService.ClearOpportunity(opportunityId)
	processedOpportunities[opportunityId] = nil
end

return RewardService
