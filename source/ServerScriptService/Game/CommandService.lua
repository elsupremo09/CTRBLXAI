--!strict
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
local TraitEffectService  = require(script.Parent.TraitEffectService) -- Perks & Flaws Phase 2
local DoctrinePassiveService = require(script.Parent.DoctrinePassiveService)
local ArmorPassiveService = require(script.Parent.ArmorPassiveService)
local AugmentEffectService = require(script.Parent.AugmentEffectService)
local ObjectEffectService = require(script.Parent.ObjectEffectService)

local ConsumableData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("ConsumableData")
)

-- ObjectData: map-object archetypes. Interact's map-object branch reads
-- `activation` (Interact (Free) vs Interact (Consumes Action)) + optional
-- per-object RT override. Object EFFECTS are PARKED to Slice 5.
local ObjectData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("ObjectData")
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
	-- Forward the same live TileEffectService to the map-object effect dispatcher.
	ObjectEffectService.SetTileEffectService(tes)
end

-- SUMMON SPAWNER (injected by Main, mirrors SetTileEffectService). Injection keeps
-- CommandService free of a hard require on EnemyGenerator (cycle-free, same pattern
-- as _tileEffectService / _eventNpcResolver). nil-safe: with no generator wired a
-- summon skill charges its cost and no-ops (logged), never crashes.
local _enemyGenerator = nil
function CommandService.SetEnemyGenerator(eg)
	_enemyGenerator = eg
end

--------------------------------------------------
-- SUMMON SKILL ROUTING (2026-10-06)
--------------------------------------------------
-- Six skills create a summoned unit on an Empty Tile instead of dealing damage:
--   Non-channeled (resolve in ValidateAndCommit Empty-Tile branch):
--     DOC-CONJURER-01 Sentinel, DOC-CONJURER-02 Wisp, DOC-CONJURER-03 Mender
--   Channeled (resolve in ActivateChanneledSkill):
--     SKL-SUMMON-DECOY, SKL-SUMMON-TURRET, SKL-SUMMON-WARD-TOTEM
-- All numbers below are AUTHORED (SkillData / CTRBLXAI.db skills.Power_Formula).
-- Nothing here is invented. Each profile is the caster-% recipe for one summon;
-- the concrete stats are computed from the live caster at cast time (snapshot).
-- hpPct / statPct are fractions of the caster's Max HP / effective stat. "statSrc"
-- names which CASTER stat each summon stat derives from (Sentinel STR<-caster INT,
-- authored quirk). range = {min,max} Basic Attack reach. proj = projectile type.
local SUMMON_PROFILES = {
	["DOC-CONJURER-01"] = {  -- Conjure Sentinel: durable melee
		type = "Sentinel", displayName = "Sentinel", profile = "melee",
		hpPct = 0.60,
		statPct = { STR = 0.60, AGI = 0.50, INT = 0.25, VIT = 0.60, DEX = 0.50, LUK = 0.25 },
		statSrc = { STR = "INT" },  -- authored: Sentinel STR = 60% of caster INT
		range = { 1, 1 }, proj = nil, canMove = true, isFlying = false,
	},
	["DOC-CONJURER-02"] = {  -- Conjure Wisp: flying electric ranged
		type = "Wisp", displayName = "Wisp", profile = "ranged",
		hpPct = 0.35,
		statPct = { STR = 0.20, AGI = 0.75, INT = 0.75, VIT = 0.25, DEX = 0.60, LUK = 0.50 },
		range = { 2, 4 }, proj = "Direct", canMove = true, isFlying = true,
	},
	["DOC-CONJURER-03"] = {  -- Conjure Mender: auto-healer
		type = "Mender", displayName = "Mender", profile = "healer",
		hpPct = 0.45,
		statPct = { STR = 0.20, AGI = 0.40, INT = 0.70, VIT = 0.50, DEX = 0.50, LUK = 0.40 },
		range = { 1, 3 }, proj = nil, canMove = true, isFlying = false,
		-- Mender heals via its own authored action (Range 3, 1 AP, RT 80, no MP).
		skillIds = { "SKL-MENDER-HEAL" },
	},
	["SKL-SUMMON-DECOY"] = {  -- fragile aggro magnet; inherits no stats
		type = "Decoy", displayName = "Decoy", profile = "idle",
		fixedHp = 1, inheritsNoStats = true,
		range = { 1, 1 }, proj = nil, canMove = false, isFlying = false,
	},
	["SKL-SUMMON-TURRET"] = {  -- immobile auto-firer; snapshots caster Weapon Atk Power x0.50
		type = "Turret", displayName = "Turret", profile = "turret",
		hpPct = 0.25, turretDamagePct = 0.50,
		range = { 1, 4 }, proj = "Direct", canMove = false, isFlying = false,
	},
	["SKL-SUMMON-WARD-TOTEM"] = {  -- passive debuff-resist aura; does not act
		type = "WardTotem", displayName = "Ward Totem", profile = "idle",
		hpPct = 0.20,
		auraSpec = { radius = 2, debuffResistMult = 0.80 },
		range = { 1, 1 }, proj = nil, canMove = false, isFlying = false,
	},
}

-- Find an empty, in-bounds, unoccupied tile as close to the caster as possible
-- (expanding Chebyshev rings). Mirrors the Summon Runtime Engine "Validate
-- placement" step (status_summon_engines): tile must be legal + unoccupied.
local function findEmptySummonTile(actor, state)
	local occupied = {}
	for _, u in ipairs(state.units) do
		if u.isAlive ~= false then
			occupied[(u.tileX or 0) .. "," .. (u.tileY or 0)] = true
		end
	end
	local cx, cy = actor.tileX or 1, actor.tileY or 1
	for radius = 1, math.max(_mapWidth, _mapHeight) do
		for dx = -radius, radius do
			for dy = -radius, radius do
				if math.max(math.abs(dx), math.abs(dy)) == radius then
					local x, y = cx + dx, cy + dy
					if x >= 1 and x <= _mapWidth and y >= 1 and y <= _mapHeight
						and not occupied[x .. "," .. y] then
						return x, y
					end
				end
			end
		end
	end
	return nil
end

-- Resolve a summon skill: compute the authored caster-% stats, place on an empty
-- tile on the CASTER's side, enforce one-per-caster-per-type (replace previous),
-- spawn via the existing EnemyGenerator.SpawnSummon, broadcast UnitSpawned. Deals
-- NO damage and grants NO rewards (flags set inside SpawnSummon). Returns ok, info.
-- Per status_summon_engines: create the NEW summon FIRST, then retire the previous
-- one (never delete-before-create); if placement fails, the existing summon stays.
local function spawnSummonFor(actor, skillDef, target, state)
	local prof = SUMMON_PROFILES[skillDef.id]
	if not prof then
		warn(string.format("[CommandService] SUMMON [%s] has no authored profile — spawn aborted (no invented stats)", tostring(skillDef.id)))
		return false, "No authored summon profile."
	end
	if not _enemyGenerator or not _enemyGenerator.SpawnSummon then
		warn("[CommandService] SUMMON: EnemyGenerator not injected — spawn no-op (SetEnemyGenerator missing)")
		return false, "Summon spawner not wired."
	end

	-- Placement (shared spawn rule, 2026-10-07): use the targeted tile if valid
	-- (in bounds, passable, no blocker, no living unit); otherwise spawn on the
	-- nearest valid tile to the target (or caster if no target), picking randomly
	-- among equally-near valid tiles. Seeded RNG keeps it deterministic.
	local sx, sy
	local ax = (target and target.tileX) or actor.tileX or 1
	local ay = (target and target.tileY) or actor.tileY or 1
	if _enemyGenerator.FindNearestFreeSpawnTile then
		local seed = (state.ct or 0) + ax * 73856093 + ay * 19349663
			+ (tonumber(string.match(tostring(actor.id or "0"), "%d+")) or 0)
		local tile = _enemyGenerator.FindNearestFreeSpawnTile(state, ax, ay, Random.new(seed))
		if tile then
			sx, sy = tile.x, tile.y
		end
	else
		warn("[CommandService] SUMMON: FindNearestFreeSpawnTile unavailable — falling back to legacy tile search")
		sx, sy = findEmptySummonTile(actor, state)
	end
	if not sx then
		warn("[CommandService] SUMMON: no empty tile for summon — spawn aborted, existing summon kept")
		return false, "No empty tile for summon."
	end

	local cStats = actor.effectiveStats or {}
	local casterMaxHp = actor.maxHp or 1

	-- Build the authored stat table (caster-% snapshot). Each summon stat derives
	-- from the caster stat named in statSrc (default: same-named stat).
	local stats
	if not prof.inheritsNoStats then
		stats = {}
		for _, k in ipairs({ "STR", "AGI", "INT", "VIT", "DEX", "LUK" }) do
			local pct = prof.statPct and prof.statPct[k] or 0
			local srcKey = (prof.statSrc and prof.statSrc[k]) or k
			local srcVal = cStats[srcKey] or 10
			stats[k] = math.max(1, math.round(srcVal * pct))
		end
	else
		-- Decoy inherits nothing; give minimal stats so UnitSchema.Create is valid.
		stats = { STR = 1, AGI = 1, INT = 1, VIT = 1, DEX = 1, LUK = 1 }
	end

	-- Authored Max HP (fixed for Decoy, % of caster for the rest).
	local maxHp = prof.fixedHp or math.max(1, math.round(casterMaxHp * (prof.hpPct or 0)))

	-- Turret snapshots the caster's Weapon Attack Power x authored pct AT CAST TIME.
	local turretDmg = nil
	local weaponDamage = 0
	if prof.turretDamagePct then
		local atkPower = GameConstants.CalcAttackPower(actor.weaponDamage or 10, cStats.STR or 10)
		turretDmg = math.max(1, math.round(atkPower * prof.turretDamagePct))
		weaponDamage = turretDmg  -- turret's basic attack uses the snapshot
	end

	local summonSpec = {
		id = (skillDef.id or "SUMMON") .. "_" .. (actor.id or "caster"),
		name = prof.displayName or prof.type or "Summon",
		side = actor.side,                 -- caster's side (incl. "Player")
		level = actor.level or 1,
		stats = stats,
		maxHp = maxHp,
		weaponDamage = weaponDamage,
		weaponMinRange = prof.range and prof.range[1] or 1,
		weaponMaxRange = prof.range and prof.range[2] or 1,
		weaponProjectileType = prof.proj,
		summonType = prof.type,
		summonOwnerId = actor.id,          -- one-at-a-time replace key
		summonProfile = prof.profile,      -- AI behaviour tag
		canMove = prof.canMove,
		isFlying = prof.isFlying,
		auraSpec = prof.auraSpec,
		turretSnapshotDamage = turretDmg,
		baseRt = prof.baseRt,              -- optional authored Base RT override (default 400)
		skillIds = prof.skillIds,          -- authored summon actions (Mender heal)
	}

	-- CREATE NEW FIRST (status_summon_engines "Replace existing": never delete the
	-- previous summon before the new one is successfully created).
	local newUnit = _enemyGenerator.SpawnSummon(summonSpec, { x = sx, y = sy }, state)
	if not newUnit then
		warn(string.format("[CommandService] SUMMON [%s] SpawnSummon failed — existing summon (if any) kept", tostring(skillDef.id)))
		return false, "Spawn failed."
	end

	-- RETIRE the caster's PREVIOUS same-type summon (one-at-a-time). Done only after
	-- the new one exists. Mark KO'd + remove from roster; broadcast its removal.
	local retired = 0
	for i = #state.units, 1, -1 do
		local u = state.units[i]
		if u ~= newUnit and u.isSummon and u.summonOwnerId == actor.id
			and u.summonType == prof.type then
			u.isAlive = false
			u.currentHp = 0
			if BattleVisualBroadcaster.UnitKilled then
				BattleVisualBroadcaster.UnitKilled(u)
			elseif BattleVisualBroadcaster.UnitStateChanged then
				BattleVisualBroadcaster.UnitStateChanged(u)
			end
			table.remove(state.units, i)
			retired += 1
		end
	end

	-- Broadcast the new summon so the client renders it (reuses UnitSpawned; the
	-- summon is already a standard, serializable unit — no client change needed).
	if BattleVisualBroadcaster.UnitSpawned then
		BattleVisualBroadcaster.UnitSpawned(newUnit)
	end

	print(string.format(
		"[CommandService] SUMMON [%s] | %s summons %s (side=%s) at (%d,%d) | HP=%d | replaced %d prior",
		skillDef.id or "?", actor.name, newUnit.name, newUnit.side, sx, sy, newUnit.maxHp, retired))
	return true, { type = "Summon", summon = newUnit, replaced = retired }
end

-- Battlefield-event NPC Interact resolver (2026-10-04). Injected by Main as
-- BattlefieldEventService.ResolveInteract — injection (not a require) keeps
-- CommandService free of any dependency on the event engine (cycle-free).
-- fn(actor, target, state) -> ok:boolean, reason:string?
-- nil-safe: with no resolver wired, an eventNpc Interact charges cost and no-ops.
local _eventNpcResolver = nil
function CommandService.SetEventNpcResolver(fn)
	_eventNpcResolver = fn
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

-- Mender's authored healing action (DOC-CONJURER-03 Power_Formula): Range 3, 1 AP,
-- RT 80, no MP, heal = (10 + 0.20L + 0.40 x Mender INT) x Skill Potency. Instant.
skillRegistry["SKL-MENDER-HEAL"] = {
	id = "SKL-MENDER-HEAL", name = "Mend", tags = { "Healing" },
	targetRules = "Ally Unit, Self", range = 3, aoePattern = nil,
	mpCost = 0, rtCost = 80, channelTime = 0, power = 0,
	inheritStr = false, appliesStatus = nil, isHealing = true,
	isMenderHeal = true, projectileType = "Direct",
}

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
	-- Perks & Flaws (Phase 2b): Fleet Runner/Plodding adjust movement RT specifically.
	local traitMoveMult = TraitEffectService.GetMoveRtMultiplier(actor)
	return math.round(perTile * tilesMoving * frozenMult * wetMult * traitMoveMult)
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
	-- Perks & Flaws Phase 2 (TRAIT-BA-WT): Basics (x0.60) / Heavy Basics (x1.30) scale the
	-- Basic Attack weapon-WT term only (skills unaffected). Non-positive WT left alone.
	local baTraitWtMult = TraitEffectService.GetBasicAttackWtMultiplier(actor)
	if baTraitWtMult ~= 1 and effectiveWt > 0 then
		effectiveWt = effectiveWt * baTraitWtMult
	end
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

function CommandService.TriggerCounterIfEligible(defender, attacker, state, wasCounter, wasAOE, dealtDamage)
	-- Guard 0: only an attack that dealt DIRECT DAMAGE provokes a counter (USER
	-- RULING 2026-10-03). Basic Attacks always deal damage; damaging skills of ANY
	-- pattern qualify; zero-damage / pure-status / debuff-only skills (Steal,
	-- Silence, etc.) and hits fully absorbed to 0 do NOT provoke. `dealtDamage`
	-- nil defaults to true for back-compat with the basic-attack call path.
	if dealtDamage == false then return false end
	-- Guard 1: never let a counter (or AOE splash) trigger another counter.
	if wasCounter or wasAOE then return false end
	-- Guard 2: both units must be live and real, and not self.
	if not defender or not attacker then return false end
	if not defender.isAlive or not attacker.isAlive then return false end
	if defender.id == attacker.id then return false end
	-- Guard 2b: enemy-only (DB trigger rule TRG-004). An ally striking the
	-- stance holder (friendly fire, mind-control, etc.) must NOT provoke a counter.
	if attacker.side == defender.side then return false end
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

	-- Weapon RT Delay to the ATTACKER (DB: Riposte 50% / Counter Stance 30% of the
	-- defender's Weapon RT Delay). Separate from the counter damage — an extra
	-- turn-order setback on whoever provoked the counter. VIT-resisted, exactly
	-- like a normal basic attack's RT delay.
	local rtDelayMult = (inst and inst.counterRtDelayMult) or 0
	local rawDelay = (defender.weaponRtDelay or 0) * rtDelayMult
	if rawDelay > 0 and attacker.isAlive then
		local atkVit = attacker.effectiveStats and attacker.effectiveStats.VIT or 10
		local delay = GameConstants.CalcRtDelayResistance(math.round(rawDelay), atkVit)
		attacker.remainingRt = (attacker.remainingRt or 0) + math.max(0, delay)
		print(string.format("[CommandService] COUNTER RT-DELAY | %s +%d RT (x%.2f weapon delay)",
			attacker.name, math.max(0, delay), rtDelayMult))
		BattleVisualBroadcaster.UnitStateChanged(attacker)
	end
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

--------------------------------------------------
-- PURE BUFF helpers (2026-10-07: Hold the Line / Coordinated Advance / War Cry).
-- Power-0 skills whose intent is a status on the caster or allies. Applied
-- directly (no ResolveSkill) so a buff never runs the damage path against a
-- friendly unit (BUG-004 class). Allies = same side only (recruited Neutrals and
-- enemies excluded).
--------------------------------------------------
local function isPureBuffSkill(skillDef)
	return (skillDef.power or 0) == 0 and not skillDef.inheritStr
		and not skillDef.isHealing and not skillDef.isShield
		and (skillDef.appliesStatus ~= nil or skillDef.appliesStatuses ~= nil)
end

-- Caster-centred ally aura (War Cry: "Self, Allies", Circle3).
local function isPureBuffAura(skillDef)
	return isPureBuffSkill(skillDef) and skillDef.targetRules == "Self, Allies"
		and skillDef.aoePattern ~= nil and skillDef.aoePattern ~= "InheritWeapon"
end

local function auraTargets(state, caster, skillDef)
	local radius = tonumber(tostring(skillDef.aoePattern):match("%d+")) or 1
	local list = {}
	for _, u in ipairs(state.units) do
		if u.isAlive and u.side == caster.side
			and math.max(math.abs((u.tileX or 0) - caster.tileX), math.abs((u.tileY or 0) - caster.tileY)) <= radius then
			table.insert(list, u)
		end
	end
	return list
end

-- Applies the skill's status(es) to each target; returns AOE-shaped entries
-- ({ target, outcome = { finalDamage = 0, appliesStatus } }) for Main's broadcast.
local function applyPureBuff(caster, skillDef, targets)
	local entries = {}
	for _, u in ipairs(targets) do
		local applied = nil
		-- MP effects (2026-10-07): Mana Surge / Meditate self restore round(MaxMP x f);
		-- Meditate on an ally transfers min(caster MP, ally missing MP, round(caster
		-- MaxMP x f)) from caster to ally. Clamped, never negative.
		if u.id == caster.id and skillDef.selfMpRestoreFraction then
			local gain = math.round((caster.maxMp or 0) * skillDef.selfMpRestoreFraction)
			caster.currentMp = math.min(caster.maxMp or 0, (caster.currentMp or 0) + gain)
			print(`[CommandService] {skillDef.name}: {caster.name} restores MP -> {caster.currentMp}/{caster.maxMp}`)
		elseif u.id ~= caster.id and skillDef.allyMpTransferFraction then
			local missing = math.max(0, (u.maxMp or 0) - (u.currentMp or 0))
			local amount = math.max(0, math.min(caster.currentMp or 0, missing,
				math.round((caster.maxMp or 0) * skillDef.allyMpTransferFraction)))
			caster.currentMp = (caster.currentMp or 0) - amount
			u.currentMp = (u.currentMp or 0) + amount
			print(`[CommandService] {skillDef.name}: {caster.name} transfers {amount} MP to {u.name}`)
			if BattleVisualBroadcaster.UnitStateChanged then BattleVisualBroadcaster.UnitStateChanged(caster) end
		end
		if skillDef.appliesStatus then
			StatusService.ApplyStatus(u, skillDef.appliesStatus, caster.id, nil, skillDef.statusDurationCt)
			applied = skillDef.appliesStatus
		end
		if skillDef.appliesStatuses then
			for _, sid in ipairs(skillDef.appliesStatuses) do
				StatusService.ApplyStatus(u, sid, caster.id, nil, skillDef.statusDurationCt)
				applied = applied or sid
			end
		end
		if BattleVisualBroadcaster.UnitStateChanged then
			BattleVisualBroadcaster.UnitStateChanged(u)
		end
		table.insert(entries, { target = u, outcome = { finalDamage = 0, appliesStatus = applied } })
	end
	return entries
end

--------------------------------------------------
-- MISDIRECTION (DOC-TRICKSTER-01, DB skills row; built 2026-10-07)
-- "For 1000 CT, first enemy AP-consuming Basic Attack or Skill directly
-- targeting caster redirects to another valid enemy-selected target adjacent
-- to caster if available; otherwise original targeting remains. One trigger;
-- consumed on first eligible targeting event. Cannot redirect AOE, reactions,
-- redirected actions, or environmental effects."
-- Runs ONCE per command at the end of STEP 5 (after the original target was
-- validated, before costs/commit), so the swapped target is what gets resolved
-- or stored for a channel. Counters/reactions never pass through
-- ValidateAndCommit, and DoT/tile effects are not commands, so they are
-- excluded by construction. Redirect target = a unit adjacent (Chebyshev 1) to
-- the Misdirection holder that the ATTACKER could legally target with the same
-- action (same TargetingService.ValidateSelection call the original used);
-- never the attacker or the holder. Deterministic pick (no-RNG rule): lowest
-- current HP, tie-break by unit id. The status is consumed on every eligible
-- event, even when no legal redirect target exists.
--------------------------------------------------
local function isSingleTargetSkill(actor, skillDef, target)
	if not skillDef or not target or target.isGroundTarget then return false end
	if (skillDef.targetRules or "Enemy Unit") ~= "Enemy Unit" then return false end
	local aoe = skillDef.aoePattern
	if aoe == "InheritWeapon" then
		return (actor.weaponPattern or "Single") == "Single"
	end
	return aoe == nil
end

local function applyMisdirection(state, actor, actionType, selection, skillDef, skillSelection)
	local holder
	if actionType == "Attack" then
		if (actor.weaponPattern or "Single") ~= "Single" then return selection end
		holder = selection
	elseif actionType == "Skill" then
		holder = type(selection) == "table" and selection.target or nil
		if not isSingleTargetSkill(actor, skillDef, holder) then return selection end
	else
		return selection
	end
	if type(holder) ~= "table" or not holder.isAlive or holder.side == actor.side
		or not StatusService.HasStatus(holder, "Misdirection") then
		return selection
	end

	-- Eligible targeting event: consume the single trigger.
	StatusService.RemoveStatus(holder, "Misdirection")
	if BattleVisualBroadcaster.StatusExpired then BattleVisualBroadcaster.StatusExpired(holder, "Misdirection") end

	local best
	for _, u in ipairs(state.units) do
		if u.isAlive and u ~= holder and u ~= actor
			and math.max(math.abs(u.tileX - holder.tileX), math.abs(u.tileY - holder.tileY)) == 1 then
			local ok
			if actionType == "Attack" then
				ok = TargetingService.ValidateSelection(actor, "Attack", u, state.units, _mapWidth, _mapHeight)
			else
				local sel = table.clone(skillSelection)
				sel.target = u
				ok = TargetingService.ValidateSelection(actor, "Skill", sel, state.units, _mapWidth, _mapHeight)
			end
			if ok then
				local hp, bestHp = u.currentHp or 0, best and (best.currentHp or 0) or math.huge
				if hp < bestHp or (hp == bestHp and tostring(u.id) < tostring(best.id)) then
					best = u
				end
			end
		end
	end

	if not best then
		print(`[CommandService] Misdirection on {holder.name} consumed — no legal adjacent target, {actor.name}'s action stays on {holder.name}`)
		return selection
	end
	print(`[CommandService] Misdirection: {actor.name}'s {actionType == "Attack" and "Basic Attack" or (skillDef.name or "Skill")} redirected from {holder.name} to {best.name}`)
	BattleVisualBroadcaster.ActionAnnounced(holder, "Misdirection")
	if actionType == "Attack" then
		return best
	end
	local swapped = table.clone(selection)
	swapped.target = best
	swapped._misdirected = true
	return swapped
end

--------------------------------------------------
-- SKILL MP COST (2026-10-07, level-based; project_rules 43 / frameworks 8)
-- ONE place that prices a cast, used by validation, commit, the turn prompt,
-- the inspector and the AI so they can never disagree (DAT-001):
--   base   = round(Base + Growth x (ESL - 1)) from the skill's DB formula
--            (GameConstants.CalcSkillMpCost; flat mpCost if no formula)
--   x race x trait x doctrine x augment MP modifiers, rounded ONCE
--   + Mana Burn extra round(Max MP x 0.20) (DB: "Total MP Spent = Skill MP Cost
--     + Extra") added after rounding.
-- Returns (totalMpCost, manaBurnExtra).
-- NOTE: the augment multiplier is now applied at COMMIT too. Before this, only
-- validation applied it, so augment MP surcharges/discounts were never charged.
--------------------------------------------------
function CommandService.GetSkillMpCost(actor, skillDef, skillId)
	if type(skillDef) ~= "table" or type(actor) ~= "table" then return 0, 0 end
	local sid = skillId or skillDef.id
	local mult = RacePassiveService.GetMpCostModifier(actor)
		* TraitEffectService.GetMpCostModifier(actor) -- Economist / Spendthrift
		* DoctrinePassiveService.GetMpCostModifier(actor, actor._docFirstSkillUsed ~= true)
		* AugmentEffectService.GetMpCostMultiplier(actor, sid)
	local mpCost = GameConstants.CalcSkillMpCost(actor, skillDef, mult)
	local manaBurnExtra = 0
	if StatusService.HasStatus(actor, "Mana Burn") then
		manaBurnExtra = math.round((actor.maxMp or 20) * 0.20)
	end
	return mpCost + manaBurnExtra, manaBurnExtra
end

function CommandService.ActivateChanneledSkill(state, unit)
	if not unit.isChanneling or not unit.channelingData then
		return false, "Unit is not channeling."
	end

	local data     = unit.channelingData
	local skillDef = data.skillDef
	local target   = data.target
	local mpCost   = data.mpCost or 0
	-- Self skills (Mana Surge) resolve on the caster even if no target was stored.
	if not target and skillDef and skillDef.targetRules == "Self" then target = unit end

	-- Clear channeling state first (regardless of outcome)
	unit.isChanneling   = false
	unit.channelingData = nil
	unit.channelRt      = nil
	unit.channelResolveCt = nil
	unit.channelPhase   = nil
	unit.pendingActivationCt = nil

	-- SUMMON skill (channeled Decoy/Turret/Ward Totem). Resolve the summon spawn
	-- here, BEFORE the target-alive fizzle below: the channel target is a stat-less
	-- Empty-Tile marker (target.isAlive == nil) which would otherwise be read as a
	-- dead target and fizzle. MP was already validated at commit; spend it, announce,
	-- then spawn. No damage, no rewards; recast replaces the caster's prior summon.
	if skillDef and skillDef.isSummon then
		if not UnitSchema.HasEnoughMp(unit, mpCost) then
			print(string.format(
				"[CommandService] Channel FIZZLE | %s | [%s] — MP insufficient (%d/%d needed)",
				unit.name, skillDef.name or skillDef.id, unit.currentMp, mpCost))
			return false, "MP insufficient at activation."
		end
		UnitSchema.SpendMp(unit, mpCost)
		BattleVisualBroadcaster.ActionAnnounced(unit, skillDef.name or skillDef.id or "Summon")
		local ok, info = spawnSummonFor(unit, skillDef, target, state)
		return ok, ok and info or { type = "Summon", failed = true, reason = info }
	end

	-- INTERACT RESUSCITATE (channeled KO'd-ally revive). Runs BEFORE the
	-- target-alive fizzle below, because for a revive the target is SUPPOSED
	-- to be KO'd. Resolves at the 200 CT (or headgear-reduced) deadline.
	if data.interactResolve == "reviveAlly" then
		if not target then
			return false, "Revive target missing at activation."
		end
		if target.isAlive then
			-- Already revived some other way during the channel — no-op.
			return false, target.name .. " is no longer KO'd."
		end
		local frac = data.reviveHpFrac or 0.05
		target.isAlive   = true
		target.currentHp = math.max(1, math.ceil((target.maxHp or 1) * frac))
		target.remainingRt = target.startingRt or 400
		BattleVisualBroadcaster.ActionAnnounced(unit, "Resuscitate")
		BattleVisualBroadcaster.UnitStateChanged(target)
		print(string.format(
			"[CommandService] INTERACT REVIVE RESOLVE | %s resuscitates %s at %d/%d HP",
			unit.name, target.name, target.currentHp, target.maxHp or 0
		))
		return true, { type = "Resuscitate", target = target, hp = target.currentHp }
	end

	-- Check if target is still alive (for offensive/healing skills). Ground-tile
	-- markers (isGroundTarget) are not units and never 'die' -- they resolve on the
	-- committed tile (2026-10-07 activation-time build; previously a channeled ground
	-- skill's stat-less marker read as a dead target and fizzled).
	if target and not target.isGroundTarget and not target.isAlive then
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

	if skillDef.isShield then
		-- SHIELD GRANT (channeled resolution: Vital Barrier, Bastion Projection,
		-- Bulwark Field, Retribution Shell) — shield subsystem 2026-10-05. Mirrors
		-- the isHealing channeled branch: compute the authored shield amount
		-- (CombatResolver.ResolveShield, keyed to skill id) and GRANT it via the
		-- existing StatusService.ApplyShield API (ApplyShieldOutcome). Deals NO
		-- attack damage. Routed FIRST so a 0-power shield skill never falls through
		-- to the damage branches. L = Effective Skill Level = caster main-hand item
		-- level (same source the channel-commit RT used).
		local shMainHand = unit.equipmentSlots and unit.equipmentSlots.MainHand
		local shSkillLevel = (shMainHand and shMainHand.itemLevel) or 1
		if skillDef.aoePattern then
			-- Bulwark Field (Self, Allies, caster-origin Circle radius 2): grant an
			-- INDEPENDENT shield instance to the caster + every living ally within the
			-- caster-origin Chebyshev radius parsed from the pattern. Each ally's
			-- amount is computed from that ally-as-recipient? No — the recipe scales
			-- with the CASTER's stats/weapon (the caster projects the field), so the
			-- caster is passed as the shield source for every grant.
			local radius = tonumber(tostring(skillDef.aoePattern):match("%d+")) or 2
			local granted = 0
			for _, u in ipairs(state.units) do
				if u.isAlive and u.side == unit.side
					and math.max(math.abs((u.tileX or 0) - unit.tileX), math.abs((u.tileY or 0) - unit.tileY)) <= radius then
					local outcome = CombatResolver.ResolveShield(unit, u, skillDef, shSkillLevel)
					CombatResolver.ApplyShieldOutcome(outcome, u)
					granted = granted + 1
				end
			end
			result.type      = "Shield"
			result.alliesShielded = granted
			result.skillName = skillDef.name
			print(string.format(
				"[CommandService] Channel ACTIVATE [%s] AOE SHIELD | %s | allies shielded:%d | MP:%d",
				skillDef.name, unit.name, granted, mpCost
			))
		else
			local outcome = CombatResolver.ResolveShield(unit, target, skillDef, shSkillLevel)
			CombatResolver.ApplyShieldOutcome(outcome, target)
			result.type      = "Shield"
			result.target    = target
			result.shieldHp  = outcome.shieldHp
			result.skillName = skillDef.name
			print(string.format(
				"[CommandService] Channel ACTIVATE [%s] SHIELD | %s -> %s | Shield:%d | MP:%d",
				skillDef.name, unit.name, target.name, outcome.shieldHp, mpCost
			))
		end

	elseif skillDef.isHealing then
		local outcome = CombatResolver.ResolveHealing(unit, target, skillDef)
		local actual = CombatResolver.ApplyOutcome(outcome, target, unit)
		result.type     = "Healing"
		result.target   = target
		result.healing  = actual
		result.skillName = skillDef.name

		print(string.format(
			"[CommandService] Channel ACTIVATE [%s] | %s -> %s | Heal:%d | MP:%d",
			skillDef.name, unit.name, target.name, actual, mpCost
		))

	elseif isPureBuffAura(skillDef) then
		-- War Cry (channeled): caster + same-side allies within the Circle radius.
		local entries = applyPureBuff(unit, skillDef, auraTargets(state, unit, skillDef))
		result.type      = "AOE"
		result.targets   = entries
		result.totalDmg  = 0
		result.hitCount  = #entries
		result.skillName = skillDef.name
		print(string.format(
			"[CommandService] Channel ACTIVATE [%s] AURA BUFF | %s | allies buffed:%d | MP:%d",
			skillDef.name, unit.name, #entries, mpCost
		))

	elseif isPureBuffSkill(skillDef) and target and not target.isGroundTarget
		and target.side == unit.side then
		-- Channeled self/ally buff (Coordinated Advance): status only, no damage path.
		local entries = applyPureBuff(unit, skillDef, { target })
		result.type      = "AOE"
		result.targets   = entries
		result.totalDmg  = 0
		result.hitCount  = #entries
		result.skillName = skillDef.name
		print(string.format(
			"[CommandService] Channel ACTIVATE [%s] BUFF | %s -> %s | MP:%d",
			skillDef.name, unit.name, target.name, mpCost
		))

	elseif skillDef.aoePattern == "Cleave" then
		local targets = TargetingService.GetCleaveTargets(unit, target, state.units)
		local totalDmg = 0
		local hitCount = 0
		local allOutcomes = {}
		for _, t in ipairs(targets) do
			if t.isAlive then
				local outcome = CombatResolver.ResolveSkill(unit, t, skillDef)
				CombatResolver.ApplyOutcome(outcome, t, unit)
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
		local actualDmg, statusApplied = CombatResolver.ApplyOutcome(outcome, target, unit)
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


		-- Level-based MP cost incl. race/trait/doctrine/augment modifiers and the
		-- Mana Burn extra (2026-10-07; ONE shared pricing: CommandService.GetSkillMpCost).
		local mpCost = CommandService.GetSkillMpCost(actor, skillDef, selection.skillId)

		if not UnitSchema.HasEnoughMp(actor, mpCost) then
			return false, string.format(
				"%s does not have enough MP (%d/%d needed).",
				actor.name, actor.currentMp, mpCost
			)
		end

		local targetSelection = {
			target      = selection.target,
			targetRules = skillDef.targetRules or "Enemy Unit",
		}
		-- 2026-10-07: ONE shared range formula (DAT-001) — same call as
		-- TargetingService.GetSkillCandidates: weapon-only min range, per-skill
		-- Bonus Skill Range share, Halfling Nimble Steps race modifier.
		targetSelection.skillRange, targetSelection.skillMinRange = GameConstants.CalcSkillRange(
			actor, skillDef, RacePassiveService.GetSkillRangeModifier(actor, skillDef))

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

	elseif actionType ~= "Wait" and actionType ~= "Guard" and actionType ~= "Push"
		and actionType ~= "Interact" then
		-- Move and Attack need target/tile validation
		local valid, reason = TargetingService.ValidateSelection(
			actor, actionType, selection,
			state.units, _mapWidth, _mapHeight
		)
		if not valid then return false, reason end
	end

	-- STEP 5b2: Misdirection redirect (DOC-TRICKSTER-01). Only enemy single-target
	-- Basic Attacks / Skills aimed at a Misdirection holder; one swap per command.
	if actionType == "Attack" or actionType == "Skill" then
		local skillSel = nil
		if actionType == "Skill" then
			skillSel = { target = selection.target, targetRules = skillDef.targetRules or "Enemy Unit" }
			skillSel.skillRange, skillSel.skillMinRange = GameConstants.CalcSkillRange(
				actor, skillDef, RacePassiveService.GetSkillRangeModifier(actor, skillDef))
		end
		selection = applyMisdirection(state, actor, actionType, selection, skillDef, skillSel)
	end

	-- STEP 5c: Interact pre-validation (reject BEFORE charging AP — DB command_pipeline
	-- step 5 "Reject without payment"). Confirms the chosen target is a current
	-- Interact candidate; a stale/invalid Interact returns here, spending no AP/RT.
	if actionType == "Interact" then
		if type(selection) ~= "table" then
			return false, "Interact requires a selection."
		end
		local _cands = TargetingService.GetInteractCandidates(actor, state.units, state)
		local _ok = false
		for _, c in ipairs(_cands) do
			if selection.interactKind == "mapObject" then
				if c.interactKind == "mapObject" and selection.objectId and c.objectId == selection.objectId then
					_ok = true; break
				end
			elseif c.id and selection.targetId and c.id == selection.targetId
				and c.interactKind == selection.interactKind then
				_ok = true; break
			end
		end
		if not _ok then
			return false, "No valid Interact target for that selection."
		end
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
		if actor.isSummon and actor.canMove == false then
			return false, "This summon cannot move."
		end
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

		-- Slice 5 passive auras: the mover may have entered/left a War Banner or
		-- Cursed Statue radius — reconcile so aura buffs/debuffs track position.
		ObjectEffectService.ReconcileAuras(state.units, state)

		-- Flight bypasses terrain cross effects, terrain triggers (Drowning) and tile-effect
		-- entry entirely (DB status id 83: "ignores terrain movement costs, tile
		-- bonuses/penalties"; Drowning is removed by/immune under Flight). A grounded unit
		-- processes them normally.
		local actorFlying = StatusService.HasStatus(actor, "Flight")
		if not actorFlying then
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
		end

		-- Counter-attack trigger (ALL weapon patterns): if the PRIMARY target holds
		-- a CounterStance and the attacker is within its weapon reach, it ripostes.
		-- Placed after the pattern block (not just single-target) so a cleave/line/
		-- splash/adjacent attacker that strikes a stance holder is also countered.
		-- wasCounter=false (this is a real attack), wasAOE=false (we are evaluating
		-- the PRIMARY target hit, not a splash victim).
		-- A basic attack provokes a counter only if it dealt direct damage > 0
		-- (a hit fully absorbed to 0 does not provoke).
		CommandService.TriggerCounterIfEligible(target, actor, state, false, false, (totalDmg or 0) > 0)

		BattleCoordinator.AccrueRt(state, rtCost)

		-- Apply Weapon RT Delay to primary target (reduced by target VIT)
		-- Perks & Flaws (Phase 2b): Time Locker/Time Freed/Timeline Sovereign scale the
		-- RT delay this attacker INFLICTS, before target VIT resistance.
		local rawDelay = (actor.weaponRtDelay or 0) * TraitEffectService.GetRtDelayInflictMultiplier(actor)
		if rawDelay > 0 and target.isAlive then
			local targetVit = target.effectiveStats and target.effectiveStats.VIT or 10
			local actualDelay = GameConstants.CalcRtDelayResistance(math.round(rawDelay), targetVit)
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
		-- MANA SURGE (2026-10-07): the next ELIGIBLE skill committed while the caster
		-- holds "Mana Surge" gets Skill Potency +10% and consumes the status here, at
		-- commit. Eligible = any skill with a potency-scaled result (damage, heal or
		-- shield) other than Mana Surge itself; pure buffs/summons don't consume it.
		-- The bonus is snapshotted on a per-cast copy of the def so a channeled skill
		-- keeps it at activation without touching the shared skill table.
		if skillDef.id ~= "DOC-ARCANIST-01" and StatusService.HasStatus(actor, "Mana Surge")
			and ((skillDef.power or 0) > 0 or skillDef.isHealing or skillDef.isShield) then
			StatusService.RemoveStatus(actor, "Mana Surge")
			if BattleVisualBroadcaster.StatusExpired then BattleVisualBroadcaster.StatusExpired(actor, "Mana Surge") end
			local surged = table.clone(skillDef)
			surged.potencyBonusMult = (skillDef.potencyBonusMult or 1)
				* ((GameConstants.STATUSES["Mana Surge"] or {}).potencyBonusMult or 1.10)
			skillDef = surged
			print(`[CommandService] Mana Surge consumed by {actor.name} on [{skillDef.name}] (potency x{surged.potencyBonusMult})`)
		end
		-- Level-based MP cost — SAME shared pricing as validation (2026-10-07), so the
		-- amount checked is the amount charged (now incl. the augment MP modifier).
		local mpCost, manaBurnExtra = CommandService.GetSkillMpCost(actor, skillDef, selection.skillId)

		-- ACTIVATION TIME (2026-10-07): authored per skill in Content.SkillData, not
		-- DEX-reduced (frameworks 10/37). A channeled skill waits channel + activation.
		-- A ZERO-channel skill with activation > 0 is deferred only when its kind is one
		-- the deferred resolver (ActivateChanneledSkill) already handles in full:
		-- shield, summon, heal, or an area pattern (not weapon-inherited). Other
		-- zero-channel skills (single-target strikes with counters/RT delay/charge,
		-- swaps, self-buffs) stay instant until that resolver supports them.
		local activationCt = GameConstants.GetSkillActivationTime(skillDef.id)
		local hasChannel = skillDef.channelTime and skillDef.channelTime > 0
		local deferZeroChannel = (not hasChannel) and activationCt > 0
			and (skillDef.isShield or skillDef.isSummon or skillDef.isHealing
				or (skillDef.aoePattern ~= nil and skillDef.aoePattern ~= "InheritWeapon"))
			and not skillDef.isCharge
		if not hasChannel and not deferZeroChannel then activationCt = 0 end

		-- Check if this is a CHANNELED (or activation-delayed) skill
		if hasChannel or deferZeroChannel then
			-- CHANNELED SKILL: don't spend MP, don't resolve.
			-- Set up channeling state, end turn with channel RT.
			local dex = actor.effectiveStats and actor.effectiveStats.DEX or 10
			local channelRt = 0
			if hasChannel then
				channelRt = GameConstants.CalcChannelTime(skillDef.channelTime, dex)
				-- Perks & Flaws (Phase 2b): Channeler/Slow Channeler adjust channel RT by +/-25%.
				channelRt = math.round(channelRt * TraitEffectService.GetChannelTimeMultiplier(actor))
			end

			BattleCoordinator.StartChanneling(state, actor, {
				skillDef  = skillDef,
				target    = target,
				mpCost    = mpCost,
				channelRt = channelRt,
				activationCt = activationCt,
			})
			-- Start the looping channel VFX on the caster (damage vs heal picks the asset).
			BattleVisualBroadcaster.ChannelStarted(actor, skillDef.isHealing == true)

			-- TWO-TIMER MODEL: the caster ends its turn NORMALLY (base + this skill's RT
			-- cost), so it keeps a real, independent RT. The channel deadline
			-- (channelResolveCt) was set in StartChanneling and ticks separately on the
			-- global clock. Compute the skill RT cost with the SAME formula as the
			-- non-channel skill path, accrue it, then end the turn normally.
			local chBaseRtCost
			-- Fixed/level-based skills (DB authoritative) charge their OWN authored cost,
			-- NOT the weapon-WT formula. L = Effective Skill Level = main-hand item level.
			local chMainHand = actor.equipmentSlots and actor.equipmentSlots.MainHand
			local chSkillLevel = (chMainHand and chMainHand.itemLevel) or 1
			local chFixedRt = GameConstants.CalcFixedSkillRt(skillDef.id, chSkillLevel)
			if chFixedRt then
				chBaseRtCost = chFixedRt
			elseif skillDef.rtMult then
				-- Skill RT = round((Modified Base RT base component + weapon WT) × SkillMult)
				-- (USER RULING 2026-10-04, DB project_rules 136). The base component
				-- (ModBaseRt × BASIC_ATTACK_RT_FACTOR) mirrors Basic Attack RT, so Haste/Slow
				-- reach skill RT via Modified Base RT (base component only; not the weapon
				-- term or SkillMult). Frozen ×2 + Arcane Prodigy apply as the outer layer below.
				local skillBaseComponent = StatusService.GetModifiedBaseRt(actor) * BASIC_ATTACK_RT_FACTOR
				local skillWeaponWt = GameConstants.CalcEffectiveWt((actor.weaponWt or 10), (actor.effectiveStats or {}).STR or 10)
				chBaseRtCost = math.round((skillBaseComponent + skillWeaponWt) * skillDef.rtMult)
			else
				chBaseRtCost = skillDef.rtCost or math.round(StatusService.GetModifiedBaseRt(actor) * 0.10)
			end
			chBaseRtCost = math.round(chBaseRtCost * StatusService.GetAllRtMultiplier(actor) * TraitEffectService.GetSkillRtMultiplier(actor)) -- Phase 2b: Arcane Prodigy skill RT
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

		-- Direct damage dealt to the PRIMARY target (the stance-holder for counter
		-- purposes). Set in each damaging branch below; stays 0 for zero-damage/
		-- status-only/self/ally/ground skills. Drives the counter trigger (damage>0).
		local _primaryTargetDamage = 0

		-- Mana Burn damage: round(Total MP Spent × 0.50 × Debuff Resistance)
		if manaBurnExtra > 0 and actor.isAlive then
			local debuffResist = StatusService.GetDebuffResist(actor) -- incl. Debuff Res Down (2026-10-07)
			local manaBurnDmg = math.round(mpCost * 0.50 * debuffResist)
			if manaBurnDmg > 0 then
				UnitSchema.ApplyDamage(actor, manaBurnDmg)
				print(string.format("[CommandService] Mana Burn: %s takes %d damage (MP spent: %d)",
					actor.name, manaBurnDmg, mpCost))
			end
		end

		-- Skill RT cost: fixed/level skills use SKILL_FIXED_RT (authored); weapon-WT skills
		-- use (Modified Base RT × 0.10 + Effective Weapon WT) × rtMult. Fixed check runs first.
		-- Fallback: rtCost (legacy) or baseRt × 0.10
		local baseRtCost
		-- Fixed/level-based skills charge their OWN authored cost (DB authoritative),
		-- NOT the weapon-WT formula. L = Effective Skill Level = main-hand item level.
		local mainHandItem = actor.equipmentSlots and actor.equipmentSlots.MainHand
		local skillLevelL = (mainHandItem and mainHandItem.itemLevel) or 1
		local fixedRt = GameConstants.CalcFixedSkillRt(skillDef.id, skillLevelL)
		if fixedRt then
			baseRtCost = fixedRt
		elseif skillDef.rtMult then
			-- Skill RT = round((Modified Base RT base component + weapon WT) × SkillMult)
			-- (USER RULING 2026-10-04, DB project_rules 136). Base component mirrors Basic
			-- Attack RT so Haste/Slow reach skill RT via Modified Base RT (base part only).
			local skillBaseComponent = StatusService.GetModifiedBaseRt(actor) * BASIC_ATTACK_RT_FACTOR
			local skillWeaponWt = GameConstants.CalcEffectiveWt((actor.weaponWt or 10), (actor.effectiveStats or {}).STR or 10)
			baseRtCost = math.round((skillBaseComponent + skillWeaponWt) * skillDef.rtMult)
		else
			baseRtCost = skillDef.rtCost or math.round(StatusService.GetModifiedBaseRt(actor) * 0.10)
		end
		-- Frozen: all RT costs ×2
		baseRtCost = math.round(baseRtCost * StatusService.GetAllRtMultiplier(actor) * TraitEffectService.GetSkillRtMultiplier(actor)) -- Phase 2b: Arcane Prodigy skill RT

		if skillDef.isShield then
			-- SHIELD GRANT (instant / non-channeled: Arcane Barrier, Weapon Ward) —
			-- shield subsystem 2026-10-05. Computes the authored shield amount
			-- (CombatResolver.ResolveShield, keyed to skill id) and GRANTS it via the
			-- existing StatusService.ApplyShield API (ApplyShieldOutcome). Deals NO
			-- attack damage to target or caster. Routed BEFORE isHealing / AOE / the
			-- ResolveSkill fallthrough so a 0-power shield skill never leaks into the
			-- damage path (BUG-004 class: 0-power skills must not resolve as damage).
			-- L = Effective Skill Level = main-hand item level (skillLevelL above).
			if skillDef.aoePattern then
				-- AOE shield (e.g. a future instant Bulwark-like skill): grant an
				-- INDEPENDENT shield to the caster + every living ally within the
				-- caster-origin Circle (Chebyshev) radius parsed from the pattern.
				local radius = tonumber(tostring(skillDef.aoePattern):match("%d+")) or 2
				local granted = 0
				for _, u in ipairs(state.units) do
					if u.isAlive and u.side == actor.side
						and math.max(math.abs((u.tileX or 0) - actor.tileX), math.abs((u.tileY or 0) - actor.tileY)) <= radius then
						local outcome = CombatResolver.ResolveShield(actor, u, skillDef, skillLevelL)
						CombatResolver.ApplyShieldOutcome(outcome, u)
						granted = granted + 1
					end
				end
				BattleCoordinator.AccrueRt(state, baseRtCost)
				print(string.format(
					"[CommandService] SKILL [%s] AOE SHIELD | %s | allies shielded:%d | MP:%d | RT:%d | AP left:%d",
					skillDef.name or skillDef.id, actor.name, granted, mpCost, baseRtCost, actor.currentAp
				))
			else
				local outcome = CombatResolver.ResolveShield(actor, target, skillDef, skillLevelL)
				CombatResolver.ApplyShieldOutcome(outcome, target)
				BattleCoordinator.AccrueRt(state, baseRtCost)
				print(string.format(
					"[CommandService] SKILL [%s] SHIELD | %s -> %s | Shield:%d | MP:%d | RT:%d | AP left:%d",
					skillDef.name or skillDef.id, actor.name, target.name,
					outcome.shieldHp, mpCost, baseRtCost, actor.currentAp
				))
			end

		elseif skillDef.isHealing then
			local outcome = CombatResolver.ResolveHealing(actor, target, skillDef)
			CombatResolver.ApplyOutcome(outcome, target, actor)
			BattleCoordinator.AccrueRt(state, baseRtCost)

			print(string.format(
				"[CommandService] SKILL [%s] | %s -> %s | Heal:%d | MP:%d | RT:%d | AP left:%d",
				skillDef.name or skillDef.id,
				actor.name, target.name,
				outcome.finalHealing, mpCost, baseRtCost, actor.currentAp
			))

		elseif isPureBuffAura(skillDef) then
			-- War Cry (instant fallback, e.g. channel reduced to 0): caster + allies in radius.
			local entries = applyPureBuff(actor, skillDef, auraTargets(state, actor, skillDef))
			BattleCoordinator.AccrueRt(state, baseRtCost)
			print(string.format(
				"[CommandService] SKILL [%s] AURA BUFF | %s | allies buffed:%d | MP:%d | RT:%d | AP left:%d",
				skillDef.name or skillDef.id, actor.name, #entries, mpCost, baseRtCost, actor.currentAp
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
					if t.id == target.id then _primaryTargetDamage = outcome.finalDamage or 0 end
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
					if u.id == target.id then _primaryTargetDamage = outcome.finalDamage or 0 end
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
						if u.id == target.id then _primaryTargetDamage = outcome.finalDamage or 0 end
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
							if entry.unit.id == target.id then _primaryTargetDamage = outcome.finalDamage or 0 end
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
			-- Stamp the stance's counter tuning onto the live status instance so the
			-- counter resolver reads THIS skill's values (Riposte 0.85/0.50,
			-- Counter Stance 0.60/0.30). Without this stamp the instance carried no
			-- counterPowerMult and every counter fell back to the 0.85 default —
			-- i.e. Counter Stance wrongly hit at 85%. Applies on fresh cast AND
			-- recast (HasStatus returns the refreshed instance).
			if skillDef.appliesStatus == "CounterStance" then
				local inst = StatusService.HasStatus(actor, "CounterStance")
				if inst then
					inst.counterPowerMult   = skillDef.counterPowerMult or inst.counterPowerMult
					inst.counterRtDelayMult = skillDef.counterRtDelayMult or inst.counterRtDelayMult
				end
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
			-- SUMMON skill (non-channeled Conjurer Sentinel/Wisp/Mender): create the
			-- summoned unit instead of a tile effect. Gated by isSummon so only the
			-- six authored summon skills take this path. Deals no damage, no rewards;
			-- recast replaces the caster's previous same-type summon. RT is still
			-- charged (the skill was paid for) whether or not placement succeeds.
			if skillDef.isSummon then
				spawnSummonFor(actor, skillDef, target, state)
				BattleCoordinator.AccrueRt(state, baseRtCost)
			else
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
			end  -- close: if skillDef.isSummon then (summon) else (ground/tile)

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
			_primaryTargetDamage = actualDmg or outcome.finalDamage or 0
			BattleCoordinator.AccrueRt(state, baseRtCost)

			-- Perks & Flaws (Phase 2b): RT-delay-inflicted trait multiplier (Time Locker etc.)
			local rawDelay = (actor.weaponRtDelay or 0) * TraitEffectService.GetRtDelayInflictMultiplier(actor)
			if rawDelay > 0 and target.isAlive then
				local targetVit = target.effectiveStats and target.effectiveStats.VIT or 10
				local actualDelay = GameConstants.CalcRtDelayResistance(math.round(rawDelay), targetVit)
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

		-- Counter-attack trigger (ALL offensive skill patterns): if the PRIMARY
		-- target is an enemy unit holding a CounterStance and the attacker is in
		-- its weapon reach, it ripostes. Placed after the whole skill-pattern block
		-- so Cleave/Chain/AOE/InheritWeapon damaging skills provoke it too — not
		-- only single-target. Gated to offensive unit-targeted skills: healing,
		-- self-buff, ally-buff, and ground-target skills never provoke a counter.
		-- Only a skill that dealt DIRECT DAMAGE to the primary target provokes a
		-- counter (any pattern); zero-damage/status-only skills never do.
		-- Counter only if the skill dealt DIRECT DAMAGE to the primary target (the
		-- stance-holder). _primaryTargetDamage is captured per-branch above; it is 0
		-- for zero-damage/status-only/self/ally/ground skills (no counter).
		if not skillDef.isHealing and target and target.id and not target.isGroundTarget then
			CommandService.TriggerCounterIfEligible(target, actor, state, false, false, _primaryTargetDamage > 0)
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
			+ TraitEffectService.GetGuardMitigationBonus(actor) -- TRAIT-GUARD (Guard Specialist / Klutz, additive like Golem)
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

	elseif actionType == "Interact" then
		-- INTERACT: the universal Head-slot action (1 AP). Four NATIVE target
		-- kinds; headgear passives ENHANCE the magnitudes (nil-safe hooks below,
		-- default to native baseline until Head passives are wired):
		--   recruitEnemy — enemy at <= threshold HP becomes a NEUTRAL
		--   allyRtHelp   — living ally: current RT cut by 35% of current
		--   reviveAlly   — KO'd ally: CHANNELED (200 CT) resuscitate at 5% HP
		--   mapObject    — PARKED (Slice 5 populates state.objects)
		-- All RT costs are a percentage of Modified Base RT (incl. armor WT).
		local sel = selection
		if type(sel) ~= "table" then
			return false, "Interact requires a selection."
		end

		-- Re-validate server-side: the chosen target must be a current Interact
		-- candidate (reach, side, HP threshold, tier eligibility all re-checked).
		local candidates = TargetingService.GetInteractCandidates(actor, state.units, state)
		local chosen = nil
		for _, c in ipairs(candidates) do
			if sel.interactKind == "mapObject" then
				if c.interactKind == "mapObject" and sel.objectId
					and (c.objectId == sel.objectId) then
					chosen = c; break
				end
			elseif c.id and sel.targetId and c.id == sel.targetId
				and c.interactKind == sel.interactKind then
				chosen = c; break
			end
		end
		if not chosen then
			return false, "No valid Interact target for that selection."
		end

		local modBaseRt = StatusService.GetModifiedBaseRt(actor)
		-- Interact RT multiplier hook: HD-001 Quickhand Hood → ×0.75 (nil-safe → 1.0).
		local interactRtMult = 1.0
		if ArmorPassiveService.GetInteractRtMultiplier then
			interactRtMult = ArmorPassiveService.GetInteractRtMultiplier(actor) or 1.0
		end

		if chosen.interactKind == "recruitEnemy" then
			-- Find the target unit.
			local target = nil
			for _, u in ipairs(state.units) do
				if u.id == chosen.id then target = u; break end
			end
			if not target or not target.isAlive then
				return false, "Recruit target is invalid."
			end
			-- Native recruit RT = 10% of Modified Base RT.
			local rt = math.round(modBaseRt * 0.10 * interactRtMult)
			rt = math.round(rt * StatusService.GetAllRtMultiplier(actor))
			BattleVisualBroadcaster.ActionAnnounced(actor, "Interact")
			BattleCoordinator.AccrueRt(state, rt)
			-- Convert to a controllable NEUTRAL for the rest of the battle.
			-- Here we only flip the in-battle allegiance. Battle-end purification +
			-- roster hand-off: GuildMenuService.AdoptBattleRecruits (rule 133).
			target.side = "Neutral"
			target.controller = "Player"
			target.recruited = true
			-- HD-006 Diplomat's Veil: heal 35% max HP on recruit (nil-safe → none).
			if ArmorPassiveService.GetRecruitHealFraction then
				local healFrac = ArmorPassiveService.GetRecruitHealFraction(actor) or 0
				if healFrac > 0 then
					target.currentHp = math.min(target.maxHp or 1,
						(target.currentHp or 0) + math.ceil((target.maxHp or 1) * healFrac))
				end
			end
			BattleVisualBroadcaster.UnitStateChanged(target)
			print(string.format(
				"[CommandService] INTERACT RECRUIT | %s recruits %s -> Neutral | RT:%d | AP left:%d",
				actor.name, target.name, rt, actor.currentAp
			))

		elseif chosen.interactKind == "allyRtHelp" then
			local target = nil
			for _, u in ipairs(state.units) do
				if u.id == chosen.id then target = u; break end
			end
			if not target or not target.isAlive then
				return false, "Ally target is invalid."
			end
			-- Native ally RT help: reduce target's CURRENT RT by 35% of current.
			local before = target.remainingRt or 0
			local reduced = before - math.round(before * 0.35)
			-- HD-004 Chronologist Monocle: extra flat −50 after the 35% cut
			-- (nil-safe → 0). Floor at 0.
			if ArmorPassiveService.GetAllyRtFlatBonus then
				reduced = reduced - (ArmorPassiveService.GetAllyRtFlatBonus(actor) or 0)
			end
			target.remainingRt = math.max(0, reduced)
			-- Interact-on-ally RT cost = 50% of Modified Base RT.
			local rt = math.round(modBaseRt * 0.50 * interactRtMult)
			rt = math.round(rt * StatusService.GetAllRtMultiplier(actor))
			BattleVisualBroadcaster.ActionAnnounced(actor, "Interact")
			BattleCoordinator.AccrueRt(state, rt)
			BattleVisualBroadcaster.UnitStateChanged(target)
			print(string.format(
				"[CommandService] INTERACT ALLY-RT | %s aids %s | RT %d->%d | selfRT:%d | AP left:%d",
				actor.name, target.name, before, target.remainingRt, rt, actor.currentAp
			))

		elseif chosen.interactKind == "reviveAlly" then
			local target = nil
			for _, u in ipairs(state.units) do
				if u.id == chosen.id then target = u; break end
			end
			if not target then
				return false, "Revive target is invalid."
			end
			if target.isAlive then
				return false, target.name .. " is not KO'd."
			end
			-- CHANNELED resuscitate (native 200 CT). Reuses the two-timer channel
			-- pipeline: a synthetic skill-shaped descriptor carries interactResolve
			-- so ActivateChanneledSkill applies the revive at the deadline.
			-- HD-017 Rescue Marshal Helm: channel 200 → 130 CT (nil-safe → 200).
			local channelCt = 200
			if ArmorPassiveService.GetReviveChannelCt then
				channelCt = ArmorPassiveService.GetReviveChannelCt(actor) or 200
			end
			-- HD-003 Field Medic Coif: revive HP 5% → 15% (nil-safe → 0.05).
			local reviveHpFrac = 0.05
			if ArmorPassiveService.GetReviveHpFraction then
				reviveHpFrac = ArmorPassiveService.GetReviveHpFraction(actor) or 0.05
			end
			-- Interact-on-KO'd-ally RT cost = 30% of Modified Base RT.
			-- HD-016 Signal Officer Beret: 30% → 15% (nil-safe → 0.30).
			local reviveRtPct = 0.30
			if ArmorPassiveService.GetReviveRtPct then
				reviveRtPct = ArmorPassiveService.GetReviveRtPct(actor) or 0.30
			end
			local reviveSkillDef = {
				id          = "_interact_revive",
				name        = "Resuscitate",
				isHealing   = false,
				channelTime = channelCt,
			}
			BattleCoordinator.StartChanneling(state, actor, {
				skillDef       = reviveSkillDef,
				target         = target,
				mpCost         = 0,
				channelRt      = channelCt,
				interactResolve = "reviveAlly",
				reviveHpFrac   = reviveHpFrac,
			})
			BattleVisualBroadcaster.ChannelStarted(actor, true)
			-- Two-timer: end the turn normally with the revive RT cost.
			local rt = math.round(modBaseRt * reviveRtPct * interactRtMult)
			rt = math.round(rt * StatusService.GetAllRtMultiplier(actor))
			actor.currentAp = 0
			BattleCoordinator.AccrueRt(state, rt)
			BattleCoordinator.EndTurn(state)
			print(string.format(
				"[CommandService] INTERACT REVIVE (CHANNEL) [%s] | %s -> %s | Channel:%d CT | RT:%d",
				reviveSkillDef.name, actor.name, target.name, channelCt, rt
			))
			return true, nil -- turn ended (two-timer); revive resolves at deadline

		elseif chosen.interactKind == "mapObject" then
			-- Slice 5: charge 1 AP + native RT (free vs consumes-action), then
			-- resolve the object's EFFECT via ObjectEffectService. RT fallback is
			-- round(ModBaseRt × 0.10) unless the object defines interactRtPct.
			local objArch = chosen.archetypeId
			local objDef = objArch and ObjectData.Objects and ObjectData.Objects[objArch] or nil
			local activation = objDef and objDef.activation or "Interact (Consumes Action)"
			local objRtPct = (objDef and objDef.interactRtPct) or 0.10
			local rt = math.round(modBaseRt * objRtPct * interactRtMult)
			rt = math.round(rt * StatusService.GetAllRtMultiplier(actor))
			BattleVisualBroadcaster.ActionAnnounced(actor, "Interact")
			-- "Interact (Free)" objects do not accrue RT; "Consumes Action" do.
			if activation ~= "Interact (Free)" then
				BattleCoordinator.AccrueRt(state, rt)
			end
			-- Reconstruct the object instance identity for the effect dispatcher.
			-- Candidate carries objectId/archetypeId/tileX/tileY; the dispatcher
			-- (and its usage ledger) expects { id, type, x, y }.
			local objInstance = {
				id   = chosen.objectId,
				type = objArch,
				x    = chosen.tileX,
				y    = chosen.tileY,
			}
			local effOk, effReason =
				ObjectEffectService.Resolve(actor, objInstance, state, state.units)
			print(string.format(
				"[CommandService] INTERACT OBJECT | %s -> %s | activation:%s | RT:%d | effect:%s",
				actor.name, tostring(objArch), activation,
				(activation == "Interact (Free)") and 0 or rt,
				effOk and "ok" or ("FAILED: " .. tostring(effReason))
			))

		elseif chosen.interactKind == "eventNpc" then
			-- BATTLEFIELD-EVENT NPC (2026-10-04): authored event interaction
			-- (DB rule 131 — event-defined, not native). Native-style cost: 1 AP
			-- (charged at STEP 8) + RT 10% of Modified Base RT (same basis as
			-- recruit/map-object). The EFFECT is resolved by the injected
			-- BattlefieldEventService.ResolveInteract (nil-safe).
			local target = nil
			for _, u in ipairs(state.units) do
				if u.id == chosen.id then target = u; break end
			end
			if not target or not target.isAlive then
				return false, "Event NPC target is invalid."
			end
			local rt = math.round(modBaseRt * 0.10 * interactRtMult)
			rt = math.round(rt * StatusService.GetAllRtMultiplier(actor))
			BattleVisualBroadcaster.ActionAnnounced(actor, "Interact")
			BattleCoordinator.AccrueRt(state, rt)
			local evOk, evReason = true, "no event resolver wired"
			if _eventNpcResolver then
				evOk, evReason = _eventNpcResolver(actor, target, state)
			end
			print(string.format(
				"[CommandService] INTERACT EVENT-NPC | %s -> %s | RT:%d | effect:%s",
				actor.name, target.name, rt, evOk and "ok" or ("FAILED: " .. tostring(evReason))
			))

		else
			return false, "Unknown Interact kind: " .. tostring(chosen.interactKind)
		end

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
	-- Phase 3 Momentum (TRAIT-P-162): if this action's KO set pendingKoApGain and Momentum
	-- hasn't fired this turn, grant +1 AP HERE — before the zero-AP end-turn check — so a
	-- kill made with the unit's LAST AP keeps the turn open with a usable bonus AP. Once
	-- per turn (guard flag); the per-turn flags reset at turn start in BattleCoordinator.
	if (actor.pendingKoApGain or 0) > 0 and not actor.momentumUsedThisTurn and actor.isAlive then
		actor.currentAp = (actor.currentAp or 0) + 1
		actor.momentumUsedThisTurn = true
		actor.pendingKoApGain = 0
		print(string.format("[CommandService] Momentum: %s gains +1 AP on KO (now %d)", actor.name, actor.currentAp))
	end
	if actor.currentAp <= 0 then
		BattleCoordinator.EndTurn(state)
	end

	return true, nil
end

return CommandService