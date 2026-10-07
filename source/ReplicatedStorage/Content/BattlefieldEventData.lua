--!strict
-- BattlefieldEventData.lua
-- CTRBLXAI | Battlefield Events catalog
--
-- Generated from CTRBLXAI.db battlefield_events table (35 rows).
-- DO NOT EDIT MANUALLY -- regenerate from DB if rules change.
-- Prose only (the DB carries no structured mechanics); behavior is resolved
-- code-side by BattlefieldEventService's Handlers table, keyed by `name`.

local BattlefieldEventData = {}

BattlefieldEventData.Events = {}

-- DB order (event_id ascending).
BattlefieldEventData.Order = {
	"Merchant Caravan",
	"Slave Trader",
	"Wandering Scholar",
	"Wandering Bard",
	"Wandering Mercenaries",
	"Champion",
	"Zombie Horde",
	"Leprechaun",
	"Thief",
	"Wandering Blacksmith",
	"Mutator",
	"Herald of XXX",
	"Divine Intervention",
	"Chaos Necromancer",
	"Fortune Teller",
	"Lost Noble",
	"Treasure Hunter",
	"Wandering Monster",
	"Vengeful Spirit",
	"Bounty Hunter",
	"Monster Hunter",
	"Wandering Bandits",
	"Plague Carrier",
	"Traitor",
	"Enemy Scout",
	"Doppelganger",
	"Chaos Lich",
	"Fog Spirit",
	"Fire Spirit",
	"Wind Spirit",
	"Water Spirit",
	"Lightning Elemental",
	"Earth Elemental",
	"Gold Golem",
	"Crystal Golem",
}

BattlefieldEventData.Events["Merchant Caravan"] = {
	id = 1,
	name = "Merchant Caravan",
	type = "Neutral NPC",
	triggerSpawn = "Randomly spawns during map gen or at map edge Round 1",
	behaviorEffect = "Moves across map during its turn. Interacting doubles items in next Merchant Shop and increases rarity.",
}

BattlefieldEventData.Events["Slave Trader"] = {
	id = 2,
	name = "Slave Trader",
	type = "Neutral NPC",
	triggerSpawn = "Random spawn",
	behaviorEffect = "Like Merchant Caravan but affects recruitment. Doubles recruitment options and increases recruit rarity.",
}

BattlefieldEventData.Events["Wandering Scholar"] = {
	id = 3,
	name = "Wandering Scholar",
	type = "Neutral NPC",
	triggerSpawn = "Random spawn",
	behaviorEffect = "Interacting doubles EXP earned during current battle.",
}

BattlefieldEventData.Events["Wandering Bard"] = {
	id = 4,
	name = "Wandering Bard",
	type = "Neutral NPC / Battlefield Modifier",
	triggerSpawn = "Random spawn",
	behaviorEffect = "While alive, provides a random buff or debuff to all units.",
}

BattlefieldEventData.Events["Wandering Mercenaries"] = {
	id = 5,
	name = "Wandering Mercenaries",
	type = "Neutral NPC",
	triggerSpawn = "Random spawn",
	behaviorEffect = "Offer to fight for player in exchange for halving gold earned. Declining makes them hostile.",
}

BattlefieldEventData.Events["Champion"] = {
	id = 6,
	name = "Champion",
	type = "Hostile Elite",
	triggerSpawn = "Spawns Round 2+ when friendly HP ≤50% max and >50% enemies defeated",
	behaviorEffect = "Powerful elite comeback threat when player is badly damaged despite winning.",
}

BattlefieldEventData.Events["Zombie Horde"] = {
	id = 7,
	name = "Zombie Horde",
	type = "Hostile Undead",
	triggerSpawn = "Spawns Round 2 in applicable biomes",
	behaviorEffect = "Hostile to non-undead units.",
}

BattlefieldEventData.Events["Leprechaun"] = {
	id = 8,
	name = "Leprechaun",
	type = "Hostile / Reward",
	triggerSpawn = "Random spawn",
	behaviorEffect = "Defeating grants large gold reward.",
}

BattlefieldEventData.Events["Thief"] = {
	id = 9,
	name = "Thief",
	type = "Hostile NPC",
	triggerSpawn = "Random spawn; starts hidden",
	behaviorEffect = "Attempts Steal on friendly units. Defeating recovers stolen item.",
}

BattlefieldEventData.Events["Wandering Blacksmith"] = {
	id = 10,
	name = "Wandering Blacksmith",
	type = "Neutral NPC",
	triggerSpawn = "Random spawn",
	behaviorEffect = "Like Merchant Caravan but affects next Blacksmith interaction, improving equipment/services.",
}

BattlefieldEventData.Events["Mutator"] = {
	id = 11,
	name = "Mutator",
	type = "Special NPC/Enemy",
	triggerSpawn = "Random spawn",
	behaviorEffect = "Defeating spawns Mutation Bench (one use per battle). Unit interacting chooses perk or drawback category but result is random from that pool. Any unit can use it.",
}

BattlefieldEventData.Events["Herald of XXX"] = {
	id = 12,
	name = "Herald of XXX",
	type = "Neutral → Boss Event",
	triggerSpawn = "Spawns Round 2+",
	behaviorEffect = "Defeating the neutral Herald spawns the boss it heralds.",
}

BattlefieldEventData.Events["Divine Intervention"] = {
	id = 13,
	name = "Divine Intervention",
	type = "Special Event",
	triggerSpawn = "Rare; requires ≥50% friendly KO'd AND map ≥5 levels above highest friendly unit",
	behaviorEffect = "Immediately revives all KO'd friendly units at full HP + team buff. Once per battle; NPC despawns after.",
}

BattlefieldEventData.Events["Chaos Necromancer"] = {
	id = 14,
	name = "Chaos Necromancer",
	type = "Hostile Special Enemy",
	triggerSpawn = "Spawns Round 2+ when >50% enemies defeated",
	behaviorEffect = "Turns enemy corpses into random undead. Highest-level resurrected becomes Elite Undead.",
}

BattlefieldEventData.Events["Fortune Teller"] = {
	id = 15,
	name = "Fortune Teller",
	type = "Neutral NPC",
	triggerSpawn = "Random spawn",
	behaviorEffect = "Interacting allows player to choose the upcoming Weather/Crisis Event.",
}

BattlefieldEventData.Events["Lost Noble"] = {
	id = 16,
	name = "Lost Noble",
	type = "Neutral NPC",
	triggerSpawn = "Random spawn",
	behaviorEffect = "Enemies prioritize attacking it. If it survives battle, Rare-or-better item added to loot pool.",
}

BattlefieldEventData.Events["Treasure Hunter"] = {
	id = 17,
	name = "Treasure Hunter",
	type = "Neutral NPC",
	triggerSpawn = "Random spawn",
	behaviorEffect = "Seeks closest treasure/hidden treasure tile. Spends 1 turn unlocking, 1 turn removing. Continues searching.",
}

BattlefieldEventData.Events["Wandering Monster"] = {
	id = 18,
	name = "Wandering Monster",
	type = "Neutral → Hostile",
	triggerSpawn = "Random spawn",
	behaviorEffect = "Level 5-10 above highest friendly. Neutral until attacked by friendly. Enemies ignore it. Defeating guarantees Rare+ loot.",
}

BattlefieldEventData.Events["Vengeful Spirit"] = {
	id = 19,
	name = "Vengeful Spirit",
	type = "Special Enemy",
	triggerSpawn = "Spawns from map edge",
	behaviorEffect = "Seeks a monster. Interacting with one makes it Elite and sets level to highest friendly +10.",
}

BattlefieldEventData.Events["Bounty Hunter"] = {
	id = 20,
	name = "Bounty Hunter",
	type = "Hostile",
	triggerSpawn = "Random spawn",
	behaviorEffect = "High-level unit that targets one friendly unit. Immune to Taunt.",
}

BattlefieldEventData.Events["Monster Hunter"] = {
	id = 21,
	name = "Monster Hunter",
	type = "Neutral NPC",
	triggerSpawn = "Random spawn",
	behaviorEffect = "Hunts monsters. Spawns visible traps every turn.",
}

BattlefieldEventData.Events["Wandering Bandits"] = {
	id = 22,
	name = "Wandering Bandits",
	type = "Neutral → Hostile",
	triggerSpawn = "Random spawn",
	behaviorEffect = "Demand gold. Paying = leave peacefully. Refusing or attacking = hostile.",
}

BattlefieldEventData.Events["Plague Carrier"] = {
	id = 23,
	name = "Plague Carrier",
	type = "Hostile / Battlefield Hazard",
	triggerSpawn = "Random spawn",
	behaviorEffect = "Every tile crossed becomes Corrupted Tile + spawns Poison Gas.",
}

BattlefieldEventData.Events["Traitor"] = {
	id = 24,
	name = "Traitor",
	type = "Enemy → Friendly",
	triggerSpawn = "Enemy spawns with Traitor debuff",
	behaviorEffect = "Enemy while debuff active. When ≤25% original enemies alive, becomes neutral ally and dispels Traitor.",
}

BattlefieldEventData.Events["Enemy Scout"] = {
	id = 25,
	name = "Enemy Scout",
	type = "Hostile",
	triggerSpawn = "Random spawn",
	behaviorEffect = "Must defeat before end of Round 2 or enemy gets reinforcements.",
}

BattlefieldEventData.Events["Doppelganger"] = {
	id = 26,
	name = "Doppelganger",
	type = "Hostile",
	triggerSpawn = "Random spawn",
	behaviorEffect = "Copies a friendly unit. Copied items can't be stolen. Defeating grants 5× EXP.",
}

BattlefieldEventData.Events["Chaos Lich"] = {
	id = 27,
	name = "Chaos Lich",
	type = "Hostile Special Enemy",
	triggerSpawn = "Rare/random spawn",
	behaviorEffect = "Casts Death Ripple every turn hitting all non-undead. Undead unaffected.",
}

BattlefieldEventData.Events["Fog Spirit"] = {
	id = 28,
	name = "Fog Spirit",
	type = "Hostile / Battlefield Hazard",
	triggerSpawn = "Random spawn",
	behaviorEffect = "Creates Fog on every tile it crosses.",
}

BattlefieldEventData.Events["Fire Spirit"] = {
	id = 29,
	name = "Fire Spirit",
	type = "Hostile / Battlefield Hazard",
	triggerSpawn = "Random spawn",
	behaviorEffect = "Burns every tile it crosses.",
}

BattlefieldEventData.Events["Wind Spirit"] = {
	id = 30,
	name = "Wind Spirit",
	type = "Hostile / Battlefield Modifier",
	triggerSpawn = "Random spawn",
	behaviorEffect = "While alive, flying effects and Flying race are disabled.",
}

BattlefieldEventData.Events["Water Spirit"] = {
	id = 31,
	name = "Water Spirit",
	type = "Hostile / Battlefield Transformation",
	triggerSpawn = "Random spawn",
	behaviorEffect = "Each turn, lowest-elevation non-water tiles become Shallow Water; Water tiles become Deep Water. Elevation rises progressively. Stops when defeated or all tiles Deep Water.",
}

BattlefieldEventData.Events["Lightning Elemental"] = {
	id = 32,
	name = "Lightning Elemental",
	type = "Hostile",
	triggerSpawn = "Random spawn",
	behaviorEffect = "Every turn attacks the unit on highest elevation, regardless of range.",
}

BattlefieldEventData.Events["Earth Elemental"] = {
	id = 33,
	name = "Earth Elemental",
	type = "Hostile / Crisis Generator",
	triggerSpawn = "Random spawn (not during Earthquake Crisis)",
	behaviorEffect = "Triggers Earthquake Crisis effect every turn. Earthquake Crisis can't occur while it exists.",
}

BattlefieldEventData.Events["Gold Golem"] = {
	id = 34,
	name = "Gold Golem",
	type = "Rare Hostile",
	triggerSpawn = "Rare spawn",
	behaviorEffect = "Defeating yields 5× normal gold reward.",
}

BattlefieldEventData.Events["Crystal Golem"] = {
	id = 35,
	name = "Crystal Golem",
	type = "Rare Hostile",
	triggerSpawn = "Rare spawn",
	behaviorEffect = "Defeating yields 5× normal material reward.",
}

function BattlefieldEventData.GetByName(name: string)
	return BattlefieldEventData.Events[name]
end

function BattlefieldEventData.GetAllNames(): {string}
	local copy = {}
	for i, n in ipairs(BattlefieldEventData.Order) do copy[i] = n end
	return copy
end

return BattlefieldEventData
