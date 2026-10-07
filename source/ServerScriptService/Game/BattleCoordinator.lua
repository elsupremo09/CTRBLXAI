-- BattleCoordinator.lua
-- CTRBLXAI | Slice 3
--
-- Owns the battle lifecycle: the CT clock, which unit acts next,
-- opening and closing turns, and deciding when the battle is over.
--
-- Slice 3 additions:
--   - Channeling system: units can enter "Channeling" state.
--     When their CT comes up again, they activate the stored skill
--     instead of getting a normal turn.
--   - Channel interruption: if a disabling status (Silence, Stun, etc.)
--     is applied while channeling, channeling is cancelled.
--   - Damage does NOT interrupt channeling.
--   - MP is checked at commit (must have enough) but only SPENT at activation.
--   - If MP is insufficient at activation, skill fizzles.

local UnitSchema = require(script.Parent.UnitSchema)
local StatusService = require(script.Parent.StatusService)
local RacePassiveService = require(script.Parent.RacePassiveService)
local DoctrinePassiveService = require(script.Parent.DoctrinePassiveService)
local ArmorPassiveService = require(script.Parent.ArmorPassiveService)

local GameConstants = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

local BattleCoordinator = {}

-- Optional: TileEffectService injected at runtime to avoid circular requires
local _tileEffectService = nil
function BattleCoordinator.SetTileEffectService(tes)
	_tileEffectService = tes
end

-- Weather engine (injected to avoid a require cycle; BattleCoordinator is required
-- widely). Drives the per-round re-roll + 300-CT periodic tick off the clock.
local _weatherService = nil
function BattleCoordinator.SetWeatherService(ws)
	_weatherService = ws
end

local _battlefieldEventService = nil
function BattleCoordinator.SetBattlefieldEventService(bes)
	_battlefieldEventService = bes
end
--------------------------------------------------
-- CONSTANTS
--------------------------------------------------

local AP_PER_TURN_STANDARD = GameConstants.AP_PER_TURN_STANDARD
local REST_RT_MULTIPLIER   = GameConstants.REST_RT_MULTIPLIER

--------------------------------------------------
-- CHANNELING INTERRUPTION STATUSES
-- Any of these, when applied to a channeling unit, cancels channeling.
--------------------------------------------------

local CHANNEL_DISRUPTORS = {
	Silence = true,
	Stun    = true,
	Freeze  = true,
	Sleep   = true,
	-- Add future disabling statuses here
}

function BattleCoordinator.IsChannelDisruptor(statusId)
	return CHANNEL_DISRUPTORS[statusId] == true
end

--------------------------------------------------
-- BATTLE STATE
--------------------------------------------------

-- Time-of-day cycle: one phase per 1000-CT round, in order. phase index =
-- floor(ct / 1000) % 4. Battle starts at Dawn (ct 0).
local TIME_PHASES = { "Dawn", "Day", "Dusk", "Night" }
local function timePhaseForCt(ct)
	local idx = math.floor((ct or 0) / 1000) % 4
	return TIME_PHASES[idx + 1]
end

-- Recompute state.timePhase from the clock; on a change, inform RacePassiveService
-- and flag day/night-dependent units (Vampire/Werewolf) for a stat resync so their
-- +/- bonuses flip at the boundary. Returns true if the phase changed.
local function updateTimePhase(state)
	local newPhase = timePhaseForCt(state.ct)
	if newPhase == state.timePhase then return false end
	state.timePhase = newPhase
	RacePassiveService.SetTimePhase(newPhase)
	-- Resync affected living units now (RefreshConditionalStats rebuilds only on
	-- an actual bonus-state flip, so non-affected races are cheap no-ops).
	for _, u in ipairs(state.units) do
		if u.isAlive and RacePassiveService.RefreshConditionalStats(u) then
			state.ctStatusUnits = state.ctStatusUnits or {}
			table.insert(state.ctStatusUnits, u)
		end
	end
	print(string.format("[BattleCoordinator] Time phase -> %s (ct=%d)", newPhase, state.ct))
	-- BattleCoordinator has no broadcaster handle (BattleVisualBroadcaster is a nil
	-- global here — calling it directly crashed the turn loop). Stash the new phase
	-- on state; the driver (Main) broadcasts it after AdvanceClock, same pattern as
	-- ctStatusUnits.
	state.pendingTimePhase = newPhase
	return true
end

function BattleCoordinator.CreateBattleState(units)
	assert(
		type(units) == "table" and #units >= 2,
		"CreateBattleState: need at least 2 units."
	)

	for index, unit in ipairs(units) do
		unit.stableOrderKey = index
	end

	local state = {
		units           = units,
		activeUnit      = nil,
		turnRtAccrued   = 0,
		turnActionTaken = false,
		ct              = 0,
		phase           = "Waiting",
		winner          = nil,
		turnCount       = 0,
		timePhase       = "Dawn",   -- time cycle: Dawn->Day->Dusk->Night, one per 1000 CT
	}

	return state
end

--------------------------------------------------
-- CHANNELING STATE ON UNIT
--
-- Unit fields added when channeling:
--   unit.isChanneling    = true/false
--   unit.channelingData  = {
--       skillDef   = <skill definition>,
--       target     = <target unit reference>,
--       mpCost     = <MP to spend on activation>,
--       casterId   = <caster id (always self)>,
--   }
--
-- Set by CommandService when a channeled skill is committed.
-- Cleared by:
--   1. Activation (skill fires or fizzles)
--   2. Interrupt (disabling status applied)
--   3. Death
--------------------------------------------------

function BattleCoordinator.StartChanneling(state, unit, channelingData)
	unit.isChanneling   = true
	unit.channelingData = channelingData
	-- TWO-TIMER MODEL: the channel is an INDEPENDENT countdown from the caster's RT.
	-- channelRt   = duration of the channel (for display / remaining calc)
	-- channelResolveCt = absolute global-CT deadline, FIXED at commit. Haste/Slow/RT
	--   manipulation on the caster must NOT move this (it only affects unit.remainingRt).
	-- The caster's remainingRt is set by the NORMAL EndTurn (base + skill RT cost) in
	-- CommandService — NOT here — so the caster keeps a real, independent RT.
	local channelRt     = channelingData and channelingData.channelRt or 0
	-- ACTIVATION TIME (2026-10-07, frameworks 10/37 + skill_resolution_pipeline 4):
	-- after the channel completes, ONE activation event is scheduled at
	-- +activationCt. Phase "Channel" is interruptible; phase "Activation" is not.
	-- A zero-channel skill with activation > 0 starts directly in "Activation".
	local activationCt  = channelingData and channelingData.activationCt or 0
	if channelRt <= 0 and activationCt > 0 then
		unit.channelPhase        = "Activation"
		unit.pendingActivationCt = 0
		channelRt                = activationCt
	else
		unit.channelPhase        = "Channel"
		unit.pendingActivationCt = activationCt
	end
	unit.channelRt      = channelRt
	unit.channelResolveCt = (state and state.ct or 0) + channelRt
	print(string.format(
		"[BattleCoordinator] %s begins CHANNELING [%s] (target: %s)",
		unit.name,
		channelingData.skillDef.name or channelingData.skillDef.id,
		channelingData.target and channelingData.target.name or "self"
	))
end

function BattleCoordinator.InterruptChanneling(unit, reason)
	if not unit.isChanneling then return false end
	-- Activation Time cannot be interrupted once scheduled (frameworks 10/37).
	-- Only the caster's death still cancels it.
	if unit.channelPhase == "Activation" and reason ~= "death" then
		print(string.format(
			"[BattleCoordinator] %s activation NOT interrupted (%s) — activation time is uninterruptible",
			unit.name, reason or "unknown"))
		return false
	end
	local skillName = unit.channelingData and unit.channelingData.skillDef
		and (unit.channelingData.skillDef.name or unit.channelingData.skillDef.id)
		or "unknown"
	unit.isChanneling   = false
	unit.channelingData = nil
	unit.channelRt      = nil
	unit.channelResolveCt = nil
	unit.channelPhase   = nil
	unit.pendingActivationCt = nil
	print(string.format(
		"[BattleCoordinator] %s channeling INTERRUPTED [%s] — %s (MP not spent)",
		unit.name, skillName, reason or "unknown"
	))
	return true
end

-- Called by the main loop at a channel deadline BEFORE firing the skill. If the
-- skill still owes Activation Time, switch to the uninterruptible Activation phase
-- (deadline = now + activation), return the clock to Waiting and return true
-- (nothing fires yet). Returns false when the skill should fire now.
function BattleCoordinator.BeginActivationPhase(state, unit)
	if not (unit and unit.isChanneling and unit.channelPhase == "Channel") then return false end
	local act = unit.pendingActivationCt or 0
	if act <= 0 then return false end
	unit.channelPhase        = "Activation"
	unit.pendingActivationCt = 0
	unit.channelRt           = act
	unit.channelResolveCt    = (state.ct or 0) + act
	if state.phase == "ChannelResolve" then
		state.phase = "Waiting"
		state.channelResolveUnit = nil
	end
	local sd = unit.channelingData and unit.channelingData.skillDef
	print(string.format(
		"[BattleCoordinator] CT:%d | %s channel complete [%s] -> ACTIVATION (%d CT, uninterruptible, lands at CT %d)",
		state.ct or 0, unit.name, sd and (sd.name or sd.id) or "?", act, unit.channelResolveCt))
	return true
end

function BattleCoordinator.IsChanneling(unit)
	return unit.isChanneling == true
end

--------------------------------------------------
-- INTERNAL: ALIVE UNIT LISTS
--------------------------------------------------

local function getAliveUnits(state)
	local alive = {}
	for _, unit in ipairs(state.units) do
		if unit.isAlive then
			table.insert(alive, unit)
		end
	end
	return alive
end

local function getSideAlive(state, side)
	local count = 0
	for _, unit in ipairs(state.units) do
		-- Count alive units + KO'd Zombies that haven't used their revive
		local canRevive = (not unit.isAlive) and unit.raceId == "RACE-ZOMBIE"
			and not unit.zombieReviveUsed
		if unit.side == side and (unit.isAlive or canRevive) then
			count = count + 1
		end
	end
	return count
end

--------------------------------------------------
-- INTERNAL: NEXT READY UNIT
--------------------------------------------------

local function resolveReadyTie(a, b)
	local aLevel = a.level or 1
	local bLevel = b.level or 1
	if aLevel ~= bLevel then return aLevel > bLevel end

	local aAgi = a.effectiveStats and a.effectiveStats.AGI or 10
	local bAgi = b.effectiveStats and b.effectiveStats.AGI or 10
	if aAgi ~= bAgi then return aAgi > bAgi end

	local aHpPct = a.currentHp / a.maxHp
	local bHpPct = b.currentHp / b.maxHp
	if aHpPct ~= bHpPct then return aHpPct < bHpPct end

	local aLuk = a.effectiveStats and a.effectiveStats.LUK or 10
	local bLuk = b.effectiveStats and b.effectiveStats.LUK or 10
	if aLuk ~= bLuk then return aLuk > bLuk end

	return a.stableOrderKey < b.stableOrderKey
end

-- TWO-TIMER MODEL: the clock advances to the NEAREST of two kinds of events:
--   (1) a unit's RT reaching 0 (its turn), and
--   (2) a channeling unit's channelResolveCt (its skill fires) — an absolute
--       global-CT deadline independent of that unit's RT.
-- A caster whose RT has already hit <=0 while its channel is still pending is
-- FROZEN: skipped for turn selection until its channel resolves/disrupts, then it
-- becomes immediately ready. Returns either a ready unit, or a channel-resolution
-- signal { channelResolve = <unit> } when a channel deadline is the nearest event.
local function advanceToNextReady(state)
	local alive = getAliveUnits(state)
	if #alive == 0 then return nil, 0 end

	-- Find the nearest event: min over (unit RT) and (channel remaining = resolveCt - ct).
	local minRt = math.huge
	for _, unit in ipairs(alive) do
		-- A frozen caster (RT<=0, still channeling) does NOT contribute an RT event.
		local frozen = unit.isChanneling and unit.remainingRt <= 0
		if not frozen and unit.remainingRt < minRt then
			minRt = unit.remainingRt
		end
		if unit.isChanneling and unit.channelResolveCt then
			local chRemain = unit.channelResolveCt - state.ct
			if chRemain < minRt then minRt = chRemain end
		end
	end
	if minRt == math.huge then return nil, 0 end
	if minRt < 0 then minRt = 0 end

	state.ct = state.ct + minRt
	for _, unit in ipairs(alive) do
		-- Frozen casters do not tick RT (they wait at 0 for the channel).
		local frozen = unit.isChanneling and unit.remainingRt <= 0
		if not frozen then
			unit.remainingRt = unit.remainingRt - minRt
		end
	end

	-- Time cycle: advance Dawn/Day/Dusk/Night as the clock crosses 1000-CT rounds.
	updateTimePhase(state)

	-- Weather engine: per-round re-roll at each 1000-CT boundary + 300-CT periodic
	-- tick. Deterministic rng seeded from the clock (no stored seed needed).
	if _weatherService then
		local wRng = Random.new(state.ct + 54321)
		_weatherService.RerollForNewRound(state, wRng, state.ct)
		_weatherService.Tick(state, minRt, wRng, state.ct)
	end

	-- Battlefield events: evaluate conditional/round-gated spawns once per 1000-CT
	-- round boundary (separate from the weather slot; events layer on top).
	if _battlefieldEventService then
		local roundIndex = math.floor((state.ct or 0) / 1000)
		if state.bfRound == nil or roundIndex > state.bfRound then
			state.bfRound = roundIndex
			local bfRng = Random.new((state.ct or 0) + 70007)
			local ok, err = pcall(_battlefieldEventService.OnRoundStart, state, roundIndex, bfRng)
			if not ok then
				warn("[BattleCoordinator] BattlefieldEventService.OnRoundStart error: " .. tostring(err))
			end
		end
	end

	-- Channel resolution takes priority at its deadline: if any channeling unit's
	-- resolveCt is now reached, fire that channel first (skill resolves independent
	-- of whose RT is up). Pick the earliest-deadline channel if several coincide.
	local resolveUnit = nil
	for _, unit in ipairs(alive) do
		if unit.isChanneling and unit.channelResolveCt and state.ct >= unit.channelResolveCt then
			if not resolveUnit or unit.channelResolveCt < resolveUnit.channelResolveCt then
				resolveUnit = unit
			end
		end
	end
	if resolveUnit then
		return { channelResolve = resolveUnit }, minRt
	end

	-- Otherwise pick a ready unit by RT. Frozen casters (RT<=0 mid-channel) are
	-- excluded — they cannot take a turn until their channel resolves.
	local ready = {}
	for _, unit in ipairs(alive) do
		local frozen = unit.isChanneling and unit.remainingRt <= 0
		if unit.remainingRt <= 0 and not frozen then
			table.insert(ready, unit)
		end
	end

	if #ready == 0 then return nil, minRt end

	table.sort(ready, resolveReadyTie)
	return ready[1], minRt
end

--------------------------------------------------
-- CHECK BATTLE END
--------------------------------------------------

local function checkBattleEnd(state)
	local playersAlive = getSideAlive(state, "Player")
	local enemiesAlive = getSideAlive(state, "Enemy")

	if playersAlive == 0 then
		state.phase  = "BattleOver"
		state.winner = "Enemy"
		return true
	end

	if enemiesAlive == 0 then
		state.phase  = "BattleOver"
		state.winner = "Player"
		return true
	end

	return false
end

--------------------------------------------------
-- PUBLIC API
--------------------------------------------------

function BattleCoordinator.AdvanceClock(state)
	assert(
		state.phase == "Waiting",
		"AdvanceClock: phase must be Waiting, got " .. state.phase
	)

	if checkBattleEnd(state) then
		return nil
	end

	local nextUnit, ctPassed = advanceToNextReady(state)
	if not nextUnit then
		return nil
	end

	-- MP Regen: all alive units regenerate based on CT elapsed
	-- MP Regen = 2 + floor(INT/40) per 1000 CT. Accumulator-based.
	if ctPassed > 0 then
		for _, unit in ipairs(state.units) do
			if unit.isAlive and unit.currentMp < unit.maxMp then
				local mpRegen = unit.derivedStats and unit.derivedStats.mpRegen
					or (2 + math.floor((unit.effectiveStats and unit.effectiveStats.INT or 10) / 40))
				if not unit.mpRegenAccumulator then unit.mpRegenAccumulator = 0 end
				unit.mpRegenAccumulator = unit.mpRegenAccumulator + (ctPassed * mpRegen / 1000)
				if unit.mpRegenAccumulator >= 1 then
					local restored = math.floor(unit.mpRegenAccumulator)
					unit.mpRegenAccumulator = unit.mpRegenAccumulator - restored
					unit.currentMp = math.min(unit.maxMp, unit.currentMp + restored)
				end
			end
		end
	end

	-- CT-based status tick: decrement durationCt for ALL alive units
	if ctPassed > 0 then
		-- Collect units that received Regeneration/Recharge periodic effects so the
		-- driver (Main) can refresh their client bars. BattleCoordinator has no
		-- broadcaster handle, so we stash on state — same pattern as state.dotEvents.
		state.ctStatusUnits = {}
		for _, unit in ipairs(state.units) do
			if unit.isAlive then
				-- ProcessCtTick also applies Regeneration (HoT) and Recharge (MoT)
				-- periodic effects, mutating currentHp/currentMp and returning the
				-- events so we can refresh the client's bars.
				local _expired, ctEvents = StatusService.ProcessCtTick(unit, ctPassed)
				if ctEvents and #ctEvents > 0 then
					for _, ev in ipairs(ctEvents) do
						print(string.format("[StatusService] %s %s +%d on %s",
							ev.statusId, ev.kind, ev.amount, unit.name))
					end
					table.insert(state.ctStatusUnits, unit)
				end
			end
		end
	end

	-- Zombie revive: accumulate CT for KO'd Zombies
	if ctPassed > 0 then
		-- BattleCoordinator has no broadcaster handle, so revived Zombies are
		-- stashed on state.ctStatusUnits and the driver (Main) refreshes their
		-- client state — same pattern as the Regeneration/Recharge tick above.
		-- (Was calling BattleVisualBroadcaster.UnitStateChanged directly, which
		-- is a nil global here and would error when a Zombie actually revived.)
		state.ctStatusUnits = state.ctStatusUnits or {}
		for _, unit in ipairs(state.units) do
			if not unit.isAlive then
				if RacePassiveService.ProcessZombieRevive(unit, ctPassed) then
					table.insert(state.ctStatusUnits, unit)
				end
			end
		end
	end

	-- Tile effect CT tick: decay durations, fire periodic damage
	if ctPassed > 0 and _tileEffectService then
		_tileEffectService.ProcessCtTick(ctPassed, state.units)
		-- Burning spread: secondary post-tick propagation (TRG-012 cadence guard
		-- lives inside ProcessSpread). Runs after ProcessCtTick per element Step 5.
		if _tileEffectService.ProcessSpread then
			_tileEffectService.ProcessSpread(ctPassed)
		end
	end

	-- TWO-TIMER MODEL: channel-resolution signal. The clock reached a channeling
	-- unit's fixed deadline. Fire the skill OUTSIDE the normal turn flow (it resolves
	-- regardless of whose RT is up). Enter a dedicated phase; the main loop calls
	-- ResolveChannelDeadline. The caster takes its turn immediately ONLY if its own
	-- RT has already hit 0 (frozen) — handled after resolution.
	if type(nextUnit) == "table" and nextUnit.channelResolve then
		state.phase = "ChannelResolve"
		state.channelResolveUnit = nextUnit.channelResolve
		return nextUnit  -- signal table; main loop detects .channelResolve
	end

	state.activeUnit      = nextUnit
	state.phase           = "TurnOpen"
	state.turnRtAccrued   = 0
	state.turnActionTaken = false

	-- Reset once-per-turn Guard limit (Guard status expires via StatusService tick)
	nextUnit.guardUsedThisTurn = false
	-- Reset once-per-turn Momentum AP gain (Perks & Flaws Phase 3, TRAIT-P-162).
	nextUnit.momentumUsedThisTurn = false
	nextUnit.pendingKoApGain = 0
	-- Reset per-turn on-KO recovery accumulators (Bloodbath/Soul Charge 45% cap).
	nextUnit.koHpThisTurn = 0
	nextUnit.koMpThisTurn = 0

	-- Process DoT at start of turn (Poison/Burn damage)
	local dotEvents = StatusService.ProcessStartOfTurn(nextUnit)
	state.dotEvents = dotEvents

	-- If unit is channeling, this is the ACTIVATION turn (not a normal turn).
	-- Main.server.lua will check unit.isChanneling and handle activation.
	-- We still give AP so EndTurn doesn't error, but the unit won't use it.
	UnitSchema.RefreshAp(nextUnit)
	nextUnit.currentAp = AP_PER_TURN_STANDARD

	-- Reset doctrine per-turn state (Slice 4H)
	DoctrinePassiveService.OnTurnStart(nextUnit)
	ArmorPassiveService.OnTurnStart(nextUnit)
	-- Race start-of-turn hooks (2026-10-02): Troll Regrowth, Dragonkin resync.
	RacePassiveService.OnTurnStart(nextUnit, state)

	print(string.format(
		"[BattleCoordinator] CT:%d | Turn %d | %s%s",
		state.ct,
		state.turnCount + 1,
		UnitSchema.Describe(nextUnit),
		nextUnit.isChanneling and " [CHANNELING ACTIVATION]" or ""
	))

	return nextUnit
end

-- TWO-TIMER MODEL: called by the main loop when AdvanceClock returned a
-- { channelResolve = unit } signal. The caller (Main.server) fires the skill via
-- CommandService.ActivateChanneledSkill BEFORE calling this. This function then
-- applies the resolve-timing rule:
--   * If the caster's own RT has already hit <=0 (it was frozen waiting), it takes
--     its turn IMMEDIATELY: we open its turn here and return it.
--   * Otherwise the caster keeps its remaining RT and re-enters normal rotation;
--     we return nil and go back to Waiting.
-- ActivateChanneledSkill has already cleared isChanneling/channelResolveCt.
function BattleCoordinator.ResolveChannelDeadline(state)
	assert(state.phase == "ChannelResolve", "ResolveChannelDeadline: wrong phase " .. tostring(state.phase))
	local unit = state.channelResolveUnit
	state.channelResolveUnit = nil

	if not unit or not unit.isAlive then
		state.phase = "Waiting"
		return nil
	end

	-- Immediate turn ONLY if the caster's own RT already reached 0 while frozen.
	if unit.remainingRt <= 0 then
		state.activeUnit      = unit
		state.phase           = "TurnOpen"
		state.turnRtAccrued   = 0
		state.turnActionTaken = false
		unit.guardUsedThisTurn = false
		-- Reset once-per-turn Momentum AP gain (Perks & Flaws Phase 3, TRAIT-P-162).
		unit.momentumUsedThisTurn = false
		unit.pendingKoApGain = 0
		-- Reset per-turn on-KO recovery accumulators (Bloodbath/Soul Charge 45% cap).
		unit.koHpThisTurn = 0
		unit.koMpThisTurn = 0
		local dotEvents = StatusService.ProcessStartOfTurn(unit)
		state.dotEvents = dotEvents
		UnitSchema.RefreshAp(unit)
		unit.currentAp = AP_PER_TURN_STANDARD
		DoctrinePassiveService.OnTurnStart(unit)
		ArmorPassiveService.OnTurnStart(unit)
		-- Race start-of-turn hooks (2026-10-02): Troll Regrowth, Dragonkin resync.
		RacePassiveService.OnTurnStart(unit, state)
		print(string.format(
			"[BattleCoordinator] CT:%d | Channel resolved -> %s takes immediate turn (was frozen at 0 RT)",
			state.ct, unit.name
		))
		return unit
	end

	-- Caster still has RT remaining: back to normal rotation, no immediate turn.
	state.phase = "Waiting"
	print(string.format(
		"[BattleCoordinator] CT:%d | Channel resolved -> %s keeps %d RT (normal rotation)",
		state.ct, unit.name, unit.remainingRt
	))
	return nil
end

function BattleCoordinator.AccrueRt(state, rtCost)
	assert(
		state.phase == "TurnOpen",
		"AccrueRt: no turn is open."
	)
	assert(rtCost >= 0, "AccrueRt: rtCost must be >= 0.")

	state.turnRtAccrued   = state.turnRtAccrued + rtCost
	state.turnActionTaken = true
end

-- EndTurn
-- Uses Modified Base RT from StatusService (accounts for Slow/Haste).
-- After computing RT, ticks all statuses (decrements turns, removes expired).
-- Returns: { expiredStatuses = { "Slow", ... } }
function BattleCoordinator.EndTurn(state)
	assert(
		state.phase == "TurnOpen",
		"EndTurn: no turn is open."
	)

	local unit = state.activeUnit

	local modifiedBaseRt = StatusService.GetModifiedBaseRt(unit)
	-- Frozen: all RT costs ×2
	local frozenMult = StatusService.GetAllRtMultiplier(unit)

	if not state.turnActionTaken then
		unit.remainingRt = math.round(modifiedBaseRt * REST_RT_MULTIPLIER * frozenMult)
	else
		unit.remainingRt = math.max(1, math.round((modifiedBaseRt + state.turnRtAccrued) * frozenMult))
	end

	-- Tick statuses: decrement durations, remove expired.
	local expired = StatusService.TickStatuses(unit)

	-- Race end-of-turn hooks (2026-10-02): Insectoid Molt Cycle, Dragonkin resync.
	RacePassiveService.OnTurnEnd(unit, state)

	print(string.format(
		"[BattleCoordinator] Turn ended | %s | Next RT: %d | ModBaseRT: %d",
		unit.name,
		unit.remainingRt,
		modifiedBaseRt
	))

	state.turnCount     = state.turnCount + 1
	state.activeUnit    = nil
	state.turnRtAccrued = 0
	state.phase         = "Waiting"

	checkBattleEnd(state)

	return { expiredStatuses = expired }
end

-- EndTurnChanneling
-- Special EndTurn for when a unit commits a channeled skill.
-- The unit's RT is set to channelRt (the time to wait before activation).
-- No status tick happens (that happens on the activation turn).
function BattleCoordinator.EndTurnChanneling(state, channelRt)
	assert(
		state.phase == "TurnOpen",
		"EndTurnChanneling: no turn is open."
	)

	local unit = state.activeUnit
	unit.remainingRt = math.max(1, channelRt)

	print(string.format(
		"[BattleCoordinator] Channeling turn ended | %s | Channel RT: %d",
		unit.name, unit.remainingRt
	))

	-- Tick statuses even during channeling (so Slow/Poison timers still count down)
	local expired = StatusService.TickStatuses(unit)

	-- Race end-of-turn hooks (2026-10-02): Insectoid Molt Cycle, Dragonkin resync.
	RacePassiveService.OnTurnEnd(unit, state)

	state.turnCount     = state.turnCount + 1
	state.activeUnit    = nil
	state.turnRtAccrued = 0
	state.phase         = "Waiting"

	checkBattleEnd(state)

	return { expiredStatuses = expired }
end

function BattleCoordinator.GetPhase(state)
	return state.phase
end

function BattleCoordinator.GetWinner(state)
	return state.winner
end

return BattleCoordinator
