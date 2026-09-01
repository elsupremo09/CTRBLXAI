-- UILayoutCoordinator.lua
-- CTRBLXAI | Slice 7 Stage 2 — Pure Layout Calculator
--
-- Stateless ModuleScript. Given a viewport size, returns panel layout values.
-- Does NOT own battle state, connect events, create/destroy panels, or touch Camera.
-- UIController owns viewport observation. BattleHUD owns applying values to instances.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CTRBLXAI_UI = ReplicatedStorage:WaitForChild("CTRBLXAI", 10):WaitForChild("UI", 10)
local UIConstants = require(CTRBLXAI_UI:WaitForChild("UIConstants", 10))

local UILayoutCoordinator = {}

--------------------------------------------------
-- LAYOUT MODE
--------------------------------------------------

function UILayoutCoordinator.GetLayoutMode(viewportSize)
	return UIConstants.GetLayoutMode(viewportSize.X)
end

--------------------------------------------------
-- LAYOUT CALCULATION
--------------------------------------------------

--- Returns a table of panel layout descriptors for the given viewport.
--- Each panel entry: { Size, Position, AnchorPoint }
--- Constraints (min/max) are NOT changed — they remain on the panel instances.
function UILayoutCoordinator.GetLayout(viewportSize)
	local mode = UILayoutCoordinator.GetLayoutMode(viewportSize)
	local w = viewportSize.X
	local h = viewportSize.Y
	local PAD = 6

	if mode == "Desktop" then
		-- Approved layout: right-side panel stack, bottom-center timeline, lower-left log
		return {
			mode = "Desktop",
			ActiveUnit   = { Size = UDim2.new(0.20, 0, 0, 0), Position = UDim2.new(1, -PAD, 0, PAD), AnchorPoint = Vector2.new(1, 0) },
			ActionPanel  = { Size = UDim2.new(0.20, 0, 0, 0), Position = nil, AnchorPoint = Vector2.new(1, 0) }, -- dynamically below ActiveUnit
			Inspector    = { Size = UDim2.new(0.20, 0, 0, 0), Position = nil, AnchorPoint = Vector2.new(1, 0) }, -- dynamically below ActionPanel
			TilePreview  = { Size = UDim2.new(0.20, 0, 0, 0), Position = nil, AnchorPoint = Vector2.new(1, 0) }, -- dynamically below Inspector
			TurnOrder    = { Size = UDim2.fromScale(0.60, 0.10), Position = UDim2.new(0, PAD, 1, -PAD), AnchorPoint = Vector2.new(0, 1) },
			Conditions   = { Size = UDim2.fromScale(0.12, 0.10), Position = UDim2.new(0.60, PAD * 2, 1, -PAD), AnchorPoint = Vector2.new(0, 1) },
			BattleLog    = { Size = UDim2.fromScale(0.25, 0.75), Position = UDim2.new(0, PAD, 0, PAD + 32), AnchorPoint = Vector2.new(0, 0) },
		}

	elseif mode == "CompactLandscape" then
		-- Same as Desktop but narrower panels
		local panelW = math.max(240, math.floor(w * 0.20))
		local panelScale = panelW / w
		return {
			mode = "CompactLandscape",
			ActiveUnit   = { Size = UDim2.new(panelScale, 0, 0, 0), Position = UDim2.new(1, -PAD, 0, PAD), AnchorPoint = Vector2.new(1, 0) },
			ActionPanel  = { Size = UDim2.new(panelScale, 0, 0, 0), Position = nil, AnchorPoint = Vector2.new(1, 0) },
			Inspector    = { Size = UDim2.new(panelScale, 0, 0, 0), Position = nil, AnchorPoint = Vector2.new(1, 0) },
			TilePreview  = { Size = UDim2.new(panelScale, 0, 0, 0), Position = nil, AnchorPoint = Vector2.new(1, 0) },
			TurnOrder    = { Size = UDim2.fromScale(0.60, 0.10), Position = UDim2.new(0, PAD, 1, -PAD), AnchorPoint = Vector2.new(0, 1) },
			Conditions   = { Size = UDim2.fromScale(0.12, 0.10), Position = UDim2.new(0.60, PAD * 2, 1, -PAD), AnchorPoint = Vector2.new(0, 1) },
			BattleLog    = { Size = UDim2.fromScale(0.25, 0.73), Position = UDim2.new(0, PAD, 0, PAD + 32), AnchorPoint = Vector2.new(0, 0) },
		}

	else -- MobileLandscape
		-- Same right-side stack, tighter spacing
		local panelW = math.max(160, math.floor(w * 0.15)) / w  -- fixed 240px as scale fraction
		local PAD_M = 4
		return {
			mode = "MobileLandscape",
			ActiveUnit   = { Size = UDim2.new(panelW, 0, 0, 0), Position = UDim2.new(1, -PAD_M, 0, PAD_M), AnchorPoint = Vector2.new(1, 0) },
			ActionPanel  = { Size = UDim2.new(panelW, 0, 0, 0), Position = nil, AnchorPoint = Vector2.new(1, 0) },
			Inspector    = { Size = UDim2.new(panelW, 0, 0, 0), Position = nil, AnchorPoint = Vector2.new(1, 0) },
			TilePreview  = { Size = UDim2.new(panelW, 0, 0, 0), Position = nil, AnchorPoint = Vector2.new(1, 0) },
			TurnOrder    = { Size = UDim2.fromScale(0.60, 0.12), Position = UDim2.new(0, PAD_M, 1, -PAD_M), AnchorPoint = Vector2.new(0, 1) },
			Conditions   = { Size = UDim2.fromScale(0.12, 0.12), Position = UDim2.new(0.60, PAD_M * 2, 1, -PAD_M), AnchorPoint = Vector2.new(0, 1) },
			BattleLog    = { Size = UDim2.fromScale(0.28, 0.70), Position = UDim2.new(0, PAD_M, 0, PAD_M + 32), AnchorPoint = Vector2.new(0, 0) },
		}
	end
end

return UILayoutCoordinator
