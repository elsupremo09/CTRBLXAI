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
--   loot_progression 82  Renown to next Rank, "Three stages" (USER 2026-11-18 4:43 PM, replaces 250 + Rank x 5):
--                        Ranks 1-10: 200 + 5 x Rank; 11-50: 250 + 15 x (Rank - 10); 51+: 850 + 60 x (Rank - 50)
--   loot_progression 74  (2026-11-18 4:59 PM) quest Renown x (1 + 0.01 x (Rank - 50)) from Rank 51, bands after
--   loot_progression 83/89  no Rank cap
--   loot_progression 87  quest level = Rank + (difficulty - 3) x 2 +/- 1, kept 1-99; enemy levels <= 99
--   loot_progression 88  above Rank 99 the gap uses min(Rank, 99)
--   loot_progression 90  failed quest costs 3x the BASE reward up to Rank 50, 1x from Rank 51 (2026-11-18 4:48 PM);
--                        never scaled, never drops a Rank
--   loot_progression 91  +1 roster slot every 5 Ranks on top of the base 10
--   loot_progression 75  recruits appear around Rank - 5 to Rank
--   loot_progression 93  old saves: starting Rank = highest unit level - 2 (at least 1)
--   guild_facilities 50 (+12/41 notes)  Blacksmith cap includes the Rank + 5 term
--   game_flow 42         new-player quest gating by Rank band (USER RULING 2026-11-18 5:17 PM; Herald
--                        un-gated 5:25 PM): difficulty pool, board mix, enemy count, Survive / elite /
--                        boss gates. Also guild_facilities 17/113, game_flow 41, loot_progression 69,
--                        unit_progression 72, open_decisions 51, live_service_features 11.
--                        USER RULING 5:52 PM: Ranks 1-8 enemy count = 3-5 fixed by Rank (goal extras
--                        inside the total); it NEVER depends on roster size (exploit: keep the roster
--                        small for easy fights). Deploy slots stay the quest's normal 5-7 at all Ranks.

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
	FailMultiplier    = 3,      -- loot_progression 90: Ranks 1-50
	FailMultiplierLate = 1,     -- loot_progression 90: from LateRank (2026-11-18 4:48 PM)
	LateRank          = 51,     -- start of the steep stage: 1x penalty, reward scaling, always-fee Escape
	-- loot_progression 82 "Three stages" (2026-11-18 4:43 PM)
	CurveEarlyMax     = 10,     -- Ranks 1-10: EarlyBase + EarlyPerRank x Rank
	CurveEarlyBase    = 200,
	CurveEarlyPerRank = 5,
	CurveMidMax       = 50,     -- Ranks 11-50: MidBase + MidPerRank x (Rank - 10)
	CurveMidBase      = 250,
	CurveMidPerRank   = 15,
	CurveLateBase     = 850,    -- Rank 51+: LateBase + LatePerRank x (Rank - 50)
	CurveLatePerRank  = 60,
	RewardScalePctPerRank = 1,  -- loot_progression 74: +1% per Rank above 50 (Rank 99 = 149%)
	-- Old curve, kept ONLY for the one-time rescale of saves written before 2026-11-18 (curve version 1).
	CurveV1Base       = 250,
	CurveV1PerRank    = 5,
	CurveVersion      = 2,
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
	-- game_flow 42 NEW-PLAYER QUEST GATING (USER RULING 2026-11-18 5:17 PM)
	NewPlayerMaxRank      = 8,  -- Ranks 1-8 = learning period
	SurviveMinRank        = 9,  -- game_flow 41: Survive goal from Rank 9
	EliteEncounterMinRank = 9,  -- loot_progression 69: elite encounters from Rank 9
	BossQuestMinRank      = 16, -- unit_progression 72 / guild_facilities 17
	HardQuestMinRank      = 16, -- guild_facilities 17: Hard needs Rank 16 AND Quest Board L3+
	HardQuestBoardLevel   = 3,  -- guild_facilities 17 / 113 ('Unlocks: Hard quests' at L3)
	MaxDifficulty         = 5,
	-- Easy = 1-2, Medium = 3, Hard = 4-5; inside a band each value is equally likely (agent default).
	DifficultyBands = table.freeze({
		Easy   = table.freeze({ lo = 1, hi = 2 }),
		Medium = table.freeze({ lo = 3, hi = 3 }),
		Hard   = table.freeze({ lo = 4, hi = 5 }),
	}),
	-- Band of each board quest slot (slot 1 = first card). L1 = slots 1-3 (2E/1M), L2 adds slot 4 (M),
	-- L3+ each level adds one slot per the Designer table (L3 2/2/1 ... L10 2/5/5). A Hard slot below
	-- Rank 16 or Quest Board L3 plays as Medium. Slots past the table are Medium.
	BoardSlotBands = table.freeze({
		"Easy", "Easy", "Medium", "Medium", "Hard", "Hard",
		"Medium", "Hard", "Medium", "Hard", "Medium", "Hard",
	}),
	-- Enemy count per quest (open_decisions 51, USER RULING 2026-11-18 5:52 PM). Ranks 1-8: 3-5 enemies
	-- (uniform), fixed by Rank, goal extras (Capture / Kill target) INSIDE the total. Never depends on
	-- units owned. Rank 9+: round(deploy slots x [2.0, 2.5)) (dev-locked 2026-09-26, moved here from
	-- QuestGenerator unchanged).
	NewPlayerEnemyMin      = 3,
	NewPlayerEnemyMax      = 5,
	EnemyMultMin           = 2.0,
	EnemyMultSpan          = 0.5,
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

--- Nominal penalty for a failed quest of this kind at this Rank: 3x the BASE reward up to Rank 50,
--- 1x from Rank 51 (loot_progression 90, 2026-11-18). Never scaled, never banded.
function RenownRules.FailPenalty(kind: string?, rank: number?): number
	local r = toInt(rank, D.StartRank)
	local mult = if r >= D.LateRank then D.FailMultiplierLate else D.FailMultiplier
	return RenownRules.BaseReward(kind) * mult
end

--- True from Rank 51 (the steep stage). Used by the Escape fee rule (project_rules 285, 2026-11-18).
function RenownRules.IsLateRank(rank: number?): boolean
	return toInt(rank, D.StartRank) >= D.LateRank
end

--- Reward scale in whole percent: 100 up to Rank 50, then 100 + (Rank - 50) (no cap, like the Rank).
function RenownRules.RewardScalePct(rank: number?): number
	local r = toInt(rank, D.StartRank)
	return 100 + math.max(0, r - (D.LateRank - 1)) * D.RewardScalePctPerRank
end

--- Base reward scaled for the Rank, before the anti-farm band (rounded down).
function RenownRules.ScaledReward(kind: string?, rank: number?): number
	return math.floor(RenownRules.BaseReward(kind) * RenownRules.RewardScalePct(rank) / 100)
end

--- Renown needed to go from `rank` to `rank + 1`. No Rank cap. "Three stages" (loot_progression 82).
function RenownRules.RenownToNext(rank: number): number
	local r = math.max(D.StartRank, toInt(rank, D.StartRank))
	if r <= D.CurveEarlyMax then return D.CurveEarlyBase + D.CurveEarlyPerRank * r end
	if r <= D.CurveMidMax then return D.CurveMidBase + D.CurveMidPerRank * (r - D.CurveEarlyMax) end
	return D.CurveLateBase + D.CurveLatePerRank * (r - D.CurveMidMax)
end

--- The pre-2026-11-18 curve (250 + Rank x 5). ONLY for rescaling saves of curve version 1.
function RenownRules.RenownToNextV1(rank: number): number
	return D.CurveV1Base + math.max(D.StartRank, toInt(rank, D.StartRank)) * D.CurveV1PerRank
end

--- Anti-farming multiplier for this Rank and quest level.
function RenownRules.BandMultiplier(rank: number, questLevel: number): number
	local gap = math.min(toInt(rank, D.StartRank), D.GapRankCeiling) - toInt(questLevel, D.MinLevel)
	for _, b in D.Bands do
		if gap <= b.maxGap then return b.mult end
	end
	return D.BandFloorMult
end

--- Renown a successful quest pays at this Rank: base x Rank scale x band, rounded down once.
--- Integer percent maths, so e.g. Normal at Rank 99 is exactly 149 (no float 148.99).
function RenownRules.QuestReward(kind: string?, rank: number, questLevel: number): number
	local base = RenownRules.BaseReward(kind)
	if base <= 0 then return 0 end
	local bandPct = math.floor(RenownRules.BandMultiplier(rank, questLevel) * 100 + 0.5)
	return math.floor(base * RenownRules.RewardScalePct(rank) * bandPct / 10000)
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

--------------------------------------------------
-- NEW-PLAYER QUEST GATING (game_flow 42, USER RULING 2026-11-18 5:17 PM)
--------------------------------------------------

--- True in the new-player learning period (Ranks 1-8).
function RenownRules.IsNewPlayerRank(rank: number?): boolean
	return toInt(rank, D.StartRank) <= D.NewPlayerMaxRank
end

--- Survive goal allowed (game_flow 41): Rank 9+.
function RenownRules.SurviveAllowed(rank: number?): boolean
	return toInt(rank, D.StartRank) >= D.SurviveMinRank
end

--- Elite encounters allowed (loot_progression 69): Rank 9+.
function RenownRules.EliteEncountersAllowed(rank: number?): boolean
	return toInt(rank, D.StartRank) >= D.EliteEncounterMinRank
end

--- Boss quest cards allowed (unit_progression 72): Rank 16+. (The Herald event is NOT gated.)
function RenownRules.BossQuestsAllowed(rank: number?): boolean
	return toInt(rank, D.StartRank) >= D.BossQuestMinRank
end

--- Hard quests (difficulty 4-5) allowed (guild_facilities 17): Rank 16+ AND Quest Board L3+.
function RenownRules.HardQuestsAllowed(rank: number?, boardLevel: number?): boolean
	return toInt(rank, D.StartRank) >= D.HardQuestMinRank and toInt(boardLevel, 1) >= D.HardQuestBoardLevel
end

--- Band ("Easy" | "Medium" | "Hard") of board quest slot `slot` (1-based). Hard falls back to Medium
--- while Hard quests are not allowed.
function RenownRules.BoardSlotBand(slot: number, rank: number?, boardLevel: number?): string
	local band = D.BoardSlotBands[toInt(slot, 1)] or "Medium"
	if band == "Hard" and not RenownRules.HardQuestsAllowed(rank, boardLevel) then
		band = "Medium"
	end
	return band
end

--- Difficulty range (lo, hi) of a band. Unknown band = Medium.
function RenownRules.DifficultyRange(band: string?): (number, number)
	local b = (D.DifficultyBands :: any)[band or "Medium"] or D.DifficultyBands.Medium
	return b.lo, b.hi
end

--- Highest difficulty allowed for this Rank and board (Daily Contract pool): 5 with Hard, else 3.
function RenownRules.MaxAllowedDifficulty(rank: number?, boardLevel: number?): number
	if RenownRules.HardQuestsAllowed(rank, boardLevel) then return D.MaxDifficulty end
	return D.DifficultyBands.Medium.hi
end

--- Enemy count target for a quest. `roll` is one rng:NextNumber() in [0, 1). rank nil = the Rank 9+
--- rule (dungeon rooms / test arena). Ranks 1-8: 3, 4 or 5 (uniform), never from roster size.
--- BUG-142 (2026-11-22): multMin / multSpan (optional) replace Data.EnemyMultMin / EnemyMultSpan for the
--- Rank 9+ formula; only dungeon rooms pass them (DungeonRules.Data.EnemyMultMin / EnemyMultSpan). nil = quests.
function RenownRules.EnemyCountTarget(rank: number?, deploySlots: number, roll: number, multMin: number?, multSpan: number?): number
	local slots = math.max(1, toInt(deploySlots, 1))
	local r = math.clamp(tonumber(roll) or 0, 0, 1)
	if rank ~= nil and RenownRules.IsNewPlayerRank(rank) then
		local span = D.NewPlayerEnemyMax - D.NewPlayerEnemyMin + 1
		return math.clamp(D.NewPlayerEnemyMin + math.floor(r * span), D.NewPlayerEnemyMin, D.NewPlayerEnemyMax)
	end
	local lo = multMin or D.EnemyMultMin
	local span = multSpan or D.EnemyMultSpan
	return math.max(1, math.floor(slots * (lo + r * span) + 0.5))
end

--- Highest enemy total after goal extras (Capture +1, Kill target +1 Elite leader): Ranks 1-8 = 5
--- (game_flow 42, 5:52 PM); nil = no cap (Rank 9+, dungeon rooms, test arena).
function RenownRules.NewPlayerEnemyCap(rank: number?): number?
	if rank ~= nil and RenownRules.IsNewPlayerRank(rank) then
		return D.NewPlayerEnemyMax
	end
	return nil
end

return RenownRules
