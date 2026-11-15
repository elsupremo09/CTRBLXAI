--!strict
-- RenownRules.lua
-- CTRBLXAI | Renown (replaces Guild Level) — every Renown number and formula, ONE place.
--
-- Server-only (ARC-003): the client receives finished numbers, never these formulas.
-- Pure functions only: no state, no requires, no side effects (DAT-001/002/003).
--
-- LOCKED DATA, copied from CTRBLXAI.db (USER RULING 2026-11-12 6:17 / 6:21 / 6:30 PM).
-- The design DB is the single source of truth; do not tune numbers here.
--   loot_progression 74  rewards per successful quest; Hard = difficulty 4-5; Elite pays as Boss
--   loot_progression 80  anti-farming bands on min(Rank, 99) - quest level
--   loot_progression 82  Renown to next Rank = 250 + Rank x 5
--   loot_progression 83/89  no Rank cap
--   loot_progression 87  quest level = Rank + (difficulty - 3) x 2 +/- 1, kept 1-99; enemy levels <= 99
--   loot_progression 88  above Rank 99 the gap uses min(Rank, 99)
--   loot_progression 90  failed quest costs 3x the reward; never drops a Rank
--   loot_progression 91  +1 roster slot every 5 Ranks on top of the base 10
--   loot_progression 75  recruits appear around Rank - 5 to Rank
--   loot_progression 93  old saves: starting Rank = highest unit level - 2 (at least 1)
--   guild_facilities 50 (+12/41 notes)  Blacksmith cap includes the Rank + 5 term

local RenownRules = {}

RenownRules.Data = table.freeze({
	-- loot_progression 74 (base Renown for a SUCCESSFUL quest, by kind)
	Rewards = table.freeze({
		Normal      = 100,
		Hard        = 130,
		Boss        = 200,
		Exploration = 250,
	}),
	HardMinDifficulty = 4,      -- loot_progression 74: Hard = difficulty 4-5
	FailMultiplier    = 3,      -- loot_progression 90
	CurveBase         = 250,    -- loot_progression 82
	CurvePerRank      = 5,
	-- loot_progression 80: gap = min(Rank, GapRankCeiling) - quest level; first band whose
	-- maxGap >= gap applies. A quest above your Rank (negative gap) is x1.0, no bonus.
	Bands = table.freeze({
		table.freeze({ maxGap = 5,  mult = 1.00 }),
		table.freeze({ maxGap = 10, mult = 0.75 }),
		table.freeze({ maxGap = 15, mult = 0.50 }),
		table.freeze({ maxGap = 20, mult = 0.25 }),
	}),
	BandFloorMult     = 0.10,   -- gap 21+
	GapRankCeiling    = 99,     -- loot_progression 88
	QuestLevelPerStep = 2,      -- loot_progression 87: (difficulty - 3) x 2
	QuestLevelCentre  = 3,
	QuestLevelJitter  = 1,      -- +/- 1
	MinLevel          = 1,
	MaxLevel          = 99,     -- quest and enemy levels (units/gear launch cap)
	RosterBase        = 10,     -- loot_progression 91
	RanksPerSlot      = 5,
	BlacksmithRankBonus = 5,    -- guild_facilities 50: Rank + 5
	RecruitWindowBelow  = 5,    -- loot_progression 75: Rank - 5 .. Rank
	ConvertBelowHighest = 2,    -- loot_progression 93
	StartRank           = 1,
})

local D = RenownRules.Data

local function toInt(n: any, fallback: number): number
	local v = tonumber(n)
	if v == nil or v ~= v then return fallback end
	return math.floor(v)
end

--- Quest kind for Renown. Returns nil when the content pays no Renown (Test Arena).
--- isElite and isBoss win over difficulty; Exploration is passed in by the explore path.
function RenownRules.QuestKind(difficulty: number?, isBoss: boolean?, isElite: boolean?,
	isExploration: boolean?, isTestArena: boolean?): string?
	if isTestArena then return nil end              -- loot_progression 74 (dev default)
	if isExploration then return "Exploration" end
	if isBoss or isElite then return "Boss" end      -- Elite pays as Boss
	if toInt(difficulty, 1) >= D.HardMinDifficulty then return "Hard" end
	return "Normal"
end

--- Base reward for a successful quest of this kind (0 for unknown kinds).
function RenownRules.BaseReward(kind: string?): number
	if kind == nil then return 0 end
	return (D.Rewards :: any)[kind] or 0
end

--- Nominal penalty for a failed quest of this kind: 3x the BASE reward (before any band).
function RenownRules.FailPenalty(kind: string?): number
	return RenownRules.BaseReward(kind) * D.FailMultiplier
end

--- Renown needed to go from `rank` to `rank + 1`. No Rank cap.
function RenownRules.RenownToNext(rank: number): number
	return D.CurveBase + math.max(D.StartRank, toInt(rank, D.StartRank)) * D.CurvePerRank
end

--- Anti-farming multiplier for this Rank and quest level.
function RenownRules.BandMultiplier(rank: number, questLevel: number): number
	local gap = math.min(toInt(rank, D.StartRank), D.GapRankCeiling) - toInt(questLevel, D.MinLevel)
	for _, b in D.Bands do
		if gap <= b.maxGap then return b.mult end
	end
	return D.BandFloorMult
end

--- Renown a successful quest pays at this Rank (base x band, rounded down).
function RenownRules.QuestReward(kind: string?, rank: number, questLevel: number): number
	local base = RenownRules.BaseReward(kind)
	if base <= 0 then return 0 end
	return math.floor(base * RenownRules.BandMultiplier(rank, questLevel))
end

--- Quest level for a Rank and difficulty. `jitter` is -1, 0 or +1 (pass rng:NextInteger(-1, 1));
--- nil means 0. Kept between 1 and 99.
function RenownRules.QuestLevel(rank: number, difficulty: number, jitter: number?): number
	local j = math.clamp(toInt(jitter, 0), -D.QuestLevelJitter, D.QuestLevelJitter)
	local lvl = toInt(rank, D.StartRank) + (toInt(difficulty, D.QuestLevelCentre) - D.QuestLevelCentre) * D.QuestLevelPerStep + j
	return math.clamp(lvl, D.MinLevel, D.MaxLevel)
end

--- Enemy level clamp (boss / elite +0..2 bonus included by the caller before clamping).
function RenownRules.ClampEnemyLevel(level: number): number
	return math.clamp(toInt(level, D.MinLevel), D.MinLevel, D.MaxLevel)
end

--- Extra roster slots from Rank (on top of the base).
function RenownRules.RosterBonus(rank: number): number
	return math.floor(math.max(0, toInt(rank, D.StartRank)) / D.RanksPerSlot)
end

--- Roster capacity from Rank: base 10 + 1 per 5 Ranks.
function RenownRules.RosterCapacity(rank: number): number
	return D.RosterBase + RenownRules.RosterBonus(rank)
end

--- The Rank part of the Blacksmith cap (the caller takes the min with building and highest unit).
function RenownRules.BlacksmithRankCap(rank: number): number
	return toInt(rank, D.StartRank) + D.BlacksmithRankBonus
end

--- Recruit level window for this Rank: Rank - 5 .. Rank, at least 1, at most 99.
function RenownRules.RecruitWindow(rank: number): (number, number)
	local r = toInt(rank, D.StartRank)
	local hi = math.clamp(r, D.MinLevel, D.MaxLevel)
	local lo = math.clamp(r - D.RecruitWindowBelow, D.MinLevel, hi)
	return lo, hi
end

--- Starting Rank for an old save: highest unit level - 2, at least 1.
function RenownRules.ConvertedRank(highestUnitLevel: number?): number
	return math.max(D.StartRank, toInt(highestUnitLevel, D.StartRank) - D.ConvertBelowHighest)
end

return RenownRules
