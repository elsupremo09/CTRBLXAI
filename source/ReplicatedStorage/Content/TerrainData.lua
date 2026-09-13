-- TerrainData.lua
-- CTRBLXAI | Slice 5 -- Procedural Map Generation
--
-- Generated from CTRBLXAI.db terrain_effects table.
-- Replaces the minimal TileDefinitions.lua with full terrain data.
-- DO NOT EDIT MANUALLY -- regenerate from DB if rules change.

local TerrainData = {}

-- ─────────────────────────────────────────────
-- TERRAIN TYPES (19)
-- ─────────────────────────────────────────────

TerrainData.Types = {}

TerrainData.Types["Clear"] = {
	id = "Clear",
	description = "Neutral ground",
	tags = { "Solid", "Natural" },
	moveCost = 1,
	crossCost = 0,
	occupyEffect = nil,
	crossEffect = nil,
	triggerEffect = nil,
	transformations = {},
	passable = true,
}

TerrainData.Types["Grassland"] = {
	id = "Grassland",
	description = "Fertile field",
	tags = { "Solid", "Organic", "Flammable", "Blessed" },
	moveCost = 1,
	crossCost = 0,
	occupyEffect = "Holy +15%",
	crossEffect = nil,
	triggerEffect = nil,
	transformations = {
		Fire = "Sand",
		Dark = "Tainted",
	},
	passable = true,
}

TerrainData.Types["Clover Field"] = {
	id = "Clover Field",
	description = "Lucky meadow",
	tags = { "Solid", "Organic", "Flammable", "Blessed", "Lucky" },
	moveCost = 1,
	crossCost = 0,
	occupyEffect = "LUK +30%",
	crossEffect = nil,
	triggerEffect = nil,
	transformations = {
		Fire = "Sand",
		Dark = "Tainted",
	},
	passable = true,
}

TerrainData.Types["Wooden Floor"] = {
	id = "Wooden Floor",
	description = "Wooden structures and bridges",
	tags = { "Solid", "Organic", "Flammable" },
	moveCost = 1,
	crossCost = 0,
	occupyEffect = nil,
	crossEffect = nil,
	triggerEffect = nil,
	transformations = {
		Fire = "Clear",
	},
	passable = true,
}

TerrainData.Types["Rocky"] = {
	id = "Rocky",
	description = "Solid stone terrain",
	tags = { "Solid", "Stone", "Stable", "Earth" },
	moveCost = 1,
	crossCost = 0,
	occupyEffect = "Earth +30%",
	crossEffect = nil,
	triggerEffect = "Knockback Immunity",
	transformations = {
		Explosion = "Cracked Ground",
	},
	passable = true,
}

TerrainData.Types["Sand"] = {
	id = "Sand",
	description = "Loose desert ground",
	tags = { "Solid", "Loose", "Earth" },
	moveCost = 1,
	crossCost = 1,
	occupyEffect = "Earth +15%",
	crossEffect = "+1 Move Cost",
	triggerEffect = nil,
	transformations = {
		Fire = "Molten",
	},
	passable = true,
}

TerrainData.Types["Mud"] = {
	id = "Mud",
	description = "Soft muddy ground",
	tags = { "Liquid", "Soft", "Conductive", "Earth", "Sticky" },
	moveCost = 1,
	crossCost = 1,
	occupyEffect = "Earth & Water +15%",
	crossEffect = "+1 Move Cost",
	triggerEffect = nil,
	transformations = {
		Fire = "Rocky",
	},
	passable = true,
}

TerrainData.Types["Swamp"] = {
	id = "Swamp",
	description = "Marshland",
	tags = { "Liquid", "Organic", "Sticky", "Water", "Dark" },
	moveCost = 1,
	crossCost = 2,
	occupyEffect = "Water & Dark +15%",
	crossEffect = "+2 Move Cost",
	triggerEffect = nil,
	transformations = {
		Fire = "Rocky",
	},
	passable = true,
}

TerrainData.Types["Shallow Water"] = {
	id = "Shallow Water",
	description = "Walkable water",
	tags = { "Liquid", "Conductive", "Water" },
	moveCost = 1,
	crossCost = 1,
	occupyEffect = "Water +25%",
	crossEffect = "+1 Move Cost",
	triggerEffect = nil,
	transformations = {
		Ice = "Ice Terrain",
		Earth = "Mud",
	},
	passable = true,
}

TerrainData.Types["Deep Water"] = {
	id = "Deep Water",
	description = "Deep water",
	tags = { "Liquid", "Conductive", "Water", "Deep" },
	moveCost = 1,
	crossCost = 2,
	occupyEffect = "Water +30%",
	crossEffect = "+2 Move Cost",
	triggerEffect = "Apply Drowning",
	transformations = {
		Ice = "Ice Terrain",
	},
	passable = true,
}

TerrainData.Types["Ice"] = {
	id = "Ice",
	description = "Frozen water surface",
	tags = { "Solid", "Frozen", "Slippery", "Water" },
	moveCost = 1,
	crossCost = 0,
	occupyEffect = "Water +25%",
	crossEffect = "Sliding Knockback",
	triggerEffect = nil,
	transformations = {
		Fire = "Shallow Water",
	},
	passable = true,
}

TerrainData.Types["Metal"] = {
	id = "Metal",
	description = "Metallic flooring",
	tags = { "Solid", "Metal", "Conductive" },
	moveCost = 1,
	crossCost = 0,
	occupyEffect = nil,
	crossEffect = nil,
	triggerEffect = nil,
	transformations = {
		Fire = "Molten",
	},
	passable = true,
}

TerrainData.Types["Molten"] = {
	id = "Molten",
	description = "Molten metal or sand",
	tags = { "Liquid", "Molten", "Fire", "Hazard" },
	moveCost = 1,
	crossCost = 0,
	occupyEffect = "Fire +30%",
	crossEffect = nil,
	triggerEffect = "End Turn: Burn +25% Max HP",
	transformations = {
		Water = "Rocky",
	},
	passable = true,
}

TerrainData.Types["Magic Circle"] = {
	id = "Magic Circle",
	description = "Arcane platform",
	tags = { "Solid", "Arcane" },
	moveCost = 1,
	crossCost = 0,
	occupyEffect = "INT +30%; Spell Range +1; +20% damage from spell damage",
	crossEffect = nil,
	triggerEffect = nil,
	transformations = {
		Dark = "Tainted",
	},
	passable = true,
}

TerrainData.Types["Tainted Ground"] = {
	id = "Tainted Ground",
	description = "Corrupted earth",
	tags = { "Solid", "Corrupted", "Dark" },
	moveCost = 1,
	crossCost = 0,
	occupyEffect = "Non-undead lose 10% Max MP at start of turn; Undead/Demons restore 10% Max MP instead.",
	crossEffect = nil,
	triggerEffect = nil,
	transformations = {
		Light = "Grassland",
	},
	passable = true,
}

TerrainData.Types["Cracked Ground"] = {
	id = "Cracked Ground",
	description = "Structurally weakened rock",
	tags = { "Solid", "Fragile" },
	moveCost = 1,
	crossCost = 0,
	occupyEffect = nil,
	crossEffect = nil,
	triggerEffect = "Explosion or Unit WT >15 -> Collapse",
	transformations = {
		Collapse = "Rocky (-3 Elevation, +50 RT Delay)",
	},
	passable = true,
}

TerrainData.Types["Quicksand"] = {
	id = "Quicksand",
	description = "Collapsing sand",
	tags = { "Loose", "Hazard", "Sticky" },
	moveCost = 1,
	crossCost = -1,
	occupyEffect = nil,
	crossEffect = "Movement prohibited",
	triggerEffect = "Apply Sinking",
	transformations = {
		Water = "Mud",
	},
	passable = false,
}

TerrainData.Types["Monolith (One-way)"] = {
	id = "Monolith (One-way)",
	description = "Ancient teleport",
	tags = { "Solid", "Portal" },
	moveCost = 1,
	crossCost = 0,
	occupyEffect = nil,
	crossEffect = nil,
	triggerEffect = "End Turn -> Random teleport",
	transformations = {},
	passable = true,
}

TerrainData.Types["Monolith (Two-way)"] = {
	id = "Monolith (Two-way)",
	description = "Linked portal",
	tags = { "Solid", "Portal" },
	moveCost = 1,
	crossCost = 0,
	occupyEffect = nil,
	crossEffect = "End Move -> Paired portal",
	triggerEffect = nil,
	transformations = {},
	passable = true,
}

-- ─────────────────────────────────────────────
-- TILE EFFECTS (9)
-- ─────────────────────────────────────────────

TerrainData.Effects = {}

TerrainData.Effects["Burning"] = {
	id = "Burning",
	description = "Tile engulfed in flames. Spreads to adjacent Flammable terrain within ±1 elevation every 500 CT.",
	tags = { "Fire", "Hazard" },
	occupyEffect = "Inflict Burn",
	crossEffect = "Inflict Burn",
	triggerEffect = "Every 300 CT: Deal 15% Max HP Fire Damage to occupying unit.",
	duration = 900,
	elementReactions = {
		Water = "Steam",
	},
	notes = "After reaction resolution, spread is optional.",
}

TerrainData.Effects["Wet"] = {
	id = "Wet",
	description = "Surface covered in water.",
	tags = { "Water", "Conductive" },
	occupyEffect = "Water Skills +25%",
	crossEffect = nil,
	triggerEffect = "Conducts Electric attacks.",
	duration = 1500,
	elementReactions = {
		Fire = "Steam",
		Ice = "Frozen",
	},
	notes = nil,
}

TerrainData.Effects["Steam"] = {
	id = "Steam",
	description = "Hot vapor obscures vision.",
	tags = { "Airborne", "Conductive" },
	occupyEffect = "+25% Evasion; Water Skills +25%",
	crossEffect = nil,
	triggerEffect = "Conducts Electric attacks.",
	duration = 900,
	elementReactions = {
		Electric = "Static Cloud",
		Wind = "Clear",
	},
	notes = "Replaces Fog.",
}

TerrainData.Effects["Static Cloud"] = {
	id = "Static Cloud",
	description = "Electrically charged air.",
	tags = { "Airborne", "Conductive", "Electric" },
	occupyEffect = nil,
	crossEffect = nil,
	triggerEffect = "Every 300 CT: Deal 15% Max HP Light Damage to occupying unit.",
	duration = 900,
	elementReactions = {
		Wind = "Clear",
	},
	notes = nil,
}

TerrainData.Effects["Poison Cloud"] = {
	id = "Poison Cloud",
	description = "Toxic airborne gas.",
	tags = { "Airborne", "Poison" },
	occupyEffect = "Inflict Poison",
	crossEffect = "Inflict Poison",
	triggerEffect = nil,
	duration = 1500,
	elementReactions = {
		Fire = "Explosion",
	},
	notes = "Explosion damage reduced if triggered by another explosion.",
}

TerrainData.Effects["Oily"] = {
	id = "Oily",
	description = "Ground coated in oil.",
	tags = { "Flammable", "Slippery" },
	occupyEffect = "Knockback continues until first non-Oily/non-Ice tile.",
	crossEffect = nil,
	triggerEffect = nil,
	duration = -1,
	elementReactions = {
		Fire = "Explosion",
	},
	notes = "Removed after exploding.",
}

TerrainData.Effects["Tar Pit"] = {
	id = "Tar Pit",
	description = "Thick sticky tar.",
	tags = { "Sticky" },
	occupyEffect = nil,
	crossEffect = "+2 Move Cost",
	triggerEffect = "Unit ending two consecutive turns on Tar Pit becomes Petrified.",
	duration = -1,
	elementReactions = {
		Fire = "Burning",
	},
	notes = nil,
}

TerrainData.Effects["Vines"] = {
	id = "Vines",
	description = "Living roots entangle movement.",
	tags = { "Organic" },
	occupyEffect = "Inflict Pinned",
	crossEffect = "Inflict Pinned",
	triggerEffect = nil,
	duration = -1,
	elementReactions = {
		Fire = "Burning",
	},
	notes = "Cannot exist on incompatible terrain.",
}

TerrainData.Effects["Frozen"] = {
	id = "Frozen",
	description = "Surface frozen solid.",
	tags = { "Frozen", "Slippery" },
	occupyEffect = "Water Skills +25%; Fire Damage Received -50%",
	crossEffect = "Sliding Knockback",
	triggerEffect = nil,
	duration = 900,
	elementReactions = {
		Fire = "Wet",
	},
	notes = "Created by Ice-tag attacks against Wet.",
}

-- ─────────────────────────────────────────────
-- TEMPLATE MARKER COLORS (from TileDefinitions)
-- ─────────────────────────────────────────────

TerrainData.MarkerColors = {
	PD  = Color3.fromRGB(112, 173, 71),
	ED  = Color3.fromRGB(192, 0, 0),
	LAN = Color3.fromRGB(166, 166, 166),
	POI = Color3.fromRGB(91, 155, 213),
	ADV = Color3.fromRGB(169, 209, 142),
	HZD = Color3.fromRGB(112, 48, 160),
	BLK = Color3.fromRGB(64, 64, 64),
	WAT = Color3.fromRGB(0, 112, 192),
	NEU = Color3.fromRGB(255, 255, 255),
}

-- ─────────────────────────────────────────────
-- PASSABILITY CHECK
-- ─────────────────────────────────────────────

function TerrainData.IsPassable(terrainId)
	local t = TerrainData.Types[terrainId]
	if not t then return true end
	return t.passable
end

function TerrainData.GetMoveCost(terrainId)
	local t = TerrainData.Types[terrainId]
	if not t then return 1 end
	return t.moveCost + math.max(0, t.crossCost)
end

return TerrainData