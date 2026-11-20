--!strict
-- LoadoutUnitHeader.lua
-- CTRBLXAI | Loadout screen: compact unit header (upper-right: portrait, name, race / doctrine,
-- level) and the unit picker popup (swap unit).
-- Split out of LoadoutScreen.lua (2026-11-10, ARC-005 file-size split, step 9). Behaviour unchanged.
-- Host state (unit header panel, the one open dropdown, Refresh, the _OpenUnitPicker test hook) is
-- reached through `ctx` -- no require of LoadoutScreen, so no circular dependency.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CTRBLXAI_UI = ReplicatedStorage:WaitForChild("CTRBLXAI", 10):WaitForChild("UI", 10)
local BattleEvents = require(ReplicatedStorage:WaitForChild("CTRBLXAI", 10)
	:WaitForChild("Remotes", 10):WaitForChild("BattleEvents", 10))
local MockData    = require(CTRBLXAI_UI:WaitForChild("MockLoadoutData", 10))
local Theme       = require(CTRBLXAI_UI:WaitForChild("Theme", 10))
local UIComponents = require(CTRBLXAI_UI:WaitForChild("UIComponents", 10))

local LoadoutUnitHeader: any = {}

local ctx: any = nil
-- Host helpers, bound in Init (thin wrappers so a later reassignment in the host is seen).
local function clearChildren(...) return ctx.clearChildren(...) end
local function getPlayerGui(...) return ctx.getPlayerGui(...) end
local function makeLabel(...) return ctx.makeLabel(...) end
local function pad(...) return ctx.pad(...) end



-- UNIT HEADER (upper-right, compact)
--------------------------------------------------

local function buildUnitHeader()
	if not ctx.getUnitHeaderPanel() then return end
	clearChildren(ctx.getUnitHeaderPanel())
	pad(ctx.getUnitHeaderPanel(), 8, 10, 10, 8)

	local unit = MockData.GetSelectedUnit()
	if not unit then return end

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 44)
	row.BackgroundTransparency = 1
	row.Parent = ctx.getUnitHeaderPanel()

	-- Swap button at the RIGHT end of the header; opens the unit dropdown
	-- (replaces the old left/right cycle arrows, user ruling 2026-10-18).
	local SWAP_W = 28
	local swapBtn = Instance.new("ImageButton")
	swapBtn.Name = "SwapUnit"
	swapBtn.Size = UDim2.new(0, SWAP_W, 0, 28)
	swapBtn.Position = UDim2.new(1, -SWAP_W, 0, 8)
	swapBtn.BackgroundColor3 = Theme.Colors.Surface
	swapBtn.BackgroundTransparency = 0.4
	-- Use the semantic compare/swap/details icon (IconButtonAssets.Options). The
	-- earlier `Theme.Icons.Options` is nil (no such key in Theme.Icons), so it fell
	-- through to the Sort glyph — wrong icon. (2026-10-18)
	swapBtn.Image = (Theme.IconButtonAssets and Theme.IconButtonAssets.Options)
		or Theme.Icons.Options or ""
	swapBtn.ScaleType = Enum.ScaleType.Fit
	swapBtn.BorderSizePixel = 0
	swapBtn.Parent = row
	Instance.new("UICorner", swapBtn).CornerRadius = UDim.new(0, 3)

	-- Portrait at the LEFT edge (no more left arrow inset).
	local portraitX = 0
	local portrait = Instance.new("Frame")
	portrait.Size = UDim2.new(0, 44, 0, 44)
	portrait.Position = UDim2.new(0, portraitX, 0, 0)
	portrait.BackgroundColor3 = Theme.Colors.Player
	portrait.BackgroundTransparency = 0.2
	portrait.BorderSizePixel = 0
	portrait.Parent = row
	Instance.new("UICorner", portrait).CornerRadius = UDim.new(0, 5)

	local pText = Instance.new("TextLabel")
	pText.Size = UDim2.new(1, 0, 0, 32)
	pText.BackgroundTransparency = 1
	pText.Font = Theme.Font.PrimaryBold
	pText.TextSize = Theme.Text.Title()
	pText.TextColor3 = Theme.Colors.TextPrimary
	pText.Text = string.sub(unit.name, 1, 2)
	pText.Parent = portrait
	-- Portrait face overlay when the unit has one (nil -> initials box).
	if UIComponents and UIComponents.ApplyPortrait and unit.portraitAssetId then
		if UIComponents.ApplyPortrait(portrait, unit.portraitAssetId) then pText.Text = "" end
	end
	if UIComponents and UIComponents.ApplyUnitFrame then UIComponents.ApplyUnitFrame(portrait, { darkBg = true }) end -- 2026-11-20 unit frame

	local lvlBadge = Instance.new("TextLabel")
	lvlBadge.Size = UDim2.new(0, 28, 0, 12)
	lvlBadge.Position = UDim2.new(0, 0, 0, 0)
	lvlBadge.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	lvlBadge.BackgroundTransparency = 0.3
	lvlBadge.Font = Theme.Font.Mono
	lvlBadge.TextSize = Theme.Text.Tiny()
	lvlBadge.TextColor3 = Theme.Colors.TextPrimary
	lvlBadge.Text = "Lv." .. unit.level
	lvlBadge.BorderSizePixel = 0
	lvlBadge.TextXAlignment = Enum.TextXAlignment.Left
	-- ApplyPortrait adds the face image at (frame.ZIndex + 1); the badge must sit
	-- ABOVE that or it hides behind the portrait. Frame is ZIndex 1 -> image 2 ->
	-- badge 3. (2026-10-18, same fix pattern as the turn-order bar.)
	lvlBadge.ZIndex = 3
	lvlBadge.Parent = portrait

	-- Unallocated stat points indicator (red dot, top-right of portrait)
	if unit.unallocatedPoints and unit.unallocatedPoints > 0 then
		local alertDot = Instance.new("Frame")
		alertDot.Size = UDim2.new(0, 10, 0, 10)
		alertDot.Position = UDim2.new(1, -12, 0, 2)
		alertDot.BackgroundColor3 = Theme.Colors.Danger
		alertDot.BorderSizePixel = 0
		alertDot.Parent = portrait
		Instance.new("UICorner", alertDot).CornerRadius = UDim.new(0.5, 0)
	end

	-- Name + "Race - Doctrine" (user ruling 2026-10-18: doctrine right after race).
	local textX = portraitX + 52
	local rightInset = SWAP_W + 8
	-- Name always gets TWO rows (user 2026-10-29) so long names wrap instead of clipping.
	local HDR_NAME_H = 2 * (Theme.Text.Heading() + 2)
	local hdrName = Instance.new("TextLabel")
	hdrName.Size = UDim2.new(1, -(textX + rightInset), 0, HDR_NAME_H)
	hdrName.Position = UDim2.new(0, textX, 0, 0)
	hdrName.BackgroundTransparency = 1; hdrName.BorderSizePixel = 0
	hdrName.Font = Theme.Font.PrimaryBold; hdrName.TextSize = Theme.Text.Heading()
	hdrName.TextColor3 = Theme.Colors.Player
	hdrName.TextXAlignment = Enum.TextXAlignment.Left
	hdrName.TextYAlignment = Enum.TextYAlignment.Top
	hdrName.TextWrapped = true; hdrName.TextTruncate = Enum.TextTruncate.AtEnd
	hdrName.Text = unit.name
	hdrName.Parent = row -- parent last (NET-004)
	local raceDoc = unit.raceName or "—"
	if unit.doctrineName and unit.doctrineName ~= "" then
		raceDoc = raceDoc .. " - " .. unit.doctrineName
	end
	makeLabel(row, { Text = raceDoc,
		Position = UDim2.new(0, textX, 0, HDR_NAME_H),
		Size = UDim2.new(1, -(textX + rightInset), 0, 12), TextSize = Theme.Text.Small(),
		TextColor3 = Theme.Colors.TextSecondary })

	-- Dropdown: full roster, each row = portrait + Lv badge, name, Race - Doctrine.
	-- Mirrors the existing DropdownOverlay pattern (ScreenGui backdrop + menu panel)
	-- and reuses `activeDropdown` so Hide()/outside-click tear it down. (2026-10-18)
	local function closeUnitDropdown()
		if ctx.getActiveDropdown() then ctx.getActiveDropdown():Destroy(); ctx.setActiveDropdown(nil) end
	end
	-- UNIT PICKER POPUP (user request 2026-11-10): replaces the row dropdown. Centred modal with
	-- the roster as tiles (portrait, Lv, name, doctrine badge) and a unit-count header. Reuses
	-- `activeDropdown` so Hide()/backdrop tap tear it down like before.
	local function openUnitPicker()
		if ctx.getActiveDropdown() then closeUnitDropdown(); return end
		local units = MockData.GetAllUnits and MockData.GetAllUnits() or {}
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		-- Same footprint as the portrait picker (user 2026-11-10): 280x300 panel, 56 px cells
		-- + a short name row, 6 px gaps (4 per row).
		local TILE_W, TILE_H = 56, 72
		local GAP = 6
		local popW = 280
		local popH = math.min(vp.Y - 24, 300)

		ctx.setActiveDropdown(Instance.new("ScreenGui"))
		ctx.getActiveDropdown().Name = "UnitPickerPopup"
		-- Above LoadoutTabBar (150) so the tab bar cannot cover the popup header (2026-11-10).
		ctx.getActiveDropdown().DisplayOrder = 160
		ctx.getActiveDropdown().ResetOnSpawn = false
		ctx.getActiveDropdown().IgnoreGuiInset = true

		local backdrop = Instance.new("TextButton")
		backdrop.Size = UDim2.fromScale(1, 1)
		backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
		backdrop.BackgroundTransparency = 0.45
		backdrop.AutoButtonColor = false
		backdrop.Text = ""
		backdrop.Parent = ctx.getActiveDropdown()
		backdrop.Activated:Connect(closeUnitDropdown)

		local pop = Theme.MakePanel("UnitPickerPanel", UDim2.fromOffset(popW, popH),
			UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), ctx.getActiveDropdown())
		pop.ZIndex = 50
		pad(pop, 10, 12, 12, 10)

		-- Header: title + unit count (capacity indicator).
		makeLabel(pop, { Text = "Choose Unit",
			Size = UDim2.new(1, -40, 0, 20), Position = UDim2.new(0, 0, 0, 0),
			Font = Theme.Font.PrimaryBold, TextSize = Theme.Text.Body(), TextColor3 = Theme.Colors.TextGold })
		local cap = MockData.GetRosterCapacity and MockData.GetRosterCapacity() or nil
		local countText = if cap then `Units {#units} / {cap}` else `Units {#units}`
		makeLabel(pop, { Text = countText,
			Size = UDim2.new(0, 90, 0, 20), Position = UDim2.new(1, -118, 0, 0),
			TextSize = Theme.Text.Small(), TextColor3 = Theme.Colors.TextSecondary,
			TextXAlignment = Enum.TextXAlignment.Right })
		local closeBtn = Instance.new("TextButton")
		closeBtn.Size = UDim2.fromOffset(32, 24)
		closeBtn.Position = UDim2.new(1, -32, 0, -2)
		closeBtn.BackgroundTransparency = 1
		closeBtn.Font = Theme.Font.PrimaryBold
		closeBtn.TextSize = Theme.Text.Heading()
		closeBtn.TextColor3 = Theme.Colors.TextSecondary
		closeBtn.Text = "X"
		closeBtn.ZIndex = 52
		closeBtn.Parent = pop
		closeBtn.Activated:Connect(closeUnitDropdown)

		local grid = Instance.new("ScrollingFrame")
		grid.Size = UDim2.new(1, 0, 1, -28)
		grid.Position = UDim2.new(0, 0, 0, 28)
		grid.BackgroundTransparency = 1
		grid.BorderSizePixel = 0
		grid.ScrollBarThickness = 4
		grid.ScrollingDirection = Enum.ScrollingDirection.Y
		grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
		grid.CanvasSize = UDim2.new()
		grid.ZIndex = 51
		grid.Parent = pop
		local gl = Instance.new("UIGridLayout")
		gl.CellSize = UDim2.fromOffset(TILE_W, TILE_H)
		gl.CellPadding = UDim2.fromOffset(GAP, GAP)
		gl.SortOrder = Enum.SortOrder.LayoutOrder
		gl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		gl.Parent = grid

		for idx, u in ipairs(units) do
			local isSel = (u.id == unit.id)
			local tile = Instance.new("TextButton")
			tile.BackgroundColor3 = Theme.Colors.PanelRaised
			tile.BackgroundTransparency = isSel and 0.1 or 0.45
			tile.AutoButtonColor = false -- no hover colour (project_rules 243)
			tile.Text = ""
			tile.BorderSizePixel = 0
			tile.LayoutOrder = idx
			tile.ZIndex = 52
			Instance.new("UICorner", tile).CornerRadius = UDim.new(0, 4)
			local st = Instance.new("UIStroke")
			st.Color = if isSel then Theme.Colors.TextGold else Theme.Colors.Border
			st.Thickness = if isSel then 2 else 1
			st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			st.Parent = tile

			local pSize = TILE_W - 4
			local pFrame = Instance.new("Frame")
			pFrame.Size = UDim2.fromOffset(pSize, pSize)
			pFrame.Position = UDim2.new(0.5, -pSize / 2, 0, 2)
			pFrame.BackgroundColor3 = Theme.Colors.Player
			pFrame.BackgroundTransparency = 0.2
			pFrame.BorderSizePixel = 0
			pFrame.ZIndex = 53
			Instance.new("UICorner", pFrame).CornerRadius = UDim.new(0, 4)
			local pInit = Instance.new("TextLabel")
			pInit.Size = UDim2.fromScale(1, 1)
			pInit.BackgroundTransparency = 1
			pInit.Font = Theme.Font.PrimaryBold
			pInit.TextSize = Theme.Text.Body()
			pInit.TextColor3 = Theme.Colors.TextPrimary
			pInit.Text = string.sub(u.name, 1, 2)
			pInit.ZIndex = 54
			pInit.Parent = pFrame
			pFrame.Parent = tile
			if UIComponents and UIComponents.ApplyPortrait and u.portraitAssetId then
				if UIComponents.ApplyPortrait(pFrame, u.portraitAssetId) then pInit.Text = "" end
			end
			if UIComponents and UIComponents.ApplyUnitFrame then UIComponents.ApplyUnitFrame(pFrame, { darkBg = true }) end -- 2026-11-20 unit frame
			-- Level badge (top-left of portrait); ZIndex above the portrait image (53+1).
			local badge = Instance.new("TextLabel")
			badge.Size = UDim2.fromOffset(Theme.BadgeFitW and Theme.BadgeFitW("Lv." .. u.level, Theme.Font.Mono, 28) or 30, 13)
			badge.BackgroundColor3 = Color3.new(0, 0, 0)
			badge.BackgroundTransparency = 0.3
			badge.Font = Theme.Font.Mono
			badge.TextSize = Theme.Text.Tiny()
			badge.TextColor3 = Theme.Colors.TextPrimary
			badge.Text = "Lv." .. u.level
			badge.BorderSizePixel = 0
			badge.ZIndex = 56
			badge.Parent = pFrame
			-- Doctrine badge (bottom-right of portrait): the doctrine's own icon.
			local docDef = ctx.getDoctrineData() and u.doctrineId and ctx.getDoctrineData()[u.doctrineId]
			local docIcon = docDef and docDef.icon
			if type(docIcon) == "string" and docIcon ~= "" then
				local db = Instance.new("ImageLabel")
				db.Name = "DoctrineBadge"
				db.Size = UDim2.fromOffset(16, 16)
				db.AnchorPoint = Vector2.new(1, 1)
				db.Position = UDim2.new(1, -2, 1, -2)
				db.BackgroundColor3 = Color3.new(0, 0, 0)
				db.BackgroundTransparency = 0.25
				db.Image = docIcon
				db.ScaleType = Enum.ScaleType.Fit
				db.ZIndex = 56
				Instance.new("UICorner", db).CornerRadius = UDim.new(0.5, 0)
				db.Parent = pFrame
			end
			-- Name (two rows) under the portrait.
			local nameLbl = Instance.new("TextLabel")
			nameLbl.Size = UDim2.new(1, -2, 0, TILE_H - pSize - 4)
			nameLbl.Position = UDim2.new(0, 1, 0, pSize + 3)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Font = Theme.Font.PrimaryBold
			nameLbl.TextSize = Theme.Text.Tiny()
			nameLbl.TextColor3 = isSel and Theme.Colors.TextGold or Theme.Colors.Player
			nameLbl.TextWrapped = false  -- one row at this size; long names end in "..."
			nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
			nameLbl.TextYAlignment = Enum.TextYAlignment.Top
			nameLbl.Text = u.name
			nameLbl.ZIndex = 53
			nameLbl.Parent = tile
			tile.Parent = grid -- parent last (NET-004)

			tile.Activated:Connect(function()
				closeUnitDropdown()
				if isSel then return end
				BattleEvents.RequestSaveLoadout:FireServer() -- save the unit we're leaving (2026-10-19)
				if MockData.SetSelectedUnitById then MockData.SetSelectedUnitById(u.id) end
				ctx.refresh()
			end)
		end
		ctx.getActiveDropdown().Parent = getPlayerGui()
	end
	swapBtn.Activated:Connect(openUnitPicker)
	-- Studio test hook (2026-11-10): lets tooling open the picker without simulated clicks.
	ctx.setOpenUnitPicker(openUnitPicker)
end


function LoadoutUnitHeader.Init(c: any)
	ctx = c
end
LoadoutUnitHeader.BuildUnitHeader = function(...) return buildUnitHeader(...) end

return LoadoutUnitHeader
