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
-- UNIT REMOVAL (2026-11-06)
-- A dismissed unit must leave this table too: post-battle recovery iterates every
-- record here, and the table is saved, so a leftover record kept "recovering" a unit
-- that was no longer on the roster (Studio-found 2026-11-06).
--------------------------------------------------

function PersistentStateService.RemoveUnit(playerId, unitId)
	PersistentStateService.InitPlayer(playerId)
	if unitStates[playerId][unitId] ~= nil then
		unitStates[playerId][unitId] = nil
		print(string.format("[PersistentState] Removed %s (left the roster)", tostring(unitId)))
	end
end

-- Defensive sweep: drop any record whose unit id is not in ownedSet ({ [unitId] = true }).
-- Cleans saves written before RemoveUnit existed. Returns the number removed.
function PersistentStateService.PruneToOwned(playerId, ownedSet)
	PersistentStateService.InitPlayer(playerId)
	if type(ownedSet) ~= "table" then return 0 end
	local stale = {}
	for unitId in pairs(unitStates[playerId]) do
		if not ownedSet[unitId] then table.insert(stale, unitId) end
	end
	for _, unitId in ipairs(stale) do
		unitStates[playerId][unitId] = nil
		warn(string.format("[PersistentState] Dropped stale record %s (not on the roster)", tostring(unitId)))
	end
	return #stale
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
	-- Slice 6 item 2 (2026-10-07): a KO'd unit (isKO flag or 0 HP) does NOT get
	-- the max-HP increase added to its current HP — it stays at 0 until KO is
	-- cleared (persistent_hp_mp_rules id 8 "KO units receive NO ... recovery").
	local isDown = state.isKO == true or (state.currentHp or 0) <= 0
	if newMaxHp > state.maxHp then
		if not isDown then
			state.currentHp = state.currentHp + (newMaxHp - state.maxHp)
		end
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

-- skip (optional, Dungeon build step 3): unitId -> true leaves that unit KO'd (dungeon party mid-run).
function PersistentStateService.ClearAllKO(playerId, skip)
	PersistentStateService.InitPlayer(playerId)
	for unitId, state in pairs(unitStates[playerId]) do
		if state.isKO and not (skip and skip(unitId)) then
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

-- recoveryOverrides (optional): { [unitId] = fraction } to use INSTEAD of the default
-- RECOVERY_FRACTION for that unit. Lets the caller apply per-unit trait modifiers
-- (Resilient adds / Slow to Recover replaces) computed from the live units, which hold
-- the trait ids this persistent-state layer does not. Units absent from the table use the
-- default fraction. (Perks & Flaws 2026-10-23.)
-- skip (optional, Dungeon build step 3): unitId -> true gets no recovery (dungeon party mid-run,
-- project_rules 266) and is left out of the results.
function PersistentStateService.ApplyPostBattleRecovery(playerId, recoveryOverrides, skip)
	PersistentStateService.InitPlayer(playerId)
	local results = {}
	recoveryOverrides = recoveryOverrides or {}

	for unitId, state in pairs(unitStates[playerId]) do
		if skip and skip(unitId) then continue end
		-- KO'd units receive NO recovery (rule 8, BUG-071 2026-11-01). The caller runs this
		-- BEFORE ClearAllKO, so isKO is still set here; they get a 0 result for the summary.
		if state.isKO then
			results[unitId] = { hpRecovered = 0, mpRecovered = 0, wasKO = true }
			print(string.format("[PersistentState] %s KO'd -- no post-battle recovery", unitId))
		else
			local frac = recoveryOverrides[unitId] or RECOVERY_FRACTION
			local hpRecovery = math.ceil(state.maxHp * frac)
			-- Resilient / Slow to Recover are HP-only in the DB; MP always uses the baseline (2026-10-29).
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

	local mpRegen = unit.derivedStats and unit.derivedStats.mpRegen
		or PersistentStateService.CalcMpRegen(unit.effectiveStats and unit.effectiveStats.INT or 10)

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
