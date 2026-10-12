--!strict
-- UGCMerchantScreen.lua
-- CTRBLXAI | UGC merchant — the separate screen opened from the Outfit tab's
-- 'UGC Merchant' shortcut (loadout_ui_spec 72, ugc_rules 36 ugc_merchant).
-- Browse every curated item with the same Type + Status filters (69/70) and
-- start a free trial, rent (shows the current doubled price), add to / remove
-- from the cart, or buy for Roblox Avatar. Cart checkout here is outside battle
-- only (ugc_rules 45). Presentation only (ARC-001): every action is a server
-- request through UGCClient; prices and access are decided by UGCService.
-- Mobile (73): tap-only, 44 px targets, Scale-based layout.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CTRBLXAI = ReplicatedStorage:WaitForChild("CTRBLXAI", 10) :: Instance
local UI = CTRBLXAI:WaitForChild("UI", 10) :: Instance
local Content = ReplicatedStorage:WaitForChild("Content", 10) :: Instance
local Theme = require(UI:WaitForChild("Theme", 10) :: ModuleScript) :: any
local UGCClient = require(UI:WaitForChild("UGCClient", 10) :: ModuleScript) :: any
local W = require(UI:WaitForChild("UGCItemWidgets", 10) :: ModuleScript) :: any
local UGCCatalogData = require(Content:WaitForChild("UGCCatalogData", 10) :: ModuleScript) :: any

local UGCMerchantScreen = {}

-- Above the loadout screen (100) and its tab bar (150) so it reads as its own screen.
local DISPLAY_ORDER = Theme.TabBar.DisplayOrder + 10
local RETRY_TOO_FAST = 0.35

local _gui: ScreenGui? = nil
local _panel: GuiObject? = nil
local _onClose: (() -> ())? = nil
local _filter = W.NewFilterState()
local _token = 0
local _pendingMessage: string? = nil
local _pendingIsError = false

local refresh: () -> ()

local function say(text: string, isError: boolean?)
	_pendingMessage = text
	_pendingIsError = isError == true
end

local function act(fn: () -> any, okText: string | (any) -> string)
	task.spawn(function()
		local res = fn()
		if res and res.ok then
			say(if type(okText) == "function" then okText(res.data) else okText)
		else
			say((res and res.error) or "Request failed", true)
		end
		refresh()
	end)
end

-- Tile grid + one right-hand action column (loadout_ui_spec, user ruling 2026-10-09 v2).
-- LEFT : header (title + gold only), filters, message, tile grid showing at least
--        GRID_MIN_ROWS full rows on a phone in landscape (tiles shrink, 44 px floor).
-- RIGHT: one vertical column - the selected item's name + status, its buttons, then
--        Checkout cart and the square Back icon at the bottom. Replaces the bottom
--        action bar and the header Checkout/Back for the UGC merchant only.
local SIDE_COLUMN_SCALE = 0.3   -- share of the merchant panel width
local SIDE_COLUMN_MIN_PX = 160  -- keeps "Buy for Roblox Avatar" readable on a phone
local GRID_MIN_ROWS = 3

local _selectedId: number? = nil
local _tiles: { [number]: GuiObject } = {}
local _side: Frame? = nil

-- Buttons for the selected item (user ruling 2026-10-09), stacked full width:
--   Primary   Buy for Roblox Avatar / Get (Free) ('Off sale' marker instead). HIDDEN in battle.
--   Secondary Free trial, or Rent once no trial/rental is running (server canTrial / canRent;
--             never offered for free items, ugc_rules 57)
--   Tertiary  Add to / Remove from cart (always Tertiary, in and out of battle, ugc_rules 56)
local function fillActions(col: Frame, item: any, view: any)
	local inBattle = view.isBattleActive == true
	local buy = UGCClient.CreateBuyButton(col, item, W.OnBuyResult(say, refresh), inBattle)
	if buy then
		buy.LayoutOrder = 1
		W.FillWidth(buy)
	end
	if item.canTrial then
		W.FillWidth(W.BarButton(col, `Free trial ({UGCCatalogData.TRIAL_BATTLES} battles)`, "Secondary", function()
			act(function() return UGCClient.StartTrial(item.assetId) end, "Free trial started — equip it in the Outfit tab")
		end, true, 2))
	elseif item.canRent then
		local verb = if item.status == "expired" then "Rent again" else "Rent"
		W.FillWidth(W.BarButton(col, `{verb} ({W.FormatGold(item.rentPrice)} gold)`, "Secondary", function()
			act(function() return UGCClient.Rent(item.assetId) end, function(d: any)
				return `Rented — {d and d.remaining or UGCCatalogData.RENT_BATTLES} battles left. Next rental: {W.FormatGold(d and d.nextPrice)} gold`
			end)
		end, (view.gold or 0) >= (item.rentPrice or 0), 2))
	end
	if item.status ~= "owned" then
		if item.isInCart then
			W.FillWidth(W.BarButton(col, "Remove from cart", "Tertiary", function()
				act(function() return UGCClient.SetInCart(item.assetId, false) end, "Removed from cart")
			end, true, 3))
		else -- always Tertiary, in and out of battle (ugc_rules 17/56)
			W.FillWidth(W.BarButton(col, "Add to cart", "Tertiary", function()
				act(function() return UGCClient.SetInCart(item.assetId, true) end, "Added to cart")
			end, true, 3))
		end
	end
end

-- Rebuilds the right column for the selected item (nil = nothing selected; Checkout
-- and Back are always present so the screen can always be closed).
local function buildColumn(item: any?, view: any)
	local side = _side
	if not side then return end
	local old = side:FindFirstChild("ActionColumn")
	if old then old:Destroy() end -- MEM-002
	local col = Instance.new("Frame")
	col.Name = "ActionColumn"
	col.BackgroundTransparency = 1
	col.Size = UDim2.fromScale(1, 1)
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, Theme.Spacing.sm)
	list.Parent = col
	if item then
		local detail = UGCClient.GetStatusLabel(item)
		if item.status ~= "owned" and (item.refundOnBuy or 0) > 0 and not item.isOffSale then
			detail = `{detail} · Buy refunds {W.FormatGold(item.refundOnBuy)} gold` -- ugc_rules 53
		end
		W.Label(col, item.name or tostring(item.assetId), { bold = true, wrap = true, order = 1 })
		W.Label(col, detail, { wrap = true, order = 2, textSize = Theme.Text.Tiny(),
			color = UGCClient.GetStatusColor(item.status) })
		local actions = W.Row(col, 3, Enum.FillDirection.Vertical, Theme.Spacing.sm)
		actions.Name = "ItemActions"
		fillActions(actions, item, view)
	end
	-- Spacer pushes Checkout + Back to the bottom of the column.
	local spacer = Instance.new("Frame")
	spacer.Name = "Spacer"
	spacer.BackgroundTransparency = 1
	spacer.Size = UDim2.fromScale(1, 0)
	spacer.LayoutOrder = 50
	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = spacer
	spacer.Parent = col
	-- Bottom row: Checkout cart (fills) + the square Back icon, side by side to save height.
	local bottom = Instance.new("Frame")
	bottom.Name = "BottomRow"
	bottom.BackgroundTransparency = 1
	bottom.Size = UDim2.new(1, 0, 0, Theme.MinSize.TouchTarget)
	bottom.LayoutOrder = 60
	local bl = Instance.new("UIListLayout")
	bl.FillDirection = Enum.FillDirection.Horizontal
	bl.SortOrder = Enum.SortOrder.LayoutOrder
	bl.VerticalAlignment = Enum.VerticalAlignment.Center
	bl.Padding = UDim.new(0, Theme.Spacing.sm)
	bl.Parent = bottom
	local canCheckout = not view.isBattleActive and (view.cartCount or 0) > 0 -- outside battle only (45)
	local checkout = W.FillWidth(Theme.MakeBarButton(bottom,
		`Checkout cart ({view.cartCount or 0}/{view.cartCap or UGCCatalogData.CART_CAP})`,
		if canCheckout then "Primary" else "Disabled", function() W.Checkout(say, refresh) end,
		{ name = "Btn_CheckoutCart", layoutOrder = 1 })) -- Primary bar (2026-10-09)
	if checkout then
		checkout.Size = UDim2.new(1, -(Theme.MinSize.TouchTarget + Theme.Spacing.sm), 0, Theme.MinSize.TouchTarget)
	end
	local back = Theme.MakeIconButton(bottom, "Back", function() UGCMerchantScreen.Close() end, {
		name = "Btn_CloseMerchant", size = UDim2.fromOffset(Theme.MinSize.TouchTarget, Theme.MinSize.TouchTarget),
	})
	back.LayoutOrder = 2
	bottom.Parent = col
	col.Parent = side -- NET-004
end

-- Corner badge (upper-right): Owned first, else In cart, else none.
local function cornerBadgeFor(item: any): string?
	if item.status == "owned" then return "Owned" end
	if item.isInCart then return "In cart" end
	return nil
end

local function build(view: any)
	local panel = _panel
	if not panel or panel.Parent == nil then return end
	local old = panel:FindFirstChild("MerchantContent")
	-- Keep the grid's scroll position across rebuilds (add/remove cart, trial, buy).
	local oldGrid = old and old:FindFirstChild("ItemGrid", true)
	local keepScroll = if oldGrid and oldGrid:IsA("ScrollingFrame") then oldGrid.CanvasPosition else nil
	if old then old:Destroy() end -- MEM-002
	local root = Instance.new("Frame")
	root.Name = "MerchantContent"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	local pad = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(pad :: any)[side] = UDim.new(0, Theme.Spacing.lg)
	end
	pad.Parent = root
	local cols = Instance.new("UIListLayout")
	cols.FillDirection = Enum.FillDirection.Horizontal
	cols.SortOrder = Enum.SortOrder.LayoutOrder
	cols.Padding = UDim.new(0, Theme.Spacing.lg)
	cols.Parent = root

	-- LEFT: header, filters, message, grid (takes the width the column leaves).
	local left = Instance.new("Frame")
	left.Name = "MainColumn"
	left.BackgroundTransparency = 1
	left.Size = UDim2.fromScale(0, 1)
	left.LayoutOrder = 1
	local leftFlex = Instance.new("UIFlexItem")
	leftFlex.FlexMode = Enum.UIFlexMode.Fill
	leftFlex.Parent = left
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, Theme.Spacing.sm)
	list.Parent = left
	left.Parent = root

	-- RIGHT: the action column.
	local sideCol = Instance.new("Frame")
	sideCol.Name = "SideColumn"
	sideCol.BackgroundTransparency = 1
	sideCol.Size = UDim2.fromScale(SIDE_COLUMN_SCALE, 1)
	sideCol.LayoutOrder = 2
	local minW = Instance.new("UISizeConstraint")
	minW.MinSize = Vector2.new(SIDE_COLUMN_MIN_PX, 0)
	minW.Parent = sideCol
	sideCol.Parent = root
	_side = sideCol

	local header = W.Row(left, 1)
	W.Label(header, "UGC MERCHANT", { size = UDim2.new(0, 0, 0, W.COMPACT_H), autoSize = Enum.AutomaticSize.X,
		bold = true, color = Theme.Colors.TextGold, textSize = Theme.Text.Heading(), order = 1 })
	W.Label(header, `Gold: {W.FormatGold(view.gold)}`, { size = UDim2.new(0, 0, 0, W.COMPACT_H),
		autoSize = Enum.AutomaticSize.X, order = 2 })

	W.MakeFilterBar(left, _filter, 2, refresh)
	local msg = W.MakeMessage(left, 3)
	if _pendingMessage then
		W.SetMessage(msg, _pendingMessage, _pendingIsError)
		_pendingMessage = nil
	end

	local shown = {}
	for _, item in view.items or {} do
		if W.PassesFilter(item, _filter) then table.insert(shown, item) end
	end
	W.SortItems(shown, _filter)
	if #shown == 0 then
		W.EmptyState(left, if #(view.items or {}) == 0 then "No UGC items are curated yet."
			else "No items match these filters.").LayoutOrder = 4
		table.clear(_tiles)
		buildColumn(nil, view) -- Checkout + Back stay reachable
		root.Parent = panel -- NET-004
	else
		local grid = W.MakeTileGrid(left, 4, { minRows = GRID_MIN_ROWS })
		table.clear(_tiles)
		local sel = W.PickSelected(shown, _selectedId) -- reselect by assetId after a refresh
		_selectedId = sel and sel.assetId
		for i, item in shown do
			_tiles[item.assetId] = W.MakeTile(grid, item, i, sel ~= nil and item.assetId == sel.assetId, function()
				if _selectedId and _tiles[_selectedId] then W.SetTileSelected(_tiles[_selectedId], false) end
				_selectedId = item.assetId
				W.SetTileSelected(_tiles[item.assetId], true)
				buildColumn(item, view)
			end, { statusAtBottom = true, cornerBadge = cornerBadgeFor(item) })
		end
		buildColumn(sel, view)
		root.Parent = panel -- NET-004
		-- Deferred: AutomaticCanvasSize must resolve first or the position is clamped to 0.
		if keepScroll then task.defer(function() if grid.Parent then grid.CanvasPosition = keepScroll end end) end
	end
end

refresh = function()
	_token += 1
	local token = _token
	task.spawn(function()
		local res = UGCClient.GetView(nil) -- merchant is not unit-specific
		if token ~= _token or not _gui then return end
		if not res.ok and res.error == "Too fast — try again" then
			task.delay(RETRY_TOO_FAST, function()
				if token == _token then refresh() end
			end)
			return
		end
		if not res.ok or type(res.data) ~= "table" then
			warn(`[UGCMerchantScreen] Could not load UGC view: {res.error}`)
			say("UGC items are unavailable right now.", true)
			build({ items = {}, gold = 0, cartCount = 0, isBattleActive = true })
			return
		end
		build(res.data)
	end)
end

function UGCMerchantScreen.IsOpen(): boolean
	return _gui ~= nil and _gui.Parent ~= nil
end

-- opts.onClose: called after the screen closes (the Outfit tab reloads).
function UGCMerchantScreen.Open(opts: any?)
	_onClose = if type(opts) == "table" then opts.onClose else nil
	if UGCMerchantScreen.IsOpen() then
		refresh()
		return
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui, root = Theme.MakeFullScreen("UGCMerchantScreen", playerGui)
	gui.DisplayOrder = DISPLAY_ORDER
	_gui = gui
	_panel = Theme.MakePanel("MerchantPanel", UDim2.fromScale(1, 1), UDim2.new(), nil, root)
	refresh()
end

-- Server push while open (the Outfit tab forwards UGCStateChanged).
function UGCMerchantScreen.Refresh(message: string?)
	if not UGCMerchantScreen.IsOpen() then return end
	if message then say(message) end
	refresh()
end

function UGCMerchantScreen.Close()
	if not _gui then return end
	if W.CloseMenu then W.CloseMenu() end -- drop any open Type/Status/Sort list
	_token += 1
	_gui:Destroy() -- MEM-002: buttons and their connections go with it
	_gui, _panel = nil, nil
	table.clear(_tiles)
	_side = nil
	local cb = _onClose
	_onClose = nil
	if cb then cb() end
end

return UGCMerchantScreen
