-- BoardPrototype.server.lua
-- Creates the first visible Rblx CT tactical board prototype.

local GRID_SIZE = 8
local TILE_SIZE = 4
local TILE_HEIGHT = 1
local TILE_GAP = 0.25
local TILE_SPACING = TILE_SIZE + TILE_GAP

local LIGHT_TILE_COLOR = Color3.fromRGB(163, 162, 165)
local DARK_TILE_COLOR = Color3.fromRGB(99, 95, 98)

local boardFolder = Instance.new("Folder")
boardFolder.Name = "Board"
boardFolder.Parent = workspace

local gridWidth = (GRID_SIZE - 1) * TILE_SPACING
local startX = -gridWidth / 2
local startZ = -gridWidth / 2

for row = 1, GRID_SIZE do
    for column = 1, GRID_SIZE do
        local tile = Instance.new("Part")

        tile.Name = string.format("Tile_%d_%d", row, column)
        tile.Size = Vector3.new(TILE_SIZE, TILE_HEIGHT, TILE_SIZE)
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
    end
end

print("Rblx CT board prototype created: 8x8")