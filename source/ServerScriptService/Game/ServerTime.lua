--!strict
-- ServerTime.lua
-- CTRBLXAI | shared server clock for real-time features (real-time Dispatch build step 1, 2026-11-19).
--
-- SERVER ONLY (lives in ServerScriptService, so clients cannot require it). Every real-time
-- rule (Dispatch earning, save lock) reads time from here, never from a client value
-- (SEC-002: the client never decides game state). os.time() is UTC seconds on the server.
--
-- Rules (unit_progression 77, 2026-11-19): earned time = min(now - lastCollectAt, limit),
-- never negative; a corrupt or future timestamp from a save is clamped, never trusted.
--
-- Step 5 (2026-11-19): a dev offset for the Studio fast-forward tool (DevTools TIME group).

local ServerTime = {}

-- Dev fast-forward (real-time Dispatch step 5, 2026-11-19). Memory only, never saved, starts at 0
-- on every server. Only the DevGuild dev handler changes it, and that handler checks
-- DevAccess.IsAllowed (Studio, or an allow-listed owner) on every call (SEC-001/002).
local DEV_OFFSET_MAX = 30 * 24 * 3600 -- 30 days
local devOffset = 0

-- Current server time, whole UTC seconds (+ the dev offset, 0 outside dev tests).
function ServerTime.Now(): number
	return os.time() + devOffset
end

-- Dev only: move the clock forward by `seconds` (0 .. 30 days in total). Returns the new offset.
function ServerTime.AddDevOffset(seconds: any): number
	local s = tonumber(seconds)
	if s == nil or s ~= s or s <= 0 then return devOffset end
	devOffset = math.min(DEV_OFFSET_MAX, devOffset + math.floor(s))
	return devOffset
end

-- Dev only: back to the real clock.
function ServerTime.ResetDevOffset(): number
	devOffset = 0
	return 0
end

function ServerTime.GetDevOffset(): number
	return devOffset
end

-- A timestamp read from a save, made safe: not a number / NaN / below 0 -> 0;
-- in the future (bad clock on an older server) -> now.
function ServerTime.Sanitize(ts: any): number
	local n = tonumber(ts)
	if n == nil or n ~= n or n < 0 then
		return 0
	end
	n = math.floor(n)
	local now = ServerTime.Now()
	if n > now then
		return now
	end
	return n
end

-- Seconds since `ts` (sanitized), never negative. Optional `limit` caps the result
-- (e.g. the Dispatch earning limit in seconds).
function ServerTime.Elapsed(ts: any, limit: number?): number
	local e = math.max(0, ServerTime.Now() - ServerTime.Sanitize(ts))
	if type(limit) == "number" and limit >= 0 then
		e = math.min(e, limit)
	end
	return e
end

return table.freeze(ServerTime)
