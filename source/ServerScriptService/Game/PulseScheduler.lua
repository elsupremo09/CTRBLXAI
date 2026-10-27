--!strict
-- PulseScheduler.lua
-- CTRBLXAI | Fixed-interval CT pulse engine for tile-anchored deployables and
-- delayed-burst consumables (server-only). Added 2026-10-26.
--
-- WHY THIS MODULE EXISTS:
-- Several consumables repeat an effect on the battle clock rather than once at
-- use: Healing Beacon ("four pulses every 400 CT"), Poison Cloud Vent ("pulses
-- at 400/800/1200 CT"), and the delayed-burst damage items (Thermite "at 0, 400,
-- 800, 1200 CT"; Meteor Marker "after 300 CT"; Tesla Pylon "at 500 and 1000 CT").
-- No engine piece drove fixed-CT repeats, so all of them deferred. This module is
-- the single place that owns scheduled pulses; it hooks the ONE CT-advance point
-- (BattleCoordinator.AdvanceClock) exactly like StatusService/TileEffectService
-- already do, and routes each pulse's effect to the system that owns it.
--
-- It is tile-anchored and stateless-per-call: all live data lives on
-- state.pulseSchedule (serializable), so it needs no bespoke persistence. Unit-
-- anchored repeaters (Sentry Turret shots, Mender Drone heals) are SUMMON-driven,
-- not pulse-driven, and are handled by the summon pass, not here.
--
-- Dependencies are INJECTED (cycle-free): this module requires nothing that
-- requires it. A pulse whose dependency is absent no-ops (logged), never crashes.

local PulseScheduler = {}

--------------------------------------------------
-- INJECTED DEPENDENCIES
--------------------------------------------------
local UnitSchema: any = nil
local StatusService: any = nil
local TileEffectService: any = nil
local GameConstants: any = nil
local TargetingService: any = nil  -- optional: line-of-sight for pulseRequiresLoS (Sentry Turret)
local ObjectEffectService: any = nil  -- optional: hidden-object reveal for kind "reveal" (drones)

-- Timed-hit resolver (user ruling 2026-10-26): injected by CommandService.SetPulseScheduler
-- (ItemEffectService.ResolveTimedHit) so damage pulses go through Defense / element rules.
-- nil = old direct-damage path (logged once per pulse).
local _hitResolver: any = nil
-- Bridge restorer (2026-10-27, ENV-010 Bridge Projector): injected by CommandService.
local _bridgeRestorer: any = nil
function PulseScheduler.SetBridgeRestorer(fn: any)
	_bridgeRestorer = fn
end
function PulseScheduler.SetHitResolver(fn: any)
	_hitResolver = fn
end

function PulseScheduler.Init(deps: any)
	UnitSchema    = deps.UnitSchema
	StatusService = deps.StatusService
	TileEffectService = deps.TileEffectService
	GameConstants = deps.GameConstants
	TargetingService = deps.TargetingService
	ObjectEffectService = deps.ObjectEffectService
end

--------------------------------------------------
-- REGISTRATION
--------------------------------------------------
-- Register a repeating pulse anchored at a tile. Called by the deploy/item path
-- at use time. `spec` fields:
--   ownerId      : the using unit's id (for side logic + cleanup; required)
--   side         : the owner's side string (required)
--   tileX, tileY : anchor tile (required)
--   kind         : "heal" | "damage" | "status"
--   recipients   : "allies" | "enemies" (who in radius is affected)
--   radius       : Chebyshev radius (>=0; 0 = anchor tile only)
--   amount       : flat HP for heal/damage (already computed by the caller)
--   element      : element tag for damage (optional; display/resist)
--   statusId     : status to apply for kind=="status"
--   statusCt     : CT duration override for the status (optional)
--   intervalCt   : CT between pulses (>0)
--   pulses       : total number of pulses to fire (>=1)
--   fireImmediate: if true, the first pulse fires at the next tick's accrual
--                  reaching interval; "at 0 CT" items set offsetCt=0 (default).
-- Returns the stored entry (also appended to state.pulseSchedule).
-- Forward declaration: Register's fireImmediate path (below) calls firePulse, which is
-- defined later in the FIRING section. In Lua a local is only visible AFTER its
-- declaration, so without this forward-declare that call would hit a nil global.
local firePulse: any

function PulseScheduler.Register(state: any, spec: any): any
	if not (state and spec and spec.ownerId and spec.tileX and spec.tileY) then
		return nil
	end
	if (spec.intervalCt or 0) <= 0 or (spec.pulses or 0) < 1 then
		return nil
	end
	state.pulseSchedule = state.pulseSchedule or {}
	local entry = {
		ownerId = spec.ownerId,
		side = spec.side,
		tileX = spec.tileX,
		tileY = spec.tileY,
		kind = spec.kind or "damage",
		recipients = spec.recipients or ((spec.kind == "heal" or spec.kind == "relocate") and "allies" or "enemies"),
		radius = spec.radius or 0,
		amount = spec.amount or 0,
		amountKind = spec.amountKind or "flat",  -- "flat" | "pctMaxHp" (per-target % of Max HP)
		element = spec.element,
		statusId = spec.statusId,
		statusCt = spec.statusCt,
		intervalCt = spec.intervalCt,
		tileEffect = spec.tileEffect,      -- kind "tileEffect": effect id placed on each tile
		tileEffectCt = spec.tileEffectCt,  -- optional lifetime override for that effect
		itemId = spec.itemId,              -- source item (one-per-type deployable limit)
		-- Item devices (2026-10-26): a pulse anchored to a placed device UNIT follows it and
		-- stops when it is destroyed. targetMode picks ONE recipient: "nearest" (Sentry
		-- Turret, Tesla Pylon) or "lowestHp" (Mender Drone, lowest HP %); default "all".
		anchorUnitId = spec.anchorUnitId,
		ringFalloff = spec.ringFalloff,  -- {centre, ring1, ring2, ...} damage fractions
		shape = spec.shape,  -- "cross": only tiles in a straight line from the centre (Impact N)
		targetMode = spec.targetMode or "all",
		requiresLoS = spec.requiresLoS == true,
		remainingPulses = spec.pulses,
		totalPulses = spec.pulses,  -- Maintenance Tool / Repair refill (2026-10-26)
		accCt = spec.offsetCt or 0,  -- accrued CT toward the next pulse
	}
	table.insert(state.pulseSchedule, entry)

	-- fireImmediate: some items burst once AT USE (CT 0) and then on the interval
	-- (e.g. Thermite "At 0, 400, 800, 1200 CT"). The normal schedule fires first at
	-- one interval; this fires one extra pulse now and consumes one of the count, so
	-- the remaining (pulses-1) still land on the interval. Items that start at the
	-- first interval (Healing Beacon "every 400 CT", Poison Cloud "at 400/800/1200")
	-- leave fireImmediate false and are unaffected.
	if spec.fireImmediate and entry.remainingPulses > 0 then
		firePulse(state, entry)
		entry.remainingPulses -= 1
		if entry.remainingPulses <= 0 then
			-- single at-use burst only: drop the spent entry so the clock does nothing further
			for i = #state.pulseSchedule, 1, -1 do
				if state.pulseSchedule[i] == entry then table.remove(state.pulseSchedule, i) break end
			end
		end
	end

	return entry
end

-- Resolve the per-target amount for a pulse: a flat authored value, or a percentage
-- of THIS target's Max HP (so "heal 5% Max HP" / "deal 10% Max HP" scale per unit).
local function resolveAmount(entry: any, unit: any): number
	if entry.amountKind == "pctMaxHp" then
		return math.max(0, math.round((unit.maxHp or 0) * (entry.amount or 0) / 100))
	end
	return math.max(0, math.round(entry.amount or 0))
end

--------------------------------------------------
-- FIRING
--------------------------------------------------
-- Anchor unit of a device pulse (nil when the entry is tile-anchored).
local function findAnchor(state: any, entry: any): any
	if not entry.anchorUnitId then return nil end
	for _, u in ipairs(state.units or {}) do
		if u.id == entry.anchorUnitId then return u end
	end
	return nil
end

-- Collect living units in the entry's radius on the recipient side.
local function collectTargets(state: any, entry: any): { any }
	local out = {}
	for _, u in ipairs(state.units or {}) do
		-- Devices never receive their own side's pulses (a Mender Drone does not heal a
		-- turret or itself); enemy devices can still be shot.
		local skipDevice = u.isItemDevice and entry.recipients == "allies"
		if u.isAlive and u.tileX and u.tileY and not skipDevice then
			local inRange = math.max(math.abs(u.tileX - entry.tileX), math.abs(u.tileY - entry.tileY)) <= entry.radius
				and (entry.shape ~= "cross" or u.tileX == entry.tileX or u.tileY == entry.tileY)
			if inRange then
				local sideOk
				if entry.recipients == "allies" then
					sideOk = (u.side == entry.side)
				else
					sideOk = (u.side ~= entry.side)
				end
				if sideOk then
					table.insert(out, u)
				end
			end
		end
	end
	return out
end

-- Narrow the recipients to ONE unit for single-target modes. "nearest": smallest
-- Chebyshev distance, ties -> lower HP %, then id. "lowestHp": lowest HP %, ties ->
-- nearer, then id. requiresLoS drops recipients without Direct line of sight first.
local function selectTargets(state: any, entry: any, targets: { any }): { any }
	local mode = entry.targetMode or "all"
	if mode == "all" then return targets end
	local pool = {}
	for _, u in ipairs(targets) do
		local seen = true
		if entry.requiresLoS and TargetingService and TargetingService.HasLineOfSight then
			seen = TargetingService.HasLineOfSight(entry.tileX, entry.tileY, u.tileX, u.tileY,
				state.units, nil, "Direct", entry.side)
		end
		if seen then table.insert(pool, u) end
	end
	if #pool == 0 then return pool end
	local function dist(u)
		return math.max(math.abs(u.tileX - entry.tileX), math.abs(u.tileY - entry.tileY))
	end
	local function pct(u)
		return (u.currentHp or 0) / math.max(1, u.maxHp or 1)
	end
	table.sort(pool, function(a, b)
		if mode == "lowestHp" then
			if pct(a) ~= pct(b) then return pct(a) < pct(b) end
			if dist(a) ~= dist(b) then return dist(a) < dist(b) end
		else
			if dist(a) ~= dist(b) then return dist(a) < dist(b) end
			if pct(a) ~= pct(b) then return pct(a) < pct(b) end
		end
		return tostring(a.id) < tostring(b.id)
	end)
	return { pool[1] }
end

-- Fire one pulse of one entry. Routes to the owning system. Records per-unit
-- events on state.pulseEvents so the driver (Main) can refresh client bars /
-- show floaters, matching the state.ctStatusUnits / state.dotEvents convention.
function firePulse(state: any, entry: any)
	-- Device pulse: fire from the device's current tile; a destroyed device fires nothing.
	if entry.anchorUnitId then
		local anchor = findAnchor(state, entry)
		if not (anchor and anchor.isAlive) then return end
		entry.tileX, entry.tileY = anchor.tileX, anchor.tileY
	end
	-- kind "tileEffect" (2026-10-26, Poison Cloud Vent): place the effect on every tile
	-- within the radius of the anchor (TileEffectService bounds-checks and runs the
	-- normal element reactions), instead of acting on units directly.
	-- kind "relocate" (2026-10-26, Emergency Extraction Beacon, user ruling 5): allied
	-- units within the radius are moved to free tiles of their own side's deployment area.
	-- Free = no living unit, not blocked, not impassable. Units that find no free tile stay.
	-- kind "reveal" (Scout / Survey Drone; user ruling 2026-10-27): ENEMIES of the drone's
	-- owner in the radius lose Hide and hidden enemy traps there are shown. Recorded as
	-- pulseEvents kind "reveal" so Main tells clients the Hide status ended.
	if entry.kind == "reveal" then
		local r = entry.radius or 0
		local tileSet = {}
		for dy = -r, r do
			for dx = -r, r do
				tileSet[(entry.tileX + dx) .. "," .. (entry.tileY + dy)] = true
			end
		end
		state.pulseEvents = state.pulseEvents or {}
		for _, u in ipairs(state.units or {}) do
			if u.isAlive and u.tileX and tileSet[u.tileX .. "," .. u.tileY]
				and (entry.side == nil or u.side ~= entry.side)
				and StatusService and StatusService.HasStatus(u, "Hide") and StatusService.RemoveStatus(u, "Hide") then
				table.insert(state.pulseEvents, { unit = u, kind = "reveal" })
			end
		end
		if ObjectEffectService and ObjectEffectService.RevealHiddenInArea then
			ObjectEffectService.RevealHiddenInArea(state, tileSet, entry.side)
		end
		return
	end
	if entry.kind == "relocate" then
		local deploy = (entry.side == "Player") and state.playerDeployTiles or state.enemyDeployTiles
		if not deploy or #deploy == 0 then return end
		state.pulseEvents = state.pulseEvents or {}
		local function tileFree(x, y)
			if GameConstants and (GameConstants.IsBlocked(x, y) or GameConstants.IsImpassableTerrain(x, y)) then
				return false
			end
			for _, o in ipairs(state.units or {}) do
				if o.isAlive and o.tileX == x and o.tileY == y then return false end
			end
			return true
		end
		local movers = {}
		for _, u in ipairs(collectTargets(state, entry)) do
			-- Phase Lock (user ruling 2026-10-27): a locked unit cannot be relocated.
			if not (StatusService and StatusService.IsRelocationLocked and StatusService.IsRelocationLocked(u)) then
				table.insert(movers, u)
			end
		end
		for _, u in ipairs(movers) do
			for _, t in ipairs(deploy) do
				if tileFree(t.x, t.y) then
					local ox, oy = u.tileX, u.tileY
					u.tileX, u.tileY = t.x, t.y
					table.insert(state.pulseEvents, { unit = u, kind = "relocate", oldX = ox, oldY = oy })
					break
				end
			end
		end
		return
	end
	if entry.kind == "tileEffect" then
		if TileEffectService and TileEffectService.ApplyTileEffect and entry.tileEffect then
			local r = entry.radius or 0
			for dy = -r, r do
				for dx = -r, r do
					TileEffectService.ApplyTileEffect(entry.tileX + dx, entry.tileY + dy,
						entry.tileEffect, entry.ownerId, state.units, nil, entry.tileEffectCt)
				end
			end
		end
		return
	end
	-- targetMode "anchor" (2026-10-27, REC-007/008 heal-over-time): only the unit the pulse
	-- follows, whatever its side.
	local targets
	if entry.targetMode == "anchor" then
		local anchor = findAnchor(state, entry)
		targets = (anchor and anchor.isAlive) and { anchor } or {}
	else
		targets = selectTargets(state, entry, collectTargets(state, entry))
	end
	if #targets == 0 then return end
	state.pulseEvents = state.pulseEvents or {}

	for _, u in ipairs(targets) do
		if entry.kind == "heal" and UnitSchema and UnitSchema.ApplyHealing then
			local before = u.currentHp or 0
			UnitSchema.ApplyHealing(u, resolveAmount(entry, u))
			local healed = (u.currentHp or 0) - before
			if healed ~= 0 then
				table.insert(state.pulseEvents, { unit = u, kind = "heal", amount = healed, element = entry.element })
			end
		elseif entry.kind == "damage" and UnitSchema and UnitSchema.ApplyDamage then
			-- Pulse/DoT-style damage is applied DIRECTLY (not through CombatResolver.ApplyOutcome)
			-- so it cannot re-trigger reactions/counters/reflects -- same TRG-010 rule the tile
			-- DoT and detonation paths follow. Deterministic flat amount (already computed).
			local dmg = resolveAmount(entry, u)
			-- Ring falloff (Meteor Marker): fraction by Chebyshev ring around the anchor.
			if type(entry.ringFalloff) == "table" then
				local ring = math.max(math.abs(u.tileX - entry.tileX), math.abs(u.tileY - entry.tileY))
				dmg = math.round(dmg * (entry.ringFalloff[ring + 1] or 0))
			end
			if dmg > 0 then
				-- Normal damage rules (Defense, element, wards) via the item hit pipeline, using
				-- the owner as the attacker. Falls back to direct damage only if no resolver is
				-- wired or the owner is no longer in the battle roster.
				local owner = nil
				if _hitResolver then
					for _, o in ipairs(state.units or {}) do
						if o.id == entry.ownerId then owner = o break end
					end
				end
				if owner then
					dmg = _hitResolver(owner, u, entry.element, dmg, entry.itemId, true) or 0  -- the item owns the hit
				else
					UnitSchema.ApplyDamage(u, dmg)
				end
				table.insert(state.pulseEvents, { unit = u, kind = "damage", amount = dmg, element = entry.element })
				if not u.isAlive then
					u._killedBy = u._killedBy or entry.ownerId
				end
			end
		elseif entry.kind == "status" and StatusService and StatusService.ApplyStatus and entry.statusId then
			StatusService.ApplyStatus(u, entry.statusId, entry.ownerId, nil, entry.statusCt)
			table.insert(state.pulseEvents, { unit = u, kind = "status", statusId = entry.statusId })
		end
	end
end

--------------------------------------------------
-- CT TICK (hooked by BattleCoordinator.AdvanceClock)
--------------------------------------------------
-- Advance all scheduled pulses by ctElapsed, firing each entry as many times as
-- the elapsed CT crosses its interval (so a large CT jump between turns still
-- fires every due pulse, in order). Spent entries (remainingPulses == 0) are
-- removed. Entries whose owner is gone are dropped (deployable destroyed).
function PulseScheduler.ProcessCtTick(state: any, ctElapsed: any)
	if not state or not ctElapsed or ctElapsed <= 0 then
		return
	end
	local sched = state.pulseSchedule
	if sched and #sched > 0 then
		for i = #sched, 1, -1 do
			local entry = sched[i]
			-- A device pulse whose device is gone is dropped (destroyed / replaced / expired).
			local anchorGone = false
			if entry.anchorUnitId then
				local anchor = findAnchor(state, entry)
				anchorGone = not (anchor and anchor.isAlive)
			end
			if anchorGone then
				table.remove(sched, i)
			else
				entry.accCt = (entry.accCt or 0) + ctElapsed
				while entry.remainingPulses > 0 and entry.accCt >= entry.intervalCt do
					entry.accCt -= entry.intervalCt
					firePulse(state, entry)
					entry.remainingPulses -= 1
				end
				if entry.remainingPulses <= 0 then
					table.remove(sched, i)
				end
			end
		end
	end

	-- Item device lifespans (2026-10-26): runs AFTER the pulses so a device's final pulse
	-- at its last CT mark still fires before it is removed (Sentry Turret 3rd shot at
	-- 1500 CT, Mender Drone 2nd heal at 1000 CT). An expired device is KO'd (no rewards:
	-- devices are rewardEligible=false); Main's pulse-event drain removes it from the
	-- board through the normal KO broadcast.
	for _, u in ipairs(state.units or {}) do
		if u.isItemDevice and u.isAlive and u.deviceLifeCt then
			u.deviceLifeCt -= ctElapsed
			if u.deviceLifeCt <= 0 then
				u.isAlive = false
				u.currentHp = 0
				state.pulseEvents = state.pulseEvents or {}
				table.insert(state.pulseEvents, { unit = u, kind = "expire" })
				print(string.format("[PulseScheduler] device %s expired (lifespan over)", tostring(u.name)))
			end
		end
	end

	-- Energy bridges (ENV-010): after their time runs out they end as soon as no unit stands
	-- on them ("cannot expire while occupied").
	-- Suppression Field zones (CON-020) run down on the battle clock.
	local zones = state.suppressionZones
	if zones then
		for i = #zones, 1, -1 do
			zones[i].ct -= ctElapsed
			if zones[i].ct <= 0 then table.remove(zones, i) end
		end
	end
	-- Reveal zones (UTI-003 Scanner Lens, user ruling 2026-10-27): while one lasts, enemies of
	-- its owner inside lose Hide and hidden traps there are shown; then its time runs down.
	if ObjectEffectService and ObjectEffectService.GetRevealZones then
		for _, z in ipairs(ObjectEffectService.GetRevealZones()) do
			for _, u in ipairs(state.units or {}) do
				if u.isAlive and u.tileX and u.side ~= z.side and z.tiles[u.tileX .. "," .. u.tileY]
					and StatusService and StatusService.HasStatus(u, "Hide") and StatusService.RemoveStatus(u, "Hide") then
					state.pulseEvents = state.pulseEvents or {}
					table.insert(state.pulseEvents, { unit = u, kind = "reveal" })
				end
			end
			ObjectEffectService.RevealHiddenInArea(state, z.tiles, z.side)
		end
		ObjectEffectService.TickRevealZones(ctElapsed)
	end
	-- Timed placed objects (DEP-004 Hardlight Wall segments) are removed when their time is up.
	if state.objects and ObjectEffectService and ObjectEffectService.ExpireObject then
		for i = #state.objects, 1, -1 do
			local o = state.objects[i]
			if o and o.lifeCt then
				o.lifeCt -= ctElapsed
				if o.lifeCt <= 0 then ObjectEffectService.ExpireObject(state, o) end
			end
		end
	end

	local bridges = state.bridges
	if bridges and #bridges > 0 then
		for i = #bridges, 1, -1 do
			local b = bridges[i]
			b.ct -= ctElapsed
			if b.ct <= 0 then
				local occupied = false
				for _, u in ipairs(state.units or {}) do
					if u.isAlive and u.tileX then
						for _, t in ipairs(b.tiles or {}) do
							if t.x == u.tileX and t.y == u.tileY then occupied = true break end
						end
					end
					if occupied then break end
				end
				if not occupied and _bridgeRestorer then
					_bridgeRestorer(state, b)
					table.remove(bridges, i)
				end
			end
		end
	end
end

-- Drop the pulses one unit placed with one specific item (one-per-type limit for
-- deployables that act on their own, user ruling 2026-10-26: a new one replaces the old).
function PulseScheduler.CancelByOwnerItem(state: any, ownerId: any, itemId: any)
	local sched = state and state.pulseSchedule
	if not sched or itemId == nil then return end
	for i = #sched, 1, -1 do
		if sched[i].ownerId == ownerId and sched[i].itemId == itemId then
			table.remove(sched, i)
		end
	end
end

-- Drop all pulses owned by a unit id (called when a deployable/owner is removed).
-- Refill a device's timed effects to full (Maintenance Tool / Repair, 2026-10-26).
function PulseScheduler.RefreshByAnchor(state: any, anchorUnitId: any)
	for _, e in ipairs((state and state.pulseSchedule) or {}) do
		if e.anchorUnitId == anchorUnitId and e.totalPulses then
			e.remainingPulses = e.totalPulses
			e.accCt = 0
		end
	end
end

function PulseScheduler.CancelByOwner(state: any, ownerId: any)
	local sched = state and state.pulseSchedule
	if not sched then return end
	for i = #sched, 1, -1 do
		if sched[i].ownerId == ownerId then
			table.remove(sched, i)
		end
	end
end

return PulseScheduler
