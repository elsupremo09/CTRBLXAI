-- StyleBootstrap.lua
-- CTRBLXAI | StyleSheet Design System (All Phases)
-- Creates token, theme, and design StyleSheets at runtime.
-- Called once before any UI renders.
--
-- Architecture:
--   Tokens (base variables) -> DarkTheme (theme layer) -> DesignSheet (rules)
--   DesignSheet is linked to each ScreenGui via StyleLink.
--   Theme.lua reads from these tokens as a compatibility bridge.
--
-- Phases implemented:
--   1. Token Foundation (52 colors, 7 text sizes)
--   2. Button tag rules (Primary/Secondary/Tertiary + hover/press)
--   4. Rarity + Status tag rules
--   5. StyleQuery responsive breakpoints

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StyleBootstrap = {}

StyleBootstrap.Tokens = nil
StyleBootstrap.DarkTheme = nil
StyleBootstrap.DesignSheet = nil

--------------------------------------------------
-- TOKEN DEFINITIONS (canonical source of truth)
--------------------------------------------------

local COLOR_TOKENS = {
	Background           = Color3.fromRGB(12, 12, 18),
	BadgeBg              = Color3.fromRGB(0, 0, 0),
	Bleed                = Color3.fromRGB(180, 30, 30),
	Border               = Color3.fromRGB(50, 50, 65),
	BorderFocused        = Color3.fromRGB(255, 230, 80),
	BorderSelected       = Color3.fromRGB(100, 160, 255),
	Burn                 = Color3.fromRGB(255, 140, 40),
	Danger               = Color3.fromRGB(220, 50, 50),
	Defeated             = Color3.fromRGB(60, 60, 60),
	EmptySlot            = Color3.fromRGB(15, 15, 22),
	Enemy                = Color3.fromRGB(200, 70, 50),
	EntityHazard         = Color3.fromRGB(60, 40, 100),
	EntityObject         = Color3.fromRGB(50, 50, 30),
	Freeze               = Color3.fromRGB(100, 200, 255),
	HP                   = Color3.fromRGB(60, 190, 70),
	HPLow                = Color3.fromRGB(220, 60, 40),
	Info                 = Color3.fromRGB(100, 170, 255),
	LockedSlot           = Color3.fromRGB(10, 10, 15),
	MP                   = Color3.fromRGB(70, 120, 220),
	MPLow                = Color3.fromRGB(140, 80, 200),
	MetalEdge            = Color3.fromRGB(42, 42, 58),
	MetalGlow            = Color3.fromRGB(80, 120, 200),
	MetalInner           = Color3.fromRGB(26, 26, 36),
	MetalOuter           = Color3.fromRGB(18, 18, 26),
	MetalRivet           = Color3.fromRGB(55, 55, 70),
	Neutral              = Color3.fromRGB(140, 140, 140),
	Overlay              = Color3.fromRGB(0, 0, 0),
	Panel                = Color3.fromRGB(22, 22, 32),
	PanelRaised          = Color3.fromRGB(32, 32, 44),
	Player               = Color3.fromRGB(70, 130, 220),
	Poison               = Color3.fromRGB(80, 200, 80),
	RarityCommon         = Color3.fromRGB(160, 160, 160),
	RarityEpic           = Color3.fromRGB(180, 80, 255),
	RarityLegendary      = Color3.fromRGB(255, 200, 50),
	RarityRare           = Color3.fromRGB(70, 140, 255),
	RarityUncommon       = Color3.fromRGB(80, 200, 80),
	SelectedItem         = Color3.fromRGB(40, 35, 20),
	Silence              = Color3.fromRGB(180, 80, 200),
	Slow                 = Color3.fromRGB(150, 150, 200),
	Stun                 = Color3.fromRGB(255, 255, 100),
	Success              = Color3.fromRGB(60, 200, 80),
	Surface              = Color3.fromRGB(40, 40, 55),
	TextDisabled         = Color3.fromRGB(80, 80, 95),
	TextGold             = Color3.fromRGB(255, 220, 80),
	TextPrimary          = Color3.fromRGB(230, 230, 235),
	TextSecondary        = Color3.fromRGB(160, 160, 175),
	TileAOE              = Color3.fromRGB(200, 100, 40),
	TileInvalid          = Color3.fromRGB(100, 30, 30),
	TileMove             = Color3.fromRGB(50, 100, 170),
	TileSelected         = Color3.fromRGB(255, 220, 60),
	TileTarget           = Color3.fromRGB(200, 170, 50),
	Warning              = Color3.fromRGB(240, 180, 40),
}

local TEXT_SIZE_TOKENS = {
	TextTitle   = 18,
	TextHeading = 15,
	TextBody    = 13,
	TextSmall   = 12,
	TextMono    = 13,
	TextTiny    = 11,
	TextBadge   = 9,
}

-- Button 9-slice asset IDs
local BUTTON_ASSETS = {
	Primary   = "rbxassetid://128127407312284",
	Secondary = "rbxassetid://79828905582448",
	Tertiary  = "rbxassetid://74754968977134",
}

--------------------------------------------------
-- HELPER: Create a StyleRule and parent it
--------------------------------------------------

local function addRule(parent, selector, props)
	local rule = Instance.new("StyleRule")
	rule.Selector = selector
	rule.Parent = parent
	rule:SetProperties(props)
	return rule
end

--------------------------------------------------
-- BOOTSTRAP
--------------------------------------------------

function StyleBootstrap.Init()
	if StyleBootstrap.Tokens then return end

	----------------------------------------------
	-- 1. Tokens
	----------------------------------------------
	local tokens = Instance.new("StyleSheet")
	tokens.Name = "CTRBLXAI_Tokens"
	tokens.Parent = ReplicatedStorage

	for name, color in pairs(COLOR_TOKENS) do
		tokens:SetAttribute(name, color)
	end
	for name, size in pairs(TEXT_SIZE_TOKENS) do
		tokens:SetAttribute(name, size)
	end
	-- Button assets as string tokens
	for name, asset in pairs(BUTTON_ASSETS) do
		tokens:SetAttribute("BtnAsset" .. name, asset)
	end

	StyleBootstrap.Tokens = tokens

	----------------------------------------------
	-- 2. DarkTheme (derives Tokens, override layer)
	----------------------------------------------
	local darkTheme = Instance.new("StyleSheet")
	darkTheme.Name = "CTRBLXAI_DarkTheme"
	darkTheme.Parent = ReplicatedStorage

	local tokenDerive = Instance.new("StyleDerive")
	tokenDerive.StyleSheet = tokens
	tokenDerive.Parent = darkTheme

	StyleBootstrap.DarkTheme = darkTheme

	----------------------------------------------
	-- 3. DesignSheet (derives DarkTheme, holds rules)
	----------------------------------------------
	local ds = Instance.new("StyleSheet")
	ds.Name = "CTRBLXAI_DesignSheet"
	ds.Parent = ReplicatedStorage

	local themeDerive = Instance.new("StyleDerive")
	themeDerive.StyleSheet = darkTheme
	themeDerive.Parent = ds

	-- ==========================================
	-- PHASE 1: Class-level defaults
	-- ==========================================

	addRule(ds, "Frame", {
		BackgroundColor3 = "$Panel",
		BorderSizePixel = 0,
	})

	addRule(ds, "TextLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		TextColor3 = "$TextPrimary",
		Font = Enum.Font.Gotham,
	})

	addRule(ds, "TextButton", {
		BackgroundColor3 = "$Surface",
		BorderSizePixel = 0,
		TextColor3 = "$TextPrimary",
		Font = Enum.Font.Gotham,
	})

	addRule(ds, "ImageButton", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})

	addRule(ds, "ImageLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})

	addRule(ds, "ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarImageColor3 = "$TextSecondary",
	})

	-- ==========================================
	-- PHASE 2: Button tag rules
	-- ==========================================
	-- Usage: CollectionService:AddTag(btn, "PrimaryBtn")
	-- Handles: image, hover, press, disabled states

	addRule(ds, ".PrimaryBtn", {
		BackgroundTransparency = 1,
		Image = "$BtnAssetPrimary",
		ScaleType = Enum.ScaleType.Slice,
	})
	addRule(ds, ".PrimaryBtn:Hover", {
		ImageColor3 = Color3.fromRGB(230, 230, 230),
	})
	addRule(ds, ".PrimaryBtn:Press", {
		ImageColor3 = Color3.fromRGB(180, 180, 180),
	})

	addRule(ds, ".SecondaryBtn", {
		BackgroundTransparency = 1,
		Image = "$BtnAssetSecondary",
		ScaleType = Enum.ScaleType.Slice,
	})
	addRule(ds, ".SecondaryBtn:Hover", {
		ImageColor3 = Color3.fromRGB(230, 230, 230),
	})
	addRule(ds, ".SecondaryBtn:Press", {
		ImageColor3 = Color3.fromRGB(180, 180, 180),
	})

	addRule(ds, ".TertiaryBtn", {
		BackgroundTransparency = 1,
		Image = "$BtnAssetTertiary",
		ScaleType = Enum.ScaleType.Slice,
	})
	addRule(ds, ".TertiaryBtn:Hover", {
		ImageColor3 = Color3.fromRGB(230, 230, 230),
	})
	addRule(ds, ".TertiaryBtn:Press", {
		ImageColor3 = Color3.fromRGB(180, 180, 180),
	})

	-- ==========================================
	-- PHASE 4: Rarity tag rules
	-- ==========================================
	-- Usage: CollectionService:AddTag(card, "RarityRare")

	addRule(ds, ".RarityCommon", {
		BackgroundColor3 = "$RarityCommon",
	})
	addRule(ds, ".RarityUncommon", {
		BackgroundColor3 = "$RarityUncommon",
	})
	addRule(ds, ".RarityRare", {
		BackgroundColor3 = "$RarityRare",
	})
	addRule(ds, ".RarityEpic", {
		BackgroundColor3 = "$RarityEpic",
	})
	addRule(ds, ".RarityLegendary", {
		BackgroundColor3 = "$RarityLegendary",
	})

	-- Status effect tag rules
	addRule(ds, ".StatusPoison",  { BackgroundColor3 = "$Poison" })
	addRule(ds, ".StatusBurn",    { BackgroundColor3 = "$Burn" })
	addRule(ds, ".StatusFreeze",  { BackgroundColor3 = "$Freeze" })
	addRule(ds, ".StatusSilence", { BackgroundColor3 = "$Silence" })
	addRule(ds, ".StatusStun",    { BackgroundColor3 = "$Stun" })
	addRule(ds, ".StatusBleed",   { BackgroundColor3 = "$Bleed" })
	addRule(ds, ".StatusSlow",    { BackgroundColor3 = "$Slow" })

	-- Faction tag rules
	addRule(ds, ".FactionPlayer",  { BackgroundColor3 = "$Player" })
	addRule(ds, ".FactionEnemy",   { BackgroundColor3 = "$Enemy" })
	addRule(ds, ".FactionNeutral", { BackgroundColor3 = "$Neutral" })

	-- ==========================================
	-- PHASE 5: StyleQuery responsive breakpoints
	-- ==========================================
	-- Usage: @MobilePortrait, @MobileLandscape, @Tablet, @Desktop
	-- Consumer code activates queries via StyleBootstrap.SetBreakpoint()

	-- Text size overrides per breakpoint
	addRule(ds, "@Desktop TextLabel", {
		TextSize = "$TextBody",
	})
	addRule(ds, "@Compact TextLabel", {
		TextSize = "$TextBody",
	})

	StyleBootstrap.DesignSheet = ds


	-- Phase 3: Bind Theme.lua to tokens (bridge layer)
	local themeOk, ThemeModule = pcall(function()
		return require(ReplicatedStorage:WaitForChild("CTRBLXAI", 5)
			:WaitForChild("UI", 5):WaitForChild("Theme", 5))
	end)
	if themeOk and ThemeModule and ThemeModule.BindToStyleSheet then
		ThemeModule.BindToStyleSheet(tokens)
	else
		warn("[StyleBootstrap] Could not bind Theme.lua to tokens -- bridge skipped")
	end

	-- Summary
	local colorCount, sizeCount = 0, 0
	for _ in pairs(COLOR_TOKENS) do colorCount = colorCount + 1 end
	for _ in pairs(TEXT_SIZE_TOKENS) do sizeCount = sizeCount + 1 end
	print(string.format(
		"[StyleBootstrap] Initialized: %d color + %d size + 3 button tokens | "
		.. "6 class rules | 3 button styles | 5 rarity + 7 status + 3 faction tags | "
		.. "2 breakpoint queries",
		colorCount, sizeCount
	))
end

--------------------------------------------------
-- LINK: Attach DesignSheet to a ScreenGui
--------------------------------------------------

function StyleBootstrap.Link(screenGui)
	if not StyleBootstrap.DesignSheet then
		warn("[StyleBootstrap] Not initialized -- call Init() first")
		return
	end
	if screenGui:FindFirstChild("CTRBLXAI_StyleLink") then return end

	local link = Instance.new("StyleLink")
	link.Name = "CTRBLXAI_StyleLink"
	link.StyleSheet = StyleBootstrap.DesignSheet
	link.Parent = screenGui
end

--------------------------------------------------
-- BREAKPOINT: Activate a responsive query
--------------------------------------------------

function StyleBootstrap.SetBreakpoint(screenGui, breakpointName)
	-- Remove existing breakpoint queries
	for _, child in ipairs(screenGui:GetChildren()) do
		if child:IsA("StyleQuery") and child.Name:find("CTRBLXAI_BP_") then
			child:Destroy()
		end
	end
	-- Activate the new breakpoint
	if breakpointName and breakpointName ~= "" then
		local sq = Instance.new("StyleQuery")
		sq.Name = "CTRBLXAI_BP_" .. breakpointName
		sq.Selector = "@" .. breakpointName
		sq.Parent = screenGui
	end
end

--------------------------------------------------
-- TOKEN ACCESS: Read token value from StyleSheet
--------------------------------------------------

function StyleBootstrap.GetColor(tokenName)
	if StyleBootstrap.Tokens then
		return StyleBootstrap.Tokens:GetAttribute(tokenName)
	end
	return nil
end

function StyleBootstrap.GetSize(tokenName)
	if StyleBootstrap.Tokens then
		return StyleBootstrap.Tokens:GetAttribute(tokenName)
	end
	return nil
end

--------------------------------------------------
-- THEME SWAP
--------------------------------------------------

function StyleBootstrap.SetTheme(themeName)
	-- Future: create LightTheme StyleSheet, swap the derive in DesignSheet
	warn("[StyleBootstrap] Theme swap not yet implemented: " .. tostring(themeName))
end

return StyleBootstrap
