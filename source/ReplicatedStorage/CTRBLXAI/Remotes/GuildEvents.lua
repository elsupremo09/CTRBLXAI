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
	"FinalizeCart",     -- ({ buys = {offerIndex}, sells = {instanceId} }) -> batch commit (cart, 2026-10-13)
	"GetDispatchBoard", -- () -> missions + unit availability
	"RequestDispatch",  -- (missionId, { unitId }) -> result
	"RecallDispatch",   -- (missionId) -> { returnedUnitIds } (2026-11-12: early return, no reward, no refund)
	"GetGuildUnits",    -- () -> unit list with level / XP / availability
	"GetParties",       -- () -> { parties, roster, maxSize }
	"SetPartyName",     -- (slot, name) -> result
	"SetPartyMembers",  -- (slot, { unitId }) -> result
	-- Parties tab (2026-11-04): create / delete / motto / emblem / background in one remote.
	"PartyAction",      -- ({ action = "Create" | "Delete" | "SetMotto" | "SetArt", id, ... }) -> result + parties
	"DevGuild",         -- Studio only: ({ action, ... }) -> { buildings, shopRefresh } (2026-10-31)
	-- Runeforge (v2 build step 4, 2026-11-01). Client sends ids only; the server prices.
	"GetRuneforge",     -- () -> level, gem storage, items with their lines and compatible gems
	"PreviewForge",     -- (instanceId, { { gem, replace? } }) -> new rarity + cost (charges nothing)
	"CheckForgeGems",   -- (instanceId, picks, candidates) -> which candidate gems the server would accept next (2026-11-06)
	"CommitForge",      -- (instanceId, { { gem, replace? } }) -> result
	-- Pay first (USER RULING 2026-11-07): the sets exist only after PayReroll.
	"GetRerollSets",    -- (instanceId) -> cost + current lines; the saved sets only once paid
	"PayReroll",        -- (instanceId) -> pays the sulfur, saves + returns the new sets
	"CommitReroll",     -- (instanceId, choice 0..N) -> closes the paid choice (0 = keep current)
	-- Gem Craft tab (USER RULING 2026-11-12 1:54 PM). Client sends gem ids + a count only.
	"CraftGems",        -- ({ action, gem?, times?, gems? }) -> spent + gained gems, gold
	-- Crucible gear merging (2026-11-02). Client sends instance IDs only; the server prices.
	"GetCrucible",      -- () -> level, inputs needed, items
	"PreviewMerge",     -- ({ instanceId }) -> result rarity, level and cost (charges nothing)
	"CommitMerge",      -- ({ instanceId }) -> the merged item (inputs destroyed)
	-- Apothecary (2026-11-03). Client sends shelf slots / ids only; the server prices.
	"GetApothecary",    -- () -> level, shelf, owned copies, refill preview, auto switch
	"CommitApothecary", -- ({ buys = { slot }, sells = { [id] = n } }) -> result
	"ApothecaryRefill", -- ({ action = "RefillNow" | "SetAuto", on? }) -> result
	-- Training Grounds card shop (2026-11-04). Client sends a shelf slot or a card id only.
	"GetCardShop",      -- () -> level, shelf, owned loose cards
	"CardShopAction",   -- ({ action = "Buy", slot } | { action = "Sell", kind, id }) -> result + state
	-- Dungeon screen (build step 5, 2026-11-13). Client sends ids only (card, units, room).
	-- Guild Hall upgrade list (Slice 8 step 1, 2026-11-16). Client sends an action + building name only.
	"BuildingAction",   -- ({ action = "List" | "Upgrade" | "Seen", building? }) -> rows, open state, message
	"FurnitureAction",  -- ({ action = "State" | "Buy" | "Place" | "Remove" | "Seen", piece?, slot?, decor? }) -> furniture state (Slice 8 step 2)
	"DungeonAction",    -- ({ action = "State" | "Start" | "Move" | "Rest" | "Treasure" | "Escape" | "Leave" | "AckResult" | "MerchantState" | "MerchantBuy" | "MerchantRefill", ... }) -> state
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
