-- RaceData.lua
-- Auto-generated Content Registry: Races (15 entries)
-- Do not edit manually. Regenerate from CTRBLXAI.db.

local RaceData = {}

-- Race definitions
RaceData.Races = {
	["RACE-HUMAN"] = {
		name = "Human",
		tags = {},
		startingStats = {STR = 1, AGI = 1, INT = 1, VIT = 2, DEX = 1, LUK = 2},
		growthRates = {STR = 0.33, AGI = 0.33, INT = 0.33, VIT = 0.34, DEX = 0.33, LUK = 0.34},
		passiveName = "Adaptability",
		passiveEffect = "EXP gained +10%. Gain +1 allocable stat point every 3 levels.",
	},
	["RACE-ELF"] = {
		name = "Elf",
		tags = {},
		startingStats = {STR = 0, AGI = 1, INT = 3, VIT = 1, DEX = 2, LUK = 1},
		growthRates = {STR = 0.1, AGI = 0.3, INT = 1.0, VIT = 0.15, DEX = 0.3, LUK = 0.15},
		passiveName = "Elven Focus",
		passiveEffect = "Skill MP Cost -20%. Jump +1.",
	},
	["RACE-DWARF"] = {
		name = "Dwarf",
		tags = {},
		startingStats = {STR = 2, AGI = 0, INT = 0, VIT = 3, DEX = 2, LUK = 1},
		growthRates = {STR = 0.45, AGI = 0.1, INT = 0.1, VIT = 1.0, DEX = 0.25, LUK = 0.1},
		passiveName = "Stout Resilience",
		passiveEffect = "Direct Physical damage received -10%. Movement Range -1.",
	},
	["RACE-ORC"] = {
		name = "Orc",
		tags = {},
		startingStats = {STR = 3, AGI = 1, INT = 0, VIT = 3, DEX = 0, LUK = 1},
		growthRates = {STR = 1.0, AGI = 0.2, INT = 0.1, VIT = 0.5, DEX = 0.1, LUK = 0.1},
		passiveName = "Bloodlust",
		passiveEffect = "While below 50% HP, final damage +15%. INT -15%.",
	},
	["RACE-GOBLIN"] = {
		name = "Goblin",
		tags = {},
		startingStats = {STR = 1, AGI = 2, INT = 1, VIT = 1, DEX = 2, LUK = 1},
		growthRates = {STR = 0.2, AGI = 0.5, INT = 0.2, VIT = 0.2, DEX = 0.6, LUK = 0.3},
		passiveName = "Cunning",
		passiveEffect = "Basic Attacks apply Poison. Damage received from traps and hazards +10%.",
	},
	["RACE-MERMAID"] = {
		name = "Mermaid",
		tags = {"Amphibious"},
		startingStats = {STR = 0, AGI = 1, INT = 3, VIT = 1, DEX = 1, LUK = 2},
		growthRates = {STR = 0.1, AGI = 0.25, INT = 0.9, VIT = 0.2, DEX = 0.15, LUK = 0.4},
		passiveName = "Tidecaller",
		passiveEffect = "Range +1 while occupying Water, Wet, or Ice. All primary stats -10% while not occupying Water, Wet, or Ice.",
	},
	["RACE-FAIRY"] = {
		name = "Fairy",
		tags = {"Flying"},
		startingStats = {STR = 0, AGI = 2, INT = 2, VIT = 0, DEX = 2, LUK = 2},
		growthRates = {STR = 0.1, AGI = 0.6, INT = 0.5, VIT = 0.1, DEX = 0.4, LUK = 0.3},
		passiveName = "Fae Grace",
		passiveEffect = "AOE damage received -25%. STR -15%.",
	},
	["RACE-ZOMBIE"] = {
		name = "Zombie",
		tags = {"Undead"},
		startingStats = {STR = 2, AGI = 0, INT = 0, VIT = 3, DEX = 0, LUK = 3},
		growthRates = {STR = 0.4, AGI = 0.1, INT = 0.1, VIT = 1.0, DEX = 0.1, LUK = 0.3},
		passiveName = "Undying",
		passiveEffect = "Revive three turns after KO with 50% HP. Movement Range -1.",
	},
	["RACE-GOLEM"] = {
		name = "Golem",
		tags = {"Mechanical"},
		startingStats = {STR = 2, AGI = 0, INT = 1, VIT = 3, DEX = 1, LUK = 1},
		growthRates = {STR = 0.4, AGI = 0.1, INT = 0.2, VIT = 1.0, DEX = 0.2, LUK = 0.1},
		passiveName = "Fortified Frame",
		passiveEffect = "Guard mitigation +20%. Movement Range -1.",
	},
	["RACE-SHADOW"] = {
		name = "Shadow",
		tags = {},
		startingStats = {STR = 0, AGI = 3, INT = 1, VIT = 0, DEX = 3, LUK = 1},
		growthRates = {STR = 0.1, AGI = 0.7, INT = 0.2, VIT = 0.1, DEX = 0.7, LUK = 0.2},
		passiveName = "Umbral Veil",
		passiveEffect = "After receiving direct damage, gain Hide for one turn. Elemental damage received +10%.",
	},
	["RACE-VAMPIRE"] = {
		name = "Vampire",
		tags = {"Undead"},
		startingStats = {STR = 2, AGI = 1, INT = 2, VIT = 1, DEX = 1, LUK = 1},
		growthRates = {STR = 0.4, AGI = 0.2, INT = 0.4, VIT = 0.3, DEX = 0.2, LUK = 0.5},
		passiveName = "Vampirism",
		passiveEffect = "Heal for 15% of direct damage dealt, reduced to 5% for AOE damage. During day, all primary stats -25%. During night, all primary stats +25%.",
	},
	["RACE-ANDROID"] = {
		name = "Android",
		tags = {"Mechanical"},
		startingStats = {STR = 1, AGI = 1, INT = 2, VIT = 2, DEX = 2, LUK = 0},
		growthRates = {STR = 0.2, AGI = 0.2, INT = 0.5, VIT = 0.4, DEX = 0.6, LUK = 0.1},
		passiveName = "Extending Arms",
		passiveEffect = "Push Range +3. Push becomes Pull. Push cannot target adjacent units.",
	},
	["RACE-LICH"] = {
		name = "Lich",
		tags = {"Undead"},
		startingStats = {STR = 0, AGI = 0, INT = 3, VIT = 2, DEX = 1, LUK = 2},
		growthRates = {STR = 0.1, AGI = 0.1, INT = 1.0, VIT = 0.3, DEX = 0.1, LUK = 0.4},
		passiveName = "Arcane Corruption",
		passiveEffect = "Elemental Skill interactions remain authored as Fire to Burn, Water to Frozen, Earth to Petrify, and Dark to Poison. Light damage received +50%.",
	},
	["RACE-ELEMENTAL-SPIRIT"] = {
		name = "Elemental Spirit",
		tags = {},
		startingStats = {STR = 0, AGI = 2, INT = 3, VIT = 0, DEX = 1, LUK = 2},
		growthRates = {STR = 0.1, AGI = 0.4, INT = 1.0, VIT = 0.1, DEX = 0.1, LUK = 0.3},
		passiveName = "Elemental Flux",
		passiveEffect = "Elemental damage dealt +30%. Elemental damage received +30%.",
	},
	["RACE-TITAN"] = {
		name = "Titan",
		tags = {},
		startingStats = {STR = 3, AGI = 0, INT = 0, VIT = 3, DEX = 0, LUK = 2},
		growthRates = {STR = 1.0, AGI = 0.1, INT = 0.1, VIT = 0.6, DEX = 0.1, LUK = 0.1},
		passiveName = "Colossal Arsenal",
		passiveEffect = "Titan may equip normally 2H melee weapon as 1H main-hand with off-hand slot. See Colossal Arsenal rules below.",
	},
}

-- Race tags (structural, non-breakable)
RaceData.Tags = {
	["Undead"] = {
		benefits = "Dark-tagged damage heals instead of damages. Immune to Poison, Venom, Bleed, Raptured, and Wounded.",
		drawbacks = "Holy damage x2. Healing from any non-Dark source is converted into damage instead of healing.",
	},
	["Mechanical"] = {
		benefits = "Immune to Poison, Venom, Bleed, Raptured, Wounded, and Hunger Virus HP drain.",
		drawbacks = "Raw Weapon WT +15%. Wet penalties are doubled.",
	},
	["Amphibious"] = {
		benefits = "Ignore Shallow Water and Deep Water movement penalties. Immune to Drowning.",
		drawbacks = "At start of turn, if not on Shallow Water, Deep Water, Ice, or Wet tile, apply Movement Range -1 until next turn.",
	},
	["Flying"] = {
		benefits = "Grants permanent Flight using complete Manual Flight benefits and drawbacks.",
		drawbacks = "No separate values invented.",
	},
}

-- Lookup by race ID
function RaceData.GetRace(raceId)
	return RaceData.Races[raceId]
end

-- Lookup by name (case-sensitive)
function RaceData.GetByName(name)
	for id, race in pairs(RaceData.Races) do
		if race.name == name then return race, id end
	end
	return nil
end

-- Get all race IDs (sorted for determinism)
function RaceData.GetAllIds()
	local ids = {}
	for id in pairs(RaceData.Races) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- Calculate base stats for a race at a given level
-- Formula: stat = startingStat + floor(growthRate × (level - 1))
function RaceData.CalcBaseStats(raceId, level)
	local race = RaceData.Races[raceId]
	if not race then return nil end
	local stats = {}
	for _, stat in ipairs({"STR", "AGI", "INT", "VIT", "DEX", "LUK"}) do
		stats[stat] = race.startingStats[stat] + math.floor(race.growthRates[stat] * (level - 1))
	end
	return stats
end

return RaceData
