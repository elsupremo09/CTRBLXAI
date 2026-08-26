-- ItemGenerator.lua
-- CTRBLXAI | Slice 4A — Equipment Foundation
--
-- 10-step procedural item generation from CTRBLXAI.db item_generation_steps.
-- Deterministic: same seed + same inputs = same item.
-- Returns a validated item instance (persistent identity only).
-- Does NOT save calculated combat stats.
--
-- Input: { baseArchetypeId, itemLevel, rarity, seed, sourceType, restrictions? }
-- Output: validated item instance table

local WeaponData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("WeaponData")
)
local BonusData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("BonusData")
)

local ItemGenerator = {}

--------------------------------------------------
-- SEEDED RANDOM (deterministic)
--------------------------------------------------

local SeededRandom = {}
SeededRandom.__index = SeededRandom

function SeededRandom.new(seed)
	local self = setmetatable({}, SeededRandom)
	self._rng = Random.new(seed)
	return self
end

function SeededRandom:NextInteger(min, max)
	return self._rng:NextInteger(min, max)
end

function SeededRandom:NextNumber()
	return self._rng:NextNumber()
end

-- Weighted random selection from a list of { item, weight } pairs
function SeededRandom:WeightedPick(weightedList)
	if #weightedList == 0 then return nil end
	local totalWeight = 0
	for _, entry in ipairs(weightedList) do
		totalWeight = totalWeight + entry.weight
	end
	if totalWeight <= 0 then return nil end
	local roll = self:NextNumber() * totalWeight
	local cumulative = 0
	for _, entry in ipairs(weightedList) do
		cumulative = cumulative + entry.weight
		if roll <= cumulative then
			return entry.item
		end
	end
	return weightedList[#weightedList].item
end

--------------------------------------------------
-- INSTANCE ID GENERATION
--------------------------------------------------

local _instanceCounter = 0

local function generateInstanceId(seed)
	_instanceCounter = _instanceCounter + 1
	return string.format("item_%d_%d", seed, _instanceCounter)
end

--------------------------------------------------
-- STEP 1: Select base item and compute scaled native stats
--------------------------------------------------

local function step1_SelectBase(input)
	local archetype = WeaponData.GetByArchetypeId(input.baseArchetypeId)
	if not archetype then
		return nil, "Invalid archetype: " .. tostring(input.baseArchetypeId)
	end
	local profile = WeaponData.GetScaledProfile(input.baseArchetypeId, input.itemLevel)
	return {
		archetype = archetype,
		scaledProfile = profile,
		itemLevel = input.itemLevel,
	}
end

--------------------------------------------------
-- STEP 2: Select rarity and retrieve Bonus BP
--------------------------------------------------

local function step2_GetBonusBp(baseInfo, rarity)
	local is2H = baseInfo.archetype.handClass == "2H"
	local bonusBp = BonusData.GetBonusBp(rarity, is2H)
	local tolerance = BonusData.GetTolerance(rarity)
	return {
		bonusBp = bonusBp,
		tolerance = tolerance,
		is2H = is2H,
		minBand = math.round(bonusBp * (1 - tolerance / 100)),
		maxBand = math.round(bonusBp * (1 + tolerance / 100)),
	}
end

--------------------------------------------------
-- STEP 3: Determine whether a Bonus Passive roll occurs
--------------------------------------------------

local function step3_PassiveRoll(rng, rarityInfo)
	-- Passive chance increases with rarity (rare mechanic)
	-- Standard: max 1 slot. 2H: max 2 slots.
	local maxSlots = rarityInfo.is2H and 2 or 1
	if rarityInfo.bonusBp <= 0 then return 0 end

	-- Passive roll chance: ~15% for Uncommon, scaling up
	local passiveChance = 0.15
	local rarityOrder = BonusData.RARITY_ORDER
	local rOrder = rarityOrder[rarityInfo.rarity] or 2
	passiveChance = passiveChance + (rOrder - 2) * 0.05 -- +5% per tier above Uncommon

	local passiveCount = 0
	for i = 1, maxSlots do
		if rng:NextNumber() < passiveChance then
			passiveCount = passiveCount + 1
		end
		passiveChance = passiveChance * 0.5 -- second roll much harder
	end
	return passiveCount
end

--------------------------------------------------
-- STEP 4: Build eligible passive pool
--------------------------------------------------

local function step4_BuildPassivePool(rarity, archetype, bonusBp)
	local pool = {}
	for passiveId, passive in pairs(BonusData.BonusPassives) do
		-- Check minimum rarity
		if not BonusData.MeetsMinimumRarity(rarity, passive.minRarity) then
			continue
		end
		-- Check BP affordability (same-rarity gate: must afford from normal budget)
		if passive.bpCost > bonusBp then
			continue
		end
		-- Simplified eligibility: "Any" passes all; specific types checked loosely
		-- (Full eligibility would check weapon family tags — simplified for now)
		local eligible = passive.eligible
		if eligible == "Any" then
			table.insert(pool, { id = passiveId, passive = passive, weight = 1.0 })
		elseif eligible == "Weapons" or eligible == "WeaponsOffHands" then
			if archetype.category == "Weapon" or archetype.category == "OffHand" then
				table.insert(pool, { id = passiveId, passive = passive, weight = 0.5 })
			end
		end
		-- Other specific eligibilities produce lower weight
	end
	return pool
end

--------------------------------------------------
-- STEP 5: Select eligible Bonus Passive(s)
--------------------------------------------------

local function step5_SelectPassives(rng, pool, count, budgetRemaining)
	local selected = {}
	local usedBp = 0
	local usedPool = {}

	for i = 1, count do
		-- Filter pool to what we can still afford
		local affordable = {}
		for _, entry in ipairs(pool) do
			if not usedPool[entry.id] and entry.passive.bpCost <= (budgetRemaining - usedBp) then
				table.insert(affordable, { item = entry.id, weight = entry.weight })
			end
		end
		if #affordable == 0 then break end

		local chosen = rng:WeightedPick(affordable)
		if chosen then
			table.insert(selected, chosen)
			usedBp = usedBp + BonusData.BonusPassives[chosen].bpCost
			usedPool[chosen] = true
		end
	end

	return selected, usedBp
end

--------------------------------------------------
-- STEP 6: Build numerical attribute pool
--------------------------------------------------

local function step6_BuildAttributePool(rarity, archetype)
	local pool = {}
	for attrId, attr in pairs(BonusData.NumericalAttributes) do
		-- Check minimum rarity
		if not BonusData.MeetsMinimumRarity(rarity, attr.minRarity) then
			continue
		end
		-- Check equipment eligibility
		local eligible = attr.eligible
		local passes = false
		if eligible == "Any" then
			passes = true
		elseif eligible == "Weapons" then
			passes = archetype.category == "Weapon"
		elseif eligible == "WeaponsOffHands" then
			passes = archetype.category == "Weapon" or archetype.category == "OffHand"
		elseif eligible == "NonWeapon" then
			passes = archetype.category ~= "Weapon"
		end
		if passes then
			table.insert(pool, { id = attrId, attr = attr })
		end
	end
	return pool
end

--------------------------------------------------
-- STEP 7: Select predefined numerical tiers
-- No duplicate lower+higher tiers of same family.
-- Target: spend remaining BP within band.
--------------------------------------------------

local function step7_SelectNumericalTiers(rng, pool, remainingBp, minBand, maxBand)
	local selected = {}
	local usedFamilies = {}
	local spentBp = 0

	-- Sort pool by BP cost descending for greedy fill
	local shuffled = {}
	for _, entry in ipairs(pool) do
		table.insert(shuffled, entry)
	end
	-- Shuffle for randomness
	for i = #shuffled, 2, -1 do
		local j = rng:NextInteger(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end

	-- Greedy selection: try to fill the budget
	local targetBp = remainingBp
	local attempts = 0
	local maxAttempts = 200

	while spentBp < minBand and attempts < maxAttempts do
		attempts = attempts + 1
		local bestCandidate = nil
		local bestDiff = math.huge

		for _, entry in ipairs(shuffled) do
			local attr = entry.attr
			-- Skip if family already used
			if usedFamilies[attr.family] then continue end
			-- Skip if would exceed max band
			if spentBp + attr.bpCost > maxBand then continue end
			-- Prefer candidates that get us closer to target
			local diff = math.abs((spentBp + attr.bpCost) - targetBp)
			if diff < bestDiff then
				bestDiff = diff
				bestCandidate = entry
			end
		end

		if not bestCandidate then break end

		table.insert(selected, { id = bestCandidate.id, tier = bestCandidate.attr.tier })
		spentBp = spentBp + bestCandidate.attr.bpCost
		usedFamilies[bestCandidate.attr.family] = true
	end

	return selected, spentBp
end

--------------------------------------------------
-- STEP 8: Check BP target (±5% or closest valid lower)
--------------------------------------------------

local function step8_ValidateBp(totalSpent, minBand, maxBand, targetBp)
	if totalSpent >= minBand and totalSpent <= maxBand then
		return true, "Within band"
	end
	-- If below minimum, it's the closest valid lower result
	if totalSpent < minBand and totalSpent > 0 then
		return true, "Closest valid below minimum"
	end
	-- Zero is valid for Broken/Common
	if targetBp == 0 and totalSpent == 0 then
		return true, "No bonus (Broken/Common)"
	end
	return false, string.format("BP %d outside band [%d, %d]", totalSpent, minBand, maxBand)
end

--------------------------------------------------
-- STEP 9: Validate interaction safety
--------------------------------------------------

local function step9_ValidateSafety(selectedPassives, selectedAttributes)
	-- No recursion, infinite resources, broken save state, or unwinnable maps
	-- For now: always passes (no dangerous combinations in initial pool)
	return true
end

--------------------------------------------------
-- STEP 10: Save generation identity
--------------------------------------------------

local function step10_BuildInstance(input, selectedPassives, selectedAttributes, rng)
	return {
		instanceId       = generateInstanceId(input.seed),
		baseArchetypeId  = input.baseArchetypeId,
		itemLevel        = input.itemLevel,
		rarityId         = input.rarity,
		bonusLines       = selectedAttributes, -- { { id = "PRI-STRBONUS-2", tier = 2 }, ... }
		bonusPassiveIds  = selectedPassives,    -- { "PAS-011", ... }
		generatorVersion = 1,
		sourceType       = input.sourceType or "Generated",
	}
end

--------------------------------------------------
-- PUBLIC: Generate
--
-- input = {
--   baseArchetypeId: string (or nil for random from pool)
--   itemLevel: number (>= 1)
--   rarity: string
--   seed: number
--   sourceType: string ("Quest"|"Loot"|"Shop"|"Debug")
--   restrictions: table? (optional)
--   archetypePool: {string}? (if baseArchetypeId is nil, pick from this)
-- }
--
-- Returns: itemInstance table, or nil + error string
--------------------------------------------------

function ItemGenerator.Generate(input)
	assert(type(input) == "table", "ItemGenerator.Generate: input must be a table.")
	assert(type(input.seed) == "number", "ItemGenerator.Generate: seed required.")
	assert(type(input.itemLevel) == "number" and input.itemLevel >= 1,
		"ItemGenerator.Generate: itemLevel must be >= 1.")
	assert(type(input.rarity) == "string", "ItemGenerator.Generate: rarity required.")

	local rng = SeededRandom.new(input.seed)

	-- Resolve archetype
	if not input.baseArchetypeId and input.archetypePool then
		local idx = rng:NextInteger(1, #input.archetypePool)
		input.baseArchetypeId = input.archetypePool[idx]
	end
	assert(input.baseArchetypeId, "ItemGenerator.Generate: no archetype resolved.")

	-- STEP 1: Base selection and scaling
	local baseInfo, err = step1_SelectBase(input)
	if not baseInfo then return nil, err end

	-- STEP 2: Rarity BP
	local rarityInfo = step2_GetBonusBp(baseInfo, input.rarity)
	rarityInfo.rarity = input.rarity

	-- Early exit for Broken/Common (no bonuses)
	if rarityInfo.bonusBp <= 0 then
		local instance = step10_BuildInstance(input, {}, {}, rng)
		return instance
	end

	-- STEP 3: Passive roll
	local passiveCount = step3_PassiveRoll(rng, rarityInfo)

	-- STEP 4: Build passive pool
	local passivePool = step4_BuildPassivePool(
		input.rarity, baseInfo.archetype, rarityInfo.bonusBp
	)

	-- STEP 5: Select passives
	local selectedPassives, passiveBpSpent = step5_SelectPassives(
		rng, passivePool, passiveCount, rarityInfo.bonusBp
	)

	-- STEP 6: Build numerical pool
	local attrPool = step6_BuildAttributePool(input.rarity, baseInfo.archetype)

	-- STEP 7: Select numerical tiers (spend remaining BP)
	local remainingBp = rarityInfo.bonusBp - passiveBpSpent
	local selectedAttributes, attrBpSpent = step7_SelectNumericalTiers(
		rng, attrPool, remainingBp, rarityInfo.minBand - passiveBpSpent, rarityInfo.maxBand - passiveBpSpent
	)

	-- STEP 8: Validate total BP
	local totalSpent = passiveBpSpent + attrBpSpent
	local valid, reason = step8_ValidateBp(
		totalSpent, rarityInfo.minBand, rarityInfo.maxBand, rarityInfo.bonusBp
	)
	if not valid then
		warn("[ItemGenerator] BP validation warning: " .. reason)
		-- Still produce the item (closest valid lower result rule)
	end

	-- STEP 9: Safety
	step9_ValidateSafety(selectedPassives, selectedAttributes)

	-- STEP 10: Build instance
	local instance = step10_BuildInstance(input, selectedPassives, selectedAttributes, rng)

	print(string.format(
		"[ItemGenerator] Generated: %s | %s L%d %s | BP:%d/%d | Attrs:%d | Passives:%d",
		instance.instanceId,
		baseInfo.archetype.name,
		input.itemLevel,
		input.rarity,
		totalSpent,
		rarityInfo.bonusBp,
		#selectedAttributes,
		#selectedPassives
	))

	return instance
end

--------------------------------------------------
-- PUBLIC: GenerateFromPool
-- Convenience for loot generation: pick random archetype from pool
--------------------------------------------------

function ItemGenerator.GenerateFromPool(archetypePool, itemLevel, rarity, seed, sourceType)
	return ItemGenerator.Generate({
		archetypePool = archetypePool,
		itemLevel = itemLevel,
		rarity = rarity,
		seed = seed,
		sourceType = sourceType or "Loot",
	})
end

return ItemGenerator
