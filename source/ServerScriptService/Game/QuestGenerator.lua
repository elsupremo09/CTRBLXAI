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

-- Renown step 3 (2026-11-13): quest level from Renown Rank (loot_progression 87). Pure module, no deps.
local RenownRules = require(script.Parent:WaitForChild("RenownRules"))

-- Quest main goals (game_flow 41, build step 1 2026-11-17): frequency table + per-goal numbers.
local QuestGoalData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("QuestGoalData")
)

-- Quest target names (user 2026-11-18 9:50 PM): Kill target / Capture name their unit on the card.
-- Same word pools as EnemyGenerator.buildEnemyName (no new name lists).
local UnitNameData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("UnitNameData")
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
	{ type = "Boss",     weight = 3 },  -- USER DECISION 2026-11-01 (boss income): was 10 (1 in 10 cards); now about 1 in 31
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

-- Elite leader roster rule (shared by elite encounters and the Kill target goal): every Elite on the
-- card becomes a Veteran, then ONE Elite leader is added at quest level + 2 (<= 99), so the count
-- is the card's own count + 1. levelBonus: elite encounters use their own +2 (ELITE_LEADER_LEVEL_BONUS),
-- Kill target uses QuestGoalData. Returns the leader level.
local ELITE_LEADER_LEVEL_BONUS = 2 -- elite encounter leader (daily systems decisions 10-14)
local function addEliteLeader(quest, levelBonus: number): number
	local recLvl = quest.recommendedLvl or 1
	local kept, oldTotal = {}, 0
	for _, et in ipairs(quest.enemyTypes or {}) do
		oldTotal += et.count
		if et.type == "Elite" then
			table.insert(kept, { type = "Veteran", level = et.level, count = et.count })
		else
			table.insert(kept, et)
		end
	end
	local leaderLvl = RenownRules.ClampEnemyLevel(recLvl + levelBonus) -- <= 99 (loot_progression 87)
	table.insert(kept, 1, { type = "Elite", level = leaderLvl, count = 1, isLeader = true })
	quest.enemyTypes = kept
	quest.enemyCount = oldTotal + 1
	return leaderLvl
end

-- QUEST MAIN GOAL (game_flow 41, build step 1 2026-11-17). Rolled as the LAST roll of a quest
-- (after quest mercury, before the promised gear when that is built), so every earlier roll is
-- unchanged for the same seed and the saved board stays stable. Only goals allowed for the
-- quest's difficulty tier AND template are rolled. Boss quests are always Kill target on the Boss
-- (open question 2). A goal that isn't built yet is rolled at its real weight but played as Wipe
-- out (quest.goalRolled keeps the rolled id for logs / the Simulator).
-- allowSurvive (game_flow 41/42, 2026-11-18): false in Ranks 1-8 -> Survive is left out of the pool,
-- so its weight is shared proportionally by the other allowed goals (same single RNG draw).
local function rollGoal(quest, rng, allowSurvive: boolean?)
	if quest.questType == "Boss" then
		quest.goal = "KillTarget"
		quest.goalParams = { target = "Boss" }
		return
	end
	local tier = QuestGoalData.TierOf(quest.difficulty)
	local pool = {}
	for _, e in ipairs(QuestGoalData.Weights[tier]) do
		if QuestGoalData.FitsTemplate(e.id, quest.template)
			and not (e.id == "Survive" and allowSurvive == false) then
			table.insert(pool, { type = e.id, weight = e.weight })
		end
	end
	local id = if #pool > 0 then weightedPick(rng, pool) else "WipeOut"
	if not QuestGoalData.IsBuilt(id) then
		quest.goalRolled = id
		id = "WipeOut"
	end
	quest.goal = id
	quest.goalParams = {}
	if id == "Slay" then
		local def = QuestGoalData.Goals.Slay
		-- Half the Grunts (rounded down) become Veterans; they keep the Grunt group's level.
		for i, et in ipairs(quest.enemyTypes) do
			if et.type == "Grunt" then
				local vets = math.floor(et.count * def.veteranShare)
				if vets > 0 then
					et.count -= vets
					table.insert(quest.enemyTypes, i + 1, { type = "Veteran", level = et.level, count = vets })
				end
				break
			end
		end
		quest.goalParams.killTarget = math.max(1, math.ceil(quest.enemyCount * def.killShare[tier]))
	elseif id == "KillTarget" then
		quest.goalParams.target = "Elite"
		addEliteLeader(quest, QuestGoalData.Goals.KillTarget.eliteLevelBonus)
	elseif id == "Survive" or id == "Reach" or id == "Activate" then
		-- Step 3 (2026-11-17): the round limit is fixed on the card. No RNG call (board stays stable);
		-- the Reach tile / Activate object are picked at battle start from the real map's POI tiles.
		local rounds = (QuestGoalData.Goals :: any)[id].rounds
		quest.goalParams.rounds = rounds[tier] or rounds.Normal
	elseif id == "Capture" then
		-- Step 5 (2026-11-17): one Veteran capture target at quest level + levelBonus, first in the
		-- roster (EnemyGenerator copies isCaptureTarget onto the unit). No RNG call (board stays stable).
		local def = QuestGoalData.Goals.Capture
		local lvl = RenownRules.ClampEnemyLevel((quest.recommendedLvl or 1) + (def.levelBonus or 1))
		table.insert(quest.enemyTypes, 1, { type = def.targetType or "Veteran", level = lvl, count = 1, isCaptureTarget = true })
		quest.enemyCount = (quest.enemyCount or 0) + 1
		quest.goalParams.target = def.targetType or "Veteran"
	elseif id == "Destroy" then
		-- Step 4 (2026-11-17): the object count is fixed on the card (no RNG call; board stays stable).
		-- The objects are placed at battle start on the real map's POI tiles.
		local objs = QuestGoalData.Goals.Destroy.objects
		quest.goalParams.objects = objs[tier] or objs.Normal
	elseif id == "Prevent" then
		-- Step 7 (2026-11-17): the runners are first in the roster (EnemyGenerator copies isRunner onto
		-- the units). Runner and loss counts are fixed on the card; no RNG call (board stays stable).
		local def = QuestGoalData.Goals.Prevent
		local n = def.runners[tier] or def.runners.Hard
		local lvl = RenownRules.ClampEnemyLevel((quest.recommendedLvl or 1) + (def.runnerLevelBonus or 0))
		table.insert(quest.enemyTypes, 1, { type = def.runnerType or "Veteran", level = lvl, count = n, isRunner = true })
		quest.enemyCount = (quest.enemyCount or 0) + n
		quest.goalParams.runners = n
		quest.goalParams.lossAt = def.lossAt[tier] or def.lossAt.Hard
	end
end

-- NEW-PLAYER ENEMY TOTAL (game_flow 42, USER RULING 2026-11-18 5:52 PM): in Ranks 1-8 the goal
-- extras count inside the rolled 3-5. Trims Grunts first, then Veterans, then Elites, down to
-- `target`, and never the goal's own unit (capture target, Elite leader, runners). A group may go to
-- 0 here and is then removed. No RNG call, so the saved board stays stable. Returns the new total.
local TRIM_ORDER = { "Grunt", "Veteran", "Elite" }
local function trimToTarget(quest, target: number): number
	local total = 0
	for _, et in ipairs(quest.enemyTypes or {}) do total += et.count end
	for _, kind in ipairs(TRIM_ORDER) do
		if total <= target then break end
		for _, et in ipairs(quest.enemyTypes or {}) do
			if total <= target then break end
			if et.type == kind and not (et.isCaptureTarget or et.isLeader or et.isRunner) then
				local trim = math.min(total - target, et.count)
				et.count -= trim
				total -= trim
			end
		end
	end
	local kept = {}
	for _, et in ipairs(quest.enemyTypes or {}) do
		if et.count > 0 then table.insert(kept, et) end
	end
	quest.enemyTypes = kept
	quest.enemyCount = total
	return total
end

-- Quest types a Daily Contract can be (never a boss: daily systems decision 4, 2026-11-01).
local NON_BOSS_TYPE_WEIGHTS = {}
for _, entry in ipairs(QUEST_TYPE_WEIGHTS) do
	if entry.type ~= "Boss" then table.insert(NON_BOSS_TYPE_WEIGHTS, entry) end
end

-- PROMISED QUEST GEAR (game_flow 36, built 2026-11-17): fixes the gear type and rarity of the
-- quest's gear reward at board refresh (stats roll at victory, RewardService). Rarity from the C-Lean
-- row for the goal the quest plays (QuestGoalData.PromisedGearRow: quick goals one row lower, Daily
-- floor D3 after the shift, Boss none). Gear type from the SAME equipment pool as victory loot. No
-- Fortune. Item level = quest level. Rolled LAST (after the goal) so every earlier roll is unchanged.
local PROMISED_ORDER = { "Common", "Uncommon", "Rare", "Epic" }
local _equipPoolProvider = nil -- optional injection (tests); default = RewardService.GetEquipPool
function QuestGenerator.SetEquipPoolProvider(fn) _equipPoolProvider = fn end
local function equipPool()
	if type(_equipPoolProvider) == "function" then return _equipPoolProvider() end
	-- Lazy require: only at board generation, never at module load (no require cycle).
	local RewardService = require(script.Parent:WaitForChild("RewardService"))
	return RewardService.GetEquipPool()
end

-- 32-bit multiply mod 2^32 without float overflow.
local function mul32(a: number, b: number): number
	local al, ah = a % 65536, a // 65536
	return (al * b + ((ah * b) % 65536) * 65536) % 4294967296
end
-- FNV-1a 32-bit over "key:id" plus the murmur3 fmix32 finaliser (even spread; deterministic, no RNG).
-- Used for the stable gear-type pick.
local function gearHash(key: number, id: string): number
	local s = tostring(key) .. ":" .. id
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = mul32(h, 16777619)
	end
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x85ebca6b)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 0xc2b2ae35)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h
end

-- QUEST TARGET NAME (user 2026-11-18 9:50 PM). Kill target (Elite leader) and Capture quests get the
-- target's name when the quest is generated, so the card, the lore ({target}) and the battle all show
-- the same name. Drawn from rng:Clone() AFTER every other roll: the quest's own RNG stream is never
-- advanced, so every earlier roll (and the saved board) is unchanged, and the same seed always gives
-- the same name (board reopen, rejoin, battle). Word pools = EnemyGenerator.buildEnemyName's pools:
-- <first word of a trait> <doctrine word>. QuestGoalService.TagTarget applies it to the spawned unit.
local function sortedKeys(t: any): { string }
	local out = {}
	if type(t) ~= "table" then return out end
	for k, v in pairs(t) do
		if type(k) == "string" and type(v) == "table" and #v > 0 then table.insert(out, k) end
	end
	table.sort(out)
	return out
end
local _firstKeys: { string }? = nil
local _docKeys: { string }? = nil
local function rollTargetName(quest, rng)
	local gp = quest.goalParams
	if type(gp) ~= "table" then return end
	local named = (quest.goal == "Capture") or (quest.goal == "KillTarget" and gp.target == "Elite")
	if not named then return end
	_firstKeys = _firstKeys or sortedKeys(UnitNameData.FirstWords)
	_docKeys = _docKeys or sortedKeys(UnitNameData.DoctrineWords)
	local fk, dk = _firstKeys :: { string }, _docKeys :: { string }
	if #fk == 0 or #dk == 0 then return end
	local r = rng:Clone() -- copy: draws here never move the quest's real RNG
	local firstPool = UnitNameData.FirstWords[fk[r:NextInteger(1, #fk)]]
	local docPool = UnitNameData.DoctrineWords[dk[r:NextInteger(1, #dk)]]
	gp.targetName = `{firstPool[r:NextInteger(1, #firstPool)]} {docPool[r:NextInteger(1, #docPool)]}`
end

local function rollPromisedGear(quest, rng, isDaily)
	local row = QuestGoalData.PromisedGearRow(quest.goal, quest.difficulty, isDaily, quest.questType == "Boss")
	if not row then return end
	local weights = QuestGoalData.PromisedGear.Rows[row]
	if not weights then return end
	local total = 0
	for _, r in ipairs(PROMISED_ORDER) do total += (weights[r] or 0) end
	local pick = rng:NextNumber() * total
	local rarity = "Common"
	local cum = 0
	for _, r in ipairs(PROMISED_ORDER) do
		cum += (weights[r] or 0)
		if (weights[r] or 0) > 0 and pick <= cum then rarity = r break end
	end
	local pool = equipPool()
	if type(pool) ~= "table" or #pool == 0 then return end
	-- Gear type pick (Tester W4, 2026-11-17): the board only saves its seed, so a promise is rebuilt
	-- from the seed. A plain list-position pick would change most promises whenever gear is added or
	-- removed. Rendezvous hashing instead: ONE rng draw (same RNG consumption as before) is combined
	-- with each archetype id; the highest hash wins. Adding an id only changes promises it now wins
	-- (about 1 in N); removing one only changes promises that had picked it.
	local key = rng:NextInteger(1, 2147483646)
	local bestId, bestHash = nil, -1
	for _, id in ipairs(pool) do
		local h = gearHash(key, id)
		if h > bestHash or (h == bestHash and bestId ~= nil and id < bestId) then bestId, bestHash = id, h end
	end
	if not bestId then return end
	quest.rewards.promisedGear = {
		archetypeId = bestId,
		rarity = rarity,
		level = quest.recommendedLvl,
		row = row,
	}
end

-- opts (optional; nil keeps the normal board unchanged): noBoss = never a boss quest,
-- noMercuryRoll = skip the 1-in-7 quest mercury roll. Dungeon rooms (build step 3) also pass
-- questType / biome / condition / difficulty / fixedLevel; absent = the normal rolls (same RNG order).
-- opts.gate (game_flow 42 new-player gating, 2026-11-18; board quests + Daily Contract only):
--   { rank, diffLo, diffHi, allowBoss }. Same RNG draws as before, different mapping:
--   the difficulty is ONE draw in [diffLo, diffHi], the boss-free type table is used when
--   allowBoss is false, and the enemy-count roll maps through RenownRules.EnemyCountTarget.
--   Never takes roster size (USER RULING 5:52 PM: enemy count must not depend on units owned).
--   Absent (dungeon rooms, test arena) = the old rules exactly.
local function generateOneQuest(questIndex, playerLevel, rng, opts)
	local gate = opts and opts.gate
	-- 1. Quest type (weighted)
	local noBoss = (opts and opts.noBoss) or (gate ~= nil and not gate.allowBoss)
	local questType = if opts and opts.questType then opts.questType
		else weightedPick(rng, if noBoss then NON_BOSS_TYPE_WEIGHTS else QUEST_TYPE_WEIGHTS)

	-- 2. Biome (uniform from all biomes — prototype has no gating)
	local biome = if opts and opts.biome then opts.biome else pickRandom(rng, ALL_BIOMES)

	-- 3. Template from quest type mapping
	local templates = QUEST_TEMPLATES[questType]
	local template = pickRandom(rng, templates)

	-- 4. Battle condition from biome's condition weights
	local biomeInfo = BiomeData[biome]
	local condition = "Clear"
	if opts and opts.condition then
		condition = opts.condition
	elseif biomeInfo and biomeInfo.battleConditionWeights then
		condition = weightedPickMap(rng, biomeInfo.battleConditionWeights)
	end

	-- 5. Difficulty: 1-5 uniform without a gate; with a gate ONE draw inside the slot's band (always
	-- a real NextInteger call, also for Medium 3..3, so the draw count never depends on the band).
	local difficulty = if opts and opts.difficulty then opts.difficulty
		elseif gate then rng:NextInteger(gate.diffLo, gate.diffHi)
		else rng:NextInteger(1, 5)

	-- 6. Recommended level (loot_progression 87, Renown step 3 2026-11-13): playerLevel is the
	-- Renown Rank. Rank + (difficulty - 3) x 2 +/- 1, kept 1-99. Enemy levels below are clamped <= 99.
	local recommendedLvl = if opts and opts.fixedLevel then opts.fixedLevel
		else RenownRules.QuestLevel(playerLevel, difficulty, rng:NextInteger(-1, 1))
	local clampLvl = RenownRules.ClampEnemyLevel

	-- 7. Player slots
	local slotOptions = QUEST_PLAYER_SLOTS[questType]
	-- The quest's normal deploy slots at every Rank (game_flow 42, 5:52 PM: no units-owned cap).
	local playerSlots = pickRandom(rng, slotOptions)

	-- 8. Enemy roster
	local enemyTypes = {}
	local totalEnemyCount = 0

	if questType == "Boss" then
		-- Boss quests always have 1 Boss + supporting Grunts
		local bossLvl = recommendedLvl + rng:NextInteger(0, 2)
		table.insert(enemyTypes, { type = "Boss", level = clampLvl(bossLvl), count = 1 })
		local gruntCount = rng:NextInteger(1, 2)
		local gruntLvl = recommendedLvl + rng:NextInteger(-2, 0)
		table.insert(enemyTypes, { type = "Grunt", level = clampLvl(gruntLvl), count = gruntCount })
		totalEnemyCount = 1 + gruntCount
	else
		local roster = ENEMY_ROSTER_BY_DIFFICULTY[difficulty]
		local gruntCount = randRange(rng, roster.gruntMin, roster.gruntMax)
		local vetCount   = randRange(rng, roster.vetMin, roster.vetMax)
		local eliteCount = randRange(rng, roster.eliteMin, roster.eliteMax)

		if gruntCount > 0 then
			local gruntLvl = recommendedLvl + rng:NextInteger(-2, 0)
			table.insert(enemyTypes, { type = "Grunt", level = clampLvl(gruntLvl), count = gruntCount })
		end
		if vetCount > 0 then
			local vetLvl = recommendedLvl + rng:NextInteger(-1, 1)
			table.insert(enemyTypes, { type = "Veteran", level = clampLvl(vetLvl), count = vetCount })
		end
		if eliteCount > 0 then
			local eliteLvl = recommendedLvl + rng:NextInteger(0, 2)
			table.insert(enemyTypes, { type = "Elite", level = clampLvl(eliteLvl), count = eliteCount })
		end

		totalEnemyCount = gruntCount + vetCount + eliteCount
	end

	-- Enemy count budget: 2x-2.5x the quest's DEPLOYABLE party size (playerSlots),
	-- NOT the number the player actually deploys. E.g. playerSlots=6 -> 12-15 enemies,
	-- playerSlots=3 -> 6-8. (dev-locked 2026-09-26; replaces the old fixed 3-6 prototype
	-- clamp and satisfies the DB's open P0 "Encounter unit-count budget" in code.)
	-- 2026-11-18 5:52 PM (open_decisions 51 / game_flow 42): Ranks 1-8 roll 3-5 enemies (uniform),
	-- fixed by Rank, never by units owned. Rank 9+ and ungated quests keep the rule above. Both use
	-- the same single NextNumber draw; the numbers live in RenownRules.Data (DAT-001). Goal extras
	-- are trimmed back inside this target after the goal roll (step 13b).
	local countRoll = rng:NextNumber()
	local enemyTarget = RenownRules.EnemyCountTarget(gate and gate.rank, playerSlots, countRoll)

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
			table.insert(enemyTypes, { type = "Grunt", level = clampLvl(gruntLvl), count = needed })
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

	-- 13. Main goal (game_flow 41): LAST roll, after quest mercury. opts.goal fixes it (dungeon
	-- rooms, test arena) and skips the roll.
	if opts and opts.goal then
		quest.goal = opts.goal
		quest.goalParams = {}
	else
		-- W1 (step 2): a failing goal roll never stops quest generation; it plays as Wipe out.
		-- pcall adds no RNG calls, so a successful roll is unchanged for the same seed.
		local allowSurvive = if gate then RenownRules.SurviveAllowed(gate.rank) else nil
		local okGoal, errGoal = pcall(rollGoal, quest, rng, allowSurvive)
		if not okGoal then
			warn("[QuestGenerator] Goal roll failed (quest plays as Wipe out): " .. tostring(errGoal))
			quest.goal = "WipeOut"
			quest.goalParams = {}
		end
	end

	-- 13b. Ranks 1-8 (game_flow 42, USER RULING 2026-11-18 5:52 PM): goal extras (Capture +1, Kill
	-- target +1 Elite leader) count INSIDE the rolled 3-5 total. No RNG call (board stays stable).
	local enemyCap = if gate then RenownRules.NewPlayerEnemyCap(gate.rank) else nil
	if enemyCap ~= nil then
		local limit = math.min(enemyTarget, enemyCap)
		if (quest.enemyCount or 0) > limit then
			trimToTarget(quest, limit)
		end
	end

	-- 14. Promised gear (game_flow 36): LAST roll, after the goal. Dungeon rooms and the test arena
	-- pass noPromisedGear. A failure never stops quest generation (the quest just has no promise).
	if not (opts and opts.noPromisedGear) then
		local okPg, errPg = pcall(rollPromisedGear, quest, rng, opts and opts.isDaily == true)
		if not okPg then
			warn("[QuestGenerator] Promised gear roll failed (no promise on this quest): " .. tostring(errPg))
			quest.rewards.promisedGear = nil
		end
	end

	-- 15. Target name (user 2026-11-18 9:50 PM): no RNG draw on the real stream (rng:Clone()).
	-- A failure only leaves the target unnamed on the card (the battle names it as before).
	do
		local okNm, errNm = pcall(rollTargetName, quest, rng)
		if not okNm then warn("[QuestGenerator] Target name roll failed (unnamed on the card): " .. tostring(errNm)) end
	end

	return quest
end

--------------------------------------------------
-- PUBLIC API
--------------------------------------------------

-- NEW-PLAYER GATING CONTEXT (game_flow 42, USER RULING 2026-11-18 5:17 PM). ctx (optional):
-- { boardLevel = number }. Missing boardLevel: Generate uses count - 2, else L1. Roster size is
-- deliberately NOT part of the gate (USER RULING 5:52 PM: enemy count never depends on units owned).
local function boardGate(rank: number, slot: number, boardLevel: number): any
	local band = RenownRules.BoardSlotBand(slot, rank, boardLevel)
	local lo, hi = RenownRules.DifficultyRange(band)
	return {
		rank = rank, band = band, diffLo = lo, diffHi = hi,
		-- Boss cards (Rank 16+) take a Medium or Hard slot, never an Easy one (game_flow 42 default).
		allowBoss = RenownRules.BossQuestsAllowed(rank) and band ~= "Easy",
	}
end

-- DAILY CONTRACT (daily systems decisions 4-6, USER DECISION 2026-11-01): one per real day,
-- built from a seed fixed by the day, so refreshing the board always shows the same contract.
-- A normal battle (never a boss; never an elite once elites exist). Reward = normal quest rewards
-- + 3 mercury (materials_system 13, paid as its quest mercury; was 5 until 2026-11-01); every 3rd one also gives 1 sulfur
-- (Main / CurrencyService). It replaces the random quest-mercury roll.
-- 2026-11-18 (live_service_features 11 / game_flow 42): difficulty is one draw from the same allowed
-- pool as the board (1-3 until Hard is allowed, then 1-5) and the enemy count follows the Rank rules.
local DAILY_CONTRACT_MERCURY = 3 -- USER DECISION 2026-11-01 (Simulator boss/daily check): was 5

function QuestGenerator.GenerateDailyContract(playerLevel, day, ctx)
	local rng = Random.new(day * 1000003 + 424241)
	local boardLevel = math.max(1, math.floor(tonumber(ctx and ctx.boardLevel) or 1))
	local gate = {
		rank = playerLevel, band = "Daily", diffLo = 1,
		diffHi = RenownRules.MaxAllowedDifficulty(playerLevel, boardLevel), allowBoss = false,
	}
	local quest = generateOneQuest(0, playerLevel, rng, { noBoss = true, noMercuryRoll = true, isDaily = true, gate = gate })
	quest.id = string.format("daily_%d", day)
	quest.name = "Daily Contract: " .. quest.name
	quest.isDailyContract = true
	quest.dailyDay = day
	quest.rewards.mercury = DAILY_CONTRACT_MERCURY
	print(string.format("[QuestGenerator] Daily Contract for day %d: %s | %s/%s | Lv %d | %d enemies",
		day, quest.name, quest.biome, quest.template, quest.recommendedLvl, quest.enemyCount))
	return quest
end

-- TEST ARENA (user request 2026-11-05): a persistent STUDIO-ONLY quest on the 8x8 T99 map so
-- units can fight on turn 1. Counts as a real battle (normal rewards/progress, user ruling).
-- 5 deployable vs 6 mixed enemies (3 Grunt, 2 Veteran, 1 Elite) at the given level. Plains
-- (random weather),
-- never a boss, no quest-mercury roll, never turned into an elite encounter (Main).
function QuestGenerator.GenerateTestArena(level)
	local lvl = math.max(1, math.floor(tonumber(level) or 1))
	local rng = Random.new(990099)
	local quest = generateOneQuest(0, lvl, rng, { noBoss = true, noMercuryRoll = true, goal = "WipeOut", noPromisedGear = true })
	quest.id = "test_arena"
	quest.name = "Test Arena (Studio)"
	quest.description = "8x8 test map. Enemies are in reach on turn 1."
	quest.isTestArena = true
	quest.questType = "Standard"
	quest.biome = "Plains"
	quest.template = "T99"
	-- Weather is random (user rulings 2026-11-05/06): the card says "Random" and the battle
	-- uses the map generator's Plains roll (Main battle start).
	quest.condition = "Random"
	quest.playerSlots = 5
	quest.recommendedLvl = lvl
	quest.enemyTypes = {
		{ type = "Grunt",   level = lvl, count = 3 },
		{ type = "Veteran", level = lvl, count = 2 },
		{ type = "Elite",   level = lvl, count = 1 },
	}
	quest.enemyCount = 6
	-- Re-derive everything the discarded random roll fed (Tester UAT 2026-11-05, c1): the posted
	-- gold, completion gold, drops and difficulty must match THIS quest (Standard, level lvl).
	-- Difficulty 4 = the roster tier that carries exactly one Elite (ENEMY_ROSTER_BY_DIFFICULTY).
	quest.difficulty = 4
	local questGold = math.floor(QUEST_GOLD_NORMAL * (1 + lvl / 40))
	quest.rewards.gold = { min = questGold, max = questGold }
	quest.rewards.questGold = questGold
	quest.rewards.completionGoldBase = COMPLETION_GOLD_NORMAL
	local baseXP = BASE_XP[quest.difficulty]
	local xpVar = math.floor(baseXP * 0.25)
	quest.rewards.xp = { min = baseXP - xpVar, max = baseXP + xpVar }
	quest.rewards.drops = "Equipment"
	return quest
end

-- DUNGEON ROOM BATTLE (Dungeon build step 3, 2026-11-13; project_rules 121/263): the room gives the
-- type (Boss room = Boss quest, else a normal non-boss type), the run gives biome, fixed weather and
-- difficulty, DungeonService gives the level (quest level + floor - 1). No quest gold and no quest
-- mercury (dungeon battles have no guaranteed rewards); battle completion and kill gold still apply.
function QuestGenerator.GenerateDungeonBattle(spec)
	local rng = Random.new(spec.seed)
	local quest = generateOneQuest(0, spec.level, rng, {
		noBoss = not spec.isBoss, noMercuryRoll = true,
		questType = if spec.isBoss then "Boss" else nil,
		biome = spec.biome, condition = spec.condition,
		difficulty = spec.difficulty, fixedLevel = spec.level,
		goal = "WipeOut", -- dungeon rooms keep today's win rule (build step 1 default)
		noPromisedGear = true, -- dungeon rooms never get promised gear (game_flow 36)
	})
	quest.id = "dungeon_" .. tostring(spec.nodeId)
	quest.isDungeon = true
	quest.dungeonNodeId = spec.nodeId
	quest.dungeonPlayed = spec.played
	quest.dungeonDropMult = spec.dropMultiplier
	quest.dungeonLootScale = spec.lootScale
	quest.dungeonRarityBonus = spec.rarityFortuneBonus -- Elite/Boss rarity step (0 on normal rooms)
	quest.dungeonMapSeed = spec.seed -- same room = same battlefield on replay (project_rules 266)
	quest.dungeonStage = spec.stage or 1 -- stages (rule 277)
	quest.dungeonGoldMult = spec.goldMult or 1 -- stage gold x1.25 / x1.5 (rule 263)
	quest.rewards.questGold = 0
	quest.rewards.gold = { min = 0, max = 0 }
	quest.rewards.mercury = nil
	print(string.format("[QuestGenerator] Dungeon room %s (%s): %s | %s | Lv %d | %d enemies | %s",
		tostring(spec.nodeId), tostring(spec.played), quest.questType, quest.biome, quest.recommendedLvl,
		quest.enemyCount, quest.condition))
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
	-- D-1 fix (2026-11-01): the result is always the card's own count + 1. Every Elite on the
	-- card becomes a Veteran, then the Elite leader is added, so a card that had 0 Elites and a
	-- card that had 1 both end with exactly one Elite and one extra enemy (addEliteLeader).
	local leaderLvl = addEliteLeader(quest, ELITE_LEADER_LEVEL_BONUS)
	quest.isEliteEncounter = true
	-- W2 (quest goals step 2): a Slay quest that becomes an elite encounter recounts its kill target
	-- from the new enemy count, so it stays the game_flow 41 share. The elite encounter is decided
	-- at departure (hidden on the card), so the card's number can be 1 lower than the battle's;
	-- the Quest accepted view and the battle tracker (build step 8) must read this updated number.
	if quest.goal == "Slay" and quest.goalParams then
		local share = QuestGoalData.Goals.Slay.killShare[QuestGoalData.TierOf(quest.difficulty)]
		local before = quest.goalParams.killTarget
		quest.goalParams.killTarget = math.max(1, math.ceil(quest.enemyCount * share))
		print(string.format("[QuestGenerator] Slay kill target %s -> %d (elite encounter)", tostring(before), quest.goalParams.killTarget))
	end
	print(string.format("[QuestGenerator] Elite encounter: %s | %d enemies, Elite leader Lv %d", quest.name, quest.enemyCount, leaderLvl))
	return quest
end

-- QUEST BOARD SCREEN DATA (Quest Board redesign step 1, 2026-11-17). Display helpers only; no
-- gameplay change.
-- LevelRange: the real enemy level range of the card, from the same enemyTypes levels the battle
-- spawns (EnemyGenerator uses spec.level as is). A hidden elite encounter (MakeEliteEncounter, +2
-- leader) is applied at departure and is not part of the card. Fallback: recommendedLvl.
function QuestGenerator.LevelRange(quest): (number, number)
	local lo, hi = math.huge, -math.huge
	for _, et in ipairs((quest and quest.enemyTypes) or {}) do
		local lv = tonumber(et.level)
		if lv and (tonumber(et.count) or 1) > 0 then
			lo = math.min(lo, lv)
			hi = math.max(hi, lv)
		end
	end
	if lo == math.huge then
		local rec = math.max(1, math.floor(tonumber(quest and quest.recommendedLvl) or 1))
		return rec, rec
	end
	return lo, hi
end

-- CancelFee: the gold AbandonQuest charges (game_flow 28): 50% of the quest's posted gold, floored.
-- Dungeon room battles post no quest gold, so their fee is 0. The ONE place this rule lives:
-- Main's abandon handler and the Quest Board card both call it. The charge is still clamped to
-- the player's balance at abandon time (Main).
function QuestGenerator.CancelFee(quest): number
	if not quest or quest.isDungeon then return 0 end
	local posted = (quest.rewards and tonumber(quest.rewards.questGold)) or 0
	return math.floor(posted * 0.5)
end

--- Generate 3 quests for the quest board.
--- @param playerLevel number Renown Rank (quest level = Rank + (difficulty - 3) x 2 +/- 1)
--- @param seed number Base seed (e.g. os.time())
--- @return table { quest1, quest2, quest3 }
-- count (2026-11-16): number of quests; the Quest Board level adds one per level above 1
-- (Quest Board L1 = 3, the old fixed number). Missing or bad = 3.
-- ctx (2026-11-18, game_flow 42): { boardLevel } for the new-player gating. Quest i
-- gets the band of board slot i (RenownRules.BoardSlotBand), so an upgrade still only ADDS a card.
function QuestGenerator.Generate(playerLevel, seed, count, ctx)
	local quests = {}
	local n = math.clamp(math.floor(tonumber(count) or 3), 1, 12)
	local boardLevel = math.max(1, math.floor(tonumber(ctx and ctx.boardLevel) or (n - 2)))
	for i = 0, n - 1 do
		local rng = Random.new(seed + i)
		local quest = generateOneQuest(i + 1, playerLevel, rng, { gate = boardGate(playerLevel, i + 1, boardLevel) })
		table.insert(quests, quest)
	end

	print(string.format("[QuestGenerator] Generated %d quests (seed=%d, level=%d, board L%d):",
		n, seed, playerLevel, boardLevel))
	for _, q in ipairs(quests) do
		print(string.format("  [%s] %s | %s/%s | Diff %d | Lv %d | %d enemies | %d slots | %s | %s",
			q.id, q.name, q.biome, q.template, q.difficulty, q.recommendedLvl, q.enemyCount,
			tonumber(q.playerSlots) or 0, tostring(q.goal), q.condition))
	end

	return quests
end

--- Elite encounters allowed at this Rank (loot_progression 69: Rank 9+). Main checks this BEFORE the
--- hidden roll; the completed-battle count still advances in Ranks 1-8 (the roll is just ignored).
function QuestGenerator.EliteEncountersAllowed(rank: number?): boolean
	return RenownRules.EliteEncountersAllowed(rank)
end

return QuestGenerator
