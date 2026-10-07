--!strict
-- GuildEvents.lua
-- CTRBLXAI | Slice 6 — temporary Guild menu (game_flow id 23 "Town: first version")
--
-- Remote registry for the Guild menu ONLY (one registry per system; BattleEvents
-- stays the battle registry). Server CREATES the remotes; the client only WAITS for
-- them (with timeouts, LOAD-001) and never creates its own copies, so a client that
-- loads before the server cannot end up talking to a client-only remote.
--
-- Direction rules (SEC-001 / SEC-002 / ARC-001):
--   Server -> Client RemoteEvents are FACTS ("the menu opened", "it closed").
--   Client -> Server RemoteFunctions are INTENTIONS or read-only queries. The client
--   sends ids only (candidateId, offerIndex, instanceId, missionId, unitIds) — never
--   prices, costs or results. Every handler re-validates and re-prices on the server.
--
-- Leaving the menu reuses the EXISTING BattleEvents.StartBattle intention (the same
-- signal the old Loadout Hub used), so Main.server.lua's wait points are unchanged.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "GuildRemotes"
local WAIT_TIMEOUT = 10 -- seconds (LOAD-001: client WaitForChild must time out)

-- Server -> Client facts
local EVENT_NAMES = table.freeze({
	"GuildMenuOpened", -- { phase = "PreBattle" | "PostBattle" }
	"GuildMenuClosed", -- {}
})

-- Client -> Server queries / intentions (RemoteFunction: client invokes, server answers)
local FUNCTION_NAMES = table.freeze({
	"GetGuildOverview", -- () -> overview (gold, materials, building levels, phase)
	"GetTavernPool",    -- () -> recruit candidates
	"RequestHire",      -- (candidateId) -> result
	"GetMerchantStock", -- () -> stock + sellable items
	"RequestBuy",       -- (offerIndex) -> result
	"RequestSell",      -- (instanceId) -> result
	"GetBlacksmithItems", -- () -> items with next-level cost
	"RequestUpgrade",   -- (instanceId) -> result (+1 level)
	"RequestDowngrade", -- (instanceId) -> result (-1 level)
	"GetDispatchBoard", -- () -> missions + unit availability
	"RequestDispatch",  -- (missionId, { unitId }) -> result
	"GetGuildUnits",    -- () -> unit list with level / XP / availability
})

local GuildEvents = {}

local folder: Instance?
if RunService:IsServer() then
	local root = ReplicatedStorage:WaitForChild("CTRBLXAI")
	local existing = root:FindFirstChild(FOLDER_NAME)
	if existing then
		folder = existing
	else
		local f = Instance.new("Folder")
		f.Name = FOLDER_NAME
		f.Parent = root
		folder = f
	end
else
	local root = ReplicatedStorage:WaitForChild("CTRBLXAI", WAIT_TIMEOUT)
	folder = root and root:WaitForChild(FOLDER_NAME, WAIT_TIMEOUT) or nil
	if not folder then
		warn("[GuildEvents] GuildRemotes folder not found (server did not create it in time)")
	end
end

local function resolve(name: string, className: string): Instance?
	if not folder then return nil end
	if RunService:IsServer() then
		local existing = folder:FindFirstChild(name)
		if existing and existing:IsA(className) then return existing end
		local inst = Instance.new(className)
		inst.Name = name
		inst.Parent = folder -- NET-004: properties set before Parent
		return inst
	end
	local found = folder:WaitForChild(name, WAIT_TIMEOUT)
	if not found then
		warn(`[GuildEvents] Remote {name} not found within {WAIT_TIMEOUT}s`)
	end
	return found
end

for _, name in EVENT_NAMES do
	(GuildEvents :: any)[name] = resolve(name, "RemoteEvent")
end
for _, name in FUNCTION_NAMES do
	(GuildEvents :: any)[name] = resolve(name, "RemoteFunction")
end

return GuildEvents
