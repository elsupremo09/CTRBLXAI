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

local function logEntry(category, text, unitId)
	if type(text) ~= "string" or text == "" then return end
	BattleEvents.BattleLogEntry:FireAllClients({ t = _logTurn, c = category, x = text, u = unitId })
end

-- Public hook for services that resolve events outside this module
-- (Interact, counters, channel landing/interrupts, removals).
function BattleVisualBroadcaster.Log(category, text, unitId)
	logEntry(category, text, unitId)
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

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function serializeUnit(unit)
	local result = {
		id          = unit.id,
		name        = unit.name,
		side        = unit.side,
		enemyType   = unit.enemyType,  -- Grunt/Veteran/Elite; client shows tier star on the name
		tileX       = unit.tileX,
		tileY       = unit.tileY,
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
		derivedStats = unit.derivedStats or nil,
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
	logEntry("info", "Battle begins.")
	local serialized = {}
	for _, unit in ipairs(units) do
		table.insert(serialized, serializeUnit(unit))
	end

	BattleEvents.BattleStarted:FireAllClients({
		units = serialized,
		elevationMap = GameConstants.ELEVATION_MAP,
		terrainMap   = GameConstants.TERRAIN_MAP,
		blockers     = GameConstants.BLOCKERS,
	})
	task.wait(PACE.BattleStart)
end

function BattleVisualBroadcaster.TurnStarted(unit, ct, allUnits)
	_logTurn += 1
	logEntry("turn", `{unitName(unit)}  ·  turn {_logTurn}  ·  CT {ct or 0}`, unit.id)
	-- Build a compact snapshot of all units' RT for client timeline simulation
	local allUnitsRt = {}
	if allUnits then
		for _, u in ipairs(allUnits) do
			if u.isAlive then
				table.insert(allUnitsRt, {
					id          = u.id,
					name        = u.name,
					side        = u.side,
					remainingRt = u.remainingRt,
					isChanneling = u.isChanneling or false,
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
	BattleEvents.UnitMoved:FireAllClients({
		unitId = unit.id,
		tileX  = unit.tileX,
		tileY  = unit.tileY,
	})
	task.wait(PACE.Move)
end

function BattleVisualBroadcaster.UnitActed(actor, target, outcome, skillName, skillId)
	BattleEvents.UnitActed:FireAllClients({
		actorId     = actor.id,
		actionType  = skillName and "Skill" or "Attack",
		targetId    = target.id,
		damage      = outcome.finalDamage,
		skillName   = skillName,
		skillId     = skillId,  -- client VFX registry lookup (element/tags)
		targetHp    = target.currentHp,
		targetMaxHp = target.maxHp,
		statusApplied = outcome.statusApplied or nil,
		rtDelay     = outcome.rtDelay or nil,
	})
	do
		local head = if skillName
			then `{unitName(actor)} uses {skillName} on {unitName(target)}`
			else `{unitName(actor)} attacks {unitName(target)}`
		local parts = { `{head}: -{outcome.finalDamage or 0} HP ({target.currentHp or 0}/{target.maxHp or 0})` }
		if outcome.statusApplied and outcome.statusApplied ~= "" then
			table.insert(parts, `+{outcome.statusApplied}`)
		end
		if outcome.rtDelay and outcome.rtDelay > 0 then
			table.insert(parts, `target RT +{outcome.rtDelay}`)
		end
		logEntry("action", table.concat(parts, ", "), actor.id)
	end
	task.wait(PACE.Action)

	if not target.isAlive then
		BattleEvents.UnitDefeated:FireAllClients({ unitId = target.id })
		logEntry("ko", `{unitName(target)} is knocked out.`, target.id)
		task.wait(PACE.Defeat)
	end
end

-- Slice 3: broadcast DoT damage
function BattleVisualBroadcaster.DotDamage(unit, statusId, damage)
	BattleEvents.DotDamage:FireAllClients({
		unitId    = unit.id,
		statusId  = statusId,
		damage    = damage,
		currentHp = unit.currentHp,
		maxHp     = unit.maxHp,
	})
	logEntry("status", `{unitName(unit)} takes {damage or 0} {statusId} damage ({unit.currentHp or 0}/{unit.maxHp or 0})`, unit.id)
	task.wait(PACE.Dot)

	if not unit.isAlive then
		BattleEvents.UnitDefeated:FireAllClients({ unitId = unit.id })
		logEntry("ko", `{unitName(unit)} is knocked out.`, unit.id)
		task.wait(PACE.Defeat)
	end
end

-- Slice 3: broadcast healing
function BattleVisualBroadcaster.HealingApplied(actor, target, amount, skillName, skillId)
	BattleEvents.HealingApplied:FireAllClients({
		actorId     = actor.id,
		targetId    = target.id,
		amount      = amount,
		targetHp    = target.currentHp,
		targetMaxHp = target.maxHp,
		skillName   = skillName,
		skillId     = skillId,  -- client VFX registry lookup
	})
	logEntry("action", `{unitName(actor)} heals {unitName(target)}{if skillName then ` with {skillName}` else ""}: +{amount or 0} HP ({target.currentHp or 0}/{target.maxHp or 0})`, actor.id)
	task.wait(PACE.Healing)
end

-- Slice 4A: broadcast channel fizzle (target died, MP insufficient, etc.)
-- Channel loop start: client plays a looping Charging VFX on the caster
-- (Charging 1 for damage skills, Charging 2 for healing) until ChannelEnded
-- (executed) or ChannelFizzled (interrupted).
function BattleVisualBroadcaster.ChannelStarted(unit, isHealing)
	if not unit then return end
	BattleEvents.ChannelStarted:FireAllClients({ unitId = unit.id, isHealing = isHealing == true })
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
	-- Include damage prediction so client can display immediately
	local nextDamage = nil
	local storedBurn = nil
	local def = GameConstants.STATUSES[statusId]
	if def then
		if def.dotType == "Poison" then
			nextDamage = math.max(1, math.round(unit.maxHp * def.dotFraction))
		elseif def.dotType == "Burn" then
			-- Find the status instance to get stored burn
			local inst = StatusService.HasStatus(unit, statusId)
			storedBurn = inst and inst.storedBurn or 0
			nextDamage = storedBurn > 0 and math.max(1, math.round(storedBurn)) or nil
		end
	end
	BattleEvents.StatusApplied:FireAllClients({
		unitId         = unit.id,
		statusId       = statusId,
		remainingTurns = remainingTurns,
		nextDamage     = nextDamage,
		storedBurn     = storedBurn,
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
		logEntry("status", `{unitName(unit)} gains {statusId}{dur}.`, unit.id)
	end
	task.wait(PACE.Status)
end

function BattleVisualBroadcaster.StatusExpired(unit, statusId)
	BattleEvents.StatusExpired:FireAllClients({
		unitId   = unit.id,
		statusId = statusId,
	})
	logEntry("status", `{statusId} wears off {unitName(unit)}.`, unit.id)
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
	local serialized = {}
	for _, unit in ipairs(units) do
		table.insert(serialized, serializeUnit(unit))
	end

	BattleEvents.BattleEnded:FireAllClients({
		winner = winner,
		units  = serialized,
	})
	logEntry("info", `Battle over: {tostring(winner)} wins.`)
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

function BattleVisualBroadcaster.UnitPushed(pusher, target, result)
	BattleEvents.UnitPushed:FireAllClients({
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
	})
	do
		local text
		if result.pushed and (result.tilesDisplaced or 0) > 0 then
			text = `{unitName(pusher)} pushes {unitName(target)} {result.tilesDisplaced} tile{if result.tilesDisplaced == 1 then "" else "s"}`
			local wallDmg = result.wallCollision and result.wallCollision.damage or 0
			if wallDmg > 0 then text ..= `, wall hit -{wallDmg} HP` end
			if (result.fallDamage or 0) > 0 then text ..= `, fall -{result.fallDamage} HP` end
			text ..= "."
		else
			text = `{unitName(pusher)}'s push on {unitName(target)} is blocked{if result.blockedBy then ` by {tostring(result.blockedBy)}` else ""}.`
		end
		logEntry("action", text, pusher.id)
	end
	task.wait(PACE.Action)
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
end

--------------------------------------------------
-- TILE EFFECTS (TileEffectService)
--------------------------------------------------

function BattleVisualBroadcaster.TileEffectApplied(tileX, tileY, effectId, durationCt)
	BattleEvents.TileEffectApplied:FireAllClients({
		tileX      = tileX,
		tileY      = tileY,
		effectId   = effectId,
		durationCt = durationCt,
	})
end

function BattleVisualBroadcaster.TileEffectRemoved(tileX, tileY, effectId)
	BattleEvents.TileEffectRemoved:FireAllClients({
		tileX    = tileX,
		tileY    = tileY,
		effectId = effectId,
	})
end

--------------------------------------------------
-- UNIT STATE CHANGE (revive, etc.)
-- Generic broadcast for HP/isAlive changes outside normal combat.
--------------------------------------------------

function BattleVisualBroadcaster.UnitStateChanged(unit)
	BattleEvents.UnitStateChanged:FireAllClients({
		unitId    = unit.id,
		hp        = unit.currentHp,
		maxHp     = unit.maxHp,
		isAlive   = unit.isAlive,
	})
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

function BattleVisualBroadcaster.ActionAnnounced(unit, label)
	if not unit or type(label) ~= "string" or label == "" then return end
	BattleEvents.ActionAnnounced:FireAllClients({ unitId = unit.id, label = label })
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
		elseif et == nil or et == "Unimplemented" then summary = "no effect"
		else summary = `on {tName}` end
		logEntry("action", `{unitName(actor)} uses {itemName or "item"}: {summary}.`, actor.id)
	end
end

-- Announce a single unit that entered the battle mid-fight (reinforcement).
-- The client spawns its token/health bar/facing using the same serialized
-- payload shape as BattleStarted, so the new unit renders identically to
-- units present at battle start.
function BattleVisualBroadcaster.UnitSpawned(unit)
	BattleEvents.UnitSpawned:FireAllClients({
		unit = serializeUnit(unit),
	})
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
		logEntry("field", if n and n ~= "" and n ~= "None" then `Weather: {tostring(n)}.` else "Weather clears.")
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

function BattleVisualBroadcaster.ShieldChanged(unit, delta, reason)
	if not unit then return end
	BattleEvents.ShieldChanged:FireAllClients({
		unitId      = unit.id,
		shieldTotal = unit.shield_total or 0,
		delta       = delta or 0,
		reason      = reason or "update",  -- "grant" | "absorb" | "decay" | "break"
		maxHp       = unit.maxHp,
		currentHp   = unit.currentHp,
	})
end

return BattleVisualBroadcaster
