
-- CTRBLXAI | AIService — 3-Tier Role-Based AI
--
-- DB: ai_integration table
--   Tier 1 (Instant filter): Remove obviously bad options
--   Tier 2 (Quick score):    Simple math scoring → top N
--   Tier 3 (Full preview):   Simulate via preview → top 2-3
--
-- Role budgets:
--   Basic:  Tier 1 + 2 only (rush nearest, hit hardest)
--   Elite:  Tier 1 + 2 + limited Tier 3 (positioning + skill choice)
--   Boss:   Full 3-tier (full evaluation)
--
-- Interface: AIService.PlanTurn(unit, state, config) → ordered action list
-- Each action = { actionType, selection, skillName, score }

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

local AIService = {}

-- Injected dependencies (set by Main)
local _TargetingService = nil
local _CommandService   = nil
local _CombatResolver   = nil
local _StatusService    = nil
local _UnitSchema       = nil
local _TileEffectService = nil

function AIService.SetDependencies(deps)
	_TargetingService  = deps.TargetingService
	_CommandService    = deps.CommandService
	_CombatResolver    = deps.CombatResolver
	_StatusService     = deps.StatusService
	_UnitSchema        = deps.UnitSchema
	_TileEffectService = deps.TileEffectService
end

--------------------------------------------------
-- SCORING CONSTANTS
--------------------------------------------------

local SCORE = {
	KILL_BONUS          = 200,   -- huge bonus for lethal action
	DAMAGE_PER_HP       = 1.0,   -- 1 point per HP damage
	HEAL_PER_HP         = 1.2,   -- slightly prefer healing (ally survival)
	STATUS_VALUE        = 30,    -- bonus for applying a debuff
	HEAL_STATUS_VALUE   = 20,    -- bonus for applying a buff (heal-side)
	GUARD_BASE          = 15,    -- base value for Guard action
	PUSH_BASE           = 10,    -- base value for Push action
	PUSH_WALL_DMG       = 2.0,   -- per HP of wall collision damage
	MOVE_TOWARD_BONUS   = 5,     -- per tile closer to nearest enemy
	MOVE_AWAY_PENALTY   = -3,    -- per tile farther (for melee)
	EXPOSURE_PENALTY    = -15,   -- penalty per enemy that can hit us after acting
	HAZARD_PENALTY      = -40,   -- penalty for moving onto hazardous tile
	CHANNEL_DEFER_BONUS = 50,    -- prefer channeling as last AP action
	MP_EFFICIENCY       = 0.5,   -- subtract mp_cost × this from skill score
	LOW_HP_HEAL_URGENT  = 2.0,   -- multiplier on heal score when ally < 25% HP
	WAIT_SCORE          = -100,  -- Wait is always last resort
}

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function chebyshev(ax, ay, bx, by)
	return math.max(math.abs(ax - bx), math.abs(ay - by))
end

local function findNearestEnemy(unit, allUnits)
	local best, bestDist = nil, math.huge
	for _, u in ipairs(allUnits) do
		if u.isAlive and u.side ~= unit.side then
			local d = chebyshev(unit.tileX, unit.tileY, u.tileX, u.tileY)
			if d < bestDist then bestDist = d; best = u end
		end
	end
	return best, bestDist
end

local function countEnemiesInRange(tileX, tileY, allUnits, side, range)
	local count = 0
	for _, u in ipairs(allUnits) do
		if u.isAlive and u.side ~= side then
			if chebyshev(tileX, tileY, u.tileX, u.tileY) <= range then
				count = count + 1
			end
		end
	end
	return count
end

local function isTileHazardous(tileX, tileY)
	if not _TileEffectService then return false end
	local effect = _TileEffectService.GetTileEffect(tileX, tileY)
	if effect then
		local def = GameConstants.TILE_EFFECTS[effect.id]
		if def and def.hazard then return true end
	end
	return false
end

local function findLowestAlly(unit, allUnits)
	local lowestAlly, lowestPct = nil, 1.0
	for _, u in ipairs(allUnits) do
		if u.isAlive and u.side == unit.side and u.id ~= unit.id then
			local pct = u.currentHp / math.max(1, u.maxHp)
			if pct < lowestPct then lowestPct = pct; lowestAlly = u end
		end
	end
	return lowestAlly, lowestPct
end

--------------------------------------------------
-- TIER 1: INSTANT FILTER
-- Remove obviously bad candidates. No scoring.
-- Budget: < 1ms total
--------------------------------------------------

local function tier1_filterMoves(unit, moveCandidates, allUnits, mapW, mapH)
	local _, nearestDist = findNearestEnemy(unit, allUnits)
	local isRanged = (unit.weaponMaxRange or 1) > 2
	local filtered = {}

	for _, tile in ipairs(moveCandidates) do
		local dominated = false

		-- Filter: hazardous tiles (Burning, Poison Cloud)
		if isTileHazardous(tile.tileX, tile.tileY) then
			dominated = true
		end

		-- Filter (melee only): tiles that move AWAY from all enemies
		if not isRanged and not dominated then
			local newDist = math.huge
			for _, u in ipairs(allUnits) do
				if u.isAlive and u.side ~= unit.side then
					local d = chebyshev(tile.tileX, tile.tileY, u.tileX, u.tileY)
					if d < newDist then newDist = d end
				end
			end
			if newDist > nearestDist + 2 then dominated = true end
		end

		if not dominated then
			table.insert(filtered, tile)
		end
	end

	return filtered
end

local function tier1_filterSkills(unit, allUnits)
	local skills = {}
	for _, sid in ipairs(unit.skillIds or {}) do
		local def = _CommandService.GetSkill(sid)
		if def and _UnitSchema.HasEnoughMp(unit, def.mpCost or 0) then
			local dominated = false
			-- Filter: healing skills when no ally below 60%
			if def.isHealing then
				local _, lowestPct = findLowestAlly(unit, allUnits)
				if lowestPct > 0.60 then dominated = true end
			end
			if not dominated then
				-- Get candidates
				local candidates = _TargetingService.GetSkillCandidates(unit, allUnits, def)
				if #candidates > 0 then
					table.insert(skills, { def = def, candidates = candidates })
				end
			end
		end
	end
	return skills
end

--------------------------------------------------
-- TIER 2: QUICK SCORE
-- Simple math scoring. No simulation. Budget: < 5ms each.
-- Returns scored candidate actions sorted by score.
--------------------------------------------------

local function tier2_scoreAttack(unit, target)
	local predicted = 0
	if _CombatResolver then
		local result = _CombatResolver.ResolveBasicAttack(unit, target, unit.weaponDamage or 10)
		predicted = result.finalDamage or 0
	end
	local score = predicted * SCORE.DAMAGE_PER_HP
	-- Kill bonus
	if predicted >= target.currentHp then
		score = score + SCORE.KILL_BONUS
	end
	-- Prefer weaker targets (focus fire)
	local hpPct = target.currentHp / math.max(1, target.maxHp)
	score = score + (1 - hpPct) * 20
	return score, predicted
end

local function tier2_scoreSkill(unit, skillEntry, target)
	local def = skillEntry.def
	local score = 0
	local predicted = 0

	if def.isHealing then
		if _CombatResolver then
			local result = _CombatResolver.ResolveHealing(unit, target, def)
			predicted = result.finalHealing or 0
		end
		score = predicted * SCORE.HEAL_PER_HP
		-- Urgency: heal more if ally is very low
		local hpPct = target.currentHp / math.max(1, target.maxHp)
		if hpPct < 0.25 then score = score * SCORE.LOW_HP_HEAL_URGENT end
		if def.appliesStatus then score = score + SCORE.HEAL_STATUS_VALUE end
	else
		if _CombatResolver then
			local result = _CombatResolver.ResolveSkill(unit, target, def)
			predicted = result.finalDamage or 0
		end
		score = predicted * SCORE.DAMAGE_PER_HP
		if predicted >= target.currentHp then score = score + SCORE.KILL_BONUS end
		if def.appliesStatus then score = score + SCORE.STATUS_VALUE end
		local hpPct = target.currentHp / math.max(1, target.maxHp)
		score = score + (1 - hpPct) * 20
	end

	-- MP efficiency penalty
	score = score - (def.mpCost or 0) * SCORE.MP_EFFICIENCY

	-- Channeling: prefer as last-AP action, slight penalty if AP > 1
	if (def.channelTime or 0) > 0 then
		if unit.currentAp > 1 then
			score = score * 0.3  -- strongly discourage early channeling
		else
			score = score + SCORE.CHANNEL_DEFER_BONUS
		end
	end

	return score, predicted
end

local function tier2_scoreMove(unit, tile, allUnits)
	local score = 0
	-- Distance to nearest enemy
	local nearestDist = math.huge
	for _, u in ipairs(allUnits) do
		if u.isAlive and u.side ~= unit.side then
			local d = chebyshev(tile.tileX, tile.tileY, u.tileX, u.tileY)
			if d < nearestDist then nearestDist = d end
		end
	end

	local currentDist = math.huge
	for _, u in ipairs(allUnits) do
		if u.isAlive and u.side ~= unit.side then
			local d = chebyshev(unit.tileX, unit.tileY, u.tileX, u.tileY)
			if d < currentDist then currentDist = d end
		end
	end

	local isRanged = (unit.weaponMaxRange or 1) > 2
	local delta = currentDist - nearestDist  -- positive = getting closer

	if isRanged then
		-- Ranged: prefer staying at weapon range, not too close
		local idealDist = math.max(2, (unit.weaponMaxRange or 3) - 1)
		local distFromIdeal = math.abs(nearestDist - idealDist)
		score = -distFromIdeal * 3  -- penalty for distance from ideal
	else
		-- Melee: reward getting closer
		score = delta * SCORE.MOVE_TOWARD_BONUS
	end

	-- Penalty for low pathCost efficiency (prefer shorter moves when equal value)
	score = score - (tile.pathCost or 0) * 0.5

	return score
end

local function tier2_scoreGuard(unit)
	local hpPct = unit.currentHp / math.max(1, unit.maxHp)
	if hpPct > 0.70 then return -50 end  -- almost never guard at high HP
	return SCORE.GUARD_BASE + (1 - hpPct) * 40
end

local function tier2_scorePush(unit, target, allUnits)
	-- Simple push scoring: value = displacement potential + wall damage
	local force = 1 + math.floor((unit.effectiveStats and unit.effectiveStats.STR or 10) / 60)
	local stability = 1 + math.floor((target.effectiveStats and target.effectiveStats.VIT or 10) / 60)
	local dist = math.max(0, force - stability)
	local score = SCORE.PUSH_BASE + dist * 5
	-- If target is near edge or blocker, push may cause wall damage
	if dist == 0 then score = score - 5 end  -- resisted push is low value
	return score
end

local function tier2_buildCandidates(unit, allUnits, moveTiles, attackTargets, skillEntries, pushTargets, mapW, mapH)
	local candidates = {}

	-- Score attacks
	for _, target in ipairs(attackTargets) do
		local score, predicted = tier2_scoreAttack(unit, target)
		table.insert(candidates, {
			actionType = "Attack",
			selection  = target,
			skillName  = nil,
			score      = score,
			predicted  = predicted,
			targetName = target.name,
		})
	end

	-- Score skills
	for _, entry in ipairs(skillEntries) do
		for _, target in ipairs(entry.candidates) do
			local score, predicted = tier2_scoreSkill(unit, entry, target)
			table.insert(candidates, {
				actionType = "Skill",
				selection  = { target = target, skillId = entry.def.id },
				skillName  = entry.def.name,
				score      = score,
				predicted  = predicted,
				targetName = target.name,
				isChannel  = (entry.def.channelTime or 0) > 0,
				isHealing  = entry.def.isHealing or false,
			})
		end
	end

	-- Score moves (only if no combat action available, or for move-then-act planning)
	if #attackTargets == 0 and #skillEntries == 0 then
		for _, tile in ipairs(moveTiles) do
			local score = tier2_scoreMove(unit, tile, allUnits)
			table.insert(candidates, {
				actionType = "Move",
				selection  = tile,
				skillName  = nil,
				score      = score,
				predicted  = 0,
				targetName = string.format("(%d,%d)", tile.tileX, tile.tileY),
			})
		end
	end

	-- Score Guard
	if not unit.guardUsedThisTurn then
		local score = tier2_scoreGuard(unit)
		table.insert(candidates, {
			actionType = "Guard",
			selection  = nil,
			skillName  = nil,
			score      = score,
			predicted  = 0,
			targetName = "self",
		})
	end

	-- Score Push (adjacent enemies only)
	for _, target in ipairs(pushTargets) do
		local score = tier2_scorePush(unit, target, allUnits)
		table.insert(candidates, {
			actionType = "Push",
			selection  = target,
			skillName  = nil,
			score      = score,
			predicted  = 0,
			targetName = target.name,
		})
	end

	-- Wait (always available, always lowest)
	table.insert(candidates, {
		actionType = "Wait",
		selection  = nil,
		skillName  = nil,
		score      = SCORE.WAIT_SCORE,
		predicted  = 0,
		targetName = "wait",
	})

	-- Sort descending by score
	table.sort(candidates, function(a, b) return a.score > b.score end)
	return candidates
end

--------------------------------------------------
-- TIER 3: FULL PREVIEW (Elite/Boss only)
-- Simulate top N candidates, apply exposure penalty.
-- Budget: < 20ms each × top N.
--------------------------------------------------

local function tier3_refine(unit, candidates, allUnits, topN)
	-- Take top N from Tier 2
	local refined = {}
	for i = 1, math.min(topN, #candidates) do
		local c = candidates[i]
		local adjustedScore = c.score

		-- Exposure check: after this action, how many enemies can hit us?
		-- (Only relevant for Move and Attack — skills already committed)
		local checkTileX = unit.tileX
		local checkTileY = unit.tileY

		if c.actionType == "Move" then
			checkTileX = c.selection.tileX
			checkTileY = c.selection.tileY
		end

		-- Count enemies that can reach us at our position after acting
		local exposure = 0
		for _, enemy in ipairs(allUnits) do
			if enemy.isAlive and enemy.side ~= unit.side then
				local enemyRange = enemy.weaponMaxRange or 1
				local d = chebyshev(checkTileX, checkTileY, enemy.tileX, enemy.tileY)
				if d <= enemyRange then
					exposure = exposure + 1
				end
			end
		end

		adjustedScore = adjustedScore + exposure * SCORE.EXPOSURE_PENALTY
		c.score = adjustedScore
		table.insert(refined, c)
	end

	-- Re-sort after adjustments
	table.sort(refined, function(a, b) return a.score > b.score end)
	return refined
end

--------------------------------------------------
-- PUBLIC: PlanTurn
-- Returns an ordered list of actions to execute.
-- The caller (Main) commits them via tryCommit.
--------------------------------------------------

function AIService.PlanTurn(unit, allUnits, mapW, mapH)
	local role = unit.aiRole or "Basic"
	local plan = {}

	-- Gather raw candidates (used by all tiers)
	local moveTiles = _TargetingService.GetMoveCandidates(unit, allUnits, mapW, mapH)
	local attackTargets = _TargetingService.GetAttackCandidates(unit, allUnits, unit.weaponMaxRange or 1)
	local pushTargets = {}
	for _, u in ipairs(allUnits) do
		if u.isAlive and u.side ~= unit.side then
			if chebyshev(unit.tileX, unit.tileY, u.tileX, u.tileY) == 1 then
				table.insert(pushTargets, u)
			end
		end
	end

	-- TIER 1: Filter
	moveTiles = tier1_filterMoves(unit, moveTiles, allUnits, mapW, mapH)
	local skillEntries = tier1_filterSkills(unit, allUnits)

	-- TIER 2: Score all candidates
	local scored = tier2_buildCandidates(
		unit, allUnits, moveTiles, attackTargets, skillEntries, pushTargets, mapW, mapH
	)

	-- TIER 3: Refine (Elite/Boss only)
	if role == "Elite" then
		scored = tier3_refine(unit, scored, allUnits, 5)
	elseif role == "Boss" then
		scored = tier3_refine(unit, scored, allUnits, 10)
	end

	-- Build action plan from scored candidates
	-- AP budget: typically 2 AP per turn
	local apRemaining = unit.currentAp or 2
	local usedActions = {}  -- track what we've planned

	for _, candidate in ipairs(scored) do
		if apRemaining <= 0 then break end

		-- Skip if we already planned this type (except Attack can repeat)
		local aType = candidate.actionType
		local skip = false
		if aType == "Wait" then skip = true end
		if aType == "Guard" and usedActions["Guard"] then skip = true end
		if aType == "Move" and usedActions["Move"] then skip = true end
		if aType == "Push" and usedActions["Push"] then skip = true end
		-- Skip channeling skills unless this is the last AP
		if candidate.isChannel and apRemaining > 1 then skip = true end
		if not skip then
			table.insert(plan, candidate)
			usedActions[aType] = true
			apRemaining = apRemaining - 1
		end
	end

	-- If no combat actions were planned (all filtered/scored low), try move-then-act
	local hasCombat = false
	for _, p in ipairs(plan) do
		if p.actionType ~= "Move" and p.actionType ~= "Wait" then hasCombat = true; break end
	end

	if not hasCombat and #moveTiles > 0 then
		-- Score moves toward enemies and plan move as first action
		local moveScored = {}
		for _, tile in ipairs(moveTiles) do
			local score = tier2_scoreMove(unit, tile, allUnits)
			table.insert(moveScored, { tile = tile, score = score })
		end
		table.sort(moveScored, function(a, b) return a.score > b.score end)

		if #moveScored > 0 then
			-- Insert move at beginning of plan
			table.insert(plan, 1, {
				actionType = "Move",
				selection  = moveScored[1].tile,
				skillName  = nil,
				score      = moveScored[1].score,
				predicted  = 0,
				targetName = string.format("(%d,%d)", moveScored[1].tile.tileX, moveScored[1].tile.tileY),
			})
			-- Flag: after move, re-evaluate combat (caller handles this)
			plan.needsReeval = true
		end
	end

	-- Always end with Wait if AP remains
	table.insert(plan, {
		actionType = "Wait",
		selection  = nil,
		skillName  = nil,
		score      = SCORE.WAIT_SCORE,
		predicted  = 0,
		targetName = "wait",
	})

	-- Log the plan
	local planStr = {}
	for _, p in ipairs(plan) do
		local s = string.format("%s→%s(%.0f)", p.actionType, p.targetName or "?", p.score)
		table.insert(planStr, s)
	end
	print(string.format("[AIService] %s (%s) plan: %s",
		unit.name, role, table.concat(planStr, " | ")))

	return plan
end

return AIService
