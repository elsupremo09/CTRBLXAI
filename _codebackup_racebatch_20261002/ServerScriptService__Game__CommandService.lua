-- CTRBLXAI | Slice 3
--
-- The single entry point for all unit actions.
-- Implements the 9-step Command Pipeline.
--
-- Slice 3 channeling rules:
--   - Skills with channelTime > 0 enter Channeling state on commit.
--   - MP is CHECKED at commit (must be sufficient) but NOT spent.
--   - MP is SPENT at activation (when channel completes).
--   - If MP is insufficient at activation (e.g. enemy drained mana), skill fizzles.
--   - Silence, Stun, or any disabling status interrupts channeling.
--   - Damage does NOT interrupt channeling.
--
-- Also:
--   - AOE skills (Cleave pattern) resolve against multiple targets.
--   - Healing skills target allies/self.
--   - MP cost deducted on instant skills.

local UnitSchema        = require(script.Parent.UnitSchema)
local TargetingService  = require(script.Parent.TargetingService)
local CombatResolver    = require(script.Parent.CombatResolver)
local BattleCoordinator = require(script.Parent.BattleCoordinator)
local StatusService     = require(script.Parent.StatusService)
local BattleVisualBroadcaster = require(script.Parent.BattleVisualBroadcaster)
local DisplacementService = require(script.Parent.DisplacementService)
local RacePassiveService  = require(script.Parent.RacePassiveService)
local DoctrinePassiveService = require(script.Parent.DoctrinePassiveService)
local ArmorPassiveService = require(script.Parent.ArmorPassiveService)
local AugmentEffectService = require(script.Parent.AugmentEffectService)

local ConsumableData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("ConsumableData")
)

-- SkillData: used to resolve a self-buff 'stance' skill's own icon for the
-- client-only status pill (Part B: stance skills that apply no real status).
local SkillData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("SkillData")
)

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

-- Bind UnitSchema helpers into CombatResolver.
CombatResolver.BindApplyDamage(UnitSchema.ApplyDamage)
CombatResolver.BindApplyHealing(UnitSchema.ApplyHealing)

local CommandService = {}

-- Optional: TileEffectService injected at runtime
local _tileEffectService = nil
function CommandService.SetTileEffectService(tes)
	_tileEffectService = tes
end

-- FORCED-ENTRY GROUND EFFECTS (map_gen_rules row 65 points 1 + 3, Slice 5).
-- A unit pushed / knocked onto a tile gets that tile's on-entry ground effect,
-- however it got there: Deep Water -> Drowning, Quicksand -> Sinking ('movement
-- prohibited' blocks walking only, not being pushed in), plus the tile EFFECT's
-- cross effect (Vines -> Pinned, Burning -> Burn, Poison Cloud -> Poison).
-- Previously DisplacementService resolved these (result.crossEffects) but no
-- caller ever applied them. Fall damage is still applied separately by the caller.
-- Turn-timed effects (Molten / Tar Pit at turn-end, Tainted at turn start) are
-- handled by TileEffectService on the unit's own turn.
local function applyForcedEntryEffects(target, result)
	if not target or not target.isAlive or not result or not result.pushed then return end
	local fx, fy = target.tileX, target.tileY
	local terrainData = GameConstants.GetTerrainData(fx, fy)
	if terrainData and StatusService then
		local trig = terrainData.triggerEffect
		if trig == "Drowning" or trig == "Sinking" then
			local applied = StatusService.ApplyStatus(target, trig, "terrain")
			print(string.format("[CommandService] Forced entry: %s pushed onto %s at (%d,%d) -> %s%s",
				target.name, terrainData.id, fx, fy, trig, applied and "" or " (not applied / immune)"))
		end
	end
	if _tileEffectService and _tileEffectService.OnUnitEntersTile then
		_tileEffectService.OnUnitEntersTile(target, fx, fy)
	end
end
--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

local MOVE_RT_FACTOR         = GameConstants.MOVE_RT_FACTOR
local BASIC_ATTACK_RT_FACTOR = GameConstants.BASIC_ATTACK_RT_FACTOR

--------------------------------------------------
-- SKILL REGISTRY
--------------------------------------------------

local skillRegistry = {}

function CommandService.RegisterSkill(skillDef)
	assert(
		type(skillDef.id) == "string",
		"RegisterSkill: skillDef must have an id string."
	)
	skillRegistry[skillDef.id] = skillDef
end

function CommandService.RegisterSkillAlias(aliasKey, skillDef)
	-- Store the same skillDef under an alias key (e.g. legacy "skill_power_strike")
	skillRegistry[aliasKey] = skillDef
end

function CommandService.GetSkill(skillId)
	return skillRegistry[skillId]
end

function CommandService.GetAllSkills()
	return skillRegistry
end

local function lookupSkill(skillId)
	return skillRegistry[skillId]
end

--------------------------------------------------
-- MAP STATE
--------------------------------------------------

local _mapWidth  = 8
local _mapHeight = 8

function CommandService.SetMapDimensions(width, height)
	_mapWidth  = width
	_mapHeight = height
end

--------------------------------------------------
-- CHARGE LANDING (shared: used by both the preview in the turn prompt AND the
-- actual commit, so they can never diverge). A charge skill repositions the
-- actor to the best empty tile adjacent (Chebyshev 1) to the target before
-- damage: closest to the actor, tie-broken by lowest Euclidean² (straightest
-- line). Returns {x,y} or nil (already adjacent / no legal tile).
--------------------------------------------------
function CommandService.ComputeChargeLanding(actor, target, state)
	if not (actor and target) then return nil end
	local dist = math.max(math.abs(actor.tileX - target.tileX), math.abs(actor.tileY - target.tileY))
	if dist <= 1 then return nil end  -- already adjacent; no move
	local bestTile, bestDist, bestDistSq = nil, 999, 999
	for dy = -1, 1 do
		for dx = -1, 1 do
			if dx ~= 0 or dy ~= 0 then
				local cx = target.tileX + dx
				local cy = target.tileY + dy
				if cx >= 1 and cx <= _mapWidth and cy >= 1 and cy <= _mapHeight
					and not GameConstants.IsBlocked(cx, cy) then
					local occupied = false
					if state and state.units then
						for _, u in ipairs(state.units) do
							if u.isAlive and u.tileX == cx and u.tileY == cy then occupied = true; break end
						end
					end
					if not occupied then
						local dCheb = math.max(math.abs(actor.tileX - cx), math.abs(actor.tileY - cy))
						local dSq = (actor.tileX - cx)^2 + (actor.tileY - cy)^2
						if dCheb < bestDist or (dCheb == bestDist and dSq < bestDistSq) then
							bestDist = dCheb
							bestDistSq = dSq
							bestTile = { x = cx, y = cy }
						end
					end
				end
			end
		end
	end
	return bestTile
end

-- Straight-line tile path from (fromX,fromY) to (toX,toY), inclusive of the
-- landing tile, EXCLUSIVE of the start. Bresenham-style diagonal walk (matches
-- the 'legal straight path' the charge traverses). For the client path visual.
function CommandService.ComputeChargePath(fromX, fromY, toX, toY)
	local path = {}
	local x, y = fromX, fromY
	local guard = 0
	while (x ~= toX or y ~= toY) and guard < 64 do
		guard = guard + 1
		local sx = (toX > x) and 1 or (toX < x) and -1 or 0
		local sy = (toY > y) and 1 or (toY < y) and -1 or 0
		x = x + sx
		y = y + sy
		local terrain = GameConstants.GetTerrainId and GameConstants.GetTerrainId(x, y) or nil
		table.insert(path, { tileX = x, tileY = y, terrain = terrain })
	end
	return path
end
--------------------------------------------------
-- RT CALCULATION
--------------------------------------------------

local function calcMoveRt(actor, tilesMoving)
	local modBaseRt = StatusService.GetModifiedBaseRt(actor)
	local perTile = modBaseRt * MOVE_RT_FACTOR
	-- Frozen: all RT costs ×2. Wet: movement RT ×1.25.
	local frozenMult = StatusService.GetAllRtMultiplier(actor)
	local wetMult    = StatusService.GetMovementRtMultiplier(actor)
	return math.round(perTile * tilesMoving * frozenMult * wetMult)
end

local function calcBasicAttackBaseRt(actor)
	-- DB formula: Basic Attack RT = round(Modified Base RT × 0.10) + Effective Weapon WT
	-- Effective WT = raw WT × (1 - STR/(200+STR)) — STR reduces burden
	-- Armor WT is NOT added here: it is part of Modified Base RT (DB weapons_equipment
	-- id 7 "Base RT + Effective Armor WT", applied in StatusService.GetModifiedBaseRt).
	-- The WT term is the Effective WEAPON WT only (weapons_equipment id 8).
	local modBaseRt = StatusService.GetModifiedBaseRt(actor)
	local str = actor.effectiveStats and actor.effectiveStats.STR or 10
	local totalWt = (actor.weaponWt or 0)
	local effectiveWt = GameConstants.CalcEffectiveWt(totalWt, str)
	-- Basic Attack RT has two parts: the base-RT component and the weapon-WT
	-- burden. Frenzy (DB elements_statuses id 72: "Basic Attack tempo only")
	-- reduces the BASE-RT component only; per developer decision 2026-09-26 it
	-- does NOT affect the weapon-WT component.
	local baseRtComponent = math.round(modBaseRt * BASIC_ATTACK_RT_FACTOR)
	local frenzyDef = GameConstants.STATUSES.Frenzy
	if frenzyDef and frenzyDef.basicAttackRtMult and StatusService.HasStatus(actor, "Frenzy") then
		baseRtComponent = baseRtComponent * frenzyDef.basicAttackRtMult
	end
	local baseAttackRt = math.round(baseRtComponent) + math.round(effectiveWt)
	-- Frozen: all RT costs ×2
	return math.round(baseAttackRt * StatusService.GetAllRtMultiplier(actor))
end

--------------------------------------------------
-- COUNTER-ATTACK (Riposte Stance / Counter Stance reaction)
--
-- When a unit holding the CounterStance buff is hit by a DIRECT attack from an
-- attacker within its own equipped-weapon basic-attack reach, it immediately
-- strikes back with a basic attack (respecting weapon pattern incl. Cleave).
--
-- Design (user decisions 2026-09-28):
--   - No count limit: counters every eligible hit for the buff's duration.
--   - Balancer: each counter ADDS the defender's basic-attack RT to its
--     remainingRt (pushes its next turn out) — no AP, no action-RT.
--   - Reach = defender's basic-attack reach (ranged min-range, spear reach,
--     etc.), reusing GetAttackCandidates so it matches normal attacks exactly.
--   - Friendly fire allowed (cleave counter hits whatever is in the arc).
--   - RECURSION GUARD: a counter is flagged isCounter and NEVER triggers a
--     counter of its own (checked by the caller before calling this).
--------------------------------------------------

function CommandService.TriggerCounterIfEligible(defender, attacker, state, wasCounter, wasAOE)
	-- Guard 1: never let a counter (or AOE splash) trigger another counter.
	if wasCounter or wasAOE then return false end
	-- Guard 2: both units must be live and real, and not self.
	if not defender or not attacker then return false end
	if not defender.isAlive or not attacker.isAlive then return false end
	if defender.id == attacker.id then return false end
	-- Guard 3: defender must actually hold the stance.
	if not StatusService.HasStatus(defender, "CounterStance") then return false end

	-- Reach check: is the attacker a unit the defender could basic-attack right
	-- now? GetAttackCandidates already bundles weapon max range, min range, LoS,
	-- and elevation legality — the single source of truth for "my weapon can hit
	-- that tile". This makes the counter respect ranged min-range, spear reach,
	-- etc. exactly like a normal attack.
	local reachable = TargetingService.GetAttackCandidates(
		defender, state.units, defender.weaponMaxRange or 1
	)
	local inReach = false
	for _, u in ipairs(reachable) do
		if u.id == attacker.id then inReach = true; break end
	end
	if not inReach then return false end

	-- Counter power multiplier: skills stamp their own value on the status
	-- instance (Riposte 0.85, Counter Stance 0.60); fall back to the status def.
	local inst = StatusService.HasStatus(defender, "CounterStance")
	local mult = (inst and inst.counterPowerMult)
		or (GameConstants.STATUSES.CounterStance and GameConstants.STATUSES.CounterStance.counterPowerMult)
		or 0.85

	local weaponDamage = defender.weaponDamage or 10
	local weaponPattern = defender.weaponPattern or "Single"

	-- Resolve the counter as a basic attack, reusing the weapon-pattern logic
	-- from the Attack commit path. Every counter hit is flagged isCounter so
	-- ApplyOutcome / the caller will not spawn a further counter.
	local function resolveCounterHit(victim, dmgMult)
		if not victim.isAlive then return end
		local outcome = CombatResolver.ResolveBasicAttack(defender, victim, weaponDamage)
		outcome.isCounter = true
		outcome.finalDamage = math.max(0, math.round((outcome.finalDamage or 0) * mult * (dmgMult or 1.0)))
		if (dmgMult or 1.0) < 1.0 then outcome.isAOE = true end
		CombatResolver.ApplyOutcome(outcome, victim, defender)
		BattleVisualBroadcaster.UnitStateChanged(victim)
	end

	print(string.format("[CommandService] COUNTER | %s ripostes %s (x%.2f, %s)",
		defender.name, attacker.name, mult, weaponPattern))

	if weaponPattern == "Cleave" or weaponPattern == "Adjacent" then
		local cleave = TargetingService.GetCleaveTargets(defender, attacker, state.units)
		for _, u in ipairs(cleave) do
			resolveCounterHit(u, (u.id == attacker.id) and 1.0 or 0.5)
		end
	elseif weaponPattern == "ImpactSplash" then
		local splash = TargetingService.GetImpactSplashTargets(defender, attacker, state.units)
		for _, entry in ipairs(splash) do
			resolveCounterHit(entry.unit, entry.dmgMult)
		end
	elseif weaponPattern == "Line2" then
		local line = TargetingService.GetLine2Targets(defender, attacker, state.units)
		for _, entry in ipairs(line) do
			resolveCounterHit(entry.unit, entry.dmgMult or 1.0)
		end
	else
		resolveCounterHit(attacker, 1.0)
	end

	-- BALANCER: each counter delays the defender's next turn by its basic-attack RT.
	local counterRt = calcBasicAttackBaseRt(defender)
	defender.remainingRt = (defender.remainingRt or 0) + counterRt
	print(string.format("[CommandService] COUNTER RT | %s next turn +%d RT (now %d)",
		defender.name, counterRt, defender.remainingRt))
	BattleVisualBroadcaster.UnitStateChanged(defender)
	return true
end

--------------------------------------------------
-- ITEM TARGET VALIDATION
--
-- Validates that a consumable item's target satisfies the
-- targetRules from ConsumableData. Range is Chebyshev distance.
--------------------------------------------------

local function validateItemTarget(actor, target, consumableDef)
	local rules = consumableDef.targetRules or "Self"
	local range = consumableDef.range or 0

	-- Self / Self-origin: must target self (or no explicit target needed)
	if rules == "Self" then
		if not target or target.id ~= actor.id then
			return false, "This item can only target yourself."
		end
		return true, nil
	end

	if rules == "Self-origin" or rules == "Self and Allies" then
		-- Self-centered AOE: user is the implicit center
		return true, nil
	end

	-- KO Ally: special — target must be dead
	if rules == "KO Ally" then
		if not target then
			return false, "This item requires a KO'd ally target."
		end
		if target.side ~= actor.side then
			return false, "This item can only target an ally."
		end
		if target.isAlive then
			return false, "This item can only target a KO'd unit."
		end
		local dist = math.max(
			math.abs(actor.tileX - (target.tileX or 0)),
			math.abs(actor.tileY - (target.tileY or 0))
		)
		if dist > range then
			return false, "Target is out of range."
		end
		return true, nil
	end

	-- Ground / Tile targeting: target is a coordinate table { tileX, tileY }
	if rules == "Ground" or rules == "Tile" or rules == "Enemy or Ground" then
		if not target then
			return false, "This item requires a target location."
		end
		local tx = target.tileX or 0
		local ty = target.tileY or 0
		local dist = math.max(
			math.abs(actor.tileX - tx),
			math.abs(actor.tileY - ty)
		)
		if dist > range then
			return false, "Target is out of range."
		end
		return true, nil
	end

	-- All remaining rules require a living unit target
	if not target then
		return false, "This item requires a target."
	end
	if not target.isAlive then
		return false, "Target is defeated."
	end

	-- Chebyshev range check
	local dist = math.max(
		math.abs(actor.tileX - (target.tileX or 0)),
		math.abs(actor.tileY - (target.tileY or 0))
	)
	if dist > range then
		return false, "Target is out of range."
	end

	if rules == "Self or Ally" then
		if target.side ~= actor.side then
			return false, "This item can only target yourself or an ally."
		end
	elseif rules == "Ally" then
		if target.side ~= actor.side or target.id == actor.id then
			return false, "This item can only target an ally (not yourself)."
		end
	elseif rules == "Enemy" or rules == "Enemy Unit" then
		if target.side == actor.side then
			return false, "This item can only target an enemy."
		end
	elseif rules == "Any Unit" then
		-- Any living unit is valid (isAlive already checked above)
	end

	return true, nil
end

--------------------------------------------------
-- ITEM EFFECT RESOLUTION
--
-- Parses effectFormula from ConsumableData and applies the
-- immediate effect. Returns a result table for broadcasting.
--
-- Supported categories:
--   A) HP Recovery   — "Restore N% ... Max HP"
--   B) MP Recovery   — "Restore N% ... Max MP"
--   C) Status Cure   — "Remove [status] and [status]"
--   D) Direct Damage  — "Deal [element] damage equal to N% Weapon Attack Power"
--   E) Status Apply   — "Apply [status] for N turns"
--   F) Unimplemented  — anything else (logged, skipped)
--
-- NOTE: AI item usage would hook into CommandService.GetItemCandidates
-- (not yet implemented — see Main.server.lua AI turn logic).
--------------------------------------------------

local function resolveItemEffect(user, target, consumableDef, allUnits)
	local formula = consumableDef.effectFormula or ""
	local result = {
		effectType  = "Unknown",
		amount      = 0,
		statusId    = nil,
		element     = nil,
		description = formula,
	}

	-- A) HP Recovery: "Restore N% ... Max HP"
	local hpPct = formula:match("Restore (%d+)%%.-Max HP")
	if hpPct then
		local pct = tonumber(hpPct)
		local heal = math.ceil((target.maxHp or 1) * pct / 100)
		UnitSchema.ApplyHealing(target, heal)
		result.effectType = "HpRestore"
		result.amount     = heal
		return result
	end

	-- B) MP Recovery: "Restore N% ... Max MP"
	local mpPct = formula:match("Restore (%d+)%%.-Max MP")
	if mpPct then
		local pct = tonumber(mpPct)
		local restore = math.max(1, math.ceil((target.maxMp or 1) * pct / 100))
		local before  = target.currentMp or 0
		target.currentMp = math.min((target.maxMp or 1), before + restore)
		result.effectType = "MpRestore"
		result.amount     = target.currentMp - before
		return result
	end

	-- C) Status Cure: "Remove [status] and/or [status]"
	if formula:match("^Remove ") then
		local statusPart = formula:gsub("^Remove ", ""):gsub("%.$", "")
		-- Normalise separators: ", and " → ", " then " and " → ", "
		statusPart = statusPart:gsub(", and ", ", "):gsub(" and ", ", ")
		local statuses = {}
		for s in statusPart:gmatch("[^,]+") do
			local trimmed = s:match("^%s*(.-)%s*$")
			if trimmed and trimmed ~= "" then
				table.insert(statuses, trimmed)
			end
		end
		for _, statusName in ipairs(statuses) do
			StatusService.RemoveStatus(target, statusName)
		end
		result.effectType = "StatusCure"
		result.statusId   = table.concat(statuses, ", ")
		return result
	end

	-- D) Direct Damage: "Deal [Element] damage equal to N% Weapon Attack Power"
	local element, dmgPct = formula:match("Deal (%a+) damage equal to (%d+)%%")
	if element and dmgPct then
		local pct = tonumber(dmgPct)
		local attackPower = user.weaponDamage or 10
		local damage = math.round(attackPower * pct / 100)
		UnitSchema.ApplyDamage(target, damage)
		result.effectType = "Damage"
		result.amount     = damage
		result.element    = element
		return result
	end

	-- E) Status Application: "Apply [status] for N turns"
	local statusName, turns = formula:match("Apply (.+) for (%d+) turns")
	if statusName and turns then
		StatusService.ApplyStatus(target, statusName, user.id)
		result.effectType = "StatusApply"
		result.statusId   = statusName
		result.amount     = tonumber(turns)
		return result
	end

	-- F) Unimplemented formula — log and skip
	print("[Item] Effect not yet implemented: " .. formula)
	result.effectType = "Unimplemented"
	return result
end

--------------------------------------------------
-- PUBLIC: GetSkillCandidates (for AI and client)
--------------------------------------------------

function CommandService.GetSkillCandidates(actor, allUnits, skillId)
	local skillDef = lookupSkill(skillId)
	if not skillDef then return {} end
	return TargetingService.GetSkillCandidates(actor, allUnits, skillDef)
end

--------------------------------------------------
-- PUBLIC: GetUnitSkills (for client Skill Card UI)
--------------------------------------------------

function CommandService.GetUnitSkills(unit)
	local skills = {}
	for _, sid in ipairs(unit.skillIds or {}) do
		local def = lookupSkill(sid)
		if def then
			table.insert(skills, def)
		end
	end
	if #skills == 0 and unit.skillId then
		local def = lookupSkill(unit.skillId)
		if def then
			table.insert(skills, def)
		end
	end
	return skills
end

--------------------------------------------------
-- PUBLIC: ActivateChanneledSkill
--
-- Called when a channeling unit's turn comes up.
-- Checks MP, spends it, resolves the skill.
-- Returns: success (bool), result info table or nil
--------------------------------------------------

function CommandService.ActivateChanneledSkill(state, unit)
	if not unit.isChanneling or not unit.channelingData then
		return false, "Unit is not channeling."
	end

	local data     = unit.channelingData
	local skillDef = data.skillDef
	local target   = data.target
	local mpCost   = data.mpCost or 0

	-- Clear channeling state first (regardless of outcome)
	unit.isChanneling   = false
	unit.channelingData = nil
	unit.channelRt      = nil
	unit.channelResolveCt = nil

	-- Check if target is still alive (for offensive/healing skills)
	if target and not target.isAlive then
		print(string.format(
			"[CommandService] Channel FIZZLE | %s | [%s] — target %s is dead",
			unit.name, skillDef.name or skillDef.id, target.name
		))
		return false, "Target died during channel."
	end

	-- Check MP at activation — if insufficient, fizzle
	if not UnitSchema.HasEnoughMp(unit, mpCost) then
		print(string.format(
			"[CommandService] Channel FIZZLE | %s | [%s] — MP insufficient (%d/%d needed)",
			unit.name, skillDef.name or skillDef.id, unit.currentMp, mpCost
		))
		return false, "MP insufficient at activation."
	end

	-- Channel fires now: announce the skill over the caster.
	BattleVisualBroadcaster.ActionAnnounced(unit, skillDef.name or skillDef.id or "Skill")

	-- SPEND MP now
	UnitSchema.SpendMp(unit, mpCost)

	-- TWO-TIMER MODEL: the caster's RT was ALREADY charged at channel-commit time
	-- (base + skill RT cost via AccrueRt + EndTurn in ValidateAndCommit). Activation
	-- now runs in the ChannelResolve phase where NO turn is open, so calling AccrueRt
	-- here would fail its TurnOpen assert (the crash we hit). No RT is charged at
	-- activation — the skill was fully paid for on commit.

	-- Resolve the skill
	local result = {}

	if skillDef.isHealing then
		local outcome = CombatResolver.ResolveHealing(unit, target, skillDef)
		local actual = CombatResolver.ApplyOutcome(outcome, target)
		result.type     = "Healing"
		result.target   = target
		result.healing  = actual
		result.skillName = skillDef.name

		print(string.format(
			"[CommandService] Channel ACTIVATE [%s] | %s -> %s | Heal:%d | MP:%d",
			skillDef.name, unit.name, target.name, actual, mpCost
		))

	elseif skillDef.aoePattern == "Cleave" then
		local targets = TargetingService.GetCleaveTargets(unit, target, state.units)
		local totalDmg = 0
		local hitCount = 0
		local allOutcomes = {}
		for _, t in ipairs(targets) do
			if t.isAlive then
				local outcome = CombatResolver.ResolveSkill(unit, t, skillDef)
				CombatResolver.ApplyOutcome(outcome, t)
				totalDmg = totalDmg + outcome.finalDamage
				hitCount = hitCount + 1
				table.insert(allOutcomes, { target = t, outcome = outcome })
			end
		end
		result.type      = "AOE"
		result.targets   = allOutcomes
		result.totalDmg  = totalDmg
		result.hitCount  = hitCount
		result.skillName = skillDef.name

		print(string.format(
			"[CommandService] Channel ACTIVATE [%s] AOE | %s | Hits:%d | Dmg:%d | MP:%d",
			skillDef.name, unit.name, hitCount, totalDmg, mpCost
		))

	elseif skillDef.aoePattern and skillDef.aoePattern:sub(1,5) == "Chain" then
		-- Chain AOE: jump from target to target with damage falloff
		local maxTargets = tonumber(skillDef.aoePattern:match("%d+")) or 3
		local chainTargets = TargetingService.GetChainTargets(
			target, state.units, unit.side, maxTargets, 2
		)
		local totalDmg = 0
		local hitCount = 0
		local falloff = 1.0
		local falloffRate = skillDef.chainFalloff or 0.80
		local allOutcomes = {}
		for _, u in ipairs(chainTargets) do
			if u.isAlive then
				local outcome = CombatResolver.ResolveSkill(unit, u, skillDef)
				outcome.finalDamage = math.max(0, math.round(outcome.finalDamage * falloff))
				outcome.isAOE = true
				CombatResolver.ApplyOutcome(outcome, u, unit)
				totalDmg = totalDmg + outcome.finalDamage
				hitCount = hitCount + 1
				table.insert(allOutcomes, { target = u, outcome = outcome })
				falloff = falloff * falloffRate
			end
		end
		result.type      = "AOE"
		result.targets   = allOutcomes
		result.totalDmg  = totalDmg
		result.hitCount  = hitCount
		result.skillName = skillDef.name
		print(string.format(
			"[CommandService] Channel ACTIVATE [%s] Chain(%d/%d) | %s | Hits:%d | Dmg:%d | MP:%d",
			skillDef.name, hitCount, maxTargets, unit.name, hitCount, totalDmg, mpCost
		))

	elseif skillDef.aoePattern and skillDef.aoePattern ~= "Cleave" then
		-- Generic AOE: tile-based pattern resolution
		local aoeTiles = TargetingService.GetAOETargetTiles(
			skillDef.aoePattern, unit,
			target.tileX, target.tileY,
			_mapWidth, _mapHeight
		)
		local totalDmg = 0
		local hitCount = 0
		local allOutcomes = {}
		-- AOE elevation filter: ±2 from center tile (DB default)
		local centerElev = GameConstants.GetElevation(target.tileX, target.tileY)
		-- AOE is indiscriminate by default (DB: friendly fire rule)
		local targetRules = skillDef.targetRules or "Enemy Unit"
		local hitsAllies = targetRules == "Ally Unit, Enemy Unit, Self"
			or targetRules == "Ground, including occupied Ground"
			or (not targetRules:find("Ally") == nil and not targetRules:find("Enemy") == nil)
		for _, tile in ipairs(aoeTiles) do
			local tileElev = GameConstants.GetElevation(tile.tileX, tile.tileY)
			if math.abs(tileElev - centerElev) <= 2 then  -- ±2 elevation limit
			-- BlocksAOE: Center Spread AOE does not pass through BlocksAOE objects
			if not TargetingService.IsAOEBlocked(target.tileX, target.tileY, tile.tileX, tile.tileY) then
			  for _, u in ipairs(state.units) do
				if u.isAlive and u.tileX == tile.tileX and u.tileY == tile.tileY
					and u.id ~= unit.id then  -- never hit self unless targetRules includes Self
					-- Indiscriminate by default: hit both sides
					local outcome = CombatResolver.ResolveSkill(unit, u, skillDef)
					outcome.isAOE = true
					CombatResolver.ApplyOutcome(outcome, u, unit)
					totalDmg = totalDmg + outcome.finalDamage
					hitCount = hitCount + 1
					table.insert(allOutcomes, { target = u, outcome = outcome })
				end
				end
			  end
			end
			end
		result.type      = "AOE"
		result.targets   = allOutcomes
		result.totalDmg  = totalDmg
		result.hitCount  = hitCount
		result.skillName = skillDef.name
		print(string.format(
			"[CommandService] Channel ACTIVATE [%s] AOE(%s) | %s | Hits:%d | Dmg:%d | MP:%d",
			skillDef.name, skillDef.aoePattern, unit.name, hitCount, totalDmg, mpCost
		))

		-- Skill→tile effect bridge (channeling activation)
		if skillDef.createsTileEffect and _tileEffectService then
			local centerElev = GameConstants.GetElevation(target.tileX, target.tileY)
			for _, tile in ipairs(aoeTiles) do
				local tileElev = GameConstants.GetElevation(tile.tileX, tile.tileY)
				if math.abs(tileElev - centerElev) <= 2
					and not TargetingService.IsAOEBlocked(target.tileX, target.tileY, tile.tileX, tile.tileY) then
					_tileEffectService.ApplyTileEffect(
						tile.tileX, tile.tileY, skillDef.createsTileEffect, unit.id
					)
				end
			end
		end

	else
		-- Single target damage
		local outcome = CombatResolver.ResolveSkill(unit, target, skillDef)
		local actualDmg, statusApplied = CombatResolver.ApplyOutcome(outcome, target)
		result.type          = "Damage"
		result.target        = target
		result.damage        = outcome.finalDamage
		result.statusApplied = statusApplied
		result.skillName     = skillDef.name

		print(string.format(
			"[CommandService] Channel ACTIVATE [%s] | %s -> %s | Dmg:%d | MP:%d%s",
			skillDef.name, unit.name, target.name,
			outcome.finalDamage, mpCost,
			statusApplied and (" | +" .. statusApplied) or ""
		))
	end

	return true, result
end

--------------------------------------------------
-- PUBLIC: ValidateAndCommit
--------------------------------------------------

function CommandService.ValidateAndCommit(
	state,
	actorId,
	actionType,
	selection
)
	-- STEP 1: Receive command
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

	-- STEP 2: Turn gate
	if state.phase ~= "TurnOpen" then
		return false, "No turn is open."
	end
	if state.activeUnit ~= actor then
		return false, actor.name .. " is not the active unit."
	end

	-- STEP 3: Action availability
	if not actor.isAlive then
		return false, actor.name .. " is defeated."
	end
	if actionType ~= "Wait" and actor.currentAp <= 0 then
		return false, actor.name .. " has no AP remaining."
	end

	-- STEP 3b: Status-based action blocking (Phase 2)
	-- Silence → blocks Skills, Disarmed → blocks Attack, Pinned → blocks Move,
	-- Sleep/Petrify/KO → blocks All. Guard/Wait never blocked.
	local blocked, blockReason = StatusService.IsActionBlocked(actor, actionType)
	if blocked then
		return false, actor.name .. " cannot " .. actionType .. ": " .. blockReason
	end

	-- STEP 4: Loadout legality (stub)

	-- STEP 5: Selection validation
	local skillDef = nil

	if actionType == "Skill" then
		if type(selection) ~= "table" or not selection.skillId then
			return false, "Skill command requires a selection with skillId."
		end

		skillDef = lookupSkill(selection.skillId)
		if not skillDef then
			return false, "Unknown skill: " .. tostring(selection.skillId)
		end


		local mpCost = skillDef.mpCost or 0
		mpCost = math.max(0, math.round(mpCost * RacePassiveService.GetMpCostModifier(actor)))
		mpCost = math.max(0, math.round(mpCost * DoctrinePassiveService.GetMpCostModifier(actor, actor._docFirstSkillUsed ~= true)))
		mpCost = math.max(0, math.round(mpCost * AugmentEffectService.GetMpCostMultiplier(actor, selection.skillId)))

		-- Mana Burn: Extra MP Cost = round(Max MP × 0.20)
		-- DB: "Extra MP Cost = round(Max MP × 0.20). Total MP Spent = Skill MP Cost + Extra."
		local manaBurnExtra = 0
		if StatusService.HasStatus(actor, "Mana Burn") then
			manaBurnExtra = math.round((actor.maxMp or 20) * 0.20)
			mpCost = mpCost + manaBurnExtra
		end

		if not UnitSchema.HasEnoughMp(actor, mpCost) then
			return false, string.format(
				"%s does not have enough MP (%d/%d needed).",
				actor.name, actor.currentMp, mpCost
			)
		end

		local targetSelection = {
			target      = selection.target,
			-- Compute skill range with bonus (same formula as GetSkillCandidates)
			skillRange  = math.max(1, ((skillDef.range == -1)
				and (actor.weaponMaxRange or 1)
				or (skillDef.range or 1))
				+ (actor.derivedStats and actor.derivedStats.bonusSkillRange
					or math.floor((actor.effectiveStats and actor.effectiveStats.INT or 10) / 75))
			),
			targetRules = skillDef.targetRules or "Enemy Unit",
		}

		local valid, reason = TargetingService.ValidateSelection(
			actor, "Skill", targetSelection,
			state.units, _mapWidth, _mapHeight
		)
		if not valid then return false, reason end
	elseif actionType == "Item" then
		-- Item action: use a consumable from an equipped slot
		if type(selection) ~= "table" or not selection.itemSlotIndex then
			return false, "Item command requires a selection with itemSlotIndex."
		end

		local slotIndex = selection.itemSlotIndex
		local slots = actor.consumableSlots
		if not slots or not slots[slotIndex] then
			return false, "No consumable equipped in slot " .. tostring(slotIndex) .. "."
		end

		local slot = slots[slotIndex]
		if not slot.consumableId or slot.consumableId == "" then
			return false, "Consumable slot " .. tostring(slotIndex) .. " is empty."
		end

		local consumableDef = ConsumableData.Items[slot.consumableId]
		if not consumableDef then
			return false, "Unknown consumable: " .. tostring(slot.consumableId)
		end

		if (slot.currentCharges or 0) <= 0 then
			return false, consumableDef.name .. " has no charges remaining."
		end

		-- Validate target against the consumable's targetRules and range
		local target = selection.target
		local valid, reason = validateItemTarget(actor, target, consumableDef)
		if not valid then return false, reason end

	elseif actionType ~= "Wait" and actionType ~= "Guard" and actionType ~= "Push" then
		-- Move and Attack need target/tile validation
		local valid, reason = TargetingService.ValidateSelection(
			actor, actionType, selection,
			state.units, _mapWidth, _mapHeight
		)
		if not valid then return false, reason end
	end

	-- STEP 6: Cost evaluation
	local apCost = (actionType == "Wait") and 0 or 1
	if apCost > 0 and actor.currentAp < apCost then
		return false, actor.name .. " does not have enough AP."
	end

	-- STEP 7: Snapshot (stub)

	-- STEP 8: Atomic commit
	actor.currentAp = actor.currentAp - apCost

	if actionType == "Move" then
		BattleVisualBroadcaster.ActionAnnounced(actor, "Move")
		local pathCost
		if selection.pathCost ~= nil then
			pathCost = selection.pathCost
		else
			local dx = math.abs(selection.tileX - actor.tileX)
			local dy = math.abs(selection.tileY - actor.tileY)
			pathCost = dx + dy
		end
		local rtCost = calcMoveRt(actor, pathCost)
		BattleCoordinator.AccrueRt(state, rtCost)

		-- Save old position for facing calculation
		local prevTileX, prevTileY = actor.tileX, actor.tileY

		actor.tileX = selection.tileX
		actor.tileY = selection.tileY

		print(string.format(
			"[CommandService] MOVE | %s -> (%d,%d) | RT:%d | AP left:%d",
			actor.name, actor.tileX, actor.tileY,
			rtCost, actor.currentAp
		))

		-- Update facing: face movement direction
		local moveFacing = GameConstants.CalcFacingFrom(prevTileX, prevTileY, actor.tileX, actor.tileY)
		if moveFacing then
			actor.facing = moveFacing
			-- Broadcast so the client's facing indicator follows the walk in real
			-- time (not just the manual Guard/Wait path).
			BattleVisualBroadcaster.FacingChanged(actor)
		end

		-- Terrain cross effects: check destination terrain for cross penalties/effects
		local terrainData = GameConstants.GetTerrainData(actor.tileX, actor.tileY)
		if terrainData then
			-- Apply crossCost as extra RT (terrains like Sand +1, Swamp +2)
			-- Note: base moveCost is already handled by GetTerrainCost in pathfinding.
			-- crossCost is for future terrains not yet on the map.
			if terrainData.crossCost and terrainData.crossCost > 0 then
				local extraRt = math.round(terrainData.crossCost * StatusService.GetModifiedBaseRt(actor) * GameConstants.MOVE_RT_FACTOR)
				BattleCoordinator.AccrueRt(state, extraRt)
			end

			-- Terrain trigger on enter: Deep Water → Drowning, etc.
			if terrainData.triggerEffect == "Drowning" and StatusService then
				StatusService.ApplyStatus(actor, "Drowning", "terrain")
				print(string.format("[CommandService] Terrain trigger: %s enters %s → Drowning",
					actor.name, terrainData.id))
			end
		end

		-- Tile effect cross check (Burning, Poison Cloud, etc.)
		if _tileEffectService then
			_tileEffectService.OnUnitEntersTile(actor, actor.tileX, actor.tileY)
		end

	elseif actionType == "Attack" then
		BattleVisualBroadcaster.ActionAnnounced(actor, "Basic Attack")
		local target = selection
		-- calcBasicAttackBaseRt already includes Effective Weapon WT
		local rtCost = calcBasicAttackBaseRt(actor)

		local weaponDamage = actor.weaponDamage or 10

		-- Weapon pattern AOE resolution
		local weaponPattern = actor.weaponPattern or "Single"
		local totalDmg = 0
		local hitCount = 0

		if weaponPattern == "ImpactSplash" then
			local splashTargets = TargetingService.GetImpactSplashTargets(actor, target, state.units)
			for _, entry in ipairs(splashTargets) do
				if entry.unit.isAlive then
					local outcome = CombatResolver.ResolveBasicAttack(actor, entry.unit, weaponDamage)
					outcome.finalDamage = math.max(0, math.round(outcome.finalDamage * entry.dmgMult))
					if entry.dmgMult < 1.0 then outcome.isAOE = true end
					CombatResolver.ApplyOutcome(outcome, entry.unit, actor)
					totalDmg = totalDmg + outcome.finalDamage
					hitCount = hitCount + 1
				end
			end
		elseif weaponPattern == "Line2" then
			local lineTargets = TargetingService.GetLine2Targets(actor, target, state.units)
			for _, entry in ipairs(lineTargets) do
				if entry.unit.isAlive then
					local outcome = CombatResolver.ResolveBasicAttack(actor, entry.unit, weaponDamage)
					CombatResolver.ApplyOutcome(outcome, entry.unit, actor)
					totalDmg = totalDmg + outcome.finalDamage
					hitCount = hitCount + 1
				end
			end
		elseif weaponPattern == "Cleave" then
			local cleaveTargets = TargetingService.GetCleaveTargets(actor, target, state.units)
			for _, u in ipairs(cleaveTargets) do
				if u.isAlive then
					local outcome = CombatResolver.ResolveBasicAttack(actor, u, weaponDamage)
					if u.id ~= target.id then
						outcome.finalDamage = math.max(0, math.round(outcome.finalDamage * 0.5))
						outcome.isAOE = true
					end
					CombatResolver.ApplyOutcome(outcome, u, actor)
					totalDmg = totalDmg + outcome.finalDamage
					hitCount = hitCount + 1
				end
			end
		elseif weaponPattern == "Adjacent" then
			-- Adjacent: primary + units on both sides of target (perpendicular), 50% splash
			local adjTargets = TargetingService.GetCleaveTargets(actor, target, state.units)
			for _, u in ipairs(adjTargets) do
				if u.isAlive then
					local outcome = CombatResolver.ResolveBasicAttack(actor, u, weaponDamage)
					if u.id ~= target.id then
						outcome.finalDamage = math.max(0, math.round(outcome.finalDamage * 0.5))
						outcome.isAOE = true
					end
					CombatResolver.ApplyOutcome(outcome, u, actor)
					totalDmg = totalDmg + outcome.finalDamage
					hitCount = hitCount + 1
				end
			end
		else
			-- Single-target (default)
			local outcome = CombatResolver.ResolveBasicAttack(actor, target, weaponDamage)
			CombatResolver.ApplyOutcome(outcome, target, actor)
			totalDmg = outcome.finalDamage
			hitCount = 1
			-- Counter-attack: if the struck target holds a CounterStance and the
			-- attacker is within its weapon reach, it ripostes now. isCounter is
			-- false here (this is a normal attack), so the counter is eligible.
			CommandService.TriggerCounterIfEligible(target, actor, state,
				outcome.isCounter, outcome.isAOE)
		end

		BattleCoordinator.AccrueRt(state, rtCost)

		-- Apply Weapon RT Delay to primary target (reduced by target VIT)
		local rawDelay = actor.weaponRtDelay or 0
		if rawDelay > 0 and target.isAlive then
			local targetVit = target.effectiveStats and target.effectiveStats.VIT or 10
			local actualDelay = GameConstants.CalcRtDelayResistance(rawDelay, targetVit)
			target.remainingRt = target.remainingRt + math.max(0, actualDelay)
		end

		-- Giant race tag: melee Basic Attacks gain Knockback (primary target only)
		if target.isAlive and actor.raceId then
			local RaceData = require(game:GetService("ReplicatedStorage"):WaitForChild("Content"):WaitForChild("RaceData"))
			local raceEntry = RaceData.GetRace(actor.raceId)
			if raceEntry and raceEntry.tags then
				for _, tag in ipairs(raceEntry.tags) do
					if tag == "Giant" then
						local force = actor.derivedStats and actor.derivedStats.force or 1
						local direction = DisplacementService.GetPushDirection(actor, target)
						-- Giant basic-attack knockback is MELEE (isRanged=false → no ranged penalty).
						-- ResolvePush computes distance from Force - Stability internally.
						local result = DisplacementService.ResolvePush(
							actor, target, force, direction,
							GameConstants.KNOCKBACK_SOURCE_MODIFIERS.SkillKnockback, state.units,
							nil, false
						)
						if result and result.pushed then
							-- Apply position change
							target.tileX = result.finalTileX
							target.tileY = result.finalTileY
							-- Apply collision/fall damage to the knocked-back target
							local knockDmg = 0
							if result.wallCollision and result.wallCollision.damage > 0 then
								knockDmg = knockDmg + result.wallCollision.damage
							end
							if result.fallDamage and result.fallDamage > 0 then
								knockDmg = knockDmg + result.fallDamage
							end
							if knockDmg > 0 and target.isAlive then
								UnitSchema.ApplyDamage(target, knockDmg)
							end
							-- Ground effect of the landing tile (chasm floors etc.).
							applyForcedEntryEffects(target, result)
							-- Collided unit also absorbs impact (both units take collision damage)
							if result.wallCollision
								and result.wallCollision.collidedUnitId
								and result.wallCollision.collidedUnitDamage
								and result.wallCollision.collidedUnitDamage > 0
							then
								for _, u in ipairs(state.units) do
									if u.id == result.wallCollision.collidedUnitId and u.isAlive then
										UnitSchema.ApplyDamage(u, result.wallCollision.collidedUnitDamage)
										break
									end
								end
							end
							-- Broadcast the displacement so the client animates it
							BattleVisualBroadcaster.UnitPushed(actor, target, result)
							print(string.format(
								"[CommandService] GIANT KNOCKBACK | %s -> %s | Moved:%d to (%d,%d) | Dmg:%d",
								actor.name, target.name, result.tilesDisplaced,
								result.finalTileX, result.finalTileY, knockDmg
							))
						end
						break
					end
				end
			end
		end

		print(string.format(
			"[CommandService] ATTACK %s | %s -> %s | Dmg:%d Hits:%d | RT:%d | AP left:%d",
			weaponPattern ~= "Single" and ("["..weaponPattern.."]") or "",
			actor.name, target.name,
			totalDmg, hitCount, rtCost, actor.currentAp
		))

		-- Update facing: face toward attack target
		local atkFacing = GameConstants.CalcFacingFrom(actor.tileX, actor.tileY, target.tileX, target.tileY)
		if atkFacing then
			actor.facing = atkFacing
			BattleVisualBroadcaster.FacingChanged(actor)
		end

		-- Hide dispel: offensive action breaks Hide
		if StatusService.HasStatus(actor, "Hide") then
			StatusService.RemoveStatus(actor, "Hide")
			print(string.format("[CommandService] %s Hide dispelled (basic attack)", actor.name))
		end

	elseif actionType == "Skill" then
		BattleVisualBroadcaster.ActionAnnounced(actor, (skillDef and skillDef.name) or "Skill")
		local target = selection.target
		local mpCost = skillDef.mpCost or 0
		mpCost = math.max(0, math.round(mpCost * RacePassiveService.GetMpCostModifier(actor)))
		mpCost = math.max(0, math.round(mpCost * DoctrinePassiveService.GetMpCostModifier(actor, actor._docFirstSkillUsed ~= true)))

		-- Mana Burn: Extra MP Cost (same as validation path)
		local manaBurnExtra = 0
		if StatusService.HasStatus(actor, "Mana Burn") then
			manaBurnExtra = math.round((actor.maxMp or 20) * 0.20)
			mpCost = mpCost + manaBurnExtra
		end

		-- Check if this is a CHANNELED skill
		if skillDef.channelTime and skillDef.channelTime > 0 then
			-- CHANNELED SKILL: don't spend MP, don't resolve.
			-- Set up channeling state, end turn with channel RT.
			local dex = actor.effectiveStats and actor.effectiveStats.DEX or 10
			local channelRt = GameConstants.CalcChannelTime(skillDef.channelTime, dex)

			BattleCoordinator.StartChanneling(state, actor, {
				skillDef  = skillDef,
				target    = target,
				mpCost    = mpCost,
				channelRt = channelRt,
			})
			-- Start the looping channel VFX on the caster (damage vs heal picks the asset).
			BattleVisualBroadcaster.ChannelStarted(actor, skillDef.isHealing == true)

			-- TWO-TIMER MODEL: the caster ends its turn NORMALLY (base + this skill's RT
			-- cost), so it keeps a real, independent RT. The channel deadline
			-- (channelResolveCt) was set in StartChanneling and ticks separately on the
			-- global clock. Compute the skill RT cost with the SAME formula as the
			-- non-channel skill path, accrue it, then end the turn normally.
			local chBaseRtCost
			if skillDef.rtMult then
				-- Skill RT = round(Effective WEAPON WT x mult) (skills.RT_Cost_Formula); armor WT lives in Modified Base RT.
				chBaseRtCost = math.round(GameConstants.CalcEffectiveWt((actor.weaponWt or 10), (actor.effectiveStats or {}).STR or 10) * skillDef.rtMult)
			else
				chBaseRtCost = skillDef.rtCost or math.round(StatusService.GetModifiedBaseRt(actor) * 0.10)
			end
			chBaseRtCost = math.round(chBaseRtCost * StatusService.GetAllRtMultiplier(actor))
			actor.currentAp = 0
			BattleCoordinator.AccrueRt(state, chBaseRtCost)
			BattleCoordinator.EndTurn(state)

			print(string.format(
				"[CommandService] SKILL COMMIT (CHANNEL) [%s] | %s -> %s | Channel RT:%d | MP reserved:%d",
				skillDef.name or skillDef.id,
				actor.name, target.name,
				channelRt, mpCost
			))

			return true, nil -- Turn already ended normally (two-timer model); channel resolves at its deadline
		end

		-- INSTANT SKILL: spend MP and resolve immediately
		UnitSchema.SpendMp(actor, mpCost)

		-- Mana Burn damage: round(Total MP Spent × 0.50 × Debuff Resistance)
		if manaBurnExtra > 0 and actor.isAlive then
			local debuffResist = actor.derivedStats and actor.derivedStats.debuffResist or 1.0
			local manaBurnDmg = math.round(mpCost * 0.50 * debuffResist)
			if manaBurnDmg > 0 then
				UnitSchema.ApplyDamage(actor, manaBurnDmg)
				print(string.format("[CommandService] Mana Burn: %s takes %d damage (MP spent: %d)",
					actor.name, manaBurnDmg, mpCost))
			end
		end

		-- Skill RT cost: rtMult × Effective Weapon WT (from DB formula)
		-- Fallback: rtCost (legacy) or baseRt × 0.10
		local baseRtCost
		if skillDef.rtMult then
			-- Skill RT = round(Effective WEAPON WT x mult) (skills.RT_Cost_Formula); armor WT lives in Modified Base RT.
			baseRtCost = math.round(GameConstants.CalcEffectiveWt((actor.weaponWt or 10), (actor.effectiveStats or {}).STR or 10) * skillDef.rtMult)
		else
			baseRtCost = skillDef.rtCost or math.round(StatusService.GetModifiedBaseRt(actor) * 0.10)
		end
		-- Frozen: all RT costs ×2
		baseRtCost = math.round(baseRtCost * StatusService.GetAllRtMultiplier(actor))

		if skillDef.isHealing then
			local outcome = CombatResolver.ResolveHealing(actor, target, skillDef)
			CombatResolver.ApplyOutcome(outcome, target, actor)
			BattleCoordinator.AccrueRt(state, baseRtCost)

			print(string.format(
				"[CommandService] SKILL [%s] | %s -> %s | Heal:%d | MP:%d | RT:%d | AP left:%d",
				skillDef.name or skillDef.id,
				actor.name, target.name,
				outcome.finalHealing, mpCost, baseRtCost, actor.currentAp
			))

		elseif skillDef.aoePattern == "Cleave" then
			local targets = TargetingService.GetCleaveTargets(
				actor, target, state.units
			)
			local totalDmg = 0
			local hitCount = 0
			for _, t in ipairs(targets) do
				if t.isAlive then
					local outcome = CombatResolver.ResolveSkill(actor, t, skillDef)
					CombatResolver.ApplyOutcome(outcome, t, actor)
					totalDmg = totalDmg + outcome.finalDamage
					hitCount = hitCount + 1
				end
			end
			BattleCoordinator.AccrueRt(state, baseRtCost)

			print(string.format(
				"[CommandService] SKILL [%s] AOE | %s | Hits:%d | TotalDmg:%d | MP:%d | RT:%d | AP left:%d",
				skillDef.name or skillDef.id,
				actor.name, hitCount, totalDmg, mpCost, baseRtCost, actor.currentAp
			))

		elseif skillDef.aoePattern and skillDef.aoePattern:sub(1,5) == "Chain" then
			-- Chain AOE: jump from target to target with damage falloff
			local maxTargets = tonumber(skillDef.aoePattern:match("%d+")) or 3
			local chainTargets = TargetingService.GetChainTargets(
				target, state.units, actor.side, maxTargets, 2
			)
			local totalDmg = 0
			local hitCount = 0
			local falloff = 1.0
			local falloffRate = skillDef.chainFalloff or 0.80
			for idx, u in ipairs(chainTargets) do
				if u.isAlive then
					local outcome = CombatResolver.ResolveSkill(actor, u, skillDef)
					-- Apply chain falloff
					outcome.finalDamage = math.max(0, math.round(outcome.finalDamage * falloff))
					outcome.isAOE = true
					CombatResolver.ApplyOutcome(outcome, u, actor)
					totalDmg = totalDmg + outcome.finalDamage
					hitCount = hitCount + 1
					falloff = falloff * falloffRate
				end
			end
			BattleCoordinator.AccrueRt(state, baseRtCost)

			print(string.format(
				"[CommandService] SKILL [%s] Chain(%d/%d) | %s | Hits:%d | TotalDmg:%d | MP:%d | RT:%d | AP left:%d",
				skillDef.name or skillDef.id, hitCount, maxTargets,
				actor.name, hitCount, totalDmg, mpCost, baseRtCost, actor.currentAp
			))

		elseif skillDef.aoePattern and skillDef.aoePattern ~= "Cleave" and skillDef.aoePattern ~= "InheritWeapon" then
			-- Generic AOE: tile-based pattern resolution
			local aoeTiles = TargetingService.GetAOETargetTiles(
				skillDef.aoePattern, actor,
				target.tileX, target.tileY,
				_mapWidth, _mapHeight
			)
			local totalDmg = 0
			local hitCount = 0
			-- AOE elevation filter: ±2 from center tile (DB default)
			local centerElev = GameConstants.GetElevation(target.tileX, target.tileY)
			for _, tile in ipairs(aoeTiles) do
				local tileElev = GameConstants.GetElevation(tile.tileX, tile.tileY)
				if math.abs(tileElev - centerElev) <= 2 then
				-- BlocksAOE: Center Spread AOE does not pass through BlocksAOE
				if not TargetingService.IsAOEBlocked(target.tileX, target.tileY, tile.tileX, tile.tileY) then
				for _, u in ipairs(state.units) do
					if u.isAlive and u.tileX == tile.tileX and u.tileY == tile.tileY
						and u.id ~= actor.id then
						local outcome = CombatResolver.ResolveSkill(actor, u, skillDef)
						outcome.isAOE = true
						CombatResolver.ApplyOutcome(outcome, u, actor)
						totalDmg = totalDmg + outcome.finalDamage
						hitCount = hitCount + 1
					end
				end
				end
			end
			end  -- tile loop (for aoeTiles)
			BattleCoordinator.AccrueRt(state, baseRtCost)

			print(string.format(
				"[CommandService] SKILL [%s] AOE(%s) | %s | Hits:%d | TotalDmg:%d | MP:%d | RT:%d | AP left:%d",
				skillDef.name or skillDef.id, skillDef.aoePattern,
				actor.name, hitCount, totalDmg, mpCost, baseRtCost, actor.currentAp
			))

			-- Skill→tile effect bridge: create tile effects on AOE tiles
			if skillDef.createsTileEffect and _tileEffectService then
				for _, tile in ipairs(aoeTiles) do
					local tileElev = GameConstants.GetElevation(tile.tileX, tile.tileY)
					if math.abs(tileElev - centerElev) <= 2
						and not TargetingService.IsAOEBlocked(target.tileX, target.tileY, tile.tileX, tile.tileY) then
						_tileEffectService.ApplyTileEffect(
							tile.tileX, tile.tileY, skillDef.createsTileEffect, actor.id
						)
					end
				end
			end

		else
			-- Check for "Inherit Weapon Pattern" skills
			local inheritedPattern = nil
			if skillDef.aoePattern == "InheritWeapon" then
				inheritedPattern = actor.weaponPattern or "Single"
			end

			if inheritedPattern and inheritedPattern ~= "Single" then
				-- Weapon pattern AOE via inherited skill
				local totalDmg = 0
				local hitCount = 0
				local aoeTargets

				if inheritedPattern == "ImpactSplash" then
					aoeTargets = TargetingService.GetImpactSplashTargets(actor, target, state.units)
				elseif inheritedPattern == "Line2" then
					aoeTargets = TargetingService.GetLine2Targets(actor, target, state.units)
				elseif inheritedPattern == "Cleave" then
					-- Re-use Cleave with 50% secondary
					local cleaveUnits = TargetingService.GetCleaveTargets(actor, target, state.units)
					aoeTargets = {}
					for _, u in ipairs(cleaveUnits) do
						local mult = (u.id == target.id) and 1.0 or 0.5
						table.insert(aoeTargets, { unit = u, dmgMult = mult })
					end
				elseif inheritedPattern == "Adjacent" then
					local adjUnits = TargetingService.GetCleaveTargets(actor, target, state.units)
					aoeTargets = {}
					for _, u in ipairs(adjUnits) do
						local mult = (u.id == target.id) and 1.0 or 0.5
						table.insert(aoeTargets, { unit = u, dmgMult = mult })
					end
				end

				if aoeTargets then
					for _, entry in ipairs(aoeTargets) do
						if entry.unit.isAlive then
							local outcome = CombatResolver.ResolveSkill(actor, entry.unit, skillDef)
							outcome.finalDamage = math.max(0, math.round(outcome.finalDamage * entry.dmgMult))
							if entry.dmgMult < 1.0 then outcome.isAOE = true end
							CombatResolver.ApplyOutcome(outcome, entry.unit, actor)
							totalDmg = totalDmg + outcome.finalDamage
							hitCount = hitCount + 1
						end
					end
				end
				BattleCoordinator.AccrueRt(state, baseRtCost)

				print(string.format(
					"[CommandService] SKILL [%s] Inherit[%s] | %s | Hits:%d | TotalDmg:%d | MP:%d | RT:%d | AP left:%d",
					skillDef.name or skillDef.id, inheritedPattern,
					actor.name, hitCount, totalDmg, mpCost, baseRtCost, actor.currentAp
				))

			elseif (skillDef.targetRules == "Self")
				or (target and target.id and target.id == actor.id) then
			-- SELF-TARGET buff (Battle Fury, Vanishing Step, Guard-stance skills, etc.).
			-- These carry power=1.0 in data but their intent is the status, NOT damage.
			-- Previously they fell into the single-target branch below and ran
			-- ResolveSkill(actor, actor) — dealing weapon damage to the CASTER
			-- (observed: Vanishing Step -> self Dmg:24, Battle Fury -> self Dmg:18).
			-- Apply the authored self-status (if any) and spend RT; deal no damage.
			-- Supports both a single appliesStatus and a list appliesStatuses
			-- (multi-status self-buffs like Battle Fury: Frenzy + Rush).
			if skillDef.appliesStatus then
				StatusService.ApplyStatus(actor, skillDef.appliesStatus, actor.id)
			end
			if skillDef.appliesStatuses then
				for _, sid in ipairs(skillDef.appliesStatuses) do
					StatusService.ApplyStatus(actor, sid, actor.id)
				end
			end
			BattleCoordinator.AccrueRt(state, baseRtCost)
			-- Part B: stance-style self-buffs (e.g. Riposte Stance) apply NO real
			-- status, so nothing would show. Emit a CLIENT-ONLY pill named after the
			-- skill, carrying the skill's own icon (via sourceIcon), so the active
			-- stance is visible. Clears naturally on the unit's next turn summary.
			if not skillDef.appliesStatus and not skillDef.appliesStatuses then
				local _sd = SkillData[skillDef.id or ""]
				local _icon = _sd and _sd.icon or nil
				-- Carry the skill's own description + duration so the detailed inspector
				-- can show real buff info (the synthetic pill id is not in STATUSES).
				local _desc = _sd and _sd.description or nil
				local _dur  = _sd and _sd.duration or nil
				BattleVisualBroadcaster.StatusApplied(actor, skillDef.name or "Stance", nil, _icon, _desc, _dur)
			end
			print(string.format(
				"[CommandService] SKILL [%s] SELF | %s | Status:%s | MP:%d | RT:%d | AP left:%d",
				skillDef.name or skillDef.id, actor.name,
				skillDef.appliesStatus or "none", mpCost, baseRtCost, actor.currentAp
			))

			elseif target and target.side == actor.side and target.id ~= actor.id
				and (skillDef.power or 0) == 0
				and (skillDef.appliesStatus or skillDef.appliesStatuses) then
			-- ALLY-TARGET buff (Benediction, Invigorate, Arcane Renewal, etc.).
			-- Target is a friendly unit that is NOT the caster, the skill deals no
			-- damage (power 0), and its intent is the authored buff status(es).
			-- Without this branch these skills fall into the single-target damage
			-- path below and run ResolveSkill(actor, ally) — DAMAGING the ally they
			-- are meant to help. Apply the status(es) to the ally, spend RT, no damage.
			-- Supports both a single appliesStatus and a list appliesStatuses.
			if skillDef.appliesStatus then
				StatusService.ApplyStatus(target, skillDef.appliesStatus, actor.id)
			end
			if skillDef.appliesStatuses then
				for _, sid in ipairs(skillDef.appliesStatuses) do
					StatusService.ApplyStatus(target, sid, actor.id)
				end
			end
			BattleCoordinator.AccrueRt(state, baseRtCost)
			-- Reflect the buff on the client (status pills / bars).
			if BattleVisualBroadcaster.UnitStateChanged then
				BattleVisualBroadcaster.UnitStateChanged(target)
			end
			print(string.format(
				"[CommandService] SKILL [%s] ALLY-BUFF | %s -> %s | Status:%s | MP:%d | RT:%d | AP left:%d",
				skillDef.name or skillDef.id, actor.name, target.name,
				skillDef.appliesStatus or (skillDef.appliesStatuses and table.concat(skillDef.appliesStatuses, "+")) or "none",
				mpCost, baseRtCost, actor.currentAp
			))

			elseif (target and target.isGroundTarget)
				or (skillDef.targetRules == "Empty Tile")
				or (skillDef.targetRules == "Ground")
				or (skillDef.targetRules == "Enemy or Ground") then
			-- GROUND/TILE-TARGET skill (Poison Trap, zone placements). The target is a
			-- stat-less marker { tileX, tileY, isGroundTarget=true }. It must NOT go
			-- through ResolveSkill (reads target.effectiveStats.VIT → crash). Create
			-- the authored tile effect if one exists, spend RT, deal no direct damage.
			-- NOTE: a skill with createsTileEffect==nil (e.g. Poison Trap today) places
			-- nothing until that tile-effect content is wired — data/Designer gap.
			if skillDef.createsTileEffect and _tileEffectService and target and target.tileX then
				_tileEffectService.ApplyTileEffect(
					target.tileX, target.tileY, skillDef.createsTileEffect, actor.id
				)
			end
			BattleCoordinator.AccrueRt(state, baseRtCost)
			print(string.format(
				"[CommandService] SKILL [%s] GROUND (%s) | %s | tile:(%s,%s) | MP:%d | RT:%d | AP left:%d",
				skillDef.name or skillDef.id, skillDef.createsTileEffect or "no-effect",
				actor.name, tostring(target and target.tileX), tostring(target and target.tileY),
				mpCost, baseRtCost, actor.currentAp
			))

			else
			-- Single-target (default)

			-- CHARGE SKILL: reposition actor adjacent to target before damage.
			-- Uses the SHARED landing function so the actual move matches the tile
			-- previewed in the turn prompt exactly (one source of truth).
			if skillDef.isCharge and target.isAlive then
				local bestTile = CommandService.ComputeChargeLanding(actor, target, state)
				if bestTile then
					print(string.format("[CommandService] CHARGE | %s moved (%d,%d)->(%d,%d) adjacent to %s",
						actor.name, actor.tileX, actor.tileY, bestTile.x, bestTile.y, target.name))
					actor.tileX = bestTile.x
					actor.tileY = bestTile.y
					BattleVisualBroadcaster.UnitMoved(actor)
				end
			end

			local outcome = CombatResolver.ResolveSkill(actor, target, skillDef)
			local actualDmg, statusApplied = CombatResolver.ApplyOutcome(outcome, target, actor)
			BattleCoordinator.AccrueRt(state, baseRtCost)
			-- Counter-attack: a single-target attacking skill can also provoke a
			-- riposte from a CounterStance holder in weapon reach. Healing/buff
			-- skills deal no damage to enemies so this only fires on real hits.
			CommandService.TriggerCounterIfEligible(target, actor, state,
				outcome.isCounter, outcome.isAOE)

			local rawDelay = actor.weaponRtDelay or 0
			if rawDelay > 0 and target.isAlive then
				local targetVit = target.effectiveStats and target.effectiveStats.VIT or 10
				local actualDelay = GameConstants.CalcRtDelayResistance(rawDelay, targetVit)
				target.remainingRt = target.remainingRt + math.max(0, actualDelay)
			end

			print(string.format(
				"[CommandService] SKILL [%s] | %s -> %s | Dmg:%d | MP:%d | RT:%d | AP left:%d%s",
				skillDef.name or skillDef.id,
				actor.name, target.name,
				outcome.finalDamage, mpCost, baseRtCost, actor.currentAp,
				statusApplied and (" | +" .. statusApplied) or ""
			))
			end
		end

		-- CHARGE SELF-COST: lose 10% current HP after damage (min 1 HP remaining)
		if skillDef.isCharge and actor.isAlive then
			local selfCost = math.max(1, math.floor(actor.currentHp * 0.10))
			actor.currentHp = math.max(1, actor.currentHp - selfCost)
			print(string.format(
				"[CommandService] CHARGE SELF-COST | %s lost %d HP (10%%) | HP: %d/%d",
				actor.name, selfCost, actor.currentHp, actor.maxHp or 0))
		end

		-- Update facing: face toward skill target (unit-targeted skills only)
		if target and target.tileX and not skillDef.isSelfTarget then
			local skillFacing = GameConstants.CalcFacingFrom(actor.tileX, actor.tileY, target.tileX, target.tileY)
			if skillFacing then
				actor.facing = skillFacing
				BattleVisualBroadcaster.FacingChanged(actor)
			end
		end

		-- Hide dispel: offensive skill breaks Hide (non-healing only)
		if not skillDef.isHealing and StatusService.HasStatus(actor, "Hide") then
			StatusService.RemoveStatus(actor, "Hide")
			print(string.format("[CommandService] %s Hide dispelled (offensive skill)", actor.name))
		end

	elseif actionType == "Wait" then
		print(string.format("[CommandService] WAIT | %s", actor.name))
		BattleCoordinator.EndTurn(state)
		return true, nil

	elseif actionType == "Guard" then
		-- Guard: 1 AP, once per turn, enters Guard stance
		if actor.guardUsedThisTurn then
			return false, "Guard already used this turn"
		end

		-- Calculate Guard RT
		-- Guard RT = round(Modified Base RT × 0.10) + 50% of Effective Armor Off-Hand WT
		local modBaseRt = StatusService.GetModifiedBaseRt(actor)
		local offHandWt = 0
		if actor.weaponHandClass ~= "2H" then
			-- Get off-hand WT (if a shield/off-hand is equipped)
			if actor.equipmentSlots and actor.equipmentSlots.OffHand then
				local offHandItem = actor.equipmentSlots.OffHand
				offHandWt = offHandItem.scaledWt or offHandItem.wt or 0
			end
		end
		local guardRt = math.round(modBaseRt * GameConstants.GUARD_RT_BASE_FACTOR)
			+ math.round(offHandWt * GameConstants.GUARD_OFFHAND_WT_FACTOR)
		-- Frozen: all RT costs ×2
		guardRt = math.round(guardRt * StatusService.GetAllRtMultiplier(actor))

		-- Apply Guard as a proper status (dispellable buff, removed by CC)
		StatusService.ApplyStatus(actor, "Guard", actor.id)
		actor.guardBonus = RacePassiveService.GetGuardMitigationBonus(actor)
		local armorGuardBonus = ArmorPassiveService.GetGuardMitigationBonus(actor)
		actor.guardUsedThisTurn = true
		BattleCoordinator.AccrueRt(state, guardRt)

		print(string.format(
			"[CommandService] GUARD | %s | RT:%d | OffHandWT:%d | AP left:%d",
			actor.name, guardRt, offHandWt, actor.currentAp
		))

		-- Calculate effective mitigation for display
		local mitigation = GameConstants.GUARD_MITIGATION + (actor.guardBonus or 0) + armorGuardBonus
		mitigation = math.min(mitigation, GameConstants.GUARD_CAP)
		BattleVisualBroadcaster.ActionAnnounced(actor, "Guard")
		BattleVisualBroadcaster.GuardActivated(actor, guardRt, mitigation)

	elseif actionType == "Push" then
		-- Push: 1 AP, push adjacent target away (allies/neutrals/objects pushable).
		-- selection = target unit (AI/legacy) OR { target = unit, pushDistance = N } (player).
		local target = selection
		local requestedDistance = nil
		if type(selection) == "table" and selection.target then
			target = selection.target
			requestedDistance = selection.pushDistance
		end
		if not target or not target.isAlive then
			return false, "Push target is invalid or defeated."
		end

		-- Android override: Pull with extended range, cannot target adjacent
		local pushOverride = RacePassiveService.GetPushOverride(actor)
		local maxPushDist = pushOverride and pushOverride.maxDistance or 1
		local minPushDist = pushOverride and pushOverride.minDistance or 1

		local dist = math.max(
			math.abs(actor.tileX - target.tileX),
			math.abs(actor.tileY - target.tileY)
		)
		if dist > maxPushDist then
			return false, "Target is out of range."
		end
		if dist < minPushDist then
			return false, "Target is too close."
		end
		BattleVisualBroadcaster.ActionAnnounced(actor, "Push")

		-- Push RT = round(Modified Base RT × 0.10)
		local modBaseRt = StatusService.GetModifiedBaseRt(actor)
		local pushRt = math.round(modBaseRt * GameConstants.GUARD_RT_BASE_FACTOR)
		-- Frozen: all RT costs ×2
		pushRt = math.round(pushRt * StatusService.GetAllRtMultiplier(actor))
		BattleCoordinator.AccrueRt(state, pushRt)

		-- Resolve displacement
		local force = 1
		if actor.derivedStats and actor.derivedStats.force then
			force = actor.derivedStats.force
		end
		if pushOverride and pushOverride.forceBonus then
			force = force + pushOverride.forceBonus
		end
		local direction = DisplacementService.GetPushDirection(actor, target)
		if pushOverride and pushOverride.reverseDirection then
			direction = { x = -direction.x, y = -direction.y }
		end
		local result = DisplacementService.ResolvePush(
			actor, target, force, direction,
			GameConstants.KNOCKBACK_SOURCE_MODIFIERS.GlobalPush,
			state.units, requestedDistance
		)

		-- Apply position change
		target.tileX = result.finalTileX
		target.tileY = result.finalTileY

		-- Apply collision/fall damage
		local totalPushDmg = 0
		if result.wallCollision and result.wallCollision.damage > 0 then
			totalPushDmg = totalPushDmg + result.wallCollision.damage
		end
		if result.fallDamage and result.fallDamage > 0 then
			totalPushDmg = totalPushDmg + result.fallDamage
		end
		if totalPushDmg > 0 then
			UnitSchema.ApplyDamage(target, totalPushDmg)
		end
		-- Ground effect of the landing tile (chasm floors etc.; map_gen_rules row 65).
		applyForcedEntryEffects(target, result)

		-- Apply collision damage to the collided unit (both units absorb the impact)
		if result.wallCollision
			and result.wallCollision.collidedUnitId
			and result.wallCollision.collidedUnitDamage
			and result.wallCollision.collidedUnitDamage > 0
		then
			for _, u in ipairs(state.units) do
				if u.id == result.wallCollision.collidedUnitId and u.isAlive then
					UnitSchema.ApplyDamage(u, result.wallCollision.collidedUnitDamage)
					print(string.format(
						"[CommandService] COLLISION | %s also takes %d damage from impact",
						u.name, result.wallCollision.collidedUnitDamage
					))
					break
				end
			end
		end

		-- Broadcast
		BattleVisualBroadcaster.UnitPushed(actor, target, result)

		local actionLabel = pushOverride and pushOverride.label or "PUSH"
		print(string.format(
			"[CommandService] %s | %s -> %s | Force:%d | Moved:%d to (%d,%d) | Dmg:%d | RT:%d | AP left:%d",
			actionLabel, actor.name, target.name, force,
			result.tilesDisplaced, result.finalTileX, result.finalTileY,
			totalPushDmg, pushRt, actor.currentAp
		))

	elseif actionType == "Item" then
		-- ITEM ACTION: use a consumable from the unit's equipped slot.
		-- Validation already confirmed slot, charges, target, and range.
		local slotIndex    = selection.itemSlotIndex
		local target       = selection.target
		local slot         = actor.consumableSlots[slotIndex]
		local consumableDef = ConsumableData.Items[slot.consumableId]
		BattleVisualBroadcaster.ActionAnnounced(actor, (consumableDef and consumableDef.name) or "Item")

		-- Deduct 1 charge (item stays equipped at 0 charges but is unusable)
		slot.currentCharges = slot.currentCharges - 1

		-- RT cost comes from the consumable definition (fixed, not weapon-scaled)
		local rtCost = consumableDef.rtCost or 80
		-- Frozen: all RT costs ×2
		rtCost = math.round(rtCost * StatusService.GetAllRtMultiplier(actor))
		BattleCoordinator.AccrueRt(state, rtCost)

		-- Resolve the consumable's effect
		local effectResult = resolveItemEffect(actor, target, consumableDef, state.units)

		-- Broadcast via dedicated ItemUsed event (client renders item feedback)
		if BattleVisualBroadcaster.ItemUsed then
			BattleVisualBroadcaster.ItemUsed(actor, target, consumableDef.name, effectResult)
		end

		print(string.format(
			"[CommandService] ITEM [%s] | %s -> %s | Effect:%s | Amount:%d | RT:%d | Charges:%d/%d | AP left:%d",
			consumableDef.name,
			actor.name,
			target and target.name or "ground",
			effectResult.effectType,
			effectResult.amount or 0,
			rtCost,
			slot.currentCharges,
			slot.maxCharges or consumableDef.maxCharges or 0,
			actor.currentAp
		))

	end  -- end if/elseif action chain

	-- STEP 9: Handoff
	if actor.currentAp <= 0 then
		BattleCoordinator.EndTurn(state)
	end

	return true, nil
end

return CommandService
