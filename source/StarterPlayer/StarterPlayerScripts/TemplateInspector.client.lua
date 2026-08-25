-- TemplateInspector.client.lua
-- CTRBLXAI | Map Viewer + Tile Inspector
--
-- Handles:
--   - Tile hover/selection (yellow outline)
--   - Adaptive grid scaling
--   - View mode toggle (TEMPLATE / REGION)
--   - Tile inspector panel (right side, restyled)
--   - Cross-selection: clicking a tile that has a unit on it
--     also selects that unit in the unit inspector panel.

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()

--------------------------------------------------
-- SETTINGS
--------------------------------------------------

local HOVER_COLOR    = Color3.fromRGB(255, 255, 255)
local SELECTED_COLOR = Color3.fromRGB(255, 230, 0)
local HOVER_OUTLINE_TRANSPARENCY    = 0.15
local SELECTED_OUTLINE_TRANSPARENCY = 0
local SELECTION_LINE_THICKNESS      = 0.16

local TILE_VISUAL_GUI_NAME   = "TileVisualGui"
local TILE_VISUAL_FRAME_NAME = "TileVisualFrame"

local GRID_VERTICAL_PREFIX   = "GridLine_V_"
local GRID_HORIZONTAL_PREFIX = "GridLine_H_"
local GRID_MINIMUM_THICKNESS = 0.08
local GRID_MAXIMUM_THICKNESS = 0.40
local GRID_DISTANCE_SCALE    = 0.0015
local GRID_MINIMUM_HEIGHT    = 0.04
local GRID_MAXIMUM_HEIGHT    = 0.16
local GRID_SURFACE_GAP       = 0.015

-- Marker colors used in the stripe
local MARKER_COLORS = {
	PD  = Color3.fromRGB(70,  140, 255),  -- player deploy (blue)
	ED  = Color3.fromRGB(220, 60,  60),   -- enemy deploy (red)
	LAN = Color3.fromRGB(166, 166, 166),  -- lane (grey)
	POI = Color3.fromRGB(91,  155, 213),  -- point of interest
	ADV = Color3.fromRGB(169, 209, 142),  -- advantage
	HZD = Color3.fromRGB(152, 72,  206),  -- hazard (purple)
	BLK = Color3.fromRGB(60,  60,  60),   -- blocker (dark)
	WAT = Color3.fromRGB(0,   112, 192),  -- water
	NEU = Color3.fromRGB(120, 120, 120),  -- neutral
}

--------------------------------------------------
-- STATE
--------------------------------------------------

local hoveredTile  = nil
local selectedTile = nil
local hoverBox     = nil
local selectedBox  = nil

local currentViewMode      = "REGION"
local currentMapFolder     = nil
local mapChildAddedConnection = nil

local gridLines        = {}
local gridOriginalSizes = {}
local mapCenter        = nil
local mapSurfaceY      = nil

--------------------------------------------------
-- PANEL CREATION  (matches unit inspector style)
--   Dark background, rounded corners, left stripe,
--   RichText monospaced content label.
--------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name         = "TileInspectorGui"
screenGui.ResetOnSpawn = false
screenGui.Parent       = player:WaitForChild("PlayerGui")

local function makePanel(name, yOffset, height)
	local frame = Instance.new("Frame")
	frame.Name                = name
	frame.Size                = UDim2.new(0, 220, 0, height)
	frame.AnchorPoint         = Vector2.new(1, 0)
	frame.Position            = UDim2.new(1, -12, 0, yOffset)
	frame.BackgroundColor3    = Color3.fromRGB(15, 15, 20)
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel     = 0
	frame.Parent              = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent       = frame

	-- Left stripe (color set when tile is selected)
	local stripe = Instance.new("Frame")
	stripe.Name             = "Stripe"
	stripe.Size             = UDim2.new(0, 4, 1, 0)
	stripe.Position         = UDim2.new(0, 0, 0, 0)
	stripe.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
	stripe.BorderSizePixel  = 0
	stripe.Parent           = frame

	local stripeCorner = Instance.new("UICorner")
	stripeCorner.CornerRadius = UDim.new(0, 8)
	stripeCorner.Parent       = stripe

	-- Content label
	local content = Instance.new("TextLabel")
	content.Name                 = "Content"
	content.Size                 = UDim2.new(1, -16, 1, -12)
	content.Position             = UDim2.new(0, 12, 0, 8)
	content.BackgroundTransparency = 1
	content.Font                 = Enum.Font.Code
	content.TextSize             = 13
	content.TextColor3           = Color3.fromRGB(220, 220, 220)
	content.TextXAlignment       = Enum.TextXAlignment.Left
	content.TextYAlignment       = Enum.TextYAlignment.Top
	content.TextWrapped          = true
	content.RichText             = true
	content.Text                 = ""
	content.Parent               = frame

	return frame, stripe, content
end

-- Tile panel — top right
local tilePanel,   tileStripe,   tileContent   = makePanel("TilePanel",   80,  230)
-- Object panel — below tile panel
local objectPanel, objectStripe, objectContent = makePanel("ObjectPanel", 322, 110)

-- Hide both until a tile is selected
tilePanel.Visible   = false
objectPanel.Visible = false

--------------------------------------------------
-- VIEW MODE BUTTON  (unchanged style)
--------------------------------------------------

local viewModeButton = Instance.new("TextButton")
viewModeButton.Name                 = "ViewModeButton"
viewModeButton.AnchorPoint          = Vector2.new(0.5, 0)
viewModeButton.Position             = UDim2.new(0.5, 0, 0, 70)
viewModeButton.Size                 = UDim2.new(0, 230, 0, 42)
viewModeButton.BackgroundColor3     = Color3.fromRGB(15, 15, 20)
viewModeButton.BackgroundTransparency = 0.08
viewModeButton.BorderSizePixel      = 0
viewModeButton.AutoButtonColor      = true
viewModeButton.Font                 = Enum.Font.SourceSansBold
viewModeButton.TextSize             = 18
viewModeButton.TextColor3           = Color3.fromRGB(220, 220, 220)
viewModeButton.Parent               = screenGui

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 6)
btnCorner.Parent       = viewModeButton

--------------------------------------------------
-- SELECTION BOXES
--------------------------------------------------

local function createSelectionBox(name, color, transparency)
	local box = Instance.new("SelectionBox")
	box.Name          = name
	box.Color3        = color
	box.LineThickness = SELECTION_LINE_THICKNESS
	box.Transparency  = transparency
	box.Visible       = false
	box.Parent        = workspace
	return box
end

hoverBox    = createSelectionBox("TileHoverBox",    HOVER_COLOR,    HOVER_OUTLINE_TRANSPARENCY)
selectedBox = createSelectionBox("TileSelectedBox", SELECTED_COLOR, SELECTED_OUTLINE_TRANSPARENCY)

--------------------------------------------------
-- INSTANCE HELPERS
--------------------------------------------------

local function isTemplateTile(instance)
	return instance
		and instance:IsA("BasePart")
		and instance:GetAttribute("IsTemplateTile") == true
end

local function isVerticalGridLine(instance)
	return instance
		and instance:IsA("BasePart")
		and string.sub(instance.Name, 1, #GRID_VERTICAL_PREFIX) == GRID_VERTICAL_PREFIX
end

local function isHorizontalGridLine(instance)
	return instance
		and instance:IsA("BasePart")
		and string.sub(instance.Name, 1, #GRID_HORIZONTAL_PREFIX) == GRID_HORIZONTAL_PREFIX
end

local function isGridLine(instance)
	return isVerticalGridLine(instance) or isHorizontalGridLine(instance)
end

local function getAttributeText(tile, attr, fallback)
	local v = tile:GetAttribute(attr)
	return v ~= nil and tostring(v) or fallback
end

local function getViewColor(tile, viewMode)
	local attr = viewMode == "TEMPLATE" and "TemplateColor" or "RegionDebugColor"
	local color = tile:GetAttribute(attr)
	return typeof(color) == "Color3" and color or tile.Color
end

--------------------------------------------------
-- TILE-TOP VISUAL
--------------------------------------------------

local function findTileVisualFrame(tile)
	local sg = tile:FindFirstChild(TILE_VISUAL_GUI_NAME)
	if not sg or not sg:IsA("SurfaceGui") then return nil end
	local f = sg:FindFirstChild(TILE_VISUAL_FRAME_NAME)
	return f and f:IsA("Frame") and f or nil
end

local function createTileVisual(tile)
	local old = tile:FindFirstChild(TILE_VISUAL_GUI_NAME)
	if old then old:Destroy() end

	local sg = Instance.new("SurfaceGui")
	sg.Name       = TILE_VISUAL_GUI_NAME
	sg.Face       = Enum.NormalId.Top
	sg.AlwaysOnTop = false
	sg.Active     = false
	sg.LightInfluence = 0
	sg.Brightness = 1
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 20
	sg.Parent     = tile

	local frame = Instance.new("Frame")
	frame.Name                = TILE_VISUAL_FRAME_NAME
	frame.Position            = UDim2.fromScale(0, 0)
	frame.Size                = UDim2.fromScale(1, 1)
	frame.BorderSizePixel     = 2
	frame.BorderColor3        = Color3.fromRGB(15, 15, 15)
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3    = getViewColor(tile, currentViewMode)
	frame.Active              = false
	frame.Parent              = sg
	return frame
end

local function ensureTileVisual(tile)
	return findTileVisualFrame(tile) or createTileVisual(tile)
end

local function setTileDisplayColor(tile, color)
	tile.Color = color
	ensureTileVisual(tile).BackgroundColor3 = color
end

--------------------------------------------------
-- VIEW MODE
--------------------------------------------------

local function updateViewModeButton()
	viewModeButton.Text = "View: " .. currentViewMode .. "  |  Click to Switch"
end

local function applyViewMode(viewMode)
	currentViewMode = viewMode
	if currentMapFolder and currentMapFolder.Parent then
		for _, inst in ipairs(currentMapFolder:GetChildren()) do
			if isTemplateTile(inst) then
				setTileDisplayColor(inst, getViewColor(inst, currentViewMode))
			end
		end
	end
	updateViewModeButton()
end

--------------------------------------------------
-- ADAPTIVE GRID
--------------------------------------------------

local function clearGridState()
	table.clear(gridLines)
	table.clear(gridOriginalSizes)
	mapCenter   = nil
	mapSurfaceY = nil
end

local function registerGridLine(line)
	-- Grid lines are no longer used — per-tile SurfaceGui borders replace them.
	-- Hide any server-created grid line Parts so they don't render.
	line.Transparency = 1
	line.CanCollide   = false
	line.CanQuery     = false
end

local function calculateMapBounds()
	if not currentMapFolder then mapCenter = nil; mapSurfaceY = nil; return end
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	-- Use the LOWEST tile surface so the grid sits at ground level.
	-- Elevated tiles rise above the grid naturally.
	local topY = math.huge
	local found = false
	for _, inst in ipairs(currentMapFolder:GetChildren()) do
		if isTemplateTile(inst) then
			found = true
			local hx, hz = inst.Size.X / 2, inst.Size.Z / 2
			minX = math.min(minX, inst.Position.X - hx)
			maxX = math.max(maxX, inst.Position.X + hx)
			minZ = math.min(minZ, inst.Position.Z - hz)
			maxZ = math.max(maxZ, inst.Position.Z + hz)
			topY = math.min(topY, inst.Position.Y + inst.Size.Y / 2)
		end
	end
	if not found then mapCenter = nil; mapSurfaceY = nil; return end
	mapSurfaceY = topY
	mapCenter   = Vector3.new((minX + maxX) / 2, topY, (minZ + maxZ) / 2)
end

local function registerCurrentMapChildren()
	if not currentMapFolder then return end
	for _, inst in ipairs(currentMapFolder:GetChildren()) do
		if isGridLine(inst) then registerGridLine(inst) end
	end
	calculateMapBounds()
end

local function updateAdaptiveGrid()
	-- No-op: grid lines replaced by per-tile SurfaceGui borders.
end

--------------------------------------------------
-- MAP ATTACHMENT
--------------------------------------------------

local function disconnectMapChildAdded()
	if mapChildAddedConnection then
		mapChildAddedConnection:Disconnect()
		mapChildAddedConnection = nil
	end
end

local function registerMapChild(child)
	if isTemplateTile(child) then
		setTileDisplayColor(child, getViewColor(child, currentViewMode))
		calculateMapBounds()
	elseif isGridLine(child) then
		registerGridLine(child)
	end
end

local function attachToMapFolder(mapFolder)
	disconnectMapChildAdded()
	clearGridState()
	currentMapFolder = mapFolder

	local iv = mapFolder:GetAttribute("InitialViewMode")
	currentViewMode = (iv == "TEMPLATE" or iv == "REGION") and iv or "REGION"

	mapChildAddedConnection = mapFolder.ChildAdded:Connect(registerMapChild)
	applyViewMode(currentViewMode)
	registerCurrentMapChildren()
	updateAdaptiveGrid()
end

--------------------------------------------------
-- INSPECTOR TEXT  (RichText, styled like unit panel)
--------------------------------------------------

local function buildTileText(tile)
	if not tile then return "" end

	local marker   = getAttributeText(tile, "TemplateMarker", "?")
	local x        = getAttributeText(tile, "X", "?")
	local y        = getAttributeText(tile, "Y", "?")
	local biome    = getAttributeText(tile, "BiomeId",  "—")
	local region   = getAttributeText(tile, "RegionId", "—")
	local elev     = getAttributeText(tile, "Elevation", "—")
	local terrain  = getAttributeText(tile, "Terrain",  "—")
	local effect   = getAttributeText(tile, "Effect",   "None")
	local passable = getAttributeText(tile, "Passable", "?")

	return string.format(
		"<font color='#CCCCCC'><b>Tile (%s, %s)</b></font>\n" ..
		"<font color='#888888'>Marker: %s</font>\n\n" ..
		"<font color='#AAAAAA'>── LOCATION ──</font>\n" ..
		"Biome    %s\n" ..
		"Region   %s\n\n" ..
		"<font color='#AAAAAA'>── TERRAIN ──</font>\n" ..
		"Type     %s\n" ..
		"Elev     %s\n" ..
		"Effect   %s\n" ..
		"Passable %s",
		x, y,
		marker,
		biome,
		region,
		terrain,
		elev,
		effect,
		passable
	)
end

local function buildObjectText(tile)
	if not tile then return "" end
	local name     = getAttributeText(tile, "ObjectName",             "None")
	local category = getAttributeText(tile, "ObjectCategory",         "None")
	local impact   = getAttributeText(tile, "ObjectPassabilityImpact","None")

	return string.format(
		"<font color='#AAAAAA'>── OBJECT ──</font>\n" ..
		"Name     %s\n" ..
		"Category %s\n" ..
		"Passability Impact\n%s",
		name, category, impact
	)
end

local function updateInspector()
	if not selectedTile then
		tilePanel.Visible   = false
		objectPanel.Visible = false
		return
	end

	-- Stripe color matches template marker
	local marker = selectedTile:GetAttribute("TemplateMarker") or "NEU"
	local stripeColor = MARKER_COLORS[marker] or Color3.fromRGB(120, 120, 120)
	tileStripe.BackgroundColor3   = stripeColor
	objectStripe.BackgroundColor3 = stripeColor

	tileContent.Text   = buildTileText(selectedTile)
	objectContent.Text = buildObjectText(selectedTile)

	tilePanel.Visible   = true
	objectPanel.Visible = true
end

--------------------------------------------------
-- HOVER AND SELECTION
--------------------------------------------------

local function setHoveredTile(tile)
	if hoveredTile == tile then return end
	hoveredTile = tile
	if hoveredTile and hoveredTile ~= selectedTile then
		hoverBox.Adornee = hoveredTile
		hoverBox.Visible = true
	else
		hoverBox.Adornee = nil
		hoverBox.Visible = false
	end
end

-- Find a unit occupying a tile by grid coordinates.
-- Calls into _G.CTRBLXAI_SelectUnit if the tile has a unit on it.
local function trySelectUnitOnTile(tile)
	if not tile then return end

	-- Pass the tile's world position so the battle client can match by proximity.
	if type(_G.CTRBLXAI_SelectUnitNearWorldPos) == "function" then
		_G.CTRBLXAI_SelectUnitNearWorldPos(tile.Position.X, tile.Position.Z)
	end
end

local function setSelectedTile(tile)
	selectedTile = tile

	if selectedTile then
		selectedBox.Adornee = selectedTile
		selectedBox.Visible = true
	else
		selectedBox.Adornee = nil
		selectedBox.Visible = false
	end

	if hoveredTile == selectedTile then
		hoverBox.Adornee = nil
		hoverBox.Visible = false
	end

	updateInspector()
	trySelectUnitOnTile(tile)
end

-- Publish to _G so BattleVisualClient can drive tile selection
-- when a unit token is clicked.
-- Finds the tile Part at the given grid coords and selects it.
_G.CTRBLXAI_SelectTileAt = function(tileX, tileY)
	if not currentMapFolder then return end
	for _, inst in ipairs(currentMapFolder:GetChildren()) do
		if isTemplateTile(inst) then
			local x = inst:GetAttribute("X")
			local y = inst:GetAttribute("Y")
			if x == tileX and y == tileY then
				setSelectedTile(inst)
				return
			end
		end
	end
	-- Tile not found (e.g. battle map is separate from template map) — clear selection.
	setSelectedTile(nil)
end

--------------------------------------------------
-- VIEW MODE BUTTON
--------------------------------------------------

viewModeButton.Activated:Connect(function()
	applyViewMode(currentViewMode == "REGION" and "TEMPLATE" or "REGION")
end)

--------------------------------------------------
-- MAP EVENTS
--------------------------------------------------

workspace.ChildAdded:Connect(function(child)
	if child.Name == "TemplateViewerMap" and child:IsA("Folder") then
		attachToMapFolder(child)
	end
end)

workspace.ChildRemoved:Connect(function(child)
	if child == currentMapFolder then
		disconnectMapChildAdded()
		clearGridState()
		currentMapFolder = nil
		hoveredTile      = nil
		selectedTile     = nil
		hoverBox.Adornee  = nil
		hoverBox.Visible  = false
		selectedBox.Adornee = nil
		selectedBox.Visible = false
		updateInspector()
	end
end)

--------------------------------------------------
-- INPUT  (RenderStepped hover + click selection)
--------------------------------------------------

local function findTileAtPosition(worldPos)
	-- Raycast straight down from clicked position to find the tile underneath
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	local tileParts = {}
	for _, child in ipairs(workspace:FindFirstChild("TemplateViewerMap"):GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute("IsTemplateTile") == true then
			table.insert(tileParts, child)
		end
	end
	rayParams.FilterDescendantsInstances = tileParts
	local origin = Vector3.new(worldPos.X, worldPos.Y + 50, worldPos.Z)
	local result = workspace:Raycast(origin, Vector3.new(0, -100, 0), rayParams)
	return result and result.Instance or nil
end

RunService.RenderStepped:Connect(function()
	updateAdaptiveGrid()
	local target = mouse.Target
	if isTemplateTile(target) then
		setHoveredTile(target)
	else
		setHoveredTile(nil)
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local target = mouse.Target
		if isTemplateTile(target) then
			setSelectedTile(target)
		elseif target and target:IsA("BasePart") then
			-- Clicked a non-tile object (blocker, unit, etc.)
			-- Find the tile underneath it
			local tile = findTileAtPosition(target.Position)
			if tile then
				setSelectedTile(tile)
			end
		end
	end
end)

--------------------------------------------------
-- INITIAL STATE
--------------------------------------------------

local existingMap = workspace:FindFirstChild("TemplateViewerMap")
if existingMap and existingMap:IsA("Folder") then
	attachToMapFolder(existingMap)
else
	updateViewModeButton()
end

updateInspector()
