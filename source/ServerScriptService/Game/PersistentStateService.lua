-- PersistentStateService.lua
-- CTRBLXAI | Slice 4B — Persistent Unit Resources
--
-- Holds per-player unit state between battles (in-memory, no DataStore yet).
-- Tracks: Current HP, Current MP, KO status, MP Regen accumulator.
--
-- Rules from persistent_hp_mp_rules:
--   - Battle start loads Current HP/MP (does NOT refill)
--   - New units default to full once
--   - Survivors recover ceil(Max × 0.35) after qualifying victory
--   - KO units get NO recovery
--   - Recovery clamps to max
--   - Abandoned battles grant nothing
--
-- MP Regen (from core_stats):
--   MP Regen = 2 + floor(INT / 40) per 1000 CT
--   Accumulator += CT_passed × MP_Regen / 1000
--   When Accumulator >= 1: restore floor(Accumulator), retain fraction

local PersistentStateService = {}

--------------------------------------------------
-- STATE STORAGE
-- unitStates[playerId][unitId] = { currentHp, currentMp, maxHp, maxMp, isKO, mpRegenAccumulator }
--------------------------------------------------

local unitStates = {}

--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

local RECOVERY_FRACTION = 0.35

--------------------------------------------------
-- PLAYER LIFECYCLE
--------------------------------------------------

function PersistentStateService.InitPlayer(playerId)
	if not unitStates[playerId] then
		unitStates[playerId] = {}
	end
end

function PersistentStateService.GetPlayerState(playerId)
	return unitStates[playerId] or {}
end

--------------------------------------------------
-- UNIT REGISTRATION
-- Call when a unit is first created/recruited. Sets full resources.
--------------------------------------------------

function PersistentStateService.RegisterNewUnit(playerId, unitId, maxHp, maxMp)
	PersistentStateService.InitPlayer(playerId)
	unitStates[playerId][unitId] = {
		currentHp = maxHp,
		currentMp = maxMp,
		maxHp = maxHp,
		maxMp = maxMp,
		isKO = false,
		mpRegenAccumulator = 0,
	}
	print(string.format(
		"[PersistentState] Registered %s | HP:%d/%d MP:%d/%d",
		unitId, maxHp, maxHp, maxMp, maxMp
	))
end

--------------------------------------------------
-- GET UNIT STATE (for battle start)
--------------------------------------------------

function PersistentStateService.GetUnitState(playerId, unitId)
	PersistentStateService.InitPlayer(playerId)
	return unitStates[playerId][unitId]
end

--------------------------------------------------
-- UPDATE AFTER EQUIPMENT/STAT CHANGE
-- When max HP/MP changes, apply the rule:
--   Max increases: Current += NewMax - OldMax (preserves missing amount)
--   Max decreases: Current = min(Current, NewMax) (clamp)
--------------------------------------------------

function PersistentStateService.UpdateMaxResources(playerId, unitId, newMaxHp, newMaxMp)
	local state = PersistentStateService.GetUnitState(playerId, unitId)
	if not state then return end

	-- HP
	if newMaxHp > state.maxHp then
		state.currentHp = state.currentHp + (newMaxHp - state.maxHp)
	elseif newMaxHp < state.maxHp then
		state.currentHp = math.min(state.currentHp, newMaxHp)
	end
	state.maxHp = newMaxHp

	-- MP
	if newMaxMp > state.maxMp then
		state.currentMp = state.currentMp + (newMaxMp - state.maxMp)
	elseif newMaxMp < state.maxMp then
		state.currentMp = math.min(state.currentMp, newMaxMp)
	end
	state.maxMp = newMaxMp
end

--------------------------------------------------
-- BATTLE END: PERSIST FINAL STATE
-- Called for ALL owned units after battle ends (before recovery).
--------------------------------------------------

function PersistentStateService.PersistBattleEnd(playerId, unitId, finalHp, finalMp, maxHp, maxMp, isKO)
	PersistentStateService.InitPlayer(playerId)
	local state = unitStates[playerId][unitId]
	if not state then
		-- Unit wasn't registered yet (shouldn't happen normally)
		state = {}
		unitStates[playerId][unitId] = state
	end
	state.currentHp = finalHp
	state.currentMp = finalMp
	state.maxHp = maxHp
	state.maxMp = maxMp
	state.isKO = isKO
	state.mpRegenAccumulator = 0 -- reset between battles
end

--------------------------------------------------
-- CLEAR KO (called after every battle regardless of outcome)
-- Session rule: base not implemented, so KO clears here.
--------------------------------------------------

function PersistentStateService.ClearAllKO(playerId)
	PersistentStateService.InitPlayer(playerId)
	for unitId, state in pairs(unitStates[playerId]) do
		if state.isKO then
			state.currentHp = 1
			state.isKO = false
			print(string.format("[PersistentState] %s KO cleared -> 1 HP", unitId))
		end
	end
end

--------------------------------------------------
-- POST-BATTLE RECOVERY
-- Apply 35% recovery to ALL surviving owned units.
-- KO units receive NOTHING.
-- Only called after qualifying victories.
--
-- Returns: { [unitId] = { hpRecovered, mpRecovered, wasKO } }
--------------------------------------------------

function PersistentStateService.ApplyPostBattleRecovery(playerId)
	PersistentStateService.InitPlayer(playerId)
	local results = {}

	for unitId, state in pairs(unitStates[playerId]) do
		-- KO already cleared by ClearAllKO before this runs.
		-- Apply 35% recovery to all living units.
		do
			local hpRecovery = math.ceil(state.maxHp * RECOVERY_FRACTION)
			local mpRecovery = math.ceil(state.maxMp * RECOVERY_FRACTION)

			local prevHp = state.currentHp
			local prevMp = state.currentMp

			state.currentHp = math.min(state.maxHp, state.currentHp + hpRecovery)
			state.currentMp = math.min(state.maxMp, state.currentMp + mpRecovery)

			local actualHpRec = state.currentHp - prevHp
			local actualMpRec = state.currentMp - prevMp

			results[unitId] = { hpRecovered = actualHpRec, mpRecovered = actualMpRec }

			print(string.format(
				"[PersistentState] %s recovered HP:%d→%d (+%d) MP:%d→%d (+%d)",
				unitId, prevHp, state.currentHp, actualHpRec,
				prevMp, state.currentMp, actualMpRec
			))
		end
	end

	return results
end

--------------------------------------------------
-- MP REGEN (called during CT advancement)
--
-- mpRegen = 2 + floor(INT / 40)
-- accumulator += ctPassed × mpRegen / 1000
-- When accumulator >= 1: restore floor(accumulator) MP, retain fraction.
-- Current MP never exceeds Max MP.
-- Only runs while CT is advancing (not during menus/pauses).
--------------------------------------------------

function PersistentStateService.CalcMpRegen(totalInt)
	return 2 + math.floor(totalInt / 40)
end

function PersistentStateService.AdvanceMpRegen(unit, ctPassed)
	-- unit must have: effectiveStats.INT, currentMp, maxMp, mpRegenAccumulator
	if not unit.isAlive then return 0 end
	if ctPassed <= 0 then return 0 end

	local int = unit.effectiveStats and unit.effectiveStats.INT or 10
	local mpRegen = PersistentStateService.CalcMpRegen(int)

	-- Initialize accumulator if missing
	if not unit.mpRegenAccumulator then
		unit.mpRegenAccumulator = 0
	end

	unit.mpRegenAccumulator = unit.mpRegenAccumulator + (ctPassed * mpRegen / 1000)

	local restored = 0
	if unit.mpRegenAccumulator >= 1 then
		restored = math.floor(unit.mpRegenAccumulator)
		unit.mpRegenAccumulator = unit.mpRegenAccumulator - restored

		-- Clamp to max
		local prevMp = unit.currentMp
		unit.currentMp = math.min(unit.maxMp, unit.currentMp + restored)
		restored = unit.currentMp - prevMp
	end

	return restored
end

--------------------------------------------------
-- SERIALIZATION (for Slice 4C)
--------------------------------------------------

function PersistentStateService.ExportState(playerId)
	return unitStates[playerId] or {}
end

function PersistentStateService.ImportState(playerId, data)
	unitStates[playerId] = data or {}
end

--------------------------------------------------
-- DEBUG
--------------------------------------------------

function PersistentStateService.DescribeUnit(playerId, unitId)
	local state = PersistentStateService.GetUnitState(playerId, unitId)
	if not state then return "No state" end
	return string.format(
		"HP:%d/%d MP:%d/%d KO:%s Acc:%.2f",
		state.currentHp, state.maxHp,
		state.currentMp, state.maxMp,
		tostring(state.isKO),
		state.mpRegenAccumulator or 0
	)
end

return PersistentStateService
