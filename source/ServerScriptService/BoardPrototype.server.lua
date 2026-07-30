-- BoardPrototype.server.lua
-- Creates the CTRBLXAI tactical board prototype.
-- The server owns the board and current tile selection.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GRID_SIZE = 8
local TILE_SIZE = 4
local TILE_HEIGHT = 1
local TILE_GAP = 0.25
local TILE_SPACING = TILE_SIZE + TILE_GAP

local LIGHT_TILE_COLOR = Color3.fromRGB(163, 162, 165)
local DARK_TILE_COLOR = Color3.fromRGB(99, 95, 98)

local SELECTION_COLOR = Color3.fromRGB(255, 221, 0)
local SELECTION_HEIGHT_OFFSET = 0.08
local SELECTION_FRAME_THICKNESS = 0.16
local SELECTION_FRAME_HEIGHT = 0.12

local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")

if not remoteFolder then
	remoteFolder = Instance.new("Folder")
	remoteFolder.Name = "Remotes"
	remoteFolder.Parent = ReplicatedStorage
end

local selectionChangedEvent = remoteFolder:FindFirstChild("SelectionChanged")

if not selectionChangedEvent then
	selectionChangedEvent = Instance.new("RemoteEvent")
	selectionChangedEvent.Name = "SelectionChanged"
	selectionChangedEvent.Parent = remoteFolder
end

local clearSelectionEvent = remoteFolder:FindFirstChild("ClearSelection")

if not clearSelectionEvent then
	clearSelectionEvent = Instance.new("RemoteEvent")
	clearSelectionEvent.Name = "ClearSelection"
	clearSelectionEvent.Parent = remoteFolder
end

local existingBoard = workspace:FindFirstChild("Board")

if existingBoard then
	existingBoard:Destroy()
end

local boardFolder = Instance.new("Folder")
boardFolder.Name = "Board"
boardFolder.Parent = workspace

local selectionFolder = Instance.new("Folder")
selectionFolder.Name = "Selection"
selectionFolder.Parent = boardFolder

local selectedFrameParts = {}
local selectedTile = nil

local gridWidth = (GRID_SIZE - 1) * TILE_SPACING
local startX = -gridWidth / 2
local startZ = -gridWidth / 2

local function clearSelection()
	if selectedTile == nil then
		return
	end

	for _, framePart in ipairs(selectedFrameParts) do
		framePart:Destroy()
	end

	selectedFrameParts = {}
	selectedTile = nil

	selectionChangedEvent:FireAllClients(false)

	print("Selection cleared")
end

local function createSelectionFrameForTile(tile)
	for _, framePart in ipairs(selectedFrameParts) do
		framePart:Destroy()
	end

	selectedFrameParts = {}
	selectedTile = tile

	local tileTopY = tile.Position.Y + (tile.Size.Y / 2)
	local frameY = tileTopY + SELECTION_HEIGHT_OFFSET

	local outerSize = TILE_SIZE + 0.35
	local halfOuterSize = outerSize / 2
	local halfThickness = SELECTION_FRAME_THICKNESS / 2

	local frameDefinitions = {
		{
			name = "Selection_North",
			size = Vector3.new(
				outerSize,
				SELECTION_FRAME_HEIGHT,
				SELECTION_FRAME_THICKNESS
			),
			offset = Vector3.new(
				0,
				0,
				-halfOuterSize + halfThickness
			),
		},
		{
			name = "Selection_South",
			size = Vector3.new(
				outerSize,
				SELECTION_FRAME_HEIGHT,
				SELECTION_FRAME_THICKNESS
			),
			offset = Vector3.new(
				0,
				0,
				halfOuterSize - halfThickness
			),
		},
		{
			name = "Selection_West",
			size = Vector3.new(
				SELECTION_FRAME_THICKNESS,
				SELECTION_FRAME_HEIGHT,
				outerSize
			),
			offset = Vector3.new(
				-halfOuterSize + halfThickness,
				0,
				0
			),
		},
		{
			name = "Selection_East",
			size = Vector3.new(
				SELECTION_FRAME_THICKNESS,
				SELECTION_FRAME_HEIGHT,
				outerSize
			),
			offset = Vector3.new(
				halfOuterSize - halfThickness,
				0,
				0
			),
		},
	}

	for _, definition in ipairs(frameDefinitions) do
		local framePart = Instance.new("Part")

		framePart.Name = definition.name
		framePart.Size = definition.size

		framePart.Position = Vector3.new(
			tile.Position.X + definition.offset.X,
			frameY,
			tile.Position.Z + definition.offset.Z
		)

		framePart.Color = SELECTION_COLOR
		framePart.Material = Enum.Material.Neon
		framePart.Anchored = true
		framePart.CanCollide = false
		framePart.CanTouch = false
		framePart.CanQuery = false
		framePart.Parent = selectionFolder

		table.insert(selectedFrameParts, framePart)
	end

	selectionChangedEvent:FireAllClients(true)
end

local function makeTileClickable(tile, row, column)
	local clickDetector = Instance.new("ClickDetector")

	clickDetector.Name = "TileClickDetector"
	clickDetector.MaxActivationDistance = 100
	clickDetector.Parent = tile

	clickDetector.MouseClick:Connect(function()
		createSelectionFrameForTile(tile)

		print(string.format(
			"Selected tile: row %d, column %d",
			row,
			column
		))
	end)
end

for row = 1, GRID_SIZE do
	for column = 1, GRID_SIZE do
		local tile = Instance.new("Part")

		tile.Name = string.format(
			"Tile_%d_%d",
			row,
			column
		)

		tile.Size = Vector3.new(
			TILE_SIZE,
			TILE_HEIGHT,
			TILE_SIZE
		)

		tile.Position = Vector3.new(
			startX + (column - 1) * TILE_SPACING,
			TILE_HEIGHT / 2,
			startZ + (row - 1) * TILE_SPACING
		)

		if (row + column) % 2 == 0 then
			tile.Color = LIGHT_TILE_COLOR
		else
			tile.Color = DARK_TILE_COLOR
		end

		tile.Anchored = true
		tile.Parent = boardFolder

		makeTileClickable(tile, row, column)
	end
end

clearSelectionEvent.OnServerEvent:Connect(function()
	clearSelection()
end)

print("CTRBLXAI board prototype created: 8x8")
print("Tile selection enabled")
print("Cross-platform cancel input enabled")