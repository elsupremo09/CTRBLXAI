-- ThemeSwitcher.client.lua
-- CTRBLXAI | Persistent font theme toggle
--
-- Creates a small button in the top-right corner (inside the Roblox top bar area)
-- that cycles between font themes. Persists across all screens (loadout, battle, menus).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local CTRBLXAI_UI = ReplicatedStorage:WaitForChild("CTRBLXAI", 10):WaitForChild("UI", 10)
local Theme       = require(CTRBLXAI_UI:WaitForChild("Theme", 10))

-- Wait for valid viewport before sizing
local function getPlayerGui()
	return player:WaitForChild("PlayerGui")
end

-- Create persistent ScreenGui (IgnoreGuiInset = true to sit in top bar area)
local gui = Instance.new("ScreenGui")
gui.Name = "ThemeSwitcherGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 200  -- above everything
gui.IgnoreGuiInset = true
gui.Parent = getPlayerGui()

local PAD = 6

local btn = Instance.new("TextButton")
btn.Name = "ThemeSwitcher"
btn.Size = UDim2.fromOffset(100, 26)
btn.Position = UDim2.new(1, -PAD, 0, 4)
btn.AnchorPoint = Vector2.new(1, 0)
btn.BackgroundColor3 = Theme.Colors.Surface
btn.BackgroundTransparency = 0.15
btn.Font = Theme.Font.PrimaryBold
btn.TextSize = 11
btn.TextColor3 = Theme.Colors.TextSecondary
btn.Text = Theme.GetFontThemeLabel()
btn.BorderSizePixel = 0
btn.Parent = gui
Instance.new("UICorner", btn).CornerRadius = Theme.CornerRadius.sm

btn.MouseButton1Click:Connect(function()
	Theme.CycleFontTheme()
	btn.Text = Theme.GetFontThemeLabel()
	btn.Font = Theme.Font.PrimaryBold

	-- If BattleHUD is active, re-render it with new fonts
	local BattleHUD = nil
	pcall(function()
		BattleHUD = require(CTRBLXAI_UI:WaitForChild("BattleHUD", 1))
	end)
	if BattleHUD then
		-- Update toggle buttons if they exist
		pcall(function()
			BattleHUD.Render(nil)
			if BattleHUD._lastTimelineEntries then
				BattleHUD.UpdateTimeline(BattleHUD._lastTimelineEntries)
			end
		end)
	end
end)
