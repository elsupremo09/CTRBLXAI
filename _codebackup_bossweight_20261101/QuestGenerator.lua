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
	-- Deployable party size per quest type (dev-locked 2026-09-26: 5-7 spread).
	-- This is the DEPLOYABLE max the enemy-count budget keys off, not the number
	-- the player actually fields. DB rule: max player-controlled deployment = 7.
	Standard = { 5 },
	Crossing = { 5 },
	Ambush   = { 5 },
	Defense  = { 6 },
	Boss     = { 7 },
	Survival = { 7 },
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

local BASE_XP   = { 60, 100, 150, 250, 400 }

-- Gold bases (economy_framework, LOCKED). Quest types with no own row use Normal.
--   Quest Reward Gold (id 9)      = Base × (1 + Recommended Level / 40)
--   Battle Completion Gold (id 8) = Base × (1 + Map Level / 50)
local QUEST_GOLD_BASE = { Boss = 150 }          -- Normal = 50
local QUEST_GOLD_NORMAL = 50
local COMPLETION_GOLD_BASE = { Boss = 100, Survival = 40, Defense = 40 } -- Normal = 30
local COMPLETION_GOLD_NORMAL = 30

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

-- Quest types a Daily Contract can be (never a boss: daily systems decision 4, 2026-11-01).
local NON_BOSS_TYPE_WEIGHTS = {}
for _, entry in ipairs(QUEST_TYPE_WEIGHTS) do
	if entry.type ~= "Boss" then table.insert(NON_BOSS_TYPE_WEIGHTS, entry) end
end

-- opts (optional; nil keeps the normal board unchanged): noBoss = never a boss quest,
-- noMercuryRoll = skip the 1-in-7 quest mercury roll.
local function generateOneQuest(questIndex, playerLevel, rng, opts)
	-- 1. Quest type (weighted)
	local questType = weightedPick(rng, if opts and opts.noBoss then NON_BOSS_TYPE_WEIGHTS else QUEST_TYPE_WEIGHTS)

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

	-- Enemy count budget: 2x-2.5x the quest's DEPLOYABLE party size (playerSlots),
	-- NOT the number the player actually deploys. E.g. playerSlots=6 -> 12-15 enemies,
	-- playerSlots=3 -> 6-8. (dev-locked 2026-09-26; replaces the old fixed 3-6 prototype
	-- clamp and satisfies the DB's open P0 "Encounter unit-count budget" in code.)
	local countMultiplier = 2.0 + rng:NextNumber() * 0.5   -- [2.0, 2.5)
	local enemyTarget = math.max(1, math.floor(playerSlots * countMultiplier + 0.5))

	if totalEnemyCount < enemyTarget then
		-- Pad with Grunts up to target.
		local existing = nil
		for _, et in ipairs(enemyTypes) do
			if et.type == "Grunt" then existing = et; break end
		end
		local needed = enemyTarget - totalEnemyCount
		if existing then
			existing.count = existing.count + needed
		else
			local gruntLvl = recommendedLvl + rng:NextInteger(-2, 0)
			table.insert(enemyTypes, { type = "Grunt", level = math.max(1, gruntLvl), count = needed })
		end
		totalEnemyCount = enemyTarget
	elseif totalEnemyCount > enemyTarget then
		-- Trim Grunts first, keeping at least 1 of the group.
		for _, et in ipairs(enemyTypes) do
			if totalEnemyCount <= enemyTarget then break end
			if et.type == "Grunt" then
				local excess = totalEnemyCount - enemyTarget
				local trim = math.min(excess, et.count - 1)
				et.count = et.count - trim
				totalEnemyCount = totalEnemyCount - trim
			end
		end
	end

	-- 9. Rewards. Quest gold is a fixed amount shown upfront (economy_framework id 9);
	-- kill gold and completion gold are added after the battle (Main post-battle).
	local baseXP   = BASE_XP[difficulty]
	local xpVariance   = math.floor(baseXP * 0.25)
	local questGold = math.floor((QUEST_GOLD_BASE[questType] or QUEST_GOLD_NORMAL) * (1 + recommendedLvl / 40))
	local completionBase = COMPLETION_GOLD_BASE[questType] or COMPLETION_GOLD_NORMAL

	local rewards = {
		gold = {
			min = questGold,
			max = questGold,
		},
		questGold = questGold,
		completionGoldBase = completionBase,
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

	-- 12. Quest mercury (USER DECISION 2026-11-01, materials_system 11): about 1 quest in 7
	-- offers 1-3 mercury, shown upfront (about 0.3 per battle). Rolled LAST so every earlier
	-- roll (enemies, rewards, name, description) is unchanged for the same seed.
	if not (opts and opts.noMercuryRoll) and rng:NextInteger(1, 7) == 1 then
		rewards.mercury = rng:NextInteger(1, 3)
	end

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

-- DAILY CONTRACT (daily systems decisions 4-6, USER DECISION 2026-11-01): one per real day,
-- built from a seed fixed by the day, so refreshing the board always shows the same contract.
-- A normal battle (never a boss; never an elite once elites exist). Reward = normal quest rewards
-- + 5 mercury (materials_system 13, paid as its quest mercury); every 3rd one also gives 1 sulfur
-- (Main / CurrencyService). It replaces the random quest-mercury roll.
local DAILY_CONTRACT_MERCURY = 5

function QuestGenerator.GenerateDailyContract(playerLevel, day)
	local rng = Random.new(day * 1000003 + 424241)
	local quest = generateOneQuest(0, playerLevel, rng, { noBoss = true, noMercuryRoll = true })
	quest.id = string.format("daily_%d", day)
	quest.name = "Daily Contract: " .. quest.name
	quest.isDailyContract = true
	quest.dailyDay = day
	quest.rewards.mercury = DAILY_CONTRACT_MERCURY
	print(string.format("[QuestGenerator] Daily Contract for day %d: %s | %s/%s | Lv %d | %d enemies",
		day, quest.name, quest.biome, quest.template, quest.recommendedLvl, quest.enemyCount))
	return quest
end

-- ELITE ENCOUNTERS (daily systems decisions 10-14, USER DECISION 2026-11-01; loot_progression 69).
-- About 1 in 30 normal quest battles (0.034) is an elite encounter, hidden until the departure
-- briefing. Anti-fishing (DEV DEFAULT 2026-11-01, Simulator finding): the roll is fixed by the
-- player's count of COMPLETED battles, not by the card, so abandoning a quest or picking another
-- card can never produce more elites. Fortune is never used. Never on boss cards or the Daily
-- Contract.
local ELITE_ENCOUNTER_CHANCE = 0.034

local function hashString(s: string): number
	local h = 0
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 2147483647
	end
	return h
end

function QuestGenerator.IsEliteBattle(playerId, battlesCompleted)
	local seed = (hashString(tostring(playerId)) + (tonumber(battlesCompleted) or 0) * 7919 + 99991) % 2147483647
	return Random.new(seed):NextNumber() < ELITE_ENCOUNTER_CHANCE
end

-- Turns a normal quest into an elite encounter (once). DEV DEFAULT 2026-11-01: the design's
-- "6 enemies" is the planning value (Normal 5 / Elite 6, loot_progression 86, not read by code);
-- real battles use 2-2.5x the deploy slots, so an elite keeps the card's enemy count + 1 extra
-- Veteran, with exactly ONE Elite (the leader; any other Elites become Veterans) so the
-- "Defeat the Elite within N rounds" objective (Elite Slayer) can run.
function QuestGenerator.MakeEliteEncounter(quest)
	if quest.isEliteEncounter then return quest end
	local recLvl = quest.recommendedLvl or 1
	-- D-1 fix (2026-11-01): the result is always the card's own count + 1. Every Elite on the
	-- card becomes a Veteran, then the Elite leader is added, so a card that had 0 Elites and a
	-- card that had 1 both end with exactly one Elite and one extra enemy.
	local kept, oldTotal = {}, 0
	for _, et in ipairs(quest.enemyTypes or {}) do
		oldTotal += et.count
		if et.type == "Elite" then
			table.insert(kept, { type = "Veteran", level = et.level, count = et.count })
		else
			table.insert(kept, et)
		end
	end
	table.insert(kept, 1, { type = "Elite", level = recLvl + 2, count = 1, isLeader = true })
	quest.enemyTypes = kept
	quest.enemyCount = oldTotal + 1
	quest.isEliteEncounter = true
	print(string.format("[QuestGenerator] Elite encounter: %s | %d enemies, Elite leader Lv %d", quest.name, quest.enemyCount, recLvl + 2))
	return quest
end

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
