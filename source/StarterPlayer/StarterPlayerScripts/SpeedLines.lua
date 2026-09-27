--!strict
-- SpeedLines.lua
-- CTRBLXAI | Client-only screen-space speed lines for camera moves.
-- Programmatic Frame streaks (no image asset) radiate around screen center and
-- fade out. Triggered by CameraController:
--   * rotation (RotateCW/RotateCCW) and view-mode switches -> Burst()
--   * zoom -> Zoom(delta), THROTTLED to one pulse per scroll/pinch gesture so
--     the wheel does not flicker the overlay on every tick.
-- NET-001: client-only visual. NET-004: properties set before Parent.
-- PRF-004: every tween is tracked and cancelled before the next burst.
-- This is a short 2D UI fade; DRW-003 (3D transparency overdraw) does not apply.

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local SpeedLines = {}

-- TUNING (adjust after viewing in Studio)
local STREAK_COUNT       = 22    -- streaks per burst
local DURATION           = 0.35  -- seconds to fade out
local START_TRANSPARENCY = 0.35  -- streak opacity at burst start (1 = invisible)
local STREAK_THICKNESS   = 2     -- px
local STREAK_LEN_MIN     = 0.10  -- fraction of the screen's shorter side
local STREAK_LEN_MAX     = 0.22
local INNER_RADIUS       = 0.55  -- start radius, fraction of half-diagonal (keeps center clear)
local TRAVEL             = 0.10  -- slide distance during the burst, fraction of half-diagonal
local STREAK_COLOR       = Color3.fromRGB(255, 255, 255)
local BURST_COOLDOWN     = 0.15  -- min seconds between bursts
local ZOOM_THRESHOLD     = 8     -- studs of accumulated zoom before a zoom pulse
local ZOOM_IDLE_RESET    = 0.30  -- seconds without zoom input = new gesture

local gui: ScreenGui? = nil
local streaks: {Frame} = {}
local activeTweens: {Tween} = {}
local lastBurst = 0
local zoomAccum = 0
local lastZoomAt = 0
local zoomGestureFired = false
local rng = Random.new()

local function ensureGui(): ScreenGui?
	if gui and gui.Parent then return gui end
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then return nil end
	local g = Instance.new("ScreenGui")
	g.Name = "SpeedLines"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 1  -- below the battle HUD so panels stay readable
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	table.clear(streaks)
	for i = 1, STREAK_COUNT do
		local f = Instance.new("Frame")
		f.Name = "Streak" .. i
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundColor3 = STREAK_COLOR
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Active = false  -- never swallow taps/clicks
		f.Visible = false
		f.Parent = g
		table.insert(streaks, f)
	end
	g.Parent = pg  -- parent last (NET-004)
	gui = g
	return g
end

local function cancelTweens()
	for _, tw in activeTweens do tw:Cancel() end
	table.clear(activeTweens)
end

-- direction: 1 = streaks rush inward (zoom in / rotate), -1 = outward (zoom out)
local function burst(direction: number)
	local now = os.clock()
	if now - lastBurst < BURST_COOLDOWN then return end
	lastBurst = now
	local g = ensureGui()
	if not g then return end
	local size = g.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then return end
	cancelTweens()
	local cx, cy = size.X / 2, size.Y / 2
	local halfDiag = math.sqrt(cx * cx + cy * cy)
	local shortSide = math.min(size.X, size.Y)
	local info = TweenInfo.new(DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, f in streaks do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dx, dy = math.cos(angle), math.sin(angle)
		local len = shortSide * rng:NextNumber(STREAK_LEN_MIN, STREAK_LEN_MAX)
		local r0 = halfDiag * rng:NextNumber(INNER_RADIUS, INNER_RADIUS + 0.30)
		local r1 = r0 - direction * halfDiag * TRAVEL
		f.Size = UDim2.fromOffset(len, STREAK_THICKNESS)
		f.Rotation = math.deg(angle)  -- long axis points along the radial direction
		f.Position = UDim2.fromOffset(cx + dx * r0, cy + dy * r0)
		f.BackgroundTransparency = START_TRANSPARENCY
		f.Visible = true
		local tw = TweenService:Create(f, info, {
			Position = UDim2.fromOffset(cx + dx * r1, cy + dy * r1),
			BackgroundTransparency = 1,
		})
		tw:Play()
		table.insert(activeTweens, tw)
	end
end

--- Immediate burst: rotation and view-mode switches.
function SpeedLines.Burst()
	burst(1)
end

--- Zoom pulse. `delta` = change in camera distance (negative = zoomed in).
--- Accumulates ticks and fires at most once per gesture.
function SpeedLines.Zoom(delta: number)
	local now = os.clock()
	if now - lastZoomAt > ZOOM_IDLE_RESET then
		zoomAccum = 0
		zoomGestureFired = false
	end
	lastZoomAt = now
	if zoomGestureFired then return end
	zoomAccum += delta
	if math.abs(zoomAccum) >= ZOOM_THRESHOLD then
		zoomGestureFired = true
		burst(if zoomAccum < 0 then 1 else -1)
	end
end

return SpeedLines
