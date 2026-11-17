--!strict
-- FeedbackEvents.lua
-- CTRBLXAI | Feedback / bug report remotes (user rulings 2026-11-17 4:01-4:38 PM).
--
-- One registry per system (same pattern as GuildEvents): the SERVER creates the remotes, the
-- client only waits for them (with a timeout, LOAD-001) and never creates its own copies.
--
-- Direction (SEC-001 / SEC-002): the client sends an INTENTION { category, text, context };
-- the server validates every field, applies the rate limit and adds its own context.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "FeedbackRemotes"
local WAIT_TIMEOUT = 10 -- seconds (LOAD-001)

local FUNCTION_NAMES = table.freeze({
	"SubmitFeedback", -- ({ category, text, context }) -> { code = "ok" | "empty" | "cooldown" | "failed", wait? }
})

local FeedbackEvents = {}

local folder: Instance? = nil
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		folder = existing
	else
		local f = Instance.new("Folder")
		f.Name = FOLDER_NAME
		f.Parent = ReplicatedStorage -- NET-004: properties set before Parent
		folder = f
	end
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, WAIT_TIMEOUT)
	if not folder then
		warn(`[FeedbackEvents] Folder {FOLDER_NAME} not found within {WAIT_TIMEOUT}s`)
	end
end

local function resolve(name: string, className: string): Instance?
	if not folder then return nil end
	if RunService:IsServer() then
		local existing = folder:FindFirstChild(name)
		if existing and existing:IsA(className) then return existing end
		local inst = Instance.new(className)
		inst.Name = name
		inst.Parent = folder
		return inst
	end
	local found = folder:WaitForChild(name, WAIT_TIMEOUT)
	if not found then
		warn(`[FeedbackEvents] Remote {name} not found within {WAIT_TIMEOUT}s`)
	end
	return found
end

for _, name in FUNCTION_NAMES do
	(FeedbackEvents :: any)[name] = resolve(name, "RemoteFunction")
end

return FeedbackEvents
