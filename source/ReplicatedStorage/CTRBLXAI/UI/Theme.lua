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

	-- UI element backgrounds
	BadgeBg         = Color3.fromRGB(0, 0, 0),       -- Level badges, name strip overlays
	SelectedItem    = Color3.fromRGB(40, 35, 20),     -- Selected inventory item (gold-tint)
	EmptySlot       = Color3.fromRGB(15, 15, 22),     -- Empty equipment tile
	LockedSlot      = Color3.fromRGB(10, 10, 15),     -- Locked consumable slot

	-- Battle tile highlights
	TileMove        = Color3.fromRGB(50, 100, 170),   -- Movement range (blue)
	TileTarget      = Color3.fromRGB(200, 170, 50),   -- Valid target (gold)
	TileSelected    = Color3.fromRGB(255, 220, 60),   -- Selected tile (bright gold)
	TileAOE         = Color3.fromRGB(200, 100, 40),   -- Area of effect (orange)
	TileInvalid     = Color3.fromRGB(100, 30, 30),    -- Invalid target (dark red)

	-- Entity portrait backgrounds (map objects/hazards)
	EntityObject    = Color3.fromRGB(50, 50, 30),     -- Map object
	EntityHazard    = Color3.fromRGB(60, 40, 100),    -- Hazard
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
	xs = UDim.new(0, 3),
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
		-- DoTs
		Poison     = Theme.Colors.Poison,
		Venom      = Theme.Colors.Poison,
		Burn       = Theme.Colors.Burn,
		Bleed      = Theme.Colors.Bleed,
		Raptured   = Theme.Colors.Bleed,
		Wounded    = Theme.Colors.Bleed,
		-- CC / Debuffs
		Freeze     = Theme.Colors.Freeze,
		Frozen     = Theme.Colors.Freeze,
		Silence    = Theme.Colors.Silence,
		Mute       = Theme.Colors.Silence,
		Stun       = Theme.Colors.Stun,
		Slow       = Theme.Colors.Slow,
		Blind      = Color3.fromRGB(120, 100, 140),
		Confuse    = Color3.fromRGB(200, 120, 200),
		Pinned     = Color3.fromRGB(160, 120, 80),
		Crippled   = Color3.fromRGB(160, 120, 80),
		Disarmed   = Color3.fromRGB(160, 120, 80),
		Petrify    = Color3.fromRGB(140, 140, 140),
		Sleep      = Color3.fromRGB(120, 140, 200),
		Weakened   = Color3.fromRGB(180, 100, 100),
		Cursed     = Color3.fromRGB(160, 60, 180),
		Wet        = Color3.fromRGB(80, 160, 220),
		Drowning   = Color3.fromRGB(40, 80, 160),
		-- Buffs
		Guard      = Color3.fromRGB(100, 180, 240),
		Haste      = Color3.fromRGB(80, 220, 180),
		Frenzy     = Color3.fromRGB(220, 100, 60),
		Hide       = Color3.fromRGB(120, 120, 140),
		Blessed    = Color3.fromRGB(240, 220, 100),
		Flight     = Color3.fromRGB(180, 220, 255),
		Regeneration = Color3.fromRGB(80, 220, 120),
		Recharge   = Color3.fromRGB(100, 180, 240),
		Rush       = Color3.fromRGB(255, 180, 60),
		Enlightened = Color3.fromRGB(240, 240, 180),
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


--------------------------------------------------
-- PANEL FRAME CONSTANTS (Slice 7 — locked)
--------------------------------------------------

Theme.PanelFrame = {
	Asset       = "rbxassetid://96315850586636",
	SliceCenter = Rect.new(163, 163, 861, 861),
	SliceScale  = 0.06,
	BgColor     = Color3.fromRGB(0, 0, 0),
	BgTransparency = 0.15,
	ImageTransparency = 0,
	MinPadding  = 10,
}

-- Creates a standard ornate panel frame (ImageLabel).
-- Usage: Theme.MakePanel(name, size, position, anchor, parent, opts)
--   opts.sliceScale: override (should NOT be used — consistency rule)
--   opts.noBg: if true, BackgroundTransparency = 1 (decorative border only)
--   opts.autoY: enables AutomaticSize.Y with min/max constraints
function Theme.MakePanel(name, size, position, anchor, parent, opts)
	opts = opts or {}
	local pf = Theme.PanelFrame
	local f = Instance.new("ImageLabel")
	f.Name = name or "Panel"
	f.Size = size
	f.Position = position or UDim2.new(0, 0, 0, 0)
	f.AnchorPoint = anchor or Vector2.new(0, 0)
	f.Image = pf.Asset
	f.ScaleType = Enum.ScaleType.Slice
	f.SliceCenter = pf.SliceCenter
	f.SliceScale = pf.SliceScale
	f.BackgroundColor3 = pf.BgColor
	f.BackgroundTransparency = opts.noBg and 1 or pf.BgTransparency
	f.ImageTransparency = pf.ImageTransparency
	f.BorderSizePixel = 0
	f.Active = true
	f.ClipsDescendants = not opts.autoY
	f.Parent = parent
	if opts.autoY then
		f.AutomaticSize = Enum.AutomaticSize.Y
		local c = Instance.new("UISizeConstraint", f)
		c.MinSize = Vector2.new(opts.minW or 180, opts.minH or 60)
		c.MaxSize = Vector2.new(opts.maxW or 260, opts.maxH or 400)
	end
	return f
end

-- Creates a decorative screen border overlay (ornate corners, no fill).
-- Usage: Theme.MakeScreenBorder(parent)
function Theme.MakeScreenBorder(parent)
	local pf = Theme.PanelFrame
	local f = Instance.new("ImageLabel")
	f.Name = "ScreenBorder"
	f.Size = UDim2.new(1, 4, 1, 4)
	f.Position = UDim2.new(0, -2, 0, -2)
	f.Image = pf.Asset
	f.ScaleType = Enum.ScaleType.Slice
	f.SliceCenter = pf.SliceCenter
	f.SliceScale = pf.SliceScale
	f.BackgroundTransparency = 1
	f.ImageTransparency = pf.ImageTransparency
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = 10
	f.Parent = parent
	return f
end

--------------------------------------------------
-- FULL-SCREEN PATTERN
--------------------------------------------------
-- Standard full-screen layout used by Equipment, Info, Skills,
-- and any future full-screen panel.  IgnoreGuiInset = false so
-- content starts below the Roblox top bar.

Theme.FullScreen = {
	DisplayOrder     = 100,
	IgnoreGuiInset   = false,
	BackgroundColor  = Theme.Colors.Background,
	BackgroundTransparency = 0,
	-- Positional gap between adjacent panels (px).
	-- Panels touch at 0; their ornate borders create a natural divider.
	PanelGap         = 0,
}

--------------------------------------------------
-- PORTRAIT / TILE DESIGN RULES
--------------------------------------------------
-- Level badge position: ALWAYS upper-left corner of any portrait or
-- item tile (units and items alike). No exceptions.
Theme.LevelBadgeAnchor = "TopLeft"   -- reference constant (enforced by convention)

--------------------------------------------------
-- ITEM TILE PRESENTATION RULES
--------------------------------------------------
-- Standard format for displaying any item (inventory, equipped gear,
-- shops, victory loot, battle inspector, trade, etc.)
--
-- Layout (top to bottom):
--   [Level badge]  upper-left corner, small text, left-aligned
--   [Icon]         centered horizontally, vertically ~15% from top
--   [Name]         bottom edge of tile, centered, rarity-colored text
--
-- Background:  rarity color at 75% transparency (subtle tint)
-- Border:      UIStroke colored by rarity (1.5px), gold 2px when selected
-- Corner:      4px radius
--
-- Any deviation is a bug, not a design choice.
Theme.ItemTile = {
	BgTransparency   = 0.75,      -- rarity color shown at this transparency
	SelectedBgColor  = Color3.fromRGB(40, 35, 20),
	SelectedBgTransparency = 0.05,
	StrokeThickness  = 1.5,
	SelectedStrokeThickness = 2,
	CornerRadius     = 4,
	IconYScale       = 0.15,      -- icon vertical position (scale from top)
	NameFromBottom   = 14,        -- name label offset from bottom edge (px)
	NameBgColor      = Color3.fromRGB(0, 0, 0),
	NameBgTransparency = 0.4,
	NameTextColor    = Theme.Colors.TextPrimary,  -- white, always
	NameAlignment    = "Left",    -- left-aligned, never centered
}

--- Creates a standard full-screen ScreenGui + root Frame + decorative border.
--- Returns screenGui, rootFrame.
--- Usage:
---   local sg, root = Theme.MakeFullScreen("LoadoutScreen", parent)
function Theme.MakeFullScreen(name, parent)
	local sg = Instance.new("ScreenGui")
	sg.Name = name or "FullScreen"
	sg.ResetOnSpawn = false
	sg.DisplayOrder = Theme.FullScreen.DisplayOrder
	sg.IgnoreGuiInset = Theme.FullScreen.IgnoreGuiInset
	sg.Parent = parent

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Theme.FullScreen.BackgroundColor
	root.BackgroundTransparency = Theme.FullScreen.BackgroundTransparency
	root.Parent = sg

	Theme.MakeScreenBorder(root)

	return sg, root
end

--------------------------------------------------
-- TAB BAR PATTERN
--------------------------------------------------
-- Sits in the Roblox top-bar safe area (IgnoreGuiInset = true).
-- Positioned to leave a 2px gap above the full-screen panel below.

Theme.TabBar = {
	DisplayOrder     = 150,
	PanelWidth       = 360,
	PanelHeight      = 45,
	PositionXScale   = 0.5,
	PositionXOffset  = 60,   -- right of center (avoids Roblox top-left buttons)
	PositionY        = 14,   -- leaves 2px gap above IgnoreGuiInset=false content
	InnerPadX        = 8,
	InnerPadY        = 3,
	TabWidth         = 110,
	TabSpacing       = 4,
	TabTextSize      = 13,
	ActiveColor      = Theme.Colors.TextGold,
	InactiveColor    = Theme.Colors.TextSecondary,
	UnderlineHeight  = 2,
}

--- Creates a standard tab bar ScreenGui + ornate panel.
--- Returns tabBarGui, tabPanel (the ImageLabel to parent tab content into).
function Theme.MakeTabBar(name, parent)
	local tb = Theme.TabBar
	local sg = Instance.new("ScreenGui")
	sg.Name = name or "TabBar"
	sg.ResetOnSpawn = false
	sg.DisplayOrder = tb.DisplayOrder
	sg.IgnoreGuiInset = true
	sg.Parent = parent

	local panel = Theme.MakePanel("TabPanel",
		UDim2.new(0, tb.PanelWidth, 0, tb.PanelHeight),
		UDim2.new(tb.PositionXScale, tb.PositionXOffset, 0, tb.PositionY),
		Vector2.new(0.5, 0), sg)

	return sg, panel
end

--------------------------------------------------
-- THEMED BUTTONS (9-slice ImageButton)
--------------------------------------------------

Theme.ButtonAssets = {
	Primary   = { Asset = "rbxassetid://128127407312284" },  -- gold/bronze (equip, attach, confirm)
	Secondary = { Asset = "rbxassetid://79828905582448" },    -- dark charcoal (back, cancel)
	Tertiary  = { Asset = "rbxassetid://74754968977134" },   -- dark blue/steel (compare, swap)
}

-- [DIAG] Asset ID dump at load time
print("[DIAG-ASSETS] Primary   = " .. Theme.ButtonAssets.Primary.Asset .. " (NEW trimmed 200x48)")
print("[DIAG-ASSETS] Secondary = " .. Theme.ButtonAssets.Secondary.Asset .. " (NEW trimmed 200x48)")
print("[DIAG-ASSETS] Tertiary  = " .. Theme.ButtonAssets.Tertiary.Asset .. " (NEW trimmed 200x48)")
print("[DIAG-ASSETS] BTN_SLICE_CENTER = " .. tostring(BTN_SLICE_CENTER) .. " (matches 200x48 source)")

-- Shared SliceCenter for all button assets (adjust if 9-slice guides differ)
local BTN_SLICE_CENTER = Rect.new(12, 12, 188, 36)

-- ============ FOOTER BUTTON BAR CONFIG ============
-- All screens must use these values for bottom-right button bars.
-- Position: anchored (1,1) at screen bottom-right with 8px margin.
Theme.FooterBar = {
	BTN_W   = 96,
	BTN_H   = 35,
	BTN_GAP = 2,
	PAD     = 8,     -- margin from screen edge
}

-- style: "Primary", "Secondary", or "Tertiary"
function Theme.MakeButton(parent, text, style, onClick, opts)
	opts = opts or {}
	local asset = Theme.ButtonAssets[style] or Theme.ButtonAssets.Secondary

	local btn = Instance.new("ImageButton")
	btn.Name = opts.name or ("Btn_" .. text)
	btn.Size = opts.size or UDim2.new(0, 80, 0, 44)
	btn.Position = opts.position or UDim2.new(0, 0, 0, 0)
	btn.AnchorPoint = opts.anchor or Vector2.new(0, 0)
	btn.Image = asset.Asset
	btn.ScaleType = Enum.ScaleType.Slice
	btn.SliceCenter = BTN_SLICE_CENTER
	btn.SliceScale = 1
	btn.ImageColor3 = Color3.new(1, 1, 1)
	btn.BackgroundTransparency = 1
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Parent = parent

	-- State handling: hover, press, disabled
	if opts.disabled then
		btn.ImageTransparency = 0.5
		btn.Active = false
		btn.ImageColor3 = Color3.fromRGB(120, 120, 120)
	else
		local normalY = btn.Position.Y
		btn.MouseEnter:Connect(function()
			btn.ImageColor3 = Color3.fromRGB(230, 230, 230)
		end)
		btn.MouseLeave:Connect(function()
			btn.ImageColor3 = Color3.new(1, 1, 1)
		end)
		btn.MouseButton1Down:Connect(function()
			btn.ImageColor3 = Color3.fromRGB(180, 180, 180)
			btn.Position = btn.Position + UDim2.new(0, 0, 0, 2)
		end)
		btn.MouseButton1Up:Connect(function()
			btn.ImageColor3 = Color3.new(1, 1, 1)
			btn.Position = btn.Position - UDim2.new(0, 0, 0, 2)
		end)
	end

	-- Text label: child of button, centered, with padding for 9-slice borders
	local lbl = Instance.new("TextLabel")
	lbl.Name = "Label"
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Theme.Font.PrimaryBold
	lbl.TextScaled = false
	lbl.TextSize = Theme.Text.Body()
	lbl.TextTruncate = Enum.TextTruncate.None
	if opts.textColor then
		lbl.TextColor3 = opts.textColor
	elseif style == "Primary" then
		lbl.TextColor3 = Theme.Colors.TextGold
	elseif style == "Secondary" then
		lbl.TextColor3 = Theme.Colors.TextSecondary
	else
		lbl.TextColor3 = Theme.Colors.TextPrimary
	end
	lbl.Text = string.upper(text)
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.Parent = btn

	-- Padding so text doesn't enter 12px slice border region
	local lblPad = Instance.new("UIPadding")
	lblPad.PaddingLeft = UDim.new(0, 14)
	lblPad.PaddingRight = UDim.new(0, 14)
	lblPad.PaddingTop = UDim.new(0, 6)
	lblPad.PaddingBottom = UDim.new(0, 6)
	lblPad.Parent = lbl

	-- Fixed TextSize from Theme.Text.Body()

	-- [DIAG] Button creation dump
	print(("[DIAG-BTN] Created: %s | Style=%s | Asset=%s"):format(
		btn:GetFullName(), style or "nil", tostring(btn.Image)))
	print(("[DIAG-BTN]   Size=%s | SliceCenter=%s | SliceScale=%s"):format(
		tostring(btn.Size), tostring(btn.SliceCenter), tostring(btn.SliceScale)))
	print(("[DIAG-BTN]   ImageColor3=%s | ImageTransparency=%s | AutoButtonColor=%s"):format(
		tostring(btn.ImageColor3), tostring(btn.ImageTransparency), tostring(btn.AutoButtonColor)))
	print(("[DIAG-BTN]   ImageRectSize=%s | ImageRectOffset=%s"):format(
		tostring(btn.ImageRectSize), tostring(btn.ImageRectOffset)))
	task.defer(function()
		if btn and btn.Parent then
			print(("[DIAG-BTN-DEFERRED] %s | AbsPos=%s | AbsSize=%s | Visible=%s | IsLoaded=%s"):format(
				btn:GetFullName(),
				tostring(btn.AbsolutePosition), tostring(btn.AbsoluteSize),
				tostring(btn.Visible), tostring(btn.IsLoaded)))
		end
	end)

	if onClick then
		btn.MouseButton1Click:Connect(onClick)
	end

	return btn
end

--------------------------------------------------
-- ICONS (uploaded image assets)
--------------------------------------------------

Theme.Icons = {
	-- Equipment slot / type filters
	MainHand   = "rbxassetid://107712701709286",
	OffHand    = "rbxassetid://98983861153491",
	Head       = "rbxassetid://103490891066080",
	Torso      = "rbxassetid://129417807804589",
	Arms       = "rbxassetid://83459049184332",
	Legs       = "rbxassetid://96798091456636",
	Accessory  = "rbxassetid://96470544764943",
	Consumable = "rbxassetid://128189551113145",
	Doctrine   = "rbxassetid://76800665797153",
	-- Card types
	SkillCard  = "rbxassetid://88268068619196",
	AugmentCard = "rbxassetid://85750066155505",
	-- Filter reset
	AllTypes   = "rbxassetid://126425312270409",
	-- Primary stats
	STR = "rbxassetid://113370285263658",
	INT = "rbxassetid://123655246718422",
	DEX = "rbxassetid://88598304062639",
	AGI = "rbxassetid://105014331313013",
	VIT = "rbxassetid://89015702504702",
	LUK = "rbxassetid://133750248203590",
	-- Navigation / UI
	Sort       = "rbxassetid://85887130565247",
	Filter     = "rbxassetid://109789920233574",
	Expand     = "rbxassetid://75163824424401",
	Collapse   = "rbxassetid://81689987316999",
	ArrowLeft  = "rbxassetid://109201725784401",
	ArrowRight = "rbxassetid://140157391488573",
	-- Skill type / element icons
	Damage     = "rbxassetid://135504525921846",
	Heal       = "rbxassetid://83266476873580",
	Buff       = "rbxassetid://120381762395957",
	Debuff     = "rbxassetid://115587565920808",
	Utility    = "rbxassetid://88423697133074",
	Fire       = "rbxassetid://98928388908694",
	Ice        = "rbxassetid://80553337901604",
	Electric   = "rbxassetid://80992677701740",
	Holy       = "rbxassetid://101839417852763",
	Dark       = "rbxassetid://101952109436543",
	Poison     = "rbxassetid://74613503786638",
	Physical   = "rbxassetid://112711726025191",
	Reset      = "rbxassetid://82195895256938",
}

--------------------------------------------------
-- TERRAIN TEXTURES (uploaded tile surface images)
--------------------------------------------------

Theme.Terrain = {
	["Clear"]          = "rbxassetid://109805975558014",
	["Grassland"]      = "rbxassetid://128007269403177",
	["Clover Field"]   = "rbxassetid://109662805904614",
	["Forest"]         = "rbxassetid://135752092589962",
	["Wooden Floor"]   = "rbxassetid://126612632552137",
	["Rocky"]          = "rbxassetid://90522759746156",
	["Sand"]           = "rbxassetid://130402247622009",
	["Mud"]            = "rbxassetid://103981896145024",
	["Dirt Road"]      = "rbxassetid://70967889930713",
	["Stone Road"]     = "rbxassetid://91078246561441",
	["Shallow Water"]  = "rbxassetid://133104312443373",
	["Deep Water"]     = "rbxassetid://91104299895108",
	["Swamp"]          = "rbxassetid://102784702693557",
	["Ice"]            = "rbxassetid://111074337572921",
	["Metal"]          = "rbxassetid://109801126120884",
	["Molten"]         = "rbxassetid://102728788006487",
	["Magic Circle"]   = "rbxassetid://83344810206782",
	["Tainted Ground"] = "rbxassetid://78418011585017",
	["Cracked Ground"] = "rbxassetid://112911396208647",
	["Quicksand"]      = "rbxassetid://125706353174532",
}

--------------------------------------------------
-- STYLESHEET LINK HELPER
-- Call on any ScreenGui to enable StyleSheet rules.
-- Only needed when using tag-based styling (Phase 2+).
--------------------------------------------------

function Theme.LinkStyleSheet(screenGui)
	local styleOk, StyleBootstrap = pcall(function()
		return require(game:GetService("ReplicatedStorage")
			:WaitForChild("CTRBLXAI", 5):WaitForChild("Shared", 5)
			:WaitForChild("StyleBootstrap", 5))
	end)
	if styleOk and StyleBootstrap and StyleBootstrap.Link then
		StyleBootstrap.Link(screenGui)
	end
end

--------------------------------------------------
-- STYLESHEET BRIDGE (Phase 3)
-- Called by StyleBootstrap after Init() to bind Theme.Colors
-- to StyleSheet token values. All existing Theme.Colors.X refs
-- continue to work but now read from the canonical token source.
--------------------------------------------------

function Theme.BindToStyleSheet(tokenSheet)
	if not tokenSheet then
		warn("[Theme] BindToStyleSheet called with nil tokenSheet")
		return
	end

	-- Replace each color in Theme.Colors with the token value
	local bound = 0
	for key, currentValue in pairs(Theme.Colors) do
		local tokenValue = tokenSheet:GetAttribute(key)
		if tokenValue and typeof(tokenValue) == "Color3" then
			Theme.Colors[key] = tokenValue
			bound = bound + 1
		end
	end

	-- Listen for token changes (hot-reload support)
	tokenSheet.AttributeChanged:Connect(function(attrName)
		if Theme.Colors[attrName] then
			local newValue = tokenSheet:GetAttribute(attrName)
			if newValue and typeof(newValue) == "Color3" then
				Theme.Colors[attrName] = newValue
			end
		end
	end)

	print("[Theme] Bound " .. bound .. " colors to StyleSheet tokens (live updates enabled)")
end

return Theme
