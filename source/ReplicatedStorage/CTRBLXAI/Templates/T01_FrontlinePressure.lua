local Template = {}

Template.Id = "T01"
Template.Name = "Frontline Pressure"
Template.Width = 30
Template.Height = 20

local function createGrid(width, height, defaultMarker)
	local grid = {}

	for y = 1, height do
		grid[y] = {}

		for x = 1, width do
			grid[y][x] = defaultMarker
		end
	end

	return grid
end

local function fillRect(grid, x1, y1, x2, y2, marker)
	for y = y1, y2 do
		for x = x1, x2 do
			if grid[y] and grid[y][x] then
				grid[y][x] = marker
			end
		end
	end
end

local grid = createGrid(Template.Width, Template.Height, "NEU")

-- Player deployment
fillRect(grid, 1, 1, 8, 5, "PD")

-- Enemy deployment
fillRect(grid, 23, 16, 30, 20, "ED")

-- Main combat lane
fillRect(grid, 5, 6, 26, 15, "LAN")

-- Hazard and blocker pressure
fillRect(grid, 12, 7, 19, 10, "HZD")
fillRect(grid, 12, 11, 19, 14, "BLK")

-- POI areas
fillRect(grid, 21, 3, 26, 5, "POI")
fillRect(grid, 5, 16, 10, 18, "POI")

-- Advantage areas
fillRect(grid, 8, 6, 11, 8, "ADV")
fillRect(grid, 20, 13, 23, 15, "ADV")

Template.Grid = grid

return Template