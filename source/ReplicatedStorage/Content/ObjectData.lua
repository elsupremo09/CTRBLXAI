-- ObjectData.lua
-- CTRBLXAI | Slice 5 -- Procedural Map Generation
--
-- Generated from CTRBLXAI.db objects_encounters table.
-- DO NOT EDIT MANUALLY -- regenerate from DB if rules change.

local ObjectData = {}

-- Objects (45)
-- -----------------------------------------

ObjectData.Objects = {}

ObjectData.Objects["Bear Trap"] = {
	id = "Bear Trap",
	category = "Hazard",
	tags = { "Trap", "Consumable" },
	passable = true,
	activation = "Triggered",
	triggerEvent = "Unit enters tile",
	primaryEffect = "Inflicts Pinned",
	uses = "Once",
	notes = "Removed after activation",
}

ObjectData.Objects["Spike Trap"] = {
	id = "Spike Trap",
	category = "Hazard",
	tags = { "Trap", "Consumable" },
	passable = true,
	activation = "Triggered",
	triggerEvent = "Unit enters tile",
	primaryEffect = "Deals physical damage and inflicts Bleed",
	uses = "Once",
	notes = "Removed after activation",
}

ObjectData.Objects["Snare Trap"] = {
	id = "Snare Trap",
	category = "Hazard",
	tags = { "Trap", "Consumable" },
	passable = true,
	activation = "Triggered",
	triggerEvent = "Unit enters tile",
	primaryEffect = "Inflicts Pinned and RT Delay",
	uses = "Once",
	notes = "Removed after activation",
}

ObjectData.Objects["Land Mine"] = {
	id = "Land Mine",
	category = "Hazard",
	tags = { "Trap", "Explosive" },
	passable = true,
	activation = "Triggered",
	triggerEvent = "Unit enters tile or Explosion",
	primaryEffect = "radius 1 Explosion (25% Max HP)",
	uses = "Once",
	notes = "Chain reactions allowed. Explosion elevation drop (-1) is owned by the EXPLOSION TAG, not this object (see terrain_effects 'Explosion').",
}

ObjectData.Objects["Bomb Barrel"] = {
	id = "Bomb Barrel",
	category = "Hazard",
	tags = { "Breakable", "Explosive" },
	passable = false,
	activation = "Triggered",
	triggerEvent = "Fire-tag attack, Explosion, or Destroyed",
	primaryEffect = "radius 1 Explosion (25% Max HP), destroys adjacent breakable bridges/walls",
	uses = "Once",
	notes = "Generated gap spans (Plank Bridge / Rocky Causeway / Drawbridge) are NOT breakable bridges (map_gen_rules 'Span Tile Protection'). Explosion elevation drop (-1) is owned by the EXPLOSION TAG, not this object (see terrain_effects 'Explosion' / open_decisions 'CTRBLXAI Explosion Tag').",
}

ObjectData.Objects["Oil Sluice"] = {
	id = "Oil Sluice",
	category = "Hazard",
	tags = { "Structure" },
	passable = false,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Creates Tar Pit in radius 2 area",
	uses = "Unlimited",
	notes = "Fire/Explosion detonates stored oil",
}

ObjectData.Objects["Steam Valve"] = {
	id = "Steam Valve",
	category = "Hazard",
	tags = { "Structure" },
	passable = false,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Creates Steam in radius 2 area",
	uses = "Unlimited",
	notes = "Battlefield control",
}

ObjectData.Objects["Stone Pillar"] = {
	id = "Stone Pillar",
	category = "Siege",
	tags = { "Heavy", "Breakable" },
	passable = false,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Falls in the direction opposite the interacting unit and becomes a 4-TILE-LONG Rocky span (fallen pillar = 4 tiles long × 1 tile wide; the standing pillar is 4 elevation levels HIGH, which is why its fall reaches 4 tiles) or crushes units on the landing tiles (70% Max HP, +100 RT, Pinned)",
	uses = "Once",
	notes = "Permanent terrain change. REVISED 2026-10-02 (user ruling): was a 3-tile bridge; now 4 long × 4 high. STANDING: Height 4 (4 elevation levels tall) — blocks movement and line of sight like a 4-high wall. FALLEN: 4 tiles long; span deck sits at the pillar's base-tile elevation; if a landing tile is 2+ levels higher than the base, the fall stops short there (the span ends on the previous tile; units on tiles it reached are still crushed). A 4-tile fall always reaches the far bank of any generated gap (max gap width 3). Crush unchanged: 70% Max HP (HP%-based, so boss HP% resistance applies), +100 RT, Pinned — now up to 4 tiles in a line instead of 3. The fallen span is NOT a protected generated span ('Span Tile Protection' does not apply). SPAWN (revised 2026-10-02 after user review): TOP = Highlands biome 10 and Mountain Pass region 10 (unchanged). Ruins biome 8 / region 8, Rocky region 8, Cave Chamber region 8 (unchanged). Added 2026-10-02: Castle biome 4, Corrupted biome 3, Castle Courtyard 4, Castle Interior 2, Village 3 (small settlements — kept), 'magic region' = Corrupted region 2 (kept) + Graveyard region 3 (user pick, Magic Circle tiles), 'big town' = new Town region 5. NOTE: shipped code places objects from the BIOME pool only — region-level weights take effect once object placement is region-aware (open_decisions 'Town region + region-level object weights — Dev wiring').",
	-- Structured spec (objects_encounters Stone Pillar row, revised 2026-10-02 user ruling) for
	-- the Stone Pillar fall/crush logic. NOTE: no object-Interact runtime exists yet
	-- (BattleVisualClient 'Interact' button is a disabled stub), so these fields are
	-- data-only until that system is built.
	standingHeight  = 4,       -- standing pillar = 4 elevation levels tall (blocks move + LoS)
	fallLength      = 4,       -- fallen pillar = 4 tiles long ...
	fallWidth       = 1,       -- ... x 1 tile wide
	fallenTerrain   = "Rocky", -- fallen span deck terrain, at the pillar's base-tile elevation
	fallStopRise    = 2,       -- a landing tile 2+ levels above the base stops the fall short there
	crushMaxTargets = 4,       -- up to 4 units in a line (was 3)
	crushMaxHpPct   = 0.70,    -- crush: 70% Max HP (HP%-based; boss HP% resistance applies)
	crushRtDelay    = 100,     -- crush: +100 RT
	crushStatus     = "Pinned",-- crush: Pinned
	protectedSpan   = false,   -- fallen pillar is NOT a protected generated span (map_gen_rules)
}

ObjectData.Objects["Ice Spike"] = {
	id = "Ice Spike",
	category = "Siege",
	tags = { "Structure", "Ice" },
	passable = false,
	activation = "Passive",
	triggerEvent = nil,
	primaryEffect = "Blocks movement and line of travel",
	uses = "Until Destroyed",
	notes = "Can melt from Fire",
}

ObjectData.Objects["Ballista"] = {
	id = "Ballista",
	category = "Siege",
	tags = { "Structure" },
	passable = false,
	activation = "Interact (Consumes Action)",
	interactRT = 100,
	triggerEvent = nil,
	primaryEffect = "Fires a penetrating bolt (250% Weapon Damage) in a chosen CARDINAL direction",
	uses = "Once per turn",
	notes = "Uses operator stats. 'Once per turn' = per-unit per-turn (resets at the start of that unit's own turn, like Guard); Slice 5 object-runtime needs a per-unit-per-turn usage tracker.",
}

ObjectData.Objects["Catapult"] = {
	id = "Catapult",
	category = "Siege",
	tags = { "Structure" },
	passable = false,
	activation = "Interact (Consumes Action)",
	interactRT = 100,
	triggerEvent = nil,
	primaryEffect = "Fires a projectile (200% Weapon Damage, Cross AOE) within Range 6",
	uses = "Unlimited",
	notes = "Splash damages objects. Cross AOE = radius-1 cross / plus-shape, 5 tiles (TargetingService.GetCrossTiles).",
}

ObjectData.Objects["War Banner"] = {
	id = "War Banner",
	category = "Aura",
	tags = { "Structure" },
	passable = false,
	activation = "Passive",
	triggerEvent = nil,
	primaryEffect = "Allies within Radius 3 gain +15% to all primary stats",
	uses = "Passive",
	notes = "Removed if destroyed",
}

ObjectData.Objects["Cursed Statue"] = {
	id = "Cursed Statue",
	category = "Aura",
	tags = { "Structure" },
	passable = false,
	activation = "Passive",
	triggerEvent = nil,
	primaryEffect = "Units within radius 3 suffer +20% to base RT",
	uses = "Passive",
	notes = "Removed if destroyed. +20% base RT = those units act SLOWER. Passive aura affects BOTH sides within radius 3 (per 2026-10-03 ruling: all passive auras are two-sided).",
}

ObjectData.Objects["Rally Flag"] = {
	id = "Rally Flag",
	category = "Aura",
	tags = { "Structure" },
	passable = false,
	activation = "Interact (Consumes Action)",
	interactRT = 150,
	triggerEvent = nil,
	primaryEffect = "Allies gain +1 Move and +1 Jump for 1500 CT",
	uses = "Once",
	notes = "Does not stack",
}

ObjectData.Objects["Star Axis"] = {
	id = "Star Axis",
	category = "Aura",
	tags = { "Structure" },
	passable = false,
	activation = "Interact (Consumes Action)",
	interactRT = 150,
	triggerEvent = nil,
	primaryEffect = "Friendly units gain +20% Spell Damage for 1500 CT",
	uses = "Once",
	notes = "Does not stack",
}

ObjectData.Objects["Burning Cauldron"] = {
	id = "Burning Cauldron",
	category = "Aura",
	tags = { "Structure" },
	passable = false,
	activation = "Interact (Consumes Action)",
	interactRT = 150,
	triggerEvent = nil,
	primaryEffect = "Friendly units gain +20% Physical Damage for 1500 CT",
	uses = "Once",
	notes = "Does not stack",
}

ObjectData.Objects["War Horn"] = {
	id = "War Horn",
	category = "Aura",
	tags = { "Structure" },
	passable = false,
	activation = "Interact (Consumes Action)",
	interactRT = 150,
	triggerEvent = nil,
	primaryEffect = "Friendly units gain -15% to base RT for 1500 CT",
	uses = "Once",
	notes = "Does not stack. -15% base RT = act FASTER (a buff). Name reused from the War Horn weapon archetype (different system); model 'War Horn' in ServerStorage.",
}

ObjectData.Objects["Runed Boulder"] = {
	id = "Runed Boulder",
	category = "Aura",
	tags = { "Structure" },
	passable = false,
	activation = "Interact (Consumes Action)",
	interactRT = 150,
	triggerEvent = nil,
	primaryEffect = "Friendly units gain +10% Attack and +10% Defense for 1500 CT",
	uses = "Once",
	notes = "Does not stack",
}

ObjectData.Objects["Treasure Chest"] = {
	id = "Treasure Chest",
	category = "Exploration",
	tags = { "Container" },
	passable = false,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Random gold, equipment, materials and runes",
	uses = "Once",
	notes = "—",
}

ObjectData.Objects["Mimic"] = {
	id = "Mimic",
	category = "Exploration",
	tags = { "Monster" },
	passable = false,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Reveals Mimic enemy with ×3 loot rate",
	uses = "Once",
	notes = "Initially appears as Treasure Chest",
}

ObjectData.Objects["Cursed Chest"] = {
	id = "Cursed Chest",
	category = "Exploration",
	tags = { "Shrine" },
	passable = false,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Random treasure; inflicts Weakened (3000 CT)",
	uses = "Once",
	notes = "—",
}

ObjectData.Objects["Healing Spring"] = {
	id = "Healing Spring",
	category = "Exploration",
	tags = { "Spring" },
	passable = true,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Fully restores HP",
	uses = "Once",
	notes = "—",
}

ObjectData.Objects["Magic Spring"] = {
	id = "Magic Spring",
	category = "Exploration",
	tags = { "Spring" },
	passable = true,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Fully restores MP",
	uses = "Once",
	notes = "—",
}

ObjectData.Objects["Campfire"] = {
	id = "Campfire",
	category = "Exploration",
	tags = { "Camp" },
	passable = true,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Restore 30% HP and MP",
	uses = "Once",
	notes = "—",
}

ObjectData.Objects["Blood Fountain"] = {
	id = "Blood Fountain",
	category = "Exploration",
	tags = { "Training" },
	passable = false,
	activation = "Interact (Consumes Action)",
	interactRT = 150,
	triggerEvent = nil,
	primaryEffect = "Grant Regeneration to all allies (MAP-WIDE)",
	uses = "Once",
	notes = "all allies = MAP-WIDE (every allied unit regardless of distance).",
}

ObjectData.Objects["Astrolabe"] = {
	id = "Astrolabe",
	category = "Exploration",
	tags = { "Shrine" },
	passable = false,
	activation = "Interact (Consumes Action)",
	interactRT = 400,
	triggerEvent = nil,
	primaryEffect = "Single use. Reduce current RT of all allied units (MAP-WIDE) by 200.",
	uses = "Once",
	notes = "all allied units = MAP-WIDE.",
}

ObjectData.Objects["Potion Desk"] = {
	id = "Potion Desk",
	category = "Exploration",
	tags = { "Shrine" },
	passable = false,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Single use. Fully recharge the interacting unit's equipped consumables.",
	uses = "Once",
	notes = "PARKED: depends on consumable charge-refill (Slice 8 Guild Base) — inert until that system exists. Scope resolved 2026-10-03: interacting unit only (not map-wide). Uses default Interact RT per G1 (round(Modified Base RT x 0.10)) — no explicit RT.",
}

ObjectData.Objects["Crystal Ball"] = {
	id = "Crystal Ball",
	category = "Exploration",
	tags = { "NPC" },
	passable = true,
	activation = "Interact (Free)",
	triggerEvent = nil,
	primaryEffect = "Reveals all Hidden Treasures",
	uses = "Unlimited",
	notes = "—",
}

ObjectData.Objects["Eye of the Magi"] = {
	id = "Eye of the Magi",
	category = "Exploration",
	tags = { "Arcane" },
	passable = true,
	activation = "Interact (Consumes Action)",
	interactRT = 150,
	triggerEvent = nil,
	primaryEffect = "Attacks two random opponents for 40% of their max HP each.",
	uses = "Once per turn",
	notes = "40% of each target's OWN max HP (per-target). 'Once per turn' = per-unit per-turn (same tracker as Ballista).",
}

ObjectData.Objects["Black Market"] = {
	id = "Black Market",
	category = "Exploration",
	tags = { "Shop" },
	passable = false,
	activation = "Interact (Free)",
	triggerEvent = nil,
	primaryEffect = "Opens shop containing six fixed discounted high-tier items",
	uses = "Unlimited",
	notes = "Shop inventory fixed for the battle",
}

ObjectData.Objects["Idol of Fortune"] = {
	id = "Idol of Fortune",
	category = "Event",
	tags = { "Shrine" },
	passable = false,
	activation = "Interact (Free)",
	triggerEvent = nil,
	primaryEffect = "Improved item drop rates until battle ends",
	uses = "Once",
	notes = "Does not stack",
}

ObjectData.Objects["Fountain of Fortune"] = {
	id = "Fountain of Fortune",
	category = "Event",
	tags = { "Shrine" },
	passable = false,
	activation = "Interact (Consumes Action)",
	interactRT = 150,
	triggerEvent = nil,
	primaryEffect = "Fortune +50% to all allies (MAP-WIDE) for 1500 CT",
	uses = "Once",
	notes = "all allies = MAP-WIDE.",
}

ObjectData.Objects["Tavern"] = {
	id = "Tavern",
	category = "Event",
	tags = { "Settlement" },
	passable = false,
	activation = "Interact (Free)",
	triggerEvent = nil,
	primaryEffect = "Increase quest rewards by 50% after battle",
	uses = "Once",
	notes = "Does not stack",
}

ObjectData.Objects["Necro Tome Stand"] = {
	id = "Necro Tome Stand",
	category = "Event",
	tags = { "Shrine" },
	passable = false,
	activation = "Passive",
	triggerEvent = "Unit dies within radius 3",
	primaryEffect = "Passive. Whenever a unit dies within radius 3, inflict dark damage to ALL opponents equal to 10% of the DYING unit's max HP.",
	uses = "Passive",
	notes = "10% of the DYING unit's max HP, dealt to that unit's opponents. Passive aura is two-sided: a death on EITHER side within radius 3 triggers damage to the dying unit's opponents (2026-10-03 ruling).",
}

ObjectData.Objects["Cover of Darkness"] = {
	id = "Cover of Darkness",
	category = "Event",
	tags = { "Shrine" },
	passable = false,
	activation = "Interact (Free)",
	triggerEvent = nil,
	primaryEffect = "Blind all enemies within Radius 5 for 2000 CT",
	uses = "Once",
	notes = "—",
}

ObjectData.Objects["Dragon Utopia"] = {
	id = "Dragon Utopia",
	category = "Event",
	tags = { "Encounter" },
	passable = false,
	activation = "Interact (Free)",
	triggerEvent = nil,
	primaryEffect = "Summons 4-6 Dragons with ×3 loot rate",
	uses = "Once",
	notes = "High-risk encounter",
}

ObjectData.Objects["Chaos Statue"] = {
	id = "Chaos Statue",
	category = "Event",
	tags = { "NPC" },
	passable = true,
	activation = "Interact (Free)",
	triggerEvent = nil,
	primaryEffect = "Generates one optional quest",
	uses = "Once",
	notes = "—",
}

ObjectData.Objects["Angel Statue"] = {
	id = "Angel Statue",
	category = "Event",
	tags = { "Settlement" },
	passable = false,
	activation = "Interact (Free)",
	triggerEvent = nil,
	primaryEffect = "Grants Flight for 1500 CT",
	uses = "Once",
	notes = "—",
}

ObjectData.Objects["Obelisk"] = {
	id = "Obelisk",
	category = "Event",
	tags = { "Shrine" },
	passable = false,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "All enemies are inflicted +300 RT Delay",
	uses = "Once",
	notes = "—",
}

ObjectData.Objects["Forge"] = {
	id = "Forge",
	category = "Event",
	tags = { "Structure" },
	passable = false,
	activation = "Interact (Consumes Action)",
	interactRT = 150,
	triggerEvent = nil,
	primaryEffect = "Summon one Ballista or Catapult on a chosen tile within radius 3 of the object",
	uses = "Once",
	notes = nil,
}

ObjectData.Objects["Witch Hut"] = {
	id = "Witch Hut",
	category = "Event",
	tags = { "NPC" },
	passable = true,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Double EXP until battle ends; inflict Weakened (3000 CT)",
	uses = "Once",
	notes = "Risk/Reward",
}

ObjectData.Objects["Mysterious Boulder"] = {
	id = "Mysterious Boulder",
	category = "Event",
	tags = { "Settlement" },
	passable = false,
	activation = "Interact (Consumes Action)",
	interactRT = 200,
	triggerEvent = nil,
	primaryEffect = "Single use. Roll a random debuff, then inflict it on ALL enemies.",
	uses = "Once",
	notes = nil,
}

ObjectData.Objects["Glow Crystal"] = {
	id = "Glow Crystal",
	category = "Event",
	tags = { "Shrine" },
	passable = false,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Double all experience gained at end of battle.",
	uses = "Once",
	notes = "ACTIVE (Slice 6 item 3, 2026-10-07): player activation sets a battle flag; ProgressionService doubles end-of-battle XP once. Uses default Interact RT per G1 (round(Modified Base RT x 0.10)) — no explicit RT.",
}

ObjectData.Objects["Pandora's Box"] = {
	id = "Pandora's Box",
	category = "Event",
	tags = { "Shrine" },
	passable = false,
	activation = "Interact (Consumes Action)",
	interactRT = 50,
	triggerEvent = nil,
	primaryEffect = "Triggers a random map object effect, drawn from the FULL pool including harmful effects (traps/explosions can backfire on the user's side).",
	uses = "Once",
	notes = "RT 50 flat regardless of triggered effect. Roll pool = all triggerable map-object effects; triggered effect centers on the Pandora's Box tile. Passive-only / terrain-reshape effects that cannot sensibly be invoked by Interact are excluded from the roll pool (Designer note).",
}

ObjectData.Objects["Swan Pond"] = {
	id = "Swan Pond",
	category = "Event",
	tags = { "Spring" },
	passable = false,
	activation = "Interact (Consumes Action)",
	interactRT = 150,
	triggerEvent = nil,
	primaryEffect = "Single use. Remove all debuffs from all allies (MAP-WIDE).",
	uses = "Once",
	notes = "all allies = MAP-WIDE (2026-10-03 ruling).",
}

-- Battle Conditions (14)
-- -----------------------------------------

ObjectData.BattleConditions = {}

ObjectData.BattleConditions["Clear"] = {
	id = "Clear",
	description = "Calm battlefield.",
	passiveEffect = "None.",
	periodicEffect = "None.",
	interval = nil,
	notes = "Baseline condition.",
}

ObjectData.BattleConditions["Rain"] = {
	id = "Rain",
	description = "Rain drenches the battlefield.",
	passiveEffect = "Fire Damage −25%; Water Damage +25%.",
	periodicEffect = "Every 300 CT, all Burning effects become Steam.",
	interval = 300,
	notes = "Promotes Water strategies.",
}

ObjectData.BattleConditions["Strong Wind"] = {
	id = "Strong Wind",
	description = "Powerful winds sweep the battlefield.",
	passiveEffect = "Wind Damage +25%.",
	periodicEffect = "Every 300 CT, remove one random Airborne Effect.",
	interval = 300,
	notes = "Limits airborne hazards.",
}

ObjectData.BattleConditions["Heatwave"] = {
	id = "Heatwave",
	description = "Intense heat dries the battlefield.",
	passiveEffect = "Fire Damage +20%; Water Damage −20%.",
	periodicEffect = "Every 300 CT, reduce all Wet durations by 300 CT.",
	interval = 300,
	notes = "Promotes Fire strategies.",
}

ObjectData.BattleConditions["Dark Eclipse"] = {
	id = "Dark Eclipse",
	description = "Darkness engulfs the battlefield.",
	passiveEffect = "Light Damage −25%; Dark Damage +25%; Recruitment Chance −20%.",
	periodicEffect = "None.",
	interval = nil,
	notes = "Holy attacks are weakened.",
}

ObjectData.BattleConditions["Holy Aurora"] = {
	id = "Holy Aurora",
	description = "Holy light shines over the battlefield.",
	passiveEffect = "Light Damage +25%; Dark Damage −25%.",
	periodicEffect = "Every 300 CT, Undead units take 5% Max HP Light Damage.",
	interval = 300,
	notes = "Strong anti-undead condition.",
}

ObjectData.BattleConditions["Wild Growth"] = {
	id = "Wild Growth",
	description = "Nature rapidly overtakes the battlefield.",
	passiveEffect = "None.",
	periodicEffect = "Every 500 CT, randomly apply Vines to 15-25% of battlefield terrain without vine.",
	interval = 500,
	notes = "Existing Vines are unaffected.",
}

ObjectData.BattleConditions["Mana Storm"] = {
	id = "Mana Storm",
	description = "Magical energy floods the battlefield.",
	passiveEffect = "None.",
	periodicEffect = "Every 500 CT, all units restore 10% Max MP and gain Mana Burn for 300 CT.",
	interval = 500,
	notes = "Encourages frequent spellcasting while increasing its cost.",
}

ObjectData.BattleConditions["Thunderstorm"] = {
	id = "Thunderstorm",
	description = "Lightning repeatedly strikes elevated targets.",
	passiveEffect = "None.",
	periodicEffect = "Every 500 CT, strike one random unit occupying the highest elevation: 20% Max HP Light Damage (lightning) and lower struck tile by 1 elevation.",
	interval = 500,
	notes = "Random among tied highest-elevation occupants.",
}

ObjectData.BattleConditions["Meteor Storm"] = {
	id = "Meteor Storm",
	description = "Meteors periodically bombard marked locations.",
	passiveEffect = "None.",
	periodicEffect = "Every 500 CT, mark 1–3 occupied tiles; after 300 CT deal 30% Max HP Fire Damage to target tile and 15% to adjacent tiles; lower target tile by 1.",
	interval = 500,
	notes = "Markers are visible.",
}

ObjectData.BattleConditions["Volcanic Eruptions"] = {
	id = "Volcanic Eruptions",
	description = "Magma erupts throughout the battlefield.",
	passiveEffect = "None.",
	periodicEffect = "Every 500 CT, mark 3–5 cross-shaped areas; after 300 CT deal 15% Max HP Fire Damage, transform to Molten when possible (otherwise Burning), increase impacted tile elevation by 1.",
	interval = 500,
	notes = "Markers are visible.",
}

ObjectData.BattleConditions["Earthquake"] = {
	id = "Earthquake",
	description = "Violent tremors reshape the battlefield.",
	passiveEffect = "None.",
	periodicEffect = "Every 500 CT, randomly alter 20–40% of map tiles by −2 to +2 elevation; units on changed tiles suffer +150 RT Delay.",
	interval = 500,
	notes = "Permanently reshapes terrain.",
}

ObjectData.BattleConditions["Severe Hail"] = {
	id = "Severe Hail",
	description = "Freezing hail blankets the battlefield.",
	passiveEffect = "None.",
	periodicEffect = "Every 300 CT, target 10–20% of traversable tiles; Liquid becomes Ice, others gain Frozen; units take 15% occupying affected tiles take Max HP Water Damage.",
	interval = 300,
	notes = "Uses terrain/effect rules.",
}

ObjectData.BattleConditions["Hunger Virus"] = {
	id = "Hunger Virus",
	description = "A magical plague spreads across the battlefield.",
	passiveEffect = "Every 300 CT, living units lose 5% Max HP; Basic Attacks heal attacker for 20% damage dealt.",
	periodicEffect = "None.",
	interval = 300,
	notes = "Encourages aggressive combat.",
}

return ObjectData
