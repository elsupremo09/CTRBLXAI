-- UIConstants.lua
-- CTRBLXAI | Slice 7A — Layout and Structural Constants
--
-- Fixed layout values, breakpoints, and panel size presets.
-- Use Theme.lua for visual styling (colors, fonts, spacing).
-- Use UIConstants.lua for structural layout decisions.

local UIConstants = {}

--------------------------------------------------
-- BREAKPOINTS (viewport width thresholds)
--------------------------------------------------

UIConstants.Breakpoints = {
	-- Stage 2 layout modes (width thresholds)
	MobileLandscape  = 1024,  -- Below 1024 = MobileLandscape
	CompactLandscape = 1280,  -- 1024-1279 = CompactLandscape
	Desktop          = 1280,  -- 1280+ = Desktop
}

--------------------------------------------------
-- PANEL SIZES (default desktop dimensions)
--------------------------------------------------

UIConstants.Panels = {
	-- Unit inspector (left side)
	Inspector = {
		Width    = 200,
		MinWidth = 160,
		MaxWidth = 240,
	},

	-- Action bar (bottom)
	ActionBar = {
		Height    = 90,
		MinHeight = 72,
		MaxWidth  = 760,
	},

	-- Timeline (top or left)
	Timeline = {
		SlotSize      = 42,
		ActiveSlotSize = 52,
		MaxSlots      = 14,
		Height        = 60,
	},

	-- Tile information (compact)
	TileInfo = {
		Width  = 160,
		Height = 80,
	},

	-- Tooltip
	Tooltip = {
		MaxWidth  = 220,
		MaxHeight = 160,
	},

	-- Modal
	Modal = {
		Width  = 320,
		Height = 200,
	},

	-- Battle state indicator
	StateIndicator = {
		Width  = 180,
		Height = 28,
	},
}

--------------------------------------------------
-- RESOURCE BAR SIZES
--------------------------------------------------

UIConstants.ResourceBar = {
	-- Billboard bars (3D world)
	Billboard = {
		HPWidth  = 80,
		HPHeight = 8,
		MPWidth  = 60,
		MPHeight = 4,
	},

	-- HUD bars (2D panels)
	HUD = {
		Width  = 140,
		Height = 14,
	},
}

--------------------------------------------------
-- TIMELINE LAYOUT
--------------------------------------------------

UIConstants.Timeline = {
	Direction    = "Horizontal",  -- "Horizontal" or "Vertical"
	Anchor       = "TopRight",    -- Where the timeline lives on screen
	SlotPadding  = 3,
	MaxVisible   = 14,           -- Max portrait slots before scrolling
	ShowRounds   = true,         -- Show round boundary markers
}

--------------------------------------------------
-- ACTION BUTTON LAYOUT
--------------------------------------------------

UIConstants.ActionButton = {
	Width  = 100,
	Height = 55,
	Gap    = 6,
}

--------------------------------------------------
-- FLOATING TEXT
--------------------------------------------------

UIConstants.FloatingText = {
	RiseDistance = 3.5,   -- Studs upward
	Duration    = 0.9,   -- Seconds
	TextSize    = 20,
	CritSize    = 26,
}

--------------------------------------------------
-- TILE HIGHLIGHT
--------------------------------------------------

UIConstants.TileHighlight = {
	Thickness    = 0.15,        -- Part height (studs)
	SizeFraction = 0.85,       -- Fraction of tile covered
	YOffset      = 0.15,       -- Above tile surface (studs)
}

--------------------------------------------------
-- SAFE AREA INSETS (conservative estimates)
--------------------------------------------------

UIConstants.SafeArea = {
	Top    = 44,   -- Status bar / notch
	Bottom = 34,   -- Home indicator
	Left   = 0,
	Right  = 0,
}

--------------------------------------------------
-- HELPER: Get layout category for current viewport
--------------------------------------------------

function UIConstants.GetLayoutMode(viewportWidth)
	if viewportWidth < UIConstants.Breakpoints.MobileLandscape then
		return "MobileLandscape"
	elseif viewportWidth < UIConstants.Breakpoints.CompactLandscape then
		return "CompactLandscape"
	end
	return "Desktop"
end

-- Legacy alias for backward compatibility
function UIConstants.GetLayoutCategory(viewportWidth)
	return UIConstants.GetLayoutMode(viewportWidth)
end

return UIConstants
