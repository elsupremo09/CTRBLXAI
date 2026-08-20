-- Main.server.lua
-- CTRBLXAI | Slice 1 — "One Fight" (Visual)
--
-- Wires up all Slice 1 services, runs a complete battle,
-- and broadcasts each event to the client for visual rendering.
--
-- SERVER SCRIPT. All game logic runs here. Client only displays.

local ServerScriptService = game:GetService("ServerScriptService")
local Game = ServerScriptService:WaitForChild("Game")

local UnitSchema              = require(Game:WaitForChild("UnitSchema"))
local BattleCoordinator       = require(Game:WaitForChild("BattleCoordinator"))
local CommandService          = require(Game:WaitForChild("CommandService"))
local TargetingService        = require(Game:WaitForChild("TargetingService"))
local BattleVisualBroadcaster = require(Game:WaitForChild("BattleVisualBroadcaster"))

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

--------------------------------------------------
-- MAP SETUP
--------------------------------------------------

local MAP_WIDTH  = 8
local MAP_HEIGHT = 8

CommandService.SetMapDimensions(MAP_WIDTH, MAP_HEIGHT)

--------------------------------------------------
-- SKILL DEFINITIONS
--------------------------------------------------

CommandService.RegisterSkill({
	id         = "skill_power_strike",
	name       = "Power Strike",
	power      = 30,
	inheritStr = true,
	range      = 1,
	rtCost     = 60,
})

CommandService.RegisterSkill({
	id         = "skill_precise_shot",
	name       = "Precise Shot",
	power      = 20,
	inheritStr = false,
	range      = 3,
	rtCost     = 50,
})

--------------------------------------------------
-- UNIT DEFINITIONS
--------------------------------------------------

local hero = UnitSchema.Create({
	id           = "unit_hero",
	name         = "Hero",
	side         = "Player",
	controller   = "Player",
	tileX        = 2,
	tileY        = 2,
	stats        = { STR=18, AGI=14, INT=8, VIT=16, DEX=12, LUK=10 },
	weaponDamage = 18,
	skillId      = "skill_power_strike",
	startingRt   = math.round(GameConstants.BASE_RT_STANDARD * (1 - 0.30 * 10 / (100 + 10))),
})

local enemy = UnitSchema.Create({
	id           = "unit_enemy",
	name         = "Grunt",
	side         = "Enemy",
	controller   = "AI",
	tileX        = 7,
	tileY        = 7,
	stats        = { STR=12, AGI=10, INT=6, VIT=12, DEX=8, LUK=6 },
	weaponDamage = 14,
	skillId      = "skill_precise_shot",
	startingRt   = math.round(GameConstants.BASE_RT_STANDARD * (1 - 0.30 * 6 / (100 + 6))),
})

print("====================================")
print("CTRBLXAI — Slice 1: One Fight")
print("====================================")
print(string.format("Hero  : %s", UnitSchema.Describe(hero)))
print(string.format("Enemy : %s", UnitSchema.Describe(enemy)))
print("====================================")

--------------------------------------------------
-- BATTLE STATE
--------------------------------------------------

local state = BattleCoordinator.CreateBattleState({ hero, enemy })

--------------------------------------------------
-- BROADCAST: battle starting
-- Small delay first so the client script has time to connect.
--------------------------------------------------

task.wait(2)
BattleVisualBroadcaster.BattleStarted(state.units)

--------------------------------------------------
-- SIMPLE AI
-- Slice 1 stand-in — both sides use this same logic.
-- Skill first, then basic attack, then move+attack.
--
-- Returns a table of { actionType, selection, outcome, skillName }
-- for each action taken, so the loop can broadcast them.
--------------------------------------------------

local function runAiTurn(unit)
	local allUnits = state.units
	local actions  = {}  -- collected for broadcasting

	-- Helper: attempt one action, record it if it succeeds.
	local function tryCommit(actionType, selection, skillName)
		if BattleCoordinator.GetPhase(state) ~= "TurnOpen" then
			return false
		end

		-- Snapshot target HP before commit so we can compute actual damage dealt.
		local targetUnit = nil
		if actionType == "Attack" then
			targetUnit = selection
		elseif actionType == "Skill" then
			targetUnit = selection and selection.target
		end
		local hpBefore = targetUnit and targetUnit.currentHp or 0

		local ok, _ = CommandService.ValidateAndCommit(
			state, unit.id, actionType, selection
		)

		if ok and actionType ~= "Wait" then
			local damage = targetUnit and (hpBefore - targetUnit.currentHp) or 0
			table.insert(actions, {
				actionType = actionType,
				unit       = unit,
				target     = targetUnit,
				skillName  = skillName,
				damage     = damage,
			})
		end

		return ok
	end

	-- 1. Try skill first.
	local acted = false

	if unit.skillId then
		-- Look up range from the registry — works for any skill, not just these two.
		local skillDef   = CommandService.GetSkill(unit.skillId)
		local skillRange = skillDef and (skillDef.range or 1) or 1
		local skillName  = skillDef and (skillDef.name or unit.skillId) or unit.skillId
		local skillCandidates = TargetingService.GetAttackCandidates(
			unit, allUnits, skillRange
		)
		if #skillCandidates > 0 then
			local ok = tryCommit("Skill",
				{ target = skillCandidates[1], skillId = unit.skillId },
				skillName
			)
			if ok then
				acted = true
				-- Use second AP on basic attack if still in range.
				local attackCandidates = TargetingService.GetAttackCandidates(
					unit, allUnits, 1
				)
				if #attackCandidates > 0 then
					tryCommit("Attack", attackCandidates[1], nil)
				end
			end
		end
	end

	-- 2. Try basic attack.
	if not acted then
		local attackCandidates = TargetingService.GetAttackCandidates(
			unit, allUnits, 1
		)
		if #attackCandidates > 0 then
			acted = true
			tryCommit("Attack", attackCandidates[1], nil)
			-- Second AP: attack again if target survived.
			attackCandidates = TargetingService.GetAttackCandidates(
				unit, allUnits, 1
			)
			if #attackCandidates > 0 then
				tryCommit("Attack", attackCandidates[1], nil)
			end
		end
	end

	-- 3. Move toward nearest enemy (only if no attack happened yet).
	if not acted then
		local nearestEnemy = nil
		local nearestDist  = math.huge
		for _, other in ipairs(allUnits) do
			if other.isAlive and other.side ~= unit.side then
				-- Chebyshev distance: diagonal counts as 1, same as a cardinal step.
				local d = math.max(math.abs(other.tileX - unit.tileX), math.abs(other.tileY - unit.tileY))
				if d < nearestDist then
					nearestDist  = d
					nearestEnemy = other
				end
			end
		end

		if nearestEnemy then
			local moveCandidates = TargetingService.GetMoveCandidates(
				unit, allUnits, MAP_WIDTH, MAP_HEIGHT
			)
			local bestTile = nil
			local bestDist = math.huge
			for _, tile in ipairs(moveCandidates) do
				-- Chebyshev: pick tile that minimises diagonal distance to enemy.
				local d = math.max(math.abs(tile.tileX - nearestEnemy.tileX), math.abs(tile.tileY - nearestEnemy.tileY))
				if d < bestDist then
					bestDist = d
					bestTile = tile
				end
			end
			if bestTile then
				tryCommit("Move", bestTile, nil)
			end
		end

		-- After moving, try to attack with second AP.
		local attackCandidates = TargetingService.GetAttackCandidates(
				unit, allUnits, 1
			)
		if #attackCandidates > 0 then
			tryCommit("Attack", attackCandidates[1], nil)
		end
	end

	-- Close the turn if still open.
	if BattleCoordinator.GetPhase(state) == "TurnOpen" then
		CommandService.ValidateAndCommit(state, unit.id, "Wait", nil)
	end

	return actions
end

--------------------------------------------------
-- BATTLE LOOP
--------------------------------------------------

local MAX_TURNS = 200
local turnCount = 0

while BattleCoordinator.GetPhase(state) ~= "BattleOver"
	and turnCount < MAX_TURNS
do
	local activeUnit = BattleCoordinator.AdvanceClock(state)
	if not activeUnit then break end

	turnCount = turnCount + 1

	-- Broadcast: turn started
	BattleVisualBroadcaster.TurnStarted(activeUnit, state.ct)

	-- Snapshot position before AI runs (for move broadcast)
	local preX = activeUnit.tileX
	local preY = activeUnit.tileY

	-- Run the AI and collect what happened
	local actions = runAiTurn(activeUnit)

	-- Broadcast each action that occurred
	for _, action in ipairs(actions) do
		if action.actionType == "Move" then
			BattleVisualBroadcaster.UnitMoved(action.unit)
		elseif action.actionType == "Attack" or action.actionType == "Skill" then
			local target = action.target
			if target then
				local outcome = { finalDamage = action.damage, type = "Damage" }
				BattleVisualBroadcaster.UnitActed(
					action.unit, target, outcome, action.skillName
				)
			end
		end
	end

	-- Safety: close turn if still open
	if BattleCoordinator.GetPhase(state) == "TurnOpen" then
		CommandService.ValidateAndCommit(state, activeUnit.id, "Wait", nil)
	end

	-- Broadcast: turn ended
	BattleVisualBroadcaster.TurnEnded(activeUnit, activeUnit.remainingRt)
end

--------------------------------------------------
-- RESULT
--------------------------------------------------

print("====================================")
local phase  = BattleCoordinator.GetPhase(state)
local winner = BattleCoordinator.GetWinner(state)

if phase == "BattleOver" then
	print(string.format("BATTLE OVER — %s wins! (%d turns)", winner, turnCount))
else
	print(string.format("BATTLE TIMED OUT after %d turns (no winner).", turnCount))
end
print("====================================")
print(string.format("Hero  final: %s", UnitSchema.Describe(hero)))
print(string.format("Enemy final: %s", UnitSchema.Describe(enemy)))
print("====================================")

BattleVisualBroadcaster.BattleEnded(winner or "None", state.units)
