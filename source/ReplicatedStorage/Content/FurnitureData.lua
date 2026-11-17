--!strict
-- FurnitureData.lua
-- CTRBLXAI | Guild Hall furniture data (DAT-001: the one place furniture data lives; client
-- and server both read it).
--
-- TWO BLOCKS (furniture v4 rebuild, step 1 of 5, 2026-11-16):
--   1. LEGACY (v1, built steps 2-3): the 22 fixed pieces + slot/cap getters that FurnitureService,
--      EquipmentService, DungeonFurniture and GuildMenu read TODAY. Kept byte-for-byte so the game
--      runs unchanged until step 2 rewires the services onto block 2. Do not edit; delete in step 5.
--   2. V4 (FurnitureData.V4): the APPROVED v4 model, docs\CTRBLXAI.db guild_facilities 91-108
--      (USER RULINGS 2026-11-16 5:57 PM v3 rooms, 6:48 PM + 7:02 PM v4 rarity tiers / threshold /
--      enemy lines). Nothing reads it yet.
--
-- Legacy effect keys (block 1): hpPct, mp, healRecv, rtDelayResist, collision, skillPotency,
-- precision, evasiveness, fortune, STR AGI DEX INT VIT LUK, battleGold, dispatchFee, inventory.
-- Legacy category Logistics = no combat power; Display = looks only.

export type Piece = {
	id: string,
	name: string,
	category: string,
	points: number,           -- gear bonus point price (10 / 15 / 20); 0 = Logistics / Display
	effect: { [string]: number },
	text: string,             -- effect line as written in the approved catalogue (guild_facilities 94)
	source: string,           -- "Shop" | "Crafted" | "DungeonDrop" | "BossDrop" | "TrophyHall" | "GuildHall10"
	price: number?,           -- gold (Shop and Crafted)
	needGuildHall: number?,   -- shop gate (Guild Hall level)
	needRank: number?,        -- shop gate (Renown Rank)
	looksOnly: boolean?,
	notInShop: boolean?,      -- in the catalogue but not sold yet (its system is not built)
	craftAt: string?,         -- Crafted: the building whose Furniture row crafts it (step 3)
	mats: { [string]: number }?, -- Crafted: materials charged with the gold (mercury / crystals)
}

local PIECES: { Piece } = {
	{ id = "FUR-01", name = "Straw Cot", category = "Comfort", points = 10, effect = { hpPct = 0.01 }, text = "+1% max HP", source = "Shop", price = 150 },
	{ id = "FUR-02", name = "Oak Bed", category = "Comfort", points = 20, effect = { hpPct = 0.02 }, text = "+2% max HP", source = "Shop", price = 450, needGuildHall = 3 },
	{ id = "FUR-03", name = "Stone Hearth", category = "Comfort", points = 10, effect = { healRecv = 0.02 }, text = "Healing received x1.02", source = "Shop", price = 200 },
	{ id = "FUR-04", name = "Herbal Rack", category = "Comfort", points = 10, effect = { rtDelayResist = 0.98 }, text = "RT Delay Resistance x0.98 (-2% RT delay taken)", source = "Crafted", price = 250, craftAt = "Apothecary", mats = { mercury = 2 } }, -- P1 (3:40 PM)
	{ id = "FUR-05", name = "Padded Wall", category = "Comfort", points = 15, effect = { collision = 0.97 }, text = "Collision taken x0.97", source = "DungeonDrop" },
	{ id = "FUR-06", name = "Scribe's Desk", category = "Study", points = 10, effect = { mp = 2 }, text = "+2 max MP", source = "Shop", price = 150 },
	{ id = "FUR-07", name = "Arcane Lectern", category = "Study", points = 10, effect = { skillPotency = 0.01 }, text = "Skill Potency +1%", source = "Shop", price = 400, needGuildHall = 4 },
	{ id = "FUR-08", name = "Star Chart", category = "Study", points = 10, effect = { precision = 0.005 }, text = "Precision +0.5pp", source = "DungeonDrop" },
	{ id = "FUR-09", name = "Tome Stack", category = "Study", points = 15, effect = { skillPotency = 0.015 }, text = "Skill Potency +1.5%", source = "BossDrop" },
	{ id = "FUR-10", name = "Practice Dummy", category = "Martial", points = 15, effect = { STR = 1 }, text = "+1 STR", source = "Shop", price = 300 },
	{ id = "FUR-11", name = "Balance Beam", category = "Martial", points = 15, effect = { AGI = 1 }, text = "+1 AGI", source = "Shop", price = 300, needGuildHall = 5 },
	{ id = "FUR-12", name = "Target Board", category = "Martial", points = 15, effect = { DEX = 1 }, text = "+1 DEX", source = "Crafted", price = 300, craftAt = "Blacksmith", mats = { mercury = 2 } },
	{ id = "FUR-13", name = "Meditation Mat", category = "Martial", points = 15, effect = { INT = 1 }, text = "+1 INT", source = "Crafted", price = 300, craftAt = "Runeforge", mats = { crystals = 1 } },
	{ id = "FUR-14", name = "Iron Training Weights", category = "Martial", points = 15, effect = { VIT = 1 }, text = "+1 VIT", source = "DungeonDrop" },
	{ id = "FUR-15", name = "Dodge Course", category = "Martial", points = 10, effect = { evasiveness = 0.005 }, text = "Evasion +0.5pp", source = "DungeonDrop" },
	{ id = "FUR-16", name = "Lucky Coin Shrine", category = "Fortune", points = 10, effect = { fortune = 0.01 }, text = "Fortune +1%", source = "Shop", price = 350 },
	{ id = "FUR-17", name = "Clover Planter", category = "Fortune", points = 15, effect = { LUK = 1 }, text = "+1 LUK", source = "DungeonDrop" },
	{ id = "FUR-18", name = "Gilded Chest", category = "Fortune", points = 20, effect = { battleGold = 0.02 }, text = "+2% battle gold", source = "BossDrop" },
	{ id = "FUR-19", name = "War Table Map", category = "Logistics", points = 0, effect = { dispatchFee = -5 }, text = "Dispatch fee -5g", source = "Shop", price = 500, needRank = 5 },
	{ id = "FUR-20", name = "Supply Shelf", category = "Logistics", points = 0, effect = { inventory = 5 }, text = "+5 inventory threshold", source = "Shop", price = 400, notInShop = true },
	{ id = "FUR-21", name = "Trophy Pedestal", category = "Display", points = 0, effect = {}, text = "Looks only — no bonus.", source = "TrophyHall", looksOnly = true },
	{ id = "FUR-22", name = "Guild Banner", category = "Display", points = 0, effect = {}, text = "Looks only — no bonus.", source = "GuildHall10", looksOnly = true },
}

local BY_ID: { [string]: Piece } = {}
for _, p in PIECES do
	table.freeze(p.effect)
	if p.mats then table.freeze(p.mats) end
	table.freeze(p)
	BY_ID[p.id] = p
end

local FurnitureData = {}

-- guild_facilities 91: bonus slots by Guild Hall level (index = level).
FurnitureData.BonusSlots = table.freeze({ 2, 3, 4, 5, 6, 7, 8, 9, 10, 12 })

-- guild_facilities 92: total combat cap = 6 points x Guild Hall level; family cap 30.
FurnitureData.CapPerGuildHallLevel = 6
FurnitureData.FamilyCap = 30

FurnitureData.Pieces = table.freeze(PIECES)

function FurnitureData.Get(id: any): Piece?
	if type(id) ~= "string" then return nil end
	return BY_ID[id]
end

--- Wall-decoration slots (looks-only pieces only): 1 at Guild Hall L5, 2 at L8, +banner at L10.
function FurnitureData.DecorSlots(guildHallLevel: number): number
	local n = 0
	if guildHallLevel >= 5 then n += 1 end
	if guildHallLevel >= 8 then n += 1 end
	if guildHallLevel >= 10 then n += 1 end
	return n
end

function FurnitureData.SlotsFor(guildHallLevel: number): number
	local l = math.clamp(math.floor(guildHallLevel), 1, 10)
	return FurnitureData.BonusSlots[l]
end

function FurnitureData.CapFor(guildHallLevel: number): number
	return FurnitureData.CapPerGuildHallLevel * math.clamp(math.floor(guildHallLevel), 1, 10)
end


-- =============================================================================================
-- BLOCK 2: V4 MODEL (guild_facilities 91-108). Not read by any service yet (step 2+).
-- Stat keys used by every V4 table:
--   primary   STR AGI DEX INT VIT LUK          flat
--   maxHp maxMp attack defense                  flat
--   precision evasion                           percentage points (0.5 = +0.5 pp)
--   skillPotency healingOutput itemDamage collisionDamage fallDamage   percent (+1 = +1%)
--   debuffResist rtDelayResist collisionResist fallResist              percent LESS taken (1 = x0.99)
--   threshold: movement jump force stability discoveryRadius interactRange itemRange range
-- =============================================================================================

local function deepFreeze(t: any): any
	if type(t) ~= "table" or table.isfrozen(t) then return t end
	for _, v in pairs(t) do deepFreeze(v) end
	return table.freeze(t)
end

local V4: any = {}

V4.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Transcendent" }

-- row 101 (rarity table) + row 104 (gates). lines = rolled lines; pts = points per line (min,max);
-- secondaryShare = chance a line comes from the Secondary pool (0 = Basic only);
-- threshold = guaranteed threshold lines; gate = Guild Hall level needed;
-- weights = per-source rarity weights (shop / craft / dungeon / boss). Mythic/Transcendent are
-- NOT in the boss weights: see BossTopChance (D37, per rewarded boss win).
V4.Rarities = {
	Common       = { step = 1, lines = 1, pts = { 8, 12 },  secondaryShare = 0,   threshold = 0, gate = 1,  weights = { shop = 70, craft = 40, dungeon = 45,  boss = 0 } },
	Uncommon     = { step = 2, lines = 1, pts = { 14, 20 }, secondaryShare = 0,   threshold = 0, gate = 1,  weights = { shop = 25, craft = 40, dungeon = 35,  boss = 40 } },
	Rare         = { step = 3, lines = 2, pts = { 10, 16 }, secondaryShare = 0,   threshold = 0, gate = 3,  weights = { shop = 5,  craft = 17, dungeon = 15,  boss = 34.8 } },
	Epic         = { step = 4, lines = 2, pts = { 16, 22 }, secondaryShare = 0.4, threshold = 0, gate = 5,  weights = { shop = 0,  craft = 3,  dungeon = 4.5, boss = 19 } },
	Legendary    = { step = 5, lines = 3, pts = { 14, 20 }, secondaryShare = 0.4, threshold = 0, gate = 8,  weights = { shop = 0,  craft = 0,  dungeon = 0.3, boss = 5 } },
	Mythic       = { step = 6, lines = 3, pts = { 14, 18 }, secondaryShare = 0.5, threshold = 1, gate = 9,  weights = { shop = 0,  craft = 0,  dungeon = 0,   boss = 0 } },
	Transcendent = { step = 7, lines = 4, pts = { 12, 16 }, secondaryShare = 0.5, threshold = 1, gate = 10, weights = { shop = 0,  craft = 0,  dungeon = 0,   boss = 0 } },
}
-- D37 (reworded 7:02 PM): separate chance PER REWARDED BOSS WIN (inside the 3/day boss limit).
-- RETIRED by v5 (guild_facilities 101/109, USER RULING 2026-11-16 7:44 PM): kept for reference, read by nothing.
V4.BossTopChance = { Mythic = 0.01, Transcendent = 0.002 }
-- D37: hardest dungeon rooms only, Mythic 0.2% per furniture roll there. RETIRED by v5 (row 109), read by nothing.
V4.HardestRoomMythicChance = 0.002
-- v5 SOURCES (guild_facilities 109, USER RULING 2026-11-16 7:44 / 7:47 PM; build step 3). Furniture only comes
-- from dungeon Elites + stage bosses (plus crafting and fixed grants). Fortune / drop multiplier / Elite+Boss
-- loot bonus never touch these rolls. Guild Hall gates (row 104) still apply after the roll.
V4.Sources = {
	-- one roll per Elite win, chance by Dungeon facility level L1-L10
	EliteChance = { 0.20, 0.22, 0.24, 0.26, 0.28, 0.30, 0.31, 0.32, 0.34, 0.35 },
	-- Elite rarity weights; at stage 1 the Epic weight moves to Rare
	EliteWeights = { Common = 45, Uncommon = 35, Rare = 17, Epic = 3 },
	EliteStage1EpicToRare = true,
	-- boss rarity rows by stage: 1, 2, 3, 4-5, 6+ (C/U/R/E/L/M/T)
	BossRows = {
		{ Common = 0, Uncommon = 45, Rare = 40, Epic = 15 },
		{ Common = 0, Uncommon = 30, Rare = 40, Epic = 24, Legendary = 6 },
		{ Common = 0, Uncommon = 20, Rare = 35, Epic = 30, Legendary = 13, Mythic = 2 },
		{ Common = 0, Uncommon = 10, Rare = 30, Epic = 35, Legendary = 20, Mythic = 4.5, Transcendent = 0.5 },
		{ Common = 0, Uncommon = 0, Rare = 25, Epic = 38, Legendary = 27, Mythic = 8, Transcendent = 2 },
	},
	-- Simulator fix 3: Medium bosses roll the next stage's row, Hard two stages deeper (old difficulty 2/3/5)
	DifficultyStageShift = { [2] = 0, [3] = 1, [5] = 2 },
	-- boss pool: the 9 rolled types (equal) + 2 boss-signature pieces, duplicates allowed
	BossSignaturePieces = { "FUR-09", "FUR-18" },
	-- save safety (step 3 agent default): no new piece is created at this many owned pieces
	-- (Scrap / storage cap deferred by the user, row 111). Saves above it still load in full.
	GrantLimit = 400,
}
-- v5 (row 101, Simulator fix 1, USER RULING 2026-11-16 7:47 PM): Mythic lines 14-18 pts (was 16-22),
-- Transcendent 12-16 (was 16-22), so top pieces fit the 8 x GH cap and the 40-per-kind caps.
V4.FortuneAffectsRarity = false        -- rows 101/104
-- row 110 (v5, agent default, vetoable): the welcome Straw Cot + Scribe's Desk are FIXED at 8 points
-- (one player line: Straw Cot +4 Max HP, Scribe's Desk +2 Max MP) so they always fit the GH1 cap.
V4.WelcomePoints = 8
V4.WelcomeKinds = { ["FUR-01"] = "maxHp", ["FUR-06"] = "maxMp" }
V4.LockedRarityFallsToHighestOpen = true

-- row 92: caps and point prices (points per unit shown).
V4.CapPerGuildHallLevel = 8            -- total cap = 8 x GH (player AND enemy lines share it)
V4.KindCap = 40                        -- per bonus kind; enemy kinds have their own 40
V4.PerUnitPercentLimit = nil           -- 5% limit REMOVED completely (D29)
V4.PointPrice = {
	STR = 4, AGI = 4, DEX = 4, INT = 4, VIT = 4, LUK = 4,   -- per +1
	maxHp = 2,                                             -- per +1 HP (D26)
	maxMp = 4,                                             -- per +1 MP (D27)
	attack = 8, defense = 8,                               -- per +1 (v4, NOT 32)
	precision = 20, evasion = 20,                          -- per +1 pp (10 per +0.5 pp)
	skillPotency = 10,                                     -- per +1%
	healingOutput = 8,                                     -- per +1%
	debuffResist = 10,                                     -- per 1% less
	rtDelayResist = 12,                                    -- per 1% less
	collisionResist = 5, fallResist = 5,                   -- per 1% less
	collisionDamage = 4, fallDamage = 4,                   -- per +1%
	itemDamage = 8,                                        -- per +1%
}
-- row 102: maximum total from furniture per secondary kind (all below one tier-1 gear line).
V4.SecondaryMax = {
	precision = 2, evasion = 2, skillPotency = 4, healingOutput = 5, debuffResist = 4,
	rtDelayResist = 3, rtDelayResistWithHerbalRack = 5, collisionResist = 8, fallResist = 8,
	collisionDamage = 10, fallDamage = 10, itemDamage = 5,
}
-- row 102: shown value range of ONE basic line per rarity (Common, Uncommon, Rare, Epic,
-- Legendary). Mythic/Transcendent use 16-22 pt lines -> value = points / price.
V4.BasicLineValues = {
	primary = { Common = { 2, 3 }, Uncommon = { 4, 5 }, Rare = { 3, 4 }, Epic = { 4, 5 }, Legendary = { 4, 5 } },
	maxHp   = { Common = { 4, 6 }, Uncommon = { 7, 10 }, Rare = { 5, 8 }, Epic = { 8, 11 }, Legendary = { 7, 10 } },
	maxMp   = { Common = { 2, 3 }, Uncommon = { 3, 5 }, Rare = { 2, 4 }, Epic = { 4, 5 }, Legendary = { 3, 5 } },
	-- attack / defense: value = line points / 8 (row 102)
}
V4.RoundPointsToStep = true            -- row 101: points rounded to the line's step

-- row 93 + 103: the 9 furniture types and their pools. basic = all rarities (2 kinds -> 50/50 per
-- line); secondary = Epic+; signature = 50% of that type's secondary rolls; threshold = Mythic+.
V4.Types = {
	Bed           = { basic = { "maxHp" },          secondary = { "debuffResist", "healingOutput" },    threshold = { "stability" } },
	Plant         = { basic = { "maxHp", "LUK" },   secondary = { "debuffResist", "healingOutput" },    threshold = { "discoveryRadius" }, wall = true },
	Bookshelf     = { basic = { "INT" },            secondary = { "skillPotency", "debuffResist" },     threshold = { "interactRange" }, signature = "skillPotency" },
	DeskCandles   = { basic = { "maxMp" },          secondary = { "skillPotency", "itemDamage" },       threshold = { "itemRange" } },
	TrainingGear  = { basic = { "STR", "VIT" },     secondary = { "collisionDamage", "collisionResist" }, threshold = { "force" } },
	AgilityCourse = { basic = { "AGI" },            secondary = { "evasion", "fallResist" },            threshold = { "movement", "jump" }, signature = "evasion" },
	Target        = { basic = { "DEX" },            secondary = { "precision", "itemDamage" },          threshold = { "jump" }, thresholdIfRangeOn = "range", signature = "precision" },
	WeaponRack    = { basic = { "attack" },         secondary = { "precision", "collisionDamage" },     threshold = { "force" } },
	ArmourStand   = { basic = { "defense" },        secondary = { "rtDelayResist", "fallResist" },      threshold = { "stability" } },
}
V4.SignatureShare = 0.5                -- row 103

-- row 107: threshold lines. Always exactly +1 (-1 on enemy lines), no points, Mythic+ only.
V4.Threshold = {
	TotalCap = 2,                      -- FIXED FOREVER, player + enemy lines combined
	PerKindCap = 1,                    -- '+1 Movement' and '-1 enemy Movement' are the same kind
	Kinds = { "movement", "jump", "force", "stability", "discoveryRadius", "interactRange", "itemRange" },
	RangeEnabled = false,              -- weapon Range OFF at launch, both sides (D34/D50 switch)
	MovementOnlyFrom = "AgilityCourse",
	BossesAndElitesIgnoreEnemyLines = true,
	OffInPvP = true,
}
V4.ForbiddenKinds = { "fortune", "weaponRtDelay", "weightReduction", "ap", "ct", "rt", "speed", "startingRt", "channelTime", "passive", "skill" }

-- row 108: enemy lines.
V4.Enemy = {
	LineChance = 0.25,                 -- each rolled line: 75% player / 25% enemy (D41)
	Strength = 0.8,                    -- 80% of the player effect for the same points (D42)
	PriceMult = 1.25,                  -- enemy price = 1.25 x player price, round down, min 1
	KindCap = 40,
	FixedPiecesNeverEnemy = true,
	EliteBossMult = 0.5,               -- D46
	PvEOnly = true,
	Basic = {
		Bed = { "hpLoss" }, Plant = { "hpLoss", "LUK" }, Bookshelf = { "INT" }, DeskCandles = { "mpLoss" },
		TrainingGear = { "STR", "VIT" }, AgilityCourse = { "AGI" }, Target = { "DEX" },
		WeaponRack = { "attack" }, ArmourStand = { "defense" },
	},
	Secondary = {
		Bed = { "healingOutput" }, Plant = { "healingOutput" }, Bookshelf = { "skillPotency" },
		DeskCandles = { "itemDamage", "debuffResist" }, TrainingGear = { "collisionResist" },
		AgilityCourse = { "evasion", "fallResist" }, Target = { "precision" },
		WeaponRack = { "precision", "collisionDamage" }, ArmourStand = { "fallResist" },
	},
	SecondarySignature = { AgilityCourse = "evasion" },
	Threshold = {
		AgilityCourse = { "movement", "jump" }, Target = { "jump" }, -- Target 'range' only if RangeEnabled
		TrainingGear = { "force" }, WeaponRack = { "force" }, Bed = { "stability" }, ArmourStand = { "stability" },
	},
	-- points per unit of enemy weakening (normal enemy), max at the 40-pt kind cap
	PointPrice = {
		hpLoss = 2.5, mpLoss = 5,
		STR = 5, AGI = 5, DEX = 5, INT = 5, VIT = 5, LUK = 5, attack = 10, defense = 10,
		precision = 25, evasion = 25,          -- 12.5 per -0.5 pp
		skillPotency = 12.5, healingOutput = 10, debuffResist = 12.5,
		collisionResist = 6.25, fallResist = 6.25, collisionDamage = 5, itemDamage = 10,
	},
	Max = { hpLoss = 16, mpLoss = 8, precision = 1.5, evasion = 1.5, skillPotency = 3, healingOutput = 4,
		debuffResist = 3, collisionResist = 6, fallResist = 6, collisionDamage = 8, itemDamage = 4 },
	Floors = {
		primaryMin = 1,
		attackDefenseMaxLossPct = 0.25,    -- Simulator change 2 (7:02 PM)
		hpLossMaxPctOfMax = 0.15, bossHpLossMaxPctOfMax = 0.05, hpMin = 1, mpMin = 0,
		movementMin = 2, rangeMin = 1,
	},
	AiPlansWithFinalValues = true,         -- BUILD REQUIREMENT (AI rules 19/20/26)
}

-- row 91: rooms by Guild Hall level. Floor spot accepts = categories (Bed, Study, Training,
-- Martial, Special). Wall spots take any wall piece.
V4.Rooms = {
	{ id = "MainBedroom",     name = "Main Bedroom",      gh = 1,  floor = { { "Bed" } },                         wall = 1 },
	{ id = "GreatHall",       name = "Great Hall",        gh = 1,  floor = { { "Study", "Training", "Special" } }, wall = 2 },
	{ id = "Armoury",         name = "Armoury",           gh = 2,  floor = { { "Martial" } },                     wall = 0 },
	{ id = "TrainingYard",    name = "Training Yard",     gh = 3,  floor = { { "Training" } },                    wall = 0, outdoors = true },
	{ id = "GuestRoom",       name = "Guest Room",        gh = 4,  floor = { { "Bed" } },                         wall = 1 },
	{ id = "Office",          name = "Office",            gh = 5,  floor = { { "Study" } },                       wall = 1 },
	{ id = "TreasureRoom",    name = "Treasure Room",     gh = 6,  floor = { { "Special" } },                     wall = 0 },
	{ id = "DiningRoom",      name = "Dining Room",       gh = 7,  floor = { { "Special" } },                     wall = 1 },
	{ id = "StrategyRoom",    name = "Strategy Room",     gh = 8,  floor = { { "Study", "Martial", "Special" } }, wall = 0 },
	{ id = "Library",         name = "Library",           gh = 9,  floor = { { "Study" } },                       wall = 1 },
	{ id = "PracticeHall",    name = "Practice Hall",     gh = 10, floor = { { "Training" } },                    wall = 1 },
	{ id = "SecondGuestRoom", name = "Second Guest Room", gh = 10, floor = { { "Bed" } },                         wall = 0 },
}
V4.FloorTotals = { 2, 3, 4, 5, 6, 7, 8, 9, 10, 12 }
V4.WallTotals  = { 3, 3, 3, 4, 5, 5, 6, 6, 7, 8 }
V4.EveryBedCounts = true               -- D5: every placed bed counts; others once per name
V4.RoomNamesArePlaceholders = false    -- D24; the 12 names approved as FINAL (FUR-ROOM-NAMES, USER APPROVAL 2026-11-16 11:02 PM)

-- row 94: the 26-piece catalogue. type = bonus type (nil for fixed/looks-only); category = room
-- category (Bed/Study/Training/Martial/Special/Wall); fixed = fixed effect, no rarity, never
-- enemy lines; signature = always-present line (old point price toward the cap).
V4.Pieces = {
	{ id = "FUR-01", name = "Straw Cot",             type = "Bed",           category = "Bed",      source = "Shop", price = 150 },
	{ id = "FUR-02", name = "Oak Bed",               type = "Bed",           category = "Bed",      source = "Shop", price = 450, needGuildHall = 3, rarityStepBonus = 1 },
	{ id = "FUR-03", name = "Stone Hearth",          category = "Special",   fixed = { healingReceived = 0.02 }, source = "Shop", price = 200 },
	{ id = "FUR-04", name = "Herbal Rack",           category = "Special",   fixed = { rtDelayResist = 0.98 }, source = "Crafted", price = 250, craftAt = "Apothecary", mats = { mercury = 2 } },
	{ id = "FUR-05", name = "Padded Wall",           category = "Wall",      fixed = { collisionTaken = 0.97 }, source = "DungeonDrop" },
	{ id = "FUR-06", name = "Scribe's Desk",         type = "DeskCandles",   category = "Study",    source = "Shop", price = 150 },
	{ id = "FUR-07", name = "Arcane Lectern",        type = "Bookshelf",     category = "Study",    signature = { skillPotency = 1 },   source = "Shop", price = 400, needGuildHall = 4 },
	{ id = "FUR-08", name = "Star Chart",            type = "Target",        category = "Wall",     source = "DungeonDrop" },
	{ id = "FUR-09", name = "Tome Stack",            type = "Bookshelf",     category = "Study",    signature = { skillPotency = 1.5 }, source = "BossDrop" },
	{ id = "FUR-10", name = "Practice Dummy",        type = "TrainingGear",  category = "Training", source = "Shop", price = 300 },
	{ id = "FUR-11", name = "Balance Beam",          type = "AgilityCourse", category = "Training", source = "Shop", price = 300, needGuildHall = 5 },
	{ id = "FUR-12", name = "Target Board",          type = "Target",        category = "Training", source = "Crafted", price = 300, craftAt = "Blacksmith", mats = { mercury = 2 } },
	{ id = "FUR-13", name = "Meditation Mat",        type = "DeskCandles",   category = "Study",    source = "Crafted", price = 300, craftAt = "Runeforge", mats = { crystals = 1 } },
	{ id = "FUR-14", name = "Iron Training Weights", type = "TrainingGear",  category = "Training", source = "DungeonDrop" },
	{ id = "FUR-15", name = "Dodge Course",          type = "AgilityCourse", category = "Training", source = "DungeonDrop" },
	{ id = "FUR-16", name = "Lucky Coin Shrine",     category = "Special",   fixed = { fortune = 0.01 }, source = "Shop", price = 350 },
	{ id = "FUR-17", name = "Clover Planter",        type = "Plant",         category = "Wall",     source = "DungeonDrop" },
	{ id = "FUR-18", name = "Gilded Chest",          category = "Special",   fixed = { battleGold = 0.02 }, source = "BossDrop" },
	{ id = "FUR-19", name = "War Table",             category = "Special",   fixed = { dispatchFee = -5 }, source = "Shop", price = 500, needRank = 5 },
	{ id = "FUR-20", name = "Supply Shelf",          category = "Special",   fixed = { inventory = 5 }, source = "Shop", price = 400, notInShop = true },
	{ id = "FUR-21", name = "Trophy Pedestal",       category = "Martial",   looksOnly = true, source = "Rank32" },
	{ id = "FUR-22", name = "Guild Banner",          category = "Wall",      looksOnly = true, source = "GuildHall10" },
	{ id = "FUR-23", name = "Weapon Rack",           type = "WeaponRack",    category = "Martial",  source = "Shop", price = 350, needGuildHall = 2 },
	{ id = "FUR-24", name = "Armour Stand",          type = "ArmourStand",   category = "Martial",  source = "Shop", price = 350, needGuildHall = 2 },
	{ id = "FUR-25", name = "Candle Sconce",         type = "DeskCandles",   category = "Wall",     source = "Shop", price = 150 },
	{ id = "FUR-26", name = "Hanging Fern",          type = "Plant",         category = "Wall",     source = "Crafted", price = 200, craftAt = "Apothecary", mats = { mercury = 1 } },
}

-- rows 95 + 105: shop offers.
V4.Shop = {
	OffersPerType = 3,
	RefreshDaily = true,
	MaxRarity = "Rare",
	PriceMult = { Common = 1, Uncommon = 2, Rare = 4 },
	EachOfferBoughtOnce = true,
}

-- row 110 (v5 crafting, USER RULING 2026-11-16 7:44 PM; build step 4b). One recipe per rolled type + the
-- fixed pieces that lost their shop. Rolled pieces: rarity random (Common 40 / Uncommon 43 / Rare 17), capped at
-- Rare, Guild Hall gates apply, repeatable. Fixed pieces: once only. Supply Shelf stays unsold.
-- gold + mercury: basic 200 + 1, better (Oak Bed, Arcane Lectern, Weapon Rack, Armour Stand) 450 + 2,
-- fixed = old shop price + 1. Building names = BuildingService names.
V4.Craft = {
	Weights = { Common = 40, Uncommon = 43, Rare = 17 },
	MaxRarity = "Rare",
	Recipes = {
		Blacksmith = {
			{ id = "FUR-10", gold = 200, mercury = 1 }, { id = "FUR-12", gold = 200, mercury = 1 },
			{ id = "FUR-23", gold = 450, mercury = 2 }, { id = "FUR-24", gold = 450, mercury = 2 },
			{ id = "FUR-19", gold = 500, mercury = 1, once = true },
		},
		Runeforge = {
			{ id = "FUR-13", gold = 200, mercury = 1 }, { id = "FUR-07", gold = 450, mercury = 2 },
			{ id = "FUR-16", gold = 350, mercury = 1, once = true }, { id = "FUR-25", gold = 200, mercury = 1 },
		},
		Apothecary = {
			{ id = "FUR-04", gold = 250, mercury = 1, once = true }, { id = "FUR-26", gold = 200, mercury = 1 },
			{ id = "FUR-01", gold = 200, mercury = 1 }, { id = "FUR-02", gold = 450, mercury = 2 },
			{ id = "FUR-03", gold = 200, mercury = 1, once = true }, { id = "FUR-11", gold = 200, mercury = 1 },
		},
	},
}

-- rows 97 / D40: old-save conversion rarities (step 2 uses these).
V4.Migration = { ShopBought = "Common", CraftedDroppedBossGift = "Uncommon", NeverReroll = true, OverflowToStorage = true }

local V4_BY_ID: { [string]: any } = {}
for _, p in V4.Pieces do V4_BY_ID[p.id] = p end

function V4.Get(id: any): any
	if type(id) ~= "string" then return nil end
	return V4_BY_ID[id]
end

local function ghClamp(gh: number): number
	return math.clamp(math.floor(tonumber(gh) or 1), 1, 10)
end

function V4.RoomsFor(gh: number): { any }
	local l, out = ghClamp(gh), {}
	for _, r in V4.Rooms do if r.gh <= l then table.insert(out, r) end end
	return out
end
function V4.FloorSpots(gh: number): number return V4.FloorTotals[ghClamp(gh)] end
function V4.WallSpots(gh: number): number return V4.WallTotals[ghClamp(gh)] end
function V4.Beds(gh: number): number
	local n = 0
	for _, r in V4.RoomsFor(gh) do for _, s in r.floor do if s[1] == "Bed" then n += 1 end end end
	return n
end
function V4.CapFor(gh: number): number return V4.CapPerGuildHallLevel * ghClamp(gh) end
function V4.RarityOpen(rarity: string, gh: number): boolean
	local r = V4.Rarities[rarity]
	return r ~= nil and ghClamp(gh) >= r.gate
end

FurnitureData.V4 = deepFreeze(V4)

return table.freeze(FurnitureData)
