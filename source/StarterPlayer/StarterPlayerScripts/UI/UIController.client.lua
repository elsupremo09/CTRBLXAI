-- UIController.client.lua
-- CTRBLXAI | Slice 7A — UI System Coordinator (Stub)
--
-- This module will eventually coordinate all HUD screens, respond to
-- battle events, and manage screen layout. In Slice 7A it only:
--   1. Verifies all UI modules load without error
--   2. Prints a confirmation to the Output window
--   3. Exposes the module table for future use
--
-- No existing behavior is modified. BattleVisualClient.client.lua
-- continues to run independently until Slice 7B migrates sections here.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

--------------------------------------------------
-- MODULE LOADING (verify all 7A modules import cleanly)
--------------------------------------------------

local CTRBLXAI_UI = ReplicatedStorage
	:WaitForChild("CTRBLXAI", 10)
	:WaitForChild("UI", 10)

local Theme        = require(CTRBLXAI_UI:WaitForChild("Theme", 10))
local UIComponents = require(CTRBLXAI_UI:WaitForChild("UIComponents", 10))
local UIFormatting = require(CTRBLXAI_UI:WaitForChild("UIFormatting", 10))
local UIConstants  = require(CTRBLXAI_UI:WaitForChild("UIConstants", 10))

--------------------------------------------------
-- VIEWPORT DETECTION
--------------------------------------------------

local camera = workspace.CurrentCamera
local viewportSize = camera and camera.ViewportSize or Vector2.new(1920, 1080)
local layoutCategory = UIConstants.GetLayoutCategory(viewportSize.X)

--------------------------------------------------
-- INITIALIZATION CONFIRMATION
--------------------------------------------------

print("[CTRBLXAI UI] Slice 7A modules loaded successfully.")
print(string.format(
	"[CTRBLXAI UI] Viewport: %dx%d | Layout: %s",
	math.round(viewportSize.X),
	math.round(viewportSize.Y),
	layoutCategory
))
print(string.format(
	"[CTRBLXAI UI] Theme colors: %d | Components: %d functions | Formatting: %d functions",
	-- Count table entries as a basic sanity check
	(function()
		local count = 0
		for _ in pairs(Theme.Colors) do count = count + 1 end
		return count
	end)(),
	(function()
		local count = 0
		for _, v in pairs(UIComponents) do
			if type(v) == "function" then count = count + 1 end
		end
		return count
	end)(),
	(function()
		local count = 0
		for _, v in pairs(UIFormatting) do
			if type(v) == "function" then count = count + 1 end
		end
		return count
	end)()
))

--------------------------------------------------
-- FIXTURE DEMO (optional: renders sample components to confirm visuals)
-- Uncomment the block below to see test components on screen.
-- Remove or disable before Slice 7B integration.
--------------------------------------------------

--[[
local demoGui = Instance.new("ScreenGui")
demoGui.Name = "UI7A_Demo"
demoGui.ResetOnSpawn = false
demoGui.DisplayOrder = 999
demoGui.Parent = player:WaitForChild("PlayerGui")

-- Sample panel
local panel = UIComponents.Panel({
	size = UDim2.fromOffset(240, 300),
	position = UDim2.new(0.5, -120, 0.5, -150),
	variant = "default",
	name = "DemoPanel",
})
panel.Parent = demoGui

-- Sample resource bars inside panel
local hpBar = UIComponents.ResourceBar({
	current = 75, max = 120, showText = true,
	size = UDim2.new(1, -16, 0, 16),
})
hpBar.Position = UDim2.new(0, 8, 0, 10)
hpBar.Parent = panel

local mpBar = UIComponents.ResourceBar({
	current = 12, max = 40,
	color = Theme.Colors.MP,
	showText = true,
	size = UDim2.new(1, -16, 0, 12),
})
mpBar.Position = UDim2.new(0, 8, 0, 32)
mpBar.Parent = panel

-- Sample action button
local atkBtn = UIComponents.ActionButton({
	text = "Attack", subtext = "RT:80",
	color = Theme.Colors.Enemy, enabled = true,
})
atkBtn.Position = UDim2.new(0, 8, 0, 56)
atkBtn.Parent = panel

-- Sample disabled button
local guardBtn = UIComponents.ActionButton({
	text = "Guard", subtext = "1 AP",
	enabled = false,
})
guardBtn.Position = UDim2.new(0, 116, 0, 56)
guardBtn.Parent = panel

-- Sample status icons
local poisonIcon = UIComponents.StatusIcon({ statusId = "Poison", remainingTurns = 4 })
poisonIcon.Position = UDim2.new(0, 8, 0, 120)
poisonIcon.Parent = panel

local burnIcon = UIComponents.StatusIcon({ statusId = "Burn", remainingTurns = 2 })
burnIcon.Position = UDim2.new(0, 34, 0, 120)
burnIcon.Parent = panel

-- Sample tooltip
local tip = UIComponents.Tooltip({
	title = "Power Strike",
	lines = {"Physical damage", "MP: 3 | RT: 60", "Range: 1 | Single"},
})
tip.Position = UDim2.new(0, 8, 0, 150)
tip.AnchorPoint = Vector2.new(0, 0)
tip.Parent = panel

-- Sample warning
local warn = UIComponents.WarningPanel({
	text = "Channel will end your turn!",
	severity = "warning",
	size = UDim2.new(1, -16, 0, 32),
})
warn.Position = UDim2.new(0, 8, 0, 260)
warn.Parent = panel

print("[CTRBLXAI UI] Demo panel rendered. Disable in UIController for production.")
--]]

--------------------------------------------------
-- PUBLIC API (for future Slice 7B+ use)
--------------------------------------------------

local UIController = {}

UIController.Theme        = Theme
UIController.Components   = UIComponents
UIController.Formatting   = UIFormatting
UIController.Constants    = UIConstants
UIController.Layout       = layoutCategory
UIController.ViewportSize = viewportSize

--- Refresh layout category (call on viewport resize)
function UIController.RefreshLayout()
	local cam = workspace.CurrentCamera
	if cam then
		viewportSize = cam.ViewportSize
		layoutCategory = UIConstants.GetLayoutCategory(viewportSize.X)
		UIController.Layout = layoutCategory
		UIController.ViewportSize = viewportSize
	end
end

return UIController
