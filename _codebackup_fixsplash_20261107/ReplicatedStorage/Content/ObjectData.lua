-- ObjectData.lua
-- CTRBLXAI | Slice 5 -- Procedural Map Generation
--
-- Generated from CTRBLXAI.db objects_encounters table.
-- DO NOT EDIT MANUALLY -- regenerate from DB if rules change.

local ObjectData = {}

-- Objects (67)
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

-- Poison Trap object (2026-10-25): the vehicle that makes SKL-POISON-TRAP work via the
-- proven createsObject trap pipeline (previously the skill was authored but unwired).
-- All values are the skill's AUTHORED numbers (Venom Strength 2; RT delay base 30 from
-- rtDelayFormula round(30 + 0.10*L) — the 0.10*L term is omitted as negligible, max +2 at
-- L20, flagged). DB DIVERGENCE: the authoritative objects_encounters DB row is Designer-
-- owned (docs, read-only here) and must be added to match this source object.
ObjectData.Objects["Poison Trap"] = {
	id = "Poison Trap",
	category = "Hazard",
	tags = { "Trap", "Consumable" },
	passable = true,
	activation = "Triggered",
	triggerEvent = "Unit enters tile",
	primaryEffect = "Inflicts Poison + Venom (Strength 2) and applies RT Delay",
	uses = "Once",
	venomStrength = 2,
	rtDelay = 30,
	notes = "Skill-placed (SKL-POISON-TRAP). Invisible ambush trap, enemy-only trigger via ownerSide, removed after activation.",
}

ObjectData.Objects["Spike Trap"] = {
	id = "Spike Trap",
	category = "Hazard",
	tags = { "Trap" },
	passable = true,
	activation = "Triggered",
	triggerEvent = "Unit enters tile",
	primaryEffect = "Deals 10% of Max HP physical damage and inflicts Bleed",
	damagePct = 0.10,
	uses = "Unlimited",
	notes = "Persistent area-denial hazard. Entry-triggered: re-springs on EACH crossing onto the tile (merely standing on it does not re-trigger). Persists until battle end and is NOT destructible/removable — the one reusable step-on hazard. Repeat crossings reapply Bleed per the existing StatusService Bleed reapply behavior. Damage 10% Max HP, Physical (authoritative DB value).",
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
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
	category = "Obstacle",
	tags = { "OBS", "Blocker", "Not-Landable", "Breakable", "Blocks-LoS", "Ice" },
	passable = false,
	activation = nil,
	triggerEvent = nil,
	primaryEffect = "Impassable ICE blocker on normal-height ground; blocks movement and direct line of sight.",
	uses = "Until Destroyed",
	notes = "ICE-SPIKE BLOCKER (reclassified 2026-10-17, user ruling): now an OBS-blocker-class object that behaves exactly like OBS Blocker (non-interactable; excluded from the point-of-interest glow; exempt from the V5 interaction-adjacency validation) PLUS a Fire weakness. A permanent wall: impassable to all, blocks direct line of sight, pushable, and breakable. Takes 3 hits from any source to destroy, OR is INSTANTLY destroyed in one hit by any Fire-tagged (Fire-element) attack regardless of remaining hits. Clearing (break/push) reverts the tile to normal passable ground. Still spawns via map generation in icy regions (RegionData weights unchanged) AND going forward via skills. First of a planned family of skill-placed blocker objects.",
	-- Standing height in elevation levels -- used by buildBlockers (blocker.height)
	-- and height-aware LoS. A low wall-height cluster (mirrors OBS Blocker).
	standingHeight = 3,
	hitsToDestroy  = 3,  -- breaks after 3 hits from any source (like OBS Blocker)
	nativeStability = 3, -- flat native Stability for Push: Distance = max(0, Force-3) (like OBS Blocker)
	-- Reactive per-object weakness: a Fire-element attack destroys it in ONE hit regardless of
	-- remaining hp. Read by ObjectEffectService.ApplyObjectHit. First reusable instance of the
	-- instantKillTags field; the skill-placed blocker family extends this (e.g. Earth Column = Water).
	instantKillTags = { "Fire" },
}

ObjectData.Objects["Ballista"] = {
	id = "Ballista",
	category = "Siege",
	tags = { "Structure" },
	passable = false,
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
	activation = "Interact (Consumes Action)",
	interactRT = 100,
	triggerEvent = nil,
	primaryEffect = "Fires a projectile (200% Weapon Damage, Cross AOE) within Range 6",
	uses = "Once per turn",  -- USER RULING 2026-10-30 6:20 PM (project_rules 242): every siege object, once per unit per turn
	notes = "Splash damages objects. Cross AOE = radius-1 cross / plus-shape, 5 tiles (TargetingService.GetCrossTiles).",
}

ObjectData.Objects["War Banner"] = {
	id = "War Banner",
	category = "Aura",
	tags = { "Structure" },
	passable = false,
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	passable = false,  -- USER RULING 2026-10-30 (project_rules 241): blocks its tile; used via Interact from an adjacent tile.
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	passable = false,  -- USER RULING 2026-10-30 (project_rules 241): blocks its tile; used via Interact from an adjacent tile.
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	passable = false,  -- USER RULING 2026-10-30 (project_rules 241): blocks its tile; used via Interact from an adjacent tile.
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	passable = false,  -- USER RULING 2026-10-30 (project_rules 241): blocks its tile; used via Interact from an adjacent tile.
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	passable = false,  -- USER RULING 2026-10-30 (project_rules 241): blocks its tile; used via Interact from an adjacent tile.
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-11-06 12:23 PM (DB objects_encounters 'Tavern', re-added): replaces the old
	-- "free, +50% quest rewards" Tavern. Breakable 3 hits (project_rules 241), no Salvager's Cap roll.
	hitsToDestroy = 3,
	newlyBreakable = true,
	activation = "Interact (Consumes Action)", -- default Interact RT (G1: round(Modified Base RT x 0.10))
	triggerEvent = nil,
	primaryEffect = "+3 recruit choices in the next Tavern refresh after the battle (WIN ONLY)",
	uses = "Once",
	notes = "Player side only. Several Taverns in one battle do not stack (max +3). Bonus used up by that one refresh.",
}

ObjectData.Objects["Necro Tome Stand"] = {
	id = "Necro Tome Stand",
	category = "Event",
	tags = { "Shrine" },
	passable = false,
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	passable = false,  -- USER RULING 2026-10-30 (project_rules 241): blocks its tile; used via Interact from an adjacent tile.
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	passable = false,  -- USER RULING 2026-10-30 (project_rules 241): blocks its tile; used via Interact from an adjacent tile.
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
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
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true, -- rule 241 B4: breaking it gives NO Salvager's Cap (HD-011) roll
	activation = "Interact (Consumes Action)",
	interactRT = 150,
	triggerEvent = nil,
	primaryEffect = "Single use. Remove all debuffs from all allies (MAP-WIDE).",
	uses = "Once",
	notes = "all allies = MAP-WIDE (2026-10-03 ruling).",
}

-- =========================================================================================
-- 18 NEW MAP OBJECTS (USER DECISION 2026-11-07 9:59 PM; objects_encounters rows 112-129;
-- shared rules project_rules 249). Added in the generated style; the DB rows are the authority.
-- All are newlyBreakable (they were not breakable before rule 241), so none gives a Salvager's
-- Cap (HD-011) roll. Extra fields below the DB columns are read by ObjectEffectService.
-- =========================================================================================

ObjectData.Objects["Toxic Crate"] = {
	id = "Toxic Crate",
	category = "Hazard",
	tags = { "Container", "Poison", "Breakable" },
	passable = false,
	-- EXCEPTION to rule 241 (project_rules 249): ANY one hit from any source breaks it.
	hitsToDestroy = 1,
	newlyBreakable = true,
	activation = "Triggered",
	triggerEvent = "Hit by anything (incl. splash)",
	primaryEffect = "Breaks and creates Poison Cloud on its tile + radius 1",
	uses = "Once",
	notes = "UNIVERSAL OBJECT (map_gen_rules 95). Blocks its tile; any one hit breaks it, like Bomb Barrel. Radius 1 incl. diagonals (9 tiles), its own tile included once it is gone; tile effects skip blocked tiles (rule 246). Poison Cloud works as normal. The breaking hit does NOT ignite the new cloud, even a Fire hit [agent default, vetoable]. Friendly fire.",
	breakTileEffect = "Poison Cloud", -- ObjectEffectService break effect
	breakRadius = 1,
	breakGuardsOwnTile = true,        -- the breaking hit's element does not react on its own tile
}

ObjectData.Objects["Sludge Barrel"] = {
	id = "Sludge Barrel",
	category = "Hazard",
	tags = { "Container", "Sticky", "Breakable" },
	passable = false,
	-- EXCEPTION to rule 241 (project_rules 249): ANY one hit from any source breaks it.
	hitsToDestroy = 1,
	newlyBreakable = true,
	activation = "Triggered",
	triggerEvent = "Hit by anything (incl. splash)",
	primaryEffect = "Breaks and creates Tar Pit on its tile + radius 1",
	uses = "Once",
	notes = "UNIVERSAL OBJECT (map_gen_rules 95). Blocks its tile; any one hit breaks it, like Bomb Barrel. Radius 1 incl. diagonals (9 tiles), its own tile included once it is gone; tile effects skip blocked tiles (rule 246). Tar Pit works as normal (1.5 move cost, 2 own turn-ends on tar = Petrify, Fire -> Burning). Friendly fire.",
	breakTileEffect = "Tar Pit", -- ObjectEffectService break effect (no own-tile guard: the row names none)
	breakRadius = 1,
}

ObjectData.Objects["Water Barrel"] = {
	id = "Water Barrel",
	category = "Hazard",
	tags = { "Container", "Water", "Breakable" },
	passable = false,
	-- EXCEPTION to rule 241 (project_rules 249): ANY one hit from any source breaks it.
	hitsToDestroy = 1,
	newlyBreakable = true,
	activation = "Triggered",
	triggerEvent = "Hit by anything (incl. splash)",
	primaryEffect = "Breaks and creates Wet on its tile + radius 1",
	uses = "Once",
	notes = "UNIVERSAL OBJECT (map_gen_rules 95). Blocks its tile; any one hit breaks it, like Bomb Barrel. Radius 1 incl. diagonals (9 tiles), its own tile included once it is gone; tile effects skip blocked tiles (rule 246). Wet works as normal (Electric -> Static Cloud, Ice -> Frozen, Fire -> Steam, Dark -> Tar Pit). The breaking hit does NOT react with the new Wet [agent default, vetoable]. Friendly fire.",
	breakTileEffect = "Wet", -- ObjectEffectService break effect
	breakRadius = 1,
	breakGuardsOwnTile = true,
}

ObjectData.Objects["Snake Jar"] = {
	id = "Snake Jar",
	category = "Hazard",
	tags = { "Container", "Poison", "Breakable" },
	passable = false,
	-- EXCEPTION to rule 241 (project_rules 249): ANY one hit from any source breaks it.
	hitsToDestroy = 1,
	newlyBreakable = true,
	activation = "Triggered",
	triggerEvent = "Hit by anything (incl. splash)",
	primaryEffect = "Breaks; every unit within radius 1 gains Venom (Strength 1)",
	uses = "Once",
	notes = "Biomes: Desert 2, Swamp 2, Forest 1 [agent default, vetoable]. Blocks its tile; any one hit breaks it, like Bomb Barrel. No tile effect. Hits every unit within 1 tile (diagonals count), any side, including the attacker if adjacent. Uses the normal Venom status (stacks +1 on reapply, cured by heals, Undead immune).",
	breakStatus = "Venom",   -- ObjectEffectService break effect: status to every unit in breakRadius
	breakStatusStacks = 1,   -- Venom Strength 1 (one application)
	breakRadius = 1,
}

ObjectData.Objects["Redwood Observatory"] = {
	id = "Redwood Observatory",
	category = "Aura",
	tags = { "Structure", "Reveal", "Breakable" },
	passable = false,
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true,
	activation = "Passive",
	triggerEvent = nil,
	primaryEffect = "Radius 3, both sides: no unit can Hide or stay hidden; hidden traps/objects inside are revealed",
	uses = "Passive",
	notes = "Biomes: Forest 2, Highlands 1 [agent default, vetoable]. A hidden unit that enters or starts inside loses Hide; Hide cannot be gained inside. Reveals hidden traps and hidden objects inside, and unmasks a disguised Mimic (stays dormant), same as other reveal effects. Revealed traps stay revealed after leaving range [agent default, vetoable].",
	revealRadius = 3, -- ObjectEffectService (Hide block + reveal sweep)
}

ObjectData.Objects["Oasis"] = {
	id = "Oasis",
	category = "Exploration",
	tags = { "Spring", "Breakable" },
	passable = false,
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true,
	activation = "Interact (Free - no AP)", -- costs no AP (CommandService STEP 6) but adds interactRT
	interactRT = 120,
	triggerEvent = nil,
	primaryEffect = "Restores 20% Max HP and 20% Max MP to the interacting unit",
	uses = "Once per turn",
	notes = "Biomes: Desert 3 [agent default, vetoable]. Used from an adjacent tile (reach 1). Costs no AP but adds RT 120. Once per unit per turn (resets at the start of that unit's turn), unlimited across the battle.",
	restoreHpPct = 0.20, -- ObjectEffectService Oasis handler
	restoreMpPct = 0.20,
}

ObjectData.Objects["Mana Fountain"] = {
	id = "Mana Fountain",
	category = "Exploration",
	tags = { "Spring", "Breakable" },
	passable = false,
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true,
	activation = "Interact (Consumes Action)",
	interactRT = 100,
	triggerEvent = nil,
	primaryEffect = "Every ally on the map (MAP-WIDE) recovers 20% of missing MP at the end of each of their own turns for 2000 CT",
	uses = "Once",
	notes = "Biomes: Ruins 2, Tundra 1, Castle 1 [agent default, vetoable]. New object; the existing Magic Spring is unchanged (user decision 2026-11-07). Given as a normal timed buff (status 'Mana Fountain': dispellable like other buffs; reapply refreshes) [agent default, vetoable]. Removed after use.",
}

ObjectData.Objects["Learning Stone"] = {
	id = "Learning Stone",
	category = "Event",
	tags = { "Shrine", "Breakable" },
	passable = false,
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true,
	activation = "Interact (Consumes Action)",
	interactRT = 150,
	triggerEvent = nil,
	primaryEffect = "The interacting unit gains bonus XP = half the gold earned this battle (WIN ONLY)",
	uses = "Once",
	notes = "UNIVERSAL OBJECT (map_gen_rules 95). Only the unit that used it. Bonus XP = floor(0.5 x total battle gold reward), paid at the end of a won battle; nothing on loss/retreat. If the unit dies it still gets it on a win [agent default, vetoable]. USER RULING 2026-11-07: uses the existing after-battle experience award (Main grants it right after the battle gold is known).",
	bonusXpGoldShare = 0.5, -- Main post-battle (state.learningStoneUnits)
}

ObjectData.Objects["Garden of Revelation"] = {
	id = "Garden of Revelation",
	category = "Event",
	tags = { "Shrine", "Breakable" },
	passable = false,
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true,
	activation = "Interact (Consumes Action)",
	interactRT = 150,
	triggerEvent = nil,
	primaryEffect = "Every ally on the map (MAP-WIDE) gains +20% Max MP and restores that amount, until battle end",
	uses = "Once",
	notes = "Biomes: Plains 2, Forest 1 [agent default, vetoable]. A second Garden does not stack (no extra +20%) [agent default, vetoable]. Allies who join later (summons, revives after) do not get it [agent default, vetoable]. Removed after use. USER RULING 2026-11-07: battle-only max-MP bonus applied when the unit's stats are rebuilt (cleared at battle end).",
	maxMpBonusPct = 0.20, -- EquipmentService battleMaxMpBonusPct
}

ObjectData.Objects["Bone Pillar"] = {
	id = "Bone Pillar",
	category = "Blocker",
	tags = { "Structure", "Bone", "Immovable", "Breakable" },
	passable = false,
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	-- Collisions do NOT count as hits on it (no collision path calls ApplyObjectHit).
	hitsToDestroy = 3,
	newlyBreakable = true,
	isImmovable = true, -- cannot be pushed (GetPushableObjectTargets skips it)
	activation = "Passive",
	triggerEvent = "Unit forced into it",
	primaryEffect = "A unit pushed into it takes collision damage + 15% Max HP and gets Bleed",
	uses = "Passive",
	notes = "Biomes: Corrupted 3, Cave 2, Desert 1 [agent default, vetoable]. FIT TO WALL-COLLISION RULE (movement_targeting 15-16): normal wall-collision damage with impact multiplier 1.3x (same as Pillar), THEN a flat extra round(Max HP x 0.15 x Boss HP% Modifier) once per collision (not multiplied by blocked tiles, STR or knockback source), then Bleed (Undead immune). Collision damage stays non-direct (no Guard, no Combat Fortune).",
	collisionExtraMaxHpPct = 0.15, -- DisplacementService (flat extra per collision)
	collisionStatus = "Bleed",     -- CommandService applyForcedEntryEffects
}

ObjectData.Objects["Soul Well"] = {
	id = "Soul Well",
	category = "Aura",
	tags = { "Structure", "Dark", "Breakable" },
	passable = false,
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true,
	activation = "Passive",
	triggerEvent = "Skill cast inside",
	primaryEffect = "Radius 2, both sides: skills cast from inside get x1.2 potency (healing too); caster then loses HP = the skill MP cost (5% Max HP if it costs no MP)",
	uses = "Passive",
	notes = "Biomes: Corrupted 2, Ruins 1, Cave 1 [agent default, vetoable]. Checked on the caster's tile when the skill is committed. x1.2 multiplies the skill's damage/heal/shield amount (Skill Power step) [agent default, vetoable]; status durations unchanged. Self-damage after the cast: cannot be reduced, goes through Shield first, never drops below 1 HP, not physical so no Bleed trigger [agent default, vetoable]. Basic Attack and items are not skills - unaffected.",
	auraRadius = 2,          -- CommandService skill commit (ObjectEffectService.IsInSoulWell)
	skillPotencyMult = 1.2,
	noMpHpCostPct = 0.05,
}

ObjectData.Objects["Iron Curtain"] = {
	id = "Iron Curtain",
	category = "Aura",
	tags = { "Structure", "Breakable" },
	passable = false,
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true,
	activation = "Passive",
	triggerEvent = nil,
	primaryEffect = "Radius 3, both sides: damage received -30%",
	uses = "Passive",
	notes = "Biomes: Castle 1, Highlands 1 (kept rare) [agent default, vetoable]. STACKING RULE: armour (Defense, step 2) works as now; the 30% is ADDED to Guard and other final reductions in step 8, sharing the existing 80% cap (Guard 35% + Curtain 30% = 65%; + Guardian Standard 5 pts = 70%). USER RULING 2026-11-07: reduces DIRECT hits only (attacks, skills, item hits); Poison, Bleed and other damage-over-time, collisions, falls and hazards are NOT reduced. BALANCE CONCERN: very strong; kept rare and two-sided; breaking it (3 hits) is the counterplay.",
	auraRadius = 3,              -- CombatResolver step 8 (ironCurtainReduction)
	damageTakenReduction = 0.30,
}

ObjectData.Objects["Wasp Nest"] = {
	id = "Wasp Nest",
	category = "Hazard",
	tags = { "Nest", "Poison", "Breakable" },
	passable = false,
	-- EXCEPTION to rule 241 (project_rules 249): 5 hits to break.
	hitsToDestroy = 5,
	newlyBreakable = true,
	activation = "Triggered",
	triggerEvent = "Each hit on it",
	primaryEffect = "The 2 nearest non-poisoned units within radius 2 (any side, attacker included) take 15% Max HP damage, Poison and +100 RT Delay",
	uses = "Until destroyed",
	notes = "Biomes: Forest 2, Plains 1, Swamp 1 [agent default, vetoable]. Every hit sets it off, including the breaking 5th hit [agent default, vetoable]. Target order tie-break (project_rules 249): nearest by tile distance (diagonals count as 1), then lowest row, then lowest column. Damage = round(Max HP x 0.15 x Boss HP% Modifier), hazard damage (no Guard/Fortune). Undead take the damage and delay, immune to Poison - so they stay valid targets [agent default, vetoable]. Already-poisoned units are skipped. INSTANT KILL (no sting): any attack that applies Poison, or a Poison Cloud created on or spreading onto its tile (a cloud that would cover it destroys it instead).",
	instantKillTags = { "Poison" }, -- a Poison packet (Poison Cloud on its tile) destroys it in one hit, no sting
	stingTargets = 2,               -- ObjectEffectService per-hit sting
	stingRadius = 2,
	stingMaxHpPct = 0.15,
	stingStatus = "Poison",
	stingRtDelay = 100,
}

ObjectData.Objects["Volcanic Vent"] = {
	id = "Volcanic Vent",
	category = "Hazard",
	tags = { "Vent", "Fire", "Breakable" },
	passable = false,
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true,
	activation = "Passive (timed)",
	triggerEvent = "Every 400 CT from CT 1000",
	primaryEffect = "Deals 15% Max HP Fire damage to the 2 nearest units within radius 2",
	uses = "Passive",
	notes = "Biomes: Volcano 4, Cave 1 [agent default, vetoable]. Fires at battle CT 1000, 1400, 1800, ... Target order tie-break (project_rules 249): nearest by tile distance (diagonals count as 1), then lowest row, then lowest column. Any side. Next targets are shown in advance: a live marker shows who would be hit right now; at each eruption it hits whoever are the 2 nearest at that moment (user decision 2026-11-07). Damage = round(Max HP x 0.15 x element modifier x Boss HP% Modifier), hazard damage (no Guard/Fortune). Hits units only - does not set tiles Burning [agent default, vetoable].",
	eruptFirstCt = 1000, -- ObjectEffectService.ProcessObjectClock
	eruptEveryCt = 400,
	eruptTargets = 2,
	eruptRadius = 2,
	eruptMaxHpPct = 0.15,
	eruptElement = "Fire",
}

ObjectData.Objects["Venus Man-Trap"] = {
	id = "Venus Man-Trap",
	category = "Hazard",
	tags = { "Plant", "Organic", "Visible", "Breakable" },
	passable = false,
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true,
	activation = "Triggered",
	triggerEvent = "First unit to move into or through a tile within radius 1",
	primaryEffect = "Pins that unit while the plant stands; it takes 10% Max HP every 300 CT",
	uses = "One unit at a time; re-arms",
	notes = "Biomes: Swamp 3, Forest 2 [agent default, vetoable]. Trigger tiles = the 8 tiles around it. Triggers on any side. Holds one unit at a time. Pin lasts while the plant stands (no 1000 CT expiry, cannot be cleansed while held) [agent default, vetoable]. Damage = round(Max HP x 0.10), hazard damage. Freed when the plant breaks, or if the unit is pushed/teleported out of range [agent default, vetoable]. If the held unit dies or is freed by being moved, the plant re-arms. Bosses immune; flying units do not trigger it [agent default, vetoable].",
	triggerRadius = 1,     -- ObjectEffectService (GetTriggeredTrapAt / TriggerTrap)
	holdTickCt = 300,      -- ObjectEffectService.ProcessObjectClock
	holdMaxHpPct = 0.10,
}

ObjectData.Objects["Harpoon Shooter"] = {
	id = "Harpoon Shooter",
	category = "Siege",
	tags = { "Structure", "Breakable" },
	passable = false,
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true,
	activation = "Interact (Consumes Action)",
	interactRT = 60,
	triggerEvent = nil,
	primaryEffect = "Target a unit within 6 tiles in direct line of sight: 80% of a Ballista shot, pull it next to the shooter and Pin it for 2000 CT",
	uses = "Once per turn", -- project_rules 242/249: every siege object, once per unit per turn
	notes = "UNIVERSAL OBJECT (map_gen_rules 95). Siege: rule-242 Siege Power (48 + 1.9 x operator level, x DEX boost, height bonus measured from this object's tile, Siege Gunner Helm +0.25 added), no weapon passives, plain Physical, skips hit quality, friendly fire, free cancel during aiming. Direct shot from the shooter's tile, range 2-6, normal direct line-of-sight rules, one target. Pull: target is moved to the free tile next to the shooter nearest to the target (same tie-break); placed directly (no collision or fall damage); if no free tile, no pull [agent default, vetoable]. Pinned for 2000 CT. Bosses and units that can't be pushed take the damage and are NOT pulled; they are still Pinned [agent default, vetoable].",
	siegeShare = 0.80,     -- x Siege Power (Ballista = 1.0)
	rangeMin = 2,
	rangeMax = 6,
	pinCt = 2000,
}

ObjectData.Objects["Arcane Cannon"] = {
	id = "Arcane Cannon",
	category = "Siege",
	tags = { "Structure", "Breakable" },
	passable = false,
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true,
	activation = "Interact (Consumes Action)",
	interactRT = 100,
	triggerEvent = nil,
	primaryEffect = "Pick one of 8 lines; after 200 CT deals 120% of a Ballista shot to every unit on that line",
	uses = "Once per turn", -- project_rules 242/249: every siege object, once per unit per turn
	notes = "UNIVERSAL OBJECT (map_gen_rules 95). Siege: rule-242 Siege Power, no weapon passives, plain Physical, skips hit quality, friendly fire, free cancel during aiming. Same 8 lines and reach rules as Ballista (height within 3 of the cannon tile, min range 2, stopped by terrain/LoS objects, units never stop it), checked when it FIRES. Hits tiles, not locked units: whoever is on the line at the moment it fires is hit. Danger line shown to everyone during the 200 CT. Power = operator's Siege Power when aimed [agent default, vetoable]. If the cannon is broken during the delay, the shot is cancelled [agent default, vetoable].",
	siegeShare = 1.20,     -- x Siege Power (Ballista = 1.0)
	fireDelayCt = 200,     -- ObjectEffectService.ProcessObjectClock
}

ObjectData.Objects["Heavy Artillery"] = {
	id = "Heavy Artillery",
	category = "Siege",
	tags = { "Structure", "Breakable" },
	passable = false,
	-- USER RULING 2026-10-30 (project_rules 241): breakable map object, 3 hits from any source.
	hitsToDestroy = 3,
	newlyBreakable = true,
	activation = "Interact (Consumes Action)",
	interactRT = 100,
	triggerEvent = nil,
	primaryEffect = "Pick a tile like Catapult; red cross marked; after 200 CT deals 120% of a Catapult shot to units there and lowers each hit tile by 1 elevation",
	uses = "Once per turn", -- project_rules 242/249: every siege object, once per unit per turn
	notes = "UNIVERSAL OBJECT (map_gen_rules 95). Siege: rule-242 Siege Power, no weapon passives, plain Physical, skips hit quality, friendly fire, free cancel during aiming. Same targeting as Catapult (arc, range 2-6, plus-shaped blast within +/-2 height). Each unit hit takes 0.84 x Siege Power (120% of the Catapult's 70%). Power = operator's Siege Power when aimed [agent default, vetoable]. Cancelled if broken during the delay [agent default, vetoable]. TILE LOWERING [agent default, vetoable]: each blast tile drops 1 level; tiles already at the minimum elevation, bridge/span tiles, water tiles and chasm/gap tiles are not lowered. Units and objects on a lowered tile drop with it (1 level = no fall damage). Paths, jumps and line of sight are recalculated at once. USER RULING 2026-11-07: Heavy Artillery CAN seal routes - no route-protection check. Tile effects stay on the tile.",
	siegeShare = 0.84,     -- x Siege Power (Catapult = 0.70)
	rangeMax = 6,          -- + siege headgear range bonus, like Catapult
	fireDelayCt = 200,
	lowerTiles = 1,
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

-- -----------------------------------------------------------------
-- OBS TWO-FORM / AD BILLBOARD OBJECTS (added 2026-10-12)
-- Mirrors objects_encounters rows 83 (Blocker-Prop Cluster) and 84 (Ad Billboard)
-- and map_gen_rules rows 75-92. Placed by the OBS Two-Form System (ElevationPass
-- form roll + MapService materialization), NOT by the biome object pool. Both are
-- impassable (passable=false) so they flow through buildBlockers -> BLOCKERS ->
-- IsBlocked (movement + direct LoS block) and renderBlockers (visual).
-- PHASE 1 = static placement only. The Phase-2 fields below (hitsToDestroy,
-- nativeStability) are DATA ONLY — no runtime system reads them yet (object HP,
-- 3-hit break, push, and the map-object inspector are the Phase-2 build).
-- -----------------------------------------------------------------
ObjectData.Objects["OBS Blocker"] = {
	id = "OBS Blocker",
	category = "Obstacle",
	tags = { "OBS", "Blocker", "Not-Landable", "Breakable", "Blocks-LoS" },
	passable = false,
	activation = nil,
	triggerEvent = nil,
	primaryEffect = "Impassable blocker-prop OBS cluster on normal-height ground; blocks movement and direct line of sight.",
	uses = "Permanent",
	notes = "BLOCKER-PROP form of an OBS strip (map_gen_rules row 77/81). PHASE 1: a permanent wall — impassable to all (flight pass-over, break, and push are Phase 2). Clearing (break/push) reverts the tile to normal passable ground (Phase 2).",
	-- Standing height in elevation levels — used by buildBlockers (blocker.height)
	-- and height-aware LoS. A low wall-height cluster.
	standingHeight = 3,
	-- Phase 2 (DATA ONLY — nothing reads these yet):
	hitsToDestroy  = 3,  -- breaks after 3 hits from any source (map_gen_rules row 82)
	nativeStability = 3, -- flat native Stability for Push: Distance = max(0, Force-3) (row 83)
}

ObjectData.Objects["Ad Billboard"] = {
	id = "Ad Billboard",
	category = "Obstacle",
	tags = { "OBS", "Blocker", "Ad", "Immersive-Ad", "Not-Landable", "AdGui", "Unbreakable", "Elevation-Immune", "Immovable", "Blocks-LoS", "Non-Object" },
	passable = false,
	activation = nil,
	triggerEvent = nil,
	primaryEffect = "Immersive-ad billboard that REPLACES an OBS strip 1:1; impassable, blocks movement and direct line of sight.",
	uses = "Permanent",
	notes = "AD BILLBOARD form (map_gen_rules rows 79/85). EXCEPTION to blocker-prop rules: NOT breakable, elevation-IMMUNE, and immovable (unpushable). PHASE 1: static immovable/unbreakable wall + flat panel visual with a commented AdGui hook; real Roblox ad units are out of scope until eligibility is met (row 80).",
	standingHeight = 3,
	isElevationImmune = true, -- consumed by GameConstants.IsElevationImmune (elevation-reduction no-op)
	isUnbreakable = true,     -- Phase 2 break system must skip this (DATA ONLY now)
	isImmovable = true,       -- Phase 2 push system must skip this (DATA ONLY now)
	-- NON-OBJECT MARKER (user ruling 2026-10-17): the Ad Billboard is the SOLE exception to the
	-- Universal Object Marker (every non-unit entity is otherwise an object). It is EXCLUDED from any
	-- future instant-kill-objects / object-targeting capability. Unbreakable/Immovable/Elevation-Immune
	-- are unchanged; it carries NO hitsToDestroy (never was breakable). See project_rules
	-- 'Universal Object Marker' + 'Ad Billboard Non-Object Exception'.
	isNonObject = true,
}


-- -----------------------------------------------------------------
-- DEPLOYABLE PLACEABLE OBJECTS (20) — added 2026-10-21
-- The placeable-object half of the 20 DEP-* Deployable-category consumables.
-- Mirrored 1:1 from CTRBLXAI.db objects_encounters (rowids 87-106). Durability
-- SPLIT (2026-10-20 ruling): 4 structures carry a level-scaling HP pool
-- (hpBase/hpPerItemLevel/hpPerVIT), 16 light gadgets carry fixed hitsToDestroy=3.
-- FOUNDATION ONLY: placement + durability + Repair. Gadget behaviours are a later wave.
-- -----------------------------------------------------------------

ObjectData.Objects["Sentry Turret"] = {
	id = "Sentry Turret",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "HP-Pool-Durability", "Blocker", "Not-Landable", "Blocks-LoS", "Stability=3", "Pushable", "Turret", "Physical" },
	passable = false,
	activation = nil,
	triggerEvent = nil,
	primaryEffect = "Auto-fires at enemies (3 shots, per item formula) once wired.",
	uses = "Until Destroyed",
	-- Deployable placeable-object foundation (2026-10-21). Behaviour (turret fire,
	-- auras, traps, drone movement, reveal, weather, interception) is a LATER WAVE.
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "DEP-001",
	standingHeight = 3,
	nativeStability = 3,
	-- HP-pool structure: maxHp computed at placement = hpBase + hpPerItemLevel*IL + hpPerVIT*VIT
	hpBase = 22.0,
	hpPerItemLevel = 0.65,
	hpPerVIT = 0.4,
}

ObjectData.Objects["Healing Beacon"] = {
	id = "Healing Beacon",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "Breakable(3-hit)", "Healing", "Aura" },
	passable = true,
	activation = nil,
	triggerEvent = nil,
	primaryEffect = "Pulses 5% Max HP heal to allies within 2 every 400 CT (4 pulses), 1600 CT.",
	uses = "Until Destroyed",
	-- Deployable placeable-object foundation (2026-10-21). Behaviour (turret fire,
	-- auras, traps, drone movement, reveal, weather, interception) is a LATER WAVE.
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "DEP-002",
	hitsToDestroy = 3, -- fixed hit-counter (any source removes 1)
}

ObjectData.Objects["Barrier Pylon"] = {
	id = "Barrier Pylon",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "HP-Pool-Durability", "Blocker", "Not-Landable", "Blocks-LoS", "Stability=3", "Pushable", "Barrier", "Cover" },
	passable = false,
	activation = nil,
	triggerEvent = nil,
	primaryEffect = "Solid barrier providing cover; HP scales with level.",
	uses = "Until Destroyed",
	-- Deployable placeable-object foundation (2026-10-21). Behaviour (turret fire,
	-- auras, traps, drone movement, reveal, weather, interception) is a LATER WAVE.
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "DEP-003",
	standingHeight = 3,
	nativeStability = 3,
	-- HP-pool structure: maxHp computed at placement = hpBase + hpPerItemLevel*IL + hpPerVIT*VIT
	hpBase = 25.0,
	hpPerItemLevel = 0.75,
	hpPerVIT = 0.6,
	hitsToDestroy = 3, -- user ruling 2026-10-27: 3 hits until object HP pools exist (hp* fields kept for later)
}

ObjectData.Objects["Barricade"] = {
	id = "Barricade",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "HP-Pool-Durability", "Blocker", "Not-Landable", "Blocks-LoS", "Stability=3", "Pushable", "Barrier", "Cover" },
	passable = false,
	activation = nil,
	triggerEvent = nil,
	primaryEffect = "Projected solid barricade providing cover; HP scales with level.",
	uses = "Until Destroyed",
	-- Barricade Projector consumable (ENV-011). Static blocker like Barrier Pylon with a
	-- lighter HP curve; placed through the existing object-deploy path (GetDeployPlan sees
	-- passable=false + activation/triggerEvent nil -> static blocker). Added to source from
	-- the Designer's DB archetype (2026-10-26).
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "ENV-011",
	standingHeight = 3,
	nativeStability = 3,
	hpBase = 20.0,
	hpPerItemLevel = 0.60,
	hpPerVIT = 0.50,
	hitsToDestroy = 3, -- user ruling 2026-10-27: 3 hits until object HP pools exist (hp* fields kept for later)
}

ObjectData.Objects["Hardlight Wall"] = {
	id = "Hardlight Wall",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "HP-Pool-Durability", "Blocker", "Not-Landable", "Blocks-LoS", "Stability=3", "Pushable", "Barrier", "Line" },
	passable = false,
	activation = nil,
	triggerEvent = nil,
	primaryEffect = "Three-segment solid wall; each segment HP scales with level.",
	uses = "Until Destroyed",
	-- Deployable placeable-object foundation (2026-10-21). Behaviour (turret fire,
	-- auras, traps, drone movement, reveal, weather, interception) is a LATER WAVE.
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "DEP-004",
	standingHeight = 3,
	nativeStability = 3,
	-- HP-pool structure: maxHp computed at placement = hpBase + hpPerItemLevel*IL + hpPerVIT*VIT
	hpBase = 15.0,
	hpPerItemLevel = 0.45,
	hpPerVIT = 0.35,
	segments = 3,
	hitsToDestroy = 3, -- user ruling 2026-10-27: 3 hits until object HP pools exist (hp* fields kept for later)
}

ObjectData.Objects["Mine Dispenser"] = {
	id = "Mine Dispenser",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "Breakable(3-hit)", "Trap", "Physical" },
	passable = true,
	activation = nil,
	triggerEvent = nil,
	primaryEffect = "Places a mine that detonates on an enemy once wired.",
	uses = "Until Destroyed",
	-- Deployable placeable-object foundation (2026-10-21). Behaviour (turret fire,
	-- auras, traps, drone movement, reveal, weather, interception) is a LATER WAVE.
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "DEP-005",
	hitsToDestroy = 3, -- fixed hit-counter (any source removes 1)
}

ObjectData.Objects["Snare Dispenser"] = {
	id = "Snare Dispenser",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "Breakable(3-hit)", "Trap", "Pinned" },
	passable = true,
	activation = nil,
	triggerEvent = nil,
	primaryEffect = "Places a snare that Pins the first enemy once wired.",
	uses = "Until Destroyed",
	-- Deployable placeable-object foundation (2026-10-21). Behaviour (turret fire,
	-- auras, traps, drone movement, reveal, weather, interception) is a LATER WAVE.
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "DEP-006",
	hitsToDestroy = 3, -- fixed hit-counter (any source removes 1)
}

ObjectData.Objects["Stasis Trap Emitter"] = {
	id = "Stasis Trap Emitter",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "Breakable(3-hit)", "Trap", "RT Delay" },
	passable = true,
	-- Runtime payload wired 2026-10-26 (DB objects_encounters "Stasis Trap Emitter" RUNTIME
	-- PAYLOAD note): enemy-entry trap, consumed on trigger. RT Delay = round(100 + 0.35*IL)
	-- (IL = placing unit's level) to every enemy of the owner within radius 1.
	activation = "Triggered",
	triggerEvent = "Unit enters tile",
	primaryEffect = "RT Delay burst on enemies within 1 tile",
	uses = "Once",
	rtDelayFlat = 100,
	rtDelayPerIL = 0.35,
	effectRadius = 1,
	-- Deployable placeable-object foundation (2026-10-21). Behaviour (turret fire,
	-- auras, traps, drone movement, reveal, weather, interception) is a LATER WAVE.
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "DEP-007",
	hitsToDestroy = 3, -- fixed hit-counter (any source removes 1)
}

ObjectData.Objects["Decoy Totem"] = {
	id = "Decoy Totem",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "HP-Pool-Durability", "Taunt", "AI" },
	passable = true,
	activation = nil,
	triggerEvent = nil,
	primaryEffect = "High-priority decoy drawing enemy AI; HP scales with level.",
	uses = "Until Destroyed",
	-- Deployable placeable-object foundation (2026-10-21). Behaviour (turret fire,
	-- auras, traps, drone movement, reveal, weather, interception) is a LATER WAVE.
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "DEP-008",
	-- HP-pool structure: maxHp computed at placement = hpBase + hpPerItemLevel*IL + hpPerVIT*VIT
	hpBase = 12.0,
	hpPerItemLevel = 0.4,
	hpPerVIT = 0.25,
}

ObjectData.Objects["Hologram Projector"] = {
	id = "Hologram Projector",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "Breakable(3-hit)", "Decoy", "Vision" },
	passable = true,
	activation = nil,
	triggerEvent = nil,
	primaryEffect = "Projects a false unit presence once wired.",
	uses = "Until Destroyed",
	-- Deployable placeable-object foundation (2026-10-21). Behaviour (turret fire,
	-- auras, traps, drone movement, reveal, weather, interception) is a LATER WAVE.
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "DEP-009",
	hitsToDestroy = 3, -- fixed hit-counter (any source removes 1)
}

ObjectData.Objects["Supply Station"] = {
	id = "Supply Station",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "Breakable(3-hit)", "Charge Restore" },
	passable = true,
	-- Runtime behaviour wired 2026-10-26 (user-approved): each allied unit next to it may
	-- Interact once (1 AP, normal Interact RT) to restore 1 charge to its item missing the
	-- most charges; 3 supplies, then removed. Enemies cannot use it.
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Interact: restore 1 item charge (once per unit); 3 supplies",
	uses = "Once per turn",
	supplies = 3,
	-- Deployable placeable-object foundation (2026-10-21). Behaviour (turret fire,
	-- auras, traps, drone movement, reveal, weather, interception) is a LATER WAVE.
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "DEP-010",
	hitsToDestroy = 3, -- fixed hit-counter (any source removes 1)
}

ObjectData.Objects["Scout Drone"] = {
	id = "Scout Drone",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "Breakable(3-hit)", "Reveal", "Flying" },
	passable = true,
	activation = nil,
	triggerEvent = nil,
	primaryEffect = "Reveals hidden units/traps/objects in its aura once wired.",
	uses = "Until Destroyed",
	-- Deployable placeable-object foundation (2026-10-21). Behaviour (turret fire,
	-- auras, traps, drone movement, reveal, weather, interception) is a LATER WAVE.
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "DEP-011",
	hitsToDestroy = 3, -- fixed hit-counter (any source removes 1)
}

ObjectData.Objects["Survey Drone"] = {
	id = "Survey Drone",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "Breakable(3-hit)", "Reveal", "Mobile" },
	passable = true,
	activation = nil,
	triggerEvent = nil,
	primaryEffect = "Mobile revealer relocating each interval once wired.",
	uses = "Until Destroyed",
	-- Deployable placeable-object foundation (2026-10-21). Behaviour (turret fire,
	-- auras, traps, drone movement, reveal, weather, interception) is a LATER WAVE.
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "DEP-012",
	hitsToDestroy = 3, -- fixed hit-counter (any source removes 1)
}

ObjectData.Objects["Elemental Ward Totem"] = {
	id = "Elemental Ward Totem",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "Breakable(3-hit)", "Ward", "Aura" },
	passable = true,
	activation = nil,
	triggerEvent = nil,
	primaryEffect = "Reduces a chosen element damage for nearby allies once wired.",
	uses = "Until Destroyed",
	-- Deployable placeable-object foundation (2026-10-21). Behaviour (turret fire,
	-- auras, traps, drone movement, reveal, weather, interception) is a LATER WAVE.
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "DEP-013",
	hitsToDestroy = 3, -- fixed hit-counter (any source removes 1)
}

ObjectData.Objects["Weather Stabilizer Totem"] = {
	id = "Weather Stabilizer Totem",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "Breakable(3-hit)", "Weather", "Aura" },
	passable = true,
	activation = nil,
	triggerEvent = nil,
	primaryEffect = "Suppresses local weather modifiers in its aura once wired.",
	uses = "Until Destroyed",
	-- Deployable placeable-object foundation (2026-10-21). Behaviour (turret fire,
	-- auras, traps, drone movement, reveal, weather, interception) is a LATER WAVE.
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "DEP-014",
	hitsToDestroy = 3, -- fixed hit-counter (any source removes 1)
}

ObjectData.Objects["Portable Ballista"] = {
	id = "Portable Ballista",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "Breakable(3-hit)", "Blocker", "Not-Landable", "Blocks-LoS", "Stability=3", "Pushable", "Siege", "Interact" },
	passable = false,
	-- Runtime behaviour (user ruling 2026-10-27: works like the map Ballista): a unit of the
	-- OWNER's side standing next to it Interacts and aims one of 8 straight lines from the
	-- Ballista; the bolt pierces every unit 3-7 tiles out on that line, allies included.
	-- Power = 50 + 0.90*IL + 0.60*DEX of the placing unit, fixed at placement; normal Defense
	-- applies. Removed after its 2nd shot. interactRT mirrors the map Ballista.
	activation = "Interact (Consumes Action)",
	interactRT = 100,
	triggerEvent = nil,
	primaryEffect = "Fires a piercing bolt down one of 8 lines (tiles 3-7 out, hits allies too); 2 shots then removed",
	uses = "Once per turn",
	shots = 2,
	rangeMin = 3,
	rangeMax = 7,
	shotPowerFormula = "50+0.90*IL+0.60*DEX",
	-- Deployable placeable-object foundation (2026-10-21). Behaviour (turret fire,
	-- auras, traps, drone movement, reveal, weather, interception) is a LATER WAVE.
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "DEP-015",
	standingHeight = 3,
	nativeStability = 3,
	hitsToDestroy = 3, -- fixed hit-counter (any source removes 1)
}

ObjectData.Objects["Rescue Beacon"] = {
	id = "Rescue Beacon",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "Breakable(3-hit)", "Revive", "Aura" },
	passable = true,
	-- Runtime behaviour wired 2026-10-26 (user-approved): the first allied unit KO'd within
	-- rescueRadius tiles AFTER placement is moved to a free tile next to the beacon and
	-- revived at rescueHpPct Max HP with rescueRt RT; the beacon is then used up. Devices and
	-- summons don't count. No free tile -> it waits for the next KO.
	activation = "Passive",
	triggerEvent = nil,
	primaryEffect = "Revives the first allied KO within 3 tiles next to it (15% HP, 400 RT)",
	uses = "Once",
	rescueRadius = 3,
	rescueHpPct = 0.15,
	rescueRt = 400,
	-- Deployable placeable-object foundation (2026-10-21). Behaviour (turret fire,
	-- auras, traps, drone movement, reveal, weather, interception) is a LATER WAVE.
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "DEP-016",
	hitsToDestroy = 3, -- fixed hit-counter (any source removes 1)
}

ObjectData.Objects["Poison Cloud Vent"] = {
	id = "Poison Cloud Vent",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "Breakable(3-hit)", "Poison", "Zone" },
	passable = true,
	activation = nil,
	triggerEvent = nil,
	primaryEffect = "Every 400 CT (3 pulses) creates Poison Cloud within 2, 1200 CT.",
	uses = "Until Destroyed",
	-- Deployable placeable-object foundation (2026-10-21). Behaviour (turret fire,
	-- auras, traps, drone movement, reveal, weather, interception) is a LATER WAVE.
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "DEP-017",
	hitsToDestroy = 3, -- fixed hit-counter (any source removes 1)
}

ObjectData.Objects["Countermeasure Turret"] = {
	id = "Countermeasure Turret",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "Breakable(3-hit)", "Blocker", "Not-Landable", "Blocks-LoS", "Stability=3", "Pushable", "Defense", "Interception" },
	passable = false,
	activation = nil,
	triggerEvent = nil,
	primaryEffect = "Intercepts hostile projectiles entering its aura once wired.",
	uses = "Until Destroyed",
	-- Deployable placeable-object foundation (2026-10-21). Behaviour (turret fire,
	-- auras, traps, drone movement, reveal, weather, interception) is a LATER WAVE.
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "DEP-018",
	standingHeight = 3,
	nativeStability = 3,
	hitsToDestroy = 3, -- fixed hit-counter (any source removes 1)
}

ObjectData.Objects["Taunt Beacon"] = {
	id = "Taunt Beacon",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "Breakable(3-hit)", "Taunt" },
	passable = true,
	activation = nil,
	triggerEvent = nil,
	primaryEffect = "Enemies within 4 tiles are Taunted by the beacon.",
	uses = "Until Destroyed",
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "CON-018",
	standingHeight = 3,
	nativeStability = 3,
	hitsToDestroy = 3, -- fixed hit-counter (any source removes 1)
}

ObjectData.Objects["Mender Drone"] = {
	id = "Mender Drone",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "Breakable(3-hit)", "Healing", "Mobile" },
	passable = true,
	activation = nil,
	triggerEvent = nil,
	primaryEffect = "Mobile healer mending the lowest-HP ally once wired.",
	uses = "Until Destroyed",
	-- Deployable placeable-object foundation (2026-10-21). Behaviour (turret fire,
	-- auras, traps, drone movement, reveal, weather, interception) is a LATER WAVE.
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "DEP-019",
	hitsToDestroy = 3, -- fixed hit-counter (any source removes 1)
}

ObjectData.Objects["Gravity Pylon"] = {
	id = "Gravity Pylon",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "Breakable(3-hit)", "Control", "Aura" },
	passable = true,
	activation = nil,
	triggerEvent = nil,
	primaryEffect = "Grants Stability and blocks teleports in its aura once wired.",
	uses = "Until Destroyed",
	-- Deployable placeable-object foundation (2026-10-21). Behaviour (turret fire,
	-- auras, traps, drone movement, reveal, weather, interception) is a LATER WAVE.
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "DEP-020",
	hitsToDestroy = 3, -- fixed hit-counter (any source removes 1)
}

ObjectData.Objects["Guardian Standard"] = {
	id = "Guardian Standard",
	category = "Deployable",
	tags = { "Deployable", "Breakable", "Repairable", "Caster-Owned", "Breakable(3-hit)", "Guard", "Aura" },
	passable = true,
	activation = "Passive",
	triggerEvent = nil,
	primaryEffect = "Allies within 2 tiles: +5 Guard percentage points while Guarding, Stability +1",
	uses = "Until Destroyed",
	-- Mirrors DB objects_encounters row 108 (2026-10-27). Spawned as an item device
	-- (deployKind summon, ref WardTotem); this row supplies its 3-hit durability.
	isDeployable = true,
	isRepairable = true,
	ownerScope = "Caster",
	sourceConsumableId = "SUP-011",
	hitsToDestroy = 3, -- fixed hit-counter (any source removes 1)
}

return ObjectData
