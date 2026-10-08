--!strict
-- UGCRatingService.lua
-- CTRBLXAI | UGC Ratings aggregate — server only (ARC-001)
--
-- Split out of UGCService.lua on 2026-10-08 (ARC-005: UGCService was at 981 of
-- 1000 lines before the Outfit tab / purchase-refund work). One responsibility:
-- the PRIVATE developer aggregate of like/dislike votes (ugc_rules rating_model /
-- rating_aggregate). The per-player vote itself still lives in UGCService state
-- (saved as 'rv'); UGCService.Rate calls RecordVote with the change.
--
-- Totals are never sent to clients. Votes are batched per server and written to
-- a DataStore with UpdateAsync and bounded retries; a failed write is re-queued.
--
-- Wired by Main.server.lua only (ARC-004 / ARC-006, nil-safe):
--   UGCService.SetRatingService(UGCRatingService)
--   UGCService.SetSaveModeProvider(fn) forwards the save mode here.

local DataStoreService = game:GetService("DataStoreService")

local UGCRatingService = {}

local RATING_FLUSH_SECONDS = 300
local MAX_RETRIES = 3 -- mirrors SaveService (save_data_contract: bounded retries)
local RETRY_DELAY = 1.0

type RatingDelta = { likes: number, dislikes: number }

local _pending: { [number]: RatingDelta } = {}
local _isFlushing = false
local _isLoopStarted = false
local _saveMode: (() -> string)? = nil
local _store: DataStore? = nil

function UGCRatingService.SetSaveModeProvider(fn: () -> string) _saveMode = fn end

-- previous / vote: 1 like, -1 dislike, 0 none. Only the change is queued.
function UGCRatingService.RecordVote(assetId: number, previous: number, vote: number)
	if previous == vote then return end
	local d = _pending[assetId] or { likes = 0, dislikes = 0 }
	d.likes += (if vote == 1 then 1 else 0) - (if previous == 1 then 1 else 0)
	d.dislikes += (if vote == -1 then 1 else 0) - (if previous == -1 then 1 else 0)
	_pending[assetId] = d
end

local function ratingStore(): DataStore?
	local mode = _saveMode and _saveMode() or "memory"
	if mode == "memory" then return nil end
	if _store then return _store end
	local namespace = if mode == "studio" then "CTRBLXAI_Dev" else "CTRBLXAI_Live" -- SaveService naming
	local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, namespace .. "_UGCRatings")
	if not ok then
		warn(`[UGCRatingService] Ratings DataStore unavailable: {store}`)
		return nil
	end
	_store = store
	return store
end

function UGCRatingService.Flush()
	if _isFlushing or next(_pending) == nil then return end
	_isFlushing = true
	local batch = _pending
	_pending = {}
	local store = ratingStore()
	if not store then
		print("[UGCRatingService] Ratings flush skipped (memory mode) — batch discarded")
		_isFlushing = false
		return
	end
	for assetId, d in batch do
		if d.likes == 0 and d.dislikes == 0 then continue end
		local isSaved = false
		for attempt = 1, MAX_RETRIES do
			local ok, err = pcall(function()
				store:UpdateAsync(`asset_{assetId}`, function(old: any)
					local t = if type(old) == "table" then old else {}
					t.likes = math.max(0, (tonumber(t.likes) or 0) + d.likes)
					t.dislikes = math.max(0, (tonumber(t.dislikes) or 0) + d.dislikes)
					return t
				end)
			end)
			if ok then
				isSaved = true
				break
			end
			warn(`[UGCRatingService] Ratings UpdateAsync {assetId} attempt {attempt}/{MAX_RETRIES} failed: {err}`)
			task.wait(RETRY_DELAY * attempt)
		end
		if not isSaved then
			-- Re-queue for the next flush rather than lose the votes.
			local p = _pending[assetId] or { likes = 0, dislikes = 0 }
			p.likes += d.likes
			p.dislikes += d.dislikes
			_pending[assetId] = p
		end
	end
	_isFlushing = false
end

-- Starts the periodic flush once; also flushes at server shutdown.
function UGCRatingService.StartFlushLoop()
	if _isLoopStarted then return end
	_isLoopStarted = true
	task.spawn(function()
		while true do
			task.wait(RATING_FLUSH_SECONDS)
			UGCRatingService.Flush()
		end
	end)
	game:BindToClose(function()
		UGCRatingService.Flush()
	end)
end

return UGCRatingService
