-- TerrainTextures.lua
-- CTRBLXAI | Terrain tile texture assets and variation system
-- Maps terrain type names to uploaded image asset IDs.
-- Used by TemplateViewer to apply visual textures to battle tiles.

local TerrainTextures = {}

-- Terrain name -> Roblox asset ID
TerrainTextures.Assets = {
	["Clear"] = "rbxassetid://109805975558014",
	["Clover Field"] = "rbxassetid://109662805904614",
	["Cracked Ground"] = "rbxassetid://112911396208647",
	["Deep Water"] = "rbxassetid://91104299895108",
	["Dirt Road"] = "rbxassetid://70967889930713",
	["Forest"] = "rbxassetid://135752092589962",
	["Grassland"] = "rbxassetid://128007269403177",
	["Ice"] = "rbxassetid://111074337572921",
	["Magic Circle"] = "rbxassetid://83344810206782",
	["Metal"] = "rbxassetid://109801126120884",
	["Molten"] = "rbxassetid://102728788006487",
	["Monolith (One-way)"] = "rbxassetid://129183515543029",
	["Monolith (Two-way)"] = "rbxassetid://133650804303627",
	["Mud"] = "rbxassetid://103981896145024",
	["Quicksand"] = "rbxassetid://125706353174532",
	["Rocky"] = "rbxassetid://90522759746156",
	["Sand"] = "rbxassetid://130402247622009",
	["Shallow Water"] = "rbxassetid://133104312443373",
	["Stone Road"] = "rbxassetid://91078246561441",
	["Swamp"] = "rbxassetid://102784702693557",
	["Tainted Ground"] = "rbxassetid://78418011585017",
	["Wooden Floor"] = "rbxassetid://126612632552137",
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
