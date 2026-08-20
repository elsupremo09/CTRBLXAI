-- BattleCoordinator.lua
-- CTRBLXAI | Slice 1
--
-- Owns the battle lifecycle: the CT clock, which unit acts next,
-- opening and closing turns, and deciding when the battle is over.
--
-- Slice 1 scope:
--   - Advance CT until the lowest-RT unit hits 0 RT.
--   - Resolve ties by: Level > AGI > HP% (lower first) > LUK > stableOrderKey.
--   - Open a turn (give the unit its AP).
--   - Close a turn (apply RT cost, check for battle end).
--   - Declare victory / defeat.
--
-- Does NOT own: skill formulas, damage, targeting, or AI logic.

local UnitSchema = require(script.Parent.UnitSchema)
local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

local BattleCoordinator = {}

--------------------------------------------------
-- CONSTANTS  (from GameConstants shared module)
--------------------------------------------------

local BASE_RT_STANDARD     = GameConstants.BASE_RT_STANDARD
local AP_PER_TURN_STANDARD = GameConstants.AP_PER_TURN_STANDARD
local REST_RT_MULTIPLIER   = GameConstants.REST_RT_MULTIPLIER

--------------------------------------------------
-- BATTLE STATE
--------------------------------------------------

-- Creates a fresh BattleState for a new battle.
-- units = list of unit tables created via UnitSchema.Create().
function BattleCoordinator.CreateBattleState(units)
	assert(
		type(units) == "table" and #units >= 2,
		"CreateBattleState: need at least 2 units."
	)

	-- Assign a stable tie-break order based on insertion order.
	for index, unit in ipairs(units) do
		unit.stableOrderKey = index
	end

	local state = {
		-- All units in the battle (alive and defeated).
		units = units,

		-- The unit whose turn is currently open, or nil.
		activeUnit = nil,

		-- RT costs queued up during the current turn.
		-- BattleCoordinator adds to this when actions are committed.
		turnRtAccrued = 0,

		-- Whether any action was taken this turn.
		turnActionTaken = false,

		-- Global CT clock. Informational only for Slice 1.
		ct = 0,

		-- "Waiting" (no one is acting) | "TurnOpen" | "BattleOver"
		phase = "Waiting",

		-- Winner: "Player" | "Enemy" | nil
		winner = nil,

		-- How many full turns have completed (for debugging).
		turnCount = 0,
	}

	return state
end

--------------------------------------------------
-- INTERNAL: ALIVE UNIT LISTS
--------------------------------------------------

local function getAliveUnits(state)
	local alive = {}
	for _, unit in ipairs(state.units) do
		if unit.isAlive then
			table.insert(alive, unit)
		end
	end
	return alive
end

local function getSideAlive(state, side)
	local count = 0
	for _, unit in ipairs(state.units) do
		if unit.isAlive and unit.side == side then
			count = count + 1
		end
	end
	return count
end

--------------------------------------------------
-- INTERNAL: NEXT READY UNIT
--   Advances CT until at least one unit reaches RT 0.
--   Returns the unit that should act next.
--------------------------------------------------

local function resolveReadyTie(a, b)
	-- Rule: Higher Level wins (acts first).
	local aLevel = a.level or 1
	local bLevel = b.level or 1
	if aLevel ~= bLevel then
		return aLevel > bLevel
	end

	-- Rule: Higher AGI wins.
	local aAgi = a.effectiveStats and a.effectiveStats.AGI or 10
	local bAgi = b.effectiveStats and b.effectiveStats.AGI or 10
	if aAgi ~= bAgi then
		return aAgi > bAgi
	end

	-- Rule: Lower HP% wins (more desperate = acts first).
	local aHpPct = a.currentHp / a.maxHp
	local bHpPct = b.currentHp / b.maxHp
	if aHpPct ~= bHpPct then
		return aHpPct < bHpPct
	end

	-- Rule: Higher LUK wins.
	local aLuk = a.effectiveStats and a.effectiveStats.LUK or 10
	local bLuk = b.effectiveStats and b.effectiveStats.LUK or 10
	if aLuk ~= bLuk then
		return aLuk > bLuk
	end

	-- Final tie-break: lower stableOrderKey acts first.
	return a.stableOrderKey < b.stableOrderKey
end

local function advanceToNextReady(state)
	local alive = getAliveUnits(state)
	if #alive == 0 then return nil end

	-- Find the minimum RT among alive units.
	local minRt = math.huge
	for _, unit in ipairs(alive) do
		if unit.remainingRt < minRt then
			minRt = unit.remainingRt
		end
	end

	-- Advance CT by that amount and subtract from all alive units.
	state.ct = state.ct + minRt
	for _, unit in ipairs(alive) do
		unit.remainingRt = unit.remainingRt - minRt
	end

	-- Collect all units now at RT 0.
	local ready = {}
	for _, unit in ipairs(alive) do
		if unit.remainingRt <= 0 then
			table.insert(ready, unit)
		end
	end

	if #ready == 0 then return nil end

	-- Sort by tie-break rules and return the winner.
	table.sort(ready, resolveReadyTie)
	return ready[1]
end

--------------------------------------------------
-- CHECK BATTLE END
--------------------------------------------------

local function checkBattleEnd(state)
	local playersAlive = getSideAlive(state, "Player")
	local enemiesAlive = getSideAlive(state, "Enemy")

	if playersAlive == 0 then
		state.phase  = "BattleOver"
		state.winner = "Enemy"
		return true
	end

	if enemiesAlive == 0 then
		state.phase  = "BattleOver"
		state.winner = "Player"
		return true
	end

	return false
end

--------------------------------------------------
-- PUBLIC API
--------------------------------------------------

-- AdvanceClock
-- Call this when phase == "Waiting".
-- Advances CT, picks the next unit, opens their turn.
-- Returns the unit that is now active, or nil if battle is over.
function BattleCoordinator.AdvanceClock(state)
	assert(
		state.phase == "Waiting",
		"AdvanceClock: phase must be Waiting, got " .. state.phase
	)

	if checkBattleEnd(state) then
		return nil
	end

	local nextUnit = advanceToNextReady(state)
	if not nextUnit then
		return nil
	end

	state.activeUnit      = nextUnit
	state.phase           = "TurnOpen"
	state.turnRtAccrued   = 0
	state.turnActionTaken = false

	UnitSchema.RefreshAp(nextUnit)
	nextUnit.currentAp = AP_PER_TURN_STANDARD

	print(string.format(
		"[BattleCoordinator] CT:%d | Turn %d | %s",
		state.ct,
		state.turnCount + 1,
		UnitSchema.Describe(nextUnit)
	))

	return nextUnit
end

-- AccrueRt
-- Called by CommandService when an action's RT cost is determined.
-- Adds that cost to the running total for this turn.
function BattleCoordinator.AccrueRt(state, rtCost)
	assert(
		state.phase == "TurnOpen",
		"AccrueRt: no turn is open."
	)
	assert(rtCost >= 0, "AccrueRt: rtCost must be >= 0.")

	state.turnRtAccrued   = state.turnRtAccrued + rtCost
	state.turnActionTaken = true
end

-- EndTurn
-- Call this when the active unit has finished acting
-- (they used Wait, ran out of AP, or voluntarily ended).
-- Applies RT and hands control back to "Waiting".
function BattleCoordinator.EndTurn(state)
	assert(
		state.phase == "TurnOpen",
		"EndTurn: no turn is open."
	)

	local unit = state.activeUnit

	-- If no action was taken, apply Rest RT instead of accrued RT.
	-- Rest RT replaces Base RT (it is a shorter-than-normal turn).
	if not state.turnActionTaken then
		unit.remainingRt = math.round(
			BASE_RT_STANDARD * REST_RT_MULTIPLIER
		)
	else
		-- Full turn RT = Base RT + sum of all action RT costs this turn.
		-- Action costs are additive on top of the base. Minimum 1.
		unit.remainingRt = math.max(1,
			BASE_RT_STANDARD + state.turnRtAccrued
		)
	end

	print(string.format(
		"[BattleCoordinator] Turn ended | %s | Next RT: %d",
		unit.name,
		unit.remainingRt
	))

	state.turnCount     = state.turnCount + 1
	state.activeUnit    = nil
	state.turnRtAccrued = 0
	state.phase         = "Waiting"

	-- Check if battle just ended after this turn's KOs.
	checkBattleEnd(state)
end

-- GetPhase
-- Returns the current phase string.
function BattleCoordinator.GetPhase(state)
	return state.phase
end

-- GetWinner
-- Returns "Player", "Enemy", or nil if battle is not over.
function BattleCoordinator.GetWinner(state)
	return state.winner
end

return BattleCoordinator
