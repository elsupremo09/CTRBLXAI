-- BattleVisualBroadcaster.lua
-- CTRBLXAI | Slice 3
--
-- Server-side broadcaster. Fires RemoteEvents for the client to render.
--
-- Slice 3 additions:
--   - DotDamage event (Poison/Burn tick at start of turn)
--   - HealingApplied event
--   - SkillCardData event (sends available skills to client)
--   - TargetHighlight event (sends valid target tiles for highlighting)
--   - serializeUnit includes MP and skillIds

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BattleEvents = require(
	ReplicatedStorage
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Remotes")
		:WaitForChild("BattleEvents")
)

local GameConstants = require(
	ReplicatedStorage
		:WaitForChild("CTRBLXAI")
		:WaitForChild("Shared")
		:WaitForChild("GameConstants")
)

local StatusService = require(
	game:GetService("ServerScriptService")
		:WaitForChild("Game")
		:WaitForChild("StatusService")
)

local DoctrineData = require(
	ReplicatedStorage
		:WaitForChild("Content")
		:WaitForChild("DoctrineData")
)

local RaceData = require(
	ReplicatedStorage
		:WaitForChild("Content")
		:WaitForChild("RaceData")
)

local BattleVisualBroadcaster = {}

--------------------------------------------------
-- BATTLE LOG (server-authored, 2026-10-08)
-- Single source of truth for the in-game battle log. Every line is built
-- here and fired as BattleLogEntry { t = turn#, c = category, x = text,
-- u = unitId }. The client only displays entries (NET-001, NET-003).
-- Categories: turn | action | rt | status | ko | channel | field | info
--------------------------------------------------

local _logTurn = 0

local function unitName(u)
	return (u and u.name) or "?"
end

local function fireLogRaw(category, text, unitId)
	if type(text) ~= "string" or text == "" then return end
	BattleEvents.BattleLogEntry:FireAllClients({ t = _logTurn, c = category, x = text, u = unitId })
end

--------------------------------------------------
-- BATTLE LOG COVERAGE (project_rules 225, 2026-10-28)
-- Cause labels + per-unit snapshot diff + batch grouping.
--   * CAUSE: callers name the cause by passing a trailing `cause` string, or by
--     scoping one with SetCause(label) ... ClearCause(prev). "__silent" = absorb the
--     change without logging (aura reconcile, passive MP regen).
--   * SNAPSHOT: _snap[unitId] = {hp, mp, alive, st = {[statusId]=true}} -- what the
--     log last described. UnitStateChanged logs only the diff. Every function that
--     already logs a change refreshes the matching snapshot fields (dedup).
--   * GROUPING: diff/object/terrain lines are buffered; on flush, >= GROUP_MIN lines
--     sharing cause+kind become one summary. Any direct log line flushes the buffer
--     first, so chronological order is preserved. Flush points: FlushLog() from
--     CommandService (end of command) and Main (end of CT-tick block), plus a
--     task.defer fallback. Logging never touches game state (read-only on units).
--------------------------------------------------

local SILENT = "__silent"
BattleVisualBroadcaster.SILENT = SILENT
local GROUP_MIN = 3  -- agent default threshold (vetoable)

local _scopedCause = nil   -- SetCause/ClearCause scope
local _snap = {}           -- [unitId] = snapshot
local _unitsById = {}      -- [unitId] = unit (registry for tile lookup)
local _buffer = {}         -- pending entries {kind, cause, unitId, name, amount, statusName, label, text, category}
local _deferScheduled = false

local function statusName(id)
	local def = GameConstants.STATUSES and GameConstants.STATUSES[id]
	return (def and def.name) or tostring(id)
end

local function statusSet(unit)
	local set = {}
	if unit and unit.statusInstances then
		for _, e in ipairs(StatusService.GetStatusSummary(unit)) do
			if e.id then set[e.id] = true end
		end
	end
	return set
end

local function seedUnit(unit)
	if not unit or unit.id == nil then return end
	_unitsById[unit.id] = unit
	_snap[unit.id] = {
		hp = unit.currentHp or 0,
		mp = unit.currentMp or 0,
		alive = unit.isAlive ~= false,
		st = statusSet(unit),
	}
end

local function rangeText(lo, hi)
	if lo == hi then return tostring(lo) end
	return `{lo}–{hi}`
end

-- Single-line text for one buffered entry.
local function entryText(e)
	if e.text then return e.text end
	local c, n = e.cause, e.name
	if e.kind == "hpLoss" then
		return if c then `{c} hit {n} for {e.amount}.` else `{n} lost {e.amount} HP.`
	elseif e.kind == "hpGain" then
		return if c then `{c} healed {n} for {e.amount}.` else `{n} recovered {e.amount} HP.`
	elseif e.kind == "ko" then
		return if c then `{n} was defeated ({c}).` else `{n} was defeated.`
	elseif e.kind == "revive" then
		return if c then `{n} was revived ({c}).` else `{n} was revived.`
	elseif e.kind == "statusAdd" then
		return if c then `{n} is now {e.statusName} ({c}).` else `{n} is now {e.statusName}.`
	elseif e.kind == "statusRem" then
		return if c then `{n} is no longer {e.statusName} ({c}).` else `{n} is no longer {e.statusName}.`
	elseif e.kind == "mpLoss" then
		return `{c}: {n} lost {e.amount} MP.`
	elseif e.kind == "mpGain" then
		return `{c}: {n} gained {e.amount} MP.`
	elseif e.kind == "tileEffect" then
		return `{c} spread to a tile.`
	elseif e.kind == "terrain" then
		return `{c}: a tile became {e.label}.`
	elseif e.kind == "objDestroyed" then
		return `{e.label} was destroyed.`
	elseif e.kind == "objExploded" then
		return `{e.label} exploded.`
	elseif e.kind == "objPushed" then
		return `{e.label} was pushed.`
	elseif e.kind == "objHit" then  -- F4 (2026-11-08, rule 225): an object took a hit and survived
		return if c then `{c} hit {e.label}.` else `{e.label} was hit.`
	end
	return nil
end

-- Summary text for k >= GROUP_MIN entries sharing cause+kind (+status/label).
local function groupText(list)
	local e = list[1]
	local c, k = e.cause, #list
	local lo, hi = math.huge, -math.huge
	for _, x in ipairs(list) do
		local a = x.amount or 0
		if a < lo then lo = a end
		if a > hi then hi = a end
	end
	if e.kind == "hpLoss" then return `{c} hit {k} units for {rangeText(lo, hi)}.`
	elseif e.kind == "hpGain" then return `{c} healed {k} units for {rangeText(lo, hi)}.`
	elseif e.kind == "statusAdd" then
		if e.statusName == "Wet" then return `{c} soaked {k} units.` end
		return `{c}: {k} units are now {e.statusName}.`
	elseif e.kind == "statusRem" then return `{c}: {k} units are no longer {e.statusName}.`
	elseif e.kind == "mpLoss" then return `{c}: {k} units lost {rangeText(lo, hi)} MP.`
	elseif e.kind == "mpGain" then return `{c}: {k} units gained {rangeText(lo, hi)} MP.`
	elseif e.kind == "tileEffect" then return `{c} spread to {k} tiles.`
	elseif e.kind == "terrain" then return `{c}: {k} tiles became {e.label}.`
	elseif e.kind == "objDestroyed" then return `{k}× {e.label} were destroyed.`
	elseif e.kind == "objExploded" then return `{k}× {e.label} exploded.`
	elseif e.kind == "objPushed" then return `{k}× {e.label} were pushed.`
	elseif e.kind == "objHit" then return `{c} hit {k}× {e.label}.`
	end
	return nil
end

local GROUPABLE = {
	hpLoss = true, hpGain = true, statusAdd = true, statusRem = true, mpLoss = true, mpGain = true,
	tileEffect = true, terrain = true, objDestroyed = true, objExploded = true, objPushed = true,
	objHit = true,
}

local function flushLog()
	_deferScheduled = false
	if #_buffer == 0 then return end
	local pending = _buffer
	_buffer = {}
	-- Bucket by cause+kind(+status/label); emit in order of first appearance.
	local buckets, order = {}, {}
	for i, e in ipairs(pending) do
		local key
		if e.cause and GROUPABLE[e.kind] then
			key = `{e.cause}|{e.kind}|{e.statusName or ""}|{e.label or ""}`
		else
			key = `#{i}`
		end
		if not buckets[key] then
			buckets[key] = {}
			table.insert(order, key)
		end
		table.insert(buckets[key], e)
	end
	for _, key in ipairs(order) do
		local list = buckets[key]
		if #list >= GROUP_MIN then
			fireLogRaw(list[1].category or "field", groupText(list), nil)
		else
			for _, e in ipairs(list) do
				if e.trace then warn(`[BattleLog] uncaused {e.kind} for {e.name}\n{e.trace}`) end
				fireLogRaw(e.category or "status", entryText(e), e.unitId)
				-- R7: a diff KO line counts as this KO's line (no second one from a hit / push).
				local _ks = if e.kind == "ko" and e.unitId ~= nil then _snap[e.unitId] else nil
				if _ks and _ks.alive == false then _ks.koLogged = true end
			end
		end
	end
end

local function bufferEntry(e)
	table.insert(_buffer, e)
	if not _deferScheduled then
		_deferScheduled = true
		task.defer(flushLog)  -- fallback so nothing is held forever
	end
end

-- Remove not-yet-flushed diff entries for a unit that a following logging
-- broadcast is about to describe itself (dedup when state sync came first).
-- amount (optional): only retract HP entries of exactly this size, so a DIFFERENT
-- earlier change (e.g. a recoil hit) is never swallowed.
local function retract(unitId, kinds, statusId, amount)
	if unitId == nil or #_buffer == 0 then return end
	for i = #_buffer, 1, -1 do
		local e = _buffer[i]
		if e.unitId == unitId and kinds[e.kind] and (statusId == nil or e.statusId == statusId)
			and (amount == nil or e.amount == nil or e.amount == amount) then
			table.remove(_buffer, i)
		end
	end
end

local HP_KINDS = { hpLoss = true, hpGain = true, ko = true, revive = true }

-- Causes whose MP change is a real effect (rules 225). Others: MP absorbed silently.
-- Callers can force it per call with UnitStateChanged(unit, cause, true).
local MP_CAUSES = {
	["Mana Storm"] = true, ["Tainted Ground"] = true, ["Magic Spring"] = true,
	["Campfire"] = true, ["Recharge"] = true, ["MP drain"] = true,
}
local _mpCauseOverride = false
function BattleVisualBroadcaster.RegisterMpCause(label)
	if type(label) == "string" then MP_CAUSES[label] = true end
end

-- Causes whose own heal line REPLACES the skill's heal line (2026-11-08, Studio bug 1). Vitality Surge
-- logs "Vitality Surge healed X for N." itself; the turn controller later reports the same caster HP
-- gain as "X heals X with <skill>". HealingApplied skips that second line when it matches the heal
-- this cause already logged (same unit, same amount, HP unchanged since). Same opt-in idea as MP_CAUSES.
local HEAL_CAUSES = {
	["Vitality Surge"] = true,
}
function BattleVisualBroadcaster.RegisterHealCause(label)
	if type(label) == "string" then HEAL_CAUSES[label] = true end
end

-- A cause that arrives right after an uncaused sync of the same unit (e.g. code that
-- calls UnitStateChanged(u) then ObjectDamage(..., "Spike Trap")) names the line that
-- is already buffered instead of adding a second one.
local function relabel(unitId, cause)
	if unitId == nil or type(cause) ~= "string" or cause == SILENT then return end
	for _, e in ipairs(_buffer) do
		if e.unitId == unitId and e.cause == nil and HP_KINDS[e.kind] then
			e.cause = cause
			e.trace = nil
		end
	end
end
local STATUS_ADD_KIND = { statusAdd = true }
local STATUS_REM_KIND = { statusRem = true }

-- Refresh snapshot fields after a broadcast that logged them itself.
local function syncHp(unit)
	if not unit or unit.id == nil then return end
	local s = _snap[unit.id]
	if not s then seedUnit(unit) return end
	retract(unit.id, HP_KINDS)
	if s.hp ~= (unit.currentHp or 0) then s.loggedGain = nil end  -- HEAL_CAUSES record is out of date
	s.hp = unit.currentHp or 0
	s.alive = unit.isAlive ~= false
	if s.alive then s.koLogged = nil end  -- R7: alive again, a later KO gets its own line
end

local function syncStatus(unit, statusId, present)
	if not unit or unit.id == nil or statusId == nil then return end
	local s = _snap[unit.id]
	if not s then seedUnit(unit) return end
	retract(unit.id, if present then STATUS_ADD_KIND else STATUS_REM_KIND, statusId)
	s.st[statusId] = if present then true else nil
end

local function logEntry(category, text, unitId)
	if type(text) ~= "string" or text == "" then return end
	flushLog()  -- keep chronological order with buffered lines
	fireLogRaw(category, text, unitId)
end

-- Rulings R7 (handoff 1, 2026-11-09, rule 256): ONE "is knocked out." line per KO. A push / collision KO
-- is HELD here (queueKo) instead of logged at once: the hit line of the same attack / skill logs it right
-- after itself (UnitActed -> logKo). FlushPendingKo() logs any KO that no hit line claimed (end of each
-- broadcast batch, next turn start, battle end). s.koLogged = this KO already has its line (cleared
-- when the unit is seen alive again).
local _pendingKo = {}       -- [unitId] = unit, KO line held back
local _pendingKoOrder = {}  -- unitIds in the order they went down
-- Job 1 (2026-11-09, rule 256 / ruling 140, attempt 2): push / collision visuals HELD while a hit command
-- resolves. BattleTurnController turns the hold on around Attack / Skill commits and channel releases.
-- UnitPushed then keeps its client event + log line here instead of sending them, and they are sent right
-- AFTER the hit that caused them (UnitActed), so the client never sees a push's HP drop / KO before that
-- hit. Unclaimed ones go at the end of the batch (FlushHeldPushes). A Push command (no hit) is never held.
-- tag = which AI action of the turn held it (nil = the commit running now).
local _holdPushes = false
local _heldPushes: { any } = {}  -- { targetId, payload, text, pusherId, tag }
local function logKo(unit)
	if not unit or unit.id == nil then return end
	_pendingKo[unit.id] = nil
	if not _snap[unit.id] then seedUnit(unit) end
	local s = _snap[unit.id]
	if s.koLogged then return end
	s.koLogged = true
	logEntry("ko", `{unitName(unit)} is knocked out.`, unit.id)
end
local function queueKo(unit)
	if not unit or unit.id == nil or unit.isAlive ~= false then return end
	local s = _snap[unit.id]
	if (s and s.koLogged) or _pendingKo[unit.id] then return end
	_pendingKo[unit.id] = unit
	table.insert(_pendingKoOrder, unit.id)
end
local function flushPendingKo()
	if #_pendingKoOrder == 0 then return end
	local order = _pendingKoOrder
	_pendingKoOrder = {}
	for _, id in ipairs(order) do
		local u = _pendingKo[id]
		_pendingKo[id] = nil
		if u and u.isAlive == false then logKo(u) end
	end
end
function BattleVisualBroadcaster.FlushPendingKo()
	flushPendingKo()
end

-- Captured at diff time, warned at flush time only if the line survived dedup.
local function uncausedTrace()
	return debug.traceback("", 3)
end

-- Diff one unit against its snapshot and buffer log lines for what changed.
local function diffUnit(unit, cause)
	if not unit or unit.id == nil then return end
	local s = _snap[unit.id]
	if not s then
		seedUnit(unit)  -- first sight: seed, don't dump the whole state
		return
	end
	_unitsById[unit.id] = unit
	local silent = cause == SILENT
	local c = if silent then nil else cause
	local name = unitName(unit)
	local hp = unit.currentHp or 0
	local mp = unit.currentMp or 0
	local alive = unit.isAlive ~= false
	local st = statusSet(unit)

	if not silent then
		local dHp = hp - s.hp
		if dHp < 0 then
			bufferEntry({ kind = "hpLoss", cause = c, unitId = unit.id, name = name, amount = -dHp, category = "action",
				trace = if c then nil else uncausedTrace() })
		elseif dHp > 0 then
			bufferEntry({ kind = "hpGain", cause = c, unitId = unit.id, name = name, amount = dHp, category = "action" })
		end
		if s.alive and not alive then
			bufferEntry({ kind = "ko", cause = c, unitId = unit.id, name = name, category = "ko",
				trace = if c then nil else uncausedTrace() })
		elseif (not s.alive) and alive then
			bufferEntry({ kind = "revive", cause = c, unitId = unit.id, name = name, category = "ko" })
		end
		for id in pairs(st) do
			if not s.st[id] then
				bufferEntry({ kind = "statusAdd", cause = c, unitId = unit.id, name = name,
					statusId = id, statusName = statusName(id), category = "status" })
			end
		end
		for id in pairs(s.st) do
			if not st[id] then
				bufferEntry({ kind = "statusRem", cause = c, unitId = unit.id, name = name,
					statusId = id, statusName = statusName(id), category = "status" })
			end
		end
		-- MP is only logged when an effect caused it (passive regen stays silent).
		-- Passive regen mutates MP without any broadcast, so a later caused sync (e.g.
		-- Hail) would otherwise report the regen too: MP lines are opt-in per cause.
		local dMp = mp - s.mp
		if c and dMp ~= 0 and (MP_CAUSES[c] or _mpCauseOverride) then
			bufferEntry({ kind = if dMp < 0 then "mpLoss" else "mpGain", cause = c, unitId = unit.id,
				name = name, amount = math.abs(dMp), category = "status" })
		end
	end
	-- HEAL_CAUSES (2026-11-08): remember a heal this cause just logged, so HealingApplied can skip
	-- describing the same HP gain again. Any other HP change replaces / clears the record.
	if hp ~= s.hp then
		s.loggedGain = if c ~= nil and HEAL_CAUSES[c] and hp > s.hp then { amount = hp - s.hp, hp = hp } else nil
	end
	s.hp = hp
	s.mp = mp
	s.alive = alive
	if alive then s.koLogged = nil end  -- R7: alive again, a later KO gets its own line
	s.st = st
end

local function unitAtTile(x, y)
	local fallback = nil
	for id, u in pairs(_unitsById) do
		if u.tileX == x and u.tileY == y then
			local s = _snap[id]
			if s and (s.hp ~= (u.currentHp or 0) or s.alive ~= (u.isAlive ~= false)) then
				return u  -- the unit whose state just changed
			end
			if u.isAlive then fallback = fallback or u end
		end
	end
	return fallback
end

-- Public hook for services that resolve events outside this module
-- (Interact, counters, channel landing/interrupts, removals).
function BattleVisualBroadcaster.Log(category, text, unitId)
	logEntry(category, text, unitId)
end

-- Scoped cause label for code that broadcasts indirectly. Returns the previous
-- label; pass it to ClearCause to restore (supports nesting).
function BattleVisualBroadcaster.SetCause(label)
	local prev = _scopedCause
	_scopedCause = label
	return prev
end

function BattleVisualBroadcaster.ClearCause(prev)
	_scopedCause = prev
end

function BattleVisualBroadcaster.GetCause()
	return _scopedCause
end

-- Flush buffered/grouped log lines now (end of command, end of CT-tick block).
function BattleVisualBroadcaster.FlushLog()
	flushLog()
end

-- True when the unit's current HP is what clients were last sent (every HP change so far already
-- went out with its own cause, e.g. Blood Price's HP cost or a Lifesteal heal). 2026-11-09.
function BattleVisualBroadcaster.IsHpShown(unit): boolean
	if not unit or unit.id == nil then return false end
	local s = _snap[unit.id]
	return s ~= nil and s.hp == (unit.currentHp or 0)
end

-- Refresh a unit's log snapshot to its current state WITHOUT logging -- for code
-- that logged the change itself via Log() (e.g. ObjectEffectService.TriggerTrap).
function BattleVisualBroadcaster.SyncUnit(unit)
	if not unit or unit.id == nil then return end
	retract(unit.id, { hpLoss = true, hpGain = true, ko = true, revive = true, statusAdd = true, statusRem = true, mpLoss = true, mpGain = true })
	seedUnit(unit)
end

-- Clear all log snapshots (battle end / reset).
function BattleVisualBroadcaster.ResetLogState()
	flushLog()
	table.clear(_pendingKo)       -- R7: a held KO never carries into another battle
	table.clear(_pendingKoOrder)
	table.clear(_heldPushes)  -- Job 1: a held push never carries into another battle
	_holdPushes = false
	table.clear(_snap)
	table.clear(_unitsById)
	_scopedCause = nil
end

--------------------------------------------------
-- PACING
--------------------------------------------------

local PACE = {
	BattleStart  = 2.5,
	TurnStart    = 0.5,
	Move         = 1.0,
	Action       = 1.2,
	Defeat       = 1.8,
	TurnEnd      = 0.4,
	BattleEnd    = 0.0,
	Status       = 0.6,
	Dot          = 0.8,
	Healing      = 0.8,
}

-- Job 1 (2026-11-09): send held push visuals (client event, then its log line, then the push pause).
-- targetId nil = any unit; anyTag = ignore the tag.
local function releaseHeldPushes(targetId: any, tag: any, anyTag: boolean)
	if #_heldPushes == 0 then return end
	local send = {}
	local keep = {}
	for _, h in ipairs(_heldPushes) do
		if (targetId == nil or h.targetId == targetId) and (anyTag or h.tag == tag) then
			table.insert(send, h)
		else
			table.insert(keep, h)
		end
	end
	if #send == 0 then return end
	_heldPushes = keep
	for _, h in ipairs(send) do
		BattleEvents.UnitPushed:FireAllClients(h.payload)
		logEntry("action", h.text, h.pusherId)
		task.wait(PACE.Action)
	end
end

function BattleVisualBroadcaster.HoldPushes(on: boolean)
	_holdPushes = on == true
end

-- Stamp the pushes held by the commit that just ran with a new tag (an AI turn batches several commits).
local _pushTagSeq = 0
function BattleVisualBroadcaster.TagHeldPushes(): number
	_pushTagSeq += 1
	for _, h in ipairs(_heldPushes) do
		if h.tag == nil then h.tag = _pushTagSeq end
	end
	return _pushTagSeq
end

function BattleVisualBroadcaster.ReleaseHeldPushes(targetId: any, tag: any)
	releaseHeldPushes(targetId, tag, false)
end

-- Everything still held, in order; also ends the hold.
function BattleVisualBroadcaster.FlushHeldPushes()
	_holdPushes = false
	releaseHeldPushes(nil, nil, true)
end

--------------------------------------------------
-- HELPERS
--------------------------------------------------

-- Info-panel stat values (2026-10-28): a COPY of derivedStats with CURRENT values from the same
-- calculation the battle uses (gear / race / trait / doctrine + active buffs and debuffs).
-- unit.derivedStats is never changed. Deferred require keeps this module free of load-order ties.
local function displayDerived(unit)
	if not unit.derivedStats then return nil end
	local ok, svc = pcall(require, script.Parent.StatCalcService)
	if ok and svc and svc.BuildDisplay then
		return svc.BuildDisplay(unit, "current")
	end
	return unit.derivedStats
end

local function serializeUnit(unit)
	local result = {
		id          = unit.id,
		name        = unit.name,
		side        = unit.side,
		enemyType   = unit.enemyType,  -- Grunt/Veteran/Elite; client shows tier star on the name
		-- Portrait asset ID (numeric) for the unit's face image. Assigned by
		-- EnemyGenerator to enemy/neutral/NPC units only; nil for player units
		-- and summons (client falls back to the colored name box when nil).
		portraitAssetId = unit.portraitAssetId,
		tileX       = unit.tileX,
		tileY       = unit.tileY,
		-- FACING FIX (2026-10-21): the BattleStarted packet never carried facing, so the
		-- client fell back to `unit.facing or "S"` and every unit faced plain south at
		-- battle start (enemies visibly turned AWAY from center). The server computes the
		-- correct center-facing (INITIAL FACING block in Main) and stores it on the unit;
		-- carry it through so the client's orientUnitToFacing uses the real value. Tokens
		-- are abbreviations (N/NE/E/.../NW) matching GameConstants.FACING_VECTORS keys.
		facing      = unit.facing,
		currentHp   = unit.currentHp,
		maxHp       = unit.maxHp,
		currentMp   = unit.currentMp or 0,
		maxMp       = unit.maxMp or 0,
		isAlive     = unit.isAlive,
		stats = unit.effectiveStats and {
			STR = unit.effectiveStats.STR,
			AGI = unit.effectiveStats.AGI,
			INT = unit.effectiveStats.INT,
			VIT = unit.effectiveStats.VIT,
			DEX = unit.effectiveStats.DEX,
			LUK = unit.effectiveStats.LUK,
		} or nil,
		currentAp   = unit.currentAp,
		remainingRt = unit.remainingRt,
		skillIds    = unit.skillIds or {},
		statuses    = StatusService.GetStatusSummary(unit),
		derivedStats = displayDerived(unit),
		primaryStats = unit.primaryStats or nil,
		level        = unit.level or 1,
		-- Compact weapon summary for battle UI display
		weaponName     = nil,
		weaponArchetype = nil,
		weaponDamage   = unit.weaponDamage or 0,
		weaponWt       = unit.weaponWt or 0,
		weaponRtDelay  = unit.weaponRtDelay or 0,
		weaponPattern  = unit.weaponPattern or "Single",
		weaponRange    = unit.weaponMaxRange or 1,
		-- Doctrine (display name)
		doctrine       = unit.doctrineId and DoctrineData[unit.doctrineId]
			and DoctrineData[unit.doctrineId].name or nil,
		-- Race (display name)
		race           = unit.raceId and RaceData.GetRace(unit.raceId)
			and RaceData.GetRace(unit.raceId).name or nil,
	}

	-- Get weapon name from equipment slots if available
	if unit.equipmentSlots then
		local mainHand = unit.equipmentSlots.MainHand
		if mainHand then
			result.weaponName = mainHand.name or nil
			result.weaponArchetype = mainHand.archetype or nil
		end
	end

	return result
end

-- SHARED SERIALIZER (2026-10-22): the single source of truth for a unit's client
-- packet. Deployment packaging (Main.serializeForDeployment) now calls THIS same
-- function, so deployment and battle describe every unit identically -- a field can
-- never again be present in one phase's packet and missing from the other (the root
-- cause behind the facing / HP-MP / stats "works in battle, blank in deployment"
-- class of bug). Callers that need a phase-specific tweak (e.g. deployment's weapon
-- label) adjust the returned table themselves; the field SET is always the same.
function BattleVisualBroadcaster.SerializeUnit(unit)
	return serializeUnit(unit)
end

local function serializeSkill(skillDef)
	return {
		id          = skillDef.id,
		name        = skillDef.name,
		range       = skillDef.range or 1,
		mpCost      = skillDef.mpCost or 0,
		rtCost      = skillDef.rtCost or 0,
		channelTime = skillDef.channelTime or 0,
		targetRules = skillDef.targetRules or "Enemy Unit",
		pattern     = skillDef.pattern or "Single",
		isHealing   = skillDef.isHealing or false,
		tags        = skillDef.tags or {},
	}
end

--------------------------------------------------
-- PUBLIC API
--------------------------------------------------

function BattleVisualBroadcaster.BattleStarted(units)
	_logTurn = 0
	BattleVisualBroadcaster.ResetLogState()
	logEntry("info", "Battle begins.")
	local serialized = {}
	for _, unit in ipairs(units) do
		table.insert(serialized, serializeUnit(unit))
		seedUnit(unit)  -- Battle Log Coverage: first UnitStateChanged must not dump state
	end

	BattleEvents.BattleStarted:FireAllClients({
		units = serialized,
		elevationMap = GameConstants.ELEVATION_MAP,
		terrainMap   = GameConstants.TERRAIN_MAP,
		blockers     = GameConstants.BLOCKERS,
	})
	task.wait(PACE.BattleStart)
end

-- Turn-bar time for a unit (user ruling 2026-10-27). Item devices take no turns: the bar shows
-- them at their next timed activation (PulseScheduler stamps deviceNextIn). nil = leave the unit
-- out of the bar (a device with nothing left to fire).
function BattleVisualBroadcaster.TimelineRtFor(u)
	if u.isItemDevice then return u.deviceNextIn end
	return u.remainingRt
end

function BattleVisualBroadcaster.TurnStarted(unit, ct, allUnits)
	-- Job 1: a held push is never carried into the next turn (should not happen: each batch sends its own).
	if #_heldPushes > 0 then
		warn(`[BattleVisualBroadcaster] {#_heldPushes} held push visual(s) were not sent by their batch; sending now.`)
	end
	BattleVisualBroadcaster.FlushHeldPushes()
	flushPendingKo()  -- R7 fallback: a held KO no hit line claimed goes before the next turn header
	_logTurn += 1
	logEntry("turn", `{unitName(unit)}  ·  turn {_logTurn}  ·  CT {ct or 0}`, unit.id)
	-- Build a compact snapshot of all units' RT for client timeline simulation
	local allUnitsRt = {}
	if allUnits then
		for _, u in ipairs(allUnits) do
			local _rt = u.isAlive and BattleVisualBroadcaster.TimelineRtFor(u) or nil
			if _rt then
				table.insert(allUnitsRt, {
					id          = u.id,
					name        = u.name,
					side        = u.side,
					remainingRt = _rt,
					isChanneling = u.isChanneling or false,
					cycleRt     = u.isItemDevice and u.deviceCycleCt or nil,     -- device: CT between activations
					cyclesLeft  = u.isItemDevice and u.devicePulsesLeft or nil,  -- device: activations left
				})
			end
		end
	end
	BattleEvents.TurnStarted:FireAllClients({
		unitId   = unit.id,
		ct       = ct,
		statuses = StatusService.GetStatusSummary(unit),
		currentMp = unit.currentMp or 0,
		maxMp     = unit.maxMp or 0,
		allUnitsRt = allUnitsRt,
	})
	task.wait(PACE.TurnStart)
end

function BattleVisualBroadcaster.UnitMoved(unit)
	-- Job 1: a held push of this unit is shown before its next move, so the token never jumps back.
	if #_heldPushes > 0 then releaseHeldPushes(unit.id, nil, true) end
	BattleEvents.UnitMoved:FireAllClients({
		unitId = unit.id,
		tileX  = unit.tileX,
		tileY  = unit.tileY,
	})
	task.wait(PACE.Move)
end

-- animKind (optional, 2026-10-28): AnimationRegistry kind the actor plays (nil = client
-- fallback, "None" = nothing). The server only names it; the client animates (NET-001).
function BattleVisualBroadcaster.UnitActed(actor, target, outcome, skillName, skillId, animKind)
	BattleEvents.UnitActed:FireAllClients({
		actorId     = actor.id,
		actionType  = skillName and "Skill" or "Attack",
		targetId    = target.id,
		damage      = outcome.finalDamage,
		skillName   = skillName,
		skillId     = skillId,  -- client VFX registry lookup (element/tags)
		animKind    = animKind,
		-- Rulings R9 (handoff 1, 2026-11-09): this hit's own HP when the caller recorded it (AI turns are
		-- sent after the whole turn), so the bar steps down hit by hit; otherwise the live HP, as before.
		targetHp    = if outcome.targetHpAfter ~= nil then outcome.targetHpAfter else target.currentHp,
		targetMaxHp = target.maxHp,
		statusApplied = outcome.statusApplied or nil,
		rtDelay     = outcome.rtDelay or nil,
	})
	do
		local head = if skillName
			then `{unitName(actor)} uses {skillName} on {unitName(target)}`
			else `{unitName(actor)} attacks {unitName(target)}`
		-- Item 10 (2026-11-08 11:52 PM): HP after THIS hit when the caller recorded it (AI turns are logged
		-- after the whole turn); otherwise the live HP, as before.
		local hpShown = if outcome.targetHpAfter ~= nil then outcome.targetHpAfter else target.currentHp
		local parts = { `{head}: -{outcome.finalDamage or 0} HP ({hpShown or 0}/{target.maxHp or 0})` }
		if outcome.statusApplied and outcome.statusApplied ~= "" then
			table.insert(parts, `+{outcome.statusApplied}`)
		end
		if outcome.rtDelay and outcome.rtDelay > 0 then
			table.insert(parts, `target RT +{outcome.rtDelay}`)
		end
		logEntry("action", table.concat(parts, ", "), actor.id)
		syncHp(target)
		if outcome.statusApplied and outcome.statusApplied ~= "" then syncStatus(target, outcome.statusApplied, true) end
	end
	task.wait(PACE.Action)
	-- Job 1 (2026-11-09): this hit's held knockback / collision now -- after the hit, before the KO below.
	releaseHeldPushes(target.id, outcome.pushTag, false)

	-- Rulings R9 (handoff 1, 2026-11-09): the defeated event AND the KO line go only with the hit that
	-- knocked the unit out (koHere == false: an earlier, non-lethal hit of this AI turn), so the client
	-- never shows the unit down before its last hit. R7: logKo writes one line per KO, after this hit line
	-- (a push / collision KO of this target was held back for it).
	if not target.isAlive and outcome.koHere ~= false then
		BattleEvents.UnitDefeated:FireAllClients({ unitId = target.id })
		logKo(target)
		task.wait(PACE.Defeat)
	end
end

-- Slice 3: broadcast DoT damage
-- sourceName (optional, 2026-10-27): a device that dealt the hit (e.g. "Sentry Turret"); the
-- battle log then names it instead of reading like a status tick.
function BattleVisualBroadcaster.DotDamage(unit, statusId, damage, sourceName)
	BattleEvents.DotDamage:FireAllClients({
		unitId    = unit.id,
		statusId  = statusId,
		damage    = damage,
		currentHp = unit.currentHp,
		maxHp     = unit.maxHp,
	})
	if sourceName then
		logEntry("action", `{sourceName} hits {unitName(unit)}: -{damage or 0} HP ({unit.currentHp or 0}/{unit.maxHp or 0})`, unit.id)
	else
		logEntry("status", `{unitName(unit)} takes {damage or 0} {statusId} damage ({unit.currentHp or 0}/{unit.maxHp or 0})`, unit.id)
	end
	syncHp(unit)
	task.wait(PACE.Dot)

	if not unit.isAlive then
		BattleEvents.UnitDefeated:FireAllClients({ unitId = unit.id })
		logKo(unit)  -- R7: one KO line per KO
		task.wait(PACE.Defeat)
	end
end

-- Slice 3: broadcast healing
-- animKind (optional, 2026-10-28): caster animation kind, same contract as UnitActed.
function BattleVisualBroadcaster.HealingApplied(actor, target, amount, skillName, skillId, animKind)
	BattleEvents.HealingApplied:FireAllClients({
		actorId     = actor.id,
		targetId    = target.id,
		amount      = amount,
		targetHp    = target.currentHp,
		targetMaxHp = target.maxHp,
		statuses    = if target.statusInstances then StatusService.GetStatusSummary(target) else nil,  -- Venom weaken/cure (2026-10-26)
		skillName   = skillName,
		skillId     = skillId,  -- client VFX registry lookup
		animKind    = animKind,
	})
	-- HEAL_CAUSES (2026-11-08): a self-heal already logged under its own cause (e.g. "Vitality Surge
	-- healed Mage for 5.") is not logged again as "Mage heals Mage with <skill>" (one event = one line,
	-- rules 225). The heal number / HP bar event above still fires.
	local _ts = if actor and target and actor.id ~= nil and actor.id == target.id then _snap[target.id] else nil
	local _lg = _ts and _ts.loggedGain
	if _lg and _lg.amount == amount and _lg.hp == (target.currentHp or 0) then
		_ts.loggedGain = nil
		flushLog()  -- the cause's own line goes out now, in order
	else
		logEntry("action", `{unitName(actor)} heals {unitName(target)}{if skillName then ` with {skillName}` else ""}: +{amount or 0} HP ({target.currentHp or 0}/{target.maxHp or 0})`, actor.id)
	end
	syncHp(target)
	if target and target.statusInstances and target.id ~= nil and _snap[target.id] then _snap[target.id].st = statusSet(target) end
	task.wait(PACE.Healing)
end

-- Slice 4A: broadcast channel fizzle (target died, MP insufficient, etc.)
-- Channel loop start: client plays a looping Charging VFX on the caster
-- (Charging 1 for damage skills, Charging 2 for healing) until ChannelEnded
-- (executed) or ChannelFizzled (interrupted).
-- animKind (optional, 2026-10-28): caster animation at channel start (double-cast for a
-- channeled skill, quick cast for an activation-delayed one, Interact for Resuscitate).
function BattleVisualBroadcaster.ChannelStarted(unit, isHealing, animKind)
	if not unit then return end
	BattleEvents.ChannelStarted:FireAllClients({ unitId = unit.id, isHealing = isHealing == true, animKind = animKind })
end

-- Channel loop stop on successful execution (interruption is signalled by
-- ChannelFizzled, which the client also treats as a stop).
function BattleVisualBroadcaster.ChannelEnded(unit)
	if not unit then return end
	BattleEvents.ChannelEnded:FireAllClients({ unitId = unit.id })
end

-- Attacker-side multi-target (Cleave) flourish: the client plays Multi-Slash ON
-- THE ATTACKER once when a single action strikes 2+ targets. Each struck target
-- still plays its own Hit effect via the per-target UnitActed events.
function BattleVisualBroadcaster.MultiTargetHit(unit)
	if not unit then return end
	BattleEvents.MultiTargetHit:FireAllClients({ unitId = unit.id })
end

function BattleVisualBroadcaster.ChannelFizzled(actor, skillName, reason)
	BattleEvents.ChannelFizzled:FireAllClients({
		actorId   = actor.id,
		skillName = skillName,
		reason    = reason or "fizzled",
		tileX     = actor.tileX,
		tileY     = actor.tileY,
	})
	logEntry("channel", `{unitName(actor)}'s {skillName or "skill"} fails ({reason or "fizzled"}).`, actor.id)
	task.wait(PACE.Action)
end

-- Slice 3: send skill card data to a specific player
function BattleVisualBroadcaster.SendSkillCards(player, unit, skills)
	local serializedSkills = {}
	for _, skillDef in ipairs(skills) do
		table.insert(serializedSkills, serializeSkill(skillDef))
	end
	BattleEvents.SkillCardData:FireClient(player, {
		unitId = unit.id,
		skills = serializedSkills,
		currentMp = unit.currentMp or 0,
		maxMp     = unit.maxMp or 0,
	})
end

-- Slice 3: send target highlight tiles to a specific player
function BattleVisualBroadcaster.SendTargetHighlight(player, tiles, mode)
	BattleEvents.TargetHighlight:FireClient(player, {
		tiles = tiles,
		mode  = mode or "enemy", -- "enemy" or "ally"
	})
end

-- Status broadcasts
function BattleVisualBroadcaster.StatusApplied(unit, statusId, remainingTurns, sourceIcon, sourceDesc, sourceDuration)
	-- Damage prediction so the client can show it immediately. Pulled from the ONE shared
	-- StatusService.GetStatusSummary (the same data TurnStarted/TurnEnded send) instead of a
	-- local copy of the math that only covered Poison/Burn -- so every damaging debuff gets
	-- its number the moment it is applied, and all phases agree. (2026-10-26)
	local nextDamage, storedBurn, stacks = nil, nil, nil
	local def = GameConstants.STATUSES[statusId]  -- still used by the battle-log line below
	for _, entry in ipairs(StatusService.GetStatusSummary(unit)) do
		if entry.id == statusId then
			nextDamage = entry.nextDamage
			storedBurn = entry.storedBurn
			stacks = entry.stacks
			break
		end
	end
	BattleEvents.StatusApplied:FireAllClients({
		unitId         = unit.id,
		statusId       = statusId,
		remainingTurns = remainingTurns,
		nextDamage     = nextDamage,
		storedBurn     = storedBurn,
		stacks         = stacks,
		-- Fallback icon for statuses with no dedicated Theme icon: the icon of the
		-- skill/augment that applied it. Client uses it only when GetStatusIcon is nil.
		sourceIcon     = sourceIcon,
		-- Fallback description/duration for synthetic pills (stance self-buffs) whose
		-- id is NOT in GameConstants.STATUSES. The detailed inspector reads these when
		-- it has no status-table def to pull description/duration from.
		sourceDesc     = sourceDesc,
		sourceDuration = sourceDuration,
	})
	do
		local dur = ""
		if def and def.durationCt then
			dur = ` ({def.durationCt} CT)`
		elseif type(remainingTurns) == "number" then
			dur = ` ({remainingTurns} turn{if remainingTurns == 1 then "" else "s"})`
		end
		-- Item 10 (2026-11-08 11:52 PM): one application = one line. An augment (e.g. Pinning Support) announces
		-- its status when it lands; the action summary (BattleTurnController) then announced the same status
		-- again. Skip the line when this exact instance (same table, same time left) was already logged.
		local _inst = StatusService.HasStatus(unit, statusId)
		local _stamp = if _inst then `{tostring(_inst.remainingCt)}|{tostring(_inst.remainingTurns)}` else nil
		local _s = if unit and unit.id ~= nil then _snap[unit.id] else nil
		local _prev = _s and _s.statusLogged and _s.statusLogged[statusId]
		local _dup = _inst ~= nil and _prev ~= nil and _prev.inst == _inst and _prev.stamp == _stamp
		if not _dup then
			logEntry("status", `{unitName(unit)} gains {statusId}{dur}.`, unit.id)
		end
		syncStatus(unit, statusId, true)
		_s = if unit and unit.id ~= nil then _snap[unit.id] else nil  -- syncStatus may have just seeded it
		if _s and _inst then
			_s.statusLogged = _s.statusLogged or {}
			_s.statusLogged[statusId] = { inst = _inst, stamp = _stamp }
		end
	end
	task.wait(PACE.Status)
end

function BattleVisualBroadcaster.StatusExpired(unit, statusId)
	BattleEvents.StatusExpired:FireAllClients({
		unitId   = unit.id,
		statusId = statusId,
	})
	logEntry("status", `{statusId} wears off {unitName(unit)}.`, unit.id)
	syncStatus(unit, statusId, false)
end

function BattleVisualBroadcaster.TurnEnded(unit, nextRt)
	BattleEvents.TurnEnded:FireAllClients({
		unitId   = unit.id,
		nextRt   = nextRt,
		statuses = StatusService.GetStatusSummary(unit),
		currentMp = unit.currentMp or 0,
	})
	if unit.isAlive and type(nextRt) == "number" then
		logEntry("rt", `{unitName(unit)} acts again in {nextRt} RT.`, unit.id)
	end
	task.wait(PACE.TurnEnd)
end

function BattleVisualBroadcaster.BattleEnded(winner, units)
	BattleVisualBroadcaster.FlushHeldPushes()  -- Job 1: nothing held is lost at battle end
	local serialized = {}
	for _, unit in ipairs(units) do
		table.insert(serialized, serializeUnit(unit))
	end

	BattleEvents.BattleEnded:FireAllClients({
		winner = winner,
		units  = serialized,
	})
	flushPendingKo()  -- R7: a held KO line still goes before the result line
	logEntry("info", `Battle over: {tostring(winner)} wins.`)
	BattleVisualBroadcaster.ResetLogState()
	task.wait(PACE.BattleEnd)
end

--------------------------------------------------
-- GUARD
--------------------------------------------------

function BattleVisualBroadcaster.GuardActivated(unit, guardRt, mitigation)
	BattleEvents.GuardActivated:FireAllClients({
		unitId  = unit.id,
		guardRt = guardRt,
		mitigation = mitigation or 0.35,
	})
	logEntry("action", `{unitName(unit)} guards (-{math.round((mitigation or 0.35) * 100)}% damage taken), RT +{guardRt or 0}.`, unit.id)
	task.wait(PACE.Action * 0.5)
end

--------------------------------------------------
-- PUSH
--------------------------------------------------

function BattleVisualBroadcaster.UnitPushed(pusher, target, result, cause)
	-- Job 1 (2026-11-09): built now (this push's own HP values); sent now, or held for the hit that caused it.
	local held = _holdPushes
	local payload = {
		pusherId       = pusher.id,
		targetId       = target.id,
		pushed         = result.pushed,
		tilesDisplaced = result.tilesDisplaced,
		finalTileX     = result.finalTileX,
		finalTileY     = result.finalTileY,
		wallDamage     = result.wallCollision and result.wallCollision.damage or 0,
		fallDamage     = result.fallDamage or 0,
		blockedBy      = result.blockedBy,
		targetHp       = target.currentHp,
		targetMaxHp    = target.maxHp,
		-- Unit the target was shoved into (2026-10-30, visual only): its HP after the
		-- collision, so the client can update its bar and show a collision KO.
		collidedId     = result.wallCollision and result.wallCollision.collidedUnitId or nil,
		collidedHp     = result.wallCollision and result.wallCollision.collidedUnitHpAfter or nil,
	}
	if not held then BattleEvents.UnitPushed:FireAllClients(payload) end
	do
		local text
		local wallDmg = result.wallCollision and result.wallCollision.damage or 0
		-- Item 8 (2026-11-08 11:52 PM): the unit it was shoved / pulled into (e.g. Vortex Strike pulling a unit
		-- into its caster) also takes collision damage: log it, with the cause when the caller gives one.
		local hitId = result.wallCollision and result.wallCollision.collidedUnitId or nil
		local hitDmg = result.wallCollision and result.wallCollision.collidedUnitDamage or 0
		local hitUnit = if hitId ~= nil then _unitsById[hitId] else nil
		local hitText = if hitUnit and hitDmg > 0
			then `, {unitName(hitUnit)} -{hitDmg} HP ({hitUnit.currentHp or 0}/{hitUnit.maxHp or 0})` else ""
		local causeText = if cause then ` ({tostring(cause)})` else ""
		if result.pushed and (result.tilesDisplaced or 0) > 0 then
			text = `{unitName(pusher)} pushes {unitName(target)} {result.tilesDisplaced} tile{if result.tilesDisplaced == 1 then "" else "s"}`
			if wallDmg > 0 then text ..= `, wall hit -{wallDmg} HP` end
			if (result.fallDamage or 0) > 0 then text ..= `, fall -{result.fallDamage} HP` end
			text ..= ` ({target.currentHp or 0}/{target.maxHp or 0})`  -- R7 (handoff 1): the pushed unit's own HP
			text ..= hitText .. causeText .. "."
		elseif wallDmg > 0 or hitText ~= "" then
			-- Blocked, but it still collided (a pull into the puller, a push into an adjacent wall).
			local into = if hitUnit then unitName(hitUnit) elseif result.blockedBy then tostring(result.blockedBy) else "an obstacle"
			text = `{unitName(target)} collides with {into}: -{wallDmg} HP ({target.currentHp or 0}/{target.maxHp or 0}){hitText}{causeText}.`
		else
			text = `{unitName(pusher)}'s push on {unitName(target)} is blocked{if result.blockedBy then ` by {tostring(result.blockedBy)}` else ""}.`
		end
		if held then
			table.insert(_heldPushes, { targetId = target.id, payload = payload, text = text, pusherId = pusher.id })
		else
			logEntry("action", text, pusher.id)
		end
		local _pd = (result.wallCollision and result.wallCollision.damage or 0) + (result.fallDamage or 0)
		-- KO lines only when the log still shows the unit standing (no second KO line if another
		-- broadcast already reported it).
		local function shownAlive(u: any): boolean
			local s = u and u.id ~= nil and _snap[u.id]
			return s ~= nil and s ~= false and s.alive == true
		end
		-- Rulings R7 (handoff 1, 2026-11-09): the KO is HELD (queueKo), not logged here, so it comes once,
		-- after the hit line of the same attack / skill (UnitActed); unclaimed ones at the batch end.
		if _pd > 0 then
			local wasShown = shownAlive(target)
			syncHp(target)
			if wasShown then queueKo(target) end
		elseif target and target.id ~= nil and _snap[target.id] then _snap[target.id].alive = target.isAlive ~= false end
		if hitUnit and hitDmg > 0 then
			local wasShown = shownAlive(hitUnit)
			syncHp(hitUnit)
			if wasShown then queueKo(hitUnit) end
		end
	end
	if not held then task.wait(PACE.Action) end  -- held: the pause is taken when it is sent
end

--------------------------------------------------
-- TURN SKIPPED (Phase 2)
--------------------------------------------------

function BattleVisualBroadcaster.TurnSkipped(unit, reason)
	BattleEvents.TurnSkipped:FireAllClients({
		unitId    = unit.id,
		unitName  = unit.name,
		side      = unit.side,
		reason    = reason,
	})
	logEntry("rt", `{unitName(unit)} loses the turn ({tostring(reason or "status")}).`, unit.id)
	task.wait(PACE.Action)
end

--------------------------------------------------
-- STATUS IMMUNE (Phase 4)
--------------------------------------------------

function BattleVisualBroadcaster.StatusImmune(unit, statusId, reason)
	BattleEvents.StatusImmune:FireAllClients({
		unitId    = unit.id,
		unitName  = unit.name,
		statusId  = statusId,
		reason    = reason,
	})
	logEntry("status", `{unitName(unit)} is immune to {statusId}{if reason then ` ({tostring(reason)})` else ""}.`, unit.id)
	syncStatus(unit, statusId, false)
end

--------------------------------------------------
-- TILE EFFECTS (TileEffectService)
--------------------------------------------------

-- cause (optional, Battle Log Coverage 2026-10-28): a meaningful spread/placement
-- ("Fire") gets a grouped line ("Fire spread to 4 tiles."). nil = no line -- floor
-- re-establish and other background re-sends stay silent.
function BattleVisualBroadcaster.TileEffectApplied(tileX, tileY, effectId, durationCt, cause)
	BattleEvents.TileEffectApplied:FireAllClients({
		tileX      = tileX,
		tileY      = tileY,
		effectId   = effectId,
		durationCt = durationCt,
	})
	cause = cause or _scopedCause
	if type(cause) == "string" and cause ~= SILENT then
		bufferEntry({ kind = "tileEffect", cause = cause, category = "field" })
	end
end

function BattleVisualBroadcaster.TileEffectRemoved(tileX, tileY, effectId)
	BattleEvents.TileEffectRemoved:FireAllClients({
		tileX    = tileX,
		tileY    = tileY,
		effectId = effectId,
	})
end

-- TERRAIN CHANGED (BUG-002 fix 2026-10-22)
-- S->C: a tile's BASE terrain transformed mid-battle (fire burn-out grass->sand,
-- Holy restore, Dark corrupt, Earth->Cracked, Wind->Mud, weather, explosion chain).
-- GameConstants.TransformTerrain mutates TERRAIN_MAP server-side but the client only
-- received terrain at map-gen (MapDataSync), so every transform was invisible. Fired
-- by TileEffectService.transformAndBroadcast for every mid-battle transform path.
-- Minimal payload (NET-003) and visual-only on the client (NET-001). No pacing wait
-- (state sync, like TileEffectApplied / ObjectChanged).
-- Temporary road (ENV-019 Road Fabricator, 2026-10-27): the client tints the tile and
-- shows the lowered move cost. cut = 0 removes it.
function BattleVisualBroadcaster.RoadChanged(x, y, cut)
	BattleEvents.RoadChanged:FireAllClients({ x = x, y = y, cut = cut or 0 })
end

-- ENV-003 move-cost zone: the client tints the tile and its inspector shows the higher cost.
-- add = 0 removes it.
function BattleVisualBroadcaster.MoveCostChanged(x, y, add)
	BattleEvents.MoveCostChanged:FireAllClients({ x = x, y = y, add = add or 0 })
end

-- cause (optional, 2026-10-28): names a meaningful transform ("Fire", "The explosion")
-- -> grouped "Fire: 2 tiles became Sand." nil = background, no line.
function BattleVisualBroadcaster.TerrainChanged(x, y, terrainId, elevation, cause)
	-- elevation (optional, 2026-10-26): the tile's NEW elevation after a dig, so the client
	-- height map (inspector, labels, unit token height) follows. nil = unchanged.
	BattleEvents.TerrainChanged:FireAllClients({
		x         = x,
		y         = y,
		terrainId = terrainId,
		elevation = elevation,
	})
	cause = cause or _scopedCause
	if type(cause) == "string" and cause ~= SILENT then
		local label = tostring(terrainId)
		local tdef = GameConstants.TERRAIN_TYPES and GameConstants.TERRAIN_TYPES[terrainId]
		if type(tdef) == "table" and type(tdef.name) == "string" then label = tdef.name end
		bufferEntry({ kind = "terrain", cause = cause, label = label, category = "field" })
	end
end

--------------------------------------------------
-- OBS OBJECT CHANGED (Phase 2c-0)
-- S->C: a map OBS object's state changed (HP decrement / destroyed / moved).
--------------------------------------------------

-- label (optional, 2026-10-28): the object's DISPLAY type (GetDisplayType -- never the
-- true type of a disguised Mimic). When given, destroyed / moved / exploded changes get a
-- grouped log line. info.exploded = true -> "Bomb Barrel exploded." instead of destroyed.
-- Hidden objects are never broadcast, so they are never logged.
function BattleVisualBroadcaster.ObjectChanged(x, y, info, label)
	-- Fired by ObjectEffectService.ApplyObjectHit. The client updates the
	-- inspector HP readout and, on destroy, drops its own blocker so the opened
	-- tile is walkable/visible. No pacing wait (state sync, like UnitStateChanged).
	--   info.newHp     (number)   -> HP decremented to this value
	--   info.destroyed (true)     -> object broke and was removed; tile reverts
	--   info.moved     ({toX,toY})-> pushed to a new tile (emitted from Phase 2c-E)
	info = info or {}
	BattleEvents.ObjectChanged:FireAllClients({
		x         = x,
		y         = y,
		newHp     = info.newHp,
		destroyed = info.destroyed == true or nil,
		moved     = info.moved,
		objType   = info.objType,  -- A3: post-unmask display type refresh (nil otherwise)
	})
	if type(label) == "string" and label ~= "" and label ~= SILENT then
		local kind = nil
		if info.exploded == true then kind = "objExploded"
		elseif info.destroyed == true then kind = "objDestroyed"
		elseif info.moved then kind = "objPushed"
		elseif info.hit == true then kind = "objHit" end  -- F4: info.by = what hit it (nil = unknown)
		if kind == "objHit" then
			bufferEntry({ kind = kind, cause = info.by, label = label, category = "field" })
		elseif kind then
			bufferEntry({ kind = kind, cause = label, label = label, category = "field" })
		end
	end
end

--------------------------------------------------
-- TRAP SPRUNG (2026-10-28)
-- S->C: a step-on trap fired at (x,y). Display-only floating indicator; fired by
-- ObjectEffectService.TriggerTrap (covers hidden traps the client never drew).
--------------------------------------------------

--------------------------------------------------
-- OBJECT MARKER (2026-11-07, 18 new map objects)
-- S->C: tiles a map object will hit (Volcanic Vent next targets, Arcane Cannon danger line,
-- Heavy Artillery red cross). key = one marker set per source; an empty tile list clears it.
-- Display-only, no log line, no pacing wait. Payload = tile pairs only (NET-003).
--------------------------------------------------
function BattleVisualBroadcaster.ObjectMarker(key, tiles)
	if type(key) ~= "string" then return end
	local out = {}
	for _, t in ipairs(tiles or {}) do
		if type(t.x) == "number" and type(t.y) == "number" then
			out[#out + 1] = { t.x, t.y }
		end
	end
	BattleEvents.ObjectMarker:FireAllClients({ key = key, tiles = out })
end

function BattleVisualBroadcaster.TrapSprung(x, y, trapType, unitId, hidden)
	BattleEvents.TrapSprung:FireAllClients({
		x        = x,
		y        = y,
		trapType = trapType,
		unitId   = unitId,
		hidden   = hidden == true,
	})
end

--------------------------------------------------
-- UNIT STATE CHANGE (revive, etc.)
-- Generic broadcast for HP/isAlive changes outside normal combat.
--------------------------------------------------

-- cause (optional, Battle Log Coverage 2026-10-28): names what changed the unit
-- ("Hail", "Retribution"). nil falls back to the SetCause scope; still nil = the HP/KO
-- line uses neutral wording plus a [BattleLog] warn; MP changes with no cause stay
-- silent. SILENT ("__silent") absorbs the change without logging.
function BattleVisualBroadcaster.UnitStateChanged(unit, cause, logMp)
	if unit then
		local c = cause or _scopedCause
		relabel(unit.id, c)
		_mpCauseOverride = logMp == true
		diffUnit(unit, c)
		_mpCauseOverride = false
	end
	BattleEvents.UnitStateChanged:FireAllClients({
		unitId    = unit.id,
		hp        = unit.currentHp,
		maxHp     = unit.maxHp,
		-- D4 (2026-11-07): MP rides along so object MP changes (Garden of Revelation's new max MP,
		-- Magic Spring / Oasis restores) show at once instead of at the unit's next turn start.
		mp        = unit.currentMp,
		maxMp     = unit.maxMp,
		isAlive   = unit.isAlive,
		-- Side rides along (2026-11-12, display only): a recruit / Traitor flip (Enemy -> Neutral) keeps
		-- the client's overhead bar side outline in sync. The server stays the authority.
		side      = unit.side,
		-- Statuses ride along so a heal that weakens/cures Venom shows at once (2026-10-26).
		statuses  = if unit.statusInstances then StatusService.GetStatusSummary(unit) else nil,
	})
end

-- Status-only refresh (sweep 2026-11-06): sends the unit's current HP/statuses to clients WITHOUT
-- writing a battle-log HP diff. Used mid-hit (status conflict removals, e.g. Wet clearing Burn during
-- an attack) so the hit's own caused broadcast still logs the HP change; the old full
-- UnitStateChanged here logged it as an "uncaused hpLoss".
function BattleVisualBroadcaster.StatusSync(unit)
	if not unit then return end
	BattleEvents.UnitStateChanged:FireAllClients({
		unitId    = unit.id,
		hp        = unit.currentHp,
		maxHp     = unit.maxHp,
		isAlive   = unit.isAlive,
		statuses  = if unit.statusInstances then StatusService.GetStatusSummary(unit) else nil,
	})
end

-- Object-sourced damage feedback (2026-10-26). Map objects that deal damage used
-- to send only a bare HP sync (UnitStateChanged) with no number/flash/camera move,
-- so hits felt invisible -- especially when the victim was off-screen. This fires a
-- dedicated event the client turns into a floating damage number + impact flash on
-- the tile, plus a camera pan to the tile when focus=true. Callers pass focus=true
-- for the FIRST unit hit in an interaction (mirrors the attack/skill camera focus).
-- cause (optional, 2026-10-28): the object/source name ("Spike Trap", "Ballista").
-- Logs "<cause> hit <name> for N." for the unit on the tile, relabelling any uncaused
-- line a preceding UnitStateChanged already buffered (one event = one line).
function BattleVisualBroadcaster.ObjectDamage(tileX, tileY, amount, focus, cause)
	BattleEvents.ObjectDamage:FireAllClients({
		tileX  = tileX,
		tileY  = tileY,
		amount = amount,
		focus  = focus == true,
	})
	local c = cause or _scopedCause
	if c ~= nil then
		local u = unitAtTile(tileX, tileY)
		if u then
			relabel(u.id, c)
			diffUnit(u, c)
		end
	end
end

-- Explosion damage (Bomb Barrel / Land Mine). TileEffectService already CALLS
-- BattleVisualBroadcaster.ExplosionDamage, but the function never existed (the call
-- was a guarded silent no-op), so explosions showed no damage number. Define it now
-- and route it through the shared ObjectDamage feedback. focus defaults to false;
-- the explosion loop passes focus=true for its first damaged tile.
-- Explosions write HP directly and send no UnitStateChanged, so this is their only log
-- line (DotDamage is only the no-ExplosionDamage fallback). Default cause "The explosion".
function BattleVisualBroadcaster.ExplosionDamage(tileX, tileY, amount, focus, cause)
	BattleVisualBroadcaster.ObjectDamage(tileX, tileY, amount, focus == true, cause or _scopedCause or "The explosion")
end

--------------------------------------------------
-- FACING CHANGE
-- Broadcasts when a unit's facing direction changes.
--------------------------------------------------

--------------------------------------------------
-- ACTION ANNOUNCED
-- Fired when a unit commits an AP action (Move / Basic Attack / Skill / Guard /
-- Push / Item) and when a channeled skill fires. Client shows the label above
-- the unit's head for ~2s. No pacing wait - the action's own event follows.
--------------------------------------------------

-- animKind (optional, 2026-10-28): animation the announcing unit plays with the label
-- (Push / Interact / Open Treasure / Big Spell). nil = label only.
function BattleVisualBroadcaster.ActionAnnounced(unit, label, animKind)
	if not unit or type(label) ~= "string" or label == "" then return end
	BattleEvents.ActionAnnounced:FireAllClients({ unitId = unit.id, label = label, animKind = animKind })
end

function BattleVisualBroadcaster.FacingChanged(unit)
	BattleEvents.FacingChanged:FireAllClients({
		unitId = unit.id,
		facing = unit.facing,
		tileX  = unit.tileX,
		tileY  = unit.tileY,
	})
end

--------------------------------------------------
-- ITEM USED
-- Broadcasts when a unit uses a consumable item.
--------------------------------------------------

function BattleVisualBroadcaster.ItemUsed(actor, target, itemName, effectResult)
	effectResult = effectResult or {}
	BattleEvents.ItemUsed:FireAllClients({
		actorId     = actor.id,
		actorName   = actor.name,
		targetId    = target and target.id,
		targetName  = target and target.name,
		itemName    = itemName,
		effectType  = effectResult.effectType,
		amount      = effectResult.amount or 0,
		statusId    = effectResult.statusId,
		element     = effectResult.element,
		actorTileX  = actor.tileX,
		actorTileY  = actor.tileY,
		targetTileX = target and target.tileX,
		targetTileY = target and target.tileY,
	})
	do
		local tName = (target and target.name) or unitName(actor)
		local amount = effectResult.amount or 0
		local et = effectResult.effectType
		local summary
		if et == "Heal" or et == "Healing" then summary = `{tName} +{amount} HP`
		elseif et == "MpRestore" then summary = `{tName} +{amount} MP`
		elseif et == "StatusCure" then summary = `cured {effectResult.statusId or "status"} on {tName}`
		elseif et == "StatusApply" then summary = `{effectResult.statusId or "status"} on {tName}`
		elseif et == "Damage" then summary = `{tName} -{amount} HP`
		elseif et == "Revive" then summary = `revived {tName}`
		-- Placements (2026-10-27): say what was placed, never where (hidden traps stay hidden).
		elseif et == "Deploy" then summary = effectResult.description or "placed"
		elseif et == "DeployFailed" then summary = "placement failed"
		elseif et == nil or et == "Unimplemented" then summary = "no effect"
		else summary = `on {tName}` end
		logEntry("action", `{unitName(actor)} uses {itemName or "item"}: {summary}.`, actor.id)
		-- dedup: the item line already described this; refresh the target snapshot.
		if target then
			if et == "Heal" or et == "Healing" then syncHp(target)
			elseif et == "Damage" then syncHp(target)
			elseif et == "MpRestore" and target.id ~= nil and _snap[target.id] then _snap[target.id].mp = target.currentMp or 0
			elseif et == "StatusCure" then syncStatus(target, effectResult.statusId, false)
			elseif et == "StatusApply" then syncStatus(target, effectResult.statusId, true) end
		end
	end
end

-- Announce a single unit that entered the battle mid-fight (reinforcement).
-- The client spawns its token/health bar/facing using the same serialized
-- payload shape as BattleStarted, so the new unit renders identically to
-- units present at battle start.
-- Remove a unit's token from every client right now (2026-10-26: a replaced item
-- device). Same payload Main sends for a KO'd unit.
function BattleVisualBroadcaster.UnitRemoved(unit)
	if not unit then return end
	BattleEvents.UnitDefeated:FireAllClients({ unitId = unit.id, removeUnit = true })
end

-- MID-BATTLE MODELS (2026-11-10 fix): battle-start / deployment build each unit's R15 race
-- model in Main, but units that join mid-battle (Dragon Utopia, Mimic, events, summons,
-- revives) only fired UnitSpawned, so the client found no model and drew the cylinder.
-- Main injects its model builder here (DI: no require of Main). Runs before the client is
-- told, so the model already exists when spawnToken looks for it. Missing model -> no-op.
local _unitModelBuilder: ((unit: any) -> ())? = nil
function BattleVisualBroadcaster.SetUnitModelBuilder(fn: (unit: any) -> ())
	_unitModelBuilder = fn
end

function BattleVisualBroadcaster.UnitSpawned(unit)
	if _unitModelBuilder then
		local ok, err = pcall(_unitModelBuilder, unit)
		if not ok then warn(`[BattleVisualBroadcaster] model build failed for {tostring(unit and unit.name)}: {err}`) end
	end
	BattleEvents.UnitSpawned:FireAllClients({
		unit = serializeUnit(unit),
	})
	seedUnit(unit)
	logEntry("ko", `{unitName(unit)} enters the battle.`, unit.id)
end

-- Time cycle: broadcast the current time-of-day phase (Dawn/Day/Dusk/Night).
function BattleVisualBroadcaster.TimePhaseChanged(phase)
	BattleEvents.TimePhaseChanged:FireAllClients({ phase = phase })
	logEntry("field", `Time of day: {tostring(phase)}.`)
end

-- Weather/crisis: broadcast the active condition (one combined slot, per round).
function BattleVisualBroadcaster.WeatherChanged(condition)
	BattleEvents.WeatherChanged:FireAllClients({ condition = condition })
	do
		local n = if type(condition) == "table" then (condition.name or condition.id) else condition
		logEntry("field", if n and n ~= "" and n ~= "None" then `Condition: {tostring(n)}.` else "Weather clears.") -- user 2026-11-18 12:56 AM (rule 275 term)
	end
end

-- Battlefield event: broadcast that a named battlefield event triggered so the
-- client can show a dramatic center-screen banner. Visual-only announcement.
-- quiet=true: update the Event panel only, no dramatic banner (used to resync
-- start-of-battle events after BattleStarted so the banner doesn't replay).
function BattleVisualBroadcaster.BattlefieldEventAnnounced(eventName, quiet)
	-- eventName = nil clears the Event panel (dev END EVENT); always quiet (no banner).
	if not eventName then
		BattleEvents.BattlefieldEventAnnounced:FireAllClients({ eventName = nil, quiet = true })
		return
	end
	BattleEvents.BattlefieldEventAnnounced:FireAllClients({ eventName = eventName, quiet = quiet == true })
	if quiet ~= true then
		logEntry("field", `Battlefield event: {tostring(eventName)}.`)
	end
end

--------------------------------------------------
-- SHIELD CHANGED (shield subsystem 2026-10-05)
-- S->C: a unit's shield_total changed (granted, absorbed, decayed, or broke).
-- Client shows a shield bar/pill and a grant/break flourish. Payload matches
-- the BattleEvents.ShieldChanged contract { unitId, shieldTotal, delta, reason,
-- maxHp, currentHp }. No pacing wait: grants ride the action's own pacing and
-- decay ticks are stashed through state.ctStatusUnits (drained by Main).
--------------------------------------------------

-- cause (optional, 2026-10-28): names a grant ("Iron Barrier"). Logs grants and breaks
-- only; absorb/decay ticks stay silent.
function BattleVisualBroadcaster.ShieldChanged(unit, delta, reason, cause)
	if not unit then return end
	BattleEvents.ShieldChanged:FireAllClients({
		unitId      = unit.id,
		shieldTotal = unit.shield_total or 0,
		delta       = delta or 0,
		reason      = reason or "update",  -- "grant" | "absorb" | "decay" | "break"
		maxHp       = unit.maxHp,
		currentHp   = unit.currentHp,
	})
	local c = cause or _scopedCause
	if c ~= SILENT then
		if reason == "grant" and (delta or 0) > 0 then
			bufferEntry({ text = if c then `{unitName(unit)} gained a {delta} shield ({c}).` else `{unitName(unit)} gained a {delta} shield.`,
				kind = "shield", unitId = unit.id, category = "status" })
		elseif reason == "break" then
			bufferEntry({ text = `{unitName(unit)}'s shield broke.`, kind = "shield", unitId = unit.id, category = "status" })
		end
	end
end

return BattleVisualBroadcaster
