-- BiomeData.lua
-- CTRBLXAI | Slice 5 -- Procedural Map Generation
--
-- Generated from CTRBLXAI.db biomes table.
-- DO NOT EDIT MANUALLY -- regenerate from DB if rules change.

local BiomeData = {}

BiomeData["Plains"] = {
	id = "Plains",
	description = "Wide open battlefields emphasizing mobility and positioning.",
	terrainWeights = {
		Grassland = 40,
		Clear = 30,
		["Clover Field"] = 10,
		Rocky = 10,
		["Shallow Water"] = 5,
		Mud = 5,
	},
	objectWeights = {
		["Treasure Chest"] = 10,
		Campfire = 8,
		["Trading Post"] = 4,
		["War Banner"] = 3,
		["Rally Flag"] = 3,
		["Healing Spring"] = 2,
	},
	typicalInhabitants = { "Human kingdoms", "beasts", "goblins", "travelers" },
	battleConditionWeights = {
		Clear = 35,
		Rain = 20,
		["Strong Wind"] = 15,
		Thunderstorm = 10,
		Heatwave = 10,
		["Holy Aurora"] = 10,
	},
	generationRules = "Low elevation variance. Large open fields with sparse obstacles.",
	notes = "Beginner-friendly biome.",
}

BiomeData["Forest"] = {
	id = "Forest",
	description = "Dense vegetation with chokepoints, ambushes, and fire hazards.",
	terrainWeights = {
		Grassland = 35,
		Clear = 20,
		["Clover Field"] = 15,
		Mud = 10,
		["Shallow Water"] = 10,
		Rocky = 10,
	},
	objectWeights = {
		["Bear Trap"] = 10,
		["Snare Trap"] = 8,
		["Treasure Chest"] = 8,
		Campfire = 6,
		["Healing Spring"] = 5,
		["Magic Spring"] = 2,
		["Witch Hut"] = 2,
		Scholar = 2,
		Mimic = 1,
	},
	typicalInhabitants = { "Beasts", "elves", "goblins", "witches", "forest spirits" },
	battleConditionWeights = {
		Rain = 30,
		["Strong Wind"] = 20,
		["Wild Growth"] = 20,
		Clear = 15,
		Thunderstorm = 10,
		["Hunger Virus"] = 5,
	},
	generationRules = "Dense tree placement with winding paths and occasional clearings.",
	notes = "Fire spreads easily.",
}

BiomeData["Desert"] = {
	id = "Desert",
	description = "Open terrain with harsh movement penalties and long sightlines.",
	terrainWeights = {
		Sand = 45,
		Rocky = 25,
		Clear = 20,
		Mud = 5,
		["Shallow Water"] = 5,
	},
	objectWeights = {
		["Treasure Chest"] = 8,
		Campfire = 5,
		["Stone Pillar"] = 4,
		Scholar = 2,
		["Warrior's Tomb"] = 2,
	},
	typicalInhabitants = { "Nomads", "bandits", "beasts", "undead" },
	battleConditionWeights = {
		Clear = 40,
		Heatwave = 35,
		["Strong Wind"] = 15,
		["Meteor Storm"] = 10,
	},
	generationRules = "Moderate elevation with scattered rock formations.",
	notes = "Favors ranged combat.",
}

BiomeData["Swamp"] = {
	id = "Swamp",
	description = "Difficult terrain focused on attrition, poison, and water control.",
	terrainWeights = {
		Swamp = 35,
		Mud = 25,
		["Shallow Water"] = 20,
		Grassland = 10,
		Rocky = 10,
	},
	objectWeights = {
		["Bear Trap"] = 8,
		["Snare Trap"] = 6,
		["Treasure Chest"] = 6,
		["Healing Spring"] = 4,
		["Witch Hut"] = 3,
		["Cursed Statue"] = 2,
		["Magic Spring"] = 2,
	},
	typicalInhabitants = { "Naga", "slimes", "insects", "undead" },
	battleConditionWeights = {
		Rain = 30,
		["Hunger Virus"] = 30,
		["Wild Growth"] = 15,
		Thunderstorm = 10,
		["Strong Wind"] = 10,
		Clear = 5,
	},
	generationRules = "Large connected wetlands with poor mobility.",
	notes = "Environmental control is dominant.",
}

BiomeData["Highlands"] = {
	id = "Highlands",
	description = "Elevation-driven combat rewarding positioning and knockback.",
	terrainWeights = {
		Rocky = 35,
		Grassland = 25,
		Clear = 15,
		Sand = 10,
		Mud = 10,
		["Clover Field"] = 5,
	},
	objectWeights = {
		["Stone Pillar"] = 10,
		Ballista = 6,
		["Treasure Chest"] = 6,
		Campfire = 3,
		["War Banner"] = 3,
		["Rally Flag"] = 2,
		Arena = 2,
		["Dragon Utopia"] = 1,
	},
	typicalInhabitants = { "Mountain tribes", "dragons", "beasts", "gryphons" },
	battleConditionWeights = {
		["Strong Wind"] = 30,
		Thunderstorm = 25,
		Earthquake = 20,
		Clear = 15,
		["Holy Aurora"] = 10,
	},
	generationRules = "Large elevation differences, cliffs, bridges and narrow passes.",
	notes = "Flight and Push/Pull are highly valuable.",
}

BiomeData["Tundra"] = {
	id = "Tundra",
	description = "Frozen battlefield emphasizing sliding movement and ice control.",
	terrainWeights = {
		Ice = 35,
		["Shallow Water"] = 20,
		Rocky = 20,
		Clear = 15,
		Grassland = 10,
	},
	objectWeights = {
		Campfire = 8,
		["Treasure Chest"] = 6,
		["Healing Spring"] = 3,
		["Magic Spring"] = 3,
		Scholar = 2,
	},
	typicalInhabitants = { "Arctic beasts", "undead", "frost creatures" },
	battleConditionWeights = {
		["Severe Hail"] = 40,
		["Strong Wind"] = 20,
		Clear = 15,
		Thunderstorm = 10,
		Heatwave = 5,
		["Holy Aurora"] = 10,
	},
	generationRules = "Large frozen lakes connected by rocky paths.",
	notes = "Water and Ice interactions dominate.",
}

BiomeData["Volcano"] = {
	id = "Volcano",
	description = "Hazardous battlefield filled with molten terrain and explosions.",
	terrainWeights = {
		Rocky = 40,
		Molten = 25,
		Clear = 20,
		Sand = 15,
	},
	objectWeights = {
		["Bomb Barrel"] = 10,
		["Steam Valve"] = 8,
		["Treasure Chest"] = 5,
		["Stone Pillar"] = 3,
		["Dragon Utopia"] = 2,
	},
	typicalInhabitants = { "Dragons", "demons", "fire creatures" },
	battleConditionWeights = {
		["Volcanic Eruptions"] = 35,
		Heatwave = 25,
		Earthquake = 15,
		["Meteor Storm"] = 15,
		["Mana Storm"] = 5,
		Clear = 5,
	},
	generationRules = "Frequent hazards, unstable terrain and elevation damage.",
	notes = "Environmental hazards are constant threats.",
}

BiomeData["Cave"] = {
	id = "Cave",
	description = "Tight underground passages with limited maneuverability.",
	terrainWeights = {
		Rocky = 45,
		Clear = 20,
		Mud = 20,
		["Deep Water"] = 15,
	},
	objectWeights = {
		["Treasure Chest"] = 8,
		Mimic = 5,
		["Stone Pillar"] = 4,
		Campfire = 3,
		["Healing Spring"] = 2,
		["Warrior's Tomb"] = 2,
	},
	typicalInhabitants = { "Undead", "slimes", "beasts", "cave dwellers" },
	battleConditionWeights = {
		Clear = 55,
		Earthquake = 25,
		["Mana Storm"] = 10,
		["Dark Eclipse"] = 10,
	},
	generationRules = "Narrow corridors connected by larger chambers.",
	notes = "Close-quarters combat favored.",
}

BiomeData["Ruins"] = {
	id = "Ruins",
	description = "Ancient battlefields filled with relics, traps, and interactive structures.",
	terrainWeights = {
		Rocky = 35,
		Clear = 25,
		Grassland = 15,
		["Wooden Floor"] = 15,
		Mud = 10,
	},
	objectWeights = {
		["Stone Pillar"] = 8,
		["Treasure Chest"] = 8,
		Mimic = 4,
		["Bomb Barrel"] = 4,
		Ballista = 3,
		["Warrior's Tomb"] = 3,
		["Library of Enlightenment"] = 2,
		Scholar = 2,
		Cartographer = 2,
	},
	typicalInhabitants = { "Undead guardians", "mercenaries", "constructs" },
	battleConditionWeights = {
		Clear = 25,
		["Strong Wind"] = 15,
		Thunderstorm = 15,
		Earthquake = 10,
		["Meteor Storm"] = 10,
		["Mana Storm"] = 10,
		["Holy Aurora"] = 10,
		["Dark Eclipse"] = 5,
	},
	generationRules = "Dense object placement with broken structures and hidden passages.",
	notes = "Highly interactive environment.",
}

BiomeData["Castle"] = {
	id = "Castle",
	description = "Fortified strongholds centered around siege warfare.",
	terrainWeights = {
		Metal = 30,
		["Wooden Floor"] = 25,
		Rocky = 20,
		Clear = 15,
		Grassland = 10,
	},
	objectWeights = {
		Ballista = 10,
		Catapult = 8,
		["Bomb Barrel"] = 8,
		["War Banner"] = 6,
		["Treasure Chest"] = 5,
		["Trading Post"] = 3,
		["Black Market"] = 2,
		["Marletto Tower"] = 2,
		["Mercenary Camp"] = 2,
	},
	typicalInhabitants = { "Soldiers", "knights", "guards", "constructs" },
	battleConditionWeights = {
		Clear = 40,
		Rain = 15,
		["Strong Wind"] = 15,
		Thunderstorm = 10,
		["Holy Aurora"] = 10,
		["Meteor Storm"] = 10,
	},
	generationRules = "Walls, courtyards, towers and defensive chokepoints.",
	notes = "Strong defensive positioning.",
}

BiomeData["Corrupted"] = {
	id = "Corrupted",
	description = "Lands twisted by dark magic and decay.",
	terrainWeights = {
		["Tainted Ground"] = 35,
		Swamp = 20,
		Rocky = 20,
		Mud = 15,
		Clear = 10,
	},
	objectWeights = {
		["Cursed Statue"] = 8,
		["Skeleton Transformer"] = 5,
		["Treasure Chest"] = 5,
		["Witch Hut"] = 4,
		Mimic = 3,
		["Altar of Sacrifice"] = 2,
		["Cover of Darkness"] = 2,
		["Seer's Hut"] = 1,
	},
	typicalInhabitants = { "Undead", "demons", "corrupted beasts", "cultists" },
	battleConditionWeights = {
		["Hunger Virus"] = 25,
		["Dark Eclipse"] = 25,
		Thunderstorm = 15,
		["Meteor Storm"] = 10,
		Rain = 10,
		["Mana Storm"] = 10,
		["Strong Wind"] = 5,
	},
	generationRules = "Corruption clusters around cursed landmarks and shrines.",
	notes = "Resource denial and status ailments are common.",
}

return BiomeData