--!strict
-- DailyService.lua
-- CTRBLXAI | Real-day counter and daily limits (daily systems, USER DECISION 2026-11-01).
--
-- RULES (CTRBLXAI.db, daily systems decisions 1, 3, 4-6, 8):
--   * A day is a real UTC day starting at 00:00 UTC, read from the SERVER clock only (the
--     player's device clock is never used). If the server's day ever reads EARLIER than the saved
--     day, nothing resets (clock-rollback guard); the saved day only moves forward.
--   * Saved in save slot 2 next to the currencies: Main puts Export() inside the currencies table,
--     so a reward and the counter that limits it are always written in the same save step.
--   * Tracks today's Daily Contract (won or not) and boss rewards used today (limit 3; the boss
--     reward itself is built separately). Both reset when a new day starts.
--   * The lifetime daily-event count is NOT here: CurrencyService keeps it (dailyEventsCompleted).
--
-- OWNS: the day number and the per-day flags. MUST NOT OWN: rewards, currencies, quests.

local DailyService = {}

local SECONDS_PER_DAY = 86400
DailyService.BOSS_REWARDS_PER_DAY = 3

type State = {
	lastDay: number,       -- the last UTC day this player was processed for
	contractDone: boolean, -- today's Daily Contract has been won
	bossUsed: number,      -- boss rewards given today
}

local states: { [string]: State } = {}

local function serverNow(): number
	return DateTime.now().UnixTimestamp
end

-- Days since 1970-01-01 (UTC).
function DailyService.CurrentDay(): number
	return math.floor(serverNow() / SECONDS_PER_DAY)
end

function DailyService.SecondsUntilNewDay(): number
	return SECONDS_PER_DAY - (serverNow() % SECONDS_PER_DAY)
end

local function toNonNegInt(v: any): number
	local n = tonumber(v)
	if not n or n ~= n or n < 0 or n == math.huge then return 0 end
	return math.floor(n)
end

-- The player's state, rolled forward to today first (forwards only).
local function stateFor(playerId: string): State
	local today = DailyService.CurrentDay()
	local s = states[playerId]
	if not s then
		s = { lastDay = today, contractDone = false, bossUsed = 0 }
		states[playerId] = s
	end
	if today > s.lastDay then
		s.lastDay = today
		s.contractDone = false
		s.bossUsed = 0
		print(`[DailyService] New day {today} for {playerId}: Daily Contract and boss rewards reset`)
	end
	return s
end

--------------------------------------------------
-- DAILY CONTRACT
--------------------------------------------------

function DailyService.IsContractDone(playerId: string): boolean
	return stateFor(playerId).contractDone
end

-- Called after a won Daily Contract. `day` is the day the contract was offered for: a contract
-- taken just before 00:00 UTC and won after it does not use up the new day's contract.
function DailyService.CompleteContract(playerId: string, day: number?)
	local s = stateFor(playerId)
	if day == nil or day == s.lastDay then
		s.contractDone = true
	end
	print(`[DailyService] Daily Contract won by {playerId} (offered for day {tostring(day)}, today {s.lastDay})`)
end

--------------------------------------------------
-- BOSS REWARD LIMIT (3 per day)
--------------------------------------------------

function DailyService.BossRewardsLeft(playerId: string): number
	return math.max(0, DailyService.BOSS_REWARDS_PER_DAY - stateFor(playerId).bossUsed)
end

-- Uses one of today's boss rewards. Returns false when the limit is reached.
function DailyService.UseBossReward(playerId: string): boolean
	local s = stateFor(playerId)
	if s.bossUsed >= DailyService.BOSS_REWARDS_PER_DAY then
		return false
	end
	s.bossUsed += 1
	return true
end

--------------------------------------------------
-- SAVE (inside the currencies table, save slot 2)
--------------------------------------------------

function DailyService.Export(playerId: string): any
	local s = stateFor(playerId)
	return { d = s.lastDay, c = if s.contractDone then 1 else nil, b = s.bossUsed }
end

function DailyService.Import(playerId: string, data: any)
	local today = DailyService.CurrentDay()
	if type(data) ~= "table" then
		states[playerId] = { lastDay = today, contractDone = false, bossUsed = 0 }
		return
	end
	local savedDay = toNonNegInt(data.d)
	-- A saved day later than today means the clock went back: keep the saved day so nothing resets.
	states[playerId] = {
		lastDay = if savedDay > 0 then savedDay else today,
		contractDone = data.c == 1 or data.c == true,
		bossUsed = math.min(toNonNegInt(data.b), DailyService.BOSS_REWARDS_PER_DAY),
	}
	local s = stateFor(playerId) -- roll forward if a new day started since the save
	print(`[DailyService] Imported {playerId}: day {s.lastDay}, contract {if s.contractDone then "done" else "open"}, boss rewards used {s.bossUsed}`)
end

function DailyService.ClearPlayer(playerId: string)
	states[playerId] = nil
end

return DailyService
