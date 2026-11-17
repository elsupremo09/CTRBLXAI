--!strict
-- FeedbackService.lua
-- CTRBLXAI | In-game feedback / bug reports (user rulings 2026-11-17 4:01-4:38 PM).
--
-- The always-on Feedback button (Feedback.client.lua) sends { category, text, context }.
-- This service:
--   * validates every field (SEC-001): category in a fixed set, text 1..500 characters after
--     trimming, client context only as short capped strings;
--   * rate-limits on the SERVER: one report per 60 s per player;
--   * adds its own context (Rank, quest, dungeon run, battle state, place version, time);
--   * stores each report in its own DataStore "CTRBLXAI_Feedback" (never in a player save),
--     key "report_<time>_<userId>_<n>", plus a per-day index list "index_<YYYYMMDD>".
--     Studio sessions use a "dev_" key prefix so test reports stay apart from live ones.
--   * test-guard / memory mode: the report is NOT stored (answers ok + warn), so Studio tests
--     never write DataStores.
-- Answers { code = "ok" | "empty" | "cooldown" | "failed", wait = seconds? }; the client maps the
-- code to the approved lines.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ServerScriptService:WaitForChild("Game")
local SaveService = require(Game:WaitForChild("SaveService"))
local FeedbackEvents: any = require(ReplicatedStorage:WaitForChild("CTRBLXAI"):WaitForChild("Remotes"):WaitForChild("FeedbackEvents"))

local FeedbackService = {}

local STORE_NAME = "CTRBLXAI_Feedback"
local MAX_TEXT = 500          -- characters (approved '{n} / 500')
local COOLDOWN = 60           -- seconds per player, server side
local MAX_LOG_LINES = 5       -- client error / warning lines kept
local MAX_LOG_LEN = 200       -- characters per log line
local MAX_SHORT = 80          -- characters for screen / device / viewport strings
local MAX_SCREENS = 8
local MAX_INDEX = 2000        -- keys kept per day index
local RETRIES = 3
local CATEGORIES = table.freeze({ Bug = true, Suggestion = true, Other = true })

type Ctx = {
	playerId: string?,
	getRank: (() -> any)?,
	getQuest: (() -> any)?,
	getDungeon: (() -> any)?,
	isBattleRunning: (() -> boolean)?,
}

local ctx: Ctx = {}
local lastSent: { [number]: number } = {}
local seq = 0
local store: any = nil

-- Text helpers ---------------------------------------------------------------

-- Keep printable text; newlines/tabs become spaces unless keepLines.
local function clean(s: string, keepLines: boolean): string
	s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
	if keepLines then
		s = s:gsub("[\0-\9\11-\31\127]", "")
	else
		s = s:gsub("[\0-\31\127]", " ")
	end
	return s
end

local function trim(s: string): string
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Cut to n characters (UTF-8 safe). Returns nil for invalid UTF-8.
local function cut(s: string, n: number): string?
	local len = utf8.len(s)
	if not len then return nil end
	if len <= n then return s end
	local stop = utf8.offset(s, n + 1)
	return if stop then s:sub(1, stop - 1) else s
end

local function shortStr(v: any, n: number): string?
	if type(v) ~= "string" then return nil end
	local s = cut(trim(clean(v, false)), n)
	if s == nil or s == "" then return nil end
	return s
end

-- Client context: only known fields, each type-checked and capped.
local function readClientContext(raw: any): { [string]: any }
	local out: { [string]: any } = {}
	if type(raw) ~= "table" then return out end
	out.screen = shortStr(raw.screen, MAX_SHORT)
	out.device = shortStr(raw.device, MAX_SHORT)
	out.viewport = shortStr(raw.viewport, MAX_SHORT)
	if type(raw.screens) == "table" then
		local list = {}
		for i = 1, math.min(#raw.screens, MAX_SCREENS) do
			local s = shortStr(raw.screens[i], MAX_SHORT)
			if s then table.insert(list, s) end
		end
		out.screens = list
	end
	if type(raw.errors) == "table" then
		local list = {}
		for i = 1, math.min(#raw.errors, MAX_LOG_LINES) do
			local s = shortStr(raw.errors[i], MAX_LOG_LEN)
			if s then table.insert(list, s) end
		end
		out.errors = list
	end
	return out
end

-- Server context: primitive values only, every getter guarded.
local function primitives(t: any, maxKeys: number): { [string]: any }?
	if type(t) ~= "table" then return nil end
	local out: { [string]: any } = {}
	local n = 0
	for k, v in t do
		if n >= maxKeys then break end
		local tv = type(v)
		if type(k) == "string" and (tv == "number" or tv == "boolean" or tv == "string") then
			out[k] = if tv == "string" then cut(v, MAX_SHORT) else v
			n += 1
		end
	end
	return out
end

local function guarded(fn: (() -> any)?): any
	if not fn then return nil end
	local ok, v = pcall(fn)
	return if ok then v else nil
end

local function serverContext(player: Player): { [string]: any }
	local quest = guarded(ctx.getQuest)
	return {
		userId = player.UserId,
		playerId = ctx.playerId,
		rank = guarded(ctx.getRank),
		quest = primitives(quest, 8),
		dungeon = primitives(guarded(ctx.getDungeon), 16),
		battleRunning = guarded(ctx.isBattleRunning) == true,
		saveMode = SaveService.GetMode(),
		placeVersion = game.PlaceVersion,
		placeId = game.PlaceId,
		jobId = game.JobId,
		time = os.time(),
	}
end

-- Storage ----------------------------------------------------------------------

local function getStore(): any
	if store then return store end
	local ok, s = pcall(function() return DataStoreService:GetDataStore(STORE_NAME) end)
	if ok then store = s end
	return store
end

local function retry(fn: () -> ()): boolean
	for attempt = 1, RETRIES do
		local ok, err = pcall(fn)
		if ok then return true end
		warn(`[FeedbackService] DataStore attempt {attempt}/{RETRIES} failed: {tostring(err)}`)
		if attempt < RETRIES then task.wait(attempt) end
	end
	return false
end

local function storeReport(report: { [string]: any }): boolean
	local ds = getStore()
	if not ds then
		warn("[FeedbackService] DataStore unavailable")
		return false
	end
	local prefix = if SaveService.GetMode() == "studio" then "dev_" else ""
	seq += 1
	local key = `{prefix}report_{report.server.time}_{report.server.userId}_{seq}`
	if not retry(function() ds:SetAsync(key, report) end) then
		return false
	end
	-- Day index: a missing index entry never fails the report itself.
	local day = `{prefix}index_{os.date("!%Y%m%d", report.server.time)}`
	local indexed = retry(function()
		ds:UpdateAsync(day, function(old: any)
			local list = if type(old) == "table" then old else {}
			if #list >= MAX_INDEX then table.remove(list, 1) end
			table.insert(list, key)
			return list
		end)
	end)
	if not indexed then
		warn(`[FeedbackService] Stored {key} but could not add it to {day}`)
	end
	print(`[FeedbackService] Stored {key} ({report.category})`)
	return true
end

-- Remote ---------------------------------------------------------------------------

local function onSubmit(player: Player, payload: any): { [string]: any }
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return { code = "failed" }
	end
	if type(payload) ~= "table" then return { code = "failed" } end
	local category = payload.category
	if type(category) ~= "string" or not CATEGORIES[category] then
		return { code = "failed" }
	end
	if type(payload.text) ~= "string" or #payload.text > MAX_TEXT * 4 + 64 then
		return { code = "failed" }
	end
	local text = trim(clean(payload.text, true))
	local len = utf8.len(text)
	if len == nil then return { code = "failed" } end
	if len == 0 then return { code = "empty" } end
	if len > MAX_TEXT then return { code = "failed" } end

	local now = os.clock()
	local last = lastSent[player.UserId]
	if last and now - last < COOLDOWN then
		return { code = "cooldown", wait = math.max(1, math.ceil(COOLDOWN - (now - last))) }
	end
	lastSent[player.UserId] = now -- set before storing, so a second fast call waits

	local report = {
		category = category,
		text = text,
		client = readClientContext(payload.context),
		server = serverContext(player),
	}

	if SaveService.GetMode() == "memory" then
		warn(`[FeedbackService] Memory / test-guard mode: {category} report not stored ({len} chars)`)
		return { code = "ok" }
	end

	if storeReport(report) then
		return { code = "ok" }
	end
	lastSent[player.UserId] = nil -- failed: the player may try again at once
	return { code = "failed" }
end

function FeedbackService.Init(c: Ctx)
	ctx = c or {}
	local remote = FeedbackEvents.SubmitFeedback
	if not remote then
		warn("[FeedbackService] SubmitFeedback remote missing")
		return
	end
	remote.OnServerInvoke = function(player: Player, payload: any)
		local ok, res = pcall(onSubmit, player, payload)
		if ok then return res end
		warn(`[FeedbackService] Submit error: {tostring(res)}`)
		return { code = "failed" }
	end
	Players.PlayerRemoving:Connect(function(p: Player)
		lastSent[p.UserId] = nil
	end)
	print("[FeedbackService] Initialized")
end

return FeedbackService
