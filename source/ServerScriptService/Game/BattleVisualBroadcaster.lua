-- BattleVisualBroadcaster.lua
-- CTRBLXAI | Slice 1 Visual
--
-- Server-side broadcaster. Called by Main.server.lua at each
-- battle event. Fires the appropriate RemoteEvent so the client
-- can render what just happened.
--
-- This module also owns the pacing delay between actions.
-- The battle logic runs instantly; this module inserts task.wait()
-- calls so the player can watch events unfold at human speed.
--
-- RULE: This module only fires RemoteEvents. It does NOT modify
-- any unit state or battle state. It is purely a display bridge.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BattleEvents = require(
	ReplicatedStorage
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Remotes")
		:WaitForChild("BattleEvents")
)

local BattleVisualBroadcaster = {}

--------------------------------------------------
-- PACING
-- How long the battle pauses after each event type
-- so the player has time to watch.
--------------------------------------------------

local PACE = {
	BattleStart  = 1.0,   -- pause after showing all units
	TurnStart    = 0.3,   -- brief pause before a unit acts
	Move         = 0.6,   -- time to watch a unit glide to its tile
	Action       = 0.8,   -- time to watch an attack or skill land
	Defeat       = 1.2,   -- longer pause when a unit goes down
	TurnEnd      = 0.2,   -- short breath between turns
	BattleEnd    = 0.0,   -- no pause needed — result is final
}

--------------------------------------------------
-- HELPERS
--------------------------------------------------

-- Serialize just the fields the client needs for each unit.
local function serializeUnit(unit)
	return {
		id       = unit.id,
		name     = unit.name,
		side     = unit.side,
		tileX    = unit.tileX,
		tileY    = unit.tileY,
		currentHp = unit.currentHp,
		maxHp    = unit.maxHp,
		isAlive  = unit.isAlive,
		-- Extra fields for the inspector panel
		stats = unit.effectiveStats and {
			STR = unit.effectiveStats.STR,
			AGI = unit.effectiveStats.AGI,
			INT = unit.effectiveStats.INT,
			VIT = unit.effectiveStats.VIT,
			DEX = unit.effectiveStats.DEX,
			LUK = unit.effectiveStats.LUK,
		} or nil,
		currentAp   = unit.currentAp,
		remainingRt = unit.remainingRt,
		skillId     = unit.skillId,
	}
end

--------------------------------------------------
-- PUBLIC API
--------------------------------------------------

-- Call once before the battle loop starts.
function BattleVisualBroadcaster.BattleStarted(units)
	local serialized = {}
	for _, unit in ipairs(units) do
		table.insert(serialized, serializeUnit(unit))
	end

	BattleEvents.BattleStarted:FireAllClients({ units = serialized })
	task.wait(PACE.BattleStart)
end

-- Call at the top of each turn (after AdvanceClock).
function BattleVisualBroadcaster.TurnStarted(unit, ct)
	BattleEvents.TurnStarted:FireAllClients({
		unitId = unit.id,
		ct     = ct,
	})
	task.wait(PACE.TurnStart)
end

-- Call after a successful Move commit.
function BattleVisualBroadcaster.UnitMoved(unit)
	BattleEvents.UnitMoved:FireAllClients({
		unitId = unit.id,
		tileX  = unit.tileX,
		tileY  = unit.tileY,
	})
	task.wait(PACE.Move)
end

-- Call after a successful Attack or Skill commit.
-- outcome = { finalDamage, type } from CombatResolver
-- skillName = nil for basic attack
function BattleVisualBroadcaster.UnitActed(actor, target, outcome, skillName)
	BattleEvents.UnitActed:FireAllClients({
		actorId    = actor.id,
		actionType = skillName and "Skill" or "Attack",
		targetId   = target.id,
		damage     = outcome.finalDamage,
		skillName  = skillName,
		-- Send updated HP so the client bar snaps to the right value.
		targetHp   = target.currentHp,
		targetMaxHp = target.maxHp,
	})
	task.wait(PACE.Action)

	-- Extra pause if this action defeated the target.
	if not target.isAlive then
		BattleEvents.UnitDefeated:FireAllClients({ unitId = target.id })
		task.wait(PACE.Defeat)
	end
end

-- Call at the end of each turn (after EndTurn).
function BattleVisualBroadcaster.TurnEnded(unit, nextRt)
	BattleEvents.TurnEnded:FireAllClients({
		unitId = unit.id,
		nextRt = nextRt,
	})
	task.wait(PACE.TurnEnd)
end

-- Call once when the battle is over.
function BattleVisualBroadcaster.BattleEnded(winner, units)
	local serialized = {}
	for _, unit in ipairs(units) do
		table.insert(serialized, serializeUnit(unit))
	end

	BattleEvents.BattleEnded:FireAllClients({
		winner = winner,
		units  = serialized,
	})
	task.wait(PACE.BattleEnd)
end

return BattleVisualBroadcaster
