local GridGenerator = require(script.Parent.GridGenerator)

local MapGenerator = {}

local TILE_SIZE = 4
local TILE_HEIGHT = 1

local MAP_WIDTH = 20
local MAP_HEIGHT = 30

local COLORS = {
	City = Color3.fromRGB(120, 120, 130),
	Beach = Color3.fromRGB(235, 210, 130),
	Sea = Color3.fromRGB(55, 130, 210),

	Road = Color3.fromRGB(80, 80, 80),
	ShorePath = Color3.fromRGB(210, 180, 110),
	Sandbar = Color3.fromRGB(240, 220, 150),
}

local function getTileColor(tile)
	if tile.IsCorridor then
		if tile.TerrainType == "Road" then
			return COLORS.Road
		elseif tile.TerrainType == "ShorePath" then
			return COLORS.ShorePath
		elseif tile.TerrainType == "Sandbar" then
			return COLORS.Sandbar
		end
	end

	if tile.RegionName == "City" then
		return COLORS.City
	elseif tile.RegionName == "Beach" then
		return COLORS.Beach
	elseif tile.RegionName == "Sea" then
		return COLORS.Sea
	end

	return Color3.fromRGB(255, 0, 255)
end

local function createTilePart(tile, parent)
	local part = Instance.new("Part")

	part.Name = string.format(
		"Tile_%02d_%02d_%s",
		tile.X,
		tile.Y,
		tile.RegionName
	)

	part.Size = Vector3.new(
		TILE_SIZE,
		TILE_HEIGHT,
		TILE_SIZE
	)

	part.Anchored = true

	part.Position = Vector3.new(
		(tile.X - 1) * TILE_SIZE,
		tile.Elevation,
		(tile.Y - 1) * TILE_SIZE
	)

	part.Color = getTileColor(tile)

	part.Material = Enum.Material.SmoothPlastic

	part:SetAttribute("X", tile.X)
	part:SetAttribute("Y", tile.Y)
	part:SetAttribute("RegionId", tile.RegionId)
	part:SetAttribute("RegionName", tile.RegionName)
	part:SetAttribute("TerrainType", tile.TerrainType)
	part:SetAttribute("Elevation", tile.Elevation)
	part:SetAttribute("IsCorridor", tile.IsCorridor)
	part:SetAttribute("IsWalkable", tile.IsWalkable)
	part:SetAttribute("IsReserved", tile.IsReserved)

	part.Parent = parent

	return part
end

function MapGenerator.Generate()
	local existing = workspace:FindFirstChild("GeneratedMap")

	if existing then
		existing:Destroy()
	end

	local mapFolder = Instance.new("Folder")
	mapFolder.Name = "GeneratedMap"
	mapFolder.Parent = workspace

	local grid = GridGenerator.Generate(MAP_WIDTH, MAP_HEIGHT)

	for y, row in ipairs(grid) do
		for _, tile in ipairs(row) do
			createTilePart(tile, mapFolder)
		end
	end

	print("Generated 20x30 Region + Corridor Prototype")
	print("Regions: City -> Beach -> Sea")
	print("Corridor: Reserved vertical connection through all regions")

	return grid
end

return MapGenerator