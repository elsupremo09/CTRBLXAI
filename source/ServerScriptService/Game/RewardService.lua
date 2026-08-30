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

local WeaponData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("WeaponData")
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
	for archetypeId, def in pairs(WeaponData.Archetypes) do
		if def.category == "Weapon" or def.category == "OffHand" then
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
				print(string.format(
					"[RewardService] Reward %d committed: %s | %s L%d %s",
					i, item.instanceId,
					WeaponData.GetByArchetypeId(item.baseArchetypeId).name,
					item.itemLevel, item.rarityId
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

function RewardService.BuildRewardSummaries(results)
	local summaries = {}
	for _, result in ipairs(results) do
		if result.committed and result.item then
			local item = result.item
			local archetype = WeaponData.GetByArchetypeId(item.baseArchetypeId)
			local profile = WeaponData.GetScaledProfile(item.baseArchetypeId, item.itemLevel)

			table.insert(summaries, {
				name = archetype and archetype.name or "Unknown",
				rarity = item.rarityId,
				itemLevel = item.itemLevel,
				damage = profile and profile.damage or 0,
				wt = profile and profile.wt or 0,
				defense = profile and profile.defense or 0,
				bonusCount = #item.bonusLines,
				passiveCount = #item.bonusPassiveIds,
				handClass = archetype and archetype.handClass or "1H",
				category = archetype and archetype.category or "Weapon",
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
