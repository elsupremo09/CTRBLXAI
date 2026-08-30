-- CameraController.lua
-- CTRBLXAI | Stage 1 — Tactical Camera + Per-Touch Gesture Model
--
-- SOLE OWNER of workspace.CurrentCamera during battle.
-- No other file writes Camera.CFrame.
--
-- Camera model: fixed pitch, 8-direction snapped yaw, bounded zoom/pan.
-- Touch model: per-touch identity tracking, tap-on-release classification.
--
-- API:
--   EnterBattle(focusPos?)   — activate tactical camera + disable controls
--   ExitBattle()             — restore all native controls
--   Pan(dx, dz)              — rotation-aware pan, clamped
--   RotateCW() / RotateCCW() — 45° snapped rotation
--   Zoom(delta)              — bounded distance change
--   FocusActiveUnit(pos)     — center on active unit
--   FocusSelectedUnit(pos)   — center on selected unit
--   ResetTacticalView(pos?)  — restore default view
--   ConsumeTapIntent()       — returns tap screen position or nil
--   IsOverUI(screenPos)      — shared UI hit-test

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local StarterGui       = game:GetService("StarterGui")
local GuiService       = game:GetService("GuiService")

local player = Players.LocalPlayer

--------------------------------------------------
-- CONFIGURATION (all tunable for Studio testing)
--------------------------------------------------

-- Camera geometry
local FIXED_PITCH     = 50          -- Degrees downward (NOT player-adjustable)
local FIXED_FOV       = 55          -- Degrees (NOT animated or zoomed)
local ROTATION_SNAP   = 45          -- 8 viewing directions

-- Distance (calculated from visible-tile targets)
-- Closest: ~8 tiles, Default: ~11 tiles, Farthest: ~20 tiles
local ZOOM_MIN        = 38
local ZOOM_DEFAULT    = 53
local ZOOM_MAX        = 96
local ZOOM_STEP       = 5           -- Per scroll tick

-- Pan
local PAN_SPEED       = 0.5         -- Studs per pixel (drag)
local PAN_KEY_SPEED   = 1.0         -- Studs per frame (WASD)

-- Battle area bounds (set by BattleVisualClient from playable grid)
-- NOTE: Future procedural maps must supply authoritative playable world bounds
-- to BattleVisualClient, which passes them to CameraController.SetBattlefieldBounds().
-- Current 8×8 prototype fallback is NOT a permanent solution.
local battleBounds = {
	minX = -20, maxX = 20,  -- prototype fallback: 8×8 battle grid edges
	minZ = -20, maxZ = 20,
	tileSize = 5,
	source = "prototype-fallback",
}

-- Touch
local DRAG_THRESHOLD  = 8           -- Pixels
local ROTATION_THRESHOLD = 20       -- Pixels horizontal movement for 2-finger rotate

-- Tween
local TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--------------------------------------------------
-- STATE
--------------------------------------------------

local camera    = workspace.CurrentCamera
local focus     = Vector3.new(0, 0, 0)
local distance  = ZOOM_DEFAULT
local yaw       = 0
local isActive  = false
local inBattle  = false

-- Desktop drag
local isDraggingRight  = false
local isDraggingMiddle = false
local dragStartPos     = Vector2.new(0, 0)
local heldKeys         = {}

-- Per-touch tracking (keyed by InputObject)
local trackedTouches = {}
-- Each entry: { startPos, prevPos, curPos, beganOverUI, exceededDrag, inMultitouch }

-- Multi-touch aggregate state (shared, OK for 2-finger gestures)
local lastPinchDist    = nil
local lastTwistAngle   = nil
local rotationTriggered = false  -- Only one 45° step per multi-touch gesture

-- Tap intent (consumed by BattleVisualClient)
local pendingTapPos    = nil

-- Stored native state for restoration
local storedCameraType     = nil
local storedCameraSubject  = nil
local storedFieldOfView    = nil
local storedCharParts      = {}
local storedHumanoidProps  = {}
local storedTouchControls  = nil

--------------------------------------------------
-- CORE CAMERA MATH
--------------------------------------------------

local function computeCFrame()
	local pitchRad = math.rad(FIXED_PITCH)
	local yawRad   = math.rad(yaw)
	local ox = distance * math.cos(pitchRad) * math.sin(yawRad)
	local oz = distance * math.cos(pitchRad) * math.cos(yawRad)
	local oy = distance * math.sin(pitchRad)
	return CFrame.lookAt(focus + Vector3.new(ox, oy, oz), focus)
end

local function clampFocus(f)
	local margin = battleBounds.tileSize * 8  -- 8 tiles margin (panels cover ~40% of mobile viewport)
	return Vector3.new(
		math.clamp(f.X, battleBounds.minX - margin, battleBounds.maxX + margin),
		0,
		math.clamp(f.Z, battleBounds.minZ - margin, battleBounds.maxZ + margin)
	)
end


local function applyCFrame(instant)
	if not isActive then return end
	focus = clampFocus(focus)
	distance = math.clamp(distance, ZOOM_MIN, ZOOM_MAX)
	local target = computeCFrame()
	if instant then
		camera.CFrame = target
	else
		TweenService:Create(camera, TWEEN_INFO, { CFrame = target }):Play()
	end
end

local function isValidNumber(v)
	return v == v and v ~= math.huge and v ~= -math.huge
end

local function isValidVector(v)
	return v and isValidNumber(v.X) and isValidNumber(v.Z)
end

--------------------------------------------------
-- UI HIT TEST (shared by all tactical input)
--------------------------------------------------

local function isOverUI(screenPos)
	local pg = player:FindFirstChildWhichIsA("PlayerGui")
	if not pg then return false end
	local objects = pg:GetGuiObjectsAtPosition(screenPos.X, screenPos.Y)
	for _, obj in ipairs(objects) do
		if obj.Visible ~= false then
			local ancestor = obj
			while ancestor and ancestor ~= pg do
				local n = ancestor.Name
				if n == "ActiveUnit" or n == "ActionPanel" or n == "Inspector"
					or n == "TilePreview" or n == "TurnOrder" or n == "BattleLog"
					or n == "Conditions" or n == "Tooltip" or n == "DevPanel" then
					return true
				end
				ancestor = ancestor.Parent
			end
		end
	end
	return false
end

--------------------------------------------------
-- PUBLIC CAMERA API
--------------------------------------------------

local CameraController = {}


--- Set battlefield bounds explicitly (called by BattleVisualClient if needed)
function CameraController.SetBattlefieldBounds(bounds)
	if bounds and bounds.minX and bounds.maxX and bounds.minZ and bounds.maxZ then
		battleBounds = bounds
		battleBounds.tileSize = bounds.tileSize or 5
		battleBounds.source = bounds.source or "explicit"
		print(string.format("[CameraBounds] source=%s minX=%.1f maxX=%.1f minZ=%.1f maxZ=%.1f tileSize=%d",
			battleBounds.source, battleBounds.minX, battleBounds.maxX, battleBounds.minZ, battleBounds.maxZ, battleBounds.tileSize))
	else
		print("[CameraBounds] WARNING: invalid bounds provided, keeping current")
	end
end

CameraController.IsOverUI = isOverUI

function CameraController.Pan(deltaX, deltaZ)
	if not isActive then return end
	-- Convert screen-relative input to world-space using camera yaw
	-- deltaX = screen right (+), deltaZ = screen forward (-) / backward (+)
	-- screenRight = (cos(yaw), -sin(yaw)), screenForward = (-sin(yaw), -cos(yaw))
	local yawRad = math.rad(yaw)
	local cosY = math.cos(yawRad)
	local sinY = math.sin(yawRad)
	local wx = deltaX * cosY + deltaZ * sinY
	local wz = -deltaX * sinY + deltaZ * cosY
	focus = clampFocus(focus + Vector3.new(wx, 0, wz))
	applyCFrame(false)
end

function CameraController.RotateCW()
	if not isActive then return end
	yaw = (math.round(yaw / ROTATION_SNAP) * ROTATION_SNAP - ROTATION_SNAP) % 360
	applyCFrame(false)
end

function CameraController.RotateCCW()
	if not isActive then return end
	yaw = (math.round(yaw / ROTATION_SNAP) * ROTATION_SNAP + ROTATION_SNAP) % 360
	applyCFrame(false)
end

function CameraController.Zoom(delta)
	if not isActive then return end
	distance = math.clamp(distance - delta, ZOOM_MIN, ZOOM_MAX)
	applyCFrame(false)
end

function CameraController.FocusActiveUnit(worldPos)
	if not isActive then return end
	if not isValidVector(worldPos) then return end
	focus = clampFocus(Vector3.new(worldPos.X, 0, worldPos.Z))
	applyCFrame(false)
	print(string.format("[CameraRecovery] action=focusActive success=true distance=%.0f yaw=%.0f", distance, yaw))
end

function CameraController.FocusSelectedUnit(worldPos)
	if not isActive then return end
	if not isValidVector(worldPos) then
		print("[CameraRecovery] action=focusSelected success=false (invalid position)")
		return
	end
	focus = clampFocus(Vector3.new(worldPos.X, 0, worldPos.Z))
	applyCFrame(false)
	print(string.format("[CameraRecovery] action=focusSelected success=true distance=%.0f yaw=%.0f", distance, yaw))
end

function CameraController.ResetTacticalView(focusPos)
	distance = ZOOM_DEFAULT
	yaw = 0
	if focusPos and isValidVector(focusPos) then
		focus = clampFocus(Vector3.new(focusPos.X, 0, focusPos.Z))
	else
		focus = Vector3.new(0, 0, 0)
	end
	applyCFrame(false)
	print(string.format("[CameraRecovery] action=reset success=true distance=%.0f yaw=%.0f", distance, yaw))
end

function CameraController.FrameTile(tileX, tileY)
	local wx = -20 + (tileX - 0.5) * 5
	local wz = -20 + (tileY - 0.5) * 5
	focus = clampFocus(Vector3.new(wx, 0, wz))
	applyCFrame(false)
end

function CameraController.GetState()
	return { focus=focus, distance=distance, pitch=FIXED_PITCH, yaw=yaw, fov=FIXED_FOV, isActive=isActive, inBattle=inBattle }
end

--------------------------------------------------
-- BATTLE MODE ENTER/EXIT
--------------------------------------------------

local function hideCharacter()
	local char = player.Character
	if not char then return end
	storedCharParts = {}
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			storedCharParts[part] = part.Transparency
			part.Transparency = 1
		elseif part:IsA("Decal") or part:IsA("Texture") then
			storedCharParts[part] = part.Transparency
			part.Transparency = 1
		end
	end
	local hum = char:FindFirstChildWhichIsA("Humanoid")
	if hum then
		storedHumanoidProps = {
			WalkSpeed = hum.WalkSpeed, JumpPower = hum.JumpPower,
			JumpHeight = hum.JumpHeight, UseJumpPower = hum.UseJumpPower,
			AutoRotate = hum.AutoRotate,
		}
		hum.WalkSpeed = 0; hum.JumpPower = 0; hum.JumpHeight = 0; hum.AutoRotate = false
	end
end

local function showCharacter()
	local char = player.Character
	if not char then return end
	for part, t in pairs(storedCharParts) do
		if part and part.Parent then part.Transparency = t end
	end
	storedCharParts = {}
	local hum = char:FindFirstChildWhichIsA("Humanoid")
	if hum and storedHumanoidProps then
		hum.WalkSpeed = storedHumanoidProps.WalkSpeed or 16
		hum.JumpPower = storedHumanoidProps.JumpPower or 50
		hum.JumpHeight = storedHumanoidProps.JumpHeight or 7.2
		hum.UseJumpPower = storedHumanoidProps.UseJumpPower ~= false
		hum.AutoRotate = storedHumanoidProps.AutoRotate ~= false
	end
	storedHumanoidProps = {}
end

local function disableControls()
	pcall(function()
		storedTouchControls = GuiService.TouchControlsEnabled
		GuiService.TouchControlsEnabled = false
		local pm = player:WaitForChild("PlayerScripts"):FindFirstChild("PlayerModule")
		if pm then
			local ctrl = require(pm):GetControls()
			if ctrl and ctrl.Disable then ctrl:Disable() end
		end
	end)
end

local function enableControls()
	pcall(function()
		if storedTouchControls ~= nil then
			GuiService.TouchControlsEnabled = storedTouchControls
			storedTouchControls = nil
		end
		local pm = player:WaitForChild("PlayerScripts"):FindFirstChild("PlayerModule")
		if pm then
			local ctrl = require(pm):GetControls()
			if ctrl and ctrl.Enable then ctrl:Enable() end
		end
	end)
end

function CameraController.EnterBattle(focusPos)
	if inBattle then return end
	inBattle = true
	camera = workspace.CurrentCamera

	-- Store native state
	storedCameraType = camera.CameraType
	storedCameraSubject = camera.CameraSubject
	storedFieldOfView = camera.FieldOfView

	-- Configure tactical camera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = nil
	camera.FieldOfView = FIXED_FOV
	isActive = true

	-- Set initial view
	distance = ZOOM_DEFAULT
	yaw = 0
	if focusPos and isValidVector(focusPos) then
		focus = clampFocus(Vector3.new(focusPos.X, 0, focusPos.Z))
	else
		focus = Vector3.new(0, 0, 0)
	end
	applyCFrame(true)

	-- Disable native controls AFTER camera is valid
	disableControls()
	hideCharacter()

	print(string.format("[CameraState] pitch=%.0f yaw=%.0f fov=%.0f distance=%.0f focus=(%.0f,%.0f,%.0f)",
		FIXED_PITCH, yaw, FIXED_FOV, distance, focus.X, focus.Y, focus.Z))
	print("[CameraController] Battle mode ENTERED.")
end

function CameraController.ExitBattle()
	if not inBattle then return end
	inBattle = false
	isActive = false

	-- Restore camera
	camera.CameraType = storedCameraType or Enum.CameraType.Custom
	local subj = storedCameraSubject
	if subj and not subj.Parent then subj = nil end
	camera.CameraSubject = subj or (player.Character and player.Character:FindFirstChildWhichIsA("Humanoid") or nil)
	if storedFieldOfView then camera.FieldOfView = storedFieldOfView end

	-- Restore character + controls
	showCharacter()
	enableControls()

	-- Clear touch state
	trackedTouches = {}
	pendingTapPos = nil

	print("[CameraController] Battle mode EXITED.")
end

player.CharacterAdded:Connect(function()
	if inBattle then
		task.wait(0.2)
		hideCharacter()
	end
end)

--------------------------------------------------
-- DESKTOP INPUT
--------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if not isActive then return end

	if input.KeyCode == Enum.KeyCode.Q then CameraController.RotateCCW() end
	if input.KeyCode == Enum.KeyCode.E then CameraController.RotateCW() end

	if input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.Up then heldKeys["W"] = true end
	if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then heldKeys["A"] = true end
	if input.KeyCode == Enum.KeyCode.S or input.KeyCode == Enum.KeyCode.Down then heldKeys["S"] = true end
	if input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then heldKeys["D"] = true end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		if not isOverUI(input.Position) then isDraggingRight = true; dragStartPos = input.Position end
	end
	if input.UserInputType == Enum.UserInputType.MouseButton3 then
		if not isOverUI(input.Position) then isDraggingMiddle = true; dragStartPos = input.Position end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then isDraggingRight = false end
	if input.UserInputType == Enum.UserInputType.MouseButton3 then isDraggingMiddle = false end
	if input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.Up then heldKeys["W"] = nil end
	if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then heldKeys["A"] = nil end
	if input.KeyCode == Enum.KeyCode.S or input.KeyCode == Enum.KeyCode.Down then heldKeys["S"] = nil end
	if input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then heldKeys["D"] = nil end
end)

UserInputService.InputChanged:Connect(function(input, gp)
	if not isActive then return end
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		CameraController.Zoom(input.Position.Z * ZOOM_STEP)
	end
	if (isDraggingRight or isDraggingMiddle) and input.UserInputType == Enum.UserInputType.MouseMovement then
		local delta = input.Position - dragStartPos
		dragStartPos = input.Position
		CameraController.Pan(-delta.X * PAN_SPEED, -delta.Y * PAN_SPEED)
	end
end)

RunService.RenderStepped:Connect(function()
	if not isActive then return end
	local dx, dz = 0, 0
	if heldKeys["W"] then dz = dz - 1 end
	if heldKeys["S"] then dz = dz + 1 end
	if heldKeys["A"] then dx = dx - 1 end
	if heldKeys["D"] then dx = dx + 1 end
	if dx ~= 0 or dz ~= 0 then
		-- Normalize diagonal so it's not faster than single-axis
		local mag = math.sqrt(dx * dx + dz * dz)
		dx = (dx / mag) * PAN_KEY_SPEED
		dz = (dz / mag) * PAN_KEY_SPEED
		CameraController.Pan(dx, dz)
	end
end)

--------------------------------------------------
-- TOUCH INPUT (per-touch identity model)
--------------------------------------------------

local function countTracked()
	local n = 0
	for _ in pairs(trackedTouches) do n = n + 1 end
	return n
end

UserInputService.TouchStarted:Connect(function(touch, gameProcessed)
	if not isActive then return end

	-- Check UI blocking (both gp and isOverUI for defense in depth)
	local overUI = isOverUI(touch.Position)
	if gameProcessed or overUI then
		return
	end

	trackedTouches[touch] = {
		startPos = touch.Position,
		prevPos = touch.Position,
		curPos = touch.Position,
		beganOverUI = false,
		exceededDrag = false,
		inMultitouch = false,
	}

	local count = countTracked()


	-- If we now have 2+ touches, mark ALL tracked as multitouch
	if count >= 2 then
		for _, entry in pairs(trackedTouches) do
			entry.inMultitouch = true
			entry.exceededDrag = true -- permanently kill tap
		end
		-- Init aggregate state
		rotationTriggered = false
		lastPinchDist = nil
		lastTwistAngle = nil
	end
end)

UserInputService.TouchEnded:Connect(function(touch)
	local entry = trackedTouches[touch]
	if not entry then
		-- Untracked touch (began over UI or before battle) — ignore completely
		return
	end

	-- Classify BEFORE removing
	local classification = "ignored"
	local tapEmitted = 0

	if not entry.exceededDrag and not entry.inMultitouch then
		-- Valid TAP
		pendingTapPos = touch.Position
		tapEmitted = 1
		classification = "tap"
	elseif entry.inMultitouch then
		classification = "multitouch"
	else
		classification = "pan"
	end

	-- Remove this touch
	trackedTouches[touch] = nil
	local remaining = countTracked()


	-- When multitouch drops to 1 surviving finger, let it pan
	if remaining == 1 then
		lastPinchDist = nil
		lastTwistAngle = nil
		rotationTriggered = false
		for _, e in pairs(trackedTouches) do
			e.inMultitouch = false
			-- Keep exceededDrag = true so the surviving finger
			-- can pan immediately but cannot produce a tap
		end
	end

	-- Reset aggregate state when all fingers released
	if remaining == 0 then
		lastPinchDist = nil
		lastTwistAngle = nil
		rotationTriggered = false

	end
end)

UserInputService.TouchMoved:Connect(function(touch, gameProcessed)
	if not isActive then return end
	local entry = trackedTouches[touch]
	if not entry then return end -- Untracked: ignore

	entry.prevPos = entry.curPos
	entry.curPos = touch.Position

	local count = countTracked()

	if count == 1 and not entry.inMultitouch then
		-- SINGLE FINGER
		local disp = (entry.curPos - entry.startPos).Magnitude
		if not entry.exceededDrag and disp > DRAG_THRESHOLD then
			entry.exceededDrag = true
		end
		if entry.exceededDrag then
			CameraController.Pan(-touch.Delta.X * PAN_SPEED * 0.4, -touch.Delta.Y * PAN_SPEED * 0.4)
		end

	elseif count >= 2 then
		-- TWO FINGERS: collect positions
		local positions = {}
		for _, e in pairs(trackedTouches) do
			table.insert(positions, e.curPos)
		end
		if #positions < 2 then return end

		local p1, p2 = positions[1], positions[2]
		local dist = (p1 - p2).Magnitude

		-- PINCH ZOOM
		if lastPinchDist then
			local pinchDelta = dist - lastPinchDist
			if math.abs(pinchDelta) > 5 then
				CameraController.Zoom(pinchDelta * 0.25)
				lastPinchDist = dist
			end
		else
			lastPinchDist = dist
		end

		-- FIXED ROTATION (one step per gesture)
		if not rotationTriggered then
			local center = (p1 + p2) / 2
			-- Use horizontal movement of the center as rotation signal
			if not lastTwistAngle then
				lastTwistAngle = center.X  -- store initial X
			else
				local deltaX = center.X - lastTwistAngle
				if math.abs(deltaX) > ROTATION_THRESHOLD then
					if deltaX > 0 then
						CameraController.RotateCCW()
					else
						CameraController.RotateCW()
					end
					rotationTriggered = true
				end
			end
		end
	end
end)

--------------------------------------------------
-- TAP INTENT API
--------------------------------------------------

function CameraController.ConsumeTapIntent()
	local pos = pendingTapPos
	pendingTapPos = nil
	return pos
end

function CameraController.WasDrag()
	-- Legacy: check if any tracked touch exceeded drag
	for _, entry in pairs(trackedTouches) do
		if entry.exceededDrag then return true end
	end
	return false
end

function CameraController.GetDragThreshold()
	return DRAG_THRESHOLD
end

print("[CameraController] Module loaded.")
return CameraController
