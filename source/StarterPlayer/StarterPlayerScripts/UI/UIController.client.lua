-- UIController.client.lua
-- CTRBLXAI | Slice 7 Stage 2 — Viewport Observer & Layout Coordinator
--
-- Responsibilities:
--   - Wait for valid viewport (>1×1) with bounded timeout
--   - Observe ViewportSize changes with debounce
--   - Recalculate layout mode when viewport materially changes
--   - Apply layout to BattleHUD panels (non-destructive reflow)
--
-- Does NOT own battle state, panel content, or camera.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

--------------------------------------------------
-- MODULE LOADING
--------------------------------------------------

local CTRBLXAI_UI = ReplicatedStorage
	:WaitForChild("CTRBLXAI", 10)
	:WaitForChild("UI", 10)

local Theme             = require(CTRBLXAI_UI:WaitForChild("Theme", 10))
local UIComponents      = require(CTRBLXAI_UI:WaitForChild("UIComponents", 10))
local UIFormatting      = require(CTRBLXAI_UI:WaitForChild("UIFormatting", 10))
local UIConstants       = require(CTRBLXAI_UI:WaitForChild("UIConstants", 10))
local UILayoutCoordinator = require(CTRBLXAI_UI:WaitForChild("UILayoutCoordinator", 10))

local BattleHUD = require(CTRBLXAI_UI:WaitForChild("BattleHUD", 10))

--------------------------------------------------
-- STATE
--------------------------------------------------

local currentMode = nil      -- "Desktop", "CompactLandscape", "MobileLandscape"
local currentLayout = nil    -- last computed layout table
local debounceThread = nil   -- pending debounce task
local DEBOUNCE_SEC = 0.15    -- debounce for rapid resize events

--------------------------------------------------
-- VIEWPORT DETECTION
--------------------------------------------------

local function getViewportSize()
	local cam = workspace.CurrentCamera
	if not cam then return nil end
	local vs = cam.ViewportSize
	if vs.X > 1 and vs.Y > 1 then
		return vs
	end
	return nil
end

--- Wait for a valid viewport (>1×1). Returns the size, or a Desktop
--- fallback after timeout.
local function waitForValidViewport()
	local vs = getViewportSize()
	if vs then return vs end

	-- Bounded wait: up to 2 seconds for a valid viewport
	local elapsed = 0
	while elapsed < 2 do
		local dt = task.wait(0.05)
		elapsed = elapsed + dt
		vs = getViewportSize()
		if vs then return vs end
	end

	-- Timeout: use Desktop fallback, will reclassify when valid size arrives
	print("[UILayout] viewport=1x1 timeout — using Desktop fallback")
	return Vector2.new(1920, 1080)
end

--------------------------------------------------
-- LAYOUT APPLICATION
--------------------------------------------------

local function applyLayout(viewportSize)
	local layout = UILayoutCoordinator.GetLayout(viewportSize)
	local newMode = layout.mode

	if newMode ~= currentMode then
		print(string.format("[UILayout] viewport=%dx%d mode=%s",
			math.round(viewportSize.X), math.round(viewportSize.Y), newMode))
		currentMode = newMode
	end

	currentLayout = layout

	-- Apply to BattleHUD if it has panels
	BattleHUD.ApplyLayout(layout)
end

--------------------------------------------------
-- VIEWPORT CHANGE OBSERVER
--------------------------------------------------

local function onViewportChanged()
	-- Debounce: cancel pending, schedule new
	if debounceThread then
		task.cancel(debounceThread)
		debounceThread = nil
	end

	debounceThread = task.delay(DEBOUNCE_SEC, function()
		debounceThread = nil
		local vs = getViewportSize()
		if not vs then return end

		-- Only reflow if mode actually changed or dimensions shifted materially (>20px)
		local layout = UILayoutCoordinator.GetLayout(vs)
		if layout.mode ~= currentMode then
			applyLayout(vs)
		end
	end)
end

--------------------------------------------------
-- CAMERA CHANGE HANDLER (new camera instance on respawn)
--------------------------------------------------

local currentCamera = nil
local viewportConn = nil

local function connectCamera()
	if currentCamera == workspace.CurrentCamera and viewportConn then return end
	if viewportConn then viewportConn:Disconnect() end

	currentCamera = workspace.CurrentCamera
	if currentCamera then
		viewportConn = currentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(onViewportChanged)
	end
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(connectCamera)

--------------------------------------------------
-- INITIALIZATION
--------------------------------------------------

-- Wait for valid viewport
local initialSize = waitForValidViewport()
connectCamera()
applyLayout(initialSize)

-- If the initial viewport was a fallback, keep watching for the real one
if initialSize.X == 1920 and initialSize.Y == 1080 then
	task.spawn(function()
		while true do
			task.wait(0.1)
			local vs = getViewportSize()
			if vs and (vs.X ~= 1920 or vs.Y ~= 1080) then
				applyLayout(vs)
				break
			end
		end
	end)
end

-- Confirmation
print("[CTRBLXAI UI] Slice 7A modules loaded successfully.")
print(string.format(
	"[CTRBLXAI UI] Viewport: %dx%d | Layout: %s",
	math.round(initialSize.X), math.round(initialSize.Y), currentMode
))
print(string.format(
	"[CTRBLXAI UI] Theme colors: %d | Components: %d functions | Formatting: %d functions",
	(function() local c = 0; for _ in pairs(Theme.Colors) do c = c + 1 end; return c end)(),
	(function() local c = 0; for _, v in pairs(UIComponents) do if type(v) == "function" then c = c + 1 end end; return c end)(),
	(function() local c = 0; for _, v in pairs(UIFormatting) do if type(v) == "function" then c = c + 1 end end; return c end)()
))
