--!strict
-- UGCInspectorOutfit.lua
-- CTRBLXAI | Detailed Unit View (in-battle UnitInspectorPanel) — "Outfit" tab
-- loadout_ui_spec 92-97, ugc_rules 17/29/33/56/57/58 (2026-10-09).
--
--   * No sub-tabs. LEFT: the unit's worn UGC, one row per occupied slot (styled
--     like the Outfit screen list). RIGHT: a read-only preview of the unit.
--   * Tapping a row opens a detail popup (same overlay pattern as the Equip-tab
--     gear popup): name, slot, creator, the PLAYER's own status (Owned / Trial N /
--     Rent N / Out of use / Free / Not owned) and "Off sale". Its only actions are
--     Add to cart / Remove from cart (always Tertiary, id 56). No Robux purchase,
--     no equip (id 95).
--   * Works for player AND enemy units (id 96): worn ids come from the existing
--     GetUnitWornUGC query (enemy looks are planned by UGCOutfitService); the
--     preview uses the existing read-only RequestUGCPreview.
--
-- Display only (ARC-001): every fact comes from the server; nothing here decides
-- ownership, price or access. Connections are tracked and cleared (PRF-004).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CTRBLXAI = ReplicatedStorage:WaitForChild("CTRBLXAI", 10) :: Instance
local UI = CTRBLXAI:WaitForChild("UI", 10) :: Instance
local Theme = require(UI:WaitForChild("Theme", 10) :: ModuleScript) :: any
local UGCClient = require(UI:WaitForChild("UGCClient", 10) :: ModuleScript) :: any
local UGCCatalogData = require(ReplicatedStorage:WaitForChild("Content", 10):WaitForChild("UGCCatalogData", 10) :: ModuleScript) :: any

local UGCInspectorOutfit = {}

export type Hooks = {
	setOverlay: (ScreenGui?) -> (), -- inspector tracks the popup (its click-outside guard)
	closeOverlay: () -> (),
}

local ROW_H = Theme.MinSize.TouchTarget -- 44 px rows (loadout_ui_spec 73)
local ICON_PX = 24
local PREVIEW_START_YAW = 200

local _conns: { RBXScriptConnection } = {}
local _token = 0

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function label(parent: Instance, text: string, props: any?): TextLabel
	local p = props or {}
	local l = Instance.new("TextLabel")
	l.Name = p.name or "Label"
	l.Text = text
	l.Font = if p.bold then Theme.Font.PrimaryBold else Theme.Font.Primary
	l.TextSize = p.textSize or Theme.Text.Small()
	l.TextColor3 = p.color or Theme.Colors.TextPrimary
	l.TextXAlignment = p.align or Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.TextWrapped = p.wrap == true
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Size = p.size or UDim2.new(1, 0, 0, 16)
	l.Position = p.position or UDim2.new()
	l.LayoutOrder = p.order or 0
	l.Parent = parent -- NET-004: properties before Parent
	return l
end

-- The player's own status for an item (same wording as the Outfit screen).
local function statusText(item: any): string
	local s = item.status
	if s == "owned" or item.isOwned then return "Owned" end
	if s == "trial" then return `Trial: {item.remaining or 0} left` end
	if s == "rent" then return `Rented: {item.remaining or 0} left` end
	if s == "expired" then return "Out of use" end
	if item.isFree then return "Free" end
	return "Not owned"
end

-- Short row badge (loadout_ui_spec 88 vocabulary).
local function badgeText(item: any): string?
	local s = item.status
	if s == "owned" or item.isOwned then return "Owned" end
	if s == "trial" then return `Trial {item.remaining or 0}` end
	if s == "rent" then return `Rent {item.remaining or 0}` end
	if item.isOffSale then return "Off sale" end
	if s == "expired" then return "Out of use" end
	if item.isFree then return "Free" end
	return nil
end

local function thumbnail(item: any): string
	if item.bundleId then
		return `rbxthumb://type=BundleThumbnail&id={item.bundleId}&w=150&h=150`
	end
	return `rbxthumb://type=Asset&id={item.assetId}&w=150&h=150`
end

function UGCInspectorOutfit.Cleanup()
	for _, c in _conns do c:Disconnect() end
	table.clear(_conns)
	_token += 1 -- drops any in-flight async result
end

--------------------------------------------------
-- DETAIL POPUP (loadout_ui_spec 94/95)
--------------------------------------------------

local showPopup: (any, Hooks, () -> ()) -> ()

showPopup = function(item: any, hooks: Hooks, onChanged: () -> ())
	hooks.closeOverlay()
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "InspectorUGCDetail"
	gui.DisplayOrder = 150 -- same layer as the gear popup
	gui.ResetOnSpawn = false

	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.Text = ""
	backdrop.BorderSizePixel = 0
	backdrop.AutoButtonColor = false
	backdrop.Parent = gui

	local panel = Theme.MakePanel("InspUGCDetail", UDim2.new(0.55, 0, 0.9, 0), UDim2.new(0, 8, 0.05, 0),
		Vector2.new(0, 0), gui)
	panel.ClipsDescendants = true
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10); pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 12); pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = panel
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, Theme.Spacing.xs)
	list.Parent = panel

	-- Header: thumbnail + name / slot / creator.
	local head = Instance.new("Frame")
	head.Name = "Header"
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, 64)
	head.LayoutOrder = 1
	local thumb = Instance.new("ImageLabel")
	thumb.Size = UDim2.fromOffset(64, 64)
	thumb.BackgroundColor3 = Theme.Colors.Surface
	thumb.BackgroundTransparency = 0.3
	thumb.BorderSizePixel = 0
	thumb.ScaleType = Enum.ScaleType.Fit
	thumb.Image = thumbnail(item)
	local tc = Instance.new("UICorner"); tc.CornerRadius = Theme.CornerRadius.md; tc.Parent = thumb
	thumb.Parent = head
	local textX = 72
	label(head, item.name or tostring(item.assetId), { bold = true, textSize = Theme.Text.Heading(),
		size = UDim2.new(1, -textX, 0, 22), position = UDim2.fromOffset(textX, 0) })
	label(head, item.slot or "", { color = Theme.Colors.TextSecondary,
		size = UDim2.new(1, -textX, 0, 18), position = UDim2.fromOffset(textX, 24) })
	if type(item.creator) == "string" and item.creator ~= "" then
		label(head, `By {item.creator}`, { color = Theme.Colors.TextSecondary, textSize = Theme.Text.Tiny(),
			size = UDim2.new(1, -textX, 0, 16), position = UDim2.fromOffset(textX, 44) })
	end
	head.Parent = panel

	-- Status (the player's own) + Off sale marker.
	local statusRow = Instance.new("Frame")
	statusRow.Name = "Status"
	statusRow.BackgroundTransparency = 1
	statusRow.Size = UDim2.new(1, 0, 0, 22)
	statusRow.LayoutOrder = 2
	local srl = Instance.new("UIListLayout")
	srl.FillDirection = Enum.FillDirection.Horizontal
	srl.VerticalAlignment = Enum.VerticalAlignment.Center
	srl.Padding = UDim.new(0, Theme.Spacing.sm)
	srl.SortOrder = Enum.SortOrder.LayoutOrder
	srl.Parent = statusRow
	local st = label(statusRow, statusText(item), { bold = true, color = UGCClient.GetStatusColor(item.status or "locked"),
		size = UDim2.new(0, 0, 1, 0), order = 1 })
	st.AutomaticSize = Enum.AutomaticSize.X
	if item.isOffSale then
		local m = UGCClient.CreateOffSaleMarker(statusRow)
		m.LayoutOrder = 2
	end
	statusRow.Parent = panel

	local msg = label(panel, "", { name = "Message", order = 4, wrap = true, textSize = Theme.Text.Tiny(),
		color = Theme.Colors.TextSecondary, size = UDim2.new(1, 0, 0, 18) })

	-- Only action: Add / Remove cart (Tertiary). Owned items can't be added (server rule).
	local isOwned = item.status == "owned" or item.isOwned == true
	if not isOwned then
		local actions = Instance.new("Frame")
		actions.Name = "Actions"
		actions.BackgroundTransparency = 1
		actions.Size = UDim2.new(1, 0, 0, ROW_H)
		actions.LayoutOrder = 3
		local al = Instance.new("UIListLayout")
		al.FillDirection = Enum.FillDirection.Horizontal
		al.Padding = UDim.new(0, Theme.Spacing.xs)
		al.Parent = actions
		local wantInCart = not item.isInCart
		Theme.MakeBarButton(actions, if item.isInCart then "Remove from cart" else "Add to cart", "Tertiary", function()
			local res = UGCClient.SetInCart(item.assetId, wantInCart)
			if res.ok then
				item.isInCart = wantInCart
				onChanged()
				showPopup(item, hooks, onChanged) -- redraw with the new label
			else
				msg.Text = res.error or "Request failed"
				msg.TextColor3 = Theme.Colors.Danger
			end
		end, { textSize = Theme.Text.Small() })
		actions.Parent = panel
	end

	-- Close: outside tap, or the same square BACK icon the gear popup uses (id 75).
	backdrop.Activated:Connect(function()
		local m = UserInputService:GetMouseLocation()
		local pos, sz = panel.AbsolutePosition, panel.AbsoluteSize
		if m.X >= pos.X and m.X <= pos.X + sz.X and m.Y >= pos.Y and m.Y <= pos.Y + sz.Y then return end
		hooks.closeOverlay()
	end)
	local fb = Theme.FooterBar
	local backBtn = Theme.MakeButton(gui, "BACK", "Secondary", function() hooks.closeOverlay() end)
	backBtn.Size = UDim2.new(0, fb.BTN_W, 0, fb.BTN_H)
	backBtn.Position = UDim2.new(1, -fb.PAD, 1, -fb.PAD)
	backBtn.AnchorPoint = Vector2.new(1, 1)

	gui.Parent = pg -- NET-004
	hooks.setOverlay(gui)
end

--------------------------------------------------
-- LEFT: worn list
--------------------------------------------------

local function buildRow(parent: Instance, item: any, order: number, hooks: Hooks, onChanged: () -> ())
	local row = Instance.new("TextButton")
	row.Name = "Worn_" .. tostring(item.slot)
	row.Text = ""
	row.AutoButtonColor = true
	row.BackgroundColor3 = Theme.Colors.Panel
	row.BackgroundTransparency = 0.3
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, -4, 0, ROW_H)
	row.LayoutOrder = order
	local rc = Instance.new("UICorner"); rc.CornerRadius = Theme.CornerRadius.sm; rc.Parent = row
	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.fromOffset(ICON_PX, ICON_PX)
	icon.Position = UDim2.new(0, 4, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = UGCCatalogData.SLOT_ICONS[item.slot] or ""
	icon.Parent = row
	local x = ICON_PX + 10
	label(row, item.slot or "", { bold = true, color = Theme.Colors.TextSecondary, textSize = Theme.Text.Tiny(),
		size = UDim2.new(1, -x - 4, 0, 14), position = UDim2.fromOffset(x, 4) })
	label(row, item.name or tostring(item.assetId), { size = UDim2.new(1, -x - 60, 0, 18), position = UDim2.fromOffset(x, 20) })
	local b = badgeText(item)
	if b then
		local badge = label(row, b, { bold = true, textSize = Theme.Text.Badge(), align = Enum.TextXAlignment.Center,
			size = UDim2.new(0, 0, 0, 16), position = UDim2.new(1, -4, 0.5, 0) })
		badge.AnchorPoint = Vector2.new(1, 0.5)
		badge.AutomaticSize = Enum.AutomaticSize.X
		badge.BackgroundColor3 = if item.isOffSale and item.status ~= "owned" then Theme.Colors.TextDisabled
			else UGCClient.GetStatusColor(item.status or "locked")
		badge.BackgroundTransparency = 0.15
		badge.TextStrokeTransparency = 0.4
		local bc = Instance.new("UICorner"); bc.CornerRadius = Theme.CornerRadius.sm; bc.Parent = badge
		local bp = Instance.new("UIPadding"); bp.PaddingLeft = UDim.new(0, 4); bp.PaddingRight = UDim.new(0, 4); bp.Parent = badge
	end
	row.Activated:Connect(function() showPopup(item, hooks, onChanged) end) -- dies with the row
	row.Parent = parent -- NET-004
end

--------------------------------------------------
-- RIGHT: read-only preview (RequestUGCPreview, no try-on)
--------------------------------------------------

local function buildPreview(parent: Instance, unitId: string, token: number)
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Preview"
	vp.Size = UDim2.fromScale(1, 1)
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
	local status = label(vp, "Loading…", { size = UDim2.fromScale(1, 1), align = Enum.TextXAlignment.Center,
		color = Theme.Colors.TextSecondary, wrap = true })
	vp.Parent = parent

	-- Drag to rotate (mouse + touch).
	local yaw, dragging, lastX = PREVIEW_START_YAW, false, 0
	local model: Model? = nil
	local pivot = CFrame.new()
	local function applyYaw()
		if model then model:PivotTo(pivot * CFrame.Angles(0, math.rad(yaw), 0)) end
	end
	table.insert(_conns, vp.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = true; lastX = input.Position.X
		end
	end))
	table.insert(_conns, UserInputService.InputChanged:Connect(function(input: InputObject)
		if not dragging then return end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
			yaw += (input.Position.X - lastX) * 0.6
			lastX = input.Position.X
			applyYaw()
		end
	end))
	table.insert(_conns, UserInputService.InputEnded:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then dragging = false end
	end))

	task.spawn(function()
		local res = UGCClient.RequestPreview(unitId, {})
		if token ~= _token or vp.Parent == nil then return end
		if not res.ok then status.Text = res.error or "Preview unavailable"; return end
		local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		local folder = pg and pg:WaitForChild("UGCPreview", 5)
		local src = folder and folder:WaitForChild("PreviewModel", 5)
		if token ~= _token or vp.Parent == nil then return end
		if not src or not src:IsA("Model") then status.Text = "Preview unavailable"; return end
		local copy = src:Clone()
		local cf, size = copy:GetBoundingBox()
		pivot = copy:GetPivot()
		local dist = math.max(size.Y, size.X) / (2 * math.tan(math.rad(cam.FieldOfView / 2))) + size.Z
		cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, 0, dist), cf.Position)
		copy.Parent = world -- local copy, framed before showing
		model = copy :: Model
		applyYaw()
		status.Visible = false
	end)
end

--------------------------------------------------
-- RENDER (called by UnitInspectorPanel for the "Outfit" tab)
--------------------------------------------------

function UGCInspectorOutfit.Render(content: Instance, data: any, hooks: Hooks)
	UGCInspectorOutfit.Cleanup()
	local token = _token
	local unitId = type(data) == "table" and data.unitId or nil

	local h = 180
	if content:IsA("GuiObject") then h = math.max(180, (content :: GuiObject).AbsoluteSize.Y - 8) end
	local box = Instance.new("Frame")
	box.Name = "OutfitTab"
	box.BackgroundTransparency = 1
	box.Size = UDim2.new(1, 0, 0, h)
	box.LayoutOrder = 1

	local left = Instance.new("ScrollingFrame")
	left.Name = "Worn"
	left.Size = UDim2.new(0.5, -3, 1, 0)
	left.BackgroundTransparency = 1
	left.BorderSizePixel = 0
	left.ScrollBarThickness = 4
	left.AutomaticCanvasSize = Enum.AutomaticSize.Y
	left.CanvasSize = UDim2.new()
	local ll = Instance.new("UIListLayout")
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Padding = UDim.new(0, 4)
	ll.Parent = left
	local loading = label(left, "Loading…", { color = Theme.Colors.TextSecondary })
	left.Parent = box

	local right = Instance.new("Frame")
	right.Name = "PreviewSide"
	right.Size = UDim2.new(0.5, -3, 1, 0)
	right.Position = UDim2.new(0.5, 3, 0, 0)
	right.BackgroundTransparency = 1
	right.Parent = box
	box.Parent = content -- NET-004

	if type(unitId) ~= "string" then
		loading.Text = "—"
		return
	end
	buildPreview(right, unitId, token)

	local function fill()
		task.spawn(function()
			local res = UGCClient.GetWornItems(unitId)
			if token ~= _token or left.Parent == nil then return end
			for _, c in left:GetChildren() do
				if c:IsA("GuiObject") then c:Destroy() end -- MEM-002
			end
			local items = if res.ok and type(res.data) == "table" and type(res.data.items) == "table" then res.data.items else nil
			if not items then
				label(left, res.error or "Outfit unavailable", { color = Theme.Colors.TextSecondary, wrap = true })
				return
			end
			if #items == 0 then
				label(left, "—", { color = Theme.Colors.TextDisabled })
				return
			end
			local bySlot: { [string]: any } = {}
			for _, it in items do if type(it) == "table" and it.slot then bySlot[it.slot] = it end end
			local order = 0
			for _, slot in UGCCatalogData.SLOTS do
				local it = bySlot[slot]
				if it then
					order += 1
					buildRow(left, it, order, hooks, function() end)
				end
			end
		end)
	end
	fill()
end

return UGCInspectorOutfit
