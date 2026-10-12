--!strict
-- UGCOutfitTab.lua
-- CTRBLXAI | Loadout screen — OUTFIT tab (loadout_ui_spec section 'Outfit Tab',
-- ugc_rules 37). Its own module (loadout_ui_spec 62): LoadoutScreen only hosts
-- the two panels and calls Render / Unmount. Presentation only (ARC-001): every
-- action is a server request through UGCClient; the server re-checks everything.
--
--   Left (main) panel : sub-tabs 'My Items' and 'Cart' (63), Type + Status
--                       filters on both (69/70), item cards, UGC Merchant
--                       shortcut (72), Checkout all on the Cart sub-tab (45).
--   Right (side) panel: below the persistent unit header (61) — what the
--                       selected unit wears per slot, with Unequip, and the
--                       slots its race cannot use (race slot blocks, 66).
--
-- My Items (64-66): owned, trial, rented and out-of-use items; rentals show
-- battles left; out-of-use items are red and cannot be equipped; Buy for Roblox
-- Avatar on every unowned item, trials included ('Off sale' marker instead).
-- Cart (67/68): items the player added; start a free trial or buy; Remove.
-- Rebuilds from a fresh GetView on every server change (UGCStateChanged,
-- including battle end) and whenever the loadout screen refreshes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CTRBLXAI = ReplicatedStorage:WaitForChild("CTRBLXAI", 10) :: Instance
local UI = CTRBLXAI:WaitForChild("UI", 10) :: Instance
local Content = ReplicatedStorage:WaitForChild("Content", 10) :: Instance
local Theme = require(UI:WaitForChild("Theme", 10) :: ModuleScript) :: any
local UGCClient = require(UI:WaitForChild("UGCClient", 10) :: ModuleScript) :: any
local W = require(UI:WaitForChild("UGCItemWidgets", 10) :: ModuleScript) :: any
local UGCMerchantScreen = require(UI:WaitForChild("UGCMerchantScreen", 10) :: ModuleScript) :: any
local UGCCatalogData = require(Content:WaitForChild("UGCCatalogData", 10) :: ModuleScript) :: any

local UGCOutfitTab = {}

local SUB_MY_ITEMS, SUB_CART = "MyItems", "Cart"
local RETRY_TOO_FAST = 0.35 -- the View remote is rate limited (SEC-001)
local MY_ITEMS_STATUSES = { owned = true, trial = true, rent = true, expired = true }

local _main: GuiObject? = nil
local _side: GuiObject? = nil
local _unit: any = nil -- { id, name, raceName } from the loadout's selected unit
local _subTab = SUB_MY_ITEMS
local _filter = W.NewFilterState()
local _conn: RBXScriptConnection? = nil
local _token = 0 -- drops stale responses when renders overlap
local _pendingMessage: string? = nil
local _pendingIsError = false
-- Side panel sub-tab + look preview (2026-10-08). Try-on is visual only: never saved,
-- never sent as an equip — only as a read-only preview request.
local SIDE_WORN, SIDE_PREVIEW = "Worn", "Preview"
local _sideTab = SIDE_WORN
local _tryOn: { [string]: number } = {} -- slot -> assetId
local _tryOnNames: { [string]: string } = {}
local _previewConns: { RBXScriptConnection } = {}
local _previewToken = 0
local _lastView: any = nil
local _lastBuiltSubTab: string? = nil -- scroll is kept only when rebuilding the same sub-tab
-- Preview starts turned to face the camera: the camera sits on +Z looking down -Z,
-- so a model whose front is -Z shows its back unless turned 180 degrees.
local PREVIEW_START_YAW = 180
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function contentFrame(panel: GuiObject, name: string, vertical: boolean): Frame
	local old = panel:FindFirstChild(name)
	if old then old:Destroy() end -- MEM-002
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1)
	local pad = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(pad :: any)[side] = UDim.new(0, Theme.Spacing.lg)
	end
	pad.Parent = f
	if vertical then
		local list = Instance.new("UIListLayout")
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0, Theme.Spacing.sm)
		list.Parent = f
	end
	return f
end

local function _byName(a: any, b: any): boolean
	return (a.name or "") < (b.name or "")
end

local refresh: () -> ()

local function say(text: string, isError: boolean?)
	_pendingMessage = text
	_pendingIsError = isError == true
end

-- Runs a request, keeps its message for the next render, then reloads.
local function act(fn: () -> any, okText: string)
	task.spawn(function()
		local res = fn()
		if res and res.ok then say(okText) else say((res and res.error) or "Request failed", true) end
		refresh()
	end)
end

--------------------------------------------------
-- TILES + ACTION BAR (2026-10-09: small tiles, one action bar for the selection)
--------------------------------------------------

local buildSide: (any) -> ()

local _selected: { [string]: number } = {} -- sub-tab -> selected assetId (reselected after refresh)
local _tiles: { [number]: GuiObject } = {}
local _barRoot: Frame? = nil
local _barItem: any = nil
local _barView: any = nil

local buildBar: (any, any) -> ()

-- Try on / Remove try-on: a visual preview on the selected unit only. Uses no
-- trial, is never saved and never worn in battle; one item per slot. Cleared on
-- unit switch, on leaving the Outfit tab and when the loadout closes (Unmount).
local function toggleTryOn(item: any)
	if not item.slot then return end
	if _tryOn[item.slot] == item.assetId then
		_tryOn[item.slot] = nil
		_tryOnNames[item.slot] = nil
	else
		_tryOn[item.slot] = item.assetId
		_tryOnNames[item.slot] = item.name or tostring(item.assetId)
		_sideTab = SIDE_PREVIEW
	end
	if _lastView then buildSide(_lastView) end
	if _barView then buildBar(item, _barView) end
end

-- Buttons for the selected item (user ruling 2026-10-09):
--   Primary   Buy for Roblox Avatar / Get (Free) ('Off sale' marker instead). HIDDEN in battle.
--   Secondary Equip / Unequip (HIDDEN in battle), or Free trial / Rent when the item is not active
--   Tertiary  Try on / Remove try-on, Add to / Remove from cart (always Tertiary, ugc_rules 56)
local function fillActions(bar: Frame, item: any, view: any)
	local unitId = _unit and _unit.id
	local inBattle = view.isBattleActive == true
	local hasUse = item.status == "owned" or item.status == "trial" or item.status == "rent"
	local equips = view.equips or {}
	local isWornHere = unitId ~= nil and equips[item.slot] == item.assetId

	local buy = UGCClient.CreateBuyButton(bar, item, W.OnBuyResult(say, refresh), inBattle)
	if buy then buy.LayoutOrder = 1 end

	if hasUse and unitId and item.isEligible ~= false then
		if inBattle then
			-- Equip / Unequip are hidden in battle, not greyed out (ugc_rules 56).
		elseif isWornHere then
			W.BarButton(bar, "Unequip", "Secondary", function()
				act(function() return UGCClient.Unequip(unitId, item.slot) end, "Unequipped")
			end, true, 2)
		else
			W.BarButton(bar, "Equip", "Secondary", function()
				act(function() return UGCClient.Equip(unitId, item.assetId) end, `Equipped on {_unit.name or "unit"}`)
			end, true, 2)
		end
	elseif item.canTrial then
		W.BarButton(bar, `Free trial ({UGCCatalogData.TRIAL_BATTLES} battles)`, "Secondary", function()
			act(function() return UGCClient.StartTrial(item.assetId) end, "Free trial started")
		end, true, 2)
	elseif item.canRent then -- only once no trial/rental is running (server rule, 2026-10-09)
		local verb = if item.status == "expired" then "Rent again" else "Rent"
		W.BarButton(bar, `{verb} ({W.FormatGold(item.rentPrice)} gold)`, "Secondary", function()
			act(function() return UGCClient.Rent(item.assetId) end, `Rented — {UGCCatalogData.RENT_BATTLES} battles`)
		end, (view.gold or 0) >= (item.rentPrice or 0), 2)
	end

	if unitId and item.slot and item.isEligible ~= false then
		local isTrying = _tryOn[item.slot] == item.assetId
		W.BarButton(bar, if isTrying then "Remove try-on" else "Try on", "Tertiary", function()
			toggleTryOn(item)
		end, true, 3)
	end
	if item.status ~= "owned" then
		if item.isInCart then
			W.BarButton(bar, "Remove from cart", "Tertiary", function()
				act(function() return UGCClient.SetInCart(item.assetId, false) end, "Removed from cart")
			end, true, 4)
		else -- always Tertiary, in and out of battle (ugc_rules 17/56)
			W.BarButton(bar, "Add to cart", "Tertiary", function()
				act(function() return UGCClient.SetInCart(item.assetId, true) end, "Added to cart")
			end, true, 4)
		end
	end
	-- Details (user decision 2026-10-12): opens the info popup (ID/creator/type/price/status/description).
	W.BarButton(bar, "Details", "Tertiary", function() W.ShowItemDetails(item) end, true, 5)
end

-- Rebuilds only the action bar (selection change / try-on toggle), not the grid.
buildBar = function(item: any, view: any)
	local root = _barRoot
	if not root then return end
	local old = root:FindFirstChild("ActionBar")
	if old then old:Destroy() end -- MEM-002
	_barItem, _barView = item, view
	local detail: string? = nil
	if item then
		detail = UGCClient.GetStatusLabel(item)
		if item.isEligible == false then
			detail = `{detail} · Not for {_unit and _unit.raceName or "this unit"}` -- race slot block (66)
		elseif item.status ~= "owned" and (item.refundOnBuy or 0) > 0 and not item.isOffSale then
			detail = `{detail} · Buy refunds {W.FormatGold(item.refundOnBuy)} gold` -- ugc_rules 53
		end
	end
	local bar = W.MakeActionBar(root, 5, item, detail)
	if item then fillActions(bar, item, view) end
end

local function selectItem(item: any, view: any)
	local prev = _selected[_subTab]
	if prev and _tiles[prev] then W.SetTileSelected(_tiles[prev], false) end
	_selected[_subTab] = item.assetId
	W.SetTileSelected(_tiles[item.assetId], true)
	buildBar(item, view)
end

--------------------------------------------------
-- PANELS
--------------------------------------------------

local function buildMain(view: any)
	local main = _main
	if not main or main.Parent == nil then return end
	-- Keep the grid's scroll position across rebuilds of the same sub-tab
	-- (add/remove cart, trial, buy all trigger a full rebuild).
	local oldGrid = main:FindFirstChild("ItemGrid", true)
	local keepScroll = if oldGrid and oldGrid:IsA("ScrollingFrame") and _lastBuiltSubTab == _subTab
		then oldGrid.CanvasPosition else nil
	_lastBuiltSubTab = _subTab
	local root = contentFrame(main, "OutfitContent", true)

	-- Header: sub-tabs (63) + merchant shortcut (72) + checkout (Cart only, 45)
	local header = W.Row(root, 1)
	local cartText = `Cart ({view.cartCount or 0}/{view.cartCap or UGCCatalogData.CART_CAP})`
	for i, tab in { { SUB_MY_ITEMS, "My Items" }, { SUB_CART, cartText } } do
		-- Sub-tabs use the old 9-slice text bars (user ruling 2026-10-08): Active = bronze, Inactive = navy.
		Theme.MakeTabButton(header, tab[2], if _subTab == tab[1] then "Active" else "Inactive", function()
			if _subTab ~= tab[1] then
				_subTab = tab[1]
				refresh()
			end
		end, {
			name = "SubTab_" .. tab[1],
			size = UDim2.fromOffset(Theme.MinSize.TouchTarget, W.COMPACT_H), -- compact header (2026-10-08)
			autoWidth = true,
			layoutOrder = i,
		})
	end
	local merchant = UGCClient.MakeTextButton(header, "UGC Merchant", Theme.Colors.TextGold, function()
		UGCMerchantScreen.Open({ onClose = function() refresh() end })
	end)
	merchant.TextColor3 = Theme.Colors.Background
	merchant.LayoutOrder = 10
	W.Compact(merchant)
	local msg = W.MakeMessage(root, 3)
	if _subTab == SUB_CART then
		-- Checkout ONLY outside battle (ugc_rules 45); the server also refuses it.
		-- Primary bar (2026-10-09); compact header height (user ruling 2026-10-08).
		local canCheckout = not view.isBattleActive and (view.cartCount or 0) > 0
		Theme.MakeBarButton(header, "Checkout all", if canCheckout then "Primary" else "Disabled", function()
			W.Checkout(say, refresh)
		end, { name = "Btn_CheckoutAll", minHeight = W.COMPACT_H, layoutOrder = 11 })
	end

	W.MakeFilterBar(root, _filter, 2, refresh)
	if _pendingMessage then
		W.SetMessage(msg, _pendingMessage, _pendingIsError)
		_pendingMessage = nil
	end

	local list = {}
	for _, item in view.items or {} do
		local isIn = if _subTab == SUB_CART then item.isInCart == true else MY_ITEMS_STATUSES[item.status] == true
		if isIn and W.PassesFilter(item, _filter) then table.insert(list, item) end
	end
	W.SortItems(list, _filter)

	if #list == 0 then
		local text = if _subTab == SUB_CART then "Your cart is empty. Add items from the UGC Merchant or from a unit's worn items in battle."
			else "No UGC items yet. Open the UGC Merchant to start a free trial, rent or buy."
		if (view.items and #view.items or 0) > 0 and (_filter.type ~= "All" or _filter.status ~= "All" or (_filter.search or "") ~= "") then
			text = "No items match these filters."
		end
		W.EmptyState(root, text).LayoutOrder = 4
		table.clear(_tiles)
		_barRoot, _barItem, _barView = nil, nil, nil
		root.Parent = main -- NET-004: built off-tree, parented once
	else
		local grid = W.MakeTileGrid(root, 4)
		table.clear(_tiles)
		_barRoot = root
		local sel = W.PickSelected(list, _selected[_subTab]) -- reselect by assetId after a refresh
		if sel then _selected[_subTab] = sel.assetId end
		local equips = view.equips or {}
		for i, item in list do
			local isWorn = _unit ~= nil and equips[item.slot] == item.assetId
			_tiles[item.assetId] = W.MakeTile(grid, item, i, sel ~= nil and item.assetId == sel.assetId, function()
				selectItem(item, view)
			end, { isWorn = isWorn })
		end
		buildBar(sel, view)
		root.Parent = main -- NET-004: built off-tree, parented once
		-- Deferred: AutomaticCanvasSize must resolve first or the position is clamped to 0.
		if keepScroll then task.defer(function() if grid.Parent then grid.CanvasPosition = keepScroll end end) end
	end
end

local function clearPreviewConns()
	for _, c in _previewConns do c:Disconnect() end -- PRF-004
	table.clear(_previewConns)
end

local function tryOnIds(): { number }
	local ids = {}
	for _, slot in UGCCatalogData.SLOTS do
		if _tryOn[slot] then table.insert(ids, _tryOn[slot]) end
	end
	return ids
end

-- Preview tab body: ViewportFrame + WorldModel, drag to rotate, try-on list.
local function buildPreviewBody(root: Frame)
	clearPreviewConns()
	local box = Instance.new("Frame")
	box.Name = "PreviewBox"
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromScale(1, 0)
	box.LayoutOrder = 3
	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = box

	local names = {}
	for _, slot in UGCCatalogData.SLOTS do if _tryOnNames[slot] then table.insert(names, _tryOnNames[slot]) end end
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Viewport"
	-- Fill to the panel bottom; reserve the footer only while something is tried on (2026-10-08).
	vp.Size = if #names > 0 then UDim2.new(1, 0, 1, -W.COMPACT_H - Theme.Spacing.xs) else UDim2.fromScale(1, 1)
	vp.BackgroundColor3 = Theme.Colors.Surface
	vp.BackgroundTransparency = 0.3
	vp.BorderSizePixel = 0
	vp.Ambient = Color3.fromRGB(170, 170, 170)
	vp.LightColor = Color3.fromRGB(255, 255, 255)
	vp.LightDirection = Vector3.new(-1, -1, -1)
	local vc = Instance.new("UICorner"); vc.CornerRadius = Theme.CornerRadius.md; vc.Parent = vp
	local world = Instance.new("WorldModel"); world.Parent = vp
	local cam = Instance.new("Camera"); cam.FieldOfView = 40; cam.Parent = vp
	vp.CurrentCamera = cam
	local status = W.Label(vp, "Loading…", { size = UDim2.fromScale(1, 1), autoSize = Enum.AutomaticSize.None,
		align = Enum.TextXAlignment.Center, color = Theme.Colors.TextSecondary })
	status.TextYAlignment = Enum.TextYAlignment.Center
	vp.Parent = box

	-- Try-on footer: what's being tried + Clear.
	local foot = Instance.new("Frame")
	foot.Name = "TryOnBar"
	foot.BackgroundTransparency = 1
	foot.Size = UDim2.new(1, 0, 0, W.COMPACT_H)
	foot.Position = UDim2.new(0, 0, 1, -W.COMPACT_H)
	-- No empty-state hint (user rule 2026-10-08: no helper text without approval).
	if #names > 0 then
		local info = W.Label(foot, `Trying on: {table.concat(names, ", ")}`,
			{ size = UDim2.new(1, -96, 1, 0), autoSize = Enum.AutomaticSize.None, color = Theme.Colors.TextSecondary,
				textSize = Theme.Text.Tiny() })
		info.TextYAlignment = Enum.TextYAlignment.Center
		local clear = UGCClient.MakeTextButton(foot, "Clear try-on", Theme.Colors.Surface, function()
			table.clear(_tryOn); table.clear(_tryOnNames)
			if _lastView then buildSide(_lastView) end
			if _barView then buildBar(_barItem, _barView) end -- Remove try-on -> Try on
		end)
		W.Compact(clear)
		clear.AnchorPoint = Vector2.new(1, 0)
		clear.Position = UDim2.new(1, 0, 0, 0)
	end
	foot.Parent = box
	box.Parent = root

	-- Drag to rotate (mouse + touch). Connections tracked; cleared on re-render/Unmount.
	local yaw, dragging, lastX = PREVIEW_START_YAW, false, 0
	local model: Model? = nil
	local pivot = CFrame.new()
	local function applyYaw()
		if model then model:PivotTo(pivot * CFrame.Angles(0, math.rad(yaw), 0)) end
	end
	table.insert(_previewConns, vp.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = true; lastX = input.Position.X
		end
	end))
	table.insert(_previewConns, UserInputService.InputChanged:Connect(function(input: InputObject)
		if not dragging then return end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
			yaw += (input.Position.X - lastX) * 0.6
			lastX = input.Position.X
			applyYaw()
		end
	end))
	table.insert(_previewConns, UserInputService.InputEnded:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then dragging = false end
	end))

	-- Zoom (2026-10-08): mouse wheel over the preview, two-finger pinch on touch.
	local ZOOM_MIN, ZOOM_MAX = 0.35, 1.6
	local zoom, baseDist, focus = 1, 0, Vector3.zero
	local function applyZoom()
		if baseDist <= 0 then return end
		cam.CFrame = CFrame.lookAt(focus + Vector3.new(0, 0, baseDist * zoom), focus)
	end
	local function isOverPreview(pos: Vector2): boolean
		local p, s = vp.AbsolutePosition, vp.AbsoluteSize
		return pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y
	end
	table.insert(_previewConns, vp.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			zoom = math.clamp(zoom * (1 - input.Position.Z * 0.1), ZOOM_MIN, ZOOM_MAX)
			applyZoom()
		end
	end))
	local pinchStart = 1
	table.insert(_previewConns, UserInputService.TouchPinch:Connect(function(points: { Vector2 }, scale: number, _vel: number, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			if not (points[1] and isOverPreview(points[1])) then pinchStart = -1; return end
			pinchStart = zoom
			dragging = false -- a pinch is not a rotate
		elseif pinchStart > 0 and scale > 0 then
			zoom = math.clamp(pinchStart / scale, ZOOM_MIN, ZOOM_MAX)
			applyZoom()
		end
	end))

	-- Ask the server for the model, then copy it into the viewport.
	local unitId = _unit and _unit.id
	if not unitId then status.Text = "Select a unit to preview"; return end
	_previewToken += 1
	local token = _previewToken
	task.spawn(function()
		local res = UGCClient.RequestPreview(unitId, tryOnIds())
		if token ~= _previewToken or vp.Parent == nil then return end
		if not res.ok and res.error == "Too fast — try again" then
			task.delay(0.6, function() if token == _previewToken and _lastView then buildSide(_lastView) end end)
			return
		end
		if not res.ok then status.Text = res.error or "Preview unavailable"; return end
		local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		local folder = pg and pg:WaitForChild("UGCPreview", 5)
		local src = folder and folder:WaitForChild("PreviewModel", 5)
		if token ~= _previewToken or vp.Parent == nil then return end
		if not src or not src:IsA("Model") then status.Text = "Preview unavailable"; return end
		local copy = src:Clone()
		local cf, size = copy:GetBoundingBox()
		pivot = copy:GetPivot()
		local dist = math.max(size.Y, size.X) / (2 * math.tan(math.rad(cam.FieldOfView / 2))) + size.Z
		baseDist, focus = dist, cf.Position
		applyZoom()
		copy.Parent = world -- NET-004: local copy, framed before showing
		model = copy :: Model
		applyYaw()
		status.Visible = false
	end)
end

buildSide = function(view: any)
	_lastView = view
	local side = _side
	if not side or side.Parent == nil then return end
	local root = contentFrame(side, "OutfitSide", true)
	-- Worn / Preview sub-tabs (compact, same style as the main sub-tabs).
	local tabs = W.Row(root, 2)
	for i, t in { SIDE_WORN, SIDE_PREVIEW } do
		Theme.MakeTabButton(tabs, t, if _sideTab == t then "Active" else "Inactive", function()
			if _sideTab ~= t then _sideTab = t; buildSide(view) end
		end, { name = "SideTab_" .. t, size = UDim2.fromOffset(Theme.MinSize.TouchTarget, W.COMPACT_H),
			autoWidth = true, layoutOrder = i })
	end
	if _sideTab == SIDE_PREVIEW then
		buildPreviewBody(root)
		root.Parent = side
		return
	end
	clearPreviewConns()
	local names: { [number]: string } = {}
	for _, item in view.items or {} do names[item.assetId] = item.name end
	local blocks = (_unit and _unit.raceName and UGCCatalogData.RACE_SLOT_BLOCKS[_unit.raceName]) or {}

	local sf = Instance.new("ScrollingFrame")
	sf.Name = "Slots"
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel = 0
	sf.Size = UDim2.fromScale(1, 0)
	sf.CanvasSize = UDim2.new()
	sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sf.ScrollingDirection = Enum.ScrollingDirection.Y
	sf.ScrollBarThickness = 6
	sf.LayoutOrder = 3
	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = sf
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, Theme.Spacing.xs)
	list.Parent = sf

	local equips = view.equips or {}
	for i, slot in UGCCatalogData.SLOTS do
		local row = W.Row(sf, i)
		-- Slot icon (2026-10-08) left of the slot name; fixed width keeps every row aligned
		-- whether or not the slot has art yet.
		local iconPx = 24
		local slotIcon = Instance.new("ImageLabel")
		slotIcon.Name = "SlotIcon"
		slotIcon.Size = UDim2.fromOffset(iconPx, iconPx)
		slotIcon.BackgroundTransparency = 1
		slotIcon.ScaleType = Enum.ScaleType.Fit
		slotIcon.Image = UGCCatalogData.SLOT_ICONS[slot] or ""
		slotIcon.LayoutOrder = 0
		slotIcon.Parent = row -- properties set before Parent (NET-004)
		W.Label(row, slot, { size = UDim2.new(0.3, -iconPx, 0, Theme.MinSize.TouchTarget), autoSize = Enum.AutomaticSize.None,
			bold = true, color = Theme.Colors.TextSecondary, order = 1 })
		local id = equips[slot]
		if blocks[slot] then
			W.Label(row, `Not for {_unit.raceName}`, { size = UDim2.new(0.65, 0, 0, Theme.MinSize.TouchTarget),
				autoSize = Enum.AutomaticSize.None, color = Theme.Colors.TextDisabled, order = 2 })
		elseif id then
			W.Label(row, names[id] or tostring(id), { size = UDim2.new(0.4, 0, 0, Theme.MinSize.TouchTarget),
				autoSize = Enum.AutomaticSize.None, order = 2 })
			local unitId = _unit and _unit.id
			if unitId ~= nil and not view.isBattleActive then -- hidden in battle (ugc_rules 56)
				local btn = UGCClient.MakeTextButton(row, "Unequip", Theme.Colors.Surface, function()
					act(function() return UGCClient.Unequip(unitId, slot) end, "Unequipped")
				end, true)
				btn.LayoutOrder = 3
			end
		else
			W.Label(row, "—", { size = UDim2.new(0.65, 0, 0, Theme.MinSize.TouchTarget), autoSize = Enum.AutomaticSize.None,
				color = Theme.Colors.TextDisabled, order = 2 })
		end
	end
	sf.Parent = root
	root.Parent = side
end

--------------------------------------------------
-- PUBLIC
--------------------------------------------------

refresh = function()
	if not _main then return end -- not mounted (e.g. merchant closed during Unmount)
	_token += 1
	local token = _token
	task.spawn(function()
		local unitId = _unit and _unit.id
		local res = UGCClient.GetView(unitId)
		if token ~= _token then return end -- a newer render started
		if not res.ok and res.error == "Too fast — try again" then
			task.delay(RETRY_TOO_FAST, function()
				if token == _token then refresh() end
			end)
			return
		end
		if not res.ok or type(res.data) ~= "table" then
			warn(`[UGCOutfitTab] Could not load UGC view: {res.error}`)
			if _main and _main.Parent then
				local root = contentFrame(_main, "OutfitContent", true)
				W.EmptyState(root, "UGC items are unavailable right now.")
				root.Parent = _main
			end
			return
		end
		buildMain(res.data)
		buildSide(res.data)
	end)
end

-- Called by LoadoutScreen when the OUTFIT tab is shown or the screen refreshes
-- (unit change included). unit = { id, name, raceName } (selected roster unit).
function UGCOutfitTab.Render(mainPanel: GuiObject, sidePanel: GuiObject, unit: any)
	_main, _side = mainPanel, sidePanel
	local newId = if type(unit) == "table" then unit.id else nil
	if not _unit or _unit.id ~= newId then
		table.clear(_tryOn); table.clear(_tryOnNames) -- try-on is per unit
	end
	_unit = if type(unit) == "table" then { id = unit.id, name = unit.name, raceName = unit.raceName } else nil
	if not _conn then
		-- Server facts: purchases, refunds, expiries, battle end (PRF-004: tracked).
		_conn = UGCClient.OnStateChanged(function(change: any)
			local text = W.DescribeChange(change)
			if text then say(text) end
			if UGCMerchantScreen.IsOpen() then UGCMerchantScreen.Refresh(text) end
			if _main and _main.Parent then refresh() end
		end)
	end
	refresh()
end

-- Called when the tab is hidden or the loadout screen closes.
function UGCOutfitTab.Unmount()
	if W.CloseMenu then W.CloseMenu() end -- drop any open Type/Status/Sort list
	if _conn then _conn:Disconnect(); _conn = nil end
	clearPreviewConns()
	_previewToken += 1
	_lastView = nil
	_token += 1
	table.clear(_tryOn); table.clear(_tryOnNames) -- try-on never outlives the Outfit tab
	table.clear(_tiles)
	_barRoot, _barItem, _barView = nil, nil, nil
	for _, panel in { _main, _side } do
		if panel then
			for _, name in { "OutfitContent", "OutfitSide" } do
				local f = panel:FindFirstChild(name)
				if f then f:Destroy() end
			end
		end
	end
	_main, _side, _unit = nil, nil, nil
	UGCMerchantScreen.Close() -- after unmounting, so its onClose refresh is a no-op
end

return UGCOutfitTab
