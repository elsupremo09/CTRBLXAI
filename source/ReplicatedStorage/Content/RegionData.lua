-- RegionData.lua
-- CTRBLXAI | Slice 5 -- Procedural Map Generation
--
-- Generated from CTRBLXAI.db regions table.
-- DO NOT EDIT MANUALLY -- regenerate from DB if rules change.

local RegionData = {}

RegionData["Grassland"] = {
	id = "Grassland",
	identity = "Open natural field",
	minSize = 20,
	maxSize = 250,
	terrainWeights = {
		Grassland = 55,
		Clear = 25,
		["Clover Field"] = 5,
		Mud = 5,
		Rocky = 5,
		["Shallow Water"] = 5,
	},
	objectWeights = {
		["Treasure Chest"] = 3,
		Campfire = 2,
		["Rally Flag"] = 1,
	},
	hazardWeights = {
		Burning = 2,
		Vines = 1,
	},
	poiTypes = { "Campfire", "Chest", "Rally Flag" },
	specialRules = "Good baseline region.",
}

RegionData["Farmland"] = {
	id = "Farmland",
	identity = "Rural cultivated land",
	minSize = 20,
	maxSize = 160,
	terrainWeights = {
		Grassland = 35,
		Clear = 30,
		Road = 15,
		["Wooden Floor"] = 5,
		Mud = 10,
		["Shallow Water"] = 5,
	},
	objectWeights = {
		Fence = 20,
		Cart = 10,
		House = 5,
		Campfire = 5,
		Chest = 3,
	},
	hazardWeights = {
		Burning = 2,
		["Bear Trap"] = 1,
	},
	poiTypes = { "Chest", "Trading Post", "Campfire" },
	specialRules = "Needs simple object substitutions in Roblox if non-catalog objects are missing.",
}

RegionData["Village"] = {
	id = "Village",
	identity = "Settlement cluster",
	minSize = 25,
	maxSize = 160,
	terrainWeights = {
		Clear = 35,
		Rocky = 20,
		["Wooden Floor"] = 20,
		Grassland = 15,
		Mud = 5,
		Metal = 5,
	},
	objectWeights = {
		House = 25,
		Fence = 15,
		["Black Market"] = 3,
		["Trading Post"] = 5,
		Tavern = 4,
		Scholar = 2,
		Chest = 3,
	},
	hazardWeights = {
		Burning = 2,
		Oily = 1,
	},
	poiTypes = { "Black Market", "Trading Post", "Tavern", "Scholar", "Chest" },
	specialRules = "Objects occupy tiles. NPC/merchant represented as objects.",
}

RegionData["Forest"] = {
	id = "Forest",
	identity = "Dense woods and clearings",
	minSize = 30,
	maxSize = 220,
	terrainWeights = {
		Grassland = 35,
		Clear = 20,
		Mud = 10,
		Rocky = 10,
		["Clover Field"] = 5,
		["Shallow Water"] = 5,
		["Forest Floor"] = 15,
	},
	objectWeights = {
		Tree = 45,
		["Fallen Log"] = 10,
		Chest = 4,
		["Witch Hut"] = 2,
		Campfire = 3,
	},
	hazardWeights = {
		["Bear Trap"] = 5,
		["Snare Trap"] = 4,
		Vines = 5,
		Burning = 1,
	},
	poiTypes = { "Witch Hut", "Campfire", "Chest", "Healing Spring" },
	specialRules = "LAN validation prevents total blockage in required lanes.",
}

RegionData["Clearing"] = {
	id = "Clearing",
	identity = "Open pocket inside forest",
	minSize = 10,
	maxSize = 80,
	terrainWeights = {
		Clear = 35,
		Grassland = 35,
		["Clover Field"] = 10,
		Mud = 10,
		Rocky = 5,
		["Shallow Water"] = 5,
	},
	objectWeights = {
		Campfire = 5,
		Chest = 5,
		["Healing Spring"] = 2,
		Scholar = 1,
	},
	hazardWeights = {
		Vines = 2,
		["Bear Trap"] = 1,
	},
	poiTypes = { "Campfire", "Chest", "Healing Spring" },
	specialRules = "Useful transition region.",
}

RegionData["Rocky"] = {
	id = "Rocky",
	identity = "Stone-heavy outcrop",
	minSize = 20,
	maxSize = 220,
	terrainWeights = {
		Rocky = 50,
		["Cracked Ground"] = 15,
		Clear = 15,
		Mud = 5,
		Sand = 5,
		Grassland = 10,
	},
	objectWeights = {
		["Stone Pillar"] = 8,
		Boulder = 20,
		Ballista = 2,
		Chest = 3,
	},
	hazardWeights = {
		["Cracked Ground"] = 5,
		["Earthquake Mark"] = 2,
	},
	poiTypes = { "Chest", "Stone Pillar", "Ballista" },
	specialRules = "Highlands/ruins core region.",
}

RegionData["Mountain Pass"] = {
	id = "Mountain Pass",
	identity = "Ridge/pass area",
	minSize = 20,
	maxSize = 180,
	terrainWeights = {
		Rocky = 45,
		Clear = 20,
		["Cracked Ground"] = 15,
		Grassland = 10,
		Mud = 5,
		Sand = 5,
	},
	objectWeights = {
		["Stone Pillar"] = 10,
		Bridge = 5,
		["War Banner"] = 2,
		Chest = 3,
	},
	hazardWeights = {
		["Cliff Edge"] = 8,
		["Cracked Ground"] = 6,
	},
	poiTypes = { "Watchtower", "Chest", "War Banner" },
	specialRules = "Likely uses LAN heavily to ensure traversal.",
}

RegionData["Riverbank"] = {
	id = "Riverbank",
	identity = "Water edge and crossing support",
	minSize = 15,
	maxSize = 160,
	terrainWeights = {
		["Shallow Water"] = 25,
		["Deep Water"] = 10,
		Mud = 20,
		Grassland = 20,
		Clear = 15,
		Rocky = 10,
	},
	objectWeights = {
		Bridge = 8,
		Chest = 3,
		Campfire = 2,
		["Healing Spring"] = 1,
	},
	hazardWeights = {
		Wet = 10,
		["Tar Pit"] = 1,
	},
	poiTypes = { "Bridge", "Chest", "Healing Spring" },
	specialRules = "Water systems should be coherent.",
}

RegionData["Marsh"] = {
	id = "Marsh",
	identity = "Swamp/wet ground region",
	minSize = 20,
	maxSize = 200,
	terrainWeights = {
		Swamp = 35,
		Mud = 25,
		["Shallow Water"] = 20,
		Grassland = 10,
		Rocky = 10,
	},
	objectWeights = {
		["Bear Trap"] = 4,
		["Snare Trap"] = 4,
		["Witch Hut"] = 2,
		["Cursed Statue"] = 1,
	},
	hazardWeights = {
		Wet = 10,
		["Poison Cloud"] = 3,
		Vines = 3,
	},
	poiTypes = { "Witch Hut", "Cursed Statue", "Chest" },
	specialRules = "Poor mobility expected outside required LAN.",
}

RegionData["Frozen Lake"] = {
	id = "Frozen Lake",
	identity = "Frozen/wet tundra feature",
	minSize = 20,
	maxSize = 220,
	terrainWeights = {
		Ice = 45,
		["Shallow Water"] = 20,
		Rocky = 15,
		Clear = 10,
		Grassland = 10,
	},
	objectWeights = {
		Campfire = 5,
		Chest = 3,
		["Ice Spike"] = 8,
	},
	hazardWeights = {
		Frozen = 10,
		["Severe Hail Mark"] = 3,
	},
	poiTypes = { "Campfire", "Chest", "Magic Spring" },
	specialRules = "Ice/water coherence important.",
}

RegionData["Volcanic Rock"] = {
	id = "Volcanic Rock",
	identity = "Volcano stone field",
	minSize = 20,
	maxSize = 220,
	terrainWeights = {
		Rocky = 45,
		Molten = 15,
		Clear = 20,
		Sand = 15,
		["Cracked Ground"] = 5,
	},
	objectWeights = {
		["Bomb Barrel"] = 6,
		["Steam Valve"] = 5,
		["Stone Pillar"] = 4,
		Chest = 2,
	},
	hazardWeights = {
		Burning = 8,
		["Molten Hazard"] = 10,
		Steam = 4,
	},
	poiTypes = { "Steam Valve", "Chest", "Dragon Utopia" },
	specialRules = "Hazards frequent. Required battleflow still validated.",
}

RegionData["Lava Channel"] = {
	id = "Lava Channel",
	identity = "Molten feature band",
	minSize = 10,
	maxSize = 140,
	terrainWeights = {
		Molten = 40,
		Rocky = 35,
		Clear = 15,
		Sand = 10,
	},
	objectWeights = {
		Bridge = 5,
		["Steam Valve"] = 4,
		["Stone Pillar"] = 3,
	},
	hazardWeights = {
		Burning = 10,
		Steam = 5,
	},
	poiTypes = { "Bridge", "Steam Valve", "Chest" },
	specialRules = "Similar to WAT but region-owned.",
}

RegionData["Ruins"] = {
	id = "Ruins",
	identity = "Broken ancient structures",
	minSize = 25,
	maxSize = 220,
	terrainWeights = {
		Rocky = 30,
		Clear = 20,
		["Wooden Floor"] = 15,
		Mud = 10,
		["Cracked Ground"] = 10,
		Grassland = 15,
	},
	objectWeights = {
		["Stone Pillar"] = 8,
		Chest = 6,
		Mimic = 3,
		["Bomb Barrel"] = 3,
		["Warrior Tomb"] = 3,
		Library = 1,
		Scholar = 1,
	},
	hazardWeights = {
		["Cracked Ground"] = 5,
		Burning = 2,
		["Poison Cloud"] = 1,
	},
	poiTypes = { "Tomb", "Library", "Scholar", "Chest", "Mimic" },
	specialRules = "Interactive objects common.",
}

RegionData["Castle Courtyard"] = {
	id = "Castle Courtyard",
	identity = "Open fortified area",
	minSize = 25,
	maxSize = 220,
	terrainWeights = {
		Rocky = 35,
		Metal = 15,
		["Wooden Floor"] = 15,
		Clear = 20,
		Grassland = 10,
		Road = 5,
	},
	objectWeights = {
		Ballista = 8,
		Catapult = 5,
		["War Banner"] = 5,
		Wall = 20,
		["Black Market"] = 1,
		Chest = 3,
	},
	hazardWeights = {
		["Bomb Barrel"] = 3,
		Burning = 1,
	},
	poiTypes = { "Ballista", "War Banner", "Chest", "Black Market" },
	specialRules = "Strong defensive object distribution.",
}

RegionData["Castle Interior"] = {
	id = "Castle Interior",
	identity = "Indoor/fortified floor area",
	minSize = 15,
	maxSize = 140,
	terrainWeights = {
		Metal = 30,
		["Wooden Floor"] = 30,
		Rocky = 20,
		Clear = 15,
		Grassland = 5,
	},
	objectWeights = {
		Wall = 25,
		Door = 8,
		Chest = 4,
		["Marletto Tower"] = 2,
		["Mercenary Camp"] = 2,
	},
	hazardWeights = {
		["Bomb Barrel"] = 3,
		Steam = 1,
	},
	poiTypes = { "Chest", "Marletto Tower", "Mercenary Camp" },
	specialRules = "May conflict with open templates unless LAN protected.",
}

RegionData["Graveyard"] = {
	id = "Graveyard",
	identity = "Tombs and death-themed objects",
	minSize = 15,
	maxSize = 140,
	terrainWeights = {
		["Tainted Ground"] = 20,
		Rocky = 25,
		Grassland = 20,
		Clear = 15,
		Mud = 10,
		["Magic Circle"] = 10,
	},
	objectWeights = {
		Tombstone = 20,
		Coffin = 10,
		["Warrior Tomb"] = 5,
		["Cursed Statue"] = 3,
		Chest = 2,
	},
	hazardWeights = {
		["Dark Eclipse Mark"] = 3,
		["Poison Cloud"] = 2,
	},
	poiTypes = { "Warrior Tomb", "Cursed Statue", "Chest" },
	specialRules = "Pairs with Corrupted/Ruins.",
}

RegionData["Corrupted"] = {
	id = "Corrupted",
	identity = "Cursed magical patch",
	minSize = 20,
	maxSize = 180,
	terrainWeights = {
		["Tainted Ground"] = 40,
		["Magic Circle"] = 15,
		Swamp = 15,
		Rocky = 15,
		Mud = 10,
		Clear = 5,
	},
	objectWeights = {
		["Cursed Statue"] = 6,
		["Skeleton Transformer"] = 4,
		Altar = 2,
		["Cover of Darkness"] = 2,
		["Seer Hut"] = 1,
	},
	hazardWeights = {
		["Poison Cloud"] = 4,
		["Dark Field"] = 6,
		["Hunger Virus Mark"] = 2,
	},
	poiTypes = { "Cursed Statue", "Altar", "Seer Hut", "Chest" },
	specialRules = "Resource denial/status theme.",
}

RegionData["Beach"] = {
	id = "Beach",
	identity = "Coastal sand/shore",
	minSize = 20,
	maxSize = 180,
	terrainWeights = {
		Sand = 45,
		["Shallow Water"] = 20,
		Clear = 15,
		Rocky = 10,
		Grassland = 5,
		Mud = 5,
	},
	objectWeights = {
		Driftwood = 12,
		Boat = 4,
		Chest = 3,
		Campfire = 2,
	},
	hazardWeights = {
		Wet = 5,
		["Strong Wind Mark"] = 2,
	},
	poiTypes = { "Chest", "Campfire", "Boat" },
	specialRules = "Useful for coastline biome later.",
}

RegionData["Dock"] = {
	id = "Dock",
	identity = "Harbor/dock structures",
	minSize = 15,
	maxSize = 120,
	terrainWeights = {
		["Wooden Floor"] = 35,
		["Shallow Water"] = 25,
		Clear = 15,
		Rocky = 10,
		Metal = 5,
		["Deep Water"] = 10,
	},
	objectWeights = {
		Crate = 15,
		Boat = 8,
		["Black Market"] = 2,
		["Trading Post"] = 3,
		Chest = 3,
	},
	hazardWeights = {
		Wet = 5,
		Oily = 2,
	},
	poiTypes = { "Trading Post", "Black Market", "Chest" },
	specialRules = "City/coast hybrid.",
}

RegionData["Cave Chamber"] = {
	id = "Cave Chamber",
	identity = "Underground chamber content",
	minSize = 20,
	maxSize = 180,
	terrainWeights = {
		Rocky = 45,
		Clear = 20,
		Mud = 15,
		["Deep Water"] = 10,
		["Cracked Ground"] = 10,
	},
	objectWeights = {
		["Stone Pillar"] = 8,
		Mimic = 4,
		Chest = 4,
		Campfire = 2,
		["Warrior Tomb"] = 2,
	},
	hazardWeights = {
		["Dark Pool"] = 5,
		["Earthquake Mark"] = 3,
	},
	poiTypes = { "Mimic", "Chest", "Campfire", "Tomb" },
	specialRules = "Topology special case.",
}

return RegionData