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

local StatusService = {}

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
	local raceEntry = RaceData[unit.raceId]
	if raceEntry and raceEntry.tags then
		return raceEntry.tags
	end
	return {}
end

function StatusService.IsImmune(unit, statusId)
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

function StatusService.ApplyStatus(unit, statusId, sourceUnitId, fireDamageDealt)
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

	-- Check if unit already has this status.
	for _, inst in ipairs(unit.statusInstances) do
		if inst.id == statusId then
			if def.reapply == "refresh" then
				inst.remainingTurns = def.duration
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
		instance.remainingCt = def.durationCt
	end

	if statusId == "Burn" and fireDamageDealt then
		instance.storedBurn = math.round(fireDamageDealt * def.burnFraction)
	elseif statusId == "Burn" then
		instance.storedBurn = 0
	end

	table.insert(unit.statusInstances, instance)

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
		"[StatusService] %s APPLIED to %s (%d turns)%s%s",
		statusId, unit.name, def.duration,
		instance.storedBurn and (" | stored:" .. instance.storedBurn) or "",
		disruptsChannel and " [CHANNEL DISRUPTOR]" or ""
	))
	return true, disruptsChannel
end

--------------------------------------------------
-- PROCESS START OF TURN (DoT damage)
--
-- Called at the START of the active unit's turn.
-- Returns a list of DoT events: { { statusId, damage, sourceUnitId }, ... }
--------------------------------------------------

function StatusService.ProcessStartOfTurn(unit)
	local dotEvents = {}
	-- Debuff Resistance: VIT reduces incoming DoT damage
	-- Rule: Debuff Resistance Multiplier = 1 - VIT / (300 + VIT)
	local debuffResist = unit.derivedStats and unit.derivedStats.debuffResist
		or (1 - (unit.effectiveStats and unit.effectiveStats.VIT or 10) / (300 + (unit.effectiveStats and unit.effectiveStats.VIT or 10)))

	for _, inst in ipairs(unit.statusInstances) do
		local def = GameConstants.STATUSES[inst.id]
		if not def or not def.dotType then
			-- skip
		elseif def.dotType == "Poison" then
			local damage = math.max(1, math.round(unit.maxHp * def.dotFraction * debuffResist))
			table.insert(dotEvents, {
				statusId     = "Poison",
				damage       = damage,
				sourceUnitId = inst.sourceUnitId,
			})
		elseif def.dotType == "Burn" then
			local storedBurn = inst.storedBurn or 0
			if storedBurn > 0 then
				local damage = math.max(1, math.round(storedBurn * debuffResist))
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
	local baseRt = GameConstants.BASE_RT_STANDARD
	local multiplier = 1.0

	for _, inst in ipairs(unit.statusInstances) do
		local def = GameConstants.STATUSES[inst.id]
		if def and def.rtMultiplier then
			multiplier = multiplier * def.rtMultiplier
		end
	end

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
	local i = 1
	while i <= #unit.statusInstances do
		local inst = unit.statusInstances[i]
		if inst.remainingCt then
			inst.remainingCt = inst.remainingCt - ctElapsed
			if inst.remainingCt <= 0 then
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
	return expired
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
	end
	return offset
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
				if stored > 0 then
					nextDamage = math.max(1, math.round(stored))
				end
			end
		end
		table.insert(summary, {
			id             = inst.id,
			remainingTurns = inst.remainingTurns,
			storedBurn     = inst.storedBurn,
			nextDamage     = nextDamage,
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
