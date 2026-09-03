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

local StatusService = {}

--------------------------------------------------
-- CHANNEL DISRUPTOR CHECK
-- These statuses interrupt channeling when applied.
--------------------------------------------------

local CHANNEL_DISRUPTORS = {
	Silence = true,
	Stun    = true,
	Freeze  = true,
	Sleep   = true,
}

-- Hard CC: statuses that remove buffs with removedByCC (e.g. Guard).
-- Silence disrupts channeling but is NOT hard CC for Guard purposes.
local HARD_CC = {
	Stun   = true,
	Freeze = true,
	Sleep  = true,
}

function StatusService.IsChannelDisruptor(statusId)
	return CHANNEL_DISRUPTORS[statusId] == true
end

--------------------------------------------------
-- APPLY STATUS
--
-- Returns: applied (bool), disruptsChannel (bool)
-- Caller must check disruptsChannel and interrupt channeling if true.
--------------------------------------------------

function StatusService.ApplyStatus(unit, statusId, sourceUnitId, fireDamageDealt)
	local def = GameConstants.STATUSES[statusId]
	if not def then
		warn("[StatusService] Unknown status: " .. tostring(statusId))
		return false, false
	end

	local disruptsChannel = CHANNEL_DISRUPTORS[statusId] == true

	-- Check if unit already has this status.
	for _, inst in ipairs(unit.statusInstances) do
		if inst.id == statusId then
			if def.reapply == "refresh" then
				inst.remainingTurns = def.duration
				inst.sourceUnitId   = sourceUnitId
				print(string.format(
					"[StatusService] %s on %s REFRESHED (%d turns)",
					statusId, unit.name, def.duration
				))
				return false, disruptsChannel
			elseif def.reapply == "accumulate" then
				local addedBurn = 0
				if statusId == "Burn" and fireDamageDealt then
					addedBurn = math.round(fireDamageDealt * def.burnFraction)
				end
				inst.storedBurn = (inst.storedBurn or 0) + addedBurn
				-- "Extends duration" = refresh to full duration (not additive)
				inst.remainingTurns = def.duration
				inst.sourceUnitId = sourceUnitId
				print(string.format(
					"[StatusService] %s on %s ACCUMULATED (+%d stored, %d turns now)",
					statusId, unit.name, addedBurn, inst.remainingTurns
				))
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
	}

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

return StatusService
