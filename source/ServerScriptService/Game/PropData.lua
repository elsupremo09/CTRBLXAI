--!strict
-- PropData.lua
-- CTRBLXAI | Slice 7 (visual polish) — decorative prop tables. VISUAL ONLY.
--
-- Two prop families, both cloned from ServerStorage > Props:
--   Blockers : dress OBS wall tiles (impassable already; props change nothing).
--   Tiles    : ground clutter on free passable tiles.
--
-- Names must match the Studio instance names EXACTLY (incl. "Pendestal",
-- "Relinquary"). Several instances may share one name — they become random
-- variants of that one prop; caps count the NAME, not the copy.
--
-- Entry fields:
--   names     : prop names sharing these rules (a "family")
--   tag       : Blockers only — "G" groupable (may repeat inside an OBS cluster)
--               or "S" solo (max SOLO_PER_NAME per map, never 8-adjacent to
--               another solo, max one per cluster)
--   regions   : region types allowed; nil = any region
--   biomes    : allow-list of biome ids; nil = any
--   notBiomes : deny-list of biome ids
--   landmark  : Tiles only — rare, spaced-out hero clutter
--
-- Server-only (MEM-003). Frozen (DAT-002). One domain per file (DAT-003).

local PropData = {}

PropData.Config = table.freeze({
	-- Folder lookup (first match wins; tolerates the "Blockers Props" spelling).
	ROOT_FOLDER          = "Props",
	BLOCKER_FOLDERS      = table.freeze({ "Blockers Props", "Blocker Props" }),
	TILE_FOLDERS         = table.freeze({ "Tile Props" }),

	-- Size envelope (studs). Single-tile props are scaled DOWN to fit; never up.
	MAX_HEIGHT           = 5,

	-- Blockers
	BLOCKER_USES_PER_NAME   = 2,    -- a cluster or a lone tile = 1 use
	SOLO_PER_NAME           = 2,
	CLUSTER_GROUPABLE_NAMES = 4,    -- distinct groupable names mixed per cluster (variety > uniformity)
	CLUSTER_SOLO_CHANCE     = 0.5,  -- chance a cluster gets one solo on an edge tile
	-- Blocker props are NOT resized (authored at final size, user 2026-10-09).
	BLOCKER_MAX_OFFSET      = 0.7,  -- studs of in-tile jitter so clusters don't read as a grid

	-- Tile props
	TILE_DENSITY            = 0.12,
	DEPLOY_DENSITY_MULT     = 0.4,  -- PD / ED / OBJ tiles get fewer props
	TILE_PER_NAME           = 4,
	LANDMARK_PER_NAME       = 1,
	LANDMARK_MAX            = 2,
	LANDMARK_SPACING        = 4,    -- Chebyshev tiles between landmarks
	TILE_MAX_OFFSET         = 0.8,  -- studs of in-tile jitter for small props
	TILE_SCALE_JITTER       = 0.15,

	EXCLUDED_TERRAIN = table.freeze({
		["Deep Water"] = true, ["Shallow Water"] = true,
		["Quicksand"] = true, ["Molten"] = true,
	}),
	REDUCED_MARKERS = table.freeze({ PD = true, ED = true, OBJ = true }),

	-- Intentionally excluded (user decision 2026-10-08): loot-looking clutter,
	-- and 1x2 bones reserved for future multi-tile cluster blockers.
	-- Listed so the audit does not warn about them.
	EXCLUDED_NAMES = table.freeze({
		["Gold Pile"] = true, ["Treasure Pile"] = true, ["Portal"] = true,
	}),
})

local NOT_HARSH = { "Desert", "Tundra", "Volcano" }

PropData.Blockers = {
	-- Groupable -------------------------------------------------------------
	{ names = { "Tree" }, tag = "G",
		regions = { "Forest", "Grassland", "Clearing", "Riverbank", "Farmland" }, notBiomes = NOT_HARSH },
	{ names = { "Palm Tree" }, tag = "G",
		regions = { "Beach", "Riverbank" }, biomes = { "Desert" } },
	{ names = { "Cactus", "Cactus2", "Cactus_1", "Cactus_3", "Cactus_4", "Cactus_5", "Cactus_6", "Cactus_7" }, tag = "G",
		regions = { "Rocky", "Beach", "Mountain Pass", "Ruins", "Clearing", "Grassland" }, biomes = { "Desert" } },
	{ names = { "Snow Tree" }, tag = "G",
		regions = { "Frozen Lake", "Rocky", "Mountain Pass", "Grassland", "Clearing", "Riverbank" }, biomes = { "Tundra" } },
	{ names = { "Dead White Tree" }, tag = "G",
		regions = { "Frozen Lake", "Graveyard", "Corrupted" } },
	{ names = { "Dead Tree" }, tag = "G",
		regions = { "Marsh", "Graveyard", "Corrupted", "Rocky" } },
	{ names = { "Ice Crystal Pile" }, tag = "G",
		regions = { "Frozen Lake", "Rocky", "Cave Chamber" }, biomes = { "Tundra", "Cave" } },
	{ names = { "Volcanic Vent", "Volcanic Vent 2", "Volcanic Vent 3" }, tag = "G",
		regions = { "Volcanic Rock", "Lava Channel" } },
	{ names = { "Poison Crystal" }, tag = "G",
		regions = { "Corrupted", "Marsh", "Cave Chamber" } },
	{ names = { "Shiny Fungi" }, tag = "G",
		regions = { "Cave Chamber", "Marsh", "Forest" } },
	{ names = { "Corrupted Nest" }, tag = "G",
		regions = { "Corrupted", "Marsh" } },
	{ names = { "Hay Stack", "Haybale" }, tag = "G",
		regions = { "Farmland", "Village", "Grassland" }, biomes = { "Plains", "Castle" } },
	{ names = { "Beer Barrel", "Beer Keg", "Wooden Barrel" }, tag = "G",
		regions = { "Village", "Town", "Farmland", "Castle Interior" } },
	{ names = { "Iron Barrel" }, tag = "G",
		regions = { "Castle Interior", "Town" } },
	{ names = { "Wooden Crate" }, tag = "G",
		regions = { "Village", "Town", "Castle Interior", "Riverbank" } },

	-- Solo ------------------------------------------------------------------
	{ names = { "Armor Stand", "Weapon Rack" }, tag = "S",
		regions = { "Castle Courtyard", "Castle Interior", "Town" } },
	{ names = { "Bone Throne", "Skull Candle" }, tag = "S",
		regions = { "Graveyard", "Corrupted", "Cave Chamber" } },
	{ names = { "Ice Throne" }, tag = "S",
		regions = { "Frozen Lake" }, biomes = { "Tundra" } },
	{ names = { "Ruined Stone Throne" }, tag = "S",
		regions = { "Ruins", "Castle Courtyard" } },
	{ names = { "Gargoyle Statue" }, tag = "S",
		regions = { "Castle Courtyard", "Ruins", "Graveyard", "Corrupted" } },
	{ names = { "Gothic Pedestal 3", "Gothic Pendestal", "Gothic Pendestal 2", "Candle Holder" }, tag = "S",
		regions = { "Castle Interior", "Ruins", "Graveyard" } },
	{ names = { "Ruins Statue Head" }, tag = "S",
		regions = { "Ruins", "Beach", "Graveyard" } },
	{ names = { "Warrior's Tomb" }, tag = "S",
		regions = { "Graveyard", "Ruins" } },
	{ names = { "Shrine 1", "Shrine 2", "Shrine 3" }, tag = "S",
		regions = { "Ruins", "Clearing", "Forest", "Village" } },
	{ names = { "Spirit Tree" }, tag = "S",
		regions = { "Forest", "Clearing", "Corrupted" } },
	{ names = { "Rocking Chair", "Wheel Cart", "Prop_FirewoodLogHolderShelfLogs" }, tag = "S",
		regions = { "Village", "Town", "Farmland" } },
}

PropData.Tiles = {
	-- Natural clutter -------------------------------------------------------
	{ names = { "Fern", "Clover 1", "Clover 2", "Crownbeard", "Mall Bigleaves Plant 1 Medium", "Mall Big Plant 01" },
		regions = { "Grassland", "Clearing", "Forest", "Riverbank", "Farmland" }, notBiomes = NOT_HARSH },
	{ names = { "Sunflower 1", "Sunflower 2", "Sunflower 3", "Sunflower 4",
		"Sunflower 5", "Sunflower 6", "Sunflower 7", "Sunflower 8" },
		regions = { "Farmland", "Grassland", "Village" }, notBiomes = NOT_HARSH },
	{ names = { "White Ornamental Kale" },
		regions = { "Village", "Town", "Castle Courtyard" } },
	{ names = { "Bamboo", "Marsh Vines" },
		regions = { "Marsh", "Riverbank", "Forest" } },
	{ names = { "Broken Branch" },
		regions = { "Forest", "Clearing", "Marsh", "Riverbank" } },
	{ names = { "Mushroom", "SM_Env_Mushroom_Giant_05" },
		regions = { "Forest", "Marsh", "Cave Chamber" } },
	{ names = { "MossyRocks 1", "MossyRocks 2", "MossyRocks 3", "MossyRocks 4", "MossyRocks 5", "MossyRocks 6" },
		regions = { "Forest", "Riverbank", "Rocky", "Mountain Pass", "Ruins", "Marsh", "Clearing" },
		notBiomes = { "Desert", "Volcano" } },
	{ names = { "Dead Bush 1", "Dead Bush 2", "Dead Bush 3" },
		regions = { "Rocky", "Beach", "Mountain Pass", "Graveyard", "Volcanic Rock" } },
	{ names = { "Ground Snow", "Snow Rock", "Snow Burial Mound" },
		regions = nil, biomes = { "Tundra" } },
	{ names = { "Bone", "Bone Pile", "Rib", "Ribcage 1x2", "Spine 1x2", "Jaw", "Skull", "Animal Bones", "Animal Bones 2" },
		regions = { "Graveyard", "Corrupted", "Cave Chamber", "Volcanic Rock", "Rocky", "Beach" } },
	{ names = { "Grave Stone", "Grave Stone 2", "Grave Stone 3", "Stone Cross" },
		regions = { "Graveyard", "Corrupted" } },
	{ names = { "Empty Wood Box" },
		regions = { "Village", "Town", "Farmland", "Castle Interior" } },
	{ names = { "Torch Stand" },
		regions = { "Castle Courtyard", "Castle Interior", "Cave Chamber", "Ruins" } },

	-- Landmarks (rare, spaced) ---------------------------------------------
	{ names = { "Dino Skull_BLDG" }, landmark = true,
		regions = { "Rocky", "Beach", "Volcanic Rock" }, biomes = { "Desert", "Volcano" } },
	{ names = { "Angel Tombstone", "Skull Shrine" }, landmark = true,
		regions = { "Graveyard", "Corrupted", "Ruins" } },
	{ names = { "Toppled Statue" }, landmark = true,
		regions = { "Ruins", "Castle Courtyard" } },
	{ names = { "Road Shrine_BLDG" }, landmark = true,
		regions = { "Village", "Grassland", "Mountain Pass" } },
	{ names = { "Precious Urn", "Relinquary" }, landmark = true,
		regions = { "Castle Interior", "Ruins", "Cave Chamber" } },
	{ names = { "Globe" }, landmark = true,
		regions = { "Castle Interior" } },
}

table.freeze(PropData.Blockers)
table.freeze(PropData.Tiles)

return table.freeze(PropData)
