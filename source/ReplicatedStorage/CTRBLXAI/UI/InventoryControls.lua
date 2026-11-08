--!strict
-- InventoryControls.lua
-- CTRBLXAI | The Loadout inventory's own controls, shared (2026-11-08, user: "Loadout screen is
-- our model that Runeforge needs to adapt to"). These pieces were local to LoadoutScreen
-- (buildInventory / buildItemGrid / the GEAR | CONSUMABLES switch); they moved here UNCHANGED so
-- the Loadout and the Runeforge draw the same bar, menus, level labels, grid spacing and sub-tabs
-- from one place (DAT-001 / AP-021).
--
--   InventoryControls.BarHeight / SubTabHeight / SubTabGap / ButtonWidth / ControlGap /
--     GridCellPadding / MenuRowHeight / MenuMinWidth   (the Loadout values)
--   InventoryControls.MakeFilterButton(row, text, order, isActive, iconAsset?) -> TextButton
--     (the Loadout Type / Rarity / sort button, 14 px icon). 2026-11-08 user ruling: white text with a
--     black outline like every button; the active state is the gold-tint selected background.
--   InventoryControls.ShowMenu(playerGui, anchor, options, onSelect, close, displayOrder?) -> ScreenGui
--     (the Loadout dropdown: 22 px rows, optional 16 px icon per row, outside tap closes).
--     options = {{ label, value, icon?, active? }}; onSelect(value, index); close() must destroy
--     the returned ScreenGui (the caller keeps it).
--   InventoryControls.MakeLevelLabel(tile, text) -> (TextLabel, width)  (Loadout "Lv.N" label)
--   InventoryControls.MakeSubTabs(parent, defs, activeId, onPick, layoutOrder?) -> Frame
--     (the Loadout GEAR | CONSUMABLES row: two Theme.MakeTabButton halves, 24 px tall)
--   InventoryControls.AddTileMarkers(card, cellW, gearLvW, isEquipped, isEquippedByOther, isNew, hasCountBadge)
--     (the Loadout tile "E" equipped marker, gold = this unit / grey = another unit, and the NEW badge)
-- Display only (ARC-001). Tap-only (.Activated, project_rules 243).

local WAIT = 10
local themeModule = script.Parent:WaitForChild("Theme", WAIT)
if not themeModule then
	error("[InventoryControls] Theme module not found")
end
local Theme: any = (require :: any)(themeModule)

local InventoryControls = {}

InventoryControls.BarHeight = 24        -- search + Type / Rarity / sort row
InventoryControls.SubTabHeight = 24     -- same height as the Outfit Worn/Preview sub-tabs (user ruling 2026-10-08)
InventoryControls.SubTabGap = 6
InventoryControls.ButtonWidth = 62
InventoryControls.ControlGap = 3        -- between the bar's controls
InventoryControls.GridCellPadding = UDim2.new(0, 4, 0, 3)
InventoryControls.MenuRowHeight = 22
InventoryControls.MenuMinWidth = 80
InventoryControls.MenuDisplayOrder = 105

-- Button / menu text: white with a black outline, the same three settings Theme uses for its
-- bar buttons (user ruling 2026-11-08: the white-outline rule wins over the old grey/gold text).
local function outlineText(lbl: any, color: Color3?)
	lbl.TextColor3 = color or Color3.new(1, 1, 1)
	lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
	lbl.TextStrokeTransparency = 0
end

local function pad(frame: Instance, top: number, left: number, right: number, bottom: number)
	local p = Instance.new("UIPadding", frame)
	p.PaddingTop = UDim.new(0, top)
	p.PaddingLeft = UDim.new(0, left)
	p.PaddingRight = UDim.new(0, right)
	p.PaddingBottom = UDim.new(0, bottom)
end

-- Loadout makeDropdown: a 62 px bar button with a 14 px icon and a left-aligned label.
function InventoryControls.MakeFilterButton(row: Instance, text: string, order: number, isActive: boolean, iconAsset: string?): TextButton
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, InventoryControls.ButtonWidth, 1, 0)
	-- Active = gold-tint selected background (same colour as a selected item tile), not gold text.
	btn.BackgroundColor3 = if isActive then Theme.Colors.SelectedItem else Theme.Colors.Surface
	btn.BackgroundTransparency = if isActive then Theme.ItemTile.SelectedBgTransparency else 0.2
	btn.BorderSizePixel = 0
	btn.LayoutOrder = order
	btn.Parent = row
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 3)
	if iconAsset then
		btn.Text = ""
		local ico = Instance.new("ImageLabel")
		ico.Size = UDim2.new(0, 14, 0, 14)
		ico.Position = UDim2.new(0, 3, 0.5, -7)
		ico.BackgroundTransparency = 1
		ico.Image = iconAsset
		ico.ScaleType = Enum.ScaleType.Fit
		ico.ImageColor3 = isActive and Theme.Colors.TextGold or Theme.Colors.TextSecondary
		ico.Parent = btn
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -19, 1, 0)
		lbl.Position = UDim2.new(0, 19, 0, 0)
		lbl.BackgroundTransparency = 1
		lbl.Font = Theme.Font.Primary
		lbl.TextSize = Theme.Text.Small()
		outlineText(lbl)
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextTruncate = Enum.TextTruncate.AtEnd
		lbl.Text = text
		lbl.Parent = btn
	else
		btn.Font = Theme.Font.Primary
		btn.TextSize = Theme.Text.Small()
		outlineText(btn)
		btn.Text = text
	end
	return btn
end

-- Loadout showDropdown: opens a menu below the anchor button; an invisible full-screen
-- backdrop closes it on an outside tap. Returns the overlay ScreenGui (the caller keeps it and
-- destroys it in close()).
function InventoryControls.ShowMenu(playerGui: Instance, anchorBtn: GuiObject, options: { any },
	onSelect: (any, number) -> (), close: () -> (), displayOrder: number?): ScreenGui
	local rowH = InventoryControls.MenuRowHeight
	local menuH = #options * rowH + 4
	local menuW = math.max(anchorBtn.AbsoluteSize.X, InventoryControls.MenuMinWidth)

	-- ScreenGui overlay to capture outside clicks
	local overlay = Instance.new("ScreenGui")
	overlay.Name = "DropdownOverlay"
	overlay.DisplayOrder = displayOrder or InventoryControls.MenuDisplayOrder
	overlay.ResetOnSpawn = false
	overlay.Parent = playerGui

	-- Invisible full-screen backdrop to close on outside click
	local ddBackdrop = Instance.new("TextButton")
	ddBackdrop.Size = UDim2.fromScale(1, 1)
	ddBackdrop.BackgroundTransparency = 1
	ddBackdrop.Text = ""
	ddBackdrop.Parent = overlay
	ddBackdrop.Activated:Connect(close)

	-- Menu panel, positioned below the anchor button
	local menuPanel = Instance.new("Frame")
	menuPanel.Size = UDim2.new(0, menuW, 0, menuH)
	menuPanel.Position = UDim2.new(0, anchorBtn.AbsolutePosition.X, 0, anchorBtn.AbsolutePosition.Y + anchorBtn.AbsoluteSize.Y + 2)
	menuPanel.BackgroundColor3 = Theme.Colors.Panel
	menuPanel.BorderSizePixel = 0
	menuPanel.ZIndex = 50
	menuPanel.Parent = overlay
	Instance.new("UICorner", menuPanel).CornerRadius = UDim.new(0, 4)
	local menuStroke = Instance.new("UIStroke", menuPanel)
	menuStroke.Color = Theme.Colors.Border
	menuStroke.Thickness = 1

	local menuLayout = Instance.new("UIListLayout", menuPanel)
	menuLayout.Padding = UDim.new(0, 0)
	menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pad(menuPanel, 2, 2, 2, 2)

	for idx, opt in ipairs(options) do
		local row = Instance.new("TextButton")
		row.Size = UDim2.new(1, 0, 0, rowH)
		row.BackgroundColor3 = Theme.Colors.PanelRaised
		row.BackgroundTransparency = opt.active and 0.2 or 0.6
		row.Font = Theme.Font.Primary
		row.TextSize = Theme.Text.Small()
		outlineText(row) -- the active row is shown by its brighter background
		row.BorderSizePixel = 0
		row.LayoutOrder = idx
		row.ZIndex = 51
		row.Parent = menuPanel
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 3)
		-- Icon + text layout
		local hasImage = opt.icon and string.find(opt.icon, "rbxassetid://")
		if hasImage then
			row.Text = ""
			local ico = Instance.new("ImageLabel")
			ico.Size = UDim2.new(0, 16, 0, 16)
			ico.Position = UDim2.new(0, 4, 0.5, -8)
			ico.BackgroundTransparency = 1
			ico.Image = opt.icon
			ico.ScaleType = Enum.ScaleType.Fit
			ico.ZIndex = 52
			ico.Parent = row
			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.new(1, -24, 1, 0)
			lbl.Position = UDim2.new(0, 22, 0, 0)
			lbl.BackgroundTransparency = 1
			lbl.Font = Theme.Font.Primary
			lbl.TextSize = Theme.Text.Small()
			outlineText(lbl)
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.Text = opt.label
			lbl.ZIndex = 52
			lbl.Parent = row
		else
			row.Text = opt.label
		end
		row.Activated:Connect(function()
			close()
			onSelect(opt.value, idx)
		end)
	end
	return overlay
end

-- Loadout gear tile level label (top-left, grey mono text, no box). 2026-11-07: never below the
-- phone badge floor (was a fixed 9 px); width from the text. Returns the label and its width
-- (the Loadout uses the width to keep its NEW / E markers clear of it).
function InventoryControls.MakeLevelLabel(tile: Instance, text: string): (TextLabel, number)
	local lvSize = math.max(9, Theme.Text.Badge())
	local w = Theme.MeasureText(text, lvSize, Theme.Font.Mono).X + 2
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0, math.max(w, 20), 0, math.max(12, lvSize + 2))
	lbl.Position = UDim2.new(0, 3, 0, 2)
	lbl.BackgroundTransparency = 1
	lbl.BorderSizePixel = 0
	lbl.Font = Theme.Font.Mono
	lbl.TextSize = lvSize
	lbl.TextColor3 = Theme.Colors.TextSecondary
	lbl.Text = text
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextTruncate = Enum.TextTruncate.AtEnd
	lbl.LayoutOrder = 0
	lbl.RichText = false
	lbl.Parent = tile
	lbl.ZIndex = 3
	return lbl, w
end

-- Loadout GEAR | CONSUMABLES switch: a 24 px row of Theme.MakeTabButton halves.
-- defs = {{ id, label }}; onPick(id) runs when a tab is tapped.
function InventoryControls.MakeSubTabs(parent: Instance, defs: { any }, activeId: any, onPick: (any) -> (), layoutOrder: number?): Frame
	local tabRow = Instance.new("Frame")
	tabRow.Size = UDim2.new(1, 0, 0, InventoryControls.SubTabHeight)
	tabRow.BackgroundTransparency = 1
	tabRow.LayoutOrder = layoutOrder or 0
	tabRow.Parent = parent

	local tabLayout = Instance.new("UIListLayout", tabRow)
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, InventoryControls.SubTabGap)

	local n = #defs
	for i, tabDef in ipairs(defs) do
		-- Old 9-slice text bars (2026-10-08); Scale width: equal shares of the row.
		Theme.MakeTabButton(tabRow, tabDef.label, if tabDef.id == activeId then "Active" else "Inactive", function()
			onPick(tabDef.id)
		end, {
			name = "SubTab_" .. tabDef.label,
			size = UDim2.new(1 / n, -(InventoryControls.SubTabGap * (n - 1)) / n, 1, 0),
			layoutOrder = i,
		})
	end
	return tabRow
end

-- Loadout tile markers (moved unchanged from LoadoutScreen buildItemGrid, 2026-11-08, so the
-- Runeforge gear tiles show the same badges). Equipped "E" (top-right): gold = this unit, grey =
-- another unit; shared badge size with a box that fits it, dropping to the second row on a narrow
-- tile where the Lv label would reach it. NEW (top-right, below E / count if both; beside a dropped
-- E). gearLvW = width of the tile's Lv label (0 if none); hasCountBadge = a top-right xN badge.
local function markerLabel(parent: Instance, text: string)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Position = UDim2.new(0, 0, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.BorderSizePixel = 0
	lbl.Font = Theme.Font.PrimaryBold
	lbl.TextSize = Theme.Text.Badge()
	lbl.TextColor3 = Color3.fromRGB(0, 0, 0)
	lbl.Text = text
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.TextTruncate = Enum.TextTruncate.AtEnd
	lbl.LayoutOrder = 0
	lbl.RichText = false
	lbl.Parent = parent
	lbl.ZIndex = 3
end

function InventoryControls.AddTileMarkers(card: Instance, cellW: number, gearLvW: number, isEquipped: boolean,
	isEquippedByOther: boolean, isNew: boolean, hasCountBadge: boolean)
	local eW = math.max(14, Theme.BadgeFitW("E", Theme.Font.PrimaryBold, 14))
	local eH = math.max(12, Theme.Text.BadgeLineH())
	local eDrops = gearLvW > 0 and (3 + gearLvW + 2) > (cellW - (eW + 2))
	if isEquipped or isEquippedByOther then
		local marker = Instance.new("Frame")
		marker.Size = UDim2.new(0, eW, 0, eH)
		marker.Position = UDim2.new(1, -(eW + 2), 0, if eDrops then 16 else 2)
		marker.BackgroundColor3 = isEquipped and Theme.Colors.TextGold or Theme.Colors.TextDisabled
		marker.BorderSizePixel = 0
		marker.ZIndex = 3
		marker.Parent = card
		Instance.new("UICorner", marker).CornerRadius = UDim.new(0, 2)
		markerLabel(marker, "E")
	end
	if isNew then
		local newBadge = Instance.new("Frame")
		newBadge.Name = "NewBadge" -- found and removed when the item is opened (2026-11-08)
		newBadge.Size = UDim2.new(0, 26, 0, 12)  -- 26: fits "NEW" at the 10px phone badge size (2026-11-07)
		-- Drop below the top row when E/count is there, or when the Lv label would touch it on a
		-- narrow tile (48px phone cells, 2026-11-07).
		local lvTouches = gearLvW > 0 and (3 + gearLvW + 2) > (cellW - 28)
		local hasE = isEquipped or isEquippedByOther
		-- E dropped to row 2 on a narrow tile: NEW sits beside it (left) in that row.
		local newX = if hasE and eDrops then -(eW + 2 + 28) else -28
		newBadge.Position = UDim2.new(1, newX, 0, (hasE or hasCountBadge or lvTouches) and 16 or 2)  -- grey E (other unit) too (2026-11-07)
		newBadge.BackgroundColor3 = Theme.Colors.Success
		newBadge.BorderSizePixel = 0
		newBadge.ZIndex = 3
		newBadge.Parent = card
		Instance.new("UICorner", newBadge).CornerRadius = UDim.new(0, 2)
		markerLabel(newBadge, "NEW")
	end
end

return table.freeze(InventoryControls)
