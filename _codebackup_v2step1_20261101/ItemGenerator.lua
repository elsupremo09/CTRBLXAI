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
local ArmorData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("ArmorData")
)
local BonusData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("BonusData")
)
local AffixData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("AffixData")
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
-- Per-server-session nonce (2026-11-01). The counter restarts every session, so the
-- same seed in two sessions could give two items the same ID; InventoryService then
-- refuses the second one. The Runeforge fixes each item's Add offers from its ID
-- (guild_facilities 55), so IDs must be unique across sessions. Item CONTENT stays
-- deterministic from the seed; only the opaque ID string changes.
local SESSION_NONCE = Random.new():NextInteger(1, 2^31 - 1)

local function generateInstanceId(seed)
	_instanceCounter = _instanceCounter + 1
	return string.format("item_%d_%d_%d", seed, SESSION_NONCE, _instanceCounter)
end

--------------------------------------------------
-- STEP 1: Select base item and compute scaled native stats
--------------------------------------------------

local function step1_SelectBase(input)
	local archetype = WeaponData.GetByArchetypeId(input.baseArchetypeId)
	local isArmor = false
	if archetype then
		isArmor = false
	else
		archetype = ArmorData.GetByArchetypeId(input.baseArchetypeId)
		isArmor = true
	end
	if not archetype then
		return nil, "Invalid archetype: " .. tostring(input.baseArchetypeId)
	end
	local profile = isArmor
		and ArmorData.GetScaledProfile(input.baseArchetypeId, input.itemLevel)
		or WeaponData.GetScaledProfile(input.baseArchetypeId, input.itemLevel)
	return {
		archetype = archetype,
		scaledProfile = profile,
		itemLevel = input.itemLevel,
		isArmor = isArmor,
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

-- Gear-type eligibility model (user ruling 2026-10-20):
--   * Ordinary weapon passives roll on ANY weapon, off-hand, or gloves
--     (off-hands use their own base stats; gloves = fist-strike inheritance).
--   * Armor/shield/accessory/glove passives roll by gear slot.
--   * TWO shape exceptions are kept, and they are REAL WEAPONS ONLY (never
--     off-hands or gloves) so they can't clash with a main-hand's identity:
--       - NonElementalWeapons: elemental transforms; excluded on already-
--         elemental weapons.
--       - SingleTarget* : pattern conversions; single-target weapons only.
-- All weapon-subtype labels (HighDamageMelee, FastWeapons, etc.) collapse to
-- the single any-weapon test by design. Weights are starting values; the
-- Simulator agent can retune them without changing eligibility.
local function step4_BuildPassivePool(rarity, archetype, bonusBp, archetypeId)
	local pool = {}

	-- A weapon already carrying a native elemental passive cannot take another.
	-- User ruling 2026-10-23: Freeze / Venomous only apply a status, they are not elements
	-- (WeaponData TRANSFORM_ELEMENT). Ignite stays: it re-types Physical hits as Fire.
	local PASSIVE_ELEMENT = {
		Ignite = true,
	}
	local isElemental = archetype.nativePassiveId
		and PASSIVE_ELEMENT[archetype.nativePassiveId] or false

	-- Off-hands carry no shield/focus field, so the shield set is authored.
	local SHIELD_OFFHANDS = {
		["OFF-SHIELD"] = true, ["OFF-BUCKLER"] = true,
	}

	-- Gear-type facts (computed once).
	local isWeapon    = archetype.category == "Weapon"
	local isOffHand   = archetype.category == "OffHand"
	local isArmor     = archetype.category == "Armor"
	local isGloves    = isArmor and archetype.slot == "Gloves"
	local isBody      = isArmor and archetype.slot == "Body"
	local isAccessory = isArmor and archetype.slot == "Accessory"
	local isShield    = isOffHand and SHIELD_OFFHANDS[archetypeId] == true
	-- Can carry ordinary weapon passives. Shape changes are excluded below.
	local isWeaponish = isWeapon or isOffHand or isGloves

	for passiveId, passive in pairs(BonusData.BonusPassives) do
		-- Guard: rarity + affordability checks (replaced continue for Luau safety)
		if BonusData.MeetsMinimumRarity(rarity, passive.minRarity)
			and passive.bpCost <= bonusBp then
			local eligible = passive.eligible
			local weight = nil
			-- WEAPON-STAT passives (Brutal/Stagger/Bulwark) are MAIN-HAND WEAPONS ONLY
			-- (user ruling 2026-10-23): they modify weapon damage / RT delay, meaningful
			-- only on the attacking weapon. They share isWeaponish eligibility labels with
			-- other passives, so they previously rolled onto off-hands/gloves where they
			-- were inert. This flag rejects those slots without touching the shared labels.
			-- Combat already excludes them from the multi-slot path (GetCombatKeys).
			-- PAS-007 Range +1 (DB "Approved weapon families only") is read from the weapon only, so it is
			-- weapon-only too (checklist fix 2026-10-29; was rolling on off-hands / gloves, where it is inert).
			local weaponStatOnly = (passiveId == "PAS-001" or passiveId == "PAS-002" or passiveId == "PAS-046"
				or passiveId == "PAS-007")

			if eligible == "Any" then
				weight = 1.0
			-- Ordinary weapon passives + all weapon-subtype labels -> any weapon,
			-- off-hand, or gloves.
			elseif eligible == "Weapons" or eligible == "WeaponsOffHands"
				or eligible == "HighDamageMelee" or eligible == "FastWeapons"
				or eligible == "BluntHeavy" or eligible == "Piercing"
				or eligible == "Magical" or eligible == "NonSingleTarget"
				or eligible == "ApprovedRanged" then
				if isWeaponish then
					weight = 0.4
				end
			-- SHAPE EXCEPTION 1: elemental transform. Real weapons only, never
			-- an already-elemental weapon, never off-hands/gloves.
			elseif eligible == "NonElementalWeapons" then
				if isWeapon and not isElemental then
					weight = 0.3
				end
			-- SHAPE EXCEPTION 2: pattern conversions. Single-target weapons only.
			elseif eligible == "SingleTargetMelee" then
				if isWeapon and archetype.pattern == "Single"
					and archetype.projectileType == nil then
					weight = 0.3
				end
			elseif eligible == "SingleTargetThrust" or eligible == "SingleTargetRanged" then
				if isWeapon and archetype.pattern == "Single"
					and archetype.projectileType ~= nil then
					weight = 0.3
				end
			-- Elemental wards: any armor piece, shields, or accessories.
			elseif eligible == "ArmorShield" then
				-- DB: Electric Negation / Absorption are "Armor, shields, clothing" -- no accessories
				-- (the Wards include accessories). Checklist fix 2026-10-29.
				local noAccessory = (passiveId == "PAS-027" or passiveId == "PAS-028")
				if (isArmor or isShield) and not (noAccessory and isAccessory) then
					weight = 0.4
				end
			-- Guard bonus: shields + body armor.
			elseif eligible == "ShieldsArmor" then
				if isShield or isBody then
					weight = 0.4
				end
			elseif eligible == "Accessories" then
				if isAccessory then
					weight = 0.3
				end
			elseif eligible == "Gloves" then
				if isGloves then
					weight = 0.4
				end
			end

			if weaponStatOnly and not isWeapon then
				weight = nil  -- main-hand weapons only; reject off-hand/gloves/armor
			end
			if weight ~= nil then
				table.insert(pool, { id = passiveId, passive = passive, weight = weight })
			end
		end
	end
	return pool
end

--------------------------------------------------
-- STEP 5: Select eligible Bonus Passive(s)
--------------------------------------------------

-- DB weapons_equipment row 56 (Locked): at most ONE elemental transformation and ONE pattern
-- conversion per generated item (a 2H item rolls up to 2 passives). Checklist fix 2026-10-29.
local EXCLUSIVE_GROUP = {
	["PAS-016"] = "transform", ["PAS-017"] = "transform", ["PAS-018"] = "transform",
	["PAS-019"] = "transform", ["PAS-020"] = "transform", ["PAS-021"] = "transform",
	["PAS-023"] = "pattern", ["PAS-024"] = "pattern", ["PAS-025"] = "pattern",
}

local function step5_SelectPassives(rng, pool, count, budgetRemaining)
	local selected = {}
	local usedBp = 0
	local usedPool = {}
	local usedGroup = {}

	for i = 1, count do
		-- Filter pool to what we can still afford
		local affordable = {}
		for _, entry in ipairs(pool) do
			local grp = EXCLUSIVE_GROUP[entry.id]
			if not usedPool[entry.id] and not (grp and usedGroup[grp])
				and entry.passive.bpCost <= (budgetRemaining - usedBp) then
				table.insert(affordable, { item = entry.id, weight = entry.weight })
			end
		end
		if #affordable == 0 then break end

		local chosen = rng:WeightedPick(affordable)
		if chosen then
			table.insert(selected, chosen)
			usedBp = usedBp + BonusData.BonusPassives[chosen].bpCost
			usedPool[chosen] = true
			if EXCLUSIVE_GROUP[chosen] then usedGroup[EXCLUSIVE_GROUP[chosen]] = true end
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
		-- Guard: rarity check (replaced continue for Luau safety)
		if BonusData.MeetsMinimumRarity(rarity, attr.minRarity) then
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
			-- Guard: family + budget checks (replaced continue for Luau safety)
			if not usedFamilies[attr.family]
				and (spentBp + attr.bpCost <= maxBand) then
				-- Prefer candidates that get us closer to target
				local diff = math.abs((spentBp + attr.bpCost) - targetBp)
				if diff < bestDiff then
					bestDiff = diff
					bestCandidate = entry
				end
			end
		end

		if not bestCandidate then
			if spentBp < minBand then
				warn("[ItemGen] step7: no candidate found, pool exhausted at " .. spentBp .. "BP")
			end
			break
		end

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
	-- Compose display name from affixes
	local displayName = nil
	local arch = WeaponData.GetByArchetypeId(input.baseArchetypeId)
		or ArmorData.GetByArchetypeId(input.baseArchetypeId)
	local baseName = arch and arch.name or nil

	if baseName and (#selectedAttributes > 0 or #selectedPassives > 0) then
		-- Build combined bonus list with BP costs
		local bonusList = {}
		for _, attr in ipairs(selectedAttributes) do
			local def = BonusData.NumericalAttributes[attr.id]
			if def then
				table.insert(bonusList, {
					bpCost = def.bpCost or 0,
					sourceType = "numerical",
					family = def.family,
					tier = def.tier or attr.tier or 1,
				})
			end
		end
		for _, passiveId in ipairs(selectedPassives) do
			local def = BonusData.BonusPassives[passiveId]
			if def then
				table.insert(bonusList, {
					bpCost = def.bpCost or 0,
					sourceType = "passive",
					family = passiveId,
					tier = 0,
				})
			end
		end

		-- Sort descending by BP cost; ties: passive > numerical, then alphabetical family
		table.sort(bonusList, function(a, b)
			if a.bpCost ~= b.bpCost then return a.bpCost > b.bpCost end
			if a.sourceType ~= b.sourceType then return a.sourceType == "passive" end
			return a.family < b.family
		end)

		-- Look up affix names
		local prefix = nil
		local suffix = nil
		if bonusList[1] then
			local b = bonusList[1]
			if b.sourceType == "numerical" then
				prefix = AffixData.Numerical[b.family] and AffixData.Numerical[b.family][b.tier]
			else
				prefix = AffixData.Passive[b.family]
			end
		end
		if bonusList[2] then
			local b = bonusList[2]
			if b.sourceType == "numerical" then
				suffix = AffixData.Numerical[b.family] and AffixData.Numerical[b.family][b.tier]
			else
				suffix = AffixData.Passive[b.family]
			end
		end

		-- Compose
		if prefix and suffix then
			displayName = prefix .. " " .. baseName .. " of " .. suffix
		elseif prefix then
			displayName = prefix .. " " .. baseName
		end
	end

	return {
		instanceId       = generateInstanceId(input.seed),
		baseArchetypeId  = input.baseArchetypeId,
		itemLevel        = input.itemLevel,
		rarityId         = input.rarity,
		bonusLines       = selectedAttributes, -- { { id = "PRI-STRBONUS-2", tier = 2 }, ... }
		bonusPassiveIds  = selectedPassives,    -- { "PAS-011", ... }
		generatorVersion = 1,
		sourceType       = input.sourceType or "Generated",
		displayName      = displayName,
		-- Acquisition record (equipment_schema 16/18/19, USER DECISION 2026-11-01): the
		-- level and rarity it was made at (catch-up fee, dismantle refund, Epic step fee,
		-- sell value of enchanted items) and its Runeforge reroll count.
		startingLevel    = input.itemLevel,
		startingRarity   = input.rarity,
		rerollCount      = 0,
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
		input.rarity, baseInfo.archetype, rarityInfo.bonusBp, input.baseArchetypeId
	)

	-- STEP 5: Select passives
	local selectedPassives, passiveBpSpent = step5_SelectPassives(
		rng, passivePool, passiveCount, rarityInfo.bonusBp
	)

	-- STEP 6: Build numerical pool
	local attrPool = step6_BuildAttributePool(input.rarity, baseInfo.archetype)
	print("[ItemGen] step6 pool: " .. #attrPool .. " eligible attributes for " .. input.rarity)

	-- STEP 7: Select numerical tiers (spend remaining BP)
	local remainingBp = rarityInfo.bonusBp - passiveBpSpent
	local selectedAttributes, attrBpSpent = step7_SelectNumericalTiers(
		rng, attrPool, remainingBp, rarityInfo.minBand - passiveBpSpent, rarityInfo.maxBand - passiveBpSpent
	)
	print("[ItemGen] step7 result: " .. #selectedAttributes .. " attrs, " .. attrBpSpent .. "BP spent of " .. remainingBp .. "BP budget")

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
