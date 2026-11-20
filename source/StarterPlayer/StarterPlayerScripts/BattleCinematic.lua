-- BattleCinematic.lua
-- CTRBLXAI | Battle cinematic focus (user request 2026-11-18 5:57 PM).
--
-- Client-only (NET-001): the server only says WHAT happened (a unit id with its event name,
-- the quest goal snapshot); this module moves the camera and shows the banner.
--   * A battlefield event spawns a unit -> 2 s camera focus on it, event name in the banner.
--   * A quest point of interest (goal target / goal tile / marked objects) -> 1.5 s focus with
--     the goal sentence in the banner (at battle start, and when a new one appears mid-battle).
-- Shots are queued and play one after another; same-name spawns that arrive together merge
-- into one shot that frames all of them. While a cinematic runs the player cannot move the
-- camera (CameraController input lock "cinematic"); gameplay camera calls keep updating the
-- real camera state, and the camera tweens back to it when the cinematic ends.
-- Text shown here is always existing approved text passed in by the caller (event names,
-- QuestGoalText lines) - this module adds no wording of its own.
--
-- API:
--   Init(deps)                       deps = { camera, theme, unitPos(id)->Vector3?,
--                                            tileWorld(x,y)->Vector3?, canPlay()->bool,
--                                            isBlocked()->bool, onShotStart(label)? }
--   QueueUnits(ids, label, seconds)  focus one or more units
--   QueueTiles(tiles, label, seconds) focus one or more battle tiles ({x=,y=} or {x,y})
--   IsBusy()                         a shot is queued or playing
--   WaitIdle(timeout)                yield until idle (or timeout)
--   Cancel()                         drop everything now (battle end / base)
--   IsPlaying()                      a shot is on screen right now
--   ShowAction(text, opts)           name banner for a skill / special / item (user 2026-11-18 6:21 PM,
--                                    layout B): same upper-centre spot, ~1.5 s, no pause, never takes
--                                    taps; the newest replaces the old one; a cinematic shot's text wins
--                                    (no action banner while a shot is on screen, and a shot clears it).
--                                    opts = { small = bool? } (text only: no icon, no side outline, user 7:44 PM)
-- Tap to skip (user 2026-11-18 6:10 PM): while a shot is on screen a full-screen invisible
-- button catches the tap, so it never also selects a tile or presses a HUD button underneath;
-- the tap calls Cancel() (current shot + the rest of the queue), the camera eases back.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local BattleCinematic = {}

local BANNER_TOP = 80          -- px from the screen top: clears the time/weather tiles (ends ~75)
local BANNER_H = 32          -- 2026-11-18: slim design-6 banner (was 48)
local STROKE_ROOM = 0        -- 2026-11-18 7:44 PM: no side outline any more; the art (gems included) fills the group
local BANNER_MAX_W = 440
local COLLECT_DELAY = 0.25     -- let same-frame spawns merge into one shot
local BLOCK_WAIT_MAX = 30      -- never wait longer than this for the player's targeting to end
local FADE = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local deps: any = nil
local queue: { any } = {}
local running = false
local runId = 0                -- bumped by Cancel so a stale runner stops
local bannerGui: ScreenGui? = nil
local catcherGui: ScreenGui? = nil -- tap-to-skip catcher, only while a shot is on screen
local playing = false
local actionGui: ScreenGui? = nil -- name banner for skills / items (one at a time)
local actionSerial = 0

local function log(msg: string)
	print("[BattleCinematic] " .. msg)
end

function BattleCinematic.Init(d: any)
	deps = d
end

local function canPlay(): boolean
	if not deps or not deps.camera then return false end
	if type(deps.canPlay) == "function" then
		local ok, res = pcall(deps.canPlay)
		return ok and res == true
	end
	return true
end

local function isBlocked(): boolean
	if not deps or type(deps.isBlocked) ~= "function" then return false end
	local ok, res = pcall(deps.isBlocked)
	return ok and res == true
end

--------------------------------------------------
-- BANNER (upper center, shared gold panel)
--------------------------------------------------
local function hideAction(fade: boolean?)
	local gui = actionGui
	actionGui = nil
	actionSerial += 1
	if not gui then return end
	local group = gui:FindFirstChild("Group")
	if fade and group and group:IsA("CanvasGroup") then
		TweenService:Create(group, FADE, { GroupTransparency = 1 }):Play()
		task.delay(0.3, function() gui:Destroy() end)
	else
		gui:Destroy()
	end
end

local function hideBanner()
	local gui = bannerGui
	bannerGui = nil
	if not gui then return end
	local group = gui:FindFirstChild("Group")
	if group and group:IsA("CanvasGroup") then
		TweenService:Create(group, FADE, { GroupTransparency = 1 }):Play()
		task.delay(0.3, function() gui:Destroy() end)
	else
		gui:Destroy()
	end
end

--- Shared banner frame. Design 6 sliced image (Theme.BattleBannerImage) when present, else the
--- old gold panel / plain frame. The frame is inset STROKE_ROOM px inside `group` (0 now: banners are
--- text only, no side outline, user 2026-11-18 7:44 PM). Returns the frame and the fixed end-cap width in px.
local function makeBannerFrame(group: GuiObject, h: number, Theme: any): (GuiObject, number)
	local img = Theme and Theme.BattleBannerImage
	local sl = Theme and Theme.BattleBannerSlice
	if type(img) == "string" and img ~= "" and type(sl) == "table" then
		local scale = h / (sl.artHeight or 128)
		local f = Instance.new("ImageLabel")
		f.Name = "Panel"
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Size = UDim2.new(1, -STROKE_ROOM * 2, 1, -STROKE_ROOM * 2)
		f.Position = UDim2.fromOffset(STROKE_ROOM, STROKE_ROOM)
		f.Image = img
		f.ScaleType = Enum.ScaleType.Slice
		f.SliceCenter = sl.center
		f.SliceScale = scale
		f.Active = false
		f.Parent = group
		return f, math.floor((sl.capPx or 112) * scale + 0.5)
	end
	if Theme and Theme.MakePanel then
		local panel = Theme.MakePanel("Panel", UDim2.new(1, -STROKE_ROOM * 2, 1, -STROKE_ROOM * 2),
			UDim2.fromOffset(STROKE_ROOM, STROKE_ROOM), Vector2.new(0, 0), group)
		panel.Active = false -- never swallows taps
		return panel, 12
	end
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, -STROKE_ROOM * 2, 1, -STROKE_ROOM * 2)
	f.Position = UDim2.fromOffset(STROKE_ROOM, STROKE_ROOM)
	f.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel = 0
	f.Parent = group
	return f, 12
end

local function showBanner(text: string)
	hideBanner()
	hideAction(false) -- the cinematic text wins over a skill / item name
	if type(text) ~= "string" or text == "" then return end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then return end
	local Theme = deps and deps.theme
	local cam = Workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 800
	local w = math.floor(math.min(BANNER_MAX_W, vw * 0.55))

	local gui = Instance.new("ScreenGui")
	gui.Name = "BattleCinematicBanner"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 95 -- above the HUD, below the center event banner (100)

	local group = Instance.new("CanvasGroup")
	group.Name = "Group"
	group.AnchorPoint = Vector2.new(0.5, 0)
	group.Position = UDim2.new(0.5, 0, 0, BANNER_TOP)
	group.Size = UDim2.fromOffset(w, BANNER_H + STROKE_ROOM * 2)
	group.BackgroundTransparency = 1
	group.GroupTransparency = 1
	group.Active = false
	group.Parent = gui

	local panel, capW = makeBannerFrame(group, BANNER_H, Theme)

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -capW * 2, 1, -6)
	label.Position = UDim2.fromOffset(capW, 3)
	label.Font = (Theme and Theme.Font and Theme.Font.PrimaryBold) or Enum.Font.GothamBold
	label.TextColor3 = (Theme and Theme.Colors and Theme.Colors.TextGold) or Color3.fromRGB(235, 205, 120)
	label.TextStrokeTransparency = 0.3
	label.TextWrapped = true
	label.TextScaled = true
	label.Text = text
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = (Theme and Theme.Text and Theme.Text.Heading and Theme.Text.Heading()) or 20
	cap.MinTextSize = 10
	cap.Parent = label
	label.Parent = panel

	gui.Parent = pg -- parent last (NET-004)
	bannerGui = gui
	TweenService:Create(group, FADE, { GroupTransparency = 0 }):Play()
end

--------------------------------------------------
-- TAP TO SKIP (full-screen invisible catcher above the HUD and the banner)
--------------------------------------------------
local function hideCatcher()
	local gui = catcherGui
	catcherGui = nil
	if gui then gui:Destroy() end
end

local function showCatcher(onTap: () -> ())
	if catcherGui then return end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "BattleCinematicSkip"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 96 -- above the HUD and the banner (95): the tap stops here
	local btn = Instance.new("TextButton")
	btn.Name = "Skip"
	btn.Size = UDim2.fromScale(1, 1)
	btn.BackgroundTransparency = 1
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.Active = true -- sinks the tap: gameProcessed = true for the map / camera handlers
	btn.Selectable = false
	btn.Parent = gui
	btn.Activated:Connect(onTap) -- destroyed with the gui (no leak)
	gui.Parent = pg -- parent last (NET-004)
	catcherGui = gui
end

--------------------------------------------------
-- SHOTS
--------------------------------------------------
local function framePoints(points: { Vector3 }): (Vector3?, number?)
	if #points == 0 then return nil, nil end
	local sum = Vector3.zero
	for _, p in ipairs(points) do sum += p end
	local c = sum / #points
	if #points == 1 then return c, nil end
	local span = 0
	for _, p in ipairs(points) do
		span = math.max(span, ((p - c) * Vector3.new(1, 0, 1)).Magnitude * 2)
	end
	local cc = deps.camera
	local dist = if cc.CinematicFitDistance then cc.CinematicFitDistance(span) else nil
	return c, dist
end

local function resolve(item: any): { Vector3 }
	local out: { Vector3 } = {}
	if item.kind == "units" and type(deps.unitPos) == "function" then
		for _, id in ipairs(item.ids) do
			local ok, p = pcall(deps.unitPos, id)
			if ok and typeof(p) == "Vector3" then table.insert(out, p) end
		end
	elseif item.kind == "tiles" and type(deps.tileWorld) == "function" then
		for _, t in ipairs(item.tiles) do
			local x = if type(t) == "table" then (t.x or t[1]) else nil
			local y = if type(t) == "table" then (t.y or t[2]) else nil
			if type(x) == "number" and type(y) == "number" then
				local ok, p = pcall(deps.tileWorld, x, y)
				if ok and typeof(p) == "Vector3" then table.insert(out, p) end
			end
		end
	end
	return out
end

local function finish(myRun: number)
	if myRun ~= runId then return end
	running = false
	playing = false
	hideBanner()
	hideCatcher()
	local cc = deps and deps.camera
	if cc then
		if cc.EndCinematic then pcall(cc.EndCinematic) end
		if cc.SetInputLocked then pcall(cc.SetInputLocked, "cinematic", false) end
	end
end

local function runQueue()
	if running then return end
	running = true
	runId += 1
	local myRun = runId
	task.spawn(function()
		task.wait(COLLECT_DELAY)
		-- Never during the player's own targeting: wait for it to end (bounded).
		local waited = 0
		while myRun == runId and isBlocked() and waited < BLOCK_WAIT_MAX do
			task.wait(0.2); waited += 0.2
		end
		if myRun ~= runId then return end
		local cc = deps.camera
		local began = false
		while myRun == runId and #queue > 0 do
			local item = table.remove(queue, 1)
			if not canPlay() then table.clear(queue); break end
			local pts = resolve(item)
			local center, dist = framePoints(pts)
			if center then
				if not began then
					began = cc.BeginCinematic and cc.BeginCinematic() == true
					if not began then table.clear(queue); break end
					if cc.SetInputLocked then cc.SetInputLocked("cinematic", true) end
					playing = true
					showCatcher(function()
						log("skipped by tap")
						BattleCinematic.Cancel()
					end)
				end
				if type(deps.onShotStart) == "function" then pcall(deps.onShotStart, item.label) end
				showBanner(item.label)
				cc.CinematicLookAt(center, dist)
				log(`focus "{tostring(item.label)}" ({#pts} point(s), {item.seconds}s)`)
				task.wait(item.seconds)
			end
		end
		finish(myRun)
	end)
end

local function enqueue(item: any)
	if not deps or not deps.camera then return end
	-- Merge same-label unit shots that have not started yet (a horde spawns several units at once).
	local last = queue[#queue]
	if item.kind == "units" and last and last.kind == "units" and last.label == item.label then
		for _, id in ipairs(item.ids) do table.insert(last.ids, id) end
		last.seconds = math.max(last.seconds, item.seconds)
	else
		table.insert(queue, item)
	end
	runQueue()
end

function BattleCinematic.QueueUnits(ids: { any }, label: string?, seconds: number?)
	if type(ids) ~= "table" or #ids == 0 then return end
	local copy = table.clone(ids)
	enqueue({ kind = "units", ids = copy, label = label or "", seconds = tonumber(seconds) or 2 })
end

function BattleCinematic.QueueTiles(tiles: { any }, label: string?, seconds: number?)
	if type(tiles) ~= "table" or #tiles == 0 then return end
	enqueue({ kind = "tiles", tiles = table.clone(tiles), label = label or "", seconds = tonumber(seconds) or 1.5 })
end

local ACTION_H = 32          -- 2026-11-18 design 6 (was 44)
local ACTION_H_SMALL = 26    -- items (was 36)
local ACTION_HOLD = 1.5

--- Name banner for an announced skill / special / item. Plays over the start of the action
--- (no pause, no queue: the newest replaces the old one). Text is the existing skill / item name.
function BattleCinematic.ShowAction(text: string?, opts: any?)
	if type(text) ~= "string" or text == "" then return end
	if playing then return end -- a cinematic shot is on screen: its text wins
	hideAction(false)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then return end
	local o = if type(opts) == "table" then opts else {}
	local Theme = deps and deps.theme
	local cam = Workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 800
	local small = o.small == true
	local h = if small then ACTION_H_SMALL else ACTION_H
	local maxW = math.floor(math.min(if small then 300 else 360, vw * (if small then 0.40 else 0.48)))
	-- Width follows the name (design-6 preview): caps + text, never wider than maxW. Text only.
	local w = maxW
	do
		local capPx = (Theme and Theme.BattleBannerSlice and Theme.BattleBannerSlice.capPx) or 112
		local cap = math.floor(capPx * h / 128 + 0.5)
		local maxText = if small then 16 else ((Theme and Theme.Text and Theme.Text.Heading and Theme.Text.Heading()) or 20)
		local font = (Theme and Theme.Font and Theme.Font.PrimaryBold) or Enum.Font.GothamBold
		local ok, size = pcall(function()
			return TextService:GetTextSize(text, maxText, font, Vector2.new(10000, h))
		end)
		if ok and typeof(size) == "Vector2" then
			w = math.clamp(math.ceil(cap * 2 + size.X + 8), 120, maxW)
		end
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "BattleActionBanner"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 94 -- just below the cinematic banner (95); no buttons, never takes taps

	local group = Instance.new("CanvasGroup")
	group.Name = "Group"
	group.AnchorPoint = Vector2.new(0.5, 0)
	group.Position = UDim2.new(0.5, 0, 0, BANNER_TOP)
	group.Size = UDim2.fromOffset(w, h + STROKE_ROOM * 2)
	group.BackgroundTransparency = 1
	group.GroupTransparency = 1
	group.Active = false
	group.Parent = gui

	local panel, capW = makeBannerFrame(group, h, Theme)

	local pad = 3
	local textX = capW -- text sits between the two gem caps
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -(textX + capW), 1, -pad * 2)
	label.Position = UDim2.fromOffset(textX, pad)
	label.Font = (Theme and Theme.Font and Theme.Font.PrimaryBold) or Enum.Font.GothamBold
	label.TextColor3 = (Theme and Theme.Colors and Theme.Colors.TextGold) or Color3.fromRGB(235, 205, 120)
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Text = text
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = if small then 16 else ((Theme and Theme.Text and Theme.Text.Heading and Theme.Text.Heading()) or 20)
	cap.MinTextSize = 10
	cap.Parent = label
	label.Parent = panel

	gui.Parent = pg -- parent last (NET-004)
	actionGui = gui
	local mySerial = actionSerial
	TweenService:Create(group, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ GroupTransparency = 0 }):Play()
	task.delay(ACTION_HOLD, function()
		if actionSerial == mySerial and actionGui == gui then hideAction(true) end
	end)
end

function BattleCinematic.IsBusy(): boolean
	return running or #queue > 0
end

--- True while a shot is on screen (not merely queued / waiting for the player's targeting).
function BattleCinematic.IsPlaying(): boolean
	return playing
end

--- Yield until no shot is queued or playing (or `timeout` seconds pass).
function BattleCinematic.WaitIdle(timeout: number?)
	local limit = tonumber(timeout) or 10
	local t0 = os.clock()
	while BattleCinematic.IsBusy() and os.clock() - t0 < limit do
		task.wait(0.1)
	end
end

--- Drop every queued shot and hand the camera back now (battle end, base wipe).
function BattleCinematic.Cancel()
	table.clear(queue)
	hideAction(false)
	if running then
		local myRun = runId
		finish(myRun)
		runId += 1 -- stop the old runner thread
	else
		hideBanner()
		hideCatcher()
	end
end

return BattleCinematic
