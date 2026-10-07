--!strict
-- CTRBLXAI | AIService — One Smart Brain + Personality Scoring
--
-- Design: DB table enemy_ai_personalities (locked 2026-09-26).
-- ONE brain for every enemy. Strength comes from stats+gear; BEHAVIOR comes
-- from a PERSONALITY assigned by the unit's doctrine (doctrines.AI_Personality).
--
-- Decision model: ONE action per call (per-AP). The turn loop calls
-- AIService.DecideAction repeatedly until AP runs out or the unit waits.
--
-- Scoring is two layers:
--   Layer 1 — a shared 6-factor scorecard applied to every action.
--   Layer 2 — personality DIALS scale those factors up/down.
-- Look-ahead: a move/setup borrows the score of the action it enables.
--
-- ALL tunable numbers live in the TUNING block below — edit these in playtest.

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

-- Content data (safe to require directly — read-only catalog, like GameConstants).
local ConsumableData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("ConsumableData")
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
-- TUNING — EDIT THESE IN PLAYTEST
--------------------------------------------------

-- General behavior thresholds
local BATTLE_DISTANCE   = 6      -- within N tiles of nearest player = "in battle"
local ALLY_STAGING_RANGE = 3     -- "don't dive alone": ally must be within N tiles
local LOW_RESOURCE_PCT  = 0.35   -- HP/MP below this = recovery-worthy
local RANGED_THRESHOLD  = 2      -- weaponMaxRange > this counts as "ranged"

-- Layer 1 — shared scorecard base weights (magnitudes before personality dials)
local W = {
	DAMAGE_PCT   = 100,  -- points per 1.0 (=100%) of target max HP dealt
	KILL_BONUS   = 200,  -- lethal single action
	ALLY_HELP    = 120,  -- per 1.0 of (heal% × need) on an ally
	CONTROL      = 40,   -- per debuff/status applied
	SELF_DANGER  = 15,   -- penalty per player unit that can hit us after acting
	HAZARD       = 40,   -- penalty for ending on a hazard tile
	MP_COST      = 0.5,  -- penalty per MP spent
	ITEM_COST    = 20,   -- penalty per consumable charge spent
	LOW_HP_FOCUS = 30,   -- extra per 1.0 of (1 - target hp%)
	GUARD_BASE   = 15,   -- base value of Guard
	WAIT_SCORE   = -100, -- Wait is always last resort
	MOVE_TOWARD  = 5,    -- per tile closer (melee gap-close)
	COUNTER_RISK = 1.0,  -- penalty scale on expected counter damage taken (CounterStance)
	DECOY_PRIORITY = 1000, -- Decoy = highest-priority target within threat range (authored)
}

-- Layer 2 — personality dials. Each scales a Layer-1 factor.
-- Qualitative settings from DB row 30 turned into starting numbers.
--   damage / allyHelp / control / selfDanger / lowHpFocus / resource
local DIALS = {
	Aggressive = { damage = 1.5, allyHelp = 0.0, control = 0.4, selfDanger = 0.0, lowHpFocus = 0.6, resource = 0.5 },
	Defender   = { damage = 0.4, allyHelp = 1.2, control = 0.7, selfDanger = 1.2, lowHpFocus = 0.3, resource = 0.5 },
	Support    = { damage = 0.2, allyHelp = 1.8, control = 0.4, selfDanger = 1.2, lowHpFocus = 0.3, resource = 0.5 },
	Controller = { damage = 0.7, allyHelp = 0.4, control = 1.8, selfDanger = 0.7, lowHpFocus = 0.4, resource = 0.5 },
	Skirmisher = { damage = 1.1, allyHelp = 0.0, control = 0.4, selfDanger = 0.6, lowHpFocus = 1.8, resource = 0.5 },
}

-- Doctrine -> personality. MIRROR of doctrines.AI_Personality (DB is source of
-- truth). DoctrineData.lua does not yet carry this field; flagged for Designer
-- to migrate. Keyed by doctrineId (e.g. "DOC-BERSERKER").
local DOCTRINE_PERSONALITY = {
	["DOC-ARCANIST"] = "Aggressive", ["DOC-BERSERKER"] = "Aggressive",
	["DOC-DRAGOON"] = "Aggressive", ["DOC-DUELIST"] = "Aggressive",
	["DOC-ELEMENTALIST"] = "Aggressive", ["DOC-JUGGERNAUT"] = "Aggressive",
	["DOC-MONK"] = "Aggressive", ["DOC-REAPER"] = "Aggressive",
	["DOC-SPELLBLADE"] = "Aggressive", ["DOC-TEMPLAR"] = "Aggressive",
	["DOC-TWINBLADE"] = "Aggressive",
	["DOC-PALADIN"] = "Defender", ["DOC-SENTINEL"] = "Defender",
	["DOC-SHIELDBEARER"] = "Defender", ["DOC-VANGUARD"] = "Defender",
	["DOC-ASCETIC"] = "Support", ["DOC-CLERIC"] = "Support",
	["DOC-ENCHANTER"] = "Support", ["DOC-WARDEN"] = "Support",
	["DOC-WARLORD"] = "Support",
	["DOC-CONJURER"] = "Controller", ["DOC-GEOMANCER"] = "Controller",
	["DOC-PLAGUE-DOCTOR"] = "Controller", ["DOC-SHADOWBINDER"] = "Controller",
	["DOC-STORMBRINGER"] = "Controller", ["DOC-TACTICIAN"] = "Controller",
	["DOC-ASSASSIN"] = "Skirmisher", ["DOC-GUNNER"] = "Skirmisher",
	["DOC-RANGER"] = "Skirmisher", ["DOC-SKIRMISHER"] = "Skirmisher",
	["DOC-THIEF"] = "Skirmisher", ["DOC-TRICKSTER"] = "Skirmisher",
}
local DEFAULT_PERSONALITY = "Aggressive"

-- Player role profiling: doctrine -> coarse role (dealer/ranged/defender/support).
local ROLE_BY_PERSONALITY = {
	Aggressive = "dealer", Skirmisher = "ranged", Controller = "dealer",
	Defender = "defender", Support = "support",
}

--------------------------------------------------
-- HELPERS (preserved from prior brain)
--------------------------------------------------

-- Neutral targeting rule (user-locked 2026-10-06): enemies ignore Neutral units
-- unless the neutral turned hostile (side changes to "Enemy") or is a protect-the-NPC
-- event marked enemyPriorityTarget (Lost Noble). Every hostile-target check routes here.
local function isHostileTo(unit, target)
	if not target or target.side == unit.side then return false end
	if target.side == "Neutral" then
		return target.enemyPriorityTarget == true
	end
	return true
end

local function chebyshev(ax, ay, bx, by)
	return math.max(math.abs(ax - bx), math.abs(ay - by))
end

local function findNearestEnemy(unit, allUnits)
	local best, bestDist = nil, math.huge
	for _, u in ipairs(allUnits) do
		if u.isAlive and isHostileTo(unit, u) then
			local d = chebyshev(unit.tileX, unit.tileY, u.tileX, u.tileY)
			if d < bestDist then bestDist = d; best = u end
		end
	end
	return best, bestDist
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
-- NEW HELPERS
--------------------------------------------------

-- Count living allies (same side, excluding self) within range.
local function countAlliesInRange(unit, allUnits, range)
	local count = 0
	for _, u in ipairs(allUnits) do
		if u.isAlive and u.side == unit.side and u.id ~= unit.id then
			if chebyshev(unit.tileX, unit.tileY, u.tileX, u.tileY) <= range then
				count = count + 1
			end
		end
	end
	return count
end

-- Battle-already-engaged check (added Sep 28 2026, user rule):
-- Returns true if ANY other unit on the acting unit's side is within
-- BATTLE_DISTANCE of ANY enemy (player) unit — i.e. the fight is already joined
-- somewhere. A lone diver may then engage even with no ally within staging range,
-- since it is no longer the one initiating a solo dive. Excludes the acting unit
-- itself so its own proximity does not count as "someone else engaged".
local function battleAlreadyEngaged(unit, allUnits)
	for _, ally in ipairs(allUnits) do
		if ally.isAlive and ally.side == unit.side and ally.id ~= unit.id then
			for _, foe in ipairs(allUnits) do
				if foe.isAlive and isHostileTo(unit, foe) then
					if chebyshev(ally.tileX, ally.tileY, foe.tileX, foe.tileY) <= BATTLE_DISTANCE then
						return true
					end
				end
			end
		end
	end
	return false
end

-- Count living enemies still standing on a side.
local function countLivingSide(allUnits, side)
	local n = 0
	for _, u in ipairs(allUnits) do
		if u.isAlive and u.side == side then n = n + 1 end
	end
	return n
end

-- Resolve a unit's personality from its doctrine, with the
-- last-enemy-standing override (sole survivor fights Aggressive).
local function resolvePersonality(unit, allUnits)
	if countLivingSide(allUnits, unit.side) <= 1 then
		return "Aggressive"
	end
	local p = DOCTRINE_PERSONALITY[unit.doctrineId or ""]
	return p or DEFAULT_PERSONALITY
end

-- Coarse role of a player unit (for profiling-based decisions).
local function profileRole(u)
	local p = DOCTRINE_PERSONALITY[u.doctrineId or ""]
	return ROLE_BY_PERSONALITY[p or ""] or "dealer"
end

local function isRangedUnit(unit)
	return (unit.weaponMaxRange or 1) > RANGED_THRESHOLD
end

-- Does target already carry this status (skip redundant re-apply)?
local function hasActiveStatus(target, statusId)
	if not statusId or not _StatusService then return false end
	return _StatusService.HasStatus(target, statusId) ~= nil
end

-- How many player units could hit `unit` if it ends on (tx,ty)? (self-danger)
local function exposureAt(unit, tx, ty, allUnits)
	local count = 0
	for _, u in ipairs(allUnits) do
		if u.isAlive and isHostileTo(unit, u) then
			local range = u.weaponMaxRange or 1
			if chebyshev(tx, ty, u.tileX, u.tileY) <= range then
				count = count + 1
			end
		end
	end
	return count
end

--------------------------------------------------
-- SCORING — Layer 1 scorecard × Layer 2 dials
--------------------------------------------------

-- Score a basic attack against a unit target.
local function scoreAttack(unit, target, dials, allUnits)
	local predicted = 0
	if _CombatResolver then
		local r = _CombatResolver.ResolveBasicAttack(unit, target, unit.weaponDamage or 10)
		predicted = r.finalDamage or 0
	end
	local dmgPct = predicted / math.max(1, target.maxHp)
	local score = dmgPct * W.DAMAGE_PCT * dials.damage
	if predicted >= target.currentHp then
		score = score + W.KILL_BONUS
	end
	-- Decoy (SKL-SUMMON-DECOY): enemies treat it as highest-priority target in range.
	if target.summonType == "Decoy" then score = score + W.DECOY_PRIORITY end
	local lowHp = 1 - (target.currentHp / math.max(1, target.maxHp))
	score = score + lowHp * W.LOW_HP_FOCUS * dials.lowHpFocus
	score = score - exposureAt(unit, unit.tileX, unit.tileY, allUnits) * W.SELF_DANGER * dials.selfDanger
	-- Counter-stance avoidance: if the target holds CounterStance and THIS
	-- attacker sits within the target's basic-attack reach, attacking provokes a
	-- riposte. Subtract the expected counter damage we'd take back so the AI
	-- prefers other targets (or attacks from outside the target's reach, where
	-- no counter fires and no penalty applies).
	if _StatusService and _StatusService.HasStatus(target, "CounterStance") then
		local inst = _StatusService.HasStatus(target, "CounterStance")
		local mult = (inst and inst.counterPowerMult) or 0.85
		local dist = math.max(math.abs(unit.tileX - target.tileX), math.abs(unit.tileY - target.tileY))
		local tMin = target.weaponMinRange or 1
		local tMax = target.weaponMaxRange or 1
		if dist >= tMin and dist <= tMax then
			local backlash = 0
			if _CombatResolver then
				local cr = _CombatResolver.ResolveBasicAttack(target, unit, target.weaponDamage or 10)
				backlash = (cr.finalDamage or 0) * mult
			end
			score = score - (backlash / math.max(1, unit.maxHp)) * W.DAMAGE_PCT * W.COUNTER_RISK
		end
	end
	return score, predicted
end

-- Score a skill against one target (damage / heal / control unified).
-- Level-based MP cost (2026-10-07): price skills exactly as the server charges
-- them (CommandService.GetSkillMpCost, injected) so the AI never plans a cast it
-- cannot afford. Falls back to the flat def value if the dependency is missing.
local function skillMpCost(unit, def)
	if _CommandService and _CommandService.GetSkillMpCost then
		return (_CommandService.GetSkillMpCost(unit, def, def.id))
	end
	return def.mpCost or 0
end

local function scoreSkill(unit, def, target, dials, allUnits)
	local score = 0
	local predicted = 0

	-- GROUND/TILE-TARGET skills (Miasma Cloud, Poison Trap, zones) pass a stat-less
	-- marker { isGroundTarget = true, tileX, tileY } as target — it has NO .side,
	-- .effectiveStats, or .currentHp. It must NOT reach the damage/heal resolvers
	-- (CombatResolver.ResolveSkill reads defender.effectiveStats.VIT → nil crash,
	-- CombatResolver:345 — this froze the AI turn). Score it as a control/utility
	-- placement and RETURN before any unit-stat access.
	-- NOTE: this guard existed in the old brain and was dropped in the rewrite;
	-- restoring it at the top choke point covers every caller of scoreSkill.
	if target and target.isGroundTarget then
		if def.appliesStatus then
			score = score + W.CONTROL * dials.control
		end
		score = score + W.CONTROL * 0.25  -- base value for placing a zone/trap
		score = score - skillMpCost(unit, def) * W.MP_COST * dials.resource
		return score, 0
	end

	if def.isHealing then
		-- Ally-help factor: only valuable if the ally actually needs it.
		if target.side == unit.side then
			local heal = 0
			if _CombatResolver then
				local r = _CombatResolver.ResolveHealing(unit, target, def)
				heal = r.finalHealing or 0
			end
			local need = 1 - (target.currentHp / math.max(1, target.maxHp))
			local healPct = heal / math.max(1, target.maxHp)
			score = healPct * need * W.ALLY_HELP * dials.allyHelp
		end
	else
		-- Damage factor.
		if _CombatResolver and isHostileTo(unit, target) then
			local r = _CombatResolver.ResolveSkill(unit, target, def)
			predicted = r.finalDamage or 0
		end
		local dmgPct = predicted / math.max(1, target.maxHp)
		score = dmgPct * W.DAMAGE_PCT * dials.damage
		if predicted >= target.currentHp and isHostileTo(unit, target) then
			score = score + W.KILL_BONUS
		end
		if target.summonType == "Decoy" and isHostileTo(unit, target) then
			score = score + W.DECOY_PRIORITY
		end
		local lowHp = 1 - (target.currentHp / math.max(1, target.maxHp))
		score = score + lowHp * W.LOW_HP_FOCUS * dials.lowHpFocus
	end

	-- Control factor: value a debuff/status on an ENEMY, but not a redundant re-apply.
	if def.appliesStatus and isHostileTo(unit, target) then
		if not hasActiveStatus(target, def.appliesStatus) then
			score = score + W.CONTROL * dials.control
		end
	end

	-- Setup-buff value (rule 24, 2026-10-07): a power-0 buff on a friendly unit that
	-- does not already have it is worth half a CONTROL point, so the AI actually uses
	-- doctrine buffs (Hold the Line, Coordinated Advance, War Cry). Rule 23 below
	-- still zeroes a re-buff of a unit that already has the status.
	if def.appliesStatus and not def.isHealing and (def.power or 0) == 0
		and target.side == unit.side and not hasActiveStatus(target, def.appliesStatus) then
		score = score + W.CONTROL * 0.5 * (dials.control or 1)
	end

	-- MP recovery value (2026-10-07: Mana Surge / Meditate): worth half a CONTROL
	-- point when the friendly target is missing MP. Rule 23 below still applies.
	if (def.selfMpRestoreFraction or def.allyMpTransferFraction) and target.side == unit.side
		and (target.currentMp or 0) < (target.maxMp or 0) then
		score = score + W.CONTROL * 0.5 * (dials.control or 1)
	end

	-- No-redundant-status on ALLIES (rule 23): a PURE BUFF skill that applies a
	-- status to an ally who ALREADY has it is a wasted turn — zero out its value so
	-- the brain won't pick it (a Support won't re-buff an already-buffed ally).
	-- NOTE: excludes healing skills (not def.isHealing) — a heal is judged on the
	-- healing it does even if it carries a rider buff the ally already holds, so a
	-- needed heal is never suppressed just because the buff is still active.
	if def.appliesStatus and not def.isHealing
		and target.side == unit.side and hasActiveStatus(target, def.appliesStatus) then
		score = 0
	end

	-- Resource cost.
	score = score - skillMpCost(unit, def) * W.MP_COST * dials.resource
	return score, predicted
end

-- Score using a consumable item (heal/cure) — items are a normal option now.
local function scoreItem(unit, slotIdx, consDef, allUnits, dials)
	local formula = consDef.effectFormula or ""
	local charges = 0
	local slot = unit.consumableSlots and unit.consumableSlots[slotIdx]
	if slot then charges = slot.currentCharges or 0 end

	local bestScore, bestTarget = -math.huge, nil

	-- Healing item → score as ally-help (best needy ally, or self).
	if formula:match("Restore%s+%d+%%%s+target%s+Max%s+HP") then
		-- consider self + allies
		local candidates = { unit }
		for _, u in ipairs(allUnits) do
			if u.isAlive and u.side == unit.side and u.id ~= unit.id then
				table.insert(candidates, u)
			end
		end
		for _, u in ipairs(candidates) do
			local need = 1 - (u.currentHp / math.max(1, u.maxHp))
			local s = need * W.ALLY_HELP * dials.allyHelp
			-- self-heal uses damage-agnostic self-preservation value for non-support
			if u.id == unit.id then s = need * W.ALLY_HELP * math.max(dials.allyHelp, dials.selfDanger * 0.5) end
			if s > bestScore then bestScore = s; bestTarget = u end
		end
	elseif formula:match("Remove") then
		-- Cure item → value only if self has a disabling status.
		for _, inst in ipairs(unit.statusInstances or {}) do
			if inst.id == "Poison" or inst.id == "Burn" or inst.id == "Silence" then
				bestScore = W.CONTROL * dials.control; bestTarget = unit; break
			end
		end
	end

	if not bestTarget then return -math.huge, nil end
	-- Resource + conservation: last charge is precious.
	bestScore = bestScore - W.ITEM_COST * dials.resource
	if charges <= 1 then
		local need = 1 - (bestTarget.currentHp / math.max(1, bestTarget.maxHp))
		if need < 0.65 then bestScore = -math.huge end  -- save last charge unless critical
	end
	return bestScore, bestTarget
end

-- Score Guard (fallback / self-preservation).
local function scoreGuard(unit, dials)
	local hpPct = unit.currentHp / math.max(1, unit.maxHp)
	local base = W.GUARD_BASE + (1 - hpPct) * 40
	-- Defenders value Guard highly; damage-first personalities barely.
	return base * (0.5 + dials.selfDanger)
end

--------------------------------------------------
-- CANDIDATE ENUMERATION (reuse targeting service)
--------------------------------------------------

local function enumerateSkillEntries(unit, allUnits)
	local skills = {}
	for _, sid in ipairs(unit.skillIds or {}) do
		local def = _CommandService and _CommandService.GetSkill(sid)
		if def and _UnitSchema and _UnitSchema.HasEnoughMp(unit, skillMpCost(unit, def)) then
			local candidates = _TargetingService.GetSkillCandidates(unit, allUnits, def)
			if candidates and #candidates > 0 then
				table.insert(skills, { def = def, candidates = candidates })
			end
		end
	end
	return skills
end

--------------------------------------------------
-- DECISION FLOW — returns ONE action per call (per-AP)
--   action = { actionType, selection, skillName, score, rtEstimate, tile }
--------------------------------------------------

function AIService.DecideAction(unit, allUnits, mapW, mapH)
	if not unit.isAlive or (unit.currentAp or 0) <= 0 then return nil end

	local personality = resolvePersonality(unit, allUnits)
	local dials = DIALS[personality] or DIALS[DEFAULT_PERSONALITY]
	local nearest, nearestDist = findNearestEnemy(unit, allUnits)
	if not nearest then return nil end  -- no players left

	local moveTiles = _TargetingService.GetMoveCandidates(unit, allUnits, mapW, mapH) or {}
	local attackTargets = _TargetingService.GetAttackCandidates(unit, allUnits, unit.weaponMaxRange or 1) or {}
	local skillEntries = enumerateSkillEntries(unit, allUnits)

	----------------------------------------------------------------
	-- Helper: best move tile toward the nearest player (gap close).
	----------------------------------------------------------------
	local function bestMoveToward()
		-- PATH-AWARE ADVANCE (fix Sep 28 2026): GetMoveCandidates already BFSes
		-- from the unit and returns ONLY reachable empty tiles (it routes THROUGH
		-- allies but cannot STOP on them). The old ranking used straight-line
		-- distance from the candidate tile to the nearest player with pathCost as a
		-- tiny tiebreak; when the straight-line-closest lane was clogged by allies,
		-- the reachable tiles that remained did not clearly win, so boxed-in
		-- enemies (observed: Grunt 2 parked 7 turns, Grunt 7 6 turns) stalled.
		--
		-- New ranking: among reachable tiles, strongly prefer those that REDUCE the
		-- unit's current distance-to-nearest-player (real progress), then break ties
		-- by shorter pathCost (cheaper step), then by lower straight-line distance.
		-- A tile reached by routing AROUND the jam has a genuine smaller
		-- distance-to-player, so it now scores as progress instead of being ignored.
		local curDist = chebyshev(unit.tileX, unit.tileY, nearest.tileX, nearest.tileY)
		local best, bestScore = nil, -math.huge
		for _, tile in ipairs(moveTiles) do
			local d = chebyshev(tile.tileX, tile.tileY, nearest.tileX, nearest.tileY)
			-- Progress reward: how many tiles closer than standing still (can be
			-- negative for a tile that is farther). Weighted heavily so any genuine
			-- advance beats a lateral/backward tile.
			local progress = curDist - d
			local s = progress * 10 - d
			if isTileHazardous(tile.tileX, tile.tileY) then s = s - 100 end
			s = s - (tile.pathCost or 0) * 0.1
			if s > bestScore then bestScore = s; best = tile end
		end
		if best then
			-- Diagnostic: if the best reachable tile does NOT reduce distance, the
			-- unit is boxed in by allies/terrain — surface it instead of silently
			-- appearing to "freeze" (it is stuck, not crashed).
			local bestDist = chebyshev(best.tileX, best.tileY, nearest.tileX, nearest.tileY)
			if bestDist >= curDist then
				print(string.format(
					"[AIService] %s cannot advance (boxed): best reachable tile (%d,%d) dist=%d >= current dist=%d — taking best available",
					unit.name, best.tileX, best.tileY, bestDist, curDist))
			end
			return { actionType = "Move", selection = best, skillName = nil,
				score = W.MOVE_TOWARD, rtEstimate = 0, tile = best,
				targetName = string.format("(%d,%d)", best.tileX, best.tileY) }
		end
		-- No reachable empty tile at all (fully surrounded): genuinely nothing to do.
		print(string.format(
			"[AIService] %s has NO reachable move tile (fully boxed in) — will Guard/Wait",
			unit.name))
		return nil
	end

	----------------------------------------------------------------
	-- Best consumable action right now (items are a normal scored option).
	-- Returns a committable Item action or nil. Uses scoreItem() per slot.
	----------------------------------------------------------------
	local function bestItemAction(u, units, d)
		if not u.consumableSlots then return nil end
		local bestScore, bestSlot, bestTarget = 0, nil, nil
		for idx = 1, (u.consumableSlotCount or 3) do
			local slot = u.consumableSlots[idx]
			if slot and slot.consumableId and (slot.currentCharges or 0) > 0 then
				local consDef = ConsumableData.GetById(slot.consumableId)
				if consDef then
					local s, tgt = scoreItem(u, idx, consDef, units, d)
					if tgt and s > bestScore then
						bestScore = s; bestSlot = idx; bestTarget = tgt
					end
				end
			end
		end
		if bestSlot and bestTarget then
			-- Pass the real UNIT OBJECT as target (NOT a coordinate). CommandService
			-- validateItemTarget/resolveItemEffect require a unit (.id for "Self",
			-- .side/.isAlive for ally rules, .maxHp/.maxMp for the heal/MP math).
			-- A bare {tileX,tileY} was rejected → item never committed (Defect #1).
			return {
				actionType = "Item",
				selection = { target = bestTarget, itemSlotIndex = bestSlot },
				skillName = nil, score = bestScore, rtEstimate = 0, tile = nil,
				targetName = bestTarget.name or "self",
			}
		end
		return nil
	end

	----------------------------------------------------------------
	-- (1) BATTLE DISTANCE: farther than 6 tiles → close gap (ignore personality).
	--     Pushed-away recovery: if HP/MP < 35%, recover first.
	----------------------------------------------------------------
	if nearestDist > BATTLE_DISTANCE then
		local hpPct = unit.currentHp / math.max(1, unit.maxHp)
		local mpPct = unit.currentMp / math.max(1, unit.maxMp)
		if hpPct < LOW_RESOURCE_PCT or mpPct < LOW_RESOURCE_PCT then
			-- Pushed-away recovery: if a recovery item is worth using now, use it
			-- before re-engaging. bestItemAction scans equipped consumables.
			local itemAction = bestItemAction(unit, allUnits, dials)
			if itemAction then return itemAction end
		end
		return bestMoveToward()
	end

	----------------------------------------------------------------
	-- (2) KO OVERRIDE: any single action that KOs a player → take it.
	----------------------------------------------------------------
	local koAction, koScore = nil, -math.huge
	for _, target in ipairs(attackTargets) do
		local _, predicted = scoreAttack(unit, target, dials, allUnits)
		if predicted >= target.currentHp then
			if predicted > koScore then
				koScore = predicted
				koAction = { actionType = "Attack", selection = target, skillName = nil,
					score = W.KILL_BONUS + predicted, rtEstimate = 0, tile = nil, targetName = target.name }
			end
		end
	end
	for _, entry in ipairs(skillEntries) do
		if not entry.def.isHealing then
			for _, target in ipairs(entry.candidates) do
				-- Skip ground/tile markers: no .side/.currentHp, can't be a KO target.
				if not target.isGroundTarget and isHostileTo(unit, target) then
					local _, predicted = scoreSkill(unit, entry.def, target, dials, allUnits)
					if predicted >= target.currentHp and predicted > koScore then
						koScore = predicted
						koAction = { actionType = "Skill",
							selection = { target = target, skillId = entry.def.id },
							skillName = entry.def.name, score = W.KILL_BONUS + predicted,
							rtEstimate = entry.def.mpCost or 0, tile = nil, targetName = target.name }
					end
				end
			end
		end
	end
	if koAction then return koAction end

	----------------------------------------------------------------
	-- (3) ENGAGEMENT STAGING — Aggressive/Skirmisher/Controller only.
	--     Within battle distance but alone (no ally within 3): don't dive.
	--     EXCEPTION (user rule, Sep 28 2026): if the battle is ALREADY ENGAGED —
	--     any other allied enemy is within BATTLE_DISTANCE of a player — then a lone
	--     diver treats it as safe to engage even with no ally within staging range.
	--     The fight is already joined, so a straggler should not hang back.
	----------------------------------------------------------------
	local staging = (personality == "Aggressive" or personality == "Skirmisher" or personality == "Controller")
	if staging
		and countAlliesInRange(unit, allUnits, ALLY_STAGING_RANGE) == 0
		and not battleAlreadyEngaged(unit, allUnits) then
		if isRangedUnit(unit) then
			-- ranged: attack if a target is in range; else move to get in range; else guard
			if #attackTargets > 0 then
				-- fall through to normal scoring (it will pick the attack)
			else
				local mv = bestMoveToward()
				if mv then return mv end
				return { actionType = "Guard", selection = nil, skillName = nil,
					score = scoreGuard(unit, dials), rtEstimate = 0, targetName = "self" }
			end
		else
			-- melee alone (fix Sep 28 2026): the "don't dive alone" rule (19) exists so
			-- a lone melee diver does not suicide-rush the player GROUP — it does NOT
			-- mean stand still. The old code unconditionally returned Guard here, so a
			-- melee unit separated from its group (e.g. clogged out of formation)
			-- Guarded in place turn after turn and looked frozen (observed: Grunt 2/7
			-- parked 6-7 turns). Instead, REGROUP: move toward the nearest ally to
			-- rejoin formation; if there is no ally to regroup with, hold with Guard.
			local nearestAllyTile, nearestAllyDist = nil, math.huge
			for _, u in ipairs(allUnits) do
				if u.isAlive and u.side == unit.side and u.id ~= unit.id then
					local d = chebyshev(unit.tileX, unit.tileY, u.tileX, u.tileY)
					if d < nearestAllyDist then nearestAllyDist = d; nearestAllyTile = u end
				end
			end
			if nearestAllyTile then
				-- Pick the reachable tile that gets closest to the nearest ally.
				local curToAlly = nearestAllyDist
				local regroupBest, regroupScore = nil, -math.huge
				for _, tile in ipairs(moveTiles) do
					local d = chebyshev(tile.tileX, tile.tileY, nearestAllyTile.tileX, nearestAllyTile.tileY)
					local s = (curToAlly - d) * 10 - d
					if isTileHazardous(tile.tileX, tile.tileY) then s = s - 100 end
					s = s - (tile.pathCost or 0) * 0.1
					if s > regroupScore then regroupScore = s; regroupBest = tile end
				end
				if regroupBest then
					print(string.format("[AIService] %s (%s) regrouping toward ally at (%d,%d)",
						unit.name, personality, nearestAllyTile.tileX, nearestAllyTile.tileY))
					return { actionType = "Move", selection = regroupBest, skillName = nil,
						score = W.MOVE_TOWARD, rtEstimate = 0, tile = regroupBest,
						targetName = string.format("regroup (%d,%d)", regroupBest.tileX, regroupBest.tileY) }
				end
			end
			-- No ally to regroup with (or no reachable tile): hold position.
			return { actionType = "Guard", selection = nil, skillName = nil,
				score = scoreGuard(unit, dials), rtEstimate = 0, targetName = "self" }
		end
	end

	----------------------------------------------------------------
	-- (4+5) SCORE ALL LEGAL OPTIONS via scorecard × dials; pick best.
	----------------------------------------------------------------
	local candidates = {}

	for _, target in ipairs(attackTargets) do
		local s = scoreAttack(unit, target, dials, allUnits)
		table.insert(candidates, { actionType = "Attack", selection = target, skillName = nil,
			score = s, rtEstimate = 0, tile = nil, targetName = target.name })
	end

	for _, entry in ipairs(skillEntries) do
		for _, target in ipairs(entry.candidates) do
			local s = scoreSkill(unit, entry.def, target, dials, allUnits)
			table.insert(candidates, { actionType = "Skill",
				selection = { target = target, skillId = entry.def.id },
				skillName = entry.def.name, score = s,
				rtEstimate = entry.def.mpCost or 0, tile = nil, targetName = target.name })
		end
	end

	-- Guard (fallback)
	if not unit.guardUsedThisTurn then
		table.insert(candidates, { actionType = "Guard", selection = nil, skillName = nil,
			score = scoreGuard(unit, dials), rtEstimate = 0, tile = nil, targetName = "self" })
	end

	-- Consumable/item use as a normal scored option (decision: items are a
	-- normal choice). Support heals allies here; Aggressive only when it wins.
	local itemAction = bestItemAction(unit, allUnits, dials)
	if itemAction then
		table.insert(candidates, itemAction)
	end

	-- Skirmisher anti-tunnel-vision (rule 26): before chasing a low-HP KO target,
	-- verify remaining AP lets us BOTH move to AND hit it THIS turn. We approximate
	-- "hit this turn" as: a legal move tile puts the target within weapon range,
	-- and we still have AP left to attack after moving (currentAp >= 2). If the
	-- ideal (lowest-HP) target is NOT reachable-and-hittable, we do NOT chase it —
	-- we let normal scoring pick the best target we CAN actually hit.
	if personality == "Skirmisher" and #attackTargets == 0 and (unit.currentAp or 0) >= 2 then
		local wpnRange = unit.weaponMaxRange or 1
		-- lowest-HP enemy that some move tile brings into weapon range this turn
		local bestKO, bestKOHp, bestKOTile = nil, math.huge, nil
		for _, u in ipairs(allUnits) do
			if u.isAlive and isHostileTo(unit, u) then
				for _, tile in ipairs(moveTiles) do
					if chebyshev(tile.tileX, tile.tileY, u.tileX, u.tileY) <= wpnRange then
						if u.currentHp < bestKOHp then
							bestKOHp = u.currentHp; bestKO = u; bestKOTile = tile
						end
						break
					end
				end
			end
		end
		if bestKO and bestKOTile then
			-- Reachable + hittable: move to set up the kill. Borrow the KO/attack value.
			table.insert(candidates, {
				actionType = "Move", selection = bestKOTile, skillName = nil,
				score = W.KILL_BONUS * 0.5 + (1 - bestKOHp / math.max(1, bestKO.maxHp)) * W.LOW_HP_FOCUS * dials.lowHpFocus,
				rtEstimate = 0, tile = bestKOTile,
				targetName = string.format("setup-KO %s", bestKO.name),
			})
		end
	end

	-- Backstab reposition (rule 15) — Aggressive & Skirmisher only. Evaluate moving
	-- to a tile in a target's BACK arc for the facing precision bonus, and compare
	-- that improved-hit value against just attacking now. Only considers move tiles
	-- adjacent to the target (melee backstab); ranged units skip (they already hold
	-- range). Bounded: only checks the current in-range attack targets.
	if (personality == "Aggressive" or personality == "Skirmisher")
		and not isRangedUnit(unit) and (unit.currentAp or 0) >= 2 then
		for _, target in ipairs(attackTargets) do
			local bestTile, bestBonus = nil, 0
			for _, tile in ipairs(moveTiles) do
				if chebyshev(tile.tileX, tile.tileY, target.tileX, target.tileY) == 1 then
					local zone = GameConstants.GetFacingZone(tile.tileX, tile.tileY, target.tileX, target.tileY, target.facing)
					local bonus = GameConstants.GetFacingPrecisionBonus(zone)
					if bonus > bestBonus then bestBonus = bonus; bestTile = tile end
				end
			end
			-- Only propose if repositioning yields a real precision gain (back/side arc).
			if bestTile and bestBonus > 0 then
				local baseScore = scoreAttack(unit, target, dials, allUnits)
				table.insert(candidates, {
					actionType = "Move", selection = bestTile, skillName = nil,
					score = baseScore * (1 + bestBonus),  -- borrow the improved attack it sets up
					rtEstimate = 0, tile = bestTile,
					targetName = string.format("backstab %s", target.name),
				})
			end
		end
	end

	-- Look-ahead move: a move borrows the score of the best attack it enables.
	-- Simplified: if no attack is currently possible, score a gap-closing move by
	-- how much closer it gets us (melee) / whether it opens a shot (ranged).
	if #attackTargets == 0 then
		local mv = bestMoveToward()
		if mv then
			-- borrow: closer to a target is worth a fraction of an attack
			mv.score = W.MOVE_TOWARD + (1 / math.max(1, nearestDist)) * W.DAMAGE_PCT * dials.damage
			table.insert(candidates, mv)
		end
	end

	-- Wait (always available, always lowest)
	table.insert(candidates, { actionType = "Wait", selection = nil, skillName = nil,
		score = W.WAIT_SCORE, rtEstimate = 0, tile = nil, targetName = "wait" })

	-- Pick highest score. Tie-break: lower RT estimate, then safer resulting tile.
	table.sort(candidates, function(a, b)
		if math.abs(a.score - b.score) > 0.001 then
			return a.score > b.score
		end
		if (a.rtEstimate or 0) ~= (b.rtEstimate or 0) then
			return (a.rtEstimate or 0) < (b.rtEstimate or 0)
		end
		local ax = a.tile and exposureAt(unit, a.tile.tileX, a.tile.tileY, allUnits) or 0
		local bx = b.tile and exposureAt(unit, b.tile.tileX, b.tile.tileY, allUnits) or 0
		return ax < bx
	end)

	local best = candidates[1]
	if best then
		print(string.format("[AIService] %s (%s) -> %s (%s) score=%.1f",
			unit.name, personality, best.actionType, tostring(best.targetName), best.score))
	end
	return best
end

--------------------------------------------------
-- COMPATIBILITY SHIM
-- Old callers used PlanTurn(...) -> action list. The per-AP turn loop should
-- call DecideAction directly; this shim returns a single-action list so any
-- stray caller still works during the transition.
--------------------------------------------------
function AIService.PlanTurn(unit, allUnits, mapW, mapH)
	local action = AIService.DecideAction(unit, allUnits, mapW, mapH)
	if not action then return {} end
	return { action }
end

return AIService
