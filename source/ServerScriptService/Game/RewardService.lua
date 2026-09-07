-- RewardService.lua
-- CTRBLXAI | Slice 4D — Rewards, Inventory, and Loadout Management
--
-- Generates encounter-completion rewards after a qualifying victory.
-- Commits rewards to InventoryService before export/save.
--
-- Slice 4 owns this pipeline for all loot drops (equips, consumables,
-- doctrines, skill cards, augment cards). Currently only equip drops
-- are implemented.
--
-- Item Level source: Map Level (owned by Slice 5).
-- Placeholder: mapLevel = 1 until Slice 5 provides authoritative value.
--
-- Non-atomic: items are committed one at a time. No rollback.
-- Insertion failures are handled explicitly per item.

local ServerScriptService = game:GetService("ServerScriptService")
local Game = ServerScriptService:WaitForChild("Game")

local ItemGenerator    = require(Game:WaitForChild("ItemGenerator"))
local InventoryService = require(Game:WaitForChild("InventoryService"))

local BonusData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("BonusData")
)
local WeaponData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("WeaponData")
)
local ArmorData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("ArmorData")
)

local RewardService = {}

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

-- Normal Encounter rarity weights (from loot_progression table)
local NORMAL_RARITY_WEIGHTS = {
	{ rarity = "Broken",    weight = 0.10  },
	{ rarity = "Common",    weight = 0.55  },
	{ rarity = "Uncommon",  weight = 0.20  },
	{ rarity = "Rare",      weight = 0.10  },
	{ rarity = "Epic",      weight = 0.049 },
	{ rarity = "Legendary", weight = 0.001 },
	-- Mythic, Transcendent, Unique: weight 0 for normal encounters
}

-- Number of reward items per qualifying victory
local MIN_REWARDS = 1
local MAX_REWARDS = 2

--------------------------------------------------
-- INTERNAL STATE
--------------------------------------------------

-- Tracks processed opportunity IDs to prevent duplicate rewards
-- opportunityId -> true
local processedOpportunities = {}

--------------------------------------------------
-- SEED GENERATION
--------------------------------------------------

local _rewardSeedCounter = 0

local function generateRewardSeed()
	_rewardSeedCounter = _rewardSeedCounter + 1
	return os.clock() * 1000000 + _rewardSeedCounter
end

--------------------------------------------------
-- RARITY ROLL
--------------------------------------------------

local function rollRarity(rng)
	local totalWeight = 0
	for _, entry in ipairs(NORMAL_RARITY_WEIGHTS) do
		totalWeight = totalWeight + entry.weight
	end

	local roll = rng:NextNumber() * totalWeight
	local cumulative = 0
	for _, entry in ipairs(NORMAL_RARITY_WEIGHTS) do
		cumulative = cumulative + entry.weight
		if roll <= cumulative then
			return entry.rarity
		end
	end
	return "Common" -- fallback
end

--------------------------------------------------
-- ARCHETYPE POOL
--------------------------------------------------

local cachedArchetypePool = nil

local function getArchetypePool()
	if cachedArchetypePool then
		return cachedArchetypePool
	end
	local pool = {}
	-- Weapon + OffHand archetypes
	for archetypeId, def in pairs(WeaponData.Archetypes) do
		if def.category == "Weapon" or def.category == "OffHand" then
			table.insert(pool, archetypeId)
		end
	end
	-- Armor archetypes (Slice 4G)
	for archetypeId, def in pairs(ArmorData.Archetypes) do
		if def.category == "Armor" then
			table.insert(pool, archetypeId)
		end
	end
	table.sort(pool) -- deterministic order
	cachedArchetypePool = pool
	return pool
end

--------------------------------------------------
-- PUBLIC: GenerateRewards
--
-- Called after qualifying victory, before export/save.
--
-- Input:
--   playerId: string
--   mapLevel: number (from Slice 5; placeholder 1 for now)
--   opportunityId: string (unique per battle, prevents duplicates)
--
-- Returns:
--   results: { { item = itemInstance, committed = bool, error = string? }, ... }
--   count: number of successfully committed items
--------------------------------------------------

function RewardService.GenerateRewards(playerId, mapLevel, opportunityId)
	assert(type(playerId) == "string", "RewardService: playerId required")
	assert(type(mapLevel) == "number" and mapLevel >= 1, "RewardService: mapLevel must be >= 1")
	assert(type(opportunityId) == "string", "RewardService: opportunityId required")

	-- Idempotency: process each opportunity exactly once
	if processedOpportunities[opportunityId] then
		warn("[RewardService] Duplicate opportunity rejected: " .. opportunityId)
		return {}, 0
	end
	processedOpportunities[opportunityId] = true

	local rng = Random.new(generateRewardSeed())
	local rewardCount = rng:NextInteger(MIN_REWARDS, MAX_REWARDS)
	local pool = getArchetypePool()

	print(string.format(
		"[RewardService] Generating %d reward(s) for %s | MapLevel=%d | OpportunityId=%s",
		rewardCount, playerId, mapLevel, opportunityId
	))

	local results = {}
	local committedCount = 0

	for i = 1, rewardCount do
		local seed = generateRewardSeed()
		local itemRng = Random.new(seed)

		-- Roll rarity
		local rarity = rollRarity(itemRng)

		-- Generate item
		local item, genErr = ItemGenerator.GenerateFromPool(
			pool,
			mapLevel,  -- Item Level = Map Level
			rarity,
			seed,
			"Loot"
		)

		if not item then
			warn(string.format(
				"[RewardService] Generation failed for reward %d: %s",
				i, genErr or "unknown"
			))
			table.insert(results, {
				item = nil,
				committed = false,
				error = genErr or "Generation failed",
			})
		else
			-- Commit to inventory (non-atomic, per-item)
			local ok, addErr = InventoryService.AddItem(playerId, item)
			if ok then
				committedCount = committedCount + 1
				local archetype = WeaponData.GetByArchetypeId(item.baseArchetypeId)
					or ArmorData.GetByArchetypeId(item.baseArchetypeId)
				local itemName = archetype and archetype.name or item.name or item.instanceId
				print(string.format(
					"[RewardService] Reward %d committed: %s | %s L%d %s",
					i, item.instanceId, itemName,
					item.itemLevel or 0, item.rarityId or "?"
				))
				table.insert(results, {
					item = item,
					committed = true,
					error = nil,
				})
			else
				warn(string.format(
					"[RewardService] Commit failed for reward %d (%s): %s",
					i, item.instanceId, addErr or "unknown"
				))
				table.insert(results, {
					item = item,
					committed = false,
					error = addErr or "Commit failed",
				})
			end
		end
	end

	print(string.format(
		"[RewardService] Done: %d/%d committed for %s",
		committedCount, rewardCount, playerId
	))

	return results, committedCount
end

--------------------------------------------------
-- PUBLIC: BuildRewardSummaries
--
-- Converts committed reward results into a client-safe payload.
-- Only includes successfully committed items.
-- No ownership data — display only.
--
-- Returns: { { name, rarity, itemLevel, damage, wt, defense, bonusCount, passiveCount }, ... }
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
		if result.committed and result.item then
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

			table.insert(summaries, {
				name = archetype and archetype.name or "Unknown",
				rarity = item.rarityId,
				itemLevel = item.itemLevel,
				wt = profile and profile.wt or 0,
				defense = profile and profile.defense or 0,
				bonusCount = #item.bonusLines,
				passiveCount = #item.bonusPassiveIds,
				isWeapon = not isArmor and archetype and archetype.category == "Weapon" or false,
				isArmor = isArmor,
				-- Weapon-specific fields
				damage = (not isArmor) and (profile and profile.damage or 0) or 0,
				rtDelay = (not isArmor) and (profile and profile.rtDelay or 0) or 0,
				minRange = (not isArmor) and (profile and profile.minRange or 1) or 0,
				maxRange = (not isArmor) and (profile and profile.maxRange or 1) or 0,
				handClass = (not isArmor) and (archetype and archetype.handClass or "1H") or nil,
				category = archetype and (isArmor and "Armor" or archetype.category) or "Unknown",
				nativePassiveId = (not isArmor) and (archetype and archetype.nativePassiveId or nil) or nil,
				nativePassiveDesc = (not isArmor) and (archetype and WeaponData.GetPassiveDesc(archetype.nativePassiveId) or nil) or nil,
				projectileType = (not isArmor) and (archetype and archetype.projectileType or nil) or nil,
				element = (not isArmor) and (archetype and WeaponData.GetElement(item.baseArchetypeId) or nil) or nil,
				-- Armor-specific fields
				hp = isArmor and (profile and profile.hp or 0) or nil,
				mp = isArmor and (profile and profile.mp or 0) or nil,
				slot = isArmor and (archetype and archetype.slot or nil) or nil,
				passiveName = isArmor and (archetype and archetype.passiveName or nil) or nil,
				passiveDesc = isArmor and (archetype and archetype.passiveDesc or nil) or nil,
				bonusStats = nil,
				bonusPassives = nil,
			})
			summaries[#summaries].bonusStats, summaries[#summaries].bonusPassives = resolveItemBonuses(item)
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
