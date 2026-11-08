--!strict
-- DevAccess.lua (2026-11-06, user ruling): ONE server-side gate for every dev tool
-- (DevCommand remote, DevGuild remote, Test Arena pin, dev god mode).
--   Allowed = running in Roblox Studio, OR the player's UserId is in OWNER_USER_IDS.
-- Server-authoritative (SEC-002 / ARC-003): this module lives in ServerScriptService, every
-- dev request is re-checked here per call, and the client only SHOWS dev panels when the
-- server marks the player with the "DevAccess" attribute (display only, never trusted).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DevAccess = {}

DevAccess.ATTRIBUTE = "DevAccess"

-- REMOVE BEFORE PUBLIC LAUNCH: owner accounts that get dev tools in the PUBLISHED game.
local OWNER_USER_IDS: { [number]: boolean } = {
	[11665436356] = true, -- El_Pi0818 (game owner, user ruling 2026-11-06; read from Studio)
}

-- True if this player may use dev tools. Studio: always. Published game: allow-list only.
function DevAccess.IsAllowed(player: any): boolean
	if RunService:IsStudio() then
		return true
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	return OWNER_USER_IDS[player.UserId] == true
end

-- True if server-wide dev features (Test Arena pin, dev god mode) may run: Studio, or EVERY
-- player in the server is allowed. If anyone else joins, these features switch off.
function DevAccess.SessionAllowed(): boolean
	if RunService:IsStudio() then
		return true
	end
	local players = Players:GetPlayers()
	if #players == 0 then
		return false
	end
	for _, p in players do
		if not DevAccess.IsAllowed(p) then
			return false
		end
	end
	return true
end

-- Mark each player for the client (display only; the server re-checks every request).
local function mark(p: Player)
	p:SetAttribute(DevAccess.ATTRIBUTE, DevAccess.IsAllowed(p))
end
if RunService:IsServer() then
	Players.PlayerAdded:Connect(mark)
	for _, p in Players:GetPlayers() do
		mark(p)
	end
end

return DevAccess
