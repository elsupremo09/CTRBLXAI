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
	{ rarity = "Broken",    weight = 0.10  },
	{ rarity = "Common",    weight = 0.55  },
	{ rarity = "Uncommon",  weight = 0.20  },
	{ rarity = "Rare",      weight = 0.10  },
	{ rarity = "Epic",      weight = 0.049 },
	{ rarity = "Legendary", weight = 0.001 },
}

-- Rarity rank for card minimum clamping
local RARITY_RANK = {
	Broken = 0, Common = 1, Uncommon = 2, Rare = 3,
	Epic = 4, Legendary = 5, Mythic = 6,
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

-- Card rarity: roll equipment weights but clamp to Rare minimum
-- per DB: "Normal Skill Card rarity begins at Rare"
local function rollCardRarity(rng)
	local base = weightedRoll(rng, NORMAL_RARITY_WEIGHTS, "rarity", "weight")
	if (RARITY_RANK[base] or 0) < 3 then
		return "Rare"
	end
	return base
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
		if type(def) == "table" and def.name then
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
	local pool = ConsumableData.GetAllIds()
	table.sort(pool)
	cachedConsumablePool = pool
	return pool
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

function RewardService.GenerateRewards(playerId, mapLevel, opportunityId)
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

	print(string.format(
		"[RewardService] Generating %d reward(s) for %s | MapLevel=%d | OpportunityId=%s",
		rewardCount, playerId, mapLevel, opportunityId
	))

	local results = {}
	local equipCommitted = 0

	for i = 1, rewardCount do
		local seed = generateRewardSeed()
		local itemRng = Random.new(seed)

		-- Step 1: Roll reward category
		local category = weightedRoll(itemRng, CATEGORY_WEIGHTS, "category", "weight")

		if category == "Equipment" then
			local rarity = weightedRoll(itemRng, NORMAL_RARITY_WEIGHTS, "rarity", "weight")
			local pool = getEquipPool()
			local item, genErr = ItemGenerator.GenerateFromPool(pool, mapLevel, rarity, seed, "Loot")
			if not item then
				warn(string.format("[RewardService] Equipment gen failed %d: %s", i, genErr or "unknown"))
				table.insert(results, {
					category = "Equipment", committed = false,
					error = genErr or "Generation failed",
				})
			else
				local ok, addErr = InventoryService.AddItem(playerId, item)
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
			local rarity = weightedRoll(itemRng, NORMAL_RARITY_WEIGHTS, "rarity", "weight")
			print(string.format("[RewardService] Reward %d: Consumable %s (%s) [%s]",
				i, conId, def and def.name or "?", rarity))
			table.insert(results, {
				category = "Consumable", committed = false,
				cardData = {
					id = conId,
					name = def and def.name or conId,
					desc = def and def.effectFormula or "",
					rarity = rarity,
					conCategory = def and def.category or "Unknown",
					maxCharges = def and def.maxCharges or 1,
				},
			})
		end
	end

	print(string.format("[RewardService] Done: %d equipment committed, %d total for %s",
		equipCommitted, #results, playerId))

	return results, equipCommitted
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
				name = archetype and archetype.name or "Unknown",
				icon = archetype and archetype.icon or nil,
				flavor = archetype and archetype.flavor or nil,
				rarity = item.rarityId,
				itemLevel = item.itemLevel,
				category = "Equipment",
				isCard = false,
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
				nativePassiveDesc = (not isArmor) and (archetype and WeaponData.GetPassiveDesc(archetype.nativePassiveId) or nil) or nil,
				projectileType = (not isArmor) and (archetype and archetype.projectileType or nil) or nil,
				element = (not isArmor) and (archetype and WeaponData.GetElement(item.baseArchetypeId) or nil) or nil,
				hp = isArmor and (profile and profile.hp or 0) or nil,
				mp = isArmor and (profile and profile.mp or 0) or nil,
				slot = isArmor and (archetype and archetype.slot or nil) or nil,
				passiveName = isArmor and (archetype and archetype.passiveName or nil) or nil,
				passiveDesc = isArmor and (archetype and archetype.passiveDesc or nil) or nil,
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
				category = result.category,
				rarity = cd.rarity or "Common",
				isCard = true,
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
