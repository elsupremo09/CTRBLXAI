-- BoardInput.client.lua
-- Handles cross-platform Cancel input for CTRBLXAI.
--
-- Desktop:
-- Right-click anywhere to cancel or go back.
--
-- Mobile:
-- Use the medieval-fantasy Cancel button in the upper-right top bar.
--
-- Gamepad:
-- ButtonB performs the same Cancel action.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remoteFolder = ReplicatedStorage:WaitForChild("Remotes")

local selectionChangedEvent =
	remoteFolder:WaitForChild("SelectionChanged")

local clearSelectionEvent =
	remoteFolder:WaitForChild("ClearSelection")

local CANCEL_ACTION_NAME = "CancelCurrentSelection"

local selectionIsActive = false
local cancelActionIsBound = false

local existingCancelGui = playerGui:FindFirstChild("CancelGui")

if existingCancelGui then
	existingCancelGui:Destroy()
end

local cancelGui = Instance.new("ScreenGui")
cancelGui.Name = "CancelGui"
cancelGui.ResetOnSpawn = false
cancelGui.ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets
cancelGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
cancelGui.DisplayOrder = 10
cancelGui.Parent = playerGui

local cancelButton = Instance.new("TextButton")
cancelButton.Name = "CancelButton"
cancelButton.AnchorPoint = Vector2.new(1, 0.5)
cancelButton.Position = UDim2.new(1, -8, 0.5, 0)
cancelButton.Size = UDim2.fromOffset(84, 36)
cancelButton.BackgroundColor3 = Color3.fromRGB(70, 43, 27)
cancelButton.BorderSizePixel = 0
cancelButton.AutoButtonColor = true
cancelButton.Text = "Cancel"
cancelButton.TextColor3 = Color3.fromRGB(244, 224, 169)
cancelButton.TextSize = 15
cancelButton.Font = Enum.Font.GothamBold
cancelButton.Visible = false
cancelButton.ZIndex = 10
cancelButton.Parent = cancelGui

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 5)
buttonCorner.Parent = cancelButton

local goldBorder = Instance.new("UIStroke")
goldBorder.Name = "GoldBorder"
goldBorder.Color = Color3.fromRGB(190, 144, 62)
goldBorder.Thickness = 2
goldBorder.Transparency = 0
goldBorder.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
goldBorder.Parent = cancelButton

local buttonGradient = Instance.new("UIGradient")
buttonGradient.Name = "LeatherGradient"
buttonGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(
		0,
		Color3.fromRGB(99, 63, 37)
	),
	ColorSequenceKeypoint.new(
		1,
		Color3.fromRGB(52, 31, 21)
	),
})
buttonGradient.Rotation = 90
buttonGradient.Parent = cancelButton

local function requestCancel()
	if not selectionIsActive then
		return
	end

	clearSelectionEvent:FireServer()
end

local function handleGamepadCancel(
	_actionName,
	inputState,
	_inputObject
)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	if not selectionIsActive then
		return Enum.ContextActionResult.Pass
	end

	requestCancel()

	return Enum.ContextActionResult.Sink
end

local function bindGamepadCancel()
	if cancelActionIsBound then
		return
	end

	cancelActionIsBound = true

	ContextActionService:BindAction(
		CANCEL_ACTION_NAME,
		handleGamepadCancel,
		false,
		Enum.KeyCode.ButtonB
	)
end

local function unbindGamepadCancel()
	if not cancelActionIsBound then
		return
	end

	cancelActionIsBound = false

	ContextActionService:UnbindAction(
		CANCEL_ACTION_NAME
	)
end

local function updateCancelInterface()
	cancelButton.Visible =
		selectionIsActive and UserInputService.TouchEnabled

	if selectionIsActive then
		bindGamepadCancel()
	else
		unbindGamepadCancel()
	end
end

cancelButton.Activated:Connect(function()
	requestCancel()
end)

selectionChangedEvent.OnClientEvent:Connect(function(isSelected)
	selectionIsActive = isSelected
	updateCancelInterface()
end)

UserInputService.InputBegan:Connect(function(
	inputObject,
	gameProcessedEvent
)
	if inputObject.UserInputType
		== Enum.UserInputType.MouseButton2 then

		requestCancel()
		return
	end

	if gameProcessedEvent then
		return
	end
end)

updateCancelInterface()

print("CTRBLXAI client input ready")