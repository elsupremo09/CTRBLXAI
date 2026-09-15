-- FloorPass.lua
-- CTRBLXAI | Feature Coherence System — Round 1
--
-- Assigns floor terrain to each tile based on its region type.
-- Every tile in a region gets the same base terrain,
-- producing visually uniform regions (no random scatter).
--
-- PD/ED/LAN tiles are marked protected so later passes
-- (FeaturePass, TransitionPass) cannot overwrite them.
--
-- Location: ServerScriptService/Game/FloorPass.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Content     = ReplicatedStorage:WaitForChild("Content")
local TerrainData = require(Content:WaitForChild("TerrainData"))

local FloorPass = {}

--------------------------------------------------
-- FLOOR TERRAIN PER REGION TYPE
-- Each region type maps to exactly one terrain.
-- This is the base layer — FeaturePass (Round 2)
-- overrides specific tiles within a region.
--------------------------------------------------

local FLOOR_TERRAIN = {
	["Grassland"]        = "Grassland",
	["Farmland"]         = "Clear",
	["Village"]          = "Clear",
	["Forest"]           = "Grassland",
	["Clearing"]         = "Clear",
	["Rocky"]            = "Rocky",
	["Mountain Pass"]    = "Rocky",
	["Riverbank"]        = "Grassland",
	["Marsh"]            = "Mud",
	["Frozen Lake"]      = "Ice",
	["Volcanic Rock"]    = "Rocky",
	["Lava Channel"]     = "Rocky",
	["Ruins"]            = "Clear",
	["Castle Courtyard"] = "Rocky",
	["Castle Interior"]  = "Metal",
	["Graveyard"]        = "Grassland",
	["Corrupted"]        = "Tainted Ground",
	["Beach"]            = "Sand",
	["Dock"]             = "Wooden Floor",
	["Cave Chamber"]     = "Rocky",
}

local DEFAULT_FLOOR = "Clear"

local YIELD_INTERVAL = 100

--------------------------------------------------
-- RUN
--------------------------------------------------

--- Assign floor terrain and protection flags to every tile.
--- @param mapState table — the shared pipeline state
--- @return mapState (modified in-place)
function FloorPass.Run(mapState)
	local tiles         = mapState.tiles
	local w             = mapState.width
	local h             = mapState.height
	local regionTypeMap = mapState.regionTypeMap

	local ops = 0

	for y = 1, h do
		for x = 1, w do
			local tile     = tiles[y][x]
			local regionId = tile.regionId

			-- Look up region type → floor terrain.
			local regionTypeName = regionTypeMap[regionId]
			local terrain        = FLOOR_TERRAIN[regionTypeName] or DEFAULT_FLOOR

			-- Defensive: if the floor terrain is impassable and
			-- the marker requires passable terrain, fall back.
			local marker = tile.marker
			if marker == "PD" or marker == "ED" or marker == "LAN" then
				local tDef = TerrainData.Types[terrain]
				if not tDef or tDef.passable == false then
					terrain = DEFAULT_FLOOR
				end
			end

			tile.terrain = terrain

			-- Mark protected tiles (features cannot overwrite later).
			if marker == "PD" or marker == "ED" or marker == "LAN" then
				tile.protected = true
			end

			ops = ops + 1
			if ops % YIELD_INTERVAL == 0 then task.wait() end
		end
	end

	return mapState
end

return FloorPass
