--!strict
-- LifeLinkService.lua
-- CTRBLXAI | Life Link (SKL-LIFE-LINK) lasting heal-share link. Server-only. Added 2026-11-08.
--
-- USER RULING 2026-11-08 4:21-4:23 PM (DB skills row SKL-LIFE-LINK, "[agent default, vetoable]" details):
--   * Lasts 2000 CT. One link per caster; a new cast replaces the old one.
--   * The linked ally gets 50% of EVERY heal the caster actually gains (skills, regen, lifesteal,
--     items, objects): overheal past max HP is not counted, rounded down, minimum 1.
--   * The shared heal triggers nothing (no heal-on-heal, no Venom weakening, no riders) and is never
--     shared again.
--   * Breaks when the two are more than 6 tiles apart (skill-range distance), or either is KO'd.
--   * Cannot target the caster. An ally may hold links from several casters.
--   * Not a status: cleanse / dispel never removes it.
--
-- Data lives on the battle state (state.lifeLinks, keyed by caster id), so a new battle never sees an
-- old battle's links. Distance / KO / time are checked on every CT advance (PulseScheduler hook), after
-- a knockback, and again right before any heal is shared (so a share never crosses 6 tiles).
-- Dependencies: BattleVisualBroadcaster only (battle log + HP bar).
-- Requires nothing that requires it (StatusService gets OnHealGained by injection from CommandService).

local BattleVisualBroadcaster = require(script.Parent.BattleVisualBroadcaster)

local LifeLinkService = {}

local DEFAULT_CT = 2000
local DEFAULT_SHARE = 0.5
local DEFAULT_MAX_DIST = 6

-- The battle state whose links are live. Set when a link is made and on every CT tick.
local _activeState: any = nil
-- True while a shared heal is being applied (belt-and-braces: a share is never re-shared).
local _sharing = false

-- Same distance as skill range (Chebyshev, TargetingService.chebyshevDistance).
local function distance(a: any, b: any): number
	return math.max(math.abs((a.tileX or 0) - (b.tileX or 0)), math.abs((a.tileY or 0) - (b.tileY or 0)))
end

local function breakLink(state: any, casterId: any, reason: string)
	local links = state and state.lifeLinks
	local link = links and links[casterId]
	if not link then
		return
	end
	links[casterId] = nil
	local cName = (link.caster and link.caster.name) or "?"
	local aName = (link.ally and link.ally.name) or "?"
	BattleVisualBroadcaster.Log("info", `Life Link between {cName} and {aName} ends ({reason}).`, link.caster and link.caster.id)
	print(`[LifeLinkService] BREAK | {cName} -> {aName} | {reason}`)
end

-- Returns a break reason, or nil if the link still holds.
local function brokenReason(link: any): string?
	local c, a = link.caster, link.ally
	if not (c and c.isAlive) then
		return `{(c and c.name) or "caster"} was KO'd`
	end
	if not (a and a.isAlive) then
		return `{(a and a.name) or "ally"} was KO'd`
	end
	if distance(c, a) > (link.maxDist or DEFAULT_MAX_DIST) then
		return "too far apart"
	end
	return nil
end

-- Make (or replace) the caster's link. Called by CommandService when Life Link resolves.
function LifeLinkService.Create(state: any, caster: any, ally: any, skillDef: any): boolean
	if not (state and caster and ally) or caster == ally or caster.id == ally.id then
		return false
	end
	if not (caster.isAlive and ally.isAlive) then
		return false
	end
	_activeState = state
	state.lifeLinks = state.lifeLinks or {}
	local old = state.lifeLinks[caster.id]
	if old then
		breakLink(state, caster.id, "replaced by a new link")
	end
	state.lifeLinks[caster.id] = {
		caster = caster,
		ally = ally,
		remainingCt = (skillDef and skillDef.lifeLinkCt) or DEFAULT_CT,
		share = (skillDef and skillDef.lifeLinkShare) or DEFAULT_SHARE,
		maxDist = (skillDef and skillDef.lifeLinkMaxDist) or DEFAULT_MAX_DIST,
	}
	BattleVisualBroadcaster.Log("buff", `{caster.name} links with {ally.name} (Life Link): {ally.name} shares {caster.name}'s healing.`, caster.id)
	print(`[LifeLinkService] LINK | {caster.name} -> {ally.name} | {state.lifeLinks[caster.id].remainingCt} CT`)
	return true
end

-- StatusService heal-gained listener. `unit` actually gained `gained` HP from any heal source.
function LifeLinkService.OnHealGained(unit: any, gained: number)
	if _sharing or not _activeState or not unit or (gained or 0) <= 0 then
		return
	end
	local state = _activeState
	local link = state.lifeLinks and state.lifeLinks[unit.id]
	if not link or link.caster ~= unit then
		return
	end
	local reason = brokenReason(link)
	if reason then
		breakLink(state, unit.id, reason)
		return
	end
	local ally = link.ally
	local share = math.max(1, math.floor(gained * (link.share or DEFAULT_SHARE)))
	local before = ally.currentHp or 0
	local maxHp = ally.maxHp or before
	if before >= maxHp then
		return  -- ally already full: nothing to gain (no overheal)
	end
	_sharing = true
	ally.currentHp = math.min(maxHp, before + share)
	_sharing = false
	-- HP bar + battle-log line ("<ally> recovers N HP (Life Link)" style, via the cause label).
	BattleVisualBroadcaster.UnitStateChanged(ally, "Life Link")
	print(`[LifeLinkService] SHARE | {unit.name} healed {gained} -> {ally.name} +{ally.currentHp - before} HP`)
end

-- Re-check every link that involves `unit` (after a knockback / forced move).
function LifeLinkService.CheckUnit(unit: any)
	local state = _activeState
	if not (state and state.lifeLinks and unit) then
		return
	end
	for casterId, link in state.lifeLinks do
		if link.caster == unit or link.ally == unit then
			local reason = brokenReason(link)
			if reason then
				breakLink(state, casterId, reason)
			end
		end
	end
end

-- CT advance hook (PulseScheduler.ProcessCtTick). Counts the 2000 CT down and re-checks KO / range.
function LifeLinkService.Tick(state: any, ctElapsed: number)
	if not state then
		return
	end
	_activeState = state
	local links = state.lifeLinks
	if not links then
		return
	end
	local ids = {}
	for casterId in links do
		table.insert(ids, casterId)
	end
	for _, casterId in ids do
		local link = links[casterId]
		if link then
			link.remainingCt = (link.remainingCt or 0) - (ctElapsed or 0)
			local reason = brokenReason(link)
			if reason then
				breakLink(state, casterId, reason)
			elseif link.remainingCt <= 0 then
				breakLink(state, casterId, "time up")
			end
		end
	end
end

return LifeLinkService
