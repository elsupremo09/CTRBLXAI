--!strict
-- DiscoveryService.lua
-- CTRBLXAI | Discovery Radius reveal (server-only). Built 2026-10-28.
--
-- DB loot_progression "LUK Fortune Discovery" rows 4-7 (authoritative):
--   Radius   = 1 + floor(LUK / 60) + bonuses - penalties, minimum 1 (computed into
--              derivedStats.discoveryRadius by GameConstants + EquipmentService).
--   Shape    = square (Chebyshev) radius; ignores LoS, elevation, walls, blockers, facing.
--   Triggers = initial deployment; beginning of a ready turn; after Move, Push, Pull,
--              Knockback, collision, teleport, blink or swap finishes. Checks the FINAL
--              occupied tile only; both swapped units trigger.
--   Targets  = hidden units, traps, treasure, hazards, switches, concealed objects.
--              Reveals to the allied team. Hidden + Undiscoverable ignores Discovery.
--
-- Rulings:
--   * User 2026-10-28: Discovery does NOT unmask a disguised Mimic. Only interact /
--     attack or a dedicated reveal effect does. ObjectEffectService.RevealObject only
--     clears `hidden`; it never unmasks, so a hidden Mimic is drawn still disguised.
--   * Object `hidden` means "hidden from the player". So only PLAYER-side units reveal
--     objects; an enemy's Discovery must never show the player anything. Hide removal is
--     symmetric: any unit strips Hide from units of a different side in its radius.
--
-- Movement triggers are detected by tile change since each unit's last check
-- (CheckMoved), run after every committed command and after every clock advance, so
-- every displacement path is covered without hooking each one individually.

local StatusService = require(script.Parent.StatusService)
local ObjectEffectService = require(script.Parent.ObjectEffectService)
local BattleVisualBroadcaster = require(script.Parent.BattleVisualBroadcaster)

local DiscoveryService = {}

local PLAYER_SIDE = "Player"

local function tileKey(u: any): string?
	if u and u.tileX and u.tileY then
		return `{u.tileX},{u.tileY}`
	end
	return nil
end

local function hasTag(tags: any, tag: string): boolean
	if type(tags) ~= "table" then
		return false
	end
	for _, t in tags do
		if t == tag then
			return true
		end
	end
	return false
end

-- DB row 7: Hidden + Undiscoverable ignores normal Discovery (needs another reveal path).
local function isUndiscoverable(x: any): boolean
	return x.undiscoverable == true or hasTag(x.tags, "Undiscoverable")
end

-- Whole tiles, minimum 1. Falls back to the base formula for units whose stats were
-- not rebuilt through EquipmentService (e.g. some spawned units).
function DiscoveryService.GetRadius(unit: any): number
	local r = unit and unit.derivedStats and unit.derivedStats.discoveryRadius
	if type(r) ~= "number" then
		local luk = (unit and unit.effectiveStats and unit.effectiveStats.LUK) or 0
		r = 1 + math.floor(luk / 60)
	end
	return math.max(1, math.floor(r + 0.5))
end

-- Run one Discovery check from `unit`'s current tile. Returns how many things it revealed.
-- radiusOverride (optional, 2026-10-29): HD-019 Oracle Diadem's wider reveal on Interact.
function DiscoveryService.RunForUnit(state: any, unit: any, radiusOverride: number?): number
	if not (state and unit and unit.isAlive) then
		return 0
	end
	local key = tileKey(unit)
	if not key then
		return 0
	end
	unit._discoveryLastTile = key

	local r = radiusOverride or DiscoveryService.GetRadius(unit)
	local ux: number, uy: number = unit.tileX, unit.tileY
	local found = 0

	-- Hidden units of any other side lose Hide.
	for _, u in state.units or {} do
		if u ~= unit and u.isAlive and u.tileX and u.tileY and u.side ~= unit.side
			and math.max(math.abs(u.tileX - ux), math.abs(u.tileY - uy)) <= r
			and not isUndiscoverable(u)
			and StatusService.HasStatus(u, "Hide") then
			StatusService.RemoveStatus(u, "Hide")
			BattleVisualBroadcaster.StatusExpired(u, "Hide")
			BattleVisualBroadcaster.UnitStateChanged(u)
			BattleVisualBroadcaster.Log("info", `{unit.name} spotted {u.name}.`, unit.id)
			print(`[DiscoveryService] {unit.name} (r={r}) spotted hidden {u.name}`)
			found += 1
		end
	end

	-- Hidden objects: player side only (see header). Own-side objects are skipped.
	if unit.side == PLAYER_SIDE and state.objects then
		for _, o in state.objects do
			if o.hidden and o.x and o.y and o.ownerSide ~= unit.side
				and math.max(math.abs(o.x - ux), math.abs(o.y - uy)) <= r
				and not isUndiscoverable(o) then
				if ObjectEffectService.RevealObject(o) then
					local shown = ObjectEffectService.GetDisplayType(o) or "object"
					BattleVisualBroadcaster.Log("info", `{unit.name} discovered a hidden {shown}.`, unit.id)
					print(`[DiscoveryService] {unit.name} (r={r}) discovered hidden {shown} at ({o.x},{o.y})`)
					found += 1
				end
			end
		end
	end

	return found
end

-- Initial deployment: every living unit checks once.
function DiscoveryService.RunForAll(state: any): number
	if not (state and state.units) then
		return 0
	end
	local total = 0
	for _, u in state.units do
		if u.isAlive then
			total += DiscoveryService.RunForUnit(state, u)
		end
	end
	return total
end

-- Any living unit whose tile changed since its last check runs a check from its new tile.
-- Units are collected first, then checked, so the order of reveals cannot matter.
function DiscoveryService.CheckMoved(state: any): number
	if not (state and state.units) then
		return 0
	end
	local moved = {}
	for _, u in state.units do
		if u.isAlive then
			local key = tileKey(u)
			if key and u._discoveryLastTile ~= key then
				table.insert(moved, u)
			end
		end
	end
	local total = 0
	for _, u in moved do
		total += DiscoveryService.RunForUnit(state, u)
	end
	return total
end

return DiscoveryService
