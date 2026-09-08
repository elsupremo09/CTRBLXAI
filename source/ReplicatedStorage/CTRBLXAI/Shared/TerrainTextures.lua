-- TerrainTextures.lua
-- CTRBLXAI | Terrain tile texture assets and variation system
-- Maps terrain type names to uploaded image asset IDs.
-- Used by TemplateViewer to apply visual textures to battle tiles.

local TerrainTextures = {}

-- Terrain name -> Roblox asset ID
TerrainTextures.Assets = {
	["Clear"] = "rbxassetid://101103754010603",
	["Clover Field"] = "rbxassetid://79830618175491",
	["Cracked Ground"] = "rbxassetid://81265895230000",
	["Deep Water"] = "rbxassetid://82736814484402",
	["Grassland"] = "rbxassetid://121141972308329",
	["Ice"] = "rbxassetid://73357387466669",
	["Magic Circle"] = "rbxassetid://108617298184427",
	["Metal"] = "rbxassetid://132523139310494",
	["Molten"] = "rbxassetid://74100663925880",
	["Monolith (One-way)"] = "rbxassetid://129183515543029",
	["Monolith (Two-way)"] = "rbxassetid://133650804303627",
	["Quicksand"] = "rbxassetid://81752574851159",
	["Rocky"] = "rbxassetid://130533342596449",
	["Sand"] = "rbxassetid://71032378624781",
	["Shallow Water"] = "rbxassetid://130567999746801",
	["Tainted Ground"] = "rbxassetid://75058268033334",
	["Wooden Floor"] = "rbxassetid://126018504938337",
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
-- Creates a SurfaceGui on the top face with an ImageLabel.
-- Randomly picks 0/90/180/270 rotation + optional horizontal flip.
-- @param tilePart: the Part instance
-- @param terrainName: string terrain type (e.g. "Grassland")
function TerrainTextures.Apply(tilePart, terrainName)
	local assetId = TerrainTextures.Assets[terrainName]
	if not assetId then return end

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
end

return TerrainTextures
