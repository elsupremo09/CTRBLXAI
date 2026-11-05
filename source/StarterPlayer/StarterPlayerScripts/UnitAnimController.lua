--!strict
-- UnitAnimController.lua
-- CTRBLXAI | Client unit-animation player (2026-10-28)
--
-- Plays AnimationRegistry kinds on R15 unit models (cylinder / sphere tokens no-op).
-- Owns: per-token track cache (keyed by asset id so random pools work), the KO hold
-- (KO dramatic is frozen on its last frame so the body stays lying down), the
-- desynced base idle, random idle fidgets (one scheduler thread), and the active
-- player unit's Thinking loop. Visual only — no game state (ARC-001 / NET-001).
--
-- Dependencies are injected by BattleVisualClient through Init (no require back into
-- the client script). Every timer is generation-guarded so a stale delay is a no-op.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationRegistry = require(
	ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
		:WaitForChild("Shared", 10):WaitForChild("AnimationRegistry", 10)
)

local UnitAnimController = {}

local FIDGET_MIN_SEC = 10        -- random idle fidget gap per unit
local FIDGET_MAX_SEC = 25
local THINK_INTERVAL_SEC = 15    -- Thinking repeats after this much inaction
local THINK_RETRY_SEC = 1        -- unit busy (hit reaction etc.) -> retry soon
local ACTION_LOCK_SEC = 0.5      -- AOE / multi-pass: one actor animation per action
local LOAD_WAIT_TRIES = 50       -- x 0.1s waiting for an AnimationTrack's Length
local KO_HOLD_MARGIN_SEC = 0.05  -- freeze this far before the KO clip ends
local RUN_FADE_SEC = 0.2

local _rng = Random.new()
local _getTokens: () -> { [any]: any } = function()
	return {}
end
local _isAlive: (any) -> boolean = function(_unitId: any): boolean
	return true
end

-- Thinking state (the one player unit whose turn is up).
local _thinkUnit: any = nil
local _thinkGen = 0

-- Fidget scheduler thread.
local _fidgetThread: thread? = nil

-- Inject the client's token table getter and alive check. Call once from
-- BattleVisualClient after its unitTokens / unitData tables exist.
function UnitAnimController.Init(getTokens: () -> { [any]: any }, isAlive: (any) -> boolean)
	_getTokens = getTokens
	_isAlive = isAlive
end

local function getAnimator(token: any): any
	if not token or not token.model then
		return nil
	end
	local hum = token.model:FindFirstChildOfClass("Humanoid")
	if not hum then
		return nil
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	return animator
end

local function pickAsset(kind: string): string?
	local pool = AnimationRegistry.Kinds[kind]
	if not pool or #pool == 0 then
		return nil
	end
	return pool[_rng:NextInteger(1, #pool)]
end

-- Get-or-load the AnimationTrack for one asset on one token (cached per asset id).
local function loadTrack(token: any, assetId: string): any
	local animator = getAnimator(token)
	if not animator then
		return nil
	end
	token._animTracks = token._animTracks or {}
	local track = token._animTracks[assetId]
	if track then
		return track
	end
	local ok, loaded = pcall(function()
		local anim = Instance.new("Animation")
		anim.AnimationId = assetId
		return animator:LoadAnimation(anim)
	end)
	if not ok or not loaded then
		warn(`[UnitAnimController] Could not load animation {assetId}: {tostring(loaded)}`)
		return nil
	end
	token._animTracks[assetId] = loaded
	return loaded
end

local function isPlaying(track: any): boolean
	return track ~= nil and track.IsPlaying == true
end

-- True while the unit is mid-action, mid-reaction or moving (filler must not start).
local function isBusy(token: any): boolean
	return isPlaying(token._actionTrack) or isPlaying(token._runTrack)
end

-- Stop idle filler (fidget / Thinking) so it never blends with a real action.
local function stopFiller(token: any, fade: number?)
	if isPlaying(token._fillerTrack) then
		token._fillerTrack:Stop(fade or 0.15)
	end
	token._fillerTrack = nil
end

local function stopAllTracks(token: any, fade: number)
	local animator = getAnimator(token)
	if not animator then
		return
	end
	for _, tr in animator:GetPlayingAnimationTracks() do
		tr:Stop(fade)
	end
	token._fillerTrack = nil
	token._actionTrack = nil
	token._runTrack = nil
end

-- Play one animation kind on a token. opts: { loop=bool, fade=number,
-- stopAfter=number, force=bool }. Returns the track, or nil (cylinder, KO'd unit,
-- "None", unknown kind, or an actor action blocked by the per-action lock).
function UnitAnimController.Play(token: any, kind: string?, opts: any?): any
	local o = opts or {}
	if not token or kind == nil or kind == "None" then
		return nil
	end
	if token._isKO and kind ~= "KO" then
		return nil  -- a KO'd body stays down; nothing plays over the KO hold
	end
	local priority = AnimationRegistry.Priority[kind] or AnimationRegistry.DEFAULT_PRIORITY
	local isAction = priority == AnimationRegistry.DEFAULT_PRIORITY
	if isAction and not o.force then
		local now = os.clock()
		if (token._actionLockUntil or 0) > now then
			return nil
		end
		token._actionLockUntil = now + ACTION_LOCK_SEC
	end
	local assetId = pickAsset(kind)
	if not assetId then
		return nil
	end
	local track = loadTrack(token, assetId)
	if not track then
		return nil
	end
	local isReaction = priority == Enum.AnimationPriority.Action3
	if isAction or isReaction or kind == "Run" then
		stopFiller(token, 0.1)
	end
	track.Priority = priority
	track.Looped = o.loop == true
	track:Play(o.fade or 0.1)
	if kind == "Fidget" or kind == "Thinking" then
		token._fillerTrack = track
	elseif kind == "Run" then
		token._runTrack = track
	elseif isAction or isReaction then
		token._actionTrack = track
	end
	if o.stopAfter and not o.loop then
		task.delay(o.stopAfter, function()
			if track.IsPlaying then
				track:Stop(0.15)
			end
		end)
	end
	return track
end

-- The base idle asset (deployment idle uses it on raw models).
function UnitAnimController.BaseIdleAssetId(): string
	return AnimationRegistry.Assets.Idle
end

-- Start the looped base idle, desynced per unit (random speed 0.85x-1.15x and a
-- random start point) so standing units never sway in unison.
function UnitAnimController.StartBaseIdle(token: any): any
	local track = UnitAnimController.Play(token, "Idle", { loop = true, fade = 0.3 })
	if not track then
		return nil
	end
	track:AdjustSpeed(_rng:NextNumber(0.85, 1.15))
	token._nextFidgetAt = os.clock() + _rng:NextNumber(FIDGET_MIN_SEC, FIDGET_MAX_SEC)
	task.spawn(function()
		local tries = 0
		while track.Length <= 0 and tries < 30 do
			task.wait(0.1)
			tries += 1
		end
		if track.Length > 0 and track.IsPlaying then
			track.TimePosition = _rng:NextNumber(0, track.Length)
		end
	end)
	return track
end

-- Run loop for a move tween of `duration` seconds.
function UnitAnimController.PlayRun(token: any, duration: number)
	local track = UnitAnimController.Play(token, "Run", { loop = true, fade = 0.1 })
	if not track then
		return
	end
	-- A second move inside `duration` must not be cut short by the first move's timer.
	token._runGen = (token._runGen or 0) + 1
	local gen = token._runGen
	task.delay(duration, function()
		if token._runGen == gen and track.IsPlaying then
			track:Stop(RUN_FADE_SEC)
		end
	end)
end

-- KO: stop everything, play KO dramatic once, then freeze it on its last frame so
-- the model stays lying down until revived or removed.
function UnitAnimController.PlayKO(token: any)
	if not token or token._isKO then
		return  -- already down: a duplicate defeat event must not replay the KO clip
	end
	token._isKO = true
	token._koGen = (token._koGen or 0) + 1
	local gen = token._koGen
	stopAllTracks(token, 0.15)
	local track = UnitAnimController.Play(token, "KO", { fade = 0.1 })
	if not track then
		return
	end
	task.spawn(function()
		local tries = 0
		while track.Length <= 0 and tries < LOAD_WAIT_TRIES do
			task.wait(0.1)
			tries += 1
		end
		if track.Length <= 0 then
			warn("[UnitAnimController] KO animation never loaded (check the asset is owned by the experience owner)")
			return
		end
		local remaining = (track.Length - track.TimePosition) - KO_HOLD_MARGIN_SEC
		if remaining > 0 then
			task.wait(remaining)
		end
		if token._koGen ~= gen or not token._isKO then
			return  -- revived (or KO'd again) meanwhile
		end
		if not track.IsPlaying then
			track:Play(0)
		end
		track.TimePosition = math.max(0, track.Length - 0.03)
		track:AdjustSpeed(0)
	end)
end

-- Revive: release the KO hold and return to the base idle.
function UnitAnimController.RestoreFromKO(token: any)
	if not token then
		return
	end
	token._isKO = false
	token._koGen = (token._koGen or 0) + 1
	stopAllTracks(token, 0.2)
	UnitAnimController.StartBaseIdle(token)
end

-- Winning side: loop a random victory animation.
function UnitAnimController.PlayVictory(token: any)
	if not token or token._isKO then
		return
	end
	stopFiller(token, 0.1)
	UnitAnimController.Play(token, "Victory", { loop = true, fade = 0.2 })
end

--------------------------------------------------
-- THINKING (player unit waiting for a command)
--------------------------------------------------

local function stopThinkingTrack(unitId: any)
	local token = unitId ~= nil and _getTokens()[unitId] or nil
	if token and isPlaying(token._fillerTrack) then
		token._fillerTrack:Stop(0.2)
		token._fillerTrack = nil
	end
end

local function scheduleThinking(unitId: any, delaySec: number)
	_thinkGen += 1
	local gen = _thinkGen
	task.delay(delaySec, function()
		if gen ~= _thinkGen or _thinkUnit ~= unitId then
			return
		end
		local token = _getTokens()[unitId]
		if not token or token._isKO or not _isAlive(unitId) then
			return
		end
		if isBusy(token) then
			scheduleThinking(unitId, THINK_RETRY_SEC)
			return
		end
		UnitAnimController.Play(token, "Thinking", { fade = 0.2 })
		scheduleThinking(unitId, THINK_INTERVAL_SEC)
	end)
end

-- Called on every command prompt for the local player's unit. The first prompt of a
-- turn plays Thinking at once; later prompts in the same turn (after an action) only
-- restart the 15s inaction timer.
function UnitAnimController.OnCommandPrompt(unitId: any)
	if unitId == nil then
		return
	end
	if _thinkUnit == unitId then
		scheduleThinking(unitId, THINK_INTERVAL_SEC)
		return
	end
	stopThinkingTrack(_thinkUnit)
	_thinkUnit = unitId
	scheduleThinking(unitId, 0)
end

-- Any action by a unit: cut its Thinking and restart the inaction timer.
function UnitAnimController.NoteActivity(unitId: any)
	if unitId == nil or _thinkUnit ~= unitId then
		return
	end
	stopThinkingTrack(unitId)
	scheduleThinking(unitId, THINK_INTERVAL_SEC)
end

-- End Thinking for this unit (or for whoever, when unitId is nil).
function UnitAnimController.EndThinking(unitId: any?)
	if _thinkUnit == nil then
		return
	end
	if unitId ~= nil and unitId ~= _thinkUnit then
		return
	end
	stopThinkingTrack(_thinkUnit)
	_thinkUnit = nil
	_thinkGen += 1  -- invalidates any pending Thinking delay
end

--------------------------------------------------
-- IDLE FIDGETS (random alternate idles)
--------------------------------------------------

local function fidgetTick()
	local now = os.clock()
	for unitId, token in _getTokens() do
		if token.model and token.model.Parent and not token._isKO
			and unitId ~= _thinkUnit and _isAlive(unitId) then
			if token._nextFidgetAt == nil then
				token._nextFidgetAt = now + _rng:NextNumber(FIDGET_MIN_SEC, FIDGET_MAX_SEC)
			elseif now >= token._nextFidgetAt then
				if not isBusy(token) and not isPlaying(token._fillerTrack) then
					UnitAnimController.Play(token, "Fidget", { fade = 0.25 })
				end
				token._nextFidgetAt = now + _rng:NextNumber(FIDGET_MIN_SEC, FIDGET_MAX_SEC)
			end
		end
	end
end

-- One scheduler thread for every unit (checks once per second; no per-frame work).
function UnitAnimController.StartFidgets()
	if _fidgetThread then
		return
	end
	_fidgetThread = task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(fidgetTick)
			if not ok then
				warn(`[UnitAnimController] fidget tick failed: {tostring(err)}`)
			end
		end
	end)
end

function UnitAnimController.StopFidgets()
	if _fidgetThread then
		task.cancel(_fidgetThread)
		_fidgetThread = nil
	end
end

return UnitAnimController
