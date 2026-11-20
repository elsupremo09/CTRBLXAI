--!strict
-- RenownService.lua
-- CTRBLXAI | Renown Service (service_boundaries "Renown Service"; replaces GuildService).
--
-- OWNS: the account's Renown Rank and the Renown inside that Rank. One account progression
-- (loot_progression 75). Server is the source of truth (ARC-001); nothing here is client-set.
-- READS: RenownRules (every number and formula). No other dependency; does not require
-- GuildService.
-- WRITES: in-memory state only. Persistence goes through Export / Import into the existing
-- progression save (no new DataStore).
--
-- Rules (CTRBLXAI.db, USER RULING 2026-11-12):
--   - Earned from successful quests only (loot_progression 74). Callers classify the quest
--     with RenownRules.QuestKind; a nil kind (Test Arena) changes nothing.
--   - A failed quest costs 3x the quest's base reward up to Rank 50, 1x from Rank 51
--     (loot_progression 90 / unit_progression 94; 2026-11-18 4:48 PM).
--     It never drops a Rank: the loss stops at the start of the current Rank, and the amount
--     actually lost is reported (0 if the floor absorbs it all).
--   - No Rank cap (loot_progression 83/89). One award can give several Rank-ups.
--   - Old saves convert once (loot_progression 93): Rank = highest unit level - 2 (min 1),
--     Renown inside the Rank = 0, old Guild XP dropped, recorded so it never runs again.
--
-- STEP 1 of PLAN_renown_build_20261112.md; step 2 (2026-11-12) wires the save + conversion.

local RenownRules = require(script.Parent.RenownRules)

local RenownService = {}

type State = { rank: number, renown: number, converted: boolean }

local state: { [string]: State } = {}

local function toInt(n: any, fallback: number): number
	local v = tonumber(n)
	if v == nil or v ~= v then return fallback end
	return math.floor(v)
end

local function stateOf(playerId: string): State
	local s = state[playerId]
	if not s then
		s = { rank = RenownRules.Data.StartRank, renown = 0, converted = false }
		state[playerId] = s
	end
	return s
end

function RenownService.InitPlayer(playerId: string)
	assert(type(playerId) == "string", "[RenownService] InitPlayer: playerId required")
	stateOf(playerId)
end

function RenownService.GetRank(playerId: string): number
	return stateOf(playerId).rank
end

--- Renown inside the current Rank, and the Renown needed for the next Rank.
function RenownService.GetProgress(playerId: string): (number, number)
	local s = stateOf(playerId)
	return s.renown, RenownRules.RenownToNext(s.rank)
end

--- What a successful quest of this kind and level would pay now (for the quest card preview).
function RenownService.PreviewQuestRenown(playerId: string, kind: string?, questLevel: number): number
	return RenownRules.QuestReward(kind, stateOf(playerId).rank, questLevel)
end

function RenownService.GetRosterCapacity(playerId: string): number
	return RenownRules.RosterCapacity(stateOf(playerId).rank)
end

function RenownService.GetBlacksmithRankCap(playerId: string): number
	return RenownRules.BlacksmithRankCap(stateOf(playerId).rank)
end

function RenownService.GetRecruitWindow(playerId: string): (number, number)
	return RenownRules.RecruitWindow(stateOf(playerId).rank)
end

export type AwardResult = {
	kind: string?,
	success: boolean,
	nominal: number,     -- reward after band (success) or 3x base penalty (fail)
	delta: number,       -- signed Renown actually gained / lost
	rankBefore: number,
	rankAfter: number,
	rankUps: { number }, -- every Rank reached by this award, in order
	renown: number,      -- Renown inside the Rank after the award
	need: number,        -- Renown needed for the next Rank after the award
}

--- Apply one quest result. result = { success = boolean, kind = string?, questLevel = number? }.
--- Unknown or nil kind (e.g. Test Arena) changes nothing and returns delta 0.
function RenownService.Award(playerId: string, result: any): AwardResult
	assert(type(playerId) == "string", "[RenownService] Award: playerId required")
	local s = stateOf(playerId)
	local rankBefore = s.rank
	local success = type(result) == "table" and result.success == true
	local kind = if type(result) == "table" and type(result.kind) == "string" then result.kind else nil
	local out: AwardResult = {
		kind = kind, success = success, nominal = 0, delta = 0,
		rankBefore = rankBefore, rankAfter = rankBefore, rankUps = {},
		renown = s.renown, need = RenownRules.RenownToNext(s.rank),
	}
	if RenownRules.BaseReward(kind) <= 0 then
		return out
	end

	if success then
		local questLevel = if type(result) == "table" then toInt(result.questLevel, s.rank) else s.rank
		local gain = RenownRules.QuestReward(kind, s.rank, questLevel)
		out.nominal = gain
		out.delta = gain
		s.renown += gain
		-- No Rank cap: keep ranking up while the Renown covers the next step.
		local need = RenownRules.RenownToNext(s.rank)
		while s.renown >= need do
			s.renown -= need
			s.rank += 1
			table.insert(out.rankUps, s.rank)
			need = RenownRules.RenownToNext(s.rank)
		end
	else
		local penalty = RenownRules.FailPenalty(kind, s.rank)
		local lost = math.min(penalty, s.renown) -- floor: never below the start of the Rank
		out.nominal = penalty
		out.delta = if lost > 0 then -lost else 0 -- plain 0 (not -0) when the floor absorbs it all
		s.renown -= lost
	end

	out.rankAfter = s.rank
	out.renown = s.renown
	out.need = RenownRules.RenownToNext(s.rank)
	print(string.format("[RenownService] %s | %s %s | %+d Renown (nominal %d) | Rank %d -> %d | %d / %d",
		playerId, tostring(kind), if success then "success" else "fail", out.delta, out.nominal,
		rankBefore, s.rank, s.renown, out.need))
	return out
end

--- Save shape: { rank, renown, converted, curveVersion }. Old Guild XP is not saved (loot_progression 93).
--- curveVersion 2 = the "Three stages" curve (2026-11-18); a save without it was written on curve 1.
function RenownService.Export(playerId: string)
	local s = stateOf(playerId)
	return { rank = s.rank, renown = s.renown, converted = s.converted, curveVersion = RenownRules.Data.CurveVersion }
end

--- Load saved Renown. `data` is the saved renown table (nil for a save from before Renown).
--- Conversion of old saves is done separately by ConvertOldSave once the roster has loaded.
function RenownService.Import(playerId: string, data: any)
	assert(type(playerId) == "string", "[RenownService] Import: playerId required")
	local s = { rank = RenownRules.Data.StartRank, renown = 0, converted = false }
	state[playerId] = s
	if type(data) ~= "table" then return end
	s.rank = math.max(RenownRules.Data.StartRank, toInt(data.rank, RenownRules.Data.StartRank))
	-- Excess saved Renown is never thrown away: apply any Rank-ups it covers (no Rank cap).
	s.renown = math.max(0, toInt(data.renown, 0))
	-- One-time curve rescale (loot_progression 93 note, 2026-11-18): a save written on the old curve
	-- (no curveVersion) keeps its Rank and the same FRACTION of the Rank's bar, rounded down
	-- (Rank 42 0/460 -> 0/730; Rank 60 300/550 -> 790/1450). Rank-ups covered by excess Renown are
	-- applied on the OLD curve first. Export writes curveVersion 2, so this never runs twice.
	if (toInt(data.curveVersion, 1)) < RenownRules.Data.CurveVersion then
		local oldNeed = RenownRules.RenownToNextV1(s.rank)
		while s.renown >= oldNeed do
			s.renown -= oldNeed
			s.rank += 1
			oldNeed = RenownRules.RenownToNextV1(s.rank)
		end
		local before = s.renown
		local newNeed = RenownRules.RenownToNext(s.rank)
		s.renown = math.clamp(math.floor(before * newNeed / oldNeed), 0, newNeed - 1)
		print(string.format("[RenownService] %s | curve rescale v1 -> v2 at Rank %d: %d/%d -> %d/%d",
			playerId, s.rank, before, oldNeed, s.renown, newNeed))
	end
	local need = RenownRules.RenownToNext(s.rank)
	while s.renown >= need do
		s.renown -= need
		s.rank += 1
		need = RenownRules.RenownToNext(s.rank)
	end
	-- A save written by Export always carries the flag; an older Renown save with a Rank but no
	-- flag counts as converted. An explicit false (saved before conversion could run) stays false.
	s.converted = data.converted == true or (data.converted == nil and data.rank ~= nil)
end

--- Brand-new player (USER RULING 2026-11-12 9:23 PM): starts at Rank 1 with 0 Renown and is
--- marked converted, so the old-save conversion (highest unit - 2) never runs for them. Does
--- nothing for a player that is already converted, so it can never lower or reset a Rank.
function RenownService.StartFresh(playerId: string)
	assert(type(playerId) == "string", "[RenownService] StartFresh: playerId required")
	local s = stateOf(playerId)
	if s.converted then return end
	s.rank = math.max(s.rank, RenownRules.Data.StartRank)
	s.converted = true
	print(string.format("[RenownService] %s | new player starts at Rank %d", playerId, s.rank))
end

--- One-time conversion for a save that has no Renown yet (loot_progression 93).
--- Returns true if it converted now, false if this save was already converted.
function RenownService.ConvertOldSave(playerId: string, highestUnitLevel: number?): boolean
	local s = stateOf(playerId)
	if s.converted then return false end
	if highestUnitLevel == nil then
		-- Roster not loaded yet: don't record a Rank-1 conversion; the caller retries later.
		warn("[RenownService] ConvertOldSave: no highest unit level yet; conversion skipped (will retry)")
		return false
	end
	-- Never lower a Rank (loot_progression 90): if anything ran before conversion, keep the higher.
	local target = RenownRules.ConvertedRank(highestUnitLevel)
	if target > s.rank then
		s.rank = target
		s.renown = 0
	end
	s.converted = true
	print(string.format("[RenownService] %s | old save converted to Rank %d (highest unit %s)",
		playerId, s.rank, tostring(highestUnitLevel)))
	return true
end

--- Highest owned unit level, injected by Main (no roster dependency here). Step 2, 2026-11-12.
local highestUnitLevelProvider: ((string) -> number?)? = nil
function RenownService.SetHighestUnitLevelProvider(fn: (string) -> number?)
	highestUnitLevelProvider = fn
end

--- Run the one-time conversion if it has not happened yet (safe to call any number of times).
--- Returns true only on the call that converted. Skips quietly if no provider / no roster yet.
function RenownService.EnsureConverted(playerId: string): boolean
	if stateOf(playerId).converted or highestUnitLevelProvider == nil then return false end
	return RenownService.ConvertOldSave(playerId, highestUnitLevelProvider(playerId))
end

function RenownService.IsConverted(playerId: string): boolean
	return stateOf(playerId).converted
end

function RenownService.ClearPlayer(playerId: string)
	state[playerId] = nil
end

return RenownService
