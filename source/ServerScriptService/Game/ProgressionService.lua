--!strict
-- ProgressionService.lua
-- CTRBLXAI | Slice 6 — Progression (Batch 3 of 3): UNIT LEVELING / XP
--
-- OWNS (per service_boundaries 'Progression Service', LOCKED):
--   Unit XP accrual, distribution, level-up, and the unit-XP grant SINK that the
--   battle / dispatch / explore systems call. This is the system that collects a
--   battle's XP, distributes it across deployed / benched / KO'd units at the
--   locked rates, applies the overleveled penalty and the Human bonus, applies
--   the result to each unit, levels it up, and clamps at 99.
--
-- READS (per boundary):
--   unit_progression (kill XP bases, level curve, distribution rates, overleveled
--   bands, Human +10%), race growth rates (via the EXISTING RaceData path), and
--   the battle result (kills, objectives, deployed / benched / KO sets).
--
-- WRITES (per boundary):
--   Updated unit XP + level onto each unit's PERSISTENT record (the existing
--   Slice 4 roster record — the `records` sub-table that already round-trips
--   through SaveService Key 1/3). Emits level-up events for presentation. It does
--   NOT open a second store and it does NOT rewrite SaveService internals.
--
-- MUST NOT OWN (per boundary):
--   Combat damage math, reward / loot generation, Guild XP (GuildService owns
--   that — unit XP and Guild XP are kept strictly separate here), equipment stats.
--
-- PRIMARY INTERFACE (per boundary):
--   AwardBattleXp(playerId, battleResult)              -> summary
--       Collect a battle's kills + objectives, distribute across the deployed /
--       benched / KO sets at the locked rates, apply the overleveled penalty and
--       the Human bonus, apply to each unit, level up, clamp 99.
--   GrantUnitXp(playerId, unitId, xp)                  -> result
--       Direct grant for the Dispatch / Explore sinks: an already-computed XP
--       amount for a specific unit. Applies, levels up, clamps 99.
--   GetUnitLevelProgress(playerId, unitId)             -> { level, xp, xpToNext, atCap }
--       Current XP + XP-to-next for the UI.
--
-- FAILURE BOUNDARY (LOCKED):
--   XP is NEVER granted twice for the same battle/source (per-battle idempotency
--   guard keyed by battleId). Each unit's distribution rate is applied EXACTLY
--   once. Level clamps at 99 (never levels past it).
--
-- ─────────────────────────────────────────────────────────────────────────────
-- LOCKED DATA — copied verbatim from CTRBLXAI.db (unit_progression). Do NOT
-- invent or tune here. Every number below was read from the design database.
-- ─────────────────────────────────────────────────────────────────────────────
--
--   unit_progression / XP Model (Locked):
--     Kill XP = Base Type XP × (1 + Enemy Level / 50).
--     Base Type XP: Grunt = 20, Veteran = 35, Elite = 60, Boss = 120.
--     Battle XP = sum of per-kill XP for each enemy defeated, PLUS objective
--     bonuses, summed BEFORE distribution.
--   unit_progression / Level Scaling (Locked):
--     Level Gap = Unit Level − Quest Recommended Level. A single multiplier is
--     applied to ALL kill XP for that unit:
--       gap ≤  5          → ×1.00   (on-level)
--       gap  6..10        → ×0.75
--       gap 11..15        → ×0.50
--       gap 16..20        → ×0.25
--       gap 21+           → ×0.10
--       underleveled ≤ −5 → ×1.25
--       underleveled ≤−10 → ×1.50  (cap)
--     (The gold penalty row states "Same bands as XP"; the ×0.10 floor is DB-
--      confirmed. Band structure is DB-confirmed; magnitudes are the locked set.)
--   unit_progression / XP Distribution (Locked):
--     Deployed units  → 100% of battle XP.
--     Benched units   →  65% of battle XP (prevents permanent roster gaps).
--     KO'd units      → full XP IF the battle is won (they participated).
--     Human passive Adaptability → total XP (kills + objectives) × 1.10.
--   unit_progression / Level Curve (Locked):
--     XP to next level = 500 + (Level × 20).  Linear ramp.
--     Level cap = 99 at launch (hard clamp; do not level past 99).
--     Stat gain on level: base stats recalculated from race growth rates:
--       baseStat = startingStat + floor(growthRate × (level − 1)).
--     ^ This recompute ALREADY EXISTS as RaceData.CalcBaseStats(raceId, level).
--       ProgressionService CALLS it — it does not reimplement the formula.
--   unit_progression / Defeat (Locked):
--     Enemy kill XP earned during a battle is RETAINED even on wipeout / escape
--     (awarded post-battle regardless of win / loss). Objective / completion
--     bonuses are NOT granted on defeat.
--   Procedural Objective bonuses (unit_progression, Working baseline — read from
--   the battle result as a already-resolved % or flat XP; see FLAG-P4):
--     Flawless 20-30%, All-defeated 10-15%, Speed clear 15-25%, Elite spawned
--     25-40%, NPC spawned 20-30%, Siege 15-25%. These are summed into total XP
--     before distribution, on VICTORY only.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- FLAGS — structure locked, exact input NOT guaranteed present in the current
-- battle-end result as of this build. Implemented structurally and surfaced for
-- a Designer / Dev ruling. NONE of these is invented away — the code degrades
-- safely and reports what it needs.
-- ─────────────────────────────────────────────────────────────────────────────
--   FLAG-P1  QUEST RECOMMENDED LEVEL (penalty gap input). The overleveled penalty
--            needs "Quest Recommended Level". Main already has this value at
--            battle end as `activeQuest.recommendedLvl` (it is used for reward
--            item level). AwardBattleXp reads it from battleResult.recommendedLevel.
--            If the caller does NOT supply recommendedLevel, the penalty cannot be
--            computed; we treat the gap as 0 (×1.0, no penalty) and FLAG it so the
--            encounter/quest system wires recommendedLevel in. We never guess a
--            recommended level.
--   FLAG-P2  DEPLOYED / BENCHED / KO SETS. The battle loop's `allUnitsList` only
--            contains DEPLOYED player units; benched (owned-but-not-deployed)
--            units are not in the battle. AwardBattleXp expects the caller to pass
--            battleResult.deployed / .benched / .ko (arrays of unitId). Main can
--            build `deployed` + `ko` directly from allUnitsList, but `benched`
--            must be derived from (full roster − deployed). If `benched` is not
--            supplied, benched units simply receive no XP this battle and we FLAG
--            that the roster-minus-deployed set must be threaded in.
--   FLAG-P3  ENEMY XP TYPE. Base Type XP keys on Grunt/Veteran/Elite/Boss, but a
--            spawned enemy unit stores `aiRole` ("Basic"/"Elite"/"Boss") which
--            COLLAPSES Grunt and Veteran into "Basic". The original per-kill type
--            therefore cannot be recovered from aiRole alone. AwardBattleXp reads
--            each kill's type from battleResult.kills[i].enemyType when present
--            (the EnemyGenerator spec `type`), and falls back to mapping aiRole→
--            {Basic→Grunt, Elite→Elite, Boss→Boss} — which UNDER-counts a Veteran
--            as a Grunt. We FLAG that the kill record should carry the real
--            enemyType so Veterans award their locked 35 base, not 20.
--   FLAG-P4  OBJECTIVE BONUS SHAPE. unit_progression locks objective bonuses as
--            PERCENT RANGES (e.g. Flawless 20-30%). The exact roll within a range
--            and which objectives fired this battle are produced by the encounter
--            system, not here. AwardBattleXp reads already-resolved objective XP
--            from battleResult.objectiveBonusXp (a flat total) OR a list
--            battleResult.objectives = { { bonusXp = N } }. It does NOT roll the
--            percent itself (that would be inventing a number). If neither is
--            supplied, objective bonus = 0 and we FLAG it.
--
-- ─────────────────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- EXISTING stat-recompute path (Slice 4F). ProgressionService calls this on
-- level-up to recalculate base stats from race growth; it does NOT reimplement
-- the baseStat = startingStat + floor(growth × (level−1)) formula.
local RaceData = require(
	ReplicatedStorage
		:WaitForChild("Content")
		:WaitForChild("RaceData")
)

local ProgressionService = {}

--------------------------------------------------
-- LOCKED CONSTANTS (mirror of DB — see header)
--------------------------------------------------

-- Base Type XP per kill (unit_progression, Locked).
local BASE_TYPE_XP: { [string]: number } = {
	Grunt   = 20,
	Veteran = 35,
	Elite   = 60,
	Boss    = 120,
}

-- aiRole → XP type fallback (FLAG-P3). Basic collapses Grunt+Veteran; mapping to
-- Grunt UNDER-counts Veterans. Only used when the kill's real enemyType is absent.
local AIROLE_TO_TYPE: { [string]: string } = {
	Basic = "Grunt",
	Elite = "Elite",
	Boss  = "Boss",
}

-- Procedural objective bonuses as a share of the battle's base (kill) XP
-- (unit_progression ids 68 Flawless 20-30%, 69 All defeated 10-15%; "Working
-- baseline"). Slice 6 item 2 (2026-10-07): the DB gives a RANGE and no roll rule,
-- so the LOW end is used — the smallest bonus the DB allows, so XP pacing moves
-- the least until the Designer locks a value. Only objectives the battle loop
-- can evaluate today are listed; the rest (Speed clear / Elite / NPC / Siege)
-- need a locked "N turns" or Slice 5 spawn tracking and are not granted yet.
local OBJECTIVE_BONUS_PCT: { [string]: number } = table.freeze({
	Flawless    = 0.20,
	AllDefeated = 0.10,
})

local KILL_LEVEL_DIVISOR = 50          -- Kill XP = Base × (1 + Enemy Level / 50)

-- Overleveled / underleveled multiplier bands (unit_progression Level Scaling).
-- gap = Unit Level − Quest Recommended Level.
local function penaltyMultiplier(gap: number): number
	if gap <= -10 then return 1.50       -- underleveled cap
	elseif gap <= -5 then return 1.25    -- underleveled
	elseif gap <= 5 then return 1.00     -- on-level
	elseif gap <= 10 then return 0.75
	elseif gap <= 15 then return 0.50
	elseif gap <= 20 then return 0.25
	else return 0.10                     -- gap 21+
	end
end

-- Distribution rates (unit_progression XP Distribution, Locked).
local RATE_DEPLOYED = 1.00
local RATE_BENCHED  = 0.65
-- KO'd units: full XP IF battle won (handled explicitly, not a flat rate).

local HUMAN_ADAPTABILITY_MULT = 1.10   -- Human passive: total XP × 1.10
local HUMAN_RACE_ID = "RACE-HUMAN"
-- Glow Crystal map object (objects_encounters, 2026-10-07): "Double all experience
-- gained at end of battle." Applied ONCE per battle to each unit's full end-of-
-- battle total (kill + objective, deployed / KO / benched shares), on any outcome
-- (kill XP is still "gained" on a loss). Multiplies with Human x1.10 (order-free).
local GLOW_CRYSTAL_XP_MULT = 2

-- Level curve (unit_progression, Locked).
local LEVEL_CAP = 99
local function xpToNext(level: number): number
	return 500 + (level * 20)           -- XP to next level = 500 + (Level × 20)
end

--------------------------------------------------
-- INJECTED DEPENDENCIES (dependency injection — no circular require)
--
-- ProgressionService must read & write the PERSISTENT unit record (level + xp)
-- and must know a unit's raceId to recompute stats on level-up. Rather than
-- requiring PersistentStateService / the roster owner directly (which would risk
-- a require cycle and couple this service to a specific store), the orchestrator
-- (Main.server.lua) injects small accessor functions. All are nil-safe.
--------------------------------------------------

-- Returns the persistent unit RECORD table we may mutate: must expose at least
-- { level, xp, raceId }. In CTRBLXAI this is the unit's `records` sub-table
-- (which already round-trips through SaveService). The record is the single
-- source of truth for persistent level + xp — we add `xp` and `level` to it.
--   fn(playerId, unitId) -> record table | nil
local _unitRecordProvider: ((string, string) -> any)? = nil

-- Optional: notify the roster/persistence owner that a unit's level changed, so
-- it can refresh max HP/MP and persistent resources via the EXISTING path
-- (PersistentStateService.UpdateMaxResources). Nil-safe.
--   fn(playerId, unitId, newLevel, newBaseStats)
local _onLevelUp: ((string, string, number, any) -> ())? = nil

-- Optional: fire a presentation event for a level-up (BattleEvents / HUD toast).
--   fn(playerId, unitId, newLevel)
local _levelUpEvent: ((string, string, number) -> ())? = nil

function ProgressionService.SetUnitRecordProvider(fn: ((string, string) -> any)?)
	_unitRecordProvider = fn
end
function ProgressionService.SetOnLevelUp(fn: ((string, string, number, any) -> ())?)
	_onLevelUp = fn
end
function ProgressionService.SetLevelUpEvent(fn: ((string, string, number) -> ())?)
	_levelUpEvent = fn
end

--------------------------------------------------
-- IDEMPOTENCY GUARD (Failure boundary: never grant twice for the same source)
--   awardedBattles[playerId][battleId] = true  once a battle's XP has been
--   awarded. A repeat AwardBattleXp with the same battleId is a no-op.
--------------------------------------------------

local awardedBattles: { [string]: { [string]: boolean } } = {}

local function alreadyAwarded(playerId: string, battleId: string): boolean
	local set = awardedBattles[playerId]
	return set ~= nil and set[battleId] == true
end

local function markAwarded(playerId: string, battleId: string)
	if not awardedBattles[playerId] then awardedBattles[playerId] = {} end
	awardedBattles[playerId][battleId] = true
end

--------------------------------------------------
-- CORE: apply raw XP to one unit's persistent record, leveling up and clamping
-- at 99. Returns (newLevel, newXp, levelsGained). Internal — all public grant
-- paths funnel through here so the curve + cap + stat-recompute live in ONE place.
--------------------------------------------------

local function applyXpToUnit(playerId: string, unitId: string, rawXp: number): (number, number, number)
	local xp = math.max(0, math.floor(rawXp or 0))

	local record = _unitRecordProvider and _unitRecordProvider(playerId, unitId) or nil
	if type(record) ~= "table" then
		-- No persistent record reachable — report but do not invent a store.
		warn(string.format(
			"[ProgressionService] No unit record for %s/%s — %d XP not persisted (record provider missing; FLAG)",
			playerId, tostring(unitId), xp))
		return 1, xp, 0
	end

	-- Seed defaults the first time XP/level are touched on this record.
	record.level = math.clamp(math.floor(tonumber(record.level) or 1), 1, LEVEL_CAP)
	record.xp = math.max(0, math.floor(tonumber(record.xp) or 0))

	-- Already at cap: XP is not accrued past the cap (no overflow banking).
	if record.level >= LEVEL_CAP then
		record.level = LEVEL_CAP
		return LEVEL_CAP, record.xp, 0
	end

	record.xp += xp

	-- Level up along the linear curve, clamping hard at 99.
	local levelsGained = 0
	while record.level < LEVEL_CAP do
		local need = xpToNext(record.level)
		if record.xp < need then break end
		record.xp -= need
		record.level += 1
		levelsGained += 1
	end

	-- At cap: stop accruing overflow XP (hold at 0 toward "next").
	if record.level >= LEVEL_CAP then
		record.level = LEVEL_CAP
		record.xp = 0
	end

	-- On level-up, recompute base stats from race growth via the EXISTING path
	-- (RaceData.CalcBaseStats) and notify the roster owner so max HP/MP refresh
	-- through the EXISTING PersistentStateService path. We do NOT reimplement the
	-- stat formula and we do NOT touch max HP/MP ourselves.
	if levelsGained > 0 then
		local raceId = record.raceId
		local newBaseStats = nil
		if raceId and RaceData.CalcBaseStats then
			local ok, stats = pcall(RaceData.CalcBaseStats, raceId, record.level)
			if ok then newBaseStats = stats end
		end
		if _onLevelUp then
			_onLevelUp(playerId, unitId, record.level, newBaseStats)
		end
		if _levelUpEvent then
			_levelUpEvent(playerId, unitId, record.level)
		end
		print(string.format(
			"[ProgressionService] %s/%s leveled up +%d -> L%d (xp %d/%d toward next)%s",
			playerId, tostring(unitId), levelsGained, record.level, record.xp,
			record.level < LEVEL_CAP and xpToNext(record.level) or 0,
			(raceId and newBaseStats) and "" or " [stat recompute skipped: no raceId/path — FLAG]"))
	end

	return record.level, record.xp, levelsGained
end

--------------------------------------------------
-- PRIMARY INTERFACE: GrantUnitXp
--
-- Direct grant used by the Dispatch / Explore sinks (and any caller that has an
-- already-computed XP amount for a specific unit). Applies the XP, levels up,
-- clamps at 99. No penalty/distribution is applied here — the amount is taken
-- as final (Dispatch/Explore already computed it under their own locked rules).
--
-- Returns: { unitId, xpGranted, level, xp, levelsGained, atCap }
--------------------------------------------------

function ProgressionService.GrantUnitXp(playerId: string, unitId: string, xp: number)
	assert(type(playerId) == "string", "ProgressionService.GrantUnitXp: playerId required")
	assert(type(unitId) == "string", "ProgressionService.GrantUnitXp: unitId required")

	local amount = math.max(0, math.floor(tonumber(xp) or 0))
	local level, newXp, gained = applyXpToUnit(playerId, unitId, amount)

	print(string.format("[ProgressionService] GrantUnitXp %s/%s +%d XP -> L%d",
		playerId, unitId, amount, level))

	return {
		unitId = unitId,
		xpGranted = amount,
		level = level,
		xp = newXp,
		levelsGained = gained,
		atCap = level >= LEVEL_CAP,
	}
end

--------------------------------------------------
-- HELPERS for AwardBattleXp
--------------------------------------------------

-- Resolve one kill's base XP type (FLAG-P3).
local function killBaseType(kill: any): string
	if type(kill) == "table" then
		local t = kill.enemyType or kill.type
		if type(t) == "string" and BASE_TYPE_XP[t] then
			return t
		end
		local role = kill.aiRole
		if type(role) == "string" and AIROLE_TO_TYPE[role] then
			return AIROLE_TO_TYPE[role]   -- fallback (under-counts Veteran as Grunt)
		end
	end
	return "Grunt"   -- safest minimum; flagged
end

-- Sum raw battle kill XP from the kills list: Σ BaseTypeXP × (1 + level/50).
local function sumKillXp(kills: { any }): (number, { string })
	local total = 0
	local flags = {}
	for _, kill in ipairs(kills) do
		local t = killBaseType(kill)
		local base = BASE_TYPE_XP[t] or BASE_TYPE_XP.Grunt
		local lvl = 0
		if type(kill) == "table" then lvl = math.max(0, math.floor(tonumber(kill.level) or 0)) end
		total += base * (1 + lvl / KILL_LEVEL_DIVISOR)
		-- Note a fallback where enemyType was missing (FLAG-P3 surfacing).
		if type(kill) == "table" and not (kill.enemyType or kill.type) then
			table.insert(flags, "kill-missing-enemyType")
		end
	end
	return total, flags
end

-- Sum already-resolved objective bonus XP (FLAG-P4). Accepts a flat total or a
-- list of { bonusXp }. Does NOT roll percentages (that would invent a number).
-- Slice 6 item 2: also accepts battleResult.objectivesMet = { "Flawless", ... },
-- each paying OBJECTIVE_BONUS_PCT[id] x the battle's raw (pre-penalty) kill XP.
local function sumObjectiveXp(battleResult: any, rawKillXp: number): number
	if type(battleResult) ~= "table" then return 0 end
	local total = 0
	if type(battleResult.objectivesMet) == "table" then
		for _, objId in ipairs(battleResult.objectivesMet) do
			local pct = OBJECTIVE_BONUS_PCT[objId]
			if pct then
				total += math.floor((rawKillXp or 0) * pct + 0.0001)
			end
		end
	end
	if type(battleResult.objectiveBonusXp) == "number" then
		return total + math.max(0, math.floor(battleResult.objectiveBonusXp))
	end
	if type(battleResult.objectives) == "table" then
		for _, o in ipairs(battleResult.objectives) do
			if type(o) == "table" and type(o.bonusXp) == "number" then
				total += math.max(0, math.floor(o.bonusXp))
			end
		end
	end
	return total
end

-- Is this unit a Human (for the ×1.10 Adaptability bonus)?
local function isHuman(playerId: string, unitId: string): boolean
	local record = _unitRecordProvider and _unitRecordProvider(playerId, unitId) or nil
	return type(record) == "table" and record.raceId == HUMAN_RACE_ID
end

-- Current persistent level of a unit (for the penalty gap).
local function unitLevel(playerId: string, unitId: string): number
	local record = _unitRecordProvider and _unitRecordProvider(playerId, unitId) or nil
	if type(record) == "table" then
		return math.clamp(math.floor(tonumber(record.level) or 1), 1, LEVEL_CAP)
	end
	return 1
end

--------------------------------------------------
-- PRIMARY INTERFACE: GrantExpeditionUnitXp
--
-- Expedition-only per-unit grant. Explore expeditions treat every unit the
-- player SENT as a full participant (100%) in each battle of the trip; a Human
-- unit additionally gets the locked Adaptability x1.10 (unit_progression Human
-- passive). This is the ONLY expedition XP path: it applies the Human bonus
-- exactly once, here, and never routes through AwardBattleXp (normal battles)
-- or the plain GrantUnitXp (Dispatch), so neither is affected.
--
-- Idempotency: keyed by (battleId + unitId) so a rejoin replaying the same
-- expedition battle never pays the same unit twice.
--------------------------------------------------
local expeditionGranted: { [string]: { [string]: boolean } } = {}

function ProgressionService.GrantExpeditionUnitXp(playerId: string, unitId: string, killXp: number, battleId: string?)
	assert(type(playerId) == "string", "ProgressionService.GrantExpeditionUnitXp: playerId required")
	assert(type(unitId) == "string", "ProgressionService.GrantExpeditionUnitXp: unitId required")

	-- Per (battle, unit) idempotency so a replayed expedition battle never double-pays.
	local bid = tostring(battleId or "")
	if bid ~= "" then
		local key = bid .. "|" .. unitId
		expeditionGranted[playerId] = expeditionGranted[playerId] or {}
		if expeditionGranted[playerId][key] then
			return {
				unitId = unitId, xpGranted = 0, levelsGained = 0, alreadyGranted = true,
			}
		end
		expeditionGranted[playerId][key] = true
	end

	-- Full participation: 100% of the battle's kill XP; Human x1.10 (locked).
	local base = math.max(0, math.floor(tonumber(killXp) or 0))
	local amount = base
	local human = isHuman(playerId, unitId)
	if human then
		amount = math.floor(base * HUMAN_ADAPTABILITY_MULT)
	end

	local level, newXp, gained = applyXpToUnit(playerId, unitId, amount)

	print(string.format("[ProgressionService] GrantExpeditionUnitXp %s/%s +%d XP%s -> L%d",
		playerId, unitId, amount, human and " (Human x1.10)" or "", level))

	return {
		unitId = unitId,
		xpGranted = amount,
		level = level,
		xp = newXp,
		levelsGained = gained,
		humanBonus = human,
		atCap = level >= LEVEL_CAP,
	}
end


--------------------------------------------------
-- PRIMARY INTERFACE: AwardBattleXp
--
-- Collects a battle's kills + objectives, distributes across the deployed /
-- benched / KO sets at the LOCKED rates, applies the overleveled penalty (per
-- unit, from its own level vs the quest recommended level) and the Human bonus,
-- applies the result to each unit, levels up, clamps at 99.
--
-- battleResult (produced by Main at battle end):
--   {
--     battleId        = string,              -- REQUIRED for idempotency
--     won             = boolean,             -- true on player victory
--     recommendedLevel= number?,             -- Quest Recommended Level (FLAG-P1)
--     kills           = { { enemyType=string?, aiRole=string?, level=number } },
--     preSummedKillXp = number?,              -- EXPEDITION path: use this
--                        pre-summed battle kill XP DIRECTLY instead of kills[]
--                        (ExploreService supplies it; never invented here)
--     objectiveBonusXp= number?,  OR  objectives = { { bonusXp=number } }, -- (FLAG-P4)
--     deployed        = { string },          -- deployed player unitIds (FLAG-P2)
--     benched         = { string }?,         -- benched owned unitIds   (FLAG-P2)
--     ko              = { string }?,         -- KO'd player unitIds this battle
--   }
--
-- Distribution semantics (LOCKED):
--   base battle XP = Σ kill XP + objective bonus XP (objectives only on a win).
--   Deployed survivor      → 100% of base, then × penalty(gap) [kills] + objective
--   KO'd (won)             → full XP (same 100% as deployed)   — participated
--   KO'd (lost)            → kill XP retained (objectives NOT granted on defeat)
--   Benched                → 65% of base
--   Human (any of the above) → final per-unit total × 1.10
--
-- Note: the overleveled penalty is defined as applying to KILL XP. Objective
-- bonus XP is a completion reward and is distributed but not penalty-scaled.
-- On DEFEAT: kill XP is retained for every participating (deployed/KO) unit;
-- objective + completion bonuses are NOT granted; benched units get kill XP at
-- 65% as well (they "participated" in the roster sense; this matches the locked
-- "kill XP retained regardless of outcome" rule). No idempotent double-grant.
--
-- Returns a summary table (per-unit granted XP + resulting level), plus flags.
--------------------------------------------------

function ProgressionService.AwardBattleXp(playerId: string, battleResult: any)
	assert(type(playerId) == "string", "ProgressionService.AwardBattleXp: playerId required")
	assert(type(battleResult) == "table", "ProgressionService.AwardBattleXp: battleResult table required")

	local battleId = tostring(battleResult.battleId or "")
	if battleId == "" then
		warn("[ProgressionService] AwardBattleXp called without battleId — refusing (cannot guarantee single-grant). FLAG")
		return { ok = false, reason = "missing battleId", flags = { "missing-battleId" } }
	end

	-- FAILURE BOUNDARY: never grant twice for the same battle.
	if alreadyAwarded(playerId, battleId) then
		warn(string.format("[ProgressionService] Battle %s already awarded for %s — no-op (idempotency guard)", battleId, playerId))
		return { ok = false, reason = "already awarded", battleId = battleId }
	end

	local won = battleResult.won == true
	local flags: { string } = {}

	-- Kill XP (retained on ANY outcome, LOCKED).
	-- Normal battle path: sum per-kill XP from the kills[] list.
	-- Expedition path (ExploreService): the series already accumulated this
	-- battle's kill XP into a single pre-summed total (loot_progression:
	-- "each battle awards XP separately; total = sum"). When battleResult
	-- carries a numeric preSummedKillXp we use it DIRECTLY as the base kill XP
	-- (no kills[] list to re-sum, and we do NOT invent one). The locked
	-- distribution rate, overleveled penalty, Human ×1.10 and level-up still
	-- apply below exactly as for a normal battle.
	local rawKillXp = 0
	if type(battleResult.preSummedKillXp) == "number" then
		rawKillXp = math.max(0, math.floor(battleResult.preSummedKillXp))
	else
		local kills = type(battleResult.kills) == "table" and battleResult.kills or {}
		local killFlags
		rawKillXp, killFlags = sumKillXp(kills)
		for _, f in ipairs(killFlags) do flags[#flags + 1] = f end
		if #killFlags > 0 then
			flags[#flags + 1] = "FLAG-P3:some kills missing enemyType (Veterans under-counted as Grunts)"
		end
	end

	-- Glow Crystal (battleResult.glowCrystal = true when a player unit activated
	-- one this battle). Boolean, so two crystals still mean x2, never x4.
	local battleXpMult = (battleResult.glowCrystal == true) and GLOW_CRYSTAL_XP_MULT or 1
	if battleXpMult ~= 1 then flags[#flags + 1] = "INFO:Glow Crystal active — battle XP x2" end

	-- Objective / completion bonus XP — VICTORY ONLY (not granted on defeat).
	local objectiveXp = won and sumObjectiveXp(battleResult, rawKillXp) or 0
	if won and objectiveXp == 0 and battleResult.objectiveBonusXp == nil
		and battleResult.objectives == nil and battleResult.objectivesMet == nil then
		flags[#flags + 1] = "FLAG-P4:no objective XP supplied (objectiveBonusXp/objectives absent)"
	end

	-- Quest Recommended Level for the penalty gap (FLAG-P1).
	local recommendedLevel = tonumber(battleResult.recommendedLevel)
	if recommendedLevel == nil then
		flags[#flags + 1] = "FLAG-P1:recommendedLevel absent — overleveled penalty treated as x1.0"
	end

	-- Unit sets (FLAG-P2).
	local deployed = type(battleResult.deployed) == "table" and battleResult.deployed or {}
	local benched = type(battleResult.benched) == "table" and battleResult.benched or nil
	local koList = type(battleResult.ko) == "table" and battleResult.ko or {}
	if benched == nil then
		flags[#flags + 1] = "FLAG-P2:benched set absent — benched units received no XP this battle"
	end

	-- Build a KO set for quick lookup; KO'd deployed units get FULL XP on a win.
	local koSet: { [string]: boolean } = {}
	for _, uid in ipairs(koList) do koSet[tostring(uid)] = true end

	-- Per-unit grant helper. `rate` is the deployed/benched base rate; kill XP is
	-- additionally penalty-scaled per the unit's own level gap; objective XP is
	-- distributed at the same base rate but not penalty-scaled; Human ×1.10 last.
	local perUnit: { [string]: any } = {}

	local function grantSet(unitIds: { string }, rate: number, participates: boolean)
		for _, raw in ipairs(unitIds) do
			local unitId = tostring(raw)
			if perUnit[unitId] == nil then  -- apply each unit's rate EXACTLY once
				-- Penalty from this unit's level vs the recommended level.
				local mult = 1.0
				if recommendedLevel ~= nil then
					local gap = unitLevel(playerId, unitId) - math.floor(recommendedLevel)
					mult = penaltyMultiplier(gap)
				end

				-- Kill XP: distributed at rate, penalty-scaled. Retained on any outcome.
				local killPart = rawKillXp * rate * mult
				-- Objective XP: victory only, distributed at rate, NOT penalty-scaled.
				local objPart = (won and participates) and (objectiveXp * rate) or 0

				local subtotal = killPart + objPart

				-- Human Adaptability: total (kills + objectives) × 1.10 (LOCKED).
				if isHuman(playerId, unitId) then
					subtotal *= HUMAN_ADAPTABILITY_MULT
				end

				-- Glow Crystal: x2 on the unit's full end-of-battle total.
				subtotal *= battleXpMult

				local granted = math.floor(subtotal + 0.0001)
				local level, newXp, gained = applyXpToUnit(playerId, unitId, granted)
				perUnit[unitId] = {
					xpGranted = granted,
					level = level,
					xp = newXp,
					levelsGained = gained,
					atCap = level >= LEVEL_CAP,
					rate = rate,
					penaltyMult = mult,
				}
			end
		end
	end

	-- Deployed units: 100%. KO'd deployed units on a WIN still get the full 100%
	-- (they participated). On a LOSS, deployed (incl. KO'd) retain kill XP only.
	grantSet(deployed, RATE_DEPLOYED, true)

	-- KO'd units that may not have been in `deployed` (defensive): ensure they
	-- are granted exactly once at the deployed rate (full XP on win).
	grantSet(koList, RATE_DEPLOYED, true)

	-- Benched units: 65% (if supplied). They participate for kill XP retention;
	-- objective bonuses only matter on a win and are distributed at 65% too.
	if benched then
		grantSet(benched, RATE_BENCHED, true)
	end

	markAwarded(playerId, battleId)

	-- Summary.
	local unitCount = 0
	for _ in pairs(perUnit) do unitCount += 1 end
	print(string.format(
		"[ProgressionService] AwardBattleXp %s | battle %s | won=%s | rawKillXp=%.1f objXp=%d | %d unit(s)%s",
		playerId, battleId, tostring(won), rawKillXp, objectiveXp, unitCount,
		(#flags > 0) and (" | FLAGS: " .. table.concat(flags, "; ")) or ""))

	return {
		ok = true,
		battleId = battleId,
		won = won,
		rawKillXp = math.floor(rawKillXp + 0.0001),
		objectiveXp = objectiveXp,
		recommendedLevel = recommendedLevel,
		units = perUnit,
		flags = flags,
	}
end

--------------------------------------------------
-- PRIMARY INTERFACE: GetUnitLevelProgress
--
-- Current XP + XP-to-next for the UI. Reads the persistent record (nil-safe).
-- Returns: { level, xp, xpToNext, atCap }
--------------------------------------------------

function ProgressionService.GetUnitLevelProgress(playerId: string, unitId: string)
	local record = _unitRecordProvider and _unitRecordProvider(playerId, unitId) or nil
	local level = 1
	local xp = 0
	if type(record) == "table" then
		level = math.clamp(math.floor(tonumber(record.level) or 1), 1, LEVEL_CAP)
		xp = math.max(0, math.floor(tonumber(record.xp) or 0))
	end
	local atCap = level >= LEVEL_CAP
	return {
		level = level,
		xp = xp,
		xpToNext = atCap and 0 or xpToNext(level),
		atCap = atCap,
	}
end

--------------------------------------------------
-- LIFECYCLE
--   ClearPlayer wipes the per-player idempotency guard (e.g. on leave). The
--   persistent level/xp live on the unit RECORD (SaveService), not here, so
--   nothing of value is lost — this only clears the "already awarded" memory.
--------------------------------------------------

function ProgressionService.ClearPlayer(playerId: string)
	awardedBattles[playerId] = nil
end

-- Expose the locked curve for any UI that wants to show it (read-only helper).
function ProgressionService.XpToNext(level: number): number
	return xpToNext(math.clamp(math.floor(level or 1), 1, LEVEL_CAP))
end

ProgressionService.LEVEL_CAP = LEVEL_CAP

return ProgressionService
