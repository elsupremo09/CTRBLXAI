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
local BattleCoordinator       = require(script.Parent.BattleCoordinator)
local CombatResolver          = require(script.Parent.CombatResolver)
local BattleVisualBroadcaster = require(script.Parent.BattleVisualBroadcaster)
local RewardService           = require(script.Parent.RewardService)
local EquipmentService        = require(script.Parent.EquipmentService)
-- Mid-battle summons (Dragon Utopia / Mimic). One-way require:
-- BattleVisualBroadcaster/EnemyGenerator do NOT require ObjectEffectService, so
-- no cycle. EnemyGenerator builds + inserts the unit; we broadcast UnitSpawned.
local EnemyGenerator          = require(script.Parent.EnemyGenerator)
local QuestGenerator          = require(script.Parent.QuestGenerator)
local InventoryService        = require(script.Parent.InventoryService)
local ItemGenerator           = require(script.Parent.ItemGenerator)
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
local _aliveSnapshot = nil

function ObjectEffectService.SetTileEffectService(tes)
	_tileEffectService = tes
end

-- Inject the runtime object renderer (Main wires a closure over its mapFolder).
function ObjectEffectService.SetObjectRenderer(fn)
	_objectRenderer = fn
end

-- Runtime-injected object-visual remover: fn(instance) -> destroys the object's
-- model/cube in the live mapFolder and clears the tile's object attributes.
-- nil-safe: if unset, the object is still logically removed.
local _objectVisualRemover = nil
function ObjectEffectService.SetObjectVisualRemover(fn)
	_objectVisualRemover = fn
end

-- Remove a map-object instance from the live battle: state.objects entry, its
-- blocker entry (so the tile is walkable/free again), and its visual.
function ObjectEffectService.RemoveObjectInstance(state, inst)
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
	if _objectVisualRemover then
		_objectVisualRemover(inst)
	end
	print(string.format("[ObjectEffectService] RemoveObjectInstance | %s at (%s,%s) removed=%s",
		tostring(inst.type), tostring(inst.x), tostring(inst.y), tostring(removed)))
	return removed
end

-- Inject the direction prompter (Main wires promptCardinalDirection). Lets a siege
-- handler ask the player to AIM in a cardinal direction: fn(actor) -> "N"/"E"/"S"/"W"
-- or nil. Blocking (yields until the player chooses). nil-safe: if unset, siege
-- handlers fall back to auto-targeting the nearest enemy.
local _directionPrompter = nil
function ObjectEffectService.SetDirectionPrompter(fn)
	_directionPrompter = fn
end

-- Inject the runtime tile reshaper (Main wires a closure over its mapFolder):
-- fn(x, y, newTerrain, newElevation) -> updates the live tile Part visual.
local _tileReshaper = nil
function ObjectEffectService.SetTileReshaper(fn)
	_tileReshaper = fn
end

-- Place a NEW map-object instance into the live battle (Forge, Mimic reveal).
-- Appends to state.objects (generator shape {id,type,x,y}) so Interact/aura/
-- death systems see it, and renders it via the injected renderer. Returns the
-- new instance, or nil if the tile is already occupied by an object.
local _spawnedObjectCounter = 0
function ObjectEffectService.PlaceObjectInstance(state, objType, x, y)
	if not (state and state.objects and objType and x and y) then return nil end
	-- Do not stack two objects on the same tile.
	for _, o in ipairs(state.objects) do
		if o.x == x and o.y == y then return nil end
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
	_spawnedObjectCounter += 1
	local inst = { id = "spawnobj_" .. _spawnedObjectCounter, type = objType, x = x, y = y }
	table.insert(state.objects, inst)
	if _objectRenderer then
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
		ObjectEffectService.ReconcileAuras(state.units, state)
	end
	print(string.format("[ObjectEffectService] PlaceObjectInstance | %s at (%d,%d) id=%s", objType, x, y, inst.id))
	return inst
end

-- Reset the usage ledger at battle start (called from Main on new battle).
function ObjectEffectService.ResetBattle()
	table.clear(_consumed)
	table.clear(_usedThisTurn)
	_aliveSnapshot = nil
	print("[ObjectEffectService] Usage ledger reset for new battle.")
end

--------------------------------------------------------------------
-- EFFECT HANDLERS — keyed by ObjectData archetype id.
-- Each: function(ctx) -> ok:boolean, reason:string?
-- ctx = { actor, objInstance, objDef, state, allUnits }
--------------------------------------------------------------------
local Handlers = {}

-- Healing Spring — fully restore the interacting unit's HP (G1 proof handler).
Handlers["Healing Spring"] = function(ctx)
	local actor = ctx.actor
	if not actor or actor.maxHp == nil then
		return false, "Healing Spring: actor has no HP."
	end
	local before = actor.currentHp or 0
	actor.currentHp = actor.maxHp
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
local function livingAllies(actor, allUnits, includeSelf)
	local out = {}
	for _, u in ipairs(allUnits) do
		if u.isAlive and u.side == actor.side and (includeSelf or u.id ~= actor.id) then
			table.insert(out, u)
		end
	end
	return out
end

local function livingEnemies(actor, allUnits)
	local out = {}
	for _, u in ipairs(allUnits) do
		if u.isAlive and u.side ~= actor.side and not u.isGroundTarget then
			table.insert(out, u)
		end
	end
	return out
end

local function enemiesInRadius(actor, allUnits, cx, cy, radius)
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
local function applyAndRebuild(unit, statusId, sourceId)
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
Handlers["Magic Spring"] = function(ctx)
	local a = ctx.actor
	if not a or a.maxMp == nil then return false, "Magic Spring: actor has no MP." end
	local before = a.currentMp or 0
	a.currentMp = a.maxMp
	if BattleVisualBroadcaster then BattleVisualBroadcaster.UnitStateChanged(a) end
	print(string.format("[ObjectEffectService] Magic Spring | %s MP %d -> %d", a.name, before, a.currentMp))
	return true, nil
end

Handlers["Campfire"] = function(ctx)
	local a = ctx.actor
	if not a or a.maxHp == nil then return false, "Campfire: actor has no HP." end
	local hpGain = math.floor((a.maxHp or 0) * 0.30)
	local mpGain = math.floor((a.maxMp or 0) * 0.30)
	a.currentHp = math.min(a.maxHp, (a.currentHp or 0) + hpGain)
	a.currentMp = math.min(a.maxMp or 0, (a.currentMp or 0) + mpGain)
	if BattleVisualBroadcaster then BattleVisualBroadcaster.UnitStateChanged(a) end
	print(string.format("[ObjectEffectService] Campfire | %s +%d HP / +%d MP", a.name, hpGain, mpGain))
	return true, nil
end

--------------------------------------------------------------------
-- SELF / ALLY TIMED BUFFS (apply status to the acting side)
-- auraStatus-free objects: Interact applies the buff to all allies incl self.
--------------------------------------------------------------------
local function allyBuffHandler(statusId, label)
	return function(ctx)
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
Handlers["Angel Statue"]     = allyBuffHandler("Flight", "Angel Statue")
Handlers["Blood Fountain"]   = allyBuffHandler("Regeneration", "Blood Fountain")
Handlers["Fountain of Fortune"] = allyBuffHandler("Fortune Boon", "Fountain of Fortune")

--------------------------------------------------------------------
-- ALLY MAP-WIDE UTILITY
--------------------------------------------------------------------
Handlers["Swan Pond"] = function(ctx)
	local a = ctx.actor
	local targets = livingAllies(a, ctx.allUnits, true)
	for _, u in ipairs(targets) do
		StatusService.RemoveDispellable(u)
		if EquipmentService and EquipmentService.RebuildUnitStats then EquipmentService.RebuildUnitStats(u) end
		if BattleVisualBroadcaster then BattleVisualBroadcaster.UnitStateChanged(u) end
	end
	print(string.format("[ObjectEffectService] Swan Pond | cleansed debuffs on %d ally(s)", #targets))
	return true, nil
end

Handlers["Astrolabe"] = function(ctx)
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
Handlers["Obelisk"] = function(ctx)
	local a = ctx.actor
	local targets = livingEnemies(a, ctx.allUnits)
	for _, u in ipairs(targets) do
		u.remainingRt = (u.remainingRt or 0) + 300
		if BattleVisualBroadcaster then BattleVisualBroadcaster.UnitStateChanged(u) end
	end
	print(string.format("[ObjectEffectService] Obelisk | +300 RT Delay to %d enemy(s)", #targets))
	return true, nil
end

Handlers["Cover of Darkness"] = function(ctx)
	local a = ctx.actor
	local targets = enemiesInRadius(a, ctx.allUnits, a.tileX, a.tileY, 5)
	for _, u in ipairs(targets) do
		applyAndRebuild(u, "Blind", a.id)
	end
	print(string.format("[ObjectEffectService] Cover of Darkness | Blind on %d enemy(s) in R5", #targets))
	return true, nil
end

Handlers["Mysterious Boulder"] = function(ctx)
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
Handlers["Cursed Chest"] = function(ctx)
	local a = ctx.actor
	applyAndRebuild(a, "Weakened", a.id)
	-- Treasure component shares the Treasure Chest reward path (best-effort).
	if ObjectEffectService._grantChestReward then
		ObjectEffectService._grantChestReward(a, ctx)
	end
	print(string.format("[ObjectEffectService] Cursed Chest | %s gains treasure + Weakened", a.name))
	return true, nil
end

--------------------------------------------------------------------
-- HAZARD / TRIGGERED (also usable via Interact where applicable)
--------------------------------------------------------------------
Handlers["Bear Trap"] = function(ctx)
	applyAndRebuild(ctx.actor, "Pinned", ctx.actor.id)
	print("[ObjectEffectService] Bear Trap | Pinned applied")
	return true, nil
end

Handlers["Snare Trap"] = function(ctx)
	applyAndRebuild(ctx.actor, "Pinned", ctx.actor.id)
	ctx.actor.remainingRt = (ctx.actor.remainingRt or 0) + 150
	print("[ObjectEffectService] Snare Trap | Pinned + RT Delay")
	return true, nil
end

Handlers["Spike Trap"] = function(ctx)
	-- Physical damage + Bleed. Damage via direct HP (environmental, no attacker stats).
	local a = ctx.actor
	local dmg = math.floor((a.maxHp or 0) * 0.10)
	a.currentHp = math.max(0, (a.currentHp or 0) - dmg)
	applyAndRebuild(a, "Bleed", a.id)
	print(string.format("[ObjectEffectService] Spike Trap | %d dmg + Bleed", dmg))
	return true, nil
end

local function explosionHandler(label)
	return function(ctx)
		local a, obj = ctx.actor, ctx.objInstance
		local x = obj.x or a.tileX
		local y = obj.y or a.tileY
		if _tileEffectService and _tileEffectService.QueueExplosion then
			-- 25% Max HP, 3x3 box per-source payload (objects_encounters / open_decisions).
			local payload = { damagePct = 0.25, element = "Fire", pattern = "box", radius = 1,
				scalesWith = "MaxHp", usesCombatFortune = false }
			_tileEffectService.QueueExplosion(x, y, 0, a.id, payload, ctx.allUnits, "box")
			print(string.format("[ObjectEffectService] %s | explosion queued at (%d,%d)", label, x, y))
			return true, nil
		end
		return false, label .. ": TileEffectService not available."
	end
end
Handlers["Land Mine"]   = explosionHandler("Land Mine")
Handlers["Bomb Barrel"] = explosionHandler("Bomb Barrel")

local function tileEffectHandler(effectId, label)
	return function(ctx)
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
Handlers["Treasure Chest"] = function(ctx)
	if ObjectEffectService._grantChestReward then
		return ObjectEffectService._grantChestReward(ctx.actor, ctx)
	end
	print("[ObjectEffectService] Treasure Chest | reward hook not wired (follow-up)")
	return true, nil
end

--------------------------------------------------------------------
-- EYE OF THE MAGI — attack two random opponents for 40% of their OWN max HP.
-- Direct HP%-damage (no weapon/operator stats). Deterministic pick via ctx.rng.
--------------------------------------------------------------------
Handlers["Eye of the Magi"] = function(ctx)
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
	for _, tgt in ipairs(picks) do
		local dmg = math.floor((tgt.maxHp or 0) * 0.40)
		tgt.currentHp = math.max(0, (tgt.currentHp or 0) - dmg)
		if tgt.currentHp <= 0 then tgt.isAlive = false end
		if BattleVisualBroadcaster then BattleVisualBroadcaster.UnitStateChanged(tgt) end
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
local function nearestEnemy(a, allUnits)
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
local function applySiegeOutcome(target, outcome)
	if not outcome then return end
	if outcome.finalDamage then
		target.currentHp = math.max(0, (target.currentHp or 0) - outcome.finalDamage)
		if target.currentHp <= 0 then target.isAlive = false end
	elseif outcome.finalHealing then
		target.currentHp = math.min(target.maxHp or (target.currentHp or 0),
			(target.currentHp or 0) + outcome.finalHealing)
	else
		return
	end
	if BattleVisualBroadcaster then BattleVisualBroadcaster.UnitStateChanged(target) end
end

Handlers["Ballista"] = function(ctx)
	local a = ctx.actor
	local wd = math.floor((a.weaponDamage or 10) * 2.5)  -- 250% operator weapon dmg

	-- Fire origin = the Ballista's tile; the bolt travels in a CARDINAL direction
	-- (DB: "penetrating bolt, cardinal") and pierces EVERY enemy along that line.
	local obj = ctx.objInstance
	local ox = (obj and obj.x) or a.tileX
	local oy = (obj and obj.y) or a.tileY

	-- Ask the player to AIM (reuse the facing ring, cardinal-only). If no prompter
	-- is injected (e.g. headless/AI context), fall back to auto-aim toward the
	-- nearest enemy's cardinal direction so the weapon still fires.
	local dir = nil
	if _directionPrompter then
		dir = _directionPrompter(a)
	end
	if not dir then
		local tgt = nearestEnemy(a, ctx.allUnits)
		if not tgt then return true, nil end
		local dx, dy = tgt.tileX - ox, tgt.tileY - oy
		if math.abs(dx) >= math.abs(dy) then
			dir = (dx >= 0) and "E" or "W"
		else
			dir = (dy >= 0) and "S" or "N"
		end
	end

	local vec = GameConstants.FACING_VECTORS[dir] or GameConstants.FACING_VECTORS.S
	-- Walk the line from the ballista tile outward; hit every enemy on it.
	local grid = GameConstants.TERRAIN_MAP
	local h = grid and #grid or 0
	local w = (h > 0 and grid[1]) and #grid[1] or 0
	-- Index living enemies by tile for O(1) line hits.
	local enemyAt = {}
	for _, u in ipairs(ctx.allUnits) do
		if u.isAlive and u.side ~= a.side and not u.isGroundTarget and u.tileX and u.tileY then
			enemyAt[u.tileX .. "," .. u.tileY] = u
		end
	end

	local hits = 0
	local cx, cy = ox + vec.dx, oy + vec.dy
	while cx >= 1 and cx <= w and cy >= 1 and cy <= h do
		local u = enemyAt[cx .. "," .. cy]
		if u and CombatResolver and CombatResolver.ResolveBasicAttack then
			local outcome = CombatResolver.ResolveBasicAttack(a, u, wd)
			applySiegeOutcome(u, outcome)
			hits = hits + 1
		end
		cx = cx + vec.dx
		cy = cy + vec.dy
	end

	print(string.format("[ObjectEffectService] Ballista | %s fires penetrating bolt %s from (%d,%d): %d hit(s) (250%% wpn)",
		a.name, dir, ox, oy, hits))
	return true, nil
end

Handlers["Catapult"] = function(ctx)
	local a = ctx.actor
	local tgt, dist = nearestEnemy(a, ctx.allUnits)
	if not tgt then return true, nil end
	if dist and dist > 6 then
		print("[ObjectEffectService] Catapult | nearest enemy out of range 6")
		return true, nil
	end
	-- 200% weapon dmg, Cross AOE (center + 4 adjacents). Hit the target tile's
	-- cross; each enemy on those tiles takes the resolved damage.
	local wd = math.floor((a.weaponDamage or 10) * 2.0)
	local crossTiles = { {tgt.tileX, tgt.tileY}, {tgt.tileX+1, tgt.tileY}, {tgt.tileX-1, tgt.tileY},
		{tgt.tileX, tgt.tileY+1}, {tgt.tileX, tgt.tileY-1} }
	local hitN = 0
	for _, u in ipairs(ctx.allUnits) do
		if u.isAlive and u.side ~= a.side and not u.isGroundTarget then
			for _, t in ipairs(crossTiles) do
				if u.tileX == t[1] and u.tileY == t[2] then
					if CombatResolver and CombatResolver.ResolveBasicAttack then
						local outcome = CombatResolver.ResolveBasicAttack(a, u, wd)
						applySiegeOutcome(u, outcome)
					end
					hitN = hitN + 1
					break
				end
			end
		end
	end
	print(string.format("[ObjectEffectService] Catapult | %s splashes %d enemy(s) around %s (200%% wpn, Cross)", a.name, hitN, tgt.name))
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
local function summonLevel(allUnits)
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
local function ringTiles(cx, cy, count, radius)
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

local function doSummon(ctx, specType, countMin, countMax, side, raceOverride, label)
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
			if BattleVisualBroadcaster and BattleVisualBroadcaster.UnitSpawned then
				BattleVisualBroadcaster.UnitSpawned(unit)
			end
		end
	end
	print(string.format("[ObjectEffectService] %s | summoned %d unit(s) at L%d", label, spawned, lvl))
	return true, nil
end

-- Dragon Utopia — summon 4-6 Dragons (Elite build, Dragonkin race).
Handlers["Dragon Utopia"] = function(ctx)
	return doSummon(ctx, "Elite", 4, 6, "Enemy", "RACE-DRAGONKIN", "Dragon Utopia")
end

-- Mimic — reveal: the chest object is REPLACED by ONE Mimic enemy (Elite build)
-- on the chest's own tile. Remove the object (and its blocker) first so the tile
-- is free; doSummon's nearest-free search then lands on that tile.
Handlers["Mimic"] = function(ctx)
	ObjectEffectService.RemoveObjectInstance(ctx.state, ctx.objInstance)
	return doSummon(ctx, "Elite", 1, 1, "Enemy", nil, "Mimic")
end

-- Refugee Camp REMOVED from the catalog (objects_encounters DB row 7:
-- "Refugee Camp removed 2026-10-03; War Machine Factory renamed Forge"). No
-- ObjectData entry, no handler. The Neutral-side summon path remains available
-- via doSummon(..., "Neutral") / SpawnReinforcement for any future neutral summon.

--------------------------------------------------------------------
-- FORGE (Blocker #2) — summon one Ballista or Catapult OBJECT on a tile within
-- radius 3 of the Forge. First functional build: auto-pick the first ring tile
-- not already holding an object (PlaceObjectInstance guards stacking + renders).
-- Interactive tile-pick UI deferred (consistent with siege auto-target).
--------------------------------------------------------------------
Handlers["Forge"] = function(ctx)
	local obj = ctx.objInstance
	local cx, cy = obj.x or ctx.actor.tileX, obj.y or ctx.actor.tileY
	-- Deterministic pick: Ballista on an even roll, Catapult on odd.
	local which = (ctx.rng:NextInteger(0, 1) == 0) and "Ballista" or "Catapult"
	-- Probe tiles within radius 3 (nearest-first), skipping the Forge's own tile,
	-- until one is free. radius=3 per objects_encounters (Forge).
	for _, t in ipairs(ringTiles(cx, cy, nil, 3)) do
		if not (t.x == cx and t.y == cy) then
			local inst = ObjectEffectService.PlaceObjectInstance(ctx.state, which, t.x, t.y)
			if inst then
				print(string.format("[ObjectEffectService] Forge | placed %s at (%d,%d)", which, t.x, t.y))
				return true, nil
			end
		end
	end
	print("[ObjectEffectService] Forge | no free tile within radius 3")
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
Handlers["Stone Pillar"] = function(ctx)
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
		local tElev = GameConstants.GetElevation(tx, ty)
		if tElev - baseElev >= 2 then
			break  -- fall stops short at the rise
		end
		table.insert(spanTiles, { x = tx, y = ty })
	end

	-- Reshape each reached tile to Rocky at base elevation (the fallen deck), and
	-- crush any unit standing on it.
	for _, t in ipairs(spanTiles) do
		GameConstants.SetTerrainId(t.x, t.y, "Rocky")
		if GameConstants.ELEVATION_MAP[t.y] then
			GameConstants.ELEVATION_MAP[t.y][t.x] = baseElev
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
				u.currentHp = math.max(0, (u.currentHp or 0) - dmg)
				if u.currentHp <= 0 then u.isAlive = false end
				u.remainingRt = (u.remainingRt or 0) + 100
				StatusService.ApplyStatus(u, "Pinned", a.id)
				if BattleVisualBroadcaster then BattleVisualBroadcaster.UnitStateChanged(u) end
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

	print(string.format("[ObjectEffectService] Stone Pillar | fell %d tile(s) toward (%d,%d) as Rocky span", #spanTiles, dx, dy))
	return true, nil
end

--------------------------------------------------------------------
-- CHAOS STATUE (Blocker #4) — generates ONE optional quest and stashes it on
-- state.pendingOptionalQuests for the battle-end flow to surface on the Quest
-- Board. QuestGenerator.Generate returns 3; we take the first. Deterministic
-- seed from ctx.rng. NOTE: battle-end surfacing of pendingOptionalQuests is a
-- small follow-up (no consumer reads it yet) — the quest is generated + stored,
-- not yet shown on the board. Flagged, not faked.
--------------------------------------------------------------------
Handlers["Chaos Statue"] = function(ctx)
	local state = ctx.state
	local playerLevel = (state and state.mapLevel) or 1
	local seed = (ctx.rng and ctx.rng:NextInteger(1, 2^31 - 1)) or os.time()
	local ok, quests = pcall(function()
		return QuestGenerator.Generate(playerLevel, seed)
	end)
	if ok and type(quests) == "table" and quests[1] then
		state.pendingOptionalQuests = state.pendingOptionalQuests or {}
		table.insert(state.pendingOptionalQuests, quests[1])
		print(string.format("[ObjectEffectService] Chaos Statue | generated optional quest '%s' (stashed; board surfacing is a follow-up)",
			tostring(quests[1].name)))
	else
		print("[ObjectEffectService] Chaos Statue | quest generation failed; no quest added")
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
Handlers["Glow Crystal"] = function(ctx)
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
Handlers["Crystal Ball"] = function(ctx)
	local state = ctx.state
	local revealed = 0
	if state and state.objects then
		for _, o in ipairs(state.objects) do
			if o.hidden then
				o.hidden = false
				if _objectRenderer then _objectRenderer(o) end
				revealed = revealed + 1
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
-- BLACK MARKET (Blocker #6) — DB intent: "opens a shop of six fixed discounted
-- high-tier items." HONEST SCOPE: there is NO persistent gold-balance economy in
-- the game yet (gold exists only as battle-end reward amounts; nothing stores or
-- spends a player's gold), and no in-battle shop UI. A true buy-with-gold shop
-- therefore cannot be built without first building a gold economy — a
-- prerequisite system, out of scope here (flagged, not faked).
--
-- What this DOES build with REAL systems: generate 6 high-tier items via
-- ItemGenerator and grant them to the player's inventory directly (a free cache,
-- not a paid shop). When a gold economy + shop UI exist, convert this to a
-- priced panel. Returns true; logs the scope honestly.
--------------------------------------------------------------------
local _blackMarketOpened = {}  -- per-battle, once per object instance
Handlers["Black Market"] = function(ctx)
	local state = ctx.state
	local playerId = state and state.ownerPlayerId
	local mapLevel = (state and state.mapLevel) or 1
	local objId = ctx.objInstance and ctx.objInstance.id or "blackmarket"
	if _blackMarketOpened[objId] then
		print("[ObjectEffectService] Black Market | already opened this battle")
		return true, nil
	end
	if not (playerId and InventoryService and ItemGenerator and ItemGenerator.GenerateFromPool) then
		print("[ObjectEffectService] Black Market | cannot grant items — missing playerId/InventoryService/ItemGenerator (gold-shop awaits economy system)")
		return true, nil
	end
	local granted = 0
	for k = 1, 6 do
		local seed = (ctx.rng and ctx.rng:NextInteger(1, 2^31 - 1)) or (os.time() + k)
		local ok, item = pcall(function()
			-- High-tier: Rare, item level scaled to map. Pool nil = any archetype.
			return ItemGenerator.GenerateFromPool(nil, mapLevel, "Rare", seed, "BlackMarket")
		end)
		if ok and item then
			InventoryService.AddItem(playerId, item)
			granted = granted + 1
		end
	end
	_blackMarketOpened[objId] = true
	print(string.format("[ObjectEffectService] Black Market | granted %d high-tier item(s) to inventory (FREE cache — paid-shop semantics await a gold economy system)", granted))
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

local function auraAppliesTo(auraDef, unit, objSide)
	if auraDef.side == "ALL" then return true end
	return unit.side == auraDef.side
end

-- Reconcile all passive auras against current unit positions. Call on battle
-- start and after any unit moves (CommandService Move hook).
function ObjectEffectService.ReconcileAuras(allUnits, state)
	if not state or not state.objects then return end
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
						applyAndRebuild(u, auraDef.status, objId)
					elseif (not inRange) and member[u.id] then
						member[u.id] = nil
						StatusService.RemoveStatus(u, auraDef.status)
						if EquipmentService.RebuildUnitStats then EquipmentService.RebuildUnitStats(u) end
						if BattleVisualBroadcaster then BattleVisualBroadcaster.UnitStateChanged(u) end
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------
-- TREASURE REWARD HOOK (best-effort). GenerateRewards needs a player id, a map
-- level, and a UNIQUE opportunity id. In the current combat context those are
-- not reliably reachable from a unit, so this is wired defensively: if the
-- state carries the needed context it generates; otherwise it logs an honest
-- deferral (object still consumed; reward is a small follow-up).
--------------------------------------------------------------------
function ObjectEffectService._grantChestReward(actor, ctx)
	local state = ctx.state
	local playerId = state and state.ownerPlayerId
	local mapLevel = state and state.mapLevel
	if playerId and mapLevel and RewardService and RewardService.GenerateRewards then
		local oppId = "chest_" .. tostring(ctx.objInstance and ctx.objInstance.id or tostring(os.clock()))
		local ok = pcall(function()
			RewardService.GenerateRewards(playerId, mapLevel, oppId)
		end)
		if ok then
			print("[ObjectEffectService] Treasure reward granted (opportunity " .. oppId .. ")")
			return true, nil
		end
	end
	print("[ObjectEffectService] Treasure reward DEFERRED — combat state lacks ownerPlayerId/mapLevel (follow-up).")
	return true, nil
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

local function necroStandsOnMap(state)
	local out = {}
	if state and state.objects then
		for _, obj in ipairs(state.objects) do
			if obj.type == "Necro Tome Stand" then table.insert(out, obj) end
		end
	end
	return out
end

-- Call after any action that may have killed a unit (battle loop hook).
function ObjectEffectService.ProcessDeaths(allUnits, state)
	local stands = necroStandsOnMap(state)
	if _aliveSnapshot == nil then
		_aliveSnapshot = {}
		for _, u in ipairs(allUnits) do
			if u.isAlive then _aliveSnapshot[u.id] = true end
		end
		return
	end
	for _, u in ipairs(allUnits) do
		local wasAlive = _aliveSnapshot[u.id]
		if wasAlive and not u.isAlive then
			if #stands > 0 and u.tileX and u.tileY then
				local triggered = false
				for _, st in ipairs(stands) do
					if math.abs(u.tileX - (st.x or 0)) <= 3 and math.abs(u.tileY - (st.y or 0)) <= 3 then
						triggered = true; break
					end
				end
				if triggered then
					local dmg = math.floor((u.maxHp or 0) * 0.10)
					for _, opp in ipairs(allUnits) do
						if opp.isAlive and opp.side ~= u.side and not opp.isGroundTarget then
							opp.currentHp = math.max(0, (opp.currentHp or 0) - dmg)
							if opp.currentHp <= 0 then opp.isAlive = false end
							if BattleVisualBroadcaster then BattleVisualBroadcaster.UnitStateChanged(opp) end
						end
					end
					print(string.format("[ObjectEffectService] Necro Tome Stand | %s died in range -> %d dark dmg to opponents", u.name, dmg))
				end
			end
		end
	end
	_aliveSnapshot = {}
	for _, u in ipairs(allUnits) do
		if u.isAlive then _aliveSnapshot[u.id] = true end
	end
end

--------------------------------------------------------------------
-- PUBLIC: Resolve one map-object interaction.
-- Returns ok, reason. CommandService has already validated candidacy and
-- charged AP/RT; this applies the EFFECT only. Usage ("Once"/"Once per turn")
-- is enforced here so a consumed object is rejected before its effect runs.
--------------------------------------------------------------------
function ObjectEffectService.Resolve(actor, objInstance, state, allUnits)
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

	local ok, reason = handler({
		actor = actor, objInstance = objInstance,
		objDef = objDef, state = state, allUnits = allUnits, rng = rng,
	})

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
function ObjectEffectService.ClearTurnUsage(unitId)
	for objId, uid in pairs(_usedThisTurn) do
		if uid == unitId then
			_usedThisTurn[objId] = nil
		end
	end
end

return ObjectEffectService
