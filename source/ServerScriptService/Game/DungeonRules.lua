--!strict
-- DungeonRules.lua
-- CTRBLXAI | Dungeon mode — every Dungeon number and formula, ONE place. (Build step 1, 2026-11-13)
--
-- Server-only (ARC-003): the client receives finished numbers, never these tables.
-- Pure data + pure functions (DAT-001/002/003). Only require: RenownRules (no requires itself).
--
-- LOCKED DATA, copied from CTRBLXAI.db (USER RULINGS 2026-11-13 4:24 / 4:36 / 5:43 / 5:49 / 6:19 PM).
-- The design DB is the single source of truth; do not tune numbers here.
--   project_rules 258 / guild_facilities 87  facility level table L1-L10
--   project_rules 260  map shape (4 wide, N floors + boss row, 4 paths, fixed rows)
--   project_rules 261  node weights
--   project_rules 262  placement rules (enforced in DungeonMap.lua)
--   project_rules 263  dungeon level (+1 per floor), growing drop multiplier
--   project_rules 268  dungeon Merchant (x1.25, Legendary 1% from L9, refills x1.5)
--   guild_facilities 86 unlock at Guild Hall L6
--   USER RULING 6:19 PM: Legendary shop markup x8.0; Event nodes play as normal battles
--     until the 10 approved events are built (build step 7).
--   Build step 3 (2026-11-13): wipeout gold, choice refresh and biome order moved here from
--     DungeonService (Tester W2); NodeDropChance adds the Elite/Boss loot bonus.

local RenownRules = require(script.Parent:WaitForChild("RenownRules"))

local DungeonRules = {}

local ALL_BIOMES = -1 -- L10 "all biomes"

-- Stages ruling (2026-11-15 1:42 AM, project_rules 258/277): floors no longer depend on the facility
-- level; each level has its allowed difficulties (up to maxTier: 1 Easy, 2 Medium, 3 Hard) and max stages.
local function lvl(choices: number, maxTier: number, maxStages: number, biomes: number, good: number, bonus: number,
	relics: { string }, relicRate: number, restHeal: number)
	return table.freeze({
		choices = choices, maxTier = maxTier, maxStages = maxStages, biomes = biomes,
		eventGoodPct = good, eventBadPct = 100 - good,
		eliteBossLootBonusPct = bonus,
		relicRarities = table.freeze(relics), relicRatePct = relicRate, -- used from build step 8
		restHealPct = restHeal,
	})
end

local C, U, R, E, L = "Common", "Uncommon", "Rare", "Epic", "Legendary"

DungeonRules.Data = table.freeze({
	MaxLevel = 10,
	-- Dungeon party (step 7b, project_rules 258/265/267; USER RULINGS 2026-11-14 10:13-10:30 AM):
	PartyCaps = table.freeze({ 7, 7, 7, 8, 8, 8, 9, 9, 9, 10 }), -- by facility level
	DeployMax = 7,       -- only 7 fight per battle; the rest wait on the bench (bench EXP)
	BringInsPerRest = 1, -- Edit party: at most 1 unit brought in per Rest room (Sim v7)
	UnlockGuildHallLevel = 6,           -- guild_facilities 86
	AllBiomes = ALL_BIOMES,
	-- project_rules 258 / guild_facilities 87
	Levels = table.freeze({
		-- Rest heal L1-L3 +15 (5-floor maps have one Rest row; USER RULING 2026-11-13 6:54 PM, rule 258)
		-- choices 1,2,2,3,3,3,4,4,5,5; Medium from L3, Hard from L6; stage 2 from L4, stage 3 from L8.
		lvl(1, 1, 1, 2,  50, 0,  { C }, 6, 45),
		lvl(2, 1, 1, 3,  52, 3,  { C }, 7, 45),
		lvl(2, 2, 1, 4,  54, 6,  { C, U }, 8, 50),
		lvl(3, 2, 2, 5,  56, 8,  { C, U }, 9, 35),
		lvl(3, 2, 2, 6,  58, 11, { C, U, R }, 10, 40),
		lvl(3, 3, 2, 7,  60, 14, { C, U, R }, 11, 40),
		lvl(4, 3, 2, 8,  62, 17, { C, U, R, E }, 12, 45),
		lvl(4, 3, 3, 9,  64, 19, { C, U, R, E }, 13, 45),
		lvl(5, 3, 3, 10, 66, 22, { C, U, R, E, L }, 14, 50),
		lvl(5, 3, 3, ALL_BIOMES, 70, 25, { C, U, R, E, L }, 15, 50),
	}),
	-- Difficulty tiers (project_rules 276/277, 2026-11-15): stored on the card as the OLD difficulty number
	-- (Easy 2 / Medium 3 / Hard 5) so RenownRules.QuestLevel / QuestKind keep working; floors per stage.
	Tiers = table.freeze({
		table.freeze({ word = "Easy",   difficulty = 2, floors = 8 }),
		table.freeze({ word = "Medium", difficulty = 3, floors = 12 }),
		table.freeze({ word = "Hard",   difficulty = 5, floors = 15 }),
	}),
	RestRowEvery = 4,                                  -- fixed Rest rows N, N-4, N-8 ... (rule 260)
	StageLevelBonus = table.freeze({ 0, 3, 6 }),        -- battle level + by stage (rule 263)
	StageGoldMult = table.freeze({ 1.0, 1.25, 1.5 }),   -- battle gold x by stage (rule 263)
	StageBringIns = 1,                                 -- bring-ins allowed at the start of stages 2/3 (rule 265)
	MaxStages = 3,
	-- project_rules 260
	MapWidth = 4,
	MapPaths = 4,
	-- project_rules 261 (random rows). Order is fixed so seeded rolls are deterministic.
	NodeWeights = table.freeze({
		table.freeze({ type = "Battle",   weight = 45 }),
		-- "?" room (USER RULING 2026-11-15 10:15 / 10:17 AM, project_rules 261): Event and Mystery MERGED into
		-- one "?" room (internal type "Mystery", "?" icon) with their combined weight 20 (= 20.8% of 96).
		-- On entry it becomes one of MysteryOutcomes (Event / Battle / Treasure / Merchant / Rest / Elite).
		table.freeze({ type = "Mystery",  weight = 20 }),
		table.freeze({ type = "Elite",    weight = 10 }),
		table.freeze({ type = "Rest",     weight = 10 }),
		table.freeze({ type = "Merchant", weight = 7 }),
		table.freeze({ type = "Treasure", weight = 4 }),
		-- Escape room REMOVED (USER RULING 2026-11-13 11:36 PM): Rest rooms are the full-loot exit.
		-- Its weight 4 is spread proportionally (picks are normalised), i.e. Battle 46.9 / Event 20.8 /
		-- Elite 10.4 / Rest 10.4 / Merchant 7.3 / Treasure 4.2 %.
	}),
	-- USER RULING 6:19 PM: until events are built, an Event node is played as a Battle (shown as
	-- Event on the map since 2026-11-14 2:30 AM).
	EventsBuilt = true, -- Dungeon build step 7a (2026-11-14): Event rooms play the 10 approved events (rule 272)
	-- project_rules 272 / 275: the 10 events (approved 2026-11-14 10:19 AM). good = counts as Good for the
	-- facility good/bad odds (mixed counts as Good). Order fixed for seeded picks.
	Events = table.freeze({
		table.freeze({ id = "EV-01", good = true }),  table.freeze({ id = "EV-02", good = true }),
		table.freeze({ id = "EV-03", good = true }),  table.freeze({ id = "EV-04", good = true }),
		table.freeze({ id = "EV-05", good = true }),  table.freeze({ id = "EV-06", good = true }),
		table.freeze({ id = "EV-07", good = true }),  table.freeze({ id = "EV-08", good = true }),
		table.freeze({ id = "EV-09", good = false }), table.freeze({ id = "EV-10", good = false }),
		-- EV-11..16 (approved 2026-11-15 1:42 AM, rule 272). Mixed counts as Good. EV-16 is now Altar of Change
		-- (10:08 AM); kept Bad (it can lower a tier; agent default). EV-11 needs a race/doctrine in the party.
		table.freeze({ id = "EV-11", good = true, needsKin = true }), table.freeze({ id = "EV-12", good = true }),
		table.freeze({ id = "EV-13", good = true }), table.freeze({ id = "EV-14", good = true }),
		table.freeze({ id = "EV-15", good = true }), table.freeze({ id = "EV-16", good = false }),
	}),
	-- Event numbers (DRAFT per rule 272, Simulator v7 checked).  Pct = % of max HP (and MP for heals).
	Ev = table.freeze({
		CacheRolls = 1, SpringHealPct = 20, FlaskRevivePct = 30, PeddlerPriceMult = 1.0,
		PouchGold = 150, BuryMercury = 1, ShrineCost = 100, ShrineBonus = 0.25,
		AltarHurtPct = 15, AltarRolls = 2, DoorTreasurePct = 60, DoorRolls = 1, DoorGold = 200,
		GambleBet = 200, GambleWinPct = 50, GamblePayout = 400, TunnelAllPct = 10, TunnelOnePct = 25,
		CutpurseGoldPct = 25,
		-- EV-11..16 (rule 272, approved 2026-11-15; numbers DRAFT per Simulator v9)
		KinHealPct = 15, KinRolls = 1, DoctrineStatPct = 10,
		SmithLevelUp = 5,
		BarterMercuryForCrystal = 10, BarterCrystalForMercury = 6, BarterGoldForMercury = 600,
		CampHealPct = 35, CampRevivePct = 35, -- EV-14 Campfire (USER RULING 2026-11-15 10:01 AM): heal OR full free refill
		ForgeMaxRarity = "Epic", -- Simulator v9 fix 4: reforge only up to Epic
		AltarOptions = 3, -- EV-16 Altar of Change (10:08 AM): 3 same-kind replacements, Mutation Bench tier odds
	}),
	-- Rarity steps for Smith's Wager / Forge of Chance (Exalted sits between Epic and Legendary).
	GearRarityOrder = table.freeze({ "Common", "Uncommon", "Rare", "Epic", "Exalted", "Legendary" }),
	-- EV-16 Shifting Hall mutators RETIRED (USER RULING 2026-11-15 10:01 AM): replaced by Altar of Change.
	-- "?" room (project_rules 261, 10:17 AM): what it becomes when entered. Never a Boss. Order fixed for
	-- seeded rolls. A "?" that becomes Rest is a full Rest room (heal, Edit party, full-loot leave).
	MysteryOutcomes = table.freeze({
		table.freeze({ type = "Event",    weight = 50 }),
		table.freeze({ type = "Battle",   weight = 20 }),
		table.freeze({ type = "Treasure", weight = 10 }),
		table.freeze({ type = "Merchant", weight = 8 }),
		table.freeze({ type = "Rest",     weight = 7 }),
		table.freeze({ type = "Elite",    weight = 5 }),
	}),
	MerchantBuilt = true, -- Dungeon build step 6 (2026-11-14): Mystery -> Merchant is a real Merchant now
	-- project_rules 268: 6 slots = 3 consumables (Apothecary pool) + 3 gear; gear rarity odds per slot (%).
	MerchantConsumableSlots = 3,
	MerchantGearSlots = 3,
	MerchantGearOdds = table.freeze({
		table.freeze({ rarity = "Common", weight = 30 }), table.freeze({ rarity = "Uncommon", weight = 30 }),
		table.freeze({ rarity = "Rare", weight = 22 }), table.freeze({ rarity = "Epic", weight = 12 }),
		table.freeze({ rarity = "Exalted", weight = 5 }), table.freeze({ rarity = "Legendary", weight = 1 }),
	}),
	-- project_rules 263: growing drop multiplier on losable loot (battle gear/cards, Boss materials)
	DropStart = 1.5,
	DropStepPerBattle = 0.25,           -- each battle node cleared; an Elite counts as 1 step
	DropCap = 2.5,
	BaseDropChance = 0.05,              -- loot_progression 13
	MaxDropChance = 0.95,
	-- project_rules 268 + 6:19 PM ruling
	MerchantMarkup = 1.25,              -- x the normal Merchant price
	MerchantLegendaryChance = 0.01,     -- per item, from facility L9
	MerchantLegendaryMinLevel = 9,      -- below L9 the 1% goes to Common
	LegendaryShopMarkup = 8.0,          -- economy_framework 15 (Exalted x6.0 -> Legendary x8.0)
	RefillPriceMult = 1.5,              -- x Apothecary price (Q9)
	-- project_rules 264: early escape
	EarlyEscapeGoldKeep = 0.75,
	-- project_rules 264: a wipeout follows the existing defeat rule (keep EXP + 50% gold)
	WipeoutGoldKeep = 0.5,
	-- project_rules 269 / guild_facilities 15: choices reroll on the Merchant's 5-completed-battle counter
	ChoiceRefreshBattles = 5,
	-- Biome unlock order for "N biomes" (project_rules 258 gives a count, not an order). DEV DEFAULT
	-- (user accepted 2026-11-13): the quest board's order (QuestGenerator ALL_BIOMES).
	-- RELICS (Dungeon build step 8; project_rules 271 APPROVED 2026-11-14 10:32 AM, text rule 275).
	-- Run-only, no duplicates, no cap. Sources: T = Treasure, E = Elite, B = Boss, Ev = good Event outcome.
	-- Relic rolls are NOT boosted by the drop rate, Fortune, the Elite/Boss bonus or the Shrine.
	Relics = table.freeze({
		table.freeze({ id = "RL-01", name = "Heartstone",        rarity = "Common",    src = "TEBV", text = "Your party's Max HP is 5% higher." }),
		table.freeze({ id = "RL-02", name = "Gilded Purse",      rarity = "Common",    src = "TEBV", text = "Battles drop 10% more gold." }),
		table.freeze({ id = "RL-03", name = "Warm Bedroll",      rarity = "Common",    src = "TEBV", text = "Rest rooms heal 10% more." }),
		table.freeze({ id = "RL-04", name = "Quickstep Boots",   rarity = "Uncommon",  src = "TEB",  text = "Your party starts each battle with RT 20 lower." }),
		table.freeze({ id = "RL-05", name = "Refill Satchel",    rarity = "Uncommon",  src = "TEB",  text = "At battle start, one equipped consumable gains +1 charge." }),
		table.freeze({ id = "RL-06", name = "Lucky Charm",       rarity = "Common",    src = "TEBV", text = "Fortune is 5% higher in this dungeon." }),
		table.freeze({ id = "RL-07", name = "Weatherward Cloak", rarity = "Common",    src = "TEBV", text = "Your party takes 10% less damage from weather." }),
		table.freeze({ id = "RL-08", name = "Hunter's Trophy",   rarity = "Uncommon",  src = "TB",   text = "Elites drop 1 extra item." }),
		table.freeze({ id = "RL-09", name = "Second Wind",       rarity = "Rare",      src = "TEB",  text = "Once per run, a unit that falls gets up with 50% HP." }),
		table.freeze({ id = "RL-10", name = "Iron Resolve",      rarity = "Rare",      src = "TEB",  text = "Your party takes 8% less damage." }),
		table.freeze({ id = "RL-11", name = "Mana Font",         rarity = "Rare",      src = "TEB",  text = "Your party regains 10% MP after each battle." }),
		table.freeze({ id = "RL-12", name = "Field Medic's Kit", rarity = "Epic",      src = "EB",   text = "After each battle, the unit with the lowest HP heals 15%." }),
		table.freeze({ id = "RL-13", name = "Champion's Banner", rarity = "Epic",      src = "EB",   text = "Your party deals 5% more damage to Elites and Bosses." }),
		table.freeze({ id = "RL-14", name = "Warding Sigil",     rarity = "Epic",      src = "B",    text = "Your party resists the first bad status effect each battle." }),
		table.freeze({ id = "RL-15", name = "Crown of the Deep", rarity = "Legendary", src = "B",    text = "Your party's Max HP is 10% higher and damage taken is 5% lower." }),
		-- RL-16..RL-22 (stages ruling 2026-11-15 1:42 AM, rule 271). kind: "Minor" | "Major" | "Curse".
		-- RL-18 is a Curse: never rolled on its own (src ""); it always comes with RL-17 (pairs below).
		table.freeze({ id = "RL-16", name = "Ogre's Belt",        rarity = "Common",    src = "TEV",  kind = "Minor", text = "Your party gains 5 + 10% STR." }),
		table.freeze({ id = "RL-17", name = "War Banner",         rarity = "Epic",      src = "EB",   kind = "Major", minParty = 8, text = "8 units can fight each battle. Enemies have 10% more Defense." }),
		table.freeze({ id = "RL-18", name = "Leaden Shackles",    rarity = "Epic",      src = "",     kind = "Curse", text = "Your party starts each battle Slowed for 2000 CT." }),
		table.freeze({ id = "RL-19", name = "Berserker's Oath",   rarity = "Rare",      src = "EB",   kind = "Major", text = "Your party gains +1 AP but deals 25% less damage." }),
		table.freeze({ id = "RL-20", name = "Seven-League Boots", rarity = "Rare",      src = "TE",   kind = "Major", text = "Your party gains +1 Movement." }),
		table.freeze({ id = "RL-21", name = "Featherfall Crest",  rarity = "Epic",      src = "B",    kind = "Major", text = "Your party has Flight in every battle this run." }),
		table.freeze({ id = "RL-22", name = "Lich's Phylactery",  rarity = "Epic",      src = "B",    kind = "Major", text = "Your party becomes Undead. Dungeon heals still heal them." }),
		-- RL-23..RL-60 (relics v2, user ruling 2026-11-15 12:21 PM; numbers = Simulator v11 + auto-accepted 12:38 PM).
		-- NOT BUILT (need code): RL-23 Prospector's Map, RL-24 Mimic's Bargain, RL-42 Vanguard Oath, RL-48 Sage's
		-- Hourglass, RL-51 Scholar's Creed -> left out of this table so they can never drop.
		table.freeze({ id = "RL-25", name = "Longshot Fletching", rarity = "Rare",      src = "TEB", kind = "Major", text = "Your party's attack range is +1." }),
		table.freeze({ id = "RL-26", name = "Steady Footing",     rarity = "Common",    src = "TEV", kind = "Minor", text = "Your party gains +1 Stability." }),
		table.freeze({ id = "RL-27", name = "Far Focus",          rarity = "Uncommon",  src = "TEV", kind = "Minor", text = "Your party's skill range is +1." }),
		table.freeze({ id = "RL-28", name = "Mana Well",          rarity = "Rare",      src = "TEB", kind = "Major", text = "Your party regains 20% MP at the start of each battle." }),
		table.freeze({ id = "RL-29", name = "Blood Well",         rarity = "Epic",      src = "EB",  kind = "Major", text = "Your party heals 10% HP at the start of each battle." }), -- v11: 20% -> 10%
		table.freeze({ id = "RL-30", name = "Bottomless Satchel", rarity = "Rare",      src = "TEB", kind = "Major", text = "Every consumable gains 1 charge at the start of each battle." }),
		table.freeze({ id = "RL-31", name = "Withering Mist",     rarity = "Uncommon",  src = "TEV", kind = "Minor", text = "Enemies lose 10% HP at the start of each battle." }),
		table.freeze({ id = "RL-32", name = "Hex Bag",            rarity = "Common",    src = "TEV", kind = "Minor", text = "Enemies start each battle with a random debuff." }),
		table.freeze({ id = "RL-33", name = "Lucky Totem",        rarity = "Common",    src = "TEV", kind = "Minor", text = "Your party starts each battle with a random buff." }),
		table.freeze({ id = "RL-34", name = "Quiet Paths",        rarity = "Epic",      src = "TE",  kind = "Major", text = "Mystery rooms never hold a battle." }),
		table.freeze({ id = "RL-35", name = "Emberproof Hide",    rarity = "Rare",      src = "TEB", kind = "Major", text = "Your party can't be Burned." }),
		table.freeze({ id = "RL-36", name = "Antidote Charm",     rarity = "Rare",      src = "TEB", kind = "Major", text = "Your party can't be Poisoned." }),
		table.freeze({ id = "RL-37", name = "Clotting Salve",     rarity = "Rare",      src = "TEB", kind = "Major", text = "Your party can't Bleed." }),
		table.freeze({ id = "RL-38", name = "Diver's Lung",       rarity = "Uncommon",  src = "TEV", kind = "Minor", text = "Your party can't Drown." }),
		table.freeze({ id = "RL-39", name = "Arcane Seal",        rarity = "Rare",      src = "TEB", kind = "Major", text = "Your party is immune to Mana Burn." }),
		table.freeze({ id = "RL-40", name = "Rustward Oil",       rarity = "Uncommon",  src = "TEV", kind = "Minor", text = "Your party can't be Corroded." }),
		table.freeze({ id = "RL-41", name = "Bond of Kin",        rarity = "Uncommon",  src = "TE",  kind = "Minor", text = "Your summons have double HP." }),
		-- Boss relics (kind "Boss"): Boss pick option a only, any facility level, shown as Legendary.
		table.freeze({ id = "RL-43", name = "Chains of the Deep", rarity = "Legendary", src = "",    kind = "Boss",  text = "Enemies move 1 less. Your party's range is -1 (min 1)." }),
		table.freeze({ id = "RL-44", name = "Tyrant's Hourglass", rarity = "Legendary", src = "",    kind = "Boss",  text = "Enemies act slower. Your party takes 10% more damage." }), -- v11: RT +100 -> +50
		table.freeze({ id = "RL-45", name = "Reaver's Pact",      rarity = "Legendary", src = "",    kind = "Boss",  text = "Your party deals 20% more damage. Fortune is 35% lower." }),
		table.freeze({ id = "RL-46", name = "Glass Crown",        rarity = "Legendary", src = "",    kind = "Boss",  text = "More damage and speed, but 10% less HP." }), -- v11: -20% -> -10% (DRAFT text)
		table.freeze({ id = "RL-47", name = "Hollow Throne",      rarity = "Legendary", src = "",    kind = "Boss",  text = "Loot grows higher, but Rests heal 10% less." }), -- v11: -50% -> -10% (DRAFT text)
		table.freeze({ id = "RL-49", name = "Pikeman's Creed",    rarity = "Common",    src = "TEV", kind = "Minor", text = "All spear users gain +1 range, foes too." }),
		table.freeze({ id = "RL-50", name = "Archer's Creed",     rarity = "Common",    src = "TEV", kind = "Minor", text = "All bow users gain +1 range, foes too." }),
		table.freeze({ id = "RL-52", name = "Duelist's Creed",    rarity = "Uncommon",  src = "TEV", kind = "Minor", text = "All sword users gain 10% Precision, foes too." }),
		table.freeze({ id = "RL-53", name = "Iron Skin Oil",      rarity = "Common",    src = "TEV", kind = "Minor", text = "Your party gains 5% Defense." }),
		table.freeze({ id = "RL-54", name = "Swift Sigil",        rarity = "Rare",      src = "TEB", kind = "Major", text = "Your party acts a little faster every turn." }),
		table.freeze({ id = "RL-55", name = "Ironjaw Mantle",     rarity = "Uncommon",  src = "TEV", kind = "Minor", text = "Your party can't be Feared or Taunted." }),
		table.freeze({ id = "RL-56", name = "Stargazer Lens",     rarity = "Common",    src = "TEV", kind = "Minor", text = "Your party sees 1 tile farther." }),
		-- Random curses (never rolled alone): 20% of Major relics come with one (take both / leave both).
		table.freeze({ id = "RL-57", name = "Leaden Crown",       rarity = "Epic",      src = "",    kind = "Curse", text = "Your party jumps 1 less." }),
		table.freeze({ id = "RL-58", name = "Hunger Curse",       rarity = "Epic",      src = "",    kind = "Curse", text = "Your party starts each battle with 5% less MP." }),
		table.freeze({ id = "RL-59", name = "Coin-Eater",         rarity = "Epic",      src = "",    kind = "Curse", text = "You keep 15% less gold from each win." }),
		table.freeze({ id = "RL-60", name = "Black Lantern",      rarity = "Epic",      src = "",    kind = "Curse", text = "Enemies have 10% more HP." }),
	}),
	-- Curse pairs (rule 271): the Major relic always comes with its curse. RL-17 War Banner -> RL-18 Leaden Shackles.
	RelicCursePairs = table.freeze({ ["RL-17"] = "RL-18" }),
	-- Random curse pool + chance (relics v2): a Major relic without a fixed pair has 20% to carry one.
	RelicCursePool = table.freeze({ "RL-18", "RL-57", "RL-58", "RL-59", "RL-60" }),
	RelicCurseChancePct = 20,
	RelicRarityOrder = table.freeze({ "Common", "Uncommon", "Rare", "Epic", "Legendary" }),
	RelicRarityWeights = table.freeze({ Common = 50, Uncommon = 30, Rare = 13, Epic = 6, Legendary = 1 }),
	RelicSourceMult = table.freeze({ T = 3, E = 2, V = 0.5 }), -- x the level's relic rate R; Boss = 1 guaranteed
	RelicBossTierBumpPct = 25,
	-- Effect numbers (rule 271). Pct = percent.
	Relic = table.freeze({
		HeartstoneHpPct = 5, PurseGoldPct = 10, BedrollRestPct = 10, BootsRt = 20, SatchelCharges = 1,
		CharmFortune = 0.05, CloakWeatherPct = 10, TrophyItems = 1, SecondWindHpPct = 50,
		IronDamagePct = 8, FontMpPct = 10, MedicHpPct = 15, BannerDamagePct = 5,
		CrownHpPct = 10, CrownDamagePct = 5,
		OgreStrFlat = 5, OgreStrPct = 10, BannerDeployBonus = 1, BannerEnemyDefPct = 10, ShacklesSlowCt = 2000,
		OathApBonus = 1, OathDamagePct = 25, LeagueMoveBonus = 1,
		-- relics v2 (Simulator v11 numbers, auto-accepted 2026-11-15 12:38 PM)
		LongshotRange = 1, StabilityBonus = 1, FarFocusRange = 1, ManaWellMpPct = 20, BloodWellHpPct = 10,
		BottomlessCharges = 1, MistHpPct = 10, MistBossHpPct = 5, KinSummonHpMult = 2,
		ChainsEnemyMove = -1, ChainsPartyRange = -1, TyrantEnemyRt = 50, TyrantDamageTakenPct = 10,
		ReaverDamagePct = 20, ReaverFortunePct = 35, GlassDamagePct = 15, GlassMoveBonus = 1, GlassHpPct = 10,
		ThroneDropCap = 3.0, ThroneRestPct = 10, CreedRange = 1, DuelistPrecision = 0.10, IronSkinDefPct = 5,
		SwiftRt = 30, StargazerRadius = 1, LeadenJump = -1, HungerMpPct = 5, CoinEaterGoldPct = 15, LanternHpPct = 10,
		HexDebuffs = table.freeze({ "Slow", "Weakened", "Enfeebled", "Addled", "Armor Break", "Unsteady", "Blind", "Silence", "Crippled", "Debuff Res Down" }),
		TotemBuffs = table.freeze({ "Haste", "Regeneration", "Empowered", "Focused", "Stoneskin", "Fleetfoot", "Precise", "Fortunate", "Armored", "Debuff Res Up" }),
		-- Creed weapon groups (agent default: spear = Spear + Lance; bow = Longbow + Great Bow + Crossbow; sword = Sword + Greatsword + Rapier + Flameberge)
		SpearWeapons = table.freeze({ ["WPN-SPEAR"] = true, ["WPN-LANCE"] = true }),
		BowWeapons = table.freeze({ ["WPN-LONGBOW"] = true, ["WPN-GREATBOW"] = true, ["WPN-CROSSBOW"] = true }),
		SwordWeapons = table.freeze({ ["WPN-SWORD"] = true, ["WPN-GREATSWORD"] = true, ["WPN-RAPIER"] = true, ["WPN-FLAMEBERGE"] = true }),
		Immunities = table.freeze({
			["RL-35"] = table.freeze({ "Burn" }), ["RL-36"] = table.freeze({ "Poison", "Venom" }), ["RL-37"] = table.freeze({ "Bleed" }),
			["RL-38"] = table.freeze({ "Drowning" }), ["RL-39"] = table.freeze({ "Mana Burn" }), ["RL-40"] = table.freeze({ "Corroded", "Corroded Lesser" }),
			["RL-55"] = table.freeze({ "Fear", "Taunted" }),
		}),
	}),
	BiomeOrder = table.freeze({
		"Plains", "Forest", "Desert", "Swamp", "Highlands",
		"Tundra", "Volcano", "Cave", "Ruins", "Castle", "Corrupted",
	}),
})

local D = DungeonRules.Data

local function toInt(v: any, fallback: number): number
	if type(v) ~= "number" or v ~= v then return fallback end
	return math.floor(v)
end

--- Level-table row for a facility level (clamped 1-10).
function DungeonRules.Level(facilityLevel: number): any
	return D.Levels[math.clamp(toInt(facilityLevel, 1), 1, D.MaxLevel)]
end

--- Tier entry for an old difficulty number (2/3/5) or a tier index (1-3). Old saved cards with any
--- other difficulty map to the nearest tier (1->Easy, 4->Hard).
function DungeonRules.TierFor(difficulty: number): any
	local d = toInt(difficulty, 2)
	for _, t in D.Tiers do if t.difficulty == d then return t end end
	if d <= 2 then return D.Tiers[1] elseif d == 3 then return D.Tiers[2] end
	return D.Tiers[3]
end

--- Floors (rows before the boss row) for a difficulty (old number 2/3/5): 8 / 12 / 15 (rule 260).
function DungeonRules.Floors(difficulty: number): number
	return DungeonRules.TierFor(difficulty).floors
end

--- Tiers a facility level may roll (rule 258): { tier entries }.
function DungeonRules.AllowedTiers(facilityLevel: number): { any }
	local n = DungeonRules.Level(facilityLevel).maxTier
	local out = {}
	for i = 1, math.clamp(n, 1, #D.Tiers) do table.insert(out, D.Tiers[i]) end
	return out
end

--- Max stages for a facility level (rule 258: 1 / 2 from L4 / 3 from L8).
function DungeonRules.MaxStages(facilityLevel: number): number
	return math.clamp(DungeonRules.Level(facilityLevel).maxStages, 1, D.MaxStages)
end

--- Stage helpers (rule 263/277). stage 1..3.
function DungeonRules.StageGoldMult(stage: number?): number
	return D.StageGoldMult[math.clamp(toInt(stage, 1), 1, D.MaxStages)]
end
function DungeonRules.StageLevelBonus(stage: number?): number
	return D.StageLevelBonus[math.clamp(toInt(stage, 1), 1, D.MaxStages)]
end
--- Map seed for a stage (rule 277: run seed + stage). Stage 1 = the card seed (old saves unchanged).
function DungeonRules.StageSeed(cardSeed: number, stage: number?): number
	local s = math.clamp(toInt(stage, 1), 1, D.MaxStages)
	return (toInt(cardSeed, 0) + (s - 1) * 7919) % 2147483647
end

--- Is row r a fixed Rest row on an N-floor map? (rule 260: N, N-4, N-8 ...)
function DungeonRules.IsFixedRestRow(r: number, floors: number): boolean
	return r >= 1 and r <= floors and (floors - r) % D.RestRowEvery == 0
end

--- Node type a player actually plays (Event stands in as Battle until events are built).
function DungeonRules.PlayedType(nodeType: string): string
	if nodeType == "Event" and not D.EventsBuilt then return "Battle" end
	return nodeType
end

--- What a Mystery room becomes (project_rules 261). Seeded by run seed + room position, so the same
--- room always gives the same result (rejoin-safe). Returns the room TYPE (Event still plays as Battle).
function DungeonRules.ResolveMystery(runSeed: number, row: number, col: number, quiet: boolean?): string
	local seed = (toInt(runSeed, 0) * 131 + toInt(row, 0) * 7919 + toInt(col, 0) * 104729 + 17) % 2147483647
	local roll = Random.new(seed):NextNumber() * 100
	local t = "Battle"
	for _, o in D.MysteryOutcomes do
		roll -= o.weight
		if roll < 0 then t = o.type break end
	end
	if t == "Merchant" and not D.MerchantBuilt then t = "Treasure" end
	if quiet and (t == "Battle" or t == "Elite") then t = "Event" end -- RL-34 Quiet Paths (relics v2)
	return t
end

--- Battle level: quest-level formula + 1 per floor above the first + the stage bonus (+3 / +6), kept
--- 1-99 (project_rules 263). stage nil = 1 (no bonus).
function DungeonRules.BattleLevel(rank: number, difficulty: number, floor: number, jitter: number?, stage: number?): number
	local base = RenownRules.QuestLevel(rank, difficulty, jitter)
	return RenownRules.ClampEnemyLevel(base + math.max(0, toInt(floor, 1) - 1) + DungeonRules.StageLevelBonus(stage))
end

--- Growing drop multiplier after `battlesCleared` battle nodes this run (project_rules 263).
--- bonus = Lucky Shrine (EV-05) extra, still capped at DropCap (rule 272). nil = 0.
function DungeonRules.DropMultiplier(battlesCleared: number, bonus: number?, cap: number?): number
	local n = math.max(0, toInt(battlesCleared, 0))
	local extra = if type(bonus) == "number" and bonus > 0 then bonus else 0
	return math.min(if type(cap) == "number" and cap > D.DropCap then cap else D.DropCap, D.DropStart + n * D.DropStepPerBattle + extra)
end

--- Drop cap for a run: x3.0 with RL-47 Hollow Throne, else nil (= DropCap 2.5). relics v2.
function DungeonRules.RunDropCap(run: any): number?
	if run and table.find(run.relics or {}, "RL-47") and not (run.relicUsed and run.relicUsed["RL-47"]) then return D.Relic.ThroneDropCap end
	return nil
end

--- Gear/card drop chance per enemy in a dungeon battle: min(95%, 5% x multiplier x Fortune).
function DungeonRules.DropChance(battlesCleared: number, fortuneMult: number?): number
	local f = if type(fortuneMult) == "number" and fortuneMult > 0 then fortuneMult else 1
	return math.min(D.MaxDropChance, D.BaseDropChance * DungeonRules.DropMultiplier(battlesCleared) * f)
end

--- Scale on a dungeon battle's victory loot rolls (gear/cards): the growing multiplier, and on Elite /
--- Boss rooms x (1 + the facility level's Elite+Boss loot bonus %) (project_rules 258 / 263).
--- USER RULING 2026-11-13 8:24 PM: the multiplier scales the victory roll count (RewardService 1-2 rolls),
--- and on Elite/Boss rooms the bonus multiplies on top (rolls x multiplier x (1 + bonus)). The rarity step is
--- RarityFortuneBonus below (9:24 PM ruling).
function DungeonRules.LootRollScale(battlesCleared: number, kind: string, facilityLevel: number, bonus: number?, cap: number?): number
	local s = DungeonRules.DropMultiplier(battlesCleared, bonus, cap)
	if kind == "Elite" or kind == "Boss" then
		s *= 1 + DungeonRules.Level(facilityLevel).eliteBossLootBonusPct / 100
	end
	return s
end

--- Elite/Boss rarity step (project_rules 258/263, USER RULING 2026-11-13 9:24 PM, option a): the facility
--- level's Elite+Boss loot bonus (0..25%) is ADDED to the normalized Fortune of the rarity roll for loot rolls
--- from Elite and Boss rooms. Same mechanism as Fortune, no new rarity table, no extra cap. 0 elsewhere.
function DungeonRules.RarityFortuneBonus(kind: string, facilityLevel: number): number
	if kind == "Elite" or kind == "Boss" then
		return DungeonRules.Level(facilityLevel).eliteBossLootBonusPct / 100
	end
	return 0
end

--- Legendary chance per dungeon Merchant item (0 below facility L9; that 1% rolls Common instead).
function DungeonRules.MerchantLegendaryChance(facilityLevel: number): number
	return if toInt(facilityLevel, 1) >= D.MerchantLegendaryMinLevel then D.MerchantLegendaryChance else 0
end

--- Gear rarity for one dungeon Merchant slot (project_rules 268). roll = 1..100. Below facility L9
--- the Legendary 1% becomes Common.
function DungeonRules.MerchantGearRarity(roll: number, facilityLevel: number): string
	local acc = 0
	for _, e in D.MerchantGearOdds do
		acc += e.weight
		if roll <= acc then
			if e.rarity == "Legendary" and DungeonRules.MerchantLegendaryChance(facilityLevel) <= 0 then return "Common" end
			return e.rarity
		end
	end
	return "Common"
end

--- RELICS (step 8). Seeded relic roll for one source ("T" Treasure, "E" Elite, "B" Boss, "V" Event).
--- held = { [relicId] = true }. Returns a relic id or nil. Not boosted by drop rate / Fortune / bonuses.
--- Rarity: weights 50/30/13/6/1 over the level's unlocked tiers; a roll on a locked tier drops one
--- tier; Boss: guaranteed, 25% chance of +1 tier. If the rolled tier has no relic left for the source,
--- lower tiers are tried, then higher unlocked tiers (agent default, logged in the step 8 report).
-- opts (2026-11-15 relics v2): partySize (War Banner minParty gate), kind ("Boss" = Boss-type only; nil = any
-- non-Boss-type), noChance (skip the room chance: Boss pick normal option), exclude (extra ids to skip, e.g. the other Boss pick option).
function DungeonRules.RollRelic(seed: number, source: string, facilityLevel: number, held: { [string]: boolean }, chanceMult: number?, opts: any?): string?
	local rng = Random.new(toInt(seed, 0) % 2147483647)
	local lv = DungeonRules.Level(facilityLevel)
	if source ~= "B" and not (opts and opts.noChance) then
		local chance = lv.relicRatePct / 100 * (D.RelicSourceMult[source] or 0) * (tonumber(chanceMult) or 1) -- chanceMult: nil (Fog mutator retired)
		if rng:NextNumber() >= chance then return nil end
	end
	-- relics v2: Boss-type relics ignore tiers (any facility level), uniform among the ones not held.
	if opts and opts.kind == "Boss" then
		local pool: { string } = {}
		for _, rl in D.Relics do
			if rl.kind == "Boss" and not held[rl.id] and not (opts.exclude and opts.exclude[rl.id]) then table.insert(pool, rl.id) end
		end
		return if #pool > 0 then pool[rng:NextInteger(1, #pool)] else nil
	end
	local unlocked: { [string]: boolean } = {}
	for _, r in lv.relicRarities do unlocked[r] = true end
	local order = D.RelicRarityOrder
	local total = 0
	for _, r in order do total += D.RelicRarityWeights[r] end
	local roll = rng:NextNumber() * total
	local idx = 1
	for i, r in order do
		roll -= D.RelicRarityWeights[r]
		if roll < 0 then idx = i break end
	end
	if (source == "B" or (opts and opts.tierBump)) and rng:NextNumber() * 100 < D.RelicBossTierBumpPct then idx = math.min(#order, idx + 1) end -- tierBump: Boss pick option b (rule 271)
	while idx > 1 and not unlocked[order[idx]] do idx -= 1 end
	-- Search the rolled tier, then lower tiers, then (so a guaranteed Boss relic is never lost while one
	-- is left) higher UNLOCKED tiers. Agent default, step 8.
	local tryOrder: { number } = {}
	for i = idx, 1, -1 do table.insert(tryOrder, i) end
	for i = idx + 1, #order do if unlocked[order[i]] then table.insert(tryOrder, i) end end
	for _, t in tryOrder do
		local pool: { string } = {}
		for _, rl in D.Relics do
			local o = opts or {}
			local kindOk = if o.kind == "Boss" then rl.kind == "Boss" else rl.kind ~= "Boss"
			if o.noCurse and rl.kind == "Curse" then kindOk = false end -- Boss pick option b (Tester FAIL fix)
			local partyOk = rl.minParty == nil or (tonumber(o.partySize) or 0) >= rl.minParty
			if rl.rarity == order[t] and not held[rl.id] and kindOk and partyOk and not (o.exclude and o.exclude[rl.id])
				and (string.find(rl.src, source, 1, true) or (o.kind == "Boss" and rl.kind == "Boss")) then
				table.insert(pool, rl.id)
			end
		end
		if #pool > 0 then return pool[rng:NextInteger(1, #pool)] end
	end
	return nil
end

--- EV-16 mutators are RETIRED (2026-11-15 10:01 AM). Kept as a stub that always returns nil so an old
--- saved run with a mutator id loads safely and the mutator is ignored.
function DungeonRules.MutatorDef(_id: string?): any
	return nil
end

--- Next gear rarity (Smith's Wager / Forge), or nil if there is none in the step list.
function DungeonRules.NextGearRarity(r: string?): string?
	local o = D.GearRarityOrder
	for i, x in o do if x == r then return o[i + 1] end end
	return nil
end

--- Forge of Chance can reforge this rarity (only up to Epic: Common/Uncommon/Rare -> next; Simulator v9 fix 4).
function DungeonRules.CanForge(r: string?): boolean
	local o = D.GearRarityOrder
	local cap = table.find(o, D.Ev.ForgeMaxRarity) or 4
	local i = table.find(o, r :: any)
	return i ~= nil and i < cap
end

--- Relic definition by id (nil if unknown).
function DungeonRules.RelicDef(id: string): any
	for _, rl in D.Relics do if rl.id == id then return rl end end
	return nil
end

--- Dungeon party cap for a facility level (project_rules 258).
function DungeonRules.PartyCap(facilityLevel: number): number
	local l = math.clamp(math.floor(tonumber(facilityLevel) or 1), 1, D.MaxLevel)
	return D.PartyCaps[l] or D.DeployMax
end

return table.freeze(DungeonRules)
