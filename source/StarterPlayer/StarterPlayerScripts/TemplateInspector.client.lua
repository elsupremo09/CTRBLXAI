local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

--------------------------------------------------
-- SETTINGS
--------------------------------------------------

local HOVER_COLOR =
	Color3.fromRGB(255, 255, 255)

local SELECTED_COLOR =
	Color3.fromRGB(255, 230, 0)

local HOVER_OUTLINE_TRANSPARENCY = 0.15
local SELECTED_OUTLINE_TRANSPARENCY = 0

local SELECTION_LINE_THICKNESS = 0.16

local TILE_VISUAL_GUI_NAME =
	"TileVisualGui"

local TILE_VISUAL_FRAME_NAME =
	"TileVisualFrame"

--------------------------------------------------
-- ADAPTIVE GRID SETTINGS
--------------------------------------------------

local GRID_VERTICAL_PREFIX = "GridLine_V_"
local GRID_HORIZONTAL_PREFIX = "GridLine_H_"

-- Minimum grid width when the camera is close.
local GRID_MINIMUM_THICKNESS = 0.08

-- Maximum grid width when the camera is far away.
local GRID_MAXIMUM_THICKNESS = 0.40

-- Controls how quickly the grid becomes thicker
-- as the camera moves farther from the map.
local GRID_DISTANCE_SCALE = 0.0015

-- Minimum and maximum physical grid height.
local GRID_MINIMUM_HEIGHT = 0.04
local GRID_MAXIMUM_HEIGHT = 0.16

-- Keeps grid Parts above the solid SurfaceGui tops.
local GRID_SURFACE_GAP = 0.015

--------------------------------------------------
-- STATE
--------------------------------------------------

local hoveredTile = nil
local selectedTile = nil

local hoverBox = nil
local selectedBox = nil

local currentViewMode = "REGION"
local currentMapFolder = nil

local mapChildAddedConnection = nil

local gridLines = {}
local gridOriginalSizes = {}

local mapCenter = nil
local mapSurfaceY = nil

--------------------------------------------------
-- UI CREATION
--------------------------------------------------

local screenGui = Instance.new("ScreenGui")

screenGui.Name = "TileInspectorGui"
screenGui.ResetOnSpawn = false
screenGui.Parent =
	player:WaitForChild("PlayerGui")

local function createPanel(
	name,
	position,
	size,
	title
)
	local frame = Instance.new("Frame")

	frame.Name = name
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 =
		Color3.fromRGB(20, 20, 20)

	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	local titleLabel =
		Instance.new("TextLabel")

	titleLabel.Name = "Title"
	titleLabel.Position =
		UDim2.new(0, 10, 0, 8)

	titleLabel.Size =
		UDim2.new(1, -20, 0, 28)

	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.SourceSansBold
	titleLabel.TextSize = 24
	titleLabel.TextColor3 =
		Color3.fromRGB(255, 255, 255)

	titleLabel.TextXAlignment =
		Enum.TextXAlignment.Left

	titleLabel.Text = title
	titleLabel.Parent = frame

	local body = Instance.new("TextLabel")

	body.Name = "Body"
	body.Position =
		UDim2.new(0, 10, 0, 42)

	body.Size =
		UDim2.new(1, -20, 1, -52)

	body.BackgroundTransparency = 1
	body.Font = Enum.Font.Code
	body.TextSize = 15
	body.TextColor3 =
		Color3.fromRGB(255, 255, 255)

	body.TextXAlignment =
		Enum.TextXAlignment.Left

	body.TextYAlignment =
		Enum.TextYAlignment.Top

	body.TextWrapped = false
	body.Text = ""
	body.Parent = frame

	return frame, body
end

local tilePanel, tileBody = createPanel(
	"TileInspectorPanel",
	UDim2.new(1, -340, 0, 70),
	UDim2.new(0, 320, 0, 260),
	"Tile Inspector"
)

local objectPanel, objectBody = createPanel(
	"ObjectInspectorPanel",
	UDim2.new(1, -340, 0, 350),
	UDim2.new(0, 320, 0, 180),
	"Object Inspector"
)

--------------------------------------------------
-- VIEW MODE BUTTON
--------------------------------------------------

local viewModeButton =
	Instance.new("TextButton")

viewModeButton.Name = "ViewModeButton"
viewModeButton.AnchorPoint =
	Vector2.new(0.5, 0)

viewModeButton.Position =
	UDim2.new(0.5, 0, 0, 20)

viewModeButton.Size =
	UDim2.new(0, 230, 0, 42)

viewModeButton.BackgroundColor3 =
	Color3.fromRGB(20, 20, 20)

viewModeButton.BackgroundTransparency = 0.1
viewModeButton.BorderSizePixel = 0
viewModeButton.AutoButtonColor = true
viewModeButton.Font =
	Enum.Font.SourceSansBold

viewModeButton.TextSize = 20
viewModeButton.TextColor3 =
	Color3.fromRGB(255, 255, 255)

viewModeButton.Parent = screenGui

local buttonCorner =
	Instance.new("UICorner")

buttonCorner.CornerRadius =
	UDim.new(0, 6)

buttonCorner.Parent = viewModeButton

--------------------------------------------------
-- SELECTION BOXES
--------------------------------------------------

local function createSelectionBox(
	name,
	color,
	transparency
)
	local box = Instance.new("SelectionBox")

	box.Name = name
	box.Color3 = color
	box.LineThickness =
		SELECTION_LINE_THICKNESS

	box.Transparency = transparency
	box.Visible = false
	box.Parent = workspace

	return box
end

hoverBox = createSelectionBox(
	"TileHoverBox",
	HOVER_COLOR,
	HOVER_OUTLINE_TRANSPARENCY
)

selectedBox = createSelectionBox(
	"TileSelectedBox",
	SELECTED_COLOR,
	SELECTED_OUTLINE_TRANSPARENCY
)

--------------------------------------------------
-- INSTANCE HELPERS
--------------------------------------------------

local function isTemplateTile(instance)
	return instance
		and instance:IsA("BasePart")
		and instance:GetAttribute(
			"IsTemplateTile"
		) == true
end

local function isVerticalGridLine(instance)
	return instance
		and instance:IsA("BasePart")
		and string.sub(
			instance.Name,
			1,
			#GRID_VERTICAL_PREFIX
		) == GRID_VERTICAL_PREFIX
end

local function isHorizontalGridLine(instance)
	return instance
		and instance:IsA("BasePart")
		and string.sub(
			instance.Name,
			1,
			#GRID_HORIZONTAL_PREFIX
		) == GRID_HORIZONTAL_PREFIX
end

local function isGridLine(instance)
	return isVerticalGridLine(instance)
		or isHorizontalGridLine(instance)
end

local function getAttributeText(
	tile,
	attributeName,
	fallback
)
	local value =
		tile:GetAttribute(attributeName)

	if value == nil then
		return fallback
	end

	return tostring(value)
end

local function getViewColor(
	tile,
	viewMode
)
	local attributeName

	if viewMode == "TEMPLATE" then
		attributeName = "TemplateColor"
	else
		attributeName =
			"RegionDebugColor"
	end

	local color =
		tile:GetAttribute(attributeName)

	if typeof(color) == "Color3" then
		return color
	end

	return tile.Color
end

--------------------------------------------------
-- SOLID TILE-TOP VISUAL
--------------------------------------------------

local function findTileVisualFrame(tile)
	local surfaceGui =
		tile:FindFirstChild(
			TILE_VISUAL_GUI_NAME
		)

	if not surfaceGui
		or not surfaceGui:IsA(
			"SurfaceGui"
		) then
		return nil
	end

	local frame =
		surfaceGui:FindFirstChild(
			TILE_VISUAL_FRAME_NAME
		)

	if frame
		and frame:IsA("Frame") then
		return frame
	end

	return nil
end

local function createTileVisual(tile)
	local oldSurfaceGui =
		tile:FindFirstChild(
			TILE_VISUAL_GUI_NAME
		)

	if oldSurfaceGui then
		oldSurfaceGui:Destroy()
	end

	local surfaceGui =
		Instance.new("SurfaceGui")

	surfaceGui.Name =
		TILE_VISUAL_GUI_NAME

	surfaceGui.Face =
		Enum.NormalId.Top

	surfaceGui.AlwaysOnTop = false
	surfaceGui.Active = false
	surfaceGui.LightInfluence = 0
	surfaceGui.Brightness = 1

	surfaceGui.SizingMode =
		Enum.SurfaceGuiSizingMode.PixelsPerStud

	surfaceGui.PixelsPerStud = 20
	surfaceGui.Parent = tile

	local frame = Instance.new("Frame")

	frame.Name =
		TILE_VISUAL_FRAME_NAME

	frame.Position =
		UDim2.fromScale(0, 0)

	frame.Size =
		UDim2.fromScale(1, 1)

	frame.BorderSizePixel = 0
	frame.BackgroundTransparency = 0

	frame.BackgroundColor3 =
		getViewColor(
			tile,
			currentViewMode
		)

	frame.Active = false
	frame.Parent = surfaceGui

	return frame
end

local function ensureTileVisual(tile)
	local frame =
		findTileVisualFrame(tile)

	if frame then
		return frame
	end

	return createTileVisual(tile)
end

local function setTileDisplayColor(
	tile,
	displayColor
)
	tile.Color = displayColor

	local visualFrame =
		ensureTileVisual(tile)

	visualFrame.BackgroundColor3 =
		displayColor
end

--------------------------------------------------
-- VIEW MODE
--------------------------------------------------

local function updateViewModeButton()
	viewModeButton.Text =
		"View: "
		.. currentViewMode
		.. " | Click to Switch"
end

local function applyViewMode(viewMode)
	currentViewMode = viewMode

	if currentMapFolder
		and currentMapFolder.Parent then
		for _, instance in ipairs(
			currentMapFolder:GetChildren()
		) do
			if isTemplateTile(instance) then
				local displayColor =
					getViewColor(
						instance,
						currentViewMode
					)

				setTileDisplayColor(
					instance,
					displayColor
				)
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

	mapCenter = nil
	mapSurfaceY = nil
end

local function registerGridLine(line)
	if gridOriginalSizes[line] then
		return
	end

	table.insert(gridLines, line)
	gridOriginalSizes[line] = line.Size

	line.Material = Enum.Material.Neon
	line.Color = Color3.fromRGB(15, 15, 15)
	line.CastShadow = false
	line.CanCollide = false
	line.CanTouch = false
	line.CanQuery = false
end

local function calculateMapBounds()
	if not currentMapFolder then
		mapCenter = nil
		mapSurfaceY = nil
		return
	end

	local minimumX = math.huge
	local maximumX = -math.huge
	local minimumZ = math.huge
	local maximumZ = -math.huge
	local highestSurfaceY = -math.huge
	local tileFound = false

	for _, instance in ipairs(
		currentMapFolder:GetChildren()
	) do
		if isTemplateTile(instance) then
			tileFound = true

			local halfX =
				instance.Size.X / 2

			local halfZ =
				instance.Size.Z / 2

			minimumX = math.min(
				minimumX,
				instance.Position.X - halfX
			)

			maximumX = math.max(
				maximumX,
				instance.Position.X + halfX
			)

			minimumZ = math.min(
				minimumZ,
				instance.Position.Z - halfZ
			)

			maximumZ = math.max(
				maximumZ,
				instance.Position.Z + halfZ
			)

			highestSurfaceY = math.max(
				highestSurfaceY,
				instance.Position.Y
					+ (instance.Size.Y / 2)
			)
		end
	end

	if not tileFound then
		mapCenter = nil
		mapSurfaceY = nil
		return
	end

	mapSurfaceY = highestSurfaceY

	mapCenter = Vector3.new(
		(minimumX + maximumX) / 2,
		mapSurfaceY,
		(minimumZ + maximumZ) / 2
	)
end

local function registerCurrentMapChildren()
	if not currentMapFolder then
		return
	end

	for _, instance in ipairs(
		currentMapFolder:GetChildren()
	) do
		if isGridLine(instance) then
			registerGridLine(instance)
		end
	end

	calculateMapBounds()
end

local function updateAdaptiveGrid()
	local camera = workspace.CurrentCamera

	if not camera
		or not mapCenter
		or not mapSurfaceY then
		return
	end

	local cameraDistance =
		(
			camera.CFrame.Position
			- mapCenter
		).Magnitude

	local gridThickness =
		math.clamp(
			GRID_MINIMUM_THICKNESS
				+ (
					cameraDistance
					* GRID_DISTANCE_SCALE
				),
			GRID_MINIMUM_THICKNESS,
			GRID_MAXIMUM_THICKNESS
		)

	local gridHeight =
		math.clamp(
			gridThickness * 0.5,
			GRID_MINIMUM_HEIGHT,
			GRID_MAXIMUM_HEIGHT
		)

	local gridPositionY =
		mapSurfaceY
		+ GRID_SURFACE_GAP
		+ (gridHeight / 2)

	for index = #gridLines, 1, -1 do
		local line = gridLines[index]
		local originalSize =
			gridOriginalSizes[line]

		if not line
			or not line.Parent
			or not originalSize then
			table.remove(gridLines, index)

			if line then
				gridOriginalSizes[line] = nil
			end
		else
			if isVerticalGridLine(line) then
				line.Size = Vector3.new(
					gridThickness,
					gridHeight,
					originalSize.Z
				)
			elseif isHorizontalGridLine(line) then
				line.Size = Vector3.new(
					originalSize.X,
					gridHeight,
					gridThickness
				)
			end

			line.Position = Vector3.new(
				line.Position.X,
				gridPositionY,
				line.Position.Z
			)
		end
	end
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
		local displayColor =
			getViewColor(
				child,
				currentViewMode
			)

		setTileDisplayColor(
			child,
			displayColor
		)

		calculateMapBounds()
	elseif isGridLine(child) then
		registerGridLine(child)
	end
end

local function attachToMapFolder(mapFolder)
	disconnectMapChildAdded()
	clearGridState()

	currentMapFolder = mapFolder

	local initialViewMode =
		mapFolder:GetAttribute(
			"InitialViewMode"
		)

	if initialViewMode == "TEMPLATE"
		or initialViewMode == "REGION" then
		currentViewMode =
			initialViewMode
	else
		currentViewMode = "REGION"
	end

	mapChildAddedConnection =
		mapFolder.ChildAdded:Connect(
			registerMapChild
		)

	applyViewMode(currentViewMode)
	registerCurrentMapChildren()
	updateAdaptiveGrid()
end

--------------------------------------------------
-- INSPECTOR TEXT
--------------------------------------------------

local function buildTileInspectorText(tile)
	if not tile then
		return "No tile selected."
	end

	local x =
		getAttributeText(tile, "X", "?")

	local y =
		getAttributeText(tile, "Y", "?")

	local marker =
		getAttributeText(
			tile,
			"TemplateMarker",
			"Unknown"
		)

	local biomeId =
		getAttributeText(
			tile,
			"BiomeId",
			"Unknown"
		)

	local elevation =
		getAttributeText(
			tile,
			"Elevation",
			"Unknown"
		)

	local terrain =
		getAttributeText(
			tile,
			"Terrain",
			"Unknown"
		)

	local regionId =
		getAttributeText(
			tile,
			"RegionId",
			"Unknown"
		)

	local effect =
		getAttributeText(
			tile,
			"Effect",
			"None"
		)

	local passable =
		getAttributeText(
			tile,
			"Passable",
			"Unknown"
		)

	return table.concat({
		"Coordinates: " .. x .. ", " .. y,
		"Template Marker: " .. marker,
		"Biome: " .. biomeId,
		"Elevation: " .. elevation,
		"Terrain: " .. terrain,
		"Region ID: " .. regionId,
		"Effect: " .. effect,
		"Passable: " .. passable,
	}, "\n")
end

local function buildObjectInspectorText(tile)
	if not tile then
		return "No tile selected."
	end

	local objectName =
		getAttributeText(
			tile,
			"ObjectName",
			"None"
		)

	local objectCategory =
		getAttributeText(
			tile,
			"ObjectCategory",
			"None"
		)

	local objectPassabilityImpact =
		getAttributeText(
			tile,
			"ObjectPassabilityImpact",
			"None"
		)

	return table.concat({
		"Object: " .. objectName,
		"Category: " .. objectCategory,
		"Passability Impact: "
			.. objectPassabilityImpact,
	}, "\n")
end

local function updateInspector()
	tileBody.Text =
		buildTileInspectorText(
			selectedTile
		)

	objectBody.Text =
		buildObjectInspectorText(
			selectedTile
		)
end

--------------------------------------------------
-- HOVER AND SELECTION
--------------------------------------------------

local function setHoveredTile(tile)
	if hoveredTile == tile then
		return
	end

	hoveredTile = tile

	if hoveredTile
		and hoveredTile ~= selectedTile then
		hoverBox.Adornee = hoveredTile
		hoverBox.Visible = true
	else
		hoverBox.Adornee = nil
		hoverBox.Visible = false
	end
end

local function setSelectedTile(tile)
	selectedTile = tile

	if selectedTile then
		selectedBox.Adornee =
			selectedTile

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
end

--------------------------------------------------
-- VIEW MODE EVENTS
--------------------------------------------------

viewModeButton.Activated:Connect(
	function()
		if currentViewMode == "REGION" then
			applyViewMode("TEMPLATE")
		else
			applyViewMode("REGION")
		end
	end
)

workspace.ChildAdded:Connect(
	function(child)
		if child.Name == "TemplateViewerMap"
			and child:IsA("Folder") then
			attachToMapFolder(child)
		end
	end
)

workspace.ChildRemoved:Connect(
	function(child)
		if child == currentMapFolder then
			disconnectMapChildAdded()
			clearGridState()

			currentMapFolder = nil
			hoveredTile = nil
			selectedTile = nil

			hoverBox.Adornee = nil
			hoverBox.Visible = false

			selectedBox.Adornee = nil
			selectedBox.Visible = false

			updateInspector()
		end
	end
)

--------------------------------------------------
-- TILE INPUT AND FRAME UPDATE
--------------------------------------------------

RunService.RenderStepped:Connect(
	function()
		updateAdaptiveGrid()

		local target = mouse.Target

		if isTemplateTile(target) then
			setHoveredTile(target)
		else
			setHoveredTile(nil)
		end
	end
)

UserInputService.InputBegan:Connect(
	function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.UserInputType
			== Enum.UserInputType.MouseButton1 then
			local target = mouse.Target

			if isTemplateTile(target) then
				setSelectedTile(target)
			end
		end
	end
)

--------------------------------------------------
-- INITIAL STATE
--------------------------------------------------

local existingMap =
	workspace:FindFirstChild(
		"TemplateViewerMap"
	)

if existingMap
	and existingMap:IsA("Folder") then
	attachToMapFolder(existingMap)
else
	updateViewModeButton()
end

updateInspector()