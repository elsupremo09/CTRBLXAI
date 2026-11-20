-- LoadoutScreen.lua
-- CTRBLXAI | Slice 7 — Equipment Loadout Screen
-- Replaces pre/post-battle loadout. Uses ornate 9-slice panel frames.
-- Presentation only — no gameplay logic.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService        = game:GetService("GuiService")
local TextService       = game:GetService("TextService")

local player = Players.LocalPlayer

local CTRBLXAI_UI = ReplicatedStorage:WaitForChild("CTRBLXAI", 10):WaitForChild("UI", 10)
local Theme       = require(CTRBLXAI_UI:WaitForChild("Theme", 10))
-- The inventory bar / menus / level label / grid spacing / sub-tabs, shared with the Runeforge
-- (user 2026-11-08: the Loadout is the model; one copy of these pieces).
local InventoryControls = require(CTRBLXAI_UI:WaitForChild("InventoryControls", 10))
local MockData    = require(CTRBLXAI_UI:WaitForChild("MockLoadoutData", 10))
local BattleEvents = require(ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
	:WaitForChild("Remotes", 10):WaitForChild("BattleEvents", 10))
local GameConstants = require(ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
	:WaitForChild("Shared", 10):WaitForChild("GameConstants", 10))
-- Shared tags-only augment rule (2026-10-26): the screen greys out exactly what the server refuses.
local AugmentCompatibility = require(ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
	:WaitForChild("Shared", 10):WaitForChild("AugmentCompatibility", 10))
local ConsumableData = require(ReplicatedStorage:WaitForChild("Content", 10)
	:WaitForChild("ConsumableData", 10))
-- Shared portrait-overlay helper + per-race 2D portrait pools (player picker).
local UIComponents = require(CTRBLXAI_UI:WaitForChild("UIComponents", 10))
local PortraitData = require(ReplicatedStorage:WaitForChild("Content", 10)
	:WaitForChild("PortraitData", 10))
-- Doctrine icons for the unit-picker tiles (2026-11-10). Guarded: no icon = name only.
local okDoctrineData, DoctrineData = pcall(function()
	return require(ReplicatedStorage:WaitForChild("Content", 10):WaitForChild("DoctrineData", 10))
end)
if not okDoctrineData then warn("[LoadoutScreen] DoctrineData require failed: " .. tostring(DoctrineData)); DoctrineData = nil end
-- OUTFIT tab (UGC cosmetics) is its own module; this screen only hosts it (loadout_ui_spec 62).
-- Guarded: if the UGC modules fail to load, the other loadout tabs keep working.
local okOutfitTab, UGCOutfitTab = pcall(require, CTRBLXAI_UI:WaitForChild("UGCOutfitTab", 10))
if not okOutfitTab then warn("[LoadoutScreen] OUTFIT tab unavailable: " .. tostring(UGCOutfitTab)); UGCOutfitTab = nil end
-- PARTIES tab (USER DECISION 2026-11-04) is its own module too, hosted the same way.
local okPartiesTab, PartiesTab = pcall(require, CTRBLXAI_UI:WaitForChild("PartiesTab", 10))
if not okPartiesTab then warn("[LoadoutScreen] PARTIES tab unavailable: " .. tostring(PartiesTab)); PartiesTab = nil end
local TipController = nil -- New-player tips (2026-11-19): guarded, a missing module never breaks this screen
do
	local okTip, tipMod = pcall(function() return (require :: any)(CTRBLXAI_UI:WaitForChild("TipController", 10)) end)
	if okTip then TipController = tipMod else warn("[LoadoutScreen] tips unavailable: " .. tostring(tipMod)) end
end

local LoadoutScreen: any = {}

local screenGui, rootFrame
local unitHeaderPanel, equippedPanel, inventoryPanel, statPanel
local skillsPanel      -- left column for skills tab
local infoPanel        -- left column for info tab  
local outfitPanel, outfitSidePanel -- OUTFIT tab: main (left) + worn slots (right, below unit header)
local partiesPanel -- PARTIES tab: full width, unit header hidden (2026-11-04)
local viewportConn: RBXScriptConnection? = nil -- bottom-gap resize (2026-11-04)
local LOADOUT_MIN_BOTTOM_GAP = 8       -- px, never less (user 2026-11-04)
local LOADOUT_BOTTOM_GAP_SCALE = 0.03  -- 3% of screen height
local rightColFrame
local currentTab = "GEARS" 
local infoView = "stats" -- Info tab sub-view: "stats" | "passives" (user decision 2026-10-29)
local currentFilter = "All"
local detailFromSlot: string? = nil -- slot tile that opened the equipped detail (2026-10-28)
local selectedItemId = nil

-- Drag state
local currentRarity = "All"

-- Active dropdown (only one open at a time)
local activeDropdown = nil

local currentSort = 1


local EQUIP_SLOTS = {
	{ slot = "MainHand",  label = "MAIN HAND" },
	{ slot = "OffHand",   label = "OFF-HAND" },
	{ slot = "Head",      label = "HEAD" },
	{ slot = "Torso",     label = "TORSO" },
	{ slot = "Arms",      label = "ARMS" },
	{ slot = "Legs",      label = "LEGS" },
	{ slot = "Accessory", label = "ACCESSORY" },
	{ slot = "Doctrine",  label = "DOCTRINE" },
}

local _STAT_ORDER = { "STR", "INT", "DEX", "AGI", "VIT", "LUK" }

local BONUS_STAT_ORDER = {
	"STR", "INT", "DEX", "AGI", "VIT", "LUK",
	"HP", "MP", "Attack", "Defense", "RT Delay", "WT",
	"Precision", "Evasiveness", "Fortune", "Skill Potency",
	"Healing", "Debuff Resist", "RT Delay Resist",
}

--------------------------------------------------
-- CONSUMABLE PICKER POPUP
--------------------------------------------------

--------------------------------------------------
-- FORWARD DECLARATIONS (functions used before definition)
--------------------------------------------------
local buildInventory
local openItemDetail, closeDetail
local buildSoloDetailContent, buildComparisonContent
local switchTab, buildSkillsContent, buildInfoContent, buildStatPanel
local buildSkillLoadout
local openSkillCardDetail, openAugmentCardDetail
local openSkillSlotPicker, openAugmentSlotPicker
local openEquippedSkillDetail, openEquippedAugmentDetail
local openAugmentPickerForSlot -- declared early: skill-row augment buttons (built above) call it on click
local openConsumableDetail, openConsumableSlotPicker, openEquippedConsumableDetail
local buildConsumableGrid
local buildUnitHeader -- bound to LoadoutUnitHeader (split step 9)
local buildEquippedLoadout -- bound to LoadoutGears (split step 8)
local buildDetailHeader, findOtherHolder -- bound to LoadoutItemDetail (split step 7)
local ELEM_COLORS, STYPE_COLORS, STYPE_ICONS, buildSkillDescription, cleanEffects, getElement, getSkillType, simplifyPattern, simplifyRange -- bound to LoadoutSkillUtil (split step 3)


local _skillSubTab = "SKILL"     -- "SKILL" or "AUGMENT"



--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function getPlayerGui()
	return player:WaitForChild("PlayerGui")
end

-- Public: build item detail content into any panel (for reuse by victory screen etc.)
function LoadoutScreen.BuildItemDetail(panel, item)
	buildSoloDetailContent(panel, item)
end

-- Public (2026-11-18): the shared item detail header (portrait + name + tags + description),
-- so the victory screen's card / consumable detail matches the Loadout look. Returns its height.
function LoadoutScreen.BuildDetailHeader(panel, opts)
	return buildDetailHeader(panel, opts)
end

local function clearChildren(frame)
	if not frame then return end
	for _, child in ipairs(frame:GetChildren()) do
		if not child:IsA("UICorner") and not child:IsA("UIPadding") and not child:IsA("UISizeConstraint") then
			child:Destroy()
		end
	end
end

local function makePanel(name, size, position, anchor, parent, opts)
	return Theme.MakePanel(name, size, position, anchor, parent, opts)
end

local function makeLabel(parent, props)
	local lbl = Instance.new("TextLabel")
	lbl.Size = props.Size or UDim2.new(1, 0, 0, 14)
	lbl.Position = props.Position or UDim2.new(0, 0, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.BorderSizePixel = 0
	lbl.Font = props.Font or Theme.Font.Primary
	lbl.TextSize = props.TextSize or Theme.Text.Body()
	lbl.TextColor3 = props.TextColor3 or Theme.Colors.TextPrimary
	lbl.Text = props.Text or ""
	lbl.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	lbl.TextTruncate = Enum.TextTruncate.AtEnd
	lbl.LayoutOrder = props.LayoutOrder or 0
	lbl.RichText = props.RichText or false
	if props.TextWrapped then lbl.TextWrapped = true end
	lbl.Parent = parent
	return lbl
end

-- Auto-sizing passive/skill info card: its height grows to FULLY show the
-- wrapped description instead of clipping at a fixed box (2026-10-23 fix).
-- Parent should drive vertical flow with a UIListLayout (cards have no manual
-- Y). Name is single-line (ellipsis if absurdly long); description wraps and
-- is never truncated.
local function makeDescCard(parent, titleText, titleColor, descText, bgColor, bgTransparency, layoutOrder)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = bgColor or Theme.Colors.PanelRaised
	card.BackgroundTransparency = bgTransparency or 0.3
	card.BorderSizePixel = 0
	card.LayoutOrder = layoutOrder or 0
	card.Parent = parent
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 4)
	local cpad = Instance.new("UIPadding", card)
	cpad.PaddingTop = UDim.new(0, 3); cpad.PaddingBottom = UDim.new(0, 4)
	cpad.PaddingLeft = UDim.new(0, 4); cpad.PaddingRight = UDim.new(0, 4)
	local clist = Instance.new("UIListLayout", card)
	clist.FillDirection = Enum.FillDirection.Vertical
	clist.SortOrder = Enum.SortOrder.LayoutOrder
	clist.Padding = UDim.new(0, 2)
	local nameLbl = Instance.new("TextLabel")
	nameLbl.BackgroundTransparency = 1
	nameLbl.BorderSizePixel = 0
	nameLbl.Size = UDim2.new(1, 0, 0, 14)
	nameLbl.Font = Theme.Font.PrimaryBold
	nameLbl.TextSize = Theme.Text.Small()
	nameLbl.TextColor3 = titleColor or Theme.Colors.Success
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	nameLbl.LayoutOrder = 0
	nameLbl.Text = titleText or ""
	nameLbl.Parent = card
	if descText and descText ~= "" then
		local d = Instance.new("TextLabel")
		d.BackgroundTransparency = 1
		d.BorderSizePixel = 0
		d.Size = UDim2.new(1, 0, 0, 0)
		d.AutomaticSize = Enum.AutomaticSize.Y
		d.Font = Theme.Font.Primary
		d.TextSize = Theme.Text.Tiny()
		d.TextColor3 = Theme.Colors.TextSecondary
		d.TextXAlignment = Enum.TextXAlignment.Left
		d.TextYAlignment = Enum.TextYAlignment.Top
		d.TextWrapped = true
		d.TextTruncate = Enum.TextTruncate.None
		d.LayoutOrder = 1
		d.Text = descText
		d.Parent = card
	end
	return card
end

local function getRarityColor(rarity)
	local map = {
		Common = Theme.Colors.RarityCommon,
		Uncommon = Theme.Colors.RarityUncommon,
		Rare = Theme.Colors.RarityRare,
		Epic = Theme.Colors.RarityEpic,
		Exalted = Theme.Colors.RarityExalted,
		Legendary = Theme.Colors.RarityLegendary,
		Mythic = Theme.Colors.RarityMythic,
		Transcendent = Theme.Colors.RarityTranscendent,
		Unique = Theme.Colors.RarityUnique,
	}
	return map[rarity] or Theme.Colors.RarityCommon
end

local function pad(frame, top, left, right, bottom)
	local p = Instance.new("UIPadding", frame)
	p.PaddingTop = UDim.new(0, top or 10)
	p.PaddingLeft = UDim.new(0, left or 10)
	p.PaddingRight = UDim.new(0, right or 10)
	p.PaddingBottom = UDim.new(0, bottom or 10)
end

--------------------------------------------------
-- TAB BAR
--------------------------------------------------

local tabBarGui = nil
local tabButtons = {} -- tab name -> button made by Theme.MakeTabButton

local function buildTabBar()
	if tabBarGui then tabBarGui:Destroy() end
	local panel
	tabBarGui, panel = Theme.MakeTabBar("LoadoutTabBar", getPlayerGui())

	local tb = Theme.TabBar
	-- Keep the tabs inside the ornate frame's side borders (2026-10-08): inset = the
	-- frame's drawn border width (slice edge x SliceScale) instead of a fixed 8 px.
	local pf = Theme.PanelFrame
	local frameBorderX = math.ceil(pf.SliceCenter.Min.X * pf.SliceScale)
	local bar = Instance.new("Frame")
	bar.Name = "TabBar"
	local padY = tb.InnerPadY + 1 -- +1 px clearance from the frame's top/bottom (2026-10-08)
	bar.Size = UDim2.new(1, -frameBorderX * 2, 1, -padY * 2)
	bar.Position = UDim2.new(0, frameBorderX, 0, padY)
	bar.BackgroundTransparency = 1
	bar.Parent = panel

	local layout = Instance.new("UIListLayout", bar)
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 0) -- tabs sit edge to edge (2026-10-08)
	layout.SortOrder = Enum.SortOrder.LayoutOrder -- was default Name sort (alphabetical order bug)

	local tabs = { "INFO", "GEARS", "SKILLS", "OUTFIT", "PARTIES" } -- PARTIES added 2026-11-04 (user)
	-- Dungeon mode (step 3, 2026-11-16): gear, skills and consumables only; outfits and party presets are home things.
	if MockData.DungeonMode then tabs = { "INFO", "GEARS", "SKILLS" } end
	tabButtons = {}
	for i, name in ipairs(tabs) do
		-- Old 9-slice text bars (2026-10-08): Active = bronze, Inactive = navy (Theme.MakeTabButton).
		-- Height = the shared tab panel's inner height (Theme.TabBar), Scale width so 4 tabs fit (73).
		tabButtons[name] = Theme.MakeTabButton(bar, name, if name == currentTab then "Active" else "Inactive", function()
			if currentTab ~= name then
				BattleEvents.RequestSaveLoadout:FireServer() -- save the tab we're leaving (2026-10-19)
				currentTab = name
				if name == "INFO" then infoView = "stats" end -- Info always opens on Stats (2026-10-29)
				switchTab()
			end
		end, {
			name = "Tab_" .. name,
			size = UDim2.new(1 / #tabs, 0, 1, 0),
			textSize = tb.TabTextSize,
			layoutOrder = i,
		})
	end

	-- Opaque strip behind the tab bar, covering only the Roblox top-bar inset. The full-screen
	-- root starts BELOW the inset (Theme.FullScreen.IgnoreGuiInset = false), so without this the
	-- Guild menu underneath showed through at the top of the loadout (BUG-026).
	local insetTopLeft = GuiService:GetGuiInset()
	local strip = Instance.new("Frame")
	strip.Name = "TopInsetStrip"
	strip.Size = UDim2.new(1, 0, 0, insetTopLeft.Y)
	strip.BackgroundColor3 = Theme.FullScreen.BackgroundColor
	strip.BackgroundTransparency = 0
	strip.BorderSizePixel = 0
	strip.ZIndex = 0 -- under the tab panel and the Back button
	strip.Active = false
	strip.Parent = tabBarGui -- properties set before Parent (NET-004)

	-- BACK button: top-right corner of the top bar, where the retired dev OPTIONS menu sat
	-- (Start Battle / Save Now / Delete Save, removed 2026-10-08). Not top-left: Roblox's own
	-- menu/chat/mic buttons own that area and always draw on top of game UI.
	-- Closes the loadout and returns to the screen underneath. The Guild menu stays enabled
	-- below this screen (DisplayOrder 80 vs 100), so hiding is enough to go back to it. Every
	-- loadout change is sent to the server the moment it is made, so Back never discards
	-- anything (loadout_ui_spec 1, 9).
	local touch = Theme.MinSize.TouchTarget -- 44 px minimum (loadout_ui_spec 73)
	local backBtn = Theme.MakeIconButton(tabBarGui, "Back", nil, {
		name = "Btn_BACK",
		size = UDim2.new(0, touch, 0, touch),
		position = UDim2.new(1, -8, 0, tb.PositionY),
		anchor = Vector2.new(1, 0),
	})
	backBtn.Activated:Connect(function() -- .Activated: mouse, touch and gamepad
		LoadoutScreen.Hide()
	end)
end

-- Move the tab highlight in place (loadout_ui_spec 53: no rebuild on tab switch).
-- Builds the bar only if it does not exist yet (first open, or after Hide()).
local function refreshTabBar()
	if not tabBarGui or tabBarGui.Parent == nil then
		buildTabBar()
		return
	end
	for name, btn in tabButtons do
		Theme.SetTabState(btn, if name == currentTab then "Active" else "Inactive")
	end
end

--------------------------------------------------

--------------------------------------------------
-- GEARS TAB STATE (equipped sub-tab; read/written by LoadoutGears + LoadoutConsumables via ctx)
--------------------------------------------------
local equippedTab = "gear"  -- "gear" or "cons"

--------------------------------------------------
-- ITEM DETAIL OVERLAY (full-screen modal)
--------------------------------------------------

local detailOverlay = nil

closeDetail = function()
	if detailOverlay then detailOverlay:Destroy(); detailOverlay = nil end
end

--------------------------------------------------
-- TAB SWITCHING
--------------------------------------------------

switchTab = function()
	-- Hide all tab-specific panels
	if inventoryPanel then inventoryPanel.Visible = false end
	if equippedPanel then equippedPanel.Visible = false end
	if statPanel then statPanel.Visible = false end
	if skillsPanel then skillsPanel.Visible = false end
	if infoPanel then infoPanel.Visible = false end
	if outfitPanel then outfitPanel.Visible = false end
	if outfitSidePanel then outfitSidePanel.Visible = false end
	if currentTab ~= "OUTFIT" and UGCOutfitTab then UGCOutfitTab.Unmount() end
	if partiesPanel then partiesPanel.Visible = false end
	if currentTab ~= "PARTIES" and PartiesTab then PartiesTab.Unmount() end
	-- The unit header column is hidden on PARTIES (approved 2026-11-04) and shown everywhere else.
	if rightColFrame then rightColFrame.Visible = currentTab ~= "PARTIES" end
	-- New-player tips (new_player_tips): first unit-screen / tab views. Seen tips never repeat.
	if TipController then
		TipController.Trigger("TIP-UNIT-01")
		local tabTips = { GEARS = { "TIP-EQP-01" }, SKILLS = { "TIP-SKL-01" }, PARTIES = { "TIP-PTY-01" } }
		for _, id in tabTips[currentTab] or {} do TipController.Trigger(id) end
		-- TIP-DOC-01 fallback (Tester W5): starter units already own their doctrine, so the first
		-- doctrine the player SEES is slot 1 on the Skills tab. Only when the unit really has one.
		if currentTab == "SKILLS" then
			local u = MockData.GetSelectedUnit()
			if u and MockData.GetEquippedDoctrine(u.id) then TipController.Trigger("TIP-DOC-01") end
		end
	end

	-- Close any open overlays
	closeDetail()
	if activeDropdown then activeDropdown:Destroy(); activeDropdown = nil end

	if currentTab == "GEARS" then
		if inventoryPanel then inventoryPanel.Visible = true end
		if equippedPanel then equippedPanel.Visible = true end
		-- Reclaim stat panel space
		local eqTop = 60 + (Theme.FullScreen.PanelGap or 2)
		if equippedPanel then equippedPanel.Size = UDim2.new(1, 0, 1, -eqTop); equippedPanel.Position = UDim2.new(0, 0, 0, eqTop) end
		if equippedTab == "cons" then buildConsumableGrid() else buildInventory() end
		buildEquippedLoadout()
	elseif currentTab == "SKILLS" then
		if skillsPanel then skillsPanel.Visible = true end
		if equippedPanel then equippedPanel.Visible = true end
		-- Reclaim stat panel space
		local eqTop = 60 + (Theme.FullScreen.PanelGap or 2)
		if equippedPanel then equippedPanel.Size = UDim2.new(1, 0, 1, -eqTop); equippedPanel.Position = UDim2.new(0, 0, 0, eqTop) end
		buildSkillsContent()
	elseif currentTab == "INFO" then
		if infoPanel then infoPanel.Visible = true end
		if statPanel then statPanel.Visible = true end
		-- Push equipped panel below stat panel
		local gap = Theme.FullScreen.PanelGap or 2
		local topUsed = 60 + gap + 160 + gap
		if equippedPanel then equippedPanel.Size = UDim2.new(1, 0, 1, -topUsed); equippedPanel.Position = UDim2.new(0, 0, 0, topUsed) end
		buildStatPanel()
		buildInfoContent()
	elseif currentTab == "OUTFIT" then
		if outfitPanel then outfitPanel.Visible = true end
		if outfitSidePanel then outfitSidePanel.Visible = true end
		if UGCOutfitTab then UGCOutfitTab.Render(outfitPanel, outfitSidePanel, MockData.GetSelectedUnit()) end
	elseif currentTab == "PARTIES" then
		if partiesPanel then partiesPanel.Visible = true end
		if PartiesTab and partiesPanel then
			-- View loadout (approved D11): select the unit and open its INFO tab. Pick mode stays.
			PartiesTab.SetViewLoadout(function(unitId: string)
				if MockData.SetSelectedUnitById then MockData.SetSelectedUnitById(unitId) end
				currentTab = "INFO"
				infoView = "stats"
				switchTab()
			end)
			PartiesTab.Render(partiesPanel)
		end
	end

	-- Move the tab highlight in place (builds the bar only if it does not exist yet)
	refreshTabBar()
	-- Rebuild unit header (always visible)
	buildUnitHeader()
end

--------------------------------------------------
-- SKILLS TAB CONTENT (v3 — Grid + Loadout Table)
--------------------------------------------------

-- =====================================================
-- CONSUMABLE GRID & DETAIL -> LoadoutConsumables.lua (split 2026-11-10, step 1)
--------------------------------------------------
local LoadoutConsumables = require(CTRBLXAI_UI:WaitForChild("LoadoutConsumables", 10))
LoadoutConsumables.Init({
	clearChildren = function(...) return clearChildren(...) end,
	makeLabel = function(...) return makeLabel(...) end,
	pad = function(...) return pad(...) end,
	getPlayerGui = function() return getPlayerGui() end,
	closeDetail = function() return closeDetail() end,
	buildDetailHeader = function(...) return buildDetailHeader(...) end,
	buildEquippedLoadout = function(...) return buildEquippedLoadout(...) end,
	getInventoryPanel = function() return inventoryPanel end,
	getEquippedTab = function() return equippedTab end,
	setDetailOverlay = function(gui) detailOverlay = gui end,
	-- Dungeon mode map use (step 3): re-fetch the run's view and redraw after a Bag item was used.
	reload = function() MockData.LoadFromServer(); LoadoutScreen.Refresh() end,
})
LoadoutScreen.ConsCategoryColors = LoadoutConsumables.ConsCategoryColors
buildConsumableGrid = LoadoutConsumables.BuildGrid
openConsumableDetail = LoadoutConsumables.OpenDetail
openConsumableSlotPicker = LoadoutConsumables.OpenSlotPicker
openEquippedConsumableDetail = LoadoutConsumables.OpenEquippedDetail


--------------------------------------------------
-- STAT PANEL + INFO TAB -> LoadoutInfo.lua (split 2026-11-10, step 2)
--------------------------------------------------
local LoadoutInfo = require(CTRBLXAI_UI:WaitForChild("LoadoutInfo", 10))
LoadoutInfo.Init({
	EQUIP_SLOTS = EQUIP_SLOTS,
	clearChildren = function(...) return clearChildren(...) end,
	makeLabel = function(...) return makeLabel(...) end,
	pad = function(...) return pad(...) end,
	getPlayerGui = function() return getPlayerGui() end,
	closeDetail = function() return closeDetail() end,
	getStatPanel = function() return statPanel end,
	getInfoPanel = function() return infoPanel end,
	getRootFrame = function() return rootFrame end,
	getInfoView = function() return infoView end,
	setInfoView = function(v) infoView = v end,
	setDetailOverlay = function(gui) detailOverlay = gui end,
	refresh = function(...) return LoadoutScreen.Refresh(...) end,
})
buildStatPanel = LoadoutInfo.BuildStatPanel
buildInfoContent = LoadoutInfo.BuildInfoContent


--------------------------------------------------
-- SKILL TEXT HELPERS -> LoadoutSkillUtil.lua (split 2026-11-10, step 3)
--------------------------------------------------
local LoadoutSkillUtil = require(CTRBLXAI_UI:WaitForChild("LoadoutSkillUtil", 10))
ELEM_COLORS = LoadoutSkillUtil.ELEM_COLORS
STYPE_COLORS = LoadoutSkillUtil.STYPE_COLORS
STYPE_ICONS = LoadoutSkillUtil.STYPE_ICONS
buildSkillDescription = LoadoutSkillUtil.BuildSkillDescription
cleanEffects = LoadoutSkillUtil.CleanEffects
getElement = LoadoutSkillUtil.GetElement
getSkillType = LoadoutSkillUtil.GetSkillType
simplifyPattern = LoadoutSkillUtil.SimplifyPattern
simplifyRange = LoadoutSkillUtil.SimplifyRange


--------------------------------------------------
-- SKILL / AUGMENT DETAIL WINDOWS -> LoadoutSkillDetail.lua (split 2026-11-10, step 3)
--------------------------------------------------
local LoadoutSkillDetail = require(CTRBLXAI_UI:WaitForChild("LoadoutSkillDetail", 10))
LoadoutSkillDetail.Init({
	setDetailOverlay = function(gui) detailOverlay = gui end,
	buildDetailHeader = function(...) return buildDetailHeader(...) end,
	buildSkillsContent = function(...) return buildSkillsContent(...) end,
	closeDetail = function(...) return closeDetail(...) end,
	getPlayerGui = function(...) return getPlayerGui(...) end,
	makeLabel = function(...) return makeLabel(...) end,
	openAugmentSlotPicker = function(...) return openAugmentSlotPicker(...) end,
	openSkillSlotPicker = function(...) return openSkillSlotPicker(...) end,
	pad = function(...) return pad(...) end,
	getActiveDropdown = function() return activeDropdown end,
	setActiveDropdown = function(x) activeDropdown = x end,
})
openAugmentCardDetail = LoadoutSkillDetail.OpenAugmentCardDetail
openEquippedAugmentDetail = LoadoutSkillDetail.OpenEquippedAugmentDetail
openEquippedSkillDetail = LoadoutSkillDetail.OpenEquippedSkillDetail
openSkillCardDetail = LoadoutSkillDetail.OpenSkillCardDetail


--------------------------------------------------
-- SKILL LOADOUT + SLOT / AUGMENT PICKERS -> LoadoutSkillLoadout.lua (split 2026-11-10, step 4)
--------------------------------------------------
local LoadoutSkillLoadout = require(CTRBLXAI_UI:WaitForChild("LoadoutSkillLoadout", 10))
LoadoutSkillLoadout.Init({
	buildSkillsContent = function(...) return buildSkillsContent(...) end,
	clearChildren = function(...) return clearChildren(...) end,
	closeDetail = function(...) return closeDetail(...) end,
	getPlayerGui = function(...) return getPlayerGui(...) end,
	makeLabel = function(...) return makeLabel(...) end,
	openEquippedAugmentDetail = function(...) return openEquippedAugmentDetail(...) end,
	openEquippedSkillDetail = function(...) return openEquippedSkillDetail(...) end,
	openSkillCardDetail = function(...) return openSkillCardDetail(...) end,
	pad = function(...) return pad(...) end,
	getActiveDropdown = function() return activeDropdown end,
	setActiveDropdown = function(x) activeDropdown = x end,
	getEquippedPanel = function() return equippedPanel end,
	setDetailOverlay = function(gui) detailOverlay = gui end,
})
buildSkillLoadout = LoadoutSkillLoadout.BuildSkillLoadout
openAugmentPickerForSlot = LoadoutSkillLoadout.OpenAugmentPickerForSlot
openAugmentSlotPicker = LoadoutSkillLoadout.OpenAugmentSlotPicker
openSkillSlotPicker = LoadoutSkillLoadout.OpenSkillSlotPicker


--------------------------------------------------
-- SKILLS TAB GRID -> LoadoutSkills.lua (split 2026-11-10, step 5)
--------------------------------------------------
local LoadoutSkills = require(CTRBLXAI_UI:WaitForChild("LoadoutSkills", 10))
LoadoutSkills.Init({
	buildSkillLoadout = function(...) return buildSkillLoadout(...) end,
	clearChildren = function(...) return clearChildren(...) end,
	getPlayerGui = function(...) return getPlayerGui(...) end,
	makeLabel = function(...) return makeLabel(...) end,
	openAugmentCardDetail = function(...) return openAugmentCardDetail(...) end,
	openSkillCardDetail = function(...) return openSkillCardDetail(...) end,
	pad = function(...) return pad(...) end,
	getActiveDropdown = function() return activeDropdown end,
	setActiveDropdown = function(x) activeDropdown = x end,
	getSkillsPanel = function() return skillsPanel end,
})
buildSkillsContent = LoadoutSkills.BuildSkillsContent


--------------------------------------------------
-- ITEM COMPARISON -> LoadoutItemCompare.lua (split 2026-11-10, step 6)
--------------------------------------------------
local LoadoutItemCompare = require(CTRBLXAI_UI:WaitForChild("LoadoutItemCompare", 10))
LoadoutItemCompare.Init({
	BONUS_STAT_ORDER = BONUS_STAT_ORDER,
	findOtherHolder = function(...) return findOtherHolder(...) end,
	getRarityColor = function(...) return getRarityColor(...) end,
	makeDescCard = function(...) return makeDescCard(...) end,
	makeLabel = function(...) return makeLabel(...) end,
})
buildComparisonContent = LoadoutItemCompare.BuildComparisonContent


--------------------------------------------------
-- ITEM DETAIL -> LoadoutItemDetail.lua (split 2026-11-10, step 7)
--------------------------------------------------
local LoadoutItemDetail = require(CTRBLXAI_UI:WaitForChild("LoadoutItemDetail", 10))
LoadoutItemDetail.Init({
	BONUS_STAT_ORDER = BONUS_STAT_ORDER,
	buildComparisonContent = function(...) return buildComparisonContent(...) end,
	closeDetail = function(...) return closeDetail(...) end,
	getPlayerGui = function(...) return getPlayerGui(...) end,
	getRarityColor = function(...) return getRarityColor(...) end,
	makeDescCard = function(...) return makeDescCard(...) end,
	makeLabel = function(...) return makeLabel(...) end,
	pad = function(...) return pad(...) end,
	getActiveDropdown = function() return activeDropdown end,
	setActiveDropdown = function(x) activeDropdown = x end,
	getCurrentFilter = function() return currentFilter end,
	getDetailFromSlot = function() return detailFromSlot end,
	setDetailOverlay = function(gui) detailOverlay = gui end,
	refresh = function(...) return LoadoutScreen.Refresh(...) end,
})
buildDetailHeader = LoadoutItemDetail.BuildDetailHeader
buildSoloDetailContent = LoadoutItemDetail.BuildSoloDetailContent
findOtherHolder = LoadoutItemDetail.FindOtherHolder
openItemDetail = LoadoutItemDetail.OpenItemDetail


--------------------------------------------------
-- GEARS TAB (EQUIPPED LOADOUT + INVENTORY) -> LoadoutGears.lua (split 2026-11-10, step 8)
--------------------------------------------------
local LoadoutGears = require(CTRBLXAI_UI:WaitForChild("LoadoutGears", 10))
LoadoutGears.Init({
	EQUIP_SLOTS = EQUIP_SLOTS,
	buildConsumableGrid = function(...) return buildConsumableGrid(...) end,
	clearChildren = function(...) return clearChildren(...) end,
	getPlayerGui = function(...) return getPlayerGui(...) end,
	getRarityColor = function(...) return getRarityColor(...) end,
	makeLabel = function(...) return makeLabel(...) end,
	openEquippedConsumableDetail = function(...) return openEquippedConsumableDetail(...) end,
	openItemDetail = function(...) return openItemDetail(...) end,
	pad = function(...) return pad(...) end,
	getActiveDropdown = function() return activeDropdown end,
	setActiveDropdown = function(x) activeDropdown = x end,
	getCurrentFilter = function() return currentFilter end,
	setCurrentFilter = function(x) currentFilter = x end,
	getCurrentRarity = function() return currentRarity end,
	setCurrentRarity = function(x) currentRarity = x end,
	getCurrentSort = function() return currentSort end,
	setCurrentSort = function(x) currentSort = x end,
	setDetailFromSlot = function(x) detailFromSlot = x end,
	getEquippedPanel = function() return equippedPanel end,
	getEquippedTab = function() return equippedTab end,
	setEquippedTab = function(x) equippedTab = x end,
	getInventoryPanel = function() return inventoryPanel end,
	getSelectedItemId = function() return selectedItemId end,
	setSelectedItemId = function(x) selectedItemId = x end,
	getConsCategoryColors = function() return LoadoutScreen.ConsCategoryColors end,
})
buildEquippedLoadout = LoadoutGears.BuildEquippedLoadout
buildInventory = LoadoutGears.BuildInventory


--------------------------------------------------
-- UNIT HEADER + UNIT PICKER -> LoadoutUnitHeader.lua (split 2026-11-10, step 9)
--------------------------------------------------
local LoadoutUnitHeader = require(CTRBLXAI_UI:WaitForChild("LoadoutUnitHeader", 10))
LoadoutUnitHeader.Init({
	clearChildren = function(...) return clearChildren(...) end,
	getPlayerGui = function(...) return getPlayerGui(...) end,
	makeLabel = function(...) return makeLabel(...) end,
	pad = function(...) return pad(...) end,
	getDoctrineData = function() return DoctrineData end,
	getActiveDropdown = function() return activeDropdown end,
	setActiveDropdown = function(x) activeDropdown = x end,
	getUnitHeaderPanel = function() return unitHeaderPanel end,
	refresh = function(...) return LoadoutScreen.Refresh(...) end,
	setOpenUnitPicker = function(f) LoadoutScreen._OpenUnitPicker = f end,
})
buildUnitHeader = LoadoutUnitHeader.BuildUnitHeader


-- SCREEN BUILD
--------------------------------------------------

function LoadoutScreen.Show()
	if screenGui and screenGui.Parent then return end

	-- Fetch real inventory from server (falls back to mock data on failure)
	MockData.LoadFromServer()
	-- Opened for one unit (guild Units screen card tap, 2026-11-13): select it after the roster loads.
	if LoadoutScreen._openUnitId and MockData.SetSelectedUnitById then MockData.SetSelectedUnitById(LoadoutScreen._openUnitId) end
	LoadoutScreen._openUnitId = nil

	screenGui, rootFrame = Theme.MakeFullScreen("LoadoutScreen", getPlayerGui())

	-- Remove outer screen border — inner panels' own 9-slice corners
	-- provide the corner ornaments at the screen edges they each own
	local sb = rootFrame:FindFirstChild("ScreenBorder")
	if sb then sb:Destroy() end

	-- Bottom gap (user 2026-11-04): the whole loadout scales with the screen but always keeps a
	-- gap above the bottom edge (small phones were touching it). Gap = 3% of screen height,
	-- never under 8 px. Re-applied when the screen size changes.
	local function applyBottomGap()
		local cam = workspace.CurrentCamera
		local h = cam and cam.ViewportSize.Y or 400
		local gap = math.max(LOADOUT_MIN_BOTTOM_GAP, math.floor(h * LOADOUT_BOTTOM_GAP_SCALE))
		if rootFrame then rootFrame.Size = UDim2.new(1, 0, 1, -gap) end
	end
	applyBottomGap()
	if viewportConn then viewportConn:Disconnect() end
	local cam = workspace.CurrentCamera
	if cam then viewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyBottomGap) end

	-- Tab bar (top center)
	buildTabBar()

	-- RIGHT COLUMN (30% width, flush to right/top/bottom edges)
	local rightCol = Instance.new("Frame")
	rightCol.Name = "RightCol"
	rightCol.Size = UDim2.new(0.30, 0, 1, 0)
	rightCol.Position = UDim2.new(0.70, 0, 0, 0)
	rightCol.BackgroundTransparency = 1
	rightCol.Parent = rootFrame
	rightColFrame = rightCol

	-- Unit header (top of right column)
	unitHeaderPanel = makePanel("UnitHeader",
		UDim2.new(1, 0, 0, 60),
		UDim2.new(0, 0, 0, 0), nil, rightCol)

	-- Stat panel (below unit header — primary stats + allocation)
	local gap = Theme.FullScreen.PanelGap
	local statPanelH = 160
	statPanel = makePanel("StatPanel",
		UDim2.new(1, 0, 0, statPanelH),
		UDim2.new(0, 0, 0, 60 + gap), nil, rightCol)

	-- Equipped loadout (below stat panel)
	local topUsed = 60 + gap + statPanelH + gap
	equippedPanel = makePanel("EquippedLoadout",
		UDim2.new(1, 0, 1, -topUsed),
		UDim2.new(0, 0, 0, topUsed), nil, rightCol)

	-- LEFT COLUMN: Tab-specific panels (70% width, flush to left/top/bottom edges)
	-- Equipment tab: inventory
	inventoryPanel = makePanel("Inventory",
		UDim2.new(0.70, 0, 1, 0),
		UDim2.new(0, 0, 0, 0), nil, rootFrame)

	-- Skills tab: skill loadout
	skillsPanel = makePanel("SkillsPanel",
		UDim2.new(0.70, 0, 1, 0),
		UDim2.new(0, 0, 0, 0), nil, rootFrame)
	skillsPanel.Visible = false

	-- Info tab: unit info
	infoPanel = makePanel("InfoPanel",
		UDim2.new(0.70, 0, 1, 0),
		UDim2.new(0, 0, 0, 0), nil, rootFrame)
	infoPanel.Visible = false

	-- Outfit tab (loadout_ui_spec 60-62): main panel on the left; worn-slot panel where the
	-- equipped loadout sits, below the persistent unit header (61).
	outfitPanel = makePanel("OutfitPanel",
		UDim2.new(0.70, 0, 1, 0),
		UDim2.new(0, 0, 0, 0), nil, rootFrame)
	outfitPanel.Visible = false
	local outfitTop = 60 + gap
	outfitSidePanel = makePanel("OutfitSidePanel",
		UDim2.new(1, 0, 1, -outfitTop),
		UDim2.new(0, 0, 0, outfitTop), nil, rightCol)
	outfitSidePanel.Visible = false

	-- Parties tab (2026-11-04): full width, unit header hidden.
	partiesPanel = makePanel("PartiesPanel",
		UDim2.new(1, 0, 1, 0),
		UDim2.new(0, 0, 0, 0), nil, rootFrame)
	pad(partiesPanel, 10, 10, 10, 10)
	partiesPanel.Visible = false

	-- Show the correct tab (PARTIES when opened from the guild Party button / Sortie)
	currentTab = LoadoutScreen._openTab or "GEARS"
	infoView = "stats"
	LoadoutScreen.Refresh()
end

function LoadoutScreen.Refresh()
	switchTab()
end

function LoadoutScreen.Hide()
	BattleEvents.RequestSaveLoadout:FireServer() -- persist staged loadout changes on exit (2026-10-19)
	closeDetail()
	if UGCOutfitTab then UGCOutfitTab.Unmount() end -- disconnects its listener, closes the UGC merchant (PRF-004)
	if activeDropdown then activeDropdown:Destroy(); activeDropdown = nil end
	if tabBarGui then tabBarGui:Destroy(); tabBarGui = nil end
	if screenGui then screenGui:Destroy(); screenGui = nil end
	rootFrame = nil
	unitHeaderPanel = nil
	equippedPanel = nil
	inventoryPanel = nil
	skillsPanel = nil
	infoPanel = nil
	outfitPanel = nil
	outfitSidePanel = nil
	if PartiesTab then PartiesTab.Unmount(); PartiesTab.Configure(nil) end
	partiesPanel = nil
	rightColFrame = nil
	if viewportConn then viewportConn:Disconnect(); viewportConn = nil end
	LoadoutScreen._openTab = nil
	LoadoutScreen._openUnitId = nil
	-- Dungeon mode ends with the screen; the dungeon map refreshes (step 3).
	local wasDungeon = MockData.DungeonMode
	MockData.DungeonMode = false
	local onClose = LoadoutScreen._onClose
	LoadoutScreen._onClose = nil
	if wasDungeon and onClose then task.spawn(onClose) end
end

-- Open straight on a tab (2026-11-04: the guild Party button and the Sortie open PARTIES).
-- opts are handed to the Parties tab: { pick, onPick, onViewLoadout }. opts.unitId (2026-11-13):
-- open with that unit selected (guild Units screen); INFO always opens on Stats.
-- opts.dungeon (step 3, 2026-11-16): open in dungeon mode (party units, Bag items only); opts.onClose runs on Back.
function LoadoutScreen.ShowTab(tab: string, opts: any?)
	if opts and opts.dungeon and not (screenGui and screenGui.Parent) then
		MockData.DungeonMode = true
		LoadoutScreen._onClose = opts.onClose
	end
	LoadoutScreen._openTab = tab
	LoadoutScreen._openUnitId = opts and opts.unitId or nil
	if tab == "INFO" then infoView = "stats" end
	if PartiesTab then
		local o = opts or {}
		PartiesTab.Configure(o)
	end
	if screenGui and screenGui.Parent then
		if LoadoutScreen._openUnitId and MockData.SetSelectedUnitById then MockData.SetSelectedUnitById(LoadoutScreen._openUnitId) end
		LoadoutScreen._openUnitId = nil
		currentTab = tab
		switchTab()
	else
		LoadoutScreen.Show()
	end
end

function LoadoutScreen.Toggle()
	if screenGui and screenGui.Parent then
		LoadoutScreen.Hide()
	else
		LoadoutScreen.Show()
	end
end

return LoadoutScreen
