-- BattleEvents.lua
-- CTRBLXAI | Slice 1 Visual
--
-- Creates and exposes the RemoteEvents used to broadcast
-- battle state from the server to the client.
--
-- RULE: Server fires these. Client only listens.
-- Client never fires back through these channels.
--
-- Events:
--   BattleStarted  { units }          — battle beginning, initial unit data
--   TurnStarted    { unitId, ct }     — a unit's turn has opened
--   UnitMoved      { unitId, tileX, tileY }
--   UnitActed      { actorId, actionType, targetId, damage, skillName }
--   UnitDefeated   { unitId }
--   TurnEnded      { unitId, nextRt } — unit's turn closed
--   BattleEnded    { winner }         — battle is over

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for the Remotes folder to exist (server creates it, client waits).
local function getOrCreateFolder()
	-- Server path: create it.
	-- Client path: wait for it.
	local CTRBLXAI = ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
	assert(CTRBLXAI, "BattleEvents: CTRBLXAI folder not found in ReplicatedStorage.")

	local existing = CTRBLXAI:FindFirstChild("BattleRemotes")
	if existing then return existing end

	local folder = Instance.new("Folder")
	folder.Name   = "BattleRemotes"
	folder.Parent = CTRBLXAI
	return folder
end

local remoteFolder = getOrCreateFolder()

local EVENT_NAMES = {
	"BattleStarted",
	"TurnStarted",
	"UnitMoved",
	"UnitActed",
	"UnitDefeated",
	"TurnEnded",
	"BattleEnded",
}

-- Create or retrieve each RemoteEvent.
local BattleEvents = {}

for _, name in ipairs(EVENT_NAMES) do
	local existing = remoteFolder:FindFirstChild(name)

	if existing and existing:IsA("RemoteEvent") then
		BattleEvents[name] = existing
	else
		local event   = Instance.new("RemoteEvent")
		event.Name    = name
		event.Parent  = remoteFolder
		BattleEvents[name] = event
	end
end

return BattleEvents
