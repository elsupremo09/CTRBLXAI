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
