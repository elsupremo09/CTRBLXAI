-- CommandService.lua
-- CTRBLXAI | Slice 1
--
-- The single entry point for all unit actions.
-- Every action — whether issued by the player or the AI —
-- goes through ValidateAndCommit(). Nothing modifies unit state
-- or the battle unless this function approves it.
--
-- Implements the 9-step Command Pipeline from the DB (command_pipeline):
--   1.  Receive command (create envelope)
--   2.  Turn gate (is this unit the active unit?)
--   3.  Action availability (is the unit able to act?)
--   4.  Loadout legality  (Slice 1: always passes — no loadout yet)
--   5.  Selection validation (call TargetingService)
--   6.  Cost evaluation (does the unit have enough AP?)
--   7.  Snapshot (immutable record — Slice 1: inline)
--   8.  Atomic commit (deduct AP, apply effects)
--   9.  Handoff (log completion)
--
-- Supported action types (Slice 1):
--   "Move"   — move the unit to a new tile
--   "Attack" — basic attack an adjacent enemy
--   "Skill"  — use the unit's equipped skill
--   "Wait"   — end the turn with no more actions
--
-- RT costs (from DB: core_stats — Action Economy):
--   Move RT per tile = round(Base RT * 0.0625) per tile moved
--   Basic Attack RT  = round(Base RT * 0.10)
--   Skill RT         = skill's authored RT cost
--   Wait             = triggers Rest RT (handled by BattleCoordinator.EndTurn)

local UnitSchema       = require(script.Parent.UnitSchema)
local TargetingService = require(script.Parent.TargetingService)
local CombatResolver   = require(script.Parent.CombatResolver)
local BattleCoordinator = require(script.Parent.BattleCoordinator)

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

-- Bind UnitSchema.ApplyDamage into CombatResolver so it can apply outcomes.
CombatResolver.BindApplyDamage(UnitSchema.ApplyDamage)

local CommandService = {}

--------------------------------------------------
-- CONSTANTS  (from GameConstants shared module)
--------------------------------------------------

local BASE_RT_STANDARD     = GameConstants.BASE_RT_STANDARD
local MOVE_RT_PER_TILE     = BASE_RT_STANDARD * GameConstants.MOVE_RT_FACTOR
local BASIC_ATTACK_BASE_RT = math.round(BASE_RT_STANDARD * GameConstants.BASIC_ATTACK_RT_FACTOR)

--------------------------------------------------
-- INTERNAL: CONTENT REGISTRY (Slice 1 stub)
--   The real Content Registry lives in ReplicatedStorage.
--   For Slice 1, skills are looked up from a simple table
--   populated when CommandService is first required.
--------------------------------------------------

local skillRegistry = {}

function CommandService.RegisterSkill(skillDef)
	assert(
		type(skillDef.id) == "string",
		"RegisterSkill: skillDef must have an id string."
	)
	skillRegistry[skillDef.id] = skillDef
end

-- Public read-only accessor so external code (e.g. AI) can look up a skill's data.
function CommandService.GetSkill(skillId)
	return skillRegistry[skillId]
end

local function lookupSkill(skillId)
	return skillRegistry[skillId]
end

--------------------------------------------------
-- INTERNAL: MAP STATE (Slice 1 stub)
--   CommandService needs map dimensions for TargetingService.
--   Main.server.lua sets these once the battle starts.
--------------------------------------------------

local _mapWidth  = 8
local _mapHeight = 8

function CommandService.SetMapDimensions(width, height)
	_mapWidth  = width
	_mapHeight = height
end

--------------------------------------------------
-- INTERNAL: RT CALCULATION
--------------------------------------------------

local function calcMoveRt(tilesMoving)
	return math.round(MOVE_RT_PER_TILE * tilesMoving)
end

--------------------------------------------------
-- PUBLIC: ValidateAndCommit
--
-- Parameters:
--   state      — BattleState from BattleCoordinator
--   actorId    — id of the unit issuing the command
--   actionType — "Move" | "Attack" | "Skill" | "Wait"
--   selection  —
--     Move:   { tileX, tileY }
--     Attack: target unit table
--     Skill:  { target = unit, skillId = string }
--     Wait:   nil
--
-- Returns:
--   true,  nil          — success
--   false, reasonString — rejected (no state was changed)
--------------------------------------------------

function CommandService.ValidateAndCommit(
	state,
	actorId,
	actionType,
	selection
)
	-- ── STEP 1: Receive command ───────────────────────────────────
	-- Find the actor in the battle state.
	local actor = nil
	for _, unit in ipairs(state.units) do
		if unit.id == actorId then
			actor = unit
			break
		end
	end

	if not actor then
		return false, "Actor not found: " .. tostring(actorId)
	end

	-- ── STEP 2: Turn gate ─────────────────────────────────────────
	if state.phase ~= "TurnOpen" then
		return false, "No turn is open."
	end
	if state.activeUnit ~= actor then
		return false, actor.name .. " is not the active unit."
	end

	-- ── STEP 3: Action availability ───────────────────────────────
	if not actor.isAlive then
		return false, actor.name .. " is defeated."
	end

	-- Wait costs 0 AP and always passes availability.
	if actionType ~= "Wait" and actor.currentAp <= 0 then
		return false, actor.name .. " has no AP remaining."
	end

	-- ── STEP 4: Loadout legality ──────────────────────────────────
	-- Slice 1: no equipment or doctrine. Always passes.

	-- ── STEP 5: Selection validation ─────────────────────────────
	local skillDef = nil

	if actionType == "Skill" then
		if type(selection) ~= "table" or not selection.skillId then
			return false, "Skill command requires a selection with skillId."
		end

		skillDef = lookupSkill(selection.skillId)
		if not skillDef then
			return false, "Unknown skill: " .. tostring(selection.skillId)
		end

		-- Re-wrap selection so TargetingService sees target + skillRange.
		local targetSelection = {
			target     = selection.target,
			skillRange = skillDef.range or 1,
		}

		local valid, reason = TargetingService.ValidateSelection(
			actor, "Skill", targetSelection,
			state.units, _mapWidth, _mapHeight
		)
		if not valid then
			return false, reason
		end

	else
		local valid, reason = TargetingService.ValidateSelection(
			actor, actionType, selection,
			state.units, _mapWidth, _mapHeight
		)
		if not valid then
			return false, reason
		end
	end

	-- ── STEP 6: Cost evaluation ───────────────────────────────────
	-- All actions cost 1 AP except Wait (0 AP).
	local apCost = (actionType == "Wait") and 0 or 1

	if apCost > 0 and actor.currentAp < apCost then
		return false, actor.name .. " does not have enough AP."
	end

	-- ── STEP 7: Snapshot (Slice 1: inline — no separate object) ──
	-- Nothing to do here in Slice 1.

	-- ── STEP 8: Atomic commit ─────────────────────────────────────
	-- Deduct AP first, then apply effects.
	actor.currentAp = actor.currentAp - apCost

	if actionType == "Move" then
		-- Use pathCost from TargetingService (actual budget consumed, accounts for
		-- diagonal steps at 1.5×). Fall back to Manhattan distance if not provided.
		local pathCost
		if selection.pathCost ~= nil then
			pathCost = selection.pathCost
		else
			local dx = math.abs(selection.tileX - actor.tileX)
			local dy = math.abs(selection.tileY - actor.tileY)
			pathCost = dx + dy
		end
		local rtCost = calcMoveRt(pathCost)
		BattleCoordinator.AccrueRt(state, rtCost)

		actor.tileX = selection.tileX
		actor.tileY = selection.tileY

		print(string.format(
			"[CommandService] MOVE | %s -> (%d,%d) | RT:%d | AP left:%d",
			actor.name, actor.tileX, actor.tileY,
			rtCost, actor.currentAp
		))

	elseif actionType == "Attack" then
		local target  = selection

		-- Basic Attack RT = round(Base RT * 0.10) + Effective Weapon WT
		-- Effective Weapon WT: Slice 1 stub — stored on unit as weaponWt (default 0).
		-- Full formula: weaponWt * (1 - STR / (200 + STR)) — added in Slice 4.
		local effectiveWeaponWt = actor.weaponWt or 0
		local rtCost = BASIC_ATTACK_BASE_RT + effectiveWeaponWt

		-- Weapon damage: stored on unit as weaponDamage (Slice 1 stub, default 10).
		local weaponDamage = actor.weaponDamage or 10

		local outcome = CombatResolver.ResolveBasicAttack(
			actor, target, weaponDamage
		)
		CombatResolver.ApplyOutcome(outcome, target)
		BattleCoordinator.AccrueRt(state, rtCost)

		print(string.format(
			"[CommandService] ATTACK | %s -> %s | Dmg:%d | RT:%d | AP left:%d",
			actor.name, target.name,
			outcome.finalDamage, rtCost, actor.currentAp
		))

	elseif actionType == "Skill" then
		local target  = selection.target
		local rtCost  = skillDef.rtCost or math.round(BASE_RT_STANDARD * 0.10)

		local outcome = CombatResolver.ResolveSkill(actor, target, skillDef)
		CombatResolver.ApplyOutcome(outcome, target)
		BattleCoordinator.AccrueRt(state, rtCost)

		print(string.format(
			"[CommandService] SKILL [%s] | %s -> %s | Dmg:%d | RT:%d | AP left:%d",
			skillDef.name or skillDef.id,
			actor.name, target.name,
			outcome.finalDamage, rtCost, actor.currentAp
		))

	elseif actionType == "Wait" then
		-- Wait ends the turn immediately. No AP or RT cost here —
		-- BattleCoordinator.EndTurn handles Rest RT.
		print(string.format(
			"[CommandService] WAIT | %s",
			actor.name
		))
		BattleCoordinator.EndTurn(state)
		return true, nil
	end

	-- ── STEP 9: Handoff ───────────────────────────────────────────
	-- If the unit has no AP left, end the turn automatically.
	if actor.currentAp <= 0 then
		BattleCoordinator.EndTurn(state)
	end

	return true, nil
end

return CommandService
