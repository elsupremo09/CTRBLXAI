-- TerrainTextures.lua
-- CTRBLXAI | Terrain tile texture assets and variation system
-- Maps terrain type names to uploaded image asset IDs.
-- Used by TemplateViewer to apply visual textures to battle tiles.

local TerrainTextures = {}

-- Grid-edge line (painted on per-tile top-face SurfaceGuis; see Apply).
TerrainTextures.GridColor = Color3.fromRGB(20, 20, 20)
TerrainTextures.GridThicknessPx = 2  -- SurfaceGui pixels (PixelsPerStud=50); tune for thinner/thicker

-- Terrain name -> Roblox asset ID
TerrainTextures.Assets = {
	["Clear"] = "rbxassetid://74692826345872",
	["Clover Field"] = "rbxassetid://86809605502149",
	["Cracked Ground"] = "rbxassetid://80266846327057",
	["Deep Water"] = "rbxassetid://138905752952965",
	["Dirt Road"] = "rbxassetid://74896495319547",
	["Forest"] = "rbxassetid://92048265218097",
	["Grassland"] = "rbxassetid://89238035189625",
	["Ice"] = "rbxassetid://93574916698714",
	["Magic Circle"] = "rbxassetid://96217583623367",
	["Metal"] = "rbxassetid://106647711046909",
	["Molten"] = "rbxassetid://120698732334060",
	["Monolith (One-way)"] = "rbxassetid://129183515543029",
	["Monolith (Two-way)"] = "rbxassetid://85412334030197",
	["Mud"] = "rbxassetid://97058803836850",
	["Quicksand"] = "rbxassetid://103522632282664",
	["Rocky"] = "rbxassetid://86134990751716",
	["Sand"] = "rbxassetid://105434745636051",
	["Shallow Water"] = "rbxassetid://111962301136930",
	["Stone Road"] = "rbxassetid://105323659190313",
	["Swamp"] = "rbxassetid://82636405695018",
	["Tainted Ground"] = "rbxassetid://90980399497254",
	["Wooden Floor"] = "rbxassetid://72918745499013",
}

-- Terrains that should NOT be randomly rotated (directional textures)
TerrainTextures.NoRotate = {
	["Monolith (One-way)"] = true,
	["Monolith (Two-way)"] = true,
	["Magic Circle"] = true,
}

-- Terrains that should NOT be randomly flipped (asymmetric)
TerrainTextures.NoFlip = {
	["Monolith (One-way)"] = true,
	["Monolith (Two-way)"] = true,
	["Magic Circle"] = true,
}

--- Apply a terrain texture to a tile Part with random variation.
-- Creates SurfaceGuis on top + 4 side faces.
-- Top: full-color texture with random rotation/flip.
-- Sides: same texture, darkened (60% brightness), no rotation.
-- @param tilePart: the Part instance
-- @param terrainName: string terrain type (e.g. "Grassland")
function TerrainTextures.Apply(tilePart, terrainName)
	local assetId = TerrainTextures.Assets[terrainName]
	if not assetId then return end

	-- Remove studs from tile
	tilePart.Material = Enum.Material.SmoothPlastic

	-- Random rotation: 0, 90, 180, 270
	local rotation = 0
	if not TerrainTextures.NoRotate[terrainName] then
		local rotChoices = {0, 90, 180, 270}
		rotation = rotChoices[math.random(1, 4)]
	end

	-- Random horizontal flip
	local flipX = false
	if not TerrainTextures.NoFlip[terrainName] then
		flipX = math.random() > 0.5
	end

	-- Create SurfaceGui on top face
	local gui = Instance.new("SurfaceGui")
	gui.Name = "TerrainTexture"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.Brightness = 1
	gui.LightInfluence = 1
	gui.ResetOnSpawn = false
	gui.Parent = tilePart

	local img = Instance.new("ImageLabel")
	img.Name = "TerrainImage"
	img.Size = UDim2.fromScale(1, 1)
	img.Position = UDim2.fromScale(0.5, 0.5)
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.BackgroundTransparency = 1
	img.Image = assetId
	img.ScaleType = Enum.ScaleType.Stretch
	img.Rotation = rotation
	img.Parent = gui

	-- Apply horizontal flip via negative scale
	if flipX then
		img.Size = UDim2.new(-1, 0, 1, 0)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.AnchorPoint = Vector2.new(0.5, 0.5)
	end

	-- GRID EDGE LINE: a black border traced on the tile's top face via a UIStroke.
	-- Because it lives on the top-face SurfaceGui, it sits exactly on the tile top and
	-- tilts with the tile's elevation — 'painted on the edges'. Voxel tiles (grass/
	-- water) never call Apply, so they get no grid, as intended. Separate from the
	-- image frame so the random rotation/flip of the texture does not affect it.
	local gridFrame = Instance.new("Frame")
	gridFrame.Name = "GridEdge"
	gridFrame.Size = UDim2.fromScale(1, 1)
	gridFrame.Position = UDim2.fromScale(0.5, 0.5)
	gridFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	gridFrame.BackgroundTransparency = 1
	gridFrame.BorderSizePixel = 0
	gridFrame.ZIndex = 5
	gridFrame.Parent = gui
	local gridStroke = Instance.new("UIStroke")
	gridStroke.Name = "GridStroke"
	gridStroke.Color = TerrainTextures.GridColor
	gridStroke.Thickness = TerrainTextures.GridThicknessPx
	gridStroke.Transparency = 0
	gridStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	gridStroke.Parent = gridFrame

	-- Side faces: same texture, darkened
	local SIDE_TINT = Color3.fromRGB(140, 140, 140) -- ~55% brightness
	local sideFaces = {
		Enum.NormalId.Front, Enum.NormalId.Back,
		Enum.NormalId.Left, Enum.NormalId.Right,
	}
	for _, face in ipairs(sideFaces) do
		local sGui = Instance.new("SurfaceGui")
		sGui.Name = "SideTexture_" .. face.Name
		sGui.Face = face
		sGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sGui.PixelsPerStud = 50
		sGui.Brightness = 1
		sGui.LightInfluence = 1
		sGui.ResetOnSpawn = false
		sGui.Parent = tilePart

		local sImg = Instance.new("ImageLabel")
		sImg.Name = "SideImage"
		sImg.Size = UDim2.fromScale(1, 1)
		sImg.BackgroundTransparency = 1
		sImg.Image = assetId
		sImg.ScaleType = Enum.ScaleType.Crop
		sImg.ImageColor3 = SIDE_TINT
		sImg.Parent = sGui
	end
end
return TerrainTextures