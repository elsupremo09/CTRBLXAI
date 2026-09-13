-- ObjectData.lua
-- CTRBLXAI | Slice 5 -- Procedural Map Generation
--
-- Generated from CTRBLXAI.db objects_encounters table.
-- DO NOT EDIT MANUALLY -- regenerate from DB if rules change.

local ObjectData = {}

-- Objects (47)
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
	primaryEffect = "3x3 Explosion (30% Max HP), Elevation -1",
	uses = "Once",
	notes = "Chain reactions allowed",
}

ObjectData.Objects["Bomb Barrel"] = {
	id = "Bomb Barrel",
	category = "Hazard",
	tags = { "Breakable", "Explosive" },
	passable = false,
	activation = "Triggered",
	triggerEvent = "Fire-tag attack, Explosion, or Destroyed",
	primaryEffect = "3x3 Explosion (30% Max HP), destroys adjacent breakable bridges/walls",
	uses = "Once",
	notes = "Explosion lowers elevation by 1",
}

ObjectData.Objects["Oil Sluice"] = {
	id = "Oil Sluice",
	category = "Hazard",
	tags = { "Structure" },
	passable = false,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Creates Tar Pit in 5x5 area",
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
	primaryEffect = "Creates Steam in 5x5 area",
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
	primaryEffect = "Falls opposite direction, becoming a 3-tile bridge or crushing units (70% Max HP, +100 RT, Pinned)",
	uses = "Once",
	notes = "Permanent terrain change",
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
	triggerEvent = nil,
	primaryEffect = "Fires penetrating bolt (250% Weapon Damage) in chosen direction",
	uses = "Unlimited",
	notes = "Uses operator stats",
}

ObjectData.Objects["Catapult"] = {
	id = "Catapult",
	category = "Siege",
	tags = { "Structure" },
	passable = false,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Fires projectile (200% Weapon Damage, 3x3 Splash) within Range 6",
	uses = "Unlimited",
	notes = "Splash damages objects",
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
	primaryEffect = "Units within Radius 3 suffer -15% to all primary stats",
	uses = "Passive",
	notes = "Removed if destroyed",
}

ObjectData.Objects["Rally Flag"] = {
	id = "Rally Flag",
	category = "Aura",
	tags = { "Structure" },
	passable = false,
	activation = "Interact (Free)",
	triggerEvent = nil,
	primaryEffect = "Allies gain +1 Move and +1 Jump for 900 CT",
	uses = "Once",
	notes = "Does not stack",
}

ObjectData.Objects["Mage Guild"] = {
	id = "Mage Guild",
	category = "Aura",
	tags = { "Structure" },
	passable = false,
	activation = "Interact (Free)",
	triggerEvent = nil,
	primaryEffect = "Friendly units gain +20% Spell Damage for 900 CT",
	uses = "Once",
	notes = "Does not stack",
}

ObjectData.Objects["Warrior Guild"] = {
	id = "Warrior Guild",
	category = "Aura",
	tags = { "Structure" },
	passable = false,
	activation = "Interact (Free)",
	triggerEvent = nil,
	primaryEffect = "Friendly units gain +20% Physical Damage for 900 CT",
	uses = "Once",
	notes = "Does not stack",
}

ObjectData.Objects["Mercenary Camp"] = {
	id = "Mercenary Camp",
	category = "Aura",
	tags = { "Structure" },
	passable = false,
	activation = "Interact (Free)",
	triggerEvent = nil,
	primaryEffect = "Friendly units deal +20% damage for 900 CT",
	uses = "Once",
	notes = "Does not stack",
}

ObjectData.Objects["Marletto Tower"] = {
	id = "Marletto Tower",
	category = "Aura",
	tags = { "Structure" },
	passable = false,
	activation = "Interact (Free)",
	triggerEvent = nil,
	primaryEffect = "Friendly units take 20% less damage for 900 CT",
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
	notes = nil,
}

ObjectData.Objects["Mimic"] = {
	id = "Mimic",
	category = "Exploration",
	tags = { "Monster" },
	passable = false,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Reveals Mimic enemy with x3 loot rate",
	uses = "Once",
	notes = "Initially appears as Treasure Chest",
}

ObjectData.Objects["Warrior's Tomb"] = {
	id = "Warrior's Tomb",
	category = "Exploration",
	tags = { "Shrine" },
	passable = false,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Random treasure; inflicts Weakened (3000 CT)",
	uses = "Once",
	notes = nil,
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
	notes = nil,
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
	notes = nil,
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
	notes = nil,
}

ObjectData.Objects["Arena"] = {
	id = "Arena",
	category = "Exploration",
	tags = { "Training" },
	passable = false,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Permanently gain +20% to to the unit's highest primary stat",
	uses = "Once",
	notes = "parked",
}

ObjectData.Objects["Tree of Knowledge"] = {
	id = "Tree of Knowledge",
	category = "Exploration",
	tags = { "Shrine" },
	passable = false,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Gain +1 Level; inflict Weakened (900 CT)",
	uses = "Once",
	notes = "parked",
}

ObjectData.Objects["Scholar"] = {
	id = "Scholar",
	category = "Exploration",
	tags = { "NPC" },
	passable = true,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "50% chance Job Level +1, otherwise random status ailment",
	uses = "Once",
	notes = "parked",
}

ObjectData.Objects["Library of Enlightenment"] = {
	id = "Library of Enlightenment",
	category = "Exploration",
	tags = { "Shrine" },
	passable = false,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Permanently gain +1 to all primary stats",
	uses = "Once",
	notes = "parked",
}

ObjectData.Objects["Cartographer"] = {
	id = "Cartographer",
	category = "Exploration",
	tags = { "NPC" },
	passable = true,
	activation = "Interact (Free)",
	triggerEvent = nil,
	primaryEffect = "Reveals all Hidden Treasures",
	uses = "Unlimited",
	notes = nil,
}

ObjectData.Objects["Eye of the Magi"] = {
	id = "Eye of the Magi",
	category = "Exploration",
	tags = { "Arcane" },
	passable = true,
	activation = "Interact (Free)",
	triggerEvent = nil,
	primaryEffect = "Reveals Hidden enemies, Hidden Objects, and Hidden Treasures within Radius 5",
	uses = "Unlimited",
	notes = nil,
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

ObjectData.Objects["Trading Post"] = {
	id = "Trading Post",
	category = "Event",
	tags = { "Settlement" },
	passable = false,
	activation = "Interact (Free)",
	triggerEvent = nil,
	primaryEffect = "Next base shop has improved inventory and 20% discount",
	uses = "Once",
	notes = "Does not stack",
}

ObjectData.Objects["Den of Thieves"] = {
	id = "Den of Thieves",
	category = "Event",
	tags = { "Settlement" },
	passable = false,
	activation = "Interact (Free)",
	triggerEvent = nil,
	primaryEffect = "Adds one high-level quest to next base visit",
	uses = "Once",
	notes = "Does not stack",
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
	activation = "Interact (Free)",
	triggerEvent = nil,
	primaryEffect = "Increased recruitment success until battle ends",
	uses = "Once",
	notes = "Does not stack",
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

ObjectData.Objects["Altar of Sacrifice"] = {
	id = "Altar of Sacrifice",
	category = "Event",
	tags = { "Shrine" },
	passable = false,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "User loses 50% Max HP; all allies gain Enlightened",
	uses = "Once",
	notes = "Risk/Reward",
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
	notes = nil,
}

ObjectData.Objects["Dragon Utopia"] = {
	id = "Dragon Utopia",
	category = "Event",
	tags = { "Encounter" },
	passable = false,
	activation = "Interact (Free)",
	triggerEvent = nil,
	primaryEffect = "Summons 4-6 Dragons with x3 loot rate",
	uses = "Once",
	notes = "High-risk encounter",
}

ObjectData.Objects["Refugee Camp"] = {
	id = "Refugee Camp",
	category = "Event",
	tags = { "Settlement" },
	passable = false,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Summons one random neutral unit",
	uses = "Once",
	notes = nil,
}

ObjectData.Objects["Seer's Hut"] = {
	id = "Seer's Hut",
	category = "Event",
	tags = { "NPC" },
	passable = true,
	activation = "Interact (Free)",
	triggerEvent = nil,
	primaryEffect = "Generates one optional quest",
	uses = "Once",
	notes = nil,
}

ObjectData.Objects["Skeleton Transformer"] = {
	id = "Skeleton Transformer",
	category = "Event",
	tags = { "Shrine" },
	passable = false,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Transform one non-boss enemy into Skeleton (cannot be recruited) for 3000 CT.",
	uses = "Once",
	notes = "parked",
}

ObjectData.Objects["Stables"] = {
	id = "Stables",
	category = "Event",
	tags = { "Settlement" },
	passable = false,
	activation = "Interact (Free)",
	triggerEvent = nil,
	primaryEffect = "Grants Flight for 1500 CT",
	uses = "Once",
	notes = nil,
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
	notes = nil,
}

ObjectData.Objects["War Machine Factory"] = {
	id = "War Machine Factory",
	category = "Event",
	tags = { "Structure" },
	passable = false,
	activation = "Interact (Consumes Action)",
	triggerEvent = nil,
	primaryEffect = "Summon one Ballista or Catapult on chosen tile within a radius of 3 from object",
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

-- Battle Conditions (15)
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
	passiveEffect = "Fire Damage -25%; Water Damage +25%.",
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
	passiveEffect = "Fire Damage +20%; Water Damage -20%.",
	periodicEffect = "Every 300 CT, reduce all Wet durations by 300 CT.",
	interval = 300,
	notes = "Promotes Fire strategies.",
}

ObjectData.BattleConditions["Dark Eclipse"] = {
	id = "Dark Eclipse",
	description = "Darkness engulfs the battlefield.",
	passiveEffect = "Light Damage -25%; Dark Damage +25%; Recruitment Chance -20%.",
	periodicEffect = "None.",
	interval = nil,
	notes = "Holy attacks are weakened.",
}

ObjectData.BattleConditions["Holy Aurora"] = {
	id = "Holy Aurora",
	description = "Holy light shines over the battlefield.",
	passiveEffect = "Light Damage +25%; Dark Damage -25%.",
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
	periodicEffect = "Every 500 CT, randomly alter 20–40% of map tiles by -2 to +2 elevation; units on changed tiles suffer +150 RT Delay.",
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