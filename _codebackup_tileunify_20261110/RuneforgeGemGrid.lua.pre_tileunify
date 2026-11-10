--!strict
-- RuneforgeGemGrid.lua
-- CTRBLXAI | Runeforge "Gems" tab on the LEFT inventory panel (2026-11-07, user request: one
-- inventory panel with a Gears | Gems swap; the right panel only shows the forge details).
-- Split out of RuneforgeScreen (ARC-005, file size). Display + input only (ARC-001): the
-- screen decides which gems fit (its shared checkPick + the server's CheckForgeGems answer)
-- and passes ready-made cells; this module only draws them and reports taps.
--
-- Tiles: Loadout size (Theme.ItemTileCell, same as the Gears grid) built with the shared
-- Theme.MakeItemTile look. Each gem tile (user request 2026-11-07): the stat's icon as the
-- portrait (Theme.GetBonusIcon; passives have none -> plain tile), tier label top left ("T3",
-- the Loadout "Lv.N" label look),
-- count badge top right (xN), name strip WITHOUT the tier. No point-cost badge (the bonus
-- inspector, opened by holding a tile, shows the points). Search / filter / sort use the shared
-- ItemListToolbar (built by the screen), same bar as the Gears tab. A gem that can't be added
-- is dimmed, takes no taps and shows a short reason. Tap-only (.Activated, project_rules 243);
-- phone sizes (project_rules 244): text >= 10 px.

local WAIT = 10

local themeModule = script.Parent:WaitForChild("Theme", WAIT)
if not themeModule then
	error("[RuneforgeGemGrid] Theme module not found")
end
-- Found at runtime via WaitForChild; the editor cannot follow that path (editor-only cast).
local Theme: any = (require :: any)(themeModule)
-- The Loadout's own grid spacing and level label (user 2026-11-08: the Loadout is the model).
local controlsModule = script.Parent:WaitForChild("InventoryControls", WAIT)
if not controlsModule then
	error("[RuneforgeGemGrid] InventoryControls module not found")
end
local InventoryControls: any = (require :: any)(controlsModule)

local RuneforgeGemGrid = {}

export type Cell = {
	key: string,          -- gem id
	name: string,         -- shown name, WITHOUT the tier ("Fortune")
	rarity: string?,      -- the gem's minimum rarity (tile colour)
	countText: string?,   -- "x3"
	tierText: string?,    -- "T3" (top-left badge); nil for bonus passives
	icon: string?,        -- portrait image (rbxassetid); nil = plain tile
	reason: string?,      -- why it can't be added (dimmed tile)
	enabled: boolean,
	onTap: (() -> ())?,
	onHold: (() -> ())?,  -- press and hold (HOLD_TIME): inspect the gem without adding it
}

local DIM = 0.5
-- Press-and-hold on a gem tile opens the bonus inspector (2026-11-07). Tap-only devices have
-- no hover, so hold is the touch-native "tell me more"; a plain tap still adds the gem.
local HOLD_TIME = 0.4
local HOLD_SLOP = 10 -- px of finger / cursor movement (or any grid scroll) that cancels a hold

-- White text with a black outline (readable over any tile colour).
local function outlinedLabel(parent: Instance, text: string, size: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Font = Theme.Font.PrimaryBold
	l.TextSize = size
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeColor3 = Color3.new(0, 0, 0)
	l.TextStrokeTransparency = 0
	l.Text = text
	l.Parent = parent
	return l
end

-- Tier label, top left: the Loadout gear tile's own "Lv.N" label (InventoryControls.
-- MakeLevelLabel: grey mono text, no box, 2026-11-08), reading "T3" (passives: UNC / RARE / EPIC).
-- Drawn above the dim layer so a greyed gem still shows its tier.
local SHORT_TAG = table.freeze({ UNC = "U", RARE = "R", EPIC = "E" })

local function addTierBadge(tile: Instance, text: string, cellW: number?, hasCount: boolean?)
	local t = Theme.ItemTile
	local lbl, w = InventoryControls.MakeLevelLabel(tile, text)
	-- 2026-11-07: on narrow tiles a wide passive tag (UNC/RARE/EPIC) would run into the
	-- top-right count badge, so it shortens to one letter there (text size unchanged).
	if hasCount and cellW and SHORT_TAG[text] and 3 + w + 2 > cellW - t.CountBadgeFromRight then
		lbl:Destroy()
		lbl = InventoryControls.MakeLevelLabel(tile, SHORT_TAG[text])
	end
	lbl.Name = "Tier"
	lbl.ZIndex = 7
end

-- Black portrait square behind the stat icon (user request 2026-11-08): the stat icons have a
-- transparent background, the gear art has its own black square, so gem tiles get the same
-- black square for a uniform look. Same box as Theme.MakeItemTile's icon (inset from the top
-- and sides, down to just above the name strip), as a centred square, under the icon (ZIndex
-- 1 < icon 2). Passive gems (no icon) get the square too.
local PORTRAIT_BG = Color3.new(0, 0, 0)
local function addPortraitBg(tile: Instance, cellW: number)
	local t = Theme.ItemTile
	local inset = math.max(t.IconInsetMin, math.round(cellW * t.IconInsetFactor))
	local box = Instance.new("Frame")
	box.Name = "PortraitBox"
	box.Size = UDim2.new(1, -inset * 2, 1, -(inset + t.NameBarHeight + 2))
	box.Position = UDim2.fromOffset(inset, inset)
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.Active = false
	box.ZIndex = 1
	local sq = Instance.new("Frame")
	sq.Name = "PortraitBg"
	sq.AnchorPoint = Vector2.new(0.5, 0.5)
	sq.Position = UDim2.fromScale(0.5, 0.5)
	sq.Size = UDim2.fromScale(1, 1)
	sq.BackgroundColor3 = PORTRAIT_BG
	sq.BackgroundTransparency = 0
	sq.BorderSizePixel = 0
	sq.Active = false
	sq.ZIndex = 1
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.AspectType = Enum.AspectType.FitWithinMaxSize
	ar.Parent = sq
	sq.Parent = box
	box.Parent = tile
end

local function addReason(tile: Instance, text: string)
	local t = Theme.ItemTile
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = DIM
	dim.BorderSizePixel = 0
	dim.Active = false
	dim.ZIndex = 5
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, t.CornerRadius)
	corner.Parent = dim
	dim.Parent = tile
	local l = outlinedLabel(tile, text, Theme.Text.Small())
	l.Name = "Reason"
	local top = Theme.Text.BadgeLineH() + 3 -- below the tier badge row
	l.Size = UDim2.new(1, -4, 1, -(t.NameBarHeight + top + 1))
	l.Position = UDim2.fromOffset(2, top)
	l.TextWrapped = true
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.ZIndex = 6
end

-- Fills `grid` (a ScrollingFrame named "Grid" made by the caller) with gem tiles.
-- heightHint: px grid height to use until the real height is known (UI-001).
function RuneforgeGemGrid.BuildGrid(grid: ScrollingFrame, cells: { Cell }, heightHint: number?)
	local h = grid.AbsoluteSize.Y
	if h < 100 then h = heightHint or 0 end
	local cellW, cellH = Theme.ItemTileCell(h)

	-- The Loadout item grid: no inner padding, its cell spacing (InventoryControls).
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.fromOffset(cellW, cellH)
	gl.CellPadding = InventoryControls.GridCellPadding
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = grid
	-- Same re-fit as the Gears grid (MerchantInspector loadoutTiles); owned by the grid.
	grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local gh = grid.AbsoluteSize.Y
		if gh < 100 then return end
		local w2, h2 = Theme.ItemTileCell(gh)
		if gl.CellSize.X.Offset ~= w2 or gl.CellSize.Y.Offset ~= h2 then
			gl.CellSize = UDim2.fromOffset(w2, h2)
		end
	end)

	for i, c in cells do
		-- Set when a hold opened the inspector, so the release that follows isn't also a tap.
		local held = false
		local onTap = c.onTap
		local tile = Theme.MakeItemTile({
			parent = grid,
			accentColor = Theme.GetRarityColor(c.rarity or "Common"),
			cellW = cellW,
			name = c.name,
			icon = c.icon,
			-- A greyed tile drops its count badge so the reason has the whole upper area.
			countText = if c.reason and not c.enabled then nil else c.countText,
			layoutOrder = i,
			onClick = if c.enabled and onTap then function()
				if held then
					held = false
					return
				end
				onTap()
			end else nil,
		})
		tile.Name = `Gem_{c.key}`
		addPortraitBg(tile, cellW)
		if not c.enabled then
			tile.Active = false        -- greyed gems take no taps
			tile.AutoButtonColor = false
		end
		-- A greyed tile shows its reason below the badge row ("over by N" carries the cost).
		if c.reason and not c.enabled then
			addReason(tile, c.reason)
		end
		if c.tierText then
			local hasCount = (c.countText ~= nil) and not (c.reason and not c.enabled)
			addTierBadge(tile, c.tierText, cellW, hasCount)
		end
		-- Hold to inspect: works on greyed tiles too (they still get input events, they just
		-- don't fire Activated). The connections live on the tile (destroyed with it, PRF-004).
		local onHold = c.onHold
		if onHold then
			local token = 0
			local startPos: Vector3? = nil
			local startCanvas = Vector2.zero
			local function isPress(input: InputObject): boolean
				return input.UserInputType == Enum.UserInputType.Touch
					or input.UserInputType == Enum.UserInputType.MouseButton1
			end
			tile.InputBegan:Connect(function(input: InputObject)
				if not isPress(input) then return end
				token += 1
				local my = token
				held = false
				startPos = input.Position
				startCanvas = grid.CanvasPosition
				task.delay(HOLD_TIME, function()
					if my ~= token or not startPos or not tile.Parent then return end
					if (grid.CanvasPosition - startCanvas).Magnitude > HOLD_SLOP then return end -- scrolled
					startPos = nil
					held = true
					onHold()
				end)
			end)
			tile.InputChanged:Connect(function(input: InputObject)
				local sp = startPos
				if sp and (input.UserInputType == Enum.UserInputType.Touch
					or input.UserInputType == Enum.UserInputType.MouseMovement)
					and (input.Position - sp).Magnitude > HOLD_SLOP then
					token += 1
					startPos = nil
				end
			end)
			tile.InputEnded:Connect(function(input: InputObject)
				if isPress(input) then
					token += 1
					startPos = nil
				end
			end)
		end
	end
end

return table.freeze(RuneforgeGemGrid)
