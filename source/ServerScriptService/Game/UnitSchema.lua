-- UnitSchema.lua
-- CTRBLXAI | Slice 4A — Equipment Foundation
--
-- HP formula: HP = 50 + VIT × 4
-- MP formula: MP = 20 + INT × 2
--
-- Slice 4B changes:
--   - Create() accepts optional currentHp/currentMp for persistent resource loading
--   - mpRegenAccumulator field for fractional MP regen tracking

-- Slice 4A changes:
--   - Equipment slots added to unit state
--   - Doctrine reference added
--   - Weapon stats read from equipped weapon (not flat input)
--   - effectiveStats rebuilt by EquipmentService (not copied from input)
--   - Backwards-compatible: if no equipment, uses legacy flat values

-- SHIELD SUBSYSTEM (2026-10-05): units carry a shield_total absorption pool.
--   All eligible damage (basic attack, skill, DoT, collision, reflect, Mana Burn)
--   funnels through UnitSchema.ApplyDamage, so the shield gate lives HERE and
--   covers every path (DB TRG-015 / damage-pipeline step G5: "Consume Shield
--   before HP, including DoT"). The shield pool is kept in sync with the live
--   "Shield" status instances by StatusService; ApplyDamage mutates shield_total
--   directly for speed and records a transient break record so the caller (which
--   knows the attacker) can resolve Retribution Shell's on-break retaliation.

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

-- Dev-tool gate (2026-11-06): Studio, or a server where every player is an allow-listed owner.
local DevAccess = require(script.Parent:WaitForChild("DevAccess"))

local UnitSchema = {}

--------------------------------------------------
-- FORMULAS
--------------------------------------------------

local function calcMaxHp(vit)
	return 50 + vit * 4
end

local function calcMaxMp(int)
	return 20 + int * 2
end

--------------------------------------------------
-- DEFAULTS
--------------------------------------------------

local DEFAULT_AP = 3

--------------------------------------------------
-- CREATE
--
-- definition fields:
--   REQUIRED: id, side, controller, tileX, tileY, stats
--   OPTIONAL: equipmentSlots, doctrineId, weaponDamage (legacy),
--             weaponWt (legacy), skillIds, startingRt, level
--
-- If equipmentSlots.MainHand is provided, weapon stats come from there.
-- Otherwise falls back to legacy flat weaponDamage/weaponWt.
--------------------------------------------------

function UnitSchema.Create(definition)
	assert(type(definition) == "table", "UnitSchema.Create: definition must be a table.")
	assert(type(definition.id) == "string" and #definition.id > 0,
		"UnitSchema.Create: id must be a non-empty string.")
	assert(definition.side == "Player" or definition.side == "Enemy",
		'UnitSchema.Create: side must be "Player" or "Enemy".')
	assert(definition.controller == "Player" or definition.controller == "AI",
		'UnitSchema.Create: controller must be "Player" or "AI".')
	assert(type(definition.tileX) == "number" and type(definition.tileY) == "number",
		"UnitSchema.Create: tileX and tileY must be numbers.")

	-- Resolve base stats: race-derived (4F) or legacy flat table
	local resolvedStats
	local raceId = definition.raceId or nil
	local level = definition.level or 1

	if raceId then
		-- Race-derived: base stats = startingStat + floor(growth × (level - 1))
		resolvedStats = RaceData.CalcBaseStats(raceId, level)
		assert(resolvedStats, "UnitSchema.Create: invalid raceId: " .. tostring(raceId))
	elseif definition.stats then
		-- Legacy: raw stat table (enemies, test units)
		resolvedStats = definition.stats
	else
		error("UnitSchema.Create: either raceId or stats must be provided.")
	end

	local vit = resolvedStats.VIT or 10
	local int = resolvedStats.INT or 10
	local maxHp = calcMaxHp(vit)
	local maxMp = definition.maxMp or calcMaxMp(int)

	local unit = {
		-- Identity
		id            = definition.id,
		name          = definition.name or definition.id,

		-- Battle team
		side          = definition.side,
		controller    = definition.controller,

		-- AI behavior role (Basic/Elite/Boss) — drives AIService tier selection.
		-- Previously dropped here, silently forcing every enemy to "Basic".
		aiRole        = definition.aiRole or "Basic",

		-- Position
		tileX         = definition.tileX,
		tileY         = definition.tileY,
		facing        = definition.facing or "South",

		-- Race identity (Slice 4F)
		raceId        = raceId,

		-- Perks and drawbacks (Slice 4F — fields only, content catalog pending)
		perkIds       = definition.perkIds or {},
		drawbackIds   = definition.drawbackIds or {},

		-- Core stats (permanent base — race growth + allocation)
		baseStats     = {
			STR = resolvedStats.STR or 10,
			AGI = resolvedStats.AGI or 10,
			INT = resolvedStats.INT or 10,
			VIT = resolvedStats.VIT or 10,
			DEX = resolvedStats.DEX or 10,
			LUK = resolvedStats.LUK or 10,
		},
		-- Effective stats (rebuilt by EquipmentService after doctrine+equipment)
		effectiveStats = {
			STR = resolvedStats.STR or 10,
			AGI = resolvedStats.AGI or 10,
			INT = resolvedStats.INT or 10,
			VIT = resolvedStats.VIT or 10,
			DEX = resolvedStats.DEX or 10,
			LUK = resolvedStats.LUK or 10,
		},

		-- Hit points
		maxHp         = maxHp,
		currentHp     = definition.currentHp or maxHp,

		-- Magic points
		maxMp         = maxMp,
		currentMp     = definition.currentMp or maxMp,

		-- MP Regen accumulator (Slice 4B: fractional CT-based regen)
		mpRegenAccumulator = 0,

		-- Shield absorption pool (2026-10-05 shield subsystem). Aggregate current
		-- Shield capacity (DB battle schema field "shield_total"). Soaks eligible
		-- damage before HP; decays 10%/300 CT via StatusService. 0 = no shield.
		-- Starts fresh each battle (not persisted — a battle-scoped buffer).
		shield_total  = 0,

		-- Weapon stats (populated by EquipmentService.RebuildUnitStats or legacy)
		weaponDamage  = definition.weaponDamage or 10,
		weaponWt      = definition.weaponWt or 40,
		weaponRtDelay = definition.weaponRtDelay or 0,
		weaponDefense = definition.weaponDefense or 0,
		weaponMinRange = definition.weaponMinRange or 1,
		weaponMaxRange = definition.weaponMaxRange or 1,
		weaponPattern = definition.weaponPattern or "Single",
		weaponProjectileType = definition.weaponProjectileType or nil,
		weaponHandClass = definition.weaponHandClass or "1H",

		-- Equipment (Slice 4A)
		equipmentSlots = definition.equipmentSlots or nil,
		doctrineId     = definition.doctrineId or nil,

		-- Timeline: Starting RT uses LUK formula if no explicit override
		-- Rule: Starting RT = round(Base RT × (1 - 0.30 × LUK / (100 + LUK)))
		remainingRt   = definition.startingRt
			or GameConstants.CalcStartingRt(GameConstants.BASE_RT_STANDARD, resolvedStats.LUK or 10),

		-- Turn resources
		currentAp     = 0,

		-- Skills (units can have multiple skills)
		skillIds      = definition.skillIds or {},
		-- Legacy single skill support
		skillId       = definition.skillId or nil,

		-- Status effects
		statusInstances = {},

		-- Level (persistent — drives race stat growth, tie-breaking, item level)
		level         = definition.level or 1,

		-- Alive flag
		isAlive       = true,

		-- SUMMON FIELDS (2026-10-05 summon wiring). Present on ALL units but only
		-- meaningful on summoned units (isSummon=true). Built by EnemyGenerator.SpawnSummon
		-- from authored caster-% specs; non-summon units leave these at the defaults
		-- below so existing behaviour is unchanged.
		--   isSummon            : this unit was created by a summon skill
		--   summonOwnerId       : id of the casting unit (one-at-a-time replace key)
		--   summonType          : "Sentinel"/"Wisp"/"Mender"/"Decoy"/"Turret"/"WardTotem"
		--   summonProfile       : AI behaviour tag — "attack"/"heal"/"turret"/"idle"
		--   canMove             : false for stationary summons (Turret/Decoy/Totem)
		--   isFlying            : Wisp flies (movement/elevation hint; data only here)
		--   auraSpec            : Ward Totem continuous aura {radius, debuffResistMult}
		--   turretSnapshotDamage: Turret's snapshotted Basic Attack power (set at summon)
		--   rewardEligible      : summons grant NO rewards (false)
		--   killTriggerEligible : summons are Kill-Trigger ineligible (false)
		isSummon            = definition.isSummon or false,
		summonOwnerId       = definition.summonOwnerId or nil,
		summonType          = definition.summonType or nil,
		summonProfile       = definition.summonProfile or nil,
		canMove             = (definition.canMove ~= false),  -- defaults true unless explicitly false
		isFlying            = definition.isFlying or false,
		auraSpec            = definition.auraSpec or nil,
		turretSnapshotDamage = definition.turretSnapshotDamage or nil,
		rewardEligible      = (definition.rewardEligible ~= false),  -- defaults true (normal units)
		killTriggerEligible = (definition.killTriggerEligible ~= false),  -- defaults true
	}

	-- Migrate single skillId into skillIds array if needed
	if unit.skillId and #unit.skillIds == 0 then
		table.insert(unit.skillIds, unit.skillId)
	end

	-- Compute derived stats from effective stats + weapon data
	GameConstants.ComputeDerivedStats(unit)

	return unit
end

--------------------------------------------------
-- HELPERS
--------------------------------------------------

function UnitSchema.CanAct(unit)
	return unit.isAlive and unit.currentAp > 0
end

-- Channel state dies with the unit (UAT 2026-10-27 D-1): a unit killed mid-channel must never come
-- back (revive, Raise Dead, Zombie, item) still holding that channel, or it fires at once on return.
-- Returns true when there was a channel to clear.
function UnitSchema.ClearChannelState(unit): boolean
	local had = unit.isChanneling == true
	unit.isChanneling        = false
	unit.channelingData      = nil
	unit.channelRt           = nil
	unit.channelResolveCt    = nil
	unit.channelPhase        = nil
	unit.pendingActivationCt = nil
	return had
end

-- REVIVE TILE (2026-10-28, same rule as Raise Dead and the spreading revives): a unit coming back
-- where a living unit now stands rises on the nearest free tile within 3 (on the map, not blocked,
-- impassable or a chasm floor). No free tile = it cannot rise right now. mapW/mapH default to the
-- live terrain grid.
function UnitSchema.FindFreeTileNear(units, x, y, mapW, mapH)
	if not (mapW and mapH) then
		local grid = GameConstants.TERRAIN_MAP
		mapH = mapH or (grid and #grid or 0)
		mapW = mapW or ((grid and grid[1]) and #grid[1] or 0)
	end
	if (mapW or 0) <= 0 then mapW = math.huge end
	if (mapH or 0) <= 0 then mapH = math.huge end
	for r = 0, 3 do
		for dy = -r, r do
			for dx = -r, r do
				if math.max(math.abs(dx), math.abs(dy)) == r then
					local cx, cy = x + dx, y + dy
					if cx >= 1 and cy >= 1 and cx <= mapW and cy <= mapH
						and not GameConstants.IsBlocked(cx, cy) and not GameConstants.IsImpassableTerrain(cx, cy)
						and not (GameConstants.IsChasmFloor and GameConstants.IsChasmFloor(cx, cy)) then
						local taken = false
						for _, u in ipairs(units or {}) do
							if u.isAlive and u.tileX == cx and u.tileY == cy then taken = true break end
						end
						if not taken then
							return cx, cy
						end
					end
				end
			end
		end
	end
	return nil, nil
end

-- Where a KO'd unit rises. Returns tileX, tileY, moved; tileX nil = no free tile within 3.
-- Revive HP with the revive traits applied (re-check 2026-10-29, one rule for every revive):
-- Undying Will flaw -> exactly 1 HP; otherwise baseFrac x Slow to Recover (x0.5) + Resilient
-- (+20% max HP), at least 1, at most max HP. Same formula the revive skills and items use.
function UnitSchema.ReviveHp(unit, baseFrac)
	local maxHp = (unit and unit.maxHp) or 1
	local ok, tes = pcall(function() return (require :: any)(script.Parent.TraitEffectService) end)
	if not ok or not tes then
		return math.min(maxHp, math.max(1, math.ceil(maxHp * (baseFrac or 0))))
	end
	if tes.HasReviveAtOneHp(unit) then return 1 end
	local eff = (baseFrac or 0) * tes.GetReviveHpMultiplier(unit) + tes.GetReviveHpBonusFraction(unit)
	return math.min(maxHp, math.max(1, math.ceil(maxHp * eff)))
end

function UnitSchema.FindReviveTile(unit, units, mapW, mapH)
	for _, o in ipairs(units or {}) do
		if o.isAlive and o ~= unit and o.tileX == unit.tileX and o.tileY == unit.tileY then
			local tx, ty = UnitSchema.FindFreeTileNear(units, unit.tileX, unit.tileY, mapW, mapH)
			return tx, ty, tx ~= nil
		end
	end
	return unit.tileX, unit.tileY, false
end

-- DEV GOD MODE (user request 2026-11-06; Studio or allow-listed owner via DevAccess): every PLAYER-side unit can't be KO'd (a
-- lethal hit stops at 1 HP). Damage still lands and shows (user ruling). HP refills once at the
-- START of each protected unit's turn (BattleCoordinator); MP/AP refill after every command
-- (CommandService wrapper) for unlimited actions. Off by default.
UnitSchema.DevGodMode = false
function UnitSchema.IsGodProtected(unit): boolean
	return UnitSchema.DevGodMode == true and unit ~= nil and unit.side == "Player"
		and DevAccess.SessionAllowed()
end
GameConstants.IsGodProtected = function(u) return UnitSchema.IsGodProtected(u) end

function UnitSchema.GodRefill(unit, skipHp)
	if not UnitSchema.IsGodProtected(unit) then return end
	if not skipHp then unit.currentHp = unit.maxHp or unit.currentHp end
	unit.currentMp = unit.maxMp or unit.currentMp
	unit.currentAp = math.max(unit.currentAp or 0, 2)
end

-- Dev kill commands (InstantLose / KillAtTile) must kill even with god mode on.
function UnitSchema.ForceKill(unit)
	unit.isAlive   = false
	unit.currentHp = 0
	unit.currentAp = 0
	UnitSchema.ClearChannelState(unit)
end

function UnitSchema.Kill(unit)
	if UnitSchema.IsGodProtected(unit) and unit.isAlive ~= false then
		-- Survive at 1 HP so the hit still reads as damage; HP refills at the start of this unit's
		-- next turn (BattleCoordinator). Clear kill tags so objectives don't count a death.
		unit.isAlive = true
		unit.currentHp = math.max(1, unit.currentHp or 0)
		unit._killCause = nil
		unit._killedFromFull = nil
		return
	end
	unit.isAlive   = false
	unit.currentHp = 0
	unit.currentAp = 0
	UnitSchema.ClearChannelState(unit)
end

--------------------------------------------------
-- APPLY DAMAGE  (SHIELD GATE — DB TRG-015 / pipeline step G5)
--
-- Shield absorbs eligible damage BEFORE HP. This is the single chokepoint for
-- every damage path (basic attack, skill, DoT, collision, reflect, Mana Burn),
-- so inserting the gate here covers them all without touching each call site.
--
-- Returns:
--   actual        — HP actually removed (first return; UNCHANGED semantics for
--                    all existing callers that only read this value)
--   shieldBroke   — true if the shield pool was reduced to 0 by THIS call
--                   (i.e. it had shield > 0 before and 0 after)
--   shieldAbsorbed— amount of the incoming damage soaked by the shield
--   shieldMaxAtBreak — the shield instance's MAX HP at the moment it broke
--                    (for Retribution Shell on-break retaliation). nil if no break.
--   retributionDamage — (5th) the broken Retribution Shell's stamped on-break
--                    Physical snapshot (round(Shield Max HP x 0.50)); nil otherwise.
--                    Forwarded from StatusService.OnShieldAbsorb so ApplyOutcome
--                    can retaliate against the breaker (shield subsystem 2026-10-05).
--
-- The caller that knows the attacker (CombatResolver.ApplyOutcome, the DoT loop)
-- inspects shieldBroke to resolve on-break reactions. ApplyDamage itself stays
-- attacker-agnostic. StatusService owns the "Shield" status instances; this
-- function syncs them via StatusService.OnShieldAbsorb so the pill/duration and
-- the per-instance max-HP bookkeeping stay correct.
--------------------------------------------------

-- StatusService is injected (DI) to avoid a require cycle: StatusService requires
-- GameConstants/RaceData/TraitEffectService; UnitSchema is required by nearly
-- everything, so pulling StatusService in at module scope risks a cycle. Nil-safe:
-- with no StatusService wired, ApplyDamage still soaks shield_total directly.
local _statusService = nil
function UnitSchema.SetStatusService(ss)
	_statusService = ss
end

function UnitSchema.ApplyDamage(unit, amount, cause, shieldDamageMult, element)
	assert(amount >= 0, "ApplyDamage: amount must be >= 0.")
	-- One-Punch objective (2026-10-24): was this unit at full HP before this hit?
	-- Captured before the shield gate / HP subtraction below.
	local wasFull = (unit.currentHp or 0) >= (unit.maxHp or math.huge)

	local shieldAbsorbed = 0
	local shieldBroke = false
	local shieldMaxAtBreak = nil
	-- Retribution snapshot (shield subsystem — 2026-10-05). If the broken shield was
	-- a Retribution Shell, StatusService.OnShieldAbsorb returns its stamped
	-- retributionDamage (round(Shield Max HP x 0.50)) as a 3rd value. We forward it
	-- as ApplyDamage's 5th return so CombatResolver.ApplyOutcome (which knows the
	-- attacker) can retaliate against the breaker. nil for the other five shields.
	local shieldRetribution = nil

	-- SHIELD GATE: soak before HP. Decay never routes here (decay cannot damage
	-- HP — handled separately in StatusService.ProcessCtTick).
	local shield = unit.shield_total or 0
	-- ELEMENTAL-ONLY SHIELD (Draining Ward, user ruling 2026-11-05): it soaks only DIRECT hits
	-- that carry a real element (Fire, Ice, Wind...). `element` is optional; callers that do not
	-- pass it (DoTs, tiles, weather, push, fall, explosions) count as non-elemental and bypass
	-- the ward straight to HP. Every existing caller is unchanged when no ward is present.
	if shield > 0 and unit.shieldElementalOnly and (element == nil or element == "" or element == "Physical") then
		shield = 0
	end
	if shield > 0 and amount > 0 then
		-- GL-012 Crushing Vambraces: a push/collision may drain the shield at a MULTIPLIER (x2) so the
		-- shield is half as effective at stopping it ("collision deals double to shields"). mult defaults
		-- to 1 for every normal caller -> identical to the original gate. shieldDrain = shield points
		-- removed; damageStopped = incoming damage neutralized (= drain / mult, floored to stay integer).
		local mult = shieldDamageMult or 1
		local shieldDrain = math.min(shield, amount * mult)
		local damageStopped = math.floor(shieldDrain / mult)
		local soak = shieldDrain
		shieldAbsorbed = soak
		unit.shield_total = shield - soak
		amount = amount - damageStopped
		-- Let StatusService draw down the live Shield status instance(s) and tell
		-- us whether the pool just emptied (for Retribution on-break). If no
		-- StatusService is wired, infer the break from shield_total hitting 0.
		if _statusService and _statusService.OnShieldAbsorb then
			shieldBroke, shieldMaxAtBreak, shieldRetribution = _statusService.OnShieldAbsorb(unit, soak)
		elseif unit.shield_total <= 0 then
			shieldBroke = true
		end
	end

	-- FIXED-HIT DURABILITY (2026-10-26, DB objects_encounters "Deployed Gadget" SPLIT ruling):
	-- a light-gadget device unit (Mender Drone, Gravity Pylon) is destroyed after a fixed
	-- number of hits from ANY source; each damaging hit removes exactly 1, whatever its size.
	-- Its HP pool IS the hit counter (maxHp = hitsToDestroy), so bars and KO reuse the
	-- normal path.
	if unit.fixedHitDurability and amount > 0 then
		amount = 1
	end
	local hpBeforeHit = unit.currentHp
	local actual = math.min(unit.currentHp, amount)
	unit.currentHp = unit.currentHp - actual
	if unit.currentHp <= 0 then
		-- Optional kill-cause tag for the objective system (2026-10-24). Set only
		-- when this lethal hit carried a cause (e.g. "push"); never overwrite an
		-- already-stamped cause. Harmless no-op for every existing caller.
		if cause and not unit._killCause then unit._killCause = cause end
		-- One-Punch: a normal attack/skill (no special cause) that kills a unit
		-- which was at full HP = a single-hit full-HP KO. Push/terrain/etc. carry a
		-- cause and are excluded (they are not "attacks").
		if wasFull and not cause then unit._killedFromFull = true end
		UnitSchema.Kill(unit)
		-- God mode kept the unit at 1 HP: report the real HP lost (lifesteal, DoT numbers).
		if unit.isAlive then actual = hpBeforeHit - unit.currentHp end
	end
	return actual, shieldBroke, shieldAbsorbed, shieldMaxAtBreak, shieldRetribution
end

function UnitSchema.ApplyHealing(unit, amount)
	assert(amount >= 0, "ApplyHealing: amount must be >= 0.")
	-- Fixed-hit gadgets (Mender Drone, Gravity Pylon) are repaired, never healed: their HP
	-- pool is a hit counter (DB "Deployed Gadget" ruling; Repair resets it).
	if unit.fixedHitDurability then
		return 0
	end
	-- Festering Wound anti-heal: reduce ALL incoming healing routed through this primitive
	-- (skill heals, lifedrain/lifesteal, trait heals, grants, potions) while a healing-reduction
	-- debuff is active. Scanned inline via GameConstants.STATUSES (module-scope require); StatusService
	-- is dependency-injected here, not required, so it is NOT callable at module scope (avoids a cycle).
	local _hrm = 1
	if _statusService and _statusService.GetHealingReceivedMult then
		-- One formula (2026-10-29): statuses + Blessed Recovery / Cursed Wounds traits.
		_hrm = _statusService.GetHealingReceivedMult(unit)
	else
		for _, inst in ipairs(unit.statusInstances or {}) do
			local d = GameConstants.STATUSES[inst.id]
			-- Ruling 10 (2026-10-26): different healing modifiers are TOTALED, not multiplied
			-- (mirrors StatusService.GetHealingReceivedMult).
			if d and d.healingReceivedMult then _hrm = _hrm + (d.healingReceivedMult - 1) * (inst.valueScale or 1) end
		end
	end
	_hrm = math.max(0, _hrm)
	if _hrm ~= 1 then amount = math.max(0, math.floor(amount * _hrm)) end
	local actual = math.min(unit.maxHp - unit.currentHp, amount)
	unit.currentHp = unit.currentHp + actual
	-- Healing weakens Venom (user ruling 2026-10-26): a heal that restores HP lowers Venom by 1.
	if actual > 0 and _statusService and _statusService.WeakenVenomOnHeal then _statusService.WeakenVenomOnHeal(unit) end
	-- Life Link (2026-11-08): report the HP actually gained (skills, lifesteal, drain, items, pulses).
	if actual > 0 and _statusService and _statusService.NotifyHealGained then _statusService.NotifyHealGained(unit, actual) end
	return actual
end

function UnitSchema.SpendMp(unit, amount)
	assert(amount >= 0, "SpendMp: amount must be >= 0.")
	if unit.currentMp < amount then return false end
	unit.currentMp = unit.currentMp - amount
	return true
end

function UnitSchema.HasEnoughMp(unit, amount)
	return unit.currentMp >= amount
end

function UnitSchema.RefreshAp(unit)
	unit.currentAp = DEFAULT_AP
end

function UnitSchema.Describe(unit)
	return string.format(
		"[%s | %s | HP:%d/%d | MP:%d/%d | AP:%d | RT:%d | Tile:(%d,%d) | WpnDmg:%d WT:%d]",
		unit.name,
		unit.side,
		unit.currentHp,
		unit.maxHp,
		unit.currentMp or 0,
		unit.maxMp or 0,
		unit.currentAp,
		unit.remainingRt,
		unit.tileX,
		unit.tileY,
		unit.weaponDamage or 0,
		unit.weaponWt or 0
	)
end

return UnitSchema