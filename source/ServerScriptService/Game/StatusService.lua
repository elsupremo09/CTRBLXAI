-- StatusService.lua
-- CTRBLXAI | Slice 3
--
-- Manages the lifecycle of status effects on units.
--
-- Channeling interrupt: ApplyStatus returns a "disruptsChannel" flag
-- when a disabling status is applied. The CALLER (Main loop) is
-- responsible for calling BattleCoordinator.InterruptChanneling()
-- because StatusService cannot require BattleCoordinator (circular dep).
--
-- Status instance shape:
--   { id = "Slow", remainingTurns = 3, sourceUnitId = "unit_enemy" }
--   { id = "Poison", remainingTurns = 5, sourceUnitId = "unit_enemy" }
--   { id = "Burn", remainingTurns = 3, sourceUnitId = "unit_enemy", storedBurn = 12 }

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

local RaceData = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Content")
		:WaitForChild("RaceData")
)

-- Perks & Flaws Phase 2: DoT-received trait multipliers (Toxin Filter / Festering,
-- Iron Stomach / Weak Stomach, Fire-Hardened / Flammable, ...). TraitEffectService
-- depends only on ReplicatedStorage content modules, so there is no require cycle.
local TraitEffectService = require(script.Parent.TraitEffectService)

local StatusService = {}

-- Weather Burn-suppression (user ruling 2026-10-04: Rain + Snow Storm prevent Burn
-- effects). WeatherService pushes this flag on each re-roll so IsImmune blocks Burn
-- APPLICATION while the active weather suppresses it — without StatusService
-- requiring WeatherService (one-way, no cycle).
local _weatherBurnSuppressed = false
-- Ward Totem aura (SKL-SUMMON-WARD-TOTEM): allied units within radius 2 of a living
-- Totem multiply their Debuff Resistance Multiplier by 0.80. Same-caster max 1 totem;
-- totems from different casters each apply independently.
local _auraUnits = nil
function StatusService.SetAuraUnitsProvider(fn) _auraUnits = fn end
-- Live battle unit list (nil outside battle). Used by doctrine proximity reads. 2026-10-28.
function StatusService.GetAuraUnits() return _auraUnits and _auraUnits() or nil end
local function findUnitById(id)
	if not id or id == "unknown" or not _auraUnits then return nil end
	local units = _auraUnits()
	if type(units) ~= "table" then return nil end
	for _, u in ipairs(units) do
		if u.id == id then return u end
	end
	return nil
end
-- Plague Doctor Virulence: Poison / Venom ticks from this source +25%. Deferred require (cycle).
local function doctrinePoisonTickMult(inst)
	local src = inst and findUnitById(inst.sourceUnitId)
	if not src then return 1 end
	return (require :: any)(script.Parent.DoctrinePassiveService).GetPoisonTickModifier(src)
end

--------------------------------------------------
-- STATUS CONFLICT RULES (2026-10-07, user ruling)
-- Enforced inside ApplyStatus so EVERY source (attacks, skills, weather, items,
-- Dev grant) obeys them. Elemental DAMAGE modifiers stay in CombatResolver.
--   cancel : applying X while Y is active removes Y and X is NOT applied
--            (Haste <-> Slow cancel each other out).
--   removes: applying X removes the listed statuses, then X is applied
--            (DB elements_statuses 57/73/74: Water removes Burn; Fire removes
--            Wet and Frozen; Ice converts Wet -> Frozen).
--------------------------------------------------
local STATUS_CANCELS = table.freeze({
	Haste = "Slow",
	Slow  = "Haste",
})

local STATUS_REMOVES = table.freeze({
	Wet    = table.freeze({ "Burn" }),
	Burn   = table.freeze({ "Wet", "Frozen" }),
	Frozen = table.freeze({ "Wet" }),
})

-- Injected removal notifier (DI, mirrors SetAuraUnitsProvider): StatusService
-- cannot require BattleVisualBroadcaster (it requires us). Main wires this so the
-- client drops the status pill when a conflict rule removes a status.
-- TRG-016 (2026-10-28): Break added or removed on a Twinblade switches the off-hand weapon off / on
-- IMMEDIATELY (one stat rebuild per Break state change). Deferred require (cycle-safe).
-- Also (USER RULING 2026-10-28): Break turns off ALL traits, including the ones applied by the stat
-- rebuild (stat %, HP/MP, armor, weapon Specialist/Klutz, force, stability...), so any unit with a
-- trait is rebuilt once when Break starts or ends. HP/MP are only capped, never raised.
local function syncBreakEquipment(unit, statusId)
	if statusId ~= "Break" or not unit then return end
	-- Summons / item devices / objects carry an authored stat snapshot and no Break-able passives;
	-- never rebuild them.
	if unit.isSummon or unit.isItemDevice or unit.isObject then return end
	local hasTraits = (type(unit.perkIds) == "table" and #unit.perkIds > 0)
		or (type(unit.drawbackIds) == "table" and #unit.drawbackIds > 0)
	-- USER RULING 2026-10-28 (DB project_rules 35/47/205): Break also switches off the race passive
	-- (incl. its stat changes, e.g. Avian STR -15%, Ogre WT +20%) and the doctrine passive (incl.
	-- the Chemist / Artificer item slot and Artificer -1 skill range). Those are applied in the stat
	-- rebuild, so units with a race or doctrine are rebuilt too. Race TAGS stay on.
	local hasRaceOrDoctrine = unit.raceId ~= nil or unit.doctrineId ~= nil
	if hasTraits or hasRaceOrDoctrine then
		(require :: any)(script.Parent.EquipmentService).RebuildUnitStats(unit)  -- also re-syncs dual wield
	elseif unit.doctrineId == "DOC-TWINBLADE" then
		(require :: any)(script.Parent.DoctrinePassiveService).SyncDualWield(unit)
	end
end
-- BUG-218 (batch 18, Tester pass 7: Timesovereign 289/365 after Break was removed, "usually /397"): a status that
-- changes primary stats (Weakened -10% all, Giant Transformation, Rush, Enlightened, any def with statPctMod such
-- as Banner Blessing) is only read by EquipmentService.RebuildUnitStats (GetStatusStatModifiers), but nothing
-- rebuilt the unit when such a status started or ended in battle (only the Dev GrantStatus / RemoveStatus
-- commands did). Weakened sat on the unit with no effect on VIT / Max HP until the next unrelated rebuild (here
-- the Break removal), which then dropped Max HP by 32 at once. Now the unit is rebuilt when such a status is
-- applied, re-applied, stacked or ends (same rebuild and same "HP only capped, never raised" rule as Break).
local REBUILD_STAT_STATUSES = { Weakened = true, ["Giant Transformation"] = true, Rush = true, Enlightened = true }
local function syncStatStatus(unit, statusId)
	if not unit or statusId == nil or type(unit.statusInstances) ~= "table" then return end
	if not REBUILD_STAT_STATUSES[statusId] then
		local def = GameConstants.STATUSES[statusId]
		if not (def and def.statPctMod) then return end
	end
	-- Summons / item devices / objects carry an authored stat snapshot: never rebuilt (same guard as Break).
	if unit.isSummon or unit.isItemDevice or unit.isObject then return end
	-- BUG-219 (batch 18b, Tester W1): a rebuild that caps current HP (Weakened on a full-HP unit, a VIT buff ending
	-- at full HP) gets its own log line, and the loss is recorded on the unit (_statCapLoss) so BattleTurnController
	-- does not count it as hit damage. Deferred require: BattleVisualBroadcaster requires us (cycle-safe at call time).
	local _pre = unit.currentHp or 0
	(require :: any)(script.Parent.EquipmentService).RebuildUnitStats(unit)
	local _cap = _pre - (unit.currentHp or 0)
	if _cap > 0 then
		unit._statCapLoss = (unit._statCapLoss or 0) + _cap
		local _okB, _bvb = pcall(require, script.Parent.BattleVisualBroadcaster)
		if _okB and _bvb and _bvb.MaxHpCapped then _bvb.MaxHpCapped(unit, _cap, statusId) end
	end
end
-- A status ENDED (removed, expired, cleansed, purged, dispelled): Break sync, plus Oversleep --
-- DB weapons_equipment 153: when Sleep ends the unit gains Sleep Immunity until the end of its next
-- ready turn. One place for every removal path (2026-10-29, Tester FAIL fix: cleanses were missed).
-- Never called on APPLY (syncBreakEquipment alone is), so applying Sleep does not grant immunity.
local function onStatusEnded(unit, statusId)
	syncBreakEquipment(unit, statusId)
	syncStatStatus(unit, statusId)  -- BUG-218
	if statusId == "Sleep" and unit and unit.isAlive ~= false and unit.statusInstances then
		StatusService.ApplyStatus(unit, "Sleep Immunity", unit.id)
	end
	-- Freeze weapon passive (weapons_equipment 156, DESIGNER RULING 2026-11-21): when a WEAPON-applied
	-- Frozen ends (expiry, Fire, cleanse) the unit gains Thawed for 2 turns. Skill / item / terrain
	-- Frozen never set _weaponFrozen, so they end without Thawed. Source "WeaponFreeze" (not a unit id)
	-- so no applier doctrine / Lore changes its fixed 2 turns.
	if statusId == "Frozen" and unit and unit._weaponFrozen then
		unit._weaponFrozen = nil
		if unit.isAlive ~= false and unit.statusInstances then
			StatusService.ApplyStatus(unit, "Thawed", "WeaponFreeze")
		end
	end
end

-- For status removals done outside this module (augment cleanses).
function StatusService.NotifyStatusRemoved(unit, statusId)
	onStatusEnded(unit, statusId)
end

-- Bleed -> Raptured -> Wounded -> Bleed chain loop guard (2026-10-29): reapplying when all three are
-- present used to recurse forever (stack overflow). Each status in one chain now refreshes once.
local _chainVisited: any = nil

local _onConflictRemoved = nil
function StatusService.SetConflictRemovedHandler(fn) _onConflictRemoved = fn end
-- BUG-140 (BUG-HUNT-09 / BUG-HUNT-16, 2026-11-22): a status that runs out ON ITS OWN (turn tick in
-- TickStatuses, CT tick in ProcessCtTick) was removed silently. The battle-log snapshot kept it, so the
-- next caused diff of that unit named a wrong cause ("Hero is no longer War Cry (Burning tile)",
-- "Taunt: 3 units are no longer Pinned"). Main injects the broadcaster hook (ARC-004; StatusService
-- cannot require the broadcaster). Called once per naturally expired status id. nil = no-op.
local _onNaturalExpiry = nil
function StatusService.SetExpiredHandler(fn) _onNaturalExpiry = fn end

local function removeByConflict(unit, removedId, causeId)
	if StatusService.RemoveStatus(unit, removedId) then
		print(`[StatusService] {removedId} on {unit.name} removed by {causeId} (conflict rule)`)
		if _onConflictRemoved then _onConflictRemoved(unit, removedId) end
	end
end

local function wardTotemMult(unit)
	local list = _auraUnits and _auraUnits() or nil
	if type(list) ~= "table" then return 1.0 end
	local m = 1.0
	for _, u in ipairs(list) do
		if u ~= unit and u.isAlive and u.isSummon and u.auraSpec and u.side == unit.side then
			local r = u.auraSpec.radius or 2
			if math.max(math.abs(u.tileX - unit.tileX), math.abs(u.tileY - unit.tileY)) <= r then
				m = m * (u.auraSpec.debuffResistMult or 1.0)
			end
		end
	end
	return m
end
StatusService.GetWardTotemDebuffMult = wardTotemMult

-- Device aura helpers (2026-10-26, DEP-020 Gravity Pylon): a placed device unit with
-- auraSpec.stabilityBonus / auraSpec.teleportLock affects EVERY unit in its radius
-- (both sides: "Units in aura"), read live from the injected aura-units provider, so
-- the effect ends the moment the device is destroyed or a unit steps out.
local function deviceAuraStability(unit)
	local list = _auraUnits and _auraUnits() or nil
	if type(list) ~= "table" or not unit.tileX then return 0 end
	local bonus = 0
	for _, u in ipairs(list) do
		-- A teleport-lock aura (Gravity Pylon) affects every unit; other stability auras
		-- (SUP-011 Guardian Standard, 2026-10-27) only the device's own side.
		if u ~= unit and u.isAlive and u.auraSpec and u.auraSpec.stabilityBonus and u.tileX
			and (u.auraSpec.teleportLock or u.side == unit.side) then
			local r = u.auraSpec.radius or 0
			if math.max(math.abs(u.tileX - unit.tileX), math.abs(u.tileY - unit.tileY)) <= r then
				bonus = bonus + u.auraSpec.stabilityBonus
			end
		end
	end
	return bonus
end

-- True when the unit stands inside a teleport-lock aura: it cannot teleport, blink or swap.
function StatusService.IsTeleportLocked(unit)
	-- CON-019 Phase Lock (2026-10-27): a status with teleportLock locks its holder anywhere.
	for _, inst in ipairs((unit and unit.statusInstances) or {}) do
		local d = GameConstants.STATUSES[inst.id]
		if d and d.teleportLock then return true end
	end
	local list = _auraUnits and _auraUnits() or nil
	if type(list) ~= "table" or not unit or not unit.tileX then return false end
	for _, u in ipairs(list) do
		if u ~= unit and u.isAlive and u.auraSpec and u.auraSpec.teleportLock and u.tileX then
			local r = u.auraSpec.radius or 0
			if math.max(math.abs(u.tileX - unit.tileX), math.abs(u.tileY - unit.tileY)) <= r then
				return true
			end
		end
	end
	return false
end

function StatusService.SetWeatherBurnSuppressed(v)
	_weatherBurnSuppressed = v and true or false
end

-- FIREBREAK ZONE (user ruling 2026-10-27, ENV-015): Main injects fn(x, y) -> true when the
-- tile is fireproofed. Everyone standing there cannot gain Burn and takes half Fire damage.
local _fireGuardQuery = nil
function StatusService.SetFireGuardQuery(fn)
	_fireGuardQuery = fn
end
-- SCANNER LENS ZONE (user ruling 2026-10-27, UTI-003): Main injects fn(unit) -> true when the
-- unit stands in a reveal zone owned by another side. Such a unit cannot gain Hide.
local _hideBlockQuery = nil
function StatusService.SetHideBlockQuery(fn)
	_hideBlockQuery = fn
end
function StatusService.IsFireGuarded(unit)
	return _fireGuardQuery ~= nil and unit ~= nil and unit.tileX ~= nil
		and _fireGuardQuery(unit.tileX, unit.tileY) == true
end

-- TAUNT (user ruling 2026-10-27, CON-018 Taunt Beacon). A Taunted unit may basic-attack, and
-- use Debuff / Direct Damage skills on, ONLY its taunter (area skills centred on it). Ends when
-- the taunter is KO'd. An aura taunt (device auraSpec.taunt) ends when the unit leaves the
-- aura and is re-applied while it stays inside. Evaluated lazily wherever targets are listed
-- or validated, plus a full pass at every turn start (Main).
local function tauntAuraContains(src, unit)
	local a = src and src.auraSpec
	if not (a and a.taunt and src.tileX and unit.tileX) then return false end
	return math.max(math.abs(src.tileX - unit.tileX), math.abs(src.tileY - unit.tileY)) <= (a.radius or 0)
end

-- Returns the living taunter of `unit` (or nil), first dropping a stale taunt and picking up
-- an aura taunt the unit now stands in. Second return: true when the status changed.
function StatusService.GetTaunter(unit, allUnits)
	if not (unit and unit.isAlive and unit.statusInstances and type(allUnits) == "table") then return nil, false end
	-- Devices are never taunted; the Bounty Hunter battlefield event is immune to Taunt.
	if unit.isItemDevice or unit.tauntImmune then return nil, false end
	local changed = false
	local inst, src = nil, nil
	for _, i in ipairs(unit.statusInstances) do
		if i.id == "Taunted" then inst = i break end
	end
	if inst then
		for _, u in ipairs(allUnits) do
			if u.id == inst.sourceUnitId then src = u break end
		end
		if not (src and src.isAlive) or (inst.fromAura and not tauntAuraContains(src, unit)) then
			StatusService.RemoveStatus(unit, "Taunted")
			print(string.format("[StatusService] Taunt on %s ended (%s)", tostring(unit.name),
				(src and src.isAlive) and "left the aura" or "taunter gone"))
			inst, src, changed = nil, nil, true
		end
	end
	if not inst and unit.side ~= "Neutral" and GameConstants.STATUSES["Taunted"] then
		for _, u in ipairs(allUnits) do
			if u ~= unit and u.isAlive and u.side ~= unit.side and tauntAuraContains(u, unit) then
				StatusService.ApplyStatus(unit, "Taunted", u.id)
				for _, i in ipairs(unit.statusInstances) do
					if i.id == "Taunted" then
						i.fromAura = true
						inst, src, changed = i, u, true
						break
					end
				end
				break
			end
		end
	end
	if inst and src then return src, changed end
	return nil, changed
end

-- Full pass (turn start): returns the units whose Taunted status changed.
function StatusService.ReconcileTaunts(allUnits)
	local out = {}
	for _, u in ipairs(allUnits or {}) do
		if u.isAlive then
			local _, changed = StatusService.GetTaunter(u, allUnits)
			if changed then table.insert(out, u) end
		end
	end
	return out
end

-- Skills a taunt restricts: Debuff or Direct Damage (tags), or a skill that applies a debuff.
function StatusService.IsTauntRestrictedSkill(def)
	if type(def) ~= "table" then return false end
	for _, t in ipairs(def.tags or {}) do
		if t == "Direct Damage" or t == "Debuff" then return true end
	end
	local s = def.appliesStatus and GameConstants.STATUSES[def.appliesStatus]
	return s ~= nil and s.kind == "Debuff"
end

-- Keeps only candidates that are the taunter (unit) or the taunter's tile (ground centre).
-- A tile-mode marker (ground / widened tile-click skills; it sits on the caster's tile as a
-- placeholder) is kept but moved onto the taunter's tile, so tile skills stay usable under Taunt and
-- an AI aims at the taunter. Dropped when the taunter is outside `range` (optional). UAT 2026-10-28 D-2.
function StatusService.FilterTauntCandidates(actor, def, candidates, allUnits, range)
	if type(candidates) ~= "table" or not StatusService.IsTauntRestrictedSkill(def) then return candidates end
	local taunter = StatusService.GetTaunter(actor, allUnits)
	if not taunter then return candidates end
	-- An "Empty Tile" skill can never be aimed at the taunter (its tile is never empty), so under
	-- Taunt it has no target at all (UAT 2026-10-28 D-A: traps / Summon Turret).
	if def.targetRules == "Empty Tile" then
		return {}
	end
	-- Weapon minimum range (e.g. Longshot) also applies, so the prompt never offers a tile the
	-- server would refuse (UAT 2026-10-28 A-1). Line of sight is still checked only on commit.
	local _, minRange = GameConstants.CalcSkillRange(actor, def, 0)
	local kept = {}
	for _, c in ipairs(candidates) do
		if type(c) == "table" and c.isGroundTarget then
			local inRange = true
			if type(range) == "number" and actor and actor.tileX and taunter.tileX then
				local d = math.max(math.abs(actor.tileX - taunter.tileX), math.abs(actor.tileY - taunter.tileY))
				inRange = d <= range and d >= (minRange or 0)
			end
			if inRange then
				local m = table.clone(c)
				m.tileX, m.tileY = taunter.tileX, taunter.tileY
				table.insert(kept, m)
			end
		elseif type(c) == "table" and (c.id == taunter.id or (c.tileX == taunter.tileX and c.tileY == taunter.tileY)) then
			table.insert(kept, c)
		end
	end
	return kept
end

-- PHASE LOCK (user ruling 2026-10-27): no self-relocation except walking.
function StatusService.IsRelocationLocked(unit)
	for _, inst in ipairs((unit and unit.statusInstances) or {}) do
		local d = GameConstants.STATUSES[inst.id]
		if d and d.relocationLock then return true end
	end
	return false
end

--------------------------------------------------
-- CHANNEL DISRUPTOR CHECK
-- These statuses interrupt channeling when applied.
--------------------------------------------------

local CHANNEL_DISRUPTORS = {
	Silence = true,
	Stun    = true,
	Sleep   = true,
	Petrify = true,
}

-- Hard CC: statuses that remove buffs with removedByCC (e.g. Guard).
-- Silence disrupts channeling but is NOT hard CC for Guard purposes.
local HARD_CC = {
	Stun   = true,
	Sleep  = true,
	Petrify = true,
}

function StatusService.IsChannelDisruptor(statusId)
	return CHANNEL_DISRUPTORS[statusId] == true
end

--------------------------------------------------
-- IMMUNITY FRAMEWORK (Phase 4)
--
-- Checks whether a unit is immune to a status before application.
-- Sources: race tags, active buffs (Sleep Immunity), Petrify state.
--------------------------------------------------

-- Race tag → immune statuses (from DB race_tags table)
local TAG_IMMUNITIES = {
	Undead     = { Poison = true, Venom = true, Bleed = true, Raptured = true, Wounded = true },
	Mechanical = { Poison = true, Venom = true, Bleed = true, Raptured = true, Wounded = true },
	Amphibious = { Drowning = true },
	-- Flying: Sinking immunity (DB: "Flight immune" on Sinking)
	Flying     = { Sinking = true },
}

-- Helper: get race tags for a unit via RaceData
local function getUnitTags(unit)
	local raceTags = {}
	if unit.raceId then
		local raceEntry = RaceData.GetRace(unit.raceId)
		if raceEntry and raceEntry.tags then
			raceTags = raceEntry.tags
		end
	end
	-- The Undead STATUS gives the Undead tag (and its immunities) to a unit of any race.
	for _, inst in ipairs(unit.statusInstances or {}) do
		if inst.id == "Undead" then
			local withUndead = table.clone(raceTags)
			table.insert(withUndead, "Undead")
			return withUndead
		end
	end
	return raceTags
end

-- BREAK SWITCHES OFF THE NAMED RACE ABILITY (rules 35/47, status row 64; user ruling
-- 2026-10-27): the ONE shared check, used by RacePassiveService and by every race ability
-- coded outside it (Dragonscale Burn immunity, Nine Lives on a ground collapse, the Giant
-- tag's reach / knockback / sight rule). Creature-type tag rules (Undead, Mechanical,
-- Amphibious, Flying) do NOT call this and stay on while Broken. Nil-safe: a unit with no
-- status list (loadout preview, map generation) is never Broken.
function StatusService.IsRacePassiveSuppressed(unit)
	for _, inst in ipairs((unit and unit.statusInstances) or {}) do
		if inst.id == "Break" then return true end
	end
	return false
end

-- DRAGONKIN — Dragonscale (races row 'Dragonkin', 2026-10-02): Burn DAMAGE
-- immunity -- NOT application immunity (Burn still applies and stays active so the
-- +15% stat bonus sees it). Race detection via RaceData.GetRace (nil-safe). Inline
-- here because StatusService cannot require RacePassiveService (circular dep).
-- Switched off while Broken (user ruling 2026-10-27).
local function isBurnDamageImmune(unit)
	if not unit or not unit.raceId then return false end
	if StatusService.IsRacePassiveSuppressed(unit) then return false end
	if not RaceData.GetRace(unit.raceId) then return false end
	return unit.raceId == "RACE-DRAGONKIN"
end

function StatusService.IsImmune(unit, statusId)
	-- Item devices (turrets, drones, totems, beacons; 2026-10-27) are machines that take no
	-- turns, so a status could never tick or wear off on them: none can be put on them.
	if unit and unit.isItemDevice then
		return true, "devices are not affected by statuses"
	end
	-- 0. Weather Burn-suppression (Rain / Snow Storm): block Burn APPLICATION.
	if statusId == "Burn" and _weatherBurnSuppressed then
		return true, "weather suppresses Burn"
	end
	if statusId == "Burn" and StatusService.IsFireGuarded(unit) then
		return true, "inside a Firebreak zone"
	end
	if statusId == "Hide" and _hideBlockQuery and _hideBlockQuery(unit) == true then
		return true, "revealed by a scan"
	end

	-- 0b. Dungeon relic immunities (relics v2: RL-35..40, RL-55), battle-only.
	if type(unit._dgImmune) == "table" and unit._dgImmune[statusId] then
		return true, "relic immune to " .. statusId
	end

	-- 1. Race tag immunities
	local tags = getUnitTags(unit)
	for _, tag in ipairs(tags) do
		local immuneSet = TAG_IMMUNITIES[tag]
		if immuneSet and immuneSet[statusId] then
			return true, tag .. " immune to " .. statusId
		end
	end

	-- 2. Active buff immunities (Sleep Immunity blocks Sleep)
	if statusId == "Sleep" then
		for _, inst in ipairs(unit.statusInstances) do
			if inst.id == "Sleep Immunity" then
				return true, "Sleep Immunity active"
			end
		end
	end

	-- 3. Petrify blocks all new debuffs
	-- DB: "Immune to new debuffs" while Petrified
	if statusId ~= "Petrify" then -- Petrify doesn't block itself
		local def = GameConstants.STATUSES[statusId]
		if def and (def.kind == "Debuff") then
			for _, inst in ipairs(unit.statusInstances) do
				if inst.id == "Petrify" then
					return true, "Petrified: immune to new debuffs"
				end
			end
		end
	end

	-- 3b. BD-010 Wardweave Robe (2026-10-24): while Guarding, immune to NEW debuff application.
	-- Same shape as Petrify above; checks the Guard status + the armor passive (deferred require
	-- to avoid a load-time cycle). Does not block buffs or re-applications of existing debuffs.
	if statusId ~= "Petrify" then
		local def = GameConstants.STATUSES[statusId]
		if def and (def.kind == "Debuff") then
			local guarding = false
			for _, inst in ipairs(unit.statusInstances) do
				if inst.id == "Guard" then guarding = true; break end
			end
			if guarding and (require :: any)(script.Parent.ArmorPassiveService).CanGuardImmuneDebuff(unit) then
				return true, "Wardweave Robe: Guarding immune to new debuffs"
			end
		end
	end

	return false, nil
end

--------------------------------------------------
-- APPLY STATUS
--
-- Returns: applied (bool), disruptsChannel (bool)
--          Third return (optional): immuneReason (string) if blocked by immunity
-- Caller must check disruptsChannel and interrupt channeling if true.
-- Caller should check third return to broadcast StatusImmune if non-nil.
--------------------------------------------------

-- durationCtOverride (optional, 2026-10-07): a skill-authored CT duration that
-- replaces the status default for THIS application only (e.g. Veil of Weakness
-- Weakened 1500 CT vs default 2000). nil = status default (all other callers).
--------------------------------------------------
-- DEBUFF RESISTANCE ON APPLICATION + STATUS STACKING (user rulings 2026-10-26)
-- Ruling 11: Debuff Resistance (GetDebuffResist, a multiplier <= 1) reduces
--   * the DURATION of CT-based debuffs,
--   * the DAMAGE of DoT debuffs (already applied at tick time; duration untouched),
--   * for debuffs that are neither: the debuff's NUMERICAL VALUE (stored on the
--     instance as valueScale and read by the modifier getters); a turn-based debuff
--     with no numerical value (e.g. Sleep) has its turn count reduced instead
--     (rounded, minimum 1 turn).
-- Ruling 10: the SAME status re-applied only refreshes duration; DIFFERENT statuses
--   affecting the same stat are TOTALED (sum of their deltas) and the net applied once.
--------------------------------------------------
local DOT_FAMILY = { Poison = true, Burn = true, Venom = true, Bleed = true,
	Raptured = true, Wounded = true, Drowning = true, Sinking = true }
-- Already reduced by Debuff Resistance at the moment the effect lands (Confuse
-- backlash, Mana Burn damage): leave their duration and value alone.
local RESIST_AT_USE = { Confuse = true, ["Mana Burn"] = true }
-- Turn-based debuffs whose numeric effect lives in bespoke code that reads valueScale.
local BESPOKE_VALUE = { Slow = true, Wet = true, Frozen = true, Cursed = true, Crippled = true }
local GENERIC_VALUE_FIELDS = { "statPctMod", "defenseMult", "attackMult", "physDamageMult",
	"spellDamageMult", "damageTakenMult", "stabilityOffset", "moveOffset", "moveRtMult",
	"rtMultiplier", "healingReceivedMult", "debuffResistPenalty", "hitQualityMod", "directDamageDealtMult" }

local function hasNumericValue(statusId, def)
	if BESPOKE_VALUE[statusId] then
		return true
	end
	for _, f in ipairs(GENERIC_VALUE_FIELDS) do
		if def[f] ~= nil then
			return true
		end
	end
	return false
end

-- pen (2026-10-28): fraction of the target's Debuff Resistance the APPLIER ignores (Plague Doctor
-- 0.15 on Dark / Poison debuffs). Resistance r is a multiplier (1 = none); ignoring a fraction of it
-- gives r + (1 - r) x pen.
local function penetrate(r, pen)
	if pen and pen > 0 and r < 1 then
		return r + (1 - r) * pen
	end
	return r
end

local function applyDebuffResistance(unit, statusId, def, inst, pen)
	if def.kind ~= "Debuff" then
		return
	end
	if DOT_FAMILY[statusId] or def.dotType or RESIST_AT_USE[statusId] then
		return
	end
	local r = penetrate(StatusService.GetDebuffResist(unit), pen)
	inst.valueScale = nil
	if r >= 1 then
		return
	end
	if inst.remainingCt then
		inst.remainingCt = math.max(1, math.round(inst.remainingCt * r))
	elseif hasNumericValue(statusId, def) then
		inst.valueScale = r
	elseif inst.remainingTurns then
		inst.remainingTurns = math.max(1, math.round(inst.remainingTurns * r))
	end
end

-- Value scale of a status instance (1 unless a turn-based debuff stored one).
local function vscale(inst)
	return inst.valueScale or 1
end

-- BOSS RULES (BUG-155, batch 12; core_stats 39/43/44/55, numbers in GameConstants.BOSS_RULES).
-- Hard control = a debuff that blocks every action or skips the turn (Sleep, Stun, Petrify ...).
local function isHardControl(def): boolean
	return def ~= nil and (def.skipsTurn == true or (def.blocks ~= nil and def.blocks.All == true))
end
StatusService.IsHardControl = isHardControl

-- Runs right after Debuff Resistance on every application / refresh (same call sites): on a boss a
-- debuff lasts x0.5 (hard control x0.2), rounded UP, never below 1; Petrify is a flat 300 CT.
-- Tester batch 12 W2 (BUG-163): the boss part on its own, so the accumulate / stack / chain reapply
-- branches (Burn, Venom, Bleed / Raptured / Wounded) can call it too. No-op unless a boss Debuff.
local function applyBossDuration(unit, statusId, def, inst)
	if def.kind ~= "Debuff" or not GameConstants.IsBoss(unit) or inst.permanent then return end
	if statusId == "Petrify" and inst.remainingCt then
		inst.remainingCt = GameConstants.BOSS_RULES.petrifyCt
		return
	end
	local m = GameConstants.GetBossMod(unit, if isHardControl(def) then "hardControlDuration" else "debuffDuration")
	if inst.remainingCt then
		inst.remainingCt = math.max(1, math.ceil(inst.remainingCt * m))
	elseif inst.remainingTurns then
		inst.remainingTurns = math.max(1, math.ceil(inst.remainingTurns * m))
	end
end
local _applyDebuffResistanceBase = applyDebuffResistance
local function applyDebuffResistance(unit, statusId, def, inst, pen)
	_applyDebuffResistanceBase(unit, statusId, def, inst, pen)
	applyBossDuration(unit, statusId, def, inst)
end

-- BUG-156 (core_stats 45/46): Phase Break. Call after damage resolves. Each threshold (70/40/10% HP left)
-- crossed for the first time: remaining RT 0 (ready to act), active debuff durations x0.5, then debuffs
-- under 1 full turn / under 300 CT are removed (exactly 1 turn / 300 CT stay). Returns thresholds crossed.
-- BUG-168 (batch 13): second return = the status ids the break removed (in removal order), so callers log
-- each one's "is no longer <status>." line (BattleVisualBroadcaster.StatusWoreOff). Empty when none.
-- Design (core_stats 46 "debuffs", kept): DoT debuffs such as Poison / Burn / Bleed count and can be removed.
function StatusService.CheckBossPhaseBreak(unit): (number, { string })
	if not GameConstants.IsBoss(unit) or not unit.isAlive or (tonumber(unit.maxHp) or 0) <= 0 then return 0, {} end
	local R = GameConstants.BOSS_RULES
	local th = R.phaseThresholds
	local done = unit._bossPhase or 0
	local frac = (unit.currentHp or 0) / unit.maxHp
	local crossed = 0
	while done < #th and frac <= th[done + 1] do
		done += 1
		crossed += 1
	end
	if crossed == 0 then return 0, {} end
	unit._bossPhase = done
	local removed = {}
	for _ = 1, crossed do
		-- BUG-161 (batch 12b): RT 0 for a channelling boss too. In the two-timer model a caster at RT <= 0
		-- waits ("frozen") for its fixed channel deadline and takes its turn the moment the channel resolves
		-- (BattleCoordinator.ResolveChannelDeadline), which is "ready to act" without breaking the channel.
		unit.remainingRt = 0
		local drop = {}
		for _, inst in ipairs(unit.statusInstances or {}) do
			local def = GameConstants.STATUSES[inst.id]
			if def and def.kind == "Debuff" and not inst.permanent then
				if inst.remainingCt then
					local left = inst.remainingCt * R.phaseBreakDebuff
					if left < R.phaseBreakMinCt then table.insert(drop, inst.id) else inst.remainingCt = math.ceil(left) end
				elseif inst.remainingTurns then
					local left = inst.remainingTurns * R.phaseBreakDebuff
					if left < R.phaseBreakMinTurns then table.insert(drop, inst.id) else inst.remainingTurns = math.ceil(left) end
				end
			end
		end
		for _, id in ipairs(drop) do
			if StatusService.RemoveStatus(unit, id) then table.insert(removed, id) end
		end
	end
	print(string.format("[StatusService] Boss Phase Break | %s at %d/%d HP (phase %d), RT -> 0",
		tostring(unit.name), unit.currentHp or 0, unit.maxHp, done))
	return crossed, removed
end

-- durationTurnsOverride (optional, 2026-11-21): turn duration used instead of def.duration on a new
-- application or refresh (weapon Freeze = 1 turn, StatusService.ApplyWeaponFreeze). nil = def.duration.
-- BUG-300/BUG-301 (batch 29/29b): shared "standard Fire hit" for a Burn that arrives with no Fire
-- damage (dev GrantStatus, Burning tile occupy/cross). terrain_effects row 23: the Burning tick is
-- round(15% Max HP) Fire, from TILE_EFFECTS.Burning.tickDamage. Burn's own burnFraction (0.20,
-- elements_statuses 57) then sets the stored amount inside ApplyStatus. Min 1.
function StatusService.StandardFireHitDamage(unit)
	local bt = GameConstants.TILE_EFFECTS and GameConstants.TILE_EFFECTS.Burning
	return math.max(1, math.round(((unit and unit.maxHp) or 0) * ((bt and bt.tickDamage) or 0.15)))
end

function StatusService.ApplyStatus(unit, statusId, sourceUnitId, fireDamageDealt, durationCtOverride, burnFractionOverride, durationTurnsOverride)
	local def = GameConstants.STATUSES[statusId]
	if not def then
		warn("[StatusService] Unknown status: " .. tostring(statusId))
		return false, false
	end

	-- Phase 4: Immunity check
	local immune, immuneReason = StatusService.IsImmune(unit, statusId)
	if immune then
		print(string.format(
			"[StatusService] %s IMMUNE to %s (%s)", unit.name, statusId, immuneReason
		))
		return false, false, immuneReason
	end

	local disruptsChannel = CHANNEL_DISRUPTORS[statusId] == true

	-- Dungeon relic RL-14 Warding Sigil (step 8, rule 271): the first bad status (Debuff) on this unit
	-- each dungeon battle is resisted. Flag set by Main per battle; spent here (apply path only).
	-- A curse (source "Curse", e.g. RL-18 Leaden Shackles) can't be blocked (rule 271, 2026-11-15 12:21 PM).
	if unit._dgWardReady and def.kind == "Debuff" and sourceUnitId ~= "Curse" then
		unit._dgWardReady = nil
		print(string.format("[StatusService] %s resisted %s (Warding Sigil)", unit.name, statusId))
		return false, false, "Warding Sigil"
	end

	-- Plague Doctor Virulence (2026-10-28): a debuff applied by a Dark-tagged skill (the applier's
	-- current cast element) ignores 15% of the target's Debuff Resistance (DB Passive_Effect: Dark only).
	local resistPen = 0
	if def.kind == "Debuff" then
		local _pdSrc = findUnitById(sourceUnitId)
		if _pdSrc then
			-- Not casting: a Dark-weapon basic attack's debuff counts as Dark too (checklist fix 2026-10-29).
			local _pdEl = _pdSrc._docCastElement
			if _pdEl == nil and _pdSrc.weaponElement == "Dark" then _pdEl = "Dark" end
			resistPen = (require :: any)(script.Parent.DoctrinePassiveService).GetDebuffResistancePenetration(_pdSrc, _pdEl)
		end
	end

	-- Conflict rules (see STATUS_CONFLICT RULES above). Runs after immunity so an
	-- immune unit keeps its existing statuses untouched.
	local cancelId = STATUS_CANCELS[statusId]
	if cancelId and StatusService.HasStatus(unit, cancelId) then
		removeByConflict(unit, cancelId, statusId)
		print(`[StatusService] {statusId} cancelled {cancelId} on {unit.name}; {statusId} not applied`)
		return false, disruptsChannel
	end
	local removesList = STATUS_REMOVES[statusId]
	if removesList then
		for _, removedId in removesList do
			if StatusService.HasStatus(unit, removedId) then
				removeByConflict(unit, removedId, statusId)
			end
		end
	end

	-- Iron Will / Susceptible on a RE-application (re-check 2026-10-29): the reset duration gets the
	-- same -1/+1 turn (or -/+400 CT) as a new application (debuffs only, never below 1).
	-- ctReset = this re-application also reset the CT timer (refresh / chain); accumulate and stack
	-- reset turns only, so their running CT deadline is left alone (Tester note 2026-10-29).
	-- Shadowbinder Malignancy (+20% debuff duration) and Enchanter Lingering Enchantment (+1 turn,
	-- +10% numbers) apply to every eligible application, re-applications included (DB "Per eligible
	-- application"), keyed on the applier like the new-application block below.
	local function traitDebuffOffset(inst, ctReset)
		if def.kind == "Debuff" then
			local off = TraitEffectService.GetDebuffDurationTurnOffset(unit)
			if off ~= 0 then
				if inst.remainingTurns then inst.remainingTurns = math.max(1, inst.remainingTurns + off) end
				if ctReset and inst.remainingCt then inst.remainingCt = math.max(1, inst.remainingCt + off * 400) end
			end
		end
		local src = findUnitById(sourceUnitId)
		if not src then return end
		local _dps = (require :: any)(script.Parent.DoctrinePassiveService)
		if def.kind == "Debuff" then
			local m = _dps.GetDebuffDurationModifier(src)
			if m ~= 1 then
				if inst.remainingTurns then inst.remainingTurns = math.max(1, math.round(inst.remainingTurns * m)) end
				if ctReset and inst.remainingCt then inst.remainingCt = math.max(1, math.round(inst.remainingCt * m)) end
			end
		elseif def.kind == "Buff" then
			local add = _dps.GetBuffDurationModifier(src)
			if add ~= 0 then
				if inst.remainingTurns then inst.remainingTurns = inst.remainingTurns + add end
				if ctReset and inst.remainingCt then inst.remainingCt = inst.remainingCt + add * 400 end
			end
			local em = _dps.GetBuffEffectModifier(src)
			if em ~= 1 then inst.valueScale = em end
		end
	end

	-- Check if unit already has this status.
	for _, inst in ipairs(unit.statusInstances) do
		if inst.id == statusId then
			if def.reapply == "refresh" then
				-- BUG-155 (core_stats 43/44): hard control already on a boss is never refreshed.
				if def.kind == "Debuff" and isHardControl(def) and GameConstants.IsBoss(unit) then
					print(string.format("[StatusService] %s on boss %s not refreshed (hard control)", statusId, tostring(unit.name)))
					return false, disruptsChannel
				end
				-- A permanent instance (race-granted Flight, 2026-10-29) is never shortened by a
				-- re-application (e.g. Angel Statue): keep it permanent.
				if inst.permanent then
					inst.sourceUnitId = inst.sourceUnitId or sourceUnitId
					return false, disruptsChannel
				end
				inst.remainingTurns = durationTurnsOverride or def.duration
				-- Lashed / Blunted (2026-11-21): refreshed during the holder's own turn -> still covers its next turn.
				if def.untilEndOfNextTurn and unit._inOwnTurn and inst.remainingTurns then
					inst.remainingTurns += 1
				end
				-- A skill / item / terrain Frozen refreshing a weapon Frozen takes it over (no Thawed after).
				if statusId == "Frozen" and not durationTurnsOverride then unit._weaponFrozen = nil end
				-- CT-based statuses (e.g. CounterStance: durationCt=1000, duration=nil)
				-- must refresh their CT window too — resetting remainingTurns alone
				-- left the original CT deadline running on recast.
				if def.durationCt then
					inst.remainingCt = durationCtOverride or def.durationCt
				end
				traitDebuffOffset(inst, true)
				inst.sourceUnitId   = sourceUnitId
				-- D2 (2026-10-27): a refreshed Command Relay is a fresh relay -> its RT discount is back.
				if def.relayRtMult then inst.relayState = nil end
				inst.resistPen = if resistPen > 0 then resistPen else nil
				if sourceUnitId ~= "Curse" then applyDebuffResistance(unit, statusId, def, inst, resistPen) end -- curses ignore Debuff Resistance (rule 271)
				-- D5 (2026-11-07): a unit held by a Venus Man-Trap keeps its endless hold. Another
				-- source's Pin runs on its own timer (venusOtherCt) under the hold; the hold itself never
				-- gets a timer, and when the plant lets go that other Pin carries on for its time left.
				if inst.venusHold then
					inst.venusOtherCt = math.max(inst.venusOtherCt or 0, inst.remainingCt or 0)
					inst.remainingCt = nil
					inst.remainingTurns = nil
				end
				print(string.format(
					"[StatusService] %s on %s REFRESHED (%s)",
					statusId, unit.name, def.duration and (def.duration .. " turns") or "CT"
				))
				syncStatStatus(unit, statusId)  -- BUG-218: a refresh can change its value scale (Enchanter)
				return false, disruptsChannel

			elseif def.reapply == "accumulate" then
				local addedBurn = 0
				if statusId == "Burn" and fireDamageDealt then
					addedBurn = math.round(fireDamageDealt * (burnFractionOverride or def.burnFraction))
				end
				inst.storedBurn = (inst.storedBurn or 0) + addedBurn
				inst.remainingTurns = def.duration
				traitDebuffOffset(inst, false)
				applyBossDuration(unit, statusId, def, inst) -- Tester W2 / BUG-163
				inst.sourceUnitId = sourceUnitId
				print(string.format(
					"[StatusService] %s on %s ACCUMULATED (+%d stored, %d turns now)",
					statusId, unit.name, addedBurn, inst.remainingTurns
				))
				return false, disruptsChannel

			elseif def.reapply == "stack" then
				-- Venom: Strength +1. Enlightened: stack +1.
				inst.stacks = (inst.stacks or 1) + 1
				inst.remainingTurns = def.duration  -- refresh duration
				traitDebuffOffset(inst, false)
				-- Tester W2 / BUG-163: only when a duration was really reset (Venom has none), so an
				-- untouched timer is never halved again on every stack.
				if def.duration then applyBossDuration(unit, statusId, def, inst) end
				inst.sourceUnitId = sourceUnitId
				print(string.format(
					"[StatusService] %s on %s STACKED (now %d stacks)",
					statusId, unit.name, inst.stacks
				))
				syncStatStatus(unit, statusId)  -- BUG-218: Enlightened +10% per stack
				return false, disruptsChannel

			elseif def.reapply == "extend" then
				-- Regeneration, Overflow: add to remaining duration
				local addTurns = def.duration or 0
				inst.remainingTurns = (inst.remainingTurns or 0) + addTurns
				traitDebuffOffset(inst, false)  -- Enchanter +1 turn on an extended buff too (re-check 2026-10-29)
				inst.sourceUnitId = sourceUnitId
				print(string.format(
					"[StatusService] %s on %s EXTENDED (+%d, now %d turns)",
					statusId, unit.name, addTurns, inst.remainingTurns
				))
				return false, disruptsChannel

			elseif def.reapply == "chain" then
				-- Bleed→Raptured, Raptured→Wounded, Wounded→Bleed
				inst.remainingTurns = def.duration  -- refresh self
				-- CT-based chain statuses (Bleed, 2000 CT) refresh their CT window too (checklist fix
				-- 2026-10-29: the old deadline kept running, so Lacerate's "refreshes Bleed" failed).
				if def.durationCt then
					inst.remainingCt = durationCtOverride or def.durationCt
				end
				traitDebuffOffset(inst, def.durationCt ~= nil)
				applyBossDuration(unit, statusId, def, inst) -- Tester W2 / BUG-163
				inst.sourceUnitId = sourceUnitId
				-- Apply next in chain
				local CHAIN_NEXT = { Bleed = "Raptured", Raptured = "Wounded", Wounded = "Bleed" }
				local nextStatus = CHAIN_NEXT[statusId]
				local chainOwner = false
				if _chainVisited == nil then
					_chainVisited = { [statusId] = true }
					chainOwner = true
				end
				if nextStatus and not _chainVisited[nextStatus] then
					_chainVisited[nextStatus] = true
					print(string.format(
						"[StatusService] %s on %s CHAINED → applying %s",
						statusId, unit.name, nextStatus
					))
					local ok, err = pcall(StatusService.ApplyStatus, unit, nextStatus, sourceUnitId)
					if not ok then
						if chainOwner then _chainVisited = nil end
						error(err)
					end
				end
				if chainOwner then _chainVisited = nil end
				return false, disruptsChannel

			elseif def.reapply == "none" then
				-- Does nothing (Sleep, Undead, KO)
				return false, disruptsChannel
			end
			return false, disruptsChannel
		end
	end

	-- New application.
	local instance = {
		id             = statusId,
		remainingTurns = durationTurnsOverride or def.duration,
		sourceUnitId   = sourceUnitId or "unknown",
		stacks         = 1,  -- default stack count for all statuses
	}
	-- Lashed / Blunted (2026-11-21, elements_statuses 131/132): "until the end of its next turn". Landed
	-- during the holder's own turn (counter / reaction) -> +1 turn, so it is not spent at this turn's end.
	if def.untilEndOfNextTurn and unit._inOwnTurn and instance.remainingTurns then
		instance.remainingTurns += 1
	end
	if statusId == "Frozen" and not durationTurnsOverride then unit._weaponFrozen = nil end

	-- CT-based duration: set remainingCt instead of remainingTurns
	if def.durationCt then
		instance.remainingCt = durationCtOverride or def.durationCt
	end

	-- Perks & Flaws Phase 3 (TRAIT-033): Iron Will / Susceptible adjust DEBUFF duration
	-- by -1 / +1 turn (or ∓400 CT for CT-based debuffs). Only affects debuffs (def.kind
	-- == "Debuff"); never reduces a debuff below 1 turn / 1 CT (Iron Will can't null it).
	if def.kind == "Debuff" then
		local durOffset = TraitEffectService.GetDebuffDurationTurnOffset(unit)
		if durOffset ~= 0 then
			if instance.remainingTurns then
				instance.remainingTurns = math.max(1, instance.remainingTurns + durOffset)
			end
			if instance.remainingCt then
				instance.remainingCt = math.max(1, instance.remainingCt + durOffset * 400)
			end
		end
	end

	-- Lore (weapon native, Tome): the APPLIER gets +30% duration on every status/buff it applies
	-- (DB "+30% applied status and buff duration"). Keyed on the SOURCE unit (resolved from
	-- sourceUnitId via the battle units provider), on NEW application only -- mirrors the Iron Will /
	-- Susceptible offset above, which also skips the refresh/stack/extend paths. Multiplicative and
	-- rounded, applied to BOTH turn- and CT-based durations; never shortens (1.30x >= x for x>=1).
	-- No-op when the source cannot be resolved or lacks Lore. Deferred require avoids a load cycle
	-- (WeaponPassiveService requires only WeaponData). Affects debuffs (incl. DoTs), buffs, self-buffs.
	if sourceUnitId and sourceUnitId ~= "unknown" and _auraUnits then
		local _units = _auraUnits()
		if type(_units) == "table" then
			local _src = nil
			for _, u in ipairs(_units) do
				if u.id == sourceUnitId then _src = u; break end
			end
			if _src then
				local _wps = (require :: any)(script.Parent.WeaponPassiveService)
				local loreMult = _wps.GetAppliedStatusDurationMultiplier(_src)
				if loreMult ~= 1 then
					if instance.remainingTurns then
						instance.remainingTurns = math.max(instance.remainingTurns, math.round(instance.remainingTurns * loreMult))
					end
					if instance.remainingCt then
						instance.remainingCt = math.max(instance.remainingCt, math.round(instance.remainingCt * loreMult))
					end
				end
			end
		end
	end

	-- Doctrine duration / effect (2026-10-28), keyed on the APPLIER, new applications only:
	--   Shadowbinder Malignancy: debuff duration +20% (before Debuff Resistance). Permanent /
	--     unlimited (no duration) debuffs are untouched by construction.
	--   Enchanter Lingering Enchantment: buff +1 turn (+400 CT for CT buffs, the same turn->CT
	--     step Iron Will uses) and buff numbers +10% via valueScale (read by vscale()).
	do
		local _docSrc = findUnitById(sourceUnitId)
		if _docSrc then
			local _dps = (require :: any)(script.Parent.DoctrinePassiveService)
			if def.kind == "Debuff" then
				local m = _dps.GetDebuffDurationModifier(_docSrc)
				if m ~= 1 then
					if instance.remainingTurns then instance.remainingTurns = math.max(1, math.round(instance.remainingTurns * m)) end
					if instance.remainingCt then instance.remainingCt = math.max(1, math.round(instance.remainingCt * m)) end
				end
			elseif def.kind == "Buff" then
				local add = _dps.GetBuffDurationModifier(_docSrc)
				if add ~= 0 then
					if instance.remainingTurns then instance.remainingTurns = instance.remainingTurns + add end
					if instance.remainingCt then instance.remainingCt = instance.remainingCt + add * 400 end
				end
				local em = _dps.GetBuffEffectModifier(_docSrc)
				if em ~= 1 then instance.valueScale = em end
			end
		end
	end

	-- Debuff Resistance (ruling 11): applied last, after trait / Lore duration changes.
	if resistPen > 0 then instance.resistPen = resistPen end -- DoT ticks read it (Plague Doctor)
	if sourceUnitId ~= "Curse" then applyDebuffResistance(unit, statusId, def, instance, resistPen) end -- curses ignore Debuff Resistance (rule 271)

	if statusId == "Burn" and fireDamageDealt then
		instance.storedBurn = math.round(fireDamageDealt * (burnFractionOverride or def.burnFraction))
	elseif statusId == "Burn" then
		instance.storedBurn = 0
	end

	table.insert(unit.statusInstances, instance)
	syncBreakEquipment(unit, statusId)
	syncStatStatus(unit, statusId)  -- BUG-218: Weakened / Banner Blessing ... change stats (and Max HP) now

	-- Recharge: immediate MP restore on application (DB elements_statuses id 78:
	-- "On application: restore round(Max MP × 0.10), minimum 1 MP"). The periodic
	-- restores are handled per-interval in ProcessCtTick. Reapplication does NOT
	-- repeat this immediate restore (reapply path returns earlier, above).
	if def.rechargeImmediateFraction then
		local restore = math.max(1, math.round((unit.maxMp or 1) * def.rechargeImmediateFraction))
		local before = unit.currentMp or 0
		unit.currentMp = math.min(unit.maxMp or before, before + restore)
		print(string.format("[StatusService] Recharge immediate: %s +%d MP", unit.name, unit.currentMp - before))
	end

	-- If this is a hard CC status, remove buffs flagged removedByCC (e.g. Guard)
	if HARD_CC[statusId] then
		local i = 1
		while i <= #unit.statusInstances do
			local inst = unit.statusInstances[i]
			local instDef = GameConstants.STATUSES[inst.id]
			if instDef and instDef.removedByCC and inst.id ~= statusId then
				print(string.format(
					"[StatusService] %s REMOVED from %s (CC: %s applied)",
					inst.id, unit.name, statusId
				))
				table.remove(unit.statusInstances, i)
			else
				i = i + 1
			end
		end
	end

	-- BUG-097 (2026-11-21): CT-timed statuses (Pinned, Bleed, Venom...) have duration=nil and
	-- were logged as "∞ turns" although they expire. Show the live remainingCt instead.
	print(string.format(
		"[StatusService] %s APPLIED to %s (%s)%s%s",
		statusId, unit.name,
		if instance.remainingCt then (tostring(instance.remainingCt) .. " CT")
			else (tostring(instance.remainingTurns or def.duration or "∞") .. " turns"),
		instance.storedBurn and (" | stored:" .. instance.storedBurn) or "",
		disruptsChannel and " [CHANNEL DISRUPTOR]" or ""
	))
	return true, disruptsChannel
end

--------------------------------------------------
-- SHIELD SUBSYSTEM (2026-10-05)
--
-- Shields are granted by the six Shield skills (routed via skillDef.isShield in
-- CombatResolver/CommandService) and tracked as a dedicated "Shield" status
-- instance so they get a pill, a duration, and the 300-CT decay tick — while the
-- fast aggregate unit.shield_total (which UnitSchema.ApplyDamage soaks against
-- directly) is kept 1:1 in sync with the instance's shieldHp.
--
-- Design (authored, SkillData / CTRBLXAI.db): one Shield instance per unit.
-- Recasting "Refresh; does not stack" — a new grant REPLACES the old instance
-- (fresh shieldHp, fresh duration, decay accumulator reset). Retribution Shell
-- carries a snapshot retributionDamage so a BREAK can retaliate against the
-- breaker (resolved by CombatResolver.ApplyOutcome, which knows the attacker).
--------------------------------------------------

-- Grant / replace a unit's shield. shieldHp and durationCt are authored per skill.
-- retributionDamage (optional) is the snapshot Physical damage dealt to whoever
-- breaks the shield (Retribution Shell only; nil for the other five).
function StatusService.ApplyShield(unit, shieldHp, durationCt, sourceUnitId, retributionDamage, elementalOnly)
	shieldHp = math.max(0, math.round(shieldHp or 0))
	if shieldHp <= 0 then
		return false
	end
	-- Draining Ward (user rulings 2026-11-05): whenever a ward is involved (ward vs normal shield,
	-- either order, or ward vs ward) the BIGGER shield is kept; ties keep the existing one. Two
	-- normal shields keep the original rule (newest replaces).
	local curWard = unit.shieldElementalOnly == true
	if (elementalOnly == true or curWard) and (unit.shield_total or 0) >= shieldHp and (unit.shield_total or 0) > 0 then
		print(string.format("[StatusService] Shield on %s kept (%d >= new %d%s)", unit.name, unit.shield_total, shieldHp,
			elementalOnly and ", ward ignored" or ", replaces ward refused"))
		return false
	end

	-- Remove any existing Shield instance (same-caster or not: a unit holds ONE
	-- shield pool; recast replaces it per the authored "does not stack" rule).
	local existingHp = 0
	for idx = #unit.statusInstances, 1, -1 do
		if unit.statusInstances[idx].id == "Shield" then
			existingHp = existingHp + (unit.statusInstances[idx].shieldHp or 0)
			table.remove(unit.statusInstances, idx)
		end
	end

	local instance = {
		id              = "Shield",
		sourceUnitId    = sourceUnitId or "unknown",
		stacks          = 1,
		shieldHp        = shieldHp,
		shieldMax       = shieldHp,
		remainingCt     = durationCt,
		decayAccumCt    = 0,
		retributionDamage = retributionDamage,  -- nil unless Retribution Shell
	}
	table.insert(unit.statusInstances, instance)

	-- Resync the aggregate pool: drop the replaced shield, add the new one.
	unit.shield_total = math.max(0, (unit.shield_total or 0) - existingHp) + shieldHp
	unit.shieldElementalOnly = (elementalOnly == true) or nil

	print(string.format(
		"[StatusService] Shield GRANTED on %s | %d HP | dur %s CT%s",
		unit.name, shieldHp, tostring(durationCt),
		retributionDamage and (" | retrib " .. tostring(retributionDamage)) or ""
	))
	return true
end

-- Called by UnitSchema.ApplyDamage (DI) after it soaks `soak` damage into
-- unit.shield_total. Draws the live Shield instance(s) down by the same amount,
-- so the pill/duration/retribution bookkeeping stays correct.
-- Returns: broke (bool — the pool reached 0 on this hit), shieldMaxAtBreak,
--          retributionDamage (nil unless the broken shield was a Retribution Shell).
function StatusService.OnShieldAbsorb(unit, soak)
	soak = soak or 0
	if soak <= 0 then return false, nil, nil end

	local remaining = soak
	local shieldMaxAtBreak, retributionDamage
	local brokeInstance = false

	local idx = 1
	while idx <= #unit.statusInstances and remaining > 0 do
		local inst = unit.statusInstances[idx]
		if inst.id == "Shield" and (inst.shieldHp or 0) > 0 then
			local drawn = math.min(inst.shieldHp, remaining)
			inst.shieldHp = inst.shieldHp - drawn
			remaining = remaining - drawn
			if inst.shieldHp <= 0 then
				-- This shield just broke. Capture its break data BEFORE removing it.
				brokeInstance = true
				shieldMaxAtBreak = inst.shieldMax or inst.shieldHp
				retributionDamage = inst.retributionDamage
				table.remove(unit.statusInstances, idx)
			else
				idx = idx + 1
			end
		else
			idx = idx + 1
		end
	end

	-- unit.shield_total was already decremented by ApplyDamage; clamp for safety
	-- and treat "pool now empty" as the break signal (covers the 1:1 case).
	if (unit.shield_total or 0) <= 0 then
		unit.shield_total = 0
		unit.shieldElementalOnly = nil  -- ward broke (2026-11-05)
		if brokeInstance then
			return true, shieldMaxAtBreak, retributionDamage
		end
		return true, shieldMaxAtBreak, retributionDamage
	end
	return false, nil, nil
end

--------------------------------------------------
-- PROCESS START OF TURN (DoT damage)
--
-- Called at the START of the active unit's turn.
-- Returns a list of DoT events: { { statusId, damage, sourceUnitId }, ... }
--------------------------------------------------

-- Debuff Resistance Multiplier used by every debuff-damage formula (2026-10-07).
-- 1) Base = 1 - VIT / (300 + VIT) (lower = more resistant).
-- 2) "Debuff Res Down" (Veil of Weakness): resistance -10 percentage points, applied
--    BEFORE other resistance/boss handling = multiplier +0.10. Does not stack (largest
--    penalty only). Clamped at 1.0 so resistance never falls below 0%.
-- 3) Then aura multipliers (Ward Totem x0.80, BUG-019).
function StatusService.GetDebuffResist(unit)
	local vit = unit.effectiveStats and unit.effectiveStats.VIT or 10
	local base = unit.derivedStats and unit.derivedStats.debuffResist or (1 - vit / (300 + vit))
	local penalty = 0
	local bonus = 0 -- Debuff Res Up (Meditate) / Warding: all sources TOTALED (ruling 10, 2026-10-26)
	for _, inst in ipairs(unit.statusInstances or {}) do
		local d = GameConstants.STATUSES[inst.id]
		-- Ruling 10 (2026-10-26): different Res Up / Res Down sources are TOTALED.
		if d and d.debuffResistPenalty then
			penalty = penalty + d.debuffResistPenalty * vscale(inst)
		end
		if d and d.debuffResistBonus then
			bonus = bonus + d.debuffResistBonus
		end
	end
	-- Net of Res Down and Res Up, clamped to [0, 1] (resistance between 0% and 100%).
	return math.clamp(base + penalty - bonus, 0, 1.0) * wardTotemMult(unit)
end

-- Festering Wound anti-heal: product of all active healingReceivedMult debuffs on the unit (1.0
-- when none). This is the single source of truth for the heal-reduction fraction, read by every
-- healing path so ALL healing is reduced while active: the central UnitSchema.ApplyHealing inline
-- scan (skill heals, lifedrain/lifesteal, potions, ally heals, trait heals/grants), the regen tick
-- below, and the six raw-HP-write sites that bypass ApplyHealing (augment heals, Campfire, object
-- heals / Healing-Magic springs / Blood Fountain, Troll Regrowth, Holy Ground, Diplomat's Veil
-- recruit). Troll Regrowth dampening is a flagged Designer decision (racial regen may be exempted).
function StatusService.GetHealingReceivedMult(unit)
	local mult = 1
	for _, inst in ipairs(unit.statusInstances or {}) do
		local d = GameConstants.STATUSES[inst.id]
		if d and d.healingReceivedMult then
			mult = mult + (d.healingReceivedMult - 1) * vscale(inst)
		end
	end
	-- Blessed Recovery / Cursed Wounds (DB "healing received +/-X%"): ALL healing the unit receives,
	-- not only skill heals (checklist fix 2026-10-29). Totaled with the status modifiers (ruling 10).
	mult = mult + (TraitEffectService.GetHealingReceivedModifier(unit) - 1)
	-- Guild Hall furniture (Stone Hearth, healing received x1.02; guild_facilities 94): set on the
	-- unit by EquipmentService.RebuildUnitStats, player units only.
	local fb = unit.furnitureBonus
	if type(fb) == "table" then mult = mult + (tonumber(fb.healRecv) or 0) end
	return math.max(0, mult)
end

-- One Burn tick's damage for this unit (shared by the turn-start tick and REC-015 Cooling Gel,
-- DAT-001 one formula): stored Burn x Debuff Resistance x DoT-received trait, halved in a
-- Firebreak zone. 0 when nothing is stored or the unit is Burn-immune (Dragonscale).
function StatusService.GetBurnTickDamage(unit, inst)
	if not (unit and inst) or isBurnDamageImmune(unit) then return 0 end
	local storedBurn = inst.storedBurn or 0
	if storedBurn <= 0 then return 0 end
	-- TRAIT-DOT-BURN: x unit-trait DoT-received multiplier (1.0 when no trait).
	local damage = math.max(1, math.round(storedBurn * StatusService.GetDebuffResist(unit)
		* TraitEffectService.GetDotDamageReceivedModifier(unit, "Burn")))
	-- Firebreak zone: Fire damage is halved (Burn ticks are Fire damage).
	if StatusService.IsFireGuarded(unit) then damage = math.max(1, math.round(damage * 0.5)) end
	return damage
end

function StatusService.ProcessStartOfTurn(unit)
	local dotEvents = {}
	-- Debuff Resistance (see GetDebuffResist): VIT, Debuff Res Down, Ward Totem.
	local debuffResist = StatusService.GetDebuffResist(unit)

	for _, inst in ipairs(unit.statusInstances) do
		local def = GameConstants.STATUSES[inst.id]
		if not def or not def.dotType then
			-- skip
		elseif def.dotType == "Poison" then
			-- TRAIT-DOT-POISON: x unit-trait DoT-received multiplier (1.0 when no trait).
			local damage = math.max(1, math.round(unit.maxHp * def.dotFraction * penetrate(debuffResist, inst.resistPen)
				* TraitEffectService.GetDotDamageReceivedModifier(unit, inst.id)
				* doctrinePoisonTickMult(inst)
			* GameConstants.GetBossMod(unit, "hpPctDebuff"))) -- BUG-155: Boss HP% Modifier (core_stats 40) -- Plague Doctor +25% (2026-10-28)
			table.insert(dotEvents, {
				statusId     = "Poison",
				damage       = damage,
				sourceUnitId = inst.sourceUnitId,
			})
		elseif def.dotType == "Burn" and isBurnDamageImmune(unit) then
			-- DRAGONKIN — Dragonscale: Burn tick nullified (0 damage). The instance is
			-- KEPT (it still ticks down and still counts as active for the stat bonus).
			print(string.format("[StatusService] Dragonscale: Burn tick on %s nullified (0 damage)", unit.name))
		elseif def.dotType == "Burn" then
			local damage = StatusService.GetBurnTickDamage(unit, inst)
			if damage > 0 then
				table.insert(dotEvents, {
					statusId     = "Burn",
					damage       = damage,
					sourceUnitId = inst.sourceUnitId,
				})
			end
		end
	end

	return dotEvents
end

-- END-OF-TURN DAMAGE (user ruling 2026-10-26): Venom hurts at the END of the victim's own
-- turn instead of the start (Poison/Burn), giving it a distinct identity: the victim gets
-- its whole turn to remove it before it ticks. Damage = round(Max HP x tickFraction (0.03)
-- x Venom Strength x Debuff Resistance x DoT-received trait modifier) -- same terms the
-- start-of-turn Poison tick uses. Pure: returns events, the caller applies the damage.
function StatusService.ProcessEndOfTurn(unit)
	local events = {}
	if not (unit and unit.isAlive and unit.statusInstances) then return events end
	-- Mana Fountain (objects_encounters row 118, 2026-11-07): recover 20% of MISSING MP at the end of
	-- the unit's own turn. MP only, no event (Main logs it: unit._manaFountainGain, cause "Mana Fountain").
	if StatusService.HasStatus(unit, "Mana Fountain") then
		local mfDef = GameConstants.STATUSES["Mana Fountain"]
		local missing = math.max(0, (unit.maxMp or 0) - (unit.currentMp or 0))
		if missing > 0 then
			local gain = math.min(missing, math.max(1, math.round(missing * ((mfDef and mfDef.missingMpRestoreFraction) or 0.20))))
			unit.currentMp = (unit.currentMp or 0) + gain
			unit._manaFountainGain = gain
			print(string.format("[StatusService] Mana Fountain | %s +%d MP at end of turn", tostring(unit.name), gain))
		end
	end
	local inst = StatusService.HasStatus(unit, "Venom")
	if inst then
		local def = GameConstants.STATUSES.Venom
		local frac = (def and def.tickFraction) or 0.03
		local strength = inst.stacks or 1
		local damage = math.max(1, math.round((unit.maxHp or 1) * frac * strength
			* penetrate(StatusService.GetDebuffResist(unit), inst.resistPen)
			* TraitEffectService.GetDotDamageReceivedModifier(unit, "Venom")
			* doctrinePoisonTickMult(inst)
			* GameConstants.GetBossMod(unit, "hpPctDebuff"))) -- BUG-155: Boss HP% Modifier (core_stats 40) -- Plague Doctor +25% (2026-10-28)
		table.insert(events, {
			statusId     = "Venom",
			damage       = damage,
			sourceUnitId = inst.sourceUnitId,
		})
	end
	return events
end

--------------------------------------------------
-- TICK STATUSES
--------------------------------------------------

function StatusService.TickStatuses(unit)
	local removed = {}
	local i = 1
	unit._inOwnTurn = nil  -- own turn is closing (set by WeaponPassiveService.OnTurnStart; Lashed / Blunted)

	while i <= #unit.statusInstances do
		local inst = unit.statusInstances[i]
		-- CT-based statuses use remainingCt (decremented elsewhere); skip turn decrement
		if inst.remainingCt then
			i = i + 1
			continue
		end
		if not inst.remainingTurns then i = i + 1; continue end
		inst.remainingTurns = inst.remainingTurns - 1

		if inst.remainingTurns <= 0 then
			print(string.format(
				"[StatusService] %s EXPIRED on %s",
				inst.id, unit.name
			))
			table.insert(removed, inst.id)
			table.remove(unit.statusInstances, i)
		else
			i = i + 1
		end
	end

	-- Break sync + Oversleep, after the scan so a new Sleep Immunity is not counted down this turn.
	for _, _rid in ipairs(removed) do onStatusEnded(unit, _rid) end
	if _onNaturalExpiry then
		for _, _rid in ipairs(removed) do _onNaturalExpiry(unit, _rid) end  -- BUG-140
	end
	return removed
end

--------------------------------------------------
-- REMOVE STATUS
--------------------------------------------------

-- WEAPON FREEZE (Frost Rod native Freeze + PAS-053; weapons_equipment 156, DESIGNER RULING
-- 2026-11-21): Frozen for 1 turn; when it ends the unit gains Thawed (2 turns, see onStatusEnded).
-- While Thawed the weapon Freeze is skipped. A Frozen from a skill / item / terrain already on the
-- unit is left alone (never shortened to 1 turn, never turned into a weapon Freeze).
-- Returns applied, disruptsChannel, immuneReason (same shape as ApplyStatus).
function StatusService.ApplyWeaponFreeze(unit, sourceUnitId)
	if not (unit and unit.statusInstances) then return false, false, nil end
	if StatusService.HasStatus(unit, "Thawed") then
		print(string.format("[StatusService] %s weapon Freeze skipped (Thawed)", tostring(unit.name)))
		return false, false, "Thawed"
	end
	if StatusService.HasStatus(unit, "Frozen") and not unit._weaponFrozen then
		return false, false, nil
	end
	local applied, disrupts, immuneReason = StatusService.ApplyStatus(unit, "Frozen", sourceUnitId, nil, nil, nil, 1)
	if StatusService.HasStatus(unit, "Frozen") then
		unit._weaponFrozen = true
	end
	return applied, disrupts, immuneReason
end

function StatusService.RemoveStatus(unit, statusId)
	for i, inst in ipairs(unit.statusInstances) do
		if inst.id == statusId then
			-- Weather hard-lock (Snow Storm undispellable Frozen, user ruling
			-- 2026-10-04): a hardLock instance cannot be removed by ANY path
			-- (including Fire thaw) until the weather clears it on re-roll.
			if inst.hardLock then
				return false
			end
			table.remove(unit.statusInstances, i)
			print(string.format(
				"[StatusService] %s REMOVED from %s",
				statusId, unit.name
			))
			onStatusEnded(unit, statusId)  -- Break sync + Oversleep
			return true
		end
	end
	return false
end

--------------------------------------------------
-- HEALING WEAKENS VENOM (user ruling 2026-10-26)
--
-- DB elements_statuses #53 / status_summon_engines "Healing interactions":
-- each qualifying heal lowers Venom Strength by 1; Venom is removed at 0.
-- A qualifying heal = one that actually restores HP. Call once per heal.
-- Returns the new strength (0 = Venom removed), or nil if the unit had no Venom.
--------------------------------------------------

--------------------------------------------------
-- HEAL-GAINED NOTIFY (Life Link, USER RULING 2026-11-08). Every place that restores HP calls this
-- once with the HP the unit ACTUALLY gained (after caps; overheal not counted). The listener is
-- injected by CommandService (LifeLinkService.OnHealGained) so this module requires nothing new
-- (no cycle). nil listener / gained <= 0 = no-op.
--------------------------------------------------
local _healGainedListener: any = nil
function StatusService.SetHealGainedListener(fn: any)
	_healGainedListener = fn
end

function StatusService.NotifyHealGained(unit: any, gained: number?)
	if _healGainedListener and unit and (gained or 0) > 0 then
		_healGainedListener(unit, gained)
	end
end

function StatusService.WeakenVenomOnHeal(unit)
	if not unit or not unit.statusInstances then return nil end
	local inst = StatusService.HasStatus(unit, "Venom")
	if not inst then return nil end
	local newStacks = (inst.stacks or 1) - 1
	if newStacks <= 0 then
		StatusService.RemoveStatus(unit, "Venom")
		print(`[StatusService] Venom on {unit.name} cured by healing`)
		return 0
	end
	inst.stacks = newStacks
	print(`[StatusService] Venom on {unit.name} weakened by healing (strength now {newStacks})`)
	return newStacks
end

--------------------------------------------------
-- HAS STATUS
--------------------------------------------------

function StatusService.HasStatus(unit, statusId)
	-- Ground-target markers ({ tileX, tileY, isGroundTarget }) carry no status list: they have no
	-- statuses. A tile pick on a unit-target item crashed the turn here (sweep 2026-11-06, SUP-016).
	for _, inst in ipairs((unit and unit.statusInstances) or {}) do
		if inst.id == statusId then
			return inst
		end
	end
	return nil
end

--------------------------------------------------
-- GET MODIFIED BASE RT
--------------------------------------------------

-- permanentOnly (optional, 2026-10-28): leave out status RT multipliers (Loadout Info panel).
function StatusService.GetModifiedBaseRt(unit, permanentOnly)
	-- DB weapons_equipment id 7: Modified Base RT = Base RT + Effective Armor WT.
	-- Armor weight belongs HERE (base turn time), not in the per-action WT term.
	-- Base RT = the unit's OWN base (enemy kind sets initiativeBaseRt: Grunt 400 /
	-- Veteran 380 / Elite 350; players have no field → default 400) PLUS gear WT.
	-- Permanent modifiers (traits) and Haste/Slow multiply this below. All per-turn
	-- RT costs and the one-time starting RT derive from this value.
	local baseRt = (unit.initiativeBaseRt or GameConstants.BASE_RT_STANDARD) + GameConstants.CalcEffectiveArmorWt(unit)
	if not permanentOnly then baseRt = math.max(1, baseRt + (tonumber(unit._dgBaseRtAdd) or 0)) end -- RL-54 Swift Sigil -30 / RL-44 enemies +50 (relics v2)
	local multiplier = 1.0

	for _, inst in ipairs(if permanentOnly then {} else (unit.statusInstances or {})) do
		local def = GameConstants.STATUSES[inst.id]
		if def and def.rtMultiplier then
			-- Ruling 10: totaled, not multiplied.
			multiplier = multiplier + (def.rtMultiplier - 1) * vscale(inst)
		end
	end
	multiplier = math.max(0, multiplier)

	-- Perks & Flaws (Phase 2b): Quick/Tardy/Timeline Sovereign/Temporal Drag adjust
	-- base RT. Folded at this chokepoint so it propagates to every RT term derived from
	-- Modified Base RT (move, basic attack, skill, guard). Starting RT is a separate term.
	multiplier = multiplier * TraitEffectService.GetBaseRtMultiplier(unit)

	return math.round(baseRt * multiplier)
end

--------------------------------------------------
-- RT COST MULTIPLIERS (Phase 3+ status effects)
--
-- Frozen: All RT costs ×2 (DB: "All RT costs including Movement RT x2")
-- Wet: Movement RT ×1.25 only (DB: "Movement RT x1.25")
--
-- These are SEPARATE from GetModifiedBaseRt (Haste/Slow) because:
-- Haste/Slow affect "Base RT-derived costs only" and explicitly exclude
-- Skill Card RT, channel time, activation time.
-- Frozen affects ALL RT costs including those.
--------------------------------------------------

-- SUP-017 Command Relay (2026-10-27): the next non-Item action costs RT x0.80. CommandService
-- tells us which action is being committed; previews (no action set) show the full cost.
local _curActionType: any = nil
function StatusService.SetCurrentAction(actionType)
	_curActionType = actionType
end
local function relayEligible(actionType)
	return actionType ~= nil and actionType ~= "Item" and actionType ~= "Wait" and actionType ~= "Undo"
end
-- Called once at the start of every committed action: the relay is "spending" during its
-- first eligible action and "spent" from the next action on.
function StatusService.BeginActionRelay(unit, actionType)
	for _, inst in ipairs((unit and unit.statusInstances) or {}) do
		local d = GameConstants.STATUSES[inst.id]
		if d and d.relayRtMult then
			if inst.relayState == "spending" then inst.relayState = "spent" end
			if inst.relayState == nil and relayEligible(actionType) then inst.relayState = "spending" end
		end
	end
end

-- noRelay (D1 fix 2026-10-27): BattleCoordinator.EndTurn passes true so the Command Relay
-- discount applies to that one action's RT only, never again to the whole turn total.
function StatusService.GetAllRtMultiplier(unit, noRelay)
	local m = 1.0
	for _, inst in ipairs(unit.statusInstances) do
		if inst.id == "Frozen" then
			m = 1 + (2.0 - 1) * vscale(inst)
			break
		end
	end
	if not noRelay and relayEligible(_curActionType) then
		for _, inst in ipairs(unit.statusInstances) do
			local d = GameConstants.STATUSES[inst.id]
			if d and d.relayRtMult and inst.relayState == "spending" then
				m = m * d.relayRtMult
				break
			end
		end
	end
	return m
end

function StatusService.GetMovementRtMultiplier(unit)
	local mult = 1.0
	for _, inst in ipairs(unit.statusInstances) do
		if inst.id == "Wet" then
			-- Mechanical race tag: Wet penalties doubled (DB: "Wet penalties are doubled")
			-- Normal: ×1.25 (penalty = 0.25). Mechanical: penalty doubled → ×1.50
			local isMechanical = false
			local tags = getUnitTags(unit)
			for _, tag in ipairs(tags) do
				if tag == "Mechanical" then isMechanical = true; break end
			end
			mult = mult + ((isMechanical and 1.50 or 1.25) - 1) * vscale(inst)
		end
		-- Data-driven movement RT buffs (e.g. Coordinated Advance x0.80, 2026-10-07).
		-- Ruling 10: totaled, not multiplied.
		local mdef = GameConstants.STATUSES[inst.id]
		if mdef and mdef.moveRtMult then
			mult = mult + (mdef.moveRtMult - 1) * vscale(inst)
		end
	end
	return math.max(0, mult)
end

--------------------------------------------------
-- CT-BASED TICK (Phase 4+)
--
-- Called by BattleCoordinator.AdvanceClock after CT advances.
-- Decrements durationCt on all CT-based statuses by ctElapsed.
-- Removes expired ones. Returns list of expired status IDs.
--
-- Turn-based statuses are NOT affected (they tick via TickStatuses).
--------------------------------------------------

function StatusService.ProcessCtTick(unit, ctElapsed)
	if ctElapsed <= 0 then return {} end
	-- HD-020 Commandant Helm damage bonus runs out on the clock (2026-10-29).
	if unit._commandantDmgCt then
		unit._commandantDmgCt -= ctElapsed
		if unit._commandantDmgCt <= 0 then
			unit._commandantDmgCt = nil
			unit._commandantDmgBonus = nil
		end
	end

	local expired = {}
	local events = {}   -- { { kind="Heal"|"Mana", statusId, amount }, ... }
	local regenHeals = 0  -- regeneration heals this step (each weakens Venom)
	local i = 1
	while i <= #unit.statusInstances do
		local inst = unit.statusInstances[i]
		local def = GameConstants.STATUSES[inst.id]

		-- Regeneration / Recharge: CT-interval periodic effects. Accrue elapsed CT
		-- and fire one event per completed interval (handles large ctElapsed steps
		-- that cross multiple boundaries). Amounts/cadence are DB-authored and live
		-- in the status def; clamp to Max so bars never overshoot.
		if def and inst.remainingCt then
			if def.regenFraction and def.regenIntervalCt then
				inst.regenAccumCt = (inst.regenAccumCt or 0) + ctElapsed
				while inst.regenAccumCt >= def.regenIntervalCt do
					inst.regenAccumCt = inst.regenAccumCt - def.regenIntervalCt
					-- DB: Final Heal = round(round(Max HP × regenFraction) × (1 + VIT/300))
					local vit = (unit.effectiveStats and unit.effectiveStats.VIT) or 10
					local base = math.round((unit.maxHp or 1) * def.regenFraction)
					local heal = math.round(base * (1 + vit / 300))
					-- Festering Wound anti-heal: regeneration ticks are reduced too.
					local _hrm = StatusService.GetHealingReceivedMult(unit)
					if _hrm ~= 1 then heal = math.max(0, math.floor(heal * _hrm)) end
					local before = unit.currentHp or 0
					unit.currentHp = math.min(unit.maxHp or before, before + heal)
					local applied = unit.currentHp - before
					if applied > 0 then
						table.insert(events, { kind = "Heal", statusId = inst.id, amount = applied })
						regenHeals += 1
						StatusService.NotifyHealGained(unit, applied)  -- Life Link share (2026-11-08)
					end
				end
			end
			if def.rechargeTickFraction and def.rechargeIntervalCt then
				inst.rechargeAccumCt = (inst.rechargeAccumCt or 0) + ctElapsed
				while inst.rechargeAccumCt >= def.rechargeIntervalCt do
					inst.rechargeAccumCt = inst.rechargeAccumCt - def.rechargeIntervalCt
					-- DB: restore round(Max MP × rechargeTickFraction), min 1, per event.
					local restore = math.max(1, math.round((unit.maxMp or 1) * def.rechargeTickFraction))
					local before = unit.currentMp or 0
					unit.currentMp = math.min(unit.maxMp or before, before + restore)
					local applied = unit.currentMp - before
					if applied > 0 then
						table.insert(events, { kind = "Mana", statusId = inst.id, amount = applied })
					end
				end
			end
		end

		-- SINKING (built 2026-10-11): Quicksand hazard. No remainingCt — ends only by
		-- escape (Water->Mud / Flight / teleport, handled elsewhere) or KO here. Every
		-- sinkIntervalCt (500) the unit sinks one level deeper; at sinkMaxLevel (5) the
		-- unit is KO'd. Accumulator mirrors Regeneration so a large ctElapsed that crosses
		-- several boundaries deepens once per boundary. Movement is already blocked via
		-- def.blocks.Move. A KO event is emitted so BattleCoordinator/Main can broadcast it.
		if def and inst.id == "Sinking" and def.sinkIntervalCt then
			inst.sinkAccumCt = (inst.sinkAccumCt or 0) + ctElapsed
			inst.sinkLevel = inst.sinkLevel or 0
			while inst.sinkAccumCt >= def.sinkIntervalCt and (unit.isAlive ~= false) do
				inst.sinkAccumCt = inst.sinkAccumCt - def.sinkIntervalCt
				inst.sinkLevel = inst.sinkLevel + 1
				table.insert(events, { kind = "Sink", statusId = inst.id, amount = inst.sinkLevel })
				if inst.sinkLevel >= (def.sinkMaxLevel or 5) and GameConstants.IsGodProtected and GameConstants.IsGodProtected(unit) then
					-- Dev god mode (2026-11-06): a protected unit never sinks to a KO.
					inst.sinkLevel = (def.sinkMaxLevel or 5) - 1
				elseif inst.sinkLevel >= (def.sinkMaxLevel or 5) then
					unit.currentHp = 0
					unit.isAlive = false
					table.insert(events, { kind = "KO", statusId = inst.id, reason = "Sinking" })
					print(string.format("[StatusService] %s KO by Sinking (level %d)", unit.name, inst.sinkLevel))
					break
				end
			end
		end

		-- Shield DECAY (runs for ANY shield instance, with or without a duration):
		-- lose shieldDecayFraction (10%) of the CURRENT shield pool every
		-- shieldDecayIntervalCt (300) CT. Mirrors the Regeneration accumulator so a
		-- large ctElapsed that crosses several boundaries decays once per boundary.
		-- Keeps the fast aggregate unit.shield_total in sync with this instance's
		-- shieldHp (1:1 — one Shield instance per unit). The min-1 chip guarantees a
		-- no-duration shield still fully drains instead of shrinking asymptotically.
		-- (DB TRG-015 / shield decay rule; cadence matches all other 300-CT ticks.)
		if def and def.shieldDecayFraction and def.shieldDecayIntervalCt and inst.shieldHp then
			inst.decayAccumCt = (inst.decayAccumCt or 0) + ctElapsed
			while inst.decayAccumCt >= def.shieldDecayIntervalCt and inst.shieldHp > 0 do
				inst.decayAccumCt = inst.decayAccumCt - def.shieldDecayIntervalCt
				local loss = math.round(inst.shieldHp * def.shieldDecayFraction)
				if loss < 1 then loss = 1 end  -- always chip at least 1 so it drains
				if loss > inst.shieldHp then loss = inst.shieldHp end
				inst.shieldHp = inst.shieldHp - loss
				unit.shield_total = math.max(0, (unit.shield_total or 0) - loss)
				if loss > 0 then
					table.insert(events, { kind = "Shield", statusId = inst.id, amount = -loss, reason = "decay" })
				end
			end
		end

		-- D5 (2026-11-07): another source's Pin under a Venus hold counts down on its own; the
		-- Venus hold itself never expires on the clock (only the plant lets go).
		if inst.venusHold then
			if inst.remainingCt then
				inst.venusOtherCt = math.max(inst.venusOtherCt or 0, inst.remainingCt)
				inst.remainingCt = nil
			end
			if inst.venusOtherCt then
				inst.venusOtherCt = inst.venusOtherCt - ctElapsed
				if inst.venusOtherCt <= 0 then inst.venusOtherCt = nil end
			end
		end
		if inst.remainingCt then
			inst.remainingCt = inst.remainingCt - ctElapsed
			if inst.remainingCt <= 0 then
				-- Shield expiry: a shield that runs out its duration simply vanishes
				-- (no Retribution — that only triggers on a BREAK, per the recipe).
				-- Drop its remaining capacity from the aggregate pool.
				if inst.shieldHp then
					unit.shield_total = math.max(0, (unit.shield_total or 0) - inst.shieldHp)
				if (unit.shield_total or 0) <= 0 then unit.shieldElementalOnly = nil end  -- ward expired (2026-11-05)
					table.insert(events, { kind = "Shield", statusId = inst.id, amount = -(inst.shieldHp), reason = "expire" })
				end
				table.insert(expired, inst.id)
				print(string.format("[StatusService] %s EXPIRED (CT) on %s", inst.id, unit.name))
				table.remove(unit.statusInstances, i)
			else
				i = i + 1
			end
		else
			i = i + 1
		end
	end
	-- AC-007 Overflowing Flask (2026-10-29): item regen entries on unit._itemRegen (added by
	-- ItemEffectService when a restoring item is used by a Flask wearer). Each entry restores a fixed
	-- amount (7% of what the item restored) every intervalCt for remainingCt. Not a status: no icon,
	-- not dispellable. HP ticks honour healing reduction like Regeneration does.
	if unit._itemRegen then
		local k = 1
		while k <= #unit._itemRegen do
			local e = unit._itemRegen[k]
			local step = math.min(ctElapsed, e.remainingCt)
			e.accumCt = (e.accumCt or 0) + step
			e.remainingCt -= step
			while e.accumCt >= e.intervalCt do
				e.accumCt -= e.intervalCt
				if e.kind == "MP" then
					local before = unit.currentMp or 0
					unit.currentMp = math.min(unit.maxMp or before, before + e.perTick)
					local applied = unit.currentMp - before
					if applied > 0 then table.insert(events, { kind = "Mana", statusId = "Overflowing Flask", amount = applied }) end
				else
					local heal = e.perTick
					local _hrm = StatusService.GetHealingReceivedMult(unit)
					if _hrm ~= 1 then heal = math.max(0, math.floor(heal * _hrm)) end
					local before = unit.currentHp or 0
					unit.currentHp = math.min(unit.maxHp or before, before + heal)
					local applied = unit.currentHp - before
					if applied > 0 then
						table.insert(events, { kind = "Heal", statusId = "Overflowing Flask", amount = applied })
						regenHeals += 1
						StatusService.NotifyHealGained(unit, applied)  -- Life Link share (2026-11-08)
					end
				end
			end
			if e.remainingCt <= 0 then
				table.remove(unit._itemRegen, k)
			else
				k += 1
			end
		end
		if #unit._itemRegen == 0 then unit._itemRegen = nil end
	end

	-- Healing weakens Venom (user ruling 2026-10-26): each regeneration heal counts once.
	-- Done after the scan so removing Venom cannot shift the list mid-loop.
	for _ = 1, regenHeals do
		if StatusService.WeakenVenomOnHeal(unit) == nil then break end
	end
	for _, _rid in ipairs(expired) do onStatusEnded(unit, _rid) end
	if _onNaturalExpiry then
		for _, _rid in ipairs(expired) do _onNaturalExpiry(unit, _rid) end  -- BUG-140
	end
	return expired, events
end

--------------------------------------------------
-- STATUS-BASED STAT MODIFIERS (Phase 2+)
--
-- Returns a table of { STAT = multiplier_offset } for all active
-- status effects that modify stats. Consumers multiply:
--   final = base × (1 + sum_of_offsets)
--
-- Weakened: all main stats -10% (offset = -0.10 per stat)
-- Giant Transformation: STR +20%, VIT +20%, INT -20%, DEX -20%, AGI -20%
-- Rush: DEX -20%
-- Crippled: handled separately (movement/jump reduction, not stat %)
-- Enlightened: all main stats +10% per stack
--------------------------------------------------

function StatusService.GetStatusStatModifiers(unit)
	local mods = { STR = 0, AGI = 0, INT = 0, VIT = 0, DEX = 0, LUK = 0 }
	local hasAny = false

	for _, inst in ipairs(unit.statusInstances) do
		if inst.id == "Weakened" then
			for stat in pairs(mods) do mods[stat] = mods[stat] - 0.10 * vscale(inst) end
			hasAny = true
		elseif inst.id == "Giant Transformation" then
			mods.STR = mods.STR + 0.20
			mods.VIT = mods.VIT + 0.20
			mods.INT = mods.INT - 0.20
			mods.DEX = mods.DEX - 0.20
			mods.AGI = mods.AGI - 0.20
			hasAny = true
		elseif inst.id == "Rush" then
			mods.DEX = mods.DEX - 0.20
			hasAny = true
		elseif inst.id == "Enlightened" then
			local stacks = inst.stacks or 1
			local bonus = stacks * 0.10
			for stat in pairs(mods) do mods[stat] = mods[stat] + bonus end
			hasAny = true
		end

		-- Data-driven stat buffs (Slice 5 map objects): any status def carrying
		-- statPctMod folds in here. Covers Banner Blessing (+15% all) and
		-- Fortune Boon (+50% LUK) without bespoke branches. The hardcoded cases
		-- above are left intact to avoid changing their behavior.
		local def = GameConstants.STATUSES[inst.id]
		if def and def.statPctMod then
			for stat, pct in pairs(def.statPctMod) do
				if mods[stat] ~= nil then
					mods[stat] = mods[stat] + pct * vscale(inst)
					hasAny = true
				end
			end
		end
	end

	return hasAny and mods or nil
end

--------------------------------------------------
-- MOVEMENT RANGE MODIFIERS FROM STATUS
-- Rush: +3 movement. Crippled: reduced by max(2, 50% current), min 1.
--------------------------------------------------

function StatusService.GetMovementRangeModifier(unit)
	local offset = 0
	for _, inst in ipairs(unit.statusInstances) do
		if inst.id == "Rush" then
			offset = offset + 3
		end
		-- Data-driven move buffs (Slice 5): any status def with moveOffset (Rally +1).
		local def = GameConstants.STATUSES[inst.id]
		if def and def.moveOffset then
			offset = offset + math.round(def.moveOffset * vscale(inst))
		end
	end
	return offset
end

-- Jump modifier from status buffs (Slice 5): sums jumpOffset across active
-- statuses (Rally +1). Read by the jump calculation in TargetingService.
function StatusService.GetJumpModifier(unit)
	local offset = 0
	for _, inst in ipairs(unit.statusInstances) do
		local def = GameConstants.STATUSES[inst.id]
		if def and def.jumpOffset then
			offset = offset + def.jumpOffset
		end
	end
	return offset
end

-- Outgoing-damage multiplier from status buffs (Slice 5). isSpell selects
-- spellDamageMult (Spell Focus) vs physDamageMult (Battle Rage); attackMult
-- (Rune Ward) applies to both. Returns a multiplier (1.0 = no change).
function StatusService.GetDamageDealtMultiplier(unit, isSpell)
	local mult = 1.0
	for _, inst in ipairs(unit.statusInstances) do
		local def = GameConstants.STATUSES[inst.id]
		if def then
			-- Ruling 10: totaled, not multiplied.
			local sc = vscale(inst)
			if isSpell and def.spellDamageMult then
				mult = mult + (def.spellDamageMult - 1) * sc
			elseif (not isSpell) and def.physDamageMult then
				mult = mult + (def.physDamageMult - 1) * sc
			end
			if def.attackMult then
				mult = mult + (def.attackMult - 1) * sc
			end
		end
	end
	-- HD-020 Commandant Helm (2026-10-29): +20% damage while the timed bonus lasts (totaled, ruling 10).
	if (unit._commandantDmgCt or 0) > 0 then
		mult = mult + (unit._commandantDmgBonus or 0.20)
	end
	-- Blunted (Breaker, elements_statuses 132, 2026-11-21): direct damage dealt x0.80, multiplicative.
	-- Only Basic Attack / skill resolution read this function, so DoT, traps and collision are untouched.
	local blunt = 1
	for _, inst in ipairs(unit.statusInstances) do
		local def = GameConstants.STATUSES[inst.id]
		if def and def.directDamageDealtMult then
			blunt = blunt * (1 - (1 - def.directDamageDealtMult) * vscale(inst))
		end
	end
	-- Dungeon RL-19 Berserker's Oath (2026-11-15): x0.75 damage dealt, battle-only stamp (nil elsewhere).
	return math.max(0, mult) * blunt * (tonumber(unit._dgDealtMult) or 1)
end

-- Incoming-defense multiplier from status buffs (Slice 5): Rune Ward +10%
-- Defense. Read where effective defense is computed in CombatResolver.
function StatusService.GetDefenseMultiplier(unit)
	local mult = 1.0
	-- stackGroup (D3 fix 2026-10-27): statuses in the same group do not stack with each other;
	-- only the strongest one counts (Corroded / Corroded Lesser). Different effects still add up.
	local groupBest = {}
	for _, inst in ipairs(unit.statusInstances) do
		local def = GameConstants.STATUSES[inst.id]
		if def and def.defenseMult then
			local delta = (def.defenseMult - 1) * vscale(inst)
			if def.stackGroup then
				local cur = groupBest[def.stackGroup]
				if cur == nil or math.abs(delta) > math.abs(cur) then groupBest[def.stackGroup] = delta end
			else
				mult = mult + delta
			end
		end
	end
	for _, d in pairs(groupBest) do mult = mult + d end
	-- Dungeon RL-17 War Banner (2026-11-15): enemies x1.10 Defense in that dungeon battle only (nil elsewhere).
	return math.max(0, mult) * (tonumber(unit._dgDefMult) or 1)
end

-- Equipment-Defense multiplier from statuses (Armored x1.20, Armor Break x0.80; status rows
-- 113 / 118, audit fix 2026-10-27). CombatResolver applies it to the unit's equipment Defense
-- BEFORE the VIT Defense Power curve. Same totaling (ruling 10), debuff-resistance value scale
-- and stackGroup rules as GetDefenseMultiplier.
function StatusService.GetEquipDefenseMultiplier(unit)
	local mult = 1.0
	local groupBest = {}
	for _, inst in ipairs((unit and unit.statusInstances) or {}) do
		local def = GameConstants.STATUSES[inst.id]
		if def and def.equipDefenseMult then
			local delta = (def.equipDefenseMult - 1) * vscale(inst)
			if def.stackGroup then
				local cur = groupBest[def.stackGroup]
				if cur == nil or math.abs(delta) > math.abs(cur) then groupBest[def.stackGroup] = delta end
			else
				mult = mult + delta
			end
		end
	end
	for _, d in pairs(groupBest) do mult = mult + d end
	return math.max(0, mult)
end

-- Stability offset from statuses (Hold the Line +2, War Cry +1; 2026-10-07).
-- Read wherever push distance uses target Stability (DisplacementService + Main
-- push preview) so both stay identical. Push Distance = max(0, Force - Stability).
function StatusService.GetStabilityModifier(unit)
	local offset = 0
	for _, inst in ipairs(unit.statusInstances or {}) do
		local def = GameConstants.STATUSES[inst.id]
		if def and def.stabilityOffset then
			offset = offset + math.round(def.stabilityOffset * vscale(inst))
		end
	end
	return offset + deviceAuraStability(unit)
end

-- Final DIRECT damage received multiplier from statuses (Hold the Line x0.85).
-- Applied by CombatResolver to basic attacks and skill hits only (not DoT ticks).
function StatusService.GetDamageReceivedMultiplier(unit)
	local mult = 1.0
	for _, inst in ipairs(unit.statusInstances or {}) do
		local def = GameConstants.STATUSES[inst.id]
		if def and def.damageTakenMult then
			mult = mult + (def.damageTakenMult - 1) * vscale(inst)
		end
	end
	-- Dungeon relics (step 8; rule 271 RL-10 / RL-15): x the relic damage-taken scale (direct hits only, like
	-- the statuses above). Set by Main on dungeon party units for a dungeon battle; nil elsewhere.
	return math.max(0, mult) * (unit._dgDamageTakenMult or 1)
end

function StatusService.GetCrippledReduction(unit, currentRange, currentJump)
	for _, inst in ipairs(unit.statusInstances) do
		if inst.id == "Crippled" then
			-- Move Range reduced by max(2, 50% current), min final 1
			local moveReduction = math.round(math.max(2, math.floor(currentRange * 0.50)) * vscale(inst))
			local finalMove = math.max(1, currentRange - moveReduction)
			-- Jump reduced by max(1, 50% current), min final 0
			local jumpReduction = math.round(math.max(1, math.floor(currentJump * 0.50)) * vscale(inst))
			local finalJump = math.max(0, currentJump - jumpReduction)
			return finalMove, finalJump
		end
	end
	return currentRange, currentJump
end

--------------------------------------------------
-- GET STATUS SUMMARY (for broadcasting)
--------------------------------------------------

-- Current DOT tick damage for a single active status on `unit`, using the SAME formulas
-- as GetStatusSummary / ProcessStartOfTurn (the authoritative DOT math lives here). Returns
-- 0 if the unit does not have the status or it has no current DOT. Pure (no side effects);
-- the caller applies the damage. Added for Perks & Flaws status Specialist "trigger" (2026-10-23).
-- Bleed bonus damage fraction of Max HP (elements_statuses 54; DESIGNER RULING 2026-11-21: 5% -> 3%,
-- every source). Exported so CombatResolver's on-hit Bleed uses the same number (DAT-001).
local BLEED_HP_FRACTION = 0.03
StatusService.BLEED_HP_FRACTION = BLEED_HP_FRACTION

function StatusService.GetCurrentDotDamage(unit, statusId)
	local inst = StatusService.HasStatus(unit, statusId)
	if not inst then return 0 end
	local def = GameConstants.STATUSES[inst.id]
	-- Same math as the real ticks (checklist fix 2026-10-29): Debuff Resistance, DoT-received traits
	-- (Iron Stomach / Weak Stomach, Fire-Hardened / Flammable, Antivenom / Thin Blood), Plague Doctor.
	if inst.id == "Poison" and def and def.dotFraction then
		return math.max(1, math.round((unit.maxHp or 1) * def.dotFraction
			* penetrate(StatusService.GetDebuffResist(unit), inst.resistPen)
			* TraitEffectService.GetDotDamageReceivedModifier(unit, "Poison")
			* doctrinePoisonTickMult(inst)
			* GameConstants.GetBossMod(unit, "hpPctDebuff"))) -- BUG-155: Boss HP% Modifier (core_stats 40)
	elseif inst.id == "Burn" then
		return StatusService.GetBurnTickDamage(unit, inst)
	elseif inst.id == "Venom" then
		local stacks = inst.stacks or 1
		local frac = (def and def.tickFraction) or 0.03
		return math.max(1, math.round((unit.maxHp or 1) * frac * stacks
			* penetrate(StatusService.GetDebuffResist(unit), inst.resistPen)
			* TraitEffectService.GetDotDamageReceivedModifier(unit, "Venom")
			* doctrinePoisonTickMult(inst)
			* GameConstants.GetBossMod(unit, "hpPctDebuff"))) -- BUG-155: Boss HP% Modifier (core_stats 40)
	elseif inst.id == "Bleed" then
		-- Same as Bleed's own on-hit damage (CombatResolver ApplyOutcome): x Debuff Resistance x
		-- Quick Clotting / Hemophiliac (2026-10-29).
		return math.max(1, math.round((unit.maxHp or 1) * BLEED_HP_FRACTION * StatusService.GetDebuffResist(unit)
			* TraitEffectService.GetDotDamageReceivedModifier(unit, "Bleed")
			* GameConstants.GetBossMod(unit, "hpPctDebuff"))) -- BUG-159: Boss HP% Modifier (core_stats 40); real hit + previews
	end
	return 0
end

function StatusService.GetStatusSummary(unit)
	local summary = {}
	for _, inst in ipairs(unit.statusInstances) do
		local def = GameConstants.STATUSES[inst.id]
		-- Calculate expected next-tick damage
		local nextDamage = nil
		if def then
			-- Tester batch 12 F1 / BUG-159 (core_stats 40): HP%-debuff previews x Boss HP% Modifier (1 for non-bosses).
			local _bm = GameConstants.GetBossMod(unit, "hpPctDebuff")
			if def.dotType == "Poison" then
				nextDamage = math.max(1, math.round(unit.maxHp * def.dotFraction * _bm))
			elseif def.dotType == "Burn" then
				local stored = inst.storedBurn or 0
				if stored > 0 and not isBurnDamageImmune(unit) then  -- Dragonscale: 0 next-tick
					nextDamage = math.max(1, math.round(stored))
				end
			elseif inst.id == "Venom" then
				local stacks = inst.stacks or 1
				nextDamage = math.max(1, math.round(unit.maxHp * 0.03 * stacks * _bm))
			elseif inst.id == "Bleed" then
				nextDamage = math.max(1, math.round(unit.maxHp * BLEED_HP_FRACTION * _bm))
			elseif inst.id == "Raptured" then
				nextDamage = math.max(1, math.round(unit.maxHp * 0.02 * _bm))
			elseif inst.id == "Wounded" then
				nextDamage = math.max(1, math.round(unit.maxHp * 0.15 * _bm))
			end
		end
		table.insert(summary, {
			id             = inst.id,
			remainingTurns = inst.remainingTurns,
			storedBurn     = inst.storedBurn,
			nextDamage     = nextDamage,
			stacks         = inst.stacks,
			-- USER RULING 2026-10-30 3:27 PM: an aura-owned status (War Banner / Cursed Statue) has no
			-- timer while the unit stays in range; the status card shows "While in range" instead.
			-- Owned = tagged by ObjectEffectService and not since refreshed by another source.
			whileInRange   = (inst.auraSourceId ~= nil and inst.sourceUnitId == inst.auraSourceId) or nil,
		})
	end
	return summary
end

--------------------------------------------------
-- PURGE / DISPEL (remove dispellable buffs)
--
-- Used by Purge/Dispel skills. Removes all statuses
-- where def.dispellable == true.
-- Returns list of removed status IDs.
--------------------------------------------------

function StatusService.RemoveDispellable(unit)
	local removed = {}
	local i = 1
	while i <= #unit.statusInstances do
		local inst = unit.statusInstances[i]
		local def = GameConstants.STATUSES[inst.id]
		if def and def.dispellable and not StatusService.IsUndispellable(inst) then
			table.insert(removed, inst.id)
			print(string.format("[StatusService] %s PURGED from %s", inst.id, unit.name))
			table.remove(unit.statusInstances, i)
		else
			i = i + 1
		end
	end
	-- Break sync + Oversleep, after the scan so a new Sleep Immunity is not counted down this turn.
	for _, _rid in ipairs(removed) do onStatusEnded(unit, _rid) end
	return removed
end

-- Remove ONE random active debuff (kind == "Debuff") from the unit. Used by the
-- Cleanse perk (TRAIT-P-132) on enemy KO. Returns the removed status id, or nil if
-- the unit has no debuffs. Does not touch buffs or special statuses.
-- Undispellable rule shared by every dispel / cleanse / purge (BUG-104, 2026-11-21): a status is
-- protected when its definition says undispellable (Thawed, Sleep Immunity) or the instance was
-- tagged undispellable at apply time (weather hard-locks, WeatherService). DAT-001: one reader.
function StatusService.IsUndispellable(inst)
	if not inst then return false end
	if inst.undispellable then return true end
	local def = GameConstants.STATUSES[inst.id]
	return def ~= nil and def.undispellable == true
end

function StatusService.RemoveRandomDebuff(unit)
	if not unit.statusInstances then return nil end
	local debuffIdx = {}
	for i, inst in ipairs(unit.statusInstances) do
		local def = GameConstants.STATUSES[inst.id]
		if def and def.kind == "Debuff" and not StatusService.IsUndispellable(inst) then
			table.insert(debuffIdx, i)
		end
	end
	if #debuffIdx == 0 then return nil end
	local pick = debuffIdx[math.random(1, #debuffIdx)]
	local removedId = unit.statusInstances[pick].id
	table.remove(unit.statusInstances, pick)
	print(string.format("[StatusService] %s CLEANSED from %s (random debuff)", removedId, unit.name))
	onStatusEnded(unit, removedId)  -- Break sync + Oversleep
	return removedId
end

-- Remove ONE random active BUFF (kind == "Buff") from the unit. Mirror of
-- RemoveRandomDebuff; used by the Purifier perk (TRAIT-P-107) on a landed hit. Returns the
-- removed status id, or nil if the unit has no buffs. Does not touch debuffs or specials.
function StatusService.RemoveRandomBuff(unit)
	if not unit.statusInstances then return nil end
	local buffIdx = {}
	for i, inst in ipairs(unit.statusInstances) do
		local def = GameConstants.STATUSES[inst.id]
		if def and def.kind == "Buff" and not StatusService.IsUndispellable(inst) then
			table.insert(buffIdx, i)
		end
	end
	if #buffIdx == 0 then return nil end
	local pick = buffIdx[math.random(1, #buffIdx)]
	local removedId = unit.statusInstances[pick].id
	table.remove(unit.statusInstances, pick)
	print(string.format("[StatusService] %s DISPELLED from %s (random buff)", removedId, unit.name))
	return removedId
end

--------------------------------------------------
-- ACTION BLOCKING (Phase 2)
--
-- Reads the `blocks` table from GameConstants.STATUSES.
-- Returns true + reason if any active status blocks this action type.
-- actionType: "Move", "Attack", "AttackObject", "Skill", "Guard", "Wait", "Push"
--------------------------------------------------

function StatusService.IsActionBlocked(unit, actionType)
	-- Guard and Wait are never blocked by status effects
	if actionType == "Guard" or actionType == "Wait" then
		return false, nil
	end

	for _, inst in ipairs(unit.statusInstances) do
		local def = GameConstants.STATUSES[inst.id]
		if def and def.blocks then
			if def.blocks.All then
				return true, inst.id .. " prevents all actions"
			end
			if actionType == "Skill" and def.blocks.Skills then
				return true, inst.id .. " prevents skill use"
			end
			-- BUG-080 (2026-11-21): a basic attack on an object ("AttackObject": barrels, walls, OBS
			-- props) is still a Basic Attack (elements_statuses row 65, Disarmed: "Prevents Basic
			-- Attack only"), so blocks.BasicAttack covers both kinds. "AttackObject" used to match
			-- no branch here, so a Disarmed unit could still hit objects.
			if (actionType == "Attack" or actionType == "AttackObject") and def.blocks.BasicAttack then
				return true, inst.id .. " prevents basic attack"
			end
			if actionType == "Move" and def.blocks.Move then
				return true, inst.id .. " prevents movement"
			end
		end
	end
	return false, nil
end

--------------------------------------------------
-- TURN SKIP CHECK (Phase 2)
--
-- Returns true + reason if the unit's turn should be
-- auto-skipped (Sleep, Petrify, Stun, Knock-out).
--------------------------------------------------

function StatusService.ShouldSkipTurn(unit)
	for _, inst in ipairs(unit.statusInstances) do
		local def = GameConstants.STATUSES[inst.id]
		if def and def.skipsTurn then
			return true, inst.id
		end
	end
	return false, nil
end

--------------------------------------------------
-- ON DAMAGE RECEIVED (Phase 2)
--
-- Called after damage is applied to a unit.
-- Currently handles: Sleep removed by damage.
-- Returns a table of status IDs that were removed.
--------------------------------------------------

function StatusService.OnDamageReceived(unit, damage)
	if damage <= 0 then return {} end

	local removed = {}

	-- Sleep: "Damage from any source removes Sleep immediately"
	local sleepInst = StatusService.HasStatus(unit, "Sleep")
	if sleepInst then
		StatusService.RemoveStatus(unit, "Sleep")
		table.insert(removed, "Sleep")
		print(string.format("[StatusService] Sleep BROKEN by damage on %s", unit.name))

		-- Sleep Immunity (Oversleep) is applied by RemoveStatus itself (2026-10-29).
	end

	return removed
end

return StatusService
