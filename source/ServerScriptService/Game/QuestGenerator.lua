-- QuestGenerator.lua
-- CTRBLXAI | Phase B — Quest Board System
--
-- Procedurally generates 3 quest definitions given a player level and seed.
-- All random decisions use Random.new(seed) for determinism.
-- Each quest uses seed+0, seed+1, seed+2 for reproducible variety.

local BiomeData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("BiomeData")
)

local QuestGenerator = {}

--------------------------------------------------
-- QUEST TYPE → TEMPLATE MAPPING
--------------------------------------------------

local QUEST_TEMPLATES = {
	Standard = { "T01", "T02" },
	Boss     = { "T04" },
	Defense  = { "T05" },
	Ambush   = { "T06", "T08" },
	Survival = { "T07" },
	Crossing = { "T03" },
}

--------------------------------------------------
-- QUEST TYPE → PLAYER SLOTS
--------------------------------------------------

local QUEST_PLAYER_SLOTS = {
	Standard = { 3 },
	Boss     = { 3, 4 },
	Defense  = { 4 },
	Ambush   = { 3 },
	Survival = { 4, 5, 6 },
	Crossing = { 3 },
}

--------------------------------------------------
-- QUEST TYPE WEIGHTS
--------------------------------------------------

local QUEST_TYPE_WEIGHTS = {
	{ type = "Standard", weight = 35 },
	{ type = "Crossing", weight = 15 },
	{ type = "Ambush",   weight = 15 },
	{ type = "Defense",  weight = 10 },
	{ type = "Boss",     weight = 10 },
	{ type = "Survival", weight = 15 },
}

--------------------------------------------------
-- BIOME POOL (all 11 for prototype — no level gating)
--------------------------------------------------

local ALL_BIOMES = {
	"Plains", "Forest", "Desert", "Swamp", "Highlands",
	"Tundra", "Volcano", "Cave", "Ruins", "Castle", "Corrupted",
}

--------------------------------------------------
-- PROCEDURAL NAME GENERATION
--------------------------------------------------

local ADJECTIVES = {
	"Desperate", "Fierce", "Hidden", "Sacred", "Dark",
	"Ancient", "Burning", "Frozen", "Lost", "Silent",
}

local NOUNS = {
	"Ambush", "Siege", "Crossing", "Patrol", "Hunt",
	"Raid", "Defense", "Skirmish", "Assault", "Ritual",
}

local BIOME_LOCATIONS = {
	Plains    = { "the Open Fields", "the Trade Road" },
	Forest    = { "the Deep Wood", "the Ancient Grove" },
	Desert    = { "the Sand Wastes", "the Scorched Valley" },
	Highlands = { "the Mountain Pass", "the High Ridge" },
	Tundra    = { "the Frozen Lake", "the Icebound Path" },
	Volcano   = { "the Magma Rift", "the Burning Caldera" },
	Castle    = { "the Outer Wall", "the Keep" },
	Ruins     = { "the Fallen Temple", "the Lost Catacombs" },
	Swamp     = { "the Black Marsh", "the Mire" },
	Cave      = { "the Deep Cavern", "the Crystal Hollow" },
	Corrupted = { "the Tainted Shrine", "the Dark Nexus" },
}

--------------------------------------------------
-- ENEMY ROSTER TABLES (by difficulty)
--------------------------------------------------

-- { gruntMin, gruntMax, vetMin, vetMax, eliteMin, eliteMax }
local ENEMY_ROSTER_BY_DIFFICULTY = {
	[1] = { gruntMin = 2, gruntMax = 3, vetMin = 0, vetMax = 0, eliteMin = 0, eliteMax = 0 },
	[2] = { gruntMin = 2, gruntMax = 3, vetMin = 0, vetMax = 1, eliteMin = 0, eliteMax = 0 },
	[3] = { gruntMin = 1, gruntMax = 2, vetMin = 1, vetMax = 2, eliteMin = 0, eliteMax = 0 },
	[4] = { gruntMin = 1, gruntMax = 2, vetMin = 1, vetMax = 1, eliteMin = 1, eliteMax = 1 },
	[5] = { gruntMin = 1, gruntMax = 2, vetMin = 1, vetMax = 2, eliteMin = 1, eliteMax = 1 },
}

--------------------------------------------------
-- REWARD TABLES
--------------------------------------------------

local BASE_GOLD = { 100, 150, 200, 300, 450 }
local BASE_XP   = { 60, 100, 150, 250, 400 }

--------------------------------------------------
-- HELPERS
--------------------------------------------------

--- Weighted random selection from a { {type, weight}, ... } table.
local function weightedPick(rng, entries)
	local totalWeight = 0
	for _, entry in ipairs(entries) do
		totalWeight = totalWeight + entry.weight
	end
	local roll = rng:NextNumber() * totalWeight
	local cumulative = 0
	for _, entry in ipairs(entries) do
		cumulative = cumulative + entry.weight
		if roll <= cumulative then
			return entry.type or entry
		end
	end
	-- Fallback (shouldn't reach)
	return entries[1].type or entries[1]
end

--- Pick a random element from a simple array.
local function pickRandom(rng, list)
	return list[rng:NextInteger(1, #list)]
end

--- Weighted random for biome condition weights (key-value table).
local function weightedPickMap(rng, weightMap)
	local entries = {}
	for key, weight in pairs(weightMap) do
		table.insert(entries, { type = key, weight = weight })
	end
	-- Sort for deterministic iteration order
	table.sort(entries, function(a, b) return a.type < b.type end)
	return weightedPick(rng, entries)
end

--- Random integer in [min, max].
local function randRange(rng, min, max)
	if min >= max then return min end
	return rng:NextInteger(min, max)
end

--------------------------------------------------
-- SINGLE QUEST GENERATION
--------------------------------------------------

local function generateOneQuest(questIndex, playerLevel, rng)
	-- 1. Quest type (weighted)
	local questType = weightedPick(rng, QUEST_TYPE_WEIGHTS)

	-- 2. Biome (uniform from all biomes — prototype has no gating)
	local biome = pickRandom(rng, ALL_BIOMES)

	-- 3. Template from quest type mapping
	local templates = QUEST_TEMPLATES[questType]
	local template = pickRandom(rng, templates)

	-- 4. Battle condition from biome's condition weights
	local biomeInfo = BiomeData[biome]
	local condition = "Clear"
	if biomeInfo and biomeInfo.battleConditionWeights then
		condition = weightedPickMap(rng, biomeInfo.battleConditionWeights)
	end

	-- 5. Difficulty (1-5 uniform for prototype)
	local difficulty = rng:NextInteger(1, 5)

	-- 6. Recommended level: playerLevel + (difficulty - 1) * 3, ± 2
	local baseLvl = playerLevel + (difficulty - 1) * 3
	local recommendedLvl = math.max(1, baseLvl + rng:NextInteger(-2, 2))

	-- 7. Player slots
	local slotOptions = QUEST_PLAYER_SLOTS[questType]
	local playerSlots = pickRandom(rng, slotOptions)

	-- 8. Enemy roster
	local enemyTypes = {}
	local totalEnemyCount = 0

	if questType == "Boss" then
		-- Boss quests always have 1 Boss + supporting Grunts
		local bossLvl = recommendedLvl + rng:NextInteger(0, 2)
		table.insert(enemyTypes, { type = "Boss", level = bossLvl, count = 1 })
		local gruntCount = rng:NextInteger(1, 2)
		local gruntLvl = recommendedLvl + rng:NextInteger(-2, 0)
		table.insert(enemyTypes, { type = "Grunt", level = math.max(1, gruntLvl), count = gruntCount })
		totalEnemyCount = 1 + gruntCount
	else
		local roster = ENEMY_ROSTER_BY_DIFFICULTY[difficulty]
		local gruntCount = randRange(rng, roster.gruntMin, roster.gruntMax)
		local vetCount   = randRange(rng, roster.vetMin, roster.vetMax)
		local eliteCount = randRange(rng, roster.eliteMin, roster.eliteMax)

		if gruntCount > 0 then
			local gruntLvl = recommendedLvl + rng:NextInteger(-2, 0)
			table.insert(enemyTypes, { type = "Grunt", level = math.max(1, gruntLvl), count = gruntCount })
		end
		if vetCount > 0 then
			local vetLvl = recommendedLvl + rng:NextInteger(-1, 1)
			table.insert(enemyTypes, { type = "Veteran", level = math.max(1, vetLvl), count = vetCount })
		end
		if eliteCount > 0 then
			local eliteLvl = recommendedLvl + rng:NextInteger(0, 2)
			table.insert(enemyTypes, { type = "Elite", level = math.max(1, eliteLvl), count = eliteCount })
		end

		totalEnemyCount = gruntCount + vetCount + eliteCount
	end

	-- Clamp total enemy count to 3-6
	if totalEnemyCount < 3 then
		-- Pad with an extra Grunt
		local existing = nil
		for _, et in ipairs(enemyTypes) do
			if et.type == "Grunt" then existing = et; break end
		end
		local needed = 3 - totalEnemyCount
		if existing then
			existing.count = existing.count + needed
		else
			local gruntLvl = recommendedLvl + rng:NextInteger(-2, 0)
			table.insert(enemyTypes, { type = "Grunt", level = math.max(1, gruntLvl), count = needed })
		end
		totalEnemyCount = 3
	elseif totalEnemyCount > 6 then
		-- Trim Grunts first
		for _, et in ipairs(enemyTypes) do
			if et.type == "Grunt" then
				local excess = totalEnemyCount - 6
				local trim = math.min(excess, et.count - 1)
				et.count = et.count - trim
				totalEnemyCount = totalEnemyCount - trim
				break
			end
		end
	end

	-- 9. Rewards
	local baseGold = BASE_GOLD[difficulty]
	local baseXP   = BASE_XP[difficulty]
	local goldVariance = math.floor(baseGold * 0.25)
	local xpVariance   = math.floor(baseXP * 0.25)

	local rewards = {
		gold = {
			min = baseGold - goldVariance,
			max = baseGold + goldVariance,
		},
		xp = {
			min = baseXP - xpVariance,
			max = baseXP + xpVariance,
		},
		drops = difficulty >= 3 and "Equipment" or "Consumables",
	}

	-- 10. Procedural name: "[Adj] [Noun] at [Location]"
	local adj  = pickRandom(rng, ADJECTIVES)
	local noun = pickRandom(rng, NOUNS)
	local locations = BIOME_LOCATIONS[biome] or { "the Unknown" }
	local location  = pickRandom(rng, locations)
	local name = adj .. " " .. noun .. " at " .. location

	-- 11. Description (short flavor from biome inhabitants)
	local inhabitants = biomeInfo and biomeInfo.typicalInhabitants or { "enemies" }
	local inhab = pickRandom(rng, inhabitants)
	local description = inhab .. " threaten the area."

	-- Build quest table
	local quest = {
		id             = string.format("quest_%03d", questIndex),
		name           = name,
		description    = description,
		questType      = questType,
		biome          = biome,
		template       = template,
		condition      = condition,
		difficulty     = difficulty,
		recommendedLvl = recommendedLvl,
		playerSlots    = playerSlots,
		enemyCount     = totalEnemyCount,
		enemyTypes     = enemyTypes,
		rewards        = rewards,
	}

	return quest
end

--------------------------------------------------
-- PUBLIC API
--------------------------------------------------

--- Generate 3 quests for the quest board.
--- @param playerLevel number Current player level (prototype: 1)
--- @param seed number Base seed (e.g. os.time())
--- @return table { quest1, quest2, quest3 }
function QuestGenerator.Generate(playerLevel, seed)
	local quests = {}
	for i = 0, 2 do
		local rng = Random.new(seed + i)
		local quest = generateOneQuest(i + 1, playerLevel, rng)
		table.insert(quests, quest)
	end

	print(string.format("[QuestGenerator] Generated 3 quests (seed=%d, level=%d):", seed, playerLevel))
	for _, q in ipairs(quests) do
		print(string.format("  [%s] %s | %s/%s | Diff %d | Lv %d | %d enemies | %s",
			q.id, q.name, q.biome, q.template, q.difficulty, q.recommendedLvl, q.enemyCount, q.condition))
	end

	return quests
end

return QuestGenerator
