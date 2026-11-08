--!strict
-- ObjectEffectService — resolves map-object Interact effects (Slice 5).
--
-- Fills the formerly-parked `mapObject` branch of CommandService's Interact
-- handler. Effects are keyed by object archetype id (ObjectData.Objects key),
-- mirroring how skills/augments resolve in code rather than from data —
-- ObjectData.lua stays prose (Designer-owned content; no effect schema there).
--
-- SERVER-ONLY (ServerScriptService). Server authority (ARC-001): every effect
-- mutates authoritative unit/battle state here; the client only renders via the
-- broadcaster. No per-frame work; no instances created (MEM/PRF clean).
--
-- Requires (LOAD-002): stable siblings in the same Game/ folder are required
-- directly. TileEffectService holds live map state and is injected at runtime
-- (SetTileEffectService), matching how CommandService/CombatResolver receive it.
-- All injected refs are nil-checked before use.
--
-- Usage tracking: map-object instances in state.objects are {id,type,x,y} with
-- NO usesLeft field. This module owns a per-battle consumed-set keyed by the
-- object instance id so "Once" / "Once per turn" / "Unlimited" are enforced
-- without touching ObjectData.
local ObjectEffectService = {}

-- Stable siblings (server-side, same Game/ folder): direct require (LOAD-002).
local StatusService           = require(script.Parent.StatusService)
local _BattleCoordinator       = require(script.Parent.BattleCoordinator)
local CombatResolver          = require(script.Parent.CombatResolver)
local BattleVisualBroadcaster = require(script.Parent.BattleVisualBroadcaster)
local RewardService           = require(script.Parent.RewardService)
local EquipmentService        = require(script.Parent.EquipmentService)
-- Mid-battle summons (Dragon Utopia / Mimic). One-way require:
-- BattleVisualBroadcaster/EnemyGenerator do NOT require ObjectEffectService, so
-- no cycle. EnemyGenerator builds + inserts the unit; we broadcast UnitSpawned.
local EnemyGenerator          = require(script.Parent.EnemyGenerator)
local InventoryService        = require(script.Parent.InventoryService)
local ItemGenerator           = require(script.Parent.ItemGenerator)
local ObjectiveService        = require(script.Parent.ObjectiveService)
local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

local ObjectData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("ObjectData")
)

-- Runtime-injected (holds live map state): nil-safe until wired.
local _tileEffectService = nil
-- Runtime-injected object renderer: fn(instance) -> renders into the live
-- mapFolder (which lives in Main's scope). Set by Main via SetObjectRenderer.
-- nil-safe: if unset, a spawned object is still logically live in state.objects,
-- but will not have a fresh visual until the next full map render.
local _objectRenderer = nil

-- Per-battle usage ledger. Keyed by object instance id ("obj_N").
--   _consumed[objId] = true        -> a "Once" object already used
--   _usedThisTurn[objId] = unitId  -> a "Once per turn" object, which unit/turn
local _consumed = {}
local _usedThisTurn = {}
-- Necro Tome Stand death-sweep snapshot (declared here so ResetBattle, defined
-- above the Necro section, binds the module local — not an accidental global).
local _aliveSnapshot: any = nil

function ObjectEffectService.SetTileEffectService(tes: any)
	_tileEffectService = tes
end

-- Inject the runtime object renderer (Main wires a closure over its mapFolder).
function ObjectEffectService.SetObjectRenderer(fn: any)
	_objectRenderer = fn
end

-- Runtime-injected object-visual remover: fn(instance) -> destroys the object's
-- model/cube in the live mapFolder and clears the tile's object attributes.
-- nil-safe: if unset, the object is still logically removed.
local _objectVisualRemover = nil
-- GOBLIN Cunning (user ruling 2026-10-27): +10% damage taken from traps and hazards (deferred
-- require: no load-time dependency).
local function hazardTakenMult(u: any): number
	local rps = (require :: any)(script.Parent.RacePassiveService)
	if rps and rps.GetHazardDamageTakenMultiplier then return rps.GetHazardDamageTakenMultiplier(u) end
	return 1
end

-- REVEAL ZONES (UTI-003 Scanner Lens, user ruling 2026-10-27): { tiles = {["x,y"]=true},
-- ct = remaining CT, side = owner side }. While a zone lasts, enemies of its owner inside it
-- lose Hide and cannot Hide again, and hidden traps there are shown. Reset per battle.
local _revealZones = {}
function ObjectEffectService.SetObjectVisualRemover(fn: any)
	_objectVisualRemover = fn
end

-- Remove a map-object instance from the live battle: state.objects entry, its
-- blocker entry (so the tile is walkable/free again), and its visual.
function ObjectEffectService.RemoveObjectInstance(state: any, inst: any)
	if not (state and state.objects and inst) then return false end
	local removed = false
	for idx, o in ipairs(state.objects) do
		if o == inst or (inst.id and o.id == inst.id) then
			table.remove(state.objects, idx)
			removed = true
			break
		end
	end
	if inst.x and inst.y and GameConstants.RemoveBlockerAt then
		GameConstants.RemoveBlockerAt(inst.x, inst.y)
	end
	-- OBS Phase 2c-E2: also clear OBJECT_MAP so GetObjectAt stops reporting a
	-- destroyed object (parity with PushObject's on-move OBJECT_MAP maintenance).
	if inst.x and inst.y and GameConstants.OBJECT_MAP and GameConstants.OBJECT_MAP[inst.y] then
		GameConstants.OBJECT_MAP[inst.y][inst.x] = nil
	end
	if _objectVisualRemover then
		_objectVisualRemover(inst)
	end
	-- 2026-10-30 (project_rules 241): a removed aura object (War Banner, Cursed Statue) stops
	-- its aura at once. Looked up on the module table: ClearAuraFrom is defined further down.
	if removed and (ObjectEffectService :: any).ClearAuraFrom then
		(ObjectEffectService :: any).ClearAuraFrom(state, inst)
	end
	print(string.format("[ObjectEffectService] RemoveObjectInstance | %s at (%s,%s) removed=%s",
		tostring(inst.type), tostring(inst.x), tostring(inst.y), tostring(removed)))
	return removed
end

-- OBS Phase 2a — object HP foundation (map_gen_rules rows 82/85, objects_encounters
-- rows 83/84). A breakable blocker-prop OBS object carries runtime hp = its
-- ObjectData hitsToDestroy (3). Billboards / unbreakable objects get NO hp and can
-- never be destroyed. Only objects that DECLARE a numeric hitsToDestroy qualify, so
-- tag-only "Breakable" props (Bomb Barrel, Stone Pillar) are unaffected.
local function isBreakableObject(def: any): boolean
	return def ~= nil
		and def.isUnbreakable ~= true
		and type(def.hitsToDestroy) == "number"
		and def.hitsToDestroy > 0
end

-- Does an ObjectData def carry a given tag? (nil-safe)
local function objHasTag(def: any, tag: any): boolean
	if not (def and def.tags) then return false end
	for _, t in ipairs(def.tags) do if t == tag then return true end end
	return false
end

-- Seed runtime hp on breakable OBS objects. Idempotent: safe to call at battle
-- start and on any mid-battle map refresh (each call resets to full, matching a
-- fresh/refreshed map). Billboards / unbreakable objects are explicitly set hp=nil.
function ObjectEffectService.InitObjectHp(state: any)
	if not (state and state.objects) then return end
	local n = 0
	for _, inst in ipairs(state.objects) do
		local def = inst and inst.type and ObjectData.Objects[inst.type]
		if isBreakableObject(def) then
			inst.hp = def.hitsToDestroy
			n += 1
		else
			inst.hp = nil
		end
	end
	print(string.format("[ObjectEffectService] InitObjectHp | %d breakable object(s) seeded with hp", n))
end

-- Repair (SKL-REPAIR, 2026-10-26): fully restore a breakable object's durability at (x,y) by
-- resetting inst.hp to its ObjectData hitsToDestroy, and tell clients. Returns the repaired object's
-- type, or nil if there is no breakable object on that tile. Mirrors InitObjectHp's hp model.
function ObjectEffectService.RepairObjectAt(state: any, x: any, y: any): any
	if not (state and state.objects and x and y) then return nil end
	for _, inst in ipairs(state.objects) do
		if inst.x == x and inst.y == y then
			local def = inst.type and ObjectData.Objects[inst.type]
			if isBreakableObject(def) then
				inst.hp = def.hitsToDestroy
				if BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectChanged then
					BattleVisualBroadcaster.ObjectChanged(x, y, { newHp = inst.hp })
				end
				print(string.format("[ObjectEffectService] RepairObjectAt | %s at (%d,%d) restored to %d hp",
					tostring(inst.type), x, y, inst.hp))
				return inst.type
			end
			return nil  -- object present but not breakable: nothing to repair
		end
	end
	return nil
end

-- OBS Phase 2a — DORMANT. Nothing calls this yet; Phase 2c wires attack / AOE /
-- elevation-reduction hits to it (map_gen_rules rows 82/84). Applies `n` hits
-- (default 1) to the breakable object at (x,y); on reaching 0 hp the object is
-- removed via the EXISTING RemoveObjectInstance (clears the blocker, reverts the
-- tile, removes the visual). Ad Billboard / unbreakable objects are a no-op.
-- Returns: "destroyed" | remaining hp (number) | "immune" | "not-found".
-- `attackElement` (optional): the element of the incoming hit (e.g. "Fire"). When the
-- object's ObjectData defines `instantKillTags` and the attack element matches one of
-- them, the object is destroyed in ONE hit regardless of remaining hp (e.g. Ice Spike
-- weak to Fire). This is the reusable per-object elemental-weakness hook: every future
-- skill-placed blocker just lists its killer element(s) in instantKillTags, no new code.
-- Omitting attackElement preserves the old behaviour exactly (back-compatible).
-- `fromExplosion` (optional): true when this hit originates INSIDE an explosion
-- (the explosion's per-tile object-hit callback). Explosive objects are NOT
-- detonated here in that case — the explosion queue chains them via
-- ConsumeExplosiveObjectAt so the 128-event cap (TRG-011) spans the whole chain
-- with no nested QueueExplosion. A direct attack / weather hit (fromExplosion
-- false) detonates an explosive top-level.
-- `attacker` (optional, 2026-10-28): the UNIT whose attack caused this hit. Only
-- used to tag an explosive detonation with an instigator (Treasure Hunter escape,
-- project_rules 230). Weather/terrain/explosion-chain callers pass nothing.

-- Treasure Hunter (project_rules 230, 2026-10-28 ruling): damage from a map object a
-- unit set off on purpose counts as an attack. Same rule shape as CombatResolver.ApplyOutcome.
local function markHunterAttacked(target: any, instigator: any, dmg: any)
	if target and target.eventName == "Treasure Hunter" and instigator and instigator ~= target
		and (dmg or 0) > 0 and not target.hunterAttacked then
		target.hunterAttacked = true
		print(string.format("[ObjectEffectService] Treasure Hunter %s hit by object set off by %s -> will try to escape",
			tostring(target.name), tostring(instigator.name)))
	end
end

function ObjectEffectService.ApplyObjectHit(state: any, x: any, y: any, n: any, attackElement: any, fromExplosion: any, attacker: any): any
	if not (state and state.objects and x and y) then return "not-found" end
	for _, inst in ipairs(state.objects) do
		-- A hidden object cannot be hit until it is revealed (no HP / break news leaks its tile).
		if inst.x == x and inst.y == y and not inst.hidden then
			local def = inst.type and ObjectData.Objects[inst.type]
			-- USER RULING 2026-10-30 (project_rules 241 B3): ANY hit on a Mimic — disguised or
			-- unmasked, from any source — wakes it instead of damaging it. Chests are breakable now,
			-- so a disguised Mimic must take hits too or it could be spotted by elimination.
			if inst.type and ObjectEffectService.DISGUISES[inst.type] then
				if ObjectEffectService.WakeByHit(state, inst, attacker) then return "woke" end
				return "immune"
			end
			-- EXPLOSIVE objects (Bomb Barrel / Land Mine) carry no hp bar — a hit
			-- DETONATES them (objects_encounters: "Fire-tag attack, Explosion, or
			-- Destroyed"). Inside an explosion we skip (queue chains it); otherwise
			-- detonate top-level at this tile with the per-source 25% Max HP payload.
			if def and objHasTag(def, "Explosive") then
				if fromExplosion then return "immune" end
				if _tileEffectService and _tileEffectService.QueueExplosion then
					local _shownType = ObjectEffectService.GetDisplayType(inst, nil)  -- log label (never the true Mimic type)
					ObjectEffectService.RemoveObjectInstance(state, inst)
					if BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectChanged then
						BattleVisualBroadcaster.ObjectChanged(x, y, { destroyed = true, exploded = true }, _shownType)
					end
					-- AC-012 Trapmaker's Roll: a wearer's Land Mine set off by a hit still blasts +20% (2026-10-29).
					_tileEffectService.QueueExplosion(x, y, 0, "object", 0.25 * (inst.trapPowerMult or 1), state.units, "box", objHasTag(def, "Trap"),
						attacker and attacker.id or nil)
				print(string.format("[ObjectEffectService] %s detonated by hit at (%d,%d)", tostring(inst.type), x, y))
				ObjectiveService.RecordEvent(state, "objectsBroken", 1)
					return "detonated"
				end
				return "immune"
			end
			if (not isBreakableObject(def)) or inst.hp == nil then
				return "immune"
			end
			-- Elemental instant-kill: attack element matches the object's instantKillTags.
			local instant = false
			if attackElement and type(def.instantKillTags) == "table" then
				for _, t in ipairs(def.instantKillTags) do
					if t == attackElement then instant = true; break end
				end
			end
			-- HD-009 Demolition Mask one-hit kill (USER RULING 2026-10-30 3:15 PM, nonweapon_equipment 32):
			-- any hit from a wearer destroys an obstacle object or placed item - every breakable object
			-- that was breakable before rule 241 (Ice Spike, OBS walls, Stone Pillar, placed items, either
			-- side). Objects made breakable by rule 241 (newlyBreakable) still take 3 hits. Lazy require,
			-- same as the Salvager's Cap check below.
			if not instant and attacker and not def.newlyBreakable then
				local _apsMask = (require :: any)(script.Parent.ArmorPassiveService)
				if _apsMask.CanInteractBreakObjects and _apsMask.CanInteractBreakObjects(attacker) then instant = true end
			end
			local dmg = instant and inst.hp or math.max(1, math.floor(tonumber(n) or 1))
			inst.hp = math.max(0, inst.hp - dmg)
			if inst.hp <= 0 then
				local _shownType = ObjectEffectService.GetDisplayType(inst, nil)  -- log label (Mimic-safe)
				ObjectEffectService.RemoveObjectInstance(state, inst)
				-- OBS Phase 2c-0: tell clients the tile opened so they drop their local
				-- blocker (GetObjectAt / LoS) and refresh the inspector HP readout.
				if BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectChanged then
					BattleVisualBroadcaster.ObjectChanged(x, y, { destroyed = true }, _shownType)
				end
				ObjectiveService.RecordEvent(state, "objectsBroken", 1)
				-- HD-011 Salvager's Cap (user ruling 2026-10-29, reward changed 2026-11-01): a player unit
				-- wearing it that destroys a breakable object gets a little gold + 5% mercury + 5% gear
				-- (salvage branch of _grantChestReward). Not counted as a chest opened; no Treasure Seeker bonus.
				-- USER RULING 2026-10-30 (rule 241 B4): only objects breakable BEFORE that ruling qualify;
				-- map objects flagged newlyBreakable in ObjectData give no salvage roll.
				-- DEV DEFAULT 2026-11-01 (Simulator: conjured Ice Spike salvage farm): only objects the
				-- map generated qualify; anything placed mid-battle (inst.spawned) gives no salvage roll.
				if attacker and attacker.side == "Player" and not (def and def.newlyBreakable) and not inst.spawned then
					local _apsSal = (require :: any)(script.Parent.ArmorPassiveService)
					if _apsSal.CanInteractBonusLoot(attacker) then
						print(string.format("[ObjectEffectService] Salvager's Cap: %s salvages the %s", tostring(attacker.name), tostring(_shownType)))
						if BattleVisualBroadcaster and BattleVisualBroadcaster.Log then
							BattleVisualBroadcaster.Log("action", `{attacker.name} salvages the wreckage.`, attacker.id)
						end
						ObjectEffectService._grantChestReward(attacker, { state = state, objInstance = inst, allUnits = state.units }, { salvage = true })
					end
				end
				return "destroyed"
			end
			-- OBS Phase 2c-0: broadcast the new hp so an open inspector card shows N/3 live.
			if BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectChanged then
				BattleVisualBroadcaster.ObjectChanged(x, y, { newHp = inst.hp })
			end
			return inst.hp
		end
	end
	return "not-found"
end

-- OBS Phase 2c-E — object PUSH (map_gen_rules row 83; objects_encounters 83/84).
-- Mirrors the UNIT stepping in DisplacementService.ResolvePush (bounds / IsBlocked /
-- elevation-up / unit-occupied; stop one tile BEFORE the first blocked tile). Objects
-- take NO collision or fall damage. Distance = max(0, force - nativeStability) using the
-- object's flat native Stability (3). An Ad Billboard / immovable object is a no-op
-- (rows 85/93). On a successful move the object relocates (old tile -> passable, new tile
-- -> blocked: BLOCKERS + OBJECT_MAP + server visual), carries its hp, and fires
-- ObjectChanged{ moved = {...} } so clients relocate their blocker cache + inspector.
-- Server-authoritative (SEC-002): the caller passes the actor's resolved Force; this
-- never trusts a client. Returns: { moved=true, fromX, fromY, toX, toY, tiles }
-- | "immovable" | "blocked" | "not-found".
-- DORMANT in 2c-E: wired to a Push command by the Studio-paired E-2 increment.
function ObjectEffectService.PushObject(state: any, x: any, y: any, dx: any, dy: any, force: any): any
	if not (state and state.objects and x and y and dx and dy) then return "not-found" end
	local sx = (dx > 0 and 1) or (dx < 0 and -1) or 0
	local sy = (dy > 0 and 1) or (dy < 0 and -1) or 0
	if sx == 0 and sy == 0 then return "blocked" end

	-- Locate the object instance on the tile.
	local inst = nil
	for _, o in ipairs(state.objects) do
		if o.x == x and o.y == y then inst = o; break end
	end
	if not inst then return "not-found" end
	local def = inst.type and ObjectData.Objects[inst.type]
	if not def or def.passable ~= false then return "not-found" end
	-- Ad Billboard / immovable objects never move (map_gen_rules rows 85/93).
	if def.isImmovable == true then return "immovable" end

	local stability = tonumber(def.nativeStability) or 3
	local distance = math.max(0, (tonumber(force) or 0) - stability)
	if distance <= 0 then return "blocked" end

	-- Map bounds from the elevation grid ([y][x]); off-grid = off map (GetElevation
	-- returns 1 off-map, so an explicit bounds check is required).
	local emap = GameConstants.ELEVATION_MAP or {}
	local mapH = #emap
	local mapW = (mapH > 0 and type(emap[1]) == "table") and #(emap[1] :: any) or 0
	local function insideMap(nx: any, ny: any): boolean
		return nx >= 1 and ny >= 1 and nx <= mapW and ny <= mapH
	end
	local function unitAt(nx: any, ny: any): boolean
		for _, u in ipairs(state.units or {}) do
			if u.isAlive and u.tileX == nx and u.tileY == ny then return true end
		end
		return false
	end

	-- Step tile-by-tile, stopping one tile BEFORE the first obstacle (mirror
	-- DisplacementService.ResolvePush checks 1-4; no collision/fall damage for objects).
	local curX, curY = x, y
	local curElev = GameConstants.GetElevation(curX, curY)
	local tiles = 0
	local collided = false
	local collidedX, collidedY = nil, nil
	local collidedKind = nil  -- "edge" / "blocker" / "elevation" / "unit" (GL-014 Chain-Push, 2026-10-29)
	for _ = 1, distance do
		local nx, ny = curX + sx, curY + sy
		if not insideMap(nx, ny) then collided=true; collidedX,collidedY=nx,ny; collidedKind="edge"; break end
		if GameConstants.IsBlocked(nx, ny) then collided=true; collidedX,collidedY=nx,ny; collidedKind="blocker"; break end
		local nextElev = GameConstants.GetElevation(nx, ny)
		if nextElev > curElev then collided=true; collidedX,collidedY=nx,ny; collidedKind="elevation"; break end
		if unitAt(nx, ny) then collided=true; collidedX,collidedY=nx,ny; collidedKind="unit"; break end
		curX, curY, curElev = nx, ny, nextElev
		tiles += 1
	end

	if tiles == 0 then return "blocked" end

	-- Relocate. Mirror PlaceObjectInstance's blocker-entry shape; keep OBJECT_MAP
	-- (GetObjectAt) and the server visual consistent with the new tile.
	local fromX, fromY = inst.x, inst.y
	if GameConstants.RemoveBlockerAt then GameConstants.RemoveBlockerAt(fromX, fromY) end
	if _objectVisualRemover then _objectVisualRemover(inst) end
	if GameConstants.OBJECT_MAP then
		if GameConstants.OBJECT_MAP[fromY] then GameConstants.OBJECT_MAP[fromY][fromX] = nil end
		GameConstants.OBJECT_MAP[curY] = GameConstants.OBJECT_MAP[curY] or {}
		GameConstants.OBJECT_MAP[curY][curX] = inst.type
	end
	inst.x, inst.y = curX, curY
	if GameConstants.BLOCKERS then
		table.insert(GameConstants.BLOCKERS, {
			tileX = curX, tileY = curY, objectType = inst.type,
			tags = { "BlocksAOE", "BlocksLoS" }, height = def.standingHeight,
		})
	end
	if _objectRenderer then _objectRenderer(inst) end

	if BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectChanged then
		BattleVisualBroadcaster.ObjectChanged(fromX, fromY, { moved = {
			fromX = fromX, fromY = fromY, toX = curX, toY = curY,
			-- Client-visible type only (Mimic disguise: never leak the true type).
			hp = inst.hp, objType = ObjectEffectService.GetDisplayType(inst, nil), height = def.standingHeight,
		} }, ObjectEffectService.GetDisplayType(inst, nil))
	end
	print(string.format("[ObjectEffectService] PushObject | %s (%d,%d)->(%d,%d) tiles=%d force=%s",
		tostring(inst.type), fromX, fromY, curX, curY, tiles, tostring(force)))
	return { moved = true, fromX = fromX, fromY = fromY, toX = curX, toY = curY, tiles = tiles, collided = collided, collidedX = collidedX, collidedY = collidedY, collidedKind = collidedKind }
end

-- OBS Phase 2c-E2: push-candidate list for breakable blocker-prop OBS objects, used
-- by BattleTurnController to extend its unit push candidates. Mirrors the unit push
-- convention (Chebyshev range; maxPushDistance = max(0, Force - stability)). Billboards
-- (isImmovable) and non-breakable objects are excluded so they are never offered.
function ObjectEffectService.GetPushableObjectTargets(state: any, unit: any, minDist: any, maxDist: any, pusherForce: any): any
	local out = {}
	if not (state and state.objects and unit) then return out end
	local ux, uy = unit.tileX, unit.tileY
	local lo = tonumber(minDist) or 1
	local hi = tonumber(maxDist) or 1
	for _, inst in ipairs(state.objects) do
		local def = inst and inst.type and ObjectData.Objects[inst.type]
		if def and def.passable == false and def.isImmovable ~= true
			and type(def.hitsToDestroy) == "number" and def.hitsToDestroy > 0
			and inst.x and inst.y then
			local dist = math.max(math.abs(inst.x - ux), math.abs(inst.y - uy))
			if dist >= lo and dist <= hi then
				local stability = tonumber(def.nativeStability) or 3
				local maxPush = math.max(0, (tonumber(pusherForce) or 1) - stability)
				table.insert(out, {
					id = string.format("obj:%d,%d", inst.x, inst.y),
					name = def.id or inst.type,
					tileX = inst.x, tileY = inst.y,
					maxPushDistance = maxPush, kind = "object",
				})
			end
		end
	end
	return out
end

-- Inject the direction prompter (Main wires promptCardinalDirection). Lets a siege
-- handler ask the player to AIM in a cardinal direction: fn(actor) -> "N"/"E"/"S"/"W"
-- or nil. Blocking (yields until the player chooses). nil-safe: if unset, siege
-- handlers fall back to auto-targeting the nearest enemy.
local _directionPrompter = nil
function ObjectEffectService.SetDirectionPrompter(fn: any)
	_directionPrompter = fn
end

-- Inject the TILE prompter (BattleTurnController wires promptTargetTile). The tile
-- analogue of the direction prompter: lets an object handler ask the player to
-- pick a target TILE within a range of an origin. Signature:
--   fn(actor, originX, originY, range, legalTiles) -> {x=,y=} or nil
-- Blocking (yields until the player taps a tile or it times out). nil-safe: if no
-- prompter is injected (AI/headless), the caller falls back to auto-targeting.
local _tilePrompter = nil
function ObjectEffectService.SetTilePrompter(fn: any)
	_tilePrompter = fn
end

-- Inject the CHOICE prompter (BattleTurnController wires promptObjectChoice, 2026-11-06 Forge).
-- fn(actor, title, options) -> one of the options (validated by the prompter) or nil.
-- Blocking. nil-safe: if unset, the caller makes an automatic pick.
local _choicePrompter = nil
function ObjectEffectService.SetChoicePrompter(fn: any)
	_choicePrompter = fn
end

-- Inject the runtime tile reshaper (Main wires a closure over its mapFolder):
-- fn(x, y, newTerrain, newElevation) -> updates the live tile Part visual.
local _tileReshaper = nil
function ObjectEffectService.SetTileReshaper(fn: any)
	_tileReshaper = fn
end
-- Remove a placed object whose time ran out (2026-10-27, Hardlight Wall) and tell clients.
function ObjectEffectService.ExpireObject(state: any, inst: any)
	if not (state and inst) then return end
	ObjectEffectService.RemoveObjectInstance(state, inst)
	if BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectChanged then
		BattleVisualBroadcaster.ObjectChanged(inst.x, inst.y, { destroyed = true })
	end
	print(string.format("[ObjectEffectService] %s at (%s,%s) expired", tostring(inst.type), tostring(inst.x), tostring(inst.y)))
end

-- Public wrapper (2026-10-26, Excavation Drill): redraw one tile at a new terrain/elevation.
function ObjectEffectService.ReshapeTile(x: any, y: any, terrainId: any, elevation: any)
	if _tileReshaper then _tileReshaper(x, y, terrainId, elevation) end
end
-- Lowered-tile redraw (2026-10-26, Excavation Drill D1 fix): Main injects a closure that
-- clears the tile's old voxel column, reshapes the Part, then rebuilds the voxel column at
-- the new height. Kept separate from the shared reshaper so Stone Pillar / weather paths
-- are unchanged. Falls back to the plain reshape when not wired.
local _tileLowerer = nil
function ObjectEffectService.SetTileLowerer(fn: any)
	_tileLowerer = fn
end
function ObjectEffectService.LowerTileVisual(x: any, y: any, terrainId: any, elevation: any)
	if _tileLowerer then
		_tileLowerer(x, y, terrainId, elevation)
	elseif _tileReshaper then
		_tileReshaper(x, y, terrainId, elevation)
	end
end

-- Place a NEW map-object instance into the live battle (Forge, Mimic reveal).
-- Appends to state.objects (generator shape {id,type,x,y}) so Interact/aura/
-- death systems see it, and renders it via the injected renderer. Returns the
-- new instance, or nil if the tile is already occupied by an object.
local _spawnedObjectCounter = 0
-- OBJECT RECALL (UTI-018, user ruling 2026-10-27): teleport a placed object to (x, y).
-- Ignores Stability. The SAME instance moves, so hp, lifeCt, shots, supplies, owner, hidden
-- flag and aura membership (keyed by id) are kept. Moves the blocker entry and OBJECT_MAP for
-- solid objects and re-renders unless hidden; a hidden object is moved without a broadcast.
-- The caller has already checked the tile and cleared any trap there.
function ObjectEffectService.MoveObjectInstance(state: any, inst: any, x: any, y: any): boolean
	if not (state and inst and x and y and inst.x and inst.y) then return false end
	local fromX, fromY = inst.x, inst.y
	if fromX == x and fromY == y then return false end
	local def = inst.type and ObjectData.Objects[inst.type]
	local solid = def ~= nil and def.passable == false
	if solid and GameConstants.RemoveBlockerAt then GameConstants.RemoveBlockerAt(fromX, fromY) end
	if not inst.hidden and _objectVisualRemover then _objectVisualRemover(inst) end
	local omap = GameConstants.OBJECT_MAP
	if omap and omap[fromY] and omap[fromY][fromX] == inst.type then
		omap[fromY][fromX] = nil
		omap[y] = omap[y] or {}
		omap[y][x] = inst.type
	end
	inst.x, inst.y = x, y
	if solid and GameConstants.BLOCKERS then
		table.insert(GameConstants.BLOCKERS, {
			tileX = x, tileY = y, objectType = inst.type,
			tags = { "BlocksAOE", "BlocksLoS" }, height = def.standingHeight,
		})
	end
	if not inst.hidden then
		if _objectRenderer then _objectRenderer(inst) end
		if BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectChanged then
			if solid then
				BattleVisualBroadcaster.ObjectChanged(fromX, fromY, { moved = {
					fromX = fromX, fromY = fromY, toX = x, toY = y,
					hp = inst.hp, objType = ObjectEffectService.GetDisplayType(inst, nil), height = def.standingHeight,
				} }, ObjectEffectService.GetDisplayType(inst, nil))
			else
				-- Passable objects carry no client blocker: clear the old tile, then send the hp.
				BattleVisualBroadcaster.ObjectChanged(fromX, fromY, { destroyed = true })
				if type(inst.hp) == "number" then
					BattleVisualBroadcaster.ObjectChanged(x, y, { newHp = inst.hp })
				end
			end
		end
	end
	print(string.format("[ObjectEffectService] MoveObjectInstance | %s (%d,%d)->(%d,%d)%s",
		tostring(inst.type), fromX, fromY, x, y, inst.hidden and " [hidden]" or ""))
	return true
end

-- Remove every Trap-tagged object on (x, y) (user ruling 2026-10-27: Forge and deployable
-- items replace the trap on their tile). A visible trap's removal is announced; a hidden one
-- is removed silently. It does not spring. Returns how many were removed.
function ObjectEffectService.ClearTrapsAt(state: any, x: any, y: any): number
	if not (state and state.objects and x and y) then return 0 end
	local n = 0
	for i = #state.objects, 1, -1 do
		local o = state.objects[i]
		local odef = o and o.type and ObjectData.Objects[o.type]
		if o and o.x == x and o.y == y and objHasTag(odef, "Trap") then
			local wasHidden = o.hidden == true
			ObjectEffectService.RemoveObjectInstance(state, o)
			if not wasHidden and BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectChanged then
				BattleVisualBroadcaster.ObjectChanged(x, y, { destroyed = true })
			end
			print(string.format("[ObjectEffectService] Trap %s at (%d,%d) replaced (%s)",
				tostring(o.type), x, y, wasHidden and "hidden" or "visible"))
			n += 1
		end
	end
	return n
end

-- replaceTraps (optional, user ruling 2026-10-27): true for the Forge and deployable items --
-- any trap on the tile (either side, visible or hidden) is replaced instead of blocking.
function ObjectEffectService.PlaceObjectInstance(state: any, objType: any, x: any, y: any, ownerSide: any, casterId: any, replaceTraps: any): any
	if not (state and state.objects and objType and x and y) then return nil end
	-- Do not stack two objects on the same tile. Exceptions (user rulings 2026-10-27), applied
	-- only once every other placement check below passes, so a refusal never removes anything:
	--   * a HIDDEN object owned by another side is replaced silently (no tile leak);
	--   * with replaceTraps, ANY trap on the tile is replaced.
	local _replaceObj = nil
	for _, o in ipairs(state.objects) do
		if o.x == x and o.y == y then
			local odef = o.type and ObjectData.Objects[o.type]
			if replaceTraps == true and objHasTag(odef, "Trap") then
				_replaceObj = o
				break
			end
			-- Only a placement with a known side replaces a hidden object (F1 fix): dev spawns
			-- pass no ownerSide and must never silently delete a hidden trap.
			if o.hidden and ownerSide ~= nil and o.ownerSide ~= nil and o.ownerSide ~= ownerSide then
				_replaceObj = o
				break
			end
			return nil
		end
	end
	-- A SOLID (non-passable) object must not trap a living unit: refuse placement on a
	-- tile a unit occupies. Passable objects (traps, springs) may share a unit's tile.
	local placingDef = ObjectData.Objects[objType]
	if placingDef and placingDef.passable == false and state.units then
		for _, u in ipairs(state.units) do
			if u.isAlive and u.tileX == x and u.tileY == y then
				return nil
			end
		end
	end
	-- Max 2 traps per caster (2026-10-26, authored SkillData rule: "Maximum 2 active traps per
	-- caster. Oldest removed if exceeded."). Applies ONLY to Trap-tagged objects placed by a known
	-- caster (casterId); blockers / springs / other objects are unaffected. "Oldest" = earliest
	-- still in state.objects insertion order. Remove down so the new trap leaves the caster at 2.
	if _replaceObj then
		-- A hidden object leaves silently (the client never saw it); a visible trap is announced.
		local wasHidden = _replaceObj.hidden == true
		ObjectEffectService.RemoveObjectInstance(state, _replaceObj)
		if not wasHidden and BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectChanged then
			BattleVisualBroadcaster.ObjectChanged(x, y, { destroyed = true })
		end
		print(string.format("[ObjectEffectService] %s %s at (%d,%d) replaced by %s",
			wasHidden and "Hidden" or "Visible", tostring(_replaceObj.type), x, y, tostring(objType)))
	end
	if casterId and placingDef and objHasTag(placingDef, "Trap") then
		local mine = {}
		for _, o in ipairs(state.objects) do
			local odef = o.type and ObjectData.Objects[o.type]
			if o.casterId == casterId and objHasTag(odef, "Trap") then
				table.insert(mine, o)
			end
		end
		while #mine >= 2 do
			local oldest = table.remove(mine, 1)
			ObjectEffectService.RemoveObjectInstance(state, oldest)
			-- A hidden trap was never shown, so its removal is not announced (no tile leak).
			if not oldest.hidden and BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectChanged then
				BattleVisualBroadcaster.ObjectChanged(oldest.x, oldest.y, { destroyed = true })
			end
			print(string.format("[ObjectEffectService] Trap limit: removed oldest trap id=%s for caster %s",
				tostring(oldest.id), tostring(casterId)))
		end
	end
	_spawnedObjectCounter += 1
	local inst = { id = "spawnobj_" .. _spawnedObjectCounter, type = objType, x = x, y = y, ownerSide = ownerSide, casterId = casterId,
		spawned = true } -- placed mid-battle (skill, item, event): never gives a Salvager's Cap roll
	-- Placed objects get their durability too (fix 2026-10-26): InitObjectHp only runs at battle
	-- start, so every object placed mid-battle (item traps, Portable Ballista, gadgets) had no hp
	-- and was immune to attacks. Light gadgets break after hitsToDestroy hits (DB SPLIT ruling).
	if isBreakableObject(placingDef) then
		inst.hp = placingDef.hitsToDestroy
	end
	-- Enemy-placed traps are hidden from the player until something reveals them (user ruling
	-- 2026-10-27). A hidden trap is not drawn, so its tile shows nothing; it still springs.
	-- A trap placed inside one of the player's reveal zones is shown at once.
	if ownerSide and ownerSide ~= "Player" and objHasTag(placingDef, "Trap")
		and not ObjectEffectService.IsRevealedFor(x, y, "Player") then
		inst.hidden = true
	end
	table.insert(state.objects, inst)
	if _objectRenderer and not inst.hidden then
		_objectRenderer(inst)
	end
	-- N1 fix (2026-10-04): a non-passable object must also become a real blocker so
	-- movement, LoS and the spawn search treat it as solid (same entry shape map-gen
	-- builds in MapService). Without this a spawned Ballista/Stone Pillar renders but
	-- units walk/see through it. Also fixes Forge/Mimic mid-battle object spawns.
	local objDef = ObjectData.Objects[objType]
	if objDef and objDef.passable == false and GameConstants.BLOCKERS then
		table.insert(GameConstants.BLOCKERS, {
			tileX      = x,
			tileY      = y,
			objectType = objType,
			tags       = { "BlocksAOE", "BlocksLoS" },
			height     = objDef.standingHeight,
		})
	end
	-- N2 fix (2026-10-04): if this object is an aura source, apply its aura immediately
	-- instead of waiting for the next unit move. ReconcileAuras only acts on recognized
	-- aura objects, so it is a harmless no-op for non-aura objects.
	if state.units then
		(ObjectEffectService :: any).ReconcileAuras(state.units, state)
	end
	print(string.format("[ObjectEffectService] PlaceObjectInstance | %s at (%d,%d) id=%s", objType, x, y, inst.id))
	return inst
end

-- Show one hidden object (draws it now). Returns true when it was hidden.
function ObjectEffectService.RevealObject(o: any): boolean
	if not (o and o.hidden) then return false end
	o.hidden = false
	if _objectRenderer then _objectRenderer(o) end
	print(string.format("[ObjectEffectService] Revealed hidden %s at (%s,%s)", tostring(o.type), tostring(o.x), tostring(o.y)))
	return true
end

--------------------------------------------------------------------
-- MIMIC DISGUISE (user-locked 2026-10-28). A Mimic is DISGUISED as a Treasure Chest
-- until it is unmasked (reveal effect) or woken (interact / attack). Derived, not stored:
-- disguised = type has a DISGUISES entry and inst.unmasked ~= true, so map-gen, spawned
-- and regenerated Mimics all start disguised with no init step. Separate from inst.hidden
-- (hidden = not drawn; disguised = drawn as something else). The server keeps the TRUE
-- type for logic; everything sent to clients must use GetDisplayType (SEC-002 / NET-003).
--------------------------------------------------------------------
ObjectEffectService.DISGUISES = table.freeze({
	["Mimic"] = "Treasure Chest",
})

function ObjectEffectService.IsDisguised(o: any): boolean
	return o ~= nil and o.type ~= nil and ObjectEffectService.DISGUISES[o.type] ~= nil and o.unmasked ~= true
end

-- Type string the CLIENT may see for this instance (or for a bare type name with no
-- instance, e.g. map-build tile data — every map object starts disguised).
function ObjectEffectService.GetDisplayType(o: any, bareType: any): any
	if o == nil then
		return (bareType and ObjectEffectService.DISGUISES[bareType]) or bareType
	end
	if ObjectEffectService.IsDisguised(o) then
		return ObjectEffectService.DISGUISES[o.type]
	end
	return o.type
end

-- Client-safe copies of the MapDataSync object grid + blocker list (true disguised
-- types replaced by their display type). Server tables are not mutated.
function ObjectEffectService.SanitizeMapSync(objectGrid: any, blockers: any): (any, any)
	local grid = {}
	for y, row in pairs(objectGrid or {}) do
		local outRow = {}
		for x, name in pairs(row) do
			outRow[x] = ObjectEffectService.GetDisplayType(nil, name)
		end
		grid[y] = outRow
	end
	local bl = {}
	for i, b in ipairs(blockers or {}) do
		local copy = table.clone(b)
		copy.objectType = ObjectEffectService.GetDisplayType(nil, b.objectType)
		bl[i] = copy
	end
	return grid, bl
end

-- Unmask a disguised object (reveal effects). It stays DORMANT: no summon, no enemy.
-- Re-renders with the true model + tile attributes (BUG-034: the change reaches clients
-- through the replicated tile attributes / model). Returns true when it was disguised.
function ObjectEffectService.UnmaskObject(o: any, revealerName: any): boolean
	if not ObjectEffectService.IsDisguised(o) then return false end
	-- Remove the chest visual while still disguised (names resolve to the display type).
	if not o.hidden and _objectVisualRemover then _objectVisualRemover(o) end
	o.unmasked = true
	if not o.hidden and _objectRenderer then _objectRenderer(o) end
	-- A3 (2026-10-28): an already-open inspector card refreshes to the now-true display
	-- type. Sent only AFTER unmask (GetDisplayType is now the real type) and only for a
	-- visible object, so nothing leaks while disguised.
	if not o.hidden and BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectChanged then
		BattleVisualBroadcaster.ObjectChanged(o.x, o.y, { objType = ObjectEffectService.GetDisplayType(o, nil) })
	end
	if BattleVisualBroadcaster and BattleVisualBroadcaster.Log then
		BattleVisualBroadcaster.Log("action", `{revealerName or "A reveal"} revealed a {o.type}!`, nil)
	end
	print(`[ObjectEffectService] Unmasked {o.type} at ({o.x},{o.y}) by {tostring(revealerName)}`)
	return true
end

-- Forward declaration: the Mimic handler lives in the Handlers table below.
local _wakeHandler: any = nil

-- Wake an UNMASKED Mimic that was attacked: runs the same Mimic handler (becomes the
-- enemy). Returns true when it woke.
function ObjectEffectService.WakeUnmasked(state: any, o: any, actor: any): boolean
	if not (o and o.unmasked == true and ObjectEffectService.DISGUISES[o.type] and _wakeHandler) then
		return false
	end
	local objId = o.id or ("obj_@" .. tostring(o.x) .. "," .. tostring(o.y))
	if _consumed[objId] then return false end
	local seedBase = (state and state.ct or 0) + ((o.x or 0) * 73856093) + ((o.y or 0) * 19349663)
	local ok = _wakeHandler({
		actor = actor or { tileX = o.x, tileY = o.y },
		objInstance = o, objDef = ObjectData.Objects[o.type],
		state = state, allUnits = state and state.units or {}, rng = Random.new(seedBase),
	})
	if ok then
		_consumed[objId] = true
		if BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectChanged then
			BattleVisualBroadcaster.ObjectChanged(o.x, o.y, { destroyed = true })
		end
		if BattleVisualBroadcaster and BattleVisualBroadcaster.Log then
			BattleVisualBroadcaster.Log("action", `{(actor and actor.name) or "Someone"} woke the {o.type}!`, actor and actor.id)
		end
	end
	return ok == true
end

-- Wake a Mimic that was HIT, disguised or not (USER RULING 2026-10-30, project_rules 241 B3).
-- A disguised one is unmasked first so it wakes through the same path (and is named "Mimic" in
-- the log); if the wake fails the disguise is put back, so nothing leaks. Returns true when it woke.
function ObjectEffectService.WakeByHit(state: any, o: any, actor: any): boolean
	if not (o and o.type and ObjectEffectService.DISGUISES[o.type]) then return false end
	local wasUnmasked = o.unmasked
	o.unmasked = true
	local ok = ObjectEffectService.WakeUnmasked(state, o, actor)
	if not ok then o.unmasked = wasUnmasked end
	print(`[ObjectEffectService] WakeByHit | {o.type} at ({o.x},{o.y}) woke={ok} (was unmasked={wasUnmasked == true})`)
	return ok
end

-- Scanner Lens reveal zone for `side`, lasting durationCt.
function ObjectEffectService.AddRevealZone(tileSet: any, durationCt: any, side: any)
	if type(tileSet) ~= "table" or (tonumber(durationCt) or 0) <= 0 then return end
	table.insert(_revealZones, { tiles = tileSet, ct = tonumber(durationCt), side = side })
end
function ObjectEffectService.GetRevealZones(): { any }
	return _revealZones
end
-- Is tile (x, y) inside a live reveal zone owned by `side`?
function ObjectEffectService.IsRevealedFor(x: any, y: any, side: any): boolean
	for _, z in ipairs(_revealZones) do
		if z.ct > 0 and z.side == side and z.tiles[x .. "," .. y] then return true end
	end
	return false
end
-- Is this unit standing in a live reveal zone owned by another side? (It cannot Hide there.)
function ObjectEffectService.IsHideBlocked(unit: any): boolean
	if not (unit and unit.tileX) then return false end
	for _, z in ipairs(_revealZones) do
		if z.ct > 0 and z.side ~= unit.side and z.tiles[unit.tileX .. "," .. unit.tileY] then return true end
	end
	return false
end
-- Run zone time down on the battle clock (PulseScheduler sweeps the zones first).
function ObjectEffectService.TickRevealZones(ctElapsed: any)
	for i = #_revealZones, 1, -1 do
		local z = _revealZones[i]
		z.ct -= (ctElapsed or 0)
		if z.ct <= 0 then table.remove(_revealZones, i) end
	end
end

-- Reset the usage ledger at battle start (called from Main on new battle).
function ObjectEffectService.ResetBattle()
	table.clear(_revealZones)
	table.clear(_consumed)
	table.clear(_usedThisTurn)
	_aliveSnapshot = nil
	-- 2026-10-30 aura fix: forget last battle's aura memberships (object ids repeat between maps).
	-- Looked up on the module table: ClearAllAuras is defined further down.
	local _clearAll = (ObjectEffectService :: any).ClearAllAuras
	if _clearAll then _clearAll(nil) end
	print("[ObjectEffectService] Usage ledger reset for new battle.")
end

--------------------------------------------------------------------
-- EFFECT HANDLERS — keyed by ObjectData archetype id.
-- Each: function(ctx) -> ok:boolean, reason:string?
-- ctx = { actor, objInstance, objDef, state, allUnits }
--------------------------------------------------------------------
local Handlers = {}

-- Healing Spring — fully restore the interacting unit's HP (G1 proof handler).
Handlers["Healing Spring"] = function(ctx: any): (boolean, any)
	local actor = ctx.actor
	if not actor or actor.maxHp == nil then
		return false, "Healing Spring: actor has no HP."
	end
	local before = actor.currentHp or 0
	-- Festering Wound anti-heal (user ruling 2026-10-26): the spring restores the MISSING HP,
	-- reduced like every other object heal, instead of always snapping to full.
	local heal = (actor.maxHp or 0) - before
	local _hrm = StatusService.GetHealingReceivedMult(actor)
	if _hrm ~= 1 then heal = math.max(0, math.floor(heal * _hrm)) end
	actor.currentHp = math.min(actor.maxHp, before + heal)
	if actor.currentHp > before then StatusService.WeakenVenomOnHeal(actor) end  -- healing weakens Venom (2026-10-26)
	if BattleVisualBroadcaster and BattleVisualBroadcaster.UnitStateChanged then
		BattleVisualBroadcaster.UnitStateChanged(actor)
	end
	print(string.format("[ObjectEffectService] Healing Spring | %s HP %d -> %d",
		actor.name, before, actor.currentHp))
	return true, nil
end

--------------------------------------------------------------------
-- SHARED HELPERS
--------------------------------------------------------------------
local function livingAllies(actor: any, allUnits: any, includeSelf: any)
	local out = {}
	for _, u in ipairs(allUnits) do
		if u.isAlive and u.side == actor.side and (includeSelf or u.id ~= actor.id) then
			table.insert(out, u)
		end
	end
	return out
end

local function livingEnemies(actor: any, allUnits: any)
	local out = {}
	for _, u in ipairs(allUnits) do
		if u.isAlive and u.side ~= actor.side and not u.isGroundTarget then
			table.insert(out, u)
		end
	end
	return out
end

local function enemiesInRadius(actor: any, allUnits: any, cx: any, cy: any, radius: any)
	local out = {}
	for _, u in ipairs(allUnits) do
		if u.isAlive and u.side ~= actor.side and not u.isGroundTarget
			and u.tileX and u.tileY then
			if math.abs(u.tileX - cx) <= radius and math.abs(u.tileY - cy) <= radius then
				table.insert(out, u)
			end
		end
	end
	return out
end

-- Apply a status to a unit and rebuild its stats so stat-% buffs take effect
-- immediately (RebuildUnitStats folds GetStatusStatModifiers; status change
-- does not otherwise trigger a rebuild).
local function applyAndRebuild(unit: any, statusId: any, sourceId: any)
	StatusService.ApplyStatus(unit, statusId, sourceId)
	if EquipmentService and EquipmentService.RebuildUnitStats then
		EquipmentService.RebuildUnitStats(unit)
	end
	if BattleVisualBroadcaster and BattleVisualBroadcaster.UnitStateChanged then
		BattleVisualBroadcaster.UnitStateChanged(unit)
	end
end

--------------------------------------------------------------------
-- RESTORE HANDLERS
--------------------------------------------------------------------
Handlers["Magic Spring"] = function(ctx: any): (boolean, any)
	local a = ctx.actor
	if not a or a.maxMp == nil then return false, "Magic Spring: actor has no MP." end
	local before = a.currentMp or 0
	a.currentMp = a.maxMp
	if BattleVisualBroadcaster then BattleVisualBroadcaster.UnitStateChanged(a) end
	print(string.format("[ObjectEffectService] Magic Spring | %s MP %d -> %d", a.name, before, a.currentMp))
	return true, nil
end

Handlers["Campfire"] = function(ctx: any): (boolean, any)
	local a = ctx.actor
	if not a or a.maxHp == nil then return false, "Campfire: actor has no HP." end
	local hpGain = math.floor((a.maxHp or 0) * 0.30)
	local mpGain = math.floor((a.maxMp or 0) * 0.30)
	-- Festering Wound anti-heal (2026-10-25): environmental HP heal reduced (MP restore unaffected).
	local _hrm = StatusService.GetHealingReceivedMult(a)
	if _hrm ~= 1 then hpGain = math.max(0, math.floor(hpGain * _hrm)) end
	local _hpBefore = a.currentHp or 0
	a.currentHp = math.min(a.maxHp, (a.currentHp or 0) + hpGain)
	if (a.currentHp or 0) > _hpBefore then StatusService.WeakenVenomOnHeal(a) end  -- healing weakens Venom (2026-10-26)
	a.currentMp = math.min(a.maxMp or 0, (a.currentMp or 0) + mpGain)
	if BattleVisualBroadcaster then BattleVisualBroadcaster.UnitStateChanged(a) end
	print(string.format("[ObjectEffectService] Campfire | %s +%d HP / +%d MP", a.name, hpGain, mpGain))
	return true, nil
end

-- Potion Desk — fully recharge the INTERACTING unit's equipped consumables.
-- Scope: interacting unit only (not map-wide), DB ruling 2026-10-03. Any side may
-- use it (user ruling 2026-10-24): refills ctx.actor's own slots regardless of
-- side, same as the other self-target restore objects (Healing/Magic Spring).
--
-- The "consumable charge-refill dependency" the DB parked this on already exists:
-- the charge model is slot.currentCharges / slot.maxCharges (item use decrements
-- currentCharges in CommandService), and the Chemist skill SKL-RESTOCK already
-- refills it. Potion Desk does a FULL refill (set currentCharges = maxCharges on
-- every equipped slot), stronger than RESTOCK's +1. UnitStateChanged is the same
-- state-sync nudge SKL-RESTOCK relies on; the item bar re-reads charges from
-- GetConsumableSlots. No dedicated charges-changed remote exists (not inventing
-- one here — mirrors the proven RESTOCK path).
Handlers["Potion Desk"] = function(ctx: any): (boolean, any)
	local a = ctx.actor
	if not a then return false, "Potion Desk: no actor." end
	local refilled = 0
	for _, slot in pairs(a.consumableSlots or {}) do
		if slot and slot.consumableId then
			local maxC = slot.maxCharges or 0
			if (slot.currentCharges or 0) < maxC then
				slot.currentCharges = maxC
				refilled = refilled + 1
			end
		end
	end
	if BattleVisualBroadcaster and BattleVisualBroadcaster.UnitStateChanged then
		BattleVisualBroadcaster.UnitStateChanged(a)
	end
	print(string.format("[ObjectEffectService] Potion Desk | %s fully recharged %d consumable(s)", a.name, refilled))
	return true, nil
end

-- Witch Hut (Event/NPC, "Double EXP until battle ends; inflict Weakened (3000 CT)",
-- Risk/Reward) — 2026-10-24. Two effects:
--   (1) Double battle EXP: reuses the EXACT same proven wire as Glow Crystal —
--       set state.glowCrystalActive = true. Main copies that into
--       battleResult.glowCrystal and ProgressionService.AwardBattleXp applies the
--       x2 on each unit's end-of-battle total. Player-side only for the EXP (same
--       guard as Glow Crystal: enemies never earn XP, so an enemy activation just
--       denies the object). The shared flag means a Witch Hut + a Glow Crystal in
--       one battle still double XP ONCE (flag, not a stacking counter) — correct.
--   (2) Weakened on the interacting unit (the "risk" half) — applied to whoever
--       used it, no side restriction, mirroring Cursed Chest's self-Weakened.
Handlers["Witch Hut"] = function(ctx: any): (boolean, any)
	local state, actor = ctx.state, ctx.actor
	if not state then return false, "Witch Hut: no battle state." end
	-- Risk half first: Weakened on the user (any side), 3000 CT per DB.
	applyAndRebuild(actor, "Weakened", actor.id)
	-- Reward half: double battle EXP, player-side only (same rule as Glow Crystal).
	if actor and actor.side == "Player" then
		local already = state.glowCrystalActive == true
		state.glowCrystalActive = true
		print(string.format("[ObjectEffectService] Witch Hut | %s activated — battle XP x2 at end of battle + Weakened%s",
			tostring(actor.name), already and " (XP already doubled; no extra stacking)" or ""))
	else
		print(string.format("[ObjectEffectService] Witch Hut | %s (non-player) — Weakened applied, no XP effect",
			tostring(actor and actor.name)))
	end
	return true, nil
end

-- Idol of Fortune (Event/Shrine, "Improved item drop rates until battle ends",
-- "Does not stack") — 2026-10-24.
-- HONEST SCOPE: RewardService has a live Fortune system, but it is EXPEDITION
-- fortune (set from the deployed team's stats via SetExpeditionFortune) — there
-- is NO existing per-battle "an Idol was used, improve drops for the rest of this
-- battle" consumer. So this handler sets a battle-level flag (state.idolFortuneActive)
-- and records a normalized drop-rate bump that the chest reward path reads when it
-- generates loot DURING this battle (see _grantChestReward). It does NOT retroactively
-- affect end-of-battle victory loot yet — that grant path (Main AwardBattleXp/
-- GenerateRewards) does not read this flag. Flagged, not faked: the in-battle chest
-- drops improve; wiring the end-of-battle victory roll to this flag is a follow-up
-- owned by the reward pipeline. "Does not stack": the flag is boolean, so a second
-- Idol is a no-op.
Handlers["Idol of Fortune"] = function(ctx: any): (boolean, any)
	local state = ctx.state
	if not state then return false, "Idol of Fortune: no battle state." end
	local already = state.idolFortuneActive == true
	state.idolFortuneActive = true
	-- Normalized fortune bump (0..1) applied to in-battle reward rolls. 0.5 chosen as
	-- a meaningful-but-not-overpowering "improved" step; exact value is a tuning knob
	-- the Simulator/Designer can revisit. Does not stack (flag already set = no-op).
	state.idolFortuneBump = 0.5
	print(string.format("[ObjectEffectService] Idol of Fortune | activated — improved in-battle drop rates%s",
		already and " (already active; does not stack)" or ""))
	return true, nil
end

-- Pandora's Box (Event/Shrine, RT 50 flat, "Triggers a random map object effect,
-- drawn from the FULL pool including harmful effects; triggered effect centers on
-- the Pandora's Box tile") — 2026-10-24.
-- Rolls ONE registered handler from a curated pool and runs it with a context
-- re-centered on the Box's own tile (per DB: "triggered effect centers on the
-- Pandora's Box tile"). The pool deliberately INCLUDES harmful effects (traps,
-- explosions, enemy summons) so it can backfire on the user's side — that is the
-- object's whole point. Excluded from the pool: Pandora's Box itself (no self-
-- recursion), and objects whose effect needs a specific placed instance / terrain
-- reshape that would be meaningless re-centered (Forge, Stone Pillar, Mimic, Crystal
-- Ball). The chosen effect runs through the SAME handler table, so each sub-effect
-- keeps its own rules. Deterministic via ctx.rng (seeded in Resolve).
local PANDORA_POOL = {
	-- harmful (can hit the user's side)
	"Bomb Barrel", "Land Mine", "Spike Trap", "Bear Trap", "Snare Trap",
	"Oil Sluice", "Steam Valve", "Obelisk", "Cover of Darkness", "Mysterious Boulder",
	"Cursed Chest", "Dragon Utopia", "Eye of the Magi",
	-- beneficial
	"Healing Spring", "Magic Spring", "Campfire", "Rally Flag", "Star Axis",
	"Burning Cauldron", "War Horn", "Runed Boulder", "Blood Fountain",
	"Fountain of Fortune", "Swan Pond", "Astrolabe", "Treasure Chest",
}
Handlers["Pandora's Box"] = function(ctx: any): (boolean, any)
	local obj = ctx.objInstance
	-- Build the pick list from the pool, keeping only names that actually have a
	-- registered handler (defensive: pool names must exist, skip any that don't).
	local candidates = {}
	for _, name in ipairs(PANDORA_POOL) do
		if Handlers[name] and name ~= "Pandora's Box" then
			candidates[#candidates + 1] = name
		end
	end
	if #candidates == 0 then
		print("[ObjectEffectService] Pandora's Box | no candidate effects available — no-op")
		return true, nil
	end
	local pick = candidates[ctx.rng:NextInteger(1, #candidates)]
	-- Re-center the triggered effect on the Box's own tile: hand the sub-handler a
	-- synthetic objInstance located at the Box (so tile-centered effects like
	-- explosions/tile-effects originate here), but keep the real actor, state,
	-- allUnits and rng. objDef points at the picked archetype so damagePct etc.
	-- resolve from the right object.
	local subInst = { id = (obj and obj.id or "pandora") .. ":" .. pick, type = pick, x = obj and obj.x, y = obj and obj.y }
	local subCtx = {
		actor = ctx.actor, objInstance = subInst,
		objDef = ObjectData.Objects[pick], state = ctx.state,
		allUnits = ctx.allUnits, rng = ctx.rng,
	}
	print(string.format("[ObjectEffectService] Pandora's Box | rolled '%s' (centered on box tile)", pick))
	-- Battle log (rules 225): say what the Box rolled. The rolled handler's own lines
	-- already carry the "Pandora's Box" cause via Resolve's SetCause scope, so this is
	-- the only extra line. Pool names are real display names (no Mimic in the pool).
	if BattleVisualBroadcaster and BattleVisualBroadcaster.Log then
		local who = (ctx.actor and ctx.actor.name) or "Someone"
		BattleVisualBroadcaster.Log("action", `Pandora's Box unleashed {pick} on {who}!`, ctx.actor and ctx.actor.id)
	end
	local ok, reason = Handlers[pick](subCtx)
	return ok, reason
end

--------------------------------------------------------------------
-- SELF / ALLY TIMED BUFFS (apply status to the acting side)
-- auraStatus-free objects: Interact applies the buff to all allies incl self.
--------------------------------------------------------------------
local function allyBuffHandler(statusId: any, label: any)
	return function(ctx: any): (boolean, any)
		local a = ctx.actor
		local targets = livingAllies(a, ctx.allUnits, true)
		for _, u in ipairs(targets) do
			applyAndRebuild(u, statusId, a.id)
		end
		print(string.format("[ObjectEffectService] %s | %s -> %d ally(s) gain %s",
			label, a.name, #targets, statusId))
		return true, nil
	end
end

Handlers["Rally Flag"]       = allyBuffHandler("Rally", "Rally Flag")
Handlers["Star Axis"]        = allyBuffHandler("Spell Focus", "Star Axis")
Handlers["Burning Cauldron"] = allyBuffHandler("Battle Rage", "Burning Cauldron")
Handlers["War Horn"]         = allyBuffHandler("War Rhythm", "War Horn")
Handlers["Runed Boulder"]    = allyBuffHandler("Rune Ward", "Runed Boulder")
-- Angel Statue (DB objects_encounters: "Grants Flight for 1500 CT"). Flight's status default is
-- 3 TURNS, so the plain ally-buff handler gave turns instead of the authored 1500 CT (Studio sweep
-- 2026-11-06). Same targets as before; each NEW / refreshed non-permanent Flight instance is
-- converted to a 1500 CT window (StatusService ticks any instance that carries remainingCt).
local ANGEL_FLIGHT_CT = 1500
local _angelBase = allyBuffHandler("Flight", "Angel Statue")
Handlers["Angel Statue"] = function(ctx: any): (boolean, any)
	local ok, reason = _angelBase(ctx)
	for _, u in ipairs(livingAllies(ctx.actor, ctx.allUnits, true)) do
		local inst = StatusService.HasStatus(u, "Flight")
		if inst and not inst.permanent then
			inst.remainingCt = ANGEL_FLIGHT_CT
			inst.remainingTurns = nil
			-- The ally-buff handler already broadcast "3 turns"; resend the status list (no log diff).
			if BattleVisualBroadcaster and BattleVisualBroadcaster.StatusSync then
				BattleVisualBroadcaster.StatusSync(u)
			end
		end
	end
	return ok, reason
end
Handlers["Blood Fountain"]   = allyBuffHandler("Regeneration", "Blood Fountain")
Handlers["Fountain of Fortune"] = allyBuffHandler("Fortune Boon", "Fountain of Fortune")

--------------------------------------------------------------------
-- ALLY MAP-WIDE UTILITY
--------------------------------------------------------------------
Handlers["Swan Pond"] = function(ctx: any): (boolean, any)
	local a = ctx.actor
	local targets = livingAllies(a, ctx.allUnits, true)
	for _, u in ipairs(targets) do
		-- DB (objects_encounters Swan Pond): "Remove all debuffs from all allies". Was
		-- RemoveDispellable, which strips dispellable BUFFS (2026-10-26 fix after buffs got
		-- their DB dispellable flags). Hard-locked statuses refuse removal as usual.
		local ids = {}
		for _, inst in ipairs(u.statusInstances or {}) do
			local d = GameConstants.STATUSES[inst.id]
			if d and d.kind == "Debuff" then table.insert(ids, inst.id) end
		end
		for _, sid in ipairs(ids) do
			if StatusService.RemoveStatus(u, sid) and BattleVisualBroadcaster and BattleVisualBroadcaster.StatusExpired then
				BattleVisualBroadcaster.StatusExpired(u, sid)
			end
		end
		if EquipmentService and EquipmentService.RebuildUnitStats then EquipmentService.RebuildUnitStats(u) end
		if BattleVisualBroadcaster then BattleVisualBroadcaster.UnitStateChanged(u) end
	end
	print(string.format("[ObjectEffectService] Swan Pond | cleansed debuffs on %d ally(s)", #targets))
	return true, nil
end

Handlers["Astrolabe"] = function(ctx: any): (boolean, any)
	local a = ctx.actor
	local targets = livingAllies(a, ctx.allUnits, true)
	for _, u in ipairs(targets) do
		u.remainingRt = math.max(0, (u.remainingRt or 0) - 200)
		if BattleVisualBroadcaster then BattleVisualBroadcaster.UnitStateChanged(u) end
	end
	print(string.format("[ObjectEffectService] Astrolabe | -200 RT to %d ally(s)", #targets))
	return true, nil
end

--------------------------------------------------------------------
-- ENEMY DEBUFF / CONTROL
--------------------------------------------------------------------
Handlers["Obelisk"] = function(ctx: any): (boolean, any)
	local a = ctx.actor
	local targets = livingEnemies(a, ctx.allUnits)
	for _, u in ipairs(targets) do
		u.remainingRt = (u.remainingRt or 0) + 300
		if BattleVisualBroadcaster then BattleVisualBroadcaster.UnitStateChanged(u) end
	end
	print(string.format("[ObjectEffectService] Obelisk | +300 RT Delay to %d enemy(s)", #targets))
	return true, nil
end

Handlers["Cover of Darkness"] = function(ctx: any): (boolean, any)
	local a = ctx.actor
	local targets = enemiesInRadius(a, ctx.allUnits, a.tileX, a.tileY, 5)
	for _, u in ipairs(targets) do
		applyAndRebuild(u, "Blind", a.id)
	end
	print(string.format("[ObjectEffectService] Cover of Darkness | Blind on %d enemy(s) in R5", #targets))
	return true, nil
end

Handlers["Mysterious Boulder"] = function(ctx: any): (boolean, any)
	local a = ctx.actor
	-- Roll ONE random existing debuff from a safe pool, inflict on all enemies.
	local pool = { "Weakened", "Blind", "Pinned", "Slow", "Bleed" }
	local pick = pool[ctx.rng and ctx.rng:NextInteger(1, #pool) or math.random(1, #pool)]
	local targets = livingEnemies(a, ctx.allUnits)
	for _, u in ipairs(targets) do
		applyAndRebuild(u, pick, a.id)
	end
	print(string.format("[ObjectEffectService] Mysterious Boulder | rolled %s -> %d enemy(s)", pick, #targets))
	return true, nil
end

--------------------------------------------------------------------
-- SELF-TARGET STATUS (Cursed Chest: reward + Weakened on user)
--------------------------------------------------------------------
Handlers["Cursed Chest"] = function(ctx: any): (boolean, any)
	local a = ctx.actor
	-- HD-012 Locksmith Lens (user ruling 2026-10-29): the opener takes no Weakened.
	if (require :: any)(script.Parent.ArmorPassiveService).CanInteractOpenLocks(a) then
		print(string.format("[ObjectEffectService] Cursed Chest | Locksmith Lens: %s avoids the curse", a.name))
	else
		applyAndRebuild(a, "Weakened", a.id)
	end
	-- Treasure component shares the Treasure Chest reward path (best-effort).
	if (ObjectEffectService :: any)._grantChestReward then
		(ObjectEffectService :: any)._grantChestReward(a, ctx)
	end
	print(string.format("[ObjectEffectService] Cursed Chest | %s gains treasure", a.name))
	return true, nil
end

--------------------------------------------------------------------
-- HAZARD / TRIGGERED (also usable via Interact where applicable)
--------------------------------------------------------------------
Handlers["Bear Trap"] = function(ctx: any): (boolean, any)
	applyAndRebuild(ctx.actor, "Pinned", ctx.actor.id)
	print("[ObjectEffectService] Bear Trap | Pinned applied")
	return true, nil
end

Handlers["Snare Trap"] = function(ctx: any): (boolean, any)
	applyAndRebuild(ctx.actor, "Pinned", ctx.actor.id)
	-- AC-012 Trapmaker's Roll: x1.20 RT delay on a trap placed by the wearer (inst.trapPowerMult).
	local _snareRt = math.round(150 * ((ctx.objInstance and ctx.objInstance.trapPowerMult) or 1))
	ctx.actor.remainingRt = (ctx.actor.remainingRt or 0) + _snareRt
	print(string.format("[ObjectEffectService] Snare Trap | Pinned + %d RT Delay", _snareRt))
	return true, nil
end

-- Poison Trap (2026-10-25): authored effect = Poison debuff + Venom (Strength 2) + RT Delay
-- on the enemy that springs it. Venom reapply stacks Strength +1 (StatusService), so applying
-- it `venomStrength` times reaches the authored Strength 2. RT delay + Venom strength are read
-- off the ObjectData def (authored numbers; no hardcode). Enemy-only trigger + consume-once are
-- handled upstream by TriggerTrap (ownerSide gate + uses="Once").
-- Stasis Trap Emitter (DEP-007, 2026-10-26): RT Delay = round(rtDelayFlat + rtDelayPerIL*IL)
-- to EVERY enemy of the trap's owner within effectRadius of the trap tile (not only the unit
-- that sprang it). IL = the placing unit's level. Each target's VIT / gear RT-delay resistance
-- applies through GameConstants.CalcRtDelayResistance (same as item and push RT delays).
-- Numbers are read off the ObjectData def. Enemy-only trigger + consume-once: TriggerTrap.
Handlers["Stasis Trap Emitter"] = function(ctx: any): (boolean, any)
	local obj, def = ctx.objInstance, ctx.objDef or {}
	local owner = nil
	for _, u in ipairs(ctx.allUnits or {}) do
		if u.id == obj.casterId then owner = u break end
	end
	local IL = (owner and owner.level) or 1
	local raw = math.round(((def.rtDelayFlat or 0) + (def.rtDelayPerIL or 0) * IL) * (obj.trapPowerMult or 1))  -- AC-012
	local r = def.effectRadius or 1
	local cx, cy = obj.x or ctx.actor.tileX, obj.y or ctx.actor.tileY
	local hit = 0
	for _, u in ipairs(ctx.allUnits or {}) do
		local hostile = (obj.ownerSide == nil) or (u.side ~= obj.ownerSide)
		if u.isAlive and hostile and u.tileX
			and math.max(math.abs(u.tileX - cx), math.abs(u.tileY - cy)) <= r then
			local vit = (u.effectiveStats and u.effectiveStats.VIT) or 10
			local gear = (u.gearDerived and u.gearDerived.rtDelayResist) or 1
			local d = math.max(0, GameConstants.CalcRtDelayResistance(raw, vit, gear))
			u.remainingRt = (u.remainingRt or 0) + d
			if BattleVisualBroadcaster and BattleVisualBroadcaster.UnitStateChanged then
				BattleVisualBroadcaster.UnitStateChanged(u)
			end
			hit += 1
		end
	end
	print(string.format("[ObjectEffectService] Stasis Trap | raw RT Delay %d to %d enemy(ies) around (%s,%s)",
		raw, hit, tostring(cx), tostring(cy)))
	return true, nil
end

Handlers["Poison Trap"] = function(ctx: any): (boolean, any)
	local a = ctx.actor
	applyAndRebuild(a, "Poison", a.id)
	local vStrength = (ctx.objDef and ctx.objDef.venomStrength) or 2
	for _ = 1, vStrength do
		applyAndRebuild(a, "Venom", a.id)
	end
	local rtDelay = (ctx.objDef and ctx.objDef.rtDelay) or 30
	a.remainingRt = (a.remainingRt or 0) + rtDelay
	print(string.format("[ObjectEffectService] Poison Trap | Poison + Venom(str %d) + %d RT on %s",
		vStrength, rtDelay, tostring(a.name)))
	return true, nil
end

Handlers["Spike Trap"] = function(ctx: any): (boolean, any)
	-- Physical damage + Bleed. Damage via direct HP (environmental, no attacker stats).
	local a = ctx.actor
	-- Damage % is the authoritative DB value (ObjectData Spike Trap damagePct); no hardcode.
	local pct = (ctx.objDef and ctx.objDef.damagePct) or 0.10
	local dmg = math.floor((a.maxHp or 0) * pct)
	dmg = math.round(dmg * hazardTakenMult(a))  -- Goblin Cunning (trap)
	local _shown0 = GameConstants.CapUnitDamage(a, dmg)  -- 1 for a 3-hit gadget
	a.currentHp = math.max(0, (a.currentHp or 0) - _shown0)
	applyAndRebuild(a, "Bleed", a.id)
	if BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectDamage and a.tileX and a.tileY then
		BattleVisualBroadcaster.ObjectDamage(a.tileX, a.tileY, _shown0, true)
	end
	print(string.format("[ObjectEffectService] Spike Trap | %d dmg + Bleed", dmg))
	return true, nil
end

local function explosionHandler(label: any)
	return function(ctx: any): (boolean, any)
		local a, obj = ctx.actor, ctx.objInstance
		local x = obj.x or a.tileX
		local y = obj.y or a.tileY
		if _tileEffectService and _tileEffectService.QueueExplosion then
			-- Consume the exploding object BEFORE its blast resolves (Studio sweep 2026-11-06): the blast
			-- runs immediately, so a Land Mine still on its tile was re-detonated by a chained Bomb
			-- Barrel blast (one mine exploded twice: 36 + 9 on the same unit). Only the live object of
			-- this type on this tile is removed; the callers' later removal is then a harmless no-op.
			if ctx.state and ctx.state.objects and obj and obj.id then
				for _, o in ipairs(ctx.state.objects) do
					if o.id == obj.id and o.type == label then
						ObjectEffectService.RemoveObjectInstance(ctx.state, o)
						if BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectChanged then
							BattleVisualBroadcaster.ObjectChanged(o.x, o.y, { destroyed = true })
						end
						break
					end
				end
			end
			-- 25% Max HP, 3x3 box per-source (objects_encounters). QueueExplosion
			-- expects a NUMERIC fraction payload (processOneExplosion computes
			-- payload * reduction^depth); passing a table errored at "damagePayload > 0".
			-- (Fix bundled with the trap-trigger wiring that first exercises this path.)
			-- Instigator (2026-10-28): the acting unit (Bomb Barrel set off / Pandora opener).
			-- QueueExplosion drops it for a trap blast (Land Mine), so traps never count.
			-- AC-012 Trapmaker's Roll: a Land Mine placed by the wearer blasts for 25% x 1.20 = 30%.
			_tileEffectService.QueueExplosion(x, y, 0, a.id, 0.25 * ((obj and obj.trapPowerMult) or 1), ctx.allUnits, "box",
				(ctx.objDef ~= nil and objHasTag(ctx.objDef, "Trap")) or label == "Land Mine",  -- Goblin: trap blast
				a and a.id or nil)
			print(string.format("[ObjectEffectService] %s | explosion queued at (%d,%d)", label, x, y))
			return true, nil
		end
		return false, label .. ": TileEffectService not available."
	end
end
Handlers["Land Mine"]   = explosionHandler("Land Mine")
Handlers["Bomb Barrel"] = explosionHandler("Bomb Barrel")

local function tileEffectHandler(effectId: any, label: any)
	return function(ctx: any): (boolean, any)
		local a, obj = ctx.actor, ctx.objInstance
		local cx = obj.x or a.tileX
		local cy = obj.y or a.tileY
		if not (_tileEffectService and _tileEffectService.ApplyTileEffect) then
			return false, label .. ": TileEffectService not available."
		end
		local n = 0
		for dx = -2, 2 do
			for dy = -2, 2 do
				_tileEffectService.ApplyTileEffect(cx + dx, cy + dy, effectId, a.id, ctx.allUnits)
				n = n + 1
			end
		end
		print(string.format("[ObjectEffectService] %s | %s over %d tiles (R2) at (%d,%d)", label, effectId, n, cx, cy))
		return true, nil
	end
end
Handlers["Oil Sluice"]  = tileEffectHandler("Tar Pit", "Oil Sluice")
Handlers["Steam Valve"] = tileEffectHandler("Steam", "Steam Valve")

--------------------------------------------------------------------
-- LOOT
--------------------------------------------------------------------
Handlers["Treasure Chest"] = function(ctx: any): (boolean, any)
	if (ObjectEffectService :: any)._grantChestReward then
		return (ObjectEffectService :: any)._grantChestReward(ctx.actor, ctx)
	end
	print("[ObjectEffectService] Treasure Chest | reward hook not wired (follow-up)")
	return true, nil
end

--------------------------------------------------------------------
-- EYE OF THE MAGI — attack two random opponents for 40% of their OWN max HP.
-- Direct HP%-damage (no weapon/operator stats). Deterministic pick via ctx.rng.
--------------------------------------------------------------------
Handlers["Eye of the Magi"] = function(ctx: any): (boolean, any)
	local a = ctx.actor
	local enemies = livingEnemies(a, ctx.allUnits)
	if #enemies == 0 then
		print("[ObjectEffectService] Eye of the Magi | no living opponents")
		return true, nil
	end
	-- Pick up to two distinct random targets deterministically.
	local picks = {}
	local pool = {}
	for _, e in ipairs(enemies) do table.insert(pool, e) end
	local count = math.min(2, #pool)
	for _ = 1, count do
		local idx = ctx.rng:NextInteger(1, #pool)
		table.insert(picks, pool[idx])
		table.remove(pool, idx)
	end
	local _eyeFocusDone = false
	for _, tgt in ipairs(picks) do
		local dmg = math.floor((tgt.maxHp or 0) * 0.40)
		local _shown1 = GameConstants.CapUnitDamage(tgt, dmg)  -- 1 for a 3-hit gadget
		tgt.currentHp = math.max(0, (tgt.currentHp or 0) - _shown1)
		markHunterAttacked(tgt, a, _shown1)  -- Treasure Hunter: operator set the Eye off
		if tgt.currentHp <= 0 then tgt.isAlive = false end
		if BattleVisualBroadcaster then BattleVisualBroadcaster.UnitStateChanged(tgt) end
		if BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectDamage and tgt.tileX and tgt.tileY then
			local _f = not _eyeFocusDone; _eyeFocusDone = true
			BattleVisualBroadcaster.ObjectDamage(tgt.tileX, tgt.tileY, _shown1, _f)
		end
		print(string.format("[ObjectEffectService] Eye of the Magi | %s takes %d (40%% own MaxHP)", tgt.name, dmg))
	end
	return true, nil
end

--------------------------------------------------------------------
-- SIEGE WEAPONS — Ballista (penetrating bolt 250% weapon dmg, cardinal) and
-- Catapult (projectile 200% weapon dmg, Cross AOE, range 6). First functional
-- build: deterministic AUTO-TARGET the nearest living enemy (full interactive
-- direction/target-pick UI is a follow-up). Damage via CombatResolver using the
-- OPERATOR's stats + a derived weaponDamage (objects_encounters: "uses operator
-- stats"). Both are "Once per turn" -> the usage ledger (ClearTurnUsage at turn
-- start) gates reuse.
--------------------------------------------------------------------
local function nearestEnemy(a: any, allUnits: any)
	local best, bestD = nil, math.huge
	for _, u in ipairs(allUnits) do
		if u.isAlive and u.side ~= a.side and not u.isGroundTarget and u.tileX and u.tileY then
			local d = math.abs(u.tileX - a.tileX) + math.abs(u.tileY - a.tileY)
			if d < bestD then best, bestD = u, d end
		end
	end
	return best, bestD
end

-- Apply a CombatResolver outcome to a siege target. ResolveBasicAttack returns
-- EITHER a Damage shape { finalDamage } OR a Healing shape { finalHealing }
-- (Dark-weapon operator vs an Undead target converts the hit to healing).
-- Handle BOTH so a Dark-vs-Undead siege shot is not silently dropped (DEFECT-2).
-- cause (optional, rules 225): siege object's DISPLAY name, so a hit resolved after a
-- deferred tile prompt (outside Resolve's SetCause scope) is still labelled.
-- attacker (optional, rules 230): the siege operator unit, so a siege hit on the
-- Treasure Hunter counts as being attacked (user ruling 2026-10-28).
local function applySiegeOutcome(target: any, outcome: any, focusState: any, cause: any, attacker: any)
	cause = cause or (BattleVisualBroadcaster and BattleVisualBroadcaster.GetCause and BattleVisualBroadcaster.GetCause())
	if not outcome then return end
	if outcome.finalDamage then
		local _shown2 = GameConstants.CapUnitDamage(target, outcome.finalDamage)  -- 1 for a 3-hit gadget
		target.currentHp = math.max(0, (target.currentHp or 0) - _shown2)
		if target.currentHp <= 0 then target.isAlive = false end
		-- Treasure Hunter (project_rules 230): a Ballista/Catapult hit counts as being
		-- attacked -> it stops hunting and tries to escape. Same rule as CombatResolver.ApplyOutcome.
		if target.eventName == "Treasure Hunter" and attacker and attacker ~= target
			and (_shown2 or 0) > 0 and not target.hunterAttacked then
			target.hunterAttacked = true
		end
		-- Damage feedback (2026-10-26): floating number + impact flash on the target
		-- tile, and a camera pan to the FIRST unit hit this interaction. focusState is
		-- an optional { done } tracker the caller passes once per interaction so only
		-- the first hit grabs the camera (mirrors attack/skill focus).
		if BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectDamage and target.tileX and target.tileY then
			local _focus = (focusState ~= nil) and (focusState.done ~= true)
			if _focus then focusState.done = true end
			BattleVisualBroadcaster.ObjectDamage(target.tileX, target.tileY, _shown2, _focus, cause)
		end
	elseif outcome.finalHealing then
		-- Festering Wound anti-heal (2026-10-25): object-sourced heals (Healing/Magic Spring,
		-- Blood Fountain, etc.) reduced too.
		local _heal = outcome.finalHealing
		local _hrm = StatusService.GetHealingReceivedMult(target)
		if _hrm ~= 1 then _heal = math.max(0, math.floor(_heal * _hrm)) end
		local _hpBefore = target.currentHp or 0
		target.currentHp = math.min(target.maxHp or (target.currentHp or 0),
			(target.currentHp or 0) + _heal)
		if (target.currentHp or 0) > _hpBefore then StatusService.WeakenVenomOnHeal(target) end  -- healing weakens Venom (2026-10-26)
	else
		return
	end
	if BattleVisualBroadcaster then BattleVisualBroadcaster.UnitStateChanged(target, cause) end
end

-- SIEGE RAY AIM (shared by the map Ballista and the Portable Ballista, user ruling 2026-10-27).
-- Builds the 8 straight rays from (ox, oy). Only tiles minStep..maxStep steps out are on a ray
-- (maxStep nil = to the map edge). unitAt maps "x,y" -> the living unit there (friendly fire:
-- every unit, ally or enemy). Returns rays[dir] = { {x, y, unit}, ... } in order from the
-- Ballista outward, the flat tile list for the tile prompter ({x, y, hit}), and tile -> dir.
local SIEGE_DIR8 = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local function siegeRays(ox: number, oy: number, unitAt: any, minStep: number?, maxStep: number?): (any, any, any)
	local grid = GameConstants.TERRAIN_MAP
	local h = grid and #grid or 0
	local w = (h > 0 and grid[1]) and #grid[1] or 0
	local rays, flat, keyDir = {}, {}, {}
	for _, d in ipairs(SIEGE_DIR8) do
		local v = GameConstants.FACING_VECTORS[d]
		local list = {}
		if v then
			local step = 1
			local rx, ry = ox + v.dx, oy + v.dy
			while rx >= 1 and rx <= w and ry >= 1 and ry <= h and (maxStep == nil or step <= maxStep) do
				if step >= (minStep or 1) then
					local k = rx .. "," .. ry
					list[#list + 1] = { x = rx, y = ry, unit = unitAt[k] }
					if not keyDir[k] then
						keyDir[k] = d
						flat[#flat + 1] = { x = rx, y = ry, hit = unitAt[k] ~= nil }
					end
				end
				rx = rx + v.dx
				ry = ry + v.dy
				step = step + 1
			end
		end
		rays[d] = list
	end
	return rays, flat, keyDir
end
-- Ask a PLAYER-controlled operator to tap a tile on one of the rays. Returns the ray direction,
-- "CANCEL" (the player tapped Cancel), or nil (AI operator, no prompter, or no valid tap).
local function promptSiegeRay(a: any, ox: number, oy: number, range: number, flat: any, keyDir: any): any
	if not (_tilePrompter and a and a.controller == "Player") or #flat == 0 then return nil end
	local picked = _tilePrompter(a, ox, oy, range, flat)
	if picked == "CANCEL" then return "CANCEL" end
	if type(picked) == "table" then
		return keyDir[(picked.x or -1) .. "," .. (picked.y or -1)]
	end
	return nil
end

-- SIEGE DAMAGE (USER RULING 2026-10-30 6:20 PM, project_rules 242; objects_encounters 11 Ballista,
-- 12 Catapult). Siege Power = 48 + 1.9 x operator level, x (1 + DEX / (DEX + 200)) (DEX is the siege
-- booster, max x2). The operator's weapon damage and STR are NOT used. share = 1 (Ballista) or 0.70
-- (Catapult, per unit hit). CombatResolver then runs the normal defense pipeline with no hit-quality
-- step (opts.isSiege). Portable Ballista keeps its own formula.
-- USER RULING 2026-10-30 6:34 PM: the Siege Gunner Helm (+25%) is no longer in Siege Power - it ADDS
-- to the height modifier instead of multiplying (see siegeOpts / CombatResolver).
local function siegePower(a: any, share: number): number
	local lvl = tonumber(a and a.level) or 1
	local dex = math.max(0, tonumber(a and a.effectiveStats and a.effectiveStats.DEX) or 0)
	return math.max(1, math.floor((48 + 1.9 * lvl) * (1 + dex / (dex + 200)) * share))
end

-- Options for a siege shot through CombatResolver.ResolveBasicAttack (USER RULING 2026-10-30 6:34 PM):
-- the height modifier is measured from the SIEGE OBJECT's tile (originX/originY), and the Helm's +25%
-- is added to that height modifier (siegeBonus) instead of multiplying it.
local function siegeOpts(a: any, ox: number, oy: number): any
	local helm = (require :: any)(script.Parent.ArmorPassiveService).GetInteractSiegeDamageModifier(a) or 1
	return { isSiege = true, originX = ox, originY = oy, siegeBonus = helm - 1 }
end

-- Elevation for the siege height rules. USER RULING 2026-10-30 6:34 PM: for siege shots a flying unit
-- counts as the height of the ground beneath it (Flight's +5 is ignored here only).
local function siegeElev(u: any): number
	return GameConstants.GetElevation(u.tileX, u.tileY) or 0
end

-- TargetingService requires this module, so it is required lazily at call time (no load cycle).
local function siegeTargeting(): any
	return (require :: any)(script.Parent.TargetingService)
end

Handlers["Ballista"] = function(ctx: any): (boolean, any)
	local a = ctx.actor
	-- Siege Power, full shot to every unit hit (rule 242; replaces 250% weapon + level, 2026-10-26).
	-- Unbounded line, so the siege RANGE bonus does not apply here (Catapult only).
	local wd = siegePower(a, 1)

	-- Fire origin = the Ballista's own tile; the bolt pierces EVERY enemy along a
	-- straight line. 8-direction aim (user ruling 2026-10-26: was cardinal-only; now
	-- includes the 4 diagonals).
	local obj = ctx.objInstance
	local ox = (obj and obj.x) or a.tileX
	local oy = (obj and obj.y) or a.tileY

	local grid = GameConstants.TERRAIN_MAP
	local h = grid and #grid or 0
	local w = (h > 0 and grid[1]) and #grid[1] or 0

	-- Index ALL living units by tile (friendly fire ON for the map Ballista, user
	-- ruling 2026-10-26): the bolt damages whoever is on the line, ALLY OR ENEMY.
	-- Occupied tiles are flagged (hit=true) so the aim preview also warns about
	-- friendly units standing in the bolt's path.
	-- DIRECT PIERCING BOLT (USER RULING 2026-10-30 6:20 PM, objects_encounters 11): a unit on the line
	-- is hit only if (a) it is within 3 elevation levels of the Ballista tile (flight-aware), (b) it is
	-- at least 2 tiles away (direct-projectile minimum range), and (c) the straight path from the
	-- Ballista to it is not blocked by walls / sight-blocking objects (TargetingService.HasLineOfSight,
	-- Direct, with NO unit list: units never stop the bolt - it pierces). Only valid targets are
	-- indexed, so the aim preview flags exactly the units that will be hit.
	local _ts = siegeTargeting()
	local oElev = GameConstants.GetElevation(ox, oy) or 0
	local enemyAt = {}
	for _, u in ipairs(ctx.allUnits) do
		if u.isAlive and not u.isGroundTarget and u.tileX and u.tileY then
			local dist = math.max(math.abs(u.tileX - ox), math.abs(u.tileY - oy))
			if dist >= 2 and math.abs(siegeElev(u) - oElev) <= 3
				and _ts.HasLineOfSight(ox, oy, u.tileX, u.tileY, nil, oElev, "Direct", nil) then
				enemyAt[u.tileX .. "," .. u.tileY] = u
			end
		end
	end

	-- Build the 8 straight rays from the Ballista out to the map edge (shared siege ray aim,
	-- 2026-10-27). The player taps any tile on a ray to fire down that ray; occupied tiles are
	-- flagged (hit=true) so the client paints them in a hit color. AI/headless (no tile prompt)
	-- falls back to nearest-enemy. Rays start 2 tiles out (minimum range 2, rule 242).
	local rays, rayTiles, rayDir = siegeRays(ox, oy, enemyAt, 2, nil)
	local pick = promptSiegeRay(a, ox, oy, math.max(w, h), rayTiles, rayDir)
	-- Player tapped Cancel during targeting: abort with no effect. Resolve does not consume the
	-- object on a false return, and the command layer refunds the AP/RT it charged so the turn
	-- is given back intact (clean cancel).
	if pick == "CANCEL" then return false, "CANCELLED" end
	local dir = pick
	if not dir then
		local tgt: any = nearestEnemy(a, ctx.allUnits)
		if not tgt then return true, nil end
		local dx, dy = tgt.tileX - ox, tgt.tileY - oy
		if math.abs(dx) >= math.abs(dy) then
			dir = (dx >= 0) and "E" or "W"
		else
			dir = (dy >= 0) and "S" or "N"
		end
	end
	if not rays[dir] then dir = "S" end

	local hits = 0
	local focusState = { done = false }
	for _, tile in ipairs(rays[dir]) do
		local u = tile.unit
		if u and CombatResolver and CombatResolver.ResolveBasicAttack then
			local outcome = CombatResolver.ResolveBasicAttack(a, u, wd, siegeOpts(a, ox, oy))
			applySiegeOutcome(u, outcome, focusState, ObjectEffectService.GetDisplayType(ctx.objInstance, "Ballista"), a)
			-- Objective "Siege Operator": a siege KO is tagged + credited to operator.
			if not u.isAlive then u._killCause = u._killCause or "siege"; u._killedBy = u._killedBy or a.id end
			print(string.format("[ObjectEffectService] Ballista | dealt %d to %s at (%d,%d)",
				(outcome and outcome.finalDamage) or 0, tostring(u.name), tile.x, tile.y))
			hits = hits + 1
		end
	end

	print(string.format("[ObjectEffectService] Ballista | %s fires %s bolt from (%d,%d): %d hit(s) (siege power %d)",
		a.name, dir, ox, oy, hits, wd))
	return true, nil
end

-- PORTABLE BALLISTA (DEP-015). User ruling 2026-10-27: works like the map Ballista through the
-- shared siege ray aim -- 8 straight rays from the Ballista's OWN tile; the operator taps a tile
-- and the bolt pierces EVERY unit on that ray, ally or enemy (friendly fire ON). Only tiles 3-7
-- steps out (+ HD siege range bonus) are on a ray. Power was fixed at placement
-- (inst.shotPower, 50 + 0.90*IL + 0.60*DEX of the placer); the operator is the attacker
-- (rule 177), so Defense, element rules and wards apply through the item hit pipeline; HD
-- siege headgear multiplies the power. Cancel = clean cancel (nothing spent). No enemy on any
-- ray -> clean cancel. Removed after its last shot (2 shots).
Handlers["Portable Ballista"] = function(ctx: any): (boolean, any)
	local a, obj, def = ctx.actor, ctx.objInstance, ctx.objDef or {}
	-- The command layer passes a reconstructed {id,type,x,y}; read the LIVE instance.
	local live = nil
	for _, o in ipairs((ctx.state and ctx.state.objects) or {}) do
		if o.id == obj.id then live = o break end
	end
	if not live or not live.shotPower then
		return false, "CANCELLED"
	end
	local _siege = (require :: any)(script.Parent.ArmorPassiveService)
	local rMin = def.rangeMin or 1
	local rMax = (def.rangeMax or 1) + (_siege.GetInteractSiegeRangeBonus(a) or 0)
	local ox, oy = live.x, live.y
	local unitAt = {}
	for _, u in ipairs(ctx.allUnits or {}) do
		if u.isAlive and not u.isGroundTarget and u.tileX and u.tileY then
			unitAt[u.tileX .. "," .. u.tileY] = u
		end
	end
	local rays, flat, keyDir = siegeRays(ox, oy, unitAt, rMin, rMax)
	local function isFoe(u: any): boolean
		return u.side ~= a.side and u.side ~= "Neutral"
	end
	local anyFoe = false
	for _, d in ipairs(SIEGE_DIR8) do
		for _, tile in ipairs(rays[d]) do
			if tile.unit and isFoe(tile.unit) then anyFoe = true break end
		end
		if anyFoe then break end
	end
	if not anyFoe then
		print("[ObjectEffectService] Portable Ballista | no enemy on any line 3-7 tiles out")
		return false, "CANCELLED"
	end
	local pick = promptSiegeRay(a, ox, oy, rMax, flat, keyDir)
	if pick == "CANCEL" then return false, "CANCELLED" end
	local dir = pick
	if not dir then
		-- AI operator / no tap: the line with the most enemies, then the fewest allies (8-way
		-- order breaks ties). A line that would hit as many allies as enemies is never chosen.
		local bestFoes, bestFriends = 0, math.huge
		for _, d in ipairs(SIEGE_DIR8) do
			local foes, friends = 0, 0
			for _, tile in ipairs(rays[d]) do
				local u = tile.unit
				if u then
					if isFoe(u) then foes += 1 elseif u.side == a.side then friends += 1 end
				end
			end
			if foes > friends and (foes > bestFoes or (foes == bestFoes and friends < bestFriends)) then
				dir, bestFoes, bestFriends = d, foes, friends
			end
		end
		if not dir then return false, "CANCELLED" end
	end
	local power = math.max(1, math.round(live.shotPower * (_siege.GetInteractSiegeDamageModifier(a) or 1)))
	local _ies = (require :: any)(script.Parent.ItemEffectService)
	local hits = 0
	for _, tile in ipairs(rays[dir]) do
		local u = tile.unit
		if u and u.isAlive then
			local dealt = _ies.ResolveTimedHit(a, u, "Physical", power, "Portable Ballista")
			if not u.isAlive then u._killCause = u._killCause or "siege"; u._killedBy = u._killedBy or a.id end
			hits += 1
			print(string.format("[ObjectEffectService] Portable Ballista | %s's bolt hits %s at (%d,%d): %d dmg",
				tostring(a.name), tostring(u.name), tile.x, tile.y, dealt or 0))
		end
	end
	live.shotsLeft = (live.shotsLeft or 1) - 1
	print(string.format("[ObjectEffectService] Portable Ballista | %s fires %s from (%d,%d): %d hit(s) | shots left %d",
		tostring(a.name), tostring(dir), ox, oy, hits, live.shotsLeft))
	if live.shotsLeft <= 0 then
		ObjectEffectService.RemoveObjectInstance(ctx.state, live)
		if BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectChanged then
			BattleVisualBroadcaster.ObjectChanged(ox, oy, { destroyed = true })
		end
	end
	return true, nil
end

-- SUPPLY STATION (DEP-010, 2026-10-26, user-approved): an allied unit next to it Interacts
-- once (per unit, per station) to restore 1 charge to ONE of its items: the one missing the
-- most charges (ties: first slot). The Supply Station item itself is never refilled. Holds
-- inst.supplies (3); removed when they run out. Nothing to refill -> clean cancel.
Handlers["Supply Station"] = function(ctx: any): (boolean, any)
	local a, obj, def = ctx.actor, ctx.objInstance, ctx.objDef or {}
	local live = nil
	for _, o in ipairs((ctx.state and ctx.state.objects) or {}) do
		if o.id == obj.id then live = o break end
	end
	if not live or (live.supplies or 0) <= 0 then return false, "CANCELLED" end
	live.usedBy = live.usedBy or {}
	if live.usedBy[a.id] then return false, "CANCELLED" end
	local best, bestMiss = nil, 0
	for _, s in ipairs(a.consumableSlots or {}) do
		if s.consumableId and s.consumableId ~= "" and s.consumableId ~= def.sourceConsumableId then
			local miss = (s.maxCharges or 0) - (s.currentCharges or 0)
			if miss > bestMiss then best, bestMiss = s, miss end
		end
	end
	if not best then
		print(string.format("[ObjectEffectService] Supply Station | %s has no item missing a charge", tostring(a.name)))
		return false, "CANCELLED"
	end
	best.currentCharges = (best.currentCharges or 0) + 1
	live.usedBy[a.id] = true
	live.supplies -= 1
	if BattleVisualBroadcaster and BattleVisualBroadcaster.UnitStateChanged then
		BattleVisualBroadcaster.UnitStateChanged(a)
	end
	print(string.format("[ObjectEffectService] Supply Station | %s restored 1 charge of %s | supplies left %d",
		tostring(a.name), tostring(best.consumableId), live.supplies))
	if live.supplies <= 0 then
		ObjectEffectService.RemoveObjectInstance(ctx.state, live)
		if BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectChanged then
			BattleVisualBroadcaster.ObjectChanged(live.x, live.y, { destroyed = true })
		end
	end
	return true, nil
end

Handlers["Catapult"] = function(ctx: any): (boolean, any)
	local a = ctx.actor
	-- Cross AOE (center + 4 adjacents), range 2-6 from the Catapult (rule 242: ARC projectile).
	-- Damage = 70% of Siege Power per unit hit (replaces 200% weapon damage). HD siege headgear:
	-- damage x1.25 (inside siegePower) and range +2 (GetInteractSiegeRangeBonus).
	local _siege = (require :: any)(script.Parent.ArmorPassiveService)
	local wd = siegePower(a, 0.70)
	local RANGE = 6 + _siege.GetInteractSiegeRangeBonus(a)
	-- Fire origin = the Catapult's own tile (the siege engine), like the Ballista.
	local obj = ctx.objInstance
	local ox = (obj and obj.x) or a.tileX
	local oy = (obj and obj.y) or a.tileY

	-- Build the set of legal landing tiles: every on-map tile within Chebyshev
	-- range 6 of the Catapult. (Catapult lobs over obstacles — no LoS requirement,
	-- consistent with the prior nearest-enemy auto-target having no LoS check.)
	local grid = GameConstants.TERRAIN_MAP
	local h = grid and #grid or 0
	local w = (h > 0 and grid[1]) and #grid[1] or 0
	-- Index ALL living units by tile so the aim preview can flag occupied tiles
	-- (friendly fire ON, user ruling 2026-10-26: the Cross damages ally OR enemy).
	local unitAt = {}
	for _, u in ipairs(ctx.allUnits) do
		if u.isAlive and not u.isGroundTarget and u.tileX and u.tileY then
			unitAt[u.tileX .. "," .. u.tileY] = u
		end
	end
	-- ARC PROJECTILE (USER RULING 2026-10-30 6:20 PM, objects_encounters 12): a landing tile must be at
	-- least 2 tiles away (projectile minimum range) and pass the normal Arc check from the Catapult's
	-- tile (TargetingService.HasLineOfSight, Arc: never blocked by units or obstacles; the target must
	-- not be above the arc peak = Catapult tile elevation + 3). Only legal tiles are offered to aim.
	local _ts = siegeTargeting()
	local oElev = GameConstants.GetElevation(ox, oy) or 0
	local legal, legalKey = {}, {}
	for ty = math.max(1, oy - RANGE), math.min(h, oy + RANGE) do
		for tx = math.max(1, ox - RANGE), math.min(w, ox + RANGE) do
			-- No unit list: a flyer counts as its ground height for siege (USER RULING 2026-10-30 6:34 PM).
			if math.max(math.abs(tx - ox), math.abs(ty - oy)) >= 2
				and _ts.HasLineOfSight(ox, oy, tx, ty, nil, oElev, "Arc", nil) then
				legal[#legal + 1] = { x = tx, y = ty, hit = unitAt[tx .. "," .. ty] ~= nil }
				legalKey[tx .. "," .. ty] = true
			end
		end
	end

	-- Ask the player to pick a landing tile (reuses the object tile-prompt seam,
	-- the tile analogue of the Ballista's direction prompt). If no prompter is
	-- injected (AI/headless), fall back to auto-aim at the nearest enemy within
	-- range so the weapon still fires — same fallback philosophy as the Ballista.
	local cxTgt, cyTgt = nil, nil
	if _tilePrompter then
		local picked = _tilePrompter(a, ox, oy, RANGE, legal)
		-- Player tapped Cancel during targeting: abort with no effect (command layer
		-- refunds AP/RT for a clean cancel; Resolve won't consume on a false return).
		if picked == "CANCEL" then return false, "CANCELLED" end
		if picked and legalKey[(picked.x or -1) .. "," .. (picked.y or -1)] then
			cxTgt, cyTgt = picked.x, picked.y
		end
	end
	if not cxTgt then
		local tgt: any = nearestEnemy(a, ctx.allUnits)
		if not tgt then return true, nil end
		-- Auto-aim must obey the same range / minimum range / arc rules as the player's aim.
		if not legalKey[tgt.tileX .. "," .. tgt.tileY] then
			print("[ObjectEffectService] Catapult | no tile chosen and nearest enemy is not a legal landing tile")
			return true, nil
		end
		cxTgt, cyTgt = tgt.tileX, tgt.tileY
	end

	-- Cross centered on the chosen tile (center + 4 orthogonal adjacents).
	local crossTiles = { {cxTgt, cyTgt}, {cxTgt+1, cyTgt}, {cxTgt-1, cyTgt},
		{cxTgt, cyTgt+1}, {cxTgt, cyTgt-1} }
	-- CENTER SPREAD AOE (rule 242; movement_targeting 55/59/60): a cross tile is struck only if it is
	-- on the map, within +/-2 elevation of the impact tile, and the spread from the impact tile is not
	-- stopped by a BlocksAOE barrier (TargetingService.IsAOEBlocked).
	do
		local cElev = GameConstants.GetElevation(cxTgt, cyTgt) or 0
		local struck = {}
		for _, t in ipairs(crossTiles) do
			local tx, ty = t[1], t[2]
			if tx >= 1 and ty >= 1 and tx <= w and ty <= h
				and math.abs((GameConstants.GetElevation(tx, ty) or 0) - cElev) <= 2
				and not _ts.IsAOEBlocked(cxTgt, cyTgt, tx, ty) then
				struck[#struck + 1] = t
			end
		end
		crossTiles = struck
	end
	local hitN = 0
	-- First-hit camera focus tracker: declared BEFORE the loops so only the FIRST
	-- unit in the Cross grabs the camera (not every unit hit). (Fix 2026-10-26.)
	local _catFocus = { done = false }
	for _, u in ipairs(ctx.allUnits) do
		-- Friendly fire ON (user ruling 2026-10-26): the Cross hits ANY unit, ally
		-- or enemy, standing on a struck tile.
		if u.isAlive and not u.isGroundTarget then
			for _, t in ipairs(crossTiles) do
				if u.tileX == t[1] and u.tileY == t[2] then
					if CombatResolver and CombatResolver.ResolveBasicAttack then
						local outcome = CombatResolver.ResolveBasicAttack(a, u, wd, siegeOpts(a, ox, oy))
						applySiegeOutcome(u, outcome, _catFocus, ObjectEffectService.GetDisplayType(ctx.objInstance, "Catapult"), a)
						if not u.isAlive then u._killCause = u._killCause or "siege"; u._killedBy = u._killedBy or a.id end
					end
					hitN = hitN + 1
					break
				end
			end
		end
	end
	print(string.format("[ObjectEffectService] Catapult | %s splashes %d unit(s) around (%d,%d) (siege power %d per unit, Cross)", a.name, hitN, cxTgt, cyTgt, wd))
	return true, nil
end

--------------------------------------------------------------------
-- MID-BATTLE SUMMONS (Blocker #1) — spawn new units into the live battle via
-- EnemyGenerator.SpawnReinforcement, then broadcast UnitSpawned so clients
-- render them identically to battle-start units. Dragons use RACE-DRAGONKIN on
-- an Elite-tier build (no dedicated Dragon tier exists; Elite strength matches
-- the "high-risk encounter" intent). Spawn tiles: near the object.
--------------------------------------------------------------------
-- Average level of living enemies (fallback for summon level), min 1.
local function summonLevel(allUnits: any)
	local sum, n = 0, 0
	for _, u in ipairs(allUnits) do
		if u.side == "Enemy" and u.level then sum = sum + u.level; n = n + 1 end
	end
	if n == 0 then return 1 end
	return math.max(1, math.floor(sum / n))
end

-- Spread spawn tiles in a small ring around the object (keeps units from
-- stacking on one tile). Deterministic order.
-- Tiles within Chebyshev `radius` of (cx,cy), nearest-first (center first, then
-- ring 1, ring 2, ...). `radius` defaults to 1. Used by summons (place a handful
-- near the object) and by Forge (must reach radius 3 per objects_encounters).
-- Previously this only emitted magnitude-<=1 offsets, so Forge never probed
-- beyond radius 1 (Tester advisory, fixed).
local function ringTiles(cx: any, cy: any, count: any, radius: any)
	radius = radius or 1
	cx = cx or 1; cy = cy or 1
	local out = {}
	for r = 0, radius do
		for dx = -r, r do
			for dy = -r, r do
				-- Only the tiles whose Chebyshev distance == r (the new ring).
				if math.max(math.abs(dx), math.abs(dy)) == r then
					table.insert(out, { x = cx + dx, y = cy + dy })
					if count and #out >= count then return out end
				end
			end
		end
	end
	return out
end

local function doSummon(ctx: any, specType: any, countMin: any, countMax: any, side: any, raceOverride: any, label: any)
	local a, obj = ctx.actor, ctx.objInstance
	local lvl = summonLevel(ctx.allUnits)
	local count = countMin
	if countMax and countMax > countMin then
		count = ctx.rng:NextInteger(countMin, countMax)
	end
	local cx, cy = obj.x or a.tileX, obj.y or a.tileY
	local spawned = 0
	for k = 1, count do
		local tile = EnemyGenerator.FindNearestFreeSpawnTile(ctx.state, cx, cy, ctx.rng)
		if not tile then
			warn(string.format("[ObjectEffectService] %s | no free spawn tile for summon %d/%d", label, k, count))
			break
		end
		local unit = EnemyGenerator.SpawnReinforcement(
			{ type = specType, level = lvl }, tile, ctx.state, ctx.rng, side, raceOverride)
		if unit then
			spawned = spawned + 1
			-- Dragon Slayer objective: tag each Dragon-Utopia dragon and track the
			-- live count so the death-sweep can decrement it.
			if label == "Dragon Utopia" then
				unit.fromDragonUtopia = true
				ObjectiveService.RecordEvent(ctx.state, "dragonsAlive", 1)
			end
			-- Treasure Hunter (project_rules 229): a Mimic woken BY the Treasure Hunter hunts that
			-- NPC (AIService.isHostileTo narrow exception). It stays an enemy of the player too.
			if label == "Mimic" and a and a.eventName == "Treasure Hunter" and a.id then
				unit.huntsUnitId = a.id
			end
			if BattleVisualBroadcaster and BattleVisualBroadcaster.UnitSpawned then
				BattleVisualBroadcaster.UnitSpawned(unit)
			end
		end
	end
	print(string.format("[ObjectEffectService] %s | summoned %d unit(s) at L%d", label, spawned, lvl))
	if label == "Dragon Utopia" and spawned > 0 then
		ObjectiveService.RecordEvent(ctx.state, "dragonUtopiaTriggered", 1)
	end
	return true, nil
end

-- Dragon Utopia — summon 4-6 Dragons (Elite build, Dragonkin race).
Handlers["Dragon Utopia"] = function(ctx: any): (boolean, any)
	return doSummon(ctx, "Elite", 4, 6, "Enemy", "RACE-DRAGONKIN", "Dragon Utopia")
end

-- Mimic — reveal: the chest object is REPLACED by ONE Mimic enemy (Elite build)
-- on the chest's own tile. Remove the object (and its blocker) first so the tile
-- is free; doSummon's nearest-free search then lands on that tile.
Handlers["Mimic"] = function(ctx: any): (boolean, any)
	-- Treasure Fever (rules 224): a woken Mimic counts as a chest opened. This handler
	-- is the single wake path (interact AND WakeUnmasked both call it, then the object
	-- is removed/consumed), so it records exactly once per Mimic. No chest loot.
	-- Treasure Hunter (project_rules 234): a Mimic woken BY the Treasure Hunter does not count.
	if ctx.objInstance and ctx.objInstance.type == "Mimic"
		and not (ctx.actor and ctx.actor.eventName == "Treasure Hunter") then
		ObjectiveService.RecordEvent(ctx.state, "chestsOpened", 1)
	end
	ObjectEffectService.RemoveObjectInstance(ctx.state, ctx.objInstance)
	return doSummon(ctx, "Elite", 1, 1, "Enemy", nil, "Mimic")
end
_wakeHandler = Handlers["Mimic"]  -- attack-wake on an unmasked Mimic reuses this handler

-- Refugee Camp REMOVED from the catalog (objects_encounters DB row 7:
-- "Refugee Camp removed 2026-10-03; War Machine Factory renamed Forge"). No
-- ObjectData entry, no handler. The Neutral-side summon path remains available
-- via doSummon(..., "Neutral") / SpawnReinforcement for any future neutral summon.

--------------------------------------------------------------------
-- FORGE (DB objects_encounters 'Forge'; player choice built 2026-11-06, user: "db is correct").
-- "Summon one Ballista or Catapult on a chosen tile within radius 3 of the object."
-- Interact (Consumes Action), RT 150, Once, removed after use.
--   * Player unit: picks Ballista or Catapult (choice prompt, with Cancel), then picks a tile
--     from the server-built legal list (tile prompt, with Cancel). Either Cancel = clean cancel
--     (nothing spent, the Forge stays). Every answer is re-checked here (SEC-001/002).
--   * AI unit / no prompter: automatic pick, as before (random engine, nearest legal tile).
-- Legal tile: on the map, Chebyshev distance 1..3 from the Forge, no living unit, no wall or
-- other solid blocker, no visible non-trap object. A trap on the tile (either side, visible or
-- hidden) is replaced (user ruling 2026-10-27). Hidden objects are NOT used to filter the list,
-- so the list never gives a hidden object away; placement still settles them the normal way.
-- No legal tile: the player's Interact is cleanly cancelled; nothing is spawned (DB row 7:
-- "reason-coded failure without partial spawn").
--------------------------------------------------------------------
local FORGE_RADIUS = 3
local FORGE_ENGINES = { "Ballista", "Catapult" }

local function forgeLegalTiles(state: any, cx: number, cy: number, viewerSide: any): ({ any }, { [string]: boolean })
	local grid = GameConstants.TERRAIN_MAP
	local h = grid and #grid or 0
	local w = (h > 0 and grid[1]) and #grid[1] or 0
	local unitAt, visibleSolidObj = {}, {}
	for _, u in ipairs((state and state.units) or {}) do
		-- W1 (2026-11-06): a HIDDEN unit of another side is NOT used to filter the list, so the
		-- list never gives its position away. Picking that tile fails at placement (the engine
		-- can't go on a unit) and is refunded like any other blocked placement.
		local hiddenFoe = viewerSide ~= nil and u.side ~= viewerSide
			and StatusService.HasStatus and StatusService.HasStatus(u, "Hide")
		if u.isAlive and u.tileX and u.tileY and not hiddenFoe then unitAt[u.tileX .. "," .. u.tileY] = true end
	end
	for _, o in ipairs((state and state.objects) or {}) do
		local odef = o.type and ObjectData.Objects[o.type]
		if o.x and o.y and not o.hidden and not objHasTag(odef, "Trap") then
			visibleSolidObj[o.x .. "," .. o.y] = true
		end
	end
	local list, key = {}, {}
	for _, t in ipairs(ringTiles(cx, cy, nil, FORGE_RADIUS)) do
		local k = t.x .. "," .. t.y
		if not (t.x == cx and t.y == cy)
			and t.x >= 1 and t.y >= 1 and t.x <= w and t.y <= h
			and not unitAt[k] and not visibleSolidObj[k]
			and not (GameConstants.IsBlocked and GameConstants.IsBlocked(t.x, t.y))
			and not (GameConstants.IsImpassableTerrain and GameConstants.IsImpassableTerrain(t.x, t.y)) then
			table.insert(list, { x = t.x, y = t.y, hit = false })
			key[k] = true
		end
	end
	return list, key
end

Handlers["Forge"] = function(ctx: any): (boolean, any)
	local a, obj = ctx.actor, ctx.objInstance
	local cx, cy = obj.x or a.tileX, obj.y or a.tileY
	local legal, legalKey = forgeLegalTiles(ctx.state, cx, cy, a and a.side)
	local isPlayer = a and a.controller == "Player"
	if #legal == 0 then
		-- W2 (2026-11-06): reason-coded failure for EVERY controller (DB row 7: "Return
		-- reason-coded failure without partial spawn"). CANCELLED = CommandService refunds
		-- AP/RT and keeps the Forge; nothing is spent.
		print("[ObjectEffectService] Forge | FORGE_NO_LEGAL_TILE: no legal tile within radius 3 - nothing summoned, nothing spent")
		return false, "CANCELLED"
	end

	local which, tx, ty = nil, nil, nil
	if isPlayer and _choicePrompter and _tilePrompter then
		local opts = { "Ballista", "Catapult", "Cancel" }
		local pick = _choicePrompter(a, "Forge: summon which engine?", opts)
		if pick == "Ballista" or pick == "Catapult" then
			which = pick
		else
			print(string.format("[ObjectEffectService] Forge | %s cancelled the engine choice", tostring(a.name)))
			return false, "CANCELLED"
		end
		local picked = _tilePrompter(a, cx, cy, FORGE_RADIUS, legal)
		if picked == "CANCEL" or type(picked) ~= "table" then
			print(string.format("[ObjectEffectService] Forge | %s cancelled the tile choice", tostring(a.name)))
			return false, "CANCELLED"
		end
		if not legalKey[(picked.x or -1) .. "," .. (picked.y or -1)] then
			warn(string.format("[ObjectEffectService] Forge | rejected illegal tile (%s,%s) from %s",
				tostring(picked.x), tostring(picked.y), tostring(a.name)))
			return false, "CANCELLED"
		end
		tx, ty = picked.x, picked.y
	else
		-- Automatic pick (AI / headless): random engine, nearest legal tile (ring order).
		which = FORGE_ENGINES[ctx.rng:NextInteger(1, #FORGE_ENGINES)]
		tx, ty = legal[1].x, legal[1].y
	end

	-- User ruling 2026-10-27: the summoned engine replaces any trap on its tile.
	local inst = ObjectEffectService.PlaceObjectInstance(ctx.state, which, tx, ty, nil, nil, true)
	if not inst then
		-- Something the list could not show (e.g. a hidden unit) holds the tile.
		print(string.format("[ObjectEffectService] Forge | FORGE_TILE_OCCUPIED: %s could not be placed at (%d,%d) - refunded, Forge stays", which, tx, ty))
		if isPlayer and BattleVisualBroadcaster and BattleVisualBroadcaster.Log then
			BattleVisualBroadcaster.Log("action", "The Forge can't place an engine there - the tile is occupied.", a.id)
		end
		return false, "CANCELLED"
	end
	print(string.format("[ObjectEffectService] Forge | %s summons %s at (%d,%d)%s", tostring(a.name), which, tx, ty,
		(isPlayer and _choicePrompter and _tilePrompter) and " (player choice)" or " (auto)"))
	if BattleVisualBroadcaster and BattleVisualBroadcaster.Log then
		BattleVisualBroadcaster.Log("action", `The Forge summons a {which}.`, a.id)
	end
	return true, nil
end

--------------------------------------------------------------------
-- TAVERN (DB objects_encounters 'Tavern', user ruling 2026-11-06 12:23 PM).
-- Interact (Consumes Action), Once, removed after use. A PLAYER-side user marks this battle as
-- having earned the Tavern bonus: if the player WINS, the next guild Tavern refresh shows +3
-- recruit choices (GuildMenuService.OnBattleCompleted). It is a flag, so several Taverns in one
-- battle still give +3. Enemy/Neutral use does nothing (no recruit pool).
--------------------------------------------------------------------
Handlers["Tavern"] = function(ctx: any): (boolean, any)
	local a = ctx.actor
	if not (a and a.side == "Player") then
		print(string.format("[ObjectEffectService] Tavern | %s (%s) used it - no effect for this side",
			tostring(a and a.name), tostring(a and a.side)))
		return true, nil
	end
	local already = ctx.state and ctx.state.tavernBonusEarned == true
	if ctx.state then ctx.state.tavernBonusEarned = true end
	print(string.format("[ObjectEffectService] Tavern | %s secured the Tavern bonus%s (+3 recruit choices after a WIN)",
		tostring(a.name), already and " (already secured - does not stack)" or ""))
	if BattleVisualBroadcaster and BattleVisualBroadcaster.Log then
		BattleVisualBroadcaster.Log("action", already
			and "The Tavern bonus is already secured this battle (it does not stack)."
			or "Win this battle for +3 recruit choices at the next Tavern refresh.", a.id)
	end
	return true, nil
end

--------------------------------------------------------------------
-- STONE PILLAR (Blocker #3) — a standing 4-high pillar. On Interact it FALLS in
-- the direction OPPOSITE the interacting unit, becoming a 4-tile Rocky span at
-- the pillar base-tile elevation, crushing units on the tiles it reaches
-- (70% MaxHP HP%-based + 100 RT + Pinned). If a landing tile is 2+ levels higher
-- than the base, the fall stops short there (span ends on the previous tile).
-- (objects_encounters Stone Pillar, revised 2026-10-02.) Terrain/elevation are
-- mutated server-side (GameConstants) and the tile visuals updated via the
-- injected reshaper. The standing pillar's own tile is cleared (it fell).
--------------------------------------------------------------------
Handlers["Stone Pillar"] = function(ctx: any): (boolean, any)
	local a, obj = ctx.actor, ctx.objInstance
	local px, py = obj.x, obj.y
	if not (px and py) then return false, "Stone Pillar: no tile." end

	-- Fall direction = opposite the interacting unit (unit -> pillar, continue).
	local dx = px - (a.tileX or px)
	local dy = py - (a.tileY or py)
	-- Normalize to a cardinal step (favor the dominant axis; default +x).
	if math.abs(dx) >= math.abs(dy) then
		dx = (dx > 0) and 1 or (dx < 0 and -1 or 1); dy = 0
	else
		dy = (dy > 0) and 1 or -1; dx = 0
	end

	local baseElev = GameConstants.GetElevation(px, py)
	local FALL_LEN = 4

	-- Walk the span tiles; stop short if a tile is 2+ levels higher than base.
	local spanTiles = {}
	for step = 1, FALL_LEN do
		local tx, ty = px + dx * step, py + dy * step
		-- Map edge (Studio sweep 2026-11-06): GetElevation returns 1 off the grid, so a pillar near
		-- the edge "fell" onto off-map tiles (terrain/blocker writes + client re-skins for tiles that
		-- don't exist). The span stops at the edge, like it stops at a rise.
		local _row = GameConstants.ELEVATION_MAP[ty]
		if not (_row and _row[tx] ~= nil) then
			break
		end
		local tElev = GameConstants.GetElevation(tx, ty)
		if tElev - baseElev >= 2 then
			break  -- fall stops short at the rise
		end
		table.insert(spanTiles, { x = tx, y = ty })
	end

	-- Reshape each reached tile to Rocky at base elevation (the fallen deck), and
	-- crush any unit standing on it.
	local elevTilesChanged = 0
	for _, t in ipairs(spanTiles) do
		GameConstants.SetTerrainId(t.x, t.y, "Rocky")
		-- BUG-002 GAP 1 (2026-10-22): the fallen-deck Rocky reskin was a silent
		-- SetTerrainId (invisible mid-battle). Fire TerrainChanged via the directly-
		-- required BattleVisualBroadcaster (stable sibling) so the client re-skins the
		-- tile. Rocky is not a VOXEL_KEEP terrain, so no server voxel-clear is needed.
		-- nil-safe like the other broadcaster calls in this module.
		if BattleVisualBroadcaster and BattleVisualBroadcaster.TerrainChanged then
			BattleVisualBroadcaster.TerrainChanged(t.x, t.y, "Rocky")
		end
		if GameConstants.ELEVATION_MAP[t.y] then
			local oldElev = GameConstants.ELEVATION_MAP[t.y][t.x]
			GameConstants.ELEVATION_MAP[t.y][t.x] = baseElev
			if oldElev ~= baseElev then elevTilesChanged = elevTilesChanged + 1 end
		end
		-- The fallen pillar becomes a WALKABLE Rocky span: clear any blocker entry on
		-- each span tile (the pillar's own standing tile + the deck tiles) so units can
		-- cross it. Pairs with the N1 fix that made the standing pillar a real blocker.
		if GameConstants.RemoveBlockerAt then
			GameConstants.RemoveBlockerAt(t.x, t.y)
		end
		if _tileReshaper then
			_tileReshaper(t.x, t.y, "Rocky", baseElev)
		end
		-- Crush units on this tile.
		for _, u in ipairs(ctx.allUnits) do
			if u.isAlive and not u.isGroundTarget and u.tileX == t.x and u.tileY == t.y then
				local dmg = math.floor((u.maxHp or 0) * 0.70)  -- HP%-based
				local _shown3 = GameConstants.CapUnitDamage(u, dmg)  -- 1 for a 3-hit gadget
				u.currentHp = math.max(0, (u.currentHp or 0) - _shown3)
				markHunterAttacked(u, a, _shown3)  -- Treasure Hunter: a unit toppled the pillar
				if u.currentHp <= 0 then u.isAlive = false end
				u.remainingRt = (u.remainingRt or 0) + 100
				StatusService.ApplyStatus(u, "Pinned", a.id)
				if BattleVisualBroadcaster then BattleVisualBroadcaster.UnitStateChanged(u) end
				if BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectDamage and u.tileX and u.tileY then
					BattleVisualBroadcaster.ObjectDamage(u.tileX, u.tileY, _shown3, true)
				end
				print(string.format("[ObjectEffectService] Stone Pillar | crushed %s for %d (70%% MaxHP) +100 RT + Pinned", u.name, dmg))
			end
		end
	end

	-- The pillar fell: clear its standing-tile object AND its blocker entry so it no
	-- longer blocks movement/LoS (N1 made the standing pillar a real blocker).
	if GameConstants.RemoveBlockerAt then
		GameConstants.RemoveBlockerAt(px, py)
	end
	for idx, o in ipairs(ctx.state.objects) do
		if o.id == obj.id then
			table.remove(ctx.state.objects, idx)
			break
		end
	end
	-- Remove the standing pillar's model and clear its tile's object tag (Tester F2 2026-10-27:
	-- the old tile still showed "Stone Pillar" after it fell).
	if _objectVisualRemover then _objectVisualRemover(obj) end
	-- Also clear the server object map so GetObjectAt stops reporting the fallen pillar (Tester W2).
	if GameConstants.OBJECT_MAP and GameConstants.OBJECT_MAP[py] then
		GameConstants.OBJECT_MAP[py][px] = nil
	end

	print(string.format("[ObjectEffectService] Stone Pillar | fell %d tile(s) toward (%d,%d) as Rocky span", #spanTiles, dx, dy))
	-- Terrain Shaper objective: a PLAYER interacting with the pillar reshaped
	-- elevTilesChanged tiles' elevation. Player-initiated by definition (Interact).
	if elevTilesChanged > 0 and a and a.side == "Player" then
		ObjectiveService.RecordEvent(ctx.state, "elevationTilesChanged", elevTilesChanged)
	end
	return true, nil
end

--------------------------------------------------------------------
-- CHAOS STATUE (Blocker #4) — adds ONE in-battle optional objective to the live
-- battle via ObjectiveService.AddOne (CONVERTED 2026-10-24 by user ruling). It
-- no longer generates a future board-quest: optional objectives live and die
-- inside the current battle (fail-and-erase at battle end). Deterministic seed
-- from ctx.rng. Single use (ObjectData).
--------------------------------------------------------------------
Handlers["Chaos Statue"] = function(ctx: any): (boolean, any)
	local state = ctx.state
	-- CONVERTED 2026-10-24 (user ruling): the Chaos Statue no longer generates a
	-- future board-quest (which violated the "optional objectives live and die
	-- inside the current battle" rule). It now ADDS ONE in-battle optional
	-- objective to the live battle via ObjectiveService — rolled from the
	-- implemented pool, gated by the live battle context, fail-and-erase at
	-- battle end like every other optional objective. Single use (ObjectData).
	local rng = ctx.rng or Random.new(os.time())
	local added = ObjectiveService.AddOne(state, rng)
	if added then
		print(string.format("[ObjectEffectService] Chaos Statue | added in-battle optional objective '%s' (%s)",
			added.name, added.mode))
		-- Tell the player in the battle log what the new objective asks for (2026-10-28):
		-- same goal text as Map Details (ObjectiveService.Describe). Full progress +
		-- reward live in Map Details.
		local goal = nil
		for _, d in ipairs(ObjectiveService.Describe(state)) do
			if d.id == added.id then goal = d.goal; break end
		end
		if BattleVisualBroadcaster and BattleVisualBroadcaster.Log then
			BattleVisualBroadcaster.Log("action", string.format(
				"Chaos Statue reveals an optional objective: %s (%s)%s. See Map Details for progress and reward.",
				added.name, added.mode, goal and (" - " .. goal) or ""), ctx.actor and ctx.actor.id or nil)
		end
	else
		print("[ObjectEffectService] Chaos Statue | no eligible objective to add (all active or none applicable)")
	end
	return true, nil
end

--------------------------------------------------------------------
-- GLOW CRYSTAL (Slice 6 item 3, 2026-10-07; was PARKED on the XP system) —
-- objects_encounters: "Double all experience gained at end of battle." Uses: Once.
-- Sets a battle-level flag only; ProgressionService.AwardBattleXp applies the x2.
-- A flag (not a counter) so two crystals on one map still double XP ONCE.
-- Only a PLAYER-side activation counts (enemies never earn XP); an enemy that
-- interacts still consumes the crystal (denies it) with no effect.
--------------------------------------------------------------------
Handlers["Glow Crystal"] = function(ctx: any): (boolean, any)
	local state, actor = ctx.state, ctx.actor
	if not state then return false, "Glow Crystal: no battle state." end
	if actor and actor.side == "Player" then
		local already = state.glowCrystalActive == true
		state.glowCrystalActive = true
		print(string.format("[ObjectEffectService] Glow Crystal | %s activated — battle XP x2 at end of battle%s",
			tostring(actor.name), already and " (already active; no extra stacking)" or ""))
	else
		print(string.format("[ObjectEffectService] Glow Crystal | consumed by non-player %s — no XP effect",
			tostring(actor and actor.name)))
	end
	if BattleVisualBroadcaster and BattleVisualBroadcaster.UnitStateChanged and actor then
		BattleVisualBroadcaster.UnitStateChanged(actor)
	end
	return true, nil
end

--------------------------------------------------------------------
-- CRYSTAL BALL (Blocker #5) — reveals all hidden treasures/objects. The reveal
-- MECHANISM is built here: it scans state.objects, clears a `hidden` flag on
-- each, and renders any that were hidden. HONEST NOTE: no object in the current
-- content is flagged hidden (there is no hidden-content system yet), so this
-- reveals NOTHING today — it is inert-until-content, NOT faked. When hidden
-- objects/treasures are designed (they must carry obj.hidden = true and be
-- withheld from the initial render), this handler reveals them unchanged.
--------------------------------------------------------------------
-- Area reveal (2026-10-26, user ruling 5): clear `hidden` on objects whose tile is in
-- tileSet ({["x,y"]=true}) and render them. Shared by reveal consumables (Scanner Lens);
-- covers hidden traps today and hidden treasure / Mimic once that content exists.
-- revealerSide (optional, 2026-10-27): objects owned by the revealer's own side are skipped,
-- so an enemy scan never shows the player the enemy's own traps.
-- revealerName (optional, A2 2026-10-28): who/what revealed (unit or item/device name,
-- e.g. "Scanner Lens") -- used in the Mimic unmask log line.
function ObjectEffectService.RevealHiddenInArea(state: any, tileSet: any, revealerSide: any, revealerName: any): number
	local revealed = 0
	if state and state.objects and tileSet then
		for _, o in ipairs(state.objects) do
			if o.hidden and o.x and o.y and tileSet[o.x .. "," .. o.y]
				and not (revealerSide ~= nil and o.ownerSide == revealerSide) then
				if ObjectEffectService.RevealObject(o) then revealed += 1 end
			end
			-- Mimic disguise: a reveal in the area also unmasks it (stays dormant).
			if o.x and o.y and tileSet[o.x .. "," .. o.y] and ObjectEffectService.IsDisguised(o) then
				if ObjectEffectService.UnmaskObject(o, revealerName or "A reveal") then revealed += 1 end
			end
		end
	end
	return revealed
end

Handlers["Crystal Ball"] = function(ctx: any): (boolean, any)
	local state = ctx.state
	local revealed = 0
	-- Reveals never show a side its own traps (user ruling 2026-10-27): skip the user's side.
	local userSide = ctx.actor and ctx.actor.side
	if state and state.objects then
		for _, o in ipairs(state.objects) do
			if o.hidden and not (userSide ~= nil and o.ownerSide == userSide) then
				if ObjectEffectService.RevealObject(o) then revealed = revealed + 1 end
			end
			if ObjectEffectService.IsDisguised(o) then
				if ObjectEffectService.UnmaskObject(o, (ctx.actor and ctx.actor.name or "Someone") .. "'s Crystal Ball") then
					revealed = revealed + 1
				end
			end
		end
	end
	if revealed == 0 then
		print("[ObjectEffectService] Crystal Ball | no hidden objects to reveal (hidden-content system not built yet — mechanism is inert until it exists)")
	else
		print(string.format("[ObjectEffectService] Crystal Ball | revealed %d hidden object(s)", revealed))
	end
	return true, nil
end

--------------------------------------------------------------------
-- BLACK MARKET (v2 build step 6b, 2026-11-01; objects_encounters 31): a paid shop. Interacting
-- is free and repeatable; BlackMarketService rolls the 6-item stock once per object per battle
-- and opens the shop screen for a player unit. Buying goes through its own remote. (Replaces
-- the old free-cache stand-in, which never produced items: it passed no archetype pool.)
--------------------------------------------------------------------
Handlers["Black Market"] = function(ctx: any): (boolean, any)
	local ok, opened = pcall(function()
		return (require :: any)(script.Parent.BlackMarketService).Open(ctx.actor, ctx.objInstance, ctx.state)
	end)
	if not ok then
		warn("[ObjectEffectService] Black Market | shop failed to open: " .. tostring(opened))
	elseif not opened then
		warn("[ObjectEffectService] Black Market | shop could not open (see BlackMarketService log)")
	end
	return true, nil
end

--------------------------------------------------------------------
-- PASSIVE AURAS (War Banner, Cursed Statue) — reconcile on move/battle-start.
-- Each aura object declares the status it emits, its radius, and whether it is
-- two-sided. War Banner = allies-of-no-one (object has no side) so it buffs by
-- the aura rule: War Banner affects the PLAYER side (ally aura, by design);
-- Cursed Statue affects ALL units in radius (two-sided, 2026-10-03 ruling).
-- Reconcile adds the status to in-range units and removes it from those that
-- left range, source-tagged by the object instance id so overlapping auras do
-- not clobber each other.
--------------------------------------------------------------------
local AURA_OBJECTS = {
	["War Banner"]    = { status = "Banner Blessing", radius = 3, side = "Player" },
	["Cursed Statue"] = { status = "Cursed Aura",     radius = 3, side = "ALL" },
}

-- Track which units currently carry which aura source so we can remove cleanly.
-- _auraMembership[objId] = { [unitId] = true }
local _auraMembership = {}

-- Source-aware aura statuses (2026-10-30, aura fix). An aura-given instance is tagged
-- inst.auraSourceId = objId. It is "the aura's" only while inst.sourceUnitId still equals that
-- tag: any other source refreshing it (e.g. Buff-Blind granting Banner Blessing) takes it over,
-- so the aura ending no longer strips it. If the unit ALREADY had the status from another source
-- when the aura arrived, that source's remaining time is parked and handed back when the aura ends.
local function auraApply(u: any, auraDef: any, objId: any, state: any)
	local existing = StatusService.HasStatus(u, auraDef.status)
	local parked = nil
	if existing and not (existing.auraSourceId ~= nil and existing.sourceUnitId == existing.auraSourceId) then
		parked = { src = existing.sourceUnitId, ct = existing.remainingCt, turns = existing.remainingTurns,
			at = (state and state.ct) or 0 }
	elseif existing then
		parked = existing.parkedOther  -- overlapping aura: keep whatever was parked before
	end
	-- 2026-10-30 3:27 PM: apply here and broadcast AFTER the aura tag below (applyAndRebuild sent the
	-- client update before the tag, so the status card could not know it is "While in range").
	-- Same three steps as applyAndRebuild, in a different order.
	StatusService.ApplyStatus(u, auraDef.status, objId)
	local inst = StatusService.HasStatus(u, auraDef.status)
	-- Only tag the instance if this aura actually owns it now (an immune unit's apply is refused).
	if inst and inst.sourceUnitId == objId then
		inst.auraSourceId = objId
		inst.parkedOther = parked
		-- USER RULING 2026-10-30 (3:15 PM): an aura status lasts while the unit stays in range — no
		-- 1500 CT expiry. StatusService only counts down instances with a remainingCt. Any other
		-- source refreshing it (Buff-Blind) sets its own timer and takes it over; auraRemove hands
		-- back a parked timer or removes the status when the aura ends.
		inst.remainingCt = nil
		inst.remainingTurns = nil
	end
	if EquipmentService and EquipmentService.RebuildUnitStats then
		EquipmentService.RebuildUnitStats(u)
	end
	if BattleVisualBroadcaster and BattleVisualBroadcaster.UnitStateChanged then
		BattleVisualBroadcaster.UnitStateChanged(u)
	end
end

-- Ends the aura's hold on a unit's status. Returns true if the unit's status changed.
local function auraRemove(u: any, statusId: any, state: any): boolean
	local inst = StatusService.HasStatus(u, statusId)
	if not inst or inst.auraSourceId == nil then return false end
	if inst.sourceUnitId ~= inst.auraSourceId then
		-- Another source refreshed it since: it is theirs now; keep it, drop the stale tag.
		inst.auraSourceId = nil; inst.parkedOther = nil
		return false
	end
	local p = inst.parkedOther
	local elapsed = ((state and state.ct) or 0) - ((p and p.at) or 0)
	if p and ((p.ct ~= nil and p.ct - elapsed > 0) or (p.ct == nil and p.turns ~= nil)) then
		-- Hand the status back to the source it had before the aura arrived.
		inst.auraSourceId = nil; inst.parkedOther = nil
		inst.sourceUnitId = p.src
		inst.remainingCt = if p.ct ~= nil then p.ct - elapsed else inst.remainingCt
		inst.remainingTurns = p.turns
		return true
	end
	StatusService.RemoveStatus(u, statusId)
	return true
end

local function auraAppliesTo(auraDef: any, unit: any, objSide: any)
	if auraDef.side == "ALL" then return true end
	return unit.side == auraDef.side
end

-- Reconcile all passive auras against current unit positions. Call on battle
-- start and after any unit moves (CommandService Move hook).
function ObjectEffectService.ReconcileAuras(allUnits: any, state: any)
	if not state or not state.objects then return end
	-- Battle Log Coverage (rules 225): aura on/off from movement is background noise.
	local _prevCause = BattleVisualBroadcaster and BattleVisualBroadcaster.SetCause
		and BattleVisualBroadcaster.SetCause(BattleVisualBroadcaster.SILENT) or nil
	for _, obj in ipairs(state.objects) do
		local auraDef = AURA_OBJECTS[obj.type]
		if auraDef then
			local objId = obj.id or ("aura_" .. tostring(obj.x) .. "," .. tostring(obj.y))
			_auraMembership[objId] = _auraMembership[objId] or {}
			local member = _auraMembership[objId]
			for _, u in ipairs(allUnits) do
				if u.isAlive and u.tileX and u.tileY then
					local inRange = math.abs(u.tileX - (obj.x or 0)) <= auraDef.radius
						and math.abs(u.tileY - (obj.y or 0)) <= auraDef.radius
						and auraAppliesTo(auraDef, u, nil)
					if inRange and not member[u.id] then
						member[u.id] = true
						auraApply(u, auraDef, objId, state)  -- 2026-10-30: source-aware
					elseif (not inRange) and member[u.id] then
						member[u.id] = nil
						-- 2026-10-30 aura fix: keep it if another live aura of the same status still
						-- covers this unit, and only strip what an aura gave (auraRemove).
						local coveredElsewhere = false
						for _, o2 in ipairs(state.objects) do
							local d2 = AURA_OBJECTS[o2.type]
							local id2 = o2.id or ("aura_" .. tostring(o2.x) .. "," .. tostring(o2.y))
							if d2 and d2.status == auraDef.status and id2 ~= objId
								and _auraMembership[id2] and _auraMembership[id2][u.id] then
								coveredElsewhere = true; break
							end
						end
						if not coveredElsewhere and auraRemove(u, auraDef.status, state) then
							if EquipmentService.RebuildUnitStats then EquipmentService.RebuildUnitStats(u) end
							if BattleVisualBroadcaster then BattleVisualBroadcaster.UnitStateChanged(u) end
						end
					end
				end
			end
		end
	end
	if BattleVisualBroadcaster and BattleVisualBroadcaster.ClearCause then
		BattleVisualBroadcaster.ClearCause(_prevCause)
	end
end

-- Aura source removed (USER RULING 2026-10-30, project_rules 241: a broken object's effects are
-- gone). Called by RemoveObjectInstance. Drops this object's aura from every unit it covered and
-- forgets the source. A unit still covered by ANOTHER live aura of the same status keeps it
-- (StatusService.RemoveStatus is not per-source). No-op for non-aura objects.
function ObjectEffectService.ClearAuraFrom(state: any, inst: any)
	local auraDef = inst and inst.type and AURA_OBJECTS[inst.type]
	if not auraDef then return end
	local objId = inst.id or ("aura_" .. tostring(inst.x) .. "," .. tostring(inst.y))
	local member = _auraMembership[objId]
	_auraMembership[objId] = nil
	if not member then return end
	-- Other live aura sources of the same status, by id.
	local otherSources = {}
	for _, o in ipairs((state and state.objects) or {}) do
		local d = AURA_OBJECTS[o.type]
		if d and d.status == auraDef.status and o ~= inst then
			local oid = o.id or ("aura_" .. tostring(o.x) .. "," .. tostring(o.y))
			if oid ~= objId and _auraMembership[oid] then table.insert(otherSources, _auraMembership[oid]) end
		end
	end
	local _prevCause = BattleVisualBroadcaster and BattleVisualBroadcaster.SetCause
		and BattleVisualBroadcaster.SetCause(BattleVisualBroadcaster.SILENT) or nil
	local n = 0
	for _, u in ipairs((state and state.units) or {}) do
		if member[u.id] then
			local stillCovered = false
			for _, m in otherSources do
				if m[u.id] then stillCovered = true; break end
			end
			if not stillCovered then
				-- 2026-10-30 aura fix: only strip what an aura gave (Buff-Blind etc. keep theirs).
				if auraRemove(u, auraDef.status, state) then
					if EquipmentService.RebuildUnitStats then EquipmentService.RebuildUnitStats(u) end
					if BattleVisualBroadcaster then BattleVisualBroadcaster.UnitStateChanged(u) end
					n += 1
				end
			end
		end
	end
	if BattleVisualBroadcaster and BattleVisualBroadcaster.ClearCause then
		BattleVisualBroadcaster.ClearCause(_prevCause)
	end
	print(`[ObjectEffectService] ClearAuraFrom | {inst.type} at ({inst.x},{inst.y}) gone - {auraDef.status} removed from {n} unit(s)`)
end

-- Drop EVERY object aura (2026-10-30 aura fix). Main calls it before a mid-battle map regenerate
-- replaces state.objects (the old banners/statues vanish without RemoveObjectInstance), and
-- ResetBattle calls it with no state so a new battle never inherits old memberships (object ids
-- "obj_N" repeat between maps, which made a fresh banner skip units it "already" covered).
function ObjectEffectService.ClearAllAuras(state: any)
	local statuses = {}
	for _, d in AURA_OBJECTS do statuses[d.status] = true end
	local n = 0
	if state and state.units then
		local _prevCause = BattleVisualBroadcaster and BattleVisualBroadcaster.SetCause
			and BattleVisualBroadcaster.SetCause(BattleVisualBroadcaster.SILENT) or nil
		for _, u in ipairs(state.units) do
			local changed = false
			for statusId in statuses do
				if auraRemove(u, statusId, state) then changed = true end
			end
			if changed then
				if EquipmentService.RebuildUnitStats then EquipmentService.RebuildUnitStats(u) end
				if BattleVisualBroadcaster then BattleVisualBroadcaster.UnitStateChanged(u) end
				n += 1
			end
		end
		if BattleVisualBroadcaster and BattleVisualBroadcaster.ClearCause then
			BattleVisualBroadcaster.ClearCause(_prevCause)
		end
	end
	table.clear(_auraMembership)
	print(`[ObjectEffectService] ClearAllAuras | object auras cleared from {n} unit(s)`)
end

--------------------------------------------------------------------
-- TREASURE REWARD HOOK (best-effort). GenerateRewards needs a player id, a map
-- level, and a UNIQUE opportunity id. In the current combat context those are
-- not reliably reachable from a unit, so this is wired defensively: if the
-- state carries the needed context it generates; otherwise it logs an honest
-- deferral (object still consumed; reward is a small follow-up).
--------------------------------------------------------------------
-- Reward ids must be unique for the whole Play session: RewardService refuses an id it has
-- already seen, and map object ids (obj_1, obj_2, ...) start again on every map. A running
-- counter keeps a later battle's obj_5 from being refused (salvage D-1 fix 2026-11-01; same
-- pattern as _hunterLootSeq below).
local _chestRewardSeq = 0

-- CHEST / SALVAGE LOOT IS HELD UNTIL THE BATTLE ENDS (USER DECISION 2026-11-01, daily systems
-- decision 15; defeat rules unit_progression 91/92/95). Items and cards are rolled now with
-- noCommit and kept on state.chestLoot, gold on state.chestGold, mercury on state.chestMercury.
-- Nothing is credited here: Main gives items, cards and mercury on a qualifying victory only, and
-- the gold with the battle gold (50% kept on a defeat). Same model as Treasure Hunter / stolen loot.
-- (Replaces the 2026-11-01 "commit at once" BUG-075 fix; chest cards now go through Main's
-- battle-loot card loop.)
local function holdChestLoot(state: any, results: any): number
	if not state or type(results) ~= "table" then return 0 end
	state.chestLoot = state.chestLoot or {}
	local n = 0
	for _, r in results do
		if type(r) == "table" and (r.item ~= nil or type(r.cardData) == "table") then
			table.insert(state.chestLoot, r)
			n += 1
		end
	end
	return n
end
local function holdChestGold(state: any, amount: number)
	if state and amount > 0 then
		state.chestGold = (tonumber(state.chestGold) or 0) + amount
	end
end
local function holdChestMercury(state: any, amount: number)
	if state and amount > 0 then
		state.chestMercury = (tonumber(state.chestMercury) or 0) + amount
	end
end
local function nextChestOppId(prefix: string, objId: any): string
	_chestRewardSeq += 1
	return `{prefix}{tostring(objId)}_{_chestRewardSeq}`
end

function ObjectEffectService._grantChestReward(actor: any, ctx: any, opts: any)
	local state = ctx.state
	-- opts.salvage (HD-011 Salvager's Cap): a salvage roll, not a chest -- no chest objective,
	-- no Treasure Seeker / Spendthrift chest modifiers.
	local isSalvage = type(opts) == "table" and opts.salvage == true
	-- Optional objective "Treasure Fever": a chest was opened (shared by Treasure
	-- Chest and Cursed Chest). Counted once per real chest open, regardless of
	-- what the reward roll yields. (Re-added 2026-10-24 -- a prior edit did not
	-- persist; Tester DEFECT-1.)
	if not isSalvage then
		ObjectiveService.RecordEvent(state, "chestsOpened", 1)
	end
	local playerId = state and state.ownerPlayerId
	local mapLevel = state and state.mapLevel
	-- SALVAGER'S CAP (USER RULING 2026-11-01): every qualifying destroyed object gives some gold
	-- (half a chest's base gold, with the normal gold multipliers), plus two separate fixed
	-- chances: 5% for 1 mercury and 5% for one gear item (rolled like normal loot). Held until
	-- the battle ends like chest loot.
	if isSalvage then
		if not (playerId and mapLevel and RewardService) then
			print("[ObjectEffectService] Salvage reward DEFERRED - combat state lacks ownerPlayerId/mapLevel.")
			return true, nil
		end
		local SALVAGE_MERCURY_CHANCE = 0.05
		local SALVAGE_GEAR_CHANCE = 0.05
		local rng = Random.new()
		local baseGold = math.round(12.5 * (1 + (mapLevel / 50)))
		local goldAmount = if RewardService.ApplyGold then RewardService.ApplyGold(baseGold) else baseGold
		local gotMercury = rng:NextNumber() < SALVAGE_MERCURY_CHANCE
		local gotGear = rng:NextNumber() < SALVAGE_GEAR_CHANCE
		holdChestGold(state, goldAmount)
		if gotMercury then
			holdChestMercury(state, 1)
		end
		if gotGear and RewardService.GenerateRewards then
			local oppId = nextChestOppId("salvage_", ctx.objInstance and ctx.objInstance.id or "obj")
			local okGear, results = pcall(RewardService.GenerateRewards, playerId, mapLevel, oppId,
				{ count = 1, allowedCategories = { "Equipment" }, noCommit = true })
			if not okGear then
				warn("[ObjectEffectService] Salvage gear roll failed: " .. tostring(results))
				gotGear = false
			elseif holdChestLoot(state, results) < 1 then
				-- Refused or not generated: report it honestly instead of "+ 1 gear item".
				warn("[ObjectEffectService] Salvage gear roll gave no item (opportunity " .. oppId .. ")")
				gotGear = false
			end
		end
		print(string.format("[ObjectEffectService] Salvage: %s finds %d gold%s%s (held until the battle ends)",
			tostring(actor and actor.name), goldAmount,
			if gotMercury then " + 1 mercury" else "", if gotGear then " + 1 gear item" else ""))
		return true, nil
	end
	if playerId and mapLevel and RewardService and RewardService.GenerateRewards then
		local oppId = nextChestOppId("chest_", ctx.objInstance and ctx.objInstance.id or "obj")
		-- Idol of Fortune (2026-10-24, fixed after Tester UAT): ADDITIVE fortune bump
		-- for THIS chest roll, layered on top of the real team baseline -- NOT an
		-- absolute overwrite. SetExpeditionFortune is an absolute setter with no
		-- getter, so we recompute the team baseline from ctx.allUnits (the same pure
		-- function Main uses: ComputeExpeditionFortune), set baseline + bump (clamped
		-- to the 1.75 ceiling by SetExpeditionFortune itself), generate, then RESTORE
		-- the baseline by recomputing it again -- never zero it. This guarantees the
		-- Idol can only raise drop quality (never lower a high-Fortune team), and a
		-- later non-Idol chest in the same battle still rolls at the correct baseline.
		local idolBump = state and state.idolFortuneBump
		local appliedIdol = false
		local baseline = nil
		if idolBump and RewardService.SetExpeditionFortune and RewardService.ComputeExpeditionFortune then
			baseline = RewardService.ComputeExpeditionFortune(ctx.allUnits or {})
			RewardService.SetExpeditionFortune(baseline + idolBump)
			appliedIdol = true
		end
		local held = 0
		local ok = pcall(function()
			held += holdChestLoot(state, (RewardService.GenerateRewards(playerId, mapLevel, oppId, { noCommit = true })))
			-- Treasure Seeker (user ruling 2026-10-29): 50% / 60% chance of ONE extra reward roll from
			-- this chest, rolled at the same Fortune (Idol bump included). Gold bonus is separate below.
			-- Own pcall: a failure in the extra roll must not cancel the chest gold below.
			pcall(function()
				local _xChance = (require :: any)(script.Parent.TraitEffectService).GetChestExtraItemChance(actor)
				if _xChance > 0 and Random.new():NextNumber() < _xChance then
					held += holdChestLoot(state, (RewardService.GenerateRewards(playerId, mapLevel, oppId .. "_seeker",
						{ count = 1, noCommit = true })))
					print(string.format("[ObjectEffectService] Treasure Seeker: %s finds an extra item", tostring(actor and actor.name)))
				end
			end)
		end)
		-- Restore the real team baseline (recompute, do NOT zero) so later chests and
		-- any other in-battle reward path keep the correct team Fortune.
		if appliedIdol then
			RewardService.SetExpeditionFortune(baseline)
		end
		if ok then
			print(string.format("[ObjectEffectService] Treasure reward rolled (opportunity %s): %d reward(s) held until the battle ends%s",
				oppId, held, appliedIdol and " [Idol of Fortune drop bonus applied]" or ""))
			-- CHEST GOLD (2026-10-24): base = Exploration-category completion gold
			-- (economy_framework: 25 x (1 + MapLevel/50)); ApplyGold layers the gold + Fortune
			-- multipliers (Fortune applies to chests per loot_progression). Per-opener trait
			-- multiplier: Treasure Seeker (+50/60%) / Spendthrift Looter (-50/60%). Held, then paid
			-- with the battle gold (50% on a defeat).
			local TraitEffectService = (require :: any)(script.Parent.TraitEffectService)
			local baseGold = math.round(25 * (1 + (mapLevel / 50)))
			local traitMult = TraitEffectService.GetChestGoldMultiplier(actor)
			local goldAmount = RewardService.ApplyGold(math.round(baseGold * traitMult))
			holdChestGold(state, goldAmount)
			print(string.format("[ObjectEffectService] Chest gold %d held for %s (base %d x trait %.2f, after gold+fortune mults)",
				goldAmount, playerId, baseGold, traitMult))
			-- CHEST MERCURY (materials_system 10): every chest reward roll (Treasure and Cursed
			-- Chest) gives 1 mercury. No crystals or rune gems. Fortune never applies. Held.
			holdChestMercury(state, 1)
			print(string.format("[ObjectEffectService] Chest mercury 1 held for %s", playerId))
			return true, nil
		end
	end
	print("[ObjectEffectService] Treasure reward DEFERRED -- combat state lacks ownerPlayerId/mapLevel (follow-up).")
	return true, nil
end

--------------------------------------------------------------------
-- TREASURE HUNTER LOOT (project_rules 226-234, user-locked 2026-10-28). The Neutral event
-- NPC takes a chest's loot. NEVER calls _grantChestReward (that records chestsOpened and
-- holds loot for the player). Treasure/Cursed Chest: roll the normal reward with
-- RewardService.GenerateRewards(..., { noCommit = true }) at NEUTRAL Fortune (no team
-- Fortune, no Idol bump; the previous Fortune is restored right after), remove the chest,
-- and return the held results. Cursed Chest also Weakens the NPC (3000 CT, same handler
-- path a player gets). Disguised Mimic: wake it through the normal Resolve -> Mimic handler
-- (which tags the Mimic huntsUnitId and skips chestsOpened for this opener).
-- Returns kind ("loot" | "mimic" | nil), heldResults (array, may be empty).
--------------------------------------------------------------------
local _hunterLootSeq = 0
function ObjectEffectService.HunterLootChest(state: any, actor: any, inst: any): (any, any)
	if not (state and actor and inst and inst.type) then return nil, {} end
	local objId = inst.id or ("obj_@" .. tostring(inst.x) .. "," .. tostring(inst.y))
	if _consumed[objId] then return nil, {} end
	local ox, oy = inst.x, inst.y

	if inst.type == "Mimic" then
		local ok = ObjectEffectService.Resolve(actor, inst, state, state.units)
		if ok then
			if BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectChanged then
				BattleVisualBroadcaster.ObjectChanged(ox, oy, { destroyed = true })
			end
			return "mimic", {}
		end
		warn(`[ObjectEffectService] HunterLootChest: Mimic wake failed at ({ox},{oy})`)
		return nil, {}
	end

	if inst.type ~= "Treasure Chest" and inst.type ~= "Cursed Chest" then return nil, {} end
	if inst.type == "Cursed Chest" then
		local _prev = BattleVisualBroadcaster and BattleVisualBroadcaster.SetCause and BattleVisualBroadcaster.SetCause("Cursed Chest") or nil
		applyAndRebuild(actor, "Weakened", actor.id)
		if BattleVisualBroadcaster and BattleVisualBroadcaster.ClearCause then BattleVisualBroadcaster.ClearCause(_prev) end
	end

	local held = {}
	local playerId = state.ownerPlayerId
	local mapLevel = state.mapLevel
	if playerId and mapLevel and RewardService and RewardService.GenerateRewards then
		_hunterLootSeq += 1
		-- Unique id: own prefix (real chest opens use "chest_<id>") + NPC id + sequence.
		local oppId = `hunterloot_{objId}_{tostring(actor.id)}_{_hunterLootSeq}`
		local prevFortune = RewardService.GetExpeditionFortune and RewardService.GetExpeditionFortune() or nil
		if RewardService.SetExpeditionFortune then RewardService.SetExpeditionFortune(0) end
		local okR, resR = pcall(RewardService.GenerateRewards, playerId, mapLevel, oppId, { noCommit = true })
		-- The chest's gold goes with the loot (daily systems decision 16, USER DECISION 2026-11-01):
		-- the base chest gold at neutral Fortune (no opener trait), held as a { category = "Gold" }
		-- entry and paid with the recovered loot only on a victory.
		local hunterGold = math.round(25 * (1 + (mapLevel / 50)))
		if RewardService.ApplyGold then hunterGold = RewardService.ApplyGold(hunterGold) end
		if hunterGold > 0 then
			table.insert(held, { category = "Gold", gold = hunterGold })
		end
		if prevFortune ~= nil and RewardService.SetExpeditionFortune then
			RewardService.SetExpeditionFortune(prevFortune)
		end
		if okR and type(resR) == "table" then
			for _, r in ipairs(resR) do
				if r.item or r.cardData then table.insert(held, r) end
			end
		else
			warn("[ObjectEffectService] HunterLootChest: reward roll failed: " .. tostring(resR))
		end
	else
		warn("[ObjectEffectService] HunterLootChest: state lacks ownerPlayerId/mapLevel — NPC holds nothing")
	end

	_consumed[objId] = true
	ObjectEffectService.RemoveObjectInstance(state, inst)
	if BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectChanged then
		BattleVisualBroadcaster.ObjectChanged(ox, oy, { destroyed = true })
	end
	print(`[ObjectEffectService] Treasure Hunter looted {inst.type} at ({ox},{oy}) -- holds {#held} reward(s) (gold included)`)
	return "loot", held
end

--------------------------------------------------------------------
-- NECRO TOME STAND — passive, death-triggered. Whenever a unit dies within
-- radius 3 of a Necro Tome Stand, deal dark damage to that dying unit's
-- OPPONENTS equal to 10% of the DYING unit's max HP (two-sided: a death on
-- either side triggers it). No single death EVENT exists in the engine (units
-- die inline in several places), so this is driven by a death-sweep the battle
-- loop calls after actions resolve: we snapshot who was alive, and on each
-- sweep detect newly-dead units and fire the effect once per death.
--------------------------------------------------------------------
-- _aliveSnapshot ({ [unitId] = true }) is declared at module top so ResetBattle
-- (defined earlier) can clear it. Captured/refreshed each ProcessDeaths sweep.

local function necroStandsOnMap(state: any)
	local out = {}
	if state and state.objects then
		for _, obj in ipairs(state.objects) do
			if obj.type == "Necro Tome Stand" then table.insert(out, obj) end
		end
	end
	return out
end

-- Call after any action that may have killed a unit (battle loop hook).
function ObjectEffectService.ProcessDeaths(allUnits: any, state: any)
	local stands = necroStandsOnMap(state)
	if _aliveSnapshot == nil then
		_aliveSnapshot = {}
		for _, u in ipairs(allUnits) do
			if u.isAlive then _aliveSnapshot[u.id] = true end
		end
		return
	end
	local sweepEnemyKOs = 0
	for _, u in ipairs(allUnits) do
		local wasAlive = _aliveSnapshot[u.id]
		if wasAlive and not u.isAlive then
			-- Optional-objective kill routing (push/siege KOs, elite timing, NPC
			-- death). Single choke-point: every death flows through this sweep,
			-- so one call here covers all death sources without touching each.
			ObjectiveService.OnUnitKilled(state, u)
			if u.side == "Enemy" and not u.isSummon then sweepEnemyKOs += 1 end
			if #stands > 0 and u.tileX and u.tileY then
				local triggered = false
				for _, st in ipairs(stands) do
					if math.abs(u.tileX - (st.x or 0)) <= 3 and math.abs(u.tileY - (st.y or 0)) <= 3 then
						triggered = true; break
					end
				end
				if triggered then
					local dmg = math.floor((u.maxHp or 0) * 0.10)
					local _necroFocusDone = false
					for _, opp in ipairs(allUnits) do
						if opp.isAlive and opp.side ~= u.side and not opp.isGroundTarget then
							local _shown4 = GameConstants.CapUnitDamage(opp, dmg)  -- 1 for a 3-hit gadget
							opp.currentHp = math.max(0, (opp.currentHp or 0) - _shown4)
							if opp.currentHp <= 0 then opp.isAlive = false end
							if BattleVisualBroadcaster then BattleVisualBroadcaster.UnitStateChanged(opp, "Necro Tome") end
							if BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectDamage and opp.tileX and opp.tileY then
								local _f = not _necroFocusDone; _necroFocusDone = true
								BattleVisualBroadcaster.ObjectDamage(opp.tileX, opp.tileY, _shown4, _f)
							end
						end
					end
					print(string.format("[ObjectEffectService] Necro Tome Stand | %s died in range -> %d dark dmg to opponents", u.name, dmg))
				end
			end
		end
	end
	-- Nuker: count enemies that died in THIS single action (one sweep = one action).
	ObjectiveService.RecordMultiKill(state, sweepEnemyKOs)
	_aliveSnapshot = {}
	for _, u in ipairs(allUnits) do
		if u.isAlive then _aliveSnapshot[u.id] = true end
	end
end

--------------------------------------------------------------------
-- PUBLIC: Is this map object a valid Interact target for this unit right now?
-- (user ruling 2026-10-26). Used by TargetingService.GetInteractCandidates, so the
-- same rule drives BOTH the Interact menu and the server re-check before any AP/RT
-- is charged (SEC-002). Not interactable:
--   * traps and anything that fires by itself ("Triggered": traps, Bomb Barrel)
--   * always-on aura objects ("Passive": War Banner, Cursed Statue, Necro Tome Stand)
--   * a single-use ("Once") object that has already been used
--   * a "Once per turn" object this unit already used during its current turn
--------------------------------------------------------------------
-- HD-009 Demolition Mask (2026-11-06): a breakable obstacle with NO interact effect is still an
-- Interact target for a Mask wearer (CommandService breaks it up front). Exported for targeting.
function ObjectEffectService.IsMaskBreakTarget(objInstance: any, actorSide: any): boolean
	local def = objInstance and objInstance.type and ObjectData.Objects[objInstance.type]
	if not def or Handlers[objInstance.type] then return false end
	-- Same owner-side gate as IsInteractable: never the OTHER side's placed deployables (keeps the
	-- pre-2026-11-06 scope; the Mask only regains what it could break before the Interact fix).
	if def.isDeployable and objInstance.ownerSide and actorSide and actorSide ~= objInstance.ownerSide then
		return false
	end
	if def.activation ~= nil then return false end
	return isBreakableObject(def)
end

function ObjectEffectService.IsInteractable(objInstance: any, actorId: any, actorSide: any, state: any): boolean
	local def = objInstance and objInstance.type and ObjectData.Objects[objInstance.type]
	if not def then return false end
	-- Item-placed interactables (Portable Ballista, 2026-10-26) work for the owner's side only.
	if def.isDeployable and objInstance.ownerSide and actorSide and actorSide ~= objInstance.ownerSide then
		return false
	end
	-- Once-per-unit deployables (Supply Station): a unit that already used it never sees it again.
	if objInstance.usedBy and actorId ~= nil and objInstance.usedBy[actorId] then
		return false
	end
	local act = def.activation
	if act == "Triggered" or act == "Passive" or objHasTag(def, "Trap") then
		return false
	end
	-- No interact effect implemented (blockers, item gadgets): never offer Interact, so a
	-- unit can't spend AP/RT for nothing (Studio-confirmed bug 2026-11-06). Resolve() keeps its
	-- own no-handler log as a safety net.
	if not Handlers[objInstance.type] then
		return false
	end
	local objId = objInstance.id or ("obj_@" .. tostring(objInstance.x) .. "," .. tostring(objInstance.y))
	local uses = def.uses or "Once"
	if uses == "Once" and _consumed[objId] then return false end
	if uses == "Once per turn" and actorId ~= nil and _usedThisTurn[objId] == actorId then
		return false
	end
	-- W2 (2026-11-06): a Forge with no legal tile in radius 3 is not offered at all (the
	-- handler also fails cleanly as a safety net). Optional state; old callers unaffected.
	if objInstance.type == "Forge" and state and objInstance.x and objInstance.y then
		local legal = forgeLegalTiles(state, objInstance.x, objInstance.y, actorSide)
		if #legal == 0 then return false end
	end
	return true
end

--------------------------------------------------------------------
-- PUBLIC: Resolve one map-object interaction.
-- Returns ok, reason. CommandService has already validated candidacy and
-- charged AP/RT; this applies the EFFECT only. Usage ("Once"/"Once per turn")
-- is enforced here so a consumed object is rejected before its effect runs.
--------------------------------------------------------------------
function ObjectEffectService.Resolve(actor: any, objInstance: any, state: any, allUnits: any): (boolean, any)
	if not objInstance then return false, "No object instance." end
	local archId = objInstance.type
	local objDef = ObjectData and ObjectData.Objects and ObjectData.Objects[archId] or nil
	if not objDef then
		return false, "Unknown object archetype: " .. tostring(archId)
	end

	local uses = objDef.uses or "Once"
	local objId = objInstance.id or ("obj_@" .. tostring(objInstance.x) .. "," .. tostring(objInstance.y))

	-- Usage gates.
	if uses == "Once" and _consumed[objId] then
		return false, objDef.id .. " has already been used."
	end
	if uses == "Once per turn" then
		-- Reject if THIS unit already used THIS object during its current turn.
		if _usedThisTurn[objId] == actor.id then
			return false, objDef.id .. " already used this turn."
		end
	end

	local handler = Handlers[archId]
	if not handler then
		-- No effect implemented yet (Tier 2/3 or parked). Honest no-op: the
		-- command already charged AP/RT; report so the caller can log it.
		print(string.format(
			"[ObjectEffectService] No effect handler for '%s' yet (Tier 2/3/parked) — AP/RT charged, no effect.",
			tostring(archId)))
		return true, nil
	end

	-- Deterministic per-interaction RNG: seeded from the battle clock + object
	-- tile + actor id so a given interaction always rolls the same (no stored
	-- seed needed; honors the determinism rule). Used by Eye of the Magi (random
	-- target pick) and Mysterious Boulder (random debuff roll).
	local seedBase = (state and state.ct or 0)
		+ ((objInstance.x or 0) * 73856093)
		+ ((objInstance.y or 0) * 19349663)
		+ (tonumber(string.match(tostring(actor.id or "0"), "%d+")) or 0)
	local rng = Random.new(seedBase)

	-- Battle Log Coverage (rules 225): every change a handler broadcasts is labelled with
	-- the object's DISPLAY name (a disguised Mimic reads as its disguise). Scope is
	-- restored even if the handler errors; the error is re-raised unchanged.
	local _bvb = BattleVisualBroadcaster
	local _prevCause = _bvb and _bvb.SetCause and _bvb.SetCause(ObjectEffectService.GetDisplayType(objInstance, nil)) or nil
	local _pok, ok, reason = pcall(handler, {
		actor = actor, objInstance = objInstance,
		objDef = objDef, state = state, allUnits = allUnits, rng = rng,
	})
	if _bvb and _bvb.ClearCause then _bvb.ClearCause(_prevCause) end
	if not _pok then error(ok, 0) end

	if ok then
		if uses == "Once" then
			_consumed[objId] = true
		elseif uses == "Once per turn" then
			_usedThisTurn[objId] = actor.id
		end
	end
	return ok, reason
end

-- Clear a unit's per-turn object usage (called at that unit's turn start).
function ObjectEffectService.ClearTurnUsage(unitId: any)
	for objId, uid in pairs(_usedThisTurn) do
		if uid == unitId then
			_usedThisTurn[objId] = nil
		end
	end
end

--------------------------------------------------------------------
-- STEP-ON TRAP TRIGGERS (Slice 5 — trap-trigger feature, 2026-10-20).
--
-- objects_encounters: Bear/Spike/Snare/Land Mine are "Triggered — Unit enters
-- tile", passable, single-use, "Removed after activation". Before this feature
-- the ONLY path that fired a map-object effect was the Interact action, so none
-- of these ever went off when walked onto. These helpers are called from the
-- movement commit (every tile crossed) and from the forced-movement apply sites.
--
-- Locked behaviour (user, 2026-10-20):
--   • Fires on every tile crossed, voluntary AND forced movement.
--   • Bear/Snare (rooting) STOP a voluntary walk at that tile; Spike and Land
--     Mine do NOT stop it; a KO stops it. Forced movement never stops early
--     (momentum) — it only ends if the unit is KO'd.
--   • Flight bypasses traps entirely (handled by the caller).
--------------------------------------------------------------------

-- A step-on trap = passable object carrying the "Trap" tag (Bear/Spike/Snare/
-- Land Mine). Bomb Barrel (non-passable, no "Trap" tag) is excluded — it is hit,
-- not stepped on.
local function isStepOnTrap(def: any): boolean
	return def ~= nil and def.passable == true and objHasTag(def, "Trap")
end

-- Traps that ROOT the unit (Pinned) and therefore stop a voluntary walk.
local TRAP_STOPS_WALK = {
	["Bear Trap"]  = true,
	["Snare Trap"] = true,
}

-- Return the live, not-yet-consumed step-on trap instance at (x,y), or nil.
function ObjectEffectService.GetTriggeredTrapAt(state: any, x: any, y: any): any
	if not (state and state.objects) then return nil end
	for _, o in ipairs(state.objects) do
		if o.x == x and o.y == y then
			local def = o.type and ObjectData.Objects[o.type]
			if isStepOnTrap(def) then return o end
			return nil  -- one object per tile; if it's not a trap, nothing to trigger
		end
	end
	return nil
end

-- Fire ONE step-on trap: run its effect via the shared Resolve dispatcher (which
-- enforces the "Once" usage gate), then remove the object ("removed after
-- activation") and tell clients to drop the sprite. A final UnitStateChanged
-- guarantees any direct HP/RT mutation (e.g. Snare's +RT) reaches the client.
-- Returns { fired, stops, killed }.
function ObjectEffectService.TriggerTrap(actor: any, inst: any, state: any, allUnits: any): any
	if not (actor and inst and actor.isAlive) then return { fired = false } end
	local def = inst.type and ObjectData.Objects[inst.type]
	if not isStepOnTrap(def) then return { fired = false } end
	-- Enemy-only trigger for SKILL-placed traps (2026-10-24): a skill-placed trap
	-- carries inst.ownerSide (caster side). Units on the owner's side walk over it
	-- safely; only enemies of the owner spring it. Map-placed traps have no ownerSide
	-- and keep triggering on ANY unit (unchanged). Trigger-gate ONLY — once sprung,
	-- the trap effect still follows the standing friendly-fire rule.
	if inst.ownerSide and actor.side and actor.side == inst.ownerSide then
		return { fired = false }
	end
	-- Trap feedback snapshot (2026-10-28): capture pre-spring HP / statuses / hidden
	-- so ONE battle-log line can say what just happened (BUG-034 class).
	local hpBefore = actor.currentHp or 0
	local statusBefore = {}
	for _, si in ipairs(actor.statusInstances or {}) do
		if si.id then statusBefore[si.id] = true end
	end
	local wasHidden = (inst.hidden == true)
	local ok = ObjectEffectService.Resolve(actor, inst, state, allUnits)
	if not ok then return { fired = false } end
	-- Visual indicator BEFORE removal/ObjectChanged so the order reads naturally.
	if BattleVisualBroadcaster and BattleVisualBroadcaster.TrapSprung then
		BattleVisualBroadcaster.TrapSprung(inst.x, inst.y, inst.type, actor.id, wasHidden)
	end
	-- Single-use traps are removed after firing ("removed after activation").
	-- A hidden persistent trap that springs is no longer a secret: draw it now.
	if (def.uses or "Once") == "Unlimited" and inst.hidden then
		ObjectEffectService.RevealObject(inst)
	end
	-- Persistent traps (uses = "Unlimited", e.g. Spike area-denial) stay on the
	-- tile and re-spring on the next crossing — do NOT remove or drop the sprite.
	if (def.uses or "Once") ~= "Unlimited" then
		ObjectEffectService.RemoveObjectInstance(state, inst)
		if BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectChanged then
			BattleVisualBroadcaster.ObjectChanged(inst.x, inst.y, { destroyed = true })
		end
	end
	if BattleVisualBroadcaster and BattleVisualBroadcaster.UnitStateChanged then
		-- The trap line below already describes the actor's change (dedup, rules 225).
		BattleVisualBroadcaster.UnitStateChanged(actor, BattleVisualBroadcaster.SILENT)
	end
	if BattleVisualBroadcaster and BattleVisualBroadcaster.SyncUnit then
		BattleVisualBroadcaster.SyncUnit(actor)
	end
	local killed = (actor.isAlive == false) or ((actor.currentHp or 1) <= 0)
	local stops = (TRAP_STOPS_WALK[inst.type] == true) or killed
	-- In-game battle-log line (single choke point for every spring path).
	do
		local hpLost = math.max(0, hpBefore - (actor.currentHp or 0))
		local gained = {}
		for _, si in ipairs(actor.statusInstances or {}) do
			if si.id and not statusBefore[si.id] then
				statusBefore[si.id] = true  -- dedupe stacked instances
				table.insert(gained, tostring(si.id))
			end
		end
		local who = actor.name or "?"
		local verb = if objHasTag(def, "Explosive") then "set off" else "triggered"
		local article = if wasHidden then "a hidden" else "a"
		local parts = {}
		if hpLost > 0 then table.insert(parts, `took {hpLost} damage`) end
		for _, sid in ipairs(gained) do table.insert(parts, sid) end
		local text = `{who} {verb} {article} {tostring(inst.type)}`
		text = if #parts > 0 then `{text} — {table.concat(parts, ", ")}.` else `{text}.`
		if killed then text = `{text} {who} was defeated.` end
		if BattleVisualBroadcaster and BattleVisualBroadcaster.Log then
			BattleVisualBroadcaster.Log("trap", text, actor.id)
		end
	end
	print(string.format("[ObjectEffectService] TRAP SPRUNG | %s on %s at (%s,%s) | stops=%s killed=%s",
		tostring(inst.type), tostring(actor.name), tostring(inst.x), tostring(inst.y),
		tostring(stops), tostring(killed)))
	return { fired = true, stops = stops, killed = killed }
end

-- Explosion-chain hook: if an EXPLOSIVE object (Bomb Barrel / Land Mine) sits at
-- (x,y), remove it and signal the caller (the explosion queue) to chain a new
-- explosion event at this tile within the SAME queue. Consume-once. Returns true
-- if an explosive was consumed here.
function ObjectEffectService.ConsumeExplosiveObjectAt(state: any, x: any, y: any): boolean
	if not (state and state.objects) then return false end
	for _, o in ipairs(state.objects) do
		if o.x == x and o.y == y then
			local def = o.type and ObjectData.Objects[o.type]
			if def and objHasTag(def, "Explosive") then
				local _shownType = if o.hidden then nil else ObjectEffectService.GetDisplayType(o, nil)  -- hidden: never logged
				ObjectEffectService.RemoveObjectInstance(state, o)
				if BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectChanged then
					BattleVisualBroadcaster.ObjectChanged(x, y, { destroyed = true, exploded = true }, _shownType)
				end
				-- Second value: was it a trap (Land Mine)? Its chained blast counts for Goblin Cunning.
				return true, objHasTag(def, "Trap")
			end
			return false
		end
	end
	return false
end

-- GL-007 Demolition Mitts: detonate ANY movable object at (x,y) as a Bomb Barrel-style blast --
-- a 3x3 (box) explosion dealing damagePercent of Max HP, then remove the object. Unlike
-- ConsumeExplosiveObjectAt this is NOT gated on the Explosive tag (the glove makes any pushed
-- object blow up on collision). Object removed FIRST so the blast is not self-blocked. nil-safe.
-- instigatorId (optional, 2026-10-28): the glove wearer's unit id (Treasure Hunter escape flag).
function ObjectEffectService.DetonateObjectAt(state: any, x: any, y: any, damagePercent: any, allUnits: any, ownerId: any, instigatorId: any): boolean
	if not (state and state.objects) then return false end
	local inst = nil
	for _, o in ipairs(state.objects) do
		if o.x == x and o.y == y then inst = o; break end
	end
	if not inst then return false end
	local _shownType = ObjectEffectService.GetDisplayType(inst, nil)
	ObjectEffectService.RemoveObjectInstance(state, inst)
	if BattleVisualBroadcaster and BattleVisualBroadcaster.ObjectChanged then
		BattleVisualBroadcaster.ObjectChanged(x, y, { destroyed = true, exploded = true }, if inst.hidden then nil else _shownType)
	end
	if _tileEffectService and _tileEffectService.QueueExplosion then
		_tileEffectService.QueueExplosion(x, y, 0, ownerId, damagePercent or 0.30, allUnits, "box", nil, instigatorId)
	end
	print(string.format("[ObjectEffectService] Demolition Mitts: object at (%d,%d) detonated (3x3, %d%% Max HP)",
		x, y, math.floor((damagePercent or 0.30) * 100)))
	return true
end

return ObjectEffectService
