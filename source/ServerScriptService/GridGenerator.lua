local GridGenerator = {}

local DEFAULT_WIDTH = 20
local DEFAULT_HEIGHT = 30

local REGION_CITY = 1
local REGION_BEACH = 2
local REGION_SEA = 3

local REGION_NAMES = {
	[REGION_CITY] = "City",
	[REGION_BEACH] = "Beach",
	[REGION_SEA] = "Sea",
}

local REGION_TERRAIN = {
	[REGION_CITY] = "Stone",
	[REGION_BEACH] = "Sand",
	[REGION_SEA] = "ShallowWater",
}

local function getRegionId(y, height)
	local cityEnd = math.floor(height * 0.35)
	local beachEnd = math.floor(height * 0.70)

	if y <= cityEnd then
		return REGION_CITY
	elseif y <= beachEnd then
		return REGION_BEACH
	else
		return REGION_SEA
	end
end

local function isVerticalCorridor(x, y, width, height)
	local centerX = math.floor(width / 2)

	local corridorHalfWidth = 1

	if math.abs(x - centerX) > corridorHalfWidth then
		return false
	end

	return true
end

function GridGenerator.Generate(width, height)
	width = width or DEFAULT_WIDTH
	height = height or DEFAULT_HEIGHT

	local grid = {}

	for y = 1, height do
		grid[y] = {}

		for x = 1, width do
			local regionId = getRegionId(y, height)
			local isCorridor = isVerticalCorridor(x, y, width, height)

			local terrainType = REGION_TERRAIN[regionId]

			if isCorridor then
				if regionId == REGION_CITY then
					terrainType = "Road"
				elseif regionId == REGION_BEACH then
					terrainType = "ShorePath"
				elseif regionId == REGION_SEA then
					terrainType = "Sandbar"
				end
			end

			grid[y][x] = {
				X = x,
				Y = y,

				RegionId = regionId,
				RegionName = REGION_NAMES[regionId],

				IsCorridor = isCorridor,

				TerrainType = terrainType,

				Elevation = 5,

				IsWalkable = true,
				IsReserved = isCorridor,
			}
		end
	end

	return grid
end

return GridGenerator