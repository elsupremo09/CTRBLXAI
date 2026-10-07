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
local _onConflictRemoved = nil
function StatusService.SetConflictRemovedHandler(fn) _onConflictRemoved = fn end

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

function StatusService.SetWeatherBurnSuppressed(v)
	_weatherBurnSuppressed = v and true or false
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
	if not unit.raceId then return {} end
	local raceEntry = RaceData.GetRace(unit.raceId)
	if raceEntry and raceEntry.tags then
		return raceEntry.tags
	end
	return {}
end

-- DRAGONKIN — Dragonscale (races row 'Dragonkin', 2026-10-02): Burn DAMAGE
-- immunity -- NOT application immunity (Burn still applies and stays active so the
-- +15% stat bonus sees it). Race detection via RaceData.GetRace (nil-safe). Inline
-- here because StatusService cannot require RacePassiveService (circular dep).
local function isBurnDamageImmune(unit)
	if not unit or not unit.raceId then return false end
	if not RaceData.GetRace(unit.raceId) then return false end
	return unit.raceId == "RACE-DRAGONKIN"
end

function StatusService.IsImmune(unit, statusId)
	-- 0. Weather Burn-suppression (Rain / Snow Storm): block Burn APPLICATION.
	if statusId == "Burn" and _weatherBurnSuppressed then
		return true, "weather suppresses Burn"
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
function StatusService.ApplyStatus(unit, statusId, sourceUnitId, fireDamageDealt, durationCtOverride)
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

	-- Check if unit already has this status.
	for _, inst in ipairs(unit.statusInstances) do
		if inst.id == statusId then
			if def.reapply == "refresh" then
				inst.remainingTurns = def.duration
				-- CT-based statuses (e.g. CounterStance: durationCt=1000, duration=nil)
				-- must refresh their CT window too — resetting remainingTurns alone
				-- left the original CT deadline running on recast.
				if def.durationCt then
					inst.remainingCt = durationCtOverride or def.durationCt
				end
				inst.sourceUnitId   = sourceUnitId
				print(string.format(
					"[StatusService] %s on %s REFRESHED (%s)",
					statusId, unit.name, def.duration and (def.duration .. " turns") or "CT"
				))
				return false, disruptsChannel

			elseif def.reapply == "accumulate" then
				local addedBurn = 0
				if statusId == "Burn" and fireDamageDealt then
					addedBurn = math.round(fireDamageDealt * def.burnFraction)
				end
				inst.storedBurn = (inst.storedBurn or 0) + addedBurn
				inst.remainingTurns = def.duration
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
				inst.sourceUnitId = sourceUnitId
				print(string.format(
					"[StatusService] %s on %s STACKED (now %d stacks)",
					statusId, unit.name, inst.stacks
				))
				return false, disruptsChannel

			elseif def.reapply == "extend" then
				-- Regeneration, Overflow: add to remaining duration
				local addTurns = def.duration or 0
				inst.remainingTurns = (inst.remainingTurns or 0) + addTurns
				inst.sourceUnitId = sourceUnitId
				print(string.format(
					"[StatusService] %s on %s EXTENDED (+%d, now %d turns)",
					statusId, unit.name, addTurns, inst.remainingTurns
				))
				return false, disruptsChannel

			elseif def.reapply == "chain" then
				-- Bleed→Raptured, Raptured→Wounded, Wounded→Bleed
				inst.remainingTurns = def.duration  -- refresh self
				inst.sourceUnitId = sourceUnitId
				-- Apply next in chain
				local CHAIN_NEXT = { Bleed = "Raptured", Raptured = "Wounded", Wounded = "Bleed" }
				local nextStatus = CHAIN_NEXT[statusId]
				if nextStatus then
					print(string.format(
						"[StatusService] %s on %s CHAINED → applying %s",
						statusId, unit.name, nextStatus
					))
					StatusService.ApplyStatus(unit, nextStatus, sourceUnitId)
				end
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
		remainingTurns = def.duration,
		sourceUnitId   = sourceUnitId or "unknown",
		stacks         = 1,  -- default stack count for all statuses
	}

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

	if statusId == "Burn" and fireDamageDealt then
		instance.storedBurn = math.round(fireDamageDealt * def.burnFraction)
	elseif statusId == "Burn" then
		instance.storedBurn = 0
	end

	table.insert(unit.statusInstances, instance)

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

	print(string.format(
		"[StatusService] %s APPLIED to %s (%s turns)%s%s",
		statusId, unit.name, tostring(def.duration or "∞"),
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
function StatusService.ApplyShield(unit, shieldHp, durationCt, sourceUnitId, retributionDamage)
	shieldHp = math.max(0, math.round(shieldHp or 0))
	if shieldHp <= 0 then
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
	local bonus = 0 -- "Debuff Res Up" (Meditate): largest bonus only, -0.10 on the multiplier
	for _, inst in ipairs(unit.statusInstances or {}) do
		local d = GameConstants.STATUSES[inst.id]
		if d and d.debuffResistPenalty and d.debuffResistPenalty > penalty then
			penalty = d.debuffResistPenalty
		end
		if d and d.debuffResistBonus and d.debuffResistBonus > bonus then
			bonus = d.debuffResistBonus
		end
	end
	-- Net of Res Down and Res Up, clamped to [0, 1] (resistance between 0% and 100%).
	return math.clamp(base + penalty - bonus, 0, 1.0) * wardTotemMult(unit)
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
			local damage = math.max(1, math.round(unit.maxHp * def.dotFraction * debuffResist
				* TraitEffectService.GetDotDamageReceivedModifier(unit, inst.id)))
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
			local storedBurn = inst.storedBurn or 0
			if storedBurn > 0 then
				-- TRAIT-DOT-BURN: x unit-trait DoT-received multiplier (1.0 when no trait).
				local damage = math.max(1, math.round(storedBurn * debuffResist
					* TraitEffectService.GetDotDamageReceivedModifier(unit, "Burn")))
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

--------------------------------------------------
-- TICK STATUSES
--------------------------------------------------

function StatusService.TickStatuses(unit)
	local removed = {}
	local i = 1

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

	return removed
end

--------------------------------------------------
-- REMOVE STATUS
--------------------------------------------------

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
			return true
		end
	end
	return false
end

--------------------------------------------------
-- HAS STATUS
--------------------------------------------------

function StatusService.HasStatus(unit, statusId)
	for _, inst in ipairs(unit.statusInstances) do
		if inst.id == statusId then
			return inst
		end
	end
	return nil
end

--------------------------------------------------
-- GET MODIFIED BASE RT
--------------------------------------------------

function StatusService.GetModifiedBaseRt(unit)
	-- DB weapons_equipment id 7: Modified Base RT = Base RT + Effective Armor WT.
	-- Armor weight belongs HERE (base turn time), not in the per-action WT term.
	-- Base RT = the unit's OWN base (enemy kind sets initiativeBaseRt: Grunt 400 /
	-- Veteran 380 / Elite 350; players have no field → default 400) PLUS gear WT.
	-- Permanent modifiers (traits) and Haste/Slow multiply this below. All per-turn
	-- RT costs and the one-time starting RT derive from this value.
	local baseRt = (unit.initiativeBaseRt or GameConstants.BASE_RT_STANDARD) + GameConstants.CalcEffectiveArmorWt(unit)
	local multiplier = 1.0

	for _, inst in ipairs(unit.statusInstances) do
		local def = GameConstants.STATUSES[inst.id]
		if def and def.rtMultiplier then
			multiplier = multiplier * def.rtMultiplier
		end
	end

	-- Perks & Flaws (Phase 2b): Quick/Sluggish/Timeline Sovereign/Temporal Drag adjust
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

function StatusService.GetAllRtMultiplier(unit)
	for _, inst in ipairs(unit.statusInstances) do
		if inst.id == "Frozen" then
			return 2.0
		end
	end
	return 1.0
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
			mult = mult * (isMechanical and 1.50 or 1.25)
		end
		-- Data-driven movement RT buffs (e.g. Coordinated Advance x0.80, 2026-10-07).
		local mdef = GameConstants.STATUSES[inst.id]
		if mdef and mdef.moveRtMult then
			mult = mult * mdef.moveRtMult
		end
	end
	return mult
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

	local expired = {}
	local events = {}   -- { { kind="Heal"|"Mana", statusId, amount }, ... }
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
					local before = unit.currentHp or 0
					unit.currentHp = math.min(unit.maxHp or before, before + heal)
					local applied = unit.currentHp - before
					if applied > 0 then
						table.insert(events, { kind = "Heal", statusId = inst.id, amount = applied })
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

		if inst.remainingCt then
			inst.remainingCt = inst.remainingCt - ctElapsed
			if inst.remainingCt <= 0 then
				-- Shield expiry: a shield that runs out its duration simply vanishes
				-- (no Retribution — that only triggers on a BREAK, per the recipe).
				-- Drop its remaining capacity from the aggregate pool.
				if inst.shieldHp then
					unit.shield_total = math.max(0, (unit.shield_total or 0) - inst.shieldHp)
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
			for stat in pairs(mods) do mods[stat] = mods[stat] - 0.10 end
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
					mods[stat] = mods[stat] + pct
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
			offset = offset + def.moveOffset
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
			if isSpell and def.spellDamageMult then
				mult = mult * def.spellDamageMult
			elseif (not isSpell) and def.physDamageMult then
				mult = mult * def.physDamageMult
			end
			if def.attackMult then
				mult = mult * def.attackMult
			end
		end
	end
	return mult
end

-- Incoming-defense multiplier from status buffs (Slice 5): Rune Ward +10%
-- Defense. Read where effective defense is computed in CombatResolver.
function StatusService.GetDefenseMultiplier(unit)
	local mult = 1.0
	for _, inst in ipairs(unit.statusInstances) do
		local def = GameConstants.STATUSES[inst.id]
		if def and def.defenseMult then
			mult = mult * def.defenseMult
		end
	end
	return mult
end

-- Stability offset from statuses (Hold the Line +2, War Cry +1; 2026-10-07).
-- Read wherever push distance uses target Stability (DisplacementService + Main
-- push preview) so both stay identical. Push Distance = max(0, Force - Stability).
function StatusService.GetStabilityModifier(unit)
	local offset = 0
	for _, inst in ipairs(unit.statusInstances or {}) do
		local def = GameConstants.STATUSES[inst.id]
		if def and def.stabilityOffset then
			offset = offset + def.stabilityOffset
		end
	end
	return offset
end

-- Final DIRECT damage received multiplier from statuses (Hold the Line x0.85).
-- Applied by CombatResolver to basic attacks and skill hits only (not DoT ticks).
function StatusService.GetDamageReceivedMultiplier(unit)
	local mult = 1.0
	for _, inst in ipairs(unit.statusInstances or {}) do
		local def = GameConstants.STATUSES[inst.id]
		if def and def.damageTakenMult then
			mult = mult * def.damageTakenMult
		end
	end
	return mult
end

function StatusService.GetCrippledReduction(unit, currentRange, currentJump)
	for _, inst in ipairs(unit.statusInstances) do
		if inst.id == "Crippled" then
			-- Move Range reduced by max(2, 50% current), min final 1
			local moveReduction = math.max(2, math.floor(currentRange * 0.50))
			local finalMove = math.max(1, currentRange - moveReduction)
			-- Jump reduced by max(1, 50% current), min final 0
			local jumpReduction = math.max(1, math.floor(currentJump * 0.50))
			local finalJump = math.max(0, currentJump - jumpReduction)
			return finalMove, finalJump
		end
	end
	return currentRange, currentJump
end

--------------------------------------------------
-- GET STATUS SUMMARY (for broadcasting)
--------------------------------------------------

function StatusService.GetStatusSummary(unit)
	local summary = {}
	for _, inst in ipairs(unit.statusInstances) do
		local def = GameConstants.STATUSES[inst.id]
		-- Calculate expected next-tick damage
		local nextDamage = nil
		if def then
			if def.dotType == "Poison" then
				nextDamage = math.max(1, math.round(unit.maxHp * def.dotFraction))
			elseif def.dotType == "Burn" then
				local stored = inst.storedBurn or 0
				if stored > 0 and not isBurnDamageImmune(unit) then  -- Dragonscale: 0 next-tick
					nextDamage = math.max(1, math.round(stored))
				end
			elseif inst.id == "Venom" then
				local stacks = inst.stacks or 1
				nextDamage = math.max(1, math.round(unit.maxHp * 0.03 * stacks))
			elseif inst.id == "Bleed" then
				nextDamage = math.max(1, math.round(unit.maxHp * 0.05))
			elseif inst.id == "Raptured" then
				nextDamage = math.max(1, math.round(unit.maxHp * 0.02))
			elseif inst.id == "Wounded" then
				nextDamage = math.max(1, math.round(unit.maxHp * 0.15))
			end
		end
		table.insert(summary, {
			id             = inst.id,
			remainingTurns = inst.remainingTurns,
			storedBurn     = inst.storedBurn,
			nextDamage     = nextDamage,
			stacks         = inst.stacks,
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
		if def and def.dispellable then
			table.insert(removed, inst.id)
			print(string.format("[StatusService] %s PURGED from %s", inst.id, unit.name))
			table.remove(unit.statusInstances, i)
		else
			i = i + 1
		end
	end
	return removed
end

-- Remove ONE random active debuff (kind == "Debuff") from the unit. Used by the
-- Cleanse perk (TRAIT-P-132) on enemy KO. Returns the removed status id, or nil if
-- the unit has no debuffs. Does not touch buffs or special statuses.
function StatusService.RemoveRandomDebuff(unit)
	if not unit.statusInstances then return nil end
	local debuffIdx = {}
	for i, inst in ipairs(unit.statusInstances) do
		local def = GameConstants.STATUSES[inst.id]
		if def and def.kind == "Debuff" then
			table.insert(debuffIdx, i)
		end
	end
	if #debuffIdx == 0 then return nil end
	local pick = debuffIdx[math.random(1, #debuffIdx)]
	local removedId = unit.statusInstances[pick].id
	table.remove(unit.statusInstances, pick)
	print(string.format("[StatusService] %s CLEANSED from %s (random debuff)", removedId, unit.name))
	return removedId
end

--------------------------------------------------
-- ACTION BLOCKING (Phase 2)
--
-- Reads the `blocks` table from GameConstants.STATUSES.
-- Returns true + reason if any active status blocks this action type.
-- actionType: "Move", "Attack", "Skill", "Guard", "Wait", "Push"
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
			if actionType == "Attack" and def.blocks.BasicAttack then
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

		-- Apply Sleep Immunity (2 turns, undispellable)
		StatusService.ApplyStatus(unit, "Sleep Immunity", unit.id)
		print(string.format("[StatusService] Sleep Immunity applied to %s", unit.name))
	end

	return removed
end

return StatusService
