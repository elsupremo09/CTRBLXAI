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

	-- Dark Metal Plate panel style
	MetalOuter      = Color3.fromRGB(18, 18, 26),    -- Outer panel frame
	MetalInner      = Color3.fromRGB(26, 26, 36),    -- Inner panel (slightly lighter)
	MetalGlow       = Color3.fromRGB(80, 120, 200),  -- Inner glow tint (blue)
	MetalEdge       = Color3.fromRGB(42, 42, 58),    -- Outer border
	MetalRivet      = Color3.fromRGB(55, 55, 70),    -- Rivet highlight

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

-- Font theme presets
Theme._fontThemes = {
	Tactical = {
		name        = "Tactical",
		label       = "⚔ Tactical",
		Primary     = Enum.Font.Gotham,
		PrimaryBold = Enum.Font.GothamBold,
		Mono        = Enum.Font.Gotham,
		Display     = Enum.Font.GothamBold,
	},
	Chronicle = {
		name        = "Chronicle",
		label       = "📜 Chronicle",
		Primary     = Enum.Font.Fondamento,
		PrimaryBold = Enum.Font.Fondamento,
		Mono        = Enum.Font.Fondamento,
		Display     = Enum.Font.Fondamento,
	},
	Tome = {
		name        = "Tome",
		label       = "📖 Tome",
		Primary     = Enum.Font.Antique,
		PrimaryBold = Enum.Font.Antique,
		Mono        = Enum.Font.Antique,
		Display     = Enum.Font.GrenzeGotisch,
	},
}
Theme._fontThemeOrder = { "Tactical", "Chronicle", "Tome" }
Theme._currentFontTheme = "Tactical"

-- Active font table (updated by SetFontTheme)
Theme.Font = {
	Primary     = Enum.Font.Gotham,
	PrimaryBold = Enum.Font.GothamBold,
	Mono        = Enum.Font.Gotham,
	Display     = Enum.Font.GothamBold,
}

function Theme.SetFontTheme(themeName)
	local preset = Theme._fontThemes[themeName]
	if not preset then return end
	Theme._currentFontTheme = themeName
	Theme.Font.Primary     = preset.Primary
	Theme.Font.PrimaryBold = preset.PrimaryBold
	Theme.Font.Mono        = preset.Mono
	Theme.Font.Display     = preset.Display
end

function Theme.CycleFontTheme()
	local order = Theme._fontThemeOrder
	for i, name in ipairs(order) do
		if name == Theme._currentFontTheme then
			local next = order[(i % #order) + 1]
			Theme.SetFontTheme(next)
			return next
		end
	end
	Theme.SetFontTheme(order[1])
	return order[1]
end

function Theme.GetFontThemeLabel()
	local preset = Theme._fontThemes[Theme._currentFontTheme]
	return preset and preset.label or Theme._currentFontTheme
end

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

--------------------------------------------------
-- VIEWPORT-SCALED TEXT & ELEMENT SIZING
--------------------------------------------------

-- Reference resolution (design target)
local REF_WIDTH = 1920
local viewportWidth = REF_WIDTH
local currentMode = "Desktop"  -- "Desktop", "Compact", "Mobile"

--- Call once per viewport change (UILayoutCoordinator → BattleHUD.ApplyLayout → here)
function Theme.SetViewport(w, h)
	viewportWidth = math.max(w or REF_WIDTH, 800)
	if viewportWidth < 1024 then
		currentMode = "Mobile"
	elseif viewportWidth < 1280 then
		currentMode = "Compact"
	else
		currentMode = "Desktop"
	end
end

--- Returns the current layout mode string.
function Theme.GetMode()
	return currentMode
end

--------------------------------------------------
-- STRICT TYPOGRAPHIC CONTRACT
-- One font family. Six roles. No exceptions.
-- Mobile sizes are LARGER than desktop (small physical screen = bigger text).
--------------------------------------------------

local TEXT_SIZES = {
	--              Desktop  Compact  Mobile
	Title   = {       16,      16,      18   },
	Heading = {       13,      13,      15   },
	Body    = {       11,      11,      13   },
	Small   = {       10,      10,      12   },
	Mono    = {       11,      11,      13   },
	Tiny    = {        9,       9,      11   },
	Badge   = {        7,       7,       9   },
}

local MODE_INDEX = { Desktop = 1, Compact = 2, Mobile = 3 }

Theme.Text = {}

function Theme.Text.Title()   return TEXT_SIZES.Title[MODE_INDEX[currentMode]]   end
function Theme.Text.Heading() return TEXT_SIZES.Heading[MODE_INDEX[currentMode]] end
function Theme.Text.Body()    return TEXT_SIZES.Body[MODE_INDEX[currentMode]]    end
function Theme.Text.Small()   return TEXT_SIZES.Small[MODE_INDEX[currentMode]]   end
function Theme.Text.Mono()    return TEXT_SIZES.Mono[MODE_INDEX[currentMode]]    end
function Theme.Text.Tiny()    return TEXT_SIZES.Tiny[MODE_INDEX[currentMode]]    end
function Theme.Text.Badge()   return TEXT_SIZES.Badge[MODE_INDEX[currentMode]]   end

--------------------------------------------------
-- ELEMENT SIZING (hard mode switch, same principle)
--------------------------------------------------

local ELEM_SIZES = {
	--                 Desktop  Compact  Mobile
	RowTall    = {       40,      38,      44   },
	RowMedium  = {       26,      26,      30   },
	RowSmall   = {       18,      18,      22   },
	RowTiny    = {       14,      14,      18   },
	Portrait   = {       36,      34,      40   },
	IconBtn    = {       26,      26,      30   },
	ToggleBtn  = {       26,      26,      30   },
	Padding    = {        6,       6,       8   },
	PaddingLg  = {        8,       8,      10   },
}

Theme.Elem = {}

function Theme.Elem.RowTall()   return ELEM_SIZES.RowTall[MODE_INDEX[currentMode]]   end
function Theme.Elem.RowMedium() return ELEM_SIZES.RowMedium[MODE_INDEX[currentMode]] end
function Theme.Elem.RowSmall()  return ELEM_SIZES.RowSmall[MODE_INDEX[currentMode]]  end
function Theme.Elem.RowTiny()   return ELEM_SIZES.RowTiny[MODE_INDEX[currentMode]]   end
function Theme.Elem.Portrait()  return ELEM_SIZES.Portrait[MODE_INDEX[currentMode]]  end
function Theme.Elem.IconBtn()   return ELEM_SIZES.IconBtn[MODE_INDEX[currentMode]]   end
function Theme.Elem.ToggleBtn() return ELEM_SIZES.ToggleBtn[MODE_INDEX[currentMode]] end
function Theme.Elem.Padding()   return ELEM_SIZES.Padding[MODE_INDEX[currentMode]]   end
function Theme.Elem.PaddingLg() return ELEM_SIZES.PaddingLg[MODE_INDEX[currentMode]] end

--- Legacy compat: Theme.Scaled(basePx) still works but uses mode-based scaling.
function Theme.Scaled(basePx)
	local multiplier = currentMode == "Mobile" and 1.15 or 1.0
	return math.floor(basePx * multiplier + 0.5)
end
Theme.ScaledPx = Theme.Scaled

return Theme
