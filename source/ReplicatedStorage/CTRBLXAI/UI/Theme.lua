-- Theme.lua
-- CTRBLXAI | Slice 7A — Central Visual Theme
--
-- Single source of truth for all visual styling.
-- Every UI component must reference Theme values instead of hardcoding colors,
-- spacing, fonts, or sizes.
--
-- Visual direction: Restrained dark-fantasy Roblox style.
--   Dark charcoal backgrounds, slightly raised gray panels, muted accents,
--   thin borders, small corner radius, minimal decoration, high readability.

local Theme = {}

--------------------------------------------------
-- COLORS
--------------------------------------------------

Theme.Colors = {
	-- Backgrounds
	Background      = Color3.fromRGB(12, 12, 18),   -- Deepest layer
	Panel           = Color3.fromRGB(22, 22, 32),    -- Standard panel
	PanelRaised     = Color3.fromRGB(32, 32, 44),    -- Elevated panel / hover state
	Surface         = Color3.fromRGB(40, 40, 55),    -- Interactive surfaces (buttons bg)

	-- Borders
	Border          = Color3.fromRGB(50, 50, 65),    -- Subtle default border
	BorderSelected  = Color3.fromRGB(100, 160, 255), -- Selected element (blue)
	BorderFocused   = Color3.fromRGB(255, 230, 80),  -- Active/focused (gold)

	-- Faction
	Player          = Color3.fromRGB(70, 130, 220),  -- Muted blue
	Enemy           = Color3.fromRGB(200, 70, 50),   -- Restrained red-orange
	Neutral         = Color3.fromRGB(140, 140, 140), -- Gray

	-- Text
	TextPrimary     = Color3.fromRGB(230, 230, 235), -- Main readable text
	TextSecondary   = Color3.fromRGB(160, 160, 175), -- Supporting text
	TextDisabled    = Color3.fromRGB(80, 80, 95),    -- Disabled / unavailable
	TextGold        = Color3.fromRGB(255, 220, 80),  -- Emphasis / headers

	-- Resources
	HP              = Color3.fromRGB(60, 190, 70),   -- Health bar fill
	HPLow           = Color3.fromRGB(220, 60, 40),   -- Health critical
	MP              = Color3.fromRGB(70, 120, 220),  -- Mana bar fill
	MPLow           = Color3.fromRGB(140, 80, 200),  -- Mana low

	-- Feedback
	Warning         = Color3.fromRGB(240, 180, 40),  -- Amber warning
	Danger          = Color3.fromRGB(220, 50, 50),   -- Red danger / critical
	Success         = Color3.fromRGB(60, 200, 80),   -- Green success / heal
	Info            = Color3.fromRGB(100, 170, 255),  -- Blue informational

	-- Status effect colors (for floating text / tinting)
	Poison          = Color3.fromRGB(80, 200, 80),
	Burn            = Color3.fromRGB(255, 140, 40),
	Freeze          = Color3.fromRGB(100, 200, 255),
	Silence         = Color3.fromRGB(180, 80, 200),
	Stun            = Color3.fromRGB(255, 255, 100),
	Bleed           = Color3.fromRGB(180, 30, 30),
	Slow            = Color3.fromRGB(150, 150, 200),

	-- Rarity
	RarityCommon    = Color3.fromRGB(160, 160, 160), -- Gray
	RarityUncommon  = Color3.fromRGB(80, 200, 80),   -- Green
	RarityRare      = Color3.fromRGB(70, 140, 255),  -- Blue
	RarityEpic      = Color3.fromRGB(180, 80, 255),  -- Purple
	RarityLegendary = Color3.fromRGB(255, 200, 50),  -- Gold

	-- Misc
	Overlay         = Color3.fromRGB(0, 0, 0),       -- Modal backdrop (use with transparency)
	Defeated        = Color3.fromRGB(60, 60, 60),    -- KO'd unit tint
}

--------------------------------------------------
-- TRANSPARENCY PRESETS
--------------------------------------------------

Theme.Transparency = {
	Solid           = 0,
	PanelBg        = 0.05,
	PanelOverlay   = 0.15,
	ButtonDisabled = 0.5,
	Highlight      = 0.45,
	HighlightFaint = 0.65,
	Overlay        = 0.4,
	Hidden         = 1,
}

--------------------------------------------------
-- SPACING (pixel values)
--------------------------------------------------

Theme.Spacing = {
	xs = 2,
	sm = 4,
	md = 8,
	lg = 12,
	xl = 16,
	xxl = 24,
}

--------------------------------------------------
-- CORNER RADIUS
--------------------------------------------------

Theme.CornerRadius = {
	sm = UDim.new(0, 4),
	md = UDim.new(0, 6),
	lg = UDim.new(0, 8),
	xl = UDim.new(0, 12),
	full = UDim.new(0.5, 0), -- Circular / pill
}

--------------------------------------------------
-- BORDER THICKNESS
--------------------------------------------------

Theme.BorderThickness = {
	Default  = 1,
	Selected = 2,
	Active   = 2,
}

--------------------------------------------------
-- FONTS
--------------------------------------------------

Theme.Font = {
	Primary     = Enum.Font.SourceSans,
	PrimaryBold = Enum.Font.SourceSansBold,
	Mono        = Enum.Font.RobotoMono,
	Display     = Enum.Font.GothamBold,
}

--------------------------------------------------
-- TEXT SIZES
--------------------------------------------------

Theme.TextSize = {
	xs    = 10,
	sm    = 12,
	md    = 14,
	lg    = 18,
	xl    = 24,
	title = 28,
}

--------------------------------------------------
-- ANIMATION DURATIONS (seconds)
--------------------------------------------------

Theme.Animation = {
	Fast   = 0.15,
	Normal = 0.3,
	Slow   = 0.6,
	Bar    = 0.4,   -- Resource bar fill
	Float  = 0.9,   -- Floating text lifespan
}

--------------------------------------------------
-- MINIMUM SIZES (for touch targets)
--------------------------------------------------

Theme.MinSize = {
	TouchTarget  = 44,  -- Minimum tappable area (px)
	ButtonWidth  = 80,
	ButtonHeight = 36,
	IconButton   = 40,
}

--------------------------------------------------
-- DISPLAY ORDER (ScreenGui layering)
--------------------------------------------------

Theme.DisplayOrder = {
	Background  = 1,
	HUD         = 10,
	Inspector   = 20,
	ActionBar   = 30,
	Timeline    = 35,
	Tooltip     = 50,
	AimOverlay  = 60,
	Prediction  = 65,
	Modal       = 80,
	Notification = 90,
}

--------------------------------------------------
-- HELPER: Get rarity color by name
--------------------------------------------------

function Theme.GetRarityColor(rarity)
	local map = {
		Common    = Theme.Colors.RarityCommon,
		Uncommon  = Theme.Colors.RarityUncommon,
		Rare      = Theme.Colors.RarityRare,
		Epic      = Theme.Colors.RarityEpic,
		Legendary = Theme.Colors.RarityLegendary,
	}
	return map[rarity] or Theme.Colors.RarityCommon
end

--------------------------------------------------
-- HELPER: Get side/faction color
--------------------------------------------------

function Theme.GetSideColor(side)
	if side == "Player" then
		return Theme.Colors.Player
	elseif side == "Enemy" then
		return Theme.Colors.Enemy
	end
	return Theme.Colors.Neutral
end

--------------------------------------------------
-- HELPER: Get status color
--------------------------------------------------

function Theme.GetStatusColor(statusId)
	local map = {
		Poison  = Theme.Colors.Poison,
		Burn    = Theme.Colors.Burn,
		Freeze  = Theme.Colors.Freeze,
		Frozen  = Theme.Colors.Freeze,
		Silence = Theme.Colors.Silence,
		Mute    = Theme.Colors.Silence,
		Stun    = Theme.Colors.Stun,
		Bleed   = Theme.Colors.Bleed,
		Slow    = Theme.Colors.Slow,
		Guard   = Color3.fromRGB(100, 180, 240),
	}
	return map[statusId] or Theme.Colors.Info
end

--------------------------------------------------
-- HELPER: Get HP bar color based on ratio
--------------------------------------------------

function Theme.GetHPColor(ratio)
	if ratio <= 0.25 then
		return Theme.Colors.HPLow
	elseif ratio <= 0.5 then
		return Theme.Colors.Warning
	end
	return Theme.Colors.HP
end

return Theme
