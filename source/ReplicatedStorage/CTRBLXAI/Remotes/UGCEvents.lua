--!strict
-- UGCEvents.lua
-- CTRBLXAI | UGC Rental & Ownership — remote registry (one registry per system,
-- same pattern as GuildEvents). The server CREATES the remotes; the client only
-- WAITS for them with timeouts (LOAD-001) and never creates its own copies.
--
-- Direction rules (SEC-001 / SEC-002 / ARC-001):
--   Server -> Client RemoteEvents are FACTS ("these items changed").
--   Client -> Server RemoteFunctions are INTENTIONS or read-only queries. The
--   client sends ids only (assetId, unitId, slot, vote, isMarked) — never prices,
--   ownership or results. UGCRemoteHandler re-validates everything server-side.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "UGCRemotes"
local WAIT_TIMEOUT = 10 -- seconds (LOAD-001)

-- Server -> Client facts
local EVENT_NAMES = table.freeze({
	"UGCStateChanged", -- { reason = "purchased" | "expired", assetIds = { number } }
})

-- Client -> Server queries / intentions
local FUNCTION_NAMES = table.freeze({
	"GetUGCView",         -- (unitId?) -> catalog view for the Customize screen / UGC merchant
	"GetUnitWornUGC",     -- (unitId) -> items a unit is wearing (inspector "worn items" list)
	"RequestUGCTrial",    -- (assetId) -> result
	"RequestUGCRent",     -- (assetId) -> result (server prices it)
	"RequestUGCEquip",    -- (unitId, assetId) -> result
	"RequestUGCUnequip",  -- (unitId, slot) -> result
	"RequestUGCWishlist", -- (assetId, isMarked) -> result
	"RequestUGCRate",     -- (assetId, vote: 1 | 0 | -1) -> result
	"RequestUGCPurchase", -- (assetId) -> result (server calls PromptPurchase)
})

local UGCEvents = {}

local folder: Instance?
if RunService:IsServer() then
	local root = ReplicatedStorage:WaitForChild("CTRBLXAI")
	local existing = root:FindFirstChild(FOLDER_NAME)
	if existing then
		folder = existing
	else
		local f = Instance.new("Folder")
		f.Name = FOLDER_NAME
		f.Parent = root -- NET-004: properties before Parent
		folder = f
	end
else
	local root = ReplicatedStorage:WaitForChild("CTRBLXAI", WAIT_TIMEOUT)
	folder = root and root:WaitForChild(FOLDER_NAME, WAIT_TIMEOUT) or nil
	if not folder then
		warn("[UGCEvents] UGCRemotes folder not found (server did not create it in time)")
	end
end

local function resolve(name: string, className: string): Instance?
	if not folder then return nil end
	if RunService:IsServer() then
		local existing = folder:FindFirstChild(name)
		if existing and existing:IsA(className) then return existing end
		local inst = Instance.new(className)
		inst.Name = name
		inst.Parent = folder -- NET-004
		return inst
	end
	local found = folder:WaitForChild(name, WAIT_TIMEOUT)
	if not found then
		warn(`[UGCEvents] Remote {name} not found within {WAIT_TIMEOUT}s`)
	end
	return found
end

for _, name in EVENT_NAMES do
	(UGCEvents :: any)[name] = resolve(name, "RemoteEvent")
end
for _, name in FUNCTION_NAMES do
	(UGCEvents :: any)[name] = resolve(name, "RemoteFunction")
end

return UGCEvents
