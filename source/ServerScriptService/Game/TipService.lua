--!strict
-- TipService.lua
-- CTRBLXAI | New-player tips, server side (new_player_tips SYS-01..10, save_data_contract SAVE-01).
--
-- OWNS: which tips each player has seen and the "Show tips" setting. Server-authoritative
-- (NET-001 / SEC-001): the client asks for its state and reports a tip it showed; this module
-- checks every id against TipData, rate-limits writes and keeps the only real copy.
--
-- Save (SAVE-01, Key 3 Progression, rides Main's doSave -- SaveService untouched):
--   progression.tips    = { "TIP-QB-01", ... }  seen ids only, no text
--   progression.tipsOff = boolean               default false = tips ON
-- Load: duplicates removed, unknown ids dropped. No list on an OLD save, or a broken list,
-- runs the one-time old-save update (SYS-09): every tip whose trigger the player is already past
-- counts as seen, so an update never floods a veteran. A broken entry never blocks the load.
-- Building-unlock tips are pulled, not pushed: State lists open buildings whose tip is unseen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CTRBLXAI = ReplicatedStorage:WaitForChild("CTRBLXAI")
local TipData = require(CTRBLXAI:WaitForChild("Shared"):WaitForChild("TipData"))
local TipEvents: any = require(CTRBLXAI:WaitForChild("Remotes"):WaitForChild("TipEvents"))
local BuildingService = require(script.Parent:WaitForChild("BuildingService"))

local TipService = {}

local RATE_LIMIT_SECONDS = 0.15 -- SEC-001: writes ("Seen" / "SetOff") per player
local STARTER_ROSTER = 3 -- Hero, Mage, Ranger (unit_progression 107): more than this = the player has hired

type State = {
	seen: { [string]: boolean },
	order: { string },
	off: boolean,
	migrate: boolean,
}

type Deps = {
	getPlayerId: (plr: Player) -> string?,
	markDirty: (() -> ())?,       -- tip changes ride the next guild save / save-on-quit (BUG-030/066 kept)
	getBattles: (() -> number)?,  -- battles completed (GuildMenuService), for the SYS-09 migration
	getRosterCount: (() -> number)?,
}

local deps: Deps? = nil
local states: { [string]: State } = {}
local lastWriteAt: { [number]: number } = {}

local function fresh(): State
	return { seen = {}, order = {}, off = false, migrate = false }
end

local function stateOf(playerId: string): State
	local s = states[playerId]
	if not s then
		s = fresh()
		states[playerId] = s
	end
	return s
end

local function add(s: State, id: any): boolean
	if not TipData.IsKnown(id) or s.seen[id] then return false end
	s.seen[id] = true
	table.insert(s.order, id)
	return true
end

-- { [buildingName] = { open = bool, ... } } from BuildingService; {} if it is not ready.
local function openBuildings(): { [string]: any }
	local ok, res = pcall(BuildingService.OpenState)
	if ok and type(res) == "table" then return res end
	return {}
end

local function isBuildingOpen(open: { [string]: any }, name: string): boolean
	local b = open[name]
	return type(b) == "table" and b.open == true
end

local function dirty()
	local d = deps
	if d and d.markDirty then
		local ok, err = pcall(d.markDirty)
		if not ok then warn("[TipService] markDirty failed: " .. tostring(err)) end
	end
end

local function readCount(fn: (() -> number)?): number
	if not fn then return 0 end
	local ok, n = pcall(fn)
	return if ok and type(n) == "number" then n else 0
end

-- SYS-09: old save -> mark seen only what the player is really past (Tester W2):
--   Town tips: a building tip only once that building is open; the starting town tips always.
--   Battle tips: only if the save shows a battle was completed.
--   Unit tips: only if the player has hired past the starter roster or completed a battle.
-- Anything not past stays unseen and shows the first time the player meets it.
local function runMigration(s: State)
	if not s.migrate then return end
	s.migrate = false
	local d = deps
	local battles = readCount(d and d.getBattles)
	local roster = readCount(d and d.getRosterCount)
	local open = openBuildings()
	local n = 0
	for _, tip in TipData.List do
		local b = tip.building
		local past: boolean
		if tip.group == "Battle" then
			past = battles >= 1
		elseif tip.group == "Unit" then
			past = roster > STARTER_ROSTER or battles >= 1
		else
			past = b == nil or isBuildingOpen(open, b)
		end
		if past and add(s, tip.id) then n += 1 end
	end
	print(`[TipService] Old save: {n} tips marked as already seen (SYS-09; battles {battles}, roster {roster})`)
	if n > 0 then dirty() end
end

local function pendingUnlocks(s: State): { string }
	local out: { string } = {}
	local open = openBuildings()
	for _, tip in TipData.List do
		local b = tip.building
		if b and not s.seen[tip.id] and isBuildingOpen(open, b) then
			table.insert(out, tip.id)
		end
	end
	return out
end

--------------------------------------------------
-- SAVE / LOAD (called by Main)
--------------------------------------------------

--- savedTips / savedOff: progression.tips / progression.tipsOff (nil on a new player).
--- isOldSave: a save was loaded (an old save without a tips list migrates once).
function TipService.Import(playerId: string, savedTips: any, savedOff: any, isOldSave: boolean)
	local s = fresh()
	if type(savedTips) == "table" then
		local entries = 0
		local ok = pcall(function()
			for _, id in ipairs(savedTips) do
				entries += 1
				add(s, id) -- dedupe + unknown ids dropped
			end
		end)
		-- Broken list, or a list where every id is unknown (Tester W1): reset to the migration (SAVE-01).
		if not ok or (entries > 0 and #s.order == 0) then
			s = fresh()
			s.migrate = true
		end
	elseif savedTips ~= nil or isOldSave then
		s.migrate = true -- broken entry or old save: SYS-09
	end
	s.off = savedOff == true -- missing / broken = tips ON
	states[playerId] = s
end

function TipService.ExportSeen(playerId: string): { string }
	local s = stateOf(playerId)
	runMigration(s)
	return table.clone(s.order)
end

function TipService.ExportOff(playerId: string): boolean
	return stateOf(playerId).off
end

--------------------------------------------------
-- REMOTE
--------------------------------------------------

local function handle(plr: Player, req: any): any
	local d = deps
	if not d then return nil end
	local playerId = d.getPlayerId(plr)
	if not playerId or type(req) ~= "table" then return nil end
	local action = req.action
	if action ~= "State" then
		local now = os.clock()
		local last = lastWriteAt[plr.UserId]
		if last and now - last < RATE_LIMIT_SECONDS then
			return { ok = false, reason = "busy" }
		end
		lastWriteAt[plr.UserId] = now
	end
	local s = stateOf(playerId)
	runMigration(s)
	if action == "State" then
		return { ok = true, seen = table.clone(s.order), off = s.off, pending = pendingUnlocks(s) }
	elseif action == "Seen" then
		if not TipData.IsKnown(req.id) then return { ok = false, reason = "unknown tip" } end
		if add(s, req.id) then dirty() end
		return { ok = true }
	elseif action == "SetOff" then
		if type(req.off) ~= "boolean" then return { ok = false, reason = "bad value" } end
		if s.off ~= req.off then dirty() end
		s.off = req.off
		return { ok = true, off = s.off }
	end
	return { ok = false, reason = "unknown action" }
end

function TipService.Init(d: Deps)
	deps = d
	local remote = TipEvents.TipAction
	if not remote then
		warn("[TipService] TipAction remote missing -- tips disabled")
		return
	end
	remote.OnServerInvoke = function(plr: Player, req: any)
		local ok, res = pcall(handle, plr, req)
		if not ok then
			warn("[TipService] TipAction failed: " .. tostring(res))
			return nil
		end
		return res
	end
	Players.PlayerRemoving:Connect(function(plr: Player)
		lastWriteAt[plr.UserId] = nil -- seen state stays until the quit save has run
	end)
end

return TipService
