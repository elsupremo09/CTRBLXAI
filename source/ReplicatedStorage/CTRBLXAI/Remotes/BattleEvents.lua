-- BattleEvents.lua
-- CTRBLXAI | Slice 3
--
-- Creates and exposes RemoteEvents for battle communication.
--
-- Server → Client (FireAllClients / FireClient):
--   BattleStarted, TurnStarted, UnitMoved, UnitActed, UnitDefeated,
--   TurnEnded, BattleEnded, StatusApplied, StatusExpired,
--   DotDamage, SkillCardData, TargetHighlight, HealingApplied,
--   PlayerTurnPrompt (tells client it's their turn with available actions)
--
-- Client → Server (FireServer):
--   PlayerCommand (player sends their chosen action)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function getOrCreateFolder()
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
	"StatusApplied",
	"StatusExpired",
	"DotDamage",
	"SkillCardData",
	"TargetHighlight",
	"HealingApplied",
	-- Player input (Slice 3)
	"PlayerTurnPrompt",
	"PlayerCommand",
	"TurnOrderUpdate",
	-- Slice 4A
	"ChannelFizzled",
	"GuardActivated",
	"UnitPushed",
	-- Unit Inspector (3-tab)
	"InspectUnitRequest",
	"InspectUnitResponse",
	-- Phase 2: Status expansion
	"TurnSkipped",
	"StatusImmune",
	-- Dev tools (Studio only)
	"DevCommand",
	-- Slice 4D: Management contracts
	"RewardScreen",       -- S->C: reward summaries after victory
	"RewardContinue",     -- C->S: player acknowledged rewards
	"LoadoutHubOpen",     -- S->C: tells client to show loadout hub
	"StartBattle",        -- C->S: player ready to fight
	-- Tile effects (Slice 3: TileEffectService)
	"TileEffectApplied",  -- S->C: effect placed on tile
	"TileEffectRemoved",  -- S->C: effect removed from tile
}

-- RemoteFunctions for Slice 4D management contracts
local FUNCTION_NAMES = {
	"GetRosterData",
	"GetInventoryData",
	"RequestEquip",
	"RequestUnequip",
}

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

for _, name in ipairs(FUNCTION_NAMES) do
	local existing = remoteFolder:FindFirstChild(name)

	if existing and existing:IsA("RemoteFunction") then
		BattleEvents[name] = existing
	else
		local fn = Instance.new("RemoteFunction")
		fn.Name   = name
		fn.Parent = remoteFolder
		BattleEvents[name] = fn
	end
end

return BattleEvents
