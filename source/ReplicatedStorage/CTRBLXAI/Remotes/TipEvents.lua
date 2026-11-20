--!strict
-- TipEvents.lua
-- CTRBLXAI | New-player tips remote registry (one registry per system, like GuildEvents).
-- Server CREATES the remote; the client only WAITS for it (LOAD-001 timeouts).
--
-- One RemoteFunction, client -> server (SEC-001 / SEC-002): the client sends an action and,
-- for "Seen", a tip id only. The server checks the id against TipData and rate-limits writes.
--   TipAction({ action = "State" })                 -> { ok, seen = { id }, off, pending = { id } }
--   TipAction({ action = "Seen", id = "TIP-QB-01" }) -> { ok }
--   TipAction({ action = "SetOff", off = boolean })   -> { ok, off }

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "TipRemotes"
local WAIT_TIMEOUT = 30 -- LOAD-001 timeout; the server creates this early in boot (Main)

local FUNCTION_NAMES = table.freeze({
	"TipAction",
})

local TipEvents = {}

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
		warn("[TipEvents] TipRemotes folder not found (server did not create it in time)")
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
		warn(`[TipEvents] Remote {name} not found within {WAIT_TIMEOUT}s`)
	end
	return found
end

for _, name in FUNCTION_NAMES do
	(TipEvents :: any)[name] = resolve(name, "RemoteFunction")
end

return TipEvents
