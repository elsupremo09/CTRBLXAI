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
local EquipmentService  = require(script.Parent.EquipmentService) -- Steal/Mug theft strip (2026-10-24)
local BattleCoordinator = require(script.Parent.BattleCoordinator)
local StatusService     = require(script.Parent.StatusService)
local BattleVisualBroadcaster = require(script.Parent.BattleVisualBroadcaster)
local DisplacementService = require(script.Parent.DisplacementService)
local RacePassiveService  = require(script.Parent.RacePassiveService)
local TraitEffectService  = require(script.Parent.TraitEffectService) -- Perks & Flaws Phase 2
local DoctrinePassiveService = require(script.Parent.DoctrinePassiveService)
local ArmorPassiveService = require(script.Parent.ArmorPassiveService)
local WeaponPassiveService = require(script.Parent.WeaponPassiveService) -- weapon native GuardBonus (2026-10-26)
local AugmentEffectService = require(script.Parent.AugmentEffectService)
local ObjectEffectService = require(script.Parent.ObjectEffectService)
local ObjectiveService    = require(script.Parent.ObjectiveService)
local ItemEffectService = require(script.Parent.ItemEffectService) -- consumable effect dispatcher (2026-10-26)

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

-- Wire the consumable effect dispatcher with the modules CommandService already holds
-- (injection keeps ItemEffectService cycle-free: it requires nothing that requires us).
ItemEffectService.Init({
	UnitSchema          = UnitSchema,
	StatusService       = StatusService,
	CombatResolver      = CombatResolver,
	GameConstants       = GameConstants,
	TraitEffectService  = TraitEffectService,
	ArmorPassiveService = ArmorPassiveService,
	TargetingService    = TargetingService,
	ObjectData          = ObjectData,
	ConsumableData      = ConsumableData,
})

local CommandService = {}

-- Optional: TileEffectService injected at runtime
local _tileEffectService = nil
function CommandService.SetTileEffectService(tes: any)
	_tileEffectService = tes
	-- Forward the same live TileEffectService to the map-object effect dispatcher.
	ObjectEffectService.SetTileEffectService(tes)
end

-- SUMMON SPAWNER (injected by Main, mirrors SetTileEffectService). Injection keeps
-- CommandService free of a hard require on EnemyGenerator (cycle-free, same pattern
-- as _tileEffectService / _eventNpcResolver). nil-safe: with no generator wired a
-- summon skill charges its cost and no-ops (logged), never crashes.
local _enemyGenerator = nil
function CommandService.SetEnemyGenerator(eg: any)
	_enemyGenerator = eg
end

-- PulseScheduler injection (2026-10-26): lets the Item deploy path register fixed-CT
-- pulses (Healing Beacon, Poison Cloud, delayed-burst damage) without a hard require
-- on the scheduler. Cycle-free; nil-safe (no scheduler wired -> pulse items defer).
local _pulseScheduler = nil
function CommandService.SetPulseScheduler(ps: any)
	_pulseScheduler = ps
	ItemEffectService.SetPulseScheduler(ps)
	-- Timed item damage follows the normal damage rules (user ruling 2026-10-26).
	if ps and ps.SetHitResolver then
		ps.SetHitResolver(ItemEffectService.ResolveTimedHit)
	end
end

-- WeatherService injection (2026-10-26): lets the Item branch run Battlefield weather
-- beacons (Rain/Sun/Storm) via WeatherService.ForceCondition without a hard require.
-- Cycle-free; nil-safe (no service wired -> weather items defer).
local _weatherService = nil
function CommandService.SetWeatherService(ws: any)
	_weatherService = ws
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
	["AUG-SOUL-ECHO"] = {  -- Soul Echo (augment): 1-HP delayed bomb; cannot act, detonates on its own turn
		type = "SoulEcho", displayName = "Soul Echo", profile = "idle",
		fixedHp = 1, inheritsNoStats = true,
		multiInstance = true,  -- no-cap/add (2026-10-26): spawnSummonFor must NOT retire prior echoes
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

-- Map size (set by Main via SetMapDimensions). Declared ABOVE findEmptySummonTile:
-- it was previously declared further down, so that function read empty globals.
local _mapWidth  = 8
local _mapHeight = 8

-- Find an empty, in-bounds, unoccupied tile as close to the caster as possible
-- (expanding Chebyshev rings). Mirrors the Summon Runtime Engine "Validate
-- placement" step (status_summon_engines): tile must be legal + unoccupied.
local function findEmptySummonTile(actor: any, state: any)
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
	return nil, nil
end

-- Resolve a summon skill: compute the authored caster-% stats, place on an empty
-- tile on the CASTER's side, enforce one-per-caster-per-type (replace previous),
-- spawn via the existing EnemyGenerator.SpawnSummon, broadcast UnitSpawned. Deals
-- NO damage and grants NO rewards (flags set inside SpawnSummon). Returns ok, info.
-- Per status_summon_engines: create the NEW summon FIRST, then retire the previous
-- one (never delete-before-create); if placement fails, the existing summon stays.
local function spawnSummonFor(actor: any, skillDef: any, target: any, state: any): (boolean, any)
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

	-- Perks & Flaws (2026-10-23): Minion Specialist / Skill Issues on the CASTER scale the
	-- summon's stats and outgoing damage. Read once here (owner's trait locked at creation).
	local summonStatMult, summonDamageMult = TraitEffectService.GetSummonModifiers(actor)

	-- Build the authored stat table (caster-% snapshot). Each summon stat derives
	-- from the caster stat named in statSrc (default: same-named stat).
	local stats
	if not prof.inheritsNoStats then
		stats = {}
		for _, k in ipairs({ "STR", "AGI", "INT", "VIT", "DEX", "LUK" }) do
			local pct = prof.statPct and prof.statPct[k] or 0
			local srcKey = (prof.statSrc and prof.statSrc[k]) or k
			local srcVal = cStats[srcKey] or 10
			stats[k] = math.max(1, math.round(srcVal * pct * summonStatMult))
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
		summonDamageMult = summonDamageMult, -- Minion Specialist / Skill Issues (owner trait, 2026-10-23)
	}

	-- CREATE NEW FIRST (status_summon_engines "Replace existing": never delete the
	-- previous summon before the new one is successfully created).
	local newUnit = _enemyGenerator.SpawnSummon(summonSpec, { x = sx, y = sy }, state)
	if not newUnit then
		warn(string.format("[CommandService] SUMMON [%s] SpawnSummon failed — existing summon (if any) kept", tostring(skillDef.id)))
		return false, "Spawn failed."
	end
	-- Minion Specialist / Skill Issues (2026-10-23): stamp the owner's outgoing-damage
	-- multiplier onto the created summon (stat scaling already applied at creation above).
	-- Read by CombatResolver on the summon's attacks. Default 1 is a harmless no-op.
	if summonDamageMult and summonDamageMult ~= 1 then
		newUnit.summonDamageMult = summonDamageMult
	end

	-- RETIRE the caster's PREVIOUS same-type summon (one-at-a-time). Done only after
	-- the new one exists. Mark KO'd + remove from roster; broadcast its removal.
	local retired = 0
	for i = #state.units, 1, -1 do
		local u = state.units[i]
		if not prof.multiInstance and u ~= newUnit and u.isSummon and u.summonOwnerId == actor.id
			and u.summonType == prof.type then
			u.isAlive = false
			u.currentHp = 0
			-- UnitKilled never existed; remove the replaced summon's token explicitly (2026-10-26).
			BattleVisualBroadcaster.UnitRemoved(u)
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

-- ITEM DEVICE SPAWN (2026-10-26). A summon-kind deployable places a real, targetable
-- device unit on the chosen empty tile. Devices never act (Main skips their turns);
-- what they do comes from authored data via ItemEffectService.GetDevicePlan:
--   HP      : Device_Hp_Formula, else the matching summon profile's default HP
--   lifespan: Device_Lifespan_Ct (PulseScheduler removes it), else until destroyed
--   aura    : Device_Aura_* (StatusService reads it live: stability, teleport lock)
--   pulses  : Pulse_* anchored to the device (fire from its tile, stop when it dies)
-- One per type per user (user ruling): a new device replaces the same user's previous
-- device from the same item, AFTER the new one exists. Returns an effectResult table.
local function spawnItemDevice(actor: any, def: any, plan: any, target: any, state: any): any
	if not _enemyGenerator or not _enemyGenerator.SpawnSummon then
		warn("[CommandService] ITEM DEVICE: EnemyGenerator not injected -- spawn no-op")
		return { effectType = "DeployFailed", amount = 0, description = "device spawner not wired" }
	end
	local tx, ty = target.tileX, target.tileY
	if _enemyGenerator.IsSpawnTileFree and not _enemyGenerator.IsSpawnTileFree(state, tx, ty) then
		print(string.format("[CommandService] ITEM DEVICE [%s] | tile (%d,%d) not free", def.name, tx, ty))
		return { effectType = "DeployFailed", amount = 0, description = "placement blocked at target tile" }
	end
	local maxHp = plan.maxHp
	if not maxHp then
		for _, prof in pairs(SUMMON_PROFILES) do
			if prof.type == plan.summonType then
				maxHp = prof.fixedHp or math.max(1, math.round((actor.maxHp or 1) * (prof.hpPct or 0)))
				break
			end
		end
	end
	if not maxHp then
		warn(string.format("[CommandService] ITEM DEVICE [%s] has no HP source -- spawn aborted", def.name))
		return { effectType = "DeployFailed", amount = 0, description = "no authored device HP" }
	end
	local newUnit = _enemyGenerator.SpawnSummon({
		id = "DEV_" .. tostring(def.name):gsub("%W", "") .. "_" .. tostring(actor.id or "user"),
		name = def.name,
		side = actor.side,
		level = actor.level or 1,
		stats = { STR = 1, AGI = 1, INT = 1, VIT = 1, DEX = 1, LUK = 1 },  -- devices inherit no stats
		maxHp = maxHp,
		weaponDamage = 0,
		summonType = plan.summonType,  -- "Decoy" keeps the AI's Decoy priority
		summonOwnerId = actor.id,
		summonProfile = "idle",
		canMove = false,
		isFlying = false,
		auraSpec = plan.auraSpec,
	}, { x = tx, y = ty }, state)
	if not newUnit then
		return { effectType = "DeployFailed", amount = 0, description = "device spawn failed" }
	end
	newUnit.isItemDevice = true
	newUnit.deviceItemId = def.name
	newUnit.deviceLifeCt = plan.lifespanCt
	newUnit.deviceLifeMax = plan.lifespanCt  -- Maintenance Tool / Repair restore target
	-- Light gadget: its HP pool is a hit counter (UnitSchema.ApplyDamage removes 1 per hit).
	newUnit.fixedHitDurability = plan.fixedHits or nil

	-- One per type: retire this user's previous device from the same item.
	local replaced = 0
	for i = #state.units, 1, -1 do
		local u = state.units[i]
		if u ~= newUnit and u.isItemDevice and u.summonOwnerId == actor.id and u.deviceItemId == def.name then
			u.isAlive = false
			u.currentHp = 0
			-- UAT advisory fix: UnitKilled does not exist; remove the token explicitly.
			BattleVisualBroadcaster.UnitRemoved(u)
			table.remove(state.units, i)
			replaced += 1
		end
	end

	if plan.pulse and _pulseScheduler and _pulseScheduler.Register then
		_pulseScheduler.Register(state, {
			ownerId = actor.id,
			side = actor.side,
			tileX = tx, tileY = ty,
			anchorUnitId = newUnit.id,
			kind = plan.pulse.kind,
			recipients = plan.pulse.recipients,
			radius = plan.pulse.radius,
			amount = plan.pulse.amount,
			element = plan.pulse.element,
			intervalCt = plan.pulse.intervalCt,
			pulses = plan.pulse.pulses,
			targetMode = plan.pulse.targetMode,
			requiresLoS = plan.pulse.requiresLoS,
			fireImmediate = plan.pulse.fireImmediate,  -- drones reveal on placement
			itemId = def.name,
		})
	end

	if BattleVisualBroadcaster.UnitSpawned then
		BattleVisualBroadcaster.UnitSpawned(newUnit)
	end
	print(string.format(
		"[CommandService] ITEM DEVICE [%s] | %s placed %s at (%d,%d) | HP=%d | life=%s | pulse=%s | replaced %d",
		def.name, actor.name, plan.summonType, tx, ty, newUnit.maxHp, tostring(plan.lifespanCt),
		plan.pulse and string.format("%s x%d/%dCT amt %d", plan.pulse.kind, plan.pulse.pulses or 0,
			plan.pulse.intervalCt or 0, plan.pulse.amount or 0) or "none", replaced))
	return { effectType = "Deploy", amount = 0, description = def.name .. " placed", deviceUnit = newUnit }
end

-- REPAIR AT TILE (2026-10-26). Item devices are units, not objects, so the object repair
-- alone never reached them. A device on the tile gets full HP (or its full 3-hit counter),
-- its original lifespan back and its timed effects refilled (turret shots, drone heals).
-- Otherwise a breakable object there is repaired; deployableOnly limits that to objects
-- placed by Deployable items (Maintenance Tool). Returns what was repaired, or nil.
local function repairAtTile(state: any, x: any, y: any, deployableOnly: boolean): any
	for _, u in ipairs(state.units or {}) do
		if u.isAlive and u.isItemDevice and u.tileX == x and u.tileY == y then
			u.currentHp = u.maxHp
			if u.deviceLifeMax then u.deviceLifeCt = u.deviceLifeMax end
			if _pulseScheduler and _pulseScheduler.RefreshByAnchor then
				_pulseScheduler.RefreshByAnchor(state, u.id)
			end
			BattleVisualBroadcaster.UnitStateChanged(u)
			print(string.format("[CommandService] REPAIR | device %s at (%d,%d) fully restored", tostring(u.name), x, y))
			return u.name
		end
	end
	if deployableOnly then
		local ok = false
		for _, inst in ipairs(state.objects or {}) do
			if inst.x == x and inst.y == y then
				local d = inst.type and ObjectData.Objects[inst.type]
				ok = d ~= nil and d.isDeployable == true
				break
			end
		end
		if not ok then return nil end
	end
	return ObjectEffectService.RepairObjectAt(state, x, y)
end

-- Soul Echo (AUG-SOUL-ECHO) spawn helper (2026-10-26). Called at EVERY kill site (single-target +
-- each AOE loop) so a kill by a Soul-Echo-augmented Direct-Damage skill drops a 1-HP echo on the
-- victim's tile that detonates next turn for 30% of the kill damage as Dark AOE (detonation handled
-- in Main's summon-turn branch). "No cap / add" (user decision 2026-10-26): the AUG-SOUL-ECHO profile
-- is multiInstance, so spawnSummonFor does NOT retire prior echoes -- a multi-kill AOE leaves one echo
-- per slain enemy and they coexist. Self-contained: re-checks the augment + that the victim actually
-- died, so callers only need to invoke it after an ApplyOutcome on a unit that was alive pre-hit.
local function trySpawnSoulEcho(actor: any, skillDef: any, victim: any, killDamage: any, state: any)
	if not (actor and actor.isAlive and victim and skillDef and skillDef.id and state) then return end
	if victim.isAlive then return end  -- only on a genuine kill
	-- Kill-credit rule (2026-10-26): no echo from allies, neutrals, summons or revived units.
	if not AugmentEffectService.IsKillCreditEligible(actor, victim) then return end
	-- Pure heals/shields never spawn echoes. Damage skills that also heal (Siphon Pulse's lifedrain,
	-- card tag "Direct Damage") do: Soul Echo fires on every kill (AugmentData, UAT 2026-10-27).
	local _damaging = false
	for _, tag in ipairs(skillDef.tags or {}) do
		if tag == "Direct Damage" then _damaging = true break end
	end
	if (skillDef.power or 0) <= 0 or skillDef.isShield or (skillDef.isHealing and not _damaging) then return end
	if not AugmentEffectService.GetAugmentsForSkill then return end
	local has = false
	for _, a in ipairs(AugmentEffectService.GetAugmentsForSkill(actor, skillDef.id)) do
		if a == "AUG-SOUL-ECHO" then has = true break end
	end
	if not has then return end
	local echoDmg = math.max(1, math.round((killDamage or 0) * 0.30))
	local okE, resE = spawnSummonFor(actor, { id = "AUG-SOUL-ECHO" }, victim, state)
	if okE and type(resE) == "table" and resE.summon then
		resE.summon._soulEchoDamage = echoDmg
		resE.summon._soulEchoOwnerId = actor.id
		print(string.format("[CommandService] Soul Echo: %s leaves an echo on %s's tile (~%d Dark next turn)",
			actor.name, victim.name or "?", echoDmg))
	end
end

-- Battlefield-event NPC Interact resolver (2026-10-04). Injected by Main as
-- BattlefieldEventService.ResolveInteract — injection (not a require) keeps
-- CommandService free of any dependency on the event engine (cycle-free).
-- fn(actor, target, state) -> ok:boolean, reason:string?
-- nil-safe: with no resolver wired, an eventNpc Interact charges cost and no-ops.
local _eventNpcResolver = nil
function CommandService.SetEventNpcResolver(fn: any)
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
local function applyForcedEntryEffects(target: any, result: any)
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
-- SHARED POST-HIT EFFECTS (2026-10-07). One copy used by the INSTANT skill path,
-- the CHANNEL/ACTIVATION (delayed) path and the Giant basic-attack knockback, so a
-- delayed skill gets exactly the same RT delay / knockback / swap as an instant one.
--------------------------------------------------

-- Melee knockback through DisplacementService (Force - Stability). Applies the
-- position change, wall/fall damage, collided-unit damage, landing-tile effects
-- and the UnitPushed broadcast. Returns the push result (or nil).
local function applyKnockback(state: any, actor: any, target: any, force: number, label: string, dirOverride: any, requestedDistance: any, stabilityIgnore: any, pullOverride: any)
	if not (target and target.isAlive) then return nil end
	-- dirOverride (optional): explicit {dx,dy} push direction. Used by FT-019 Kick Boots to knock the
	-- enemy in ITS OWN facing direction. When nil, falls back to the standard away-from-attacker push.
	local direction = dirOverride or DisplacementService.GetPushDirection(actor, target)
	local result = DisplacementService.ResolvePush(
		actor, target, force, direction,
		GameConstants.KNOCKBACK_SOURCE_MODIFIERS.SkillKnockback, state.units,
		requestedDistance, false, stabilityIgnore  -- optional: Magnetic Snare (2026-10-26)
	)
	-- A PULL (direction toward the actor) whose first step is already blocked by a unit --
	-- normally the user, when the target stands next to them -- still collides: both units
	-- take normal collision damage (user ruling 2026-10-26: "a pull that hits you hurts";
	-- DB GL-005 edge-case rule). Pushes keep the old behaviour (no change).
	-- pullOverride (optional, DEFECT-2 fix 2026-10-26): callers whose pull centre is NOT the
	-- actor's tile (Vortex Strike pulls toward an impact centre) say explicitly whether this is
	-- a pull. Otherwise: a pull is a direction pointing toward the actor.
	local _isPull = if pullOverride ~= nil then (pullOverride == true) else (((direction.dx * ((actor.tileX or 0) - (target.tileX or 0)))
		+ (direction.dy * ((actor.tileY or 0) - (target.tileY or 0)))) > 0)
	local _pullBlocked = _isPull and result ~= nil and not result.pushed
		and result.wallCollision ~= nil and result.wallCollision.collidedUnitId ~= nil
	if result and (result.pushed or _pullBlocked) then
		target.tileX = result.finalTileX
		target.tileY = result.finalTileY
		-- Forced-movement trap trigger (2026-10-20): a knockback that drags the
		-- target across step-on trap tiles springs each one. Actor-targeted effects
		-- (Pinned/Bleed/RT/direct damage) apply to the pushed unit; a Land Mine
		-- detonates at its tile. Forced momentum does NOT stop early (only a KO ends
		-- the unit). Walks the crossed-tile list ResolvePush now returns.
		if ObjectEffectService and result.tilesPath then
			for _, tp in ipairs(result.tilesPath) do
				local trap = ObjectEffectService.GetTriggeredTrapAt(state, tp.x, tp.y)
				if trap then ObjectEffectService.TriggerTrap(target, trap, state, state.units) end
			end
		end
		local knockDmg = 0
		if result.wallCollision and result.wallCollision.damage > 0 then
			knockDmg = knockDmg + result.wallCollision.damage
		end
		if result.fallDamage and result.fallDamage > 0 then
			knockDmg = knockDmg + result.fallDamage
		end
		if knockDmg > 0 and target.isAlive then
			UnitSchema.ApplyDamage(target, knockDmg, "push")
			-- Objective "Pusher": a push/collision/fall KO is credited to the pusher.
			if not target.isAlive then target._killedBy = target._killedBy or actor.id end
		end
		if result.pushed then  -- a blocked pull did not enter a new tile
			applyForcedEntryEffects(target, result)
		end
		if result.wallCollision
			and result.wallCollision.collidedUnitId
			and result.wallCollision.collidedUnitDamage
			and result.wallCollision.collidedUnitDamage > 0
		then
			for _, u in ipairs(state.units) do
				if u.id == result.wallCollision.collidedUnitId and u.isAlive then
					UnitSchema.ApplyDamage(u, result.wallCollision.collidedUnitDamage, "push")
					if not u.isAlive then u._killedBy = u._killedBy or actor.id end
					break
				end
			end
		end
		BattleVisualBroadcaster.UnitPushed(actor, target, result)
		print(string.format(
			"[CommandService] %s KNOCKBACK | %s -> %s | Moved:%d to (%d,%d) | Dmg:%d",
			label, actor.name, target.name, result.tilesDisplaced,
			result.finalTileX, result.finalTileY, knockDmg
		))
	end
	return result
end

-- AUGMENT DISPLACEMENT (2026-10-26): AugmentEffectService has no battle state, so it calls
-- this (injected by Main) to run the shared knockback. The state is the one most recently
-- handed to AugmentEffectService.SetBattleUnits (same skill / attack resolution).
local _augKnockState: any = nil
function CommandService.ApplyAugmentKnockback(pusher: any, target: any, force: any, dir: any, distance: any, isPull: any): any
	if not (_augKnockState and pusher and target and target.isAlive and dir) then return nil end
	return applyKnockback(_augKnockState, pusher, target, force or 1, "AUGMENT", dir, distance, nil, isPull)
end

-- RESCUE BEACON (DEP-016, 2026-10-26, user-approved). Called by Main before every
-- battle-end check (BattleCoordinator.SetKoHook). For each placed beacon: the first unit of
-- the beacon's side KO'd within rescueRadius AFTER placement (not a summon, not a device)
-- is moved to the first free tile next to the beacon (N, NE, E, SE, S, SW, W, NW) and
-- revived at rescueHpPct of Max HP with rescueRt RT. The beacon is then used up. No free
-- tile next to it -> nothing happens this time (it tries again on the next check).
-- Returns { {unit, oldX, oldY}, ... } so Main can re-label tiles.
local RESCUE_DIRS = { { 0, -1 }, { 1, -1 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 } }
function CommandService.ProcessRescueBeacons(state: any): any
	local out = {}
	if not (state and state.objects and state.units) then return out end
	for i = #state.objects, 1, -1 do
		local inst = state.objects[i]
		local def = inst and inst.type and ObjectData.Objects[inst.type]
		if def and def.rescueRadius and inst.ownerSide and inst.x then
			local victim = nil
			for _, u in ipairs(state.units) do
				if not u.isAlive and u.side == inst.ownerSide and not u.isSummon and not u.isItemDevice
					and not (inst.ignoreKo and inst.ignoreKo[u.id]) and u.tileX
					and math.max(math.abs(u.tileX - inst.x), math.abs(u.tileY - inst.y)) <= def.rescueRadius then
					victim = u
					break
				end
			end
			local spot = nil
			if victim then
				for _, d in ipairs(RESCUE_DIRS) do
					local x, y = inst.x + d[1], inst.y + d[2]
					local free = x >= 1 and y >= 1 and x <= _mapWidth and y <= _mapHeight
						and not GameConstants.IsBlocked(x, y) and not GameConstants.IsImpassableTerrain(x, y)
						and not (GameConstants.IsChasmFloor and GameConstants.IsChasmFloor(x, y))
					if free then
						for _, o in ipairs(state.units) do
							if o.isAlive and o.tileX == x and o.tileY == y then free = false break end
						end
					end
					if free then spot = { x = x, y = y } break end
				end
			end
			if victim and spot then
				local ox, oy = victim.tileX, victim.tileY
				victim.tileX, victim.tileY = spot.x, spot.y
				victim.isAlive = true
				victim._revivedThisBattle = true  -- same kill-credit rule as the Interact revive
				local maxHp = victim.maxHp or 1
				victim.currentHp = math.min(maxHp, math.max(1, math.ceil(maxHp * (def.rescueHpPct or 0.15))))
				victim.remainingRt = def.rescueRt or 400
				BattleVisualBroadcaster.UnitSpawned(victim)       -- re-create the token if it was removed
				BattleVisualBroadcaster.UnitStateChanged(victim)  -- client restores a greyed KO body
				BattleVisualBroadcaster.UnitMoved(victim)
				BattleVisualBroadcaster.Log("ko", `Rescue Beacon revives {victim.name} ({victim.currentHp}/{maxHp} HP).`, victim.id)
				ObjectEffectService.RemoveObjectInstance(state, inst)
				if BattleVisualBroadcaster.ObjectChanged then
					BattleVisualBroadcaster.ObjectChanged(inst.x, inst.y, { destroyed = true })
				end
				print(string.format("[CommandService] RESCUE BEACON | %s revived at (%d,%d) %d HP, RT %d",
					victim.name, spot.x, spot.y, victim.currentHp, victim.remainingRt))
				table.insert(out, { unit = victim, oldX = ox, oldY = oy })
			end
		end
	end
	return out
end

-- Single-target skill post-hit: weapon RT delay (Time Locker trait scaling, target
-- VIT resistance) and authored skill knockback (skillDef.knockbackOnHit = +N Force,
-- only after successful HP damage, e.g. Overwhelming Blow DB 'Knockback +1').
local function applySkillPostHit(state: any, actor: any, target: any, skillDef: any, dealtDamage: number?)
	if not target or target.isGroundTarget then return end
	local rawDelay = GameConstants.CalcRtDelayBonus(actor.weaponRtDelay or 0, (actor.effectiveStats and actor.effectiveStats.STR) or 10) * TraitEffectService.GetRtDelayInflictMultiplier(actor)
	if rawDelay > 0 and target.isAlive then
		local targetVit = target.effectiveStats and target.effectiveStats.VIT or 10
		local actualDelay = GameConstants.CalcRtDelayResistance(math.round(rawDelay), targetVit, (target.gearDerived and target.gearDerived.rtDelayResist or 1))
		target.remainingRt = target.remainingRt + math.max(0, actualDelay)
	end
	if skillDef.knockbackOnHit and (dealtDamage or 0) > 0 and target.isAlive and actor.isAlive then
		local force = (actor.derivedStats and actor.derivedStats.force or 1) + skillDef.knockbackOnHit
		applyKnockback(state, actor, target, force, "SKILL")
	end
end

-- Position swap with the selected ally (Phantom Exchange: 'the swap uses the
-- selected ally's occupied tile'). Voluntary teleport: no forced-entry effects.
local function applySwap(actor: any, target: any): boolean
	if not (target and target.isAlive and actor.isAlive) or target.id == actor.id then return false end
	-- Steadfast Strike (2026-10-24): a displacement-immune unit cannot be swapped.
	if actor._displacementImmune or target._displacementImmune then return false end
	-- Gravity Pylon aura (2026-10-26): a unit inside a teleport-lock aura cannot swap.
	if StatusService.IsTeleportLocked(actor) or StatusService.IsTeleportLocked(target) then
		print(`[CommandService] SWAP blocked | {actor.name} / {target.name} inside a teleport-lock aura`)
		return false
	end
	local ax, ay = actor.tileX, actor.tileY
	actor.tileX, actor.tileY = target.tileX, target.tileY
	target.tileX, target.tileY = ax, ay
	BattleVisualBroadcaster.UnitMoved(actor)
	BattleVisualBroadcaster.UnitMoved(target)
	print(`[CommandService] SWAP | {actor.name} <-> {target.name} | now ({actor.tileX},{actor.tileY}) / ({target.tileX},{target.tileY})`)
	return true
end

-- FEAR (CON-017, user ruling 2026-10-26): a Feared unit spends its FIRST AP moving
-- toward its OWN side's deployment area, as far as one Move allows. Called by Main at
-- the start of the unit's normal turn. Picks the reachable tile closest (Chebyshev) to
-- any own deployment tile; ties -> lower path cost, then lower x, then lower y. If no
-- reachable tile is closer than where it stands, the AP is still spent (it froze).
-- Returns { moved = bool }.
function CommandService.ApplyFearMove(state: any, unit: any): any
	if not (state and unit and unit.isAlive) or (unit.currentAp or 0) <= 0 then
		return { moved = false }
	end
	local deploy = (unit.side == "Player") and state.playerDeployTiles or state.enemyDeployTiles
	local function distToDeploy(x, y)
		local best = math.huge
		for _, t in ipairs(deploy or {}) do
			local d = math.max(math.abs(x - t.x), math.abs(y - t.y))
			if d < best then best = d end
		end
		return best
	end
	local here = distToDeploy(unit.tileX, unit.tileY)
	local bestTile, bestD, bestCost = nil, here, math.huge
	if deploy and #deploy > 0 then
		for _, c in ipairs(TargetingService.GetMoveCandidates(unit, state.units, _mapWidth, _mapHeight)) do
			local d = distToDeploy(c.tileX, c.tileY)
			local cost = c.pathCost or 0
			local better = d < bestD
				or (bestTile and d == bestD and (cost < bestCost
					or (cost == bestCost and (c.tileX < bestTile.tileX
						or (c.tileX == bestTile.tileX and c.tileY < bestTile.tileY)))))
			if better then
				bestTile, bestD, bestCost = c, d, cost
			end
		end
	end
	if bestTile then
		local ok = CommandService.ValidateAndCommit(state, unit.id, "Move",
			{ tileX = bestTile.tileX, tileY = bestTile.tileY, pathCost = bestTile.pathCost })
		if ok then
			-- D1 fix (UAT 2026-10-26): the forced move must not be undoable, or the player
			-- could Undo it and get the AP back. Mark the Move entry it just pushed as
			-- non-reversible (UndoLastAction refuses entries with reaction = true).
			local e = BattleCoordinator.PeekUndo(state)
			if e and e.kind == "Move" and e.actorId == unit.id then
				e.reaction = true
				e.forcedByFear = true
			end
			print(string.format("[CommandService] FEAR | %s flees to (%d,%d)", unit.name, unit.tileX, unit.tileY))
			return { moved = true }
		end
	end
	-- Could not get closer: the first AP is lost to fear.
	unit.currentAp = math.max(0, (unit.currentAp or 0) - 1)
	print(string.format("[CommandService] FEAR | %s is frozen in fear (first AP lost)", unit.name))
	if unit.currentAp <= 0 then
		CommandService.ValidateAndCommit(state, unit.id, "Wait", nil)
	end
	return { moved = false }
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

-- Card-facing fields always come from Content.SkillData (generated from CTRBLXAI.db), never
-- from the hand-written combat tables (GameConstants.SKILLS, Main's doctrine defs). Tags and
-- Target Rules are what the player reads on the card, so battle must use exactly those
-- (tags-only compatibility + tile targeting, 2026-10-26; DAT-001 single source). The combat
-- table keeps its runtime-only fields (range, aoePattern, power, ...). Skills absent from
-- SkillData (internal skills such as SKL-MENDER-HEAL) keep their own values.
local function withCardFields(skillDef: any): any
	local card = SkillData[skillDef.id]
	if not card then
		return skillDef
	end
	local merged = table.clone(skillDef)
	if type(card.tags) == "table" then
		merged.tags = table.clone(card.tags)
	end
	if card.targetRules then
		merged.targetRules = card.targetRules
	end
	return merged
end

function CommandService.RegisterSkill(skillDef: any)
	assert(
		type(skillDef.id) == "string",
		"RegisterSkill: skillDef must have an id string."
	)
	skillRegistry[skillDef.id] = withCardFields(skillDef)
end

function CommandService.RegisterSkillAlias(aliasKey: any, skillDef: any)
	-- Store the same skillDef under an alias key (e.g. legacy "skill_power_strike")
	skillRegistry[aliasKey] = skillRegistry[skillDef.id] or withCardFields(skillDef)
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

function CommandService.GetSkill(skillId: any)
	return skillRegistry[skillId]
end

function CommandService.GetAllSkills()
	return skillRegistry
end

local function lookupSkill(skillId: any)
	return skillRegistry[skillId]
end

-- Live, targetable unit standing on a tile (nil if the tile is empty). Hidden units are
-- skipped: Hide protects from tile-aimed casts exactly as it does from unit targeting.
-- Used to turn a stat-less ground marker into the real occupant before any resolver reads
-- effectiveStats (crash 2026-10-26: CombatResolver:826 "attempt to index nil with 'VIT'").
local function findLiveTileOccupant(state: any, tileX: any, tileY: any): any
	if not (state and state.units and tileX and tileY) then
		return nil
	end
	for _, u in ipairs(state.units) do
		if u.isAlive and u.tileX == tileX and u.tileY == tileY
			and not StatusService.HasStatus(u, "Hide") then
			return u
		end
	end
	return nil
end

-- Patterns ANCHORED ON A UNIT: single target, Cleave, Chain, and weapon-inherited shapes. Their
-- hit lists start from the primary target unit, so a ground marker must be swapped for the tile's
-- occupant first, or (empty tile) resolved as an empty-tile cast. Tile-area patterns (Circle,
-- Cross, Ring, ...) iterate tiles and are safe with a marker. (BUG-057 second fix, 2026-10-26.)
local function isUnitAnchoredPattern(skillDef: any): boolean
	local p = skillDef.aoePattern
	if p == nil or p == "Cleave" or p == "InheritWeapon" then
		return true
	end
	return type(p) == "string" and string.sub(p, 1, 5) == "Chain"
end

-- Tiles a skill covers, for whole-area ground augments (Wet/Frozen Ground, Poison Cloud; user
-- ruling 2026-10-26: "affected tiles follow the skill's range, area and pattern"). Tile-area
-- patterns return every pattern tile; unit-anchored patterns return the target tile.
local function skillAffectedTiles(caster: any, skillDef: any, centerX: any, centerY: any): { any }
	if not (centerX and centerY) then
		return {}
	end
	local p = skillDef.aoePattern
	if p == "InheritWeapon" then
		p = caster.weaponPattern
	end
	local weaponShape = p == "ImpactSplash" or p == "Line2" or p == "Adjacent"
	if type(p) == "string" and p ~= "Single" and not weaponShape and not isUnitAnchoredPattern({ aoePattern = p }) then
		local ok, tiles = pcall(TargetingService.GetAOETargetTiles, p, caster, centerX, centerY, _mapWidth, _mapHeight)
		if ok and type(tiles) == "table" and #tiles > 0 then
			local out = {}
			for _, t in ipairs(tiles) do
				if t.tileX and t.tileY then
					table.insert(out, { x = t.tileX, y = t.tileY })
				end
			end
			if #out > 0 then
				return out
			end
		end
	end
	return { { x = centerX, y = centerY } }
end

-- Weapon-inherited hit list (ImpactSplash / Line2 / Cleave / Adjacent): primary at 100%, the rest
-- at the pattern's secondary rate. Shared by the instant and channeled paths so they always hit
-- the same units. nil = weapon pattern not an area shape (caller treats it as single target).
local function weaponPatternTargets(actor: any, target: any, units: any, pattern: any): any
	if pattern == "ImpactSplash" then
		return TargetingService.GetImpactSplashTargets(actor, target, units)
	elseif pattern == "Line2" then
		return TargetingService.GetLine2Targets(actor, target, units)
	elseif pattern == "Cleave" or pattern == "Adjacent" then
		local out = {}
		for _, u in ipairs(TargetingService.GetCleaveTargets(actor, target, units)) do
			table.insert(out, { unit = u, dmgMult = if u.id == target.id then 1.0 else 0.5 })
		end
		return out
	end
	return nil
end

-- AREA HEAL (Mending Rain): heal every living unit inside the skill's tile pattern around the
-- chosen tile, any side (tile targeting, 2026-10-26). Same elevation (+/-2) and BlocksAOE rules
-- as damage areas. The chosen tile itself is never resolved as a unit (BUG-057).
local function resolveAreaHealing(caster: any, skillDef: any, centerX: any, centerY: any, state: any): { any }
	local entries = {}
	local tiles = TargetingService.GetAOETargetTiles(skillDef.aoePattern, caster, centerX, centerY, _mapWidth, _mapHeight)
	local centerElev = GameConstants.GetElevation(centerX, centerY)
	for _, tile in ipairs(tiles or {}) do
		if math.abs(GameConstants.GetElevation(tile.tileX, tile.tileY) - centerElev) <= 2
			and not TargetingService.IsAOEBlocked(centerX, centerY, tile.tileX, tile.tileY) then
			for _, u in ipairs(state.units) do
				if u.isAlive and not u.isGroundTarget and u.tileX == tile.tileX and u.tileY == tile.tileY then
					local outcome = CombatResolver.ResolveHealing(caster, u, skillDef)
					local amount = CombatResolver.ApplyOutcome(outcome, u, caster) or 0
					local isHeal = outcome.finalHealing ~= nil
					table.insert(entries, {
						target = u, outcome = outcome,
						healing = if isHeal then amount else 0,
						damage = if isHeal then 0 else amount,  -- Undead healing reversal
					})
				end
			end
		end
	end
	return entries
end

-- AREA LIFEDRAIN (Siphon Pulse; DB SKL-SIPHON-PULSE): damage every unit in the pattern (any side,
-- friendly fire), then the caster heals round(damage dealt to non-allies x 0.30 x (1 + VIT/300)).
-- Dark vs Undead heals them instead and gives the caster nothing. The chosen tile is never a unit.
-- Entries use the AreaHealing shape { target, healing, damage } so the client shows each unit.
local function resolveAreaDrain(caster: any, skillDef: any, centerX: any, centerY: any, state: any): ({ any }, number, number)
	local entries = {}
	local drainable = 0
	local totalDmg = 0
	local kills = {}
	local tiles = TargetingService.GetAOETargetTiles(skillDef.aoePattern, caster, centerX, centerY, _mapWidth, _mapHeight)
	local centerElev = GameConstants.GetElevation(centerX, centerY)
	for _, tile in ipairs(tiles or {}) do
		if math.abs(GameConstants.GetElevation(tile.tileX, tile.tileY) - centerElev) <= 2
			and not TargetingService.IsAOEBlocked(centerX, centerY, tile.tileX, tile.tileY) then
			for _, u in ipairs(state.units) do
				if u.isAlive and not u.isGroundTarget and u.id ~= caster.id
					and u.tileX == tile.tileX and u.tileY == tile.tileY then
					local outcome = CombatResolver.ResolveSkill(caster, u, skillDef)
					outcome.isAOE = true
					local amount = CombatResolver.ApplyOutcome(outcome, u, caster) or 0
					if outcome.type == "Damage" then
						totalDmg = totalDmg + amount
						if u.side ~= caster.side then
							drainable = drainable + amount
						end
						table.insert(entries, { target = u, healing = 0, damage = amount })
						if not u.isAlive then
							table.insert(kills, { v = u, dmg = amount })
						end
					else
						table.insert(entries, { target = u, healing = amount, damage = 0 })
					end
				end
			end
		end
	end
	-- Soul Echo spawns after the unit scan (never mid-iteration of state.units).
	for _, k in ipairs(kills) do
		trySpawnSoulEcho(caster, skillDef, k.v, k.dmg, state)
	end
	local vit = (caster.effectiveStats and caster.effectiveStats.VIT) or 10
	local drainHeal = math.round(drainable * 0.30 * (1 + vit / 300))
	if drainHeal > 0 and caster.isAlive then
		local healed = CombatResolver.ApplyOutcome({
			type = "Healing", targetId = caster.id, finalHealing = drainHeal, sourceUnitId = caster.id,
		}, caster, caster) or 0
		table.insert(entries, { target = caster, healing = healed, damage = 0 })
	end
	return entries, totalDmg, drainHeal
end

--------------------------------------------------
-- MAP STATE
--------------------------------------------------

function CommandService.SetMapDimensions(width: any, height: any)
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
function CommandService.ComputeChargeLanding(actor: any, target: any, state: any)
	if not (actor and target) then return nil end
	local dist = math.max(math.abs(actor.tileX - target.tileX), math.abs(actor.tileY - target.tileY))
	if dist <= 1 then return nil end  -- already adjacent; no move
	local bestTile: any, bestDist, bestDistSq = nil, 999, 999
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
function CommandService.ComputeChargePath(fromX: any, fromY: any, toX: any, toY: any)
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

local function calcMoveRt(actor: any, tilesMoving: any)
	local modBaseRt = StatusService.GetModifiedBaseRt(actor)
	local perTile = modBaseRt * MOVE_RT_FACTOR
	-- AGI reduces Movement RT (DB movement_targeting id 8): x (1 - AGI/(200+AGI)).
	local agi = (actor.effectiveStats and actor.effectiveStats.AGI) or 10
	local agiFactor = 1 - agi / (200 + agi)
	-- Frozen: all RT costs ×2. Wet: movement RT ×1.25.
	local frozenMult = StatusService.GetAllRtMultiplier(actor)
	local wetMult    = StatusService.GetMovementRtMultiplier(actor)
	-- Perks & Flaws (Phase 2b): Fleet Runner/Plodding adjust movement RT specifically.
	local traitMoveMult = TraitEffectService.GetMoveRtMultiplier(actor)
	-- Armor (Feet) base Movement RT multiplier: FT-002 Windrunner x0.75, FT-012 Relay second-move
	-- x0.50, FT-015 Portal Treads teleport x2. (Rescue/Kick x2 are applied contextually at commit.)
	local armorMoveMult = ArmorPassiveService.GetMoveRtModifier(actor)
	return math.round(perTile * tilesMoving * agiFactor * frozenMult * wetMult * traitMoveMult * armorMoveMult)
end

local function calcBasicAttackBaseRt(actor: any)
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
	-- Dual Strike flaw (TRAIT-F-171, 2026-10-23): Basic Attack costs double RT. Applied to the
	-- assembled basic-attack RT, before the Frozen all-RT multiplier (composes multiplicatively).
	baseAttackRt = math.round(baseAttackRt * TraitEffectService.GetBasicAttackRtMultiplier(actor))
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

function CommandService.TriggerCounterIfEligible(defender: any, attacker: any, state: any, wasCounter: any, wasAOE: any, dealtDamage: any)
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
	local function resolveCounterHit(victim: any, dmgMult: any)
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
	BattleVisualBroadcaster.Log("rt", `{defender.name} counterattacks; own next turn +{counterRt} RT.`, defender.id)

	-- Weapon RT Delay to the ATTACKER (DB: Riposte 50% / Counter Stance 30% of the
	-- defender's Weapon RT Delay). Separate from the counter damage — an extra
	-- turn-order setback on whoever provoked the counter. VIT-resisted, exactly
	-- like a normal basic attack's RT delay.
	local rtDelayMult = (inst and inst.counterRtDelayMult) or 0
	local rawDelay = GameConstants.CalcRtDelayBonus(defender.weaponRtDelay or 0, (defender.effectiveStats and defender.effectiveStats.STR) or 10) * rtDelayMult
	if rawDelay > 0 and attacker.isAlive then
		local atkVit = attacker.effectiveStats and attacker.effectiveStats.VIT or 10
		local delay = GameConstants.CalcRtDelayResistance(math.round(rawDelay), atkVit, (attacker.gearDerived and attacker.gearDerived.rtDelayResist or 1))
		attacker.remainingRt = (attacker.remainingRt or 0) + math.max(0, delay)
		print(string.format("[CommandService] COUNTER RT-DELAY | %s +%d RT (x%.2f weapon delay)",
			attacker.name, math.max(0, delay), rtDelayMult))
		BattleVisualBroadcaster.Log("rt", `{attacker.name} is delayed +{math.max(0, delay)} RT by the counter.`, attacker.id)
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

local function validateItemTarget(actor: any, target: any, consumableDef: any): (boolean, any)
	local rules = consumableDef.targetRules or "Self"
	-- ARTIFICER — Applied Artifice: Consumable Item Maximum Range +1 (2026-10-20).
	local range = (consumableDef.range or 0) + DoctrinePassiveService.GetConsumableRangeBonus(actor)
		+ ArmorPassiveService.GetItemRangeBonus(actor)  -- AC Accessory: Item Maximum Range +2 (0 default)

	-- Self / Self-origin: must target self (or no explicit target needed)
	if rules == "Self" then
		if not target or target.id ~= actor.id then
			return false, "This item can only target yourself."
		end
		return true, nil
	end

	if rules == "Self-origin" or rules == "Self and Allies" then
		-- Self-centered AOE: user is the implicit center. A Line / Cone aim tile (user
		-- ruling 2) must lie within the aim range (2026-10-26 UAT finding).
		local aim = ItemEffectService.GetItemAimRange(actor, consumableDef)
		if aim and target and target.tileX then
			local d = math.max(math.abs(actor.tileX - target.tileX), math.abs(actor.tileY - target.tileY))
			if d > math.max(range, aim) then
				return false, "Target is out of range."
			end
		end
		return true, nil
	end

	-- Battlefield / Global: no target needed (whole-battle effect, e.g. weather beacons).
	-- The effect handler reads battle state directly; nothing to position or range-check.
	if rules == "Battlefield" or rules == "Global" then
		return true, nil
	end

	-- KO Ally: special — target must be dead. Widened 2026-10-24: a KO'd ENEMY is
	-- also a valid revive target (returns on the enemy side; feeds the Torture
	-- objective + enables recruit-a-revived-enemy). Allies still revivable too.
	if rules == "KO Ally" then
		if not target then
			return false, "This item requires a KO'd target."
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

	-- Ground / Tile targeting: target is a coordinate table { tileX, tileY }.
	-- Empty Tile (deployables / emitters) and Self to Empty Tile (teleport) pick a tile
	-- the same way (2026-10-26); the teleport's reach comes from its pattern formula.
	if rules == "Self to Empty Tile" then
		range = math.max(range, ItemEffectService.GetItemAimRange(actor, consumableDef) or 0)
	end
	if rules == "Ground" or rules == "Tile" or rules == "Enemy or Ground"
		or rules == "Empty Tile" or rules == "Self to Empty Tile"
		or rules == "Owned Deployable"  -- Object Recall: tap the destination tile
		or rules == "Mechanical Object"  -- Maintenance Tool: tap the device / gadget
		or rules == "Breakable Terrain" then  -- Excavation Drill: tap the tile
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
	-- Any-side unit rules (Kinetic Ram / Grapple "Unit or Object", Exchange "Ally or Enemy")
	-- never target the user themself.
	if (rules == "Unit or Object" or rules == "Ally or Enemy" or rules == "Enemy or Ally") and target.id == actor.id then
		return false, "This item cannot target yourself."
	end
	-- Holy Water (DAM-009 "Enemy or Ally"): an enemy target must be Undead (nothing else
	-- would happen to it), refused here before any cost is paid.
	if rules == "Enemy or Ally" and target.side ~= actor.side
		and not (CombatResolver.IsUndead and CombatResolver.IsUndead(target)) then
		return false, "Only Undead enemies or allies can be targeted."
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

	-- All-tile widening (2026-10-24): ally-only / enemy-only consumables accept a
	-- target of ANY side (heal/buff an enemy, damage-item an ally). Hide still
	-- protects; the bare "Ally" rule keeps its not-self restriction. Mirrors the
	-- skill path. isAlive + range were already checked above.
	if TargetingService.IsWidenedItemRule(rules) then
		if StatusService.HasStatus(target, "Hide") then
			return false, "Target is hidden."
		end
		if rules == "Ally" and target.id == actor.id then
			return false, "This item can only target an ally (not yourself)."
		end
	elseif rules == "Self or Ally" then
		if target.side ~= actor.side then
			return false, "This item can only target yourself or an ally."
		end
	elseif rules == "Ally" or rules == "Ally or Object" then
		-- "Ally or Object" (Recovery Winch, 2026-10-26): ally units only for now; pulling an
		-- object is not built (objects have no move path).
		if target.side ~= actor.side or target.id == actor.id then
			return false, "This item can only target an ally (not yourself)."
		end
	elseif rules == "Enemy" or rules == "Enemy Unit" then
		if target.side == actor.side then
			return false, "This item can only target an enemy."
		end
	elseif rules == "Any Unit" then
		-- Any living unit is valid (isAlive already checked above)
	elseif rules == "Mechanical Unit/Object" then
		-- Magnetic Snare (2026-10-26): a Mechanical-race unit of either side, not yourself.
		-- Objects are not supported yet.
		if target.id == actor.id then
			return false, "This item cannot target yourself."
		end
		if not (CombatResolver.HasRaceTag and CombatResolver.HasRaceTag(target, "Mechanical")) then
			return false, "This item only works on Mechanical units."
		end
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

local function resolveItemEffect(user: any, target: any, consumableDef: any, allUnits: any, state: any)
	-- Delegated to ItemEffectService (2026-10-26): a single, data-driven dispatcher that
	-- routes each consumable to the system already owning that effect. The former 6-pattern
	-- inline parser lived here and silently no-op'd 116 of 140 items; that logic now lives
	-- (migrated verbatim) in ItemEffectService, alongside the new handlers.
	return ItemEffectService.Resolve(user, target, consumableDef, allUnits, { mapWidth = _mapWidth, mapHeight = _mapHeight, state = state })
end
--------------------------------------------------
-- REVIVE SKILL RESOLUTION (2026-10-24)
--
-- Shared by the instant and channeled skill-resolution branches. Brings a KO'd
-- target back to life at skillDef.reviveHpPct% Max HP, scaled by the caster's
-- Skill Potency (skills-only stat; GameConstants.CalcSkillPotency — single source)
-- and the target's Perks & Flaws revive modifiers (same as Interact/potion revive).
-- Phoenix Rite extras: cleanseWound removes one wound-family status (Bleed/Raptured/
-- Wounded); reviveLowRt brings the unit back ready to act soon. Enemy revive is
-- allowed (target keeps its own side) and feeds the Torture objective.
local function applyReviveSkill(caster: any, target: any, skillDef: any, state: any): number
	local pct = (skillDef.reviveHpPct or 5) / 100
	local maxHp = target.maxHp or 1
	local reviveHp
	if TraitEffectService.HasReviveAtOneHp(target) then
		reviveHp = 1
	else
		local casterInt = (caster.effectiveStats and caster.effectiveStats.INT) or 10
		local potency = GameConstants.CalcSkillPotency(casterInt)
		local effFrac = pct * potency * TraitEffectService.GetReviveHpMultiplier(target)
			+ TraitEffectService.GetReviveHpBonusFraction(target)
		reviveHp = math.max(1, math.ceil(maxHp * effFrac))
		reviveHp = math.min(reviveHp, maxHp)
	end
	target.isAlive     = true
	target._revivedThisBattle = true  -- kill-credit rule: revived units never trigger kill augments
	target.currentHp   = reviveHp
	StatusService.WeakenVenomOnHeal(target)  -- a revive weakens Venom like a heal (user ruling 2026-10-26)
	target.remainingRt = skillDef.reviveLowRt and 150 or (target.startingRt or 400)
	if skillDef.cleanseWound then
		for _, s in ipairs({ "Wounded", "Raptured", "Bleed" }) do
			if StatusService.HasStatus(target, s) then
				StatusService.RemoveStatus(target, s)
				break
			end
		end
	end
	-- Torture objective: reviving a KO'd ENEMY (returns on its own side) counts.
	if state and target.side ~= caster.side then
		ObjectiveService.RecordEvent(state, "enemiesRevived", 1)
	end
	if BattleVisualBroadcaster and BattleVisualBroadcaster.UnitStateChanged then
		BattleVisualBroadcaster.UnitStateChanged(target)
	end
	print(string.format("[CommandService] REVIVE SKILL [%s] | %s revives %s at %d/%d HP%s",
		skillDef.name or skillDef.id, caster.name, target.name, reviveHp, maxHp,
		(target.side ~= caster.side) and " (ENEMY revive)" or ""))
	return reviveHp
end

--------------------------------------------------
-- PUBLIC: GetSkillCandidates (for AI and client)
--------------------------------------------------

function CommandService.GetSkillCandidates(actor: any, allUnits: any, skillId: any)
	local skillDef = lookupSkill(skillId)
	if not skillDef then return {} end
	return TargetingService.GetSkillCandidates(actor, allUnits, skillDef)
end

--------------------------------------------------
-- PUBLIC: GetUnitSkills (for client Skill Card UI)
--------------------------------------------------

function CommandService.GetUnitSkills(unit: any)
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
local function isPureBuffSkill(skillDef: any)
	return (skillDef.power or 0) == 0 and not skillDef.inheritStr
		and not skillDef.isHealing and not skillDef.isShield
		and (skillDef.appliesStatus ~= nil or skillDef.appliesStatuses ~= nil)
end

-- Card-tag helper: true when the skill's card shows `tagName`.
local function hasCardTag(skillDef: any, tagName: string): boolean
	for _, tag in ipairs(skillDef.tags or {}) do
		if tag == tagName then return true end
	end
	return false
end

-- "Caster Area" (DB Target_Rules, ruling 2026-10-26): centered on the caster and affects
-- every unit in the area, any side (the user's "either side" ruling applied to an area).
local function isCasterArea(skillDef: any): boolean
	return skillDef.targetRules == "Caster Area"
end

-- Caster-centred aura (War Cry: "Caster Area", Circle3; legacy "Self, Allies").
local function isPureBuffAura(skillDef: any)
	return isPureBuffSkill(skillDef)
		and (skillDef.targetRules == "Self, Allies" or skillDef.targetRules == "Self (Aura)"
			or isCasterArea(skillDef))
		and skillDef.aoePattern ~= nil and skillDef.aoePattern ~= "InheritWeapon"
end

local function auraTargets(state: any, caster: any, skillDef: any)
	local radius = tonumber(tostring(skillDef.aoePattern):match("%d+")) or 1
	-- "Caster Area" affects every unit in the area, any side (ruling 2026-10-26).
	local anySide = isCasterArea(skillDef)
	local list = {}
	for _, u in ipairs(state.units) do
		if u.isAlive and (anySide or u.side == caster.side)
			and math.max(math.abs((u.tileX or 0) - caster.tileX), math.abs((u.tileY or 0) - caster.tileY)) <= radius then
			table.insert(list, u)
		end
	end
	return list
end

-- Applies the skill's status(es) to each target; returns AOE-shaped entries
-- ({ target, outcome = { finalDamage = 0, appliesStatus } }) for Main's broadcast.
local function applyPureBuff(caster: any, skillDef: any, targets: any)
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
local function isSingleTargetSkill(actor: any, skillDef: any, target: any)
	if not skillDef or not target or target.isGroundTarget then return false end
	-- "Any Tile" single-target skills are the former enemy-unit strikes (tile targeting, 2026-10-26).
	local tr = skillDef.targetRules or "Enemy Unit"
	if tr ~= "Enemy Unit" and tr ~= "Any Tile" then return false end
	local aoe = skillDef.aoePattern
	if aoe == "InheritWeapon" then
		return (actor.weaponPattern or "Single") == "Single"
	end
	return aoe == nil
end

local function applyMisdirection(state: any, actor: any, actionType: any, selection: any, skillDef: any, skillSelection: any)
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

-- BD-018 Interception Armor (2026-10-24): a Guarding unit wearing it auto-redirects a single-target
-- Basic Attack / Skill aimed at an ADJACENT (Chebyshev 1) same-side ally onto ITSELF. No limit while
-- Guarding (unlike Misdirection, which consumes). Mirrors applyMisdirection's structure. By ruling we
-- do NOT re-validate the attacker's range/LOS to the interceptor: the interceptor interposes for the
-- ally (it sits one tile farther than the original target, so re-validating would nullify the passive
-- in most geometries). Deterministic pick: lowest unit id among eligible interceptors.
local function applyInterception(state: any, actor: any, actionType: any, selection: any, skillDef: any, skillSelection: any)
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
	-- Only enemy-aimed single-target hits (holder on the opposite side from the actor) can be intercepted.
	if type(holder) ~= "table" or not holder.isAlive or holder.side == actor.side
		or not holder.tileX or not holder.tileY then
		return selection
	end

	local interceptor
	for _, u in ipairs(state.units) do
		if u.isAlive and u ~= holder and u ~= actor and u.side == holder.side
			and u.tileX and u.tileY
			and math.max(math.abs(u.tileX - holder.tileX), math.abs(u.tileY - holder.tileY)) == 1
			and ArmorPassiveService.CanGuardIntercept(u)
			and StatusService.HasStatus(u, "Guard") then
			if not interceptor or tostring(u.id) < tostring(interceptor.id) then
				interceptor = u
			end
		end
	end

	if not interceptor then return selection end
	print(`[CommandService] Interception: {interceptor.name} intercepts {actor.name}'s single-target hit meant for {holder.name}`)
	if BattleVisualBroadcaster.ActionAnnounced then BattleVisualBroadcaster.ActionAnnounced(interceptor, "Guard") end
	if actionType == "Attack" then
		return interceptor
	end
	local swapped = table.clone(selection)
	swapped.target = interceptor
	swapped._intercepted = true
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
function CommandService.GetSkillMpCost(actor: any, skillDef: any, skillId: any)
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

-- Public summon wrapper for augment effects (2026-10-24): lets AugmentEffectService's
-- OnSkillComplete (Decoy/Turret Spawn) spawn next to the caster without reaching the local
-- spawnSummonFor. Minimal skillDef carries only the id (spawnSummonFor keys profiles by id);
-- nil target => nearest free tile to the caster. Injected via AugmentEffectService.SetSummonHandler.
function CommandService.SpawnAugmentSummon(actor: any, summonSkillId: any, state: any): boolean
	if not (actor and summonSkillId and state) then return false end
	local ok = spawnSummonFor(actor, { id = summonSkillId }, nil, state)
	return ok ~= false
end

-- HP / Blood Casting augments (2026-10-25). Resource-conversion casting:
--   HP Casting   — pays the skill's MP cost with HP instead (2 HP per 1 MP), no MP spent.
--   Blood Casting — pays the normal MP cost PLUS 3 HP per 1 MP (potency handled separately).
-- DESIGN DEFAULT (flagged, not authored): a cast may NOT reduce the caster below 1 HP — if the
-- HP cost can't be paid while staying >=1 HP, the cast is blocked exactly like insufficient MP
-- (no suicide-casting). CanPayCastCost validates (no mutation); PayCastCost spends. Both detect
-- the augment via AugmentEffectService.GetAugmentsForSkill; neither augment present = normal MP.
local function _castPayModes(actor: any, skillDef: any): (boolean, boolean)
	local hp, blood = false, false
	if skillDef and skillDef.id and AugmentEffectService.GetAugmentsForSkill then
		for _, a in ipairs(AugmentEffectService.GetAugmentsForSkill(actor, skillDef.id)) do
			if a == "AUG-HP-CASTING" then hp = true elseif a == "AUG-BLOOD-CASTING" then blood = true end
		end
	end
	return hp, blood
end

function CommandService.CanPayCastCost(actor: any, skillDef: any, mpCost: any): (boolean, string?)
	local hp, blood = _castPayModes(actor, skillDef)
	if hp then
		local need = (mpCost or 0) * 2
		if (actor.currentHp or 0) - need < 1 then
			return false, (actor.name or "Unit") .. " lacks the HP to cast with HP Casting."
		end
		return true
	end
	if not UnitSchema.HasEnoughMp(actor, mpCost) then
		return false, (actor.name or "Unit") .. " does not have enough MP."
	end
	if blood then
		local need = (mpCost or 0) * 3
		if (actor.currentHp or 0) - need < 1 then
			return false, (actor.name or "Unit") .. " lacks the HP to cast with Blood Casting."
		end
	end
	return true
end

function CommandService.PayCastCost(actor: any, skillDef: any, mpCost: any)
	local hp, blood = _castPayModes(actor, skillDef)
	if hp then
		local need = (mpCost or 0) * 2
		if need > 0 then actor.currentHp = math.max(1, (actor.currentHp or 1) - need) end
		if BattleVisualBroadcaster.UnitStateChanged then BattleVisualBroadcaster.UnitStateChanged(actor) end
		return
	end
	UnitSchema.SpendMp(actor, mpCost)
	if blood then
		local need = (mpCost or 0) * 3
		if need > 0 then actor.currentHp = math.max(1, (actor.currentHp or 1) - need) end
		if BattleVisualBroadcaster.UnitStateChanged then BattleVisualBroadcaster.UnitStateChanged(actor) end
	end
end

-- LEAP STRIKE landing (Dragon Dive; DB SKL-DRAGON-DIVE): after the hit the caster lands on the
-- target tile. If that tile is still occupied (target survived) or blocked, it lands on the nearest
-- free tile next to it (closest to the caster). No free tile = stays put. Not a Move action.
local function landLeapStrike(caster: any, tileX: any, tileY: any, state: any)
	if not (caster and caster.isAlive and tileX and tileY and state and state.units) then
		return
	end
	if caster.tileX == tileX and caster.tileY == tileY then
		return
	end
	local function isFree(x: number, y: number): boolean
		if x < 1 or x > _mapWidth or y < 1 or y > _mapHeight or GameConstants.IsBlocked(x, y) then
			return false
		end
		for _, u in ipairs(state.units) do
			if u.isAlive and u.id ~= caster.id and u.tileX == x and u.tileY == y then
				return false
			end
		end
		return true
	end
	local landX, landY = nil, nil
	if isFree(tileX, tileY) then
		landX, landY = tileX, tileY
	else
		local bestDist, bestSq = math.huge, math.huge
		for dy = -1, 1 do
			for dx = -1, 1 do
				local cx, cy = tileX + dx, tileY + dy
				if (dx ~= 0 or dy ~= 0) and isFree(cx, cy) then
					local d = math.max(math.abs(caster.tileX - cx), math.abs(caster.tileY - cy))
					local sq = (caster.tileX - cx) ^ 2 + (caster.tileY - cy) ^ 2
					if d < bestDist or (d == bestDist and sq < bestSq) then
						landX, landY, bestDist, bestSq = cx, cy, d, sq
					end
				end
			end
		end
	end
	if landX then
		caster.tileX, caster.tileY = landX, landY
		BattleVisualBroadcaster.UnitMoved(caster)
		print(string.format("[CommandService] LEAP STRIKE | %s lands at (%d,%d)", caster.name, landX, landY))
	else
		print(string.format("[CommandService] LEAP STRIKE | %s found no free landing tile near (%d,%d); stays put",
			caster.name, tileX, tileY))
	end
end

-- DUAL heal/damage single-target skill (Dark Restoration; DB SKL-DARK-RESTORATION): it heals the
-- caster or an Undead ally; any other unit takes Dark damage (Dark vs Undead heals per normal rules).
local function isDualHealDamage(skillDef: any): boolean
	return skillDef.isHealing == true and skillDef.aoePattern == nil and hasCardTag(skillDef, "Direct Damage")
end

local function dualHealsTarget(caster: any, target: any): boolean
	return target.id == caster.id or (target.side == caster.side and CombatResolver.IsUndead(target))
end

-- Damage side of a dual skill. Dark Restoration power follows its card:
-- (12 + 0.30L + 0.35INT + Weapon Damage x 0.35) x Skill Potency, then normal defense/element rules.
local function resolveDualDamage(caster: any, target: any, skillDef: any, state: any): (any, number, any)
	local dmgDef = table.clone(skillDef)
	dmgDef.isHealing = false
	if skillDef.id == "SKL-DARK-RESTORATION" then
		dmgDef.flatPower = CombatResolver.EstimateDarkRestorationPower(caster)  -- same card power as its heal
	end
	local wasAlive = target.isAlive
	local outcome = CombatResolver.ResolveSkill(caster, target, dmgDef)
	local dealt, statusApplied = CombatResolver.ApplyOutcome(outcome, target, caster)
	dealt = dealt or outcome.finalDamage or outcome.finalHealing or 0
	if wasAlive and not target.isAlive then
		trySpawnSoulEcho(caster, skillDef, target, dealt, state)
	end
	return outcome, dealt, statusApplied
end

function CommandService.ActivateChanneledSkill(state: any, unit: any): (boolean, any)
	if not unit.isChanneling or not unit.channelingData then
		return false, "Unit is not channeling."
	end
	if state and state.units and AugmentEffectService.SetBattleUnits then
		AugmentEffectService.SetBattleUnits(state.units)
		_augKnockState = state
	end

	local data     = unit.channelingData
	local skillDef: any = data.skillDef
	local target: any   = data.target
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
		if not CommandService.CanPayCastCost(unit, skillDef, mpCost) then
			print(string.format(
				"[CommandService] Channel FIZZLE | %s | [%s] — MP insufficient (%d/%d needed)",
				unit.name, skillDef.name or skillDef.id, unit.currentMp, mpCost))
			return false, "MP insufficient at activation."
		end
		CommandService.PayCastCost(unit, skillDef, mpCost)
		BattleVisualBroadcaster.ActionAnnounced(unit, skillDef.name or skillDef.id or "Summon")
		local ok, info = spawnSummonFor(unit, skillDef, target, state)
		return ok, ok and info or { type = "Summon", failed = true, reason = info }
	end

	-- OBJECT-PLACING skill resolved after a cast delay (2026-10-24): trap-deploy skills
	-- (Set Bear/Spike/Snare Trap, Set Land Mine) and any createsObject ground skill that
	-- defers via activationTime. Mirrors the isSummon early block — runs BEFORE the
	-- target-alive fizzle because the target is a stat-less Empty-Tile marker. MP was
	-- validated at commit; spend it, announce, then place the object STAMPED with the
	-- caster side so ObjectEffectService gates the trap to enemy-only triggering.
	if skillDef and skillDef.createsObject then
		if not CommandService.CanPayCastCost(unit, skillDef, mpCost) then
			return false, "MP insufficient at activation."
		end
		if not (target and target.tileX and target.tileY) then
			return false, "Object skill: no tile at activation."
		end
		CommandService.PayCastCost(unit, skillDef, mpCost)
		BattleVisualBroadcaster.ActionAnnounced(unit, skillDef.name or skillDef.id or "Deploy")
		local inst = ObjectEffectService.PlaceObjectInstance(state, skillDef.createsObject, target.tileX, target.tileY, unit.side, unit.id)
		print(string.format("[CommandService] Channel ACTIVATE [%s] PLACE %s | %s at (%s,%s) | owner=%s | MP:%d",
			skillDef.name or skillDef.id, tostring(skillDef.createsObject), unit.name,
			tostring(target.tileX), tostring(target.tileY), tostring(unit.side), mpCost))
		return inst ~= nil, { type = "ObjectPlaced", objectType = skillDef.createsObject, placed = inst ~= nil, skillName = skillDef.name }
	end

	-- REPAIR (Artificer, SKL-REPAIR, 2026-10-26): channeled object-repair utility. Runs BEFORE the
	-- target-alive fizzle below (the target is a stat-less Ground marker). The skill is aimed with the
	-- "Ground, including occupied Ground" rule, so target.tileX/tileY is the tile the player clicked;
	-- we fully restore the breakable object sitting there (resets its hits-to-destroy to max). No damage.
	if skillDef and skillDef.repairsObject then
		if not CommandService.CanPayCastCost(unit, skillDef, mpCost) then
			return false, "MP insufficient at activation."
		end
		if not (target and target.tileX and target.tileY) then
			return false, "Repair: no tile at activation."
		end
		CommandService.PayCastCost(unit, skillDef, mpCost)
		BattleVisualBroadcaster.ActionAnnounced(unit, skillDef.name or skillDef.id or "Repair")
		-- Item devices too (DB: "Repair (SKL-REPAIR) resets remaining hits to 3"), 2026-10-26.
		local repaired = repairAtTile(state, target.tileX, target.tileY, false)
		print(string.format("[CommandService] Channel ACTIVATE [Repair] | %s repaired object at (%s,%s) -> %s | MP:%d",
			unit.name, tostring(target.tileX), tostring(target.tileY), tostring(repaired), mpCost))
		return true, { type = "Repair", repaired = repaired, skillName = skillDef.name }
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
		target._revivedThisBattle = true  -- kill-credit rule: revived units never trigger kill augments
		-- Perks & Flaws revive modifiers (2026-10-23): Slow to Recover halves revive HP;
		-- Resilient adds +20% max HP; Undying Will flaw forces exactly 1 HP (overrides all).
		local maxHp = target.maxHp or 1
		local reviveHp
		if TraitEffectService.HasReviveAtOneHp(target) then
			reviveHp = 1
		else
			local effFrac = frac * TraitEffectService.GetReviveHpMultiplier(target)
				+ TraitEffectService.GetReviveHpBonusFraction(target)
			reviveHp = math.max(1, math.ceil(maxHp * effFrac))
			reviveHp = math.min(reviveHp, maxHp)
		end
		target.currentHp = reviveHp
		StatusService.WeakenVenomOnHeal(target)  -- a revive weakens Venom like a heal (user ruling 2026-10-26)
		target.remainingRt = target.startingRt or 400
		BattleVisualBroadcaster.ActionAnnounced(unit, "Resuscitate")
		BattleVisualBroadcaster.UnitStateChanged(target)
		print(string.format(
			"[CommandService] INTERACT REVIVE RESOLVE | %s resuscitates %s at %d/%d HP",
			unit.name, target.name, target.currentHp, target.maxHp or 0
		))
		BattleVisualBroadcaster.Log("ko", `{unit.name} resuscitates {target.name} ({target.currentHp}/{target.maxHp or 0} HP).`, target.id)
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

	-- Steal (SKL-STEAL) execution re-check (2026-10-24): the caster must STILL be on the
	-- target's exact rear tile at resolve. Pushed off, or the target turned to face them,
	-- during the channel => fizzle (turn already spent at commit; MP refunded, like every
	-- other fizzle path above). Good counterplay, set on purpose.
	if skillDef and skillDef.id == "SKL-STEAL" then
		if not target or not GameConstants.IsCasterBehindTarget(unit, target) then
			print(string.format("[CommandService] Channel FIZZLE | %s | [Steal] — no longer behind target", unit.name))
			return false, "No longer behind the target."
		end
	end

	-- Tile-occupant resolution at activation (crash fix 2026-10-26). A channeled SINGLE-target
	-- skill can carry the stat-less ground marker: an empty tile at commit, an AI ground-aimed
	-- cast, or an area skill collapsed to single-target by Concentrated Effect. Channels resolve
	-- on the committed tile, so whoever stands there NOW takes the hit. An empty tile gets only
	-- the terrain reaction (handled in the dispatch below). The marker must never reach
	-- ResolveSkill/ResolveHealing/ResolveShield (they read target.effectiveStats).
	local _emptyTileCast = false
	if target and target.isGroundTarget and skillDef
		and isUnitAnchoredPattern(skillDef)  -- incl. Cleave / Chain / weapon shapes (BUG-057 fix 2)
		and not skillDef.isSummon and not skillDef.createsObject and not skillDef.repairsObject
		and not RacePassiveService.IsMovementSkill(skillDef) then
		local occupant = findLiveTileOccupant(state, target.tileX, target.tileY)
		if occupant then
			target = occupant
		else
			_emptyTileCast = true
		end
	end

	-- Check cast affordability at activation (MP, or HP for HP/Blood Casting) — else fizzle
	if not CommandService.CanPayCastCost(unit, skillDef, mpCost) then
		print(string.format(
			"[CommandService] Channel FIZZLE | %s | [%s] — MP insufficient (%d/%d needed)",
			unit.name, skillDef.name or skillDef.id, unit.currentMp, mpCost
		))
		return false, "MP insufficient at activation."
	end

	-- Channel fires now: announce the skill over the caster.
	BattleVisualBroadcaster.ActionAnnounced(unit, skillDef.name or skillDef.id or "Skill")

	-- SPEND the cast cost now (MP, or HP for HP/Blood Casting)
	CommandService.PayCastCost(unit, skillDef, mpCost)

	-- TWO-TIMER MODEL: the caster's RT was ALREADY charged at channel-commit time
	-- (base + skill RT cost via AccrueRt + EndTurn in ValidateAndCommit). Activation
	-- now runs in the ChannelResolve phase where NO turn is open, so calling AccrueRt
	-- here would fail its TurnOpen assert (the crash we hit). No RT is charged at
	-- activation — the skill was fully paid for on commit.

	-- Resolve the skill
	local result = {}

	if _emptyTileCast then
		-- EMPTY-TILE resolution: nothing to hit. Apply the authored tile effect and the skill
		-- element's terrain reaction (same as the instant ground branch); no damage, no status.
		if skillDef.createsTileEffect and _tileEffectService then
			_tileEffectService.ApplyTileEffect(target.tileX, target.tileY, skillDef.createsTileEffect, unit.id)
		end
		local elem = CombatResolver.ExtractSkillElement(skillDef)
		-- Tile targeting includes objects (ruling 2026-10-26): a damaging skill aimed at a
		-- tile holding a breakable object lands one hit on it, exactly like a basic attack on
		-- the object (ApplyObjectHit: 1 hit, element instant-kill tags apply). No-op otherwise.
		if (skillDef.power or 0) > 0 and not skillDef.isHealing and not skillDef.isShield then
			local objHit = ObjectEffectService.ApplyObjectHit(state, target.tileX, target.tileY, 1, elem or "Physical")
			if objHit ~= "not-found" then
				print(`[CommandService] Channel ACTIVATE [{skillDef.name or skillDef.id}] hits object at ({target.tileX},{target.tileY}) -> {tostring(objHit)}`)
			end
		end
		if elem and elem ~= "Physical" and _tileEffectService and _tileEffectService.ResolveElementOnTile then
			_tileEffectService.ResolveElementOnTile(target.tileX, target.tileY, elem, unit.id, state.units)
		end
		result.type      = "GroundReaction"
		result.skillName = skillDef.name
		result.tileX     = target.tileX
		result.tileY     = target.tileY
		print(string.format(
			"[CommandService] Channel ACTIVATE [%s] | %s -> empty tile (%d,%d) | reaction:%s | MP:%d",
			skillDef.name or skillDef.id, unit.name, target.tileX, target.tileY,
			tostring(elem), mpCost
		))

	-- RESTOCK (Chemist, SKL-RESTOCK): channeled self utility — refill 1 use charge to
	-- each equipped consumable (capped at its max). No damage/status. 2026-10-20.
	elseif skillDef.id == "SKL-RESTOCK" then
		local refilled = 0
		for _, slot in pairs(unit.consumableSlots or {}) do
			if slot and slot.consumableId then
				local maxC = slot.maxCharges or 0
				local cur = slot.currentCharges or 0
				if cur < maxC then
					slot.currentCharges = math.min(maxC, cur + 1)
					refilled = refilled + 1
				end
			end
		end
		result.type = "Restock"
		result.refilled = refilled
		result.skillName = skillDef.name
		print(string.format("[CommandService] Channel ACTIVATE [Restock] | %s refilled %d consumable(s) | MP:%d",
			unit.name, refilled, mpCost))

	elseif skillDef.id == "SKL-STEAL" then
		-- STEAL RESOLVE (2026-10-24): the slot was validated at commit and rode the channel
		-- (data.stolenSlot). Re-check it is still populated, then REAL-THEFT it: Unequip
		-- strips it from the victim AND rebuilds their stats (lost defense/passives apply
		-- immediately), tag it stolen, and stash it on the battle state for victory loot
		-- (kept only on a win). Both hands are never in STEALABLE_SLOTS, so never a weapon.
		local slot = data.stolenSlot
		local legal = false
		for _, s in ipairs(GameConstants.GetStealableSlots(target)) do
			if s == slot then legal = true break end
		end
		if not legal then
			result.type = "Steal"; result.failed = true; result.skillName = skillDef.name
			print(string.format("[CommandService] Steal RESOLVE | %s -> %s | slot gone, nothing taken",
				unit.name, target.name))
		else
			local okU, removed = EquipmentService.Unequip(target, slot)
			if okU and removed then
				removed.stolen = true
				state.stolenItems = state.stolenItems or {}
				table.insert(state.stolenItems, removed)
				result.type = "Steal"; result.target = target; result.slot = slot
				result.stolenItem = removed; result.skillName = skillDef.name
				BattleVisualBroadcaster.UnitStateChanged(target)
				print(string.format("[CommandService] Steal RESOLVE | %s stole %s (%s) from %s",
					unit.name, removed.instanceId or "?", slot, target.name))
				BattleVisualBroadcaster.Log("steal", `{unit.name} steals {slot} from {target.name}.`, target.id)
			else
				result.type = "Steal"; result.failed = true; result.skillName = skillDef.name
			end
		end

	elseif skillDef.isPurify and target and not target.isGroundTarget then
		-- Purifying Form is channeled (200 CT), so it always resolves here. Same effect as the
		-- instant branch: remove one real debuff, grant Purified. Any side (tile targeting).
		-- Previously missing, so the cast fell through to single-target damage (UAT 2026-10-26).
		local purged = StatusService.RemoveRandomDebuff(target)
		StatusService.ApplyStatus(target, "Purified", unit.id)
		if BattleVisualBroadcaster.UnitStateChanged then
			BattleVisualBroadcaster.UnitStateChanged(target)
		end
		result.type      = "Purify"
		result.target    = target
		result.removed   = purged
		result.skillName = skillDef.name
		print(string.format("[CommandService] Channel ACTIVATE [%s] PURIFY | %s -> %s | purged:%s +Purified | MP:%d",
			skillDef.name or skillDef.id, unit.name, target.name, tostring(purged), mpCost))

	elseif skillDef.isShield then
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
			-- "Caster Area" shields every unit in the field, any side (ruling 2026-10-26).
			local shieldAnySide = isCasterArea(skillDef)
			for _, u in ipairs(state.units) do
				if u.isAlive and (shieldAnySide or u.side == unit.side)
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

	elseif skillDef.isRevive then
		-- Revive skill (channeled path, e.g. Battlefield Triage 100 CT). Must precede
		-- the isHealing branch (revive skills also carry isHealing for VFX). Target was
		-- validated KO'd at commitment; it may have been revived another way mid-channel.
		if not target or target.isAlive then
			result.type = "Revive"
			result.skillName = skillDef.name
			print(string.format("[CommandService] REVIVE FIZZLE | %s | %s no longer KO'd",
				unit.name, target and target.name or "target"))
		else
			local hp = applyReviveSkill(unit, target, skillDef, state)
			result.type     = "Revive"
			result.target   = target
			result.healing  = hp
			result.skillName = skillDef.name
		end

	elseif skillDef.isHealing and hasCardTag(skillDef, "Direct Damage")
		and skillDef.aoePattern ~= nil and not isUnitAnchoredPattern(skillDef) and target and target.tileX then
		-- AREA LIFEDRAIN (Siphon Pulse, channeled): damage the area, caster heals from it.
		local entries, totalDmg, drainHeal = resolveAreaDrain(unit, skillDef, target.tileX, target.tileY, state)
		result.type      = "AreaHealing"
		result.targets   = entries
		result.skillName = skillDef.name
		print(string.format("[CommandService] Channel ACTIVATE [%s] AREA DRAIN | %s | units:%d | Dmg:%d | Drain heal:%d | MP:%d",
			skillDef.name or skillDef.id, unit.name, #entries, totalDmg, drainHeal, mpCost))

	elseif skillDef.isHealing and not hasCardTag(skillDef, "Direct Damage")
		and skillDef.aoePattern ~= nil and not isUnitAnchoredPattern(skillDef)
		and target and target.tileX then
		-- AREA HEAL (Mending Rain, channeled): every unit in the pattern, any side. Fixes the
		-- empty-tile crash (marker passed to ResolveHealing) and the old one-unit-only heal.
		local entries = resolveAreaHealing(unit, skillDef, target.tileX, target.tileY, state)
		result.type      = "AreaHealing"
		result.targets   = entries
		result.skillName = skillDef.name
		print(string.format("[CommandService] Channel ACTIVATE [%s] AREA HEAL | %s at (%d,%d) | units:%d | MP:%d",
			skillDef.name or skillDef.id, unit.name, target.tileX, target.tileY, #entries, mpCost))

	elseif isDualHealDamage(skillDef) and target and not target.isGroundTarget
		and not dualHealsTarget(unit, target) then
		-- Dark Restoration on anyone but the caster or an Undead ally: Dark damage (card), not a heal.
		local outcome, dealt, statusApplied = resolveDualDamage(unit, target, skillDef, state)
		local isDamage = outcome.type == "Damage"
		result.type          = if isDamage then "Damage" else "Healing"
		result.target        = target
		result.damage        = if isDamage then dealt else 0
		result.healing       = if isDamage then 0 else dealt
		result.statusApplied = statusApplied
		result.skillName     = skillDef.name
		print(string.format("[CommandService] Channel ACTIVATE [%s] DARK | %s -> %s | %s:%d | MP:%d",
			skillDef.name or skillDef.id, unit.name, target.name, if isDamage then "Dmg" else "Heal", dealt, mpCost))

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

	elseif skillDef.swapWithTarget and target and not target.isGroundTarget then
		-- Delayed Phantom Exchange: swap with the selected ally at activation.
		local swapped = applySwap(unit, target)
		result.type      = "AOE"
		result.targets   = { { target = target, outcome = { finalDamage = 0 } } }
		result.totalDmg  = 0
		result.hitCount  = swapped and 1 or 0
		result.skillName = skillDef.name
		print(string.format("[CommandService] Channel ACTIVATE [%s] SWAP | %s <-> %s | ok:%s | MP:%d",
			skillDef.name, unit.name, target.name, tostring(swapped), mpCost))

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

	-- Buff-tagged skills may be cast on ANY side (ruling 2026-10-26); debuffs on a foe keep the
	-- normal hit path below (resistance/reaction rules).
	elseif isPureBuffSkill(skillDef) and target and not target.isGroundTarget
		and (target.side == unit.side
			or (hasCardTag(skillDef, "Buff") and not hasCardTag(skillDef, "Debuff"))) then
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

	elseif skillDef.aoePattern == "InheritWeapon" and (unit.weaponPattern or "Single") ~= "Single" then
		-- Channeled weapon-shaped skill (Execution Stroke, Storm Barrage) with an area weapon: same
		-- targets as the instant path. Previously fell into the tile-pattern branch, which does not
		-- know "InheritWeapon", so it hit nothing (UAT 2026-10-26 P-1).
		local aoeTargets = weaponPatternTargets(unit, target, state.units, unit.weaponPattern) or {}
		local totalDmg, hitCount, allOutcomes = 0, 0, {}
		for _, entry in ipairs(aoeTargets) do
			if entry.unit.isAlive then
				local outcome = CombatResolver.ResolveSkill(unit, entry.unit, skillDef)
				outcome.finalDamage = math.max(0, math.round(outcome.finalDamage * entry.dmgMult))
				if entry.dmgMult < 1.0 then outcome.isAOE = true end
				CombatResolver.ApplyOutcome(outcome, entry.unit, unit)
				totalDmg = totalDmg + outcome.finalDamage
				hitCount = hitCount + 1
				table.insert(allOutcomes, { target = entry.unit, outcome = outcome })
				if not entry.unit.isAlive then
					trySpawnSoulEcho(unit, skillDef, entry.unit, outcome.finalDamage or 0, state)
				end
			end
		end
		result.type      = "AOE"
		result.targets   = allOutcomes
		result.totalDmg  = totalDmg
		result.hitCount  = hitCount
		result.skillName = skillDef.name
		print(string.format("[CommandService] Channel ACTIVATE [%s] Inherit[%s] | %s | Hits:%d | Dmg:%d | MP:%d",
			skillDef.name or skillDef.id, tostring(unit.weaponPattern), unit.name, hitCount, totalDmg, mpCost))

	elseif skillDef.aoePattern and skillDef.aoePattern ~= "Cleave" and skillDef.aoePattern ~= "InheritWeapon" then
		-- Generic AOE: tile-based pattern resolution (InheritWeapon with a Single weapon falls to
		-- the single-target branch below)
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
		local _actualDmg, statusApplied = CombatResolver.ApplyOutcome(outcome, target, unit)
		-- Same post-hit effects as the instant path (RT delay, skill knockback).
		applySkillPostHit(state, unit, target, skillDef, _actualDmg or outcome.finalDamage or 0)
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

	-- Augment OnSkillComplete (2026-10-24): once-per-cast augment hook for the CHANNELED
	-- resolution path (Decoy/Turret spawn, Scatter/Vortex AOE displacement). Center = the
	-- channel's target tile. nil-safe; no-op when the skill carries no augments.
	if skillDef and skillDef.id then
		local _scAug = AugmentEffectService.GetAugmentsForSkill(unit, skillDef.id)
		if _scAug and #_scAug > 0 then
			AugmentEffectService.OnSkillComplete(unit, skillDef, _scAug, {
				state = state,
				centerX = target and target.tileX,
				centerY = target and target.tileY,
				affectedTiles = skillAffectedTiles(unit, skillDef, target and target.tileX, target and target.tileY),
			})
		end
	end

	-- Leap strike (Dragon Dive): the caster lands after the hit.
	if skillDef and skillDef.isLeapStrike and target and target.tileX then
		landLeapStrike(unit, target.tileX, target.tileY, state)
	end

	return true, result
end

--------------------------------------------------
-- PUBLIC: ValidateAndCommit
--------------------------------------------------

function CommandService.ValidateAndCommit(
	state: any,
	actorId: any,
	actionType: any,
	selection: any
): (boolean, any)
	-- Augment radius/push augments read a cached live unit list (2026-10-24 augment fix);
	-- refresh it at each resolution entry (same pattern TileEffectService uses). nil-safe.
	if state and state.units and AugmentEffectService.SetBattleUnits then
		AugmentEffectService.SetBattleUnits(state.units)
		_augKnockState = state
	end
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

		do
			local _payOk, _payReason = CommandService.CanPayCastCost(actor, skillDef, mpCost)
			if not _payOk then return false, _payReason end
		end

		local targetSelection = {
			target      = selection.target,
			targetRules = skillDef.targetRules or "Enemy Unit",
			-- All-tile widening (2026-10-24): derived from the server's authoritative
			-- skillDef (id + flags), so the six carve-outs stay unit-targeted even
			-- though they share a targetRules string with widenable skills.
			widened     = TargetingService.IsWidenedSkill(skillDef),
		}
		-- 2026-10-07: ONE shared range formula (DAT-001) — same call as
		-- TargetingService.GetSkillCandidates: weapon-only min range, per-skill
		-- Bonus Skill Range share, Halfling Nimble Steps race modifier.
		targetSelection.skillRange, targetSelection.skillMinRange = GameConstants.CalcSkillRange(
			actor, skillDef, RacePassiveService.GetSkillRangeModifier(actor, skillDef)
				+ WeaponPassiveService.GetSkillRangeBonus(actor, skillDef)) -- ArcaneReach (Staff) +1 on weapon-range skills

		local valid, reason = TargetingService.ValidateSelection(
			actor, "Skill", targetSelection,
			state.units, _mapWidth, _mapHeight
		)
		if not valid then return false, reason end

		-- Steal (SKL-STEAL) commit gate (2026-10-24): authoritative re-validation — the
		-- client gray-out is only UX, the server never trusts it (SEC-001/SEC-002). Require
		-- the caster to be directly behind the target, the target to have a stealable piece,
		-- and the player's picked slot to be one of them. Both hands are never stealable.
		if skillDef.id == "SKL-STEAL" then
			local tgt = selection.target
			if type(tgt) == "string" then
				local found = nil
				for _, u in ipairs(state.units) do if u.id == tgt then found = u break end end
				tgt = found
			end
			if type(tgt) ~= "table" then return false, "Steal: target not found." end
			if not GameConstants.IsCasterBehindTarget(actor, tgt) then
				return false, "Steal requires standing directly behind the target."
			end
			local sslots = GameConstants.GetStealableSlots(tgt)
			if #sslots == 0 then return false, "Target has no stealable gear." end
			local okSlot = false
			for _, s in ipairs(sslots) do if s == selection.stealSlot then okSlot = true break end end
			if not okSlot then return false, "Steal: invalid or missing slot pick." end
		end
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
		-- Maintenance Tool (2026-10-26): something repairable must be on the tile, checked
		-- BEFORE any cost so a mis-tap never wastes the charge.
		if ItemEffectService.IsRepairItem(consumableDef) and type(target) == "table" and target.tileX then
			local found = false
			for _, u in ipairs(state.units) do
				if u.isAlive and u.isItemDevice and u.tileX == target.tileX and u.tileY == target.tileY then
					found = true
					break
				end
			end
			if not found then
				for _, inst in ipairs(state.objects or {}) do
					local d = inst.type and ObjectData.Objects[inst.type]
					if inst.x == target.tileX and inst.y == target.tileY and d and d.isDeployable == true
						and type(d.hitsToDestroy) == "number" then
						found = true
						break
					end
				end
			end
			if not found then
				return false, "Nothing to repair there."
			end
		end
		-- Pick-list items (user ruling 1, 2026-10-26): reject a missing / invalid choice
		-- before any cost is paid.
		local choiceErr = ItemEffectService.ValidateItemChoice(consumableDef, selection.choice, target, actor, state.units)
		if choiceErr then return false, choiceErr end

	elseif actionType ~= "Wait" and actionType ~= "Guard" and actionType ~= "Push"
		and actionType ~= "Interact" and actionType ~= "PushObject" and actionType ~= "AttackObject" then
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
			skillSel = { target = selection.target, targetRules = skillDef.targetRules or "Enemy Unit",
				widened = TargetingService.IsWidenedSkill(skillDef) }
			skillSel.skillRange, skillSel.skillMinRange = GameConstants.CalcSkillRange(
				actor, skillDef, RacePassiveService.GetSkillRangeModifier(actor, skillDef)
					+ WeaponPassiveService.GetSkillRangeBonus(actor, skillDef)) -- ArcaneReach (Staff)
		end
		selection = applyMisdirection(state, actor, actionType, selection, skillDef, skillSel)
		-- BD-018 Interception Armor: a Guarding neighbor may take the hit instead (runs after
		-- Misdirection so it applies to the final redirected target). No trigger consumed.
		selection = applyInterception(state, actor, actionType, selection, skillDef, skillSel)
	end

	-- STEP 5c: Interact pre-validation (reject BEFORE charging AP — DB command_pipeline
	-- step 5 "Reject without payment"). Confirms the chosen target is a current
	-- Interact candidate; a stale/invalid Interact returns here, spending no AP/RT.
	-- interactObjType captures the matched map-object's type (for the Treasure Seeker
	-- no-AP rule at STEP 6); stays nil for non-object interacts.
	local interactObjType = nil
	if actionType == "Interact" then
		if type(selection) ~= "table" then
			return false, "Interact requires a selection."
		end
		local _cands = TargetingService.GetInteractCandidates(actor, state.units, state)
		local _ok = false
		for _, c in ipairs(_cands) do
			if selection.interactKind == "mapObject" then
				if c.interactKind == "mapObject" and selection.objectId and c.objectId == selection.objectId then
					_ok = true; interactObjType = c.archetypeId or c.name; break
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
	-- GL-021 Initiator's Grips: the FIRST Push each turn costs no AP (once per turn via
	-- _armorFreePushUsed, reset at OnTurnStart; GetFreePushConfig returns nil once used). Captured
	-- here; the push branch reads initiatorFreeCfg for Force x0.5 and RT x2 (via pushContext.isFreePush).
	local initiatorFreeCfg = (actionType == "Push") and ArmorPassiveService.GetFreePushConfig(actor) or nil
	if initiatorFreeCfg then apCost = 0 end
	-- Treasure Seeker (P-122/P-151, 2026-10-24): opening a treasure chest costs no AP. Scoped
	-- to chest object types via TraitEffectService.IsFreeTreasureInteract. Only the no-AP half
	-- of the trait; the +reward/gold half is blocked on the chest-gold economy rule.
	if apCost > 0 and actionType == "Interact"
		and TraitEffectService.IsFreeTreasureInteract(actor, interactObjType) then
		apCost = 0
	end
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
		-- Perks & Flaws (2026-10-23): mark a VOLUNTARY move this turn so Restless /
		-- Sniper's Perch can read "did not move last turn" next turn. Rolled over in
		-- TraitEffectService.OnTurnStart. Push / knockback / charge do NOT set this.
		actor._movedThisTurn = true
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
		-- UNDO (2026-10-17): running total of RT this Move adds (base + any
		-- crossCost below) so Undo can refund exactly what was accrued.
		local undoMoveRt = rtCost

		-- Save old position for facing calculation
		local prevTileX, prevTileY = actor.tileX, actor.tileY
		local prevFacing = actor.facing

		-- TRAP TRIGGER (Slice 5, 2026-10-20) — fire step-on traps on EVERY tile
		-- crossed, not just the destination. The client sends only the destination
		-- + pathCost (never a trusted path), so the server REBUILDS the route from
		-- the actor's CURRENT tile via GetMoveCandidates (the same BFS the move
		-- prompt uses) and reads the matching candidate's reconstructed .path. We
		-- step the actor onto each tile in turn so a Land Mine detonation is centered
		-- on the unit correctly, then fire any trap there. Bear/Snare (root) or a KO
		-- stop the walk at that tile; Spike and Land Mine do not. Flight bypasses.
		local destX, destY = selection.tileX, selection.tileY
		-- FT-018 Rescue Spurs: tile the ally will relocate to if this Move ends on an ally (the rescuer's
		-- last crossed tile). Defaults to the origin (covers a flying rescuer / adjacent ally); refined to
		-- the tile before the destination inside the grounded walk below.
		local rescueBackX, rescueBackY = prevTileX, prevTileY
		local trapSprung = false
		local trapActorFlying = StatusService.HasStatus(actor, "Flight")
		if trapActorFlying then
			actor.tileX = destX
			actor.tileY = destY
		else
			local crossed = {}
			local moveCands = TargetingService.GetMoveCandidates(actor, state.units, _mapWidth, _mapHeight)
			local matched = nil
			for _, c in ipairs(moveCands) do
				if c.tileX == destX and c.tileY == destY then matched = c; break end
			end
			if matched and matched.path then
				for _, step in ipairs(matched.path) do
					table.insert(crossed, { x = step.tileX, y = step.tileY })
				end
			else
				print("[CommandService] Trap walk: no server path to destination; checking destination tile only.")
			end
			table.insert(crossed, { x = destX, y = destY })
			-- FT-018 Rescue Spurs: the tile crossed just BEFORE the destination (last entry is the
			-- destination itself). Used only if this turns out to be a rescue landing.
			if #crossed >= 2 then
				rescueBackX, rescueBackY = crossed[#crossed - 1].x, crossed[#crossed - 1].y
			end

			local fx, fy = prevTileX, prevTileY
			-- FT-007 Softstep Slippers: crossing a trap tile does not trigger it; only ENDING on a trap
			-- tile (the final/destination tile) still triggers. Gate skips triggers on non-final crossed
			-- tiles when the mover has the passive. The destination is always the last entry in `crossed`.
			local avoidCrossTraps = ArmorPassiveService.CanAvoidTrapsInPath(actor)
			-- FT-016 Trailblazer Boots: tiles traversed THIS move are set on fire; the unit's FINAL resting
			-- tile is spared. Collect each stepped tile here, then ignite after the walk so the actual end
			-- tile (fx,fy -- the destination OR a trap-stop tile) is excluded. Movement -1 is already applied
			-- via GetMovementRangeBonus in pathfinding. Flight (handled above) leaves no trail by design.
			local fireTrailTiles = (ArmorPassiveService.GetMoveFireTrailConfig(actor) ~= nil) and {} or nil
			for _, tile in ipairs(crossed) do
				actor.tileX, actor.tileY = tile.x, tile.y   -- step onto the tile
				fx, fy = tile.x, tile.y
				if fireTrailTiles then fireTrailTiles[#fireTrailTiles + 1] = { x = tile.x, y = tile.y } end
				local isFinalTile = (tile.x == destX and tile.y == destY)
				local trap = ObjectEffectService.GetTriggeredTrapAt(state, tile.x, tile.y)
				if trap and not (avoidCrossTraps and not isFinalTile) then
					local tr = ObjectEffectService.TriggerTrap(actor, trap, state, state.units)
					if tr.fired then trapSprung = true end
					if tr.stops then break end
				end
			end
			actor.tileX = fx
			actor.tileY = fy
			-- FT-016: ignite every traversed tile EXCEPT the unit's final resting tile (fx,fy).
			if fireTrailTiles and _tileEffectService and _tileEffectService.ApplyTileEffect then
				for _, ft in ipairs(fireTrailTiles) do
					if not (ft.x == fx and ft.y == fy) then
						_tileEffectService.ApplyTileEffect(ft.x, ft.y, "Burning", actor.id)
					end
				end
			end
		end

		-- FT-018 Rescue Spurs: if the Move ENDED on an ally's tile, relocate that ally to the rescuer's
		-- last crossed tile (rescueBackX/Y) and charge RT x2 (contextual -- double the base move RT by
		-- accruing one more rtCost). Gated on the actor actually REACHING the destination (a trap that
		-- stopped the walk short leaves actor.tileX/Y != destX/Y and cancels the rescue). The ally's
		-- target tile was crossed by the rescuer this move, so it is empty now that the rescuer left it.
		if actor.tileX == destX and actor.tileY == destY and ArmorPassiveService.GetMoveRescueConfig(actor) then
			local rescuedAlly = nil
			for _, u in ipairs(state.units) do
				if u ~= actor and u.isAlive and u.side == actor.side
					and u.tileX == destX and u.tileY == destY then
					rescuedAlly = u; break
				end
			end
			if rescuedAlly then
				rescuedAlly.tileX = rescueBackX
				rescuedAlly.tileY = rescueBackY
				BattleCoordinator.AccrueRt(state, rtCost)
				undoMoveRt = undoMoveRt + rtCost
				if BattleVisualBroadcaster.UnitMoved then BattleVisualBroadcaster.UnitMoved(rescuedAlly) end
				print(string.format("[CommandService] Rescue Spurs: %s rescues %s -> (%d,%d) | RT x2",
					actor.name, rescuedAlly.name, rescueBackX, rescueBackY))
			end
		end

		-- FT-019 Kick Boots: if the Move ENDED on an enemy's tile, knock that enemy back in ITS OWN facing
		-- direction (DB: "trigger Knockback on enemy in enemy's facing direction"); the kicker then holds
		-- the vacated tile. RT x2 (one extra rtCost accrual). If the enemy could NOT be displaced (wall /
		-- displacement-immune, still on the tile and alive), the kicker stays on its last crossed tile
		-- (rescueBackX/Y) so two units never share a tile -- the knockback attempt + any wall-collision
		-- damage still resolved. Gated on the actor actually reaching the destination (trap-stop cancels).
		if actor.tileX == destX and actor.tileY == destY and ArmorPassiveService.GetMoveKickConfig(actor) then
			local kicked = nil
			for _, u in ipairs(state.units) do
				if u ~= actor and u.isAlive and u.side ~= actor.side
					and u.tileX == destX and u.tileY == destY then
					kicked = u; break
				end
			end
			if kicked then
				local force = (actor.derivedStats and actor.derivedStats.force) or 1
				local facingDir = GameConstants.GetFacingVector(kicked.facing)
				applyKnockback(state, actor, kicked, force, "KICK", facingDir)
				BattleCoordinator.AccrueRt(state, rtCost)
				undoMoveRt = undoMoveRt + rtCost
				if kicked.isAlive and kicked.tileX == destX and kicked.tileY == destY then
					-- push blocked: enemy still occupies the tile -> kicker cannot share it.
					actor.tileX = rescueBackX
					actor.tileY = rescueBackY
					print(string.format("[CommandService] Kick Boots: %s could not displace %s (blocked) -- holds at (%d,%d) | RT x2",
						actor.name, kicked.name, rescueBackX, rescueBackY))
				else
					print(string.format("[CommandService] Kick Boots: %s kicks %s and takes tile (%d,%d) | RT x2",
						actor.name, kicked.name, destX, destY))
				end
			end
		end

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
		-- UNDO: snapshot the mover's own status-instance signature BEFORE the
		-- reaction block. This dimension catches AURA changes (War Banner / Cursed
		-- Statue buffs/debuffs gained or lost on landing) — those apply as statuses
		-- to the mover, so a signature change flags them. It does NOT, on its own,
		-- catch terrain/tile triggers that don't mutate the mover's status set
		-- (Sinking, slides, collapse, teleport, molten) — those are detected from
		-- the destination tile's definition below (source of truth), per the
		-- "flag reactions at the source" fix (2026-10-17).
		local function undoStatusSig(u)
			local ids = {}
			for _, inst in ipairs(u.statusInstances or {}) do ids[#ids + 1] = inst.id end
			table.sort(ids)
			return table.concat(ids, "|")
		end
		local undoSigBefore = undoStatusSig(actor)
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
					undoMoveRt = undoMoveRt + extraRt
				end

				-- Terrain trigger on enter: Deep Water → Drowning, etc.
				-- FT-005 Levitation Boots: a wearer floats over water and does NOT take the Deep Water
				-- Drowning trigger (the only concrete water-terrain penalty in code; Shallow Water / Wet
				-- carry only an occupy BONUS, nothing to ignore). CanIgnoreWaterEffects reads the Feet slot.
				if terrainData.triggerEffect == "Drowning" and StatusService
					and not ArmorPassiveService.CanIgnoreWaterEffects(actor) then
					StatusService.ApplyStatus(actor, "Drowning", "terrain")
					print(string.format("[CommandService] Terrain trigger: %s enters %s → Drowning",
						actor.name, terrainData.id))
				elseif terrainData.triggerEffect == "Drowning" and ArmorPassiveService.CanIgnoreWaterEffects(actor) then
					print(string.format("[CommandService] Levitation Boots: %s floats over %s (no Drowning)",
						actor.name, terrainData.id))
				end
			end

			-- Tile effect cross check (Burning, Poison Cloud, etc.)
			if _tileEffectService then
				_tileEffectService.OnUnitEntersTile(actor, actor.tileX, actor.tileY)
			end
		end

		-- ===== Perks & Flaws move-completion hooks (2026-10-23) =====
		-- Evaluate Martial Footwork BEFORE marking the unit as having acted — the trait needs
		-- to know this Move was the FIRST action this turn. pathCost = tiles moved this action.
		local martial = TraitEffectService.GetMartialFootworkOnFirstMove(actor)
		-- Dodger / Sitting Duck: accumulate per-tile evasion (until next turn).
		TraitEffectService.AccumulateMoveEvasion(actor, pathCost)
		-- Unstable Footing (F-114): landing on an effect-less tile rolls a random tile effect
		-- onto it. Stable Land (P-114) is enforced inside TileEffectService.ApplyTileEffect.
		if TraitEffectService.HasUnstableFooting(actor) and _tileEffectService
			and _tileEffectService.GetTileEffect and _tileEffectService.ApplyRandomTileEffect then
			local existing = _tileEffectService.GetTileEffect(actor.tileX, actor.tileY)
			if not existing then
				_tileEffectService.ApplyRandomTileEffect(actor.tileX, actor.tileY, actor.id)
			end
		end
		-- Revive the (previously dead) armor move-completion hook so GL-018 etc. accumulate too.
		if ArmorPassiveService.OnMoveCompleted then
			ArmorPassiveService.OnMoveCompleted(actor, pathCost, pathCost)
		end
		-- Charge (weapon native, Lance): accumulate tiles moved THIS TURN so a later basic attack
		-- gains +6% damage per tile. Reset at turn start by WeaponPassiveService.OnTurnStart. Counts
		-- voluntary Move path cost only (push/knockback do not run this branch). Harmless for units
		-- without Charge (plain counter; the bonus getter gates on the passive).
		actor._chargeTilesThisTurn = (actor._chargeTilesThisTurn or 0) + (pathCost or 0)
		-- ===== Armor Feet move-end reactions (2026-10-25): evaluated from the actor's FINAL tile. =====
		-- FT-010 Vanguard Greaves and FT-017 Pursuer Greaves both key off "Move ended adjacent to an
		-- enemy" (Chebyshev 1). Server-authoritative read of state.units at the landing tile.
		do
			local ax, ay = actor.tileX, actor.tileY
			local adjacentEnemies = {}
			for _, u in ipairs(state.units) do
				if u.isAlive and u.side ~= actor.side and u.tileX and u.tileY
					and math.max(math.abs(u.tileX - ax), math.abs(u.tileY - ay)) == 1 then
					adjacentEnemies[#adjacentEnemies + 1] = u
				end
			end
			if #adjacentEnemies > 0 then
				-- FT-010: arm the 15% direct-damage-reduction window (reads in CombatResolver; until next turn).
				if ArmorPassiveService.GetMoveVanguardConfig(actor) then
					actor._armorVanguardDrActive = true
					print(string.format("[CommandService] Vanguard Greaves: %s ends Move adjacent to enemy -> 15%% DR until next turn", actor.name))
				end
				-- FT-017: once per turn, +50 RT to every adjacent enemy. GetMovePursuerConfig returns nil
				-- once _armorPursuerUsed is set, so this naturally fires at most once per turn.
				local pur = ArmorPassiveService.GetMovePursuerConfig(actor)
				if pur then
					for _, e in ipairs(adjacentEnemies) do
						e.remainingRt = (e.remainingRt or 0) + pur.rtDelay
						print(string.format("[CommandService] Pursuer Greaves: %s delays %s by +%d RT (now %d)", actor.name, e.name, pur.rtDelay, e.remainingRt))
					end
					actor._armorPursuerUsed = true
				end
				-- BD-015 Sentinel Carapace: if any adjacent enemy is GUARDING and wears Sentinel Carapace, the
				-- mover loses Movement Range NEXT turn (flat, from the aura's movePenalty). Imposed as a pending
				-- debuff promoted at the mover's next turn start (ArmorPassiveService.OnTurnStart) and read in
				-- TargetingService.getMovementRange. The "wearer is Guarding" condition is locked in NOW.
				for _, e in ipairs(adjacentEnemies) do
					local eGuarding = false
					if e.statusInstances then
						for _, inst in ipairs(e.statusInstances) do
							if inst.id == "Guard" then eGuarding = true; break end
						end
					end
					if eGuarding then
						local aura = ArmorPassiveService.GetGuardMovementPenaltyAura(e)
						if aura then
							actor._sentinelSlowPending = true
							actor._sentinelSlowMag     = aura.movePenalty
							print(string.format("[CommandService] Sentinel Carapace: %s ends Move adjacent to guarding %s -> -%d Move Range next turn", actor.name, e.name, aura.movePenalty))
							break
						end
					end
				end
			end
		end
		-- FT-009 Retreat Boots move-end evaluation (2026-10-25): grant Evasiveness +20% (until next
		-- turn) only if EVERY step of this Move strictly increased the distance to the nearest enemy.
		-- Gated on the passive first (the BFS below is not free). The actor has already moved to the
		-- destination, so we briefly restore its START tile to reconstruct the server's authoritative
		-- route (the same shortest path the trap-walk uses), then restore. GetMoveCandidates is a pure
		-- query that does not mutate the actor. Per-tile "nearest enemy" distance is Chebyshev, matching
		-- the grid's adjacency metric. Interpretation (flagged for Studio): nearest enemy is recomputed
		-- per tile (moving away from one enemy but toward another fails the check).
		if ArmorPassiveService.GetMoveRetreatConfig(actor) then
			local enemies = {}
			for _, u in ipairs(state.units) do
				if u.isAlive and u.side ~= actor.side and u.tileX and u.tileY then
					enemies[#enemies + 1] = u
				end
			end
			if #enemies > 0 and (actor.tileX ~= prevTileX or actor.tileY ~= prevTileY) then
				local movedX, movedY = actor.tileX, actor.tileY
				actor.tileX, actor.tileY = prevTileX, prevTileY
				local cands = TargetingService.GetMoveCandidates(actor, state.units, _mapWidth, _mapHeight)
				actor.tileX, actor.tileY = movedX, movedY
				local routePath = nil
				for _, c in ipairs(cands) do
					if c.tileX == movedX and c.tileY == movedY then routePath = c.path; break end
				end
				local route = { { x = prevTileX, y = prevTileY } }
				if routePath then
					for _, step in ipairs(routePath) do
						route[#route + 1] = { x = step.tileX, y = step.tileY }
					end
				end
				route[#route + 1] = { x = movedX, y = movedY }
				local function nearestEnemyDist(tx, ty)
					local best = math.huge
					for _, e in ipairs(enemies) do
						local d = math.max(math.abs(e.tileX - tx), math.abs(e.tileY - ty))
						if d < best then best = d end
					end
					return best
				end
				local retreated = #route >= 2
				local prevD = nearestEnemyDist(route[1].x, route[1].y)
				for i = 2, #route do
					local d = nearestEnemyDist(route[i].x, route[i].y)
					if d <= prevD then retreated = false; break end
					prevD = d
				end
				if retreated then
					actor._armorRetreatBonusActive = true
					print(string.format("[CommandService] Retreat Boots: %s moved away from all enemies every step -> Evasiveness +20%% until next turn", actor.name))
				end
			end
		end
		-- Mark that the unit has taken an action this turn (for Martial Footwork "first action").
		actor._traitActedThisTurn = true
		-- Apply Martial Footwork outcome now that the Move has fully resolved.
		if martial == "grantAp" then
			actor.currentAp = (actor.currentAp or 0) + 1
			print(string.format("[CommandService] Martial Footwork (perk): %s replenishes 1 AP after first-move (now %d)", actor.name, actor.currentAp))
		elseif martial == "endTurn" then
			print(string.format("[CommandService] Martial Footwork (flaw): %s turn ends after first-move", actor.name))
			actor.currentAp = 0
		end

		-- UNDO REACTION DETECTION (source-based, 2026-10-17 fix for Tester item B).
		-- A Move is undoable ONLY if landing triggered no reaction. We decide this
		-- from WHAT THE DESTINATION TILE IS (its terrain trigger + any active tile
		-- effect), not by inferring from status deltas — because several reactions
		-- (Sinking, Ice/Frozen/Oily slides, Cracked Ground collapse, RandomTeleport,
		-- MoltenBurn, tick-only hazards like Static Cloud) do NOT change the mover's
		-- own status set and were previously missed (false-negatives). Conservative:
		-- if the landing tile CAN trigger any of these, undo is disabled.
		--   Reaction = (a) mover's own status set changed this landing (auras +
		--   crossEffect statuses), OR (b) destination terrain carries an
		--   irreversible triggerEffect or is a slide terrain (Ice), OR (c) an active
		--   tile effect at the destination is a hazard / applies a crossEffect /
		--   extends a slide. Flight bypasses terrain + tile effects entirely, so a
		--   flying mover is only gated by the aura/status dimension.
		local IRREVERSIBLE_TRIGGERS = {
			Drowning = true, Sinking = true, MoltenBurn = true,
			Collapse = true, RandomTeleport = true,
		}
		local reactionTriggered = (undoStatusSig(actor) ~= undoSigBefore) or trapSprung
		if not reactionTriggered and not actorFlying then
			local td = GameConstants.GetTerrainData(actor.tileX, actor.tileY)
			if td then
				if td.triggerEffect and IRREVERSIBLE_TRIGGERS[td.triggerEffect] then
					reactionTriggered = true
				elseif td.id == "Ice" then
					reactionTriggered = true  -- Sliding Knockback cross effect
				end
			end
			if not reactionTriggered and _tileEffectService and _tileEffectService.GetTileEffect then
				local te = _tileEffectService.GetTileEffect(actor.tileX, actor.tileY)
				local tdef = te and GameConstants.TILE_EFFECTS and GameConstants.TILE_EFFECTS[te.id]
				if tdef and (tdef.crossEffect or tdef.hazard or tdef.slideExtension) then
					reactionTriggered = true
				end
			end
		end
		BattleCoordinator.PushUndo(state, {
			kind       = "Move",
			actorId    = actor.id,
			reaction   = reactionTriggered,
			apCost     = apCost,
			rt         = undoMoveRt,
			prevTileX  = prevTileX,
			prevTileY  = prevTileY,
			prevFacing = prevFacing,
		})

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

		-- Dual Strike perk (P-171, 2026-10-24): basic attack resolves twice; both passes apply
		-- full damage + on-hit effects. RT cost (already doubled via GetBasicAttackRtMultiplier),
		-- the counter trigger and RT delay stay OUTSIDE this loop (once per action). On pass 2 the
		-- existing isAlive guards skip already-dead targets, and each ApplyOutcome keeps its own
		-- TRG-010 reaction gating, so a second pass cannot loop.
		local _dsPasses = TraitEffectService.GetBasicAttackResolveCount(actor)
		for _dsPass = 1, _dsPasses do
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
			totalDmg = totalDmg + outcome.finalDamage
			hitCount = hitCount + 1
		end
		end  -- Dual Strike resolve passes

		-- Reap (weapon native, Scythe): heal the attacker 5% of the TOTAL damage this basic attack
		-- dealt across all targets (DB "Heal 5% of total Cleave damage dealt"). Summed-then-once (a
		-- cleave hitting 3 heals 5% of the combined total). Direct heal, basic-attack only. No heal
		-- when totalDmg rounds the 5% to 0 (small hits). Gated on the Reap passive; 0 otherwise.
		if (totalDmg or 0) > 0 and actor.isAlive then
			local reapFrac = WeaponPassiveService.GetReapHealFraction(actor)
			if reapFrac > 0 then
				local reapHeal = math.round(totalDmg * reapFrac)
				if reapHeal > 0 then
					UnitSchema.ApplyHealing(actor, reapHeal)
					print(string.format("[CommandService] Reap: %s heals %d (5%% of %d cleave damage)", actor.name, reapHeal, totalDmg))
				end
			end
		end

		-- FT-008 Skirmisher Greaves CONSUME (whole-action, 2026-10-25): the armed +15% applies to the
		-- ENTIRE attack action -- every pattern hit and both Dual Strike passes read it above, because
		-- the window is marked used ONLY HERE, after the whole swing resolves. "next ATTACK", not "next
		-- hit" (design ruling 2026-10-25). Consumed once, real path only (never in Resolve*, which AI
		-- scoring/preview call). Gate mirrors the read; (totalDmg>0) = the action actually dealt damage.
		if (totalDmg or 0) > 0 and not actor._armorSkirmishUsed
			and ArmorPassiveService.GetMoveSkirmishDamageBonus(actor) > 0 then
			actor._armorSkirmishUsed = true
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

		-- QuickDraw (weapon native, Quiver): after 2 basic attacks, the next basic attack costs 0 RT.
		-- Per-ACTION counter (Dual Strike's double resolve is still ONE basic attack, counted once here).
		-- On the free attack rtCost is zeroed and the counter resets to 0; otherwise it increments. Only
		-- the attacker's OWN RT is waived -- the Weapon RT Delay inflicted on the target (below) is NOT.
		-- Rolling across turns (a unit rarely gets 3 basic attacks in one turn); _quickDrawCount is
		-- runtime unit state. Real commit path only -- AI scoring uses Resolve*, never this branch.
		local _qdThreshold = WeaponPassiveService.GetQuickDrawThreshold(actor)
		if _qdThreshold then
			if (actor._quickDrawCount or 0) >= _qdThreshold then
				rtCost = 0
				actor._quickDrawCount = 0
				print(string.format("[CommandService] QuickDraw: %s's basic attack costs 0 RT", actor.name))
			else
				actor._quickDrawCount = (actor._quickDrawCount or 0) + 1
			end
		end

		BattleCoordinator.AccrueRt(state, rtCost)

		-- Apply Weapon RT Delay to primary target (reduced by target VIT)
		-- Perks & Flaws (Phase 2b): Time Locker/Time Freed/Timeline Sovereign scale the
		-- RT delay this attacker INFLICTS, before target VIT resistance.
		local rawDelay = GameConstants.CalcRtDelayBonus(actor.weaponRtDelay or 0, (actor.effectiveStats and actor.effectiveStats.STR) or 10) * TraitEffectService.GetRtDelayInflictMultiplier(actor)
		if rawDelay > 0 and target.isAlive then
			local targetVit = target.effectiveStats and target.effectiveStats.VIT or 10
			local actualDelay = GameConstants.CalcRtDelayResistance(math.round(rawDelay), targetVit, (target.gearDerived and target.gearDerived.rtDelayResist or 1))
			target.remainingRt = target.remainingRt + math.max(0, actualDelay)
		end

		-- Giant race tag: melee Basic Attacks gain Knockback (primary target only)
		if target.isAlive and actor.raceId then
			local RaceData = require(game:GetService("ReplicatedStorage"):WaitForChild("Content"):WaitForChild("RaceData"))
			local raceEntry = RaceData.GetRace(actor.raceId)
			if raceEntry and raceEntry.tags then
				for _, tag in ipairs(raceEntry.tags) do
					if tag == "Giant" then
						-- Giant basic-attack knockback is MELEE (no ranged penalty); shared helper.
						local force = actor.derivedStats and actor.derivedStats.force or 1
						applyKnockback(state, actor, target, force, "GIANT")
						break
					end
				end
			end
		end

		-- Knockback (weapon native, Hammer/Club) / Pull (weapon native, Chains): on a landed basic
		-- attack, displace the PRIMARY target floor(Force/2) tiles -- away (Knockback) or toward the
		-- attacker (Pull). BASIC-ATTACK ONLY (user ruling 2026-10-26: not on skills -- skills author
		-- their own displacement). Mutually exclusive (a unit resolves at most one). Reuses the shared
		-- applyKnockback helper (trap/wall/fall/KO handling) with requestedDistance = floor(Force/2);
		-- Pull passes a reversed (toward-attacker) direction. Primary target only, mirrors Giant above.
		if target.isAlive then
			local _force = (actor.derivedStats and actor.derivedStats.force) or 1
			local _dist = math.floor(_force / 2)
			if _dist > 0 then
				if WeaponPassiveService.HasKnockbackOnHit(actor) then
					applyKnockback(state, actor, target, _force, "WPN_KNOCKBACK", nil, _dist)
				elseif WeaponPassiveService.HasPullOnHit(actor) then
					local _d0 = DisplacementService.GetPushDirection(actor, target)
					local _pullDir = { dx = -_d0.dx, dy = -_d0.dy }  -- toward the attacker
					applyKnockback(state, actor, target, _force, "WPN_PULL", _pullDir, _dist)
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
		-- Blood Casting augment (2026-10-25): +10% skill potency (the HP surcharge is paid at
		-- spend time by PayCastCost). Snapshot on a per-cast copy like Mana Surge so a channeled
		-- cast keeps it at activation without mutating the shared skill table. Only potency-scaled
		-- skills carry it (damage/heal/shield).
		do
			local _h, _blood = _castPayModes(actor, skillDef)
			if _blood and ((skillDef.power or 0) > 0 or skillDef.isHealing or skillDef.isShield) then
				local bc = table.clone(skillDef)
				bc.potencyBonusMult = (skillDef.potencyBonusMult or 1) * 1.10
				skillDef = bc
			end
		end

		-- Concentrated Effect augment (2026-10-25, Pattern family): collapse an AOE skill into
		-- a single-target hit for +25% damage. Implemented as a per-cast skillDef clone (same
		-- snapshot pattern as Mana Surge / Blood Casting) that clears aoePattern so the resolution
		-- dispatch below takes the single-target branch, and bumps potency +25% (consumed by
		-- CombatResolver for the damage result). No-op on a skill that has no aoePattern.
		do
			local _hasConcentrated = false
			if skillDef.id and AugmentEffectService.GetAugmentsForSkill then
				for _, a in ipairs(AugmentEffectService.GetAugmentsForSkill(actor, skillDef.id)) do
					if a == "AUG-CONCENTRATED-EFFECT" then _hasConcentrated = true break end
				end
			end
			-- Weapon-shaped skills count when the equipped weapon gives them an area shape (they show the
			-- "Area" tag then), so the augment never fits a skill it can't change (UAT 2026-10-27 O2).
			if _hasConcentrated and skillDef.aoePattern ~= nil
				and (skillDef.aoePattern ~= "InheritWeapon" or (actor.weaponPattern or "Single") ~= "Single") then
				local ce = table.clone(skillDef)
				ce.aoePattern = nil
				ce.potencyBonusMult = (skillDef.potencyBonusMult or 1) * 1.25
				skillDef = ce
				print(string.format("[CommandService] Concentrated Effect: %s focused to single-target (+25%%)", actor.name))
			end
		end

		-- Chain Support augment (2026-10-25, Pattern family): convert the skill to chain through
		-- up to 2 ADDITIONAL enemies (3 total) via the existing Chain resolution branch. Per-cast
		-- clone sets aoePattern="Chain3" + chainFalloff=0.75. FIDELITY NOTE: the engine's chain
		-- falloff COMPOUNDS (100% / 75% / 56%), so "75% per" is the per-jump rate, not a flat 75%
		-- on every secondary — faithful reuse of the existing mechanic (flagged, not invented).
		do
			local _hasChainSup = false
			if skillDef.id and AugmentEffectService.GetAugmentsForSkill then
				for _, a in ipairs(AugmentEffectService.GetAugmentsForSkill(actor, skillDef.id)) do
					if a == "AUG-CHAIN-SUPPORT" then _hasChainSup = true break end
				end
			end
			-- Only meaningful on a single-target damaging skill (don't override an authored AOE
			-- shape); skip healing/shield/summon/ground skills.
			if _hasChainSup and (skillDef.aoePattern == nil or skillDef.aoePattern == "InheritWeapon")
				and (skillDef.power or 0) > 0 and not skillDef.isHealing and not skillDef.isShield then
				local cs = table.clone(skillDef)
				cs.aoePattern = "Chain3"
				cs.chainFalloff = 0.75
				skillDef = cs
				print(string.format("[CommandService] Chain Support: %s chains to up to 2 extra targets (75%% falloff)", actor.name))
			end
		end

		-- Evasion Surge augment (Defensive family, reworked 2026-10-26 per user): a qualifying
		-- Direct-Damage cast BANKS one evasion charge (-15% weapon damage on that cast, potency x0.85).
		-- Each charge grants +0.30 evasiveness to ONE incoming direct hit (CombatResolver.calcHitQuality
		-- reads actor._evasionSurgeStacks) and is CONSUMED by that hit in CombatResolver.ApplyOutcome.
		-- Charges STACK across casts and persist until consumed (no turn expiry, no cap). FLAGGED tunables:
		-- the +0.30 per-charge magnitude, the absence of a stack cap, and whether the -15% cost stays.
		do
			local _hasEva = false
			if skillDef.id and AugmentEffectService.GetAugmentsForSkill then
				for _, a in ipairs(AugmentEffectService.GetAugmentsForSkill(actor, skillDef.id)) do
					if a == "AUG-EVASION-SURGE" then _hasEva = true break end
				end
			end
			if _hasEva and (skillDef.power or 0) > 0 and not skillDef.isHealing and not skillDef.isShield then
				local es = table.clone(skillDef)
				es.potencyBonusMult = (skillDef.potencyBonusMult or 1) * 0.85
				skillDef = es
				-- Reworked 2026-10-26 (user): bank ONE evasion charge instead of a duration buff. Each charge
				-- grants +0.30 evasiveness to ONE incoming direct hit, then is consumed in CombatResolver.
				-- Charges STACK across casts and persist until consumed (no turn expiry, no cap -- flagged
				-- tunables). The -15%% damage cost per cast is kept.
				actor._evasionSurgeStacks = (actor._evasionSurgeStacks or 0) + 1
				print(string.format("[CommandService] Evasion Surge: %s banks an evasion charge (now %d; -15%% dmg this cast)", actor.name, actor._evasionSurgeStacks))
			end
		end

		-- Priority Surge augment (reworked 2026-10-26, Timing family): moved to a PER-TARGET damage
		-- modifier in AugmentEffectService.OnDamageCalculation (+30%% vs a target that has NOT yet taken
		-- a turn this round). No commitment-time potency clone anymore -- the old "caster acts first"
		-- condition was replaced per user decision.

		-- Tile-occupant resolution, instant casts (crash fix 2026-10-26). A single-target cast still
		-- aimed at a ground marker here (AI ground-aimed casts, or an area skill collapsed to
		-- single-target by Concentrated Effect) resolves against whoever stands on that tile. An
		-- empty tile keeps the marker and takes the ground branch (terrain reaction only).
		-- Channeled casts are re-checked at activation instead (ActivateChanneledSkill).
		local _instantEmptyTile = false
		if target and target.isGroundTarget
			and isUnitAnchoredPattern(skillDef)  -- incl. Cleave / Chain / weapon shapes (BUG-057 fix 2)
			and not (skillDef.channelTime and skillDef.channelTime > 0)
			and not skillDef.isSummon and not skillDef.createsObject and not skillDef.repairsObject
			and (skillDef.isLeapStrike or not RacePassiveService.IsMovementSkill(skillDef)) then
			local occupant = findLiveTileOccupant(state, target.tileX, target.tileY)
			if occupant then
				target = occupant
			elseif skillDef.isShield or skillDef.isHealing or skillDef.isRevive
				or skillDef.aoePattern ~= nil then  -- Cleave / Chain / weapon shapes need a first unit
				-- These branches resolve against a UNIT (heal/shield/revive/weapon-shaped strike)
				-- and would read the marker as one. Send them to the empty-tile resolution instead.
				_instantEmptyTile = true
			end
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
			and (skillDef.isShield or skillDef.isSummon or skillDef.isHealing or skillDef.swapWithTarget
				or (skillDef.aoePattern ~= nil and skillDef.aoePattern ~= "InheritWeapon")
				or skillDef.createsObject ~= nil)
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
				stolenSlot = selection.stealSlot,  -- Steal: player's picked slot rides the channel (2026-10-24)
			})
			-- Start the looping channel VFX on the caster (damage vs heal picks the asset).
			BattleVisualBroadcaster.ChannelStarted(actor, skillDef.isHealing == true)
			BattleVisualBroadcaster.Log("channel", `{actor.name} begins channeling {skillDef.name or "a skill"} ({channelRt} CT).`, actor.id)

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

		-- INSTANT SKILL: spend the cast cost (MP, or HP for HP/Blood Casting) and resolve
		CommandService.PayCastCost(actor, skillDef, mpCost)

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

		if _instantEmptyTile then
			-- EMPTY-TILE resolution (tile targeting, 2026-10-26): a single-target heal, shield,
			-- revive or weapon-shaped strike aimed at an empty tile has no unit to affect. It
			-- hits a breakable object there (damaging skills only) and fires the element's
			-- terrain reaction; the marker never reaches a unit resolver (crash class of
			-- CombatResolver:826 'attempt to index nil with VIT').
			local elem = CombatResolver.ExtractSkillElement(skillDef)
			if (skillDef.power or 0) > 0 and not skillDef.isHealing and not skillDef.isShield then
				local objHit = ObjectEffectService.ApplyObjectHit(state, target.tileX, target.tileY, 1, elem or "Physical")
				if objHit ~= "not-found" then
					print(`[CommandService] SKILL [{skillDef.name or skillDef.id}] hits object at ({target.tileX},{target.tileY}) -> {tostring(objHit)}`)
				end
			end
			if elem and elem ~= "Physical" and _tileEffectService and _tileEffectService.ResolveElementOnTile then
				_tileEffectService.ResolveElementOnTile(target.tileX, target.tileY, elem, actor.id, state.units)
			end
			BattleCoordinator.AccrueRt(state, baseRtCost)
			print(string.format("[CommandService] SKILL [%s] | %s -> empty tile (%d,%d) | reaction:%s | MP:%d | RT:%d",
				skillDef.name or skillDef.id, actor.name, target.tileX, target.tileY, tostring(elem), mpCost, baseRtCost))

		elseif skillDef.isShield then
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
				-- "Caster Area" shields every unit in the field, any side (ruling 2026-10-26).
				local shieldAnySide = isCasterArea(skillDef)
				for _, u in ipairs(state.units) do
					if u.isAlive and (shieldAnySide or u.side == actor.side)
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

		elseif skillDef.isRevive then
			-- Revive skill (instant path, e.g. Phoenix Rite channelTime 0). Precedes the
			-- isHealing branch (revive skills also carry isHealing for VFX). Target was
			-- validated KO'd. RT still accrues whether or not it still needs reviving.
			if target and not target.isAlive then
				applyReviveSkill(actor, target, skillDef, state)
			else
				print(string.format("[CommandService] REVIVE FIZZLE | %s | %s no longer KO'd",
					actor.name, target and target.name or "target"))
			end
			BattleCoordinator.AccrueRt(state, baseRtCost)

		elseif skillDef.isHealing and hasCardTag(skillDef, "Direct Damage")
			and skillDef.aoePattern ~= nil and not isUnitAnchoredPattern(skillDef) and target and target.tileX then
			-- AREA LIFEDRAIN (Siphon Pulse, instant fallback): damage the area, caster heals from it.
			local entries, totalDmg, drainHeal = resolveAreaDrain(actor, skillDef, target.tileX, target.tileY, state)
			BattleCoordinator.AccrueRt(state, baseRtCost)
			print(string.format("[CommandService] SKILL [%s] AREA DRAIN | %s | units:%d | Dmg:%d | Drain heal:%d | MP:%d | RT:%d",
				skillDef.name or skillDef.id, actor.name, #entries, totalDmg, drainHeal, mpCost, baseRtCost))

		elseif skillDef.isHealing and not hasCardTag(skillDef, "Direct Damage")
			and skillDef.aoePattern ~= nil and not isUnitAnchoredPattern(skillDef)
			and target and target.tileX then
			-- AREA HEAL (instant): every unit in the pattern, any side; the tile is never a unit.
			local entries = resolveAreaHealing(actor, skillDef, target.tileX, target.tileY, state)
			BattleCoordinator.AccrueRt(state, baseRtCost)
			print(string.format("[CommandService] SKILL [%s] AREA HEAL | %s at (%d,%d) | units:%d | MP:%d | RT:%d",
				skillDef.name or skillDef.id, actor.name, target.tileX, target.tileY, #entries, mpCost, baseRtCost))

		elseif isDualHealDamage(skillDef) and target and not target.isGroundTarget
			and not dualHealsTarget(actor, target) then
			-- Dark Restoration (instant fallback) on a non-heal target: Dark damage.
			local outcome, dealt = resolveDualDamage(actor, target, skillDef, state)
			if outcome.type == "Damage" then
				_primaryTargetDamage = dealt
			end
			BattleCoordinator.AccrueRt(state, baseRtCost)
			print(string.format("[CommandService] SKILL [%s] DARK | %s -> %s | %d | MP:%d | RT:%d",
				skillDef.name or skillDef.id, actor.name, target.name, dealt, mpCost, baseRtCost))

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
			local _soulEchoKills = {}
			for _, t in ipairs(targets) do
				if t.isAlive then
					local outcome = CombatResolver.ResolveSkill(actor, t, skillDef)
					CombatResolver.ApplyOutcome(outcome, t, actor)
					totalDmg = totalDmg + outcome.finalDamage
					if t.id == target.id then _primaryTargetDamage = outcome.finalDamage or 0 end
					hitCount = hitCount + 1
					if not t.isAlive then table.insert(_soulEchoKills, { v = t, dmg = outcome.finalDamage or 0 }) end
				end
			end
			for _, k in ipairs(_soulEchoKills) do trySpawnSoulEcho(actor, skillDef, k.v, k.dmg, state) end
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
			local _soulEchoKills = {}
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
					if not u.isAlive then table.insert(_soulEchoKills, { v = u, dmg = outcome.finalDamage or 0 }) end
				end
			end
			for _, k in ipairs(_soulEchoKills) do trySpawnSoulEcho(actor, skillDef, k.v, k.dmg, state) end
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
			local _soulEchoKills = {}
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
						if not u.isAlive then table.insert(_soulEchoKills, { v = u, dmg = outcome.finalDamage or 0 }) end
					end
				end
				end
			end
			end  -- tile loop (for aoeTiles)
			-- Soul Echo (2026-10-26): spawn AFTER the tile loop (never mid-iteration of the live
			-- ipairs(state.units) scan above) so adding echo units cannot disturb the AOE walk.
			for _, k in ipairs(_soulEchoKills) do trySpawnSoulEcho(actor, skillDef, k.v, k.dmg, state) end
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
				-- Same hit list as the channeled path (shared helper).
				local aoeTargets = weaponPatternTargets(actor, target, state.units, inheritedPattern)

				if aoeTargets then
					local _soulEchoKills = {}
					for _, entry in ipairs(aoeTargets) do
						if entry.unit.isAlive then
							local outcome = CombatResolver.ResolveSkill(actor, entry.unit, skillDef)
							outcome.finalDamage = math.max(0, math.round(outcome.finalDamage * entry.dmgMult))
							if entry.dmgMult < 1.0 then outcome.isAOE = true end
							CombatResolver.ApplyOutcome(outcome, entry.unit, actor)
							totalDmg = totalDmg + outcome.finalDamage
							if entry.unit.id == target.id then _primaryTargetDamage = outcome.finalDamage or 0 end
							hitCount = hitCount + 1
							if not entry.unit.isAlive then table.insert(_soulEchoKills, { v = entry.unit, dmg = outcome.finalDamage or 0 }) end
						end
					end
					for _, k in ipairs(_soulEchoKills) do trySpawnSoulEcho(actor, skillDef, k.v, k.dmg, state) end
				end
				BattleCoordinator.AccrueRt(state, baseRtCost)

				print(string.format(
					"[CommandService] SKILL [%s] Inherit[%s] | %s | Hits:%d | TotalDmg:%d | MP:%d | RT:%d | AP left:%d",
					skillDef.name or skillDef.id, inheritedPattern,
					actor.name, hitCount, totalDmg, mpCost, baseRtCost, actor.currentAp
				))

			elseif skillDef.isPurify and target and not target.isGroundTarget then
			-- Purifying Form: remove ONE real debuff (kind=="Debuff") from the target (ally or self)
			-- or, since tile targeting (2026-10-26), any unit on the chosen tile.
			-- and grant Debuff Resistance +15% (Purified buff, 1000 CT). Placed BEFORE the SELF branch
			-- so a self-cast still cleanses+buffs (the SELF branch would only apply a status, not cleanse).
			-- Uses RemoveRandomDebuff (user decision 2026-10-25): the authored "dispellable" flag is only
			-- on buffs in the data, so cleanse targets actual debuffs instead. FLAGGED: no per-debuff
			-- picker exists, so it removes a RANDOM active debuff (not a player-selected one).
			local _purged = StatusService.RemoveRandomDebuff(target)
			StatusService.ApplyStatus(target, "Purified", actor.id)
			if BattleVisualBroadcaster.UnitStateChanged then BattleVisualBroadcaster.UnitStateChanged(target) end
			BattleCoordinator.AccrueRt(state, baseRtCost)
			print(string.format("[CommandService] SKILL [%s] PURIFY | %s -> %s | purged:%s +Purified | RT:%d",
				skillDef.name or skillDef.id, actor.name, target.name, tostring(_purged), baseRtCost))

			elseif skillDef.relocatesAllyAdjacent and target and target.side == actor.side and target.id ~= actor.id then
			-- Fated Escape: teleport the selected ally to a free tile CARDINALLY adjacent to the caster.
			-- Respects displacement immunity (a Steadfast ally is not relocated). If no cardinal tile is
			-- free, the skill fizzles (RT still spent) -- flagged.
			local _moved = false
			if not target._displacementImmune then
				local _cards = {
					{ x = actor.tileX, y = actor.tileY - 1 }, { x = actor.tileX, y = actor.tileY + 1 },
					{ x = actor.tileX - 1, y = actor.tileY }, { x = actor.tileX + 1, y = actor.tileY },
				}
				for _, c in ipairs(_cards) do
					if c.x >= 1 and c.y >= 1
						and (not state.mapWidth or c.x <= state.mapWidth)
						and (not state.mapHeight or c.y <= state.mapHeight) then
						local _occ = false
						for _, u in ipairs(state.units) do
							if u.isAlive and u.id ~= target.id and u.tileX == c.x and u.tileY == c.y then _occ = true break end
						end
						if not _occ then
							target.tileX, target.tileY = c.x, c.y
							BattleVisualBroadcaster.UnitMoved(target)
							_moved = true break
						end
					end
				end
			end
			BattleCoordinator.AccrueRt(state, baseRtCost)
			print(string.format("[CommandService] SKILL [%s] FATED ESCAPE | %s moved %s | success:%s | RT:%d",
				skillDef.name or skillDef.id, actor.name, target.name, tostring(_moved), baseRtCost))

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

			elseif skillDef.swapWithTarget and target and target.side == actor.side and target.id ~= actor.id then
			-- Phantom Exchange (instant fallback): swap with the selected ally, no damage.
			applySwap(actor, target)
			BattleCoordinator.AccrueRt(state, baseRtCost)

			-- Buff-tagged skills may be cast on ANY side (ruling 2026-10-26); a debuff on a foe keeps
			-- the normal hit path below (resistance/reaction rules), exactly as before.
			elseif target and not target.isGroundTarget and target.id ~= actor.id
				and (target.side == actor.side or (hasCardTag(skillDef, "Buff") and not hasCardTag(skillDef, "Debuff")))
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
			-- Movement skills (Blink, Opportunist's Step): relocate the CASTER to the selected legal
			-- empty tile. Keyed on the existing RacePassiveService.IsMovementSkill classification
			-- (MOVEMENT_SKILL_IDS) so we reuse the one movement-skill source of truth, not a parallel
			-- list. Voluntary self-move (not a forced push) so displacement immunity does not block it;
			-- guard only against landing on a living unit. FLAGGED: Opportunist's Step is authored as
			-- path-based (walks intermediate tiles, resolving tile-entry effects); this relocates to the
			-- end tile directly (no intermediate tile-entry resolution) -- a simplification to flag.
			-- Leap strikes (Dragon Dive) land through landLeapStrike after the hit, which also refuses
			-- walls and objects (UAT 2026-10-27 D1); everything else relocates here as before.
			if RacePassiveService.IsMovementSkill(skillDef) and not skillDef.isLeapStrike
				and target and target.tileX and target.tileY then
				local _blocked = false
				for _, u in ipairs(state.units) do
					if u.isAlive and u.id ~= actor.id and u.tileX == target.tileX and u.tileY == target.tileY then
						_blocked = true break
					end
				end
				-- Gravity Pylon aura (2026-10-26): Blink is a teleport; blocked inside a lock aura.
				-- Walking / leaping movement skills are not teleports and are unaffected.
				if skillDef.id == "SKL-BLINK" and StatusService.IsTeleportLocked(actor) then
					_blocked = true
					print(`[CommandService] BLINK blocked | {actor.name} inside a teleport-lock aura`)
				end
				if not _blocked then
					actor.tileX, actor.tileY = target.tileX, target.tileY
					BattleVisualBroadcaster.UnitMoved(actor)
					print(string.format("[CommandService] MOVE SKILL [%s] | %s relocated to (%d,%d)",
						skillDef.name or skillDef.id, actor.name, target.tileX, target.tileY))
				end
			end
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
			-- GENERIC OBJECT-PLACING skill (2026-10-17): a skill with createsObject = "<ObjectData
			-- id>" drops that object on the chosen empty tile (e.g. Ice Spike). Reuses the
			-- battle-ready ObjectEffectService.PlaceObjectInstance primitive, which guards
			-- against stacking / placing a solid object on a living unit, renders the model,
			-- and registers it as a real blocker (movement + LoS + HP). First of the planned
			-- skill-placed blocker family — any future object (Earth Column, Magic Wall, ...)
			-- reuses this branch via data alone, no new code. MP already spent + RT accrued on
			-- this commit path; placement failing (occupied/invalid) is a no-op (object just is
			-- not created), consistent with the createsTileEffect gap behaviour above.
			if skillDef.createsObject and target and target.tileX then
				-- Enemy-only trigger for INSTANTLY-placed skill traps (2026-10-25): stamp the
				-- caster side so TriggerTrap gates the trap to enemies of the owner, exactly like
				-- the deferred trap-deploy path (L1441). Without this, an instant createsObject
				-- trap (e.g. Poison Trap) carried no ownerSide and would spring on allies too.
				-- Blockers ignore ownerSide (TriggerTrap only gates step-on traps), so passing it
				-- is harmless for non-trap objects (e.g. Ice Spike).
				ObjectEffectService.PlaceObjectInstance(
					state, skillDef.createsObject, target.tileX, target.tileY, actor.side, actor.id
				)
			end
			-- Tile targeting includes objects (ruling 2026-10-26): a damaging skill aimed at an
			-- unoccupied tile holding a breakable object lands one hit on it, like a basic attack
			-- on the object (ApplyObjectHit: 1 hit, element instant-kill tags apply).
			if target and target.tileX and not skillDef.createsObject
				and (skillDef.power or 0) > 0 and not skillDef.isHealing and not skillDef.isShield then
				local objHit = ObjectEffectService.ApplyObjectHit(state, target.tileX, target.tileY, 1,
					CombatResolver.ExtractSkillElement(skillDef) or "Physical")
				if objHit ~= "not-found" then
					print(`[CommandService] SKILL [{skillDef.name or skillDef.id}] hits object at ({target.tileX},{target.tileY}) -> {tostring(objHit)}`)
				end
			end
			-- All-tile widening (Option A, 2026-10-24): a widened skill committed on an
			-- EMPTY tile fires the terrain reaction for the skill's element (fire igniting
			-- grass, etc.) — the "set grass on fire" play. Tile-keyed per the locked
			-- Terrain Reaction principle. Occupied tiles never reach here (the occupant
			-- is resolved as a unit target in BattleTurnController). nil-safe: no element
			-- / no tile-effect service = no-op. Physical returns false inside Resolve.
			if TargetingService.IsWidenedSkill(skillDef) and _tileEffectService
				and _tileEffectService.ResolveElementOnTile and target and target.tileX then
				local elem = CombatResolver.ExtractSkillElement(skillDef)
				if elem and elem ~= "Physical" then
					_tileEffectService.ResolveElementOnTile(
						target.tileX, target.tileY, elem, actor.id, state.units
					)
					print(string.format("[CommandService] WIDENED SKILL [%s] empty-tile %s reaction at (%d,%d)",
						skillDef.name or skillDef.id, elem, target.tileX, target.tileY))
				end
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

			local _mugWasAlive = target.isAlive  -- Mug KO-steal gate (2026-10-24)
			local outcome = CombatResolver.ResolveSkill(actor, target, skillDef)
			local actualDmg, statusApplied = CombatResolver.ApplyOutcome(outcome, target, actor)
			_primaryTargetDamage = actualDmg or outcome.finalDamage or 0
			BattleCoordinator.AccrueRt(state, baseRtCost)

			-- Shared post-hit effects (RT delay incl. Time Locker trait, skill knockback).
			applySkillPostHit(state, actor, target, skillDef, _primaryTargetDamage)

			-- Pattern augments — secondary-target pass (2026-10-25). On a single-target damaging
			-- skill, these augments add extra hits at a falloff %, reusing existing TargetingService
			-- geometry helpers. One augment applies (first match). Secondary hits are flagged isAOE
			-- so they don't recurse per-hit augment riders. Primary already hit above; we skip it here.
			--   Impact Splash  -> 4 cardinal neighbours of target @50% (GetImpactSplashTargets)
			--   Line Projection-> unit directly behind target @75%   (GetLine2Targets)
			--   Piercing Shot  -> unit directly behind target @60%   (GetLine2Targets)
			--   Wide Arc       -> flank tiles adjacent to caster+target @40% (GetCleaveTargets)
			if (skillDef.power or 0) > 0 and not skillDef.isHealing and not skillDef.isShield
				and target and target.tileX and not target.isGroundTarget then
				local _patMode, _patMult = nil, nil
				if skillDef.id and AugmentEffectService.GetAugmentsForSkill then
					for _, a in ipairs(AugmentEffectService.GetAugmentsForSkill(actor, skillDef.id)) do
						if a == "AUG-IMPACT-SPLASH" then _patMode, _patMult = "splash", 0.50 break
						elseif a == "AUG-LINE-PROJECTION" then _patMode, _patMult = "line", 0.75 break
						elseif a == "AUG-PIERCING-SHOT" then _patMode, _patMult = "line", 0.60 break
						elseif a == "AUG-WIDE-ARC" then _patMode, _patMult = "arc", 0.40 break
						elseif a == "AUG-BOUNCE-SHOT" then _patMode, _patMult = "bounce", 0.50 break
						end
					end
				end
				if _patMode then
					local extra = {}
					if _patMode == "splash" then
						for _, e in ipairs(TargetingService.GetImpactSplashTargets(actor, target, state.units)) do
							if e.unit and e.unit.id ~= target.id then table.insert(extra, e.unit) end
						end
					elseif _patMode == "line" then
						for _, e in ipairs(TargetingService.GetLine2Targets(actor, target, state.units)) do
							if e.unit and e.unit.id ~= target.id then table.insert(extra, e.unit) end
						end
					elseif _patMode == "arc" then
						-- Wide Arc (ruling 2026-10-26): flank tiles hit whoever stands there, any side.
						for _, u in ipairs(TargetingService.GetCleaveTargets(actor, target, state.units, true)) do
							if u.id ~= target.id then table.insert(extra, u) end
						end
					elseif _patMode == "bounce" then
						-- Bounce Shot: 1 bounce to the NEAREST living enemy within 3 tiles of the
						-- primary (excluding the primary), at 50% damage. Enemies only (ruling
						-- 2026-10-26): allies and untouched Neutrals are never bounce targets.
						local best, bestD = nil, math.huge
						for _, u in ipairs(state.units) do
							if u.isAlive and u.side ~= actor.side and u.side ~= "Neutral" and not u.isGroundTarget
								and u.id ~= target.id and u.tileX then
								local d = math.max(math.abs(u.tileX - target.tileX), math.abs((u.tileY or 0) - (target.tileY or 0)))
								if d <= 3 and d < bestD then best, bestD = u, d end
							end
						end
						if best then table.insert(extra, best) end
					end
					local secHits, secDmg = 0, 0
					for _, u in ipairs(extra) do
						if u.isAlive then
							local o = CombatResolver.ResolveSkill(actor, u, skillDef)
							o.finalDamage = math.max(0, math.round((o.finalDamage or 0) * _patMult))
							o.isAOE = true
							CombatResolver.ApplyOutcome(o, u, actor)
							secHits = secHits + 1
							secDmg = secDmg + o.finalDamage
						end
					end
					if secHits > 0 then
						print(string.format("[CommandService] Pattern augment [%s]: %s hit %d extra target(s) for %d (x%.2f)",
							_patMode, actor.name, secHits, secDmg, _patMult))
					end
				end
			end

			-- Chain Kill augment (2026-10-25, Kill Trigger): if this single-target damaging skill
			-- KO'd the primary (alive before -> dead now), repeat it ONCE on a different valid
			-- enemy at 70% weapon scaling (costFormula ×0.70). Hard "no chain of chains" guard:
			-- the repeat hit is applied inline (one ResolveSkill/ApplyOutcome) and gated by
			-- actor._chainKillFiring so it can never re-enter. Different-target: nearest living
			-- enemy (not the corpse) within the skill's range of the caster.
			if _mugWasAlive and not target.isAlive and not actor._chainKillFiring
				and (skillDef.power or 0) > 0 and not skillDef.isHealing and not skillDef.isShield
				and (skillDef.aoePattern == nil or skillDef.aoePattern == "InheritWeapon")
				and AugmentEffectService.IsKillCreditEligible(actor, target) then
				local _hasChainKill = false
				if skillDef.id and AugmentEffectService.GetAugmentsForSkill then
					for _, a in ipairs(AugmentEffectService.GetAugmentsForSkill(actor, skillDef.id)) do
						if a == "AUG-CHAIN-KILL" then _hasChainKill = true break end
					end
				end
				if _hasChainKill and actor.isAlive then
					local reach = skillDef.range or 1
					local best, bestD = nil, math.huge
					for _, u in ipairs(state.units) do
						if u.isAlive and u.side ~= actor.side and not u.isGroundTarget
							and u.id ~= target.id and u.tileX then
							local d = math.max(math.abs(u.tileX - (actor.tileX or 0)), math.abs((u.tileY or 0) - (actor.tileY or 0)))
							if d <= reach and d < bestD then best, bestD = u, d end
						end
					end
					if best then
						actor._chainKillFiring = true
						local o = CombatResolver.ResolveSkill(actor, best, skillDef)
						o.finalDamage = math.max(0, math.round((o.finalDamage or 0) * 0.70))
						CombatResolver.ApplyOutcome(o, best, actor)
						actor._chainKillFiring = nil
						print(string.format("[CommandService] Chain Kill: %s repeats [%s] on %s (70%%)",
							actor.name, skillDef.name or skillDef.id, best.name))
					end
				end
			end

			-- Soul Echo augment (AUG-SOUL-ECHO / Summoning, updated 2026-10-26): on a kill, drop a 1-HP
			-- echo on the victim's tile (detonates next turn for 30% of kill damage as Dark AOE, handled
			-- in Main's summon-turn branch). Now fires on EVERY kill via trySpawnSoulEcho (single-target
			-- here + each AOE loop); multiple echoes coexist (no cap / add). _mugWasAlive gates that the
			-- primary was alive before this hit, so a kill here is attributable to this cast.
			if _mugWasAlive then
				trySpawnSoulEcho(actor, skillDef, target, outcome.finalDamage or 0, state)
			end

			-- Mug (DOC-THIEF-01) KO-steal (2026-10-24): if THIS hit KO'd the target and it
			-- still has a stealable piece, take ONE random non-weapon slot. No pick, no
			-- rear-tile rule (Mug's own condition). Seeded Random (not math.random) keeps
			-- combat reproducible. Item leaves the corpse -> a later revive comes back without
			-- it (consistent). Stashed on battle state for victory loot, like Steal.
			if skillDef.id == "DOC-THIEF-01" and _mugWasAlive and not target.isAlive then
				local mslots = GameConstants.GetStealableSlots(target)
				if #mslots > 0 then
					local rng = Random.new((state.ct or 0) + (actor.tileX or 0) * 31 + (target.tileY or 0) * 17)
					local pick = mslots[rng:NextInteger(1, #mslots)]
					local okU, removed = EquipmentService.Unequip(target, pick)
					if okU and removed then
						removed.stolen = true
						state.stolenItems = state.stolenItems or {}
						table.insert(state.stolenItems, removed)
						print(string.format("[CommandService] Mug KO-steal | %s took %s (%s) from %s",
							actor.name, removed.instanceId or "?", pick, target.name))
						BattleVisualBroadcaster.Log("steal", `{actor.name} mugs {pick} from {target.name}.`, target.id)
					end
				end
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
		-- Leap strike (Dragon Dive): the caster lands after the hit and BEFORE any counter, so a counter
		-- measures reach from where the caster actually is (UAT 2026-10-27 A6).
		if skillDef.isLeapStrike and target and target.tileX then
			landLeapStrike(actor, target.tileX, target.tileY, state)
		end

		-- Dark Restoration's damage side is an offensive hit: it can provoke a counter (UAT A2).
		local _offensiveHit = not skillDef.isHealing
			or (isDualHealDamage(skillDef) and _primaryTargetDamage > 0)
		if _offensiveHit and target and target.id and not target.isGroundTarget then
			CommandService.TriggerCounterIfEligible(target, actor, state, false, false, _primaryTargetDamage > 0)
		end

		-- FT-008 Skirmisher Greaves CONSUME (whole-action, skill path, 2026-10-25): a damage skill is
		-- ONE action -- all its hits (single/AOE/chain/cleave/inherit) read the +15% above; the window
		-- is marked used HERE once, after the whole skill resolves, only when it dealt damage
		-- (_primaryTargetDamage > 0, the same signal the counter uses). Real path only; heal/buff/
		-- ground/summon skills keep _primaryTargetDamage 0 and never consume the window.
		if _primaryTargetDamage > 0 and not actor._armorSkirmishUsed
			and ArmorPassiveService.GetMoveSkirmishDamageBonus(actor) > 0 then
			actor._armorSkirmishUsed = true
		end

		-- CHARGE SELF-COST: lose 10% current HP after damage (min 1 HP remaining)
		if skillDef.isCharge and actor.isAlive then
			local selfCost = math.max(1, math.floor(actor.currentHp * 0.10))
			actor.currentHp = math.max(1, actor.currentHp - selfCost)
			print(string.format(
				"[CommandService] CHARGE SELF-COST | %s lost %d HP (10%%) | HP: %d/%d",
				actor.name, selfCost, actor.currentHp, actor.maxHp or 0))
		end

		-- Augment OnSkillComplete (2026-10-24): once-per-cast augment hook for the INSTANT
		-- resolution path. Center = the skill's primary target tile. nil-safe; no-op when the
		-- skill carries no augments. (Channeled skills fire the same hook in ActivateChanneledSkill.)
		if skillDef and skillDef.id and target then
			local _scAug = AugmentEffectService.GetAugmentsForSkill(actor, skillDef.id)
			if _scAug and #_scAug > 0 then
				AugmentEffectService.OnSkillComplete(actor, skillDef, _scAug, {
					state = state, centerX = target.tileX, centerY = target.tileY,
					affectedTiles = skillAffectedTiles(actor, skillDef, target.tileX, target.tileY),
				})
			end
		end

		-- Update facing: face toward skill target (unit-targeted skills only)
		if target and target.tileX and not skillDef.isSelfTarget then
			local skillFacing = GameConstants.CalcFacingFrom(actor.tileX, actor.tileY, target.tileX, target.tileY)
			if skillFacing then
				actor.facing = skillFacing
				BattleVisualBroadcaster.FacingChanged(actor)
			end
		end

		-- Hide dispel: offensive skill breaks Hide (non-healing only; Dark Restoration's damage counts)
		if _offensiveHit and StatusService.HasStatus(actor, "Hide") then
			StatusService.RemoveStatus(actor, "Hide")
			print(string.format("[CommandService] %s Hide dispelled (offensive skill)", actor.name))
		end

	elseif actionType == "Wait" then
		print(string.format("[CommandService] WAIT | %s", actor.name))
		BattleVisualBroadcaster.Log("action", `{actor.name} waits.`, actor.id)
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
		-- Armor Guard RT modifier (e.g. "Guard RT ×0.60" faster-guard body armor). Applied to the
		-- assembled Guard RT before the Frozen all-RT multiplier. 1.0 when absent. (Armor wiring 2026-10-24)
		guardRt = math.round(guardRt * ArmorPassiveService.GetGuardRtModifier(actor))
		-- Frozen: all RT costs ×2
		guardRt = math.round(guardRt * StatusService.GetAllRtMultiplier(actor))

		-- Apply Guard as a proper status (dispellable buff, removed by CC)
		StatusService.ApplyStatus(actor, "Guard", actor.id)
		-- BD-006 Layered Lamellar (2026-10-24): reset successive-hit DR counter so each new Guard
		-- session starts fresh (stacking is within one Guard, not cumulative across guards).
		ArmorPassiveService.OnGuardEnd(actor)
		actor.guardBonus = RacePassiveService.GetGuardMitigationBonus(actor)
			+ TraitEffectService.GetGuardMitigationBonus(actor) -- TRAIT-GUARD (Guard Specialist / Klutz, additive like Golem)
		-- Armor guard mitigation (e.g. body armor "damage reduction 35%→45%") must actually REDUCE
		-- damage, not just display — fold it into guardBonus which the damage path reads. (Fix 2026-10-24)
		local armorGuardBonus = ArmorPassiveService.GetGuardMitigationBonus(actor)
		actor.guardBonus = (actor.guardBonus or 0) + armorGuardBonus
		-- GuardBonus (weapon native, Shield): +15% mitigation while Guarding. Same fold as armor/trait.
		actor.guardBonus = (actor.guardBonus or 0) + WeaponPassiveService.GetGuardMitigationBonus(actor)
		actor.guardUsedThisTurn = true
		-- BD-019 Second-Wind Vest (2026-10-24): recover 10% Max HP when Guard is activated. 0 for
		-- units without the passive. Uses the standard healing path (respects Max HP cap).
		local regenPct = ArmorPassiveService.GetGuardRegenPercent(actor)
		if regenPct > 0 then
			local healAmt = math.max(0, math.round((actor.maxHp or 0) * regenPct))
			if healAmt > 0 then
				UnitSchema.ApplyHealing(actor, healAmt)
				print(string.format("[CommandService] Second-Wind Vest: %s recovers %d HP on Guard | HP: %d/%d",
					actor.name, healAmt, actor.currentHp, actor.maxHp or 0))
			end
		end
		BattleCoordinator.AccrueRt(state, guardRt)

		print(string.format(
			"[CommandService] GUARD | %s | RT:%d | OffHandWT:%d | AP left:%d",
			actor.name, guardRt, offHandWt, actor.currentAp
		))

		-- Calculate effective mitigation for display
		-- actor.guardBonus now already includes armorGuardBonus (folded in above), so do NOT add it again.
		local mitigation = GameConstants.GUARD_MITIGATION + (actor.guardBonus or 0)
		mitigation = math.min(mitigation, GameConstants.GUARD_CAP)
		BattleVisualBroadcaster.ActionAnnounced(actor, "Guard")
		BattleVisualBroadcaster.GuardActivated(actor, guardRt, mitigation)

		-- UNDO (2026-10-17): Guard triggers no environmental reaction, so it is
		-- always reversible within the turn. Record what to undo: the AP, the RT
		-- Guard accrued, and the guard-stance flags/status to clear on revert.
		BattleCoordinator.PushUndo(state, {
			kind     = "Guard",
			actorId  = actor.id,
			reaction = false,
			apCost   = apCost,
			rt       = guardRt,
		})

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
		-- GL-005 Butcher's Gloves: Push becomes PULL. When no race Pull override (Android) is active,
		-- synthesize an equivalent override from the glove conversion config so ALL the existing pull
		-- machinery (reverseDirection, min range 2 cannot-target-adjacent, extended range) applies with
		-- no new push-resolution code. Normal Push Force (no forceBonus). Race override wins if present.
		local grapplerSwap = false
		if not pushOverride then
			local conv = ArmorPassiveService.GetPushConversionConfig(actor)
			if conv and conv.mode == "Pull" then
				pushOverride = {
					reverseDirection = true,
					minDistance = conv.minRange or 2,
					maxDistance = 1 + (conv.rangeBonus or 0),
					label = "Pull",
				}
			elseif conv and conv.mode == "Swap" then
				-- GL-017 Grappler's Wraps: NOT a pushOverride (range stays adjacent-1, no reverseDirection
				-- flag). The swap + fling-behind direction are applied at the direction step below.
				grapplerSwap = true
			end
		end
		-- GL-004 Longarm Bracers: Push Maximum Range +1 (additive with any race Pull override). pushContext
		-- below also drives GL-001/002/006/018 force and GL-003/006 RT for this unit push.
		local pushContext = { isAlly = (target.side == actor.side), isObject = false, isFreePush = (initiatorFreeCfg ~= nil) }
		local maxPushDist = (pushOverride and pushOverride.maxDistance or 1) + ArmorPassiveService.GetPushRangeBonus(actor)
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
		-- GL-003 Quickgrip (x0.75) / GL-006 Ally Launcher (x0.50 on ally pushes): glove Push-RT modifier.
		pushRt = math.round(pushRt * ArmorPassiveService.GetPushRtModifier(actor, pushContext))
		BattleCoordinator.AccrueRt(state, pushRt)

		-- Resolve displacement
		local force = 1
		if actor.derivedStats and actor.derivedStats.force then
			force = actor.derivedStats.force
		end
		if pushOverride and pushOverride.forceBonus then
			force = force + pushOverride.forceBonus
		end
		-- Glove Push-Force bonuses: GL-001 (+1), GL-002 (+3), GL-006 (+3 vs ally), GL-018 Momentum
		-- (+0.5 per tile moved this turn, floored). Context-aware; 0 for units without a Gloves passive.
		force = force + ArmorPassiveService.GetPushForceBonus(actor, pushContext)
		-- GL-021 Initiator's Grips: the free push trades power for tempo -- Force x0.5 (min 1); its RT x2
		-- already folds in via pushContext.isFreePush -> GetPushRtModifier. Marks the once-per-turn flag.
		if initiatorFreeCfg then
			force = math.max(initiatorFreeCfg.minForce or 1, math.floor(force * (initiatorFreeCfg.forceMultiplier or 0.5)))
			actor._armorFreePushUsed = true
		end
		local direction
		if grapplerSwap then
			-- GL-017 Grappler's Wraps (fling-behind, user ruling 2026-10-26): SWAP places with the target
			-- FIRST, then fling the target AWAY from the user's NEW position -- the reverse of the original
			-- user->target direction -- so it is thrown past where the user originally stood. The target is
			-- displaced (below) from the user's ORIGINAL tile; ResolvePush steps it from there.
			local origUX, origUY = actor.tileX, actor.tileY
			local origTX, origTY = target.tileX, target.tileY
			local d0 = DisplacementService.GetPushDirection(actor, target)  -- original user->target dir
			actor.tileX, actor.tileY = origTX, origTY    -- user takes the target's tile
			target.tileX, target.tileY = origUX, origUY  -- target takes the user's original tile
			if BattleVisualBroadcaster.UnitMoved then BattleVisualBroadcaster.UnitMoved(actor) end
			direction = { dx = -d0.dx, dy = -d0.dy }      -- fling away from the user's new position
		else
			direction = DisplacementService.GetPushDirection(actor, target)
			if pushOverride and pushOverride.reverseDirection then
				-- Pull: reverse the push direction. FIX 2026-10-25: GetPushDirection returns {dx,dy} and
				-- ResolvePush reads direction.dx/.dy -- the old {x=-direction.x,...} built a {x,y} table with
				-- nil .dx/.dy, which errored any Pull (Android race override + GL-005 Butcher's). Now {dx,dy}.
				direction = { dx = -direction.dx, dy = -direction.dy }
			end
		end
		-- GL-001 Reinforced Gloves: ignore up to 2 of the target's Stability on this push (0 for units
		-- without the glove). Passed as the trailing ResolvePush arg; isRanged=false (global push is melee).
		local pushStabIgnore = ArmorPassiveService.GetPushStabilityIgnore(actor)
		local result = DisplacementService.ResolvePush(
			actor, target, force, direction,
			GameConstants.KNOCKBACK_SOURCE_MODIFIERS.GlobalPush,
			state.units, requestedDistance, false, pushStabIgnore
		)

		-- GL-009 Ram Gauntlets (user-follows): remember the tile the target occupied BEFORE the push,
		-- so a Ram wearer can advance into it after the shove (captured pre-move while it is still the
		-- target's tile).
		local ramFollowX, ramFollowY = target.tileX, target.tileY
		-- Apply position change
		target.tileX = result.finalTileX
		target.tileY = result.finalTileY
		-- Forced-movement trap trigger (2026-10-20): a push that drags the target
		-- across step-on trap tiles springs each one. Actor-targeted effects
		-- (Pinned/Bleed/RT/direct damage) apply to the pushed unit; a Land Mine
		-- detonates at its tile. Forced momentum does NOT stop early (only a KO ends
		-- the unit). Walks the crossed-tile list ResolvePush now returns.
		if ObjectEffectService and result.tilesPath then
			for _, tp in ipairs(result.tilesPath) do
				local trap = ObjectEffectService.GetTriggeredTrapAt(state, tp.x, tp.y)
				if trap then ObjectEffectService.TriggerTrap(target, trap, state, state.units) end
			end
		end

		-- Apply collision/fall damage
		local totalPushDmg = 0
		if result.wallCollision and result.wallCollision.damage > 0 then
			totalPushDmg = totalPushDmg + result.wallCollision.damage
		end
		if result.fallDamage and result.fallDamage > 0 then
			totalPushDmg = totalPushDmg + result.fallDamage
		end
		-- GL-012 Crushing Vambraces: this pusher's collision/fall damage drains the target's shield at
		-- x2 (shield half as effective). "Ignores Guard" needs no code -- push damage already bypasses
		-- Guard mitigation (that lives in CombatResolver resolve, which push does not use). Pusher-keyed.
		local crushCfg = ArmorPassiveService.GetPushCollisionConfig(actor)
		local pushShieldMult = (crushCfg and crushCfg.type == "Crush" and crushCfg.doubleVsShields) and 2 or 1
		if totalPushDmg > 0 then
			UnitSchema.ApplyDamage(target, totalPushDmg, "push", pushShieldMult)
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

		-- GL-014 Chain-Push Bracers: if the pushed target COLLIDED with another UNIT, transfer the
		-- REMAINING force (original force minus tiles already traveled) to that collided unit, shoving it
		-- one chain further in the same direction, with its OWN collision/fall damage. Single transfer --
		-- the chained push does NOT re-chain (no loop). Pusher-keyed; only when remaining force > 0.
		-- A PULL that slams the target into the acting unit itself never chain-transfers: the
		-- user cannot shove themself (fix 2026-10-26, UAT thread-7c99505298a5, Android/GL-005
		-- Pull + GL-014 Chain-Push Bracers).
		if result.wallCollision and result.wallCollision.collidedUnitId
			and result.wallCollision.collidedUnitId ~= actor.id then
			local chain = ArmorPassiveService.GetPushCollisionConfig(actor)
			if chain and chain.type == "Chain" then
				local remaining = math.max(0, force - (result.tilesDisplaced or 0))
				if remaining > 0 then
					for _, u in ipairs(state.units) do
						if u.id == result.wallCollision.collidedUnitId and u.isAlive then
							local cres = DisplacementService.ResolvePush(actor, u, remaining, direction,
								GameConstants.KNOCKBACK_SOURCE_MODIFIERS.GlobalPush, state.units, nil, false)
							if cres and cres.pushed then
								u.tileX = cres.finalTileX
								u.tileY = cres.finalTileY
								local chainDmg = 0
								if cres.wallCollision and cres.wallCollision.damage and cres.wallCollision.damage > 0 then chainDmg = chainDmg + cres.wallCollision.damage end
								if cres.fallDamage and cres.fallDamage > 0 then chainDmg = chainDmg + cres.fallDamage end
								if chainDmg > 0 then UnitSchema.ApplyDamage(u, chainDmg, "push") end
								applyForcedEntryEffects(u, cres)
								if BattleVisualBroadcaster.UnitPushed then BattleVisualBroadcaster.UnitPushed(actor, u, cres) end
								print(string.format("[CommandService] Chain-Push: %s transfers %d force to %s", actor.name, remaining, u.name))
							end
							break
						end
					end
				end
			end
		end

		-- GL-020 Shockwave Gauntlets: when this push caused a COLLISION (target slammed into a wall/
		-- unit/edge), units CARDINALLY adjacent to the collision tile (the target's final tile) are
		-- shoved 1 tile straight away from it. Displacement only (no damage): ResolvePush is used purely
		-- for positioning (force 99 clamped to requestedDistance 1 -> always 1 tile, ignoring stability
		-- like a shockwave; walls/occupied tiles still stop it). Pusher-keyed. nil-safe.
		if result.wallCollision then
			local shock = ArmorPassiveService.GetPushCollisionConfig(actor)
			if shock and shock.type == "Shockwave" then
				local cx, cy = target.tileX, target.tileY
				local CARDINALS = { {dx=1,dy=0}, {dx=-1,dy=0}, {dx=0,dy=1}, {dx=0,dy=-1} }
				for _, d in ipairs(CARDINALS) do
					local nx, ny = cx + d.dx, cy + d.dy
					for _, u in ipairs(state.units) do
						if u.isAlive and u ~= actor and u ~= target and u.tileX == nx and u.tileY == ny then
							local sres = DisplacementService.ResolvePush(actor, u, 99, { dx = d.dx, dy = d.dy },
								GameConstants.KNOCKBACK_SOURCE_MODIFIERS.GlobalPush, state.units, 1, false)
							if sres and sres.pushed then
								u.tileX = sres.finalTileX
								u.tileY = sres.finalTileY
								if BattleVisualBroadcaster.UnitPushed then BattleVisualBroadcaster.UnitPushed(actor, u, sres) end
							end
							break
						end
					end
				end
				print(string.format("[CommandService] Shockwave Gauntlets: %s collision shockwave around (%d,%d)", actor.name, cx, cy))
			end
		end

		-- Broadcast
		BattleVisualBroadcaster.UnitPushed(actor, target, result)

		-- ===== Glove on-push reactions (2026-10-25): fire only on a push that actually moved the target
		-- (tilesDisplaced > 0); a fully-resisted 0-distance push triggers neither. =====
		if (result.tilesDisplaced or 0) > 0 then
			-- GL-011 Staggering Fists: +75 RT Delay (flat, raw -- mirrors Pursuer Greaves/Ogre idiom) and
			-- -1 Movement Range on the target's NEXT turn (generic imposed accumulator, promoted at the
			-- target's OnTurnStart, read in getMovementRange).
			local stagger = ArmorPassiveService.GetPushDebuffConfig(actor)
			if stagger and target.isAlive then
				target.remainingRt = (target.remainingRt or 0) + (stagger.rtDelay or 0)
				if stagger.movePenalty and stagger.movePenalty < 0 then
					target._imposedMovePendingMag = (target._imposedMovePendingMag or 0) + (-stagger.movePenalty)
				end
				print(string.format("[CommandService] Staggering Fists: %s +%d RT, -%d Move next turn",
					target.name, stagger.rtDelay or 0, -(stagger.movePenalty or 0)))
			end
			-- GL-019 Counterforce Gloves: after a successful push, the pusher auto-Guards at no AP (does
			-- NOT spend the Guard action economy -- mirrors BD-005 Reactive Cuirass). guardBonus uses the
			-- same Race+Trait+Armor fold as the manual Guard command.
			if actor.isAlive and ArmorPassiveService.CanPushTriggerGuard(actor) then
				local alreadyGuard = false
				if actor.statusInstances then
					for _, inst in ipairs(actor.statusInstances) do
						if inst.id == "Guard" then alreadyGuard = true; break end
					end
				end
				if not alreadyGuard then
					StatusService.ApplyStatus(actor, "Guard", actor.id)
					actor.guardBonus = RacePassiveService.GetGuardMitigationBonus(actor)
						+ TraitEffectService.GetGuardMitigationBonus(actor)
						+ ArmorPassiveService.GetGuardMitigationBonus(actor)
						+ WeaponPassiveService.GetGuardMitigationBonus(actor)
					if BattleVisualBroadcaster.UnitStateChanged then BattleVisualBroadcaster.UnitStateChanged(actor) end
					print(string.format("[CommandService] Counterforce Gloves: %s auto-Guards after push", actor.name))
				end
			end
			-- GL-016 Fighter's Gauntlets: the push also deals 30% of base weapon damage AND triggers weapon
			-- on-hit effects. Reuses ResolveBasicAttack (weapon on-hit statuses ride along via
			-- outcome.appliesStatuses that ApplyOutcome applies) scaled to 30%, then ApplyOutcome. ENEMY-only
			-- (an offensive strike + on-hit debuffs on a pushed ally would be clearly wrong; DB is silent, so
			-- enemy-gated by ruling 2026-10-25). ApplyOutcome does NOT itself fire counters (separate
			-- CommandService call), so a push-strike cannot provoke a counter-attack.
			if target.isAlive and target.side ~= actor.side then
				local fdmg = ArmorPassiveService.GetPushDamageConfig(actor)
				if fdmg then
					local fgOutcome = CombatResolver.ResolveBasicAttack(actor, target, actor.weaponDamage or 10)
					if fgOutcome and fgOutcome.type == "Damage" then
						fgOutcome.finalDamage = math.max(0, math.round((fgOutcome.finalDamage or 0) * fdmg.weaponDamagePercent))
						CombatResolver.ApplyOutcome(fgOutcome, target, actor)
						print(string.format("[CommandService] Fighters Gauntlets: %s push-strikes %s for %d (30%% weapon dmg + on-hit)",
							actor.name, target.name, fgOutcome.finalDamage))
					end
				end
			end
			-- GL-009 Ram Gauntlets (user-follows): the pusher advances ONE tile into the space the target
			-- vacated (ramFollowX/Y), so a ram carries the attacker forward. Only when the target actually
			-- moved (tilesDisplaced>0, this gate) AND that vacated tile is now empty (no unit, not blocked)
			-- so the pusher never lands on an occupied/illegal tile. Pure position move; no extra RT/AP.
			if actor.isAlive then
				local ramCfg = ArmorPassiveService.GetPushCollisionConfig(actor)
				if ramCfg and ramCfg.userFollows and (ramFollowX ~= actor.tileX or ramFollowY ~= actor.tileY) then
					local occupied = false
					for _, u in ipairs(state.units) do
						if u.isAlive and u.tileX == ramFollowX and u.tileY == ramFollowY then occupied = true; break end
					end
					if not occupied and not GameConstants.IsBlocked(ramFollowX, ramFollowY) then
						actor.tileX = ramFollowX
						actor.tileY = ramFollowY
						if BattleVisualBroadcaster.UnitMoved then BattleVisualBroadcaster.UnitMoved(actor) end
						print(string.format("[CommandService] Ram Gauntlets: %s follows into (%d,%d)", actor.name, ramFollowX, ramFollowY))
					end
				end
			end
		end

		local actionLabel = pushOverride and pushOverride.label or "PUSH"
		print(string.format(
			"[CommandService] %s | %s -> %s | Force:%d | Moved:%d to (%d,%d) | Dmg:%d | RT:%d | AP left:%d",
			actionLabel, actor.name, target.name, force,
			result.tilesDisplaced, result.finalTileX, result.finalTileY,
			totalPushDmg, pushRt, actor.currentAp
		))

	elseif actionType == "PushObject" then
		-- OBS Phase 2c-E2: push a breakable blocker-prop OBS object (map_gen_rules row 83).
		-- Mirrors the unit Push RT/force/direction; objects take NO collision/fall damage.
		-- Same AP (1, charged in STEP 8) and RT as a unit push (user decision 2026-10-14).
		-- The unit "Push" branch above is byte-unchanged; this is a separate branch and,
		-- like it, falls through to the shared Momentum/EndTurn tail.
		if type(selection) ~= "table" or not selection.objX or not selection.objY then
			return false, "Object push requires a target tile."
		end
		local ox, oy = selection.objX, selection.objY
		local pushOverride = RacePassiveService.GetPushOverride(actor)
		local maxPushDist = pushOverride and pushOverride.maxDistance or 1
		local minPushDist = pushOverride and pushOverride.minDistance or 1
		local dist = math.max(math.abs(actor.tileX - ox), math.abs(actor.tileY - oy))
		if dist > maxPushDist then return false, "Target is out of range." end
		if dist < minPushDist then return false, "Target is too close." end
		BattleVisualBroadcaster.ActionAnnounced(actor, "Push")

		-- Push RT = round(Modified Base RT * 0.10), *2 if Frozen -- identical to unit push.
		local modBaseRt = StatusService.GetModifiedBaseRt(actor)
		local pushRt = math.round(modBaseRt * GameConstants.GUARD_RT_BASE_FACTOR)
		pushRt = math.round(pushRt * StatusService.GetAllRtMultiplier(actor))
		BattleCoordinator.AccrueRt(state, pushRt)

		local force = 1
		if actor.derivedStats and actor.derivedStats.force then
			force = actor.derivedStats.force
		end
		if pushOverride and pushOverride.forceBonus then
			force = force + pushOverride.forceBonus
		end
		-- GL-008 Siege Bracers: Push Force +3 when the target is a movable object. Context isObject=true
		-- selects this glove only (0 for other gloves / no glove). Mirrors the unit-push force fold.
		force = force + ArmorPassiveService.GetPushForceBonus(actor, { isAlly = false, isObject = true, isFreePush = false })
		local direction = DisplacementService.GetPushDirection(actor, { tileX = ox, tileY = oy })
		local ddx, ddy = direction.dx, direction.dy
		if pushOverride and pushOverride.reverseDirection then
			ddx, ddy = -ddx, -ddy
		end
		local result = ObjectEffectService.PushObject(state, ox, oy, ddx, ddy, force)
		local outcome = (type(result) == "table") and "moved" or tostring(result)
		-- GL-007 Demolition Mitts: if the pushed object COLLIDED (stopped early against a wall / unit /
		-- map edge), it detonates as a Bomb Barrel (3x3, 30%% Max HP) at its final tile and is destroyed.
		-- nil for units without the glove. Reuses the object-owned DetonateObjectAt helper. (Edge: an
		-- object shoved against an ADJACENT obstacle -- 0 tiles moved -- returns "blocked" and does not
		-- detonate; detonation requires the object to travel >=1 tile then strike something.)
		if type(result) == "table" and result.collided then
			local demo = ArmorPassiveService.GetPushObjectDetonation(actor)
			if demo then
				ObjectEffectService.DetonateObjectAt(state, result.toX, result.toY, demo.damagePercent, state.units, actor.id)
			end
		end
		print(string.format(
			"[CommandService] PUSH OBJECT | %s -> obj(%d,%d) | Force:%d | %s | RT:%d | AP left:%d",
			actor.name, ox, oy, force, outcome, pushRt, actor.currentAp
		))

	elseif actionType == "AttackObject" then
		-- OBS Phase 2c-B: a basic attack targeting a breakable blocker-prop OBS object
		-- (map_gen_rules row 82: 3 hits from ANY source, incl. a direct attack, break it).
		-- One basic attack = one hit via ObjectEffectService.ApplyObjectHit. Same AP (1,
		-- charged in STEP 8) and the same basic-attack RT a unit attack costs. Does NOT
		-- touch the unit isAlive/CombatResolver/crit/status path; the unit "Attack" branch
		-- is byte-unchanged. Billboards are never offered as candidates and ApplyObjectHit
		-- double-guards immovable/unbreakable. Falls through to the shared Momentum/EndTurn tail.
		if type(selection) ~= "table" or not selection.objX or not selection.objY then
			return false, "Object attack requires a target tile."
		end
		local ox, oy = selection.objX, selection.objY
		local atkRange = (actor.weaponMaxRange or 1) + RacePassiveService.GetRangeModifier(actor)
			+ TraitEffectService.GetAttackRangeModifier(actor) -- Restless / Sniper's Perch (2026-10-23)
		local atkDist = math.max(math.abs(actor.tileX - ox), math.abs(actor.tileY - oy))
		if atkDist > atkRange or atkDist < (actor.weaponMinRange or 1) then
			return false, "Object is out of attack range."
		end
		BattleVisualBroadcaster.ActionAnnounced(actor, "Basic Attack")
		local rtCost = calcBasicAttackBaseRt(actor)
		BattleCoordinator.AccrueRt(state, rtCost)
		-- Pass the attacker's weapon element so an object weak to it (instantKillTags,
		-- e.g. Ice Spike vs Fire) is destroyed in one hit. Default "Physical" = no weakness.
		local result = ObjectEffectService.ApplyObjectHit(state, ox, oy, 1, actor.weaponElement or "Physical")
		print(string.format(
			"[CommandService] ATTACK OBJECT | %s -> obj(%d,%d) | %s | RT:%d | AP left:%d",
			actor.name, ox, oy, tostring(result), rtCost, actor.currentAp
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

		-- HD trap headgear "Interact disarms adjacent traps; reveals hidden traps within 3 tiles":
		-- a rider on ANY committed Interact. Disarm = remove a Trap-tagged object within disarmRange
		-- (Chebyshev 1) of the actor; reveal = clear o.hidden on a Trap object within revealRange (3).
		-- Keyed on the actor's Head passive; nil without it. Safe no-op if no trap objects present.
		do
			local _trapCfg = ArmorPassiveService.GetInteractTrapConfig(actor)
			if _trapCfg and state.objects then
				local _disarmed, _revealed = 0, 0
				-- iterate a snapshot copy since disarm removes from state.objects mid-loop
				local _objs = {}
				for _, ob in ipairs(state.objects) do _objs[#_objs + 1] = ob end
				for _, ob in ipairs(_objs) do
					local odef = ob.type and ObjectData.Objects and ObjectData.Objects[ob.type]
					local isTrap = false
					if odef and odef.tags then
						for _, tg in ipairs(odef.tags) do if tg == "Trap" then isTrap = true; break end end
					end
					if isTrap and ob.x and ob.y then
						local d = math.max(math.abs(ob.x - actor.tileX), math.abs(ob.y - actor.tileY))
						if d <= (_trapCfg.disarmRange or 1) then
							ObjectEffectService.RemoveObjectInstance(state, ob)
							if BattleVisualBroadcaster.ObjectChanged then BattleVisualBroadcaster.ObjectChanged(ob.x, ob.y, { destroyed = true }) end
							_disarmed = _disarmed + 1
						elseif ob.hidden and d <= (_trapCfg.revealRange or 3) then
							ob.hidden = false
							if BattleVisualBroadcaster.ObjectChanged then BattleVisualBroadcaster.ObjectChanged(ob.x, ob.y, { revealed = true }) end
							_revealed = _revealed + 1
						end
					end
				end
				if _disarmed > 0 or _revealed > 0 then
					print(string.format("[CommandService] Trap headgear: %s disarmed %d, revealed %d trap(s)", actor.name, _disarmed, _revealed))
				end
			end
		end

		local modBaseRt = StatusService.GetModifiedBaseRt(actor)
		-- Interact RT multiplier hook: HD-001 Quickhand Hood → ×0.75 (nil-safe → 1.0).
		local interactRtMult = 1.0
		if (ArmorPassiveService :: any).GetInteractRtMultiplier then
			interactRtMult = (ArmorPassiveService :: any).GetInteractRtMultiplier(actor) or 1.0
		end
		-- D-2 fix (UAT 2026-10-26): keep a copy; every rejection below hands the bonus back,
		-- so only an Interact that actually resolves uses it up.
		local _ampSaved = actor._interactAmp
		-- UTI-016 Interaction Amplifier: this Interact costs RT x0.80 and uses up the bonus.
		if actor._interactAmp then
			interactRtMult = interactRtMult * (actor._interactAmp.rtMult or 1)
			actor._interactAmp = nil
		end

		if chosen.interactKind == "recruitEnemy" then
			-- Find the target unit.
			local target = nil
			for _, u in ipairs(state.units) do
				if u.id == chosen.id then target = u; break end
			end
			if not target or not target.isAlive then
				actor._interactAmp = _ampSaved
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
			-- Optional objective "Recruit": count each enemy recruited this battle.
			ObjectiveService.RecordEvent(state, "enemiesRecruited", 1)
			-- HD-006 Diplomat's Veil: heal 35% max HP on recruit (nil-safe → none).
			if (ArmorPassiveService :: any).GetRecruitHealFraction then
				local healFrac = (ArmorPassiveService :: any).GetRecruitHealFraction(actor) or 0
				if healFrac > 0 then
					local _rh = math.ceil((target.maxHp or 1) * healFrac)
					-- Festering Wound anti-heal (2026-10-25): recruit heal reduced too.
					local _hrm = StatusService.GetHealingReceivedMult(target)
					if _hrm ~= 1 then _rh = math.max(0, math.floor(_rh * _hrm)) end
					local _hpBefore = target.currentHp or 0
					target.currentHp = math.min(target.maxHp or 1,
						(target.currentHp or 0) + _rh)
					if (target.currentHp or 0) > _hpBefore then StatusService.WeakenVenomOnHeal(target) end  -- healing weakens Venom (2026-10-26)
				end
			end
			BattleVisualBroadcaster.UnitStateChanged(target)
			print(string.format(
				"[CommandService] INTERACT RECRUIT | %s recruits %s -> Neutral | RT:%d | AP left:%d",
				actor.name, target.name, rt, actor.currentAp
			))
			BattleVisualBroadcaster.Log("action", `{actor.name} recruits {target.name} (now a neutral ally).`, actor.id)

		elseif chosen.interactKind == "allyRtHelp" then
			local target = nil
			for _, u in ipairs(state.units) do
				if u.id == chosen.id then target = u; break end
			end
			if not target or not target.isAlive then
				actor._interactAmp = _ampSaved
				return false, "Ally target is invalid."
			end
			-- Native ally RT help: reduce target's CURRENT RT by 35% of current.
			local before = target.remainingRt or 0
			local reduced = before - math.round(before * 0.35)
			-- HD-004 Chronologist Monocle: extra flat −50 after the 35% cut
			-- (nil-safe → 0). Floor at 0.
			if (ArmorPassiveService :: any).GetAllyRtFlatBonus then
				reduced = reduced - ((ArmorPassiveService :: any).GetAllyRtFlatBonus(actor) or 0)
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
			BattleVisualBroadcaster.Log("rt", `{actor.name} aids {target.name}: RT {before} → {target.remainingRt}.`, actor.id)

		elseif chosen.interactKind == "reviveAlly" then
			local target = nil
			for _, u in ipairs(state.units) do
				if u.id == chosen.id then target = u; break end
			end
			if not target then
				actor._interactAmp = _ampSaved
				return false, "Revive target is invalid."
			end
			if target.isAlive then
				actor._interactAmp = _ampSaved
				return false, target.name .. " is not KO'd."
			end
			-- CHANNELED resuscitate (native 200 CT). Reuses the two-timer channel
			-- pipeline: a synthetic skill-shaped descriptor carries interactResolve
			-- so ActivateChanneledSkill applies the revive at the deadline.
			-- HD-017 Rescue Marshal Helm: channel 200 → 130 CT (nil-safe → 200).
			local channelCt = 200
			if (ArmorPassiveService :: any).GetReviveChannelCt then
				channelCt = (ArmorPassiveService :: any).GetReviveChannelCt(actor) or 200
			end
			-- HD-003 Field Medic Coif: revive HP 5% → 15% (nil-safe → 0.05).
			local reviveHpFrac = 0.05
			if (ArmorPassiveService :: any).GetReviveHpFraction then
				reviveHpFrac = (ArmorPassiveService :: any).GetReviveHpFraction(actor) or 0.05
			end
			-- Interact-on-KO'd-ally RT cost = 30% of Modified Base RT.
			-- HD-016 Signal Officer Beret: 30% → 15% (nil-safe → 0.30).
			local reviveRtPct = 0.30
			if (ArmorPassiveService :: any).GetReviveRtPct then
				reviveRtPct = (ArmorPassiveService :: any).GetReviveRtPct(actor) or 0.30
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
			BattleVisualBroadcaster.Log("channel", `{actor.name} begins resuscitating {target.name} ({channelCt} CT).`, actor.id)
			return true, nil -- turn ended (two-timer); revive resolves at deadline

		elseif chosen.interactKind == "mapObject" then
			-- Slice 5: charge 1 AP + native RT (free vs consumes-action), then
			-- resolve the object's EFFECT via ObjectEffectService. RT fallback is
			-- round(ModBaseRt × 0.10) unless the object defines interactRtPct.
			local objArch = chosen.archetypeId
			local objDef = objArch and ObjectData.Objects and ObjectData.Objects[objArch] or nil
			local activation = objDef and objDef.activation or "Interact (Consumes Action)"
			-- HD break headgear: Interact DESTROYS a breakable object in ONE action regardless of HP
			-- (a breakable blocker normally needs multiple AttackObject hits). Lethal ApplyObjectHit;
			-- "immune"/number (non-breakable, e.g. a chest/shrine) leaves brokeObject false so the normal
			-- object EFFECT below still runs. nil-safe; RT is charged either way (it is an Interact action).
			local brokeObject = false
			if ArmorPassiveService.CanInteractBreakObjects and ArmorPassiveService.CanInteractBreakObjects(actor) then
				local _br = ObjectEffectService.ApplyObjectHit(state, chosen.tileX, chosen.tileY, 999999, nil)
				if _br == "destroyed" or _br == "detonated" then brokeObject = true end
			end
			-- Authored flat RT (ObjectData.interactRT, e.g. Astrolabe 400) wins; otherwise
			-- the basic Interact cost round(ModBaseRt x 0.10). Headgear modifier applies to both.
			local rt
			if objDef and objDef.interactRT then
				rt = math.round(objDef.interactRT * interactRtMult)
			else
				local objRtPct = (objDef and objDef.interactRtPct) or 0.10
				rt = math.round(modBaseRt * objRtPct * interactRtMult)
			end
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
			local effOk, effReason = true, nil
			if brokeObject then
				print(string.format("[CommandService] INTERACT BREAK | %s destroys breakable %s in one action | RT:%d",
					actor.name, tostring(objArch), (activation == "Interact (Free)") and 0 or rt))
			else
				effOk, effReason =
					ObjectEffectService.Resolve(actor, objInstance, state, state.units)
				-- CLEAN CANCEL (2026-10-26): the player tapped Cancel during a siege
				-- targeting prompt. Resolve returned (false, "CANCELLED") and did NOT
				-- consume the object. Give back the action: refund the RT accrued above
				-- and the AP charged at Step 6, then reject so executePlayerCommand
				-- returns nil and the turn loop re-prompts the SAME unit with full AP/RT
				-- (same refund+re-prompt pattern as Undo). Nothing is net-charged.
				if (not effOk) and effReason == "CANCELLED" then
					if activation ~= "Interact (Free)" then
						BattleCoordinator.RefundRt(state, rt)
					end
					actor.currentAp = (actor.currentAp or 0) + apCost
					-- Also reset the turn-action flag so a cancel-then-idle turn keeps
					-- its RT-rest discount. Recompute from the undo stack (not an
					-- unconditional clear) so a cancel AFTER a real move this turn still
					-- counts as an action. (2026-10-26 rest-RT fix.)
					BattleCoordinator.RecomputeActionTaken(state)
					print(string.format("[CommandService] INTERACT CANCELLED | %s aborted %s targeting — AP/RT refunded",
						actor.name, tostring(objArch)))
					actor._interactAmp = _ampSaved
					return false, "cancelled"
				end
				print(string.format(
					"[CommandService] INTERACT OBJECT | %s -> %s | activation:%s | RT:%d | effect:%s",
					actor.name, tostring(objArch), activation,
					(activation == "Interact (Free)") and 0 or rt,
					effOk and "ok" or ("FAILED: " .. tostring(effReason))
				))
				-- SINGLE-USE OBJECTS LEAVE THE MAP (user ruling 2026-10-26): once a "Once"
				-- object has been used, remove it and its model, free its tile, and tell
				-- clients (closes its info card). Reuses the same removal the step-on traps
				-- use. Safe for objects whose own effect already removed them (Mimic, Stone
				-- Pillar): RemoveObjectInstance and the model removal tolerate a missing entry.
				if effOk and objDef and (objDef.uses or "Once") == "Once" then
					ObjectEffectService.RemoveObjectInstance(state, objInstance)
					if BattleVisualBroadcaster.ObjectChanged then
						BattleVisualBroadcaster.ObjectChanged(chosen.tileX, chosen.tileY, { destroyed = true })
					end
				end
			end
			BattleVisualBroadcaster.Log("action", `{actor.name} activates {(objDef and objDef.name) or tostring(objArch)}{if effOk then "" else " (no effect)"}.`, actor.id)

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
				actor._interactAmp = _ampSaved
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
			BattleVisualBroadcaster.Log("action", `{actor.name} interacts with {target.name}.`, actor.id)

		else
			actor._interactAmp = _ampSaved
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

		-- AC-017 Conservation Charm: the SECOND manual Item action each turn consumes NO charge (and
		-- costs RT x2, folded below). GetItemConservationConfig returns non-nil only when the unit has
		-- the charm, has NOT yet used the conserve this turn, and already took >=1 manual item action
		-- this turn (_armorManualItemCount). nil for everyone else -> normal charge deduction.
		local _consCfg = ArmorPassiveService.GetItemConservationConfig(actor)
		if _consCfg and _consCfg.noChargeConsume then
			-- Conserved: no charge spent, no "charge spent" objective tick.
			actor._armorConservationUsed = true
		else
			-- Deduct 1 charge (item stays equipped at 0 charges but is unusable)
			slot.currentCharges = slot.currentCharges - 1
			-- Optional objective "Glutton": count each consumable charge spent.
			ObjectiveService.RecordEvent(state, "chargesUsed", 1)
		end
		-- Count this manual Item action (drives Conservation's "second action this turn").
		actor._armorManualItemCount = (actor._armorManualItemCount or 0) + 1

		-- RT cost comes from the consumable definition (fixed, not weapon-scaled)
		local rtCost = consumableDef.rtCost or 80
		-- CHEMIST — Field Chemistry: Consumable Item RT Cost -20% (2026-10-20)
		rtCost = math.round(rtCost * DoctrinePassiveService.GetConsumableRtModifier(actor))
		-- AC Accessory item-RT modifier: AC-002 Quickdraw x0.75, AC-016 Mirror Charm x1.50 (the cost of
		-- its self-copy benefit, wired below), AC-019 x1.20. 1.0 without an item-RT accessory.
		rtCost = math.round(rtCost * ArmorPassiveService.GetItemRtModifier(actor))
		-- AC-017 Conservation Charm: the conserved (no-charge) action costs RT x2 (same _consCfg gate).
		if _consCfg and _consCfg.rtMultiplier then
			rtCost = math.round(rtCost * _consCfg.rtMultiplier)
		end
		-- Frozen: all RT costs x2
		rtCost = math.round(rtCost * StatusService.GetAllRtMultiplier(actor))
		local _itemPreActionTaken = state.turnActionTaken
		BattleCoordinator.AccrueRt(state, rtCost)

		-- DEPLOYABLE items (2026-10-26): a functional-by-placement object deploy places its
		-- archetype into battle state via the existing object pipeline (solid blockers block
		-- move/LoS; entry-triggered traps fire through the trap pipeline). ItemEffectService
		-- classifies (functional vs placement-only-shell); CommandService does the state
		-- mutation here (it owns `state`). Summon-kind / pulse / shell / defer deploys are NOT
		-- functional yet and fall through to resolveItemEffect -> Unimplemented (logged, never
		-- faked). KNOWN DELTA (flagged for Simulator/Designer): a placed Land Mine uses its
		-- archetype's authored explosion (25% Max HP), NOT the item's own power+RT rider -- that
		-- override needs the trap-payload pass; placement is still a real, functional mine.
		local effectResult
		local _deployPlan = ItemEffectService.GetDeployPlan(consumableDef)
		local _devicePlan = ItemEffectService.GetDevicePlan(consumableDef, actor)
		if _devicePlan and type(target) == "table" and target.tileX then
			-- ITEM DEVICE (2026-10-26): Sentry Turret / Mender Drone / Decoy Totem / Gravity Pylon /
			-- Elemental Ward Totem. A ward aura takes the element the player picked (validated
			-- before any cost by ValidateItemChoice).
			if _devicePlan.auraSpec and _devicePlan.auraSpec.wardMult then
				_devicePlan.auraSpec.wardElement = selection.choice
			end
			effectResult = spawnItemDevice(actor, consumableDef, _devicePlan, target, state)
		elseif _deployPlan and _deployPlan.functional and type(target) == "table" and target.tileX then
			local placed = ObjectEffectService.PlaceObjectInstance(
				state, _deployPlan.ref, target.tileX, target.tileY, actor.side, actor.id)
			if placed then
				-- Placed siege object (Portable Ballista): fix its shot power from the PLACER's
				-- stats now, and its shot count, on the live instance (2026-10-26).
				local _arch = ObjectData.Objects[_deployPlan.ref]
				if _arch and _arch.shotPowerFormula then
					placed.shotPower = ItemEffectService.ItemDamageFromFormula(actor, _arch.shotPowerFormula)
					placed.shotsLeft = _arch.shots or 1
				end
				-- Supply Station: its stock of supplies.
				if _arch and _arch.supplies then
					placed.supplies = _arch.supplies
				end
				-- Rescue Beacon: allies already KO'd when it is placed never count (only the
				-- first KO AFTER placement is rescued).
				if _arch and _arch.rescueRadius then
					placed.ignoreKo = {}
					for _, u in ipairs(state.units) do
						if not u.isAlive then placed.ignoreKo[u.id] = true end
					end
				end
				effectResult = { effectType = "Deploy", amount = 0,
					description = consumableDef.name .. " deployed " .. _deployPlan.ref }
				print(string.format("[CommandService] DEPLOY [%s] | %s placed %s at (%d,%d)",
					consumableDef.name, actor.name, _deployPlan.ref, target.tileX, target.tileY))
			else
				effectResult = { effectType = "DeployFailed", amount = 0,
					description = "placement blocked at target tile" }
				print(string.format("[CommandService] DEPLOY [%s] | placement blocked at (%s,%s)",
					consumableDef.name, tostring(target.tileX), tostring(target.tileY)))
			end
		else
			-- Non-deploy (or not-yet-functional deploy) -> normal item effect resolution.
			local _weatherPlan = ItemEffectService.GetWeatherPlan(consumableDef)
			local _pushPlan = ItemEffectService.GetPushPlan(actor, consumableDef)
			local _terrainPlan = ItemEffectService.GetTerrainPlan(consumableDef, selection.choice)
			local _isWard = ItemEffectService.IsElementWardItem(consumableDef) and consumableDef.targetRules ~= "Empty Tile"
			local _isCleanse = ItemEffectService.IsCleanseChoiceItem(consumableDef)
			local _isExtend = ItemEffectService.IsBuffExtendItem(consumableDef)
			local _tilePlan = ItemEffectService.GetTileEffectPlan(consumableDef)
			local _swapPlan = ItemEffectService.GetSwapPlan(consumableDef)
			local _revealPlan = ItemEffectService.GetRevealPlan(consumableDef)
			local _teleportPlan = ItemEffectService.GetTeleportPlan(consumableDef)
			local _winchPlan = ItemEffectService.GetWinchPlan(consumableDef)
			local _snarePlan = ItemEffectService.GetSnarePlan(consumableDef)
			local _galePlan = ItemEffectService.GetGalePlan(consumableDef)
			local _roadPlan = ItemEffectService.GetRoadPlan(consumableDef)
			local _digPlan = ItemEffectService.GetExcavatePlan(consumableDef)
			local _isRepair = ItemEffectService.IsRepairItem(consumableDef)
			local _climbPlan = ItemEffectService.GetClimbPlan(consumableDef)
			local _isRelay = ItemEffectService.IsChargeRelayItem(consumableDef)
			local _isRecall = ItemEffectService.IsRecallItem(consumableDef)
			local _firebreakPlan = ItemEffectService.GetFirebreakPlan(consumableDef)
			-- Free legal landing tile for rescue moves: in bounds, passable, unblocked, empty.
			local function _freeTile(x: number, y: number): boolean
				if x < 1 or y < 1 or x > _mapWidth or y > _mapHeight then return false end
				if GameConstants.IsImpassableTerrain(x, y) or GameConstants.IsBlocked(x, y) then return false end
				for _, u in ipairs(state.units) do
					if u.isAlive and u.tileX == x and u.tileY == y then return false end
				end
				return true
			end
			-- Landing on a tile springs its trap and entry effects (same as teleport / swap).
			local function _landOn(u: any)
				BattleVisualBroadcaster.UnitMoved(u)
				if ObjectEffectService and ObjectEffectService.GetTriggeredTrapAt then
					local trap = ObjectEffectService.GetTriggeredTrapAt(state, u.tileX, u.tileY)
					if trap then ObjectEffectService.TriggerTrap(u, trap, state, state.units) end
				end
				if u.isAlive then applyForcedEntryEffects(u, { pushed = true }) end
			end
			-- Line/Cone tile items need a direction: a target tile different from the user's.
			local _tilePat = (tostring(consumableDef.pattern or "Single"):gsub("%s+", ""))
			local _tileAimOk = not ((_tilePat:match("^Line") or _tilePat:match("^Cone"))
				and type(target) == "table" and target.tileX == actor.tileX and target.tileY == actor.tileY)
			if _terrainPlan and type(target) == "table" and target.tileX and _tileEffectService
				and _tileEffectService.TransformTileTerrain then
				-- TERRAIN TRANSFORM (2026-10-26): for each tile in the item's AOE pattern, if the
				-- tile's current terrain matches a rule's `from` list, swap it to the rule's `to`
				-- via TileEffectService.TransformTileTerrain (handles client re-skin + water voxel
				-- clear). Protected spans (bridges / required routes / objective tiles) are SKIPPED
				-- per-tile (not the whole use) via GameConstants.IsProtectedSpan, so one protected
				-- tile never wastes the charge. Secondary clauses flagged DEFER in the item data
				-- (move-cost zones, sliding end, poison-cloud removal) are NOT applied here.
				local tiles = TargetingService.GetAOETargetTiles(
					(tostring(consumableDef.pattern or "Single"):gsub("%s+", "")),
					actor, target.tileX, target.tileY, _mapWidth, _mapHeight)
				-- Single-tile patterns (no AOE expansion) resolve to just the target tile.
				if not tiles or #tiles == 0 then
					tiles = { { tileX = target.tileX, tileY = target.tileY } }
				end
				-- Ruling 18 (2026-10-26): deployment-zone tiles of either side are protected too.
				local _deploySet = {}
				for _, list in ipairs({ state.playerDeployTiles or {}, state.enemyDeployTiles or {} }) do
					for _, d in ipairs(list) do _deploySet[d.x .. "," .. d.y] = true end
				end
				local changed = 0
				for _, t in ipairs(tiles) do
					if not GameConstants.IsProtectedSpan(t.tileX, t.tileY)
						and not _deploySet[t.tileX .. "," .. t.tileY] then
						local cur = GameConstants.GetTerrainId(t.tileX, t.tileY)
						for _, rule in ipairs(_terrainPlan.rules) do
							local hit = false
							for _, fromId in ipairs(rule.from) do
								if fromId == cur then hit = true break end
							end
							if hit then
								if _tileEffectService.TransformTileTerrain(t.tileX, t.tileY, rule.to) then
									changed += 1
								end
								break  -- first matching rule wins for this tile
							end
						end
					end
				end
				effectResult = { effectType = "Terrain", amount = changed,
					description = string.format("%s transformed %d tile(s)", consumableDef.name, changed) }
				print(string.format("[CommandService] ITEM TERRAIN [%s] | %s | %d tile(s) changed",
					consumableDef.name, actor.name, changed))
			elseif _weatherPlan and _weatherService and _weatherService.ForceCondition then
				-- BATTLEFIELD WEATHER (2026-10-26): set the global condition via the existing
				-- WeatherService. HONEST LIMIT: ForceCondition has no duration, so the authored
				-- "for N CT" auto-revert is not enforced -- the condition holds until the next
				-- per-round weather re-roll. Disclosed, not faked.
				local ok = _weatherService.ForceCondition(_weatherPlan.conditionId, state)
				effectResult = {
					effectType = ok and "Weather" or "Unimplemented",
					amount = 0,
					description = ok and (consumableDef.name .. " set weather -> " .. _weatherPlan.conditionId) or nil,
				}
				print(string.format("[CommandService] ITEM WEATHER [%s] | %s -> %s%s",
					consumableDef.name, actor.name, _weatherPlan.conditionId,
					_weatherPlan.durationCt and (" (authored " .. _weatherPlan.durationCt .. " CT, not duration-enforced)") or ""))
			elseif _tilePlan and _tileAimOk and type(target) == "table" and target.tileX and _tileEffectService then
				-- TILE EFFECT (2026-10-26): place an existing ground effect (Steam / Oily) or hit
				-- the tiles with an element through the normal reaction engine (Water). An Aura N
				-- emitter is centred on the PLACED tile (Circle N); Line/Cone aim from the user
				-- toward the target tile; other patterns centre on the target tile.
				local pat = _tilePat
				local auraR = pat:match("^Aura(%d+)$")
				if auraR then pat = "Circle" .. auraR end
				local tiles = TargetingService.GetAOETargetTiles(pat, actor, target.tileX, target.tileY, _mapWidth, _mapHeight)
				if not tiles or #tiles == 0 then tiles = { { tileX = target.tileX, tileY = target.tileY } } end
				local n = 0
				for _, t in ipairs(tiles) do
					if _tilePlan.element and _tileEffectService.ResolveElementOnTile then
						_tileEffectService.ResolveElementOnTile(t.tileX, t.tileY, _tilePlan.element, actor.id, state.units)
						n += 1
					elseif _tilePlan.effect and _tileEffectService.ApplyTileEffect then
						_tileEffectService.ApplyTileEffect(t.tileX, t.tileY, _tilePlan.effect, actor.id, state.units, nil, _tilePlan.ct)
						n += 1
					end
				end
				effectResult = { effectType = "TileEffect", amount = n,
					description = string.format("%s affected %d tile(s)", consumableDef.name, n) }
				print(string.format("[CommandService] ITEM TILE-EFFECT [%s] | %s | %s | %d tile(s)",
					consumableDef.name, actor.name, tostring(_tilePlan.effect or _tilePlan.element), n))
			elseif _isWard and selection.choice and type(target) == "table" and target.isAlive then
				-- ELEMENTAL WARD (SUP-016): apply the ward, store the picked element on the instance.
				StatusService.ApplyStatus(target, "Elemental Ward", actor.id)
				local inst = StatusService.HasStatus(target, "Elemental Ward")
				if type(inst) == "table" then inst.wardElement = selection.choice end
				if BattleVisualBroadcaster.UnitStateChanged then BattleVisualBroadcaster.UnitStateChanged(target) end
				effectResult = { effectType = "StatusApply", amount = 1, statusId = "Elemental Ward",
					description = string.format("%s: %s warded against %s", consumableDef.name, target.name or "target", selection.choice) }
				print(string.format("[CommandService] ITEM WARD [%s] | %s -> %s | %s",
					consumableDef.name, actor.name, target.name or "?", selection.choice))
			elseif _isCleanse and selection.choice and type(target) == "table" and target.tileX then
				-- PURIFICATION (REC-016): remove the picked debuff from every ally in the area.
				local pat = _tilePat
				local tiles = TargetingService.GetAOETargetTiles(pat, actor, target.tileX, target.tileY, _mapWidth, _mapHeight)
				if not tiles or #tiles == 0 then tiles = { { tileX = target.tileX, tileY = target.tileY } } end
				local key = {}
				for _, t in ipairs(tiles) do key[t.tileX .. "," .. t.tileY] = true end
				local cleansed = 0
				for _, u in ipairs(state.units) do
					if u.isAlive and u.side == actor.side and u.tileX and key[u.tileX .. "," .. u.tileY]
						and StatusService.HasStatus(u, selection.choice) then
						-- W2 fix: only count and broadcast removals that succeed (a weather
						-- hard-locked status, e.g. Snow Storm Frozen, refuses removal).
						if StatusService.RemoveStatus(u, selection.choice) then
							if BattleVisualBroadcaster.StatusExpired then BattleVisualBroadcaster.StatusExpired(u, selection.choice) end
							cleansed += 1
						end
					end
				end
				effectResult = { effectType = "StatusCure", amount = cleansed, statusId = selection.choice,
					description = string.format("%s removed %s from %d ally(ies)", consumableDef.name, selection.choice, cleansed) }
				print(string.format("[CommandService] ITEM CLEANSE [%s] | %s | %s x%d",
					consumableDef.name, actor.name, selection.choice, cleansed))
			elseif _isExtend and selection.choice and type(target) == "table" and target.isAlive then
				-- BLESSING PROJECTOR (SUP-018): extend the picked buff once (+500 CT, or +1 turn
				-- for a turn-based buff). Validated earlier (dispellable buff, not yet extended).
				local inst = StatusService.HasStatus(target, selection.choice)
				local ok = false
				if type(inst) == "table" and not inst.blessExtended then
					if inst.remainingCt then
						inst.remainingCt += 500
					elseif inst.remainingTurns then
						inst.remainingTurns += 1
					end
					inst.blessExtended = true
					ok = true
					if BattleVisualBroadcaster.UnitStateChanged then BattleVisualBroadcaster.UnitStateChanged(target) end
				end
				effectResult = { effectType = ok and "StatusExtend" or "Unimplemented", amount = ok and 1 or 0,
					statusId = selection.choice,
					description = string.format("%s extended %s on %s", consumableDef.name, selection.choice, target.name or "target") }
				print(string.format("[CommandService] ITEM EXTEND [%s] | %s -> %s | %s | %s",
					consumableDef.name, actor.name, target.name or "?", selection.choice, ok and "OK" or "FAILED"))
			elseif _galePlan and type(target) == "table" and target.tileX and _tileAimOk then
				-- GALE ENGINE (ENV-009, user ruling 2026-10-26): blow away airborne zones in the cone,
				-- then push EVERY unit in it (both sides, not the user) away from the user with the
				-- authored Force, farthest first so near units are not blocked by far ones.
				local tiles = TargetingService.GetAOETargetTiles(_tilePat, actor, target.tileX, target.tileY,
					_mapWidth, _mapHeight) or {}
				local onCone = {}
				local cleared = 0
				for _, t in ipairs(tiles) do
					onCone[t.tileX .. "," .. t.tileY] = true
					if _tileEffectService then
						local eff = _tileEffectService.GetTileEffect(t.tileX, t.tileY)
						local edef = eff and GameConstants.TILE_EFFECTS[eff.id]
						local airborne = false
						for _, tg in ipairs((edef and edef.tags) or {}) do
							if tg == "Airborne" then airborne = true break end
						end
						if airborne then
							_tileEffectService.RemoveTileEffect(t.tileX, t.tileY)
							cleared += 1
						end
					end
				end
				local victims = {}
				for _, u in ipairs(state.units) do
					if u.isAlive and u ~= actor and u.tileX and onCone[u.tileX .. "," .. u.tileY] then
						table.insert(victims, u)
					end
				end
				local function _d(u: any): number
					return math.max(math.abs(u.tileX - actor.tileX), math.abs(u.tileY - actor.tileY))
				end
				table.sort(victims, function(a: any, b: any): boolean
					if _d(a) ~= _d(b) then return _d(a) > _d(b) end
					return tostring(a.id) < tostring(b.id)
				end)
				local moved = 0
				for _, u in ipairs(victims) do
					if u.isAlive then
						local r = applyKnockback(state, actor, u, _galePlan.force, consumableDef.name, nil, nil)
						if r and r.pushed then moved += 1 end
					end
				end
				effectResult = { effectType = "Push", amount = moved,
					description = string.format("%s pushed %d unit(s), cleared %d zone(s)", consumableDef.name, moved, cleared) }
				print(string.format("[CommandService] ITEM GALE [%s] | %d in cone, %d pushed, %d airborne zones cleared",
					consumableDef.name, #victims, moved, cleared))
			elseif _roadPlan and type(target) == "table" and target.tileX and _tileEffectService and _tileAimOk then
				-- ROAD FABRICATOR (ENV-019): every tile on the line gets a temporary road.
				local tiles = TargetingService.GetAOETargetTiles(_tilePat, actor, target.tileX, target.tileY,
					_mapWidth, _mapHeight) or {}
				for _, t in ipairs(tiles) do
					_tileEffectService.SetRoad(t.tileX, t.tileY, _roadPlan.durationCt, _roadPlan.cut)
				end
				effectResult = { effectType = "Road", amount = #tiles,
					description = string.format("%s laid road on %d tile(s) for %d CT", consumableDef.name, #tiles, _roadPlan.durationCt) }
				print(string.format("[CommandService] ITEM ROAD [%s] | %d tiles, -%d move cost, %d CT",
					consumableDef.name, #tiles, _roadPlan.cut, _roadPlan.durationCt))
			elseif _digPlan and type(target) == "table" and target.tileX then
				-- EXCAVATION DRILL (ENV-012): lower each legal tile of the pattern (Impact 1 =
				-- the tile plus its 4 neighbours). Units standing there ride down with it.
				local tiles = TargetingService.GetAOETargetTiles(_tilePat, actor, target.tileX, target.tileY,
					_mapWidth, _mapHeight)
				if not tiles or #tiles == 0 then tiles = { { tileX = target.tileX, tileY = target.tileY } } end
				local deploySet = {}
				for _, list in ipairs({ state.playerDeployTiles or {}, state.enemyDeployTiles or {} }) do
					for _, d in ipairs(list) do deploySet[d.x .. "," .. d.y] = true end
				end
				local lowered = 0
				for _, t in ipairs(tiles) do
					local tx, ty = t.tileX, t.tileY
					local tid = GameConstants.GetTerrainId(tx, ty)
					local tdef = tid and GameConstants.TERRAIN_TYPES[tid]
					local wet = false
					for _, tg in ipairs((tdef and tdef.tags) or {}) do
						-- (Portal / Hazard added 2026-10-26: Monolith portals and Quicksand are not dug.)
						if tg == "Liquid" or tg == "Deep" or tg == "Molten" or tg == "Water"
							or tg == "Portal" or tg == "Hazard" then wet = true break end
					end
					local legal = not wet and not deploySet[tx .. "," .. ty]
						and not GameConstants.IsBlocked(tx, ty)
						and not (GameConstants.IsChasmFloor and GameConstants.IsChasmFloor(tx, ty))
					if legal and GameConstants.LowerElevation(tx, ty, _digPlan.amount) > 0 then
						lowered += 1
						-- D1 fix: redraw with the voxel column dropped too, and tell clients the
						-- new height BEFORE the UnitMoved below (token heights read it).
						local newElev = GameConstants.GetElevation(tx, ty)
						ObjectEffectService.LowerTileVisual(tx, ty, tid, newElev)
						BattleVisualBroadcaster.TerrainChanged(tx, ty, tid, newElev)
						for _, u in ipairs(state.units) do
							if u.isAlive and u.tileX == tx and u.tileY == ty then BattleVisualBroadcaster.UnitMoved(u) end
						end
					end
				end
				effectResult = { effectType = "Excavate", amount = lowered,
					description = string.format("%s lowered %d tile(s)", consumableDef.name, lowered) }
				print(string.format("[CommandService] ITEM EXCAVATE [%s] | %d of %d tiles lowered by %d",
					consumableDef.name, lowered, #tiles, _digPlan.amount))
			elseif _isRepair and type(target) == "table" and target.tileX then
				-- MAINTENANCE TOOL (UTI-008, user ruling 2026-10-26): full restore of the device /
				-- gadget on the tile (checked before cost). Shares the Repair skill's helper.
				local what = repairAtTile(state, target.tileX, target.tileY, true)
				effectResult = { effectType = what and "Repair" or "RepairFailed", amount = what and 1 or 0,
					description = what and (consumableDef.name .. " restored " .. tostring(what))
						or (consumableDef.name .. ": nothing to repair") }
			elseif _snarePlan and type(target) == "table" and target.isAlive and not target.isGroundTarget then
				-- MAGNETIC SNARE (CON-016): pull the Mechanical target toward the user, force =
				-- distance, its Stability counted 2 lower. Normal push rules apply (collision,
				-- falls, traps crossed, entry effects) through the shared applyKnockback.
				local away = DisplacementService.GetPushDirection(actor, target)
				local res = applyKnockback(state, actor, target, _snarePlan.distance, consumableDef.name,
					{ dx = -away.dx, dy = -away.dy }, _snarePlan.distance, _snarePlan.stabilityIgnore)
				local moved = (res and res.tilesDisplaced) or 0
				effectResult = { effectType = "Pull", amount = moved,
					description = string.format("%s pulled %s %d tile(s)", consumableDef.name, target.name or "target", moved) }
				print(string.format("[CommandService] ITEM SNARE [%s] | %s -> %s | moved=%d", consumableDef.name,
					actor.name, target.name or "?", moved))
			elseif _winchPlan and type(target) == "table" and target.isAlive and not target.isGroundTarget then
				-- RECOVERY WINCH (UTI-012): one legal tile toward the user, no collision or fall
				-- damage. Tries the straight step first, then the two single-axis steps; the step
				-- must bring the target closer and never onto the user. No legal step = no move
				-- (charge spent, like a failed teleport).
				local tx, ty = target.tileX, target.tileY
				local sx = (actor.tileX > tx) and 1 or ((actor.tileX < tx) and -1 or 0)
				local sy = (actor.tileY > ty) and 1 or ((actor.tileY < ty) and -1 or 0)
				local d0 = math.max(math.abs(actor.tileX - tx), math.abs(actor.tileY - ty))
				local moved = false
				for _, st in ipairs({ { sx, sy }, { sx, 0 }, { 0, sy } }) do
					if not moved and (st[1] ~= 0 or st[2] ~= 0) then
						local nx, ny = tx + st[1], ty + st[2]
						local nd = math.max(math.abs(actor.tileX - nx), math.abs(actor.tileY - ny))
						if nd < d0 and nd >= 1 and _freeTile(nx, ny) then
							target.tileX, target.tileY = nx, ny
							moved = true
						end
					end
				end
				if moved then _landOn(target) end
				effectResult = { effectType = moved and "Pull" or "PullFailed", amount = moved and 1 or 0,
					description = moved and (consumableDef.name .. " pulled " .. (target.name or "target"))
						or (consumableDef.name .. " found no legal tile") }
				print(string.format("[CommandService] ITEM WINCH [%s] | %s -> %s | %s",
					consumableDef.name, actor.name, target.name or "?", moved and "MOVED" or "NO LEGAL TILE"))
			elseif _climbPlan and type(target) == "table" and target.isAlive and not target.isGroundTarget then
				-- CLIMBING LINE (UTI-013): move the target to the NEAREST free legal tile that is
				-- 1..maxGain elevation higher than its own. Ties: nearer, then the bigger climb,
				-- then lower y, then lower x. No such tile = no move (charge spent).
				local tx, ty = target.tileX, target.tileY
				local e0 = GameConstants.GetElevation(tx, ty)
				local best, bd, bg = nil, math.huge, -1
				for y = 1, _mapHeight do
					for x = 1, _mapWidth do
						local gain = GameConstants.GetElevation(x, y) - e0
						local d = math.max(math.abs(x - tx), math.abs(y - ty))
						-- User ruling 2026-10-26: only tiles within the authored radius (3).
						local inReach = (_climbPlan.radius == nil) or d <= _climbPlan.radius
						if inReach and gain >= 1 and gain <= _climbPlan.maxGain and _freeTile(x, y) then
							if d < bd or (d == bd and gain > bg) then
								best, bd, bg = { x = x, y = y }, d, gain
							end
						end
					end
				end
				if best then
					target.tileX, target.tileY = best.x, best.y
					_landOn(target)
				end
				effectResult = { effectType = best and "Relocate" or "RelocateFailed", amount = best and 1 or 0,
					description = best and string.format("%s lifted %s to (%d,%d)", consumableDef.name,
						target.name or "target", best.x, best.y) or (consumableDef.name .. " found no higher tile") }
				print(string.format("[CommandService] ITEM CLIMB [%s] | %s | %s", consumableDef.name,
					target.name or "?", best and string.format("-> (%d,%d) +%d elev", best.x, best.y, bg) or "NO TILE"))
			elseif _isRecall and type(target) == "table" and target.tileX and type(selection.choice) == "string" then
				-- OBJECT RECALL (UTI-018): move the picked device to the tapped free tile. Its
				-- lifespan and remaining pulses are unchanged (pulses follow the device).
				local dev = ItemEffectService.FindOwnedDevice(actor, state.units, selection.choice)
				local ok = dev ~= nil and _freeTile(target.tileX, target.tileY)
				if ok and dev then
					dev.tileX, dev.tileY = target.tileX, target.tileY
					_landOn(dev)
				end
				effectResult = { effectType = ok and "Relocate" or "RelocateFailed", amount = ok and 1 or 0,
					description = ok and string.format("%s moved %s to (%d,%d)", consumableDef.name,
						selection.choice, target.tileX, target.tileY) or (consumableDef.name .. ": tile not legal") }
				print(string.format("[CommandService] ITEM RECALL [%s] | %s -> (%d,%d) | %s", consumableDef.name,
					selection.choice, target.tileX, target.tileY, ok and "OK" or "ILLEGAL"))
			elseif _firebreakPlan and type(target) == "table" and target.tileX and _tileEffectService and _tileAimOk then
				-- FIREBREAK (ENV-015): along the line, put out Burning (early extinguish spares
				-- the terrain) and guard each tile against new Burning for the authored CT.
				local tiles = TargetingService.GetAOETargetTiles(
					(tostring(consumableDef.pattern or "Single"):gsub("%s+", "")),
					actor, target.tileX, target.tileY, _mapWidth, _mapHeight)
				if not tiles or #tiles == 0 then
					tiles = { { tileX = target.tileX, tileY = target.tileY } }
				end
				local out = 0
				for _, t in ipairs(tiles) do
					local eff = _tileEffectService.GetTileEffect(t.tileX, t.tileY)
					-- DB ENV-015 Terrain_Side_Effect: "Removes tile effects Burning/Oily" (D-1 fix).
					if eff and (eff.id == "Burning" or eff.id == "Oily") then
						_tileEffectService.RemoveTileEffect(t.tileX, t.tileY)
						out += 1
					end
					_tileEffectService.SetFirebreak(t.tileX, t.tileY, _firebreakPlan.durationCt)
				end
				effectResult = { effectType = "Firebreak", amount = #tiles,
					description = string.format("%s guarded %d tile(s), cleared %d fire/oil tile(s)", consumableDef.name, #tiles, out) }
				print(string.format("[CommandService] ITEM FIREBREAK [%s] | %d tiles guarded %d CT | %d extinguished",
					consumableDef.name, #tiles, _firebreakPlan.durationCt, out))
			elseif _isRelay and type(target) == "table" and target.isAlive and type(selection.choice) == "string" then
				-- CHARGE RELAY (UTI-009): move 1 charge of the picked item from the user to the
				-- target's same item. Legality was checked by ValidateItemChoice before any cost.
				local from, to = ItemEffectService.FindRelaySlots(consumableDef, actor, target, selection.choice)
				if from and to then
					from.currentCharges -= 1
					to.currentCharges += 1
					BattleVisualBroadcaster.UnitStateChanged(actor)
					BattleVisualBroadcaster.UnitStateChanged(target)
				end
				effectResult = { effectType = (from and to) and "ChargeTransfer" or "ChargeTransferFailed",
					amount = (from and to) and 1 or 0,
					description = string.format("%s gave 1 %s charge to %s", actor.name, selection.choice, target.name or "target") }
				print(string.format("[CommandService] ITEM RELAY [%s] | %s -> %s | %s | %s", consumableDef.name,
					actor.name, target.name or "?", selection.choice, (from and to) and "OK" or "FAILED"))
			elseif _teleportPlan and type(target) == "table" and target.tileX then
				-- TELEPORT (2026-10-26, UTI-004 Phase Translocator): move the user to the picked
				-- tile if it is in bounds, passable, unblocked and not occupied by a living unit.
				-- Landing triggers the tile's trap / entry effects, same as the swap ruling.
				local tx, ty = target.tileX, target.tileY
				local legal = tx >= 1 and ty >= 1 and tx <= _mapWidth and ty <= _mapHeight
					and not GameConstants.IsImpassableTerrain(tx, ty) and not GameConstants.IsBlocked(tx, ty)
					and not StatusService.IsTeleportLocked(actor)  -- Gravity Pylon aura
				if legal then
					for _, u in ipairs(state.units) do
						if u.isAlive and u.tileX == tx and u.tileY == ty then legal = false break end
					end
				end
				if legal then
					actor.tileX, actor.tileY = tx, ty
					BattleVisualBroadcaster.UnitMoved(actor)
					if ObjectEffectService and ObjectEffectService.GetTriggeredTrapAt then
						local trap = ObjectEffectService.GetTriggeredTrapAt(state, tx, ty)
						if trap then ObjectEffectService.TriggerTrap(actor, trap, state, state.units) end
					end
					if actor.isAlive then applyForcedEntryEffects(actor, { pushed = true }) end
				end
				effectResult = { effectType = legal and "Teleport" or "TeleportFailed", amount = legal and 1 or 0,
					description = legal and string.format("%s teleported to (%d,%d)", consumableDef.name, tx, ty)
						or (consumableDef.name .. " failed (tile not legal)") }
				print(string.format("[CommandService] ITEM TELEPORT [%s] | %s -> (%d,%d) | %s",
					consumableDef.name, actor.name, tx, ty, legal and "OK" or "ILLEGAL"))
			elseif _swapPlan and type(target) == "table" and target.isAlive and target.id ~= actor.id then
				-- SWAP (2026-10-26, UTI-005 Exchange Device, user ruling): an ENEMY resists when it is
				-- Guarding or Pinned; a failed swap still spends the charge. On success BOTH units
				-- trigger the tile they land on (trap + terrain entry), same as a push.
				local resisted = target.side ~= actor.side
					and (StatusService.HasStatus(target, "Guard") or StatusService.HasStatus(target, "Pinned"))
				local ok = (not resisted) and applySwap(actor, target)
				if ok then
					for _, u in ipairs({ actor, target }) do
						if u.isAlive and ObjectEffectService and ObjectEffectService.GetTriggeredTrapAt then
							local trap = ObjectEffectService.GetTriggeredTrapAt(state, u.tileX, u.tileY)
							if trap then ObjectEffectService.TriggerTrap(u, trap, state, state.units) end
						end
						if u.isAlive then applyForcedEntryEffects(u, { pushed = true }) end
					end
				end
				effectResult = { effectType = ok and "Swap" or "SwapFailed", amount = ok and 1 or 0,
					description = ok and (consumableDef.name .. " swapped with " .. (target.name or "target"))
						or (consumableDef.name .. (resisted and " resisted" or " failed")) }
				print(string.format("[CommandService] ITEM SWAP [%s] | %s <-> %s | %s",
					consumableDef.name, actor.name, target.name or "?", ok and "OK" or (resisted and "RESISTED" or "FAILED")))
			elseif _revealPlan and type(target) == "table" and target.tileX then
				-- REVEAL (2026-10-26, user ruling 5): remove Hide from ALL units (both sides) in the
				-- area and reveal hidden objects there (traps now; hidden treasure / Mimic later).
				local pat = _tilePat
				local tiles = TargetingService.GetAOETargetTiles(pat, actor, target.tileX, target.tileY, _mapWidth, _mapHeight)
				if not tiles or #tiles == 0 then tiles = { { tileX = target.tileX, tileY = target.tileY } } end
				local key = {}
				for _, t in ipairs(tiles) do key[t.tileX .. "," .. t.tileY] = true end
				local unitsRevealed = 0
				for _, u in ipairs(state.units) do
					if u.isAlive and u.tileX and key[u.tileX .. "," .. u.tileY] and StatusService.HasStatus(u, "Hide") then
						StatusService.RemoveStatus(u, "Hide")
						if BattleVisualBroadcaster.StatusExpired then BattleVisualBroadcaster.StatusExpired(u, "Hide") end
						unitsRevealed += 1
					end
				end
				local objsRevealed = (ObjectEffectService.RevealHiddenInArea and ObjectEffectService.RevealHiddenInArea(state, key)) or 0
				effectResult = { effectType = "Reveal", amount = unitsRevealed + objsRevealed,
					description = string.format("%s revealed %d unit(s), %d object(s)", consumableDef.name, unitsRevealed, objsRevealed) }
				print(string.format("[CommandService] ITEM REVEAL [%s] | %s | units=%d objects=%d",
					consumableDef.name, actor.name, unitsRevealed, objsRevealed))
			elseif _pushPlan and not _pushPlan.area and type(target) == "table" and target.isAlive
				and not target.isGroundTarget then
				-- SINGLE-TARGET PUSH / PULL (2026-10-26): reuse the shared applyKnockback helper
				-- (handles distance = force - stability, wall/fall collision, trap triggering,
				-- landing-tile effects and the UnitPushed broadcast). Push = default away-from-user
				-- direction (dirOverride nil); Pull = toward the user (negate the away direction).
				-- This is the SINGLE-TARGET branch. Area push (Repulsion) is handled in the elseif
				-- below. Kinetic Ram's collision x1.25 bonus is still NOT applied (ram collision
				-- plumbing) -> disclosed partial, the push itself works.
				local dirOverride = nil
				if _pushPlan.mode == "pull" then
					local away = DisplacementService.GetPushDirection(actor, target)
					dirOverride = { dx = -away.dx, dy = -away.dy }
				end
				-- Kinetic Ram "collision multiplier x1.25" (2026-10-26): stamped on the pusher for
				-- this one push only; DisplacementService scales the collision damage by it.
				actor._itemCollisionMult = _pushPlan.collisionMult
				local pushRes = applyKnockback(state, actor, target, _pushPlan.force,
					consumableDef.name, dirOverride, nil)
				actor._itemCollisionMult = nil
				effectResult = {
					effectType = (_pushPlan.mode == "pull") and "Pull" or "Push",
					amount = (pushRes and pushRes.tilesDisplaced) or 0,
					description = string.format("%s %s %s %d tile(s)", consumableDef.name,
						(_pushPlan.mode == "pull") and "pulled" or "pushed",
						target.name or "target", (pushRes and pushRes.tilesDisplaced) or 0),
				}
				print(string.format("[CommandService] ITEM %s [%s] | %s -> %s | force=%d | moved=%d",
					(_pushPlan.mode == "pull") and "PULL" or "PUSH", consumableDef.name, actor.name,
					target.name or "?", _pushPlan.force, (pushRes and pushRes.tilesDisplaced) or 0))
			elseif _pushPlan and _pushPlan.area and type(target) == "table" and target.tileX and TargetingService then
				-- AREA PUSH (2026-10-26): Repulsion Device "Push from center". For each ENEMY on the
				-- AOE tiles, push it AWAY from the center tile via the shared applyKnockback (so each
				-- unit still gets real collision / fall / trap handling). Direction is per-unit:
				-- sign(unit - center), computed by GetPushDirection from a pseudo-pusher sitting on
				-- the center tile (handles the on-center unit via its dx=1 default). Enemies only
				-- (Control-category convention; the formula says "from center" without naming a side,
				-- so this is the conservative read). Deterministic order (distance, then id).
				local cx, cy = target.tileX, target.tileY
				local tiles = TargetingService.GetAOETargetTiles(
					(tostring(consumableDef.pattern or "Single"):gsub("%s+", "")),
					actor, cx, cy, _mapWidth, _mapHeight)
				if not tiles or #tiles == 0 then tiles = { { tileX = cx, tileY = cy } } end
				local key = {}
				for _, t in ipairs(tiles) do key[t.tileX .. "," .. t.tileY] = true end
				local victims = {}
				for _, u in ipairs(state.units) do
					if u.isAlive and u.side ~= actor.side and u.tileX and key[u.tileX .. "," .. u.tileY] then
						table.insert(victims, u)
					end
				end
				table.sort(victims, function(a, b)
					local da = math.max(math.abs(a.tileX - cx), math.abs(a.tileY - cy))
					local db = math.max(math.abs(b.tileX - cx), math.abs(b.tileY - cy))
					if da ~= db then return da > db end  -- farthest first, so inner units don't collide into movers
					return tostring(a.id) < tostring(b.id)
				end)
				local pseudoCenter = { tileX = cx, tileY = cy }
				local moved = 0
				for _, u in ipairs(victims) do
					local dir = DisplacementService.GetPushDirection(pseudoCenter, u)
					local r = applyKnockback(state, actor, u, _pushPlan.force, consumableDef.name, dir, nil)
					if r and (r.tilesDisplaced or 0) > 0 then moved += 1 end
				end
				effectResult = { effectType = "Push", amount = moved,
					description = string.format("%s repulsed %d enemy(ies) from center", consumableDef.name, moved) }
				print(string.format("[CommandService] ITEM AREA-PUSH [%s] | %s | center (%d,%d) | force=%d | %d moved",
					consumableDef.name, actor.name, cx, cy, _pushPlan.force, moved))
			else
				-- Non-deploy / non-push (or deferred area push) -> normal item effect resolution.
				effectResult = resolveItemEffect(actor, target, consumableDef, state.units, state)
			end
		end
		-- NOT-BUILT REFUND (2026-10-26): the menu now offers every item that has a legal
		-- target, including ones whose effect is not built yet. Such an item resolves to
		-- "Unimplemented"; give back the charge, AP and RT so using it costs nothing and the
		-- turn stays open. Remove this once every consumable is built.
		if not effectResult or effectResult.effectType == "Unimplemented" then
			if _consCfg and _consCfg.noChargeConsume then
				actor._armorConservationUsed = nil
			else
				slot.currentCharges = slot.currentCharges + 1
				ObjectiveService.RecordEvent(state, "chargesUsed", -1)
			end
			actor._armorManualItemCount = math.max(0, (actor._armorManualItemCount or 1) - 1)
			actor.currentAp = actor.currentAp + apCost
			BattleCoordinator.RefundRt(state, rtCost)
			state.turnActionTaken = _itemPreActionTaken
			print(string.format("[CommandService] ITEM [%s] not built yet -> charge, AP and RT refunded", consumableDef.name))
			-- D-2 fix (UAT 2026-10-26): report the use as REJECTED, not as a success, so the
			-- AI turn loop cannot re-pick the same item until its action cap. The AI also
			-- remembers the item for this battle and stops scoring it (AIService.scoreItem),
			-- and _unbuiltItemRetry lets its loop choose a different action this AP.
			actor._unbuiltItems = actor._unbuiltItems or {}
			actor._unbuiltItems[consumableDef.name] = true
			actor._unbuiltItemRetry = true
			return false, "This item is not built yet (nothing was spent)."
		end
		-- Area items report the units they changed; refresh those bars on the client.
		if effectResult and effectResult.affectedUnits and BattleVisualBroadcaster.UnitStateChanged then
			for _, au in ipairs(effectResult.affectedUnits) do
				BattleVisualBroadcaster.UnitStateChanged(au)
			end
		end

		-- AC-016 Mirror Charm: an ALLY-targeted Item effect ALSO applies to the user. Re-resolve the
		-- same consumable on the actor when the chosen target was a DIFFERENT friendly unit (not self,
		-- not an enemy). No extra charge/AP; the x1.50 RT cost is already folded above. nil-safe.
		if target and target ~= actor and target.side == actor.side
			and ArmorPassiveService.GetItemSelfApplyConfig(actor) then
			resolveItemEffect(actor, actor, consumableDef, state.units)
			print(string.format("[CommandService] Mirror Charm: %s also receives %s effect", actor.name, consumableDef.name))
		end

		-- Optional objective "Torture": count a revive consumable used on a KO'd
		-- ENEMY (returns on the enemy side). Ally revives do not count. Gated on the
		-- resolver actually performing a Revive this use.
		if effectResult and effectResult.effectType == "Revive"
			and target and target.side ~= actor.side then
			ObjectiveService.RecordEvent(state, "enemiesRevived", 1)
		end

		-- Broadcast via dedicated ItemUsed event (client renders item feedback)
		if BattleVisualBroadcaster.ItemUsed then
			BattleVisualBroadcaster.ItemUsed(actor, target, consumableDef.name, effectResult)
		end
		-- A revive item can weaken Venom (user ruling 2026-10-26); refresh the revived unit's
		-- HP + status icons the same way Divine Intervention does after its revive.
		if effectResult and effectResult.effectType == "Revive" and target and BattleVisualBroadcaster.UnitStateChanged then
			BattleVisualBroadcaster.UnitStateChanged(target)
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

	-- PHASE 2 — resolve the Electric Shock reaction (Step-5 secondary) once, after
	-- the whole action's damage is done. No-op unless an Electric hit was buffered
	-- this action. Must run before EndTurn so KO/HP changes are in state when the
	-- turn hands off. (CombatResolver buffers each Electric hit in ApplyOutcome.)
	if CombatResolver.FlushElectricShock then
		CombatResolver.FlushElectricShock(state.units)
	end
	-- Ally-KO reactions (Perks & Flaws 2026-10-23): Hemophage / Sluggish Finisher. Drains
	-- units that were KO'd by this action's combat damage (buffered in CombatResolver) and
	-- applies the reaction to nearby same-side allies. Runs after the electric flush, before
	-- EndTurn, so HP/AP changes are in state at handoff. Combat deaths only (DoT / CT-tick /
	-- collision / fall deaths are not yet buffered -- deferred).
	if CombatResolver.FlushAllyKoReactions then
		CombatResolver.FlushAllyKoReactions(state.units)
	end

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

--------------------------------------------------
-- UNDO LAST ACTION (2026-10-17)
--
-- Reverses the most recent reversible action (Move or Guard) for the active
-- unit, newest first and repeatable, as long as that action triggered no
-- environmental reaction. Operates only within the current open turn, before
-- EndTurn, so RT is still in state.turnRtAccrued and reversal is a clean
-- subtraction. Server-authoritative (SEC-001/SEC-002): the client only asks;
-- every eligibility rule is re-checked here.
--
-- Returns (ok: boolean, reason: string?). ok=false reasons are the same strings
-- the client uses for the grayed-button tooltip.
--------------------------------------------------
function CommandService.UndoLastAction(state: any, actorId: any): (boolean, any)
	-- Turn gate (mirror ValidateAndCommit steps 1-2)
	local actor = nil
	for _, unit in ipairs(state.units) do
		if unit.id == actorId then actor = unit; break end
	end
	if not actor then return false, "Actor not found." end
	if state.phase ~= "TurnOpen" then return false, "No turn is open." end
	if state.activeUnit ~= actor then return false, actor.name .. " is not the active unit." end

	local entry = BattleCoordinator.PeekUndo(state)
	if not entry then
		return false, "Nothing to undo."
	end
	if entry.actorId ~= actor.id then
		-- Stack belongs to a different unit's turn (should not happen — reset at
		-- turn open — but never undo across units).
		return false, "Nothing to undo."
	end
	if entry.reaction then
		return false, "Can't undo — that move caused a reaction."
	end

	-- Commit the pop now that eligibility passed.
	BattleCoordinator.PopUndo(state)

	-- Refund resources common to both kinds.
	actor.currentAp = actor.currentAp + (entry.apCost or 0)
	BattleCoordinator.RefundRt(state, entry.rt or 0)

	if entry.kind == "Move" then
		actor.tileX = entry.prevTileX
		actor.tileY = entry.prevTileY
		actor.facing = entry.prevFacing
		-- Auras depend on position: reconcile again now that the unit is back.
		ObjectEffectService.ReconcileAuras(state.units, state)
		BattleVisualBroadcaster.UnitMoved(actor)
		BattleVisualBroadcaster.FacingChanged(actor)
		print(string.format(
			"[CommandService] UNDO Move | %s -> (%d,%d) | +AP:%d | -RT:%d | AP now:%d",
			actor.name, actor.tileX, actor.tileY, entry.apCost or 0, entry.rt or 0, actor.currentAp
		))
	elseif entry.kind == "Guard" then
		StatusService.RemoveStatus(actor, "Guard")
		actor.guardBonus = nil
		actor.guardUsedThisTurn = false
		BattleVisualBroadcaster.StatusExpired(actor, "Guard")
		print(string.format(
			"[CommandService] UNDO Guard | %s | +AP:%d | -RT:%d | AP now:%d",
			actor.name, entry.apCost or 0, entry.rt or 0, actor.currentAp
		))
	else
		return false, "Nothing to undo."
	end

	BattleVisualBroadcaster.UnitStateChanged(actor)
	BattleVisualBroadcaster.Log("action", `{actor.name} undoes their {entry.kind}.`, actor.id)
	return true, nil
end

-- AC-015 Emergency Locket (out-of-turn auto-heal). Called by BattleCoordinator at the scheduler
-- boundary (no unit's turn open) for a wearer that dropped to <= its locket HP threshold while it
-- was NOT its own turn. Finds an equipped consumable tagged "Self Heal" (the runtime label for a
-- self-usable HP-restore item) with charges left, uses the one with the MOST charges on the wearer,
-- consumes 1 charge, adds DOUBLE the item's RT to the wearer's recovery (no AP), and marks the
-- once-per-turn flag. Returns true if it healed. Real-resolution path only (never AI preview).
function CommandService.TryAutoUseHeal(state, wearer)
	if not (wearer and wearer.isAlive and wearer.consumableSlots) then return false end
	local cfg = ArmorPassiveService.GetAutoHealConfig(wearer)
	if not cfg then return false end  -- no locket, or already auto-healed this turn

	-- Pick the Self Heal item with the most remaining charges (tie -> lowest slot index).
	local bestSlot, bestDef, bestCharges, bestIndex = nil, nil, -1, math.huge
	for idx, slot in pairs(wearer.consumableSlots) do
		if slot and slot.consumableId and (slot.currentCharges or 0) > 0 then
			local def = ConsumableData.Items[slot.consumableId]
			if def and def.tags then
				local isSelfHeal = false
				for _, t in ipairs(def.tags) do
					if t == "Self Heal" then isSelfHeal = true; break end
				end
				if isSelfHeal then
					local c = slot.currentCharges or 0
					local numIdx = tonumber(idx) or math.huge
					if c > bestCharges or (c == bestCharges and numIdx < bestIndex) then
						bestSlot, bestDef, bestCharges, bestIndex = slot, def, c, numIdx
					end
				end
			end
		end
	end
	if not bestSlot then return false end  -- nothing stocked; flag stays unset so a later charge can still fire

	-- Apply the heal on the wearer (self-target) and consume 1 charge.
	local effectResult = resolveItemEffect(wearer, wearer, bestDef, state.units)
	bestSlot.currentCharges = math.max(0, (bestSlot.currentCharges or 0) - 1)

	-- Double RT, added DIRECTLY to the wearer's recovery: we are OUTSIDE its turn, so AccrueRt's
	-- open-turn contract does not apply (same out-of-turn RT idiom as on-hit RT delays). No AP.
	local rtCost = (bestDef.rtCost or 80) * (cfg.rtMultiplier or 2.0)
	wearer.remainingRt = (wearer.remainingRt or 0) + math.round(rtCost)

	wearer._armorAutoHealUsed = true

	if BattleVisualBroadcaster.ItemUsed then
		BattleVisualBroadcaster.ItemUsed(wearer, wearer, bestDef.name, effectResult)
	end
	print(string.format("[CommandService] Emergency Locket: %s auto-uses %s (%d charge left), +%d RT",
		wearer.name, tostring(bestDef.name), bestSlot.currentCharges, math.round(rtCost)))
	return true
end

return CommandService
