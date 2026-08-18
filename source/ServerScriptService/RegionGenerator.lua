-- RegionGenerator.lua
-- CTRBLXAI Region Generator V1
--
-- Generates a complete randomized region-ownership grid.
--
-- Guarantees:
-- - Every tile receives exactly one Region ID.
-- - Every region is cardinally connected.
-- - Every region reaches its configured minimum tile count.
-- - Region shapes are generated through unrestricted growth.
-- - Generation is bounded by a maximum attempt count.
--
-- This module does not create Roblox Instances.
-- This module does not generate terrain, elevation, objects,
-- hazards, POIs, deployment, pathfinding, or combat data.

local RegionGenerator = {}

--------------------------------------------------
-- DEFAULTS
--------------------------------------------------

local DEFAULT_BIOME_ID = "Plains"
local DEFAULT_REGION_COUNT = 3
local DEFAULT_MINIMUM_REGION_PERCENT = 0.25
local DEFAULT_MAXIMUM_GENERATION_ATTEMPTS = 100

local DEBUG_COLORS = {
	Color3.fromRGB(231, 76, 60),
	Color3.fromRGB(52, 152, 219),
	Color3.fromRGB(46, 204, 113),
	Color3.fromRGB(241, 196, 15),
	Color3.fromRGB(155, 89, 182),
	Color3.fromRGB(230, 126, 34),
	Color3.fromRGB(26, 188, 156),
	Color3.fromRGB(149, 165, 166),
}

local CARDINAL_DIRECTIONS = {
	{ x = 1, y = 0 },
	{ x = -1, y = 0 },
	{ x = 0, y = 1 },
	{ x = 0, y = -1 },
}

--------------------------------------------------
-- INPUT VALIDATION
--------------------------------------------------

local function assertPositiveInteger(value, name)
	assert(
		type(value) == "number",
		name .. " must be a number."
	)

	assert(
		value == math.floor(value),
		name .. " must be an integer."
	)

	assert(
		value > 0,
		name .. " must be greater than zero."
	)
end

local function isInsideGrid(x, y, width, height)
	return x >= 1
		and x <= width
		and y >= 1
		and y <= height
end

--------------------------------------------------
-- DATA CREATION
--------------------------------------------------

local function createGrid(width, height)
	local grid = {}

	for y = 1, height do
		grid[y] = {}

		for x = 1, width do
			grid[y][x] = nil
		end
	end

	return grid
end

local function createRegionId(index)
	return string.format("R%03d", index)
end

local function getDebugColor(index)
	local paletteIndex =
		((index - 1) % #DEBUG_COLORS) + 1

	return DEBUG_COLORS[paletteIndex]
end

local function createRegions(
	regionCount,
	biomeId,
	minimumTileCount
)
	local regions = {}

	for index = 1, regionCount do
		regions[index] = {
			Id = createRegionId(index),
			BiomeId = biomeId,
			DebugColor = getDebugColor(index),
			TileCount = 0,
			MinimumTileCount = minimumTileCount,
			SeedX = nil,
			SeedY = nil,
		}
	end

	return regions
end

--------------------------------------------------
-- SEED PLACEMENT
--------------------------------------------------

local function getManhattanDistance(
	x1,
	y1,
	x2,
	y2
)
	return math.abs(x1 - x2)
		+ math.abs(y1 - y2)
end

local function isSeedFarEnough(
	x,
	y,
	regions,
	minimumDistance
)
	for _, region in ipairs(regions) do
		if region.SeedX ~= nil then
			local distance =
				getManhattanDistance(
					x,
					y,
					region.SeedX,
					region.SeedY
				)

			if distance < minimumDistance then
				return false
			end
		end
	end

	return true
end

local function placeSeeds(
	grid,
	regions,
	width,
	height,
	random
)
	local minimumDistance = math.max(
		2,
		math.floor(
			(width + height)
				/ (#regions * 3)
		)
	)

	local placementAttemptLimit =
		width * height * 10

	for _, region in ipairs(regions) do
		local placed = false

		for _ = 1, placementAttemptLimit do
			local x =
				random:NextInteger(1, width)

			local y =
				random:NextInteger(1, height)

			if grid[y][x] == nil
				and isSeedFarEnough(
					x,
					y,
					regions,
					minimumDistance
				) then
				grid[y][x] = region.Id

				region.SeedX = x
				region.SeedY = y
				region.TileCount = 1

				placed = true
				break
			end
		end

		if not placed then
			return false
		end
	end

	return true
end

--------------------------------------------------
-- CLAIMABLE-TILE COLLECTION
--------------------------------------------------

local function getCoordinateKey(x, y)
	return tostring(x)
		.. ":"
		.. tostring(y)
end

local function collectClaimableTiles(
	grid,
	regionId,
	width,
	height
)
	local claimableByKey = {}
	local claimableTiles = {}

	for y = 1, height do
		for x = 1, width do
			if grid[y][x] == regionId then
				for _, direction
					in ipairs(
						CARDINAL_DIRECTIONS
					) do
					local neighborX =
						x + direction.x

					local neighborY =
						y + direction.y

					if isInsideGrid(
						neighborX,
						neighborY,
						width,
						height
					)
						and grid[neighborY][neighborX]
							== nil then
						local key =
							getCoordinateKey(
								neighborX,
								neighborY
							)

						if not claimableByKey[key] then
							claimableByKey[key] = true

							table.insert(
								claimableTiles,
								{
									x = neighborX,
									y = neighborY,
								}
							)
						end
					end
				end
			end
		end
	end

	return claimableTiles
end

local function claimRandomTile(
	grid,
	region,
	claimableTiles,
	random
)
	local claimedTile =
		claimableTiles[
			random:NextInteger(
				1,
				#claimableTiles
			)
		]

	grid[claimedTile.y][claimedTile.x] =
		region.Id

	region.TileCount += 1
end

--------------------------------------------------
-- MINIMUM-SIZE GROWTH
--------------------------------------------------

local function allRegionsReachedMinimum(
	regions,
	minimumTileCount
)
	for _, region in ipairs(regions) do
		if region.TileCount < minimumTileCount then
			return false
		end
	end

	return true
end

local function getSmallestUnderMinimumRegions(
	regions,
	minimumTileCount
)
	local smallestTileCount = math.huge
	local smallestRegions = {}

	for regionIndex, region
		in ipairs(regions) do
		if region.TileCount < minimumTileCount then
			if region.TileCount
				< smallestTileCount then
				smallestTileCount =
					region.TileCount

				smallestRegions = {
					regionIndex,
				}
			elseif region.TileCount
				== smallestTileCount then
				table.insert(
					smallestRegions,
					regionIndex
				)
			end
		end
	end

	return smallestRegions
end

local function growRegionsToMinimum(
	grid,
	regions,
	width,
	height,
	minimumTileCount,
	random
)
	while not allRegionsReachedMinimum(
		regions,
		minimumTileCount
	) do
		local smallestRegions =
			getSmallestUnderMinimumRegions(
				regions,
				minimumTileCount
			)

		if #smallestRegions == 0 then
			return true, nil
		end

		local candidates = {}

		for _, regionIndex
			in ipairs(smallestRegions) do
			local region =
				regions[regionIndex]

			local claimableTiles =
				collectClaimableTiles(
					grid,
					region.Id,
					width,
					height
				)

			if #claimableTiles > 0 then
				table.insert(
					candidates,
					{
						RegionIndex =
							regionIndex,

						ClaimableTiles =
							claimableTiles,
					}
				)
			end
		end

		if #candidates == 0 then
			return false,
				"One or more minimum-size regions became enclosed."
		end

		local selectedCandidate =
			candidates[
				random:NextInteger(
					1,
					#candidates
				)
			]

		local selectedRegion =
			regions[
				selectedCandidate.RegionIndex
			]

		claimRandomTile(
			grid,
			selectedRegion,
			selectedCandidate.ClaimableTiles,
			random
		)
	end

	return true, nil
end

--------------------------------------------------
-- REMAINING OPEN GROWTH
--------------------------------------------------

local function countAssignedTiles(regions)
	local assignedTileCount = 0

	for _, region in ipairs(regions) do
		assignedTileCount += region.TileCount
	end

	return assignedTileCount
end

local function collectExpandableRegions(
	grid,
	regions,
	width,
	height
)
	local expandableRegions = {}

	for regionIndex, region
		in ipairs(regions) do
		local claimableTiles =
			collectClaimableTiles(
				grid,
				region.Id,
				width,
				height
			)

		if #claimableTiles > 0 then
			table.insert(
				expandableRegions,
				{
					RegionIndex = regionIndex,
					ClaimableTiles =
						claimableTiles,
				}
			)
		end
	end

	return expandableRegions
end

local function chooseOpenGrowthCandidate(
	expandableRegions,
	regions,
	random
)
	-- Smaller regions receive a moderate weighting advantage,
	-- but every expandable region remains eligible.
	local totalWeight = 0
	local weightedCandidates = {}

	for _, entry in ipairs(expandableRegions) do
		local region =
			regions[entry.RegionIndex]

		local weight =
			1 / math.max(region.TileCount, 1)

		totalWeight += weight

		table.insert(
			weightedCandidates,
			{
				Entry = entry,
				Weight = weight,
			}
		)
	end

	local roll =
		random:NextNumber(0, totalWeight)

	local accumulatedWeight = 0

	for _, candidate
		in ipairs(weightedCandidates) do
		accumulatedWeight +=
			candidate.Weight

		if roll <= accumulatedWeight then
			return candidate.Entry
		end
	end

	return weightedCandidates[
		#weightedCandidates
	].Entry
end

local function growRemainingTiles(
	grid,
	regions,
	width,
	height,
	random
)
	local totalTileCount =
		width * height

	local assignedTileCount =
		countAssignedTiles(regions)

	while assignedTileCount < totalTileCount do
		local expandableRegions =
			collectExpandableRegions(
				grid,
				regions,
				width,
				height
			)

		if #expandableRegions == 0 then
			return false,
				"Unassigned tiles remain but no region can expand."
		end

		local selectedCandidate =
			chooseOpenGrowthCandidate(
				expandableRegions,
				regions,
				random
			)

		local selectedRegion =
			regions[
				selectedCandidate.RegionIndex
			]

		claimRandomTile(
			grid,
			selectedRegion,
			selectedCandidate.ClaimableTiles,
			random
		)

		assignedTileCount += 1
	end

	return true, nil
end

--------------------------------------------------
-- CONNECTIVITY VALIDATION
--------------------------------------------------

local function countConnectedTiles(
	grid,
	region,
	width,
	height
)
	if region.SeedX == nil
		or region.SeedY == nil then
		return 0
	end

	local visited = {}
	local queue = {
		{
			x = region.SeedX,
			y = region.SeedY,
		},
	}

	local queueIndex = 1
	local connectedCount = 0

	visited[
		getCoordinateKey(
			region.SeedX,
			region.SeedY
		)
	] = true

	while queueIndex <= #queue do
		local current =
			queue[queueIndex]

		queueIndex += 1
		connectedCount += 1

		for _, direction
			in ipairs(
				CARDINAL_DIRECTIONS
			) do
			local neighborX =
				current.x + direction.x

			local neighborY =
				current.y + direction.y

			if isInsideGrid(
				neighborX,
				neighborY,
				width,
				height
			) then
				local key =
					getCoordinateKey(
						neighborX,
						neighborY
					)

				if not visited[key]
					and grid[neighborY][neighborX]
						== region.Id then
					visited[key] = true

					table.insert(
						queue,
						{
							x = neighborX,
							y = neighborY,
						}
					)
				end
			end
		end
	end

	return connectedCount
end

local function validateGeneratedRegions(
	grid,
	regions,
	width,
	height,
	minimumTileCount
)
	local countedTilesByRegion = {}

	for _, region in ipairs(regions) do
		countedTilesByRegion[region.Id] = 0
	end

	for y = 1, height do
		for x = 1, width do
			local regionId = grid[y][x]

			if regionId == nil then
				return false,
					string.format(
						"Tile (%d, %d) is unassigned.",
						x,
						y
					)
			end

			if countedTilesByRegion[regionId]
				== nil then
				return false,
					string.format(
						'Unknown Region ID "%s".',
						tostring(regionId)
					)
			end

			countedTilesByRegion[regionId] += 1
		end
	end

	for _, region in ipairs(regions) do
		local countedTileCount =
			countedTilesByRegion[region.Id]

		if countedTileCount
			~= region.TileCount then
			return false,
				region.Id
				.. " metadata count mismatch."
		end

		if region.TileCount
			< minimumTileCount then
			return false,
				string.format(
					"%s has %d tiles; minimum is %d.",
					region.Id,
					region.TileCount,
					minimumTileCount
				)
		end

		local connectedTileCount =
			countConnectedTiles(
				grid,
				region,
				width,
				height
			)

		if connectedTileCount
			~= region.TileCount then
			return false,
				region.Id
				.. " is not cardinally connected."
		end
	end

	return true, nil
end

--------------------------------------------------
-- ONE COMPLETE GENERATION ATTEMPT
--------------------------------------------------

local function tryGenerate(
	width,
	height,
	regions,
	minimumTileCount,
	random
)
	local grid =
		createGrid(width, height)

	local seedsPlaced =
		placeSeeds(
			grid,
			regions,
			width,
			height,
			random
		)

	if not seedsPlaced then
		return nil,
			"Seed placement failed."
	end

	local minimumGrowthSucceeded,
		minimumFailureReason =
		growRegionsToMinimum(
			grid,
			regions,
			width,
			height,
			minimumTileCount,
			random
		)

	if not minimumGrowthSucceeded then
		return nil, minimumFailureReason
	end

	local remainingGrowthSucceeded,
		remainingFailureReason =
		growRemainingTiles(
			grid,
			regions,
			width,
			height,
			random
		)

	if not remainingGrowthSucceeded then
		return nil, remainingFailureReason
	end

	local valid, validationReason =
		validateGeneratedRegions(
			grid,
			regions,
			width,
			height,
			minimumTileCount
		)

	if not valid then
		return nil, validationReason
	end

	return grid, nil
end

--------------------------------------------------
-- PUBLIC API
--------------------------------------------------

function RegionGenerator.Generate(config)
	assert(
		type(config) == "table",
		"RegionGenerator.Generate requires a config table."
	)

	local width = config.Width
	local height = config.Height

	local biomeId =
		config.BiomeId
		or DEFAULT_BIOME_ID

	local regionCount =
		config.RegionCount
		or DEFAULT_REGION_COUNT

	local minimumRegionPercent =
		config.MinimumRegionPercent
		or DEFAULT_MINIMUM_REGION_PERCENT

	local maximumGenerationAttempts =
		config.MaximumGenerationAttempts
		or DEFAULT_MAXIMUM_GENERATION_ATTEMPTS

	local seed = config.Seed

	assertPositiveInteger(width, "Width")
	assertPositiveInteger(height, "Height")

	assertPositiveInteger(
		regionCount,
		"RegionCount"
	)

	assertPositiveInteger(
		maximumGenerationAttempts,
		"MaximumGenerationAttempts"
	)

	assert(
		type(biomeId) == "string"
			and biomeId ~= "",
		"BiomeId must be a non-empty string."
	)

	assert(
		type(minimumRegionPercent)
			== "number"
			and minimumRegionPercent > 0
			and minimumRegionPercent <= 1,
		"MinimumRegionPercent must be greater than 0 and no more than 1."
	)

	assert(
		regionCount
			* minimumRegionPercent <= 1,
		"Combined minimum region percentages cannot exceed 100%."
	)

	if seed ~= nil then
		assert(
			type(seed) == "number",
			"Seed must be a number when provided."
		)
	end

	local totalTileCount =
		width * height

	local minimumTileCount =
		math.ceil(
			totalTileCount
				* minimumRegionPercent
		)

	assert(
		minimumTileCount * regionCount
			<= totalTileCount,
		"Minimum region sizes exceed the total tile count."
	)

	local random

	if seed ~= nil then
		random = Random.new(seed)
	else
		random = Random.new()
	end

	local lastFailureReason = "Unknown failure."

	for generationAttempt = 1,
		maximumGenerationAttempts do
		local regions =
			createRegions(
				regionCount,
				biomeId,
				minimumTileCount
			)

		local grid, failureReason =
			tryGenerate(
				width,
				height,
				regions,
				minimumTileCount,
				random
			)

		if grid ~= nil then
			return {
				Width = width,
				Height = height,
				BiomeId = biomeId,
				Seed = seed,

				GenerationAttempt =
					generationAttempt,

				RegionCount =
					regionCount,

				MinimumRegionPercent =
					minimumRegionPercent,

				MinimumRegionTileCount =
					minimumTileCount,

				Grid = grid,
				Regions = regions,
			}
		end

		lastFailureReason = failureReason
	end

	error(
		string.format(
			"Region generation failed after %d attempts. Last failure: %s",
			maximumGenerationAttempts,
			tostring(lastFailureReason)
		)
	)
end

return RegionGenerator